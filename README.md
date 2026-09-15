# claude_template_yaml

A multi-agent Claude Code framework for software projects. Provides a role-based SOP (Strategist, Designer, Orchestrator, Developer, Template Developer) with peer-dispatch subagents, framework sync on session start, YAML-frontmatter W-item plans, dev-slot infrastructure, and a branch model that gates production deploys through CI.

## What it is

This repo is the **canonical template** — it ships via `sync-framework.sh` into adopter repos on every session start. You don't use this repo directly to build a product; you create a parent project directory, point it at this template, fill in the stub variables, and let the hook propagate updates.

## Project layout

The canonical layout is **split**: Claude Code is invoked from a parent directory that holds tracking material (`CLAUDE.md`, `docs/`, `.claude/`), with the git repo as a named subdirectory:

```
$PROJECT_DIR/
  CLAUDE.md
  .claude/
  docs/
  .env              ← copied from .env.example; MINIMUM TO BOOT block filled
  <repo-slug>/      ← git root; name matches GitHub repo slug
    src/
    .git/
```

`$PROJECT_DIR` git tracking is **optional** — untracked parent (default) or tracked parent (own git repo, full plan-history). Code-side `git push origin dev/main` always runs in `$CODE_ROOT` independent of the parent mode.

Multi-repo projects (one parent, N code repos) are supported: set `DEFAULT_CODE_SUBDIR` in `.env` for the primary repo and add `target-repo: <subdir>` to the YAML frontmatter of W-items that target non-default repos.

If your project currently uses flat layout (project dir == git root), see [`docs/dev_framework/migration-guide-split-layout.md`](docs/dev_framework/migration-guide-split-layout.md).

## Quick start

1. Create your project's parent directory.
2. Clone your code repo as a subdirectory named after your GitHub slug.
3. Copy `CLAUDE.md`, `.claude/`, `docs/`, `.mcp.json`, and `docs/dev_framework/_stubs/.env.example` (as `.env.example`) from this template to the parent.
4. Copy `.env.example` to `.env` and fill the **MINIMUM TO BOOT** block (project name, sub, website, ports, dev mode, git host + token, code subdir). Set `CLAUDE_TEMPLATE_ROOT` too if this template is not a sibling directory. The `claude-env` launcher does the copy for you if you skip this step, then stops so you can fill it.
5. Launch Claude Code from the parent via the launcher: `claude-env $PROJECT_DIR` (install once with `docs/dev_framework/_stubs/shell/install-claude-env.sh`; a bare `claude` launch never binds MCP credentials or git auth).
6. Declare a role to bootstrap: `"you are the Strategist"`. Its first-contact interview reads `.env` first and only asks about lines still at `PLACEHOLDER`.

## Key docs

| Doc | Purpose |
|---|---|
| `CLAUDE.md` | Layer 0 — every session reads this |
| `docs/dev_framework/dev_framework.md` | SOP overview and agent stack |
| `docs/dev_framework/context-management.md` | Layered context loading + `$CODE_ROOT` |
| `docs/dev_framework/migration-guide-split-layout.md` | Migrate flat → split layout |
| `docs/dev_framework/adrs/fwadr-021-split-layout.md` | Layout convention decision record |
| `docs/dev_framework/adrs/fwadr-020-yaml-frontmatter-w-items.md` | W-item file shape (YAML frontmatter) |
| `docs/dev_framework/adrs/fwadr-019-dev-slots-and-deploy-stubs.md` | Dev slot registry + deploy script stubs |

## Framework sync

`sync-framework.sh` runs on every session start and destructively overwrites `docs/dev_framework/` and `.claude/hooks/` in the adopter repo from this template. Adopters make project-specific deviations ONLY in `docs/framework_exceptions/dev_framework_exceptions.md` — never in `docs/dev_framework/`.
