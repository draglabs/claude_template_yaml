#!/usr/bin/env bash
# check-ditto-stack.sh — mechanical sizing check for a Dittofeed compose stack.
# FRAMEWORK-OWNED — overwritten on every sync; do not edit (FWADR-014).
#
# Resolves a compose file with `docker compose config` (env substitution,
# memory units) and checks the ClickHouse service against the floors that
# FWADR-038 measured on the shared host. Run it from the repo on any diff that
# touches the stack's compose file (Reviewer), and on the box before
# `docker compose up -d` (deploy README apply step).
#
# Usage:
#   check-ditto-stack.sh <docker-compose.yml>
#
# The compose file's own directory supplies `.env` (compose reads it there).
# A `${VAR:?}` the file requires must be present or the resolve fails — that
# is an exit 2, not a pass.
#
# Checks (each miss is one FAIL line on stdout):
#   - ClickHouse `mem_limit` (or deploy.resources.limits.memory) >= 8 GiB
#   - ClickHouse `cpus` (or deploy.resources.limits.cpus) set and >= 2
#   - a file bind-mounted into /etc/clickhouse-server/config.d/ whose
#     <text_log> block lowers <level> below trace and sets a <ttl>;
#     the mount is a single file, never the whole config.d directory
#     (the image's docker_related_config.xml carries listen_host)
#   - the Dittofeed app service (`dittofeed/*` image) `mem_limit` >= 1 GiB
#
# Exit codes:
#   0 — all checks pass.
#   1 — at least one FAIL line printed.
#   2 — cannot decide: usage error, jq/docker missing, compose did not
#       resolve, or no ClickHouse service in the file.
#
# Canonical doctrine: docs/dev_framework/adrs/fwadr-038-dittofeed-stack-sizing.md

set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "usage: check-ditto-stack.sh <docker-compose.yml>" >&2
  exit 2
fi
FILE="$1"
if [[ ! -f "$FILE" ]]; then
  echo "check-ditto-stack: compose file not found: $FILE" >&2
  exit 2
fi
for tool in jq docker; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "check-ditto-stack: '$tool' is required and not on PATH" >&2
    exit 2
  fi
done

DIR="$(cd "$(dirname "$FILE")" && pwd)"
BASE="$(basename "$FILE")"
ERR="$(mktemp)"
trap 'rm -f "$ERR"' EXIT
if ! JSON="$(cd "$DIR" && docker compose -f "$BASE" config --format json 2>"$ERR")"; then
  echo "check-ditto-stack: 'docker compose config' did not resolve $FILE:" >&2
  sed 's/^/  /' "$ERR" >&2
  exit 2
fi

# Accept "8589934592", "8g", "8192m", "8GiB" — compose normalizes mem_limit to
# bytes, deploy.resources.limits.memory may keep its unit.
to_bytes() {
  local v num unit
  v="$(printf '%s' "$1" | tr 'A-Z' 'a-z')"
  num="${v%%[^0-9.]*}"
  unit="${v#"$num"}"
  [[ -n "$num" ]] || { echo 0; return; }
  # %.0f, not %d: mawk's %d saturates at 2^31-1, which reads 8 GiB as 2 GiB.
  case "$unit" in
    ""|b)       awk -v n="$num" 'BEGIN{printf "%.0f", n}' ;;
    k|kb|kib)   awk -v n="$num" 'BEGIN{printf "%.0f", n*1024}' ;;
    m|mb|mib)   awk -v n="$num" 'BEGIN{printf "%.0f", n*1024*1024}' ;;
    g|gb|gib)   awk -v n="$num" 'BEGIN{printf "%.0f", n*1024*1024*1024}' ;;
    *)          echo 0 ;;
  esac
}
fmt_gib() { awk -v b="$1" 'BEGIN{printf "%.2f GiB", b/1073741824}'; }

CH_MIN=$((8 * 1024 * 1024 * 1024))
LITE_MIN=$((1024 * 1024 * 1024))
FINDINGS=0
fail() { printf 'FAIL: %s\n' "$*"; FINDINGS=$((FINDINGS + 1)); }

CH="$(jq -r '.services | to_entries[] | select((.value.image // "") | test("clickhouse")) | .key' <<<"$JSON" | head -1)"
if [[ -z "$CH" ]]; then
  echo "check-ditto-stack: no service with a 'clickhouse' image in $FILE" >&2
  exit 2
fi

