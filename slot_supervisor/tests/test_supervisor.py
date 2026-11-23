import os

from helpers import SupervisorCase, write_template
from slots.errors import Forbidden, Invalid, NotFound, ProjectCapReached, RuntimeFailed, ServerLimitReached
from slots.supervisor import Supervisor


class RequestTests(SupervisorCase):
    def test_request_starts_seeds_and_routes(self):
        slot = self.supervisor.request("alpha", "T-1", "dev-agent")
        self.assertEqual(self.runtime.events, [("start", "alpha-1"), ("seed", "alpha-1"), ("route", "alpha-1")])
        self.assertEqual(slot["slot"], "alpha-1")
        self.assertTrue(slot["created"])
        self.assertEqual(slot["state"], "running")
        self.assertEqual(slot["url"], "https://alpha-1.slots.test/")
        self.assertEqual((slot["ticket"], slot["agent"]), ("T-1", "dev-agent"))
        self.assertEqual(slot["started_at"], "2026-11-23T09:00:00Z")
        self.assertEqual(slot["expires_at"], "2026-11-23T17:00:00Z")
        self.assertEqual(slot["ports"], {"app": 20000, "db": 20001})
        self.assertEqual(slot["health"]["ok"], True)
        self.assertEqual(slot["database"], "postgres://app:app@ssh.slots.test:20001/app")
        self.assertEqual(slot["logs"], "docker compose -p alpha-1 logs")
        deploy = slot["deploy"]
        self.assertEqual((deploy["host"], deploy["user"]), ("ssh.slots.test", "deploy"))
        self.assertEqual(deploy["directory"], os.path.join(self.settings.work_dir, "alpha-1"))
        self.assertEqual(deploy["compose_project"], "alpha-1")
        self.assertEqual(deploy["env"]["SLOT_PORT_APP"], "20000")
        self.assertEqual(deploy["env"]["SLOT_HOST"], "alpha-1.slots.test")
        self.assertEqual(deploy["env"]["SLOT_URL"], "https://alpha-1.slots.test/")
        self.assertNotIn("SLOT_BASE_PATH", deploy["env"])
        self.assertNotIn("SLOT_STRIP_PREFIX", deploy["env"])
        self.assertEqual(deploy["env"]["SLOT_INTERNAL_PORT"], "3000")
        self.assertEqual(self.runtime.routes["alpha-1"], {"host": "alpha-1.slots.test", "port": 20000})

    def test_labels_carry_the_record(self):
        self.supervisor.request("alpha", "T-1", "dev-agent")
        labels = self.runtime.projects["alpha-1"]["labels"]
        self.assertEqual(labels["slots.project"], "alpha")
        self.assertEqual(labels["slots.number"], "1")
        self.assertEqual(labels["slots.ticket"], "T-1")
        self.assertEqual(labels["slots.agent"], "dev-agent")
        self.assertEqual(labels["slots.started_at"], "2026-11-23T09:00:00Z")

    def test_same_ticket_gets_the_same_slot(self):
        first = self.supervisor.request("alpha", "T-1", "dev-agent")
        self.clock.forward(hours=1)
        again = self.supervisor.request("alpha", "T-1", "another-agent")
        self.assertEqual(again["slot"], first["slot"])
        self.assertFalse(again["created"])
        self.assertEqual(again["expires_at"], first["expires_at"])
        self.assertEqual(len(self.runtime.projects), 1)

    def test_other_tickets_get_other_slots_and_ports(self):
        one = self.supervisor.request("alpha", "T-1", "a")
        two = self.supervisor.request("alpha", "T-2", "a")
        other = self.supervisor.request("beta", "T-1", "a")
        self.assertEqual([one["slot"], two["slot"], other["slot"]], ["alpha-1", "alpha-2", "beta-1"])
        ports = [p for slot in (one, two, other) for p in slot["ports"].values()]
        self.assertEqual(len(set(ports)), 6)

    def test_project_cap_refuses(self):
        self.supervisor.request("alpha", "T-1", "a")
        self.supervisor.request("alpha", "T-2", "a")
        with self.assertRaises(ProjectCapReached):
            self.supervisor.request("alpha", "T-3", "a")
        self.assertEqual(len(self.runtime.projects), 2)

    def test_server_limit_refuses(self):
        self.supervisor.request("alpha", "T-1", "a")
        self.supervisor.request("alpha", "T-2", "a")
        self.supervisor.request("beta", "T-1", "a")
        with self.assertRaises(ServerLimitReached):
            self.supervisor.request("beta", "T-2", "a")
        self.assertEqual(len(self.runtime.projects), 3)

    def test_no_free_port_refuses(self):
        write_template(self.templates, "alpha", ports=["app"] + ["p%d" % n for n in range(10)], database=None)
        with self.assertRaises(ServerLimitReached):
            self.supervisor.request("alpha", "T-1", "a")
        self.assertEqual(self.runtime.projects, {})

    def test_unknown_project_and_bad_input(self):
        with self.assertRaises(NotFound):
            self.supervisor.request("gamma", "T-1", "a")
        with self.assertRaises(Invalid):
            self.supervisor.request("Alpha!", "T-1", "a")
        with self.assertRaises(Invalid):
            self.supervisor.request("alpha", "", "a")

    def test_a_slot_name_must_be_a_dns_label(self):
        for name in ("Alpha-1", "alpha_x-1", "-alpha-1", "alpha--1", "alpha-", "alpha-01", "alpha.b-1", "alpha"):
            with self.assertRaises(Invalid, msg=name):
                self.supervisor.check(name)
        longest = "a" * 61  # "<61>-1" is 63 characters: the longest label DNS allows
        write_template(self.templates, longest, cap=1)
        self.assertEqual(self.supervisor.request(longest, "T-1", "a")["slot"], longest + "-1")
        self.assertEqual(self.supervisor.check(longest + "-1")["state"], "running")
        with self.assertRaises(Invalid):
            self.supervisor.check("a" * 62 + "-1")
        # A cap that would make a later name too long is refused before anything starts.
        write_template(self.templates, "b" * 61, cap=10)
        with self.assertRaises(Invalid) as caught:
            self.supervisor.request("b" * 61, "T-1", "a")
        self.assertIn("at most 63", str(caught.exception))
        self.assertEqual(len(self.runtime.projects), 1)

    def test_a_failed_seed_leaves_nothing_behind(self):
        self.runtime.fail_seed = True
        with self.assertRaises(RuntimeFailed):
            self.supervisor.request("alpha", "T-1", "a")
        self.assertEqual(self.runtime.projects, {})
        self.assertEqual(self.runtime.routes, {})


