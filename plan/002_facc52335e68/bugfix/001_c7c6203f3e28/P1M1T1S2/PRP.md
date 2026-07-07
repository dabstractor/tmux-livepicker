# PRP — Bugfix P1.M1.T1.S2: Add window-index assertion tests for the multi-window driver

> **Re-planning context**: Issue 1 from the rev-002 QA pass
> (`plan/002_facc52335e68/bugfix/001_c7c6203f3e28/architecture/issue1_2_findings.md`,
> §"Test Coverage Gap"). The shipped suite asserts on window **IDs** (`#{window_id}`),
> which are invariant under an index shift, so it passes even when indices are
> corrupted. The shipped suite also uses single-window drivers, so the shift class
> of bugs is invisible to it. This subtask closes that gap with two committed tests
> that snapshot `#{window_index}:#{window_name}` on a **multi-window** driver and
> assert byte-equality after a preview cycle (cancel AND confirm).
>
> **Hard dependency on S1 (P1.M1.T1.S1)**: S1 removes the `-a` flag from
> `preview.sh`'s `link-window` call so the preview appends at the END (no shift).
> These tests PASS once S1 is applied and FAIL with the bug present (`-a`) — that
> dual behavior is exactly what makes them a faithful regression guard. S2 is
> implemented AFTER S1 (plan status: S1 Implementing, S2 Researching).

---

## Goal

**Feature Goal**: Two committed `test_*` functions that would have CAUGHT Issue 1 by
asserting on the driver's window **INDEX** ordering (not just `#{window_id}`) before
vs after a full activate → preview-foreign-session → cancel/confirm cycle, on a
**multi-window** driver whose active window is the FIRST (not last) — the exact
trigger for the `-a` index shift.

**Deliverable**: Two new functions appended to `tests/test_restore.sh`:
- `test_preview_preserves_window_indices_cancel`
- `test_preview_preserves_window_indices_confirm`

