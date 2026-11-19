#!/usr/bin/env python3
# Seed-once stub (FWADR-014): copied when missing, never overwritten. Adapt it to the project.
"""Back up the age key that decrypts env.yaml to Bitwarden Secrets Manager, and prove it restores (FWADR-041).

Run from $PROJECT_DIR.

    scripts/env_key_backup.py status     what the machine account can see (names only)
    scripts/env_key_backup.py backup     store .sops-age-key.txt as a secret (create, or update if it differs)
    scripts/env_key_backup.py verify     fetch the secret back and confirm it decrypts env.yaml
    scripts/env_key_backup.py restore    write the secret to .sops-age-key.txt (refuses to overwrite)
    options: --project=<name>            the Bitwarden project to store it in (needed when there are several)
             --name=<name>               the secret's name (default <PROJECT_NAME>-sops-age-key-<ddmmmyy>);
                                         on an existing backup, renames it

Each project has its own key. A backup is recognised by the key inside it, not by its name, so it
can be renamed freely as long as the name still contains "sops-age-key"; `verify` and `restore`
try every such secret and take the one that decrypts this project's env.yaml.

The token is BITWARDEN_MACHINE_ACCESS in the hand-kept part of the operator .env (or the
environment). It is never an entry in env.yaml: what recovers the key cannot sit behind the key.
The machine account needs a Bitwarden project it can write to. The key is never printed.
Needs `pip install bitwarden-sdk` (there is no Homebrew formula).
"""
from __future__ import annotations

import base64
import json
import os
import subprocess
import sys
import tempfile
import urllib.parse
import urllib.request
from pathlib import Path

PROJECT_DIR = Path.cwd()
KEY_FILE = PROJECT_DIR / ".sops-age-key.txt"
ENV_YAML = PROJECT_DIR / "env.yaml"
TOKEN_VAR = "BITWARDEN_MACHINE_ACCESS"
REGIONS = (("https://api.bitwarden.com", "https://identity.bitwarden.com"),
           ("https://api.bitwarden.eu", "https://identity.bitwarden.eu"))


def die(msg: str) -> None:
    print(f"error: {msg}", file=sys.stderr)
    sys.exit(1)


def token() -> str:
    v = os.environ.get(TOKEN_VAR, "").strip()
    if not v and (PROJECT_DIR / ".env").exists():
        for line in (PROJECT_DIR / ".env").read_text().splitlines():
            if line.startswith(TOKEN_VAR + "="):
                v = line.split("=", 1)[1].strip().strip("'\"")
    return v or die(f"{TOKEN_VAR} is not in the environment or in .env")


def organization(tok: str) -> tuple[str, str, str]:
    """(organization id, api url, identity url). The org id is a claim in the login token."""
    try:
        _, token_id, rest = tok.split(".", 2)
        secret = rest.split(":", 1)[0]
    except ValueError:
        die(f"{TOKEN_VAR} is not a Secrets Manager access token (expected 0.<id>.<secret>:<key>)")
    body = urllib.parse.urlencode({"grant_type": "client_credentials", "scope": "api.secrets",
                                   "client_id": token_id, "client_secret": secret}).encode()
    last = ""
    for api, identity in REGIONS:
        req = urllib.request.Request(identity + "/connect/token", data=body,
                                     headers={"Content-Type": "application/x-www-form-urlencoded", "User-Agent": "env-key-backup"})
        try:
            with urllib.request.urlopen(req, timeout=30) as r:
                jwt = json.loads(r.read())["access_token"]
        except Exception as e:  # wrong region, revoked token, no network
            last = f"{identity}: {getattr(e, 'code', e)}"
            continue
        claims = jwt.split(".")[1]
        claims = json.loads(base64.urlsafe_b64decode(claims + "=" * (-len(claims) % 4)))
        return claims["organization"], api, identity
    die(f"Bitwarden refused the token in every region ({last})")


def client():
    try:
        from bitwarden_sdk import BitwardenClient, DeviceType, client_settings_from_dict
    except ImportError:
        die("pip install bitwarden-sdk (into the Python that runs this script)")
    tok = token()
    org, api, identity = organization(tok)
    c = BitwardenClient(client_settings_from_dict({"apiUrl": api, "identityUrl": identity,
                                                   "deviceType": DeviceType.SDK, "userAgent": "env-key-backup"}))
    c.auth().login_access_token(tok, os.path.join(tempfile.mkdtemp(prefix="bws-"), "state"))
    return c, org


