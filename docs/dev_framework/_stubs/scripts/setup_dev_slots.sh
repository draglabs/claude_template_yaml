#!/usr/bin/env bash
# One-time interactive setup for dev slots.
#
# Reads project variables from $PROJECT_DIR/.env (sourced) — the canonical
# machine-readable surface per ADR-019 Revision (v1.1). Halts if .env is
# missing or if PROJECT_SUB / PROJECT_PORTS still hold PLACEHOLDER values —
# the Strategist owns these (per strategist.md §"First-contact interview")
# and the Developer can't proceed until the interview is done.
#
# What this script does:
#   1. Source $PROJECT_DIR/.env and validate required vars.
#   2. Ask whether the project has an HTTP surface (sets http_surface in
#      slots.yaml; gates Caddy block generation).
#   3. Pick a base port within PROJECT_PORTS (validated to fit 4 slots).
#   4. Write hostnames + ports into docs/dev/slots.yaml.
#   5. If http_surface=true: generate Caddyfile block per slot, optionally
#      append/update in user's Caddyfile with begin/end markers.
#   6. Print the extras: {} edit pattern for projects with secondary ports
#      (DB, cache, queue). extras stay project-managed — this script does
#      NOT write them.
#
# Does NOT edit CLAUDE.md or .env — those are the Strategist's surfaces.
# slots.yaml is the source of truth for actual port + hostname assignments.
#
# Safe to re-run: detects existing config and asks before overwriting.
#
# Hostnames use .localhost (RFC 6761; auto-resolves to 127.0.0.1) so no
# /etc/hosts edits are needed. Caddy reverse-proxies hostname → port.
#
# Canonical doctrine: docs/architecture/adr-019-dev-slots-and-deploy-stubs.md
# (Revision v1.1)

set -euo pipefail

SLOTS_FILE="docs/dev/slots.yaml"
ENV_FILE=".env"
ENV_EXAMPLE=".env.example"

# ---------- Locate slots.yaml ----------
if [[ ! -f "$SLOTS_FILE" ]]; then
  echo "ERROR: Missing $SLOTS_FILE."
  echo "Is the framework synced? Run a SessionStart in this project to trigger sync, then re-run this script."
  exit 1
fi

# ---------- Source .env ----------
if [[ ! -f "$ENV_FILE" ]]; then
  echo ""
  echo "ERROR: Missing $ENV_FILE."
  if [[ -f "$ENV_EXAMPLE" ]]; then
    echo ""
    echo "  A starter $ENV_EXAMPLE was seeded by the framework. Copy it and fill in:"
    echo "    cp $ENV_EXAMPLE $ENV_FILE"
    echo "    \$EDITOR $ENV_FILE   # Strategist fills the values per first-contact interview"
    echo ""
    echo "  Then re-run this script."
  else
    echo ""
    echo "  Run a SessionStart to sync the framework (which seeds $ENV_EXAMPLE), then:"
    echo "    cp $ENV_EXAMPLE $ENV_FILE"
    echo "    \$EDITOR $ENV_FILE"
  fi
  echo ""
  echo "  See strategist.md §\"First-contact interview\" for what to fill in."
  exit 1
fi

# shellcheck disable=SC1091
set -a
# shellcheck source=/dev/null
. "$ENV_FILE"
set +a

# ---------- Validate required vars ----------
MISSING=()
[[ -z "${PROJECT_SUB:-}" || "$PROJECT_SUB" == "PLACEHOLDER" ]] && MISSING+=("PROJECT_SUB")
[[ -z "${PROJECT_PORTS:-}" || "$PROJECT_PORTS" == "PLACEHOLDER" ]] && MISSING+=("PROJECT_PORTS")

