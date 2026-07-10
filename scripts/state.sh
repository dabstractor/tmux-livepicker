#!/usr/bin/env bash
# scripts/state.sh — tmux-livepicker runtime state accessors + saved-state CONTRACT.
#
# Sourced library (NOT executed). Three responsibilities:
#   1. set_state/get_state — thin accessors over the 6 @livepicker-* runtime keys.
#   2. Named readonly constants for the saved-state CONTRACT (the integration seam
#      P1.M4.T1.S1 activate writes and P1.M5.T3.S1 restore reads — PRD §9).
#   3. The status-format -gu trap (state_status_format_save / _restore) +
#      clear_all_state teardown.
#
# DEPENDS ON scripts/utils.sh: the caller MUST `source scripts/utils.sh` BEFORE this
# file. We assume tmux_get_opt / tmux_set_opt / tmux_unset_opt are defined. We do NOT
# source utils.sh ourselves (mirror the options/utils convention; no SCRIPT_DIR).
#
# CONTRACT CORRECTIONS encoded here (see research/state_module_findings.md):
#   CORRECTION A — clear_all_state clears ONLY picker-internal keys (5 runtime +
#     every @livepicker-orig-*). It MUST NOT unset PRD §11 config (@livepicker-fg,
#     @livepicker-key, ...). The literal "grep '@livepicker-' and unset each" is a
#     production bug (wipes user config mid-session). @livepicker-type is preserved
#     (shared config+runtime mirror; the picker only reads it).
#   CORRECTION D — the status-format "is this index user-set?" probe via tmux_is_set
#     is USELESS (rc=0 for set/default/never-existed). The corrected mechanism:
#     enumerate materialized indices from the bulk dump; tmux always materializes
#     defaults [0,1,2]; indices >= 3 are user-set. Save stores only those; restore
#     does the -gu reset (TRAP 1) then replays them.
#
# CONTRACT: sourcing this file has NO side effects (beyond defining readonly consts).
# Coexists with options.sh (get_opt/opt_*) and utils.sh (tmux_*): disjoint namespacing.
#
# shellcheck disable=SC2034
# SC2034 (file-wide): every STATE_* and ORIG_* constant is the saved-state CONTRACT —
# an integration seam CONSUMED by external scripts (livepicker.sh activate P1.M4,
# restore.sh P1.M5, input-handler.sh/preview.sh/renderer.sh P1.M2-M6) which source
# this library and reference these names directly. They are intentionally unused
# within this file; their stability across activate↔restore is the whole point.

set -u   # NOT -e (show-option legitimately returns non-zero); NOT -o pipefail.

# --- runtime state keys (picker-internal; cleared on exit by clear_all_state) ---
readonly STATE_MODE="@livepicker-mode"
readonly STATE_LIST="@livepicker-list"
readonly STATE_FILTER="@livepicker-filter"
readonly STATE_INDEX="@livepicker-index"
readonly STATE_LINKED_ID="@livepicker-linked-id"
readonly STATE_TYPE="@livepicker-type"   # session|window — ALIAS of PRD §11 config (read-only; NEVER cleared)
readonly STATE_TAB_CURRENT_TMPL="@livepicker-tab-current-tmpl"   # cached window-status-current-format (PRD §17; written P1.M1.T2, read P1.M1.T3; cleared via _STATE_RUNTIME_KEYS)
readonly STATE_TAB_INACTIVE_TMPL="@livepicker-tab-inactive-tmpl" # cached window-status-format         (PRD §17; written P1.M1.T2, read P1.M1.T3; cleared via _STATE_RUNTIME_KEYS)
readonly STATE_PREVIEW_SEQ="@livepicker-preview-seq"        # monotonic supersede counter (PRD §18; external_tmux_behavior.md Q6): bumped by the fire helper (P1.M2.T3), re-checked by preview.sh (P1.M2.T2) before mutating; init 0 at activate; cleared via _STATE_RUNTIME_KEYS
readonly STATE_PREVIEW_TARGET="@livepicker-preview-target"  # latest session/window token (PRD §18): written by the fire helper (P1.M2.T3), read/rechecked by preview.sh (P1.M2.T2); cleared via _STATE_RUNTIME_KEYS
readonly STATE_SCROLL="@livepicker-scroll"            # viewport scroll offset (PRD §19 §3.32): written by input-handler scroll-into-view/reset (P1.M3.T2); read by the renderer viewport slice; init 0 at activate (P1.M3.T1); cleared via _STATE_RUNTIME_KEYS
readonly STATE_CLIENT_WIDTH="@livepicker-client-width"  # invoking-client width cache (PRD §10 §3.35): captured at activate (P1.M3.T1) via display-message -p '#{client_width}', refreshed by the client-resized hook; the renderer measures the viewport against this (no per-keystroke tmux round-trip, §18); cleared via _STATE_RUNTIME_KEYS
readonly STATE_RENDER_CACHE="@livepicker-render-cache"  # renderer STATIC-config blob (newline-separated, fixed field order): baked ONCE at activate (scripts/livepicker.sh::_lp_build_render_cache) so the per-redraw renderer reads ONE option instead of ~10 round-trips that each fork a tmux client (~3-4ms each — the dominant renderer cost). The renderer (scripts/renderer.sh::_lp_load_render_config) reads it once and falls back to fresh per-option reads if absent/partial, so a missing/stale cache never breaks rendering. Static config never changes during a picker session (same assumption the §17 tab-template cache already relies on). Cleared via _STATE_RUNTIME_KEYS
readonly STATE_CAND_WIN_SESSION="@livepicker-cand-win-session"  # cache-invalidation key: the candidate session the cached window-list belongs to (PRD §9; read by P2.M1.T3 flip actions to decide whether to re-derive the list); init = current session at activate; cleared via _STATE_RUNTIME_KEYS
readonly STATE_CAND_WIN_LIST="@livepicker-cand-win-list"        # newline-joined ordered window ids of STATE_CAND_WIN_SESSION's candidate; derived lazily on first window flip (P2.M1.T3); init '' at activate; cleared via _STATE_RUNTIME_KEYS
readonly STATE_CAND_WIN_CURSOR="@livepicker-cand-win-cursor"    # 0-based index into STATE_CAND_WIN_LIST; defaults to the candidate's ACTIVE window on entry (PRD §9); advanced/wrapped by P2.M1.T3 next/prev-window; init '0' at activate; cleared via _STATE_RUNTIME_KEYS
readonly STATE_PREVIEW_WIN_ID="@livepicker-preview-win-id"      # the window currently shown; OVERLAPS STATE_LINKED_ID for non-self candidates, DIVERGES for the self-session (linked-id empty there); set by P2.M1.T2 preview; init '' at activate; cleared via _STATE_RUNTIME_KEYS

