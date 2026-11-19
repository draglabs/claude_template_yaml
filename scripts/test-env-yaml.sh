#!/usr/bin/env bash
# test-env-yaml.sh — template-repo test for the env.yaml protocol (FWADR-041).
#
# Drives docs/dev_framework/_stubs/scripts/env_yaml.py and the env.yaml part of
# .claude/hooks/git-guard-pre-push.sh end to end in a throwaway project: a
# throwaway age key, a local stand-in for the GitLab and Paperclip APIs, and a
# local bare repo to push to. Touches nothing outside its temp directory and no
# real service. Needs sops, age, python3, git.
#
# Run from the template repo root by hand after changing either file.
# Template-only — never synced to adopters.

set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TOOL="$ROOT/docs/dev_framework/_stubs/scripts/env_yaml.py"
GUARD="$ROOT/.claude/hooks/git-guard-pre-push.sh"
T="$(mktemp -d "${TMPDIR:-/tmp}/env-yaml-test.XXXXXX")"
pass=0; fail=0
trap '[[ -n "${SRV:-}" ]] && kill "$SRV" 2>/dev/null; rm -rf "$T"' EXIT

ok()   { pass=$((pass+1)); echo "  ok   $1"; }
bad()  { fail=$((fail+1)); echo "  FAIL $1"; [[ -n "${2:-}" ]] && echo "$2" | sed 's/^/       /' | head -12; }
# expect <0|1> <label> <command...>: the command's exit status is zero (0) or non-zero (1).
expect() {
  local want="$1" label="$2" out rc; shift 2
  out="$("$@" 2>&1)"; rc=$?
  if { [[ "$want" == 0 && $rc -eq 0 ]] || [[ "$want" == 1 && $rc -ne 0 ]]; }; then ok "$label"; else bad "$label (exit $rc)" "$out"; fi
  LAST="$out"
}
has()  { if grep -qF -- "$2" <<<"$LAST"; then ok "$1"; else bad "$1: output lacks '$2'" "$LAST"; fi; }
lacks(){ if grep -qF -- "$2" <<<"$LAST"; then bad "$1: output contains '$2'" "$LAST"; else ok "$1"; fi; }

for bin in sops age-keygen python3 git; do
  command -v "$bin" >/dev/null || { echo "missing $bin"; exit 2; }
done
unset SOPS_AGE_KEY SOPS_AGE_KEY_FILE GITLAB_TOKEN SECRETS_GITLAB_TOKEN PAPERCLIP_API_URL PAPERCLIP_API_KEY GIT_HOST GIT_HOST_URL

# --- a stand-in for the GitLab and Paperclip APIs ------------------------------
cat > "$T/server.py" <<'PY'
import json, sys, urllib.parse
from http.server import BaseHTTPRequestHandler, HTTPServer
STATE = {"vars": {}, "secrets": {}, "projects": {"p1": {"id": "p1", "name": "App", "env": {"KEEP": {"type": "plain", "value": "x"}}},
                                                  "p2": {"id": "p2", "name": "NoEnv", "env": None}}, "log": []}
