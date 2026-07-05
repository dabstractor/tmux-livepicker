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

# S2 (P1.M3.T1.S2) REPLACES THIS STUB with the capture-pane snapshot fallback:
#   tmux capture-pane -ep -t "=$1" ... written into the preview area; return 0.
# S1's stub returns 1 so preview.sh exits non-zero on link failure (S1 contract
# §4: "non-zero only if fallback also fails"; the caller — input-handler /
# activate — decides). $1 = candidate session S (S2's capture target).
preview_fallback() {
	return 1
}

# argv[1] = candidate session name S.
preview_main() {
	local S="${1:-}"
	local current_session orig_window linked_id src_id

	# The session we preview INSIDE (the driver). Equal to the live client session
	# during browsing (Invariant A); client-independent (FINDING 9).
	current_session="$(get_state "$ORIG_SESSION" "")"
	orig_window="$(get_state "$ORIG_WINDOW" "")"
	linked_id="$(get_state "$STATE_LINKED_ID" "")"

	# --- S2: insert the @livepicker-preview-mode gate here (live|snapshot|off) ---

	# Self-session guard (PRD §7; FINDING 6). Do NOT link — would create an
	# in-session duplicate; instead show the user their own session. Select the
	# original window and return. (S1: do not unlink/clear LINKED_ID here.)
	if [ -n "$current_session" ] && [ "$S" = "$current_session" ]; then
		[ -n "$orig_window" ] && tmux select-window -t "$orig_window" 2>/dev/null || true
		return 0
	fi

	# Resolve S's active window id (exact-match =S; one line @N; FINDING 7).
	src_id="$(tmux list-windows -t "=$S" -F '#{window_id}' -f '#{window_active}' 2>/dev/null)"
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
