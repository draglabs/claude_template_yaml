#!/usr/bin/env python3
# FRAMEWORK-OWNED — overwritten on every sync; do not edit (FWADR-014).
"""The agent host reaper: ends what a dead agent run left behind (FWADR-043, paperclip-mode.md adoption step 6).

    agent_host_reaper.py                  dry run: list what would be ended, end nothing
    agent_host_reaper.py --kill           end it (TERM, then KILL five seconds later)
    agent_host_reaper.py --user paperclip the agent user (default: whoever runs this)
    agent_host_reaper.py --min-age 30     minutes a leftover must have lived (default 30)
    agent_host_reaper.py --keep REGEX     command lines never ended, with everything under them

Why: a run that dies leaves its children (a test runner, a dev server, a helper that calls itself)
running with no parent. Nothing ends them, they count against the agent user's task limit, and at
the limit every new run dies at start. It has held a host for ten days once and for a night once.

What it ends: a process tree of the agent user that belongs to NO live run and is older than
--min-age. It never ends a process under a live run. "Under a live run" means either of:
  - it has an ancestor that is the run's connection (REAPER_LIVE_ROOT, default: sshd), or
  - it shares a login session (systemd `session-N.scope`) with such a process, which covers what a
    live run started in the background and detached.
It also never ends: the user's systemd manager and anything it runs as a user service, anything
matching --keep / REAPER_KEEP, and itself.

On a host without systemd login sessions the second test cannot be made, and a job a live run
detached looks like a leftover: set --min-age above the longest run there.

Run it on the agent host, as root or as the agent user, from a timer every ten minutes or so.
Dry-run it first and read the list. Linux only (reads /proc). Stdlib only. Exit 1 when a process
it meant to end is still alive.
"""
from __future__ import annotations

import argparse
import os
import pwd
import re
import signal
import sys
import time
from pathlib import Path

SESSION = re.compile(r"session-[^/]+\.scope")


def read_procs(proc: Path = Path("/proc")) -> dict[int, dict]:
    ticks = os.sysconf("SC_CLK_TCK")
    uptime = float((proc / "uptime").read_text().split()[0])
    out = {}
    for d in proc.iterdir():
        if not d.name.isdigit():
            continue
        try:
            stat = (d / "stat").read_text()
            rest = stat[stat.rindex(")") + 2:].split()  # after "pid (comm) "; comm may hold spaces
            uid = int(re.search(r"^Uid:\s+(\d+)", (d / "status").read_text(), re.M).group(1))
            args = (d / "cmdline").read_bytes().replace(b"\0", b" ").decode(errors="replace").strip()
            cgroup = (d / "cgroup").read_text()
        except (OSError, ValueError, AttributeError):
            continue  # it ended while being read
        if rest[0] == "Z":
            continue  # already dead, waiting for its parent; nothing to end
        out[int(d.name)] = {"pid": int(d.name), "ppid": int(rest[1]), "uid": uid, "start": int(rest[19]),
                            "age_min": (uptime - int(rest[19]) / ticks) / 60,
                            "args": args or stat[stat.index("(") + 1:stat.rindex(")")], "cgroup": cgroup}
    return out


def select(procs: dict[int, dict], uid: int, min_age: float, keep: str, live_root: str, me: int) -> list[list[dict]]:
    """The leftover trees: each a list of processes, its root first. Pure, so it can be tested on a made-up table."""
    live_re, keep_re = re.compile(live_root), re.compile(keep) if keep else None

    def ancestors(p):
        seen = set()
        while p["ppid"] in procs and p["pid"] not in seen:
            seen.add(p["pid"])
            p = procs[p["ppid"]]
            yield p

    def session(p):
        m = SESSION.search(p["cgroup"])
        return m.group(0) if m else None

    mine = [p for p in procs.values() if p["uid"] == uid]
    under_run = {p["pid"] for p in mine if any(live_re.search(a["args"]) for a in ancestors(p))}
    live_sessions = {session(procs[pid]) for pid in under_run} - {None}
    under_run |= {a["pid"] for pid in list(under_run) for a in ancestors(procs[pid])}  # what a run hangs from
    safe = set(under_run) | {me} | {a["pid"] for a in ancestors(procs[me])} if me in procs else set(under_run)
    for p in mine:
        if (session(p) in live_sessions or f"user@{uid}.service" in p["cgroup"] or live_re.search(p["args"])
                or re.match(r"(/usr)?/lib/systemd/systemd --user|\(sd-pam\)", p["args"])
                or (keep_re and any(keep_re.search(a["args"]) for a in (p, *ancestors(p)) if a["uid"] == uid))):
            safe.add(p["pid"])
    left = {p["pid"]: p for p in mine if p["pid"] not in safe}
    trees: dict[int, list[dict]] = {}
    for p in sorted(left.values(), key=lambda p: p["start"]):
        root = p
        for a in ancestors(p):
            if a["pid"] not in left:
                break
            root = a
        trees.setdefault(root["pid"], []).append(p)
    return [sorted(t, key=lambda p: p["pid"] != r) for r, t in trees.items() if procs[r]["age_min"] > min_age]


def main() -> None:
    ap = argparse.ArgumentParser(description="End what a dead agent run left behind. Dry run unless --kill.")
    ap.add_argument("--kill", action="store_true")
    ap.add_argument("--user", default=os.environ.get("REAPER_USER") or pwd.getpwuid(os.getuid()).pw_name)
    ap.add_argument("--min-age", type=float, default=float(os.environ.get("REAPER_MIN_AGE") or 30))
    ap.add_argument("--keep", default=os.environ.get("REAPER_KEEP", ""))
    a = ap.parse_args()
    uid = pwd.getpwnam(a.user).pw_uid
    live_root = os.environ.get("REAPER_LIVE_ROOT") or r"^sshd(-session)?(:| |$)"
    procs = read_procs()
    trees = select(procs, uid, a.min_age, a.keep, live_root, os.getpid())
    if not trees:
        return  # quiet when there is nothing: it runs from a timer
    total = sum(len(t) for t in trees)
    print(f"reaper: {total} leftover process(es) of {a.user} in {len(trees)} tree(s), none under a live run"
          + ("" if a.kill else " (dry run: nothing ended; --kill ends them)"))
    for t in trees:
        print(f"  pid {t[0]['pid']}, {t[0]['age_min']:.0f} min old, {len(t)} process(es): {t[0]['args'][:120]}")
    if not a.kill:
        return
    targets = [p for t in trees for p in t]

    def alive(p) -> bool:  # the same process, not a new one that was given its number
        try:
            stat = Path(f"/proc/{p['pid']}/stat").read_text()
            return int(stat[stat.rindex(")") + 2:].split()[19]) == p["start"]
        except (OSError, ValueError):
            return False

    for sig in (signal.SIGTERM, signal.SIGKILL):
        for p in targets:
            if alive(p):
                try:
                    os.kill(p["pid"], sig)
                except (ProcessLookupError, PermissionError):
                    pass
        time.sleep(5 if sig == signal.SIGTERM else 1)
    still = [p for p in targets if alive(p)]
    print(f"reaper: ended {total - len(still)} of {total}" + (f"; STILL ALIVE: {[p['pid'] for p in still]}" if still else ""))
    sys.exit(1 if still else 0)


if __name__ == "__main__":
    main()
