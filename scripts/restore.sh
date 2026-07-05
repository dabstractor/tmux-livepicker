#!/usr/bin/env bash
# shellcheck disable=SC1091,SC2153
#   SC1091: sources sibling libs (options/utils/state) via the resolved $CURRENT_DIR;
#           follow with `shellcheck -x` if you want them traced.
#   SC2153: ORIG_WINDOW/STATE_LINKED_ID are readonly CONTRACT constants defined in
#           state.sh (sourced above); shellcheck sees no assignment here.
# scripts/restore.sh — tmux-livepicker teardown orchestrator.
#
# argv[1] = 'keep' | 'cancel' (consumed by P1.M5.T2.S1's switch branch; NOT read
# by T1.S1's steps 1-2). Implements PRD §9 "State saved and restored", restore
# list, in order — THIS FILE owns steps 1-2; steps 3-6 land in the T2/T3/T4
# seams below:
#   1. Unlink the preview window from the current session if @livepicker-linked-id is set.  [T1.S1]
#   2. select-window -t "$ORIG_WINDOW".                                            [T1.S1]
#   3. keep: do not switch. cancel: switch-client -t "$ORIG_SESSION".              [T2 seam]
#   4. Restore status, status-format[n], renumber-windows, key-table, the hook.    [T3 seam]
#   5. select-layout "$ORIG_LAYOUT".                                               [T4 seam]
#   6. clear_all_state + unbind the livepicker table.                             [T4 seam]
#
# LOAD-BEARING RULES (research/restore_unlink_select_findings.md):
#  - unlink-window WITHOUT -k removes ONE link; the source session KEEPS its
#    window (FINDING 1). It FAILS (rc=1) only when singly-linked -> ALWAYS
#    `2>/dev/null || true`. NEVER pass -k (would destroy the shared window in
#    ALL sessions — FINDING 2 / preview.sh FINDING 11).
#  - @livepicker-linked-id is EMPTY when the self-session was the last highlight
#    (preview.sh's self-session path clears it). Empty => nothing to unlink ->
#    skip the unlink entirely (work-item point 1).
#  - Address windows by @id, NEVER index (renumber-windows on — FINDING 3 /
#    system_context §2). ORIG_WINDOW is the @N id activate STEP 2 saved.
#  - current_session via `tmux display-message -p '#{session_name}'`. In
#    production a client is attached (restore runs from a key press) and NO
#    switch has happened yet (switch is step 3 / T2), so the client's session ==
#    the driver == ORIG_SESSION (FINDING 4). The test mock MUST attach a client
#    or display-message returns an arbitrary session (detached non-determinism).
#  - unlink-window fires window-unlinked ONLY — NOT session-window-changed, NOT
#    client-session-changed (Invariant A; system_context §3). So this unlink
#    cannot pollute session history.
#  - NO `set -e` (unlink/select/display legitimately return non-zero; a transient
#    failure must not abort a half-restored teardown). `set -u` inherited; every
#    var defaulted at read.
#
# DEPENDS ON (source order load-bearing — state.sh needs utils.sh first):
#   options.sh (opt_*), utils.sh (tmux_*), state.sh (get_state/STATE_*/ORIG_*).
#   restore.sh is its OWN process under run-shell -> it MUST source its own trio
#   (sourced state does not cross process boundaries — FINDING 7).

CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=options.sh
source "$CURRENT_DIR/options.sh"
# shellcheck source=utils.sh
source "$CURRENT_DIR/utils.sh"
# shellcheck source=state.sh
source "$CURRENT_DIR/state.sh"

