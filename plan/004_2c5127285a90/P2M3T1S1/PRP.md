# PRP — P2.M3.T1.S1: Write test_window_flip.sh test suite

---

## Goal

**Feature Goal**: A passing, hermetic `tests/test_window_flip.sh` that validates
the window-flip feature end-to-end (PRD §3.6 + §15.20 Functional + §15.22
Live all-panes preview + §15.25 Restore) against the isolated-socket harness:
(a) flip links each chosen window into the driver and line-2 follows; (b)
leave-no-trace — the candidate's `window_active` AND `window_layout` are
byte-identical before/after a flip sequence (Invariant B); (c) confirm-on-window
lands the client on (S, W) — the chosen window, not the prior active; (d) cursor
reset — flipping A, leaving for B, and returning re-previews A on its OWN active
(flip history forgotten); (e) self-session flip + cancel restores ORIG_WINDOW.

**Deliverable** (1 NEW test file + 1 REQUIRED prerequisite correctness fix):
- **CREATE `tests/test_window_flip.sh`** — 5 `test_*` functions (one per case
  above) + a small `lp_winflip_match_size` helper, following the
  `test_functional.sh` / `test_preview_clip.sh` lifecycle style.
- **EDIT `scripts/preview.sh`** — make the three `select-window -t "$src_id"`
  calls SESSION-SCOPED (`"$current_session:$src_id"`). This is a load-bearing
  Invariant B fix the validation suite EXPOSES: the bare-id form selects the
  window in the candidate's HOME session, drifting the candidate's active on
  every flip. WITHOUT this fix, cases (b) and (d) cannot pass. See FINDING 3.
- **`tests/run.sh`**: NO edit (it auto-globs `tests/test_*.sh` — FINDING 6).

**Success Definition**:
- `bash -n`/`shellcheck` clean on the new test file + edited preview.sh.
- `tests/run.sh` GREEN — all 5 new `test_window_flip_*` functions PASS, and every
  pre-existing test still PASSES (the preview.sh fix is strictly additive: it
  preserves candidate-active on flips; session-nav/active-preview paths and all
  existing assertions are unchanged — FINDING 3).
- Each test case asserts exactly the observable tmux state named in the work item
  (verified shapes in the Validation Loop).

## User Persona (if applicable)

**Target User**: the tmux-livepicker maintainer — needs an automated, hermetic
regression suite for the window-flip + confirm-on-window feature so refactors
(P3 clip/immutability, future themes) cannot silently break Invariant B or the
flip/confirm mechanics.

**Use Case**: `tests/run.sh` runs after every change to scripts/preview.sh,
input-handler.sh, restore.sh, or state.sh; a red `test_window_flip_*` pinpoints
the broken case.

**Pain Points Addressed**: today there is NO test exercising the window-flip
axis (next-window/prev-window) or confirm-on-flipped-window; the P2.M1 flip +
P2.M2 confirm landed with only throwaway smokes. Invariant B (candidate active
untouched by flips) is currently VIOLATED by a bare-id select-window (FINDING 3)
— this suite both fixes and locks it.

## Why

- **PRD §15.20 Functional** + **§15.22 Live all-panes preview** mandate: "Flipping
  its windows (window axis) re-links each chosen window … The candidate's own
  active window is unchanged (Invariant B)" and "Enter on a match … lands on the
  chosen session **and the window being previewed**." This suite is the
  machine-checkable proof of both.
- **PRD §15.25 Restore**: "For every candidate previewed during the run, its
  active window id and `window_layout` equal their pre-activation values
  (Invariant B)." Case (b) asserts exactly this for the flip path.
- **The fix is load-bearing**: the validation purpose of this task is to LOCK
  Invariant B. The current code violates it (FINDING 3); shipping the test
  without the fix would ship a guaranteed-failing suite. The 3-line preview.sh
  edit is the minimal correctness change that makes the contract hold.
- **Sibling contract**: case (c) consumes P2.M2.T1.S1 (confirm commits the
  window via `select-window -t "=$S:$W"`) and P2.M2.T2.S1 (restore `keep` skips
  the ORIG_WINDOW re-select so the client STAYS on (S, W)). Both are
  COMPLETE/IMPLEMENTING; this suite is their acceptance test.

## What

1. **tests/test_window_flip.sh** (CREATE) — 5 test functions + 1 helper. Each
   test attaches a real client, drives the REAL `livepicker.sh` →
   `input-handler.sh` → `preview.sh` → `restore.sh` pipeline DIRECTLY (NOT via
   keypress — mirror test_functional.sh), and asserts observable tmux state via
   `fail`/`assert_*` (which set `TEST_STATUS`; run.sh reads it). Full bodies in
   the Blueprint.
2. **scripts/preview.sh** (EDIT) — 3 lines: `select-window -t "$src_id"` →
   `select-window -t "$current_session:$src_id"` (lines ~211, ~221, ~264). Byte-
   exact oldText/newText + a `sed` one-liner in the Blueprint.
3. **Docs**: NONE (the work item says "DOCS: none — internal test file"; the
   changeset README/CHANGELOG is P4.M1.T1.S1/S2).

### Success Criteria

- [ ] `tests/test_window_flip.sh` exists with exactly these 5 functions:
      `test_flip_links_chosen_window`, `test_flip_leave_no_trace`,
      `test_confirm_on_flipped_window`, `test_cursor_reset_on_return`,
      `test_self_session_flip_cancel_restores`.
- [ ] All 5 PASS under `tests/run.sh` (defer OFF, isolated socket — deterministic).
- [ ] preview.sh has ZERO `select-window -t "$src_id"` (grep == 0) and THREE
      `select-window -t "$current_session:$src_id"` (grep == 3).
