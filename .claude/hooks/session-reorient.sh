#!/usr/bin/env bash
# SessionStart hook: re-orients the session after any context-reset event.
# Fires on source in {startup, resume, compact, clear}. Routes the message.
#
# Wired from .claude/settings.json. See docs/dev_framework/adrs/fwadr-012-auto-reorient-hook.md.
#
# Hook stdout is injected into the post-reset session context.
# Keep the emitted text short and actionable — it lands in every session start.

input="$(cat)"

# Pure-bash source extraction so this hook has no jq/python dependency.
if [[ $input =~ \"source\"[[:space:]]*:[[:space:]]*\"([^\"]+)\" ]]; then
  source_value="${BASH_REMATCH[1]}"
else
  source_value="unknown"
fi

case "$source_value" in
  startup)
    cat <<'EOF'
[session-reorient] New session started.

Before substantive action:
  1. Confirm which role you are operating as. See CLAUDE.md §Roles. If the
     user has not declared a role ("you are a strategist" / "you are the
     orchestrator" / "you are a designer" / "you are the developer" / "you are the parallel developer" / "you are the researcher" / "you are the curator" / "you are the template developer"),
     ask. Note: "template developer" is only meaningful in the canonical
     claude_template_yaml repo.
  2. After the role is confirmed, load your role's Layer 1 docs per
     docs/dev_framework/context-management.md. Premature loading wastes
     context budget.
  3. Check docs/framework_exceptions/dev_framework_exceptions.md for any project
     deviations from the template SOP.
EOF
    ;;
  resume)
    cat <<'EOF'
[session-reorient] Session resumed.

Before continuing:
  1. Re-confirm your role and re-read your role doc
     (docs/dev_framework/{strategist,designer,session-policy,developer,researcher,curator,template-developer}.md).
  2. Re-read CLAUDE.md §"Locked-in decisions" and
     docs/framework_exceptions/dev_framework_exceptions.md.
  3. If Orchestrator: reconcile the status ledger per
     docs/dev_framework/templates/orchestrator-bootstrap.md STEP 0 before
     dispatching anything new.
  4. Acknowledge re-orientation in one line, then continue.
EOF
    ;;
  compact)
    cat <<'EOF'
[session-reorient] Context was compacted — earlier doc context may have been
dropped. Re-orient before your next substantive action:

  1. Re-read your role doc
     (docs/dev_framework/{strategist,designer,session-policy,developer,researcher,curator,template-developer}.md)
     depending on which role you are currently operating as.
  2. Re-read CLAUDE.md §"Locked-in decisions" and
     docs/framework_exceptions/dev_framework_exceptions.md for project deviations.
  3. If Developer: read your active W-item's working log file
     (docs/execution-plans/<plan>/w-<id>.log.md) to recover phase + working
     context. The latest timestamped header names the current phase
     (Build / QA / Code Review). If unclear, ask the user. Re-read the
     matching subsection of developer.md §"Phase discipline" — that is
     the discipline target for this phase, not the whole role doc.
  4. If Orchestrator: reconcile the status ledger per
     docs/dev_framework/templates/orchestrator-bootstrap.md STEP 0.
  5. Acknowledge re-orientation in one line, then continue.
EOF
    ;;
  clear)
    cat <<'EOF'
[session-reorient] Context was cleared. You are starting fresh.

Before acting:
  1. If the user has not declared a role ("you are a strategist" / "you are
     the orchestrator" / "you are a designer" / "you are the developer" / "you are the parallel developer" / "you are the researcher" / "you are the curator" / "you are the template developer"),
     ask. "Template developer" is only meaningful in the canonical claude_template_yaml
     repo. If the user is changing role from before, state the new role explicitly.
  2. After the role is confirmed: load your role doc
     (docs/dev_framework/{strategist,designer,session-policy,developer,researcher,curator,template-developer}.md),
     CLAUDE.md §"Locked-in decisions", and
     docs/framework_exceptions/dev_framework_exceptions.md.
  3. If Orchestrator: reconcile the status ledger per
     docs/dev_framework/templates/orchestrator-bootstrap.md STEP 0 before
     dispatching anything.
EOF
    ;;
  *)
    cat <<'EOF'
[session-reorient] SessionStart fired (source unknown).

Re-read CLAUDE.md and your role doc before continuing. See CLAUDE.md §Roles
if you are unsure which role you are operating as.
EOF
    ;;
esac

