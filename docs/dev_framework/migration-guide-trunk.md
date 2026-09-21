# Migration guide: dev-main → trunk

**Layer 2 — loaded on demand.** For an existing project switching `GIT_FLOW` from `dev-main` to `trunk` ([FWADR-035](adrs/fwadr-035-git-flow-mode.md)). A fresh project never needs this: the first-contact interview sets the mode before any branch exists.

The switch is a phase boundary, not a mid-phase edit. Run it by the Strategist with the user in the loop, after the last dev-main promotion has landed and before the next phase's first W-item is claimed. Nothing in flight: no `in_progress`, `code_review`, or `held` items; no live worktrees.

## What changes

| | dev-main (before) | trunk (after) |
|---|---|---|
| Integration branch | `dev` | `main` |
| Feature branches cut from / merged to | `origin/dev` | `origin/main` |
| Dev environment deploys on | push to `dev` | push to `main` |
| Production deploys on | push to `main` (promotion merge) | push of a `v*` tag |
| Guard blocks | pushes to `main` | pushes of `v*` tags |
| Release script | `promote_dev_to_main.sh` | `promote_dev_to_main.sh v<X.Y.Z>` |
| Emergency bypass | commit on `main`, `--bypass`, back-merge to `dev` | commit on `main`, `v<X.Y.Z> --bypass`, no back-merge |

## Steps

1. **Merge everything down to `main`.** The last act under dev-main is a normal phase-exit promotion: every W-item merged to `dev`, test suite green, QA against the dev URL, user authorizes, `./scripts/promote_dev_to_main.sh`. After it, `main` and `dev` point at the same commit. Verify:
   ```
   git -C $CODE_ROOT fetch origin && git -C $CODE_ROOT rev-parse origin/main origin/dev
   ```
   Two identical SHAs. If not, promote again; do not proceed with divergent branches.

2. **Update CI triggers.** In the project's workflow files (GitHub Actions, GitLab CI, or equivalent per `GIT_HOST`): the dev-environment deploy job now triggers on push to `main` instead of `dev`; the production deploy job now triggers on tags matching `v*` instead of push to `main`. Commit this on a feature branch off `main` and merge it. Under remote-hosted mode, confirm the merge deployed the dev environment.

3. **Retire host-side protection of `main` as a push target; protect the release ref instead.** On the git host: keep or add "require PR" on `main` (it is now where every feature lands), and add tag protection for `v*`. GitHub: repo Settings → Tags → tag protection rules. GitLab: Settings → Repository → Protected tags.

4. **Flip `GIT_FLOW`** in `$PROJECT_DIR/.env` from `dev-main` to `trunk`. Update the `{{git_flow}}` bullet in CLAUDE.md to match (the two-surface rule from the interview).

5. **Relaunch and resync.** Exit Claude Code and relaunch via `claude-env` so `INTEGRATION_BRANCH` derives as `main` in the process env. The session-start sync re-installs the guard; the guard reads `GIT_FLOW` on every push, so from this point it blocks `v*` tags and lets `main` through. Confirm from `$CODE_ROOT`:
   ```
   git push origin main            # allowed (no-op if nothing to push)
   git tag v0.0.0-guardtest && git push origin v0.0.0-guardtest   # must be BLOCKED
   git tag -d v0.0.0-guardtest
   ```

6. **Cut the first release tag** to establish the baseline production version on the current head of `main`, with the Promotion-commit tag shape from `session-policy.md`:
   ```
   git tag -a v<X.Y.Z> -m "Release v<X.Y.Z>: trunk migration baseline"
   ./scripts/promote_dev_to_main.sh v<X.Y.Z>     # from $PROJECT_DIR
   ```
   Production CI should deploy the same commit it is already running. If it does not fire, the tag trigger in step 2 is wrong; fix before continuing.

7. **Delete `dev`.** Locally and on origin, once step 6 has deployed:
   ```
   git -C $CODE_ROOT branch -d dev && git -C $CODE_ROOT push origin --delete dev
   ```
   Any `planning/*` branches still based on `dev` get rebased onto `main` first.

8. **Record it.** One line in `dev_framework_exceptions.md` is not needed — trunk is a framework mode, not an exception. Note the switch in the project's ADR log (a short product ADR, or a line on the dev-environment ADR) with the date and the baseline tag, so a future session reading `git log` understands why `dev` stops.

## Reverse direction (trunk → dev-main)

Rare, and the mirror image: cut `dev` from the current `main` head, point dev-environment CI at `dev` and production CI at push to `main`, flip `GIT_FLOW`, relaunch, resync, verify the guard now blocks `main`. No tags need removing; they remain valid history.
