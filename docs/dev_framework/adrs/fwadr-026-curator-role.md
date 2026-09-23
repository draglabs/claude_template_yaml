# FWADR-026: Curator role — an opposing incentive for doc pruning

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
corpus, and [`strategist.md`](../strategist.md) states its disposition explicitly: "treats docs as
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
| Churn | `git log --follow` per ADR | FWADR-018 at **10 commits vs a median of 2** |
| Self-declared revisions | `^#{2,4} Revision \(?v[0-9]` headings | FWADR-018 carried **5** appended revision sections |
| Dead ADR | inbound reference count | FWADR-015 at 2, ADR-000 at 3 |
| Bloat | line count vs Layer 1 budget | `developer.md` 448, `session-policy.md` 473, `strategist.md` 321 |

FWADR-018 (the Developer role) was simultaneously the highest-churn ADR, the most
revision-annotated, and tied to the most bloated doc in the framework. The
user's "updated 30 times" heuristic fired on real data, unprompted, on the
first run. This is not a rule that needs hope — it needs a script.

## Decision

Add a **Curator** role ([`curator.md`](../curator.md)): a persistent, episodic, top-tier session that audits the
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
   [`doc_churn_audit.sh`](../_stubs/scripts/doc_churn_audit.sh) computes churn, revision counts, inbound
   references, line budgets, exception age, and the fight-detection evidence in
   decision 10. **The script ranks; it does not recommend.** A script emitting
   verdicts would be trusted past its evidence; the Curator reads the evidence
   and proposes, the user decides.

4. **Fenced out of framework docs, mechanically.** `docs/dev_framework/*` and
   `.claude/hooks/*` are destructively re-synced every SessionStart ([FWADR-014](fwadr-014-framework-sync-on-session-start.md)),
   so a Curator edit there buys one session and silently reverts.
   [`check-curator-scope.sh`](../_stubs/scripts/check-curator-scope.sh) enforces this.

   **It compares against the template, not against git**, and that choice is
   load-bearing. A `git diff` fence — mirroring the Researcher's
   ([FWADR-024](fwadr-024-researcher-role.md)) — was tried first and exited `2`
   (usage error) under FWADR-021's **default** untracked-parent layout, where
   `$PROJECT_DIR` is not a git repo and `docs/` is not tracked at all. A
   git-based fence is therefore silently inert in the most common
   configuration: precisely the "passes a reading, fails at execution" drift
   attractor this framework exists to prevent. Diffing `docs/dev_framework/`
   and `.claude/hooks/` against the resolved template root works in every
   layout mode and is semantically exact — a framework file is *defined* as
   byte-identical to the template, so any deviation is the violation. Template
   resolution mirrors `sync-framework.sh`'s chain and, like it, deliberately
   ignores shell environment variables.

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
   is an *adopter-project* role, like the Strategist. In the template repo,
   stubs are not deployed (sync self-skips there), so
   `scripts/doc_churn_audit.sh` and the scope fence do not exist outside
   `_stubs/`, and the `fwreq-*` path is **circular** — a request addressed to
   the Template Developer, filed in the repo the Template Developer works in.
   The routing is one-directional, *from* an adopter *to* canon, and has
   nowhere to travel when origin and destination coincide. So `curator.md`
   states the boundary (a top-of-file applicability note, and a §"Routing"
   clause: report to the user instead of filing), and the Template Developer
   curates the framework corpus by running the audit script directly from
   `_stubs/scripts/`. A Curator booted in the template repo hit all three
   breakages at once, from that one cause.

8. **Proportionality is stated in its own doc, not by reference.** A bounded
   request gets a bounded audit. This role is the most likely in the framework
   to over-reach, because its disposition actively rewards finding things; a
   Curator returning forty findings when asked about one directory has buried
   whatever mattered. Also stated inline: "nothing to prune" is a legitimate
   finding, and a Curator that never returns it cannot be trusted.

