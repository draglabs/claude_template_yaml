"""The `slot` command: the same verbs as the HTTP API, run on the slot server itself.

Whoever can run this on the server can already run docker there, so the
command needs no token and sees every project.
"""
from __future__ import annotations

import argparse
import json
import os
import sys

from .config import Settings, Tokens, serve_settings
from .errors import SlotError
from .supervisor import Supervisor


def _parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(prog="slot", description="Dev slots on this server.")
    verbs = parser.add_subparsers(dest="verb", required=True)
    request = verbs.add_parser("request", help="get the ticket's slot, starting one if needed")
    request.add_argument("--project", required=True)
    request.add_argument("--ticket", required=True)
    request.add_argument("--agent", required=True)
    for verb, text in (("check", "report one slot"),
                       ("reset", "drop the data, reseed, restart; the expiry does not move"),
                       ("release", "stop a slot and free what it reserved")):
        verbs.add_parser(verb, help=text).add_argument("slot")
    verbs.add_parser("list", help="every running slot").add_argument("--project")
    verbs.add_parser("reap", help="stop every slot past its expiry")
    verbs.add_parser("serve", help="run the HTTP API")
    return parser


def main(argv=None, supervisor=None, environ=None, out=None, err=None) -> int:
    out, err = out or sys.stdout, err or sys.stderr
    environ = os.environ if environ is None else environ
    args = _parser().parse_args(argv)
    try:
        if supervisor is None:
            from .docker_runtime import DockerRuntime
            settings = Settings.from_env(environ)
            supervisor = Supervisor(settings, DockerRuntime(settings))
        if args.verb == "serve":
            return _serve(supervisor, environ, err)
        if args.verb == "request":
            result = supervisor.request(args.project, args.ticket, args.agent)
        elif args.verb == "check":
            result = supervisor.check(args.slot)
        elif args.verb == "reset":
            result = supervisor.reset(args.slot)
        elif args.verb == "release":
            result = supervisor.release(args.slot)
        elif args.verb == "list":
            result = supervisor.list(project=args.project)
        else:
            result = supervisor.reap()
    except SlotError as exc:
        json.dump({"error": {"code": exc.code, "message": str(exc)}}, err, indent=2)
        err.write("\n")
        return 1
    if result is not None:
        json.dump(result, out, indent=2)
        out.write("\n")
    # A reap that could not stop something must make the timer's unit fail.
    return 1 if args.verb == "reap" and result["failed"] else 0


def _serve(supervisor, environ, err) -> int:
    from .httpapi import make_server
    host, port, tokens_file = serve_settings(environ)
    server = make_server(supervisor, Tokens.load(tokens_file), host, port)
    err.write("slot supervisor listening on %s:%d\n" % (host, port))
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()
    return 0
