#!/usr/bin/env bash
# shellcheck disable=SC1091,SC2153
#   SC1091: sources sibling libs (options/utils/state) via the resolved $CURRENT_DIR;
#           follow with `shellcheck -x` if you want them traced.
#   SC2153: ORIG_SESSION/ORIG_WINDOW/STATE_LINKED_ID are readonly CONTRACT constants
#           defined in state.sh (sourced above); shellcheck sees no assignment here.
# scripts/preview.sh — tmux-livepicker live preview core (link-window).
#
# argv[1] = candidate session name S (or "session:index" token in window mode).
# argv[2] = chosen window-id (session-mode flip target; "" for session-nav/first preview).
# argv[3] = deferred-preview supersede seq ("" for inline calls -> seq guards skipped).
# Links S's active window — or the chosen window (argv[2]) when supplied — into the
# CURRENT (driver) session and selects it, so all its panes render live below the
# status bar — WITHOUT switching the client's session (Invariant A: select-window
# does NOT fire client-session-changed). Tracks the linked window id in
# @livepicker-linked-id (non-self) and the logical shown window in
# @livepicker-preview-win-id, for unlinking on the next navigation and on restore.
#
# SCOPE (P1.M3.T1.S1): the LIVE link/unlink/select core ONLY. The self-session
# case here is the minimal guard (select orig + return). S2 (P1.M3.T1.S2) EXTENDS
# this file: it replaces preview_fallback() with capture-pane, inserts the
# @livepicker-preview-mode gate (live|snapshot|off), and completes self-session
# handling. S2 DEPENDS ON this file.
#
# LOAD-BEARING RULES (research/preview_link_unlink_findings.md):
#  - link-window does NOT fail when the window is already linked in the target
#    session — it silently creates a DUPLICATE (FINDING 4). So ALWAYS unlink the
#    previous preview before linking a DIFFERENT one, AND if LINKED_ID == src_id
#    (single-match wrap) skip BOTH unlink and link — just select (FINDING 5).
#  - unlink-window WITHOUT -k removes ONE link; the source session KEEPS its
#    window (FINDING 1). It FAILS (rc=1) only when singly-linked -> ignore
#    non-zero (`|| true`). NEVER pass -k (would destroy the shared window in ALL
#    sessions — FINDING 11).
#  - Address windows by @id, NEVER index (renumber-windows is on — FINDING 10).
#  - Read CURRENT_SESSION from @livepicker-orig-session, NOT display-message:
#    during browsing the client never switches (Invariant A), so ORIG_SESSION is
#    provably == the live client session AND is client-independent (works on the
#    detached test socket). display-message is non-deterministic without a client
#    (FINDING 9).
#  - NO `set -e` — unlink/list-windows legitimately return non-zero; guard each.
#    `set -u` inherited; every var defaulted at read.
#
# DEPENDS ON (source order load-bearing — state.sh needs utils.sh first):
#   options.sh (opt_*), utils.sh (tmux_*), state.sh (get_state/set_state/STATE_*/ORIG_*).

CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=options.sh
source "$CURRENT_DIR/options.sh"
# shellcheck source=utils.sh
source "$CURRENT_DIR/utils.sh"
# shellcheck source=state.sh
source "$CURRENT_DIR/state.sh"

