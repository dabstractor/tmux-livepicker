# PRP — P1.M3.T1.S1: Update CHANGELOG.md with bug fix entries

## Goal

**Feature Goal**: Add a new `### Fixed` subsection to the **top (rev 002)**
`## [Unreleased]` section of `CHANGELOG.md` documenting all six QA bug fixes
from the rev 002 adversarial test pass (3 Major + 3 Minor), in the exact style
of the existing round-1 `### Fixed` block, without altering any other content.

**Deliverable**: A single in-place edit to `CHANGELOG.md` — one INSERT of a
`### Fixed` block (intro paragraph + six `**<Severity> — <title>.**` bullets,
ordered Major → Minor → Minor(docs)) immediately before the
`## [Unreleased] — Initial implementation` heading.

**Success Definition**: `CHANGELOG.md` contains two `### Fixed` subsections
(the round-1 block + the new rev 002 block), the new block documents all six
fixes in the file's existing entry style, the round-1 content is byte-for-byte
unchanged, and no third `## [Unreleased]` section is introduced.

## User Persona

**Target User**: Maintainers and future contributors reading the CHANGELOG to
understand what the rev 002 QA pass fixed and why.

**Use Case**: Auditing the shipped state of the plugin after the bugfix round,
or matching a regression to its fix + test.

**Pain Points Addressed**: The six fixes (Issues 1–6) are invisible in the
CHANGELOG today; readers can't tell which QA findings were addressed or which
tests guard them.

## Why

- **Changeset-level documentation sync (Mode B).** This subtask IS the
  documentation deliverable for the whole rev 002 bugfix changeset — it sweeps
  all six fixes into one CHANGELOG entry.
- The six code fixes are ALL complete (git log: `f37e3ee`, `70a50e3`, `2c12943`,
  `6aea983`, `8a35d4b`, `99d5137`, `3a67ae1`, `bec7369`); this task only records
  them. No code, no tests, no README change here.
- Keeps the rev 002 `## [Unreleased]` section self-contained: its features
  (`### Added`) + its QA fixes (`### Fixed`) live together.

## What

A single `### Fixed` block inserted into the **top** `## [Unreleased]` section
(`## [Unreleased]: theme-matched tabs and deferred preview`), placed AFTER the
existing `### Added` bullets and BEFORE the `## [Unreleased] — Initial implementation`
heading. The block contains:

1. A short intro paragraph naming the pass, the source findings doc, and the
   new test count (40 → 44).
2. Six bullets, severity-ordered (3 Major, then Minor, Minor, Minor/docs), each
   in the `**<Severity> — <title>.**` bold-lead style with: file(s) changed,
   root cause, fix mechanism, user impact, PRD cross-refs, and a
   `Regression test:` / `tests:` / related-coverage line.

### Success Criteria

- [ ] `grep -c '^### Fixed' CHANGELOG.md` → **2** (round-1 + new rev 002 block).
- [ ] `grep -c 'Major —\|Minor —\|Minor (docs) —' CHANGELOG.md` → **≥ 11**
  (5 round-1 + 6 new; round-1 also has a `Critical —`).
- [ ] `grep -c '^## \[Unreleased\]' CHANGELOG.md` → **2** (no third section added).
- [ ] All six fix titles / the new regression-test names appear in the new block.
- [ ] The round-1 `### Fixed` block (lines ~37–81 of the original) is byte-identical
  after the edit (verify with `git diff` — the diff must be a pure insertion).

## All Needed Context

### Context Completeness Check

_Passed._ A new contributor who knows nothing about this codebase can implement
this with only this PRP + read access to `CHANGELOG.md`: the exact anchor, the
exact entry style to mirror, the verified file/root-cause/test facts, and the
grep self-checks are all below.

### Documentation & References

```yaml
# MUST READ — the file you are editing
- file: CHANGELOG.md
  why: This is the ONLY file you edit. Read it fully to absorb the existing
        style and to confirm the insertion anchor before editing.
  pattern: The round-1 `### Fixed` block (starts at the line `### Fixed` that
            sits BELOW `## [Unreleased] — Initial implementation`) is the
            canonical entry style to mirror EXACTLY.
  gotcha: There are TWO `## [Unreleased]` sections. Insert into the TOP one
          (rev 002), NOT the initial-implementation one.

