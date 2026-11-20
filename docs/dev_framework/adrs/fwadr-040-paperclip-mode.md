# FWADR-040: Paperclip is an execution layer; the roles stay single-sourced

**Status:** accepted
**Date:** 2026-11-08
**Deciders:** user (framework author) + Template Developer

## Context

thankmu ran its engineering for two days through a Paperclip agent (a board of issues,
agents that wake on assignment, question cards for the human). The agent's work merged
after a read; what cost operator time was everything the framework had no reading for:
"the Orchestrator dispatches an Executor", "ask the user", "wait for approval", "the
Reviewer subagent" all assume a chat session with a human in it. The first fix tried was
one Paperclip agent per role with the role docs **copied** into its instructions —
200 KB of duplicated doctrine per company that was stale the moment the template moved.
Paperclip's own answer to shared agent definitions is the Agent Companies package
(`agentcompanies/v1`): markdown files, external content referenced at a pinned commit,
skills in the Agent Skills format, upgrade as an explicit act.

On 2026-11-08 six `FW_*` agents ran a full day on that board. The mode document then made
every merge a human's: finished work sat in the human's queue for more than five hours,
and planning changes stacked on branches no other agent could read. The founder's working
model is the opposite: agents merge as they go, the human tests hands-on at the end of an
epic or phase, and only the release is the human's. A narrower rule that still kept CI
configuration and deploy scripts for the human stalled ThankMu the same way: one harness
MR waited eleven days, and by 2026-11-19 ten issues were in review and five blocked
behind two MRs that touched a pipeline file.

## Decision

1. **Paperclip is an execution layer, not a second framework.** The role docs are the
   roles. Nothing is rewritten for Paperclip; a Paperclip agent for a role is a
   **reading list** (the project's `CLAUDE.md`, its exceptions file, the role's Layer-1
   docs at the template's `main`) plus one mode document.
2. **One mode document, [`paperclip-mode.md`](../paperclip-mode.md),** holds every
   substitution: ask-the-user → question card; approval → first comment, then proceed;
   spawn → the same issue, reassigned; Reviewer → a checklist the Orchestrator applies before it merges;
   PR handoff → comment with the deep link;
   plus the record rule (git is the record, Paperclip is the queue; two issue classes),
   the carve-outs (working notes live on the issue between milestones and reach the W-item
   log at every milestone, not only at close), the delegation policy for cards, session
   hygiene, and the rules against waiting and pondering: act at 80% confidence, verify a
   claim once, close the issue before any optional waiting, never end a run with a
   background process alive, screenshots as part of done for anything visible. Each role
   doc carries a four-line "Under Paperclip mode" pointer, nothing more.
3. **The framework publishes itself as a company package** at [`paperclip/`](../../../paperclip/)
   in this repo: `COMPANY.md`, one `agents/fw-<role>/AGENTS.md` per role, the
   `dev-framework` skill, the recurring alignment task. Agents are named `FW_<Role>`.
   One framework project = one Paperclip company; a project's overrides (its `CLAUDE.md`,
   `dev_framework_exceptions.md`) are read from its planning repo at run start, never
   copied into the package.
