# Dev environment

How this project's integration-branch code (`dev`, or `main` under `GIT_FLOW=trunk` — session-policy §"Branching and isolation") becomes something a QA subagent can test. Every project running on this template picks one of two modes; the rest of the framework stays identical either way.

## Naming convention (fixed)

The dev URL is always `{{sub}}.dev.{{website}}.com` where:
- `{{sub}}` — this project's subdomain (project-scoped; set in CLAUDE.md)
- `{{website}}` — the shared parent domain (org-scoped)

Example: `myapp.dev.draglabs.com`. Every project that uses this template follows the same shape so the Strategist and QA always know where to point without a per-project lookup.

## The two modes

| | **Local-hosted dev** | **Remote-hosted dev** |
|---|---|---|
| Where dev runs | User's machine | A real server (VPS, Fly, Cloudron, …) |
| Push to the integration branch (`dev` / `main` under trunk) | No deploy. User runs `docker compose up` locally. | CI deploys to the dev server. |
| QA target | `{{sub}}.dev.{{website}}.com` (resolves to localhost via local redirect) | `{{sub}}.dev.{{website}}.com` (resolves to dev-server IP via wildcard DNS) |
| Infra cost | Zero beyond user's machine | A server + DNS + CI deploy path |
| When to pick | Solo dev, early stage, iteration-heavy | Multiple contributors, stable architecture, QA needs to run while laptop is closed |

The choice is an ADR — see `docs/architecture/stack.md` "Dev environment hosting" row.

## Branch flow (both modes)

```
┌────────────────────────┐
│  feature branch        │
│  w-<id>/<slug>         │
└────────────┬───────────┘
             │ Orchestrator merges after Executor pass
             ▼
┌────────────────────────┐        CI on push:
│  dev                   │  ───▶  LOCAL:  no deploy (user runs locally)
│                        │  ───▶  REMOTE: deploy to dev server
└────────────┬───────────┘
             │ Phase-boundary promotion
             │ (user/Strategist authorizes after QA passes on dev)
             ▼
┌────────────────────────┐        CI on push:
│  main                  │  ───▶  deploy to production
└────────────────────────┘
```

## Orchestrator's role in first-time setup

On a fresh project, the first-time dev-environment setup is **bootstrap work, not a W-item**. The Orchestrator runs it directly — one-time orientation with no diff to produce — similar to how 🔍 spikes are handled. No Executor dispatch, no Reviewer gate.

The trigger: user starts the first Orchestrator session, says "set up the dev environment." Orchestrator reads this doc and the ADR, then walks the user through the chosen mode.

### Local-hosted bootstrap walkthrough

The goal: `curl https://{{sub}}.dev.{{website}}.com` from the user's laptop hits the local dev server.

1. **Confirm project variables.** Read `{{sub}}`, `{{website}}`, and `{{ports}}` from CLAUDE.md. If any are still placeholders, prompt the user to fill them in first — `{{ports}}` is allocated by the user (e.g. `3050-3060`) so different projects on the same laptop don't collide. See §"Port allocation (local-hosted)" for the binding + teardown discipline.
2. **Pick a DNS strategy.**
   - **Option i — `/etc/hosts` entry.** Simplest. Add `127.0.0.1  {{sub}}.dev.{{website}}.com` to `/etc/hosts`. Works, but each new subdomain needs a new entry. Good for single-project.
   - **Option ii — wildcard via local DNS.** Tools like `dnsmasq` (Linux/macOS) or `Acrylic` (Windows) resolve `*.dev.{{website}}.com` → `127.0.0.1`. Better when the user works on multiple projects under the same `{{website}}`.
   - **Option iii — owned domain with DNS wildcard.** If the user owns `{{website}}.com` at a registrar, add a `*.dev` wildcard A record → `127.0.0.1`. Works from anywhere with no local config, but exposes project names in DNS queries.
