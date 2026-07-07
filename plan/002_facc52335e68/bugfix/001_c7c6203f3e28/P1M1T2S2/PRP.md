# PRP — Bugfix P1.M1.T2.S2: Add window-mode driver-owned-window preview test

> **Context**: Issue 2 from the rev-002 QA pass
> (`plan/002_facc52335e68/bugfix/001_c7c6203f3e28/architecture/issue1_2_findings.md` §Issue 2,
> Major). The shipped window-mode tests (`test_window_preview_shows_highlighted_window`) only
> preview windows in OTHER sessions (`multi`). **None** preview a window that lives in the
> DRIVER session — the exact case the S1 fix (P1.M1.T2.S1) protects. This PRP adds ONE test
> that closes that coverage gap and makes the S1 fix durable (it FAILS if the guard regresses
> to the bare `[ "$S" = "$current_session" ]` comparison).
>
> **Test-only**: no production code changes. Appends one `test_*` function to `tests/test_preview.sh`.

---

## Goal

**Feature Goal**: A committed regression test (`test_window_preview_driver_self_no_duplicate`)
that calls `preview.sh` on a **driver-owned** window in **window mode** (a `"session:index"`
token) and asserts (1) no link is attempted (`@livepicker-linked-id` empty), (2) the driver's
window list has NO duplicate `@id` entries (count + uniqueness invariant), and (3) the correct
highlighted window is selected. This codifies the window-mode self-session behavior so the
Issue 2 regression cannot be reintroduced silently.

**Deliverable**: ONE new function appended to `tests/test_preview.sh` — `test_window_preview_driver_self_no_duplicate`.
No other files change.

**Success Definition**:
- The new test PASSES against the FIXED `preview.sh` (S1 applied): `@livepicker-linked-id`
  empty, the driver's window-id list / count / uniqueness unchanged, and the target window
  is active. (PROVEN: research `test_window_preview_driver_self_findings.md` FINDING 1 — pass=5 fail=0.)
- The new test FAILS against the buggy behavior (guard reverted to bare `$S` comparison →
  duplicate link created): the three "no duplicate" assertions fire. (PROVEN: FINDING 2 — pass=0 fail=3.)
- The full `tests/run.sh` suite stays green (the new test is additive; `run.sh` auto-discovers it).
- `shellcheck` on the edited file reports 0 NEW findings (the new code reuses documented
  patterns + `set -u`-safe locals).

## User Persona (if applicable)

**Target User**: The maintainer (regression safety net). Not directly end-facing — it is a
test that locks in the S1 fix.

**Use Case**: A future change to `preview.sh`'s self-session guard regresses Issue 2 (e.g.
restores the bare `[ "$S" = "$current_session" ]` comparison). This test fails in CI before
the regression ships.

**Pain Points Addressed**: The shipped suite has ZERO coverage for "preview a driver-owned
window in window mode" — exactly the path Issue 2 corrupts. Without this test, the S1 fix is
unguarded and can regress undetected (the findings doc §Test Coverage Gaps calls this out).

---

## Why

- **Closes the documented test gap.** `issue1_2_findings.md` §"ISSUE 2 Gaps" states verbatim:
  "`test_self_session_no_link` only tests session mode. No test calls `preview.sh "driver:N"`.
  ISSUE 2 is invisible to every existing test." This test makes Issue 2 visible.
- **Guards the S1 fix (P1.M1.T2.S1), which lands in parallel.** S1 extends the self-session
  guard to window mode via `${S%%:*}` extraction + a mode-branched `select-window`. This test
  is its regression net — it passes today (S1 applied) and fails the moment the guard regresses.
- **One function, zero production risk.** Pure test addition; `run.sh` auto-discovers
  `test_*` via `compgen -A function | grep '^test_'`, so no registration/wiring is needed.

## What

