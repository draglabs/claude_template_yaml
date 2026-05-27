#!/usr/bin/env bash
# Launch a local dev runtime in a named slot.
#
# Slots are defined in docs/dev/slots.yaml (created on first sync; configured
# by scripts/setup_dev_slots.sh). This script claims the slot, resolves the
# code source (worktree or main checkout) for the slot, prints a pre-launch
# confirmation block, then hands off to the project-specific launch body.
#
# THIS IS A STUB. The slot-claim + source-resolution + confirmation plumbing
# is filled in; the project-specific launch body (docker run / docker compose
# up / npm run dev / etc.) is left blank for the agent to fill in once per
# project. After filling in, this script becomes the canonical entry point
# for "launch dev<N>" — never improvise docker commands outside it.
#
# Usage:
#   ./scripts/launch_local.sh <slot> [--wid=W-NN] [--auto-confirm]
#                                    [--code-path=PATH]
#
# Slot:           positional, required.  dev0..dev3 per docs/dev/slots.yaml.
# --wid=W-NN:     resolve CODE_PATH from worktree by W-id (parent-CWD use).
# --auto-confirm: skip the "Proceed? [Y/n]" prompt (CI / scripted use).
# --code-path=P:  explicit CODE_PATH override; takes precedence over all
#                 auto-detect.  Last-resort escape hatch.
#
# Auto-detect order for CODE_PATH (if --code-path not given):
#   1. CODE_PATH env var (backwards-compat with pre-safety-primitive callers).
#   2. --wid=W-NN → /tmp/worktrees/${DEFAULT_CODE_SUBDIR}/<lowercased>-<slug>.
#   3. git rev-parse --show-toplevel from $PWD (worktree or main checkout
#      that contains the current directory).
#   4. $PROJECT_DIR/$DEFAULT_CODE_SUBDIR (the canonical main-checkout fallback).
#
# Environment exposed to the PROJECT-SPECIFIC LAUNCH BODY (read these below):
#   $SLOT                slot name (e.g. dev1)
#   $ROLE                role (default_developer | parallel_developer)
#   $HOSTNAME_VAL        Caddy-fronted hostname (e.g. dev1.myapp.localhost)
#   $PORT                HTTP/Caddy-routed port — bind the app server here so
#                        Caddy reverse-proxies $HOSTNAME_VAL → localhost:$PORT.
#                        Canonical user-facing surface for QA (ADR-019 v1.1).
#   $CODE_PATH_RESOLVED  absolute path to the source directory the user just
#                        confirmed — point docker/dev-server at this, NOT at
#                        $PWD or $PROJECT_DIR/$DEFAULT_CODE_SUBDIR (worktree
#                        launches must use the worktree path).
#   $MODE                "worktree" or "main"
#   $STATE_FILE          path to this slot's state file (project body MAY
#                        append project-specific fields like compose_project)
#
# If your project needs SECONDARY ports per slot (database, cache, queue,
# etc.), declare them under each slot's optional `extras:` map in
# docs/dev/slots.yaml and read them in the project body with a Ruby one-liner.
# Example:
#
#   DB_PORT="$(ruby -e '
#     require "yaml"
#     data = YAML.load_file(ARGV[0])
#     extras = data.fetch("slots").fetch(ARGV[1]).fetch("extras", {})
#     puts extras.fetch("db", "")
#   ' "$SLOTS_FILE" "$SLOT")"
#
# extras is project-managed — setup_dev_slots.sh does NOT touch it.
#
# Canonical doctrine: docs/architecture/adr-019-dev-slots-and-deploy-stubs.md

set -euo pipefail

