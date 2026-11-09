# FWADR-037: CI runs on the ephemeral host and runs Tier 1 only; Tier 2 and 3 are the dev harness

**Status:** accepted
**Date:** 2026-11-08
**Deciders:** user (framework author) + Template Developer

## Context

Until 2026-10 every project's CI ran on one shell runner on the shared
dev/prod Docker host: 2–21 minute queues, `image:`/`services:` ignored, MR
jobs from any branch running as the deploy user. The 2026-10-12 fix split
runners by job kind but kept them on the same box. Measured again on
2026-11-07: the dev host was still carrying every runner, verify jobs were
competing with the dev-grade sites for CPU, and every DB-backed verify job in
seven repos was starting its own Postgres inside the job (`docker run
pgvector/pgvector:pg16`, random ports, orphan sweeps in `before_script`).
makinrate's 1454-test jest suite timed out when six jobs shared the box. The
user's direction: CI runs basic, deterministic checks and gets the build onto
dev; the elaborate testing runs on dev once the deploy lands; nothing in CI
competes with dev or prod for a processor. A disposable 8-core box,
**ephemeral** (`SERVER_EPHEMERAL` in every project's `.env` server table), now
exists for exactly this.

One escape was tried and measured: a runner test that needed Postgres
connected to dev's live instance over the network. thankmu built it. Its
suite issues 93,029 statements; each waited a 107 ms round trip between the
two hosts — about 3 hours per run, against 19 minutes co-located. A test that
needs a database is not a CI test.

## Decision

1. **Every runner lives on the ephemeral host. Dev and prod run none.** This
   is the forcing function: with no runner on the deploy host, a deploy job
   cannot be a shell on that host — it runs on ephemeral and reaches dev or
   prod over SSH with a deploy key held as a **protected, masked CI variable**
   (exposed to protected refs only). The deploy host keeps nothing a runner
   needs beyond the deploy user's `authorized_keys`. Capacity is a number on
   the runner process (`concurrent`, per-runner `limit`), not a count of
   boxes.
2. **CI runs Tier 1 only. A CI job never starts a database and never
   reaches one.** Not `docker run postgres`, not `services: [postgres]`, not a
   connection string to dev's instance, not a tunnel. Alongside Tier 1 a
   runner does lint, typecheck, diff and consistency analysis, and the image
   build.
3. **Three tiers; every test declares its tier** with a marker the project's
   test runner supports (a pytest marker, a jest project or tag, a Go build
   tag, a directory per tier). A test with no tier fails collection.
   - **Tier 1** — fast, deterministic, no database, no network. The only
     tier CI runs; run in parallel; budget a few minutes; target at most
     about 5% of the project's test cases.
   - **Tier 2** — needs the database or another service. Code that runs **on
     the dev site** after each deploy: the deploy job's last step runs the
     code repo's `scripts/dev_harness.sh` on the dev host; its exit code is
     the job's.
   - **Tier 3** — slow, end-to-end, browser-driven. Runs on dev, on demand
     or nightly.
4. **The dev harness is a page.** The dev site lists every Tier 2 and Tier 3
   case at `/__dev/`, runnable one-or-all from that page by the user or an
   agent, with the last result per case, history, and the deployed branch and
   commit; every run has a permanent URL. Building the tests into dev makes
   them visible by forcing function. The harness uses dev's own services and
   seed data: the dev Postgres exists once, on dev, seeded with dummy data;
   migrations carry it forward; a wipe-and-reseed script, run by a human, is
   the rare reset. The page exists on dev only. Seeded stub ships with the
   framework; the body, the page and the seed script are the project's,
   decided in its own ADR.
5. **A runner is not an agent.** The rule in 2 binds CI jobs. An agent's own
   run environment (a chat session, a Paperclip agent host) may reach dev —
   only dev, never production — to start the harness, read its results, and
   run a Tier 2 or Tier 3 case it is writing against dev's services. Whole
   suites go through the harness, which runs next to the database.
6. **Done, for a code item:** merged → deployed to dev → harness green on the
   dev page → the link to that result posted on the item or issue. The agent
   that merged checks its own deploy; it does not wait for a human to look.
7. **Tags.** Verify/build jobs: `docker` (docker executor, `image:` pins the
   toolchain). Deploy jobs: `deploy` (shell executor on ephemeral, protected
   refs only, `resource_group: production`). `ephemeral-shell` is
   **transitional** — right host, host toolchain implied — accepted and
   reported. `self-hosted` is the retired dev runner: no job carries it.
   Every job carries `tags:`; an untagged job lands on whichever runner takes
   untagged work, never on one we chose.

## Consequences

- **Mechanism:** [`check-ci-placement.sh`](../_stubs/scripts/check-ci-placement.sh)
  (framework-owned, synced into every adopter's `scripts/`) lints
  `.gitlab-ci.yml` and `.github/workflows/*`: FAIL on `self-hosted`, on an
  untagged job, on a datastore under `services:` or in a `docker run` line,
  and on a non-deploy job that names a database connection (`*DATABASE_URL`,
  a `postgres://`-style URL, `psql`, an `ssh -L` tunnel); WARN on
  `ephemeral-shell` and on a deploy job that never calls the harness.
  It runs at SessionStart for every code repo (`sync-framework.sh` emits a
  NOTICE while a project's CI is unmigrated), in the Reviewer brief as a
  `block` on any pipeline diff, and in the first-contact interview so new
  projects start compliant. This closes the lint gap the 2026-10 decision
  left open.
- **Named gap:** runner *placement* is server state the repo cannot see.
  Backstop: once the dev runners are deleted (paused as of 2026-11-07, to be
  removed), a `self-hosted` or untagged job sits `pending` with no runner,
  loudly, instead of running on the deploy host. Runner registration and
  capacity are recorded in the project's deploy README per
  [FWADR-019](fwadr-019-dev-slots-and-deploy-stubs.md).
- **Named gap:** the tier of a test is the project's to enforce — its
  runner configuration fails collection on an untiered test and its CI test
  command selects Tier 1. The framework's check reads pipeline files, not
  test files; the Reviewer blocks on a new test with no tier. The Tier 1
  share (about 5%) and time budget are targets, not checks.
- **Named gap:** "the agent that merged checks its own deploy" is
  English-only. The link on the item is the evidence; an item closed without
  one is visible to whoever reads it.
- **Security shape changes.** Deploy keys move from the deploy host's runner
  user to protected CI variables; the disposable box holds them only for the
  duration of a protected-ref job. A compromised MR job on ephemeral reaches
  ephemeral's Docker daemon, not dev's.
- **Host-neutral.** github.com hosted runners are already per-job containers
  off every box of ours; only the database rules apply to Actions files.
- **Coherence surfaces:** this ADR; [`dev-environment.md`](../dev-environment.md)
  §"CI runners", §"Test tiers and the dev harness" and step 5;
  `coding-standards.md` §"Test tiers and the CI gate"; `session-policy.md`
  §"Dispatch flow"; `developer.md` §"Code review"; `paperclip-mode.md`
  §"Tests and done"; `templates/reviewer-brief.md`, `executor-brief.md`,
  `integrator-qa-brief.md`; `templates/first-contact-interview.md` Block 1;
  `sync-framework.sh` 5c/5e; stubs `check-ci-placement.sh`, `dev_harness.sh`.
