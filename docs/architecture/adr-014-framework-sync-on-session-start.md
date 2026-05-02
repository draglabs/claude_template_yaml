# ADR-014: Framework sync on SessionStart

**Status:** accepted
**Date:** 2026-04-23
**Deciders:** David (template author), Strategist session

## Context

Two related problems the template had to solve together:

1. **Framework drift in adopting projects.** `docs/dev_framework/` is the canonical SOP — the role docs, the subagent briefs, the session policy, the coding standards. If an adopting project's Strategist edits those files locally to accommodate some project reality, the project silently diverges from every other adopter. Future template updates become manual merges. The "copy-paste the new framework over" story breaks.

2. **Context-reset re-orientation already exists but doesn't cover the sync.** ADR-012 added a `SessionStart` hook that re-orients the session after compact/clear/resume/startup. Adding framework sync to the same trigger closes the loop: after any context reset, the session also has the freshest canonical framework on disk, not whatever-was-there-whenever-this-project-was-cloned.

Policy text alone can't enforce "don't edit `docs/dev_framework/*`" — that's another English-only rule. The mechanical equivalent is to overwrite any such edits on every session start. Projects that need to deviate record the deviation in `docs/framework_exceptions/dev_framework_exceptions.md`, which the sync never touches.

## Decision

Ship a second `SessionStart` hook — `.claude/hooks/sync-framework.sh` — that runs before the re-orient hook. It does four things:

1. **Destructively sync `docs/dev_framework/`** from the canonical template via `rsync -a --delete`. Any local edits to that tree are overwritten without warning. This is the "push it back into alignment" enforcement — if the system went wild and started editing framework docs, the next session start restores the canonical state.

2. **Destructively sync `.claude/hooks/`** from the canonical template. The hooks themselves are part of the framework and must stay current.

3. **Idempotent-initialize `docs/framework_exceptions/`**. On first sync (folder missing), copy pristine stubs from `$TEMPLATE_ROOT/docs/dev_framework/_stubs/framework_exceptions/`. On subsequent syncs, leave existing files alone — the adopter's accumulated exceptions are preserved.

4. **Reconcile CLAUDE.md via managed-block markers.** The template's CLAUDE.md wraps framework-owned sections in `<!-- BEGIN FRAMEWORK MANAGED -->` / `<!-- END FRAMEWORK MANAGED -->`. The sync script extracts that block from the template and replaces the corresponding block in the local CLAUDE.md. Content outside the markers (project variables, commands, stack, locked decisions, dev mode) is untouched. This lets the framework evolve CLAUDE.md's framework-side content centrally without destroying per-project values.

### Template root discovery

Resolved in three-tier priority:

1. `$CLAUDE_TEMPLATE_ROOT` environment variable (shell-level).
2. `CLAUDE_TEMPLATE_ROOT=` line in the project's `.env` file.
3. Sibling directory `../claude_template`.

If none resolves, the hook warns and exits 0 — sync is value-add, never blocking.

### Template-self detection

The sync script compares the resolved template root against the current project's resolved path (`pwd -P`). If equal, sync skips with a no-op message. This prevents the template from syncing onto itself.

### Failure posture

Every step in the sync script is non-blocking. rsync errors warn and continue. Missing stubs warn and continue. Missing markers warn and continue. A broken sync never prevents a session from starting.

## Consequences

**What this buys:**

- Framework drift is mechanically prevented. An adopter's Strategist can edit framework docs on any given day, but the next session start erases those edits and warns nothing — the lesson is "don't edit there; use the exceptions file."
- The "copy-paste the new framework over" story becomes automatic. The user edits framework docs in `claude_template` itself; every adopting project pulls the change on next session start.
- CLAUDE.md stays in sync on the framework-y sections without losing per-project content.
- `framework_exceptions/` initializes itself for new adopters — no manual setup step.

**What this costs:**

- Silent overwrite is dangerous if the template's own dev_framework gets into a bad state — adopters pull breakage. Mitigation: the template is curated; framework-doc changes go through the Strategist on the template repo, not arbitrary commits. This is the same risk model as pushing any shared dependency.
- Adopters lose the ability to locally tweak framework docs for testing. Deliberate — the policy is "tweak the template, not the adopting project." For short-lived experiments, change the template on a feature branch and have adopters sync from that branch by setting `$CLAUDE_TEMPLATE_ROOT` to its working copy.
- The managed-block pattern in CLAUDE.md is fragile if markers are deleted or moved. Mitigation: the sync warns when markers are missing on either side; it does not fabricate them.

**What this does NOT do:**

- Does not touch `docs/framework_exceptions/*` once initialized. Those files are project-owned.
- Does not touch `.claude/settings.json` — that file has per-project permissions blocks. Adopters merge hook registrations manually. (Future work: a more surgical settings.json merge.)
- Does not delete adopter-owned hooks. `.claude/hooks/` syncs additively, not destructively — a custom `my-project-pre-push.sh` in an adopter's hooks folder survives. The asymmetry with `docs/dev_framework/*` (fully destructive sync) is intentional: framework docs have a clean "template owns everything" rule; hook scripts are a shared namespace where adopters legitimately extend.
- Does not verify the template is itself healthy. A broken template ships broken. That's addressed by the Strategist's alignment audits on the template repo.

## First-time adopter bootstrap (one-time manual step)

The sync hook runs on `SessionStart`, but `SessionStart` hooks only fire if they are registered in `.claude/settings.json`. A brand-new adopter who has only cloned the template's `docs/` tree does NOT yet have the hook registration — so the first `/clear` in a fresh adopter fires no hook, syncs nothing, and the adopter is stuck in bootstrap limbo.

