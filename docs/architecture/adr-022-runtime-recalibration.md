# ADR-022 — Runtime recalibration: role-relative model tiers, continuation retries, consultant middle rung

**Status:** Accepted — 2026-07-19
**Owner:** Template Developer
**Supersedes in part:** [ADR-013](adr-013-peer-dispatch.md) (retry mechanism only; the peer-dispatch topology is unchanged)

## Context

The framework was written against a specific runtime snapshot (early 2026) and encoded three facts from it as if they were permanent:

1. **`SendMessage` is unavailable in the Claude Code CLI runtime** (verified 2026-04-23, recorded in ADR-013). Retries were therefore mandated as fresh Agent-tool dispatches — and the docs justified the design as a *platform constraint*, not a choice.
2. **A two-tier model ladder** — Sonnet as the cheap writer, Opus as the top-tier judge — was hardcoded as literal model names across role docs, subagent briefs, the tier table, and the merge-commit trailer template.
3. **An `advisor` tool** ("sees full conversation context") was named as the middle rung of the Developer's 80/20 confidence ladder.

The runtime moved: `SendMessage` now exists (a prior Executor can be continued with its context intact); the model ladder gained a tier above Opus (Fable/Mythos class), and subagents now inherit the parent session's model by default; no `advisor` tool exists in the harness.

Each stale fact is a distinct failure mode. (1) invites a future session to "discover" SendMessage, correctly conclude the doc is stale, and feel licensed to improvise. (2) can silently *invert the review gate* — a top-tier Developer session spawning a literal-Opus Reviewer puts a weaker judge over a stronger writer — and makes the mandated commit trailer record a falsehood when the spawned agent actually inherited a different model. For a framework whose doctrine is "a ledger that lies is worse than no ledger," that is self-inflicted. (3) stalls a Developer session hunting for a tool that isn't there.

## Decisions

### 1. Model tiers are role-relative; literal names resolve at spawn time

Framework docs and briefs no longer name literal models. Two named tiers:

- **Top tier** — the strongest generally available Claude model in the harness at the moment of spawn. Used for judgment work: Reviewer, Integrator-QA, and the persistent judgment-heavy sessions (Strategist, Developer, Template Developer, Orchestrator when retry judgment matters).
- **Work tier** — a cost-efficient tier below the top tier, sufficient for well-briefed, bounded work: Executor, QA, Doc/Code Consultants, Designer.

The Integrator-QA additionally requires the **long-context variant** available at the top tier — its batch context (N worktree diffs + standards + plan) is the load-bearing capability of batch mode.

**Invariant: a review gate runs at a tier ≥ the tier that wrote the code.** This is the property the old "Reviewer is always Opus" rule was actually protecting.

**Mechanism.** Subagents inherit the parent session's model by default in the current harness. At spawn time the Orchestrator (or Developer, for its Reviewer) resolves tiers to concrete models: set the work-tier model explicitly for Executors/QA/consultants; for the Reviewer, inherit when the session itself runs top tier, otherwise set the top-tier model explicitly. The merge-commit trailer records the **actual resolved model names**, never names copied from a template — the templates now carry `<model resolved at spawn>` placeholders.

### 2. Retries default to continuation via SendMessage; fresh dispatch is retained for approach-level blocks

The retry loop keeps its shape (Orchestrator-owned, counted against tier caps, new commits on top — no rebase/amend) but gains two mechanisms:

- **Continuation (default).** The Orchestrator sends the blocking concerns to the *same* Executor via `SendMessage`. Context intact, cheapest path. Appropriate when the block is about incomplete or incorrect *execution* of a sound approach.
- **Fresh dispatch.** A new Executor spawned from a rebuilt brief (branch name + verbatim concerns + no-scope-reopen instruction), exactly as under ADR-013. **Mandatory** when any of:
  1. The Reviewer classifies the block as **approach-level** — the approach is wrong, not the execution. A continued Executor tends to rationalize its own prior choices; fresh eyes don't.
  2. The same concern (or its direct descendant) survives a continuation retry — one continuation attempt per concern, then fresh eyes.
  3. The prior Executor is no longer reachable.

**Mechanism.** The Reviewer's `block` return now carries a **Block class** field — `execution` or `approach` — so the Orchestrator routes mechanically instead of interpreting prose. Either mechanism consumes one retry against the cap.

The old rule's *stated* rationale (platform constraint) is retired; the fresh-dispatch mechanism survives on its actual merits (independent judgment, deterministic briefs) in the cases where those merits bind.

### 3. The Developer's 80/20 middle rung is a consultant subagent

The phantom `advisor` tool is removed. The ladder becomes: self ≥80% → act; self <80% → **spawn a consultant subagent** (Doc/Code Consultant when the gap is a doc or code fact; a general research consultant otherwise); consultant round-trip still <80% → escalate to the user.

**Known loss, stated explicitly:** a spawned consultant does **not** see the conversation context — that was the advisor's whole distinction. The Developer must package the fork into the consultant brief: the decision, the options, the constraints, and the specific consideration blocking confidence. A consultant briefed with a bare question returns a bare answer; the packaging is what makes the rung work.

## Deferred (named gaps, not silent ones)

Two further observations from the same runtime assessment are **deliberately deferred** to the phase-boundary calibration review that `session-policy.md` §"Policy propagation" already prescribes — they are calibration questions, not stale facts, and reshaping the framework around them without measurement would violate the framework's own doctrine:

- **Context-scarcity posture.** The layer budgets, `/compact` choreography, and consultant-indirection math were calibrated against earlier models' retention. Current models + harness auto-summarization change the slope. Keep the layering, working logs, and hooks (model-version-proof); re-measure the mandatory `/compact` choreography and the Doc-Consultant round-trip economics against observed behavior.
- **Structured outputs and deterministic orchestration.** Subagent return shapes ("pass shape," verdict formats) are English-enforced schemas; the runtime can now enforce JSON schemas mechanically, and the Orchestrator's control flow (fan-out, barrier, verdict-driven merge, capped retries) matches the shape of a deterministic workflow script. Both are the framework's own mechanism-over-intention doctrine applied to itself — and both are renovations, not patches. Evaluate at a phase boundary with retry/escalation data in hand.

## Consequences

- Docs and briefs stop going stale on every model-generation change; the only spawn-time obligation is tier resolution.
- The commit-trailer ledger records truth (actual models) instead of template fiction.
- Retries get cheaper in the common case (execution-level fixes) while preserving fresh-eyes review where it matters.
- The Reviewer brief grows one field (Block class); the Orchestrator bootstrap's retry step routes on it.
- ADR-013's peer-dispatch topology (no nested subagent spawns; every subagent a peer under the Orchestrator) is **unchanged** and re-verified — only its retry-mechanism section is superseded.

## Alternatives considered

- **Literal-name refresh** (update Sonnet/Opus → current names): rejected — reintroduces the same staleness bug on the next model generation.
- **Single-source model-ladder table** (one file maps role → current model): considered; rejected in favor of role-relative language because the table itself goes stale and adds a doc every role must consult. Spawn-time resolution puts the freshness burden at the only moment freshness is checkable.
- **SendMessage continuation for *all* retries**: rejected — approach-level blocks are precisely where a continued Executor's self-consistency bias is most costly.
- **Keeping fresh-dispatch-only, re-justified on merits**: viable and simpler, but forgoes real cost savings on the most common retry class (small execution fixes); user decision 2026-07-19 chose continuation-by-default.
