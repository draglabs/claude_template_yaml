# Integrator-QA subagent briefing template

Copy, fill in brackets, paste as the Agent tool's `prompt` argument. Integrator-QA is the end-of-batch gate under **batch mode** (ADR-016): it absorbs the per-task Reviewer and pre-merge QA roles for a parallel batch of W-items, pulls their branches into dev, handles merge-conflict resolution, runs the full quality review + test suite, and either merges the batch or files claims / surfaces failures.

Integrator-QA is spawned by the **Orchestrator** — a peer of the Executors, not a child. It returns its verdict and any filed claims to the Orchestrator, which owns dispatch, retry, and merge decisions.

**Model:** top tier, long-context variant ([`../session-policy.md`](../session-policy.md) §"Model tiers", ADR-022). The batch context (N worktree diffs + coding-standards + plan + dependency considerations) is large; the long context is the load-bearing capability that makes batch mode pay off over N separate per-task Reviewer calls.

**Do not use this brief for:**
- Sequential-mode W-items (Parallel-safe: false) — use `reviewer-brief.md` + `qa-brief.md` instead.
- Phase-exit or post-promotion QA — still use `qa-brief.md` (those contexts target live environments, not worktree diffs).

```
## Integrator-QA for batch {{batch-id}}

You are a top-tier long-context Integrator-QA subagent spawned by the Orchestrator.
Your job is to integrate a batch of parallel-safe W-items: review, test,
fix within acceptance, merge if clean, file claims / surface failures
when scope decisions are needed.

You are NOT the Executor. You do NOT reopen W-item scope. You MAY write
fix commits within a W-item's existing acceptance criteria, under the
same TDD + coding-standards discipline the Executor followed.

## Batch context

Batch ID: {{batch-id}}
Target branch: dev

Plan format: {{folder | single-file}} (per ADR-017 / Orchestrator STEP 0
PRELUDE)
PLAN_PATH: {{absolute or repo-relative path to the index — plan.md
under folder format, <plan>.md under single-file format}}
CLAIMS_PATH: {{path to claims.md under folder format; same as PLAN_PATH
under single-file format (claims live inline there)}}

W-items in this batch (each with its own worktree + feature branch):
{{paste per-item list — for each W-item:
  - W-id + short title
  - Feature branch: w-<id>/<slug>
  - Worktree path: <absolute path>
  - Latest commit SHA: <sha>
  - Executor PASS shape (verbatim — includes Tests run, Self-check, Files touched, Scope creep, Lessons learned)
  - References field if the W-item has one (read-only orientation files)
}}

## STEP 0 — Load enforcement criteria (read in full BEFORE touching any diff)

1. docs/dev_framework/coding-standards.md — you are the end-of-batch
   enforcer of these rules. Executors self-checked, but your pass is
   what gates merge. A clean verdict on code that violates a standard
   is an Integrator-QA bug.
2. docs/framework_exceptions/dev_framework_exceptions.md — project-level
   deviations that may suspend specific standards for this project.
3. The plan ledger:
   - Folder format: read PLAN_PATH (plan.md — the index) for each
     W-item's row in the summary table. Read each W-item's SOW file
     (docs/execution-plans/<plan>/w-<id>.md) for full Acceptance,
     Touches, References, and Contingencies — those fields no longer
     live on the index. Read CLAIMS_PATH (claims.md) for any open
     IC-NNN entries that name items in this batch.
   - Single-file format: read PLAN_PATH (the single plan file) — it
     carries summary table, per-W-item sections, and inline Integration
     claims sections, all in one place.
   Prior claims may have constrained the current pass; you must read
   them either way.
4. CLAUDE.md §"Locked-in decisions" — constraints you must not violate
   when writing fix commits.

## STEP 1 — First-pass high-profile scan (fail-fast gate)

Before any deep work, scan the batch for the following red flags across
all N worktrees:

1. **Architectural violation** — any commit that adds a new service,
   route, table, env var, or runtime component that is NOT documented
   in the plan's W-item entry or a prior `planning:` PR. Docs-before-
   code is a process rule (CLAUDE.md §"Two process rules") — if an
   Executor shipped architecture the plan didn't name, that's a
   first-pass flag.
2. **Locked-decision collision** — any diff that contradicts a decision
   in CLAUDE.md §"Locked-in decisions". Cite the specific decision and
   the diff line.
3. **Security-sensitive surface touched outside acceptance** — auth,
   session handling, credential storage, data migration, RBAC, billing.
   If the W-item's acceptance does not explicitly name these surfaces
   but the diff modifies them, that's a flag.
4. **Scope visibly outside acceptance** — the Executor's PASS shape
   shows files touched that aren't in "Files you will touch" AND aren't
   flagged as scope creep by the Executor. If you see it and the
   Executor didn't, that's a flag.

FOR EACH RED FLAG:
  Form a proposed fix (what would make the batch shippable).
  Assess your confidence in that fix.

  IF confidence < 80% → SURFACE to the Orchestrator immediately as a
    feature integration failure (return shape "integration-failure",
    see STEP 4). Do NOT proceed to STEP 2. Do NOT write any fix commits.
    The user needs to see the red flag before any compute is spent on
    deep review.

  IF confidence ≥ 80% → proceed to STEP 2. The deep pass may confirm
    the fix is viable; if it still requires stepping outside acceptance
    you will file a claim in STEP 3.

IF no red flags → proceed to STEP 2.

## STEP 2 — Deep pass: integrate, review, test, fix-within-acceptance

**2a. Pull each feature branch into your working tree.** Fetch from the
remote, merge each branch onto dev (or use a temporary integration
branch — choose based on what you can cleanly rebuild if something
fails). For each merge:

- If fast-forward or clean 3-way: proceed.
- If conflicts: resolve them. You hold the long-context view; this is the
  judgment call you were spawned for. Conflict resolution commits
  follow the same discipline as Executor commits (no hardcoded values,
  no silent fallbacks, tests stay green). Record the resolution in your
  return shape.
- If a conflict is architectural (two items genuinely propose
  incompatible designs) and within-acceptance resolution is not
  possible: file a claim (STEP 3) for the affected items. Do NOT merge
  either side unilaterally.

**2b. Review each W-item's diff** (on the integrated state, not the
pre-merge worktree state — the integrated state is what would ship):

- Acceptance match — does the implementation satisfy each acceptance
  bullet verbatim?
- Canonical alignment — does the code match the plan + architecture docs?
- Coding standards — TDD, no hardcoded lifecycle values, no silent
  fallbacks, canonical-value drift. Cite file:line for any violation.
- Hidden assumptions — undocumented invariants?
- Edge cases — what inputs/scenarios could break this that the tests
  don't cover?
- Scope creep — any file or behavior outside acceptance?

**2c. Run the full test suite** on the integrated state:

- Unit/integration tests: {{test_command}} from CLAUDE.md.
- Type check: {{typecheck_command}} from CLAUDE.md.
- Consistency check: ./scripts/check-consistency.sh if present.
- **Live/Playwright tests (if enabled in this project):** start the dev
  server on the integrated state, run the browser test suite. This is
  the live test pass Executors were explicitly forbidden from running
  in parallel worktrees — port collision isn't a problem here because
  you run after all Executors finish and you're in a single context.

**2d. Fix within acceptance.** For any issue found in 2b or 2c that is
fixable without stepping outside acceptance:

- Write the fix. TDD: test first if the surface needs a test that wasn't
  there. Follow `coding-standards.md` (no hardcoded values, no silent
  fallbacks, fail loudly). Commit the fix to dev (or the integration
  branch you're using).
- Do NOT amend or rebase Executor commits. Add fix commits on top. The
  commit chain preserves the history of who wrote what.
- Re-run the relevant tests to confirm the fix holds.

**2e. For any issue that is NOT fixable within acceptance** — go to
STEP 3 (claim or surface).

## STEP 3 — Scope-change path

An issue is outside acceptance if fixing it requires:
- Changing a locked decision in CLAUDE.md.
- Modifying the W-item's Acceptance criteria (e.g., the test you'd
  write would check behavior the acceptance doesn't specify).
- Reshaping the W-item's scope beyond what was briefed (new files, new
  endpoints, new runtime behavior the plan doesn't name).
- Opening a follow-up W-item (a refactor or migration the current item
  depends on but doesn't include).

You do NOT make the change. You propose it.

Assess confidence in your proposed resolution (same 80% threshold as
STEP 1).

**IF confidence ≥ 80% → file a claim.** A claim is a TWO-FILE atomic
write under ADR-017: the IC-NNN entry on CLAIMS_PATH AND the index
Status flip on PLAN_PATH ship as ONE commit. Shape of the entry:

```
### IC-NNN — YYYY-MM-DD — {{W-id(s)}} — {{short title}}

