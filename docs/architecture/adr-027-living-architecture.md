# ADR-027: Living architecture — the review gate must not reverse the user

**Status:** accepted
**Date:** 2026-07-31
**Owner:** Template Developer

## Context

The user reported (2026-07-31) a loop that silently reverses their own orders:

1. The user gives an instruction that conflicts with an accepted ADR.
2. The Developer builds it.
3. The Reviewer detects the divergence and returns `block`.
4. The Developer "resolves" the block by re-coding to match the ADR.

The user's instruction is gone, and **nothing announces that it was
overridden**. Their framing: *"the reviewer may be actually the executor of
many conflicts."* That is precisely right — the Reviewer does not decide
anything, but it is the component through which a stale document overrules a
live human.

Three framework properties combine to produce it, none of them a model defect:

1. **The review gate is structurally blind to the conversation.** The Reviewer
   is a fresh subagent reading the diff, the W-item file, and
   `coding-standards.md`. It has no access to the session where the instruction
   was given. A user-ordered deviation and a careless one are *the same
   observation* from inside that brief. It cannot distinguish them, so it
   correctly applies the only rule it has.

2. **The brief told it to suppress its own judgment.** `reviewer-brief.md`
   question 2 read: *"does the code match the plan + architecture docs? Call
   out any divergence, **even if it looks reasonable**."* That trailing clause
   removes the one escape hatch a thoughtful reviewer might have used. The same
   instruction sits in `integrator-qa-brief.md`, so the batch path
   ([ADR-016](adr-016-batch-mode-integrator-qa.md)) had the identical defect.

3. **No verdict path meant "the document is what's wrong."** The Developer's
   outcomes were Ship / Resolve / Postpone. `Resolve` — "concerns the user
   wants fixed" — is the natural landing for a canonical-alignment block, and
   it routes to re-coding. `Postpone` mischaracterizes it as a known limitation
   in the *code*, when the limitation is in the *doc*. There was no path that
   updated the ADR.

Root doctrine: CLAUDE.md §"Two process rules" rule 1 — *"Docs before code…
Enforced at the merge boundary by the Reviewer (`block` if no matching doc)"* —
is what appoints the Reviewer as enforcer. Written for *undocumented
additions*, it was silently doing duty for *contradicted existing decisions*
too.

