# Research: CHANGELOG + README doc-sync for the adversarial QA bugfix pass (P1.M3.T1.S1)

> Documentation-only task (Mode B). No code, no tests. This file captures the
> exact CHANGELOG format/structure, the verified state of all 5 fixes, and the
> README consistency points — everything an implementer needs to write the 5
> CHANGELOG entries and verify the README in one pass.

## 1. CHANGELOG.md — current structure & format (verified live)

The file is **45 lines**, follows [Keep a Changelog](https://keepachangelog.com/).
Heading skeleton (exact, from `grep -n '^#\|^###' CHANGELOG.md`):

```
1: # Changelog
6: ## [Unreleased] — Initial implementation
8: ### Added
28: ### Documented corrections
36: ### Notes for maintainers
```

- There is a **single** `## [Unreleased]` section (no version number yet) with the
  subtitle "— Initial implementation". Keep a Changelog uses **one** Unreleased
  section that accumulates changes until a tagged release.
- Subsection categories present: `### Added` (the initial build), `### Documented
  corrections` (research-derived doc fixes, e.g. tmux floor 3.0→3.2), `### Notes
  for maintainers` (the PRD §0 manual-removal recommendation).
- **Keep a Changelog's standard category for bug fixes is `### Fixed`.** The file
  does NOT yet have a `### Fixed` subsection — this task adds it.
- Entry style: bullet list (`-`), bold lead-in (`**...**`), prose with PRD
  cross-refs (`(PRD §10.)`), hand-wrapped ~76–80 cols. Code identifiers are
  backticked (`` `status-format[n]` ``, `` `tests/run.sh` ``).

### Placement decision (FINDING: insert `### Fixed` between `### Added` and `### Documented corrections`)

Rationale: (a) Keep a Changelog keeps a single `[Unreleased]`; (b) the bugfixes
are part of the same unreleased version; (c) narrative order — *Added* (built it)
→ *Fixed* (QA'd it) → *Documented corrections* → *Notes* — reads naturally. The
`### Documented corrections` heading is a clean, unique insertion anchor.

### The insertion anchor (exact, verified)

The boundary between `### Added` and `### Documented corrections` is (CHANGELOG.md
~lines 24–28):

```
     is tmux's live-composed default (the user's normal window-status line). (PRD §10.)

### Documented corrections
```

`### Documented corrections` is **unique** in the file (appears once). The edit
prepends the `### Fixed` block immediately before it (and keeps the heading).

## 2. The 5 fixes — verified state & exact CHANGELOG facts (all COMPLETE)

Each fix's subtask PRP was read; file markers confirmed present via grep on the
live scripts (2026-07-06). Test count went **24 → 30** (+6 regression tests).

### Issue 1 — Critical (P1.M1.T1.S1, COMPLETE)
- **Files changed**: `scripts/input-handler.sh` (deleted the stray 5-tab duplicate
  `restore.sh keep-window` call at the old line 301; the 4-tab call at line 300 is
  the sole one now); `tests/test_restore.sh` (+1 test).
- **Verified marker**: `grep -c 'restore.sh" keep-window' scripts/input-handler.sh` → **1**.
- **Root cause**: the 2nd call ran after `clear_all_state` emptied saved state →
  `state_status_format_restore` did `set-option -gu status-format` then replayed an
  EMPTY index list → every custom `status-format[n]` wiped; also forced
  `status`/`renumber-windows`/`key-table` to defaults.
- **User-visible impact**: a window-mode confirm no longer destroys the user's
  custom status-bar configuration.
- **Regression test**: `test_window_confirm_preserves_custom_status_format`.

### Issue 2 — Major (P1.M1.T2.S1, COMPLETE)
- **Files changed**: `scripts/input-handler.sh` (new helper
  `_lp_sync_preview_to_top_match` + 3 call sites in type/backspace/cancel-clear;
  updated comments); `tests/test_functional.sh` (+2 tests).
- **Verified marker**: `grep -c '_lp_sync_preview_to_top_match' scripts/input-handler.sh` → **7**.
- **Root cause**: type/backspace/cancel-clear refreshed only the status-line
  highlight, never calling `preview.sh`; only next/prev did. PRD §3 vs §5
  contradiction; reconciled in favour of §3 / the README.
- **User-visible impact**: the live preview now tracks the highlighted candidate
  while typing/backspacing (the README's "preview follows live" promise is now true).
- **Regression tests**: `test_preview_follows_type_filter`, `test_preview_follows_backspace`.

### Issue 3 — Minor (P1.M2.T1.S1, COMPLETE)
- **Files changed**: `scripts/renderer.sh` (added `local esc_name`/`esc_filter`,
  substituted escaped forms at all 5 emission sites); `tests/test_functional.sh` (+2 tests).
- **Verified marker**: `grep -c 'esc_name\|esc_filter' scripts/renderer.sh` → **8**.
- **Root cause**: candidate names + filter query emitted raw into `#[...]` format
  strings → `#` re-interpreted (`#dev`→`<day>ev`) / style injection (`#[fg=red]x`).
- **User-visible impact**: session/window names containing `#` render literally;
  format-injection vector closed.
- **Regression tests**: `test_renderer_escapes_hash_in_names`, `test_renderer_escapes_hash_in_filter`.

### Issue 4 — Minor (P1.M2.T2.S1, COMPLETE)
- **Files changed**: `scripts/preview.sh` (window-index-aware branch: `w_sess`/`w_idx`
  parse the `session:index` token + resolve the specific `@id` by index; fixed the
  malformed `preview_fallback` capture-pane target); `tests/test_preview.sh` (+1 test).
- **Verified marker**: `grep -c 'w_sess\|w_idx' scripts/preview.sh` → **7**.
- **Root cause**: `#{window_active}` ignored the token's index → window-mode preview
  always showed the session's active window.
- **User-visible impact**: in window mode, previewing `session:5` now shows window 5.
- **Regression test**: `test_window_preview_shows_highlighted_window`.

### Issue 5 — Minor/docs (P1.M2.T3.S1, COMPLETE / parallel)
- **Files changed**: `README.md` (Validation section: removed the
  `VALIDATE_SKIP_SLOW=1`/`./validate.sh` clause; `;`→`.`).
- **Verified marker**: `grep -c 'validate\.sh\|VALIDATE_SKIP_SLOW' README.md` → **0**.
- **User-visible impact**: the README no longer points users at a non-existent file.
- **Regression test**: none (doc-only; grep is the gate).

## 3. README.md consistency — verification gates (FINDING: already consistent)

The contract (logic §3c) requires verifying the README is consistent with the 5
fixes and applying a minor touch only if needed. Verified live (2026-07-06):

| Point | README location | Current text | Status after fixes |
|---|---|---|---|
| validate.sh removed (Issue 5) | Validation § (~line 180) | `…sources the user config). The suites cover the PRD §15 clusters:` | ✅ consistent (0 refs) — **no edit needed** |
| "preview follows live" (Issue 2) | Usage §3 (line 128) | `…move the selection. The preview follows live.` | ✅ now TRUE (was false pre-Issue-2) — **no edit needed** |
| Overview live-preview language (Issue 2) | Overview (line 10) | `…shows a live, all-panes preview of the highlighted candidate.` | ✅ now accurate — **no edit needed** |
| Window-mode preview (Issue 4) | Overview/How-it-works | no specific violated claim | ✅ consistent — **no edit needed** |

**Conclusion**: the README is already consistent with all 5 fixes. The only README
edit in this changeset (validate.sh removal) is owned by the parallel P1.M2.T3.S1.
This task's README step is a **verification gate** (assert the 3 points hold); it
does NOT make further README edits unless an inconsistency is found (none exists).
The README Maintenance section already defers release notes to the CHANGELOG
("Release notes and the version bump live in the CHANGELOG"), so no README change
is needed to surface the changelog content.

## 4. Scope boundaries (what NOT to do)

- Do NOT edit `PRD.md` (READ-ONLY; agents forbidden). The bugfix PRD's findings
  are the source of truth for the 5 issues but the PRD itself is not touched.
- Do NOT add a `## [x.y.z] — date` version header — there is no tagged release;
  keep the single `## [Unreleased]` section (Keep a Changelog convention).
- Do NOT edit `tasks.json` / `prd_snapshot.md` (orchestrator-owned).
- Do NOT modify any script or test file — all 5 fixes are COMPLETE; this is doc-only.
- Do NOT duplicate the validate.sh fix in the README (P1.M2.T3.S1 owns it; verify only).
- Do NOT add a regression test for the CHANGELOG (doc-only; MOCKING: N/A).

## 5. Validation approach (doc-only)

Primary gate = grep self-checks:
- `grep -c '^### Fixed' CHANGELOG.md` → 1 (the new subsection exists).
- `grep -c 'Critical —\|Major —\|Minor —\|Minor (docs) —' CHANGELOG.md` → ≥5 (all 5 entries).
- `grep -c 'test_window_confirm_preserves\|test_preview_follows_type_filter\|test_preview_follows_backspace\|test_renderer_escapes_hash_in_names\|test_renderer_escapes_hash_in_filter\|test_window_preview_shows_highlighted_window' CHANGELOG.md` → ≥5 (regression-test names referenced).
- `grep -c 'validate\.sh\|VALIDATE_SKIP_SLOW' README.md` → 0 (Issue 5 still gone).
- `grep -n 'preview follows live' README.md` → present (Issue 2 promise now true).
Optional belt-and-braces: `bash tests/run.sh` (30/30) — README/CHANGELOG aren't read by tests, so this only confirms nothing else regressed.
