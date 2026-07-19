# Context management

How to keep the doc surface manageable as the project evolves. Every doc added to the "required reading" list costs context window budget for every session. This doc defines the rules for keeping that cost under control.

## Project layout

The framework supports two directory structures. Understanding which one your project uses determines what `$CODE_ROOT` means in every role doc and brief. See [ADR-021](../architecture/adr-021-split-layout.md) for the decision record.

### Split layout (canonical)

Claude Code is invoked from a **parent directory** (`$PROJECT_DIR`) that holds only tracking material. The git repo lives as a subdirectory:

```
$PROJECT_DIR/           ← invoke claude from here
  CLAUDE.md
  .claude/
  docs/
  .env                  ← contains DEFAULT_CODE_SUBDIR + CLAUDE_TEMPLATE_ROOT
  <repo-slug>/          ← git root; name = GitHub repo slug
    src/
    .git/
```

`$CODE_ROOT = $PROJECT_DIR/$CODE_SUBDIR`

For **multi-repo projects** (N code repos under one parent), W-item files set an optional `target-repo: <subdir>` field in their YAML frontmatter (per [ADR-020](../architecture/adr-020-yaml-frontmatter-w-items.md)). `$CODE_ROOT = $PROJECT_DIR/$TARGET_REPO`, defaulting to `$PROJECT_DIR/$DEFAULT_CODE_SUBDIR` when `target-repo` is unset.

### Flat layout (legacy)

Project dir == git root. `$CODE_ROOT == $PROJECT_DIR`. The sync hook emits a migration NOTICE on every session start. See [`migration-guide-split-layout.md`](migration-guide-split-layout.md) for steps.

### `$PROJECT_DIR` git tracking is optional

Under split layout, the parent directory is **not required to be a git repo**. Two sanctioned modes ([ADR-021](../architecture/adr-021-split-layout.md)):

- **Untracked parent (default):** plain files for CLAUDE.md / docs / .claude. Plan-write visibility is via shared filesystem only — concurrent sessions see plan.md edits immediately, but the push-then-fail collision guard is unavailable. Sufficient for solo or single-machine multi-session work.
- **Tracked parent (optional):** `$PROJECT_DIR` is its own git repo with its own remote. Plan edits commit + push there. Full PLAN-WRITE DISCIPLINE concurrent-claim safety + durable plan history; right for team work or multi-machine setups.

Code-side git operations (`git push origin dev`, `git push origin main`) ALWAYS happen in `$CODE_ROOT` and are independent of whether the parent is tracked.

### How roles use $CODE_ROOT

| Role | Working tree | Notes |
|---|---|---|
| Strategist | `$PROJECT_DIR` | Reads `docs/`; never reads `$CODE_ROOT/src/` |
| Orchestrator | `$PROJECT_DIR` | Reads plan; worktrees created inside `$CODE_ROOT` |
| Developer (Default) | `$CODE_ROOT` | Coding happens here; plan lives at `$PROJECT_DIR/docs/` |
| Developer (Parallel) | `/tmp/worktrees/<project>/<branch>` | `<project>` = `basename $CODE_ROOT` |
| Executor | `/tmp/worktrees/<project>/<branch>` | Same slug convention |
| Template Developer | `$PROJECT_DIR` (template only) | Template has no `$CODE_ROOT` |

Git commands run from `$CODE_ROOT` (or a worktree rooted there). Plan and doc writes run from `$PROJECT_DIR`.

### .env variables

```bash
DEFAULT_CODE_SUBDIR=my-repo-slug    # primary code repo (required for split layout)
CLAUDE_TEMPLATE_ROOT=/path/to/...   # framework sync source (optional; sibling fallback exists)
```

---

## The problem

Agent sessions have finite context windows. Every doc loaded at session start competes with the code the session needs to reason about. As a project grows, the "required reading" grows with it — and eventually sessions start with so much context that they can't hold the actual work in memory.

This isn't hypothetical. Symptoms:
- Agents forget locked decisions mid-session because they were compacted.
- Hardcoded values drift because the session that bumped the canonical source didn't have room to `git grep` the dependents.
- Briefing templates go stale because the policy doc they live in is too long for anyone to review end-to-end.
- Sessions re-ask questions that are answered in docs they loaded but couldn't retain.

## Layered context loading

Not every agent needs every doc. Context loads in layers — each agent reads only what their role requires.

### Layer 0 — Always loaded (every session)

**Target: under 100 lines.**

- `CLAUDE.md` — project identity, key rules, pointers to deeper docs. This is the only doc every session reads in full.

### Layer 1 — Loaded by role

Each persistent instance reads its role doc at session start. No instance reads all of them.

