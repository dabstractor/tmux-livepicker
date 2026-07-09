#!/usr/bin/env bash
# tests/test_session_mgmt.sh — tmux-livepicker PRD §21 + §15.28 session
# MANAGEMENT validation (P2.M2.T1.S1).
#
# SOURCED by run.sh (NEVER executed directly). Defines test_* functions that drive
# the COMPLETE real scripts/session-mgmt.sh (P2.M1.T2: the rename + delete
# implementation) DIRECTLY (NOT via keypress — the harness idiom; mirrors how
# test_create.sh drives input-handler.sh confirm) against the socket-isolated
# server the harness provides (tests/setup_socket.sh + tests/helpers.sh), and
# assert observable tmux state for every §15.28 management behaviour: rename,
# sanitized-name abort, collision abort, delete (list rewrite + neighbour
# highlight + re-sync), driver-guard, last-session-guard, the kill-session /
# linked-preview leak, and confirm-delete.
#
# CONTRACT: run.sh sources setup_socket.sh + helpers.sh + every tests/test_*.sh,
# then PER test calls setup_test "lp-$$-<name>" (-> fresh isolated socket + PATH
# shim + baseline fixtures driver/alpha/beta, pins @livepicker-preview-defer off)
# -> resets TEST_STATUS=pass -> runs the test_* in the CURRENT shell -> reads
# TEST_STATUS -> teardown_test. So when a test_* runs: bare `tmux` hits the
# isolated socket; $LIVEPICKER_SCRIPTS, TEST_DRIVER_SESSION, attach_test_client,
# fail/pass/assert_eq/assert_contains are all IN SCOPE; this file SOURCES NOTHING
# and calls NO setup_test/teardown_test (run.sh owns the per-test cycle).
#
# CRITICAL (research RESEARCH NOTE / E1): command-prompt/confirm-before are
# interactive; under the harness we test the SUBMIT HANDLERS DIRECTLY —
# `$LIVEPICKER_SCRIPTS/session-mgmt.sh do-rename <NEW>` and
# `... do-delete <S>` with seeded state. do-rename/do-delete are CLIENT-
# INDEPENDENT (refresh-client -S is guarded `|| true`) -> NO attach_test_client
# for (a)-(g). Only the confirm-before test (h) attaches a client (confirm-before
# needs one to display its prompt).
#
# CRITICAL: abort messages (display-message) are NOT observable without an
# attached client. For (b)/(c)/(e)/(f) assert on tmux STATE (list unchanged,
# session still exists / still dead), NOT on message text.
#
# CRITICAL: the leak test MUST include a CONTROL (raw kill-session, no unlink)
# that reproduces the orphan. Without it the 'gone' assertion is vacuous — it
# could pass because the link never happened. EXP D (empirical_findings.md F3)
# proves raw kill-session leaves the window SURVIVING in the driver.
#
# CRITICAL: window ids (@N) are GLOBAL and assigned at creation; ALWAYS read them
# dynamically via list-windows -F '#{window_id}'. Never hardcode @1/@2.
#
# `set -u` is INHERITED from helpers.sh (do NOT re-declare; mirror test_self.sh).
# shellcheck disable=SC2154,SC2016,SC2034,SC2086
#   SC2154: assert_*/fail/attach_test_client/$LIVEPICKER_SCRIPTS/
#           $TEST_DRIVER_SESSION are defined by run.sh's sources, not in this
#           file.
#   SC2016: single-quoted tmux format strings ('#{window_id}') are literal for
#           tmux, not for bash.
#   SC2034/SC2086: in-scope symbols + quoted expansions the harness contract
#                  dictates; mirror the sibling test files.

