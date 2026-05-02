# Execution plans

This directory holds the work plans the Orchestrator executes against. Each plan is a self-contained **folder** covering one phase or initiative.

## Plan structure

A plan is a folder under `docs/execution-plans/` containing three artifact types:

```
docs/execution-plans/
  README.md                # this file — framework spec
  exec-<slug>/             # one folder per active or archived plan
    plan.md                # the index — runtime state surface
    w-a1.md                # W-item SOW (one file per W-item)
    w-a1.log.md            # Working log (lazy — created when Developer claims; ADR-018)
    w-a2.md
    claims.md              # Integration claims (open + resolved)
```

Naming:
- Folder: `exec-<slug>/` (e.g. `exec-phase-1/`).
- Index: always `plan.md`.
- W-item files: `w-<id-lowercase>.md` (e.g. `w-a1.md`, `w-b3.md`).
- Working log files: `w-<id-lowercase>.log.md` (e.g. `w-a1.log.md`) — lazy; created at the Developer's first append after claiming an item (Developer mode only; ADR-018).
- Claims file: always `claims.md` (created lazily — first claim filing creates it).

Introduced by [ADR-017](../architecture/adr-017-plan-folder-restructure.md). The folder shape separates runtime state (the index) from static SOW (W-item files) so that Status appears in exactly one place.

### Soft migration (plans that predate ADR-017)

Plans drafted before ADR-017 are single-file at `docs/execution-plans/<plan>.md` (e.g. `exec-phase-1.md`). These continue to work — the Orchestrator detects format in STEP 0 PRELUDE before any reconciliation runs:

- `docs/execution-plans/<plan>/plan.md` exists → **new format**. Read `plan.md` for ledger; read W-item files on demand; read `claims.md` for claims.
- `docs/execution-plans/<plan>.md` exists (and no folder of the same name) → **old format**. Read as before — single file with summary table + per-W-item sections + inline Integration claims (ADR-016 inline shape).

Both formats coexist during transition. New plans drafted after ADR-017 use the folder structure by default. Strategists migrate existing plans on a schedule that suits the project; the framework does not force migration.

## Archival

Closing a plan moves the entire folder to `docs/archive/`:

```
mv docs/execution-plans/exec-phase-1 docs/archive/
```

Single move; all artifacts preserved. The folder structure inside `docs/archive/` is identical to `docs/execution-plans/`. Single-file plans archived under the old format remain valid in `docs/archive/` as standalone files — soft migration applies to archives too.

After moving:
1. Add a one-line summary to `docs/archive/README.md`.
2. Remove from CLAUDE.md's active-plan pointer if it named this plan.

**Closed plans are never in the session-start reading list.** This is how context stays manageable — see `docs/dev_framework/context-management.md`.

## Size limits

- **Index (`plan.md`)** — under **150 lines / 15 W-items**. Larger initiatives split into focused sub-plans by stream or theme.
- **W-item file** — under **200 lines**. If a W-item file is growing past 200 lines, the work item itself is too big — split it into multiple W-items.
- **Working log file (`w-<id>.log.md`)** — **no limit**. Chronological growth is expected during active QA cycles; the discipline is "log signal, not noise" rather than a line cap. See §"Working log files" for what's worth logging.

These bounds keep each artifact readable within a session's context budget. Per-dispatch reads stay scoped to the W-item the agent is working on, not the full phase. The working log is exempt because it is read only by the Developer that owns the item — it is not on the Reviewer or Strategist surface.

## The index (`plan.md`)

The index is the runtime ledger. The top of the file orients a reader; the rest tracks state.

**Top of file (plan-level, set at draft, rarely revised):**

- An H1 plan title — a phrase a fresh reader understands without context, not the folder slug.
- An **Executive summary** section — Goal, Scope, Out of scope, Success criteria.

**Below that (runtime, mutable):**

- A summary table — one row per W-item.
- A pointer to `claims.md` if the plan has any claims.
- An optional Notes section — runtime event log, per W-item.

### Plan title and executive summary

The first two sections orient any agent or human opening the plan: what is this phase trying to accomplish, what's intentionally not in it, when does it close.

```markdown
# Phase 1: Auth and tenancy foundation

## Executive summary

**Mode:** orchestrator

**Goal:** Establish multi-tenant auth and per-tenant data isolation as the substrate every later feature depends on.

**Scope:**
- Email + OAuth login
- Tenant model with row-level isolation
- Session management

**Out of scope:**
- SSO / SAML (deferred to Phase 3)
- Tenant-level RBAC (Phase 2)

**Success criteria:**
- All W-items `done` and merged to `dev`
- Phase-exit QA against `{{sub}}.dev.{{website}}.com` green
- User authorizes promotion to `main`
```

The Strategist writes these at plan-draft time. They are not runtime ledger fields — phase pivots may revise them; routine W-item progress does not.

