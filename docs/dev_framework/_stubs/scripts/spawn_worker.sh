#!/usr/bin/env bash
# spawn_worker.sh — launch a named, Remote-Control-enabled Claude worker in a
# new macOS terminal window at the project root (FWADR-031).
#
#   spawn_worker.sh <name> ["initial prompt"]
#
# Opens a terminal (WORKER_TERMINAL: iterm | terminal, default iterm) that does:
#   cd <project> → set -a; source .env; set +a → exec claude \
#       --dangerously-skip-permissions --name "<name>" --remote-control [prompt]
#
# That fuses the old "claude-env + /rename + /remote-control" steps into one
# launch: --name sets the display name, --remote-control enables Remote Control
# so the worker joins your phone's session list. Sourcing .env also runs the
# FWADR-030 git-auth wiring, so the worker's git is authenticated too.
#
# Customized per project ONLY via .env (WORKER_TERMINAL) — the project path is
# self-located, so there is no per-repo body to fill. macOS only.
#
# Dry run: WORKER_DRYRUN=1 spawn_worker.sh <name> [prompt]  — prints the plan,
# opens nothing. Works on any platform (useful for testing).

set -euo pipefail

# --- locate the project root (this script lives at $PROJECT_DIR/scripts/) ------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd -P)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd -P)"

# --- args ---------------------------------------------------------------------
NAME="${1:-}"
PROMPT="${2:-}"
if [[ -z "$NAME" ]]; then
  echo "usage: spawn_worker.sh <name> [\"initial prompt\"]" >&2
  exit 2
fi

DRYRUN="${WORKER_DRYRUN:-}"

# --- platform guard (skipped in dry run so the plan is inspectable anywhere) ---
if [[ -z "$DRYRUN" && "$(uname)" != "Darwin" ]]; then
  echo "spawn_worker.sh: macOS only (uses osascript). Elsewhere, run by hand:" >&2
  echo "  cd \"$PROJECT_DIR\" && set -a; source .env; set +a; claude --dangerously-skip-permissions --name \"$NAME\" --remote-control" >&2
  exit 1
fi

# --- terminal choice (project-customizable via .env, default iterm) -----------
WORKER_TERMINAL="${WORKER_TERMINAL:-}"
if [[ -z "$WORKER_TERMINAL" && -f "$PROJECT_DIR/.env" ]]; then
  WORKER_TERMINAL="$(grep -E '^WORKER_TERMINAL=' "$PROJECT_DIR/.env" 2>/dev/null \
                     | head -1 | cut -d= -f2- | sed 's/^["'"'"']//; s/["'"'"']$//' || true)"
fi
WORKER_TERMINAL="${WORKER_TERMINAL:-iterm}"

# --- build a temp launcher (sidesteps AppleScript quote-escaping) -------------
# The launcher deletes itself (its lines are already read) then execs claude, so
# the terminal tab BECOMES the worker.
LAUNCHER="$(mktemp "${TMPDIR:-/tmp}/claude-worker.XXXXXX")"
{
  echo '#!/bin/zsh'
  printf 'cd %q || exit 1\n' "$PROJECT_DIR"
  echo 'set -a; source .env 2>/dev/null; set +a'
  if [[ -n "$PROMPT" ]]; then
    printf 'rm -f %q; exec claude --dangerously-skip-permissions --name %q --remote-control %q\n' \
           "$LAUNCHER" "$NAME" "$PROMPT"
  else
    printf 'rm -f %q; exec claude --dangerously-skip-permissions --name %q --remote-control\n' \
           "$LAUNCHER" "$NAME"
  fi
} > "$LAUNCHER"
chmod +x "$LAUNCHER"

# --- dry run: show the plan, open nothing -------------------------------------
if [[ -n "$DRYRUN" ]]; then
  echo "[dry-run] project     : $PROJECT_DIR"
  echo "[dry-run] terminal     : $WORKER_TERMINAL"
  echo "[dry-run] worker name  : $NAME"
  echo "[dry-run] initial prompt: ${PROMPT:-<none>}"
  echo "[dry-run] launcher ($LAUNCHER):"
  sed 's/^/    /' "$LAUNCHER"
  rm -f "$LAUNCHER"
  exit 0
fi

# --- open the terminal --------------------------------------------------------
case "$WORKER_TERMINAL" in
  iterm|iTerm|iterm2|iTerm2)
    osascript <<OSA
tell application "iTerm"
  create window with default profile
  tell current session of current window to write text "zsh '$LAUNCHER'"
  activate
end tell
OSA
    ;;
  terminal|Terminal|terminal.app|Terminal.app)
    osascript -e "tell application \"Terminal\" to do script \"zsh '$LAUNCHER'\""
    osascript -e 'tell application "Terminal" to activate'
    ;;
  *)
    echo "spawn_worker.sh: unknown WORKER_TERMINAL='$WORKER_TERMINAL' (use 'iterm' or 'terminal')" >&2
    rm -f "$LAUNCHER"
    exit 2
    ;;
esac

echo "spawned worker '$NAME' in $WORKER_TERMINAL at $PROJECT_DIR (Remote Control enabled)"
