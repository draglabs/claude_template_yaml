---
name: Framework alignment check
assignee: fw-curator
recurring: true
priority: low
metadata:
  paperclip:
    schedule: "0 13 * * *"
    timezone: UTC
    concurrencyPolicy: skip_if_active
---

**Issue class: ops (routine).** The daily backstop for the Paperclip Lead's four-hour sync:
this company's `FW_*` agents carry the framework package as it is on the template's `main`.
Runs in the planning-repo workspace.

1. `./scripts/paperclip_company.py status`. `aligned` → comment `aligned: <commit>`, done.
   Read nothing else.
2. On drift: `./scripts/paperclip_company.py sync`, then `status` must print `aligned`.
   Comment what changed in one line. Framework updates are always taken; nobody is asked,
   and running work is not waited for.
3. Only if the sync itself fails (`403`, consent required): do not retry. Raise one card
   to the board with the output (A: the board runs `sync`; "Anything else?").

No secrets in comments or MRs; the status output contains none.
