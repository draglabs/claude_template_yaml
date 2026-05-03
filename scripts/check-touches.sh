#!/usr/bin/env bash
# check-touches.sh — mechanical scope check for the Reviewer subagent.
#
# Reads the `touches:` list from a W-item file's YAML frontmatter, runs
# `git diff --name-only <base-ref>` from the current working directory,
# and emits any modified file that is not in the touches list.
#
# Usage:
#   check-touches.sh <w-item-file> <base-ref>
#
# Example (Reviewer running in the Executor's worktree):
#   cd /tmp/worktrees/myproj/w-a1-auth
#   /path/to/scripts/check-touches.sh \
#     docs/execution-plans/exec-phase-1/w-a1.md \
#     origin/dev
#
# Exit codes:
#   0 — every modified file is within `touches`.
#   1 — at least one modified file is out of scope. Out-of-scope file paths
#       are written to stdout, one per line.
#   2 — usage error, missing file, or no YAML frontmatter / no `touches`
#       field. The Reviewer falls back to manual judgment in this case.
#
# Canonical doctrine: docs/architecture/adr-020-yaml-frontmatter-w-items.md

set -euo pipefail

if [[ $# -ne 2 ]]; then
  echo "usage: check-touches.sh <w-item-file> <base-ref>" >&2
  exit 2
fi

WITEM_FILE="$1"
BASE_REF="$2"

if [[ ! -f "$WITEM_FILE" ]]; then
  echo "check-touches: W-item file not found: $WITEM_FILE" >&2
  exit 2
fi

# Extract the `touches:` list from YAML frontmatter using ruby
# (already used elsewhere in framework stubs — no extra dependency).
TOUCHES_LIST="$(ruby -e '
  require "yaml"
  content = File.read(ARGV[0])
  m = content.match(/\A---\n(.+?)\n---\n/m)
  unless m
    warn "check-touches: no YAML frontmatter in #{ARGV[0]}"
    exit 2
  end
  data = YAML.safe_load(m[1])
  unless data.is_a?(Hash)
    warn "check-touches: frontmatter is not a YAML mapping in #{ARGV[0]}"
    exit 2
  end
  touches = data["touches"]
  unless touches.is_a?(Array) && !touches.empty?
    warn "check-touches: missing or empty touches list in #{ARGV[0]}"
    exit 2
  end
  puts touches.join("\n")
' "$WITEM_FILE")" || exit 2

# Get the list of files changed vs the base ref.
CHANGED="$(git diff --name-only "$BASE_REF" 2>/dev/null || true)"

if [[ -z "$CHANGED" ]]; then
  # No changes — trivially in-scope.
  exit 0
fi

# Find changed files that are NOT in the touches list.
OUT_OF_SCOPE=""
while IFS= read -r changed_file; do
  [[ -z "$changed_file" ]] && continue
  in_scope=0
  while IFS= read -r touch_file; do
    [[ -z "$touch_file" ]] && continue
    if [[ "$changed_file" == "$touch_file" ]]; then
      in_scope=1
      break
    fi
  done <<< "$TOUCHES_LIST"
  if [[ "$in_scope" -eq 0 ]]; then
    OUT_OF_SCOPE+="$changed_file"$'\n'
  fi
done <<< "$CHANGED"

if [[ -n "$OUT_OF_SCOPE" ]]; then
  printf "%s" "$OUT_OF_SCOPE"
  exit 1
fi

exit 0
