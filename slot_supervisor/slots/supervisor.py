"""The contract: request, check, reset, release, list, reap.

The supervisor keeps no record of its own. Every call rebuilds the picture
from the labels on what is actually running.
"""
from __future__ import annotations

import json
import os
import re
from dataclasses import dataclass
from datetime import datetime, timezone
from typing import Callable, Dict, List, Optional, Tuple

from .config import ADMIN, Settings
from .errors import Forbidden, Invalid, NotFound, ProjectCapReached, RuntimeFailed, ServerLimitReached, SlotError
from .runtime import ENV_FILE_NAME, OVERRIDE_FILE_NAME, Runtime
from .templates import COMPOSE_FILE_NAME, ROUTED_PORT, Template, format_database, load_template

PROJECT_RE = re.compile(r"^[a-z][a-z0-9]*(-[a-z0-9]+)*$")
NUMBER_RE = re.compile(r"^[1-9][0-9]*$")
MAX_DNS_LABEL = 63  # a slot name is the first label of the slot's host name
TEXT_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9 ._:#/@-]{0,99}$")
TIME_FORMAT = "%Y-%m-%dT%H:%M:%SZ"
LABEL_PREFIX = "slots."


def utc_now() -> datetime:
    return datetime.now(timezone.utc)


def _format_time(moment: datetime) -> str:
    return moment.astimezone(timezone.utc).strftime(TIME_FORMAT)


def _parse_time(text: str) -> datetime:
    return datetime.strptime(text, TIME_FORMAT).replace(tzinfo=timezone.utc)


def parse_slot_name(name: str) -> Tuple[str, int]:
    project, _, number = name.rpartition("-") if isinstance(name, str) else ("", "", "")
    if not PROJECT_RE.match(project) or not NUMBER_RE.match(number):
        raise Invalid("a slot name is <project>-<number>, got %r" % (name,))
    # PROJECT_RE and NUMBER_RE leave only lower-case letters, digits and inner hyphens.
    if len(name) > MAX_DNS_LABEL:
        raise Invalid("a slot name is part of a host name, so at most %d characters; %r has %d"
                      % (MAX_DNS_LABEL, name, len(name)))
    return project, int(number)


@dataclass(frozen=True)
class Slot:
    """One running slot, exactly as its container labels describe it."""
    project: str
    number: int
    ticket: str
    agent: str
    started_at: datetime
    expires_at: datetime
    ports: Dict[str, int]
    env: Dict[str, str]
    deploy_user: str
    health_path: str
    database: str  # "" when the template names none

    @property
    def name(self) -> str:
        return "%s-%d" % (self.project, self.number)

    def to_labels(self) -> Dict[str, str]:
        values = {
            "slot": self.name, "project": self.project, "number": str(self.number),
            "ticket": self.ticket, "agent": self.agent,
            "started_at": _format_time(self.started_at), "expires_at": _format_time(self.expires_at),
            "ports": json.dumps(self.ports, sort_keys=True), "env": json.dumps(self.env, sort_keys=True),
            "deploy_user": self.deploy_user, "health_path": self.health_path, "database": self.database,
        }
        return {LABEL_PREFIX + key: value for key, value in values.items()}

    @classmethod
    def from_labels(cls, labels: Dict[str, str]) -> "Slot":
        try:
            get = lambda key: labels[LABEL_PREFIX + key]  # noqa: E731
            return cls(
                project=get("project"), number=int(get("number")), ticket=get("ticket"), agent=get("agent"),
                started_at=_parse_time(get("started_at")), expires_at=_parse_time(get("expires_at")),
                ports=json.loads(get("ports")), env=json.loads(get("env")),
                deploy_user=get("deploy_user"), health_path=get("health_path"), database=get("database"),
            )
        except (KeyError, ValueError) as exc:
            raise RuntimeFailed("a running project carries broken slot labels (%s): %r"
                                % (exc, labels.get(LABEL_PREFIX + "slot")))


