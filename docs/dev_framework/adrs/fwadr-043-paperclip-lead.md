# FWADR-043: The Paperclip Lead reviews the whole board on a clock; budgets and a kill switch hold without it

**Status:** accepted
**Date:** 2026-11-19
**Deciders:** user (framework author) + Template Developer
**Evidence:** ThankMu's board, 2026-11-05 to 2026-11-19 — 137 runs, 48 tickets, about 950M tokens read

## Context

Every role on a Paperclip board looks at one ticket. Nothing looked at the board. In two
weeks on one project:

- One ticket ran 23 times, 9 of them failed, and nothing stopped it.
- A run polled a cancelled pipeline for 100 minutes, then died without closing its issue.
- Four tickets sat `in_progress` for ten days with no run.
- A ticket and everything split from it read 613M tokens; standalone tickets read 326M.
- One stuck process group (566 processes) held the agent host at its task limit for ten
  days. New runs died at start with `exit 255`, which read as unrelated flakiness.
- Every agent had been created with no budget.

The user's words: "an agent that runs every 4 hours and uses AI to look holistically at
the board, blocks and identifies outliers"; "there needs to be an insurance plan"; and, on
the name and the role, "it should be called 'paperclip lead' and its purpose according to
paperclip ethos is to hire subagents."

## Decision

1. **A meter and a reader, kept apart.** `scripts/board_meter.py` (framework-owned) reads
   Paperclip's records and flags tickets with reason codes. It costs no tokens, judges
   nothing and changes nothing. The **Paperclip Lead** (`FW_Paperclip_Lead`,
   [`paperclip-lead.md`](../paperclip-lead.md)) reads the meter's output and uses
   judgement on what it flags, because a costly ticket can be the one that mattered.
2. **The Lead hires.** It may propose an agent for the board to approve. It is the one
   `FW_*` agent created with that permission. It never bumps the framework pin.
3. **Every four hours, around the clock.** A routine in the company package. A quiet board
   ends the run with nothing written.
4. **Per flagged ticket, the smallest action:** leave, nudge, stop and block with a reason
   code, or report for triage. One wake per run when nothing is live.
5. **Acting starts off.** `PAPERCLIP_LEAD_ACTS` is a project variable. `off` (the default):
   report and nudge, and the log lists what it would have done. `on`: it may stop another
   agent's live run, block the ticket, and re-open a ticket it judges was stopped in error.
6. **It answers to the health of the company, in the planning repo.** `docs/paperclip_lead/`
   holds `log.md` (one entry per run that did anything) and `triage/` (one file per issue
   for the human and the Strategist). It does not raise cards for board health.
7. **A reading list of two, no bootstrap report.** Six runs a day cannot afford the usual
   list; the meter's output is the context.
8. **Insurance that is not an agent.** Budgets are project variables:
   `PAPERCLIP_AGENT_BUDGET_CENTS` for every agent, `PAPERCLIP_BUDGET_CENTS_<AGENT>` for
   one, set by `paperclip_company.py sync`. `paperclip_company.py pause` / `resume` is the
   kill switch. A breaker and a process reaper on the hosts are the user's to install
   ([`paperclip-mode.md`](../paperclip-mode.md) adoption step 6).

The starting budget is 4,000 cents per agent per month: twice what the session that
wrote this cost, priced at the rate the evidence board recorded (about 33M tokens read,
near $18). It is a starting number, meant to be changed in the project's variables.

## Mechanisms

| Rule | What makes it mechanical |
|---|---|
| The board is looked at every four hours | The `board-review` routine, created by `paperclip_company.py sync` |
| Counting costs nothing | The meter is a script; its thresholds are `BOARD_METER_<NAME>` variables |
| No agent spends without a cap | `sync` sets `budgetMonthlyCents` from the project variables and prints which agents have none |
| Everything can be stopped at once | `paperclip_company.py pause`, a board operation that also cancels live runs |
| The Lead acts only when switched on | `PAPERCLIP_LEAD_ACTS`, read by the agent — English-only, see below |

## Honest ceiling

- **Unexercised against a live board:** the new agent, the routine, the budget field on
  create and update, `pause` / `resume`. The endpoints were read from Paperclip's source
  (`POST /agents/:id/pause`, `/resume`; `budgetMonthlyCents` on the agent;
  `POST /heartbeat-runs/:runId/cancel`), not called.
- **Stopping a run and pausing an agent are board-only in Paperclip.** The Lead can do
  them only where the project routes it board credentials; otherwise a stop is a triage
  file for the human.
- **`PAPERCLIP_LEAD_ACTS` is read by the agent, not enforced.** With acting off, nothing
  but its instructions keeps the Lead from blocking a ticket.
- **The thresholds are guesses** from two weeks of one board.
- **The meter does not see the git host** (a mergeable MR on a waiting ticket, a cancelled
  pipeline a run is polling), and Paperclip records no cost on some runs, so `over-budget`
  under-counts.
- **Labels on a ticket were not found in Paperclip's update route,** so a block is
  recognised by its blocker text, not a `wasteful` label.
- **The breaker, the reaper and the alarm on the review itself are not shipped.** They are
  host state; adoption step 6 says what they do.
- **The Lead is a Paperclip-only role.** There is no "you are the Paperclip Lead" chat
  session, so it is not in CLAUDE.md's Roles table or the re-orient hook.

## Consequences

- A stuck or looping ticket is seen within four hours instead of ten days.
- The company gains a seventh agent and a second routine; six short runs a day is the cost.
- The Strategist reads `docs/paperclip_lead/triage/` at session start.
- **Coherence surfaces, all in this change:** this ADR; `paperclip-lead.md`;
  `paperclip-mode.md` (§"The Paperclip Lead", §"Ending a run", the agents list, adoption
  steps 4 and 6); `paperclip/agents/fw-paperclip-lead/`, `paperclip/tasks/board-review/`,
  `paperclip/COMPANY.md` and `README.md`; `paperclip_company.py`; `board_meter.py` and the
  sync hook's stub list; `.env.example`; `dev_framework.md`; `context-management.md`;
  `strategist.md`; the interview's Block 4; `check-doc-weight.sh`.

## Alternatives considered

- **The Orchestrator on a routine:** it already looks at its own tickets; the review has to
  be able to judge the Orchestrator's work too.
- **An agent that counts for itself:** tokens every cycle to count what a script counts.
- **Blocking from day one:** the thresholds have been seen against one board.
- **Budgets hard-coded in the script:** a budget is a project's decision.
- **Children allowed for oversized work, charged to the parent** (the pitch's splitting
  rules): superseded by one ticket stays one ticket
  ([FWADR-040](fwadr-040-paperclip-mode.md)).
