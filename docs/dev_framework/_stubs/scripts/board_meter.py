#!/usr/bin/env python3
# FRAMEWORK-OWNED — overwritten on every sync; do not edit (FWADR-014).
"""The board meter: which Paperclip tickets look wasteful, from the records Paperclip keeps (FWADR-043).

    scripts/board_meter.py                 a short report (markdown), flagged tickets first
    scripts/board_meter.py --json          the same, as JSON, for an agent to read
    scripts/board_meter.py --all           include tickets with no flag
    scripts/board_meter.py --housekeep     clear what is stuck in the queue (below); quiet when nothing is

The report changes nothing: no run is stopped, no ticket is blocked. It costs no tokens, so it
can run as often as wanted; the board-review agent reads its output and decides what to do: the
Paperclip Lead (docs/dev_framework/paperclip-lead.md).

--housekeep is the one mode that acts, and only on work that is not running: it cancels a run
that has sat in the queue without starting (`queued-stale`) and wakes the ticket's current
assignee, and it wakes the assignee of a ticket that never got a run (`assigned-no-run`). It
never touches a run that has started. It needs a board key (cancel and wake are board
operations in Paperclip) and is meant to run hourly, with no agent, from a schedule the
project sets up. Exit 1 when an action was refused.

Waste is unuseful work, not cost: the flags are signs of unuseful work, and cost is shown as
information (runs, tokens read, spend) that flags nothing by itself.

Signals, and the reason code each one gives a ticket:
  retry-loop     2 or more failed runs in a row
  stalled        a live run older than LONG_RUN_MIN with no output for QUIET_MIN
  queued-stale   a run queued for QUEUED_MIN that never started; it holds its agent's slot
  assigned-no-run  `in_progress`, idle for ASSIGNED_MIN, and its assignee has never run it
  label-mismatch a `str_question` that is not assigned to FW_Strategist, or a `lead_review` that is
                 not assigned to FW_Paperclip_Lead (housekeeping moves it)
  blocked-unlabelled  `blocked` with none of the five labels: Paperclip blocked it after a failed
                 run, or an agent forgot to say who must act
The summary lists the tickets carrying `lead_review` (waiting for the Lead's post review) and the
ones waiting on the founder (`fdr_question`, `fdr_blocked`), and the closed tickets whose rundown the
founder has not read (`fdr_review_pending`).
  orphaned       `in_progress` with no live run for ORPHAN_HOURS
  waiting        `in_review` for WAIT_HOURS
  family         a ticket and everything split from it: more than FAMILY_SIZE tickets, or
                 children still open under a parent that is not running
  over-budget    recorded spend on the ticket past PAPERCLIP_TICKET_BUDGET_CENTS (when set)
The summary also lists agents whose recorded spend this month is past
PAPERCLIP_AGENT_BUDGET_CENTS. Both budgets are SOFT: this script reports, and no run is ended
or held back for a budget alone.
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
import urllib.error
import urllib.request
from pathlib import Path

def setting(name: str, default: float) -> float:
    return float(os.environ.get("BOARD_METER_" + name) or default)


LONG_RUN_MIN = setting("LONG_RUN_MIN", 45)
QUIET_MIN = setting("QUIET_MIN", 15)
QUEUED_MIN = setting("QUEUED_MIN", 10)
ASSIGNED_MIN = setting("ASSIGNED_MIN", 30)
ORPHAN_HOURS = setting("ORPHAN_HOURS", 24)
WAIT_HOURS = setting("WAIT_HOURS", 24)
FAMILY_SIZE = setting("FAMILY_SIZE", 3)
HOST_TASK_SHARE = setting("HOST_TASK_SHARE", 0.5)
TICKET_BUDGET_CENTS = float(os.environ.get("PAPERCLIP_TICKET_BUDGET_CENTS") or 0)  # 0 = no per-ticket cap
AGENT_BUDGET_CENTS = float(os.environ.get("PAPERCLIP_AGENT_BUDGET_CENTS") or 0)    # 0 = no per-agent monthly cap
OPEN = ("todo", "in_progress", "in_review", "blocked")
LABELS = ("str_question", "fdr_question", "fdr_blocked", "lead_review", "fdr_review_pending")
STRATEGIST = os.environ.get("BOARD_METER_STRATEGIST", "FW_Strategist")
LEAD = os.environ.get("BOARD_METER_LEAD", "FW_Paperclip_Lead")
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

    # An agent's key may not list companies or labels (403) but knows its own company id.
    if os.environ.get("PAPERCLIP_COMPANY_ID"):
        co = get(f"/companies/{os.environ['PAPERCLIP_COMPANY_ID']}")
    else:
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
    try:
        label_name = {l["id"]: l["name"] for l in get(f"/companies/{cid}/labels")}
    except urllib.error.HTTPError as e:
        if e.code != 403:
            raise
        # the names the tickets themselves carry; a list with no `labels` field means the checks cannot run
        label_name = {l["id"]: l["name"] for i in issues for l in i.get("labels") or [] if isinstance(l, dict) and l.get("name")}
    labels_readable = bool(label_name) or any(isinstance(i.get("labels"), list) for i in issues)
    strategist = next((a for a, n in agents.items() if n == STRATEGIST), None)
    lead = next((a for a, n in agents.items() if n == LEAD), None)

    def labels_of(i) -> set[str]:
        ids = i.get("labelIds") or [l.get("id") for l in i.get("labels") or []]
        return {label_name.get(x, "") for x in ids} & set(LABELS)
    runs = sorted(get(f"/companies/{cid}/heartbeat-runs?limit=1000"), key=lambda r: r.get("createdAt") or "")
    now = dt.datetime.now(dt.timezone.utc)

    def post(path: str, body: dict):
        req = urllib.request.Request(base + path, data=json.dumps(body).encode(), method="POST",
                                     headers={"Authorization": "Bearer " + key, "Content-Type": "application/json"})
        return urllib.request.urlopen(req, timeout=60).read()

    def is_stale_queued(r) -> bool:
        return (r.get("status") == "queued" and not r.get("startedAt")
                and (now - when(r["createdAt"])).total_seconds() / 60 > QUEUED_MIN)

    stat = collections.defaultdict(lambda: {"runs": 0, "cached": 0.0, "cost": 0.0, "streak": 0, "live": None,
                                            "last_run": None, "stale": []})
    busy = set()  # agents with a run that is really live
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
        if is_stale_queued(r):
            s["stale"].append(r)
        elif r.get("status") in ("running", "queued"):
            s["live"] = r
            busy.add(r.get("agentId"))

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
    never_ran = []  # issues whose current assignee has never run them
    misplaced = []  # (ticket, label, agent id, agent name): a label whose ticket is not on the agent it names
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
                flags.append(("stalled", f"run is {age:.0f} min old, no output for {quiet:.0f} min"))
        for r in s["stale"]:
            mins = (now - when(r["createdAt"])).total_seconds() / 60
            flags.append(("queued-stale", f"a run for {agents.get(r.get('agentId'), '?')} queued {mins:.0f} min ago never started"))
        who = i.get("assigneeAgentId")
        if (i["status"] == "in_progress" and who and not s["live"] and not s["stale"] and idle_h * 60 > ASSIGNED_MIN
                and (s["last_run"] is None or s["last_run"].get("agentId") != who)):
            flags.append(("assigned-no-run", f"assigned to {agents.get(who, '?')}, which has never run it"))
            never_ran.append(i)
        if i["status"] == "in_progress" and not s["live"] and idle_h > ORPHAN_HOURS:
            flags.append(("orphaned", f"in progress, no run for {idle_h / 24:.0f} days"))
        labs = labels_of(i)
        if is_open and "str_question" in labs and strategist and who != strategist:
            flags.append(("label-mismatch", f"str_question, but assigned to {agents.get(who, 'nobody')}"))
            misplaced.append((i, "str_question", strategist, STRATEGIST))
        if is_open and "lead_review" in labs and lead and who != lead:
            flags.append(("label-mismatch", f"lead_review, but assigned to {agents.get(who, 'nobody')}"))
            misplaced.append((i, "lead_review", lead, LEAD))
        if i["status"] == "blocked" and not labs and labels_readable:
            flags.append(("blocked-unlabelled", "blocked with no label saying who must act"))
        if i["status"] == "in_review" and "lead_review" not in labs and idle_h > WAIT_HOURS:
            flags.append(("waiting", f"in review for {idle_h / 24:.0f} days"))
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
                     "labels": sorted(labs), "flags": [{"code": c, "detail": d} for c, d in flags], "open": is_open})

    flagged = sorted((r for r in rows if r["flags"]), key=lambda r: (-len(r["flags"]), -r["tokens_read_m"]))
    host = host_findings()
    day = [r for r in runs if (now - (when(r.get("createdAt")) or now)).total_seconds() < 86400]
    summary = {
        "at": now.strftime("%Y-%m-%d %H:%M UTC"), "company": co["name"],
        "open": collections.Counter(r["status"] for r in rows if r["open"]),
        "runs_24h": len(day), "failed_24h": sum(1 for r in day if r.get("status") in BAD_RUN),
        # the agent ended its turn with a job still running; Paperclip calls it "Adapter failed"
        "left_job_24h": sum(1 for r in day if r.get("status") in BAD_RUN and (
            (r.get("resultJson") or {}).get("unmanagedBackgroundTask") or r.get("error") == "Adapter failed")),
        "tokens_read_24h_m": round(sum(num(r.get("cachedInputTokens")) for r in day) / 1e6),
        "live_runs": [f"{by[r['issueId']]['identifier']} ({agents.get(r.get('agentId'), '?')})" for r in runs
                      if r.get("status") in ("running", "queued") and r.get("issueId") in by and not is_stale_queued(r)],
        "host": host, "labels_readable": labels_readable,
        "lead_review": [r["id"] for r in rows if r["open"] and "lead_review" in r["labels"]],
        "founder_to_read": [r["id"] for r in rows if "fdr_review_pending" in r["labels"]],
        "waiting_on_founder": [r["id"] for r in rows if r["open"] and {"fdr_question", "fdr_blocked"} & set(r["labels"])],
    }
    month = collections.Counter()
    for r in runs:
        if (r.get("createdAt") or "")[:7] == now.strftime("%Y-%m"):
            month[agents.get(r.get("agentId"), "?")] += num(r.get("costUsd")) * 100
    summary["agents_over_budget"] = [f"{a} (${c / 100:.2f} of ${AGENT_BUDGET_CENTS / 100:.2f} this month)"
                                     for a, c in sorted(month.items()) if AGENT_BUDGET_CENTS and c > AGENT_BUDGET_CENTS]
    if "--housekeep" in argv:
        failed = False

        def act(what: str, path: str, body: dict) -> bool:
            try:
                post(path, body)
                print(f"housekeep: {what}")
                return True
            except urllib.error.HTTPError as e:
                print(f"housekeep: REFUSED ({e.code}) {what}")
                return False

        def wake(issue, why: str) -> bool:
            who = issue.get("assigneeAgentId")
            if not who or issue["status"] not in OPEN or who in busy:
                return True  # nobody to wake, or its one slot is in use: the next pass looks again
            busy.add(who)
            return act(f"woke {agents.get(who, '?')} for {issue['identifier']} ({why})", f"/agents/{who}/wakeup",
                       {"source": "automation", "reason": why, "payload": {"issueId": issue["id"]}})

        for i in issues:
            for r in stat[i["id"]]["stale"]:
                ok = act(f"cancelled a run queued for {agents.get(r.get('agentId'), '?')} on {i['identifier']} that never started",
                         f"/heartbeat-runs/{r['id']}/cancel", {})
                failed |= not ok
                if ok:
                    failed |= not wake(i, "queued-stale")
        for i in never_ran:
            failed |= not wake(i, "assigned-no-run")
        for i, label, target, target_name in misplaced:  # an assignment is what wakes the agent the label names
            try:
                req = urllib.request.Request(base + f"/issues/{i['id']}", data=json.dumps({"assigneeAgentId": target}).encode(),
                                             method="PATCH", headers={"Authorization": "Bearer " + key, "Content-Type": "application/json"})
                urllib.request.urlopen(req, timeout=60).read()
                print(f"housekeep: moved {i['identifier']} ({label}) to {target_name}")
            except urllib.error.HTTPError as e:
                print(f"housekeep: REFUSED ({e.code}) moving {i['identifier']} to {target_name}")
                failed = True
        sys.exit(1 if failed else 0)
    if "--json" in argv:
        print(json.dumps({"summary": summary, "flagged": flagged, "all": rows if "--all" in argv else None}, indent=1, default=dict))
        return
    print(f"# Board meter — {summary['company']} — {summary['at']}\n")
    print(f"- Open: {dict(summary['open'])}")
    print(f"- Last 24 h: {summary['runs_24h']} runs, {summary['failed_24h']} failed ({summary['left_job_24h']} ended with a background job still running), {summary['tokens_read_24h_m']}M tokens read")
    print(f"- Running now: {', '.join(summary['live_runs']) or 'nothing'}")
    if not summary["labels_readable"]:
        print("- **Labels could not be read with this key:** the label checks did not run")
    print(f"- Waiting for post review (`lead_review`): {', '.join(summary['lead_review']) or 'nothing'}")
    print(f"- Waiting on the founder: {', '.join(summary['waiting_on_founder']) or 'nothing'}")
    print(f"- Closed, rundown not yet read by the founder (`fdr_review_pending`): {', '.join(summary['founder_to_read']) or 'nothing'}")
    for h in host:
        print(f"- **Host:** {h}")
    for a in summary["agents_over_budget"]:
        print(f"- **Over its monthly budget (soft):** {a}")
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
