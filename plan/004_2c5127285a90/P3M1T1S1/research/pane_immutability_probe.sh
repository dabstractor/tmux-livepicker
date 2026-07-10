#!/usr/bin/env bash
# pane_immutability_probe.sh — tmux-livepicker PRD §23 (Invariant C) candidate-
# window pinning verification probe. Part of plan/004 P3.M1.T1.S1.
#
# Reproducible, harness-isolated, 5-arm experiment on the installed tmux 3.6b
# (with a REAL attached client) that settles whether freezing a CANDIDATE's
# `window-size` + height at link time prevents the source-view pane disturbance
# that clip_verification.md §4 found.
#
# Sources the SHIPPED harness tests/setup_socket.sh (the PATH-shim `-L` isolation)
# — NEVER touches the user's real tmux server. Verified by Level 3: real-server
# session list is byte-identical before/after the whole probe.
#
# Evidence answer key + template:
#   plan/004_2c5127285a90/P3M1T1S1/research/candidate_pin_probe_findings.md
# Predecessor finding this EXTENDS:
#   plan/003_77ef311abf10/architecture/clip_verification.md  §4 + §3
# Harness mechanics cookbook:
#   plan/003_77ef311abf10/P3M1T1S1/research/clip_probe_findings.md  §4 + §5
# Spec: PRD.md §23 (Invariant C), §15.23, §16, §22.
#
# This probe writes NOTHING to scripts/ tests/ PRD.md README.md — it is research
# ONLY. The conditional candidate-pin CODE is P3.M2.T2 (gated by THIS probe's
# decision doc: architecture/pane_immutability_verification.md).
#
# CONTRACT (mirrors tests/setup_socket.sh): set -u ONLY (not -e; not pipefail —
# tmux show-option/has-session/kill-server legitimately return nonzero). `local`
# for function locals. TABS for indent. Quote everything.
# shellcheck disable=SC2154

set -u   # NOT -e; NOT -o pipefail.

# Resolve the repo root from this script's location so the probe is runnable from
# anywhere. research/ -> P3M1T1S1/ -> 004_*/ -> plan/ -> repo root = 4 levels up.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../../.." && pwd)"

# Source the shipped harness — defines setup_socket / teardown_socket /
# attach_test_client / detach_test_client + the PATH shim that makes bare `tmux`
# hit the isolated -L socket. Sourcing has NO side effects (functions only).
# shellcheck source=tests/setup_socket.sh
. "$REPO_ROOT/tests/setup_socket.sh"

# ---------------------------------------------------------------------------
# Geometry + banner helpers (define once; reused by every arm).
# ---------------------------------------------------------------------------

# snap <target_spec> — print a 3-line labeled snapshot of a window's geometry:
#   height (window_height), layout (window_layout), and the sorted per-pane
#   geometry (the explicit §23 per-pane assertion shape). $1 is a tmux target
#   spec, e.g. an @id "$ALPHA_WID" or a window-qualified spec "=$SESS:".
# ALWAYS assert a client is attached before measuring (gotcha #5): on a client-less
# socket window_height/window_layout read the creation size and hide the shared-window
# resize. The caller ensures attach_test_client ran + settled before calling snap.
snap() {
	local target="$1"
	local height layout panes
	height="$(tmux display-message -p -t "$target" '#{window_height}')"
	layout="$(tmux display-message -p -t "$target" '#{window_layout}')"
	panes="$(tmux list-panes -t "$target" -F '#{pane_id}:#{pane_left},#{pane_top},#{pane_width},#{pane_height}' | sort)"
	echo "    height : $height"
	echo "    layout : $layout"
	echo "    panes  : $(printf '%s' "$panes" | paste -sd'|' -)"
}

# banner <text> — print a visible section delimiter.
banner() {
	echo ""
	echo "=================================================================="
	echo "  $1"
	echo "=================================================================="
}

