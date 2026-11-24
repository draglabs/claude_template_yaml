# The post review

What the Paperclip Lead does for a ticket carrying `lead_review`
([FWADR-043](adrs/fwadr-043-paperclip-lead.md)). A builder hands a ticket over by assigning it
to the Lead with that label, and the assignment starts the run: review that ticket and
any other carrying the label, and skip the board look. The ten-minute limit of the board look does not cover this part; budget
about ten minutes a ticket.

**It is a rundown for the founder, not a gate.** The user: "the purpose of the post
review is for me to see a clean readable rundown of what happened on the run. KPIs are
cost, confidence rating, items accepted and items rejected from the reviewer, ADR
conflicts that need my approval to rewrite. Never in that list is the lead sending it
back to the developer." The Lead reports and closes. **It never sends a ticket back,**
never reassigns it to a builder, and never reads the diff for quality: the code was
reviewed once, before the merge.

## What to read, per ticket

1. The ticket: what was asked, its acceptance criteria, the agent's end-of-run comment
   (its review findings, taken or not, and its totals line).
2. The MR: merged into `main`; the Reviewer's verdict, and any `doc-conflict` in it.
3. Dev: the deployed commit is the merge commit or a later one; the harness result for it.
4. The run history: how many runs, what they cost, any that failed, any question labels.

## What to do

- **Take the relevant screenshots.** Open the dev site (or the ticket's slot, while it is
  still up) and capture the thing that was asked for, at phone and desktop width where it
  can be seen. Nothing a human can see → no screenshot.
- **Acceptance, lightly.** Read the criteria against the builder's evidence and what your
  screenshots show. Do not re-test each one; the harness and the builder's Reviewer did.
- **Rate your confidence that the ticket is done,** 0–100%, with the one thing that
  holds it down.
- **A miss is a line, not a hand-off.** A criterion not met, work that is not on dev, a
  red harness nobody explained: write it under "Not met" and close the ticket all the
  same. The Strategist reads the rundown and decides whether it becomes work.
- **ADR conflicts.** Every `doc-conflict` the Reviewer reported, every deviation from an
  accepted ADR the builder recorded, every ADR left `proposed`: one line each, naming the
  ADR and what the founder is asked to approve.

## The rundown

One comment on the ticket, **posted before the ticket is closed** (a comment on a closed
ticket reopens it). About one screen; the four figures come first:

```markdown
## Rundown — <ticket> — <one line: what was asked and what is now live>
- **Cost:** $<total>, <n> runs, <elapsed> from ticket to live
- **Confidence it is done:** <n>% — <what holds it down, or nothing>
- **Review:** <taken> of <raised> taken, added <N> lines and <M> minutes; not taken: <one phrase each, or none>
- **ADR conflicts for you:** <ADR — what to approve; or none>
- **Not met:** <criterion or step — what is missing; or nothing>
- **Delivered:** MR <link>, on dev at <commit>, harness <pass | fail | skip> <link>
- **How it ran:** <a failed run, a retry, an unanswered question; or clean>
- **Screenshots:** <attached, or none: nothing to see>
```

A figure the builder did not give (no totals line, no lines and minutes) is written as
"not reported", never worked out from the diff.

Then one update that clears `lead_review` (`labelIds: []`) and closes the ticket. That is
the only outcome.

**Cannot take a screenshot from where you run:** say so in the rundown and use the
builder's own; put the gap in the triage folder once, not per ticket.

A line in `docs/paperclip_lead/log.md` per ticket reviewed: the ticket, your confidence,
anything under "Not met", elapsed time from ticket to live.
