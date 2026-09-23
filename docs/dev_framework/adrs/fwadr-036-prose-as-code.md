# FWADR-036: Prose as code — no dead prose in spec docs

**Status:** accepted
**Date:** 2026-09-23
**Owner:** Template Developer

## Context

The user caught an Orchestrator working with a Curator (tesla_app_worker
session) to align documents to their instructions. It came back with a list of
conflicts and an offer to *amend* them. The user's observation: *"in code you
do not amend changes, you simply correct the code and expect the git blame to
be your history — otherwise code would become a forest of comments."*

The framework already said this, in three places, and did not act on it:

- [FWADR-027](fwadr-027-living-architecture.md) Decision 5: *rewrite, never
  append; git keeps the history.*
- [`curator.md`](../curator.md) §Dispositions listed "Append a revision" as
  *discouraged* — still a legal disposition, with an escape clause.
- [`docs/architecture/README.md`](../../architecture/README.md) shipped a
  template for appended `## Revision (vN)` sections, and
  `doc_churn_audit.sh` read its decider signal *only* from those sections. The
  tooling depended on the anti-pattern.

And the corpus modelled it: nine framework ADRs carried appended revisions or
addenda (FWADR-018 had five, out of order). Agents imitate the files they
read, not the rule stated about them. An agent asked to reconcile a doc does
what the docs around it look like they did.

**Dead prose is worse than dead code.** Dead code does not run. Dead prose is
read by every agent that loads the file and *acted on* — an appended revision
leaves the superseded position at the top, where it is read first. That is
the [FWADR-025](fwadr-025-named-deliverables.md) /
[FWADR-027](fwadr-027-living-architecture.md) failure class (stale doctrine
outranking a live decision), produced by the editing habit itself.

Why agents append rather than rewrite — each pull is answered below:

| Pull toward appending | Counter |
|---|---|
| Feels safe — deleting a decision feels like overstepping | Decision 2: git is the undo; appending is the destructive act |
| Visible proof of work — a rewrite looks like nothing happened | Decision 4: the proof lives in the commit |
| Cheaper — no need to read the whole doc | Decision 3: contradictions are callers |
| The corpus models it | Decision 7: corpus rewritten in this change |
| The tooling rewards it | Decision 5: the audit reads trailers |
| Nothing stops it | Decision 6: mechanical check + `dead-prose` review finding |

## Decision

**Spec prose is treated like code. It states what is true now. History lives
in git. A document that describes a superseded decision as if it held is a
defect, the same way dead code is.**

