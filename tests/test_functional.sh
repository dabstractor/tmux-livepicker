#!/usr/bin/env bash
# tests/test_functional.sh — tmux-livepicker PRD §15.17 Functional validation (P1.M7.T3.S1).
#
# SOURCED by run.sh (NEVER executed directly). Defines five test_* functions that
# drive the COMPLETE real plugin (scripts/livepicker.sh -> input-handler.sh ->
# renderer.sh -> preview.sh -> restore.sh, all COMPLETE P1.M1-M6) DIRECTLY (NOT via
# keypress — work-item §1) against the socket-isolated server the harness provides
# (tests/setup_socket.sh P1.M7.T1.S1 + tests/helpers.sh P1.M7.T2.S1), and assert
# observable tmux state. Each test attaches a real client (the scripts need one),
# exercises one §15.17 bullet, and signals pass/fail via fail/assert_* (which set
# TEST_STATUS; run.sh reads it in the current shell).
#
# CONTRACT: run.sh sources setup_socket.sh + helpers.sh + every tests/test_*.sh,
# then PER test calls setup_test "lp-$$-<name>" (-> fresh isolated socket + PATH
# shim + baseline fixtures driver/alpha/beta) -> resets TEST_STATUS=pass -> runs
# the test_* in the CURRENT shell -> reads TEST_STATUS -> teardown_test. So when a
# test_* runs: bare `tmux` hits the isolated socket; $LIVEPICKER_SCRIPTS,
# attach_test_client, fail/pass/assert_eq/assert_contains are all IN SCOPE; this
# file SOURCES NOTHING and calls NO setup_test/teardown_test.
#
# CRITICAL (research FINDING 2): the isolated server sources the user tmux.conf ->
# @livepicker-fg "#ffffff" + @livepicker-key Space are pre-set (dormant §11 config).
# clear_all_state (CORRECTION A) PRESERVES config -> after confirm/cancel those two
# options REMAIN. So `show-options -g | grep livepicker` is NOT empty; the work-
# item's literal "no @livepicker-*" FALSE-FAILS. Use lp_runtime_cleared() (runtime+
# orig keys unset), NOT grep==0.
#
# `set -u` is INHERITED from helpers.sh (do NOT re-declare; mirror test_self.sh).
# shellcheck disable=SC2154,SC2016,SC2034,SC2086
#   SC2154: assert_*/attach_test_client/$LIVEPICKER_SCRIPTS/$TEST_DRIVER_SESSION are
#           defined by run.sh's sources, not in this file.

# lp_runtime_cleared — TRUE (rc 0) iff every picker-INTERNAL key is unset after a
# teardown (confirm keep / cancel). CORRECTION A (state.sh): clear_all_state clears
# ONLY the 5 runtime keys + @livepicker-orig-* and PRESERVES §11 config. In THIS
# env the dormant @livepicker-fg/@livepicker-key (sourced from the user tmux.conf)
# legitimately REMAIN -> the broad `grep livepicker` is non-empty (FINDING 2). This
# helper is the CORRECT "picker torn down" predicate.
lp_runtime_cleared() {
	local k
	for k in @livepicker-mode @livepicker-list @livepicker-filter \
	         @livepicker-index @livepicker-linked-id; do
		[ -z "$(tmux show-option -gqv "$k" 2>/dev/null)" ] || return 1
	done
	# No @livepicker-orig-* saved-state keys either (grep is READ-ONLY here; safe).
	# shellcheck disable=SC2143 # intentional: also catches empty grep output (no match == cleared)
	[ -z "$(tmux show-options -g 2>/dev/null | grep '@livepicker-orig-')" ] || return 1
	return 0
}

# test_activate_grows_status — PRD §15.17 bullet 1: activation grows the status
# bar to two lines; line 1 shows the picker; the key-table switches; mode arms.
test_activate_grows_status() {
	attach_test_client
	"$LIVEPICKER_SCRIPTS/livepicker.sh"
	# PRD §15.17 bullet 1: activation grows the status bar; line 1 shows the picker.
	assert_eq "$(tmux show-option -gqv status)" "2" "status grew to two lines"
	assert_contains "$(tmux show-option -gqv 'status-format[0]')" "renderer.sh" \
		"status-format[0] installs the renderer"
	assert_eq "$(tmux show-option -gqv key-table)" "livepicker" "key-table switched to livepicker"
	assert_eq "$(tmux show-option -gqv @livepicker-mode)" "on" "@livepicker-mode armed"
}

# test_typing_filters — PRD §15.17 bullet 2: typing filters the list; the
# highlight resets to the top match. Fixtures matching 'log' are added BEFORE
# activate (the list is captured at activate time — FINDING 5).
test_typing_filters() {
	attach_test_client
	# Add 'log'-matching fixtures BEFORE activate: @livepicker-list is captured at
	# activate time; the baseline driver/alpha/beta contain no 'log' substring.
	tmux new-session -d -s syslog -x 120 -y 40
	tmux new-session -d -s blog   -x 120 -y 40
	"$LIVEPICKER_SCRIPTS/livepicker.sh"
	"$LIVEPICKER_SCRIPTS/input-handler.sh" type l
	"$LIVEPICKER_SCRIPTS/input-handler.sh" type o
	"$LIVEPICKER_SCRIPTS/input-handler.sh" type g
	# PRD §15.17 bullet 2: typing filters the list and updates the highlight.
	out="$("$LIVEPICKER_SCRIPTS/renderer.sh")"
	assert_contains "$out" "syslog" "filtered view shows the 'log' match syslog"
	assert_contains "$out" "blog"   "filtered view shows the 'log' match blog"
	# NEGATIVE (FINDING 9): non-matches must NOT appear (inline case — no subprocess).
	case "$out" in *alpha*)  fail "alpha leaked into the filtered view"  ;; esac
	case "$out" in *driver*) fail "driver leaked into the filtered view" ;; esac
	assert_eq "$(tmux show-option -gqv @livepicker-index)" "0" "type resets highlight to the top match"
}