# active_wid <session> — capture the active window's @id for a session. NEVER use
# a hardcoded index (base-index 1, renumber-windows on — gotcha #3). The '='
# exact-match prefix IS valid for list-windows. Returns the bare @id (e.g. "@1");
# callers write `-t "$WID"`, NOT `-t "@$WID"` (that becomes "@@1").
active_wid() {
	tmux list-windows -t "=$1" -F '#{window_id}' -f '#{window_active}'
}

# make_multipane <session> — give a session's active window a 3-pane split so the
# layout has real per-pane structure (a byte-identical multi-pane window_layout is
# a much stronger no-mutation proof than a single-pane one). Uses the BARE session
# name (gotcha #1: split-window -t "=sess" -> "can't find pane"). Returns the
# active window's @id AFTER splitting.
make_multipane() {
	local sess="$1"
	tmux split-window -h -t "$sess"
	tmux split-window -v -t "$sess"
	active_wid "$sess"
}

# freeze_driver — the §3 driver-side freeze recipe applied FIRST in every arm:
# per-session window-size manual (BARE name — gotcha #1; NEVER -g — gotcha #6),
# then resize-window -y <current_height> pins the self-window across the status
# grow, then grow status to 2. Capture the driver's pinned height live (gotcha #2:
# the script pty is 80x24, NOT 120x40 — usable is 23/22). sleep 0.3 after grow to
# let it settle (gotcha #5).
freeze_driver() {
	local drv_wid h_drv
	drv_wid="$(active_wid driver)"
	h_drv="$(tmux display-message -p -t "$drv_wid" '#{window_height}')"
	tmux set-option -t driver window-size manual          # bare name (gotcha #1)
	tmux resize-window -y "$h_drv" -t "$drv_wid"
	tmux set-option -g status 2; sleep 0.3                # grow (status 2 before candidate link)
	echo "$drv_wid"
}

# ---------------------------------------------------------------------------
# ARM A — CONTROL (no candidate pin). Reproduce clip_verification.md §4.
# ---------------------------------------------------------------------------
arm_control() {
	banner "ARM A — CONTROL (no candidate pin; reproduce clip_verification.md §4)"
	local alpha_wid lay_pre lay_post h_pre h_post
	setup_socket "lp-piv-ctrl-$$"
	attach_test_client
	# 3-pane candidate alpha (detached, source size 40).
	alpha_wid="$(make_multipane alpha)"
	freeze_driver >/dev/null   # driver manual + pinned + status 2
	echo "  ALPHA source BEFORE link:"
	snap "$alpha_wid"
	lay_pre="$(tmux display-message -p -t "$alpha_wid" '#{window_layout}')"
	h_pre="$(tmux display-message -p -t "$alpha_wid" '#{window_height}')"
	# Link unpinned alpha into the driver, select it (session-scoped per P2.M3.T1.S1).
	tmux link-window -s "$alpha_wid" -t "driver:"
	tmux select-window -t "driver:$alpha_wid"; sleep 0.3
	echo "  ALPHA source AFTER  link:"
	snap "$alpha_wid"
	lay_post="$(tmux display-message -p -t "$alpha_wid" '#{window_layout}')"
	h_post="$(tmux display-message -p -t "$alpha_wid" '#{window_height}')"
	echo "  >> layout: $([ "$lay_pre" = "$lay_post" ] && echo SAME || echo DIFF)"
	echo "  >> height: $h_pre -> $h_post  ($([ "$h_pre" = "$h_post" ] && echo SAME || echo DISTURBED))"
	echo "  EXPECT: DISTURBED (40 -> 22, layout changes). Reproduces clip_verification.md §4."
	detach_test_client
	teardown_socket
}

