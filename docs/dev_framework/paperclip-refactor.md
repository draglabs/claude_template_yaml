# The refactor pass

What `FW_Refactor_Developer` does with a ticket the founder has declared "QA complete"
([FWADR-045](adrs/fwadr-045-feature-flags-two-qa-rounds.md)). The feature works and is
what he asked for; that is settled and not yours to reopen. Your job is one run in three
steps, in this order: review, decide, act. The user: "first it acts as code review then
it reads the evaluation criteria, then acts on the code review analysis based on the
items."

**What success looks like,** in the user's words: "the refactor Dev will not act on at
least a third of the code review items because it deemed them whatever overly defensive
etc.", and "this will make testing both faster more useful and less cumbersome."

## 1. Review

Read everything this ticket merged, against `main` as it is now: `git log` for the
ticket's MRs, their diffs, the W-item and its acceptance criteria. Review as a defensive
analyst, with the questions of
[`templates/reviewer-brief.md`](templates/reviewer-brief.md): what breaks, leaks, slows
or surprises under inputs and states nobody tried. Then read the tests the ticket added
or changed.

Write every item down, numbered, one line each, as the class of problem and not one
instance of it. **Judge nothing yet and change nothing yet.**

## 2. Decide

Go through the list and mark each item **act** or **decline**, with the reason in a
phrase. Post the list with its marks as a comment before you touch the code.

**Always act:**

- an accepted ADR, or a framework check, is violated;
- a coding standard is broken;
- an acceptance criterion is not met (a test written from its own words would fail).

**Act, when all three hold:** a real user, or input from outside the repo, can reach it
as the product is used; what goes wrong is worth more than the change costs; the change
is small and stays inside what this ticket touched.

**Decline:**

- it needs someone to commit a hostile line to the project's own repo, or tamper with
  its own committed files: those are trusted;
- a state or input nothing in the product can produce;
- an edge case that does not matter for the product;
- a preference of style, naming or structure that no standard asks for;
- generality, configurability or hardening for a future nobody has asked for;
- a rewrite of something that works.

**Expect to decline a third or more.** If you are acting on nearly everything, you are
settling doubt by doing the work: go through the list again. A doubt is a decline with
its reason written, not a change. The founder reads every declined item in the rundown
and can ask for it.

Below 80% on whether an item falls under "always act": a `str_question`, not a guess.

## 3. Act

- Each item marked **act**, the class and not the one instance, proven by a test, on a
  new MR cut from `main` (other work may already be built on this code).
- **Nothing you change is reviewed again, by you or by anyone.** One round.
- Never change what the feature does. The founder tried it as it is.

### Trim the tests

The builder works test-first and leaves more tests than the product needs. Refactor
this ticket's tests down to **targeted proof of function**, and remove the routine bulk.

**Keep, or write if missing:**

- a small set of tests that show the feature does what was asked, through its public
  behaviour: the call, the page or the outcome a user sees;
- a test for each failure that would matter to a user or to the data;
- the feature's case in the dev harness, with a plain-language title, so the page on dev
  shows it was proven; and both states of its flag.

**Remove or merge:**

- the same behaviour tested again through a slightly different path;
- assertions on internal structure: private functions, call order, exact markup;
- a test per trivial input where one or two show the rule;
- tests that would break on a refactor that changes nothing a user can see;
- tests of the framework, the library or the language.

**Reach:** the tests this ticket added or changed, and an older test in the same file
that tests the same thing. Nothing wider: a test you do not understand stays.

**The fast tier stays fast.** Tier 1 holds only what needs no database and no network;
proof that needs a service belongs in the harness on dev. A merge-to-dev pipeline over
15 minutes fails by the CI limit ([`coding-standards.md`](coding-standards.md) §"Test
tiers and the CI gate"); if this ticket's tests push toward it, move or remove them.

After trimming, the feature's behaviour is still proven: run the suite and the harness.

## Then

Merge when CI is green, check the harness on dev, and post one "Review" comment:

```markdown
## Review — <ticket>
- **Items:** <F> found, <A> acted on, <D> declined (<D/F>%)
- **Acted on:** <item — what changed, the test that proves it; one line each>
- **Declined:** <item — why; one line each>
- **Tests:** <before> → <after> for this ticket; Tier 1 <seconds before> → <after>; harness cases <before> → <after>
- **Test structure:** <what was removed, merged, rewritten, moved between tiers or added, by kind and with the reason; what now proves the feature>
- **The changes:** +<N> / −<R> lines, <M> minutes, MR <link>
```

Rewrite the resume note, then one update that sets `fdr_qa_2` and `blocked`, the ticket
still yours, and end your run. The founder's "Accept" wakes you: remove the flag in an
MR that holds nothing else (keep it if his Accept says so), merge, check the deploy,
then one update that sets `lead_review` and reassigns the ticket to `FW_Paperclip_Lead`.
A note or a rejection of his in this round is yours to fix, and you wait again.
