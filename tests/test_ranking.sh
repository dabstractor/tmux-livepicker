#!/usr/bin/env bash
# shellcheck disable=SC2154,SC2016,SC2034,SC2086
#   SC2154: TEST_STATUS / fail / assert_* / setup_test / tmux / LIVEPICKER_SCRIPTS
#           are provided by run.sh + helpers.sh + setup_socket.sh (sourced before
#           this file by run.sh). SC2016/SC2034/SC2086: the harness's eval/single-
#           quote + word-split idioms (mirrors test_appearance.sh / test_layout.sh).
# tests/test_ranking.sh — tmux-livepicker fuzzy-ranking validation suite (PRD §20,
# §15.28). Validates scripts/rank.sh::lp_rank: (a) prefix>subsequence, (b) hidden,
# (c) empty-filter order, (d) no-drift (renderer/nav/confirm share lp_rank), (e)
# perf (O(N*Q), no per-name subshell). lp_rank is a PURE leaf function (sources
# nothing, calls no tmux) -> the pure tests source rank.sh and call lp_rank directly
# (NO socket); only the no-drift integration test runs renderer.sh (renderer-seed
# idiom). See research/test_ranking_findings.md for the captured outputs behind
# every assertion.

set -u   # NOT -e (tmux/grep legitimately return nonzero); NOT -o pipefail.

# Source the function under test ONCE (guarded: rank.sh defines LP_* as readonly;
# an unguarded re-source would error). $LIVEPICKER_SCRIPTS is exported by
# setup_socket.sh, which run.sh sources before the test files. SC1091: the source
# path is dynamic ($LIVEPICKER_SCRIPTS) so shellcheck cannot follow it (mirror of
# run.sh's `# shellcheck source=/dev/null` on its test_*.sh glob loop).
# shellcheck disable=SC1091
command -v lp_rank >/dev/null 2>&1 || source "$LIVEPICKER_SCRIPTS/rank.sh"

# lp_ranking_seed LIST [FILTER] [INDEX] — pin the §11 defaults so renderer-seed
# assertions are deterministic (highlight token == #[fg=black,bg=yellow]<name>#[default]).
# client-width 0 -> renderer renders the FULL ranked list (no viewport windowing).
# Mirrors the sibling test_layout.sh::lp_layout_seed.
lp_ranking_seed() {
	local list="${1:-}" filter="${2:-}" index="${3:-0}"
	tmux set-option -g @livepicker-fg default
	tmux set-option -g @livepicker-bg default
	tmux set-option -g @livepicker-highlight-fg black
	tmux set-option -g @livepicker-highlight-bg yellow
	tmux set-option -g @livepicker-nerd-fonts off        # clean ASCII (no U+F002 icon bytes)
	tmux set-option -g @livepicker-tab-style plain
	tmux set-option -g @livepicker-query-gap 2
	tmux set-option -g @livepicker-type session
	tmux set-option -g @livepicker-client-width 0        # width 0 -> full list, no viewport windowing
	tmux set-option -g @livepicker-scroll 0
	tmux set-option -g @livepicker-list "$list"
	tmux set-option -g @livepicker-filter "$filter"
	tmux set-option -g @livepicker-index "$index"
}

# (a) PRD §3.37: prefix bonus (1000) beats a deep subsequence. logs-prod (pos0,
# score 1120) ranks above blog-engine (pos1, score 19) and alog (pos1, score 19).
# blog-engine before alog: stable tie-break keeps original tmux order (score 19==19).
test_ranking_prefix_beats_subsequence() {
	local LIST=$'blog-engine\nlogs-prod\nalog'
	local out first
	out="$(lp_rank "$LIST" 'log')"
	first="$(printf '%s\n' "$out" | head -1)"
	assert_eq "$first" 'logs-prod' "(a) prefix bonus ranks logs-prod first"
	assert_eq "$out" $'logs-prod\nblog-engine\nalog' "(a) full ranked order (stable tie at score 19)"
}

