#!/usr/bin/env bash
# SessionStart hook: re-orients the session after any context-reset event.
# Fires on source in {startup, resume, compact, clear}. Routes the message.
#
# Wired from .claude/settings.json. See docs/architecture/adr-012-auto-reorient-hook.md.
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
     orchestrator" / "you are a designer" / "you are the developer" / "you are the parallel developer" / "you are the template developer"),
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
     (docs/dev_framework/{strategist,designer,session-policy,developer,template-developer}.md).
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
     (docs/dev_framework/{strategist,designer,session-policy,developer,template-developer}.md)
     depending on which role you are currently operating as.
  2. Re-read CLAUDE.md §"Locked-in decisions" and
     docs/framework_exceptions/dev_framework_exceptions.md for project deviations.
  3. If Orchestrator: reconcile the status ledger per
     docs/dev_framework/templates/orchestrator-bootstrap.md STEP 0.
  4. Acknowledge re-orientation in one line, then continue.
EOF
    ;;
  clear)
    cat <<'EOF'
[session-reorient] Context was cleared. You are starting fresh.

Before acting:
  1. If the user has not declared a role ("you are a strategist" / "you are
     the orchestrator" / "you are a designer" / "you are the developer" / "you are the parallel developer" / "you are the template developer"),
     ask. "Template developer" is only meaningful in the canonical claude_template_yaml
     repo. If the user is changing role from before, state the new role explicitly.
  2. After the role is confirmed: load your role doc
     (docs/dev_framework/{strategist,designer,session-policy,developer,template-developer}.md),
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
