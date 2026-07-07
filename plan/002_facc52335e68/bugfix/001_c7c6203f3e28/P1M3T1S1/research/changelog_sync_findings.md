# Research: CHANGELOG.md sync for the rev 002 QA bugfix pass (P1.M3.T1.S1)

> Documentation-only task (Mode B). No code, no tests, no README edit (README
> verification is the sibling S2; Issue 6's README `### Known limitations` is the
> parallel P1.M2.T3.S1). This file captures the existing CHANGELOG format, the
> verified state of all 6 fixes, the exact regression-test names, and the
> insertion anchor — everything needed to write the 6 entries in one pass.

## 1. CHANGELOG.md — current structure & format (verified live, 100 lines)

Follows [Keep a Changelog](https://keepachangelog.com/). Heading skeleton:

```
6:  ## [Unreleased]: theme-matched tabs and deferred preview      <- rev 002 (TOP)
8:    ### Added                                                    (the 2 new options + notes)
15: ## [Unreleased] — Initial implementation                       <- original (below)
17:   ### Added                                                    (initial build + 3 invariants)
      ### Fixed                                                    (PRIOR round-1 bugfix, 5 entries)
      ### Documented corrections                                   (tmux floor 3.0→3.2)
      ### Notes for maintainers                                    (PRD §0 removal)
```

**There are TWO `## [Unreleased]` sections** (a pre-existing convention in this
file). The rev 002 section (top) has only `### Added`; the initial-implementation
section (below) has `### Added` / `### Fixed` (round 1) / corrections / notes.

### Placement decision — add `### Fixed` to the TOP (rev 002) section

These 6 fixes bugfix the rev 002 implementation (Issues 1/4 touch the deferred-
preview code in preview.sh; Issue 5 the §17 sentinel/tab code; 2/3 are general
preview/confirm). They belong with the rev 002 work. Adding `### Fixed` to the
top `## [Unreleased]: theme-matched tabs and deferred preview` section (after its
`### Added`, before the `## [Unreleased] — Initial implementation` heading) keeps
each Unreleased section self-contained: rev 002 = its features + its QA fixes;
initial = its features + its round-1 fixes + corrections + notes. The round-1
`### Fixed` (5 entries) stays byte-for-byte untouched.

### The insertion anchor (exact, verified)

The boundary between the rev 002 `### Added` and the initial `## [Unreleased]`:
- Line 13 (last rev 002 Added bullet): `…and \`preview-defer off\` is the synchronous escape hatch.`
- Line 15: `## [Unreleased] — Initial implementation`

`## [Unreleased] — Initial implementation` is **unique** in the file (the rev 002
header is `## [Unreleased]: theme-matched tabs and deferred preview` — different
suffix). Prepend the `### Fixed` block immediately before line 15.

### Entry style (mirror the existing round-1 `### Fixed` exactly)

- A short intro paragraph: pass name + the source findings reference + test count.
- `- ` bullets with a `**<Severity> — <title>.**` bold lead-in.
- Each bullet: the file(s) changed (backticked), the root cause (one phrase), the
  fix mechanism, the user-visible impact, and `Regression test: <name>` (or
  `tests:` for multiple). PRD cross-refs in parentheses. Hand-wrapped ~80 cols.

## 2. The 6 fixes — verified state & exact CHANGELOG facts (all LANDED)

Test count: **44** unique `test_*` functions (was 40 shipped; +4 this round).
Every fix confirmed present in the scripts via grep (2026-07-06).

### Issue 1 — Major (P1.M1.T1.S1 + S2, COMPLETE)
- **File**: `scripts/preview.sh` (dropped `link-window -a`; now bare `link-window -s "$src_id" -t "$current_session:"`).
- **Verified**: `grep -c 'link-window -a' scripts/preview.sh` → **0**; `grep -c 'link-window -s'` → **1**.
- **Root cause**: `-a` = "insert after active window" → preview inserted in the MIDDLE
  of the driver's list when active ≠ last → shifted every later index; `unlink-window`
  left the gap (renumber-windows on does NOT close gaps on unlink) → permanent reindex.
- **Impact**: violates PRD §9/§15 exact restoration on the DEFAULT code path (session
  mode, browse, cancel/confirm) for any user whose active window isn't last.
- **Regression tests**: `test_preview_preserves_window_indices_cancel`,
  `test_preview_preserves_window_indices_confirm` (new — assert `#{window_index}`
  ordering byte-equal before/after; existing `test_navigate_unlinks_intact` /
  `test_restore_cancel_layout_exact` asserted only on IDs, which is why it escaped).

### Issue 2 — Major (P1.M1.T2.S1 + S2, COMPLETE)
- **File**: `scripts/preview.sh` (self-session guard now extracts `${S%%:*}` for window mode).
- **Root cause**: guard was `[ "$S" = "$current_session" ]`; in window mode `$S` is a
  `session:index` token, never equal to the bare session name → guard never fired for
  the driver's own windows → `link-window` on a window already in the current session →
  tmux silently created a DUPLICATE link (rc=0) → polluted the list, shifted indices,
  sent later nav to the wrong window.
- **Impact**: window-mode preview/confirm of a driver-owned window corrupted the list.
- **Regression test**: `test_window_preview_driver_self_no_duplicate`.

### Issue 3 — Major (P1.M1.T3.S1 + S2, COMPLETE)
- **File**: `scripts/input-handler.sh` (confirm branch: replaced the `has-session -t "=$query"`
  gate with `new-session -P -F '#{session_name}'` name capture).
- **Verified**: `grep -c '\-P.*\-F\|new-session.*\-P' scripts/input-handler.sh` → **2**.
- **Root cause**: `.` is typeable; tmux silently sanitizes session names (`my.proj` →
  `my_proj`); `new-session` SUCCEEDED with the sanitized name, then `has-session -t "=$query"`
  with the ORIGINAL query FAILED → branch fell through to `restore.sh cancel` → the
  created session was orphaned and the user stranded on the original session, no feedback.
- **Impact**: phantom sessions + user stranded (violates PRD §6 "if creation fails, cancel").
- **Regression test**: `test_create_sanitized_name_lands_on_session`.

### Issue 4 — Minor (P1.M2.T1.S1, COMPLETE — defensive fix, NO new test)
- **File**: `scripts/preview.sh` (third `@livepicker-preview-seq` re-check immediately
  before `set_state "$STATE_LINKED_ID"` after `select-window` + idempotent pre-link probe).
- **Verified**: `grep -c 'expected_seq\|STATE_PREVIEW_SEQ\|idempotent' scripts/preview.sh` → **18**.
- **Root cause**: the supersede guard checked the seq at entry + before the unlink/link
  block, but between the 2nd check and the trailing `set_state LINKED_ID` there was a
  window of real tmux round-trips; if confirm/restore ran during it (unsetting the seq),
  a late job had passed its guard and proceeded to link → orphaned window. (Proven with
  an injected 0.4s delay, 5/5.)
- **Impact**: narrow TOCTOU race in the deferred-preview supersede guarantee (PRD §18/§16).
- **Regression test**: NONE dedicated (defensive hardening). Related coverage:
  `test_superseded_preview_noop`. Do NOT fabricate a test name.

### Issue 5 — Minor (P1.M2.T2.S1, COMPLETE)
- **Files**: `scripts/livepicker.sh` (sentinel now uses a STABLE session name as a 2nd
  placeholder) + `scripts/renderer.sh` (swaps BOTH the window-name and session-name
  placeholders in the window-status render path).
- **Verified**: sentinel session-name refs → livepicker.sh ×6, renderer.sh ×2.
- **Root cause**: the sentinel resolution expanded `#W` → `__lp_tab__` (swappable), but a
  theme's `#{session_name}` / `#S` expanded to the sentinel SESSION name (a unique
  `__lp_sent_<pid>_<ts>`, NOT swappable) → the single `__lp_tab__` swap missed it → every
  tab rendered the literal sentinel session name; the unexpanded-`#{` fallback didn't catch
  it (the specifier expanded fully).