# ---------------------------------------------------------------------------
# ARM B — PIN BEFORE LINK (the proposed fix), detached alpha. DECISIVE.
# ---------------------------------------------------------------------------
arm_pin_before() {
	banner "ARM B — PIN BEFORE LINK (detached candidate; the proposed fix)"
	local alpha_wid h_cand lay_pre lay_post panes_pre panes_post
	setup_socket "lp-piv-pinb-$$"
	attach_test_client
	alpha_wid="$(make_multipane alpha)"
	freeze_driver >/dev/null
	echo "  ALPHA source BEFORE pin/link:"
	snap "$alpha_wid"
	lay_pre="$(tmux display-message -p -t "$alpha_wid" '#{window_layout}')"
	panes_pre="$(tmux list-panes -t "$alpha_wid" -F '#{pane_id}:#{pane_left},#{pane_top},#{pane_width},#{pane_height}' | sort)"
	# THE candidate pin (CONDITIONAL recipe): bare name manual + resize-window -y H_cand.
	tmux set-option -t alpha window-size manual           # bare name (gotcha #1)
	h_cand="$(tmux display-message -p -t "$alpha_wid" '#{window_height}')"
	tmux resize-window -y "$h_cand" -t "$alpha_wid"
	echo "  ALPHA source AFTER pin (did the pin itself change it?):"
	snap "$alpha_wid"
	# Link + select (session-scoped).
	tmux link-window -s "$alpha_wid" -t "driver:"
	tmux select-window -t "driver:$alpha_wid"; sleep 0.3
	echo "  ALPHA source AFTER link:"
	snap "$alpha_wid"
	lay_post="$(tmux display-message -p -t "$alpha_wid" '#{window_layout}')"
	panes_post="$(tmux list-panes -t "$alpha_wid" -F '#{pane_id}:#{pane_left},#{pane_top},#{pane_width},#{pane_height}' | sort)"
	echo "  >> layout: $([ "$lay_pre" = "$lay_post" ] && echo SAME/BYTE-IDENTICAL || echo DIFF)"
	echo "  >> panes : $([ "$panes_pre" = "$panes_post" ] && echo SAME/BYTE-IDENTICAL || echo DIFF)"
	echo "  EXPECT: BYTE-IDENTICAL (the decisive data point)."
	detach_test_client
	teardown_socket
}

