#!/usr/bin/env bash
# shellcheck disable=SC1091,SC2034
#   SC1091: this is a SOURCED library; callers source it via $CURRENT_DIR.
#   SC2034: CURRENT_DIR is the house resolver var (matches rank.sh/state.sh); the
#           sourced-library contract (codebase_patterns.md §P1) keeps it even though
#           layout.sh only defines functions — siblings read it when sourced together.
# scripts/layout.sh — tmux-livepicker shared display-width + viewport math (PRD §19/§16).
#
# Sourced library (NOT executed). NO source-time side effects — sourcing defines
# _lp_strip_styles, lp_disp_width, lp_viewport (+ LPV_* output globals) and nothing else.
# Sourced by BOTH renderer.sh (P1.M2, to slice the visible window) and input-handler.sh
# (P1.M3, to scroll-into-view) so the measurement CANNOT disagree between them
# (PRD §16 "Viewport measurement").
#
# PURE bash: NO tmux calls, NO subshells on the measurement path (the renderer runs this
# per-tab per-redraw — §18 budget). NO get_state/opt_* reads — the caller passes T,
# scroll, highlight, and the separator width as args; lp_viewport returns numbers via the
# LPV_* globals. This keeps the lib unit-testable and free of the indicator-presence
# circular dependency (the renderer resolves that — research FINDING 5).
#
# LOAD-BEARING RULES (research/layout_viewport_findings.md):
#  - DO NOT use `wc -m` for width — it is LOCALE-DEPENDENT (C locale counts BYTES, so the
#    3-byte nerd-font icon measures as width 3 — WRONG) AND spawns a subshell per call.
#    USE bash's `${#var}` (builtin, codepoints under a UTF-8 locale — the nerd-font use
#    case guarantees UTF-8). (FINDING 1)
#  - DO NOT use the naive glob strip `${var//\#\[[^]]*\]/}` — bash param expansion uses
#    GLOB patterns (`*` is a wildcard, not a quantifier), so it greedily eats from the
#    first #[ to the last ], INCLUDING visible text. USE the manual case-loop below.
#    (FINDING 2)
#  - #[…] style directives are zero-width but inflate the raw string; strip FIRST, then
#    count codepoints. The nerd-font icon U+F002 is 1 codepoint → width 1 (PRD §19
#    assumption). Wide CJK/emoji glyphs (width 2) are undercounted — a documented
#    limitation (session names are typically ASCII; out of scope for §19). (FINDING 3)
#  - The inter-tab separator counts: cumwidth includes (count)*SEP between tabs. SEP
#    defaults to 1 (plain-mode space); the window-status caller passes len(separator).
#  - LPV_END = -1 signals an EMPTY slice (n=0 or T<=0); callers loop
#    `for ((i=LPV_START; i<=LPV_END; i++))` (a no-op when END<START).

set -u   # NOT -e (the strip loop's case + param expansions are control flow); NOT -o pipefail.

CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# _LP_MEASURED — set by _lp_measure_into to the stripped codepoint width. A FORK-FREE
# out-param so the per-tab hot loops (lp_viewport's measure pass + the renderer's
# indicator/justify measurements) avoid the $(…) capture fork that lp_disp_width
# historically incurred. Measured cost of that fork: ~1ms/tab; lp_viewport runs once
# per renderer redraw AND once per input-handler scroll-into-view, and the renderer
# is re-evaluated on EVERY status refresh — so per-tab subshells dominated the
# viewport cost (~15ms/call). Eliminating them is the single biggest renderer win.
_LP_MEASURED=0

# _lp_measure_into STRING — set the global _LP_MEASURED to STRING's display-column
# count: strip #[…] style runs (manual case-loop — NOT a glob/regex strip; bash param-
# expansion globs can't express "#[ run of non-] chars ]" without eating visible text,
# research FINDING 2), then count codepoints via ${#var} (builtin; codepoints under a
# UTF-8 locale — FINDING 1; NOT wc -m, which is locale-dependent + subshells). Pure
# bash, NO subshell, NO printf — call it directly in hot loops. Returns the width via
# the _LP_MEASURED global (mirrors the LPV_* out-global convention in this file).
_lp_measure_into() {
	local in="${1:-}" out=""
	while :; do
		case "$in" in
			*"#["*)
				# text before the first #[, then drop through the #[...] run (up to next ]).
				out="$out${in%%\#[*}"
				in="${in#*]}"
				;;
			*)
				out="$out$in"
				break
				;;
		esac
	done
	_LP_MEASURED=${#out}
}

# lp_disp_width STRING — print the integer display-column count (legacy contract for
# callers that capture via $(…)). Implemented on the fork-free _lp_measure_into helper.
# HOT loops should call _lp_measure_into directly and read $_LP_MEASURED to avoid the
# command-substitution fork this wrapper still incurs.
lp_disp_width() {
	_lp_measure_into "${1:-}"
	printf '%s' "$_LP_MEASURED"
}

# LPV_* — lp_viewport outputs (set each call; documented namespaced globals).
LPV_SCROLL=0       # the (possibly advanced/clamped) first-visible index — caller writes this to @livepicker-scroll
LPV_START=0        # first visible tab index (== LPV_SCROLL)
LPV_END=-1         # last visible tab index (-1 = empty slice; loop `for ((i=START;i<=END;i++))`)
LPV_HIDDEN_LEFT=0  # tabs hidden to the left (== scroll; drives the `<` indicator)
LPV_HIDDEN_RIGHT=0 # tabs hidden to the right (drives the +%d> indicator; %d = LEFT+RIGHT)

