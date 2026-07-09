#!/usr/bin/env bash
# clip_verify_probe.sh — reproducible clip-vs-reflow verification probe (tmux 3.6b).
#
# Implements the experiment specified by PRP:
#   plan/003_77ef311abf10/P3M1T1S1/PRP.md
# "P3.M1.T1.S1 — Clip verification on tmux 3.6b + clip-vs-reflow default decision".
#
# This probe reproduces (against the SHIPPED harness, not hand-rolled tmux -L) the
# real `activate` ordering (freeze self-window -> grow status -> candidate nav
# re-link) and captures the deterministic `window_layout`/`window_height` evidence
# that the decision document
#   plan/003_77ef311abf10/architecture/clip_verification.md
# is built on. The prior evidence this re-confirms is recorded in
#   plan/003_77ef311abf10/P3M1T1S1/research/clip_probe_findings.md
# (manual ALONE reflows 23->22; manual + resize-window -y <pre-grow-height> pins
# byte-identical; linked candidate undergoes one link-time resize with no
# per-nav reflow).
#
# What this script is NOT: it is a research artifact. It writes nothing to the
# plugin runtime (scripts/), tests (tests/), PRD, README, or any tasks.json. It
# ONLY sources the shipped harness (tests/setup_socket.sh) so the user's real
# tmux server is never touched (PRD §15 non-pollution invariant). The freeze
# implementation it informs is P3.M1.T2, gated by the decision doc above.
#
# Usage:
#   bash plan/003_77ef311abf10/P3M1T1S1/research/clip_verify_probe.sh
# (Re-runnable. Two independent invocations must emit byte-identical
# window_layout strings — that determinism is the Level-1 gate.)
#
# Gotchas baked in (see PRP "Known Gotchas" + clip_probe_findings.md §0):
#   1. set-option -t needs the BARE session name (NOT "=driver").
#   2. attach_test_client's `script` pty reports 80x24, NOT 120x40; measure live.
#   3. Address windows by @id captured dynamically (NOT a hardcoded index).
#   4. resize-window accepts a value larger than the client -> that IS the clip.
#   5. window_height/window_layout only reflect client-driven size WITH an
#      attached client; assert list-clients non-empty before every measurement.
#   6. NEVER set window-size with -g (global) -> disconnects from the client.
#   7. window_layout embeds per-node dims + a 4-hex checksum -> identical ==
#      no reflow (our experiment changes nothing structural).
#   8. split-window -t needs the BARE session name too: '=alpha' is resolved as
#      a pane target (-> "can't find pane: =alpha"). Same shape as gotcha #1
#      (set-option) but for split-window. display-message against a session's
#      source window is likewise addressed by its captured @id, not '=session'.

set -u   # NOT -e (several tmux calls legitimately return nonzero); NOT -o pipefail.

# Resolve the repo root from this script's location and source the shipped
# harness. dirname("$0")/../../../.. == plan/003_77ef311abf10/P3M1T1S1/research
# -> repo root.
PROBE_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$PROBE_DIR/../../../.." && pwd)"
# shellcheck source=tests/setup_socket.sh
. "$REPO_ROOT/tests/setup_socket.sh"

# Settle time after a status grow / link-window / select-window before measuring.
# 0.3s matches the prior probe; the attach settle (0.5s) is inside
# attach_test_client. We also assert a client is attached before every measure
# (gotcha #5) so a too-fast probe cannot read the detached creation size (40).
SETTLE=0.3

# Pretty / deterministic banner.
banner() { printf '\n========== %s ==========\n' "$1"; }

# Capture the active window's @id in the driver session. The bare `tmux` resolves
# to the harness shim -> isolated -L socket. Use '=driver' (the '=' exact-match
# prefix is valid for list-windows/display-message/link-window, just NOT
# set-option — gotcha #1). Returns the @N id (e.g. "@3").
active_window_id() {
	tmux list-windows -t "=driver" -F '#{window_id}' -f '#{window_active}'
}

# Capture the active window's current height (client-driven usable rows; only
# meaningful WITH an attached client — gotcha #5).
active_window_height() {
	tmux display-message -p -t "$1" '#{window_height}'
}

# Capture the active window's full serialized layout (embeds dims + checksum).
active_window_layout() {
	tmux display-message -p -t "$1" '#{window_layout}'
}

