# ADR-013: Peer dispatch (supersedes the A2 nested-spawn model)

**Status:** accepted; superseded in part by [ADR-022](adr-022-runtime-recalibration.md) (2026-07-19) — the retry mechanism only. The peer-dispatch topology (no nested subagent spawns; Executor/Reviewer/QA as peers under the Orchestrator) remains in force and was re-verified against the current runtime.
**Date:** 2026-04-23
**Deciders:** David (template author), Strategist session

> **Addendum 2026-07-19 (ADR-022).** The SendMessage-unavailability premise below (Context, final paragraph; Alternatives §2) no longer holds — the current Claude Code runtime provides SendMessage for continuing a prior agent. Retries now default to continuation of the same Executor, with fresh dispatch retained for approach-level blocks. See ADR-022 and `session-policy.md` §"Orchestrator-owned retry mechanics". The rest of this ADR — including the nested-spawn prohibition, which was re-confirmed — stands unchanged. Model names in this ADR (Sonnet/Opus) reflect the ladder at decision time; current docs use role-relative tiers per ADR-022.

## Context

The prior execution model (internally called "A2") had the Orchestrator spawn an Executor subagent, and the Executor spawn its own Reviewer and QA as sub-sub-agents. The intent was context economy: the Orchestrator would see only short pass/stumped packages, and the full write → review → QA loop would live inside the Executor's context window.

Two failure modes surfaced in real use (documented in `execution-incidents.md` of an adopting project):

1. **EI-001:** An Executor (Sonnet, `general-purpose`) returned text formatted as a Reviewer's verdict, without actually spawning a Reviewer subagent. The Orchestrator had no way to detect self-review vs. real review.
2. **EI-002:** A different Executor refused to attempt the nested Agent-tool call at all and instead proposed scheduling a remote cron job as the review mechanism, stalling for Orchestrator input.

Research uncovered the root cause: **nested subagent spawning is explicitly unsupported by the Claude Agent SDK.** From the official docs (https://code.claude.com/docs/en/agent-sdk/subagents): *"Subagents cannot spawn their own subagents. Don't include `Agent` in a subagent's `tools` array."* Cross-confirmed by open GitHub issues #4182, #19077, #31977, #32731, #43198.

Cross-framework convention is uniform: LangGraph (Supervisor), CrewAI, AutoGen (for pipeline review, not private reflection), OpenAI Agents SDK, and Google ADK all dispatch worker and reviewer as peers from a central orchestrator. "Generator self-critiquing" is a named anti-pattern in the multi-agent literature.

Additionally, `SendMessage` (the mechanism for continuing a prior agent) is **not available in the Claude Code CLI runtime** — confirmed 2026-04-23 via `ToolSearch`. Any retry strategy that assumes SendMessage is unavailable; retries must use fresh Agent-tool invocations with sharpened context.

## Decision

**The Orchestrator dispatches Executor, Reviewer, and QA as peers.** The Executor writes and commits; the Orchestrator separately spawns the Reviewer (Opus) and, when required, the QA (Sonnet). The Orchestrator owns the retry loop; on a Reviewer `block` or QA `fail`, it dispatches a fresh Executor with the prior branch + the concerns verbatim as sharpened context.

### Flow

```
Orchestrator
  → Executor (worktree, writes + commits, returns code-only package)
  → Reviewer (Opus, passed worktree path + commit SHA)
     block? → re-dispatch Executor with concerns; re-run Reviewer
  → QA (Sonnet, only after Reviewer ships, only if tier/markers require)
     fail? → re-dispatch Executor with QA findings; re-run from Reviewer
  → merge to dev, push, auto-advance
```

**Sequential, not parallel:** Reviewer runs first, QA only after `ship`. Parallel execution would waste QA cycles on code that's about to change.

**Retry budget:** Orchestrator-owned counter. Default caps (2 for XS/S/M, 3 for L/XL/⚠️) unchanged from the prior model. Each block+re-dispatch consumes one retry. On exhaustion, escalate to the user with the unresolved concern and what was tried.

**Naming:** the acronym "A2" is retired. The framework describes the flow directly ("dispatch model" or "peer dispatch") rather than maintaining a code name for an architecture we no longer use. Retaining the name would be a drift attractor — a name that reads as accurate but describes something structurally different.

## Consequences

**Mechanical wins:**

- **Provenance by construction.** The Orchestrator itself called the Reviewer via the Agent tool; the result is in the Orchestrator's own message history, with `agentId` returned automatically. Fabrication — the EI-001 failure mode — is impossible. No `Reviewer subagent id:` field or verification ritual is needed.
- **Works with the Claude Code CLI as shipped.** No reliance on nested Agent-tool calls, no reliance on SendMessage.
- **Aligned with Anthropic's documented constraint** and with every major multi-agent framework's convention.

**Softened claims the framework used to make:**

- **"Orchestrator doesn't read code."** Softens to: *Orchestrator reads Reviewer and QA verdicts, which may cite `file:line`. Orchestrator does not open diffs or source files directly.* Code reading still happens only inside Executor and Reviewer contexts.
- **"Orchestrator context grows linearly, small per-item."** Verdicts are larger than the old 6-line pass packages (Reviewer returns per-question answers; QA returns per-criterion results). Growth is still linear and bounded — the structured shapes are the cap — but the per-item cost is higher than under A2. See `context-management.md` for updated budget.

**Rejected as obsoleted by the structural fix:**

- The tactical mitigations proposed for EI-001 — a `Reviewer subagent id:` field in the Executor's PASS shape, a "final bytes" rule for the shape, an explicit "do not paste Reviewer report inline" prohibition — were considered. They are all made unnecessary by peer dispatch: the Orchestrator has direct provenance, so no return-shape lie is possible. Shipping tactical mitigations for a pattern we're removing would be a drift attractor of its own.

## Alternatives considered

1. **Keep nested spawning; try harder.** Add concrete JSON Agent-tool invocation examples to the Executor brief, require a specific `subagent_type`, hope for reliability. Rejected because Anthropic's SDK docs state nested spawning is unsupported regardless of how the brief is written. We would be hardening a mechanism against its own constraint.
2. **SendMessage-based retries on the same Executor.** Rejected because SendMessage is unavailable in the Claude Code CLI runtime (verified 2026-04-23).
3. **Parallel Reviewer + QA.** Rejected as premature optimization; sequential is simpler and avoids wasted QA cycles.
4. **Keep the A2 name, redefine internally.** Rejected; a misleading name violates the policy-mechanism coherence doctrine just as English-only rules do.

## Carry-over and retired content

- The `A2` acronym is removed from all framework docs (`session-policy.md`, all brief templates, `dev_framework.md`, `context-management.md`, `coding-standards.md`, `dev-environment.md`, `execution-plans/README.md`).
- The Executor brief's STEP 4 (self-gate Reviewer + QA loop) collapses into a return-after-commit shape.
- The Reviewer and QA briefs update their "spawned by" headers to name the Orchestrator.
- The Orchestrator bootstrap gains explicit STEPs for Reviewer dispatch and QA dispatch, with the retry loop documented.
- Emergency bypass retrospective Reviewer (session-policy §"When to suspend this policy") was already an Orchestrator-direct spawn pattern — it now matches the standard model instead of being an exception.