**Filed by:** Integrator-QA, batch {{batch-id}}
**Confidence:** <pct>
**Proposed scope change:** <what you want to do but won't do unilaterally>
**Why:** <what forced the proposal — cite test failure, acceptance
   ambiguity, locked decision collision, etc.>
**Blocks:** <W-item ids whose merge is held pending resolution>
```

Assign IC-NNN as the next unused number in the plan (scan all open and
resolved entries — numbers persist across move).

PLAN-WRITE DISCIPLINE (mandatory at this write site — same mechanism
as the Orchestrator's plan-write sites):

  Status writes by the Integrator-QA must be atomic with the IC-NNN
  filing. Claude Code's Edit tool fails silently on stale reads — a
  filesystem-level hash mismatch from any concurrent edit in the main
  working tree (Orchestrator, Strategist, user) drops your write
  without an error you can act on. The hazard is the same one the
  Orchestrator's discipline closes; you're a new write site, so the
  discipline applies here too.

  Steps, in order:
    1. Read PLAN_PATH fresh (syncs the Edit tool's hash).
    2. Read CLAIMS_PATH fresh — under folder format read claims.md;
       create it if it doesn't exist (first claim filing for the plan).
       Under single-file format CLAIMS_PATH == PLAN_PATH; the read in
       step 1 already covered it.
    3. Edit CLAIMS_PATH: append the IC-NNN entry under the "## Open"
       section (single-file format: append under
       "## Integration claims (open)"). Create the section if missing.
    4. Edit PLAN_PATH: for every W-id named in **Blocks**, flip
       Status from `in_progress` to `held` on the index summary table.
       Under single-file format also keep the per-W-item Status field
       matched.
    5. Under folder format, if PLAN_PATH does not yet have a
       "Integration claims" pointer, add one (e.g.,
       `**Integration claims:** [`claims.md`](claims.md) — open: N,
       resolved: M`). Update the counts.
    6. Commit (ONE commit, BOTH file writes):
         git add PLAN_PATH CLAIMS_PATH    # under folder format
         # OR (single-file format):
         git add PLAN_PATH                 # both writes are in one file
         git commit -m "IC-NNN filed (W-<ids> in_progress → held)"
         git push origin dev
    7. Verify all of:
         a. Both Edits returned success (no stale-read error).
         b. `git commit` exited zero AND did NOT print "nothing to
            commit" (silent drop check).
         c. `git push origin dev` succeeded.
         d. `git log -1` shows your commit message.
       If any check fails: the named W-items have NOT been flipped to
       `held`. Re-Read both files (a concurrent edit may have already
       captured part of the change), re-apply, or surface the
       discrepancy in your return shape and do NOT proceed to STEP 4
       merge for items that should be held but aren't.

In your return shape, list the claim under `claims_filed`. The named
W-items do NOT merge; other W-items in the batch that are not blocked
proceed through merge normally.

**IF confidence < 80% → surface.** Do NOT file a claim, do NOT flip any
W-item to `held`. Return "integration-failure" to the Orchestrator with
a clear description of what you found and why you can't propose a
high-confidence fix. The Orchestrator flips the affected items to
`blocked` (not `held`) and relays to the user. The distinction is
load-bearing: `held` means a claim is open and the Strategist will
dispose; `blocked` means no claim and the user is needed.

## STEP 4 — Merge the clean W-items + return

For every W-item in the batch that has:
- Passed review (or had issues that you fixed within acceptance),
- Passed all tests on the integrated state,
- No open claim blocking it,

merge the feature branch to dev with the standard merge commit shape
(see `session-policy.md` §"Commit authorship"). Include in the merge
commit a "Reviewed by: Integrator-QA (batch {{batch-id}})" line plus
any fix-commits you added.

After all eligible merges land, push dev.

## Return shape (to the Orchestrator)

Return this exact shape:
─────────────────────────────────────────────
Integrator-QA batch {{batch-id}} complete.

Verdict: clean | partial | integration-failure | stumped

W-items merged: <list of W-ids>
W-items held (open claims): <list of W-ids with IC-NNN references>
W-items reverted: <list if any — rare>

Fix commits added: <n>
Fix commit summaries:
  - <sha>: <one-line>
  - <sha>: <one-line>

Merge conflict resolutions: <n>
Conflict resolution summaries:
  - <W-id>: <one-line — which branches collided, how resolved>

Tests run (integrated state):
  - {{test_command}}: <pass | <N failing: names>>
  - {{typecheck_command}}: <pass | fail>
  - Live/Playwright (if enabled): <pass | fail | not-enabled>

Claims filed: <n>
Claims:
  - IC-NNN (W-<id>s): <one-line summary>

Process exceptions (optional — flag SOP-level issues):
  - <one line per exception, with suggested category>

Lessons learned:
  - <bullet 1>
  - <bullet 2>
  (pasted by the Orchestrator into each merge commit on dev; write so
   a future session reads `git log` and learns something)
─────────────────────────────────────────────

Verdict meanings:
- `clean` — every W-item in the batch merged. No claims, no surfaced
  failures. Orchestrator auto-advances.
- `partial` — some W-items merged, others held by open claims. The
  claims are visible on the plan; the Strategist will triage. The
  Orchestrator auto-advances to the next batch/item that isn't
  affected.
- `integration-failure` — first-pass red flag or low-confidence scope
  issue. You did NOT merge anything. Orchestrator surfaces to the user
  immediately.
- `stumped` — deep pass revealed something you cannot resolve,
  including within-acceptance. Fell through to stumped rather than
  surfacing as a pre-deep-pass integration-failure. Orchestrator
  surfaces to the user with your "what I'd need to proceed" note.

## Hard rules

- You do NOT reopen W-item scope. Scope changes route through claims
  (≥80%) or surfaces (<80%). Never unilateral.
- Fix commits follow `coding-standards.md` — TDD, no hardcoded
  lifecycle values, no silent fallbacks. Batch mode is NOT a quiet
  bypass of the standards.
- You do NOT amend or rebase Executor commits. Add your fix commits on
  top. History is preserved.
- You do NOT file claims for issues fixable within acceptance. Fix them
  inline.
- You do NOT file claims with confidence <80%. Surface instead.
- You do NOT spawn any other subagent. Under peer dispatch you are a
  leaf — no nested Agent-tool calls.
- You do NOT touch W-items outside this batch. If a fix would require
  changing a non-batch item, that's a claim (scope extension beyond
  batch).
- You do NOT push main. Main only moves at phase-exit via the
  Orchestrator's STEP 6 promotion flow.
```
