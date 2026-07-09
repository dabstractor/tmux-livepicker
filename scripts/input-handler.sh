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
#   argv[1] = action (type | backspace | next-session | prev-session | confirm | cancel | refresh-width)
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
# shellcheck source=rank.sh
source "$CURRENT_DIR/rank.sh"
# shellcheck source=layout.sh
source "$CURRENT_DIR/layout.sh"   # P1.M3.T2.S1: lp_viewport (shared §19 viewport math; §P7) — scroll-into-view

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

# _lp_sync_preview_to_top_match — re-link the live preview to the TOP filtered
# match (index 0), so the preview pane tracks the status-line highlight when the
# user types / backspaces / clears the query (PRD §3 story 3 + README "the preview
# follows live"). Reconciles PRD §5 (which lists type/backspace as status-only) in
# favour of §3 / the README. Mirrors the nav (next/prev) resolution: same
# lp_rank the renderer uses (so filtered[0] == the highlighted session),
# same preview.sh call + `2>/dev/null || true` guard. type/backspace/cancel-clear
# always reset @livepicker-index to 0, so the top match is ALWAYS filtered[0].
# Empty filtered list (no matches) -> skip the preview (leave the prior pane as-is,
# mirroring nav's `[ "$L" -eq 0 ] && return 0` guard).
_lp_sync_preview_to_top_match() {
	local _list _filt _top
	local -a _sync_filtered=()
	_list="$(get_state "$STATE_LIST" "")"
	_filt="$(get_state "$STATE_FILTER" "")"
	mapfile -t _sync_filtered < <(lp_rank "$_list" "$_filt")
	if [ "${#_sync_filtered[@]}" -eq 0 ]; then
		_top=""
	else
		_top="${_sync_filtered[0]}"
	fi
	# Delegate the preview to _lp_preview_dispatch (the caller has ALREADY issued
	# _lp_status_redraw so the highlight moves before this runs). Empty filtered
	# list -> _top="" -> no preview fires (leave the prior pane as-is).
	_lp_preview_dispatch "$_top"
}

# _lp_scroll_into_view IDX RANKED — PRD §19 §3.32: keep @livepicker-scroll tracking the
# highlight so the viewport follows the keypress. Pure STATE math via layout.sh::lp_viewport
# (the SAME function the renderer slices with -> they can never disagree, §P7). Reads
# STATE_CLIENT_WIDTH (T) + STATE_SCROLL, runs lp_viewport's scroll-into-view rule (snap scroll
# to IDX if IDX<scroll; advance scroll while the highlight tab overflows T; clamp 0 when it
# fits / when width is unknown), and writes the result to STATE_SCROLL.
# T = client_width is a conservative approximation (the renderer's tab-region T is narrower:
# − query block − indicators); it is SAFE because the renderer re-runs lp_viewport every redraw
# (steps a+b) and self-corrects — the highlight is ALWAYS visible regardless of STATE_SCROLL.
# So this write is STATE hygiene (keep scroll tracking), not a render-correctness requirement.
# Scroll is a synchronous STATE write (part of the §18 status update) — NO preview work; the
# nav preview re-sync stays deferred via the caller's _lp_preview_dispatch call.
_lp_scroll_into_view() {
	local idx="${1:-0}" ranked="${2:-}"
	local width scroll
	width="$(get_state "$STATE_CLIENT_WIDTH" "0")"
	scroll="$(get_state "$STATE_SCROLL" "0")"
	lp_viewport "$ranked" "$width" "$scroll" "$idx"   # SEP_WIDTH defaults to 1 (plain-mode space)
	set_state "$STATE_SCROLL" "$LPV_SCROLL"
}

# _lp_invalidate_pending_preview — bump STATE_PREVIEW_SEQ FIRST (defer=on only) so any in-flight
# background preview fire (run-shell -b from a prior keystroke/nav) is marked stale BEFORE the nav
# path performs any tmux round-trips. Each tmux round-trip pumps the server event loop, which
# ADVANCES pending -b jobs; bumping the seq up front means a stale fire re-checks the seq in
# preview.sh (GUARD 2, before the unlink) and NO-OPS, regardless of how many round-trips the
# scroll-into-view / reads add afterward. defer=off runs preview.sh INLINE (no -b job, no race)
# -> the gate makes this a no-op. _lp_fire_preview (called later via _lp_preview_dispatch) bumps
# AGAIN and captures the final seq for THIS nav's fire — the early bump is a pure invalidation
# signal (one "spent" seq number; the seq guards compare equality, so gaps are harmless).
# RACE-FIX for the scroll-into-view wiring (P1.M3.T2.S1 attempt 2). See research/race_fix_findings.md.
_lp_invalidate_pending_preview() {
	[ "$(opt_preview_defer)" = "on" ] || return 0
	local s
	s="$(get_state "$STATE_PREVIEW_SEQ" "0")"
	set_state "$STATE_PREVIEW_SEQ" "$(( s + 1 ))"
}

