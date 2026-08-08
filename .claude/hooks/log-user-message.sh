#!/usr/bin/env bash
# log-user-message.sh — UserPromptSubmit hook.
#
# Appends every prompt the user submits to $PROJECT_DIR/userlog.md, grouped by
# chat name. Logs ONLY what the user types — nothing from Claude. The record
# shape is:
#
#   ## <chat name>
#
#   ### <YYYY-MM-DD HH:MM:SS TZ>
#   <the message verbatim>
#
# The "## <chat name>" header is emitted only when the chat changes from the
# previous entry, so consecutive messages from one chat stay grouped.
#
# Two hard invariants, because this runs on EVERY prompt in EVERY session:
#   * SILENT   — no stdout, so nothing is injected into the model's context.
#   * SOFT-FAIL — always exit 0; a logging failure must never block or disturb
#                 a session.
#
# The script rides .claude/hooks/ sync; its settings.json registration is
# injected by sync-framework.sh (settings.json is not itself synced). See
# docs/dev_framework/adrs/fwadr-029-userlog-hook.md.

# Wrap everything so no error escapes; the final `exit 0` is the only exit.
{
  payload="$(cat)"

  # jq is required to parse the payload / transcript; no-op silently without it.
  command -v jq >/dev/null 2>&1 || exit 0

  # The submitted prompt text. The field name has varied across Claude Code
  # versions (.prompt / .user_message); accept whichever is present.
  prompt="$(printf '%s' "$payload" | jq -r '.prompt // .user_message // empty' 2>/dev/null)"

  # Skip empty / whitespace-only prompts.
  [[ -z "${prompt//[[:space:]]/}" ]] && exit 0

  # Skip subagent prompts — those are Claude talking to a subagent, not the
  # user. Subagent payloads carry a non-empty agent_id / agent_type.
  agent="$(printf '%s' "$payload" | jq -r '.agent_id // .agent_type // empty' 2>/dev/null)"
  [[ -n "$agent" ]] && exit 0

  transcript="$(printf '%s' "$payload" | jq -r '.transcript_path // empty' 2>/dev/null)"
  session="$(printf '%s' "$payload" | jq -r '.session_id // empty' 2>/dev/null)"
  cwd="$(printf '%s' "$payload" | jq -r '.cwd // empty' 2>/dev/null)"

  # Chat name = the last "custom-title" record in the transcript (the live
  # /rename name). This reads Claude Code's internal transcript format, which
  # is unsupported and may change between releases — accepted per FWADR-029.
  # The short-session-id fallback keeps the hook working if the format shifts
  # or the chat was never named.
  chat=""
  if [[ -n "$transcript" && -f "$transcript" ]]; then
    chat="$(jq -r 'select(.type=="custom-title") | .customTitle' "$transcript" 2>/dev/null | tail -1)"
  fi
  [[ -z "$chat" ]] && chat="${session:0:8}"
  [[ -z "$chat" ]] && chat="unknown-chat"

  # Destination: $PROJECT_DIR/userlog.md (the parent tracking dir under split
  # layout). Fall back to the payload cwd, then $PWD.
  base="${CLAUDE_PROJECT_DIR:-${cwd:-$PWD}}"
  log="$base/userlog.md"

  ts="$(date '+%Y-%m-%d %H:%M:%S %Z')"

  # Serialize concurrent writers (parallel chats can share one file). Best-
  # effort mkdir lock; proceed anyway if it can't be acquired within ~1s.
  lock="$log.lock"
  for _ in 1 2 3 4 5 6 7 8 9 10; do
    mkdir "$lock" 2>/dev/null && break
    sleep 0.1
  done

  {
    # Header only when the chat differs from the last one recorded.
    last_hdr=""
    [[ -f "$log" ]] && last_hdr="$(grep '^## ' "$log" 2>/dev/null | tail -1)"
    if [[ "$last_hdr" != "## $chat" ]]; then
      printf '\n## %s\n' "$chat" >> "$log"
    fi
    printf '\n### %s\n%s\n' "$ts" "$prompt" >> "$log"
  } 2>/dev/null

  rmdir "$lock" 2>/dev/null
} 2>/dev/null

exit 0
