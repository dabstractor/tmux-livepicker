# PRP — Bugfix P1.M2.T3.S1: Add a "Known limitations" subsection to README.md (Issue 6)

> **Bug context**: Issue 6 (Minor, documentation) from the rev-002 QA pass
> (`plan/002_facc52335e68/bugfix/001_c7c6203f3e28/architecture/issue4_5_6_findings.md`
> §Issue 6). When a **detached** candidate session's window is linked into the attached
> driver for live preview, tmux's `window-size` (default `auto`/`latest`) resizes the
> shared window object to the driver's dimensions while it is linked+active; on unlink
> the candidate (which has no attached client of its own) does **not** restore its
> original size. The pane count and window id are intact — only the geometry changes —
> and only detached candidates are affected. This is inherent to tmux `link-window` and
> is out of scope to fix (saving/restoring layout around each preview link would add
> 2–3 tmux round-trips per nav and change visuals). The fix is **documentation**: add a
> "Known limitations" subsection to README.md noting the behavior and the existing
> `@livepicker-preview-mode snapshot` workaround (snapshot uses `capture-pane` and never
> links, so it cannot resize). No code, no test, no config.

---

## Goal

**Feature Goal**: The README documents the detached-candidate resize limitation and
points users at the existing snapshot-mode workaround, so the behavior is not a silent
surprise. The new `### Known limitations` subsection sits at the end of the `## How it
works` section, immediately before `## Compatibility`.

**Deliverable**: A single surgical insert to `README.md` — one `### Known limitations`
heading + one bullet — placed between the last line of "How it works"
(`at confirm. Cancelling leaves zero trace.`) and the `## Compatibility` heading. No
other file is touched; no code, no test, no config, no CHANGELOG (that is P1.M3.T1.S1).

**Success Definition**:
- `grep -n '^### Known limitations' README.md` returns exactly one match, located
  between the "How it works" paragraph and `## Compatibility`.
- The bullet documents (a) detached candidate windows are resized during live preview,
  (b) the resize is inherent to tmux `window-size`, (c) it affects only detached
  candidates, and (d) the `@livepicker-preview-mode snapshot` workaround.
- `## Compatibility` still immediately follows the new subsection (no section reordered
  or removed); the rest of README.md is byte-for-byte unchanged.

## User Persona (if applicable)

**Target User**: Any user who previews a **detached** candidate session (e.g. a
background dev session) in `live` preview mode and later returns to it, finding its
window geometry changed.

**Use Case**: The user opens the picker, browses a detached session, cancels/confirms,
and later switches to that session — noticing its panes are no longer at their original
size. The Known Limitations note explains why and offers the snapshot workaround.

**Pain Points Addressed**: Today the resize is undocumented and looks like a bug.
Documenting it sets correct expectations and gives the user a one-line workaround
(`@livepicker-preview-mode snapshot`) that already exists.

## Why

- **Issue 6 is explicitly "document as known limitation"** in the findings (the code fix
  is out of scope for this bugfix cycle — 2–3 extra tmux round-trips per nav + visual
  change). This task is the documentation half of that resolution.
- **The workaround already exists.** `@livepicker-preview-mode snapshot` (README config
  table, line 103) uses `capture-pane` and never links the window, so it cannot trigger
  the resize. The note simply surfaces it where a surprised user would look.
- **Cheap, surgical, zero-risk.** One prose insert to one Markdown file; no logic, no
  config, no state, no scripts, no tests. Confined to the How-it-works/Compatibility seam.
- **Disjoint from parallel work.** P1.M2.T2.S1 (Issue 5, in-flight) edits
  `scripts/livepicker.sh` + `scripts/renderer.sh` ONLY. P1.M2.T1.S1 (Issue 4) edits
  `scripts/preview.sh` ONLY. This task edits `README.md` ONLY — no file collision. The
  cross-cutting CHANGELOG + broader README verification are later tasks (P1.M3.T1.S1 /
  P1.M3.T1.S2) and are out of scope here.

## What

A single insert to `README.md`: a `### Known limitations` subsection (h3, matching the
README's existing h2→h3 convention — see `### Appearance` / `### Performance` under
`## Configuration`) appended to the end of the `## How it works` section, immediately
before `## Compatibility`. The subsection contains one bullet stating the detached-
candidate resize behavior + the `@livepicker-preview-mode snapshot` workaround, using
the exact wording from the work-item contract.

### Success Criteria

- [ ] `grep -c '^### Known limitations' README.md` → `1`.
- [ ] The subsection sits AFTER `at confirm. Cancelling leaves zero trace.` and BEFORE
      `## Compatibility`.
