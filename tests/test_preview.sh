#!/usr/bin/env bash
# tests/test_preview.sh — tmux-livepicker PRD §15.19 Live all-panes preview + §7
# Fallbacks validation (P1.M7.T4.S1).
#
# SOURCED by run.sh (NEVER executed directly). Defines four test_* functions that drive
# the COMPLETE real scripts/preview.sh (P1.M3.T1.S1+S2) DIRECTLY (contract §1:
# `preview.sh S`; NOT via keypress, NOT via livepicker.sh) against the socket-isolated
# server the harness provides (tests/setup_socket.sh P1.M7.T1.S1 + tests/helpers.sh
# P1.M7.T2.S1), and assert observable tmux state. Each test seeds the minimal
# @livepicker-* state preview.sh reads, exercises one §15.19 bullet (+ a §7 fallback
# probe), and signals pass/fail via fail/assert_* (which set TEST_STATUS; run.sh reads
# it in the current shell).
#
# CONTRACT: run.sh sources setup_socket.sh + helpers.sh + every tests/test_*.sh, then
# PER test calls setup_test "lp-$$-<name>" (-> fresh isolated socket + PATH shim +
# baseline fixtures driver/alpha/beta) -> resets TEST_STATUS=pass -> runs the test_* in
# the CURRENT shell -> reads TEST_STATUS -> teardown_test. So when a test_* runs: bare
# `tmux` hits the isolated socket; $LIVEPICKER_SCRIPTS, TEST_DRIVER_SESSION, fail/pass/
# assert_eq/assert_contains are all IN SCOPE; this file SOURCES NOTHING and calls NO
# setup_test/teardown_test.
#
# CRITICAL (research FINDING 1): preview.sh is CLIENT-INDEPENDENT — it reads the driver
# session name from @livepicker-orig-session (NOT display-message). So NO
# attach_test_client (unlike T3.S1, whose livepicker.sh activate uses display-message).
#
# CRITICAL (research FINDING 7): the work-item's literal "already-linked-singly" trigger
# CANNOT fail link-window on tmux 3.6b (it duplicates, rc=0). test_capture_fallback uses
# the TWO correct deterministic triggers (FINDING 8: snapshot-mode gate + bogus-driver
# link failure).
#
# `set -u` is INHERITED from helpers.sh (do NOT re-declare; mirror test_self.sh).
# shellcheck disable=SC2154,SC2016,SC2034,SC2086
#   SC2154: assert_*/fail/$LIVEPICKER_SCRIPTS/$TEST_DRIVER_SESSION are defined by run.sh's
#           sources, not in this file.

# lp_preview_seed_state — set the MINIMAL @livepicker-* state preview.sh reads. preview.sh
# is CLIENT-INDEPENDENT (FINDING 1): it reads the driver from @livepicker-orig-session
# (get_state), the self-session window from @livepicker-orig-window, and the prior link
# from @livepicker-linked-id. It does NOT read @livepicker-mode/list/filter/index, status,
# or key-table -> no full activate needed. The literal key strings are stable state.sh
# contract constants (NO sourcing — mirror T3.S1's lp_runtime_cleared).
lp_preview_seed_state() {
	local drv_win
	# The driver's ACTIVE window id, read DYNAMICALLY (window ids are GLOBAL; the
	# baseline seed makes driver's active window the "extra" @N, NOT @0 — FINDING 3).
	drv_win="$(tmux list-windows -t "=$TEST_DRIVER_SESSION" -F '#{window_id}' -f '#{window_active}')"
	tmux set-option -g @livepicker-orig-session "$TEST_DRIVER_SESSION"
	tmux set-option -g @livepicker-orig-window "$drv_win"
	tmux set-option -g @livepicker-linked-id ""
}

# test_multipane_preview — PRD §15.19 bullet 1: a multi-pane candidate links into the
# driver; the linked window id is in BOTH sessions; all panes render live (a linked
# window is the SAME object in both sessions — FINDING 4).
test_multipane_preview() {
	lp_preview_seed_state
	# A candidate session with a 3-pane active window (PRD §15.19 b1).
	tmux new-session -d -s multi -x 120 -y 40
	tmux split-window -h -t multi
	tmux split-window -v -t multi
	# Window ids are GLOBAL — read the candidate's active window id DYNAMICALLY (FINDING 3).
	local multi_wid
	multi_wid="$(tmux list-windows -t '=multi' -F '#{window_id}' -f '#{window_active}')"
	"$LIVEPICKER_SCRIPTS/preview.sh" multi
	# PRD §15.19 b1: the linked window id appears in BOTH the driver AND the source; all
	# panes render live (a linked window is the SAME object in both sessions).
	assert_contains "$(tmux list-windows -t "=$TEST_DRIVER_SESSION" -F '#{window_id}')" \
		"$multi_wid" "linked window present in the driver session"
	assert_contains "$(tmux list-windows -t '=multi' -F '#{window_id}')" \
		"$multi_wid" "source session keeps its window (link is shared, not moved)"
	assert_eq "$(tmux list-windows -t "=$TEST_DRIVER_SESSION" -F '#{window_id}' -f '#{window_active}')" \
		"$multi_wid" "driver's current window is multi's linked window (all panes visible)"
	# All panes visible: a linked window's panes are queryable by id from either session.
	local _panes
	mapfile -t _panes < <(tmux list-panes -t "$multi_wid" -F '#{pane_id}')
	assert_eq "${#_panes[@]}" "3" "linked window renders all 3 panes live"
	assert_eq "$(tmux show-option -gqv @livepicker-linked-id)" "$multi_wid" \
		"@livepicker-linked-id tracks the linked window id"
}

