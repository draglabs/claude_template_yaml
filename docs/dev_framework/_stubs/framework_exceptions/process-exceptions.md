# Process exceptions

Raw field reports from agents about friction with the SOP, briefs, tools, or mechanisms. Append-only log. The Strategist reviews this file at phase boundaries (and on demand) to decide which entries become SOP updates, which graduate to full `execution-incidents.md` post-mortems, and which are wontfix.

## Who files here

| Role | How |
|---|---|
| **Executor** | Appends directly to this file on the worktree branch during work. Flags the count in the return shape. |
| **Reviewer** | Can't write files (verdict-only). Flags in the return; the Orchestrator appends on its behalf. Under peer dispatch, the Executor does not see the Reviewer's output — the Reviewer reports to the Orchestrator, so only the Orchestrator can relay. |
| **QA** | Same as Reviewer — verdict-only, Orchestrator appends. |
| **Doc Consultant / Code Consultant** | Same — flag in return, spawning agent appends. |
| **Orchestrator** | Appends directly on `main` as part of normal Orchestrator workflow. Commits as a standalone plan-adjacent commit. Also relays Reviewer / QA exceptions (see above rows). |
| **Strategist** | Does NOT file. The Strategist is the REVIEWER of this file — if the Strategist sees friction, it opens a `planning:` PR directly rather than logging a complaint. |
| **Designer** | Can write here as a bounded exception to the `mockups/` write-scope rule. Mockup-surface friction is a legitimate category. |

## When to file

File when the friction is **plausibly preventable by a process change**:

- Brief had an ambiguous requirement, missing info, or contradictory constraints.
- SOP rule conflicted with what actually needed to happen.
- Tool / mechanism was insufficient (retry cap exhausted on a class of work it shouldn't have; isolation mechanism didn't match assumption; MCP returned unexpected shape).
- Sub-sub-agent interaction surprised you (Reviewer cited a concern the brief didn't warn about; QA target URL didn't resolve).
- A step took substantially more time than the effort estimate suggested, AND the cause was process-shaped, not code-shaped.

## When NOT to file

- Ordinary bugs in the product code — those are just work.
- One-off surprises that don't generalize.
- Feature requests for the product — belong in `issues/`, not here.
- Your own mistakes that aren't the SOP's fault.
- Disagreements with locked decisions — raise those through the Strategist as proposed ADRs, not as complaints.

## Format

Append new entries to the **Open** section below. Use this shape:

```markdown
### PE-NNN — YYYY-MM-DD — {{role}} on {{W-id or context}}

**Category:** brief-ambiguity | sop-mismatch | tool-friction | retry-exhaustion | subagent-surprise | other
**Severity:** low (minor noise) | medium (cost one retry / partial work) | high (cost the whole W-item / forced bypass)
**Description:** 2-4 sentences. What happened, what you expected, what you did about it.
**Suggested fix:** Optional but valuable. What SOP / brief / tool change would have prevented this? One sentence.
```

Numbering is sequential across all entries (open + resolved). The Strategist assigns the PE-NNN when triaging if the filer left a placeholder.

**Parallel filing note.** The SOP allows up to ~3 concurrent Executors, each on its own worktree branch. If two Executors file PE-TBD entries during the same phase, both arrive in the Open section after merge with no stable ordering guarantee from git (both are append-only on different branches before merge). When the Strategist assigns PE-NNN at triage, it orders by the **filing timestamp on the entry itself**, not by file position. Always include a precise date on every entry so ordering is unambiguous.

## Triage protocol (Strategist)

At each phase boundary, before running the exit-gate QA:

1. Read every entry in the Open section.
2. Cluster by category. Two entries of the same category are a signal; three are a forcing function.
3. For each entry, decide one disposition:
   - **→ SOP update.** Open a `planning:` PR that amends the relevant doc (session-policy, a brief, this doc's own when-to-file rules). Reference the PE-id.
   - **→ Full incident.** Promote to `execution-incidents.md` with root cause, impact, fix. Use when the entry describes a real process violation (not just friction).
   - **→ Clarification needed.** Reply inline in the entry (under "Strategist response"). Move the entry to Resolved once the filer confirms or the next phase starts.
   - **→ Wontfix.** The friction is structural and the alternative is worse. Move to Resolved with explanation.
4. Move the entry to Resolved with a dated disposition line.

Never delete an entry. The history is the value — it shows where the process has been, what was decided, and why.

---

## Open

(None yet.)

---

## Resolved

(None yet.)
