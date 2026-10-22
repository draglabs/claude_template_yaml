# FWADR-038: Dittofeed stacks are sized for ClickHouse, not for the tenant data

**Status:** accepted
**Date:** 2026-10-22
**Deciders:** user (framework author) + Template Developer

## Context

Dittofeed is the standard lifecycle-email stack across the user's projects:
one compose stack per project (`dittofeed-lite`, Postgres, Temporal,
ClickHouse) on the shared dev/prod host. Four such stacks run there today.
Every one of them was first stood up with ClickHouse under a 2 GiB container
cap, which looks generous next to the tenant data it holds (11 MiB on the
largest, under 1 MiB on the others). Measured on 2026-10-22:

- **A 2 GiB ClickHouse crash-loops.** The one stack still at 2 GiB was
  kernel-OOM-killed 3,415 times in four days, one kill every ~90 seconds,
  even with ClickHouse's own memory ratio lowered to 0.7 and the mark cache
  bounded. Each boot schedules merges over the part backlog (two system
  tables held 9,000 and 6,400 parts), anonymous RSS reaches the cap, the
  kernel kills the server, the backlog grows. Its error log alone was 14 GiB.
  Dittofeed's compute-properties loop fails on every attempt, so segments and
  journeys silently stop updating.
- **The weight is ClickHouse's own logging, not Dittofeed.** The stock image
  writes `system.text_log` at trace level with no TTL. One stack reached
  24 GiB and 394 M rows of trace against 11 MiB of tenant data; two others
  sit at 18 and 8.5 GiB today. Under a small cap it feeds back on itself:
  memory errors write trace rows, trace-row merges eat the memory.
- **8 GiB plus the log override is calm.** The three stacks raised to 8 GiB
  (the first by trial on 2026-08-27, 2 → 4 → 8) have had zero kills since.
  Over 14 days their resident memory idles near 1 GiB and peaks at 1.4 GiB.
  The spike the cap must absorb is not daily load; it is the merge storm
  when a system-log backlog finally gets room — 7.5 GiB tracked on the one
  stack whose backlog was drained in place.

The fix was rediscovered independently in three projects over two months.
That is the signal to lift it into the framework.

## Decision

A Dittofeed stack's compose file meets these floors, and a mechanical check
enforces them:

- **ClickHouse `mem_limit` ≥ 8 GiB, `cpus` set (3 on the shared host).**
  The cap is headroom for merges, not steady state; it is not a sign the
  stack is "using" 8 GiB.
- **The system-log override is mounted.** A single file bind-mounted into
  `/etc/clickhouse-server/config.d/` that sets `text_log` to `warning` with a
  7-day TTL and TTLs on the other system logs. The reference copy is
  [`_stubs/dittofeed/clickhouse-system-logs.xml`](../_stubs/dittofeed/clickhouse-system-logs.xml);
  projects copy it into the stack's deploy directory. Never mount the whole
  `config.d` directory: the image's own `docker_related_config.xml` carries
  `listen_host`.
- **`dittofeed-lite` `mem_limit` ≥ 1 GiB** (measured steady state ~540 MiB).
- **Apply order on a stack that already has a large `text_log`:** truncate,
  then recreate the container with the override. Mounting first triggers
  the merge storm over the old parts.

`scripts/check-ditto-stack.sh <compose-file>` (framework-owned stub, synced
into every adopter) resolves the file with `docker compose config` and prints
one `FAIL:` line per miss. The Reviewer runs it on any diff that touches a
compose file with a ClickHouse service and blocks on findings
([`templates/reviewer-brief.md`](../templates/reviewer-brief.md)); the
stack's deploy README runs it before `docker compose up -d`.
[`dev-environment.md`](../dev-environment.md) §"Dittofeed stack" carries the
compose shape.

## Consequences

- **Mechanism:** the check is the rule. It fails loudly (exit 2) when the
  compose cannot resolve, so a missing `.env` is never read as a pass.
- **Named gap:** the check sees the compose file, not the box. A stack that
  was raised by editing the live file on the server and never merged back
  to the repo passes nowhere until the repo copy is updated, and a repo
  copy that passes says nothing about what is running. Repo-to-box drift is
  the stack README's apply procedure, not this check.
- **Four stacks on one host at 8 GiB each is a 32 GiB commitment.** On the
  current 47 GiB host that fits with 11 GiB otherwise in use; a new host or
  a fifth stack re-opens the question.
- **Coherence surfaces touched:** this ADR; the stub override; the check
  script and its `sync-framework.sh` entry; `dev-environment.md`
  §"Dittofeed stack"; the Reviewer brief. The per-project stacks themselves
  are server state, recorded in each project's deploy README per
  [FWADR-019](fwadr-019-dev-slots-and-deploy-stubs.md).
