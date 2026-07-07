# PRP — P1.M3.T3.S1: Sync changeset-level documentation (README.md + CHANGELOG.md) for §17 + §18

> **Scope**: Documentation-ONLY. Edits exactly TWO files: `README.md` (add two
> config-table rows + two short notes) and `CHANGELOG.md` (add one new section).
> No production code, no tests, no PRD.md, no tasks.json. This is the Mode-B docs
> task; it runs last and summarizes the complete plan-002 changeset. Both
> features are fully implemented (§17 by P1.M1.T1–T3, §18 by P1.M2.T1–T3) and
> validated (§15.23 by P1.M3.T1.S1, §15.24 by P1.M3.T2.S1). The job is to make
> the two new options discoverable and configurable from the README alone, and to
> record them in the CHANGELOG with the invariants they preserve.

---

## Goal

**Feature Goal**: A reader who has never seen this repo can discover both new
options (`@livepicker-tab-style`, `@livepicker-preview-defer`), learn their
defaults, their effect, and their escape hatches, from the README alone; and a
maintainer reading the CHANGELOG sees a scoped entry for the two features that
states their defaults, the invariants they preserve, and the legacy paths that
remain.

**Deliverable**: Two edited markdown files.
1. `README.md`: two new rows in the Configuration table (in PRD §11 order), plus
   two short subsections (`### Appearance`, `### Performance`) under
   `## Configuration`.
2. `CHANGELOG.md`: one new `[Unreleased]` section (placed above the existing one)
   with an `### Added` list covering both options, the invariants, and the legacy
   paths.

**Success Definition**:
- The Configuration table contains both rows in the correct positions
  (`preview-defer` after `preview-mode`, before `suppress-window-hook`;
  `tab-style` after `suppress-window-hook`, before `fg`), matching PRD §11 order.