# _lp_fire_preview TARGET — schedule a background, supersedeable preview of TARGET
# (PRD §18; external_tmux_behavior.md Q6). Bumps the monotonic STATE_PREVIEW_SEQ,
# records STATE_PREVIEW_TARGET, then launches preview.sh detached via run-shell -b
# (non-blocking — Q5). The job re-checks the seq in preview_main (P1.M2.T2.S1) and
# NO-OPS if a newer keystroke/nav won, so a late/superseded job never clobbers the
# current link (and clear_all_state unsets the seq on teardown -> a post-teardown
# job reads "0" != its seq -> no-op). No-op on an empty TARGET (no top match).
_lp_fire_preview() {
	local target="${1:-}" seq
	[ -z "$target" ] && return 0
	seq="$(get_state "$STATE_PREVIEW_SEQ" "0")"
	seq=$(( seq + 1 ))
	set_state "$STATE_PREVIEW_SEQ" "$seq"
	set_state "$STATE_PREVIEW_TARGET" "$target"
	# Absolute path (the server's cwd is NOT the plugin dir); bash shebang honored
	# under run-shell (Q5). Single-quote the target so session names with spaces
	# survive (matches the key-binding run-shell form, livepicker.sh:326).
	tmux run-shell -b "$CURRENT_DIR/preview.sh '$target' '$seq'"
}

# _lp_status_redraw — force the status line to redraw NOW. The #() renderer is
# re-evaluated ASYNCHRONOUSLY by the server (verified: refresh-client -S returns in
# ~4ms regardless of renderer cost — it does NOT block on it). Calling this the
# instant the highlight/query STATE changes lets the user see the tab selection move
# WHILE the scroll/preview tail work still runs (the renderer self-corrects the
# viewport via lp_viewport to keep the highlight visible regardless of scroll —
# §19/§P7). This is the snappiness lever: refresh EARLY, do the slow work behind it.
_lp_status_redraw() {
	tmux refresh-client -S 2>/dev/null || true
}

