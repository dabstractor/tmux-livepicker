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
# shellcheck source=filter.sh
source "$CURRENT_DIR/filter.sh"

render() {
	local TYPE FG BG HFG HBG SHOW_COUNT_RAW SHOW_COUNT
	local LIST FILTER IDX
	local -a all=() filtered=()
	local TOTAL FLEN
	local out seg i cidx first esc_filter esc_name

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

	# --- PRD §17: window-status render path (theme-matched tabs) ---
	# Self-contained early-return. Entered only when @livepicker-tab-style is
	# window-status AND both cached templates are non-empty (cached once at activation
	# by _lp_resolve_tab_templates, P1.M1.T2.S1). If EITHER fails, execution falls
	# through to the existing plain path below (untouched). The cached templates are
	# fully-resolved #[...]-styled strings with __lp_tab__ baked in where #W was; here
	# we swap __lp_tab__ -> each # escaped session name and join with
	# window-status-separator. #[...] styling in #() output IS applied
	# (external_tmux_behavior.md Q2); #{...} is NOT (why pre-resolution is needed).
	# See research/renderer_ws_branch_findings.md (FINDING 1-8).
	if [ "$(opt_tab_style)" = "window-status" ]; then
		local cur_tpl reg_tpl
		local ws_list ws_filter ws_idx esc_wfilter ws_sep ws_out ws_first ws_total
		local -a ws_all=() ws_filtered=()
		local ws_flen ws_cidx ws_i ws_name esc_wname ws_tpl ws_seg

		cur_tpl="$(get_state "$STATE_TAB_CURRENT_TMPL" "")"
		reg_tpl="$(get_state "$STATE_TAB_INACTIVE_TMPL" "")"
		# If EITHER template is empty (resolution failed -> set-empty by the writer, or
		# helper not yet run -> unset), fall through to the plain path. (FINDING 3:
		# get_state + [ -n ] fully honors the writer's set-empty contract and is leaner
		# than a tmux_is_set probe, which adds no branching signal.)
		if [ -n "$cur_tpl" ] && [ -n "$reg_tpl" ]; then
			ws_list="$(get_state "$STATE_LIST" "")"
			ws_filter="$(get_state "$STATE_FILTER" "")"
			esc_wfilter="${ws_filter//\#/##}"   # display escape: every # -> ## (tmux literal-#; Issue 3)
			ws_idx="$(get_state "$STATE_INDEX" "0")"
			ws_sep="$(tmux show-options -gwv window-status-separator 2>/dev/null)"
			[ -z "$ws_sep" ] && ws_sep=" "       # default to a space (window option; -gwv scope)

			mapfile -t ws_all < <(printf '%s' "$ws_list")
			ws_total="${#ws_all[@]}"
			mapfile -t ws_filtered < <(lp_build_filtered "$ws_list" "$ws_filter")
			ws_flen="${#ws_filtered[@]}"

			# no-match: mirror the plain path's no-match output (consistency; FINDING 6).
			if [ "$ws_flen" -eq 0 ]; then
				if [ "$SHOW_COUNT" -eq 1 ]; then
					printf '%s' "#[fg=$FG,bg=$BG]query> $esc_wfilter (no match) 0/$ws_total#[default]"
				else
					printf '%s' "#[fg=$FG,bg=$BG]query> $esc_wfilter (no match)#[default]"
				fi
				return 0
			fi

			# clamp cidx (same rule as the plain path; 0-based, wrap is input-handler's job).
			ws_cidx="$ws_idx"
			[[ "$ws_cidx" =~ ^[0-9]+$ ]] || ws_cidx=0
			[ "$ws_cidx" -ge "$ws_flen" ] && ws_cidx=$((ws_flen - 1))
			[ "$ws_cidx" -lt 0 ] && ws_cidx=0

			# Build the joined tabs: current template for the highlighted index, inactive
			# for the rest; swap __lp_tab__ -> the # escaped name (FINDING 4).
			ws_first=1
			ws_out=""
			for ws_i in "${!ws_filtered[@]}"; do
				ws_name="${ws_filtered[$ws_i]}"
				esc_wname="${ws_name//\#/##}"   # escape # BEFORE substitution (tmux literal-#)
				if [ "$ws_i" -eq "$ws_cidx" ]; then
					ws_tpl="$cur_tpl"
				else
					ws_tpl="$reg_tpl"
				fi
				# literal swap: ${var//pat/rep} does not re-scan the replacement, so a name
				# equal to __lp_tab__ cannot corrupt or recurse.
				ws_seg="${ws_tpl//__lp_tab__/$esc_wname}"
				if [ "$ws_first" -eq 1 ]; then
					ws_out="$ws_seg"
					ws_first=0
				else
					ws_out="$ws_out$ws_sep$ws_seg"
				fi
			done

			# SHOW_COUNT suffix — mirror the plain path for consistency (FINDING 6).
			if [ "$SHOW_COUNT" -eq 1 ]; then
				ws_out="$ws_out #[fg=$FG,bg=$BG]query> $esc_wfilter [$((ws_cidx + 1))/$ws_flen]#[default]"
			fi

			printf '%s' "$ws_out"   # ONE line, NO trailing newline (multi-line #() renders last only)
			return 0
		fi
		# (else: a template is empty -> fall through to the plain path below)
	fi

	LIST="$(get_state "$STATE_LIST" "")"
	FILTER="$(get_state "$STATE_FILTER" "")"
	esc_filter="${FILTER//\#/##}"   # display escape: every # -> ## (tmux literal-#; Issue 3)
	IDX="$(get_state "$STATE_INDEX" "0")"

	mapfile -t all < <(printf '%s' "$LIST")
	TOTAL="${#all[@]}"

	mapfile -t filtered < <(lp_build_filtered "$LIST" "$FILTER")
	FLEN="${#filtered[@]}"

	out=""
	if [ "$FLEN" -eq 0 ]; then
		if [ "$SHOW_COUNT" -eq 1 ]; then
			out="#[fg=$FG,bg=$BG]query> $esc_filter (no match) 0/$TOTAL#[default]"
		else
			out="#[fg=$FG,bg=$BG]query> $esc_filter (no match)#[default]"
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
		esc_name="${filtered[$i]//\#/##}"   # display escape: every # -> ## (tmux literal-#; Issue 3)
		if [ "$i" -eq "$cidx" ]; then
			seg="#[fg=$HFG,bg=$HBG]${esc_name}#[default]"
		else
			seg="#[fg=$FG,bg=$BG]${esc_name}#[default]"
		fi
		if [ "$first" -eq 1 ]; then
			out="$seg"
			first=0
		else
			out="$out $seg"
		fi
	done

	if [ "$SHOW_COUNT" -eq 1 ]; then
		out="$out #[fg=$FG,bg=$BG]query> $esc_filter [$((cidx + 1))/$FLEN]#[default]"
	fi

	printf '%s' "$out"
}

render || printf '%s' '#[fg=red]livepicker: renderer error#[default]'
exit 0
