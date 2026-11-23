import json
import os
import threading
import urllib.error
import urllib.request

from helpers import SupervisorCase
from slots.config import Tokens
from slots.httpapi import make_server

ADMIN = "admin-token-0123456789"
ALPHA = "alpha-token-0123456789"
BETA = "beta-token-01234567890"


class HttpTests(SupervisorCase):
    def setUp(self):
        super().setUp()
        tokens = Tokens(ADMIN, {"alpha": ALPHA, "beta": BETA})
        self.server = make_server(self.supervisor, tokens, "localhost", 0, quiet=True)
        thread = threading.Thread(target=self.server.serve_forever, daemon=True)
        thread.start()
        self.addCleanup(thread.join)
        self.addCleanup(self.server.server_close)
        self.addCleanup(self.server.shutdown)
        self.base = "http://localhost:%d" % self.server.server_address[1]

    def call(self, method, path, token=None, body=None):
        data = None if body is None else json.dumps(body).encode()
        request = urllib.request.Request(self.base + path, data=data, method=method)
        if token:
            request.add_header("Authorization", "Bearer " + token)
        try:
            with urllib.request.urlopen(request) as response:
                raw = response.read()
                return response.status, (json.loads(raw) if raw else None)
        except urllib.error.HTTPError as exc:
            return exc.code, json.loads(exc.read())

    def request_slot(self, token, project="alpha", ticket="T-1"):
        return self.call("POST", "/api/slots", token, {"project": project, "ticket": ticket, "agent": "dev-agent"})

    def test_request_then_same_ticket(self):
        status, slot = self.request_slot(ALPHA)
        self.assertEqual(status, 201)
        self.assertEqual(slot["slot"], "alpha-1")
        self.assertEqual(slot["url"], "https://alpha-1.slots.test/")
        self.assertEqual(slot["deploy"]["directory"], os.path.join(self.settings.work_dir, "alpha-1"))
        self.assertEqual(self.runtime.events, [("start", "alpha-1"), ("seed", "alpha-1"), ("route", "alpha-1")])
        status, again = self.request_slot(ALPHA)
        self.assertEqual((status, again["slot"], again["created"]), (200, "alpha-1", False))

    def test_check_reset_release(self):
        _, slot = self.request_slot(ALPHA)
        status, checked = self.call("GET", "/api/slots/alpha-1", ALPHA)
        self.assertEqual((status, checked["state"], checked["ticket"]), (200, "running", "T-1"))
        self.clock.forward(hours=2)
        status, reset = self.call("POST", "/api/slots/alpha-1/reset", ALPHA)
        self.assertEqual((status, reset["expires_at"]), (200, slot["expires_at"]))
        self.assertEqual(self.runtime.events.count(("seed", "alpha-1")), 2)
        self.assertEqual(self.call("DELETE", "/api/slots/alpha-1", ALPHA), (204, None))
        self.assertEqual(self.runtime.projects, {})
        self.assertEqual(self.runtime.routes, {})
        status, checked = self.call("GET", "/api/slots/alpha-1", ALPHA)
        self.assertEqual((status, checked["state"]), (200, "stopped"))

    def test_refusals_carry_a_code(self):
        self.request_slot(ALPHA, ticket="T-1")
        self.request_slot(ALPHA, ticket="T-2")
        status, body = self.request_slot(ALPHA, ticket="T-3")
        self.assertEqual((status, body["error"]["code"]), (409, "project_cap_reached"))
        self.request_slot(BETA, project="beta", ticket="T-1")
        status, body = self.request_slot(BETA, project="beta", ticket="T-2")
        self.assertEqual((status, body["error"]["code"]), (409, "server_limit_reached"))
        status, body = self.call("POST", "/api/slots", ALPHA, {"project": "alpha"})
        self.assertEqual((status, body["error"]["code"]), (400, "invalid_request"))
        status, body = self.call("GET", "/api/nothing", ALPHA)
        self.assertEqual((status, body["error"]["code"]), (404, "not_found"))

    def test_tokens(self):
        self.request_slot(ALPHA)
        self.request_slot(BETA, project="beta")
        for token in (None, "wrong-token-0123456789"):
            status, body = self.call("GET", "/api/slots", token)
            self.assertEqual((status, body["error"]["code"]), (401, "unauthorized"))
        _, listing = self.call("GET", "/api/slots", ALPHA)
        self.assertEqual([s["slot"] for s in listing["slots"]], ["alpha-1"])
        _, listing = self.call("GET", "/api/slots", ADMIN)
        self.assertEqual([s["slot"] for s in listing["slots"]], ["alpha-1", "beta-1"])
        _, listing = self.call("GET", "/api/slots?project=beta", ADMIN)
        self.assertEqual([s["slot"] for s in listing["slots"]], ["beta-1"])
        for method, path, body in (("GET", "/api/slots/beta-1", None),
                                   ("POST", "/api/slots/beta-1/reset", None),
                                   ("DELETE", "/api/slots/beta-1", None),
                                   ("GET", "/api/slots?project=beta", None),
                                   ("POST", "/api/reap", None),
                                   ("POST", "/api/slots", {"project": "beta", "ticket": "T-5", "agent": "x"})):
            status, answer = self.call(method, path, ALPHA, body)
            self.assertEqual((status, answer["error"]["code"]), (403, "forbidden"), path)
        self.assertIn("beta-1", self.runtime.projects)

    def test_reap_and_healthz(self):
        self.request_slot(ALPHA)
        self.assertEqual(self.call("GET", "/api/healthz"), (200, {"ok": True}))
        self.assertEqual(self.call("POST", "/api/reap", ADMIN), (200, {"stopped": [], "failed": []}))
        self.clock.forward(hours=8)
        self.assertEqual(self.call("POST", "/api/reap", ADMIN), (200, {"stopped": ["alpha-1"], "failed": []}))
