#!/usr/bin/env python3
# FRAMEWORK-OWNED — overwritten on every sync; do not edit (FWADR-014).
"""Render the framework's company package into this project's Paperclip company (FWADR-040).

The package lives at paperclip/ in the framework template: one AGENTS.md per role, each a
reading list. The role docs it names are fetched from the template's branch head on every run,
so a framework change reaches the agents at their next run; `sync` is needed only when the
package itself (an agent file, a routine) changes, and the Paperclip Lead's routine runs it. This script fills the package's placeholders
from the operator .env, creates or refreshes the FW_* agents and the recurring alignment
task, stamps the framework commit on each agent, and reports drift.

    scripts/paperclip_company.py status            # pinned commit vs the template's main; exit 1 on drift,
                                                   # 2 when it could not tell. With an agent's key it compares
                                                   # the package at the agent's own pin with the template's main
    scripts/paperclip_company.py sync [--dry-run]  # create or refresh the agents at the template's main
    scripts/paperclip_company.py pause             # the emergency switch: pause every FW_* agent. CANCELS their live runs;
                                                   # a cancelled run keeps only what it pushed
    scripts/paperclip_company.py resume            # resume them

Environment (the operator .env, sourced by claude-env; or an agent's own run credentials):
    PAPERCLIP_API_URL, PAPERCLIP_API_KEY      the board (or agent) credentials
    PAPERCLIP_COMPANY                         company name (default: PROJECT_NAME)
    PAPERCLIP_PLANNING_REPO                   planning repo path on the git host, e.g. draglabs/premium-ab
    PAPERCLIP_FRAMEWORK_REPO                  GitHub repo of the template (default draglabs/claude_template_yaml)
    PAPERCLIP_FRAMEWORK_REF                   branch to pin to (default main)
    PAPERCLIP_TEMPLATE_AGENT                  existing agent whose adapter and environment new agents copy (default Lead)
    PAPERCLIP_PLANNING_PROJECT                Paperclip project whose workspace is the planning repo (default Planning)
    PAPERCLIP_FUSE_BUDGET_CENTS               last-resort fuse: Paperclip's own monthly budget per FW_* agent, in cents.
                                              Paperclip CANCELS LIVE RUNS when it trips, so set it far above a normal
                                              month or leave it unset. The working cap is soft: PAPERCLIP_AGENT_BUDGET_CENTS,
                                              read by scripts/board_meter.py, which only reports.
    PAPERCLIP_FUSE_BUDGET_CENTS_<AGENT>       one agent's own fuse, e.g. PAPERCLIP_FUSE_BUDGET_CENTS_FW_DEVELOPER
    PAPERCLIP_PACKAGE_DIR                     template development only: read the package from this directory
                                              instead of GitHub (the pin still records the template's main)
    PROJECT_NAME, GIT_HOST, GIT_HOST_URL      from the project .env

Stdlib only; runs on a laptop or on the agent host. Never prints secrets.
"""
from __future__ import annotations

import hashlib
import json
import os
import re
import subprocess
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from datetime import datetime, timezone

ROLES = ["fw-paperclip-lead", "fw-strategist", "fw-orchestrator", "fw-parallel-developer", "fw-designer", "fw-curator"]
PAPERCLIP_ROLE = {"fw-paperclip-lead": "general", "fw-strategist": "cto", "fw-orchestrator": "pm",
                  "fw-parallel-developer": "engineer", "fw-designer": "designer", "fw-curator": "general"}
RETIRED = ["FW_Developer"]  # no longer in the package; never paused or removed from here (a pause cancels live runs)
HIRES = {"fw-paperclip-lead"}  # in Paperclip a lead hires: it may propose agents for the board to approve
TASKS = ["framework-alignment", "board-review"]
LABELS = {"str_question": "#7c3aed", "fdr_question": "#d97706", "fdr_blocked": "#dc2626", "lead_review": "#2563eb",
          "fdr_review_pending": "#059669", "fdr_qa_1": "#0891b2", "fdr_qa_2": "#0e7490"}  # who must act
MANAGED_BY = "scripts/paperclip_company.py"

