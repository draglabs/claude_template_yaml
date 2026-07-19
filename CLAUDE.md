# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

**{{project_name}}** — {{one-line description}}.

**Live at:** `{{sub}}.{{website}}.com` | **Dev at:** `{{sub}}.dev.{{website}}.com` | **Status:** {{current phase/status summary}}

Project variables (fill these in, used across docs and QA briefs):
- `{{sub}}` — this project's subdomain (e.g. `myapp`)
- `{{website}}` — shared parent domain (e.g. `draglabs.com`)
- `{{ports}}` — local port range allocated to this project (e.g. `3050-3060` or `305*`); local dev runtimes (Docker, native dev server, reverse proxy) bind within this range. See [`docs/dev_framework/dev-environment.md`](docs/dev_framework/dev-environment.md) §"Port allocation (local-hosted)".

<!-- BEGIN FRAMEWORK MANAGED -->
<!--
  Everything between the FRAMEWORK MANAGED markers is overwritten on
  every SessionStart by .claude/hooks/sync-framework.sh, which copies
  this block verbatim from the template's CLAUDE.md. Do NOT edit here;
  project-specific content belongs OUTSIDE these markers. If you need to
  deviate from framework-managed content, record the deviation in
  docs/framework_exceptions/dev_framework_exceptions.md. See ADR-014.
-->

## Roles (bootstrap trigger)

**When the user types "you are a {role}" (or "you are the {role}"), you ARE that role.** Read the docs listed in your row below, follow your role doc's bootstrap steps, and report back with your understanding + confidence. Wait for user approval before doing substantive work.

Every role also reads this file (CLAUDE.md) as Layer 0 — the always-loaded baseline. Deeper material loads by role (Layer 1) or on demand (Layer 2). Full layering rules in [`docs/dev_framework/context-management.md`](docs/dev_framework/context-management.md).

| Say | Role | Reads on bootstrap |
|---|---|---|
| "you are the Strategist" | Strategist | [`docs/dev_framework/strategist.md`](docs/dev_framework/strategist.md) + [`dev_framework_exceptions.md`](docs/framework_exceptions/dev_framework_exceptions.md) + planning docs (plan, roadmap, future-directions). Does NOT load project `src/` |
| "you are the Designer" | Designer | [`docs/dev_framework/designer.md`](docs/dev_framework/designer.md) + [`dev_framework_exceptions.md`](docs/framework_exceptions/dev_framework_exceptions.md) + main app UI components (read for reference) |
| "you are the Orchestrator" | Orchestrator | [`docs/dev_framework/session-policy.md`](docs/dev_framework/session-policy.md) + [`dev_framework_exceptions.md`](docs/framework_exceptions/dev_framework_exceptions.md) + active plan from [`docs/execution-plans/`](docs/execution-plans/). Does NOT load `coding-standards.md` or project `src/` |
| "you are the Developer" | Developer (Default) | [`docs/dev_framework/developer.md`](docs/dev_framework/developer.md) + [`docs/dev_framework/coding-standards.md`](docs/dev_framework/coding-standards.md) + [`dev_framework_exceptions.md`](docs/framework_exceptions/dev_framework_exceptions.md) + active plan's `plan.md`. Hands-on coding in your main checkout on a feature branch (`w-<id>/<slug>`). Bootstrap proposes top critical-path `pending` item. User-mediated QA loop + spawned Reviewer subagent for code review ([ADR-018](docs/architecture/adr-018-developer-role.md)). Mixed-mode phases allowed. |
| "you are the parallel developer" | Developer (Parallel) | Same role doc + Layer 1 reads as Default. Works in a **worktree** at `/tmp/worktrees/<project>/w-<id>-<slug>` instead of the main checkout. Bootstrap does the **non-competing scan** (avoids items that overlap with already-claimed work). Use when running alongside the Default Developer for coding-throughput parallelism. Same lifecycle, same Reviewer-subagent code-review gate. |
| "you are the Template Developer" | Template Developer | [`docs/dev_framework/template-developer.md`](docs/dev_framework/template-developer.md) + [`docs/dev_framework/dev_framework.md`](docs/dev_framework/dev_framework.md) + [`dev_framework_exceptions.md`](docs/framework_exceptions/dev_framework_exceptions.md). **Only meaningful in the canonical `claude_template_yaml` repo** — adopter-repo framework changes go via PR against the template, not this role. |

**SOP overview:** [`docs/dev_framework/dev_framework.md`](docs/dev_framework/dev_framework.md) — read this if you're not sure which role you are, or you need the big picture (subagent stack, PR-based handoff, context layering).

