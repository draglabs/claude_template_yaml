# FWADR-044: Dev slots are handed out by a slot supervisor the framework owns

**Status:** accepted; running on one slot server with no project template yet
**Date:** 2026-11-23
**Deciders:** user (framework author) + Template Developer
**Piloted in:** none yet. ThankMu is the first project to add a slot template.

## Context

On a Paperclip board every builder tries its work somewhere. With one shared dev site,
two tickets cannot be tried at once, and agents that needed a database of their own
started one by hand: two Postgres containers from finished tickets were still running on
ThankMu's server weeks later, one published on every interface. The user's model comes
from how slots worked on his own machine ([FWADR-019](fwadr-019-dev-slots-and-deploy-stubs.md)):
the agent brings its branch up on a slot where "services like Postgres would already be
running and seeded… If there was a problem, it could restart the dev slot, no big deal."

## Decision

1. **A slot is started on request and lives a fixed 8 hours from start.** A ticket that
   outlasts it asks again. Nothing on a slot is precious.
2. **A slot supervisor hands slots out.** The user: "we can expand the reaper over time
   to be a slot supervisor with a restful contract… a launch script simply has to go to
   the dev endpoint… and restfully request a dev slot; then the slot supervisor spins one
   up, tracks, and tells the developer what it needs to know." Five verbs — request,
   check, reset, release, list — and a reaper; specified in
   [`slot-supervisor.md`](../slot-supervisor.md).
3. **The record lives on the slot server,** rebuilt from what is actually running.
4. **The builder deploys its own branch.** The supervisor hands over a blank seeded slot
   and a way in, and knows nothing about how a project builds.
5. **The framework owns the supervisor.** It serves every project on a server, so it is
   no project's. The code is in the template repo under `slot_supervisor/`, and every
   change to it goes through the Template Developer.
6. **It runs as a service on the slot server's host,** under systemd, with a timer for
   the reaper — not as a container. A container that starts containers needs the Docker
   socket, which is the same power as the host, and compose resolves bind paths on the
   host.
7. **Built for scale:** one template and one cap per project, a limit on running slots
   per server, a token per project, and a slot that is off reserves nothing. The user:
   "we will end up having dozens of slots. Maybe 6 for this one project but 10 projects
   later… the vast majority offline at any one time."

## Honest ceiling

- **No project's app has run on a slot.** On 2026-11-23 the first slot server started,
  reused, reset and released a slot from the example template; that is all.
- **Container labels are the record, and a deploy can lose them.** A deploy that
  recreates every container without the supervisor's override file hides the slot.
- **Serving an app under a path is unsolved in general.** Most apps assume they sit at
  `/`; a project that picks a site by hostname needs more than one path; cookies are
  shared across paths on one host. Each project's template has to answer this before
  its slots are usable.
- **No check makes a project use slots.** A builder with no slot server tries its work
  on dev, as before.
- **Laptop slots (FWADR-019) are not yet under this contract.**

## Consequences

- An agent no longer starts its own database on a shared host; the leftovers stop with
  the reaper.
- The slot server needs a front door with a certificate, and a limit that leaves room
  for the CI runner and the agents where they share the host.
- **Coherence surfaces:** this ADR; `slot-supervisor.md`; `paperclip-mode.md` §"Dev
  slots"; the Parallel Developer's agent file; `slot_supervisor/`.

## Alternatives considered

- **Each project builds its own slots:** as many reapers as projects, on one server.
- **The supervisor as a container:** ships as an image, but adds no safety and makes
  templates awkward.
- **Slots that live as long as their ticket:** needs the supervisor to read the board,
  and a stuck ticket holds a slot for days.