3. **Set up TLS (if HTTPS needed).** `mkcert` is the standard. Install mkcert, run `mkcert -install`, then `mkcert "{{sub}}.dev.{{website}}.com" "*.dev.{{website}}.com"` for a local-trusted cert. Put the cert + key somewhere the reverse proxy reads them.
4. **Reverse proxy routing.** If multiple projects share the `.dev.{{website}}.com` parent, use a single Caddy/Traefik/nginx config at e.g. `:443` that routes each subdomain to the matching project's local port. Example Caddy:
   ```caddy
   {{sub}}.dev.{{website}}.com {
     tls /path/to/cert.pem /path/to/key.pem
     reverse_proxy localhost:3000
   }
   ```
   For a single project, the app itself can bind to `:443` with the cert and skip the proxy.
5. **Smoke test.** `curl -k https://{{sub}}.dev.{{website}}.com/` should return the hello-world response once the stub is running. If it doesn't, debug before declaring setup done.
6. **Document.** Orchestrator adds a short "Local dev redirect is configured via X (hosts file / dnsmasq / wildcard DNS)" note to the ADR so future sessions know the specifics.

### Remote-hosted bootstrap walkthrough

The goal: `curl https://{{sub}}.dev.{{website}}.com` from anywhere hits the remote dev server, fresh with whatever was last pushed to `dev`.

1. **Confirm project variables** (same as local, step 1).
2. **Dev server provisioned.** If one doesn't exist, that's a prerequisite — escalate to user. Don't provision infrastructure from the Orchestrator; this is a one-time user decision, often involving billing.
3. **Wildcard DNS.** `*.dev.{{website}}.com` → dev-server IP, at the registrar or DNS provider. Orchestrator can confirm via `dig` but doesn't edit DNS records.
4. **TLS certificate.** Let's Encrypt wildcard (`*.dev.{{website}}.com`) via DNS-01 challenge. Caddy/Traefik on the dev server handles this automatically if pointed at the right DNS provider API.
5. **CI deploy to dev.** Add a CI workflow on the project's git host (GitHub Actions, GitLab CI, or equivalent — per `GIT_HOST`): on push to the integration branch (`dev`; `main` under trunk), build the image and deploy to the dev server. Production deploys on push to `main` (dev-main) or on a `v*` tag (trunk). Runner tags and the pipeline shape follow §"CI runners": the deploy job runs on the ephemeral runner host and reaches dev over SSH with a deploy key held as a protected CI variable; its last step runs the dev harness (Tier 2) on dev — §"Test tiers and the dev harness". Exact deploy mechanism is project-specific (rsync + systemctl, `docker pull` on server, Cloudron app update, …). Record the chosen mechanism in the ADR, and run `./scripts/check-ci-placement.sh $CODE_ROOT` before the first push.
6. **Smoke test.** Same as local — `curl` the URL, expect hello world. CI passing is not sufficient; confirm the URL actually serves the current dev commit and the harness page at `/__dev/` loads.
7. **Document.** Orchestrator adds deploy mechanism + server identity to the ADR.

## Why the Orchestrator (not an Executor) for bootstrap

Under peer dispatch, the Orchestrator dispatches Executors for all code work. Bootstrap is different:

- **Interactive with the user.** The Orchestrator is already in conversation with the user; an Executor subagent isn't. Setup requires back-and-forth ("which DNS strategy?", "do you want mkcert or real LE?") that a one-shot Executor brief can't handle.
- **No diff to produce.** Most of the setup is system-level config outside the repo (`/etc/hosts`, DNS records, certificate files). The Executor pattern assumes "write to worktree, commit, review" — not applicable here.
- **One-time.** Amortize the cost across the entire project, not per-W-item.

Same reasoning as 🔍 spikes: research-flavored work with no diff, run by Orchestrator directly. The first-time dev-environment setup is documented in the project's first ADR(s) so it's not lost.

## After bootstrap: routine dev-branch operation

Once set up, dev is just another branch in the flow. The Orchestrator's STEP 4 merges feature branches to `dev`. Phase exit QAs against `{{sub}}.dev.{{website}}.com`. Promotion to main happens when the user authorizes at the phase boundary.