# argv[1] = 'keep' | 'cancel' (T2's branch; T1.S1's steps 1-2 do not read it).
restore_main() {
	local linked_id orig_window current_session orig_session mode r_status r_kt r_renumber r_hook hk_line hk_idx hk_cmd

	# --- STEP 1 (PRD §9 restore step 1): unlink the preview window ---
	# @livepicker-linked-id is empty when the self-session was the last highlight
	# (preview.sh cleared it) -> nothing to unlink (work-item point 1). Non-empty
	# means a foreign window is linked into the driver -> unlink it from the
	# CURRENT session only (NO -k; source keeps it — FINDING 1; ignore the
	# singly-linked rc=1 — FINDING 2).
	linked_id="$(get_state "$STATE_LINKED_ID" "")"
	if [ -n "$linked_id" ]; then
		current_session="$(tmux display-message -p '#{session_name}' 2>/dev/null || true)"
		# display-message is non-deterministic without a client (FINDING 4); in
		# production a client is attached (== ORIG_SESSION at this point). If it
		# came back empty, fall back to the client-independent saved driver name.
		[ -n "$current_session" ] || current_session="$(get_state "$ORIG_SESSION" "")"
		tmux unlink-window -t "$current_session:$linked_id" 2>/dev/null || true
	fi

	# --- STEP 2 (PRD §9 restore step 2): re-select the original window ---
	# ORIG_WINDOW is the @N id activate saved (NOT an index — renumber-windows on).
	# Guard on non-empty + ignore rc (ORIG_WINDOW could have vanished in a race).
	orig_window="$(get_state "$ORIG_WINDOW" "")"
	[ -n "$orig_window" ] && tmux select-window -t "$orig_window" 2>/dev/null || true

	# --- STEP 3 (PRD §9 restore step 3): keep/cancel client branch ---
	# cancel: switch the client back to the ORIGINAL session (exact-match `=`).
	#   This is the ONLY switch-client in the cancel path. It DOES fire
	#   client-session-changed (FINDING A), but the history engine dedups a
	#   same-session event ([ "$to" = "$CURRENT" ] && return in do_hook) -> zero
	#   net history entries. The client is back where it started.
	# keep: do NOT switch. Confirm (P1.M6.T3.S1) already issued the ONE
	#   switch-client to the chosen target; a second switch here would pollute
	#   history. "keep -> 1" counts the confirm switch, not a restore switch.
	#
	# ${1:-} defaults the arg for `set -u` safety (input-handler always passes
	# keep|cancel). ORIG_SESSION via get_state (client-independent; display-message
	# is non-deterministic detached — FINDING E / T1.S1 FINDING 4). The `=` prefix
	# is exact-match (PRD §13); `2>/dev/null || true` because the session may have
	# vanished (FINDING C).
	mode="${1:-}"
	orig_session="$(get_state "$ORIG_SESSION" "")"
	if [ "$mode" = "cancel" ] && [ -n "$orig_session" ]; then
		tmux switch-client -t "=$orig_session" 2>/dev/null || true
	fi
	# keep: intentionally no else — doing nothing is the contract (FINDING D).

	# --- STEP 4 (PRD §9 restore step 4): restore status / status-format /
	#     key-table / renumber-windows / session-window-changed hook ---
	# The matched teardown of ACTIVATE T3 (status grow) + T4.S1 (key-table switch)
	# + T4.S2 (hook suppress) + the STEP-2 save. Goal: byte-identical to
	# pre-activate (assertable by diffing show-options/show-hooks before vs after).
	#
	# status-format: TRAP 1 (system_context §4). Call the ALREADY-COMPLETE helper
	#   in state.sh — it does `set-option -gu status-format` (clears EVERY index,
	#   incl. the renderer line T3 installed, and tmux re-composes the [0,1,2]
	#   defaults) then replays the saved user-set indices (>=3; EMPTY in this env).
	#   NEVER replay captured default strings (fragile, fights tubular).
	state_status_format_restore
	# status: replay the RAW saved line-count value (e.g. "on"). NO case
	#   normalization on restore (that was T3 grow-only, to dodge the $((on+1))
	#   crash). -g required (T3's grow used -g; matched pair).
	r_status="$(get_state "$ORIG_STATUS" "on")"
	tmux set-option -g status "$r_status"
	# key-table: CORRECTION (research FINDING 3) — MUST use -g. The no-g form does
	#   NOT take effect on show-option -gv (verified; mirrors activate T4.S1
	#   FINDING 3, which mandated -g on the switch). Default "root" (system_context §2).
	r_kt="$(get_state "$ORIG_KEY_TABLE" "root")"
	tmux set-option -g key-table "$r_kt"
	# renumber-windows: round-trip the saved value (e.g. "on"). -g (matched pair).
	r_renumber="$(get_state "$ORIG_RENUMBER" "on")"
	tmux set-option -g renumber-windows "$r_renumber"
	# session-window-changed hook: TRAP 2 (system_context §4) + the index-
	#   preserving CORRECTION (research FINDING 5). GATED on the SAME option as
	#   activate T4.S2's clear (mirror symmetry). Under the gate: replay every
	#   saved `session-window-changed[N] <cmd>` line, preserving BOTH the index N
	#   AND the command verbatim (incl. -b + absolute path). The index-less form
	#   `set-hook -g session-window-changed "<cmd>"` ALWAYS writes [0] and would
	#   CLOBBER multi-index hooks — use `session-window-changed[$hk_idx]`.
	#   If nothing was saved (bare "session-window-changed" line), the loop skips
	#   it -> no set-hook fires -> the hook stays cleared (== "leave unset").
	if [ "$(opt_suppress_window_hook)" = "on" ]; then
		r_hook="$(get_state "$ORIG_HOOK" "")"
		while IFS= read -r hk_line; do
			case "$hk_line" in
				"session-window-changed"|"") continue ;;   # bare name / blank -> skip
			esac
			hk_idx="$(printf '%s\n' "$hk_line" | sed -n 's/^session-window-changed\[\([0-9]\+\)\].*/\1/p')"
			hk_cmd="${hk_line#session-window-changed\[*\] }"
			[ -z "$hk_idx" ] && continue
			tmux set-hook -g "session-window-changed[$hk_idx]" "$hk_cmd" 2>/dev/null || true
		done <<< "$r_hook"
	fi
	# When @livepicker-suppress-window-hook is "off": activate did NOT clear the
	# hook, so the live hook is still the user's original -> restore does nothing
	# here (the if skips). Symmetric with activate T4.S2.

	# --- T4 (P1.M5.T4.S1): select-layout ORIG_LAYOUT + clear_all_state +
	#     unbind-key -T livepicker (insert here) ---
	# PRD §9 restore steps 5-6. select-layout "$ORIG_LAYOUT"; clear_all_state
	# (state.sh — clears the 5 runtime keys + every @livepicker-orig-*); then
	# tmux unbind-key -T livepicker <each> (or unbind-key -aT livepicker).

	return 0
}

restore_main "$@" || exit 1
exit 0