class H(BaseHTTPRequestHandler):
    def log_message(self, *a): pass
    def send(self, code, obj):
        body = json.dumps(obj).encode(); self.send_response(code); self.send_header("Content-Length", str(len(body))); self.end_headers(); self.wfile.write(body)
    def body(self):
        return self.rfile.read(int(self.headers.get("Content-Length") or 0)).decode()
    def do_GET(self):
        path = urllib.parse.urlparse(self.path).path
        if path == "/__state": return self.send(200, STATE)
        if path.startswith("/api/v4/projects/") and path.endswith("/variables"):
            if self.headers.get("PRIVATE-TOKEN") != "glpat-test-token-123": return self.send(401, {"message": "401"})
            repo = urllib.parse.unquote(path.split("/")[4]); return self.send(200, list(STATE["vars"].get(repo, {}).values()))
        if path == "/api/companies": return self.send(200, [{"id": "c1", "name": "Demo"}])
        if path == "/api/companies/c1/secrets": return self.send(200, [{"id": i, "name": s["name"]} for i, s in STATE["secrets"].items()])
        if path == "/api/companies/c1/projects": return self.send(200, list(STATE["projects"].values()))
        self.send(404, {})
    def do_POST(self):
        path = urllib.parse.urlparse(self.path).path; raw = self.body(); STATE["log"].append("POST " + path)
        if path.endswith("/variables"):
            repo = urllib.parse.unquote(path.split("/")[4]); f = dict(urllib.parse.parse_qsl(raw, keep_blank_values=True))
            STATE["vars"].setdefault(repo, {})[f["key"] + "@" + f["environment_scope"]] = {"key": f["key"], "value": f["value"], "environment_scope": f["environment_scope"], "protected": f["protected"] == "true", "masked": f["masked"] == "true"}
            return self.send(201, {})
        if path == "/api/companies/c1/secrets":
            b = json.loads(raw); i = "s%d" % (len(STATE["secrets"]) + 1); STATE["secrets"][i] = {"name": b["name"], "value": b["value"], "rotations": 0}; return self.send(201, {"id": i})
        if path.startswith("/api/secrets/") and path.endswith("/rotate"):
            s = STATE["secrets"][path.split("/")[3]]; s["value"] = json.loads(raw)["value"]; s["rotations"] += 1; return self.send(200, {})
        self.send(404, {})
    def do_PUT(self):
        u = urllib.parse.urlparse(self.path); raw = self.body(); STATE["log"].append("PUT " + u.path)
        repo = urllib.parse.unquote(u.path.split("/")[4]); key = u.path.split("/")[-1]; f = dict(urllib.parse.parse_qsl(raw, keep_blank_values=True))
        STATE["vars"][repo][key + "@" + f["environment_scope"]].update(value=f["value"], protected=f["protected"] == "true", masked=f["masked"] == "true")
        self.send(200, {})
    def do_PATCH(self):
        path = urllib.parse.urlparse(self.path).path; STATE["log"].append("PATCH " + path)
        STATE["projects"][path.split("/")[-1]]["env"] = json.loads(self.body())["env"]; self.send(200, {})
srv = HTTPServer(("127.0.0.1", 0), H); print(srv.server_address[1], flush=True); srv.serve_forever()
PY
python3 "$T/server.py" > "$T/port" & SRV=$!; disown
for _ in 1 2 3 4 5 6 7 8 9 10; do [[ -s "$T/port" ]] && break; sleep 0.3; done
URL="http://127.0.0.1:$(cat "$T/port")"
state() { python3 -c "import json,sys,urllib.request; s=json.load(urllib.request.urlopen('$URL/__state')); print(eval(sys.argv[1]))" "$1"; }

# --- a throwaway project --------------------------------------------------------
P="$T/project"; mkdir -p "$P/app"; cd "$P" || exit 2
git init -q -b main . && git config user.email t@example.invalid && git config user.name t
printf '.env\napp/\n' > .gitignore
cat > .env <<EOF
PROJECT_NAME=demo
GIT_HOST=gitlab
GIT_HOST_URL=$URL
GITLAB_TOKEN=glpat-test-token-123
PAPERCLIP_API_URL=$URL
PAPERCLIP_API_KEY='pc-board-key-123456'
BITWARDEN_MACHINE_ACCESS=0.aaaa.bbbb:cccc
EMPTY_ONE=PLACEHOLDER
case "\$GIT_HOST" in
  gitlab) export INTEGRATION_BRANCH=main ;;
esac
EOF

