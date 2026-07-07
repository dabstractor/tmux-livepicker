# Research — P1.M2.T3.S1: Add Known Limitations section to README.md (Issue 6)

> Documentation-only fix (Mode A) for bugfix **Issue 6 (Minor)**.
> Source of truth: `plan/002_facc52335e68/bugfix/001_c7c6203f3e28/architecture/issue4_5_6_findings.md` §Issue 6.

## FINDING 1 — The README seam (exact, byte-level)

The `## How it works` section (README line 156) is a single paragraph whose LAST
content line is **line 165** (`at confirm. Cancelling leaves zero trace.`). The
contract's "ends at ~line 164" is off by one — line 164 is the wrapped predecessor
(`browse. The only session switch in the whole flow is the single \`switch-client\``);
the true last line is 165. **Anchor edits on CONTENT, not line numbers.**

`cat -A` of the seam (lines 164-167):

```
browse. The only session switch in the whole flow is the single `switch-client`$
at confirm. Cancelling leaves zero trace.$
$
## Compatibility$
```

So: line 165 = `at confirm. Cancelling leaves zero trace.`, line 166 = blank,
line 167 = `## Compatibility`. The new subsection is inserted between line 165's
content and line 167's heading (after the blank).

## FINDING 2 — No existing "Known Limitations" section (no duplication risk)

`grep -n 'Known [Ll]imitation' README.md` → no matches. The README has no such
section anywhere. This task ADDS one; there is nothing to merge or de-duplicate.

## FINDING 3 — Heading level `###` is consistent with the README's style

README top-level sections are `##` (Overview, Goals, ..., How it works, Compatibility,
Validation, Maintenance). `###` subsections already exist under `## Configuration`
(`### Appearance` line 121, `### Performance` line 125). The contract specifies
`### Known limitations` placed after the "How it works" paragraph — i.e. the last h3
subsection of `## How it works`, immediately before `## Compatibility`. This matches
the README's existing h2→h3 convention. Use `###` (NOT `##`).

## FINDING 4 — The snapshot workaround is accurate and already documented

README line 103 (the Configuration table) documents:
`| \`@livepicker-preview-mode\` | \`live\` | \`live\` (link-window, all panes), \`snapshot\` (capture-pane, active pane), or \`off\`. |`

Issue 6 findings confirm: snapshot mode uses `capture-pane` and **never links** the
window, so it cannot trigger the `window-size` resize. So the contract's recommended
workaround (`@livepicker-preview-mode snapshot`) is correct and the option already
exists. No new option/config is introduced — this is purely a doc note pointing at an
existing escape hatch.

## FINDING 5 — The exact edit (unique, ASCII-only anchor)

The anchor `at confirm. Cancelling leaves zero trace.\n\n## Compatibility` is UNIQUE
(the phrase "Cancelling leaves zero trace." appears once; `## Compatibility` is the
only such heading) and pure ASCII (the `§` symbol lives elsewhere, not in this seam).
So the edit is a single, safe `oldText`→`newText` replacement (verbatim in the PRP).

## FINDING 6 — Issue 6 root cause (for comment accuracy / future-proofing)

tmux's `window-size` (default `latest`/`auto`) resizes a linked window to the
largest/smallest attached client across ALL sessions that link it. A detached candidate
(80x24) linked into an attached driver (200x50) and selected resizes the SHARED window
object to 200x50. On unlink, the candidate has no attached client, so it does NOT
restore to 80x24 (it shrinks to the no-client default). The pane COUNT and window ID
are intact — only the dimensions/geometry change. This affects ONLY detached candidate
sessions (a candidate with its own attached client would size to that client). Saving/
restoring `window-size`+layout around each preview link is feasible but adds 2-3 tmux
round-trips per nav and changes visuals — explicitly OUT OF SCOPE for this bugfix cycle
(documented instead). The contract's wording matches this exactly.

## FINDING 7 — Disjoint from the parallel P1.M2.T2.S1 (Issue 5)

P1.M2.T2.S1 (in-flight) modifies `scripts/livepicker.sh` (`_lp_resolve_tab_templates`)
+ `scripts/renderer.sh` (window-status path) ONLY — its PRP states "no shared file, no
collision". **This task modifies `README.md` ONLY.** No file overlap. P1.M3.T1.S2
("Verify and update README.md feature/behavior sections") is a LATER, separate task —
this subtask adds only the Known Limitations subsection and must not pre-empt other
README edits. CHANGELOG sync is P1.M3.T1.S1 (also later, also out of scope here).

## FINDING 8 — Validation = content self-check (no test; doc-only)

The contract is Mode A (`MOCKING: No external services; README.md is a static
document`). No regression test is added (a doc-only note; the existing `tests/run.sh`
suite does not read README.md). Validation is a `grep`/`sed` self-check that (a) the new
`### Known limitations` heading + bullet are present between "How it works" and
"## Compatibility", (b) the `@livepicker-preview-mode snapshot` workaround is mentioned,
(c) "## Compatibility" still immediately follows, and (d) no other section was disturbed.
A full `tests/run.sh` run is optional (expected unchanged — README is not read by tests).