E = os.environ.get
API = E("PAPERCLIP_API_URL", "").rstrip("/")
API = API + ("" if API.endswith("/api") else "/api")
KEY = E("PAPERCLIP_API_KEY", "")
COMPANY = E("PAPERCLIP_COMPANY") or E("PROJECT_NAME", "")
PLANNING_REPO = E("PAPERCLIP_PLANNING_REPO", "")
FW_REPO = E("PAPERCLIP_FRAMEWORK_REPO", "draglabs/claude_template_yaml")
FW_REF = E("PAPERCLIP_FRAMEWORK_REF", "main")
TEMPLATE_AGENT = E("PAPERCLIP_TEMPLATE_AGENT", "Lead")
GIT_HOST = E("GIT_HOST", "")
GIT_HOST_URL = (E("GIT_HOST_URL", "") or {"github": "https://github.com", "gitlab": "https://gitlab.com"}.get(GIT_HOST, "")).rstrip("/")


def die(msg: str) -> None:
    sys.exit(f"paperclip_company: {msg}")


TRANSIENT = (409, 502, 503, 504)  # what an agent's bridge answers when a request ran out of time


def api(method: str, path: str, body=None, soft: bool = False):
    """One API call. A read is tried three times on a transient answer; a write never is, because
    it may have landed. `soft` returns None instead of stopping the script."""
    data = json.dumps(body).encode() if body is not None else None
    tries = 3 if method == "GET" and not soft else 1
    for n in range(tries):
        req = urllib.request.Request(API + path, data=data, method=method,
                                     headers={"Authorization": "Bearer " + KEY, "Content-Type": "application/json"})
        try:
            with urllib.request.urlopen(req, timeout=60) as r:
                return json.load(r)
        except urllib.error.HTTPError as e:
            why = f"{e.code}: {e.read()[:300].decode(errors='replace')}"
            transient = e.code in TRANSIENT
        except (urllib.error.URLError, TimeoutError) as e:
            why, transient = str(e), True
        if transient and n + 1 < tries:
            time.sleep(5 * (n + 1))
            continue
        if soft:
            return None
        die(f"{method} {path} -> {why}" + (f" (after {tries} tries)" if tries > 1 else ""))


def framework_commit() -> str:
    out = subprocess.run(["git", "ls-remote", f"https://github.com/{FW_REPO}.git", f"refs/heads/{FW_REF}"],
                         capture_output=True, text=True)
    if out.returncode != 0 or not out.stdout.strip():
        die(f"cannot resolve {FW_REPO}@{FW_REF} via git ls-remote")
    return out.stdout.split()[0]


def fetch_package_file(commit: str, rel: str, at_pin: bool = False) -> str:
    local = E("PAPERCLIP_PACKAGE_DIR")  # template development: render an unpushed package from disk
    if local and not at_pin:
        p = os.path.join(local, rel)
        if not os.path.exists(p):
            die(f"package file {rel} not found under PAPERCLIP_PACKAGE_DIR={local}")
        with open(p) as f:
            return f.read()
    url = f"https://raw.githubusercontent.com/{FW_REPO}/{commit}/paperclip/{rel}"
    try:
        with urllib.request.urlopen(url) as r:
            return r.read().decode()
    except urllib.error.HTTPError as e:
        die(f"package file {rel} not found at {FW_REPO}@{commit[:12]} ({e.code})")


def split_frontmatter(text: str) -> tuple[dict, str]:
    """Tiny flat-YAML reader: top-level `key: value` lines only; nested blocks are kept raw."""
    m = re.match(r"^---\n(.*?)\n---\n(.*)$", text, re.S)
    if not m:
        return {}, text
    fm: dict = {}
    for line in m.group(1).splitlines():
        km = re.match(r"^([A-Za-z_]+):\s*(.*)$", line)
        if km:
            v = km.group(2).strip().strip('"')
            fm[km.group(1)] = None if v in ("null", "") else v
    return fm, m.group(2).lstrip("\n")


def fetch_project_docs_snippet() -> str:
    """Shell lines an agent runs to pull the planning repo's CLAUDE.md and exceptions file."""
    if not PLANNING_REPO:
        die("PAPERCLIP_PLANNING_REPO must name the planning repo (e.g. draglabs/premium-ab)")
    files = ["CLAUDE.md", "docs/framework_exceptions/dev_framework_exceptions.md"]
    lines = ["mkdir -p .fw && cd .fw"]
    if GIT_HOST == "gitlab":
        proj = urllib.parse.quote(PLANNING_REPO, safe="")
        for f in files:
            lines.append(f'curl -fsS -H "PRIVATE-TOKEN: ${{GITLAB_TOKEN}}" "{GIT_HOST_URL}/api/v4/projects/{proj}/repository/files/{urllib.parse.quote(f, safe="")}/raw?ref=main" -o "{os.path.basename(f)}"')
    elif GIT_HOST == "github":
        for f in files:
            lines.append(f'curl -fsSL -H "Authorization: token ${{GH_TOKEN}}" "https://raw.githubusercontent.com/{PLANNING_REPO}/main/{f}" -o "{os.path.basename(f)}"')
    else:
        die(f"GIT_HOST={GIT_HOST!r}: no fetch recipe; set GIT_HOST to github or gitlab")
    lines.append("cd ..")
    return "\n".join(lines)