Append `test_window_preview_driver_self_no_duplicate` to `tests/test_preview.sh`. It:
1. Calls `lp_preview_seed_state` (the existing helper — sets `@livepicker-orig-session`,
   `@livepicker-orig-window` = the driver's active window id, `@livepicker-linked-id=""`).
2. Sets `@livepicker-type window` (the mode the guard's window-mode branch gates on;
   `lp_preview_seed_state` does NOT set type).
3. Dynamically detects the driver's NON-active window index + `@id` (base-index-agnostic;
   the baseline driver's `@id`s are NON-sequential — `@0` and `@3` — so detection is mandatory).
4. Calls `"$LIVEPICKER_SCRIPTS/preview.sh" "$TEST_DRIVER_SESSION:$target_idx"`.
5. Asserts the 3 contract invariants (linked-id empty / no duplicate @id / correct window selected).

### Success Criteria

- [ ] `test_window_preview_driver_self_no_duplicate` is the LAST function in `tests/test_preview.sh`.
- [ ] It sets `@livepicker-type window` (not relying on `lp_preview_seed_state` for type).
- [ ] It detects the target window/index DYNAMICALLY (no hard-coded index or `@id`).
- [ ] It asserts `@livepicker-linked-id` is empty after the preview.
- [ ] It asserts no duplicate `@id` via 3 complementary checks (list byte-equality, count, `uniq -d`).
- [ ] It asserts the active window after preview equals the target window's `@id`.
- [ ] `bash tests/run.sh` is green; the new test auto-discovered and PASSes.

## All Needed Context

### Context Completeness Check

_Pass_: The implementer needs (a) the verbatim function to append (in Implementation Patterns),
(b) the file's header CONTRACT (sourced by run.sh; no setup_test/teardown_test; `set -u` inherited;
signal failure ONLY via `fail`/`assert_*`; never `exit`), (c) the empirical proof it passes on the
fixed build and fails on the bug, and (d) the two sibling tests to mirror. All are supplied below.

### Documentation & References

```yaml
# MUST READ — the empirical ground-truth (PROVES the test passes on the fix + catches the bug)
- docfile: plan/002_facc52335e68/bugfix/001_c7c6203f3e28/P1M1T2S2/research/test_window_preview_driver_self_findings.md
  why: PROVES the test end-to-end on the isolated harness. FINDING 1 (pass=5 fail=0 on the FIXED
       preview.sh); FINDING 2 (pass=0 fail=3 on the BUG simulation — the assertions are load-bearing);
       FINDING 3 (no client needed); FINDING 4 (dynamic detection is mandatory — @ids are @0/@3,
       non-sequential); FINDING 5 (the 3 no-duplicate checks are complementary). Includes the
       VERBATIM function to append.
  critical: Read BEFORE editing. The driver's window ids are @0 and @3 (NOT @0/@1) — hard-coding
            an @id would be wrong. base-index=1 -> original window is at index 1.

# MUST READ — the file being modified (APPEND one function)
- file: tests/test_preview.sh
  why: The header CONTRACT block (sourced by run.sh; no side effects on source; `set -u` inherited;
        signal failure ONLY via fail/assert_* — NEVER exit). The lp_preview_seed_state helper (the
        minimal @livepicker-* state preview.sh reads). The two tests to MIRROR:
        test_self_session_no_link (session-mode self-session counterpart — same 3-assertion shape:
        linked-id empty / window-id list unchanged / correct window selected) and
        test_window_preview_shows_highlighted_window (dynamic index+id detection via
        list-windows | awk '$3==0' — copy this idiom; loud-fail sanity guard).
  pattern: assert_eq/assert_contains/fail from tests/helpers.sh; dynamic window capture via
           `list-windows -t "=$SESS" -F '#{window_index} #{window_id} #{window_active}' | awk`.
  gotcha: the file is SOURCED (no shebang execution); it defines functions ONLY. Do NOT add a
          setup_test/teardown_test (run.sh owns the cycle). The new function must be named
          exactly `test_...` (underscore-separated) to be discovered.

# MUST READ — the bug this test guards (root cause + the gap it fills)
- docfile: plan/002_facc52335e68/bugfix/001_c7c6203f3e28/architecture/issue1_2_findings.md
  why: §ISSUE 2 gives the root cause (the bare `[ "$S" = "$current_session" ]` comparison never
       matches a "driver:N" token) + the duplicate-creation mechanism (link-window rc=0 on
       already-linked windows). §"ISSUE 2 Gaps" documents the EXACT missing test this PRP adds.
  section: "ISSUE 2" + "Test Coverage Gaps" (ISSUE 2 Gaps row).

# MUST READ — the fix under test (the S1 PRP, landing in parallel — treat as a CONTRACT)
- docfile: plan/002_facc52335e68/bugfix/001_c7c6203f3e28/P1M1T2S1/PRP.md
  why: Defines what preview.sh will do for driver-owned windows in window mode: the self-session
       guard extracts `${S%%:*}` (the token's session), compares to current_session, and when it
       fires selects the SPECIFIC window (`select-window -t "$S"`) WITHOUT linking. This test
       validates exactly that behavior. Read the "Goal" + "What" + "Known Gotchas" sections.
  critical: S1 is the code fix; THIS PRP (S2) is its test. Do NOT modify preview.sh here.

# Reference — the assertion helpers + the per-test socket cycle contract
- docfile: tests/helpers.sh
  why: The COMPLETE public assertion API: fail/pass/assert_eq/assert_contains + setup_test/
       teardown_test (thin delegates to setup_socket). assert_eq(a,b,msg) is POSIX equality
       (handles multi-line strings); assert_contains(str,sub,msg) is literal substring. No
       assert_not_contains/assert_match — write inline `case`+fail if ever needed.
  section: (the whole file is short; the table in test_harness.md §3 summarizes signatures)

# Reference — the harness map (header contract, discovery, fixture model)
- docfile: plan/002_facc52335e68/architecture/test_harness.md
  why: §2 (run.sh discovery via `compgen -A function | grep '^test_'` — the new function is
       auto-registered); §3 (assertion signatures); §4 (the structural template +
       lp_preview_seed_state; "Best general-purpose structural template: test_preview.sh").
  section: §2, §3, §4 (Start Here).

# Reference — PRD §7 (the self-session rule this test enforces)
- docfile: PRD.md
  why: §7 "When the highlighted session is the current session, do not link ... Select the
       original window" — the rule the guard implements (extended to window mode by S1).
  section: "§7 The preview subsystem" (Self-session edge case)
```

