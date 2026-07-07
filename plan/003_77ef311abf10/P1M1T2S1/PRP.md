# PRP — P1.M1.T2.S1: Implement display-width measurement + lp_viewport scroll math

---

## Goal

**Feature Goal**: A new sourced library `scripts/layout.sh` that provides the SINGLE
shared display-width measurement and viewport/scroll math for PRD §19's status-line
layout. `lp_disp_width STRING` measures a tab's visible columns (with `#[…]` styles
stripped first); `lp_viewport` computes the visible slice + scroll-into-view + hidden
counts. Both are PURE bash (no tmux calls, no subshells on the measurement path) so the
renderer (M2) and input-handler (M3) can never disagree on width (PRD §16 "Viewport
measurement").

**Deliverable**: The single new file `scripts/layout.sh` (created — it does not exist).
Defines `_lp_strip_styles`, `lp_disp_width`, `lp_viewport` (+ `LPV_*` output globals).
Sourced library — no source-time side effects, no driver. NOT yet wired into the
renderer/input-handler (that is M2/M3); this subtask ships the lib only.

**Success Definition**:
- `lp_disp_width` strips every `#[…]` run then counts codepoints via `${#var}`:
  `#[fg=red]hello#[default]` → 5; `<nerd-font-icon>main` → 5 (icon=1); `#[default]#[fg=...] __lp_tab__ #[...]` → 12.
- `lp_viewport` returns the correct scroll/start/end/hidden-left/hidden-right for: fits-in-T
  (clamp scroll 0), overflow + scroll-into-view (highlight always visible), highlight<scroll
  (scroll=highlight), single-tab-wider-than-T (degenerate), and styled/icon tabs.
- `bash -n` + `shellcheck` clean; sourcing has NO side effects; `tests/run.sh` stays green
  (the lib is not yet referenced by any shipped script, so nothing can regress).

## User Persona (if applicable)

**Target User**: The renderer (P1.M2) and input-handler (P1.M3) — downstream siblings
that will `source` this lib. Not end-user facing. Mode A — internal lib, no docs.

**Use Case**: The renderer calls `lp_viewport` to slice the ranked list to the visible
window + render the `+N>`/`<` overflow indicators; the input-handler calls it after nav
to compute the new scroll index to write to `@livepicker-scroll`. Both measure tab widths
via the same `lp_disp_width` so the slice and the scroll never disagree.

**Pain Points Addressed**: PRD §16 "Viewport measurement … lives once … so [renderer and
input-handler] cannot disagree"; the `#[…]`-styles-inflate-raw-length trap; the per-keystroke
width-source must be the cached `@livepicker-client-width` (no tmux round-trip — §18 budget).

---

## Why

- **The shared-measurement invariant (PRD §16).** Tab display width must be measured
  identically by the renderer (to slice) and the input-handler (to scroll-into-view), or
  the highlight and the visible window desync. Centralizing it in one sourced lib makes
  disagreement impossible.
- **Unblocks the §19 renderer rework (M2) and the scroll state (M3).** Both depend on this
  lib existing with a stable interface. This subtask is the contract seam.
- **Pure + fast (§18 budget).** No tmux calls, no per-tab subshell (`wc -m`/`sed` rejected —
  they spawn a process per tab and `wc -m` is locale-dependent). The manual-loop strip +
  `${#var}` builtin measures 200 tabs in ~21 ms (verified), well under the <50 ms renderer budget.
- **Leak-safe by construction.** A sourced lib defining functions + a few readonly scoring
  constants touches no tmux state and prints nothing at source time (matches rank.sh/filter.sh).

## What

A sourced Bash library `scripts/layout.sh` exposing:
1. `_lp_strip_styles STRING` (internal) — strip every `#[…]` style run, print visible text.
2. `lp_disp_width STRING` — print the integer display-column count (strip + `${#var}` codepoints).
3. `lp_viewport RANKED_LIST T SCROLL HIGHLIGHT [SEP_WIDTH]` — compute the visible slice +
   scroll-into-view, setting globals `LPV_SCROLL LPV_START LPV_END LPV_HIDDEN_LEFT LPV_HIDDEN_RIGHT`.

