"""An in-memory runtime for tests. Starts nothing."""
from __future__ import annotations

import threading
from typing import Dict, List

from .errors import RuntimeFailed
from .runtime import Runtime


class FakeRuntime(Runtime):
    def __init__(self):
        self.projects: Dict[str, dict] = {}   # name -> {"labels", "env", "template_dir", "slot_dir"}
        self.routes: Dict[str, dict] = {}     # name -> {"host", "port"}
        self.events: List[tuple] = []         # ("start"|"seed"|"stop"|"route"|"unroute", name)
        self.unhealthy = set()                # names whose health check fails
        self.fail_seed = False
        self._lock = threading.RLock()

    def lock(self):
        return self._lock

    def start(self, name, template_dir, slot_dir, env, labels):
        if name in self.projects:
            raise RuntimeFailed("fake: project %s is already running" % name)
        self.projects[name] = {"labels": dict(labels), "env": dict(env),
                               "template_dir": template_dir, "slot_dir": slot_dir}
        self.events.append(("start", name))

    def stop(self, name, slot_dir):
        if name not in self.projects:
            raise RuntimeFailed("fake: project %s is not running" % name)
        del self.projects[name]
        self.events.append(("stop", name))

    def list_running(self):
        return [dict(p["labels"]) for p in self.projects.values()]

    def seed(self, name, template_dir, command, env):
        if self.fail_seed:
            raise RuntimeFailed("fake: seed failed")
        self.events.append(("seed", name))

    def health(self, name, url):
        ok = name in self.projects and name not in self.unhealthy
        return {"ok": ok, "detail": "fake: %s" % url}

    def write_route(self, name, host, port):
        self.routes[name] = {"host": host, "port": port}
        self.events.append(("route", name))

    def remove_route(self, name):
        self.routes.pop(name, None)
        self.events.append(("unroute", name))