# (b) PRD §3.36: a non-subsequence is HIDDEN entirely (so create-on-empty fires).
# 'xyz' has no 'l' -> not a subsequence of 'log' -> absent from output.
test_ranking_non_subsequence_hidden() {
	local LIST=$'blog-engine\nlogs-prod\nalog\nxyz'
	local out cnt
	out="$(lp_rank "$LIST" 'log')"
	cnt="$(printf '%s\n' "$out" | grep -c '^xyz$')"
	assert_eq "$cnt" '0' "(b) non-subsequence 'xyz' hidden (grep count == 0)"
	assert_eq "$out" $'logs-prod\nblog-engine\nalog' "(b) the 3 matches intact + ranked"
}

# (c) PRD §3.38 + §2 non-goal: empty FILTER -> ALL names at score 0 in ORIGINAL
# tmux order (no reordering; no MRU). Byte-identical to LIST after $() normalization.
test_ranking_empty_filter_preserves_order() {
	local LIST=$'gamma\nalpha\nbeta'
	local out
	out="$(lp_rank "$LIST" '')"
	assert_eq "$out" "$LIST" "(c) empty filter byte-identical to LIST (original order preserved)"
	# diff form (belt-and-braces): left re-terminates LIST; right is lp_rank's terminated output.
	diff <(printf '%s\n' "$LIST") <(lp_rank "$LIST" '') >/dev/null \
		|| fail "(c) diff not clean (empty filter reordered the list)"
	pass "(c) diff clean"
}

# (d1) STRUCTURAL no-drift: every consumer calls lp_rank (single source of truth),
# not a re-implementation. renderer.sh + input-handler.sh (next/prev/confirm/sync).
test_ranking_no_drift_consumers_share_source() {
	grep -q 'lp_rank' "$LIVEPICKER_SCRIPTS/renderer.sh" \
		|| fail "no-drift: renderer.sh does not call lp_rank (re-implemented filter?)"
	grep -q 'lp_rank' "$LIVEPICKER_SCRIPTS/input-handler.sh" \
		|| fail "no-drift: input-handler.sh does not call lp_rank (nav/confirm diverge?)"
	pass "no-drift: renderer + nav/confirm/prev/sync share lp_rank (PRD §20 single source of truth)"
}

# (d2) DETERMINISM no-drift: lp_rank is a pure function -> identical input gives
# identical output, so the renderer's ranked == nav's ranked == confirm's ranked.
test_ranking_no_drift_deterministic() {
	local LIST=$'blog-engine\nlogs-prod\nalog'
	local a b
	a="$(lp_rank "$LIST" 'log')"
	b="$(lp_rank "$LIST" 'log')"
	assert_eq "$a" "$b" "no-drift: lp_rank deterministic (two calls byte-identical)"
}

# (d3) INTEGRATION no-drift: the renderer's VISIBLE highlight == lp_rank's ranked[IDX]
# (what the user sees == what confirm targets == what next-session moves to). Uses the
# renderer-seed idiom (setup_test brought up the isolated socket). IDX=0 -> ranked[0];
# IDX=1 (next-session moved) -> ranked[1] (same ranked array, no drift).
test_ranking_no_drift_renderer_highlight() {
	local LIST=$'blog-engine\nlogs-prod\nalog'
	local -a ranked
	local raw0 raw1
	mapfile -t ranked < <(lp_rank "$LIST" 'log')   # canonical: single source of truth
	# IDX=0: renderer highlights ranked[0] (== confirm target).
	lp_ranking_seed "$LIST" 'log' 0
	raw0="$(bash "$LIVEPICKER_SCRIPTS/renderer.sh")"
	assert_contains "$raw0" "#[fg=black,bg=yellow]${ranked[0]}#[default]" \
		"no-drift: renderer highlights ranked[0] (${ranked[0]}) == lp_rank top / confirm target"
	# IDX=1 (next-session moved the index): renderer highlights ranked[1] (same array).
	lp_ranking_seed "$LIST" 'log' 1
	raw1="$(bash "$LIVEPICKER_SCRIPTS/renderer.sh")"
	assert_contains "$raw1" "#[fg=black,bg=yellow]${ranked[1]}#[default]" \
		"no-drift: renderer highlights ranked[1] (${ranked[1]}) after index move (== next-session)"
}