# lp_mgmt_seed_state — set the MINIMAL @livepicker-* state session-mgmt.sh reads.
# Mirrors tests/test_preview.sh:lp_preview_seed_state (NO sourcing — the literal
# key strings are stable state.sh contract constants). Seeds exactly the keys
# _lp_resolve_highlighted / session_mgmt_delete / session_mgmt_do_delete read:
# list, filter="", index, orig-session=driver, orig-window=driver's ACTIVE window
# id (read DYNAMICALLY — window ids are GLOBAL), mode=on, linked-id="".
#
# $1 = 0-based highlight index over the list given by the remaining args
# (defaults to alpha beta gamma). The CALLER ensures those sessions EXIST (via
# bare `tmux new-session -d -s <name>`). lp_rank with an empty filter preserves
# list order, so index N over the seeded list resolves to the Nth line.
lp_mgmt_seed_state() {
	local _idx="${1:-0}"; shift
	local _drv_win
	_drv_win="$(tmux list-windows -t "=$TEST_DRIVER_SESSION" -F '#{window_id}' -f '#{window_active}')"
	tmux set-option -g @livepicker-orig-session "$TEST_DRIVER_SESSION"
	tmux set-option -g @livepicker-orig-window "$_drv_win"
	tmux set-option -g @livepicker-list "$(printf '%s\n' "$@")"
	tmux set-option -g @livepicker-filter ""
	tmux set-option -g @livepicker-index "$_idx"
	tmux set-option -g @livepicker-mode "on"
	tmux set-option -g @livepicker-linked-id ""
	tmux set-option -g @livepicker-confirm-delete off   # default; (h) flips on
}

# lp_mgmt_list_form — normalize @livepicker-list to a comma-join so list-equality
# assertions avoid newline ambiguity. Every seed emits a trailing newline (so the
# comma form has a trailing comma): "alpha,beta,gamma,".
lp_mgmt_list_form() {
	tmux show-option -gqv @livepicker-list | tr '\n' ','
}

# lp_mgmt_has — rc predicate helper: TRUE (rc 0) iff session $1 exists. Wraps
# has-session so callers stay free of raw `tmux ... ; then` under set -u.
lp_mgmt_has() {
	tmux has-session -t "=$1" 2>/dev/null
}

# test_rename_updates_list_preserves_highlight — contract (a): do-rename <valid>
# rewrites @livepicker-list (old name -> new), leaves @livepicker-index unchanged
# (highlight preserved), @livepicker-mode still `on`, the renamed session exists
# under the NEW name and is gone under the old. do-rename is client-independent
# -> NO attach_test_client.
test_rename_updates_list_preserves_highlight() {
	tmux new-session -d -s gamma -x 120 -y 40   # baseline gives driver/alpha/beta
	lp_mgmt_seed_state 1 alpha beta gamma        # highlight index 1 => beta

	"$LIVEPICKER_SCRIPTS/session-mgmt.sh" do-rename delta

	# (a) index unchanged (rename does not reorder -> highlight stays).
	assert_eq "$(tmux show-option -gqv @livepicker-index)" "1" \
		"rename preserved the highlight index"
	# (a) list rewritten: delta present, beta absent.
	assert_contains "$(lp_mgmt_list_form)" "delta," "list gained the new name delta"
	case "$(lp_mgmt_list_form)" in *"beta,"*) fail "rename left the old name beta in the list" ;; esac
	# (a) session renamed: delta exists, beta gone.
	if lp_mgmt_has delta; then pass "rename created the session delta"; else fail "rename did not create the session delta"; fi
	if lp_mgmt_has beta; then fail "rename left the old session beta alive"; else pass "rename killed the old session beta"; fi
	# (a) picker stays active (do-rename never calls restore).
	assert_eq "$(tmux show-option -gqv @livepicker-mode)" "on" \
		"picker stays active after rename (no restore)"
}

# test_rename_sanitized_colon_aborts — contract (b1): do-rename with `:` anywhere
# aborts BEFORE renaming. list UNCHANGED, original session still exists, NO
# sanitized variant (be_ta / be:ta) created. Assert on STATE only (display-message
# abort text is not observable without a client). NO attach_test_client.
test_rename_sanitized_colon_aborts() {
	tmux new-session -d -s gamma -x 120 -y 40
	lp_mgmt_seed_state 1 alpha beta gamma        # highlight => beta

	"$LIVEPICKER_SCRIPTS/session-mgmt.sh" do-rename 'be:ta'

	# (b1) list unchanged (no rename applied).
	assert_eq "$(lp_mgmt_list_form)" "alpha,beta,gamma," "colon rename left the list unchanged"
	# (b1) original session still exists.
	if lp_mgmt_has beta; then pass "colon rename kept the original session beta"; else fail "colon rename destroyed beta"; fi
	# (b1) NO sanitized variant created.
	if lp_mgmt_has 'be:ta'; then fail "colon rename created a be:ta session"; else pass "colon rename created no be:ta session"; fi
	if lp_mgmt_has 'be_ta'; then fail "colon rename created a sanitized be_ta session"; else pass "colon rename created no be_ta session"; fi
}

