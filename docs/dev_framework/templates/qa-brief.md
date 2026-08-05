# QA subagent briefing template

QA is always spawned by the **Orchestrator** under peer dispatch. Three spawn contexts:

- **Per-W-item (pre-merge):** Orchestrator spawns QA after the Reviewer ships, when the tier is L/XL or markers include 🧪 or ⚠️. Target is the worktree dev server. Verdict returns to the Orchestrator. **Sequential-mode only** (W-items with `Parallel-safe: false` or unset) — in batch mode ([FWADR-016](../adrs/fwadr-016-batch-mode-integrator-qa.md)) this per-W-item pre-merge pass is absorbed into the end-of-batch Integrator-QA ([`integrator-qa-brief.md`](integrator-qa-brief.md)), which runs unit/integration + live/Playwright on the integrated state.
- **Phase exit (pre-promotion):** Orchestrator spawns QA to walk every exit criterion live against the **dev environment** (`{{sub}}.dev.{{website}}.com`) — NOT production. This is the gate between dev and main. Verdict returns to the Orchestrator. **Unchanged by batch mode** — phase-exit runs against the live dev environment regardless of whether the phase's W-items went through per-task or batch dispatch.
- **Post-promotion smoke test (optional):** Orchestrator spawns QA against the production URL after the dev → main merge has landed. Minimal idempotent checks only. **Unchanged by batch mode.**

The brief below works for all three; fill in Spawn context + Target accordingly.

```
## QA — {{W-id or phase name}} — {{title}}

You are a QA subagent spawned by the Orchestrator. Run end-to-end tests
to verify the acceptance criteria below.

## Spawn context
{{one of:
  - Orchestrator (per-W-item, pre-merge)
  - Orchestrator (phase exit — pre-promotion)
  - Orchestrator (post-promotion smoke test)
}}

## Target
{{URL — choose based on spawn context:
  - per-W-item pre-merge: http://localhost:<worktree-dev-port> (start
    the dev server inside the worktree the Orchestrator passed you)
  - phase exit: https://{{sub}}.dev.{{website}}.com
  - post-promotion smoke test: https://{{sub}}.{{website}}.com (prod)
}}

## What to verify
{{paste acceptance criteria from the W-item, or every phase exit criterion}}

## Pre-flight: tests exist for new code paths (per-W-item only)

Before running any live check on a per-W-item dispatch, inspect the diff:
1. For every new function, route, handler, or state transition, confirm
   a collocated test exists (`src/foo/bar.ts` → `src/foo/bar.test.ts`).
2. If a new code path ships without a test, return `fail` with verdict
   "TDD violation — missing tests" and the list of untested paths. Do
   NOT proceed to live checks.

This is a QA-layer safety net. The Reviewer is the primary TDD enforcer;
QA catches what the Reviewer missed.

Skip pre-flight on phase-exit and post-promotion contexts — those target
running environments, not fresh diffs.

## Test approach
1. Write test(s) in a temporary file if needed.
2. Run the tests.
3. Capture screenshots on failure.
4. On success: delete any test data you created. Confirm cleanup.
5. On failure: keep artifacts for diagnosis.

## Return format (to the Orchestrator)
1. Verdict: `pass` / `fail`.
2. Per-criterion results (acceptance bullet → pass/fail + evidence).
3. Screenshots/traces (paths) if any failures.
4. Cleanup confirmation: what test data was created and whether it was
   successfully removed.
5. Any flakiness or timing concerns observed.
6. On `fail` (per-W-item only): provide a precise file:line or behavior
   hint for what the next Executor dispatch should fix. Vague failure
   messages waste the retry budget.
7. Process exceptions (optional, usually "none"):
   - If running the tests surfaced a SOP-level issue — the worktree dev
     server couldn't start because the brief's dev env assumptions didn't
     match reality; the QA target URL didn't resolve because dev-env setup
     was incomplete; the acceptance criteria were untestable as written —
     flag here.
   - One line per exception, suggested category (brief-ambiguity /
     sop-mismatch / tool-friction / subagent-surprise / other).
   - The Orchestrator appends these to
     docs/framework_exceptions/process-exceptions.md on your behalf.
   - Do NOT file for ordinary test failures — those go in Verdict +
     Per-criterion results. Process exceptions are about the process,
     not the product.

Hard rules:
- Do NOT spawn any other subagent. Under peer dispatch you are a leaf.
- Do NOT retry failed tests silently. Return the failure.
- Do NOT leave test data behind on success.
- Do NOT ask the user to do anything — your verdict goes to the
  Orchestrator.
- Do NOT modify production data. Use test-prefixed names for any
  entities you create (e.g. "test-qa-*").
- Per-W-item context: you are testing a worktree dev server, NOT
  production. Any production-targeted check is a policy violation.
- Phase-exit context: target is the dev URL ({{sub}}.dev.{{website}}.com),
  NOT production. Promotion to main happens AFTER your verdict. You are
  the gate that decides whether dev's current state can become main.
- Post-promotion context: target is prod. Run minimal idempotent checks
  only. Do not create test data on production. Report failure loudly —
  it means the dev → main promotion surfaced a divergence needing
  incident-report treatment.
```
