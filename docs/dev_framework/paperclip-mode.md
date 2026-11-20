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
| Code repo `main` | `FW_Orchestrator`; `FW_Parallel_Developer` on an issue the human assigned it directly | When the gates pass: reviewer checklist `approve`, QA evidence including screenshots, CI green. Every MR, CI configuration and deploy scripts included. |
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
created.** No other agent creates a ticket, ever: no child issue, no follow-up issue, no workaround
issue. A follow-up ticket is a normal outcome — of a `found:` line, created at triage.
What is ruled out is an agent creating it, and a ticket dividing.

- **Triage is a back-and-forth with the human.** The human's ticket is vague on purpose
  ("plugins for three browsers, in a dev and a prod build"). It goes to `FW_Strategist`
  first, who asks — question cards or comments on that ticket, as many rounds as it
  takes. A vague request is not yet a ticket; this conversation is what turns it into
  tickets. **No ticket is created until the human has agreed
  the breakdown,** which is written on their ticket. Their ticket stays as the parent, the
  W-item tickets hang under it, and it closes when they do.
- **A ticket is a concrete programming objective that has been planned and thought out.**
  Small ideally, medium or large sometimes; the size is not the test. The test is that
  nobody downstream needs to split it or ask what it means: one repo; one outcome a person
  can check; acceptance the builder can meet without asking the human anything; everything
  it depends on done, or its own ticket ahead of it.
- **A ticket that is not yet that goes back.** A builder handed one says why in one line,
  reassigns it to the Strategist, and does not start.
- **Work stays on the ticket it arrived on.** It changes hands by reassignment: the
  Orchestrator hands the issue to the builder and gets it back for the gate. The board
  shows one ticket per thing the human asked for.
- **Who builds.** `FW_Parallel_Developer` is the one builder: each run in its own worktree,
  never in the shared checkout. An item that touches a claimed file waits for the claim
  to clear. There is no `FW_Developer` on Paperclip: the Developer's strength is working
  in the main checkout with no worktree, fast, on urgent, precise or admin work — that is
  a chat session ("you are the Developer"), and a board gives every run a worktree.
- **Stuck is `blocked`, not a new ticket.** When the work is not converging, stop. Write
  on the ticket what was tried and what stands in the way, set it `blocked` with *who*
  and *for what*, and raise a card if a human must choose. A workaround is a proposal on
  that card, never a ticket you open and start.
- **Found something else?** A line on the ticket — `found: <what>, <where>` — for the
  Strategist. Whether it becomes work is decided at triage, not by the agent that
  tripped over it.
- **Finish this, then do that — on the same ticket.** A ticket may carry more than one MR
  in sequence. What the human adds mid-run is done after the current work, on the same
  ticket, by the same agent: merge what is ready, say what is not in it, deliver the rest
  as the next MR. `found:` is for what is outside the ticket's purpose.
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

## Checkpoints: git is the agent's memory, not the chat

On a remote agent host no run resumes an earlier conversation: every wake is a cold
start, and a run that is cancelled — by a pause, a budget, a crash — keeps only what it
pushed. So an agent writes its state to the two repos as it goes, and any run can be
picked up by a fresh one.

**Checkpoint at every meaningful step, and at least every 15 minutes.** Two pushes:

- **The code repo:** commit the work in progress to the ticket's branch and push, with CI
  skipped (`git push -o ci.skip`, or the host's equivalent). It need not pass tests; it
  has to be what is on disk. The MR opens when the work is ready, not before.
- **The planning repo:** rewrite the ticket's **resume note** and push it to the ticket's
  log branch (`log/<issue>`), whose one MR stays open until the ticket closes.

**The resume note** is one block at the top of `w-<id>.log.md` (for an ops issue, a file
named for the issue), under 20 lines, **rewritten in place, never appended to**:

```markdown
## Resume here
- **As of:** <time UTC>, branch `<branch>` at `<commit>`
- **Done:** …
- **Doing now:** …
- **Next:** …
- **Decided, and why:** …
- **Do not redo:** …
- **To check it works:** <command>
- **Waiting on:** …
```

It names the commit it describes; a note that does not match the branch head is stale,
and the reader trusts the branch. "Decided, and why" and "Do not redo" are what a cold
start otherwise rediscovers at full price.

**A resume reads git, and little else.** A run that picks up a ticket with a resume note
reads the ticket, the note, and the branch (`git log main..<branch>` and the diff). Its
first comment is `Resuming from <commit>; next: <step>`. It does not re-read the reading
list, the plan, the ADRs or earlier comments unless the note points at one. The reading
list is for a first run on a ticket.

**"Checkpoint and stop."** When that comment arrives — from the Paperclip Lead or the
human — checkpoint both repos and end your own run. Nothing is cancelled from outside.

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
  Nothing on the git side is edited without an MR; a ticket's log is one MR, opened at its
  first checkpoint and merged when the ticket closes, and checkpoints are pushes to it
  (§"Checkpoints").
- **"Waiting on the world."** A ticket only a human can close (an account, counsel, a
  payment) is `blocked` with *who* and *for what* in the blocker text, so the board
  distinguishes "needs a review" from "needs the founder to make a phone call".
- **Reconciliation.** The Orchestrator's STEP 0 also lists the company's open issues and
  checks each *work* issue names a W-item and no W-item is `in_progress` without an open
  issue. The Curator's divergence report is the backstop (English-only gap, FWADR-040).

## Carve-outs: what Paperclip is allowed to hold

These are the places where Paperclip's own surfaces replace a framework artifact **between
milestones**. Every one of them is reconciled to git at each milestone, not only at close.

- **Working notes.** The issue's comments are for people. The agent's own state is in git,
  never more than one checkpoint behind the run (§"Checkpoints"): the resume note at the
  top of the W-item log (`w-<id>.log.md`), rewritten at every checkpoint. At every
  **milestone** — a phase change (Build → QA → Code Review), a decision taken, a
  measurement that settles a question, a deviation from the W-item or a mockup, an MR
  opened — the substance goes into the log below the note: what was decided, what was
  measured, what deviated and why.
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
`FW_Parallel_Developer`, `FW_Designer`, `FW_Curator` — each a reading list
(and `FW_Paperclip_Lead`, whose list is two documents — §"The Paperclip Lead"):

1. the project's `CLAUDE.md` and `docs/framework_exceptions/dev_framework_exceptions.md`,
   fetched from the planning repo at run start (the exceptions file is where a project
   says where its agents run, how they authenticate to the git host there, and its server
   map — never the package);
2. the role's Layer-1 docs from the framework, **at the template's `main`, fetched once at
   the start of every run**;
3. this document.

**Framework updates are always pumped in,** as they are into a chat session at every
reset. A change to a role doc or to this document reaches an agent at its next run; a run
under way keeps what it started with. Nobody chooses to take an update and nothing waits
for running work. `scripts/paperclip_company.py` renders the package into a company
(`sync`) and says when the package itself — an agent's file, a routine — is behind
(`status`); the Paperclip Lead's four-hour routine runs that sync unasked, the Curator's
daily task is the backstop, and the session-start hook NOTICEs on drift.

## The Paperclip Lead

`FW_Paperclip_Lead` answers for the health of the company
([`paperclip-lead.md`](paperclip-lead.md), [FWADR-043](adrs/fwadr-043-paperclip-lead.md)).
It hires, and every four hours it runs the board meter (`scripts/board_meter.py`, no
tokens) and checks that work is doing normal things: runs that loop, wait on something
that has ended, or sit orphaned. **It never interrupts work that is under way,** whatever
it has cost. It nudges; it may ask you to "checkpoint and stop"; with
`PAPERCLIP_LEAD_ACTS=on` it may end a run that is *not* working and block its ticket, and
re-open one stopped in error. A ticket of yours it blocks carries
`<code>: <evidence>. Unblock: <what>`: do what the way out says. Its log
and what it needs triaged are in the planning repo under `docs/paperclip_lead/`.

**No budget ends a working run.** Budgets are soft project variables
(`PAPERCLIP_AGENT_BUDGET_CENTS`, `PAPERCLIP_TICKET_BUDGET_CENTS`): past one, the Lead
reports it, and a ticket that is delivering keeps going — waste is unuseful work, not cost. Paperclip's
own agent budget and its pause both cancel live runs, and a cancelled run keeps only what
it pushed — so the built-in budget is at most a far-off fuse, and
`paperclip_company.py pause` / `resume` is the emergency switch, not a routine one.

## What a project does to adopt

1. `PAPERCLIP_API_URL`, `PAPERCLIP_API_KEY`, `PAPERCLIP_COMPANY`, `PAPERCLIP_PLANNING_REPO`
   as entries in `env.yaml` routed to `operator`, and a `paperclip` place for the values
   the agents need (interview Blocks 4 and 5).
2. A "Paperclip" section in `dev_framework_exceptions.md`: agent host, git-push recipe,
   server map, production definition, what the agents must never touch.
3. On the git host: the agents' bot may merge MRs into the planning repo's `main` and
   each code repo's `main`; `v*` tags are protected — only the `release` job and the
   human create them.
4. `PAPERCLIP_AGENT_BUDGET_CENTS` set (a soft budget per agent is a project variable), then
   `./scripts/paperclip_company.py sync` — creates or refreshes the six agents and the
   two routines (the daily alignment check, the four-hour board review).
5. One ops issue that proves the loop end to end before any work issue.
6. On the hosts, by the user: a timer on the agent host that kills the agent user's
   processes older than any run could be (one stuck process group once held the host at
   its task limit for ten days; new runs then died at start with `exit 255`), and a
   breaker on the Paperclip host that runs `paperclip_company.py pause` on three failed
   runs in an hour or when the board review has not run.
