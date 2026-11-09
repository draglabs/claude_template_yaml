#!/usr/bin/env bash
# Dev test harness — runs ON THE DEV SERVER. Tier 2 and Tier 3 live here.
#
# Tier 1 (fast, deterministic, no database, no network) is the only tier CI
# runs. A CI job never starts a database and never reaches one (FWADR-037).
#   Tier 2  needs the database or another service — runs here after each deploy
#   Tier 3  slow, end-to-end, browser-driven      — runs here on demand or nightly
# Both run against dev's own live services and dev's seed data.
#
# Contract:
#   dev_harness.sh               every Tier 2 case. The deploy job's last step
#                                runs this on the dev host; its exit code is the job's.
#   dev_harness.sh --tier 3      every Tier 3 case
#   dev_harness.sh --case <id>   one case
#   dev_harness.sh --list        every Tier 2 and Tier 3 case, with its tier
# Each run writes a record (run id, branch, commit, timestamp, pass/fail per
# case) where the dev site's harness page reads it. That page — /__dev/ on the
# dev site, never in production — lists every case, runs one or all for the
# user or an agent, and shows the last result per case and the history. Each
# run has a permanent URL: the link an agent posts on its item as "done".
#
# THIS IS A STUB. The project's own ADR decides the body: how the test runner
# selects a tier, the seed script (dummy data; migrations carry dev forward; a
# human-run wipe-and-reseed is the rare reset), where run records land, and how
# the page serves and starts runs.

set -euo pipefail

echo "scripts/dev_harness.sh is the dev test harness entry point (FWADR-037)."
echo "This is a developer-managed stub and is not implemented yet."
echo ""
echo "Before first use, the agent scopes with the user and fills in:"
echo "  - how a test declares its tier, and how this script selects Tier 2 / Tier 3 / one case"
echo "  - the seed script this depends on, and the human-run wipe-and-reseed"
echo "  - where each run's record is written"
echo "  - the /__dev/ page on the dev site: list cases, run one or all, last result per case, history"
echo ""
echo "Until then the deploy job does not call this script; check-ci-placement.sh WARNs on that."
echo "Canonical doctrine: docs/dev_framework/adrs/fwadr-037-ci-runner-topology.md"
exit 1
