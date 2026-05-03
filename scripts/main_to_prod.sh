#!/usr/bin/env bash
# Direct-to-server production deploy.
#
# THIS IS THE NAMED ESCAPE HATCH for the user-approved non-CI deploy path.
#
# CLAUDE.md §"Two process rules" #2 ("CI-only deploys to production") remains
# the default. This script exists for projects where the user has explicitly
# approved direct-to-server deploy. When that's the case, ALL prod deploys
# go through this script — never improvise prod commands outside it.
#
# Reviewer enforcement: a commit that runs prod deploy by any path other
# than this script is a `block`. See docs/architecture/adr-019-dev-slots-and-deploy-stubs.md
# §"Reviewer-side enforcement".
#
# THIS IS A STUB. Before first use, an agent must scope the real server with
# the user and fill in the body — connection, code update, dependencies,
# service restart, verification.

set -euo pipefail

echo "scripts/main_to_prod.sh is the canonical direct-to-server production deploy entrypoint."
echo "This is a developer-managed stub and is not implemented yet."
echo ""
echo "Before first use, the agent must scope the real server with the user and fill in:"
echo "  - how to connect to the server (ssh user@host, deploy key location, jump host?)"
echo "  - how code is updated on the server (git pull, rsync, docker image push, etc.)"
echo "  - how dependencies / build steps run (npm ci, docker build, migrations, etc.)"
echo "  - how services are restarted or reloaded (systemctl, pm2, docker compose, etc.)"
echo "  - how deploy success is verified (health check curl, log tail, smoke test)"
echo ""
echo "Once filled in: every prod deploy MUST go through this script. Never improvise."
echo "Reviewer will block any commit that ran a prod deploy by any other path."
echo ""
echo "Canonical doctrine: docs/architecture/adr-019-dev-slots-and-deploy-stubs.md"
exit 1
