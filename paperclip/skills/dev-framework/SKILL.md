---
name: dev-framework
description: Read the dev framework's role docs, templates and ADRs at the pinned commit this company was rendered from, and play a role from a Paperclip issue per paperclip-mode.md.
metadata:
  paperclip:
    tags:
      - engineering
      - dev-framework
  sources:
    - kind: github-dir
      repo: "{{framework_repo}}"
      path: docs/dev_framework
      commit: "{{framework_commit}}"
      url: "https://github.com/{{framework_repo}}/tree/{{framework_commit}}/docs/dev_framework"
      attribution: draglabs
      license: MIT
      usage: referenced
---

# dev-framework

The framework is markdown under `docs/dev_framework/` of `{{framework_repo}}`, pinned for
this company at commit `{{framework_commit}}`. Fetch a document with:

```sh
fw() { curl -fsSL "https://raw.githubusercontent.com/{{framework_repo}}/{{framework_commit}}/docs/dev_framework/$1"; }
fw paperclip-mode.md          # the one document that differs on Paperclip
fw developer.md               # a role doc
fw templates/reviewer-brief.md
fw adrs/fwadr-040-paperclip-mode.md
```

Read what your `AGENTS.md` lists, in the order it lists it, at the start of every run. The
project's own files (`CLAUDE.md`, `docs/framework_exceptions/dev_framework_exceptions.md`)
come from the planning repo, not from here; your `AGENTS.md` says how to fetch them. Where
a role doc and `paperclip-mode.md` disagree about *how* to do something from an issue,
`paperclip-mode.md` wins; where the project's exceptions file disagrees with either, the
exceptions file wins.