# test_navigate_unlinks_intact — PRD §15.19 bullet 2: navigating away unlinks the prior
# preview from the driver, but the source session KEEPS its window (unlink without -k
# removes ONE link — FINDING 5). The before/after list-windows diff is the proof.
test_navigate_unlinks_intact() {
	lp_preview_seed_state
	# Two candidates: a fresh `multi` + the baseline `alpha`.
	tmux new-session -d -s multi -x 120 -y 40
	tmux split-window -h -t multi
	local multi_wid alpha_wid
	multi_wid="$(tmux list-windows -t '=multi' -F '#{window_id}' -f '#{window_active}')"
	# preview multi first (links multi into the driver).
	"$LIVEPICKER_SCRIPTS/preview.sh" multi
	# Capture the BEFORE state of the source session (the §15.19 b2 before/after diff).
	local multi_before
	multi_before="$(tmux list-windows -t '=multi' -F '#{window_id}')"
	# Navigate away: preview alpha -> unlink multi from the driver, link alpha.
	alpha_wid="$(tmux list-windows -t '=alpha' -F '#{window_id}' -f '#{window_active}')"
	"$LIVEPICKER_SCRIPTS/preview.sh" alpha
	# PRD §15.19 b2: multi's window is NO LONGER in the driver (unlinked)...
	case "$(tmux list-windows -t "=$TEST_DRIVER_SESSION" -F '#{window_id}')" in
		*"$multi_wid"*) fail "multi's window still linked in the driver after navigating away" ;;
	esac
	# ...but multi's window list is UNCHANGED (intact in its own session — unlink without
	# -k removes ONE link; the source keeps its window — preview.sh FINDING 1/11).
	assert_eq "$(tmux list-windows -t '=multi' -F '#{window_id}')" "$multi_before" \
		"multi's window intact in its own session (before/after diff)"
	assert_eq "$(tmux show-option -gqv @livepicker-linked-id)" "$alpha_wid" \
		"@livepicker-linked-id now tracks alpha's window"
}

# test_self_session_no_link — PRD §15.19 bullet 3: previewing the driver's OWN session
# never links (would create an in-session duplicate). preview.sh's self-session guard
# clears linked_id + select-window ORIG_WINDOW WITHOUT linking — FINDING 6.
test_self_session_no_link() {
	lp_preview_seed_state
	# The driver's ORIGINAL active window + its window list (for the "no link attempted" proof).
	local drv_wid drv_before
	drv_wid="$(tmux show-option -gqv @livepicker-orig-window)"
	drv_before="$(tmux list-windows -t "=$TEST_DRIVER_SESSION" -F '#{window_id}')"
	# PRD §15.19 b3: preview the driver's OWN session -> no link (would create an in-session
	# duplicate). preview.sh's self-session guard clears linked_id + select-window ORIG_WINDOW.
	"$LIVEPICKER_SCRIPTS/preview.sh" "$TEST_DRIVER_SESSION"
	assert_eq "$(tmux show-option -gqv @livepicker-linked-id)" "" \
		"self-session leaves @livepicker-linked-id empty (no link)"
	assert_eq "$(tmux list-windows -t "=$TEST_DRIVER_SESSION" -F '#{window_id}' -f '#{window_active}')" \
		"$drv_wid" "self-session selects the ORIGINAL window"
	assert_eq "$(tmux list-windows -t "=$TEST_DRIVER_SESSION" -F '#{window_id}')" "$drv_before" \
		"self-session created no duplicate window (no link-window attempted)"
}

