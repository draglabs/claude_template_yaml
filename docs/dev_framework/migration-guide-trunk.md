# Migration guide: dev-main → trunk

**Layer 2 — loaded on demand.** For an existing project switching `GIT_FLOW` from `dev-main` to `trunk` ([FWADR-035](adrs/fwadr-035-git-flow-mode.md)). A fresh project never needs this: the first-contact interview sets the mode before any branch exists.

The switch is a phase boundary, not a mid-phase edit. Run it by the Strategist with the user in the loop, after the last dev-main promotion has landed in every code repo and before the next phase's first W-item is claimed. Nothing in flight: no `in_progress`, `code_review`, or `held` items; no live worktrees.

## What changes

| | dev-main (before) | trunk (after) |
|---|---|---|
| Integration branch | `dev` | `main` |
| Feature branches cut from / land on | `origin/dev`, local merge + push | `origin/main`, **one PR per finished W-item**, merged on the host ([FWADR-035](adrs/fwadr-035-git-flow-mode.md) §"Landing under trunk") |
| Dev environment deploys on | push to `dev` | push to `main` |
| Production deploys on | push to `main` (promotion merge) | push of a `v*` tag |
| Guard blocks | pushes to `main` | pushes of `v*` tags; direct pushes to `main` in code repos |
| Release script | `promote_dev_to_main.sh [--repo <subdir>]` | `promote_dev_to_main.sh [--repo <subdir>] v<X.Y.Z> [-m <msg>]` |
| Emergency bypass | commit on `main`, `--bypass`, back-merge to `dev` | open — FWADR-035 §"Landing under trunk" |

## Scope: every code repo at once

`GIT_FLOW` is one line in `$PROJECT_DIR/.env`, so flipping it converts **every code repo in the project together** — a multi-repo project cannot stage the switch repo by repo. Every step below runs once per code repo (`$PROJECT_DIR/<subdir>`, called `$REPO` here); the parent is a code repo for this purpose only if it is git-tracked ([FWADR-021](adrs/fwadr-021-split-layout.md)), and then only steps 0, 1 and 7 apply to it.

## Steps

