#!/usr/bin/env bash
# check-doc-weight.sh — template-repo lint for per-role framework load (FWADR-034).
#
# Answers, for every role: "how many template-owned words does this agent load
# as context at bootstrap?" — the template CLAUDE.md (Layer 0) plus the role's
# Layer 1 framework docs — and compares it against a per-role cap.
#
# This is an AUTHORING RATCHET on the Template Developer, not a restriction on
# agents (they always read their full operating contract). Caps below are the
# CANONICAL numbers (context-management.md deliberately does not duplicate
# them). They were set from measured reality + ~10% headroom on 2026-08-27.
#
# Raising a cap is legal but deliberate: bump it in the same commit as the doc
# growth it licenses, with a one-line justification in the commit message.
# After compacting a doc, re-tauten its cap to the new measured reality.
#
# Run from the template repo root. Invoked by sync-framework.sh's template-self
# branch on every SessionStart; safe to run by hand any time. Template-only —
# never synced to adopters.

set -u
cd "$(dirname "$0")/.." || exit 1

FW=docs/dev_framework
fail=0

words() { wc -w < "$1" | tr -d ' '; }

L0=0
if [[ -f CLAUDE.md ]]; then
  L0="$(words CLAUDE.md)"
else
  echo "[check-doc-weight] WARN: CLAUDE.md missing; Layer 0 counted as 0"
fi

check_role() {
  local role="$1" cap="$2"; shift 2
  local total="$L0" f
  for f in "$@"; do
    if [[ -f "$FW/$f" ]]; then
      total=$((total + $(words "$FW/$f")))
    else
      echo "[check-doc-weight] WARN: $FW/$f missing (counted as 0 for $role)"
    fi
  done
  if (( total > cap )); then
    printf '[check-doc-weight] OVER: %-18s %6d words (cap %d) — Layer 1: %s\n' \
      "$role" "$total" "$cap" "$*"
    fail=1
  else
    printf '[check-doc-weight] ok:   %-18s %6d / %d words\n' "$role" "$total" "$cap"
  fi
}

# Role                          cap    Layer 1 framework docs
# Developer + Strategist caps re-tautened 2026-08-27 after the FWADR-034
# compaction review (F1-F3, F5) — measured 11,595 / 8,814 + ~8% headroom.
check_role "Developer"          12500  developer.md coding-standards.md
check_role "Strategist"          9500  strategist.md
# Orchestrator + Researcher caps +100 on 2026-10-12: Layer 0 grew by the
# user-mandated "Handing off a PR" rule (CLAUDE.md), which every role loads.
check_role "Orchestrator"        9100  session-policy.md
check_role "Template Developer"  7000  template-developer.md dev_framework.md
check_role "Curator"             5500  curator.md
check_role "Designer"            4000  designer.md
check_role "Researcher"          3600  researcher.md

if (( fail )); then
  echo "[check-doc-weight] FAILED — a role's bootstrap load exceeds its cap (FWADR-034)."
  echo "[check-doc-weight] Compact the doc, demote content to Layer 2, or — deliberately —"
  echo "[check-doc-weight] raise the cap in this script in the same commit, with a one-line why."
  exit 1
fi

echo "[check-doc-weight] OK — all per-role framework loads within caps (FWADR-034)."
exit 0
