#!/usr/bin/env bash
# shellcheck disable=SC1091,SC2153
#   SC1091: sources sibling libs (options/utils/state) via the resolved $CURRENT_DIR;
#           follow with `shellcheck -x` if you want them traced.
#   SC2153: ORIG_SESSION/ORIG_WINDOW/STATE_LINKED_ID are readonly CONTRACT constants
#           defined in state.sh (sourced above); shellcheck sees no assignment here.
# scripts/preview.sh — tmux-livepicker live preview core (link-window).
#
# argv[1] = candidate session name S. Links S's active window into the CURRENT
# (driver) session and selects it, so all its panes render live below the status
# bar — WITHOUT switching the client's session (Invariant A: select-window does
# NOT fire client-session-changed). Tracks the linked window id in
# @livepicker-linked-id for unlinking on the next navigation and on restore.
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
	# Captures the candidate's active pane with escapes. CRITICAL: the target is
	# "=$target:." where $target is the session name (session mode) OR the parsed
	# "session:index" (window mode). The bare "=$1:." form is MALFORMED in window
	# mode: $1="multi:1" -> "=multi:1:." -> "can't find window 1:". So in window
	# mode parse the token and build "=$w_sess:$w_idx." (the active pane of the
	# specific window). Returns capture's rc: 0 = captured, non-zero = gone.
	local captured target="$1"
	if [ "$(opt_type)" = "window" ] && [ "${1%%:*}" != "$1" ]; then
		local w_sess="${1%%:*}" w_idx="${1#*:}"
		target="$w_sess:$w_idx"
	fi
	# shellcheck disable=SC2034  # best-effort hint; text intentionally unused.
	captured="$(tmux capture-pane -ep -t "=$target:." 2>/dev/null)" && return 0 || return 1
}

# argv[1] = candidate session name S.
preview_main() {
	local S="${1:-}" expected_seq="${2:-}"
	local current_session orig_window linked_id src_id w_sess w_idx cur_seq

	# The session we preview INSIDE (the driver). Equal to the live client session
	# during browsing (Invariant A); client-independent (FINDING 9).
	current_session="$(get_state "$ORIG_SESSION" "")"
	orig_window="$(get_state "$ORIG_WINDOW" "")"
	linked_id="$(get_state "$STATE_LINKED_ID" "")"

	# --- deferred-preview supersede guard (PRD §18 / external_tmux_behavior.md Q6) ---
	# When called WITH an expected_seq ($2 — the deferred background path from
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
		# Snapshot: capture-pane of S's active pane; NEVER link. Self-session
		# needs no special handling (capturing your own pane is harmless).
		preview_fallback "$S"
		return $?
	fi
	# mode == live (default): fall through to the link flow below.

	# Self-session guard (PRD §7; FINDING 6). Do NOT link — would create an
	# in-session duplicate; instead show the user their own session. S2
	# refinement (contract §3): first drop any prior preview linked into the
	# driver (source keeps it — S1 FINDING 1; no -k, || true — S1 FINDING 2),
	# clear LINKED_ID (tmux_unset_opt = -gu — FINDING E; matches state.sh
	# teardown), THEN select the original window.
	if [ -n "$current_session" ] && [ "$S" = "$current_session" ]; then
		if [ -n "$linked_id" ]; then
			tmux unlink-window -t "$current_session:$linked_id" 2>/dev/null || true
			tmux_unset_opt "$STATE_LINKED_ID"
		fi
		[ -n "$orig_window" ] && tmux select-window -t "$orig_window" 2>/dev/null || true
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
	else
		src_id="$(tmux list-windows -t "=$S" -F '#{window_id}' -f '#{window_active}' 2>/dev/null)"
	fi
	if [ -z "$src_id" ]; then
		# Session gone / no windows / exact-match miss -> fallback.
		preview_fallback "$S"
		return $?
	fi

	# DUPLICATE GUARD (FINDING 4/5). Re-previewing the SAME session (linked_id ==
	# src_id, e.g. single-match wrap): the window is already linked + selected.
	# Skip unlink AND link (re-linking would silently duplicate). Just ensure shown.
	if [ -n "$linked_id" ] && [ "$linked_id" = "$src_id" ]; then
		tmux select-window -t "$src_id" 2>/dev/null || true
		return 0
	fi

	# Optional second supersede re-check (PRD §18 / Q6 read->mutate race). Placed
	# here — BEFORE the first mutation (the unlink) — so a job that went stale
	# between the top-of-function guard and now is a TRUE no-op (it skips
	# unlink+link+select+set_state entirely, so no link is left untracked). Do NOT
	# move this to before the final select-window: that fires AFTER link-window but
	# BEFORE set_state LINKED_ID -> a stale job would link its window then bail,
	# leaving an UNTRACKED link (a leak). (research FINDING 5.)
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

	# Link S's active window into the current session (bare index -> free slot).
	# GUARDED: on ANY failure, fall back (S1 stub -> exit non-zero; S2 -> capture-pane).
	if ! tmux link-window -a -s "$src_id" -t "$current_session:" 2>/dev/null; then
		preview_fallback "$S"
		return $?
	fi

	# Show it — all panes, live. select-window does NOT fire client-session-changed
	# (Invariant A). It DOES fire session-window-changed (suppressed globally by
	# P1.M4.T4.S2 — not this task's concern).
	tmux select-window -t "$src_id" 2>/dev/null || true

	# Track the linked id (handle for the next unlink + for restore P1.M5).
	set_state "$STATE_LINKED_ID" "$src_id"
	return 0
}

preview_main "$@" || exit 1
exit 0
