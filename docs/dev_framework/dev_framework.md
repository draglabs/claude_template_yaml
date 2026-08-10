# Dev framework

The SOP for how agents operate on this repo. One doc, pointers to the rest.

Linked from `CLAUDE.md`; every session reads CLAUDE.md at start, then loads what its role needs from here.

## What this is

A multi-instance model where four **product-side** persistent Claude Code sessions coordinate via git (PRs and branches), each with a narrow context budget:

- **Strategist** — the architect. Owns planning docs and operational docs (runbooks, SOPs, checklists). Doesn't read code. Writes the artifact the user named, at the path they named; a missing ADR is a question for the user, not work to create ([FWADR-025](adrs/fwadr-025-named-deliverables.md)).
- **Designer** — owns UI mockups. Writes only to `mockups/`.
- **Orchestrator** — dispatches implementation work and coordinates peer review gates. Doesn't write code (except emergency bypass — see [`session-policy.md`](session-policy.md) §"When to suspend this policy").
- **Developer** — user-invoked persistent session for hands-on coding work; user-mediated QA loop + spawned Reviewer subagent for the code-review gate ([FWADR-018](adrs/fwadr-018-developer-role.md)). Two named invocations: **Default** (`"you are the Developer"`, works in main checkout on a feature branch) and **Parallel** (`"you are the parallel developer"`, works in a worktree, runs alongside Default on a non-competing item). Parallel mode to Orchestrator dispatch; mixed-mode phases allowed (per-item mode locking via Status path).

A fifth product-side session audits the corpus the other four produce:

- **Curator** ([FWADR-026](adrs/fwadr-026-curator-role.md)) — episodic doc-cleanup session that identifies over-churned ADRs (high commit-churn = the project is *fighting* a decision, not following it), dead ADRs nothing references, closed plans and `done` tickets to archive, and exceptions past their retire-when criterion. It exists because the **Strategist authored the corpus** and its disposition ("treats docs as load-bearing," "protective of scope") biases toward conservation; the Curator holds the opposite incentive by design. **Proposes, never disposes** — per-item user confirmation. Fenced out of `docs/dev_framework/*` (mechanically, via `scripts/check-curator-scope.sh`) because those files are destructively re-synced; framework findings become `fwreq-*` requests routed to the Template Developer. See [`curator.md`](curator.md).

An optional sixth product-side session exists for projects that configure it:

- **Researcher** ([FWADR-024](adrs/fwadr-024-researcher-role.md)) — finds and acquires content/data missing from the project's corpus and delivers it through the project's sanctioned intake. **Finder, not a builder**: write scope is one named directory (mechanical pre-merge check via `scripts/check-researcher-scope.sh`), the server API is an opaque contract (capability gaps become `req-*` server-work requests the Strategist triages, never server-side edits), merges to `dev` only. Refuses to bootstrap unless the project has set its parameters. See [`researcher.md`](researcher.md).

Work gets done via two parallel modes — **a phase runs end-to-end under one mode**:

- **Orchestrator dispatch** (default, autonomous): the Orchestrator spawns an **Executor** (who writes + commits), then spawns a **Reviewer** and, when required, a **QA** as peer subagents of the Executor. The Orchestrator owns the retry loop — on a Reviewer `block` or QA `fail`, it runs an Executor fix cycle with the concerns as sharpened context (continuation via SendMessage by default; fresh dispatch for approach-level blocks — [FWADR-022](adrs/fwadr-022-runtime-recalibration.md)). See [`session-policy.md`](session-policy.md) §"Dispatch flow" and [FWADR-013](adrs/fwadr-013-peer-dispatch.md) for the full model and rationale.
- **Developer mode** (hands-on, user-in-loop): the user invokes the Developer directly. Developer codes one W-item at a time conversationally, runs a user-mediated QA loop inside `in_progress` (no separate `qa` state), then at user-confirmation runs `/compact` and spawns a Reviewer subagent on the diff for the code-review gate. The Developer remains the persistent owner end-to-end (claim → code → user-QA → /compact → Reviewer dispatch → merge → Implementation log). A per-W-item **working log file** (`w-<id>.log.md`) preserves the chronological journey across `/compact` boundaries and is distilled into the Implementation log at the `code_review → done` flip ([FWADR-018](adrs/fwadr-018-developer-role.md) Revision v3.3). See [`developer.md`](developer.md) and [FWADR-018](adrs/fwadr-018-developer-role.md).