# test_rename_sanitized_leading_dot_aborts — contract (b2): do-rename with a
# leading `.` aborts BEFORE renaming. list UNCHANGED, original still exists, NO
# sanitized variant (.dot / _dot) created. Same shape as (b1). NO client.
test_rename_sanitized_leading_dot_aborts() {
	tmux new-session -d -s gamma -x 120 -y 40
	lp_mgmt_seed_state 1 alpha beta gamma        # highlight => beta

	"$LIVEPICKER_SCRIPTS/session-mgmt.sh" do-rename '.dot'

	# (b2) list unchanged.
	assert_eq "$(lp_mgmt_list_form)" "alpha,beta,gamma," "leading-dot rename left the list unchanged"
	# (b2) original session still exists.
	if lp_mgmt_has beta; then pass "leading-dot rename kept the original session beta"; else fail "leading-dot rename destroyed beta"; fi
	# (b2) NO sanitized variant created.
	if lp_mgmt_has '.dot'; then fail "leading-dot rename created a .dot session"; else pass "leading-dot rename created no .dot session"; fi
	if lp_mgmt_has '_dot'; then fail "leading-dot rename created a sanitized _dot session"; else pass "leading-dot rename created no _dot session"; fi
}

# test_rename_collision_aborts — contract (c): do-rename to an EXISTING session
# name aborts (rename-session rc!=0). list UNCHANGED, original session unchanged.
# NO client.
test_rename_collision_aborts() {
	tmux new-session -d -s gamma -x 120 -y 40
	lp_mgmt_seed_state 1 alpha beta gamma        # highlight => beta

	"$LIVEPICKER_SCRIPTS/session-mgmt.sh" do-rename alpha   # alpha already exists

	# (c) list unchanged.
	assert_eq "$(lp_mgmt_list_form)" "alpha,beta,gamma," "collision rename left the list unchanged"
	# (c) the renamed-away target (beta) is still itself.
	if lp_mgmt_has beta; then pass "collision rename kept the original session beta"; else fail "collision rename destroyed beta"; fi
	# (c) the collision target (alpha) is unchanged (still exactly one alpha).
	if lp_mgmt_has alpha; then pass "collision rename kept alpha"; else fail "collision rename destroyed alpha"; fi
}

# test_delete_rewrites_list_and_highlights_neighbour — contract (d): do-delete <S>
# (non-driver, list >=3): session gone from list-sessions, dropped from
# @livepicker-list, @livepicker-index clamped to a valid neighbour, the new
# highlight's window re-linked as the preview (@livepicker-linked-id). do-delete
# is client-independent -> NO attach_test_client.
test_delete_rewrites_list_and_highlights_neighbour() {
	tmux new-session -d -s gamma -x 120 -y 40
	lp_mgmt_seed_state 1 alpha beta gamma        # highlight index 1 => beta

	"$LIVEPICKER_SCRIPTS/session-mgmt.sh" do-delete beta

	# (d) beta killed.
	if lp_mgmt_has beta; then fail "delete left beta alive"; else pass "delete killed beta"; fi
	# (d) beta dropped from the list.
	assert_eq "$(lp_mgmt_list_form)" "alpha,gamma," "delete dropped beta from the list"
	# (d) index clamped to a valid neighbour (gamma is now index 1).
	assert_eq "$(tmux show-option -gqv @livepicker-index)" "1" \
		"delete clamped the highlight onto the neighbour (gamma)"
	# (d) the new highlight's window re-linked as the preview. Window ids are
	# GLOBAL -> read gamma's active window id DYNAMICALLY; do NOT assert "" (the
	# re-sync OVERWRITES linked-id with the neighbour's window).
	local gamma_wid
	gamma_wid="$(tmux list-windows -t '=gamma' -F '#{window_id}' -f '#{window_active}')"
	assert_eq "$(tmux show-option -gqv @livepicker-linked-id)" "$gamma_wid" \
		"delete re-synced the preview to the new highlight's window (gamma)"
}

