#!/usr/bin/env bash
# check-env-comments.sh — env-style files carry at most two comment lines per value.
# FRAMEWORK-OWNED — overwritten on every sync; do not edit (FWADR-014).
#
# Usage:
#   check-env-comments.sh [file ...]
#
# With no arguments, checks every env-style file under the current directory
# (depth 3, skipping .git and node_modules): .env, .env.*, *.env, and
# docker-compose*/compose* YAML. Prints file:line and the run length for every
# run of more than two consecutive comment lines — never the lines themselves,
# since .env files hold secrets. Blank lines, values, and commented-out values
# (`# NAME=`) end a run.
#
# Exit codes: 0 clean, 1 findings printed, 2 usage error / no files found.
# Rule: docs/dev_framework/coding-standards.md §"Environment variables".

set -euo pipefail

MAX=2
files=()
if [[ $# -gt 0 ]]; then
  for f in "$@"; do
    if [[ ! -f "$f" ]]; then
      echo "check-env-comments: not a file: $f" >&2
      exit 2
    fi
    files+=("$f")
  done
else
  while IFS= read -r f; do files+=("$f"); done < <(
    find . -maxdepth 3 \( -name .git -o -name node_modules \) -prune -o -type f \
      \( -name '.env' -o -name '.env.*' -o -name '*.env' \
         -o -name 'docker-compose*.yml' -o -name 'docker-compose*.yaml' \
         -o -name 'compose*.yml' -o -name 'compose*.yaml' \) -print | sort
  )
fi
if [[ ${#files[@]} -eq 0 ]]; then
  echo "check-env-comments: no env-style files found under $(pwd)" >&2
  exit 2
fi

findings=0
for f in "${files[@]}"; do
  out="$(awk -v max="$MAX" -v file="$f" '
    /^[[:space:]]*#[[:space:]]*[A-Za-z_][A-Za-z0-9_]*=/ { if (run > max) printf "%s:%d: %d consecutive comment lines (max %d)\n", file, start, run, max; run = 0; next }
    /^[[:space:]]*#/ { if (run == 0) start = NR; run++; next }
    { if (run > max) printf "%s:%d: %d consecutive comment lines (max %d)\n", file, start, run, max; run = 0 }
    END { if (run > max) printf "%s:%d: %d consecutive comment lines (max %d)\n", file, start, run, max }
  ' "$f")"
  if [[ -n "$out" ]]; then
    printf '%s\n' "$out"
    findings=$((findings + $(printf '%s\n' "$out" | wc -l)))
  fi
done

if (( findings > 0 )); then
  echo "check-env-comments: $findings finding(s) — one or two comment lines per value; the rest belongs in a doc" >&2
  exit 1
fi
echo "check-env-comments: OK — ${#files[@]} file(s), no comment run over $MAX lines"
exit 0