def label_table(co: dict) -> str:
    """The label ids, for the agent files: an agent's key cannot list labels."""
    have = {l["name"]: l["id"] for l in api("GET", f"/companies/{co['id']}/labels")}
    rows = [f"| `{n}` | `{have.get(n, 'not created yet: run sync')}` |" for n in LABELS]
    return "\n".join(["| Label | id |", "|---|---|", *rows])


def render(text: str, commit: str, labels: str) -> str:
    return (text.replace("{{project_name}}", COMPANY)
                .replace("{{label_ids}}", labels)
                .replace("{{framework_repo}}", FW_REPO)
                .replace("{{framework_commit}}", commit)
                .replace("{{framework_ref}}", FW_REF)
                .replace("{{fetch_project_docs}}", fetch_project_docs_snippet()))


def sha256(s: str) -> str:
    return hashlib.sha256(s.encode()).hexdigest()


def load_company():
    # An agent's run credentials may not list companies (403) but know their own company id.
    if E("PAPERCLIP_COMPANY_ID"):
        co = api("GET", f"/companies/{E('PAPERCLIP_COMPANY_ID')}")
    else:
        cos = api("GET", "/companies")
        cos = cos if isinstance(cos, list) else cos.get("items", [])
        co = next((c for c in cos if c["name"].lower() == COMPANY.lower()), None) or die(f"company {COMPANY!r} not found")
    agents = api("GET", f"/companies/{co['id']}/agents")
    return co, {a["name"]: a for a in agents}


def load_agents(commit: str, co: dict) -> list[dict]:
    out, labels = [], label_table(co)
    for slug in ROLES:
        fm, body = split_frontmatter(fetch_package_file(commit, f"agents/{slug}/AGENTS.md"))
        out.append({"slug": slug, "name": fm.get("name") or slug, "title": fm.get("title"),
                    "reports_to": fm.get("reportsTo"), "content": render(body, commit, labels)})
    return out


def status_from_an_agent(me: dict, commit: str) -> int:
    """An agent's key cannot read the agents' files or the labels, and on a slow agent host the
    agent list does not answer in time. What it can tell: whether the package changed on the
    template since this agent was last synced. Hand edits on the board are not seen from here."""
    pinned = (me.get("metadata") or {}).get("framework_commit")
    if not pinned:
        print(f"could not tell: {me.get('name', 'this agent')} carries no framework pin — run sync with a board key")
        return 2
    def at(c: str, slug: str, at_pin: bool) -> str | None:
        try:
            return fetch_package_file(c, f"agents/{slug}/AGENTS.md", at_pin)
        except SystemExit:
            return None  # not in the package at that commit

    then = {slug: at(pinned, slug, True) for slug in ROLES}
    if not any(then.values()):
        print(f"could not tell: the package could not be read at this agent's pin {pinned[:12]}")
        return 2
    changed = [slug for slug in ROLES if then[slug] != at(commit, slug, False)]
    print(f"template {FW_REPO}@{FW_REF} = {commit[:12]}; {me.get('name', 'this agent')} last synced at {pinned[:12]}")
    if changed:
        print(f"DRIFT: the package changed since {pinned[:12]} ({', '.join(changed)}) — sync needs a board key")
        return 1
    print("aligned (package unchanged since the last sync; checked with an agent's key, the files on the board were not read)")
    return 0


def cmd_status() -> int:
    commit = framework_commit()
    me = api("GET", "/agents/me", soft=True)  # answers only for an agent's key
    if isinstance(me, dict) and me.get("id"):
        return status_from_an_agent(me, commit)
    co, by_name = load_company()
    drift = 0
    print(f"template {FW_REPO}@{FW_REF} = {commit[:12]}")
    for spec in load_agents(commit, co):
        a = by_name.get(spec["name"])
        if not a:
            print(f"DRIFT {spec['name']}: agent missing"); drift += 1; continue
        pinned = (a.get("metadata") or {}).get("framework_commit") or "?"
        bundle = api("GET", f"/agents/{a['id']}/instructions-bundle")
        have = {f["path"]: f["contentHash"] for f in bundle.get("files", [])}
        # Role docs are read at the template's branch head on every run, so only the package
        # (the agent's own file) can be behind; the stamp records the last sync.
        why = []
        if have.get("AGENTS.md") != sha256(spec["content"]): why.append("AGENTS.md differs from the rendered package")
        if why:
            drift += 1; print(f"DRIFT {spec['name']}: " + "; ".join(why))
        else:
            print(f"ok    {spec['name']}: last synced at {pinned[:12]}")
    print("aligned" if not drift else f"{drift} agent(s) drifted — run: scripts/paperclip_company.py sync")
    return 0 if not drift else 1


