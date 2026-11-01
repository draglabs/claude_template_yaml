# FWADR-039: Mockups set direction; the builder holds the override

**Status:** accepted
**Date:** 2026-11-01
**Deciders:** user (framework author) + Template Developer

## Context

A Developer building ad-slot cards stopped and asked the user to choose
between three layouts because the Designer's mockup had not anticipated an
empty ad box that leaves a blank gap above nineteen of twenty cards on a real
site. The question was well formed (options, confidence, difficulty) and
still wrong to ask: it put the user in the loop to arbitrate between a
mockup and a constraint the mockup never saw.

That is **design lock**: development stalls because the design has not
caught up with reality. Designers explore on fixtures; production meets ad
networks, slow APIs, odd viewports, legal copy, and data that does not match
the fixture. No Designer can pre-empt all of it, so a process that treats the
mockup as binding guarantees either stalled work or a stream of questions the
user should never have to answer.

[`designer.md`](../designer.md) already said "mockups set direction;
production code adapts to real constraints." It was not stated where the
builders read, and it had no reminder surviving a context reset, so it did
not hold.

## Decision

1. **The builder has standing executive override over mockups.** Whoever
   builds the production surface — the Developer, an Executor under the
   Orchestrator — may deviate from `mockups/` whenever a real-world
   constraint makes the mockup wrong or incomplete. No permission needed, not
   from the user, not from the Designer. This holds over time: the override
   is not a one-off exception but the normal relationship between concept and
   production.
2. **Mockup deviations are not a user decision fork.** The 80/20 ladder in
   [`developer.md`](../developer.md) governs *how* to deviate, never *whether*
   the builder may. Asking the user "mockup or constraint?" is the false-low
   failure mode of that ladder. Ask the user only when the choice is one the
   user personally fixed — a locked decision in CLAUDE.md or a user-approved
   entry in `mockups/docs/README.md` — and even then the builder proposes a
   default rather than an open question.
3. **Deviations are recorded, not approved.** A deviation goes in the
   W-item's Execution notes or Implementation log in one or two lines: what
   the mockup showed, what shipped, why. The Reviewer treats a deviation from
   `mockups/` as not a finding; an *unrecorded* one is a LOW.
4. **The Designer catches up, not the builder.** The Designer's Live concept
   mirrors production at every Designer session start
   ([`designer.md`](../designer.md) §"Live concept"), so shipped deviations
   flow back into the mockups without any builder action. The Designer may
   then propose a better answer to the constraint as a new concept.
5. **Reminder rides every reset.** `session-reorient.sh` re-injects the rule
   alongside the other conversational conventions, since a judgment rule has
   no checkable artifact.

## Consequences

- The Developer's Designer relationship row, the Executor brief's locked
  decisions section, the Reviewer brief, the Designer doc, CLAUDE.md's
  Designer row, and the reorient hook all state the override. Same change,
  all surfaces.
- Designers lose nothing they had: the user still signs off visually before a
  concept is marked Approved, and the Live concept keeps them honest about
  what production actually did.
- The failure mode this trades for: a builder deviating lazily and calling it
  a constraint. The recorded-deviation line is the audit point; the user
  reads it in the Implementation log and can send it back.
