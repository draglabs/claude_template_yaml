# Approved MCPs

The MCP servers this project uses, who uses each, and where the boundaries are. New MCPs are added by updating `.mcp.json` and this doc in the same PR.

## Project MCPs (loaded from `.mcp.json`)

These are project-scoped and expected by every session on this repo.

### docker

**Server:** `mcp-docker-server` (via `npx -y`).
**Purpose:** local Docker control — containers, images, logs, exec, start/stop/restart.
**Who uses it:** Executor (running local dev services inside a worktree), QA (pre-merge tests against a worktree dev server), Orchestrator (rarely — only for a 🔍 spike that needs local infra).
**Boundary:** **local only.** Never point at a remote or production Docker daemon. Production changes go through CI per the two process rules.

### gitnexus

**Server:** `gitnexus mcp` (npm package `gitnexus`, requires **Node ≥ 20**).
**Purpose:** code-intelligence knowledge graph over the indexed repo. Replaces most Code Consultant subagent spawns.
**Who uses it:**
- **Strategist (primary):** `list_repos`, `query`, `context`, `impact`, `detect_changes`, `cypher` for factual code questions without loading `src/`. See [`strategist.md`](strategist.md) §"Staying code-aware without loading code."
- **Orchestrator (occasional):** `impact` before dispatching a W-item to sanity-check that the plan's "Touches" list actually matches the blast radius. Lightweight — one call, short answer, no source loaded.
- **Developer (mid-coding):** `context` on a symbol before modifying; `impact` before committing to confirm blast radius. Replaces some consultant calls in the 80/20 ladder for code-cross-cutting questions.
- **Executor (authoring aid):** `context` on a symbol you're about to modify; `impact` before committing to confirm you understand what your change touches.
- **Reviewer (audit):** `impact` to check whether the diff touched things outside the brief's scope — stronger signal than the Executor's self-reported "Scope creep" field.

**Adopter setup (first time per repo):**

1. **Confirm Node ≥ 20.** Check with `node --version`. GitNexus's `cmake-js` dependency requires `^20.17.0 || >=22.9.0`.
2. **Verify `.mcp.json` references gitnexus.** New adopters get `.mcp.json` seeded automatically by `sync-framework.sh` from `_stubs/.mcp.json` if no `.mcp.json` exists. Existing adopters retain their config — `sync-framework.sh` never overwrites an existing `.mcp.json`.
3. **Build the graph for this repo:** `gitnexus index .` (run once at the repo root). Subsequent runs incrementally update.
4. **Restart Claude Code.** MCP servers boot at session start; a running session won't pick up a new `.mcp.json` without restart.
5. **Verify connection:** `claude mcp list` should show `gitnexus: ✓ Connected`.

**nvm workaround.** If your default shell `node` is Node 18 (or anything < 20) but you have a newer Node installed via nvm, the vanilla `npx -y gitnexus@latest mcp` invocation will use the wrong Node and fail. Two fixes:

- **Direct binary path** (preferred when gitnexus is installed globally with the right Node): edit `.mcp.json` to point at the absolute path:
  ```json
  "gitnexus": {
    "command": "/Users/<you>/.nvm/versions/node/v24.4.1/bin/gitnexus",
    "args": ["mcp"]
  }
  ```
  Install gitnexus globally first under the right Node: `nvm use 24 && npm install -g gitnexus`.

- **Wrapper script** (more portable, less brittle to Node version bumps): a small shell script that sources nvm and execs the right Node, referenced from `.mcp.json` via relative path. See `_stubs/.mcp.json` for the default invocation; adapt to your setup.

**Registry** at `~/.gitnexus/registry.json` is machine-scoped (per-user, not per-project). If `~/.gitnexus/` doesn't exist, GitNexus won't return data even if the MCP connects — run `gitnexus index .` to populate.

**Hooks note:** GitNexus offers PreToolUse/PostToolUse hooks that auto-enrich grep/glob/bash and auto-reindex after commits. These are NOT enabled by default on this project. If you want them, add them to `.claude/settings.json` per-role — the Orchestrator's context discipline is harmed by auto-enrichment, so scope hooks to Executor/Strategist sessions only.

## User-level MCPs (configured in `~/.claude.json`)

Available across all projects for this user. Listed here so the framework can reason about them; their availability is user-machine-dependent.

