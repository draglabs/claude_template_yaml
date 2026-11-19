#!/usr/bin/env bash
# Dev test harness, host part — runs ON THE DEV SERVER, never in a CI job.
#
# Tier 1 (fast, deterministic, no database, no network) is the only tier CI
# runs. A CI job never starts a database and never reaches one (FWADR-037).
# What runs on dev has two parts (dev-environment.md §"Test tiers and the dev
# harness"):
#   this script   host checks: the deploy really served (health by loopback and
#                 by public name, the deployed commit, static assets present).
#                 Shipped with the deploy payload; the remote deploy runs it on
#                 the target as its last step, and its exit code is the job's.
#   in the app    Tier 2 and Tier 3 cases, from test code in the image, started
#                 by the deploy and, on demand, by a dev-only endpoint (the
#                 stakeholder from the QA view, an agent over HTTP).
#
# What a filled-in harness keeps (learned in the first project to build one):
#   - three outcomes per suite: pass, fail, skip (exit 77 = "could not run");
#     a skip is shown as a skip, never counted green
#   - every suite time-bounded, the bounds summing to less than the job timeout
#   - every suite has a plain-language title and a one-line summary written for
#     a reader with no log: the QA view shows them to the stakeholder
#   - one report (commit, start, finish, per-suite status and summary), written
#     to a temp file and moved into place; the page shows a missing or bad
#     report as a state, never an error
#   - one comment on the commit when it finishes, with the dev server's
#     comment-only key:  qa:harness pass|fail|skip <run-url>
#   - settings come from the deploy script, never rebuilt here
#   - dev only: refuses any other environment
#   - never deletes or flushes dev data; no secret in a report or a log
#
# THIS IS A STUB. The project's own ADR decides the body: the suites, where the
# report lands, the in-app runner and its endpoint, the seed script (dummy
# data; migrations carry dev forward; a human-run wipe-and-reseed is the rare
# reset).

set -euo pipefail

echo "scripts/dev_harness.sh is the dev test harness's host part (FWADR-037, FWADR-042)."
echo "This is a developer-managed stub and is not implemented yet."
echo ""
echo "Before first use, the agent scopes with the user and fills in:"
echo "  - the host suites (health, deployed commit, assets), each with a plain-language title"
echo "  - how Tier 2 / Tier 3 cases run inside the app, and the dev-only endpoint that starts them"
echo "  - where each run's report is written, and the qa:harness comment on the commit"
echo "  - the seed script this depends on, and the human-run wipe-and-reseed"
echo ""
echo "Until then the deploy does not call this script; check-ci-placement.sh WARNs on that."
echo "Canonical doctrine: docs/dev_framework/dev-environment.md §\"Test tiers and the dev harness\""
exit 1