This is the same failure class as [ADR-025](adr-025-named-deliverables.md)
(stale doctrine outranking a live instruction) and
[ADR-026](adr-026-curator-role.md) Revision v1.2 (a churned doc arguing its old
position over the user's latest ruling) — but at the merge gate, where it is
worst, because the gate's verdict is treated as binding and the reversal is
never surfaced.

## Decision

**An ADR is the best current record of a decision, not a constraint that
outranks the user. When the two conflict, the ADR changes.**

1. **Record the deviation on the W-item — the load-bearing mechanism.** A
   `## User-directed deviation` section (naming the ADR, quoting the
   instruction, dated) is added **when the instruction is given**, not after a
   gate blocks. Format in
   [`../execution-plans/README.md`](../execution-plans/README.md)
   §"User-directed deviations". Nothing else in this ADR works without it: the
   review gate is blind by construction, so this section is the *only* channel
   through which intent reaches it. It records that a conflict is intentional;
   it does not settle it.

2. **New finding class: `doc-conflict`, orthogonal to the verdict.** Both
   `reviewer-brief.md` and `integrator-qa-brief.md` now check for the section
   before classifying a divergence. Present and matching → `doc-conflict`, not
   `block`; otherwise-clean code is `ship` + `doc-conflict`. Absent → normal
   `block`. Present but narrower than the actual deviation → `block`, naming
   the excess. Integrator-QA additionally must not write a fix commit reverting
   the code, nor file an integration claim against it.

3. **Fourth Developer outcome: `Reconcile`.** Ship / Resolve / **Reconcile** /
   Postpone. `Reconcile` never re-codes; it updates the ADR and merges.

4. **The Developer holds targeted ADR-rewrite authority.** On a `doc-conflict`:
   **rewrite the ADR** when the user's intent is clear — an explicit
   instruction this session, or their **last position** on the topic per
   [ADR-026](adr-026-curator-role.md) §"Reading a churned document" settles it.
   **Ask the user** when intent must be reconstructed rather than transcribed.
   The threshold is the existing 80/20 ladder, not a new test. The asymmetry is
   what makes this safe: **asking costs one exchange; silently reverting the
   user's order costs a build, and they may never find out.** When uncertain,
   ask — never default toward the old ADR merely because it is written down.

5. **Rewrite, never append.** A `Revision` section stacked on a contradicted
   ADR leaves the superseded decision arguing its case at the top of the file,
   where every future agent reads it first. Rewrite the body to state the
   decision that now holds; git keeps the history. Established in
   [ADR-026](adr-026-curator-role.md) Revision v1.2 §Dispositions and
   [`README.md`](README.md) §"Staleness rule" — cited here, not restated.

6. **Rule 1 qualified at the root.** CLAUDE.md and `dev_framework.md` §"Two
   process rules" now scope docs-before-code to *additions*, and state that a
   conflict between a live instruction and an existing ADR resolves
   doc-follows-instruction. An undocumented addition is still a `block`; the
   distinction is between code with no decision behind it and code with a
   *newer* decision behind it than the file has.

**Boundaries on the authority.** It covers ADRs the instruction actually
contradicts, not neighbouring ones the Developer disagrees with. It *records* a
decision the user made and never makes one — if the Developer finds itself
deciding architecture rather than transcribing a ruling, that is path 2. ADR
rewrites commit with the W-item so code and decision land together, and the
Implementation log names which ADR was rewritten under which instruction.

## Consequences

**Buys:** the user's instruction stops being silently reversible by a
subagent that cannot see them. The ADR corpus tracks reality instead of
drifting into a body of rules the project works around — the "living
architecture, not doctrine" property the user asked for.

**Costs:** one more W-item section to write, and it must be written at
instruction time. If the Developer forgets, the gate behaves exactly as before
and blocks — a safe failure, but the recovery is a round trip.

**Makes harder:** genuinely accidental ADR divergences are now one W-item
section away from being waved through. The `doc-conflict` path is only as
honest as the deviation record; a Developer that writes the section to dodge a
block has defeated it. Mitigation is that the section is user-visible, quotes a
specific instruction, and lands in the merge commit.

**Mechanism honesty.** The deviation record is a doc convention, not a check —
no script can verify that a quoted instruction was really given. What *is*
mechanical is the routing: both briefs now branch on the section's presence, so
the gate cannot reach `block` on a recorded deviation by accident. Named as an
English-only rule under
[Template Developer doctrine](../dev_framework/template-developer.md)
§"Framework-change doctrine".

**Open question deliberately not decided.** `README.md` §"What goes here" names
**Non-negotiables** — security boundaries, compliance constraints, scaling
assumptions. A marker forcing those to always take the ask-path rather than
auto-rewrite would be a cheap safety valve. It is *not* shipped here, because
inventing a category of ADR that outranks the user is the exact doctrine
attractor this ADR removes, and that call is the user's to make rather than the
framework's to assume. Raised for a decision, not deferred silently.

## Alternatives considered

- **Give the Reviewer access to the conversation.** Would fix the blindness at
  its source, but destroys the fresh-eyes property that makes the review gate
  worth having — a Reviewer that has read the session inherits its rationales
  and stops being independent. Rejected.

- **Let the Developer override a `block` on judgment alone.** Simpler, and no
  W-item section required. Rejected: it makes every canonical-alignment
  finding negotiable by the party being reviewed, and removes the audit trail
  that makes the override reviewable afterwards.

- **Route ADR conflicts to the Strategist.** Correct on paper — the Strategist
  owns architecture. Rejected as the primary path because it is slow at exactly
  the wrong moment: the user is present, the instruction is fresh, and a
  handoff to another session to transcribe a ruling the user already gave is
  ceremony. The Strategist still owns *reversing* decisions; the Developer only
  records them.

- **Append a `Revision` section instead of rewriting.** Rejected — see
  Decision 5.
