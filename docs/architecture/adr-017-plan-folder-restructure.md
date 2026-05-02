# ADR-017: Plan-folder restructure with single-source Status

**Status:** accepted
**Date:** 2026-04-24
**Deciders:** David (template author), Template Developer session

## Context

Execution plans are single `.md` files (e.g. `docs/execution-plans/exec-phase-1.md`). Each file contains a top-of-plan summary table (W-id | Title | Effort | Markers | Status | Depends on) AND per-W-item sections that include their own `Status:` field.

This shape has two structural problems:

1. **Status is duplicated** — once in the summary table, once on each W-item. Updating one and forgetting the other produces a stale ledger that lies. The Orchestrator's bootstrap STEP 0 CHECK 1 ("summary-table drift") exists exactly to detect this drift after the fact, which is itself an admission that the structure invites it. The doctrine the framework holds — *eliminate drift bait, don't check for it* — was being violated at a load-bearing surface.
2. **Plans grow to hundreds of lines.** An adopting project reported plans reaching 600+ lines. Every agent dispatched against the plan loads the full file even when it only needs one W-item's acceptance criteria. Context budget waste compounds across a phase. Plans were exceeding the 150-line/15-W-item limit in `execution-plans/README.md` regularly, suggesting either the limit was wrong for real work or the structure couldn't accommodate it.

ADR-016 added Integration claims as inline sections on the plan file, which compounds the size problem and embeds another mutable surface inside the same file as the W-item ledger.

## Decision

Restructure each plan from a single file into a **folder** with three artifact types, separated by mutability and concern:

```
docs/execution-plans/
  README.md                        # framework spec (this directory's how-to)
  exec-phase-1/                    # plan folder (one per active or archived plan)
    plan.md                        # the index — runtime state surface
    w-a1.md                        # W-item SOW (static spec for the work)
    w-a2.md
    claims.md                      # Integration claims (open + resolved)
```

### Single-source Status

**Status lives only on the index (`plan.md`).** W-item files do NOT carry a Status field. The W-item file is the static SOW; the index is the runtime ledger. There is no second place for Status to drift to.

The summary table on the index has columns: `W-id | Title | Effort | Markers | Status | Branch`. Title links to the W-item file. Other dispatch-relevant metadata that the Orchestrator needs at-a-glance (Effort, Markers, Status, Branch) sits on the index. SOW fields (What, Acceptance, Touches, References, Depends on, Parallel-safe, Contingencies) sit on the W-item file. Each field appears in exactly one location.

### W-item file structure

Each W-item file is at most 200 lines. Three sections:

- **High level** — What, Acceptance criteria, Depends on.
- **Execution notes** — Parallel-safe, Touches, References, any work-relevant constraints.
- **Contingencies** — Pre-planned fallbacks, known edge cases, "if X happens, do Y" guidance.

The H1 of the file is just the W-id (e.g. `# W-A1`). Title lives on the index table only — no duplication between H1 and the table column.

### Claims file

Integration claims (IC-NNN, ADR-016) move from inline on the plan file into a dedicated `claims.md` in the plan folder. The index links to it. The shape, blocking semantics, and triage protocol from ADR-016 carry over unchanged — only the file location changes.

### State machine: add `held`

The Status state machine extends from 5 to 6 values:

```
pending → in_progress → blocked / done / shipped
                ↓
              held → in_progress (claim approve/modify)
                   → blocked (claim reject)
```

A W-item is `held` when an open Integration claim names it. Held items have a branch that exists; the branch is preserved during the hold (no Executor activity). This eliminates the ambiguity ADR-016 left in place — under that ADR a claim-held item stayed at `in_progress` with a Notes line, leaving the Status field misleading. Under ADR-017 the field reflects actual state.

### Status-write authority follows trigger-agent atomicity

PLAN-WRITE DISCIPLINE (commits 6963426 / c2d3b1a) was originally Orchestrator-only because the Orchestrator was the sole Status writer. Under ADR-017, three agents write Status in different transitions:

- **Orchestrator** — owns most transitions: `pending → in_progress` (dispatch), `in_progress → done` (merge), `in_progress → blocked` (stumped/integration-failure), `done → shipped` (phase-exit), and `blocked → in_progress` (re-dispatch).
- **Integrator-QA** — owns `in_progress → held`, written atomically with the IC-NNN claim filing in `claims.md`. One commit, two file writes (claims.md + plan.md).
- **Strategist** — owns `held → in_progress` (claim approve/modify) and `held → blocked` (claim reject), written atomically with the disposition commit on `claims.md`.