The user doesn't interact with dev-environment details again unless:
- A new subdomain is needed (spawns a mini-bootstrap).
- The local redirect breaks (usually `/etc/hosts` edit was lost, or DNS changed).
- The remote dev server goes down (different kind of problem — probably escalate to the user).

## Port allocation (local-hosted)

Each project gets a fixed port range at first-time setup, recorded as `{{ports}}` in CLAUDE.md (e.g. `3050-3060` or `305*`). Local dev runtimes — Docker containers, native dev servers (`npm run dev`, `vite`, etc.), reverse proxies — bind within that range and nowhere else. The reverse-proxy config in §"Local-hosted bootstrap walkthrough" step 4 maps the project's subdomain to a chosen port within the range.

**Why a range, not a single port.** Parallel work. The Default Developer, a Parallel Developer working a different W-item, and a one-off smoke-test container can each claim a different port within the range without colliding. Ten ports per project covers any realistic level of parallel local activity on one laptop.

**The Caddyfile is the machine-wide ledger.** Every project's `setup_dev_slots.sh` writes a `# BEGIN <sub>-dev-slots … PORTS=<range> PROJECT=<name> DIR=<path>` block to the local Caddyfile — comment-only when the project has no HTTP surface — so one file records which ranges are taken by whom. `scripts/port_ledger.sh` reads it: bare, a table plus cross-project overlap warnings; `--propose [N]`, the lowest free decade-aligned range above 3000 that also avoids well-known defaults (3000, 5000, 8080, …); `--check LOW-HIGH`, exit 2 on collision (`setup_dev_slots.sh` runs this before writing). The interview proposes from it rather than asking ([FWADR-019](adrs/fwadr-019-dev-slots-and-deploy-stubs.md) Decisions 2–3).

**Allocation is fixed for the project's lifetime.** The range is proposed by the ledger and confirmed by the user at first-time setup so different projects on the same laptop don't collide. Moving it after the fact requires updating reverse-proxy configs, `mkcert` certs, and any hardcoded references — possible but not free, so pick a range that won't conflict with existing tools (avoid `3000`, `8000`, `8080` defaults if those are already in use elsewhere).

**Per-W-item binding + teardown.** When a Developer (Default or Parallel) brings up a local runtime to drive the user-QA loop, it picks a port within `{{ports}}`. When the W-item ships through to `done`, the runtime is torn down — see [`developer.md`](developer.md) §"Cleanup at done-flip". Leaving containers running between W-items accumulates resource residue and burns port slots the next session expects to be free.

## Slot registry and launch scripts

[FWADR-019](adrs/fwadr-019-dev-slots-and-deploy-stubs.md) mechanizes the port-allocation discipline above into a committed slot registry plus four scripts. After first-time setup, the Developer launches and tears down local runtimes by **slot name**, not by manually-chosen port.

**Slot registry** at `docs/dev/slots.yaml` — committed; defines four named slots:

- **`dev0`** — Default Developer's slot (coordination, hot-fixes, neutral runtime; `worktree_required: false`).
- **`dev1`, `dev2`, `dev3`** — Parallel Developer slots (formal ticket work; `worktree_required: true`).

Each slot carries a `hostname` (`<slot>.{{sub}}.localhost`, auto-resolves via RFC 6761), a `port` within `{{ports}}`, a `role`, and an `intended_use` array.

**Live state** at `.local/dev_slots/<slot>.yaml` — gitignored; written by `launch_local.sh` when a slot is claimed, removed by `teardown_local.sh`. Captures which W-item / ticket currently holds the slot.

**Four scripts in `scripts/`:**

