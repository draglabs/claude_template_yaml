# ADR-019: Dev slots and deploy script stubs

**Status:** accepted
**Date:** 2026-05-02
**Deciders:** David (template author), Template Developer session

## Context

Two related context-cost problems surfaced in production use of the framework:

1. **Deploy process re-derived every session.** Bringing up a local dev runtime (Docker container, native dev server, reverse proxy mapping) was unscripted. Every Developer session re-discovered the project's port range, container names, run flags, and Caddy/proxy config from scratch — sometimes from CLAUDE.md, sometimes from Slack scrollback, sometimes by reading `docker ps` and reverse-engineering the prior session's setup. The user reported burning a 20x account in ~20 working hours partly because of this re-derivation cost across three Parallel Developer sessions.

2. **Inconsistent deploys across sessions.** The same project would launch on different ports, different container names, or with different env vars depending on which session (or which Developer) brought it up. When two Parallel Developers needed to coexist, port collisions and container-name collisions surfaced unpredictably. The user-supervised QA loop hid most of this — but the cost was the user noticing and fixing it inline rather than the framework preventing it.

The companion template `codex_template` had already solved this with a slot-registry + deploy-stub pattern. A `docs/dev/slots.yaml` file pinned slot names to ports + roles + worktree requirements; three scripts (`launch_local.sh`, `teardown_local.sh`, `main_to_prod.sh`) shipped as exit-1 stubs with the slot/state-file plumbing pre-filled and the project-specific docker bodies left blank. Once an agent filled the project bodies into the scripts, "launch dev0" became `./scripts/launch_local.sh dev0` — no re-derivation, consistent across sessions, and the canonical entry point that Reviewer can audit against.

## Decision

Bring the codex pattern into `claude_template_yaml`, adapted for two claude-side specifics: the `{{ports}}` project variable (port range varies per project) and the framework's existing CI-only production-deploy rule (CLAUDE.md §"Two process rules" #2). Adaptations:

1. **Slot registry at `docs/dev/slots.yaml`.** Four named slots (`dev0`, `dev1`, `dev2`, `dev3`). dev0 is reserved for the Default Developer (coordination, hot-fixes, neutral runtime; `worktree_required: false`). dev1–3 are for Parallel Developers (formal ticket work; `worktree_required: true`). Each slot carries a `hostname`, `port`, `role`, and `intended_use` array. Hostnames follow the pattern `<slot>.<sub>.localhost` — RFC 6761 reserves `.localhost`, which auto-resolves to 127.0.0.1 on macOS, Linux, and modern Windows, so no `/etc/hosts` edits are needed.

2. **Caddy as the routing layer.** Caddy reverse-proxies `<slot>.<sub>.localhost` → `localhost:<port>`. The setup script generates the Caddy block and (with user confirmation) appends it to the user's Caddyfile, wrapped in `# BEGIN <sub>-dev-slots` / `# END <sub>-dev-slots` markers so re-runs update in place. Caddy auto-issues internal-CA certs for `.localhost` hosts; first-time use may require `caddy trust` once to suppress browser cert warnings.

3. **Four scripts in `scripts/`** (all ship as stubs, idempotent-init):
   - **`scripts/setup_dev_slots.sh`** — interactive one-time setup. Asks for base port, fills in slots.yaml (hostnames + ports), generates the Caddy block, prompts for Caddyfile path (auto-detects `/opt/homebrew/etc/Caddyfile`, `/usr/local/etc/Caddyfile`, `/etc/caddy/Caddyfile`, `~/Caddyfile` in order), appends with begin/end markers. Re-runnable; updates between markers on subsequent runs. Does NOT edit CLAUDE.md — `{{ports}}` lives inside the framework-managed block which gets overwritten on every sync (per ADR-014); slots.yaml is the authoritative source of truth for actual port assignments.
   - **`scripts/launch_local.sh <slot>`** — claims the slot (writes `.local/dev_slots/<slot>.yaml` state file), then runs the project-specific launch body. Slot-claim plumbing is pre-filled; the launch body (the actual `docker run …` or equivalent) is stubbed with `exit 1` until the agent fills it in. Detects "stub still has placeholders" via `port: 0` / `hostname: PLACEHOLDER` and halts with a "run setup_dev_slots.sh first" message.
   - **`scripts/teardown_local.sh <slot>`** — reads the state file, runs the project-specific teardown body, removes the state file. Same stub-and-fill shape as launch.
   - **`scripts/main_to_prod.sh`** — the **named escape hatch** for user-approved direct-to-server production deploy. Ships as a stub; agent scopes the real server with the user once and fills in connection + update + restart + verification steps. After filling, every prod deploy goes through this script — never improvise prod commands outside it.

