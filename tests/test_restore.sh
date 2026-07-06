#!/usr/bin/env bash
# tests/test_restore.sh — tmux-livepicker PRD §15.21 Restore validation (P1.M7.T6.S1).
#
# SOURCED by run.sh (NEVER executed directly). Defines two test_* functions that drive the
# COMPLETE real plugin (scripts/livepicker.sh -> input-handler.sh -> preview.sh -> restore.sh,
# all COMPLETE P1.M1-M6) DIRECTLY (NOT via keypress — work-item §1) against the socket-
# isolated server the harness provides (tests/setup_socket.sh P1.M7.T1.S1 +
# tests/helpers.sh P1.M7.T2.S1), and assert PRD §15.21: after exit, status / every
# status-format[n] / key-table / renumber-windows / the session-window-changed hook / the
# pane layout are byte-exact, the livepicker table is unbound, and no picker-INTERNAL
# state leaks. Each test attaches a client (the scripts need one), exercises an activate ->
# nav -> cancel cycle, and signals pass/fail via fail/assert_* (which set TEST_STATUS; run.sh
# reads it in the current shell).
#
# CONTRACT: run.sh sources setup_socket.sh + helpers.sh + every tests/test_*.sh, then PER test
# calls setup_test "lp-$$-<name>" (-> fresh isolated socket + PATH shim + baseline fixtures
# driver/alpha/beta) -> resets TEST_STATUS=pass -> runs the test_* in the CURRENT shell -> reads
# TEST_STATUS -> teardown_test. So when a test_* runs: bare `tmux` hits the isolated socket;
# $LIVEPICKER_SCRIPTS, $TEST_DRIVER_SESSION, attach_test_client, fail/pass/assert_eq/
# assert_contains are all IN SCOPE; this file SOURCES NOTHING and calls NO setup_test/teardown_test.
#
# CRITICAL (research FINDING 2 — THE "grep livepicker" FALSE-FAIL): the contract's literal
# "assert `show-options -g | grep livepicker` is empty" FALSE-FAILS — the isolated server sources
# the user tmux.conf so the dormant §11 config (@livepicker-fg/@livepicker-key) is present, and
# clear_all_state PRESERVES §11 config -> those options REMAIN after cancel. THE FIX (FINDING 3):
# snapshot the FULL `show-options -g | sort` BEFORE activate and assert it BYTE-IDENTICAL after.
# The before-snapshot has the dormant config but NO runtime/orig keys -> byte-identity proves exact
# restore AND no runtime pollution in ONE assert (subsumes the corrected grep clause).
#
# CRITICAL (research FINDING 4): the livepicker table is GONE after cancel (unbind-key -a -T
# livepicker -> tmux reports it non-existent). Assert via capture + empty-test, NOT a raw rc.
#
# CRITICAL (research FINDING 7): the driven scripts REQUIRE an attached client -> attach FIRST.
#
# `set -u` is INHERITED from helpers.sh (do NOT re-declare; mirror test_self.sh).
# shellcheck disable=SC2154,SC2016,SC2034,SC2086
#   SC2154: assert_*/attach_test_client/$LIVEPICKER_SCRIPTS/$TEST_DRIVER_SESSION are defined by
#           run.sh's sources, not in this file.

# test_restore_cancel_options_hooks_exact — PRD §15.21 bullets 1-3: after activate -> nav ->
# cancel, the global options + hooks are BYTE-IDENTICAL to pre-activate (status / status-format[*] /
# key-table / renumber-windows restored AND no @livepicker-* runtime/orig keys leaked AND the
# dormant §11 config preserved), the livepicker table is unbound, and @livepicker-mode is disarmed.
test_restore_cancel_options_hooks_exact() {
	attach_test_client
	local opts_before hks_before opts_after hks_after lp_tbl

	# Snapshot the FULL sorted global options + hooks BEFORE activate (the baseline includes the
	# dormant §11 config + the live session-window-changed hook). sort -> stable set compare.
	opts_before="$(tmux show-options -g | sort)"
	hks_before="$(tmux show-hooks -g | sort)"

	"$LIVEPICKER_SCRIPTS/livepicker.sh"                     # activate (grows status, switches key-table)
	"$LIVEPICKER_SCRIPTS/input-handler.sh" next-session     # link a preview window into the driver
	"$LIVEPICKER_SCRIPTS/input-handler.sh" cancel           # empty filter -> full restore cancel

	opts_after="$(tmux show-options -g | sort)"
	hks_after="$(tmux show-hooks -g | sort)"

	# PRD §15.21 b1/b2: options byte-identical (status, status-format[*], key-table, renumber-windows
	# restored) AND no runtime/orig @livepicker-* leaked (the before-snapshot has none -> byte-identity
	# forces the after-snapshot to have none) AND the dormant §11 config correctly survives. This
	# single assert SUBSUMES the corrected "grep livepicker empty" clause (FINDING 2/3).
	assert_eq "$opts_after" "$opts_before" \
		"global options byte-identical after restore (status/format/key-table/renumber restored; no @livepicker-* leaked; §11 config preserved)"
	# PRD §15.21 b2: the session-window-changed[0] run-shell -b hook is restored exactly (index + -b +
	# abs path preserved — TRAP 2). Diffing the whole hook dump proves it (no manual parsing).
	assert_eq "$hks_after" "$hks_before" \
		"global hooks byte-identical after restore (session-window-changed hook with -b preserved)"

	# PRD §15.21 / work-item: the livepicker table is unbound (FINDING 4: unbind-key -a -T livepicker
	# makes tmux report it non-existent -> list-keys stdout is EMPTY; capture + empty-test, not rc).
	lp_tbl="$(tmux list-keys -T livepicker 2>/dev/null || true)"
	assert_eq "$lp_tbl" "" "livepicker key table unbound after cancel (no bindings remain)"

	# The double-activation guard is disarmed (restore clear_all_state).
	assert_eq "$(tmux show-option -gqv @livepicker-mode)" "" "@livepicker-mode disarmed after restore"
}

# test_restore_cancel_layout_exact — PRD §15.21 bullet 4: the original window's pane layout is
# byte-exact (select-layout "$ORIG_LAYOUT") and the client returns to the original session/window.
test_restore_cancel_layout_exact() {
	attach_test_client
	local layout_before sess_before win_before

	# Capture the client's ORIGINAL active-window layout + session + window id BEFORE activate
	# (the driver's active window is the baseline 'extra' multi-pane window — read it live).
	layout_before="$(tmux display-message -p '#{window_layout}')"
	sess_before="$(tmux display-message -p '#{session_name}')"
	win_before="$(tmux display-message -p '#{window_id}')"

	"$LIVEPICKER_SCRIPTS/livepicker.sh"
	"$LIVEPICKER_SCRIPTS/input-handler.sh" next-session     # link a candidate window (changes the layout)
	"$LIVEPICKER_SCRIPTS/input-handler.sh" cancel           # restore: unlink + select ORIG_WINDOW + select-layout

	# PRD §15.21 b4: the pane layout round-trips through select-layout ORIG_LAYOUT byte-for-byte.
	assert_eq "$(tmux display-message -p '#{window_layout}')" "$layout_before" \
		"original window's pane layout byte-exact after restore (select-layout ORIG_LAYOUT)"
	assert_eq "$(tmux display-message -p '#{session_name}')" "$sess_before" \
		"client back on the original session"
	assert_eq "$(tmux display-message -p '#{window_id}')" "$win_before" \
		"client back on the original window"
}