- [ ] The bullet mentions `@livepicker-preview-mode snapshot` and `capture-pane`.
- [ ] `## Compatibility` still immediately follows (no reorder); nothing else changed.
- [ ] No other file modified; no CHANGELOG entry added (that is P1.M3.T1.S1's job).

## All Needed Context

### Context Completeness Check

_Pass_: an implementer who has never seen this repo can do it from (a) the exact unique
`oldText`→`newText` block (ASCII-only, content-anchored), (b) the `###` heading-level
rule, and (c) the grep self-checks. No tmux / shell / plugin knowledge required — it is
a prose insert. All anchors verified against the live file
(research/readme_known_limitations_findings.md, FINDINGS 1–8).

### Documentation & References

```yaml
# MUST READ — the bug report (root cause + the "document as known limitation" directive)
- docfile: plan/002_facc52335e68/bugfix/001_c7c6203f3e28/architecture/issue4_5_6_findings.md
  why: §Issue 6 states the mechanism (tmux window-size resizes the shared linked window
       to the attached driver's size; on unlink the detached candidate does not restore),
       confirms it affects only detached candidates (pane count/id intact; geometry
       changes), rules out the save/restore-layout fix (out of scope: 2-3 round-trips +
       visual change), and directs: document in README + mention the snapshot workaround.
  critical: the option name is @livepicker-preview-mode with value snapshot (NOT
            @livepicker-preview-defer — that is a different, unrelated option). snapshot
            uses capture-pane and never links, so it cannot resize.

# MUST READ — the empirical ground-truth for THIS task (8 verified findings)
- docfile: plan/002_facc52335e68/bugfix/001_c7c6203f3e28/P1M2T3S1/research/readme_known_limitations_findings.md
  why: FINDING 1 (exact seam — last "How it works" line is 165, NOT 164 as the contract
       implies; anchor on "Cancelling leaves zero trace."); FINDING 2 (no existing Known
       Limitations section -> no dup); FINDING 3 (### heading is consistent — do NOT use
       ##); FINDING 4 (snapshot workaround is accurate + already documented at line 103);
       FINDING 5 (the unique ASCII-only anchor); FINDING 6 (root cause for comment
       accuracy); FINDING 7 (disjoint from parallel P1.M2.T2.S1); FINDING 8 (validation =
       grep self-check, no test).

# MUST READ — the file being edited (the seam + the existing option doc)
- file: README.md
  why: ## How it works (line 156) ends at line 165 "at confirm. Cancelling leaves zero
        trace."; blank line 166; ## Compatibility (line 167). The new ### Known limitations
        subsection is inserted between line 165's content and line 167's heading.
  pattern: the README already uses ### subsections under ## sections (### Appearance /
           ### Performance under ## Configuration), so ### Known limitations under
           ## How it works matches the file's convention.
  gotcha: anchor the edit on the CONTENT "at confirm. Cancelling leaves zero trace." +
          the following "## Compatibility" heading (both unique). Do NOT edit by line
          number — the contract's "~line 164/166" is off by one (actual last content
          line is 165). Do NOT change the "## Compatibility" heading or any other section.

# Reference — the existing option the workaround points at (so the doc is accurate)
- file: README.md
  why: line 103 config-table row documents `@livepicker-preview-mode` with values
        `live` / `snapshot` / `off` ("snapshot (capture-pane, active pane)"). The Known
        Limitations bullet points users at `snapshot` — this confirms the option + value
        names the bullet must use.
  section: "## Configuration" → the options table, @livepicker-preview-mode row
```

### Current Codebase tree

```bash
tmux-livepicker/
  README.md           # MODIFY: +### Known limitations subsection at end of ## How it works (before ## Compatibility)
  CHANGELOG.md        # UNCHANGED (the Issue 6 "Documented:" entry is added later by P1.M3.T1.S1)
  scripts/            # UNCHANGED (P1.M2.T1.S1 preview.sh + P1.M2.T2.S1 livepicker.sh/renderer.sh — disjoint)
  PRD.md, plugin.tmux, tests/   # UNCHANGED
```

### Desired Codebase tree with files to be added and responsibility of file

```bash
README.md   # +### Known limitations: documents the detached-candidate resize + the @livepicker-preview-mode snapshot workaround
# (no files added; documentation-only change)
```

### Known Gotchas of our codebase & Library Quirks

```bash
# CRITICAL (research FINDING 1): the contract's "ends at ~line 164" is OFF BY ONE. The
# last "How it works" content line is 165 ("at confirm. Cancelling leaves zero trace.");
# line 164 is the wrapped predecessor. Anchor the edit on CONTENT, not line numbers.

# CRITICAL: use heading level `###` (h3), NOT `##`. The contract specifies "### Known
# limitations" as a SUBSECTION at the end of ## How it works. `##` would make it a peer
# top-level section and mis-place it in the document outline. The README already uses
# ### subsections (### Appearance / ### Performance under ## Configuration).

# CRITICAL: the workaround option is `@livepicker-preview-mode snapshot` — NOT
# `@livepicker-preview-defer`. preview-defer is a DIFFERENT option (the §18 toggle). The
# resize is governed by preview-MODE (live links the window; snapshot does not). Use the
# exact option/value names from the contract + README line 103.

# GOTCHA (research FINDING 5): the anchor "at confirm. Cancelling leaves zero trace." +
# "## Compatibility" is UNIQUE and ASCII-only (the § symbol lives elsewhere, not in this
# seam). Do not include any non-ASCII bytes in oldText.

# GOTCHA (research FINDING 2): there is NO existing "Known Limitations" section — this
# is a pure insert, no merge/de-dup needed.

# GOTCHA: do NOT reorder sections. "## Compatibility" must IMMEDIATELY follow the new
# subsection (it is the next top-level section). Keep exactly one blank line between the
# new bullet and "## Compatibility", and one blank line between "Cancelling leaves zero
# trace." and the "### Known limitations" heading (Markdown paragraph separation).

# GOTCHA (research FINDING 7): CHANGELOG sync is P1.M3.T1.S1; broader README verification
# is P1.M3.T1.S2. This task adds ONLY the Known Limitations subsection — do not edit other
# README sections or the CHANGELOG here.

# GOTCHA (research FINDING 8): no regression test is added (doc-only; tests/run.sh does
# not read README.md). Validation is the grep self-check.
```

## Implementation Blueprint

### Data models and structure

None. No data, no schema, no state. This is a prose insert of one heading + one bullet.

### Implementation Tasks (ordered by dependencies)

```yaml
Task 1: MODIFY README.md — insert the ### Known limitations subsection
  - LOCATE the seam: the last line of ## How it works ("at confirm. Cancelling leaves
    zero trace.") followed by a blank line followed by "## Compatibility". (Content
    anchor — the contract's "~line 164/166" is off by one; actual last content line is
    165, Compatibility is 167.)
  - ACTION: a single oldText->newText replacement (verbatim in "Implementation Patterns"
    below) that inserts, between "Cancelling leaves zero trace." and "## Compatibility":
      * a blank line,
      * the "### Known limitations" heading,
      * a blank line,
      * the one bullet (detached-candidate resize + @livepicker-preview-mode snapshot
        workaround), using the EXACT contract wording,
      * a blank line,
    then "## Compatibility" follows unchanged.
  - HEADING LEVEL: ### (h3 subsection of ## How it works) — NOT ##.
  - PRESERVE: the "## Compatibility" heading and every other section byte-for-byte.
  - DO NOT: edit any other file; add a CHANGELOG entry; change any option name; touch
    scripts/ or tests/.