def budget_for(name: str) -> int | None:
    """An agent's fuse in cents (Paperclip's hard monthly budget); None = not set, leave the agent alone."""
    v = E("PAPERCLIP_FUSE_BUDGET_CENTS_" + name.upper()) or E("PAPERCLIP_FUSE_BUDGET_CENTS")
    return int(v) if v and v.strip().isdigit() else None


def cmd_lifecycle(verb: str) -> int:
    co, by_name = load_company()
    for name, a in sorted(by_name.items()):
        if (a.get("metadata") or {}).get("managed_by") != MANAGED_BY:
            continue
        api("POST", f"/agents/{a['id']}/{verb}")
        print(f"{verb}d {name}")
    return 0


def ensure_labels(co: dict, dry: bool) -> None:
    have = {l["name"] for l in api("GET", f"/companies/{co['id']}/labels")}
    for name, color in LABELS.items():
        if name not in have:
            print(f"label {name}: creating")
            if not dry:
                api("POST", f"/companies/{co['id']}/labels", {"name": name, "color": color})


def ensure_routine(co: dict, by_name: dict, slug_to_name: dict, commit: str, dry: bool) -> None:
    for slug in TASKS:
        fm, body = split_frontmatter(fetch_package_file(commit, f"tasks/{slug}/TASK.md"))
        title = fm.get("name") or slug
        assignee = by_name.get(slug_to_name.get(fm.get("assignee"), fm.get("assignee")))
        routines = api("GET", f"/companies/{co['id']}/routines")
        routines = routines if isinstance(routines, list) else routines.get("items", [])
        existing = next((r for r in routines if r.get("title") == title), None)
        desc = render(body, commit, label_table(co))
        if existing:
            if existing.get("description") != desc and not dry:
                api("PATCH", f"/routines/{existing['id']}", {"description": desc})
            print(f"routine {title!r}: {'refreshed' if existing.get('description') != desc else 'unchanged'}")
            continue
        print(f"routine {title!r}: creating (assignee {fm.get('assignee')})")
        if dry:
            continue
        sched = re.search(r'schedule:\s*"?([^"\n]+)"?', fetch_package_file(commit, f"tasks/{slug}/TASK.md"))
        tz = re.search(r"timezone:\s*(\S+)", fetch_package_file(commit, f"tasks/{slug}/TASK.md"))
        # The task runs in the planning repo's workspace: that project's env carries the git-host
        # token and its checkout carries scripts/. Matched by name (PAPERCLIP_PLANNING_PROJECT).
        projects = api("GET", f"/companies/{co['id']}/projects")
        projects = projects if isinstance(projects, list) else projects.get("items", [])
        planning = next((p for p in projects if p.get("name", "").lower() == E("PAPERCLIP_PLANNING_PROJECT", "Planning").lower()), None)
        if not planning:
            print(f"  WARN: no project named {E('PAPERCLIP_PLANNING_PROJECT', 'Planning')!r}; the task will run without a workspace")
        rt = api("POST", f"/companies/{co['id']}/routines", {
            "title": title, "description": desc, "assigneeAgentId": assignee["id"] if assignee else None,
            "projectId": planning["id"] if planning else None,
            "priority": fm.get("priority") or "low", "status": "active",
            "concurrencyPolicy": "skip_if_active", "catchUpPolicy": "skip_missed"})
        if sched:
            api("POST", f"/routines/{rt['id']}/triggers", {"kind": "schedule", "cronExpression": sched.group(1).strip(),
                                                           "timezone": tz.group(1) if tz else "UTC"})


