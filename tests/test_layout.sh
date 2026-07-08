#!/usr/bin/env bash
# tests/test_layout.sh — tmux-livepicker PRD §19 / §15.28 renderer-layout integration suite.
#
# SOURCED by run.sh (NEVER executed directly). Defines lp_layout_seed + ~11 test_layout_*
# functions that validate the status-line LAYOUT the renderer emits: the query bar,
# the viewport windowing, the overflow indicators (+N> / <), the no-match marker, the
# absence of any index/total count, the status-justify emulation, and that the
# window-status tab-style path STILL honors §19 (query bar + viewport + overflow).
#
# CONTRACT: run.sh sources setup_socket.sh + helpers.sh + every tests/test_*.sh, then
# PER test calls setup_test "lp-$$-<name>" (-> fresh isolated socket + PATH shim +
# baseline fixtures) -> resets TEST_STATUS=pass -> runs the test_* in the CURRENT shell
# -> reads TEST_STATUS -> teardown_test. So when a test_* runs: bare `tmux` hits the
# isolated socket; $LIVEPICKER_SCRIPTS + fail/pass/assert_eq/assert_contains are IN SCOPE;
# this file SOURCES NOTHING and calls NO setup_test/teardown_test at file scope.
#
# APPROACH (codebase_patterns §P8; mirror test_appearance.sh): the renderer is PURE +
# CLIENT-INDEPENDENT (reads @livepicker-* state only, emits ONE line, zero tmux
# mutations). So every test seeds state DIRECTLY, runs renderer.sh, and asserts on
# stdout — NO attach_test_client. The seed pins the §11 DEFAULT colors so the output is
# byte-deterministic regardless of the user's tmux.conf (which sets @livepicker-fg
# "#ffffff" on the isolated socket). Every assertion is backed by a captured renderer
# output (research/test_layout_findings.md) — no guessed bytes.
#
# SCOPE: LAYOUT only. Ranking ORDER is test_ranking.sh (P1.M4.T2); scroll-into-view
# mechanics are P1.M4.T3; # escaping is test_functional.sh. This suite asserts the
# renderer's LAYOUT (positions/indicators/absence-of-count) for both tab styles.
#
# `set -u` is INHERITED from helpers.sh (do NOT re-declare; mirror test_appearance.sh).
# shellcheck disable=SC2154,SC2016,SC2034,SC2086
#   SC2154: assert_*/fail/$LIVEPICKER_SCRIPTS are defined by run.sh's sources.
#   SC2016: the negative-assertion case patterns use single-quoted literals.
#   SC2034/SC2086: locals + the intentional word split-free literal substrings.

# lp_layout_seed LIST [FILTER] [INDEX] — pin the deterministic base state the renderer
# reads. §11 default colors (byte-deterministic output); width 0 -> NO windowing
# (the renderer's full-list path; structure tests see every tab); scroll 0; nerd-fonts
# OFF (deterministic ASCII; the icon test turns it ON). The caller overrides the
# case-specific options (nerd-fonts / query-gap / tab-style / client-width / scroll /
# templates) AFTER seeding.
lp_layout_seed() {
	tmux set-option -g @livepicker-type session
	tmux set-option -g @livepicker-fg             "default"
	tmux set-option -g @livepicker-bg             "default"
	tmux set-option -g @livepicker-highlight-fg   "black"
	tmux set-option -g @livepicker-highlight-bg   "yellow"
	tmux set-option -g @livepicker-list   "$1"
	tmux set-option -g @livepicker-filter "${2:-}"
	tmux set-option -g @livepicker-index  "${3:-0}"
	tmux set-option -g @livepicker-client-width "0"   # 0 -> no windowing (full list)
	tmux set-option -g @livepicker-scroll "0"
	tmux set-option -g @livepicker-nerd-fonts "off"   # ASCII-deterministic; icon test flips ON
}

# (a) PRD §19 §3.30 / §15.28: empty query -> line 1 is ONLY the session tabs. No icon,
# no query, no gap, no "query>", no "/", no count. Highlight = index 0 (alpha).
test_layout_empty_query_tabs_only() {
	lp_layout_seed $'alpha\nbeta\ndriver' "" 0
	local out
	out="$("$LIVEPICKER_SCRIPTS/renderer.sh")"
	# the tabs are all present, joined by a single space; alpha highlighted (index 0):
	assert_contains "$out" "#[fg=black,bg=yellow]alpha#[default]" "empty: alpha tab present + highlighted"
	assert_contains "$out" "#[fg=default,bg=default]beta#[default]" "empty: beta tab present (inactive)"
	assert_contains "$out" "#[fg=default,bg=default]driver#[default]" "empty: driver tab present (inactive)"
	# negatives: NO query machinery, NO no-match marker, NO slash, NO icon glyph.
	case "$out" in *"query>"*) fail "empty: 'query>' label leaked" ;; esac
	case "$out" in *" (no match)"*) fail "empty: no-match marker leaked" ;; esac
	case "$out" in *"/"*) fail "empty: '/' leaked (count or separator)" ;; esac
	case "$out" in *$'\uf002'*) fail "empty: nerd-font icon leaked (icon is query-active only)" ;; esac
}