| Instance | Reads at session start |
|----------|----------------------|
| **Orchestrator** | `docs/dev_framework/session-policy.md` + active execution plan index (`plan.md` under ADR-017 folder layout; the single plan file under pre-ADR-017 layout) |
| **Strategist** | `docs/dev_framework/strategist.md` + planning docs (plan, roadmap, future-directions). Does NOT load `docs/dev_framework/coding-standards.md` or project `src/` — code questions go through a Code Consultant subagent |
| **Designer** | `docs/dev_framework/designer.md` + existing UI components (read, not load) |
| **Developer** ([ADR-018](../architecture/adr-018-developer-role.md)) — both Default and Parallel invocations | `docs/dev_framework/developer.md` + `docs/dev_framework/coding-standards.md` + active plan's `plan.md`. **Loads `coding-standards.md` at session start** — unlike Orchestrator/Strategist, the Developer writes code, and standards must be available without a Layer 2 round-trip. W-item files load on demand. Both invocations share Layer 1; they diverge only at the working-directory + bootstrap-scan steps (Default in main checkout, Parallel in a worktree) |
| **Template Developer** | `docs/dev_framework/template-developer.md` + `docs/dev_framework/dev_framework.md`. Template-repo-only; specific role docs / ADRs / hook scripts load on demand (Layer 2). Does NOT load project `src/` (template has none) or `coding-standards.md` |

**Why code-level docs are not in Layer 1 for Orchestrator / Strategist.** Code-quality rules (TDD, no hardcoded values, fail loudly) are enforced at the subagent layer when those roles drive work, not by the Orchestrator or Strategist directly. Keeping `coding-standards.md` out of their Layer 1 preserves context for decision-making and plan-keeping. The Executor loads the doc to write correctly; the Reviewer loads it to enforce. **The Developer is an exception** — it writes code in the user loop and needs standards available for in-flight self-checks before the spawned Reviewer subagent runs the code-review gate. The role's net Layer 1 weight stays bounded because Developer doesn't load planning docs (Strategist's load) or `dev_framework.md` (Template Developer's load).

**Peer-dispatch and Orchestrator context.** Under peer dispatch (see `docs/dev_framework/session-policy.md` §"Dispatch flow"), the Orchestrator dispatches Executor, Reviewer, and QA as peers and reads their structured returns directly. Executors return code-only packages (SHA, diff summary, files touched, lessons — roughly 10 lines). Reviewer verdicts are larger (per-question answers, concerns with file:line citations — typically 30–60 lines on a clean ship, more on a block). QA returns per-criterion results with evidence. Over a long phase, the Orchestrator's context grows linearly with the number of W-items processed, bounded by the structured shape of the returns — not by the size of the diffs (the Orchestrator does not open diffs or source files directly). If the Orchestrator ever finds itself opening `src/` to "help" a stumped Executor, that's a policy violation — dispatch another Executor with a sharpened brief instead. See [ADR-013](../architecture/adr-013-peer-dispatch.md) for why the prior "sub-sub-agent" A2 model was retired.

### Layer 2 — Loaded on demand

Reference material pulled only when actively needed for a specific task.

- `docs/dev_framework/coding-standards.md` — loaded by Executor, Reviewer, and Integrator-QA subagents at spawn (Step 1 / Step 0 of their briefs)
- `docs/dev_framework/templates/*` — briefing templates, loaded when spawning a subagent. In particular: `reviewer-brief.md` for sequential-mode per-task review, `integrator-qa-brief.md` for batch-mode end-of-batch integration + review + test + fix (ADR-016), `qa-brief.md` for phase-exit and post-promotion live-environment passes.
- **W-item SOW files** (ADR-017 folder layout: `docs/execution-plans/<plan>/w-<id>.md`; pre-ADR-017: per-W-item section inline on the plan) — loaded ON DEMAND by the Orchestrator when filling a dispatch brief, by the Executor at STEP 1, by the Reviewer when reading acceptance, and by the Integrator-QA when scanning the batch. Never preloaded at session start; this is the load-bearing part of the folder structure — per-dispatch context is bounded by the W-item, not the phase.
- `docs/execution-plans/<plan>/claims.md` (folder layout) — loaded by the Orchestrator only during STEP 0 reconciliation of `held` items, and by the Strategist during claim triage. Filed by the Integrator-QA. Other roles do not read it.
- `docs/framework_exceptions/execution-incidents.md` — loaded when a process violation occurs
- `docs/archive/*` — closed phases, loaded only for historical reference
- `references/` — external repos, loaded when cross-referencing

### The rule

**Before adding a doc to Layer 0 or Layer 1, identify what it replaces or what gets demoted to Layer 2.** The total context budget for session start is fixed — additions require subtractions.

## Doc weight budget

Target context costs for session-start reading:

| Layer | Target | Enforced by |
|-------|--------|------------|
| Layer 0 (CLAUDE.md) | < 100 lines | Strategist reviews any CLAUDE.md edit for bloat |
| Layer 1 (role doc + standards) | < 200 lines per role | Strategist reviews at phase boundaries |
| Layer 1 (active execution plan index) | < 150 lines | Plans that exceed this should be split. Under the ADR-017 folder layout this is `plan.md` (the index) only; W-item SOW files (≤200 lines each) load on demand at Layer 2. |

**If the combined Layer 0 + Layer 1 for any role exceeds ~400 lines, something must be archived, condensed, or moved to Layer 2.**

## Phase archival

When a phase or execution plan is complete:

