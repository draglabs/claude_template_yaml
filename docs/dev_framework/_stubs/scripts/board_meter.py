#!/usr/bin/env python3
# FRAMEWORK-OWNED — overwritten on every sync; do not edit (FWADR-014).
"""The board meter: which Paperclip tickets look wasteful, from the records Paperclip keeps (FWADR-043).

    scripts/board_meter.py                 a short report (markdown), flagged tickets first
    scripts/board_meter.py --json          the same, as JSON, for an agent to read
    scripts/board_meter.py --all           include tickets with no flag

REPORT ONLY. It reads the board and changes nothing: no run is stopped, no ticket is blocked.
It costs no tokens, so it can run as often as wanted; the board-review agent reads its output
and decides what to do: the Paperclip Lead (docs/dev_framework/paperclip-lead.md).

Signals, and the reason code each one gives a ticket:
  retry-loop     2 or more failed runs in a row
  long-run       a live run older than LONG_RUN_MIN with no output for QUIET_MIN
  orphaned       `in_progress` with no live run for ORPHAN_HOURS
  waiting        `in_review` for WAIT_HOURS
  heavy          more than HEAVY_M million cached tokens read on the ticket
  many-runs      MANY_RUNS or more runs
  family         a ticket and everything split from it: more than FAMILY_SIZE tickets, or
                 children still open under a parent that is not running
  over-budget    recorded spend on the ticket past PAPERCLIP_TICKET_BUDGET_CENTS (when set)
  host           (when run on the agent host) the agent user's task count near its limit, or
                 processes older than a day

Thresholds are project variables: each constant below is the default, and BOARD_METER_<NAME>
in the environment overrides it (BOARD_METER_LONG_RUN_MIN=30). The defaults are guesses from two
weeks of one board and are meant to be tuned. Credentials: PAPERCLIP_API_URL and
PAPERCLIP_API_KEY from the environment (an agent run has them; a person sources the operator
.env). PAPERCLIP_COMPANY names the company (default: PROJECT_NAME, else the only one the key
can see). Stdlib only.
"""
from __future__ import annotations

import collections
import datetime as dt
import json
import os
import sys
import urllib.request
from pathlib import Path

def setting(name: str, default: float) -> float:
    return float(os.environ.get("BOARD_METER_" + name) or default)


LONG_RUN_MIN = setting("LONG_RUN_MIN", 45)
QUIET_MIN = setting("QUIET_MIN", 15)
ORPHAN_HOURS = setting("ORPHAN_HOURS", 24)
WAIT_HOURS = setting("WAIT_HOURS", 24)
HEAVY_M = setting("HEAVY_M", 60)
MANY_RUNS = setting("MANY_RUNS", 8)
FAMILY_SIZE = setting("FAMILY_SIZE", 3)
HOST_TASK_SHARE = setting("HOST_TASK_SHARE", 0.5)
TICKET_BUDGET_CENTS = float(os.environ.get("PAPERCLIP_TICKET_BUDGET_CENTS") or 0)  # 0 = no per-ticket cap
OPEN = ("todo", "in_progress", "in_review", "blocked")
BAD_RUN = ("failed", "timed_out")


def creds() -> tuple[str, str]:
    url, key = os.environ.get("PAPERCLIP_API_URL", ""), os.environ.get("PAPERCLIP_API_KEY", "")
    if not (url and key):
        sys.exit("board_meter: PAPERCLIP_API_URL and PAPERCLIP_API_KEY are needed (source the operator .env)")
    return url.rstrip("/") + "/api", key


def when(s: str | None) -> dt.datetime | None:
    return dt.datetime.fromisoformat(s.replace("Z", "+00:00")) if s else None


def num(v) -> float:
    return float(v) if v not in (None, "") else 0.0