# test_delete_refuses_driver — contract (e): the `delete` action (the GUARD entry
# point) refuses the DRIVER session. orig-session=driver + highlight=driver =>
# guard A fires; driver still alive, list UNCHANGED. NO client.
test_delete_refuses_driver() {
	# List includes the driver itself; highlight index 0 => driver.
	lp_mgmt_seed_state 0 "$TEST_DRIVER_SESSION" alpha victim

	"$LIVEPICKER_SCRIPTS/session-mgmt.sh" delete

	# (e) driver still alive.
	if lp_mgmt_has "$TEST_DRIVER_SESSION"; then pass "driver guard kept the driver alive"; else fail "driver guard killed the driver"; fi
	# (e) list unchanged.
	assert_eq "$(lp_mgmt_list_form)" "$TEST_DRIVER_SESSION,alpha,victim," \
		"driver guard left the list unchanged"
}

# test_delete_refuses_last_session — contract (f): `delete` when @livepicker-list
# has length 1 is refused (killing the last session kills the server). The lone
# session stays alive; list UNCHANGED. NO client.
test_delete_refuses_last_session() {
	# Reduce to ONE non-driver session. Baseline gives driver/alpha/beta; kill the
	# extras, then create a single `lonely` so the list has length 1.
	tmux kill-session -t '=alpha' 2>/dev/null || true
	tmux kill-session -t '=beta'  2>/dev/null || true
	tmux new-session -d -s lonely -x 120 -y 40
	lp_mgmt_seed_state 0 lonely   # list length 1

	"$LIVEPICKER_SCRIPTS/session-mgmt.sh" delete

	# (f) the lone session still alive.
	if lp_mgmt_has lonely; then pass "last-session guard kept lonely alive"; else fail "last-session guard killed the lone session"; fi
	# (f) list unchanged.
	assert_eq "$(lp_mgmt_list_form)" "lonely," "last-session guard left the list unchanged"
}

# test_delete_unlinks_preview_no_orphan — contract (g) FIX half: after
# preview.sh links the victim's window into the driver, do-delete victim leaves
# NO orphan window in the driver (it unlinks FIRST, then kills). The CONTROL
# (test_raw_kill_leaks_orphan) reproduces the leak so this assertion is not
# vacuous. preview.sh is client-independent -> NO attach_test_client.
test_delete_unlinks_preview_no_orphan() {
	tmux new-session -d -s victim -x 120 -y 40
	tmux new-session -d -s other -x 120 -y 40
	lp_mgmt_seed_state 0 victim other   # highlight => victim

	# Link the victim's window into the driver AS preview does.
	"$LIVEPICKER_SCRIPTS/preview.sh" victim
	local vid
	vid="$(tmux show-option -gqv @livepicker-linked-id)"

	# SANITY (guards against a vacuous pass): the link really happened — the
	# victim's window id is present in the driver's window list.
	assert_contains "$vid" "@" "preview linked a window id"
	assert_contains "$(tmux list-windows -t "=$TEST_DRIVER_SESSION" -F '#{window_id}')" \
		"$vid" "victim's window linked into the driver (setup for the no-orphan assertion)"

	# FIX PATH: do-delete victim unlinks FIRST, then kills -> NO orphan.
	"$LIVEPICKER_SCRIPTS/session-mgmt.sh" do-delete victim

	# (g) the victim's window id is GONE from the driver (no orphan).
	case "$(tmux list-windows -t "=$TEST_DRIVER_SESSION" -F '#{window_id}')" in
		*"$vid"*) fail "do-delete left the victim's window as an orphan in the driver" ;;
		*)        pass "do-delete left no orphan window in the driver" ;;
	esac
	# (g) the victim session is gone.
	if lp_mgmt_has victim; then fail "do-delete left the victim session alive"; else pass "do-delete killed the victim session"; fi
}

