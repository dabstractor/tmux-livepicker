# PRP — Bugfix P1.M1.T1.S1: Delete duplicate restore.sh keep-window call + window-mode confirm status-format regression test

> **Re-planning context**: This is Issue 1 from the adversarial QA pass
> (`plan/001_fd5d622d3939/bugfix/001_15442f34c366/architecture/bugfix_findings.md`,
> Critical). A literal duplicate `restore.sh keep-window` call in the **window-mode
> confirm** branch permanently destroys custom `status-format` overrides (and
> force-resets `status`/`renumber-windows`/`key-table`). The shipped
> `test_restore_preserves_custom_status_format_low_indices` test only covers the
> **cancel** path, so this regression slipped through. This PRP fixes the root
> cause (one-line deletion) AND closes the test gap.

---

## Goal

**Feature Goal**: The window-mode **confirm** branch in `scripts/input-handler.sh`
calls `restore.sh keep-window` **exactly once**, so a window-mode confirm leaves
`status`, every `status-format[n]`, `renumber-windows`, and `key-table`
byte-identical to their pre-activation values — exactly like session-mode confirm
and cancel already do. A regression test proves it.

**Deliverable**:
1. One-line deletion in `scripts/input-handler.sh` (line 301 — the stray duplicate).
2. A new test function `test_window_confirm_preserves_custom_status_format`
   appended to `tests/test_restore.sh` (auto-discovered by `tests/run.sh`).

**Success Definition**:
- After a **window-mode confirm**, `status-format[0..3]` user overrides survive
  unchanged (FAILS today, PASSES after the fix).
- `tests/run.sh` reports the new test as PASS and the full suite stays green
  (no other test regresses — the deletion touches only the window-mode confirm
  path).
- The new test, run against the UN-fixed script, reproduces the failure (proving
  it actually guards this regression).

## User Persona (if applicable)

**Target User**: The maintainer / automated QA. Not end-user facing.

**Use Case**: A user with custom `status-format` overrides (e.g. tubular-style or
hand-tuned status lines) opens the picker in window mode, types a filter, and
confirms — their status bar config must survive.

**Pain Points Addressed**: Silent destruction of user config on a common action
(window-mode confirm); the only thing protecting this codepath before was a test
that exercised the *cancel* path, not *confirm*.

---

## Why

- **Critical data-loss bug.** Any non-default `status-format[n]` is wiped to tmux
  defaults after a window-mode confirm. PRD §2 promises "Full, exact restoration
  of status layout, key table, and focus on exit"; PRD §9 step 4 requires every
  `status-format[n]` restored.
- **Root cause is trivial & isolated.** It is a paste-duplicate of one line, in
  one branch, with no logic change elsewhere. The fix is the lowest-risk change
  possible — strictly removing a harmful redundant call.
- **Test gap is the real lesson.** The M2 fix added protection but only tested
  cancel. Adding a window-mode **confirm** regression test ensures this exact
  shape (any code path that calls restore twice) can't regress again.

## What

1. **The fix**: in `scripts/input-handler.sh`, the window-mode confirm branch
   currently has two consecutive, identical `restore.sh keep-window` calls
   (lines 300–301). Line 300 (4 tabs) is the correct single call; **line 301
   (5 tabs — a stray extra indent) is an accidental duplicate**. Delete line 301.
   Change **nothing else** — the unlink/switch-client/select-window above it and
   the `keep-window` mode argument are all correct.
2. **The test**: a new `test_window_confirm_preserves_custom_status_format()`
   function in `tests/test_restore.sh`, mirroring the existing cancel-path test
   but switching to `@livepicker-type window` and performing a **confirm** (with a
   type-filter that resolves to a real window target).

### Success Criteria

- [ ] `scripts/input-handler.sh` line 301 deleted; line 300 is the sole
      `restore.sh keep-window` in the window-mode confirm branch.
- [ ] `grep -c 'restore.sh" keep-window' scripts/input-handler.sh` returns **1**
      in the window branch (and the session branch still has its single
      `restore.sh" keep` — different mode arg, untouched).