**Project deviations from the SOP:** [`docs/framework_exceptions/dev_framework_exceptions.md`](docs/framework_exceptions/dev_framework_exceptions.md) — per-project overrides maintained by the Strategist. Every role loads this alongside CLAUDE.md at session start. The framework docs themselves are canonical and are not edited per-project; deviations go in the exceptions file, not into the framework.

## Two process rules (every session)

1. **Docs before code.** Architectural additions get documented by the Strategist and merged before the Orchestrator dispatches implementation. Enforced at the merge boundary by the Reviewer (`block` if no matching doc) and at the phase boundary by the Strategist's alignment audit.
2. **CI-only deploys to production.** Production changes land via `git push origin main` → CI. Never from a laptop. Never via `docker exec`. Dev environment behavior depends on mode — see [`docs/dev_framework/dev-environment.md`](docs/dev_framework/dev-environment.md). **Direct-deploy escape hatch:** projects that have user-approved direct-to-server deploy use [`scripts/main_to_prod.sh`](scripts/main_to_prod.sh) as the canonical entry point — never improvise prod commands outside it. See [ADR-019](docs/architecture/adr-019-dev-slots-and-deploy-stubs.md). Most projects keep this script as a stub (the unimplemented `exit 1` state IS the correct steady state for CI-deployed projects).

## Presenting options

When you present more than one option to the user, give each a **Confidence** (0–100%, same scale as the 80/20 ladder in `docs/dev_framework/developer.md` §"Confidence-driven escalation") and a **Difficulty** score (1 / 2 / 3 / 5 / 8 fibonacci-ish points; 1 = trivial, 8 = hard). End with a one-line recommendation naming the option and the reason. Format as a table for ≥2 options.

Example:

| Option | Conf | Diff | What it is |
|---|---|---|---|
| **A** | 75% | 5 | Use existing FooStore pattern; matches the rest of the codebase |
| **B** | 65% | 3 | Add a thin BarStore subclass; smaller diff, slight inconsistency |
| **C** | 55% | 2 | Inline the logic where it's used; cheapest now, drift risk later |

Recommend **A** — codebase consistency wins despite the size.

When the rule does NOT apply: yes/no confirmations, tool-use approvals, choices the user has already constrained.

Bias-correction:
- Confidence is self-rated. If you'd default to "this is obviously right," double-check; same false-high mode as the 80/20 ladder.
- If you frame the choice as "right way vs hack," you're probably missing a middle. Pause and look for one before presenting — binary forks are usually unimagined alternatives. Some are genuinely two-way; most aren't.

## Branch model

Feature branches merge to **`dev`**, dev promotes to **`main`** at phase boundaries. Full flow in [`docs/dev_framework/session-policy.md`](docs/dev_framework/session-policy.md) §"Branching and isolation" and [`docs/dev_framework/dev-environment.md`](docs/dev_framework/dev-environment.md).

Code-level rules (TDD, no hardcoded lifecycle values, fail loudly) live in [`docs/dev_framework/coding-standards.md`](docs/dev_framework/coding-standards.md) and are enforced by the Executor (writing) and Reviewer (checking) subagent briefs. The Orchestrator and Strategist do NOT load that doc — they delegate enforcement to the subagent layer.

## Project layout

**Canonical layout: split** ([ADR-021](docs/architecture/adr-021-split-layout.md)). Claude Code is invoked from a parent directory (`$PROJECT_DIR`) that holds tracking material (`CLAUDE.md`, `docs/`, `.claude/`, `.mcp.json`). The git repo lives at `$PROJECT_DIR/$CODE_SUBDIR`. `$CODE_ROOT = $PROJECT_DIR/$CODE_SUBDIR`.

Set `DEFAULT_CODE_SUBDIR=<repo-slug>` in `$PROJECT_DIR/.env`. For multi-repo projects, W-item files set `target-repo: <subdir>` in their YAML frontmatter (per [ADR-020](docs/architecture/adr-020-yaml-frontmatter-w-items.md)) to override the default.

**`$PROJECT_DIR` git tracking is optional.** Two sanctioned modes ([ADR-021](docs/architecture/adr-021-split-layout.md) §"`$PROJECT_DIR` git tracking: optional"): *untracked parent* (default, simpler — plan-write visibility via shared filesystem only) or *tracked parent* (optional — `$PROJECT_DIR` is its own git repo for full PLAN-WRITE DISCIPLINE concurrent-claim safety + durable plan history). Code-side `git push origin dev/main` always operates on `$CODE_ROOT`, independent of which parent mode.

