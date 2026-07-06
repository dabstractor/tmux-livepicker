#!/usr/bin/env bash
# scripts/utils.sh — tmux-livepicker general-purpose tmux option & hook primitives.
#
# Sourced library (NOT executed). Provides the safe wrappers around show-option /
# set-option / show-hooks / set-hook that the save (livepicker.sh) and restore
# (restore.sh) paths build on, so neither re-implements the two environment traps
# documented in plan/001_fd5d622d3939/architecture/system_context.md §4:
#   TRAP 1 — status-format restore MUST be `set-option -gu status-format` (unset
#            all → tmux re-composes defaults), NOT literal replay of captured
#            strings. tmux_unset_opt status-format does exactly this.
#   TRAP 2 — session-window-changed is array-indexed with -b; save the WHOLE
#            show-hooks line. tmux_get_hook returns it verbatim; tmux_clear_hook
#            clears every index via set-hook -gu.
#
# CONTRACT: sourcing this file has NO side effects — it touches no tmux state
# and prints nothing. All work happens inside functions called by the consumer.
# Coexists with options.sh (get_opt/opt_*): the tmux_ prefix is disjoint.

set -u   # NOT -e (show-option/show-hooks legitimately return non-zero); NOT -o pipefail.

# $1: option name, $2: optional default (returned when option is unset/empty).
# Reads the EFFECTIVE global value (built-in options return their default even
# when unset — e.g. key-table -> "root"). For "was it explicitly set?" use
# tmux_is_set (and note its @-options-only limitation).
tmux_get_opt() {
	local v
	v="$(tmux show-option -gqv "$1")"
	[ -n "$v" ] && echo "$v" || echo "${2:-}"
}

# $1: option name, $2: value. Sets a global option. For array options pass the
# indexed name, e.g. tmux_set_opt "status-format[0]" "#(...)".
tmux_set_opt() {
	tmux set-option -g "$1" "$2"
}

# $1: option name. Unsets (→ tmux default). For an array option with NO index
# (e.g. "status-format") this clears EVERY index and tmux re-composes defaults —
# this is the TRAP-1 status-format restore. An indexed name ("status-format[4]")
# clears just that index.
tmux_unset_opt() {
	tmux set-option -gu "$1"
}

# $1: orig_name (bracket-free dest suffix), $2: src_name (option to read).
# Snapshots src_name's value into @livepicker-orig-${orig_name}.
# GOTCHA: tmux rejects brackets in @-option names ("not an array" error), so
# orig_name MUST be bracket-free. For status-format indices pass a sanitized
# suffix: tmux_save_opt "status-format-0" "status-format[0]". For ordinary
# options pass both args identical: tmux_save_opt status status.
tmux_save_opt() {
	local v
	v="$(tmux show-option -gqv "$2")"
	tmux set-option -g "@livepicker-orig-$1" "$v"
}

# $1: option name. Exit-code probe (return code = tmux exit code): 0 = set
# (even if set to ""), 1 = unset. Mirrors tubular's __tubular_is_set verbatim.
#
# LIMITATION (verified on tmux 3.6b): reliable ONLY for @-user-options (which
# have no built-in default). For built-in options (status, key-table, ...) and
# array indices (status-format[n]) the exit code is ALWAYS 0 — set, default, or
# never-existed all return 0. DO NOT use this to decide status-format save/
# restore; use unconditional tmux_unset_opt status-format there (TRAP 1).
tmux_is_set() {
	tmux show-options -g "$1" >/dev/null 2>&1
}

# $1: hook name. Prints the FULL raw show-hooks output (multi-line, one
# "hookname[N] <cmd>" per index). When the hook is cleared, prints just the bare
# hook name (no [N], no cmd) and still exits 0 — so "is it set?" is decided by
# grepping for a '[' marker, not by the exit code. Caller strips the
# "hookname[N] " prefix to recover commands for replay (system_context §7).
tmux_get_hook() {
	tmux show-hooks -g "$1"
}

