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
   - the pre-push guard blocks `refs/heads/main` under dev-main and `refs/tags/v*` under trunk, resolving `GIT_FLOW` from the process env or `$PROJECT_DIR/.env` (found via the common git dir, so worktrees resolve too);
   - `scripts/promote_dev_to_main.sh` keeps its name (every doc pointer stays valid) and takes `v<X.Y.Z>` under trunk: it verifies the tag sits on HEAD of `main` and HEAD is already on `origin/main`, then pushes the tag; `-m <msg>` creates the annotated tag first, after the checks pass. `--bypass` pushes main and tag together. It resolves the repo from `--repo <subdir>`, else `DEFAULT_CODE_SUBDIR`, and only then `$PWD` — a git-tracked parent ([FWADR-021](fwadr-021-split-layout.md)) is never released by accident, and one holding code repos with no subdir named is refused;
   - `check-touches.sh` and `check-researcher-scope.sh` default their base ref to `origin/${INTEGRATION_BRANCH}` (derived from `GIT_FLOW` in `.env` when the process env lacks it), and fail loudly when the base ref does not resolve — an empty diff against a deleted `origin/dev` must never read as "in scope";
   - the interview recommends host-side protection of the release ref: `main` under dev-main, `v*` tags plus required PRs into `main` under trunk.

6. **Switching an existing project is supported** by [`migration-guide-trunk.md`](../migration-guide-trunk.md). `GIT_FLOW` is project-wide, so the switch converts every code repo at once: a per-repo readiness pre-flight (unreleased `dev` commits are a release decision for the user), merge everything down to `main`, make the tag pipeline run verify *and* deploy, flip `GIT_FLOW`, resync, baseline-tag each deployable repo, retire `dev`, and rewrite project docs that still equate `main` with production.

## Consequences

- Trunk projects have one branch fewer and the same number of human decisions. The emergency bypass under trunk is a normal commit on `main` plus a tag; the back-merge step becomes a no-op.
- The guard's allow variable keeps its name, `FRAMEWORK_ALLOW_MAIN_PUSH`, although under trunk it gates tag pushes. Renaming would ripple through every doc and adopter shell for no behavioural gain.
- Bare terminals without `.env` sourced see an empty `${INTEGRATION_BRANCH}` in command snippets and fail loudly (`origin/` is not a ref). That is the intended failure: the `claude-env` launcher ([FWADR-032](fwadr-032-claude-env-launcher.md)) is the sanctioned path.
- Coherence surfaces in this change: `.env.example`, the guard, the promotion script, both scope-check stubs, `session-policy.md` (branching, promotion commit, phase exit, bypass), `developer.md`, `orchestrator-bootstrap.md` STEP 6, the Executor and Reviewer briefs, `dev-environment.md`, `dev_framework.md`, CLAUDE.md (variables, process rule 2, branch model, commands), `strategist.md`, the interview, FWADR-023 (rewritten), the migration guide, and this ADR.