Pure bash; no tmux; no source-time side effects; `set -u`; tabs; `local` everywhere.

### Success Criteria

- [ ] File exists at `scripts/layout.sh`; shebang `#!/usr/bin/env bash`; `set -u` only.
- [ ] `_lp_strip_styles`, `lp_disp_width`, `lp_viewport` defined; `LPV_*` globals set by viewport.
- [ ] `lp_disp_width "#[fg=red]hello#[default]"` → 5; on a nerd-font-icon+name tab → icon(1)+name.
- [ ] `lp_viewport` passes all 7 verified cases (fits, overflow+scroll-into-view, hl<scroll,
      single-wide-tab, styled/icon tabs) — see Validation L2.
- [ ] `bash -n` + `shellcheck` clean; sourcing = no side effects (L3 cksum unchanged).
- [ ] `tests/run.sh` green (lib unreferenced → no regression possible).

## All Needed Context

### Context Completeness Check

_Pass_: The implementer needs (a) the verbatim function bodies (below), (b) the two trap
corrections from the research file (`wc -m` locale-dependent → use `${#var}`; naive glob
strip broken → use the manual loop), and (c) the verified viewport algorithm. No inference
required — every behavior is empirically proven.

### Documentation & References

```yaml
# MUST READ — the empirical ground-truth (corrects TWO contract traps)
- docfile: plan/003_77ef311abf10/P1M1T2S1/research/layout_viewport_findings.md
  why: PROVES the mechanism live. FINDING 1 (wc -m is LOCALE-DEPENDENT → use ${#var}, a
       builtin, no subshell); FINDING 2 (the naive ${var//#[[^]]*]/} glob strip is BROKEN
       — eats everything; use the manual case-loop, verified, 21ms/200tabs); FINDING 3
       (realistic-tab widths; icon=1); FINDING 4 (all 7 viewport cases verified); FINDING 5
       (indicators/separator handling).
  critical: Read BEFORE writing. The contract's "regex strip of #\[[^]]*\]" and "wc -m"
            are BOTH traps that produce silently-wrong widths.

# MUST READ — the sourced-library contract this lib must match
- docfile: plan/003_77ef311abf10/architecture/codebase_patterns.md
  why: §P1 (sourced lib: functions+consts ONLY, NO source-time side effects, NO driver,
       set -u not -e, # shellcheck disable=SC1091, CURRENT_DIR resolver); §P7 (layout.sh
       is the ONE shared measurement, sourced by renderer+input-handler; strip #[…] first;
       T=client_width−query_block−indicators; clamp scroll=0 when fits).
  section: "P1 — Sourced library contract" and "P7 — Layout viewport (layout.sh, NEW, shared)"

# MUST READ — the sibling lib to mirror (rank.sh, LANDED)
- file: scripts/rank.sh
  why: The exact sourced-lib style to match: header (shebang, SC1091/SC2034 disables, set -u,
       CURRENT_DIR resolver, contract comment), `lp_rank LIST FILTER` prints newline-separated
       output, empty-list → prints nothing, mapfile-via-process-substitution input convention.
  pattern: layout.sh mirrors this file's shape (header + pure functions + readonly consts).
  gotcha: rank.sh declares `readonly LP_*` scoring consts; layout.sh may declare none (the
          SEP default is a function default, not a const) — match rank.sh's header but do not
          copy consts that have no meaning here.

# MUST READ — the input format layout.sh consumes (rank.sh output)
- file: scripts/rank.sh
  why: `lp_rank LIST FILTER` → newline-separated ranked names, best-first (empty FILTER →
        all names original order). lp_viewport takes THIS list (newline-separated string);
        it is agnostic to the source (filter.sh today, rank.sh after T1.S2 retires filter.sh).
  section: the lp_rank function + the mapfile/printf input/output convention

# MUST READ — PRD §19 (the layout spec) + §16 (the measurement invariant)
- docfile: PRD.md
  why: §19 §3.32 (viewport+scroll rules: scroll=first-visible; type/backspace/cancel-clear→
       scroll=0; nav scroll-into-view; clamp scroll=0 when fits) and §3.33 (overflow indicators:
       +%d> = left-hidden+right-hidden total; < when scroll>0; neither when fits). §16
       "Viewport measurement" (strip #[…] first; measurement lives once; recompute every redraw).
  section: "§19 Status-line layout" (Viewport and scroll / Overflow indicators) + "§16 Viewport measurement"

# Reference — the M2 consumer (read; do NOT edit — wiring is M2)
- file: scripts/renderer.sh
  why: Shows how the renderer reads STATE_LIST/FILTER/INDEX via mapfile+lp_build_filtered and
        builds #[...]-styled segments joined by a space. M2 will replace lp_build_filtered with
        lp_rank + add lp_viewport windowing. This PRP ships the lib ONLY; the renderer is unchanged.
  gotcha: the renderer sources filter.sh today; T1.S2 (parallel) swaps it to rank.sh. layout.sh
          is independent of that swap (consumes the list string, not the filter function).

# Reference — state keys the M3 caller will use (read; do NOT add here)
- docfile: plan/003_77ef311abf10/architecture/codebase_patterns.md
  why: §P3 lists STATE_SCROLL (@livepicker-scroll), STATE_CLIENT_WIDTH (@livepicker-client-width)
        that M3 wires. layout.sh itself reads NO state (pure args-in, globals-out) — it does not
        even need to be sourced alongside state.sh. This keeps it unit-testable in isolation.
```