- [ ] `tests/run.sh` is fully GREEN (no existing test regresses).
- [ ] `bash -n` + `shellcheck` clean on both files.

## All Needed Context

### Context Completeness Check

_Pass_: a developer who has never seen this repo implements the suite from
(a) the 5 full test-function bodies + helper in the Blueprint (copy-adapt),
(b) FINDING 2 (use `type <unique-name>` to highlight — `next-session` moves by 1),
(c) FINDING 3 (the preview.sh fix — why + exact lines + sed), (d) FINDING 4 (the
dynamic pre-size+manual helper that makes window_layout byte-identical),
(e) FINDING 5/6/8/9 (state-key evolution, harness contract, self-flip + confirm
mechanics). Every assertion shape was verified GREEN on tmux 3.6b (Validation Loop).

### Documentation & References

```yaml
# MUST READ — the ground-truth findings for THIS task (9 findings).
- docfile: plan/004_2c5127285a90/P2M3T1S1/research/findings.md
  why: FINDING 1 (5 cases + which pass as-is vs need the fix); FINDING 2 (type<unique>
       for deterministic highlight — NOT next-session); FINDING 3 (THE preview.sh bug +
       the session-scoped fix REQUIRED for b/d); FINDING 4 (dynamic pre-size+manual for
       window_layout byte-identical); FINDING 5 (cand-win state keys); FINDING 6 (harness
       contract); FINDING 7 (sibling deps); FINDING 8 (self-flip); FINDING 9 (confirm).
  critical: FINDING 2, 3, 4 are load-bearing. Read BEFORE writing any test body.

# MUST READ — the lifecycle style to MIRROR (activate → input-handler → assert).
- file: tests/test_functional.sh
  why: the canonical "drive the REAL plugin via input-handler.sh + assert tmux state"
        test style. Mirror: attach_test_client first; livepicker.sh to activate;
        input-handler.sh type/next-session/confirm/cancel; assert_eq/assert_contains;
        NO setup_test/teardown_test (run.sh owns the cycle). lp_runtime_cleared() is
        reusable for "picker torn down" checks.
  pattern: test_confirm_lands / test_nav_moves_selection / test_escape_restores.
  gotcha: the isolated server sources ~/.tmux.conf -> dormant @livepicker-* config
          REMAINS after teardown; use lp_runtime_cleared() (NOT `grep livepicker == 0`).

# MUST READ — the real-client + activate/restore lifecycle + sleep-after-activate style.
- file: tests/test_preview_clip.sh
  why: case (b) needs the driver's post-activate window size (FINDING 4) — mirror its
        `display-message -p -t "$drv_active" '#{window_width}'`/`'#{window_height}'` reads.
        Also mirrors sleep 0.3 after livepicker.sh (let the synchronous resize-pin +
        status-grow settle before asserting).
  pattern: _lp_clip_setup (attach + set option + activate + sleep).

# MUST READ — the EDIT target (the 3 select-window lines + the self-session path).
- file: scripts/preview.sh
  why: the 3 `select-window -t "$src_id"` calls (idempotent pre-link check ~L211,
        duplicate guard ~L221, main link flow ~L264) are the FINDING 3 fix. The
        self-session path (~L121-150) uses $chosen_win/$orig_window (NOT $src_id) ->
        leave it ALONE. $current_session is assigned at L94 (in scope at all 3 sites).
  gotcha: TAB-indented; the 3 target lines are byte-identical -> use the sed one-liner
          (the string `select-window -t "$src_id"` appears NOWHERE ELSE in the file).

# MUST READ — the input actions + confirm mechanics this suite drives.
- file: scripts/input-handler.sh
  why: next-window/prev-window (flip), next-session, type, confirm, cancel branches;
        confirm's session-mode path resolves W from STATE_CAND_WIN_CURSOR and does
        select-window -t "=$S:$W" (already session-scoped — correct). next-window lazily
        derives the cand-win list + resets cursor to active on (re)derivation.
  section: next-window, prev-window, confirm (session-mode non-self + self sub-paths).

# MUST READ — the state keys the tests read/write.
- file: scripts/state.sh
  why: STATE_CAND_WIN_SESSION/LIST/CURSOR, STATE_PREVIEW_WIN_ID, STATE_LINKED_ID — the
        readonly constants + the literal "@livepicker-*" option strings the assertions
        query via tmux show-option -gqv. All cleared by clear_all_state on teardown.

# MUST READ — the restore contract (cancel re-selects ORIG_WINDOW; keep skips it).
- file: scripts/restore.sh
  why: case (e) depends on cancel STEP-2 re-selecting ORIG_WINDOW (cancel-only after
        P2.M2.T2.S1). case (c) depends on keep NOT re-selecting (so the client stays
        on (S, W)). STEP-1 client-aware unlink; STEP-6 clear_all_state.

# MUST READ — the sibling PRPs this suite consumes (treat as CONTRACTS).
- docfile: plan/004_2c5127285a90/P2M1T3S1/research/findings.md
  why: FINDING 1 (window-list primitives: awk active-idx), FINDING 4 (the next-session
        pattern the flip mirrors), FINDING 7 (self-session flip needs no special case).
- docfile: plan/004_2c5127285a90/P2M2T1S1/PRP.md
  why: confirm resolves W from the cursor + commits via select-window -t "=$S:$W".
- docfile: plan/004_2c5127285a90/P2M2T2S1/PRP.md
  why: restore keep skips the ORIG_WINDOW re-select (cancel-only) — case (c) GREEN depends on it.

# MUST READ — PRD validation sections this suite implements.
- docfile: PRD.md
  why: §15.20 (Functional: flip + confirm land on the window being previewed);
        §15.22 (Live all-panes preview: flip re-links, candidate active unchanged =
        Invariant B); §15.25 (Restore: candidate active + window_layout equal
        pre-activation = Invariant B); §3.6 (Window navigation / flip semantics).
  section: "§15 Validation", "§6 Window navigation (flip)".
```

