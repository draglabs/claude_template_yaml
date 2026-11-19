# Paperclip mode: how the roles are played from an issue

[Paperclip](https://github.com/paperclipai/paperclip) is a board: issues, agents that wake
when assigned, question cards for the human, comments as the conversation. The framework's
roles were written for a chat session with the user in it. This document is the whole
difference. A role doc stays the role; where it says one of the things in the left column,
a Paperclip agent does the thing in the right column. Decided in
[FWADR-040](adrs/fwadr-040-paperclip-mode.md).

## Substitutions

| Role doc says | On Paperclip |
|---|---|
| "ask the user" / "Anything else?" | Raise a **question card**: options with evidence, each with Confidence and Difficulty, the recommendation first, last item "Anything else?". Never block on chat. |
| "report your understanding and wait for approval" | Post the bootstrap report as the **first comment** on the issue and proceed. Stop and wait only if the issue says `approve-first` or the report finds a conflict. |
| "spawn an Executor" (Orchestrator) | **Reassign the same issue** to `FW_Parallel_Developer`, the Executor brief as a comment. It comes back to you by reassignment when the MR is open. Never a child issue (§"One ticket stays one ticket"). |
| "spawn a Reviewer" (Orchestrator) | Apply `templates/reviewer-brief.md` as a checklist in an MR comment: `approve` / `request changes` / `block` / `doc-conflict`. On `approve`, with QA evidence posted and CI green, **merge the MR to `main` yourself** (§"Who merges"). |
| "spawn a Reviewer" (Developer) | Unchanged — the local Reviewer subagent still runs before the MR opens. The Orchestrator merges it; on an issue the human assigned you directly, you merge it yourself once the Reviewer ships and CI is green. |
| "the user is the QA gate" (Developer) | Post the evidence (commands, output, screenshots) as a comment; a card only where a human must choose. |
| "hand off the PR" | The end-of-run comment carries the deep link: `Review MR <n> (W-<id>): <url>`. The comment is the handoff to the Orchestrator (§"Who merges"). |
| "`/compact`", "fresh session" | A run is a session. State that must outlive the run is in the issue (comments) or in git (MR, W-item log) — nowhere else. |
| "worktree at `/tmp/worktrees/…`" (Parallel) | Same path, off the workspace checkout Paperclip gives the run, never in the checkout itself. |
| "push the release tag" / "deploy production" | **Never.** The release tag is the human's alone: the `release` job cuts it when the human approves in the QA view on dev ([`dev-environment.md`](dev-environment.md) §"Release by approval"). The pre-push guard does not run on the agent host, so this is a standing instruction, enforced by the host's branch and tag protection and the bot's permissions. |

## Who merges

| Where | Who merges | When |
|---|---|---|
| Planning repo `main` — everyone's shared page | The agent that wrote the change | At once: open the MR, merge it yourself, the MR stays as the record. No stacked or long-lived planning branches. |
| Code repo `main` | `FW_Orchestrator`; `FW_Developer` on an issue the human assigned it directly | When the gates pass: reviewer checklist `approve`, QA evidence including screenshots, CI green. Every MR, CI configuration and deploy scripts included. |
| Release tag | The human, never an agent — by approving in the QA view on dev | After the human works the checklist at the end of an epic or phase. |

**ADRs.** An ADR lands with status `proposed`, and a card asks the founder to accept it.
An ADR is `proposed` until the human accepts it; no agent writes `accepted`.

**Nothing waits on the human short of the release.** An MR that touches CI
configuration or a deploy or release script is merged like any other once its gates
pass. A merged pipeline change reaches dev at once and that is accepted; production is
protected because only the release tag deploys it and only the human's approval in the
QA view cuts that.

**`env.yaml` is not an agent's to edit.** Every env value the project shares is in the
planning repo's encrypted `env.yaml`, and an agent has a value because an entry routes it
to the `paperclip` place ([FWADR-041](adrs/fwadr-041-env-yaml.md)). The key is on the
operator's machine only, so an edit made here breaks the file. A value you need added,
changed or routed to you is a question card naming the variable and the place.

## One ticket stays one ticket

**Only the Strategist creates tickets, and only while triaging a ticket the human
created.** That triage is where work is split, once, into W-items with a ticket each. No
other agent creates a ticket, ever: no child issue, no follow-up issue, no workaround
issue.

- **Work stays on the ticket it arrived on.** It changes hands by reassignment: the
  Orchestrator hands the issue to the builder and gets it back for the gate. The board
  shows one ticket per thing the human asked for.
- **Who builds.** The Orchestrator reassigns to `FW_Parallel_Developer` by default: the
  team player, each run in its own worktree, never in the shared checkout. An item that
  touches a claimed file waits for the claim to clear. `FW_Developer` is reserved for
  issues the human assigns it directly — emergencies, admin, hotfixes, work the founder
  wants to watch live.
- **Stuck is `blocked`, not a new ticket.** When the work is not converging, stop. Write
  on the ticket what was tried and what stands in the way, set it `blocked` with *who*
  and *for what*, and raise a card if a human must choose. A workaround is a proposal on
  that card, never a ticket you open and start.
- **Found something else?** A line on the ticket — `found: <what>, <where>` — for the
  Strategist. Whether it becomes work is decided at triage, not by the agent that
  tripped over it.
- **Acceptance is frozen at push.** Once the builder has pushed, nobody adds acceptance
  criteria to the issue; a new criterion is a `found:` line.
- **When the issue comes back,** verify against the MR and CI before anything else. A
  builder whose run failed after its work landed (branch pushed, MR open) has returned:
  run the gate. Never re-dispatch work that is already on the git host.

The failure this prevents: a ticket asks for one hard thing; an agent splits it into a
hard part and an easy part; the easy part runs five steps and blocks on the hard part;
the hard part circles for hours and opens workaround tickets as it goes; the human
returns to fourteen stuck tickets, each with its own run history and its own bill, for
one request.

## Act, don't ponder

The 80/20 ladder in [`developer.md`](developer.md) §"Confidence-driven escalation" holds
for every role here: at 80% confidence, act.

- Read the reading list once per run, not once per step.
- Verify a claim once. A second check needs a new reason, stated.
- Post the first visible result — a comment or a commit — early in the run.
- Checked the same thing three times? Stop and write what you know.
- A ticket too big for one run is not yours to split: stop and say so on a card.

## Ending a run

A run never ends with a background process alive: Paperclip reads that exit as a failed
run, parks the issue behind a login card, and the parent never wakes. Prefer not to wait
inside a run at all: post the result so far, close or hand back the issue, and let the
next wake read the pipeline. If you do wait for CI, wait in the foreground with a bounded
poll, on the **newest** pipeline — a pipeline on `main` is cancelled when a newer commit
lands, and polling the cancelled one never ends. Set the issue's status and post the final comment **first**, before
any optional waiting: closing the issue is what wakes the parent.

## Record: git is the record, Paperclip is the queue

An issue is a *run* of framework work, never the record of it. If Paperclip vanished, the
plan, the W-items, the ADRs and the MRs must still tell the whole story.

- **Two issue classes, declared in the description.** A *work* issue names a W-item
  (`W-A13`) and is done when an MR moves that W-item's status row and the W-item's
  frontmatter carries `paperclip_issue: <id>`. An *ops* issue (incident, environment,
  infrastructure, release mechanics) needs no W-item and is done when an MR touches a doc
  (README, runbook, ADR, plan log). Done with no doc touched is not done.
- **Status flows one direction.** Paperclip status is live; W-items, `plan.md` and ADRs
  move only by MR to the planning repo, merged by its author at once (§"Who merges").
  Nothing on the git side is edited without an MR.
- **"Waiting on the world."** A ticket only a human can close (an account, counsel, a
  payment) is `blocked` with *who* and *for what* in the blocker text, so the board
  distinguishes "needs a review" from "needs the founder to make a phone call".
- **Reconciliation.** The Orchestrator's STEP 0 also lists the company's open issues and
  checks each *work* issue names a W-item and no W-item is `in_progress` without an open
  issue. The Curator's divergence report is the backstop (English-only gap, FWADR-040).

## Carve-outs: what Paperclip is allowed to hold

These are the places where Paperclip's own surfaces replace a framework artifact **between
milestones**. Every one of them is reconciled to git at each milestone, not only at close.

- **Working notes.** Between milestones the issue's comments are the working log; the
  W-item log (`w-<id>.log.md`) is not appended comment by comment. At every **milestone** —
  a phase change (Build → QA → Code Review), a decision taken, a measurement that settles a
  question, a deviation from the W-item or a mockup, an MR opened — the agent carries the
  substance into the W-item log by MR: what was decided, what was measured, what deviated
  and why. Chatter stays on the issue; signal reaches git while the work is still live, so
  a reader of the planning repo is never more than one milestone behind the board.
- **Claims.** A file-overlap claim is a comment on both issues the moment it is found;
  `claims.md` gets the claim at the next milestone and the resolution when it resolves.
- **Evidence.** Screenshots, run output and attachments live on the issue; the MR
  description links them and carries the measurements in text, so `git log` reads
  without Paperclip. **For anything a human can see, screenshots are part of done:**
  before and after, at phone and desktop width, attached to the issue and shown in the
  MR. If the attachment upload fails, commit them on the MR branch under
  `docs/screenshots/` so they always show.
- **Cards and their answers.** The card is the question and the answer is on the issue.
  A decision that changes an ADR, plan or exception is still an MR; the card is cited in
  its description.

## Cards: who may answer for the founder

The founder answers cards. A named Claude Code session may answer **for** the founder
when the answer text starts `answered by <session> acting for <founder>`; every such
answer is a comment the founder can overrule later. **Never delegable:** money, legal,
accounts and store submissions, anything the project's server map reserves to the
founder, and production cutovers of a project with paying users.

## Session hygiene (one human, many sessions)

Every agent states its project in the first line of any status it posts. An instruction
that would act outside the agent's own project is confirmed by card before it is acted on,
however plain it sounds. The founder's rule of 2026-11-07, after one session cancelled
another project's deploy on a message meant for a different window.

## Tests and done

A CI runner runs Tier 1 and never reaches a database. Your run environment is not a
runner: from the agent host you may reach **dev — only dev, never production** — to start
the dev harness (Tier 2, Tier 3), read the result from the dev page, and run a case you
are writing against dev's services. Whole suites go through the harness
([`dev-environment.md`](dev-environment.md) §"Test tiers and the dev harness",
[FWADR-037](adrs/fwadr-037-ci-runner-topology.md)).

A code issue is done when: merged → deployed to dev → harness green on the dev page → the
link to that result posted on the issue. The agent that merged checks the deploy itself;
nobody waits for a human to look. A red harness goes back to the builder as a comment
carrying the failing run's link.

## The agents

One company per framework project. The company is created from the package at
[`paperclip/`](../../paperclip/) in the template repo — `FW_Strategist`, `FW_Orchestrator`,
`FW_Developer`, `FW_Parallel_Developer`, `FW_Designer`, `FW_Curator` — each a reading list
(and `FW_Paperclip_Lead`, whose list is two documents — §"The Paperclip Lead"):

1. the project's `CLAUDE.md` and `docs/framework_exceptions/dev_framework_exceptions.md`,
   fetched from the planning repo at run start (the exceptions file is where a project
   says where its agents run, how they authenticate to the git host there, and its server
   map — never the package);
2. the role's Layer-1 docs from the framework at the **pinned commit**;
3. this document.

`scripts/paperclip_company.py` renders the package into a company (`sync`) and checks the
pin against the template's `main` (`status`); the sync hook NOTICEs on drift, and the
package's recurring task has `FW_Curator` report it daily. Bumping the pin is a deliberate
act, like every framework sync.

## The Paperclip Lead

`FW_Paperclip_Lead` answers for the health of the company
([`paperclip-lead.md`](paperclip-lead.md), [FWADR-043](adrs/fwadr-043-paperclip-lead.md)).
It hires, and every four hours it runs the board meter (`scripts/board_meter.py`, no
tokens) and looks at what the meter flags: a run that is looping, stalled or orphaned, a
ticket past its budget. It nudges; with `PAPERCLIP_LEAD_ACTS=on` it may stop a run, block
the ticket with a reason code, and re-open one stopped in error. A ticket of yours it
blocks carries `<code>: <evidence>. Unblock: <what>`: do what the way out says. Its log
and what it needs triaged are in the planning repo under `docs/paperclip_lead/`.

Three things hold with no agent alive: each agent's monthly budget (project variables,
set by `paperclip_company.py sync`), `paperclip_company.py pause` / `resume`, and the
host's own breaker and reaper (adoption step 6).

## What a project does to adopt

1. `PAPERCLIP_API_URL`, `PAPERCLIP_API_KEY`, `PAPERCLIP_COMPANY`, `PAPERCLIP_PLANNING_REPO`
   as entries in `env.yaml` routed to `operator`, and a `paperclip` place for the values
   the agents need (interview Blocks 4 and 5).
2. A "Paperclip" section in `dev_framework_exceptions.md`: agent host, git-push recipe,
   server map, production definition, what the agents must never touch.
3. On the git host: the agents' bot may merge MRs into the planning repo's `main` and
   each code repo's `main`; `v*` tags are protected — only the `release` job and the
   human create them.
4. `PAPERCLIP_AGENT_BUDGET_CENTS` set (a budget per agent is a project variable), then
   `./scripts/paperclip_company.py sync` — creates or refreshes the seven agents and the
   two routines (the daily alignment check, the four-hour board review).
5. One ops issue that proves the loop end to end before any work issue.
6. On the hosts, by the user: a timer on the agent host that kills the agent user's
   processes older than any run could be (one stuck process group once held the host at
   its task limit for ten days; new runs then died at start with `exit 255`), and a
   breaker on the Paperclip host that runs `paperclip_company.py pause` on three failed
   runs in an hour or when the board review has not run.
