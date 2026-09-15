# FWADR-032: `claude-env` launchers — .env-bound Claude launch, confirmed at first contact

**Status:** accepted
**Date:** 2026-08-11
**Deciders:** user (framework author) + Template Developer

## Context

Two framework mechanisms depend on `.env` being in Claude Code's **process env
at launch**, and both fail *silently* when it isn't:

1. **MCP credentials.** Claude Code expands `.mcp.json` env vars from its own
   process env, not from `.env` (CLAUDE.md §"MCP (.mcp.json)"). Launched bare,
   env-backed servers boot with empty credentials.
2. **Git auth.** The FWADR-030 auto-wire block at the bottom of `.env` only
   executes when `.env` is sourced. Launched bare, git has no credential helper.

The framework's answer to date was an English-only preamble — "run
`set -a; source .env; set +a` before `claude`" — repeated in CLAUDE.md and two
Strategist reminders. That is exactly the drift-bait shape the framework
doctrine rejects: a rule with no mechanism. The user's actual practice was a
personal `claude-env` zsh function (cd → require `.env` → source → launch),
which FWADR-031 explicitly noted was *not* framework-shipped and so couldn't be
relied on in adopter projects.

## Decision

Make the launcher canonical, its placement part of project initialization, and
launch-without-env mechanically detected:

1. **Ship the launcher as a synced snippet** at
   `docs/dev_framework/_stubs/shell/claude-env.zsh` (rides the wholesale
   `docs/dev_framework/` sync; deliberately NOT in the `DEV_SLOT_STUBS`
   copy-to-project list — it installs into the user's shell rc, per machine,
   not into a project tree). Three **named variants**, choice made at every
   launch by name, zero stored state:
   - `claude-env [dir]` — safe: normal permission prompts.
   - `claude-env-yolo [dir]` — adds `--dangerously-skip-permissions`.
   - `load-env [dir]` — sources `.env` into the current shell, launches
     nothing: for manual framework-script runs and FWADR-030 git auth in a
     bare terminal. Permission-neutral; installs with either launch variant.

   All three refuse to act when the target directory has no `.env` — fail
   loudly, never a half-bound session or shell.

2. **First-contact interview Block 0** (`templates/first-contact-interview.md`;
   trigger in `strategist.md` §"First-contact interview"): before Block 1, the
   Strategist confirms the launcher is installed in the user's shell rc —
   presenting both variants and letting the user choose what to install (safe
   only, or both). Checking/editing `~/.zshrc` is outside the project tree, so
   it happens only with the user's explicit go-ahead in the interview.

3. **Session-start binding check** (`sync-framework.sh` step 0): if a project
   `.env` declaring `PROJECT_NAME` exists but `PROJECT_NAME` is absent from
   the hook's (inherited) process env, the session was launched unbound → emit
   a NOTICE naming the consequence (MCP creds + FWADR-030 git auth dead this
   session) and the fix (relaunch via `claude-env`). A NOTICE, not a hard
   fail: env-less quick sessions (doc reads) stay legal, and hooks are
   value-add, never session-start blockers (FWADR-014).

## Consequences

- **Coherence surfaces, all in this change:** the shell stub, strategist.md
  (Block 0 + the two preamble reminders now pointing at `claude-env`), the
  `sync-framework.sh` step-0 check, CLAUDE.md §"MCP (.mcp.json)" managed
  block, `dev_framework.md` §"Git-host neutrality" launch-step wording,
  `.env.example` header, a FWADR-031 touch-up (the "not framework-synced"
  claim), and this ADR.
- **Installation stays per-machine opt-in.** The framework ships and confirms
  the launcher; it never edits a shell rc unasked. A user who declines still
  gets the step-0 NOTICE every unbound session — nagging is the enforcement.
- **The sentinel is `PROJECT_NAME`**, guarded by a grep that the found `.env`
  actually declares it — so an app-only `.env` (no framework variables) never
  false-positives. A `PLACEHOLDER` value still proves sourcing happened, which
  is the only thing the check claims.
- **Detection is one session late by nature.** The hook can detect but not
  repair (env must exist before the process starts), so the NOTICE instructs
  relaunch. Same restart semantics as `.mcp.json` edits.
- **`--dangerously-skip-permissions` stays a user-facing choice**, made
  per-launch by function name — the framework never defaults anyone into
  bypass mode, and no `.env` flag can silently flip a project into it.

## Revision (v1.1) — 2026-09-15: launcher seeds `.env` from `.env.example`

Field experience from a fresh adopter on 2026-09-15: the Strategist's first-contact interview opened on a two-line, hand-written `.env` (a token and one variable nothing reads) and had to ask every identity question from scratch. The user's question — "what could I put in `.env` up front so the interview doesn't have to ask?" — was already answered by `.env.example`; the adopter simply never received it as `.env`. Three defects compounded:

1. **Chicken-and-egg at launch.** The launcher refused to start without `.env`, but the only thing that seeded `.env.example` into the project was the sync hook, which runs inside a session. The user wrote a minimal `.env` by hand to get past the launcher, and that file is what the interview found.
2. **README quick start taught the two-line file** (create `.env` with `DEFAULT_CODE_SUBDIR` and `CLAUDE_TEMPLATE_ROOT`) and omitted `.env.example` from the copy list.
3. **The interview had no pre-flight.** It ran the question list in order regardless of what `.env` already held.

**Decision.** Close the gap at the earliest mechanical point, never by writing into an existing `.env`:

- **`_claude_env_source` seeds.** When `.env` is absent and `.env.example` is present, the launcher copies the starter to `.env`, prints "fill the MINIMUM TO BOOT block, then relaunch", and still refuses to launch. An existing `.env` is never touched. The installer sources the adopter's synced snippet by path, so this propagates on the next sync plus a new shell.
- **`.env.example` leads with a `MINIMUM TO BOOT` block** — the eight variables every role needs (`PROJECT_NAME`, `PROJECT_SUB`, `PROJECT_WEBSITE`, `PROJECT_PORTS`, `DEV_ENVIRONMENT_MODE`, `GIT_HOST`, the host token, `DEFAULT_CODE_SUBDIR`) — with everything else under "Optional". `DEFAULT_CODE_SUBDIR` moved up from the split-layout section; `CLAUDE_TEMPLATE_ROOT` stays optional.
- **The interview reads `.env` first** (`templates/first-contact-interview.md` §"Pre-flight"): set values are batch-confirmed in one table, `PLACEHOLDER`/empty lines are the only questions, and variables missing from a hand-written file are appended from `.env.example` rather than the file being replaced.
- **README quick start** copies `.env.example`, fills the MINIMUM TO BOOT block, and launches via `claude-env`, not bare `claude`.

**Consequences.** A fully filled `.env` turns Block 1 of the interview into one confirmation. The launcher gains a write (one `cp`, only when no `.env` exists), which is the first time it touches the filesystem; the guard is "absent target, present source" and nothing else. Coherence surfaces in this change: the shell stub, `.env.example`, the interview template, `strategist.md` §"First-contact interview", `README.md`, and this revision.
