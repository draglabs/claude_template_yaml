# FWADR-016: Batch-mode peer dispatch with Integrator-QA

**Status:** accepted
**Date:** 2026-04-24
**Deciders:** David (template author), Template Developer session

## Context

Per-task peer dispatch (FWADR-013) runs three subagents per W-item — Executor (Sonnet), Reviewer (Opus, always), and, for L/XL/🧪/⚠️ items, QA (Sonnet) — plus any retries. Practical cost observed in an adopting project: a 4-hour session burned through Claude Pro 20× weekly usage. The dominant cost pattern was **parallelism gap** — long sequences of small independent W-items running back-to-back, each paying a full per-task Opus Reviewer call even though the items had no dependencies on each other.

The existing `session-policy.md` §"Mandatory overrides" permits parallel execution of dependency-independent W-items "up to ~3 concurrent, each with its own peer chain (Executor, Reviewer, optional QA)." This preserves correctness but does nothing for Opus spend — 3 parallel W-items still means 3 Opus Reviewer calls. The framework had no mechanism for amortizing Opus review across independent work.

Secondary cost pattern: retries. Reviewer `block` → fresh Executor → fresh Reviewer stacks fast. For items whose first-pass Executor consistently missed the Reviewer's bar, effective cost climbed to 4–6 calls per W-item.

## Decision

Add **batch mode** to peer dispatch, alongside the existing per-task mode. Batch mode is opt-in per W-item via a plan-time `Parallel-safe` field set by the Strategist. When a parallel-safe batch is dispatched:

- **Executors** run concurrently as under FWADR-013 (one worktree each, Sonnet).
- **Per-task Reviewer and per-task (pre-merge) QA are replaced by a single Integrator-QA** call (Opus, 1M context) at the end of the batch. The Integrator-QA pulls all branches, handles integration (including merge-conflict resolution), runs a first-pass scan for high-profile issues, then full code-quality review, full test suite (Playwright if enabled), and fixes issues within acceptance.
- **Sequential (parallel-safe: false) W-items keep the current per-task Reviewer + optional QA chain** from FWADR-013. Batch mode is an added mode, not a replacement. FWADR-013 is extended, not superseded.

### Integrator-QA behavior

1. **First pass — high-profile issue scan.** Architectural violation, locked-decision collision, security-sensitive surface, scope visibly outside acceptance criteria. If a red flag hits and Integrator confidence in fix is <80% → raise to the user immediately as a **feature integration failure**. Do not proceed to deep work. This is an early-bailout gate to avoid sinking Opus compute into a batch the user needs to re-scope anyway.
2. **Deep pass:** pull all branches, resolve merges (including conflict resolution), run full code-quality review (absorbs Reviewer question set from `reviewer-brief.md`), run full test suite.
3. **Fix authority within acceptance.** Integrator may write commits to address issues it finds — bugs, missed tests, standards violations — **within the W-item's existing acceptance criteria**. Integrator-fix commits follow the same discipline as Executor commits: TDD (test-first), no hardcoded lifecycle values, no silent fallbacks, loud failures. Batch mode is not a quiet bypass of `coding-standards.md`. If the fix cannot be performed within acceptance, Integrator does not change scope — see claim path.
4. **Scope-change path (claim):** if a fix would require stepping outside acceptance (change a locked decision, alter acceptance criteria, reshape the W-item), Integrator does NOT make the change. Instead:
   - **≥80% confident in the proposed change** → file an **integration claim** inline on the active execution plan; the Strategist triages with the user asynchronously. Named W-items are held from merging pending resolution; other W-items (in this batch or others) proceed.
   - **<80% confident** → surface to the user immediately as a feature integration failure.
5. **All green:** merge to dev, push, auto-advance.

### Executor brief changes

Executors in batch mode own first-pass quality more aggressively — the Reviewer gate they used to cross is absorbed into the Integrator-QA. Executor must:

- Write tests first (TDD unchanged).
- **Run its own unit / integration tests** inside the worktree before returning. Report results in the PASS shape.
- **Run a final code-quality self-check** against `coding-standards.md`: TDD, no hardcoded lifecycle values, no silent fallbacks, grep-for-canonical-value-drift. Report results in the PASS shape.
- **Do NOT start a live dev server inside the worktree.** Three concurrent Executors each spinning a dev server on default ports would collide. Live/Playwright testing belongs to Integrator-QA, which runs after all Executors in the batch return. Port discipline is mechanical, not aspirational.