# Assert (print-only; the probe is a research artifact, not a pytest) a client is
# attached to the driver before any measurement, else the height reads 40 (the
# detached creation size) and the experiment is meaningless.
assert_client_attached() {
	local n
	n="$(tmux list-clients -t "=driver" -F '#{client_name}' 2>/dev/null | wc -l | tr -d ' ')"
	if [ "$n" -lt 1 ]; then
		echo "  !!! NO CLIENT ATTACHED to driver (list-clients empty); measurements below are MEANINGLESS (gotcha #5)"
	fi
}

# Shared setup for the control + treatment arms: isolated socket, attached
# client on driver, and a multi-pane driver window (the self/preview window).
# After this, the active driver window is a 3-pane window (mirrors the real
# driver fixture built by setup_socket, which already has a multi-pane 'extra').
arm_setup() {
	local label="$1"
	setup_socket "cvp-$label"
	attach_test_client
	sleep "$SETTLE"
	assert_client_attached
}

# ============================================================================
# CONTROL — reproduce the jank (no freeze; just grow status).
# Expect: window_height drops (23 -> 22) and window_layout changes => reflow.
# ============================================================================
arm_control() {
	local AW H0 L0 H1 L1
	banner "CONTROL — no freeze, grow status 1->2 (expect REFLOW)"
	arm_setup "ctrl"
	# The driver fixture already has a multi-pane 'extra' window (setup_socket
	# built it). Make it active + capture it by @id (gotcha #3).
	tmux select-window -t "=driver:extra"
	sleep "$SETTLE"
	AW="$(active_window_id)"
	assert_client_attached
	H0="$(active_window_height "$AW")"
	L0="$(active_window_layout "$AW")"
	printf '  before grow : height=%s layout=%s\n' "$H0" "$L0"
	# Grow the status line 1 -> 2 (mirrors livepicker.sh activate T3(c) on->2).
	tmux set-option -g status 2
	sleep "$SETTLE"
	assert_client_attached
	H1="$(active_window_height "$AW")"
	L1="$(active_window_layout "$AW")"
	printf '  after  grow : height=%s layout=%s\n' "$H1" "$L1"
	if [ "$H0" != "$H1" ] && [ "$L0" != "$L1" ]; then
		printf '  CONTROL: REFLOW confirmed (height %s->%s, layout changed) PASS\n' "$H0" "$H1"
	else
		printf '  CONTROL: NO reflow seen (height %s->%s) FAIL — jank not reproduced\n' "$H0" "$H1"
	fi
	teardown_socket
}

# ============================================================================
# TREATMENT — the clip recipe: freeze BEFORE the grow, then grow.
# Expect: window_height + window_layout byte-identical before vs after => clip.
# Plus a second grow (status 2->3) to prove the pin survives.
# ============================================================================
arm_treatment() {
	local AW H0 L0 H1 L1 H2 L2
	banner "TREATMENT — window-size manual + resize-window -y H0, THEN grow (expect CLIP)"
	arm_setup "trt"
	tmux select-window -t "=driver:extra"
	sleep "$SETTLE"
	AW="$(active_window_id)"
	assert_client_attached
	H0="$(active_window_height "$AW")"
	L0="$(active_window_layout "$AW")"
	printf '  before freeze/grow : height=%s layout=%s\n' "$H0" "$L0"
	# THE corrected freeze recipe (slot into activate IMMEDIATELY BEFORE the
	# status grow). Bare session name for set-option (gotcha #1); never -g
	# (gotcha #6); the resize-window pin is the LOAD-BEARING step (gotcha #4).
	tmux set-option -t driver window-size manual
	tmux resize-window -y "$H0" -t "$AW"
	sleep "$SETTLE"
	# Grow status 1 -> 2 (the analog of livepicker.sh activate T3(c) on->2).
	tmux set-option -g status 2
	sleep "$SETTLE"
	assert_client_attached
	H1="$(active_window_height "$AW")"
	L1="$(active_window_layout "$AW")"
	printf '  after  grow 1->2   : height=%s layout=%s\n' "$H1" "$L1"
	# Second grow (2->3) to prove the pin survives additional status changes
	# (clip_probe_findings.md §1 "Second-grow robustness").
	tmux set-option -g status 3
	sleep "$SETTLE"
	assert_client_attached
	H2="$(active_window_height "$AW")"
	L2="$(active_window_layout "$AW")"
	printf '  after  grow 2->3   : height=%s layout=%s\n' "$H2" "$L2"
	local pin_pass=0
	if [ "$H0" = "$H1" ] && [ "$L0" = "$L1" ]; then
		printf '  TREATMENT grow 1->2: CLIP confirmed (height %s==%s, layout byte-identical) PASS\n' "$H0" "$H1"
	else
		printf '  TREATMENT grow 1->2: REFLOW seen (height %s->%s, layout changed) FAIL\n' "$H0" "$H1"
		pin_pass=1
	fi
	if [ "$H1" = "$H2" ] && [ "$L1" = "$L2" ]; then
		printf '  TREATMENT grow 2->3: pin survives second grow (height %s==%s) PASS\n' "$H1" "$H2"
	else
		printf '  TREATMENT grow 2->3: pin DRIFTED on second grow (height %s->%s) FAIL\n' "$H1" "$H2"
		pin_pass=1
	fi
	# Per-session isolation record (PRP "Per-session isolation" criterion): the
	# manual setting landed ONLY on driver; alpha falls back to global; the
	# global value is untouched by a per-session set.
	local drv_ws alpha_ws glob_ws
	drv_ws="$(tmux show-options -t driver -qv window-size 2>/dev/null)"
	alpha_ws="$(tmux show-options -t alpha  -qv window-size 2>/dev/null)"
	glob_ws="$(tmux show-options -g         -qv window-size 2>/dev/null)"
	printf '  isolation: driver=[%s] alpha=[%s] global=[%s]\n' "$drv_ws" "$alpha_ws" "$glob_ws"
	teardown_socket
	return "$pin_pass"
}