- [ ] New test `test_window_confirm_preserves_custom_status_format` exists in
      `tests/test_restore.sh` and is auto-discovered (appears in `run.sh` output).
- [ ] `tests/run.sh` exits 0 with the new test PASSING.
- [ ] With the fix temporarily reverted, the new test FAILS (catches the bug).

## All Needed Context

### Context Completeness Check

_Pass_: The implementer needs (a) the exact two lines to edit (quoted verbatim
below with tab counts), (b) the existing cancel-path test to mirror (quoted
verbatim), and (c) the window-mode confirm semantics (target = `session:index`,
lands on the chosen window). No inference required.

### Documentation & References

```yaml
# MUST READ - the bug report (root-cause + repro)
- docfile: plan/001_fd5d622d3939/bugfix/001_15442f34c366/architecture/bugfix_findings.md
  why: §ISSUE 1 gives the exact location, the mechanism (1st call's clear_all_state
       empties saved state -> 2nd call's state_status_format_restore runs -gu + replays
       an EMPTY index list -> all custom status-format wiped), and the repro script.
  critical: The duplicate is IDENTIFIED BY INDENTATION — line 300 = 4 tabs (keep),
            line 301 = 5 tabs (delete). Do not delete line 300.

# MUST READ - the exact lines to edit (window-mode confirm branch)
- file: scripts/input-handler.sh
  why: Lines 300-301 are the duplicate. Confirmed via `awk`/`cat -A`: line 300 has
        4 tabs, line 301 has 5 tabs, both are `"$CURRENT_DIR/restore.sh" keep-window`.
  pattern: Window-mode branch is `if [ "$pick_type" = "window" ]; then` (line 268),
           ends with the restore call then `else` -> `_confirm_land_on_session` (session mode).
  gotcha: The session-mode path (_confirm_land_on_session, line 79-117) calls
          `restore.sh keep` (NOT keep-window) exactly ONCE (line 117) — that path is
          CORRECT and must NOT be touched. Only the window-mode keep-window duplicate is wrong.

# MUST READ - the test to mirror (cancel-path status-format round-trip)
- file: tests/test_restore.sh
  why: Lines 110-137 `test_restore_preserves_custom_status_format_low_indices` is the
        exact pattern: set status-format[0..3], snapshot (sfN_b), activate, CANCEL,
        re-read (sfN_a), assert_eq each. The new test copies this but uses WINDOW mode
        + CONFIRM (not cancel) and adds a 2nd window to alpha.
  pattern: attach_test_client first; `tmux set-option -g 'status-format[N]' '<val>'`;
           snapshot via `tmux show-option -gqv 'status-format[N]'`; assert_eq a b msg.
  gotcha: status-format is a GLOBAL option; assertions are valid regardless of which
          session the client lands on after confirm.

# MUST READ - the test harness contract (how a new test gets discovered/run)
- file: tests/run.sh
  why: Auto-discovers every `test_*` function via `compgen -A function | grep '^test_'`,
        runs each against a FRESH isolated socket (per-test setup_test/teardown_test),
        reset TEST_STATUS="pass" before each, prints PASS/FAIL + summary, exits 0/1.
  critical: Test bodies MUST signal failure ONLY via fail()/assert_* (set TEST_STATUS);
            NEVER `exit`/`return`-nonzero-to-abort (run.sh reads TEST_STATUS in the
            CURRENT shell — a bare exit kills the runner). Adding a test_* function to
            tests/test_restore.sh is sufficient — no registration needed.

# MUST READ - assertion + fixture helpers (in scope inside test bodies)
- file: tests/helpers.sh
  why: assert_eq a b msg, fail msg, pass msg; attach_test_client [sess] (attaches a
        client to $TEST_DRIVER_SESSION="driver" — REQUIRED before activate, because
        livepicker.sh uses lp_client_format '#{...}' which needs an attached client).
  critical: attach_test_client MUST be called before livepicker.sh, else window-mode
            current-token resolution (`lp_client_format '#{session_name}:#{window_index}'`)
            fails and confirm has no valid target.

# Reference - how window-mode builds its list (confirms the filter "alpha" matches)
- file: scripts/livepicker.sh
  why: Line 103 `list="$(tmux list-windows -a -F '#{session_name}:#{window_index}')"` —
        window tokens are `session:index` (e.g. `alpha:0`, `alpha:1`). Typing "alpha"
        filters to alpha's windows, giving confirm a non-empty target.
  section: Window-mode list build (~line 95-104)

# Reference - the restore contract (why keep-window once is correct)
- file: scripts/restore.sh
  why: `keep-window` differs from `keep` ONLY in restore STEP-2 (whether to re-select
        ORIG_WINDOW). Both run the full status-format restore exactly once when called
        once. The bug is NOT in restore.sh — it is calling it twice.
```