echo "init and import"
expect 0 "init" "$TOOL" init
[[ "$(stat -f %Lp .sops-age-key.txt 2>/dev/null || stat -c %a .sops-age-key.txt)" == 600 ]] && ok "key file is mode 600" || bad "key file mode"
grep -qxF '.sops-age-key.txt' .gitignore && ok "key file is gitignored" || bad "key not gitignored"
grep -q '^sops:' env.yaml && ok "env.yaml went through sops" || bad "env.yaml has no sops block"
expect 1 "init refuses a second run" "$TOOL" init
expect 0 "import .env" "$TOOL" import .env
has "import skips the Bitwarden token" "skipped BITWARDEN_MACHINE_ACCESS: never in env.yaml"
has "import files a token as a secret" "filed GITLAB_TOKEN as a secret"
has "import files a hostname as plain" "filed GIT_HOST_URL as plain"
lacks "import prints no value" "glpat-test-token-123"
expect 0 "check" "$TOOL" check
grep -q 'glpat-test-token-123\|pc-board-key' env.yaml && bad "a secret is readable in env.yaml" || ok "no secret readable in env.yaml"
grep -q "plain: gitlab" env.yaml && ok "plain values are readable in env.yaml" || bad "plain value not readable"

echo "render"
expect 1 "render refuses while .env sets the same names by hand" "$TOOL" render
has "refusal names the clash" "GITLAB_TOKEN"
expect 0 "render --take-over" "$TOOL" render --take-over
grep -q '^BITWARDEN_MACHINE_ACCESS=' .env && ok "hand-kept line survives" || bad "hand-kept line lost"
grep -q 'export INTEGRATION_BRANCH=main' .env && ok "shell block survives" || bad "shell block lost"
[[ "$(grep -c '^GITLAB_TOKEN=' .env)" == 1 ]] && ok "one GITLAB_TOKEN line after take-over" || bad "duplicate GITLAB_TOKEN lines"
got="$(bash -c 'set -a; . ./.env; echo "$PROJECT_NAME/$GITLAB_TOKEN/$INTEGRATION_BRANCH"')"
[[ "$got" == "demo/glpat-test-token-123/main" ]] && ok "generated .env sources correctly" || bad "sourced .env gave: $got"
stamp="$(python3 -c "import hashlib;print(hashlib.sha256(open('env.yaml','rb').read()).hexdigest()[:16])")"
grep -q "^# >>> env.yaml $stamp " .env && ok "block carries env.yaml's stamp" || bad "stamp missing or wrong"
expect 0 "render again" "$TOOL" render
has "second render is a no-op" "is current"