4. **Framework updates are always pumped in.** The user: "I don't care if an agent is in
   progress, I think framework updates need to always be pumped in. That is how it has
   always worked, that on compact or clear the framework got updated; why would that be
   different for paperclip?" Agents fetch their role docs from the template's `main` once
   at the start of every run, so a change reaches them at their next run and a run under
   way keeps what it started with. The package itself (an agent's file, a routine) is
   re-rendered by `scripts/paperclip_company.py sync`, which the Paperclip Lead's
   four-hour routine runs unasked whenever `status` reports drift; the Curator's daily
   task is the backstop and the session-start sync NOTICEs on drift. A pin that gated
   updates left one project's agents five commits behind for a day. The cost, accepted: a
   bad framework commit is live in every company at its agents' next run.
5. **Agents merge; the release is the human's.** The planning repo's `main` is everyone's
   shared page: any agent writing to it opens an MR and merges it itself at once, the MR
   staying as the record — no stacked or long-lived planning branches. In a code repo the
   Orchestrator merges to `main` once its gates pass (reviewer checklist,
   QA evidence including screenshots, CI green); the human works the checklist in the QA view on dev at the end of
   an epic or phase and approves the release there. **The release tag is never an agent's.** That covers every MR, CI configuration and deploy and
   release scripts included: a merged pipeline change reaches dev at once, which is
   accepted, and production is protected because only the release tag deploys it. One
   thing stays with the human short of the release: an ADR is `proposed` until the human
   accepts it. `env.yaml` is not a merge rule at all — only the operator's machine holds
   its key ([FWADR-041](fwadr-041-env-yaml.md)).
6. **The Parallel Developer is the one builder; there is no `FW_Developer`.** Every run
   on a board gets its own worktree, which suits the Parallel Developer and removes what
   sets the Default Developer apart: working in the main checkout, with no worktree, fast,
   on urgent, precise or admin work. That stays a chat session. On 2026-11-08, when every
   item went to an `FW_Developer` in a shared checkout, the runs collided.
7. **One ticket stays one ticket.** Only the Strategist creates tickets, and only while
   triaging a ticket the human created; that is where work is split. No other agent
   creates a ticket: an issue changes hands by reassignment, a stuck issue is `blocked`
   with a card, and anything else an agent finds is a `found:` line for the Strategist.
   Triage is a back-and-forth with the human, and nothing is created until they agree the
   breakdown. A ticket is a concrete programming objective that is planned and thought
   out — one repo, one checkable outcome, acceptance needing no further questions,
   dependencies ahead — small ideally, medium or large sometimes.
   Sequence inside a ticket is wanted: "finish this, then do that" is one ticket carrying
   more than one MR, not a reason for tickets to divide.
   The case that decided it (2026-11-19): one request — a dev and a production build of
   a plugin — split by the agent working it into a hard part and an easy part, the easy
   part blocked on the hard part, the hard part circling for hours and opening workaround
   tickets, fourteen stuck tickets in all, each with its own run history and cost.

8. **Git is the agent's memory, not the chat.** On a remote agent host no run resumes an
   earlier conversation (each run gets its own working directory), and a pause or a
   tripped budget cancels the live run. So an agent checkpoints at every meaningful step
   and at least every 15 minutes: work in progress pushed to the ticket's branch, and a
   short resume note rewritten in the planning repo. A resuming run reads the ticket, the
   note and the branch, not the reading list. Stopping is cooperative: "checkpoint and
   stop", and the agent ends its own run.

## Consequences

- **Mechanism:** `paperclip_company.py` (framework-owned stub) renders the package into
  a company and says when the package is behind; `sync-framework.sh` 5f runs the check;
  the Paperclip Lead's routine and the `framework-alignment` task run the sync from inside
  Paperclip. The reading-list shape means a framework change needs no agent change at
  all: the next run reads it.
- **Mechanism for 5:** the git host. The bot's permissions allow merging MRs into the
  planning repo's `main` and a code repo's `main`; tag protection
  reserves the release tag to the `release` job and the human (adoption step 3 in `paperclip-mode.md`, interview
  Block 4). The pre-push guard does not run on the agent host.
- **Named gap:** "no agent writes `accepted`" is English-only.
- **Named gap:** the checkpoint interval is English-only; the Paperclip Lead's look at each
  live run (a recent push, a current note) and the Reviewer's check that the note names
  the final commit are what notice a run that is not checkpointing. Unproven: no run has
  yet resumed from a note.
- **Named gap:** "only the Strategist creates a ticket" is English-only unless the board
  can deny issue creation per agent; where it can, deny it to every `FW_*` agent but
  `FW_Strategist`. Reassignment by an agent is assumed to wake the assignee; not yet
  exercised.
- What waits on the human — a release, and the feedback that precedes it — is in one
  place: the QA view on dev ([FWADR-042](fwadr-042-qa-view-release.md)). Cards stay on
  the board.
- **Named gap:** the act-at-80% rules and the end-of-run order are English-only; the
  evidence is the issue itself (first comment early, final comment before the exit).
- **Named gap:** "a work issue names a W-item and ends with an MR that moves it" is
  English-only until the Orchestrator's reconciliation reads the Paperclip API (listed
  in `paperclip-mode.md` §"Record"); accepted, the Curator's divergence report is the
  backstop.
- **Coherence surfaces:** this ADR; `paperclip-mode.md`; the five role docs' pointer
  sections; `dev_framework.md` §"Paperclip mode"; `context-management.md` Layer 1;
  CLAUDE.md managed block; `first-contact-interview.md` Block 4; `.env.example`
  (`PAPERCLIP_*`); `sync-framework.sh` 5f; the `paperclip/` package; the stub script;
  `templates/reviewer-brief.md` (`env.yaml` line).
