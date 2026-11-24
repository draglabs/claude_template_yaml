# FWADR-042: Every dev site carries a QA view; approving there cuts the release

**Status:** accepted
**Date:** 2026-11-19
**Deciders:** user (framework author) + Template Developer
**Piloted in:** Moss Films (built and deployed on its marketing site); ThankMu (designed, with three marks, several repos and machine callers)

## Context

The stakeholder reviewed work on the dev site and then released it somewhere else: a
terminal running `promote_dev_to_main.sh`, or the git host. Feedback had no home at all.
Under Paperclip mode the cost showed: what waited on the human was scattered over issue
comments, with no one place the human opens ([FWADR-040](fwadr-040-paperclip-mode.md)),
and finished work sat for days.

Moss Films built the answer on its dev site: a QA view that shows the deployed commit's
checklist, takes marks and feedback, and has an Approve button that releases. The user
decided (2026-11-19) that this is how every project works from now on, that the
promotion script is obsolete, and that the guide to dev servers says how dev releases
and how dev takes feedback.

## Decision

1. **Every project has a dev mode, and its dev site carries a QA view.** One view per
   project, hosted by the project's main app on dev, covering every code repo of the
   project. Specified in [`dev-environment.md`](../dev-environment.md) §"The QA view".
   The bubble opens it as an overlay over the page under review. The user: "one core
   feature of the bubble is that it is supposed to open an overlay that shows me the
   commit we are on, the features that need to be reviewed up to today, the options… and
   finally the option to cut a release and no status ever prevents me from cutting a
   release."
2. **The checklist is in the code.** `qa/checklist.yaml` in each code repo, read at the
   deployed commit. Every change adds the items the stakeholder should check. The view
   shows everything not yet released: an item on the checklist at the last release tag is
   hidden unless that release's approval carried it (released while open, rejected or
   postponed). Nobody removes items by hand. Beside it
   the view links the PRs merged since the last release: agents merge on their own gates
   ([FWADR-040](fwadr-040-paperclip-mode.md)), and this is where the human reviews them.
3. **Three marks:** approved, rejected, postponed (a soft approval). **Nothing blocks
   Approve.** When something is unsettled — an open or rejected item, a failed or skipped
   harness suite — the view says exactly what and asks the stakeholder to confirm; the
   approval records what was overridden.
3a. **The view shows what was tested, in plain language.** The harness result for the
   deployed commit, suite by suite with human-readable titles, sits above the checklist.
   The harness answers "did anything important break" and nobody marks it; the checklist
   is the human's review of what changed and is never settled by a test. The harness
   posts its result on the commit (`qa:harness pass|fail|skip <run-url>`), and its Tier 2
   and Tier 3 cases run inside the app so the page and an agent can start them.
4. **State is comments on the commit, in the git host,** with a machine-readable first
   line. The app keeps no QA state; agents read the same record the stakeholder wrote.
   A mark is written on the deployed commit and counts until the next release: the view
   reads the comments on every commit since the last release tag and the latest mark on
   an item wins. Dev redeploys on every merge, and with marks read from one commit an
   approval was lost at the next merge.
5. **Approving cuts the release tag, on the git host.** The view posts an approval
   comment; a webhook starts the repo's `release` job, which re-checks everything and
   creates the tag with a token only it receives. The dev server holds a key that
   comments and cannot push. Specified in `dev-environment.md` §"Release by approval".
6. **`promote_dev_to_main.sh` is removed.** There is no script, no bypass variable and no
   laptop path. The pre-push guard refuses every tag push and every direct push to `main`
   in a code repo ([FWADR-023](fwadr-023-main-push-guard.md)). If the QA view is down, the
   user creates the tag in the git host's interface.
7. **No dev mode, no QA.** A repo that truly has no dev mode does not use this; the
   project records that, and how the repo releases, as a framework exception.
8. **The framework ships the description and the contract, not the code.** The user: "I
   meant for the framework to carry instructions on how to create that QA bubble, this
   way it would be 2nd nature for another project to adopt it." The view is a module in
   each project's own stack, built from [`qa-view-build.md`](../qa-view-build.md): the
   bubble (upper left corner of every dev page), the page top to bottom, three build
   steps, and what is fixed so views are interchangeable to agents and to the release
   job — the checklist file, the comment grammar, the comment-only key, the release
   job's checks, the dev login with its exempt-path list. The grammar ships as test
   cases in any language's reach (`_stubs/qa/grammar-cases.yaml`). A project's agents
   never read another project's repo for it.

