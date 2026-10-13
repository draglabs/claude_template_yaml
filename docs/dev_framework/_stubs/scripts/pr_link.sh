#!/usr/bin/env bash
# pr_link.sh — print the git-host deep link for a PR / MR.
# FRAMEWORK-OWNED — overwritten on every sync; do not edit (FWADR-014).
#
# Every message that asks the user to review, approve or merge a PR carries
# the PR's host URL (CLAUDE.md §"Handing off a PR"; FWADR-035 §"Landing under
# trunk"). This script is the host-neutral resolver, so no role has to
# remember `gh` vs `glab` or build a URL by hand.
#
# Usage (from $PROJECT_DIR):
#   ./scripts/pr_link.sh [--repo <subdir>] [<number>]
#     <number> omitted → the open PR for the repo's current branch.
#
# Which repo: --repo <subdir>, else DEFAULT_CODE_SUBDIR from .env, else $PWD.
# Which host: GIT_HOST from the process env (claude-env launch), else .env.
# Self-hosted (GIT_HOST_URL) is honoured through the GH_HOST / GITLAB_HOST
# variables the .env auto-wire block exports (FWADR-030).
#
# Exit 0 and the URL on stdout. Exit 1 and the reason on stderr otherwise —
# never a guessed URL.

set -u

usage() {
  echo "usage: pr_link.sh [--repo <subdir>] [<number>]" >&2
  exit 1
}

REPO=""; NUM=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo)   [[ $# -ge 2 ]] || usage; REPO="$2"; shift ;;
    --repo=*) REPO="${1#--repo=}" ;;
    -h|--help) usage ;;
    *)        [[ -z "$NUM" ]] || usage; NUM="${1#[#!]}" ;;
  esac
  shift
done
[[ -z "$NUM" || "$NUM" =~ ^[0-9]+$ ]] || { echo "[pr_link] ERROR: '$NUM' is not a PR number." >&2; exit 1; }

env_val() { { grep -E "^$1=" .env 2>/dev/null || true; } | head -1 | cut -d= -f2- | tr -d '"'"'"; }

[[ -z "${GIT_HOST:-}" && -f .env ]] && GIT_HOST="$(env_val GIT_HOST)"

# Resolve $CODE_ROOT: --repo, else DEFAULT_CODE_SUBDIR (split layout), else $PWD.
CODE_ROOT=""
if [[ -n "$REPO" ]]; then
  [[ -d "$PWD/$REPO/.git" ]] || { echo "[pr_link] ERROR: --repo $REPO: no git repo at $PWD/$REPO." >&2; exit 1; }
  CODE_ROOT="$PWD/$REPO"
else
  CODE_SUBDIR=""
  [[ -f .env ]] && CODE_SUBDIR="$(env_val DEFAULT_CODE_SUBDIR)"
  if [[ -n "$CODE_SUBDIR" && "$CODE_SUBDIR" != "PLACEHOLDER" && -d "$PWD/$CODE_SUBDIR/.git" ]]; then
    CODE_ROOT="$PWD/$CODE_SUBDIR"
  elif git -C "$PWD" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    CODE_ROOT="$PWD"
  fi
fi
[[ -n "$CODE_ROOT" ]] || { echo "[pr_link] ERROR: cannot resolve the code repo. Run from \$PROJECT_DIR with --repo <subdir> or DEFAULT_CODE_SUBDIR set in .env." >&2; exit 1; }
cd "$CODE_ROOT" || exit 1

case "${GIT_HOST:-}" in
  github)
    command -v gh >/dev/null 2>&1 || { echo "[pr_link] ERROR: GIT_HOST=github but 'gh' is not installed." >&2; exit 1; }
    url="$(gh pr view ${NUM:+"$NUM"} --json url --jq .url 2>/dev/null)" ;;
  gitlab)
    command -v glab >/dev/null 2>&1 || { echo "[pr_link] ERROR: GIT_HOST=gitlab but 'glab' is not installed." >&2; exit 1; }
    json="$(glab mr view ${NUM:+"$NUM"} -F json 2>/dev/null)"
    if command -v jq >/dev/null 2>&1; then
      url="$(printf '%s' "$json" | jq -r '.web_url // empty' 2>/dev/null)"
    else
      url="$(printf '%s' "$json" | grep -o '"web_url":"[^"]*"' | head -1 | cut -d'"' -f4)"
    fi ;;
  ""|PLACEHOLDER)
    echo "[pr_link] ERROR: GIT_HOST is not set. Set it in \$PROJECT_DIR/.env (github | gitlab); see .env.example." >&2; exit 1 ;;
  *)
    echo "[pr_link] ERROR: GIT_HOST=$GIT_HOST has no resolver. Record the project's PR mechanism in docs/framework_exceptions/dev_framework_exceptions.md and link by hand." >&2; exit 1 ;;
esac

[[ -n "$url" && "$url" == http* ]] || {
  what="PR #$NUM"
  [[ -n "$NUM" ]] || what="an open PR for branch $(git rev-parse --abbrev-ref HEAD 2>/dev/null)"
  echo "[pr_link] ERROR: $what not found in $CODE_ROOT (host: $GIT_HOST). Is the host CLI authenticated and the PR open?" >&2
  exit 1
}
printf '%s\n' "$url"
