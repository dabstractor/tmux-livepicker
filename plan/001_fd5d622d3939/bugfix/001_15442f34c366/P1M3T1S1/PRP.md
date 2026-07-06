# PRP — Bugfix P1.M3.T1.S1: Update CHANGELOG with all 5 bugfix entries + verify README consistency

> **Task context**: This is the changeset-level documentation sync (Mode B) for
> the adversarial QA bugfix pass (`plan/001_fd5d622d3939/bugfix/001_15442f34c366/`).
> All 5 fixes (Issues 1–5) are COMPLETE in code (test count 24→30). This task
> records them in `CHANGELOG.md` under a new `### Fixed` subsection (Keep a
> Changelog's standard bug-fix category), then verifies `README.md` is consistent
> with the fixes. **Documentation-only**: no scripts, no tests, no new files,
> no `PRD.md` edits.

---

## Goal

**Feature Goal**: `CHANGELOG.md` documents all 5 adversarial-QA bugfixes under a
new `### Fixed` subsection of the existing `## [Unreleased]` section — each entry
naming the severity, a one-line summary, the file(s) changed, and the
user-visible impact, and referencing the regression test(s) added. `README.md` is
verified consistent with the fixes (and, only if an inconsistency is found,
touched minimally).

**Deliverable**:
1. One edit to `CHANGELOG.md`: insert a `### Fixed` subsection (5 bullets + a
   one-line pass-summary intro) between the existing `### Added` and
   `### Documented corrections` subsections. The verbatim block is in the
   Implementation Blueprint.
2. A verification pass on `README.md` (grep gates proving the 3 consistency
   points hold). **No README edit is expected** — the README is already consistent
   (the only README change in this changeset, the validate.sh removal, is owned by
   the parallel P1.M2.T3.S1).

**Success Definition**:
- `grep -c '^### Fixed' CHANGELOG.md` returns `1`.
- `grep -c 'Critical —\|Major —\|Minor —\|Minor (docs) —' CHANGELOG.md` returns
  `≥ 5` (all five severity-tagged entries present).
- All 6 regression-test names introduced by the 5 fixes are referenced in the
  CHANGELOG (`grep -c` over the 6 names → `≥ 5`; some entries name two tests).
- `grep -c 'validate\.sh\|VALIDATE_SKIP_SLOW' README.md` returns `0` (Issue 5
  still resolved).
- `grep -n 'preview follows live' README.md` still prints Usage §3 (Issue 2's
  promise is now true, not just aspirational).
- No file other than `CHANGELOG.md` is modified (README verified, not edited,
  unless an inconsistency is found — none expected).

## User Persona (if applicable)

**Target User**: Anyone reading the CHANGELOG to understand what changed in this
bugfix pass — maintainers, contributors, and (eventually) end users reading release
notes. Mode B (changeset-level documentation spanning the whole bugfix effort).

**Use Case**: A maintainer opens CHANGELOG.md to write release notes or a PR
description for the bugfix pass. Each entry tells them: what broke, how severe it
was, which file was fixed, what the user experiences now, and which test guards it.

**Pain Points Addressed**: Before this task, the 5 fixes exist only in the bugfix
PRD (`plan/.../bugfix_findings.md`) and the per-subtask PRPs — not in the
user/maintainer-facing CHANGELOG. The CHANGELOG's `### Added` section describes
the initial build but is silent on the QA remediation. This task closes that gap.

## Why

- **The SOW makes this the documentation capstone.** The work-item contract (§6
  DOCS) states: "This IS the changeset-level documentation sync task (Mode B). It
  covers CHANGELOG.md and README.md overview sections that span the whole
  changeset. Per-subtask docs (Mode A) were handled in the implementing subtasks."
- **Keep a Changelog discipline.** The repo's CHANGELOG explicitly follows
  [Keep a Changelog](https://keepachangelog.com/), whose standard category for bug
  fixes is `### Fixed`. The file has `### Added` but no `### Fixed`; this adds it.
- **Traceability.** Each entry cross-references the regression test(s) that guard
  the fix, so a future maintainer can find the test that proves the fix and
  (via its "reintroduce-the-bug → FAIL" check) understand the regression shape.
- **Disjoint & low-risk.** A single Markdown insertion in one file; no code, no
  tests, no config. The README step is read-only verification. Fully disjoint from
  the (complete) code fixes and from the (parallel) README validate.sh edit.

## What

A single insertion in `CHANGELOG.md`: a `### Fixed` subsection placed between the
existing `### Added` and `### Documented corrections` subsections, containing a
one-line pass summary and five bullets (one per issue). Each bullet follows the
existing CHANGELOG entry style: a bold severity lead-in, a one-line summary, the
file(s) changed (backticked), the root cause in one phrase, the user-visible
impact, and the regression test(s) added (backticked function names). Then a
README verification pass (grep gates) confirming consistency — no edit expected.

### Success Criteria

- [ ] `CHANGELOG.md` has a `### Fixed` subsection under `## [Unreleased]`,
      placed between `### Added` and `### Documented corrections`.
- [ ] The `### Fixed` section contains exactly 5 issue bullets, each tagged
      Critical / Major / Minor / Minor (docs).
- [ ] Each bullet names the file(s) changed and the user-visible impact.
- [ ] Each bullet references its regression test(s) by function name.
- [ ] The single `## [Unreleased]` section is preserved (no duplicate heading;
      no version number added).
- [ ] `README.md` is unchanged AND passes the 3 consistency grep gates.
- [ ] No file other than `CHANGELOG.md` is modified.

## All Needed Context

### Context Completeness Check

_Pass_: An implementer who has never seen this repo can do this from (a) the
verbatim `### Fixed` block in the Implementation Blueprint (copy-paste), (b) the
exact insertion anchor (`### Documented corrections` — unique), (c) the grep
self-checks that prove all 5 entries landed and the README is consistent, and
(d) the per-issue facts (severity/file/impact/test) verified live and tabulated in
research/changelog_readme_sync_findings.md §2. No inference required.

### Documentation & References

```yaml
# MUST READ — the empirical ground-truth for THIS task (format + 5 fixes + README state)
- docfile: plan/001_fd5d622d3939/bugfix/001_15442f34c366/P1M3T1S1/research/changelog_readme_sync_findings.md
  why: §1 (CHANGELOG structure + the placement decision + the exact insertion anchor);
       §2 (all 5 fixes: files changed, verified grep markers, root cause, user-visible
       impact, regression-test names); §3 (README consistency table — already consistent,
       no edit needed); §4 (scope boundaries); §5 (validation grep gates).
  critical: Read BEFORE writing the entries — the severity tags, file lists, test names,
       and user-impact phrasing are all verified there. The placement (between ### Added
       and ### Documented corrections) and the single-Unreleased-section rule are load-bearing.

# MUST READ — the bug report (the authoritative source for the 5 issues)
- docfile: plan/001_fd5d622d3939/bugfix/001_15442f34c366/architecture/bugfix_findings.md
  why: §ISSUE 1–5 give severity, PRD reference, location, root cause, expected/actual
       behaviour, and repro for each issue. The CHANGELOG entries summarise these.
  critical: The bugfix_findings "Fix" notes are DETAILED; the CHANGELOG condenses each to
       one bullet (severity + summary + files + impact + test). Do NOT copy the full
       repro/steps-to-reproduce into the CHANGELOG — it is a summary, not a report.

# MUST READ — the file being edited
- file: CHANGELOG.md
  why: The single file under edit. 45 lines; Keep a Changelog format; one
       `## [Unreleased] — Initial implementation` section with `### Added` /
       `### Documented corrections` / `### Notes for maintainers` subsections.
  pattern: Entries are `- ` bullets with a `**bold lead-in**`, hand-wrapped ~76–80 cols,
       backticked code identifiers (`` `status-format[n]` ``, `` `tests/run.sh` ``), and
       PRD cross-refs (`(PRD §10.)`). Match this style exactly in the new `### Fixed` bullets.
  gotcha: Do NOT add a `## [x.y.z] — date` version header (no tagged release exists).
          Keep the single `## [Unreleased]` section. Do NOT reorder/rewrite existing
          subsections — only INSERT `### Fixed` before `### Documented corrections`.

# MUST READ — the file being verified (NOT edited unless inconsistent)
- file: README.md
  why: Verification target. The 3 consistency points: (1) Validation § has no
       validate.sh/VALIDATE_SKIP_SLOW reference (Issue 5, fixed by P1.M2.T3.S1);
       (2) Usage §3 line ~128 "The preview follows live." is now TRUE (Issue 2);
       (3) Overview line ~10 "live, all-panes preview of the highlighted candidate"
       is now accurate (Issue 2). All three currently PASS (verified live).
  gotcha: Do NOT edit README.md unless a grep gate FAILS. The README Maintenance
          section already defers release notes to the CHANGELOG, so no README change
          is needed to surface the changelog content.

# Reference — the 5 fix PRPs (for double-checking file/test names)
- docfile: plan/001_fd5d622d3939/bugfix/001_15442f34c366/P1M1T1S1/PRP.md   # Issue 1
- docfile: plan/001_fd5d622d3939/bugfix/001_15442f34c366/P1M1T2S1/PRP.md   # Issue 2
- docfile: plan/001_fd5d622d3939/bugfix/001_15442f34c366/P1M2T1S1/PRP.md   # Issue 3
- docfile: plan/001_fd5d622d3939/bugfix/001_15442f34c366/P1M2T2S1/PRP.md   # Issue 4
- docfile: plan/001_fd5d622d3939/bugfix/001_15442f34c366/P1M2T3S1/PRP.md   # Issue 5
  why: Each PRP's Goal/Integration Points confirm the exact file(s) changed and the
       regression-test function name(s). The research file §2 already distilled these;
       consult a PRP only if you want to verify a specific file/test name.
```

### Current Codebase tree

```bash
tmux-livepicker/
  CHANGELOG.md   # MODIFY: insert ### Fixed subsection (5 bullets) before ### Documented corrections
  README.md      # VERIFY ONLY (consistency gates) — do NOT edit unless a gate fails (none expected)
  PRD.md         # UNCHANGED (READ-ONLY — agents must not edit)
  scripts/       # UNCHANGED (all 5 fixes complete)
  tests/         # UNCHANGED (30 test_* functions; +6 regression tests from the 5 fixes)
  plugin.tmux    # UNCHANGED
```

### Desired Codebase tree with files to be added and responsibility of file

```bash
CHANGELOG.md   # + ### Fixed subsection under ## [Unreleased]: 5 bugfix bullets (severity/summary/files/impact/test)
# (no files added; documentation-only change to CHANGELOG.md; README verified, not edited)
```

### Known Gotchas of our codebase & Library Quirks

```bash
# CRITICAL (research §1): there is exactly ONE `## [Unreleased]` section. Do NOT
# add a second `## [Unreleased] — Bugfix` heading and do NOT add a versioned
# `## [x.y.z]` header. Keep a Changelog accumulates all unreleased changes under
# one Unreleased section. Add a `### Fixed` SUBSECTION to the existing section.

# CRITICAL (research §1): insert `### Fixed` BETWEEN `### Added` and
# `### Documented corrections` (narrative order: Added → Fixed → corrections →
# notes). Anchor the edit on the unique `### Documented corrections` heading and
# PREPEND the Fixed block. Do NOT place it at EOF (after Notes for maintainers) —
# that breaks the reading order.

# CRITICAL: do NOT edit README.md unless a consistency grep gate FAILS. Verified
# live (2026-07-06): validate.sh=0 refs; "preview follows live" present (Usage §3);
# Overview live-preview language present and accurate. The only README edit in this
# changeset (validate.sh removal) is owned by P1.M2.T3.S1. README's Maintenance
# section already points release notes to the CHANGELOG — no README change needed.

# CRITICAL: PRD.md is READ-ONLY. The bugfix PRD (plan/.../prd_snapshot.md and the
# bugfix_findings.md) is the SOURCE for the issue facts, but you must NOT edit
# PRD.md, prd_snapshot.md, or any prd_* file. Only CHANGELOG.md is writable here.

# GOTCHA (style): match the existing CHANGELOG entry style exactly — `- ` bullets,
# `**bold severity lead-in**`, hand-wrapped ~76–80 cols, backticked code
# identifiers and test names, parenthesised PRD/plan cross-refs. See the verbatim
# block in Implementation Patterns; use it as-is.

# GOTCHA: the 6 regression-test names are load-bearing traceability — include
# each fix's test(s) by function name:
#   Issue 1 -> test_window_confirm_preserves_custom_status_format
#   Issue 2 -> test_preview_follows_type_filter, test_preview_follows_backspace
#   Issue 3 -> test_renderer_escapes_hash_in_names, test_renderer_escapes_hash_in_filter
#   Issue 4 -> test_window_preview_shows_highlighted_window
#   Issue 5 -> (none; doc-only, grep is the gate)
# Do NOT invent or rename tests; these are the actual function names in tests/.

# GOTCHA: the pass summary line states the suite went 24 -> 30 (the initial shipped
# suite was 24/24; the 5 fixes added 6 regression tests). Use "30/30" for the
# post-fix count. Do NOT claim a specific version number (there is none).

# GOTCHA: keep the existing `## [Unreleased] — Initial implementation` subtitle
# intact — do NOT rename it to "— Initial implementation + bugfix pass". The
# `### Fixed` subsection is sufficient to convey the bugfix pass.
```

## Implementation Blueprint

### Data models and structure

None. No data, no schema, no state. This is a Markdown insertion in one file plus
a read-only verification pass on a second file.

### Implementation Tasks (ordered by dependencies)

```yaml
Task 1: MODIFY CHANGELOG.md — insert the ### Fixed subsection
  - LOCATE the boundary between `### Added` and `### Documented corrections`
    (~CHANGELOG line 26-28). The unique anchor is the heading line
    `### Documented corrections`.
  - INSERT (immediately BEFORE `### Documented corrections`) the verbatim
    `### Fixed` block from "Implementation Patterns & Key Details" below — a
    one-line pass-summary, then 5 bullets (Issues 1-5 in severity order:
    Critical, Major, Minor, Minor, Minor/docs).
  - STYLE: match existing entries — `- ` bullets, `**bold lead-in**`, ~76-80 col
    hand-wrap, backticked identifiers/test-names, parenthesised cross-refs.
  - PRESERVE: the `# Changelog` header, the `## [Unreleased] — Initial
    implementation` section + its subtitle, the entire `### Added` block, the
    `### Documented corrections` block, the `### Notes for maintainers` block.
    Do NOT add a version header; do NOT create a second Unreleased section.
  - PLACEMENT: between `### Added` and `### Documented corrections`.

Task 2: VERIFY README.md consistency (grep gates — NO edit expected)
  - RUN (Level 1): grep -c 'validate\.sh\|VALIDATE_SKIP_SLOW' README.md   # -> 0
  - RUN (Level 1): grep -n 'preview follows live' README.md               # -> Usage §3 present
  - RUN (Level 1): grep -n 'all-panes preview of the highlighted candidate' README.md  # -> Overview present
  - IF any gate FAILS (not expected): apply the minimal specific touch:
      * validate.sh ref present -> remove the clause (mirror P1.M2.T3.S1's fix;
        but that task owns it, so this is a defensive fallback only).
      * "preview follows live" missing -> do NOT re-add (it is present); investigate.
    Otherwise: leave README.md byte-for-byte unchanged.
  - DO NOT: add a README section for the bugfix pass (the Maintenance section
    already defers release notes to the CHANGELOG).

Task 3: VALIDATE (grep self-checks on CHANGELOG + the README gates)
  - RUN: grep -c '^### Fixed' CHANGELOG.md                                # -> 1
  - RUN: grep -c 'Critical —\|Major —\|Minor —\|Minor (docs) —' CHANGELOG.md  # -> >= 5
  - RUN: grep -c '<the 6 test names>' CHANGELOG.md                        # -> >= 5
  - RUN: the 3 README consistency gates from Task 2.
  - OPTIONAL: bash tests/run.sh  # 30/30; README/CHANGELOG aren't read by tests,
    so this only confirms nothing else regressed (~2-3 min).
```

### Implementation Patterns & Key Details

**Task 1 — the `### Fixed` block (paste verbatim; hand-wrap matches the file).**
This is the **only** edit. Anchor on the unique heading `### Documented corrections`
and prepend the block. The five entries are in severity order (Critical → Major →
3× Minor), each with: severity, one-line summary, file(s) changed, root cause,
user-visible impact, and regression test(s).

> **Edit instruction**: match `oldText` = `### Documented corrections` (unique in
> the file) and replace with the `### Fixed` block below followed by a blank line
> and `### Documented corrections`. (Concretely, `newText` =
> `<the ### Fixed block>\n\n### Documented corrections`.)

The `### Fixed` block to insert (matches existing entry style: `- ` bullets,
`**bold**` lead-ins, ~76–80 col hand-wrap, backticked identifiers):

```markdown
### Fixed

Adversarial QA bugfix pass — five issues found by an exploratory test pass on top
of the shipped 24/24 `tests/run.sh` suite (see
`plan/001_fd5d622d3939/bugfix/001_15442f34c366/architecture/bugfix_findings.md`).
All five are fixed with regression tests; the suite is now 30/30.

- **Critical — Window-mode confirm no longer destroys custom `status-format`.**
  Removed a stray duplicate `restore.sh keep-window` call in the window-mode
  confirm branch (`scripts/input-handler.sh`) whose second invocation ran after
  `clear_all_state` had emptied the saved state, so `state_status_format_restore`
  replayed an empty index list over a `set-option -gu status-format` — wiping every
  custom `status-format[n]` to tmux defaults and forcing `status` /
  `renumber-windows` / `key-table` to defaults. A window-mode confirm now leaves
  status configuration byte-identical to pre-activation, exactly like session-mode
  confirm and cancel. Regression test: `test_window_confirm_preserves_custom_status_format`.
- **Major — The live preview now follows the highlighted candidate when typing or
  backspacing.** The `type`, `backspace`, and cancel query-clear branches refreshed
  only the status-line highlight and never called `preview.sh` (only
  `next-session` / `prev-session` did), so the large preview pane stayed frozen
  while the highlight moved. A new shared helper `_lp_sync_preview_to_top_match`
  (`scripts/input-handler.sh`) re-links the preview to the top filtered match on
  every query change, reconciling PRD §3 / §7 and the README's "the preview follows
  live" promise (which had contradicted the PRD §5 data-flow diagram). Regression
  tests: `test_preview_follows_type_filter`, `test_preview_follows_backspace`.
- **Minor — Renderer no longer mis-renders session names containing `#`.**
  `scripts/renderer.sh` emitted candidate names and the filter query raw into tmux
  `#[...]` format strings, so a name like `#dev` was re-interpreted (`#d` →
  day-of-month) and a name like `#[fg=red]x` injected styling. Every `#` is now
  doubled to `##` (tmux's literal-`#` escape) on local copies at all five emission
  sites; stored state and `filter.sh` are untouched, so navigation and confirm still
  resolve the real name. Regression tests: `test_renderer_escapes_hash_in_names`,
  `test_renderer_escapes_hash_in_filter`.
- **Minor — Window-mode preview now shows the highlighted window, not the
  session's active window.** `scripts/preview.sh` resolved the candidate via
  `#{window_active}`, which ignored the `session:index` token's index, so previewing
  `alpha:5` showed `alpha`'s active window instead of window 5. It now branches on
  `@livepicker-type` and resolves the specific window `@id` by index (session mode
  is unchanged); the `capture-pane` fallback target is also corrected for
  window-mode tokens. Regression test: `test_window_preview_shows_highlighted_window`.
- **Minor (docs) — README no longer references a non-existent `./validate.sh`.**
  The Validation section advertised a `VALIDATE_SKIP_SLOW=1` budget in
  `./validate.sh`, which does not exist (the real runner is `tests/run.sh`, which
  has no such flag). The broken clause is removed and the paragraph repaired;
  `bash tests/run.sh` is now the only documented validation entry point.
```

**After the edit, the CHANGELOG structure reads (top → bottom):**

```
# Changelog
... (intro) ...
## [Unreleased] — Initial implementation
### Added
... (initial implementation + 3 invariants) ...
### Fixed                         <- NEW (this task)
... (pass summary + 5 bullets) ...
### Documented corrections
... (tmux floor 3.0->3.2) ...
### Notes for maintainers
... (PRD §0 removal recommendation) ...
```

**Verification after the edit (copy-paste):**

```bash
cd /home/dustin/.config/tmux/plugins/tmux-livepicker
grep -c '^### Fixed' CHANGELOG.md                                              # -> 1
grep -c 'Critical —\|Major —\|Minor —\|Minor (docs) —' CHANGELOG.md            # -> >= 5
grep -cE 'test_window_confirm_preserves_custom_status_format|test_preview_follows_type_filter|test_preview_follows_backspace|test_renderer_escapes_hash_in_names|test_renderer_escapes_hash_in_filter|test_window_preview_shows_highlighted_window' CHANGELOG.md  # -> >= 5
grep -n '^## \[' CHANGELOG.md                                                  # -> one ## [Unreleased] line (no duplicate/version)
sed -n '/^### Fixed/,/^### Documented corrections/p' CHANGELOG.md              # eyeball the 5 bullets
```

### Integration Points

```yaml
DOCS:
  - file: CHANGELOG.md
    change: "insert ### Fixed subsection (5 bullets) between ### Added and
             ### Documented corrections under ## [Unreleased]"
    invariant: "one ## [Unreleased] section; ### Added / ### Fixed / ### Documented
               corrections / ### Notes for maintainers in that order; existing
               entries byte-for-byte unchanged"

README:
  - file: README.md
    change: "NONE (verification only). Gated: validate.sh/VALIDATE_SKIP_SLOW == 0
             refs; 'preview follows live' present (Usage §3); Overview live-preview
             language present."
    invariant: "README remains byte-for-byte unchanged unless a gate fails (none
               expected); the Maintenance section already defers release notes to
               the CHANGELOG"

CODE / TESTS / DATABASE / CONFIG / ROUTES: none.
```

## Validation Loop

### Level 1: Content self-check (primary gate — doc-only)

```bash
cd /home/dustin/.config/tmux/plugins/tmux-livepicker
# --- CHANGELOG: the ### Fixed subsection landed with all 5 entries ---
grep -c '^### Fixed' CHANGELOG.md                                              # -> 1
grep -c 'Critical —\|Major —\|Minor —\|Minor (docs) —' CHANGELOG.md            # -> 5
grep -cE 'test_window_confirm_preserves_custom_status_format|test_preview_follows_type_filter|test_preview_follows_backspace|test_renderer_escapes_hash_in_names|test_renderer_escapes_hash_in_filter|test_window_preview_shows_highlighted_window' CHANGELOG.md  # -> >= 5
# --- CHANGELOG: structural integrity (single Unreleased; ordering preserved) ---
grep -n '^## \[' CHANGELOG.md            # -> exactly one "## [Unreleased]" (no version/duplicate)
grep -n '^### ' CHANGELOG.md             # -> Added, Fixed, Documented corrections, Notes for maintainers (in order)
# --- README: consistency gates (must pass; README is NOT edited) ---
grep -c 'validate\.sh\|VALIDATE_SKIP_SLOW' README.md                          # -> 0
grep -n 'preview follows live' README.md                                      # -> Usage §3 present
grep -n 'all-panes preview of the highlighted candidate' README.md            # -> Overview present
# Expected: CHANGELOG has ### Fixed (1) with 5 severity-tagged bullets and >=5 test-name refs;
#           one Unreleased section; README gates all pass; no other file changed.
```

### Level 2: No-breakage suite run (optional — belt-and-braces)

```bash
cd /home/dustin/.config/tmux/plugins/tmux-livepicker
bash tests/run.sh
# Expected: 30/30 green (exit 0). CHANGELOG/README are NOT read by the tests, so
# this is purely a "nothing else regressed" sanity check. Takes ~2-3 min.
```

### Level 3: Cross-source accuracy check (the entries match the real fixes)

```bash
cd /home/dustin/.config/tmux/plugins/tmux-livepicker
# Each CHANGELOG claim should match the live code state (defensive: proves the
# entries aren't describing fixes that didn't actually land).
echo "Issue 1 (keep-window once): $(grep -c 'restore.sh" keep-window' scripts/input-handler.sh)"   # -> 1
echo "Issue 2 (sync helper):      $(grep -c '_lp_sync_preview_to_top_match' scripts/input-handler.sh)"  # -> 7
echo "Issue 3 (renderer escape):  $(grep -c 'esc_name\|esc_filter' scripts/renderer.sh)"            # -> 8
echo "Issue 4 (window-index):     $(grep -c 'w_sess\|w_idx' scripts/preview.sh)"                    # -> 7
echo "Issue 5 (no validate.sh):   $(grep -c 'validate\.sh\|VALIDATE_SKIP_SLOW' README.md)"          # -> 0
echo "Tests added (24 -> 30):     $(grep -rh '^[a-z_]*(*)\|^test_' tests/test_*.sh | grep -c '^test_')"  # -> 30
# Expected: all match the values baked into the CHANGELOG entries. If any differs,
# the CHANGELOG entry is inaccurate — reconcile the entry to the real state (do NOT
# change the code; the fixes are complete and verified).
```

### Level 4: Markdown render sanity (optional)

```bash
# Render CHANGELOG.md (any markdown viewer) and eyeball:
#   - the ### Fixed block sits between ### Added and ### Documented corrections;
#   - the 5 bullets render with their bold severity lead-ins and backticked code;
#   - no broken list nesting, no stray heading-level drift.
# No performance / security / load validation applies (prose edit).
```

## Final Validation Checklist

### Technical Validation

- [ ] `grep -c '^### Fixed' CHANGELOG.md` returns `1`.
- [ ] `grep -c 'Critical —\|Major —\|Minor —\|Minor (docs) —' CHANGELOG.md`
      returns `5`.
- [ ] The 6 regression-test names appear in the CHANGELOG (`grep -cE` → `≥ 5`).
- [ ] `grep -n '^## \[' CHANGELOG.md` shows exactly ONE `## [Unreleased]`.
- [ ] `grep -n '^### ' CHANGELOG.md` shows `Added, Fixed, Documented corrections,
      Notes for maintainers` in that order.
- [ ] (Optional) `bash tests/run.sh` exits 0 (30/30; no regression).

### Feature Validation

- [ ] All 5 issues documented (Issues 1–5), each with severity, summary, files,
      impact, and regression test(s).
- [ ] Each entry's facts match the live code (Level 3 cross-check).
- [ ] README consistency gates all pass (validate.sh=0; "preview follows live"
      present; Overview live-preview language present).
- [ ] No README edit was made (no inconsistency found).

### Code Quality Validation

- [ ] New entries match the existing CHANGELOG style (bullets, bold lead-ins,
      ~76–80 col wrap, backticked identifiers, cross-refs).
- [ ] Change confined to `CHANGELOG.md`; no other file modified.
- [ ] Existing CHANGELOG subsections (`### Added`, `### Documented corrections`,
      `### Notes for maintainers`) byte-for-byte preserved.
- [ ] No version header added; single `## [Unreleased]` section retained.

### Documentation & Deployment

- [ ] The CHANGELOG is now an accurate, self-contained record of the bugfix pass.
- [ ] Release-note-ready: a maintainer can lift the 5 bullets directly into a PR
      description or GitHub release notes.
- [ ] `PRD.md` was NOT edited (READ-ONLY); `tasks.json` / `prd_snapshot.md` untouched.

---

## Anti-Patterns to Avoid

- ❌ Don't add a `## [x.y.z] — date` version header or a second `## [Unreleased]`
  section — Keep a Changelog uses ONE Unreleased section; there is no tagged
  release. Add a `### Fixed` SUBSECTION to the existing section (research §1).
- ❌ Don't place `### Fixed` at EOF (after `### Notes for maintainers`) — it belongs
  between `### Added` and `### Documented corrections` for narrative order.
- ❌ Don't edit `README.md` unless a consistency grep gate FAILS — it is already
  consistent (verified live). The validate.sh removal is owned by P1.M2.T3.S1;
  README's Maintenance section already defers release notes to the CHANGELOG.
- ❌ Don't edit `PRD.md`, `prd_snapshot.md`, or any `prd_*` / `tasks.json` file —
  READ-ONLY / orchestrator-owned. The bugfix PRD is the SOURCE of issue facts, not
  an edit target.
- ❌ Don't copy the full repro / steps-to-reproduce from `bugfix_findings.md` into
  the CHANGELOG — each entry is a one-bullet SUMMARY (severity + summary + files +
  impact + test), not a bug report.
- ❌ Don't invent or rename regression tests — use the exact function names
  (`test_window_confirm_preserves_custom_status_format`, etc.). These are the real
  names in `tests/`.
- ❌ Don't modify any script or test file — all 5 fixes are COMPLETE. This is
  doc-only. If Level 3 reveals a fix didn't land, surface it to the orchestrator;
  do NOT re-implement the fix here.
- ❌ Don't claim a specific test count other than 24 → 30 (the verified delta:
  +6 regression tests across the 5 fixes).
- ❌ Don't rename the `## [Unreleased] — Initial implementation` subtitle — the
  `### Fixed` subsection conveys the bugfix pass; the subtitle stays.
- ❌ Don't reorder or rewrite the existing `### Added` / `### Documented
  corrections` / `### Notes for maintainers` blocks — only INSERT `### Fixed`.

---

## Confidence Score

**10 / 10** for one-pass success. Rationale: this is a single Markdown insertion in
one file, with the complete verbatim `### Fixed` block provided above (5 bullets,
each with verified severity / file / impact / test-name). Every load-bearing fact
is **live-verified** (research/changelog_readme_sync_findings.md): the CHANGELOG
format and the exact insertion anchor (`### Documented corrections`, unique); the
state of all 5 fixes (grep markers: keep-window=1, sync helper=7, renderer escape=8,
window-index branch=7, README validate.sh=0); the test-count delta (24→30, +6
regression tests); and the README consistency (all 3 gates currently pass → no
README edit needed). The grep self-checks (Validation Level 1) deterministically
prove the entries landed and the README is consistent. The task is fully disjoint
from the (complete) code fixes and the (parallel) README validate.sh edit. Residual
risk: an edit-tool `oldText` mismatch on the `### Documented corrections` anchor —
mitigated by the anchor being unique and the verbatim old→new instruction. There
is no logic, no test, and no integration surface to get wrong.