## Mechanisms

| Rule | What makes it mechanical |
|---|---|
| Nobody pushes a release tag | The pre-push guard refuses tag pushes and direct pushes to `main` in a code repo, with no bypass. On the host: release tags protected, `main` locked to PR landing. |
| Only an approved commit is tagged | The `release` job's own checks; the tag token is scoped to that job. |
| Dev cannot change code | The dev server's token has the comment-only role. |
| Every code repo has a checklist | `sync-framework.sh` step 5g NOTICEs for a code repo with CI and no `qa/checklist.yaml`, until the repo is listed in `QA_EXEMPT_REPOS` with its exception. |
| A project still on a `dev` branch converts | Step 5g NOTICEs while a code repo still has `origin/dev`, pointing at [`migration-guide-trunk.md`](../migration-guide-trunk.md). |

## Honest ceiling

- **The overlay, marks that count across commits and items that leave at release are
  specified and unbuilt.** The one project with a working view (a three-item checklist,
  few merges) opens a page, reads marks from the deployed commit only, and never drops
  an item. The cost of reading every commit since the last release is unmeasured.
- **The contract is English, except the grammar.** The comment grammar has shared test
  cases a project copies; nothing makes a project run them, and no framework check reads
  a project's release job or its view. A project that implements the checks loosely
  releases loosely.
- **The guide is ahead of the pilots in three places:** the `rejected` mark, the
  `qa:harness` comment and the `overrides:` line are specified and not yet built
  anywhere.
- **A stolen dev-server key can post a false approval.** It cannot change code, so the
  worst case is an unwanted release of a commit already on `main`. The dev login and the
  job's checks are the guard.
- **Nothing stops a confirmed release of a red commit.** That is the stakeholder's call
  by design; the override is on the record, on the commit.
- **The in-app harness runner is unbuilt.** ThankMu's harness is a host script with a
  read-only page; no project yet starts a run from the page.
- **Feedback does not yet wake anyone.** A rejection is a comment on a commit; nothing
  turns it into an issue until a project builds that step
  (`dev-environment.md` §"Feedback from the QA view").
- **Postponed items are carried by the next change, by habit.** Nothing files them.
- **GitLab-shaped.** The pilots use GitLab comment webhooks, project access tokens and
  environment-scoped variables. On another host the same contract needs that host's
  equivalents; none is proven.
- **A project without the view cannot release** except by the user tagging on the host.
  That is deliberate: building the view is the path.

## Consequences

- The stakeholder releases from the page they reviewed on, and the approved commit is
  exactly the commit tagged.
- The framework has one branch model ([FWADR-035](fwadr-035-git-flow-mode.md)) and one
  release path. The emergency bypass and its duties are gone with the script.
- Every comment on a commit starts a short pipeline that ends at once unless the comment
  is an approval.
- The QA view's tokens and the dev login's users are `env.yaml` entries
  ([FWADR-041](fwadr-041-env-yaml.md)); a Paperclip agent that does QA has a user routed
  to the `paperclip` place.
- **Coherence surfaces, all in this change:** this ADR; `dev-environment.md`; FWADR-023
  and FWADR-035; the guard; `sync-framework.sh` (step 5g, the stub list, the retired
  stub); the removed script; `migration-guide-trunk.md`; `.env.example`; CLAUDE.md;
  `session-policy.md`, `developer.md`, `dev_framework.md`, `strategist.md`,
  `paperclip-mode.md`, the briefs and the interview.

## Alternatives considered

- **One framework-shipped QA service run beside every repo's dev mode:** one copy of the
  release checks, any stack. Not chosen: one view per project in its main app is enough,
  and the service would be one more thing on every dev host.
- **Checklist items settled by a harness suite** (`check: harness:<suite>`): fewer items
  for the human, but it blurs the two lists. The checklist is what a person reviews.
- **A failed or skipped harness, or a rejected item, blocks Approve:** the stakeholder
  would then need a second path to release when they judge it right. Confirmation
  keeps one path and records the judgement.
- **Each repo builds its own view:** most work, and as many implementations of the
  release checks as there are repos.
- **Keep the script as a fallback:** a second release path that skips the checklist, and
  the bypass variable with it.
- **The dev server creates the tag itself:** needs a key on dev that can also merge and
  change settings.
