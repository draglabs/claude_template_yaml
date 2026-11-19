#!/usr/bin/env bash
# git-guard-pre-push.sh — FRAMEWORK-PUSH-GUARD
#
# Git pre-push hook enforcing three framework rules at the push boundary:
#
#   1. LANDING AND RELEASE GUARD (FWADR-023, FWADR-035, FWADR-042). In a code
#      repo it blocks:
#        - any push that updates refs/heads/main: work lands on main by PR,
#          merged on the git host;
#        - any push of a tag: a release tag is cut on the git host by the
#          repo's release job when the stakeholder approves in the QA view.
#      The tracking parent (a repo that holds code repos) pushes main and
#      tags freely — plan commits. There is no bypass: no variable, no script.
#   2. ENV GUARD (FWADR-033): blocks any push whose ref tips track a file
#      named `.env` or `.sops-age-key.txt` (any depth). A plaintext env file
#      and the decryption key never belong in git.
#   3. ENV.YAML GUARD (FWADR-041): blocks any push whose ref tips hold a root
#      `env.yaml` that is not encrypted: a `value` field that is not
#      ciphertext, a file SOPS never wrote, or a `plain` item under a name that
#      looks like a secret without `secret: false`.
#
# Source of truth: .claude/hooks/git-guard-pre-push.sh in the canonical
# claude_template_yaml repo. sync-framework.sh installs it into each code
# repo's .git/hooks/pre-push on every SessionStart and refreshes it when the
# template copy changes. Do not edit the installed copy — edits are
# overwritten on the next sync. The FRAMEWORK-PUSH-GUARD marker in line 2 is
# how the installer distinguishes this hook from an adopter-owned pre-push
# (which it will never overwrite). Deliberate deviations: record them in
# dev_framework_exceptions.md and fork the hook (drop the marker).
#
# See docs/dev_framework/adrs/fwadr-023-main-push-guard.md,
# fwadr-033-env-scope-rule.md and fwadr-041-env-yaml.md.

ZERO_SHA="0000000000000000000000000000000000000000"

# Is this the tracking parent (FWADR-021 tracked parent) rather than a code
# repo? Judged by child repos, never by a .env — every code repo may carry its
# own app .env (FWADR-033). Worktrees share the main repo's hooks, so the
# common git dir finds the repo root.
repo_root="$(cd "$(git rev-parse --git-common-dir 2>/dev/null || echo .git)/.." 2>/dev/null && pwd)"
IS_PARENT=0
for child in "$repo_root"/*/.git; do
  [[ -e "$child" ]] && { IS_PARENT=1; break; }
done

# ENV.YAML GUARD: findings for the env.yaml on stdin, one per line; silent when
# clean. The two patterns are the ones in scripts/env_yaml.py; change them
# together.
env_yaml_findings() {
  awk '
    function flush() {
      if (initem && plain && !notsecret && toupper(name) ~ /SECRET|TOKEN|PASSWORD|PASSWD|PRIVATE|CREDENTIAL|_KEY($|_)|DATABASE_URL/)
        print name ": plain, but the name looks like a secret (use `value`, or add `secret: false`)"
      initem = 0; plain = 0; notsecret = 0
    }
    /^vars:/ { invars = 1; next }
    /^sops:/ { wrote = 1 }
    /^[^ #]/ { flush(); invars = 0 }
    /^ *(- +)?value:/ {
      v = $0; sub(/^ *(- +)?value: */, "", v)
      if (v !~ /^ENC\[AES256_GCM,/ && v != "\"\"" && v != "\047\047") { clear++; print "line " NR ": a `value` that is not encrypted" }
    }
    invars {
      ind = match($0, /[^ ]/) - 1
      if ($0 ~ /^ +[A-Za-z_][A-Za-z0-9_]*: *$/ && (!varind || ind == varind)) {
        flush(); varind = ind; itemind = 0; name = $0; gsub(/[ :]/, "", name); next
      }
      if ($0 ~ /^ +- / && (!itemind || ind == itemind)) { flush(); itemind = ind; initem = 1 }
      if ($0 ~ /^ *(- +)?plain:/) plain = 1
      if ($0 ~ /^ *(- +)?secret: *false *$/) notsecret = 1
    }
    END { flush(); if (!wrote && !clear) print "the file was never encrypted by SOPS (no `sops:` block)" }
  '
}

