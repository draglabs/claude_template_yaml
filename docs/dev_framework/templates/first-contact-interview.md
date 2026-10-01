# First-contact interview (Strategist, run-once)

**Layer 2 — loaded on demand**, not at session start. The Strategist loads this
file when actually running the interview; the trigger conditions and the goal
live in [`strategist.md`](../strategist.md) §"First-contact interview"
([FWADR-034](../adrs/fwadr-034-doc-weight-ratchet.md) demoted the full
procedure here: it runs once per project, and every-session loading of
run-once content is what the doc weight budget exists to prevent).

The goal: a confirmed `claude-env` launcher in the user's shell rc (Block 0),
a filled `$PROJECT_DIR/.env`, a CLAUDE.md with no surviving `{{...}}`
placeholders, a slots.yaml with the right shape, and a working `.mcp.json`
(every server connected or explicitly waived) — BEFORE any other role does
meaningful work or before the Developer runs `scripts/setup_dev_slots.sh`.

This isn't optional — `scripts/setup_dev_slots.sh` sources `.env` and halts on
`PLACEHOLDER` values for `PROJECT_SUB` or `PROJECT_PORTS` (see
[FWADR-019](../adrs/fwadr-019-dev-slots-and-deploy-stubs.md) Decision 7),
so the Developer's first launch attempt will fail until the Strategist has
done this.

## Two surfaces, kept in sync

Project variables live in **two places**:

- **`$PROJECT_DIR/.env`** — canonical machine-readable source. Scripts source this file (single line `source .env` and they have everything). The framework ships `.env.example` as a starter; the adopter copies it to `.env` (gitignored) on first init and the Strategist fills the values.
- **`CLAUDE.md`** — human-readable mirror. The inline `{{...}}` bullets get replaced with concrete values so humans and agents reading CLAUDE.md see the project identity at a glance.

**The Strategist fills BOTH in the same interview pass**, value-by-value, atomically. Drift between the two is a bug the [`strategist.md`](../strategist.md) §"Stub audit" catches.

## Pre-flight: read `.env` before asking anything

The `claude-env` launcher seeds `.env` from `.env.example` on the first launch in a fresh project ([FWADR-032](../adrs/fwadr-032-claude-env-launcher.md)), and users are told to fill the **MINIMUM TO BOOT** block before the first session. So the interview starts by reading, not asking:

1. `grep -E '^[A-Z_]+=' $PROJECT_DIR/.env` — every framework variable, with its current value. Do not print token values back.
2. **Set values** (not `PLACEHOLDER`, not empty) are answers. Present them in one table — variable, value, the CLAUDE.md surface it fills — and ask for a single yes/no confirmation of the batch, followed by "Anything else?" (CLAUDE.md §"Asking questions"). Correct individual rows only if the user objects.
3. **`PLACEHOLDER` or empty values** in the MINIMUM TO BOOT block are the questions. Ask only those, in the Block 1 order below.
4. **Variables missing from the file entirely** mean `.env` was hand-written rather than seeded. Append the missing lines from `.env.example` (never overwrite what is there), then treat them as `PLACEHOLDER`.
5. Block 0 (launcher) and Blocks 2–3 (slots, MCP) still run — `.env` cannot pre-answer those. Block 0 is one question when `.env` was launcher-seeded: the seed proves the launcher is installed.

A fully filled `.env` turns Block 1 into a single confirmation. That is the intended path.

## Question list

Run through these in order, skipping any row the pre-flight already confirmed. Each one fills both a `.env` variable and the corresponding CLAUDE.md surface. Batch the open questions of a block into one message, and close every such message with "Anything else?" — the user's slot for context you didn't know to ask for (CLAUDE.md §"Asking questions"); fold what lands there into the same commit. Don't accept "let's figure that out later" answers — that's how you end up with `{{sub}}` leaking into other sessions' chat output.