# S2 (P1.M3.T1.S2) REPLACED THIS STUB with the capture-pane snapshot fallback:
#   tmux capture-pane -ep -t "=$1:." captured to a local var (discarded —
#   FINDING H: under run-shell bare escape sequences could corrupt the status
#   area); returns capture's rc (0 = captured, non-zero = gone — S1 contract §4).
# S1's stub returned 1 so preview.sh exited non-zero on link failure. $1 = S.
preview_fallback() {
	# capture-pane snapshot fallback (PRD §7 Fallbacks). Single-pane, NOT live.
	# Invoked (a) when @livepicker-preview-mode == snapshot (always), and
	# (b) when a live link-window fails (degraded but non-blocking path).
	# Captures the candidate's active pane with escapes. The target is a
	# "=<sess>:<win>." pane spec (the trailing '.' = active pane): SESSION mode
	# uses "=$S:." (= active window's active pane); WINDOW mode ($S is a
	# "session:index" token) uses "=$w_sess:$w_idx." (the active pane of THAT
	# window). Do NOT build "=$w_sess:$w_idx:." — the extra ':' makes tmux parse
	# the index as "1:" and fail with "can't find window 1:". Returns capture's
	# rc: 0 = captured, non-zero = gone.
	local captured target chosen="${2:-}"
	if [ -n "$chosen" ]; then
		# P2.M1.T2: session mode + flipped window -> capture THAT window's active pane.
		# "=session:@id." is a valid target (rc=0 verified — research FINDING 3).
		target="=$1:$chosen."
	elif [ "$(opt_type)" = "window" ] && [ "${1%%:*}" != "$1" ]; then
		# WINDOW mode: candidate token is "session:window_index" (livepicker.sh).
		# Build "session:index." — the '.' attaches directly to the index (NO ':').
		target="=${1%%:*}:${1#*:}."
	else
		# SESSION mode: "=session:." = active window's active pane.
		target="=$1:."
	fi
	# shellcheck disable=SC2034  # best-effort hint; text intentionally unused.
	captured="$(tmux capture-pane -ep -t "$target" 2>/dev/null)" && return 0 || return 1
}

# P3.M2.T2.S1 (PRD §23): restore a previously-pinned candidate's window-size. Called from
# preview.sh's TWO unlink paths (self-session + replace) BEFORE the unlink/link, so the
# candidate session returns to its prior window-size (no trace of our manual pin). Reads
# STATE_CAND_PIN_SESSION/WS; if set, replays the prior window-size (or UNSETS the session
# override when the prior value was empty/inherited) on the BARE session name, then clears
# both keys. No-op when nothing was pinned. Idempotent (clears state after restoring).
# restore.sh STEP 1 has its OWN inline copy (separate process under run-shell — cannot source
# this helper). The pin was detached-only (preview.sh gate), so restoring window-size is
# safe (no client to fight). NO '=' prefix on set-option -t (gotcha #1; mirror the §22 driver clip).
_preview_restore_cand_pin() {
	local pin_sess pin_ws
	pin_sess="$(get_state "$STATE_CAND_PIN_SESSION" "")"
	[ -z "$pin_sess" ] && return 0
	pin_ws="$(get_state "$STATE_CAND_PIN_WS" "")"
	if [ -n "$pin_ws" ]; then
		tmux set-option -t "$pin_sess" window-size "$pin_ws" 2>/dev/null || true
	else
		tmux set-option -u -t "$pin_sess" window-size 2>/dev/null || true
	fi
	tmux_unset_opt "$STATE_CAND_PIN_SESSION"
	tmux_unset_opt "$STATE_CAND_PIN_WS"
}