Outside the product-side stack entirely, the **Template Developer** maintains the canonical `claude_template_yaml` repo itself (the framework docs, hooks, ADRs, and managed CLAUDE.md block that every adopter inherits via destructive sync). It is only meaningful when operating in the template repo; in adopter repos the role is inert and framework changes are made by opening a PR against the template. Template Developer sits outside the product-side stack — it does not dispatch Executors, does not produce product artifacts, and does not interact with the four product-side roles during a session. See [`template-developer.md`](template-developer.md) and [FWADR-015](adrs/fwadr-015-template-developer-role.md).

## The agent stack

```
User ↔ Strategist          (doc-only, opens planning: PRs)
User ↔ Designer            (mockups/ only, opens design: PRs)
User ↔ Orchestrator        (dispatcher + review coordinator + merger)
           │
           ├─▶ Executor (work tier, worktree off `dev`) ── code-only return
           │
           ├─▶ Reviewer (top tier)                      ── verdict to Orchestrator
           │       │
           │       └─ block? Orchestrator retries the Executor (continuation
           │         or fresh dispatch, per session-policy); retries capped
           │         per tier
           │
           ├─▶ QA (work tier, when required)            ── verdict to Orchestrator
           │       │
           │       └─ fail? same retry loop
           │
           ▼  all gates green
       Orchestrator ──▶ merge to `dev` ──▶ push ──▶ auto-advance
                                                       │
                         (when phase complete ─────────┘
                          + phase-exit QA + user OK)
                                │
                                ▼
                        merge `dev` → `main`
                                │
                                ▼
                     production CI deploy
```

Every subagent is a peer under the Orchestrator — no subagent spawns another subagent (hard constraint of the Claude Agent SDK; see [FWADR-013](adrs/fwadr-013-peer-dispatch.md)). The Orchestrator never opens diffs or source files; it reads Reviewer, QA, and Integrator-QA verdicts (which cite `file:line`). Main only moves at phase-exit promotion.

The stack above shows sequential (per-task) Orchestrator dispatch. For W-items marked `Parallel-safe: true` on the plan, the Orchestrator uses **batch mode** ([FWADR-016](adrs/fwadr-016-batch-mode-integrator-qa.md)): up to ~3 Executors dispatched concurrently, followed by a single **Integrator-QA** (top tier, long-context) call that absorbs per-task Reviewer + pre-merge QA for the batch, writes fix commits within acceptance, files integration claims for scope changes (routed through Strategist + user), and merges the clean items to dev. Sequential mode and batch mode coexist within Orchestrator dispatch — the choice is per-item at dispatch time, based on the `Parallel-safe` field.

**Developer mode** ([FWADR-018](adrs/fwadr-018-developer-role.md)) is a parallel mode to the Orchestrator dispatch chain shown above. The user invokes the Developer directly. The user is the QA gate (real-time, in the loop, throughout `in_progress`); a **spawned Reviewer subagent** is the code-review gate (fresh process, sees only the diff + W-item brief). The Developer codes one W-item at a time, runs the user-mediated QA loop, optionally `/compact`s its session context at user-confirmation, then dispatches the Reviewer brief and acts on the verdict. State machine adds one state, `code_review`, that exists only in Developer-mode lifecycles. **Mixed-mode phases are allowed** — items lock into a mode at claim time via the Status path they take, so Orchestrator-driven items and Developer-driven items can coexist on the same plan with no per-plan exclusivity. The plan's `Mode` field is the Strategist's recommendation, not a lock.

## Role docs

| Role | Doc | Session-start reads |
|---|---|---|
| Strategist | [`strategist.md`](strategist.md) | strategist.md + planning docs |
| Designer | [`designer.md`](designer.md) | designer.md + main app UI components |
| Orchestrator | [`session-policy.md`](session-policy.md) | session-policy.md + active execution plan |
| Developer (Default and Parallel) | [`developer.md`](developer.md) | developer.md + coding-standards.md + active plan's plan.md. Two invocations sharing one doc: Default in main checkout, Parallel in a worktree |
| Researcher (optional, per-project) | [`researcher.md`](researcher.md) | researcher.md + the project's Researcher parameters entry in `dev_framework_exceptions.md` + the acquisition reading list it names. Refuses to bootstrap unconfigured. No coding-standards.md, no app/api source |
| Curator | [`curator.md`](curator.md) | curator.md + `dev_framework_exceptions.md`, then runs `./scripts/doc_churn_audit.sh`. Episodic — summoned at phase boundaries. Does NOT preload `docs/architecture/` or `docs/execution-plans/`; the script names the few docs worth opening |
| Template Developer | [`template-developer.md`](template-developer.md) | template-developer.md + dev_framework.md (template repo only; no-op in adopter repos) |

