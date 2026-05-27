#!/usr/bin/env bash
# Tear down a local dev runtime by slot name.
#
# Reads the slot's state file (.local/dev_slots/<slot>.yaml), prints a
# confirmation block showing what's about to be torn down, then hands off
# to the project-specific teardown body (docker compose down / process
# kill / etc.). Once the body returns, removes the state file.
#
# THIS IS A STUB. The slot-state read + confirmation plumbing is filled in;
# the project-specific teardown body is left blank for the agent to fill in
# once per project — paired with the launch body in scripts/launch_local.sh.
#
# Usage:
#   ./scripts/teardown_local.sh <slot> [--auto-confirm]
#
# Slot:           positional, required.
# --auto-confirm: skip the "Proceed? [Y/n]" prompt.
#
# Canonical doctrine: docs/architecture/adr-019-dev-slots-and-deploy-stubs.md

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------
SLOT=""
AUTO_CONFIRM="false"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --auto-confirm) AUTO_CONFIRM="true" ;;
    --help|-h)
      awk '/^#/{print; next} {exit}' "${BASH_SOURCE[0]}" | sed 's/^# \?//'
      exit 0
      ;;
    -*)
      echo "Unknown flag: $1" >&2
      echo "Usage: ./scripts/teardown_local.sh <slot> [--auto-confirm]" >&2
      exit 1
      ;;
    *)
      if [[ -z "$SLOT" ]]; then
        SLOT="$1"
      else
        echo "Unexpected positional arg: $1" >&2
        exit 1
      fi
      ;;
  esac
  shift
done

if [[ -z "$SLOT" ]]; then
  echo "Usage: ./scripts/teardown_local.sh <slot> [--auto-confirm]" >&2
  exit 1
fi

STATE_ROOT="$PROJECT_DIR/.local/dev_slots"
STATE_FILE="$STATE_ROOT/${SLOT}.yaml"

if [[ ! -f "$STATE_FILE" ]]; then
  echo "No claimed slot state found for: $SLOT" >&2
  echo "Expected state file: $STATE_FILE" >&2
  echo "(If the slot is running but the state file is missing, the launch was" >&2
  echo " not completed cleanly — investigate before forcing teardown.)" >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# Read state file (generic fields)
# ---------------------------------------------------------------------------
# The launch script writes a generic schema (slot, role, hostname, port,
# claimed_at, ticket, status, code_path, mode, branch, sha). The
# PROJECT-SPECIFIC LAUNCH BODY may append additional fields (compose_project,
# compose_file, etc.) — those are read inside the PROJECT-SPECIFIC TEARDOWN
# BODY below, not here.
read_state() {
  ruby -e '
    require "yaml"
    data = YAML.load_file(ARGV[0])
    puts data.fetch(ARGV[1], "")
  ' "$STATE_FILE" "$1" 2>/dev/null || true
}

PORT="$(read_state port)"
HOSTNAME_VAL="$(read_state hostname)"
CODE_PATH_STATE="$(read_state code_path)"
MODE_STATE="$(read_state mode)"
BRANCH_STATE="$(read_state branch)"
SHA_STATE="$(read_state sha)"

# ---------------------------------------------------------------------------
# Pre-teardown confirmation block (mirror of launch)
# ---------------------------------------------------------------------------
cat <<EOF

Tearing down $SLOT
  source:    ${CODE_PATH_STATE:-unknown}
             (${MODE_STATE:-unknown} mode — branch ${BRANCH_STATE:-unknown} @ ${SHA_STATE:-unknown})
  port:      ${PORT:-unknown}
  hostname:  ${HOSTNAME_VAL:-unknown}

EOF

if [[ "$AUTO_CONFIRM" != "true" ]]; then
  read -r -p "Proceed? [Y/n] " REPLY
  if [[ "$REPLY" =~ ^[Nn] ]]; then
    echo "Aborted."
    exit 0
  fi
fi

# ---------------------------------------------------------------------------
# PROJECT-SPECIFIC TEARDOWN BODY
#
# Fill this in to mirror the launch body. Read project-specific state fields
# the launch body appended (compose_project, compose_file, etc.) via
# read_state, then run the inverse of the launch (docker compose down,
# process kill, etc.).
#
# Backwards compat: if the launch body started appending new fields after an
# adopter already had slots in flight, read_state will return "" for those
# fields on pre-upgrade state files. Either bail out with a clear message or
# fall back to a sane default — your call.
#
# Examples:
#
#   COMPOSE_PROJECT="$(read_state compose_project)"
#   COMPOSE_FILE="$(read_state compose_file)"
#   COMPOSE_OVERRIDE="$(read_state compose_override)"
#   if [[ -z "$COMPOSE_PROJECT" ]]; then
#     echo "ERROR: state file missing compose_project — pre-upgrade slot?" >&2
#     exit 1
#   fi
#   COMPOSE_ARGS=(-p "$COMPOSE_PROJECT" -f "$COMPOSE_FILE")
#   [[ -n "$COMPOSE_OVERRIDE" && -f "$COMPOSE_OVERRIDE" ]] && COMPOSE_ARGS+=(-f "$COMPOSE_OVERRIDE")
#   docker compose "${COMPOSE_ARGS[@]}" down
#   [[ -n "$COMPOSE_OVERRIDE" && -f "$COMPOSE_OVERRIDE" ]] && rm -f "$COMPOSE_OVERRIDE"
#
#   docker stop "${SLOT}-myapp" 2>/dev/null && docker rm "${SLOT}-myapp" 2>/dev/null
#
#   if [[ -f "$STATE_ROOT/${SLOT}.pid" ]]; then
#     kill "$(cat "$STATE_ROOT/${SLOT}.pid")" 2>/dev/null || true
#     rm -f "$STATE_ROOT/${SLOT}.pid"
#   fi
#
# Once the body returns successfully, the generic post-body below removes
# the state file. Do NOT remove the state file from inside the body — leave
# that to the generic post-body so the post-body's removal sequence is the
# single source of truth.
#
# To fill in: replace the placeholder block below (from the `echo
# "Project-specific..."` line through `exit 1`) with your teardown commands.
# ---------------------------------------------------------------------------
echo "Project-specific teardown body is not implemented yet."
echo "Fill in this script (PROJECT-SPECIFIC TEARDOWN BODY section), then"
echo "commit the change. The generic post-body will then remove the state"
echo "file once teardown succeeds."
exit 1

# ---------------------------------------------------------------------------
# Generic post-body — state file removal
# (only reached once the PROJECT-SPECIFIC TEARDOWN BODY above is filled in
# and runs to completion without the placeholder `exit 1`).
# ---------------------------------------------------------------------------
rm -f "$STATE_FILE"
echo ""
echo "Slot ${SLOT} down. State file removed."
exit 0