### Current Codebase tree (run `tree` in the repo root)

```bash
tmux-livepicker/
  scripts/
    preview.sh          # EDIT: 3x select-window -t "$src_id" -> "$current_session:$src_id" (FINDING 3)
    input-handler.sh    # UNCHANGED (next-window/prev-window/confirm/cancel — this suite DRIVES them)
    restore.sh          # UNCHANGED (cancel re-selects ORIG_WINDOW; keep skips — consumed by c/e)
    state.sh            # UNCHANGED (cand-win + linked-id + preview-win-id keys the tests read)
    livepicker.sh options.sh utils.sh rank.sh layout.sh renderer.sh session-mgmt.sh  # UNCHANGED
  tests/
    test_window_flip.sh # CREATE (this task)
    run.sh              # UNCHANGED (auto-globs test_*.sh — no edit; FINDING 6)
    setup_socket.sh helpers.sh test_functional.sh test_preview.sh test_preview_clip.sh ...  # UNCHANGED
  README.md PRD.md      # UNCHANGED (Mode A — DOCS: none)
  plan/004_2c5127285a90/{architecture/gap_analysis_confirm_preview.md, P2M1T3S1|P2M2T1S1|P2M2T2S1/...}
```

### Desired Codebase tree with files to be added and responsibility of file

```bash
tests/test_window_flip.sh   # NEW — 5 test_* functions validating flip + leave-no-trace +
                            #   confirm-on-window + cursor-reset + self-flip. Hermetic
                            #   (isolated socket via setup_test; defer OFF; real client).
scripts/preview.sh          # 3 lines: session-scoped select-window (Invariant B fix).
```

### Known Gotchas of our codebase & Library Quirks

```bash
# CRITICAL (FINDING 2): `next-session` moves the highlight by EXACTLY ONE position in
# tmux's session-creation order — it does NOT jump to a named candidate. To highlight a
# specific candidate DETERMINISTICALLY, `type` its UNIQUE name (zzcand/qqmulti/xxA/yyB —
# none is a substring of driver/alpha/beta or a sibling). `type` invalidates the cand-win
# cache; the first `next-window` after it re-derives + resets the cursor to active. CORRECT.

# CRITICAL (FINDING 3): bare `select-window -t "@id"` on a MULTI-LINKED window selects it
# in the window's HOME/origin session (the candidate), DRIFTING the candidate's active.
# This is why the flip (which selects a NON-active candidate window) violates Invariant B.
# The fix is session-scoped: `select-window -t "$current_session:$src_id"`. link-window
# ALONE does not drift (verified) — only the bare select does. Self-session is unaffected
# (its select targets a driver window that is NOT multi-linked).

# CRITICAL (FINDING 4): the candidate's window_layout (pane geometry) REFLOWS when a window
# is linked into the differently-sized driver (the §22/§23 shared-window resize). To assert
# window_layout BYTE-IDENTICAL (the work item's literal spec for b), the test must
# DYNAMICALLY pre-size the candidate's windows to the driver's post-activate size AND set
# the candidate's `window-size` to `manual` — then no reflow occurs. Query the driver size
# AFTER livepicker.sh activate (so the post-status-grow size is known). Verified byte-identical.

# GOTCHA (FINDING 6): every test_* in this file MUST call attach_test_client FIRST —
# livepicker.sh activate + display-message -p + refresh-client -S REQUIRE a client (mirror
# test_functional.sh / test_preview_clip.sh, NOT test_preview.sh which is client-independent).

# GOTCHA (FINDING 6): `set -u` is INHERITED from helpers.sh — do NOT re-declare it. Do NOT
# call setup_test/teardown_test inside a test_* (run.sh owns the per-test cycle). Source
# NOTHING (the harness provides everything in scope).

# GOTCHA (FINDING 7): case (c)'s "confirm lands and STAYS on (S, W)" depends on P2.M2.T2.S1
# (restore keep skips ORIG_WINDOW re-select). That task is IMPLEMENTING in parallel; the test
# is correct and goes GREEN once it lands. Do NOT add a workaround — assert the contract.

# GOTCHA: window ids (@N) are GLOBAL and assigned non-sequentially — ALWAYS read them
# DYNAMICALLY via list-windows (never hardcode). The chosen flip window W is
# `awk -v c="$cursor" 'NR==(c+1){print;exit}'` over @livepicker-cand-win-list, or simply
# @livepicker-linked-id (== W for non-self candidates).
```

## Implementation Blueprint

### Data models and structure

No data-model change. The tests READ these existing `@livepicker-*` options
(state.sh constants) and tmux formats:

```bash
# Window-cursor state (written by input-handler flip/nav, read by the tests):
@livepicker-cand-win-session   # the session the cached list belongs to
@livepicker-cand-win-list      # newline-joined window ids of the candidate
@livepicker-cand-win-cursor    # 0-based index into the list
@livepicker-preview-win-id     # the window currently shown (== linked-id non-self)
@livepicker-linked-id          # the window linked into the driver ("" for self)
# tmux formats used in assertions:
#{window_id}  #{window_active}  #{window_layout}  #{window_name}  #{session_name}  #{window_panes}
```

The chosen flip window `W` (non-self) = `@livepicker-linked-id` = `list[cursor]`.

### Implementation Tasks (ordered by dependencies)

