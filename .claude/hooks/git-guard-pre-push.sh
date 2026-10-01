#!/usr/bin/env bash
# git-guard-pre-push.sh — FRAMEWORK-PUSH-GUARD
#
# Git pre-push hook enforcing two framework rules at the push boundary:
#
#   1. RELEASE GUARD (FWADR-023, mode-aware per FWADR-035): blocks any push
#      that updates the project's RELEASE REF unless FRAMEWORK_ALLOW_MAIN_PUSH=1
#      is set in the environment. Which ref that is depends on GIT_FLOW:
#        dev-main (default) → refs/heads/main      (promotion merge)
#        trunk              → refs/tags/v*         (release tag), and in code
#                                                   repos also refs/heads/main:
#                                                   work lands on the trunk by
#                                                   PR, merged on the host. The
#                                                   tracking parent (a repo that
#                                                   holds code repos) pushes
#                                                   main freely — plan commits.
#      The only sanctioned setter of that variable is
#      scripts/promote_dev_to_main.sh (phase-exit release and, with --bypass,
#      the emergency path). GIT_FLOW is read from the process env, else from
#      $PROJECT_DIR/.env (repo root under flat layout, its parent under split).
#   2. ENV GUARD (FWADR-033): blocks any push whose ref tips track a file
#      named `.env` (any depth). App runtime secrets never belong in git.
#      FRAMEWORK_ALLOW_MAIN_PUSH does NOT bypass this check — there is no
#      env-var bypass at all (an .env-sourced bypass would disable the guard
#      permanently and silently). Deliberate deviations: see FWADR-033.
#
# Source of truth: .claude/hooks/git-guard-pre-push.sh in the canonical
# claude_template_yaml repo. sync-framework.sh installs it into each code
# repo's .git/hooks/pre-push on every SessionStart and refreshes it when the
# template copy changes. Do not edit the installed copy — edits are
# overwritten on the next sync. The FRAMEWORK-PUSH-GUARD marker in line 2 is
# how the installer distinguishes this hook from an adopter-owned pre-push
# (which it will never overwrite).
#
# NEVER put FRAMEWORK_ALLOW_MAIN_PUSH in .env — framework scripts source .env
# wholesale (set -a), which would leave the main guard permanently bypassed.
#
# See docs/dev_framework/adrs/fwadr-023-main-push-guard.md and
# docs/dev_framework/adrs/fwadr-033-env-scope-rule.md.

ZERO_SHA="0000000000000000000000000000000000000000"

# Resolve GIT_FLOW (FWADR-035). Worktrees share the main repo's hooks, so use
# the common git dir to find the repo root, then look for .env there (flat
# layout) or one level up (split layout, $PROJECT_DIR/.env).
if [[ -z "${GIT_FLOW:-}" ]]; then
  repo_root="$(cd "$(git rev-parse --git-common-dir 2>/dev/null || echo .git)/.." 2>/dev/null && pwd)"
  for envf in "$repo_root/.env" "$repo_root/../.env"; do
    if [[ -f "$envf" ]] && grep -qE '^GIT_FLOW=' "$envf" 2>/dev/null; then
      GIT_FLOW="$(grep -E '^GIT_FLOW=' "$envf" | head -1 | cut -d= -f2- | tr -d '"'"'"'"' )"
      break
    fi
  done
fi
[[ "${GIT_FLOW:-}" == "trunk" ]] || GIT_FLOW="dev-main"

