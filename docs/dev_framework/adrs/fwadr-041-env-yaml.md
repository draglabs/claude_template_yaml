# FWADR-041: One encrypted `env.yaml` per project; the operator delivers its values to each place

**Status:** accepted
**Date:** 2026-11-19
**Deciders:** user (framework author) + Template Developer
**Piloted in:** Moss Films (the `places` layout) and ThankMu (the delivery scripts, the Bitwarden backup, a real delivery to GitLab and Paperclip)

## Context

Env values were hand-placed: a hand-written operator `.env`, hand-set CI variables,
hand-edited app env files on hosts, and a second hand-made copy for Paperclip agents.
Nothing recorded which value was where, values drifted between places, and a change
meant logging in somewhere. [FWADR-033](fwadr-033-env-scope-rule.md) said which plane a
key belongs to but kept every secret out of git, so the only record of a value was the
place it happened to be.

Two projects piloted one tracked file. The pilots settled the shape; the user settled
three questions the pilots left open (2026-11-19): each project has its own key,
delivery is run from the operator's machine and never by CI, and whether a
production-only secret reaches Paperclip is decided entry by entry.

## Decision

1. **One file.** `env.yaml` at the root of `$PROJECT_DIR`, tracked in the planning repo.
   It lists every env value the project shares — operator values and the values its
   deployed environments and its agents need — and the places each one goes.

2. **Only secrets are encrypted.** SOPS with one age key, `encrypted_regex: ^value$`. A
   secret is a `value`; anything else is a `plain`. Names, places, notes and plain values
   are readable in the file and in every diff.

3. **Places are declared in the file, and an entry names the places it goes to.**

   ```yaml
   places:
     operator:  {kind: env-file, path: .env}
     app-dev:   {kind: ci-variables, repo: group/app, scope: dev}
     app-prod:  {kind: ci-variables, repo: group/app, scope: prod}
     paperclip: {kind: paperclip, company: myproject}
   vars:
     APP_SECRET_KEY:
       - value: ENC[...]
         places: [app-dev, paperclip]
       - value: ENC[...]
         places: [app-prod]
     SERVER_DEV:
       - plain: 203.0.113.7
         places: [all]
   ```

   - A variable is a list of items, one per distinct value. A different value for
     production is a second item.
   - An item with no `places` goes nowhere: it is recorded, not delivered.
   - `all` means every declared place.
   - An undeclared place, or two items of one variable reaching the same place, is an error.

