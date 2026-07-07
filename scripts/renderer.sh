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
# shellcheck source=rank.sh
source "$CURRENT_DIR/rank.sh"
# shellcheck source=layout.sh
source "$CURRENT_DIR/layout.sh"

render() {
	local TYPE FG BG HFG HBG
	local LIST FILTER IDX
	local -a all=() filtered=()
	local TOTAL FLEN
	local out seg i cidx first esc_filter esc_name SCROLL icon gap tabs justify width pad padw tabs_w \
		vis_start vis_end left_ind right_ind qbw T0 vp_T th ind_w left_present new_lp ovl ovr_fmt ranked \
		tab_style cur_tpl reg_tpl sep sep_w

	TYPE="$(opt_type)"
	FG="$(opt_fg)"
	BG="$(opt_bg)"
	HFG="$(opt_highlight_fg)"
	HBG="$(opt_highlight_bg)"

	# (§17 window-status is handled by the shared §19 engine below — the tab-style
	#  decision picks the per-tab render strategy + separator; no separate early-return.)

	LIST="$(get_state "$STATE_LIST" "")"
	FILTER="$(get_state "$STATE_FILTER" "")"
	esc_filter="${FILTER//\#/##}"   # display escape: every # -> ## (tmux literal-#; §P6)
	IDX="$(get_state "$STATE_INDEX" "0")"
	SCROLL="$(get_state "$STATE_SCROLL" "0")"   # read; viewport slicing lands in P1.M2.T2

	mapfile -t all < <(printf '%s' "$LIST")
	TOTAL="${#all[@]}"
	mapfile -t filtered < <(lp_rank "$LIST" "$FILTER")
	FLEN="${#filtered[@]}"

	# icon: the search glyph (U+F002) iff nerd-fonts on; else empty (raw UTF-8 bytes either way).
	if [ "$(opt_nerd_fonts)" = "on" ]; then
		icon="$(opt_search_icon)"
	else
		icon=""
	fi
	# gap: exactly opt_query_gap PLAIN (unstyled) spaces between the query and the tabs.
	[[ "$(opt_query_gap)" =~ ^[0-9]+$ ]] && gap="$(printf '%*s' "$(opt_query_gap)" '')" || gap=""

	# --- (c) NO-MATCH (PRD §19 §3.34): <icon><query> (no match). Plain-ASCII marker. ---
	if [ "$FLEN" -eq 0 ]; then
		printf '%s' "#[fg=$FG,bg=$BG]${icon}${esc_filter} (no match)#[default]"
		return 0
	fi

	# clamp cidx (0-based; wrap is the input-handler's job).
	cidx="$IDX"
	[[ "$cidx" =~ ^[0-9]+$ ]] || cidx=0
	[ "$cidx" -ge "$FLEN" ] && cidx=$((FLEN - 1))
	[ "$cidx" -lt 0 ] && cidx=0

	# --- §17 tab style + per-tab render strategy + inter-tab separator (shared §19 engine).
	# plain: standalone fg/bg coloring, joined by a single space. window-status: each tab
	# renders by swapping __lp_tab__/__lp_sentinel__ -> the # escaped name in the cached
	# template (current vs inactive per index), joined by window-status-separator. If EITHER
	# ws template is empty (resolution failed / not yet cached), fall back to plain (§17
	# Fallback) so the option never breaks a setup. The §19 layout (query bar / viewport /
	# overflow indicators / query-empty vs query-active / no-match) is IDENTICAL for both.
	tab_style="$(opt_tab_style)"
	cur_tpl=""; reg_tpl=""; sep=" "; sep_w=1
	if [ "$tab_style" = "window-status" ]; then
		cur_tpl="$(get_state "$STATE_TAB_CURRENT_TMPL" "")"
		reg_tpl="$(get_state "$STATE_TAB_INACTIVE_TMPL" "")"
		if [ -z "$cur_tpl" ] || [ -z "$reg_tpl" ]; then
			tab_style="plain"   # §17 Fallback: empty/unresolvable template -> plain
		else
			sep="$(tmux show-options -gwv window-status-separator 2>/dev/null)"
			[ -z "$sep" ] && sep=" "
			sep_w="$(lp_disp_width "$sep")"
		fi
	fi

	# --- viewport windowing + overflow indicators (PRD §19 §3.32/§3.33) ---
	# Available tab width T = client_width − query_block − active indicators. The indicator
	# presence depends on hidden counts (circular with the viewport); resolve via probe +
	# converge (research FINDING 2). layout.sh lp_viewport does the slice; the renderer
	# computes T (layout FINDING 5: layout.sh does NOT resolve the circle).
	width="$(get_state "$STATE_CLIENT_WIDTH" "0")"
	[[ "$width" =~ ^[0-9]+$ ]] || width=0

	# Default: no windowing (width unknown -> legacy full-list render, no indicators; FINDING 6).
	vis_start=0
	vis_end=$((FLEN - 1))
	left_ind=""
	right_ind=""
	if [ "$width" -gt 0 ]; then
		# query_block width: icon + query + gap (query-ACTIVE only; 0 when query empty). FINDING 5.
		qbw=0
		if [ -n "$FILTER" ]; then
			qbw=$(( ${#icon} + $(lp_disp_width "$FILTER") ))
			[[ "$(opt_query_gap)" =~ ^[0-9]+$ ]] && qbw=$(( qbw + $(opt_query_gap) ))
		fi
		T0=$(( width - qbw ))
		# The ranked list lp_viewport measures (newline-joined filtered names).
		ranked="$(printf '%s\n' "${filtered[@]}")"
		# Probe (no indicator reservation).
		lp_viewport "$ranked" "$T0" "$SCROLL" "$cidx" "$sep_w"
		th=$(( LPV_HIDDEN_LEFT + LPV_HIDDEN_RIGHT ))
		if [ "$th" -eq 0 ]; then
			# Fits entirely -> no indicators; lp_viewport already clamped scroll to 0.
			vis_start=$LPV_START
			vis_end=$LPV_END
		else
			# Overflow -> resolve the indicator circle (bounded; converges ≤2 iters; FINDING 2).
			ovl="$(opt_overflow_left)"
			ovr_fmt="$(opt_overflow_right_format)"
			left_present=0
			[ "$LPV_HIDDEN_LEFT" -gt 0 ] && left_present=1
			while :; do
				[ "$left_present" = 1 ] && left_ind="$ovl" || left_ind=""
				th=$(( LPV_HIDDEN_LEFT + LPV_HIDDEN_RIGHT ))
				right_ind="${ovr_fmt//%d/$th}"
				ind_w=$(( $(lp_disp_width "$left_ind") + $(lp_disp_width "$right_ind") ))
				vp_T=$(( T0 - ind_w ))
				lp_viewport "$ranked" "$vp_T" "$SCROLL" "$cidx" "$sep_w"
				new_lp=0
				[ "$LPV_HIDDEN_LEFT" -gt 0 ] && new_lp=1
				[ "$new_lp" = "$left_present" ] && break
				left_present="$new_lp"   # left flipped off->on; loop once more (monotonic)
			done
			vis_start=$LPV_START
			vis_end=$LPV_END
			# Final indicator strings from the CONVERGED counts; styled as chrome (FG/BG).
			th=$(( LPV_HIDDEN_LEFT + LPV_HIDDEN_RIGHT ))
			if [ "$LPV_HIDDEN_LEFT" -gt 0 ]; then
				left_ind="#[fg=$FG,bg=$BG]${ovl}#[default]"
			else
				left_ind=""
			fi
			[ "$th" -gt 0 ] && right_ind="#[fg=$FG,bg=$BG]${ovr_fmt//%d/$th}#[default]" || right_ind=""
		fi
	fi

	# Build the tab segments from the VISIBLE slice [vis_start, vis_end] (PRD §3.32). Each name
	# # escaped, styled; the highlighted index uses HFG/HBG; joined by a single space (plain mode).
	# cidx is guaranteed in the slice (scroll-into-view; or all-rendered when width=0). FINDING 11.
	first=1
	tabs=""
	for (( i = vis_start; i <= vis_end; i++ )); do
		esc_name="${filtered[$i]//\#/##}"
		if [ "$tab_style" = "window-status" ]; then
			# §17: swap __lp_tab__/__lp_sentinel__ -> name in the cached template (current
			# vs inactive per index). ${var//pat/rep} does not re-scan the replacement, so
			# a name equal to a placeholder cannot corrupt or recurse.
			if [ "$i" -eq "$cidx" ]; then
				seg="${cur_tpl//__lp_tab__/$esc_name}"
				seg="${seg//__lp_sentinel__/$esc_name}"
			else
				seg="${reg_tpl//__lp_tab__/$esc_name}"
				seg="${seg//__lp_sentinel__/$esc_name}"
			fi
		else
			if [ "$i" -eq "$cidx" ]; then
				seg="#[fg=$HFG,bg=$HBG]${esc_name}#[default]"
			else
				seg="#[fg=$FG,bg=$BG]${esc_name}#[default]"
			fi
		fi
		if [ "$first" -eq 1 ]; then
			tabs="$seg"
			first=0
		else
			tabs="$tabs$sep$seg"
		fi
	done

	if [ -z "$FILTER" ]; then
		# (a) QUERY EMPTY (PRD §19 §3.30): ONLY the tabs.
		if [ -n "$left_ind" ] || [ -n "$right_ind" ]; then
			# Overflow -> justification is MOOT; flow left-to-right from column 0 with indicators.
			printf '%s' "${left_ind}${tabs}${right_ind}"
		else
			# Fits -> emulate status-justify (leading padding). width already read above.
			justify="$(tmux show-options -g -v status-justify 2>/dev/null)"
			[ -z "$justify" ] && justify=left
			pad=""
			if [ "$justify" != left ]; then
				tabs_w="$(lp_disp_width "$tabs")"
				if [ "$tabs_w" -lt "$width" ]; then
					case "$justify" in
						centre | absolute-centre) padw=$(( (width - tabs_w) / 2 )) ;;
						right) padw=$(( width - tabs_w )) ;;
						*) padw=0 ;;
					esac
					[ "$padw" -gt 0 ] && pad="$(printf '%*s' "$padw" '')"
				fi
			fi
			printf '%s' "${pad}${tabs}"
		fi
		return 0
	fi

	# (b) QUERY ACTIVE (PRD §19 §3.31): <icon><query><gap>[<left_ind>]<tabs>[<right_ind>] at column 0.
	# status-justify SUSPENDED (pinned-left). Query # escaped; gap plain spaces; indicators chrome.
	printf '%s' "#[fg=$FG,bg=$BG]${icon}${esc_filter}#[default]${gap}${left_ind}${tabs}${right_ind}"
}

render || printf '%s' '#[fg=red]livepicker: renderer error#[default]'
exit 0
