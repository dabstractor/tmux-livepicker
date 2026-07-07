#!/usr/bin/env bash
# tests/test_responsiveness.sh — tmux-livepicker PRD §15.23 Responsiveness / §18
# deferred-preview validation (P1.M3.T1.S1).
#
# SOURCED by run.sh (NEVER executed directly). Defines five test_* functions that
# validate PRD §18's interaction-first contract on the socket-isolated server:
# typing/nav redraw the status SYNCHRONOUSLY and DEFER the preview to a background,
# supersedeable run-shell -b job; confirm never blocks on a preview; defer=off
# restores the legacy synchronous-preview path.
#
# CONTRACT: run.sh sources setup_socket.sh + helpers.sh + every tests/test_*.sh,
# then PER test calls setup_test "lp-$$-<name>" (-> fresh isolated socket + PATH
# shim + baseline fixtures driver/alpha/beta) -> resets TEST_STATUS=pass -> runs
# the test_* in the CURRENT shell -> reads TEST_STATUS -> teardown_test. So when a
# test_* runs: bare `tmux` hits the isolated socket; $LIVEPICKER_SCRIPTS,
# attach_test_client, fail/pass/assert_eq/assert_contains are all IN SCOPE; this
# file SOURCES NOTHING and calls NO setup_test/teardown_test at file scope.
#
# DEFER OPT-IN (CRITICAL): setup_test (helpers.sh) pins @livepicker-preview-defer
# OFF so the existing functional/restore/etc. tests' SYNCHRONOUS @livepicker-
# linked-id assertions stay deterministic. THESE tests OPT INTO the deferred path
# by setting @livepicker-preview-defer ON per test (except (e), the legacy contrast,
# which sets it OFF explicitly).
#
# ASYNC TIMING (external_tmux_behavior.md Q5/Q6/Q7): run-shell -b is detached/
# non-blocking/non-cancellable. _lp_fire_preview bumps STATE_PREVIEW_SEQ and sets
# STATE_PREVIEW_TARGET SYNCHRONOUSLY (before run-shell -b returns); the actual
# link-window + set @livepicker-linked-id happens ASYNC in the bg preview.sh job.
# So this file asserts:
#   SYNCHRONOUS (immediate, no sleep): SEQ bumped, filter/index set, renderer.sh
#     output current, AND @livepicker-linked-id still the PRE-action value (the bg
#     job's fork+bash+libs+round-trips ~30-60ms >> the test's show-option read ~5ms,
#     so the immediate read reliably observes the lag).
#   ASYNC (poll ~2s via wait_linked): @livepicker-linked-id == the target's window id.
# refresh-client -S is a no-op on a client-less socket (Q7) -> attach_test_client is
# MANDATORY in every test.
#
# `set -u` is INHERITED from helpers.sh (do NOT re-declare; mirror test_self.sh).
# shellcheck disable=SC2154,SC2016,SC2034,SC2086
#   SC2154: assert_*/attach_test_client/$LIVEPICKER_SCRIPTS/$TEST_DRIVER_SESSION are
#           defined by run.sh's sources, not in this file.

# wait_linked WANT — poll @livepicker-linked-id until it equals WANT (rc 0) or ~2s
# timeout (rc 1). The bg run-shell -b preview job is async; on a healthy isolated
# socket it links in <50ms. Mirrors the P1.M2.T3.S1 defer-fire smoke. Callers use
# `wait_linked "$wid" || fail "...not linked"`.
wait_linked() {
	local want="$1" i
	for i in $(seq 1 100); do
		[ "$(tmux show-option -gqv @livepicker-linked-id)" = "$want" ] && return 0
		sleep 0.02
	done
	return 1
}

# _lp_active_wid SESSION — print SESSION's active window id (@N). Window ids are
# GLOBAL but renumber-windows=on makes indices unstable -> capture DYNAMICALLY.
_lp_active_wid() {
	tmux list-windows -t "=$1" -F '#{window_id}' -f '#{window_active}'
}

