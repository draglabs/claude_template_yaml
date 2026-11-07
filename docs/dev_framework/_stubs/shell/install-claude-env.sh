#!/usr/bin/env bash
# install-claude-env.sh — wire the claude-env launchers into a shell rc (FWADR-032).
#
# Installs by appending ONE line to your rc:  source <abs-path>/claude-env.zsh
# The snippet defines claude-env / claude-env-yolo / claude-env-extra-yolo /
# load-env; despite the
# .zsh name its functions are bash-compatible, so the same file serves both
# shells. Idempotent: if the rc already loads the framework launchers, does
# nothing. A hand-written claude-env of your own does not count as installed —
# the line is appended anyway and the shadowed definition is reported.
#
# Usage:
#   ./install-claude-env.sh              # auto-pick rc from $SHELL
#   ./install-claude-env.sh --rc FILE    # explicit rc (e.g. ~/.bashrc)
#   ./install-claude-env.sh --check      # report only, edit nothing:
#                                        # exit 0 = installed, 1 = not
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
CHECK=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --rc)    RC="${2:?--rc needs a file path}"; shift 2 ;;
    --check) CHECK=1; shift ;;
    *)
      echo "usage: install-claude-env.sh [--check] [--rc FILE]" >&2
      exit 2 ;;
  esac
done
if [[ -z "$RC" ]]; then
  case "$(basename "${SHELL:-}")" in
    zsh)  RC="$HOME/.zshrc" ;;
    bash) RC="$HOME/.bashrc" ;;
    *)
      echo "[install-claude-env] Cannot auto-pick an rc for shell '${SHELL:-unset}'." >&2
      echo "[install-claude-env] Re-run with: --rc <your rc file>" >&2
      exit 2 ;;
  esac
fi

# Installed = a non-comment line sources the snippet, or carries its functions
# pasted verbatim (every paste includes the _claude_env_source helper). The
# bare string "claude-env" proves nothing: a hand-written launcher of the same
# name matches it too, and has none of the other variants.
FRAMEWORK_RE='^[[:space:]]*([^#[:space:]].*)?(claude-env\.zsh|_claude_env_source)'
OWN_RE='^[[:space:]]*((function[[:space:]]+)?claude-env[[:space:]]*\(\)|function[[:space:]]+claude-env([[:space:]]|$)|alias[[:space:]]+claude-env=)'

INSTALLED=0
OWN_LINE=""
if [[ -f "$RC" ]]; then
  if grep -Eq "$FRAMEWORK_RE" "$RC"; then
    INSTALLED=1
  else
    OWN_LINE="$(grep -nE "$OWN_RE" "$RC" | head -1 | cut -d: -f1 || true)"
  fi
fi

if [[ "$CHECK" -eq 1 ]]; then
  if [[ "$INSTALLED" -eq 1 ]]; then
    echo "[install-claude-env] $RC loads the framework launchers — installed."
    exit 0
  fi
  if [[ -n "$OWN_LINE" ]]; then
    echo "[install-claude-env] $RC:$OWN_LINE defines its own claude-env, not the framework launchers — NOT installed."
  else
    echo "[install-claude-env] $RC does not load the framework launchers — NOT installed."
  fi
  exit 1
fi

if [[ "$INSTALLED" -eq 1 ]]; then
  echo "[install-claude-env] $RC already loads the framework launchers — nothing to do."
  exit 0
fi

{
  printf '\n# claude-env / claude-env-yolo / claude-env-extra-yolo / load-env launchers (FWADR-032)\n'
  printf 'source %q\n' "$SNIPPET"
} >> "$RC"
echo "[install-claude-env] Added to $RC:"
echo "    source $SNIPPET"

if [[ -n "$OWN_LINE" ]]; then
  echo "[install-claude-env] NOTICE: $RC:$OWN_LINE defines its own claude-env. The line added above"
  echo "[install-claude-env] comes later in the rc, so the framework's definition now wins: plain"
  echo "[install-claude-env] claude-env prompts for permissions, claude-env-yolo is the bypass variant."
  echo "[install-claude-env] Delete the old definition by hand — this script never removes your code."
fi

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
