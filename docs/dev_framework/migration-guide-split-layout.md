# Migration guide: flat layout → split layout

The canonical framework layout is **split**: Claude Code is invoked from a parent directory that holds tracking material (`CLAUDE.md`, `docs/`, `.claude/`), with the git repo living as a named subdirectory. If your project currently invokes Claude Code from inside the git repo itself (flat layout), this guide walks the migration.

See [ADR-021](../architecture/adr-021-split-layout.md) for the rationale.

---

## What you're doing

Before:
```
my-project/          ← Claude invoked from here; also the git root
  CLAUDE.md
  .claude/
  docs/
  src/
  .git/
  .env
```

After:
```
my-project/          ← Claude invoked from here (tracking tree)
  CLAUDE.md
  .claude/
  docs/
  references/
  .env               ← parent .env; see step 4
  my-repo-slug/      ← git root; name matches GitHub repo slug
    src/
    .git/
    .env             ← code-level secrets (optional; see step 4)
```

---

## Steps

### 1. Create the parent directory

```bash
# Move up one level — the current project dir becomes the code subdir
cd ..
mkdir my-project-parent
mv my-project my-project-parent/my-repo-slug
cd my-project-parent
```

Replace `my-repo-slug` with your GitHub repo's slug (the repository name, not the org).

### 2. Move tracking material to the parent

```bash
# From inside my-project-parent:
mv my-repo-slug/CLAUDE.md .
mv my-repo-slug/.claude .
mv my-repo-slug/.mcp.json .           # if present
mv my-repo-slug/docs .
mv my-repo-slug/references .          # if present
```

Leave all code files (`src/`, `tests/`, `package.json`, `Makefile`, etc.) inside `my-repo-slug/`.

### 3. Update .gitignore (if present)

Your code repo's `.gitignore` may have entries for `docs/` or `.claude/`. Since those now live at the parent level, they're outside the git repo and no longer need to be ignored. Review and clean up if needed.

### 4. Set up .env

Create `$PROJECT_DIR/.env` (at the parent level) with at minimum:

```bash
# The name of the code subdirectory (matches GitHub repo slug)
DEFAULT_CODE_SUBDIR=my-repo-slug

# Optional: points to the canonical template repo for framework sync.
# If omitted, the sync hook also tries the code subdir's .env (if present)
# and then sibling directories (../claude_template_yaml, ../../claude_template_yaml,
# ../../../claude_template_yaml).
CLAUDE_TEMPLATE_ROOT=/path/to/claude_template_yaml
```

If your code repo has its own `.env` for runtime secrets (database URLs, API keys, etc.), you have two options:

- **Separate files (recommended):** parent `.env` holds only framework vars; code repo `.env` holds runtime secrets. Both exist independently.
- **Symlink bridge:** `ln -s my-repo-slug/.env .env` at the parent, so a single `.env` serves both. The sync hook also resolves `CLAUDE_TEMPLATE_ROOT` from the code subdir's `.env` directly as of this ADR, so the symlink is optional if your `CLAUDE_TEMPLATE_ROOT=` line lives inside the code repo.

### 5. Update CLAUDE.md for the new layout

At the top of `CLAUDE.md`, fill in:
```
**Repository layout:** split — code at `my-repo-slug/`
```

And update `{{ports}}` and other template variables if you haven't already.

### 6. Invoke Claude from the parent

From now on, always `cd` to `$PROJECT_DIR` (the parent) before starting Claude Code:

```bash
cd my-project-parent
set -a; source .env; set +a
claude
```

If you use a shell alias or `.envrc`, update it to point at the parent.

### 7. Verify

Start a session. The `[sync-framework]` output should no longer show the flat-layout NOTICE. You should see:

```
[sync-framework] docs/dev_framework/ synced from template
[sync-framework] .claude/hooks/ synced from template (additive; ...)
[sync-framework] CLAUDE.md managed block refreshed from template
[sync-framework] done.
```

No `NOTICE: flat layout detected` line = migration complete.

---

## Optional: track `$PROJECT_DIR` as its own git repo

ADR-021 sanctions two modes for `$PROJECT_DIR` git tracking:

- **Untracked (default, simpler).** `$PROJECT_DIR` has no `.git/`. Tracking material is plain files; plan-write visibility is via shared filesystem only. Fine for solo or single-machine multi-session work — and what you have after completing the steps above.
- **Tracked (optional, full discipline).** `$PROJECT_DIR` is its own git repo with its own remote (a "project management" repo). Plan edits, ADRs, and tracking material are committed and pushed there. Gives full PLAN-WRITE DISCIPLINE concurrent-claim safety + durable plan history. Right for team work, multi-machine setups, or when plan history needs to outlive disk failures.

To enable tracked-parent mode after migration:

```bash
cd $PROJECT_DIR
git init
# Add a .gitignore that excludes <repo-slug>/ (it's its own git repo)
echo "<repo-slug>/" > .gitignore
echo ".env" >> .gitignore        # parent .env often holds secrets
git add CLAUDE.md .claude docs .mcp.json .gitignore
git commit -m "Initial commit: tracking material"
git remote add origin git@github.com:your-org/<project>-tracking.git
git push -u origin main
```

Code-side git operations always happen in `$CODE_ROOT` regardless. The two repos are independent; the parent repo holds plan/doc history, the code repo holds source history.

---

## Multi-repo projects

If one parent holds N code repos, add entries in `.env` for each after the migration:

```bash
DEFAULT_CODE_SUBDIR=api        # primary repo (used when W-item has no target-repo)
```

In your plan's W-item files, add the optional frontmatter field for non-default repos (composes with the existing [ADR-020](../architecture/adr-020-yaml-frontmatter-w-items.md) shape):

```yaml
---
parallel-safe: false
touches:
  - src/routes/web/home.ts
target-repo: web
---
```

The Orchestrator and Developer resolve `$CODE_ROOT = $PROJECT_DIR/$TARGET_REPO` from this field.

---

## Checklist

- [ ] Parent directory created; code repo is a subdirectory named after the GitHub slug
- [ ] CLAUDE.md, .claude/, docs/, .mcp.json, references/ are at parent level
- [ ] `$PROJECT_DIR/.env` has `DEFAULT_CODE_SUBDIR` (and optionally `CLAUDE_TEMPLATE_ROOT`)
- [ ] Claude Code is invoked from `$PROJECT_DIR`, not from inside the code repo
- [ ] Session-start sync runs without the flat-layout NOTICE