# --- saved-state CONTRACT keys (PRD §9; written by activate, read by restore) ---
readonly ORIG_SESSION="@livepicker-orig-session"
readonly ORIG_WINDOW="@livepicker-orig-window"                         # window ID, NOT index
readonly ORIG_LAYOUT="@livepicker-orig-layout"                         # window_layout string
readonly ORIG_KEY_TABLE="@livepicker-orig-key-table"
readonly ORIG_STATUS="@livepicker-orig-status"                         # status line-count value
readonly ORIG_RENUMBER="@livepicker-orig-renumber-windows"
readonly ORIG_WINDOW_SIZE="@livepicker-orig-window-size"                     # driver's pre-activate window-size (PRD §9/§22; frozen to manual in clip mode; SESSION-SCOPED value saved, empty=inherits global; auto-cleared by clear_all_state's grep '@livepicker-orig-')
readonly ORIG_HOOK="@livepicker-orig-session-window-changed"           # FULL show-hooks output (multi-line)
readonly ORIG_CLIENT_RESIZED_HOOK="@livepicker-orig-client-resized"        # FULL show-hooks output (the IDENTICAL-shape mirror of ORIG_HOOK; §P4); saved/restored by activate/restore (P1.M3.T1); auto-cleared by clear_all_state's grep '@livepicker-orig-'
readonly ORIG_STATUS_FORMAT_INDICES="@livepicker-orig-status-format-indices"
readonly ORIG_STATUS_FORMAT_PREFIX="@livepicker-orig-status-format-"   # +N suffix (bracket-free)

# keys clear_all_state unsets explicitly (STATE_TYPE deliberately absent: it is config)
readonly _STATE_RUNTIME_KEYS="$STATE_MODE $STATE_LIST $STATE_FILTER $STATE_INDEX $STATE_LINKED_ID $STATE_TAB_CURRENT_TMPL $STATE_TAB_INACTIVE_TMPL $STATE_PREVIEW_SEQ $STATE_PREVIEW_TARGET $STATE_SCROLL $STATE_CLIENT_WIDTH $STATE_RENDER_CACHE $STATE_CAND_WIN_SESSION $STATE_CAND_WIN_LIST $STATE_CAND_WIN_CURSOR $STATE_PREVIEW_WIN_ID"

# $1: STATE_* key, $2: value. Writes a runtime @livepicker-* option (delegates to
# utils tmux_set_opt). Caller passes a STATE_* constant, not a raw string.
set_state() {
	tmux_set_opt "$1" "$2"
}

# $1: STATE_* key, $2: optional default (returned when unset/empty). Reads a runtime
# @livepicker-* option (delegates to utils tmux_get_opt). ${2:-} makes the default
# OPTIONAL and safe under `set -u`.
get_state() {
	tmux_get_opt "$1" "${2:-}"
}

