# Architecture

System design docs. Owned by the Strategist. Referenced by the Orchestrator when briefing Executors on constrained surfaces.

## What goes here

- **ADRs (Architecture Decision Records).** The *rationale* behind locked decisions — why this database, why this auth model, why this boundary. Short one-line summaries of the decisions themselves stay inline in `CLAUDE.md` for every-session visibility; the long-form reasoning lives here.
- **System diagrams.** Components, data flows, deployment topology. Mermaid in markdown preferred — renders in GitHub and stays diffable.
- **Data model.** Schema docs, table relationships, invariants. Not the migration files (those live with the code) — the *conceptual* model.
- **API surface.** Externally-visible contracts: route table, auth model, rate limits, SLA claims.
- **Integration maps.** Third-party services, MCP servers in use (see `../dev_framework/approved-mcps.md`), external data sources.
- **Non-negotiables.** Security boundaries, compliance constraints, scaling assumptions.

## What does NOT go here

- **Work plans.** Phase plans and W-items live in `docs/execution-plans/`.
- **Process / SOP.** How agents operate lives in `docs/dev_framework/`.
- **Code-level conventions.** TDD, hardcoded-value rules, fail-loudly — `docs/dev_framework/coding-standards.md`.
- **Issues / bugs / feature requests.** Those belong in `issues/` or a tracker.
- **Planning / roadmap.** Strategic planning docs (roadmap, future-directions) are a separate surface — see the Strategist's reading list.

## Naming convention

- ADRs: `adr-NNN-<slug>.md` (numbered, padded to 3 digits). Example: `adr-001-postgres-over-mysql.md`.
- Diagrams / models / maps: free-form descriptive name. Example: `system-overview.md`, `data-model.md`, `api-surface.md`.

## ADR template

```markdown
# ADR-NNN: <decision name>

**Status:** proposed | accepted | superseded by ADR-MMM | deprecated
**Date:** YYYY-MM-DD
**Deciders:** <who>

## Context
<what forced the decision — constraint, incident, growing pain>

## Decision
<what we chose, in one or two sentences>

## Consequences
<what this buys us, what it costs us, what it makes harder>

## Alternatives considered
<what we didn't pick and why, briefly>
```

Lock the decision by adding a one-line summary under `## Locked-in decisions` in `CLAUDE.md` with a link back to the ADR.

### Revision sections — record the decider

When a revision *is* the right disposition (see §"Staleness rule" — usually it is not), head it and name who decided:

```markdown
## Revision (vN.N, YYYY-MM-DD) — <what changed, stated as the direction>

**Decided by:** user | Strategist | Template Developer
```

**`Decided by:` is load-bearing, not bookkeeping.** `scripts/doc_churn_audit.sh` extracts revisions newest-first with their decider, because a run of **user**-decided revisions that consistently *relax* something — drop a cap, soften a MUST, remove a gate — means the document is more restrictive than the user wants and keeps drifting back. That is a fight, and it is only legible if the decider is recorded. Without it the audit prints `(no decider recorded)` and the strongest available signal is lost. Title the revision by its **direction** ("rewind retired", "no force-push of feature"), not by its topic — the extractor surfaces that title as the direction cue.

## Who reads this

- **Strategist:** reads the full tree. ADRs + diagrams are primary material for architectural judgment.
- **Orchestrator:** reads targeted docs when briefing an Executor on a constrained surface (e.g. auth, billing, data migration). Does NOT load the whole tree.
- **Executor:** reads only the ADR(s) named in their brief, if any. Most W-items don't need architecture context.
- **Reviewer:** reads an ADR when the Executor claims the work follows it, to verify alignment. Cites ADR numbers in concerns.

## Living architecture, not doctrine

**An ADR is the best current record of a decision. It is not a constraint that outranks a live instruction from the user.** See [ADR-027](adr-027-living-architecture.md).

When a user instruction conflicts with an accepted ADR, the ADR is what changes — rewritten to state the decision that now holds, or escalated to the user when their intent isn't clear. What must never happen is the silent inverse: code built to the user's order, blocked at a review gate for "canonical misalignment," and quietly re-coded back to the stale ADR. Review gates are fresh subagents that cannot see the conversation, so they need the deviation recorded on the W-item (`## User-directed deviation` — [`../execution-plans/README.md`](../execution-plans/README.md)) to tell an ordered departure from a careless one.

This does not weaken §"Docs before code": an *undocumented* architectural addition is still a `block`. The distinction is between code that has no decision behind it, and code that has a *newer* decision behind it than the file does.

## Staleness rule

Architecture docs that no longer match the code are worse than missing docs — they produce confident wrong answers. The Strategist's phase-boundary alignment audit checks every ADR and diagram against current code state (via GitNexus queries or Code Consultant spawns). Stale docs get either updated or marked `superseded` / `deprecated` — never silently wrong.

**Marking `superseded` is not the whole move — the file leaves this directory.** A superseded ADR goes to `docs/archive/` in the same commit as its successor (steps in [`../archive/README.md`](../archive/README.md) §"Superseded ADRs"). An ADR marked superseded but left here is still grepped, loaded, and read past by every future session; the directory would otherwise only ever grow.

**Prefer fixing over superseding.** Supersession is for decisions that genuinely *changed*. When the decision still stands and only its wording was over-broad, or its binding force too strong, the right move is to **rewrite or detune the ADR in place** — a doc amended many times is usually one that was never articulated right, and superseding it just yields a successor that gets amended too. Stacking `Revision` sections onto an ADR is the most common and least useful option: it preserves history at the cost of a document nobody can read top-to-bottom and know what is true. Full disposition set in [`../dev_framework/curator.md`](../dev_framework/curator.md) §"Dispositions".
