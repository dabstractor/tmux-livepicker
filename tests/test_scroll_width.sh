#!/usr/bin/env bash
# shellcheck disable=SC2154,SC2016,SC2034,SC2086
#   SC2154: TEST_STATUS / fail / assert_* / setup_test / attach_test_client / tmux /
#           LIVEPICKER_SCRIPTS are provided by run.sh + helpers.sh + setup_socket.sh
#           (sourced before this file by run.sh). SC2016/SC2034/SC2086: the harness's
#           eval/single-quote + word-split idioms (mirrors test_functional.sh).
# tests/test_scroll_width.sh — tmux-livepicker scroll + client-width-cache validation
# suite (PRD §15.28 scroll/width items; §10 step 5 / §3.35 width source; §3.32 viewport+
# scroll; §16 width-cache-staleness). Drives the REAL plugin (livepicker.sh -> input-
# handler.sh -> renderer.sh -> restore.sh) on the isolated harness. scroll-into-view +
# the width cache are COMPLETE+shipping (P1.M3.T1/T2). See research/test_scroll_width_findings.md
# for the live captures behind every assertion.
#
# CONTRACT: run.sh sources setup_socket.sh + helpers.sh + every test_*.sh, then PER test
# calls setup_test "lp-$$-<name>" (-> fresh isolated -L socket + baseline fixtures, AND
# pins @livepicker-preview-defer OFF so nav/scroll are SYNCHRONOUS). So when a test_*
# runs: bare `tmux` hits the isolated socket; attach_test_client / $LIVEPICKER_SCRIPTS /
# fail / assert_* are IN SCOPE; this file SOURCES NOTHING and calls NO setup_test.
# set -u is INHERITED from helpers.sh (do NOT re-declare; mirror test_functional.sh).

# _lp_scroll_setup [width] — attach a pty client, seed ~8 wide-named sessions, activate
# the picker, and pin @livepicker-client-width (default 12 -> forces overflow so scroll
# advances on nav). The wide session names ("session-tab-N") + small width make the
# scroll-into-view write deterministic. Sessions are added BEFORE activate (the list is
# captured at activate time).
_lp_scroll_setup() {
	local width="${1:-12}"
	local i
	attach_test_client
	for i in $(seq 1 8); do
		tmux new-session -d -s "session-tab-$i" -x 120 -y 40
	done
	"$LIVEPICKER_SCRIPTS/livepicker.sh"
	tmux set-option -g @livepicker-client-width "$width"
}

# (a) PRD §3.32: next-session advances @livepicker-scroll so the viewport follows the
# highlight; the renderer emits the left overflow '<'. With width 0 (no windowing) the
# renderer drops '<' — proving it re-derives the slice against the cached width.
test_scroll_advances_on_nav() {
	_lp_scroll_setup 12
	local n sc out before
	before="$(tmux show-option -gqv @livepicker-scroll)"; [ -z "$before" ] && before=0
	for n in 1 2 3 4 5; do
		"$LIVEPICKER_SCRIPTS/input-handler.sh" next-session >/dev/null
	done
	sc="$(tmux show-option -gqv @livepicker-scroll)"
	[ -n "$sc" ] && [ "$sc" -gt 0 ] 2>/dev/null \
		|| fail "(a) scroll advanced >0 after 5 next-session (got [$sc], started [$before])"
	pass "(a) scroll advanced to $sc (width 12, 8 wide sessions)"
	out="$("$LIVEPICKER_SCRIPTS/renderer.sh")"
	assert_contains "$out" "<" "(a) renderer shows left overflow '<' when scroll>0"
	# viewport recompute: width 0 -> renderer renders the FULL list (no windowing, no '<').
	tmux set-option -g @livepicker-client-width 0
	out="$("$LIVEPICKER_SCRIPTS/renderer.sh")"
	case "$out" in *"<"*) fail "(a) width 0 should drop '<' (viewport recompute, no windowing)" ;; esac
	pass "(a) width 0 recomputes viewport (no '<' — full list)"
}

# (a-clamp) PRD §3.32 "clamp scroll=0 when the list fits": with a WIDE width the whole
# list fits, so lp_viewport clamps scroll to 0 even after nav, and the renderer has no '<'.
test_scroll_clamps_zero_when_fits() {
	_lp_scroll_setup 200
	local n sc out
	for n in 1 2 3 4 5; do
		"$LIVEPICKER_SCRIPTS/input-handler.sh" next-session >/dev/null
	done
	sc="$(tmux show-option -gqv @livepicker-scroll)"; [ -z "$sc" ] && sc=0
	assert_eq "$sc" "0" "(a-clamp) scroll stays 0 when the list fits (wide width)"
	out="$("$LIVEPICKER_SCRIPTS/renderer.sh")"
	case "$out" in *"<"*) fail "(a-clamp) renderer should NOT show '<' when the list fits" ;; esac
	pass "(a-clamp) no '<' when the list fits"
}

# (d) PRD §19 §3.32: typing resets the viewport scroll to the top (a status-only STATE write).
test_scroll_resets_on_type() {
	_lp_scroll_setup 12
	local n sc
	for n in 1 2 3 4 5; do
		"$LIVEPICKER_SCRIPTS/input-handler.sh" next-session >/dev/null
	done
	sc="$(tmux show-option -gqv @livepicker-scroll)"
	[ -n "$sc" ] && [ "$sc" -gt 0 ] 2>/dev/null || fail "(d) type: precondition scroll>0 not met (got [$sc])"
	"$LIVEPICKER_SCRIPTS/input-handler.sh" type x >/dev/null
	sc="$(tmux show-option -gqv @livepicker-scroll)"; [ -z "$sc" ] && sc=0
	assert_eq "$sc" "0" "(d) type resets scroll to 0"
}

