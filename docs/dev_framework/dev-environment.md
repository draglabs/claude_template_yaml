# Dev environment

How this project's `main` becomes something a person and a QA subagent can test, how the person reviewing it on dev releases it, and how their feedback comes back. Every project has a dev mode, and every project running on this template picks one of two hosting modes for it; the rest of the framework stays identical either way.

## Naming convention (fixed)

The dev URL is always `{{sub}}.dev.{{website}}.com` where:
- `{{sub}}` — this project's subdomain (project-scoped; set in CLAUDE.md)
- `{{website}}` — the shared parent domain (org-scoped)

Example: `myapp.dev.draglabs.com`. Every project that uses this template follows the same shape so the Strategist and QA always know where to point without a per-project lookup.

## The two modes

| | **Local-hosted dev** | **Remote-hosted dev** |
|---|---|---|
| Where dev runs | User's machine | A real server (VPS, Fly, Cloudron, …) |
| Push to `main` | No deploy. User runs `docker compose up` locally. | CI deploys to the dev server. |
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
             │ one PR per finished W-item, merged on the git host
             ▼
┌────────────────────────┐        CI on push:
│  main                  │  ───▶  LOCAL:  no deploy (user runs locally)
│                        │  ───▶  REMOTE: deploy to dev server
└────────────┬───────────┘
             │ Approve in the QA view on dev
             │ (§"Release by approval": the release job cuts the tag)
             ▼
┌────────────────────────┐        CI on the tag:
│  release tag (v*)      │  ───▶  deploy to production
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

The goal: `curl https://{{sub}}.dev.{{website}}.com` from anywhere hits the remote dev server, fresh with whatever was last merged to `main`.

1. **Confirm project variables** (same as local, step 1).
2. **Dev server provisioned.** If one doesn't exist, that's a prerequisite — escalate to user. Don't provision infrastructure from the Orchestrator; this is a one-time user decision, often involving billing.
3. **Wildcard DNS.** `*.dev.{{website}}.com` → dev-server IP, at the registrar or DNS provider. Orchestrator can confirm via `dig` but doesn't edit DNS records.
4. **TLS certificate.** Let's Encrypt wildcard (`*.dev.{{website}}.com`) via DNS-01 challenge. Caddy/Traefik on the dev server handles this automatically if pointed at the right DNS provider API.
5. **CI deploy to dev.** Add a CI workflow on the project's git host (GitHub Actions, GitLab CI, or equivalent — per `GIT_HOST`): on push to `main`, build the image and deploy to the dev server. Production deploys on a release tag. Runner tags and the pipeline shape follow §"CI runners": the deploy job runs on the ephemeral runner host and reaches dev over SSH with a deploy key held as a protected CI variable (§"How a build reaches a host"); its last step runs the dev harness (Tier 2) on dev — §"Test tiers and the dev harness". The same change adds the QA view and the `release` job (§"The QA view", §"Release by approval"). Record the chosen mechanism in the ADR, and run `./scripts/check-ci-placement.sh $CODE_ROOT` before the first push.
6. **Smoke test.** Same as local — `curl` the URL, expect hello world. CI passing is not sufficient; confirm the URL actually serves the current dev commit and the harness page at `/__dev/` loads.
7. **Document.** Orchestrator adds deploy mechanism + server identity to the ADR.

## Why the Orchestrator (not an Executor) for bootstrap

Under peer dispatch, the Orchestrator dispatches Executors for all code work. Bootstrap is different:

- **Interactive with the user.** The Orchestrator is already in conversation with the user; an Executor subagent isn't. Setup requires back-and-forth ("which DNS strategy?", "do you want mkcert or real LE?") that a one-shot Executor brief can't handle.
- **No diff to produce.** Most of the setup is system-level config outside the repo (`/etc/hosts`, DNS records, certificate files). The Executor pattern assumes "write to worktree, commit, review" — not applicable here.
- **One-time.** Amortize the cost across the entire project, not per-W-item.

Same reasoning as 🔍 spikes: research-flavored work with no diff, run by Orchestrator directly. The first-time dev-environment setup is documented in the project's first ADR(s) so it's not lost.

## After bootstrap: routine operation