# test_raw_kill_leaks_orphan — contract (g) CONTROL half: a RAW kill-session
# (bypassing do-delete / NO unlink-first) leaves the victim's window SURVIVING in
# the driver (the orphan). This proves the leak is real and makes the FIX half
# (test_delete_unlinks_preview_no_orphan) a meaningful regression guard. preview.sh
# is client-independent -> NO attach_test_client.
test_raw_kill_leaks_orphan() {
	tmux new-session -d -s victim -x 120 -y 40
	tmux new-session -d -s other -x 120 -y 40
	lp_mgmt_seed_state 0 victim other   # highlight => victim

	# Link the victim's window into the driver.
	"$LIVEPICKER_SCRIPTS/preview.sh" victim
	local vid
	vid="$(tmux show-option -gqv @livepicker-linked-id)"

	# SANITY: the link happened.
	assert_contains "$vid" "@" "preview linked a window id"
	assert_contains "$(tmux list-windows -t "=$TEST_DRIVER_SESSION" -F '#{window_id}')" \
		"$vid" "victim's window linked into the driver (setup for the leak assertion)"

	# CONTROL: a RAW kill-session (no unlink) leaves the window SURVIVING in the
	# driver — the orphan EXP D (empirical_findings.md F3) documents.
	tmux kill-session -t '=victim' 2>/dev/null || true

	# (g-control) the victim's window id is STILL in the driver (leak reproduced).
	case "$(tmux list-windows -t "=$TEST_DRIVER_SESSION" -F '#{window_id}')" in
		*"$vid"*) pass "raw kill-session reproduced the orphan (victim window survives in the driver)" ;;
		*)        fail "raw kill-session did NOT leak the victim window (control invalid — leak test is vacuous)" ;;
	esac
}

# test_confirm_delete_gates_kill — contract (h): @livepicker-confirm-delete on =>
# `delete` opens confirm-before and the victim SURVIVES until confirmed; contrast
# @livepicker-confirm-delete off => immediate kill. confirm-before needs an
# attached client to display -> attach_test_client FIRST.
#
# The DETERMINISTIC BACKBONE (confirm-before intercepts on confirm-delete=on +
# immediate kill on confirm-delete=off) ALONE proves the gate. The `'y'` send-keys
# drive was a bonus exercise but is NOT reliable under the `script`-pty harness
# client (send-keys to the session/client does not reach the confirm-before
# prompt deterministically) — per the PRP Task 9 GOTCHA, the deterministic
# assertions are KEPT and the flaky send-keys drive is DROPPED rather than risk a
# brittle suite. confirm-before BLOCKS the calling shell process (it waits for the
# client's response), so the confirm-on `delete` invocation is run in the
# background — mirroring how the plugin dispatches it via `run-shell` (async,
# fire-and-forget) in production; the synchronous confirm-off call returns at
# once (no prompt).
test_confirm_delete_gates_kill() {
	attach_test_client
	tmux new-session -d -s victim -x 120 -y 40
	tmux new-session -d -s other -x 120 -y 40
	lp_mgmt_seed_state 0 victim other   # highlight => victim
	tmux set-option -g @livepicker-confirm-delete on

	# (h-on) `delete` opens confirm-before and RETURNS without killing. confirm-
	# before blocks the caller (it waits for the client), so run it in the
	# background the way run-shell would in production.
	"$LIVEPICKER_SCRIPTS/session-mgmt.sh" delete &
	local _del_pid=$!
	sleep 1   # let confirm-before settle so the 'survives' assertion is stable
	if lp_mgmt_has victim; then pass "confirm-before intercepted the delete (victim survives until confirmed)"; \
	else fail "confirm-before did not gate the delete (victim killed without confirmation)"; fi
	# Tear down the lingering confirm-before caller + dismiss the open prompt so
	# teardown_test gets a free client (best-effort; teardown kills the server).
	kill "$_del_pid" 2>/dev/null || true
	wait "$_del_pid" 2>/dev/null || true
	tmux send-keys -t "$TEST_DRIVER_SESSION" C-c 2>/dev/null || true

	# (h-off contrast) recreate the victim, flip confirm-delete off, delete =>
	# immediate kill (no prompt). Proves confirm-before is what gates the kill.
	# Kill any survivor first (the on-phase left victim alive on purpose; a bare
	# new-session -d -s victim would "duplicate session" against it).
	tmux kill-session -t '=victim' 2>/dev/null || true
	tmux new-session -d -s victim -x 120 -y 40
	lp_mgmt_seed_state 0 victim other
	tmux set-option -g @livepicker-confirm-delete off
	"$LIVEPICKER_SCRIPTS/session-mgmt.sh" delete
	if lp_mgmt_has victim; then fail "confirm-delete off did not kill immediately"; \
	else pass "confirm-delete off killed the victim immediately (no prompt)"; fi
}
