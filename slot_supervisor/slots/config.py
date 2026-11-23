"""Settings from SLOTS_* environment variables, and the tokens file."""
from __future__ import annotations

import hmac
import json
import os
import shlex
import stat
from dataclasses import dataclass
from datetime import timedelta
from typing import Dict, List, Mapping, Optional, Tuple

from .errors import ConfigError

PREFIX = "SLOTS_"
ADMIN = "*"  # the scope of the admin token and of the local CLI

# The owner's decision: a slot lives a fixed 8 hours from start.
DEFAULT_TTL_HOURS = 8
DEFAULT_COMMAND_TIMEOUT_SECONDS = 600


def _required(env: Mapping[str, str], key: str) -> str:
    value = env.get(PREFIX + key, "").strip()
    if not value:
        raise ConfigError("missing required setting %s%s" % (PREFIX, key))
    return value


def _positive_int(name: str, value: str) -> int:
    try:
        number = int(value)
    except ValueError:
        raise ConfigError("%s%s must be a whole number, got %r" % (PREFIX, name, value))
    if number <= 0:
        raise ConfigError("%s%s must be above zero, got %r" % (PREFIX, name, value))
    return number


def _optional_int(env: Mapping[str, str], key: str, default: int) -> int:
    value = env.get(PREFIX + key, "").strip()
    return _positive_int(key, value) if value else default


@dataclass(frozen=True)
class Settings:
    host: str                 # public name: a slot is at https://<slot>.<host>/
    ssh_host: str             # where a developer logs in to deploy
    upstream_host: str        # where the proxy and health check reach a slot's ports
    templates_dir: str        # <templates_dir>/<project>/{compose.yaml,slot.json}
    work_dir: str             # <work_dir>/<slot>/ exists only while the slot runs
    routes_dir: str           # one Caddy site block per running slot
    port_low: int
    port_high: int
    max_running: int          # limit on running slots for this server
    proxy_reload_command: List[str]
    ttl: timedelta
    command_timeout: int

    @classmethod
    def from_env(cls, env: Mapping[str, str]) -> "Settings":
        host = _required(env, "HOST")
        port_range = _required(env, "PORT_RANGE")
        low, sep, high = port_range.partition("-")
        if not sep:
            raise ConfigError("%sPORT_RANGE must look like 20000-20999, got %r" % (PREFIX, port_range))
        port_low, port_high = _positive_int("PORT_RANGE", low), _positive_int("PORT_RANGE", high)
        if port_low > port_high:
            raise ConfigError("%sPORT_RANGE is empty: %r" % (PREFIX, port_range))
        return cls(
            host=host,
            ssh_host=env.get(PREFIX + "SSH_HOST", "").strip() or host,
            upstream_host=_required(env, "UPSTREAM_HOST"),
            templates_dir=_required(env, "TEMPLATES_DIR"),
            work_dir=_required(env, "WORK_DIR"),
            routes_dir=_required(env, "ROUTES_DIR"),
            port_low=port_low,
            port_high=port_high,
            max_running=_positive_int("MAX_RUNNING", _required(env, "MAX_RUNNING")),
            proxy_reload_command=shlex.split(_required(env, "PROXY_RELOAD_COMMAND")),
            ttl=timedelta(hours=_optional_int(env, "TTL_HOURS", DEFAULT_TTL_HOURS)),
            command_timeout=_optional_int(env, "COMMAND_TIMEOUT_SECONDS", DEFAULT_COMMAND_TIMEOUT_SECONDS),
        )


def serve_settings(env: Mapping[str, str]) -> Tuple[str, int, str]:
    """What only `slot serve` needs: (listen host, listen port, tokens file)."""
    listen = _required(env, "LISTEN")
    host, sep, port = listen.rpartition(":")
    if not sep or not host:
        raise ConfigError("%sLISTEN must look like <host>:<port>, got %r" % (PREFIX, listen))
    return host, _positive_int("LISTEN", port), _required(env, "TOKENS_FILE")


class Tokens:
    """Maps a bearer token to a scope: one project, or ADMIN."""

    def __init__(self, admin: str, projects: Dict[str, str]):
        self._by_scope = dict(projects)
        self._by_scope[ADMIN] = admin
        values = list(self._by_scope.values())
        if any(not isinstance(v, str) or len(v) < 16 for v in values):
            raise ConfigError("every token must be a string of at least 16 characters")
        if len(set(values)) != len(values):
            raise ConfigError("two scopes share one token; every token must be different")

    @classmethod
    def load(cls, path: str) -> "Tokens":
        try:
            mode = os.stat(path).st_mode
        except OSError as exc:
            raise ConfigError("cannot read tokens file %s: %s" % (path, exc.strerror))
        if mode & (stat.S_IRWXG | stat.S_IRWXO):
            raise ConfigError("tokens file %s must be readable by its owner only (chmod 600)" % path)
        try:
            with open(path, encoding="utf-8") as handle:
                data = json.load(handle)
        except ValueError:
            # Say nothing about the content: it holds secrets.
            raise ConfigError("tokens file %s is not valid JSON" % path)
        if not isinstance(data, dict) or set(data) != {"admin", "projects"} or not isinstance(data["projects"], dict):
            raise ConfigError('tokens file %s must be {"admin": "...", "projects": {"<project>": "..."}}' % path)
        return cls(data["admin"], data["projects"])

    def scope_for(self, presented: str) -> Optional[str]:
        found = None
        for scope, token in self._by_scope.items():
            if hmac.compare_digest(token.encode(), presented.encode()):
                found = scope
        return found