Task 2: VALIDATE (content self-check)
  - RUN (Level 1): grep -c '^### Known limitations' README.md            # -> 1
  - RUN (Level 1): confirm placement between "Cancelling leaves zero trace." and
    "## Compatibility" (sed -n '/## How it works/,/## Maintenance/p' README.md).
  - RUN (Level 1): grep -c '@livepicker-preview-mode snapshot' README.md # -> >=1 (the
    new bullet; the config table uses a different phrasing so this is the bullet's mark)
  - RUN (Level 1): grep -c '^## Compatibility' README.md                 # -> 1 (unchanged)
  - OPTIONAL (Level 2): tests/run.sh  # expected unchanged (README not read by tests).
```

### Implementation Patterns & Key Details

**Task 1 — the insert (paste verbatim into the edit tool).** The anchor is unique
(the phrase "Cancelling leaves zero trace." appears once; `## Compatibility` is the only
such heading) and ASCII-only.

CURRENT (the exact text to match — the last "How it works" line + blank + the next
heading):

```markdown
at confirm. Cancelling leaves zero trace.

## Compatibility
```

→ REPLACE WITH (the same lines, with the new subsection inserted between them):

```markdown
at confirm. Cancelling leaves zero trace.

### Known limitations

- **Detached candidate windows are resized during preview.** When a detached
  candidate window is linked into the attached driver session for live
  preview, tmux resizes the shared window object to the driver's dimensions.
  After the picker exits, the candidate's window retains the driver's size
  rather than its original dimensions. This is inherent to tmux's
  `window-size` behavior and affects only detached candidate sessions. To
  avoid this, set `@livepicker-preview-mode snapshot` (uses `capture-pane`
  and never links the window).

## Compatibility
```

