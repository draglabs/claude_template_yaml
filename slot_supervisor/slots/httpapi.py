"""HTTP over the same six verbs. JSON in and out, bearer-token auth."""
from __future__ import annotations

import json
import sys
import traceback
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, urlsplit

from .config import Tokens
from .errors import Invalid, NotFound, SlotError, Unauthorized
from .supervisor import Supervisor

MAX_BODY_BYTES = 65536


def make_server(supervisor: Supervisor, tokens: Tokens, host: str, port: int, quiet: bool = False):
    class Handler(BaseHTTPRequestHandler):
        server_version = "slot-supervisor"

        def do_GET(self):
            self._handle("GET")

        def do_POST(self):
            self._handle("POST")

        def do_DELETE(self):
            self._handle("DELETE")

        def log_message(self, format, *args):
            # The request line and status only. Headers (the token) are never logged.
            if not quiet:
                sys.stderr.write("%s %s\n" % (self.address_string(), format % args))

        def _handle(self, method):
            try:
                status, body = self._route(method)
            except SlotError as exc:
                status, body = exc.status, {"error": {"code": exc.code, "message": str(exc)}}
            except Exception as exc:
                traceback.print_exc(file=sys.stderr)
                status, body = 500, {"error": {"code": "internal_error", "message": str(exc)}}
            payload = b"" if body is None else json.dumps(body).encode()
            self.send_response(status)
            if body is not None:
                self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(payload)))
            self.end_headers()
            self.wfile.write(payload)

        def _route(self, method):
            url = urlsplit(self.path)
            parts = [part for part in url.path.split("/") if part]
            if (method, parts) == ("GET", ["api", "healthz"]):
                return 200, {"ok": True}
            scope = self._scope()
            if (method, parts) == ("POST", ["api", "reap"]):
                return 200, supervisor.reap(scope)
            if parts[:2] == ["api", "slots"]:
                rest = parts[2:]
                if method == "GET" and not rest:
                    project = parse_qs(url.query).get("project", [None])[0]
                    return 200, supervisor.list(scope, project)
                if method == "POST" and not rest:
                    body = self._json_body()
                    if set(body) != {"project", "ticket", "agent"}:
                        raise Invalid('the body must be {"project": ..., "ticket": ..., "agent": ...}')
                    slot = supervisor.request(body["project"], body["ticket"], body["agent"], scope)
                    return (201 if slot["created"] else 200), slot
                if method == "GET" and len(rest) == 1:
                    return 200, supervisor.check(rest[0], scope)
                if method == "DELETE" and len(rest) == 1:
                    supervisor.release(rest[0], scope)
                    return 204, None
                if method == "POST" and len(rest) == 2 and rest[1] == "reset":
                    return 200, supervisor.reset(rest[0], scope)
            raise NotFound("no such route: %s %s" % (method, url.path))

        def _scope(self):
            kind, _, token = self.headers.get("Authorization", "").partition(" ")
            scope = tokens.scope_for(token.strip()) if kind == "Bearer" and token.strip() else None
            if scope is None:
                raise Unauthorized("send 'Authorization: Bearer <token>' with a valid token")
            return scope

        def _json_body(self):
            try:
                length = int(self.headers.get("Content-Length", ""))
            except ValueError:
                raise Invalid("a JSON body with a Content-Length is required")
            if length > MAX_BODY_BYTES:
                raise Invalid("the body is too large")
            try:
                body = json.loads(self.rfile.read(length))
            except ValueError:
                raise Invalid("the body is not valid JSON")
            if not isinstance(body, dict):
                raise Invalid("the body must be a JSON object")
            return body

    return ThreadingHTTPServer((host, port), Handler)
