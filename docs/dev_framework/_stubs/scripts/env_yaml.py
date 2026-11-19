#!/usr/bin/env python3
# Seed-once stub (FWADR-014): copied when missing, never overwritten. Adapt it to the project.
"""env.yaml: every env value the project shares, and the places each one goes (FWADR-041).

Run from $PROJECT_DIR, on the machine that holds the age key (.sops-age-key.txt).

    scripts/env_yaml.py init                      create the key, .sops.yaml, editor config and an empty env.yaml
    scripts/env_yaml.py import <envfile> [--places=operator]
                                                  file every KEY=value of a hand-written .env (names printed, never values)
    scripts/env_yaml.py map                       table: name -> secret or plain -> places (no values)
    scripts/env_yaml.py check                     validate the file (decrypts it; prints no value)
    scripts/env_yaml.py place <name> kind=<kind> key=value ...
                                                  declare or redefine a place
    scripts/env_yaml.py set <NAME> [--places=a,b] [--plain] [--not-secret] [--file] [--note=text] [--from=<envfile>]
                                                  set one value, read from stdin or taken from <envfile>;
                                                  --file: a multi-line value (an ssh key) delivered to CI
                                                  as a file-type variable
    scripts/env_yaml.py route <NAME> <a,b|none> [--item=N]
                                                  change where an item goes; its value is untouched
    scripts/env_yaml.py unset <NAME> [--item=N]   remove an item (or the name, when it is the last one)
    scripts/env_yaml.py render [--take-over] [--dry-run]
                                                  write every env-file place's generated block
    scripts/env_yaml.py deliver --all | --since=<git ref> [--places=a,b] [--dry-run]
                                                  write values to CI variables, Paperclip and env files
(flags take their value with '=')

The file:

    places:                                   # a place is a name declared here
      operator:  {kind: env-file, path: .env}
      app-dev:   {kind: ci-variables, repo: group/app, scope: dev}
      app-prod:  {kind: ci-variables, repo: group/app, scope: prod}
      paperclip: {kind: paperclip, company: myproject}
    vars:
      APP_SECRET_KEY:                         # one item per distinct value
        - value: ENC[...]                     # a secret: the only encrypted field
          places: [app-dev, paperclip]
        - value: ENC[...]
          places: [app-prod]
      SERVER_DEV:
        - plain: 203.0.113.7                  # not a secret: readable in the file and in every diff
          places: [all]                       # every declared place
      OLD_VENDOR_TOKEN:
        - value: ENC[...]                     # no places: recorded, delivered nowhere

A plain item whose name looks like a secret must also say `secret: false`. Changing the file
delivers nothing; `deliver` does, and `--since=HEAD` is "what I just edited". Start with
--dry-run: it lists what would change by name and place and writes nothing. Values never reach
argv, a log or a temp file.

Place kinds, and the credential each uses (the environment first, else the file's own values
routed to the `.env` place):
  env-file      path (relative to $PROJECT_DIR). The generated block between the `# >>> env.yaml`
                and `# <<< env.yaml` lines is rewritten; every other line is kept.
  ci-variables  repo, scope (default *), protected (default true), masked (default auto).
                GitLab only: GITLAB_TOKEN or a `glab` login; GIT_HOST_URL for self-hosted.
  paperclip     company, [projects]. PAPERCLIP_API_URL and PAPERCLIP_API_KEY. A secret becomes a
                company secret bound into each project's env; a plain value is written into each
                project's env. Paperclip never returns a value, so every delivery rotates.

Stdlib only; needs `sops` and `age` (brew install sops age).
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
from pathlib import Path

PROJECT_DIR = Path.cwd()
FILE = PROJECT_DIR / "env.yaml"
KEY_FILE = PROJECT_DIR / ".sops-age-key.txt"
KINDS = ("env-file", "ci-variables", "paperclip")
ITEM_FIELDS = {"value", "plain", "places", "note", "secret", "file"}
NAME = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*$")
# The same two patterns are in .claude/hooks/git-guard-pre-push.sh; change them together.
SECRET_NAME = re.compile(r"SECRET|TOKEN|PASSWORD|PASSWD|PRIVATE|CREDENTIAL|_KEY($|_)|DATABASE_URL")
VALUE_LINE = re.compile(r"^\s*(?:-\s+)?value:\s*(.*)$")
# What recovers or unlocks the key cannot sit behind the key.
NEVER_IN_FILE = {"BITWARDEN_MACHINE_ACCESS", "SOPS_AGE_KEY", "SOPS_AGE_KEY_FILE"}
BEGIN, END = "# >>> env.yaml", "# <<< env.yaml"
GITIGNORE = (".sops-age-key.txt", ".decrypted~*", "env.yaml.bak")


def die(msg: str) -> None:
    print(f"error: {msg}", file=sys.stderr)
    sys.exit(1)


def log(msg: str) -> None:
    print(msg, flush=True)


# ---------------------------------------------------------------- sops

def sops_env() -> dict[str, str]:
    env = dict(os.environ)
    if "SOPS_AGE_KEY_FILE" not in env and "SOPS_AGE_KEY" not in env and KEY_FILE.exists():
        env["SOPS_AGE_KEY_FILE"] = str(KEY_FILE)
    return env


def sops(*args: str, stdin: str | None = None) -> str:
    try:
        r = subprocess.run(["sops", *args], cwd=PROJECT_DIR, env=sops_env(), input=stdin, capture_output=True, text=True)
    except FileNotFoundError:
        die("sops is not installed (brew install sops age)")
    if r.returncode != 0:
        tail = r.stderr.strip().splitlines()[-1] if r.stderr.strip() else str(r.returncode)
        die(f"sops {args[0]} failed: {tail}")
    return r.stdout


# ---------------------------------------------------------------- the document

def plaintext_secrets(raw: str) -> list[int]:
    """Line numbers of `value:` fields that are not ciphertext."""
    bad = []
    for n, line in enumerate(raw.splitlines(), 1):
        m = VALUE_LINE.match(line)
        if m and not m.group(1).startswith("ENC[AES256_GCM,") and m.group(1).strip() not in ('""', "''"):
            bad.append(n)
    return bad


class Doc:
    """The decrypted file, validated. `routes[place][name]` is (value, is_plain)."""

    def __init__(self, data, where: str) -> None:
        errors: list[str] = []
        if not isinstance(data, dict) or not isinstance(data.get("places"), dict) or not isinstance(data.get("vars") or {}, dict):
            die(f"{where}: expected a mapping with `places` and `vars`")
        self.places: dict[str, dict] = data["places"]
        self.vars: dict[str, list[dict]] = data.get("vars") or {}
        self.routes: dict[str, dict[str, tuple[str, bool]]] = {p: {} for p in self.places}
        self.files: set[str] = set()  # names delivered to CI as file-type variables
        for name, p in self.places.items():
            if name == "all":
                errors.append("`all` is reserved and cannot be a place name")
            if not isinstance(p, dict) or p.get("kind") not in KINDS:
                errors.append(f"place {name!r} needs kind in {KINDS}"); continue
            need = {"env-file": "path", "ci-variables": "repo", "paperclip": "company"}[p["kind"]]
            if not p.get(need):
                errors.append(f"place {name!r} ({p['kind']}) needs `{need}`")
            if p["kind"] == "env-file" and p.get("path"):
                target = (PROJECT_DIR / str(p["path"])).resolve()
                if Path(str(p["path"])).is_absolute() or PROJECT_DIR.resolve() not in target.parents:
                    errors.append(f"place {name!r}: path must stay inside the project directory (hosts are built at deploy)")
        for key, items in self.vars.items():
            if not NAME.match(str(key)):
                errors.append(f"{key!r} is not a variable name"); continue
            if key in NEVER_IN_FILE:
                errors.append(f"{key} is never an entry in env.yaml; it stays in the hand-kept part of .env")
            if not isinstance(items, list) or not items:
                errors.append(f"{key}: needs a list of at least one item"); continue
            for i, item in enumerate(items):
                at = f"{key}[{i}]"
                if not isinstance(item, dict):
                    errors.append(f"{at}: must be a mapping"); continue
                if ("value" in item) == ("plain" in item):
                    errors.append(f"{at}: needs exactly one of `value` (secret) or `plain`"); continue
                extra = set(item) - ITEM_FIELDS
                if extra:
                    errors.append(f"{at}: unknown field(s) {sorted(extra)}")
                is_plain = "plain" in item
                if item.get("file"):
                    self.files.add(key)
                if is_plain and SECRET_NAME.search(key.upper()) and item.get("secret") is not False:
                    errors.append(f"{at}: the name looks like a secret but the item is `plain`; use `value`, or add `secret: false`")
                raw = item["plain"] if is_plain else item["value"]
                value = "" if raw is None else (str(raw).lower() if isinstance(raw, bool) else str(raw))
                names = item.get("places") or []
                if not isinstance(names, list):
                    errors.append(f"{at}: `places` must be a list"); continue
                for p in (list(self.places) if "all" in names else names):
                    if p not in self.places:
                        errors.append(f"{at}: {p!r} is not a declared place")
                    elif key in self.routes[p]:
                        errors.append(f"{key}: two items go to place {p!r}")
                    else:
                        if self.places[p].get("kind") == "env-file" and ("'" in value or "\n" in value):
                            errors.append(f"{at}: a value with a quote or newline cannot go to env file {p!r}")
                        self.routes[p][key] = (value, is_plain)
        if errors:
            die(f"{where}:\n  " + "\n  ".join(errors))

    def credential(self, *names: str) -> str:
        """A credential by name: the environment first, then what the file routes to the `.env` place."""
        for n in names:
            v = os.environ.get(n, "").strip()
            if not v:
                for p, spec in self.places.items():
                    if spec["kind"] == "env-file" and str(spec["path"]) == ".env" and n in self.routes[p]:
                        v = self.routes[p][n][0].strip()
            if v:
                return v
        return ""


def load() -> Doc:
    if not FILE.exists():
        die(f"no env.yaml in {PROJECT_DIR} (run from $PROJECT_DIR; `init` creates one)")
    bad = plaintext_secrets(FILE.read_text())
    if bad:
        die(f"env.yaml: `value` on line(s) {bad} is not encrypted. Do not commit; re-enter it with `set`, or edit with `sops env.yaml`")
    return Doc(json.loads(sops("-d", "--output-type", "json", FILE.name)), "env.yaml")


def doc_at(ref: str) -> Doc | None:
    r = subprocess.run(["git", "show", f"{ref}:env.yaml"], cwd=PROJECT_DIR, capture_output=True, text=True)
    if r.returncode != 0:
        return None  # not there at that ref: everything is new
    try:
        return Doc(json.loads(sops("-d", "--input-type", "yaml", "--output-type", "json", "/dev/stdin", stdin=r.stdout)), f"{ref}:env.yaml")
    except SystemExit:
        log(f"note: env.yaml at {ref} is unreadable or has another layout; treating everything as changed")
        return None


# ---------------------------------------------------------------- env files

def dotenv_assignments(text: str) -> dict[str, str]:
    """KEY=value lines that start in column 0; indented lines (shell blocks) are not assignments."""
    out = {}
    for line in text.splitlines():
        m = re.match(r"^(?:export\s+)?([A-Za-z_][A-Za-z0-9_]*)=(.*)$", line)
        if m:
            v = m.group(2).strip()
            if len(v) >= 2 and v[0] == v[-1] and v[0] in "'\"":
                v = v[1:-1]
            out[m.group(1)] = v
    return out


def render_place(doc: Doc, place: str, take_over: bool, dry: bool) -> None:
    path = PROJECT_DIR / str(doc.places[place]["path"])
    if not path.parent.is_dir():
        log(f"  {place}: {path.parent} is not on this machine; skipped"); return
    keys = doc.routes[place]
    stamp = hashlib.sha256(FILE.read_bytes()).hexdigest()[:16]
    block = [f"{BEGIN} {stamp} (generated by scripts/env_yaml.py; change env.yaml, never this block)"]
    block += [f"{k}='{v}'" for k, (v, _) in sorted(keys.items())] + [END]
    existing = path.read_text() if path.exists() else ""
    kept, inside, had_block = [], False, False
    for line in existing.splitlines():
        if line.startswith(BEGIN):
            inside = had_block = True
        elif line.startswith(END):
            inside = False
        elif not inside:
            kept.append(line)
    clash = sorted(set(dotenv_assignments("\n".join(kept))) & set(keys))
    if clash and not take_over:
        die(f"{place}: {path.name} also sets {', '.join(clash)} by hand, which would override env.yaml. "
            "Delete those lines, or re-run with --take-over to drop them")
    if clash:
        kept = [ln for ln in kept if not any(re.match(rf"^(?:export\s+)?{k}=", ln) for k in clash)]
    while kept and not kept[0].strip():
        kept.pop(0)
    new = "\n".join(block + ([""] + kept if kept else [])) + "\n"
    if new == existing:
        log(f"  {place}: {path.name} is current"); return
    log(f"  {place}: write {len(keys)} value(s) into {path.relative_to(PROJECT_DIR)}"
        + (f"; dropped hand lines for {', '.join(clash)}" if clash else "") + ("" if had_block else " (first generated block)"))
    if dry:
        return
    tmp = path.with_name(path.name + ".new")
    tmp.write_text(new); tmp.chmod(0o600); tmp.replace(path)


# ---------------------------------------------------------------- CI variables (GitLab)

def http(method: str, url: str, headers: dict, data: bytes | None = None) -> tuple[int, object]:
    req = urllib.request.Request(url, method=method, data=data, headers=headers)
    try:
        with urllib.request.urlopen(req, timeout=60) as r:
            return r.status, json.loads(r.read() or b"null")
    except urllib.error.HTTPError as e:
        return e.code, e.read().decode()[:300]


def deliver_ci(doc: Doc, place: str, keys: dict[str, tuple[str, bool]], dry: bool) -> None:
    t = doc.places[place]
    host = doc.credential("GIT_HOST") or "gitlab"
    if host != "gitlab":
        die(f"{place}: ci-variables is implemented for GitLab only (GIT_HOST={host}); set those variables on the host by hand (FWADR-041 names this gap)")
    api = (doc.credential("GIT_HOST_URL").rstrip("/") or "https://gitlab.com") + "/api/v4"
    token = doc.credential("SECRETS_GITLAB_TOKEN", "GITLAB_TOKEN")
    if not token:
        try:
            token = subprocess.run(["glab", "config", "get", "token", "--host", urllib.parse.urlparse(api).hostname or ""],
                                   capture_output=True, text=True).stdout.strip()
        except FileNotFoundError:
            token = ""
    if not token:
        die(f"{place}: needs GITLAB_TOKEN (environment or env.yaml) or a `glab` login")
    H = {"PRIVATE-TOKEN": token}
    proj, scope, protected = urllib.parse.quote(str(t["repo"]), safe=""), str(t.get("scope", "*")), t.get("protected", True)
    have, page = {}, 1
    while True:
        st, out = http("GET", f"{api}/projects/{proj}/variables?per_page=100&page={page}", H)
        if st != 200:
            die(f"{place}: listing variables of {t['repo']}: {st} {out}")
        have.update({(v["key"], v["environment_scope"]): v for v in out})
        if len(out) < 100:
            break
        page += 1
    for k, (v, _) in sorted(keys.items()):
        is_file = k in doc.files
        if is_file and not v.endswith("\n"):
            v += "\n"  # OpenSSH refuses a key whose last line has no newline
        masked = t.get("masked", "auto")
        if masked == "auto":  # GitLab refuses to mask short values and values with spaces or newlines
            masked = len(v) >= 8 and "\n" not in v and " " not in v
        cur = have.get((k, scope))
        if cur and cur["value"] == v and cur["protected"] == protected:
            log(f"  {place}: {t['repo']} {k} [{scope}] unchanged"); continue
        log(f"  {place}: {'update' if cur else 'create'} {t['repo']} {k} [{scope}]")
        if dry:
            continue
        body = {"value": v, "protected": "true" if protected else "false", "masked": "true" if masked else "false", "environment_scope": scope,
                "variable_type": "file" if is_file else "env_var"}
        if cur:
            st, out = http("PUT", f"{api}/projects/{proj}/variables/{k}?filter[environment_scope]={urllib.parse.quote(scope)}", H, urllib.parse.urlencode(body).encode())
        else:
            st, out = http("POST", f"{api}/projects/{proj}/variables", H, urllib.parse.urlencode({**body, "key": k}).encode())
        if st not in (200, 201):
            die(f"{place}: {k}: {st} {out}")


# ---------------------------------------------------------------- Paperclip

def deliver_paperclip(doc: Doc, place: str, keys: dict[str, tuple[str, bool]], dry: bool) -> None:
    t = doc.places[place]
    base = (doc.credential("PAPERCLIP_API_URL") or die(f"{place}: needs PAPERCLIP_API_URL")).rstrip("/") + "/api"
    H = {"Authorization": "Bearer " + (doc.credential("PAPERCLIP_API_KEY") or die(f"{place}: needs PAPERCLIP_API_KEY")),
         "Content-Type": "application/json"}

    def call(method, path, body=None):
        return http(method, base + path, H, None if body is None else json.dumps(body).encode())

    st, companies = call("GET", "/companies")
    if st != 200:
        die(f"{place}: listing companies: {st}")
    company = next((c for c in companies if c.get("name", "").lower() == str(t["company"]).lower()), None) or die(f"{place}: company {t['company']!r} not found")
    st, secrets = call("GET", f"/companies/{company['id']}/secrets")
    if st != 200:
        die(f"{place}: listing secrets: {st}")
    have = {s["name"]: s for s in (secrets if isinstance(secrets, list) else secrets.get("items", []))}
    refs: dict[str, str] = {}
    for k, (v, plain) in sorted(keys.items()):
        if plain:
            continue
        # Paperclip never returns a value, so "unchanged" cannot be seen: every delivery rotates.
        log(f"  {place}: {'rotate' if k in have else 'create'} Paperclip secret {k}")
        if k in have:
            refs[k] = have[k]["id"]
        if dry:
            continue
        if k in have:
            st, out = call("POST", f"/secrets/{have[k]['id']}/rotate", {"value": v})
        else:
            st, out = call("POST", f"/companies/{company['id']}/secrets", {"name": k, "value": v, "description": "delivered from env.yaml (FWADR-041)"})
            if st in (200, 201) and isinstance(out, dict):
                refs[k] = out.get("id", "")
        if st not in (200, 201):
            die(f"{place}: {k}: {st} {out}")

    # An agent's run gets a value only through its project's env: bind every value into it.
    st, projects = call("GET", f"/companies/{company['id']}/projects")
    if st != 200:
        die(f"{place}: listing projects: {st}")
    wanted = t.get("projects")
    for p in projects:
        if (wanted and p["name"] not in wanted) or (not wanted and not p.get("env")):
            continue
        env, changed = dict(p.get("env") or {}), []
        for k, (v, plain) in sorted(keys.items()):
            cur = env.get(k) or {}
            if plain:
                entry = {"type": "plain", "value": v}
            elif cur.get("type") == "secret_ref" and (cur.get("secretId") == refs.get(k) or (dry and k not in refs)):
                continue
            else:
                entry = {"type": "secret_ref", "secretId": refs.get(k, ""), "version": "latest"}
            if cur != entry:
                env[k] = entry; changed.append(k)
        if not changed:
            continue
        log(f"  {place}: bind into project {p['name']}: {', '.join(changed)}")
        if dry:
            continue
        st, out = call("PATCH", f"/projects/{p['id']}", {"env": env})
        if st not in (200, 201):
            die(f"{place}: project {p['name']}: {st} {out}")


# ---------------------------------------------------------------- commands

def flags_of(argv: list[str]) -> tuple[dict[str, str], list[str]]:
    flags = {a.split("=", 1)[0]: (a.split("=", 1)[1] if "=" in a else "") for a in argv if a.startswith("--")}
    return flags, [a for a in argv if not a.startswith("--")]


def csv(flags: dict[str, str], name: str) -> list[str]:
    return [x for x in flags.get(name, "").split(",") if x]


def cmd_map() -> None:
    doc = load()
    width = max((len(k) for k in doc.vars), default=8)
    for k in sorted(doc.vars):
        for n, item in enumerate(doc.vars[k]):
            tag = f"[{n}]" if len(doc.vars[k]) > 1 else "   "
            log(f"{k:<{width}} {tag} {'plain ' if 'plain' in item else 'secret'}  -> {', '.join(item.get('places') or []) or '(nowhere)'}")
    log(f"\n{len(doc.vars)} names; places: " + ", ".join(f"{n} ({p['kind']})" for n, p in doc.places.items()))


def cmd_check() -> None:
    doc = load()
    log(f"ok: {len(doc.vars)} names, {len(doc.places)} places, every secret encrypted")


def set_item(key: str, index: int, item: dict) -> None:
    """Write one item. It travels on stdin, never argv; every other item keeps its ciphertext."""
    sops("set", "--value-stdin", FILE.name, f'["vars"]["{key}"][{index}]', stdin=json.dumps(item))


def cmd_set(key: str, flags: dict[str, str]) -> None:
    if not NAME.match(key):
        die(f"{key!r} is not a variable name")
    if "--from" in flags:
        src = Path(flags["--from"])
        value = dotenv_assignments(src.read_text() if src.exists() else die(f"{src} is missing")).get(key) or die(f"{key} is not set in {src}")
    else:
        value = sys.stdin.read().rstrip("\n")
    if not value:
        die("the value is read from stdin (or --from=<envfile>) and was empty")
    doc = load()
    places, plain = csv(flags, "--places"), "--plain" in flags
    items = [dict(i) for i in doc.vars.get(key, [])]
    index = None
    if "--places" in flags:
        same = [n for n, i in enumerate(items) if sorted(i.get("places") or []) == sorted(places)]
        index = same[0] if same else None
    elif len(items) == 1:
        index = 0
    elif items:
        die(f"{key} has {len(items)} items: say which with --places=<its places>")
    if index is None:
        item = {"plain" if plain else "value": value, "places": places}
        items.append(item); index = len(items) - 1
    else:
        item = items[index]
        if plain != ("plain" in item):
            die(f"{key} is filed as {'plain' if 'plain' in item else 'a secret'}; moving it between the two is an edit in `sops env.yaml`")
        item["plain" if plain else "value"] = value
    if "--not-secret" in flags:
        item["secret"] = False
    if "--file" in flags:
        item["file"] = True
    if flags.get("--note"):
        item["note"] = flags["--note"]
    Doc({"places": doc.places, "vars": {**doc.vars, key: items}}, "set")  # validate before anything is written
    set_item(key, index, item)
    log(f"set {key} -> {', '.join(item.get('places') or []) or '(nowhere)'} in env.yaml (not delivered: run `env_yaml.py deliver --since=HEAD`)")


def pick_item(doc: Doc, key: str, flags: dict[str, str]) -> int:
    items = doc.vars.get(key) or die(f"{key} is not in env.yaml")
    if len(items) > 1 and "--item" not in flags:
        die(f"{key} has {len(items)} items: say which with --item=N (see `map`)")
    n = int(flags.get("--item") or 0)
    return n if 0 <= n < len(items) else die(f"{key} has no item {n}")


def cmd_route(key: str, where: str, flags: dict[str, str]) -> None:
    doc = load()
    n = pick_item(doc, key, flags)
    items = [dict(i) for i in doc.vars[key]]
    items[n]["places"] = [] if where == "none" else [x for x in where.split(",") if x]
    Doc({"places": doc.places, "vars": {**doc.vars, key: items}}, "route")
    set_item(key, n, items[n])
    log(f"{key} -> {', '.join(items[n]['places']) or '(nowhere)'} (not delivered; a place it left keeps the value until removed there by hand)")


def cmd_unset(key: str, flags: dict[str, str]) -> None:
    doc = load()
    n = pick_item(doc, key, flags)
    sops("unset", FILE.name, f'["vars"]["{key}"]' + (f"[{n}]" if len(doc.vars[key]) > 1 else ""))
    log(f"removed {key}{f' item {n}' if len(doc.vars[key]) > 1 else ''} from env.yaml (the places it went to keep the value until removed there by hand)")


def cmd_place(name: str, pairs: list[str]) -> None:
    doc = load()
    spec: dict[str, object] = {}
    for pair in pairs:
        k, _, v = pair.partition("=")
        spec[k] = {"true": True, "false": False}.get(v, v.split(",") if k == "projects" else v)
    Doc({"places": {**doc.places, name: spec}, "vars": doc.vars}, "place")
    sops("set", "--value-stdin", FILE.name, f'["places"]["{name}"]', stdin=json.dumps(spec))
    log(f"place {name}: {spec}")


def cmd_import(src: Path, flags: dict[str, str]) -> None:
    doc = load()
    places = csv(flags, "--places") or ["operator"]
    found = dotenv_assignments(src.read_text() if src.exists() else die(f"{src} is missing"))
    added = []
    for k, v in found.items():
        why = ("never in env.yaml" if k in NEVER_IN_FILE else "already in env.yaml" if k in doc.vars
               else "empty or PLACEHOLDER" if v in ("", "PLACEHOLDER") else "a shell expression" if "$" in v or "`" in v else "")
        if why:
            log(f"  skipped {k}: {why}"); continue
        item = {"value" if SECRET_NAME.search(k.upper()) else "plain": v, "places": places}
        Doc({"places": doc.places, "vars": {k: [item]}}, f"import {k}")
        set_item(k, 0, item)
        added.append(k)
        log(f"  filed {k} as {'a secret' if 'value' in item else 'plain'} -> {', '.join(places)}")
    log(f"imported {len(added)} name(s). Read `env_yaml.py map`: a secret filed as plain is readable in git. Then `render --take-over`.")


def cmd_init() -> None:
    if FILE.exists():
        die("env.yaml already exists")
    if not KEY_FILE.exists():
        r = subprocess.run(["age-keygen", "-o", str(KEY_FILE)], capture_output=True, text=True)
        if r.returncode != 0:
            die(f"age-keygen failed (brew install sops age): {r.stderr.strip()}")
        KEY_FILE.chmod(0o600)
        log(f"created {KEY_FILE.name}: this project's own key, on this machine only")
    public = subprocess.run(["age-keygen", "-y", str(KEY_FILE)], capture_output=True, text=True).stdout.strip() or die(f"{KEY_FILE.name} is not an age key")
    gi = PROJECT_DIR / ".gitignore"
    if (PROJECT_DIR / ".git").exists() or gi.exists():
        have = gi.read_text().splitlines() if gi.exists() else []
        missing = [ln for ln in GITIGNORE if ln not in have]
        if missing:
            with gi.open("a") as f:
                f.write("\n# env.yaml is tracked and encrypted (FWADR-041). These are never tracked.\n" + "\n".join(missing) + "\n")
    rules = PROJECT_DIR / ".sops.yaml"
    if not rules.exists():
        rules.write_text("# Who may decrypt env.yaml (FWADR-041). Only `value` fields are encrypted.\n"
                         f"creation_rules:\n  - path_regex: ^env\\.yaml$\n    encrypted_regex: ^value$\n    age: {public}\n")
    elif "env\\.yaml" not in rules.read_text():
        die(".sops.yaml exists without a rule for env.yaml; add one (path_regex ^env\\.yaml$, encrypted_regex ^value$)")
    rc = PROJECT_DIR / ".sopsrc"
    if not rc.exists():
        rc.write_text("# VS Code SOPS extension: where the age key for env.yaml is (gitignored).\nageKeyFile: .sops-age-key.txt\n")
    vs = PROJECT_DIR / ".vscode" / "settings.json"
    if not vs.exists():
        vs.parent.mkdir(exist_ok=True)
        vs.write_text(json.dumps({"sops.enabled": True, "sops.beta": False, "sops.configPath": "./.sopsrc", "sops.creationEnabled": False}, indent=2) + "\n")
    FILE.write_text("# Every env value this project shares, and the places each one goes (FWADR-041).\n"
                    "# Edit with `sops env.yaml` or scripts/env_yaml.py set; deliver with scripts/env_yaml.py deliver.\n"
                    "places:\n    operator:\n        kind: env-file\n        path: .env\nvars: {}\n")
    try:
        sops("-e", "-i", FILE.name)
    except SystemExit:
        FILE.unlink()  # never leave an unencrypted env.yaml behind
        raise
    log("created env.yaml, .sops.yaml, .sopsrc and .vscode/settings.json\n"
        "next: scripts/env_key_backup.py backup && scripts/env_key_backup.py verify   (the key exists only on this machine until then)\n"
        "      scripts/env_yaml.py import .env    then    scripts/env_yaml.py render --take-over")


def cmd_render(flags: dict[str, str]) -> None:
    doc = load()
    for place, spec in doc.places.items():
        if spec["kind"] == "env-file":
            render_place(doc, place, "--take-over" in flags, "--dry-run" in flags)


def cmd_deliver(flags: dict[str, str]) -> None:
    dry, only = "--dry-run" in flags, csv(flags, "--places")
    if "--all" not in flags and not flags.get("--since"):
        die("say --since=<git ref> or --all (flags take their value with '=')")
    new = load()
    unknown = [p for p in only if p not in new.places]
    if unknown:
        die(f"not declared places: {unknown}")
    old = None if "--all" in flags else doc_at(flags["--since"])
    touched_ci = False
    for place in sorted(new.places):
        spec = new.places[place]
        if only and place not in only:
            continue
        if spec["kind"] == "env-file":
            render_place(new, place, False, dry); continue
        keys = new.routes[place]
        if old is not None and old.places.get(place) == spec:
            keys = {k: v for k, v in keys.items() if old.routes[place].get(k) != v}
        if not keys:
            continue
        log(f"{place} ({spec['kind']}): {len(keys)} value(s): {', '.join(sorted(keys))}")
        if spec["kind"] == "ci-variables":
            deliver_ci(new, place, keys, dry); touched_ci = True
        else:
            deliver_paperclip(new, place, keys, dry)
    if touched_ci:
        log("CI variables reach a host at that repo's next deploy; production at the next release.")
    log("dry run; nothing written" if dry else "delivered")


def main(argv: list[str]) -> None:
    flags, args = flags_of(argv)
    mode = args[0] if args else "map"
    if mode == "init":
        cmd_init()
    elif mode == "map":
        cmd_map()
    elif mode == "check":
        cmd_check()
    elif mode == "set" and len(args) == 2:
        cmd_set(args[1], flags)
    elif mode == "route" and len(args) == 3:
        cmd_route(args[1], args[2], flags)
    elif mode == "unset" and len(args) == 2:
        cmd_unset(args[1], flags)
    elif mode == "place" and len(args) >= 3:
        cmd_place(args[1], args[2:])
    elif mode == "import" and len(args) == 2:
        cmd_import(Path(args[1]), flags)
    elif mode == "render":
        cmd_render(flags)
    elif mode == "deliver":
        cmd_deliver(flags)
    else:
        die("usage: env_yaml.py init | import <envfile> | map | check | place | set | route | unset | render | deliver --all|--since=<ref>   (see the header of this file)")


if __name__ == "__main__":
    main(sys.argv[1:])