if (( ${#MISSING[@]} > 0 )); then
  echo ""
  echo "ERROR: $ENV_FILE is missing required values for dev-slot setup:"
  for var in "${MISSING[@]}"; do
    echo "  - $var (currently empty or PLACEHOLDER)"
  done
  echo ""
  echo "  These are Strategist-confirmed values from the first-contact interview"
  echo "  (per strategist.md §\"First-contact interview\"). Ask the Strategist to:"
  echo ""
  echo "    1. Interview the user about project subdomain and port range."
  echo "    2. Fill the values in $ENV_FILE."
  echo "    3. Update CLAUDE.md's project-variable bullets to match (human-readable mirror)."
  echo "    4. Commit + push (under flat / tracked-parent layout) or save (untracked-parent)."
  echo ""
  echo "  Then re-run this script."
  echo ""
  echo "  See ADR-019 Revision (v1.1) for the .env-canonical doctrine."
  exit 1
fi

SUB="$PROJECT_SUB"

# ---------- Parse PROJECT_PORTS range ----------
# Accept "<low>-<high>" format.
PORT_LOW=""
PORT_HIGH=""
if [[ "$PROJECT_PORTS" =~ ^([0-9]+)-([0-9]+)$ ]]; then
  PORT_LOW="${BASH_REMATCH[1]}"
  PORT_HIGH="${BASH_REMATCH[2]}"
fi

if [[ -z "$PORT_LOW" || -z "$PORT_HIGH" ]] || (( PORT_LOW >= PORT_HIGH )); then
  echo ""
  echo "ERROR: PROJECT_PORTS=\"$PROJECT_PORTS\" in $ENV_FILE is not a valid range."
  echo "Expected format: '<low>-<high>' (e.g. PROJECT_PORTS=3050-3060)."
  echo "Strategist: fix the value and re-run."
  exit 1
fi

if (( PORT_HIGH - PORT_LOW < 3 )); then
  echo ""
  echo "ERROR: Confirmed range $PORT_LOW-$PORT_HIGH is too narrow for 4 slots."
  echo "Need at least 4 contiguous ports. Strategist: widen PROJECT_PORTS in $ENV_FILE."
  exit 1
fi

echo ""
echo "Project: $SUB (from \$PROJECT_SUB)"
echo "Confirmed port range: $PORT_LOW-$PORT_HIGH (from \$PROJECT_PORTS)"

# ---------- HTTP surface question ----------
echo ""
echo "Does this project expose an HTTP surface that needs Caddy routing?"
echo "  Examples of yes: web app, API server, admin UI."
echo "  Examples of no:  CLI tool, library, headless data pipeline."
echo "If yes, this script generates Caddyfile blocks routing"
echo "<slot>.${SUB}.localhost → localhost:<port> per slot."
echo "If no, slots still get ports assigned but no Caddy blocks are written."
read -r -p "HTTP surface? [Y/n] " HTTP_ANSWER
case "${HTTP_ANSWER:-y}" in
  y|Y|yes|Yes|YES) HTTP_SURFACE=true ;;
  n|N|no|No|NO)    HTTP_SURFACE=false ;;
  *) echo "Invalid answer: $HTTP_ANSWER"; exit 1 ;;
esac

# ---------- Ask base port (constrained to confirmed range) ----------
DEFAULT_BASE="$PORT_LOW"
echo ""
read -r -p "Base port for dev slots within $PORT_LOW-$PORT_HIGH [$DEFAULT_BASE]: " BASE
BASE="${BASE:-$DEFAULT_BASE}"
if ! [[ "$BASE" =~ ^[0-9]+$ ]]; then
  echo "Invalid port: $BASE"
  exit 1
fi
if (( BASE < PORT_LOW )) || (( BASE + 3 > PORT_HIGH )); then
  echo ""
  echo "ERROR: Base $BASE puts slots at $BASE-$((BASE+3)), which is outside the"
  echo "Strategist-confirmed range $PORT_LOW-$PORT_HIGH. Pick a base such that"
  echo "all 4 slots fit within the range."
  exit 1
fi

PORTS=("$BASE" "$((BASE+1))" "$((BASE+2))" "$((BASE+3))")
SLOTS=("dev0" "dev1" "dev2" "dev3")

echo ""
echo "Will configure (http_surface=$HTTP_SURFACE):"
for i in 0 1 2 3; do
  if [[ "$HTTP_SURFACE" == "true" ]]; then
    printf "  %s -> %s.%s.localhost via Caddy → localhost:%s\n" "${SLOTS[$i]}" "${SLOTS[$i]}" "$SUB" "${PORTS[$i]}"
  else
    printf "  %s -> port %s (no Caddy block; project is non-HTTP)\n" "${SLOTS[$i]}" "${PORTS[$i]}"
  fi
done
read -r -p "Proceed? [y/N] " CONFIRM
if [[ "$CONFIRM" != "y" && "$CONFIRM" != "Y" ]]; then
  echo "Aborted."
  exit 0
fi

# ---------- Update slots.yaml ----------
TMP_SLOTS="$(mktemp)"
ruby -e '
  require "yaml"
  data = YAML.load_file(ARGV[0])
  sub = ARGV[1]
  http_surface = ARGV[2] == "true"
  data["http_surface"] = http_surface
  4.times do |i|
    name = "dev#{i}"
    data["slots"][name]["hostname"] = "#{name}.#{sub}.localhost"
    data["slots"][name]["port"] = ARGV[3 + i].to_i
  end
  File.write(ARGV[7], data.to_yaml)
' "$SLOTS_FILE" "$SUB" "$HTTP_SURFACE" "${PORTS[@]}" "$TMP_SLOTS"
mv "$TMP_SLOTS" "$SLOTS_FILE"
echo "Wrote $SLOTS_FILE"

