# FWADR-018: Developer role (hands-on, user-in-loop coding)

**Status:** accepted
**Date:** 2026-04-25
**Deciders:** David (template author), Template Developer session

## Context

The framework has a single dispatch model: User ↔ Orchestrator → Executor → Reviewer → QA. It is well-suited to autonomous batch work where the user wants to be hands-off. It is poorly suited to work where the user wants to be in the loop — driving the test cadence personally, talking to the coding agent conversationally, calling pivots in real-time.

Three specific frictions surfaced:

1. **Conversational coding has no first-class shape.** The user can talk to a Claude Code session and code with it directly, but doing so leaves the framework's plan ledger behind — Status doesn't flip, branches aren't tracked, the artifacts the framework expects (W-item file references, lessons learned in commits, plan-side Notes) aren't produced. The user-in-the-loop mode exists in practice as ad-hoc work outside the SOP.

2. **Code-review gate for hands-on work.** Orchestrator mode runs a Reviewer subagent on every diff; Developer mode needs the same gate, but invoked by the persistent Developer (since the user is the QA gate, not the Reviewer dispatcher).

3. **QA-loop context bloat.** A persistent session linearly accumulates the full feature-build context plus every QA round-trip's investigation, and nothing in the loop sheds that mid-item. `/clear`-per-W-item bounds the cost but burns a full bootstrap reload (~12K tokens of Layer 0+1) per item. `/compact` is cheaper, but only workable if the session has a durable on-disk record to re-establish working state from — the role doc alone is not enough.

## Decision

Add a fourth product-side persistent role, **Developer**, that operates as a parallel mode to Orchestrator dispatch. The Developer is user-invoked, drives one W-item at a time conversationally, runs a user-mediated QA loop within `in_progress`, keeps a working log that survives `/compact`, then at user-confirmation spawns a Reviewer subagent on the diff for the code-review gate. The Developer remains the persistent owner of each W-item end-to-end.

### Mode field is advisory, not binding

The Developer and the Orchestrator both write Status to `plan.md`. The collision concern is per-W-item, not per-plan: an item can only run one mode's Status path (Orchestrator's `in_progress → done` or Developer's `in_progress → code_review → done`), and Status paths take different routes from `in_progress` so they cannot overlap.

A `**Mode**` field in the plan's Executive summary records the Strategist's recommended execution style — `orchestrator`, `developer`, or absent for no recommendation. **The field is advisory.** Either mode can claim any `pending` item on any plan. Per-plan exclusivity (binding Mode, refuse-on-mismatch) was tried and failed in field testing: it locked the Developer out of plans the Strategist had drafted with Orchestrator in mind, even when no W-item had been claimed and no collision was possible. It added friction without reducing collision risk.

Both bootstraps read the field on session start:

- The Orchestrator's STEP 0 MODE AWARENESS (in `orchestrator-bootstrap.md`) reads `Mode`. If `developer` (explicit), it **prompts the user** to confirm proceeding in Orchestrator mode anyway. If `orchestrator` or absent, proceeds normally.
- The Developer's bootstrap (in `developer.md`) reads `Mode`. If `orchestrator` (explicit), prompts the user to confirm proceeding in Developer mode anyway. If `developer` or absent, proceeds normally.

Items lock into a mode at claim time via the Status path they take. Per-W-item collision is naturally enforced; no plan-level lock is needed. **Mixed-mode phases are allowed** — a single plan can have some items running under Orchestrator dispatch and others running under Developer mode in parallel. The cost is historical asymmetry (Orchestrator-mode items have no Implementation log; Developer-mode items do), which is tolerable.

Claim attribution lives in the plan's Notes section (`"W-A1 — claimed by Developer YYYY-MM-DD"`), written atomically with the `pending → in_progress` flip. This gives a fresh session unambiguous attribution for in-flight items even before Status leaves `in_progress`.

### State machine extension: `code_review`

Add one new state — `code_review`. The full lifecycle for Developer-mode items:

```
pending → in_progress → code_review → done → shipped
              │              │
              │              └─(Reviewer concerns; user chooses Resolve)──→ in_progress
              │
              ├─(unblockable)──→ blocked
              │
              └─(acceptance ambiguity; claim)──→ held ──→ in_progress / blocked (Strategist)
```

**No `qa` state.** User-mediated QA happens inside `in_progress`. `in_progress` exits only when the user confirms the feature works. A `qa` state would never be observed long enough to matter — the user is personally pushing items through QA, with no automatic bounce and no asynchronous wait.

