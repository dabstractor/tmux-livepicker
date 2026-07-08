#!/usr/bin/env bash
# shellcheck disable=SC1091,SC2153
#   SC1091: sources sibling libs (options/utils/state/rank) via the resolved
#           $CURRENT_DIR; follow with `shellcheck -x` if you want them traced.
#   SC2153: STATE_*/ORIG_* are readonly CONTRACT constants defined in state.sh
#           (sourced above); shellcheck sees no assignment here.
# scripts/session-mgmt.sh — tmux-livepicker session/window MANAGEMENT (PRD §21).
#   rename        : open tmux command-prompt pre-filled with the highlighted name.
#   do-rename NEW : apply rename-session/rename-window, detect sanitization/
#                   collision, rewrite @livepicker-list (session mode), keep the
#                   highlight, and refresh-client -S. The picker STAYS OPEN
#                   throughout (no restore).
# Invoked via run-shell: from input-handler.sh `rename` (delegated by the C-r
#   binding P2.M1.T1.S1 installed), and from the command-prompt template
#   `do-rename %%` (on submit).
#
# LOAD-BEARING RULES (research/findings.md):
#  - `set -u` ONLY; NEVER `set -e`. rename-session legitimately returns rc!=0 on
#    collision; `set -e` would abort the script and strand the picker. Check rc
#    with `if ! …; then …; fi` (mirror restore.sh / input-handler.sh). FINDING 10.
#  - rename-session rc=0 does NOT mean "unchanged" (FINDING 2). Sanitization
#    (`:`->`_`, leading `.`->`_`) returns rc=0 with a DIFFERENT name. ALWAYS read
#    the actual name back via the STABLE session id and compare to $NEW.
#  - After a sanitized rename the session is named neither $S nor $NEW (FINDING
#    1/3). Target rename-session AND the read-back by the STABLE session id
#    (captured from `list-sessions -F '#{session_id} #{session_name}'`), bare
#    `$N` — NOT `=S` (a name target can't find the renamed session to revert).
#  - OUTPUT §4: sanitized/collision names abort with a message and NO rename.
#    Pre-detect the documented rules (FINDING 2); as a safety net REVERT any
#    rename tmux silently applied (read-back != $NEW -> rename back to $S via
#    the id). Never silently mis-rename. FINDING 3.
#  - Window mode (FINDING 4): rename-window does NOT change the window index ->
#    the picker token (session:window_index) is unchanged -> NO STATE_LIST
#    rewrite. Window names are NOT sanitized. Same shape: rename-window + rc
#    check + refresh.
#  - FINDING 8: a rename does NOT change the window id and does NOT reorder the
#    list -> @livepicker-linked-id stays valid (NO preview re-link/re-sync) and
#    @livepicker-index is UNCHANGED (highlight stays). Only refresh-client -S.
#  - The `%%` command-prompt substitution uses the EXACT PRD template (unquoted
#    %%); do NOT wrap %% in quotes (FINDING 6 — that trades one breakage class
#    for another and deviates from the contract; the limitation rides to P4).
#
# DEPENDS ON (source order load-bearing — state.sh needs utils.sh first):
#   options.sh (opt_type), utils.sh (tmux_*), state.sh (get_state/set_state/
#   STATE_*), rank.sh (lp_rank — the SAME ranker the renderer/confirm/nav use so
#   rename resolves the SAME highlighted item the renderer shows). NOT layout.sh
#   (no viewport/scroll work). session-mgmt.sh is its OWN process under run-shell
#   -> it MUST source its own quartet (sourced state does not cross process
#   boundaries — restore.sh FINDING 7).

set -u   # NOT -e (rename-session legitimately rc!=0 on collision); NOT -o pipefail.

CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=options.sh
source "$CURRENT_DIR/options.sh"
# shellcheck source=utils.sh
source "$CURRENT_DIR/utils.sh"
# shellcheck source=state.sh
source "$CURRENT_DIR/state.sh"
# shellcheck source=rank.sh
source "$CURRENT_DIR/rank.sh"