def host_findings() -> list[str]:
    """Only meaningful on the agent host; silent anywhere else."""
    out = []
    base = Path(f"/sys/fs/cgroup/user.slice/user-{os.getuid()}.slice")
    try:
        cur, mx = int((base / "pids.current").read_text()), (base / "pids.max").read_text().strip()
        if mx != "max" and cur > HOST_TASK_SHARE * int(mx):
            out.append(f"agent user is at {cur} of {mx} tasks")
    except (OSError, ValueError):
        return out
    try:
        import subprocess
        old = subprocess.run(["ps", "-u", str(os.getuid()), "-o", "etimes=,comm="], capture_output=True, text=True).stdout
        stale = [ln.split(None, 1)[1] for ln in old.splitlines() if ln.split() and int(ln.split()[0]) > 86400
                 and ln.split(None, 1)[1].strip() not in ("systemd", "(sd-pam)")]
        if stale:
            out.append(f"{len(stale)} process(es) older than a day ({', '.join(sorted(set(stale))[:4])})")
    except (OSError, ValueError, IndexError):
        pass
    return out


def main(argv: list[str]) -> None:
    base, key = creds()

    def get(path: str):
        req = urllib.request.Request(base + path, headers={"Authorization": "Bearer " + key})
        return json.loads(urllib.request.urlopen(req, timeout=60).read())

    companies = get("/companies")
    want = (os.environ.get("PAPERCLIP_COMPANY") or os.environ.get("PROJECT_NAME") or "").lower()
    co = next((c for c in companies if c["name"].lower() == want), None) or (companies[0] if len(companies) == 1 else None)
    if co is None:
        sys.exit(f"board_meter: set PAPERCLIP_COMPANY to one of {[c['name'] for c in companies]}")
    cid = co["id"]
    agents = {a["id"]: a["name"] for a in get(f"/companies/{cid}/agents")}
    issues = get(f"/companies/{cid}/issues?limit=500")
    issues = issues if isinstance(issues, list) else issues.get("items", [])
    by = {i["id"]: i for i in issues}
    runs = sorted(get(f"/companies/{cid}/heartbeat-runs?limit=1000"), key=lambda r: r.get("createdAt") or "")
    now = dt.datetime.now(dt.timezone.utc)

    stat = collections.defaultdict(lambda: {"runs": 0, "cached": 0.0, "cost": 0.0, "streak": 0, "live": None, "last_run": None})
    for r in runs:  # oldest first, so `streak` ends as the failures in a row up to now
        if r.get("issueId") not in by:
            continue
        s = stat[r["issueId"]]
        s["runs"] += 1
        s["cached"] += num(r.get("cachedInputTokens"))
        s["cost"] += num(r.get("costUsd"))
        s["last_run"] = r
        if r.get("status") in BAD_RUN:
            s["streak"] += 1
        elif r.get("status") == "succeeded":
            s["streak"] = 0
        if r.get("status") in ("running", "queued"):
            s["live"] = r

    kids = collections.defaultdict(list)
    for i in issues:
        if i.get("parentId") in by:
            kids[i["parentId"]].append(i)

    def root(i):
        seen = set()
        while i.get("parentId") in by and i["id"] not in seen:
            seen.add(i["id"])
            i = by[i["parentId"]]
        return i

    fam = collections.defaultdict(list)
    for i in issues:
        fam[root(i)["id"]].append(i)

    rows = []
    for i in issues:
        s = stat[i["id"]]
        is_open = i["status"] in OPEN
        idle_h = (now - when(i["updatedAt"])).total_seconds() / 3600
        flags: list[tuple[str, str]] = []
        if s["streak"] >= 2 and is_open:
            flags.append(("retry-loop", f"{s['streak']} failed runs in a row"))
        if s["live"]:
            age = (now - when(s["live"].get("startedAt") or s["live"]["createdAt"])).total_seconds() / 60
            quiet = (now - (when(s["live"].get("lastOutputAt")) or now)).total_seconds() / 60
            if age > LONG_RUN_MIN and quiet > QUIET_MIN:
                flags.append(("long-run", f"run is {age:.0f} min old, no output for {quiet:.0f} min"))
            elif age > 2 * LONG_RUN_MIN:
                flags.append(("long-run", f"run is {age:.0f} min old (still producing output)"))
        if i["status"] == "in_progress" and not s["live"] and idle_h > ORPHAN_HOURS:
            flags.append(("orphaned", f"in progress, no run for {idle_h / 24:.0f} days"))
        if i["status"] == "in_review" and idle_h > WAIT_HOURS:
            flags.append(("waiting", f"in review for {idle_h / 24:.0f} days"))
        if is_open and s["cached"] > HEAVY_M * 1e6:
            flags.append(("heavy", f"{s['cached'] / 1e6:.0f}M tokens read"))
        if is_open and s["runs"] >= MANY_RUNS:
            flags.append(("many-runs", f"{s['runs']} runs"))
        if is_open and TICKET_BUDGET_CENTS and s["cost"] * 100 > TICKET_BUDGET_CENTS:
            flags.append(("over-budget", f"${s['cost']:.2f} recorded against a ${TICKET_BUDGET_CENTS / 100:.2f} cap"))
        if i["id"] in fam and len(fam[i["id"]]) > 1:
            members = fam[i["id"]]
            open_kids = [m for m in members if m["id"] != i["id"] and m["status"] in OPEN]
            cached = sum(stat[m["id"]]["cached"] for m in members)
            if len(members) > FAMILY_SIZE or (open_kids and not any(stat[m["id"]]["live"] for m in members)):
                flags.append(("family", f"{len(members)} tickets, {len(open_kids)} children open, {cached / 1e6:.0f}M tokens read together"))
        rows.append({"id": i["identifier"], "title": i["title"], "status": i["status"],
                     "agent": agents.get(i.get("assigneeAgentId"), "-"), "runs": s["runs"],
                     "tokens_read_m": round(s["cached"] / 1e6, 1), "cost_usd": round(s["cost"], 2),
                     "parent": by[i["parentId"]]["identifier"] if i.get("parentId") in by else None,
                     "flags": [{"code": c, "detail": d} for c, d in flags], "open": is_open})

    flagged = sorted((r for r in rows if r["flags"]), key=lambda r: (-len(r["flags"]), -r["tokens_read_m"]))
    host = host_findings()
    day = [r for r in runs if (now - (when(r.get("createdAt")) or now)).total_seconds() < 86400]
    summary = {
        "at": now.strftime("%Y-%m-%d %H:%M UTC"), "company": co["name"],
        "open": collections.Counter(r["status"] for r in rows if r["open"]),
        "runs_24h": len(day), "failed_24h": sum(1 for r in day if r.get("status") in BAD_RUN),
        "tokens_read_24h_m": round(sum(num(r.get("cachedInputTokens")) for r in day) / 1e6),
        "live_runs": [f"{by[r['issueId']]['identifier']} ({agents.get(r.get('agentId'), '?')})" for r in runs
                      if r.get("status") in ("running", "queued") and r.get("issueId") in by],
        "host": host,
    }
    if "--json" in argv:
        print(json.dumps({"summary": summary, "flagged": flagged, "all": rows if "--all" in argv else None}, indent=1, default=dict))
        return
    print(f"# Board meter — {summary['company']} — {summary['at']}\n")
    print(f"- Open: {dict(summary['open'])}")
    print(f"- Last 24 h: {summary['runs_24h']} runs, {summary['failed_24h']} failed, {summary['tokens_read_24h_m']}M tokens read")
    print(f"- Running now: {', '.join(summary['live_runs']) or 'nothing'}")
    for h in host:
        print(f"- **Host:** {h}")
    print(f"\n## Flagged ({len(flagged)})\n")
    print("| Ticket | Status | Agent | Runs | Read | Flags |\n|---|---|---|---|---|---|")
    for r in flagged:
        fl = "; ".join(f"`{f['code']}` {f['detail']}" for f in r["flags"])
        print(f"| {r['id']}{' ← ' + r['parent'] if r['parent'] else ''} | {r['status']} | {r['agent']} | {r['runs']} | {r['tokens_read_m']:.0f}M | {fl} |")
    if "--all" in argv:
        print("\n## Not flagged\n")
        for r in rows:
            if not r["flags"] and r["open"]:
                print(f"- {r['id']} {r['status']} {r['agent']}: {r['title'][:70]}")


if __name__ == "__main__":
    main(sys.argv[1:])
