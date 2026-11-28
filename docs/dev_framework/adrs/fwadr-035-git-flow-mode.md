# FWADR-035: Trunk is the branch model — work lands on `main` by PR, production is released by tag

**Status:** accepted
**Date:** 2026-09-21
**Deciders:** user (framework author) + Template Developer

## Context

The framework once carried two branch models behind a `GIT_FLOW` setting: a trimmed GitFlow (`dev` as the integration branch, promoted to `main` by merge) and trunk. In practice every active project moved to trunk, and the second model cost a reading rule in every doc, a mode switch in the guard and the scope checks, and a promotion script with four modes. The user's decision (2026-11-19): the framework is trunk only, and a project still on a `dev` branch converts.

## Decision

1. **One branch model.** `main` is the integration branch. Feature branches (`w-<id>/<slug>`) are cut from `origin/main` and land on it by PR. Push to `main` deploys the dev environment. Production is released by an annotated release tag on `main`. There is no `dev` branch and no `GIT_FLOW` setting.

2. **`INTEGRATION_BRANCH` is always `main`.** Sourcing `.env` exports it, and command snippets and the scope checks (`check-touches.sh`, `check-researcher-scope.sh`) use it. Both checks default their base ref to `origin/main` and fail loudly when the base ref does not resolve — an empty diff against a missing ref must never read as "in scope".

3. **Release by tag, cut by approval.** The stakeholder approves in the QA view on dev and the repo's `release` job creates the tag ([FWADR-042](fwadr-042-qa-view-release.md)); nobody pushes one. **Tags are per repo:** in a multi-repo project each deployable repo versions independently (`v1.0.0` in two repos names two unrelated releases), a repo declares its tag pattern when it is not `v*`, and a repo without production CI carries no release tags. Pure continuous deployment (every merge deploys production) was rejected: it removes the human gate. The user, when feature flags arrived ([FWADR-045](fwadr-045-feature-flags-two-qa-rounds.md)): "CI takes prod flat to production, and that happens when i click that cut release tag button." Flags keep unaccepted work off in production, so a release never waits for it.

4. **Every release is QA'd once, before the tag.** Items are not double-checked. Fast over perfect, by the author's call. On a Paperclip board each ticket has its own two rounds with the founder before its flag comes out ([FWADR-045](fwadr-045-feature-flags-two-qa-rounds.md)); the release press itself is unchanged.

5. **Converting is mandatory and supported** by [`migration-guide-trunk.md`](../migration-guide-trunk.md): merge everything down to `main`, make the tag pipeline run verify *and* deploy, baseline-tag each deployable repo, retire `dev`, and rewrite project docs that still equate `main` with production. `sync-framework.sh` NOTICEs at every session start while a code repo still has `origin/dev`.

6. **Work lands on `main` by PR** — §"Landing on main".

### Landing on main

`main` is the branch production is tagged from, so in every **code repo** work lands on it only through a merged PR (MR on GitLab), merged on the git host:

1. **A PR is a finished unit.** One PR per W-item; Integrator-QA opens one per batch, its fix commits included. It opens only when the work is complete — Developer mode: the user's QA passed and the Reviewer returned ship; Orchestrator mode: Reviewer (and QA, when required) passed. Every fix before that is a commit on the feature branch, never its own PR, and a PR is never opened as a draft to iterate in. Fixes found after a merge collect on one `fix/<topic>` branch and land as one PR when that round is done.
2. **The PR carries the ledger.** Its description is the W-item summary, the Reviewer verdict and the QA evidence; the merge commit keeps the shape `orchestrator-bootstrap.md` STEP 4 prescribes (Lessons learned, actual-model trailers), set through the host CLI — `gh pr merge --merge --subject … --body …`, `glab mr merge -m …`.
3. **Offer, then merge.** Before merging, the agent offers the user the review and merges on their word. The offer carries the PR's host deep link — `Review PR !14 (W-A3): https://gitlab.example.com/.../merge_requests/14 — or I merge?` — resolved by `scripts/pr_link.sh <n>` (framework-owned, host-neutral per `GIT_HOST`), so the user lands on the diff in one click instead of hunting for it; a bare "PR 14 is ready" is not a handoff. CLAUDE.md §"Handing off a PR" states the rule at Layer 0 and `session-reorient.sh` re-injects it on every reset. The agent merging its own PR *is* the self-approval: no approval object is required, which matters because some hosts and tiers have none (GitLab Community Edition has no approvals at all). Unattended work — an Orchestrator overnight — runs under a **merge grant** the user records on the plan (`**Merge grant:**` in the Executive summary: who granted, when, scope). A grant covers merging, **never releasing**: the release always waits for the user's Approve. No grant → offer and wait. Under Paperclip mode agents merge once their gates pass ([FWADR-040](fwadr-040-paperclip-mode.md)).
4. **After a PR exists, never rewrite it.** The feature branch is pushed for the first time when the PR opens; review fixes are plain commits on top, and a moved `main` is merged into the branch (or updated through the host), not rebased — no force-push, ever.
5. **The tracking parent is not gated.** A git-tracked parent ([FWADR-021](fwadr-021-split-layout.md)) holds plans and ledgers, not code; it pushes `main` directly, as every plan write expects. Only code repos land by PR.
6. **The lock, in mechanisms every host tier has.** Locally, the pre-push guard rejects a direct push to `main` and every tag push in a code repo ([FWADR-023](fwadr-023-main-push-guard.md)). On the host (recommended at first contact, configured by the user): `main` protected with **push = no one**, **merge = maintainers**, plus *pipeline must succeed* and *all discussions resolved* where offered; release tags protected.

**Mechanism honesty.** The guard and the host lock are mechanical: no code reaches `main` except through a merged PR. "Opens complete", "one PR, not one per fix", and "offer before merging" are English-only — no check can tell a finished PR from a premature one, or see whether the offer was made. The merge grant is a recorded line, not an enforced one. Accepted: the failure each prevents is noise or a skipped courtesy, not a production change, because releasing still requires the user.

**Emergencies** take the same path, faster: an expedited PR merged at once, dev deploys, the user approves in the QA view.

## Consequences

- One branch, one release path, and the same number of human decisions: the PR merge is the landing, the Approve is the release.
- Bare terminals without `.env` sourced see an empty `${INTEGRATION_BRANCH}` in command snippets and fail loudly (`origin/` is not a ref). That is the intended failure: the `claude-env` launcher ([FWADR-032](fwadr-032-claude-env-launcher.md)) is the sanctioned path.
- A project's `.env` may still carry a `GIT_FLOW` line; nothing reads it.
- Coherence surfaces: `.env.example`, the guard, both scope-check stubs, `session-policy.md` (branching, phase exit), `developer.md`, `orchestrator-bootstrap.md`, the Executor and Reviewer briefs, `dev-environment.md`, `dev_framework.md`, CLAUDE.md (variables, process rule 2, branch model, commands), `strategist.md`, the interview, FWADR-023, FWADR-042, the migration guide, and this ADR.
