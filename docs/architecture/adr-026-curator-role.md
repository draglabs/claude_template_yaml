# ADR-026: Curator role — an opposing incentive for doc pruning

**Status:** accepted
**Date:** 2026-07-29
**Owner:** Template Developer

## Context

The user reported (2026-07-29) that the doc corpus becomes friction as a
project matures: ADRs that should be deprecated stay `accepted`, done tickets
never get archived, and some ADRs are "highly restrictive" in ways that the
project works around rather than follows. Their diagnostic instinct was
specific and correct: **"if an ADR has been updated 30 times I am probably
fighting it."** And their read on why nobody fixes it: *"Strategist likes to
protect his pile of cards."*

That last observation is the load-bearing one. The Strategist **authored** the
corpus, and [`strategist.md`](../dev_framework/strategist.md) states its disposition explicitly: "treats docs as
load-bearing," "doesn't let drift accumulate," "protective of scope." Every one
of those biases toward *conservation*. Asking the author to prune its own work
reliably under-prunes. The residue compounds — by mid-project the pile is
friction rather than guidance, and no role owns removing any of it.

The framework already had a pruning responsibility — `strategist.md` §"Stub
audit" — but it covers **initialization cruft** (unfilled `{{placeholders}}`,
`adr-000-starter-stub.md`, sample plan folders). It does not cover
**accumulated** cruft: the ADRs, plans, and exceptions the project itself
created and outgrew. Nothing owned that surface.

**The signals are mechanically computable**, which was verified before the role
was designed rather than assumed. Run against this repo at design time:

| Signal | Method | Result |
|---|---|---|
| Churn | `git log --follow` per ADR | ADR-018 at **10 commits vs a median of 2** |
| Self-declared revisions | `^#{2,4} Revision \(?v[0-9]` headings | ADR-018 carries **5** (v2, v3, v3.1, v3.2, v3.3) |
| Dead ADR | inbound reference count | ADR-015 at 2, ADR-000 at 3 |
| Bloat | line count vs Layer 1 budget | `developer.md` 448, `session-policy.md` 473, `strategist.md` 321 |

ADR-018 (the Developer role) is simultaneously the highest-churn ADR, the most
revision-annotated, and tied to the most bloated doc in the framework. The
user's "updated 30 times" heuristic fired on real data, unprompted, on the
first run. This is not a rule that needs hope — it needs a script.

## Decision

Add a **Curator** role ([`curator.md`](../dev_framework/curator.md)): a persistent, episodic, top-tier session that audits the
accumulated doc corpus and proposes dispositions.

1. **Its defining property is the inverted incentive.** Where the Strategist
   asks "what does this doc protect?", the Curator asks "what does keeping it
   cost?" A corpus that has never lost a document is un-audited, not
   well-maintained. This is the entire reason it is a separate role rather than
   another Strategist responsibility — the same session cannot hold both
   dispositions honestly.

2. **Proposes, never disposes.** No deletion, archive, or rewrite without
   **per-item** user confirmation — not batch approval. A role built to want
   deletion must not also hold unsupervised authority to perform it. Mirrors
   the existing §"Stub audit" user-involvement rule. Its only unconfirmed write
   is authoring `fwreq-*` request files, which change nothing.

3. **Evidence is mechanical; disposition is judgment.**
   [`doc_churn_audit.sh`](../dev_framework/_stubs/scripts/doc_churn_audit.sh) computes churn, revision counts, inbound
   references, line budgets, and exception age. **The script ranks; it does not
   recommend.** Whether a high-churn ADR is mis-scoped or simply load-bearing
   and actively maintained is precisely the call a script cannot make, and a
   script emitting verdicts would be trusted past its evidence.

4. **Fenced out of framework docs, mechanically.** `docs/dev_framework/*` and
   `.claude/hooks/*` are destructively re-synced every SessionStart ([ADR-014](adr-014-framework-sync-on-session-start.md)),
   so a Curator edit there buys one session and silently reverts.
   [`check-curator-scope.sh`](../dev_framework/_stubs/scripts/check-curator-scope.sh) enforces this.

   **It compares against the template, not against git**, and that choice is
   load-bearing. The first implementation used `git diff` — mirroring the
   Researcher's fence ([ADR-024](adr-024-researcher-role.md)) — and was caught
   in testing exiting `2` (usage error) under ADR-021's **default**
   untracked-parent layout, where `$PROJECT_DIR` is not a git repo and `docs/`
   is not tracked at all. A git-based fence is therefore silently inert in the
   most common configuration: precisely the "passes a reading, fails at
   execution" drift attractor this framework exists to prevent. Diffing
   `docs/dev_framework/` and `.claude/hooks/` against the resolved template root
   works in every layout mode and is semantically exact — a framework file is
   *defined* as byte-identical to the template, so any deviation is the
   violation. Template resolution mirrors `sync-framework.sh`'s chain and, like
   it, deliberately ignores shell environment variables.

