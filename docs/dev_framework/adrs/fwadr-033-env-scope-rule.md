# FWADR-033: Two-tier env scope rule — operator env vs app env

**Status:** accepted
**Date:** 2026-08-27
**Deciders:** user (framework author) + Template Developer

## Context

The framework runs two distinct planes off env files:

1. **The operator plane.** `$PROJECT_DIR/.env` is sourced wholesale under
   `set -a` by the `claude-env` launchers ([FWADR-032](fwadr-032-claude-env-launcher.md)),
   so every variable in it becomes ambient in every agent session, every MCP
   server process, and every worker spawned by `spawn_worker.sh`
   ([FWADR-031](fwadr-031-spawn-worker.md)) — for the life of the session.
   It is the widest exposure surface in the project.
2. **The app plane.** What the application runtime reads: a code repo's own
   `.env` for local slots (`$PROJECT_DIR/<subdir>/.env`), and on a host the env
   the deploy job writes.

With no stated rule, the placement of each next credential was a coin flip in
both directions: app secrets drifting into every agent's ambient env, operator
credentials drifting into deployed containers.

## Decision

**The scope rule.** Every env key belongs to a plane, and the plane decides
*where the value is delivered*:

- **Operator** — keys consumed by the tooling *around* the code: framework
  identity (`PROJECT_NAME`, ports, subdirs), git-host declaration + tokens
  (FWADR-030), MCP server credentials, worker and launcher settings. Delivered
  to `$PROJECT_DIR/.env`; sourced at launch; ambient everywhere.
- **App** — keys the application runtime reads: database URLs, third-party API
  keys, service config. Delivered to that environment's CI variables and to the
  code repo's local `.env`. Never sourced by `claude-env`; never in the
  operator `.env`.

**Litmus:** *would this key belong in the deployed container's environment?*
Yes → app. No → operator. A key that seems to need both is two keys or a design
smell — surface it, don't duplicate it.

**Both planes are recorded in one file.** The values themselves live in the
project's tracked, encrypted `env.yaml`, and each entry's `places` carry out
this rule ([FWADR-041](fwadr-041-env-yaml.md)). The rule decides the places an
entry gets, not the file it is kept in. **A plaintext `.env` is never tracked**,
in any repo, on either plane.

Mechanisms:

1. **Stub.** `.env.example` states the scope rule and holds no app keys.
2. **Push-boundary guard (prevention).** The framework pre-push guard
   (`git-guard-pre-push.sh`, installed per-repo by sync step 4b per
   [FWADR-023](fwadr-023-main-push-guard.md)) refuses any push whose ref tips
   track a file named `.env` or `.sops-age-key.txt` (any depth), and any push
   whose root `env.yaml` holds a secret in the clear (FWADR-041). The push
   boundary is the existing choke point: it catches humans and agents alike,
   and covers worktrees for free.
3. **Session-start detection.** `sync-framework.sh` step 4e emits a NOTICE
   when any visible repo (parent or immediate subdir) *already tracks* a
   `.env` — the case prevention can't cover: the file committed before the
   guard existed, or a repo whose adopter-owned pre-push blocked guard
   installation.
4. **Visibility symlinks (ergonomics).** `sync-framework.sh` step 4f
   maintains read-convenience links at the parent —
   `$PROJECT_DIR/.env.<subdir>` → `<subdir>/.env` for every immediate-subdir
   repo that has an app env — so every env file is inspectable from the
   planning directory without changing what any process sources. Links are
   created when the target exists, re-pointed if wrong, removed when dangling,
   and never replace a regular file of the same name. They are ignored via the
   parent `.gitignore` (`.env.*` with `!.env.example` carve-out, appended by
   sync where a `.gitignore` exists).

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
- **Nothing checks an entry's places against the litmus.** An app secret
  routed to `operator` is ambient in every session; the file makes that
  visible in a diff, and the Strategist who routes it is the check.
- **A project that deliberately tracks a non-secret `.env`** (rare, and still
  discouraged) records the deviation in `dev_framework_exceptions.md` and
  forks the hook (drop the `FRAMEWORK-PUSH-GUARD` marker, merge the main
  check manually). No bypass env var is provided — an env-var bypass sourced
  from `.env` under `set -a` would disable the guard permanently and
  silently ([FWADR-023](fwadr-023-main-push-guard.md)).

## Consequences

- **Coherence surfaces:** this ADR; the `.env.example` stub;
  `git-guard-pre-push.sh` (+ its header and a cross-ref note in FWADR-023);
  `sync-framework.sh` steps 4e/4f + gitignore append; the template's own
  `.gitignore`; CLAUDE.md managed block ("Env scope");
  `context-management.md` §".env variables"; `migration-guide-split-layout.md`
  §4; the `launch_local.sh` app-env comment citing this ADR; FWADR-041.
- **One file serving both planes at runtime is still the violation.** The
  operator `.env` and a code repo's `.env` stay separate files; `env.yaml`
  records both and delivers each to its own.
- **Every push is subject to the env checks** — the tracking parent's
  included, which the landing and release check lets through.
- **Flat-layout projects** have one `.env` serving both planes by
  construction; the scope rule is fully realizable only under split layout —
  one more reason flat layout is legacy (FWADR-021).
