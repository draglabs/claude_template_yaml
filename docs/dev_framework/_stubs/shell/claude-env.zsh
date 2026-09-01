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
# refuse to start without one. The session-start sync hook emits a NOTICE when
# it detects a session that was launched unbound.
#
# Three named variants — the choice is made at every launch by name (FWADR-032):
#   claude-env       [dir]  → source .env, launch claude (normal permission prompts)
#   claude-env-yolo  [dir]  → same, + --dangerously-skip-permissions
#   load-env         [dir]  → source .env into the CURRENT shell, no claude launch
#                             (for running framework scripts by hand, or getting
#                             FWADR-030 git auth in a plain terminal)

_claude_env_source() {
  if [ -n "$1" ]; then
    cd "$1" || {
      echo "claude-env: cannot cd to '$1'" >&2
      return 1
    }
  fi
  if [ ! -f .env ]; then
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
  [ "$mode" = "yolo" ] && flags=(--dangerously-skip-permissions)
  _claude_env_source "$@" || return 1
  claude "${flags[@]}"
}

claude-env()      { _claude_env_launch safe "$@"; }
claude-env-yolo() { _claude_env_launch yolo "$@"; }
load-env()        { _claude_env_source "$@"; }