5. **Framework findings become `fwreq-NNN-<slug>.md`** in
   `docs/framework_exceptions/`, routed **straight to the user**, who carries
   them to the Template Developer in the canonical template repo. This is
   deliberately shorter than the Researcher's `req-*` path, which routes
   through Strategist triage: those are product-scope decisions, whereas a
   framework change is not the Strategist's to approve. **Ownership within that
   directory is split** — the Curator authors `fwreq-*` and touches nothing
   else there; the Strategist owns the other three files and does not edit
   `fwreq-*`.

6. **Explicit split with the Strategist's stub audit.** Strategist prunes
   *initialization* cruft (template artifacts that arrived unfilled); Curator
   prunes *accumulated* cruft (what the project created and outgrew). Ambiguous
   findings belong to the Strategist — the Curator does not contest ownership.
   Two roles auditing overlapping surfaces with opposing dispositions would be
   a real collision; this is the line that prevents it.

7. **Always available in adopter projects, no activation gate — and not
   applicable in the canonical template repo.** Unlike the Researcher, the
   Curator needs no per-project parameters, so there is nothing to gate. But it
   is an *adopter-project* role, like the Strategist. **Revision (v1.1,
   2026-07-29):** the first version of this ADR omitted that boundary, and a
   Curator booted in the template repo found three coupled breakages, all from
   one cause — stubs deploy via sync, and sync self-skips in the template:
   `scripts/doc_churn_audit.sh` did not exist there (only under `_stubs/`), the
   scope fence was likewise unrunnable and therefore documentation-only, and
   the `fwreq-*` escalation path was **circular** — a request addressed to the
   Template Developer, filed in the repo the Template Developer works in. That
   last one is a genuine design defect, not a missing file: the routing is
   one-directional, *from* an adopter *to* canon, and has nowhere to travel
   when origin and destination coincide. Fixed by stating the boundary in
   `curator.md` (top-of-file applicability note plus a §"Routing" clause that
   says report-to-user instead of file), and by the Template Developer running
   the audit script directly from `_stubs/scripts/` when curating the framework
   corpus. Found by the Curator role auditing its own first release.

8. **Proportionality is stated in its own doc, not by reference.** A bounded
   request gets a bounded audit. This role is the most likely in the framework
   to over-reach, because its disposition actively rewards finding things; a
   Curator returning forty findings when asked about one directory has buried
   whatever mattered. Also stated inline: "nothing to prune" is a legitimate
   finding, and a Curator that never returns it cannot be trusted.

9. **Revision (v1.2, 2026-07-30) — dispositions, fight-detection, and pacing.**
   Rewritten in place rather than superseded, which is itself the rule this
   revision establishes. Driven by a live curation session plus the Curator's
   critique of its own operating manual (FWREQ-005). Four corrections:

   - **Supersede was a permanent context tax.** `docs/archive/README.md` and
     `context-management.md` §"Phase archival" were **plan-only**; nothing ever
     moved a superseded ADR out of `docs/architecture/`, so every supersession
     added a permanently-loaded document describing a decision that is no
     longer true. Archival now covers ADRs, in the same commit as the successor.
   - **`detune` is now a first-class disposition.** The original vocabulary was
     entirely about *volume* — archive, deprecate, retire, split — which biases
     every finding toward deletion when the real defect is often binding force.
     Detune keeps the document and lowers its modality (MUST → SHOULD, hard
     gate → default). It is the precise remedy for the user's founding
     complaint, "ADRs that are highly restrictive," and the original doc could
     not express it; the live session had to improvise it as "user-directed
     re-scope."
   - **Churn is not ambiguous — it was being read wrong.** v1.0 framed
     load-bearing-vs-mis-scoped as judgment a script cannot make. The ambiguity
     dissolves on reading revisions **newest-first with their deciders**: a run
     of user-decided revisions that consistently *relax* something is the user
     overruling the document repeatedly while it re-accretes. That is a fight,
     not maintenance, and it is legible from the corpus alone — chat logs are
     not needed. **This is the same defect as
     [ADR-025](adr-025-named-deliverables.md)**: a churned doc argues its old
     position at the top and records the overruling at the bottom, agents read
     top-down, and stale doctrine outranks the user's live ruling. The Curator
     shipped reproducing the very failure this framework was fixing.
   - **Both corrections are mechanical, not advisory.**
     `doc_churn_audit.sh` gained a **fight-detection** pass that emits revision
     sections newest-first with their decider and direction-bearing title —
     parsing version numbers rather than file order, since those differ
     (ADR-018 carries v3.3 *above* v3.2, so bottom-up reading inverts it). It
     also gained a **REACH** column (highest context layer citing the doc) and
     a worst-first shortlist that ranks Layer 0/1 reach above raw churn. The
     `**Decided by:**` revision convention ships with it in
     [`README.md`](README.md) §"Revision sections" — the extractor is useless
     without a decider to extract, so rule and mechanism land together.
   - **Pacing: one conflict at a time, worst first.** The v1.0 bootstrap report
     ("ranked table + three or four findings") buried the single item that
     mattered under forensics. Now: user's last position, the contradiction,
     one recommendation, stop. Ranked table only on request; diagnostics into
     `fwreq-*`, not the conversation. And **rank by reach** — an ADR cited from
     CLAUDE.md or a Layer 1 doc is paid for by every session, which outranks
     raw churn.

