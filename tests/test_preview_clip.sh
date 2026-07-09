#!/usr/bin/env bash
# tests/test_preview_clip.sh — tmux-livepicker PRD §15.22 + §22 clip/reflow validation (P3.M2.T1.S1).
# Drives the REAL scripts/livepicker.sh activate + scripts/restore.sh (via input-handler.sh cancel) +
# scripts/preview.sh (candidate link) on the isolated -L harness WITH an attached client (the freeze
# reads display-message -p '#{window_height}'). Cites P3.M1.T1.S1 clip_probe_findings.md (assert shapes)
# + clip_verification.md (the GATE) + P3.M1.T2.S1 PRP (the SUT). Mirrors test_scroll_width.sh's
# activate/restore lifecycle (NOT test_preview.sh, which skips the client — preview.sh is client-
# independent; clip is NOT).
#
# CONTRACT: run.sh sources setup_socket.sh + helpers.sh + every tests/test_*.sh, then PER test calls
# setup_test "lp-$$-<name>" (-> fresh isolated -L socket + baseline fixtures, AND pins
# @livepicker-preview-defer OFF so nav preview is SYNCHRONOUS — no race on the candidate-residual
# asserts). So when a test_* runs: bare `tmux` hits the isolated socket; attach_test_client /
# $LIVEPICKER_SCRIPTS / $TEST_DRIVER_SESSION / fail / assert_* are IN SCOPE; this file SOURCES NOTHING
# and calls NO setup_test/teardown_test. set -u is INHERITED from helpers.sh (do NOT re-declare).
# shellcheck disable=SC2154,SC2016,SC2034,SC2086
#   SC2154: TEST_STATUS/fail/assert_*/attach_test_client/$LIVEPICKER_SCRIPTS/$TEST_DRIVER_SESSION are
#           provided by run.sh's sources (setup_socket.sh + helpers.sh). SC2016/SC2034/SC2086: the
#           harness's single-quote format strings + word-split idioms (mirrors the sibling test files).

# _lp_clip_setup [fit] — attach a client, set @livepicker-preview-fit, ACTIVATE the picker. Caller
# captures the BEFORE state (AW/L0/H0/window-size) BEFORE calling this (it runs livepicker.sh).
_lp_clip_setup() {
	local fit="${1:-clip}"
	attach_test_client
	tmux set-option -g @livepicker-preview-fit "$fit"
	"$LIVEPICKER_SCRIPTS/livepicker.sh" >/dev/null
	sleep 0.3   # let the synchronous resize-pin + status grow settle
}

# (a) §22 no-reflow: the self-window (driver active == ORIG_WINDOW) is byte-identical across the grow.
test_clip_self_window_no_reflow() {
	attach_test_client
	tmux set-option -g @livepicker-preview-fit clip
	local AW L0 H0
	AW="$(tmux list-windows -t "=$TEST_DRIVER_SESSION" -F '#{window_id}' -f '#{window_active}')"
	L0="$(tmux display-message -p -t "$AW" '#{window_layout}')"
	H0="$(tmux display-message -p -t "$AW" '#{window_height}')"
	"$LIVEPICKER_SCRIPTS/livepicker.sh" >/dev/null
	sleep 0.3
	# the active window is still ORIG_WINDOW (first preview is the self-session -> select, no link)
	local AW2 L1 H1
	AW2="$(tmux list-windows -t "=$TEST_DRIVER_SESSION" -F '#{window_id}' -f '#{window_active}')"
	L1="$(tmux display-message -p -t "$AW2" '#{window_layout}')"
	H1="$(tmux display-message -p -t "$AW2" '#{window_height}')"
	assert_eq "$AW2" "$AW"  'self-session: active window unchanged (no link on first preview)'
	assert_eq "$L1" "$L0"   'clip: self-window layout unchanged across status grow (no reflow)'
	assert_eq "$H1" "$H0"   'clip: self-window height pinned (clip, not reflow)'
	assert_eq "$(tmux show-options -gv status)" "2"            'clip: status grew to 2'
	assert_eq "$(tmux show-options -t "$TEST_DRIVER_SESSION" -v window-size 2>/dev/null || true)" "manual" \
		'clip: driver window-size frozen to manual (the freeze ran)'
	"$LIVEPICKER_SCRIPTS/input-handler.sh" cancel >/dev/null
}

# (b) §22 residual / §16 limitation: linked candidate reflows ONCE at link time; NO per-nav reflow.
test_clip_candidate_no_per_nav_reflow() {
	_lp_clip_setup clip        # self pinned (status grown); activate set ORIG_SESSION/ORIG_WINDOW
	# alpha/beta are baseline detached sessions (source size 40) — link them via the direct seam.
	local alpha_wid LA1 alpha_wid2 LA2
	"$LIVEPICKER_SCRIPTS/preview.sh" alpha; sleep 0.2          # link alpha: 40 -> driver usable (one-time)
	alpha_wid="$(tmux list-windows -t "=$TEST_DRIVER_SESSION" -F '#{window_id}' -f '#{window_active}')"
	LA1="$(tmux display-message -p -t "$alpha_wid" '#{window_layout}')"
	"$LIVEPICKER_SCRIPTS/preview.sh" beta;  sleep 0.2          # unlink alpha, link beta
	"$LIVEPICKER_SCRIPTS/preview.sh" alpha; sleep 0.2          # re-link alpha
	alpha_wid2="$(tmux list-windows -t "=$TEST_DRIVER_SESSION" -F '#{window_id}' -f '#{window_active}')"
	LA2="$(tmux display-message -p -t "$alpha_wid2" '#{window_layout}')"
	assert_eq "$LA2" "$LA1" 'candidate: no per-nav additional reflow (link-time resize only)'
	"$LIVEPICKER_SCRIPTS/input-handler.sh" cancel >/dev/null
}