# Filesystem scope boundary — emitted for EVERY session-start source.
# Counters the newer-model instinct to fan out across the surrounding code
# directory on the first action. See CLAUDE.md §"Project layout".
cat <<'EOF'

[session-reorient] Filesystem scope — stay inside this project.
  - Confine your own exploration to the project dir (PWD / $PROJECT_DIR) and,
    under split layout, its code repo ($CODE_ROOT = $PROJECT_DIR/$CODE_SUBDIR).
  - Do NOT range into sibling projects, ancestor dirs, or unrelated trees in
    the surrounding code directory on your own initiative.
  - Crawling up the filetree or reading outside directories is opt-in — do it
    only when the user explicitly asks. (Harness CLAUDE.md auto-discovery is a
    separate mechanism and is unaffected; this governs your own actions.)
EOF

# Named-deliverable re-anchor — emitted for EVERY session-start source.
# A context reset reloads role doctrine at full strength while the user's actual
# request may be gone; the doctrine then wins and the agent writes the nearest
# artifact its role already owns. Phrased so a lost request produces a QUESTION,
# not a silent substitution. See FWADR-025 and strategist.md §"Named deliverables".
cat <<'EOF'

[session-reorient] Named deliverables — write what was asked for.
  - Before your next write, name the artifact the user asked for and where it
    goes. If you cannot name both from current context, ASK — do not infer it
    from the plan, the ledger, or open work items.
  - If the user named an artifact, a document type, or a location, that named
    artifact IS the deliverable. Producing an adjacent one instead — a W-item,
    a plan edit, a note on an existing doc — is a substitution, and substitution
    needs the user's agreement BEFORE it happens, not a report afterward.
  - Doctrine you just re-read is context, not a task list. Re-reading your role
    doc does not convert pending work items into the current request.
  - Missing a value the deliverable needs? A missing ADR or plan entry is a
    QUESTION FOR THE USER, not work to create. Ask for the value; do not file
    tickets to define it first. Pausing a requested deliverable to do upstream
    work needs the user's explicit agreement — it turns one doc into a phase.
EOF

# Code-repo staleness check — runs for EVERY session-start source (FWADR-012
# Revision v1.1). CI and auto-promotion keep origin moving while local
# checkouts sit idle; a stale tree is misleading exactly when it looks normal
# (field case: an audit session reasoned from a checkout 87 commits behind
# origin and produced false conclusions). Quietly fetch each repo's origin,
# then NOTICE when local dev/main trail their remotes. Soft-fail throughout:
# a failed fetch reports "staleness UNKNOWN" (never blocks session start), and
# GIT_TERMINAL_PROMPT=0 + http.lowSpeed* keep a dead network from hanging the
# hook on a credential prompt or stalled transfer.

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(pwd)}"

check_repo_staleness() {
  local repo="$1" name branch behind
  name="$(basename "$repo")"
  [[ -d "$repo/.git" ]] || return 0
  git -C "$repo" remote get-url origin >/dev/null 2>&1 || return 0
  if ! GIT_TERMINAL_PROMPT=0 git -C "$repo" \
       -c http.lowSpeedLimit=1 -c http.lowSpeedTime=10 \
       fetch --quiet --no-tags origin 2>/dev/null; then
    echo "  - $name: could not fetch origin (offline or unauthenticated) — staleness UNKNOWN; do not trust local branch freshness."
    return 0
  fi
  for branch in dev main; do
    git -C "$repo" rev-parse --verify -q "refs/heads/$branch" >/dev/null || continue
    git -C "$repo" rev-parse --verify -q "refs/remotes/origin/$branch" >/dev/null || continue
    behind="$(git -C "$repo" rev-list --count "refs/heads/$branch..refs/remotes/origin/$branch" 2>/dev/null)"
    if [[ -n "$behind" && "$behind" -gt 0 ]]; then
      echo "  - $name: local $branch is $behind commit(s) behind origin/$branch — fetch/pull before reasoning from this tree."
    fi
  done
}

STALENESS="$(
  check_repo_staleness "$PROJECT_DIR"
  for subdir in "$PROJECT_DIR"/*/; do
    [[ -d "$subdir/.git" ]] && check_repo_staleness "${subdir%/}"
  done
)"

if [[ -n "$STALENESS" ]]; then
  cat <<EOF

[session-reorient] Code-repo staleness NOTICE (origin fetched just now):
$STALENESS
EOF
fi