# _lp_resolve_highlighted — echo the highlighted session name (session mode) or
# the "session:window_index" token (window mode), or "" if the ranked list is
# empty. VERBATIM resolution from input-handler.sh `confirm` (so the target
# resolved here == the item the renderer is highlighting on the status line).
# Reads STATE_LIST/STATE_FILTER (re-rank via lp_rank) + STATE_INDEX, clamped into
# range (mirrors confirm's clamp). Empty ranked list -> echo nothing + return 0.
_lp_resolve_highlighted() {
	local _list _filt _idx _L
	local -a _filtered=()
	_list="$(get_state "$STATE_LIST" "")"
	_filt="$(get_state "$STATE_FILTER" "")"
	mapfile -t _filtered < <(lp_rank "$_list" "$_filt")
	_L="${#_filtered[@]}"
	[ "$_L" -eq 0 ] && return 0   # empty ranked list -> no target (echo nothing)
	_idx="$(get_state "$STATE_INDEX" "0")"
	# Sanitize the stored index (a STRING option; mirror confirm/nav).
	[[ "$_idx" =~ ^[0-9]+$ ]] || _idx=0
	# Clamp into range (matches the renderer's clamp).
	[ "$_idx" -ge "$_L" ] && _idx=$(( _L - 1 ))
	printf '%s' "${_filtered[$_idx]}"
}

# session_mgmt_rename — resolve the highlighted target; no-op if empty; branch on
# opt_type (session|window); open tmux's command-prompt pre-filled with the
# current name. The template uses the EXACT PRD form (unquoted `%%`); the outer
# string is double-quoted so $CURRENT_DIR expands to the absolute scripts/ dir
# at call time and `%%` stays literal for tmux's command-prompt to substitute on
# submit. While the prompt is open it captures input (the livepicker table is
# suspended); tmux restores the table on submit/escape -> no extra binding work.
# Escape cancels (do-rename NOT run). The picker stays OPEN throughout (no
# restore call). FINDING 5.
session_mgmt_rename() {
	local _target _pick_type _wprefill
	_target="$(_lp_resolve_highlighted)"
	[ -z "$_target" ] && return 0   # ranked empty -> no-op (PRD §21.42 step 1)
	_pick_type="$(opt_type)"
	if [ "$_pick_type" = "window" ]; then
		# Window token = "session:window_index". Prefill the current WINDOW NAME
		# (display-message -p -t "$token" '#{window_name}'; client-independent via
		# the explicit target). Guard an invalid/vanished target.
		_wprefill="$(tmux display-message -p -t "$_target" '#{window_name}' 2>/dev/null || true)"
		tmux command-prompt -I "$_wprefill" -p "Rename window:" \
			"run-shell '$CURRENT_DIR/session-mgmt.sh do-rename %%'"
	else
		# Session mode: prefill the highlighted SESSION NAME ($_target).
		tmux command-prompt -I "$_target" -p "Rename session:" \
			"run-shell '$CURRENT_DIR/session-mgmt.sh do-rename %%'"
	fi
	return 0
}

