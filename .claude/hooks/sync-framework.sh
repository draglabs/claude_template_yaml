#!/usr/bin/env bash
# sync-framework.sh — runs on SessionStart, keeps the framework canonical.
#
# Resolves claude_template_yaml location, destructively syncs docs/dev_framework/
# and .claude/hooks/ from the template, initializes docs/framework_exceptions/
# if missing, and refreshes the managed block in CLAUDE.md. All failure modes
# warn + continue — sync is value-add, never a session-start blocker.
#
# See docs/architecture/adr-014-framework-sync-on-session-start.md.

# Soft-fail mode: every step logs and continues.
set +e

# Ensure CLAUDE_PROJECT_DIR is set. Fall back to pwd if the hook harness
# somehow didn't populate it. realpath normalizes for the self-detect below.
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(pwd)}"
PROJECT_DIR="$(cd "$PROJECT_DIR" 2>/dev/null && pwd -P)"

# ---------------------------------------------------------------------------
# 1. Resolve template root, in this order:
#    (a) CLAUDE_TEMPLATE_ROOT= line in $PROJECT_DIR/.env
#    (b) CLAUDE_TEMPLATE_ROOT= line in any immediate subdir's .env that has .git/
#        (supports split-layout adopters whose single .env is inside the code repo)
#    (c) sibling directory ../claude_template_yaml
#    (d) sibling directory ../../claude_template_yaml
#    (e) sibling directory ../../../claude_template_yaml
#
# Shell environment variables are intentionally NOT consulted — adopters
# configure via local .env or rely on the sibling-depth fallback. Removing
# the shell-env path eliminates surprise when an adopter's environment has
# a stale CLAUDE_TEMPLATE_ROOT export pointing at a long-defunct location.
# ---------------------------------------------------------------------------

TEMPLATE_ROOT=""

if [[ -f "$PROJECT_DIR/.env" ]]; then
  # Pull CLAUDE_TEMPLATE_ROOT= line from .env if present. Strip quotes.
  TEMPLATE_ROOT="$(grep -E '^CLAUDE_TEMPLATE_ROOT=' "$PROJECT_DIR/.env" 2>/dev/null \
                    | head -1 | cut -d= -f2- | sed 's/^["'"'"']//; s/["'"'"']$//')"
fi

