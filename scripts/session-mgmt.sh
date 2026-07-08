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

# session_mgmt_main — dispatch on argv[1]. `rename` opens the prompt;
# `do-rename` applies the rename (argv[2] = the new name). The `delete`/
# `do-delete` branches are P2.M1.T2.S2's scope (seam comment only — do NOT
# implement here). Unknown action -> defensive no-op (never crash the picker).
session_mgmt_main() {
	local _action="${1:-}"
	case "$_action" in
		rename)
			session_mgmt_rename
			;;
		do-rename)
			session_mgmt_do_rename "${2:-}"
			;;
		# --- P2.M1.T2.S2 seam: delete / do-delete (guards + unlink-first +
		#     kill-session + re-sync). Add `delete)` + `do-delete)` branches here. ---
		*)
			return 0   # unknown action -> defensive no-op
			;;
	esac
}

session_mgmt_main "$@" || exit 1
exit 0
