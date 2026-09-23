#!/usr/bin/env bash
# port_ledger.sh — machine-wide dev-port ledger, read from the Caddyfile.
#
# The local Caddyfile is the one file every local-hosted project on this
# machine already writes to (scripts/setup_dev_slots.sh appends a
# `# BEGIN <sub>-dev-slots` block per project), so it is the ledger of record
# for which port ranges are consumed and by whom. This script reads it and
# answers the question the first-contact interview used to ask the user:
# "what port range is free?"
#
# Two sources of truth inside the Caddyfile, both parsed:
#   1. Ledger headers written by setup_dev_slots.sh (FWADR-019 Decision 2):
#        # BEGIN <sub>-dev-slots (managed by scripts/setup_dev_slots.sh) PORTS=<low>-<high> PROJECT=<name> DIR=<path>
#      These record the FULL reserved range (PROJECT_PORTS), not just the four
#      slot ports, and are written for non-HTTP projects too (comment-only
#      block, which Caddy ignores) so every project appears here.
#   2. Every `reverse_proxy ... localhost:<port>` / `127.0.0.1:<port>` / `:<port>`
#      line, attributed to its enclosing `# BEGIN <name>` block or, outside any
#      block, to the site label — so hand-written blocks are counted too.
#
# Usage (run from $PROJECT_DIR, or anywhere — the Caddyfile is machine-global):
#   scripts/port_ledger.sh                    # table of consumed ranges + overlap warnings
#   scripts/port_ledger.sh --propose [N]      # print the next free range of N ports (default 10)
#   scripts/port_ledger.sh --check LOW-HIGH   # exit 2 if LOW-HIGH overlaps anything consumed
#   scripts/port_ledger.sh --ignore <sub>-dev-slots  # drop that block first (a project re-checking its own range)
#   scripts/port_ledger.sh --caddyfile PATH   # override Caddyfile discovery (also: CADDYFILE env)
#
# Exit codes: 0 clean · 1 usage / unreadable Caddyfile · 2 overlaps found.
# Read-only: this script never writes the Caddyfile. Local-hosted mode only —
# remote-hosted projects have no local Caddyfile (dev-environment.md §"Port
# allocation (local-hosted)").
#
# Canonical doctrine: docs/dev_framework/adrs/fwadr-019-dev-slots-and-deploy-stubs.md

set -euo pipefail

MODE="table"
PROPOSE_N=10
CHECK_RANGE=""
CADDY_PATH="${CADDYFILE:-}"
IGNORE_OWNER=""
FLOOR=3000   # never propose below this; avoids the 1024-2999 band of common daemons
# Well-known dev/daemon defaults, treated as claimed so a proposal never lands
# on one (dev-environment.md §"Port allocation": avoid 3000/8000/8080-style defaults).
WELL_KNOWN="3000 3306 5000 5173 5432 6379 8000 8080 8888 27017"

usage() { sed -n '2,30p' "$0" | sed 's/^# \{0,1\}//'; exit 1; }

while (( $# > 0 )); do
  case "$1" in
    --propose)
      MODE="propose"
      if [[ "${2:-}" =~ ^[0-9]+$ ]]; then PROPOSE_N="$2"; shift; fi ;;
    --check)
      MODE="check"; CHECK_RANGE="${2:-}"; shift
      [[ "$CHECK_RANGE" =~ ^[0-9]+-[0-9]+$ ]] || { echo "port_ledger: --check wants LOW-HIGH, got '$CHECK_RANGE'" >&2; exit 1; } ;;
    --caddyfile) CADDY_PATH="${2:-}"; shift ;;
    --ignore)    IGNORE_OWNER="${2:-}"; shift ;;
    -h|--help) usage ;;
    *) echo "port_ledger: unknown argument '$1'" >&2; usage ;;
  esac
  shift
done

# ---------- Locate the Caddyfile (same candidates as setup_dev_slots.sh) ----------
if [[ -z "$CADDY_PATH" ]]; then
  for cand in /opt/homebrew/etc/Caddyfile /usr/local/etc/Caddyfile /etc/caddy/Caddyfile "$HOME/Caddyfile"; do
    [[ -f "$cand" ]] && { CADDY_PATH="$cand"; break; }
  done
fi

if [[ -z "$CADDY_PATH" || ! -r "$CADDY_PATH" ]]; then
  echo "port_ledger: no readable Caddyfile found (tried the Homebrew, /usr/local, /etc/caddy and \$HOME locations; set CADDYFILE= or pass --caddyfile)." >&2
  case "$MODE" in
    propose) echo "port_ledger: ledger is empty — proposing the floor." >&2; echo "$FLOOR-$((FLOOR + PROPOSE_N - 1))"; exit 0 ;;
    check)   echo "port_ledger: nothing to check against; treating $CHECK_RANGE as free." >&2; exit 0 ;;
    *)       exit 1 ;;
  esac
fi