# session_mgmt_do_rename — $1 = NEW name (the command-prompt substitution on
# submit; empty -> no-op). Re-resolve the target (the index is stable during the
# prompt but do-rename runs in its own process, so resolution must run here).
# Branch session/window:
#  - window (FINDING 4): rename-window -t "$token" "$NEW"; rc!=0 -> message, no
#    rename. NO STATE_LIST rewrite (the token is index-based, unchanged).
#    refresh-client -S. Done.
#  - session (FINDING 1/2/3): pre-detect the documented sanitization rules ->
#    abort NO rename; rename targeting the STABLE session id; rc!=0 -> collision,
#    no rename; read the actual name back by id; if != $NEW (unpredicted
#    sanitization) REVERT to $S via the id -> no rename. Clean success (_actual
#    == _new) rewrites STATE_LIST in place ($S -> _new), keeps the index (rename
#    doesn't reorder -> highlight stays), and refresh-client -S. FINDING 7/8.
session_mgmt_do_rename() {
	local _new="${1:-}"
	[ -z "$_new" ] && return 0   # empty submit -> no-op (PRD §21.42)
	local _target _pick_type
	_target="$(_lp_resolve_highlighted)"
	[ -z "$_target" ] && return 0
	_pick_type="$(opt_type)"

	if [ "$_pick_type" = "window" ]; then
		# FINDING 4: rename-window does NOT change the index -> the picker token
		# (session:window_index) is unchanged -> NO STATE_LIST rewrite. Window names
		# are NOT sanitized. rc!=0 only on an invalid target. Refresh to redraw the
		# window-status name.
		if ! tmux rename-window -t "$_target" "$_new" 2>/dev/null; then
			tmux display-message "livepicker: cannot rename window '$_target'"
			return 0
		fi
		tmux refresh-client -S 2>/dev/null || true
		return 0
	fi

	# --- session mode ---
	# (a) PRE-detect the DOCUMENTED tmux sanitization rules (FINDING 2): ':' anywhere,
	#     or a leading '.'. Abort BEFORE renaming so the session is NEVER renamed
	#     under a different name (OUTPUT §4). Per-rule messages tell the user why.
	case "$_new" in
		*:*) tmux display-message "livepicker: ':' is not allowed in a session name"; return 0 ;;
	esac
	case "$_new" in
		.*)  tmux display-message "livepicker: a session name cannot start with '.'"; return 0 ;;
	esac

	# (b) Capture the STABLE session id (rename/revert/read-back by the bare id;
	#     FINDING 1/3). After a sanitized rename the session is named neither $S
	#     nor $NEW, so a NAME target can't find it. The id does NOT change across
	#     rename. `awk -v s="$S" '$2==s{print $1; exit}'` resolves the id from the
	#     list-sessions pairing (a spaced $S would defeat the field split — that
	#     rides the documented %% limitation, FINDING 6).
	local _S _sid _actual
	_S="$_target"
	_sid="$(tmux list-sessions -F '#{session_id} #{session_name}' 2>/dev/null \
		| awk -v s="$_S" '$2==s{print $1; exit}')"
	[ -z "$_sid" ] && return 0   # _S vanished (race) -> no-op
	if ! tmux rename-session -t "$_sid" "$_new" 2>/dev/null; then
		# rc!=0 -> collision (a session named $_new exists) OR invalid -> nothing
		# renamed (FINDING 2). Picker stays open, list UNCHANGED.
		tmux display-message "livepicker: cannot rename '$_S' to '$_new' (in use or invalid)"
		return 0
	fi
	_actual="$(tmux display-message -p -t "$_sid" '#{session_name}' 2>/dev/null || true)"
	if [ "$_actual" != "$_new" ]; then
		# SAFETY NET (FINDING 3): tmux sanitized in an unpredicted way (rc=0,
		# different name). REVERT to $S via the stable id -> NO rename; never silent.
		# The pre-detect above covers the documented cases; this catches anything
		# else so we never silently mis-rename. Best-effort (`|| true`): a
		# pathological race (another session taking $S in the ms between rename and
		# revert) could leave the sanitized name; the pre-detect makes this rare.
		tmux rename-session -t "$_sid" "$_S" 2>/dev/null || true
		tmux display-message "livepicker: '$_new' is not a valid session name"
		return 0   # list UNCHANGED, picker stays open
	fi

	# (c) Clean success (_actual == _new). FINDING 7: rewrite STATE_LIST in place
	#     (replace the $_S line with $_new). Whole-line compare handles spaces;
	#     session names are unique -> exactly one match. Rebuild with a join loop
	#     that emits NO trailing newline (mirror activate's format; the trailing
	#     newline is stripped by $() at capture time, FINDING 7).
	local _list _new_list _first _l _i
	local -a _lines=()
	_list="$(get_state "$STATE_LIST" "")"
	mapfile -t _lines < <(printf '%s' "$_list")
	for _i in "${!_lines[@]}"; do
		[ "${_lines[$_i]}" = "$_S" ] && _lines[_i]="$_new"
	done
	_new_list=""
	_first=1
	for _l in "${_lines[@]}"; do
		if [ "$_first" = 1 ]; then
			_new_list="$_l"
			_first=0
		else
			_new_list="$_new_list"$'\n'"$_l"
		fi
	done
	set_state "$STATE_LIST" "$_new_list"
	# FINDING 8: index unchanged (rename doesn't reorder) -> highlight stays; window
	# id unchanged -> NO preview re-link. Just redraw the status so the §19 renderer
	# reprints the new name in the tab.
	tmux refresh-client -S 2>/dev/null || true
	return 0
}