**`code_review → in_progress` is user-mediated, not automatic.** Unlike the Orchestrator's Reviewer-block re-dispatch (where the Orchestrator auto-loops with concerns as a sharpened brief), the Developer surfaces the Reviewer's findings and the user decides the outcome (§"Code-review gate" below).

### Code-review gate: sync, then spawned Reviewer subagent

At the user's QA-complete confirmation:

1. **`/compact` (recommended)** — collapses the QA-loop journey from session memory; the working log keeps the durable record. Optional, not required for correctness.
2. **Plan-write Status flip `in_progress → code_review`**, visible to other sessions immediately (§"Developer as fourth Status writer").
3. **Sync the feature branch with `origin/dev` by local rebase.** The Reviewer then reads accurate codebase context (the synced state, not stale pre-rebase files), the eventual merge is a clean fast-forward, and conflicts surface to the user before the Reviewer runs — so a "ship" verdict isn't undone by a later merge conflict.
4. **No push of the rebased feature branch.** It stays local: the Reviewer reads from the local working directory (Default: main checkout; Parallel: worktree) per its brief, never `origin/<feature>`. Pushing would buy nothing and would require force-push, conflicting with the framework's destructive-ops doctrine. Only `dev` is pushed, at the Ship merge.
5. **Spawn a Reviewer subagent** on the synced state — the same brief Orchestrator-mode sequential dispatch uses (FWADR-013). It gets the fresh-eyes property by being a separate process, not by context manipulation in the same session. The Developer remains owner: it spawned the Reviewer, reads the verdict, decides the merge, writes the Implementation log.

This ADR defines three user-mediated Reviewer outcomes: **Ship** (fast-forward merge to `dev` + `done`), **Resolve** (user wants concerns fixed → back to `in_progress` → re-code → re-sync → re-Reviewer), **Postpone** (user accepts concerns as a known limitation → logged in the Implementation log under `**Postponed concerns:**` + plan Notes → merge proceeds as Ship). Postpone fits a concern that is real but not blocking shipment for this phase; Resolve fits a concern that would cause user-visible breakage or violates a load-bearing standard. A fourth, **Reconcile**, for a Reviewer `doc-conflict` on a user-ordered deviation, is defined by [FWADR-027](fwadr-027-living-architecture.md).

The Implementation log lands on `dev` via the Ship merge but post-dates the Reviewer pass — it is metadata about the just-shipped work, not part of what was reviewed. The Reviewer brief does not audit it.

### Developer as fourth Status writer

Status writers expand from three to four:

- **Orchestrator** — owns Orchestrator-mode transitions (unchanged).
- **Integrator-QA** — owns `in_progress → held` in batch mode (unchanged).
- **Strategist** — owns `held → in_progress / blocked` (unchanged).
- **Developer** — owns Developer-mode transitions: `pending → in_progress`, `in_progress → code_review`, `in_progress → held` (rare), `in_progress → blocked`, `code_review → in_progress` (user-mediated), `code_review → done`, `done → shipped` (when phase is Developer-driven).

PLAN-WRITE DISCIPLINE applies at every Developer write site, same form as the other three writers: read fresh, edit, single commit alongside trigger event, verify pushed.

**Plan-writes never go on the feature branch.** Every Developer plan-write (claim flip, Status transitions, Notes lines) commits on `dev` and pushes to `origin/dev`, matching the Orchestrator's plan-write pattern; feature branches carry only code commits. A Status flip committed on the feature branch is invisible from `origin/dev`, so a concurrent plan-reader (a second Developer, an Orchestrator bootstrapping a mixed-mode phase, the Strategist auditing claims) could not see the in-flight claim — defeating PLAN-WRITE DISCIPLINE's visibility purpose. The Parallel Developer leaves its worktree for the main checkout to make plan-writes. (Under split layout, where the plan lives outside the code repo, the visibility mechanism follows [FWADR-021](fwadr-021-split-layout.md); the rule — never on the feature branch — is unchanged.)

### Implementation log on W-item file

Adds a fourth section to the W-item file template — appended by the Developer at `code_review → done` flip, atomic with the merge commit, distilled from the working log (§"Working log and phase discipline"):

```markdown
## Implementation log

**Approach:** One paragraph on how the work was actually done.
**Key decisions:** ...
**Pivots:** ...
**Surprises:** ...
**Followups / loose ends:** ...
```

This is **Developer-mode-specific**. `/compact` collapses the persistent session's journey, and the spawned Reviewer subagent never saw the journey to begin with — the Implementation log is the curated retrospective on the W-item itself. Other modes (Orchestrator-dispatched Executor) capture journey in commit messages and the plan's Notes section already.