```yaml
Task 1: EDIT scripts/preview.sh — session-scoped select-window (Invariant B fix; REQUIRED)
  - FILE: ./scripts/preview.sh (EXISTING). Three byte-identical lines (TAB-indented):
    `		tmux select-window -t "$src_id" 2>/dev/null || true` (idempotent pre-link check, ~L211;
    2 TABs), `		tmux select-window -t "$src_id" 2>/dev/null || true` (duplicate guard, ~L221;
    2 TABs), `	tmux select-window -t "$src_id" 2>/dev/null || true` (main link flow, ~L264;
    1 TAB). All three become session-scoped: `"$current_session:$src_id"`.
  - PREFERRED (handles all 3 identical lines atomically; the target string appears
    NOWHERE ELSE in preview.sh — verified by grep — so it is safe):
    sed -i 's/select-window -t "$src_id"/select-window -t "$current_session:$src_id"/g' scripts/preview.sh
    # (single-quoted sed script: $ is literal in the pattern; $current_session + $src_id in
    #  the replacement are literal text for tmux to expand at runtime — correct.)
  - ALTERNATIVE (per-line via the edit tool, each oldText made unique by its neighbor):
      #1 (idempotent pre-link check):
        oldText: | grep -Fxq "$src_id"; then\n\t\ttmux select-window -t "$src_id" 2>/dev/null || true\n\t\tset_state "$STATE_LINKED_ID" "$src_id"
        newText: | grep -Fxq "$src_id"; then\n\t\ttmux select-window -t "$current_session:$src_id" 2>/dev/null || true\n\t\tset_state "$STATE_LINKED_ID" "$src_id"
      #2 (duplicate guard):
        oldText: if [ -n "$linked_id" ] && [ "$linked_id" = "$src_id" ]; then\n\t\ttmux select-window -t "$src_id" 2>/dev/null || true\n\t\treturn 0
        newText: if [ -n "$linked_id" ] && [ "$linked_id" = "$src_id" ]; then\n\t\ttmux select-window -t "$current_session:$src_id" 2>/dev/null || true\n\t\treturn 0
      #3 (main link flow):
        oldText: # P1.M4.T4.S2 — not this task's concern).\n\ttmux select-window -t "$src_id" 2>/dev/null || true
        newText: # P1.M4.T4.S2 — not this task's concern).\n\ttmux select-window -t "$current_session:$src_id" 2>/dev/null || true
    (Use REAL TABS, not spaces. The § and — in comments are UTF-8 — copy byte-exact.)
  - FOLLOW pattern: the self-session path already selects with explicit targets
    ($chosen_win/$orig_window/$S) and confirm already uses `select-window -t "=$S:$W"`
    (session-scoped) — this makes the link path consistent with them.
  - PRESERVE: the `2>/dev/null || true`, the surrounding GUARD comments, the self-session
    path, preview_fallback, and EVERYTHING else. ONLY the 3 target substrings change.
  - DEPENDENCIES: none (preview.sh is COMPLETE; this is a pure correctness fix).

Task 2: CREATE tests/test_window_flip.sh — header + helper + 5 test functions
  - FILE: ./tests/test_window_flip.sh (NEW). Start with the file header comment block
    (mirror test_functional.sh / test_preview_clip.sh): explain it is SOURCED by run.sh,
    drives the REAL plugin via input-handler.sh, attaches a real client, defer OFF,
    signals pass/fail via fail/assert_* (set TEST_STATUS). Add the shellcheck disable
    line: `# shellcheck disable=SC2154,SC2016,SC2034,SC2086` (same as the siblings).
    DO NOT re-declare `set -u` (inherited). Source NOTHING. Call NO setup_test/teardown_test.
  - HELPER lp_winflip_match_size SESS — FINDING 4: after activate, query the driver's
    active-window dimensions and pre-size + manual-lock the candidate's windows so the
    driver's active window post-activate; echo nothing. Used by case (b) (and optional
    for the others). Body in "Implementation Patterns" below.
  - test_flip_links_chosen_window (case a): body in "Implementation Patterns".
  - test_flip_leave_no_trace (case b): body in "Implementation Patterns".
  - test_confirm_on_flipped_window (case c): body in "Implementation Patterns".
  - test_cursor_reset_on_return (case d): body in "Implementation Patterns".
  - test_self_session_flip_cancel_restores (case e): body in "Implementation Patterns".
  - NAMING: test_* prefix (run.sh discovers via `compgen -A function | grep '^test_'`).
    snake_case function + local names (house style). TABS for indent.
  - PLACEMENT: tests/test_window_flip.sh (auto-registered by run.sh's glob — FINDING 6).

Task 3: VALIDATE (L1 syntax/lint + L2 full suite + L3 the 5 cases isolated)
  - RUN: bash -n tests/test_window_flip.sh ; shellcheck tests/test_window_flip.sh
        bash -n scripts/preview.sh ; shellcheck scripts/preview.sh
  - RUN: grep cross-checks (preview.sh: 0 bare, 3 session-scoped; the test file has the
        5 named functions).
  - RUN: tests/run.sh (expect GREEN — all 5 new + every existing test).
  - RUN: the 5 cases in isolation (the Validation Loop's L3 — confirms each case alone).
```

### Implementation Patterns & Key Details

```bash
# File: tests/test_window_flip.sh — FULL bodies. Copy-adapt; TAB-indent; mirror the
# sibling test files' header + shellcheck line + the "no set -u / no setup_test" contract.

# ── HELPER: FINDING 4 — pre-size the candidate to the driver + manual-lock (no reflow) ──
# After activate the driver's status has grown, so its active window is at the final size
# a linked candidate window will adopt. Match the candidate's windows to THAT size and lock
# the candidate's window-size to manual -> linking does NOT reflow -> window_layout stable.
lp_winflip_match_size() {
	local sess="$1" drv_active DW DH w
	drv_active="$(tmux list-windows -t "=$TEST_DRIVER_SESSION" -F '#{window_id}' -f '#{window_active}')"
	DW="$(tmux display-message -p -t "$drv_active" '#{window_width}')"
	DH="$(tmux display-message -p -t "$drv_active" '#{window_height}')"
	tmux set-option -t "$sess" window-size manual
	for w in $(tmux list-windows -t "=$sess" -F '#{window_id}'); do
		tmux resize-window -t "$w" -x "$DW" -y "$DH" 2>/dev/null || true
	done
}

# ── (a) FLIP: next-window links the chosen window into the driver + line-2 follows ──
test_flip_links_chosen_window() {
	attach_test_client
	tmux new-session -d -s zzcand -x 80 -y 24
	tmux new-window -t zzcand -a -n w2
	tmux new-window -t zzcand -a -n w3          # zzcand: 3 windows; multi-pane below
	tmux split-window -h -t "zzcand:w2"
	"$LIVEPICKER_SCRIPTS/livepicker.sh" >/dev/null; sleep 0.3
	local c
	for c in z z c a n d; do "$LIVEPICKER_SCRIPTS/input-handler.sh" type "$c" >/dev/null 2>&1; done
	sleep 0.2
	# flip once; the chosen window W == @livepicker-linked-id (non-self) == list[cursor].
	"$LIVEPICKER_SCRIPTS/input-handler.sh" next-window >/dev/null 2>&1; sleep 0.2
	local W cl cur
	W="$(tmux show-option -gqv @livepicker-linked-id)"
	cl="$(tmux show-option -gqv @livepicker-cand-win-list)"; cur="$(tmux show-option -gqv @livepicker-cand-win-cursor)"
	assert_contains "$W" "@" "flip resolved a window id"
	assert_eq "$W" "$(awk -v c="$cur" 'NR==(c+1){print;exit}' <<<"$cl")" \
		"linked-id == cand-win-list[cursor] (the chosen window)"
	assert_contains "$(tmux list-windows -t "=$TEST_DRIVER_SESSION" -F '#{window_id}')" "$W" \
		"driver contains the chosen (linked) window"
	assert_eq "$(tmux list-windows -t "=$TEST_DRIVER_SESSION" -F '#{window_id}' -f '#{window_active}')" "$W" \
		"driver's active window == chosen (line 2 follows the flip)"
	# flip again -> a different chosen window is linked (wrapping is fine); re-assert link+select.
	"$LIVEPICKER_SCRIPTS/input-handler.sh" next-window >/dev/null 2>&1; sleep 0.2
	local W2; W2="$(tmux show-option -gqv @livepicker-linked-id)"
	assert_contains "$(tmux list-windows -t "=$TEST_DRIVER_SESSION" -F '#{window_id}')" "$W2" \
		"second flip links the new chosen window into the driver"
	assert_eq "$(tmux list-windows -t "=$TEST_DRIVER_SESSION" -F '#{window_id}' -f '#{window_active}')" "$W2" \
		"second flip selects the new chosen window (line 2 follows)"
	"$LIVEPICKER_SCRIPTS/input-handler.sh" cancel >/dev/null 2>&1
}

# ── (b) LEAVE-NO-TRACE: candidate window_active AND window_layout byte-identical (Invariant B) ──
test_flip_leave_no_trace() {
	attach_test_client
	tmux new-session -d -s zzcand -x 80 -y 24
	tmux new-window -t zzcand -a -n w2
	tmux new-window -t zzcand -a -n w3
	tmux split-window -h -t "zzcand:w2"; tmux split-window -v -t "zzcand:w2.0"   # w2 = 3 panes
	"$LIVEPICKER_SCRIPTS/livepicker.sh" >/dev/null; sleep 0.3
	lp_winflip_match_size zzcand                 # FINDING 4: freeze geometry (no reflow)
	local geom_before
	geom_before="$(tmux list-windows -t '=zzcand' -F '#{window_id}:#{window_active}:#{window_layout}')"
	local c
	for c in z z c a n d; do "$LIVEPICKER_SCRIPTS/input-handler.sh" type "$c" >/dev/null 2>&1; done
	sleep 0.2
	# flip through ALL windows (3 flips wraps the 3-window list once) — exercises every window.
	"$LIVEPICKER_SCRIPTS/input-handler.sh" next-window >/dev/null 2>&1; sleep 0.15
	"$LIVEPICKER_SCRIPTS/input-handler.sh" next-window >/dev/null 2>&1; sleep 0.15
	"$LIVEPICKER_SCRIPTS/input-handler.sh" next-window >/dev/null 2>&1; sleep 0.15
	assert_eq "$(tmux list-windows -t '=zzcand' -F '#{window_id}:#{window_active}:#{window_layout}')" \
		"$geom_before" \
		"candidate window_active + window_layout byte-identical after a full flip sequence (Invariant B)"
	# NOTE: window_layout encodes pane geometry + positions, so the byte-identical check above
	# ALREADY proves no pane was split/killed/moved — no separate pane-count assertion needed.
	"$LIVEPICKER_SCRIPTS/input-handler.sh" cancel >/dev/null 2>&1; sleep 0.2
	# after cancel the candidate is STILL byte-identical (cancel unlinks the DRIVER only).
	assert_eq "$(tmux list-windows -t '=zzcand' -F '#{window_id}:#{window_active}:#{window_layout}')" \
		"$geom_before" "candidate unchanged after cancel (leave-no-trace)"
}

# ── (c) CONFIRM-ON-WINDOW: flip a NON-active window, confirm lands on (S, W) ──
test_confirm_on_flipped_window() {
	attach_test_client
	tmux new-session -d -s qqmulti -x 80 -y 24
	tmux new-window -t qqmulti -a -n second
	tmux new-window -t qqmulti -a -n third       # qqmulti: 3 windows; active = third
	local pre_active
	pre_active="$(tmux list-windows -t '=qqmulti' -F '#{window_id}' -f '#{window_active}')"
	"$LIVEPICKER_SCRIPTS/livepicker.sh" >/dev/null; sleep 0.3
	local c
	for c in q q m u l t i; do "$LIVEPICKER_SCRIPTS/input-handler.sh" type "$c" >/dev/null 2>&1; done
	sleep 0.2
	"$LIVEPICKER_SCRIPTS/input-handler.sh" next-window >/dev/null 2>&1; sleep 0.2
	local W; W="$(tmux show-option -gqv @livepicker-linked-id)"
	# the chosen window MUST be a NON-active window of qqmulti (else the test is vacuous).
	[ "$W" != "$pre_active" ] || { fail "test setup invalid: flip landed on the active window"; return 0; }
	# Invariant B mid-flip: qqmulti's active is STILL its pre-flip active (the flip never
	# selected in qqmulti). This is the load-bearing FINDING 3 assertion.
	assert_eq "$(tmux list-windows -t '=qqmulti' -F '#{window_id}' -f '#{window_active}')" "$pre_active" \
		"candidate active unchanged mid-flip (Invariant B; the flip selects in the driver only)"
	"$LIVEPICKER_SCRIPTS/input-handler.sh" confirm >/dev/null 2>&1; sleep 0.2
	assert_eq "$(tmux display-message -p '#{session_name}')" "qqmulti" \
		"confirm landed the client on the target session (qqmulti)"
	assert_eq "$(tmux display-message -p '#{window_id}')" "$W" \
		"confirm landed on the CHOSEN window (the flipped window), not the prior active"
	# PRD §15.20: confirm commits the window — list-windows -f window_active shows W in qqmulti.
	assert_eq "$(tmux list-windows -t '=qqmulti' -F '#{window_id}' -f '#{window_active}')" "$W" \
		"confirm committed the chosen window as qqmulti's active"
}

# ── (d) CURSOR RESET: flip A, go B, return to A -> A re-previewed on its OWN active ──
test_cursor_reset_on_return() {
	attach_test_client
	tmux new-session -d -s xxA -x 80 -y 24
	tmux new-window -t xxA -a -n xa2
	tmux new-window -t xxA -a -n xa3            # xxA: 3 windows; active = xa3
	tmux new-session -d -s yyB -x 80 -y 24
	tmux new-window -t yyB -a -n yb2            # yyB: 2 windows
	local A_active; A_active="$(tmux list-windows -t '=xxA' -F '#{window_id}' -f '#{window_active}')"
	"$LIVEPICKER_SCRIPTS/livepicker.sh" >/dev/null; sleep 0.3
	local c
	for c in x x A; do "$LIVEPICKER_SCRIPTS/input-handler.sh" type "$c" >/dev/null 2>&1; done; sleep 0.2
	"$LIVEPICKER_SCRIPTS/input-handler.sh" next-window >/dev/null 2>&1; sleep 0.2   # flip A off its active
	# go to yyB (clear filter, type yyB)
	for i in 1 2 3; do "$LIVEPICKER_SCRIPTS/input-handler.sh" backspace >/dev/null 2>&1; done
	for c in y y B; do "$LIVEPICKER_SCRIPTS/input-handler.sh" type "$c" >/dev/null 2>&1; done; sleep 0.2
	# return to xxA (clear filter, type xxA)
	for i in 1 2 3; do "$LIVEPICKER_SCRIPTS/input-handler.sh" backspace >/dev/null 2>&1; done
	for c in x x A; do "$LIVEPICKER_SCRIPTS/input-handler.sh" type "$c" >/dev/null 2>&1; done; sleep 0.2
	# A is re-previewed on its OWN active window (flip history NOT remembered). FINDING 3 makes
	# A's active == A_active still; without the fix it drifted to the flipped window -> FAIL.
	assert_eq "$(tmux show-option -gqv @livepicker-linked-id)" "$A_active" \
		"returning to A re-previews A on its OWN active window (flip history forgotten)"
	# STATE_CAND_WIN_SESSION is invalidated by type (correct); a fresh flip re-binds it to xxA.
	"$LIVEPICKER_SCRIPTS/input-handler.sh" next-window >/dev/null 2>&1; sleep 0.2
	assert_eq "$(tmux show-option -gqv @livepicker-cand-win-session)" "xxA" \
		"STATE_CAND_WIN_SESSION re-bound to xxA on the post-return flip (cursor reset to active)"
	"$LIVEPICKER_SCRIPTS/input-handler.sh" cancel >/dev/null 2>&1
}

# ── (e) SELF-SESSION FLIP: flip the driver's own windows, cancel -> back on ORIG_WINDOW ──
test_self_session_flip_cancel_restores() {
	attach_test_client
	local orig_win; orig_win="$(tmux display-message -p '#{window_id}')"
	"$LIVEPICKER_SCRIPTS/livepicker.sh" >/dev/null; sleep 0.3
	# the driver is the initial highlight (self-session). flip the driver's OWN windows.
	"$LIVEPICKER_SCRIPTS/input-handler.sh" next-window >/dev/null 2>&1; sleep 0.2
	assert_eq "$(tmux show-option -gqv @livepicker-linked-id)" "" \
		"self-session flip leaves @livepicker-linked-id empty (no link attempted)"
	[ "$(tmux show-option -gqv @livepicker-preview-win-id)" != "$orig_win" ] \
		|| fail "self-session flip did not move the driver off ORIG_WINDOW"
	pass "self-session flip moved the driver to a different window"
	"$LIVEPICKER_SCRIPTS/input-handler.sh" cancel >/dev/null 2>&1; sleep 0.2
	assert_eq "$(tmux display-message -p '#{window_id}')" "$orig_win" \
		"cancel restored the driver to ORIG_WINDOW after a self-session flip"
}
```

### Integration Points

```yaml
TEST REGISTRATION:
  - file: tests/test_window_flip.sh
  - mechanism: "run.sh globs tests/test_*.sh and compgen -A function | grep '^test_' —
    creating the file AUTO-REGISTERS its 5 test_* functions. NO run.sh edit (FINDING 6)."

PREVIEW (scripts/preview.sh):
  - change: "3x `select-window -t "$src_id"` -> `select-window -t "$current_session:$src_id"`"
  - scope: "ONLY the link path (idempotent pre-link check + duplicate guard + main flow).
    The self-session path ($chosen_win/$orig_window/$S) is UNCHANGED. preview_fallback,
    the seq guards, and the @livepicker-linked-id/preview-win-id tracking are UNCHANGED."

INPUT-HANDLER / RESTORE / STATE / LIVEPICKER / OPTIONS: NO CHANGE (this suite DRIVES them).

DATABASE / MIGRATIONS / ROUTES / CONFIG-FILE: none.
```

## Validation Loop

### Level 1: Syntax & Style (Immediate Feedback)

```bash
cd /home/dustin/.config/tmux/plugins/tmux-livepicker
bash -n tests/test_window_flip.sh && echo "OK: test syntax"
bash -n scripts/preview.sh        && echo "OK: preview syntax"
shellcheck tests/test_window_flip.sh
shellcheck scripts/preview.sh
# preview.sh: the bare-id select is GONE (== 0); the session-scoped form is present (== 3):
grep -c 'select-window -t "\$src_id"' scripts/preview.sh                       # == 0
grep -c 'select-window -t "\$current_session:\$src_id"' scripts/preview.sh     # == 3
# the self-session path is UNCHANGED (still selects $chosen_win):
grep -c 'select-window -t "\$chosen_win"' scripts/preview.sh                   # >= 1
# the test file defines exactly the 5 named functions:
for fn in test_flip_links_chosen_window test_flip_leave_no_trace \
          test_confirm_on_flipped_window test_cursor_reset_on_return \
          test_self_session_flip_cancel_restores; do
  grep -q "$fn" tests/test_window_flip.sh || echo "MISSING: $fn"
done
# Expected: test syntax OK; preview syntax OK; shellcheck clean; bare==0; scoped==3;
#           self-session untouched; all 5 functions present.
```

### Level 2: Full suite (no regression + the 5 new cases GREEN)

```bash
cd /home/dustin/.config/tmux/plugins/tmux-livepicker
tests/run.sh
# Expected: exit 0. The 5 new test_window_flip_* PASS. Every pre-existing test still
# PASSES (the preview.sh fix is strictly additive — it preserves candidate-active on
# flips; session-nav/active-preview paths are no-ops under the fix; test_preview.sh /
# test_functional.sh assertions hold identically). If a PRE-EXISTING test turns red,
# the preview.sh fix over-reached — re-check that ONLY the 3 $src_id selects changed.
```

### Level 3: Each case in isolation (confirms the verified shapes)

```bash
# The 5 cases were each verified GREEN on tmux 3.6b via the probes in research/findings.md.
# To re-run a single case in isolation, source the harness + the file + call the function
# against a fresh socket (mirror setup_socket_self_test's isolated-cycle style):
cd /home/dustin/.config/tmux/plugins/tmux-livepicker
cat > /tmp/lp_one.sh <<'EOF'
#!/usr/bin/env bash
set -u
cd /home/dustin/.config/tmux/plugins/tmux-livepicker
source tests/setup_socket.sh; source tests/helpers.sh; source tests/test_window_flip.sh
setup_test "lp-one-${1:-a}"; TEST_STATUS="pass"; "$1"; echo "STATUS=$TEST_STATUS"; teardown_test
[ "$TEST_STATUS" = "pass" ] || exit 1
EOF
for t in test_flip_links_chosen_window test_flip_leave_no_trace \
         test_confirm_on_flipped_window test_cursor_reset_on_return \
         test_self_session_flip_cancel_restores; do
  bash /tmp/lp_one.sh "$t" && echo "PASS  $t" || echo "FAIL  $t"
done
rm -f /tmp/lp_one.sh
# Expected: all 5 PASS in isolation. (b) and (d) go GREEN ONLY after the Task 1 preview.sh
# fix lands — if (b)/(d) FAIL with "candidate active changed" / "linked-id != A_active",
# the fix did not apply (re-run the sed; verify grep scoped==3).
```

### Level 4: Creative & Domain-Specific Validation

```bash
# (1) INVARIANT B stress: flip a candidate MANY times (10x next-window on a 3-window
#     candidate) and assert window_active + window_layout STILL byte-identical. Wraps the
#     list ~3x; catches any cumulative drift. Use lp_winflip_match_size for geometry.
# (2) PREVIEW-DEFER parity: the suite pins defer OFF (setup_test). Sanity-check the SAME
#     flip mechanics hold with defer ON (@livepicker-preview-defer on) by toggling it in a
#     throwaway smoke (the seq guards + the session-scoped select are defer-agnostic). This
#     is NOT a shipped assertion (defer ON is non-deterministic for linked-id timing); it is
#     a manual confidence check. tests/test_responsiveness.sh owns the defer-ON path.
# (3) POLLUTION (PRD §15): after each test's cancel/confirm, assert the REAL server
#     (/usr/bin/tmux) is byte-identical before/after the full run.sh cycle — setup_socket's
#     self-test already proves this for the harness; the suite inherits it (no extra work).
# (4) SELF-SESSION confirm (P2.M2.T1 self path): after (e)'s flip, confirm (not cancel) on
#     the driver's own flipped window and assert #{window_id} == the chosen W (NOT
#     ORIG_WINDOW) — the keep-skip (P2.M2.T2.S1) leaves the driver there. Throwaway smoke
#     (not a shipped assertion — (e) covers the cancel path; this is the confirm analogue).
```

## Final Validation Checklist

### Technical Validation

- [ ] `bash -n` + `shellcheck` clean on tests/test_window_flip.sh AND scripts/preview.sh.
- [ ] preview.sh: `grep -c 'select-window -t "\$src_id"' == 0` and
      `grep -c 'select-window -t "\$current_session:\$src_id"' == 3` (L1).
- [ ] The self-session path (`select-window -t "\$chosen_win"`) is UNCHANGED (L1 >= 1).
- [ ] The 5 named test_* functions exist (L1).
- [ ] `tests/run.sh` exits 0 — all 5 new cases PASS + no existing test regresses (L2).

### Feature Validation

- [ ] (a) flip links each chosen window into the driver; driver active == chosen; line 2 follows.
- [ ] (b) candidate `window_active` + `window_layout` byte-identical before/after a flip
      sequence AND after cancel (Invariant B; requires Task 1 fix + lp_winflip_match_size).
- [ ] (c) confirm on a NON-active window lands the client on (S, W); qqmulti active == W
      after confirm; active unchanged mid-flip.
- [ ] (d) flipping A, leaving for B, returning re-previews A on its OWN active
      (linked-id == A_active); STATE_CAND_WIN_SESSION re-binds to xxA on the post-return flip.
- [ ] (e) self-session flip leaves linked-id empty + moves the driver off ORIG_WINDOW;
      cancel restores ORIG_WINDOW.
- [ ] All cases PASS in isolation (L3).

### Code Quality Validation

- [ ] Follows the test_functional.sh / test_preview_clip.sh lifecycle + assertion style.
- [ ] Deterministic highlighting via `type <unique-name>` (FINDING 2) — NEVER `next-session`
      to reach a named candidate.
- [ ] Window ids read DYNAMICALLY (never hardcoded); chosen W via linked-id / list[cursor].
- [ ] attach_test_client called first in EVERY test (client required); no setup_test/teardown_test
      inside test_*; `set -u` NOT re-declared; sources NOTHING.
- [ ] preview.sh change is the minimal 3-substring edit (sed or 3 unique-context edits);
      surrounding GUARD comments + self-session path + fallback byte-preserved.

### Documentation & Deployment

- [ ] No README / CHANGELOG / docs edit (Mode A — DOCS: none per the work item; the
      changeset CHANGELOG is P4.M1.T1.S2).
- [ ] No tests/run.sh edit (auto-glob registers the file — FINDING 6).

---

## Anti-Patterns to Avoid

- ❌ Don't use `next-session` to reach a named candidate — it moves the highlight by ONE in
  creation order and lands on alpha, not your candidate (FINDING 2). Use `type <unique-name>`.
- ❌ Don't skip the Task 1 preview.sh fix. Cases (b) and (d) CANNOT pass without it: the bare
  `select-window -t "$src_id"` drifts the candidate's active on every flip (Invariant B
  violation). The fix is session-scoped select — strictly more correct, 3 lines, no regression.
  (FINDING 3.)
- ❌ Don't assert `window_layout` byte-identical WITHOUT lp_winflip_match_size. The candidate
  reflows when linked into the differently-sized driver (§22/§23); without pre-sizing +
  manual-lock the geometry changes and (b) fails. The helper dynamically matches the driver's
  post-activate size — robust to any pty size. (FINDING 4.)
- ❌ Don't add a workaround for the P2.M2.T2.S1 dependency in (c). Confirm-lands-and-STAYS is
  the contract; the test asserts it. It goes GREEN once the sibling lands. (FINDING 7.)
- ❌ Don't hardcode window ids (@N) or assume base-index/creation order. Read them dynamically
  via `list-windows`; resolve the chosen W from `@livepicker-linked-id` or `list[cursor]`.
- ❌ Don't re-declare `set -u`, don't call setup_test/teardown_test, don't source anything
  inside the test file — run.sh owns the per-test cycle and provides everything in scope.
  (FINDING 6.)
- ❌ Don't touch the self-session path in preview.sh (`$chosen_win`/`$orig_window`/`$S`). It
  selects a driver window that is NOT multi-linked → no drift. The fix targets ONLY the 3
  `$src_id` selects. (FINDING 3, 8.)
- ❌ Don't edit tests/run.sh. It auto-globs `tests/test_*.sh`; creating the file registers it.
  (FINDING 6.)

---

## Confidence Score

**9 / 10** for one-pass success. Rationale: every one of the 5 test cases was
verified END-TO-END on tmux 3.6b against the isolated harness (7 probe batches —
the assertion shapes in the Blueprint are the GREEN shapes). The one non-trivial
piece — the Task 1 preview.sh fix — is a 3-substring `sed` whose target string
appears nowhere else in the file (grep-confirmed), whose session-scoped form was
proven to preserve the candidate's active (probe `lp_diag2.sh` TEST A), and which
is strictly additive (no existing test regresses — the session-nav/active-preview
path is a no-op under it). The window_layout byte-identical assertion (case b) —
the riskiest because it depends on no-reflow — is de-risked by the
`lp_winflip_match_size` helper, which was proven byte-identical across a 3-flip
sequence with a DYNAMICALLY-queried driver size (probe `lp_robust.sh`, robust to
any pty). The deterministic-highlighting gotcha (FINDING 2: type, not next-session)
is the most likely implementation slip, but it is called out in 3 places (gotchas,
anti-patterns, every test body uses it). The residual 1/10 is the P2.M2.T2.S1
parallel dependency for case (c)'s "stays on (S, W)" — but (c) is correct and
goes GREEN once that sibling lands; it does not block (a)/(b)/(d)/(e). The byte-
exact TAB/UTF-8 anchors for the optional per-line edit are provided; the `sed`
one-liner is the safer default.
