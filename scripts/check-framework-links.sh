#!/usr/bin/env bash
# check-framework-links.sh — template-repo lint for the framework ADR namespace.
#
# Enforces FWADR-028 (docs/dev_framework/adrs/fwadr-028-framework-adr-namespace.md):
# framework docs must never point back into the adopter-owned product ADR space,
# and must cite framework ADRs unambiguously. Three checks:
#
#   A. No file in docs/dev_framework/ (or CLAUDE.md) references a framework-
#      numbered ADR (012+) under architecture/ — those live in
#      docs/dev_framework/adrs/. References to the adopter product space
#      (adr-000..adr-011, generic adr-*.md globs, architecture/README.md) are fine.
#   B. No bare ADR-0NN citation in the framework number range (012+) inside
#      docs/dev_framework/ or CLAUDE.md — those must be FWADR-0NN.
#   C. Every fwadr-*.md filename cited anywhere in docs/ or CLAUDE.md exists
#      in docs/dev_framework/adrs/.
#
# Run from the template repo root. Invoked by sync-framework.sh's template-self
# branch on every SessionStart; safe to run by hand any time.

set -u
cd "$(dirname "$0")/.." || exit 1

fail=0

# --- A: no links into the product ADR directory from the synced tree ---------
hits="$(grep -rEn 'architecture/(fw)?adr-0(1[2-9]|[2-9][0-9])' docs/dev_framework/ CLAUDE.md 2>/dev/null)"
if [[ -n "$hits" ]]; then
  echo "[check-framework-links] FAIL A: synced files link into docs/architecture/ ADR space:"
  echo "$hits"
  fail=1
fi

# --- B: bare ADR-0NN citations in the framework range must be FWADR ----------
hits="$(grep -rEn '(^|[^W])ADR-0(1[2-9]|[2-9][0-9])' docs/dev_framework/ CLAUDE.md 2>/dev/null)"
if [[ -n "$hits" ]]; then
  echo "[check-framework-links] FAIL B: bare ADR-0NN citations in the framework range (must be FWADR-0NN):"
  echo "$hits"
  fail=1
fi

# --- C: every cited fwadr filename resolves to a real file -------------------
while IFS= read -r name; do
  [[ -z "$name" ]] && continue
  if [[ ! -f "docs/dev_framework/adrs/$name" ]]; then
    echo "[check-framework-links] FAIL C: cited but missing: docs/dev_framework/adrs/$name"
    fail=1
  fi
done < <(grep -rEoh 'fwadr-[0-9]{3}-[a-z0-9-]+\.md' docs/ CLAUDE.md 2>/dev/null | sort -u)

if [[ "$fail" -eq 0 ]]; then
  echo "[check-framework-links] OK — framework ADR namespace clean."
fi
exit "$fail"
