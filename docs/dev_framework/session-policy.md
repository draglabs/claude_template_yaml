# Session policy

**Source of truth for how a Claude Code session executes work on this repo.** Linked from `CLAUDE.md`; editable directly without touching CLAUDE.md.

Applies to any session (any model tier) driving work items from [execution-plans/](../execution-plans/) or equivalent phase plans.

**Project deviations** from this policy live in [`dev_framework_exceptions.md`](../framework_exceptions/dev_framework_exceptions.md), maintained by the project's Strategist. Every agent reads that file alongside CLAUDE.md. This policy doc is canonical — it is not edited per-project.

## Model tiers (role-relative, ADR-022)

Framework docs and briefs never name literal models — model generations change under the framework. Two named tiers, resolved to concrete model names **at spawn time**:

- **Top tier** — the strongest generally available Claude model in the harness at the moment of spawn. Judgment work: Reviewer, Integrator-QA, and judgment-heavy persistent sessions.
- **Work tier** — a cost-efficient tier below the top tier, sufficient for well-briefed, bounded work: Executor, QA, consultants.

The Integrator-QA additionally requires the **long-context variant** available at the top tier (see §"Batch mode").

**Invariant: a review gate runs at a tier ≥ the tier that wrote the code.** Subagents inherit the parent session's model by default in the current harness — so the spawner sets the work-tier model *explicitly* for Executors/QA/consultants, and for a Reviewer either inherits (when the session itself runs top tier) or explicitly sets the top-tier model. Merge-commit trailers record the **actual resolved model names**, never names copied from a template. See [ADR-022](../architecture/adr-022-runtime-recalibration.md).

## Roles

| Role | Played by | Responsibility |
|---|---|---|
| **Orchestrator** | The active Claude Code session. | **Dispatcher + merger + review coordinator.** Picks the next W-item, pre-creates the worktree off `origin/dev`, dispatches Executor, then spawns Reviewer and (when required) QA as peer subagents, owns the retry loop, merges, pushes. Does NOT write code. Does NOT open diffs or `src/` directly — reads Reviewer/QA verdicts instead (which may cite `file:line`). |
| **Executor** | Work-tier subagent spawned via Agent tool by the Orchestrator. | **Writer.** Writes code + tests in a pre-created worktree, commits to the feature branch, returns a code-only package to the Orchestrator. Does NOT spawn Reviewer or QA. Does NOT merge or push. |
| **Reviewer** | Top-tier subagent spawned via Agent tool **by the Orchestrator**. Sequential-mode (per-task) only. | Reviews the Executor's diff against canonical docs + coding standards. Returns verdict + concerns to the Orchestrator. Does not modify files. |
| **QA** | Work-tier subagent spawned via Agent tool **by the Orchestrator** — per-W-item (pre-merge, sequential mode only), at phase exit, or post-promotion. | Runs end-to-end tests against a pre-merge worktree build or the live dev environment. Returns structured pass/fail to the Orchestrator. Cleans up test artifacts on success. |
| **Integrator-QA** | Top-tier long-context subagent spawned via Agent tool **by the Orchestrator** — batch mode (ADR-016) only, end of parallel batch. | Integrates N parallel-safe W-item branches, resolves merges, reviews against coding standards, runs full test suite (including live/Playwright), fixes within acceptance, files claims for scope changes. Absorbs per-task Reviewer and pre-merge QA for items in the batch. |
| **Doc Consultant** | Work-tier subagent spawned by any role. | Reads the doc corpus and answers a targeted question. Returns a short citation-backed answer. Does not modify files. |
| **Code Consultant** | Work-tier subagent spawned primarily by the Strategist. | Reads code and answers a targeted question. Returns a short citation-backed answer. Does not modify files. |

Briefing templates for each subagent role live in [`templates/`](templates/). Load them when spawning a subagent — not at session start.

**Hard constraint of the runtime: subagents cannot spawn subagents.** Confirmed by Anthropic's Agent SDK docs and by GitHub issue history. Under this policy every subagent is a peer under the Orchestrator. See [ADR-013](../architecture/adr-013-peer-dispatch.md) for the decision record.

### Dispatch flow

```
User ↔ Orchestrator
           │
           ├─▶ Executor (work tier, worktree) ── code-only return ───▶ Orchestrator
           │
           ├─▶ Reviewer (top tier)            ── verdict + concerns ─▶ Orchestrator
           │       │
           │       └─ on block: Orchestrator retries the Executor —
           │         continuation or fresh dispatch per §"Orchestrator-
           │         owned retry mechanics" — then re-spawns Reviewer.
           │         Consumes one retry.
           │
           ├─▶ QA (work tier, when required)  ── verdict + results ──▶ Orchestrator
           │       │
           │       └─ on fail: same retry loop with QA findings as the
           │         concerns; re-runs Reviewer then QA. Consumes one
           │         retry.
           │
           ▼ on ship + pass (or retry cap + escalation)
       Orchestrator ──▶ merge to dev ──▶ push ──▶ auto-advance
                                                    │
                (at phase boundary + user OK) ──────┘
                                │
                                ▼
                        merge dev → main → production CI deploy
```

