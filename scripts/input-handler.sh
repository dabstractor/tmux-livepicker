#!/usr/bin/env bash
# shellcheck disable=SC1091,SC2153
#   SC1091: sources sibling libs (options/utils/state) via the resolved $CURRENT_DIR;
#           follow with `shellcheck -x` if you want them traced.
#   SC2153: STATE_* are readonly CONTRACT constants defined in state.sh
#           (sourced above); shellcheck sees no assignment here.
# scripts/input-handler.sh — tmux-livepicker input dispatcher.
#
# Invoked via `run-shell` from the livepicker key table that activate
# (P1.M4.T4.S1, COMPLETE) installed. Each typing key is bound as:
#   tmux bind-key -T livepicker "$lp_c" run-shell "$CURRENT_DIR/input-handler.sh type $lp_c"
# run-shell execs the WHOLE string via the shell (word-split on spaces), so:
#   argv[1] = action (type | backspace | next-session | prev-session | confirm | cancel)
#   argv[2] = the typed char (for `type`) — verified to pass correctly for
#             a-z A-Z 0-9 - _ . / (the `-` is the 2nd positional, NOT a flag).
#
# THIS FILE (P1.M6.T1.S1) implements ONLY the `type` action. The remaining
# actions are seam comments filled by P1.M6.T2-T4 (mirror the incremental build
# of scripts/restore.sh across P1.M5.T1-T4):
#   type           -> append char to @livepicker-filter, index=0, refresh      [T1.S1 — HERE]
#   backspace      -> remove last char, index=0, refresh                       [T2 seam]
#   next-session   -> index+1 (wrap), refresh preview + status                 [T2 seam]
#   prev-session   -> index-1 (wrap), refresh preview + status                 [T2 seam]
#   confirm        -> resolve target / create / switch-client once / restore   [T3 seam]
#   cancel         -> restore.sh cancel                                        [T4 seam]
#
# LOAD-BEARING RULES (research/input_handler_type_findings.md):
#  - The handler does NOT filter. The RENDERER (scripts/renderer.sh, COMPLETE)
#    filters @livepicker-list by @livepicker-filter (case-insensitive substring)
#    and highlights @livepicker-index on each redraw. The data-flow diagram's
#    "recompute list" is the RENDERER's filtered VIEW — the handler NEVER touches
#    @livepicker-list (FINDING 2). For `type`: append char to filter, index=0,
#    refresh — that is all.
#  - read $2 as `char="${2:-}"` (set -u safety; the binding always passes a char,
#    but a manual/stale invocation without one would crash under set -u — FINDING 1).
#  - append via parameter expansion: `new_filter="$(get_state "$STATE_FILTER" "")$char"`
#    (NO bash += ; NO shell-escaping of $char — FINDING 6).
#  - index=0 is ALWAYS safe (renderer clamps + handles FLEN=0 — FINDING 4). Do
#    NOT check whether the filter matches — that is the renderer's concern.
#  - `tmux refresh-client -S` re-runs the #() renderer (PRD §10/§13, primitives
#    §3). Requires a client (production always has one — the typing key fires
#    from an attached client while key-table==livepicker). Guard for the detached
#    edge: `2>/dev/null || true` (FINDING 3; mirror restore.sh STEP 6c).
#  - NO `set -e` (refresh legitimately returns non-zero detached); `set -u`
#    inherited from the sourced libs — do NOT re-declare it. NO getopts (it would
#    mis-parse `-`, `.`, `/` — use positional $1/$2 — FINDING 1).
#
# DEPENDS ON (source order load-bearing — state.sh needs utils.sh first):
#   options.sh (opt_*), utils.sh (tmux_*), state.sh (get_state/set_state/STATE_*).
#   input-handler.sh is its OWN process under run-shell -> it MUST source its own
#   trio (sourced state does not cross process boundaries — restore.sh FINDING 7).

CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=options.sh
source "$CURRENT_DIR/options.sh"
# shellcheck source=utils.sh
source "$CURRENT_DIR/utils.sh"
# shellcheck source=state.sh
source "$CURRENT_DIR/state.sh"
# shellcheck source=filter.sh
source "$CURRENT_DIR/filter.sh"

# _confirm_land_on_session TARGET — the shared "switch to a chosen session and
# tear down to leave the client there" sequence. Called by BOTH the session-mode
# target path and the create-on-success path in the confirm branch below.
#
# CRITICAL (research FINDING 1/2 — the catastrophic bug this helper exists to
# prevent): during browsing preview.sh linked the candidate's window into the
# DRIVER (@livepicker-orig-session), tracked in @livepicker-linked-id. restore.sh
# STEP-1 unlinks current_session:$linked_id — so if we switch-client FIRST,
# current_session becomes the TARGET and restore would unlink the target's OWN
# window and destroy the session. We therefore unlink the DRIVER's preview window
# (ORIG_SESSION:$linked_id) BEFORE the switch. restore's redundant STEP-1 unlink
# then targets target:$linked_id (a singly-linked origin) and fails harmlessly
# (rc=1, swallowed). Verified live (research SCENARIO TEST B).
#
# CRITICAL (research FINDING 3): ONLY call this from a branch that switches the
# client. Window mode and cancel issue no switch -> leave cleanup to restore.
_confirm_land_on_session() {
	local tgt="${1:-}"
	local orig_session linked_id
	orig_session="$(get_state "$ORIG_SESSION" "")"
	linked_id="$(get_state "$STATE_LINKED_ID" "")"
	# Drop the DRIVER's preview window BEFORE the switch (FINDING 1/2). unlink-window
	# WITHOUT -k removes ONE link; the source session KEEPS its window (preview.sh
	# FINDING 1). Singly-linked edge rc=1 is swallowed (preview.sh FINDING 2). Empty
	# linked_id (self-session was last previewed, or preview never ran) -> skip.
	# H2 HARDEN: unlink-window WITHOUT -k removes ONE link, but if the named
	# session's ONLY window is linked_id, tmux KILLS that session (rc=0). The
	# driver (ORIG_SESSION) normally retains ORIG_WINDOW, so this is defensive —
	# but verify the driver has another window before unlinking; if not, leave the
	# link (the switch + restore keep will handle it, and killing the driver would
	# strand the client). Count windows in orig_session EXCLUDING nothing — if
	# count > 1 OR the linked window is not the active one, unlink is safe.
	if [ -n "$linked_id" ] && [ -n "$orig_session" ]; then
		local drv_wins drv_active
		drv_wins="$(tmux list-windows -t "=$orig_session" 2>/dev/null | wc -l)"
		drv_active="$(tmux list-windows -t "=$orig_session" -F '#{window_id}' -f '#{window_active}' 2>/dev/null)"
		# Safe to unlink when the driver has >1 window, OR the active window is a
		# different one (so unlinking linked_id won't empty the session). When the
		# driver has exactly one window AND it is linked_id, skip the unlink to
		# avoid killing the driver (the switch-client below moves the client off
		# it anyway; the orphaned link is benign — it unlinks with the source on
		# restore if still present).
		if [ "$drv_wins" -gt 1 ] || [ "$drv_active" != "$linked_id" ]; then
			tmux unlink-window -t "$orig_session:$linked_id" 2>/dev/null || true
		fi
	fi
	# The ONE session switch (PRD §4/§6/§14). exact-match = (FINDING 8); guard a
	# vanished session. Fires client-session-changed ONCE — the engine dedups a
	# same-session switch to 0 entries (FINDING 7), so no special-case is needed.
	tmux switch-client -t "=$tgt" 2>/dev/null || true
	# Tear down the picker (status/key-table/layout/hook/state) but LEAVE the client
	# on the target — keep does NOT switch again (P1.M5.T2.S1 restore contract).
	# restore STEP-1's redundant unlink (target:$linked_id) fails harmlessly; STEP-6
	# clear_all_state clears STATE_LINKED_ID + every @livepicker-* key.
	"$CURRENT_DIR/restore.sh" keep
}

