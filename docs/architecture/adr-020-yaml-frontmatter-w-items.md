# ADR-020: YAML frontmatter on W-item files

**Status:** accepted
**Date:** 2026-05-02
**Deciders:** David (template author), Template Developer session

## Context

W-item files under [ADR-017](adr-017-plan-folder-restructure.md) carry their structural metadata as labeled prose lines under an "Execution notes" section:

```markdown
## Execution notes

**Parallel-safe:** false
**Touches:** `src/foo.ts`, `src/bar.ts`
**References:** `src/legacy/foo.py:120-280` (auth middleware pattern)
```

Three problems with this shape:

1. **No mechanical scope check.** The Reviewer's job (per [`reviewer-brief.md`](../dev_framework/templates/reviewer-brief.md) question 6) includes "did the Executor modify any file outside the Touches list?" The brief instructs the Reviewer to read and infer — there is no script that mechanically compares `git diff --name-only` against the Touches list. Scope creep that's only mentioned by an Executor itself in the PASS shape (per [`executor-brief.md`](../dev_framework/templates/executor-brief.md)) is the only mechanical signal; an Executor that touches an extra file and forgets to flag it gets through.
2. **The Orchestrator's batch-mode dispatch (ADR-016) reads multiple W-item files to evaluate `Parallel-safe: true` candidates** for collision risk. Each candidate's full prose body loads into context just to extract one boolean and one file list. The fields the dispatcher actually consumes are a small fraction of what gets read.
3. **The Parallel Developer's non-competing scan (ADR-018)** does not currently read W-item bodies — it relies on the index's `Blocked by` column and the stream-letter convention. But shared-infra collisions across streams (lockfile, route registry, schema migration) are exactly the cases the stream-letter convention misses. A mechanically-readable `touches` would let Parallel Dev sharpen the scan when the user asks it to.

The common thread: structural metadata is data, but it lives as prose. Tools that should consume it can't.

## Decision

Add YAML frontmatter to W-item files. Move structural fields out of the "Execution notes" prose section and into the frontmatter block at the top of the file. The body keeps prose: `High level` (What + Acceptance criteria), `Contingencies`, `Implementation log` (post-completion).

### W-item file shape under ADR-020

```markdown
---
parallel-safe: false
touches:
  - src/auth/login.ts
  - src/auth/session.ts
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

Pre-planned fallbacks, known edge cases. Optional — write `(none)` when nothing applies.

## Implementation log

(populated at code_review → done)
```

The "Execution notes" section header retires — every field that lived under it moves to frontmatter.

### Frontmatter schema

| Field | Type | Required | Notes |
|---|---|---|---|
| `parallel-safe` | bool | Yes (defaults to `false` if omitted) | Gates Orchestrator batch-mode dispatch (ADR-016). |
| `parallel-safe-considered` | list of strings | Required when `parallel-safe: true`; omit otherwise | Names the shared surfaces the Strategist evaluated. |
| `touches` | list of strings | Yes | File paths the item is permitted to modify. Reviewer scope check reads from here. |
| `references` | list of objects | Optional | Each entry: `path` (required), `lines` (optional, e.g. `"120-280"`), `purpose` (optional, short string). Read-only orientation material; modifying a References file is scope creep. |
| `target-repo` | string | Optional | Multi-repo split layout only. Names the code subdirectory for this W-item. Defaults to `DEFAULT_CODE_SUBDIR` from `$PROJECT_DIR/.env` when unset. Added by [ADR-021](adr-021-split-layout.md); `check-touches.sh` ignores it (orthogonal to the touches scope check). |

Fields the W-item file does NOT carry (and the reasons):

