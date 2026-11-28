# Paperclip mode: how the roles are played from an issue

[Paperclip](https://github.com/paperclipai/paperclip) is a board: issues, agents that wake
when assigned, labels, comments as the conversation. The framework's
roles were written for a chat session with the user in it. This document is the whole
difference. A role doc stays the role; where it says one of the things in the left column,
a Paperclip agent does the thing in the right column. Decided in
[FWADR-040](adrs/fwadr-040-paperclip-mode.md).

## Substitutions

| Role doc says | On Paperclip |
|---|---|
| "ask the user" / "Anything else?" | Write the question on the ticket — options with evidence, each with Confidence and Difficulty, the recommendation first, last item "Anything else?" — set the label that names who must answer, and end your run (§"Labels"). Labels replace question cards. Never block on chat. |
| "report your understanding and wait for approval" | Post the bootstrap report as the **first comment** on the issue and proceed. Stop and wait only if the issue says `approve-first` or the report finds a conflict. |
| "spawn an Executor" (Orchestrator) | Unchanged: a **subagent inside your run**, each in its own worktree. You never reassign the ticket to another agent. Each Executor pushes its branch at every step, so a run that dies loses nothing that was pushed (§"Checkpoints"). |
| "spawn a Reviewer" | The agent that holds the ticket self-tests before the merge and spawns no Reviewer. The review is done **once**, after the founder's "QA complete", by `FW_Refactor_Developer`, which then acts on it; nothing reads the diff a second time (§"Self-test, two QA rounds, one technical review"). |
| "the user is the QA gate" (Developer) | Post the evidence (commands, output, screenshots) as a comment, merge when the gates pass, and hand the ticket to the Lead with `lead_review` (§"Done"). |
| "hand off the PR" | There is nobody to hand it to: the agent that holds the ticket merges it (§"Who merges"). The end-of-run comment carries the deep link: `Merged MR <n> (W-<id>): <url>`. |
| "`/compact`", "fresh session" | A run is a session. State that must outlive the run is in the issue (comments) or in git (MR, W-item log) — nowhere else. |
| "worktree at `/tmp/worktrees/…`" (Parallel) | Same path, off the workspace checkout Paperclip gives the run, never in the checkout itself. |
| "push the release tag" / "deploy production" | **Never.** The release tag is the human's alone: the `release` job cuts it when the human approves in the QA view on dev ([`dev-environment.md`](dev-environment.md) §"Release by approval"). The pre-push guard does not run on the agent host, so this is a standing instruction, enforced by the host's branch and tag protection and the bot's permissions. |

## Who merges

| Where | Who merges | When |
|---|---|---|
| Planning repo `main` — everyone's shared page | The agent that wrote the change | At once: open the MR, merge it yourself, the MR stays as the record. No stacked or long-lived planning branches. |
| Code repo `main` | The agent that holds the ticket: `FW_Parallel_Developer`, or `FW_Orchestrator` on the big work it threads together; after the founder's "QA complete", `FW_Refactor_Developer` | When the gates pass: its self-test, QA evidence including screenshots, CI green. Every MR, CI configuration and deploy scripts included. |
| Release tag | The human, never an agent — by approving in the QA view on dev | After the human works the checklist at the end of an epic or phase. |

**ADRs.** An ADR lands with status `proposed`, and an `fdr_question` asks the founder to accept it.
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
changed or routed to you is an `fdr_blocked` naming the variable and the place.

## Who gets a ticket

**A planned ticket goes straight to `FW_Parallel_Developer`,** assigned by whoever
triaged it. It builds, self-tests, merges when that and CI pass, checks the deploy, and keeps the
ticket until the founder's "QA complete", when `FW_Refactor_Developer` takes it to the
end (§"Self-test, two QA rounds, one technical review").

**The Orchestrator is for big work.** The user: "5 points but it's really a judgement
call. We use orchestrators when we think that the coding could be completed faster using
two or more agents in parallel, each merging code up to the orchestrator to thread
together into a complete work item. The orchestrator also has a certain persistent
personality to drive work to completion." On a board it works as it does in a chat
session: Executors and the Reviewer are subagents inside its run, and it opens one MR per
work item, threaded from their branches. It does not reassign.

What this replaces: a ticket to add one bubble to the dev page went Orchestrator →
builder → Orchestrator, three cold starts and 4 h 52 min.

## Self-test, two QA rounds, one technical review

The founder tries the work before anyone reviews its code
([FWADR-045](adrs/fwadr-045-feature-flags-two-qa-rounds.md)). The user: "what this locks
in is that it's technically reviewing something that works, not technically reviewing the
wrong thing or the lack of the thing that I asked for."

| Step | Who | What | The ticket while it waits |
|---|---|---|---|
| 1 | Builder | Builds behind a feature flag, self-tests, merges | |
| 2 | Builder | Checks the deploy on dev, says what to try | `fdr_qa_1`, `blocked`, the builder's |
| 3 | Founder | Tries it on dev: **QA complete** | |
| 4 | Refactor developer | Reviews the code, decides per item, acts, trims the tests | `fdr_qa_2`, `blocked`, the refactor developer's |
| 5 | Founder | Checks nothing broke: **Accept** | |
| 6 | Refactor developer | Removes the flag, merges, hands to the Lead | `lead_review`, the Lead's |
| 7 | Lead | The rundown; closes the ticket | `fdr_review_pending`, closed |

The builder is `FW_Parallel_Developer`, or `FW_Orchestrator` on big work; the path is
the same for both. Every ticket goes through both rounds, including one with nothing for
the founder to try. The user: "they can still go through this process, even though I'll
probably end up just clicking accept on them."

**1. The self-test is two questions, and the builder answers them itself.** Are there
tests that confirm the feature works, and is what was built what the ticket asked for?
No review runs before the merge. Hunting for security holes, performance and edge
cases is not this step's job: a defensive review is coming, after the founder has
tried the work. The user: "the first Claude knows that there's a defensive analyst
coming up, it will be less of a defensive analyst in getting the job done so that I can
hit the QA complete button."

**The work merges behind a feature flag,** on in dev and off in production
([`coding-standards.md`](coding-standards.md) §"Feature flags"), unless the ticket says
`flag: none`. The Strategist writes that on a fix to a feature that is already live, on
CI and on infrastructure; a builder never decides it.

**2. Waiting for the founder.** Harness green on dev and its link on the ticket, a
comment saying what to try and where, the resume note rewritten, then one update that
sets `fdr_qa_1` and `blocked` and leaves the ticket assigned to the builder. The ticket
is not handed to anyone: the founder's comment wakes its assignee.

**3 and 5. Only the founder declares QA complete, and only the founder accepts.** The
user: "QA complete is something that only David can declare. It means that the user
tested it and the human said it was done." He presses it in the QA view, which comments
on the ticket as him, or he writes it on the ticket. No agent presses either button,
writes either phrase, or takes a green harness for his word.

**"QA complete" passes the ticket to `FW_Refactor_Developer`.** Pressed in the QA view,
the same update that carries his comment clears `fdr_qa_1` and assigns the ticket to the
refactor developer, which starts it. Written on the ticket by hand, it wakes the
builder, which makes that one update and ends its run.

**Woken on a waiting ticket: read the founder's last comment.**

- *QA complete* (the builder, `fdr_qa_1`) → pass the ticket on, as above.
- *Accept* (the refactor developer, `fdr_qa_2`) → step 6.
- *A note or a rejection* → whoever holds the ticket fixes it on a new MR on this
  ticket, tests it, merges, and waits again in the same round.
- *Anything else, or no comment of his* → set `blocked` again, label unchanged, and end
  the run.

**4. The refactor developer reviews, decides, then acts, in one run**
([`paperclip-refactor.md`](paperclip-refactor.md)). The user: "first it acts as code
review then it reads the evaluation criteria, then acts on the code review analysis."
It did not write the code, so it reads it fresh, and it reads it once: no Reviewer
subagent, and no builder starting cold to re-read a Reviewer's list.

- **Review:** everything this ticket merged, against `main` as it is now, as a
  defensive analyst. Every item is written down before any is judged.
- **Decide:** each item is marked *act* or *decline*, with a reason, before any code
  changes. An ADR violation, a broken coding standard and an acceptance criterion not
  met are always acted on. The rest are weighed, and a third or more are expected to be
  declined as overly defensive.
- **Act:** the items marked *act*, each proven by a test, on a new MR cut from `main`:
  other work may already be built on the code.
- **Trim the tests:** the ticket's tests are refactored down to targeted proof that the
  feature works, and the routine bulk is removed.
- **One round, and nothing is reviewed again.** The user: "I also still like the way we
  do one round of fixes, not infinite looping on fix."
- **Declined items are listed,** one line each. The Lead's rundown recommends a fix or
  leaving it; the founder decides.
- Below 80% on whether an item must be acted on: that is a `str_question`.

Then harness green on dev, the "Review" comment with its totals, the resume note,
and one update that sets `fdr_qa_2` and `blocked`, the ticket still the refactor
developer's. A review that changes no code goes to round two all the same.

**6. Accept settles the feature.** The refactor developer removes the flag in an MR that
holds the removal and nothing else, merges it, checks the harness on dev, and hands the
ticket to the Lead (§"Done"). The user: "flag is removed after the second accept unless
otherwise specified by me": when his Accept says to keep the flag, it stays and the
hand-off says so. The feature reaches production at the founder's next release
([FWADR-042](adrs/fwadr-042-qa-view-release.md)); work still behind a flag is released
switched off, so a release never waits for a ticket.

**A red harness on `main` holds up dev for everyone.** The builder whose merge turned it
red fixes it or reverts that merge before anything else.

**This is the rule on a board.** `developer.md`'s review gate, its Reviewer subagent and
its "doesn't second-guess the Reviewer" are for a chat session, where the user is in the
loop.

**After the ticket is closed, the founder's comment brings the builder back.** The user:
"i have feedback on the feature then that reopens the ticket, it does not create
tickets... i would expect parallel dev to be assigned and then fix the commit and tell
me when it's done." A comment from the founder on a closed ticket reopens it and wakes
its assignee, the Lead. When the comment asks for a change, the Lead reassigns that
ticket to the builder that built it (never the refactor developer), in one update that
clears `fdr_review_pending`,
and does nothing else: no checking on dev, no new ticket, no planning item. The founder
may also assign the ticket to the builder himself. The builder fixes it on a new MR on
the same ticket, self-tests, merges, and hands to the Lead with `lead_review`; the
Lead's second rundown covers the fix only. A comment that asks for nothing is closed
again with no reassignment.

## Labels: who must act

A ticket carries at most one of seven labels. Each names who must act next; a ticket with
none is being worked, or is closed and read.

| Label | Who acts | Set by | Cleared by |
|---|---|---|---|
| `str_question` | The Strategist | An agent below 80% confidence on something; a builder handed a ticket that is not yet a concrete objective | The Strategist, with the answer |
| `fdr_question` | The founder | The Strategist, when it cannot answer at 80% either; or any agent, when only the founder could know | The agent that resumes on the founder's answer |
| `fdr_blocked` | The founder | Anyone, for what no agent can fix: a secret, access, money, an outside party | The agent that resumes once it is fixed |
| `fdr_qa_1` | The founder | The builder, once the work is on dev with a green harness | The update that passes the ticket to the refactor developer on the founder's "QA complete" |
| `fdr_qa_2` | The founder | The refactor developer, after its review and changes | The refactor developer, woken by the founder's "Accept" |
| `lead_review` | The Paperclip Lead | The refactor developer, after the founder's Accept, in the update that reassigns the ticket to the Lead | The Lead, with the rundown |
| `fdr_review_pending` | The founder | The Lead, in the update that closes the ticket after its rundown | The founder, once the rundown is read |

**A label always travels with what wakes the right agent.** Paperclip wakes on
assignment and on comment, never on a label:

- **`str_question`:** write the question as a comment naming who asks, then **one update**
  that sets the label and reassigns the ticket to `FW_Strategist`. The Strategist answers
  in a comment, then one update that clears the label and reassigns to the asker.
- **`fdr_question`, `fdr_blocked`, `fdr_qa_1`, `fdr_qa_2`:** the ticket stays assigned to the agent that will act
  on the answer, status `blocked`, the label set, the question, the obstacle or what to
  try written on it. The founder finds these by label; the founder's comment wakes the assignee, which
  clears the label and carries on.
- **`lead_review`:** **one update** that sets the label and reassigns the ticket to
  `FW_Paperclip_Lead`. The assignment wakes the Lead, which does the post review at once.
  Do not set `in_review`: Paperclip refuses an agent's move to `in_review` unless a
  person, a card or a monitor owns the next step.

**A label is set by id, inside the ticket update.** `PATCH /api/issues/<id>` with
`labelIds`: the whole set the ticket should carry, `[]` to clear. A label name is
accepted and ignored, and an agent's key cannot list labels, so the seven ids are in your
agent file, written there by `paperclip_company.py sync`. Agent ids come from
`GET /api/companies/<id>/agents`.

**What Paperclip does on its own, and what follows from it** (seen on a live board):

- A wake moves a ticket to `in_progress`, even from `blocked`. **The label is the lasting
  signal, not the status:** an agent woken while still waiting sets `blocked` again and
  ends its run.
- A run that ends without setting the ticket's state is run again five minutes later.
  **Every run ends with an explicit ticket state.**
- Paperclip sets `blocked` itself when a run fails. A `blocked` ticket with no label is
  that, or a forgotten label; the meter flags it.
- A comment on a closed ticket reopens it and wakes its agent. **The last comment goes on
  before the ticket is closed.**
- Two tickets assigned to one agent in the same second can fail on the agent host. The
  failed one is picked up by the hourly housekeeping.

**The backstop costs no tokens:** the board meter flags a `str_question` that is not on
the Strategist and a `blocked` ticket with no label, and its hourly housekeeping puts a
`str_question` on the Strategist. `paperclip_company.py sync` creates the seven labels.

## Below 80%: stop, flag, wait

At 80% confidence or better, decide, record why in one line, and carry on. **Below 80%,
do not guess and do not take the recommended option:** write the question (what you need,
the options, what you would pick), set `str_question`, and end your run. The Strategist
that answers is held to the same rule: below 80% it sets `fdr_question` and stops. The
user: "stop and wait, flag it. Same goes for a strategist who comes along to answer the
question or flags it for me."

## One ticket stays one ticket

**Only the Strategist creates tickets, and only while triaging a ticket the human
created.** No other agent creates a ticket, ever: no child issue, no follow-up issue, no workaround
issue. A follow-up ticket is a normal outcome — of a `found:` line, created at triage.
What is ruled out is an agent creating it, and a ticket dividing.

- **Triage is a back-and-forth with the human.** The human's ticket is vague on purpose
  ("plugins for three browsers, in a dev and a prod build"). It goes to `FW_Strategist`
  first, who asks — comments on that ticket, under `fdr_question`, as many rounds as it
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
  sets `str_question`, and does not start.
- **Work stays on the ticket it arrived on,** with the agent it was assigned to. It
  changes hands only to carry a question (§"Labels"). The board shows one ticket per
  thing the human asked for.
- **Whenever a ticket does change hands: reassign first, then comment** (or both in one
  update). A comment posted first wakes the old assignee, and that queued run can hold
  its slot and keep the new assignee from ever starting.
- **Who builds.** `FW_Parallel_Developer` is the builder: each run in its own worktree,
  never in the shared checkout. An item that touches a claimed file waits for the claim
  to clear. Before queueing work behind another ticket, check that ticket is alive: one
  with no run for a day will not free anything, so say so with a `str_question` instead of waiting. There is no `FW_Developer` on Paperclip: the Developer's strength is working
  in the main checkout with no worktree, fast, on urgent, precise or admin work — that is
  a chat session ("you are the Developer"), and a board gives every run a worktree.
- **Stuck is a label, not a new ticket.** When the work is not converging, stop. Write
  on the ticket what was tried and what stands in the way, and set the label that names
  who can move it. A workaround is a proposal in that question, never a ticket you open
  and start.
- **Found something else?** A line on the ticket — `found: <what>, <where>` — for the
  Strategist. Whether it becomes work is decided at triage, not by the agent that
  tripped over it.
- **Finish this, then do that — on the same ticket.** A ticket may carry more than one MR
  in sequence. What the human adds mid-run is done after the current work, on the same
  ticket, by the same agent: merge what is ready, say what is not in it, deliver the rest
  as the next MR. `found:` is for what is outside the ticket's purpose.
- **A run that picks a ticket up** checks the git host before anything else. Work whose
  run failed after it landed (branch pushed, MR open) is not redone: carry on from it.

The failure this prevents: a ticket asks for one hard thing; an agent splits it into a
hard part and an easy part; the easy part runs five steps and blocks on the hard part;
the hard part circles for hours and opens workaround tickets as it goes; the human
returns to fourteen stuck tickets, each with its own run history and its own bill, for
one request.

## Act, don't ponder

At 80% confidence, act (§"Below 80%").

- Read the reading list once per run, not once per step.
- Verify a claim once. A second check needs a new reason, stated.
- Post the first visible result — a comment or a commit — early in the run.
- Checked the same thing three times? Stop and write what you know.
- A ticket too big for one run is not yours to split: stop and say so with `str_question`.

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

**The end of your turn is the end of the run, and nothing wakes you when a background
job finishes.** Before your final message, wait in the foreground for every job you
started (a test suite, a subagent, a poll) or stop it. "I'll report when the suite
finishes" cannot happen: five seconds after your last message Paperclip kills what is
still running and records the run as failed, under the name "Adapter failed", and the
ticket sits `in_progress` with nobody on it. A job too long to wait for: stop it, write
the resume note, and let the next wake rerun it. All six "Adapter failed" runs on one
board in a week (2026-11-19 to 11-23) were this. Prefer not to wait
inside a run at all: post the result so far, close or hand back the issue, and let the
next wake read the pipeline. If you do wait for CI, wait in the foreground with a bounded
poll, on the **newest** pipeline — a pipeline on `main` is cancelled when a newer commit
lands, and polling the cancelled one never ends. **Every run ends with the ticket in an
explicit state** — still `in_progress` with a resume note, `blocked` with a label, or
handed to the Lead with `lead_review` — set before any optional waiting. A comment on a closed
ticket reopens it, so the last comment goes on first.

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
- **"Waiting on the world."** A ticket only a human can move (an account, counsel, a
  payment) is `blocked` with `fdr_blocked` and *for what* in the blocker text.
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
- **Questions and their answers** are comments on the issue. A decision that changes an
  ADR, plan or exception is still an MR; the comment is cited in its description.

## Who may answer for the founder

The founder answers `fdr_question`. A named Claude Code session may answer **for** the founder
when the answer text starts `answered by <session> acting for <founder>`; every such
answer is a comment the founder can overrule later. **Never delegable:** money, legal,
accounts and store submissions, anything the project's server map reserves to the
founder, and production cutovers of a project with paying users.

## Session hygiene (one human, many sessions)

Every agent states its project in the first line of any status it posts. An instruction
that would act outside the agent's own project is confirmed by an `fdr_question` before it is acted on,
however plain it sounds. The founder's rule of 2026-11-07, after one session cancelled
another project's deploy on a message meant for a different window.

## Tests and done

A CI runner runs Tier 1 and never reaches a database. Your run environment is not a
runner: from the agent host you may reach **dev — only dev, never production** — to start
the dev harness (Tier 2, Tier 3), read the result from the dev page, and run a case you
are writing against dev's services. Whole suites go through the harness
([`dev-environment.md`](dev-environment.md) §"Test tiers and the dev harness",
[FWADR-037](adrs/fwadr-037-ci-runner-topology.md)).

## Done

**Whoever merges finishes the job itself.** After each merge: deployed to dev → harness
green on the dev page → the link to that result posted on the ticket. A red harness is
its own to fix, on the same ticket. The ticket then waits for the founder twice
(§"Self-test, two QA rounds, one technical review"). After his Accept and the flag's
removal, the refactor developer hands the ticket over in one update that sets
`lead_review` and reassigns it to `FW_Paperclip_Lead`, and ends its run.

**The post review is the Paperclip Lead's, and it is not a code review**
([`paperclip-post-review.md`](paperclip-post-review.md)). The user: "the job is to ensure
the ticket ran smoothly, the agent did what it was supposed to, code landed on the real
dev server etc. So it's a review of 'what happened and if anything went wrong', not a
review of the code." The Lead posts a rundown for the founder (cost, its confidence
that the ticket is done, a recommendation on each review item that was declined, ADR conflicts needing approval,
anything not met, screenshots), then closes the ticket carrying `fdr_review_pending` in
place of `lead_review`: a closed ticket the founder has not read yet. The founder clears
that label, and can reopen the ticket. The Lead never sends a
ticket back: a miss is a line in the rundown, and the Strategist decides whether it
becomes work.