echo "places, set, route, unset"
expect 0 "place app-dev"  "$TOOL" place app-dev  kind=ci-variables repo=grp/app scope=dev
expect 0 "place app-prod" "$TOOL" place app-prod kind=ci-variables repo=grp/app scope=prod
expect 0 "place paperclip" "$TOOL" place paperclip kind=paperclip company=demo
expect 0 "place local-app" "$TOOL" place local-app kind=env-file path=app/.env
expect 1 "place outside the project is refused" "$TOOL" place host kind=env-file path=/opt/app/.env
expect 1 "place with an unknown kind is refused" "$TOOL" place host kind=ssh-dotenv path=x
expect 0 "set a secret for dev + paperclip" bash -c "printf 'dev-secret-value-1' | '$TOOL' set APP_SECRET_KEY --places=app-dev,paperclip,local-app"
expect 0 "set a second value for prod"      bash -c "printf 'prod-secret-value-9' | '$TOOL' set APP_SECRET_KEY --places=app-prod"
expect 0 "set a plain value everywhere"     bash -c "printf '203.0.113.7' | '$TOOL' set SERVER_DEV --plain --places=all"
expect 0 "set a recorded-only secret"       bash -c "printf 'old-vendor-token-1' | '$TOOL' set OLD_VENDOR_TOKEN"
expect 1 "plain under a secret-looking name is refused" bash -c "printf 'oops-a-real-token' | '$TOOL' set STRIPE_API_KEY --plain --places=app-dev"
expect 0 "…unless it says it is not a secret" bash -c "printf '/keys/deploy.pem' | '$TOOL' set DEPLOY_KEY_PATH --plain --not-secret --places=operator"
expect 1 "an undeclared place is refused" bash -c "printf 'x' | '$TOOL' set FOO --plain --places=nowhere-declared"
expect 1 "two items to one place are refused" bash -c "printf 'x' | '$TOOL' set APP_SECRET_KEY --places=app-dev"
expect 1 "the Bitwarden token is refused as an entry" bash -c "printf 'x' | '$TOOL' set BITWARDEN_MACHINE_ACCESS --places=operator"
expect 1 "a quote cannot go to an env file" bash -c "printf \"it's\" | '$TOOL' set QUOTED --plain --places=operator"
expect 0 "map" "$TOOL" map
has "map shows the nowhere entry" "(nowhere)"
lacks "map prints no value" "dev-secret-value-1"
expect 0 "route" "$TOOL" route OLD_VENDOR_TOKEN paperclip
expect 0 "route back to nowhere" "$TOOL" route OLD_VENDOR_TOKEN none
expect 0 "unset" "$TOOL" unset DEPLOY_KEY_PATH
expect 0 "check after edits" "$TOOL" check
printf 'dev-secret-value-2' | "$TOOL" set APP_SECRET_KEY --places=app-dev,paperclip,local-app >/dev/null
git add -A >/dev/null 2>&1; git commit -qm one
printf 'prod-secret-value-10' | "$TOOL" set APP_SECRET_KEY --places=app-prod >/dev/null
changed="$(git diff --unified=0 -- env.yaml | grep -c '^[-+] .*value: ENC')"
[[ "$changed" == 2 ]] && ok "set changes one ciphertext, leaves the rest" || bad "set changed $changed value lines (want 2: one removed, one added)"

echo "deliver"
expect 0 "deliver --all --dry-run" "$TOOL" deliver --all --dry-run
has "dry run lists a create" "create grp/app APP_SECRET_KEY [dev]"
lacks "dry run prints no value" "dev-secret-value-2"
[[ "$(state 'len(s["log"])')" == 0 ]] && ok "dry run wrote nothing" || bad "dry run wrote: $(state 's["log"]')"
expect 0 "deliver --all" "$TOOL" deliver --all
[[ "$(state 's["vars"]["grp/app"]["APP_SECRET_KEY@dev"]["value"]')" == "dev-secret-value-2" ]] && ok "dev variable holds the dev value" || bad "dev variable wrong"
[[ "$(state 's["vars"]["grp/app"]["APP_SECRET_KEY@prod"]["value"]')" == "prod-secret-value-10" ]] && ok "prod variable holds the prod value" || bad "prod variable wrong"
[[ "$(state 's["vars"]["grp/app"]["APP_SECRET_KEY@dev"]["masked"]')" == True ]] && ok "a long secret is masked" || bad "secret not masked"
[[ "$(state '"OLD_VENDOR_TOKEN@dev" in s["vars"]["grp/app"]')" == False ]] && ok "an entry with no places went nowhere" || bad "nowhere entry was delivered"
[[ "$(state '"SERVER_DEV@prod" in s["vars"]["grp/app"]')" == True ]] && ok "'all' reached a CI place" || bad "'all' missed a CI place"
[[ "$(state '[x["value"] for x in s["secrets"].values() if x["name"]=="APP_SECRET_KEY"]')" == "['dev-secret-value-2']" ]] && ok "Paperclip secret holds the dev value" || bad "Paperclip secret wrong"
[[ "$(state 's["projects"]["p1"]["env"]["APP_SECRET_KEY"]["type"]')" == secret_ref ]] && ok "secret is bound into the project env" || bad "secret not bound"
[[ "$(state 's["projects"]["p1"]["env"]["SERVER_DEV"]')" == "{'type': 'plain', 'value': '203.0.113.7'}" ]] && ok "plain value is written into the project env" || bad "plain value not in project env"
[[ "$(state 's["projects"]["p1"]["env"]["KEEP"]["value"]')" == x ]] && ok "other project env keys are kept" || bad "project env key dropped"
[[ "$(state 's["projects"]["p2"]["env"]')" == None ]] && ok "a project with no env is left alone" || bad "env-less project was written"
grep -q "^APP_SECRET_KEY='dev-secret-value-2'" app/.env && ok "local app env file is written" || bad "local app env file missing the value"
grep -q "^SERVER_DEV='203.0.113.7'" .env && ok "'all' reached the operator .env" || bad "'all' missed the operator .env"
before_log="$(state 'len([l for l in s["log"] if "variables" in l])')"
expect 0 "deliver --all again" "$TOOL" deliver --all
has "an unchanged CI variable is skipped" "APP_SECRET_KEY [dev] unchanged"
[[ "$(state 'len([l for l in s["log"] if "variables" in l])')" == "$before_log" ]] && ok "second delivery wrote no CI variable" || bad "second delivery rewrote CI variables"
git add -A >/dev/null 2>&1; git commit -qm two
printf 'prod-secret-value-11' | "$TOOL" set APP_SECRET_KEY --places=app-prod >/dev/null
expect 0 "deliver --since=HEAD" "$TOOL" deliver --since=HEAD
has "--since delivers the changed value" "update grp/app APP_SECRET_KEY [prod]"
lacks "--since leaves the unchanged place alone" "APP_SECRET_KEY [dev]"
lacks "--since does not rotate Paperclip for an unchanged value" "Paperclip secret"

