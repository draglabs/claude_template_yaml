# FWADR-040: Paperclip is an execution layer; the roles stay single-sourced

**Status:** accepted
**Date:** 2026-11-07
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

## Decision

1. **Paperclip is an execution layer, not a second framework.** The role docs are the
   roles. Nothing is rewritten for Paperclip; a Paperclip agent for a role is a
   **reading list** (the project's `CLAUDE.md`, its exceptions file, the role's Layer-1
   docs at a pinned framework commit) plus one mode document.
2. **One mode document, [`paperclip-mode.md`](../paperclip-mode.md),** holds every
   substitution: ask-the-user → question card; approval → first comment, then proceed;
   spawn → child issue; Reviewer → human merge; PR handoff → comment with the deep link;
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

## Consequences

- **Mechanism:** `paperclip_company.py` (framework-owned stub) renders the package into
  a company and checks the pin; `sync-framework.sh` 5f runs the check; the
  `framework-alignment` task runs it from inside Paperclip. The reading-list shape means
  a framework change needs no agent change — only a pin bump.
- **Named gap:** "a work issue names a W-item and ends with an MR that moves it" is
  English-only until the Orchestrator's reconciliation reads the Paperclip API (listed
  in `paperclip-mode.md` §"Record"); accepted, the Curator's divergence report is the
  backstop.
- **Coherence surfaces:** this ADR; `paperclip-mode.md`; the five role docs' pointer
  sections; `dev_framework.md` §"Paperclip mode"; `context-management.md` Layer 1;
  CLAUDE.md managed block; `first-contact-interview.md` Block 4; `.env.example`
  (`PAPERCLIP_*`); `sync-framework.sh` 5f; the `paperclip/` package; the stub script.