Sequential by design: Reviewer first, QA only after `ship`. Parallel execution would waste QA cycles on code that's about to change.

## Tiered execution pattern (sequential mode)

Applies to sequential-mode (per-task) dispatch — W-items with `Parallel-safe: false` or unset. For batch-mode dispatch (`Parallel-safe: true`), see §"Batch mode" below; batch mode does NOT use tier-based retry caps, it uses verdict-driven outcomes from the Integrator-QA.

All tiers use the same peer-dispatch flow. Tiers differ only in **which gates are mandatory** and **how many retries the Orchestrator gets before escalating**.

"Retries" means attempts **after** the initial write. `retries: 2` means: write → Reviewer (+ QA), and if blocked, up to 2 more (Executor fix cycle with concerns → Reviewer + QA) loops.

| Tier | Bucket | Executor | Reviewer | QA | Retries | Total loops | Notes |
|---|---|---|---|---|---|---|---|
| **XS** | Easy | Work tier, worktree | Top tier (required) | Skip unless 🧪 | 2 | 3 | Trivial edits. |
| **S** | Easy | Work tier, worktree | Top tier (required) | Skip unless 🧪 | 2 | 3 | |
| **M** | Unknown tier | Work tier, worktree | Top tier (required) | Skip unless 🧪 | 2 | 3 | Ambiguous effort — same budget as easy by default. |
| **L** | Hard | Work tier, worktree | Top tier (required) | Required | 3 | 4 | |
| **XL** | Hard | Work tier, worktree | Top tier (required) | Required | 3 | 4 | Split if > 4h. |
| ⚠️ override | — | Work tier, worktree | Top tier (required) | Required (forced) | 3 | 4 | Locks to Hard regardless of base tier. |

**Every W-item** gets a worktree + a feature branch (`w-<id>/<slug>`). Nothing lands on `dev` except via Orchestrator merge after all required gates pass.

### How the retry budget is used

- **Initial attempt:** Orchestrator dispatches Executor; Executor writes, commits, returns. Orchestrator spawns Reviewer. Orchestrator spawns QA if required. This initial cycle is NOT a retry.
- **Each retry:** Reviewer `block` or QA `fail` triggers one Executor fix cycle — continuation or fresh dispatch per §"Orchestrator-owned retry mechanics" — with the concerns verbatim as sharpened context, then re-spawn Reviewer (and QA if required). One fix cycle consumes one retry.
- **Exhaustion:** on retry cap reached with an unresolved block, Orchestrator escalates to the user (see §"When to escalate to the user"). The W-item flips to `blocked` in the plan.
- A fix that satisfies Reviewer but breaks QA (or vice versa) still counts as one retry, not two. One fix cycle = one retry regardless of which gate failed and which mechanism was used.

### Orchestrator-owned retry mechanics

Retry state lives in the Orchestrator session; it is NOT written to the plan ledger. The plan records only Status transitions (`pending` → `in_progress` → `blocked` / `done` / `shipped`) — retry counts are ephemeral.

Two retry mechanisms exist ([ADR-022](../architecture/adr-022-runtime-recalibration.md)):

- **Continuation (default).** The Orchestrator sends the blocking concerns to the *same* Executor via SendMessage — context intact, cheapest path. The message contains the full verbatim concerns from the Reviewer (or QA) and the one-line instruction: "address these concerns; do not reopen the original scope." Appropriate when the block is about incomplete or incorrect *execution* of a sound approach.
- **Fresh dispatch.** A new Executor spawned via the Agent tool with a rebuilt brief containing: the feature branch name (worktree already exists; Executor checks out the existing commits), the full verbatim concerns, and the same no-scope-reopen instruction. **Mandatory** when any of:
  1. The Reviewer's `block` carries `Block class: approach` — the approach is wrong, not the execution. A continued Executor tends to rationalize its own prior choices; fresh eyes don't.
  2. The same concern (or its direct descendant) survives a continuation retry — one continuation attempt per concern, then fresh eyes.
  3. The prior Executor is no longer reachable (session ended, agent expired).

The routing signal is mechanical: the Reviewer's `block` return includes a **Block class** field (`execution` / `approach`); QA `fail`s are treated as `execution` unless the QA return says otherwise. Either mechanism consumes one retry against the tier cap.

The Executor writes a new commit on top of the existing ones — **no rebase, no amend.** The Reviewer reads history; the chain of fix-commits shows the loop's work.

**History note.** Earlier framework versions mandated fresh dispatch exclusively because SendMessage was unavailable in the Claude Code CLI runtime (ADR-013, verified 2026-04-23). The runtime now provides SendMessage; continuation-by-default is a deliberate choice, with fresh dispatch retained where independent judgment matters. See ADR-022.