### Current Codebase tree

```bash
tmux-livepicker/
  scripts/
    input-handler.sh      # MODIFY: delete duplicate line 301 (window-mode confirm branch)
    restore.sh            # UNCHANGED (keep-window logic is correct; bug is the 2nd call)
    state.sh              # UNCHANGED (clear_all_state + state_status_format_restore correct)
    livepicker.sh         # UNCHANGED (window-mode list build correct)
    ...
  tests/
    test_restore.sh       # MODIFY: append test_window_confirm_preserves_custom_status_format
    run.sh                # UNCHANGED (auto-discovers the new test_*)
    helpers.sh            # UNCHANGED (assert_eq/attach_test_client reused)
    setup_socket.sh       # UNCHANGED (setup_test/attach_test_client/fixtures reused)
```

### Desired Codebase tree with files to be added and responsibility of file

```bash
scripts/input-handler.sh   # one line shorter (duplicate removed); behavior: restore once
tests/test_restore.sh      # one new test_ function; closes the window-mode confirm gap
```

### Known Gotchas of our codebase & Library Quirks

```bash
# CRITICAL — IDENTIFY THE LINE BY INDENTATION, not by content (both lines are
# textually identical). Verified via `awk 'NR>=299 && NR<=301{print NR": "gsub(/\t/,"&")" tabs"}'`:
#   line 299: 4 tabs  (the comment "# (keep-window skips restore STEP-2...)")
#   line 300: 4 tabs  "$CURRENT_DIR/restore.sh" keep-window   <- KEEP
#   line 301: 5 tabs  "$CURRENT_DIR/restore.sh" keep-window   <- DELETE (stray extra tab)
# Use the edit tool: oldText = BOTH lines (4-tab + 5-tab); newText = the 4-tab line only.

# CRITICAL — do NOT touch the SESSION-mode path. _confirm_land_on_session (line 79-117)
# calls `restore.sh keep` (note: "keep", NOT "keep-window") exactly once at line 117.
# That path is correct. Only the window-mode branch (keep-window) has the duplicate.

# CRITICAL — restore.sh keep-window is correct when called ONCE. Do NOT "harden" restore.sh
# to be idempotent against double-calls as an alternative fix — the root cause is the caller,
# and adding idempotency would mask future double-call bugs. Fix the caller; add the test.

# CRITICAL — test bodies run in the CURRENT shell under `set -u`. Every variable used in the
# new test MUST be declared `local` (mirror the existing test's `local sf0_b sf1_b ...`).
# Never `exit` from a test body — only fail()/assert_*.

# GOTCHA — attach_test_client BEFORE livepicker.sh. Window-mode current-token resolution
# needs an attached client. The existing cancel test calls attach_test_client first; do same.

# GOTCHA — give alpha a 2nd window BEFORE activate (`tmux new-window -t alpha -n chosenwin`).
# The baseline fixture seeds alpha/beta as SINGLE-window sessions; in window mode a single
# window per session still works, but the 2nd window guarantees a robust confirmable target
# and matches the bug-report repro exactly.

# GOTCHA — after a window-mode confirm, the client LANDS on the target (alpha), not back on
# driver. That is expected (keep-window preserves the selection). status-format assertions
# are GLOBAL so they're unaffected by landing session. Do NOT assert the client is on driver.

# GOTCHA — the new test mutates @livepicker-type and status-format globally, but each test
# runs on a FRESH isolated socket (setup_test/teardown_test per test), so no leak to others.

# GOTCHA — Indent with TABS (this whole codebase uses tabs; shfmt is NOT installed).
# The existing test_restore.sh tests use TAB indent — match them exactly.
```

