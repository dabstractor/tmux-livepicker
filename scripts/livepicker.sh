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

# _lp_resolve_tab_templates — PRD §17: resolve the theme's window-status[-current]-format
# against a short-lived hidden sentinel window and cache the two rendered templates, so the
# renderer (P1.M1.T3) can emit theme-matched tabs from a #() status command (whose stdout is
# NOT re-parsed for #{…} — only #[…] styles apply). Done ONCE at activation (fast; no
# per-keystroke display-message). Gated on @livepicker-tab-style == window-status; in plain
# mode it is a no-op. On ANY failure/ambiguity it leaves both cache keys SET-EMPTY (real
# `tmux set-option -g @x ""`, NOT unset) so the renderer's tmux_is_set probe detects "resolved
# empty" and falls back to plain (PRD §17 Fallback, §16 fragility). ALWAYS returns 0 — this
# is a cosmetic enhancement; it must NEVER block activation. See research/
# sentinel_resolution_findings.md (FINDING 1 new-window form, FINDING 3 never-empty value,
# FINDING 5 set-empty contract).
_lp_resolve_tab_templates() {
	# plain mode (the default) -> no-op; the renderer takes the plain path regardless.
	[ "$(opt_tab_style)" = "window-status" ] || return 0

	local cur_fmt reg_fmt cur_tpl reg_tpl sent_sess

	# (a) Read both format VALUES (window options -> -gwv global-window scope). NOTE: these
	# NEVER read empty (tmux always materializes a default); the empty-check below is
	# defensive. The real fallback is the unexpanded-'#{' check in (e). (FINDING 3)
	cur_fmt="$(tmux show-options -gwv window-status-current-format 2>/dev/null)"
	reg_fmt="$(tmux show-options -gwv window-status-format 2>/dev/null)"
	if [ -z "$cur_fmt" ] || [ -z "$reg_fmt" ]; then
		set_state "$STATE_TAB_CURRENT_TMPL" ""
		set_state "$STATE_TAB_INACTIVE_TMPL" ""
		return 0
	fi

	# (b) Create a hidden 2-window sentinel session (anchor + tab). CRITICAL (FINDING 1):
	# `new-window -d -t "$sent_sess"` (bare) FAILS under base-index=1/renumber ("index in
	# use"); the TRAILING-COLON form `-t "$sent_sess:"` picks a free slot. Force-select the
	# anchor so __lp_tab__ is NON-active -> clean window-state specifiers. The sentinel
	# SESSION name is a FIXED placeholder `__lp_sentinel__` (not unique) so that a theme's
	# SESSION-state specifiers (#S / #{session_name}) bake a STABLE placeholder the renderer
	# can swap — mirroring the sentinel WINDOW name `__lp_tab__` (from #W). Issue 5.
	# Pre-clean any stray sentinel left by a crashed prior run (new-session on an existing
	# name would FAIL -> set-empty fallback -> plain tabs). Concurrency-safe: the modal
	# @livepicker-mode guard (activate_main) blocks a 2nd activation, so no two sentinels
	# coexist. RESIDUAL: a user session literally named __lp_sentinel__ would be destroyed
	# here (vanishing probability; the fixed name is required for the renderer swap).
	tmux kill-session -t "__lp_sentinel__" 2>/dev/null || true
	sent_sess="__lp_sentinel__"
	if ! tmux new-session -d -s "$sent_sess" -n __lp_anchor__ 2>/dev/null; then
		set_state "$STATE_TAB_CURRENT_TMPL" ""
		set_state "$STATE_TAB_INACTIVE_TMPL" ""
		return 0
	fi
	# (trailing colon = target the session; tmux appends at a free index)
	if ! tmux new-window -d -t "$sent_sess:" -n __lp_tab__ 2>/dev/null; then
		tmux kill-session -t "$sent_sess" 2>/dev/null || true
		set_state "$STATE_TAB_CURRENT_TMPL" ""
		set_state "$STATE_TAB_INACTIVE_TMPL" ""
		return 0
	fi
	tmux select-window -t "$sent_sess:__lp_anchor__" 2>/dev/null || true

	# (c) Resolve both formats FULLY against the non-active sentinel window. Pass the OPTION
	# VALUE (not the literal #{window_status_current_format} — no such var). -p = stdout.
	# Expands every #{…} incl. #{E:@user_option} and #W (-> __lp_tab__ placeholder). (Q1)
	cur_tpl="$(tmux display-message -p -t "$sent_sess:__lp_tab__" "$cur_fmt" 2>/dev/null)"
	reg_tpl="$(tmux display-message -p -t "$sent_sess:__lp_tab__" "$reg_fmt" 2>/dev/null)"

	# (d) Kill the sentinel (tears down anchor + tab together; never leaks).
	tmux kill-session -t "$sent_sess" 2>/dev/null || true

	# (e) Guard: an unexpanded '#{' means a malformed theme (nested a format in a user-option
	# WITHOUT #{E:…}); blank it so the renderer falls back to plain. (FINDING 4: this fires
	# precisely for the tubular-misuse case; a plain unset @-opt resolves to empty, not '#{'.)
	case "$cur_tpl" in *"#{"*) cur_tpl="" ;; esac
	case "$reg_tpl" in *"#{"*) reg_tpl="" ;; esac

	# (f) Cache. If EITHER is empty (resolution failed OR the guard blanked it), set BOTH
	# empty (set-empty, NOT unset — FINDING 5: the renderer's tmux_is_set probe needs "set").
	if [ -z "$cur_tpl" ] || [ -z "$reg_tpl" ]; then
		set_state "$STATE_TAB_CURRENT_TMPL" ""
		set_state "$STATE_TAB_INACTIVE_TMPL" ""
	else
		set_state "$STATE_TAB_CURRENT_TMPL" "$cur_tpl"
		set_state "$STATE_TAB_INACTIVE_TMPL" "$reg_tpl"
	fi
	return 0
}

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
	# NOT tmux_save_opt). CLIENT-AWARE (H1 fix): resolved against the INVOKING
	# client via lp_client_format. The context-free `display-message -p
	# '#{session_name}'` returns the SERVER's last-active session, NOT reliably
	# the attached client's — a stale pointer (any session created/switched after
	# the client's last interaction, e.g. continuum/resurrect auto-restore at
	# startup) would capture the wrong driver, and confirm would then operate on
	# the wrong session (data-loss blast radius). lp_resolve_client picks the
	# invoking client (MRU under run-shell); display-message -t <client> makes
	# session_name/window_id/window_layout resolve against THAT client. Falls back
	# to the context-free form on the detached/test edge (no client attached).
	tmux set-option -g "$ORIG_SESSION" "$(lp_client_format '#{session_name}')"
	tmux set-option -g "$ORIG_WINDOW"   "$(lp_client_format '#{window_id}')"      # @N id, NOT index
	tmux set-option -g "$ORIG_LAYOUT"   "$(lp_client_format '#{window_layout}')"
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
	# Init the deferred-preview supersede counter (PRD §18 / external_tmux_behavior.md
	# Q6). Monotonic from 0; bumped by the fire helper (P1.M2.T3) and re-checked by
	# preview.sh (P1.M2.T2) so a late/superseded -b job is a no-op. clear_all_state
	# clears it on exit (via _STATE_RUNTIME_KEYS); this init is the authoritative
	# reset for the fresh session.
	set_state "$STATE_PREVIEW_SEQ" "0"

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
		# activation). CLIENT-AWARE (H1 fix): use lp_client_format so the token
		# resolves against the invoking client, not the server's last-active
		# session (research FINDING 4/5).
		list="$(tmux list-windows -a -F '#{session_name}:#{window_index}' 2>/dev/null)"
		current="$(lp_client_format '#{session_name}:#{window_index}')"
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
	# --- T2b (P1.M3.T1.S1): client-width cache + client-resized hook (PRD §10 step 5 / §3.35).
	# Capture the invoking client's width into @livepicker-client-width so the §19 renderer
	# measures the viewport with NO per-keystroke tmux round-trip (§18 budget; width=0 ->
	# degraded full-list render). Done AFTER T2 (window-mode token resolution needs the
	# client) and BEFORE T3 (the renderer is installed + first-rendered here). CLIENT-AWARE
	# via lp_client_format (H1 fix; falls back to context-free on the detached/test edge).
	# Then save the prior client-resized hook (tmux_get_hook, verbatim incl. -b / multi-index),
	# clear every index, and install ours -> input-handler.sh refresh-width, which re-caches
	# the width on resize. restore.sh STEP 4 clears ours + replays the saved lines (the
	# IDENTICAL shape as session-window-changed, §P4; the save MUST precede the clear).
	set_state "$STATE_CLIENT_WIDTH" "$(lp_client_format '#{client_width}')"
	tmux set-option -g "$ORIG_CLIENT_RESIZED_HOOK" "$(tmux_get_hook client-resized)"
	tmux_clear_hook client-resized
	# Absolute path (server cwd != plugin dir); single-quote the arg inside the double-quoted
	# run-shell (matches the key-binding form, livepicker.sh bind-key lines). Installs as
	# client-resized[0]; show-hooks -g always lists client-resized (bare when unset).
	tmux set-hook -g client-resized "run-shell '$CURRENT_DIR/input-handler.sh refresh-width'"
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
	#
	# H3 FIX — exclude HARMFUL copied bindings. The naive copy-all imports every
	# tmux default root binding + every user binding, including many that break
	# the plugin's two core guarantees:
	#   - SESSION/WINDOW-SWITCHING (break Invariant A — "browsing must not change
	#     the client's session"; fires client-session-changed -> history
	#     pollution): switch-client, next/previous-window, select-window -n/-p,
	#     choose-tree, etc.
	#   - STATE-MUTATING (break "display-only preview" PRD §7; the linked window
	#     is a SHARED object so mutations damage the SOURCE session and are NOT
	#     restored on exit): next-layout, kill-window/pane, split-window,
	#     swap-pane/window, resize-pane, rename-session/window, new-window/session.
	# The copy is therefore FILTERED: any binding whose command mentions one of
	# these harmful targets is dropped from the copy. The explicit picker keys
	# bound in (2) below run AFTER the copy and OVERRIDE any same-key binding, so
	# a harmful binding dropped here does not leave its key inert — the explicit
	# picker binds cover the keys the user actually needs (typing/nav/confirm/cancel).
	# Non-harmful user bindings (e.g. custom display-menu, capture-pane) are still
	# copied through, preserving PRD §8's intent ("rest of their keybinds keep
	# working") for keys that do not endanger the invariants.
	#
	# L3 FIX — the next/prev key skip uses a FIXED-STRING match (grep -F) per key
	# rather than a single ERE interpolating the key values, so a user-set
	# @livepicker-next-key containing regex metacharacters (`.`, `*`, `+`, `[`)
	# is treated literally and cannot mis-skip / double-bind.
	lp_key="$(opt_next_key)"
	lp_keys="$(opt_prev_key)"
	lp_tf="$(mktemp)"
	{
		tmux list-keys -T prefix 2>/dev/null | sed 's/-T prefix/-T livepicker/'
		tmux list-keys -T root   2>/dev/null | sed 's/-T root/-T livepicker/'
	} | lp_filter_harmful_bindings \
		| grep -vF -e "-T livepicker ${lp_key} " -e "-T livepicker ${lp_keys} " \
			-e "-T livepicker -r ${lp_key} " -e "-T livepicker -r ${lp_keys} " \
			> "$lp_tf"
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

	# --- P2.M1.T1.S1: session-mgmt keys (rename + delete), PRD §21 step 5. ---
	# SINGLE keys (not space-lists -> no loop). Bound AFTER the typing + nav
	# blocks so they OVERRIDE any same-key copy (C-r / M-BSpace are distinct
	# tmux keys from r / BSpace, so typing is unaffected -- PRD §8/§16). INERT
	# until P2.M1.T2 adds the rename)/delete) dispatch in input-handler.sh (the
	# default * branch is a no-op return 0 -> picker stays open).
	tmux bind-key -T livepicker "$(opt_rename_key)" run-shell "$CURRENT_DIR/input-handler.sh rename"
	tmux bind-key -T livepicker "$(opt_delete_key)" run-shell "$CURRENT_DIR/input-handler.sh delete"

	# (3) SWITCH the active key-table to livepicker (global; FINDING 3: -g is
	# mandatory and the standalone `key-table` cmd does not exist on 3.6b).
	tmux set-option -g key-table livepicker
	# --- T4 (P1.M4.T4.S2): suppress session-window-changed hook ---
	# PRD §7.11 "Side effects to suppress" + §16 "Hook suppression scope" +
	# system_context §4 TRAP 2 / §7. select-window DURING preview fires
	# session-window-changed, which runs the user's sync-window-focus.sh and
	# would spam focus bytes into the linked preview window on every nav
	# keystroke. When @livepicker-suppress-window-hook is "on" (PRD §11
	# default), clear the LIVE global hook for the picker duration. The SAVED
	# hook lives in @livepicker-orig-session-window-changed (captured verbatim
	# by STEP 2 / T1, incl. the -b flag + absolute path) and is replayed
	# EXACTLY by restore (P1.M5.T3.S1) — S2 does NOT touch that saved value.
	# If the option is "off", leave the hook INTACT (preview nav runs
	# sync-window-focus.sh — documented opt-in behavior). set-hook -gu clears
	# EVERY index of the hook array (verified; system_context §7 recipe) and is
	# a safe no-op on an already-cleared hook (rc=0). Uses the tmux_clear_hook
	# helper from utils.sh (house style; raw `tmux set-hook -gu
	# session-window-changed` is equivalent). NO -e (house style).
	if [ "$(opt_suppress_window_hook)" = "on" ]; then
		tmux_clear_hook session-window-changed
	fi
	# --- T5 (P1.M4.T5.S1): first preview + set @livepicker-mode on + refresh ---
	# PRD §6 Activation steps 6-7 + §10/§13. The FINAL activate step: show the
	# first preview, arm the guard, force the renderer to draw. ORDER IS
	# LOAD-BEARING (research FINDING 5): (1) preview; (2) mode-on LAST; (3)
	# refresh. The first highlight is the current session (T2's initial index),
	# so this is the SELF-SESSION path (PRD §7 / P1.M3.T1.S2): preview.sh reads
	# current_session from @livepicker-orig-session, sees S == current_session,
	# and select-window's ORIG_WINDOW WITHOUT linking (leaves @livepicker-linked-id
	# empty). Read the session name from @livepicker-orig-session (saved by STEP 2;
	# client-independent) — do NOT reuse T2's `current` (it is session:window_index
	# in window mode). The `|| return 1` is REQUIRED: under house `set -u` (NO -e)
	# a bare failing preview would fall through to mode-on, arming the guard on a
	# broken picker (stuck). The guard makes "mode-on is LAST so a crash leaves
	# mode off (re-activatable — PRD §16)" actually hold. (The self-session path
	# always returns 0, so this guard is defensive — but it is the contract's
	# stated safety property.) Then set @livepicker-mode on (arms the STEP-1
	# double-activation guard). Then `tmux refresh-client -S` forces a status
	# redraw that re-runs the #() renderer (PRD §10/§13; verified) so the picker
	# list appears on line 1 NOW instead of waiting on status-interval. refresh
	# targets the invoking client (the user pressed the key -> a client exists);
	# its rc is non-fatal under no-set-e (best-effort draw — mode is already on).
	local orig_session
	orig_session="$(get_state "$ORIG_SESSION" "")"
	# L2 FIX: if the first preview fails, roll back the half-applied picker state
	# (status grow / key-table switch / hook clear / copied key bindings) by calling
	# restore cancel BEFORE returning. Without this, mode stays off (re-activatable)
	# but the mutated status/key-table/hook remain, and a re-activation would
	# re-save THAT mutated state as the "original" baseline -> corrupt restore.
	# restore cancel tears down cleanly and switches the client back to ORIG_SESSION
	# (a same-session switch, deduped by the history engine -> 0 net entries). The
	# `|| true` ensures a failure inside restore cannot mask the original error.
	if ! "$CURRENT_DIR/preview.sh" "$orig_session"; then
		"$CURRENT_DIR/restore.sh" cancel 2>/dev/null || true
		return 1
	fi
	# PRD §17: resolve theme tab formats once + cache (no-op in plain mode; never blocks).
	_lp_resolve_tab_templates
	set_state "$STATE_MODE" "on"
	tmux refresh-client -S
	return 0
}

activate_main "$@" || exit 1
exit 0