# The source of truth for each fix's facts
- file: plan/002_facc52335e68/bugfix/001_c7c6203f3e28/architecture/system_context.md
  why: Per-fix file list, root cause, mechanism, and the verified "BEFORE/AFTER"
        empirical proof for Issues 1/2/3/5.
  section: "Codebase Map (files touched)" + "Empirical Verification Results"

# The QA findings these fixes answer (PRD cross-refs + symptoms)
- file: PRD.md   # READ-ONLY — do not edit; cite §refs only
  why: Each bullet cites PRD section numbers (§6/§7/§9/§13/§15/§16/§17/§18).

# The prior CHANGELOG round (style precedent + intro wording)
- url: git log — commit 75a0b1b "Document five adversarial QA bugfixes in changelog"
  why: That round-1 block is the style this round mirrors. Its intro paragraph
        ("Adversarial QA bugfix pass — five issues found …") is the template
        for the new intro.
```

### Current Codebase tree (relevant slice)

```bash
CHANGELOG.md            # EDIT THIS — add `### Fixed` to the top rev 002 section
scripts/preview.sh      # Issues 1, 2, 4 (already fixed; reference only)
scripts/input-handler.sh# Issue 3      (already fixed; reference only)
scripts/livepicker.sh   # Issue 5      (already fixed; reference only)
scripts/renderer.sh     # Issue 5      (already fixed; reference only)
README.md               # Issue 6 Known Limitations (already added; reference only)
tests/                  # 44 test_* functions total (+4 this round)
```

### Known Gotchas of our codebase & CHANGELOG conventions

```text
# CRITICAL: There are TWO `## [Unreleased]` sections in CHANGELOG.md (pre-existing).
#   - TOP:    `## [Unreleased]: theme-matched tabs and deferred preview`  (rev 002; has only `### Added`)
#   - BOTTOM: `## [Unreleased] — Initial implementation`                   (has Added/Fixed/Documented/Notes)
# The new `### Fixed` block goes in the TOP (rev 002) section, AFTER its `### Added`.

# CRITICAL: The insertion anchor is the literal line:
#     ## [Unreleased] — Initial implementation
# This string is UNIQUE in the file (the rev 002 header uses `: theme-matched...`,
# NOT ` — Initial implementation`). Prepend the new block immediately above it.

# GOTCHA: Entry style (verified against the existing round-1 block) is:
#     - **<Severity> — <Title ends with period>.** <body>. (<PRD §refs>) Regression test: <name>.
#   Severity tokens used in-file: `Critical`, `Major`, `Minor`, `Minor (docs)`.
#   NOTE: the contract's example used `(Major):` parens style — DO NOT copy that.
#   Mirror the ACTUAL file style (`**Major — ...**`), not the contract example.

# GOTCHA: Severity ORDER in the round-1 block is descending: Critical → Major → Minor → Minor(docs).
#   For this round there is no Critical; order = Major(×3) → Minor → Minor → Minor(docs).

# GOTCHA: Issue 4 has NO dedicated regression test (defensive hardening only).
#   Reference the EXISTING `test_superseded_preview_noop` as "related coverage".
#   Do NOT fabricate a test name for Issue 4.

# GOTCHA: Issue 6 is docs-only; the README `### Known limitations` subsection is
#   owned by the parallel P1.M2.T3.S1 (it HAS landed — `grep -c 'Known [Ll]imitations'
#   README.md` = 1). The CHANGELOG entry for Issue 6 RECORDS that README change;
#   this task does NOT edit README.

