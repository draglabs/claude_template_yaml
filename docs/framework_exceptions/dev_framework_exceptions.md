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

### EX-001 — 2026-05-03 — Ops profile (Cloudron admin repo)

**Scope:** broad — affects `CLAUDE.md` §"What this is" and §"Two process rules" #2 (CI-only deploys); `dev_framework/session-policy.md` (subagent stack, branching semantics, deploy mechanism); `dev_framework/developer.md` (role meaning, code-review gate); `dev_framework/designer.md` (role applicability); `dev_framework/dev-environment.md` (dev slots, `launch_local.sh`, `teardown_local.sh`); `dev_framework/coding-standards.md` (TDD applicability); `dev_framework/template-developer.md` (not applicable here — this is an adopter, not the canonical template repo); `execution-plans/README.md` (W-item field semantics, batch-mode); `scripts/main_to_prod.sh`, `scripts/setup_dev_slots.sh`, `scripts/launch_local.sh`, `scripts/teardown_local.sh` (framework script stubs); ADRs 016 (Integrator-QA), 018 (Developer + Parallel Developer), 019 (dev slots + deploy stubs).

**Project reality:** This repo administers a live Cloudron instance at `my.draglabs.com` (`209.126.80.182`). It contains no `src/` and produces no runtime artifact. "Production" IS the Cloudron server, configured via Cloudron's admin UI, REST API, or `cloudron-cli` — not via `git push`. Changes are operator runbooks and change-log entries committed to this repo, then executed by the user against the live server. The Developer role is reinterpreted as an ops engineer.

**New rule (ops profile):**

1. **Developer role = ops engineer.** Output is runbooks (under `docs/runbooks/<topic>.md`, created on first need) and change-log entries (under `docs/change-log.md`, created on first need), not code under `src/`. The Reviewer subagent, when spawned, reviews runbooks for: completeness, rollback path, idempotency where applicable, alignment with current Cloudron documentation. `coding-standards.md` is loaded by Developer/Reviewer per the framework but most rules are inert (no TDD on runbooks; no production source files to lint).
2. **Runbook-before-action replaces "docs before code."** Production changes happen by the user executing a committed runbook against `my.draglabs.com`. The runbook lands on `dev` (and is reviewed) BEFORE execution. Immediately after execution, a change-log entry is committed recording: timestamp, command(s) run, server response, observed before/after state, validation step. The change-log commit is the mechanical proof of completion.
3. **CI-only-deploys rule (CLAUDE.md §"Two process rules" #2) is suspended.** No CI exists; nothing deploys. `scripts/main_to_prod.sh` stays as a stub permanently — the unimplemented `exit 1` IS the correct steady state and any change to it is itself a framework-relevant event.
4. **Dev-slots system is inert.** `scripts/setup_dev_slots.sh`, `launch_local.sh`, `teardown_local.sh`, and `docs/dev/slots.yaml` remain as stubs. There is no local runtime to launch — Cloudron itself is the runtime, and it is remote-only.
5. **No Designer role.** "you are the Designer" trigger is inert. `mockups/` is not created. Retire this rule individually if a UI surface ever appears in this repo.
6. **W-items adapted.** Items remain the trackable unit. `Touches:` may be `—` or list runbook/change-log paths. `Parallel-safe: false` always (ops actions on a single live server are inherently serial; Orchestrator batch-mode is therefore inert here). Stream-letter convention still used to keep W-ids unique. Acceptance always reduces to "runbook merged + operator action executed against `my.draglabs.com` + change-log entry committed + observable post-state matches expected."
7. **Active role set is narrowed.** In this project the live roles are: Strategist (planning, runbook review at merge boundary, change-log audit) and Developer-as-ops-engineer (authoring runbooks, executing them against the server, committing change-log entries). Reviewer subagent is spawned sparingly on runbook diffs. Orchestrator, Parallel Developer, Integrator-QA, Designer, and Template Developer are NOT invoked.
8. **Branch model is retained but reinterpreted.** `w-<id>/<slug>` → `dev` → `main` still applies. What changes is what `main` means: it is "the canonical, reviewed runbook + change-log set," NOT "what's running in production." Production state lives on the Cloudron server, not in this repo's git history.

**Enforcement:**
- This file is read by every role at Layer 0 (alongside CLAUDE.md), so the profile is in-context at every session start.
- Strategist enforces at the planning boundary by NOT producing W-items that would dispatch Executor code work, and by reviewing runbooks before they merge.
- The four script stubs (`main_to_prod.sh`, `setup_dev_slots.sh`, `launch_local.sh`, `teardown_local.sh`) staying as stubs is the mechanical signal that the deploy / dev-runtime halves of the framework are inert. Any future commit modifying those files is itself a framework event requiring this exception to be revisited.
- Each ops change leaves a paired artifact pair on `main`: a runbook (pre-action) AND a change-log entry (post-action). Strategist audits this pairing at phase boundaries.

**Retire when:**
- The project takes on a code surface (e.g., a custom Cloudron-hosted app developed in-repo). At that point each numbered rule above is re-litigated per surface — some rules (e.g. #5 Designer) retire individually, others (#3 CI deploys) may stay even with code added.
- OR the canonical `claude_template_yaml` absorbs a first-class "ops profile" mode. At that point this entry becomes a one-line "ops profile: enabled" referencing the template's profile spec; escalate via PR against the template repo (Template Developer's territory).

**Budget note:** This single entry exceeds the file's "under 30 lines of active content" target. That's intentional and acknowledged: the budget rule is calibrated for one-off carve-outs, not a categorical profile shift. Consolidating into one EX entry beats fragmenting into 5–8 small ones because retirement is coupled — when an ops profile becomes a template-level feature, the whole entry collapses, not piece-meal.

---

## Retired

### EX-001 — 2026-04-23 → retired 2026-04-23 — Template repo: Strategist may edit framework docs

**Original scope:** carved out an exception letting the Strategist modify `docs/dev_framework/*` when operating in the canonical `claude_template` repo, since that role was serving double duty as framework maintainer.

**Retirement reason:** superseded by the introduction of the [Template Developer](../dev_framework/template-developer.md) role. Framework maintenance is now a first-class role with its own doc, bootstrap trigger, and Layer 1 context — rather than an overloaded Strategist with a documented carve-out. The Strategist role is no longer applicable in the template repo at all (no product to strategize over), so the carve-out it was modifying has nothing left to carve. Tracked in ADR-015.