0. **Pre-flight, per repo.** Build a readiness table — one row per repo — before touching anything:

   | Repo | Working tree | `dev` vs `main` | Production CI | Needs |
   |---|---|---|---|---|

   - **Working tree clean** in every repo, the parent included (commit or discard first). In a tracked parent, framework-synced files are gitignored by the sync ([FWADR-014](adrs/fwadr-014-framework-sync-on-session-start.md) §"Tracked parent") — if its session-start NOTICE says the parent still tracks some, run the one-time un-track command it prints first. Split layout only — a flat-layout project ([FWADR-021](adrs/fwadr-021-split-layout.md)) migrates to split first, because under trunk its plan commits would have to land by PR.
   - **`dev` vs `main`:** already at a promotion boundary (step 1's check passes), or carrying unreleased commits.
   - **Unreleased commits on `dev` are a release decision, not a git chore.** Promoting them deploys them to production. Present them to the user — what ships, what it changes for users — and get a ship / not-yet answer. The flip waits until every repo is at a boundary; there is no `dev` to park work on afterwards.
   - **Production CI:** which repos deploy (they get a release tag in step 6) and which do not (no tag, ever).

1. **Merge everything down to `main`.** The last act under dev-main is a normal phase-exit promotion in each repo that has unreleased commits: every W-item merged to `dev`, test suite green, QA against the dev URL, user authorizes, `./scripts/promote_dev_to_main.sh --repo $REPO`. The promotion is a merge commit, so `main` and `dev` never share a SHA; check trees and ancestry instead:
   ```
   git -C $REPO fetch origin
   git -C $REPO diff --quiet origin/dev origin/main && echo "trees identical"
   git -C $REPO merge-base --is-ancestor origin/dev origin/main && echo "dev contained in main"
   ```
   Both lines must print. If not, promote again; do not proceed with divergent branches.

2. **Update CI triggers** in each repo with production CI (GitHub Actions, GitLab CI, or equivalent per `GIT_HOST`). This is a code change, made while the project is still on dev-main: a W-item landed on `dev` as usual, then released with `./scripts/promote_dev_to_main.sh --repo $REPO` — the guard blocks any other route to `main`. (Flipping `GIT_FLOW` first does not help: until the new rules land, a push to `main` still deploys production under the old ones.)
   - **Production:** deploys on tags matching `v*` instead of push to `main`.
   - **The tag pipeline must run verify as well as deploy.** Rules keyed on the branch miss tags: GitLab leaves `CI_COMMIT_BRANCH` unset in a tag pipeline, so a `v*` push matches nothing and the release silently does nothing — and fixing only the deploy rule deploys unverified. Add the tag condition to *every* job the release needs (GitLab: `$CI_COMMIT_TAG =~ /^v/`; GitHub Actions: `on: push: tags: ['v*']` on the workflow that verifies, or a `needs:` chain).
   - **Dev environment (remote-hosted only):** retarget the deploy from push to `dev` to push to `main`, and confirm the merge deployed it. Local-hosted projects have no dev deploy to move (`DEV_ENVIRONMENT_MODE`).
   - **Confirm, at the step-6 baseline tag, that the verify stage actually ran on the tag pipeline** — not just that deploy fired.

3. **Lock `main` to PR landing and protect the release tags**, per code repo ([FWADR-035](adrs/fwadr-035-git-flow-mode.md) §"Landing under trunk"). Use mechanisms every host tier has — an *approval* object is a paid feature on some hosts, and GitLab Community Edition has none:
   - `main` protected: **push = no one**, **merge = maintainers**; plus *pipeline must succeed* and *all discussions resolved* where offered.
   - `v*` tags protected. GitHub: repo Settings → Rules / tag protection. GitLab: Settings → Repository → Protected branches / Protected tags.

   The tracking parent is not locked — it holds plans, not code, and pushes `main` directly.

4. **Flip `GIT_FLOW`** in `$PROJECT_DIR/.env` from `dev-main` to `trunk`. Update the `{{git_flow}}` bullet in CLAUDE.md to match (the two-surface rule from the interview).

5. **Relaunch and resync.** Exit Claude Code and relaunch via `claude-env` so `INTEGRATION_BRANCH` derives as `main` in the process env. The session-start sync re-installs the guard; the guard reads `GIT_FLOW` on every push, so from this point it blocks `v*` tags everywhere and direct pushes to `main` in code repos; the tracking parent still pushes `main`. Confirm in each repo:
   ```
   git -C $REPO commit --allow-empty -m guardtest && git -C $REPO push origin main   # must be BLOCKED (work lands by PR)
   git -C $REPO reset -q --hard HEAD~1
   git -C $REPO tag v0.0.0-guardtest && git -C $REPO push origin v0.0.0-guardtest    # must be BLOCKED
   git -C $REPO tag -d v0.0.0-guardtest
   ```
   Then run the scope checks once against the new base (`./scripts/check-touches.sh … origin/main`, and `./scripts/check-researcher-scope.sh` if the Researcher is configured) — they must pass before `dev` is deleted, because both fail loudly on a base ref that no longer resolves.

6. **Cut the baseline release tag** in each repo with production CI, from `$PROJECT_DIR`. The script creates the annotated tag on `main`'s head in the named repo and pushes it:
   ```
   ./scripts/promote_dev_to_main.sh --repo $REPO v<X.Y.Z> -m "Release v<X.Y.Z>: trunk migration baseline"
   ```
   Never run a bare `git tag` from `$PROJECT_DIR` — under a tracked parent it tags the parent. **Tags are per repo:** each deployable repo versions independently, so `v1.0.0` in two repos names two unrelated releases. The version number is the user's call (a repo already live in production usually baselines at `v1.0.0`). Production CI should deploy the commit it is already running; if it does not fire, step 2's tag rule is wrong — fix before continuing. Repos without production CI get no tag.

7. **Delete `dev`** in each repo, once step 6 has deployed:
   ```
   git -C $REPO branch -d dev && git -C $REPO push origin --delete dev
   ```
   Rebase any `planning/*` branches still based on `dev` onto `main` first. Prune merged `w-*` feature branches (local and remote) at the same time.

8. **Rewrite what still says "main = production".** Grep the project's own docs (deploy READMEs, runbooks, product ADRs, CLAUDE.md outside the managed block) for statements that `main` is what production runs, and rewrite them in place ([FWADR-036](adrs/fwadr-036-prose-as-code.md)): under trunk, production is the latest `v*` tag and `main` runs ahead of it between releases. Record the switch in the project's ADR log (a short product ADR, or a line on the dev-environment ADR) with the date and each repo's baseline tag. Trunk is a framework mode, not an exception — nothing goes in `dev_framework_exceptions.md`.

## Reverse direction (trunk → dev-main)

Rare, and the mirror image: cut `dev` from the current `main` head, point dev-environment CI at `dev` and production CI at push to `main`, flip `GIT_FLOW`, relaunch, resync, verify the guard now blocks `main`. No tags need removing; they remain valid history.