1. **Two kinds of document, opposite rules.**
   - **Spec** — states current truth; **rewritten in place**: ADRs (framework
     and product), `docs/dev_framework/**` (role docs, briefs, templates,
     stub scripts' comments), `CLAUDE.md`, `docs/architecture/**`, operational
     docs (runbooks, SOPs, checklists), execution-plan ledgers and W-item spec
     sections (scope, acceptance).
   - **Log** — records what happened; **append-only**, never rewritten:
     `process-exceptions.md`, `execution-incidents.md`, integration claims,
     W-item `## Implementation log` and `## User-directed deviation` sections,
     `w-<id>.log.md` working logs, `docs/archive/**`.
   The code analogy holds both ways: source is edited in place, migrations and
   changelogs are append-only. A doc not listed is spec unless it is plainly a
   dated journal.

2. **What counts as dead prose — and what does not.** The test for each
   statement: *does it explain the current decision, or describe an old one?*
   - **Live ("why") prose stays:** context, rationale, constraints, rejected
     alternatives, "we tried X and it failed because Y". When a mechanism is
     retired, the *reason* is rationale — it moves into Context or
     Alternatives considered. Deleting it invites the next agent to re-propose
     the rejected option.
   - **Dead prose goes:** appended `Revision` / `Addendum` / `Amendment`
     sections; "originally… now…" narration; version tags in the body
     (`vN.N`, "Revision vN"); statements the current decision contradicts.
   Rewriting in place loses nothing: the previous text is one `git log -p`
   away. Appending is the destructive act — it leaves two contradicting
   statements and agents obey both.

3. **Contradictions are callers.** Changing a function signature is not done
   until every caller is updated, or the build breaks. A spec edit is not done
   until every statement it contradicts — in the same doc, and in docs that
   cite the changed section — is rewritten too. `grep` for the ADR number and
   the changed term before committing.

4. **The commit carries the history.** A commit that changes a spec doc's
   *decision* (not a typo or link fix) states in its body what the doc said
   before and what it says now, and ends with two trailers:
   ```
   Decided-by: user | Strategist | Template Developer | Developer
   Direction: <what moved, as a direction — "relax: cap removed", "tighten: gate added", "clarify">
   ```
   They go in the message's final paragraph, together with any
   `Co-Authored-By:` — git parses trailers from the last paragraph only.
   The diff shows the removed line and the added one — better proof of work
   than an appended section ever was.

5. **The churn audit reads git, not headings.** `doc_churn_audit.sh` fight
   detection extracts `Decided-by:` / `Direction:` trailers from `git log`
   per ADR, newest first. A decision-changing commit without them prints
   `(no decider recorded)` — the missing trailer is what gets noticed. Legacy
   `Revision` headings still in an adopter corpus are reported as **dead
   prose to rewrite**, not as signal.

6. **Mechanical enforcement, two layers.**
   - **Template:** `scripts/check-dead-prose.sh` runs at every template
     SessionStart (beside `check-framework-links.sh` and
     `check-doc-weight.sh`) and fails on structural markers in spec docs:
     `Revision` / `Addendum` / `Amendment` headings, the blockquote addendum
     form, inline revision labels, and ADR version tags. It matches
     *structure*, not words — prose that discusses the anti-pattern (this ADR,
     `curator.md`) does not trip it. A deliberate exception carries
     `dead-prose: allow` on the line.
   - **Review gate:** new finding class **`dead-prose`** in
     [`reviewer-brief.md`](../templates/reviewer-brief.md) and
     [`integrator-qa-brief.md`](../templates/integrator-qa-brief.md). When a
     diff touches spec prose: appended revision markers, or a statement the
     change contradicts left standing → `block` (class `execution` — the fix
     is a rewrite, continuation handles it). A decision-changing spec commit
     without trailers → `ship-with-concerns`.

7. **The corpus is rewritten in this change.** The nine framework ADRs with
   appended revisions or addenda (FWADR-012, 013, 014, 017, 018, 019, 026,
   031, 032) are collapsed to current-state bodies; version-tagged citations
   across docs, hooks, and stub-script comments are rewritten to cite the ADR
   alone. "Append a revision" is removed from the Curator's dispositions
   ([FWADR-026](fwadr-026-curator-role.md)) and the Revision template from
   `docs/architecture/README.md`, which now documents §"Rewriting an ADR".

## Consequences

**Buys:** a doc read top-to-bottom is true. Agents asked to reconcile a
conflict rewrite, because that is now the only shape in the corpus, the only
disposition offered, and the only one that passes the gate. The churn signal
survives and gets stronger: every decision-changing commit carries a decider,
not only the ones someone remembered to annotate.

**Costs:** rewriting is more work than appending — the author must read the
whole doc and its citers (Decision 3). That cost is the point: it is paid once
by the writer instead of by every future reader.

**Makes harder:** reading *how* a decision evolved now needs `git log -p`
instead of scrolling. Deliberate — evolution is history, and history is git's
job. Where the reason for a past change still matters, Decision 2 keeps it as
rationale.

**Mechanism honesty.** The heading/tag check is mechanical. The contradiction
rule (Decision 3) and trailer discipline (Decision 4) are English-only at
authoring time; the Reviewer's `dead-prose` finding and the audit's
`(no decider recorded)` are the after-the-fact backstops. Semantic dead prose
— a paragraph contradicted without any marker — cannot be grepped for; it is
caught by review or by the Curator, not by a script.

**Delivery gap.** `doc_churn_audit.sh` is a seed-once stub
([FWADR-014](fwadr-014-framework-sync-on-session-start.md)): existing adopters
keep their old copy. Deleting `scripts/doc_churn_audit.sh` re-seeds the new
one on next SessionStart. Accepted as a gap, not fixed here.

**Untracked parent: rewrite in place anyway.** Under the default *untracked
parent* ([FWADR-021](fwadr-021-split-layout.md)), `docs/architecture/` has no
git history, so a rewrite loses the old text. That loss is accepted: the
untracked phase is where early ideas get worked out, and their history is not
worth keeping. Rewrite in place with no extra confirmation step and no
fallback copy; the trailers and the audit's decider column simply do not exist
there yet, like its churn column. **The framework never pushes git tracking.**
The user decides when a project starts tracking its parent; from that commit
on, history and trailers apply.

## Alternatives considered

- **Keep "append" as a discouraged disposition** (the prior state). Rejected:
  "discouraged" with an escape clause was the de-facto default, because the
  corpus modelled it and the tooling rewarded it.
- **Changelog section at the bottom of each ADR** — history in the file, but
  out of the reading path. Rejected: a second, hand-maintained copy of what
  `git log` already records; it drifts, and agents still read it.
- **Frontmatter `kind: spec | log` on every doc.** More explicit than a path
  list, but a new field on every file in every adopter for a distinction the
  paths already make. Rejected for now; revisit if misclassification shows up.
- **Delete superseded ADRs instead of archiving them** — the strict
  prose-as-code reading. Deferred: `docs/archive/` is cheap, out of the load
  path, and gives the Strategist old reasoning without `git` archaeology.