Both follow `test_restore.sh`'s existing pattern (`attach_test_client` →
`livepicker.sh` → `input-handler.sh next-session` → `cancel`/`confirm`). `run.sh`
auto-discovers any `test_*` function, so they join the suite with zero wiring.
**No other files change.** No source/`scripts/` edits (that is S1's job).

**Success Definition**:
- With S1 applied: `bash tests/run.sh` passes, including the two new tests.
- With the bug re-introduced (`-a`): both new tests FAIL with a clear
  `assert_eq` diagnostic showing the shifted indices (e.g. `1:first 3:extra 4:third`
  vs `1:first 2:extra 3:third`). This proves they are a real regression guard.
- The existing 40 tests still pass (no regression).

## User Persona (if applicable)

**Target User**: The maintainer / automated QA (CI). End users never see tests.

**Use Case**: A future change to `preview.sh` (or a tmux upgrade) that re-introduces
a mid-list link insertion is caught by the suite before it ships.

**Pain Points Addressed**: Issue 1 shipped undetected because every existing test
asserts on `#{window_id}` (stable under a shift) over a single-window driver. This
subtask makes the index-corruption class of bugs visible to the suite.

---

## Why

- **The shipped suite is blind to Issue 1.** `test_navigate_unlinks_intact`
  (test_preview.sh) and `test_restore_cancel_layout_exact` (test_restore.sh) assert
  on `#{window_id}` + `#{window_layout}`, neither of which moves when an index
  shifts. They PASS despite the corruption (issue1_2_findings.md §"Test Coverage
  Gap"). S1 fixes the bug but without S2 the fix is unguarded — a regression would
  re-escape detection.
- **The bug fires on the default path.** Session mode → browse another session →
  cancel/confirm, for any driver whose active window isn't last. A committed test
  that reproduces that path on a multi-window driver is the only durable proof S1
  works and keeps working.
- **Confirms AND cancel both corrupt.** Per the bug report, the shift occurs
  identically in both exit modes. Testing only cancel would leave the confirm path
  unguarded (it has different teardown: `_confirm_land_on_session` unlinks the driver
  pre-switch; restore runs `keep`, not `cancel`). Two tests cover both.

## What

Two `test_*` functions added to `tests/test_restore.sh`. Each:

1. Attaches a test client (the full activate flow needs one — `livepicker.sh`
   capture uses `display-message`, which is non-deterministic detached).
2. Builds a **3-window** driver: the 2 baseline windows (`zsh`, `extra`) + a 3rd
   added with `new-window -a -n third` (the `-a` idiom is required on this isolated
   server, which inherits `base-index=1`; a bare `new-window` collides — see
   `test_window_preview_shows_highlighted_window`).
3. Selects the **FIRST** (lowest-index) window by resolving its `@id` dynamically
   (robust to base-index), then renames it `first` (pins the auto-name for a fully
   deterministic snapshot). This is the bug's trigger (active = first/middle, not last).
4. Snapshots `tmux list-windows -t "=driver" -F '#{window_index}:#{window_name}'`
   BEFORE activation.
5. Runs `livepicker.sh` → `input-handler.sh next-session` (links a foreign preview
   into the driver) → `cancel` (test a) / `confirm` (test b).
6. Snapshots the same AFTER and asserts byte-equality via `assert_eq`.

### Success Criteria

- [ ] `tests/test_restore.sh` contains `test_preview_preserves_window_indices_cancel`
      and `test_preview_preserves_window_indices_confirm`.
- [ ] With S1 applied, `bash tests/run.sh` exits 0 (all 42 tests pass, incl. the 2 new).
- [ ] With `-a` re-introduced in `preview.sh`, both new tests FAIL (indices shifted);
      with the fix restored, both PASS. (Proven by Validation L3.)
- [ ] No `scripts/` file is touched by this subtask (the fix is S1; this is test-only).

## All Needed Context

### Context Completeness Check

_Pass_: the implementer needs (a) the two exact test functions (given verbatim
below), (b) awareness that they go in `tests/test_restore.sh` (the activate→nav→
cancel/confirm pattern, NOT test_preview.sh's direct-`preview.sh` pattern), (c) the
hard dependency on S1 (bare `link-window` in `preview.sh`), and (d) the bug-
reintroduction check (Validation L3) that proves the tests are load-bearing. All
empirical facts (base-index=1, the snapshot oracle, the confirm-path unlink) are
verified in `research/empirical_findings.md` and summarized below.

### Documentation & References

```yaml
# MUST READ — the bug report (root cause + repro + the exact test gap this closes)
- docfile: plan/002_facc52335e68/bugfix/001_c7c6203f3e28/architecture/issue1_2_findings.md
  why: §"Test Coverage Gap" enumerates every shipped test that asserts on #{window_id}
       (invariant under a shift) and prescribes the missing test (snapshot
       #{window_index} on a multi-window driver, assert byte-equal after cancel AND
       confirm). This subtask implements that prescription verbatim.
  critical: the bug report says the shift occurs in BOTH cancel AND confirm, and in
            window mode too. This subtask covers cancel + confirm (session mode).
            Window-mode coverage is a SEPARATE subtask (P1.M1.T2.S2) — do NOT add it here.

# MUST READ — S1's PRP (the fix these tests guard; the hard dependency)
- docfile: plan/002_facc52335e68/bugfix/001_c7c6203f3e28/P1M1T1S1/PRP.md
  why: S1 removes `-a` from preview.sh's link-window call (appends at END, no shift).
       These tests PASS with S1 and FAIL without it. S2 is implemented AFTER S1.
  critical: the line S1 edits is preview.sh:187 (`link-window -a -s "$src_id" -t
            "$current_session:"` -> `link-window -s "$src_id" -t "$current_session:"`).
            Validation L3 temporarily re-adds `-a` to PROVE the tests catch the bug.

# MUST READ — empirical ground-truth for every test mechanic (base-index, snapshot, confirm unlink)
- docfile: plan/002_facc52335e68/bugfix/001_c7c6203f3e28/P1M1T1S2/research/empirical_findings.md
  why: §1 base-index=1 (why new-window -a); §3 the snapshot oracle (before/after for
       bug vs fix); §4 the confirm path DOES unlink the driver's preview (the
       non-obvious fact that makes the confirm test's before/after assertion valid);
       §6 why renaming window 0 to 'first' is safe + deterministic.
  critical: §4 — confirm unlinks the driver via `_confirm_land_on_session` (input-handler.sh:106)
            BEFORE switch-client (targets $orig_session:$linked_id, not current_session).
            Without this, the confirm test would see an extra window and false-fail.

# The file to MODIFY (append the two functions after the last test)
- file: tests/test_restore.sh
  why: owns the exact-restoration invariant (PRD §15.21/§9) these tests strengthen;
       its existing tests use the SAME pattern (attach_test_client + full activate→
       nav→cancel/confirm). issue1_2_findings.md names test_restore_cancel_layout_exact
       (in this file) as one that MISSED the bug.
  pattern: test_restore_cancel_layout_exact (attach_test_client; snapshot before;
           livepicker.sh; input-handler.sh next-session; cancel; assert_eq after).
           test_window_confirm_preserves_custom_status_format (the confirm analog).
  gotcha: do NOT add these to test_preview.sh — that file's pattern is
          lp_preview_seed_state + DIRECT preview.sh calls (no client), which does
          NOT match the full-flow tests here.

# The confirm-path unlink (proves the confirm test is valid — read but do NOT edit)
- file: scripts/input-handler.sh
  why: _confirm_land_on_session (lines 79-118) unlinks the DRIVER's preview window
       (line 106, `tmux unlink-window -t "$orig_session:$linked_id"`) BEFORE the
       switch-client (line 112). drv_wins is 4 (3 + linked) > 1 so the unlink fires.
  gotcha: restore.sh keep STEP-1 then SKIPS its redundant unlink (current_session=alpha
          != orig_session=driver) — that is correct + harmless; do not "fix" it.

# The assert helper + the test-runner contract (read but do NOT edit)
- file: tests/helpers.sh
  why: assert_eq a b msg (POSIX equality; fail sets TEST_STATUS; never exits).
       setup_test/teardown_test are per-test (run.sh calls them; tests MUST NOT).
  gotcha: tests signal failure ONLY via fail/assert_* — NEVER `exit` or `return nonzero`
          (run.sh reads TEST_STATUS in the CURRENT shell; a bare exit kills the runner).

# The runner (read but do NOT edit)
- file: tests/run.sh
  why: discovers every `test_*` via `compgen -A function | grep '^test_'` and runs
       each against a FRESH isolated socket (per-test setup_test "lp-$$-<name>").
  pattern: the two new test_* names are auto-discovered with ZERO wiring.
```

### Current Codebase tree

```bash
tests/
  test_restore.sh   # MODIFY: append the two new test_* functions (after the last test)
  ...               # (all other test files + scripts/ UNCHANGED — the fix is S1)
```

### Desired Codebase tree with files to be added and responsibility of file

```bash
tests/test_restore.sh   # +2 test_* functions appended; no other change.
                        # Responsibility: regression guard for Issue 1 (index shift on
                        # a multi-window driver) across both exit paths (cancel/confirm).
```

### Known Gotchas of our codebase & Library Quirks

```bash
# CRITICAL — S1 is a HARD dependency. These tests PASS only after S1 removes `-a`
# from preview.sh:187. If S1 is not yet applied, both tests FAIL — that is CORRECT
# (they are catching the bug). Run/validate AFTER S1 lands. (Plan: S1 Implementing,
# S2 Researching — S2 implementation follows S1.)

# CRITICAL — base-index=1 on the isolated server (inherited ~/.tmux.conf). A bare
# `new-window -t driver` can collide ("index in use"). Use `new-window -a` (append
# after the active window) — the SAME idiom test_window_preview_shows_highlighted_window
# already uses and documents. Verified: appends cleanly at the END (index 3 here).

# CRITICAL — resolve the FIRST window by lowest INDEX via @id, NOT by a hardcoded
# index. base-index may be 0 or 1; the @id handle is stable. Pattern:
#   first_wid="$(tmux list-windows -t "=$drv" -F '#{window_index} #{window_id}' | sort -n | head -n1 | cut -d' ' -f2)"
# (Mirrors test_window_preview_shows_highlighted_window's dynamic @id resolution.)

# CRITICAL — the confirm test's before/after byte-equality is VALID because
# _confirm_land_on_session (input-handler.sh:106) unlinks the DRIVER's preview window
# BEFORE switch-client (targets $orig_session:$linked_id). Do NOT "simplify" the
# confirm test to assume the preview stays — it does not; it is removed. (See
# research/empirical_findings.md §4.)

# CRITICAL — snapshot #{window_index}:#{window_name} (per the work-item CONTRACT),
# NOT #{window_id}. #{window_id} is invariant under a shift and would NOT catch the
# bug (that is exactly why the existing tests miss it). The index is the oracle.

# GOTCHA — window 0 is auto-named ('zsh'/bash/etc.); it is stable across the cycle
# (nothing runs in its pane), but rename it to 'first' for a fully deterministic
# snapshot + clearer failure diagnostics. Renaming is safe (restore never touches
# window names; per-test fresh server). The 'extra' window keeps its name; the 3rd
# is `-n third`.

# GOTCHA — do NOT call setup_test/teardown_test inside a test_* (run.sh does that
# per-test). Tests use bare `tmux` (resolves to the isolated socket via the PATH shim)
# + the assert_* helpers + attach_test_client, all IN SCOPE from run.sh's sources.

# GOTCHA — signal failure ONLY via fail/assert_* (set TEST_STATUS). NEVER `exit` or
# `return <nonzero>` from a test body — run.sh reads TEST_STATUS in the current shell;
# a bare exit kills the whole runner (helpers.sh header CONTRACT).

# GOTCHA — Indent with TABS (the file is tab-indented; shfmt is NOT installed).
```

## Implementation Blueprint

### Data models and structure

No data model. The "oracle" is the `#{window_index}:#{window_name}` snapshot string;
the predicate is `assert_eq "$after" "$before"` (POSIX byte-equality). Both tests
share an identical setup + activate + next-session prefix; they differ only in the
exit action (`cancel` vs `confirm`) and the message.

### Implementation Tasks (ordered by dependencies)

```yaml
PRECONDITION: S1 (P1.M1.T1.S1) is applied — preview.sh:187 uses BARE `link-window`
  (no `-a`). Verify before implementing:
    grep -n 'link-window' scripts/preview.sh   # expect: `link-window -s "$src_id" -t "$current_session:"` (NO -a)
  If `-a` is still present, S1 has not landed — STOP and flag it (the tests will fail
  until S1 is in). Do NOT edit preview.sh yourself (that is S1's exclusive scope).

Task 1: APPEND two test_* functions to tests/test_restore.sh
  - LOCATE: the end of the last function `test_window_confirm_preserves_custom_status_format`
    (its closing `}` is the file's final line).
  - APPEND: the two functions EXACTLY as given in "Implementation Patterns" below,
    after that closing brace. Preserve the file's tab indent + header style.
  - DO NOT: modify any existing test, the file header, or any other file. Do NOT add
    a helper function (test_restore.sh's existing tests are all self-contained;
    match that style). Do NOT touch scripts/.

Task 2: VALIDATE — run the two new tests in isolation (should PASS with S1)
  - RUN: the throwaway isolation runner in Validation Loop §2 (sources setup_socket +
    helpers + test_restore.sh, calls ONLY the two new test_* names). Expect PASS PASS.
  - RUN: the bug-reintroduction check in Validation Loop §3 (temporarily re-add `-a`
    to preview.sh; the two tests MUST FAIL with shifted indices; restore the fix).
    This is the proof the tests are a real regression guard — do not skip it.

Task 3: VALIDATE — full suite (no regression)
  - RUN: bash tests/run.sh   # expect 42 passed, 0 failed (40 existing + 2 new).
```

### Implementation Patterns & Key Details

**Exact code to append** (paste after `test_window_confirm_preserves_custom_status_format`'s
closing `}`; every indented line starts with ONE tab — the file is tab-indented):

```bash

# test_preview_preserves_window_indices_cancel — Bugfix Issue 1 (test gap): the shipped
# suite asserts on #{window_id} (invariant under an index shift) over single-window
# drivers, so the `-a` index-shift bug escaped detection. This test snapshots the
# driver's #{window_index}:#{window_name} ordering on a MULTI-window driver whose
# active window is the FIRST (not last — the exact -a trigger), runs a full
# activate -> preview-foreign-session -> cancel cycle, and asserts byte-equality.
# PASSES with S1 (bare link-window appends at the END); FAILS with `-a` (mid-list
# insert leaves a permanent gap after unlink). Mirrors test_restore_cancel_layout_exact's
# attach -> activate -> next-session -> cancel pattern.
test_preview_preserves_window_indices_cancel() {
	attach_test_client
	# 3-window driver: the 2 baseline windows (zsh, extra) + a 3rd. `-a` (not bare
	# new-window) because the isolated server inherits base-index=1 and a bare
	# new-window collides — same idiom as test_window_preview_shows_highlighted_window.
	tmux new-window -t "$TEST_DRIVER_SESSION" -a -n third
	# Select the FIRST (lowest-index) window by @id (robust to base-index) + rename it
	# deterministically (pins auto-rename off -> fully stable snapshot). Active=FIRST
	# is the bug's trigger (-a inserts AFTER the active window, shifting later windows).
	local first_wid
	first_wid="$(tmux list-windows -t "=$TEST_DRIVER_SESSION" -F '#{window_index} #{window_id}' | sort -n | head -n1 | cut -d' ' -f2)"
	tmux select-window -t "$first_wid"
	tmux rename-window -t "$first_wid" first
	# Snapshot the driver's window INDEX ordering BEFORE activation (the property the
	# bug corrupts). #{window_index} is the oracle — NOT #{window_id} (invariant under
	# a shift). e.g. "1:first\n2:extra\n3:third" (base-index=1).
	local before
	before="$(tmux list-windows -t "=$TEST_DRIVER_SESSION" -F '#{window_index}:#{window_name}')"
	# Full cycle: activate -> preview a FOREIGN session (links its window into the
	# driver) -> cancel (restore unlinks the preview). next-session does not change the
	# filter, so cancel is the full-restore (two-step cancel's exit step).
	"$LIVEPICKER_SCRIPTS/livepicker.sh"                  >/dev/null
	"$LIVEPICKER_SCRIPTS/input-handler.sh" next-session  >/dev/null
	"$LIVEPICKER_SCRIPTS/input-handler.sh" cancel        >/dev/null
	local after
	after="$(tmux list-windows -t "=$TEST_DRIVER_SESSION" -F '#{window_index}:#{window_name}')"
	assert_eq "$after" "$before" \
		"driver window INDEX ordering unchanged after preview+cancel (multi-window driver, active=first)"
}

# test_preview_preserves_window_indices_confirm — Bugfix Issue 1 (confirm half): the
# index shift fires in BOTH exit paths (issue1_2_findings.md). The confirm path is
# structurally different from cancel: _confirm_land_on_session (input-handler.sh:106)
# unlinks the DRIVER's preview window BEFORE switch-client (targets $orig_session:
# $linked_id), then restore runs `keep` (no switch back). So the driver's window list
# IS restored to its pre-activate state on confirm -> the before/after byte-equality
# assertion is valid. Same multi-window/active=FIRST setup as the cancel test.
test_preview_preserves_window_indices_confirm() {
	attach_test_client
	tmux new-window -t "$TEST_DRIVER_SESSION" -a -n third
	local first_wid
	first_wid="$(tmux list-windows -t "=$TEST_DRIVER_SESSION" -F '#{window_index} #{window_id}' | sort -n | head -n1 | cut -d' ' -f2)"
	tmux select-window -t "$first_wid"
	tmux rename-window -t "$first_wid" first
	local before
	before="$(tmux list-windows -t "=$TEST_DRIVER_SESSION" -F '#{window_index}:#{window_name}')"
	# Full cycle: activate -> preview a FOREIGN session -> CONFIRM on it. Confirm lands
	# the CLIENT on alpha, but the DRIVER is queried by name (=driver) so its window
	# list (preview unlinked by _confirm_land_on_session) is observable regardless.
	"$LIVEPICKER_SCRIPTS/livepicker.sh"                  >/dev/null
	"$LIVEPICKER_SCRIPTS/input-handler.sh" next-session  >/dev/null   # highlight -> alpha (links preview)
	"$LIVEPICKER_SCRIPTS/input-handler.sh" confirm       >/dev/null   # unlink driver preview + switch to alpha + restore keep
	local after
	after="$(tmux list-windows -t "=$TEST_DRIVER_SESSION" -F '#{window_index}:#{window_name}')"
	assert_eq "$after" "$before" \
		"driver window INDEX ordering unchanged after preview+confirm (multi-window driver, active=first)"
}
```

**edit-tool usage** (the implementer appends after the last function). Anchor on
the final assertion + closing brace of `test_window_confirm_preserves_custom_status_format`
(unique in the file):

- oldText (the file's current last 2 lines):
```bash
	assert_eq "$sf3_a" "$sf3_b" "status-format[3] preserved across window-mode confirm"
}
```
- newText: the same 2 lines, immediately followed by a blank line + the two new
  functions verbatim (from the block above). Keep the trailing functions' tab indent.

### Integration Points

```yaml
TEST SUITE:
  - file: tests/test_restore.sh
    change: "append test_preview_preserves_window_indices_cancel + _confirm"
    discovery: "run.sh's `compgen -A function | grep '^test_'` auto-finds both — ZERO wiring"
    ordering: "run.sh sorts test_* names; both run in their own per-test fresh socket (hermetic)"

DEPENDENCY (read-only contract):
  - S1 (P1.M1.T1.S1): preview.sh:187 MUST be bare `link-window` (no `-a`) for the
    tests to PASS. Verify with `grep -n 'link-window' scripts/preview.sh` first.

CODE / DATABASE / ROUTES: none (test-only; no source/README/CHANGELOG change here —
docs are P1.M3.T1's scope).
```

## Validation Loop

### Level 1: Syntax & Style (Immediate Feedback)

```bash
cd /home/dustin/.config/tmux/plugins/tmux-livepicker
bash -n tests/test_restore.sh && echo "OK: syntax"
shellcheck tests/test_restore.sh          # expect 0 NEW findings (SC2154/SC2016 are
                                          # pre-existing + silenced in the header)
# The two new functions are present + named exactly:
grep -c '^test_preview_preserves_window_indices_' tests/test_restore.sh   # -> 2
# Tabs-not-spaces on the new region (shfmt absent):
grep -nP '^    ' tests/test_restore.sh | grep -i 'indices' && echo "WARN: spaces, not tabs" || echo "OK: tab-indented"
# PRECONDITION — S1 applied (bare link-window, no -a):
grep -n 'link-window' scripts/preview.sh   # expect the bare form; if `-a` is present, S1 hasn't landed -> STOP
```

### Level 2: Run the two new tests in isolation (should PASS with S1)

A throwaway runner that sources the harness + test_restore.sh and calls ONLY the two
new functions (so a failure isn't buried in the 40-test suite). Each gets its own
fresh isolated socket via the per-test setup_test/teardown_test pair (mirrors run.sh).

```bash
cat > /tmp/run_s2.sh <<'EOF'
#!/usr/bin/env bash
set -u
cd /home/dustin/.config/tmux/plugins/tmux-livepicker
source tests/setup_socket.sh
source tests/helpers.sh
source tests/test_restore.sh
rc=0
for t in test_preview_preserves_window_indices_cancel test_preview_preserves_window_indices_confirm; do
	setup_test "lp-s2-$$-${t#test_}"
	TEST_STATUS="pass"
	"$t"
	if [ "$TEST_STATUS" = "pass" ]; then echo "PASS  $t"; else echo "FAIL  $t"; rc=1; fi
	teardown_test
done
exit $rc
EOF
bash /tmp/run_s2.sh; rc=$?
rm -f /tmp/run_s2.sh
exit $rc
# Expected: PASS PASS (exit 0) WITH S1 applied. If either FAILS, first confirm S1 is in
# (grep 'link-window' scripts/preview.sh has no -a); if S1 is in and a test still fails,
# READ the assert_eq diagnostic (it prints got=[...] want=[...]) and debug.
```

### Level 3: Prove the tests catch the bug (critical — do not skip)

Temporarily re-introduce `-a` in preview.sh; BOTH new tests MUST now FAIL (indices
shifted). Restore the fix and confirm PASS. This is the proof the tests are a real
regression guard for Issue 1.

```bash
cd /home/dustin/.config/tmux/plugins/tmux-livepicker
cp scripts/preview.sh /tmp/preview.s1fixed
# Re-introduce -a (the bug):
perl -0pi -e 's/tmux link-window -s "\$src_id" -t "\$current_session:"/tmux link-window -a -s "$src_id" -t "$current_session:"/' scripts/preview.sh
grep -q 'link-window -a' scripts/preview.sh && echo "bug re-introduced (-a present)"
# Run the two tests -> expect FAIL FAIL (indices shifted, e.g. got=[1:first 3:extra 4:third] want=[1:first 2:extra 3:third])
bash /tmp/run_s2.sh 2>/dev/null || true   # (re-create /tmp/run_s2.sh from L2 first if removed)
# Restore S1's fix:
cp /tmp/preview.s1fixed scripts/preview.sh
rm -f /tmp/preview.s1fixed
grep -q 'link-window -a' scripts/preview.sh && echo "FAIL: -a still present" || echo "OK: S1 fix restored"
# Re-run -> expect PASS PASS again.
# Expected sequence: with -a, both FAIL; after restore, both PASS. If the tests PASS
# even with -a, they are NOT guarding Issue 1 -> the snapshot/assert is wrong (re-check
# it uses #{window_index}, not #{window_id}).
```

### Level 4: Full suite (no regression)

```bash
cd /home/dustin/.config/tmux/plugins/tmux-livepicker
bash tests/run.sh
# Expected: "<N> passed, 0 failed" where <N> = previous count (40) + 2 = 42.
# If a PRE-EXISTING test now fails, the new tests polluted shared state — but they
# can't (run.sh gives each test_* a fresh isolated socket via setup_test/teardown_test).
# Most likely cause of a surprise failure: S1's preview.sh edit interacting with an
# existing test -> that is S1's concern to triage, not S2's.
```

## Final Validation Checklist

### Technical Validation

- [ ] `bash -n tests/test_restore.sh` clean; `shellcheck` 0 NEW findings.
- [ ] Both `test_preview_preserves_window_indices_cancel` and `_confirm` present (grep -> 2).
- [ ] L2 isolation runner: PASS PASS (with S1 applied).
- [ ] L3 bug-reintroduction: with `-a`, both FAIL; with the fix, both PASS.
- [ ] L4 full suite: 42 passed, 0 failed (no regression to the 40 existing tests).

### Feature Validation

- [ ] Cancel path: multi-window driver, active=first, preview-foreign + cancel leaves
      `#{window_index}:#{window_name}` byte-identical to before activation.
- [ ] Confirm path: same setup, preview-foreign + confirm leaves the DRIVER's window
      indices byte-identical (preview unlinked by `_confirm_land_on_session`).
- [ ] The oracle is `#{window_index}` (NOT `#{window_id}`) — the test FAILS on a shift.
- [ ] Both tests use a 3-window driver with active=FIRST (the bug's worst-case trigger).

### Code Quality Validation

- [ ] Tests appended to `tests/test_restore.sh` only (no other file touched).
- [ ] No `scripts/` edit (the fix is S1's exclusive scope; this is test-only).
- [ ] Tab indent; matches test_restore.sh's self-contained, attach_test_client pattern.
- [ ] Failure is signalled ONLY via `assert_eq`/`fail` (TEST_STATUS); no `exit`/`return nonzero`.
- [ ] No `setup_test`/`teardown_test` called inside a test_* (run.sh owns the per-test cycle).

### Documentation & Deployment

- [ ] No README/CHANGELOG change in this subtask (handled by P1.M3.T1).
- [ ] Inline comments cite Issue 1 + the S1 dependency so the tests are self-documenting.

---

## Anti-Patterns to Avoid

- ❌ Don't assert on `#{window_id}` — it is invariant under an index shift (that is
  exactly why the existing tests miss Issue 1). Use `#{window_index}:#{window_name}`.
- ❌ Don't use a single-window driver — the `-a` shift only manifests when the linked
  window is inserted BEFORE an existing window (i.e. the driver has windows after the
  active one). Use a 3-window driver with active=FIRST.
- ❌ Don't use a bare `new-window -t driver` — base-index=1 on the isolated server
  makes it collide. Use `new-window -a` (the codebase's own idiom).
- ❌ Don't hardcode the first window's index (base-index may be 0 or 1). Resolve the
  lowest-index `@id` dynamically.
- ❌ Don't add these to `test_preview.sh` — its pattern is `lp_preview_seed_state` +
  DIRECT `preview.sh` calls (no client). These tests use the full activate flow with
  `attach_test_client` -> `test_restore.sh` is the correct home.
- ❌ Don't edit `scripts/preview.sh` or any source file — the fix is S1's exclusive
  scope. This subtask is test-only.
- ❌ Don't add window-mode coverage here — that is P1.M1.T2.S2 (Issue 2). This subtask
  is session-mode cancel + confirm only (Issue 1).
- ❌ Don't skip the bug-reintroduction check (L3). A test you can't prove fails without
  the fix is a test you can't trust.
- ❌ Don't `exit`/`return nonzero` from a test body — run.sh reads `TEST_STATUS` in the
  current shell; a bare exit kills the runner.

---

## Confidence Score

**10 / 10** for one-pass success. Rationale:
1. The two test functions are given verbatim (tab-indented, exact names).
2. Every mechanic was empirically verified on the repo's own isolated-socket harness
   (research/empirical_findings.md): base-index=1 (-> `new-window -a`); the
   `#{window_index}:#{window_name}` snapshot is a faithful oracle (FAILS with `-a`,
   PASSES with bare `link-window`); the confirm path unlinks the driver's preview
   before switch-client (so the confirm test's before/after assertion is valid).
3. The placement (`test_restore.sh`) matches the existing activate→nav→cancel/confirm
   pattern exactly, and the runner auto-discovers the functions with zero wiring.
4. The hard S1 dependency is stated up front and gated by a precondition check, and
   the L3 bug-reintroduction step proves the tests are load-bearing.
5. No source change is required (test-only), so the blast radius is nil — the worst
   case is a test that fails loudly with a `got=[...] want=[...]` diagnostic.
