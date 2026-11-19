# Migration guide: converting a `dev`-branch project to trunk

**Layer 2 — loaded on demand.** For an existing project whose code repos still have a `dev` branch promoted to `main`. The framework is trunk only ([FWADR-035](adrs/fwadr-035-git-flow-mode.md)), so the conversion is mandatory; the session-start sync NOTICEs until it is done. A fresh project never needs this.

The switch is a phase boundary, not a mid-phase edit. Run it by the Strategist with the user in the loop, before the next W-item is claimed. Nothing in flight: no `in_progress`, `code_review`, or `held` items; no live worktrees.

## What changes

| | Before | After |
|---|---|---|
| Integration branch | `dev` | `main` |
| Feature branches cut from / land on | `origin/dev`, local merge + push | `origin/main`, **one PR per finished W-item**, merged on the host ([FWADR-035](adrs/fwadr-035-git-flow-mode.md) §"Landing on main") |
| Dev environment deploys on | push to `dev` | every merge to `main` |
| Production deploys on | push to `main` | a release tag |
| Who releases | an agent or the user, running a script | the stakeholder, pressing Approve in the QA view on dev ([FWADR-042](adrs/fwadr-042-qa-view-release.md)) |
| Guard blocks | pushes to `main` | every tag push and every direct push to `main` in a code repo, no bypass |

## Scope: every code repo

Every step below runs once per code repo (`$PROJECT_DIR/<subdir>`, called `$REPO` here). The parent is not converted: a git-tracked parent ([FWADR-021](adrs/fwadr-021-split-layout.md)) holds plans, not code, and keeps pushing `main` directly.

## Steps

0. **Pre-flight, per repo.** Build a readiness table — one row per repo — before touching anything:

   | Repo | Working tree | `dev` vs `main` | Production CI | Needs |
   |---|---|---|---|---|

   - **Working tree clean** in every repo, the parent included (commit or discard first). Split layout only — a flat-layout project ([FWADR-021](adrs/fwadr-021-split-layout.md)) migrates to split first, because its plan commits would otherwise have to land by PR.
   - **Unreleased commits on `dev` are a release decision, not a git chore.** Merging them to `main` is the step before they ship. Present them to the user — what ships, what it changes for users — and get a ship / not-yet answer. There is no `dev` to park work on afterwards.
   - **Production CI:** which repos deploy (they get a baseline tag in step 5) and which do not (no tag, ever).

1. **Change the CI triggers, on `dev`,** in each repo with CI. A normal W-item:
   - **Production** deploys on release tags instead of push to `main`.
   - **The tag pipeline must run verify as well as deploy.** Rules keyed on the branch miss tags: GitLab leaves `CI_COMMIT_BRANCH` unset in a tag pipeline, so a tag push matches nothing and the release silently does nothing — and fixing only the deploy rule deploys unverified. Add the tag condition to *every* job the release needs (GitLab: `$CI_COMMIT_TAG =~ /^v/`; GitHub Actions: `on: push: tags: ['v*']` on the workflow that verifies, or a `needs:` chain).
   - **Dev environment (remote-hosted only):** deploys on push to `main` instead of `dev`. Local-hosted projects have no dev deploy to move (`DEV_ENVIRONMENT_MODE`).

2. **Merge `dev` into `main` by one PR, on the host,** in each repo, with the user's word. Until step 1's rules are on `main`, a push to `main` still deploys production under the old ones — so this PR *is* the last old-style release, and it carries step 1 with it. Check that nothing was left behind:
   ```
   git -C $REPO fetch origin
   git -C $REPO merge-base --is-ancestor origin/dev origin/main && echo "dev contained in main"
   ```

3. **Lock `main` to PR landing and protect the release tags**, per code repo. Use mechanisms every host tier has — an *approval* object is a paid feature on some hosts, and GitLab Community Edition has none:
   - `main` protected: **push = no one**, **merge = maintainers**; plus *pipeline must succeed* and *all discussions resolved* where offered.
   - Release tags protected. GitHub: repo Settings → Rules / tag protection. GitLab: Settings → Repository → Protected branches / Protected tags.

4. **Relaunch and resync.** Exit Claude Code and relaunch via `claude-env`. The session-start sync re-installs the guard and removes the retired `promote_dev_to_main.sh`. Delete any `GIT_FLOW` line from `.env` (nothing reads it), and drop the `{{git_flow}}` bullet from CLAUDE.md if the project still has one. Confirm the guard in each repo:
   ```
   git -C $REPO commit --allow-empty -m guardtest && git -C $REPO push origin main   # must be BLOCKED (work lands by PR)
   git -C $REPO reset -q --hard HEAD~1
   git -C $REPO tag v0.0.0-guardtest && git -C $REPO push origin v0.0.0-guardtest    # must be BLOCKED
   git -C $REPO tag -d v0.0.0-guardtest
   ```
   Then run the scope checks once against the new base (`./scripts/check-touches.sh … origin/main`, and `./scripts/check-researcher-scope.sh` if the Researcher is configured) — they must pass before `dev` is deleted, because both fail loudly on a base ref that no longer resolves.

5. **The user cuts the baseline release tag** in each repo with production CI, in the git host's own interface, on `main`'s head. **Tags are per repo:** each deployable repo versions independently, so `v1.0.0` in two repos names two unrelated releases. The version number is the user's call (a repo already live in production usually baselines at `v1.0.0`). Production CI should deploy the commit it is already running; if it does not fire, step 1's tag rule is wrong — fix before continuing. Repos without production CI get no tag.

6. **Delete `dev`** in each repo, once step 5 has deployed:
   ```
   git -C $REPO branch -d dev && git -C $REPO push origin --delete dev
   ```
   Rebase any `planning/*` branches still based on `dev` onto `main` first. Prune merged `w-*` feature branches (local and remote) at the same time.

7. **Build the QA view.** From here a release needs it: a W-item for the view on the project's main app, `qa/checklist.yaml` in every code repo, the `release` job and its webhook ([`dev-environment.md`](dev-environment.md) §"The QA view", §"Release by approval"). Until it exists, the user tags on the host as in step 5.

8. **Rewrite what still says "main = production".** Grep the project's own docs (deploy READMEs, runbooks, product ADRs, CLAUDE.md outside the managed block) for statements that `main` is what production runs, or that a script releases, and rewrite them in place ([FWADR-036](adrs/fwadr-036-prose-as-code.md)): production is the latest release tag and `main` runs ahead of it between releases. Record the switch in the project's ADR log (a short product ADR, or a line on the dev-environment ADR) with the date and each repo's baseline tag.
