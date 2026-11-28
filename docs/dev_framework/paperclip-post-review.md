# The post review

What the Paperclip Lead does for a ticket carrying `lead_review`
([FWADR-043](adrs/fwadr-043-paperclip-lead.md)). A builder hands a ticket over, after the
founder's Accept, by assigning it to the Lead with that label, and the assignment starts
the run: review that ticket and
any other carrying the label, and skip the board look. The ten-minute limit of the board look does not cover this part; budget
about ten minutes a ticket.

**It is a rundown for the founder, not a gate.** The user: "the purpose of the post
review is for me to see a clean readable rundown of what happened on the run. KPIs are
cost, confidence rating, items accepted and items rejected from the reviewer, ADR
conflicts that need my approval to rewrite. Never in that list is the lead sending it
back to the developer." The Lead reports and closes. **It never sends a ticket back,**
never reassigns it to a builder, and never reads the diff for quality: the code was
reviewed once, after the founder's first QA.

## What to read, per ticket

1. The ticket: what was asked, its acceptance criteria, the founder's "QA complete" and
   "Accept", the builder's "Review" comment (the technical review's verdict, blocking
   findings fixed, concerns listed, its totals line) and its end-of-run comment.
2. The MRs: each merged into `main`; any `doc-conflict` the Reviewer reported; the flag
   removed, or kept on the founder's word.
3. Dev: the deployed commit is the merge commit or a later one; the harness result for it.
4. The run history: how many runs, what they cost, any that failed, any question labels.
   Cost and run count are this ticket's row (`cost_usd`, `runs`) in
   `python3 /tmp/board_meter.py --json --all`; Paperclip refuses an agent the ticket's own
   run list. A run that ended by reassigning its ticket records no cost, and every
   hand-off is one, so write the figure as "at least $<n>".

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
- **Recommend on each concern.** For every concern the Reviewer raised and the builder
  listed: "fix" or "leave", with the reason in a phrase. You recommend; the founder
  decides. Do not reopen the review and do not read the diff to do it.
- **ADR conflicts.** Every `doc-conflict` the Reviewer reported, every deviation from an
  accepted ADR the builder recorded, every ADR left `proposed`: one line each, naming the
  ADR and what the founder is asked to approve.

## The rundown

One comment on the ticket, **posted before the ticket is closed** (a comment on a closed
ticket reopens it). About one screen; the four figures come first:

```markdown
## Rundown — <ticket> — <one line: what was asked and what is now live>
- **Cost:** at least $<total>, <n> runs, <elapsed> from ticket to live
- **Confidence it is done:** <n>% — <what holds it down, or nothing>
- **Review:** <verdict>; <B> blocking fixed (+<N> lines, <M> minutes); concerns: <each — fix | leave, why; or none>
- **ADR conflicts for you:** <ADR — what to approve; or none>
- **Not met:** <criterion or step — what is missing; or nothing>
- **Delivered:** MR <link>, on dev at <commit>, harness <pass | fail | skip> <link>, flag <removed | kept: why | none>
- **How it ran:** <a failed run, a retry, an unanswered question; or clean>
- **Screenshots:** <attached, or none: nothing to see>
```

A figure the builder did not give (no verdict, no totals line) is written as
"not reported", never worked out from the diff.

Then one update that swaps `lead_review` for `fdr_review_pending` (`labelIds` holding
that one id) and closes the ticket. That is the only outcome. The label marks a closed
ticket whose rundown the founder has not read; the founder clears it, and can reopen the
ticket. The user: "it can close the ticket.... note i can always reopen the ticket."

## Woken by the founder's comment on a closed ticket

His comment reopened it. Read the comment and nothing else.

- **It asks for a change** (a concern to fix, something wrong on dev): one update that
  clears `fdr_review_pending` and reassigns the ticket, `in_progress`, to the builder that
  merged it. That is all: no checking on dev, no rundown, no new ticket. If that builder
  is mid-run on another ticket in the same files, say so in one comment first. This is
  the founder's request, not a send-back of yours.
- **It asks for nothing** ("ok", "thanks"): close the ticket again, label unchanged.
- **The fix comes back** with `lead_review`: a rundown of the fix only (cost, confidence,
  what changed, screenshots), then close with `fdr_review_pending`.

**Cannot take a screenshot from where you run:** say so in the rundown and use the
builder's own; put the gap in the triage folder once, not per ticket.

A line in `docs/paperclip_lead/log.md` per ticket reviewed: the ticket, your confidence,
anything under "Not met", elapsed time from ticket to live.
