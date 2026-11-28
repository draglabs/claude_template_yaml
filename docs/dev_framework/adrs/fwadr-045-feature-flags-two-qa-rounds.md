# FWADR-045: On a board, the founder tries the work before its code is reviewed; unaccepted work sits behind a feature flag

**Status:** accepted; not yet run on any board
**Date:** 2026-11-27
**Deciders:** user (framework author) + Template Developer
**Piloted in:** none yet. ThankMu is first; its own decision record holds the flag mechanism.

## Context

On a Paperclip board the builder's Reviewer ran before the merge
([FWADR-040](fwadr-040-paperclip-mode.md)). Two rules for acting on its findings were
tried. Under both, the review sat between the founder and the work: 20 to 70 minutes a
ticket, and under the second rule both tickets came back with 0 blocking findings, so
the review changed nothing that merged. Meanwhile the founder could find, on trying the
work, that it was not what he asked for, after its code had been defended in detail.

The user (2026-11-27): "Dev will build and it'll run its own QA review. But its QA
review will be primarily to make sure that it has tests that confirm the functionality
of the feature it just delivered. And it will confirm that the feature it just delivered
is the feature that was asked for... once it passes that, and that's a self-test, it
will merge directly to dev, where a human can do the next test. Once that next test has
been completed by me, I mark it QA complete, then it will run the second code review,
which is more of a technical code review and gives greater flexibility to Claude to be a
defensive analyst than a accepting developer."

## Decision

1. **The order on every ticket:** build behind a flag → self-test → merge → the
   founder's QA round 1 ("QA complete") → the technical review, one round of fixes → the
   founder's QA round 2 ("Accept") → the flag is removed → the Lead's rundown. Specified
   in [`paperclip-mode.md`](../paperclip-mode.md) §"Self-test, two QA rounds, one
   technical review".
2. **The self-test is the builder's own and asks two questions:** do tests confirm the
   feature, and is it the feature that was asked for. No separate agent.
3. **Only the founder declares "QA complete" and "Accept".** "It means that the user
   tested it and the human said it was done." No agent presses or writes either, and the
   QA view takes them only from a named person's own sign-in.
4. **The technical review comes after round 1,** so that "it's technically reviewing
   something that works, not technically reviewing the wrong thing." What gets fixed is
   unchanged: blocking findings, in one round, never re-reviewed; concerns are listed,
   the Lead recommends, the founder decides. "I like how we've been categorizing things
   worth fixing. I just don't like the time we're wasting on it, jamming up QA cycles."
5. **Every ticket goes through both rounds,** one with nothing to try included.
6. **The ticket stays with its builder** from the start to the hand-off for the rundown,
   `blocked` with `fdr_qa_1` or `fdr_qa_2` while it waits. The founder's press is a
   comment in his name, which wakes the builder.
7. **Feature flags are a protocol.** "Feature flags will control what's live on
   production and what's still in testing and QA on dev." One required setting per
   environment turns unaccepted work on (dev) or off (production); flags are declared in
   one list in the code; both states are tested; migrations are never flagged. The rules
   are in [`coding-standards.md`](../coding-standards.md) §"Feature flags"; the mechanism
   is the project's. A fix to a live feature, CI and infrastructure carry no flag, and
   only when the ticket, written by the Strategist, says so.
8. **The flag is removed after the second Accept,** in a change that holds nothing else,
   "unless otherwise specified by me."
9. **The release is unchanged.** "CI takes prod flat to production, and that happens
   when i click that cut release tag button." The founder's Accept settles a feature;
   it reaches production at his next release
   ([FWADR-042](fwadr-042-qa-view-release.md)). Work still behind a flag is released
   switched off, so a release never waits for a ticket. No agent's merge deploys
   production.

## Honest ceiling

- **English-only:** that the self-test stays at two questions, and that no agent writes
  the founder's words. The second has one mechanical part, the view's sign-in check,
  which each project builds.
- **The flag's removal is merged after the founder's last check.** It is covered by the
  tests of the "on" state and by the dev harness, not by him.
- **Two more cold starts per ticket** (after each press), each a few dollars on one
  board's figures; the resume note written before each wait is what keeps them short.
- **A fix to a live feature reaches production at the next release whether or not the
  founder has finished its rounds;** the release press lists it as unsettled.
- **Code the technical review faults is already merged,** and other work may be built on
  it. That is the price of the founder trying work sooner.

## Consequences

- The Reviewer brief describes a defensive review of merged work on a board.
- Two labels, `fdr_qa_1` and `fdr_qa_2`, created by `paperclip_company.py sync`; the
  Lead and the meter treat them as waiting on the founder, never as a stall.
- The QA view gains the two presses, the list of flags, and "Send to the team".
- A project adopting flags with unreleased, unflagged work on `main` decides once
  whether that work is accepted as live or flagged first.

## Alternatives considered

- **Review before the merge, the verdict deciding** (the rule this replaces): kept the
  review in front of the founder's QA for no change in what merged.
- **Every merge deploys production, no release tag:** considered and set aside by the
  user; the release press stays the one human gate on production.
- **A flag per environment entry in `env.yaml`:** every new flag would wait for the
  operator's machine, since agents never hold that file's key.