# ---------- Caddy block (only if HTTP surface) ----------
if [[ "$HTTP_SURFACE" == "true" ]]; then
  CADDY_BLOCK="$(mktemp)"
  {
    echo "# BEGIN ${SUB}-dev-slots (managed by scripts/setup_dev_slots.sh)"
    for i in 0 1 2 3; do
      echo "${SLOTS[$i]}.${SUB}.localhost {"
      echo "    reverse_proxy localhost:${PORTS[$i]}"
      echo "}"
    done
    echo "# END ${SUB}-dev-slots"
  } > "$CADDY_BLOCK"

  echo ""
  echo "Proposed Caddyfile block:"
  echo "---"
  cat "$CADDY_BLOCK"
  echo "---"

  # Detect Caddyfile path
  CADDY_CANDIDATES=(
    "/opt/homebrew/etc/Caddyfile"
    "/usr/local/etc/Caddyfile"
    "/etc/caddy/Caddyfile"
    "$HOME/Caddyfile"
  )
  CADDY_DEFAULT=""
  for cand in "${CADDY_CANDIDATES[@]}"; do
    if [[ -f "$cand" ]]; then
      CADDY_DEFAULT="$cand"
      break
    fi
  done
  CADDY_DEFAULT="${CADDY_DEFAULT:-$HOME/Caddyfile}"

  read -r -p "Caddyfile path [${CADDY_DEFAULT}]: " CADDY_PATH
  CADDY_PATH="${CADDY_PATH:-$CADDY_DEFAULT}"

  read -r -p "Append the block to ${CADDY_PATH}? [y/N] " WRITE_CADDY
  if [[ "$WRITE_CADDY" == "y" || "$WRITE_CADDY" == "Y" ]]; then
    # If markers exist, replace between them. Else append.
    if [[ -f "$CADDY_PATH" ]] && grep -q "^# BEGIN ${SUB}-dev-slots" "$CADDY_PATH"; then
      TMP_CADDY="$(mktemp)"
      awk -v block_file="$CADDY_BLOCK" -v marker="${SUB}-dev-slots" '
        $0 ~ "^# BEGIN " marker { in_block=1; while ((getline line < block_file) > 0) print line; next }
        $0 ~ "^# END " marker { in_block=0; next }
        !in_block { print }
      ' "$CADDY_PATH" > "$TMP_CADDY"
      cp "$TMP_CADDY" "$CADDY_PATH"
      rm -f "$TMP_CADDY"
      echo "Updated existing block in $CADDY_PATH"
    else
      [[ -f "$CADDY_PATH" ]] && printf "\n" >> "$CADDY_PATH"
      cat "$CADDY_BLOCK" >> "$CADDY_PATH"
      echo "Appended block to $CADDY_PATH"
    fi
  else
    echo "Skipped Caddyfile write — paste the block above into ${CADDY_PATH} manually."
  fi
  rm -f "$CADDY_BLOCK"
else
  echo ""
  echo "Skipped Caddyfile generation (http_surface=false)."
fi

# ---------- Suggest extras{} for projects with secondary ports ----------
echo ""
echo "---"
echo "If this project needs SECONDARY ports per slot (e.g. per-slot Postgres,"
echo "Redis, message queue for test isolation), add an extras: map under each"
echo "slot in $SLOTS_FILE. Example for per-slot DB:"
echo ""
echo "  dev1:"
echo "    role: parallel_developer"
echo "    hostname: dev1.${SUB}.localhost"
echo "    port: <http_port>           # set by this script"
echo "    extras:"
echo "      db: 5441                  # project-managed, edit by hand"
echo "    worktree_required: true"
echo ""
echo "The launch_local.sh project body reads extras directly from slots.yaml"
echo "(see the header comment in scripts/launch_local.sh for the Ruby snippet)."
echo "setup_dev_slots.sh does NOT manage extras — projects own them."

# ---------- Final reminders ----------
echo ""
echo "---"
echo "Setup complete. Next steps:"
if [[ "$HTTP_SURFACE" == "true" ]]; then
  echo "  1. Reload Caddy:"
  echo "       macOS (Homebrew): brew services restart caddy"
  echo "       Linux (systemd):  sudo systemctl reload caddy"
  echo "       Manual:           caddy reload --config <CADDYFILE_PATH>"
  echo "  2. First-time TLS trust (one-shot, only if browser shows cert warnings on https):"
  echo "       caddy trust"
  echo "  3. Verify: ./scripts/launch_local.sh dev0   (will exit 1 until you fill in"
  echo "             the PROJECT-SPECIFIC LAUNCH BODY section)"
  echo "  4. Add .local/ to .gitignore if not already there."
else
  echo "  1. Add per-slot extras{} to $SLOTS_FILE if needed (see suggestion above)."
  echo "  2. Fill in the PROJECT-SPECIFIC LAUNCH BODY in scripts/launch_local.sh."
  echo "  3. Verify: ./scripts/launch_local.sh dev0 (will exit 1 until launch body is filled)."
  echo "  4. Add .local/ to .gitignore if not already there."
fi
