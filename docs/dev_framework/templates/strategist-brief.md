# Strategist subagent briefing template (bounded doc work)

Spawn when a session needs **bounded, write-capable doc work** — intake a ticket into a plan, update a planning doc, record a decision, add a W-item — without handing off to a persistent Strategist session.

This is the one sanctioned way to reach Strategist-surface *writes* from a subagent. The read-only consultants ([`doc-consultant-brief.md`](doc-consultant-brief.md), [`code-consultant-brief.md`](code-consultant-brief.md)) answer questions; this one changes files.

**This is not "the Strategist role in a subagent."** The persistent Strategist ([`../strategist.md`](../strategist.md)) is a standing job description — audit, cross-reference, triage, verify, sweep. A subagent that loads that doc treats the job description as its task list and inflates a five-minute intake into a corpus-wide review that exhausts its window and returns nothing useful. **The spawned Strategist does NOT read `strategist.md`.** Its scope is this brief and nothing else. See [ADR-025](../../architecture/adr-025-named-deliverables.md).

## When to spawn

- **Developer needs a ticket taken into the plan** mid-session — "intake this bug as a W-item on the current plan" — without leaving the coding loop.
- **A decision reached in conversation needs recording** in a planning doc, roadmap, or future-directions entry.
- **A small planning-doc edit** whose content is already settled: update a status line, add an acceptance criterion, correct a stale pointer.

## When NOT to spawn

- **The work is architectural, not clerical.** Anything requiring judgment about direction, scope tradeoffs, or a locked decision belongs to a persistent Strategist session with the user present — not a subagent with no user access.
- **You only need to know something.** Use a Doc or Code Consultant; they are cheaper and read-only.
- **The task is open-ended** ("review the plan", "check alignment", "clean up the docs"). Those are phase-boundary Strategist work. A subagent handed an unbounded task will produce unbounded output.
- **Live plan-ledger writes are in flight from another session.** Status flips race with the Orchestrator — see [`../strategist.md`](../strategist.md) §"Plan amendments during a live phase".

## Brief template

```
## Doc work — {{one-line task}}

You are a Strategist subagent doing ONE bounded doc task. You are not
running the Strategist role. Do NOT read docs/dev_framework/strategist.md
— it is a standing job description for a persistent session and will
inflate this task.

## The task
{{exactly what to do, in one or two sentences. Name the artifact and
the outcome.}}

## Files you may write
{{explicit list — full paths. This is your ENTIRE write surface.}}
- docs/execution-plans/<plan>/plan.md
- docs/execution-plans/<plan>/w-<id>.md

Writing any file not on this list is out of scope. If the task seems to
require one, STOP and return a question instead (see Return format).

## Files you may read
{{list — keep it short. Every extra file is context you spend.}}
- docs/execution-plans/<plan>/plan.md
- docs/execution-plans/README.md   (only if you need the W-item format)

## Content
{{the actual material — ticket text, decision to record, values to set.
Paste it. Do NOT make the subagent go find it.}}

## Hard rules

1. **Write what was asked for.** The task above names an artifact and an
   outcome. That IS the deliverable. Do not substitute an adjacent one —
   do not record the request as a note on a different doc, do not open a
   different item "covering" it. If you cannot produce the named
   artifact, return a question; do not produce a different artifact and
   report success.

2. **A missing value is a QUESTION, not work to create.** If this task
   needs a parameter nothing defines — a threshold, a cadence, an owner,
   a date — do NOT create an ADR, a W-item, or a plan amendment to
   define it, and do NOT invent a value. Return the question. You have
   no user access; the session that spawned you does, and one question
   costs them one exchange.

3. **Bounded means bounded.** Do the task. Do NOT additionally run an
   alignment audit, a stub audit, a cross-reference sweep, a status
   reconciliation, or a coherence pass. Do NOT "improve" adjacent
   content you notice in passing — note it in Observations instead.

4. **Do not spawn subagents.** Peer-dispatch constraint (ADR-013). If
   you need something you cannot get, return a question.

5. **Do not commit or push.** You write files; the spawning session owns
   the commit. This is NOT optional caution — see the plan-write note
   below, which the spawning session must honour on your return.

6. **Stale-read hazard on plan files.** Read each file fresh immediately
   before editing it. If an Edit returns a stale-read error, re-read and
   retry once, then report the failure — do NOT report success on a
   write that did not land.

## Return format

1. **Status** — `done` | `question` | `blocked`. One word, first line.
2. **What was written** — file path + one line per change. If nothing
   was written, say so explicitly.
3. **Question** (if status is `question`) — the specific value or
   decision you need, stated so the user can answer in one line. Name
   the fork; do not ask "how should I proceed?"
4. **Observations** (optional, max 3 lines) — anything you noticed but
   correctly did NOT act on. This is where adjacent problems go.

Keep the response under 15 lines. Do not narrate your process.
```

## Plan-file writes: the spawning session must close the commit

**Read this before briefing a spawn that touches `plan.md` or a W-item file.** Plan-write commit semantics are **mode-dependent** ([`../developer.md`](../developer.md) §"Working directory: `$CODE_ROOT`", [ADR-021](../../architecture/adr-021-split-layout.md)):

- **Untracked parent (default)** — `$PROJECT_DIR` is not a git repo. Plan edits are file-only writes; concurrent sessions see them through the shared filesystem. The subagent's write is complete on return. Nothing further needed.
- **Tracked parent, or flat layout** — plan edits must **commit + push** to be visible to sibling sessions. That is what PLAN-WRITE DISCIPLINE's concurrent-claim safety depends on.

Under tracked-parent or flat layout, the subagent leaves an **uncommitted plan edit in the working tree**. Two consequences the spawning session owns:

1. **Commit immediately on return, before any further plan write of your own.** An uncommitted plan edit is invisible to sibling sessions, so a concurrent Developer or Orchestrator can claim the same item.
2. **Your next plan-write reads a dirty tree you did not author.** PLAN-WRITE DISCIPLINE's read-fresh step assumes the tree reflects your own last write. Re-read before editing, and do not assume an Edit failure is a stale-read fluke — it may be the subagent's pending change.

If you cannot commit on return (mid-rebase, detached head, unrelated staged work), **do not spawn** — do the doc edit inline instead. A bounded intake is not worth a plan-ledger race.

## Why the return format has a `question` status

The read-only consultants always return an answer. This one is allowed to return **nothing written plus a question**, and that is a success outcome, not a failure. The failure mode this brief exists to prevent — manufacturing prerequisites rather than asking — happens precisely when a subagent believes it must return completed work. Returning a question is cheaper than a phase of invented scaffolding.

The spawning session surfaces the question to the user, gets a one-line answer, and re-spawns with it filled into the `## Content` section.