# test_nav_moves_selection — PRD §15.17 bullet 3: navigation moves the selection;
# the preview follows live (linked window id). Window ids are GLOBAL — read the
# target's id DYNAMICALLY (FINDING 6); nav never switches the client (Invariant A).
test_nav_moves_selection() {
	attach_test_client
	"$LIVEPICKER_SCRIPTS/livepicker.sh"
	# Activate's first preview is the SELF-session (driver) -> no link yet.
	assert_eq "$(tmux show-option -gqv @livepicker-linked-id)" "" "initial self-session preview leaves no link"
	# PRD §15.17 bullet 3: nav moves the selection; the preview follows live. Window
	# ids are GLOBAL — read the target's id DYNAMICALLY (FINDING 6).
	alpha_wid="$(tmux list-windows -t =alpha -F '#{window_id}' -f '#{window_active}')"
	"$LIVEPICKER_SCRIPTS/input-handler.sh" next-session
	assert_eq "$(tmux show-option -gqv @livepicker-linked-id)" "$alpha_wid" \
		"preview linked alpha's window (highlight moved to alpha)"
	beta_wid="$(tmux list-windows -t =beta -F '#{window_id}' -f '#{window_active}')"
	"$LIVEPICKER_SCRIPTS/input-handler.sh" next-session
	assert_eq "$(tmux show-option -gqv @livepicker-linked-id)" "$beta_wid" \
		"preview linked beta's window (highlight moved to beta)"
	# Invariant A: nav never switches the client (still on driver).
	assert_eq "$(tmux display-message -p '#{session_name}')" "driver" \
		"navigation never calls switch-client (Invariant A)"
}

# test_confirm_lands — PRD §15.17 bullet 4: Enter on a match closes the picker
# and lands the client on the target session; the picker's runtime state is
# cleared. Navigate to a real target BEFORE confirm; use lp_runtime_cleared
# (NOT grep==0 — FINDING 2).
test_confirm_lands() {
	attach_test_client
	"$LIVEPICKER_SCRIPTS/livepicker.sh"
	"$LIVEPICKER_SCRIPTS/input-handler.sh" next-session   # highlight -> alpha
	# PRD §15.17 bullet 4: Enter on a match closes the picker and lands on the session.
	linked_id="$(tmux show-option -gqv @livepicker-linked-id)"   # for the regression
	"$LIVEPICKER_SCRIPTS/input-handler.sh" confirm
	assert_eq "$(tmux display-message -p '#{session_name}')" "alpha" \
		"confirm landed the client on the target (alpha)"
	lp_runtime_cleared || fail "picker torn down (runtime+orig cleared; §11 config may remain — FINDING 2)"
	# Optional regression (confirm_mock FINDING 1/2): the driver must NOT still hold
	# the preview window after a session-mode confirm (switch-before-unlink bug guard).
	case "$(tmux list-windows -t driver -F '#{window_id}')" in
		*"$linked_id"*) fail "driver not cleaned of the preview window (FINDING 1/2)" ;;
	esac
}

# test_escape_restores — PRD §15.17 bullet 5: Escape closes the picker; the
# client returns to the original session/window; status/key-table restored.
# Capture orig state DYNAMICALLY before activate (FINDING 8); nav links a preview
# window so cancel exercises restore's unlink + layout work.
test_escape_restores() {
	attach_test_client
	# Capture the client's ORIGINAL state DYNAMICALLY before activate (driver's
	# active window is the 'extra' window, NOT @0 — read it live; FINDING 8).
	orig_sess="$(tmux display-message -p '#{session_name}')"
	orig_win="$(tmux display-message -p '#{window_id}')"
	orig_status="$(tmux show-option -gqv status)"
	orig_kt="$(tmux show-option -gqv key-table)"
	"$LIVEPICKER_SCRIPTS/livepicker.sh"
	"$LIVEPICKER_SCRIPTS/input-handler.sh" next-session   # link a preview window
	# PRD §15.17 bullet 5: Escape closes the picker; client back on the original
	# session/window; status restored. cancel is two-step: the empty filter (activate
	# sets "") -> full restore cancel; nav did not change the filter.
	"$LIVEPICKER_SCRIPTS/input-handler.sh" cancel
	assert_eq "$(tmux display-message -p '#{session_name}')" "$orig_sess" "session restored to origin"
	assert_eq "$(tmux display-message -p '#{window_id}')" "$orig_win" "window restored to origin"
	assert_eq "$(tmux show-option -gqv status)" "$orig_status" "status restored to origin"
	assert_eq "$(tmux show-option -gqv key-table)" "$orig_kt" "key-table restored to origin"
	lp_runtime_cleared || fail "picker torn down after cancel"
}
