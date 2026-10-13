# FWADR-037: CI runners split by job kind, not by project

**Status:** accepted
**Date:** 2026-10-12
**Deciders:** user (framework author) + Template Developer

## Context

Every active project on the user's self-hosted GitLab ran all of its CI on one
instance-level **shell** runner that lives on the shared dev/prod Docker host.
Measured on 2026-10-12: average job queue times of 2–4 minutes with peaks of
21 minutes; `image:` and `services:` silently ignored (shell executor), so
every project hand-rolled throwaway Postgres containers, orphan sweeps and
"host python is 3.10, fall back to `docker run`" workarounds; and every MR
pipeline from any branch ran as the deploy user with the Docker socket on the
production host. Options weighed: a runner per project (multiplies the same
shape, no isolation gain), an ephemeral autoscaling fleet (a cloud API and an
autoscaler for a handful of projects), or splitting runners by **what a job
does**.

## Decision

Runners are split by job kind. Parallelism is a number on the runner, not a
count of registrations.

- **CI runner — `docker` executor, tag `docker`.** Verify/test/lint jobs
  declare a real `image:`; dependencies such as Postgres come from
  `services:`, never from `docker run` inside the job. The host Docker socket
  is mounted so image builds work. Any ref may run here.
- **Deploy runner — `shell` executor on the deploy host, tag `deploy`,
  protected refs only.** One per *server*, not per project. Deploy jobs carry
  `resource_group: production` so two deploys of one project serialize while
  different projects run side by side.
- **Capacity:** process-wide `concurrent` sized so verify jobs can never
  starve deploys (currently 6 on a 12-core host, `limit = 2` per runner), and
  `request_concurrency = 2` per runner when several share one process — the
  runner's own journal warns about job-pickup delays otherwise.
- **No new job is written against the legacy `self-hosted` tag.** After every
  active project has migrated, the legacy runner becomes protected-refs-only
  and stops taking untagged work.

Registered as **group** runners (the operator token is a group owner, not an
instance admin); each group that holds code repos gets the pair.
[`dev-environment.md`](../dev-environment.md) §"CI runners" carries the
per-project `.gitlab-ci.yml` shape.

## Consequences

- **Mechanism:** the deploy rule is enforced by the runner itself
  (`access_level = ref_protected`, `run_untagged = false`); GitLab serializes
  `resource_group` jobs. **Named gap:** "verify jobs use `docker`, not
  `self-hosted`" is English-only until a `.gitlab-ci.yml` lint exists; the
  legacy-runner lockdown is the backstop (a mis-tagged MR job then sits
  `pending` with no runner, loudly, rather than running on the deploy host).
- **Blast radius is reduced, not removed.** On a single shared box the docker
  runner's socket mount still reaches the host daemon; the security gain is
  that MR jobs no longer run as the deploy user with the host filesystem. A
  separate CI box removes the rest.
- **Host-neutral in principle.** GitHub-hosted projects get this for free
  (hosted runners *are* per-job containers); self-hosted runners on either
  host follow the same split.
- **Coherence surfaces touched:** this ADR; `dev-environment.md` §"CI
  runners". The runner registrations themselves are server state, recorded in
  the project's deploy README per [FWADR-019](fwadr-019-dev-slots-and-deploy-stubs.md).