### Integration claim

- **Artifact location:** under FWADR-017's folder structure, claims live in `claims.md` inside the plan folder (`docs/execution-plans/<plan>/claims.md`). Under the pre-FWADR-017 single-file layout, claims live inline on the active plan file under a `## Integration claims` section. Both layouts use the same shape and triage protocol; only the file location differs. The Orchestrator's STEP 0 PRELUDE format detection (orchestrator-bootstrap.md) resolves the path; the Integrator brief's `CLAIMS_PATH` field carries it.
- **Shape:**
  ```markdown
  ### IC-NNN — YYYY-MM-DD — {{W-id(s)}} — {{short title}}

  **Filed by:** Integrator-QA, batch <ids>
  **Confidence:** <pct>
  **Proposed scope change:** <what Integrator wants to do but won't do unilaterally>
  **Why:** <what forced the proposal — test failing for X, acceptance ambiguous on Y>
  **Blocks:** <W-item ids whose merge is held pending resolution>
  ```
- **Status linkage (FWADR-017):** under the folder layout, filing a claim atomically flips named W-items to `held` on the index (one commit, both files). Disposition (`approve`/`modify`/`reject`) atomically moves the claim to Resolved AND flips Status (`held → in_progress` for approve/modify; `held → blocked` for reject). The pre-FWADR-017 layout keeps named items at `in_progress` with a Notes line; the new `held` state replaces that convention so the Status field stops misleading.
- **Blocking semantics:** an open claim blocks **only the named W-items** from merging. Other W-items in the batch that aren't named proceed normally. Other batches, sequential work, and the Orchestrator's forward progress are not blocked.
- **Triage:** the Strategist reviews open claims on a cadence similar to `process-exceptions.md` — at phase boundaries and on demand. Resolution loops in the user. No autonomous resolution by the Strategist — claims exist because the Integrator refused to make a scope decision without authorization.

### Parallel-safe is Strategist judgment, not Touches-disjointness

Two items with disjoint `Touches` lists can still conflict on: `package.json`, lockfiles, shared config, schema, route registries, migration ordering, refactor-of-a-callee, test fixtures. The framework does NOT auto-derive `parallel-safe` from `Touches`. The Strategist sets the field explicitly at plan time, with a "considered factors" line in the W-item's Notes explaining what shared surfaces were evaluated. Mechanizing the decision would produce mid-batch merge corruption on the first refactor that touches a shared dependency.

### Migration default

Existing adopter plans predate this ADR — their W-items have no `Parallel-safe` field. On first sync, the Orchestrator treats missing-field as `parallel-safe: false` (current per-task behavior retained). Strategists backfill the field when they decide to use batch mode for a given plan. No plan breaks at sync time.

## Consequences

**What this buys:**

- **Opus amortization.** A 3-item batch pays 1 Integrator call (Opus 1M) instead of 3 Reviewer calls (Opus). Loading `coding-standards.md` and the plan is paid once per batch, not N times. The batched context holds all N diffs simultaneously — review-in-context is cheaper than N separate context builds.
- **Retry loop collapse.** Under per-task mode, a Reviewer `block` dispatches a fresh Executor, who re-reads, re-writes, re-tests; the Reviewer re-runs. Two full rebuild cycles per retry. Under batch mode, the Integrator-fixes small issues inline within acceptance, so most "retry-worthy" issues never bounce back to an Executor at all. Retries as a cost category shrink significantly.
- **User-gate frequency.** Under per-task mode, retry-cap exhaustion and stumped returns both escalate to the user. Under batch mode, most mid-retry issues get fixed inline; true escalations (scope changes) route to async claims that resolve on the Strategist's cadence. The Orchestrator runs closer to continuously between real user gates (phase exit, integration failure, claims requiring user disposition).

**What this costs:**