# lp_filter_harmful_bindings — stdin -> stdout filter that DROPS key bindings whose
# command would break the picker's core guarantees (H3 fix). Used by activate to
# filter the prefix+root bindings before copying them into the livepicker table.
#
# Two classes are dropped:
#   1. SESSION/WINDOW-SWITCHING — break Invariant A ("browsing must not change
#      the client's session"); fire client-session-changed -> history pollution.
#      e.g. switch-client, next/previous-window, select-window -n/-p, choose-tree.
#   2. STATE-MUTATING — break "display-only preview" (PRD §7); the linked window
#      is a SHARED object so mutations damage the SOURCE session and are NOT
#      restored on exit. e.g. next-layout, kill-window/pane, split-window,
#      swap-pane/window, resize-pane, rename-session/window, new-window/session.
#
# Detection: a binding line matches when, after the table+key spec, the command
# word (or a flag-bearing form like `select-window -n`) appears. We match the
# command token following the key, which covers both `cmd ...` and `cmd -flag ...`.
# Mouse bindings (MouseDown1Status etc.) whose command switches/mutates are also
# dropped by the same command-word match.
#
# Non-harmful user bindings (display-menu, capture-pane, custom scripts, etc.)
# pass through, preserving PRD §8's intent for keys that do not endanger the
# invariants. The explicit picker keys (typing/nav/confirm/cancel) are bound
# AFTER the copy and OVERRIDE any same-key binding, so a dropped harmful binding
# does not leave its key inert.
lp_filter_harmful_bindings() {
	grep -vE \
		-e '[[:space:]]switch-client([[:space:]]|$)' \
		-e '[[:space:]]next-window([[:space:]]|$)' \
		-e '[[:space:]]previous-window([[:space:]]|$)' \
		-e '[[:space:]]last-window([[:space:]]|$)' \
		-e '[[:space:]]select-window([[:space:]]|$)' \
		-e '[[:space:]]choose-tree([[:space:]]|$)' \
		-e '[[:space:]]choose-session([[:space:]]|$)' \
		-e '[[:space:]]choose-window([[:space:]]|$)' \
		-e '[[:space:]]find-window([[:space:]]|$)' \
		-e '[[:space:]]next-layout([[:space:]]|$)' \
		-e '[[:space:]]previous-layout([[:space:]]|$)' \
		-e '[[:space:]]kill-window([[:space:]]|$)' \
		-e '[[:space:]]kill-pane([[:space:]]|$)' \
		-e '[[:space:]]split-window([[:space:]]|$)' \
		-e '[[:space:]]break-pane([[:space:]]|$)' \
		-e '[[:space:]]join-pane([[:space:]]|$)' \
		-e '[[:space:]]swap-pane([[:space:]]|$)' \
		-e '[[:space:]]swap-window([[:space:]]|$)' \
		-e '[[:space:]]move-window([[:space:]]|$)' \
		-e '[[:space:]]move-pane([[:space:]]|$)' \
		-e '[[:space:]]resize-pane([[:space:]]|$)' \
		-e '[[:space:]]rename-session([[:space:]]|$)' \
		-e '[[:space:]]rename-window([[:space:]]|$)' \
		-e '[[:space:]]new-window([[:space:]]|$)' \
		-e '[[:space:]]new-session([[:space:]]|$)' \
		-e '[[:space:]]delete-buffer([[:space:]]|$)' \
		-e '[[:space:]]clear-history([[:space:]]|$)' \
		-e '[[:space:]]pipe-pane([[:space:]]|$)' \
		-e '[[:space:]]confirm-before[[:space:]].*(kill|delete)' \
		|| true   # grep -v exits 1 when ALL lines are filtered out (empty result is valid)
}

# lp_resolve_client — print the name of the invoking (attached) client, or "".
#
# Resolves the attached tmux client the picker is operating under. Used to make
# state capture client-aware (H1 fix): `display-message -p '#{session_name}'`
# returns the SERVER's last-active session, NOT reliably the attached client's
# session — so a stale pointer (any session created/switched after the client's
# last interaction, e.g. continuum/resurrect auto-restore) captures the wrong
# driver and can destroy an unrelated session at confirm.
#
# Resolution order (first non-empty wins):
#   1. The single attached client, when there is exactly one (the documented
#      single-client target environment — README "Non-goals: Single attached
#      client"). This is deterministic and race-free.
#   2. The most recently active client (list-clients is MRU-ordered by tmux),
#      used only when more than one client is attached. tmux runs run-shell from
#      the invoking client, so the MRU client is the invoker.
#   3. "" if no client is attached (detached/test edge) -> callers fall back to
#      the saved ORIG_SESSION or a client-independent path.
#
# Prints the client name (e.g. "/dev/pts/3") to stdout; empty on no client.
# Exits 0 regardless (callers treat empty as "no client").
lp_resolve_client() {
	local clients
	clients="$(tmux list-clients -F '#{client_name}' 2>/dev/null)"
	[ -n "$clients" ] || return 0
	# list-clients is MRU-ordered; head -1 is the most-recently-active client,
	# which under run-shell from a keypress is the invoker.
	printf '%s\n' "$clients" | head -1
}

# lp_client_format FORMAT — print a tmux format string resolved against the
# INVOKING client (client-aware; H1 fix). Falls back to the context-free form
# when no client is attached (detached/test edge) so behaviour degrades to the
# previous semantics rather than failing.
#
# $1: the tmux format (e.g. '#{session_name}', '#{window_id}', '#{window_layout}').
lp_client_format() {
	local fmt="$1"
	local client
	client="$(lp_resolve_client)"
	if [ -n "$client" ]; then
		tmux display-message -t "$client" -p "$fmt" 2>/dev/null || true
	else
		tmux display-message -p "$fmt" 2>/dev/null || true
	fi
}

# $1: hook name. Clears EVERY index of the hook array (mirrors set-option -gu
# on an array option). Used by activate to suppress session-window-changed.
tmux_clear_hook() {
	tmux set-hook -gu "$1"
}
