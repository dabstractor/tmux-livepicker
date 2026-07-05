#!/usr/bin/env bash
# shellcheck disable=SC1091  # sources a sibling lib via the resolved $CURRENT_DIR; follow with `shellcheck -x` if you want it traced.
# plugin.tmux — tmux-livepicker entry point.
#
# Binds @livepicker-key (in the PREFIX table) to launch the picker. Mirrors the
# structure of tmux-session-history/session_history.tmux (CURRENT_DIR idiom, inline
# option read, option-driven bind-key, reload-safe idempotent re-bind).
#
# LOAD-BEARING RULE (system_context §5): prefix is None; tubular binds C-Space in
# the ROOT table to switch INTO the prefix table. @livepicker-key is therefore a
# PREFIX-table binding. `tmux bind-key` with NO `-T` and NO `-n` targets the prefix
# table by default (verified live on 3.6b). Do NOT add `-n` (root) — it would
# shadow tubular's root C-Space binding and break prefix entry for the whole session.
#
# DEPENDENCY: sources scripts/options.sh (P1.M1.T1.S1) for get_opt. The bind TARGET
# scripts/livepicker.sh is created by P1.M4.T1.S1 and NEED NOT EXIST YET —
# bind-key stores the path as a string; tmux only runs it when the key is pressed.
#
# GUARD (PRD §11): if @livepicker-key is unset/empty, print a display-message and
# bind nothing, exiting 0 so the plugin still loads cleanly.
#
# NO `set -e` — a bad @livepicker-key makes `tmux bind-key` print `unknown key:`
# and return non-zero; we want graceful degradation (warn + clean exit), not abort.
# `set -u` is inherited from options.sh and is safe here (every var is assigned first).

CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/options.sh
source "$CURRENT_DIR/scripts/options.sh"

KEY="$(get_opt "@livepicker-key" '')"

if [ -z "$KEY" ]; then
	# Unset/empty: do not bind. Tell the user how to enable, and load cleanly.
	tmux display-message 'tmux-livepicker: set @livepicker-key to activate'
	exit 0
fi

# Prefix-table bind (DEFAULT target — NO -n, NO -T). -n would put this in the root
# table and shadow tubular's root C-Space (switch-client -T prefix), breaking prefix.
tmux bind-key "$KEY" run-shell "$CURRENT_DIR/scripts/livepicker.sh"

exit 0
