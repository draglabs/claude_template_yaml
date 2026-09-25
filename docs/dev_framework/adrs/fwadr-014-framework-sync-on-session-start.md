# FWADR-014: Framework sync on SessionStart

**Status:** accepted
**Date:** 2026-04-23
**Deciders:** David (template author), Strategist session

## Context

Two related problems the template had to solve together:

1. **Framework drift in adopting projects.** `docs/dev_framework/` is the canonical SOP — the role docs, the subagent briefs, the session policy, the coding standards. If an adopting project's Strategist edits those files locally to accommodate some project reality, the project silently diverges from every other adopter. Future template updates become manual merges. The "copy-paste the new framework over" story breaks.

2. **Context-reset re-orientation already exists but doesn't cover the sync.** FWADR-012 added a `SessionStart` hook that re-orients the session after compact/clear/resume/startup. Adding framework sync to the same trigger closes the loop: after any context reset, the session also has the freshest canonical framework on disk, not whatever-was-there-whenever-this-project-was-cloned.

Policy text alone can't enforce "don't edit `docs/dev_framework/*`" — that's another English-only rule. The mechanical equivalent is to overwrite any such edits on every session start. Projects that need to deviate record the deviation in `docs/framework_exceptions/dev_framework_exceptions.md`, which the sync never touches.

## Decision

Ship a second `SessionStart` hook — `.claude/hooks/sync-framework.sh` — that runs before the re-orient hook. It does five things:

1. **Destructively sync `docs/dev_framework/`** from the canonical template via `rsync -a --delete`. Any local edits to that tree are overwritten without warning. This is the "push it back into alignment" enforcement — if the system went wild and started editing framework docs, the next session start restores the canonical state.

2. **Sync `.claude/hooks/` without delete** from the canonical template (`rsync -a`). Template hooks are overwritten — they are part of the framework and must stay current; adopter-owned hooks survive (see "What this does NOT do").

3. **Idempotent-initialize `docs/framework_exceptions/`**. On first sync (folder missing), copy pristine stubs from `$TEMPLATE_ROOT/docs/dev_framework/_stubs/framework_exceptions/`. On subsequent syncs, leave existing files alone — the adopter's accumulated exceptions are preserved.

4. **Reconcile CLAUDE.md via managed-block markers.** The template's CLAUDE.md wraps framework-owned sections in `<!-- BEGIN FRAMEWORK MANAGED -->` / `<!-- END FRAMEWORK MANAGED -->`. The sync script extracts that block from the template and replaces the corresponding block in the local CLAUDE.md. Content outside the markers (project variables, commands, stack, locked decisions, dev mode) is untouched. This lets the framework evolve CLAUDE.md's framework-side content centrally without destroying per-project values.

5. **Place stub scripts by ownership** (§"Stub scripts").

### Stub scripts

Stubs under `docs/dev_framework/_stubs/` copy to project paths (`scripts/`, `docs/dev/slots.yaml`, `.env.example`). Each is one of two kinds, and **the file says which**:

- **Framework-owned** — no project-specific body; carries the header line `FRAMEWORK-OWNED — overwritten on every sync; do not edit`. The sync overwrites the project copy whenever it differs from the template, so a fix reaches every existing adopter on its next session start. Changes go to the template (`fwreq-*`), never into the project copy. Today: `promote_dev_to_main.sh`, `check-touches.sh`, `check-researcher-scope.sh`, `check-curator-scope.sh`, `doc_churn_audit.sh`, `port_ledger.sh`, `setup_dev_slots.sh`, `spawn_worker.sh`.
- **Seed-once** — holds a project body or project values (`launch_local.sh`, `teardown_local.sh`, `main_to_prod.sh`, `slots.yaml`, `.env.example`). Copied when missing, never overwritten; improvements to their generic parts reach a filled-in copy only by manual merge ([FWADR-019](fwadr-019-dev-slots-and-deploy-stubs.md)).

The marker lives in the file, not a list in the hook, so whoever opens a script can see whether editing it is legal, and moving a script between kinds is one header line.

### Template root discovery

The canonical template is `claude_template_yaml`. Resolved in priority order:

1. `CLAUDE_TEMPLATE_ROOT=` line in the project's `.env` file.
2. `CLAUDE_TEMPLATE_ROOT=` line in the `.env` of any immediate subdirectory that has `.git/` (split-layout adopters who keep `.env` in the code repo — [FWADR-021](fwadr-021-split-layout.md)).
3. `../claude_template_yaml`
4. `../../claude_template_yaml`
5. `../../../claude_template_yaml`

The deeper sibling fallbacks support adopters nested under `code/projects/<team>/<repo>` rather than directly under `code/`. Sibling lookups name only `claude_template_yaml`; the dormant predecessor `claude_template`, if still on disk, is never found.

**Shell environment variables are intentionally not consulted.** A stale `CLAUDE_TEMPLATE_ROOT` export in a dotfile (commonly pointing at a long-defunct template location) would silently shadow every other source, and the adopter would pull framework from the wrong place for months without noticing. Configure via `.env` or rely on the sibling fallback.

