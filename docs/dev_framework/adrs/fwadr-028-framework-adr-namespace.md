# FWADR-028: Framework ADRs get their own number space and live inside the synced tree

**Status:** accepted
**Date:** 2026-08-05
**Deciders:** user (via Curator request fwreq-002, navy_exam_tutor) + Template Developer

## Context

Framework ADRs (012–027) lived in `docs/architecture/` under the same `adr-NNN`
integer sequence adopter projects use for product decisions. `sync-framework.sh`
syncs only `docs/dev_framework/` and `.claude/hooks/`, so adopters received
framework ADRs at seed time only — then both sequences kept counting
independently. First observed collision (navy_exam_tutor, fwreq-002): numbers
023–026 occupied twice, 21 links in synced files dangling and unfixable
adopter-side (destructive sync reverts any local edit), and bare number-only
citations silently resolving to the wrong decision. Any adopter that authors
more than ~22 product ADRs hits this.

## Decision

Framework ADRs move to `docs/dev_framework/adrs/fwadr-NNN-<slug>.md`, keeping
their existing numbers (`adr-023-main-push-guard` → `fwadr-023-main-push-guard`).
Bare citations use the `FWADR-NNN` form. `docs/architecture/adr-NNN` is
henceforth the product-only space; the framework never numbers against it.

Three properties this buys, each load-bearing:

1. **Collision-immune.** No adopter product sequence can ever occupy a
   framework number, past or future.
2. **Links resolve everywhere.** The files ride the existing destructive sync,
   so every `adrs/fwadr-*` link inside `docs/dev_framework/` resolves in every
   adopter — and adopters now receive framework ADRs *current*, not
   frozen-at-seed-time.
3. **Citations are unambiguous.** The `FWADR-` prefix makes framework
   citations a distinct grep target from product ones; an agent resolving a
   citation by number cannot land on the wrong decision.

Numbers were kept (not restarted at 001) so historical citations in commit
messages and adopter prose stay grep-able against the new filenames.

## Enforcement

`scripts/check-framework-links.sh` (template repo) fails if any file in
`docs/dev_framework/` links into `../architecture/` or contains a bare
`ADR-0NN` citation in the framework range (012–028+). `sync-framework.sh` runs
it in its template-self branch, so every template session start re-checks.
Adopter-side, nothing to enforce: the fence that keeps local edits out of
`docs/dev_framework/*` (destructive sync + Curator scope check) already covers
the new `adrs/` subdirectory.

## Consequences

- Adopters that referenced framework ADRs by old number/path in their own prose
  (plans, W-items) have stale citations. Mitigated by kept numbers — old
  citations map to new by prefixing `FW` — but the framework does not rewrite
  adopter prose; those age out naturally.
- `doc_churn_audit.sh` scans `docs/architecture/adr-*.md` only, so
  template-side churn auditing of `fwadr-*` files is a **named gap**: in the
  template repo the Template Developer must point the audit at
  `docs/dev_framework/adrs/` manually when curating. Adopter-side this is
  correct behavior — framework ADR churn is sync noise, not decision-fighting,
  and stays out of the Curator's signal.
- The synced payload grows by the framework ADR corpus (~16 files). They are
  Layer 2 material — loaded on demand, no session-start context cost.

## Alternatives considered

- **Cite by title only, no path links** (fwreq-002 option B): kills the
  dangling links but keeps bare-number ambiguity — the half that actively
  misleads agents — and leaves adopters unable to read the referenced decision.
- **Renumber from fwadr-001**: no collision benefit over keeping numbers, and
  breaks grep-ability against years of existing citations.
- **Reserved 900-block in the shared space**: avoids renaming but keeps both
  sequences in one directory the sync doesn't cover, so links still dangle and
  the reservation is an English-only rule no mechanism enforces.