# session_mgmt_delete — the `delete)` action (PRD §21 §3.43). Resolve the
# highlighted session/window, apply the guards (refuse with a message + NO
# kill), then either confirm-before (if opt_confirm_delete on) or call do-delete
# directly. The picker STAYS OPEN (no restore). MUST NOT reference $2 (the
# M-BSpace binding passes no char; mirror rename/confirm).
session_mgmt_delete() {
	local _target _pick_type _orig _t_sess _list
	_target="$(_lp_resolve_highlighted)"
	[ -z "$_target" ] && return 0   # ranked empty -> no-op (PRD §21 §3.43 step 1)
	_pick_type="$(opt_type)"
	_orig="$(get_state "$ORIG_SESSION" "")"
	# Guard A: refuse the DRIVER (killing it detaches the client). Session mode:
	# _target is the name; window mode: _target is "session:window_index" -> session part.
	if [ "$_pick_type" = "window" ]; then _t_sess="${_target%%:*}"; else _t_sess="$_target"; fi
	if [ -n "$_orig" ] && [ "$_t_sess" = "$_orig" ]; then
		tmux display-message "livepicker: cannot delete the driver session"
		return 0
	fi
	# Guard B: refuse when deleting would strand the client / kill the server.
	if [ "$_pick_type" = "window" ]; then
		# Window mode: refuse the driver's ONLY window (FINDING 8).
		if [ -n "$_orig" ]; then
			local _drv_wins
			_drv_wins="$(tmux list-windows -t "=$_orig" 2>/dev/null | wc -l)"
			if [ "$_drv_wins" -le 1 ] && [ "$_t_sess" = "$_orig" ]; then
				tmux display-message "livepicker: cannot delete the driver's only window"
				return 0
			fi
		fi
	else
		# Session mode: raw list must have >=2 entries (FINDING 2: killing the
		# last session kills the server). mapfile makes "" a truly empty array.
		local -a _l=()
		_list="$(get_state "$STATE_LIST" "")"
		mapfile -t _l < <(printf '%s' "$_list")
		if [ "${#_l[@]}" -le 1 ]; then
			tmux display-message "livepicker: cannot delete the last session"
			return 0
		fi
	fi
	# confirm-before (optional; PRD §21 §3.43 step 3; FINDING 5). $S is resolved
	# here (NOT %%). On 'y' it fires do-delete $S as its own run-shell; on n/Esc
	# nothing runs. While open it suspends the livepicker table; picker stays open.
	if [ "$(opt_confirm_delete)" = "on" ]; then
		if [ "$_pick_type" = "window" ]; then
			tmux confirm-before -p "Kill window $_target? (y/n)" \
				"run-shell '$CURRENT_DIR/session-mgmt.sh do-delete $_target'"
		else
			tmux confirm-before -p "Kill session $_target? (y/n)" \
				"run-shell '$CURRENT_DIR/session-mgmt.sh do-delete $_target'"
		fi
		return 0
	fi
	# No confirm: call do-delete directly (pass S as the arg).
	session_mgmt_do_delete "$_target"
	return 0
}

