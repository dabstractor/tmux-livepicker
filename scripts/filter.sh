#!/usr/bin/env bash
# shellcheck disable=SC1091
#   SC1091: this is a SOURCED library; callers source it via $CURRENT_DIR.
# scripts/filter.sh — tmux-livepicker shared filtered-list builder.
#
# Sourced library (NOT executed). NO source-time side effects — sourcing this
# file defines lp_build_filtered and nothing else (no driver, no *_main call).
# Consumed by BOTH:
#   - scripts/renderer.sh   (the #() status filter+highlight view), and
#   - scripts/input-handler.sh (nav's filtered[index] resolution + length L)
# so there is EXACTLY ONE filter in the repo (PRD §6 + work-item CONTRACT
# point 1: "share a single filter function ... to avoid drift"). The algorithm
# is byte-identical to what renderer.sh used inline (research FINDING 2/3).

set -u   # NOT -e; NOT -o pipefail.

# lp_build_filtered LIST FILTER
#   Print each name from LIST (newline-separated) that case-insensitively
#   contains FILTER (substring), one per line, PRESERVING original order+case.
#   Empty FILTER matches all names. Empty LIST prints nothing.
#   Caller does:  mapfile -t filtered < <(lp_build_filtered "$LIST" "$FILTER")
#   which yields the SAME array renderer.sh used to build via filtered+=("$name").
lp_build_filtered() {
	local LIST="${1:-}"
	local FILTER="${2:-}"
	local -a all=()
	local low_filter name low_name
	# printf '%s' (NO trailing newline): empty LIST -> all=() (NOT [""]); a
	# trailing newline in LIST is harmless (mapfile -t strips it).
	mapfile -t all < <(printf '%s' "$LIST")
	# Case-insensitive substring: lowercase BOTH sides; empty filter -> *""*
	# matches everything (so nav works with no query typed — PRD §6).
	low_filter="${FILTER,,}"
	for name in "${all[@]}"; do
		low_name="${name,,}"
		if [[ "$low_name" == *"$low_filter"* ]]; then
			printf '%s\n' "$name"
		fi
	done
}