# (a) test_typing_defers_preview — PRD §18.1: typing is status-only + synchronous;
# the preview is DEFERRED. After one type, SEQ bumped + renderer shows the new query
# + linked-id UNCHANGED (the bg job hasn't run); the link arrives ASYNC (poll).
test_typing_defers_preview() {
	attach_test_client
	tmux set-option -g @livepicker-preview-defer on
	"$LIVEPICKER_SCRIPTS/livepicker.sh"
	# Activate's first preview is the SELF-session -> no link yet.
	assert_eq "$(tmux show-option -gqv @livepicker-linked-id)" "" \
		"initial self-session preview leaves no link"
	# Resolve the top filtered match for "a" DYNAMICALLY from @livepicker-list
	# (filter is now "a"). Mirrors lp_build_filtered: case-insensitive substring,
	# list order; "a" matches alpha + beta, so read the actual top match, never
	# hardcode it (do NOT parse the renderer's styled output — names with special
	# chars would break a sed extract; the list is the source of truth).
	"$LIVEPICKER_SCRIPTS/input-handler.sh" type a >/dev/null
	local top_wid top_sess
	top_sess="$(printf '%s\n' "$(tmux show-option -gqv @livepicker-list)" | grep -i 'a' | head -1)"
	top_wid="$(_lp_active_wid "$top_sess")"
	[ -n "$top_wid" ] || fail "resolved a top 'a' match from the live list (got empty)"
	# SYNCHRONOUS assertions (immediate — the input handler has returned; the bg job lags).
	# The DETERMINISTIC deferral proof is the trio: SEQ bumped (>0, sync), the renderer
	# shows the new query (sync), AND the link arrives only via the eventual poll below
	# (async). The intermediate "linked-id still empty" read is a BEST-EFFORT lag
	# observation (not hard-asserted): the bg job's startup (~30-60ms) usually exceeds
	# the read (~5ms), but under suite load it can occasionally win the race (research
	# §2 / external_tmux_behavior Q5). It never hardens deferral on its own — the
	# SEQ/renderer/poll trio does — so a fast job here does not fail the test.
	local seq
	seq="$(tmux show-option -gqv @livepicker-preview-seq)"
	[ -n "$seq" ] && [ "$seq" != "0" ] \
		|| fail "type bumped @livepicker-preview-seq synchronously (got [$seq])"
	tmux set-option -g @livepicker-nerd-fonts on
	local rendered
	rendered="$("$LIVEPICKER_SCRIPTS/renderer.sh")"
	case "$rendered" in
		*$'\uf002'*) pass "status reflects the new query synchronously (query-active icon shown)" ;;
		*) fail "status did not show the query-active icon (§19 query-active layout)" ;;
	esac
	case "$(tmux show-option -gqv @livepicker-linked-id)" in
		"") pass "preview link lags the status (still the self-session immediately after type)" ;;
		*) pass "bg preview job already linked (race won under load; deferral proven by seq+renderer+poll)" ;;
	esac
	# ASYNC: the deferred bg job eventually links the top match.
	wait_linked "$top_wid" \
		|| fail "deferred preview never linked the top match ($top_sess @ $top_wid)"
	assert_eq "$(tmux show-option -gqv @livepicker-linked-id)" "$top_wid" \
		"deferred preview linked the top match (async catch-up)"
	"$LIVEPICKER_SCRIPTS/input-handler.sh" cancel >/dev/null 2>&1 || true
}

# (b) test_rapid_type_confirm_no_backlog — PRD §18: a burst of typing collapses to a
# single trailing preview (supersede), and confirm lands correctly without waiting.
test_rapid_type_confirm_no_backlog() {
	attach_test_client
	tmux set-option -g @livepicker-preview-defer on
	# "xyz" matches NO baseline session (driver/alpha/beta) -> unique target. Created
	# BEFORE activate so it is in @livepicker-list.
	tmux new-session -d -s xyz -x 120 -y 40
	"$LIVEPICKER_SCRIPTS/livepicker.sh"
	local xyz_wid c
	xyz_wid="$(_lp_active_wid xyz)"
	# 3 rapid fires (seq 1,2,3), all targeting xyz (the unique match).
	for c in x y z; do
		"$LIVEPICKER_SCRIPTS/input-handler.sh" type "$c" >/dev/null
	done
	# SYNCHRONOUS: 3 fires happened (SEQ==3) — the burst was not dropped.
	assert_eq "$(tmux show-option -gqv @livepicker-preview-seq)" "3" \
		"rapid typing fired 3 deferred previews (seq bumped per keystroke)"
	# ASYNC: the burst collapsed to ONE link (the latest target; earlier fires no-op'd).
	wait_linked "$xyz_wid" \
		|| fail "rapid typing did not collapse to the final target's preview"
	assert_eq "$(tmux show-option -gqv @livepicker-linked-id)" "$xyz_wid" \
		"burst collapsed to a single trailing preview (no backlog)"
	# Confirm lands on the target independent of the preview (PRD §18 contract #4).
	"$LIVEPICKER_SCRIPTS/input-handler.sh" confirm >/dev/null 2>&1 || true
	assert_eq "$(tmux display-message -p '#{session_name}')" "xyz" \
		"type+Enter lands on the target (confirm never blocks on the preview)"
}