### Current Codebase tree (run `ls scripts/ tests/` in the repo root)

```bash
tmux-livepicker/
  scripts/
    preview.sh      # UNCHANGED (S1 already applied: check_session + window-mode self-session guard).
                    #   This PRP does NOT touch it.
  tests/
    run.sh          # UNCHANGED (auto-discovers test_* — the new function is picked up for free).
    setup_socket.sh # UNCHANGED (baseline fixtures: driver has original + 'extra' windows).
    helpers.sh      # UNCHANGED (fail/pass/assert_eq/assert_contains + setup_test/teardown_test).
    test_preview.sh # MODIFY: APPEND test_window_preview_driver_self_no_duplicate as the LAST function.
```

### Desired Codebase tree with files to be added and responsibility of file

```bash
tests/test_preview.sh   # +test_window_preview_driver_self_no_duplicate (the LAST function):
                         #   window-mode preview of a DRIVER-OWNED window -> no link, no duplicate
                         #   @id, correct window selected. Regression net for Issue 2 / S1.
```

### Known Gotchas of our codebase & Library Quirks

```bash
# CRITICAL — detect the target window DYNAMICALLY; do NOT hard-code an index or @id. The
# baseline driver's two windows are @0 (original, NON-active) and @3 (extra, ACTIVE) — the
# @ids are NON-sequential because alpha/beta + their splits consume ids in between. base-index
# is inherited from ~/.tmux.conf (1 here; could be 0 elsewhere). Use the EXACT idiom from
# test_window_preview_shows_highlighted_window:
#   target="$(tmux list-windows -t "=$TEST_DRIVER_SESSION" -F '#{window_index} #{window_id} #{window_active}' | awk '$3==0 {print $1" "$2; exit}')"
#   target_idx="${target%% *}";  target_id="${target#* }"
# (research FINDING 4.)

# CRITICAL — pick the NON-active window as the target. This makes the "correct window selected"
# assertion MEANINGFUL: the active window CHANGES from extra(@3) to the target(@0), proving
# select-window -t "$S" fired. If you picked the already-active window, the assertion would
# pass trivially and not prove the guard's select branch ran. (research FINDING 4.)

# CRITICAL — set @livepicker-type window EXPLICITLY. lp_preview_seed_state sets orig-session /
# orig-window / linked-id but does NOT set type. The self-session guard's window-mode branch
# gates on `[ "$(opt_type)" = "window" ]` — without this, opt_type defaults to "session" and the
# guard's window-mode branch never runs (the test would exercise the session-mode path). Mirror
# test_window_preview_shows_highlighted_window, which also sets type explicitly.

# CRITICAL — preview.sh is CLIENT-INDEPENDENT (reads current_session from @livepicker-orig-session,
# NOT display-message). So lp_preview_seed_state suffices — NO attach_test_client. Confirmed:
# the validation smoke ran with no attached client. (research FINDING 3.) Do NOT add
# attach_test_client (it would be dead weight + slow the suite).

# CRITICAL — signal failure ONLY via fail()/assert_*(). NEVER `exit`, NEVER `return` nonzero to
# abort (run.sh reads TEST_STATUS in the CURRENT shell; a bare exit kills the runner). An early
# `return 0` to skip the rest of a body after a fail() is acceptable (used by the sibling test).

# GOTCHA — `set -u` is INHERITED (from helpers.sh via run.sh). Do NOT re-declare it. Declare
# EVERY function-local with `local` (the awk-parsed target, before_ids, before_n, after_n, dups).
# `${target%% *}` and `${target#* }` are safe under set -u AFTER the `local target=...` assignment.

# GOTCHA — `wc -l` emits leading whitespace (e.g. "      2"); pipe through `tr -d '[:space:]'`
# before assert_eq (a bare string compare would otherwise fail on "  2" vs "2"). Both before_n
# and after_n must be normalized identically. (research FINDING 1 uses this exact form.)

# GOTCHA — the `sort | uniq -d` uniqueness check: `uniq` requires SORTED input to detect
# duplicates across non-adjacent lines, so `sort` MUST come first. `uniq -d` prints ONLY lines
# that appear more than once; empty output == all ids unique. assert_eq "$dups" "" "" asserts that.

# GOTCHA — Indent with TABS (the file is tab-indented; shfmt is NOT installed). The function
# body is 1-tab; nested blocks (the `if [ -z ... ]` sanity guard, the assertion comments) are
# 2-tab. Match the surrounding functions EXACTLY (open test_preview.sh and copy the indent).

# GOTCHA — the function name MUST be `test_window_preview_driver_self_no_duplicate` (the work-item
# contract name; the S1 PRP referenced it loosely as `test_window_mode_self_session_no_link` —
# use the CONTRACT name). It is discovered by run.sh's `compgen -A function | grep '^test_' | sort`,
# so lexical sort places it LAST among the preview tests (after test_window_preview_shows_*).

# GOTCHA — do NOT add a second function. The contract specifies ONE test_* function. The 3
# "no duplicate" checks all live inside it (they are complementary belt-and-braces, research
# FINDING 5 — not separate tests).
```

## Implementation Blueprint

### Data models and structure

No data model. The "structure" is the assertion flow, mirroring `test_self_session_no_link`:

```
test_window_preview_driver_self_no_duplicate():
  lp_preview_seed_state()                       # orig-session/orig-window/linked-id=""
  set @livepicker-type window                   # gate the guard's window-mode branch
  detect target = driver's NON-active window (index + @id) dynamically
  sanity: target_id contains "@"; else fail + return 0
  snapshot before_ids, before_n
  preview.sh "$TEST_DRIVER_SESSION:$target_idx"
  assert linked-id == ""                         # (1) no link attempted
  assert after_ids == before_ids                 # (2a) list byte-identical
  assert after_n   == before_n                   # (2b) count unchanged
  assert uniq -d   == ""                         # (2c) all ids unique
  assert active_id == target_id                  # (3) correct window selected
```

### Implementation Tasks (ordered by dependencies)

```yaml
PRECONDITION: S1 (P1.M1.T2.S1) is applied to scripts/preview.sh. Verify the guard is the
  window-mode-aware form (NOT the bare comparison):
    grep -q 'check_session' scripts/preview.sh && echo "OK: S1 applied" || echo "FAIL: S1 missing"
    grep -q '\[ "\$S" = "\$current_session" \]' scripts/preview.sh && echo "FAIL: bare guard (bug present)" || echo "OK: guard fixed"
  (S1 is Complete; preview.sh currently has `check_session` + the ${S%%:*} extraction.)

Task 1: MODIFY tests/test_preview.sh — APPEND the new function as the LAST function
  - LOCATE: the file currently ENDS with test_window_preview_shows_highlighted_window's
    closing block (the belt-and-braces `if [ "$(tmux show-option ... linked-id)" = "$active_id" ];
    then fail ...; fi` then the final `}`).
  - ACTION: append `test_window_preview_driver_self_no_duplicate` AFTER that closing `}`.
  - oldText/newText: see Implementation Patterns (anchor on the unique trailing block).
  - DO NOT: touch any other function, the header CONTRACT comment, or any other file.
  - DO NOT: add setup_test/teardown_test (run.sh owns the cycle) or re-declare `set -u`.

Task 2: VALIDATE (syntax + targeted smoke + full suite + load-bearing proof)
  - RUN: `bash -n tests/test_preview.sh` (expect OK); `shellcheck tests/test_preview.sh`
    (expect 0 NEW findings — SC2154/SC2016/SC2034/SC2086 are the file's pre-existing silenced
     directives in the header; the new function inherits them).
  - RUN: `bash tests/run.sh` (expect the new test PASS + the rest green; count rises by 1).
  - RUN (load-bearing proof): temporarily revert preview.sh's guard to the bare comparison
    (`check_session="$S"` unconditionally, or `[ "$S" = "$current_session" ]`), re-run JUST
    the new test, confirm it FAILS (the 3 no-duplicate assertions fire), then RESTORE preview.sh
    and confirm green again. See Validation Level 3.
```

### Implementation Patterns & Key Details

**The edit — APPEND after the file's last function.** The file currently ends with:

```bash
# oldText (the LAST function's tail — unique anchor; replace with itself + the new function):
	# Belt-and-braces: prove it is NOT the active window's id.
	if [ "$(tmux show-option -gqv @livepicker-linked-id)" = "$active_id" ]; then
		fail "window-mode preview linked the ACTIVE window (the bug)"
	fi
}
# newText (same tail + the appended function):
	# Belt-and-braces: prove it is NOT the active window's id.
	if [ "$(tmux show-option -gqv @livepicker-linked-id)" = "$active_id" ]; then
		fail "window-mode preview linked the ACTIVE window (the bug)"
	fi
}

