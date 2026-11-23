"""The real runtime with its command runner replaced. Docker is never called."""
import json
import os

from helpers import SupervisorCase, write_template
from slots.docker_runtime import DockerRuntime, render_route
from slots.errors import RuntimeFailed
from slots.supervisor import Supervisor


class Recorder:
    """Stands in for subprocess: records each command and plays back canned output."""

    def __init__(self):
        self.calls = []
        self.containers = []  # what `docker inspect` returns
        self.fail = None      # a word; a command containing it fails

    def __call__(self, argv, env, cwd, timeout):
        self.calls.append(argv)
        if self.fail and self.fail in argv:
            return 1, "", "boom"
        if argv[-2:] == ["config", "--services"]:
            return 0, "db\napp\n", ""
        if argv[:3] == ["docker", "ps", "-aq"]:
            return 0, "".join("id%d\n" % n for n in range(len(self.containers))), ""
        if argv[:2] == ["docker", "inspect"]:
            return 0, json.dumps(self.containers), ""
        if argv[:3] == ["docker", "ps", "-a"]:
            return 0, "running\nrunning\n", ""
        return 0, "", ""


class DockerRuntimeTests(SupervisorCase):
    def setUp(self):
        super().setUp()
        os.makedirs(self.settings.work_dir)
        os.makedirs(self.settings.routes_dir)
        write_template(self.templates, "alpha", database="postgres://app:pa$$@{host}:{port_db}/app")
        self.run = Recorder()
        self.docker = DockerRuntime(self.settings, run=self.run, http_status=lambda url: (200, ""))
        self.supervisor = Supervisor(self.settings, self.docker, self.clock)
        self.slot_dir = os.path.join(self.settings.work_dir, "alpha-1")
        self.route = os.path.join(self.settings.routes_dir, "alpha-1.caddy")

    def start(self):
        slot = self.supervisor.request("alpha", "T-1", "dev-agent")
        with open(os.path.join(self.slot_dir, "compose.slot.json")) as handle:
            override = json.load(handle)
        # What docker would report back: the labels, with "$$" read as "$".
        labels = {k: v.replace("$$", "$") for k, v in override["services"]["db"]["labels"].items()}
        labels["com.docker.compose.project"] = "alpha-1"
        self.run.containers = [{"Config": {"Labels": labels}}, {"Config": {"Labels": labels}}]
        return slot, override

    def test_start_writes_files_and_runs_compose(self):
        slot, override = self.start()
        compose = os.path.join(self.templates, "alpha", "compose.yaml")
        env_file = os.path.join(self.slot_dir, ".env")
        base = ["docker", "compose", "--env-file", env_file, "-p", "alpha-1", "-f", compose]
        calls = [call for call in self.run.calls if call[:2] != ["docker", "ps"]]
        self.assertEqual(calls, [
            base + ["config", "--services"],
            base + ["-f", os.path.join(self.slot_dir, "compose.slot.json"), "up", "-d", "--wait"],
            ["sh", "seed.sh"],
            ["reload-proxy"],
        ])
        self.assertEqual(sorted(override["services"]), ["app", "db"])
        labels = override["services"]["app"]["labels"]
        self.assertEqual((labels["slots.slot"], labels["slots.ticket"]), ("alpha-1", "T-1"))
        self.assertIn("pa$$$$@", labels["slots.database"])
        with open(env_file) as handle:
            env = handle.read()
        self.assertIn("SLOT_PORT_APP=20000\n", env)
        self.assertIn("COMPOSE_PROJECT_NAME=alpha-1\n", env)
        with open(self.route) as handle:
            self.assertIn("reverse_proxy upstream.test:20000", handle.read())
        self.assertEqual(slot["deploy"]["compose_files"], [compose, os.path.join(self.slot_dir, "compose.slot.json")])

    def test_the_picture_comes_back_from_container_labels(self):
        slot, _ = self.start()
        restarted = Supervisor(self.settings, DockerRuntime(self.settings, run=self.run,
                                                            http_status=lambda url: (200, "")), self.clock)
        checked = restarted.check("alpha-1")
        self.assertEqual(checked["ticket"], "T-1")
        self.assertEqual(checked["database"], "postgres://app:pa$$@ssh.slots.test:20001/app")
        self.assertEqual(checked["health"]["ok"], True)
        self.assertEqual(checked["deploy"], slot["deploy"])
        self.assertEqual(len(restarted.list()["slots"]), 1)

    def test_release_removes_containers_volumes_directory_and_route(self):
        self.start()
        self.run.calls.clear()
        self.supervisor.release("alpha-1")
        self.assertIn(["docker", "compose", "-p", "alpha-1", "down", "--volumes", "--remove-orphans"], self.run.calls)
        self.assertEqual(self.run.calls[-1], ["reload-proxy"])
        self.assertFalse(os.path.exists(self.slot_dir))
        self.assertFalse(os.path.exists(self.route))

    def test_a_failed_command_is_loud(self):
        self.run.fail = "up"
        with self.assertRaises(RuntimeFailed) as caught:
            self.supervisor.request("alpha", "T-1", "dev-agent")
        self.assertIn("boom", str(caught.exception))
        self.assertFalse(os.path.exists(self.route))

    def test_route_snippets(self):
        stripped = render_route("alpha-1", "upstream.test:20000", True)
        self.assertIn("handle_path /alpha-1/* {", stripped)
        self.assertIn("header_up X-Forwarded-Prefix /alpha-1", stripped)
        kept = render_route("alpha-1", "upstream.test:20000", False)
        self.assertIn("handle /alpha-1/* {", kept)
        self.assertNotIn("handle_path", kept)
        self.assertIn("redir /alpha-1 /alpha-1/ 308", kept)
