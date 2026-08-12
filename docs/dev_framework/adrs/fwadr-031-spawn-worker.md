# FWADR-031: `spawn_worker.sh` — launch a named, remote-controlled worker in one command

**Status:** accepted
**Date:** 2026-08-11
**Deciders:** user (framework author) + Template Developer

## Context

The user wanted to spin up worker Claude sessions with minimal ceremony — ideally
triggerable from a phone — each opening in a terminal at the project, with its
environment loaded, a recognizable name, and Remote Control enabled so it shows
up in the phone's session list. The hand-rolled version was four steps (open
terminal → `claude-env` → `/rename` → `/remote-control`), the last two being
interactive slash commands a launcher can't easily send.

The Claude Code CLI (v2.1.220) already exposes those as **launch flags**, which
collapses the whole sequence:

- `-n, --name <name>` sets the session display name — replaces `/rename`.
- `--remote-control [name]` starts with Remote Control enabled — replaces the
  interactive `/remote-control`.
- `--dangerously-skip-permissions` — the bypass `claude-env` already used.

So no fragile AppleScript keystroking is needed; one `claude …` invocation does it.

## Decision

Ship `scripts/spawn_worker.sh` as a synced dev-slot stub (seeded by
`sync-framework.sh`, alongside the FWADR-019 scripts):

```
spawn_worker.sh <name> ["initial prompt"]
```

It opens a macOS terminal that runs, in the project root:
`set -a; source .env; set +a; exec claude --dangerously-skip-permissions --name "<name>" --remote-control [prompt]`.
An optional second arg is sent as the worker's first message — arbitrary, so it
covers a role bootstrap (`"you are the Developer"`) or any task.

Design choices:

- **Self-contained, not dependent on the user's `claude-env`.** `claude-env` is a
  shell-rc function installed per machine (framework-shipped and confirmed at
  first contact since [FWADR-032](fwadr-032-claude-env-launcher.md), but
  installation remains opt-in), so an adopter may not have it. The script
  reimplements its core (cd + `source .env`) inline, which also runs the
  FWADR-030 git-auth wiring, so the worker's git is authenticated like any
  `claude-env` session.
- **Customized only via `.env`.** `WORKER_TERMINAL` (`iterm` default, or
  `terminal`) picks the terminal app; the project path is self-located from the
  script's own position. So the Strategist "customizes at setup" by setting one
  `.env` value — there is no per-repo script body to fill.
- **Temp-launcher indirection.** The command (with a name and an arbitrary prompt)
  is written to a `mktemp` script that the terminal runs, sidestepping
  AppleScript quote-escaping. The launcher `rm`s itself then `exec`s claude, so
  the tab becomes the worker and no temp file lingers.
- **`WORKER_DRYRUN=1`** prints the plan and the generated launcher without opening
  anything — testable on any platform.

The "cellphone" workflow is emergent, not new mechanism: you Remote-Control an
existing session from your phone, tell it to run `spawn_worker.sh <name>`, and the
new worker — Remote Control enabled — appears in your phone's session list, ready
to drive. `spawn_worker.sh` is the local action; Remote Control is what makes each
worker phone-reachable.

## Consequences

- **macOS only** (osascript). On other platforms it prints the exact manual
  command and exits non-zero — a named gap, not a silent failure.
- **First run needs macOS Automation (TCC) permission** to let the invoking
  terminal control the target app; the initial spawn triggers a one-time "allow
  control of iTerm2/Terminal" prompt. Grant it once, then spawns are instant.
  From a non-interactive context that can't answer the prompt (e.g. a headless
  agent Bash call), the AppleEvent times out — so `spawn_worker.sh` is run from
  an interactive terminal, and the osascript is wrapped in `with timeout of 30
  seconds` to fail fast with guidance rather than hang the 120s default. This was
  found by a live smoke test; the dry run alone could not surface it.
- **Copy-if-missing stub**, like the other dev-slot scripts (FWADR-019): existing
  adopters get it on next sync only if absent, so a future change to the script
  does not auto-propagate. Acceptable for an ops helper; consistent with the
  established dev-slot sync tier rather than inventing a new one.
- **Coherence surfaces, all in this change:** the stub script, its entry in the
  `sync-framework.sh` `DEV_SLOT_STUBS` list, the `WORKER_TERMINAL` declaration in
  `.env.example`, and this ADR.
- **Remote Control availability is the account's concern.** The flag enables it;
  if unavailable the worker terminal surfaces the error — the framework does not
  wrap or hide it.
- **One worker per name.** Names are the operator's handle (`dev-auth`, `orch-1`);
  the script does not enforce uniqueness. Reusing a name just launches another
  session with the same display name.

## Revision v1.1 (2026-08-11)

The project directory is now located by **walking up from the script to the
nearest ancestor that holds a `.env`**, rather than assuming "parent of
`scripts/`". The worker launches there — the planning directory where `.env`,
`CLAUDE.md`, and the planning git repo live (split layout, FWADR-021), which is
also where `.env` must be sourced. This resolves correctly wherever the script
sits (canonically `$PROJECT_DIR/scripts/`, but also the template's own
`_stubs/scripts/`), falling back to the parent of `scripts/` only if no `.env` is
found upward. Motivated by a spawned worker opening in `docs/dev_framework/_stubs`
during testing instead of the project root — the old "parent of `scripts/`" rule
was correct only for the canonical deploy location.