Once set up, dev follows `main`: every merged PR deploys there. The stakeholder reviews on `{{sub}}.dev.{{website}}.com`, works the checklist in the QA view, and approves the release from that page.

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
| deploy, release | `deploy` | shell on ephemeral | SSH with a deploy key from a protected CI variable | protected only (`main`, release tags) |
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
  rules: [{ if: $CI_COMMIT_BRANCH == "main" }]
  script:
    - deploy/remote-deploy.sh dev    # ships the image and the harness, runs deploy.sh then dev_harness.sh ON dev
```

**Mechanism:** `./scripts/check-ci-placement.sh <repo>` (framework-owned) FAILs on `self-hosted`, on an untagged job, on a datastore under `services:` or in a `docker run` line, and on a non-deploy job that names a database connection (`*DATABASE_URL`, a `postgres://`-style URL, `psql`, an `ssh -L` tunnel); WARNs on `ephemeral-shell` and on a deploy job that never calls the harness. SessionStart runs it for every code repo and emits a NOTICE while CI is unmigrated; the Reviewer runs it on any pipeline diff and each FAIL is a `block`; the first-contact interview runs it so a new project starts compliant. Runner registration and capacity (`concurrent`, per-runner `limit`, `request_concurrency`) are server state owned by the user, recorded in the project's deploy README.

## How a build reaches a host

The image is built on the ephemeral host and the deploy job, on the same host, ships it: `docker save | gzip | ssh | docker load`, skipped when the target already holds that image. No registry. The job then copies the repo's deploy files to the target and runs the repo's `deploy.sh` **there**, so every check (compose up, migrate, health, public name) is made on the host being deployed, by the same script in every environment. Dev and production use the same path; only the target differs.

- **Build and deploy run on the same host.** A build tagged for one host and a deploy tagged for another fails with "image not found"; `check-ci-placement.sh` does not see this, so the first deploy is the test.
- **Connection, per environment:** `<ENV>_SSH_PRIVATE_KEY` and `<ENV>_SSH_KNOWN_HOSTS` (file-type variables), `<ENV>_HOST`, `<ENV>_USER`; protected, scoped to that environment, strict host-key checking. They are `env.yaml` entries routed to that environment's CI place ([FWADR-041](adrs/fwadr-041-env-yaml.md)).
- **The target has a login, not a runner:** one deploy user per project, in the docker group, owning the project's deploy root, with the CI public key authorized.
- **The app env is written at deploy,** whole, from that environment's CI variables plus the committed non-secret settings; secrets travel on stdin, never argv.
- **A retried deploy may need a rebuild.** The ephemeral host prunes images daily.

Building the image where the deploy runs, or a registry, are a project's to choose instead; record it in the dev-environment ADR.

## The QA view

**Every project's dev site carries a QA view: the one place the stakeholder reviews what is deployed, sends feedback, and releases** ([FWADR-042](adrs/fwadr-042-qa-view-release.md)). It is hosted by the project's main app, on dev only, and covers every code repo of the project. A repo with no dev mode at all has no QA and does not use this; that is recorded as an exception in `dev_framework_exceptions.md`, with how it releases.

