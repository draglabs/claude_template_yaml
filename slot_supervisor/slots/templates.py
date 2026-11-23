"""A project's slot template: <templates_dir>/<project>/{compose.yaml,slot.json}."""
from __future__ import annotations

import json
import os
import re
from dataclasses import dataclass
from typing import List, Optional

from .errors import ConfigError, NotFound

COMPOSE_FILE_NAME = "compose.yaml"
SETTINGS_FILE_NAME = "slot.json"
ROUTED_PORT = "app"  # the port name the proxy sends /<slot>/ to

PORT_NAME_RE = re.compile(r"^[a-z][a-z0-9_]*$")
REQUIRED = {"cap", "ports", "internal_port", "strip_prefix", "health_path", "seed_command", "deploy_user"}
OPTIONAL = {"database"}


@dataclass(frozen=True)
class Template:
    project: str
    directory: str
    cap: int
    ports: List[str]
    internal_port: int
    strip_prefix: bool
    health_path: str
    seed_command: List[str]
    deploy_user: str
    database: Optional[str]


def load_template(templates_dir: str, project: str) -> Template:
    directory = os.path.join(templates_dir, project)
    path = os.path.join(directory, SETTINGS_FILE_NAME)
    if not os.path.isfile(path):
        raise NotFound("project %r has no slot template (%s is missing)" % (project, path))

    def bad(message: str) -> ConfigError:
        return ConfigError("%s: %s" % (path, message))

    if not os.path.isfile(os.path.join(directory, COMPOSE_FILE_NAME)):
        raise bad("%s is missing next to it" % COMPOSE_FILE_NAME)
    try:
        with open(path, encoding="utf-8") as handle:
            data = json.load(handle)
    except ValueError as exc:
        raise bad("not valid JSON (%s)" % exc)
    if not isinstance(data, dict):
        raise bad("must be a JSON object")
    missing, unknown = REQUIRED - set(data), set(data) - REQUIRED - OPTIONAL
    if missing or unknown:
        raise bad("missing keys %s, unknown keys %s" % (sorted(missing), sorted(unknown)))

    def is_int(value) -> bool:
        return isinstance(value, int) and not isinstance(value, bool) and value > 0

    if not is_int(data["cap"]):
        raise bad("cap must be a whole number above zero")
    if not is_int(data["internal_port"]):
        raise bad("internal_port must be a whole number above zero")
    if not isinstance(data["strip_prefix"], bool):
        raise bad("strip_prefix must be true or false")
    ports = data["ports"]
    if (not isinstance(ports, list) or len(set(ports)) != len(ports) or ROUTED_PORT not in ports
            or not all(isinstance(p, str) and PORT_NAME_RE.match(p) for p in ports)):
        raise bad('ports must be a list of different lower-case names that includes "%s"' % ROUTED_PORT)
    health_path = data["health_path"]
    if not isinstance(health_path, str) or not health_path.startswith("/"):
        raise bad('health_path must start with "/"')
    seed = data["seed_command"]
    if not isinstance(seed, list) or not seed or not all(isinstance(a, str) and a for a in seed):
        raise bad("seed_command must be a non-empty list of strings (a command and its arguments)")
    if not isinstance(data["deploy_user"], str) or not data["deploy_user"]:
        raise bad("deploy_user must be a non-empty string")
    database = data.get("database")
    if database is not None:
        if not isinstance(database, str):
            raise bad("database must be a string")
        try:
            format_database(database, "host", project + "-1", {name: 1 for name in ports})
        except (KeyError, IndexError, ValueError) as exc:
            raise bad("database uses a placeholder that does not exist: %s" % exc)
    return Template(project, directory, data["cap"], ports, data["internal_port"], data["strip_prefix"],
                    health_path, seed, data["deploy_user"], database)


def format_database(pattern: str, host: str, slot: str, ports: dict) -> str:
    """Fill {host}, {slot} and {port_<name>} in a template's database string."""
    values = {"host": host, "slot": slot}
    values.update({"port_" + name: port for name, port in ports.items()})
    return pattern.format(**values)
