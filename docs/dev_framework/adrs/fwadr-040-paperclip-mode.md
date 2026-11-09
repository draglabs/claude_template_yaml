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
epic or phase, and only the release is the human's.

## Decision

1. **Paperclip is an execution layer, not a second framework.** The role docs are the
   roles. Nothing is rewritten for Paperclip; a Paperclip agent for a role is a
   **reading list** (the project's `CLAUDE.md`, its exceptions file, the role's Layer-1
   docs at a pinned framework commit) plus one mode document.
2. **One mode document, [`paperclip-mode.md`](../paperclip-mode.md),** holds every
   substitution: ask-the-user → question card; approval → first comment, then proceed;
   spawn → child issue; Reviewer → a checklist the Orchestrator applies before it merges;
   PR handoff → comment with the deep link;
   plus the record rule (git is the record, Paperclip is the queue; two issue classes),
   the carve-outs (working notes live on the issue between milestones and reach the W-item
   log at every milestone, not only at close), the delegation policy for cards, and session hygiene. Each role
   doc carries a four-line "Under Paperclip mode" pointer, nothing more.
3. **The framework publishes itself as a company package** at [`paperclip/`](../../../paperclip/)
   in this repo: `COMPANY.md`, one `agents/fw-<role>/AGENTS.md` per role, the
   `dev-framework` skill, the recurring alignment task. Agents are named `FW_<Role>`.
   One framework project = one Paperclip company; a project's overrides (its `CLAUDE.md`,
   `dev_framework_exceptions.md`) are read from its planning repo at run start, never
   copied into the package.
4. **Pinned, bumped deliberately.** A company's agents point at one framework commit.
   `scripts/paperclip_company.py status` compares that pin with the template's `main`;
   `sync` bumps it. The session-start sync NOTICEs on drift for any project with
   `PAPERCLIP_API_URL` in its operator `.env`; the package's recurring task has
   `FW_Curator` run the same check daily and report, so a project nobody opens still
   learns it is behind. Live-mounting the template on the Paperclip server was rejected:
   a bad framework commit would be live in every company at once.
5. **Agents merge; the release is the human's.** The planning repo's `main` is everyone's
   shared page: any agent writing to it opens an MR and merges it itself at once, the MR
   staying as the record — no stacked or long-lived planning branches. In a code repo the
   Orchestrator merges to the integration branch once its gates pass (reviewer checklist,
   QA evidence including screenshots, CI green); the human does hands-on E2E at the end of
   an epic or phase. **The release ref — a push to `main` under dev-main, a `v*` tag under
   trunk — is never an agent's.** Two things stay with the human short of the release: an
   ADR is `proposed` until the human accepts it, and no agent merges an MR that touches
   the machinery (CI configuration, secrets files, deploy or release scripts), because a
   merge to a protected branch runs that branch's CI with its protected variables.
6. **The Parallel Developer is the default builder.** The Orchestrator dispatches to
   `FW_Parallel_Developer` — each run in its own worktree, never in the shared checkout,
   which is what collided on 2026-11-08 when every item went to `FW_Developer`.
   `FW_Developer` is reserved for issues the human assigns directly: emergencies, admin,
   hotfixes, work the founder wants to watch live. The Orchestrator sets itself as the
   task watchdog of every issue it dispatches under, so Paperclip wakes it when the
   children come to rest; that wake is the sweep for stuck issues, and no recurring task
   does it.

## Consequences

- **Mechanism:** `paperclip_company.py` (framework-owned stub) renders the package into
  a company and checks the pin; `sync-framework.sh` 5f runs the check; the
  `framework-alignment` task runs it from inside Paperclip. The reading-list shape means
  a framework change needs no agent change — only a pin bump.
- **Mechanism for 5:** the git host. The bot's permissions allow merging MRs into the
  planning repo's `main` and a code repo's integration branch; branch and tag protection
  reserve the release ref to the human (adoption step 3 in `paperclip-mode.md`, interview
  Block 4). The pre-push guard does not run on the agent host.
- **Named gap:** "no agent merges a machinery MR" and "no agent writes `accepted`" are
  English-only where the host has no per-path approval rule; the Reviewer checklist names
  a machinery diff on its first line.
- **Named gap:** "a work issue names a W-item and ends with an MR that moves it" is
  English-only until the Orchestrator's reconciliation reads the Paperclip API (listed
  in `paperclip-mode.md` §"Record"); accepted, the Curator's divergence report is the
  backstop.
- **Coherence surfaces:** this ADR; `paperclip-mode.md`; the five role docs' pointer
  sections; `dev_framework.md` §"Paperclip mode"; `context-management.md` Layer 1;
  CLAUDE.md managed block; `first-contact-interview.md` Block 4; `.env.example`
  (`PAPERCLIP_*`); `sync-framework.sh` 5f; the `paperclip/` package; the stub script;
  `templates/reviewer-brief.md` (machinery line).
