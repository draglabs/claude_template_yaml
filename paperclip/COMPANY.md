---
schema: agentcompanies/v1
kind: company
slug: dev-framework
name: "{{project_name}}"
description: The dev framework's roles as Paperclip agents for one project — a reading list per role, the role docs at a pinned commit, one mode document.
version: 1.0.0
license: MIT
authors:
  - name: draglabs
homepage: https://github.com/draglabs/claude_template_yaml
tags:
  - engineering
  - dev-framework
requirements:
  secrets:
    - GITLAB_TOKEN or GH_TOKEN (the bot's token for the project's git host)
metadata:
  dev_framework:
    mode_doc: docs/dev_framework/paperclip-mode.md
    adr: docs/dev_framework/adrs/fwadr-040-paperclip-mode.md
---

# {{project_name}} — framework roles on Paperclip

One framework project is one Paperclip company. This package creates the six role agents
(`FW_Strategist`, `FW_Orchestrator`, `FW_Developer`, `FW_Parallel_Developer`, `FW_Designer`,
`FW_Curator`) and one recurring task. Nothing project-specific lives here: each agent reads
the project's `CLAUDE.md` and `docs/framework_exceptions/dev_framework_exceptions.md` from
the planning repo at run start, and the framework's role docs at the commit this package
was rendered from. How the roles are played from an issue is one document,
`docs/dev_framework/paperclip-mode.md`, decided in FWADR-040.

Rendered into a company by `scripts/paperclip_company.py sync` (a framework-owned stub in
every adopter's `scripts/`), which fills the `{{…}}` placeholders from the project's
operator `.env` and stamps the framework commit. `status` reports when the template has
moved past that commit.

Org chart: `FW_Strategist` reports to the board; `FW_Orchestrator`, `FW_Designer` and
`FW_Curator` report to the Strategist; both Developers report to the Orchestrator.