What this does:
- Keeps `at confirm. Cancelling leaves zero trace.` (the end of "How it works") intact.
- Inserts a blank line, the `### Known limitations` heading, a blank line, the bullet,
  and a blank line.
- Leaves `## Compatibility` (and everything below) byte-for-byte unchanged.

The bullet wording is the **exact** text from the work-item contract (§3 LOGIC) — do not
paraphrase. It states: (a) detached candidate windows are resized during live preview;
(b) tmux resizes the shared window object to the driver's dimensions; (c) after exit the
candidate retains the driver's size; (d) inherent to tmux `window-size`, affects only
detached candidates; (e) workaround `@livepicker-preview-mode snapshot` (capture-pane,
never links).

**Verification after the edit (copy-paste):**

```bash
cd /home/dustin/.config/tmux/plugins/tmux-livepicker
grep -c '^### Known limitations' README.md                 # -> 1
grep -c '^## Compatibility' README.md                      # -> 1  (unchanged, still present)
# Placement proof: "Known limitations" must appear AFTER "Cancelling leaves zero trace."
# and BEFORE "## Compatibility":
awk '/Cancelling leaves zero trace/{a=NR} /### Known limitations/{b=NR} /^## Compatibility/{c=NR}
     END{ if(a&&b&&c&&a<b&&b<c) print "OK: Known limitations placed correctly"; else print "FAIL: placement" }' README.md
# The workaround + mechanism are mentioned:
grep -c '@livepicker-preview-mode snapshot' README.md      # -> >=1
grep -c 'capture-pane' README.md                           # -> >=2 (config table + the new bullet)
# Re-read the How-it-works -> Compatibility region to eyeball:
sed -n '/## How it works/,/## Compatibility/p' README.md
```

### Integration Points

```yaml
CODE:
  - file: README.md
    change: "+### Known limitations subsection (1 heading + 1 bullet) at the end of
             ## How it works, immediately before ## Compatibility"
    invariant: "the detached-candidate resize is documented; the @livepicker-preview-mode
               snapshot workaround is surfaced; ## Compatibility still immediately follows;
               no other section changed"

TESTS: none added (doc-only; contract MOCKING: N/A — README is a static document).
DATABASE / CONFIG / ROUTES: none.
```

## Validation Loop

### Level 1: Content self-check (primary gate — doc-only)

```bash
cd /home/dustin/.config/tmux/plugins/tmux-livepicker
# 1) The new subsection exists exactly once:
grep -c '^### Known limitations' README.md                 # -> 1
# 2) Placement: AFTER "Cancelling leaves zero trace." and BEFORE "## Compatibility":
awk '/Cancelling leaves zero trace/{a=NR} /### Known limitations/{b=NR} /^## Compatibility/{c=NR}
     END{ if(a&&b&&c&&a<b&&b<c) print "OK: placement"; else print "FAIL: placement" }' README.md
# 3) The workaround + mechanism are mentioned:
grep -c '@livepicker-preview-mode snapshot' README.md      # -> >=1
grep -c '\`window-size\`' README.md                        # -> >=1 (the bullet's "tmux's `window-size`")
# 4) No section was removed/reordered — Compatibility still exactly one, immediately after:
grep -c '^## Compatibility' README.md                      # -> 1
# 5) The bullet is the LAST thing before Compatibility (no stray blank-line splits):
sed -n '/### Known limitations/,/^## Compatibility/p' README.md
# Expected: 1 Known limitations; correct placement; snapshot + window-size mentioned;
#           Compatibility intact; the region reads as one heading + one bullet + the
#           Compatibility heading.
```

### Level 2: No-breakage suite run (optional — belt-and-braces)

```bash
cd /home/dustin/.config/tmux/plugins/tmux-livepicker
tests/run.sh
# Expected: exit 0, full suite green. README is NOT read by the tests, so this is purely a
# "nothing else regressed" sanity check (e.g. no accidental edit of a sourced file). The
# full suite takes ~2-3 min; safe to skip for a pure-prose README insert if Level 1 passes.
```

### Level 3: Rendered-Markdown sanity (manual, 30 sec)