# GOTCHA: Test count is 40 shipped → 44 now (+4 new tests this round). State "44"
#   (or "40 → 44") in the intro, NOT 30/30 (that was the round-1 count).
```

## Implementation Blueprint

### Implementation Tasks (ordered by dependencies)

```yaml
Task 1: READ CHANGELOG.md in full (confirm structure + anchor)
  - READ the entire file; confirm the TWO `## [Unreleased]` sections and that
    `## [Unreleased] — Initial implementation` is unique.
  - LOCATE the round-1 `### Fixed` block (the one BELOW the initial-implementation
    header) and study its 5 bullets as the exact style to mirror.
  - CONFIRM the insertion point: after the LAST `### Added` bullet of the TOP
    section (the line ending `…and \`preview-defer off\` is the synchronous escape hatch.`)
    and immediately before `## [Unreleased] — Initial implementation`.

Task 2: INSERT the new `### Fixed` block into the TOP (rev 002) section
  - USE the edit tool with oldText = the literal `## [Unreleased] — Initial implementation`
    line (unique in file) and newText = the new `### Fixed` block + a trailing
    blank line + that same header line.
  - MATCH the round-1 entry style EXACTLY (see "Entry content" below):
      * Intro paragraph: pass name + findings source doc path + test count (40→44).
      * Six bullets, severity-ordered: 3 Major, then Minor (Issue 4), Minor (Issue 5),
        Minor (docs) (Issue 6).
      * Each bullet: `- **<Severity> — <title>.**` lead, file(s) backticked, root cause
        (one phrase), fix mechanism, user impact, `(PRD §refs)`, and `Regression test:
        <name>` (Issues 1,2,3,5) / `Related coverage: test_superseded_preview_noop`
        (Issue 4) / `Docs only` (Issue 6).
  - PRESERVE: the top section's `### Added` bullets (unchanged), the round-1
    `### Fixed` block (byte-identical), and the two existing `## [Unreleased]`
    headings. NO third `## [Unreleased]` section. NO versioned `## [x.y.z]` header.

Task 3: SELF-CHECK (no edits) — run the grep gates from "Validation Loop Level 1".
```

### Entry content — exact facts to encode (all VERIFIED against live code)

```text
### Fixed

Adversarial QA bugfix pass — six issues found by an exploratory test pass on top
of the shipped `tests/run.sh` suite (rev 002: theme-matched tabs §17 + deferred
preview §18; see
`plan/002_facc52335e68/bugfix/001_c7c6203f3e28/architecture/system_context.md`).
All six are fixed; the suite is now 44/44 (was 40).