- `### Appearance` explains `@livepicker-tab-style window-status` (reuse the
  theme's window-status formats) with the `plain` default and the fallback.
- `### Performance` explains the deferred preview default, the synchronous status
  redraw, and the `off` escape hatch.
- The CHANGELOG entry states: defaults (preview-defer `on` / tab-style `plain`),
  the pollution invariant (no `client-session-changed` while browsing), the
  restore invariant (`clear_all_state` still tears down everything, incl. the new
  state keys), and the legacy paths that remain (`plain` default, `preview-defer
  off` synchronous).
- The new prose passes the write-tech-docs style rules: zero em dashes, zero
  tell-words, no prose paragraph over ~100 words. (The pre-existing em dashes in
  both files are out of scope and are left as-is.)
- `PRD.md` is untouched.

## User Persona

**Target User**: Two readers.
- The end user / tmux user reading the README to discover and configure the two
  new capabilities (match their theme's tabs; keep typing snappy).
- The maintainer / future contributor reading the CHANGELOG to understand what
  plan-002 added and which invariants it must not break.

**Use Case**: A tubular/catppuccin user wants the picker to look like their own
window tabs; they scan the Configuration table, find `@livepicker-tab-style`, set
it to `window-status`, and read the Appearance note to confirm the fallback. A
user who sees typing lag on a slow box reads the Performance note and learns
`@livepicker-preview-defer off` is the synchronous diagnostic path.

**Pain Points Addressed**: Before this task, neither option appears in the README
or CHANGELOG, so a user cannot discover or configure them without reading the PRD
or the source. The CHANGELOG does not record that plan-002 preserved the
pollution/restore invariants.

## Why

- **Discoverability.** The README is the only user-facing entry point. PRD §11
  lists both options; the README table must mirror it or the options are
  invisible.
- **Correct mental model.** The two features have an asymmetric default
  (`preview-defer` default-on, `tab-style` default-off) and an escape hatch each.
  Short notes prevent a user from mis-configuring (e.g. expecting tabs to match
  by default) or mis-diagnosing lag.
- **CHANGELOG honesty.** The plan-002 changeset touches the render path and the
  input/preview path, both of which are invariant-sensitive. The CHANGELOG must
  state plainly that browsing still fires no `client-session-changed` and that
  teardown is still complete, so a maintainer does not fear a regression.
- **Right-sized.** This is a doc sync, not a restyle. Only the two new options'
  rows/notes/entry are added; no existing prose is rewritten (the pre-existing
  em dashes are left untouched, out of scope).

## What

### README.md

1. **Configuration table**: add two rows in PRD §11 order.
   - `@livepicker-preview-defer` (default `on`) between `@livepicker-preview-mode`
     and `@livepicker-suppress-window-hook`.
   - `@livepicker-tab-style` (default `plain`) between
     `@livepicker-suppress-window-hook` and `@livepicker-fg`.
2. **Two subsections** under `## Configuration`, placed after the
   "Set any option before the plugin loads" code block and before `## Usage`:
   - `### Appearance`: the picker can match the window-status theme via
     `@livepicker-tab-style window-status`; `plain` is the default; on resolution
     failure it falls back to `plain`.
   - `### Performance`: the live preview is deferred by default so the status
     tracks every keystroke; `@livepicker-preview-defer off` restores the
     synchronous path.

### CHANGELOG.md

A new section placed directly above the existing
`## [Unreleased] — Initial implementation`, with an `### Added` list covering:
- `@livepicker-tab-style` (default `plain`, §17): theme-matched tabs via the
  sentinel-resolved window-status formats, with a plain fallback.
- `@livepicker-preview-defer` (default `on`, §18): deferred, supersedeable
  background preview; synchronous status redraw; confirm never blocks; `off`
  restores the legacy path.
- The invariant statement: no `client-session-changed` while browsing;
  `clear_all_state` still tears down everything (incl. the new state keys).
- The legacy-paths statement: `plain` tab style is the default; `preview-defer
  off` is the synchronous escape hatch.

### Success Criteria

- [ ] README Configuration table has 21 rows (was 19), with `@livepicker-preview-defer`
      immediately after `@livepicker-preview-mode` and `@livepicker-tab-style`
      immediately after `@livepicker-suppress-window-hook`.
- [ ] README has `### Appearance` and `### Performance` subsections under
      `## Configuration`, before `## Usage`.
- [ ] CHANGELOG has a new `[Unreleased]` section above the existing one, with an
      `### Added` list naming both options and stating defaults, invariants, and
      legacy paths.
- [ ] New prose contains zero em dashes and zero write-tech-docs tell-words.
- [ ] No prose paragraph over ~100 words.
- [ ] `PRD.md` byte-identical to before (untouched).

## All Needed Context

### Context Completeness Check

_Pass_. An implementer who has never seen this repo can do it from: (a) the
verbatim old/new edit blocks below (anchored on unique content), (b) the exact
pre-padded table rows, (c) the default asymmetry and the four invariants
(research §3/§4), and (d) the write-tech-docs em-dash trap (research §5). No
inference about tmux internals is required; every claim is cross-checked against
PRD §17/§18, system_context.md §2, and the implementing PRPs.

### Documentation & References

```yaml
# MUST READ — the load-bearing decisions for THIS task (placement, padding,
# defaults, invariants, the em-dash/linter trap)
- docfile: plan/002_facc52335e68/P1M3T3S1/research/docs_sync_findings.md
  why: §2 (exact table column widths + the single-edit insertion trick);
       §3 (the default asymmetry: tab-style=plain, preview-defer=on); §4 (the four
       invariants to state); §5 (THE em-dash trap: existing files already have
       em dashes, so whole-file lint is NOT 0 and must NOT be the gate; validate
       the NEW prose only; header separator uses a colon, not an em dash);
       §6 (forbidden edits); §7 (README notes placement + anchor).
  critical: §5 is load-bearing. Running the linter and demanding exit 0 would
            force rewriting ~30 pre-existing em dashes, which is out of scope and
            would touch unrelated prose. The gate is "new prose is clean", verified
            by checking the added line numbers only.

# MUST READ — the authoritative defaults (overrides any scout speculation)
- docfile: plan/002_facc52335e68/architecture/system_context.md
  why: §2 pins the PRD §11 defaults: `@livepicker-tab-style` = `plain`,
       `@livepicker-preview-defer` = `on`. §1 summarizes both features. The
       CHANGELOG entry MUST use these exact defaults.
  section: "## 1.", "## 2."

# MUST READ — the feature specs (the source of truth for behavior claims)
- docfile: PRD.md
  why: §17 (tab appearance: sentinel resolution, placeholder swap, separator join,
       plain fallback, the Control subsection); §18 (responsiveness: typing is
       status-only + synchronous, nav sync-highlights + defers preview, preview is
       deferred + supersedeable, confirm never blocks, the Control subsection);
       §11 (the authoritative option table, incl. row order and the exact default
       + purpose wording to mirror); §4/§14 (the pollution invariant: only
       switch-client fires client-session-changed).
  section: "§17 Tab appearance", "§18 Responsiveness", "§11 Configuration options",
           "§4 The core rule", "§14 Pollution and compatibility"
  note: PRD.md is READ-ONLY. Read it for facts; do NOT edit it.

# MUST READ — the style rules this task MUST follow (em-dash ban, tell-words, linter)
- file: /home/dustin/.pi/agent/skills/write-tech-docs/SKILL.md
  why: the hard rules (no em dashes; no marketing tell-words; no hedging; do not
       narrate the codebase; run the linter). The reference tell-word list. The
       concision rules (state the fact, stop; no >100-word prose paragraph).
  critical: the linter strips code blocks + inline code first, so tmux primitives
            and option names in backticks are never flagged; but PLAIN words
            (e.g. "synchronously", "background", "supersedeable") ARE checked. Keep
            primitives/names in backticks; keep plain prose tell-word-free.

# MUST READ — the linter itself (run it on the edited files)
- file: /home/dustin/.pi/agent/skills/write-tech-docs/scripts/lint.sh
  why: exits 1 on em dashes (U+2014) / " -- ", banned tell-words (whole word), or a
       prose paragraph > 100 words. Strips fenced code + inline code first. Prints
       the offending line numbers, so you can confirm every hit is PRE-EXISTING
       (not in your added rows/notes/section).

# MUST READ — the implementing PRPs (the exact behavior to document; treat as contracts)
- docfile: plan/002_facc52335e68/P1M1.T3.S1/PRP.md
  why: the renderer window-status block: entered when opt_tab_style==window-status
       AND both cache templates non-empty; swaps __lp_tab__ -> the #-escaped session
       name; joins with window-status-separator; else the unchanged plain path. This
       is what the Appearance note + the tab-style row describe.
- docfile: plan/002_facc52335e68/P1M2.T3.S1/PRP.md
  why: the defer producer: _lp_preview_follow refreshes the status synchronously
       then fires a background run-shell -b preview (seq-tagged, supersedeable) when
       defer=on; defer=off is the legacy sync-preview-then-refresh path. Confirm is
       untouched (already independent of the preview). This is what the Performance
       note + the preview-defer row describe.
- docfile: plan/002_facc52335e68/P1M1.T1.S1/PRP.md   # STATE_TAB_* in _STATE_RUNTIME_KEYS
- docfile: plan/002_facc52335e68/P1M2.T1.S1/PRP.md   # STATE_PREVIEW_* in _STATE_RUNTIME_KEYS
  why: confirm both new state-key families are cleared by clear_all_state (the
       restore invariant the CHANGELOG states).

# MUST READ — the files being edited (current structure + exact anchors)
- file: README.md
  why: the Configuration table (lines 92-110) and the "Set any option before the
       plugin loads" code block (~line 112-115) followed by `## Usage`. The table is
       hand-padded (option col content width 34, default col 11). See research §2/§7.
  pattern: each row is `| \`@livepicker-<opt>\` <pad> | \`<default>\` <pad> | <purpose> |`.
  gotcha: the table is hand-padded; match the column widths exactly (research §2) or
          the source looks ragged (markdown still renders, but match conventions).
- file: CHANGELOG.md
  why: intro paragraph (lines 1-4) ending with the Keep a Changelog link, then
       `## [Unreleased] — Initial implementation` (line 6). The new section goes
       BETWEEN them. The existing header uses a real em dash (U+2014); the edit's
       oldText MUST copy that em dash exactly (it is not a hyphen).
  gotcha: do NOT rewrite the existing `[Unreleased] — Initial implementation`
          header (out of scope). Insert ABOVE it.
```

### Current Codebase tree (doc-relevant)

```bash
tmux-livepicker/
  README.md        # EDIT: +2 config-table rows + Appearance/Performance subsections
  CHANGELOG.md     # EDIT: +1 new [Unreleased] section (above the existing one)
  PRD.md           # READ-ONLY (do NOT edit) — the source of truth for §17/§18/§11
  scripts/         # UNCHANGED (§17/§18 already implemented)
  tests/           # UNCHANGED (§15.23/§15.24 already validated by sibling tasks)
  plan/002_facc52335e68/architecture/system_context.md   # READ — §1/§2 defaults
  plan/002_facc52335e68/P1M1.T3.S1/PRP.md, .../P1M2.T3.S1/PRP.md   # READ — behavior
```

### Desired Codebase tree with files to be edited

```bash
README.md      # +2 table rows (PRD §11 order) + ### Appearance + ### Performance
CHANGELOG.md   # +1 [Unreleased]: theme-matched tabs and deferred preview section
```

### Known Gotchas of our codebase & Library Quirks

```bash
# CRITICAL (research §5 — THE em-dash trap): the EXISTING README has ~20 em dashes
# and CHANGELOG has ~10. The write-tech-docs linter flags the WHOLE file, so
# `bash lint.sh README.md` does NOT exit 0 today and will NOT after this edit. Do
# NOT try to fix the pre-existing em dashes (out of scope; would rewrite unrelated
# prose). The gate is: the NEW prose (2 table rows, 2 notes, 1 CHANGELOG section)
# has ZERO em dashes and ZERO tell-words. Verify by checking the linter's reported
# line numbers are all PRE-EXISTING, and/or by grepping only your added lines.

# CRITICAL: the new CHANGELOG section header MUST NOT use an em dash. The existing
# `## [Unreleased] — Initial implementation` uses one (U+2014); do not copy that
# separator for the new header. Use a colon:
#   `## [Unreleased]: theme-matched tabs and deferred preview`
# This is a deliberate, compliant divergence from the pre-existing header style.

# CRITICAL: the edit anchoring the CHANGELOG insertion must match the EXISTING
# header's real em dash (U+2014) in oldText. It is not a hyphen `-` and not an
# en dash `–`. Copy it verbatim from the file (the read tool shows it).

# CRITICAL: the default asymmetry. `@livepicker-preview-defer` default = `on`
# (default-ON). `@livepicker-tab-style` default = `plain` (default-OFF for the new
# look). State both correctly in the CHANGELOG. (system_context.md §2.)

# GOTCHA: the config table is hand-padded. Option column content width = 34 chars
# (cell + trailing pad; widest row `@livepicker-suppress-window-hook` = 34 with
# zero pad). Default column = 11. Use the pre-padded rows in the Implementation
# Blueprint verbatim. The Purpose column trailing-pad is cosmetic; leave it
# unpadded (markdown renders identically).

# GOTCHA: insert BOTH table rows in ONE edit by anchoring on the unique
# `@livepicker-suppress-window-hook` row and replacing it with [preview-defer,
# suppress-window-hook, tab-style]. This yields PRD §11 order
# (preview-mode, preview-defer, suppress-window-hook, tab-style, fg) and avoids two
# fragile edits.

# GOTCHA: keep tmux primitives and option names in BACKTICKS (`link-window`,
# `select-window`, `switch-client`, `run-shell -b`, `window-status-current-format`,
# `@livepicker-*`, `clear_all_state`). The linter strips inline code before the
# tell-word/em-dash check, so backticked content is never flagged; plain words are.

# GOTCHA: do NOT narrate the implementation (no "the system does X", no file walks).
# State what the option is, its default, its effect, and its escape hatch. Stop.
# (write-tech-docs hard rule #4.)

# FORBIDDEN EDITS: PRD.md (READ-ONLY), tasks.json, prd_snapshot.md, .gitignore,
# any scripts/ or tests/ file. This task touches ONLY README.md and CHANGELOG.md.
```

## Implementation Blueprint

### Data models and structure

No data model. The structure is the placement of five small edits across two
files:

```
README.md
  ## Configuration
    | table ...                                  # unchanged
    | @livepicker-preview-mode   row             # unchanged (line ~103)
    | @livepicker-preview-defer  row             # NEW (insert here)
    | @livepicker-suppress-window-hook row       # unchanged (line ~104, the anchor)
    | @livepicker-tab-style      row             # NEW (insert here)
    | @livepicker-fg ...                        # unchanged (line ~105)
    "Set any option before the plugin loads" code block
    ### Appearance                               # NEW subsection
    ### Performance                              # NEW subsection
  ## Usage                                       # unchanged

CHANGELOG.md
  intro paragraph (Keep a Changelog link)
  ## [Unreleased]: theme-matched tabs and deferred preview   # NEW section
    ### Added
      - @livepicker-tab-style (default plain, §17) ...
      - @livepicker-preview-defer (default on, §18) ...
      - invariants (no client-session-changed; clear_all_state tears down all) ...
      - legacy paths remain (plain default; preview-defer off synchronous) ...
  ## [Unreleased] — Initial implementation       # unchanged (existing, em dash)
```

### Implementation Tasks (ordered by dependencies)

```yaml
Task 1: EDIT README.md — insert the two config-table rows (single edit)
  - ANCHOR (content, unique): the `@livepicker-suppress-window-hook` table row:
        | `@livepicker-suppress-window-hook` | `on`       | Clear `session-window-changed` during the picker to avoid focus-resync side effects.                 |
  - ACTION: replace that single row with THREE rows in this order:
        1. the NEW `@livepicker-preview-defer` row (pre-padded, verbatim below)
        2. the unchanged `@livepicker-suppress-window-hook` row (copy exactly)
        3. the NEW `@livepicker-tab-style` row (pre-padded, verbatim below)
    This yields PRD §11 order: preview-mode, preview-defer, suppress-window-hook,
    tab-style, fg.
  - VERBATIM new rows (copy the padding exactly; option col=34, default col=11):
        | `@livepicker-preview-defer`        | `on`        | Defer the live preview to a background job so typing and navigation never wait on `link-window`/`select-window`; `off` restores the synchronous path for diagnosis. |
        | `@livepicker-tab-style`            | `plain`     | `plain` (standalone `@livepicker-fg`/`bg`/`highlight-*`) or `window-status` (reuse the theme's `window-status-current-format` / `window-status-format` so picker tabs match your window tabs; falls back to `plain`). |
  - GOTCHA: copy the `@livepicker-suppress-window-hook` row from the file byte-for-byte
    (its purpose column has trailing padding); place it verbatim as the middle row.

Task 2: EDIT README.md — add the Appearance + Performance subsections (single edit)
  - ANCHOR (content, unique): the tail of the "Set any option" code block + the
    Usage header. Match this exactly (note the real backticks and the blank line):
        set -g @livepicker-highlight-bg 'magenta'
        ```

        ## Usage
  - ACTION: insert two subsections BETWEEN the closing ``` and `## Usage`. The new
    block (verbatim below) replaces the anchor with:
        set -g @livepicker-highlight-bg 'magenta'
        ```

        ### Appearance
        <appearance note>

        ### Performance
        <performance note>

        ## Usage
  - VERBATIM notes (from "Implementation Patterns" below). Keep the `###` headings;
    they are subsections of `## Configuration`.

Task 3: EDIT CHANGELOG.md — insert the new [Unreleased] section (single edit)
  - ANCHOR (content, unique): the Keep a Changelog link line + the existing header:
        Format based on
        [Keep a Changelog](https://keepachangelog.com/).

        ## [Unreleased] — Initial implementation
    NOTE: the existing header uses a REAL em dash (U+2014). Copy it exactly in oldText.
  - ACTION: insert the new section BETWEEN the link paragraph and the existing
    header. Replace the anchor with:
        Format based on
        [Keep a Changelog](https://keepachangelog.com/).

        ## [Unreleased]: theme-matched tabs and deferred preview

        ### Added

        <the four bullets from "Implementation Patterns" below>

        ## [Unreleased] — Initial implementation
  - GOTCHA: the new header uses a COLON (no em dash); the existing header keeps its
    em dash (unchanged). Do not alter the existing header.

Task 4: VALIDATE (lint the new prose + structural greps + invariant accuracy)
  - RUN: bash /home/dustin/.pi/agent/skills/write-tech-docs/scripts/lint.sh README.md
         bash /home/dustin/.pi/agent/skills/write-tech-docs/scripts/lint.sh CHANGELOG.md
    Expect NON-zero (pre-existing em dashes). Confirm EVERY reported line is a
    PRE-EXISTING line, NOT one of your added rows/notes/bullets. (See Validation
    Loop L1 for the targeted "new prose is clean" check.)
  - RUN: the structural greps (Validation Loop L2): both rows present in the right
    positions; both subsections present before ## Usage; CHANGELOG has the new
    section above the existing one.
  - RUN: the invariant-accuracy check (Validation Loop L3): defaults correct
    (preview-defer on / tab-style plain); both invariants stated.
  - RUN: git diff --stat PRD.md   # expect NO changes to PRD.md (READ-ONLY).
```

### Implementation Patterns & Key Details

**Task 1 — the two table rows (copy verbatim, padding included):**

```markdown
| `@livepicker-preview-defer`        | `on`        | Defer the live preview to a background job so typing and navigation never wait on `link-window`/`select-window`; `off` restores the synchronous path for diagnosis. |
| `@livepicker-suppress-window-hook` | `on`       | Clear `session-window-changed` during the picker to avoid focus-resync side effects.                 |
| `@livepicker-tab-style`            | `plain`     | `plain` (standalone `@livepicker-fg`/`bg`/`highlight-*`) or `window-status` (reuse the theme's `window-status-current-format` / `window-status-format` so picker tabs match your window tabs; falls back to `plain`). |
```

(The middle row is the unchanged `@livepicker-suppress-window-hook` row, copied
from the file. The edit replaces the single existing suppress-window-hook row
with these three rows. Note the suppress row's default column is padded to the
ORIGINAL 11-width used elsewhere for `on`; keep its existing padding as-is when
copying.)

**Task 2 — the Appearance and Performance notes (copy verbatim):**

```markdown
### Appearance

The picker can match your window-status theme. Set `@livepicker-tab-style window-status` and the picker renders its items through the theme's own `window-status-current-format` / `window-status-format`, so the tabs read as part of the status bar under any theme. The default is `plain`, which uses the standalone `@livepicker-fg` / `bg` / `highlight-*` colors. If the theme format cannot be resolved, the picker falls back to `plain`, so the option never breaks your status bar.

### Performance

The live preview is deferred by default. Typing and navigation redraw the status line immediately; the preview re-link runs in the background, so neither waits on `link-window` / `select-window`. Set `@livepicker-preview-defer off` to restore the synchronous preview path (useful for diagnosis).
```

**Task 3 — the CHANGELOG section (copy verbatim):**

```markdown
## [Unreleased]: theme-matched tabs and deferred preview

### Added

- **`@livepicker-tab-style`** (default `plain`, PRD §17). In `window-status` mode the picker renders its items through the theme's own `window-status-current-format` / `window-status-format`, so the picker tabs match your window tabs under any theme. A short-lived sentinel window resolves both formats once at activation; the renderer swaps the placeholder for each session name on every redraw. On any resolution failure it falls back to `plain`, so the option never breaks the status bar.
- **`@livepicker-preview-defer`** (default `on`, PRD §18). Typing and navigation redraw the status line synchronously and defer the live preview to a background, supersedeable `run-shell -b` job, so a keystroke never waits on `link-window` / `select-window`. Confirm never blocks on a preview. Set `off` to restore the synchronous preview path for diagnosis.
- Neither option changes the invariants the plugin already upholds. Browsing still fires no `client-session-changed` (the preview uses `link-window` / `select-window`, not `switch-client`), and `clear_all_state` still tears down every picker state key on exit, including the new template cache and preview-sequence keys.
- The existing `plain` tab style and the synchronous preview path remain available: `plain` is the shipped default, and `preview-defer off` is the synchronous escape hatch.
```

NOTE for the implementer:
- The new prose contains NO em dashes and NO tell-words. Keep every tmux primitive
  and option name in backticks (the linter strips inline code first).
- Do NOT rewrite the existing `[Unreleased] — Initial implementation` section, its
  `### Added`/`### Fixed`/etc., or any pre-existing em dashes.
- Do NOT touch `PRD.md`.

### Integration Points

```yaml
DOCS (the only integration surface):
  - file: README.md
    change: "+2 config-table rows (PRD §11 order) + ### Appearance + ### Performance"
    invariant: "the table mirrors PRD §11; a reader can discover + configure both
               options from the README alone"
  - file: CHANGELOG.md
    change: "+1 [Unreleased]: theme-matched tabs and deferred preview section (above
             the existing [Unreleased])"
    invariant: "states defaults (preview-defer on / tab-style plain), the pollution +
               restore invariants, and the legacy paths; PRD.md untouched"

CODE / DATABASE / CONFIG / ROUTES: none (documentation-only).
```

## Validation Loop

### Level 1: write-tech-docs lint on the NEW prose (the real gate)

```bash
cd /home/dustin/.config/tmux/plugins/tmux-livepicker
# Run the linter on both files. Expect NON-zero (pre-existing em dashes). Then
# confirm EVERY reported hit is on a PRE-EXISTING line, not one you added.
bash /home/dustin/.pi/agent/skills/write-tech-docs/scripts/lint.sh README.md
bash /home/dustin/.pi/agent/skills/write-tech-docs/scripts/lint.sh CHANGELOG.md

# Targeted "new prose is clean" check: extract ONLY the added lines and assert no
# em dashes / no tell-words. (The added lines are the two table rows, the two notes,
# and the four CHANGELOG bullets + their header.)
# 1. No em dash (U+2014) anywhere in the added prose:
grep -nP '\x{2014}' README.md CHANGELOG.md | grep -E 'preview-defer|tab-style|### Appearance|### Performance|theme-matched|Neither option|plain.* tab style and the synchronous' \
  && echo "FAIL: em dash in NEW prose" || echo "OK: no em dash in new prose"
# 2. No banned tell-words in the added prose (sample of the unambiguous ones):
grep -niEw 'powerful|robust|elegant|seamless|comprehensive|leverage|utilize|unlock|empower|streamline|elevate|delve|blazing-fast|intuitive|effortless|moreover|furthermore' README.md CHANGELOG.md \
  | grep -E 'preview-defer|tab-style|### Appearance|### Performance|theme-matched|Neither option' \
  && echo "FAIL: tell-word in NEW prose" || echo "OK: no tell-word in new prose"
# Expected: both checks print OK. (If a hit appears, it is in your added line: rewrite
# it without the em dash / tell-word. Pre-existing hits elsewhere are out of scope.)
```

### Level 2: structural greps (placement + presence)

```bash
cd /home/dustin/.config/tmux/plugins/tmux-livepicker
# README table: both rows present, in PRD §11 order.
awk '/@livepicker-preview-mode/{pm=NR} /@livepicker-preview-defer/{pd=NR} /@livepicker-suppress-window-hook/{sw=NR} /@livepicker-tab-style/{ts=NR} /@livepicker-fg/{fg=NR} END{printf "pm=%d pd=%d sw=%d ts=%d fg=%d\n",pm,pd,sw,ts,fg; exit !(pm<pd && pd<sw && sw<ts && ts<fg)}' README.md \
  && echo "OK: README table order (preview-mode < preview-defer < suppress-window-hook < tab-style < fg)" \
  || echo "FAIL: README table order wrong"
# README subsections present before ## Usage:
grep -q '### Appearance' README.md && grep -q '### Performance' README.md \
  && awk '/### Appearance/{a=NR}/### Performance/{p=NR}/## Usage/{u=NR;exit}END{exit !(a<p && p<u)}' README.md \
  && echo "OK: Appearance + Performance subsections present before ## Usage" \
  || echo "FAIL: notes missing or misplaced"
# README table now has 21 option rows (was 19):
[ "$(grep -c '^| `@livepicker' README.md)" -eq 21 ] && echo "OK: 21 config rows" || echo "FAIL: row count != 21"
# CHANGELOG: new section above the existing one:
awk '/theme-matched tabs and deferred preview/{n=NR}/Initial implementation/{i=NR}END{exit !(n<i)}' CHANGELOG.md \
  && echo "OK: new CHANGELOG section is above the existing one" \
  || echo "FAIL: CHANGELOG section missing or below existing"
# CHANGELOG names both options + both invariants:
grep -q '`@livepicker-tab-style`' CHANGELOG.md && grep -q '`@livepicker-preview-defer`' CHANGELOG.md \
  && grep -q 'client-session-changed' CHANGELOG.md && grep -q 'clear_all_state' CHANGELOG.md \
  && echo "OK: CHANGELOG names both options + both invariants" || echo "FAIL: CHANGELOG content incomplete"
# Expected: every check prints OK.
```

### Level 3: invariant accuracy (defaults + escape hatches stated correctly)

```bash
cd /home/dustin/.config/tmux/plugins/tmux-livepicker
# Default asymmetry stated correctly in CHANGELOG:
grep -q '`@livepicker-tab-style`\*\* (default `plain`' CHANGELOG.md \
  && grep -q '`@livepicker-preview-defer`\*\* (default `on`' CHANGELOG.md \
  && echo "OK: defaults correct (tab-style plain / preview-defer on)" \
  || echo "FAIL: defaults not stated correctly"
# Escape hatches stated in README:
grep -q '`@livepicker-preview-defer off`' README.md \
  && grep -q 'falls back to `plain`' README.md \
  && echo "OK: README states both escape hatches / fallbacks" \
  || echo "FAIL: README missing an escape hatch / fallback"
# PRD.md untouched:
git diff --quiet -- PRD.md && echo "OK: PRD.md unchanged" || echo "FAIL: PRD.md was modified (READ-ONLY)"
# Expected: every check prints OK. PRD.md MUST be unchanged.
```

### Level 4: render sanity (optional, eyeball check)

```bash
cd /home/dustin/.config/tmux/plugins/tmux-livepicker
# Confirm the table still parses as a table (a blank line does not precede the rows,
# and the header separator row is intact). Quick check: the row before the first new
# row and the row after the last new row are still table rows.
sed -n '/@livepicker-preview-mode/,/@livepicker-fg/p' README.md
# Expected: a contiguous block of `| ... |` rows with no blank line inside it, in the
# order preview-mode, preview-defer, suppress-window-hook, tab-style, fg.
# Also eyeball the CHANGELOG top to confirm the two [Unreleased] sections read in
# newest-first order with clear subtitles.
sed -n '1,30p' CHANGELOG.md
```

## Final Validation Checklist

### Technical Validation

- [ ] write-tech-docs linter run on both files; every reported hit is a PRE-EXISTING
      line (no em dash / tell-word / >100-word paragraph in the NEW prose).
- [ ] L1 targeted checks: no em dash and no tell-word in the added lines.
- [ ] L2 structural greps all pass (table order, 21 rows, notes before `## Usage`,
      CHANGELOG section above existing, both options + both invariants named).
- [ ] L3 invariant-accuracy checks pass (defaults correct; escape hatches stated;
      `PRD.md` unchanged).

### Feature Validation

- [ ] README Configuration table: `@livepicker-preview-defer` (default `on`) after
      `@livepicker-preview-mode`; `@livepicker-tab-style` (default `plain`) after
      `@livepicker-suppress-window-hook`.
- [ ] README `### Appearance`: explains `window-status` mode (reuse the theme's
      window-status formats), `plain` default, and the plain fallback.
- [ ] README `### Performance`: explains the deferred-by-default preview,
      synchronous status redraw, and `@livepicker-preview-defer off`.
- [ ] CHANGELOG new section: states both options, their defaults, the pollution
      invariant (no `client-session-changed` while browsing), the restore invariant
      (`clear_all_state` tears down all, incl. new keys), and the legacy paths.

### Code Quality Validation

- [ ] New prose follows write-tech-docs: no em dashes, no tell-words, no hedging,
      no codebase narration; one idea per sentence; concrete verbs.
- [ ] Table rows match the existing hand-padded column widths (option col 34,
      default col 11).
- [ ] Tmux primitives and option names are in backticks throughout the new prose.
- [ ] The new CHANGELOG header uses a colon (no em dash); the existing em-dash
      header is left unchanged.

### Documentation & Deployment

- [ ] A reader can discover and configure both options from the README alone.
- [ ] `PRD.md` is byte-identical to before (READ-ONLY honored).
- [ ] No `scripts/`, `tests/`, `tasks.json`, `prd_snapshot.md`, or `.gitignore`
      changes.

---

## Anti-Patterns to Avoid

- ❌ Don't demand `lint.sh` exit 0 on the whole file — the README/CHANGELOG already
  contain ~30 pre-existing em dashes. The gate is "the NEW prose is clean", verified
  on the added line numbers. Trying to "fix" the pre-existing em dashes is out of
  scope and rewrites unrelated prose. (research §5.)
- ❌ Don't use an em dash in the new CHANGELOG header to "match" the existing
  `[Unreleased] — …` style. The task mandates the write-tech-docs style (no em
  dashes). Use a colon: `## [Unreleased]: theme-matched tabs and deferred preview`.
- ❌ Don't get the default asymmetry backwards. `@livepicker-preview-defer` is
  default `on`; `@livepicker-tab-style` is default `plain`. State both exactly.
  (system_context.md §2.)
- ❌ Don't edit `PRD.md`, `tasks.json`, any `scripts/` or `tests/` file. This task
  touches ONLY `README.md` and `CHANGELOG.md`. `PRD.md` is READ-ONLY.
- ❌ Don't rewrite the existing `[Unreleased] — Initial implementation` section or
  its subsections. Insert a NEW section ABOVE it; leave the old one byte-identical.
- ❌ Don't misstate the invariants. Browsing fires no `client-session-changed`
  (preview uses `link-window`/`select-window`, NOT `switch-client`); `clear_all_state`
  tears down every picker state key (incl. the new `STATE_TAB_*` and `STATE_PREVIEW_*`
  families, both in `_STATE_RUNTIME_KEYS`). Cross-check against the implementing
  PRPs (P1.M1.T1.S1, P1.M2.T1.S1).
- ❌ Don't pad only one column of the new table rows — match BOTH the option column
  (34) and the default column (11), or the source looks ragged next to its neighbors.
- ❌ Don't add a second `### Added` under the EXISTING `[Unreleased]`. Plan-002 is a
  distinct changeset; give it its own scoped `[Unreleased]` section above the old one.
- ❌ Don't narrate the implementation in the README notes ("the renderer does X, then
  Y"). State the option, its default, its effect, its escape hatch. Stop.
- ❌ Don't leave tmux primitives / option names un-backticked in plain prose. The
  linter strips inline code before checking; plain `link-window` (no backticks) is
  still fine for the linter but inconsistent with the file's style. Backtick them.

---

## Confidence Score

**9 / 10** for one-pass success. Rationale: this is a scoped, low-risk
documentation edit on two files whose exact structure, anchors, column widths,
and insertion points are measured and given verbatim. The behavior claims are
cross-checked against three independent sources (PRD §17/§18/§11,
system_context.md §2, and the implementing PRPs P1.M1.T3.S1 / P1.M2.T3.S1), so
the defaults, the fallback, the deferred/synchronous split, and the two
invariants are all pinned. The single load-bearing nuance — that the
write-tech-docs linter does NOT exit 0 on these files because of pre-existing
em dashes, so the gate is "new prose is clean" rather than "whole-file lint
passes" — is identified and handled with a targeted check (L1). The new prose is
drafted to pass the style rules (no em dashes, no tell-words, no long
paragraphs, primitives in backticks). Residual risk: (i) an `edit`-tool
whitespace mismatch on the hand-padded table rows or the CHANGELOG's real em
dash in oldText — mitigated by the verbatim copy-paste blocks and the L2
structural greps that confirm placement afterward; (ii) the cosmetic
purpose-column trailing-padding inconsistency between new and existing rows —
mitigated by noting markdown renders identically and by matching the
option/default columns exactly. The 1-point deduction is for the byte-exactness
sensitivity of the table-padding and the existing em-dash anchor, both scoped
and verifiable, not for any missing context.
