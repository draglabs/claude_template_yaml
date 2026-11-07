#!/usr/bin/env bash
# sync-framework.sh — runs on SessionStart, keeps the framework canonical.
#
# Resolves claude_template_yaml location, destructively syncs docs/dev_framework/
# and .claude/hooks/ from the template, initializes docs/framework_exceptions/
# if missing, and refreshes the managed block in CLAUDE.md. All failure modes
# warn + continue — sync is value-add, never a session-start blocker.
#
# See docs/dev_framework/adrs/fwadr-014-framework-sync-on-session-start.md.

# Soft-fail mode: every step logs and continues.
set +e

# Ensure CLAUDE_PROJECT_DIR is set. Fall back to pwd if the hook harness
# somehow didn't populate it. realpath normalizes for the self-detect below.
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(pwd)}"
PROJECT_DIR="$(cd "$PROJECT_DIR" 2>/dev/null && pwd -P)"

# ---------------------------------------------------------------------------
# 0. Launch-env binding check (FWADR-032).
#    Hooks inherit Claude's process env. If a project .env that declares
#    PROJECT_NAME exists but PROJECT_NAME is absent from this process env,
#    Claude was launched without sourcing .env — so MCP credentials and the
#    FWADR-030 git-auth auto-wire are dead for this whole session. Can't be
#    repaired from here (env must precede the process): NOTICE + relaunch
#    instruction. The grep guard keeps app-only .env files (no framework
#    variables) from false-positiving.
# ---------------------------------------------------------------------------

ENV_CANDIDATE=""
if [[ -f "$PROJECT_DIR/.env" ]]; then
  ENV_CANDIDATE="$PROJECT_DIR/.env"