4. **Three kinds of place.** `env-file`: a file inside `$PROJECT_DIR` (the operator
   `.env`, a code repo's local `.env`). `ci-variables`: variables on a repo, scoped to an
   environment. `paperclip`: the company's secrets, bound into its projects' envs. There
   is no kind that writes to a host.

5. **Paperclip is a place, never a key holder.** An agent has a value because an entry
   routes it to `paperclip`. Route liberally: Paperclip is where the developers work. A
   production-only secret goes there when its entry says so; the entry decides.

6. **One key per project, on the operator's machine.** `.sops-age-key.txt` at the project
   root, gitignored, mode 600. Not in CI, not in Paperclip, not on a host, and not shared
   with another project: a leaked key exposes one project.

7. **The key is backed up to Bitwarden Secrets Manager.** The token that reaches it,
   `BITWARDEN_MACHINE_ACCESS`, lives in the hand-kept part of the operator `.env` and is
   never an entry in `env.yaml`: what recovers the key cannot sit behind the key.

8. **Delivery is run by hand, on the machine that holds the key.** Merging a change to
   `env.yaml` delivers nothing; `./scripts/env_yaml.py deliver` does. The Strategist
   decides which place gets which value and runs the delivery. No CI job decrypts the file.

9. **The operator `.env` is generated.** Delivery rewrites one block in each env file,
   between `# >>> env.yaml` and `# <<< env.yaml`; every line outside it is kept. The
   hand-kept part of the operator `.env` holds the Bitwarden token, anything personal, and
   the derived shell section. The launcher sources the file as it stands
   ([FWADR-032](fwadr-032-claude-env-launcher.md)); it does not render.

10. **Hosts are built at deploy.** A code repo's deploy job writes the app env on the host
    whole, from the CI variables scoped to its environment plus the committed non-secret
    settings, and fails on a missing name. So a production value takes effect at the next
    release deploy, and delivery never redeploys anything.

11. **Agents do not edit the file.** A value an agent needs added or changed is an `fdr_blocked`
    ([`paperclip-mode.md`](../paperclip-mode.md) §"Who merges").

The scope rule of FWADR-033 still decides *where a value goes*: a key the deployed
container needs is routed to that environment's CI place, a key the tooling needs is
routed to `operator`. It no longer decides which file the value is kept in.

## Mechanisms, all in this change

| Rule | What makes it mechanical |
|---|---|
| Only ciphertext leaves the machine | The pre-push guard refuses a root `env.yaml` holding a `value` that is not ciphertext, a file SOPS never wrote, or a `plain` item under a name that looks like a secret without `secret: false`. It also refuses a tracked `.sops-age-key.txt`. `env_yaml.py` refuses the same before it does anything. |
| Places are explicit | `env_yaml.py` validates on every command: undeclared place, duplicate route, unknown kind, an env-file path outside the project. |
| The recovery token is never behind the key | `env_yaml.py` refuses `BITWARDEN_MACHINE_ACCESS` and `SOPS_AGE_KEY*` as entries; `import` skips them. |
| No delivery to hosts, none from CI | The script has no host kind. The key is on one machine, so nothing else can decrypt. |
| `.env` matches `env.yaml` | The generated block carries a stamp of the `env.yaml` it came from; `sync-framework.sh` step 4g NOTICEs when it is missing or behind. |
| Projects adopt it | Step 4g NOTICEs at every session start in a project with no `env.yaml`; the first-contact interview's Block 5 is the adoption. |
| An edit without the key is rejected | SOPS's integrity check covers the readable fields too: a hand edit to a `plain` value makes the file fail to decrypt (tested). |
| The key can be recovered | `env_key_backup.py backup`, then `verify`, which fetches the key back and decrypts `env.yaml` with it. |

The scripts are seed-once stubs (`scripts/env_yaml.py`,
`scripts/env_key_backup.py`): copied into a project when missing and the
project's to adapt from there — a new place kind, another CI host, a different
backup store. A fix to the template copy reaches an existing project by hand. `scripts/test-env-yaml.sh` in the
template runs them and the guard end to end against a throwaway key and a local stand-in
for the GitLab and Paperclip APIs.

## What the pilots learned

- A Paperclip company secret is invisible to an agent until it is bound into a project's
  env. Delivery creates the secret and writes the binding; a plain value is written into
  the project's env directly.
- Paperclip never returns a secret's value, so "unchanged" cannot be seen there. Every
  delivery to it rotates. `--since=<ref>` limits a delivery to what changed in the file.
- GitLab returns values, so an unchanged variable is skipped. It refuses to mask short
  values and values with spaces or newlines; delivery masks when it can.
- `sops set` changes one item and leaves every other ciphertext alone, so a diff shows
  one entry changed. It does not accept a bare list; the scripts write whole items.
- The VS Code SOPS extension needs `.sopsrc` pointing at the key file, the `.sops.yaml`
  path rule matching `env.yaml`, and the folder opened as the workspace root. `init`
  writes all three.
- A Bitwarden machine account sees nothing until it has a project it can write to. The
  Python package is `bitwarden-sdk`.

## Honest ceiling

- **A secret filed as `plain` under an innocent name is committed in the clear.** The
  name check catches the common case, not all of them. Whoever adds an entry decides.
- **Removing an entry removes nothing at its places.** Delivery creates and updates. A
  variable or Paperclip secret that left the file is deleted by hand.
- **`ci-variables` is implemented for GitLab only.** On another host the stub stops
  with that message; the project adds its host to its own copy, or sets the variables
  by hand. This is a gap in [git-host neutrality](../dev_framework.md#git-host-neutrality),
  named here until a project on GitHub fills it.
- **The deploy rule (item 10) is English-only.** Nothing checks that a deploy job builds
  the host env whole; a project whose deploy does not is still hand-placing on the host.
- **The guard reads ref tips and does not run on an agent host.** There, "agents do not
  edit the file" rests on the merge rule and on SOPS rejecting an edit made without the key.
- **A merged change waits for a person.** Nothing is delivered while the operator's
  machine is closed.
- **Ciphertext is in git history for good.** If a key leaks, every secret that project's
  file has ever held is rotated. If the machine is lost, the key comes back from
  Bitwarden and the Bitwarden token is re-issued by hand.
- **The Bitwarden round trip is ThankMu's.** The template's test does not reach
  Bitwarden; `backup`, `verify` and `restore` were proven there.

## Consequences

- One file answers "where is this value and who gets it", and a change to it is a commit.
- Operator tokens are in git, encrypted, and plain operator values are in git in the
  clear. FWADR-033 is rewritten to say so.
- A project adopts by running the interview's Block 5: `init`, back up the key, `import`
  the hand-written `.env`, declare the places, `render --take-over`, `deliver`.
- **Coherence surfaces, all in this change:** this ADR; FWADR-033 and FWADR-032;
  `git-guard-pre-push.sh` and its note in FWADR-023; `sync-framework.sh` step 4g and the
  stub list; the two scripts and the template's test; `.env.example`; the interview's
  Block 5 and Block 4; `strategist.md`; `paperclip-mode.md` §"Who merges" and §"What a
  project does to adopt"; `reviewer-brief.md`; `context-management.md`; `dev_framework.md`;
  the CLAUDE.md managed block; the template's `.gitignore`.

## Alternatives considered

- **Delivery by a CI job on merge** (Moss Films as first written): automatic, but the key
  is in a second place and a merged change delivers itself.
- **One key shared across projects:** convenient on the day of the pilot; one leak then
  exposes every project.
- **Encrypt every value** (ThankMu's earlier two-file scheme): no misfiled-secret risk,
  but nothing about the file is readable in a diff.
- **Per-entry `variants` picked by each target** (ThankMu's running layout): works, but
  needs four field names and an indirection; one item per value needs neither.
- **Hand Paperclip the key:** agents could then read every secret. A place is narrower.
