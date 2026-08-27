# FWADR-033: Two-tier env scope rule — operator env vs app env

**Status:** accepted
**Date:** 2026-08-27
**Deciders:** user (framework author) + Template Developer

## Context

The framework runs two distinct planes off files both named `.env`, and had
no rule saying which keys belong where:

1. **The operator plane.** `$PROJECT_DIR/.env` is sourced wholesale under
   `set -a` by the `claude-env` launchers ([FWADR-032](fwadr-032-claude-env-launcher.md)),
   so every variable in it becomes ambient in every agent session, every MCP
   server process, and every worker spawned by `spawn_worker.sh`
   ([FWADR-031](fwadr-031-spawn-worker.md)) — for the life of the session.
   It is the widest exposure surface in the project.
2. **The app plane.** Each code repo's own `.env`
   (`$PROJECT_DIR/<subdir>/.env`) is what the application runtime reads —
   Docker, the dev server, whatever the deploy target injects.

The split was already **latent in the code but stated nowhere**:
`launch_local.sh` distinguishes the "canonical app .env (NOT the
project-parent .env)" and symlinks it into fresh worktrees; FWADR-030 puts
host tokens (`GH_TOKEN`/`GITLAB_TOKEN`) in the parent `.env` — correctly, but
without a principle explaining why. Meanwhile the `.env.example` stub closed
with a catch-all "Runtime secrets / project-specific" section stubbing
`DATABASE_URL` and `API_KEY` — actively inviting app runtime secrets into the
operator file. And the split-layout migration guide offered a "symlink
bridge" (one `.env` serving both planes), which is the same violation made
into a recipe. With no stated principle, the placement of each next credential
acquired was a coin flip in both directions: app secrets drifting into every
agent's ambient env, operator credentials drifting into deployed containers.

## Decision

**The scope rule.** Every env key belongs to exactly one plane:

- **Operator env — `$PROJECT_DIR/.env`.** Keys consumed by the tooling
  *around* the code: framework identity (`PROJECT_NAME`, ports, subdirs),
  git-host declaration + tokens (FWADR-030), MCP server credentials, worker
  and launcher settings. Sourced at launch; ambient everywhere.
- **App env — `$CODE_ROOT/.env`** (per code repo under multi-repo). Keys the
  application runtime reads: database URLs, third-party API keys, service
  config. Never sourced by `claude-env`; never present at the parent.

**Litmus:** *would this key belong in the deployed container's environment?*
Yes → app env. No → operator env. A key that seems to need both homes is two
keys or a design smell — surface it, don't duplicate it.

Shipped mechanisms, all in this change:

1. **Stub rewrite.** The `.env.example` closing section no longer invites
   `DATABASE_URL`/`API_KEY`; it states the scope rule and points app keys at
   `$CODE_ROOT/.env`.
2. **Push-boundary guard (prevention).** The framework pre-push guard
   (`git-guard-pre-push.sh`, installed per-repo by sync step 4b per
   [FWADR-023](fwadr-023-main-push-guard.md)) additionally refuses any push
   whose ref tips track a file named `.env` (any depth). The push boundary is
   the existing choke point: it stops a committed `.env` from ever leaving
   the machine, catches humans and agents alike, and covers worktrees for
   free.
3. **Session-start detection.** `sync-framework.sh` step 4e emits a NOTICE
   when any visible repo (parent or immediate subdir) *already tracks* a
   `.env` — covering exactly the case prevention can't: the file committed
   before the guard existed, or in a repo whose adopter-owned pre-push
   blocked guard installation.
4. **Visibility symlinks (ergonomics).** `sync-framework.sh` step 4f
   maintains read-convenience links at the parent —
   `$PROJECT_DIR/.env.<subdir>` → `<subdir>/.env` for every immediate-subdir
   repo that has an app env — so all env values are inspectable/editable from
   the planning directory without changing what any process sources. Links
   are created when the target exists, re-pointed if wrong, removed when
   dangling, and never replace a regular file of the same name. They are
   ignored via the parent `.gitignore` (`.env.*` with `!.env.example`
   carve-out, appended by sync where a `.gitignore` exists).

## Honest ceiling

- **The guard checks ref *tips* only.** A `.env` committed and later removed
  still exists in pushed history; nothing here scrubs history or rotates the
  secrets it exposed. The guard's block message says so.
- **Neither mechanism un-tracks anything.** Prevention stops new escapes;
  the NOTICE names the already-tracked case and the fix
  (`git rm --cached`, gitignore, rotate); the human does the untracking.
- **Adopter-owned pre-push hooks are never overwritten** (FWADR-023
  doctrine), so a repo with a custom hook has detection but not prevention —
  the existing per-session WARN names that gap.
- **A project that deliberately tracks a non-secret `.env`** (rare, and still
  discouraged) records the deviation in `dev_framework_exceptions.md` and
  forks the hook (drop the `FRAMEWORK-PUSH-GUARD` marker, merge the main
  check manually). No bypass env var is provided — an env-var bypass sourced
  from `.env` under `set -a` would disable the guard permanently and
  silently, the exact failure class FWADR-023 already refuses.

## Consequences

- **Coherence surfaces, all in this change:** this ADR; the `.env.example`
  stub closing section; `git-guard-pre-push.sh` (+ its header and a
  cross-ref note in FWADR-023); `sync-framework.sh` steps 4e/4f + gitignore
  append; the template's own `.gitignore`; CLAUDE.md managed block ("Env
  scope"); `context-management.md` §".env variables";
  `migration-guide-split-layout.md` §4 (symlink bridge retired — it
  contradicted the rule); the `launch_local.sh` app-env comment now citing
  this ADR.
- **The migration guide's "symlink bridge" option is retired.** One file
  serving both planes is the violation this ADR exists to prevent; the
  legitimate need it served (template-root resolution from a code-subdir
  `.env`) has been covered by the sync hook's subdir scan since FWADR-021.
- **Promotion pushes are subject to the env check too** — the
  `FRAMEWORK_ALLOW_MAIN_PUSH=1` escape applies only to the main-ref check.
  A promotion blocked because `dev` tracks a `.env` is the guard working.
- **Flat-layout projects** have one `.env` serving both planes by
  construction; the scope rule is fully realizable only under split layout —
  one more reason flat layout is legacy (FWADR-021).
