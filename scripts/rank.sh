#!/usr/bin/env bash
# shellcheck disable=SC1091,SC2034
#   SC1091: this is a SOURCED library; callers source it via $CURRENT_DIR.
#   SC2034: CURRENT_DIR is the house resolver var (matches renderer.sh/state.sh);
#           sourced-library contract (§P1) keeps it even though rank.sh itself
#           only defines lp_rank — siblings read it when sourced together.
# scripts/rank.sh — tmux-livepicker shared fuzzy ranker (PRD §20).
#
# Sourced library (NOT executed). NO source-time side effects — sourcing defines
# lp_rank (+ LP_* constants) and nothing else. Supersedes filter.sh::lp_build_filtered
# (case-insensitive substring) with a subsequence match + integer score. SAME call
# convention, so callers swap `lp_build_filtered` -> `lp_rank` verbatim:
#     mapfile -t ranked < <(lp_rank "$LIST" "$FILTER")
#
# CONTRACT (PRD §20):
#  - Match (§3.36): every FILTER char appears in the name IN ORDER, case-insensitively
#    (subsequence, not contiguous). Non-matches HIDDEN (so create-on-empty fires).
#  - Score (§3.37, higher=better; ranked[0] = top match = preview target):
#       PREFIX bonus > WORD-BOUNDARY bonus > CONTIGUITY bonus > POSITION penalty.
#       Stable tie-break on ORIGINAL tmux order (equal scores NOT reordered).
#  - Empty FILTER (§3.38): ALL names at score 0, ORIGINAL order — BYTE-IDENTICAL to
#    lp_build_filtered's empty-filter output (keeps existing tests green).
#  - Empty LIST: prints nothing.
#
# PERF (§3.40 / §18 budget): O(N·Q) pure bash, NO per-name subshell, source-once.
# Constants are illustrative (PRD: "not load-bearing; do not over-tune").

set -u   # NOT -e; NOT -o pipefail.

CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Scoring constants (integers; magnitudes chosen so the ordering is unambiguous).
readonly LP_PREFIX_BONUS=1000         # first query char matches at name position 0
readonly LP_WORD_BOUNDARY_BONUS=100   # per matched char at a word boundary
readonly LP_CONTIGUITY_BONUS=10       # per matched char immediately after the prev matched
# position penalty = the first matched char's index (1/unit; small)

# lp_rank LIST FILTER
#   Print each name from LIST (newline-separated) that subsequence-matches FILTER
#   (case-insensitive, in-order), BEST score first, one per line, PRESERVING case.
#   Empty FILTER -> all names, original order (score 0). Empty LIST -> nothing.
lp_rank() {
	local LIST="${1:-}"
	local FILTER="${2:-}"
	local -a all=()
	# printf '%s' (NO trailing newline): empty LIST -> all=() (NOT [""]); a trailing
	# newline in LIST is harmless (mapfile -t strips it). Mirrors filter.sh so the
	# empty/blank cases are byte-identical.
	mapfile -t all < <(printf '%s' "$LIST")

	local low_filter="${FILTER,,}"

	# EMPTY FILTER (§3.38): all names at score 0, ORIGINAL order, no reorder.
	# Byte-identical to lp_build_filtered's empty-filter path — CRITICAL for tests.
	if [ -z "$low_filter" ]; then
		local _n
		for _n in "${all[@]}"; do
			printf '%s\n' "$_n"
		done
		return 0
	fi

	local qlen=${#low_filter}
	# Per-name accumulators. Array index == original tmux order (mapfile preserves
	# LIST order) => that index is the stable tie-break key.
	local -a r_name=()
	local -a r_score=()
	# per-name scratch (declared once, reset each iteration):
	local name low_name nlen qi ni qc found matched score j p prevc curc prevp
	local -a pos=()

	for name in "${all[@]}"; do
		low_name="${name,,}"
		nlen=${#low_name}
		# Quick reject: a name shorter than the query cannot be a subsequence match.
		[ "$nlen" -lt "$qlen" ] && continue

		# --- subsequence walk (§3.36): find each query char at/after ni, in order ---
		qi=0
		ni=0
		matched=1
		pos=()
		while [ "$qi" -lt "$qlen" ]; do
			qc="${low_filter:$qi:1}"
			found=-1
			while [ "$ni" -lt "$nlen" ]; do
				if [ "${low_name:$ni:1}" = "$qc" ]; then
					found=$ni
					break
				fi
				ni=$((ni + 1))
			done
			if [ "$found" -lt 0 ]; then
				matched=0
				break
			fi
			pos+=("$found")
			ni=$((found + 1))
			qi=$((qi + 1))
		done
		[ "$matched" -eq 1 ] || continue   # non-match -> HIDDEN (create-on-empty fires)

		# --- score (§3.37) ---
		score=0
		# PREFIX: first query char at name position 0.
		[ "${pos[0]}" -eq 0 ] && score=$((score + LP_PREFIX_BONUS))
		# Per matched char: word-boundary + contiguity.
		prevp=-1
		j=0
		for p in "${pos[@]}"; do
			# word boundary: pos 0 | after a separator [-_. /] | camelCase (lower->UPPER)
			if [ "$p" -eq 0 ]; then
				score=$((score + LP_WORD_BOUNDARY_BONUS))
			else
				prevc="${name:$((p - 1)):1}"   # ORIGINAL case (camelCase needs it)
				case "$prevc" in
					# PRD §3.37 separator set: dash, underscore, dot, SPACE, slash.
					# [:space:] covers the space (a literal space inside a case-glob
					# bracket breaks bash's case tokenizer); tab/newline are also valid breaks.
					[-_.[:space:]/])
						score=$((score + LP_WORD_BOUNDARY_BONUS))
						;;
					*)
						curc="${name:$p:1}"
						# camelCase boundary: prev lowercase, current uppercase.
						if [[ "$prevc" == [a-z] && "$curc" == [A-Z] ]]; then
							score=$((score + LP_WORD_BOUNDARY_BONUS))
						fi
						;;
				esac
			fi
			# contiguity: this matched char immediately follows the previous matched.
			if [ "$j" -gt 0 ] && [ "$p" -eq $((prevp + 1)) ]; then
				score=$((score + LP_CONTIGUITY_BONUS))
			fi
			prevp=$p
			j=$((j + 1))
		done
		# position penalty: proportional to the match's start offset (small).
		score=$((score - pos[0]))

		r_name+=("$name")
		r_score+=("$score")
	done

	# --- stable sort by score DESCENDING (equal scores keep original order) ---
	# Pure-bash selection sort: advance `best` ONLY on strictly-greater score, so the
	# earlier original index wins ties (stable). O(M^2), M = match count (small <100).
	local m=${#r_name[@]}
	if [ "$m" -eq 0 ]; then
		return 0   # no matches -> print nothing (caller sees an empty ranked list)
	fi
	local -a taken=()
	local r k best best_score
	r=0
	while [ "$r" -lt "$m" ]; do taken[r]=0; r=$((r + 1)); done
	r=0
	while [ "$r" -lt "$m" ]; do
		best=-1
		k=0
		while [ "$k" -lt "$m" ]; do
			if [ "${taken[$k]}" -ne 1 ]; then
				if [ "$best" -lt 0 ] || [ "${r_score[$k]}" -gt "$best_score" ]; then
					best=$k
					best_score="${r_score[$k]}"
				fi
			fi
			k=$((k + 1))
		done
		taken[best]=1
		printf '%s\n' "${r_name[$best]}"
		r=$((r + 1))
	done
}
