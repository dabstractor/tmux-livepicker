#!/usr/bin/env bash
# shellcheck disable=SC1091,SC2034
#   SC1091: sources sibling libs (options/utils/state) via the resolved $CURRENT_DIR;
#           follow with `shellcheck -x` if you want them traced.
#   SC2034: TYPE is read from opt_type (FINDING 11) and reserved for a future
#           session/window label; the core render path does not branch on it.
# scripts/renderer.sh — tmux-livepicker #() status-line renderer.
#
# Invoked as status-format[0] = #($SCRIPT_DIR/renderer.sh) by activate
# (P1.M4.T3.S1) and re-evaluated on EVERY status redraw — which the input handler
# (P1.M6) forces via `tmux refresh-client -S` after each keystroke. Therefore:
# PURE (read options → print ONE line → exit; ZERO tmux mutations) and FAST
# (<50ms; ~9 option reads ≈ 30-45ms on target — see research FINDING 7).
#
# LOAD-BEARING RULES (research/renderer_findings.md):
#  - Emit EXACTLY ONE line, NO trailing newline: `printf '%s' "$out"`. Multi-line
#    stdout from #() renders ONLY the last line (data loss). (FINDING 2)
#  - `#[default]` after EVERY segment resets BOTH fg AND bg (one reset, both
#    axes — proven live). Omitting it leaks the highlight color onward. (FINDING 1)
#  - Read the list via PROCESS SUBSTITUTION: `mapfile -t all < <(printf '%s' "$LIST")`,
#    NOT a here-string (which makes an empty list look like a 1-element [""]).
#    (FINDING 3)
#  - NO `set -e` — an unset @-option makes show-option return rc=1; set -e would
#    abort the renderer and blank line 1. set -u is inherited (every var defaulted).
#    (FINDING 8)
#  - render || fallback-red-echo; exit 0 — a renderer crash must NEVER blank the
#    bar. (FINDING 9)
#
# INDEX is 0-based (contract; matches array indexing). The renderer CLAMPS
# (idx<0→0, idx>=FLEN→FLEN-1); wrapping is the input-handler's job (P1.M6.T2).
# Display idx+1. Empty-filtered count denominator = TOTAL; non-empty = FLEN.
#
# DEPENDS ON (source order is load-bearing — state.sh needs utils.sh first):
#   options.sh (get_opt/opt_*), utils.sh (tmux_*), state.sh (get_state/STATE_*).
# All three guarantee NO source-time side effects.

CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=options.sh
source "$CURRENT_DIR/options.sh"
# shellcheck source=utils.sh
source "$CURRENT_DIR/utils.sh"
# shellcheck source=state.sh
source "$CURRENT_DIR/state.sh"

render() {
	local TYPE FG BG HFG HBG SHOW_COUNT_RAW SHOW_COUNT
	local LIST FILTER IDX
	local -a all=() filtered=()
	local TOTAL FLEN low_filter name low_name
	local out seg i cidx first

	TYPE="$(opt_type)"
	FG="$(opt_fg)"
	BG="$(opt_bg)"
	HFG="$(opt_highlight_fg)"
	HBG="$(opt_highlight_bg)"
	SHOW_COUNT_RAW="$(opt_show_count)"
	case "${SHOW_COUNT_RAW,,}" in
		'' | off | 0 | no | false | disable) SHOW_COUNT=0 ;;
		*) SHOW_COUNT=1 ;;
	esac

	LIST="$(get_state "$STATE_LIST" "")"
	FILTER="$(get_state "$STATE_FILTER" "")"
	IDX="$(get_state "$STATE_INDEX" "0")"

	mapfile -t all < <(printf '%s' "$LIST")
	TOTAL="${#all[@]}"

	low_filter="${FILTER,,}"
	for name in "${all[@]}"; do
		low_name="${name,,}"
		if [[ "$low_name" == *"$low_filter"* ]]; then
			filtered+=("$name")
		fi
	done
	FLEN="${#filtered[@]}"

	out=""
	if [ "$FLEN" -eq 0 ]; then
		if [ "$SHOW_COUNT" -eq 1 ]; then
			out="#[fg=$FG,bg=$BG]query> $FILTER (no match) 0/$TOTAL#[default]"
		else
			out="#[fg=$FG,bg=$BG]query> $FILTER (no match)#[default]"
		fi
		printf '%s' "$out"
		return 0
	fi

	cidx="$IDX"
	[[ "$cidx" =~ ^[0-9]+$ ]] || cidx=0
	[ "$cidx" -ge "$FLEN" ] && cidx=$((FLEN - 1))
	[ "$cidx" -lt 0 ] && cidx=0

	first=1
	for i in "${!filtered[@]}"; do
		if [ "$i" -eq "$cidx" ]; then
			seg="#[fg=$HFG,bg=$HBG]${filtered[$i]}#[default]"
		else
			seg="#[fg=$FG,bg=$BG]${filtered[$i]}#[default]"
		fi
		if [ "$first" -eq 1 ]; then
			out="$seg"
			first=0
		else
			out="$out $seg"
		fi
	done

	if [ "$SHOW_COUNT" -eq 1 ]; then
		out="$out #[fg=$FG,bg=$BG]query> $FILTER [$((cidx + 1))/$FLEN]#[default]"
	fi

	printf '%s' "$out"
}

render || printf '%s' '#[fg=red]livepicker: renderer error#[default]'
exit 0
