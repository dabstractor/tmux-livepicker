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
	# --- T3 (P1.M4.T3.S1): grow status bar + install renderer ---
	# PRD §10 steps 2-4, in order:
	#   (a) SHIFT every genuinely-user-set status-format index up by one,
	#       HIGHEST-FIRST (race-free — PRD §10 step 2 / tmux_primitives §3).
	#       Source = ORIG_STATUS_FORMAT_INDICES (the >=3 space-list STEP 2 saved;
	#       EMPTY in this env -> no-op). We read the LIVE value and copy to [n+1],
	#       then unset [n] (single-index -gu kills ONLY [n] — research FINDING 2).
	#       Restore (P1.M5.T3.S1) replays the saved values at the ORIGINAL [n]
	#       after a -gu reset, so the user's overrides return to [n].
	#   (b) INSTALL the picker renderer at IDX (=@livepicker-status-format-index,
	#       default 0). DOUBLE quotes so $CURRENT_DIR expands to an ABSOLUTE path
	#       at set-time; tmux #() then runs it on every redraw. Single quotes
	#       would store a literal "$CURRENT_DIR" -> renderer never runs
	#       (research FINDING 3).
	#   (c) GROW the status line count by one (PRD §10 step 4). GOTCHA: tmux 3.6b
	#       show-option -gv status returns on/off/2..5 — NOT 0/1; the literal
	#       integer 1 is REJECTED ("unknown value: 1") and $((on+1)) CRASHES under
	#       set -u ("unbound variable"). So normalize via case: on->2, off->on,
	#       2..4->n+1, 5->5 (clamp). status-left/right/window-status-format are
	#       LEFT UNTOUCHED (tubular owns them; Invariant C: line 2 composes from
	#       them when status-format[1] is unset — research FINDING 5).
	local sf_n sf_val sf_indices lp_idx orig_status
	local -a sf_desc=()
	# (a) shift genuinely-user-set indices HIGHEST-FIRST (no-op when the saved
	# list is empty, as in this env). sf_indices is a digit-only space-list
	# (state.sh contract); word-split is intentional and safe.
	sf_indices="$(get_state "$ORIG_STATUS_FORMAT_INDICES" "")"
	# Reverse the ascending saved list to DESCENDING (race-free for adjacent
	# indices; ascending would overwrite the next index's original value).
	# shellcheck disable=SC2086
	for sf_n in $sf_indices; do sf_desc=("$sf_n" "${sf_desc[@]}"); done
	for sf_n in "${sf_desc[@]}"; do
		sf_val="$(tmux show-option -gqv "status-format[$sf_n]" 2>/dev/null)"
		tmux set-option -g "status-format[$((sf_n + 1))]" "$sf_val"
		tmux set-option -gu "status-format[$sf_n]"
	done
	# (b) install the picker renderer at the configured index (default 0).
	lp_idx="$(opt_status_format_index)"
	tmux set-option -g "status-format[$lp_idx]" "#($CURRENT_DIR/renderer.sh)"
	# (c) grow the status line count by one — NORMALIZED for tmux's on/off/2..5
	# (do NOT use $((orig_status + 1)): "on" crashes under set -u and 1 is rejected).
	orig_status="$(get_state "$ORIG_STATUS" "on")"
	case "$orig_status" in
		off|0|"") tmux set-option -g status on  ;;   # was off -> 1 picker line
		on)       tmux set-option -g status 2   ;;   # was 1 line -> 2 (typical)
		2|3|4)    tmux set-option -g status "$((orig_status + 1))" ;;
		5)        tmux set-option -g status 5   ;;   # 5-line cap; renderer overlays [lp_idx] (rare)
		*)        tmux set-option -g status 2   ;;   # defensive default
	esac
	# --- T4 (P1.M4.T4.S1): build livepicker key table + switch key-table ---
	# PRD §8 "Binding" + §6 step 4. While key-table==livepicker, tmux consults
	# ONLY that table (system_context §3 INVARIANT B); unbound keys are DROPPED,
	# never passed to root/prefix/pane. So the user's prefix/root bindings do NOT
	# fire during the picker UNLESS explicitly copied in. This block, in this
	# exact order:
	#   (1) COPY the user's prefix + root bindings into livepicker (skipping the
	#       repurposed next/prev keys), via `source-file` (NOT `tmux $line` —
	#       word-split breaks on complex bindings like display-menu; research
	#       FINDING 1). Skip removes the compound swap-window bindings so the
	#       explicit nav binds below are authoritative (FINDING 4).
	#   (2) BIND the explicit picker keys (typing/actions/nav) — these OVERRIDE
	#       any copied same-key binding (e.g. Down/Up/Enter/a) because they run
	#       LAST (FINDING 2 — copy-first/explicit-last is load-bearing). All
	#       route through scripts/input-handler.sh (P1.M6; need not exist yet —
	#       the binding only stores the command string; it is inert until a key
	#       fires, which is after T5 sets mode-on).
	#   (3) SWITCH key-table to livepicker (global, matching the -g save/restore
	#       contract; the standalone `key-table` cmd is absent on 3.6b — FINDING 3).
	# Discovery (PRD §8) is intentionally OMITTED: the defaults (C-M-Tab /
	# C-M-BTab) already match this user's root-table window-nav keys
	# (system_context §2), and discovery must not override explicit options.
	local lp_key lp_keys lp_tf lp_c

	# (1) COPY prefix + root -> livepicker via source-file (tmux's own parser
	# re-binds each line; the sed rewrites ONLY the first `-T <table>` which is
	# always the table spec). Skip next/prev keys (FINDING 4 skip pattern).
	lp_key="$(opt_next_key)"
	lp_keys="$(opt_prev_key)"
	lp_tf="$(mktemp)"
	{
		tmux list-keys -T prefix 2>/dev/null | sed 's/-T prefix/-T livepicker/'
		tmux list-keys -T root   2>/dev/null | sed 's/-T root/-T livepicker/'
	} | grep -vE -- "-T livepicker[[:space:]]+(${lp_key}|${lp_keys})([[:space:]]|$)" > "$lp_tf"
	tmux source-file "$lp_tf"
	rm -f "$lp_tf"

	# (2) BIND explicit picker keys (run AFTER the copy -> override any copied
	# same-key binding). input-handler.sh path uses $CURRENT_DIR (the scripts/
	# dir global; same idiom as T3's renderer install).
	# typing: a-z A-Z 0-9 and - _ . / (PRD §8; FINDING 5 — `-` binds with no `--`).
	for lp_c in {a..z} {A..Z} {0..9} - _ . /; do
		tmux bind-key -T livepicker "$lp_c" run-shell "$CURRENT_DIR/input-handler.sh type $lp_c"
	done
	# backspace / confirm / cancel (space-list accessors -> word-split; SC2086).
	# shellcheck disable=SC2086
	for lp_c in $(opt_backspace_keys); do
		tmux bind-key -T livepicker "$lp_c" run-shell "$CURRENT_DIR/input-handler.sh backspace"
	done
	# shellcheck disable=SC2086
	for lp_c in $(opt_confirm_keys); do
		tmux bind-key -T livepicker "$lp_c" run-shell "$CURRENT_DIR/input-handler.sh confirm"
	done
	# shellcheck disable=SC2086
	for lp_c in $(opt_cancel_keys); do
		tmux bind-key -T livepicker "$lp_c" run-shell "$CURRENT_DIR/input-handler.sh cancel"
	done
	# nav: next-key + nav-next-keys -> next-session; prev-key + nav-prev-keys -> prev-session.
	# shellcheck disable=SC2086
	for lp_c in $(opt_next_key) $(opt_nav_next_keys); do
		tmux bind-key -T livepicker "$lp_c" run-shell "$CURRENT_DIR/input-handler.sh next-session"
	done
	# shellcheck disable=SC2086
	for lp_c in $(opt_prev_key) $(opt_nav_prev_keys); do
		tmux bind-key -T livepicker "$lp_c" run-shell "$CURRENT_DIR/input-handler.sh prev-session"
	done

	# (3) SWITCH the active key-table to livepicker (global; FINDING 3: -g is
	# mandatory and the standalone `key-table` cmd does not exist on 3.6b).
	tmux set-option -g key-table livepicker
	# --- T4 (P1.M4.T4.S2): suppress session-window-changed hook (insert here) ---
	# --- T5 (P1.M4.T5.S1): first preview + set @livepicker-mode on (insert here) ---
	return 0
}

activate_main "$@" || exit 1
exit 0