# test_capture_fallback — PRD §7 Fallbacks: BOTH deterministic capture-pane triggers
# (FINDING 8). (a) the @livepicker-preview-mode=snapshot gate calls preview_fallback
# before any link; (b) a NON-EXISTENT driver makes link-window FAIL rc=1 -> the real
# `if ! tmux link-window` fallback branch fires. Both run capture-pane on a REAL
# candidate -> capture SUCCEEDS (rc=0). The contract's "already-linked-singly" trigger
# CANNOT fail (it duplicates, rc=0) — FINDING 7 — so it is NOT used here.
test_capture_fallback() {
	lp_preview_seed_state
	# A REAL candidate (capture-pane needs a live pane — FINDING 9: target is =$S:.).
	tmux new-session -d -s cand -x 120 -y 40
	tmux split-window -h -t cand

	# --- (a) SNAPSHOT-mode gate (PRD §7): capture-pane path, never links. ---
	tmux set-option -g @livepicker-preview-mode snapshot
	# FINDING 11: snapshot returns before state mutation -> re-seed linked-id="".
	tmux set-option -g @livepicker-linked-id ""
	"$LIVEPICKER_SCRIPTS/preview.sh" cand \
		|| fail "snapshot-mode preview returned non-zero (capture-pane path errored)"
	assert_eq "$(tmux show-option -gqv @livepicker-linked-id)" "" \
		"snapshot mode leaves no link"
	tmux set-option -g @livepicker-preview-mode live   # reset

	# --- (b) LINK-FAILURE branch (the faithful "force a link failure"): a NON-EXISTENT
	#     driver makes `link-window -t "no-such:"` FAIL rc=1 ("can't find session") -> the
	#     real `if ! tmux link-window …` fallback branch fires. cand is REAL -> capture
	#     succeeds. (The contract's "already-linked-singly" CANNOT fail — FINDING 7.) ---
	tmux set-option -g @livepicker-orig-session "no-such-session-xyz"
	tmux set-option -g @livepicker-linked-id ""
	"$LIVEPICKER_SCRIPTS/preview.sh" cand \
		|| fail "link-failure preview returned non-zero (capture-pane path errored)"
	assert_eq "$(tmux show-option -gqv @livepicker-linked-id)" "" \
		"failed link leaves no linked-id"
}

# test_window_preview_shows_highlighted_window — Bugfix Issue 4: in WINDOW mode
# the picker lists 'session:window_index' tokens (livepicker.sh:103) and preview.sh
# is called with such a token. The candidate may be the session's NON-active window.
# preview.sh must link the window at the given INDEX, NOT the session's active
# window (the #{window_active} filter ignores the index). Creates a session with
# TWO windows, dynamically detects the NON-active window's index + @id (base-index
# may be 0 or 1 — the isolated server inherits ~/.tmux.conf; `new-window -t multi`
# FAILS "index 1 in use" on base-index=1, so use -a + detect dynamically), calls
# preview.sh 'multi:<non_active_index>', and asserts @livepicker-linked-id equals
# the HIGHLIGHTED window's @id (NOT the active window's @id). Before the fix,
# linked-id == the active window's @id (the bug). preview.sh is client-independent
# (reads @livepicker-orig-session from state) -> NO attach_test_client.
test_window_preview_shows_highlighted_window() {
	lp_preview_seed_state
	# Window mode: opt_type gates the new resolution branch. lp_preview_seed_state
	# does NOT set type -> set it explicitly.
	tmux set-option -g @livepicker-type window
	# A candidate session with TWO windows. base-index may be 0 or 1 (inherited
	# from ~/.tmux.conf); create the 2nd window with -a (append — a bare
	# `new-window -t multi` FAILS "index 1 in use" on base-index=1). new-window
	# makes the new window ACTIVE, so the FIRST window is NON-active.
	tmux new-session -d -s multi -x 120 -y 40
	tmux new-window -t multi -a -n secondwin
	# Dynamically detect the NON-active window's index + @id (the highlight target).
	# Space-delimited to avoid any ':' ambiguity in @ids (which are clean @N).
	local nonactive na_idx na_id active_id
	nonactive="$(tmux list-windows -t '=multi' -F '#{window_index} #{window_id} #{window_active}' | awk '$3==0 {print $1" "$2; exit}')"
	na_idx="${nonactive%% *}"
	na_id="${nonactive#* }"
	active_id="$(tmux list-windows -t '=multi' -F '#{window_id}' -f '#{window_active}')"
	# Sanity: the non-active window differs from the active one (proves the bug is
	# reachable — if equal, the test would be vacuous; fail loudly on bad setup).
	assert_contains "$na_id" "@" "non-active window resolved to a @id handle"
	if [ "$na_id" = "$active_id" ]; then
		fail "test setup invalid: non-active window == active window (need 2 distinct windows)"
		return 0
	fi
	# Preview the NON-active window's token (session:index).
	"$LIVEPICKER_SCRIPTS/preview.sh" "multi:$na_idx"
	# The linked window MUST be the HIGHLIGHTED (non-active) window, NOT the
	# session's active window. Before the fix, linked-id == active_id (the bug).
	assert_eq "$(tmux show-option -gqv @livepicker-linked-id)" "$na_id" \
		"window-mode preview links the highlighted window (by index), not the active window"
	# Belt-and-braces: prove it is NOT the active window's id.
	if [ "$(tmux show-option -gqv @livepicker-linked-id)" = "$active_id" ]; then
		fail "window-mode preview linked the ACTIVE window (the bug)"
	fi
}