4. **`.local/dev_slots/<slot>.yaml`** — per-slot live state (gitignored). Created by launch, read by teardown. Captures `slot`, `role`, `hostname`, `port`, `claimed_at`, `ticket`, `status`. The committed slot registry (`slots.yaml`) tells you what slots exist; the local state tells you which are currently held.

5. **Idempotent-init sync.** All four scripts and `slots.yaml` ship under `docs/dev_framework/_stubs/` in the canonical template. The sync hook (`.claude/hooks/sync-framework.sh`) copies them on first sync and never overwrites afterward — same pattern already used for `framework_exceptions/` and `.mcp.json`. Adopters that fill in the stubs keep their work across all future syncs.

6. **Parent-side placement under split layout.** All four scripts and `slots.yaml` are seeded at **`$PROJECT_DIR/scripts/`** and **`$PROJECT_DIR/docs/dev/slots.yaml`** — the parent directory under split layout ([ADR-021](adr-021-split-layout.md)), NOT inside `$CODE_ROOT`. These are agent-orchestration artifacts (dev-slot launch/teardown, deploy escape hatch); they belong with the tracking tree, not the code repo. About the only deploy-shaped thing that lives in `$CODE_ROOT` is CI config. Agents invoke the scripts with `$PROJECT_DIR` as the working directory (the scripts use CWD-relative paths internally). See [ADR-021](adr-021-split-layout.md) §"Script placement doctrine" for the full rule.

### Production-deploy doctrine (carve-out)

CLAUDE.md §"Two process rules" #2 ("CI-only deploys to production. Production changes land via `git push origin main` → CI. Never from a laptop. Never via `docker exec`.") remains the **default rule for every adopter**. Most projects should never fill in `main_to_prod.sh` — its `exit 1` stub state is the correct steady state for a CI-deployed project.

For the small number of projects where the user has explicitly approved direct-to-server deploy (legacy infrastructure, no CI runner, niche hosting), `main_to_prod.sh` is the **named, single, canonical entry point**. The doctrine sharpens to:

- The default rule is unchanged: CI is how production gets updated.
- When the user has approved direct-deploy, `main_to_prod.sh` is the only path. Improvisation outside this script is a Reviewer-blocking violation.
- The script's existence as a filled-in artifact in the project repo is the implicit signal that the user has approved this exception. A still-stub `main_to_prod.sh` means CI-only is still in force.

### Reviewer-side enforcement

The Reviewer brief (`docs/dev_framework/templates/reviewer-brief.md`) gains a rule:

> If a commit message, diff, or work history shows a production deploy executed by any path other than `scripts/main_to_prod.sh` (e.g., raw `ssh user@host docker pull`, ad-hoc `kubectl apply`, manual `pm2 restart` on the prod server), verdict is **block**. The Reviewer flags this even if the deploy succeeded — the doctrine violation is the issue, not the outcome.

This makes the named-escape-hatch enforceable. Without Reviewer enforcement, `main_to_prod.sh` becomes one of several deploy paths in practice, and the consistency win evaporates.

## Consequences

**What this buys:**

- **Deploy commands are scoped once per project, not every session.** After the agent fills in the launch/teardown bodies, "launch dev0" is one shell command. Context spent re-deriving the deploy process drops to zero across all subsequent sessions.
- **Consistent slot allocation across sessions.** Default Developer always gets dev0; Parallel Developers always get dev1+ in order. Container names, ports, and hostnames are stable — no "what port is the QA running on this time?" friction.
- **Friendly hostnames without `/etc/hosts`.** `dev0.<sub>.localhost` auto-resolves; Caddy reverse-proxies to the port. The user QAs at a real-looking URL instead of `localhost:3060`.
- **Named escape hatch for direct-deploy projects.** The minority of projects that don't use CI now have a single canonical command instead of improvised ssh sessions, and the Reviewer can audit it.
- **Setup is interactive but one-shot.** `scripts/setup_dev_slots.sh` is the only place that knows how to update both slots.yaml and the Caddyfile in lockstep — adopters don't have to remember the steps.

