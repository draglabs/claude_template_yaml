# FWADR-037: CI runs on the ephemeral host and runs only deterministic checks

**Status:** accepted
**Date:** 2026-11-07
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

## Decision

1. **Every runner lives on the ephemeral host. Dev and prod run none.** This
   is the forcing function: with no runner on the deploy host, a deploy job
   cannot be a shell on that host — it runs on ephemeral and reaches dev or
   prod over SSH with a deploy key held as a **protected, masked CI variable**
   (exposed to protected refs only). The deploy host keeps nothing a runner
   needs beyond the deploy user's `authorized_keys`. Capacity is a number on
   the runner process (`concurrent`, per-runner `limit`), not a count of
   boxes.
2. **CI is deterministic only.** Lint, typecheck, unit tests, diff and
   consistency analysis, image build. **No datastore ever starts inside a CI
   job** — not `docker run postgres`, not `services: [postgres]`. The dev
   Postgres exists once, on the dev server, seeded with the project's dummy
   data; migrations carry it forward and a flush-and-reseed script is the
   rare reset. If a test has a specific, documented reason to touch Postgres
   from a runner, it **connects to the live dev instance** over the network
   (`DEV_DATABASE_URL` as a protected CI variable). It never stands up its
   own.
3. **Progressive and integration testing is a post-deploy harness on dev.**
   The deploy job's final step runs the code repo's `scripts/dev_harness.sh`
   on the dev host; its exit code is the job's. The harness uses dev's own
   services and dev's seed data. Dev, knowing it is dev, exposes the deployed
   branch and commit and the last harness report. Seeded stub ships with the
   framework; the body, the seed script and the report surface are the
   project's, decided in its own ADR.
4. **Tags.** Verify/build jobs: `docker` (docker executor, `image:` pins the
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
  untagged job, on a datastore under `services:` or in a `docker run` line;
  WARN on `ephemeral-shell` and on a deploy job that never calls the harness.
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
- **Named gap:** "a runner test that needs Postgres uses the live dev
  instance" is English-only — the check can see a datastore being *started*,
  not where a connection goes. Acceptable: the rare case is documented in the
  job and the Reviewer reads it.
- **Security shape changes.** Deploy keys move from the deploy host's runner
  user to protected CI variables; the disposable box holds them only for the
  duration of a protected-ref job. A compromised MR job on ephemeral reaches
  ephemeral's Docker daemon, not dev's.
- **Host-neutral.** github.com hosted runners are already per-job containers
  off every box of ours; only the datastore rule applies to Actions files.
- **Coherence surfaces:** this ADR; [`dev-environment.md`](../dev-environment.md)
  §"CI runners" and step 5; `templates/reviewer-brief.md`;
  `templates/first-contact-interview.md` Block 1; `sync-framework.sh` 5c/5e;
  stubs `check-ci-placement.sh`, `dev_harness.sh`.
