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
# Customized per project ONLY via .env (WORKER_TERMINAL) — the project (planning)
# dir is located by walking up to the nearest .env, so there is no per-repo body
# to fill. macOS only.
#
# First run: macOS shows a one-time Automation prompt to let your terminal control
# the target app — grant it, then spawns are instant. Run this from an interactive
# terminal (a headless context can't answer that prompt; the AppleEvent times out).
#
# Dry run: WORKER_DRYRUN=1 spawn_worker.sh <name> [prompt]  — prints the plan,
# opens nothing. Works on any platform (useful for testing).

set -euo pipefail

# --- locate the project (planning) directory ----------------------------------
# The worker must launch where the project's .env and planning git repo live —
# the parent tracking dir under split layout (FWADR-021), NOT the scripts/ folder.
# Anchor on the .env: walk up from this script to the nearest ancestor that holds
# a .env, and use that. This lands in the planning dir wherever the script sits
# (canonically $PROJECT_DIR/scripts/, but also e.g. the template's _stubs/). Falls
# back to the parent of scripts/ only if no .env is found upward.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd -P)"
PROJECT_DIR=""
_d="$SCRIPT_DIR"
while [ "$_d" != "/" ]; do
  if [ -f "$_d/.env" ]; then PROJECT_DIR="$_d"; break; fi
  _d="$(dirname "$_d")"
done
[ -z "$PROJECT_DIR" ] && PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd -P)"

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
# The osascript is wrapped in `with timeout` so a first run that hits the macOS
# Automation-permission (TCC) prompt fails fast with guidance instead of hanging
# the full 120s default AppleEvent timeout. On failure the launcher is kept so
# the printed manual fallback works.
open_rc=0
case "$WORKER_TERMINAL" in
  iterm|iTerm|iterm2|iTerm2)
    osascript <<OSA || open_rc=$?
with timeout of 30 seconds
  tell application "iTerm"
    create window with default profile
    tell current session of current window to write text "zsh '$LAUNCHER'"
    activate
  end tell
end timeout
OSA
    ;;
  terminal|Terminal|terminal.app|Terminal.app)
    osascript <<OSA || open_rc=$?
with timeout of 30 seconds
  tell application "Terminal"
    do script "zsh '$LAUNCHER'"
    activate
  end tell
end timeout
OSA
    ;;
  *)
    echo "spawn_worker.sh: unknown WORKER_TERMINAL='$WORKER_TERMINAL' (use 'iterm' or 'terminal')" >&2
    rm -f "$LAUNCHER"
    exit 2
    ;;
esac

if [[ "$open_rc" -ne 0 ]]; then
  echo "spawn_worker.sh: could not drive $WORKER_TERMINAL via osascript (rc=$open_rc)." >&2
  echo "  First run? Grant Automation permission and retry: System Settings → Privacy &" >&2
  echo "  Security → Automation → allow your terminal to control $WORKER_TERMINAL." >&2
  echo "  (An AppleEvent timeout / -1712 is almost always this; it also fails from a" >&2
  echo "  non-interactive context that can't answer the prompt.)" >&2
  echo "  Manual fallback — open a terminal and run:  zsh '$LAUNCHER'" >&2
  exit 1
fi

echo "spawned worker '$NAME' in $WORKER_TERMINAL at $PROJECT_DIR (Remote Control enabled)"
