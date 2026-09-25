# FWADR-019: Dev slots and deploy script stubs

**Status:** accepted
**Date:** 2026-05-02
**Deciders:** David (template author), Template Developer session

## Context

Two related context-cost problems surfaced in production use of the framework:

1. **Deploy process re-derived every session.** Bringing up a local dev runtime (Docker container, native dev server, reverse proxy mapping) was unscripted. Every Developer session re-discovered the project's port range, container names, run flags, and Caddy/proxy config from scratch — from CLAUDE.md, Slack scrollback, or by reverse-engineering `docker ps`. The user burned a 20x account in ~20 working hours partly on this re-derivation across three Parallel Developer sessions.

2. **Inconsistent deploys across sessions.** The same project launched on different ports, container names, or env vars depending on which session brought it up. Parallel Developers collided on ports and container names unpredictably; the user noticed and fixed it inline rather than the framework preventing it.

The companion template `codex_template` had solved this with a slot-registry + deploy-stub pattern: `docs/dev/slots.yaml` pinned slot names to ports, roles, and worktree requirements; `launch_local.sh`, `teardown_local.sh`, and `main_to_prod.sh` shipped as exit-1 stubs with slot/state plumbing pre-filled and the project-specific bodies left blank. Once filled, "launch dev0" is `./scripts/launch_local.sh dev0` — no re-derivation, consistent across sessions, and a canonical entry point the Reviewer can audit.

Field use of the adapted pattern then exposed further gaps, each of which shaped a Decision item below:

- **Ambiguous `port`.** A multi-port adopter (Postgres per slot + a Marimo app server) typed their Postgres base port into setup, because nothing said which port a slot's `port` meant. Caddy routed the slot hostname to the database, breaking HTTP access; the Developer improvised raw `localhost:<port>` QA and hand-edited the Caddyfile. There was also no canonical home for the per-slot DB port.
- **Fragile, ambient project variables.** Scripts regex-parsed CLAUDE.md for `{{sub}}` and `{{ports}}` (breaking on any rephrasing), and whoever ran setup picked a base port, so the range could collide with another project or drift from `{{ports}}` silently.
- **Wrong-source launches.** A Parallel Developer ran `launch_local.sh` from a worktree and it silently launched the main checkout (the body used the implicit `$PWD`). It surfaced only in user-QA; a full launch + teardown cycle was lost. The missing primitive: "what source is this slot about to launch against, and does the operator agree?"
- **Unread port ledger.** Picking a range asked the user to remember every other project's ports, yet the local Caddyfile already recorded them in each project's `# BEGIN <sub>-dev-slots` block. A read of the framework author's Caddyfile found a live collision (two projects on 3060) nobody had noticed, because nothing read the file as a ledger — and blocks held only the four slot ports, not the reserved range, while non-HTTP projects wrote none.

## Decision

