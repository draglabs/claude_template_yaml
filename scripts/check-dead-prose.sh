#!/usr/bin/env bash
# check-dead-prose.sh — template-repo lint for dead prose in spec docs (FWADR-036).
#
# Spec prose states what is true now; history lives in git. This fails on the
# STRUCTURAL markers of appended history — never on words, so prose that
# discusses the anti-pattern (FWADR-036, curator.md) does not trip it:
#
#   A. Appended-history headings: "## Revision …", "## Addendum …", "## Amendment …"
#   B. Blockquote addenda:        "> **Addendum …", "> **Revision …"
#   C. Inline revision labels:    "Revision v1.1", "Revision (v1.1", "**Revision (v2"
#   D. ADR version tags:          "FWADR-019 v1.3", "ADR-004 v2"
#
# Scope: spec docs only — docs/dev_framework/ (incl. stub scripts' comments),
# docs/architecture/, docs/execution-plans/README.md, CLAUDE.md, .claude/hooks/. Log docs (process-exceptions,
# incidents) are append-only by design and not scanned. A deliberate exception
# carries "dead-prose: allow" on the same line.
#
# Run from the template repo root. Invoked by sync-framework.sh's template-self
# branch on every SessionStart; safe to run by hand any time. Template-only —
# never synced to adopters.

set -u
cd "$(dirname "$0")/.." || exit 1

PATHS=(docs/dev_framework docs/architecture docs/execution-plans/README.md CLAUDE.md .claude/hooks)
EXCLUDE='docs/dev_framework/_stubs/framework_exceptions/(process-exceptions|execution-incidents)\.md'

fail=0
scan() {  # $1 label, $2 ERE
  local hits
  hits="$(grep -rEn --include='*.md' --include='*.sh' --include='*.yaml' --include='*.example' \
            "$2" "${PATHS[@]}" 2>/dev/null \
          | grep -Ev "^($EXCLUDE):" | grep -v 'dead-prose: allow')"
  if [[ -n "$hits" ]]; then
    echo "[check-dead-prose] FAIL $1:"
    echo "$hits" | sed 's/^/  /'
    fail=1
  fi
}

scan "A (appended-history heading)" '^#{1,6}[[:space:]]+(Revision|Addendum|Amendment)\b'
scan "B (blockquote addendum)"      '^>[[:space:]]*\*\*(Revision|Addendum|Amendment)\b'
scan "C (inline revision label)"    'Revision[[:space:]]+\(?v[0-9]'
scan "D (ADR version tag)"          '(^|[^A-Za-z])(FW)?ADR-[0-9]{3}[[:space:]]+v[0-9]'

if (( fail )); then
  echo "[check-dead-prose] FAILED — rewrite in place; history belongs in git (FWADR-036)."
  exit 1
fi
echo "[check-dead-prose] OK — no appended-history markers in spec docs."
exit 0