- **The way in is the QA bubble:** on dev, a circle labelled "QA" in the upper left corner of every page opens the view as an overlay over the page being reviewed; a detailed harness page it links into is a project's detail. In production it does not exist: `QA_VIEW` is a required setting, `on` or `off`, with no default.
- **How to build it** — the bubble, the page top to bottom, the three build steps, the exact file and comment formats and the test cases every project's parser passes — is [`qa-view-build.md`](qa-view-build.md). The framework describes it and ships no code.
- **What it shows, per repo, top to bottom:** the deployed commit and whether it is `main`'s head; **what was tested** — the harness result for that commit, every suite and case by its plain-language title, passed, failed or skipped (§"Test tiers and the dev harness"); **what changed** — the checklist, and the PRs merged since the last release, each linked, so work that agents merged on their own gates has one place to be reviewed; and what has already been said about the commit.
- **Two questions, two lists.** The harness answers "did anything important break"; nobody marks it. The checklist answers "is this what I asked for": it is the human's review of what changed, and it closes the feedback loop. A checklist item is never settled by a test.
- **The checklist** is `qa/checklist.yaml` in each code repo, read at the deployed commit. Every change adds the items the stakeholder should look at; an item names the W-item or issue it came from. The view shows everything not yet released: an item leaves when it is released approved, and nobody removes it by hand.
- **Three marks per item:** **approved**, **rejected**, **postponed** (a soft approval). Each can carry a note. There is also free feedback on the commit.
- **State lives on the commit, in the git host.** Every mark, note, harness result and approval is one comment on the commit whose first line is machine-readable: `qa:item <id> approved|rejected|postponed`, `qa:feedback [<id>]`, `qa:harness pass|fail|skip <run-url>`, `qa:approve <version>`. Marks count since the last release: the view reads the comments on every commit after the last release tag, and the latest mark on an item wins, so an approval survives the next merge's deploy. The latest `qa:harness` on the deployed commit is its result. Comments are how one view covers several repos: the app cannot read another repo's files on dev, but it reads any repo's commit. The app keeps no QA state, so there is nothing to migrate and agents read the same record.
- **The dev server's key cannot push.** It holds one token per repo with the lowest role that reads commits and writes comments. It cannot push, merge, tag or change settings.
- **Dev is behind a login.** `SITE_ACCESS` is a required setting, `restricted` or `open`. Dev is `restricted`: per-user passwords, so every mark records who made it. Machine callers (inbound webhooks, the harness, a client's dev build) are an explicit list of exempt paths in the repo, each with its caller named; the harness and each QA agent get a user of their own.

## Release by approval

**The release tag is cut on the git host when the stakeholder presses Approve in the QA view. Nobody pushes a tag: not an agent, not a laptop.**

1. **Approve is one deliberate action, and nothing blocks it.** It names the version (default: the next patch after the highest release tag). When something is unsettled — an item still open or rejected, a harness suite failed or skipped, no harness result for this commit, or dev not at `main`'s head — the view lists exactly what, and asks the stakeholder to confirm the release anyway. The approval comment records what was overridden. It is bound to the commit the page showed: if dev was redeployed in between, it is refused.
2. **Approval is a comment** (`qa:approve <version>`) on that commit. A webhook on comment events starts a pipeline on `main`.
3. **The `release` job re-checks everything itself** before it tags: the comment is an approval; its author is the QA token's own bot user; the commit is on `main`; nothing was marked and no harness result was posted after the approval; anything unsettled at that commit is named in the approval as overridden; the version is new and the commit carries no release tag. These checks establish that the approval is real and current; what to release is the stakeholder's call. Then it creates the annotated tag with a token only that job receives (protected, scoped to a `release` environment).
4. **The tag deploys production.** Each repo is released on its own tag; a repo declares its tag pattern when it is not `v*`.
5. **What was not approved carries over.** The approval names every item released while open, rejected or postponed (`carried:`); those stay on the checklist after the release, back at "to check".

Emergencies take the same path, faster: an expedited PR to `main`, dev deploys, Approve. If the QA view itself is down, the user creates the tag in the git host's own interface. The pre-push guard refuses every tag push and every direct push to `main` in a code repo, and has no bypass ([FWADR-023](adrs/fwadr-023-main-push-guard.md)).

## Feedback from the QA view

A rejection, a note and a failed harness suite are the same kind of event: this commit has something to fix, and why. Each is a comment on the commit, where every agent can read it. What turns them into work is the project's to build and is not yet proven anywhere: the intended shape is **one issue per approval round** listing every rejected item (each reopening the W-item or issue its checklist entry names) and every failed suite with its summary, never one run per comment. Until a project has that, the Strategist reads the commit's comments at session start and files the work.

## Test tiers and the dev harness

Every test declares its tier with a marker the project's test runner supports — a pytest marker, a jest project or tag, a Go build tag, a directory per tier. A test with no tier fails collection ([FWADR-037](adrs/fwadr-037-ci-runner-topology.md)).

| Tier | What it is | Where and when it runs |
|---|---|---|
| **1** | Fast, deterministic, no database, no network | CI, in parallel, on every push. The only tier CI runs. Budget: a few minutes. Target: at most about 5% of the project's test cases. |
| **2** | Needs the database or another service | On the dev site after each deploy, and on demand from the QA view. |
| **3** | Slow, end-to-end, browser-driven | On the dev site, on demand or nightly. |

**The harness shows what is tested, in words a stakeholder reads.** Every suite and case carries a plain-language title and one line saying what it checks ("Both sign-up question sets load", never a test id). The result for the deployed commit is the first thing on the QA view (§"The QA view"): what was tested, what passed, failed or was skipped, and a one-line reason written for a reader who has no log. It is on dev only — never in production. Local-hosted dev has no deploy step: the same harness runs against the local runtime.

**Two parts, by where they must run.**

| Part | What | Where it runs | Started by |
|---|---|---|---|
| Host checks | The deploy really served: health by loopback and by public name, the deployed commit, static assets present | A script on the dev host, shipped with the deploy payload | The deploy, as its last step on the target; its exit code is the job's |
| Tier 2 and Tier 3 cases | The project's own tests that need the database or a browser | **Inside the app**, from test code in the image | The deploy; and on demand through a dev-only endpoint — the stakeholder from the page, an agent over HTTP |

A page in a container cannot run a host script, so anything startable from the page lives in the app; that is the cost of test code and its dependencies in the image, accepted for dev.

**Three outcomes: pass, fail, skip.** A skip means "could not run" (a credential it was not given) and is shown as a skip, never counted green.

**Every run is recorded twice.** A report (commit, start, finish, per-suite status and summary) the page reads, written atomically; and a `qa:harness pass|fail|skip <run-url>` comment on the commit, posted with the dev server's comment-only key. Each run has a permanent URL: the link an agent posts as "done". A missing or malformed report is a state the page shows, never an error.

**The harness never deletes or flushes dev data,** every suite is time-bounded, and no secret reaches a report or a log.

**A runner is not an agent.** A CI runner runs Tier 1 and never reaches a database. An agent's own run environment — a chat session, a Paperclip agent host — may reach dev, and only dev, never production: it starts the harness, reads the results, and runs a Tier 2 or Tier 3 case it is writing against dev's services. Whole suites go through the harness, which runs next to the database.

**Done, for a code item:** merged → deployed to dev → harness green on the dev page → the link to that result posted on the item (the W-item, or the issue). The agent that merged checks its own deploy; it does not wait for a human to look. A red harness is that agent's to resolve before it takes the next item.

**Dev data.** The dev Postgres exists once, on dev, seeded with dummy data; migrations carry it forward. A wipe-and-reseed script, run by a human, is the rare reset.

`scripts/dev_harness.sh` ships as a seed-once stub for the host checks; the project's own ADR fills its body, the in-app runner, the page and the seed script.

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

The "CI-only deploys" rule from CLAUDE.md applies to prod. Dev is whatever the mode says — local means "run it yourself," remote means "CI deploys every merge to `main`." Both are allowed; neither counts as a prod deploy.

### Pointing prod at a branch (escape hatch)

Sometimes WIP needs to be reachable at the prod URL before it has been released — usually because the work depends on prod-only data, integrations, or auth surfaces that dev doesn't carry. The "CI-only deploys to prod" rule still holds; what changes is what CI deploys *from*.

Discipline:

1. **Pre-flight.** User flips CI's prod deploy from release tags to `main` or `<feature>`. Whatever surface CI watches (workflow file, deploy config, manual trigger) is project-specific. Confirm the flip took effect at the prod URL before the Developer starts iterating.
2. **Work normally.** Developer (or Orchestrator) drives the W-item through its standard lifecycle. The user-mediated QA loop runs against the prod URL since that's where the WIP is now reachable. Plan-writes follow PLAN-WRITE DISCIPLINE as usual — the prod-pointer flip changes deploy mechanics, not branching mechanics.
3. **Land and release.** Standard path: PR to `main`, then Approve in the QA view.
4. **Post-flight: flip back.** Switch CI's prod deploy back to release tags. **This is easy to forget** — if you skip it, prod silently keeps deploying a branch, and the next release tag doesn't reach the live URL until someone notices the divergence.

Forcing function: the Developer's `Cleanup at done-flip` discipline (in `developer.md`) includes a prod-pointer check before the W-item closes. The Orchestrator's phase exit should do the same when a phase was driven under this escape hatch. Both ask the user directly because the CI surface is project-specific — the agent can't probe it generically.
