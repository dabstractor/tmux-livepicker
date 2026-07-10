#!/usr/bin/env bash
# tests/test_pane_immutability.sh — tmux-livepicker PRD §15.23 + §23 Invariant C validation (P3.M3.T1.S1).
#
# SOURCED by run.sh (NEVER executed directly). Defines 5 test_* functions (a-e) that validate §23
# Invariant C (zero pane mutation of any session) against the REAL plugin on the isolated-socket
# harness WITH a real attached client. CONSUMES the parallel §23 stack: §22 driver clip (COMPLETE),
# candidate pin (P3.M2.T2.S1), pane-geometry snapshot (P3.M2.T1.S1), drift-gated restore (P3.M2.T1.S2).
# Adds NO production code.
#
# Assert shape = the COMPLETE gate pane_immutability_verification.md §4: window_layout + sorted
# list-panes byte-identical. Unlike test_window_flip.sh's lp_winflip_match_size (a PRE-PIN workaround),
# this suite asserts the candidate pin holds geometry byte-identical with NO test-side pre-sizing.
#
# CONTRACT: run.sh sources setup_socket.sh + helpers.sh + every tests/test_*.sh (the GLOB auto-discovers
# this file — NO run.sh edit), then PER test calls setup_test "lp-$$-<name>" (-> fresh isolated -L socket +
# baseline fixtures + @livepicker-preview-defer OFF) -> resets TEST_STATUS=pass -> runs test_* in the
# CURRENT shell -> teardown_test. So when a test_* runs: bare `tmux` hits the isolated socket;
# attach_test_client / $LIVEPICKER_SCRIPTS / $TEST_DRIVER_SESSION / fail / pass / assert_* are ALL IN
# SCOPE; this file SOURCES NOTHING and calls NO setup_test/teardown_test. set -u is INHERITED (do NOT
# re-declare).
# shellcheck disable=SC2154,SC2016,SC2034,SC2086
#   SC2154: TEST_STATUS/fail/pass/assert_*/attach_test_client/$LIVEPICKER_SCRIPTS/$TEST_DRIVER_SESSION are
#           provided by run.sh's sources. SC2016/SC2034/SC2086: the single-quote format strings + word-split
#           idioms (mirrors the sibling test files).

# lp_immut_geom WID — echo a combined comparable geometry blob for window target WID (an @id or a
# "=sess:@id" form). Line 1 = the checksummed layout tree (window_layout embeds per-node dims + a
# 4-hex checksum -> changes on ANY reflow/resize); following lines = sorted per-pane geometry (the
# explicit §23 per-pane proof: pane_id:left,top,width,height). assert_eq on before/after blobs =
# byte-identity proof (gate §4). Echoes the blob.
lp_immut_geom() {
	local wid="$1"
	printf '%s\n' "$(tmux display-message -p -t "$wid" '#{window_layout}')"
	tmux list-panes -t "$wid" -F '#{pane_id}:#{pane_left},#{pane_top},#{pane_width},#{pane_height}' | sort
}

# lp_immut_make_candidate SESS [PANES] [WINDOWS] — build a DETACHED candidate session SESS with a
# multi-pane window 1 (PANES panes: 1|2|3) + WINDOWS total windows (each extra window is single-pane).
# Created BEFORE the picker opens (gate gotcha #9: create all windows BEFORE the manual/link state).
# Uses the BARE session name for new-session/split-window/new-window (NO '=' prefix — gate gotcha #1;
# '=' IS valid for list-windows/display-message). Candidates are created at 120x40 — the gate's ARM B
# fixture dimensions (matching the baseline alpha/beta), at which the candidate pin holds geometry
# byte-identical (ARM B proved byte-identical at this size; narrower sizes do not pin reliably).
# W1 (the multi-pane window) is left ACTIVE (the first preview target). Echoes nothing.
lp_immut_make_candidate() {
	local sess="$1" panes="${2:-3}" wins="${3:-3}" i
	tmux new-session -d -s "$sess" -x 120 -y 40          # W1, detached (BARE name — gotcha #1)
	if [ "$panes" -ge 2 ]; then tmux split-window -h -t "$sess"; fi
	if [ "$panes" -ge 3 ]; then tmux split-window -v -t "$sess"; fi
	for ((i = 2; i <= wins; i++)); do tmux new-window -t "$sess" -a -n "w$i"; done
	# W1 (the multi-pane window) is left ACTIVE so it is the first preview target. base-index is 1
	# (renumber-windows on) so W1 is at index 1 after the new-window -a appends; select it explicitly.
	tmux select-window -t "$sess:1"
}