# (c) §9/§15 restore + zero-trace: window-size byte-exact (unset->unset); global never touched; panes natural.
test_clip_restore_window_size_byte_exact() {
	attach_test_client
	tmux set-option -g @livepicker-preview-fit clip
	local ws_sess_before ws_global_before status_before H0
	ws_sess_before="$(tmux show-options -t "$TEST_DRIVER_SESSION" -v window-size 2>/dev/null || true)"   # ""
	ws_global_before="$(tmux show-options -g -v window-size)"
	status_before="$(tmux show-options -gv status)"
	H0="$(tmux display-message -p -t "$(tmux list-windows -t "=$TEST_DRIVER_SESSION" -F '#{window_id}' -f '#{window_active}')" '#{window_height}')"
	"$LIVEPICKER_SCRIPTS/livepicker.sh" >/dev/null; sleep 0.3
	# precondition: the freeze ran (driver is manual)
	assert_eq "$(tmux show-options -t "$TEST_DRIVER_SESSION" -v window-size 2>/dev/null || true)" "manual" \
		'restore precondition: freeze set window-size manual'
	"$LIVEPICKER_SCRIPTS/input-handler.sh" cancel >/dev/null; sleep 0.3
	local ws_sess_after ws_global_after status_after H_after
	ws_sess_after="$(tmux show-options -t "$TEST_DRIVER_SESSION" -v window-size 2>/dev/null || true)"
	ws_global_after="$(tmux show-options -g -v window-size)"
	status_after="$(tmux show-options -gv status)"
	H_after="$(tmux display-message -p -t "$(tmux list-windows -t "=$TEST_DRIVER_SESSION" -F '#{window_id}' -f '#{window_active}')" '#{window_height}')"
	assert_eq "$ws_sess_after" "$ws_sess_before" 'restore: driver window-size byte-exact (unset->unset)'
	assert_eq "$ws_global_after" "$ws_global_before" 'restore: global window-size never touched (PRD §15)'
	assert_eq "$status_after" "$status_before" 'restore: status restored (2->on)'
	assert_eq "$H_after" "$H0" 'restore: panes returned to natural size (height back to pre-activate)'
}

# (d) §22 "Control" reflow escape hatch: window-size NEVER touched; status grows; window DOES reflow.
test_reflow_fallback_grows_and_restores() {
	attach_test_client
	tmux set-option -g @livepicker-preview-fit reflow
	local ws_sess_before ws_global_before L0 H0
	ws_sess_before="$(tmux show-options -t "$TEST_DRIVER_SESSION" -v window-size 2>/dev/null || true)"
	ws_global_before="$(tmux show-options -g -v window-size)"
	L0="$(tmux display-message -p -t "$(tmux list-windows -t "=$TEST_DRIVER_SESSION" -F '#{window_id}' -f '#{window_active}')" '#{window_layout}')"
	H0="$(tmux display-message -p -t "$(tmux list-windows -t "=$TEST_DRIVER_SESSION" -F '#{window_id}' -f '#{window_active}')" '#{window_height}')"
	"$LIVEPICKER_SCRIPTS/livepicker.sh" >/dev/null; sleep 0.3
	local ws_sess_after status_now L1 H1
	ws_sess_after="$(tmux show-options -t "$TEST_DRIVER_SESSION" -v window-size 2>/dev/null || true)"
	status_now="$(tmux show-options -gv status)"
	L1="$(tmux display-message -p -t "$(tmux list-windows -t "=$TEST_DRIVER_SESSION" -F '#{window_id}' -f '#{window_active}')" '#{window_layout}')"
	H1="$(tmux display-message -p -t "$(tmux list-windows -t "=$TEST_DRIVER_SESSION" -F '#{window_id}' -f '#{window_active}')" '#{window_height}')"
	assert_eq "$ws_sess_after" "$ws_sess_before" 'reflow: window-size untouched on activate (clip gate skipped)'
	assert_eq "$status_now" "2" 'reflow: status DID grow (legacy path)'
	[ "$L0" != "$L1" ] || fail 'reflow: window SHOULD have reflowed across the grow (layout changed 23->22)'
	[ "$H0" != "$H1" ] || fail 'reflow: height SHOULD have changed (23->22)'
	"$LIVEPICKER_SCRIPTS/input-handler.sh" cancel >/dev/null; sleep 0.3
	assert_eq "$(tmux show-options -t "$TEST_DRIVER_SESSION" -v window-size 2>/dev/null || true)" "$ws_sess_before" \
		'reflow: window-size still untouched after restore'
	assert_eq "$(tmux show-options -g -v window-size)" "$ws_global_before" 'reflow: global window-size never touched'
}