# SAVE the status-format array for later restore. Enumerates materialized indices
# from `show-options -g status-format` and saves EVERY one (indices 0-9, per PRD
# §10 "save every set status-format[n] (indices 0 through 9)"). tmux materializes
# the 3 built-in defaults [0,1,2] even when unset, so the exit-code probe cannot
# distinguish user-set from default (FINDING D). Instead we capture the live value
# of every materialized index; restore replays them after the -gu reset. This is
# correct in both cases:
#   - default [0,1,2]: the captured string IS the tmux default; replaying it after
#     -gu (which re-composes the same default) is a no-op-equivalent -> safe.
#   - user-overridden [0,1,2]: the captured string is the user override; it is
#     faithfully replayed -> preserved (M2 fix; the old >=3-only shortcut dropped
#     genuine user overrides of [0,1,2]).
# Stores the index list in ORIG_STATUS_FORMAT_INDICES and each value in a
# bracket-free ORIG_STATUS_FORMAT_PREFIX+N key (brackets rejected in @-names).
state_status_format_save() {
	local bulk idx user_indices n val
	bulk="$(tmux show-options -g status-format 2>/dev/null)"
	user_indices=""
	# heredoc (not a pipe) feeds $bulk to while-read so the loop runs in this shell
	# (avoids a subshell scoping the user_indices accumulation under `set -u`).
	while IFS= read -r line; do
		idx="$(printf '%s\n' "$line" | sed -n 's/^status-format\[\([0-9]\+\)\].*/\1/p')"
		[ -z "$idx" ] && continue
		[ "$idx" -ge 0 ] && [ "$idx" -le 9 ] || continue
		user_indices="${user_indices}${user_indices:+ }$idx"
	done <<EOF
$bulk
EOF
	tmux_set_opt "$ORIG_STATUS_FORMAT_INDICES" "$user_indices"
	# shellcheck disable=SC2086
	# intentional word-split: $user_indices is the internal space-list of digit-only
	# indices we just built; splitting is how we iterate each index in turn.
	for n in $user_indices; do
		val="$(tmux show-option -gqv "status-format[$n]" 2>/dev/null)"
		tmux_set_opt "${ORIG_STATUS_FORMAT_PREFIX}${n}" "$val"
	done
}

# RESTORE the status-format array (TRAP 1, system_context §4). Step 1:
# `set-option -gu status-format` clears EVERY index and tmux re-composes the
# [0,1,2] defaults. Step 2: replay EVERY index saved by state_status_format_save
# (now 0-9, per the M2 fix). For default [0,1,2] the replayed string equals the
# re-composed default (no-op-equivalent); for user overrides it faithfully
# restores the user value.
state_status_format_restore() {
	local indices n val
	tmux_unset_opt status-format
	indices="$(tmux_get_opt "$ORIG_STATUS_FORMAT_INDICES" "")"
	# shellcheck disable=SC2086
	# intentional word-split: $indices is the saved space-list of digit-only indices
	# (empty when the user had no status-format overrides — the tubular common case).
	for n in $indices; do
		val="$(tmux_get_opt "${ORIG_STATUS_FORMAT_PREFIX}${n}" "")"
		[ -n "$val" ] && tmux_set_opt "status-format[$n]" "$val"
	done
}

# Tear down ALL picker-INTERNAL state. Unsets the 5 runtime keys + every
# @livepicker-orig-* saved-state key. MUST NOT unset PRD §11 config (CORRECTION A):
# `grep '@livepicker-'` broadly would wipe @livepicker-fg/#ffffff, @livepicker-key,
# etc. We clear the runtime list explicitly and grep ONLY '@livepicker-orig-'.
# @livepicker-type is preserved (shared config+runtime mirror; never written by us).
# set-option -gu is safe on already-unset @-options (rc=0); `|| true` + 2>/dev/null
# belt-and-braces. Key-table teardown (unbind-key -T livepicker) is restore.sh's
# job (P1.M5.T4.S1) — clear_all_state clears OPTIONS only.
clear_all_state() {
	local k
	# shellcheck disable=SC2086
	# intentional word-split: $_STATE_RUNTIME_KEYS is the internal space-list of the
	# 5 runtime @livepicker-* keys we deliberately enumerate and clear one-by-one.
	for k in $_STATE_RUNTIME_KEYS; do
		tmux set-option -gu "$k" 2>/dev/null || true
	done
	# heredoc (not `grep | while`) keeps the while-read in this shell so `k` scoping
	# is correct; the grep output is captured at expansion time into the heredoc.
	while IFS= read -r line; do
		k="${line%% *}"
		[ -n "$k" ] && tmux set-option -gu "$k" 2>/dev/null || true
	done <<EOF
$(tmux show-options -g 2>/dev/null | grep '@livepicker-orig-')
EOF
}
