#!/usr/bin/env bash
# Post-deploy test harness — runs ON THE DEV SERVER after a deploy lands.
#
# CI runs only deterministic checks (lint, typecheck, unit tests, build) on the
# ephemeral runner host. Everything progressive — integration suites,
# end-to-end flows, anything that needs Postgres or another service — runs
# HERE, against dev's own live services and dev's seed data. No datastore ever
# starts inside a CI job (FWADR-037).
#
# Contract: the deploy job's last step runs this script on the dev host; its
# exit code is the job's. It writes a report (branch, commit, timestamp,
# pass/fail, per-suite summary) where the dev deployment serves it, so dev
# shows what it is running and how the last harness went.
#
# THIS IS A STUB. The project's own ADR decides the body: which suites run,
# the seed script it depends on (seed with dummy data; flush-and-reseed is the
# rare reset — migrations carry dev forward), where the report lands, and how
# dev exposes it.

set -euo pipefail

echo "scripts/dev_harness.sh is the post-deploy test harness entry point (FWADR-037)."
echo "This is a developer-managed stub and is not implemented yet."
echo ""
echo "Before first use, the agent scopes with the user and fills in:"
echo "  - which suites run here (integration, e2e, anything that touches Postgres or another service)"
echo "  - the seed script this depends on, and the flush-and-reseed reset"
echo "  - where the report is written so the dev deployment can serve it"
echo "  - how dev shows branch, commit and the last report"
echo ""
echo "Until then the deploy job does not call this script; check-ci-placement.sh WARNs on that."
echo "Canonical doctrine: docs/dev_framework/adrs/fwadr-037-ci-runner-topology.md"
exit 1
