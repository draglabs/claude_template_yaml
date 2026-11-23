"""The one narrow door to the outside world. The supervisor touches nothing else."""
from __future__ import annotations

from typing import ContextManager, Dict, List

# Files the runtime writes into a slot's directory while the slot runs.
ENV_FILE_NAME = ".env"
OVERRIDE_FILE_NAME = "compose.slot.json"


class Runtime:
    def lock(self) -> ContextManager:
        """One start/stop at a time on this server, across processes."""
        raise NotImplementedError

    def start(self, name: str, template_dir: str, slot_dir: str, env: Dict[str, str], labels: Dict[str, str]) -> None:
        """Create slot_dir and bring up compose project `name` from the template, labelled."""
        raise NotImplementedError

    def stop(self, name: str, slot_dir: str) -> None:
        """Remove the project's containers, networks and volumes, and slot_dir."""
        raise NotImplementedError

    def list_running(self) -> List[Dict[str, str]]:
        """One dict of `slots.*` labels per compose project that has containers."""
        raise NotImplementedError

    def seed(self, name: str, template_dir: str, command: List[str], env: Dict[str, str]) -> None:
        """Run the template's seed command against the started project."""
        raise NotImplementedError

    def health(self, name: str, url: str) -> Dict[str, object]:
        """{"ok": bool, "detail": str}: all containers running and `url` answers."""
        raise NotImplementedError

    def write_route(self, name: str, host: str, port: int) -> None:
        """Send the slot's own host name to `port`, and reload the proxy."""
        raise NotImplementedError

    def remove_route(self, name: str) -> None:
        raise NotImplementedError