- **`status`** — lives only on the plan index per [ADR-017](adr-017-plan-folder-restructure.md). Putting it in frontmatter would re-introduce the drift bait ADR-017 eliminated. Status stays where it is.
- **`effort` / `markers`** — index columns ([ADR-017](adr-017-plan-folder-restructure.md) §"Index fields"); the Orchestrator reads them at-a-glance from the summary table. Duplicating them on the W-item file would invite the same drift.
- **`blocked-by`** — index `Blocked by` column ([ADR-017 v1.1](adr-017-plan-folder-restructure.md) §"Revision (v1.1)") is the single source for dependency data. Frontmatter would re-introduce the duplication that revision removed.
- **`id` / `title`** — H1 + filename + index already carry these. Frontmatter duplication earns nothing.

### Mechanical consumer (ships with the ADR)

`scripts/check-touches.sh` is a Reviewer-side mechanical scope check. Inputs: a W-item file path and a base ref (typically `origin/dev`). It parses the `touches` list from the file's YAML frontmatter, runs `git diff --name-only <base-ref>`, and emits any modified file that is not in `touches`. Exit codes:

- `0` — every modified file is within `touches`.
- `1` — at least one modified file is out of scope. Out-of-scope files are written to stdout, one per line.
- `2` — usage error or missing frontmatter (script can't decide; Reviewer falls back to manual judgment).

The Reviewer brief calls this script as part of question 6 (scope creep) before reading the diff. A non-zero exit gives the Reviewer a verified scope-creep signal with file paths attached, sharpening the verdict.

The script is shipped via the existing [ADR-019](adr-019-dev-slots-and-deploy-stubs.md) idempotent-init sync mechanism — the template's `_stubs/scripts/check-touches.sh` copies into adopter projects on first sync, never overwrites once present. (References field handling — flagging modified References as a separate scope-creep category — is left to the Reviewer's judgment for now; the script's first-pass check is `touches`-only.)

### Backward compatibility

Plans drafted before ADR-020 use the prose "Execution notes" shape. Both shapes coexist:

- **W-item file has frontmatter** → tools read frontmatter; Reviewer can run `check-touches.sh`.
- **W-item file has no frontmatter** (pre-ADR-020 plan) → tools fall back to prose extraction (Reviewer reads the prose Touches line; `check-touches.sh` exits 2 and the Reviewer judges manually).

No forced migration. New W-items drafted after ADR-020 use frontmatter. Strategists migrate older W-items on a schedule that suits the project. The repo's stub state means no production data exists to migrate.

### What this ADR does NOT do

- **Does not modify ADR-017.** Status stays on the plan index. The single-source doctrine is unchanged. ADR-017 remains canonical.
- **Does not introduce a separate `index.yaml` / `status.yaml`.** A second file for index state was considered and rejected — see Alternatives.
- **Does not yamlify the plan.md summary table.** That stays as a Markdown table for now. Revisit when a mechanical consumer for the summary-table data ships; today there is none.
- **Does not change role boundaries.** Strategist authors W-items (now with frontmatter); Executor reads them; Reviewer reads them + runs the new script. No write authorities change.
- **Does not change the lifecycle, status state machine, or claim flow.** All transitions and writers from ADR-017/018 remain.

## Consequences

**What this buys:**

- **Mechanical scope check.** Reviewer's question 6 gains a verified signal — `check-touches.sh` flags out-of-scope files with paths, before the Reviewer's prose verdict. Forgotten scope creep that a self-reporting Executor missed gets caught.
- **Cheap structured reads.** Orchestrator batch-mode collision evaluation can read just the frontmatter block (`head -N` until the second `---`), not the full prose body. Bytes-per-decision drops on the dispatcher's hot path.
- **Schema discipline.** Strategists writing new W-items hit a shape with required fields, not free-form prose where "Touches:" might or might not appear. Authoring drift is structurally constrained.
- **Token cost on the agent side falls** when the Reviewer or Orchestrator only needs the metadata — frontmatter is ~10 lines vs. a full prose body that may be 50+.

**What this costs:**

- **Two W-item shapes during transition.** Pre-ADR-020 plans have prose Execution notes; new plans have frontmatter. Tools must handle both; agents reading docs see references to both shapes. The cost is bounded but non-zero.
- **YAML parsing in scripts.** `check-touches.sh` uses Ruby (already in the framework's stub scripts under [ADR-019](adr-019-dev-slots-and-deploy-stubs.md)). Adopters without Ruby see a script that fails — but the failure mode is "Reviewer falls back to manual judgment," which is the pre-ADR-020 status quo.
- **Frontmatter syntax errors invisible until consumed.** A typo in YAML breaks the script silently (exit 2 → manual fallback). The framework does not enforce frontmatter validity at write time. Acceptable trade — the cost of broken frontmatter is "Reviewer falls back," not lost work.

**What this enables (deferred, not in this PR):**

- Future yamlification of `plan.md` summary table once a second mechanical consumer materializes (Orchestrator bootstrap script that ledger-reconciles by parsing YAML rather than reading the table).
- CI hook that runs `check-touches.sh` against PRs as a pre-merge gate.
- Strategist-side linter that validates frontmatter shape at draft time.

These are real follow-ups but each earns its own decision. Shipping them upfront would be speculative scaffolding.

## Alternatives considered

1. **Separate `status.yaml` ledger.** A YAML file under each plan folder with the W-item statuses. Rejected — directly contradicts ADR-017's single-source Status doctrine. Re-introduces the drift bait the prior ADR was specifically structured to eliminate. The original sketch in conversation proposed this; on review it was a doctrine reversal disguised as an extension.
2. **Fenced YAML block inside `plan.md`.** Replace the Markdown summary table with a ```yaml block. Rejected — half-measure. Tools still need a custom extractor (the file mixes formats); edits straddle two formats. Either commit to splitting state into `plan.yaml` cleanly (which would revise ADR-017 and is deferred) or leave the MD table alone. Half-doing it has neither benefit.
3. **Full hybrid (frontmatter on both W-items and plan.md).** Touch 9 docs, revise ADR-017's single-source rule, ship both layers in one PR. Rejected — speculative. The W-item frontmatter has a concrete consumer (`check-touches.sh`) shipping in this PR; the plan-index frontmatter does not. Defer until a consumer materializes. Smaller cuts that earn their keep beat large cuts that pay upfront for downstream wins.
4. **Add `touches` as JSON inside an HTML comment.** Machine-readable without restructuring the prose section. Rejected — JSON in HTML comments is awkward to author, awkward to read, and uglier than YAML frontmatter for the same parsing benefit. Frontmatter is the standard pattern.
5. **Skip the script entirely; just yamlify the field.** Move Touches into frontmatter without a mechanical consumer. Rejected — exactly the "speculative scaffolding" pattern the advisor flagged. The format change earns its keep only if at least one consumer ships in the same PR.

## Acceptance criteria for the shipping PR

- New file: `docs/architecture/adr-020-yaml-frontmatter-w-items.md` (this file).
- New file: `docs/dev_framework/_stubs/scripts/check-touches.sh` — Reviewer-side mechanical scope check, executable bit set.
- Updated: `docs/execution-plans/README.md` — W-item file shape shows frontmatter, "Execution notes" section header removed, field table updated to mark which fields are frontmatter and which are body, "What's NOT on the W-item file" paragraph extended to cover the frontmatter exclusions (status, effort, markers, blocked-by, id, title).
- Updated: `docs/dev_framework/templates/executor-brief.md` — STEP 1 / STEP 3 reference frontmatter as the source for `touches` and `references`.
- Updated: `docs/dev_framework/templates/reviewer-brief.md` — question 6 (scope creep) instructs the Reviewer to run `./scripts/check-touches.sh <w-item-file> origin/dev` and treat any non-zero exit's stdout as scope-creep findings.
- Updated: `.claude/hooks/sync-framework.sh` — `scripts/check-touches.sh` added to the idempotent-init sync list (preserves executable bit via `cp -p`).
- ADR-017 unchanged (Status doctrine intact).
- Single PR. Format change + consumer script + brief integrations land together. A format change without the consumer is speculative scaffolding; a script without the format is unmoored.
