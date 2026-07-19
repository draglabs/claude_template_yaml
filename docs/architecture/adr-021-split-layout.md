# ADR-021 — Split project layout as canonical convention

**Date:** 2026-05-21
**Status:** Accepted
**Authors:** Template Developer / David Strom

---

## Context

Every framework doc and hook has been written with the implicit assumption that the directory Claude Code is invoked from **is** the git repository. The two trees are the same tree.

Two independent pressures break that assumption:

1. **Ignoring docs in the code repo.** A real adopter (`auto-jm-co`) had a CTO directive to gitignore all `*.md` files repo-wide. With framework docs, planning docs, and ADRs all untracked, keeping them inside the git repo was vestigial — a build artifact of how the template was originally structured, not a useful constraint.

2. **Multi-repo projects.** In practice, a single product spans multiple git repos (e.g., `api/`, `web/`, `infra/`). Claude Code is invoked once from a parent directory that holds shared tracking material, and each code repo is a subdirectory. The single-tree assumption makes this pattern awkward to express.

The solution that resolved both problems in practice (and is in production at `auto-jumpermedia-co`): a **split layout** where the directory Claude Code is invoked from (`$PROJECT_DIR`) holds only tracking material, and the git repo(s) live as named subdirectories underneath it.

---

## Decision

**Split layout is the canonical project structure for the `claude_template_yaml` framework.**

Flat layout (where `$PROJECT_DIR` == git root) is legacy and receives a soft migration NOTICE from `sync-framework.sh` on every session start. The framework does not auto-migrate existing flat-layout adopters, but it provides a migration playbook (`docs/dev_framework/migration-guide-split-layout.md`) and does not develop new features in flat-layout mode.

---

## Definitions

### Split layout (canonical)

```
$PROJECT_DIR/                 ← Claude Code is invoked from here
  CLAUDE.md
  .claude/
  .mcp.json
  .env                        ← holds CLAUDE_TEMPLATE_ROOT, DEFAULT_CODE_SUBDIR, etc.
  docs/                       ← planning, framework, ADRs
  references/                 ← external repo clones
  <repo-slug>/                ← git repo; name matches GitHub repo slug exactly
    src/
    tests/
    package.json
    .git/
    .env                      ← code-level secrets (symlinked or separate from parent .env)
    …
```

`$CODE_ROOT = $PROJECT_DIR/$CODE_SUBDIR`

### Multi-repo split layout

When one parent holds N code repos (single Claude Code session, shared tracking tree):

```
$PROJECT_DIR/
  CLAUDE.md
  .claude/
  docs/
  .env                        ← DEFAULT_CODE_SUBDIR=api (primary for single-repo ops)
  api/                        ← $PROJECT_DIR/api
    .git/
    …
  web/                        ← $PROJECT_DIR/web
    .git/
    …
  infra/                      ← $PROJECT_DIR/infra
    .git/
    …
```

Each W-item carries an optional `target-repo: <subdir>` field in its YAML frontmatter (per [ADR-020](adr-020-yaml-frontmatter-w-items.md)). `$CODE_ROOT = $PROJECT_DIR/$TARGET_REPO` for that W-item, defaulting to `$PROJECT_DIR/$DEFAULT_CODE_SUBDIR` when unset.

### Flat layout (legacy)

```
$PROJECT_DIR/                 ← also the git root
  CLAUDE.md
  .claude/
  docs/
  src/
  .git/
  …
```

`$CODE_ROOT == $PROJECT_DIR`

---

## `.env` convention for split layout

Minimum additions to `$PROJECT_DIR/.env`:

```bash
# Which subdirectory holds the code (matches GitHub repo slug)
DEFAULT_CODE_SUBDIR=my-repo-name

# Template location for framework sync (optional — the hook also resolves
# via sibling-directory fallback at depths 1, 2, 3)
CLAUDE_TEMPLATE_ROOT=/path/to/claude_template_yaml
```