PLAN-WRITE DISCIPLINE applies at all three write sites, not just the Orchestrator's. Each agent's brief / role doc spells out the discipline inline.

### Soft migration

Adopter plans that predate ADR-017 are single-file `<plan>.md`. They continue to work. The Orchestrator's STEP 0 PRELUDE detects format before any reconciliation:

- `docs/execution-plans/<plan>/plan.md` exists → new format (folder). Read the index for ledger; read W-item files on demand.
- `docs/execution-plans/<plan>.md` exists (and no folder of same name) → old format. Read as before — single file, summary table + per-W-item Status, ADR-013/016 flow unchanged.

Both formats are supported during transition. Strategists migrate plans on a schedule that suits the project; the framework does not force migration. New plans drafted after ADR-017 use the folder structure by default.

### Archival

Closing a plan moves the entire folder to `docs/archive/`:

```
mv docs/execution-plans/exec-phase-1 docs/archive/
```

Single move, all artifacts preserved. The plan-folder structure is the same in `docs/archive/` as in `docs/execution-plans/`. `execution-plans/README.md §"Archival"` updates to name the folder move. Single-file plans archived under the old format remain valid in `docs/archive/` as standalone files — soft migration applies to archives too.

## Consequences

**What this buys:**

- **Zero Status drift.** Status appears once. STEP 0 CHECK 1 ("summary-table drift") in the Orchestrator bootstrap retires.
- **Targeted reads.** Executor / Reviewer / Integrator-QA load the W-item file (≤200 lines) instead of the full plan. Per-dispatch context is bounded by the actual work, not the size of unrelated W-items in the same phase.
- **Smaller write contention surfaces.** Plan-write discipline now operates on smaller files; concurrent edits between the Strategist (drafting new W-items in a W-item file) and the Orchestrator (flipping Status on the index) target different files entirely. Stale-read failures on the index decrease structurally.
- **`held` clarity.** A held W-item is named at the Status level rather than via a Notes-field side channel. The Orchestrator's reconciliation, the Strategist's triage, and any agent reading the ledger see the same truth.

**What this costs:**

- **More files in the repo.** A 12-W-item plan grows from one file to 14 (`plan.md` + 12 W-item files + `claims.md`). Tooling that operates on plan content (CI checks, diff readability) sees more granular changes.
- **Soft-migration cognitive load.** Until adopters migrate, two formats coexist. The bootstrap routes by detection; agents reading docs see references to both shapes. The cost is bounded but non-zero.
- **More agents touching Status.** Three write sites instead of one. Each must apply PLAN-WRITE DISCIPLINE. The doctrine doesn't break — agents still verify per the discipline — but the surface area where the discipline matters expands.
- **W-item file churn at draft time.** Strategists writing new plans now create N+2 files instead of one. The natural rhythm changes; expect early adopter friction on the boilerplate.

**What this does NOT do:**

- **Does not change ADR-013 or ADR-016 dispatch flow.** Per-task and batch modes both still apply. Sequential-mode peer chain unchanged. Batch-mode Integrator-QA unchanged. Only the *plan storage shape* and the *Status state machine* change.
- **Does not change retry caps, phase-exit QA, or post-promotion smoke.** Those flows reference Status and the plan path; both work unchanged once the path-detection step routes correctly.
- **Does not change role boundaries.** Strategist drafts plans, Orchestrator dispatches, Integrator-QA integrates, Reviewer reviews per-task. The new write authorities (Integrator on `held`-entry, Strategist on `held`-exit) are scoped narrowly to claim-driven transitions; routine Status flips remain the Orchestrator's.
- **Does not delete or migrate adopter plans.** Soft migration means existing single-file plans keep working. Strategists migrate on their own schedule.

## Alternatives considered

