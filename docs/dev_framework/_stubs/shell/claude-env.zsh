# claude-env.zsh — canonical Claude Code launchers (FWADR-032).
#
# Install into your shell rc (once per machine, confirmed at the Strategist's
# first-contact interview, Block 0):
#
#   source /path/to/docs/dev_framework/_stubs/shell/claude-env.zsh
#
# or paste the functions into ~/.zshrc directly.
#
# WHY THIS EXISTS: Claude Code expands MCP env vars from its OWN process env,
# not from .env — and the FWADR-030 git-auth auto-wire block at the bottom of
# .env only executes when .env is sourced. Launching bare `claude` inside a
# project therefore silently unbinds API keys, MCP credentials, and git auth.
# These launchers make sourcing .env an inseparable part of the launch, and
# refuse to start without one. On a fresh adopter (no .env, but a synced
# .env.example) they seed .env from the starter and stop, so the first-contact
# interview begins from a complete file rather than a hand-written stub. The
# session-start sync hook emits a NOTICE when it detects a session that was
# launched unbound.
#
# Four named variants — the choice is made at every launch by name (FWADR-032):
#   claude-env             [dir] → source .env, launch claude (normal permission prompts)
#   claude-env-yolo        [dir] → same, + --dangerously-skip-permissions
#   claude-env-extra-yolo  [dir] → same as yolo, + CLAUDE_CODE_EVEN_MORE_DANGEROUSLY_SKIP_PERMISSIONS=1
#                                  in claude's process env only (never exported to your shell)
#   load-env               [dir] → source .env into the CURRENT shell, no claude launch
#                                  (for running framework scripts by hand, or getting
#                                  FWADR-030 git auth in a plain terminal)

_claude_env_source() {
  if [ -n "$1" ]; then
    cd "$1" || {
      echo "claude-env: cannot cd to '$1'" >&2
      return 1
    }
  fi
  if [ ! -f .env ]; then
    if [ -f .env.example ]; then
      # First launch in a fresh adopter: seed .env from the framework starter so
      # the Strategist's first-contact interview finds every variable present
      # and only has to ask about the PLACEHOLDER lines. Never overwrites an
      # existing .env; still refuses to launch until the file has been filled.
      cp .env.example .env
      echo "claude-env: no .env in $PWD — seeded one from .env.example." >&2
      echo "            Fill the PLACEHOLDER lines in the MINIMUM TO BOOT block, then relaunch." >&2
      return 1
    fi
    echo "❌ claude-env: no .env in $PWD — refusing without project env." >&2
    return 1
  fi
  set -a
  source .env
  set +a
}

_claude_env_launch() {
  local mode="$1"; shift
  local -a flags
  case "$mode" in
    yolo|extra-yolo) flags=(--dangerously-skip-permissions) ;;
  esac
  _claude_env_source "$@" || return 1
  if [ "$mode" = "extra-yolo" ]; then
    # Prefix assignment: the override reaches claude's process env only, so a
    # later plain `claude` from this same shell stays unaffected.
    CLAUDE_CODE_EVEN_MORE_DANGEROUSLY_SKIP_PERMISSIONS=1 claude "${flags[@]}"
  else
    claude "${flags[@]}"
  fi
}

claude-env()            { _claude_env_launch safe "$@"; }
claude-env-yolo()       { _claude_env_launch yolo "$@"; }
claude-env-extra-yolo() { _claude_env_launch extra-yolo "$@"; }
load-env()              { _claude_env_source "$@"; }
