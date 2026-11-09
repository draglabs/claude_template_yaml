#!/usr/bin/env bash
# check-ci-placement.sh — CI runs on the ephemeral runner host, and runs Tier 1
# only. A CI job never starts a database and never reaches one.
# FRAMEWORK-OWNED — overwritten on every sync; do not edit (FWADR-014).
#
# Usage:
#   check-ci-placement.sh [repo-dir ...]      # default: the current directory
#
# For each repo, reads .gitlab-ci.yml and .github/workflows/*.yml and prints
# one line per finding:
#   FAIL: <file>:<line> <job> — <reason>     (exit 1)
#   WARN: <file>:<line> <job> — <reason>     (does not fail)
#   NOTE: <repo> — no pipeline file           (not a finding)
#
# GitLab rules (FWADR-037):
#   FAIL legacy-tag       a job's tags contain `self-hosted` (the retired dev
#                         instance runner).
#   FAIL untagged         a job has no `tags:` after resolving `extends:` and
#                         `default:` — an untagged job lands on whichever
#                         runner takes untagged work, never one we chose.
#                         `trigger:` bridge jobs are exempt (no runner).
#   FAIL datastore-in-ci  a `services:` entry, or a `docker run` / `docker
#                         compose` line, names a datastore image (postgres,
#                         pgvector, mysql, mariadb, redis, clickhouse, mongo,
#                         rabbitmq, elasticsearch, opensearch, minio, kafka).
#                         A test that needs one is Tier 2: it runs in the
#                         dev harness, on dev.
#   FAIL database-in-ci   a job without the `deploy` tag names a database
#                         connection: a `*DATABASE_URL` / `PGHOST` variable, a
#                         postgres:// mysql:// mongodb:// redis:// URL, `psql`,
#                         `pg_isready`, or an `ssh -L` tunnel. Reaching dev's
#                         instance from a runner measured ~3 h per run.
#                         (sqlite lines are not flagged.)
#   WARN transitional     tags contain `ephemeral-shell` — on the right host,
#                         but the host toolchain is still implied. Canonical
#                         is `docker` with a pinned `image:`.
#   WARN no-harness       a `deploy`-tagged job never mentions dev_harness.sh:
#                         Tier 2 runs in the dev harness after each deploy.
#   WARN include          the file pulls in `include:` — jobs defined there are
#                         not followed; run the check in that repo too.
# GitHub Actions: only datastore-in-ci and database-in-ci apply (hosted runners
# are already per-job containers off every box of ours); a job whose name
# contains `deploy` is exempt from database-in-ci.
#
# Heuristic YAML reader: two-space-indented blocks, inline `[a, b]` or `- item`
# lists, `extends:` up to three deep, `default:` tags. YAML anchors/merges
# (`<<: *x`) are not resolved. Exit codes: 0 clean, 1 FAIL printed,
# 2 usage error.
# Canonical doctrine: docs/dev_framework/adrs/fwadr-037-ci-runner-topology.md

set -euo pipefail

DATASTORE_RE='(postgres|pgvector|timescale|mysql|mariadb|redis|valkey|clickhouse|mongo|rabbitmq|elasticsearch|opensearch|minio|kafka|memcached|nats)'
# A line that reaches a database. No backslashes: awk -v would eat them.
DBREACH_RE='(DATABASE_URL|PGHOST|PGPASSWORD|postgres(ql)?://|mysql://|mongodb([+]srv)?://|rediss?://|pg_isready|(^|[^A-Za-z_])psql([ ]|$)|ssh[ ][^|;&]*-[A-Za-z]*L[ ])'