# argv[1] = candidate session name S.
preview_main() {
	local S="${1:-}" chosen_win="${2:-}" expected_seq="${3:-}"
	local current_session orig_window linked_id src_id w_sess w_idx cur_seq check_session cand_sess cand_ws cand_h

	# The session we preview INSIDE (the driver). Equal to the live client session
	# during browsing (Invariant A); client-independent (FINDING 9).
	current_session="$(get_state "$ORIG_SESSION" "")"
	orig_window="$(get_state "$ORIG_WINDOW" "")"
	linked_id="$(get_state "$STATE_LINKED_ID" "")"

	# --- deferred-preview supersede guard (PRD §18 / external_tmux_behavior.md Q6) ---
	# When called WITH an expected_seq ($3 — the deferred background path from
	# P1.M2.T3's fire helper), bail EARLY if the live seq has advanced past it: a
	# newer keystroke fired a newer preview, so THIS job is stale and must NOT touch
	# any window. (A run-shell -b job is non-cancellable — Q5 — so it no-ops here.)
	# When called with ONE arg ($2 empty — the activation first-preview and the
	# preview-defer=off synchronous path), the guard is SKIPPED: behavior is exactly
	# as before. clear_all_state unsets STATE_PREVIEW_SEQ on exit (P1.M2.T1.S1 lists
	# it in _STATE_RUNTIME_KEYS), so a late post-teardown job reads the "0" default
	# != its captured seq -> no-op too (the Q6 teardown-safety guarantee).
	if [ -n "$expected_seq" ]; then
		cur_seq="$(get_state "$STATE_PREVIEW_SEQ" "0")"
		[ "$cur_seq" != "$expected_seq" ] && return 0
	fi

	# --- @livepicker-preview-mode gate (PRD §7 Fallbacks / §11; default live) ---
	local mode
	mode="$(opt_preview_mode)"   # live | snapshot | off
	if [ "$mode" = "off" ]; then
		# Show nothing. No link, no capture, no state change. (mode is constant
		# for the picker lifetime, so no prior link exists to clean here.)
		return 0
	fi
	if [ "$mode" = "snapshot" ]; then
		# Snapshot: capture-pane of S's (or the FLIPPED window's) active pane; NEVER
		# link. chosen_win (session-mode flip) -> capture THAT window's active pane;
		# else S's active window. Self-session needs no special handling (capturing
		# your own pane is harmless). (PRD §7 Fallbacks; P2.M1.T2 chosen-window.)
		preview_fallback "$S" "$chosen_win"
		return $?
	fi
	# mode == live (default): fall through to the link flow below.

	# Self-session guard (PRD §7; FINDING 6). Do NOT link — would create an
	# in-session duplicate; instead select the user's own window. Bugfix ISSUE 2
	# (window-mode extension): in window mode $S is a "session:index" token
	# (e.g. "driver:1") which never equals the bare session name, so the OLD bare
	# comparison let driver-owned windows fall through to link-window, silently
	# creating a DUPLICATE (link-window rc=0 on already-linked windows). Fix:
	# compare ${S%%:*} (the token's session) — the SAME idiom used at lines 62/144.
	# Session mode ($S has no colon) is the identity -> zero regression. When the
	# guard fires in window mode, select the SPECIFIC highlighted window ($S token
	# works directly with select-window); in session mode, select ORIG_WINDOW as
	# before. (research/self_session_window_mode_findings.md FINDING 2/3/5.)
	check_session="$S"
	if [ "$(opt_type)" = "window" ] && [ "${S%%:*}" != "$S" ]; then
		check_session="${S%%:*}"
	fi
	if [ -n "$current_session" ] && [ "$check_session" = "$current_session" ]; then
		# Drop any prior CROSS-session preview linked into the driver (source keeps
		# it — S1 FINDING 1; no -k, || true — S1 FINDING 2), then clear LINKED_ID.
		if [ -n "$linked_id" ]; then
			tmux unlink-window -t "$current_session:$linked_id" 2>/dev/null || true
			# P3.M2.T2.S1 (PRD §23): restore a pinned candidate's window-size AFTER unlinking
			# its window (see replace-path comment: unlink-then-restore — the candidate window
			# is shared while linked; unsetting window-size first lets the driver client reflow
			# it). No-op if nothing was pinned (detached+clip only).
			_preview_restore_cand_pin
			tmux_unset_opt "$STATE_LINKED_ID"
		fi
		# Select the target window: window mode -> the specific "session:index" ($S);
		# session mode -> the FLIPPED window ($chosen_win, P2.M1.T2) if supplied, else
		# ORIG_WINDOW. NO link in any case. Record STATE_PREVIEW_WIN_ID (the logical
		# shown window — overlaps STATE_LINKED_ID for non-self, DIVERGES here: linked-id
		# stays empty for self; preview-win-id = the driver window now shown). Flipping
		# the driver's own windows while browsing moves its active window; cancel's hard
		# reset to ORIG_WINDOW (restore STEP 2) undoes it. (PRD §7 self-session; §3.6.)
		if [ "$(opt_type)" = "window" ]; then
			tmux select-window -t "$S" 2>/dev/null || true
		elif [ -n "$chosen_win" ]; then
			tmux select-window -t "$chosen_win" 2>/dev/null || true
			set_state "$STATE_PREVIEW_WIN_ID" "$chosen_win"
		else
			[ -n "$orig_window" ] && tmux select-window -t "$orig_window" 2>/dev/null || true
			[ -n "$orig_window" ] && set_state "$STATE_PREVIEW_WIN_ID" "$orig_window"
		fi
		return 0
	fi

	# Resolve the candidate window id. SESSION mode: the session's active window
	# (exact-match =S; one line @N; FINDING 7) — UNCHANGED. WINDOW mode: $S is a
	# 'session:window_index' token (livepicker.sh:103); resolve the SPECIFIC window
	# at that index, NOT the session's active window (bugfix ISSUE 4). The
	# #{window_active} filter ignores the index, and -f '#{window_index} == N'
	# does NOT filter (expands to non-empty text -> always truthy), so list all
	# windows and match the index field, returning the @id (address by @id — the
	# plugin's invariant; renumber-windows is on but the list is snapshotted).
	if [ "$(opt_type)" = "window" ] && [ "${S%%:*}" != "$S" ]; then
		w_sess="${S%%:*}"
		w_idx="${S#*:}"
		src_id="$(tmux list-windows -t "=$w_sess" -F '#{window_id}:#{window_index}' 2>/dev/null | awk -F: -v idx="$w_idx" '$2==idx {print $1; exit}')"
	elif [ -n "$chosen_win" ]; then
		# P2.M1.T2: session mode + a FLIPPED window — use the supplied window-id
		# directly (skip the active-window lookup). chosen_win is a server-global @id
		# (select-window -t "@id" verified — research FINDING 2). Only session mode
		# supplies chosen_win; window mode is handled by the branch above.
		src_id="$chosen_win"
	else
		src_id="$(tmux list-windows -t "=$S" -F '#{window_id}' -f '#{window_active}' 2>/dev/null)"
	fi
	if [ -z "$src_id" ]; then
		# Session gone / no windows / exact-match miss -> fallback.
		preview_fallback "$S"
		return $?
	fi

	# IDEMPOTENT PRE-LINK CHECK (bugfix Issue 4 / issue4_5_6_findings.md §Issue 4 part B).
	# Probe whether src_id is ALREADY linked into the driver session — an AUTHORITATIVE
	# check that does not rely on @livepicker-linked-id (which a racing deferred job may
	# not have committed yet, or which clear_all_state may have unset). If src_id is
	# already here (a re-preview of the same window, OR a losing interleave that already
	# linked it), skip unlink+link — re-linking would silently create a DUPLICATE
	# (link-window rc=0 on already-linked windows — FINDING 4) — and just select +
	# record, exactly like the duplicate-guard below. No seq guard here: this fires only
	# when src_id is already linked, so select+set_state are non-destructive and the
	# duplicating link-window is skipped (research FINDING 6). GUARD 1/2/3 own supersede.
	if tmux list-windows -t "=$current_session" -F '#{window_id}' 2>/dev/null \
		| grep -Fxq "$src_id"; then
		tmux select-window -t "$current_session:$src_id" 2>/dev/null || true
		set_state "$STATE_LINKED_ID" "$src_id"
		set_state "$STATE_PREVIEW_WIN_ID" "$src_id"   # P2.M1.T2: logical shown window (== LINKED_ID non-self)
		return 0
	fi

	# DUPLICATE GUARD (FINDING 4/5). Re-previewing the SAME session (linked_id ==
	# src_id, e.g. single-match wrap): the window is already linked + selected.
	# Skip unlink AND link (re-linking would silently duplicate). Just ensure shown.
	if [ -n "$linked_id" ] && [ "$linked_id" = "$src_id" ]; then
		tmux select-window -t "$current_session:$src_id" 2>/dev/null || true
		return 0
	fi

	# Optional second supersede re-check (PRD §18 / Q6 read->mutate race). Placed
	# here — BEFORE the first mutation (the unlink) — so a job that went stale
	# between the top-of-function guard and now is a TRUE no-op (it skips
	# unlink+link+select+set_state entirely, so no link is left untracked). Do NOT
	# move this to before the final select-window: that fires AFTER link-window but
	# BEFORE set_state LINKED_ID -> a stale job would link its window then bail,
	# leaving an UNTRACKED link (a leak). (research FINDING 5.) NOTE: this warning is
	# about THIS guard's OWN placement (stay before the unlink). GUARD 3 below is an
	# ADDITIVE late commit-clobber check (Issue 4) placed intentionally before
	# set_state; it does NOT move or replace this guard.
	if [ -n "$expected_seq" ]; then
		[ "$(get_state "$STATE_PREVIEW_SEQ" "0")" != "$expected_seq" ] && return 0
	fi
	# Re-read LINKED_ID here (not just the snapshot at the top) so the unlink targets
	# the window ACTUALLY linked in the driver now (the freshest) — a newer -b job may
	# have linked a different window and updated @livepicker-linked-id since entry.
	linked_id="$(get_state "$STATE_LINKED_ID" "")"
	# Drop the previous preview from the current session (NO -k; source keeps it).
	# Ignore non-zero: singly-linked edge / already-gone (FINDING 2).
	if [ -n "$linked_id" ]; then
		tmux unlink-window -t "$current_session:$linked_id" 2>/dev/null || true
	fi
	# P3.M2.T2.S1 (PRD §23): restore the PREVIOUSLY-pinned candidate's window-size AFTER
	# unlinking its window from the driver. ORDER IS LOAD-BEARING: the candidate's window is
	# a SHARED object while linked into the driver (which has a client); unsetting its
	# session window-size (→ inherits global "latest") while still linked lets the driver
	# client drag the shared window down to its usable size (120x40 → 120x22). Unlink FIRST
	# so the candidate window is back to its own (detached) session only → no client forces
	# a reflow → restoring window-size is safe + trace-free. Idempotent (clears
	# STATE_CAND_PIN_*). No-op if nothing was pinned (detached+clip only).
	_preview_restore_cand_pin

	# P3.M2.T2.S1 (PRD §23 Prevention-regime bullet 2): PIN THE NEW CANDIDATE at link time,
	# CONDITIONAL. GATE (pane_immutability_verification.md §1/§7): (1) clip mode — the
	# driver must be manual too, else its latest client drags the shared window and the
	# candidate pin cannot hold (reflow retains its documented resize behavior); (2) NON-SELF
	# (we are past the self-session guard); (3) DETACHED — a client-bearing candidate is
	# HARMED by `window-size manual` (ARM E3: reverts its client view to the creation size);
	# the bare link does NOT disturb it (ARM E4), so skipping the pin there is safe.
	# Under the gate: freeze the candidate's session window-size to manual + pin its window
	# height, so the shared window keeps the candidate's geometry (ARM B2: byte-identical,
	# deterministic). Record the candidate session + prior window-size so
	# _preview_restore_cand_pin / restore.sh STEP 1 can undo it. BARE session name for
	# set-option/show-options (gotcha #1 — set-option REJECTS '='; list-clients takes it).
	# cand_h reads the detached candidate's creation size — CORRECT (we pin at its OWN
	# natural size). resize-window -y cand_h is the §23-SANCTIONED candidate pin (NOT a
	# violation — §23 prescribes it). Pin BEFORE link-window (ARM B2 verified recipe).
	cand_sess="$check_session"
	if [ "$(opt_preview_fit)" = "clip" ] && [ -n "$cand_sess" ] \
		&& [ -z "$(tmux list-clients -t "=$cand_sess" 2>/dev/null)" ]; then
		cand_ws="$(tmux show-options -t "$cand_sess" -v window-size 2>/dev/null || true)"
		cand_w="$(tmux display-message -p -t "$src_id" '#{window_width}' 2>/dev/null || true)"
		cand_h="$(tmux display-message -p -t "$src_id" '#{window_height}' 2>/dev/null || true)"
		tmux set-option -t "$cand_sess" window-size manual 2>/dev/null || true
		if [ -n "$cand_w" ] && [ -n "$cand_h" ]; then
			tmux resize-window -x "$cand_w" -y "$cand_h" -t "$src_id" 2>/dev/null || true
		elif [ -n "$cand_h" ]; then
			tmux resize-window -y "$cand_h" -t "$src_id" 2>/dev/null || true
		fi
		set_state "$STATE_CAND_PIN_SESSION" "$cand_sess"
		set_state "$STATE_CAND_PIN_WS" "$cand_ws"
	fi
	# (If link-window below FAILS -> preview_fallback/snapshot: the pin was manual + a
	#  size-no-op resize (cand_h == the candidate's own height); STATE_CAND_PIN_* is set, so
	#  the next nav / teardown restores it. Benign + trace-free. Do not over-engineer.)

	# Link S's active window into the current session. BARE link-window (no -a)
	# appends at the next free index at the END, so NO existing window's index
	# shifts and unlink restores the original list exactly. PRD §13 prescribes
	# `-a` (insert AFTER active) — DEVIATION: that inserts mid-list when the active
	# window isn't last, permanently shifting later windows (unlink leaves a gap;
	# renumber-windows does NOT fire on unlink). Verified on tmux 3.6b. See
	# plan/002_facc52335e68/bugfix/001_c7c6203f3e28/architecture/issue1_2_findings.md §Issue 1.
	# GUARDED: on ANY failure, fall back (S1 stub -> exit non-zero; S2 -> capture-pane).
	if ! tmux link-window -s "$src_id" -t "$current_session:" 2>/dev/null; then
		preview_fallback "$S"
		return $?
	fi

	# Show it — all panes, live. select-window does NOT fire client-session-changed
	# (Invariant A). It DOES fire session-window-changed (suppressed globally by
	# P1.M4.T4.S2 — not this task's concern).
	tmux select-window -t "$current_session:$src_id" 2>/dev/null || true

	# GUARD 3 — third supersede re-check before the LINKED_ID commit (bugfix Issue 4 /
	# issue4_5_6_findings.md §Issue 4 part A; PRD §18 contract #3). Closes the
	# commit-clobber TOCTOU window: between GUARD 2 (above) and here the function
	# performed unlink + link + select (three tmux round-trips). If a newer keystroke /
	# confirm / cancel advanced STATE_PREVIEW_SEQ (or clear_all_state unset it) during
	# those round-trips, THIS job is stale -> bail BEFORE set_state so it does NOT
	# overwrite the newer job's @livepicker-linked-id commit. Placed AFTER select-window
	# and BEFORE set_state (the contract is explicit: do NOT move earlier — a pre-link
	# guard would let a stale job link then bail, leaving an UNTRACKED link). Residual:
	# a stale job that already linked+selected a now-superseded window is unavoidable
	# without per-window locking (tmux has none); GUARD 3 prevents the WORSE outcome
	# (clobbering the newer commit -> mis-tracked -> wrong-window unlink on next
	# nav/restore), and the idempotent pre-link check above prevents a same-target
	# duplicate. GUARD 2 above remains the primary early no-op guard; THIS is additive.
	if [ -n "$expected_seq" ]; then
		[ "$(get_state "$STATE_PREVIEW_SEQ" "0")" != "$expected_seq" ] && return 0
	fi

	# Track the linked id (handle for the next unlink + for restore P1.M5) AND the
	# logical shown window (P2.M1.T2: STATE_PREVIEW_WIN_ID overlaps STATE_LINKED_ID
	# for non-self candidates; both = src_id here).
	set_state "$STATE_LINKED_ID" "$src_id"
	set_state "$STATE_PREVIEW_WIN_ID" "$src_id"
	return 0
}

preview_main "$@" || exit 1
exit 0