# test_window_preview_driver_self_no_duplicate — Bugfix Issue 2 (window mode):
# previewing a window that LIVES in the driver (current) session must NOT link it
# (a session cannot usefully link its own window into itself — link-window would
# silently create a DUPLICATE, rc=0). The self-session guard must fire for the
# "session:index" token, select the target window, and leave the driver's window
# list byte-identical (no duplicate @id). This is the window-mode counterpart of
# test_self_session_no_link (session mode). Before S1/P1.M1.T2.S1, the guard's
# bare `[ "$S" = "$current_session" ]` never matched the "driver:N" token, so
# preview fell through to link-window and polluted the list — this test catches
# that regression. Mirrors the dynamic-index detection of
# test_window_preview_shows_highlighted_window (base-index may be 0 or 1;
# @ids are non-sequential — @0 and @3 here — so detect dynamically).
test_window_preview_driver_self_no_duplicate() {
	lp_preview_seed_state
	# Window mode: the self-session guard's window-mode branch gates on opt_type
	# (lp_preview_seed_state does NOT set type — set it explicitly).
	tmux set-option -g @livepicker-type window
	# Pick a DRIVER-OWNED window token. The baseline driver has ≥2 windows
	# (original + 'extra'); detect the NON-active one dynamically so the
	# "correct window selected" assertion is meaningful (selection changes) and
	# base-index-agnostic (the index comes straight from list-windows). @ids are
	# clean @N, so space-delimit to avoid any ':' ambiguity.
	local target target_idx target_id before_ids before_n
	target="$(tmux list-windows -t "=$TEST_DRIVER_SESSION" -F '#{window_index} #{window_id} #{window_active}' | awk '$3==0 {print $1" "$2; exit}')"
	target_idx="${target%% *}"
	target_id="${target#* }"
	assert_contains "$target_id" "@" "non-active driver window resolved to a @id handle"
	if [ -z "$target_idx" ] || [ -z "$target_id" ]; then
		fail "test setup invalid: no non-active driver window (need ≥2 driver windows)"
		return 0
	fi
	# Snapshot the driver's window list BEFORE (ids + count).
	before_ids="$(tmux list-windows -t "=$TEST_DRIVER_SESSION" -F '#{window_id}')"
	before_n="$(tmux list-windows -t "=$TEST_DRIVER_SESSION" -F '#{window_id}' | wc -l | tr -d '[:space:]')"
	# Preview the DRIVER's own window (window-mode token). The self-session guard
	# must fire (check_session = ${S%%:*} = "driver" = current_session) -> select
	# the target, NO link, NO duplicate.
	"$LIVEPICKER_SCRIPTS/preview.sh" "$TEST_DRIVER_SESSION:$target_idx"
	# (1) PRD §7 self-session: NO link attempted -> @livepicker-linked-id is EMPTY.
	assert_eq "$(tmux show-option -gqv @livepicker-linked-id)" "" \
		"window-mode self-session leaves @livepicker-linked-id empty (no link)"
	# (2) NO duplicate @id: the window-id list is unchanged (catches ANY change),
	#     the count is unchanged, AND every id is unique (sort | uniq -d empty).
	assert_eq "$(tmux list-windows -t "=$TEST_DRIVER_SESSION" -F '#{window_id}')" "$before_ids" \
		"window-mode self-session created no duplicate (window-id list unchanged)"
	local after_n dups
	after_n="$(tmux list-windows -t "=$TEST_DRIVER_SESSION" -F '#{window_id}' | wc -l | tr -d '[:space:]')"
	assert_eq "$after_n" "$before_n" "driver window count unchanged (no duplicate link added)"
	dups="$(tmux list-windows -t "=$TEST_DRIVER_SESSION" -F '#{window_id}' | sort | uniq -d)"
	assert_eq "$dups" "" "no duplicate @id entries in the driver window list"
	# (3) PRD §7: the CORRECT window was selected (active == the token's window),
	#     not a duplicate occupying a shifted index.
	assert_eq "$(tmux list-windows -t "=$TEST_DRIVER_SESSION" -F '#{window_id}' -f '#{window_active}')" "$target_id" \
		"window-mode self-session selects the highlighted (token's) window, not a duplicate"
}
```

Key pattern notes:
- The function is a direct mirror of `test_self_session_no_link` (same 3-assertion shape:
  linked-id empty / window-id list unchanged / correct window selected) PLUS the explicit
  count + `uniq -d` uniqueness checks the contract asks for, PLUS dynamic target detection
  copied from `test_window_preview_shows_highlighted_window`.
- `target` is space-delimited (`"idx id"`); `${target%% *}` = idx, `${target#* }` = id — avoids
  any `:` ambiguity (the sibling test uses the same split). `@ids` are clean `@N`.
- The sanity guard (`[ -z "$target_idx" ] || [ -z "$target_id" ]`) fails LOUDLY on a bad
  baseline (mirrors the sibling's `na_id == active_id` guard) — better than a vacuous pass.
- `wc -l | tr -d '[:space:]'` normalizes the count for the string-compare assert.
- All assertions are quiet on success; `fail()` (via assert_eq) sets `TEST_STATUS` on mismatch.
  No `exit`, no nonzero `return` (except the `return 0` skip-after-fail, which is documented-safe).

### Integration Points

```yaml
TESTS:
  - file: tests/test_preview.sh
    change: "+test_window_preview_driver_self_no_duplicate (appended as the LAST function)"
    discovery: "run.sh: compgen -A function | grep '^test_' | sort -> auto-registered, no wiring"
    invariant: "PASS on the fixed preview.sh; FAILS if the guard regresses to bare $S comparison"

CODE: none (preview.sh is owned by S1; do NOT modify it here).
DATABASE / CONFIG / ROUTES: none.
```

## Validation Loop

### Level 1: Syntax & Style (Immediate Feedback)

```bash
cd /home/dustin/.config/tmux/plugins/tmux-livepicker
bash -n tests/test_preview.sh && echo "OK: test_preview syntax"
shellcheck tests/test_preview.sh          # expect 0 NEW findings (SC2154/SC2016/SC2034/SC2086
                                          #   are the file's pre-existing silenced header directives)
# the new function is present + named correctly + is the LAST function:
grep -q '^test_window_preview_driver_self_no_duplicate()' tests/test_preview.sh \
  && echo "OK: function present" || echo "FAIL: function missing"
# dynamic detection (NOT a hard-coded index/@id) is present:
grep -q 'awk .\$3==0' tests/test_preview.sh && echo "OK: dynamic target detection" || echo "FAIL: no dynamic detection"
# type is set explicitly:
grep -q '@livepicker-type window' tests/test_preview.sh && echo "OK: type set" || echo "FAIL: type not set"
# Tabs-not-spaces in the new region:
grep -nP '^    [^#/]' tests/test_preview.sh | tail -20 && echo "WARN: space-indent" || echo "OK: tabs"
# PRECONDITION — S1 applied (the guard this test exercises):
grep -q 'check_session' scripts/preview.sh && echo "OK: S1 applied" || echo "FAIL: S1 missing"
```

### Level 2: Full suite (the new test auto-discovered + green)

```bash
cd /home/dustin/.config/tmux/plugins/tmux-livepicker
bash tests/run.sh
# Expected: the suite count rises by exactly 1 (the new test) and ALL tests PASS,
# including "PASS  test_window_preview_driver_self_no_duplicate". The new test runs
# against a FRESH isolated socket (run.sh's per-test setup_test "lp-$$-...").
# If the new test FAILS, READ its ASSERT FAIL line — the most likely cause is S1 not
# actually being applied (re-check the PRECONDITION grep in Level 1).
```

### Level 3: Load-bearing proof (the test MUST fail when the bug is present — do not skip)

Temporarily regress preview.sh's guard to the bare comparison; the new test's three
"no duplicate" assertions MUST fail. Restore preview.sh and confirm green. This proves
the test is not vacuous — it catches the Issue 2 regression.

```bash
cd /home/dustin/.config/tmux/plugins/tmux-livepicker
cp scripts/preview.sh /tmp/preview.t2s2.bak
# Re-introduce the bug: force check_session="$S" (the bare comparison) so the guard
# never matches a "driver:N" token -> falls through to link-window -> DUPLICATE.
perl -0pi -e 's/\tcheck_session="\$S"\n\tif \[ "\$\(opt_type\)" = "window" \] && \[ "\$\{S%%:\*\}" != "\$S" \]; then\n\t\tcheck_session="\$\{S%%:\*\}"\n\tfi/\tcheck_session="$S"  # BUG: no token extraction (Issue 2)/' scripts/preview.sh
grep -q 'BUG: no token extraction' scripts/preview.sh && echo "bug re-introduced" || echo "FAIL: could not regress"
# Run JUST the new test (run.sh has no filter; run the suite and grep the one line):
bash tests/run.sh 2>&1 | grep -E 'test_window_preview_driver_self_no_duplicate|passed,'
# Expected: "FAIL  test_window_preview_driver_self_no_duplicate" (the 3 no-duplicate
#   assertions fire; research FINDING 2). The OTHER tests stay PASS.
# Restore the fix:
cp /tmp/preview.t2s2.bak scripts/preview.sh
rm -f /tmp/preview.t2s2.bak
grep -q 'BUG: no token extraction' scripts/preview.sh && echo "FAIL: bug not restored" || echo "OK: fix restored"
bash tests/run.sh 2>&1 | grep -E 'test_window_preview_driver_self_no_duplicate|passed,'
# Expected: "PASS  test_window_preview_driver_self_no_duplicate" + "N passed, 0 failed".
```

### Level 4: Creative & Domain-Specific Validation

```bash
# (Optional) Direct harness smoke mirroring run.sh's per-test cycle, isolating the new
# test from the full suite (useful if the suite is slow and you want a tight loop). This
# is EXACTLY the validation that produced research FINDING 1/2:
cd /home/dustin/.config/tmux/plugins/tmux-livepicker
cat > /tmp/lp_t2s2_isolated.sh <<'SMOKE'
#!/usr/bin/env bash
set -u
cd /home/dustin/.config/tmux/plugins/tmux-livepicker
source tests/setup_socket.sh
source tests/helpers.sh
source tests/test_preview.sh           # defines lp_preview_seed_state + the new test_*
setup_test "lp-t2s2-iso"
TEST_STATUS="pass"
test_window_preview_driver_self_no_duplicate
echo "RESULT: $TEST_STATUS"
teardown_test
[ "$TEST_STATUS" = "pass" ]
SMOKE
bash /tmp/lp_t2s2_isolated.sh; rc=$?; rm -f /tmp/lp_t2s2_isolated.sh
echo "isolated smoke exit=$rc"   # Expected: RESULT: pass, exit 0
# Expected: RESULT: pass, exit 0.
```

## Final Validation Checklist

### Technical Validation

- [ ] `bash -n tests/test_preview.sh` clean; `shellcheck` 0 NEW findings.
- [ ] `test_window_preview_driver_self_no_duplicate` is appended as the LAST function.
- [ ] Dynamic target detection present (no hard-coded index/@id); `@livepicker-type window` set.
- [ ] L2 full suite: green; the new test PASSes; count rises by exactly 1.
- [ ] L3 load-bearing: regressing preview.sh's guard to bare `$S` makes the new test FAIL;
      restoring makes it PASS again.

### Feature Validation

- [ ] The 3 contract assertions are all present: linked-id empty / no duplicate @id (list +
      count + uniq -d) / correct window selected (active == target id).
- [ ] The test needs NO attached client (preview.sh is client-independent).
- [ ] The test is base-index-agnostic (passes whether base-index is 0 or 1).

### Code Quality Validation

- [ ] Mirrors `test_self_session_no_link` (3-assertion shape) + `test_window_preview_shows_highlighted_window` (dynamic detection idiom).
- [ ] `set -u`-safe: every local declared; `wc -l` output whitespace-normalized.
- [ ] Tab indent; `fail`/`assert_*` only (no `exit`, no nonzero `return` to abort).
- [ ] No production code touched (preview.sh belongs to S1).

### Documentation & Deployment

- [ ] The function's header comment documents: what it tests (Issue 2), the window-mode
      counterpart relationship, why dynamic detection is used (@ids non-sequential), and the
      S1 regression it guards.
- [ ] Doc sync (CHANGELOG/README) is NOT this task's scope (test-only; P1.M3.T1 owns docs).

---

## Anti-Patterns to Avoid

- ❌ Don't hard-code the target index (`:1`) or `@id` (`@0`). base-index is inherited (1 here,
  could be 0) and the driver's @ids are non-sequential (`@0`, `@3`). Detect dynamically via
  `list-windows | awk '$3==0'` (the sibling test's idiom).
- ❌ Don't pick the already-ACTIVE window as the target. The "correct window selected" assertion
  must observe a selection CHANGE (active extra→target) to prove `select-window -t "$S"` fired.
  Pick the NON-active window.
- ❌ Don't omit `tmux set-option -g @livepicker-type window`. `lp_preview_seed_state` does NOT
  set type; without it, `opt_type` defaults to "session" and the guard's window-mode branch
  never runs — the test would exercise the session-mode path (a false pass).
- ❌ Don't add `attach_test_client`. preview.sh is client-independent (reads
  `@livepicker-orig-session`, not display-message). The client is dead weight + slows the suite.
- ❌ Don't `exit` or `return` nonzero to signal failure — run.sh reads `TEST_STATUS` in the
  current shell; a bare exit kills the runner. Use `fail()`/`assert_*()` only. An early
  `return 0` after a `fail` (the sanity guard) is the documented-safe skip.
- ❌ Don't skip the `wc -l` whitespace normalization. `wc -l` emits leading spaces ("  2");
  `assert_eq` does a string compare and would fail on "  2" vs "2". `tr -d '[:space:]'` both sides.
- ❌ Don't reorder the `sort | uniq -d` check. `uniq -d` needs SORTED input to catch
  non-adjacent duplicates; `sort` MUST come first. (A single duplicate here is adjacent anyway,
  but keep the correct order for robustness.)
- ❌ Don't split the assertions into multiple `test_*` functions. The contract is ONE function
  with the 3 complementary no-duplicate checks inside it.
- ❌ Don't modify `scripts/preview.sh` — that is S1's scope (Complete). This task is test-only.
      The L3 load-bearing check temporarily regresses preview.sh but RESTORES it at the end.
- ❌ Don't edit by guessing the file's tail — open `tests/test_preview.sh`, confirm the last
      function is `test_window_preview_shows_highlighted_window`, and anchor the append on its
      unique closing block (the `if [ "$(tmux show-option ... linked-id)" = "$active_id" ]` belt-and-braces + final `}`).

---

## Confidence Score

**10 / 10** for one-pass success. Rationale: the test is a single append of one function whose
verbatim body is supplied; every assertion is EMPIRICALLY PROVEN on the isolated harness
(research FINDING 1: pass=5 fail=0 against the fixed preview.sh; FINDING 2: pass=0 fail=3 against
the bug simulation — the assertions are load-bearing, not vacuous); it mirrors two existing
tests (`test_self_session_no_link` for the assertion shape, `test_window_preview_shows_highlighted_window`
for the dynamic-detection idiom); `run.sh` auto-discovers it (no wiring); it touches no production
code (zero regression risk to the rest of the suite); and the L3 load-bearing check deterministically
proves it catches the Issue 2 regression. The only environmental dependency (base-index) is handled
by dynamic detection, so the test is portable across configs.