1. Move the plan to `docs/archive/`.
   - Folder layout (ADR-017): `mv docs/execution-plans/exec-phase-1 docs/archive/` — single move; the folder (`plan.md` + W-item files + `claims.md`) preserves intact.
   - Single-file layout: add `## Status: CLOSED` header to the plan, then `mv docs/execution-plans/exec-phase-1.md docs/archive/`.
2. Remove it from CLAUDE.md's reading order if it was the active-plan pointer.
3. The Strategist keeps a one-line summary in `docs/archive/README.md` for historical reference.

**Closed phases are never in the session-start reading list.** If a session needs historical context, it loads from the archive on demand.

### Archive structure

```
docs/archive/
  README.md              # one-line summaries of each archived plan
  exec-phase-1/          # closed plan, folder layout (ADR-017)
    plan.md
    w-a1.md
    ...
    claims.md
  exec-phase-2.md        # closed plan, single-file layout (pre-ADR-017)
  ...
```

## Doc compaction rules

Docs grow naturally. Apply these rules at phase boundaries:

### Session-policy.md

- **Briefing templates live in `docs/dev_framework/templates/`, not inline.** Session-policy points to them but doesn't contain them. This alone saves ~200 lines from session-start reading.
- **Phase-specific guidance goes in the execution plan, not session-policy.** Session-policy is for rules that apply across all phases.
- **Examples are good for templates, bad for policy.** A rule should be stated once, clearly. If it needs an example to be understood, the rule is unclear.

### CLAUDE.md

- **Status updates go in the active execution plan, not CLAUDE.md.** CLAUDE.md says "Status: Phase 3 active" and points to the plan. It doesn't list what's done in each sub-phase.
- **Repo layout tables are discoverable.** Don't enumerate every directory — agents can `ls` and `Read`. Only document layout that's surprising or non-obvious.
- **Locked decisions are worth the lines.** These prevent costly re-litigation. Keep them, but keep them terse — one line per decision, not a paragraph.

### Execution plans

- **Split large plans.** A plan with 20+ W-items should be split into focused sub-plans by stream or theme.
- **Don't accumulate historical context in active plans.** "Phase 2 is done, here's what happened" belongs in the archive, not at the top of the Phase 3 plan.

## Consistency checking

Values that exist in more than one place will drift. Two defenses:

### 1. Single source of truth (prevention)

Every value with a lifecycle should have exactly one canonical source:
- **Version strings** → `package.json`, `capabilities.yaml`, or a dedicated `versions.json`
- **Domain names** → env vars (`ROOT_DOMAIN`, `CONTROL_PLANE_URL`)
- **Infrastructure paths** → env vars (`CADDYFILE_PATH`, etc.)
- **Model versions** → a constants file or env var

Other files read from the canonical source. They never duplicate the value.

### 2. CI consistency checks (detection)

Run `scripts/check-consistency.sh` as a CI step. It catches:
- Bare IP addresses in source code
- Hardcoded domain names not behind env vars
- Version strings that don't match the canonical source
- `process.env.FOO || "fallback"` patterns (silent fallbacks)

See `scripts/check-consistency.sh` for the implementation.

## Consultant patterns (Doc + Code)

Mid-session lookups are the hidden context killer. A role hits a question and reads N full files to answer it — hundreds of lines consumed, most irrelevant to the question.

**Instead:** spawn a Consultant subagent. The Consultant reads in its own context window and returns a ~10-line answer with source citations and cross-reference checks.

### Doc Consultant

Used by any role to answer a documentation question. See `docs/dev_framework/templates/doc-consultant-brief.md`.

**When to use:**
- Cross-cutting questions that require reading multiple docs
- Checking locked decisions or constraints you don't have loaded
- Verifying a proposed approach doesn't contradict anything in the archive
- Any doc question requiring > 50 lines of docs you haven't already loaded

**When NOT to use:**
- The answer is in a doc you already loaded at session start (Layer 1)
- Simple lookups where you know the exact file and section
- Reading code (use the Code Consultant instead)

### Code Consultant

Primarily used by the **Strategist**, whose Layer 1 excludes project `src/`. See `docs/dev_framework/templates/code-consultant-brief.md`.

**When to use:**
- Verifying a code-level claim before approving a plan ("does function X exist? what does it do?")
- Checking whether a proposed architectural change would break an existing call site
- Any targeted code question the Strategist would otherwise load src/ to answer

**When NOT to use:**
- You need to MODIFY code (go through the Orchestrator → Executor path)
- The question is about docs (use Doc Consultant)
- You're the Orchestrator and already have the file loaded

**Future direction: code-aware MCP.** A longer-term goal is to back code queries with an MCP server that indexes the project (function signatures, call graph, file summaries) so the Strategist can query without spawning a subagent at all. For now, the Code Consultant is the bridge.

The round-trip cost (~10 seconds to spawn + answer) is always cheaper than loading 300 lines of docs or code that will sit in context for the rest of the session.

## When to revisit this doc

- At every phase boundary — is the session-start reading list still lean?
- When a session reports "I lost context on X" — X probably needs to move up a layer or be condensed.
- When adding a new doc — what does it replace?