## Implementation Blueprint

### Data models and structure

No data-model change. This is a one-line code deletion + one test function. The
relevant "model" is the window-mode confirm flow:

```
confirm action (input-handler.sh)
  └─ if pick_type == "window":
       target = "<session>:<window_index>"   (e.g. "alpha:0")
       drop driver preview window (if linked)
       switch-client -t "=alpha"             (the ONE session switch)
       select-window -t "alpha:0"
       restore.sh keep-window   ← MUST BE CALLED EXACTLY ONCE (currently twice -> BUG)
     else (session mode):
       _confirm_land_on_session target       ← calls restore.sh keep ONCE (correct)
```

### Implementation Tasks (ordered by dependencies)

```yaml
Task 1: MODIFY scripts/input-handler.sh — DELETE the duplicate restore call
  - LOCATE: window-mode confirm branch, lines 300-301. Both are:
      "$CURRENT_DIR/restore.sh" keep-window
    but line 300 has 4 tabs, line 301 has 5 tabs (verified via cat -A).
  - ACTION: delete line 301 ONLY. Keep line 300 (the 4-tab version).
  - METHOD (edit tool, exact-match both lines -> keep one):
      oldText (note: represent the tabs precisely; 4 tabs then 5 tabs):
        \t\t\t\t"$CURRENT_DIR/restore.sh" keep-window
        \t\t\t\t\t"$CURRENT_DIR/restore.sh" keep-window
      newText:
        \t\t\t\t"$CURRENT_DIR/restore.sh" keep-window
  - DO NOT change: the unlink block above, switch-client, select-window, the
    keep-window arg, the `else` -> _confirm_land_on_session branch, or anything
    in the session-mode path.
  - OPTIONAL: extend the comment on line 299 to note restore must be called
    exactly once (helps future readers); NOT required.
  - VERIFY after edit: `grep -n 'restore.sh" keep-window' scripts/input-handler.sh`
    shows exactly ONE match (line 300). `grep -n 'restore.sh" keep"'` still shows
    the session-mode call at ~line 117.

Task 2: MODIFY tests/test_restore.sh — APPEND the regression test
  - LOCATE: end of file (after test_restore_preserves_custom_status_format_low_indices,
    lines 110-137, for logical grouping).
  - IMPLEMENT function test_window_confirm_preserves_custom_status_format() (full
    body in "Implementation Patterns" below).
  - FOLLOW pattern: tests/test_restore.sh:110-137 (the cancel-path sibling). Same
    attach_test_client-first, same set-option -g 'status-format[N]' values, same
    sfN_b snapshot + sfN_a re-read + assert_eq structure.
  - NAMING: test_window_confirm_preserves_custom_status_format (matches existing
    snake_case test_ convention; auto-discovered by run.sh).
  - DEPENDENCIES: attach_test_client, $LIVEPICKER_SCRIPTS, $TEST_DRIVER_SESSION,
    assert_eq — all in scope (helpers.sh + setup_socket.sh sourced by run.sh).
  - PLACEMENT: tests/test_restore.sh (preferred per contract; it already owns the
    cancel-path status-format test). NOT test_create.sh.
  - STYLE: TABS for indent; `local` for all function locals; `set -u`-safe.

Task 3: VALIDATE (full harness; prove the test catches the bug)
  - RUN: bash -n scripts/input-handler.sh ; bash -n tests/test_restore.sh
  - RUN: shellcheck scripts/input-handler.sh tests/test_restore.sh  (expect clean;
    the existing files already pass shellcheck — your edits must not introduce findings)
  - RUN: tests/run.sh   (expect: new test PASS, full suite green, exit 0)
  - PROVE-IT-CATCHES-THE-BUG: temporarily re-add the duplicate line (or git stash the
    input-handler.sh fix), run ONLY the new test, confirm it FAILS, then restore the
    fix and confirm PASS again. (See Validation Loop §3 for the one-liner.)
```

