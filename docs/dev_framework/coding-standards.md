# Coding standards

> **Who loads this doc:** the Executor subagent at spawn (authoring), the Reviewer subagent at spawn (enforcing — sequential mode), and the Integrator-QA subagent at spawn (enforcing — batch mode, and authoring its own fix commits). The Orchestrator and Strategist do NOT carry this file in session-start context — code-level enforcement is delegated to the subagent layer. See [`context-management.md`](context-management.md) for the layering rules.
>
> **Fix commits follow the same rules as Executor commits, regardless of who writes them.** In batch mode ([ADR-016](../architecture/adr-016-batch-mode-integrator-qa.md)) the Integrator-QA may write fix commits within a W-item's existing acceptance. Those commits are subject to the full discipline below — TDD, no hardcoded lifecycle values, no silent fallbacks, canonical-value grep. Batch mode is NOT a quiet bypass of the standards; a clean Integrator-QA verdict on code that violates a rule here is an Integrator bug.

Enforced practices for all agents writing code in this repo. These aren't aspirational — they're the result of real incidents where shortcuts caused silent regressions, lost work, or wasted sessions.

## Test-driven development

**Write the test first, then the implementation.**

The cycle:
1. Write a failing test that captures the acceptance criterion.
2. Write the minimum code to make it pass.
3. Refactor if needed, keeping tests green.

This applies to all W-items with code changes. The Executor subagent's report must include test results — if no tests exist for the changed surface, the Executor writes them as part of the work item.

### What to test

Tests are for **surfaces where silent failure is expensive** — security, money, state corruption, data integrity, input validation. They are not for:

- Proving types are correct — that's `tsc --noEmit` (or your language's type checker).
- Guarding against hypothetical future deletions.
- Snapshotting generated output.

### When bugs get through

A test lands **alongside the fix** — not retroactively across the whole module. Test debt is tracked explicitly, not hidden in coverage reports.

### Test layout

Tests live **collocated** with source — `src/foo/bar.ts` → `src/foo/bar.test.ts`. No `__tests__/` directories.

### CI gate

Tests run as a CI gate alongside type checking. A red test blocks deploy.

```bash
# CI runs these in order — all must pass
{{typecheck_command}} && {{test_command}}
```

## No hardcoded values with a lifecycle

**Never inline a value that duplicates information from a canonical source.** It will drift silently across sessions.

Values with a lifecycle include: version strings, domain names, IP addresses, container names, registry URLs, infrastructure paths, org names, credential fallbacks.

### The pattern

Bad:
```typescript
const imageVersion = "1.2.0";  // duplicates capabilities.yaml
const domain = `${name}.draglabs.com`;  // duplicates ROOT_DOMAIN env var
const dbUrl = process.env.DATABASE_URL || "postgres://postgres:postgres@localhost:5432/mydb";  // silent fallback
```

Good:
```typescript
const imageVersion = getDefaultImageVersion();  // reads from canonical source
const domain = `${name}.${process.env.ROOT_DOMAIN}`;  // env var
const dbUrl = requireEnv("DATABASE_URL");  // fails loudly if missing
```

### Why this matters

Session 1 introduces a literal. Session N bumps the canonical source but only touches files it's actively working on. The stale literal drifts silently because context window pressure means earlier sessions' details are compacted away by the time the source of truth changes.

### Enforcement

When introducing any value that might change independently of the file it's in, read it from its source. **When bumping a canonical value, `git grep` the old value across the full codebase before committing.**

### Environment variables

- **No silent fallbacks.** If an env var is required, throw at startup if it's missing. `process.env.FOO || "default"` is almost always wrong for infrastructure values.
- **Document every env var** in `.env.example` with its purpose and an example value.
- **Dev vs prod:** If a value legitimately differs between environments, use an env var. If it's the same everywhere, use a constant with a comment pointing to why.

## Docs-first workflow

**Before implementing any architectural addition, update the planning docs first.**

The order:
1. Update planning docs to reflect the decision.
2. Commit the doc changes.
3. Only then implement code.

### Why

The planning docs are the source of truth. Shipping code ahead of docs produces a split-brain where the code works but the plan doesn't mention it. Every new session starts by reading the docs — if the docs are stale, the session starts with wrong assumptions.

### What counts as an architectural addition

- New tool, MCP server, or runtime component
- New database table or schema change
- New API route or endpoint
- New service or container
- Change to the deployment pipeline
- New env var that affects behavior

For pure implementation work within an existing design, update docs only if the implementation reveals something the design didn't anticipate.

## Fail loudly, never silently

Code should fail with a clear error rather than silently doing the wrong thing.

- **Missing config:** throw at startup, not at first use.
- **Invalid input:** reject at the boundary (zod, schema validation), not deep in business logic.
- **Unexpected state:** throw or return an error, not a default value that hides the problem.

The worst class of bug is one where the system appears to work but is silently wrong. Every fallback and default is a potential silent failure mode. Prefer explicit errors over graceful degradation for infrastructure values.

## Code review via the Reviewer subagent

Under peer dispatch, the Reviewer is spawned **by the Orchestrator** as a peer of the Executor (see `docs/dev_framework/session-policy.md` §"Dispatch flow" and ADR-013). The Executor writes and commits; the Orchestrator then spawns the Reviewer independently. The Reviewer returns its verdict directly to the Orchestrator, which runs the retry loop on `block` — an Executor fix cycle (continuation or fresh dispatch, per session-policy §"Orchestrator-owned retry mechanics") with the concerns as sharpened context.

The Reviewer checks these questions (from reviewer-brief.md):

1. **Acceptance match** — does the implementation satisfy each acceptance bullet?
2. **Canonical alignment** — does the code match the plan + architecture docs?
3. **Coding standards** — TDD, no hardcoded lifecycle values, no silent fallbacks.
4. **Hidden assumptions** — undocumented invariants?
5. **Edge cases** — what inputs/scenarios could break this?
6. **Scope creep** — anything added that wasn't in scope?

The Reviewer returns: `ship` / `ship-with-concerns` / `block` (with a Block class on `block` — ADR-022). A `block` causes the Orchestrator to run an Executor fix cycle with the concerns verbatim — continuing the same Executor or dispatching a fresh one per the Block class; either way the Executor adds fix-commits on top of the existing branch (no amend, no rebase — the Reviewer reads history). The Orchestrator re-spawns the Reviewer after each fix cycle. On exhausting the retry cap with an unresolved block, the Orchestrator escalates the W-item as stumped.

## Execution incidents

When a process violation or briefing error causes lost work, wasted execution, or a false conclusion, document it in `docs/framework_exceptions/execution-incidents.md` with:

- **When** it happened
- **What** went wrong
- **Root cause** — why it happened
- **Impact** — time/work lost
- **Fix** — policy change to prevent recurrence

Incidents are how the process improves. Every incident should produce a policy fix so it doesn't repeat.
