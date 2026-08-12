# FWADR-012: Automatic re-orientation on context resets

**Status:** accepted
**Date:** 2026-04-23
**Deciders:** David (template author), Strategist session

## Context

Claude Code sessions lose context through four mechanisms: fresh startup, `--resume` / `--continue`, manual `/clear`, and automatic or manual `/compact`. All four can drop the role doc, CLAUDE.md, and other load-bearing session-start context. The framework relied on English-only policy ("re-read your role doc after compaction") to address this, which reads well but fails at the moment it matters — the session that just lost context is also the session that doesn't know it needs to re-orient.

This violates the template's own doctrine: **a rule of the shape "X always happens on Y" must ship in the same PR as the command or check that makes X mechanical.** Context-reset re-orientation was a rule without a mechanism.

Claude Code's `SessionStart` hook fires on all four reset paths with a `source` value discriminating which one. Hook stdout is injected into the post-reset context as a system message. This is the mechanism.

## Decision

Ship a `SessionStart` hook at `.claude/hooks/session-reorient.sh`, wired in `.claude/settings.json`, that emits a re-orientation instruction tailored to the `source` value. The injected text points agents at CLAUDE.md's Roles table and the per-project deviations file (see ADR and `dev_framework_exceptions.md`) and — for Orchestrator sessions — reminds them to reconcile the status ledger before dispatching.

Hook coverage:

| `source` | Behavior |
|---|---|
| `startup` | Point at Roles table; prompt user for role declaration if none stated. |
| `resume` | Re-read role doc; flag possible state drift since last activity. |
| `compact` | Re-read role doc + CLAUDE.md locked decisions + exceptions file; Orchestrators re-run ledger reconciliation. |
| `clear` | Starting fresh; confirm role; same re-read list as compact. |

Script is pure bash (no jq / python dependency) so it runs on any dev machine that adopts the template. Script uses `$CLAUDE_PROJECT_DIR` for portability when the template is copy-pasted into other repos.

## Consequences

**What this buys:**

- Re-orientation becomes mechanical. The session that just lost context is told what to re-read, by the harness, before its next substantive action.
- One mechanism covers all four reset paths.
- The hook is part of the template; adopters inherit the behavior automatically.
- Auditable — the injected text is visible in the transcript, so drift (agents ignoring the reminder) is observable.

**What this costs:**

- ~50 lines of shell and ~15 lines of settings JSON added to every project that adopts the template.
- A small startup delay at every session start while the hook runs. Originally the script did no I/O beyond reading stdin; Revision v1.1 adds one quiet `git fetch` per project repo (bounded by prompt/stall guards — see below).
- The hook itself is English-only once it has injected — the agent still has to choose to obey. Acceptable because the injection happens at the one moment the agent is most likely to accept orientation instructions (immediately post-reset, before the agent has committed to any interpretation).

**What this does NOT do:**

- Does not force agents to re-read docs; it instructs them. An agent that ignores the injection is visible in the transcript and can be corrected.
- Does not detect role changes silently — the `clear` case explicitly asks the user to state the role.
- Does not produce a proactive assistant turn after `/compact` or `/clear`. Claude Code is turn-reactive: no hook event triggers an assistant message. The injected re-orientation text surfaces on the next user turn. Framework convention is documented in `session-policy.md` §"Automatic re-orientation on context resets": users send a one-word trigger (`ack`, `continue`, `role?`) after a reset to get the session to re-orient.

## Alternatives considered

1. **Document the re-orientation rule in CLAUDE.md; no hook.** Rejected — this is the status quo ante, and it doesn't fire at the moment it matters. The doctrine against English-only rules applies.
2. **Put re-orientation in each role doc, rely on the agent to re-read proactively.** Rejected — same problem. The agent that just lost context is the wrong actor to trigger its own re-orientation.
3. **PreCompact hook that prevents compaction.** Rejected — compaction is necessary for long sessions; blocking it trades one problem for another.
4. **External tooling (a script the user runs after `/clear`).** Rejected — relies on user action, breaks on `/compact` which is often automatic.

## Acceptance criteria for the shipping PR

- `.claude/settings.json` registers the hook for all four sources.
- `.claude/hooks/session-reorient.sh` runs under bash on macOS and Linux, with no external dependencies beyond POSIX utilities.
- Manual test recorded in the PR: run `/clear` in a session that adopts the template, verify the injected text appears in the next response's context.
- Manual test recorded in the PR: trigger compaction (fill context near cap), verify `source: "compact"` branch fires.
- `session-policy.md` gains a section documenting the hook and linking to this ADR, so adopters understand it's part of the SOP and not magic.

## Revision v1.1 (2026-08-12) — code-repo staleness NOTICE

Adopter field case (navy_exam_tutor EX-007): CI auto-promotion kept origin
moving while a local checkout sat idle; an audit session reasoned from a tree
87 commits behind origin and produced false conclusions ("uncommitted" work
that had landed weeks earlier). The framework's only fetch step was
`developer.md` lifecycle step 1, which covers the W-item claim path — ad-hoc
diagnosis/audit sessions had no freshness mechanism at all. A stale tree is
invisible precisely when it is misleading, so the session is the wrong actor
to trigger its own fetch — same actor problem this ADR already solved for
re-orientation.

The hook now runs a staleness check for **every** session-start source, over
the flat/tracked-parent repo (`$PROJECT_DIR/.git`) and every immediate
subdirectory with `.git/` (split layout, multi-repo):

- Quiet `git fetch --no-tags origin` per repo, guarded against hangs:
  `GIT_TERMINAL_PROMPT=0` (a credential prompt fails instead of blocking —
  relevant for sessions launched without `.env`, FWADR-032) and
  `http.lowSpeedLimit/lowSpeedTime` (a stalled transfer aborts in ~10s).
- Emits `[session-reorient] Code-repo staleness NOTICE` naming each repo whose
  local `dev`/`main` trails its origin counterpart, with the commit count —
  same pattern as the sync hook's flat-layout NOTICE.
- A failed fetch reports "staleness UNKNOWN" for that repo rather than staying
  silent — silence is indistinguishable from freshness, which is the exact
  failure being fixed. Repos without an `origin` remote are skipped.
- Everything is current → no output. Quiet means healthy. Soft-fail
  throughout; the hook never blocks session start.
