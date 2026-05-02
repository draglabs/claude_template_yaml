# ADR-015: Split Template Developer from Strategist

**Status:** accepted
**Date:** 2026-04-23
**Deciders:** David (template author)

## Context

The framework had three persistent roles — Strategist, Designer, Orchestrator — designed for work inside a product project. When operating on the `claude_template_yaml` repo itself (framework maintenance), the Strategist role was overloaded to also act as framework maintainer. The overloading was formalized via a carve-out in `docs/framework_exceptions/dev_framework_exceptions.md` (EX-001) that granted the Strategist write access to `docs/dev_framework/*` when — and only when — the current repo was the template itself.

Two problems with the overload:

1. **Role-confusion across projects.** When the user context-switched between a product repo (where Strategist is product-facing) and the template repo (where Strategist was framework-facing via EX-001), the session's internal model of "what Strategist does" would flip. The user reported concrete confusion: "I want to distinguish this so I don't confuse you with a real strategist from another project."
2. **Policy-mechanism drift.** The framework doctrine is *"a rule of the shape 'X always happens on Y' must ship with the mechanism that makes X mechanical."* EX-001 was a write-permission broadening, not a rule, so it technically complied — but its very existence hinted that framework maintenance was a distinct mode of operation with distinct read surfaces, distinct blast radius, and distinct failure modes. Hiding that distinction inside an exceptions file rather than surfacing it as a first-class role obscured it from users and from the session's own bootstrap.

## Decision

Split framework maintenance out into a first-class role: **Template Developer**, documented in `docs/dev_framework/template-developer.md`. Only meaningful when operating in the canonical `claude_template_yaml` repo. In adopter repos, framework changes are made by opening a PR against the template, not by invoking this role.

Surface changes landed in the same PR as this ADR:

| Surface | Change |
|---|---|
| `CLAUDE.md` §Roles (framework-managed block) | Added "you are the Template Developer" row |
| `docs/dev_framework/template-developer.md` | New role doc |
| `docs/dev_framework/dev_framework.md` §"Role docs" | Added Template Developer row |
| `docs/dev_framework/context-management.md` Layer 1 table | Added Template Developer row with its Layer 1 reads |
| `docs/dev_framework/strategist.md` §"Does not modify framework docs" | Removed EX-001 carve-out; points at Template Developer instead |
| `.claude/hooks/session-reorient.sh` | `startup` and `clear` branches include the `template-developer` slug and path |
| `docs/framework_exceptions/dev_framework_exceptions.md` | Retired EX-001 with dated note pointing at this ADR |

Both English rule (role doc, CLAUDE.md row) and mechanical enforcement (hook update, context-management Layer 1 table, bootstrap reads) shipped together — that is what the doctrine requires.

## Consequences

**What this buys:**

- No more role overloading. "Strategist" and "Template Developer" are distinct session identities with distinct Layer 1 contexts. A user can say "you are the Strategist" in a product repo and "you are the Template Developer" in the template repo without the session's internal behavior flipping based on which directory it happens to be in.
- Bootstrap coherence. `session-reorient.sh` now lists the role when prompting for role declaration on `/clear` and `/startup`. A user in the template repo is pointed at the right role from the hook itself, not by convention.
- Adopter clarity. The role doc opens with an explicit "only meaningful in the canonical `claude_template_yaml` repo" preamble, so an adopter who sees `template-developer.md` in their repo (via sync) understands it is inert for them.
- EX-001 no longer exists as an active exception. The exceptions file returns to its intended shape: zero active entries, which is the healthy state.

**What this costs:**

- ~140 lines of new doc (`template-developer.md`) added to every adopter repo via `sync-framework.sh`. The file is inert in adopter repos but takes context-budget space if any adopter-side role reads `docs/dev_framework/*` broadly (no role does today; the file adds cost only if someone grep-loads the whole dir).
- One more row in CLAUDE.md §Roles, which is Layer 0 and always loaded. Acceptable at the current scale (four roles still fits comfortably under the Layer 0 weight target).
- One more case in `session-reorient.sh`'s heredoc text. Adds ~4 lines to the injected reminder on `startup` and `clear`.

**What this does NOT do:**

- Does not change how Strategist, Designer, or Orchestrator operate in product repos. Those roles are untouched.
- Does not introduce a sync-exclusion rule for `template-developer.md`. The doc ships to every adopter, same as `strategist.md` does even though Strategist is product-side. Doc-level gating (the "only meaningful in..." preamble) is cheaper and more consistent than a sync filter.
- Does not give Template Developer any authority over adopter-repo `process-exceptions.md` triage. That stays with the local Strategist. The handoff is one-way: local Strategist disposes an entry as "SOP update" → opens a PR against the template → Template Developer reviews and lands it.

## Alternatives considered

1. **Keep the EX-001 carve-out; leave Strategist overloaded.** Rejected. It was the status quo ante, and the user's reported confusion is the direct cost of that design.
2. **Add a sync-hook exclusion for `template-developer.md` so adopters never see it.** Rejected. Inconsistent with how every other framework doc (including `strategist.md`, `session-policy.md`) is synced — which is uniformly wholesale. Doc-level gating via the role doc's preamble achieves the same clarity with less sync-hook complexity.
3. **Rename "Strategist" to "Template Developer" when in the template repo; keep a single logical role.** Rejected. A role's identity cannot depend on the repo it is invoked in without making the bootstrap ambiguous and making `session-reorient.sh` branch on repo detection.

## Acceptance criteria for the shipping PR

- `docs/dev_framework/template-developer.md` exists and opens with the "only meaningful in the canonical `claude_template_yaml` repo" preamble.
- `CLAUDE.md` (within the FRAMEWORK MANAGED block) has the Template Developer row in §Roles.
- `session-reorient.sh` `startup` and `clear` branches name `template-developer` in the role list and path glob.
- `strategist.md` §"Does not modify framework docs" no longer references the EX-001 carve-out; it points at Template Developer instead.
- `dev_framework.md` §"Role docs" and `context-management.md` Layer 1 table both include Template Developer.
- `dev_framework_exceptions.md` EX-001 is in the Retired section with a dated note referencing this ADR.
- Manual smoke: on `/clear` in the template repo, the reorient hook prompts the user with all four role slugs including `template-developer`.
