# FWADR-035: `GIT_FLOW` — dev-main or trunk, chosen once at first contact

**Status:** accepted
**Date:** 2026-09-21
**Deciders:** user (framework author) + Template Developer

## Context

The framework's branch model was a trimmed GitFlow hard-coded into every doc: feature branches merge to `dev`, `dev` promotes to `main` by an annotated merge at phase exit, and a pre-push guard ([FWADR-023](fwadr-023-main-push-guard.md)) makes the promotion script the only path to `main`. A project that needed trunk-based development — one integration branch, production released from it — had no supported way to say so, and the guard would have fought it.

Trunk-based, examined against this framework, is a small delta. The `dev` branch already behaves as a trunk: every work item merges there after review, the dev environment deploys from it, and it is always the integrated state. What distinguishes the two models is only **which branch that is** and **what the release event is**.

## Decision

1. **One variable.** `GIT_FLOW=dev-main | trunk` lives in the MINIMUM TO BOOT block of `.env`, asked at the Strategist's first-contact interview right after the git host, never assumed. `dev-main` is the default; `PLACEHOLDER` behaves as `dev-main`.

2. **Two derived concepts, one doc set.** Sourcing `.env` exports `INTEGRATION_BRANCH` (`dev` under dev-main, `main` under trunk). The docs define the *integration branch* and the *release event* once, in `session-policy.md` §"Branching and isolation", with a mapping table, and carry a reading rule: where a doc says `dev` as a branch, read the integration branch; where it says "promote `dev → main`", read the release event. Command snippets use `${INTEGRATION_BRANCH}` and are correct in both modes when `.env` is sourced. Parallel "under trunk" sections in every doc were rejected: they would blow the per-role weight caps ([FWADR-034](fwadr-034-doc-weight-ratchet.md)) and double every future edit.

3. **Trunk flavour: release by tag.** Under trunk, push to `main` deploys the dev environment; pushing an annotated `v<X.Y.Z>` tag deploys that commit to production. **Tags are per repo:** in a multi-repo project each deployable repo versions independently (`v1.0.0` in two repos names two unrelated releases), and a repo without production CI carries no release tags. The phase-exit gate is unchanged: QA against the dev URL, explicit user authorization, then the release event. Pure continuous deployment (every merge deploys production) was rejected for now — it removes the human gate and requires a feature-flag convention the framework does not yet carry.

4. **Per-item QA policy is unchanged under trunk.** Every release is QA'd once at phase exit before the tag; items are not double-checked. Fast over perfect, by the author's call.

5. **Mechanisms read the variable:**
   - the pre-push guard blocks `refs/heads/main` under dev-main; under trunk it blocks `refs/tags/v*` everywhere and `refs/heads/main` in code repos (§"Landing under trunk"), resolving `GIT_FLOW` from the process env or `$PROJECT_DIR/.env` (found via the common git dir, so worktrees resolve too);
   - `scripts/promote_dev_to_main.sh` keeps its name (every doc pointer stays valid) and takes `v<X.Y.Z>` under trunk: it verifies the tag sits on HEAD of `main` and HEAD is already on `origin/main`, then pushes the tag; `-m <msg>` creates the annotated tag first, after the checks pass. `--bypass` pushes main and tag together. It resolves the repo from `--repo <subdir>`, else `DEFAULT_CODE_SUBDIR`, and only then `$PWD` — a git-tracked parent ([FWADR-021](fwadr-021-split-layout.md)) is never released by accident, and one holding code repos with no subdir named is refused;
   - `check-touches.sh` and `check-researcher-scope.sh` default their base ref to `origin/${INTEGRATION_BRANCH}` (derived from `GIT_FLOW` in `.env` when the process env lacks it), and fail loudly when the base ref does not resolve — an empty diff against a deleted `origin/dev` must never read as "in scope";
   - the interview recommends host-side protection: `main` under dev-main; under trunk, `v*` tags plus the PR lock on `main` (§"Landing under trunk").

6. **Switching an existing project is supported** by [`migration-guide-trunk.md`](../migration-guide-trunk.md). `GIT_FLOW` is project-wide, so the switch converts every code repo at once: a per-repo readiness pre-flight (unreleased `dev` commits are a release decision for the user), merge everything down to `main`, make the tag pipeline run verify *and* deploy, flip `GIT_FLOW`, resync, baseline-tag each deployable repo, retire `dev`, and rewrite project docs that still equate `main` with production.