echo "tamper and push guard"
cp env.yaml "$T/good.yaml"
sed -i.bak 's/plain: 203.0.113.7/plain: 198.51.100.1/' env.yaml && rm -f env.yaml.bak
expect 1 "a hand edit without sops breaks the file (MAC)" "$TOOL" check
cp "$T/good.yaml" env.yaml
git init -q --bare "$T/remote.git"; git remote add origin "$T/remote.git"
cp "$GUARD" .git/hooks/pre-push; chmod +x .git/hooks/pre-push
mkdir -p app/.git   # a child repo makes this a tracking parent: main pushes freely
git add -A >/dev/null 2>&1; git commit -qm three
expect 0 "an encrypted env.yaml pushes" git push -q origin main
python3 - <<'PY'
import re
s = open("env.yaml").read()
s = re.sub(r"value: ENC\[[^\n]*", "value: leaked-in-the-clear", s, count=1)
open("env.yaml", "w").write(s)
PY
expect 1 "the tool refuses a plaintext value" "$TOOL" check
git commit -qam "plaintext value"
expect 1 "the guard blocks a plaintext value" git push -q origin main
has "the block names the line" "a \`value\` that is not encrypted"
git reset -q --hard HEAD~1
python3 - <<'PY'
s = open("env.yaml").read()
s = s.replace("    SERVER_DEV:", "    STRIPE_API_KEY:\n        - plain: sk_live_misfiled\n          places:\n            - app-dev\n    SERVER_DEV:", 1)
open("env.yaml", "w").write(s)
PY
git commit -qam "misfiled secret"
expect 1 "the guard blocks a secret filed as plain" git push -q origin main
has "the block names the variable" "STRIPE_API_KEY: plain, but the name looks like a secret"
git reset -q --hard HEAD~1
git add -f .sops-age-key.txt >/dev/null 2>&1; git commit -qm "key"
expect 1 "the guard blocks the key file" git push -q origin main
git reset -q --hard HEAD~1
printf 'places:\n  operator: {kind: env-file, path: .env}\nvars:\n  FOO:\n    - plain: bar\n' > env.yaml
git commit -qam "never encrypted"
expect 1 "the guard blocks a file SOPS never wrote" git push -q origin main
git reset -q --hard HEAD~1

echo
echo "$pass passed, $fail failed"
[[ $fail -eq 0 ]]