Bring the codex pattern into `claude_template_yaml`, adapted to the `{{ports}}` project variable (range varies per project) and the CI-only production-deploy rule (CLAUDE.md §"Two process rules" #2):

1. **Slot registry at `docs/dev/slots.yaml`.** Four named slots (`dev0`–`dev3`). `dev0` is the Default Developer's (coordination, hot-fixes, neutral runtime; `worktree_required: false`); `dev1`–`dev3` are for Parallel Developers (ticket work; `worktree_required: true`). Each slot carries `hostname`, `port`, `role`, `intended_use`, and an optional `extras` map. Hostnames follow `<slot>.<sub>.localhost` — RFC 6761 `.localhost` auto-resolves to 127.0.0.1 on macOS, Linux, and modern Windows, so no `/etc/hosts` edits.
   - **`port` is the HTTP/Caddy-routed port** — what `<slot>.<sub>.localhost` reverse-proxies to, and what QA targets.
   - **`extras: { <name>: <port>, ... }`** holds project-specific secondary ports (database, cache, queue — per-slot but not HTTP-fronted). Project-managed: `setup_dev_slots.sh` never writes it; the launch body reads it from `slots.yaml` (Ruby snippet) and binds services to it.
   - **Top-level `http_surface: true|false`** records whether the project has HTTP routes needing Caddy. `false` (CLI tools, libraries, headless pipelines) still uses slots for port assignment, without routes.

   ```yaml
   dev1:
     role: parallel_developer
     hostname: dev1.analytics.localhost
     port: 2719           # HTTP/Caddy-routed — Marimo binds here
     extras:
       db: 5442           # Postgres — project body reads extras.db
     worktree_required: true
   ```

2. **Caddy as routing layer and machine-wide port ledger.** Caddy reverse-proxies `<slot>.<sub>.localhost` → `localhost:<port>` and auto-issues internal-CA certs for `.localhost` (first use may need `caddy trust` once). `setup_dev_slots.sh` writes each project's block between `# BEGIN <sub>-dev-slots` / `# END <sub>-dev-slots` markers so re-runs update in place. The BEGIN line is a **ledger header**: `# BEGIN <sub>-dev-slots (managed by scripts/setup_dev_slots.sh) PORTS=<low>-<high> PROJECT=<name> DIR=<path>` — `PORTS` is the full `PROJECT_PORTS` range; `DIR` is last so paths with spaces survive. **Every project writes a block:** `http_surface: false` projects get a comment-only block (header, one comment, end marker) that Caddy ignores and needs no reload, so their range is still visible. The framework reads the Caddyfile freely and writes it only through this marker mechanism, with confirmation.

3. **Five scripts in `scripts/`** (`launch_local.sh`, `teardown_local.sh`, and `main_to_prod.sh` carry stubbed project bodies and are seed-once; `setup_dev_slots.sh` and `port_ledger.sh` are complete and framework-owned — Decision #5):
   - **`setup_dev_slots.sh`** — interactive one-time setup, re-runnable. Sources `$PROJECT_DIR/.env` and halts if `PROJECT_SUB` or `PROJECT_PORTS` is empty or `PLACEHOLDER`. Runs `port_ledger.sh --check` on `PROJECT_PORTS` (ignoring its own block); on collision it warns with the proposed free range and asks before continuing — not fatal, because the fix is a Strategist `.env` edit this script does not own. Asks the HTTP-surface question and writes `http_surface`; asks for a base port within `PROJECT_PORTS` (default: range low end; all four slots must fit). Fills `slots.yaml` hostnames + ports, generates the Caddy block, prompts for the Caddyfile path (auto-detects `/opt/homebrew/etc/Caddyfile`, `/usr/local/etc/Caddyfile`, `/etc/caddy/Caddyfile`, `~/Caddyfile` in order), and writes between the markers. Prints the `extras` edit pattern. Does NOT edit CLAUDE.md or `.env` — `{{ports}}` lives in the framework-managed block overwritten on every sync ([FWADR-014](fwadr-014-framework-sync-on-session-start.md)); `slots.yaml` is the source of truth for actual port assignments.
   - **`port_ledger.sh`** — read-only. Parses ledger headers *and* every `reverse_proxy … :<port>` line, attributing each to its enclosing block or site label, so hand-written blocks and blocks without a `PORTS=` header count too (re-running setup upgrades an old block in place). Bare: prints the table and cross-project overlaps (exit 2 if any). `--propose [N]`: the lowest free decade-aligned range of N at or above 3000, treating well-known defaults (3000, 5000, 5173, 8000, 8080, …) as built-in claims. `--check LOW-HIGH [--ignore <sub>-dev-slots]`: exit 2 on collision. **Lowest gap, not "above the highest claim"** — one project parked at 8080 must not push every later project into the 8000s. Pre-existing overlaps surface on first run and are the user's to resolve per project.
   - **`launch_local.sh <slot> [--wid=W-NN] [--auto-confirm] [--code-path=PATH]`** — sources `$PROJECT_DIR/.env` and validates `DEFAULT_CODE_SUBDIR` (no init-time stub edit; single source per [FWADR-021](fwadr-021-split-layout.md)). Resolves the source, prints the confirmation block, claims the slot (writes the state file), then runs the project-specific launch body below the `PROJECT-SPECIFIC LAUNCH BODY` marker. The body ships as `exit 1` (cleaning up `$STATE_FILE` first) until the agent fills it in. Halts with "run setup_dev_slots.sh first" while `slots.yaml` still has `port: 0` / `hostname: PLACEHOLDER`.
     - **`CODE_PATH` resolver**, in order: `--code-path` flag → `CODE_PATH` env var (backwards compatibility) → `--wid=W-NN` (worktree under `/tmp/worktrees/${DEFAULT_CODE_SUBDIR}/<wid>-*`) → `git rev-parse --show-toplevel` from `$PWD` → `$PROJECT_DIR/$DEFAULT_CODE_SUBDIR`. Exposed to the body as `$CODE_PATH_RESOLVED` plus `$MODE` (`worktree|main`). A body that binds docker/dev-server to `$PWD` or the main checkout instead of `$CODE_PATH_RESOLVED` is wrong. `$PORT` is the HTTP/Caddy-routed port.
     - **App-env symlink for worktrees.** Worktrees don't carry gitignored files; if the resolved source lacks a `.env`, launch symlinks the app env from the main checkout (`$PROJECT_DIR/$DEFAULT_CODE_SUBDIR/.env` — the app env, distinct from the operator env it sources; [FWADR-033](fwadr-033-env-scope-rule.md)) after confirmation. With no canonical app env it reports "absent" and the body decides.
     - **Pre-launch confirmation block (load-bearing).** Prints source path, mode, branch+SHA, port, hostname, `.env` state, then `Proceed? [Y/n]`. `--auto-confirm` bypasses for CI / scripted use. Because the script enforces it, "confirm the source before launching" is mechanical, not doctrine.
   - **`teardown_local.sh <slot> [--auto-confirm]`** — prints the mirror confirmation block from the state file (no auto-detect; missing generic fields render `unknown`), prompts, runs the project-specific teardown body, then removes the state file once the body returns successfully. Same stub-and-fill shape and marker. Recommended body pattern: read project fields (`compose_project`, `compose_file`, `compose_override`) via `read_state`, bail or fall back as the project requires, then `docker compose down`.
   - **`main_to_prod.sh`** — the **named escape hatch** for user-approved direct-to-server production deploy. Ships as a stub; the agent scopes the real server with the user once and fills in connection + update + restart + verification. After that, every prod deploy goes through it — never improvise prod commands outside it.

4. **`.local/dev_slots/<slot>.yaml`** — per-slot live state (gitignored). Written by launch, read by teardown. The generic write (above the body marker) captures `slot`, `role`, `hostname`, `port`, `claimed_at`, `ticket`, `status`, `code_path`, `mode`, `branch`, `sha`; project bodies append their own fields (e.g. `compose_project`, `compose_file`, `compose_override`) below it. Teardown's generic header reads only generic fields; backwards-compat fallbacks for project fields belong in the project teardown body. `slots.yaml` says what slots exist; local state says which are held.

5. **Sync by ownership** ([FWADR-014](fwadr-014-framework-sync-on-session-start.md) §"Stub scripts"). The five scripts, `slots.yaml`, and `.env.example` ship under `docs/dev_framework/_stubs/` in the canonical template. `setup_dev_slots.sh` and `port_ledger.sh` have no project body; they carry the FRAMEWORK-OWNED header and the sync overwrites them whenever they differ. `launch_local.sh`, `teardown_local.sh`, `main_to_prod.sh`, `slots.yaml`, and `.env.example` are seed-once: copied on first sync, never overwritten. Improvements to the generic header of a filled-in launch/teardown script reach an adopter only when an agent merges it by hand (Alternative 8).

6. **Parent-side placement under split layout.** The scripts and `slots.yaml` are seeded at **`$PROJECT_DIR/scripts/`** and **`$PROJECT_DIR/docs/dev/slots.yaml`** — the parent under split layout ([FWADR-021](fwadr-021-split-layout.md)), NOT inside `$CODE_ROOT`. They are agent-orchestration artifacts and belong with the tracking tree; about the only deploy-shaped thing in `$CODE_ROOT` is CI config. Agents invoke them with `$PROJECT_DIR` as the working directory (CWD-relative paths internally). Full rule: [FWADR-021](fwadr-021-split-layout.md) §"Script placement doctrine".

7. **Project variables live in the operator `.env`; the Strategist sets them.** `$PROJECT_DIR/.env` is the canonical machine source for `PROJECT_SUB`, `PROJECT_PORTS`, `DEFAULT_CODE_SUBDIR`, and the other project variables; scripts source it rather than parsing CLAUDE.md. It is created from the synced `$PROJECT_DIR/.env.example` (PLACEHOLDER values + comments) at first contact. CLAUDE.md shows the same values inline as the human-readable mirror, kept in sync by Strategist discipline and the §"Stub audit" `.env`↔CLAUDE.md drift row. Port allocation is a cross-project resource decision, so the Strategist owns it in the first-contact interview ([`strategist.md`](../strategist.md) §"First-contact interview"), filling `.env` and CLAUDE.md together. **The interview proposes, not asks** ([`templates/first-contact-interview.md`](../templates/first-contact-interview.md) Block 1): it runs `./scripts/port_ledger.sh --propose` from `$PROJECT_DIR` and offers the result as a yes/no. Remote-hosted projects have no local Caddyfile; the interview asks for the range directly. The setup-script halt is the forcing function: no local runtime until the interview is done.

8. **QA target is the slot hostname when `http_surface: true`.** `developer.md` §Build: QA targets `https://<slot>.<sub>.localhost/` via Caddy, not `localhost:<port>`; if the slot lacks a Caddy block, re-run `./scripts/setup_dev_slots.sh` from `$PROJECT_DIR`. The Parallel Developer may launch from inside the worktree (auto-detect) or from `$PROJECT_DIR` with `--wid=W-NN`. The Reviewer enforces it (below). QA exercises the prod-shaped path through the proxy — host header, TLS, cookie domains — not the raw bind port.

### Production-deploy doctrine (carve-out)

CLAUDE.md §"Two process rules" #2 (production changes land via the release push → CI; never from a laptop, never via `docker exec`) remains the **default rule for every adopter**. Most projects should never fill in `main_to_prod.sh` — its `exit 1` stub state is the correct steady state for a CI-deployed project.

For the small number of projects where the user has explicitly approved direct-to-server deploy (legacy infrastructure, no CI runner, niche hosting), `main_to_prod.sh` is the **named, single, canonical entry point**:

- The default rule is unchanged: CI is how production gets updated.
- When the user has approved direct-deploy, `main_to_prod.sh` is the only path. Improvisation outside it is a Reviewer-blocking violation.
- A filled-in `main_to_prod.sh` in the project repo is the implicit signal that the user approved this exception. A still-stub one means CI-only is in force.

### Reviewer-side enforcement

The Reviewer brief (`docs/dev_framework/templates/reviewer-brief.md`) carries two rules from this ADR:

> If a commit message, diff, or work history shows a production deploy executed by any path other than `scripts/main_to_prod.sh` (e.g., raw `ssh user@host docker pull`, ad-hoc `kubectl apply`, manual `pm2 restart` on the prod server), verdict is **block**. The Reviewer flags this even if the deploy succeeded — the doctrine violation is the issue, not the outcome.

Without it, `main_to_prod.sh` becomes one of several deploy paths in practice and the consistency win evaporates.

**QA target (conditional):** if `slots.yaml` has `http_surface: true` AND the working log or diff shows the QA loop targeted raw `localhost:<port>` for an HTTP surface, the Reviewer flags **MED**. The rule no-ops when `http_surface` is `false` or `PLACEHOLDER`.

## Consequences

**What this buys:**

- **Deploy commands are scoped once per project, not every session.** After the launch/teardown bodies are filled, "launch dev0" is one shell command.
- **Consistent slot allocation across sessions.** Default Developer always gets dev0; Parallel Developers get dev1+ in order. Container names, ports, and hostnames are stable.
- **Friendly hostnames without `/etc/hosts`.** The user QAs at `dev0.<sub>.localhost` instead of `localhost:3060`.
- **Wrong-source launches caught before launch, not during QA.** The confirmation block surfaces source, mode, and branch+SHA up front.
- **Port ranges proposed from a ledger, not memory.** Cross-project collisions surface at setup and in the interview.
- **Named escape hatch for direct-deploy projects.** A single canonical command instead of improvised ssh sessions, auditable by the Reviewer.
- **Setup is interactive but one-shot.** `setup_dev_slots.sh` is the only place that updates `slots.yaml` and the Caddyfile in lockstep.

**What this costs:**

- **More framework surface.** Seven seeded files (five scripts, `slots.yaml`, `.env.example`) ship to every adopter. Mostly small self-documenting stubs; the cost is cognitive plus one-time setup.
- **Caddy as a dependency.** Without Caddy, slots and scripts still work but friendly hostnames don't — QA hits `localhost:<port>` directly. Documented in `dev-environment.md`; not framework-blocking.
- **Ruby dependency for yaml parsing.** Scripts use `ruby -e` to read `slots.yaml` (matches codex; on macOS by default and widely available on Linux). Adopters without ruby swap in `yq` or another parser.
- **Filled-in stubs become project assets.** Launch/teardown bodies are project-specific code committed to the project, like any infrastructure-as-code.
- **Generic plumbing does not auto-propagate** to adopters with filled bodies (Decision #5).
- **First-launch TLS friction.** `caddy trust` is one extra first-time step, documented in setup output.
- **The ledger is a machine-local file outside every project.** Its accuracy depends on every project on the machine having run setup.

**What this does NOT do:**

- **Does not change the production-deploy default.** CI-only remains the rule; `main_to_prod.sh` is for projects that have already opted out by user decision and does not encourage opting out.
- **Does not change the Developer's QA-loop pattern.** User-mediated QA inside `in_progress` ([FWADR-018](fwadr-018-developer-role.md)) is unchanged; slots give it a stable hostname/port.
- **Does not change Orchestrator-mode dispatch.** Executor subagents in worktrees can use slots, but the mechanism is Developer-centric — the QA loop assumes a persistent session.
- **Does not auto-fill the launch/teardown bodies or `extras`.** Fundamentally project-specific; filled once on first use, then the script is the canonical entry point.

## Alternatives considered

1. **Codex's pattern as-is (no setup script, no Caddy).** Rejected — codex hard-codes ports 3060–3063 and leaves hostname routing to the adopter. `{{ports}}` is project-specific (no universal default), and the user wanted Caddyfile auto-configuration. The adapted pattern adds the setup ritual on top of codex's slot+stub shape.

2. **Skip Caddy; use raw `localhost:<port>` for QA.** Rejected — the user QAs against URLs that look like the product (cookie domains, CORS, OAuth redirects depend on hostname). Caddy + `.localhost` cost a one-time `caddy trust` and earn realism for every QA session.

3. **`/etc/hosts` + non-`.localhost` suffix (e.g., `.local`, `.test`).** Rejected — `.localhost` auto-resolves per RFC 6761, eliminating the `/etc/hosts` step. The user chose this in design for that property.

4. **Uniform seed-once sync for every script.** Rejected — no fix to generic plumbing would ever reach an existing adopter; a plumbing bug strands every project until each re-pulls by hand. Its argument was cognitive load ("which scripts do I edit? which get overwritten?"); the FRAMEWORK-OWNED header answers that inside the file itself, so mixed semantics cost nothing to read ([FWADR-014](fwadr-014-framework-sync-on-session-start.md) §"Stub scripts").

5. **Single ADR for both the slot registry and the production-deploy carve-out vs. two ADRs.** Single ADR wins — the carve-out is a doctrine adjustment driven by introducing `main_to_prod.sh`, not an independent decision. Two ADRs would force a forward reference from the deploy-doctrine ADR to the slot-mechanism ADR.

6. **Fold setup into `sync-framework.sh` (run setup automatically on first sync).** Rejected — setup is interactive (range confirmation, HTTP-surface question, base port, Caddyfile write). From a SessionStart hook it would block the session on input, or skip prompts and use defaults that may collide. An explicit user-invoked script preserves "first sync seeds, user runs setup once."

7. **A `--migrate` flag for slots whose `port` held a non-HTTP port.** Rejected — the fix is moving the old value under `extras` and setting `port` to the HTTP port, two YAML edits per slot; automating it would be more code than the manual fix.

8. **Above-sentinel partial re-sync of launch/teardown stubs.** Stubs would carry a sentinel line (e.g. `# ============ PROJECT-SPECIFIC LAUNCH BODY (do not edit above) ============`) and `sync-framework.sh` would re-drop the above-sentinel generic plumbing into adopters with customized bodies, closing the remaining propagation gap for filled-in launch/teardown scripts. Deferred — whether the sync hook gets smarter about stubs is its own doctrine decision and its own ADR. The current comment-block marker form stays.

9. **Ask the user for a port range in the interview.** Rejected for local-hosted projects — it relies on the user remembering every other project's ports, and the Caddyfile already holds that answer (see Context). Proposing from `port_ledger.sh` replaces recall with a read.

## Acceptance criteria

The surfaces that must stay coherent with this ADR:

- `docs/dev_framework/_stubs/scripts/{setup_dev_slots,port_ledger,launch_local,teardown_local,main_to_prod}.sh` — `bash -n`-clean, executable, generic plumbing filled per Decision #3, project bodies stubbed behind the `PROJECT-SPECIFIC … BODY` marker.
- `docs/dev_framework/_stubs/docs/dev/slots.yaml` — `dev0`–`dev3`, `port: 0` / `hostname: PLACEHOLDER` until setup, header defining `port` as HTTP/Caddy-routed, `http_surface: PLACEHOLDER`, commented `extras` example.
- `docs/dev_framework/_stubs/.env.example` — project variables (`PROJECT_NAME`, `PROJECT_SUB`, `PROJECT_WEBSITE`, `PROJECT_PORTS`, `DEV_ENVIRONMENT_MODE`, `DEFAULT_CODE_SUBDIR`, `CLAUDE_TEMPLATE_ROOT`) as PLACEHOLDER + comments.
- `.claude/hooks/sync-framework.sh` — stub list covers all seeded files, framework-owned ones overwritten on difference (Decision #5); `.gitignore` includes `.local/`.
- `docs/dev_framework/dev-environment.md` §"Port allocation (local-hosted)" and §"Slot registry and launch scripts" describe the ledger, slots, flags, resolver order, confirmation block, and app-env symlink.
- `docs/dev_framework/developer.md` — §Build launches via `./scripts/launch_local.sh dev<N>` (worktree or `--wid`), QA-target rule; §"Cleanup at done-flip" tears down via `teardown_local.sh` (which also prompts; `--auto-confirm` for scripted use only). Discipline: a still-stub script means halt, fill it in, commit — no improvised docker.
- `docs/dev_framework/templates/reviewer-brief.md` — both rules in §"Reviewer-side enforcement".
- `docs/dev_framework/strategist.md` §"First-contact interview" + `templates/first-contact-interview.md` Block 1 — `.env` + CLAUDE.md fill, ledger-proposed range; stub-audit rows for `.env` PLACEHOLDERs and `.env`↔CLAUDE.md drift.
- `CLAUDE.md` — Commands rows for the setup/launch/teardown/deploy scripts; §"Two process rules" #2 names `main_to_prod.sh` as the direct-deploy escape hatch.
