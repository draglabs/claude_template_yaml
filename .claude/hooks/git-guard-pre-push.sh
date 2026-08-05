#!/usr/bin/env bash
# git-guard-pre-push.sh — FRAMEWORK-PUSH-GUARD
#
# Git pre-push hook blocking any push that updates refs/heads/main unless
# FRAMEWORK_ALLOW_MAIN_PUSH=1 is set in the environment. The only sanctioned
# setter of that variable is scripts/promote_dev_to_main.sh (phase-exit
# promotion and, with --bypass, the emergency-bypass path).
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
# wholesale (set -a), which would leave the guard permanently bypassed.
#
# See docs/dev_framework/adrs/fwadr-023-main-push-guard.md.

if [[ "${FRAMEWORK_ALLOW_MAIN_PUSH:-}" == "1" ]]; then
  exit 0
fi

# stdin: one line per ref being pushed: <local ref> <local sha> <remote ref> <remote sha>
blocked_refs=""
while read -r local_ref local_sha remote_ref remote_sha; do
  [[ -z "$remote_ref" ]] && continue
  if [[ "$remote_ref" == "refs/heads/main" ]]; then
    blocked_refs+="$remote_ref"$'\n'
  fi
done

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
