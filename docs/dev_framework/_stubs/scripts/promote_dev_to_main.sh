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
# Behaviour follows GIT_FLOW in .env (FWADR-035):
#
# GIT_FLOW=dev-main (default)          usage: promote_dev_to_main.sh [--bypass]
#   (default)  Phase-exit promotion. Verifies main is checked out and HEAD is
#              a merge commit whose second parent is dev's head (i.e. the
#              annotated promotion merge per session-policy.md §"Promotion
#              commit" has already been made), then pushes main.
#   --bypass   Emergency bypass push (session-policy.md §"Emergency bypass").
#              Skips the merge-shape check — for [bypass]-tagged commits made
#              directly on main during a production fire. Loud on purpose.
#
# GIT_FLOW=trunk                       usage: promote_dev_to_main.sh v<X.Y.Z> [--bypass]
#   (default)  Phase-exit release. Verifies main is checked out, the named
#              annotated tag exists and points at HEAD, and HEAD is already
#              on origin/main (so dev-environment CI has run on exactly this
#              commit), then pushes the tag. Production CI deploys on the tag.
#              The tag itself is made first, by the Orchestrator/Developer,
#              with the shape in session-policy.md §"Promotion commit".
#   --bypass   Emergency release: pushes main and the tag together, skipping
#              the already-on-origin check. Loud on purpose.
#
# The script name is kept across modes so every doc pointer stays valid.
#
# Generic script — no project-specific body to fill in.

set -euo pipefail

BYPASS=0
TAG=""
for arg in "$@"; do
  case "$arg" in
    --bypass) BYPASS=1 ;;
    v[0-9]*)  TAG="$arg" ;;
    *) echo "usage: promote_dev_to_main.sh [--bypass]            (GIT_FLOW=dev-main)" >&2
       echo "       promote_dev_to_main.sh v<X.Y.Z> [--bypass]   (GIT_FLOW=trunk)" >&2
       exit 2 ;;
  esac
done

# GIT_FLOW: process env (claude-env launch) or the .env in this directory.
if [[ -z "${GIT_FLOW:-}" && -f .env ]]; then
  GIT_FLOW="$(grep -E '^GIT_FLOW=' .env | head -1 | cut -d= -f2- | tr -d '"'"'"'"')"
fi
[[ "${GIT_FLOW:-}" == "trunk" ]] || GIT_FLOW="dev-main"

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

if [[ "$GIT_FLOW" == "trunk" ]]; then
  if [[ -z "$TAG" ]]; then
    echo "[promote] ERROR: GIT_FLOW=trunk releases by tag — name it: promote_dev_to_main.sh v<X.Y.Z>" >&2
    exit 2
  fi
  if ! git rev-parse --verify -q "refs/tags/$TAG" >/dev/null; then
    echo "[promote] ERROR: tag $TAG does not exist. Create the annotated release tag" >&2
    echo "[promote] first (session-policy.md §\"Promotion commit\"), e.g.:" >&2
    echo "[promote]   git tag -a $TAG -m 'Release $TAG: <phase name> complete ...'" >&2
    exit 1
  fi
  if [[ "$(git rev-parse "$TAG^{commit}")" != "$(git rev-parse HEAD)" ]]; then
    echo "[promote] ERROR: $TAG does not point at HEAD of main. Release the CURRENT" >&2
    echo "[promote] trunk state — re-tag, or investigate what moved." >&2
    exit 1
  fi
  if [[ "$BYPASS" -eq 0 ]]; then
    git fetch -q origin main
    if [[ "$(git rev-parse origin/main)" != "$(git rev-parse HEAD)" ]]; then
      echo "[promote] ERROR: HEAD is not on origin/main yet. Push main first so the dev" >&2
      echo "[promote] environment CI runs on exactly this commit, QA it, then release." >&2
      echo "[promote] (--bypass pushes main and the tag together — emergencies only.)" >&2
      exit 1
    fi
    FRAMEWORK_ALLOW_MAIN_PUSH=1 git push origin "refs/tags/$TAG"
  else
    echo "[promote] BYPASS MODE — pushing main and $TAG together without the on-origin check."
    echo "[promote] Emergency duties still apply: [bypass] commit tag, 24h retrospective Reviewer, incident log."
    FRAMEWORK_ALLOW_MAIN_PUSH=1 git push origin main "refs/tags/$TAG"
  fi
  echo "[promote] $TAG pushed — production CI deploys the tagged commit."
  exit 0
fi

if [[ -n "$TAG" ]]; then
  echo "[promote] ERROR: a release tag was given but GIT_FLOW=dev-main promotes by merge, not tag." >&2
  exit 2
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