**What this costs:**

- **More framework surface.** Five new files (four scripts + one yaml) ship to every adopter. Most are small stubs with self-documenting "fill me in" exit-1 states; cost is mostly cognitive (more files to understand) plus the one-time setup time.
- **Caddy as a dependency.** The hostname routing relies on Caddy. Adopters without Caddy installed get a working slots.yaml + scripts but the friendly hostnames don't work — they hit `localhost:<port>` directly. Documented in `dev-environment.md`; not framework-blocking.
- **Ruby dependency for yaml parsing.** Launch and teardown scripts use `ruby -e` to read slots.yaml (matches codex; ruby is on macOS by default and widely available on Linux). Adopters without ruby need to swap in `yq` or another parser — documented as a known constraint.
- **Filled-in stubs become project assets.** The launch/teardown bodies are project-specific code committed to the project repo. Same model as any other infrastructure-as-code artifact.
- **First-launch TLS friction.** `caddy trust` is a one-shot but adds a step to the first-time setup. Documented in setup script output and in the ADR.

**What this does NOT do:**

- **Does not change the production-deploy default.** CI-only remains the rule. `main_to_prod.sh` is for projects that have already opted out of CI by user decision; it does not encourage opting out.
- **Does not change the Developer's QA-loop pattern.** User-mediated QA inside `in_progress` (per ADR-018) is unchanged. The slots simply give the runtime a stable hostname/port for the user to QA against.
- **Does not change Orchestrator-mode dispatch.** Executor subagents in worktrees can use the slots if the project is configured, but the slot mechanism is Developer-centric — the QA-loop framing assumes a persistent session.
- **Does not auto-fill the launch/teardown bodies.** Fundamentally project-specific (which container, which env vars, which compose file). The agent fills them in once on first use, then the script is the canonical entry point forever.

## Alternatives considered

1. **Codex's pattern as-is (no setup script, no Caddy).** Rejected — codex hard-codes ports 3060–3063 and leaves hostname routing to the adopter. claude_template's `{{ports}}` variable means port range is project-specific (no universal default), and the user explicitly wanted Caddyfile auto-configuration to save time. The adapted pattern adds the setup ritual on top of codex's slot+stub shape.

2. **Skip Caddy; use raw `localhost:<port>` for QA.** Rejected — the user QAs against URLs that look like the product (cookie domains, CORS behavior, OAuth redirects depend on hostname). Friendly hostnames via Caddy + `.localhost` cost a one-time `caddy trust` and earn realism for every QA session thereafter.

3. **`/etc/hosts` + non-`.localhost` suffix (e.g., `.local`, `.test`).** Rejected — `.localhost` auto-resolves per RFC 6761, eliminating the `/etc/hosts` step entirely. The user picked option 2 in design specifically for this property.

4. **Destructive sync for `setup_dev_slots.sh` (framework-canonical) + idempotent-init for the others.** Rejected — mixed sync semantics inside `scripts/` create cognitive load (which scripts do I edit? which get overwritten?) without clear benefit. Uniform idempotent-init is simpler; the cost is that **none of the four scripts auto-propagate framework improvements to existing adopters** — including the slot-claim/state-file plumbing inside `launch_local.sh` and `teardown_local.sh`. If the plumbing has a bug, every adopter is stranded on the buggy version until they manually re-pull. Acceptable trade-off because the plumbing is small (~50 lines, well-tested via use) and a managed-block pattern inside scripts would be material additional complexity. v2 may revisit if the plumbing grows or a bug bites — adopters who want the latest framework-side script content can `cp $TEMPLATE_ROOT/docs/dev_framework/_stubs/scripts/* scripts/` manually.

5. **Single ADR for both the slot registry and the production-deploy carve-out vs. two ADRs.** Single ADR (this one) wins — the carve-out is a doctrine adjustment driven by introducing `main_to_prod.sh`, not an independent decision. Two ADRs would force a forward reference from the deploy-doctrine ADR to the slot-mechanism ADR.