# argv[1] = action; argv[2] = the typed char (for `type`). Dispatch + act.
input_main() {
	local action char new_filter cur_filter cur_list cur_index L new_idx target pick_type query orig_session linked_id
	local -a filtered=()
	action="${1:-}"

	case "$action" in
		type)
			# --- P1.M6.T1.S1: append the typed char to the query, reset the
			#     highlight to the top filtered match, force a status redraw.
			# PRD §6 Filtering: "Each typed character appends to @livepicker-filter
			# and resets the index to the top match. After each change, run
			# `tmux refresh-client -S` so the status renderer re-evaluates and the
			# picker redraws." The renderer (scripts/renderer.sh) does the actual
			# filtering + highlighting — the handler only updates filter/index +
			# refresh (research FINDING 2: never touch @livepicker-list).
			char="${2:-}"
			# No char (manual/stale invocation) -> no-op (never crash the picker).
			[ -z "$char" ] && return 0
			# Append via parameter expansion (FINDING 6). get_state defaults to ""
			# so the FIRST keystroke appends to an empty query. The RAW query is
			# stored (case preserved — filtering is case-insensitive at RENDER
			# time, not here).
			new_filter="$(get_state "$STATE_FILTER" "")$char"
			set_state "$STATE_FILTER" "$new_filter"
			# Reset the highlight to the top filtered match (PRD §6). Always safe
			# — the renderer clamps + handles FLEN=0 itself (FINDING 4).
			set_state "$STATE_INDEX" "0"
			# Force the #() renderer to re-run (PRD §10/§16). Requires a client
			# (production always has one); guard the detached edge (FINDING 3).
			tmux refresh-client -S 2>/dev/null || true
			return 0
			;;
		# --- P1.M6.T2.S1 seam: backspace / next-session / prev-session ---
		# backspace:      new_filter="${old_filter%?}"; set_state FILTER; index=0; refresh.
		# next-session:   index = (index+1) % FLEN (wrap); refresh preview.sh + refresh -S.
		# prev-session:   index = (index-1+FLEN) % FLEN (wrap); refresh preview.sh + refresh -S.
		# (FLEN comes from re-filtering @livepicker-list by @livepicker-filter —
		#  the same case-insensitive substring the renderer uses.)
		backspace)
			# --- P1.M6.T2.S1: trim the last char off the query, reset the
			#     highlight to the top filtered match, force a status redraw.
			# PRD §6 Filtering: "Backspace removes the last character. After
			# each change, run tmux refresh-client -S ..." The renderer does the
			# filtering + highlighting — the handler only trims filter/index +
			# refresh (research FINDING 2/4).
			# CONTRACT (work-item §3): backspace = filter+index+refresh ONLY.
			# It does NOT call preview.sh (FINDING 4) — the top match is already
			# shown; shortening the filter may re-admit a different top match
			# (a known minor UX gap that re-syncs on the next nav/confirm).
			cur_filter="$(get_state "$STATE_FILTER" "")"
			# ${var%?} removes the shortest trailing match of one char. On an
			# empty var it yields "" (no error, no set -u issue). Guard empty
			# so the write is an explicit no-op when nothing is left to erase.
			if [ -n "$cur_filter" ]; then
				new_filter="${cur_filter%?}"
				set_state "$STATE_FILTER" "$new_filter"
			fi
			# Reset the highlight to the top filtered match (PRD §6). Always
			# safe — the renderer clamps + handles FLEN=0 itself.
			set_state "$STATE_INDEX" "0"
			# Force the #() renderer to re-run (PRD §10/§16). Guard the detached
			# edge (FINDING 3; mirror the `type` branch / restore.sh STEP 6c).
			tmux refresh-client -S 2>/dev/null || true
			return 0
			;;
		next-session)
			# --- P1.M6.T2.S1: move the highlight DOWN within the FILTERED list
			#     (wrapping), refresh the live preview + the status renderer.
			# PRD §6 Session navigation: "next-session ... moves @livepicker-index
			# within the filtered list (wrapping). Each move refreshes the
			# preview (section 7) and the status renderer. Navigation must not
			# call switch-client." (Invariant A — PRD §4 / system_context §3.)
			# Re-filter via the SAME function the renderer uses (work-item
			# CONTRACT point 1; research FINDING 2/3) so L == the renderer's FLEN
			# and filtered[new_idx] is the session the renderer will highlight.
			cur_list="$(get_state "$STATE_LIST" "")"
			cur_filter="$(get_state "$STATE_FILTER" "")"
			mapfile -t filtered < <(lp_build_filtered "$cur_list" "$cur_filter")
			L="${#filtered[@]}"
			# Nothing matches -> no-op (never divide by zero; FINDING 5).
			[ "$L" -eq 0 ] && return 0
			# Sanitize the stored index to a non-negative int (it is a STRING
			# option; FINDING 5) before the modulo.
			cur_index="$(get_state "$STATE_INDEX" "0")"
			[[ "$cur_index" =~ ^[0-9]+$ ]] || cur_index=0
			# Wrap modulo L (PRD §6 "wrapping"). No +L needed for next.
			new_idx=$(( (cur_index + 1) % L ))
			# Set the NEW index FIRST, resolve the target at it, THEN preview +
			# refresh (so the highlight + the live preview agree — FINDING 5).
			set_state "$STATE_INDEX" "$new_idx"
			target="${filtered[$new_idx]}"
			# Delegate the live link/select to preview.sh (P1.M3; FINDING 9). It
			# fires session-window-changed (suppressed by activate T4.S2) but
			# NEVER client-session-changed (Invariant A). Guard a mid-nav failure
			# (session gone) so nav still advances + redraws.
			"$CURRENT_DIR/preview.sh" "$target" 2>/dev/null || true
			tmux refresh-client -S 2>/dev/null || true
			return 0
			;;
		prev-session)
			# --- P1.M6.T2.S1: move the highlight UP within the FILTERED list
			#     (wrapping, reverse). Mirror of next-session.
			cur_list="$(get_state "$STATE_LIST" "")"
			cur_filter="$(get_state "$STATE_FILTER" "")"
			mapfile -t filtered < <(lp_build_filtered "$cur_list" "$cur_filter")
			L="${#filtered[@]}"
			[ "$L" -eq 0 ] && return 0
			cur_index="$(get_state "$STATE_INDEX" "0")"
			[[ "$cur_index" =~ ^[0-9]+$ ]] || cur_index=0
			# Wrap modulo L (PRD §6). The +L dodges bash's negative-modulo quirk
			# (bash `%` can return negatives for negative operands — FINDING 5).
			new_idx=$(( (cur_index - 1 + L) % L ))
			set_state "$STATE_INDEX" "$new_idx"
			target="${filtered[$new_idx]}"
			"$CURRENT_DIR/preview.sh" "$target" 2>/dev/null || true
			tmux refresh-client -S 2>/dev/null || true
			return 0
			;;
		# --- P1.M6.T3.S1 seam: confirm ---
		# Resolve the target from the filtered list at @livepicker-index. If a
		# target exists: switch-client -t "=target" (the ONE switch). If empty +
		# session mode + @livepicker-create on: new-session -d -s "<query>"; switch.
		# window mode: select-window -t "<session>:<window>". Then restore.sh keep.
		confirm)
			# --- P1.M6.T3.S1: resolve the highlighted item and LAND on it. This is
			#     the ONE branch in the whole flow that calls switch-client (PRD §4/
			#     §6/§14; Invariant A). Research FINDING 9: confirm takes argv[1]
			#     ONLY — it MUST NOT reference $2 (set -u).
			# Re-filter via the SAME function the renderer/nav use (T2.S1 shared
			# filter) so target == the session the renderer is highlighting.
			pick_type="$(opt_type)"
			cur_list="$(get_state "$STATE_LIST" "")"
			cur_filter="$(get_state "$STATE_FILTER" "")"
			mapfile -t filtered < <(lp_build_filtered "$cur_list" "$cur_filter")
			L="${#filtered[@]}"
			# Sanitize the stored index (a STRING option; mirror nav T2.S1).
			cur_index="$(get_state "$STATE_INDEX" "0")"
			[[ "$cur_index" =~ ^[0-9]+$ ]] || cur_index=0
			if [ "$L" -gt 0 ]; then
				# Clamp into range (matches the renderer's clamp; nav keeps index
				# valid — this guards a stale value after an external list shrink).
				[ "$cur_index" -ge "$L" ] && cur_index=$(( L - 1 ))
				target="${filtered[$cur_index]}"
			else
				target=""
			fi
			if [ -n "$target" ]; then
				if [ "$pick_type" = "window" ]; then
				# Window mode (PRD §3/§6; M1 FIX). target is a full
				# "session:window_index" token. To LAND on the chosen window the client
				# must (a) drop the driver's preview window FIRST (the linked window is
				# a shared object; leaving the driver link would be stale), (b) switch
				# to the TARGET's session, (c) select the chosen window there. Then
				# restore with `keep-window` so STEP-2 does NOT re-select ORIG_WINDOW
				# (which would undo the selection and strand the client on the original
				# window). Split target on the FIRST ':' only (session names cannot
				# contain ':'; window names may in pathological cases).
				local w_sess
				w_sess="${target%%:*}"
				orig_session="$(get_state "$ORIG_SESSION" "")"
				linked_id="$(get_state "$STATE_LINKED_ID" "")"
				# Drop the driver's preview window BEFORE the switch (mirror
				# _confirm_land_on_session's H2-hardened unlink). linked_id may be
				# empty (self-session / no preview ran) -> skip.
				if [ -n "$linked_id" ] && [ -n "$orig_session" ]; then
					local drv_wins drv_active
					drv_wins="$(tmux list-windows -t "=$orig_session" 2>/dev/null | wc -l)"
					drv_active="$(tmux list-windows -t "=$orig_session" -F '#{window_id}' -f '#{window_active}' 2>/dev/null)"
					if [ "$drv_wins" -gt 1 ] || [ "$drv_active" != "$linked_id" ]; then
						tmux unlink-window -t "$orig_session:$linked_id" 2>/dev/null || true
					fi
				fi
				# Switch the client to the target's session (the ONE session switch;
				# exact-match). Fires client-session-changed once (expected at confirm).
				tmux switch-client -t "=$w_sess" 2>/dev/null || true
				# Select the chosen window in the target session (target = session:index).
				tmux select-window -t "$target" 2>/dev/null || true
				# Tear down picker state but PRESERVE the chosen window selection
				# (keep-window skips restore STEP-2's ORIG_WINDOW re-select).
				"$CURRENT_DIR/restore.sh" keep-window
					"$CURRENT_DIR/restore.sh" keep-window
				else
					# Session mode: the helper unlinks the driver preview BEFORE
					# switch-client (FINDING 1/2 — load-bearing), switches once,
					# and tears down with restore keep.
					_confirm_land_on_session "$target"
				fi
				return 0
			fi
			# Empty filtered list.
			if [ "$pick_type" = "session" ] && [ "$(opt_create)" = "on" ]; then
				query="$cur_filter"
				# Robust create gate (FINDING 4/5). new-session SILENTLY SANITIZES
				# names (':'->'_', leading '.'->'_') and returns rc=0 with a
				# DIFFERENT name, so checking rc alone would strand the client
				# (switch-client -t "=.hidden" -> rc=1, no such session). Require
				# BOTH new-session rc=0 AND the EXACT $query name to now exist
				# (has-session exact-match =). A duplicate cannot occur here: if
				# an exact-$query session existed it would be a case-insensitive
				# match -> in the filtered list -> this branch is never reached.
				# Empty query -> new-session rc=1 -> gate false -> cancel.
				if tmux new-session -d -s "$query" 2>/dev/null && tmux has-session -t "=$query" 2>/dev/null; then
					_confirm_land_on_session "$query"
				else
					# Invalid/sanitized/empty name -> cancel (PRD §6 Confirm).
					"$CURRENT_DIR/restore.sh" cancel
				fi
				return 0
			fi
			# Window mode, OR session mode with @livepicker-create off: nothing to
			# create -> cancel (PRD §6/§15.22).
			"$CURRENT_DIR/restore.sh" cancel
			return 0
			;;
		# --- P1.M6.T4.S1: two-step cancel (PRD §6 Cancel + §11 + work-item §1).
		#     "clears the query, or cancels if the query is empty."
		# Research FINDING 5: cancel takes argv[1] ONLY — it MUST NOT reference $2
		# (the cancel binding passes no char; mirror confirm/nav/backspace).
		cancel)
			cur_filter="$(get_state "$STATE_FILTER" "")"
			if [ -n "$cur_filter" ]; then
				# First press with a NON-empty filter: CLEAR the query (like
				# backspace-to-empty) and KEEP THE PICKER OPEN. This is the
				# load-bearing UX detail (work-item §1). Mirror backspace (T2.S1)
				# exactly: set filter, set index=0, refresh — but write "" (the
				# WHOLE query) instead of ${cur_filter%?} (one char).
				# FINDING 1: set_state "" is a SET-EMPTY (tmux set-option -g @x ""),
				# NOT an unset; get_state reads it back as "" (the default). Do NOT
				# use tmux_unset_opt / -gu (that is restore's teardown concern).
				set_state "$STATE_FILTER" ""
				# Reset the highlight to the top filtered match (PRD §6). Always
				# safe — the renderer clamps + handles FLEN=0 (empty filter matches
				# ALL names; renderer FINDING 4 / filter.sh).
				set_state "$STATE_INDEX" "0"
				# Force the #() renderer to re-run so the picker redraws with the
				# empty query + the full list (PRD §10/§16). Guard the detached edge
				# (mirror backspace / type / restore.sh STEP 6c).
				tmux refresh-client -S 2>/dev/null || true
				# LOAD-BEARING return: this is what keeps the picker OPEN. Omitting
				# it would fall through to restore.sh cancel (the picker would tear
				# down on the FIRST press — the exact bug the two-step semantics
				# prevents). The clear path writes ONLY @livepicker-filter +
				# @livepicker-index (picker-internal); mode/list/key-table/status
				# are untouched (FINDING 2). No switch-client -> 0 history.
				return 0
			fi
			# Filter ALREADY empty: full cancel (PRD §6 Cancel + §9). Delegate ALL
			# teardown to restore.sh cancel (P1.M5, IMMUTABLE): it unlinks the
			# preview (STEP-1, on current_session==driver — correct: cancel never
			# switched, confirm FINDING 3's "no-switch -> leave cleanup to restore"),
			# selects ORIG_WINDOW (STEP-2), switch-client -t "=$ORIG_SESSION"
			# (STEP-3 — a SAME-SESSION switch the engine dedups -> 0 net history,
			# FINDING 4 / restore_findings A), restores status/key-table/renumber/
			# hook (STEP-4) + layout (STEP-5), clear_all_state + unbind-key -a -T
			# livepicker + refresh-client -S (STEP-6).
			# FINDING 6: use $CURRENT_DIR (the house variable; == scripts/). Do NOT
			# use $SCRIPT_DIR (undefined here -> set -u crash).
			"$CURRENT_DIR/restore.sh" cancel
			return 0
			;;
		*)
			# Unknown action — defensive no-op (never crash the picker).
			return 0
			;;
	esac
}

input_main "$@" || exit 1
exit 0
