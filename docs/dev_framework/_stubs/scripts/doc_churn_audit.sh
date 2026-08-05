#!/usr/bin/env bash
# doc_churn_audit.sh — mechanical evidence for the Curator role (FWADR-026).
#
# Computes the signals that identify docs worth pruning, re-scoping, or
# archiving. It RANKS; it does NOT recommend. Whether a high-churn ADR is
# mis-scoped or simply load-bearing and well-maintained is a judgment call the
# Curator makes with the user — never present a number here as a verdict.
#
# Usage (run from $PROJECT_DIR, per FWADR-021 script placement doctrine):
#   ./scripts/doc_churn_audit.sh
#
# Exit codes:
#   0 — audit ran (findings on stdout; findings are not an error)
#   2 — not run from a directory containing docs/, or git unavailable
#
# Generic script — no project-specific body to fill in.

set -euo pipefail

if [[ ! -d docs ]]; then
  echo "doc_churn_audit: no docs/ in $PWD — run from \$PROJECT_DIR" >&2
  exit 2
fi

# Plan/ADR history may live in the parent repo, the code repo, or neither
# (untracked-parent mode, FWADR-021). Degrade gracefully rather than failing.
GIT_OK=1
git rev-parse --git-dir >/dev/null 2>&1 || GIT_OK=0
[[ $GIT_OK -eq 0 ]] && echo "NOTE: $PWD is not a git repo — churn column unavailable (untracked-parent mode)." >&2

churn() {  # commits touching a path; 0 when history is unavailable
  [[ $GIT_OK -eq 1 ]] || { echo 0; return; }
  git log --oneline --follow -- "$1" 2>/dev/null | wc -l | tr -d ' '
}

hr() { printf '%s\n' "------------------------------------------------------------"; }

# ---------------------------------------------------------------- ADR signals
echo
echo "=== ADR signals ==="
if compgen -G "docs/architecture/adr-*.md" >/dev/null; then
  rows=""
  for f in docs/architecture/adr-*.md; do
    base="$(basename "$f" .md)"
    c="$(churn "$f")"
    # Headings only, and both spellings in the wild: "Revision (v3.1)" / "Revision v2".
    rev="$(grep -cE '^#{2,4} Revision \(?v[0-9]' "$f" 2>/dev/null || true)"
    # inbound references: any doc/script citing this ADR slug, excluding itself
    refs="$(grep -rl "$base" --include='*.md' --include='*.sh' . 2>/dev/null | grep -vx "./$f" || true)"
    inb="$(printf '%s' "$refs" | grep -c . || true)"
    # REACH — which context layer pays for this doc. A citation from CLAUDE.md
    # (Layer 0) or a Layer 1 role doc is read by EVERY session, which outranks
    # raw reference count when ranking findings.
    reach="-"
    if printf '%s\n' "$refs" | grep -qE '(^|/)CLAUDE\.md$'; then
      reach="L0"
    elif printf '%s\n' "$refs" | grep -qE 'docs/dev_framework/(strategist|designer|developer|researcher|curator|template-developer|session-policy|context-management)\.md$'; then
      reach="L1"
    fi
    lines="$(wc -l < "$f" | tr -d ' ')"
    # Only when the Status VALUE leads with it. "accepted; superseded in part by
    # FWADR-022" is still in force — matching mid-line produces false positives that
    # get trusted past their evidence.
    dep=""
    grep -qiE '^\*\*Status:\*\*[[:space:]]*(superseded|deprecated)' "$f" && dep="ALREADY-DEPRECATED"
    rows+="$(printf '%4s %4s %5s %5s %6s  %-42s %s' "$c" "$rev" "$inb" "$reach" "$lines" "$base" "$dep")"$'\n'
  done

  # Median churn — the comparison point that makes a churn number meaningful.
  med="$(printf '%s' "$rows" | awk '{print $1}' | sort -n \
         | awk '{a[NR]=$1} END{if(NR)print (NR%2)?a[(NR+1)/2]:int((a[NR/2]+a[NR/2+1])/2); else print 0}')"

  printf '%4s %4s %5s %5s %6s  %-42s %s\n' CHURN REVS INREF REACH LINES ADR NOTE
  hr
  printf '%s' "$rows" | sort -rn
  hr
  echo "median churn: ${med}"
  echo
  echo "Reading the columns:"
  echo "  CHURN  commits touching the file. Well above median = the project may be"
  echo "         fighting this decision. A STARTING signal — it says which doc to"
  echo "         read, not what is wrong with it. NOT a verdict."
  echo "  REVS   self-declared 'Revision (vN)' sections. Do not stop at the count —"
  echo "         see the fight-detection section below."
  echo "  INREF  files citing this ADR. Near zero = possibly dead."
  echo "  REACH  highest context layer citing it. L0 = cited from CLAUDE.md, L1 ="
  echo "         cited from a Layer 1 role doc. Both are read by EVERY session, so"
  echo "         they outrank raw CHURN when deciding which finding is worst."
  echo "  LINES  size. Long ADRs that keep growing are usually two decisions."
  [[ -n "$med" && "$med" != "0" ]] && \
    echo && echo "Above 2x median churn (${med}) — look at these first:" && \
    printf '%s' "$rows" | awk -v m="$med" 'm>0 && $1 > 2*m {print "  " $0}'
  # REACH is a ranking WEIGHT, not a filter — in a mature corpus most ADRs are
  # cited from Layer 0/1, so listing them all is noise. Shortlist = docs with an
  # actual churn/revision signal, ordered so Layer 0/1 ones come first.
  echo
  shortlist="$(printf '%s' "$rows" | awk -v m="$med" '($1+0) > (m+0) || ($2+0) >= 2 {print}')"
  if [[ -n "$shortlist" ]]; then
    echo "Worst-first shortlist (has a churn/revision signal; Layer 0/1 reach ranked up):"
    { printf '%s\n' "$shortlist" | awk '$4=="L0"' | sort -rn
      printf '%s\n' "$shortlist" | awk '$4=="L1"' | sort -rn
      printf '%s\n' "$shortlist" | awk '$4!="L0" && $4!="L1"' | sort -rn; } | grep . | sed 's/^/  /'
    echo
    echo "  Take the TOP ONE. Read its revisions newest-first (below), state the"
    echo "  user's last position on that topic, then propose ONE disposition."
  else
    echo "No doc carries a churn or revision signal — nothing obvious to prune."
  fi

  # -------------------------------------------------------- fight detection
  # A churned doc argues its OLD position at the top and records the user
  # overruling it at the bottom. Agents read top-down and get the stale position
  # first. Emit revisions NEWEST-FIRST so the latest ruling is read first.
  # File order is NOT version order (FWADR-018 has v3.3 above v3.2), so sort by
  # parsed version rather than position.
  echo
  echo "=== Fight detection — revisions newest-first ==="
  echo "Read the DECIDER and the DIRECTION, not the count. A run of user-decided"
  echo "revisions that consistently RELAX something (drop a cap, soften a MUST,"
  echo "remove a gate) is the user overruling the doc while it re-accretes —"
  echo "that is a fight, not maintenance."
  any=0
  for f in docs/architecture/adr-*.md; do
    n="$(grep -cE '^#{2,4} Revision \(?v[0-9]' "$f" 2>/dev/null || true)"
    [[ "${n:-0}" -ge 2 ]] || continue
    any=1
    hr
    echo "$(basename "$f" .md)  — ${n} revisions, newest first:"
    grep -nE '^#{2,4} Revision \(?v[0-9]' "$f" \
      | sed -E 's/^([0-9]+):#+ Revision \(?v?([0-9]+(\.[0-9]+)?)\)?/\2|\1|v\2/' \
      | sort -t'|' -k1,1 -rV \
      | while IFS='|' read -r _ver line rest; do
          # decider convention: a "**Decided by:** X" line within 4 lines of the heading
          who="$(sed -n "${line},$((line+4))p" "$f" \
                 | sed -nE 's/.*\*\*Decided by:\*\*[[:space:]]*([^.]*).*/\1/p' | head -1)"
          [[ -z "$who" ]] && who="(no decider recorded)"
          # The revision TITLE carries the direction ("rewind retired",
          # "no force-push") — that is the signal, so give it room.
          title="$(printf '%s' "$rest" | sed -E 's/^v[0-9.]+[,)]?[[:space:]]*//; s/^[0-9-]*\)?[:—[:space:]]*//' | cut -c1-56)"
          printf '    L%-5s %-56s %s\n' "$line" "$title" "$who"
        done
  done
  [[ $any -eq 0 ]] && echo "  (no ADR carries 2+ revision sections)"
