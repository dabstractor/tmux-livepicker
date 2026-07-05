#!/usr/bin/env bash
# shellcheck disable=SC1091,SC2153
#   SC1091: sources the lib trio (options/utils/state) via $CURRENT_DIR; follow
#           with `shellcheck -x` if you want them traced.
#   SC2153: ORIG_*/STATE_* are readonly CONTRACT constants defined in state.sh
#           (sourced above); shellcheck sees no assignment here.
# scripts/livepicker.sh — tmux-livepicker ACTIVATE orchestrator.
#
# Invoked via `run-shell` from the prefix-key binding plugin.tmux installed
# (P1.M1.T4.S1). Implements PRD §6 Activation steps 1-2 (guard + save); steps 3-7
# (list, status, key-table+hook, first preview, mode-on) are added in place by
# P1.M4.T2-T5 (see the seam comments below).
#
# LOAD-BEARING RULES (research/activate_guard_save_findings.md):
#  - The GUARD is the FIRST statement of activate_main. If @livepicker-mode == on
#    (set only by P1.M4.T5.S1), return 0 silently — a second activation must NOT
#    re-save the picker's state over the user's originals (PRD §16 double-activation).
#  - Capture window via '#{window_id}' (@N token), NOT '#{window_index}'.
#    renumber-windows is on -> indices are unstable (system_context §2).
#  - Save the FULL `show-hooks -g session-window-changed` output VERBATIM into
#    ORIG_HOOK (TRAP 2). show-hooks exits 0 set-or-cleared -> do NOT branch on rc.
#  - status-format: delegate to state_status_format_save (TRAP 1). It keeps ONLY
#    indices>=3 (genuinely user-set; empty in this env) so restore's -gu reset is
#    correct. Do NOT capture/replay the default [0,1,2] strings; do NOT use
#    tmux_is_set (useless for status-format[n] — FINDING 4).
#  - @livepicker-mode is NOT set on here — that is P1.M4.T5.S1's LAST step.
#  - NO `set -e` (display-message/show-hooks legitimately return non-zero on edge
#    cases; a transient failure must not abort a half-saved activate). `set -u`
#    is inherited from options.sh (every var is assigned first).
#
# DEPENDS ON (source order load-bearing — state.sh needs utils.sh first):
#   options.sh (get_opt/opt_*), utils.sh (tmux_save_opt/tmux_get_hook/tmux_set_opt),
#   state.sh (get_state/set_state/STATE_*/ORIG_*/state_status_format_save).

CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=options.sh
source "$CURRENT_DIR/options.sh"
# shellcheck source=utils.sh
source "$CURRENT_DIR/utils.sh"
# shellcheck source=state.sh
source "$CURRENT_DIR/state.sh"

activate_main() {
	# --- STEP 1 (PRD §6.1 / §16): double-activation guard ---
	# If a picker is already active, ignore the second activation silently. This
	# MUST be the first statement: it short-circuits before ANY mutation, so a
	# re-activation cannot re-save the picker's state over the user's originals.
	# @livepicker-mode is set on ONLY by P1.M4.T5.S1, so a fresh run proceeds.
	if [ "$(get_state "$STATE_MODE" "off")" = "on" ]; then
		return 0
	fi

	# --- STEP 2 (PRD §6.2 / §9): save original state into @livepicker-orig-* ---
	# Three display-message captures (NOT option reads -> direct set-option -g,
	# NOT tmux_save_opt). Resolved against the current client (under run-shell the
	# user pressed the prefix key, so a client exists).
	tmux set-option -g "$ORIG_SESSION" "$(tmux display-message -p '#{session_name}')"
	tmux set-option -g "$ORIG_WINDOW"   "$(tmux display-message -p '#{window_id}')"      # @N id, NOT index
	tmux set-option -g "$ORIG_LAYOUT"   "$(tmux display-message -p '#{window_layout}')"
	# Three ordinary option reads (orig_name == src_name -> tmux_save_opt idiom).
	tmux_save_opt key-table key-table
	tmux_save_opt status status
	tmux_save_opt renumber-windows renumber-windows
	# The session-window-changed hook: FULL raw show-hooks output verbatim (single
	# line "session-window-changed[0] run-shell -b <abs path>" here; multi-line ok).
	# show-hooks exits 0 set-or-cleared -> do NOT branch on its rc.
	tmux set-option -g "$ORIG_HOOK" "$(tmux_get_hook session-window-changed)"
	# The status-format array: TRAP 1 (system_context §4). Delegate to the
	# trap-aware helper — it keeps ONLY genuinely-user-set indices (>=3) and
	# stores the list (empty here) + per-index values. Restore does the -gu reset.
	state_status_format_save
	# Init the linked-preview id (no preview linked yet). preview.sh reads this
	# via get_state "$STATE_LINKED_ID" "" — empty means no prior link to unlink.
	set_state "$STATE_LINKED_ID" ""

	# --- T2 (P1.M4.T2.S1): build session/window list + initial selection ---
	# PRD §6 Activation step 3 (build the list) + step 6's initial-selection
	# half (highlight lands on the user's own session/window; the first PREVIEW
	# is P1.M4.T5.S1). Empty filter -> full list shown. Index is 0-based and
	# points at the current session (or current session:window) in the FULL
	# unfiltered list (renderer FINDING 4: empty filter matches all, so the
	# index is valid for filtered==all too).
	local pick_type current list idx i
	local -a items=()
	pick_type="$(opt_type)"                       # session | window (PRD §11; default session)
	current="$(get_state "$ORIG_SESSION" "")"     # client-independent; saved by STEP 2
	if [ "$pick_type" = "window" ]; then
		# Window mode: session:window_index tokens across ALL sessions (PRD §11).
		# The current token is the live session:window_index in the SAME format
		# the list emits -> exact string match. ORIG_WINDOW is the @N id, NOT the
		# index, so the index must come from display-message (client present at
		# activation). (research FINDING 4/5)
		list="$(tmux list-windows -a -F '#{session_name}:#{window_index}' 2>/dev/null)"
		current="$(tmux display-message -p '#{session_name}:#{window_index}')"
	else
		# Session mode: one name per line, tmux default order (NO MRU — PRD §2
		# non-goals). $() strips the trailing newline so the stored value has
		# embedded \n but no trailing \n (renderer mapfile yields exactly N).
		list="$(tmux list-sessions -F '#{session_name}' 2>/dev/null)"
	fi
	# Resolve the 0-based index of `current` in the full list (default 0 if the
	# current session/window vanished between save and list-build — a race; the
	# renderer clamps anyway). PROCESS SUBSTITUTION (not a here-string) so an
	# empty list is a truly empty array (renderer FINDING 3 / research FINDING 8).
	mapfile -t items < <(printf '%s' "$list")
	idx=0
	for i in "${!items[@]}"; do
		[ "${items[$i]}" = "$current" ] && { idx="$i"; break; }
	done
	# Store newline-joined list (verbatim $() output), empty filter (full list),
	# and the resolved index. set_state -> tmux set-option -g preserves embedded
	# newlines (research FINDING 3); renderer reads back exactly N entries.
	set_state "$STATE_LIST" "$list"
	set_state "$STATE_FILTER" ""
	set_state "$STATE_INDEX" "$idx"
	# --- T3 (P1.M4.T3.S1): grow status bar + install renderer (insert here) ---
	# --- T4 (P1.M4.T4.S1/S2): switch key-table + bind keys + suppress hook (insert here) ---
	# --- T5 (P1.M4.T5.S1): first preview + set @livepicker-mode on (insert here) ---
	return 0
}

activate_main "$@" || exit 1
exit 0
