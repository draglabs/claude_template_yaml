# ADR-018: Developer role (hands-on, user-in-loop coding)

**Status:** accepted
**Date:** 2026-04-25
**Deciders:** David (template author), Template Developer session

## Context

The framework has a single dispatch model: User ↔ Orchestrator → Executor → Reviewer → QA. It is well-suited to autonomous batch work where the user wants to be hands-off. It is poorly suited to work where the user wants to be in the loop — driving the test cadence personally, talking to the coding agent conversationally, calling pivots in real-time.

Two specific frictions surfaced:

1. **Conversational coding has no first-class shape.** The user can talk to a Claude Code session and code with it directly today, but doing so leaves the framework's plan ledger behind — Status doesn't flip, branches aren't tracked, the artifacts the framework expects (W-item file references, lessons learned in commits, plan-side Notes) aren't produced. The user-in-the-loop mode exists in practice as ad-hoc work outside the SOP.

2. **Code-review gate for hands-on work.** Orchestrator mode runs a Reviewer subagent on every diff; Developer mode needs the same gate, but invoked by the persistent Developer (since the user is the QA gate, not the Reviewer dispatcher). The Developer spawns the Reviewer subagent at `in_progress → code_review` and reads the verdict. Same brief, same fresh-eyes property — different invocation point.

## Decision

Add a fourth product-side persistent role, **Developer**, that operates as a parallel mode to Orchestrator dispatch. The Developer is user-invoked, drives one W-item at a time conversationally, runs a user-mediated QA loop within `in_progress`, then at user-confirmation optionally `/compact`s its session context and spawns a Reviewer subagent on the diff for the code-review gate. The Developer remains the persistent owner of each W-item end-to-end.

### Mode field is advisory, not binding (v2)

The Developer and the Orchestrator both write Status to `plan.md`. The collision concern is per-W-item, not per-plan: an item can only run one mode's Status path (Orchestrator's `in_progress → done` or Developer's `in_progress → code_review → done`), and Status paths take different routes from `in_progress` so they cannot overlap.

A `**Mode**` field in the plan's Executive summary records the Strategist's recommended execution style — `orchestrator`, `developer`, or absent for no recommendation. **The field is advisory.** Either mode can claim any `pending` item on any plan. The Strategist's recommendation is a hint, not a lock.

Both bootstraps read the field on session start:

- The Orchestrator's STEP 0 MODE AWARENESS (in `orchestrator-bootstrap.md`) reads `Mode`. If `developer` (explicit), it **prompts the user** to confirm proceeding in Orchestrator mode anyway. If `orchestrator` or absent, proceeds normally.
- The Developer's bootstrap (in `developer.md`) reads `Mode`. If `orchestrator` (explicit), prompts the user to confirm proceeding in Developer mode anyway. If `developer` or absent, proceeds normally.

Items lock into a mode at claim time via the Status path they take. Per-W-item collision is naturally enforced; no plan-level lock is needed. **Mixed-mode phases are allowed** — a single plan can have some items running under Orchestrator dispatch and others running under Developer mode in parallel. The cost is historical asymmetry (early items have no Implementation log; later items do), which is tolerable.

Claim attribution lives in the plan's Notes section (`"W-A1 — claimed by Developer YYYY-MM-DD"`), written atomically with the `pending → in_progress` flip. This gives a fresh session unambiguous attribution for in-flight items even before Status leaves `in_progress`.

#### Revision (v2)

ADR-018 originally specified per-phase mode-exclusivity enforced via the Mode field with refuse-on-mismatch. Field testing showed this was over-strict — it locked the Developer out of plans the Strategist had drafted with Orchestrator in mind, even when no W-item had been claimed and no collision was possible. The doctrine "rule + mechanism in the same PR" was satisfied, but the rule itself was wrong.

The correct read: per-W-item Status paths are the natural collision boundary. Per-plan exclusivity adds friction without reducing collision risk. v2 (current) walks back to: Mode field as advisory recommendation, prompt-on-explicit-mismatch instead of refuse, mixed-mode phases allowed, claim attribution in Notes for at-a-glance ownership.