else
  echo "(no docs/architecture/adr-*.md found)"
fi

# ------------------------------------------------------- Layer budget signals
echo
echo "=== Doc size vs budget ==="
echo "Layer 0 CLAUDE.md < 100 lines; Layer 1 role docs < 200 (context-management.md)."
hr
[[ -f CLAUDE.md ]] && awk 'END{printf "  %5d  CLAUDE.md%s\n", NR, (NR>100?"   OVER (Layer 0 budget 100)":"")}' CLAUDE.md
for f in docs/dev_framework/*.md; do
  [[ -e "$f" ]] || continue
  case "$(basename "$f")" in
    strategist.md|designer.md|developer.md|researcher.md|curator.md|template-developer.md|session-policy.md)
      awk -v n="$(basename "$f")" 'END{printf "  %5d  %s%s\n", NR, n, (NR>200?"   OVER (Layer 1 budget 200)":"")}' "$f" ;;
  esac
done

# ------------------------------------------------------------ archive signals
echo
echo "=== Archive candidates ==="
hr
found=0
for p in docs/execution-plans/*/plan.md; do
  [[ -e "$p" ]] || continue
  total="$(grep -cE '^\|+.*\bW-' "$p" 2>/dev/null || true)"
  open="$(grep -ciE 'pending|in_progress|code_review|blocked|held' "$p" 2>/dev/null || true)"
  if [[ "${total:-0}" -gt 0 && "${open:-0}" -eq 0 ]]; then
    echo "  ALL-CLOSED  $(dirname "$p")  — no open W-items; archive candidate"
    found=1
  fi
done
[[ $found -eq 0 ]] && echo "  (no fully-closed plan folders found)"

# ---------------------------------------------------------- exception signals
echo
echo "=== Active exceptions (check Retire-when) ==="
hr
EXC=docs/framework_exceptions/dev_framework_exceptions.md
if [[ -f "$EXC" ]]; then
  awk '/^## Active/{a=1;next} /^## Retired/{a=0} a && /^### EX-/{print "  " $0}' "$EXC" \
    | grep . || echo "  (none active)"
  echo
  echo "  Each Active entry states a 'Retire when' criterion. Verify whether it has"
  echo "  fired — an exception outliving its criterion is drift wearing a badge."
else
  echo "  (no dev_framework_exceptions.md)"
fi

echo
echo "Signals only. Dispositions are the Curator's judgment, confirmed per item"
echo "by the user before anything is archived, rewritten, or deleted."