## Dev slots

A builder that needs a running copy of the app with its own database asks the **slot
supervisor** for a dev slot: a blank, seeded runtime that lives a fixed 8 hours, onto
which the builder deploys its own branch with the project's deploy script. A ticket that
outlasts its slot asks again. Nothing on a slot is precious: the code is in git and the
data is the seed. The contract is in [`slot-supervisor.md`](slot-supervisor.md)
([FWADR-044](adrs/fwadr-044-slot-supervisor.md)). A project with no slot server tries
its work on dev, as before.

## The agents

One company per framework project. The company is created from the package at
[`paperclip/`](../../paperclip/) in the template repo — `FW_Strategist`, `FW_Orchestrator`,
`FW_Parallel_Developer`, `FW_Refactor_Developer`, `FW_Designer`, `FW_Curator` — each a reading list
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
daily task is the backstop, and the session-start hook NOTICEs on drift. Where agents
reach Paperclip through its sandbox bridge, an agent's key cannot read or write the
agents' files: `status` then compares the package at the agent's own pin with the
template's `main`, and a drift is an `fdr_blocked` for a `sync` run with a board key.

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
and what it needs triaged are in the planning repo under `docs/paperclip_lead/`. It does the
post review of a ticket when the ticket is assigned to it with `lead_review` (§"Done").

**Between its looks, the queue is kept moving by a script, hourly, with no agent:**
`board_meter.py --housekeep` cancels a run that sat queued without ever starting and wakes
the ticket's current assignee, and wakes the assignee of a ticket that never got a run.
It touches nothing that has started.

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
   `./scripts/paperclip_company.py sync` — creates or refreshes the seven agents, the two
   routines (the daily alignment check, the four-hour board review) and the seven labels.
5. One ops issue that proves the loop end to end before any work issue.
6. On the hosts, by the user: a timer on the agent host that kills the agent user's
   processes older than any run could be (one stuck process group once held the host at
   its task limit for ten days; new runs then died at start with `exit 255`), and a
   breaker on the Paperclip host that runs `paperclip_company.py pause` on three failed
   runs in an hour or when the board review has not run.
7. An hourly schedule for `./scripts/board_meter.py --housekeep` with a board key: a cron
   entry on the Paperclip host or a scheduled pipeline in the planning repo. Where it
   runs is recorded in the project's Paperclip section.