# (d) PRD §19 §3.32: backspace resets the viewport scroll to the top.
test_scroll_resets_on_backspace() {
	_lp_scroll_setup 12
	# Type a char that MATCHES the session-tab-* names so the filtered list stays
	# non-empty (typing 'x' would filter them all out -> next-session no-ops -> scroll
	# never advances). 's' matches every "session-tab-N"; typing resets scroll to 0,
	# then nav re-advances it, then backspace trims 's' and resets scroll again.
	"$LIVEPICKER_SCRIPTS/input-handler.sh" type s >/dev/null
	local n sc
	for n in 1 2 3 4 5; do
		"$LIVEPICKER_SCRIPTS/input-handler.sh" next-session >/dev/null
	done
	sc="$(tmux show-option -gqv @livepicker-scroll)"
	[ -n "$sc" ] && [ "$sc" -gt 0 ] 2>/dev/null || fail "(d) backspace: precondition scroll>0 not met (got [$sc])"
	"$LIVEPICKER_SCRIPTS/input-handler.sh" backspace >/dev/null
	sc="$(tmux show-option -gqv @livepicker-scroll)"; [ -z "$sc" ] && sc=0
	assert_eq "$sc" "0" "(d) backspace resets scroll to 0"
}

# (d) PRD §6 Cancel (two-step): cancel with a NON-empty filter CLEARS the query and keeps
# the picker OPEN; that clear path also resets scroll to 0. The normal flow can't produce
# non-empty-filter + non-zero-scroll together (typing resets scroll), so seed both directly
# post-activate (state is picker-internal) and assert the clear path resets scroll + filter.
test_scroll_resets_on_cancel_clear() {
	_lp_scroll_setup 12
	tmux set-option -g @livepicker-filter "xx"
	tmux set-option -g @livepicker-scroll 5
	"$LIVEPICKER_SCRIPTS/input-handler.sh" cancel >/dev/null
	local sc fl mo
	sc="$(tmux show-option -gqv @livepicker-scroll)"; [ -z "$sc" ] && sc=0
	fl="$(tmux show-option -gqv @livepicker-filter)"
	mo="$(tmux show-option -gqv @livepicker-mode)"
	assert_eq "$sc" "0"  "(d) cancel-clear resets scroll to 0"
	assert_eq "$fl" ""   "(d) cancel-clear cleared the filter"
	assert_eq "$mo" "on" "(d) cancel-clear kept the picker OPEN (mode on)"
}

# (b) PRD §10 step 5 / §3.35: the client-resized hook runs `input-handler.sh refresh-width`,
# which re-caches @livepicker-client-width from the LIVE #{client_width}. Deterministic
# proof: seed a STALE width (999), fire refresh-width, assert it returns to the live value.
# (resize-window does NOT move client_width — it is pty-derived — so the action is the path.)
test_width_refresh_recaches_live() {
	attach_test_client
	"$LIVEPICKER_SCRIPTS/livepicker.sh" >/dev/null
	local live cached
	live="$(tmux display-message -p '#{client_width}' 2>/dev/null)"
	tmux set-option -g @livepicker-client-width 999        # simulate a stale cache
	"$LIVEPICKER_SCRIPTS/input-handler.sh" refresh-width >/dev/null
	cached="$(tmux show-option -gqv @livepicker-client-width)"
	assert_eq "$cached" "$live" "(b) refresh-width re-cached the LIVE client_width (was stale 999)"
	[ "$cached" != "999" ] || fail "(b) stale 999 survived refresh-width"
}

# (b) PRD §10 step 5: activate installs a client-resized hook that runs refresh-width.
# Assert the wiring (the hook fires refresh-width on a real resize; resize-window can't
# trigger it deterministically, so we assert the install + the action separately).
test_client_resized_hook_installed() {
	attach_test_client
	"$LIVEPICKER_SCRIPTS/livepicker.sh" >/dev/null
	local hk
	hk="$(tmux show-hooks -g client-resized)"
	assert_contains "$hk" "input-handler.sh" "(b) client-resized hook wired to input-handler.sh"
	assert_contains "$hk" "refresh-width"    "(b) client-resized hook runs the refresh-width action"
}

# (c) PRD §9 / §16 "width cache staleness": restore puts back the EXACT prior client-resized
# hook. UNSET prior: the baseline socket has client-resized bare/unset; a full activate ->
# cancel cycle must leave show-hooks byte-identical (no leak of our refresh-width hook).
test_client_resized_hook_restored_unset_prior() {
	local before after
	before="$(tmux show-hooks -g client-resized)"
	attach_test_client
	"$LIVEPICKER_SCRIPTS/livepicker.sh" >/dev/null
	"$LIVEPICKER_SCRIPTS/input-handler.sh" cancel >/dev/null
	after="$(tmux show-hooks -g client-resized)"
	assert_eq "$after" "$before" "(c) client-resized restored byte-exact (unset/bare prior)"
}

# (c) SET prior with -b: activate saves + clears + installs ours; cancel replays the saved
# client-resized[0] line preserving index + -b + verbatim command. Byte-identical before/after.
test_client_resized_hook_restored_set_prior() {
	tmux set-hook -g client-resized "run-shell -b /usr/bin/true"   # a user prior (-b, [0])
	local before after
	before="$(tmux show-hooks -g client-resized)"
	attach_test_client
	"$LIVEPICKER_SCRIPTS/livepicker.sh" >/dev/null
	"$LIVEPICKER_SCRIPTS/input-handler.sh" cancel >/dev/null
	after="$(tmux show-hooks -g client-resized)"
	assert_eq "$after" "$before" "(c) client-resized restored byte-exact (set -b prior)"
}