# Fallback: scan immediate subdirectories that look like git repos and try
# their .env files. This supports split-layout adopters whose single .env
# lives inside the code subdirectory rather than at the parent level
# (per ADR-021).
if [[ -z "$TEMPLATE_ROOT" ]]; then
  for subdir in "$PROJECT_DIR"/*/; do
    [[ -d "$subdir/.git" && -f "$subdir/.env" ]] || continue
    TEMPLATE_ROOT="$(grep -E '^CLAUDE_TEMPLATE_ROOT=' "$subdir/.env" 2>/dev/null \
                      | head -1 | cut -d= -f2- | sed 's/^["'"'"']//; s/["'"'"']$//')"
    [[ -n "$TEMPLATE_ROOT" ]] && break
  done
fi

if [[ -z "$TEMPLATE_ROOT" ]]; then
  PARENT="$PROJECT_DIR"
  for depth in 1 2 3; do
    PARENT="$(dirname "$PARENT")"
    CANDIDATE="$PARENT/claude_template_yaml"
    if [[ -d "$CANDIDATE" ]]; then
      TEMPLATE_ROOT="$CANDIDATE"
      break
    fi
  done
fi

if [[ -z "$TEMPLATE_ROOT" || ! -d "$TEMPLATE_ROOT" ]]; then
  echo "[sync-framework] WARN: claude_template_yaml not found. Tried: \$PROJECT_DIR/.env, immediate-subdir .env files, ../claude_template_yaml, ../../claude_template_yaml, ../../../claude_template_yaml. Skipping sync."
  exit 0
fi

TEMPLATE_ROOT="$(cd "$TEMPLATE_ROOT" && pwd -P)"

# ---------------------------------------------------------------------------
# 2. Template-self detection. If this project IS the template, skip.
# ---------------------------------------------------------------------------

if [[ "$PROJECT_DIR" == "$TEMPLATE_ROOT" ]]; then
  echo "[sync-framework] This project IS the template — no sync."
  exit 0
fi

# ---------------------------------------------------------------------------
# 2b. Flat-layout detection.
#     If $PROJECT_DIR contains a .git/ directory, the project is using the
#     legacy flat layout (project dir == git repo). Emit a migration notice
#     and continue — the sync itself is still valid (all sync targets write
#     to $PROJECT_DIR, which is correct for both layouts). See ADR-021.
# ---------------------------------------------------------------------------

if [[ -d "$PROJECT_DIR/.git" ]]; then
  echo "[sync-framework] NOTICE: flat layout detected — this project's working directory IS the git repository."
  echo "[sync-framework] The canonical framework layout is split: tracking material (CLAUDE.md, docs/, .claude/) lives in a parent directory; the git repo is a named subdirectory."
  echo "[sync-framework] Migration guide: docs/dev_framework/migration-guide-split-layout.md"
  echo "[sync-framework] Sync continuing (flat layout still supported; migration recommended)."
fi

# ---------------------------------------------------------------------------
# 3. Destructive sync of docs/dev_framework/ from template.
#    Per ADR-014: always destructive. If local framework drifted, pull it
#    back into alignment. Adopters are expected to make changes ONLY in
#    docs/framework_exceptions/, not in docs/dev_framework/.
# ---------------------------------------------------------------------------

if [[ -d "$TEMPLATE_ROOT/docs/dev_framework" ]]; then
  mkdir -p "$PROJECT_DIR/docs/dev_framework"
  if rsync -a --delete "$TEMPLATE_ROOT/docs/dev_framework/" "$PROJECT_DIR/docs/dev_framework/" 2>/dev/null; then
    echo "[sync-framework] docs/dev_framework/ synced from template"
  else
    echo "[sync-framework] WARN: rsync of docs/dev_framework/ failed"
  fi
else
  echo "[sync-framework] WARN: template has no docs/dev_framework/; skipping framework sync"
fi

# ---------------------------------------------------------------------------
# 4. Additive sync of .claude/hooks/ from template.
#    Template-owned hook files overwrite. Adopter-owned hooks (anything
#    not in the template) are preserved — .claude/hooks/ is a shared
#    namespace, unlike docs/dev_framework/ which is fully template-owned.
#    If the template retires a hook, adopters keep the old file (cruft,
#    but not dangerous).
# ---------------------------------------------------------------------------

if [[ -d "$TEMPLATE_ROOT/.claude/hooks" ]]; then
  mkdir -p "$PROJECT_DIR/.claude/hooks"
  if rsync -a "$TEMPLATE_ROOT/.claude/hooks/" "$PROJECT_DIR/.claude/hooks/" 2>/dev/null; then
    echo "[sync-framework] .claude/hooks/ synced from template (additive; adopter-owned hooks preserved)"
  else
    echo "[sync-framework] WARN: rsync of .claude/hooks/ failed"
  fi
fi

# ---------------------------------------------------------------------------
# 5. Initialize docs/framework_exceptions/ if missing.
#    Idempotent: only creates files that don't exist. On repeat runs, leaves
#    adopter's accumulated exceptions untouched.
# ---------------------------------------------------------------------------

EXC_DIR="$PROJECT_DIR/docs/framework_exceptions"
STUB_DIR="$TEMPLATE_ROOT/docs/dev_framework/_stubs/framework_exceptions"

if [[ -d "$STUB_DIR" ]]; then
  mkdir -p "$EXC_DIR"
  for stub in "$STUB_DIR"/*.md; do
    [[ -f "$stub" ]] || continue
    name="$(basename "$stub")"
    if [[ ! -f "$EXC_DIR/$name" ]]; then
      cp "$stub" "$EXC_DIR/$name" && \
        echo "[sync-framework] initialized docs/framework_exceptions/$name from stub"
    fi
  done
else
  echo "[sync-framework] WARN: stubs dir missing at $STUB_DIR; framework_exceptions/ not initialized"
fi

# Sanity: verify the three expected files exist now.
for f in dev_framework_exceptions.md process-exceptions.md execution-incidents.md; do
  if [[ ! -f "$EXC_DIR/$f" ]]; then
    echo "[sync-framework] WARN: docs/framework_exceptions/$f still missing after init"
  fi
done

# ---------------------------------------------------------------------------
# 5b. Seed .mcp.json from stub if adopter doesn't have one.
#     Idempotent: never overwrites an existing .mcp.json — adopters who
#     have customized their MCP config (e.g., absolute Node paths for nvm,
#     extra servers, removed servers) keep their version.
# ---------------------------------------------------------------------------

MCP_STUB="$TEMPLATE_ROOT/docs/dev_framework/_stubs/.mcp.json"
LOCAL_MCP="$PROJECT_DIR/.mcp.json"

if [[ -f "$MCP_STUB" && ! -f "$LOCAL_MCP" ]]; then
  cp "$MCP_STUB" "$LOCAL_MCP" && \
    echo "[sync-framework] seeded .mcp.json from stub (gitnexus + docker). Run 'gitnexus index .' once to build the code graph for this repo. See docs/dev_framework/approved-mcps.md."
fi

# ---------------------------------------------------------------------------
# 5c. Initialize project-local stubs (scripts/ + docs/dev/slots.yaml)
#     if missing. Idempotent: never overwrites filled-in stubs. Adopters
#     fill any project-specific bodies once; subsequent syncs leave their
#     work alone.
#
#     Stubs live under $TEMPLATE_ROOT/docs/dev_framework/_stubs/<relpath>
#     and copy to $PROJECT_DIR/<relpath>, preserving the executable bit
#     for .sh files (cp -p).
#
#     Stubs covered:
#       - Dev-slot infrastructure (ADR-019): launch_local.sh,
#         teardown_local.sh, main_to_prod.sh, setup_dev_slots.sh,
#         docs/dev/slots.yaml.
#       - Reviewer-side mechanical scope check (ADR-020):
#         check-touches.sh — generic, no project-specific body to fill.
#       - Project variables starter (ADR-019 Revision v1.1):
#         .env.example — committed template; adopter copies to .env (gitignored)
#         and fills in. Strategist owns the values per first-contact interview.
# ---------------------------------------------------------------------------

DEV_SLOT_STUBS=(
  "scripts/launch_local.sh"
  "scripts/teardown_local.sh"
  "scripts/main_to_prod.sh"
  "scripts/setup_dev_slots.sh"
  "scripts/check-touches.sh"
  "docs/dev/slots.yaml"
  ".env.example"
)

for relpath in "${DEV_SLOT_STUBS[@]}"; do
  src="$TEMPLATE_ROOT/docs/dev_framework/_stubs/$relpath"
  dst="$PROJECT_DIR/$relpath"
  if [[ -f "$src" && ! -f "$dst" ]]; then
    mkdir -p "$(dirname "$dst")"
    if cp -p "$src" "$dst" 2>/dev/null; then
      echo "[sync-framework] initialized $relpath from stub"
    else
      echo "[sync-framework] WARN: failed to initialize $relpath"
    fi
  fi
done

# ---------------------------------------------------------------------------
# 6. CLAUDE.md managed-block reconciliation.
#    The template's CLAUDE.md wraps framework-owned sections in:
#      <!-- BEGIN FRAMEWORK MANAGED -->
#      ...
#      <!-- END FRAMEWORK MANAGED -->
#    Content inside is synced from template; content outside is project-owned.
# ---------------------------------------------------------------------------

TPL_CLAUDE="$TEMPLATE_ROOT/CLAUDE.md"
LOCAL_CLAUDE="$PROJECT_DIR/CLAUDE.md"
BEGIN_MARK="<!-- BEGIN FRAMEWORK MANAGED -->"
END_MARK="<!-- END FRAMEWORK MANAGED -->"

if [[ -f "$TPL_CLAUDE" && -f "$LOCAL_CLAUDE" ]]; then
  tpl_has_begin=$(grep -c "$BEGIN_MARK" "$TPL_CLAUDE" 2>/dev/null || echo 0)
  tpl_has_end=$(grep -c "$END_MARK" "$TPL_CLAUDE" 2>/dev/null || echo 0)
  loc_has_begin=$(grep -c "$BEGIN_MARK" "$LOCAL_CLAUDE" 2>/dev/null || echo 0)
  loc_has_end=$(grep -c "$END_MARK" "$LOCAL_CLAUDE" 2>/dev/null || echo 0)

  if [[ "$tpl_has_begin" -lt 1 || "$tpl_has_end" -lt 1 ]]; then
    echo "[sync-framework] WARN: template CLAUDE.md missing managed-block markers; cannot reconcile"
  elif [[ "$loc_has_begin" -lt 1 || "$loc_has_end" -lt 1 ]]; then
    echo "[sync-framework] WARN: local CLAUDE.md has no managed-block markers; add $BEGIN_MARK / $END_MARK around framework sections to enable reconciliation"
  else
    tmp_before="$(mktemp)"
    tmp_after="$(mktemp)"
    tmp_block="$(mktemp)"
    # Everything BEFORE the BEGIN marker in local (exclusive):
    sed "/$BEGIN_MARK/,\$d" "$LOCAL_CLAUDE" > "$tmp_before"
    # Everything AFTER the END marker in local (exclusive):
    sed -n "/$END_MARK/,\$p" "$LOCAL_CLAUDE" | sed '1d' > "$tmp_after"
    # The full managed block from the template (inclusive of both markers):
    sed -n "/$BEGIN_MARK/,/$END_MARK/p" "$TPL_CLAUDE" > "$tmp_block"

    if [[ -s "$tmp_block" ]]; then
      cat "$tmp_before" "$tmp_block" "$tmp_after" > "$LOCAL_CLAUDE"
      echo "[sync-framework] CLAUDE.md managed block refreshed from template"
    else
      echo "[sync-framework] WARN: template managed block extracted empty; CLAUDE.md not changed"
    fi
    rm -f "$tmp_before" "$tmp_after" "$tmp_block"
  fi
fi

echo "[sync-framework] done."