# ---------------------------------------------------------------------------
# ARM C — PIN AFTER LINK (reversibility). Corrects §23 "permanent" for resize-pin.
# The link disturbs BOTH height (40->22) AND width (120->80). A height-only
# resize-window -y H_orig restores the height but NOT the width (stays 80x40),
# so the per-pane split differs from the original 120x40. Restoring BOTH dims
# (resize-window -x W_orig -y H_orig) restores the EXACT layout byte-for-byte;
# equivalently, restore height THEN select-layout. This refines candidate_pin-
# probe_findings.md §ARM C2 (which claimed -y alone restores): height-only is
# insufficient when the link also changed the width.
# ---------------------------------------------------------------------------
arm_pin_after() {
	banner "ARM C — PIN AFTER LINK (reversibility of the link-time mutation)"
	local alpha_wid h_pre w_pre lay_pre panes_pre
	local lay_y panes_y lay_xy panes_xy
	setup_socket "lp-piv-pina-$$"
	attach_test_client
	alpha_wid="$(make_multipane alpha)"
	freeze_driver >/dev/null
	echo "  ALPHA source BEFORE link (unpinned):"
	snap "$alpha_wid"
	lay_pre="$(tmux display-message -p -t "$alpha_wid" '#{window_layout}')"
	panes_pre="$(tmux list-panes -t "$alpha_wid" -F '#{pane_id}:#{pane_left},#{pane_top},#{pane_width},#{pane_height}' | sort)"
	h_pre="$(tmux display-message -p -t "$alpha_wid" '#{window_height}')"
	w_pre="$(tmux display-message -p -t "$alpha_wid" '#{window_width}')"
	# Link unpinned -> alpha disturbed (shared window dragged to driver usable: 120x40 -> 80x22).
	tmux link-window -s "$alpha_wid" -t "driver:"
	tmux select-window -t "driver:$alpha_wid"; sleep 0.3
	echo "  ALPHA source AFTER unpinned link (DISTURBED):"
	snap "$alpha_wid"
	# Restore attempt (a): height only. Restores height, NOT width -> per-pane split differs.
	tmux resize-window -y "$h_pre" -t "$alpha_wid"; sleep 0.3
	echo "  ALPHA source AFTER pin-back -y $h_pre (height only):"
	snap "$alpha_wid"
	lay_y="$(tmux display-message -p -t "$alpha_wid" '#{window_layout}')"
	panes_y="$(tmux list-panes -t "$alpha_wid" -F '#{pane_id}:#{pane_left},#{pane_top},#{pane_width},#{pane_height}' | sort)"
	echo "  >> height-only -y: layout $([ "$lay_pre" = "$lay_y" ] && echo SAME || echo DIFF)  (width NOT restored: stays at disturbed 80)"
	# Restore attempt (b): BOTH width and height. Restores the EXACT original layout.
	tmux resize-window -x "$w_pre" -y "$h_pre" -t "$alpha_wid"; sleep 0.3
	echo "  ALPHA source AFTER pin-back -x $w_pre -y $h_pre (both dims):"
	snap "$alpha_wid"
	lay_xy="$(tmux display-message -p -t "$alpha_wid" '#{window_layout}')"
	panes_xy="$(tmux list-panes -t "$alpha_wid" -F '#{pane_id}:#{pane_left},#{pane_top},#{pane_width},#{pane_height}' | sort)"
	echo "  >> both-dim -x -y: layout $([ "$lay_pre" = "$lay_xy" ] && echo SAME-restored/BYTE-IDENTICAL || echo DIFF)"
	echo "  >> both-dim -x -y: panes  $([ "$panes_pre" = "$panes_xy" ] && echo SAME-restored/BYTE-IDENTICAL || echo DIFF)"
	echo "  EXPECT: height-only=DIFF (width not restored); both-dim=SAME-restored (the exact layout)."
	echo "  REFINES C2: a reliable restore needs BOTH W and H (resize-window -x W_orig -y H_orig), or height + select-layout."
	detach_test_client
	teardown_socket
}

# ---------------------------------------------------------------------------
# ARM D — FLIP (second distinct window of the candidate). See gotcha #9.
# Create the flip's second window BEFORE the manual/link state to dodge the
# post-manual new-window index-collision fixture quirk.
# ---------------------------------------------------------------------------
arm_flip() {
	banner "ARM D — FLIP (second distinct window of the candidate)"
	local w1 w2 lay_pre panes_pre lay_post panes_post
	setup_socket "lp-piv-flip-$$"
	attach_test_client
	# Create BOTH distinct windows BEFORE any manual/link state (gotcha #9).
	# alpha starts with 1 window; make it 3-pane (W1), then add a 2nd window (W2).
	w1="$(make_multipane alpha)"
	tmux new-window -t alpha                                 # bare name (gotcha #1)
	w2="$(active_wid alpha)"
	# Now freeze the driver + pin BOTH candidate windows.
	freeze_driver >/dev/null
	tmux set-option -t alpha window-size manual
	local h1 h2
	h1="$(tmux display-message -p -t "$w1" '#{window_height}')"
	h2="$(tmux display-message -p -t "$w2" '#{window_height}')"
	tmux resize-window -y "$h1" -t "$w1"
	tmux resize-window -y "$h2" -t "$w2"
	# Link W1, select; snapshot W1 source.
	tmux link-window -s "$w1" -t "driver:"
	tmux select-window -t "driver:$w1"; sleep 0.3
	echo "  W1 source BEFORE flip (linked, selected):"
	snap "$w1"
	lay_pre="$(tmux display-message -p -t "$w1" '#{window_layout}')"
	panes_pre="$(tmux list-panes -t "$w1" -F '#{pane_id}:#{pane_left},#{pane_top},#{pane_width},#{pane_height}' | sort)"
	# Flip: link W2, select it (the flip), then re-select W1 — snapshot W1 again.
	tmux link-window -s "$w2" -t "driver:"
	tmux select-window -t "driver:$w2"; sleep 0.3
	tmux select-window -t "driver:$w1"; sleep 0.3
	echo "  W1 source AFTER  flip (W2 linked + selected, then back to W1):"
	snap "$w1"
	lay_post="$(tmux display-message -p -t "$w1" '#{window_layout}')"
	panes_post="$(tmux list-panes -t "$w1" -F '#{pane_id}:#{pane_left},#{pane_top},#{pane_width},#{pane_height}' | sort)"
	echo "  >> flip layout: $([ "$lay_pre" = "$lay_post" ] && echo SAME/safe || echo DIFF)"
	echo "  >> flip panes : $([ "$panes_pre" = "$panes_post" ] && echo SAME/safe || echo DIFF)"
	echo "  EXPECT: SAME/safe (distinct @id windows are independent shared objects; no per-nav reflow — clip §4)."
	detach_test_client
	teardown_socket
}

