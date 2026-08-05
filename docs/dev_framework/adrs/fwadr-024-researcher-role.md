# FWADR-024: Researcher role (generalized from the "Localhost Researcher" requirements handoff)

**Status:** accepted
**Date:** 2026-07-28
**Owner:** Template Developer

## Context

An adopter project's Strategist (makinrate, 2026-07-28) filed a requirements
handoff asking the framework for a "Localhost Researcher" role: a persistent
session that hunts content missing from the project's library on the open web
from the user's machine, delivers it through the project's intake API, and
records the hunt. Two live failure modes earned it:

1. **Branch indiscipline** — the research session committed directly to
   `main` and mirrored work to `dev` as duplicate commits, producing merge
   conflicts at promotion. Resolved framework-wide by
   [FWADR-023](fwadr-023-main-push-guard.md); no longer role-specific.
2. **Debugging drift across a contract boundary** — the session's job is
   acquisition via API calls against the project's server, and it has its own
   small codebase of scrape/search/prioritize/upload tooling. But when an API
   call misbehaved, it dug into the rest of the monorepo to "fix" the cause —
   a finder turning into a builder. And when the API genuinely lacked a
   capability the hunt needed, the session had no sanctioned outlet, so the
   pressure resolved as server-side edits.

The framework had no home for a project-local role: the Roles table lives
inside the sync-managed CLAUDE.md block and `session-reorient.sh` hardcodes
the role list, so any role must land in canon or nowhere.

## Decision

Land a generalized **Researcher** role in canon ([`researcher.md`](../researcher.md)), renamed from "Localhost Researcher" — run-locality (residential egress from the user's machine) is a project property, not the role's function. The role is **optional and parameterized**; it is inert in projects that don't configure it.

Load-bearing pieces:

1. **Refuse-to-bootstrap when unparameterized.** Activation requires
   `RESEARCHER_SCOPE_DIR` in `.env` plus a Researcher parameters entry in
   `dev_framework_exceptions.md` (intake, gap surfaces, hunt logs,
   acquisition-doctrine reading list). Without them the role stops at
   bootstrap. This is what makes canon-wide shipping safe: every adopter
   receives the doc; only configured projects can run the role.
2. **Mechanical write fence.** Write scope is one named directory plus
   exact-path data carve-outs (`RESEARCHER_DATA_CARVEOUTS`), checked by the
   generic stub `scripts/check-researcher-scope.sh` (diff vs `origin/dev`
   filtered against the `.env` scope) before every merge to `dev`.
3. **Contract-boundary rule with two named outlets.** The server API is
   opaque. API *failure* → hunt/dead-end log (evidence, memory, no action
   owed). API *capability gap* → a **server-work request**: a
   `req-YYYY-MM-DD-<slug>.md` file with YAML frontmatter dropped in the
   relevant plan folder, or in `docs/execution-plans/inbox/` when no phase
   clearly fits. The Strategist scans both at session start and phase
   boundaries and dispositions each request (accepted → W-item / declined /
   deferred) with user involvement. Giving the pressure a sanctioned outlet
   is the other half of banning the digging.
4. **Named gap: read discipline is English-only.** Mechanically fencing
   *reads* would cripple the session. The rule "never read server source to
   debug an API call" ships as doctrine with the write fence as backstop —
   drift into reading cannot land as code. Per framework doctrine, the gap is
   named rather than papered over.
5. **Role-addition coherence set** shipped in one change: CLAUDE.md Roles
   table, `researcher.md`, `dev_framework.md`, `context-management.md`,
   `session-reorient.sh`, plus `strategist.md` (request triage + parameter
   ownership), `.env.example`, the scope-check stub, and
   `docs/execution-plans/README.md` §"Server-work requests".

## Alternatives considered

- **Project-local role extension point** (roles manifest outside the managed
  block; `session-reorient.sh` reading roles from a file). More doctrinally
  pure for a single-project need, but a bigger and more speculative framework
  redesign than the role itself. Deferred: if a second genuinely
  project-specific role appears, build the extension point then and consider
  migrating Researcher out of canon.
- **Decline; run the role informally via an exceptions-file entry.** The
  role row cannot survive sync and the fences stay unenforced —
  institutionalizes exactly the observed drift.
- **Keeping the "Localhost" name.** Rejected: encodes an egress
  implementation detail into a canonical identity that propagates to every
  adopter.

## Consequences

- Adopters get the role doc on next sync; nothing activates anywhere until a
  Strategist writes the parameters. The requesting project activates by
  filling `RESEARCHER_SCOPE_DIR` (+ carve-outs), writing the parameters
  entry, and pointing it at its acquisition doctrine and standing logs.
- The Strategist's session-start surface grows by one scan (`req-*` files in
  active plan folders + inbox). `docs/execution-plans/README.md` is
  init-copied, not synced — existing adopters get the request spec through
  the synced `researcher.md`/`strategist.md`; the README section reaches new
  adopters only. Named propagation gap, acceptable because the synced docs
  carry the full spec.
- Coexistence with Developer/Orchestrator streams is by construction: the
  Researcher's write scope is a directory no Developer stream owns, and its
  branch discipline is the standard model, now mechanically enforced at the
  main boundary by FWADR-023.
