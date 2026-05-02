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