#### Mode field (Strategist recommendation, advisory not binding)

`Mode` is the Strategist's recommended execution style for the plan. Allowed values:

- **`orchestrator`** — drafted with Orchestrator dispatch in mind (ADR-013 sequential or ADR-016 batch via Executor / Reviewer / QA peer subagents).
- **`developer`** — drafted with Developer mode in mind (ADR-018 hands-on, user-invoked; user-mediated QA loop + spawned Reviewer subagent for the code-review gate).
- **absent** — no recommendation expressed.

**The field is advisory** ([ADR-018](../architecture/adr-018-developer-role.md) §"Mode field is advisory"). Either mode can claim any `pending` item on any plan. The Strategist's recommendation is a hint about expected execution style, not a lock — items lock into a mode at claim time via the Status path they take (Orchestrator-mode items go `in_progress → done`; Developer-mode items go `in_progress → code_review → done`). Per-item collision is naturally enforced by the mode-specific Status paths; per-plan collision was over-broad enforcement.

When a session is invoked against a plan whose explicit `Mode` recommendation differs from the session's role — e.g., Developer invoked against `Mode: orchestrator` — the bootstrap **prompts the user to confirm**: "this plan's recommended Mode is X; proceed in Y mode anyway?" Confirm → proceed. Cancel → user may want to re-invoke the recommended role. Absent `Mode` is treated as no recommendation, and the session proceeds without prompt.

Mixed-mode phases are allowed. Some items can be Orchestrator-driven, others Developer-driven, in the same plan. The cost is **historical asymmetry within the phase** — early items shipped via Orchestrator have no Implementation log; later items shipped via Developer do. That's tolerable, not load-bearing.

When claiming an item, record the claim in the plan's Notes section — `"W-A1 — claimed by Developer YYYY-MM-DD"` — so a fresh session opening the plan has unambiguous attribution for in-flight items even before any Status flip beyond `in_progress`.

### Summary table

```markdown
| W-id | Title | Effort | Markers | Status | Branch | Blocked by |
|------|-------|--------|---------|--------|--------|------------|
| W-A1 | [Auth alignment](w-a1.md) | S | ⚠️ | done | w-a1/auth | — |
| W-A2 | [Task claim](w-a2.md) | M | ⚠️ | held | w-a2/task-claim | W-A1 |
| W-A3 | [Webhook retry](w-a3.md) | S | — | pending | — | W-A2 |
| W-B1 | [Account profile](w-b1.md) | S | — | pending | — | — |
```