### Implementation Patterns & Key Details

**Exact edit for Task 1** (the implementer can paste this into the `edit` tool;
`\t` = one literal tab — use real tab characters, the file is tab-indented):

```bash
# oldText (TWO lines: 4 tabs, then 5 tabs):
				"$CURRENT_DIR/restore.sh" keep-window
					"$CURRENT_DIR/restore.sh" keep-window

# newText (ONE line: 4 tabs):
				"$CURRENT_DIR/restore.sh" keep-window
```

**Complete test function for Task 2** (copy verbatim; append at EOF of
`tests/test_restore.sh`; uses TAB indent to match the file):

```bash
# test_window_confirm_preserves_custom_status_format — Bugfix Issue 1: a window-mode
# CONFIRM must leave status-format[0..3] byte-identical to pre-activation, exactly
# like cancel/session-confirm. The window-mode confirm branch previously had a
# DUPLICATE restore.sh keep-window call; its 2nd invocation ran with state already
# cleared by the 1st -> state_status_format_restore replayed an EMPTY index list
# after a `set-option -gu status-format`, wiping every custom override (and forcing
# status/renumber-windows/key-table to defaults). Mirror the cancel-path test but
# switch to @livepicker-type window and perform a CONFIRM.
test_window_confirm_preserves_custom_status_format() {
	attach_test_client
	local sf0_b sf1_b sf2_b sf3_b sf0_a sf1_a sf2_a sf3_a

	# Window mode (PRD §11 @livepicker-type). Must be set BEFORE activate.
	tmux set-option -g @livepicker-type window

	# Genuine user overrides at indices 0..3 (same values as the cancel-path test).
	tmux set-option -g 'status-format[0]' '#[fg=red]custom-zero'
	tmux set-option -g 'status-format[1]' '#[fg=green]custom-one'
	tmux set-option -g 'status-format[2]' '#[fg=yellow]custom-two'
	tmux set-option -g 'status-format[3]' '#[fg=blue]custom-three'

	sf0_b="$(tmux show-option -gqv 'status-format[0]' 2>/dev/null)"
	sf1_b="$(tmux show-option -gqv 'status-format[1]' 2>/dev/null)"
	sf2_b="$(tmux show-option -gqv 'status-format[2]' 2>/dev/null)"
	sf3_b="$(tmux show-option -gqv 'status-format[3]' 2>/dev/null)"

	# Give alpha a 2nd window so window mode has a robust confirmable target.
	tmux new-window -t alpha -n chosenwin

	"$LIVEPICKER_SCRIPTS/livepicker.sh" >/dev/null
	# Type "alpha" -> filtered list = alpha's windows (tokens "alpha:0"/"alpha:1").
	for c in a l p h a; do "$LIVEPICKER_SCRIPTS/input-handler.sh" type "$c" >/dev/null; done
	# Window-mode CONFIRM (the path that regressed). Lands on alpha; restores once.
	"$LIVEPICKER_SCRIPTS/input-handler.sh" confirm >/dev/null

	sf0_a="$(tmux show-option -gqv 'status-format[0]' 2>/dev/null)"
	sf1_a="$(tmux show-option -gqv 'status-format[1]' 2>/dev/null)"
	sf2_a="$(tmux show-option -gqv 'status-format[2]' 2>/dev/null)"
	sf3_a="$(tmux show-option -gqv 'status-format[3]' 2>/dev/null)"

	assert_eq "$sf0_a" "$sf0_b" "status-format[0] preserved across window-mode confirm"
	assert_eq "$sf1_a" "$sf1_b" "status-format[1] preserved across window-mode confirm"
	assert_eq "$sf2_a" "$sf2_b" "status-format[2] preserved across window-mode confirm"
	assert_eq "$sf3_a" "$sf3_b" "status-format[3] preserved across window-mode confirm"
}
```

