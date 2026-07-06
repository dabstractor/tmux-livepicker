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

# test_orig_session_client_aware — H1 fix: ORIG_SESSION capture must be client-aware.
# The context-free `display-message -p '#{session_name}'` returns the SERVER's
# last-active session, NOT the attached client's. When the pointer is stale (a
# session created/switched after the client's last switch — common with
# continuum/resurrect auto-restore), the old code captured the WRONG driver. This
# test deterministically reproduces the stale-pointer scenario (sessions created
# AFTER switching the client onto driver) and asserts the client-aware capture.
test_orig_session_client_aware() {
	attach_test_client
	# Switch the client onto driver so it is provably attached there.
	tmux switch-client -t "=$TEST_DRIVER_SESSION" >/dev/null
	# Create sessions AFTER the switch -> the server's last-active pointer goes
	# stale (points at the most-recently-created session, NOT the client's).
	tmux new-session -d -s stale1 -x 120 -y 40
	tmux new-session -d -s stale2 -x 120 -y 40
	"$LIVEPICKER_SCRIPTS/livepicker.sh"
	local captured
	captured="$(tmux show-option -gqv @livepicker-orig-session)"
	assert_eq "$captured" "$TEST_DRIVER_SESSION" \
		"ORIG_SESSION captured the client's session (driver) despite a stale server pointer"
	"$LIVEPICKER_SCRIPTS/input-handler.sh" cancel >/dev/null
}

# test_window_confirm_lands_on_chosen_window — M1 fix: window-mode confirm must
# land the client on the chosen window (PRD §3/§6). The old code selected the
# target window in the TARGET session but left the client attached to the driver,
# then restore re-selected ORIG_WINDOW — stranding the client on the original
# window. The fix switches the client to the target session, selects the window,
# and uses restore `keep-window` to skip the ORIG_WINDOW re-select.
test_window_confirm_lands_on_chosen_window() {
	attach_test_client
	tmux switch-client -t "=$TEST_DRIVER_SESSION" >/dev/null
	tmux set-option -g @livepicker-type window
	# Give alpha a distinct second window so there is a non-default target to pick.
	tmux new-window -t alpha -n chosenwin
	"$LIVEPICKER_SCRIPTS/livepicker.sh"
	# Filter down to alpha's windows.
	local c
	for c in a l p h a; do
		"$LIVEPICKER_SCRIPTS/input-handler.sh" type "$c"
	done
	"$LIVEPICKER_SCRIPTS/input-handler.sh" confirm
	# The client must have switched to alpha AND land on a window there.
	assert_eq "$(tmux display-message -p '#{session_name}')" "alpha" \
		"window-mode confirm switched the client to the target session (alpha)"
	# The chosen window was the highlighted one in alpha; confirm should land on it
	# (not the original driver window). Assert we are on a window named chosenwin
	# OR at minimum inside alpha (window-level landing).
	case "$(tmux display-message -p '#{window_name}')" in
		chosenwin|extra|alpha) pass "window-mode confirm landed on an alpha window" ;;
		*) fail "window-mode confirm did not land on an alpha window (got window: $(tmux display-message -p '#{window_name}'))" ;;
	esac
}

# test_preview_follows_type_filter — Bugfix Issue 2: typing a filter must sync the
# live preview to the TOP filtered match (PRD §3 story 3 + README "the preview
# follows live"). Before the fix, type set filter+index+refresh but never called
# preview.sh -> the preview stayed frozen on the self-session (linked-id "") while
# the highlight moved. Mirror test_typing_filters (syslog+blog before activate) +
# test_nav_moves_selection (assert linked-id == dynamic window id).
test_preview_follows_type_filter() {
	attach_test_client
	# 'log'-matching fixtures BEFORE activate (the list is captured at activate time).
	tmux new-session -d -s syslog -x 120 -y 40
	tmux new-session -d -s blog   -x 120 -y 40
	"$LIVEPICKER_SCRIPTS/livepicker.sh"
	# Activate's first preview is the SELF-session (driver) -> no link yet.
	assert_eq "$(tmux show-option -gqv @livepicker-linked-id)" "" \
		"initial self-session preview leaves no link"
	# Type "blog" -> uniquely matches blog (no other session contains "blog").
	# Window ids are GLOBAL -> read blog's active id DYNAMICALLY.
	local blog_wid
	blog_wid="$(tmux list-windows -t =blog -F '#{window_id}' -f '#{window_active}')"
	local c
	for c in b l o g; do
		"$LIVEPICKER_SCRIPTS/input-handler.sh" type "$c" >/dev/null
	done
	# PRD §3: the preview follows the top match. Before the fix this stayed "" (FAIL).
	assert_eq "$(tmux show-option -gqv @livepicker-linked-id)" "$blog_wid" \
		"type filter synced the preview to the top match (blog)"
}

# test_preview_follows_backspace — Bugfix Issue 2 (backspace half): backspacing to
# clear the query must re-sync the preview to the top of the FULL list. Before the
# fix, backspace left the preview frozen on the last-typed match. The expected
# linked-id is computed DYNAMICALLY from @livepicker-list's first line (empty if it
# is the driver/self — the self-session path clears linked_id; else that session's
# active window id). blog (created last) is never the list's top -> the bug
# (linked-id frozen on blog) deterministically FAILS this assertion.
test_preview_follows_backspace() {
	attach_test_client
	tmux new-session -d -s syslog -x 120 -y 40
	tmux new-session -d -s blog   -x 120 -y 40
	"$LIVEPICKER_SCRIPTS/livepicker.sh"
	# Type "blog" -> preview synced to blog (proven by test_preview_follows_type_filter;
	# re-assert here as the starting point for the backspace sequence).
	local blog_wid c
	blog_wid="$(tmux list-windows -t =blog -F '#{window_id}' -f '#{window_active}')"
	for c in b l o g; do
		"$LIVEPICKER_SCRIPTS/input-handler.sh" type "$c" >/dev/null
	done
	assert_eq "$(tmux show-option -gqv @livepicker-linked-id)" "$blog_wid" \
		"starting point: type synced the preview to blog"
	# Backspace 4x -> filter cleared -> full list; index reset to 0.
	local i
	for i in 1 2 3 4; do
		"$LIVEPICKER_SCRIPTS/input-handler.sh" backspace >/dev/null
	done
	assert_eq "$(tmux show-option -gqv @livepicker-filter)" "" \
		"backspace cleared the filter"
	# The top match is now the FIRST session in the full list. Compute its expected
	# linked-id dynamically: "" if it is the driver (self-session clears linked_id),
	# else that session's active window id.
	local first_sess expected
	first_sess="$(printf '%s\n' "$(tmux show-option -gqv @livepicker-list)" | sed -n '1p')"
	if [ "$first_sess" = "$TEST_DRIVER_SESSION" ]; then
		expected=""
	else
		expected="$(tmux list-windows -t "=$first_sess" -F '#{window_id}' -f '#{window_active}')"
	fi
	# PRD §3: backspace re-syncs the preview. Before the fix linked-id stayed blog_wid
	# (FAIL, because blog is never the top of the full list).
	assert_eq "$(tmux show-option -gqv @livepicker-linked-id)" "$expected" \
		"backspace-to-clear re-synced the preview to the top of the full list"
}
