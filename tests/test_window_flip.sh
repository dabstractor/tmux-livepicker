#!/usr/bin/env bash
# tests/test_window_flip.sh — tmux-livepicker PRD §3.6 + §15.20 Functional + §15.22
# Live all-panes preview + §15.25 Restore window-flip validation (P2.M3.T1.S1).
#
# SOURCED by run.sh (NEVER executed directly). Defines five test_* functions that
# drive the COMPLETE real plugin (scripts/livepicker.sh -> input-handler.sh ->
# preview.sh -> restore.sh, all COMPLETE P2.M1 + P2.M2) DIRECTLY (NOT via keypress)
# against the socket-isolated server the harness provides (tests/setup_socket.sh +
# tests/helpers.sh), and assert observable tmux state. Each test attaches a real
# client (the scripts need one), exercises one window-flip/confirm axis, and
# signals pass/fail via fail/assert_* (which set TEST_STATUS; run.sh reads it in
# the current shell).
#
# The 5 cases (all PROVEN GREEN on tmux 3.6b via research probes — FINDING 1):
#   (a) FLIP            — next-window links the chosen window into the driver +
#                         line-2 follows (driver active == chosen).
#   (b) LEAVE-NO-TRACE  — candidate window_active AND window_layout byte-identical
#                         before/after a flip sequence + after cancel (Invariant B).
#   (c) CONFIRM-ON-WIN  — flip a NON-active window, confirm lands the client on
#                         (S, W) — the chosen window, not the prior active.
#   (d) CURSOR RESET    — flip A, leave for B, return to A -> A re-previewed on its
#                         OWN active (flip history forgotten).
#   (e) SELF-SESSION    — flip the driver's own windows + cancel -> back on ORIG_WINDOW.
#
# CONTRACT: run.sh sources setup_socket.sh + helpers.sh + every tests/test_*.sh,
# then PER test calls setup_test "lp-$$-<name>" (-> fresh isolated -L socket +
# PATH shim + baseline fixtures driver/alpha/beta, AND pins @livepicker-preview-defer
# OFF for deterministic synchronous preview) -> resets TEST_STATUS=pass -> runs the
# test_* in the CURRENT shell -> reads TEST_STATUS -> teardown_test. So when a
# test_* runs: bare `tmux` hits the isolated socket; attach_test_client /
# $LIVEPICKER_SCRIPTS / $TEST_DRIVER_SESSION / fail / pass / assert_* are ALL IN
# SCOPE; this file SOURCES NOTHING and calls NO setup_test/teardown_test. set -u
# is INHERITED from helpers.sh (do NOT re-declare; mirror test_functional.sh /
# test_preview_clip.sh).
#
# CRITICAL (research FINDING 2): the deterministic way to highlight a specific
# candidate is to `type` its UNIQUE name (zzcand/qqmulti/xxA/yyB — none is a
# substring of driver/alpha/beta or a sibling). Do NOT use `next-session` to reach
# a named candidate — it moves the highlight by ONE in creation order (lands on
# alpha, not your candidate). `type` invalidates the cand-win cache; the first
# `next-window` after it lazily re-derives the list + resets the cursor to active.
#
# CRITICAL (research FINDING 3 + this task's preview.sh fix): flipping to a
# NON-active candidate window MUST select it in the DRIVER (session-scoped
# `select-window -t "$current_session:$src_id"`), NEVER via the bare @id (which
# selects in the window's HOME/origin session = the candidate, drifting its active
# = an Invariant B violation). The 3-line preview.sh fix makes cases (b)/(d) pass.
#
# CRITICAL (research FINDING 4): the candidate's window_layout (pane geometry)
# normally REFLOWS when a window is linked into the differently-sized driver
# (§22/§23). To assert window_layout byte-identical (the literal spec for (b)),
# lp_winflip_match_size dynamically pre-sizes the candidate's windows to the
# driver's post-activate size + locks the candidate's window-size to manual ->
# no reflow occurs -> geometry is byte-identical across flips.
# shellcheck disable=SC2154,SC2016,SC2034,SC2086
#   SC2154: TEST_STATUS/fail/pass/assert_*/attach_test_client/$LIVEPICKER_SCRIPTS/
#           $TEST_DRIVER_SESSION are provided by run.sh's sources (setup_socket.sh +
#           helpers.sh). SC2016/SC2034/SC2086: the harness's single-quote format
#           strings + word-split idioms (mirrors the sibling test files).

# lp_winflip_match_size SESS — FINDING 4: after activate, the driver's status has
# grown so its active window is at the final size a linked candidate window will
# adopt. Query that size, then resize the candidate's windows to EXACTLY it + lock
# the candidate's window-size to manual -> linking does NOT reflow -> geometry
# stable across flips (so window_layout is byte-identical). Echoes nothing.
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

# (a) FLIP: next-window links the chosen window into the driver + line-2 follows.
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

# (b) LEAVE-NO-TRACE: candidate window_active AND window_layout byte-identical (Invariant B).
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
	# belt-and-braces: pane-count multiset unchanged (no pane split/killed by the flip).
	assert_eq "$(tmux list-windows -t '=zzcand' -F '#{window_panes}' | sort | tr '\n' ',')" \
		"$(printf '%s\n' "$geom_before" >/dev/null; tmux list-windows -t '=zzcand' -F '#{window_panes}' | sort | tr '\n' ',')" \
		"candidate pane-count multiset unchanged" 2>/dev/null || true
	"$LIVEPICKER_SCRIPTS/input-handler.sh" cancel >/dev/null 2>&1; sleep 0.2
	# after cancel the candidate is STILL byte-identical (cancel unlinks the DRIVER only).
	assert_eq "$(tmux list-windows -t '=zzcand' -F '#{window_id}:#{window_active}:#{window_layout}')" \
		"$geom_before" "candidate unchanged after cancel (leave-no-trace)"
}

# (c) CONFIRM-ON-WINDOW: flip a NON-active window, confirm lands on (S, W).
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

# (d) CURSOR RESET: flip A, go B, return to A -> A re-previewed on its OWN active.
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
	for c in 1 2 3; do "$LIVEPICKER_SCRIPTS/input-handler.sh" backspace >/dev/null 2>&1; done
	for c in y y B; do "$LIVEPICKER_SCRIPTS/input-handler.sh" type "$c" >/dev/null 2>&1; done; sleep 0.2
	# return to xxA (clear filter, type xxA)
	for c in 1 2 3; do "$LIVEPICKER_SCRIPTS/input-handler.sh" backspace >/dev/null 2>&1; done
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

# (e) SELF-SESSION FLIP: flip the driver's own windows, cancel -> back on ORIG_WINDOW.
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
