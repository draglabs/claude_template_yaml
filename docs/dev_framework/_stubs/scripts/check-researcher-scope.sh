#!/usr/bin/env bash
# check-researcher-scope.sh — mechanical write-fence check for the Researcher
# role (FWADR-024). Verifies that every file changed vs the base ref is inside
# RESEARCHER_SCOPE_DIR or named in RESEARCHER_DATA_CARVEOUTS.
#
# Usage (run from $PROJECT_DIR, per FWADR-021 script placement doctrine):
#   ./scripts/check-researcher-scope.sh [<base-ref>]     # default: origin/dev
#
# Reads from $PROJECT_DIR/.env:
#   RESEARCHER_SCOPE_DIR      — the one directory the Researcher may modify
#                               (path relative to $CODE_ROOT)
#   RESEARCHER_DATA_CARVEOUTS — optional comma-separated exact file paths
#   DEFAULT_CODE_SUBDIR       — split-layout repo resolution
#
# Exit codes:
#   0 — every changed file is within scope.
#   1 — out-of-scope changes; paths written to stdout, one per line.
#       Strip them or convert them into a server-work request — never merge.
#   2 — Researcher not configured (missing/PLACEHOLDER vars) or usage error.
#
# Generic script — no project-specific body to fill in.

set -euo pipefail

BASE_REF="${1:-origin/dev}"

env_val() {
  grep -E "^$1=" .env 2>/dev/null | head -1 | cut -d= -f2- \
    | sed 's/^["'"'"']//; s/["'"'"']$//'
}

if [[ ! -f .env ]]; then
  echo "check-researcher-scope: no .env in $PWD — run from \$PROJECT_DIR" >&2
  exit 2
fi

SCOPE_DIR="$(env_val RESEARCHER_SCOPE_DIR)"
CARVEOUTS="$(env_val RESEARCHER_DATA_CARVEOUTS)"

if [[ -z "$SCOPE_DIR" || "$SCOPE_DIR" == "PLACEHOLDER" ]]; then
  echo "check-researcher-scope: RESEARCHER_SCOPE_DIR is not configured in .env —" >&2
  echo "the Researcher role is not activated for this project (see" >&2
  echo "docs/dev_framework/researcher.md §\"Activation\")." >&2
  exit 2
fi
SCOPE_DIR="${SCOPE_DIR%/}"

# Resolve $CODE_ROOT: flat layout (this dir is the repo) or split layout.
if [[ -d .git ]]; then
  CODE_ROOT="$PWD"
else
  CODE_SUBDIR="$(env_val DEFAULT_CODE_SUBDIR)"
  if [[ -n "$CODE_SUBDIR" && "$CODE_SUBDIR" != "PLACEHOLDER" && -d "$PWD/$CODE_SUBDIR/.git" ]]; then
    CODE_ROOT="$PWD/$CODE_SUBDIR"
  else
    echo "check-researcher-scope: cannot resolve \$CODE_ROOT (no .git here, no usable DEFAULT_CODE_SUBDIR)" >&2
    exit 2
  fi
fi

cd "$CODE_ROOT"

CHANGED="$(git diff --name-only "$BASE_REF" 2>/dev/null || true)"
[[ -z "$CHANGED" ]] && exit 0

OUT_OF_SCOPE=""
while IFS= read -r f; do
  [[ -z "$f" ]] && continue
  if [[ "$f" == "$SCOPE_DIR"/* ]]; then
    continue
  fi
  in_carveout=0
  if [[ -n "$CARVEOUTS" ]]; then
    IFS=',' read -ra CARVE_ARR <<< "$CARVEOUTS"
    for c in "${CARVE_ARR[@]}"; do
      c="$(echo "$c" | sed 's/^ *//; s/ *$//')"
      if [[ -n "$c" && "$f" == "$c" ]]; then
        in_carveout=1
        break
      fi
    done
  fi
  [[ "$in_carveout" -eq 1 ]] && continue
  OUT_OF_SCOPE+="$f"$'\n'
done <<< "$CHANGED"

if [[ -n "$OUT_OF_SCOPE" ]]; then
  printf "%s" "$OUT_OF_SCOPE"
  exit 1
fi

exit 0
