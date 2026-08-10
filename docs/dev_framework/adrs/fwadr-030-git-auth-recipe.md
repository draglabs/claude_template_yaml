# FWADR-030: `.env`-driven, host-symmetric git credential auto-wiring

**Status:** accepted
**Date:** 2026-08-09
**Deciders:** user (framework author) + Template Developer

## Context

The framework's git policy is host-neutral ([`dev_framework.md`](../dev_framework.md)
§"Git-host neutrality"), and `GIT_HOST` already declares a project's host. But
declaring the host did nothing to *authenticate* git: pushing/pulling still
depended on ad-hoc per-machine setup (SSH keys in `~/.ssh/config`, a global
`gh auth setup-git`, or a hardcoded per-repo `core.sshCommand`). That last
pattern is what stranded this very repo — a `core.sshCommand` pinned to a key
file that later moved, leaving the clone unable to reach GitHub at all.

Two facts make a clean recipe possible:

1. **Env vars only override where a tool reads them.** `AWS_*`, `gh` (`GH_TOKEN`),
   and `glab` (`GITLAB_TOKEN`) natively consume env-var credentials. **`git` does
   not** — it has no token env var; it delegates to a credential helper, the URL,
   or askpass. So git needs a *bridge*, and the bridge must be scoped so one
   project's token never leaks into another.
2. **Both host CLIs expose an equivalent git credential helper** — verified:
   `gh auth git-credential` and `glab auth git-credential` both exist. So a
   single mechanism covers both hosts with only the CLI name swapped.

## Decision

Ship a **`GIT_HOST`-conditional git-auth block in the `.env.example` stub** that
executes when `.env` is sourced (the existing `set -a; source .env` launch step).
It routes `git` over HTTPS to the declared host's CLI credential helper via
**session-scoped** `GIT_CONFIG_*` env vars — nothing is written to any gitconfig,
so it lives and dies with the terminal and cannot bleed between projects.

**Declaration** (per project, in `.env`): `GIT_HOST=github|gitlab`, the matching
token (`GH_TOKEN` / `GITLAB_TOKEN`), and `GIT_HOST_URL` for self-hosted.

**Non-preferential by construction** — the property the user required, on all
three axes:

- **GitHub ↔ GitLab:** identical mechanism; only `gh`↔`glab` differs. Both
  branches derive their credential host from `GIT_HOST_URL`.
- **GitLab self-hosted ↔ gitlab.com:** `GIT_HOST_URL` picks the instance and is
  exported as `GITLAB_HOST` so `glab` targets it; `gitlab.com` is merely the
  unset-URL default, not a privileged branch.
- **GitHub Enterprise ↔ github.com:** symmetric to the GitLab case via `GH_HOST`.
  (An earlier draft hardcoded `github.com` while parameterizing only GitLab —
  that bias was removed; self-hosted is first-class on both.)

**Remote convention:** token auth engages only for **HTTPS** remotes. SSH remotes
authenticate by key via `~/.ssh/config` — keys are host-scoped and belong there,
not in per-repo config (the lesson of the stranded repo). Token-auth projects
therefore standardize on HTTPS remotes.

## Consequences

- **Coherence surfaces, all in this change:** the `.env.example` stub (declaration
  + auto-wire block), `dev_framework.md` §"Git-host neutrality", and this ADR.
  Existing adopters keep their filled-in `.env`, so the block reaches them when
  they next copy from the refreshed stub or paste it in; new adopters get it at
  seed time.
- **One residual asymmetry, and it is the CLIs', not the framework's:** `gh` wants
  `GH_ENTERPRISE_TOKEN` (+ `GH_HOST`) for self-hosted GitHub, whereas `glab` uses
  `GITLAB_TOKEN` against any `GITLAB_HOST`. So the *token variable name* differs
  for the GitHub-Enterprise corner. Everything the framework itself controls is
  symmetric; this is documented as a host-tool quirk, not a preference.
- **HTTPS-remote requirement is a documented convention, not a mechanical gate**
  (the honest gap per framework doctrine). It needs none: an SSH remote simply
  doesn't trigger the helper and fails *loudly* on key auth — a self-announcing
  misconfiguration, not silent drift.
- **Single declared host per project.** A mixed-host multi-repo project (github
  primary + gitlab secondary) wires only the primary; the second host is added by
  extending `GIT_CONFIG_COUNT` manually. Rare enough to leave as documented
  overflow rather than complicate the common path.
- **Proven before shipping:** the exact mechanism was validated live on this repo
  — `git fetch` and a real `git push` (9-commit fast-forward landing FWADR-029)
  authenticated as `draglabs` over HTTPS through `gh auth git-credential`, with
  the SSH key still missing and irrelevant.