# lp_immut_type WORD — type the unique subsequence WORD char-by-char to highlight candidate WORD
# (test_window_flip FINDING 2: `type` invalidates the cand-win cache + re-derives on the next flip;
# `next-session` moves by ONE in creation order and lands on alpha, NOT a named candidate). Echoes
# nothing. Each char goes through input-handler.sh type (synchronous — defer is OFF).
lp_immut_type() {
	local c
	# shellcheck disable=SC2068 # intentional word-split: caller passes space-separated single chars (i m m A); each $c is one char.
	for c in ${@:-}; do "$LIVEPICKER_SCRIPTS/input-handler.sh" type "$c" >/dev/null 2>&1; done
}

# lp_immut_clear_filter — clear the typed filter (backspace once per char of the last typed word) so
# the next `cancel` EXITS the picker (input-handler cancel CLEARs a non-empty filter on the first
# press and keeps the picker OPEN; only a second press with an empty filter triggers restore.sh).
# Echoes nothing.
lp_immut_clear_filter() {
	local c
	for c in 1 2 3 4 5 6 7 8 9 10; do "$LIVEPICKER_SCRIPTS/input-handler.sh" backspace >/dev/null 2>&1; done
}

# lp_immut_cancel — cancel the picker, ensuring it actually EXITS (runs restore.sh). Clears any typed
# filter first (the first cancel otherwise just clears the filter), then issues the exit cancel. The
# picker is now gone; restore.sh has run. Echoes nothing.
lp_immut_cancel() {
	lp_immut_clear_filter
	"$LIVEPICKER_SCRIPTS/input-handler.sh" cancel >/dev/null 2>&1
}

# (a) NO CANDIDATE PANE MOVEMENT (the core Invariant C). A detached 3-window multi-pane candidate's
# W1 window_layout + sorted list-panes are byte-identical before highlight vs after flip×3 + move to
# another candidate + return + cancel; the candidate's session window-size is restored (no manual
# trace) after cancel. Gate ARM B (pin HOLDS byte-identical, detached) + ARM D (flip safe under
# per-window pinning). NO test-side pre-sizing — asserts the candidate pin (P3.M2.T2.S1) holds.
test_no_candidate_pane_movement() {
	attach_test_client
	lp_immut_make_candidate immA 3 3        # W1 3-pane + W2 + W3
	lp_immut_make_candidate immB 1 1        # move target (single-pane, single-window)
	local w1
	w1="$(tmux list-windows -t '=immA' -F '#{window_id}' | sed -n '1p')"   # W1 @id (stable; flip selects in DRIVER only -> candidate active unchanged, Invariant B)
	local geom_before panes_before
	geom_before="$(lp_immut_geom "$w1")"
	"$LIVEPICKER_SCRIPTS/livepicker.sh" >/dev/null; sleep 0.3
	lp_immut_type i m m A; sleep 0.2        # highlight immA -> preview links W1 -> candidate pin fires
	# Flip through W1 -> W2 -> W3 -> W1 (gate ARM D: flip safe under per-window pinning).
	local i
	for i in 1 2 3; do "$LIVEPICKER_SCRIPTS/input-handler.sh" next-window >/dev/null 2>&1; sleep 0.2; done
	# Move to immB (clear filter, type immB) -> unlink immA (restore its pin), link immB.
	lp_immut_clear_filter; lp_immut_type i m m B; sleep 0.2
	# Return to immA (clear filter, type immA) -> unlink immB, re-link immA (re-pin).
	lp_immut_clear_filter; lp_immut_type i m m A; sleep 0.2
	lp_immut_cancel; sleep 0.3
	local geom_after panes_after
	geom_after="$(lp_immut_geom "$w1")"
	assert_eq "$geom_after" "$geom_before" \
		"candidate W1 pane geometry byte-identical across flip+move+cancel (Invariant C, detached)"
	# The candidate pin (P3.M2.T2.S1) restores the candidate's prior window-size on unlink/teardown
	# (no manual trace). window-size is session-scoped; empty/unset = inherits global (byte-exact).
	assert_eq "$(tmux show-options -t immA -v window-size 2>/dev/null || true)" "" \
		"candidate window-size restored (no pin trace) after cancel"
}