# ---------------------------------------------------------------------------
# ARM E — CANDIDATE WITH ITS OWN CLIENT (real multi-client). DECISION INPUT.
# E3 WITH pin: manual + resize-window REVERTS alpha's client view -> HARMFUL.
# E4 NO  pin: bare link alone does NOT disturb a client-bearing candidate.
# A SECOND pty is spawned manually for alpha (gotcha #8: attach_test_client
# overwrites the single TEST_CLIENT_PID).
# ---------------------------------------------------------------------------
arm_candidate_with_client() {
	banner "ARM E — CANDIDATE WITH ITS OWN CLIENT (E3 pin=HARMFUL, E4 no-pin=CLEAN)"
	local alpha_wid cand_pid lay_e3_pre panes_e3_pre lay_e3_post panes_e3_post
	local lay_e4_pre lay_e4_post h_e3_pre h_e3_post
	setup_socket "lp-piv-cand-$$"
	attach_test_client                       # the DRIVER client
	alpha_wid="$(make_multipane alpha)"
	# Spawn a SECOND pty attached to alpha (gotcha #8). Kill it on teardown.
	script -qec "tmux attach -t 'alpha'" /dev/null >/dev/null 2>&1 &
	cand_pid=$!
	sleep 0.5
	freeze_driver >/dev/null                  # driver manual + pinned + status 2 (global grow hits alpha too)

	# --- E3: WITH candidate pin (expect HARMFUL: reverts client view to creation size) ---
	echo "  --- E3: WITH candidate pin ---"
	echo "  ALPHA (own client) baseline AFTER global status grow:"
	snap "$alpha_wid"
	lay_e3_pre="$(tmux display-message -p -t "$alpha_wid" '#{window_layout}')"
	panes_e3_pre="$(tmux list-panes -t "$alpha_wid" -F '#{pane_id}:#{pane_left},#{pane_top},#{pane_width},#{pane_height}' | sort)"
	h_e3_pre="$(tmux display-message -p -t "$alpha_wid" '#{window_height}')"
	tmux set-option -t alpha window-size manual
	local h_cand
	h_cand="$(tmux display-message -p -t "$alpha_wid" '#{window_height}')"
	tmux resize-window -y "$h_cand" -t "$alpha_wid"; sleep 0.3
	echo "  ALPHA AFTER candidate pin (manual + resize-window):"
	snap "$alpha_wid"
	lay_e3_post="$(tmux display-message -p -t "$alpha_wid" '#{window_layout}')"
	panes_e3_post="$(tmux list-panes -t "$alpha_wid" -F '#{pane_id}:#{pane_left},#{pane_top},#{pane_width},#{pane_height}' | sort)"
	h_e3_post="$(tmux display-message -p -t "$alpha_wid" '#{window_height}')"
	echo "  >> pin changed alpha (vs post-grow)? $([ "$lay_e3_pre" = "$lay_e3_post" ] && echo NO || echo YES/REVERTED)  ($h_e3_pre -> $h_e3_post)"
	echo "  EXPECT: REVERTED/HARMFUL (manual detaches the window from its client -> creation size)."

	# --- E4: NO pin (expect CLEAN: bare link does NOT disturb a client-bearing candidate) ---
	echo "  --- E4: NO candidate pin (bare link only) ---"
	# Undo the E3 manual so alpha re-fits its client for a clean E4 baseline.
	tmux set-option -t alpha window-size latest; sleep 0.3
	tmux set-option -gu window-size 2>/dev/null || true     # clear any leftover; per-session only
	tmux set-option -t alpha window-size latest; sleep 0.3
	echo "  ALPHA (re-fitted) BEFORE link (no pin):"
	snap "$alpha_wid"
	lay_e4_pre="$(tmux display-message -p -t "$alpha_wid" '#{window_layout}')"
	tmux link-window -s "$alpha_wid" -t "driver:"
	tmux select-window -t "driver:$alpha_wid"; sleep 0.3
	echo "  ALPHA AFTER bare link (no pin):"
	snap "$alpha_wid"
	lay_e4_post="$(tmux display-message -p -t "$alpha_wid" '#{window_layout}')"
	echo "  >> link effect with NO pin: $([ "$lay_e4_pre" = "$lay_e4_post" ] && echo NO-change/CLEAN || echo DIFF)"
	echo "  EXPECT: NO-change/CLEAN (driver is manual -> no downward pressure; alpha's own client keeps it fitted)."
	echo "  DECISION INPUT: pin must be SKIPPED for client-bearing candidates (gate on list-clients)."

	# Teardown: kill the manually-spawned candidate pty FIRST, then the harness teardown.
	kill "$cand_pid" 2>/dev/null || true
	wait "$cand_pid" 2>/dev/null || true
	detach_test_client
	teardown_socket
}