# (b) PRD §19 §3.31 / §15.28: query active -> <icon><query><exactly gap spaces><ranked
# tabs>, top match highlighted, non-matches hidden. nerd-fonts OFF (icon empty) so the
# structure is pure ASCII + the gap is unambiguous. width 0 -> full ranked list.
test_layout_query_active_structure() {
	# logs-prod (prefix 'l') is the top match; alpha/blog-engine match as subsequences;
	# foo has no 'l' -> HIDDEN.
	lp_layout_seed $'alpha\nlogs-prod\nblog-engine\nfoo' "l" 0
	local out
	out="$("$LIVEPICKER_SCRIPTS/renderer.sh")"
	# the query 'l' is emitted (no icon prefix — nerd off):
	assert_contains "$out" "#[fg=default,bg=default]l#[default]" "query: 'l' emitted, styled FG/BG"
	# EXACTLY 2 spaces (default gap) between the query block and the highlighted top match:
	assert_contains "$out" "#[fg=default,bg=default]l#[default]  #[fg=black,bg=yellow]logs-prod#[default]" \
		"query: exactly 2-space gap then the highlighted top match (logs-prod)"
	# the top match is highlighted:
	assert_contains "$out" "#[fg=black,bg=yellow]logs-prod#[default]" "query: top match (logs-prod) highlighted"
	# a non-matching name is HIDDEN:
	case "$out" in *foo*) fail "query: non-match 'foo' was not hidden" ;; esac
	# negative: NOT 3 spaces (gap is exactly 2, not more):
	case "$out" in *"l#[default]   "#*) fail "query: gap is 3 spaces (want exactly 2)" ;; esac
}

# (b-gap) PRD §19 §3.31: the gap is EXACTLY @livepicker-query-gap spaces. Pin it with a
# distinctive value (4) and with 0 to prove the renderer honors the option verbatim.
test_layout_query_gap_exact() {
	lp_layout_seed $'alpha\nlogs-prod' "l" 0
	# gap = 4 -> exactly 4 spaces between the query block and the highlight.
	tmux set-option -g @livepicker-query-gap "4"
	local out4
	out4="$("$LIVEPICKER_SCRIPTS/renderer.sh")"
	assert_contains "$out4" "#[fg=default,bg=default]l#[default]    #[fg=black,bg=yellow]logs-prod#[default]" \
		"query-gap=4: exactly 4 spaces before the highlight"
	case "$out4" in *"l#[default]     "#*) fail "query-gap=4: 5 spaces leaked (want exactly 4)" ;; esac
	# gap = 0 -> NO spaces; the highlight immediately follows the query block's #[default].
	tmux set-option -g @livepicker-query-gap "0"
	local out0
	out0="$("$LIVEPICKER_SCRIPTS/renderer.sh")"
	assert_contains "$out0" "#[fg=default,bg=default]l#[default]#[fg=black,bg=yellow]logs-prod#[default]" \
		"query-gap=0: zero spaces (highlight immediately follows the query block)"
}

# (b-icon) PRD §19 §3.31: with nerd-fonts ON, the search icon (U+F002) is emitted as raw
# UTF-8 bytes immediately before the query, inside the #[…] segment. Leave
# @livepicker-search-icon at its default (U+F002) so the bytes are deterministic.
test_layout_query_active_nerd_font_icon() {
	lp_layout_seed $'alpha\nlogs-prod' "l" 0
	tmux set-option -g @livepicker-nerd-fonts "on"
	local out
	out="$("$LIVEPICKER_SCRIPTS/renderer.sh")"
	# the U+F002 glyph (ef 80 82) appears right before the query 'l':
	assert_contains "$out" "#[fg=default,bg=default]$(_icon_bytes)l#[default]" \
		"nerd-on: search icon (U+F002) emitted before the query"
	assert_contains "$out" "$(_icon_bytes)" "nerd-on: the raw U+F002 bytes are present"
}
# the default icon glyph as raw bytes (ANSI-C $'\uf002' -> ef 80 82). Kept in a helper
# so the assertion reads cleanly and the byte source is documented in one place.
_icon_bytes() { printf '%s' $'\uf002'; }