# (e) PERF: O(N*Q) pure bash, NO per-name subshell. The HARD guard is a source grep
# (machine-independent): the lp_rank FUNCTION BODY has NO command substitution (only
# $(( arithmetic + ${} expansion + <() process sub). Timing is secondary + generous
# (research FINDING 5: the <50ms claim is the O(N*Q) matching loop, NOT the O(M^2)
# sort — all-300-match is ~480ms BY DESIGN; so we use a FEW-match fixture).
test_ranking_perf_no_per_name_subshell() {
	local rank="$LIVEPICKER_SCRIPTS/rank.sh"
	# HARD invariant: extract the lp_rank body; assert NO '$(' non-arithmetic inside.
	local body bad
	body="$(sed -n '/^lp_rank()/,/^}$/p' "$rank")"
	bad="$(printf '%s' "$body" | grep -nE '\$\([^(]' || true)"   # excludes '$((' arithmetic
	[ -z "$bad" ] || fail "perf: lp_rank body has command substitution (per-name subshell?): $bad"
	pass "perf: no command substitution in lp_rank body (hard invariant — O(N*Q), no per-name subshell)"
	# TIMING: 300 names, few-match filter (s99 -> 3 matches) measures O(N*Q), not O(M^2).
	local big m t0 t1 ms run best
	big="$(seq -f 'sess-%g' 1 300)"                # 300 distinct names (one process)
	m="$(lp_rank "$big" 's99' | grep -c .)"
	assert_eq "$m" '3' "perf fixture: 's99' matches exactly 3 of 300 (few-match -> measures O(N*Q))"
	if date +%s%N >/dev/null 2>&1; then
		best=999999
		for run in 1 2 3 4 5; do
			t0=$(date +%s%N); lp_rank "$big" 's99' >/dev/null; t1=$(date +%s%N)
			ms=$(( (t1 - t0) / 1000000 )); [ "$ms" -lt "$best" ] && best=$ms
		done
		pass "perf: lp_rank(300, few-match) min ${best}ms (generous bound 200ms)"
		[ "$best" -lt 200 ] || fail "perf: lp_rank(300,few-match) took ${best}ms (want <200; subshell regression?)"
	else
		pass "perf: date +%s%N unavailable here; the grep invariant above is the hard guard"
	fi
}

# --- cheap §15.28 edge coverage (pure lp_rank, no socket) ---

# Stable tie-break (PRD §3.37): equal scores keep ORIGINAL tmux order. aaa-mlog and
# bbb-mlog both match 'mlog' at pos[0]=4 (identical score) -> input order preserved.
test_ranking_stable_tiebreak() {
	local LIST=$'aaa-mlog\nbbb-mlog'
	local out
	out="$(lp_rank "$LIST" 'mlog')"
	assert_eq "$out" "$LIST" "stable tie-break: equal scores keep original tmux order"
}

# Case-insensitive match (PRD §3.36); ORIGINAL case preserved in output (low_name is
# used only for matching/scoring; the printed token is the original name).
test_ranking_case_insensitive_preserves_case() {
	local out
	out="$(lp_rank 'LOGS-Prod' 'log')"
	assert_eq "$out" 'LOGS-Prod' "case-insensitive match; original case preserved in output"
}

# Empty LIST -> empty output (rank.sh: m==0 -> return 0, prints nothing).
test_ranking_empty_list_outputs_nothing() {
	local out
	out="$(lp_rank '' 'x')"
	[ -z "$out" ] || fail "empty LIST + filter 'x' should produce no output (got [$out])"
	out="$(lp_rank '' '')"
	[ -z "$out" ] || fail "empty LIST + empty filter should produce no output (got [$out])"
	pass "empty LIST -> empty output (both filter and empty-filter paths)"
}

# Quick reject (rank.sh): a name shorter than the query cannot be a subsequence.
test_ranking_quick_reject_short_name() {
	local out cnt
	out="$(lp_rank 'ab' 'abc')"
	cnt="$(printf '%s\n' "$out" | grep -c '^ab$')"
	assert_eq "$cnt" '0' "name shorter than query is hidden (quick-reject nlen<qlen)"
}

# Word-boundary bonus (PRD §3.37): a match right after a separator (-_. /) scores
# higher than a deep subsequence. 'my-log' (boundary after '-') ranks above 'xlog'.
test_ranking_word_boundary_ordering() {
	local LIST=$'my-log\nxlog'
	local out first
	out="$(lp_rank "$LIST" 'log')"
	first="$(printf '%s\n' "$out" | head -1)"
	assert_eq "$first" 'my-log' "word-boundary (after '-') ranks my-log above xlog"
}