else
  for subdir in "$PROJECT_DIR"/*/; do
    if [[ -d "$subdir/.git" && -f "$subdir/.env" ]]; then
      ENV_CANDIDATE="$subdir/.env"
      break
    fi
  done
fi

if [[ -n "$ENV_CANDIDATE" && -z "${PROJECT_NAME:-}" ]] \
   && grep -qE '^PROJECT_NAME=' "$ENV_CANDIDATE" 2>/dev/null; then
  echo "[sync-framework] NOTICE: Claude was launched WITHOUT sourcing $ENV_CANDIDATE — MCP credentials and git auth (FWADR-030) will NOT bind this session."
  echo "[sync-framework] Fix: exit and relaunch via 'claude-env' (or 'claude-env-yolo' for permission-bypass). Launcher snippet: docs/dev_framework/_stubs/shell/claude-env.zsh (FWADR-032)."
fi

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
# (per FWADR-021).
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
  # Template-only lint: framework ADR namespace discipline (FWADR-028).
  if [[ -x "$PROJECT_DIR/scripts/check-framework-links.sh" ]]; then
    "$PROJECT_DIR/scripts/check-framework-links.sh" \
      || echo "[sync-framework] WARN: framework link check FAILED — fix before committing (FWADR-028)."
  fi
  # Template-only lint: per-role framework load vs caps (FWADR-034).
  if [[ -x "$PROJECT_DIR/scripts/check-doc-weight.sh" ]]; then
    "$PROJECT_DIR/scripts/check-doc-weight.sh" \
      || echo "[sync-framework] WARN: doc weight check FAILED — compact or deliberately re-cap before committing (FWADR-034)."
  fi
  # Template-only lint: no appended-history markers in spec docs (FWADR-036).
  if [[ -x "$PROJECT_DIR/scripts/check-dead-prose.sh" ]]; then
    "$PROJECT_DIR/scripts/check-dead-prose.sh" \
      || echo "[sync-framework] WARN: dead-prose check FAILED — rewrite in place before committing (FWADR-036)."
  fi
  # Template-only lint: the shipped env stub keeps to two comment lines per value.
  if [[ -x "$PROJECT_DIR/docs/dev_framework/_stubs/scripts/check-env-comments.sh" ]]; then
    "$PROJECT_DIR/docs/dev_framework/_stubs/scripts/check-env-comments.sh" \
      "$PROJECT_DIR/docs/dev_framework/_stubs/.env.example" \
      || echo "[sync-framework] WARN: env-comment check FAILED — trim the stub before committing (coding-standards.md)."
  fi
  exit 0
fi

# ---------------------------------------------------------------------------
# 2b. Flat-layout detection.
#     If $PROJECT_DIR contains a .git/ directory, the project is using the
#     legacy flat layout (project dir == git repo). Emit a migration notice
#     and continue — the sync itself is still valid (all sync targets write
#     to $PROJECT_DIR, which is correct for both layouts). See FWADR-021.
# ---------------------------------------------------------------------------

if [[ -d "$PROJECT_DIR/.git" ]]; then
  echo "[sync-framework] NOTICE: flat layout detected — this project's working directory IS the git repository."
  echo "[sync-framework] The canonical framework layout is split: tracking material (CLAUDE.md, docs/, .claude/) lives in a parent directory; the git repo is a named subdirectory."
  echo "[sync-framework] Migration guide: docs/dev_framework/migration-guide-split-layout.md"
  echo "[sync-framework] Sync continuing (flat layout still supported; migration recommended)."
fi

# ---------------------------------------------------------------------------
# 3. Destructive sync of docs/dev_framework/ from template.
#    Per FWADR-014: always destructive. If local framework drifted, pull it
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
# 4b. Install the main-push guard into each code repo's .git/hooks/pre-push.
#     Source of truth is .claude/hooks/git-guard-pre-push.sh (just synced in
#     step 4). Idempotent: installs when missing, refreshes when the template
#     copy changed, and NEVER overwrites an adopter-owned pre-push (a file
#     without the FRAMEWORK-PUSH-GUARD marker) — warns instead.
#     Covers flat layout ($PROJECT_DIR/.git) and split layout (every
#     immediate subdir with .git/, which also covers multi-repo projects).
#     See docs/dev_framework/adrs/fwadr-023-main-push-guard.md.
# ---------------------------------------------------------------------------

GUARD_SRC="$PROJECT_DIR/.claude/hooks/git-guard-pre-push.sh"
GUARD_MARKER="FRAMEWORK-PUSH-GUARD"

install_push_guard() {
  local repo="$1"
  [[ -d "$repo/.git" && -f "$GUARD_SRC" ]] || return 0
  local dst="$repo/.git/hooks/pre-push"
  if [[ -f "$dst" ]] && ! grep -q "$GUARD_MARKER" "$dst" 2>/dev/null; then
    echo "[sync-framework] WARN: $dst exists and is not the framework push guard — main-push guard NOT installed for $(basename "$repo"). Merge the guard's main check into your hook manually (see FWADR-023)."
    return 0
  fi
  if ! cmp -s "$GUARD_SRC" "$dst" 2>/dev/null; then
    mkdir -p "$repo/.git/hooks"
    if cp "$GUARD_SRC" "$dst" 2>/dev/null && chmod +x "$dst" 2>/dev/null; then
      echo "[sync-framework] main-push guard installed: $(basename "$repo")/.git/hooks/pre-push"
    else
      echo "[sync-framework] WARN: failed to install main-push guard into $repo"
    fi
  else
    chmod +x "$dst" 2>/dev/null
  fi
}

install_push_guard "$PROJECT_DIR"
for subdir in "$PROJECT_DIR"/*/; do
  [[ -d "$subdir/.git" ]] && install_push_guard "${subdir%/}"
done

# ---------------------------------------------------------------------------
# 4c. Register the userlog UserPromptSubmit hook in the adopter's
#     .claude/settings.json. The hook SCRIPT (log-user-message.sh) rides
#     step 4's .claude/hooks/ sync; its REGISTRATION does not, because
#     settings.json is adopter-owned and deliberately not synced. Injecting it
#     here — from a hook that already runs on every SessionStart in every
#     adopter — is the only path that reaches EXISTING adopters, not just ones
#     that copy .claude/ fresh. Idempotent (keyed on the script name), never
#     touches permissions or other hooks, validates before replacing.
#     Requires jq; warn + skip if absent.
#     See docs/dev_framework/adrs/fwadr-029-userlog-hook.md.
# ---------------------------------------------------------------------------

