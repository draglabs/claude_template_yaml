# FWADR-045: On a board, the founder tries the work before a refactor developer reviews it and acts; unaccepted work sits behind a feature flag

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

1. **The order on every ticket:** the builder builds behind a flag → self-test → merge →
   the founder's QA round 1 ("QA complete") → the refactor developer reviews, decides
   and acts, in one round → the founder's QA round 2 ("Accept") → the flag is removed →
   the Lead's rundown. Specified in [`paperclip-mode.md`](../paperclip-mode.md)
   §"Self-test, two QA rounds, one technical review". Big work held by the Orchestrator
   takes the same path.
2. **The self-test is the builder's own and asks two questions:** do tests confirm the
   feature, and is it the feature that was asked for. No separate agent.
3. **Only the founder declares "QA complete" and "Accept".** "It means that the user
   tested it and the human said it was done." No agent presses or writes either, and the
   QA view takes them only from a named person's own sign-in.
4. **A new agent, `FW_Refactor_Developer`, does the review and acts on it.** The user:
   "we can mint a new agent and call it refactor dev, first it acts as code review then
   it reads the evaluation criteria, then acts on the code review analysis based on the
   items. That saves at least 20 minutes of re-reading time." It did not write the
   code, so the review is still fresh eyes; it reads the code once, where a Reviewer
   subagent and then a builder started cold each read it. It comes after round 1 so that
   "it's technically reviewing something that works, not technically reviewing the wrong
   thing." Its guide is [`paperclip-refactor.md`](../paperclip-refactor.md).
5. **It decides per item before it changes anything, and it is expected to decline.**
   An ADR violation, a broken coding standard and an acceptance criterion not met are
   always acted on. Everything else is weighed against written criteria. The user's
   measure: "the refactor Dev will not act on at least a third of the code review items
   because it deemed them whatever overly defensive etc." One round; nothing it changes
   is reviewed again; declined items are listed, the Lead recommends, the founder
   decides.
6. **It trims the tests.** Builders work test-first and leave more tests than the
   product needs. The refactor developer refactors the ticket's tests "toward more
   practical targeted proof of function tests while eliminating the majority of routine
   bloat tests": the same behaviour re-tested by another path, assertions on internals,
   a test per trivial input, tests that break on a refactor nobody can see. Its reach is
   the ticket's tests and an older test in the same file that tests the same thing. The
   user's measure: "this will make testing both faster more useful and less cumbersome."
7. **The fast tier has a hard limit.** "If a deploy takes longer than 15 minutes i
   consider the fast tier as failing. We can actually program that in as a hard limit on
   CI." From merge to live on dev is 15 minutes at most, as the CI timeout.
8. **Every ticket goes through both rounds,** one with nothing to try included.
9. **The ticket has one holder at a time and two hand-offs:** the builder until "QA
   complete", the refactor developer until the Lead. While it waits for the founder it
   is `blocked` with `fdr_qa_1` or `fdr_qa_2`. The QA view's "QA complete" press passes
   the ticket to the refactor developer in the same update as the founder's comment;
   typed by hand, the comment wakes the builder, which passes it on.
10. **Feature flags are a protocol.** "Feature flags will control what's live on
   production and what's still in testing and QA on dev." One required setting per
   environment turns unaccepted work on (dev) or off (production); flags are declared in
   one list in the code; both states are tested; migrations are never flagged. The rules
   are in [`coding-standards.md`](../coding-standards.md) §"Feature flags"; the mechanism
   is the project's. A fix to a live feature, CI and infrastructure carry no flag, and
   only when the ticket, written by the Strategist, says so.
11. **The flag is removed after the second Accept,** in a change that holds nothing else,
   "unless otherwise specified by me."
12. **The release is unchanged.** "CI takes prod flat to production, and that happens
   when i click that cut release tag button." The founder's Accept settles a feature;
   it reaches production at his next release
   ([FWADR-042](fwadr-042-qa-view-release.md)). Work still behind a flag is released
   switched off, so a release never waits for a ticket. No agent's merge deploys
   production.

## Honest ceiling

- **English-only:** that the self-test stays at two questions, that no agent writes the
  founder's words, and that the refactor developer declines. Builders told to weigh each
  finding still took about nine in ten ([FWADR-040](fwadr-040-paperclip-mode.md)): a
  careful agent settles a doubt by doing the work. What is different here is that every
  item is marked before any code changes and the share declined is on every rundown. If
  the first tickets come back near nine in ten, the criteria are what to tighten.
- **Whoever reviews also decides and acts,** so nothing checks its changes but its own
  tests and the founder's second round.
- **A trimmed test can be one that was protecting something.** The reach is kept narrow
  for that reason. The second has one mechanical part, the view's sign-in check,
  which each project builds.
- **The flag's removal is merged after the founder's last check.** It is covered by the
  tests of the "on" state and by the dev harness, not by him.
- **Two more runs per ticket,** one of them a new agent's first read of the ticket.
  Typed by hand, "QA complete" costs a third: the builder's run that passes it on.
- **A fix to a live feature reaches production at the next release whether or not the
  founder has finished its rounds;** the release press lists it as unsettled.
- **Code the review faults is already merged,** and other work may be built on
  it. That is the price of the founder trying work sooner.

## Consequences

- A seventh agent in the package, `FW_Refactor_Developer`, with its guide. No Reviewer
  subagent is spawned on a board.
- Two labels, `fdr_qa_1` and `fdr_qa_2`, created by `paperclip_company.py sync`; the
  Lead and the meter treat them as waiting on the founder, never as a stall.
- The 15-minute limit is each project's CI configuration to set.
- The QA view gains the two presses, the list of flags, and "Send to the team".
- A project adopting flags with unreleased, unflagged work on `main` decides once
  whether that work is accepted as live or flagged first.

## Alternatives considered

- **Review before the merge, the verdict deciding** (the rule this replaces): kept the
  review in front of the founder's QA for no change in what merged.
- **A Reviewer subagent after round 1, the builder acting on its blocking findings:**
  the builder starts cold and re-reads what the Reviewer just read, and nobody trims
  the tests.
- **Every merge deploys production, no release tag:** considered and set aside by the
  user; the release press stays the one human gate on production.
- **A flag per environment entry in `env.yaml`:** every new flag would wait for the
  operator's machine, since agents never hold that file's key.
