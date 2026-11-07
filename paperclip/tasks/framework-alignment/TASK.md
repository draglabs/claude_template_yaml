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

**Issue class: ops (routine).** Daily check that this company's `FW_*` agents are pinned to
the framework template's current `main`. Runs in the planning-repo workspace.

1. `./scripts/paperclip_company.py status` (the planning repo carries the script).
   `aligned` → comment `aligned: <commit>`, done. Read nothing else.
2. On drift, for each role the output lists, diff what that role reads between the pinned
   commit and `main` of `{{framework_repo}}` (`git clone --depth 50`, then
   `git diff <pinned>..origin/main -- docs/dev_framework/<its reads>`), and write three
   lines per role in your comment: what changed, whether `paperclip-mode.md` still covers
   it (name the sentence if not), and whether the change alters what the role may do or
   only its wording.
3. If `paperclip-mode.md` no longer covers a role doc, file an `fwreq-*` request in the
   planning repo by MR and stop; the framework is not yours to edit.
4. Otherwise `./scripts/paperclip_company.py sync --dry-run` (paste it), then `sync`, then
   `status` must print `aligned`. Updating another agent's instructions is a protected
   change: on `403` / consent required, do not retry — raise a question card to the board
   with the analysis and the dry-run output (A: approve, the board runs `sync`; B: hold;
   "Anything else?") and mark this issue blocked on it.

No secrets in comments or MRs; the status output contains none.