The Implementation log does NOT violate FWADR-017's "static SOW" principle for the W-item file. The log is appended at done-flip and is then static for the lifetime of the project. FWADR-017 was about preventing Status drift via mid-flight runtime mutations of the W-item file. A done-flip append is a different shape and does not reintroduce drift bait.

### Working log and phase discipline

1. **Live working log file.** Each Developer-claimed W-item gets a sibling `w-<id>.log.md` in the plan folder, separate from the W-item SOW. Created lazily at the `pending → in_progress` claim. Freeform chronological — the Developer appends decisions, dead ends, fixes, retest outcomes, and **phase-transition markers** (`ready for QA`, `QA complete`) at every meaningful state change. Distilled into the Implementation log at `code_review → done`; the log file persists in the plan folder and archives with the plan. It is the durable artifact that lets the session `/compact` aggressively mid-item without losing the journey.

   **Why a separate file:** the W-item file's 200-line limit is structural — it gates per-dispatch context cost (Reviewer reads it, Strategist re-reads it on triage, fresh sessions re-bootstrap it). A QA cycle with 10+ rounds easily exceeds 200 lines of chronological log. Embedding the log would force either softening the limit (degrading the cost model for every reader) or truncating the log (losing the honest record). A separate file keeps the W-item file bounded and reader-cheap while the log grows freely, read only by the Developer that owns the item — and gives the Reviewer a clean exclusion (Reviewer reads diff + W-item file + `coding-standards.md`, never the working log).

2. **Session-level phase discipline.** `in_progress` covers two session-level phases — **Build** (pre-QA) and **QA** (post-QA-handoff). **Code Review** is the third phase, the only one with its own Status state (`code_review`). The split is a session-level convention; **the on-disk Status machine is unchanged** — Build → QA has no Status flip. `developer.md` §"Phase discipline" has one subsection per phase, each a re-read target after `/compact`. The user `/compact`s at QA-handoff and again at QA-complete; the agent re-reads the matching subsection plus the working log to recover phase and working state.

3. **Reorient hook differentiation.** The `compact` branch of `.claude/hooks/session-reorient.sh` tells a Developer to read its active W-item's working log in addition to the role doc, and to ask the user which phase is current if unclear (the latest timestamped header in the log names it). Other roles and other reorient sources are unaffected.

The QA back-and-forth (change-this-not-that, scope creep, refinement) is **acknowledged but not formalized** — the working log absorbs it as it happens; the discipline doc says "user leads, you investigate, log as you go," not a round-trip protocol. The working log is Developer-mode only: Executor subagents are stateless and per-task, so a persistent log has no consumer there.

### Invocation patterns: Default and Parallel

The Developer has two named invocations sharing one role doc, lifecycle, and discipline:

- **Default Developer** (`"you are the Developer"`) — works in the user's main checkout on a feature branch (`w-<id>/<slug>`). Bootstrap proposes the top critical-path `pending` item. The session the user collaborates with most actively.
- **Parallel Developer** (`"you are the parallel developer"`) — works in a worktree at `/tmp/worktrees/<project>/w-<id>-<slug>` (same path scheme as Orchestrator-mode Executors per FWADR-013). Bootstrap does a **non-competing scan** that reads the index alone:
  1. Note claimed items' (Status `in_progress` or `code_review`) stream letters (the letter in `W-<stream><number>`).
  2. For each `pending` item in critical-path order: skip if its stream letter matches a claimed item's; skip if any `Blocked by` entry on the index isn't `done`/`shipped`; otherwise propose.

The scan depends on FWADR-017's single-source dependency data (the index's `Blocked by` column) and makes the W-id stream-letter convention load-bearing: same letter = assumed code-path overlap; different letter = assumed non-competing. `Touches` and `Parallel-safe considered` are not scan inputs; the `Parallel-safe` field gates Orchestrator batch-mode dispatch (FWADR-016) only. The asymmetry is intentional: batch mode is autonomous and benefits from explicit infra-collision curation; Parallel Dev is user-supervised, and a rare cross-stream infra collision surfaces as a merge conflict the user catches in the loop. Canonical procedure: `dev_framework/developer.md` §"Non-competing scan (Parallel Developer)"; data model: `execution-plans/README.md` §"Summary table" + §"Index fields".

Why two invocations instead of one role with conditional behavior: the working-directory model is fundamentally different (in-place vs worktree) and the bootstrap scan is fundamentally different (critical-path vs non-competing). Conditional behavior in one role would require the session to ask "am I parallel or not?" at boot — fragile. Two named triggers make the user's intent unambiguous and the session's behavior deterministic from session start.

