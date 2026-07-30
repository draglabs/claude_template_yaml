#!/usr/bin/env bash
# check-curator-scope.sh — mechanical write-fence for the Curator role
# (ADR-026). The Curator audits the project's accumulated doc corpus but may
# NOT edit canonical framework files: they are destructively re-synced from the
# template on the next SessionStart, so an edit buys one session and then
# silently reverts. Framework findings become fwreq-*.md requests instead.
#
# Mechanism: compare the local framework surfaces against the canonical
# template rather than against git. This is deliberate — under ADR-021's
# DEFAULT untracked-parent layout, $PROJECT_DIR is not a git repo at all, so a
# git-diff-based fence would be silently inert in the most common
# configuration. Diffing the template works in every layout mode, and is also
# semantically exact: "framework file" means "byte-identical to the template",
# so any deviation IS the violation.
#
# Usage (run from $PROJECT_DIR, per ADR-021 script placement doctrine):
#   ./scripts/check-curator-scope.sh
#
# Exit codes:
#   0 — local framework surfaces match the template.
#   1 — local edits found; paths on stdout, one per line.
#       Revert them and file docs/framework_exceptions/fwreq-NNN-<slug>.md
#       instead — never keep a local edit to a synced framework file.
#   2 — template root could not be resolved (cannot check).
#
# Generic script — no project-specific body to fill in.

set -euo pipefail

PROJECT_DIR="$PWD"

# Template resolution mirrors .claude/hooks/sync-framework.sh, in the same
# order. Shell environment variables are intentionally NOT consulted: a stale
# export pointing at a defunct location would silently misroute the check.
env_template() {
  grep -E '^CLAUDE_TEMPLATE_ROOT=' "$1" 2>/dev/null | head -1 | cut -d= -f2- \
    | sed 's/^["'"'"']//; s/["'"'"']$//'
}

TEMPLATE_ROOT=""
[[ -f "$PROJECT_DIR/.env" ]] && TEMPLATE_ROOT="$(env_template "$PROJECT_DIR/.env")"

# (b) immediate subdir .env files (split-layout adopters whose .env is in the repo)
if [[ -z "$TEMPLATE_ROOT" ]]; then
  for subdir in "$PROJECT_DIR"/*/; do
    [[ -d "$subdir/.git" && -f "$subdir/.env" ]] || continue
    TEMPLATE_ROOT="$(env_template "$subdir/.env")"
    [[ -n "$TEMPLATE_ROOT" ]] && break
  done
fi

# (c) conventional sibling / ancestor locations
if [[ -z "$TEMPLATE_ROOT" ]]; then
  for cand in ../claude_template_yaml ../../claude_template_yaml ../../../claude_template_yaml; do
    [[ -d "$cand/docs/dev_framework" ]] && { TEMPLATE_ROOT="$cand"; break; }
  done
fi

if [[ -z "$TEMPLATE_ROOT" || ! -d "$TEMPLATE_ROOT/docs/dev_framework" ]]; then
  echo "check-curator-scope: could not resolve the canonical template root." >&2
  echo "Set CLAUDE_TEMPLATE_ROOT= in $PROJECT_DIR/.env (same value" >&2
  echo "sync-framework.sh uses). Cannot verify the framework fence without it." >&2
  exit 2
fi
TEMPLATE_ROOT="$(cd "$TEMPLATE_ROOT" && pwd -P)"

# If this IS the template repo, the fence is meaningless — the Curator does not
# operate here (framework maintenance is the Template Developer's role).
if [[ "$TEMPLATE_ROOT" == "$PROJECT_DIR" ]]; then
  echo "check-curator-scope: this IS the canonical template repo — the Curator" >&2
  echo "role does not operate here (see docs/dev_framework/curator.md)." >&2
  exit 0
fi

# Surfaces that sync-framework.sh overwrites destructively (rsync --delete).
violations=""
for rel in docs/dev_framework .claude/hooks; do
  [[ -d "$PROJECT_DIR/$rel" && -d "$TEMPLATE_ROOT/$rel" ]] || continue
  # _stubs/ is seeded once and then owned locally — not a synced surface.
  while IFS= read -r line; do
    [[ -n "$line" ]] && violations+="$rel/$line"$'\n'
  done < <(diff -rq --exclude=_stubs "$TEMPLATE_ROOT/$rel" "$PROJECT_DIR/$rel" 2>/dev/null \
             | sed -n 's/^Files .* and .*\/\([^/]*\) differ$/\1/p; s/^Only in '"$(printf '%s' "$PROJECT_DIR/$rel" | sed 's|[/.*]|\\&|g')"': \(.*\)$/\1 (local-only)/p')
done

if [[ -n "$violations" ]]; then
  echo "check-curator-scope: local edits to canonical framework files —" >&2
  echo "these are destructively re-synced on the next SessionStart and will be lost:" >&2
  printf '%s' "$violations"
  echo >&2
  echo "File docs/framework_exceptions/fwreq-NNN-<slug>.md instead; the user" >&2
  echo "carries it to the Template Developer in the canonical template repo." >&2
  echo "See docs/dev_framework/curator.md \"Framework-update requests\"." >&2
  exit 1
fi

echo "check-curator-scope: OK — framework surfaces match the template."
exit 0
