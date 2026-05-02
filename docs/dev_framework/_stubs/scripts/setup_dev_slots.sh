#!/usr/bin/env bash
# One-time interactive setup for dev slots.
#
# Asks for base port, fills in docs/dev/slots.yaml with hostnames + ports,
# prints proposed Caddyfile block (and optionally appends it with begin/end
# markers for idempotent re-run). Does NOT edit CLAUDE.md — {{ports}} is in
# the framework-managed block (per ADR-014); slots.yaml is the source of
# truth for actual port values from here on.
#
# Safe to re-run: detects existing config and asks before overwriting.
#
# Hostnames use .localhost (RFC 6761; auto-resolves to 127.0.0.1) so no
# /etc/hosts edits are needed. Caddy reverse-proxies hostname → port.
#
# Canonical doctrine: docs/architecture/adr-019-dev-slots-and-deploy-stubs.md

set -euo pipefail

SLOTS_FILE="docs/dev/slots.yaml"
CLAUDE_FILE="CLAUDE.md"

if [[ ! -f "$SLOTS_FILE" ]]; then
  echo "Missing $SLOTS_FILE. Is the framework synced? Run a SessionStart in this project to trigger sync, then re-run this script."
  exit 1
fi

# ---------- Resolve {{sub}} ----------
SUB=""
if [[ -f "$CLAUDE_FILE" ]]; then
  # Look for an existing project subdomain. Pattern: `{{sub}}` is the placeholder
  # in the template; once filled, the literal value sits in CLAUDE.md.
  # Try to read a "{{sub}} — this project's subdomain (e.g. `myapp`)" line.
  SUB="$(grep -E '^\- \`\{\{sub\}\}\`' "$CLAUDE_FILE" 2>/dev/null | sed -E 's/.*\(e\.g\. \`([^`]+)\`\).*/\1/' | head -1 || true)"
fi

if [[ -z "$SUB" || "$SUB" == "myapp" ]]; then
  read -r -p "Project subdomain (e.g. myapp): " SUB
fi
if [[ -z "$SUB" ]]; then
  echo "Subdomain is required."
  exit 1
fi

# ---------- Ask base port ----------
read -r -p "Base port for dev slots [3060]: " BASE
BASE="${BASE:-3060}"
if ! [[ "$BASE" =~ ^[0-9]+$ ]] || (( BASE < 1024 || BASE > 65500 )); then
  echo "Invalid port: $BASE"
  exit 1
fi

PORTS=("$BASE" "$((BASE+1))" "$((BASE+2))" "$((BASE+3))")
SLOTS=("dev0" "dev1" "dev2" "dev3")

echo ""
echo "Will configure:"
for i in 0 1 2 3; do
  printf "  %s -> %s.%s.localhost on port %s\n" "${SLOTS[$i]}" "${SLOTS[$i]}" "$SUB" "${PORTS[$i]}"
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
  4.times do |i|
    name = "dev#{i}"
    data["slots"][name]["hostname"] = "#{name}.#{sub}.localhost"
    data["slots"][name]["port"] = ARGV[2 + i].to_i
  end
  File.write(ARGV[6], data.to_yaml)
' "$SLOTS_FILE" "$SUB" "${PORTS[@]}" "$TMP_SLOTS"
mv "$TMP_SLOTS" "$SLOTS_FILE"
echo "Wrote $SLOTS_FILE"

# ---------- Note about CLAUDE.md ----------
#
# Deliberately NOT editing CLAUDE.md. The {{ports}} description sits inside
# the framework-managed block (per ADR-014) and would be overwritten by
# sync-framework.sh on the next session start, silently reverting the edit.
#
# slots.yaml is the authoritative source of truth for actual port values
# from this point on. CLAUDE.md's {{ports}} bullet stays as the framework's
# generic description; slots.yaml has the project's concrete port assignments.
echo "Port range recorded in $SLOTS_FILE. CLAUDE.md {{ports}} bullet is a framework"
echo "variable description and stays as-is — slots.yaml is the source of truth."

# ---------- Caddy block ----------
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

# ---------- Final reminders ----------
echo ""
echo "Setup complete. Next steps:"
echo "  1. Reload Caddy:"
echo "       macOS (Homebrew): brew services restart caddy"
echo "       Linux (systemd):  sudo systemctl reload caddy"
echo "       Manual:           caddy reload --config ${CADDY_PATH}"
echo "  2. First-time TLS trust (one-shot, only if browser shows cert warnings on https):"
echo "       caddy trust"
echo "  3. Verify: ./scripts/launch_local.sh dev0   (will exit 1 until you fill in"
echo "             the PROJECT-SPECIFIC LAUNCH BODY section)"
echo "  4. Add .local/ to .gitignore if not already there."