- **Opus 1M context spend per batch.** Individually large, but the amortized per-W-item cost is lower than 3× Opus Reviewer calls on the same N items.
- **Larger blast radius on Integrator failure.** When the Integrator can't resolve a batch, all N items stall (or named items stall if only some are claimed). Under per-task mode, a stumped item stalled only itself. Mitigated by the first-pass high-profile scan (fail fast before sinking compute) and by the batching cap (~3, same as FWADR-013's parallel cap) — a stuck batch is a stuck 3-way, not a stuck 12-way.
- **Two modes to maintain.** Sequential (parallel-safe: false) keeps per-task peer chain; parallel (parallel-safe: true) uses batch mode. The Orchestrator bootstrap, `session-policy.md`, and brief templates all document both paths. Documentation weight goes up; the per-mode enforcement stays separate and verifiable.
- **Strategist judgment load at plan time.** `Parallel-safe` is a new field and requires real reasoning about shared surfaces. A hasty "true" on a W-item that touches `package.json` is a landmine. The Strategist brief names the risk explicitly and requires a "considered factors" line.

**What this does NOT do:**

- **Does not remove per-task mode.** Sequential W-items (`parallel-safe: false`, or dependency chains) still run under FWADR-013's Executor → Reviewer → QA chain. This ADR adds a mode; it does not retire the default.
- **Does not change Orchestrator's role or read surface.** Orchestrator still dispatches and merges; still does not open diffs. The Integrator-QA is a new peer under the Orchestrator, not a replacement for it.
- **Does not change phase-exit QA or post-promotion QA.** Those are live-environment passes against `{{sub}}.dev.{{website}}.com` or production URLs. Unchanged under this ADR. `qa-brief.md` retains those two contexts; the per-W-item (pre-merge) context is deprecated for parallel-safe W-items (those flow through Integrator-QA instead) and retained for sequential W-items.
- **Does not grant Integrator-QA scope-change authority.** Every scope change routes through a claim. The Integrator is a fix-within-acceptance agent; scope decisions stay with the Strategist + user.

## Alternatives considered

1. **Lower the Reviewer model to Sonnet on XS/S.** Cheaper, but doesn't amortize — still one Reviewer call per W-item. Doesn't close the retry-loop cost either. Kept as a potential future tuning on top of this ADR, not a replacement.
2. **Run per-task Reviewer AND Integrator-QA.** Adds cost rather than reducing it. Rejected.
3. **Batch over a whole phase, not ~3-item sub-batches.** Cheaper per item but one stuck Integrator freezes the entire phase. Blast radius outweighs cost. Rejected.
4. **Auto-derive `Parallel-safe` from `Touches` disjointness.** Rejected — shared surfaces (package.json, migrations, route registries) don't show up in `Touches`. The Strategist's judgment is the source of truth.
5. **Executor self-merge as a fast path.** Rejected — merge-conflict resolution in Sonnet context is where subtle bugs ship. Centralizing merge authority with the Opus 1M Integrator (which already holds the batch's context) is cleaner.
6. **Integrator with broad scope-change authority.** Rejected — silently bypasses the docs-before-code rule in CLAUDE.md. Claims route scope changes through the Strategist+user gate.

## Acceptance criteria for the shipping PR

- `docs/execution-plans/README.md` defines the `Parallel-safe` field and the integration-claim section + shape.
- `docs/dev_framework/session-policy.md` §"Batch mode" exists and cross-references FWADR-013 for per-task mode.
- `docs/dev_framework/templates/executor-brief.md` includes the run-own-tests step, the self-check step, and the explicit "no live dev server in the worktree" rule.
- `docs/dev_framework/templates/integrator-qa-brief.md` exists with first-pass, deep-pass, fix-within-acceptance, and claim-filing sections.
- `docs/dev_framework/templates/reviewer-brief.md` names its scope explicitly as sequential-mode W-items; points at Integrator-QA for batch-mode.
- `docs/dev_framework/templates/qa-brief.md` retains phase-exit and post-promotion contexts; notes that per-W-item (pre-merge) QA is absorbed into Integrator-QA in batch mode.
- `docs/dev_framework/templates/orchestrator-bootstrap.md` has explicit STEPs for batch dispatch, Integrator-QA call, and claim handling.
- `docs/dev_framework/strategist.md` documents `Parallel-safe` discipline ("considered factors" line required) and claim triage.
- `docs/dev_framework/coding-standards.md` §"Who writes code" names Integrator-QA as subject to the same rules as Executor commits.
- `docs/dev_framework/context-management.md` Layer 2 lists `integrator-qa-brief.md`.
- `docs/dev_framework/dev_framework.md` agent-stack diagram reflects batch mode as an added path.
- Missing `Parallel-safe` field on an existing adopter plan is treated as `false` by the Orchestrator at bootstrap. Documented in `execution-plans/README.md` and in this ADR.