7. **Under trunk, work lands on `main` by PR** — §"Landing under trunk".

### Landing under trunk

Under dev-main, finished work lands by a local merge pushed to `dev`; nothing changes there. Under trunk, `main` is the branch production is tagged from, so in every **code repo** work lands on it only through a merged PR (MR on GitLab), merged on the git host:

1. **A PR is a finished unit.** One PR per W-item; Integrator-QA opens one per batch, its fix commits included. It opens only when the work is complete — Developer mode: the user's QA passed and the Reviewer returned ship; Orchestrator mode: Reviewer (and QA, when required) passed. Every fix before that is a commit on the feature branch, never its own PR, and a PR is never opened as a draft to iterate in. Fixes found after a merge collect on one `fix/<topic>` branch and land as one PR when that round is done.
2. **The PR carries the ledger.** Its description is the W-item summary, the Reviewer verdict and the QA evidence; the merge commit keeps the shape `orchestrator-bootstrap.md` STEP 4 prescribes (Lessons learned, actual-model trailers), set through the host CLI — `gh pr merge --merge --subject … --body …`, `glab mr merge -m …`.
3. **Offer, then merge.** Before merging, the agent offers the user the review ("PR !14 (W-A3) is ready — review it, or I merge?") and merges on their word. The agent merging its own PR *is* the self-approval: no approval object is required, which matters because some hosts and tiers have none (GitLab Community Edition has no approvals at all). Unattended work — an Orchestrator overnight — runs under a **merge grant** the user records on the plan (`**Merge grant:**` in the Executive summary: who granted, when, scope). A grant covers merging, **never releasing**: the `v*` tag always waits for the user. No grant → offer and wait.
4. **After a PR exists, never rewrite it.** The feature branch is pushed for the first time when the PR opens; review fixes are plain commits on top, and a moved `main` is merged into the branch (or updated through the host), not rebased — no force-push, ever.
5. **The tracking parent is not gated.** A git-tracked parent ([FWADR-021](fwadr-021-split-layout.md)) holds plans and ledgers, not code; it pushes `main` directly, as every plan write expects. Only code repos land by PR.
6. **The lock, in mechanisms every host tier has.** Locally, the pre-push guard rejects a direct push to `main` in a code repo, pointing the agent at the PR path. On the host (recommended at first contact, configured by the user): `main` protected with **push = no one**, **merge = maintainers**, plus *pipeline must succeed* and *all discussions resolved* where offered; `v*` tags protected.

**Mechanism honesty.** The guard and the host lock are mechanical: no code reaches `main` except through a merged PR. "Opens complete", "one PR, not one per fix", and "offer before merging" are English-only — no check can tell a finished PR from a premature one, or see whether the offer was made. The merge grant is a recorded line, not an enforced one. Accepted: the failure each prevents is noise or a skipped courtesy, not a production change, because releasing still requires the user.

**Open — emergency path under trunk.** With `main` locked, `promote_dev_to_main.sh v<X.Y.Z> --bypass` (push `main` and the tag together) is rejected by the host. Pending the user's choice between an expedited PR (merge at once without the review offer, then a normal tag) and relaxing the lock for one push.

## Consequences

- Trunk projects have one branch fewer and the same number of human decisions: the PR merge replaces the local merge, and the merge grant lets unattended work proceed without adding a release path.
- The guard's allow variable keeps its name, `FRAMEWORK_ALLOW_MAIN_PUSH`, although under trunk it gates tag pushes. Renaming would ripple through every doc and adopter shell for no behavioural gain.
- Bare terminals without `.env` sourced see an empty `${INTEGRATION_BRANCH}` in command snippets and fail loudly (`origin/` is not a ref). That is the intended failure: the `claude-env` launcher ([FWADR-032](fwadr-032-claude-env-launcher.md)) is the sanctioned path.
- Coherence surfaces in this change: `.env.example`, the guard, the promotion script, both scope-check stubs, `session-policy.md` (branching, promotion commit, phase exit, bypass), `developer.md`, `orchestrator-bootstrap.md` STEP 6, the Executor and Reviewer briefs, `dev-environment.md`, `dev_framework.md`, CLAUDE.md (variables, process rule 2, branch model, commands), `strategist.md`, the interview, FWADR-023 (rewritten), the migration guide, and this ADR.