### Current Codebase tree

```bash
tmux-livepicker/
  scripts/
    rank.sh      # (P1.M1.T1.S1, LANDED) lp_rank — the input format layout.sh consumes
    filter.sh    # (still present; T1.S2 retires it) — layout.sh is agnostic to the source
    layout.sh    # NEW (this task). lp_disp_width + lp_viewport + _lp_strip_styles. Pure lib.
    renderer.sh  # UNCHANGED here (M2 wires layout.sh in)
    ...          # (options/utils/state/input-handler/preview/restore/livepicker unchanged)
  tests/         # UNCHANGED (feature validation is P1.M4.T1 test_layout.sh; this ships the lib only)
```

### Desired Codebase tree with files to be added and responsibility of file

```bash
scripts/layout.sh   # NEW. Responsibility: the ONE shared display-width measurement + viewport
                    #   scroll/slice math (PRD §16/§19). Pure bash, no tmux, no source-time side
                    #   effects. Sourced by renderer.sh (M2) and input-handler.sh (M3).
```

### Known Gotchas of our codebase & Library Quirks

```bash
# CRITICAL (research FINDING 1) — DO NOT use `wc -m`. It is LOCALE-DEPENDENT: under a C locale
# it counts BYTES (the 3-byte nerd-font icon → width 3, WRONG); under UTF-8 it counts codepoints
# (icon → 1, correct). AND it spawns a subshell per call (violates the §18 renderer budget when
# called per-tab). USE bash's `${#var}` on the STRIPPED string — it's a builtin (no subshell) and
# counts codepoints under a UTF-8 locale (the nerd-font use case guarantees UTF-8; a C-locale
# user sees raw icon garbage regardless, so a width miscalc is moot). Document the assumption.

# CRITICAL (research FINDING 2) — the naive bash glob strip `${var//\#\[[^]]*\]/}` is BROKEN.
# bash parameter expansion uses GLOB patterns, where `*` is a standalone wildcard, NOT a regex
# quantifier. The glob greedily eats from the first #[ to the LAST ], including visible text
# (verified: returns ""). USE THE MANUAL CASE-LOOP (_lp_strip_styles): case-match `*"#["*`,
# `${in%%\#[*}` (text before #[), `${in#*]}` (drop through to after the next ]). Verified correct
# + fast (21ms/200tabs). Do NOT use sed on the render path (spawns a process per tab).

# CRITICAL — this is a SOURCED library. It MUST NOT have a `*_main "$@"` driver, MUST NOT call
# tmux, MUST NOT print at source time, MUST NOT mutate globals beyond the documented LPV_*
# viewport outputs. Match rank.sh/filter.sh exactly (§P1). Only renderer.sh/input-handler.sh/
# preview.sh/etc. (entry points invoked via run-shell/#()) have drivers.

# CRITICAL — `lp_viewport` is PURE MATH (args-in, LPV_* globals-out). It reads NO tmux state
# (not @livepicker-client-width, not @livepicker-scroll). The CALLER passes T (already net of
# query block + indicator budget), scroll, highlight. This keeps it unit-testable and avoids the
# indicator-presence circular dependency (the renderer resolves that in M2 — research FINDING 5).
# Do NOT add get_state/opt_* calls inside layout.sh.

# CRITICAL — the "active indicators width" is NOT layout.sh's concern. PRD §19 says
# T = client_width − query_block − active_indicators, but indicator presence depends on hidden
# counts (circular). layout.sh takes T as a GIVEN input and returns hidden counts; the renderer
# (M2) decides indicator presence and reserves their width. Do NOT try to resolve the circle here.

# GOTCHA — the nerd-font icon U+F002 is 1 codepoint → width 1 (the contract's assumption,
# verified). ASCII = 1/codepoint. Wide CJK/emoji (width 2) would be UNDERCOUNTED — a documented
# limitation (session names are typically ASCII; §19 doesn't require wide-glyph support). Do NOT
# add a wcwidth-style wide-glyph check (YAGNI).

# GOTCHA — the inter-tab separator matters for the slice. Plain mode joins with a space (width 1);
# window-status mode joins with window-status-separator (variable width). lp_viewport takes
# SEP_WIDTH as an optional 5th arg (default 1) and includes (count)*sep in cumwidth. The caller
# passes the right sep for its mode. Do NOT hardcode sep=1 inside cumwidth.

# GOTCHA — LPV_END = -1 signals an EMPTY slice (n=0 or T<=0). Callers must loop
# `for ((i=LPV_START; i<=LPV_END; i++))` (which is a no-op when END<START). Document this.

# GOTCHA — sanitize scroll/highlight to [0, n-1] (they are STRING state options; a stale/invalid
# value must not crash the math under set -u). Match rank.sh's `[[ "$x" =~ ^[0-9]+$ ]] || x=0` idiom.

# GOTCHA — `set -u` is inherited/included. Every function local MUST be `local`-declared. NO
# `set -e` (the strip loop's case + param expansions are control flow, not error checks). Tabs
# for indent (shfmt is NOT installed).

# GOTCHA — do NOT add layout.sh to any consumer's `source` line in THIS subtask. M2 (renderer)
# and M3 (input-handler) wire it in. Shipping the lib unreferenced is correct (it cannot regress
# the suite — nothing calls it yet). Validate via a throwaway smoke (L2).
```

## Implementation Blueprint

### Data models and structure

No runtime data model — only function definitions and the `LPV_*` output globals. The
"model" is the viewport computation:

```
lp_viewport(RANKED_LIST, T, SCROLL, HIGHLIGHT, SEP=1):
  tabs = split(RANKED_LIST)             # mapfile -t < <(printf '%s' "$list")
  n = len(tabs)
  if n==0 or T<=0: LPV_* = (0,0,-1,n,0)  # empty slice; END=-1 sentinel
  w[i] = lp_disp_width(tabs[i])          # strip #[...] then ${#} codepoints
  total = sum(w) + (n-1)*SEP
  if total <= T: clamp scroll=0, slice=[0,n-1], hidden=0   # §3.32 "clamp when fits"
  else:
    sanitize scroll, highlight to [0,n-1]
    if highlight < scroll: scroll = highlight               # §3.32
    advance scroll while cumwidth(scroll,highlight) > T     # §3.32 scroll-into-view (incremental)
    end = largest idx>=scroll with cumwidth(scroll,end) <= T
    hidden_left = scroll; hidden_right = n-1-end            # §3.33 +%d> = left+right
```

### Implementation Tasks (ordered by dependencies)

```yaml
Task 1: CREATE scripts/layout.sh
  - STRUCTURE: shebang; SC1091/SC2034 disable header (match rank.sh); contract comment
    (purpose, "sourced lib, NO side effects", the two measurement traps); set -u; CURRENT_DIR
    resolver (match rank.sh — siblings read it when sourced together).
  - IMPLEMENT _lp_strip_styles STRING (internal): the manual case-loop (research FINDING 2a).
    Prints visible text. Pure bash, no shopt, no subshell.
  - IMPLEMENT lp_disp_width STRING: `local s; s="$(_lp_strip_styles "$1")"; printf '%s' "${#s}"`.
    (The ${#} builtin — NOT wc -m — research FINDING 1.)
  - IMPLEMENT lp_viewport RANKED_LIST T SCROLL HIGHLIGHT [SEP_WIDTH]: the verified algorithm
    (research FINDING 4). Sets LPV_SCROLL/START/END/HIDDEN_LEFT/HIDDEN_RIGHT. Sanitize inputs,
    measure widths, total+fits check, scroll-into-view (incremental cumwidth), find-end forward
    scan, hidden counts.
  - FOLLOW pattern: scripts/rank.sh (header + sourced-lib shape + mapfile-via-process-subst
    input + printf output convention).
  - NAMING: _lp_strip_styles (leading _ = internal); lp_disp_width; lp_viewport (match lp_rank's
    lp_ prefix); LPV_* output globals (namespaced).
  - STYLE: tabs; local for ALL locals; quote expansions; NO set -e; NO driver line.
  - PLACEMENT: scripts/layout.sh.
  - NO SIDE EFFECTS: no tmux calls, no source-time prints, no get_state/opt_* reads.

Task 2: VALIDATE (throwaway smoke — the lib is not yet referenced by any shipped script)
  - RUN: bash -n scripts/layout.sh ; shellcheck scripts/layout.sh (expect 0 findings)
  - RUN: the throwaway smoke (Validation L2) — lp_disp_width on styled/icon tabs; lp_viewport
    on all 7 verified cases. Then DELETE the smoke.
  - RUN: no-side-effects proof (L3): source layout.sh in a subshell, assert it defines the 3
    functions and prints nothing / sets only the documented globals.
  - RUN: tests/run.sh (expect green — the lib is unreferenced; no regression possible).
```

### Implementation Patterns & Key Details

**The complete file body** (paste verbatim; the implementer may adjust comment phrasing only):

```bash
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

# _lp_strip_styles STRING — print STRING with every #[…] style run removed (zero-width
# directives that inflate raw length). Manual case-loop (NOT a glob/regex strip — bash
# param expansion globs can't express "#[ run of non-] chars ]" without eating visible
# text; research FINDING 2). Pure bash, no shopt, no subshell.
_lp_strip_styles() {
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
	printf '%s' "$out"
}

# lp_disp_width STRING — print the integer display-column count: strip #[…] styles, then
# count codepoints via ${#var} (builtin; codepoints under a UTF-8 locale — FINDING 1).
# NOT wc -m (locale-dependent + subshell). Used by lp_viewport AND (in M2/M3) by callers
# that need a single tab's width.
lp_disp_width() {
	local s
	s="$(_lp_strip_styles "${1:-}")"
	printf '%s' "${#s}"
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

	# Measure each tab width once; accumulate the total (with separators).
	local -a w=()
	local i=0 total=0 wid
	for ((i = 0; i < n; i++)); do
		wid="$(lp_disp_width "${tabs[i]}")"
		w[i]="$wid"
		total=$((total + wid))
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
```

Key pattern notes:
- The strip loop is the load-bearing primitive; `lp_disp_width` is a thin wrapper over it.
- `lp_viewport` measures widths via `lp_disp_width` (the SINGLE measurement point — §16).
- The scroll-into-view `cw` update is incremental (O(n), not O(n²)) — critical for the §18 budget.
- `LPV_*` globals are reset at every call (no stale state across invocations).
- No `set -e` (control flow is case/while, not error checks); `set -u` satisfied (every var defaulted).

### Integration Points

```yaml
CODE:
  - file: scripts/layout.sh
    change: "NEW sourced lib: _lp_strip_styles, lp_disp_width, lp_viewport (+ LPV_* globals)"
    invariant: "the ONE shared display-width measurement + viewport math (PRD §16/§19)"

CONSUMERS (later subtasks — DO NOT wire here):
  - P1.M2.T2 (renderer.sh): source layout.sh; call lp_viewport to slice + render overflow indicators
  - P1.M3.T2 (input-handler.sh): source layout.sh; call lp_viewport after nav to compute the new scroll
  - Both pass the cached @livepicker-client-width as T (captured at activate, P1.M3.T1)

DATABASE / CONFIG / ROUTES: none.
```

## Validation Loop

### Level 1: Syntax & Style (Immediate Feedback)

```bash
cd /home/dustin/.config/tmux/plugins/tmux-livepicker
bash -n scripts/layout.sh && echo "OK: layout syntax"
shellcheck scripts/layout.sh          # expect 0 findings (SC1091/SC2034 disabled in-header)
# Tabs-not-spaces (shfmt NOT installed):
grep -nP '^    [^#/]' scripts/layout.sh && echo "WARN: space-indent (use tabs)" || echo "OK: tabs"
# The 3 functions + globals are present:
grep -c '^lp_disp_width\|^lp_viewport\|^_lp_strip_styles\|^LPV_' scripts/layout.sh   # -> 8 (3 fns + 5 globals)
# NO driver line (it is a sourced lib, NOT an entry point):
grep -q '_main "\$@"' scripts/layout.sh && echo "FAIL: has a driver (sourced libs must not)" || echo "OK: no driver"
# NO tmux calls (pure lib):
grep -nE '^[^#]*\btmux\b' scripts/layout.sh && echo "WARN: tmux call in pure lib" || echo "OK: no tmux calls"
```

### Level 2: Functional smoke (the 7 verified cases; DELETE after — feature tests are P1.M4.T1)

```bash
cat > /tmp/smoke_layout.sh <<'EOF'
#!/usr/bin/env bash
set -u
cd /home/dustin/.config/tmux/plugins/tmux-livepicker
source scripts/layout.sh
pass=0; fail=0
ck() { if [ "$2" = "$3" ]; then pass=$((pass+1)); else fail=$((fail+1)); printf 'FAIL %s: got[%s] want[%s]\n' "$1" "$2" "$3"; fi; }

# --- lp_disp_width ---
ck "strip simple"   "$(lp_disp_width '#[fg=red]hello#[default]')" "5"
ck "strip multi"    "$(lp_disp_width '#[a]x#[b]y#[c]z')" "3"
ck "literal # kept" "$(lp_disp_width 'a#b##c')" "6"   # a,#,b,#,#,c = 6 chars; no #[…] runs to strip
icon="$(printf '\xef\x80\x82')"   # U+F002 nerd-font search icon
ck "icon+name"      "$(lp_disp_width "#[fg=c]${icon} main#[default]")" "6"   # icon1+space+main4
ck "tubular-style"  "$(lp_disp_width '#[default]#[fg=#181822,bg=#7aa89f] __lp_tab__ #[fg=#7aa89f,bg=#181822]')" "12"
ck "empty"          "$(lp_disp_width '')" "0"

# --- lp_viewport (the 7 verified cases) ---
vp() { lp_viewport "$1" "$2" "$3" "$4" "${5:-1}"; }
# (1) fits -> clamp scroll 0, all visible
vp $'aaa\nbbb\nccc' 100 5 1; ck "fits scroll"   "$LPV_SCROLL" "0"; ck "fits end" "$LPV_END" "2"; ck "fits hiddenR" "$LPV_HIDDEN_RIGHT" "0"
# (2) overflow, scroll=0, hl=0, 5 width-3 tabs, T=10 -> slice [0,1], hiddenR=3
vp $'aaa\nbbb\nccc\nddd\neee' 10 0 0; ck "ovf end" "$LPV_END" "1"; ck "ovf hiddenR" "$LPV_HIDDEN_RIGHT" "3"
# (3) scroll-into-view: hl=3, T=10 -> scroll=2, slice [2,3]
vp $'aaa\nbbb\nccc\nddd\neee' 10 0 3; ck "siv scroll" "$LPV_SCROLL" "2"; ck "siv end" "$LPV_END" "3"; ck "siv hiddenL" "$LPV_HIDDEN_LEFT" "2"
# (4) hl<scroll -> scroll=hl
vp $'aaa\nbbb\nccc\nddd\neee' 10 3 1; ck "lt scroll" "$LPV_SCROLL" "1"; ck "lt end" "$LPV_END" "2"
# (5) 7 tabs, scroll=2, hl=5 -> scroll advances to 4; total hidden=5
vp $'aaa\nbbb\nccc\nddd\neee\nfff\nggg' 10 2 5; ck "7 hidden_total" "$((LPV_HIDDEN_LEFT+LPV_HIDDEN_RIGHT))" "5"; ck "7 end" "$LPV_END" "5"
# (6) single tab wider than T -> scroll=0, end=0, hidden=0
vp $'verylongname' 3 0 0; ck "wide scroll" "$LPV_SCROLL" "0"; ck "wide end" "$LPV_END" "0"; ck "wide hidden" "$((LPV_HIDDEN_LEFT+LPV_HIDDEN_RIGHT))" "0"
# (7) styled/icon tabs (widths 6,5,4), T=12, hl=1 -> slice [0,1], hiddenR=1
vp "$(printf '#[fg=r]%s main#[d]\n#[fg=b]alpha#[d]\n#[d]beta' "$icon")" 12 0 1; ck "sty end" "$LPV_END" "1"; ck "sty hiddenR" "$LPV_HIDDEN_RIGHT" "1"
# (8) empty list -> END=-1 (empty slice)
vp '' 80 0 0; ck "empty END" "$LPV_END" "-1"
# (9) separator width: sep=2 changes the fit (aaa[2]bbb = 3+2+3=8; +ccc=8+2+3=13)
vp $'aaa\nbbb\nccc' 10 0 0 2; ck "sep2 end" "$LPV_END" "1"   # 8<=10 fits 2 tabs; +ccc=13>10

printf 'pass=%d fail=%d\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
EOF
bash /tmp/smoke_layout.sh; rc=$?
rm -f /tmp/smoke_layout.sh
exit $rc
# Expected: pass~=30 fail=0. (The 'literal # kept' case asserts 6: 'a#b##c' is 6 chars with
# no #[…] runs, so the strip is a no-op.) Cases (1)-(9) mirror research FINDING 4 + the width findings.
```

### Level 3: No-side-effects proof (sourced-lib contract)

```bash
cd /home/dustin/.config/tmux/plugins/tmux-livepicker
# Sourcing must define the 3 functions + globals and print NOTHING.
out="$(set -u; source scripts/layout.sh; echo "DEFINED")"
[ "$out" = "DEFINED" ] && echo "OK: source prints nothing" || echo "FAIL: source printed [$out]"
# The functions exist after sourcing:
(set -u; source scripts/layout.sh; type lp_disp_width lp_viewport _lp_strip_styles >/dev/null) \
  && echo "OK: 3 functions defined" || echo "FAIL: functions missing"
# LPV_* globals are the ONLY module-level state (no stray globals):
(set -u; source scripts/layout.sh; compgen -v | grep -E '^(LPV_|CURRENT_DIR)') | sort
# Expected: source is silent; 3 functions defined; only CURRENT_DIR + LPV_* globals exist.
```

### Level 4: Full suite (no regression — the lib is unreferenced)

```bash
cd /home/dustin/.config/tmux/plugins/tmux-livepicker
bash tests/run.sh
# Expected: the same count as before passes. layout.sh is NOT sourced by any shipped script
# in this subtask (M2/M3 wire it), so it cannot affect the suite. If a test fails, it is
# unrelated to this change — triage separately.
```

## Final Validation Checklist

### Technical Validation

- [ ] `bash -n scripts/layout.sh` clean; `shellcheck` 0 findings.
- [ ] `_lp_strip_styles`, `lp_disp_width`, `lp_viewport` defined; 5 `LPV_*` globals present.
- [ ] No driver line; no tmux calls; no source-time output (L3).
- [ ] L2 smoke: pass~=30 fail=0 (all 9 width+viewport cases).

### Feature Validation

- [ ] `lp_disp_width` strips `#[…]` then counts codepoints (icon=1, ASCII=1, styled tabs correct).
- [ ] `lp_viewport` clamps scroll=0 when the list fits; scroll-into-view keeps highlight visible;
      hidden_left+hidden_right is the `+N>` %d; single-wide-tab + empty-list edge cases handled.
- [ ] Separator width arg (sep=2) correctly changes the fit.
- [ ] `LPV_END=-1` correctly signals an empty slice.

### Code Quality Validation

- [ ] Uses `${#var}` (NOT `wc -m`) and the manual strip loop (NOT the broken glob).
- [ ] Matches rank.sh's sourced-lib shape (header, set -u, CURRENT_DIR, no driver, no side effects).
- [ ] Pure math (no tmux, no get_state/opt_*); args-in, LPV_*-globals-out.
- [ ] Incremental cumwidth (O(n) scroll-into-view, not O(n²)).
- [ ] `local` everywhere; tabs; `set -u`-safe (inputs sanitized).

### Documentation & Deployment

- [ ] Header comment documents the two measurement traps (wc -m locale; broken glob strip).
- [ ] No README/CHANGELOG change (Mode A — internal lib; README sync is P4.T1).
- [ ] Not wired into any consumer in this subtask (M2/M3 own the wiring).

---

## Anti-Patterns to Avoid

- ❌ Don't use `wc -m` for width — locale-dependent (C→bytes) AND spawns a subshell per call.
  Use bash's `${#var}` (builtin, codepoints under UTF-8). (research FINDING 1.)
- ❌ Don't use the naive `${var//\#\[[^]]*\]/}` glob strip — it eats visible text (glob `*` is
  a wildcard, not a quantifier). Use the manual case-loop `_lp_strip_styles`. (FINDING 2.)
- ❌ Don't use `sed`/`perl` for the strip on the render path — spawns a process per tab.
- ❌ Don't add a `*_main "$@"` driver — this is a SOURCED library (only entry-point scripts
  have drivers). Sourcing must be side-effect-free.
- ❌ Don't call `tmux` / `get_state` / `opt_*` inside layout.sh — it is PURE MATH. The caller
  passes T/scroll/highlight/sep; lp_viewport returns numbers via LPV_*. (FINDING 5.)
- ❌ Don't resolve the "active indicators" width inside lp_viewport — it's circular (indicator
  presence depends on hidden counts). Take T as given; let the renderer (M2) reserve indicator budget.
- ❌ Don't hardcode `sep=1` inside cumwidth — take SEP_WIDTH as an arg (plain=1, ws=variable).
- ❌ Don't use `extglob` for the strip — it's a global shell-option change (must save/restore);
  the manual loop has no global state and is equally fast. (FINDING 2.)
- ❌ Don't add a wide-glyph (wcwidth) check — YAGNI; session names are typically ASCII; §19
  doesn't require it. Document the limitation instead.
- ❌ Don't wire layout.sh into renderer.sh/input-handler.sh here — M2/M3 own the wiring. Ship
  the lib unreferenced (it cannot regress the suite).
- ❌ Don't forget to reset `LPV_*` at the top of every `lp_viewport` call (no stale outputs).
- ❌ Don't let the scroll-into-view loop be O(n²) — use the incremental `cw -= w[scroll]+sep`
  update (O(n) total).

---

## Confidence Score

**9 / 10** for one-pass success. Rationale: the complete file body is given verbatim (every
function + the verified algorithm); both measurement traps (`wc -m` locale; broken glob strip)
are corrected with the proven alternatives (`${#var}` builtin; manual case-loop) and backed by
the empirical research; the viewport math is validated on all 7 cases (+ width cases + edge
cases) in an executable L2 smoke that asserts ~30 points; the lib is pure (no tmux, no state)
and unreferenced by any shipped script, so the blast radius is nil (worst case: a smoke
assertion fails with a got/want diff, not a suite regression); and the perf is verified
(21 ms / 200 tabs, well under the §18 budget). Residual risk: a bash-ism typo in the
verbatim body — caught by `bash -n`/`shellcheck`/the L2 smoke.