def cmd_sync(dry: bool) -> int:
    commit = framework_commit()
    co, by_name = load_company()
    template = by_name.get(TEMPLATE_AGENT) or die(f"template agent {TEMPLATE_AGENT!r} not found in {COMPANY}; set PAPERCLIP_TEMPLATE_AGENT")
    adapter = {k: v for k, v in (template.get("adapterConfig") or {}).items() if not k.startswith("instructions")}
    runtime = {"heartbeat": {"enabled": False, "cooldownSec": 10, "intervalSec": 300, "wakeOnDemand": True,
                             "maxConcurrentRuns": 4, "skipTimerWhenNoActionableWork": True}}
    stamp = {"managed_by": MANAGED_BY, "framework_repo": FW_REPO, "framework_commit": commit,
             "stamped_at": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%MZ")}
    slug_to_name = {}
    ensure_labels(co, dry)  # before the agent files: they carry the label ids
    for spec in load_agents(commit, co):  # package order: managers before reports
        slug_to_name[spec["slug"]] = spec["name"]
        reports_to = by_name[slug_to_name[spec["reports_to"]]]["id"] if spec["reports_to"] else None
        meta = dict(stamp, framework_role=spec["slug"])
        budget = budget_for(spec["name"])
        if budget is not None:
            print(f"{spec['name']}: fuse ${budget / 100:.2f}/month — Paperclip cancels this agent's live runs if it trips")
        if spec["name"] in by_name:
            a = by_name[spec["name"]]
            bundle = api("GET", f"/agents/{a['id']}/instructions-bundle")
            have = {f["path"]: f for f in bundle.get("files", [])}
            changed = have.get("AGENTS.md", {}).get("contentHash") != sha256(spec["content"])
            print(f"{spec['name']}: {'refresh AGENTS.md' if changed else 'instructions unchanged'}; pin {commit[:12]}")
            if dry:
                continue
            if changed:
                body = {"path": "AGENTS.md", "content": spec["content"]}
                if "AGENTS.md" in have:
                    body["baseHash"] = have["AGENTS.md"]["contentHash"]
                api("PUT", f"/agents/{a['id']}/instructions-bundle/file", body)
            for extra in [p for p in have if p != "AGENTS.md"]:  # older copies of framework docs are not part of this model
                api("DELETE", f"/agents/{a['id']}/instructions-bundle/file?path={urllib.parse.quote(extra, safe='')}&baseHash={have[extra]['contentHash']}")
            patch = {"reportsTo": reports_to, "title": spec["title"], "metadata": meta}
            if budget is not None and a.get("budgetMonthlyCents") != budget:
                patch["budgetMonthlyCents"] = budget
            api("PATCH", f"/agents/{a['id']}", patch)
        else:
            print(f"{spec['name']}: creating; reports to {spec['reports_to']}; pin {commit[:12]}")
            if dry:
                by_name[spec["name"]] = {"id": "dry-run"}
                continue
            created = api("POST", f"/companies/{co['id']}/agents", {
                "name": spec["name"], "role": PAPERCLIP_ROLE[spec["slug"]], "title": spec["title"],
                "reportsTo": reports_to, "adapterType": template["adapterType"], "adapterConfig": adapter,
                "defaultEnvironmentId": template.get("defaultEnvironmentId"), "runtimeConfig": runtime,
                "permissions": {"canCreateAgents": spec["slug"] in HIRES, "canCreateSkills": False},
                **({"budgetMonthlyCents": budget} if budget is not None else {}),
                "instructionsBundle": {"entryFile": "AGENTS.md", "files": {"AGENTS.md": spec["content"]}},
                "metadata": meta})
            by_name[spec["name"]] = created
    for name in RETIRED:
        if (by_name.get(name, {}).get("metadata") or {}).get("managed_by") == MANAGED_BY:
            print(f"NOTE {name} is no longer part of the framework package: reassign its open issues to "
                  "FW_Parallel_Developer, then terminate it on the board when it is idle")
    ensure_routine(co, by_name, slug_to_name, commit, dry)
    print(f"pinned {FW_REPO}@{commit[:12]}")
    return 0


def main() -> None:
    if not API.startswith("http") or not KEY:
        die("PAPERCLIP_API_URL and PAPERCLIP_API_KEY must be set (source the operator .env)")
    if not COMPANY:
        die("PAPERCLIP_COMPANY or PROJECT_NAME must be set")
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    cmd = args[0] if args else "status"
    if cmd == "status":
        sys.exit(cmd_status())
    if cmd == "sync":
        sys.exit(cmd_sync("--dry-run" in sys.argv))
    if cmd in ("pause", "resume"):
        sys.exit(cmd_lifecycle(cmd))
    die(f"unknown command {cmd!r}; use status | sync [--dry-run] | pause | resume")


if __name__ == "__main__":
    main()