A **per-W-item** `Mode` override field is also rejected — once items lock into a mode at claim time via Status path, the override field would be redundant. The Notes-line attribution + Status-path inference covers what a per-item Mode field would cover.

#### Revision (v3): rewind retired

ADR-018 v1 specified a **chat-rewind blind self-review** as the code-review gate: at the `in_progress → code_review` flip, the Developer would produce a structured rewind summary, recommend the user rewind chat to a pre-coding anchor and paste the summary, then read the resulting clean-context state and perform blind self-review on its own work. The novel value was "same persistent session, different context" — fresh-eyes review without spawning a separate process.

Field testing showed the ritual was **cumbersome in practice**: multi-step user UI gymnastics (rewind chat, paste summary, re-prompt) on every W-item, easy to skip under time pressure, and harness-coupled (depended on Claude Code's chat-rewind affordance). The user described it as "pretty cumbersome" after first encounter.

v3 retires the rewind ritual and replaces it with: **`/compact` (recommended) for the persistent session's context budget + sync feature with `dev` (rebase) + spawned Reviewer subagent on the synced state for the actual code-review gate**. The Reviewer is a fresh process with its own context — same brief Orchestrator-mode sequential dispatch uses (ADR-013) — so it gets the fresh-eyes property by virtue of being a separate session, not via context manipulation in the same session. The Developer remains the persistent owner: it spawned the Reviewer, reads the verdict, decides the merge, writes the Implementation log.

The sync step (rebase feature on `origin/dev` before review) means the Reviewer reads accurate codebase context (the synced state, not stale pre-rebase files) and the eventual merge is a clean fast-forward. Conflicts surface to the user before the Reviewer runs, so a "ship" verdict isn't undone by a subsequent merge conflict.

Reviewer outcomes are three, all user-mediated: **Ship** (merge + done), **Resolve** (user wants concerns fixed → re-code → re-sync → re-Reviewer), **Postpone** (user accepts concerns as known limitation → log in Implementation log under `**Postponed concerns:**` line + plan Notes → merge proceeds). Postpone is the right call when the concern is real but not blocking shipment for this phase; Resolve is right when the concern would cause user-visible breakage or violates a load-bearing standard.

The original v1 rejection of "spawn Reviewer subagent" cited "loses project context" as the concern. That was overstated — the Reviewer brief reconstructs project context from the W-item file + diff, the same artifacts a rewound self would read. The actual difference between rewound-self and Reviewer-subagent is "same session" vs "different session," not "context-aware" vs "context-blind." Workflow simplicity wins.

What survives from v1: the Developer is still a persistent role, still drives the user-mediated QA loop, still owns the W-item end-to-end via the persistent session, still writes the Implementation log at done. The lifecycle states are unchanged (`pending → in_progress → code_review → done → shipped`); only the mechanism behind `code_review` changes.

#### Revision (v3.1): plan-writes on `dev`, no force-push of feature

Field iteration after v3 landed surfaced two refinements to the sync + plan-write flow:

1. **Plan-writes go on `dev`, not the feature branch.** Originally the `in_progress → code_review` Status flip was committed on the feature branch alongside the sync. This made the claim invisible from `origin/dev` — any concurrent plan-reader (a second Developer instance, an Orchestrator bootstrapping a mixed-mode phase, the Strategist auditing claims) could not see the in-flight `code_review` claim by reading the canonical plan, defeating PLAN-WRITE DISCIPLINE's visibility purpose. Resolution: **every Developer plan-write (claim flip, Status transitions, Notes lines) commits on `dev` and pushes to `origin/dev`**, matching the Orchestrator's plan-write pattern. Feature branches carry only code commits. Parallel Developer must `cd <main checkout path>` to do plan-writes (leaving the worktree); Default Developer is already there.

2. **No force-push of `origin/<feature>` after rebase.** The rebased feature branch is local-only — the Reviewer reads from the local working directory (Default: main checkout; Parallel: worktree path) per the brief's "Where to read from" section, never fetching `origin/<feature>`. Pushing the rebased branch to `origin/<feature>` would buy nothing and would require force-push, conflicting with the framework's destructive-ops doctrine. The eventual merge to `dev` (Ship path) is a clean fast-forward locally; only `dev` is pushed.

Side effects: the Implementation log lands on `dev` via the fast-forward Ship merge but post-dates the Reviewer pass — it is metadata about the just-shipped work, not part of what was reviewed. No rule break: the Reviewer brief does not audit the Implementation log section.

These refinements were made during field testing of v3 against the framework's own development workflow. Lifecycle states and Reviewer outcomes are unchanged; only the commit topology of the sync + plan-write flow was tightened.

### State machine extension: `code_review`

Add one new state — `code_review`. The full lifecycle for Developer-mode items:

```
pending → in_progress → code_review → done → shipped
              │              │
              │              └─(self-review serious; user re-engages)──→ in_progress
              │
              ├─(unblockable)──→ blocked
              │
              └─(acceptance ambiguity; claim)──→ held ──→ in_progress / blocked (Strategist)
```

**No `qa` state.** User-mediated QA happens inside `in_progress`. `in_progress` exits only when the user confirms the feature works. Adding a `qa` state was rejected because the user is personally pushing items through QA — there's no automatic bounce, no asynchronous wait — so a separate Status value would never be observed long enough to matter.

**`code_review → in_progress` is user-mediated, not automatic.** Unlike the Orchestrator's Reviewer-block re-dispatch (where the Orchestrator auto-loops with concerns as a sharpened brief), a self-review block requires the user to engage. The Developer surfaces findings; the user decides whether to fix-and-retry, ship-with-known-limitation, or block.

### Developer as fourth Status writer

Status writers expand from three to four:

- **Orchestrator** — owns Orchestrator-mode transitions (unchanged).
- **Integrator-QA** — owns `in_progress → held` in batch mode (unchanged).
- **Strategist** — owns `held → in_progress / blocked` (unchanged).
- **Developer** — owns Developer-mode transitions: `pending → in_progress`, `in_progress → code_review`, `in_progress → held` (rare), `in_progress → blocked`, `code_review → in_progress` (user-mediated), `code_review → done`, `done → shipped` (when phase is Developer-driven).

PLAN-WRITE DISCIPLINE applies at every Developer write site, same form as the other three writers: read fresh, edit, single commit alongside trigger event, verify pushed.

### Implementation log on W-item file

Adds a fourth section to the W-item file template — appended by the Developer at `code_review → done` flip, atomic with the merge commit:

```markdown
## Implementation log

**Approach:** One paragraph on how the work was actually done.
**Key decisions:** ...
**Pivots:** ...
**Surprises:** ...
**Followups / loose ends:** ...
```

This is **Developer-mode-specific** in v1. `/compact` collapses the persistent session's journey at the QA-pass moment, and the spawned Reviewer subagent never saw the journey to begin with — the Implementation log persists it on the project as the only durable record. Other modes (Orchestrator-dispatched Executor) capture journey in commit messages and the plan's Notes section already; extending Implementation log to those modes is an option for the future, not v1.

The Implementation log does NOT violate ADR-017's "static SOW" principle for the W-item file. The log is appended at done-flip and is then static for the lifetime of the project. ADR-017 was about preventing Status drift via mid-flight runtime mutations of the W-item file. A done-flip append is a different shape and does not reintroduce drift bait.

#### Revision (v3.3, 2026-05-02): live working log + phase discipline

Field iteration after v3.1 surfaced the **QA-loop context bloat** failure mode: the Developer's persistent session linearly accumulates the full feature-build context plus every QA round-trip's investigation, and nothing in the existing loop sheds that mid-item. The user's heuristic of `/clear`-per-W-item bounded the cost per item but burned a full bootstrap reload (~12K tokens of Layer 0+1) per item. `/compact` was the cheaper alternative but required the agent to re-establish working context on every fire — cost-prohibitive if the role doc was the only re-read surface.

The fix is a durable on-disk artifact that survives `/compact`, so the persistent session can shed mid-item context aggressively without losing the journey:

1. **Live working log file.** Each Developer-claimed W-item gets a sibling `w-<id>.log.md` file in the plan folder, separate from the W-item SOW. Lazy creation at the `pending → in_progress` claim. Freeform chronological — Developer appends decisions, dead ends, fixes, retest outcomes, and **phase-transition markers** (`ready for QA`, `QA complete`) at every meaningful state change. Distilled into the Implementation log on the W-item file at `code_review → done`; the log file itself persists in the plan folder and archives with the plan.

   Separate file (option C in the design conversation) over single-file-with-embedded-log (option A: distill + remove) or both-on-W-item-file (option B): keeps the W-item file under its 200-line limit, preserves an honest chronological record permanently, and gives the Reviewer surface a clean exclusion (Reviewer reads diff + W-item file + `coding-standards.md`; never the working log).

2. **Session-level phase discipline.** `in_progress` covers two distinct session-level phases — **Build** (pre-QA) and **QA** (post-QA-handoff). Code Review is the third phase, the only one with its own on-disk Status state (`code_review`). The split is a session-level convention; **the on-disk Status machine is unchanged** — Build → QA transition has no Status flip. `developer.md` adds a `## Phase discipline` section with three subsections (Build / QA / Code Review), each a re-read target after `/compact`. The user `/compact`s at QA-handoff and again at QA-complete to renew discipline-doc context; the agent re-reads the matching subsection plus the working log to recover phase + working state.

3. **Reorient hook differentiation.** The `compact` branch of `.claude/hooks/session-reorient.sh` now tells a Developer to read its active W-item's working log file in addition to the role doc, and to ask the user which phase is current if unclear (the latest timestamped header in the log will name it). Other roles and other reorient sources are unchanged.

The QA back-and-forth (change-this-not-that, scope creep, refinement) is **acknowledged as reality but not formalized** — the working log absorbs it as it happens; the discipline doc says "user leads, you investigate, log as you go," not a tidy round-trip protocol.

**Why a separate file rather than embedding the log on the W-item file:**

Honest records are a project value, but the W-item file's 200-line limit is structural — it gates per-dispatch context cost (Reviewer reads it, Strategist re-reads it on triage, fresh sessions re-bootstrap it). A QA cycle with 10+ rounds easily exceeds 200 lines of chronological log. Embedding the log on the W-item file would either force the limit to soften (degrades the cost model for every reader) or force log-truncation (loses honest record). Separate file decouples: the W-item file stays bounded and reader-cheap; the working log grows freely and is read only by the Developer that owns the item.

**What this does NOT do:**

- Does not change the on-disk Status machine. `pending → in_progress → code_review → done → shipped` is unchanged. No `qa` state.
- Does not change Reviewer surface. Reviewer still reads diff + W-item file + `coding-standards.md`; not the working log.
- Does not extend to Orchestrator mode. Working log is Developer-mode only — Executor subagents are stateless and per-task, so a persistent log artifact has no consumer.
- Does not formalize the QA loop's content shape. The log is freeform; `/compact`-as-phase-transition is a usage pattern, not a Status-machine state.

**Surfaces updated in this revision:**

- `docs/execution-plans/README.md` — new artifact type (working log files), updated plan-folder structure diagram + naming bullet + new "## Working log files" spec section. Soft-edit to Implementation log description noting distillation source.
- `docs/dev_framework/developer.md` — new `## Phase discipline` section with Build / QA / Code Review subsections; "log as you go" rule lands inline in §Build and §QA.
- `.claude/hooks/session-reorient.sh` — `compact` branch updated with Developer-specific re-read target (working log + matching phase subsection + ask-user-if-unclear).

The mechanism (template + role-doc split + hook update) and the rule (working-log discipline + phase discipline) ship together — doctrine compliance.

### Invocation patterns: Default and Parallel

The Developer has two named invocations sharing one role doc, lifecycle, and discipline:

- **Default Developer** (`"you are the Developer"`) — works in the user's main checkout on a feature branch (`w-<id>/<slug>`). Bootstrap proposes the top critical-path `pending` item. The session the user collaborates with most actively.
- **Parallel Developer** (`"you are the parallel developer"`) — works in a worktree at `/tmp/worktrees/<project>/w-<id>-<slug>` (same path scheme as Orchestrator-mode Executors per ADR-013). Bootstrap does a **non-competing scan**: reads claimed items (Status `in_progress` or `code_review`, attributed in plan Notes), checks each `pending` item's `Touches` + Parallel-safe shared surfaces (per ADR-016 / `execution-plans/README.md` §"Parallel-safe field"), proposes the first non-conflicting item.

Why two invocations instead of one role with conditional behavior: the working-directory model is fundamentally different (in-place vs worktree) and the bootstrap scan is fundamentally different (critical-path vs non-competing). Conditional behavior in one role would require the session to ask "am I parallel or not?" at boot — fragile. Two named triggers make the user's intent unambiguous and the session's behavior deterministic from session start.

**Concurrent claim safety** is handled by PLAN-WRITE DISCIPLINE — read-fresh + commit + verify-pushed catches simultaneous claims at the push step, and the loser pulls + re-scans + picks something else. No new mechanism needed.

**N-Parallel sessions** (a third or fourth Parallel Developer alongside the Default) are mechanically supported — each in its own worktree, each does its own non-competing scan at boot. Diminishing returns past two because user attention serializes through the QA loop; documented but not optimized for.

**The "check dev" handoff** (Default Dev pulling Parallel's merged work into its own feature branch) is standard git: `git fetch origin dev && git merge origin/dev`. No framework-special protocol.

#### Revision (v3.2, 2026-05-01): non-competing scan reads the index alone

The original scan procedure inlined above ("reads claimed items, checks each `pending` item's `Touches` + Parallel-safe shared surfaces, proposes the first non-conflicting item") forced the Parallel Developer to fan out and read multiple W-item files at boot to assemble the data needed for collision detection. That defeated the context-budget rationale ADR-017 established for the index/SOW split — and worse, the bulk content couldn't be selectively evicted from the persistent session via `/compact`.

ADR-017 §Revision (v1.1) extends single-source doctrine to dependency data: a `Blocked by` column on the index replaces the W-item file's `Depends on` field, and the W-id stream-letter convention becomes load-bearing for non-competing detection (same letter = assumed code-path overlap; different letter = assumed non-competing).

Under v3.2, the Parallel Developer's scan reads the index alone:

1. Note claimed items' stream letters (the letter in `W-<stream><number>`).
2. For each `pending` item in critical-path order: skip if its stream letter matches a claimed item's; skip if any `Blocked by` entry on the index isn't `done`/`shipped`; otherwise propose.

`Touches` and `Parallel-safe considered` are no longer scan inputs. `Parallel-safe` (the field) narrows to Orchestrator batch-mode dispatch (ADR-016) only — Parallel Developer does not gate on it. The asymmetry is intentional: batch mode is autonomous and benefits from explicit infra-collision curation; Parallel Dev is user-supervised and a rare cross-stream infra collision surfaces as a merge conflict the user catches in the loop.

Canonical procedure: `dev_framework/developer.md` §"Non-competing scan (Parallel Developer)". Canonical data-model spec: `execution-plans/README.md` §"Summary table" + §"Index fields". The inline description above (this section's third bullet, "reads claimed items, checks each `pending` item's `Touches`...") is superseded.

### Five-surface role-add

Per the framework-change doctrine: adding a role updates five surfaces in one PR.

1. `docs/dev_framework/developer.md` — the role doc itself.
2. `CLAUDE.md` §Roles table — invocation trigger + bootstrap reads.
3. `docs/dev_framework/dev_framework.md` §Role docs — role row + brief mention in agent stack.
4. `docs/dev_framework/context-management.md` Layer 1 — bootstrap reading set, including `coding-standards.md` (Developer writes code, unlike Orchestrator/Strategist).
5. `.claude/hooks/session-reorient.sh` — add "developer" to the role-list strings in all four sources (startup / resume / compact / clear).

Plus the spec/doc updates:

6. `docs/execution-plans/README.md` — `code_review` state, transitions, Developer as Status writer, Implementation log section template, Mode field as advisory recommendation, §"Mode signaling (per item, not per phase)" with the v1→v2 walk-back rationale.
7. `docs/dev_framework/session-policy.md` §"Status ledger" — Developer as fourth writer.

## Consequences

**What this buys:**

- **First-class shape for conversational coding.** The user-in-the-loop mode now produces the same plan ledger, branches, and persistent record as Orchestrator mode. Work no longer has to fall outside the framework to be done conversationally.
- **Fresh-eyes code review without losing ownership.** The Reviewer subagent gives fresh-eyes review by being a separate process; the Developer remains the persistent owner because it spawned the Reviewer, reads the verdict, decides the merge, and writes the Implementation log. Same Reviewer brief Orchestrator-mode sequential dispatch uses (no new mechanism).
- **Documented journey on the project.** The Implementation log captures what actually happened — pivots, advisor calls, decisions reversed — in a place that survives session resets and shows up next to the W-item itself. Commit messages alone don't aggregate this.
- **Disciplined escalation.** The Developer follows an **80/20 confidence ladder** at decision forks (self ≥80% → act; self <80% → advisor or consultant subagent; advisor <80% → escalate to user), consistent with Integrator-QA's claim-filing threshold. Mechanizes "when to interrupt the user" so the dialogue stays high-signal. Detail in `developer.md` §"Confidence-driven escalation (80/20 rule)".

**What this costs:**

- **Fourth Status writer.** PLAN-WRITE DISCIPLINE now applies at four agent-types' write sites instead of three. Each must hold the discipline. Drift risk extends.
- **Two parallel modes for the same kind of work (coding).** Newcomers to the framework have to learn both. Mitigated by per-plan Mode field as the Strategist's recommendation + prompt-on-explicit-mismatch in both bootstraps. Per-W-item collision is naturally prevented by mode-specific Status paths.
- **Rewind harness-coupling.** The role's signature behavior depends on a Claude Code affordance. Adopters on other harnesses get a degraded role with the Reviewer-subagent fallback documented in `dev_framework_exceptions.md`.
- **W-item file template grows.** Fourth section (Implementation log) on the SOW file — unused in Orchestrator mode (or used optionally), populated in Developer mode. Adopters reading the template see a section that may not apply to their mode.
- **One more field on `plan.md`.** Mode adds a single line in the Executive summary. Cheap, advisory — Strategists set it explicitly when they have a recommendation; absent means no recommendation expressed (no penalty in v2).

**What this does NOT do:**

- **Does not change Orchestrator dispatch.** ADR-013 sequential mode and ADR-016 batch mode flow unchanged. The new state `code_review` does not appear in Orchestrator-mode lifecycles.
- **Does not change claim semantics.** ADR-016's claim shape and ADR-017's claim location unchanged. Developer becomes a second filer (after Integrator-QA), but the protocol is identical.
- **Does not deprecate the Reviewer subagent — extends its use.** Reviewer is spawned in Orchestrator sequential mode (ADR-013), absorbed by Integrator-QA in batch mode (ADR-016), AND now spawned by the Developer at `in_progress → code_review` (ADR-018 v3). Same brief, three invocation points.
- **Does not change phase exit gates.** Phase exit still requires QA against the dev environment + user authorization, regardless of mode. The Developer can run the phase-exit smoke pass itself or coordinate with the user to run it; the gate is not waived.

## Alternatives considered

1. **Developer as Orchestrator-dispatched Executor variant.** Rejected — subagents are stateless invocations; the user-mediated QA loop and the persistent Implementation-log discipline both require a session the user talks to directly across many turns. Developer must be a persistent role, not a dispatched subagent.
2. **Per-W-item `Mode` field on plan.md.** Rejected — once items lock into a mode at claim time via Status path (Developer's `in_progress → code_review → done` versus Orchestrator's `in_progress → done`), an explicit per-item field would be redundant. Notes-section claim attribution (`"W-A1 — claimed by Developer YYYY-MM-DD"`) covers at-a-glance ownership for in-flight items.

   **Per-plan binding Mode field with refuse-on-mismatch (original ADR-018 v1, walked back in v2).** Initially specified as the mechanism behind per-phase mode-exclusivity. Walked back after field testing showed it locked the Developer out of Strategist-drafted Orchestrator plans even when no W-item had been claimed. The actual collision boundary is per-W-item (enforced by Status paths), not per-plan. v2 reframes Mode as advisory with prompt-on-explicit-mismatch instead of refuse.
3. **Code-review via chat-rewind + blind self-review (original v1, walked back in v3).** Rejected after field testing. The rewind ritual was novel — same persistent session, different context via Claude Code's chat-rewind affordance — but cumbersome in practice (multi-step user UI gymnastics: rewind chat, paste summary, re-prompt). Replaced in v3 by spawning a Reviewer subagent on the diff, which gets the same fresh-eyes property via separate process at lower workflow cost. The "lose project context" concern about Reviewer subagents (the original v1 rejection rationale) was overstated — the Reviewer brief reconstructs project context from the W-item file + diff, the same artifacts a rewound self would read. See §"Revision (v3): rewind retired" below.
4. **Add a `qa` state.** Rejected — the user is the QA gate in real-time. State doesn't bounce between `qa` and `in_progress`; `in_progress` covers the whole loop until user confirmation. A separate `qa` state would never be observed long enough to matter.
5. **Universal Implementation log (all modes).** Deferred — Developer-mode-specific in v1 because that's where `/compact` collapses the persistent session's journey and the spawned Reviewer never sees it; the log is the only durable journey record. Easy to extend to Orchestrator mode if usage shows benefit.
6. **Skip ADR; document in role doc only.** Rejected — adding a role + state machine extension + new write authority is a load-bearing decision touching seven framework surfaces. Future readers need a single decision record explaining why.

## Acceptance criteria for the shipping PR

- `docs/dev_framework/developer.md` exists, describes the role's behavior end-to-end (bootstrap with Mode check, lifecycle, user QA loop, /compact + Reviewer-subagent code-review handoff, Implementation log, claim filing). Documents both invocation patterns (Default + Parallel) with a Non-competing scan procedure for Parallel.
- `CLAUDE.md` §Roles table has TWO rows — `"you are the Developer"` (Default) and `"you are the parallel developer"` (Parallel) — pointing at the same role doc.
- `docs/dev_framework/dev_framework.md` has Developer in the Role docs table; the agent-stack diagram or surrounding prose names it as a parallel mode.
- `docs/dev_framework/context-management.md` Layer 1 row for Developer names `coding-standards.md` + the active plan's `plan.md` as bootstrap reads.
- `.claude/hooks/session-reorient.sh` includes both `"you are the developer"` and `"you are the parallel developer"` in the role-list strings in all four sources (startup / resume / compact / clear).
- `docs/execution-plans/README.md`:
  - State machine adds `code_review`.
  - Transition table adds the Developer-owned transitions.
  - W-item file template adds the Implementation log section.
  - **Mode field** documented in the Executive summary spec as the Strategist's advisory recommendation (allowed values `orchestrator` / `developer` / absent; prompt-on-explicit-mismatch in both bootstraps; mixed-mode phases allowed).
  - Status state count updates to **seven** (`pending`, `in_progress`, `code_review`, `held`, `blocked`, `done`, `shipped`).
  - Claim-filer set expanded (Integrator-QA OR Developer) in §"Integration claims" + Filed-by template.
- `docs/dev_framework/session-policy.md` §"Status ledger" lists Developer as a fourth writer with the transition set.
- `docs/dev_framework/strategist.md` updates the claim-filer set in the Integration-claims-triage bullet (Integrator-QA OR Developer).
- `docs/dev_framework/templates/orchestrator-bootstrap.md`:
  - Multi-writer note expanded to four writers including Developer-mode transitions.
  - **STEP 0 MODE CHECK** added between PRELUDE format detection and the ledger-reconciliation paragraph; refuses on `Mode: developer`.
- One PR. Half-shipping any of these creates an incoherent intermediate state — agents read a role doc that names a state the spec doesn't define, or vice versa.
