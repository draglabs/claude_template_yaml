"""Shared test setup: temp templates on disk, the fake runtime, a clock we can move."""
import json
import os
import shutil
import sys
import tempfile
import unittest
from datetime import datetime, timedelta, timezone

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from slots.config import Settings  # noqa: E402
from slots.fake_runtime import FakeRuntime  # noqa: E402
from slots.supervisor import Supervisor  # noqa: E402

TEMPLATE = {
    "cap": 2,
    "ports": ["app", "db"],
    "internal_port": 3000,
    "health_path": "/healthz",
    "seed_command": ["sh", "seed.sh"],
    "deploy_user": "deploy",
    "database": "postgres://app:app@{host}:{port_db}/app",
}


class Clock:
    def __init__(self):
        self.now = datetime(2026, 11, 23, 9, 0, 0, tzinfo=timezone.utc)

    def __call__(self):
        return self.now

    def forward(self, **kwargs):
        self.now += timedelta(**kwargs)


def write_template(root, project, **changes):
    directory = os.path.join(root, project)
    os.makedirs(directory, exist_ok=True)
    with open(os.path.join(directory, "compose.yaml"), "w") as handle:
        handle.write("services: {}\n")
    with open(os.path.join(directory, "slot.json"), "w") as handle:
        json.dump(dict(TEMPLATE, **changes), handle)
    return directory


class SupervisorCase(unittest.TestCase):
    max_running = 3

    def setUp(self):
        self.tmp = tempfile.mkdtemp()
        self.addCleanup(shutil.rmtree, self.tmp)
        self.templates = os.path.join(self.tmp, "templates")
        write_template(self.templates, "alpha")
        write_template(self.templates, "beta")
        self.settings = Settings(
            host="slots.test", ssh_host="ssh.slots.test", upstream_host="upstream.test",
            templates_dir=self.templates, work_dir=os.path.join(self.tmp, "work"),
            routes_dir=os.path.join(self.tmp, "routes"), port_low=20000, port_high=20009,
            max_running=self.max_running, proxy_reload_command=["reload-proxy"],
            ttl=timedelta(hours=8), command_timeout=5,
        )
        self.runtime = FakeRuntime()
        self.clock = Clock()
        self.supervisor = Supervisor(self.settings, self.runtime, self.clock)