# ============================================================================
# CANDIDATE RESIDUAL — with status already grown + self-window pinned, link a
# candidate and check (a) the one-time link-time resize, (b) the source-view is
# also resized (shared window), (c) NO per-nav reflow on a second nav.
# ============================================================================
arm_candidate() {
	local AW H0 L0 alpha_wid linked_alpha_h linked_alpha_l alpha_self_h alpha_self_l
	local beta_idx alpha_linked_after_h alpha_linked_after_l free_idx
	banner "CANDIDATE RESIDUAL — linked candidate link-time resize + no per-nav reflow"
	arm_setup "cand"
	# Freeze + grow first (the production ordering: freeze -> grow -> THEN nav).
	tmux select-window -t "=driver:extra"
	sleep "$SETTLE"
	AW="$(active_window_id)"
	H0="$(active_window_height "$AW")"
	L0="$(active_window_layout "$AW")"
	tmux set-option -t driver window-size manual
	tmux resize-window -y "$H0" -t "$AW"
	tmux set-option -g status 2
	sleep "$SETTLE"
	assert_client_attached
	printf '  driver self-window pinned: height=%s layout=%s\n' "$H0" "$L0"

	# Make alpha multi-pane (so its source view is a real pane tree) and capture
	# its source window id (by @id — gotcha #3). alpha is detached -> its window
	# is at creation size 40 (gotcha #2), which is why the link resizes it down.
	# NOTE: split-window needs the BARE session name — the '=' prefix that works
	# for list-windows/display-message/link-window BREAKS split-window (it resolves
	# '=alpha' as a pane target -> "can't find pane: =alpha"). Same shape as the
	# set-option gotcha, different command.
	tmux split-window -h -t "alpha"
	sleep "$SETTLE"
	alpha_wid="$(tmux list-windows -t "=alpha" -F '#{window_id}' -f '#{window_active}')"
	printf '  alpha source window: id=%s\n' "$alpha_wid"

	# Capture alpha's OWN (source) view before linking (expect 40: detached).
	# Address the source by its captured @id, NOT '=alpha' (display-message -t
	# '=alpha' hits the session's active pane, ambiguous after a split).
	alpha_self_h="$(tmux display-message -p -t "$alpha_wid" '#{window_height}')"
	alpha_self_l="$(tmux display-message -p -t "$alpha_wid" '#{window_layout}')"
	printf '  alpha source BEFORE link: height=%s layout=%s\n' "$alpha_self_h" "$alpha_self_l"

	# Link alpha's active window into the driver at a free index, then select it.
	# link-window -t accepts "=alpha:." (the '=' prefix IS valid for link-window).
	# Find a free index in the driver so we do not clobber an existing window.
	free_idx="$(tmux list-windows -t "=driver" -F '#{window_index}' | sort -n | tail -n 1)"
	free_idx=$((free_idx + 1))
	tmux link-window -s "alpha:." -t "driver:$free_idx"
	sleep "$SETTLE"
	# Capture the linked candidate as seen IN the driver (the preview view).
	linked_alpha_h="$(tmux display-message -p -t "driver:$free_idx" '#{window_height}')"
	linked_alpha_l="$(tmux display-message -p -t "driver:$free_idx" '#{window_layout}')"
	printf '  linked alpha IN driver : height=%s layout=%s\n' "$linked_alpha_h" "$linked_alpha_l"

	# alpha's OWN (source) view AFTER the link — shared window, so it is also
	# resized to the driver's usable size. Address by the same @id.
	alpha_self_h="$(tmux display-message -p -t "$alpha_wid" '#{window_height}')"
	alpha_self_l="$(tmux display-message -p -t "$alpha_wid" '#{window_layout}')"
	printf '  alpha source AFTER link: height=%s layout=%s\n' "$alpha_self_h" "$alpha_self_l"

	# Link a SECOND candidate (beta) and navigate to it, then back to alpha, to
	# prove there is NO per-nav additional reflow on the already-linked alpha.
	# Bare 'beta' for split-window (same gotcha as alpha above).
	tmux split-window -h -t "beta"
	sleep "$SETTLE"
	beta_idx=$((free_idx + 1))
	tmux link-window -s "beta:." -t "driver:$beta_idx"
	sleep "$SETTLE"
	# Navigate: select beta-linked, then back to alpha-linked.
	tmux select-window -t "driver:$beta_idx"
	sleep "$SETTLE"
	tmux select-window -t "driver:$free_idx"
	sleep "$SETTLE"
	alpha_linked_after_h="$(tmux display-message -p -t "driver:$free_idx" '#{window_height}')"
	alpha_linked_after_l="$(tmux display-message -p -t "driver:$free_idx" '#{window_layout}')"
	printf '  alpha-linked AFTER 2nd nav: height=%s layout=%s\n' "$alpha_linked_after_h" "$alpha_linked_after_l"

	if [ "$linked_alpha_l" = "$alpha_linked_after_l" ] && [ "$linked_alpha_h" = "$alpha_linked_after_h" ]; then
		printf '  CANDIDATE: NO per-nav reflow (layout byte-identical across 2nd nav) PASS\n'
	else
		printf '  CANDIDATE: per-nav reflow seen (layout changed across 2nd nav) FAIL\n'
	fi
	# Reconcile: the link-time resize magnitude + source disturbance.
	printf '  CANDIDATE residual: link-time resize to driver usable; source view also resized (shared window)\n'
	teardown_socket
}