# stdin: one line per ref being pushed: <local ref> <local sha> <remote ref> <remote sha>
blocked_main=""
blocked_tags=""
env_hits=""
yaml_hits=""
while read -r local_ref local_sha remote_ref remote_sha; do
  [[ -z "$remote_ref" ]] && continue

  if [[ "$IS_PARENT" -eq 0 ]]; then
    case "$remote_ref" in
      refs/heads/main) blocked_main="$remote_ref" ;;
      refs/tags/*)     blocked_tags+="${remote_ref#refs/tags/} " ;;
    esac
  fi

  # Env guards: skip deletions (no local objects to inspect). Tip tree only —
  # a .env in earlier history is out of this guard's reach (FWADR-033
  # §"Honest ceiling").
  if [[ "$local_sha" != "$ZERO_SHA" ]]; then
    tracked_env="$(git ls-tree -r --name-only "$local_sha" 2>/dev/null \
                    | grep -E '(^|/)(\.env|\.sops-age-key\.txt)$' | head -5)"
    if [[ -n "$tracked_env" ]]; then
      env_hits+="  $remote_ref tracks: $(echo "$tracked_env" | tr '\n' ' ')"$'\n'
    fi
    # Only the framework's own file (root env.yaml with a top-level `vars:`).
    if git show "$local_sha:env.yaml" 2>/dev/null | grep -q '^vars:'; then
      found="$(git show "$local_sha:env.yaml" 2>/dev/null | env_yaml_findings | head -8)"
      [[ -n "$found" ]] && yaml_hits+="  $remote_ref env.yaml:"$'\n'"$(echo "$found" | sed 's/^/    /')"$'\n'
    fi
  fi
done

if [[ -n "$env_hits" ]]; then
  cat >&2 <<EOF
[push-guard] BLOCKED: a pushed ref tracks a .env file or the decryption key.
$env_hits
  A plaintext env file and .sops-age-key.txt never belong in git (FWADR-033);
  shared values go in env.yaml, encrypted (FWADR-041). Fix, then re-push:

    git rm --cached <path>        # un-track (keeps the working file)
    echo "<path>" >> .gitignore   # if not already ignored
    git commit

  The file remains in earlier history — if it ever held real secrets,
  rotate them. See docs/dev_framework/adrs/fwadr-033-env-scope-rule.md.
EOF
  exit 1
fi

if [[ -n "$yaml_hits" ]]; then
  cat >&2 <<EOF
[push-guard] BLOCKED: a pushed ref holds an env.yaml with a secret in the clear.
$yaml_hits
  Only ciphertext leaves this machine (FWADR-041). Re-enter the value with
  ./scripts/env_yaml.py set <NAME> (or edit with: sops env.yaml), amend the
  commit so no pushed commit carries the plaintext, then re-push. A secret
  already pushed in the clear must be rotated.
  See docs/dev_framework/adrs/fwadr-041-env-yaml.md.
EOF
  exit 1
fi

if [[ -n "$blocked_main" ]]; then
  cat >&2 <<'EOF'
[push-guard] BLOCKED: this push updates main in a code repo.

  Work lands on main by PR, merged on the git host — one PR per finished
  W-item (or batch), never a direct push. Push your feature branch and open
  the PR:

    git push -u origin <w-id/slug>

  See docs/dev_framework/adrs/fwadr-035-git-flow-mode.md §"Landing on main".
EOF
  exit 1
fi

if [[ -n "$blocked_tags" ]]; then
  cat >&2 <<EOF
[push-guard] BLOCKED: this push creates, moves or deletes a tag: $blocked_tags

  A release tag is never pushed. It is cut on the git host by the repo's
  release job when the stakeholder presses Approve in the QA view on dev
  (docs/dev_framework/dev-environment.md §"Release by approval"). If the QA
  view is down, the user creates the tag in the git host's own interface.
  There is no bypass. See docs/dev_framework/adrs/fwadr-023-main-push-guard.md.
EOF
  exit 1
fi

exit 0