# ---- memory ---------------------------------------------------------------
mem_raw="$(jq -r --arg s "$CH" '.services[$s].mem_limit // .services[$s].deploy.resources.limits.memory // empty' <<<"$JSON")"
if [[ -z "$mem_raw" ]]; then
  fail "$CH: no mem_limit (FWADR-038 floor is 8 GiB; an uncapped ClickHouse takes the box with it)"
else
  mem_b="$(to_bytes "$mem_raw")"
  if (( mem_b < CH_MIN )); then
    fail "$CH: mem_limit is $(fmt_gib "$mem_b"), floor is 8 GiB (FWADR-038: 2 GiB produced one kernel OOM kill every ~90 s)"
  fi
fi

# ---- cpu --------------------------------------------------------------------
cpus_raw="$(jq -r --arg s "$CH" '.services[$s].cpus // .services[$s].deploy.resources.limits.cpus // empty' <<<"$JSON")"
if [[ -z "$cpus_raw" ]]; then
  fail "$CH: no cpus cap (FWADR-038: set 3; a thrashing ClickHouse took 6 cores of the shared host)"
elif ! awk -v c="$cpus_raw" 'BEGIN{exit !(c+0 >= 2)}'; then
  fail "$CH: cpus is $cpus_raw, floor is 2 (merges stall below that and the part backlog grows)"
fi

# ---- config.d override ------------------------------------------------------
mounts="$(jq -c --arg s "$CH" '.services[$s].volumes[]? | select((.target // "") | startswith("/etc/clickhouse-server/config.d"))' <<<"$JSON")"
if [[ -z "$mounts" ]]; then
  fail "$CH: nothing mounted into /etc/clickhouse-server/config.d/ — the system-log override is required (stub: docs/dev_framework/_stubs/dittofeed/clickhouse-system-logs.xml)"
else
  override_ok=0
  while IFS= read -r m; do
    [[ -n "$m" ]] || continue
    target="$(jq -r '.target' <<<"$m")"
    source="$(jq -r '.source // ""' <<<"$m")"
    case "$target" in
      /etc/clickhouse-server/config.d|/etc/clickhouse-server/config.d/)
        fail "$CH: whole config.d directory mounted at $target — masks the image's docker_related_config.xml (listen_host); mount the override file by name"
        continue ;;
    esac
    if [[ -z "$source" || ! -f "$source" ]]; then
      fail "$CH: override source '$source' for $target is not a file here — docker would create an empty directory in its place"
      continue
    fi
    block="$(awk '/<text_log>/{f=1} f{print} /<\/text_log>/{f=0}' "$source")"
    if [[ -z "$block" ]]; then
      continue  # some other config.d file (limits, users); keep looking
    fi
    if ! grep -qiE '<level>[[:space:]]*(warning|error|fatal)[[:space:]]*</level>' <<<"$block"; then
      fail "$(basename "$source"): <text_log> keeps the stock trace level — set <level>warning</level> (FWADR-038: trace rows were 24 GiB against 11 MiB of tenant data)"
    fi
    if ! grep -q '<ttl>' <<<"$block"; then
      fail "$(basename "$source"): <text_log> has no <ttl> — rows never expire"
    fi
    override_ok=1
  done <<<"$mounts"
  if (( override_ok == 0 )); then
    fail "$CH: no mounted config.d file carries a <text_log> override (stub: docs/dev_framework/_stubs/dittofeed/clickhouse-system-logs.xml)"
  fi
fi

# ---- dittofeed app service --------------------------------------------------
LITE="$(jq -r '.services | to_entries[] | select((.value.image // "") | test("dittofeed/dittofeed-(lite|api|worker)")) | .key' <<<"$JSON" | head -1)"
if [[ -n "$LITE" ]]; then
  lite_raw="$(jq -r --arg s "$LITE" '.services[$s].mem_limit // .services[$s].deploy.resources.limits.memory // empty' <<<"$JSON")"
  if [[ -n "$lite_raw" ]]; then
    lite_b="$(to_bytes "$lite_raw")"
    if (( lite_b < LITE_MIN )); then
      fail "$LITE: mem_limit is $(fmt_gib "$lite_b"), floor is 1 GiB (measured steady state ~540 MiB)"
    fi
  else
    fail "$LITE: no mem_limit (floor 1 GiB)"
  fi
fi

if (( FINDINGS > 0 )); then
  echo "check-ditto-stack: $FINDINGS finding(s) in $FILE" >&2
  exit 1
fi
echo "check-ditto-stack: OK — $CH sized per FWADR-038"
exit 0