# _lp_preview_dispatch TARGET — sync the live preview to TARGET, honoring
# @livepicker-preview-defer. The status redraw is the CALLER's responsibility: each
# path issues _lp_status_redraw right after the highlight/query write (so the tab
# selection moves first), THEN calls this for the preview. Decoupled by design
# (PRD §18): the slow link-window/render runs detached and never blocks the UI.
#   defer=on (default): _lp_fire_preview launches a background, supersedeable
#     run-shell -b job (non-blocking — verified ~4ms return; the render takes its
#     time detached). NO redraw here (the caller's early _lp_status_redraw covers it).
#   defer=off (legacy/diagnostic): preview.sh runs INLINE; the trailing refresh
#     preserves the pre-§18 synchronous order byte-for-byte (preview-then-redraw).
# Empty TARGET -> no preview (leave the prior pane as-is).
_lp_preview_dispatch() {
	local target="${1:-}"
	if [ "$(opt_preview_defer)" = "on" ]; then
		_lp_fire_preview "$target"
	else
		[ -n "$target" ] && { "$CURRENT_DIR/preview.sh" "$target" 2>/dev/null || true; }
		tmux refresh-client -S 2>/dev/null || true
	fi
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
			# — the renderer clamps + handles FLEN=0 itself (FINDING 4). The preview
			# now ALSO follows the top match (PRD §3 story 3 / README "the preview
			# follows live") via _lp_sync_preview_to_top_match, mirroring nav.
			set_state "$STATE_INDEX" "0"
			# Reset the viewport scroll to the top (PRD §19 §3.32). A status-only STATE write
			# (part of the synchronous status update; NO preview work — §18).
			set_state "$STATE_SCROLL" "0"
			# Sync the live preview to the new top filtered match (PRD §3 / README;
			# mirror next/prev). Always index 0 — these branches just reset it.
			# REDRAW NOW (the instant the query/highlight changes) so the tab selection
			# moves before the (deferred | sync) preview work below.
			_lp_status_redraw
			_lp_sync_preview_to_top_match
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
			# CONTRACT (work-item §3): backspace trims the query and re-syncs the
			# preview to the (possibly new) top filtered match (PRD §3 story 3 +
			# README "the preview follows live"; reconciles PRD §5 in favour of §3).
			# Shortening the filter may re-admit a different top match ->
			# _lp_sync_preview_to_top_match re-links it so the preview pane stays
			# aligned with the highlight.
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
			# Reset the viewport scroll to the top (PRD §19 §3.32). A status-only STATE write
			# (part of the synchronous status update; NO preview work — §18).
			set_state "$STATE_SCROLL" "0"
			# Sync the live preview to the new top filtered match (PRD §3 / README;
			# mirror next/prev). Always index 0 — these branches just reset it.
			# REDRAW NOW (mirror type) so the highlight moves before the preview work.
			_lp_status_redraw
			_lp_sync_preview_to_top_match
			return 0
			;;
		next-session)
			# RACE FIX: invalidate any pending background preview fire FIRST, before the nav path's
			# tmux round-trips (reads + scroll-into-view) pump the server loop and advance a stale
			# -b fire toward its GUARD 2 mutation. _lp_fire_preview below bumps again for THIS nav's
			# own fire. (defer=off -> no-op: inline preview.)
			_lp_invalidate_pending_preview
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
			mapfile -t filtered < <(lp_rank "$cur_list" "$cur_filter")
			L="${#filtered[@]}"
			# Nothing matches -> no-op (never divide by zero; FINDING 5).
			[ "$L" -eq 0 ] && return 0
			# Sanitize the stored index to a non-negative int (it is a STRING
			# option; FINDING 5) before the modulo.
			cur_index="$(get_state "$STATE_INDEX" "0")"
			[[ "$cur_index" =~ ^[0-9]+$ ]] || cur_index=0
			# Wrap modulo L (PRD §6 "wrapping"). No +L needed for next.
			new_idx=$(( (cur_index + 1) % L ))
			# Set the NEW index FIRST, resolve the target at it, THEN redraw + preview
			# (so the highlight + the live preview agree — FINDING 5).
			set_state "$STATE_INDEX" "$new_idx"
			target="${filtered[$new_idx]}"
			# REDRAW NOW (the instant the highlight changes): the renderer is async and
			# self-corrects the viewport to keep the highlight visible, so the slow
			# scroll/preview work below runs BEHIND the redraw, not before it.
			_lp_status_redraw
			# PRD §19 §3.32: scroll the highlight into view (synchronous STATE write;
			# the renderer already self-corrected for THIS redraw — this keeps
			# @livepicker-scroll tracking for SUBSEQUENT redraws, §P7).
			_lp_scroll_into_view "$new_idx" "$(printf '%s\n' "${filtered[@]}")"
			# Delegate the live link/select to preview.sh (P1.M3; FINDING 9). It
			# fires session-window-changed (suppressed by activate T4.S2) but
			# NEVER client-session-changed (Invariant A). _lp_preview_dispatch runs
			# the (deferred | sync) preview; guard a mid-nav failure (session gone).
			_lp_preview_dispatch "$target"
			return 0
			;;
		prev-session)
			# RACE FIX: invalidate any pending background preview fire FIRST (mirror next-session).
			# _lp_fire_preview below bumps again for THIS nav's own fire.
			_lp_invalidate_pending_preview
			# --- P1.M6.T2.S1: move the highlight UP within the FILTERED list
			#     (wrapping, reverse). Mirror of next-session.
			cur_list="$(get_state "$STATE_LIST" "")"
			cur_filter="$(get_state "$STATE_FILTER" "")"
			mapfile -t filtered < <(lp_rank "$cur_list" "$cur_filter")
			L="${#filtered[@]}"
			[ "$L" -eq 0 ] && return 0
			cur_index="$(get_state "$STATE_INDEX" "0")"
			[[ "$cur_index" =~ ^[0-9]+$ ]] || cur_index=0
			# Wrap modulo L (PRD §6). The +L dodges bash's negative-modulo quirk
			# (bash `%` can return negatives for negative operands — FINDING 5).
			new_idx=$(( (cur_index - 1 + L) % L ))
			set_state "$STATE_INDEX" "$new_idx"
			target="${filtered[$new_idx]}"
			# REDRAW NOW (mirror next-session): the renderer is async and self-corrects
			# the viewport, so the highlight moves before the scroll/preview tail.
			_lp_status_redraw
			# PRD §19 §3.32: scroll the highlight into view (synchronous STATE write;
			# keeps @livepicker-scroll tracking for SUBSEQUENT redraws, §P7).
			_lp_scroll_into_view "$new_idx" "$(printf '%s\n' "${filtered[@]}")"
			_lp_preview_dispatch "$target"
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
			mapfile -t filtered < <(lp_rank "$cur_list" "$cur_filter")
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
				# @livepicker-zoxide-mode on (mirrors sessionx's @sessionx-zoxide-mode):
				# resolve the query through zoxide and start the session there
				# (-c "$z_target"), naming the window after the dir (-n, like sessionx).
				# zoxide only resolves dirs it has indexed with enough frecency; an
				# empty result (not indexed / below threshold / zoxide absent) falls
				# back to a PLAIN create (no -c) rather than -c "" — more robust than
				# sessionx, and still satisfies the create gate below.
				local z_target="" created="" new_session_args=(-d -P -F '#{session_name}' -s "$query")
				if [ "$(opt_zoxide)" = "on" ]; then
					z_target="$(zoxide query "$query" 2>/dev/null)"
					[ -n "$z_target" ] && new_session_args+=(-c "$z_target" -n "$z_target")
				fi
				# Create gate (Issue 3 fix). new-session SILENTLY SANITIZES names
				# (every '.' and ':' -> '_') and returns rc=0 with a DIFFERENT name.
				# The OLD gate (has-session -t "=$query") checked the ORIGINAL
				# unsanitized query, so it always failed after a sanitized success ->
				# the just-created session was orphaned and the client stranded.
				# FIX: -P -F '#{session_name}' captures the ACTUAL name tmux created;
				# gate on a non-empty capture and switch to THAT name. Empty query or
				# a collision (sanitized name exists) -> new-session rc=1, stdout empty
				# -> created="" -> cancel (NO orphan). See research/issue3_fix_findings.md.
				created="$(tmux new-session "${new_session_args[@]}" 2>/dev/null)"
				if [ -n "$created" ]; then
					_confirm_land_on_session "$created"
				else
					# Genuine failure (empty/collision) -> cancel (PRD §6 Confirm).
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
				# exactly: set filter, set index=0, sync the preview, refresh — but
				# write "" (the WHOLE query) instead of ${cur_filter%?} (one char).
				# The preview re-syncs to the now-unfiltered top match (PRD §3 /
				# README; mirrors backspace).
				# FINDING 1: set_state "" is a SET-EMPTY (tmux set-option -g @x ""),
				# NOT an unset; get_state reads it back as "" (the default). Do NOT
				# use tmux_unset_opt / -gu (that is restore's teardown concern).
				set_state "$STATE_FILTER" ""
				# Reset the highlight to the top filtered match (PRD §6). Always
				# safe — the renderer clamps + handles FLEN=0 (empty filter matches
				# ALL names; renderer FINDING 4 / rank.sh).
				set_state "$STATE_INDEX" "0"
				# Reset the viewport scroll to the top (PRD §19 §3.32). A status-only STATE write
				# (part of the synchronous status update; NO preview work — §18).
				set_state "$STATE_SCROLL" "0"
				# Sync the live preview to the new top filtered match (PRD §3 / README;
				# mirror next/prev). Always index 0 — these branches just reset it.
				# REDRAW NOW (mirror type) so the highlight moves before the preview work.
				_lp_status_redraw
				_lp_sync_preview_to_top_match
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
		# --- P2.M1.T2.S1: rename the highlighted session/window via tmux's
		#     prompt (PRD §21.42). Thin delegate — session-mgmt.sh hosts the
		#     resolution + command-prompt (rename) + apply/detect/rewrite
		#     (do-rename). While command-prompt is open the livepicker table is
		#     suspended (the prompt captures input); tmux restores it on
		#     submit/escape -> no extra binding work. The picker stays OPEN
		#     (no restore). MUST NOT reference $2 (the C-r binding passes no char;
		#     mirror confirm FINDING 9).
		rename)
			"$CURRENT_DIR/session-mgmt.sh" rename
			return 0
			;;
		# --- P2.M1.T2.S2: delete the highlighted session/window (PRD §21 §3.43).
		#     Thin delegate — session-mgmt.sh hosts the guards + optional
		#     confirm-before + do-delete (unlink-first + kill + rewrite + clamp
		#     + re-rank + re-sync). MUST NOT reference $2 (the M-BSpace binding
		#     passes no char; mirror rename). The picker STAYS OPEN. ---
		delete)
			"$CURRENT_DIR/session-mgmt.sh" delete
			return 0
			;;
		refresh-width)
			# PRD §10 step 5 / §3.35: the client-resized hook fires this on resize. Re-cache the
			# invoking client's width (client-aware via lp_client_format) and force a status redraw
			# so the §19 renderer re-windows the viewport for the new width. NO preview work, NO
			# filter/index change (the hook is global; single-client plugin — PRD §2).
			set_state "$STATE_CLIENT_WIDTH" "$(lp_client_format '#{client_width}')"
			tmux refresh-client -S 2>/dev/null || true
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
