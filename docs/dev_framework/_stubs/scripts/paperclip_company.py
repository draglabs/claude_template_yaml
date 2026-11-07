#!/usr/bin/env python3
# FRAMEWORK-OWNED — overwritten on every sync; do not edit (FWADR-014).
"""Render the framework's company package into this project's Paperclip company (FWADR-040).

The package lives at paperclip/ in the framework template: one AGENTS.md per role, each a
reading list pinned to a framework commit. This script fills the package's placeholders
from the operator .env, creates or refreshes the FW_* agents and the recurring alignment
task, stamps the framework commit on each agent, and reports drift.

    scripts/paperclip_company.py status            # pinned commit vs the template's main; exit 1 on drift
    scripts/paperclip_company.py sync [--dry-run]  # create or refresh the agents at the template's main

Environment (the operator .env, sourced by claude-env; or an agent's own run credentials):
    PAPERCLIP_API_URL, PAPERCLIP_API_KEY      the board (or agent) credentials
    PAPERCLIP_COMPANY                         company name (default: PROJECT_NAME)
    PAPERCLIP_PLANNING_REPO                   planning repo path on the git host, e.g. draglabs/premium-ab
    PAPERCLIP_FRAMEWORK_REPO                  GitHub repo of the template (default draglabs/claude_template_yaml)
    PAPERCLIP_FRAMEWORK_REF                   branch to pin to (default main)
    PAPERCLIP_TEMPLATE_AGENT                  existing agent whose adapter and environment new agents copy (default Lead)
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
import urllib.error
import urllib.parse
import urllib.request
from datetime import datetime, timezone

ROLES = ["fw-strategist", "fw-orchestrator", "fw-developer", "fw-parallel-developer", "fw-designer", "fw-curator"]
PAPERCLIP_ROLE = {"fw-strategist": "cto", "fw-orchestrator": "pm", "fw-developer": "engineer",
                  "fw-parallel-developer": "engineer", "fw-designer": "designer", "fw-curator": "general"}
TASKS = ["framework-alignment"]
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


def api(method: str, path: str, body=None):
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(API + path, data=data, method=method,
                                 headers={"Authorization": "Bearer " + KEY, "Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req) as r:
            return json.load(r)
    except urllib.error.HTTPError as e:
        die(f"{method} {path} -> {e.code}: {e.read()[:300].decode(errors='replace')}")


def framework_commit() -> str:
    out = subprocess.run(["git", "ls-remote", f"https://github.com/{FW_REPO}.git", f"refs/heads/{FW_REF}"],
                         capture_output=True, text=True)
    if out.returncode != 0 or not out.stdout.strip():
        die(f"cannot resolve {FW_REPO}@{FW_REF} via git ls-remote")
    return out.stdout.split()[0]


def fetch_package_file(commit: str, rel: str) -> str:
    local = E("PAPERCLIP_PACKAGE_DIR")  # template development: render an unpushed package from disk
    if local:
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


def render(text: str, commit: str) -> str:
    return (text.replace("{{project_name}}", COMPANY)
                .replace("{{framework_repo}}", FW_REPO)
                .replace("{{framework_commit}}", commit)
                .replace("{{fetch_project_docs}}", fetch_project_docs_snippet()))


def sha256(s: str) -> str:
    return hashlib.sha256(s.encode()).hexdigest()


def load_company():
    cos = api("GET", "/companies")
    cos = cos if isinstance(cos, list) else cos.get("items", [])
    co = next((c for c in cos if c["name"].lower() == COMPANY.lower()), None) or die(f"company {COMPANY!r} not found")
    agents = api("GET", f"/companies/{co['id']}/agents")
    return co, {a["name"]: a for a in agents}


def load_agents(commit: str) -> list[dict]:
    out = []
    for slug in ROLES:
        fm, body = split_frontmatter(fetch_package_file(commit, f"agents/{slug}/AGENTS.md"))
        out.append({"slug": slug, "name": fm.get("name") or slug, "title": fm.get("title"),
                    "reports_to": fm.get("reportsTo"), "content": render(body, commit)})
    return out


def cmd_status() -> int:
    commit = framework_commit()
    co, by_name = load_company()
    drift = 0
    print(f"template {FW_REPO}@{FW_REF} = {commit[:12]}")
    for spec in load_agents(commit):
        a = by_name.get(spec["name"])
        if not a:
            print(f"DRIFT {spec['name']}: agent missing"); drift += 1; continue
        pinned = (a.get("metadata") or {}).get("framework_commit") or "?"
        bundle = api("GET", f"/agents/{a['id']}/instructions-bundle")
        have = {f["path"]: f["contentHash"] for f in bundle.get("files", [])}
        why = []
        if pinned != commit: why.append(f"pinned {pinned[:12]}")
        if have.get("AGENTS.md") != sha256(spec["content"]): why.append("AGENTS.md differs from the rendered package")
        if why:
            drift += 1; print(f"DRIFT {spec['name']}: " + "; ".join(why))
        else:
            print(f"ok    {spec['name']}: pinned {pinned[:12]}")
    print("aligned" if not drift else f"{drift} agent(s) drifted — run: scripts/paperclip_company.py sync")
    return 0 if not drift else 1


def ensure_routine(co: dict, by_name: dict, commit: str, dry: bool) -> None:
    for slug in TASKS:
        fm, body = split_frontmatter(fetch_package_file(commit, f"tasks/{slug}/TASK.md"))
        title = fm.get("name") or slug
        assignee = by_name.get({"fw-curator": "FW_Curator"}.get(fm.get("assignee"), fm.get("assignee")))
        routines = api("GET", f"/companies/{co['id']}/routines")
        routines = routines if isinstance(routines, list) else routines.get("items", [])
        existing = next((r for r in routines if r.get("title") == title), None)
        desc = render(body, commit)
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
        rt = api("POST", f"/companies/{co['id']}/routines", {
            "title": title, "description": desc, "assigneeAgentId": assignee["id"] if assignee else None,
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
    for spec in load_agents(commit):  # package order: managers before reports
        slug_to_name[spec["slug"]] = spec["name"]
        reports_to = by_name[slug_to_name[spec["reports_to"]]]["id"] if spec["reports_to"] else None
        meta = dict(stamp, framework_role=spec["slug"])
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
                api("DELETE", f"/agents/{a['id']}/instructions-bundle/file?path={urllib.parse.quote(extra, safe='')}")
            api("PATCH", f"/agents/{a['id']}", {"reportsTo": reports_to, "title": spec["title"], "metadata": meta})
        else:
            print(f"{spec['name']}: creating; reports to {spec['reports_to']}; pin {commit[:12]}")
            if dry:
                by_name[spec["name"]] = {"id": "dry-run"}
                continue
            created = api("POST", f"/companies/{co['id']}/agents", {
                "name": spec["name"], "role": PAPERCLIP_ROLE[spec["slug"]], "title": spec["title"],
                "reportsTo": reports_to, "adapterType": template["adapterType"], "adapterConfig": adapter,
                "defaultEnvironmentId": template.get("defaultEnvironmentId"), "runtimeConfig": runtime,
                "permissions": {"canCreateAgents": False, "canCreateSkills": False},
                "instructionsBundle": {"entryFile": "AGENTS.md", "files": {"AGENTS.md": spec["content"]}},
                "metadata": meta})
            by_name[spec["name"]] = created
    ensure_routine(co, by_name, commit, dry)
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
    die(f"unknown command {cmd!r}; use status | sync [--dry-run]")


if __name__ == "__main__":
    main()