Subagent briefs (load on spawn, not at session start):

| Role | Brief | Spawned by |
|---|---|---|
| Executor | [`templates/executor-brief.md`](templates/executor-brief.md) | Orchestrator (both modes) |
| Reviewer | [`templates/reviewer-brief.md`](templates/reviewer-brief.md) | Orchestrator — **sequential mode only**, peer of Executor |
| QA | [`templates/qa-brief.md`](templates/qa-brief.md) | Orchestrator — per-W-item pre-merge (**sequential mode only**), phase exit (both modes), post-promotion smoke (both modes) |
| Integrator-QA | [`templates/integrator-qa-brief.md`](templates/integrator-qa-brief.md) | Orchestrator — **batch mode only**, end of parallel batch; absorbs per-task Reviewer + pre-merge QA |
| Doc Consultant | [`templates/doc-consultant-brief.md`](templates/doc-consultant-brief.md) | Any role |
| Code Consultant | [`templates/code-consultant-brief.md`](templates/code-consultant-brief.md) | Primarily Strategist |
| Strategist (bounded doc work) | [`templates/strategist-brief.md`](templates/strategist-brief.md) | Developer or Orchestrator — the only sanctioned **write-capable** doc subagent. Does NOT read `strategist.md`; may return a question instead of completed work ([FWADR-025](adrs/fwadr-025-named-deliverables.md)) |
| Orchestrator bootstrap | [`templates/orchestrator-bootstrap.md`](templates/orchestrator-bootstrap.md) | User, in a fresh session |

## Enforced practices

| Concern | Canonical doc | Who loads it |
|---|---|---|
| Execution policy (tiers, retries, escalation) | [`session-policy.md`](session-policy.md) | Orchestrator |
| Coding standards (TDD, no hardcoded values, fail loudly) | [`coding-standards.md`](coding-standards.md) | Executor + Reviewer (never Orchestrator or Strategist) |
| Context budget (what each role loads) | [`context-management.md`](context-management.md) | Reference — loaded on demand |
| Approved MCPs (tools each role uses; config + health owned by Strategist) | [`approved-mcps.md`](approved-mcps.md) | Reference — loaded when adding or evaluating an MCP; Strategist runs the session-start health check per [`strategist.md`](strategist.md) §"MCP health check" |
| Dev environment (local vs remote `{{sub}}.dev.{{website}}.com`) | [`dev-environment.md`](dev-environment.md) | Orchestrator on first-time setup; loaded on demand otherwise |
| Process exceptions (raw field reports from agents) | [`process-exceptions.md`](../framework_exceptions/process-exceptions.md) | Appended to by any agent that hits process friction; read by Strategist at phase boundaries |
| Process incidents (analyzed: root cause + fix) | [`execution-incidents.md`](../framework_exceptions/execution-incidents.md) | Promoted from process-exceptions by Strategist when an entry warrants full post-mortem |

## PR-based handoff between instances

| Instance | Coordinates via |
|---|---|
| Strategist | Opens `planning:` PRs with feature specs and roadmap changes |
| Designer | Opens `design:` PRs with mockup concepts (user approves before actionable) |
| Orchestrator | Reads `planning:` and `design:` PRs via the host CLI (`gh pr list --label` / `glab mr list --label`), merges to acknowledge, then dispatches Executors on `w-<id>/<slug>` branches |

This is async-safe: each instance operates on its own surface, signals work via PR labels, and never blocks the others.

### Git-host neutrality

The framework's git policy is **host-neutral**. GitHub and GitLab (including self-hosted) are both first-class; nothing in the branch model, the PR-based handoff, or the merge gates assumes one host. Concretely:

- **"PR" is generic.** Wherever framework docs say "PR", read pull request (GitHub) or merge request (GitLab) — same object, same role in the workflow. Labels, descriptions-as-briefs, and merge-to-acknowledge all work identically on both.
- **`GIT_HOST` in `$PROJECT_DIR/.env` names the project's host** (`github` | `gitlab` | `other`; plus `GIT_HOST_URL` for self-hosted). It is set by the Strategist's first-contact interview — asked, never assumed, because a user may run different hosts for different projects and a repo created on the wrong host is expensive to unwind.
- **Git auth is `.env`-driven and host-symmetric ([FWADR-030](adrs/fwadr-030-git-auth-recipe.md)).** A project declares `GIT_HOST` plus a host token (`GH_TOKEN` / `GITLAB_TOKEN`) in `.env`; sourcing `.env` at launch (`set -a; source .env`) auto-wires `git` over HTTPS to that host's CLI credential helper (`gh` / `glab`), session-scoped and written to no gitconfig. The github and gitlab branches are mirrors, and `GIT_HOST_URL` makes self-hosted (GitHub Enterprise / self-managed GitLab) first-class on both — no host is a privileged default. Requires HTTPS remotes; SSH remotes authenticate by key via `~/.ssh/config` instead.
- **Host commands are qualified, not defaulted.** Before reaching for a host CLI (`gh` / `glab`) or host MCP (github / a GitLab server), check `GIT_HOST`. Framework docs that show `gh ...` examples are showing the GitHub instantiation of a host-neutral step; substitute the `glab` equivalent when `GIT_HOST=gitlab`.
- **Policy is stated in git terms.** Branches, merges, tags, remotes, labels — not "GitHub" terms. A doc or plan that says "GitHub" where it means "the project's git host" is naming drift; the Strategist's alignment audit catches it.
- **`GIT_HOST=other`** means the workflow needs a documented mechanism: record how PRs/MRs (or their equivalent) work in `dev_framework_exceptions.md`.

## Branch model

```
feature  ──▶  dev  ──(phase exit + user authorizes)──▶  main
              │                                          │
              ▼                                          ▼
     dev environment                            production
     (local or remote)                          (always CI-deployed)
```

Feature branches merge to `dev` per W-item (Orchestrator decision). Dev promotes to `main` only at phase-exit, gated by QA against `{{sub}}.dev.{{website}}.com` and explicit user authorization. See [`session-policy.md`](session-policy.md) §"Branching and isolation" and §"Phase exit gate."

Pushing `main` is mechanically blocked by a git pre-push guard installed on every SessionStart sync ([FWADR-023](adrs/fwadr-023-main-push-guard.md)); the only sanctioned push path is `scripts/promote_dev_to_main.sh` (default = phase-exit promotion, `--bypass` = emergency path).

## Two process rules (every session)

1. **Docs before code — for *additions*.** Architectural additions get documented by the Strategist and merged before the Orchestrator dispatches implementation. Enforced at the merge boundary by the Reviewer (`block` if no matching doc) and at the phase boundary by the Strategist's alignment audit. **This does NOT make an existing ADR outrank a live instruction from you.** When your instruction conflicts with an accepted ADR, the resolution is *doc-follows-instruction*: the deviation is recorded on the W-item, the review gate reports `doc-conflict` rather than blocking, and the ADR is **rewritten** (never appended to) to state the decision that now holds — or escalated to you if your intent isn't clear. The ADR log is living architecture, not doctrine ([FWADR-027](adrs/fwadr-027-living-architecture.md)).
2. **CI-only deploys to production.** Production changes land via `git push origin main` → CI. Never from a laptop. Never via `docker exec`. Dev environment behavior depends on mode — see [`dev-environment.md`](dev-environment.md).

Code-level rules (TDD, no hardcoded lifecycle values, fail loudly) live in [`coding-standards.md`](coding-standards.md) and are enforced by the Executor (writing) and Reviewer (checking) subagent briefs. The Orchestrator and Strategist do NOT load that doc — they delegate enforcement to the subagent layer.

## When to suspend the SOP

See [`session-policy.md`](session-policy.md) §"When to suspend this policy" — emergency bypass rules, policy edits, and the explicit user override.

## The idea in one paragraph

The four persistent sessions keep their context focused on their own surface — docs (Strategist), UI (Designer), dispatch + review coordination (Orchestrator), hands-on coding (Developer) — and the optional Researcher, where a project configures it, keeps to its acquisition surface the same way. For Orchestrator-mode phases, heavy thinking about code happens inside bounded peer subagents — Executors write, Reviewers judge, QA verifies — each spun up fresh per gate call; the Orchestrator's context grows with each W-item but only as much as structured verdicts require (not diff content), keeping it bounded. For Developer-mode phases (FWADR-018), the Developer codes directly, the user mediates QA in the loop, and a Reviewer subagent (same brief as Orch-mode sequential dispatch) covers the code-review gate; `/compact` at the QA-pass moment keeps the persistent session bounded across items. Either way, failed items surface as short "stumped" packages the user can address in one exchange, and successful items surface as merge commits — Orchestrator-mode commits carry the Reviewer's verdict + Executor's lessons; Developer-mode commits carry the Implementation log on the W-item file. Both land in `git log` where the user reads them.
