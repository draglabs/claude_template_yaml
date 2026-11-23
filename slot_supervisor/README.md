# Slot supervisor

A small service that hands out **dev slots** on a shared dev server.

A slot is a blank, seeded runtime for one project: its database and other
services are up and seeded. An agent working a ticket asks for a slot, deploys
its own branch onto it with the project's own deploy script, tries its work
there, and can reset it.

This is a first version. It has run on one server with the example template
(start, reuse, reset, release, reap); no project's app has run on it yet. See
[Not yet proven](#not-yet-proven).

## The rules it keeps

- A slot is a project plus a number: `<project>-<n>`, for example `thankmu-2`.
- A slot is started on request and lives a **fixed 8 hours from start**. A
  ticket that outlasts its slot asks again and gets a fresh one. Nothing on a
  slot is precious.
- One template per project, and a cap per project. One limit on running slots
  for the whole server.
- A slot that is off reserves nothing: no port, no proxy route, no container,
  no directory.
- The supervisor keeps **no record of its own**. Who holds a slot is written as
  labels on the slot's containers, and every call reads them again. Restart the
  supervisor, or delete it and install it again, and it sees the same slots.
- The supervisor knows nothing about how a project builds. It gives a blank
  seeded slot and a way in.
- A running slot is reached at `https://<SLOTS_HOST>/<slot>/`.
- A token per project reaches only that project's slots. One admin token
  reaches everything.

## The contract

Six verbs. The CLI and the HTTP API call the same functions.

| Verb | CLI (on the slot server) | HTTP | Does |
|---|---|---|---|
| request | `slot request --project P --ticket T --agent A` | `POST /api/slots` | Returns the ticket's running slot if it has one. Otherwise starts a free one from the project's template, seeds it and routes it. Refuses when the project is at its cap or the server at its limit |
| check | `slot check <slot>` | `GET /api/slots/<slot>` | Reports one slot: running or stopped, holder, expiry, health |
| reset | `slot reset <slot>` | `POST /api/slots/<slot>/reset` | Drops the data, reseeds, restarts. Does **not** move the expiry |
| release | `slot release <slot>` | `DELETE /api/slots/<slot>` | Stops the slot and frees its ports, route and directory |
| list | `slot list [--project P]` | `GET /api/slots[?project=P]` | Every running slot the token can see |
| reap | `slot reap` | `POST /api/reap` (admin only) | Stops every slot past its expiry |

Also: `slot serve` runs the HTTP API, and `GET /api/healthz` answers
`{"ok": true}` without a token.

### CLI

The CLI runs on the slot server and needs no token: whoever can run it there
can already run docker there. It sees every project.

- Output is JSON on standard output. `release` prints nothing.
- Exit code 0 on success. Exit code 1 on a refusal, with
  `{"error": {"code": ..., "message": ...}}` on standard error.
- `slot reap` also exits 1 when it could not stop a slot, so the timer's unit
  shows as failed.

### HTTP

Every call except `/api/healthz` needs `Authorization: Bearer <token>`.
Bodies are JSON both ways.

```
curl -X POST https://$SLOTS_HOST/api/slots \
  -H "Authorization: Bearer $TOKEN" \
  -d '{"project": "thankmu", "ticket": "THA-49", "agent": "fw-parallel-developer"}'
```

| Call | Request body | Success | Body |
|---|---|---|---|
| `POST /api/slots` | `{"project", "ticket", "agent"}`, all three required | `201` when it started a slot, `200` when the ticket already had one | slot, full shape, plus `"created"` |
| `GET /api/slots/<slot>` | none | `200` | slot, full shape; or the stopped shape |
| `POST /api/slots/<slot>/reset` | none | `200` | slot, full shape |
| `DELETE /api/slots/<slot>` | none | `204` | empty. Also `204` when the slot was not running |
| `GET /api/slots` | none | `200` | the list shape |
| `POST /api/reap` | none | `200` | `{"stopped": ["thankmu-1"], "failed": [{"slot": ..., "error": ...}]}` |
| `GET /api/healthz` | none | `200` | `{"ok": true}` |

`project` is a lower-case name (`thankmu`, `my-app`). `ticket` and `agent` are
1 to 100 letters, digits, spaces or `. _ : # / @ -`.

### A slot, full shape

What `request`, `check` (running) and `reset` answer with:

```json
{
  "slot": "thankmu-1",
  "project": "thankmu",
  "number": 1,
  "state": "running",
  "ticket": "THA-49",
  "agent": "fw-parallel-developer",
  "started_at": "2026-11-23T09:00:00Z",
  "expires_at": "2026-11-23T17:00:00Z",
  "expired": false,
  "url": "https://slots.example.com/thankmu-1/",
  "ports": {"app": 20000, "db": 20001},
  "health": {"ok": true, "detail": "2 of 2 containers running; http://localhost:20000/healthz: HTTP 200"},
  "deploy": {
    "host": "slots.example.com",
    "user": "deploy",
    "directory": "/srv/slots/work/thankmu-1",
    "compose_project": "thankmu-1",
    "env_file": "/srv/slots/work/thankmu-1/.env",
    "compose_files": [
      "/srv/slots/templates/thankmu/compose.yaml",
      "/srv/slots/work/thankmu-1/compose.slot.json"
    ],
    "env": {
      "COMPOSE_PROJECT_NAME": "thankmu-1",
      "COMPOSE_FILE": "/srv/slots/templates/thankmu/compose.yaml:/srv/slots/work/thankmu-1/compose.slot.json",
      "SLOT_NAME": "thankmu-1",
      "SLOT_PROJECT": "thankmu",
      "SLOT_NUMBER": "1",
      "SLOT_URL": "https://slots.example.com/thankmu-1/",
      "SLOT_BASE_PATH": "/thankmu-1",
      "SLOT_STRIP_PREFIX": "true",
      "SLOT_INTERNAL_PORT": "3000",
      "SLOT_UPSTREAM_HOST": "localhost",
      "SLOT_TEMPLATE_DIR": "/srv/slots/templates/thankmu",
      "SLOT_DIR": "/srv/slots/work/thankmu-1",
      "SLOT_PORT_APP": "20000",
      "SLOT_PORT_DB": "20001"
    }
  },
  "database": "postgres://app:app@slots.example.com:20001/app",
  "logs": "docker compose -p thankmu-1 logs",
  "created": true
}
```

- `created` is only in the answer to `request`.
- `expired` is true for a slot past its expiry that the reaper has not stopped
  yet. `request` never returns such a slot; it stops it and starts a fresh one.
- `health.ok` is true when every container of the slot is running and the
  template's `health_path` answers below HTTP 400 on the slot's `app` port.
- `database` is `null` when the template names none.
- `logs` is a command to run on `deploy.host`.

### A stopped slot

`check` on a slot that is not running (its number is within the project's cap):

```json
{"slot": "thankmu-2", "project": "thankmu", "number": 2, "state": "stopped",
 "ticket": null, "agent": null, "started_at": null, "expires_at": null}
```

### The list

Only running slots are listed; a stopped slot is nothing. Each item is the
full shape without `health`, `deploy`, `database` and `logs`.

```json
{
  "now": "2026-11-23T10:30:00Z",
  "max_running": 8,
  "slots": [
    {"slot": "thankmu-1", "project": "thankmu", "number": 1, "state": "running",
     "ticket": "THA-49", "agent": "fw-parallel-developer",
     "started_at": "2026-11-23T09:00:00Z", "expires_at": "2026-11-23T17:00:00Z",
     "expired": false, "url": "https://slots.example.com/thankmu-1/",
     "ports": {"app": 20000, "db": 20001}}
  ]
}
```

### Refusals

Every refusal is `{"error": {"code": "...", "message": "..."}}`.

| Code | HTTP | When |
|---|---|---|
| `invalid_request` | 400 | A bad slot name, project, ticket, agent or body |
| `unauthorized` | 401 | No token, or a token nobody has |
| `forbidden` | 403 | A project token used on another project, or to reap |
| `not_found` | 404 | No template for the project; a slot number above the cap; reset of a slot that is not running; an unknown route |
| `project_cap_reached` | 409 | The project already runs its cap of slots |
| `server_limit_reached` | 409 | The server already runs its limit, or the port range is used up |
| `config_error` | 500 | A missing setting or a broken template or tokens file |
| `runtime_failed` | 500 | Docker, the seed command or the proxy reload failed |
| `internal_error` | 500 | A bug |

On 409 the ticket waits and asks again later; nothing was started.

## How a developer uses a slot

1. `request`. Keep `slot`, `url`, `expires_at` and `deploy`.
2. Log in to `deploy.host` as `deploy.user`. Put what the deploy needs in
   `deploy.directory`.
3. Deploy the branch into the slot's compose project, keeping the supervisor's
   files in the command so the containers keep their labels:

   ```
   docker compose --env-file <env_file> -p <compose_project> \
     -f <compose_files[0]> -f <compose_files[1]> -f my-branch.compose.yaml up -d --build
   ```

   The app must listen so that it is reachable on `SLOT_PORT_APP`.
4. Open `url`. Use `database` and `logs` to look inside.
5. `reset` when the data is in a bad state. Reset gives back the blank seeded
   slot, so deploy again after it.
6. `release` when the ticket is done. If nobody does, the reaper stops the
   slot at `expires_at`.

The labels are the supervisor's only record. A deploy that recreates **every**
container without `compose.slot.json` removes them, and the supervisor no
longer sees the slot. Containers the deploy does not touch (usually the
database) keep theirs, and one labelled container is enough.

## Settings

All settings are environment variables. A missing required one stops the
command with an error that names it.

| Variable | Required | Meaning |
|---|---|---|
| `SLOTS_HOST` | yes | Public host name. Slots are at `https://<SLOTS_HOST>/<slot>/` |
| `SLOTS_UPSTREAM_HOST` | yes | Where the proxy and the health check reach a slot's ports, for example `localhost` |
| `SLOTS_TEMPLATES_DIR` | yes | Root of the project templates |
| `SLOTS_WORK_DIR` | yes | Root of the per-slot directories. Must exist. Holds only running slots and a lock file |
| `SLOTS_ROUTES_DIR` | yes | Where the per-slot Caddy snippets go. Must exist |
| `SLOTS_PORT_RANGE` | yes | Ports to hand out, as `low-high`, for example `20000-20999` |
| `SLOTS_MAX_RUNNING` | yes | Limit on running slots for this server |
| `SLOTS_PROXY_RELOAD_COMMAND` | yes | Command that makes the proxy read its routes again |
| `SLOTS_LISTEN` | for `serve` | `<host>:<port>` the HTTP API binds to |
| `SLOTS_TOKENS_FILE` | for `serve` | Path of the tokens file |
| `SLOTS_SSH_HOST` | no | Host a developer logs in to. Default: `SLOTS_HOST` |
| `SLOTS_TTL_HOURS` | no | Life of a slot in hours. Default: 8 |
| `SLOTS_COMMAND_TIMEOUT_SECONDS` | no | Longest one docker or seed command may run. Default: 600 |

### The tokens file

JSON, readable by its owner only (`chmod 600`; the server refuses to start
otherwise). Tokens are never taken from the command line and never logged.

```json
{
  "admin": "<token>",
  "projects": {
    "thankmu": "<token>",
    "other-project": "<token>"
  }
}
```

Every token must be at least 16 characters and different from the others.
The file is read once, when `slot serve` starts; restart it after a change.

## A project template

```
<SLOTS_TEMPLATES_DIR>/
  thankmu/
    compose.yaml     the blank slot: database, other services, a placeholder app
    slot.json        the settings below
    seed/…           whatever the seed command needs (a prepared dump)
```

`slot.json`:

```json
{
  "cap": 6,
  "ports": ["app", "db"],
  "internal_port": 3000,
  "strip_prefix": true,
  "health_path": "/healthz",
  "seed_command": ["docker", "compose", "exec", "-T", "db", "sh", "-c", "pg_restore -U app -d app /seed/app.dump"],
  "deploy_user": "deploy",
  "database": "postgres://app:app@{host}:{port_db}/app"
}
```

| Key | Meaning |
|---|---|
| `cap` | Most slots of this project that may run at once. Slots are numbered 1 to `cap` |
| `ports` | Names of the host ports a slot needs. Must include `app`, the one the proxy routes to. Each becomes `SLOT_PORT_<NAME>` |
| `internal_port` | The port the app listens on inside its container. Passed on as `SLOT_INTERNAL_PORT` |
| `strip_prefix` | `true`: the proxy removes `/<slot>` before the app sees the request. `false`: the app gets the full path |
| `health_path` | Path the health check asks for on the `app` port. Must start with `/` |
| `seed_command` | Command and arguments, run in the template directory after the services are up, with the slot's env |
| `deploy_user` | The user a developer logs in as. Reported back; the supervisor does not create it |
| `database` | Optional. How to reach the slot's database. `{host}`, `{slot}` and `{port_<name>}` are filled in |

All keys but `database` are required, and an unknown key is an error.
Only `slot.json` is read; there is no `slot.toml` in this version.

`compose.yaml` uses the slot's env to place itself, for example
`"${SLOT_UPSTREAM_HOST}:${SLOT_PORT_APP}:${SLOT_INTERNAL_PORT}"` for the app's
port. Paths in it are relative to the template directory, and
`SLOT_TEMPLATE_DIR` names it, so a dump is mounted and never copied. Every
start seeds, so seed from a prepared dump, not from a script that builds the
data from zero. An example is in [`examples/demo/`](examples/demo/).

A started slot's services must come up healthy: the supervisor starts them
with `docker compose up -d --wait` and seeds after that.

### Serving an app under a path

A slot is served at `/<slot>/`, and most apps expect to be at `/`. Each
template picks one of two ways:

- `strip_prefix: false`. The app is told its base path (`SLOT_BASE_PATH`,
  for example `/thankmu-1`) and serves everything under it.
- `strip_prefix: true`. The proxy removes the prefix and sends it in the
  `X-Forwarded-Prefix` header. The app sees `/`, but every link, redirect and
  asset URL it sends back must be relative or use the prefix, or the browser
  leaves the slot.

## Installing on a server

Needs Python 3.9 or newer, Docker with the compose plugin, and Caddy. Nothing
to `pip install`.

1. Copy this directory to `/opt/slot_supervisor` and link the command:
   `ln -s /opt/slot_supervisor/bin/slot /usr/local/bin/slot`.
2. Pick the user it runs as. In this version that is the same user developers
   deploy as (`deploy` in the unit files): it must be able to run docker and
   to write the work and routes directories.
3. Create the directories from the settings: templates, work, routes.
4. Copy [`systemd/env.example`](systemd/env.example) to
   `/etc/slot-supervisor/env` and fill it in. Write
   `/etc/slot-supervisor/tokens.json`, owned by that user, mode 600.
5. Point Caddy at the API and the routes. In the Caddyfile:

   ```
   slots.example.com {
   	handle /api/* {
   		reverse_proxy localhost:8700
   	}
   	import /etc/caddy/slots/*.caddy
   }
   ```

   The supervisor writes one `<slot>.caddy` file per running slot into the
   routes directory and runs `SLOTS_PROXY_RELOAD_COMMAND` after each change.
6. Install the units from [`systemd/`](systemd/) into `/etc/systemd/system/`:
   - `slot-supervisor.service` runs `slot serve` and restarts it if it dies.
   - `slot-reaper.timer` runs `slot-reaper.service` (`slot reap`) every five
     minutes.

   Then `systemctl daemon-reload` and
   `systemctl enable --now slot-supervisor.service slot-reaper.timer`.
7. Add a template per project, then try `slot request` on the server before
   giving out tokens.

The reaper and the CLI work without the HTTP service. That is the first step
of the build order: the timer and the `slot` command, then the API.

To use the CLI by hand, load the same settings first:
`set -a; . /etc/slot-supervisor/env; set +a`.

## How it is built

```
slots/supervisor.py      the six verbs; no side effects of its own
slots/runtime.py         the one interface every side effect goes through
slots/docker_runtime.py  the real one: docker compose, files, Caddy snippets
slots/fake_runtime.py    the in-memory one the tests use
slots/templates.py       reads slot.json
slots/config.py          settings and tokens
slots/cli.py             the slot command
slots/httpapi.py         the HTTP API
```

What the real runtime does for a start: makes `<work>/<slot>/`, writes the
slot's `.env` and a `compose.slot.json` that puts the `slots.*` labels on every
service, runs `docker compose up -d --wait`, runs the seed command, writes the
Caddy snippet and reloads Caddy. If any step fails, the slot is taken down
again and the call fails. A stop runs `docker compose down --volumes` by
project name, removes any volume still labelled with the project, deletes the
directory and the snippet, and reloads Caddy.

Starts and stops run one at a time on a server (a lock file in the work
directory), so two requests never get the same slot or port. A request waits
while another slot starts.

Tests use only the fake runtime, or the real one with its command runner
replaced. They never call docker.

```
python3 -m unittest discover -s slot_supervisor/tests
```

## Not yet proven

- **Only the example template has run on a real server** (Ubuntu 24.04, Docker
  29, Caddy 2.6). That first start found two things, both now in the example:
  `SLOTS_UPSTREAM_HOST` must be an IP address, because compose rejects
  `localhost` in a port mapping; and a Postgres health check must go over TCP,
  or the seed runs while the database is still restarting after its first
  start.
- **Serving an app under a path.** Neither way in "Serving an app under a
  path" has been tried with a real app. Each stack needs its own recipe.
- **Apps that pick a site by host name** (ThankMu's partner portal). Under one
  host and a path there is no second host name. Not handled: it needs a second
  path per slot or a host header set by the proxy.
- **Cookies are shared across paths on one host.** Two slots open in one
  browser can see each other's session cookie unless the app sets cookie names
  or paths per slot. Not handled.
- **Labels after a deploy.** See "How a developer uses a slot". Whether real
  deploy scripts keep at least one labelled container is untested.
- **Who owns the slot directory.** The supervisor and the developers are
  assumed to be one user. `deploy_user` is reported, not enforced.
- **Removing volumes by project name** when the developer deployed other
  compose files, and `import` of an empty routes directory in Caddy, are
  believed to work and are untested.
- **The database address** uses a port published on the server. Whether a
  developer reaches it directly or through an SSH tunnel depends on the
  firewall.
- **A request holds the lock while a slot starts.** Fine for a few starts a
  day; slow if many projects ask at once.

## Not built

- No way to extend a slot (`touch`). Fixed 8 hours, by decision.
- No client for the HTTP API; `curl` is enough for a launch script.
- No `slot.toml`, no hostname-per-slot routing, no metrics, no web page.
- The supervisor does not create users, SSH keys or DNS records.