repos=()
if [[ $# -gt 0 ]]; then
  for d in "$@"; do
    if [[ ! -d "$d" ]]; then
      echo "check-ci-placement: not a directory: $d" >&2
      exit 2
    fi
    repos+=("${d%/}")
  done
else
  repos=(".")
fi

fail=0

# --- GitLab -----------------------------------------------------------------
check_gitlab() {
  local file="$1"
  awk -v FILE="$file" -v DS="$DATASTORE_RE" -v DBR="$DBREACH_RE" '
  function indent(s) { match(s, /^ */); return RLENGTH }
  function trim(s) { sub(/^[ \t]+/, "", s); sub(/[ \t]+$/, "", s); return s }
  function strip_comment(s) { sub(/[ \t]#.*$/, "", s); return s }
  function add_list(key, blk, items,   n, parts, i, v) {
    n = split(items, parts, ",")
    for (i = 1; i <= n; i++) {
      v = trim(parts[i]); gsub(/^["'\'']|["'\'']$/, "", v)
      if (v != "") LIST[key, blk] = LIST[key, blk] " " v
    }
  }
  function is_reserved(k) {
    return (k == "stages" || k == "variables" || k == "include" || k == "workflow" ||
            k == "image" || k == "before_script" || k == "after_script" || k == "cache" ||
            k == "types" || k == "services" || k == "default")
  }
  function blockname(k) {
    # top-level image:/services:/before_script: belong to the implicit default block
    if (k == "image" || k == "services" || k == "before_script" || k == "after_script" || k == "default") return "default"
    return k
  }
  function tags_of(blk, depth,   t, n, parts, i, r) {
    if (depth > 3) return ""
    t = LIST["tags", blk]
    if (t != "") return t
    n = split(LIST["extends", blk], parts, " ")
    for (i = 1; i <= n; i++) { r = tags_of(parts[i], depth + 1); if (r != "") return r }
    return ""
  }
  {
    raw = $0
    line = strip_comment(raw)
    if (trim(line) == "" || raw ~ /^[ \t]*#/) next
    ind = indent(line)

    if (ind == 0 && line ~ /^[A-Za-z_.][^ \t]*:([ \t]|$)/) {
      # the key ends at the first ":" followed by space or end-of-line, so
      # colon-bearing job names (verify:api-db) survive intact
      match(line, /:([ \t]|$)/); key = substr(line, 1, RSTART - 1)
      cur = blockname(key)
      if (!(cur in SEEN)) { SEEN[cur] = NR; ORDER[++NB] = cur }
      mode = ""
      if (key == "include") INCLUDE = NR
      # top-level `services: [..]` inline
      if (key == "services") { rest = line; sub(/^[^:]*:[ \t]*/, "", rest); if (rest ~ /^\[/) { gsub(/[\[\]]/, "", rest); add_list("services", cur, rest) } else mode = "services"; mode_ind = 0 }
      next
    }
    if (cur == "") next

    # list continuation for the active mode
    if (mode != "" && ind > mode_ind && line ~ /^[ \t]*-[ \t]/) {
      item = line; sub(/^[ \t]*-[ \t]*/, "", item)
      if (item ~ /^name:/) { sub(/^name:[ \t]*/, "", item) }
      else if (item ~ /^[a-z_]+:/) { next }     # other service keys (alias:, command:)
      add_list(mode, cur, item)
      next
    }
    if (mode != "" && ind <= mode_ind) mode = ""
    if (mode != "" && line ~ /^[ \t]*name:[ \t]/ ) { item = line; sub(/^[ \t]*name:[ \t]*/, "", item); add_list(mode, cur, item); next }

    if (line ~ /^[ \t]*(tags|services|extends):/) {
      k = line; sub(/^[ \t]*/, "", k); sub(/:.*$/, "", k)
      rest = line; sub(/^[^:]*:[ \t]*/, "", rest)
      if (rest ~ /^\[/) { gsub(/[\[\]]/, "", rest); add_list(k, cur, rest) }
      else if (rest == "") { mode = k; mode_ind = ind }
      else add_list(k, cur, rest)
      if (k == "services") SVC_LINE[cur] = NR
      next
    }
    if (line ~ /^[ \t]*trigger:/) TRIGGER[cur] = 1
    if (line ~ /^[ \t]*(script|before_script|after_script):/) HAS_SCRIPT[cur] = 1
    if (line ~ /dev_harness\.sh/) HARNESS[cur] = 1
    if (line ~ DBR && tolower(line) !~ /sqlite/ && !(cur in DBRL)) { DBRL[cur] = NR; DBRTXT[cur] = trim(line) }
    if (tolower(line) ~ ("docker[ \t]+(run|compose|container[ \t]+run|create|service[ \t]+create)[^\n]*" DS) ||
        tolower(line) ~ ("image:[ \t]*[\"'\'']?[a-z0-9./-]*" DS)) {
      if (!((cur, "dsline") in DSL)) { DSL[cur, "dsline"] = NR; DSTXT[cur] = trim(line) }
    }
  }
  END {
    rc = 0
    if (INCLUDE) print "WARN: " FILE ":" INCLUDE " include — jobs defined in included files are not followed; run the check in that repo too"
    for (i = 1; i <= NB; i++) {
      b = ORDER[i]
      if (b == "default") {
        if (LIST["services", b] ~ DS) { print "FAIL: " FILE ":" SVC_LINE[b] " default — datastore-in-ci: top-level services: run under every job (" trim(LIST["services", b]) ")"; rc = 1 }
        continue
      }
      if (substr(b, 1, 1) == ".") continue          # hidden template job
      if (is_reserved(b)) continue
      t = tags_of(b, 0)
      if (t == "") t = tags_of("default", 0)
      if (t ~ /(^| )self-hosted( |$)/) { print "FAIL: " FILE ":" SEEN[b] " " b " — legacy-tag: self-hosted is the retired dev runner; verify jobs take tags: [docker]"; rc = 1 }
      else if (t == "" && !(b in TRIGGER)) { print "FAIL: " FILE ":" SEEN[b] " " b " — untagged: lands on whichever runner takes untagged work; add tags: [docker] (verify) or [deploy]"; rc = 1 }
      if (t ~ /(^| )ephemeral-shell( |$)/) print "WARN: " FILE ":" SEEN[b] " " b " — transitional: ephemeral-shell runs on the right host but implies the host toolchain; canonical is tags: [docker] + image:"
      if (LIST["services", b] ~ DS) { print "FAIL: " FILE ":" SVC_LINE[b] " " b " — datastore-in-ci: services: starts " trim(LIST["services", b]) "; a test that needs it is Tier 2 and runs in the dev harness"; rc = 1 }
      if ((b in DBRL) && t !~ /(^| )deploy( |$)/) { print "FAIL: " FILE ":" DBRL[b] " " b " — database-in-ci: `" DBRTXT[b] "`; a CI job never reaches a database — the test is Tier 2 and runs in the dev harness"; rc = 1 }
      if ((b, "dsline") in DSL) { print "FAIL: " FILE ":" DSL[b, "dsline"] " " b " — datastore-in-ci: `" DSTXT[b] "`; no datastore starts inside a CI job"; rc = 1 }
      if (t ~ /(^| )deploy( |$)/ && !(b in HARNESS)) print "WARN: " FILE ":" SEEN[b] " " b " — no-harness: deploy job never runs scripts/dev_harness.sh; Tier 2 runs in the dev harness after each deploy"
    }
    exit rc
  }' "$file" || return 1
}

# --- GitHub Actions ---------------------------------------------------------
check_github() {
  local file="$1"
  awk -v FILE="$file" -v DS="$DATASTORE_RE" -v DBR="$DBREACH_RE" '
  function trim(s) { sub(/^[ \t]+/, "", s); sub(/[ \t]+$/, "", s); return s }
  {
    line = $0; sub(/[ \t]#.*$/, "", line)
    if (line ~ /^[ \t]*#/ || trim(line) == "") next
    if (line ~ /^  [A-Za-z_-]+:[ \t]*$/ && injobs) { job = trim(line); sub(/:$/, "", job) }
    if (line ~ /^jobs:/) injobs = 1
    if (line ~ /^[ \t]*services:/) { insvc = 1; svc_ind = match(line, /[^ ]/) - 1; next }
    if (insvc) {
      ind = match(line, /[^ ]/) - 1
      if (ind <= svc_ind) insvc = 0
      else if (tolower(line) ~ ("image:[ \t]*[\"'\'']?[a-z0-9./-]*" DS)) { print "FAIL: " FILE ":" NR " " job " — datastore-in-ci: services: starts `" trim(line) "`; a test that needs it is Tier 2 and runs in the dev harness"; rc = 1 }
    }
    if (tolower(line) ~ ("docker[ \t]+(run|compose|container[ \t]+run|create)[^\n]*" DS)) { print "FAIL: " FILE ":" NR " " job " — datastore-in-ci: `" trim(line) "`; no datastore starts inside a CI job"; rc = 1 }
    if (line ~ DBR && tolower(line) !~ /sqlite/ && tolower(job) !~ /deploy/) { print "FAIL: " FILE ":" NR " " job " — database-in-ci: `" trim(line) "`; a CI job never reaches a database — the test is Tier 2 and runs in the dev harness"; rc = 1 }
  }
  END { exit rc }' "$file" || return 1
}

for repo in "${repos[@]}"; do
  found=0
  if [[ -f "$repo/.gitlab-ci.yml" ]]; then
    found=1
    check_gitlab "$repo/.gitlab-ci.yml" || fail=1
  fi
  for wf in "$repo"/.github/workflows/*.yml "$repo"/.github/workflows/*.yaml; do
    [[ -f "$wf" ]] || continue
    found=1
    check_github "$wf" || fail=1
  done
  if [[ "$found" -eq 0 ]]; then
    echo "NOTE: $repo — no pipeline file (.gitlab-ci.yml or .github/workflows/); CI deploy to dev is dev-environment.md step 5"
  fi
done

exit "$fail"