# session_mgmt_do_delete S — the destructive half (PRD §21 §3.43 step 4).
# argv[1] = S (session name OR "session:window_index") — S is forwarded by
# session_mgmt_main as this function's $1 (mirror do_rename's $1=NEW). Session
# mode: unlink the preview FIRST if it belongs to S (prevents the orphan leak,
# FINDING 3), then kill-session. Window mode: kill-window (destroys the shared
# window -> no orphan, FINDING 8). Then rewrite STATE_LIST, clamp the index onto
# a neighbour, re-rank, re-sync the preview to the new highlight, refresh. Runs
# as its own process (from session_mgmt_delete, OR standalone from confirm-before).
session_mgmt_do_delete() {
	local _S="${1:-}"
	[ -z "$_S" ] && return 0
	local _pick_type _orig _linked _list _new_list
	_pick_type="$(opt_type)"
	_orig="$(get_state "$ORIG_SESSION" "")"
	_linked="$(get_state "$STATE_LINKED_ID" "")"
	_list="$(get_state "$STATE_LIST" "")"

	# DEFENSIVE re-check of the catastrophic length-<=1 guard (FINDING 2). The
	# confirm-delete path has a time gap; a raced external kill could make S the
	# last session -> killing it shuts the server down. S==ORIG_SESSION is stable
	# across the gap, so only the length guard is re-checked (session mode).
	if [ "$_pick_type" != "window" ]; then
		local -a _l=()
		mapfile -t _l < <(printf '%s' "$_list")
		if [ "${#_l[@]}" -le 1 ]; then
			tmux display-message "livepicker: cannot delete the last session"
			return 0
		fi
	fi

	if [ "$_pick_type" = "window" ]; then
		# ===== WINDOW MODE (FINDING 8) =====
		# kill-window destroys the window OBJECT in every session -> the driver's
		# link dies with it -> NO orphan leak, NO unlink-first. Re-guard the
		# driver's-only-window (the confirm gap could race).
		if [ -n "$_orig" ]; then
			local _drv_wins
			_drv_wins="$(tmux list-windows -t "=$_orig" 2>/dev/null | wc -l)"
			if [ "$_drv_wins" -le 1 ] && [ "${_S%%:*}" = "$_orig" ]; then
				tmux display-message "livepicker: cannot delete the driver's only window"
				return 0
			fi
		fi
		tmux kill-window -t "$_S" 2>/dev/null || true
		# REBUILD the list: renumber-windows is ON -> killing window i shifts later
		# indices -> surviving tokens are stale. Re-derive exactly as activate does
		# (livepicker.sh:192). The killed window is simply absent.
		_new_list="$(tmux list-windows -a -F '#{session_name}:#{window_index}' 2>/dev/null)"
	else
		# ===== SESSION MODE (FINDINGS 3, 4, 9) =====
		# Unlink the linked preview from the driver FIRST when it belongs to S,
		# else kill-session leaves it as a permanent orphan (FINDING 3). Ownership
		# test (FINDING 4): the linked id is one of S's windows.
		if [ -n "$_linked" ] && [ -n "$_orig" ] && [ -n "$_S" ]; then
			if tmux list-windows -t "=$_S" -F '#{window_id}' 2>/dev/null | grep -Fxq "$_linked"; then
				# unlink ONE link (the driver's); source keeps it; kill below destroys it.
				tmux unlink-window -t "$_orig:$_linked" 2>/dev/null || true
			fi
		fi
		tmux kill-session -t "=$_S" 2>/dev/null || true
		# DROP S from the raw list (sessions do not renumber; in-place line edit,
		# matches the rename sibling; preserves order; one unique match). NOTE: do
		# NOT clear STATE_LINKED_ID — preview.sh's re-link (below) unlinks the now-
		# dead id (rc swallowed) and overwrites it (FINDING 6).
		local -a _lines=()
		local _i _x _first
		mapfile -t _lines < <(printf '%s' "$_list")
		for _i in "${!_lines[@]}"; do
			[ "${_lines[$_i]}" = "$_S" ] && unset '_lines[_i]'
		done
		_new_list=""; _first=1
		for _x in "${_lines[@]}"; do   # "${arr[@]}" skips the unset index
			if [ "$_first" = 1 ]; then _new_list="$_x"; _first=0
			else _new_list="$_new_list"$'\n'"$_x"; fi
		done
	fi

	set_state "$STATE_LIST" "$_new_list"

	# ===== SHARED re-sync tail (FINDINGS 6, 7) =====
	# Re-rank the new list (the SAME function the renderer uses), clamp the index
	# onto a valid neighbour, re-sync the preview to the new highlight, refresh.
	# do-delete is its own process -> invoke preview.sh DIRECTLY (single-arg
	# synchronous form; honors defer ORDERING but not the async -b launcher).
	local _filt _new_L _idx _new_target
	local -a _filtered=()
	_filt="$(get_state "$STATE_FILTER" "")"
	mapfile -t _filtered < <(lp_rank "$_new_list" "$_filt")
	_new_L="${#_filtered[@]}"
	_idx="$(get_state "$STATE_INDEX" "0")"
	[[ "$_idx" =~ ^[0-9]+$ ]] || _idx=0
	if [ "$_new_L" -gt 0 ]; then
		[ "$_idx" -ge "$_new_L" ] && _idx=$(( _new_L - 1 ))   # clamp to a neighbour
		set_state "$STATE_INDEX" "$_idx"
		_new_target="${_filtered[$_idx]}"
	else
		set_state "$STATE_INDEX" "0"
		_new_target=""   # no match -> no preview re-link (mirror _lp_preview_follow)
	fi
	# Re-sync the preview + redraw (§P5). Empty target -> just refresh.
	if [ -n "$_new_target" ]; then
		if [ "$(opt_preview_defer)" = "on" ]; then
			tmux refresh-client -S 2>/dev/null || true
			"$CURRENT_DIR/preview.sh" "$_new_target" 2>/dev/null || true
		else
			"$CURRENT_DIR/preview.sh" "$_new_target" 2>/dev/null || true
			tmux refresh-client -S 2>/dev/null || true
		fi
	else
		tmux refresh-client -S 2>/dev/null || true
	fi
	return 0
}

# session_mgmt_main — dispatch on argv[1]. `rename` opens the prompt;
# `do-rename` applies the rename (argv[2] = the new name). `delete` resolves +
# guards (+ optional confirm-before); `do-delete` (argv[2] = S) unlinks-first +
# kills + rewrites + clamps + re-ranks + re-syncs. Unknown action -> defensive
# no-op (never crash the picker).
session_mgmt_main() {
	local _action="${1:-}"
	case "$_action" in
		rename)
			session_mgmt_rename
			;;
		do-rename)
			session_mgmt_do_rename "${2:-}"
			;;
		delete)
			session_mgmt_delete
			;;
		do-delete)
			session_mgmt_do_delete "${2:-}"
			;;
		*)
			return 0   # unknown action -> defensive no-op
			;;
	esac
}

session_mgmt_main "$@" || exit 1
exit 0
