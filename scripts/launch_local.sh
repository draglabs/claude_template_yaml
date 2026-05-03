#!/usr/bin/env bash
# Launch a local dev runtime in a named slot.
#
# Slots are defined in docs/dev/slots.yaml (created on first sync; configured
# by scripts/setup_dev_slots.sh). This script claims the slot, then launches
# the project-specific runtime (Docker container, native dev server, etc.).
#
# THIS IS A STUB. The slot-claim + state-file plumbing is filled in; the
# project-specific launch body (the docker run / npm run / etc.) is left
# blank for the agent to fill in once per project. After filling in, this
# script becomes the canonical entry point for "launch dev<N>" — never
# improvise docker commands outside it.
#
# Canonical doctrine: docs/architecture/adr-019-dev-slots-and-deploy-stubs.md

set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "Usage: ./scripts/launch_local.sh <slot>"
  echo "Slots are defined in docs/dev/slots.yaml (e.g. dev0, dev1, dev2, dev3)."
  exit 1
fi

SLOT="$1"
SLOTS_FILE="docs/dev/slots.yaml"
STATE_ROOT=".local/dev_slots"
STATE_FILE="$STATE_ROOT/${SLOT}.yaml"

if [[ ! -f "$SLOTS_FILE" ]]; then
  echo "Missing slot registry: $SLOTS_FILE"
  echo "Run scripts/setup_dev_slots.sh first."
  exit 1
fi

PORT="$(ruby -e '
  require "yaml"
  data = YAML.load_file(ARGV[0])
  slot = data.fetch("slots").fetch(ARGV[1], nil)
  abort("") unless slot
  puts slot.fetch("port")
' "$SLOTS_FILE" "$SLOT" 2>/dev/null || true)"

ROLE="$(ruby -e '
  require "yaml"
  data = YAML.load_file(ARGV[0])
  slot = data.fetch("slots").fetch(ARGV[1], nil)
  abort("") unless slot
  puts slot.fetch("role")
' "$SLOTS_FILE" "$SLOT" 2>/dev/null || true)"

HOSTNAME_VAL="$(ruby -e '
  require "yaml"
  data = YAML.load_file(ARGV[0])
  slot = data.fetch("slots").fetch(ARGV[1], nil)
  abort("") unless slot
  puts slot.fetch("hostname")
' "$SLOTS_FILE" "$SLOT" 2>/dev/null || true)"

if [[ -z "${PORT:-}" || -z "${ROLE:-}" || -z "${HOSTNAME_VAL:-}" ]]; then
  echo "Unknown slot: $SLOT (or registry malformed)"
  exit 1
fi

# Stub-config detection. If setup hasn't run, ports/hostnames are placeholders.
if [[ "$PORT" == "0" || "$HOSTNAME_VAL" == "PLACEHOLDER" ]]; then
  echo "Slot $SLOT not configured. Run: ./scripts/setup_dev_slots.sh"
  exit 1
fi

mkdir -p "$STATE_ROOT"

if [[ -f "$STATE_FILE" ]]; then
  echo "Slot already claimed: $SLOT"
  echo "State file: $STATE_FILE"
  echo "Run scripts/teardown_local.sh $SLOT to release, or use a different slot."
  exit 1
fi

cat > "$STATE_FILE" <<EOF
slot: $SLOT
role: $ROLE
hostname: $HOSTNAME_VAL
port: $PORT
claimed_at: $(date -u +"%Y-%m-%dT%H:%M:%SZ")
ticket: TBD
status: claimed
EOF

echo "Claimed slot $SLOT"
echo "Role: $ROLE"
echo "Hostname: $HOSTNAME_VAL"
echo "Port: $PORT"
echo "State file: $STATE_FILE"

# ---------------------------------------------------------------------------
# PROJECT-SPECIFIC LAUNCH BODY
#
# Fill this in once for the project. Examples:
#
#   docker run -d --name "${SLOT}-myapp" -p "${PORT}:3000" -e NODE_ENV=development myapp:dev
#
#   docker compose -f docker-compose.dev.yml up -d --build
#   (then update docker-compose.dev.yml to bind to ${PORT})
#
#   npm run dev -- --port "${PORT}" &
#   echo $! > "$STATE_ROOT/${SLOT}.pid"
#
# After the runtime is up, verify Caddy routes ${HOSTNAME_VAL} to localhost:${PORT}.
# ---------------------------------------------------------------------------
echo "Project-specific launch body is not implemented yet."
echo "Fill in this script (PROJECT-SPECIFIC LAUNCH BODY section) so slot $SLOT"
echo "launches repeatably on port $PORT, then commit the change."
rm -f "$STATE_FILE"
echo "Released temporary slot claim because launch flow is still a placeholder."
exit 1