1. **Keep single-file plans, remove Status column from summary table.** Lighter change, single-source Status without restructuring. Rejected — addresses the drift but not the plan-size problem (600-line plans stay 600 lines), and leaves agents loading full plans for any single W-item's work.
2. **Mechanically render the summary table from per-W-item Status (sync script).** Eliminates manual drift but reintroduces a sync mechanism that itself can fail. Rejected — adds operational complexity to fix what the structure should fix structurally.
3. **Hard migration on next sync.** Adopter plans get auto-converted to folder shape. Rejected — invasive, risk of botched migrations, no real upside over soft migration.
4. **Per-W-item file as the only artifact (no separate index).** Index data computed by walking the folder. Rejected — Orchestrator at-a-glance phase view is real value; cheap to maintain.
5. **Keep `held` ambiguous (don't bundle the state-machine change).** Rejected because the restructure is being done explicitly to eliminate drift bait, and accepting a known ambiguous Status value at the surface that drove the restructure undermines the whole point.

## Acceptance criteria for the shipping PR

- `docs/execution-plans/README.md` documents the new folder structure (index + W-item files + claims file) and the soft-migration rule (both formats supported, format detection in bootstrap).
- `docs/execution-plans/README.md` Status state machine includes `held`, with transitions named and write-authority annotated per agent.
- `docs/architecture/adr-016-batch-mode-integrator-qa.md` updated to point at `claims.md` (not inline-on-plan) for claim location.
- `docs/dev_framework/templates/orchestrator-bootstrap.md` STEP 0 PRELUDE routes by format detection (before reconciliation); STEP 0 CHECK 1 conditional on single-file format; new CHECK 6 covers `held` items (must have an open IC-NNN); plan-write sites use new path conventions.
- `docs/dev_framework/templates/integrator-qa-brief.md` claim-filing step writes `claims.md` and flips index Status to `held` atomically; PLAN-WRITE DISCIPLINE inlined.
- `docs/dev_framework/strategist.md` claim disposition flips index Status `held → in_progress / blocked` atomically; PLAN-WRITE DISCIPLINE inlined.
- `docs/dev_framework/templates/executor-brief.md` and `reviewer-brief.md` reference the W-item file path under the new structure.
- `docs/dev_framework/session-policy.md §"Status ledger"` ownership clause names the three writing agents.
- `docs/dev_framework/context-management.md` plan-budget rules updated for the new structure.
- `docs/dev_framework/dev_framework.md` references survive the path change.
- Single PR. State-machine `held` addition, structure split, soft-migration detection, and PLAN-WRITE DISCIPLINE multi-agent extension all ship together — half-shipping any of them creates an incoherent intermediate state.

## Revision (v1.1, 2026-05-01) — Dependency data joins the index

**Problem.** The Parallel Developer's bootstrap (ADR-018) had to read multiple W-item files at scan time to detect non-competing items, because the data needed for collision detection (`Touches`, `Depends on`, parallel-safe surfaces) lived only on the W-item files. Reading N W-item files on every Parallel Dev boot defeated the context-budget rationale for the index/SOW split that this ADR established. Worse, once read, those files couldn't be selectively evicted from the persistent session — `/compact` is whole-session and lossy. So the data leaked into the working session and polluted downstream coding work.

**Decision.** Extend this ADR's single-source doctrine to dependency data. Effective immediately:

- The **`Blocked by`** column on the summary table is the single source of dependency data. Comma-separated W-ids that must reach `done` or `shipped` before the item is eligible to claim, or `—` when none.
- The **`Depends on`** field on the W-item file is **removed**. The "High level" section of a W-item file now has two fields: `What` and `Acceptance criteria`. Dependency information is read from the index alone.
- The **stream-letter convention** on W-ids becomes load-bearing for Parallel Developer's non-competing scan: items in the same stream (same letter) are assumed to share a code-path area and are skipped against claimed items; items in different streams are assumed non-competing. The convention is enforced by Strategist discipline — named-gap statement in `execution-plans/README.md` §"Index fields" on W-id.
- **`Parallel-safe` is unchanged in semantics but narrowed in scope** — it gates Orchestrator batch-mode dispatch (ADR-016) only. Parallel Developer (ADR-018) does NOT use this field. The asymmetry is intentional and documented in `execution-plans/README.md` §"Parallel-safe field".

**Surfaces updated:** lines 36 (summary-table column list) and 42 (W-item file "High level" enumeration) above are superseded by this Revision. The current canonical specification lives in `execution-plans/README.md` (summary table example, Index fields, W-item file fields), `dev_framework/developer.md` §"Non-competing scan", and `dev_framework/strategist.md` (where Strategist authors `Blocked by` and the stream-letter convention).

**Migration.** No data migration required — the project is in stub state; no existing plans carry the now-removed `Depends on` field. Adopters with existing plans on the soft-migration single-file format may continue to use `Depends on` inline; the no-`Depends on`-on-W-item-file rule applies only to plans drafted under the folder layout going forward. Strategists backfilling existing folder-layout plans copy the `Depends on` value into the index's `Blocked by` column and remove the line from the W-item file.

**Why a Revision instead of a new ADR.** The change extends the same single-source doctrine this ADR established (Status lives on the index only) to one more field. New rule, same principle. A separate ADR would imply a new principle.
