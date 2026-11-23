# Dev slots and the slot supervisor

A **dev slot** is a blank, seeded runtime for one project on a shared slot server: its
database and other services already up and seeded, nothing of the ticket in it yet. A
builder working a ticket asks for one, deploys its own branch onto it, tries the work
there, and can reset it. Decided in [FWADR-044](adrs/fwadr-044-slot-supervisor.md).

The user's model: the agent brings its branch up on a slot where "services like Postgres
would already be running and seeded… If there was a problem, it could restart the dev
slot, no big deal."

## The rules

- **A slot is started on request and lives a fixed 8 hours from its start.** A ticket
  that outlasts its slot asks again and gets a fresh one. A reset does not extend it.
- **Nothing on a slot is precious.** The code is in git and the data is the seed.
- **The record of who holds a slot is on the slot server,** read from what is actually
  running. It is not in the planning repo and not on the board.
- **The supervisor knows nothing about how a project builds.** It hands over a blank
  seeded slot and a way in; the builder deploys its branch with the project's own deploy
  script.
- **A running slot is reached at `https://<slot server>/<slot name>/`.** The slot
  server's name is the project variable `SLOTS_URL`.
- **A slot that is off reserves nothing:** no port, no route, no container.

## The contract

One piece of software, the **slot supervisor**, owned by the framework and kept in the
template repo under `slot_supervisor/`. The same five verbs are a command on the server
(`slot …`) and a web interface; the exact shapes are in that directory's README.

| Verb | What it does | Answers with |
|---|---|---|
| **request** (project, ticket, agent) | Returns the ticket's slot if it has one running; otherwise starts a free one from the project's template and seeds it. Refuses when the project is at its cap or the server at its limit | The slot's name and address, when it expires, the way in to deploy, how to reach its database and logs |
| **check** (slot) | Reports one slot | Running or stopped, who holds it, expiry, health |
| **reset** (slot) | Drops the data, reseeds, restarts | State |
| **release** (slot) | Stops it and frees what it reserved | Nothing |
| **list** | Every slot the caller may see | What the board meter reads |

A **reaper** on a timer stops every slot past its expiry.

## What a project provides

- **A slot template:** the compose file for a blank runtime, the seed command and a
  prepared dump (every start seeds, so it must be fast), a health path, and a cap on how
  many of its slots may run at once.
- **A token** that reaches only that project's slots, an `env.yaml` entry routed to the
  `paperclip` place ([FWADR-041](adrs/fwadr-041-env-yaml.md)).
- **A deploy script that can target a slot,** and an app that can be served under a path
  prefix, or a template that says the prefix is stripped.
- A line in the project's Paperclip section naming the slot server.

## Scale

Dozens of slots across many projects, most of them off at any moment. A slot is a
project plus a number. The server has a limit on running slots that leaves room for
whatever else it hosts.

## Laptop slots

The slots of [FWADR-019](adrs/fwadr-019-dev-slots-and-deploy-stubs.md)
(`launch_local.sh <slot>`) are the same idea on one machine with a person in the chair.
They keep their scripts for now; one contract for both is the direction, not yet built.
