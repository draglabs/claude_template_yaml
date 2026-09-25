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
# Which repo: --repo <subdir> names the code repo (multi-repo projects run the
# script once per deployable repo); without it, DEFAULT_CODE_SUBDIR from .env;
# only when neither names a repo does $PWD itself count (flat layout). A
# git-tracked parent (FWADR-021) is never the target by accident.
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
# GIT_FLOW=trunk          usage: promote_dev_to_main.sh [--repo <subdir>] v<X.Y.Z> [-m <msg>] [--bypass]
#   (default)  Phase-exit release. Verifies main is checked out, the named
#              annotated tag points at HEAD, and HEAD is already on
#              origin/main (so dev-environment CI has run on exactly this
#              commit), then pushes the tag. Production CI deploys on the tag.
#              -m creates the annotated tag on HEAD in the resolved repo
#              (message shape: session-policy.md §"Promotion commit");
#              without -m the tag must already exist there.
#              Tags are per repo: each deployable repo versions independently.
#   --bypass   Emergency release: pushes main and the tag together, skipping
#              the already-on-origin check. Loud on purpose.
#
# The script name is kept across modes so every doc pointer stays valid.
#
# FRAMEWORK-OWNED — overwritten on every sync; do not edit (FWADR-014).

set -euo pipefail

BYPASS=0
TAG=""
MSG=""
REPO=""
usage() {
  echo "usage: promote_dev_to_main.sh [--repo <subdir>] [--bypass]                      (GIT_FLOW=dev-main)" >&2
  echo "       promote_dev_to_main.sh [--repo <subdir>] v<X.Y.Z> [-m <msg>] [--bypass]   (GIT_FLOW=trunk)" >&2
  exit 2
}
while [[ $# -gt 0 ]]; do
  case "$1" in
    --bypass)   BYPASS=1 ;;
    --repo)     [[ $# -ge 2 ]] || usage; REPO="$2"; shift ;;
    --repo=*)   REPO="${1#--repo=}" ;;
    -m)         [[ $# -ge 2 ]] || usage; MSG="$2"; shift ;;
    v[0-9]*)    TAG="$1" ;;
    *)          usage ;;
  esac
  shift
done

# GIT_FLOW: process env (claude-env launch) or the .env in this directory.
if [[ -z "${GIT_FLOW:-}" && -f .env ]]; then
  GIT_FLOW="$({ grep -E '^GIT_FLOW=' .env || true; } | head -1 | cut -d= -f2- | tr -d '"'"'"'"')"
fi
[[ "${GIT_FLOW:-}" == "trunk" ]] || GIT_FLOW="dev-main"

if [[ -n "${FRAMEWORK_ALLOW_MAIN_PUSH:-}" ]]; then
  echo "[promote] WARN: FRAMEWORK_ALLOW_MAIN_PUSH is already set in your environment." >&2
  echo "[promote] The push guard may be permanently bypassed — find and remove the" >&2
  echo "[promote] stray export (check .env and shell profiles), then re-run." >&2
  exit 2
fi

# Resolve $CODE_ROOT: --repo, else DEFAULT_CODE_SUBDIR (split layout), else
# $PWD only if it is itself the repo (flat layout). The subdir is checked
# BEFORE $PWD/.git so a git-tracked parent is never released by accident.
CODE_ROOT=""
if [[ -n "$REPO" ]]; then
  if [[ ! -e "$PWD/$REPO/.git" ]]; then
    echo "[promote] ERROR: --repo $REPO: no git repo at $PWD/$REPO." >&2
    exit 2
  fi
  CODE_ROOT="$PWD/$REPO"