If none resolves, the hook warns and exits 0 — sync is value-add, never blocking.

Canonical specification of the chain: `.claude/hooks/sync-framework.sh`; mirrored in CLAUDE.md §"Framework sync on SessionStart" and `session-policy.md` §"Framework sync on context resets".

### Template-self detection

The sync script compares the resolved template root against the current project's resolved path (`pwd -P`). If equal, sync skips with a no-op message. This prevents the template from syncing onto itself.

### Failure posture

Every step in the sync script is non-blocking. rsync errors warn and continue. Missing stubs warn and continue. Missing markers warn and continue. A broken sync never prevents a session from starting.

## Consequences

**What this buys:**

- Framework drift is mechanically prevented. An adopter's Strategist can edit framework docs on any given day, but the next session start erases those edits and warns nothing — the lesson is "don't edit there; use the exceptions file."
- The "copy-paste the new framework over" story becomes automatic. The user edits framework docs in `claude_template_yaml` itself; every adopting project pulls the change on next session start.
- CLAUDE.md stays in sync on the framework-y sections without losing per-project content.
- `framework_exceptions/` initializes itself for new adopters — no manual setup step.

**What this costs:**

- Silent overwrite is dangerous if the template's own dev_framework gets into a bad state — adopters pull breakage. Mitigation: the template is curated; framework-doc changes go through the Strategist on the template repo, not arbitrary commits. This is the same risk model as pushing any shared dependency.
- Adopters lose the ability to locally tweak framework docs for testing. Deliberate — the policy is "tweak the template, not the adopting project." For short-lived experiments, change the template on a feature branch and have adopters sync from that branch by pointing their `.env` `CLAUDE_TEMPLATE_ROOT=` line at its working copy.
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

After this one-time edit, sync takes over: every subsequent session start pulls the canonical framework and hooks from `claude_template_yaml`, keeps them current, and the adopter never edits framework content directly again.

The adopter also needs to have the hook scripts themselves on disk. On the first sync, `.claude/hooks/` is populated from the template. But on the very first bootstrap — before the first sync ever runs — the scripts must be present. The simplest path: copy `.claude/hooks/sync-framework.sh` and `.claude/hooks/session-reorient.sh` from the template by hand, alongside the settings.json edit. After that, the sync keeps them current automatically.

## Alternatives considered

1. **Git-clean check before destructive sync.** Skip overwrite if local `docs/dev_framework/*` is dirty. Rejected per user decision — if the system went wild and edited framework docs, the user WANTS them forcibly reset, not preserved.
2. **Diff-only mode with user confirmation.** Report drift, let the user run a separate sync command. Rejected — adds a manual step, defeats "first thing it should do after /clear."
3. **Git submodule for `docs/dev_framework/`.** Fully isolates the framework, and git detects drift automatically. Rejected as over-engineered for this stage — submodules introduce their own friction (init, update, detached HEAD). rsync-based sync is simpler and achieves the same goal.
4. **Symlink `docs/dev_framework/` to the template.** Makes the canonical source literal but breaks when the template isn't on the same machine (different dev machine, CI, etc.). Rejected.
5. **Always-copy CLAUDE.md wholesale.** Would destroy per-project values. Rejected.
6. **Semantic merge of CLAUDE.md.** Harder, error-prone. Rejected in favor of structural managed-block markers.
7. **Shell-env `$CLAUDE_TEMPLATE_ROOT` as a resolution source.** Rejected — a stale export silently shadows every other source (see §"Template root discovery").
8. **Seed every stub once and never overwrite.** Uniform and simple, but no fix to generic plumbing ever reached an existing adopter: a wrong-repo bug in `promote_dev_to_main.sh` (it released a git-tracked parent instead of the code repo) and a rewritten `doc_churn_audit.sh` would each have needed a manual delete-and-reseed in every project. Rejected for scripts with no project body; kept for stubs that hold one.

## Acceptance criteria

- `.claude/hooks/sync-framework.sh` runs on macOS and Linux under bash, no external dependencies beyond `rsync`, `sed`, `grep`, POSIX utilities.
- Manual test: in an adopting project, modify `docs/dev_framework/session-policy.md`, run `/clear`, confirm the file is restored to the template's version.
- Manual test: in an adopting project with no `docs/framework_exceptions/` folder, run `/clear`, confirm the folder is created with the three stub files.
- Manual test: no `CLAUDE_TEMPLATE_ROOT=` line in any `.env`, no `claude_template_yaml` at any sibling depth — run `/clear`, confirm the hook warns but does not error.
- Manual test: run `/clear` in the template repo itself, confirm the hook reports "This project IS the template — no sync."
- Manual test: in an adopting project, edit `scripts/promote_dev_to_main.sh` and `scripts/launch_local.sh`, run `/clear`; the first is restored ("updated framework-owned"), the second is untouched.
- `session-policy.md` gains a §"Framework sync on context resets" that points at this ADR.
