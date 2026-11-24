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
3. Only if the sync itself fails (`403`, refused, timed out) or `status` says `could not
   tell`: do not retry. Post the output, set `fdr_blocked` and `blocked`: the founder runs
   `sync`. On a host where agents reach Paperclip through its bridge this is every drift:
   an agent's key can see that the package is behind and cannot change it.

No secrets in comments or MRs; the status output contains none.