```bash
# Eyeball the How-it-works -> Compatibility region in any Markdown renderer (or just read
# the source). Confirm:
#   - "### Known limitations" renders as a subsection of "## How it works" (NOT a peer of
#     the ## sections);
#   - the bullet renders as one list item with the bold lead "**Detached candidate
#     windows are resized during preview.**";
#   - "## Compatibility" is the next top-level section, unchanged;
#   - the inline code spans `@livepicker-preview-mode snapshot`, `capture-pane`, and
#     `window-size` render as code.
# No performance / security / load validation applies (prose edit).
```

## Final Validation Checklist

### Technical Validation

- [ ] `grep -c '^### Known limitations' README.md` → `1`.
- [ ] Placement proof (Level 1 awk): `a < b < c` (Cancelling… < Known limitations < Compatibility).
- [ ] `grep -c '^## Compatibility' README.md` → `1` (heading intact, immediately follows).
- [ ] `@livepicker-preview-mode snapshot` and `window-size` mentioned in the bullet.
- [ ] (Optional) `tests/run.sh` exits 0 (no regression — README not read by tests).

### Feature Validation

- [ ] The detached-candidate resize behavior is documented.
- [ ] The `@livepicker-preview-mode snapshot` workaround is surfaced (and is accurate —
      the option/value already exist in the config table, README line 103).
- [ ] The note states it affects only detached candidate sessions + is inherent to tmux.
- [ ] "## Compatibility" still immediately follows the new subsection.

### Code Quality Validation

- [ ] Change confined to the single How-it-works/Compatibility seam in README.md.
- [ ] Heading level is `###` (matches the README's h2→h3 convention); NOT `##`.
- [ ] Bullet wording matches the work-item contract verbatim (no paraphrasing).
- [ ] Exactly one blank line separates each Markdown block (paragraph/heading/list).
- [ ] No other file modified; no CHANGELOG entry (P1.M3.T1.S1); no scripts/tests touched.

### Documentation & Deployment

- [ ] The README now sets correct expectations for detached-candidate preview resizing.
- [ ] No new option/config/API surface (the note points at an existing option).

---

## Anti-Patterns to Avoid

- ❌ Don't use `##` for the heading — the contract specifies `### Known limitations` (an
  h3 subsection at the end of `## How it works`). `##` would make it a peer top-level
  section and break the document outline.
- ❌ Don't edit by line number — the contract's "~line 164/166" is off by one (the last
  "How it works" content line is 165; Compatibility is 167). Anchor on the content
  "at confirm. Cancelling leaves zero trace." + "## Compatibility".
- ❌ Don't point the workaround at the wrong option — it is `@livepicker-preview-mode
  snapshot` (preview-MODE governs linking). `@livepicker-preview-defer` is a DIFFERENT
  option (the §18 deferred-preview toggle) and has no effect on the resize.
- ❌ Don't paraphrase the bullet — use the exact contract wording (it precisely states the
  mechanism, the scope "only detached candidate sessions", and the workaround).
- ❌ Don't reorder or remove sections — "## Compatibility" must IMMEDIATELY follow the new
  subsection. Keep one blank line between each block.
- ❌ Don't add a CHANGELOG entry or edit other README sections here — the cross-cutting doc
  sync is P1.M3.T1.S1 (CHANGELOG) / P1.M3.T1.S2 (README verification). This task adds only
  the Known Limitations subsection.
- ❌ Don't add a regression test — doc-only (contract MOCKING: N/A); tests/run.sh does not
  read README.md. Validation is the grep self-check.
- ❌ Don't include non-ASCII bytes (e.g. `§`) in the edit's `oldText` — the seam is pure
  ASCII; anchor on "Cancelling leaves zero trace." to stay ASCII-safe.

---

## Confidence Score

**10 / 10** for one-pass success. Rationale: this is a single, surgical prose insert to
one Markdown file. Every fact is **live-verified**: the exact seam (last "How it works"
line is 165, not the contract's implied 164 — anchored on content); no existing Known
Limitations section (pure insert); the `###` heading level matches the README convention;
the `@livepicker-preview-mode snapshot` workaround is accurate and already documented
(README line 103); the anchor is unique and ASCII-only. The grep/awk self-checks
deterministically prove correctness (presence, placement, intact Compatibility), and the
task is fully disjoint from both in-flight parallel tasks (P1.M2.T1.S1 preview.sh,
P1.M2.T2.S1 livepicker.sh/renderer.sh) and from the later CHANGELOG/README-sync tasks
(P1.M3). Residual risk: an edit-tool `oldText` mismatch — mitigated by the verbatim
old→new pair above and the Level 1 grep/awk post-checks. There is no logic, no test, and
no integration surface to get wrong.