To unblock the first session, the adopter must manually add this block to their `.claude/settings.json` (merging into an existing `hooks` key if present):

```json
"hooks": {
  "SessionStart": [
    {
      "hooks": [
        { "type": "command", "command": "bash $CLAUDE_PROJECT_DIR/.claude/hooks/sync-framework.sh" },
        { "type": "command", "command": "bash $CLAUDE_PROJECT_DIR/.claude/hooks/session-reorient.sh" }
      ]
    }
  ]
}
```

After this one-time edit, sync takes over: every subsequent session start pulls the canonical framework and hooks from `claude_template`, keeps them current, and the adopter never edits framework content directly again.

The adopter also needs to have the hook scripts themselves on disk. On the first sync, `.claude/hooks/` is populated from the template. But on the very first bootstrap — before the first sync ever runs — the scripts must be present. The simplest path: copy `.claude/hooks/sync-framework.sh` and `.claude/hooks/session-reorient.sh` from the template by hand, alongside the settings.json edit. After that, the sync keeps them current automatically.

## Alternatives considered

1. **Git-clean check before destructive sync.** Skip overwrite if local `docs/dev_framework/*` is dirty. Rejected per user decision — if the system went wild and edited framework docs, the user WANTS them forcibly reset, not preserved.
2. **Diff-only mode with user confirmation.** Report drift, let the user run a separate sync command. Rejected — adds a manual step, defeats "first thing it should do after /clear."
3. **Git submodule for `docs/dev_framework/`.** Fully isolates the framework, and git detects drift automatically. Rejected as over-engineered for this stage — submodules introduce their own friction (init, update, detached HEAD). rsync-based sync is simpler and achieves the same goal.
4. **Symlink `docs/dev_framework/` to the template.** Makes the canonical source literal but breaks when the template isn't on the same machine (different dev machine, CI, etc.). Rejected.
5. **Always-copy CLAUDE.md wholesale.** Would destroy per-project values. Rejected.
6. **Semantic merge of CLAUDE.md.** Harder, error-prone. Rejected in favor of structural managed-block markers.

## Acceptance criteria

- `.claude/hooks/sync-framework.sh` runs on macOS and Linux under bash, no external dependencies beyond `rsync`, `sed`, `grep`, POSIX utilities.
- Manual test: in an adopting project, modify `docs/dev_framework/session-policy.md`, run `/clear`, confirm the file is restored to the template's version.
- Manual test: in an adopting project with no `docs/framework_exceptions/` folder, run `/clear`, confirm the folder is created with the three stub files.
- Manual test: `$CLAUDE_TEMPLATE_ROOT` unset, `.env` absent, `../claude_template` absent — run `/clear`, confirm the hook warns but does not error.
- Manual test: run `/clear` in the template repo itself, confirm the hook reports "This project IS the template — no sync."
- `session-policy.md` gains a §"Framework sync on context resets" that points at this ADR.

## Revision (v1.1, 2026-05-02) — Template renamed; resolution chain narrowed

**Problem.** Two changes shipped together:

1. **Template renamed.** The canonical template repo is now `claude_template_yaml` (this repo). The original `claude_template` is forked away from. Every reference to the old name in framework code paths and docs would silently misroute — adopters with `../claude_template` siblings on disk would keep syncing from a defunct location.
2. **Shell-env resolution dropped.** A stale `CLAUDE_TEMPLATE_ROOT` exported in an adopter's shell config (commonly an old dotfile pointing at `~/code/claude_template`) silently shadows everything else. Failure mode: adopter pulls framework from a long-defunct location for months without noticing. Removing the shell-env path eliminates the silent-shadow class entirely.

**Decision.** Effective 2026-05-02:

- Template root is `claude_template_yaml`. All references in hooks, framework docs, and ADRs use the new name.
- Resolution chain narrows from 3 sources to 2 (with deeper sibling fallback to handle nested adopter project layouts):
  1. `CLAUDE_TEMPLATE_ROOT=` line in the project's `.env` file.
  2. `../claude_template_yaml`
  3. `../../claude_template_yaml`
  4. `../../../claude_template_yaml`
- Shell environment variables (`$CLAUDE_TEMPLATE_ROOT` from the parent shell) are intentionally NOT consulted. Adopters configure via local `.env` or rely on the sibling-depth fallback.
- The deeper sibling fallback (`../..`, `../../..`) replaces the prior single-depth `../claude_template` to support adopters whose projects are nested under `code/projects/<team>/<repo>` rather than directly under `code/`.

**Surfaces updated:** lines 33–35 (Template root discovery), line 59 (alternative consideration about feature-branch experimentation via `$CLAUDE_TEMPLATE_ROOT`), line 88 (first-time bootstrap reference to `claude_template`), line 106 (acceptance test for unset env). Canonical specification lives in `.claude/hooks/sync-framework.sh` (the script), `CLAUDE.md` §"Framework sync on SessionStart", and `dev_framework/session-policy.md` §"Framework sync on context resets".

**Migration.** The old `claude_template` repo on adopters' disks does not need to be removed — it is simply no longer found by the resolution chain. Adopters who relied on the shell-env override path must move the value into their project's `.env` file (or rename/relocate the template repo to one of the sibling-fallback paths). Adopters with no override saw no change other than the template-name update.

**Why a Revision instead of a new ADR.** The mechanism (sync on SessionStart, destructive into `dev_framework/`, additive into `hooks/`, managed-block on CLAUDE.md) is unchanged. Only the input-resolution table and the template name move. New rule, same principle.