**Block 0 — launch environment (fills the user's shell rc; [FWADR-032](../adrs/fwadr-032-claude-env-launcher.md)):**

Everything downstream assumes Claude Code was launched with `.env` in its process env — MCP credentials and the FWADR-030 git-auth auto-wire both silently fail otherwise. The canonical launch path is the `claude-env` launcher set (snippet: [`../_stubs/shell/claude-env.zsh`](../_stubs/shell/claude-env.zsh)): `claude-env` (safe, normal permission prompts), `claude-env-yolo` (adds `--dangerously-skip-permissions`), and `load-env` (sources `.env` into the current shell with NO claude launch — for running framework scripts by hand or getting git auth in a bare terminal). The permission choice is made at every launch by name — nothing stores a permission posture.

| Question | Where it lands |
|---|---|
| Is the `claude-env` launcher installed in your shell rc? (With the user's go-ahead — the rc is outside the project tree — check: `grep -q 'claude-env' ~/.zshrc`.) If not: present the variants and ask which to install — safe only, or safe + yolo; `load-env` is permission-neutral and comes with either choice. Offer a `source <path-to-snippet>` line, pasting the functions verbatim, or running [`../_stubs/shell/install-claude-env.sh`](../_stubs/shell/install-claude-env.sh) (`--rc <file>` for a non-default rc; the snippet is bash-compatible despite the `.zsh` name). | The user's shell rc (e.g. `~/.zshrc`, `~/.bashrc`), edited only on explicit approval. Never installed silently. |
| Confirm the user knows the consequence of skipping: every session launched bare gets the sync hook's step-0 NOTICE (unbound MCP creds + git auth) until relaunched via `claude-env`. | Nowhere — this is the informed-decline path. The NOTICE is the standing enforcement. |

**Block 1 — project identity (fills .env + CLAUDE.md outside the managed block):**

| Question | `.env` variable | CLAUDE.md target |
|---|---|---|
| What is this project called? (slug) | `PROJECT_NAME=auto-portal` | `**{{project_name}}**` on the §"What this is" line |
| One sentence: what does it do? | (no .env mirror) | `{{one-line description}}` on the same line |
| What's the project subdomain? Examples: `auto`, `analytics`, `myapp`. Used in URLs like `<sub>.<website>.com` (prod) and `<slot>.<sub>.localhost` (dev). | `PROJECT_SUB=auto` | `{{sub}}` bullet |
| What's the parent domain? Examples: `jumpermedia.co`, `draglabs.com`. | `PROJECT_WEBSITE=jumpermedia.co` | `{{website}}` bullet |
| Port range — **propose, don't ask.** Run `./scripts/port_ledger.sh --propose` from `$PROJECT_DIR` (local-hosted only; it reads the machine-wide Caddyfile, where every project's `setup_dev_slots.sh` block records its reserved range — [FWADR-019](../adrs/fwadr-019-dev-slots-and-deploy-stubs.md) Decision 7). Offer the printed range for a yes/no; `--propose 20` if the project needs more than ten (HTTP + DB + queue per slot). Run it bare first to show the table if the user wants to see what is taken — it also flags existing cross-project overlaps, which are theirs to resolve, not this interview's. Remote-hosted: no local ledger; ask as before. | `PROJECT_PORTS=3080-3089` | `{{ports}}` bullet |
| Local-hosted or remote-hosted dev environment? Local = dev runtimes on the user's machine. Remote = dev runtimes on a shared dev server. | `DEV_ENVIRONMENT_MODE=local-hosted` | `{{local-hosted \| remote-hosted}}` in §"Dev environment mode" |
| Where is this repo hosted — GitHub, self-hosted GitLab, or something else? **Ask; never assume GitHub.** Users may run multiple hosts (e.g. GitHub for some projects, a private GitLab for others), and a repo created on the wrong host is expensive confusion. The answer determines the host CLI (`gh` vs `glab`), which MCP applies, and where PRs/MRs live. Self-hosted: also capture the base URL. | `GIT_HOST=gitlab` (+ `GIT_HOST_URL=https://...` if self-hosted) | `{{git_host}}` bullet |
| Which git flow — `dev-main` (features → `dev`, promotion merge to `main` at phase exit; the default) or `trunk` (features → `main`, production released by a `v*` tag at phase exit)? **Ask; never assume.** Both keep the same human gate at phase exit; trunk has one branch fewer and releases by tag ([FWADR-035](../adrs/fwadr-035-git-flow-mode.md)). Existing project switching modes: [`../migration-guide-trunk.md`](../migration-guide-trunk.md). | `GIT_FLOW=dev-main` | `{{git_flow}}` bullet |
| Recommend enabling **host-side protection of the release ref** (belt-and-braces over the FWADR-023 pre-push guard, which is machine-local): dev-main → protect `main` (GitHub → repo Settings → Branches; GitLab → protected branches); trunk → in each code repo protect `v*` tags and lock `main` to PR landing with mechanisms every tier has: **push = no one**, **merge = maintainers**, plus *pipeline must succeed* / *discussions resolved* where offered (approval objects are paid on some hosts; GitLab CE has none). The tracking parent stays unlocked ([FWADR-035](../adrs/fwadr-035-git-flow-mode.md) §"Landing under trunk"). For `GIT_HOST=other`, record whether an equivalent exists in `dev_framework_exceptions.md`. | (no .env mirror — configured on the git host) | (none) |
| One-line current-status summary (can be "stub state, no work yet"). | (no .env mirror) | `{{current phase/status summary}}` on the **Status:** line |
| Split layout: which subdirectory holds the primary code repo? | `DEFAULT_CODE_SUBDIR=my-repo` | (no CLAUDE.md mirror — `.env` only) |

**Block 2 — dev-slot shape (fills slots.yaml + informs Developer / Reviewer):**

| Question | Where it lands |
|---|---|
| Does this project expose an HTTP surface that needs Caddy routing? Most web apps: yes. CLI tools, libraries, headless scripts, data-pipeline jobs: no. | `setup_dev_slots.sh` asks this interactively and writes `http_surface: true \| false` (top-level in slots.yaml). If `false`, no routes are generated and the Reviewer's QA-target MED rule no-ops — but a comment-only ledger block is still written to the Caddyfile so the range shows up in `port_ledger.sh`. |
| Does each slot need secondary ports for project services? Examples: per-slot Postgres for test isolation (`db: 5441` on dev1, `5442` on dev2, …), per-slot Redis, per-slot message-queue. | Project-managed: edit `extras: { db: ..., redis: ... }` under each slot in `slots.yaml` by hand after running `setup_dev_slots.sh`. The script prints the edit pattern but does NOT write extras. |

**Block 3 — MCP servers (fills `.mcp.json` + the MCP roster docs):**

| Question | Where it lands |
|---|---|
| Do the shipped defaults connect on this machine? (`.mcp.json` is seeded from `_stubs/.mcp.json` with docker + gitnexus.) Run `claude mcp list`; walk the gitnexus adopter-setup steps (Node ≥ 20, `gitnexus index .`, restart, verify). | Fixes land in `.mcp.json` (e.g. the nvm direct-binary path — see [`../approved-mcps.md`](../approved-mcps.md) §"gitnexus"). Anything still broken at interview end is reported to the user with the fix + restart instruction, and re-flagged by the session-start health check until resolved. |
| Which project-specific MCP servers does this project need beyond the defaults? Examples: postgres/mysql for direct schema queries, a gitlab server when `GIT_HOST=gitlab` (the github MCP only applies to GitHub-hosted repos), slack for alerts, linear/jira if issues live off the git host. | Each addition follows [`../approved-mcps.md`](../approved-mcps.md) §"How to add a new MCP": `.mcp.json` entry + a doc entry in the same commit. In adopter repos the doc entry goes in `dev_framework_exceptions.md` §"Project MCPs" (NOT `approved-mcps.md` — that file is destructively synced). Credentials via env — remind the user that launching via `claude-env` (Block 0) is what binds them. |
| Any shipped default this project will never use? | User waiver, recorded in `dev_framework_exceptions.md` so the health check stops flagging it. Remove the `.mcp.json` entry or leave it waived — user's call. |

## Fill format for CLAUDE.md placeholders

The template ships bullets in a "scaffolding" shape:
```markdown
- `{{sub}}` — this project's subdomain (e.g. `myapp`)
- `{{ports}}` — local port range allocated to this project (e.g. `3050-3060` or `305*`); local dev runtimes ...
```

The Strategist replaces the `(e.g. \`...\`)` parenthetical with a concrete value bullet:
```markdown
- `{{sub}}` — this project's subdomain: `auto`
- `{{ports}}` — local port range allocated to this project: 3050-3060; local dev runtimes ...
```

For `{{project_name}}` / `{{one-line description}}` / `{{current phase/status summary}}` / `{{local-hosted | remote-hosted}}`: replace the literal placeholder text with the value — these aren't parsed by scripts, just read by humans and agents reading CLAUDE.md.

## When to run the interview

- **Once, on the Strategist's very first session for a project.** This is part of "the first 30 minutes of a fresh project" — happens before any plan, before any ADR, before the Developer can bring up a runtime.
- **Re-run partial intake when project identity changes** — domain rename, sub change, port-range collision discovered, HTTP surface added later. Update `.env`, CLAUDE.md, and `slots.yaml` together; commit; tell the user the new shape so they re-orient. Drift between `.env` and CLAUDE.md after such a change is the bug the stub-audit row catches.

## Disposition

Each interview answer is a small commit that touches both `.env` and CLAUDE.md (under flat / tracked-parent layout: one commit covering both files; under untracked-parent: just file edits, no commit). Group the interview into one commit (`chore: first-contact interview — project identity confirmed`); the dev-slot interactive setup (`./scripts/setup_dev_slots.sh` from `$PROJECT_DIR`) lands a second commit for slots.yaml.
