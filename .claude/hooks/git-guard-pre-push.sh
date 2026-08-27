#!/usr/bin/env bash
# git-guard-pre-push.sh — FRAMEWORK-PUSH-GUARD
#
# Git pre-push hook enforcing two framework rules at the push boundary:
#
#   1. MAIN GUARD (FWADR-023): blocks any push that updates refs/heads/main
#      unless FRAMEWORK_ALLOW_MAIN_PUSH=1 is set in the environment. The only
#      sanctioned setter of that variable is scripts/promote_dev_to_main.sh
#      (phase-exit promotion and, with --bypass, the emergency-bypass path).
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

# stdin: one line per ref being pushed: <local ref> <local sha> <remote ref> <remote sha>
blocked_refs=""
env_hits=""
while read -r local_ref local_sha remote_ref remote_sha; do
  [[ -z "$remote_ref" ]] && continue

  if [[ "$remote_ref" == "refs/heads/main" && "${FRAMEWORK_ALLOW_MAIN_PUSH:-}" != "1" ]]; then
    blocked_refs+="$remote_ref"$'\n'
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
  cat >&2 <<'EOF'
[push-guard] BLOCKED: this push updates main.

  main only moves at phase-exit promotion (or explicit emergency bypass),
  and only through the sanctioned script:

    ./scripts/promote_dev_to_main.sh            # phase-exit promotion
    ./scripts/promote_dev_to_main.sh --bypass   # emergency bypass ([bypass] commit)

  run from $PROJECT_DIR. Feature work merges to dev, never to main.
  See docs/dev_framework/adrs/fwadr-023-main-push-guard.md.
EOF
  exit 1
fi

exit 0
