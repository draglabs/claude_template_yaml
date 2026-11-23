# The post review

What the Paperclip Lead does for a ticket carrying `lead_review`
([FWADR-043](adrs/fwadr-043-paperclip-lead.md)). Read only in a run where the meter lists
such a ticket. The ten-minute limit of the board look does not cover this part; budget
about ten minutes a ticket.

**It reviews what happened, not the code.** The code was reviewed once, by the builder's
own Reviewer subagent, before the merge. Never read the diff for quality.

## What to read, per ticket

1. The ticket: what was asked, its acceptance criteria, the agent's end-of-run comment.
2. The MR: merged, into `main`, by the agent that held the ticket; the Reviewer's verdict
   is on it.
3. The pipeline on the merge commit, and the deploy.
4. Dev: the deployed commit is the merge commit or a later one; the harness result for it.
5. The run history: how many runs, any that failed, any question labels along the way.

## What to check

- Each acceptance criterion: met, with the evidence that shows it. Go and look: open the
  dev site (or the ticket's slot, while it is still up) and take a screenshot of the
  thing that was asked for, at phone and desktop width where it can be seen.
- The work is on dev, not only merged.
- The harness is green for that commit, or the red is explained.
- The W-item's status row moved and its log has the milestones.
- Nothing went wrong on the way that the next ticket will hit again: a failed run, a
  retry, a question nobody answered. One line each in the report.

## The final report

One comment on the ticket, **posted before the ticket is closed** (a comment on a closed
ticket reopens it):

```markdown
## Final report — <ticket> — <clean | sent back>
- **Asked:** <one line>
- **Delivered:** <one line>, MR <link>, on dev at <commit>
- **Acceptance:** <criterion> — met / not met, <evidence>
- **Harness:** <pass | fail | skip>, <link>
- **How it ran:** <n> runs, <elapsed> from ticket to live; <anything that went wrong>
- **Screenshots:** <attached>
- **For the founder:** <what to look at in the QA view, or nothing>
```

- **Clean:** post the report, then one update that clears `lead_review` and closes the
  ticket.
- **Something is wrong:** post the report saying what, then one update that clears
  `lead_review` and reassigns the ticket, `in_progress`, to the agent that merged. Never
  a new ticket.
- **Cannot take a screenshot from where you run:** say so in the report and use the
  builder's own screenshots; put the gap in the triage folder once, not per ticket.

A line in `docs/paperclip_lead/log.md` per ticket reviewed: the ticket, clean or sent
back, elapsed time from ticket to live.