class Supervisor:
    def __init__(self, settings: Settings, runtime: Runtime, clock: Callable[[], datetime] = utc_now):
        self.settings = settings
        self.runtime = runtime
        self.clock = clock

    # -- the six verbs ---------------------------------------------------------

    def request(self, project: str, ticket: str, agent: str, scope: str = ADMIN) -> dict:
        if not isinstance(project, str) or not PROJECT_RE.match(project):
            raise Invalid("project must be a lower-case name such as 'thankmu', got %r" % (project,))
        _check_text("ticket", ticket)
        _check_text("agent", agent)
        _authorize(scope, project)
        with self.runtime.lock():
            self._reap()
            slots = self._running()
            for slot in slots:
                if slot.project == project and slot.ticket == ticket:
                    return dict(self._describe(slot, detail=True), created=False)
            template = load_template(self.settings.templates_dir, project)
            parse_slot_name("%s-%d" % (project, template.cap))  # every name this project can get
            taken = {slot.number for slot in slots if slot.project == project}
            if len(taken) >= template.cap:
                raise ProjectCapReached("project %s already runs its cap of %d slots" % (project, template.cap))
            if len(slots) >= self.settings.max_running:
                raise ServerLimitReached("this server already runs its limit of %d slots"
                                         % self.settings.max_running)
            number = min(n for n in range(1, template.cap + 1) if n not in taken)
            slot = self._new_slot(template, number, ticket, agent, slots)
            self._start(slot, template)
            return dict(self._describe(slot, detail=True), created=True)

    def check(self, name: str, scope: str = ADMIN) -> dict:
        project, number = parse_slot_name(name)
        _authorize(scope, project)
        slot = self._find(name)
        if slot is not None:
            return self._describe(slot, detail=True)
        template = load_template(self.settings.templates_dir, project)
        if number > template.cap:
            raise NotFound("project %s has slots 1 to %d; %s does not exist" % (project, template.cap, name))
        return {"slot": name, "project": project, "number": number, "state": "stopped",
                "ticket": None, "agent": None, "started_at": None, "expires_at": None}

    def reset(self, name: str, scope: str = ADMIN) -> dict:
        project, _ = parse_slot_name(name)
        _authorize(scope, project)
        with self.runtime.lock():
            slot = self._find(name)
            if slot is None:
                raise NotFound("slot %s is not running; request one instead" % name)
            template = load_template(self.settings.templates_dir, project)
            # Same labels go back on, so the start time and the expiry do not move.
            self.runtime.stop(name, self._slot_dir(name))
            self._start(slot, template)
            return self._describe(slot, detail=True)

    def release(self, name: str, scope: str = ADMIN) -> None:
        project, _ = parse_slot_name(name)
        _authorize(scope, project)
        with self.runtime.lock():
            if self._find(name) is not None:
                self._stop(name)

    def list(self, scope: str = ADMIN, project: Optional[str] = None) -> dict:
        if project is not None:
            _authorize(scope, project)
        slots = [slot for slot in self._running()
                 if (scope == ADMIN or slot.project == scope) and (project is None or slot.project == project)]
        return {"now": _format_time(self.clock()), "max_running": self.settings.max_running,
                "slots": [self._describe(slot, detail=False) for slot in slots]}

    def reap(self, scope: str = ADMIN) -> dict:
        if scope != ADMIN:
            raise Forbidden("only the admin token may reap")
        with self.runtime.lock():
            return self._reap()

    # -- internals -------------------------------------------------------------

    def _running(self) -> List[Slot]:
        slots = [Slot.from_labels(labels) for labels in self.runtime.list_running()]
        return sorted(slots, key=lambda slot: (slot.project, slot.number))

    def _find(self, name: str) -> Optional[Slot]:
        for slot in self._running():
            if slot.name == name:
                return slot
        return None

    def _slot_dir(self, name: str) -> str:
        return os.path.join(self.settings.work_dir, name)

    def _reap(self) -> dict:
        now, stopped, failed = self.clock(), [], []
        for slot in self._running():
            if slot.expires_at <= now:
                try:
                    self._stop(slot.name)
                    stopped.append(slot.name)
                except SlotError as exc:
                    failed.append({"slot": slot.name, "error": str(exc)})
        return {"stopped": stopped, "failed": failed}

    def _stop(self, name: str) -> None:
        self.runtime.stop(name, self._slot_dir(name))
        self.runtime.remove_route(name)

    def _new_slot(self, template: Template, number: int, ticket: str, agent: str, running: List[Slot]) -> Slot:
        used = {port for slot in running for port in slot.ports.values()}
        free = (p for p in range(self.settings.port_low, self.settings.port_high + 1) if p not in used)
        ports = {}
        for port_name in template.ports:
            port = next(free, None)
            if port is None:
                raise ServerLimitReached("no free port left in %d-%d"
                                         % (self.settings.port_low, self.settings.port_high))
            ports[port_name] = port
        name = "%s-%d" % (template.project, number)
        slot_dir = self._slot_dir(name)
        compose_files = [os.path.join(template.directory, COMPOSE_FILE_NAME),
                         os.path.join(slot_dir, OVERRIDE_FILE_NAME)]
        env = {
            "COMPOSE_PROJECT_NAME": name,
            "COMPOSE_FILE": os.pathsep.join(compose_files),
            "SLOT_NAME": name,
            "SLOT_PROJECT": template.project,
            "SLOT_NUMBER": str(number),
            "SLOT_HOST": self._host(name),
            "SLOT_URL": self._url(name),
            "SLOT_INTERNAL_PORT": str(template.internal_port),
            "SLOT_UPSTREAM_HOST": self.settings.upstream_host,
            "SLOT_TEMPLATE_DIR": template.directory,
            "SLOT_DIR": slot_dir,
        }
        env.update({"SLOT_PORT_" + key.upper(): str(port) for key, port in ports.items()})
        database = ""
        if template.database is not None:
            database = format_database(template.database, self.settings.ssh_host, name, ports)
        started = self.clock().replace(microsecond=0)
        return Slot(project=template.project, number=number, ticket=ticket, agent=agent,
                    started_at=started, expires_at=started + self.settings.ttl, ports=ports, env=env,
                    deploy_user=template.deploy_user, health_path=template.health_path, database=database)

    def _start(self, slot: Slot, template: Template) -> None:
        """Start, seed, route. A slot that fails half way is taken down again."""
        try:
            self.runtime.start(slot.name, template.directory, self._slot_dir(slot.name), slot.env, slot.to_labels())
            self.runtime.seed(slot.name, template.directory, template.seed_command, slot.env)
            self.runtime.write_route(slot.name, self._host(slot.name), slot.ports[ROUTED_PORT])
        except Exception as failure:
            try:
                if any(labels.get(LABEL_PREFIX + "slot") == slot.name for labels in self.runtime.list_running()):
                    self.runtime.stop(slot.name, self._slot_dir(slot.name))
                self.runtime.remove_route(slot.name)
            except Exception as second:
                raise RuntimeFailed("starting %s failed (%s) and so did cleaning up after it (%s)"
                                    % (slot.name, failure, second)) from failure
            raise

    def _host(self, name: str) -> str:
        return "%s.%s" % (name, self.settings.host)

    def _url(self, name: str) -> str:
        return "https://%s/" % self._host(name)

    def _describe(self, slot: Slot, detail: bool) -> dict:
        out = {
            "slot": slot.name, "project": slot.project, "number": slot.number, "state": "running",
            "ticket": slot.ticket, "agent": slot.agent,
            "started_at": _format_time(slot.started_at), "expires_at": _format_time(slot.expires_at),
            "expired": slot.expires_at <= self.clock(),
            "url": self._url(slot.name), "ports": slot.ports,
        }
        if not detail:
            return out
        slot_dir = self._slot_dir(slot.name)
        health_url = "http://%s:%d%s" % (self.settings.upstream_host, slot.ports[ROUTED_PORT], slot.health_path)
        out["health"] = self.runtime.health(slot.name, health_url)
        out["deploy"] = {
            "host": self.settings.ssh_host, "user": slot.deploy_user, "directory": slot_dir,
            "compose_project": slot.name,
            "env_file": os.path.join(slot_dir, ENV_FILE_NAME),
            "compose_files": slot.env["COMPOSE_FILE"].split(os.pathsep),
            "env": slot.env,
        }
        out["database"] = slot.database or None
        out["logs"] = "docker compose -p %s logs" % slot.name
        return out


def _check_text(field: str, value) -> None:
    if not isinstance(value, str) or not TEXT_RE.match(value):
        raise Invalid("%s must be 1 to 100 letters, digits, spaces or . _ : # / @ -, got %r" % (field, value))


def _authorize(scope: str, project: str) -> None:
    if scope != ADMIN and scope != project:
        raise Forbidden("this token reaches project %s only, not %s" % (scope, project))
