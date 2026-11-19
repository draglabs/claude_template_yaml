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

1. Run the meter (`board_meter.py --json`). Nothing flagged, nothing running, nothing
   ready → done; write nothing.
2. For each flagged ticket: its last two comments and its last run's outcome, then one of
   leave / nudge / stop and block / report (`paperclip-lead.md`).
3. No live run → wake one ready ticket.
4. Append one entry to `docs/paperclip_lead/log.md`; put anything for the human and the
   Strategist in `docs/paperclip_lead/triage/`. One MR to the planning repo, merged at once.
