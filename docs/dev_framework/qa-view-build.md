# Building the QA view

How a project builds the QA bubble and the view behind it, so that a second project
builds it without looking at the first. The framework carries the description, the exact
formats and the test cases; it carries no code, because the view is a module in each
project's own stack ([FWADR-042](adrs/fwadr-042-qa-view-release.md)). What the view is
for is in [`dev-environment.md`](dev-environment.md) §"The QA view" and §"Release by
approval"; this is the build guide. Read on demand by whoever builds or reviews the view.

**A ticket never points at another project's repo as the reference.** Agents cannot read
it and should not. What is worth sharing between projects is written here.

## The bubble

The way in, on every page of a dev site.

- **Where:** fixed in the upper left corner, 16 px from the top and from the left, above
  all page content, at phone and desktop width. It stays put when the page scrolls.
- **What:** a 44 px circle labelled `QA`. It is a plain link to `/qa`, with the accessible
  label "Open the QA view".
- **Look:** colours and type come from the project. Position, size and label do not, so
  the stakeholder finds it in the same place on every project.
- **When:** rendered by the app's outermost layout when `QA_VIEW` is `on`. With `off` it
  is not in the page at all, and `/qa` answers 404. `QA_VIEW` has no default: a missing
  value stops the app at start.
- **Cost:** the bubble loads nothing. The view's data is fetched only when `/qa` is
  opened, because the view calls the git host.

## The view

One page at `/qa`, a single column no wider than a comfortable line of text, readable on a
phone. Every action is an ordinary form post that redirects back to `/qa` with a result,
so it works without client-side script. Top to bottom:

1. **Header.** "QA", the title "Release checklist", the deployed commit in full, whether
   it is `main`'s head, and a link back to the site.
2. **Result of the last action,** when there is one: one sentence ("Saved." / "The git
   host did not accept that. Nothing was saved; try again.").
3. **What was tested.** The harness result for the deployed commit: each suite and case by
   its plain-language title, passed, failed or skipped, with a one-line reason for
   anything not passed. Nobody marks this list. No result for this commit is said in
   words, not shown as green.
4. **The checklist.** One card per item:
   - the title, and a status pill: **To check**, **Approved**, **Rejected** or
     **Postponed**, followed by who made the mark;
   - the detail line: what to look at and what right looks like;
   - the notes already written on this item, oldest first, each with its author and time;
   - a note box and four buttons: **Approve**, **Reject**, **Postpone**, **Send
     feedback**. The button for the item's current state is filled; the others are
     outlined. Reject and Send feedback need a note; Approve and Postpone take one
     optionally.
5. **What changed.** The PRs merged since the last release, each a link to the git host.
6. **Anything else on this commit.** Earlier general feedback, then a box and a Send
   feedback button.
7. **Release.** A version field, filled with the next patch after the highest release
   tag (`v0.0.1` when there is none), and **Approve release**. Above it, one sentence on
   where things stand. When anything is unsettled, pressing the button shows exactly what
   and asks for confirmation; nothing disables it. After approval the box says "Approved
   as `<version>`; waiting for the release job", then "Released as `<version>`".

With several code repos, sections 3 to 5 repeat per repo under the repo's name, and
section 7 releases one repo at a time.

**When the git host cannot be read,** the page shows the header and one sentence saying
so, and nothing else. It never shows a checklist with guessed state.

## Build it in three steps

Each step is one ticket and leaves something the stakeholder can use.

| Step | What it adds | What it needs |
|---|---|---|
| 1. Bubble and read-only view | The bubble; sections 1, 3, 4 (without buttons), 5 and existing notes | `QA_VIEW`; a read token for the git host. No login. |
| 2. Marks and feedback | The buttons and note boxes; the result sentence | The dev login (`SITE_ACCESS=restricted`); the token may write commit comments |
| 3. Approve and release | Section 7; the comment webhook; the `release` job | The release token, scoped to that job; protected release tags |

A project has a bubble after step 1.

## The parts that are the same in every project

These make one project's view, agents and release job readable by another's.

### `qa/checklist.yaml`

At the root of each code repo, read at the deployed commit, built into the image.

```yaml
items:
  - id: phone-width          # permanent; lowercase letters, digits and dashes
    title: The page reads well on a phone
    detail: Narrow the window. Nothing is cut off and nothing scrolls sideways.
    from: W-E6               # the W-item or issue this came from
```

`id` and `title` are required; `detail` and `from` are optional text. An id is never
reused for a different check. The id `general` is reserved. A missing file, an empty
list, a repeated id or a malformed id fails the build.

### The comment

Every mark, note, harness result and approval is one comment on the deployed commit,
written by the QA token's bot user:

```
qa:item phone-width rejected
by: dana

> The menu covers the logo below 400 px.
```

- **Line 1** is one of: `qa:item <id> approved|rejected|postponed`, `qa:feedback <id>`,
  `qa:feedback general`, `qa:harness pass|fail|skip <run-url>`, `qa:approve <version>`.
  Single spaces, nothing after the last word. A version is `vMAJOR.MINOR.PATCH`.
- **Line 2** is `by: <user>`: the dev-site user who acted, or the harness's own user.
  Line breaks in a user name are removed before writing.
- **An approval of something unsettled** has a third line, `overrides: <a>,<b>`, naming
  each: an item id, `harness`, `no-harness`, `behind-main`.
- **The note** follows a blank line, each line quoted with `> `, and every `@` followed
  by a zero-width space, so the git host runs no command from it and notifies nobody.
  Reading it back removes both.

### Reading comments

- Only comments by the bot user count. Anything whose first two lines do not parse is not
  a QA comment and is ignored, including a QA line that appears inside a note.
- Order by the comment's time as an instant, never as text; ties keep the host's order.
- The latest mark on an item wins. A mark for an id not on this commit's checklist is
  ignored. An item with no mark is "to check".
- A mark's note is shown with that item's feedback.
- The latest `qa:harness` is the commit's result; the latest `qa:approve` is its approval.

The cases in [`_stubs/qa/grammar-cases.yaml`](_stubs/qa/grammar-cases.yaml) say this
exactly. Copy the file into the repo and make the parser's tests read it: a port in any
language proves it reads the same comments by passing the same cases.

### Settings

| Name | Values | Meaning |
|---|---|---|
| `QA_VIEW` | `on` / `off`, required | Whether the bubble and `/qa` exist. `on` on dev only. |
| `SITE_ACCESS` | `restricted` / `open`, required | Dev is `restricted`: per-user passwords. |
| `QA_GIT_TOKEN_<REPO>` | secret | One token per repo, the lowest role that reads commits and writes commit comments. |
| `QA_BOT_USER_ID` | number | The token's own user; only its comments count. |

Names beyond these are the project's. All of them are `env.yaml` entries routed to the
dev environment only ([FWADR-041](adrs/fwadr-041-env-yaml.md)).

### What the view asks the git host

Four reads and one write, per repo: the head of `main`; the comments on the deployed
commit; the tags; the PRs merged since the last release tag; and "add a comment to this
commit". The token can do nothing else: no push, merge, tag or settings.

## What to test

Tier 1, no network: the checklist loader's refusals; the grammar cases; the state built
from a list of comments; the next version; that a post from another origin is refused;
that `/qa` is 404 and the bubble absent with `QA_VIEW=off`. The release job's checks
(`dev-environment.md` §"Release by approval", step 3) get their own cases, one per check.
