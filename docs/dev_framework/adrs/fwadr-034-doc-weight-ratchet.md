# FWADR-034: Doc weight budget v2 — word-denominated per-role load, template-side ratchet

**Status:** accepted
**Date:** 2026-08-27
**Deciders:** user (framework author) + Template Developer

## Context

`context-management.md` set the doc weight budget as line counts: Layer 0
under 100 lines, Layer 1 under 200 lines per role, combined ~400. It failed
three independent ways:

1. **Wrong unit.** Context cost tracks words (≈1.3–1.4 tokens/word for this
   prose); line count tracks how prose happens to be wrapped. The divergence
   was large enough to invert rankings among the very docs the budget
   governs: `strategist.md` was 30% smaller than `session-policy.md` by
   lines (332 vs 473) while costing 31% *more* in words (7,890 vs 6,143).
2. **Unreachable.** No heavy role doc ever met 200 lines; the corpus drifted
   to ~3× the target unchallenged. A target nobody hits constrains nothing.
3. **Unowned.** Detection existed (`doc_churn_audit.sh` prints size-vs-budget
   correctly) but only the Curator runs it, and the Curator is mechanically
   fenced out of `docs/dev_framework/*` (FWADR-026) — the single role that
   saw a framework doc over budget could not fix it.

The user's clarified intent resolves the design: the limiter was always
meant to **stop the Template Developer from bloating the agents** — an
authoring-time ratchet on the framework — never to stop an agent from
reading its full operating contract.

## Decision

1. **Unit: words.** The budget's question is "how many words does agent X
   load as context at bootstrap?" No framework budget is line-denominated.
2. **Metric: per-role framework load** — the sum of template-owned words a
   role reads at session start: the template CLAUDE.md plus that role's
   Layer 1 framework docs. Project-side artifacts (plan index, exceptions
   file, planning docs) vary per project and stay under project-side
   ownership and rules.
3. **Per-role caps, set taut.** Caps start at measured reality (2026-08-27)
   plus ~10% headroom — reachable by construction, so every violation is
   news. A uniform ceiling was rejected: it would initially constrain only
   the heaviest role while light roles could triple silently, which is
   exactly the drift that took the old budget to 3×.
4. **Single source of numbers.** The caps live in ONE place —
   `scripts/check-doc-weight.sh` in the template repo — never duplicated
   into prose. `context-management.md` states the model and points at the
   script.
5. **Enforcement where the fixer sits.** The script runs on every template
   SessionStart via `sync-framework.sh`'s template-self branch (same pattern
   as the FWADR-028 link check), so the Template Developer — the only role
   that can edit framework docs — sees any violation at the start of every
   session in this repo. It is a template-repo lint; it does not sync to
   adopters.
6. **The ratchet doctrine.** Raising a cap is legal but deliberate: the bump
   ships in the same commit as the doc growth it licenses, diff-visible,
   with a one-line justification in the commit message. Lowering caps after
   a compaction is encouraged — re-tauten to the new measured reality.

## Explicitly out of scope / accepted gaps

- **`doc_churn_audit.sh` is untouched** (user decision). Its core — churn,
  revision markers, inbound references, archive candidates, exception age —
  is the Curator's contested-decision detector and was never the gap. Its
  trailing "Doc size vs budget" section still prints the legacy line-count
  signals; the Curator routes any framework-doc finding as `fwreq-*` exactly
  as before (FWADR-026). Accepted incoherence, named here: that section's
  caption cites line budgets this ADR retires. If it misleads in practice,
  fixing the stub is a one-line follow-up.
- **Project-side structural limits stay line-denominated.** The plan-index
  (<150 lines) and W-item SOW (≤200 lines, FWADR-017/018) caps bound the
  *structure* of template-shaped artifacts rather than measure framework
  load; converting them would mean rewriting accepted product-side ADRs for
  no observed failure.
- **The exceptions file** (`dev_framework_exceptions.md`) is adopter-owned
  after seeding; its growth is governed by its own "under 30 lines of active
  content" rule, project-side. It is not counted in the template-side load.

## Consequences

- Coherence surfaces, all in this change: this ADR; `scripts/check-doc-weight.sh`
  (new, with the caps); `sync-framework.sh` template-self branch invocation;
  `context-management.md` §"Doc weight budget" rewritten (line targets
  deleted, including the dead Layer 0 "<100 lines" target); `curator.md`
  size-signal row re-captioned to name the template-side check.
- Framework doc growth now has a named owner, a truthful unit, and a
  session-start mechanical check in the one repo where fixes are legal —
  rule and mechanism ship together per framework doctrine.
- Measured loads at adoption (words): Developer 12,403; Strategist 10,093;
  Orchestrator 8,346; Template Developer 6,299; Curator 4,786; Designer
  3,581; Researcher 3,208. Caps: see the script — it is the canonical list.
