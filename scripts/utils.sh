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

# $1: hook name. Clears EVERY index of the hook array (mirrors set-option -gu
# on an array option). Used by activate to suppress session-window-changed.
tmux_clear_hook() {
	tmux set-hook -gu "$1"
}
