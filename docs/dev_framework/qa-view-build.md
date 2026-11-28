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
- **What:** a 44 px circle labelled `QA`, with the accessible label "Open the QA view".
  Pressing it opens the view **as an overlay over the page the stakeholder is on**, so
  the thing under review stays behind it. It is built as a plain link to `/qa`: where
  script does not run, the link opens the view as a page.
- **Look:** colours and type come from the project. Position, size and label do not, so
  the stakeholder finds it in the same place on every project.
- **When:** rendered by the app's outermost layout when `QA_VIEW` is `on`. With `off` it
  is not in the page at all, and `/qa` answers 404. `QA_VIEW` has no default: a missing
  value stops the app at start.
- **Cost:** the bubble loads nothing. The view's data is fetched only when the bubble is
  pressed or `/qa` is opened, because the view calls the git host.

### The overlay

- A panel over the current page, with the page dimmed behind it: full screen at phone
  width; at desktop width a column from the left edge, no wider than the view itself,
  so the page stays visible beside it.
- It shows the same server-rendered view as `/qa`, fetched when the bubble is pressed. It
  is one view shown two ways, never a second implementation.
- It closes with a close button, the Escape key, or a press on the dimmed page, and
  leaves the page where it was: same scroll position, nothing reloaded. Focus moves into
  the panel on opening and back to the bubble on closing.
- An action inside it (a mark, feedback, the release) posts as it does on the page and
  the panel shows the result; the overlay stays open and the page behind is untouched.
- The bubble stays visible while the overlay is open and closes it when pressed again.

## The view

The same content in the overlay and at `/qa`: a single column no wider than a
comfortable line of text, readable on a phone. Every action is an ordinary form post
that returns to the view with a result, so `/qa` works without client-side script. Top
to bottom:

1. **Header.** "QA", the title "Release checklist", the deployed commit in full, whether
   it is `main`'s head, and a link back to the site.