Key pattern notes:
- `attach_test_client` FIRST — window-mode current-token resolution needs an
  attached client (livepicker.sh `lp_client_format '#{session_name}:#{window_index}'`).
- `@livepicker-type window` set globally BEFORE `livepicker.sh` so `opt_type`
  returns `window` at activation.
- The 2nd window on alpha guarantees confirm resolves a non-empty target
  (`target="${filtered[$cur_index]}"` → `"alpha:0"`).
- After confirm the client is on alpha (expected; `keep-window` preserves the
  selection). status-format is global, so assertions are landing-session-agnostic.
- Each test runs on a fresh isolated socket, so the global `@livepicker-type`/
  `status-format` mutations never leak to other tests.

### Integration Points

```yaml
CODE:
  - file: scripts/input-handler.sh
    change: "delete line 301 (5-tab duplicate restore.sh keep-window); keep line 300"
    invariant: "window-mode confirm calls restore.sh keep-window EXACTLY ONCE"

TESTS:
  - file: tests/test_restore.sh
    change: "append test_window_confirm_preserves_custom_status_format()"
    discovery: "auto via run.sh compgen -A function | grep '^test_'"

DATABASE / CONFIG / ROUTES: none.
```

## Validation Loop

### Level 1: Syntax & Style (Immediate Feedback)

```bash
cd /home/dustin/.config/tmux/plugins/tmux-livepicker
bash -n scripts/input-handler.sh && echo "OK: input-handler syntax"
bash -n tests/test_restore.sh     && echo "OK: test_restore syntax"
shellcheck scripts/input-handler.sh tests/test_restore.sh
# Tabs-not-spaces sanity on the edited region (shfmt is NOT installed):
awk 'NR>=299 && NR<=301' scripts/input-handler.sh | grep -qP '^ *\t' || echo "OK: tabs"
# Expected: both syntax-clean; shellcheck 0 findings; exactly ONE keep-window match:
grep -c 'restore.sh" keep-window' scripts/input-handler.sh   # -> 1
```

### Level 2: Unit Tests (the regression test)

```bash
# Run the full suite (hermetic, fresh isolated socket per test):
tests/run.sh
# Expected: the new test_window_confirm_preserves_custom_status_format prints PASS,
# the cancel-path sibling still PASSes, total suite green, exit 0.

# Run just the new test in isolation (optional, for fast iteration):
#   (the harness is whole-suite; isolating one test requires a tiny driver that
#    sources setup_socket.sh + helpers.sh + test_restore.sh then calls the fn.
#    Simplest: rely on run.sh and read the one PASS/FAIL line.)
```

### Level 3: Prove the test actually catches the bug (critical)

```bash
cd /home/dustin/.config/tmux/plugins/tmux-livepicker
# Temporarily restore the bug: re-add the duplicate line after the (now single) call.
cp scripts/input-handler.sh /tmp/ih.fixed
# Re-introduce the 5-tab duplicate immediately after the single keep-window call:
perl -0pi -e 's/(\t{4}"\$CURRENT_DIR\/restore\.sh" keep-window\n)/$1\t"$CURRENT_DIR\/restore.sh" keep-window\n/' scripts/input-handler.sh
grep -c 'restore.sh" keep-window' scripts/input-handler.sh   # -> 2 (bug present)
tests/run.sh 2>&1 | grep -E 'window_confirm_preserves'        # -> FAIL window_confirm_preserves...
# Restore the fix:
cp /tmp/ih.fixed scripts/input-handler.sh
grep -c 'restore.sh" keep-window' scripts/input-handler.sh   # -> 1 (fixed)
tests/run.sh 2>&1 | grep -E 'window_confirm_preserves'        # -> PASS window_confirm_preserves...
# Expected: the test FAILS with the duplicate present and PASSES once removed.
# If it PASSES even with the duplicate, the test is not exercising the window-mode
# confirm path correctly (re-check attach_test_client + @livepicker-type window + the
# type loop resolves a non-empty target).
```

