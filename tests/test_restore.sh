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

# test_restore_preserves_custom_status_format_low_indices — M2 fix: a genuine user
# override of status-format[0], [1], or [2] MUST round-trip through activate -> cancel.
# The old shortcut saved only indices >= 3 (assuming 0-2 were always tmux defaults),
# which destroyed a real user override of [0,1,2] on exit. The fix saves EVERY
# materialized index (0-9) and replays it after the -gu reset.
test_restore_preserves_custom_status_format_low_indices() {
	attach_test_client
	local sf0_b sf1_b sf2_b sf3_b sf0_a sf1_a sf2_a sf3_a

	# Set genuine user overrides at indices 0, 1, 2, AND 3 (3 was always saved; 0-2 are the fix).
	tmux set-option -g 'status-format[0]' '#[fg=red]custom-zero'
	tmux set-option -g 'status-format[1]' '#[fg=green]custom-one'
	tmux set-option -g 'status-format[2]' '#[fg=yellow]custom-two'
	tmux set-option -g 'status-format[3]' '#[fg=blue]custom-three'

	sf0_b="$(tmux show-option -gqv 'status-format[0]' 2>/dev/null)"
	sf1_b="$(tmux show-option -gqv 'status-format[1]' 2>/dev/null)"
	sf2_b="$(tmux show-option -gqv 'status-format[2]' 2>/dev/null)"
	sf3_b="$(tmux show-option -gqv 'status-format[3]' 2>/dev/null)"

	"$LIVEPICKER_SCRIPTS/livepicker.sh" >/dev/null
	"$LIVEPICKER_SCRIPTS/input-handler.sh" cancel >/dev/null

	sf0_a="$(tmux show-option -gqv 'status-format[0]' 2>/dev/null)"
	sf1_a="$(tmux show-option -gqv 'status-format[1]' 2>/dev/null)"
	sf2_a="$(tmux show-option -gqv 'status-format[2]' 2>/dev/null)"
	sf3_a="$(tmux show-option -gqv 'status-format[3]' 2>/dev/null)"

	assert_eq "$sf0_a" "$sf0_b" "status-format[0] (custom user override) preserved across restore"
	assert_eq "$sf1_a" "$sf1_b" "status-format[1] (custom user override) preserved across restore"
	assert_eq "$sf2_a" "$sf2_b" "status-format[2] (custom user override) preserved across restore"
	assert_eq "$sf3_a" "$sf3_b" "status-format[3] (custom user override) preserved across restore"
}

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