2. **Result of the last action,** when there is one: one sentence ("Saved." / "The git
   host did not accept that. Nothing was saved; try again.").
3. **What was tested.** The harness result for the deployed commit: each suite and case by
   its plain-language title, passed, failed or skipped, with a one-line reason for
   anything not passed. Nobody marks this list. No result for this commit is said in
   words, not shown as green.
4. **The checklist: everything not yet released.** One card per item (§"Which items
   show, and which marks count"):
   - the title, and a status pill: **To check**, **Approved**, **Rejected** or
     **Postponed**, followed by who made the mark, and, when the mark was made on an
     earlier commit than the one deployed, that commit's short id and how many commits
     ago ("Approved by dana on `1a2b3c4`, 3 commits ago");
   - "carried from `<version>`" on an item that was released without being approved;
   - the detail line: what to look at and what right looks like;
   - the notes already written on this item, oldest first, each with its author and time;
   - a note box and four buttons: **Approve**, **Reject**, **Postpone**, **Send
     feedback**. The button for the item's current state is filled; the others are
     outlined. Reject and Send feedback need a note; Approve and Postpone take one
     optionally.
5. **What changed.** The PRs merged since the last release, each a link to the git host.
6. **Waiting for you** (a project on a Paperclip board). One row per ticket carrying
   `fdr_qa_1` or `fdr_qa_2`, read from the board: its title, a link to it, the builder's
   "what to try", a note box, and one button: **QA complete** in the first round,
   **Accept** in the second, with a "keep the flag" tick beside Accept. Pressing posts a
   comment on the ticket whose first line is `QA complete` or `Accept` (`Accept, keep
   the flag` when ticked), then the note, then who pressed and on which commit. A note
   with no press goes with "Send to the team" and leaves the ticket waiting. The
   buttons are shown to, and accepted from, a named person's own sign-in only: never the
   harness's user or any shared account.
7. **Still behind a flag.** Every flag in the code's list at the deployed commit: its
   name, its ticket and how long ago it was added. These are released switched off.
8. **Anything else.** General feedback since the last release, each with the commit it
   was written on, then a box and a Send feedback button.
9. **Send to the team** (a project on a Paperclip board). One button, with the count of
   notes and rejections not yet sent. It posts one comment per affected ticket and one
   new Strategist ticket for general feedback
   ([`dev-environment.md`](dev-environment.md) §"Feedback from the QA view"), and records
   what it sent so nothing is sent twice. A note deleted before the press is not sent.
10. **Release.** A version field, filled with the next patch after the highest release
   tag (`v0.0.1` when there is none), and **Approve release**. Above it, one sentence on
   where things stand. When anything is unsettled, pressing the button shows exactly what
   and asks for confirmation; nothing disables it. A ticket still waiting for the
   stakeholder is not unsettled when its work is behind a flag: it is listed as
   "ships off". After approval the box says "Approved
   as `<version>`; waiting for the release job", then "Released as `<version>`".

With several code repos, sections 3 to 5 repeat per repo under the repo's name, and
section 10 releases one repo at a time.

**When the git host cannot be read,** the page shows the header and one sentence saying
so, and nothing else. It never shows a checklist with guessed state.

## Build it in three steps

Each step is one ticket and leaves something the stakeholder can use.

| Step | What it adds | What it needs |
|---|---|---|
| 1. Bubble and read-only view | The bubble and its overlay; sections 1, 3, 4 (without buttons), 5 and existing notes | `QA_VIEW`; a read token for the git host. No login. |
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
- **An approval that releases items not approved** has a line `carried: <a>,<b>` after
  that: every checklist item shown at approval that was open, rejected or postponed.
  Those stay on the list after the release.
- **The note** follows a blank line, each line quoted with `> `, and every `@` followed
  by a zero-width space, so the git host runs no command from it and notifies nobody.
  Reading it back removes both.

### Reading comments

- Only comments by the bot user count. Anything whose first two lines do not parse is not
  a QA comment and is ignored, including a QA line that appears inside a note.
- Order by the comment's time as an instant, never as text; ties keep the host's order.
- A mark for an id not on the deployed commit's checklist is ignored. An item with no
  mark is "to check". A mark's note is shown with that item's feedback.
- The latest `qa:harness` **on the deployed commit** is its result, and the latest
  `qa:approve` on it is its approval. Neither carries from another commit.

### Which items show, and which marks count

Dev redeploys on every merge, so a mark has to outlive the commit it was made on, and
the list has to shrink when work is released.

- **Marks count since the last release.** A mark is written on the deployed commit. The
  view reads the QA comments on every commit of `main` after the last release tag, up to
  the deployed commit, as one list: the latest mark on an item wins, whichever commit it
  is on. Feedback is gathered the same way.
- **An item leaves the list when it is released approved.** Nobody edits the file to
  remove it. The view reads `qa/checklist.yaml` at the last release tag and that
  release's approval: an item that was on the checklist at the tag is not shown, unless
  the approval names it under `carried:` (an approval from before that line existed
  carries the item ids in its `overrides:`). A carried item starts again at "to check".
- **A released check that needs looking at again is a new item with a new id.**
- **No release tag yet:** every item shows and marks are read from the start of `main`.
- **A limit, said out loud.** The view reads at most 200 commits back. When there are
  more, it says so above the checklist; it never shows a shorter history as the whole.
- Comments on a commit that is no longer deployed do not change, so the view may keep
  them for as long as it runs; only the deployed commit is read fresh each time.
- The `release` job reads marks the same way when it checks what is unsettled.

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
| `QA_BOARD_API_KEY` | secret | Paperclip board only: a person's key, for a user made for the view and limited to the one company. Reads the waiting tickets and comments on tickets. |

Names beyond these are the project's. All of them are `env.yaml` entries routed to the
dev environment only ([FWADR-041](adrs/fwadr-041-env-yaml.md)).

### What the view asks the git host

Reads and one write, per repo: the head of `main`; the tags; the commits after the last
release tag; the comments on each of those and on the tagged commit; `qa/checklist.yaml`
at the tag; the PRs merged since the tag; and "add a comment to this commit". The token
can do nothing else: no push, merge, tag or settings.

## What to test

Tier 1, no network: the checklist loader's refusals; the grammar cases; the state built
from a list of comments; the carry cases (marks across commits, items released); the
next version; that a post from another origin is refused;
that `/qa` is 404 and the bubble absent with `QA_VIEW=off`. The release job's checks
(`dev-environment.md` §"Release by approval", step 3) get their own cases, one per check.