- **`setup_dev_slots.sh`** — one-time, interactive. Checks `PROJECT_PORTS` against the ledger, asks for base port, fills in `slots.yaml` (hostnames + ports), generates and (with confirmation) appends a Caddy block with the ledger header to your Caddyfile (comment-only for non-HTTP projects). Re-runnable; updates between `# BEGIN <sub>-dev-slots` / `# END <sub>-dev-slots` markers. Does NOT edit CLAUDE.md — `{{ports}}` lives inside the framework-managed block which gets overwritten on every sync (per [FWADR-014](adrs/fwadr-014-framework-sync-on-session-start.md)); `slots.yaml` is the authoritative source of truth.
- **`launch_local.sh <slot> [--wid=W-NN] [--auto-confirm] [--code-path=PATH]`** — resolve the code source, print a pre-launch confirmation block, claim the slot, then run the project-specific launch body (Docker run, dev server, etc.). Slot-claim + source-resolution + confirmation plumbing pre-filled; the launch body itself is a stub on first sync — fill it in once per project, then commit. The confirmation block (source path, mode, branch+SHA, port, hostname, .env state, `Proceed? [Y/n]`) is the load-bearing safety primitive: it exists because a worktree-CWD launch once silently brought up the main checkout instead, and the operator only noticed during QA. Surfacing source before launch turns that class of failure into "discover before launch." `--auto-confirm` skips the prompt for CI / scripted use. `CODE_PATH` resolves in this order: `--code-path` flag → `CODE_PATH` env var (backwards-compat) → `--wid=W-NN` (worktree match under `/tmp/worktrees/<DEFAULT_CODE_SUBDIR>/<wid>-*`) → `git rev-parse --show-toplevel` from `$PWD` → `$PROJECT_DIR/$DEFAULT_CODE_SUBDIR` fallback. Worktrees that lack a `.env` are auto-symlinked from the canonical app `.env` at the main checkout. `DEFAULT_CODE_SUBDIR` is sourced from `$PROJECT_DIR/.env` per [FWADR-021](adrs/fwadr-021-split-layout.md) — no manual stub edit at init.
- **`teardown_local.sh <slot> [--auto-confirm]`** — print a confirmation block mirroring launch (source, mode, branch+SHA, port, hostname), then run the project-specific teardown body, then remove the slot's state file. Same stub-and-fill shape. State file at `.local/dev_slots/<slot>.yaml` carries `code_path`, `mode`, `branch`, `sha` (written by launch); the project-specific body appends and reads its own fields (e.g. `compose_project`, `compose_file`).
- **`main_to_prod.sh`** — named escape hatch for user-approved direct-deploy projects. Most projects keep this as a stub (CI-only remains the default per CLAUDE.md §"Two process rules" #2).

**Caddy reverse-proxies** `<slot>.{{sub}}.localhost` → `localhost:<port>`. The `setup_dev_slots.sh` script generates the Caddyfile block. First-time TLS: run `caddy trust` once to suppress browser cert warnings on `.localhost` hosts.

**Sync semantics.** All four scripts and `slots.yaml` ship as **idempotent-init stubs** under `docs/dev_framework/_stubs/` in the canonical template ([FWADR-014](adrs/fwadr-014-framework-sync-on-session-start.md) sync flow). First sync copies them; subsequent syncs leave the adopter's filled-in versions alone.

**Discipline.** When a script is still a stub (exit-1 with "PROJECT-SPECIFIC ... is not implemented yet"), halt — fill it in and commit before launching. Never improvise `docker run` or `docker stop` outside the scripts. The Reviewer enforces the same rule for `main_to_prod.sh`: any prod-deploy commit by a path other than `main_to_prod.sh` is a `block`.

## CI runners

**Every runner lives on the ephemeral host (`SERVER_EPHEMERAL`); dev and prod run none** ([FWADR-037](adrs/fwadr-037-ci-runner-topology.md)). Runners are split by **job kind**, never by project. Hosted runners (github.com) are already off-box per-job containers; for them only the database rules below apply.

| Job kind | Tag | Executor | Reaches the target by | Refs |
|---|---|---|---|---|
| verify / test / lint / build | `docker` | docker, `image:` pins the toolchain | — | any |
| deploy | `deploy` | shell on ephemeral | SSH with a deploy key from a protected, masked CI variable | protected only (`main`, `dev`, `v*`) |
| *(transitional)* | `ephemeral-shell` | shell on ephemeral | — | any; reported by the check, migrate to `docker` |

**What a runner runs.** Tier 1 tests (§"Test tiers and the dev harness"), lint, typecheck, diff/consistency analysis, image build. **A CI job never starts a database and never reaches one** — not `services:`, not `docker run postgres`, not a connection string to dev's instance, not a tunnel. Reaching dev's Postgres from a runner was built and measured: 93,029 statements × a 107 ms network round trip ≈ 3 hours per run, against 19 minutes co-located.

Per-project `.gitlab-ci.yml` shape:

```yaml
verify:app:
  tags: [docker]
  image: python:3.12-slim          # real image; the executor honours it
  script: [pytest -m tier1 -n auto]   # Tier 1 only, in parallel; no services:, no database

deploy:dev:
  tags: [deploy]
  resource_group: production       # same-project deploys serialize; others run alongside
  rules: [{ if: $CI_COMMIT_BRANCH == "dev" }]
  script:
    - ssh deploy@$SERVER_DEV 'cd /srv/app && ./deploy.sh'
    - ssh deploy@$SERVER_DEV 'cd /srv/app && scripts/dev_harness.sh'   # Tier 2 runs here, on dev
```

**Mechanism:** `./scripts/check-ci-placement.sh <repo>` (framework-owned) FAILs on `self-hosted`, on an untagged job, on a datastore under `services:` or in a `docker run` line, and on a non-deploy job that names a database connection (`*DATABASE_URL`, a `postgres://`-style URL, `psql`, an `ssh -L` tunnel); WARNs on `ephemeral-shell` and on a deploy job that never calls the harness. SessionStart runs it for every code repo and emits a NOTICE while CI is unmigrated; the Reviewer runs it on any pipeline diff and each FAIL is a `block`; the first-contact interview runs it so a new project starts compliant. Runner registration and capacity (`concurrent`, per-runner `limit`, `request_concurrency`) are server state owned by the user, recorded in the project's deploy README.

## Test tiers and the dev harness

Every test declares its tier with a marker the project's test runner supports — a pytest marker, a jest project or tag, a Go build tag, a directory per tier. A test with no tier fails collection ([FWADR-037](adrs/fwadr-037-ci-runner-topology.md)).

| Tier | What it is | Where and when it runs |
|---|---|---|
| **1** | Fast, deterministic, no database, no network | CI, in parallel, on every push. The only tier CI runs. Budget: a few minutes. Target: at most about 5% of the project's test cases. |
| **2** | Needs the database or another service | On the dev site after each deploy: the deploy job's last step runs `scripts/dev_harness.sh` on the dev host; its exit code is the job's. |
| **3** | Slow, end-to-end, browser-driven | On the dev site, on demand or nightly. |

**The harness is a page.** Tier 2 and Tier 3 are code that runs on dev, against dev's own services and seed data. The dev site lists every Tier 2 and Tier 3 case at `https://{{sub}}.dev.{{website}}.com/__dev/`: run one or all from the page, last result per case, history, the deployed branch and commit. The user runs it from the browser; an agent runs it over HTTP and reads the result. Every run has a permanent URL. Building the tests into dev makes them visible by forcing function. The page exists on dev only — never in production. Local-hosted dev has no deploy step: the same harness runs against the local runtime.

**A runner is not an agent.** A CI runner runs Tier 1 and never reaches a database. An agent's own run environment — a chat session, a Paperclip agent host — may reach dev, and only dev, never production: it starts the harness, reads the results, and runs a Tier 2 or Tier 3 case it is writing against dev's services. Whole suites go through the harness, which runs next to the database.

**Done, for a code item:** merged → deployed to dev → harness green on the dev page → the link to that result posted on the item (the W-item, or the issue). The agent that merged checks its own deploy; it does not wait for a human to look. A red harness is that agent's to resolve before it takes the next item.

**Dev data.** The dev Postgres exists once, on dev, seeded with dummy data; migrations carry it forward. A wipe-and-reseed script, run by a human, is the rare reset.

`scripts/dev_harness.sh` ships as a seed-once stub; the project's own ADR fills the body, the page and the seed script.

## Dittofeed stack

Dittofeed is the standard lifecycle-email stack; each project runs its own compose stack (`dittofeed-lite`, Postgres, Temporal, ClickHouse). It is sized for ClickHouse, not for the tenant data ([FWADR-038](adrs/fwadr-038-dittofeed-stack-sizing.md)): under a 2 GiB cap ClickHouse crash-loops on its own trace logging, and the merge storm that follows a backlog needs headroom far above the ~1 GiB steady state.

| Service | `mem_limit` | `cpus` | Also |
|---|---|---|---|
| ClickHouse | ≥ 8 GiB | 3 | system-log override mounted (below) |
| `dittofeed-lite` | ≥ 1 GiB | 1 | |
| Postgres / Temporal | 512 MiB / 1 GiB | | measured, not floors |

Compose shape:

```yaml
clickhouse-server:
  image: clickhouse/clickhouse-server:24.12.6.70-alpine
  mem_limit: ${CLICKHOUSE_CONTAINER_MEM_LIMIT:?}m   # 8192
  cpus: 3
  volumes:
    - ./clickhouse-config/system-logs.xml:/etc/clickhouse-server/config.d/system-logs.xml:ro
```

The override file is copied from [`_stubs/dittofeed/clickhouse-system-logs.xml`](_stubs/dittofeed/clickhouse-system-logs.xml) — the file by name, never the whole `config.d` directory. On a stack that already runs, truncate `system.text_log` before recreating the container with the mount. `./scripts/check-ditto-stack.sh <compose-file>` checks all of this; the Reviewer runs it on any diff touching the stack's compose, and the deploy README runs it before `up -d`.

## Relationship to production

Dev and prod are separate CI workflows and separate URLs:

- Dev: `{{sub}}.dev.{{website}}.com` (local or remote)
- Prod: `{{sub}}.{{website}}.com` (the live URL from CLAUDE.md — no `dev` subdomain)

The "CI-only deploys" rule from CLAUDE.md applies to prod. Dev is whatever the mode says — local means "run it yourself," remote means "CI deploys on dev push." Both are allowed; neither counts as a prod deploy.

### Pointing prod at a non-main branch (escape hatch)

Sometimes WIP needs to be reachable at the prod URL before it's been promoted to `main` — usually because the work depends on prod-only data, integrations, or auth surfaces that dev doesn't carry. The "CI-only deploys to prod" rule still holds; what changes is the branch CI deploys *from*.

Discipline:

1. **Pre-flight.** User flips the branch CI deploys to prod from `main` → `dev` or `<feature>`. Whatever surface CI watches (workflow file, deploy config, manual trigger) is project-specific. Confirm the flip took effect at the prod URL before the Developer starts iterating.
2. **Work normally.** Developer (or Orchestrator) drives the W-item through its standard lifecycle. The user-mediated QA loop runs against the prod URL since that's where the WIP is now reachable. Plan-writes still go on `dev` per PLAN-WRITE DISCIPLINE — the prod-pointer flip changes deploy mechanics, not branching mechanics.
3. **Merge to `main`.** Standard Ship path: feature → dev → main, all via CI. The just-shipped work is now on `main`.
4. **Post-flight: flip back.** Switch CI's prod deploy branch back to `main`. **This is easy to forget** — if you skip it, prod silently keeps deploying dev/feature, and the next item that merges to `main` doesn't reach the live URL until someone notices the divergence.

Forcing function: the Developer's `Cleanup at done-flip` discipline (in `developer.md`) includes a prod-pointer check before the W-item closes. The Orchestrator's phase-exit promotion should do the same when a phase was driven under this escape hatch. Both ask the user directly because the CI surface is project-specific — the agent can't probe it generically.