6. **Fold setup into `sync-framework.sh` directly (run setup automatically on first sync).** Rejected — setup is interactive (asks user for base port, asks before writing Caddyfile). Running it from a SessionStart hook would block the session waiting for input, or skip the prompts and use defaults that may collide. Keeping setup as an explicit user-invoked script preserves the "first sync seeds, user runs setup once" flow.

## Acceptance criteria for the shipping PR

- `docs/dev_framework/_stubs/scripts/{launch_local,teardown_local,main_to_prod,setup_dev_slots}.sh` exist, each `bash -n`-clean, executable, with the slot/state plumbing filled and project-specific bodies stubbed.
- `docs/dev_framework/_stubs/docs/dev/slots.yaml` exists with `dev0`–`dev3` entries, `port: 0` and `hostname: PLACEHOLDER` until setup runs.
- `.claude/hooks/sync-framework.sh` includes the "5c" idempotent-init pass for the four scripts + `slots.yaml`. `bash -n` clean. Adopters first-syncing get the files; subsequent syncs leave them alone.
- `docs/dev_framework/developer.md` §"Phase discipline" §Build mentions launching via `./scripts/launch_local.sh dev<N>` and §Code Review §Cleanup mentions teardown via `./scripts/teardown_local.sh dev<N>`. Discipline rule: "if the script is still a stub, halt and fill it in + commit before launching — no improvising docker."
- `docs/dev_framework/dev-environment.md` has a §"Slot registry and launch scripts" section pointing at slots.yaml + the scripts + this ADR.
- `CLAUDE.md` Commands section has rows for `setup_dev_slots.sh`, `launch_local.sh`, `teardown_local.sh`, `main_to_prod.sh`. §"Two process rules" #2 has a footnote naming `main_to_prod.sh` as the canonical escape hatch for user-approved direct-deploy projects.
- `docs/dev_framework/templates/reviewer-brief.md` has the "block if prod deploy by any path other than `main_to_prod.sh`" rule under review questions.
- `.gitignore` includes `.local/`.
- One PR. Half-shipping these creates an incoherent intermediate state — adopters get scripts that reference docs that don't exist, or vice versa.

---

## Revision (v1.1) — 2026-05-21: slot schema refinement + port-range governance

Field experience from the first multi-port-surface adopter (Postgres-per-slot + Marimo app server) exposed three gaps in the original schema:

1. **Implicit single-port-per-slot.** The original `slots.yaml.port` field was *intended* as the HTTP/Caddy-routed port, but nothing in the schema named it. The adopter typed their Postgres base port into `setup_dev_slots.sh` (because that was their primary "per-slot port"); Caddy then routed the slot hostname to the DB, breaking HTTP access entirely. The Developer improvised by running the app server on raw `localhost:<port>` and hand-editing the Caddyfile.
2. **No place for project-specific secondary ports.** Once the adopter had separate DB and app ports, there was no canonical home for the DB port assignment — it lived in a project-local `.env` or scattered constants, with no per-slot mapping the launch body could read.
3. **Port-range governance was ambient.** `setup_dev_slots.sh` asked "Base port for dev slots [3060]?" — whoever ran it picked a number, which could collide with another project on the same machine. `{{ports}}` in CLAUDE.md (the Strategist-set range) and slots.yaml could diverge silently.

### Refinements

1. **`port` is canonical: the HTTP/Caddy-routed port.** Renamed semantically — the slot's `port` is now formally defined as the port `<slot>.<sub>.localhost` reverse-proxies to. Caddy routes there; the Reviewer assumes QA targets this hostname.

2. **Optional `extras: { <name>: <port>, ... }` map per slot.** Project-specific secondary ports (database, cache, message queue, anything per-slot but NOT HTTP-fronted) live here. `setup_dev_slots.sh` does NOT manage extras — projects fill them by hand or via a project-local helper. `launch_local.sh`'s project body reads them from slots.yaml directly (Ruby snippet in the body) and binds the project services to them.

   Example for the field Dev's case (Marimo app + Postgres per slot):
   ```yaml
   dev1:
     role: parallel_developer
     hostname: dev1.analytics.localhost
     port: 2719           # HTTP/Caddy-routed — Marimo binds here
     extras:
       db: 5442           # Postgres — project body reads from extras.db
     worktree_required: true
   ```