else
  CODE_SUBDIR=""
  if [[ -f .env ]]; then
    CODE_SUBDIR="$({ grep -E '^DEFAULT_CODE_SUBDIR=' .env || true; } | head -1 | cut -d= -f2- \
                    | sed 's/^["'"'"']//; s/["'"'"']$//')"
  fi
  if [[ -n "$CODE_SUBDIR" && "$CODE_SUBDIR" != "PLACEHOLDER" && -e "$PWD/$CODE_SUBDIR/.git" ]]; then
    CODE_ROOT="$PWD/$CODE_SUBDIR"
  elif [[ -e .git ]]; then
    # Flat layout — unless this is a git-tracked parent holding code repos,
    # where guessing would release the wrong repo.
    if compgen -G "*/.git" >/dev/null; then
      echo "[promote] ERROR: $PWD is a git-tracked parent holding code repos, and no" >&2
      echo "[promote] DEFAULT_CODE_SUBDIR is set. Name the repo: --repo <subdir>." >&2
      exit 2
    fi
    CODE_ROOT="$PWD"
  fi
fi

if [[ -z "$CODE_ROOT" ]]; then
  echo "[promote] ERROR: cannot resolve \$CODE_ROOT. Run from \$PROJECT_DIR with" >&2
  echo "[promote] --repo <subdir> or DEFAULT_CODE_SUBDIR set in .env (split layout)," >&2
  echo "[promote] or from the git repo itself (flat layout)." >&2
  exit 2
fi

cd "$CODE_ROOT"
echo "[promote] repo: $CODE_ROOT (GIT_FLOW=$GIT_FLOW)"

BRANCH="$(git rev-parse --abbrev-ref HEAD)"
if [[ "$BRANCH" != "main" ]]; then
  echo "[promote] ERROR: main is not checked out (on '$BRANCH'). The promotion" >&2
  echo "[promote] merge happens first, per session-policy.md §\"Phase exit gate\";" >&2
  echo "[promote] this script only performs the guarded push." >&2
  exit 1
fi

CREATE_TAG=0
make_tag() {
  [[ "$CREATE_TAG" -eq 1 ]] || return 0
  git tag -a "$TAG" -m "$MSG"
  echo "[promote] created annotated tag $TAG on HEAD of main in $CODE_ROOT."
}

if [[ "$GIT_FLOW" == "trunk" ]]; then
  if [[ -z "$TAG" ]]; then
    echo "[promote] ERROR: GIT_FLOW=trunk releases by tag — name it: promote_dev_to_main.sh v<X.Y.Z>" >&2
    exit 2
  fi
  if ! git rev-parse --verify -q "refs/tags/$TAG" >/dev/null; then
    if [[ -n "$MSG" ]]; then
      CREATE_TAG=1   # made on HEAD after the checks below pass
    else
      echo "[promote] ERROR: tag $TAG does not exist in $CODE_ROOT. Pass the release" >&2
      echo "[promote] message and the script creates it here (session-policy.md" >&2
      echo "[promote] §\"Promotion commit\"):  ... $TAG -m 'Release $TAG: <phase name> complete ...'" >&2
      exit 1
    fi
  elif [[ -n "$MSG" ]]; then
    echo "[promote] ERROR: tag $TAG already exists; -m would not apply. Drop -m to release it." >&2
    exit 2
  fi
  if [[ "$CREATE_TAG" -eq 0 && "$(git rev-parse "$TAG^{commit}")" != "$(git rev-parse HEAD)" ]]; then
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
    make_tag
    FRAMEWORK_ALLOW_MAIN_PUSH=1 git push origin "refs/tags/$TAG"
  else
    echo "[promote] BYPASS MODE — pushing main and $TAG together without the on-origin check."
    echo "[promote] Emergency duties still apply: [bypass] commit tag, 24h retrospective Reviewer, incident log."
    make_tag
    FRAMEWORK_ALLOW_MAIN_PUSH=1 git push origin main "refs/tags/$TAG"
  fi
  echo "[promote] $TAG pushed — production CI deploys the tagged commit."
  exit 0
fi

if [[ -n "$TAG" || -n "$MSG" ]]; then
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