### Level 4: Cross-check the other global options (defense-in-depth, optional)

```bash
# The duplicate ALSO clobbered status/renumber-windows/key-table to defaults. While
# the primary assertion is status-format, optionally assert those too for a stronger
# test (add to the same test body or a sibling test). Minimal optional snippet:
#   st_b="$(tmux show-option -gqv status)"; rn_b="$(tmux show-option -gqv renumber-windows)"
#   # ... activate, type, confirm ...
#   assert_eq "$(tmux show-option -gqv status)" "$st_b" "status preserved across window-confirm"
#   assert_eq "$(tmux show-option -gqv renumber-windows)" "$rn_b" "renumber-windows preserved"
# NOTE: keep this optional — the contract's required assertion is status-format[0..3].
```

## Final Validation Checklist

### Technical Validation

- [ ] `bash -n scripts/input-handler.sh` and `bash -n tests/test_restore.sh` clean.
- [ ] `shellcheck` on both files: 0 new findings.
- [ ] `grep -c 'restore.sh" keep-window' scripts/input-handler.sh` → **1**.
- [ ] Session-mode `restore.sh" keep"` call (~line 117) still present and untouched.

### Feature Validation

- [ ] New test `test_window_confirm_preserves_custom_status_format` discovered and PASS.
- [ ] Full `tests/run.sh` suite green (exit 0); no other test regressed.
- [ ] Bug-reintroduction check: with the duplicate restored, the new test FAILS.
- [ ] status-format[0..3] survive a window-mode confirm (the core fix).

### Code Quality Validation

- [ ] Only ONE line deleted in input-handler.sh; no other logic changed.
- [ ] New test follows existing conventions: `attach_test_client` first, `local`
      vars, `assert_eq`, TAB indent, `set -u`-safe, no `exit` in the body.
- [ ] Test placed in `tests/test_restore.sh` next to its cancel-path sibling.

### Documentation & Deployment

- [ ] No user-facing/config/API surface change (the fix restores already-documented
      "byte-exact restore" behavior). Optional inline comment noting "call exactly
      once" is acceptable but not required.
- [ ] (Doc sync is a separate changeset — P1.M3.T1.S1 CHANGELOG; do NOT edit
      CHANGELOG/README here unless this subtask explicitly owns it. The plan splits
      doc sync into P1.M3.)

---

## Anti-Patterns to Avoid

- ❌ Don't delete line 300 (the 4-tab correct call). The lines are textually
  identical — delete the one with the EXTRA (5th) tab.
- ❌ Don't "fix" this by making `restore.sh` idempotent against double-calls. The
  root cause is the caller; masking it invites future double-call bugs to pass
  silently. Fix the caller + add the regression test.
- ❌ Don't touch the session-mode `_confirm_land_on_session` path (it uses
  `restore.sh keep`, once, correctly).
- ❌ Don't `exit` or `return`-nonzero from the test body — signal failure ONLY via
  `fail()`/`assert_*` (run.sh reads `TEST_STATUS` in the current shell).
- ❌ Don't forget `attach_test_client` before `livepicker.sh` (window-mode
  current-token resolution needs an attached client).
- ❌ Don't assert the client is back on driver after a window-mode confirm — it
  lands on the target (alpha); that's correct `keep-window` behavior.
- ❌ Don't use spaces for indent — TABS only (match the file; shfmt absent).
- ❌ Don't skip the "prove it catches the bug" step (Level 3) — a regression test
  that passes both before AND after the fix is worthless.

---

## Confidence Score

**10 / 10** for one-pass success. Rationale: the fix is a verbatim one-line
deletion with the exact before/after provided (and verified by `cat -A`/`awk` tab
counts); the test is a near-clone of an existing passing test (same helpers, same
assertion shape) with the documented deltas (window mode + confirm + 2nd window +
type loop); the harness auto-discovers new `test_*` functions; and the
"reintroduce the bug → test FAILS" check (Level 3) deterministically proves the
test guards this exact regression. No ambiguity remains.
