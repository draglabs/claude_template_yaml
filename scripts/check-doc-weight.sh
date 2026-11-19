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
# Budgets are per agent. Going over one is a WARNING TO THE USER, who decides:
# raise that agent's budget, or refine the content. The Template Developer puts
# the choice to the user and does neither on its own. A raised budget ships in
# the same commit as the growth it licenses, with a one-line why. After
# compacting a doc, re-tauten its budget to the new measured reality.
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
# Developer re-tautened 2026-11-19 after compacting developer.md (8,429 -> 4,181
# words, same rules) — measured 8,079 + ~8% headroom.
check_role "Developer"           8700  developer.md coding-standards.md
check_role "Strategist"          9500  strategist.md
# Orchestrator + Researcher caps +100 on 2026-10-12: Layer 0 grew by the
# user-mandated "Handing off a PR" rule (CLAUDE.md), which every role loads.
# Orchestrator +50 on 2026-11-08: FWADR-037's done rule (harness green, link
# posted) and tiered phase-exit step land in session-policy.md.
# Orchestrator + Researcher +50, Template Developer +100 on 2026-11-19: Layer 0
# gained the env.yaml rule (FWADR-041: who changes env values, who never edits
# the file), which every role must load; dev_framework.md gained its table row.
# Orchestrator re-tautened the same day: trunk only (FWADR-035) cut the two-mode
# text from session-policy.md — measured 8,734 + ~3% headroom.
check_role "Orchestrator"        9000  session-policy.md
check_role "Template Developer"  7100  template-developer.md dev_framework.md
check_role "Curator"             5500  curator.md
check_role "Designer"            4100  designer.md   # +100 on 2026-11-07: FWADR-040 adds a Paperclip-mode pointer to every Layer-1 load
check_role "Researcher"          3650  researcher.md
# The Paperclip Lead does not load CLAUDE.md (FWADR-043): its budget is its role doc alone.
PL="$(words "$FW/paperclip-lead.md")"
if (( PL > 1000 )); then
  printf '[check-doc-weight] OVER: %-18s %6d words (cap 1000) — paperclip-lead.md, without Layer 0\n' "Paperclip Lead" "$PL"; fail=1
else
  printf '[check-doc-weight] ok:   %-18s %6d / 1000 words\n' "Paperclip Lead" "$PL"
fi

if (( fail )); then
  echo "[check-doc-weight] WARNING FOR THE USER — an agent's bootstrap load is over its budget (FWADR-034)."
  echo "[check-doc-weight] Your decision, per agent above: raise its budget (the number in this script),"
  echo "[check-doc-weight] or have the content refined (compact the doc, or demote content to Layer 2)."
  exit 1
fi

echo "[check-doc-weight] OK — all per-role framework loads within caps (FWADR-034)."
exit 0