The Title cell links to the W-item file. Dispatch-relevant fields (Effort, Markers, Status, Branch, Blocked by) sit on the index only. Branch is populated when Status becomes `in_progress`. `Blocked by` lists the W-ids that must reach `done` or `shipped` before this item is eligible to claim — Strategist authors at draft time, `—` when none. The dependency graph (used for critical-path ordering and for Parallel Developer's non-competing scan) is derived from this column on the index, not from a field on the W-item file.

### Claims pointer

When the plan has any claims, the index links to `claims.md`:

```markdown
**Integration claims:** [`claims.md`](claims.md) — open: 2, resolved: 5
```

The pointer is added by whichever agent files the first claim (Integrator-QA) and updated by the Strategist as dispositions move claims between Open and Resolved.

### Notes (optional)

Below the summary table, the index may include a free-form Notes section for runtime events that don't fit a table cell:

```markdown
## Notes

### W-A2 — 2026-04-25
Stumped on auth refresh: token rotation contract unclear. User clarified rotation window; sharpened brief dispatched.
```

Notes capture stumped reasons + resolution, ship-with-concerns text, lessons-learned highlights worth keeping past the merge commit. One paragraph per event max — not a diary.

### Index fields

| Field | Purpose | Owner |
|-------|---------|-------|
| **W-id** | Unique within the plan. Format: `W-<stream><number>` (e.g. W-A1, W-B3). **Stream letters group items by code-path area.** Items in the same stream MAY share files; items in different streams are assumed non-competing for parallel claim (Parallel Developer's non-competing scan relies on this). Strategists name items consistently with the convention. The convention is enforced by Strategist discipline, not mechanically — cross-stream shared-infra exceptions (rare; e.g., two items in different streams both bumping `package.json`) surface as merge conflicts at integration, not silent corruption; the user catches them in the loop. | Strategist |
| **Title** | Short title — cell links to the W-item file. | Strategist |
| **Effort** | XS / S / M / L / XL — drives the tiered execution pattern in `session-policy.md`. | Strategist |
| **Markers** | ⚠️ architectural/irreversible (forces QA, bumps retry cap to 3). 🔍 spike/research (Orchestrator runs directly, 2h max); also applies to branch-topology work that cannot run inside a worktree. Combine with ⚠️ when destructive. 🧪 requires live QA regardless of tier. | Strategist |
| **Status** | One of `pending` / `in_progress` / `held` / `blocked` / `done` / `shipped`. Multi-writer — see transition table below. | Orchestrator (most), Integrator-QA (`in_progress → held`), Strategist (`held → in_progress / blocked`) |
| **Branch** | `w-<id>/<slug>` — populated when Status becomes `in_progress`. | Orchestrator |
| **Blocked by** | Comma-separated W-ids that must reach `done` or `shipped` before this item is eligible to claim. `—` if none. Forms the dependency graph; both critical-path ordering and Parallel Developer's non-competing scan read from this column. | Strategist |

## W-item files

Each W-item is its own file in the plan folder, `w-<id-lowercase>.md`. The H1 is just the W-id (e.g. `# W-A1`). Title lives on the index table only — no duplication.

Each W-item file has at most 200 lines, a YAML frontmatter block at the top, and prose sections below.

```markdown
---
parallel-safe: false
touches:
  - src/foo.ts
  - src/bar.ts
references:
  - path: src/legacy/foo.py
    lines: "120-280"
    purpose: auth middleware pattern
---

# W-A1

## High level

**What:** One sentence describing what this item produces.

**Acceptance criteria:**
- [ ] Criterion 1
- [ ] Criterion 2

## Contingencies

Pre-planned fallbacks, known edge cases, "if X happens, do Y" guidance. Optional — write `(none)` when nothing applies.

## Implementation log

Appended by the Developer at `code_review → done` (Developer mode only in v1; ADR-018). Absent until that flip — the section header does not appear on a W-item file at draft. The Developer drafts it by reading the W-item's working log file (see §"Working log files" below) alongside the diff — the Implementation log is the curated retrospective; the working log is the chronological record.

**Approach:** One paragraph on how the work was actually done.

**Key decisions:**
- Decision 1 — why
- Decision 2 — why

**Pivots:**
- What was tried first, why it didn't work, what replaced it (or `none`).

**Surprises:**
- Anything the work uncovered that future readers should know (or `none`).

**Followups / loose ends:**
- Anything intentionally deferred (or `none`).
```

When `parallel-safe: true`, the frontmatter MUST also include a `parallel-safe-considered:` list naming the shared surfaces the Strategist evaluated (see §"Parallel-safe field" below). Omit the field entirely when `parallel-safe: false`.

Introduced by [ADR-020](../architecture/adr-020-yaml-frontmatter-w-items.md). The frontmatter is the structural-metadata surface; the body is prose. Tools that consume the metadata (the Reviewer's `scripts/check-touches.sh` mechanical scope check, the Orchestrator's batch-mode collision evaluation) read frontmatter without loading the full body. Pre-ADR-020 plans use the prior `## Execution notes` prose shape — both formats coexist during transition.

**No Status field on the W-item file.** Status lives only on the index. The W-item file is the static SOW; the index is the runtime ledger. This is the single-source rule introduced by ADR-017 — there is no second place for Status to drift to. ADR-020 preserves this: the frontmatter carries structural metadata only (`parallel-safe`, `touches`, `references`), never `status`.

**What is NOT in the W-item file (frontmatter or body) and why:**

- `status` — index-only, per ADR-017's drift-bait elimination.
- `effort` / `markers` — index summary-table columns; the Orchestrator reads them at-a-glance there.
- `blocked-by` — index `Blocked by` column, per ADR-017 v1.1 (single source for dependency data).
- `id` / `title` — H1, filename, and the index summary table all carry these; frontmatter duplication earns nothing.

The Implementation log is the one section that gets appended after draft, at the `code_review → done` flip. It is append-only (not mutated after merge) and therefore does not reintroduce drift bait — see ADR-018.

### W-item file fields

| Field | Location | Purpose |
|-------|----------|---------|
| **parallel-safe** | Frontmatter | `true` = eligible for **Orchestrator batch-mode dispatch** (ADR-016). `false` = per-task peer chain (ADR-013). Owned by the Strategist; set at plan time. Default: `false`. **Does not gate Parallel Developer** (ADR-018) — Parallel Dev relies on the stream-letter convention on the index instead. See §"Parallel-safe field" below. |
| **parallel-safe-considered** | Frontmatter | Required when `parallel-safe: true`; list of shared-surface factors the Strategist evaluated (e.g., `package.json bumps`, `shared route registry`, `migration ordering`, `test fixtures`, `refactor-of-a-callee`). Forces the judgment to be recorded rather than mechanized. Omit the field when `parallel-safe: false`. |
| **touches** | Frontmatter | List of file paths the item will modify. Executor uses this as the scope boundary; Reviewer runs `scripts/check-touches.sh` against this list to mechanically verify the diff stayed in scope (ADR-020). |
| **references** | Frontmatter | Optional list of read-only orientation entries. Each: `path` (required), `lines` (optional, e.g. `"120-280"`), `purpose` (optional, short string). Intended for port / migration / refactor work where pre-existing structure must be understood. Modifying a References file is scope creep. |
| **What** | Body §High level | One sentence — what artifact does this item produce? |
| **Acceptance** | Body §High level | Checkboxes. All must be green before the item is `done`. |
| **Contingencies** | Body §Contingencies | Pre-planned fallbacks and edge cases. Strategist-authored at draft time. |
| **Implementation log** | Body §Implementation log (post-completion) | Appended by the Developer at `code_review → done` flip. Captures approach, key decisions, pivots, surprises, followups. Distilled from the W-item's working log file (see §"Working log files") alongside the diff — the curated retrospective; the working log is the chronological record. Developer mode only in v1 (ADR-018). |

## Working log files

Each Developer-claimed W-item gets its own working log file in the plan folder, `w-<id-lowercase>.log.md`. Freeform chronological scratchpad the Developer appends to throughout `in_progress` (build + user-mediated QA). Survives `/compact` so a post-compact session can re-establish working context cheaply by reading the log instead of re-deriving it from session memory that was just summarized away.

Introduced by [ADR-018](../architecture/adr-018-developer-role.md) Revision v3.3. Developer mode only — Orchestrator-mode dispatch does not produce working logs (Executor subagents are stateless and per-task; their working memory dies with the dispatch).

### Lifecycle

- **Lazy creation.** Created at the `pending → in_progress` claim — Developer's first append creates the file. W-items that never reach `in_progress` have no log file.
- **Appended throughout `in_progress`.** Build decisions, dead ends, fixes attempted, user-reported QA issues, retest outcomes. Chronological. The QA back-and-forth (change-this-not-that, scope creep, refinement) lives here verbatim.
- **Distilled at `code_review → done`.** Developer reads the working log alongside the diff and writes the Implementation log on the W-item file (structured retrospective: approach, key decisions, pivots, surprises, postponed concerns, followups). The working log file itself **persists** in the plan folder; it is not deleted. The Implementation log is the curated retrospective; the working log is the honest chronological record.
- **Archives with the plan.** When the plan folder moves to `docs/archive/`, the log files move with it.

### Format

Freeform markdown. Suggested layout — timestamped session blocks with short prose underneath:

```markdown
# W-A1 working log

## 2026-05-02 14:30 — claimed, scoping
Decided to use FooStore pattern instead of subclassing BarStore. Reason:
matches the rest of the auth surface; subclass would be one-off.

## 2026-05-02 15:10 — first attempt failed
Tried passing the session through as a closure; ran into the test harness'
`expectFn` race. Pivot: pull session out of the request context at handler
entry instead.

## 2026-05-02 16:45 — ready for QA
Feature builds. `npm test` green. User to take it.

## 2026-05-02 17:05 — QA round 1
User: "header doesn't show on /settings". Fixed — middleware was scoped to
/auth only. Retest passing.

## 2026-05-02 17:30 — QA round 2 (scope creep, accepted)
User wants the header to also collapse on mobile. Adding to scope per user
direction; not a separate W-item.

## 2026-05-02 18:00 — QA complete
User confirms everything works. /compact now, then code review.
```

The timestamp + short prose pattern is suggested, not required. The discipline that matters: **append something at every meaningful state change** — at claim, at design decisions, at dead ends, at "ready for QA," at each QA round, at QA complete. The agent's working memory after `/compact` is whatever it can re-read here.

### What's worth logging

- Decisions and the reason (why this library, why this approach).
- Dead ends — what didn't work and why.
- Fixes applied during the QA loop, with a one-line note on what triggered each fix.
- Retest outcomes (user-confirmed pass / new issue surfaced).
- Phase-transition markers ("ready for QA," "QA complete," "Reviewer block — re-coding") — these are the anchors the Developer reads to infer phase after `/compact`.
- Anything the Developer would want to recover after `/compact` — context that would be expensive to re-derive.

### What's NOT worth logging

- Verbose narration of every file read or test run.
- Tool-call output already visible in the diff.
- Routine work (`wrote test, made it pass`) without a decision attached.

### Size

**No hard size limit.** The W-item file's 200-line limit (see §"Size limits") does not apply to log files — chronological growth is expected. Long QA cycles produce long logs; that's the point. Even so, the discipline is "log signal, not noise" — verbose narration bloats the file without earning context.

### Who reads it

- The Developer that owns the W-item — primary user.
- A fresh Developer session that picks up an interrupted item — reads the log to recover state.
- Strategist on triage if a claim is filed mid-work and the log clarifies why.
- The Reviewer subagent does **not** read it — Reviewer reads the diff + W-item file + `coding-standards.md` only (per `reviewer-brief.md`). The log is Developer working memory, not part of the code-review surface.

## Parallel-safe field

The `Parallel-safe` field gates batch-mode dispatch (ADR-016). When `true`, the Orchestrator may dispatch the item concurrently with other `Parallel-safe: true` items in a batch of up to ~3, with one Integrator-QA (Opus 1M) call replacing the per-task Reviewer and per-W-item (pre-merge) QA. When `false` (or unset), the item flows through the per-task peer chain from ADR-013: Executor → Reviewer → optional QA → merge.

**Judgment rule (Strategist-owned).** `Parallel-safe: true` requires the W-item to be independent of every other W-item in the same plan at the level of **every shared runtime and build surface**, not just `Touches`. Two items with disjoint `Touches` can still conflict on:

- `package.json` / lockfile changes
- Shared configuration (env schema, route registry, feature flag registry)
- Database migration ordering
- Schema changes that other items consume
- Refactor of a callee that other items call
- Shared test fixtures or test-DB seed
- Dev-environment setup (dev-server port, docker-compose service names)

The framework does NOT auto-derive `parallel-safe` from `touches`. The Strategist considers the shared surfaces above and decides explicitly. Whenever `parallel-safe: true`, the W-item file MUST include a `parallel-safe-considered:` list in frontmatter naming what was evaluated — this forces the judgment to be recorded rather than mechanized.

**Default when unset:** `false`. Adopter plans that predate ADR-016 (no parallel-safe data on any W-item) continue to flow through the per-task peer chain. Strategists backfill the field when they decide to opt items into batch mode. No plan breaks at sync time. Pre-ADR-020 plans carry parallel-safe as a prose `**Parallel-safe:**` line under `## Execution notes`; both shapes are read by the framework during the soft-migration window.

**Asymmetry: this field gates Orchestrator batch mode only.** Parallel Developer (Developer-mode parallel; ADR-018) does NOT use `Parallel-safe`. Its non-competing scan reads the index alone — stream-letter clash check + `Blocked by` check — and trusts the stream-letter convention to imply collision risk (same letter = same code-path area = likely shares files). The asymmetry is intentional: Orchestrator batch mode is autonomous and benefits from explicit Strategist curation of shared-infra collisions across `Touches`-disjoint items; Parallel Developer is user-supervised, so the rare cross-stream shared-infra collision (lockfile bump, schema bump, registry edit) surfaces as a merge conflict the user catches in the loop.

## Status state machine

Seven states: `pending`, `in_progress`, `code_review`, `held`, `blocked`, `done`, `shipped`.

The state machine has two mode-specific lifecycles. Orchestrator mode (ADR-013 sequential, ADR-016 batch) and Developer mode (ADR-018) share `pending`, `held`, `blocked`, `done`, `shipped` and the `held`/`blocked` recovery transitions. The middle of the lifecycle differs:

- **Orchestrator mode** runs `in_progress → done` — Reviewer + QA gates run as peer subagents.
- **Developer mode** runs `in_progress → code_review → done` — user mediates QA inside `in_progress` (no separate `qa` state); a spawned Reviewer subagent (same brief as Orch sequential mode) covers the `code_review` step.

A given W-item runs through one mode's lifecycle at a time. The plan-level `Mode` field is the Strategist's recommendation (advisory) — collision-freedom is enforced per W-item by the mode-specific Status paths (see §"Mode signaling" below).

### Orchestrator-mode lifecycle

```
      ┌─────────┐
      │ pending │ ← default for newly-added W-items
      └────┬────┘
           │ Orchestrator dispatches Executor
           ▼
    ┌─────────────┐  Integrator-QA files claim    ┌──────┐
    │ in_progress │ ────────────────────────────▶ │ held │
    └──┬──────────┘                               └──┬───┘
       │  ▲                                          │
       │  │                                          │ Strategist
       │  │ Orchestrator                             │ disposes
       │  │ re-dispatches                            │
       │  │                                          │ approve/modify
       │  │ ┌─────────┐                              ├─────────────▶ in_progress
       │  └─│ blocked │ ◀─────────reject─────────────┤
       │    └─────────┘                              │ reject
       │      ▲                                      └─────────────▶ blocked
       │      │ Executor stumped /
       │      │ Integrator integration failure
       │
       │ Executor pass + Orchestrator merge
       ▼
    ┌──────┐
    │ done │
    └───┬──┘
        │ Phase exit QA + user authorize + Orchestrator promotes
        ▼
   ┌─────────┐
   │ shipped │ ← terminal
   └─────────┘
```

### Developer-mode lifecycle

```
   pending ──▶ in_progress ──▶ code_review ──▶ done ──▶ shipped
                  │     ▲          │    ▲                  ▲
                  │     │          │    │                  │
                  │     │          │    │ Reviewer block,  │ phase exit
                  │     │          │    │ user chooses     │ + user authorize
                  │     │          │    │ Resolve          │ + Developer promotes
                  │     │          │    │
                  │     │          │    └── (manual; not auto-loop;
                  │     │          │        Postpone bypasses this and
                  │     │          │        proceeds to done with concerns
                  │     │          │        logged)
                  │     │          │
                  │     │          │ Reviewer Ship verdict (or Postpone) →
                  │     │          │   merge feature → dev (fast-forward)
                  │     │          │   + Implementation log on W-item file
                  │     │          │   + cleanup (worktree + branches)
                  │     │          ▼
                  │     │       (continue to done)
                  │     │
                  │     │ user confirms feature works → /compact (recommended)
                  │     │ + "ready for review" commit + sync feature with
                  │     │ origin/dev (rebase) + spawn Reviewer subagent
                  │     │
                  │     └──── user mediates QA loop inside in_progress
                  │            (Developer codes, user tests, iterate)
                  │
                  ├─▶ held (Developer files claim; rare; Strategist disposes
                  │         as in Orchestrator mode)
                  │
                  └─▶ blocked (unblockable; user can't move it forward)
```

Confirm + claim: the Developer asks "ready to start coding W-X?" before the `pending → in_progress` flip. At the `in_progress → code_review` flip (after user-mediated QA confirms the feature works), the Developer optionally `/compact`s, commits a "ready for review" marker, **rebases the feature on `origin/dev`** (so the Reviewer reads accurate context and the eventual merge is a fast-forward), and spawns a Reviewer subagent. The verdict drives one of three outcomes — Ship, Resolve, or Postpone — described in §"`code_review` semantics" below.

### Mode signaling (per item, not per phase)

ADR-018 originally proposed per-phase mode-exclusivity (the user picks at draft; both bootstraps refuse-on-mismatch). That rule was over-strict — it locked Developer out of plans the Strategist had drafted with Orchestrator in mind, even when no W-item had been claimed. The actual collision risk is per-W-item, not per-plan, and is naturally enforced by mode-specific Status transitions: Orchestrator's `in_progress → done` and Developer's `in_progress → code_review → done` take different paths from `in_progress` and don't conflict.

Under the v2 model (current): the plan-level `Mode` field is the Strategist's recommendation (see §"Mode field" above). Either mode can claim any `pending` item. Items lock into a mode at claim time via the Status path they take. Cross-mode collision on a single in-flight item is prevented by PLAN-WRITE DISCIPLINE (read-fresh + commit) at claim time and by the mode-specific Status paths thereafter.

**A per-W-item `Mode` override field is not needed.** Once items lock into a mode at claim time via Status path, an explicit per-item field would be redundant. Claim attribution lives in the plan's Notes section (`"W-A1 — claimed by Developer YYYY-MM-DD"`) for at-a-glance disambiguation of in-flight items.

### Transition table

PLAN-WRITE DISCIPLINE applies to every transition: the writing agent reads the index file fresh, edits it, commits the edit alongside the trigger event (atomically — one commit, all touched files together), and verifies the push. Each writer's role doc / brief inlines the discipline at its write site.

| From → To | Mode | Trigger | Writer | Atomic with |
|---|---|---|---|---|
| `pending` → `in_progress` | Orch | Orchestrator about to spawn Executor | Orchestrator | Dispatch event (Status flip + Branch populate; commit before spawning) |
| `pending` → `in_progress` | Dev | Developer claims item after user confirms "ready to start coding" | Developer | Branch creation + anchor message; one plan-write commit |
| `in_progress` → `done` | Orch | Executor pass + Orchestrator merges feature → `dev` | Orchestrator | The merge commit |
| `in_progress` → `code_review` | Dev | User confirms feature works; Developer optionally `/compact`s, commits a "ready for review" marker, syncs feature with origin/dev (rebase), spawns Reviewer subagent on the synced state | Developer | "Ready for review" commit on the W-item branch + Status flip in one PLAN-WRITE commit. Sync + Reviewer spawn follow as separate operations |
| `code_review` → `done` | Dev | Reviewer ship verdict (or Postpone with logged concerns); merge feature → `dev` (fast-forward, since pre-review sync rebased onto dev's tip) | Developer | Merge commit + Implementation log on W-item file (with `**Postponed concerns:**` line if Postpone) |
| `code_review` → `in_progress` | Dev | Reviewer block + concerns; user chooses Resolve | Developer | Re-dispatch (user-mediated, NOT auto-loop). Re-sync + re-spawn Reviewer after re-confirming via user QA loop |
| `in_progress` → `blocked` | Orch | Executor stumped, or Integrator-QA integration failure (confidence <80%) | Orchestrator | Stumped notice (Status flip + index Notes line) |
| `in_progress` → `blocked` | Dev | Unblockable issue; user can't move work forward | Developer | Stumped notice (Status flip + index Notes line) |
| `in_progress` → `held` | Orch (batch) | Integrator-QA files a claim naming the W-item | Integrator-QA | Claim filing — one commit writes `claims.md` (IC-NNN under Open) + `plan.md` (Status flip) |
| `in_progress` → `held` | Dev | Developer files a claim mid-work (rare; ≥80% confidence acceptance ambiguity) | Developer | Claim filing — same shape as Integrator-QA |
| `held` → `in_progress` | Both | Strategist disposes claim `approve` / `modify` | Strategist | Disposition — one commit moves IC-NNN to Resolved + flips Status |
| `held` → `blocked` | Both | Strategist disposes claim `reject` and W-item is un-actionable | Strategist | Same as above |
| `blocked` → `in_progress` | Orch | Orchestrator re-dispatches with a sharpened brief | Orchestrator | Re-dispatch (Status flip + updated Branch if changed) |
| `done` → `shipped` | Both | Phase-exit QA passes + user authorizes + active mode promotes `dev → main` | Orchestrator (Orch-driven phase) or Developer (Dev-driven phase) | The promotion merge |

The plan is a ledger — stale entries mean the ledger is lying and a future session will dispatch duplicate work or skip done work. PLAN-WRITE DISCIPLINE is the mechanism that keeps the ledger and git in lockstep across all four writing agents.

### `held` semantics

A W-item enters `held` when an open Integration claim names it. Filer depends on mode:

- **Orchestrator (batch) mode:** Integrator-QA files when an integration fix would step outside acceptance (ADR-016).
- **Developer mode:** the Developer files mid-work when it identifies acceptance ambiguity at ≥80% confidence (ADR-018, rare path; most ambiguity resolves with the user in real-time).

In both cases: held items have a branch that exists, the branch is preserved during the hold (no Executor or Developer activity), held items do NOT merge to `dev` until the claim is disposed. Strategist disposes per the standard claim flow (`held → in_progress / blocked`).

The `held` state replaces the convention (used in earlier ADR-016 drafts) of leaving claim-blocked items at `in_progress` with a Notes line — that approach left the Status field misleading.

### `code_review` semantics

A W-item enters `code_review` only in Developer mode, when the user has confirmed the feature works and the Developer is dispatching the code-review gate. The branch carries the implementation; a "ready for review" marker has been committed; the Developer has **synced the feature with `origin/dev` via rebase** (so the Reviewer reads accurate codebase context and the eventual merge is a fast-forward); then spawned a Reviewer subagent (`docs/dev_framework/templates/reviewer-brief.md`) on the synced state. The Reviewer is a fresh process — it sees the W-item brief + diff against `origin/dev`, not the Developer's coding journey.

Three outcomes, all user-mediated:

- **Ship.** Reviewer returns no blocking concerns. Developer merges feature → `dev` (fast-forward), writes Implementation log on the W-item file, flips `code_review → done` in one commit. Cleanup follows (worktree + branch deletion).
- **Resolve.** Reviewer returns concerns the user wants fixed before merging. Status `code_review → in_progress`. Re-code, re-confirm via user QA, re-sync (in case dev advanced), re-spawn Reviewer.
- **Postpone.** Reviewer returns concerns the user accepts as a known limitation. Concerns logged in the Implementation log under `**Postponed concerns:**` + plan Notes line. Merge proceeds as Ship; flip to `done`. Open follow-up W-item if the postponed concern is anything beyond a true known-limitation.

Resolve vs Postpone is a user judgment: Resolve when the concern would cause user-visible breakage or violates a load-bearing standard; Postpone when the concern is real but not blocking shipment for this phase.

### Reconciliation (on session start)

A fresh Orchestrator session MUST reconcile the plan ledger against git reality before dispatching anything. See `orchestrator-bootstrap.md` STEP 0. Check under ADR-017: every `held` W-item must have a corresponding open IC-NNN entry in `claims.md`. A `held` item with no open claim is a ledger lie — surface to the user, do not auto-fix.

A fresh Developer session reconciles similarly per its bootstrap (`developer.md`). The state IS the memory:

- Item at `code_review` → Reviewer subagent didn't return (session reset before verdict, or interrupted); propose re-spawning the Reviewer brief on the same branch + SHA before any new work. Reviewer is stateless and idempotent.
- Item at `in_progress` after a context reset → ambiguous (mid-coding, mid-QA-loop, or pre-`/compact`). Read the W-item's working log file (`w-<id>.log.md`); the latest timestamped header names the most recent phase-transition marker (`ready for QA`, `QA complete`, etc.), recovering phase + working context cheaply. If still unclear, confirm with user.
- Item at `held` → awaiting Strategist disposition; skip.
- Otherwise → propose top `pending` item by critical path (using the index's `Blocked by` column to derive the dependency graph).

Summary-table-vs-W-item-section drift is structurally impossible under the folder layout (Status appears once on the index). The pre-ADR-017 STEP 0 check for that drift retires.

## Integration claims

**Filed by the Integrator-QA in batch mode (ADR-016), or by the Developer in Developer mode (ADR-018), when a fix would require stepping outside a W-item's acceptance criteria.** The filer does NOT change scope unilaterally. When confidence in a proposed scope change is ≥80%, the filer adds an integration claim to `claims.md` and flips the named W-item(s) to `held`. The Strategist triages with the user. When confidence is <80%, the filer surfaces to the user immediately as a feature failure — no claim is filed; the W-item moves to `blocked` instead.

In Developer mode the rare-path filing is described in [`developer.md`](../dev_framework/developer.md) §"Claim-filing (rare path)" — most acceptance ambiguity in Developer mode resolves with the user in real-time, but a claim is appropriate when the change has cross-W-item implications or the user isn't immediately available to confirm.

### Where claims live

Integration claims live in `claims.md` inside the plan folder. Two sections — Open and Resolved.

```markdown
# Integration claims — exec-phase-1

## Open

(Open claims — held W-items do not merge until the Strategist + user dispose.)

### IC-NNN — YYYY-MM-DD — {{W-id(s)}} — {{short title}}

**Filed by:** Integrator-QA (batch <ids>) | Developer (Dev-mode session, ADR-018)
**Confidence:** <pct>
**Proposed scope change:** <what Integrator wants to do but won't do unilaterally>
**Why:** <what forced the proposal — test failing for X, acceptance ambiguous on Y>
**Blocks:** <W-item ids whose merge is held pending resolution>

## Resolved

### IC-NNN — YYYY-MM-DD → resolved YYYY-MM-DD — {{title}}

**Disposition:** approve | reject | modify
**Resolution:** <one-line summary of what the Strategist + user decided>
**Follow-up:** <W-item id if the resolution opened a new item, or "none">
```

### Numbering

Sequential across the plan, `IC-001`, `IC-002`, etc. Numbers persist across open → resolved (the entry moves between sections; the number stays). The Integrator-QA assigns the next unused number when filing.

### Blocking semantics

An open claim blocks **only the named W-items** from merging — those items are at `held` Status. Other W-items in the same batch that aren't named proceed through merge normally. Other batches, sequential work, and Orchestrator forward progress are not blocked. If the Strategist's resolution modifies acceptance or opens a follow-up W-item, the held items either re-enter dispatch (with the updated acceptance, transitioning to `in_progress`) or move to `blocked` pending the follow-up — the Strategist records which in the claim's Resolution line.

### Triage

The Strategist reviews open claims at phase boundaries and on demand, in the same triage pass as `process-exceptions.md`. Dispositions:

- **approve** — Integrator's proposed change is sound. Strategist updates the W-item's acceptance / SOW (in the W-item file), moves the claim to Resolved, flips index Status `held → in_progress`. Integrator-QA re-runs its fix pass on the affected items.
- **reject** — Do not make the change. Strategist moves the claim to Resolved, flips index Status `held → blocked`. The Integrator-QA surfaces a revised plan (or a stumped return) instead.
- **modify** — Strategist revises the proposal in the Resolution line, moves claim to Resolved, flips index Status `held → in_progress`. Integrator re-runs against the revised acceptance.

Every disposition is recorded in the Resolved section. Never delete — the history is the value.

### Atomicity

Three writes touch claim state. Each is one commit:

- **Filing** (Integrator-QA) — `claims.md` (new IC-NNN under Open) AND `plan.md` (Status `in_progress → held` for named W-items). One commit, both files.
- **Disposition** (Strategist) — `claims.md` (move IC-NNN from Open to Resolved with Disposition + Resolution) AND `plan.md` (Status `held → in_progress` or `held → blocked` for named W-items). One commit, both files. If the disposition also revises acceptance, the matching W-item file edit is part of the same commit.
- **No partial states.** A `held` Status with no open claim, or an open claim with no `held` Status, is a ledger lie — see Reconciliation above.

### When a claim is NOT appropriate

- **Ordinary bugs within acceptance.** The Integrator fixes those inline; no claim.
- **Standards violations** (hardcoded values, missing tests, silent fallbacks) within acceptance. Same — the Integrator writes a fix commit per `coding-standards.md`.
- **Confidence <80%.** Surface to the user directly; W-item goes to `blocked`, not `held`. Don't hand the user a low-confidence proposal to chew on.
- **Issues the Integrator caught in its first-pass high-profile scan.** Those are surfaced immediately as feature integration failures, not claims — the distinction is that the first-pass scan catches problems that should halt the batch before deep work, whereas claims emerge from deep work that revealed an acceptance ambiguity.