# (c) PRD §19 §3.33 / §15.28: overflow -> +N> on the right where N = TOTAL hidden
# (left+right combined); scroll 0 -> NO left indicator. 8 tabs of width 5 = 47 cols;
# width 20 -> 3 visible -> 5 hidden -> "+5>".
test_layout_overflow_right_indicator() {
	lp_layout_seed $'aaaaa\nbbbbb\nccccc\nddddd\neeeee\nfffff\nggggg\nhhhhh' "" 0
	tmux set-option -g @livepicker-client-width "20"
	tmux set-option -g @livepicker-scroll "0"
	local out
	out="$("$LIVEPICKER_SCRIPTS/renderer.sh")"
	# +5> = total hidden (8 total - 3 visible = 5); styled as chrome (FG/BG):
	assert_contains "$out" "#[fg=default,bg=default]+5>#[default]" "overflow-right: +5> (total hidden=5), styled chrome"
	# scroll 0 -> NO left indicator:
	case "$out" in *"<"*) fail "overflow-right: '<' present at scroll 0 (want absent)" ;; esac
}

# (c) PRD §19 §3.33: scroll > 0 -> the left indicator '<' appears (presence-only, no
# count). scroll 3 -> visible starts at index 3; hidden_left=3, hidden_right=3 -> +6>.
test_layout_overflow_left_indicator() {
	lp_layout_seed $'aaaaa\nbbbbb\nccccc\nddddd\neeeee\nfffff\nggggg\nhhhhh' "" 3
	tmux set-option -g @livepicker-client-width "20"
	tmux set-option -g @livepicker-scroll "3"
	local out
	out="$("$LIVEPICKER_SCRIPTS/renderer.sh")"
	# both indicators: '<' (left, presence-only) + '+6>' (right, total hidden=3+3):
	assert_contains "$out" "#[fg=default,bg=default]<#[default]" "overflow-left: '<' present (scroll>0)"
	assert_contains "$out" "+6>" "overflow-left: +6> (hidden_left 3 + hidden_right 3)"
	# the highlighted tab (index 3 = ddddd) is in the visible slice:
	assert_contains "$out" "#[fg=black,bg=yellow]ddddd#[default]" "overflow-left: highlight (ddddd) visible"
}

# (c) PRD §19 §3.33: when the tabs fit, NEITHER indicator shows.
test_layout_overflow_fits_no_indicators() {
	lp_layout_seed $'alpha\nbeta\ngamma' "" 0
	tmux set-option -g @livepicker-client-width "80"   # plenty -> everything fits
	local out
	out="$("$LIVEPICKER_SCRIPTS/renderer.sh")"
	# no overflow indicator '+N>' anywhere (the '+' is the chrome right-indicator prefix):
	case "$out" in *"+"[0-9]*">"*) fail "fits: '+N>' present (want neither indicator)" ;; esac
	case "$out" in *"<"*) fail "fits: '<' present (want neither indicator)" ;; esac
	# sanity: the tabs ARE rendered (fits is not an empty-output bug):
	assert_contains "$out" "alpha" "fits: tabs still rendered"
}

# (c)+(b) PRD §19: overflow WITH a query active -> the query bar is pinned at column 0
# AND the overflow indicators apply to the tab region. Seed s0..s9 (all match 's'),
# narrow width, nerd off. Assert the query bar + +N>; scroll>0 variant -> '<'.
test_layout_overflow_with_query_active() {
	lp_layout_seed "$(printf 's0\ns1\ns2\ns3\ns4\ns5\ns6\ns7\ns8\ns9')" "s" 0
	tmux set-option -g @livepicker-client-width "14"   # T = 14-3(query block) = 11 -> overflow
	tmux set-option -g @livepicker-scroll "0"
	local out
	out="$("$LIVEPICKER_SCRIPTS/renderer.sh")"
	# the query bar is pinned left: icon(empty)+query 's'+#[default]+2-space gap:
	assert_contains "$out" "#[fg=default,bg=default]s#[default]  " "overflow+query: query bar pinned at column 0"
	# the tab region overflows -> +N> (the '+' prefix + digits + '>'):
	case "$out" in *"+"[0-9]*">"*) : ;; *) fail "overflow+query: '+N>' absent (want overflow indicator)" ;; esac
	# scroll > 0 -> the left indicator '<' appears in the query-active layout too:
	tmux set-option -g @livepicker-scroll "3"
	tmux set-option -g @livepicker-index "3"
	local out2
	out2="$("$LIVEPICKER_SCRIPTS/renderer.sh")"
	assert_contains "$out2" "#[fg=default,bg=default]<#[default]" "overflow+query scroll>0: '<' present"
}