### Escalation

The Orchestrator relays to the user on:

- Retry cap exhausted with an unresolved block or fail.
- Executor returned "brief ambiguity at confirm" — no code produced, the brief needs judgment the Orchestrator can't provide.
- A sensitive surface is implicated (auth, keys, billing, data migration) and the Reviewer flagged architectural concern.
- A single W-item has consumed substantially more than its effort-estimate budget (> 50% over) in Orchestrator dispatch time.

The Orchestrator does NOT escalate when:

- All gates passed within the retry cap (user doesn't need to see the intermediate blocks).
- One retry fixed the concern cleanly.

## Batch mode

An alternative dispatch path for W-items marked `Parallel-safe: true` on the plan. Introduced in [ADR-016](../architecture/adr-016-batch-mode-integrator-qa.md) to amortize top-tier review cost across independent work. When multiple parallel-safe W-items are ready to dispatch, the Orchestrator runs them as a batch instead of serially.

### Batch dispatch flow

```
Orchestrator
  ├─▶ Executor (worktree, work tier) — W-X1   ─┐
  ├─▶ Executor (worktree, work tier) — W-X2   ─┤  concurrent,
  ├─▶ Executor (worktree, work tier) — W-X3   ─┘  ~3 cap
              │
              ▼ all return with PASS shapes (Tests + Self-check included)
         Orchestrator
              │
              ▼
  ─▶ Integrator-QA (top tier, long-context; sees all N worktrees)
              │
              ├─ First pass: high-profile scan
              │     └─ red flag + <80% confidence → integration-failure
              │                                    (surface to user; no merge)
              │
              ├─ Deep pass: pull → merge → review → test (incl. Playwright)
              │     └─ fix within acceptance (TDD, coding-standards)
              │
              ├─ Scope-change path (outside acceptance)
              │     ├─ ≥80% confident → file IC-NNN claim on plan; named
              │     │                    W-items held, unnamed proceed
              │     └─ <80% confident → integration-failure (surface)
              │
              ▼
         Orchestrator merges clean items to dev → push → auto-advance
```

### How batch mode differs from sequential mode

| Concern | Sequential (ADR-013) | Batch (ADR-016) |
|---|---|---|
| Reviewer stage | Per-task top-tier call | Absorbed into Integrator-QA (one top-tier long-context call per batch) |
| Pre-merge QA | Per-task work-tier call (L/XL/🧪/⚠️) | Absorbed into Integrator-QA |
| Phase-exit QA | Unchanged (live dev env) | Unchanged |
| Retries on `block` | Executor retry cycle (continuation or fresh dispatch) + fresh Reviewer, counted against cap | Integrator-QA fixes inline within acceptance — no Executor bounce. Claim path handles scope issues. |
| Merge authority | Orchestrator, after Reviewer ships | Orchestrator, after Integrator-QA returns `clean` or `partial` (only clean items merge on partial) |
| Conflict resolution | Orchestrator (conflicts rare — one branch merges at a time) | Integrator-QA (single long-context view sees all diffs; conflicts more likely given concurrent work) |

### Eligibility

A W-item is batch-eligible iff:
1. The plan has `Parallel-safe: true` on the item.
2. All W-ids in the item's `Blocked by` column on the index are `done` or `shipped`.
3. No open Integration claim (IC-NNN) on the plan names it as a Blocked item.

The Orchestrator groups up to ~3 eligible items into a batch and dispatches them concurrently. Items that fail eligibility at the moment of dispatch (e.g., a `Blocked by` entry just flipped to blocked) sit out the current batch and are reconsidered for the next one.

### Integrator-QA retry model

Unlike per-task retries, batch-mode does not have a fixed "retry cap." The Integrator-QA either:

- **Returns `clean`** — all items in the batch merged. Auto-advance.
- **Returns `partial`** — some items merged, others held by open claims. Auto-advance on the clean items; named-blocked items wait for Strategist+user claim resolution.
- **Returns `integration-failure`** — first-pass red flag or low-confidence scope issue. Nothing merged. Surface to user immediately.
- **Returns `stumped`** — deep pass revealed something the Integrator can't resolve, including within-acceptance. Nothing merged. Surface to user.

There is no "re-run the Integrator-QA" loop the way sequential mode runs Reviewer loops. If the Integrator can't close a batch, the user decides next steps. Re-dispatching Executors to the same items with sharpened briefs is one option the user may choose, but it's a user decision, not an automatic retry.

### Claim resolution

Integration claims (IC-NNN) live in `claims.md` inside the plan folder under the ADR-017 layout, or inline on the single-file plan under the pre-ADR-017 layout — see `execution-plans/README.md §"Integration claims"`. Filing a claim is the Integrator-QA's `in_progress → held` write (atomic with the IC-NNN entry). The Strategist triages alongside `process-exceptions.md` at phase boundaries and on demand. Dispositions (`approve` / `reject` / `modify`) are recorded with the claim and flip the named W-items' Status atomically: `held → in_progress` on approve/modify, `held → blocked` on reject. After the Strategist's disposition the Orchestrator re-dispatches affected items at its next eligibility check (either as a small batch or sequentially, depending on updated `Parallel-safe` status). The Orchestrator's cadence is "continue forward progress on unblocked items; revisit held items after Strategist disposition."

## Status ledger (non-negotiable)

Status writes on the active execution plan are **atomic with the git events that trigger them**. Under [ADR-017](../architecture/adr-017-plan-folder-restructure.md) and [ADR-018](../architecture/adr-018-developer-role.md), four agents share the writer authority — each owns a distinct subset of transitions:

- **Orchestrator** (Orchestrator-mode phases) — owns most transitions:
  - `pending → in_progress` on Executor dispatch (commit the plan update **before** spawning the Executor; no "update later").
  - `in_progress → done` alongside the merge commit.
  - `in_progress → blocked` on Executor stumped or Integrator-QA integration failure.
  - `blocked → in_progress` on re-dispatch with sharpened brief.
  - `done → shipped` in the same commit as the `dev → main` promotion merge.
- **Integrator-QA** — owns `in_progress → held` (Orchestrator batch mode). Atomic with filing an IC-NNN claim: one commit writes both `claims.md` (new entry under "## Open") and the index `plan.md` (Status flip on every named W-item). Under the pre-ADR-017 single-file layout the same commit edits the inline claims section and the per-W-item Status fields.
- **Strategist** — owns `held → in_progress` (claim approve / modify) and `held → blocked` (claim reject). Atomic with claim disposition: one commit moves the IC-NNN entry from "## Open" to "## Resolved" on `claims.md` AND flips the named W-items' Status on the index. If the disposition revises acceptance, the W-item file edit is part of the same commit.
- **Developer** (Developer-mode phases) — owns Developer-mode lifecycle transitions ([ADR-018](../architecture/adr-018-developer-role.md)):
  - `pending → in_progress` on item claim (atomic with branch creation + the user-anchor message).
  - `in_progress → code_review` when the user confirms the feature works (atomic with a "ready for review" commit on the W-item branch; Developer then spawns a Reviewer subagent).
  - `code_review → done` on Reviewer-subagent ship verdict (atomic with the merge to `dev` + Implementation log written on the W-item file).
  - `code_review → in_progress` on a self-review block, user-mediated re-engagement (NOT auto-loop).
  - `in_progress → blocked` when an issue is unblockable.
  - `in_progress → held` when filing a claim mid-work (rare path; same shape as Integrator-QA's claim filing).
  - `done → shipped` when the phase is Developer-driven, in the same commit as the `dev → main` promotion merge.

A retry dispatch (`blocked → in_progress` or `code_review → in_progress`) does NOT increment any counter on the plan — the W-item simply moves through Status. Retry counts are role-internal (Orchestrator's tier-based caps, Developer's user-mediated re-engagement).

**Mode coexistence per item (ADR-018, v2).** Orchestrator and Developer modes both write Status. Per-item collision is naturally enforced by the mode-specific Status paths — Orchestrator's `pending → in_progress → done` and Developer's `pending → in_progress → code_review → done` take different routes from `in_progress`. Plans carry a Strategist-set `Mode` field as a recommendation (advisory, not binding); mixed-mode phases are allowed. Items lock into a mode at claim time via the path they take. Claim attribution lives in the plan's Notes section for at-a-glance disambiguation of in-flight items.

PLAN-WRITE DISCIPLINE — the read-fresh / Edit / single-commit / verify-pushed sequence — applies at all four write sites. The Orchestrator's discipline lives in [`templates/orchestrator-bootstrap.md`](templates/orchestrator-bootstrap.md) (top of file). The Integrator-QA's lives in [`templates/integrator-qa-brief.md`](templates/integrator-qa-brief.md) §STEP 3. The Strategist's lives in [`strategist.md`](strategist.md) §"Plan-write discipline (claim disposition)." The Developer's lives in [`developer.md`](developer.md) §"Plan-write discipline (Developer)."

Full state machine + transition rules + transition table are in [`../execution-plans/README.md`](../execution-plans/README.md) §"Status state machine."

### Why this matters

The plan is a ledger. A stale ledger causes:
- Fresh Orchestrator sessions re-dispatch work that's already in flight.
- Phase-exit gates pass over done-but-unmarked items, leaving them un-shipped.
- The user loses visibility into whether the system is working or stuck.

A ledger that lies is worse than no ledger — future sessions act confidently on bad data.

### CLAUDE.md is NOT a live dashboard

CLAUDE.md's Status line is a one-liner ("Phase 2 active, stream A in flight") pointing at the active execution plan. It does NOT list per-W-item state. If you catch yourself editing W-item status in CLAUDE.md, stop — that belongs in the plan doc.

### Reconciliation on session start

On Orchestrator bootstrap, STEP 0 reconciles the ledger against git reality. See [`templates/orchestrator-bootstrap.md`](templates/orchestrator-bootstrap.md) STEP 0. If the plan says `pending` but a branch with commits exists, or if the plan says `in_progress` on a branch that's been deleted, the Orchestrator surfaces the discrepancy to the user before dispatching anything new.

## Auto-advance after merge

After merging to **`dev`** and pushing (and after flipping the W-item Status to `done`), **immediately orient on the next W-item**. No "Ready for your go?" pause.

**Pause only if:**
- Retry cap was exhausted and the W-item flipped to `blocked`.
- Next item has unresolved dependencies.
- Orchestrator confidence is `low`.
- User explicitly asked to pause.
- Dev-branch CI (remote-hosted mode) is still running or has reported failure — wait for green before starting the next item, so dev doesn't accumulate broken commits.

**Auto-advance does NOT apply to promotion to main.** After merging `dev` → `main`, pause. Wait for production CI confirmation; wait for the user to confirm prod landed cleanly before starting the next phase.

## Mandatory overrides

- **⚠️ items** — Top-tier review is already the default. ⚠️ additionally forces QA regardless of tier and bumps the retry cap to 3.
- **🔍 items** — The Orchestrator runs the spike directly (research, not code). 2h max. No Executor dispatch. Validate conclusions in the real runtime environment, not simplified tests. This is the ONE case where the Orchestrator touches content, because there's no diff to produce.
- **🧪 items** — QA required regardless of tier. Orchestrator dispatches QA after Reviewer ships.
- **Parallel execution** — only for dependency-graph-independent W-items marked `Parallel-safe: true` on the plan (see [ADR-016](../architecture/adr-016-batch-mode-integrator-qa.md) and `execution-plans/README.md §"Parallel-safe field"`). Two dispatch paths:
  - **Batch mode (Parallel-safe: true):** Orchestrator dispatches up to ~3 concurrent Executors, one worktree each. When all return, a single Integrator-QA (top tier, long-context) call absorbs per-task Reviewer + pre-merge QA — one top-tier call amortized across the batch instead of N. See §"Batch mode" below.
  - **Sequential mode (Parallel-safe: false or unset):** Orchestrator runs each W-item through its own per-task peer chain (Executor, Reviewer, optional QA) serially. This is the ADR-013 default.
  Practical cap on batch size is ~3 W-items — wider batches increase Integrator-QA blast radius on failure.
- **Doc questions → Doc Consultant, not inline reads.** When the Orchestrator needs to check a locked decision, cross-reference acceptance criteria, or verify a constraint, spawn a Doc Consultant subagent instead of reading the docs inline. The Consultant's 10-line answer costs far less context than loading 3 full docs. Exception: docs already loaded at session start (Layer 1).
- **Strategist code questions → Code Consultant.** The Strategist does not load project `src/`. When it needs a code-level fact to approve a plan or verify a claim, it spawns a Code Consultant subagent.
- **Code-quality rules live in the subagent layer.** The Orchestrator does not carry `docs/dev_framework/coding-standards.md`. TDD, no-hardcoded-values, and fail-loudly enforcement happens in the Executor brief (authoring) and Reviewer brief (blocking merge). If a Reviewer returns `ship` on code that violates the standards, that's a Reviewer bug — file an execution incident.

## Trust but verify

Under peer dispatch, the Orchestrator called each subagent itself. Provenance is mechanical — the Agent tool results are in the Orchestrator's own message history, each with an `agentId`. Fabrication of a verdict is impossible by construction.

On each subagent return the Orchestrator checks:

1. **Executor return.** Confirms the worktree branch exists and matches the claimed `w-<id>/<slug>` name. Reads the 1-line diff summary and the Files touched list. Flags scope creep (files outside the brief's Touches) — this is the one code-level check the Orchestrator does, because the Reviewer hasn't run yet.
2. **Reviewer return.** Reads the verdict (`ship` / `ship-with-concerns` / `block`) and the per-question answers. On `block`, reads the listed concerns — they become the next Executor's brief.
3. **QA return (when required).** Reads the verdict and per-criterion results. On `fail`, reads the precise file:line or behavior hint — that becomes the next Executor's brief.

The Orchestrator does NOT open diffs or source files directly. Verdicts cite `file:line`; the Orchestrator reads the citations as evidence, not the code itself. Code reading remains bounded to Executor and Reviewer contexts.

## Orchestrator model choice

Under peer dispatch the Orchestrator sees Reviewer and QA verdicts inline — per-question answers, per-criterion results — which is more context than the old 6-line pass packages of earlier models. The **top tier** is preferred when retry judgment is likely to matter (⚠️ density, ambiguous Reviewer concerns, scope-creep calls). The **work tier** remains sufficient for phases of routine W-items where most items ship on first pass.

## Branching and isolation (dev → main)

This project uses a **dev branch** between feature branches and main. Features merge to dev; dev promotes to main at phase boundaries.

```
feature (w-<id>/<slug>)  ──Orchestrator merge──▶  dev  ──phase-exit promotion──▶  main
                                                   │                               │
                                                   ▼                               ▼
                                     CI deploys to dev env            CI deploys to production
                             (local: no deploy; remote: dev server)   (always remote)
```

See [`dev-environment.md`](dev-environment.md) for local vs remote dev mode.

Every W-item follows one of two flows depending on its `Parallel-safe` field (see §"Batch mode" above and [ADR-016](../architecture/adr-016-batch-mode-integrator-qa.md)). The sequential flow described below is per-task mode (ADR-013); batch-mode items follow the batch flow in §"Batch mode" §"Batch dispatch flow" instead of steps 3–4 below.

### Sequential mode (Parallel-safe: false or unset)

1. **Orchestrator** pre-creates the worktree explicitly off `origin/dev` with `git worktree add -b w-<id>/<slug> <path> origin/dev`, then dispatches the Executor via the Agent tool (WITHOUT the `isolation: "worktree"` flag — the Orchestrator owns worktree creation under this model). The Executor works inside the pre-created worktree. The standard worktree path is `/tmp/worktrees/<project>/w-<id>-<slug>`, where `<project>` = `basename $CODE_ROOT` (the git repo name; see [`context-management.md §Project layout`](context-management.md#project-layout)). Under split layout this is the `$CODE_SUBDIR` name; under flat layout it is `basename $PROJECT_DIR`.

   **Mechanism, not intention.** The Agent tool's `isolation: "worktree"` flag creates a worktree from the parent session's current HEAD. If the Orchestrator happens to be sitting on `main` (or any other branch) when it dispatches, the worktree — and therefore the feature branch — inherits THAT base. Rule compliance here requires the Orchestrator to pre-create the worktree off `origin/dev` explicitly so the base becomes a literal command-line argument. "I read the rule" is not enforcement. The command is.

2. **Executor** writes code + tests inside the worktree, commits to the feature branch, runs its own unit/integration tests + coding-standards self-check, returns a code-only package to the Orchestrator.

3. **Orchestrator** spawns the Reviewer (top tier) as a peer Agent-tool call, passing the worktree path and the latest commit SHA. On `block`, Orchestrator runs one Executor fix cycle — continuation or fresh dispatch per §"Orchestrator-owned retry mechanics" — and re-spawns the Reviewer. Retry cap per tier.

4. **Orchestrator** (if tier L/XL or marker 🧪 or ⚠️) spawns the QA as a peer Agent-tool call after Reviewer ships. Same retry pattern on `fail`.

5. **Orchestrator** verifies the return per §"Trust but verify", merges the feature branch to **`dev`**, pushes `dev`. If remote-hosted dev, CI now deploys to `{{sub}}.dev.{{website}}.com`. Auto-advance to next W-item.

### Batch mode (Parallel-safe: true)

Same worktree pre-creation discipline per item (step 1), same Executor self-test discipline (step 2). Differences:

- Orchestrator dispatches up to ~3 Executors concurrently.
- When all N Executors return, Orchestrator spawns a single Integrator-QA (top tier, long-context) that absorbs per-task Reviewer + pre-merge QA for every item in the batch (replaces steps 3–4).
- Integrator-QA returns `clean` / `partial` / `integration-failure` / `stumped`. On `clean`, Orchestrator merges every item. On `partial`, Orchestrator merges the non-blocked items and leaves the claim-blocked items for Strategist disposition. On `integration-failure` or `stumped`, Orchestrator surfaces to the user (no merge).
- Fix commits authored by the Integrator-QA are already in dev (or an integration branch the Integrator is using) when its return lands; Orchestrator does not re-merge those.

Main is NOT touched per W-item. Main only moves at phase-boundary promotion (see §"Phase exit gate" below).

### Commit authorship

Merge commit on **`dev`** (per W-item). The **Lessons learned** block is required — pasted verbatim from the Executor's pass shape. This is the user's primary post-hoc visibility into what the Executor experienced.

```
Merge w-a2/some-feature: short description

<diff 1-line summary from Executor>

Executor: <model resolved at spawn> (worktree-isolated)
Reviewer: <model resolved at spawn>, <verdict>
QA: <model resolved at spawn>, <pass | n/a>
Retries used: <n>/<retries>

Lessons learned:
  - <bullet from Executor pass shape, verbatim>
  - <bullet>

Co-Authored-By: Claude <executor model> <noreply@anthropic.com>
Co-Authored-By: Claude <reviewer model> <noreply@anthropic.com>
```

Model lines record the **actual model names resolved at spawn time** — never copy literal names from a template. A trailer that names a model the agent didn't run on is a ledger that lies (ADR-022).

If the Executor's return came back without Lessons learned, the Orchestrator bounces back and asks — does NOT merge with an empty block. (Exception: Executor wrote "Nothing surprising." That's a valid Lessons-learned value.)

### Promotion commit (dev → main)

At phase exit, after QA passes on the dev environment and the user authorizes, the Orchestrator merges `dev` → `main`. Use a single annotated merge commit:

```
Promote dev → main: <phase name> complete

W-items included: <list of w-ids>
Phase-exit QA: pass (targeted {{sub}}.dev.{{website}}.com)
Authorized by: <user | Strategist on user's behalf>

Co-Authored-By: Claude <noreply@anthropic.com>
```

No auto-advance on this commit — the Orchestrator pauses after a main push to let the user confirm production deploy landed cleanly before starting the next phase.

## Phase exit gate (and promotion to main)

All W-items done is necessary but not sufficient. Phase exit under the dev-branch model requires **demonstrating every exit criterion live on the dev environment**, then promoting dev → main.

### Steps

1. Confirm every W-item in the phase is merged to `dev` (no `blocked` items outstanding).
2. Run the full test suite against `dev` — all green.
3. Apply all pending migrations (on the dev environment or locally if local-hosted).
4. Push `dev` to origin (if any unpushed commits). Wait for dev-branch CI to pass.
5. **Orchestrator spawns a QA subagent against `{{sub}}.dev.{{website}}.com`** (this is the same peer-dispatch pattern as per-W-item QA; spawn context is "phase exit"). Record pass/fail per criterion.
6. Report per-criterion results to the user. **Explicit user authorization required to proceed.** The user sees the QA verdict; the user says "promote" or "hold."
7. On authorization: Orchestrator merges `dev` → `main` (annotated merge commit per §"Promotion commit"), pushes `main`. Production CI deploys.
8. Optional post-promotion smoke test against production URL (`{{sub}}.{{website}}.com`). Strongly recommended for phases that touched critical paths (auth, billing, data migration). Not mandatory.

### Failure modes

- **Criteria fail on dev** → re-open the failing W-ids. Fix on dev. Re-run the gate. No promotion yet.
- **Criteria pass on dev, user withholds authorization** → not a failure, just a hold. Dev continues to accumulate W-items if there are follow-ups; main stays where it is.
- **CI fails on `main` after promotion** → unusual (dev CI already passed), but possible if prod environment differs from dev. Revert on main; investigate the divergence; document in `execution-incidents.md`.

### Why user authorization is explicit here

Every W-item merge to dev is automated (Orchestrator decides). Every promotion to main is a user decision. This is the single point where human judgment gates production.

## When to escalate to the user

The Orchestrator relays to the user when:

- Retry cap exhausted on a W-item with an unresolved concern.
- A W-item returned with architectural ambiguity the Orchestrator cannot resolve (locked-decision collision, plan contradiction, scope ambiguity).
- A sensitive surface (auth, keys, billing, data migration) surfaced a Reviewer concern the retry loop couldn't close.
- A W-item consumed substantially more than the effort-estimate budget (> 50% over).
- A spike (🔍) diverged from the expected approach.

The Orchestrator does NOT escalate when:

- All gates passed within the retry cap — merge, auto-advance, no interruption.
- A single retry closed the concern cleanly.

## Automatic re-orientation on context resets

Claude Code loses context on four paths: fresh startup, `--resume`, manual `/clear`, automatic or manual `/compact`. Two `SessionStart` hooks fire on all four — wired in `.claude/settings.json`, runs in order:

1. **`.claude/hooks/sync-framework.sh`** — destructively syncs `docs/dev_framework/` and `.claude/hooks/` from the canonical `claude_template_yaml` repo, initializes `docs/framework_exceptions/` if missing, and refreshes the framework-managed block of CLAUDE.md. See §"Framework sync on context resets" below and [ADR-014](../architecture/adr-014-framework-sync-on-session-start.md).
2. **`.claude/hooks/session-reorient.sh`** — injects a role re-orientation instruction tailored to the reset `source`. The hook routes by source and tells the session which docs to re-read and — for Orchestrators — to run the ledger reconciliation before dispatching. See [ADR-012](../architecture/adr-012-auto-reorient-hook.md).

Both are mechanical enforcements of rules that used to be English-only: "re-read the SOP after context loss" and "keep the framework canonical." Each one is a command, not a hope.

Hooks are canonical to the template; projects that adopt the template inherit them automatically through the framework sync itself. Project-specific deviations go in [`dev_framework_exceptions.md`](../framework_exceptions/dev_framework_exceptions.md), not by editing the hooks.

**After `/compact` or `/clear`, send a one-word trigger** (`ack`, `continue`, `role?`) to get the session to re-orient. Claude Code is turn-reactive: SessionStart hooks inject the re-orientation text into Claude's context, but Claude cannot produce a message without a user turn. The first user message after a reset is what triggers the acknowledgement and any role question. This is a Claude Code platform constraint, not a framework choice — see ADR-012 §"What this does NOT do".

## Framework sync on context resets

`docs/dev_framework/*` is canonical — it is maintained in the `claude_template_yaml` source repo and copy-pasted into every adopting project. The sync hook enforces this:

- **Template root discovery:** `.env` file `CLAUDE_TEMPLATE_ROOT=` line → `../claude_template_yaml` → `../../claude_template_yaml` → `../../../claude_template_yaml`, in priority order. Shell environment variables are intentionally not consulted. Missing root: hook warns and skips.
- **Template-self detection:** if the current project's resolved path equals the template root's, the hook reports "no sync needed" and exits. This repo is safe from syncing onto itself.
- **Destructive sync of `docs/dev_framework/`** via `rsync -a --delete` — any local edits are silently overwritten. Adopters who need framework changes open a PR against the template repo, not against their local copy.
- **Destructive sync of `.claude/hooks/`** via the same pattern — hooks are part of the canonical machinery.
- **Idempotent init of `docs/framework_exceptions/`** from pristine stubs at `$TEMPLATE_ROOT/docs/dev_framework/_stubs/framework_exceptions/`. Only files that don't exist get created; existing files are preserved.
- **CLAUDE.md managed-block reconciliation.** The block between `<!-- BEGIN FRAMEWORK MANAGED -->` and `<!-- END FRAMEWORK MANAGED -->` in the local CLAUDE.md is replaced with the template's corresponding block. Content outside those markers is never touched.
- **Failure posture:** every step warns and continues on error. Framework sync is value-add, never a blocker for session start.

See [ADR-014](../architecture/adr-014-framework-sync-on-session-start.md) for rationale, alternatives considered, and acceptance criteria.

## Policy propagation

- **New sessions:** CLAUDE.md points here. Policy edits take effect at next session.
- **Current session:** user prompts "policy updated, reread" → session fetches.
- **Review cadence:** every phase boundary, check if the dispatch pattern is paying off — measure retry rates, escalation rates, time-per-W-item.

## When to suspend this policy

### Emergency bypass (production fire)

Peer-dispatch discipline is for normal operations. When production is on fire and the fix is small and obvious, the user can invoke emergency bypass with: **"skip review, just ship it."**

Under bypass:

1. **Orchestrator writes directly to `main`.** Skip dev entirely — dev-branch discipline is about orderly integration, not fire suppression. Commit goes straight to main; CI deploys to production. This is the single explicit exception to "Orchestrator doesn't write code."
2. **Commit with a `[bypass]` tag** in the first line, plus a one-line reason:
   ```
   [bypass] Fix null-deref on /api/login — prod error rate spike

   Reason: blocking all logins as of <timestamp>. Peer-dispatch review
   + dev-branch suspended per user request. Retrospective Reviewer
   within 24h. Back-merge to dev planned so dev doesn't drift behind
   main.
   ```
3. **Back-merge to dev immediately after bypass lands.** `git checkout dev && git merge main`. Without this, dev is missing the fix and the next W-item will either lose it or collide with it. Back-merge is mandatory, not optional.

   **Race note:** if an Executor is mid-flight when the bypass lands, let it complete. Its feature branch was based on pre-bypass dev, and its Reviewer ran against pre-bypass state. After the Executor's merge to dev, dev-CI (remote-hosted) or a quick local smoke (local-hosted) re-verifies the combined state. The auto-advance rule already gates the next W-item on dev-CI green. If dev-CI fails, treat it as a normal red-dev incident and fix on dev.
4. **Within 24h, Orchestrator spawns a retrospective Reviewer** on the bypass commit (use the Reviewer brief as-is, pass the commit SHA instead of a worktree path). This is the same peer-dispatch call as a normal Reviewer spawn — the emergency path uses the standard mechanism, not a bespoke one. Two outcomes:
   - **`ship` or `ship-with-concerns`** — log the Reviewer verdict as a follow-up commit or annotation. Discipline is restored.
   - **`block`** — the bypass introduced a new problem. Open a cleanup W-item in the active plan with the Reviewer's concerns as acceptance criteria, and run it through normal dev-branch flow.
5. **Log the bypass in `execution-incidents.md`.** Every bypass is an incident by definition — the process failed to be fast enough to handle a real need. Incidents feed policy improvement.

Bypass is explicit and ugly on purpose. The `[bypass]` tag makes it searchable. The 24h retrospective is a forcing function. If bypasses are happening more than a few times a quarter, the dispatch pattern isn't fitting the reality and needs policy review.

### Other suspensions

- **Editing this policy** — user approves directly.
- **🔍 spikes** — Orchestrator runs directly per §Mandatory overrides. Not a bypass — spikes are research, not code that ships.
- **Per-project deviations** — live in [`dev_framework_exceptions.md`](../framework_exceptions/dev_framework_exceptions.md), not inline here. If the project needs a sustained variation, record it there with a mechanism; don't fork this doc.
