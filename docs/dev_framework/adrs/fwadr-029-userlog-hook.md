# FWADR-029: Userlog hook — every user prompt logged to a per-project userlog.md

**Status:** accepted
**Date:** 2026-08-08
**Deciders:** user (framework author) + Template Developer

## Context

The user wanted a durable, per-project record of everything they tell a chat —
one entry per message, only what the user said (nothing from Claude) — so that
the intent history of a project is legible outside any single session's
transcript. The requested shape:

```
## <chat name>
### <datetime>
<what I said>
```

A rule of the form "every user message is logged" is exactly the kind of
"X always happens on Y" policy the framework refuses to ship as English-only
(see [`template-developer.md`](../template-developer.md) §"Framework-change
doctrine"). It needs a mechanism that fires on every prompt, in every session,
in every adopter — or it is hope, not mechanism.

Claude Code exposes precisely that trigger: the `UserPromptSubmit` hook fires
once per submitted prompt, before Claude processes it, and receives the prompt
text on stdin. That is the enforcement point.

Two facts about the harness shaped the design:

1. **The chat's `/rename` title is not in the hook payload.** The hook receives
   `session_id` (a UUID), `transcript_path`, and `cwd` — but not the
   human-readable name. The name *is* recorded inside the transcript JSONL as
   `{"type":"custom-title","customTitle":"<name>",...}` records (verified
   against a live transcript). Reading it means parsing Claude Code's internal
   transcript format, which Anthropic documents as unsupported and
   version-dependent.
2. **`settings.json` is not synced.** `sync-framework.sh` syncs
   `docs/dev_framework/` and `.claude/hooks/`, but not `.claude/settings.json`
   (adopters own their permissions and hook registrations). So a hook *script*
   propagates automatically; its *registration* does not.

## Decision

Ship a `UserPromptSubmit` hook, `.claude/hooks/log-user-message.sh`, that
appends each user prompt to `$PROJECT_DIR/userlog.md`, grouped by chat name.

- **Chat name** is the last `custom-title` record in `transcript_path`, falling
  back to the short `session_id` when absent (chat never named, or the internal
  format changed). Parsing the internal transcript format is a knowingly
  fragile dependency; the user accepts breakage-on-upgrade and we will match any
  format change. The fallback guarantees the hook keeps logging regardless.
- **Format** matches the request: a `## <chat>` header emitted only when the
  chat changes from the previous entry, then `### <datetime>` and the message
  verbatim.
- **Only genuine user input** is logged. Empty/whitespace prompts and subagent
  prompts (payloads carrying `agent_id`/`agent_type`) are skipped.
- **Silent and soft-fail.** No stdout (nothing enters the model context); the
  script always exits 0 (a logging failure never blocks or disturbs a session).
- **Propagation.** The script rides the existing `.claude/hooks/` sync. The
  registration is *injected* into the adopter's `.claude/settings.json` by a new
  idempotent step in `sync-framework.sh` (§4c) — keyed on the script name, it
  adds the `UserPromptSubmit` entry once and never touches existing permissions
  or hooks. This is what reaches *existing* adopters, not only those who copy
  `.claude/` fresh. Injection requires `jq`; it warns and skips without it.
- **`userlog.md` is gitignored**, because it records raw user input. The
  template ignores it directly; `sync-framework.sh` §4d ensures the line in any
  adopter that already has a `.gitignore`.

## Consequences

- **Coherence surfaces touched, all in this change:** the hook script, the
  template `settings.json` registration, the `sync-framework.sh` injection +
  gitignore steps, the template `.gitignore`, and this ADR.
- **`jq` becomes a soft dependency** for the registration step and for the hook
  itself. Both degrade to a silent/logged no-op without it rather than failing a
  session.
- **Pre-rename messages carry the fallback name.** A chat renamed after its
  first message logs early entries under the short session id; entries after the
  rename use the name. This is inherent to per-message append logging and is
  accepted.
- **Not Layer 0.** The behavior is invisible infrastructure agents never need to
  reason about, so it is deliberately *not* added to CLAUDE.md — keeping the
  always-loaded baseline lean. This ADR is the record of it.
- **Reversal** is a three-line delete: the hook script, the `settings.json`
  block, and the `sync-framework.sh` §4c/§4d steps. Adopters shed the
  registration on their next sync only if a removal step is added; absent that,
  the injected entry is inert once the script is gone (the hook simply no-ops).