class LifecycleTests(SupervisorCase):
    def test_check_running_and_stopped(self):
        self.supervisor.request("alpha", "T-1", "dev-agent")
        self.runtime.unhealthy.add("alpha-1")
        running = self.supervisor.check("alpha-1")
        self.assertEqual((running["state"], running["ticket"], running["agent"]), ("running", "T-1", "dev-agent"))
        self.assertFalse(running["health"]["ok"])
        self.assertIn("http://upstream.test:20000/healthz", running["health"]["detail"])
        stopped = self.supervisor.check("alpha-2")
        self.assertEqual((stopped["state"], stopped["ticket"]), ("stopped", None))
        with self.assertRaises(NotFound):
            self.supervisor.check("alpha-3")  # above the cap
        with self.assertRaises(NotFound):
            self.supervisor.check("gamma-1")
        with self.assertRaises(Invalid):
            self.supervisor.check("nonsense")

    def test_reset_reseeds_without_moving_expiry(self):
        first = self.supervisor.request("alpha", "T-1", "a")
        self.runtime.events.clear()
        self.clock.forward(hours=3)
        after = self.supervisor.reset("alpha-1")
        self.assertEqual(self.runtime.events[:3], [("stop", "alpha-1"), ("start", "alpha-1"), ("seed", "alpha-1")])
        self.assertEqual(after["expires_at"], first["expires_at"])
        self.assertEqual(after["started_at"], first["started_at"])
        self.assertEqual(after["ports"], first["ports"])
        self.assertEqual(after["ticket"], "T-1")
        with self.assertRaises(NotFound):
            self.supervisor.reset("alpha-2")

    def test_release_frees_the_port_and_the_route(self):
        first = self.supervisor.request("alpha", "T-1", "a")
        self.assertIsNone(self.supervisor.release("alpha-1"))
        self.assertEqual(self.runtime.projects, {})
        self.assertEqual(self.runtime.routes, {})
        self.assertEqual(self.supervisor.check("alpha-1")["state"], "stopped")
        again = self.supervisor.request("alpha", "T-2", "a")
        self.assertEqual(again["ports"], first["ports"])
        self.supervisor.release("alpha-2")  # not running: nothing to do, no error

    def test_reap_stops_only_expired_slots(self):
        self.supervisor.request("alpha", "T-1", "a")
        self.clock.forward(hours=5)
        self.supervisor.request("beta", "T-9", "a")
        self.clock.forward(hours=2, minutes=59)
        self.assertEqual(self.supervisor.reap(), {"stopped": [], "failed": []})
        self.clock.forward(minutes=1)  # alpha-1 is now exactly 8 hours old
        self.assertEqual(self.supervisor.reap(), {"stopped": ["alpha-1"], "failed": []})
        self.assertEqual(list(self.runtime.projects), ["beta-1"])
        self.assertEqual(list(self.runtime.routes), ["beta-1"])

    def test_a_ticket_that_outlasts_its_slot_gets_a_fresh_one(self):
        first = self.supervisor.request("alpha", "T-1", "a")
        self.clock.forward(hours=8, minutes=1)
        self.assertTrue(self.supervisor.check("alpha-1")["expired"])
        fresh = self.supervisor.request("alpha", "T-1", "a")
        self.assertTrue(fresh["created"])
        self.assertEqual(fresh["expires_at"], "2026-11-24T01:01:00Z")
        self.assertNotEqual(fresh["expires_at"], first["expires_at"])
        self.assertEqual(self.runtime.events.count(("stop", "alpha-1")), 1)

    def test_list_is_what_a_monitor_reads(self):
        self.supervisor.request("alpha", "T-1", "a")
        self.supervisor.request("beta", "T-2", "b")
        listing = self.supervisor.list()
        self.assertEqual(listing["max_running"], 3)
        self.assertEqual(listing["now"], "2026-11-23T09:00:00Z")
        self.assertEqual([s["slot"] for s in listing["slots"]], ["alpha-1", "beta-1"])
        self.assertEqual(listing["slots"][0]["ticket"], "T-1")
        self.assertNotIn("deploy", listing["slots"][0])
        self.assertEqual([s["slot"] for s in self.supervisor.list(project="beta")["slots"]], ["beta-1"])

    def test_state_is_rebuilt_from_what_is_running(self):
        first = self.supervisor.request("alpha", "T-1", "dev-agent")
        # A "restart": a new supervisor that has only the runtime to look at.
        restarted = Supervisor(self.settings, self.runtime, self.clock)
        self.assertEqual(restarted.check("alpha-1"), self.supervisor.check("alpha-1"))
        same = restarted.request("alpha", "T-1", "dev-agent")
        self.assertEqual((same["slot"], same["created"], same["expires_at"]),
                         ("alpha-1", False, first["expires_at"]))
        second = restarted.request("alpha", "T-2", "dev-agent")
        self.assertEqual(second["ports"], {"app": 20002, "db": 20003})
        self.clock.forward(hours=9)
        self.assertEqual(restarted.reap()["stopped"], ["alpha-1", "alpha-2"])


class ScopeTests(SupervisorCase):
    def test_a_project_token_cannot_see_or_touch_another_project(self):
        self.supervisor.request("alpha", "T-1", "a", scope="alpha")
        self.supervisor.request("beta", "T-1", "b", scope="beta")
        self.assertEqual([s["slot"] for s in self.supervisor.list(scope="alpha")["slots"]], ["alpha-1"])
        for call in (lambda: self.supervisor.request("beta", "T-2", "a", scope="alpha"),
                     lambda: self.supervisor.check("beta-1", scope="alpha"),
                     lambda: self.supervisor.reset("beta-1", scope="alpha"),
                     lambda: self.supervisor.release("beta-1", scope="alpha"),
                     lambda: self.supervisor.list(scope="alpha", project="beta"),
                     lambda: self.supervisor.reap(scope="alpha")):
            with self.assertRaises(Forbidden):
                call()
        self.assertIn("beta-1", self.runtime.projects)
        self.assertEqual(self.runtime.events.count(("stop", "beta-1")), 0)
        self.assertEqual(len(self.supervisor.list()["slots"]), 2)  # admin sees both
