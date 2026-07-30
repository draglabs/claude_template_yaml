# ADR-025: Named deliverables — the Strategist writes what was asked for

**Status:** accepted
**Date:** 2026-07-29
**Owner:** Template Developer

## Context

An adopter project's user (2026-07-29) reviewed a synthetic-content generation
approach with their Strategist, then asked it to write a runbook and save it
next to an existing runbook covering verification. The artifact type, the
location, and a precedent sibling document were all supplied — there was no
ambiguity about what was wanted or where it went.

The Strategist did not write the runbook. While drafting it, it needed
parameters the runbook would have to state, looked for the ADRs that would
define them, found none, and treated the missing ADRs as blocking
prerequisites. It then went and edited adjacent incomplete work items,
inventing content for them — including a constraint stating that an agent is
not permitted to run the content-generation cycle. The runbook was the
procedure for an agent to orient and run exactly that cycle. The requested
deliverable was never produced.

Four framework properties combined to produce this, none of them a model
defect:

1. **No escalation path for out-of-surface requests.** `strategist.md` §"What
   it does not do" enumerates the write surface exhaustively across seven
   "Does not…" bullets. The Developer has an 80/20 confidence ladder
   ([`developer.md`](../dev_framework/developer.md) §"Confidence-driven
   escalation") whose job is turning sub-threshold confidence into a *visible
   question*. The Strategist had no equivalent — its only "bug the user" rule
   was the MCP health check. With no escalation path, an unmapped request
   resolved as the nearest permitted write instead of a question.

2. **The failure is high-confidence, so no uncertainty check catches it.** The
   Developer's ladder fires on "an honest 'I'm not sure which way' feeling."
   Silent substitution does not feel uncertain. Porting the ladder verbatim
   would have shipped a rule that cannot fire in this failure mode.

3. **"Gap found" has exactly one trained disposition: create a work item.**
   §"Triages `process-exceptions.md`" and §"Triages server-work requests" both
   dispose of gaps by folding them into a plan as W-items. There was no path
   from "gap found" → "ask the user for the value." Manufacturing the
   prerequisite was the only well-worn road available.

4. **"Docs before code" over-applied.** CLAUDE.md §"Two process rules" gates
   *implementing* an architectural addition. The Strategist read it as
   requiring that every value appearing in a document first exist in an ADR,
   converting a one-document request into upstream architectural work.

Aggravating factor: `.claude/hooks/session-reorient.sh` re-anchored resumed and
compacted sessions on role doc, locked-in decisions, exceptions, and the status
ledger — every anchor a doctrine surface, none pointing back at the user's
actual request. After a compact, doctrine reloads at full strength while a
one-sentence instruction does not.

**A second, related failure reported in the same conversation.** Developers
routinely hand the Strategist a small bounded job — "intake this ticket and
update the planning docs." The Strategist inflates it: alignment audits,
cross-reference sweeps, stub audits, ledger reconciliation, none of them asked
for, until the context window is exhausted and the small deliverable never
lands. The cause is structural. `strategist.md` is written as a **standing job
description for a persistent session** — audit everything, cross-reference
everything, triage everything, verify every claim. Read as a *task list* at the
moment of a small request, that job description is the task. Nothing in the
role bounded a response to the size of its request.

## Decision

Add a **named-deliverable discipline** to the Strategist, with an objective
trigger rather than a self-rated one, and make operational docs a first-class
Strategist artifact class.

1. **Objective trigger.** The question is "did the request name an artifact, a
   document type, or a location?" — checkable — not "am I ≥80% confident?" —
   which was ~90% in the failure case. A named artifact **is** the deliverable;
   producing an adjacent one instead is a substitution requiring the user's
   agreement *before* it happens.

2. **Two user-visible firing moments.** Before the first write, state the
   comparison: *"You asked for X at P; writing X at P."* At completion, state
   what was produced against what was named. Both are output the user reads and
   can interrupt.

3. **Missing definitions are questions, not prerequisites.** When authoring a
   requested document needs a value nothing defines, ask the user for the
   value. Do not create an ADR, W-item, plan amendment, or `req-*` to define it
   first. Pausing a deliverable to do upstream work requires explicit user
   agreement, because it converts one document into a phase.

4. **"Docs before code" scoped.** It gates implementation, not authorship. An
   operational doc may record a user-stated parameter inline; capturing a value
   is not locking a decision.

5. **Operational docs are in surface (folded-in scope).** Runbooks, SOPs, and
   operator checklists are a first-class Strategist artifact class, distinct
   from planning docs. Location is project-chosen — the framework prescribes no
   `docs/runbooks/` convention, and a user-named path is authoritative. A
   runbook describing an agent operating a capability is a description of an
   existing procedure, not a proposal to expand scope.

6. **Hook re-anchor.** `session-reorient.sh` emits a named-deliverable block on
   **every** source, alongside the existing filesystem-scope block, phrased so
   the empty case escalates: if the artifact and its path cannot be named from
   current context, ask.

7. **Adopt the 80/20 ladder, calibrated — and add a proportionality rule.**
   Context bullet 1 records that the Strategist had *no* escalation path;
   decisions 1–6 address confident substitution but leave honest uncertainty
   unhandled. The Strategist therefore adopts the same ladder the Developer
   runs, by reference rather than duplication, with one calibration: **when the
   user is in the loop and the task is bounded, skip rung 2 (consultant) and
   ask them directly** — a consultant round-trip returns context into the
   session window and costs more than the question is worth when the person who
   knows the answer is present. Rung 2 stands when the user is unavailable or
   the gap is a corpus fact rather than a user decision.

   Separately, and addressing a different failure: **a bounded task gets a
   bounded response.** `strategist.md` is written as a standing job description
   for a persistent session (audit, cross-reference, triage, sweep). Read as a
   task list at the moment of a small request — "intake this ticket, update
   planning docs" — it inflates a five-minute job into a corpus-wide review that
   exhausts the context window and never delivers the small thing asked for.
   Audits are phase-boundary work with their own stated cadence, not free
   additions to every task that touches a doc. Mid-task scope inflation is a
   signal to stop and ask, not to absorb.

   The ladder and the proportionality rule are **two fixes for two different
   halves** of the observed complaint ("it asked me nothing, and it did far too
   much"). The ladder governs decision forks; it does not bound task size.

8. **Ship a bounded Strategist brief for the spawn path.** The Developer's
   sanctioned spawns were Reviewer, Doc Consultant, Code Consultant, and
   one-shot investigation — all read-only except the Reviewer. There was no
   sanctioned, bounded, *write-capable* doc-work subagent, so "intake this
   ticket and update the planning docs" had no legitimate path and got
   improvised as a Strategist invocation. The framework shipped briefs for
   Executor, Reviewer, QA, Integrator-QA, both Consultants, and Orchestrator
   bootstrap — but **none for the Strategist**, because it was designed as a
   persistent session rather than a spawnable subagent. A Strategist reached by
   spawn therefore loaded a 300+ line standing job description with no task
   boundary, and did the job description instead of the task.

   The user confirmed (2026-07-29) that adopters reach it by **Agent-tool
   spawn**, so a brief template is the load-bearing surface.
   [`templates/strategist-brief.md`](../dev_framework/templates/strategist-brief.md)
   ships with three properties the role doc cannot provide:

   - **It forbids reading `strategist.md`.** The standing job description is
     the inflation mechanism; excluding it is the fix, not an optimization.
   - **Write surface is enumerated per spawn.** The brief names the exact files
     the subagent may write; anything else returns a question.
   - **`question` is a success status.** The subagent may return *nothing
     written plus a specific question*, and that is a correct outcome.
     Manufacturing prerequisites happens precisely when an agent believes it
     must return completed work; the return format removes that pressure. The
     spawning session surfaces the question to the user and re-spawns with the
     answer filled in.

   Wired into `dev_framework.md` §"Subagent briefs", `developer.md` §"What it
   does", and `context-management.md` Layer 2 in the same change.

## Consequences

**Buys:** a failure mode that previously consumed a phase now costs one
question. The check is objective, so it survives the high-confidence case that
defeats uncertainty-based escalation. The hook block re-anchors every role, not
just the Strategist, on every context reset — the surface where doctrine mass
otherwise wins against a one-sentence instruction.

**Costs:** two extra user-visible statements per deliverable. Mild redundancy
when the deliverable is obvious; that redundancy is the mechanism, and it is
cheap relative to what it prevents.

**Makes harder:** autonomous multi-step Strategist work that legitimately needs
upstream definitions now stops to ask rather than proceeding. This is
intentional — the user is present, and the cost asymmetry is roughly one
exchange against one phase.

**Mechanism honesty.** No script enforces this. The forcing function is that
both statements are user-visible output, the same shape the framework already
sanctions where an agent cannot verify something generically
([`developer.md`](../dev_framework/developer.md) §"Lifecycle (per W-item)" —
"Ready to start coding W-X?"; [`dev-environment.md`](../dev_framework/dev-environment.md)
§"Pointing prod at a non-main branch (escape hatch)"). Under
[Template Developer doctrine](../dev_framework/template-developer.md)
§"Framework-change doctrine" this is an explicitly-named English-only rule with
a hook-level re-anchor, not hope.

**Closed gap — no write-capable doc subagent.** Addressed by Decision 8 above;
`strategist-brief.md` is the sanctioned path that previously did not exist.

**Known gap — Layer 1 budget.** `context-management.md` sets a hard "< 200
lines per role" Layer 1 budget. `strategist.md` was already 277 lines before
this change and is now ~310; `developer.md` is 448; `session-policy.md` is 473.
Doctrine mass outweighing the live instruction is a *contributing cause* of the
failure this ADR addresses, so this change makes the underlying condition
marginally worse while fixing the proximate mechanism. Nothing checks the
budget today. Mechanizing it (`scripts/check-doc-budget.sh` + a trim pass
across `strategist.md` and `developer.md`) is queued as separate work and is
deliberately not bundled here.

## Alternatives considered

- **Port the Developer's 80/20 ladder as the *primary* mechanism.** Rejected in
  that role: it triggers on felt uncertainty, and this failure is confident.
  The ladder is nonetheless adopted as a *secondary* mechanism under
  Decision 7 — Context bullet 1 records that the Strategist had no escalation
  path at all, and shipping this ADR without one would have left the gap the
  Context section names. It is referenced rather than duplicated, to avoid
  adding ~15 lines to an over-budget doc.

- **Put the rule in CLAUDE.md's managed block (Layer 0).** The rule is genuinely
  universal — Designer, Researcher, and Orchestrator can substitute the same
  way. Deferred, not rejected: that block syncs destructively into every
  adopter's CLAUDE.md, and the hook re-anchors on CLAUDE.md §"Locked-in
  decisions" specifically rather than the whole file, so a new section there
  would not survive a compact without a matching hook edit. The hook block in
  this ADR already reaches every role at lower blast radius.

- **Add a `docs/runbooks/` convention.** Rejected. Adopter projects already
  have operational docs in project-chosen locations; a framework-imposed path
  would fight the user's own layout, and this failure had a location supplied.

- **Ship a validation script.** No mechanical check can compare "what the user
  asked for" against "what was written" without the request in machine-readable
  form. Named as an English-only rule rather than papered over with a check
  that would not work.