## Consequences

**Buys:** an owner for a surface nobody owned, with the incentive alignment to
actually use it, and a mechanical evidence base so findings are arguable
against numbers rather than taste. Deprecation and archival stop depending on
the author volunteering to delete their own work.

**Costs:** an eighth role — a Roles-table row, a Layer 1 doc, and five surfaces
to keep coherent on every future role change. Two more stub scripts to sync.

**Makes harder:** nothing structurally, since the Curator cannot act
unilaterally. The realistic failure mode is a Curator that over-reports and
becomes noise, which decisions 2 and 8 target directly.

**Mechanism honesty.** The fence and the evidence are mechanical
(`check-curator-scope.sh`, `doc_churn_audit.sh`). The propose-only rule and the
proportionality rule are **English-only**, enforced by the per-item
confirmation being user-visible output. No script can judge whether a document
still earns its place; naming that as a gap is more honest than a check that
would rubber-stamp it.

**Known gap — Layer 0/1 budget, third violation this session.**
[`context-management.md`](../dev_framework/context-management.md) §"The rule"
requires that any Layer 0/1 addition name what it replaces or demotes. This ADR
adds a Roles-table row (CLAUDE.md 164 → 165, already 65% over its 100-line
Layer 0 budget) and a new Layer 1 doc, and subtracts nothing. `curator.md` was
at least written to budget (107). But the corpus now stands at **four docs over
budget with no mechanical check**: `session-policy.md` 473, `developer.md` 448,
`strategist.md` 321, CLAUDE.md 165. Doc mass outweighing a live instruction is
a named contributing cause in [ADR-025](adr-025-named-deliverables.md), and
this session added to it three times. A `scripts/check-doc-budget.sh` plus a
trim pass on the three worst offenders is now the highest-value outstanding
framework work — the pattern, not the footnote.

**Verification note.** The audit script's two judgment columns were both wrong
on first run and were caught by live-running it against this repo: the revision
pattern missed the actual `Revision (v3.1)` spelling (reporting 0 where ADR-018
has 5), and the deprecation check matched mid-line, flagging ADR-013
("accepted; superseded **in part**") and ADR-000 ("stub — superseded
incrementally") as already-deprecated when both are in force. Both fixed. A
signal script that ships wrong is worse than no script, because its output
looks authoritative — live-run any addition to it against a real corpus before
trusting a column.

## Alternatives considered

- **Give the pruning duty to the Strategist.** Rejected — this is the status
  quo, and the user's report is the evidence it does not work. The conservation
  bias is stated in the role's own personality section; adding a
  responsibility that contradicts it produces a rule that loses every time it
  competes with the disposition around it.

- **Spawned subagent brief instead of a persistent role.** Cheaper — no
  Roles-table row, no Layer 1 cost. Rejected because a subagent inherits the
  spawner's disposition, and the inverted incentive *is* the feature. The user
  chose the persistent-role shape when presented with both.

- **Let the Curator edit framework docs directly.** Rejected: they are
  destructively re-synced, so the edit is lost at the next SessionStart. The
  `fwreq-*` request path is the only durable route, and the mechanical fence
  keeps a well-intentioned Curator from discovering this the expensive way.

- **Have the script emit recommendations.** Rejected. A verdict column gets
  trusted past its evidence — the false-positive bug found during verification
  is exactly that failure in miniature. The script ranks; the Curator judges;
  the user decides.
