#!/usr/bin/env bash
# install-claude-env.sh — wire the claude-env launchers into a shell rc (FWADR-032).
#
# Installs by appending ONE line to your rc:  source <abs-path>/claude-env.zsh
# The snippet defines claude-env / claude-env-yolo / claude-env-extra-yolo /
# load-env; despite the
# .zsh name its functions are bash-compatible, so the same file serves both
# shells. Idempotent: if the rc already mentions claude-env, does nothing.
#
# Usage:
#   ./install-claude-env.sh              # auto-pick rc from $SHELL
#   ./install-claude-env.sh --rc FILE    # explicit rc (e.g. ~/.bashrc)
#
# Running this script IS the explicit approval FWADR-032 requires — it still
# never edits an rc without being invoked, and prints exactly what it did.

set -euo pipefail

SNIPPET="$(cd "$(dirname "$0")" && pwd -P)/claude-env.zsh"
if [[ ! -f "$SNIPPET" ]]; then
  echo "[install-claude-env] ERROR: snippet not found at $SNIPPET" >&2
  exit 1
fi

RC=""
if [[ "${1:-}" == "--rc" ]]; then
  RC="${2:?--rc needs a file path}"
elif [[ $# -gt 0 ]]; then
  echo "usage: install-claude-env.sh [--rc FILE]" >&2
  exit 2
else
  case "$(basename "${SHELL:-}")" in
    zsh)  RC="$HOME/.zshrc" ;;
    bash) RC="$HOME/.bashrc" ;;
    *)
      echo "[install-claude-env] Cannot auto-pick an rc for shell '${SHELL:-unset}'." >&2
      echo "[install-claude-env] Re-run with: --rc <your rc file>" >&2
      exit 2 ;;
  esac
fi

if [[ -f "$RC" ]] && grep -q 'claude-env' "$RC"; then
  echo "[install-claude-env] $RC already references claude-env — nothing to do."
  exit 0
fi

{
  printf '\n# claude-env / claude-env-yolo / claude-env-extra-yolo / load-env launchers (FWADR-032)\n'
  printf 'source %q\n' "$SNIPPET"
} >> "$RC"
echo "[install-claude-env] Added to $RC:"
echo "    source $SNIPPET"

# macOS quirk: Terminal starts bash as a LOGIN shell, which reads
# ~/.bash_profile and skips ~/.bashrc unless the profile chains to it.
if [[ "$RC" == "$HOME/.bashrc" && "$(uname)" == "Darwin" ]]; then
  PROFILE="$HOME/.bash_profile"
  if [[ ! -f "$PROFILE" ]] || ! grep -q '\.bashrc' "$PROFILE"; then
    echo "[install-claude-env] NOTE (macOS): login shells read ~/.bash_profile, not ~/.bashrc."
    echo "[install-claude-env] Add this to $PROFILE so the launchers load in Terminal:"
    echo '    [ -f ~/.bashrc ] && source ~/.bashrc'
  fi
fi

echo "[install-claude-env] Open a new shell (or: source $RC) to pick up the functions."