For multi-repo projects, `DEFAULT_CODE_SUBDIR` names the primary repo (used when a W-item's frontmatter does not set `target-repo`).

---

## `$PROJECT_DIR` git tracking: optional

The split layout does **not require** `$PROJECT_DIR` to be a git repo. Both modes are first-class:

- **Untracked parent (default, simpler).** `$PROJECT_DIR` has no `.git/`. Tracking material (CLAUDE.md, docs/, .claude/, .mcp.json) lives as plain files. Plan edits are file-only writes; concurrent-claim safety relies on shared-filesystem visibility (sessions reading `$PROJECT_DIR/docs/execution-plans/plan.md` see updates immediately). The push-then-fail collision guard from PLAN-WRITE DISCIPLINE is unavailable but rarely needed in practice for single-machine multi-session work.
- **Tracked parent (optional, full discipline).** `$PROJECT_DIR` is its own git repo with its own remote (e.g., a "project management" repo tracking plan history, ADRs, and tracking material across phases). Plan edits commit + push there. Full PLAN-WRITE DISCIPLINE concurrent-claim safety, plus durable plan history.

Adopters choose based on context: solo work on a single machine → untracked parent is sufficient; team work where plan history matters or where multiple machines need synchronized plans → tracked parent.

**Code-side git operations (branching, merging, pushing the code repo's `dev`/`main`) always happen in `$CODE_ROOT` and are independent of whether the parent is tracked.** The `git push origin dev` and `git push origin main` steps throughout the framework refer to the CODE repo's branches, not the parent's. This holds in both modes.

---

## W-item field addition: `target-repo` (YAML frontmatter)

For multi-repo projects, W-item files gain an optional frontmatter field that composes with the shape defined in [ADR-020](adr-020-yaml-frontmatter-w-items.md):

```yaml
---
parallel-safe: false
touches:
  - src/auth/login.ts
target-repo: api        # optional; defaults to DEFAULT_CODE_SUBDIR from $PROJECT_DIR/.env
---
```

The Orchestrator and Developer resolve `$CODE_ROOT` from this field before creating worktrees or running git commands. Single-repo projects omit the field; ADR-020's existing schema is unchanged for them.

The Reviewer's `scripts/check-touches.sh` (mechanical scope check shipped under ADR-020) treats `target-repo` as a known-orthogonal field and ignores it — `touches` paths remain relative to `$CODE_ROOT`, so the script's `git diff --name-only` comparison still works in either layout.

---

## Effect on sync-framework.sh

All sync targets in `sync-framework.sh` write to `$PROJECT_DIR` (the tracking tree), which is already correct for split layout:

| Hook step | Target path | Status |
|---|---|---|
| `docs/dev_framework/` sync | `$PROJECT_DIR/docs/dev_framework/` | ✓ already correct |
| `.claude/hooks/` sync | `$PROJECT_DIR/.claude/hooks/` | ✓ already correct |
| `docs/framework_exceptions/` init | `$PROJECT_DIR/docs/framework_exceptions/` | ✓ already correct |
| `.mcp.json` seed | `$PROJECT_DIR/.mcp.json` | ✓ already correct |
| Dev-slot + check-touches stubs ([ADR-019](adr-019-dev-slots-and-deploy-stubs.md), [ADR-020](adr-020-yaml-frontmatter-w-items.md)) | `$PROJECT_DIR/scripts/...`, `$PROJECT_DIR/docs/dev/slots.yaml` | ✓ already correct |
| `CLAUDE.md` managed-block refresh | `$PROJECT_DIR/CLAUDE.md` | ✓ already correct |

Two logic changes are added:

1. **`CLAUDE_TEMPLATE_ROOT` resolution fallback.** After trying `$PROJECT_DIR/.env`, the hook scans immediate subdirectories of `$PROJECT_DIR` that contain both `.git/` and `.env`, and tries those `.env` files for `CLAUDE_TEMPLATE_ROOT`. This removes the need for a symlink bridge in split-layout adopters who kept their single `.env` inside the code repo. The existing sibling-depth fallback (`../claude_template_yaml`, `../../claude_template_yaml`, `../../../claude_template_yaml`) remains after the subdir scan.

2. **Flat-layout detection NOTICE.** If `$PROJECT_DIR/.git` exists, the hook emits a `NOTICE` prompting migration. Sync continues (soft warning, not a block).

---

## Effect on worktree paths

The Parallel Developer and Orchestrator-mode Executors use `/tmp/worktrees/<project>/w-<id>-<slug>`. Under this ADR, `<project>` is formally defined as the **git repository name** — `basename $CODE_ROOT` — not `basename $PROJECT_DIR`. In flat layout these are identical; in split layout they differ.

---

## Script placement doctrine

Two categories of scripts, with different homes:

**Agent-orchestration scripts → `$PROJECT_DIR/scripts/`** (the parent). These are framework infrastructure invoked by agent roles for framework reasons — they belong with the tracking tree, not the code repo.

- `scripts/launch_local.sh` — dev-slot launch ([ADR-019](adr-019-dev-slots-and-deploy-stubs.md))
- `scripts/teardown_local.sh` — dev-slot teardown ([ADR-019](adr-019-dev-slots-and-deploy-stubs.md))
- `scripts/setup_dev_slots.sh` — one-time slot + Caddyfile setup ([ADR-019](adr-019-dev-slots-and-deploy-stubs.md))
- `scripts/main_to_prod.sh` — named escape hatch for user-approved direct-to-prod deploy ([ADR-019](adr-019-dev-slots-and-deploy-stubs.md))
- `scripts/check-touches.sh` — Reviewer-side mechanical scope check ([ADR-020](adr-020-yaml-frontmatter-w-items.md))
- `docs/dev/slots.yaml` — slot registry (committed) and `.local/dev_slots/<slot>.yaml` — slot live state (gitignored)

The sync hook seeds these under `$PROJECT_DIR/` — agents invoke them from the parent.

**Code-native artifacts → `$CODE_ROOT/`** (the git repo). These belong to the codebase and ride with code commits:

- CI config (`.github/workflows/`, `.gitlab-ci.yml`, `circle.yml`, etc.)
- Language-specific build/test/migrate scripts (npm scripts in `package.json`, `alembic` migrations, `prisma` schemas, `Makefile`, etc.)
- Code-shaped consistency checks the project owns (e.g., the project-local `scripts/check-consistency.sh` mentioned in CLAUDE.md — note: this one is project-owned, not template-shipped)

**Adopter rule of thumb:** if the script is something a framework AGENT ROLE invokes (Developer launching a slot, Orchestrator triggering a deploy, Reviewer running scope check), it lives at parent. If it's something the codebase itself owns (CI runs it, a code commit changes it, a language tool invokes it), it lives in the code repo. The reason production-deploy commands live at the parent (`scripts/main_to_prod.sh`) is that they are agent-orchestration of release operations — the code repo's role in deploys is the CI config, not the deploy invocation. About the only deploy-shaped thing that lives in the code repo is the CI config.

**Invocation under split layout.** Agents invoke parent-side scripts from `$PROJECT_DIR`. The scripts use CWD-relative internal paths (`docs/dev/slots.yaml`, `.local/dev_slots/`), so they must be run with `$PROJECT_DIR` as the working directory — not from inside `$CODE_ROOT` or a worktree. Each consuming doc (developer.md, CLAUDE.md commands block) spells this out explicitly at the invocation site.

---

## Backward compatibility

Flat-layout adopters receive a session-start NOTICE. All existing behavior is preserved. There is no forced migration, no data loss risk, and no auto-rewrite of their directory tree.

New adopters should use split layout from the start. The template stub, migration guide, and managed CLAUDE.md block all assume split layout.

---

## Named gaps (follow-up)

The following items are out of scope for this ADR and are called out explicitly so they don't get lost:

### 1. `target-repo` mechanism in consumer briefs

`target-repo` is defined here (W-item YAML frontmatter field) and referenced in `developer.md` and `context-management.md`. It is **not yet wired into the consumer briefs that must act on it**:

- `docs/dev_framework/templates/orchestrator-bootstrap.md` — STEP 1 worktree creation must resolve `$CODE_ROOT` from the W-item's `target-repo` frontmatter before `git worktree add`
- `docs/dev_framework/templates/executor-brief.md` — STEP 1 ("set working directory") must do the same

Until these briefs are updated, `target-repo` is an English-only convention. Orchestrators and Executors using the template briefs will default to `DEFAULT_CODE_SUBDIR` regardless. Multi-repo projects must currently add a `dev_framework_exceptions.md` note overriding STEP 1 in those briefs.

### 2. `$CODE_ROOT` references in remaining framework files

The following docs have not been updated to reference `$CODE_ROOT` or the split-layout cd discipline. They retain implicit flat-layout assumptions in their path references and cd steps:

- `docs/dev_framework/coding-standards.md`
- `docs/dev_framework/strategist.md`
- `docs/dev_framework/templates/reviewer-brief.md`
- `docs/dev_framework/templates/integrator-qa-brief.md`

These files are not blockers for adopters working in split layout today — the cd discipline is defined in `developer.md §Working directory: $CODE_ROOT` and `context-management.md §Project layout`, and those are the primary references roles read. The above files will be updated in a follow-up pass once the split layout is validated across more adopters.

---

## Related

- [ADR-014](adr-014-framework-sync-on-session-start.md) — sync hook design
- [ADR-015](adr-015-template-developer-role.md) — Template Developer role
- [ADR-019](adr-019-dev-slots-and-deploy-stubs.md) — dev slots / deploy stubs (orthogonal; both ADRs ship stubs via the sync hook)
- [ADR-020](adr-020-yaml-frontmatter-w-items.md) — YAML frontmatter on W-items (this ADR extends the schema with `target-repo`)
- `docs/dev_framework/migration-guide-split-layout.md` — migration playbook
- `docs/dev_framework/context-management.md §Project layout` — runtime resolution rules