# (b) NO STATUS-GROW REFLOW (candidate not yet linked). A detached multi-pane candidate's geometry is
# byte-identical before activate vs after activate (status 1->2); the candidate is NOT previewed/linked.
# A DETACHED candidate is immune to the global status grow (no client to reflow to; gate §5 — the grow
# only disturbs CLIENT-BEARING sessions by 1 row). The §22 driver clip pins the driver; the candidate
# is untouched until linked.
test_no_status_grow_reflow() {
	attach_test_client
	lp_immut_make_candidate immA 3 1        # W1 3-pane, single window
	local w1
	w1="$(tmux list-windows -t '=immA' -F '#{window_id}' | sed -n '1p')"
	local geom_before
	geom_before="$(lp_immut_geom "$w1")"
	"$LIVEPICKER_SCRIPTS/livepicker.sh" >/dev/null; sleep 0.3      # status 1->2; candidate NOT previewed/linked
	assert_eq "$(tmux show-options -gv status)" "2" "status grew to 2"
	local geom_after
	geom_after="$(lp_immut_geom "$w1")"
	assert_eq "$geom_after" "$geom_before" \
		"candidate geometry unchanged by status-grow alone (not yet linked; detached immune)"
	lp_immut_cancel; sleep 0.3
}

# (c) NO CONFIRM SIDE-EFFECTS. After confirm on a candidate's chosen (non-active) window W: the
# candidate's OTHER windows' window_layout are byte-identical (unchanged), W is now the candidate's
# active window (only active-window selection moved), and W's pane geometry is byte-identical (no
# reflow). The candidate pin held W's geometry through the link, so confirming (select-window in the
# target) does not reflow it. Reuses the all-windows blob (window_id:window_active:window_layout).
test_no_confirm_side_effects() {
	attach_test_client
	lp_immut_make_candidate immA 3 3        # W1 3-pane ACTIVE, W2, W3
	"$LIVEPICKER_SCRIPTS/livepicker.sh" >/dev/null; sleep 0.3
	local all_before
	all_before="$(tmux list-windows -t '=immA' -F '#{window_id}:#{window_active}:#{window_layout}')"
	lp_immut_type i m m A; sleep 0.2        # highlight -> preview links W1 (active)
	"$LIVEPICKER_SCRIPTS/input-handler.sh" next-window >/dev/null 2>&1; sleep 0.2    # flip to W (the chosen NON-active window)
	local W w_geom_before pre_active
	W="$(tmux show-option -gqv @livepicker-linked-id)"              # the chosen window @id
	w_geom_before="$(lp_immut_geom "$W")"                            # W's pane geometry pre-confirm
	pre_active="$(printf '%s\n' "$all_before" | awk -F: '$2==1{print $1}')"   # W1 (the pre-confirm active)
	# Guard: W MUST be a non-active window of immA (else the test is vacuous).
	if [ "$W" = "$pre_active" ]; then
		fail "test setup invalid: flip landed on the active window"
		lp_immut_cancel
		return 0
	fi
	"$LIVEPICKER_SCRIPTS/input-handler.sh" confirm >/dev/null 2>&1; sleep 0.3   # lands client on (immA, W)
	local all_after
	all_after="$(tmux list-windows -t '=immA' -F '#{window_id}:#{window_active}:#{window_layout}')"
	# OTHER windows (windows != W) unchanged: their window_layout byte-identical (sorted, so window order is irrelevant).
	local others_before others_after
	others_before="$(printf '%s\n' "$all_before" | awk -F: -v w="$W" '$1!=w{print $1":"$3}' | sort)"
	others_after="$(printf '%s\n' "$all_after" | awk -F: -v w="$W" '$1!=w{print $1":"$3}' | sort)"
	assert_eq "$others_after" "$others_before" "confirm: immA's OTHER windows unchanged"
	# W is now immA's active window (only active-window selection moved).
	assert_eq "$(tmux list-windows -t '=immA' -F '#{window_id}' -f '#{window_active}')" "$W" \
		"confirm: W is now immA's active window (only selection moved)"
	# W's pane geometry byte-identical (the candidate pin held it through the link; confirm does not reflow).
	assert_eq "$(lp_immut_geom "$W")" "$w_geom_before" \
		"confirm: W's pane geometry byte-identical (no reflow)"
}