**Concurrent claim safety** is handled by PLAN-WRITE DISCIPLINE — read-fresh + commit + verify-pushed catches simultaneous claims at the push step, and the loser pulls + re-scans + picks something else. No new mechanism needed.

**N-Parallel sessions** (a third or fourth Parallel Developer alongside the Default) are mechanically supported — each in its own worktree, each does its own non-competing scan at boot. Diminishing returns past two because user attention serializes through the QA loop; documented but not optimized for.

**The "check dev" handoff** (Default Dev pulling Parallel's merged work into its own feature branch) is standard git: `git fetch origin dev && git merge origin/dev`. No framework-special protocol.

### Five-surface role-add

Per the framework-change doctrine: adding a role updates five surfaces in one PR.

1. `docs/dev_framework/developer.md` — the role doc itself, including §"Phase discipline" (Build / QA / Code Review).
2. `CLAUDE.md` §Roles table — two rows (Default + Parallel) pointing at the same role doc.
3. `docs/dev_framework/dev_framework.md` §Role docs — role row + brief mention in agent stack.
4. `docs/dev_framework/context-management.md` Layer 1 — bootstrap reading set, including `coding-standards.md` (Developer writes code, unlike Orchestrator/Strategist) + the active plan's `plan.md`.
5. `.claude/hooks/session-reorient.sh` — both Developer triggers in the role-list strings in all four sources (startup / resume / compact / clear), plus the Developer-specific `compact` re-read target (working log + matching phase subsection).

Plus the spec/doc updates:

6. `docs/execution-plans/README.md` — `code_review` state (seven Status values: `pending`, `in_progress`, `code_review`, `held`, `blocked`, `done`, `shipped`), Developer-owned transitions, Developer as Status writer and claim filer, Implementation log section template, Mode field as advisory recommendation, §"Mode signaling (per item, not per phase)", working log files (§"Working log files").
7. `docs/dev_framework/session-policy.md` §"Status ledger" — Developer as fourth writer.
8. `docs/dev_framework/strategist.md` and `templates/orchestrator-bootstrap.md` — claim-filer set (Integrator-QA OR Developer), four-writer note, STEP 0 MODE AWARENESS (prompt on explicit `Mode: developer`).

Half-shipping any of these creates an incoherent state — agents read a role doc that names a state the spec doesn't define, or vice versa. The mechanism and the rule ship together.

## Consequences

**What this buys:**

- **First-class shape for conversational coding.** The user-in-the-loop mode now produces the same plan ledger, branches, and persistent record as Orchestrator mode. Work no longer has to fall outside the framework to be done conversationally.
- **Fresh-eyes code review without losing ownership.** The Reviewer subagent gives fresh-eyes review by being a separate process; the Developer remains the persistent owner because it spawned the Reviewer, reads the verdict, decides the merge, and writes the Implementation log. Same Reviewer brief Orchestrator-mode sequential dispatch uses (no new mechanism).
- **Documented journey on the project.** The working log records what actually happened chronologically; the Implementation log curates it next to the W-item — pivots, advisor calls, decisions reversed — in places that survive session resets. Commit messages alone don't aggregate this.
- **Cheap mid-item context shedding.** `/compact` at phase boundaries recovers from the working log + phase subsection instead of a full bootstrap reload.
- **Disciplined escalation.** The Developer follows an **80/20 confidence ladder** at decision forks (self ≥80% → act; self <80% → advisor or consultant subagent; advisor <80% → escalate to user), consistent with Integrator-QA's claim-filing threshold. Mechanizes "when to interrupt the user" so the dialogue stays high-signal. Detail in `developer.md` §"Confidence-driven escalation (80/20 rule)".

**What this costs:**

- **Fourth Status writer.** PLAN-WRITE DISCIPLINE now applies at four agent-types' write sites instead of three. Each must hold the discipline. Drift risk extends.
- **Two parallel modes for the same kind of work (coding).** Newcomers to the framework have to learn both. Mitigated by per-plan Mode field as the Strategist's recommendation + prompt-on-explicit-mismatch in both bootstraps. Per-W-item collision is naturally prevented by mode-specific Status paths.
- **W-item file template grows.** Fourth section (Implementation log) on the SOW file — unused in Orchestrator mode (or used optionally), populated in Developer mode. Adopters reading the template see a section that may not apply to their mode.
- **One more artifact per Developer item.** The working log file sits beside the SOW in the plan folder.
- **One more field on `plan.md`.** Mode adds a single line in the Executive summary. Cheap, advisory — Strategists set it explicitly when they have a recommendation; absent means no recommendation expressed, with no penalty.

**What this does NOT do:**

- **Does not change Orchestrator dispatch.** FWADR-013 sequential mode and FWADR-016 batch mode flow unchanged. The new state `code_review` does not appear in Orchestrator-mode lifecycles.
- **Does not change claim semantics.** FWADR-016's claim shape and FWADR-017's claim location unchanged. Developer becomes a second filer (after Integrator-QA), but the protocol is identical.
- **Does not deprecate the Reviewer subagent — extends its use.** Reviewer is spawned in Orchestrator sequential mode (FWADR-013), absorbed by Integrator-QA in batch mode (FWADR-016), AND spawned by the Developer at `in_progress → code_review`. Same brief, three invocation points. The Reviewer surface (diff + W-item file + `coding-standards.md`) does not include the working log.
- **Does not change phase exit gates.** Phase exit still requires QA against the dev environment + user authorization, regardless of mode. The Developer can run the phase-exit smoke pass itself or coordinate with the user to run it; the gate is not waived.

## Alternatives considered

1. **Developer as Orchestrator-dispatched Executor variant.** Rejected — subagents are stateless invocations; the user-mediated QA loop and the persistent Implementation-log discipline both require a session the user talks to directly across many turns. Developer must be a persistent role, not a dispatched subagent.
2. **Per-W-item `Mode` field on plan.md.** Rejected — once items lock into a mode at claim time via Status path (Developer's `in_progress → code_review → done` versus Orchestrator's `in_progress → done`), an explicit per-item field would be redundant. Notes-section claim attribution (`"W-A1 — claimed by Developer YYYY-MM-DD"`) covers at-a-glance ownership for in-flight items.

   **Per-plan binding Mode field with refuse-on-mismatch.** Tried as the mechanism behind per-phase mode-exclusivity and abandoned after field testing: it locked the Developer out of Strategist-drafted Orchestrator plans even when no W-item had been claimed. The actual collision boundary is per-W-item (enforced by Status paths), not per-plan. Mode is advisory with prompt-on-explicit-mismatch instead (§"Mode field is advisory, not binding").
3. **Code-review via chat-rewind + blind self-review.** Tried and retired after field testing. At the `in_progress → code_review` flip the Developer would produce a structured rewind summary, the user would rewind chat to a pre-coding anchor and paste it, and the Developer would self-review from the clean context — "same persistent session, different context." In practice it was cumbersome (multi-step UI gymnastics — rewind chat, paste summary, re-prompt — on every W-item), easy to skip under time pressure, and coupled to Claude Code's chat-rewind affordance. The spawned Reviewer subagent gets the same fresh-eyes property via a separate process at lower workflow cost. The objection that a Reviewer subagent "loses project context" was overstated — the Reviewer brief reconstructs project context from the W-item file + diff, the same artifacts a rewound self would read; the real difference is same-session vs different-session, not context-aware vs context-blind. Workflow simplicity wins. See §"Code-review gate".
4. **Add a `qa` state.** Rejected — the user is the QA gate in real-time. State doesn't bounce between `qa` and `in_progress`; `in_progress` covers the whole loop until user confirmation. A separate `qa` state would never be observed long enough to matter. The Build/QA split is carried by session-level phase discipline instead.
5. **Universal Implementation log (all modes).** Deferred — Developer-mode-specific because that's where `/compact` collapses the persistent session's journey and the spawned Reviewer never sees it. Easy to extend to Orchestrator mode if usage shows benefit.
6. **Skip ADR; document in role doc only.** Rejected — adding a role + state machine extension + new write authority is a load-bearing decision touching eight framework surfaces. Future readers need a single decision record explaining why.
7. **Plan-writes on the feature branch** (Status flip committed alongside the sync). Rejected — invisible from `origin/dev`, so concurrent plan-readers cannot see the claim. See §"Developer as fourth Status writer".
8. **Push the rebased feature branch to `origin/<feature>` before review.** Rejected — the Reviewer reads the local working directory, so it buys nothing, and it requires force-push, conflicting with the destructive-ops doctrine.
9. **Working log embedded in the W-item file** — either distilled then removed at done (option A) or kept alongside the Implementation log (option B). Rejected in favor of a separate file (option C): A loses the honest chronological record; B breaks the W-item file's 200-line limit. See §"Working log and phase discipline".
10. **Non-competing scan reading W-item files (`Touches` + Parallel-safe shared surfaces).** Rejected — it forced the Parallel Developer to fan out across multiple W-item files at boot, defeating the context-budget rationale of FWADR-017's index/SOW split, and the bulk content couldn't be selectively evicted from the persistent session by `/compact`. The index-only scan (stream letter + `Blocked by`) replaced it.
