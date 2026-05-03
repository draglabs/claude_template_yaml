#!/usr/bin/env bash
# Tear down a local dev runtime by slot name.
#
# Reads the slot's state file (.local/dev_slots/<slot>.yaml), stops the
# project-specific runtime, then deletes the state file.
#
# THIS IS A STUB. The slot-state lookup is filled in; the project-specific
# teardown body (docker stop / process kill / etc.) is left blank for the
# agent to fill in once per project — paired with the launch body in
# scripts/launch_local.sh.
#
# Canonical doctrine: docs/architecture/adr-019-dev-slots-and-deploy-stubs.md

set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "Usage: ./scripts/teardown_local.sh <slot>"
  exit 1
fi

SLOT="$1"
STATE_ROOT=".local/dev_slots"
STATE_FILE="$STATE_ROOT/${SLOT}.yaml"

if [[ ! -f "$STATE_FILE" ]]; then
  echo "No claimed slot state found for: $SLOT"
  echo "Expected state file: $STATE_FILE"
  echo "(If the slot is running but the state file is missing, the launch was"
  echo " not completed cleanly — investigate before forcing teardown.)"
  exit 1
fi

PORT="$(ruby -e '
  require "yaml"
  data = YAML.load_file(ARGV[0])
  puts data.fetch("port")
' "$STATE_FILE" 2>/dev/null || true)"

HOSTNAME_VAL="$(ruby -e '
  require "yaml"
  data = YAML.load_file(ARGV[0])
  puts data.fetch("hostname")
' "$STATE_FILE" 2>/dev/null || true)"

echo "Preparing teardown for slot $SLOT"
echo "Hostname: ${HOSTNAME_VAL:-unknown}"
echo "Port: ${PORT:-unknown}"

# ---------------------------------------------------------------------------
# PROJECT-SPECIFIC TEARDOWN BODY
#
# Fill this in to mirror the launch body. Examples:
#
#   docker stop "${SLOT}-myapp" 2>/dev/null && docker rm "${SLOT}-myapp" 2>/dev/null
#
#   docker compose -f docker-compose.dev.yml down
#
#   if [[ -f "$STATE_ROOT/${SLOT}.pid" ]]; then
#     kill "$(cat "$STATE_ROOT/${SLOT}.pid")" 2>/dev/null || true
#     rm -f "$STATE_ROOT/${SLOT}.pid"
#   fi
#
# After the runtime is down and the state file is no longer needed, the
# script removes the state file and exits 0.
# ---------------------------------------------------------------------------
echo "Project-specific teardown body is not implemented yet."
echo "Fill in this script (PROJECT-SPECIFIC TEARDOWN BODY section), then"
echo "delete \"$STATE_FILE\" inside the script after the runtime is down,"
echo "then commit the change."
exit 1