3. **Project variables move to `.env` (canonical machine source); CLAUDE.md is the human-readable mirror.** Previously the script regex-parsed CLAUDE.md to extract `{{sub}}` and `{{ports}}` — fragile against any rephrasing of the bullet text. Now: a starter `.env.example` ships with the template (`docs/dev_framework/_stubs/.env.example`) and is idempotent-init'd to `$PROJECT_DIR/.env.example` by the sync hook. The adopter copies it to `.env` (gitignored) on first init; the Strategist fills the values during the first-contact interview. Scripts source `.env` directly — `setup_dev_slots.sh` halts if `PROJECT_SUB` or `PROJECT_PORTS` is empty or `PLACEHOLDER`. CLAUDE.md still displays the same values inline (for human readability), kept in sync by Strategist discipline + the §"Stub audit" `.env`↔CLAUDE.md drift row.

4. **Strategist owns the first-contact interview, including port-range confirmation.** Port allocation is a cross-project resource decision (avoids collisions with other projects on the same machine) — the Strategist negotiates with the user, fills `.env` (`PROJECT_SUB`, `PROJECT_PORTS`, etc.) and CLAUDE.md atomically. The script halt above is the forcing function: the Developer can't bring up a local runtime until the interview is done. Full question list in [`strategist.md`](../dev_framework/strategist.md) §"First-contact interview."

5. **`setup_dev_slots.sh` asks the HTTP-surface question.** New interactive prompt: "Does this project expose an HTTP surface that needs Caddy routing?" Answer `true|false` is written to `http_surface` at the top of `slots.yaml`. If `false`, the script skips Caddy block generation entirely (no `<slot>.<sub>.localhost` blocks written). This lets non-HTTP projects (CLI tools, libraries, headless pipelines) use the slot model for port assignment without Caddy noise.

6. **Reviewer rule: QA target is the slot hostname when Caddy is configured.** New conditional rule in `reviewer-brief.md`: if `slots.yaml` has `http_surface: true` AND the working log or diff shows the QA loop targeted raw `localhost:<port>` for an HTTP surface, flag **MED**. Pre-condition matters — projects with `http_surface: false` (CLI tools, libraries, server-side scripts) are unaffected. The rule mechanizes the doctrine "QA exercises the prod-shaped path through the proxy, not the raw bind port."

7. **Developer doctrine update.** `developer.md §Build` adds: "QA target is `https://<slot>.<sub>.localhost/` via Caddy, NOT `localhost:<port>`. If your slot lacks a Caddy block, run `./scripts/setup_dev_slots.sh` from `$PROJECT_DIR` to (re)generate them." The Reviewer's MED rule is the enforcement; the Developer doc is the rule.

### Migration (one-shot, per affected adopter)