# Is this the tracking parent (FWADR-021 tracked parent) rather than a code
# repo? Judged by child repos, never by a .env — every code repo may carry its
# own app .env (FWADR-033).
repo_root="${repo_root:-$(cd "$(git rev-parse --git-common-dir 2>/dev/null || echo .git)/.." 2>/dev/null && pwd)}"
IS_PARENT=0
for child in "$repo_root"/*/.git; do
  [[ -e "$child" ]] && { IS_PARENT=1; break; }
done

# stdin: one line per ref being pushed: <local ref> <local sha> <remote ref> <remote sha>
blocked_refs=""
env_hits=""
while read -r local_ref local_sha remote_ref remote_sha; do
  [[ -z "$remote_ref" ]] && continue

  if [[ "${FRAMEWORK_ALLOW_MAIN_PUSH:-}" != "1" ]]; then
    case "$GIT_FLOW" in
      trunk)    { [[ "$remote_ref" == refs/tags/v* ]] \
                  || { [[ "$remote_ref" == "refs/heads/main" ]] && [[ "$IS_PARENT" -eq 0 ]]; }; } \
                  && blocked_refs+="$remote_ref"$'\n' ;;
      dev-main) [[ "$remote_ref" == "refs/heads/main" ]]   && blocked_refs+="$remote_ref"$'\n' ;;
    esac
  fi

  # Env guard: skip deletions (no local objects to inspect). Tip tree only —
  # a .env in earlier history is out of this guard's reach (FWADR-033
  # §"Honest ceiling").
  if [[ "$local_sha" != "$ZERO_SHA" ]]; then
    tracked_env="$(git ls-tree -r --name-only "$local_sha" 2>/dev/null \
                    | grep -E '(^|/)\.env$' | head -5)"
    if [[ -n "$tracked_env" ]]; then
      env_hits+="  $remote_ref tracks: $(echo "$tracked_env" | tr '\n' ' ')"$'\n'
    fi
  fi
done

if [[ -n "$env_hits" ]]; then
  cat >&2 <<EOF
[push-guard] BLOCKED: a pushed ref tracks a committed .env file.
$env_hits
  App runtime secrets never belong in git (FWADR-033). Fix, then re-push:

    git rm --cached <path>        # un-track (keeps the working file)
    echo ".env" >> .gitignore     # if not already ignored
    git commit

  The file remains in earlier history — if it ever held real secrets,
  rotate them. See docs/dev_framework/adrs/fwadr-033-env-scope-rule.md.
EOF
  exit 1
fi

if [[ -n "$blocked_refs" ]]; then
  if [[ "$GIT_FLOW" == "trunk" && "$blocked_refs" == *refs/heads/main* ]]; then
    cat >&2 <<'EOF'
[push-guard] BLOCKED: this push updates main in a code repo.

  GIT_FLOW=trunk: work lands on main by PR, merged on the git host — one
  PR per finished W-item (or batch), never a direct push. Push your feature
  branch and open the PR:

    git push -u origin <w-id/slug>

  See docs/dev_framework/adrs/fwadr-035-git-flow-mode.md §"Landing under trunk".
EOF
  elif [[ "$GIT_FLOW" == "trunk" ]]; then
    cat >&2 <<'EOF'
[push-guard] BLOCKED: this push creates or moves a release tag (v*).

  GIT_FLOW=trunk: PRODUCTION is released by a v* tag, which only moves at
  phase exit through the sanctioned script (it verifies the tag sits on the
  pushed head of main):

    ./scripts/promote_dev_to_main.sh --repo <subdir> v<X.Y.Z> -m "<msg>"

  run from $PROJECT_DIR. See docs/dev_framework/adrs/fwadr-023-main-push-guard.md.
EOF
  else
    cat >&2 <<'EOF'
[push-guard] BLOCKED: this push updates main.

  GIT_FLOW=dev-main: main only moves at phase-exit promotion (or explicit
  emergency bypass), and only through the sanctioned script:

    ./scripts/promote_dev_to_main.sh            # phase-exit promotion
    ./scripts/promote_dev_to_main.sh --bypass   # emergency bypass ([bypass] commit)

  run from $PROJECT_DIR. Feature work merges to dev, never to main.
  See docs/dev_framework/adrs/fwadr-023-main-push-guard.md.
EOF
  fi
  exit 1
fi

exit 0