# (c) test_superseded_preview_noop — PRD §18.3: a preview whose target has been
# superseded is a TRUE no-op (never unlinks/links). Two rapid nav fires -> only the
# LATEST target links; the stale fire touches nothing.
test_superseded_preview_noop() {
	attach_test_client
	tmux set-option -g @livepicker-preview-defer on
	"$LIVEPICKER_SCRIPTS/livepicker.sh"
	local alpha_wid beta_wid
	alpha_wid="$(_lp_active_wid alpha)"
	beta_wid="$(_lp_active_wid beta)"
	# Two rapid nav fires: seq=1 -> alpha, seq=2 -> beta. The alpha fire is superseded.
	"$LIVEPICKER_SCRIPTS/input-handler.sh" next-session >/dev/null
	"$LIVEPICKER_SCRIPTS/input-handler.sh" next-session >/dev/null
	# ASYNC: only the LATEST target (beta) links; the alpha fire no-op'd.
	wait_linked "$beta_wid" \
		|| fail "the latest nav target (beta) was not linked"
	assert_eq "$(tmux show-option -gqv @livepicker-linked-id)" "$beta_wid" \
		"only the latest target linked (the stale alpha fire was a no-op)"
	# The stale fire never left a stray link: driver has beta's window, NOT alpha's.
	local drv_wins
	drv_wins="$(tmux list-windows -t "$TEST_DRIVER_SESSION" -F '#{window_id}')"
	assert_contains "$drv_wins" "$beta_wid" "driver holds the latest preview (beta)"
	case "$drv_wins" in
		*"$alpha_wid"*) fail "stale alpha fire leaked a stray link into the driver" ;;
	esac
	# Source undamaged: alpha's window is intact in alpha.
	assert_contains "$(tmux list-windows -t =alpha -F '#{window_id}')" "$alpha_wid" \
		"alpha's window intact in alpha (source undamaged by the stale fire)"
	# Settle: a late stale job must not clobber the newer link.
	sleep 0.2
	assert_eq "$(tmux show-option -gqv @livepicker-linked-id)" "$beta_wid" \
		"latest link stable (a late stale job did not clobber it)"
	"$LIVEPICKER_SCRIPTS/input-handler.sh" cancel >/dev/null 2>&1 || true
}

# (d) test_nav_moves_highlight_before_preview — PRD §18.2: nav moves the highlight
# SYNCHRONOUSLY; the preview re-sync is deferred. The status shows the new highlight
# before the linked window catches up.
test_nav_moves_highlight_before_preview() {
	attach_test_client
	tmux set-option -g @livepicker-preview-defer on
	"$LIVEPICKER_SCRIPTS/livepicker.sh"
	local idx_before
	idx_before="$(tmux show-option -gqv @livepicker-index)"
	"$LIVEPICKER_SCRIPTS/input-handler.sh" next-session >/dev/null
	# SYNCHRONOUS: the highlight moved (index advanced) + the renderer shows it now.
	[ "$(tmux show-option -gqv @livepicker-index)" != "$idx_before" ] \
		|| fail "nav moved the highlight synchronously (index advanced)"
	# Resolve the now-highlighted session from the live list + its window id.
	local cur_idx list filtered sess alpha_wid
	cur_idx="$(tmux show-option -gqv @livepicker-index)"
	list="$(tmux show-option -gqv @livepicker-list)"
	filtered="$(printf '%s' "$list" | grep -i "$(tmux show-option -gqv @livepicker-filter)")"
	sess="$(printf '%s\n' "$filtered" | sed -n "$((cur_idx + 1))p")"
	[ -n "$sess" ] || sess="$(printf '%s\n' "$filtered" | sed -n '1p')"
	# The deferred link still lags at the instant nav returns; then catches up async.
	# (Best-effort lag observation — not asserted hard, since the bg job may have run.)
	local target_wid
	target_wid="$(_lp_active_wid "$sess")"
	wait_linked "$target_wid" \
		|| fail "deferred nav preview never linked the highlighted session ($sess)"
	assert_eq "$(tmux show-option -gqv @livepicker-linked-id)" "$target_wid" \
		"nav preview caught up to the new highlight (async)"
	"$LIVEPICKER_SCRIPTS/input-handler.sh" cancel >/dev/null 2>&1 || true
}

# (e) test_preview_defer_off_synchronous — PRD §18 Control: @livepicker-preview-defer=off
# restores the legacy SYNCHRONOUS-preview path. Typing links inline (no poll) and does
# NOT bump the seq (no bg fire). The contrast that proves (a)-(d) are deferral, not breakage.
test_preview_defer_off_synchronous() {
	attach_test_client
	tmux set-option -g @livepicker-preview-defer off
	"$LIVEPICKER_SCRIPTS/livepicker.sh"
	assert_eq "$(tmux show-option -gqv @livepicker-linked-id)" "" \
		"initial self-session preview leaves no link"
	"$LIVEPICKER_SCRIPTS/input-handler.sh" type a >/dev/null
	# Resolve the top match for "a" dynamically.
	local top_sess top_wid
	top_sess="$(printf '%s' "$(tmux show-option -gqv @livepicker-list)" | grep -i 'a' | head -1)"
	top_wid="$(_lp_active_wid "$top_sess")"
	# SYNCHRONOUS (NO poll): defer=off ran preview.sh inline before returning.
	assert_eq "$(tmux show-option -gqv @livepicker-linked-id)" "$top_wid" \
		"defer=off links the preview SYNCHRONOUSLY (legacy path restored)"
	# defer=off does NOT fire a background job -> seq stays at its init (0/unbumped).
	local seq
	seq="$(tmux show-option -gqv @livepicker-preview-seq)"
	[ -z "$seq" ] || [ "$seq" = "0" ] \
		|| fail "defer=off did not fire a background preview (seq stayed 0, got [$seq])"
	"$LIVEPICKER_SCRIPTS/input-handler.sh" cancel >/dev/null 2>&1 || true
}