# (d) ORIGINAL WINDOW INTACT + drift-gate no-op. The driver's ORIG_WINDOW (the baseline active
# multi-pane "extra" window) is byte-identical across browse->cancel (the §22 clip held it); AND the
# @livepicker-orig-pane-geometry snapshot (read DURING the picker — it is cleared at restore STEP 6)
# equals the in-picker re-capture (proving the drift gate will find NO drift -> STEP 5 no-op ->
# select-layout did NOT run).
test_original_window_intact() {
	attach_test_client
	# The baseline driver's ACTIVE window is "extra" (3 panes) = ORIG_WINDOW. Grab it AFTER attach
	# (the client's active window). Precondition: it is multi-pane (else the byte-identity is vacuous).
	local orig
	orig="$(tmux display-message -p '#{window_id}')"
	if [ "$(tmux list-panes -t "$orig" 2>/dev/null | wc -l)" -lt 2 ]; then
		fail "precondition: driver ORIG_WINDOW not multi-pane"
		return 0
	fi
	local geom_pre
	geom_pre="$(lp_immut_geom "$orig")"     # pre-activate baseline
	lp_immut_make_candidate immA 3 2        # W1 3-pane + W2
	lp_immut_make_candidate immB 1 1        # move target
	"$LIVEPICKER_SCRIPTS/livepicker.sh" >/dev/null; sleep 0.3   # §22 clip pins driver; snapshot captured (STEP 2)
	lp_immut_type i m m A; sleep 0.2        # browse immA
	"$LIVEPICKER_SCRIPTS/input-handler.sh" next-window >/dev/null 2>&1; sleep 0.2
	lp_immut_clear_filter
	lp_immut_type i m m B; sleep 0.2        # move to immB
	# Read the snapshot DURING the picker (it is cleared at restore STEP 6, AFTER STEP 5 — gone after cancel).
	local snap cur_in_picker
	snap="$(tmux show-option -gqv @livepicker-orig-pane-geometry)"
	cur_in_picker="$(tmux list-panes -t "$orig" -F '#{pane_id}:#{pane_left},#{pane_top},#{pane_width},#{pane_height}')"
	lp_immut_cancel; sleep 0.3              # restore: STEP 4 un-pins driver + status 1; STEP 5 drift-gate (cancel-only)
	local geom_post
	geom_post="$(lp_immut_geom "$orig")"
	# snapshot == in-picker current -> drift gate finds NO drift -> STEP 5 no-op -> select-layout did NOT run.
	assert_eq "$cur_in_picker" "$snap" \
		"drift gate: snapshot == current geometry (no drift -> STEP5 no-op, select-layout did NOT run)"
	# ORIG_WINDOW byte-identical across the whole cycle (the §22 clip held it).
	assert_eq "$geom_post" "$geom_pre" \
		"driver ORIG_WINDOW pane geometry byte-identical across browse->cancel (§22 clip held it)"
}

# (e) SNAPSHOT MODE (escape hatch — invariant holds trivially). With @livepicker-preview-mode snapshot,
# @livepicker-linked-id stays EMPTY (preview_fallback = capture-pane, NEVER link-window — preview.sh
# snapshot gate) and the candidate geometry is byte-identical (never linked -> no shared-window
# disturbance -> invariant holds trivially). Gate §5 escape hatch.
test_snapshot_mode_invariant_holds() {
	attach_test_client
	lp_immut_make_candidate immA 3 1        # W1 3-pane, single window
	local w1
	w1="$(tmux list-windows -t '=immA' -F '#{window_id}' | sed -n '1p')"
	local geom_before
	geom_before="$(lp_immut_geom "$w1")"
	tmux set-option -g @livepicker-preview-mode snapshot    # per-test (AFTER setup_test — fresh server)
	"$LIVEPICKER_SCRIPTS/livepicker.sh" >/dev/null; sleep 0.3
	lp_immut_type i m m A; sleep 0.2        # preview_fallback (capture-pane) — NEVER link-window
	"$LIVEPICKER_SCRIPTS/input-handler.sh" next-window >/dev/null 2>&1; sleep 0.2   # still no link in snapshot mode
	assert_eq "$(tmux show-option -gqv @livepicker-linked-id)" "" \
		"snapshot mode: no window linked (capture-pane only)"
	lp_immut_cancel; sleep 0.3
	local geom_after
	geom_after="$(lp_immut_geom "$w1")"
	assert_eq "$geom_after" "$geom_before" \
		"snapshot mode: candidate geometry byte-identical (never linked -> invariant holds trivially)"
}
