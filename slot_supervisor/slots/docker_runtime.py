"""The real runtime: `docker compose`, files under the work dir, Caddy route snippets."""
from __future__ import annotations

import contextlib
import fcntl
import json
import os
import shutil
import subprocess
import urllib.error
import urllib.request
from typing import Dict, List, Optional

from .config import Settings
from .errors import RuntimeFailed
from .runtime import ENV_FILE_NAME, OVERRIDE_FILE_NAME, Runtime
from .templates import COMPOSE_FILE_NAME

SLOT_LABEL = "slots.slot"
COMPOSE_PROJECT_LABEL = "com.docker.compose.project"
HEALTH_TIMEOUT_SECONDS = 5


def render_route(name: str, upstream: str, strip_prefix: bool) -> str:
    """The Caddy snippet for one slot. Imported inside the site block of the slots host."""
    lines = ["# Slot %s. Written by the slot supervisor; removed when the slot stops." % name,
             "redir /%s /%s/ 308" % (name, name)]
    if strip_prefix:
        lines += ["handle_path /%s/* {" % name,
                  "\treverse_proxy %s {" % upstream,
                  "\t\theader_up X-Forwarded-Prefix /%s" % name,
                  "\t}",
                  "}"]
    else:
        lines += ["handle /%s/* {" % name,
                  "\treverse_proxy %s" % upstream,
                  "}"]
    return "\n".join(lines) + "\n"


def _subprocess_run(argv, env, cwd, timeout):
    done = subprocess.run(argv, env=env, cwd=cwd, timeout=timeout, capture_output=True, text=True)
    return done.returncode, done.stdout, done.stderr


def _http_status(url):
    try:
        with urllib.request.urlopen(url, timeout=HEALTH_TIMEOUT_SECONDS) as response:
            return response.status, ""
    except urllib.error.HTTPError as exc:
        return exc.code, ""
    except (urllib.error.URLError, OSError) as exc:
        return None, str(exc)


class DockerRuntime(Runtime):
    def __init__(self, settings: Settings, run=_subprocess_run, http_status=_http_status):
        self.settings = settings
        self._run_command = run          # replaced in tests; never the real one there
        self._http_status = http_status

    # -- helpers ---------------------------------------------------------------

    def _run(self, argv: List[str], env: Optional[Dict[str, str]] = None, cwd: Optional[str] = None) -> str:
        full_env = dict(os.environ)
        full_env.update(env or {})
        try:
            code, out, err = self._run_command(argv, full_env, cwd, self.settings.command_timeout)
        except subprocess.TimeoutExpired:
            raise RuntimeFailed("timed out after %ss: %s" % (self.settings.command_timeout, " ".join(argv)))
        except OSError as exc:
            raise RuntimeFailed("cannot run %s: %s" % (argv[0], exc))
        if code != 0:
            raise RuntimeFailed("command failed (%s): %s\n%s" % (code, " ".join(argv), err.strip()[-2000:]))
        return out

    def _route_path(self, name: str) -> str:
        return os.path.join(self.settings.routes_dir, name + ".caddy")

    def _reload_proxy(self) -> None:
        self._run(self.settings.proxy_reload_command)

    # -- the interface ---------------------------------------------------------

    @contextlib.contextmanager
    def lock(self):
        path = os.path.join(self.settings.work_dir, ".lock")
        try:
            handle = open(path, "w")
        except OSError as exc:
            raise RuntimeFailed("cannot open lock file %s: %s" % (path, exc.strerror))
        with handle:
            fcntl.flock(handle, fcntl.LOCK_EX)
            yield

    def start(self, name, template_dir, slot_dir, env, labels):
        # A directory left by a crash belongs to no running slot, so it is rubbish.
        if os.path.exists(slot_dir):
            shutil.rmtree(slot_dir)
        os.makedirs(slot_dir)
        env_file = os.path.join(slot_dir, ENV_FILE_NAME)
        with open(env_file, "w", encoding="utf-8") as handle:
            handle.write("".join("%s=%s\n" % item for item in sorted(env.items())))
        compose_file = os.path.join(template_dir, COMPOSE_FILE_NAME)
        base = ["docker", "compose", "--env-file", env_file, "-p", name, "-f", compose_file]
        services = self._run(base + ["config", "--services"], env).split()
        if not services:
            raise RuntimeFailed("%s defines no services" % compose_file)
        # Compose reads "$" in a file as a variable, so "$$" keeps a literal one.
        escaped = {key: value.replace("$", "$$") for key, value in labels.items()}
        override = os.path.join(slot_dir, OVERRIDE_FILE_NAME)
        with open(override, "w", encoding="utf-8") as handle:
            json.dump({"services": {service: {"labels": escaped} for service in services}}, handle, indent=2)
        self._run(base + ["-f", override, "up", "-d", "--wait"], env)

    def stop(self, name, slot_dir):
        # By project name, not by file: the developer may have deployed other files.
        self._run(["docker", "compose", "-p", name, "down", "--volumes", "--remove-orphans"])
        volumes = self._run(["docker", "volume", "ls", "-q", "--filter",
                             "label=%s=%s" % (COMPOSE_PROJECT_LABEL, name)]).split()
        if volumes:
            self._run(["docker", "volume", "rm"] + volumes)
        if os.path.exists(slot_dir):
            shutil.rmtree(slot_dir)

    def list_running(self):
        ids = self._run(["docker", "ps", "-aq", "--filter", "label=" + SLOT_LABEL]).split()
        if not ids:
            return []
        projects: Dict[str, Dict[str, str]] = {}
        for container in json.loads(self._run(["docker", "inspect"] + ids)):
            labels = container["Config"]["Labels"]
            projects.setdefault(labels[SLOT_LABEL], {k: v for k, v in labels.items() if k.startswith("slots.")})
        return list(projects.values())

    def seed(self, name, template_dir, command, env):
        self._run(command, env, cwd=template_dir)

    def health(self, name, url):
        states = self._run(["docker", "ps", "-a", "--filter", "label=%s=%s" % (COMPOSE_PROJECT_LABEL, name),
                            "--format", "{{.State}}"]).split()
        running = states.count("running")
        status, error = self._http_status(url)
        answer = "HTTP %s" % status if status is not None else "no answer (%s)" % error
        ok = bool(states) and running == len(states) and status is not None and status < 400
        return {"ok": ok, "detail": "%d of %d containers running; %s: %s" % (running, len(states), url, answer)}

    def write_route(self, name, port, strip_prefix):
        path = self._route_path(name)
        upstream = "%s:%d" % (self.settings.upstream_host, port)
        with open(path + ".tmp", "w", encoding="utf-8") as handle:
            handle.write(render_route(name, upstream, strip_prefix))
        os.replace(path + ".tmp", path)
        self._reload_proxy()

    def remove_route(self, name):
        path = self._route_path(name)
        if os.path.exists(path):
            os.remove(path)
            self._reload_proxy()
