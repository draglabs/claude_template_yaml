# Dev framework exceptions (per project)

**This file is the ONLY place for project-level deviations from the template SOP.** All other framework docs (`session-policy.md`, the brief templates, `coding-standards.md`, `context-management.md`, etc.) are canonical — they get copy-pasted over from the template on update and are not edited per-project. If a project needs to deviate, record the deviation here and point at it; do NOT fork the framework.

**Owner:** the project's Strategist. The Strategist adds entries; other agents read them.

**Read at session start by:** every role, as part of Layer 0 (linked from CLAUDE.md). Every agent that loads CLAUDE.md also loads this file. That's a context budget cost; keep it minimal.

## Weight budget

Target: **under 30 lines of active content.** If the active section is growing past that, the project has framework-fit problems — escalate back to the template, not here. More than two or three sustained exceptions in the same category is a signal that the template itself should absorb the pattern (open a PR against the template repo, not this file).

## When to file an exception

- A framework rule actively blocks a project-specific reality that has been explored and can't be worked around without deviating.
- A project-specific tool, environment, or constraint requires a different default (e.g. this project doesn't have a Designer, so the designer.md role never activates).
- A policy has been explicitly suspended for this project with the user's knowledge (e.g. "this project merges feature → main directly; no dev branch").

## When NOT to file

- You disagree with the template. Take it up as a PR against the template.
- One-off frustrations with a brief or tool. File those as `process-exceptions.md` entries instead.
- The framework is silent on something, not prohibiting it. Silence is not a rule — just do the right thing.

## Format

Append new entries to the **Active** section below. Use this shape:

```markdown
### EX-NNN — YYYY-MM-DD — {{short title}}

**Scope:** which framework rule or section is being deviated from (cite file + §).
**Project reality:** the specific project constraint forcing the deviation.
**New rule:** the replacement rule that applies here. Must be as mechanically stated as the rule it replaces.
**Enforcement:** how the deviation is enforced (command, check, brief edit, …). If there's no mechanism, the exception is an English-only rule, which the template doctrine treats as drift bait.
**Retire when:** criteria under which this exception should be deleted (e.g. "when the project adopts a Designer," "when the CI pipeline supports dev-branch deploys").
```

## Retiring an exception

When the underlying project reality changes, move the entry to **Retired** with a dated note on why. Don't delete. The history is worth keeping.

---

## Active

(None.)

---

## Retired

### EX-001 — 2026-04-23 → retired 2026-04-23 — Template repo: Strategist may edit framework docs

**Original scope:** carved out an exception letting the Strategist modify `docs/dev_framework/*` when operating in the canonical `claude_template` repo, since that role was serving double duty as framework maintainer.

**Retirement reason:** superseded by the introduction of the [Template Developer](../dev_framework/template-developer.md) role. Framework maintenance is now a first-class role with its own doc, bootstrap trigger, and Layer 1 context — rather than an overloaded Strategist with a documented carve-out. The Strategist role is no longer applicable in the template repo at all (no product to strategize over), so the carve-out it was modifying has nothing left to carve. Tracked in ADR-015.