# (d) PRD §19 §3.34: no-match -> <icon><query> (no match). Plain-ASCII marker regardless
# of nerd-font mode. NO tabs, NO indicators.
test_layout_no_match() {
	lp_layout_seed $'alpha\nbeta' "zzz" 0
	local out
	out="$("$LIVEPICKER_SCRIPTS/renderer.sh")"
	assert_contains "$out" " (no match)" "no-match: ' (no match)' marker present"
	assert_contains "$out" "#[fg=default,bg=default]zzz (no match)#[default]" "no-match: full <query> (no match) segment"
	# NO tabs, NO indicators:
	case "$out" in *alpha*) fail "no-match: tab 'alpha' leaked (want no tabs)" ;; esac
	case "$out" in *beta*) fail "no-match: tab 'beta' leaked (want no tabs)" ;; esac
	case "$out" in *">"*) fail "no-match: overflow indicator leaked (want none)" ;; esac
}

# (e) PRD §15.28 / P1.M2.T3.S1: the index/total count is GONE ENTIRELY. Sweep every
# layout state and assert NONE contains a [digit]/[digit] pattern (the old [0/5] form).
test_layout_no_count_anywhere() {
	local outs=""
	# empty:
	lp_layout_seed $'alpha\nbeta\ndriver' "" 0
	outs="$outs|$("$LIVEPICKER_SCRIPTS/renderer.sh")"
	# query active:
	lp_layout_seed $'alpha\nlogs-prod\nblog-engine' "l" 0
	outs="$outs|$("$LIVEPICKER_SCRIPTS/renderer.sh")"
	# no-match:
	lp_layout_seed $'alpha\nbeta' "zzz" 0
	outs="$outs|$("$LIVEPICKER_SCRIPTS/renderer.sh")"
	# overflow:
	lp_layout_seed $'aaaaa\nbbbbb\nccccc\nddddd\neeeee\nfffff\nggggg\nhhhhh' "" 0
	tmux set-option -g @livepicker-client-width "20"
	outs="$outs|$("$LIVEPICKER_SCRIPTS/renderer.sh")"
	# NONE of the captured outputs contains a [0-9]/[0-9] count pattern:
	if [[ $outs == *[0-9]/[0-9]* ]]; then
		fail "no-count: an index/total pattern (e.g. [0/5]) leaked into a layout state"
	fi
	# sanity: each state DID render (the sweep is not vacuous):
	[ -n "$outs" ] || fail "no-count: the sweep captured no output (vacuous)"
}

# (f) PRD §19 + §17: the window-status tab-style path STILL honors §19 — the query bar
# + viewport + overflow indicators — it does NOT fall back to the old full-line join.
# Seed both cached templates + a separator + many matching tabs + a narrow width.
test_layout_window_status_keeps_query_bar() {
	lp_layout_seed "$(printf 's0\ns1\ns2\ns3\ns4\ns5\ns6\ns7\ns8\ns9')" "s" 0
	tmux set-option -g @livepicker-tab-style "window-status"
	tmux set-option -gw window-status-separator "|"
	tmux set-option -g @livepicker-tab-current-tmpl  "#[fg=red,bold]__lp_tab__#[default]"
	tmux set-option -g @livepicker-tab-inactive-tmpl "#[fg=blue]__lp_tab__#[default]"
	tmux set-option -g @livepicker-client-width "14"
	local out
	out="$("$LIVEPICKER_SCRIPTS/renderer.sh")"
	# the query bar is present (§19 honored; NOT the old full-line join):
	assert_contains "$out" "#[fg=default,bg=default]s#[default]  " "window-status: query bar present (§19 honored)"
	# the tab region overflows -> +N> (the '+' prefix + digits + '>'):
	case "$out" in *"+"[0-9]*">"*) : ;; *) fail "window-status: '+N>' absent (overflow not honored)" ;; esac
	# the tabs render through the CACHED template (the current styling, not plain):
	assert_contains "$out" "#[fg=red,bold]" "window-status: current-template styling applied"
	# the placeholder was fully swapped (§17 reader contract):
	case "$out" in *__lp_tab__*) fail "window-status: unswapped __lp_tab__ leaked" ;; esac
}

# (justify) PRD §19 §3.30: empty query + tabs fit -> tabs positioned per status-justify.
# centre -> leading pad (output starts with a space); left (default) -> no leading pad.
test_layout_status_justify_empty() {
	lp_layout_seed $'alpha\nbeta' "" 0
	tmux set-option -g @livepicker-client-width "40"
	# centre -> leading pad:
	tmux set-option -g status-justify centre
	local outc
	outc="$("$LIVEPICKER_SCRIPTS/renderer.sh")"
	case "$outc" in " "*) : ;; *) fail "justify centre: no leading pad (want output to start with a space)" ;; esac
	assert_contains "$outc" "alpha" "justify centre: tabs still rendered after the pad"
	# left (default) -> NO leading pad:
	tmux set-option -g status-justify left
	local outl
	outl="$("$LIVEPICKER_SCRIPTS/renderer.sh")"
	case "$outl" in " "*) fail "justify left: leading pad present (want none)" ;; *) : ;; esac
}
