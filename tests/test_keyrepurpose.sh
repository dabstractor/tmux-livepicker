#!/usr/bin/env bash
# tests/test_keyrepurpose.sh — tmux-livepicker PRD §15.20 Key repurpose validation (P1.M7.T6.S1).
#
# SOURCED by run.sh (NEVER executed directly). Defines two test_* functions that drive the
# COMPLETE real plugin DIRECTLY against the socket-isolated server and assert PRD §15.20:
# during the picker C-M-Tab/C-M-BTab move SESSIONS (they are bound in the livepicker table to
# input-handler next-session/prev-session), and after exit they move WINDOWS again (the root-
# table bindings are byte-identical to before — never mutated — and key-table reverts to root).
# Each test attaches a client, exercises one bullet, and signals pass/fail via fail/assert_*.
#
# CONTRACT: (same as test_restore.sh — SOURCED by run.sh; NO side effects on source; NO
# setup_test/teardown_test; attach_test_client FIRST; $LIVEPICKER_SCRIPTS/$TEST_DRIVER_SESSION/
# assert_*/attach_test_client in scope; this file SOURCES NOTHING.)
#
# CRITICAL (research FINDING 1): the isolated server sources the user tmux.conf -> the root-table
# C-M-Tab/C-M-BTab swap-window bindings ARE present before activate (no fixture needed):
#   bind-key -T root C-M-Tab swap-window -t +1 \; select-window -t +1
#   bind-key -T root C-M-BTab swap-window -t -1 \; select-window -t -1
# CRITICAL (research FINDING 5): the root binding is NEVER mutated (INVARIANT B — activate only
# COPIES prefix+root into livepicker); the revert is free because key-table returns to root.
#   during: list-keys -T livepicker C-M-Tab -> run-shell "<abs>/input-handler.sh next-session"
#   after:   list-keys -T root C-M-Tab      -> swap-window -t +1 \; select-window -t +1  (byte-identical)
# CRITICAL (research FINDING 7): attach_test_client FIRST.
#
# `set -u` is INHERITED from helpers.sh (do NOT re-declare; mirror test_self.sh).
# shellcheck disable=SC2154,SC2016,SC2034,SC2086

# test_keyrepurpose_during_picker — PRD §15.20 bullet 1: while the picker is active, C-M-Tab /
# C-M-BTab are repurposed to session navigation in the livepicker table.
test_keyrepurpose_during_picker() {
	attach_test_client
	local next_bind prev_bind

	"$LIVEPICKER_SCRIPTS/livepicker.sh"                     # activate -> key-table = livepicker

	# list-keys -T <table> <key> filters to one key (one line + rc=0 when present; empty + rc=1
	# when absent). Capture with 2>/dev/null || true so an absent binding yields "" (assert fails).
	next_bind="$(tmux list-keys -T livepicker C-M-Tab 2>/dev/null || true)"
	prev_bind="$(tmux list-keys -T livepicker C-M-BTab 2>/dev/null || true)"

	# PRD §15.20 b1: during the picker, C-M-Tab/C-M-BTab move SESSIONS (FINDING 5).
	assert_contains "$next_bind" "next-session" \
		"C-M-Tab repurposed to next-session in the livepicker table"
	assert_contains "$prev_bind" "prev-session" \
		"C-M-BTab repurposed to prev-session in the livepicker table"
	assert_eq "$(tmux show-option -gqv key-table)" "livepicker" \
		"key-table is livepicker during the picker"

	# Cleanup: cancel leaves a clean mid-test state (teardown kills the server anyway).
	"$LIVEPICKER_SCRIPTS/input-handler.sh" cancel
}

# test_keyrepurpose_reverts_after_exit — PRD §15.20 bullet 2: after the picker closes, the same
# keys move WINDOWS again. The root-table binding is byte-identical before/after (never mutated).
test_keyrepurpose_reverts_after_exit() {
	attach_test_client
	local root_before root_after rootb_before rootb_after

	# Snapshot the ROOT-table bindings BEFORE activate (the revert target).
	root_before="$(tmux list-keys -T root C-M-Tab 2>/dev/null || true)"
	rootb_before="$(tmux list-keys -T root C-M-BTab 2>/dev/null || true)"

	"$LIVEPICKER_SCRIPTS/livepicker.sh"
	"$LIVEPICKER_SCRIPTS/input-handler.sh" cancel           # key-table reverts to root

	root_after="$(tmux list-keys -T root C-M-Tab 2>/dev/null || true)"
	rootb_after="$(tmux list-keys -T root C-M-BTab 2>/dev/null || true)"

	# PRD §15.20 b2: after exit, C-M-Tab/C-M-BTab move WINDOWS again. The root binding was NEVER
	# mutated (INVARIANT B); byte-identical before/after is the proof. The revert is free because
	# key-table returned to root (FINDING 5).
	assert_eq "$root_after" "$root_before" \
		"root C-M-Tab byte-identical before/after (never mutated; reverts for free)"
	assert_contains "$root_after" "swap-window" \
		"after exit, C-M-Tab moves windows again (swap-window)"
	assert_contains "$rootb_after" "swap-window" \
		"after exit, C-M-BTab moves windows again (swap-window)"
	assert_eq "$(tmux show-option -gqv key-table)" "root" \
		"key-table reverted to root after exit"
}