# ---------------------------------------------------------------------------
# Main — snapshot the real server, run all 5 arms, re-snapshot, verify non-pollution.
# ---------------------------------------------------------------------------
main() {
	local real_before real_after
	real_before="$(/usr/bin/tmux list-sessions -F '#{session_name}' 2>/dev/null | sort)"

	banner "Pane-Immutability Verification Probe — tmux 3.6b (PRD §23 Invariant C)"
	echo "  PRP     : plan/004_2c5127285a90/P3M1T1S1/PRP.md"
	echo "  Answer  : plan/004_2c5127285a90/P3M1T1S1/research/candidate_pin_probe_findings.md"
	echo "  Harness : tests/setup_socket.sh (isolated -L socket; never the real server)"
	echo "  Real server sessions BEFORE: $(echo "$real_before" | wc -l) session(s)"

	arm_control
	arm_pin_before
	arm_pin_after
	arm_flip
	arm_candidate_with_client

	real_after="$(/usr/bin/tmux list-sessions -F '#{session_name}' 2>/dev/null | sort)"
	banner "Non-pollution check (PRD §15)"
	echo "  Real server sessions AFTER: $(echo "$real_after" | wc -l) session(s)"
	if [ "$real_before" = "$real_after" ]; then
		echo "  >> REAL SERVER UNTOUCHED (byte-identical session list)"
	else
		echo "  >> !!! POLLUTION DETECTED — real server session list CHANGED !!!"
		diff <(printf '%s\n' "$real_before") <(printf '%s\n' "$real_after") || true
	fi
	echo ""
	echo "=================================================================="
	echo "  Probe complete. See architecture/pane_immutability_verification.md."
	echo "=================================================================="
}

main "$@"
