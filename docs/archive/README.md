# Archive

Closed execution plans, superseded ADRs, and historical docs. Not loaded at session start — read on demand for historical reference only.

When archiving a plan:
1. Add `## Status: CLOSED` header.
2. Move to this directory.
3. Remove from CLAUDE.md's reading order.
4. Add a one-line summary below.

## Superseded ADRs

A superseded ADR **moves here**; it does not stay in `docs/architecture/`. Leaving it there is a permanent context tax — every future session greps, loads, and reads past a decision that is no longer true, and the corpus can only grow. See [`curator.md`](../dev_framework/curator.md) §"Dispositions" and [ADR-026](../architecture/adr-026-curator-role.md).

When archiving an ADR:
1. Set `**Status:** superseded by ADR-NNN` (or `deprecated`) on the ADR itself.
2. `mv docs/architecture/adr-NNN-<slug>.md docs/archive/`
3. Fix inbound references — anything citing it should point at the successor. A link that now resolves into `docs/archive/` is a signal the citing doc needs updating, not that the move was wrong.
4. Remove its line from CLAUDE.md §"Locked-in decisions" if present.
5. Add a one-line entry below.
6. **Same commit as the successor ADR.** A supersession split across two commits leaves a window where both are live in `docs/architecture/`.

**Archive, don't delete.** The file is cheap here and unreadable-by-default; the history stays recoverable without any session paying for it. Deletion is only for content git already holds and nobody will ever want.

**Not every stale ADR gets archived.** Where the decision still stands and only its wording or binding force was wrong, rewrite or detune it in place — archiving is for decisions that genuinely changed.

## Archived plans

(none yet)

## Archived ADRs

(none yet)
