---
name: Board review
assignee: fw-paperclip-lead
recurring: true
priority: medium
metadata:
  paperclip:
    schedule: "0 */4 * * *"
    timezone: UTC
    concurrencyPolicy: skip_if_active
---

**Issue class: ops (routine).** The four-hour look at the whole board, by the Paperclip Lead.

0. Keep the company current: `paperclip_company.py status`; on drift, `sync`. Never asked,
   never held for running work. A sync that is refused goes in the triage folder.
1. Run the meter (`board_meter.py --json`). Nothing flagged, nothing running, nothing
   ready, nothing waiting for post review → done; write nothing.
2. For each live run: is it doing normal things (a recent push, a current resume note)?
   For each flagged ticket: its last two comments, its last run's outcome, its resume
   note, then one of leave / nudge / report (`paperclip-lead.md`). Never interrupt a run
   that is working.
3. No live run → wake one ready ticket.
3a. For each ticket the meter lists under `lead_review`: the post review
   (`fw paperclip-post-review.md`). Final report on the ticket first, then clear the label
   and close it, or send it back to the agent that merged.
4. Append one entry to `docs/paperclip_lead/log.md`; put anything for the human and the
   Strategist in `docs/paperclip_lead/triage/`. One MR to the planning repo, merged at once.
