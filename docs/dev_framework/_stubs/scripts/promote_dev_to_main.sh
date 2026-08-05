#!/usr/bin/env bash
# promote_dev_to_main.sh — the ONLY sanctioned way to push main (FWADR-023).
#
# The framework installs a git pre-push hook (FRAMEWORK-PUSH-GUARD) that
# blocks every push updating refs/heads/main unless FRAMEWORK_ALLOW_MAIN_PUSH=1.
# This script is the single place that variable gets set. Never set it by
# hand, never export it in a shell profile, and NEVER put it in .env
# (framework scripts source .env wholesale — the guard would be permanently
# bypassed).
#
# Run from $PROJECT_DIR (parent dir under split layout), like every framework
# script (FWADR-021 script placement doctrine).
#
# Modes:
#   (default)  Phase-exit promotion. Verifies main is checked out and HEAD is
#              a merge commit whose second parent is dev's head (i.e. the
#              annotated promotion merge per session-policy.md §"Promotion
#              commit" has already been made), then pushes main.
#   --bypass   Emergency bypass push (session-policy.md §"Emergency bypass").
#              Skips the merge-shape check — for [bypass]-tagged commits made
#              directly on main during a production fire. Loud on purpose.
#
# Generic script — no project-specific body to fill in.

set -euo pipefail

BYPASS=0
if [[ "${1:-}" == "--bypass" ]]; then
  BYPASS=1
elif [[ $# -gt 0 ]]; then
  echo "usage: promote_dev_to_main.sh [--bypass]" >&2
  exit 2
fi

if [[ -n "${FRAMEWORK_ALLOW_MAIN_PUSH:-}" ]]; then
  echo "[promote] WARN: FRAMEWORK_ALLOW_MAIN_PUSH is already set in your environment." >&2
  echo "[promote] The push guard may be permanently bypassed — find and remove the" >&2
  echo "[promote] stray export (check .env and shell profiles), then re-run." >&2
  exit 2
fi

# Resolve $CODE_ROOT: flat layout (this dir is the repo) or split layout
# (DEFAULT_CODE_SUBDIR from .env names the repo subdir).
CODE_ROOT=""
if [[ -d .git ]]; then
  CODE_ROOT="$PWD"
elif [[ -f .env ]]; then
  CODE_SUBDIR="$(grep -E '^DEFAULT_CODE_SUBDIR=' .env | head -1 | cut -d= -f2- \
                  | sed 's/^["'"'"']//; s/["'"'"']$//')"
  if [[ -n "$CODE_SUBDIR" && "$CODE_SUBDIR" != "PLACEHOLDER" && -d "$PWD/$CODE_SUBDIR/.git" ]]; then
    CODE_ROOT="$PWD/$CODE_SUBDIR"
  fi
fi

if [[ -z "$CODE_ROOT" ]]; then
  echo "[promote] ERROR: cannot resolve \$CODE_ROOT. Run from \$PROJECT_DIR with" >&2
  echo "[promote] DEFAULT_CODE_SUBDIR set in .env (split layout), or from the git" >&2
  echo "[promote] repo itself (flat layout)." >&2
  exit 2
fi

cd "$CODE_ROOT"

BRANCH="$(git rev-parse --abbrev-ref HEAD)"
if [[ "$BRANCH" != "main" ]]; then
  echo "[promote] ERROR: main is not checked out (on '$BRANCH'). The promotion" >&2
  echo "[promote] merge happens first, per session-policy.md §\"Phase exit gate\";" >&2
  echo "[promote] this script only performs the guarded push." >&2
  exit 1
fi

if [[ "$BYPASS" -eq 0 ]]; then
  # Phase-exit shape check: HEAD must be a merge whose second parent is dev.
  if ! SECOND_PARENT="$(git rev-parse --verify -q HEAD^2)"; then
    echo "[promote] ERROR: HEAD is not a merge commit. Phase-exit promotion pushes" >&2
    echo "[promote] the annotated dev → main merge (session-policy.md §\"Promotion" >&2
    echo "[promote] commit\"). For an emergency [bypass] commit, use --bypass." >&2
    exit 1
  fi
  DEV_HEAD="$(git rev-parse --verify -q dev)" || {
    echo "[promote] ERROR: no local dev branch found." >&2
    exit 1
  }
  if [[ "$SECOND_PARENT" != "$DEV_HEAD" ]]; then
    echo "[promote] ERROR: HEAD's merge parent ($SECOND_PARENT) is not dev's head" >&2
    echo "[promote] ($DEV_HEAD). Promote the CURRENT dev state — re-merge, or" >&2
    echo "[promote] investigate what moved dev since the promotion merge." >&2
    exit 1
  fi
else
  echo "[promote] BYPASS MODE — pushing main without the promotion-shape check."
  echo "[promote] Session-policy emergency-bypass duties still apply: [bypass] tag,"
  echo "[promote] immediate back-merge to dev, 24h retrospective Reviewer, incident log."
fi

FRAMEWORK_ALLOW_MAIN_PUSH=1 git push origin main
echo "[promote] main pushed."
