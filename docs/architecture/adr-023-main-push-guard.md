# ADR-023: Mechanical main-push guard + sanctioned promotion script

**Status:** accepted
**Date:** 2026-07-28
**Owner:** Template Developer

## Context

The framework's branch model has always said that `main` only moves at
phase-exit promotion (or explicit emergency bypass) with user authorization —
`session-policy.md` §"Branching and isolation", §"Phase exit gate",
CLAUDE.md §"Branch model". But the rule was English-only: nothing on the
machine stopped a session from running `git push origin main`.

The gap was demonstrated live on an adopter project (makinrate, 2026-07-28):
a research-focused session committed work directly to `main` and mirrored the
same changes to `dev` as separate commits — same feature, different SHAs on
both branches — producing four-file merge conflicts at the next promotion.
Under the framework's own doctrine ("a rule of the shape 'X always happens on
Y' must ship with the command or check that makes X mechanical"), this was a
named drift attractor waiting for exactly this incident.

## Decision

Ship the mechanism, framework-wide:

1. **Git pre-push guard.** `.claude/hooks/git-guard-pre-push.sh` (template-
   owned, synced to adopters like every hook) is a git `pre-push` hook that
   rejects any push updating `refs/heads/main` unless
   `FRAMEWORK_ALLOW_MAIN_PUSH=1` is set. It checks the real refspecs on the
   hook's stdin — not command strings — so `git push origin main`,
   `push origin HEAD:main`, `push --all`, and ref deletions are all caught
   regardless of phrasing.

2. **SessionStart installation.** `sync-framework.sh` step 4b installs the
   guard into `.git/hooks/pre-push` of every code repo it can see: the
   project dir itself (flat layout) and every immediate subdirectory with
   `.git/` (split layout, including multi-repo projects). Install is
   idempotent (refreshes only when the template copy changed) and **never
   overwrites an adopter-owned pre-push hook** — a file without the
   `FRAMEWORK-PUSH-GUARD` marker gets a warning telling the adopter to merge
   the check manually. Worktrees share the parent repo's hooks directory, so
   Executor/Developer worktrees are covered automatically.

3. **Sanctioned bypass = one named script.** The stub
   `scripts/promote_dev_to_main.sh` (seeded to adopters like the other
   ADR-019 script stubs; generic, no fill-in needed) is the only place
   `FRAMEWORK_ALLOW_MAIN_PUSH=1` is ever set:
   - **Default mode** — phase-exit promotion. Verifies `main` is checked out
     and HEAD is a merge commit whose second parent is `dev`'s current head
     (the annotated promotion merge already made per session-policy
     §"Promotion commit"), then pushes. The merge itself remains the
     Orchestrator's (or Developer's) act; the script owns only the guarded
     push.
   - **`--bypass` mode** — the emergency-bypass path (production fire,
     `[bypass]`-tagged commit directly on main). Skips the merge-shape check,
     prints the outstanding bypass duties (back-merge, retrospective
     Reviewer, incident log). Loud on purpose.

4. **Belt-and-braces recommendation.** The Strategist's first-contact
   interview now recommends enabling host-side branch protection on `main`
   where the host supports it. Host-side protection is absolute but
   host-specific and unsyncable; the pre-push guard is the portable layer.

**`FRAMEWORK_ALLOW_MAIN_PUSH` must never appear in `.env`** — framework
scripts source `.env` wholesale (`set -a`), which would leave the guard
permanently bypassed. The promotion script refuses to run if it finds the
variable already set in the environment, which catches exactly this mistake.

## Alternatives considered

- **Claude Code PreToolUse hook matching `git push` command strings.** Syncs
  automatically, but only guards Claude sessions and is evadable/false-
  positive-prone on refspecs, aliases, and `HEAD:main` forms. The git layer
  sees actual refs and guards humans and agents alike.
- **Host-side branch protection only.** Absolute where configured, but
  host-specific, manual per project, and nonexistent for `GIT_HOST=other` or
  bare remotes. Kept as a recommendation, not the mechanism.
- **Blocking commits on main (pre-commit) as well.** Considered and dropped:
  the promotion merge is itself a commit on main, bypass commits are
  legitimate commits on main, and the damage from a stray local commit is
  recoverable until pushed. Push is the boundary that matters.

## Consequences

- The branch-model rule is now enforced at the git layer on every adopter
  machine after their next SessionStart sync. Blast radius of the makinrate
  failure mode drops to zero for pushes; mirror-by-recommit on `main` can no
  longer land remotely.
- Adopters with a pre-existing custom `pre-push` hook keep it and get a
  per-session warning until they merge the guard's check — named, visible
  drift instead of silent non-enforcement.
- A user who genuinely wants to push main outside the two sanctioned modes
  must consciously set `FRAMEWORK_ALLOW_MAIN_PUSH=1` — possible, but now an
  explicit act that can't happen by reflex.
- `session-policy.md` §"Promotion commit", §"Phase exit gate" step 7, and
  §"Emergency bypass" step 1 now route through the script; the English rule
  and its mechanism ship together in this change.