def public_half(private_text: str) -> str:
    lines = [ln for ln in private_text.splitlines() if ln.strip() and not ln.startswith("#")]
    r = subprocess.run(["age-keygen", "-y"], input="\n".join(lines) + "\n", capture_output=True, text=True)
    if r.returncode != 0:
        die("that is not an age private key")
    return r.stdout.strip()


MARK = "sops-age-key"


def default_name() -> str:
    import datetime as dt
    project = os.environ.get("PROJECT_NAME", "")
    if not project and (PROJECT_DIR / ".env").exists():
        for line in (PROJECT_DIR / ".env").read_text().splitlines():
            if line.startswith("PROJECT_NAME="):
                project = line.split("=", 1)[1].strip().strip("'\"")
    return f"{project or PROJECT_DIR.name}-{MARK}-{dt.date.today().strftime('%d%b%y').lower()}"


def candidates(c, org: str):
    return [c.secrets().get(s.id).data for s in c.secrets().list(org).data.data if MARK in s.key]


def find(c, org: str, pub: str):
    """The backed-up secret holding the key whose public half is <pub>, whatever it is called."""
    for s in candidates(c, org):
        try:
            if public_half(s.value) == pub:
                return s
        except SystemExit:
            continue
    return None


def pick_project(c, org: str, wanted: str | None):
    projects = c.projects().list(org).data.data
    if wanted:
        return next((p for p in projects if p.name == wanted), None) or die(f"no project named {wanted!r}; have {[p.name for p in projects]}")
    if len(projects) == 1:
        return projects[0]
    die("the machine account sees no project it can write to" if not projects
        else f"several projects; say which with --project=<name>: {[p.name for p in projects]}")


def main(argv: list[str]) -> None:
    flags = {a.split("=", 1)[0]: (a.split("=", 1)[1] if "=" in a else "") for a in argv if a.startswith("--")}
    args = [a for a in argv if not a.startswith("--")]
    mode = args[0] if args else "status"
    if mode not in ("status", "backup", "verify", "restore"):
        die("usage: env_key_backup.py [status|backup|verify|restore] [--project=<name>] [--name=<name>]")
    if mode != "status" and not ENV_YAML.exists():
        die(f"no env.yaml in {PROJECT_DIR} (run from $PROJECT_DIR)")
    c, org = client()

    if mode == "status":
        print("projects:", [p.name for p in c.projects().list(org).data.data] or "none")
        print("secrets: ", [s.key for s in c.secrets().list(org).data.data] or "none")
        if KEY_FILE.exists():
            pub = public_half(KEY_FILE.read_text())
            have = find(c, org, pub)
            print(f"this machine's key ({pub}) is " + (f"BACKED UP as {have.key!r}" if have else "NOT backed up"))
        return

    if mode == "backup":
        if not KEY_FILE.exists():
            die(f"{KEY_FILE} is missing")
        text = KEY_FILE.read_text()
        pub = public_half(text)
        have = find(c, org, pub)
        name = flags.get("--name") or (have.key if have else default_name())
        if MARK not in name:
            die(f"the name must contain {MARK!r}, or the backup cannot be found again")
        note = f"age private key for SOPS (env.yaml). Public half: {pub}. Restore: scripts/env_key_backup.py restore."
        if have and have.value == text and have.key == name:
            print(f"already backed up: {name}"); return
        project = pick_project(c, org, flags.get("--project") or None)
        if have:
            c.secrets().update(org, have.id, name, text, note, [project.id])
            print(f"updated {name} in project {project.name}")
        else:
            c.secrets().create(org, name, text, note, [project.id])
            print(f"created {name} in project {project.name}")
        return

    if mode in ("verify", "restore"):
        if mode == "restore" and KEY_FILE.exists():
            die(f"{KEY_FILE} exists; move it away first")
        found = candidates(c, org)
        if not found:
            die("no sops-age-key secret in Bitwarden")
        for s in found:
            text = s.value
            env = dict(os.environ, SOPS_AGE_KEY=next(ln for ln in text.splitlines() if ln.startswith("AGE-SECRET-KEY-")))
            env.pop("SOPS_AGE_KEY_FILE", None)
            ok = subprocess.run(["sops", "-d", str(ENV_YAML)], env=env, capture_output=True).returncode == 0
            print(f"{s.key}: {'decrypts' if ok else 'does NOT decrypt'} {ENV_YAML.name}")
            if ok and mode == "restore":
                KEY_FILE.write_text(text); KEY_FILE.chmod(0o600)
                print(f"wrote {KEY_FILE}"); return
            if ok:
                return
        die("no backed-up key decrypts env.yaml")


if __name__ == "__main__":
    main(sys.argv[1:])