# Non-pollution guard (PRP Level 3): snapshot the real server's session list
# before + after the whole probe; they must be byte-identical.
real_server_snapshot() {
	/usr/bin/tmux list-sessions -F '#{session_name}' 2>/dev/null | sort
}

main() {
	local before after tmux_bin
	# $REAL_TMUX is set by setup_socket; before the first arm it is unset, so
	# resolve the version banner's tmux binary defensively (/usr/bin/tmux is the
	# verified path on this box). `tmux -V` prints "tmux 3.6b" already, so do not
	# prefix "tmux " again.
	tmux_bin="${REAL_TMUX:-/usr/bin/tmux}"
	echo "clip_verify_probe.sh — $("$tmux_bin" -V 2>/dev/null || /usr/bin/tmux -V)"
	before="$(real_server_snapshot)"
	printf 'REAL SERVER BEFORE (%d sessions): %s\n' "$(printf '%s\n' "$before" | wc -l | tr -d ' ')" "$(printf '%s\n' "$before" | tr '\n' ',' | sed 's/,$//')"

	# Run the three arms in dependency order. Each arm does its own
	# setup_socket/teardown_socket cycle on a uniquely-named isolated socket.
	arm_control
	arm_treatment || true   # a FAIL here is recorded, not fatal (honest-result path)
	arm_candidate

	after="$(real_server_snapshot)"
	printf '\nREAL SERVER AFTER  (%d sessions): %s\n' "$(printf '%s\n' "$after" | wc -l | tr -d ' ')" "$(printf '%s\n' "$after" | tr '\n' ',' | sed 's/,$//')"
	if [ "$before" = "$after" ]; then
		banner "NON-POLLUTION: REAL SERVER BYTE-IDENTICAL before/after (PASS)"
	else
		banner "NON-POLLUTION: REAL SERVER CHANGED (FAIL — ABORT)"
	fi
}

main "$@"
