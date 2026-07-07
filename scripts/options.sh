#!/usr/bin/env bash
# scripts/options.sh — tmux-livepicker option accessors.
#
# Sourced library (NOT executed). Defines get_opt() plus one opt_<name>()
# accessor per @livepicker-* option (PRD §11), each baking in its PRD default.
# Mirrors the get_tmux_option idiom shared by session-history / sessionx /
# resurrect (see plan/001_fd5d622d3939/architecture/sibling_plugins_and_env.md §4).
#
# CONTRACT: sourcing this file has NO side effects — it touches no tmux state
# and prints nothing. All work happens inside functions called by the consumer.

set -u   # NOT -e (option reads legitimately return non-zero); NOT -o pipefail.

# $1: option name (e.g. "@livepicker-type"), $2: default value
get_opt() {
	local value
	value="$(tmux show-option -gqv "$1")"
	[ -n "$value" ] && echo "$value" || echo "$2"
}

# --- per-option accessors (defaults are PRD §11 verbatim) ---------------------
# Each accessor returns the user-set value if present, else the PRD default.
# (Argument formatting uses single space so the Level 4 default cross-check grep
# matches each `get_opt "@livepicker-<suffix>" "<default>"` exactly once.)

opt_key()                  { get_opt "@livepicker-key" ""; }                  # required: empty if unset (guard lives in plugin.tmux)
opt_type()                 { get_opt "@livepicker-type" "session"; }          # enum: session|window
opt_create()               { get_opt "@livepicker-create" "on"; }             # bool on/off (session mode only)
opt_zoxide()               { get_opt "@livepicker-zoxide-mode" "off"; }       # bool on/off (session-mode create only)
opt_next_key()             { get_opt "@livepicker-next-key" "C-M-Tab"; }      # single key (repurposed window-nav)
opt_prev_key()             { get_opt "@livepicker-prev-key" "C-M-BTab"; }     # single key (repurposed window-nav)
opt_nav_next_keys()        { get_opt "@livepicker-nav-next-keys" "Down"; }    # space-list (caller word-splits)
opt_nav_prev_keys()        { get_opt "@livepicker-nav-prev-keys" "Up"; }      # space-list (caller word-splits)
opt_confirm_keys()         { get_opt "@livepicker-confirm-keys" "Enter"; }    # space-list
opt_cancel_keys()          { get_opt "@livepicker-cancel-keys" "Escape"; }    # space-list (clear query, else cancel)
opt_backspace_keys()       { get_opt "@livepicker-backspace-keys" "BSpace"; } # space-list
opt_preview_mode()         { get_opt "@livepicker-preview-mode" "live"; }     # enum: live|snapshot|off
opt_suppress_window_hook() { get_opt "@livepicker-suppress-window-hook" "on"; } # bool on/off
opt_fg()                   { get_opt "@livepicker-fg" "default"; }            # tmux color
opt_bg()                   { get_opt "@livepicker-bg" "default"; }            # tmux color
opt_highlight_fg()         { get_opt "@livepicker-highlight-fg" "black"; }    # tmux color
opt_highlight_bg()         { get_opt "@livepicker-highlight-bg" "yellow"; }   # tmux color
opt_show_count()           { get_opt "@livepicker-show-count" "on"; }         # bool on/off
opt_status_format_index()  { get_opt "@livepicker-status-format-index" "0"; } # int 0-9
opt_tab_style()            { get_opt "@livepicker-tab-style" "plain"; }       # enum: plain|window-status (PRD §17; plain=standalone fg/bg, window-status=reuse theme window-status-format)
opt_preview_defer()        { get_opt "@livepicker-preview-defer" "on"; }      # bool on|off (PRD §18; on=defer preview to bg run-shell -b supersedeable job, off=legacy synchronous)
opt_nerd_fonts()             { get_opt "@livepicker-nerd-fonts" "on"; }             # bool on/off (opt-out for the search icon; tmux can't detect the font)
opt_search_icon()            { get_opt "@livepicker-search-icon" $'\uf002'; }       # glyph: nf-fa-search U+F002 (ANSI-C quoting -> bytes ef 80 82; do NOT use "\uf002")
opt_query_gap()              { get_opt "@livepicker-query-gap" "2"; }               # int: spaces between the query and the first session tab while a query is active (PRD §19)
opt_overflow_left()          { get_opt "@livepicker-overflow-left" "<"; }           # left overflow indicator (presence-only; shown when @livepicker-scroll > 0)
opt_overflow_right_format()  { get_opt "@livepicker-overflow-right-format" "+%d>"; } # right overflow indicator; %d = total hidden tabs, left+right combined (PRD §19)
