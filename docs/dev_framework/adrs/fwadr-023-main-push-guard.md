# FWADR-023: Mechanical push guard — no direct push to `main`, no tag push, in a code repo

**Status:** accepted
**Date:** 2026-07-28
**Owner:** Template Developer

## Context

The framework's branch model says how code reaches `main` and how production
is released, but for a long time the rule was English-only: nothing on the
machine stopped a session from running `git push origin main`.

The gap was demonstrated live on an adopter project (makinrate, 2026-07-28):
a research-focused session committed work directly to `main` and mirrored the
same changes to another branch as separate commits — same feature, different
SHAs on both — producing four-file merge conflicts at the next release.
Under the framework's own doctrine ("a rule of the shape 'X always happens on
Y' must ship with the command or check that makes X mechanical"), this was a
named drift attractor waiting for exactly this incident.

## Decision

Ship the mechanism, framework-wide:

1. **Git pre-push guard.** `.claude/hooks/git-guard-pre-push.sh` (template-
   owned, synced to adopters like every hook) is a git `pre-push` hook. In a
   **code repo** it rejects:
   - any push that updates `refs/heads/main` — work lands there by PR,
     merged on the git host ([FWADR-035](fwadr-035-git-flow-mode.md)
     §"Landing on main");
   - any push that creates, moves or deletes a tag — a release tag is cut on
     the git host by the repo's `release` job when the stakeholder approves
     in the QA view ([FWADR-042](fwadr-042-qa-view-release.md)).

   The tracking parent (a repo that holds code repos, and carries plans
   rather than code) pushes `main` and tags freely. The guard checks the real
   refspecs on the hook's stdin — not command strings — so
   `git push origin main`, `push origin HEAD:main`, `push --all`,
   `push --tags`, and ref deletions are all caught regardless of phrasing.

2. **No bypass.** There is no allow variable and no sanctioned script. A
   variable sourced from `.env` under `set -a` would disable the guard
   permanently and silently; a script that sets one is a second release path.
   The paths that exist are the PR and the Approve button. When the QA view
   itself is down, the user creates the tag in the git host's interface,
   where the guard does not run and the host's own protection applies.

3. **SessionStart installation.** `sync-framework.sh` step 4b installs the
   guard into `.git/hooks/pre-push` of every code repo it can see: the
   project dir itself (flat layout) and every immediate subdirectory with
   `.git/` (split layout, including multi-repo projects). Install is
   idempotent (refreshes only when the template copy changed) and **never
   overwrites an adopter-owned pre-push hook** — a file without the
   `FRAMEWORK-PUSH-GUARD` marker gets a warning telling the adopter to merge
   the check manually. Worktrees share the parent repo's hooks directory, so
   Executor/Developer worktrees are covered automatically.

4. **Belt-and-braces recommendation.** The Strategist's first-contact
   interview recommends host-side protection: release tags protected, and
   `main` locked to PR landing (push = no one, merge = maintainers).
   Host-side protection is absolute but host-specific and unsyncable; the
   pre-push guard is the portable layer. On an agent host the guard does not
   run at all, and host protection is the only layer.

## Alternatives considered

- **Claude Code PreToolUse hook matching `git push` command strings.** Syncs
  automatically, but only guards Claude sessions and is evadable/false-
  positive-prone on refspecs, aliases, and `HEAD:main` forms. The git layer
  sees actual refs and guards humans and agents alike.
- **Host-side branch protection only.** Absolute where configured, but
  host-specific, manual per project, and nonexistent for `GIT_HOST=other` or
  bare remotes. Kept as a recommendation, not the mechanism.
- **Blocking commits on main (pre-commit) as well.** Considered and dropped:
  the damage from a stray local commit is recoverable until pushed. Push is
  the boundary that matters.
- **A bypass variable set by one named script** (`promote_dev_to_main.sh`).
  It was the release path until the QA view replaced it; kept as a fallback
  it would be a way to release without the checklist.

## Consequences

- The branch-model rule is enforced at the git layer on every adopter
  machine after their next SessionStart sync. Blast radius of the makinrate
  failure mode drops to zero for pushes; mirror-by-recommit on `main` can no
  longer land remotely.
- Adopters with a pre-existing custom `pre-push` hook keep it and get a
  per-session warning until they merge the guard's check — named, visible
  drift instead of silent non-enforcement.
- A repo that uses tags for something other than releases cannot push them
  from a laptop; it creates them on the host, or records the deviation in
  `dev_framework_exceptions.md` and forks the hook.
- **The guard file carries two more checks** — it refuses pushes whose ref
  tips track a `.env` or the decryption key
  ([FWADR-033](fwadr-033-env-scope-rule.md)), and pushes whose `env.yaml`
  holds a secret in the clear ([FWADR-041](fwadr-041-env-yaml.md)).
  Installation and the never-overwrite rule are the same for all three.