- **Impact**: `@livepicker-tab-style window-status` broke for themes using session-state
  specifiers (PRD §17).
- **Regression test**: `test_sentinel_resolution_end_to_end` (+ the existing
  `test_window_status_*` / `test_empty_template_falls_back_to_plain` cluster).

### Issue 6 — Minor/docs (P1.M2.T3.S1, parallel — IN PROGRESS)
- **File**: `README.md` — new `### Known limitations` subsection at the end of
  `## How it works`, immediately before `## Compatibility`.
- **Content**: documents that linking a DETACHED candidate window for preview lets tmux's
  `window-size auto` resize the shared window object to the driver's size, and on unlink
  it shrinks to the no-client default (pane COUNT and window id intact; geometry changes);
  inherent to `link-window`; affects only detached candidates; `@livepicker-preview-mode
  snapshot` workaround.
- **Current state**: README has 0 refs (the parallel task is implementing it now — assume
  it lands as specified). My CHANGELOG entry for Issue 6 DOCUMENTS that README change; I do
  NOT edit README (that's P1.M2.T3.S1 + the sibling P1.M3.T1.S2).
- **Regression test**: none (docs).

## 3. Scope boundaries (what NOT to do)

- Do NOT edit `README.md` — Issue 6's `### Known limitations` is owned by the parallel
  P1.M2.T3.S1; README feature/behavior verification is the sibling P1.M3.T1.S2. This task
  is CHANGELOG-only.
- Do NOT edit `PRD.md` / `tasks.json` / `prd_snapshot.md` (READ-ONLY / orchestrator-owned).
- Do NOT add a versioned `## [x.y.z]` header or a third `## [Unreleased]` section — add a
  `### Fixed` SUBSECTION to the existing top (rev 002) Unreleased section.
- Do NOT touch the round-1 `### Fixed` (5 entries under the initial-implementation section)
  or any other existing CHANGELOG content — only INSERT the new `### Fixed` block.
- Do NOT modify any script or test file — all 6 fixes are COMPLETE; this is doc-only.
- Do NOT invent a regression-test name for Issue 4 (it has none; reference the existing
  `test_superseded_preview_noop` as related coverage).

## 4. Validation approach (doc-only)

Primary gate = grep self-checks:
- `grep -c '^### Fixed' CHANGELOG.md` → 2 (the round-1 block + the new rev 002 block).
- `grep -c 'Major —\|Minor —\|Minor (docs) —' CHANGELOG.md` → ≥ 11 (5 round-1 + 6 new).
- The 6 new test names / the rev 002 intro appear in the new block.
- The round-1 `### Fixed` block is byte-identical (diff the region below the new block).
- `grep -c '^## \[Unreleased\]' CHANGELOG.md` → 2 (no third section added).