9. **Four dispositions: Rewrite in place, Detune, Consolidate N→1, Supersede +
   archive.**
   - **Rewrite in place** is the dominant case. A doc amended thirty times is
     not a decision that changed thirty times; it is one never articulated
     right, and superseding it just produces a successor that will also be
     amended.
   - **Detune** keeps the document and lowers its modality (MUST → SHOULD,
     hard gate → default). A volume-only vocabulary — archive, deprecate,
     retire, split — biases every finding toward deletion when the real defect
     is often binding force. Detune is the precise remedy for the user's
     founding complaint, "ADRs that are highly restrictive"; without it a live
     curation session had to improvise it as "user-directed re-scope."
   - **Supersede + archive**: the superseded ADR moves to `docs/archive/` in
     the same commit as the successor. Supersession without archival is a
     permanent context tax — every supersession would add a permanently-loaded
     document describing a decision that is no longer true — so
     `docs/archive/README.md` and `context-management.md` §"Phase archival"
     cover ADRs, not only plans.
   - **Appending a revision is not a disposition**
     ([FWADR-036](fwadr-036-prose-as-code.md)); see §"Alternatives considered".

10. **Fight detection reads the decider and direction, newest-first.** Churn
    alone cannot tell a mis-scoped ADR from a load-bearing, actively maintained
    one. The ambiguity dissolves when the changes are read newest-first with
    their deciders: a run of user-decided changes that consistently *relax*
    something is the user overruling the document repeatedly while it
    re-accretes. That is a fight, not maintenance. **This is the same defect as
    [FWADR-025](fwadr-025-named-deliverables.md)**: stale doctrine outranking
    the user's live ruling.

    The reading is mechanical. `doc_churn_audit.sh` has a **fight-detection**
    pass that reads the `Decided-by:` and `Direction:` commit trailers on the
    commits that rewrite each doc from `git log`, newest-first. The trailer
    convention ships in [`README.md`](../../architecture/README.md)
    §"Rewriting an ADR" — the extractor is useless without a decider to
    extract, so rule and mechanism land together. The script also emits a
    **REACH** column (highest context layer citing the doc) and a worst-first
    shortlist that ranks Layer 0/1 reach above raw churn: an ADR cited from
    CLAUDE.md or a Layer 1 doc is paid for by every session.

11. **Pacing: one conflict at a time, worst first.** A bootstrap report of a
    ranked table plus several findings buries the single item that matters
    under forensics. The Curator presents the user's last position, the
    contradiction, one recommendation, and stops. Ranked table only on request;
    diagnostics go into `fwreq-*`, not the conversation.

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
confirmation being user-visible output. Fight detection, like churn, needs the
docs to be git-tracked; under an untracked parent there is no history, the
script reports no decider, and the Curator asks the user. No script can judge whether a document
still earns its place; naming that as a gap is more honest than a check that
would rubber-stamp it.

**Layer 0/1 cost.** This ADR adds a Roles-table row to CLAUDE.md and a new
Layer 1 doc, and subtracts nothing. Doc mass outweighing a live instruction is
a named contributing cause in [FWADR-025](fwadr-025-named-deliverables.md), so
the cost is held mechanically: framework doc weight is word-capped per role
and checked at every template SessionStart
([FWADR-034](fwadr-034-doc-weight-ratchet.md)), `curator.md` included.

**Verification rule.** A signal script that ships wrong is worse than no
script, because its output looks authoritative. Live-run any addition to
`doc_churn_audit.sh` against a real corpus before trusting a column — both of
its judgment columns failed their first live run (a pattern that missed a real
heading spelling, and a deprecation match that fired mid-line on in-force
ADRs whose Status read "accepted; superseded **in part**").

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

- **Keep "append a revision" as a (discouraged) disposition.** Rejected by
  [FWADR-036](fwadr-036-prose-as-code.md). Appending produces dead prose: the
  superseded position stays at the top where agents read it first, and every
  append worsens the reading order that decision 10 exists to detect. History
  belongs in git.

- **Decider lines in the doc body** (`**Decided by:**` under revision
  headings). Rejected: they need appended sections to hang on, re-creating the
  dead prose above, and version-order parsing because file order and version
  order diverge. Commit trailers keep the evidence in git, where history
  belongs.

- **Have the script emit recommendations.** Rejected. A verdict column gets
  trusted past its evidence — the false-positive bug found during verification
  is exactly that failure in miniature. The script ranks; the Curator judges;
  the user decides.