# ---------- Parse: emit one TSV record per claim ----------
# kind  owner  low  high  detail
#   range  <block>            low high  DIR=<path>
#   port   <block|site>       p   p     <site hostname>
RECORDS="$(awk '
  function emit_port(p,   owner) {
    owner = (block != "") ? block : ((site != "") ? "unmanaged:" site : "unmanaged")
    printf "port\t%s\t%d\t%d\t%s\n", owner, p, p, (site != "" ? site : "-")
  }
  /^# BEGIN / {
    block = $3
    if (match($0, /PORTS=[0-9]+-[0-9]+/)) {
      r = substr($0, RSTART + 6, RLENGTH - 6); split(r, lh, "-")
      dir = "-"; if (match($0, /DIR=.*$/)) dir = substr($0, RSTART + 4)
      printf "range\t%s\t%d\t%d\t%s\n", block, lh[1], lh[2], dir
    }
    next
  }
  /^# END / { block = ""; site = ""; next }
  /^#/ { next }
  # Site label: a non-indented line ending in "{" at brace depth 0.
  depth == 0 && /^[^ \t{}#][^{}]*\{[ \t]*$/ { site = $1 }
  /reverse_proxy/ {
    line = $0
    while (match(line, /(^|[ \t])(localhost|127\.0\.0\.1)?:[0-9]+/)) {
      tok = substr(line, RSTART, RLENGTH); sub(/^.*:/, "", tok); emit_port(tok)
      line = substr(line, RSTART + RLENGTH)
    }
  }
  { n = gsub(/\{/, "{"); m = gsub(/\}/, "}"); depth += n - m; if (depth == 0 && m > 0) site = "" }
' "$CADDY_PATH")"

for wk in $WELL_KNOWN; do
  RECORDS="${RECORDS}${RECORDS:+$'\n'}port	well-known-default	$wk	$wk	common dev/daemon default"
done

if [[ -n "$IGNORE_OWNER" && -n "$RECORDS" ]]; then
  RECORDS="$(printf '%s\n' "$RECORDS" | awk -F'\t' -v ig="$IGNORE_OWNER" '$2 != ig')"
fi

if [[ -z "$RECORDS" ]]; then
  echo "port_ledger: $CADDY_PATH holds no reverse_proxy lines or ledger headers." >&2
  [[ "$MODE" == "propose" ]] && { echo "$FLOOR-$((FLOOR + PROPOSE_N - 1))"; exit 0; }
  exit 0
fi

# ---------- Overlaps: any two claims with different owners that intersect ----------
# A port inside its own block's ledger range is not a conflict (the range covers it).
OVERLAPS="$(printf '%s\n' "$RECORDS" | awk -F'\t' '
  { k[NR]=$1; o[NR]=$2; lo[NR]=$3; hi[NR]=$4; d[NR]=$5 }
  END {
    for (i = 1; i <= NR; i++) for (j = i + 1; j <= NR; j++) {
      if (o[i] == o[j]) continue
      if (o[i] == "well-known-default" || o[j] == "well-known-default") continue
      if (lo[i] <= hi[j] && lo[j] <= hi[i]) {
        a = (k[i]=="range") ? lo[i]"-"hi[i] : lo[i]
        b = (k[j]=="range") ? lo[j]"-"hi[j] : lo[j]
        printf "  %s (%s)  <->  %s (%s)\n", a, o[i], b, o[j]
      }
    }
  }')"

# ---------- Next free range: lowest decade-aligned block of N at or above FLOOR ----------
# Lowest gap, not "above the highest claim" — one project parked at 8080 must not
# push every later project into the 8000s.
NEXT_FREE="$(printf '%s\n' "$RECORDS" | awk -F'\t' -v floor="$FLOOR" -v n="$PROPOSE_N" '
  { lo[NR]=$3; hi[NR]=$4 }
  END {
    for (base = floor; base + n - 1 <= 65535; base += 10) {
      free = 1
      for (i = 1; i <= NR; i++) if (lo[i] <= base + n - 1 && base <= hi[i]) { free = 0; break }
      if (free) { printf "%d-%d\n", base, base + n - 1; exit }
    }
  }')"

case "$MODE" in
  table)
    echo "Dev-port ledger — $CADDY_PATH"
    echo ""
    printf '%-12s  %-36s  %-8s  %s\n' "PORTS" "OWNER (Caddy block / site)" "KIND" "DETAIL"
    printf '%s\n' "$RECORDS" | sort -t$'\t' -k3,3n -k1,1r | awk -F'\t' '{
      r = ($1=="range") ? $3"-"$4 : $3
      printf "%-12s  %-36s  %-8s  %s\n", r, $2, ($1=="range" ? "reserved" : "port"), $5
    }'
    echo ""
    if [[ -n "$OVERLAPS" ]]; then
      echo "OVERLAPS — these claims collide across projects:"
      printf '%s\n' "$OVERLAPS"
      echo ""
      echo "Resolve by moving one project's PROJECT_PORTS (.env) and re-running its scripts/setup_dev_slots.sh."
      echo "Next free range of $PROPOSE_N: $NEXT_FREE"
      exit 2
    fi
    echo "No overlaps. Next free range of $PROPOSE_N: $NEXT_FREE"
    ;;
  propose)
    echo "$NEXT_FREE"
    ;;
  check)
    lo="${CHECK_RANGE%-*}"; hi="${CHECK_RANGE#*-}"
    HITS="$(printf '%s\n' "$RECORDS" | awk -F'\t' -v lo="$lo" -v hi="$hi" '
      ($3 <= hi && lo <= $4) { r = ($1=="range") ? $3"-"$4 : $3; printf "  %s (%s)\n", r, $2 }')"
    if [[ -n "$HITS" ]]; then
      echo "port_ledger: $CHECK_RANGE overlaps existing claims in $CADDY_PATH:"
      printf '%s\n' "$HITS"
      echo "port_ledger: next free range of $PROPOSE_N would be $NEXT_FREE"
      exit 2
    fi
    echo "port_ledger: $CHECK_RANGE is free (no overlap with $CADDY_PATH)."
    ;;
esac