# Resolve the project parent dir from the script's own location, so the
# script can be invoked from anywhere (project parent, code root, worktree,
# arbitrary CWD).
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# ---------------------------------------------------------------------------
# Argument parsing (runs before .env sourcing so --help works without .env)
# ---------------------------------------------------------------------------
SLOT=""
WID=""
AUTO_CONFIRM="false"
CODE_PATH_FLAG=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --wid=*) WID="${1#*=}" ;;
    --auto-confirm) AUTO_CONFIRM="true" ;;
    --code-path=*) CODE_PATH_FLAG="${1#*=}" ;;
    --help|-h)
      awk '/^#/{print; next} {exit}' "${BASH_SOURCE[0]}" | sed 's/^# \?//'
      exit 0
      ;;
    -*)
      echo "Unknown flag: $1" >&2
      echo "Usage: ./scripts/launch_local.sh <slot> [--wid=W-NN] [--auto-confirm] [--code-path=PATH]" >&2
      exit 1
      ;;
    *)
      if [[ -z "$SLOT" ]]; then
        SLOT="$1"
      else
        echo "Unexpected positional arg: $1 (only <slot> is positional)" >&2
        exit 1
      fi
      ;;
  esac
  shift
done

if [[ -z "$SLOT" ]]; then
  echo "Usage: ./scripts/launch_local.sh <slot> [--wid=W-NN] [--auto-confirm] [--code-path=PATH]" >&2
  echo "Slots are defined in docs/dev/slots.yaml (e.g. dev0, dev1, dev2, dev3)." >&2
  exit 1
fi

# DEFAULT_CODE_SUBDIR is sourced from $PROJECT_DIR/.env per ADR-021
# (split-layout single-source rule). setup_dev_slots.sh enforces .env exists
# before this script can run, so a hard error here is correct.
ENV_FILE="$PROJECT_DIR/.env"
if [[ ! -f "$ENV_FILE" ]]; then
  echo "ERROR: missing $ENV_FILE" >&2
  echo "  Run scripts/setup_dev_slots.sh first (it seeds and validates .env)." >&2
  exit 1
fi
set -a
# shellcheck source=/dev/null
. "$ENV_FILE"
set +a
if [[ -z "${DEFAULT_CODE_SUBDIR:-}" || "$DEFAULT_CODE_SUBDIR" == "PLACEHOLDER" ]]; then
  echo "ERROR: DEFAULT_CODE_SUBDIR not set in $ENV_FILE" >&2
  echo "  Strategist owns this value (per ADR-021). Fill it in then re-run." >&2
  exit 1
fi

SLOTS_FILE="$PROJECT_DIR/docs/dev/slots.yaml"
STATE_ROOT="$PROJECT_DIR/.local/dev_slots"
STATE_FILE="$STATE_ROOT/${SLOT}.yaml"

# ---------------------------------------------------------------------------
# Slot registry lookup
# ---------------------------------------------------------------------------
if [[ ! -f "$SLOTS_FILE" ]]; then
  echo "Missing slot registry: $SLOTS_FILE" >&2
  echo "Run scripts/setup_dev_slots.sh first." >&2
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
  echo "Unknown slot: $SLOT (or registry malformed: $SLOTS_FILE)" >&2
  exit 1
fi

if [[ "$PORT" == "0" || "$HOSTNAME_VAL" == "PLACEHOLDER" ]]; then
  echo "Slot $SLOT not configured (port=$PORT hostname=$HOSTNAME_VAL)." >&2
  echo "Run: ./scripts/setup_dev_slots.sh" >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# CODE_PATH resolution