Adopters whose slots.yaml currently uses `port` for something other than the HTTP-routed port (i.e., the field Dev's case) do a one-time hand-edit:

1. **Identify the HTTP port.** Whatever the app server should bind to for QA via Caddy.
2. **Rename current `port`.** Move it under `extras` with a descriptive name. Example:
   ```yaml
   # Before
   dev1: { port: 5441, hostname: dev1.analytics.localhost, ... }

   # After
   dev1:
     port: 2719              # HTTP/Caddy-routed (new)
     hostname: dev1.analytics.localhost
     extras:
       db: 5441              # moved from port
     ...
   ```
3. **Update `launch_local.sh`'s project body.** It currently reads `$PORT` as the DB port; change to read `$PORT` as the HTTP port, plus a Ruby snippet to pull `extras.db` for the database.
4. **Re-run `./scripts/setup_dev_slots.sh`** from `$PROJECT_DIR` to regenerate Caddyfile blocks against the new `port` values (or hand-edit the Caddyfile if setup would clobber project-specific blocks).
5. **Commit.** One commit per slot is fine; one commit covering all four slots is preferable.

No mechanical `--migrate` flag ships — the rename is two YAML edits per slot, and a script automating it would be more code than the manual fix. Adopters who haven't run setup yet (or whose `port` is already the HTTP port, the original intent) need no migration.

Projects with no app port (CLI-only tooling) leave `port` set to whatever (or `0` if no HTTP surface), skip Caddy generation entirely in setup, and use extras as the project requires. The Reviewer rule no-ops in that case (pre-condition: Caddyfile block exists).

### Acceptance criteria for the Revision

- `docs/dev_framework/_stubs/.env.example` — new starter file with project variables (PROJECT_NAME, PROJECT_SUB, PROJECT_WEBSITE, PROJECT_PORTS, DEV_ENVIRONMENT_MODE, DEFAULT_CODE_SUBDIR, CLAUDE_TEMPLATE_ROOT) as PLACEHOLDER values + comments.
- `.claude/hooks/sync-framework.sh` — `.env.example` added to the idempotent-init list (seeded once; never overwrites adopter's `.env.example` or `.env`).
- `docs/dev_framework/_stubs/docs/dev/slots.yaml` — header defines `port` as HTTP/Caddy-routed; `http_surface: PLACEHOLDER` top-level field; commented `extras: {}` example per slot.
- `docs/dev_framework/_stubs/scripts/setup_dev_slots.sh` — sources `.env` (no more markdown regex), halts on `PLACEHOLDER` values, asks the HTTP-surface question, writes `http_surface` to `slots.yaml`, prints the extras edit pattern.
- `docs/dev_framework/_stubs/scripts/launch_local.sh` — header names `$PORT` as HTTP/Caddy-routed; shows Ruby one-liner for reading `extras` in the project body.
- `docs/dev_framework/developer.md §Build` — QA-target-is-slot-hostname rule (conditional on `http_surface: true`).
- `docs/dev_framework/templates/reviewer-brief.md` — new conditional MED rule (pre-condition reads `http_surface` from `slots.yaml`).
- `docs/dev_framework/strategist.md` — first-contact-interview responsibility (subsumes the prior port-range bullet); §"First-contact interview" section with .env + CLAUDE.md dual-surface fill instructions; new stub-audit rows for `.env` PLACEHOLDERs and `.env`↔CLAUDE.md drift.
- `docs/architecture/adr-019-dev-slots-and-deploy-stubs.md` — this Revision (v1.1) section.

## Revision (v1.2) — 2026-05-27: launch/teardown safety primitives

Field experience from a Parallel Developer at an adopter on 2026-05-27 exposed a fourth gap: `launch_local.sh <slot>` was invoked from a worktree CWD but silently launched against the main checkout (because the project body had no source-resolution layer — it just used the implicit `$PWD` of the script's enclosing directory). The mismatch surfaced only because the operator noticed the missing feature during user-QA; one full launch + teardown cycle was lost. The retrospective named the missing primitive: "what source is this slot about to launch against, and does the operator agree?"

### Refinements

1. **`CODE_PATH` 5-tier auto-resolver in the launch stub's generic header.** Order: `--code-path=PATH` flag → `CODE_PATH` env var (backwards-compat) → `--wid=W-NN` (worktree match under `/tmp/worktrees/${DEFAULT_CODE_SUBDIR}/<wid>-*`) → `git rev-parse --show-toplevel` from `$PWD` → `$PROJECT_DIR/$DEFAULT_CODE_SUBDIR` fallback. Result exposed to the project body as `$CODE_PATH_RESOLVED` plus `$MODE` (`worktree|main`). Worktree-launches that bind docker/dev-server at `$PWD` or `$PROJECT_DIR/$DEFAULT_CODE_SUBDIR` are wrong; the project body must use `$CODE_PATH_RESOLVED`.

2. **`.env` auto-symlink for worktrees.** Worktrees do not carry gitignored files; a fresh worktree at `/tmp/worktrees/<repo>/<wid>-<slug>` has no `.env`. The launch stub detects this case, prints "will symlink from $PROJECT_DIR/$DEFAULT_CODE_SUBDIR/.env" in the confirmation block, and applies the symlink after user confirmation. Adopters whose app needs no `.env` see "absent (no canonical to bootstrap from — project body must handle)" and the project body decides what to do.

3. **Pre-launch confirmation block (the load-bearing rule).** The launch stub prints `source path, mode, branch+SHA, port, hostname, .env state` and prompts `Proceed? [Y/n]` (interactive default). `--auto-confirm` bypasses for CI / scripted use. Teardown prints the mirror block (read from the state file — no auto-detect) and prompts the same. The rule "the launch script confirms the source before launching" is mechanical because the script enforces it; framework-level doctrine just acknowledges this is how the script now behaves.

4. **State-file schema additions.** The generic state-file write (above the `PROJECT-SPECIFIC LAUNCH BODY` marker) now includes `code_path`, `mode`, `branch`, `sha`. Project-specific bodies continue to append project-specific fields (e.g. `compose_project`, `compose_file`, `compose_override`) below the generic write. Teardown's generic header reads only the generic fields; the project-specific teardown body reads project-specific fields and is the right place for backwards-compat fallbacks when an in-flight slot pre-dates a body change.

5. **`DEFAULT_CODE_SUBDIR` sourced from `$PROJECT_DIR/.env` in the launch stub.** Aligns with v1.1's `setup_dev_slots.sh` doctrine (project variables live in `.env`, scripts source it). No init-time placeholder edit in the stub. Single source of truth per [ADR-021](adr-021-split-layout.md).

### Migration (adopter-side)

For adopters that have already filled their `launch_local.sh` / `teardown_local.sh` project bodies (auto_portal is the precedent), the sync hook does NOT overwrite filled-in stubs — the new safety primitives ship in the template's `_stubs/scripts/` and reach existing adopters only when an agent manually merges the generic header into the customized script. The customized-body case is left to the adopter (and is the precedent for the follow-up sentinel-marker pattern described under "Out of scope" below). Adopters who have NOT yet filled the stubs receive the new generic header on first sync, the same way any other stub seeds.

In-flight state files (claimed pre-upgrade, torn down post-upgrade) will lack `code_path`, `mode`, `branch`, `sha`. The teardown's generic confirmation block tolerates this (renders `unknown` for missing fields). The project-specific teardown body decides whether to require its own appended fields or fall back — that decision lives in the body, not the generic header.

### Out of scope (follow-up)

A "above-sentinel partial re-sync" mechanism — where the template stubs use a sentinel line (e.g. `# ============ PROJECT-SPECIFIC LAUNCH BODY (do not edit above) ============`) and `sync-framework.sh` can re-drop the above-sentinel content into adopters with customized bodies — would close the customized-body migration gap, but is not landing in this Revision. The current Revision keeps the existing comment-block marker form; the sentinel pattern is a separate doctrine decision (does the sync hook get smarter about stubs?) and a separate ADR's worth of work.

### Acceptance criteria for the Revision

- `docs/dev_framework/_stubs/scripts/launch_local.sh` — sources `$PROJECT_DIR/.env`, validates `DEFAULT_CODE_SUBDIR`, parses `--wid` / `--auto-confirm` / `--code-path` / `--help`, runs the 5-tier resolver, detects mode, prints the confirmation block, applies the `.env` symlink, writes the new state schema. Preserves the `PROJECT-SPECIFIC LAUNCH BODY` marker form; the body's "not yet implemented" placeholder cleans up `$STATE_FILE` before exit 1.
- `docs/dev_framework/_stubs/scripts/teardown_local.sh` — parses `--auto-confirm` / `--help`, reads generic state fields, prints the mirror confirmation block. Marker preserved. Project-specific body recommended pattern (in commented examples): read `compose_project` / `compose_file` / `compose_override` via `read_state`, bail or fall back as the project requires, then `docker compose down`. Generic post-body (below the marker) removes the state file once the body returns successfully.
- `docs/dev_framework/dev-environment.md §"Slot registry and launch scripts"` — `launch_local.sh` / `teardown_local.sh` bullets describe the new flags, confirmation block, CODE_PATH resolver order, and `.env` symlink behavior.
- `docs/dev_framework/developer.md §Build` — guidance that the Parallel Developer can invoke from inside the worktree (auto-detect) or from `$PROJECT_DIR` with `--wid=W-NN`. §"Cleanup at done-flip" — note that teardown also prompts; `--auto-confirm` is for scripted use only.
- This Revision (v1.2) section.

No new entries in `_stubs/.env.example` (DEFAULT_CODE_SUBDIR was already added in v1.1's acceptance criteria; this Revision just adds a second consumer of it).