**Exploration scope — stay inside the project.** Confine your own file exploration to `$PROJECT_DIR` and `$CODE_ROOT` (its code repo). Do not range into sibling projects, ancestor directories, or other trees in the surrounding code directory on your own initiative — crawling up the filetree or reading outside directories is opt-in, done only when the user explicitly asks for it. This governs *your* exploration actions; the harness's automatic `CLAUDE.md` ancestor-discovery is a separate mechanism and is unaffected.

Flat layout (project dir == git root) is legacy. Session-start sync emits a migration NOTICE if detected. See [`docs/dev_framework/migration-guide-split-layout.md`](docs/dev_framework/migration-guide-split-layout.md).

## Framework sync on SessionStart

On every session start (fresh, resume, `/clear`, `/compact`), two hooks run in order:

1. `.claude/hooks/sync-framework.sh` — destructively syncs `docs/dev_framework/` and `.claude/hooks/` from the canonical `claude_template_yaml` repo, initializes `docs/framework_exceptions/` if missing, and refreshes this managed block. Adopters are expected to make changes ONLY in `docs/framework_exceptions/*`, never in `docs/dev_framework/*`. See [ADR-014](docs/architecture/adr-014-framework-sync-on-session-start.md).
2. `.claude/hooks/session-reorient.sh` — injects a role re-orientation reminder tailored to the `source` of the reset. See [ADR-012](docs/architecture/adr-012-auto-reorient-hook.md).

The template root is resolved via `$PROJECT_DIR/.env` `CLAUDE_TEMPLATE_ROOT=` line → immediate-subdir `.env` files (split-layout adopters whose `.env` lives in the code repo) → `../claude_template_yaml` → `../../claude_template_yaml` → `../../../claude_template_yaml`, in that order. Shell environment variables are intentionally not consulted (a stale export pointing at a defunct location would silently misroute the sync). If none resolve, sync is skipped with a warning.

## MCP (.mcp.json)

Claude Code expands env vars from its **own process env**, not `.env`. Export before starting:

```bash
set -a; source .env; set +a    # then run claude
```

Docker MCP is local-only. Never point it at production. Treat MCP servers the same as any other runtime component — adding one counts as an architectural addition (see "Docs before code" above).

## Live references

Query **Context7** (MCP) for library/framework docs before using training data. Clone external reference repos into `references/` — see [`references/README.md`](references/README.md).

<!-- END FRAMEWORK MANAGED -->

## Dev environment mode (project choice)

**Dev environment mode for this project:** `{{local-hosted | remote-hosted}}` — fill in after the first Strategist interview resolves `adr-011-dev-environment.md`.

## Commands

```bash
{{adapt to your project}}
npm install              # dependencies
npm run dev              # dev server
npm run build            # production build
npm run typecheck        # type check (CI gate)
npm test                 # test suite (CI gate)
./scripts/check-consistency.sh  # hardcode/drift check (CI gate)

# Dev slots (ADR-019) — one-time setup, then launch/teardown by slot name.
# Run these from $PROJECT_DIR (parent), not from $CODE_ROOT — scripts live at
# the parent under split layout per ADR-021 §"Script placement doctrine" and use
# CWD-relative paths internally.
./scripts/setup_dev_slots.sh             # one-time: pick base port + write Caddyfile block
./scripts/launch_local.sh <slot>         # bring up a local runtime in a slot (e.g. dev0)
./scripts/teardown_local.sh <slot>       # release a slot

# Production deploy (also from $PROJECT_DIR):
./scripts/main_to_prod.sh                # NAMED ESCAPE HATCH for user-approved direct-deploy
                                         # (most projects: keep as stub; CI-only is the default)
```

## Stack

**Status: undecided (stub).** See [`docs/architecture/stack.md`](docs/architecture/stack.md) for the decision matrix the Strategist walks through on first contact. Each row becomes an ADR in [`docs/architecture/`](docs/architecture/).

## Locked-in decisions

No decisions locked yet — project is in stub state. See [`docs/architecture/adr-000-starter-stub.md`](docs/architecture/adr-000-starter-stub.md) for why.

As ADRs accept, add a one-line summary here with a link to the ADR. Example:
```
- Postgres 16 over MySQL — [ADR-004](docs/architecture/adr-004-database-prod.md)
```

## Consistency checks

`scripts/check-consistency.sh` runs in CI and catches bare IPs, silent env fallbacks, hardcoded localhost URLs, and hardcoded container names in source code. Add project-specific patterns in the CUSTOM CHECKS section of the script.
