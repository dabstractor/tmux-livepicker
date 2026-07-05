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

# argv[1] = action; argv[2] = the typed char (for `type`). Dispatch + act.
input_main() {
	local action char new_filter
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
		backspace|next-session|prev-session)
			return 0
			;;
		# --- P1.M6.T3.S1 seam: confirm ---
		# Resolve the target from the filtered list at @livepicker-index. If a
		# target exists: switch-client -t "=target" (the ONE switch). If empty +
		# session mode + @livepicker-create on: new-session -d -s "<query>"; switch.
		# window mode: select-window -t "<session>:<window>". Then restore.sh keep.
		confirm)
			return 0
			;;
		# --- P1.M6.T4.S1 seam: cancel ---
		# restore.sh cancel (unlink preview, restore status/key-table/layout/hook,
		# switch-client back to ORIG_SESSION, clear @livepicker-* state).
		cancel)
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
