# paperclip/ — the framework as a company package

An [Agent Companies](https://agentcompanies.io/specification) (`agentcompanies/v1`)
package: `COMPANY.md`, one `agents/fw-<role>/AGENTS.md` per framework role, the
`dev-framework` skill, and a recurring alignment task. It is the framework's own
answer to "how do the roles run on Paperclip" — see
[`docs/dev_framework/paperclip-mode.md`](../docs/dev_framework/paperclip-mode.md) and
[FWADR-040](../docs/dev_framework/adrs/fwadr-040-paperclip-mode.md).

**Nothing in here is a rewrite of a role.** Each `AGENTS.md` is a reading list plus the
pointer to the mode document. The role docs stay single-sourced under
`docs/dev_framework/`; agents read them at a pinned commit of this repo.

## Using it from a project

From the project's `$PROJECT_DIR`, with the operator `.env` sourced
(`PAPERCLIP_API_URL`, `PAPERCLIP_API_KEY`, `PAPERCLIP_COMPANY`, `PAPERCLIP_PLANNING_REPO`):

```sh
./scripts/paperclip_company.py status      # pinned commit vs the template's main; exit 1 on drift
./scripts/paperclip_company.py sync        # create or refresh the six agents at the template's main
./scripts/paperclip_company.py sync --dry-run
```

`sync` fills the `{{placeholders}}` below from `.env`, stamps each agent with the framework
commit it was rendered from, and copies adapter and environment settings from an existing
agent in the company (`PAPERCLIP_TEMPLATE_AGENT`, default `Lead`) so the new agents run
where that one runs. The session-start sync runs `status` for any project with
`PAPERCLIP_API_URL` set and prints a NOTICE on drift.

## Placeholders

| Placeholder | Filled from |
|---|---|
| `{{project_name}}` | `PROJECT_NAME` |
| `{{framework_repo}}` | `PAPERCLIP_FRAMEWORK_REPO` (default `draglabs/claude_template_yaml`) |
| `{{framework_commit}}` | the template's `main` at render time |
| `{{fetch_project_docs}}` | shell lines that fetch the planning repo's `CLAUDE.md` and exceptions file, built from `GIT_HOST`, `GIT_HOST_URL`, `PAPERCLIP_PLANNING_REPO` |

## Importing natively

The package is spec-valid, so Paperclip's own company import can read it from this repo
at a commit. The script exists because the import has no way to fill placeholders or copy
a sibling agent's adapter; once it does, the script shrinks to `status`.