# ---------------------------------------------------------------------------
resolve_code_path() {
  # 1. Explicit --code-path flag
  if [[ -n "$CODE_PATH_FLAG" ]]; then
    echo "$CODE_PATH_FLAG"
    return
  fi
  # 2. CODE_PATH env var (backwards compat with pre-safety-primitive callers)
  if [[ -n "${CODE_PATH:-}" ]]; then
    if [[ "$CODE_PATH" = /* ]]; then
      echo "$CODE_PATH"
    else
      # Relative CODE_PATH anchored to PROJECT_DIR (matches legacy default)
      echo "$PROJECT_DIR/$CODE_PATH"
    fi
    return
  fi
  # 3. --wid=W-NN → match a worktree under /tmp/worktrees/${DEFAULT_CODE_SUBDIR}/
  if [[ -n "$WID" ]]; then
    local wid_lower
    wid_lower="$(echo "$WID" | tr '[:upper:]' '[:lower:]')"
    local search_dir="/tmp/worktrees/${DEFAULT_CODE_SUBDIR}"
    if [[ ! -d "$search_dir" ]]; then
      echo "ERROR: --wid=$WID given but $search_dir does not exist" >&2
      exit 1
    fi
    local matches=()
    while IFS= read -r -d '' m; do
      matches+=("$m")
    done < <(find "$search_dir" -mindepth 1 -maxdepth 1 -type d -name "${wid_lower}-*" -print0 2>/dev/null)
    if [[ ${#matches[@]} -eq 0 ]]; then
      echo "ERROR: no worktree matches --wid=$WID under $search_dir/${wid_lower}-*" >&2
      exit 1
    fi
    if [[ ${#matches[@]} -gt 1 ]]; then
      echo "ERROR: multiple worktrees match --wid=$WID:" >&2
      printf '  %s\n' "${matches[@]}" >&2
      exit 1
    fi
    echo "${matches[0]}"
    return
  fi
  # 4. $PWD inside a git checkout (worktree or main)
  local toplevel
  if toplevel="$(git -C "$PWD" rev-parse --show-toplevel 2>/dev/null)"; then
    echo "$toplevel"
    return
  fi
  # 5. Project-parent fallback
  if [[ -d "$PROJECT_DIR/$DEFAULT_CODE_SUBDIR" ]]; then
    echo "$PROJECT_DIR/$DEFAULT_CODE_SUBDIR"
    return
  fi
  echo "ERROR: cannot resolve CODE_PATH" >&2
  echo "  $PWD is not inside a git checkout" >&2
  echo "  --wid not given" >&2
  echo "  no fallback $PROJECT_DIR/$DEFAULT_CODE_SUBDIR" >&2
  exit 1
}

CODE_PATH_RESOLVED="$(resolve_code_path)"

if [[ ! -d "$CODE_PATH_RESOLVED" ]]; then
  echo "ERROR: resolved CODE_PATH does not exist: $CODE_PATH_RESOLVED" >&2
  exit 1
fi

# Worktree-vs-main detection. `.git` is a file in a worktree (gitdir pointer)
# and a directory in the main checkout.
if [[ -f "$CODE_PATH_RESOLVED/.git" ]]; then
  MODE="worktree"
elif [[ -d "$CODE_PATH_RESOLVED/.git" ]]; then
  MODE="main"
else
  echo "ERROR: $CODE_PATH_RESOLVED is not a git checkout (no .git)" >&2
  exit 1
fi

# Branch + SHA (best-effort)
BRANCH="$(git -C "$CODE_PATH_RESOLVED" rev-parse --abbrev-ref HEAD 2>/dev/null || echo unknown)"
SHA="$(git -C "$CODE_PATH_RESOLVED" rev-parse --short HEAD 2>/dev/null || echo unknown)"

# ---------------------------------------------------------------------------
# .env handling (worktree case)
# ---------------------------------------------------------------------------
# Canonical app .env (NOT the project-parent .env sourced above) lives at the
# main checkout: $PROJECT_DIR/$DEFAULT_CODE_SUBDIR/.env. Worktrees don't carry
# gitignored files, so a fresh worktree won't have its own .env — symlink it
# from the canonical location if absent. Projects without an app .env will
# see "absent" and the project body is responsible for handling that case.
CANONICAL_APP_ENV="$PROJECT_DIR/$DEFAULT_CODE_SUBDIR/.env"
TARGET_APP_ENV="$CODE_PATH_RESOLVED/.env"
ENV_ACTION=""

if [[ -e "$TARGET_APP_ENV" ]]; then
  if [[ -L "$TARGET_APP_ENV" ]]; then
    ENV_STATUS="symlink → $(readlink "$TARGET_APP_ENV")"
  else
    ENV_STATUS="present (regular file)"
  fi
elif [[ -f "$CANONICAL_APP_ENV" ]]; then
  ENV_STATUS="will symlink from $CANONICAL_APP_ENV"
  ENV_ACTION="symlink"
else
  ENV_STATUS="absent (no canonical to bootstrap from — project body must handle)"
fi

# ---------------------------------------------------------------------------
# Pre-launch confirmation block (the load-bearing safety primitive)
# ---------------------------------------------------------------------------
# This block exists because of a source-mismatch incident: a launch invoked
# from a worktree CWD silently brought up the main checkout instead. The
# operator only noticed because the missing feature was visually obvious.
# Surfacing source + mode + branch + SHA before launch turns that class of
# failure from "discover during QA" into "discover before launch."
cat <<EOF

Launching $SLOT
  source:    $CODE_PATH_RESOLVED
             ($MODE mode — branch $BRANCH @ $SHA)
  port:      $PORT
  hostname:  $HOSTNAME_VAL
  .env:      $ENV_STATUS

EOF

if [[ "$AUTO_CONFIRM" != "true" ]]; then
  read -r -p "Proceed? [Y/n] " REPLY
  if [[ "$REPLY" =~ ^[Nn] ]]; then
    echo "Aborted."
    exit 0
  fi
fi

# Apply .env action now that user has confirmed.
if [[ "$ENV_ACTION" == "symlink" ]]; then
  ln -s "$CANONICAL_APP_ENV" "$TARGET_APP_ENV"
  echo "Symlinked $TARGET_APP_ENV → $CANONICAL_APP_ENV"
fi

# ---------------------------------------------------------------------------
# Slot claim — write state file (generic schema)
# ---------------------------------------------------------------------------
mkdir -p "$STATE_ROOT"

if [[ -f "$STATE_FILE" ]]; then
  echo "Slot already claimed: $SLOT" >&2
  echo "State file: $STATE_FILE" >&2
  echo "Run scripts/teardown_local.sh $SLOT to release, or use a different slot." >&2
  exit 1
fi

cat > "$STATE_FILE" <<EOF
slot: $SLOT
role: $ROLE
hostname: $HOSTNAME_VAL
port: $PORT
claimed_at: $(date -u +"%Y-%m-%dT%H:%M:%SZ")
ticket: ${WID:-TBD}
status: claimed
code_path: $CODE_PATH_RESOLVED
mode: $MODE
branch: $BRANCH
sha: $SHA
EOF

echo ""
echo "Claimed slot $SLOT"
echo "  state file: $STATE_FILE"

# ---------------------------------------------------------------------------
# PROJECT-SPECIFIC LAUNCH BODY
#
# Fill this in once for the project. Use $CODE_PATH_RESOLVED (NOT $PWD or
# $PROJECT_DIR/$DEFAULT_CODE_SUBDIR) so worktree launches actually launch
# the worktree's code. Examples:
#
#   docker run -d --name "${SLOT}-myapp" -p "${PORT}:3000" \
#     -v "${CODE_PATH_RESOLVED}:/app" -e NODE_ENV=development myapp:dev
#
#   COMPOSE_FILE="${CODE_PATH_RESOLVED}/docker-compose.yml"
#   COMPOSE_PROJECT="${SLOT}-myapp"
#   docker compose -p "$COMPOSE_PROJECT" -f "$COMPOSE_FILE" up -d --build
#
#   (cd "$CODE_PATH_RESOLVED" && npm run dev -- --port "${PORT}" &)
#   echo $! > "$STATE_ROOT/${SLOT}.pid"
#
# If the project body needs to record project-specific state for teardown
# (e.g. compose project name, compose file path, override file path), append
# those fields to $STATE_FILE so teardown_local.sh's project body can mirror:
#
#   cat >> "$STATE_FILE" <<APPEND
#   compose_project: $COMPOSE_PROJECT
#   compose_file: $COMPOSE_FILE
#   APPEND
#
# After the runtime is up, verify Caddy routes ${HOSTNAME_VAL} to
# localhost:${PORT}.
#
# To fill in: replace the placeholder block below (from the `echo
# "Project-specific..."` line through `exit 1`) with your launch commands.
# ---------------------------------------------------------------------------
echo "Project-specific launch body is not implemented yet."
echo "Fill in this script (PROJECT-SPECIFIC LAUNCH BODY section) so slot $SLOT"
echo "launches repeatably on port $PORT, then commit the change."
rm -f "$STATE_FILE"
echo "Released temporary slot claim because launch flow is still a placeholder."
exit 1