- **Major — Window indices are no longer permanently shifted by preview.**
  `scripts/preview.sh` linked the candidate with `tmux link-window -a` ("insert
  after active window"); when the driver's active window was not the last, the
  preview window was inserted in the MIDDLE of the list, shifting every later
  index, and `unlink-window` left the gap (`renumber-windows on` does NOT close
  gaps on unlink). Dropping `-a` appends at the end and unlinks cleanly back to
  the original indices, restoring PRD §9 / §15 exact restoration on the DEFAULT
  code path (session mode, browse, cancel/confirm). Regression tests:
  `test_preview_preserves_window_indices_cancel`,
  `test_preview_preserves_window_indices_confirm` (new — the shipped tests
  asserted only on window IDs, which is why this escaped).

- **Major — Window-mode preview of a driver-owned window no longer creates a
  duplicate link.** `scripts/preview.sh`'s self-session guard compared the raw
  token `$S` to the session name; in window mode `$S` is a `session:index` token
  that never equals the bare name, so the guard never fired and `link-window`
  silently duplicated an already-linked window (polluting the list, shifting
  indices, and mis-resolving later navigation). The guard now extracts
  `${S%%:*}` for window mode. Regression test: `test_window_preview_driver_self_no_duplicate`.

- **Major — Create-on-confirm with a sanitized name no longer orphans the
  session and strands the user.** `.` is typeable; tmux silently sanitizes
  session names (`my.proj` → `my_proj`), so `new-session` SUCCEEDED while the
  `has-session -t "=$query"` gate used the ORIGINAL query and FAILED, falling
  through to `restore.sh cancel` and leaving a phantom session behind. The
  confirm branch now captures the actual created name via
  `new-session -P -F '#{session_name}'` and lands on it (PRD §6). Regression
  test: `test_create_sanitized_name_lands_on_session`.

- **Minor — The deferred-preview supersede guard no longer has a TOCTOU gap.**
  `scripts/preview.sh` checked the supersede sequence at entry and before the
  unlink/link block, but a window of real tmux round-trips sat between the
  second check and the trailing `set_state LINKED_ID`; a confirm/restore during
  that window could let a late job proceed to link an orphan window (proven with
  an injected 0.4s delay, 5/5). A third sequence re-check immediately before
  `set_state` plus an idempotent pre-link probe closes the gap (PRD §18 / §16).
  Related coverage: `test_superseded_preview_noop`.

- **Minor — `@livepicker-tab-style window-status` now works for themes using
  session-context specifiers.** `scripts/livepicker.sh` resolved the sentinel
  window name to a swappable `__lp_tab__` placeholder, but a theme's
  `#{session_name}` / `#S` expanded to the sentinel's unique session name
  (`__lp_sent_<pid>_<ts>`, NOT swappable), so the single swap missed it and every
  tab rendered the literal sentinel session name. The sentinel now uses a STABLE
  session name as a second placeholder and `scripts/renderer.sh` swaps BOTH in
  the window-status render path (PRD §17). Regression test:
  `test_sentinel_resolution_end_to_end`.

- **Minor (docs) — Detached candidate window resize is now documented as a known
  limitation.** Linking a detached candidate window for preview lets tmux's
  `window-size auto` resize the shared window object to the driver's size, and on
  unlink it shrinks to the no-client default (pane count and window id intact;
  geometry changes) — inherent to `link-window` (PRD §7 / §15). Added a
  `### Known limitations` subsection to `README.md`. Docs only.
```

### Implementation Patterns & Key Details

```text
# PATTERN (round-1 intro, to mirror): lead with pass name + "issues found by an
# exploratory test pass on top of the shipped tests/run.sh suite" + the findings
# source doc path, then "+N tests" count. Round-1 said "30/30"; THIS round's
# count is "44/44 (was 40)".

# PATTERN (bullet body): backtick the file(s), state the root cause as one
# phrase ("X did Y; ..."), state the fix mechanism ("now Z"), state the user-
# visible impact, then `(PRD §refs)` then `Regression test: <name>.`

# CRITICAL: Severity must read `**Major — ...**` / `**Minor — ...**` /
# `**Minor (docs) — ...**` (em dash, spaces), matching the round-1 block. The
# contract's example `(Major):` parens form is NOT the file's convention.

# CRITICAL: do NOT invent a regression-test name for Issue 4. It has none;
# cite `test_superseded_preview_noop` as "Related coverage".
```

### Integration Points

```yaml
FILES:
  - edit:   CHANGELOG.md   (ONLY this file; pure insertion, no deletion/rewrite)

NO CHANGES TO:
  - scripts/*.sh        # all fixes already landed (reference only)
  - tests/*.sh          # all tests already landed (reference only)
  - README.md           # Issue 6 Known Limitations owned by P1.M2.T3.S1 (landed)
  - PRD.md / tasks.json / prd_snapshot.md   # READ-ONLY / orchestrator-owned
```

## Validation Loop

### Level 1: Structure & format self-checks (run immediately after the edit)

```bash
# Exactly two `### Fixed` subsections (round-1 + new rev 002).
test "$(grep -c '^### Fixed' CHANGELOG.md)" -eq 2 \
  && echo "OK: 2 ### Fixed blocks" || echo "FAIL"

# Exactly two `## [Unreleased]` sections (no third added; no versioned header).
test "$(grep -c '^## \[Unreleased\]' CHANGELOG.md)" -eq 2 \
  && echo "OK: 2 Unreleased sections" || echo "FAIL"

# At least 11 severity-lead bullets total (5 round-1 + 6 new; round-1 has a
# Critical too). This asserts all six new bullets landed.
n=$(grep -c 'Major —\|Minor —\|Minor (docs) —' CHANGELOG.md)
[ "$n" -ge 11 ] && echo "OK: $n severity bullets (>=11)" || echo "FAIL: $n"

# All six new regression/test references present.
for ref in \
  test_preview_preserves_window_indices_cancel \
  test_preview_preserves_window_indices_confirm \
  test_window_preview_driver_self_no_duplicate \
  test_create_sanitized_name_lands_on_session \
  test_superseded_preview_noop \
  test_sentinel_resolution_end_to_end ; do
  grep -q "$ref" CHANGELOG.md && echo "OK: $ref" || echo "MISSING: $ref"
done

# The round-1 block is unchanged: the diff must be a PURE insertion.
git diff CHANGELOG.md | grep '^-' | grep -v '^---' | grep -q . \
  && echo "FAIL: edit deleted/changed existing lines (must be insert-only)" \
  || echo "OK: pure insertion"
```

### Level 2: Content sanity (manual read)

- Read the new `### Fixed` block: every bullet has the `**<Severity> — <title>.**`
  lead, backticked file, root cause, fix, impact, `(PRD §refs)`, and a
  test/coverage line.
- Severity order is Major(×3) → Minor → Minor → Minor(docs).
- Intro paragraph cites the findings source doc path and "44/44 (was 40)".

### Level 3: N/A (no code, no service, no database)

This is a static-document edit; there is no runtime to start or integration to
probe. The plugin test suite is unaffected (no `tests/run.sh` run needed — the
CHANGELOG is not executed).

### Level 4: N/A (no creative/domain validation)

## Final Validation Checklist

### Technical Validation

- [ ] `grep -c '^### Fixed' CHANGELOG.md` == 2
- [ ] `grep -c '^## \[Unreleased\]' CHANGELOG.md` == 2
- [ ] `grep -c 'Major —\|Minor —\|Minor (docs) —' CHANGELOG.md` >= 11
- [ ] All six regression/test references present (see Level 1 loop)
- [ ] `git diff CHANGELOG.md` is a pure insertion (no `-` content lines)

### Feature Validation

- [ ] All six fixes (Issues 1–6) documented in the new `### Fixed` block
- [ ] Severity ordering: 3 Major, then Minor (4), Minor (5), Minor/docs (6)
- [ ] Each entry mirrors the round-1 style (`**Severity — title.**`, files
      backticked, root cause, fix, impact, PRD §refs, test/coverage line)
- [ ] Issue 4 references `test_superseded_preview_noop` (no fabricated test name)
- [ ] Issue 6 recorded as docs-only (records the README Known Limitations change)
- [ ] Intro paragraph names the pass + findings doc + "44/44 (was 40)"

### Code Quality Validation

- [ ] Round-1 `### Fixed` block byte-for-byte unchanged
- [ ] No third `## [Unreleased]` section; no versioned `## [x.y.z]` header
- [ ] No edits to `scripts/`, `tests/`, `README.md`, `PRD.md`, `tasks.json`

### Documentation & Deployment

- [ ] New `### Fixed` block sits in the TOP (rev 002) `## [Unreleased]` section,
      after its `### Added` and before `## [Unreleased] — Initial implementation`
- [ ] Every PRD § cross-reference matches the verified mapping (1→§9/§15,
      2→§7, 3→§6, 4→§18/§16, 5→§17, 6→§7/§15)

---

## Anti-Patterns to Avoid

- ❌ Don't edit any file other than `CHANGELOG.md` (this is CHANGELOG-only).
- ❌ Don't invent a regression-test name for Issue 4 (it has none).
- ❌ Don't use the contract's `(Major):` parens style — mirror the file's actual
  `**Major — ...**` em-dash style.
- ❌ Don't add a versioned header or a third `## [Unreleased]` section.
- ❌ Don't touch the round-1 `### Fixed` block or any existing content —
  the edit must be a pure insertion.
- ❌ Don't state the old test count as 30/30 (that was round-1); this round is
  40 → 44.

---

## Confidence Score

**9/10** — one-pass success likelihood. The task is a single pure-insertion edit
to one static file. The exact anchor, the exact entry style (mirrored from the
verified round-1 block), and all six fixes' verified facts (files, root causes,
mechanisms, exact regression-test names that exist in `tests/`) are captured
above. The only residual risk is a style nuance (em-dash vs parens), which is
explicitly resolved to "mirror the file." The grep self-checks catch any
structural slip on the spot.