# lp_viewport RANKED_LIST T SCROLL HIGHLIGHT [SEP_WIDTH]
#   RANKED_LIST: newline-separated ranked tab strings (lp_rank / lp_build_filtered output).
#   T: available tab width in columns (CALLER computes client_width − query_block − indicator
#      budget; layout.sh does NOT resolve the indicator circle — research FINDING 5).
#   SCROLL: current first-visible index (0-based; the @livepicker-scroll state).
#   HIGHLIGHT: current highlight index (0-based; the @livepicker-index state).
#   SEP_WIDTH: inter-tab separator columns (default 1 = plain-mode space; window-status
#      caller passes len(window-status-separator)).
#   Sets LPV_SCROLL/START/END/HIDDEN_LEFT/HIDDEN_RIGHT. Pure math; no tmux; no state reads.
#   Algorithm (PRD §19 §3.32/§3.33; research FINDING 4 — all cases verified):
#     1. total = sum(tab widths) + (n-1)*SEP. If total <= T: clamp scroll=0, all visible.
#     2. else scroll-into-view: if HIGHLIGHT<SCROLL, scroll=HIGHLIGHT; then advance scroll
#        while cumwidth(scroll,highlight) > T (so the highlight tab is always visible).
#     3. end = largest idx>=scroll with cumwidth(scroll,end) <= T.
#     4. hidden_left=scroll; hidden_right=n-1-end (their sum is the +%d> %d).
lp_viewport() {
	local list="${1:-}" T="${2:-0}" scroll="${3:-0}" hl="${4:-0}" sep="${5:-1}"
	local -a tabs=()
	mapfile -t tabs < <(printf '%s' "$list")
	local n="${#tabs[@]}"

	# Reset outputs (empty-slice defaults; END=-1 => caller's loop is a no-op).
	LPV_SCROLL=0; LPV_START=0; LPV_END=-1; LPV_HIDDEN_LEFT=0; LPV_HIDDEN_RIGHT=0
	[ "$n" -eq 0 ] && return 0
	# T<=0 (no room for any tab): nothing visible; all hidden to the left conceptually.
	if [ "$T" -le 0 ]; then LPV_HIDDEN_LEFT="$n"; LPV_HIDDEN_RIGHT=0; LPV_START=0; LPV_END=-1; return 0; fi

	# Sanitize the STRING state inputs to [0, n-1] (mirror rank.sh's regex-guard idiom).
	[[ "$scroll" =~ ^[0-9]+$ ]] || scroll=0
	[[ "$hl" =~ ^[0-9]+$ ]] || hl=0
	[ "$scroll" -ge "$n" ] && scroll=$((n - 1))
	[ "$hl" -ge "$n" ] && hl=$((n - 1))
	[ "$scroll" -lt 0 ] && scroll=0
	[ "$hl" -lt 0 ] && hl=0

	# Measure each tab width once; accumulate the total (with separators). FORK-FREE:
	# _lp_measure_into sets _LP_MEASURED directly (no $(…) per tab — that subshell was
	# the dominant viewport cost; ~1ms/tab × N tabs per lp_viewport call).
	local -a w=()
	local i=0 total=0
	for ((i = 0; i < n; i++)); do
		_lp_measure_into "${tabs[i]}"
		w[i]="$_LP_MEASURED"
		total=$((total + w[i]))
	done
	total=$((total + (n - 1) * sep))

	# Whole list fits -> clamp scroll=0, all visible (PRD §3.32 "clamp scroll=0 when fits").
	if [ "$total" -le "$T" ]; then
		LPV_SCROLL=0; LPV_START=0; LPV_END=$((n - 1)); LPV_HIDDEN_LEFT=0; LPV_HIDDEN_RIGHT=0
		return 0
	fi

	# --- overflow: scroll-into-view (PRD §3.32) ---
	# (a) if the highlight is left of scroll, snap scroll to it.
	[ "$hl" -lt "$scroll" ] && scroll="$hl"

	# (b) advance scroll until the highlight tab fits: cumwidth(scroll,hl) <= T.
	#     cumwidth(a,b) = w[a] + sep+w[a+1] + ... + sep+w[b]. Incremental on scroll++:
	#     cw -= w[scroll] + sep (the leftmost tab + its trailing separator). O(n) total.
	local k cw=0
	for ((k = scroll; k <= hl; k++)); do
		[ "$k" -gt "$scroll" ] && cw=$((cw + sep))
		cw=$((cw + w[k]))
	done
	while [ "$scroll" -lt "$hl" ] && [ "$cw" -gt "$T" ]; do
		cw=$((cw - w[scroll] - sep))
		scroll=$((scroll + 1))
	done

	# --- find end: largest idx>=scroll with cumwidth(scroll,end) <= T (forward scan) ---
	local end=$scroll
	cw=${w[$scroll]}
	while [ $((end + 1)) -lt "$n" ]; do
		local nxt
		nxt=$((cw + sep + w[end + 1]))
		[ "$nxt" -gt "$T" ] && break
		cw=$nxt
		end=$((end + 1))
	done

	LPV_SCROLL="$scroll"
	LPV_START="$scroll"
	LPV_END="$end"
	LPV_HIDDEN_LEFT="$scroll"
	LPV_HIDDEN_RIGHT=$((n - 1 - end))
}
