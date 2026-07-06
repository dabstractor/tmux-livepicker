#!/usr/bin/env bash
# tests/test_create.sh — tmux-livepicker PRD §15.22 Create-on-enter validation (P1.M7.T6.S1).
#
# SOURCED by run.sh (NEVER executed directly). Defines three test_* functions that drive the
# COMPLETE real plugin DIRECTLY against the socket-isolated server and assert PRD §15.22:
# session mode + create on + no match + Enter -> a new session is created and active; create off
# -> nothing created; window mode -> nothing created. Each test attaches a client, types a unique
# query, confirms, and signals pass/fail via fail/assert_*.
#
# CONTRACT: (same as test_restore.sh — SOURCED by run.sh; NO side effects on source; NO
# setup_test/teardown_test; attach_test_client FIRST; this file SOURCES NOTHING.)
#
# CRITICAL (research FINDING 6): type a UNIQUE query (not a substring of driver/alpha/beta) char-
# by-char via input-handler.sh type <c>. With an empty filtered list + session mode + create on,
# confirm creates the EXACT $query name (has-session "=$query" gate) and switches to it. create
# off OR window mode -> confirm takes the cancel path -> nothing created, client on driver. Set
# @livepicker-create / @livepicker-type via set-option -g BEFORE activate (activate reads opt_type
# to build the list; confirm reads opt_create/opt_type — correct when set before activate).
# CRITICAL (research FINDING 7): attach_test_client FIRST.
#
# `set -u` is INHERITED from helpers.sh (do NOT re-declare; mirror test_self.sh).
# shellcheck disable=SC2154,SC2016,SC2034,SC2086

# test_create_on_creates_and_activates — PRD §15.22 bullet 1: session mode + create on + no match
# + Enter -> the new session EXISTS and is ACTIVE.
test_create_on_creates_and_activates() {
	attach_test_client
	tmux set-option -g @livepicker-create on
	local q="zzzno" c

	"$LIVEPICKER_SCRIPTS/livepicker.sh"
	for c in z z z n o; do
		"$LIVEPICKER_SCRIPTS/input-handler.sh" type "$c"
	done
	"$LIVEPICKER_SCRIPTS/input-handler.sh" confirm

	# PRD §15.22 b1: the session was created (has-session exact-match =) AND is active.
	# has-session rc is the predicate; pass/fail narrates (no raw rc under set -u/no -e).
	if tmux has-session -t "=$q" 2>/dev/null; then
		pass "create-on-enter created the session $q"
	else
		fail "create-on-enter created the session $q (has-session = $q failed — FINDING 6)"
	fi
	assert_eq "$(tmux display-message -p '#{session_name}')" "$q" \
		"the new session is active (client landed on it)"
	assert_eq "$(tmux show-option -gqv @livepicker-mode)" "" \
		"picker torn down after confirm"
}

# test_create_off_creates_nothing — PRD §15.22 bullet 2: @livepicker-create off + no match + Enter
# -> nothing is created (confirm takes the cancel path); the client stays on the driver.
test_create_off_creates_nothing() {
	attach_test_client
	tmux set-option -g @livepicker-create off
	local q="qwfx" c

	"$LIVEPICKER_SCRIPTS/livepicker.sh"
	for c in q w f x; do
		"$LIVEPICKER_SCRIPTS/input-handler.sh" type "$c"
	done
	"$LIVEPICKER_SCRIPTS/input-handler.sh" confirm

	# PRD §15.22 b2: nothing created.
	if tmux has-session -t "=$q" 2>/dev/null; then
		fail "create-off created nothing ($q must not exist — FINDING 6)"
	else
		pass "create-off created nothing ($q absent)"
	fi
	assert_eq "$(tmux display-message -p '#{session_name}')" "$TEST_DRIVER_SESSION" \
		"client stayed on the driver (cancel path)"
}

# test_window_mode_creates_nothing — PRD §15.22 bullet 3: window mode + no match + Enter ->
# nothing created (window mode has no create path; confirm takes the cancel path).
test_window_mode_creates_nothing() {
	attach_test_client
	tmux set-option -g @livepicker-type window
	local q="mplg" c

	"$LIVEPICKER_SCRIPTS/livepicker.sh"
	for c in m p l g; do
		"$LIVEPICKER_SCRIPTS/input-handler.sh" type "$c"
	done
	"$LIVEPICKER_SCRIPTS/input-handler.sh" confirm

	# PRD §15.22 b3: nothing created.
	if tmux has-session -t "=$q" 2>/dev/null; then
		fail "window mode created nothing ($q must not exist — FINDING 6)"
	else
		pass "window mode created nothing ($q absent)"
	fi
}