USERLOG_SETTINGS="$PROJECT_DIR/.claude/settings.json"
USERLOG_CMD='bash $CLAUDE_PROJECT_DIR/.claude/hooks/log-user-message.sh'

if command -v jq >/dev/null 2>&1; then
  mkdir -p "$PROJECT_DIR/.claude"
  [[ -f "$USERLOG_SETTINGS" ]] || echo '{}' > "$USERLOG_SETTINGS"
  # Inject only if no UserPromptSubmit hook already references the script.
  if ! jq -e '(.hooks.UserPromptSubmit // [])
                | any(.[]?; (.hooks // []) | any(.[]?; (.command // "") | contains("log-user-message.sh")))' \
        "$USERLOG_SETTINGS" >/dev/null 2>&1; then
    ul_tmp="$(mktemp)"
    if jq --arg cmd "$USERLOG_CMD" '
            .hooks = (.hooks // {})
            | .hooks.UserPromptSubmit = (.hooks.UserPromptSubmit // [])
            | .hooks.UserPromptSubmit += [ { "hooks": [ { "type": "command", "command": $cmd, "timeout": 10 } ] } ]
          ' "$USERLOG_SETTINGS" > "$ul_tmp" 2>/dev/null && [[ -s "$ul_tmp" ]]; then
      mv "$ul_tmp" "$USERLOG_SETTINGS"
      echo "[sync-framework] registered userlog UserPromptSubmit hook in .claude/settings.json (FWADR-029)"
    else
      rm -f "$ul_tmp"
      echo "[sync-framework] WARN: failed to register userlog hook in settings.json (FWADR-029)"
    fi
  fi
else
  echo "[sync-framework] WARN: jq not found — userlog hook not registered (FWADR-029); install jq or add the UserPromptSubmit hook to .claude/settings.json manually"
fi

# 4d. Keep userlog.md out of git where the parent tracks one — it records raw
#     user input. Idempotent single-line append; only acts when a .gitignore
#     already exists (never litters an untracked parent).
USERLOG_GI="$PROJECT_DIR/.gitignore"
if [[ -f "$USERLOG_GI" ]] && ! grep -qxF 'userlog.md' "$USERLOG_GI" 2>/dev/null; then
  printf '\n# Local record of user prompts (FWADR-029); never tracked.\nuserlog.md\n' >> "$USERLOG_GI"
  echo "[sync-framework] added userlog.md to .gitignore (FWADR-029)"
fi

# ---------------------------------------------------------------------------
# 4e. Tracked-.env detection (FWADR-033). App runtime secrets never belong in
#     git. The pre-push guard (4b) blocks NEW escapes; this NOTICE covers what
#     prevention can't: a .env committed before the guard existed, or a repo
#     whose adopter-owned pre-push blocked guard installation. Detection only —
#     un-tracking is the human's act.
# ---------------------------------------------------------------------------

check_tracked_env() {
  local repo="$1"
  [[ -d "$repo/.git" ]] || return 0
  local tracked
  tracked="$(git -C "$repo" ls-files 2>/dev/null | grep -E '(^|/)\.env$' | head -5)"
  if [[ -n "$tracked" ]]; then
    echo "[sync-framework] NOTICE: $(basename "$repo") TRACKS a committed .env — app secrets never belong in git (FWADR-033): $(echo "$tracked" | tr '\n' ' ')"
    echo "[sync-framework]   Fix: git rm --cached <path>; add '.env' to .gitignore; commit. Earlier history still holds it — rotate any real secrets."
  fi
}

check_tracked_env "$PROJECT_DIR"
for subdir in "$PROJECT_DIR"/*/; do
  [[ -d "$subdir/.git" ]] && check_tracked_env "${subdir%/}"
done

# ---------------------------------------------------------------------------
# 4f. App-env visibility symlinks (FWADR-033). For each immediate-subdir repo
#     with an app .env, maintain $PROJECT_DIR/.env.<subdir> → <subdir>/.env so
#     all env values are inspectable from the planning directory. Read/edit
#     convenience ONLY — claude-env sources $PWD/.env and nothing else, so the
#     links change what the operator can SEE, never what any process sources.
#     Created when the target exists, re-pointed if wrong, removed when
#     dangling; a regular file squatting the name is warned about, not touched.
# ---------------------------------------------------------------------------

for subdir in "$PROJECT_DIR"/*/; do
  [[ -d "$subdir/.git" ]] || continue
  sub="$(basename "${subdir%/}")"
  link="$PROJECT_DIR/.env.$sub"
  target="$sub/.env"   # relative, so the link survives a parent-dir move
  if [[ -f "${subdir%/}/.env" ]]; then
    if [[ -L "$link" ]]; then
      if [[ "$(readlink "$link")" != "$target" ]]; then
        rm -f "$link" && ln -s "$target" "$link" \
          && echo "[sync-framework] visibility link re-pointed: .env.$sub → $target (FWADR-033)"
      fi
    elif [[ -e "$link" ]]; then
      echo "[sync-framework] WARN: $link exists and is not a symlink — visibility link not created (FWADR-033)"
    else
      ln -s "$target" "$link" \
        && echo "[sync-framework] visibility link created: .env.$sub → $target (FWADR-033)"
    fi
  elif [[ -L "$link" && "$(readlink "$link")" == "$target" ]]; then
    rm -f "$link" \
      && echo "[sync-framework] removed dangling visibility link .env.$sub (FWADR-033)"
  fi
done

# Keep the visibility links (and any local .env variants) out of git where the
# parent tracks one; .env.example stays tracked via the carve-out. Same
# guarded-append pattern as 4d.
if [[ -f "$USERLOG_GI" ]] && ! grep -qxF '.env.*' "$USERLOG_GI" 2>/dev/null; then
  printf '\n# App-env visibility links + local env variants (FWADR-033); never tracked.\n.env.*\n!.env.example\n' >> "$USERLOG_GI"
  echo "[sync-framework] added .env.* (with !.env.example carve-out) to .gitignore (FWADR-033)"
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
# 5c. Project-local stubs (scripts/ + docs/dev/slots.yaml + .env.example).
#     Two kinds, told apart by a marker in the template copy:
#       - FRAMEWORK-OWNED scripts (no project-specific body): overwritten
#         whenever they differ, so framework fixes reach existing adopters.
#         promote_dev_to_main.sh, check-touches.sh, check-researcher-scope.sh,
#         check-curator-scope.sh, doc_churn_audit.sh, port_ledger.sh,
#         setup_dev_slots.sh, spawn_worker.sh, pr_link.sh, check-ditto-stack.sh,
#         check-env-comments.sh, check-ci-placement.sh.
#       - Seed-once stubs (project bodies or project values): copied when
#         missing, never overwritten. launch_local.sh, teardown_local.sh,
#         main_to_prod.sh (FWADR-019), dev_harness.sh (FWADR-037),
#         docs/dev/slots.yaml, and .env.example
#         (the claude-env launcher seeds .env from it; the Strategist owns the
#         values per the first-contact interview).
#     Stubs live under $TEMPLATE_ROOT/docs/dev_framework/_stubs/<relpath> and
#     copy to $PROJECT_DIR/<relpath>, preserving the executable bit (cp -p).
#     Rationale: FWADR-014 §"Stub scripts".
# ---------------------------------------------------------------------------

DEV_SLOT_STUBS=(
  "scripts/launch_local.sh"
  "scripts/teardown_local.sh"
  "scripts/main_to_prod.sh"
  "scripts/setup_dev_slots.sh"
  "scripts/check-touches.sh"
  "scripts/promote_dev_to_main.sh"
  "scripts/check-researcher-scope.sh"
  "scripts/doc_churn_audit.sh"
  "scripts/check-curator-scope.sh"
  "scripts/spawn_worker.sh"
  "scripts/port_ledger.sh"
  "scripts/pr_link.sh"
  "scripts/check-ditto-stack.sh"
  "scripts/check-env-comments.sh"
  "scripts/check-ci-placement.sh"
  "scripts/dev_harness.sh"
  "scripts/paperclip_company.py"
  "docs/dev/slots.yaml"
  ".env.example"
)

# A stub whose template copy carries the FRAMEWORK-OWNED marker has no
# project-specific body: it is overwritten whenever it differs, so fixes reach
# existing adopters. Every other stub (project bodies, slots.yaml,
# .env.example) is seeded once and never touched again. The marker in the file
# itself answers "may I edit this?" for whoever opens it.
OWNED_MARK='FRAMEWORK-OWNED — overwritten on every sync'
for relpath in "${DEV_SLOT_STUBS[@]}"; do
  src="$TEMPLATE_ROOT/docs/dev_framework/_stubs/$relpath"
  dst="$PROJECT_DIR/$relpath"
  [[ -f "$src" ]] || continue
  if [[ ! -f "$dst" ]]; then
    mkdir -p "$(dirname "$dst")"
    if cp -p "$src" "$dst" 2>/dev/null; then
      echo "[sync-framework] initialized $relpath from stub"
    else
      echo "[sync-framework] WARN: failed to initialize $relpath"
    fi
  elif grep -qF "$OWNED_MARK" "$src" && ! cmp -s "$src" "$dst"; then
    if cp -p "$src" "$dst" 2>/dev/null; then
      echo "[sync-framework] updated framework-owned $relpath"
    else
      echo "[sync-framework] WARN: failed to update framework-owned $relpath"
    fi
  fi
done

# ---------------------------------------------------------------------------
# 5d. Tracked parent: keep framework-synced files out of its git (FWADR-014
#     §"Tracked parent"). docs/dev_framework/, the template's hooks, and the
#     framework-owned scripts are rebuilt from the template every session, so
#     tracking them only produces churn. Applies only to a git-tracked parent
#     that holds code repos — never a flat layout (its repo IS the code repo).
#     Maintains one managed block in .gitignore; files already tracked get a
#     NOTICE with the one-time un-track command — never run from here.
# ---------------------------------------------------------------------------

if [[ -d "$PROJECT_DIR/.git" ]] && compgen -G "$PROJECT_DIR/*/.git" >/dev/null; then
  SYNCED=("/docs/dev_framework/")
  for h in "$TEMPLATE_ROOT"/.claude/hooks/*; do
    [[ -f "$h" ]] && SYNCED+=("/.claude/hooks/$(basename "$h")")
  done
  for relpath in "${DEV_SLOT_STUBS[@]}"; do
    src="$TEMPLATE_ROOT/docs/dev_framework/_stubs/$relpath"
    [[ -f "$src" ]] && grep -qF "$OWNED_MARK" "$src" && SYNCED+=("/$relpath")
  done
  GI="$PROJECT_DIR/.gitignore"
  GI_BEGIN="# BEGIN framework-synced (FWADR-014) — rebuilt from the template every session; do not edit"
  GI_END="# END framework-synced"
  want="$(printf '%s\n' "$GI_BEGIN" "${SYNCED[@]}" "$GI_END")"
  have=""
  [[ -f "$GI" ]] && have="$(awk -v b="$GI_BEGIN" -v e="$GI_END" '$0==b{f=1} f{print} $0==e{f=0}' "$GI")"
  if [[ "$have" != "$want" ]]; then
    tmp="$(mktemp)"
    [[ -f "$GI" ]] && awk -v b="$GI_BEGIN" -v e="$GI_END" '$0==b{f=1;next} $0==e{f=0;next} !f' "$GI" > "$tmp"
    { cat "$tmp"; [[ -s "$tmp" ]] && echo; printf '%s\n' "$want"; } > "$GI"
    rm -f "$tmp"
    echo "[sync-framework] refreshed framework-synced block in .gitignore (tracked parent)"
  fi
  tracked="$(git -C "$PROJECT_DIR" ls-files -- "${SYNCED[@]#/}" 2>/dev/null | wc -l | tr -d ' ')"
  if [[ "${tracked:-0}" -gt 0 ]]; then
    echo "[sync-framework] NOTICE: the tracked parent still tracks $tracked framework-synced file(s); they churn on every template change. One-time fix, from $PROJECT_DIR:"
    echo "[sync-framework]   git rm -r --cached -q --ignore-unmatch -- ${SYNCED[*]#/} && git commit -m 'chore: stop tracking framework-synced files (FWADR-014)'"
  fi
fi

# ---------------------------------------------------------------------------
# 5e. CI placement check (FWADR-037). CI runs on the ephemeral runner host and
#     runs only deterministic checks; no datastore starts inside a CI job. For
#     each code repo, run the template's copy of the check (always present,
#     unlike the just-seeded scripts/ copy on a first sync) and NOTICE while
#     the pipeline is unmigrated. Detection only — the Developer fixes the
#     pipeline file; the Reviewer blocks on a diff that fails it.
# ---------------------------------------------------------------------------

CI_CHECK="$TEMPLATE_ROOT/docs/dev_framework/_stubs/scripts/check-ci-placement.sh"
check_ci_placement() {
  local repo="$1" out fails
  [[ -d "$repo/.git" ]] || return 0
  [[ -f "$repo/.gitlab-ci.yml" ]] || compgen -G "$repo/.github/workflows/*.y*ml" >/dev/null || return 0
  out="$("$CI_CHECK" "$repo" 2>/dev/null || true)"
  fails="$(printf '%s\n' "$out" | grep -c '^FAIL:' || true)"
  if [[ "$fails" -gt 0 ]]; then
    echo "[sync-framework] NOTICE: $(basename "$repo") CI is NOT migrated (FWADR-037) — $fails finding(s). CI runs on ephemeral, tags: [docker], no datastore in any job; the real tests run in the post-deploy harness on dev."
    printf '%s\n' "$out" | grep '^FAIL:' | head -3 | sed "s#^FAIL: $repo/#[sync-framework]   #"
    [[ "$fails" -gt 3 ]] && echo "[sync-framework]   … run ./scripts/check-ci-placement.sh $repo for all $fails."
  fi
}

if [[ -x "$CI_CHECK" ]]; then
  check_ci_placement "$PROJECT_DIR"
  for subdir in "$PROJECT_DIR"/*/; do
    [[ -d "$subdir/.git" ]] && check_ci_placement "${subdir%/}"
  done
fi

# ---------------------------------------------------------------------------
# 5f. Paperclip pin check (FWADR-040). A project that runs the framework's roles
#     as Paperclip agents pins them to one framework commit; the template moving
#     past it is drift the project should see. Only when the operator .env names
#     a board (PAPERCLIP_API_URL) and the session was launched with it bound.
#     Detection only — bumping the pin is a deliberate act:
#     ./scripts/paperclip_company.py sync
# ---------------------------------------------------------------------------

PC_CHECK="$TEMPLATE_ROOT/docs/dev_framework/_stubs/scripts/paperclip_company.py"
if [[ -n "${PAPERCLIP_API_URL:-}" && -n "${PAPERCLIP_API_KEY:-}" && -x "$PC_CHECK" ]]; then
  pc_out="$(cd "$PROJECT_DIR" && timeout 20 "$PC_CHECK" status 2>&1 || true)"
  if printf '%s\n' "$pc_out" | grep -q '^DRIFT'; then
    echo "[sync-framework] NOTICE: Paperclip agents are pinned behind the framework (FWADR-040). Bump with ./scripts/paperclip_company.py sync"
    printf '%s\n' "$pc_out" | grep '^DRIFT' | head -3 | sed 's/^/[sync-framework]   /'
  elif ! printf '%s\n' "$pc_out" | grep -q '^aligned'; then
    echo "[sync-framework] NOTICE: Paperclip pin check did not complete: $(printf '%s\n' "$pc_out" | tail -1)"
  fi
fi

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