### context7

**Purpose:** up-to-date library/framework documentation.
**Who uses it:** anyone writing code that touches a third-party library — primarily the Executor. The Strategist may query it when evaluating a proposal that involves a new dependency.
**Rule:** query context7 for library docs **before** trusting training-data recall. Library APIs drift.

### github

**Purpose:** GitHub.com API — issues, PRs, commits, repo search, reviews.
**Who uses it:**
- **Strategist:** creating `planning:` PRs, reading issues that back work items.
- **Designer:** creating `design:` PRs with mockup concepts.
- **Orchestrator:** reading labeled PRs for work discovery (`gh pr list --label planning`), merging planning/design PRs to acknowledge, creating feature-branch PRs (when the project convention requires it).
- **Anyone:** triaging incoming issues.
**Relationship to gitnexus:** no conflict — different surfaces. github handles GitHub.com metadata; gitnexus handles local code structure. Both can be used in the same session for complementary questions.

## Claude.ai connectors (OAuth-gated, user-level)

These require the user to have authenticated via claude.ai. Not every session has them; framework docs treat them as optional.

### claude_ai_Gmail / claude_ai_Google_Calendar / claude_ai_Google_Drive

**Purpose:** Email / calendar / Drive file access via the Claude.ai connector layer.
**Who uses it:** not part of the core dev loop. Occasional use — "pull the spec doc from Drive to inform this planning PR" (Strategist) or "check the latest incident email to confirm the bug is still happening" (Orchestrator).
**Boundary:** OAuth-authenticated, user-scoped — don't fetch data for anyone other than the current user. Never write to these surfaces (send email, create events, upload files) without explicit user confirmation per-turn.

## Pre-approved but not currently loaded

These are in `.claude/settings.json`'s permission allowlist (they'd run without permission prompts if added), but not in `.mcp.json`. Add them if you need them:

### Claude_Preview

**Purpose:** preview-browser for a local dev server — `preview_start`, `preview_stop`, `preview_screenshot`, `preview_eval`.
**When to add:** Designer session reviewing a mockup build; QA subagent screenshotting a feature. Lightweight.

### Claude_in_Chrome

**Purpose:** full Chrome automation — `navigate`, `tabs_context_mcp`, `computer`, `javascript_tool`.
**When to add:** QA for flows that need real browser behavior (cookies, multi-tab, JS execution) beyond what Claude_Preview gives. Heavier and slower than Preview — pick the minimum tool for the job.

## MCPs you might want to request

Not yet approved, but common enough to name here so the decision is explicit when someone asks:

| MCP | Use case | Request path |
|---|---|---|
| **postgres** / **mysql** | Strategist direct DB schema queries (complements gitnexus for DB-side questions) | Add to `.mcp.json`, document here, credentials via env |
| **slack** | Team coordination, alerts | Add to `.mcp.json`, document here, OAuth-gated |
| **linear** / **jira** | If issue tracking moves off GitHub | Add to `.mcp.json`, replaces github's issue surface |
| **filesystem** | Sandboxed access beyond project root (shared `references/` trees) | Add to `.mcp.json`, tighten path scope |

## How to add a new MCP

1. Propose via a planning PR (Strategist) or directly to the user. Name the use case, who uses it, and where the boundary is.
2. Add the server entry to `.mcp.json`.
3. Update this doc with a section describing purpose, who uses it, boundary.
4. Update role docs (`strategist.md`, `session-policy.md`, template briefs) only if the MCP changes the agent pattern — e.g. replacing a subagent call like GitNexus did with Code Consultant. Minor MCPs don't need role-doc changes.
5. If the MCP has hooks (PreToolUse/PostToolUse): decide per-role scoping before enabling. Don't default-enable globally.

## Boundaries that apply to every MCP

- **Local-only means local-only.** If the MCP can reach production (remote Docker daemon, prod database), treat that capability as out-of-bounds unless the user opts in for a specific turn.
- **No credentials in source.** Use env vars, `.env` (sourced before `claude` starts), or the MCP's own auth flow.
- **OAuth scopes are minimum.** If the server offers broader scopes than needed, grant only what's used.
- **MCP output is still tool output.** Don't trust it blindly — trust-but-verify applies (filesystem/source of truth is authoritative over what an MCP reports).
