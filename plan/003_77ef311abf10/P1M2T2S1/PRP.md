# PRP — P1.M2.T2.S1: viewport windowing + overflow indicators in the renderer plain path (PRD §19 §3.32/§3.33)

> **Scope**: Build on the §19 plain render path (established by the in-flight P1.M2.T1.S1)
> to (a) **window** the ranked tab list by `@livepicker-scroll` so only the visible slice
> renders, and (b) render **overflow indicators** — `<` on the left when `scroll>0`, and
> `+N>` on the right where `N` is the TOTAL hidden tabs (left+right combined) — whenever the
> tab region overflows the available width. Both query states (empty / active) get the
> windowed viewport; no-match is unchanged (no tabs). The available width `T` is
> `client_width − query_block − active_indicators`, recomputed every redraw, with the
> indicator-presence circular dependency resolved by the renderer (probe + converge).
>
> **Builds on P1.M2.T1.S1** (the §19 3-branch plain path: query-empty / query-active /
> no-match; reads `STATE_SCROLL`/`STATE_CLIENT_WIDTH` but does not slice). This task adds
> the slicing + indicators. The window-status (§17) path is untouched (P1.M2.T3 reworks it).

---

## Goal

**Feature Goal**: The renderer's plain path shows a scrollable viewport of the ranked tabs:
only tabs in `[scroll, scroll+T)` render, with a `<` left indicator (when `scroll>0`) and a
`+N>` right indicator (`N` = total hidden, left+right combined) when the region overflows.
Both indicators can show at once (`< …visible tabs… +N>`); neither when everything fits.
They are chrome (styled `@livepicker-fg`/`bg`), never highlighted, never counted as tabs.
When `@livepicker-client-width` is unset (P1.M3.T1 not landed), windowing degrades
gracefully to the full-list render (no indicators) so the renderer is correct today and
activates windowing automatically once the width is captured.

**Deliverable**: Targeted edits to `scripts/renderer.sh` (extend the plain-path locals;
replace the tab-build + branch-(a)/(b) region with the windowed version). **No new files,
no committed test** (P1.M4.T1 owns `test_layout.sh`).

**Success Definition**:
- Tabs fit → all render, NO indicators; query-empty still justifies (P1.M2.T1.S1 behavior);
  query-active still pins `<icon><query><gap><tabs>` at column 0.
- Tabs overflow → only the `[vis_start, vis_end]` slice renders; `<` shows iff `scroll>0`;
  `+N>` shows with `N` = total hidden (left+right); query-empty SUSPENDS justify and flows
  `<tabs+N>` from column 0; query-active emits `<icon><query><gap><<tabs>+N>`.
- `N` reflects the converged hidden count (it grows as indicator width is reserved).
- `client_width=0` (unset) → full-list render, no indicators (legacy; correct today).
- The window-status path is byte-identical.
- Throwaway smoke passes (fits / left-only / right-only / both / width=0-degraded);
  `tests/run.sh` stays green.

## User Persona (if applicable)

**Target User**: The end user with many sessions. Also the §15.28 layout tests (P1.M4.T1).

**Use Case**: "I have 40 sessions. The ones that don't fit get a `+12>` on the right telling
me how many are off-screen. When I arrow over, they scroll into view and a `<` appears on
the left." (PRD §3 user story.) The `12` is the TOTAL hidden, not split by side.

**Pain Points Addressed**: Without windowing, a long session list overflows the status line
and tmux clips it silently (no indication more exist). The indicators + scroll give the user
awareness + navigation of the full list within the available width.

## Why

- **PRD §19 §3.32/§3.33 mandate it.** The viewport + overflow indicators are the §19
  layout's answer to "more sessions than fit". §3.32 specifies the scroll state + the
  `T = client_width − query_block − indicators` width; §3.33 specifies the `<` / `+N>`
  indicators (total hidden, chrome-styled).
- **`lp_viewport` is COMPLETE (P1.M1.T2).** The slice + hidden-count math is done; this
  task is the renderer-side consumption + the indicator-circle resolution (which layout.sh
  deliberately leaves to the renderer — layout research FINDING 5). Verified live.
- **Cheap on the hot path.** lp_viewport is O(n) pure bash (~21ms for 200 tabs); the
  resolve loop runs ≤2 iterations (FINDING 2). Well within the §18 <50ms renderer budget.
  No per-tab tmux round-trip; width from the cached `STATE_CLIENT_WIDTH`.
- **Graceful today.** The `client_width=0` guard means the feature is inert until P1.M3.T1
  captures the width — no broken render in the meantime.
- **Sequenced, not conflicting, with P1.M2.T1.S1.** T1 (§19 restructure) lands first; this
  task's `oldText` anchors match T1's output (quoted verbatim from its PRP). The
  window-status path + the no-match branch are untouched.

## What

1. **Extend the plain-path locals** (add the viewport/indicator variables).
2. **Replace the tab-build + branch region** (P1.M2.T1.S1's "# Build the tab segments …"
   through the branch-(b) printf) with the windowed version:
   - Read `STATE_CLIENT_WIDTH` → `width`. If `width ≤ 0`: no windowing (vis = all, no
     indicators). Else compute `query_block_width` (icon+query+gap for query-active; 0 for
     query-empty), `T0 = width − query_block`, and resolve the viewport (probe + converge).
   - Build `tabs` from the visible slice `[vis_start, vis_end]` (not all filtered).
   - Build styled `left_ind` / `right_ind` (`%d` → converged total hidden).
   - Branch (a) query-empty: overflow → `${left_ind}${tabs}${right_ind}` (justify moot);
     fits → P1.M2.T1.S1's justify emulation (`${pad}${tabs}`).
   - Branch (b) query-active: `${icon}${esc_filter}…${gap}${left_ind}${tabs}${right_ind}`.
3. **Do NOT change**: the no-match branch (c), the option-read prefix (incl. SHOW_COUNT —
   the ws path still uses it), the window-status path, the header sources, the driver, any
   other script, or any state writes (the renderer stays PURE — it reads `STATE_SCROLL` for
   the slice but does NOT write it; scroll-state management is P1.M3.T2's job).

### Success Criteria

- [ ] Plain path reads `STATE_CLIENT_WIDTH`; guards windowing on `width > 0`.
- [ ] `lp_viewport` called with `T0` (probe) then `T` (resolved); slice from LPV_START/END.
- [ ] Tab loop is `for ((i=vis_start; i<=vis_end; i++))` (the visible slice), not all filtered.
- [ ] `<` indicator renders iff `LPV_HIDDEN_LEFT > 0`; `+N>` renders iff total hidden > 0;
      `N` = converged total hidden; indicators styled FG/BG (chrome), never highlighted.
- [ ] Query-empty overflow SUSPENDS justify (flows from column 0 with indicators); fits
      keeps the P1.M2.T1.S1 justify emulation.
- [ ] `client_width=0` → full-list render, no indicators (legacy; correct pre-P1.M3.T1).
- [ ] Window-status path + no-match branch byte-identical.
- [ ] `bash -n` + `shellcheck` clean; throwaway smoke passes; `tests/run.sh` green.

## All Needed Context

### Context Completeness Check

_Pass_: The implementer needs (a) the two verbatim edits (oldText = the P1.M2.T1.S1 output,
newText = windowed — both below), (b) the indicator-circle resolution algorithm (probe +
converge; FINDING 2), (c) the width=0 degradation guard (FINDING 6), (d) the overflow-
suspends-justify rule (FINDING 7), (e) the indicator chrome styling + `%d` substitution.
All live-proven in research/viewport_overflow_findings.md.

### Documentation & References

```yaml
# MUST READ — the empirical ground-truth for THIS task (12 verified findings)
- docfile: plan/003_77ef311abf10/P1M2T2S1/research/viewport_overflow_findings.md
  why: FINDING 1 (lp_viewport interface + verified slice/hidden behavior); FINDING 2 (the
       indicator CIRCLE + the probe+converge resolution — convergence proof, ≤3 lp_viewport
       calls worst case, ≤2 common; the %d recomputes from converged counts); FINDING 3 (%d
       via ${fmt//%d/$n}, NOT printf); FINDING 4 (indicator widths via lp_disp_width); FINDING
       5 (query_block_width = icon+query+gap for active, 0 for empty); FINDING 6 (CRITICAL:
       width=0 -> lp_viewport returns empty slice -> renderer MUST skip windowing, render all,
       no indicators; STATE_CLIENT_WIDTH unwritten until P1.M3.T1); FINDING 7 (overflow
       SUSPENDS status-justify in query-empty — PRD §3.30); FINDING 8 (indicators are chrome:
       FG/BG styled, never highlighted, never counted; left before first tab, right after
       last); FINDING 9 (sequenced on P1.M2.T1.S1; oldText = its output); FINDING 10 (no
       committed test — P1.M4.T1 owns test_layout.sh); FINDING 11 (loop bounds change; cidx
       always in slice via scroll-into-view); FINDING 12 (exact anchors + %d timing).
  critical: FINDING 2 (the resolution algorithm) + FINDING 6 (the width=0 guard) + FINDING 7
            (overflow suspends justify) are the three things most likely to be gotten wrong.

# MUST READ — the CONTRACT this task builds on (the §19 plain path; assume it is implemented)
- docfile: plan/003_77ef311abf10/P1M2T1S1/PRP.md
  why: P1.M2.T1.S1 (in-flight, lands FIRST) restructured the plain path into 3 §19 branches
       (query-empty/active/no-match), dropped SHOW_COUNT use, read STATE_SCROLL/STATE_CLIENT_WIDTH
       (but did not slice), and sourced layout.sh. This task's oldText anchors are VERBATIM from
       its Task-3 newText. The implementer runs AFTER P1.M2.T1.S1 lands.
  section: "Implementation Patterns / Task 3 — the new plain-path body"

# MUST READ — PRD §19 (the layout spec: viewport + overflow indicators)
- docfile: PRD.md
  why: §3.32 (T = client_width − query_block − active indicators; measure tab display width
       via lp_viewport; @livepicker-scroll = first visible idx; clamp scroll=0 when fits);
       §3.33 (right +N> with %d=TOTAL hidden left+right combined; left < presence-only when
       scroll>0; both can show < …tabs… +N>; neither when fits; chrome FG/BG, never
       highlighted/counted); §3.30 (query-empty: overflow -> justify moot, flow from col 0);
       §3.35 (width from cached @livepicker-client-width, no per-keystroke tmux round-trip).
  section: "§19 Status-line layout" (§3.30/§3.32/§3.33/§3.35)

# MUST READ — lp_viewport (the slice math this consumes) + lp_disp_width
- file: scripts/layout.sh
  why: lp_viewport RANKED_LIST T SCROLL HIGHLIGHT [SEP=1] sets LPV_SCROLL/START/END/
       HIDDEN_LEFT/HIDDEN_RIGHT. LPV_END=-1 = empty slice. Pure bash, no tmux. The caller
       computes T (layout research FINDING 5: layout.sh does NOT resolve the indicator circle
       — the renderer does). lp_disp_width STRING strips #[…] + counts codepoints (FINDING 1:
       NOT wc -m — locale-dependent). Sourced by renderer.sh (P1.M2.T1.S1 added the source).
  gotcha: lp_viewport with T≤0 returns an empty slice (all hidden) — the renderer's width=0
          guard (FINDING 6) prevents reaching this with a broken result.

# MUST READ — the option accessors (overflow indicators + query block) — all COMPLETE
- file: scripts/options.sh
  why: opt_overflow_left (default "<"); opt_overflow_right_format (default "+%d>"); opt_nerd_fonts
       (default "on"); opt_search_icon (default $'\uf002', width 1); opt_query_gap (default "2").
       opt_fg/bg/highlight_fg/highlight_bg (the chrome + tab colors).
  gotcha: opt_overflow_right_format is DATA (a format string) — substitute %d with ${fmt//%d/$n}
          (literal), NOT printf (which would reinterpret % and \ in the user's format).

# MUST READ — the state keys (scroll + client-width) — COMPLETE (P1.M1.T3.S2)
- file: scripts/state.sh
  why: STATE_SCROLL (@livepicker-scroll; written by input-handler P1.M3.T2; read here for the
       slice — NOT written by the renderer, which stays pure); STATE_CLIENT_WIDTH
       (@livepicker-client-width; captured at activate P1.M3.T1; UNWRITTEN today -> get_state
       returns "0" -> the width=0 guard degrades to full-list render). get_state/set_state.

# MUST READ — the renderer load-bearing rules (§P6) + the file being modified
- docfile: plan/003_77ef311abf10/architecture/codebase_patterns.md
  why: §P6 — ONE line no trailing newline (`printf '%s' "$out"` QUOTED); #[default] after every
       segment; NO set -e; render||fallback-red; #() stdout NOT re-parsed for #{} (=> query/
       indicator text doubles #); PURE+FAST (option reads + pure-bash ONLY; one status-justify
       read allowed; width from cached STATE_CLIENT_WIDTH, NEVER display-message per-keystroke).
  section: "P6 — Renderer rules (renderer.sh)"
- file: scripts/renderer.sh
  why: render()'s plain path (P1.M2.T1.S1 output) is the region edited. The ws early-return
        (above) + the no-match branch + the option-read prefix are UNTOUCHED. The header already
        sources layout.sh (P1.M2.T1.S1). SC2034 is file-wide disabled (unused locals ok).
  gotcha: the `printf '%s'` MUST be quoted ("$out" / "${left_ind}${tabs}…") — unquoted word-splits.

# Reference — the test landscape (NOT modified; for the suite-green claim)
- file: tests/test_functional.sh / tests/test_responsiveness.sh
  why: P1.M2.T1.S1 updated their renderer assertions (dropped `query>`). This task changes the
        tab COUNT shown only when overflow (which needs client_width set — not set in those
        tests -> full-list render -> their assertions still hold). Verify in L2.
```

### Current Codebase tree

```bash
tmux-livepicker/
  scripts/
    renderer.sh   # MODIFY: plain path — +viewport windowing (slice by STATE_SCROLL) + overflow
                  #   indicators (< / +N>); width=0 degrades to full-list. ws path untouched.
    layout.sh     # (COMPLETE) lp_viewport / lp_disp_width — consumed (already sourced)
    rank.sh       # (COMPLETE) lp_rank — consumed (the ranked list)
    options.sh    # (COMPLETE) opt_overflow_left/right_format/nerd_fonts/search_icon/query_gap — consumed
    state.sh      # (COMPLETE) STATE_SCROLL/STATE_CLIENT_WIDTH — consumed (READ only; no writes)
    ... (utils/livepicker/input-handler/preview/restore)  # UNCHANGED
    # NOTE: P1.M2.T1.S1 (lands FIRST) restructured the plain path this builds on. No file conflict
    #       (sequential: T1 then T2). P1.M3.T1 (later) writes STATE_CLIENT_WIDTH -> activates windowing.
  tests/          # UNCHANGED (test_layout.sh is P1.M4.T1; validate via throwaway smoke)
```

### Desired Codebase tree with files to be added and responsibility of file

```bash
scripts/renderer.sh  # plain path: ranked tabs windowed by scroll + overflow indicators (< left, +N> right);
                     #   width=0 degrades to full-list. The user-visible scrollable picker line (plain mode).
```

### Known Gotchas of our codebase & Library Quirks

```bash
# CRITICAL (research FINDING 6): STATE_CLIENT_WIDTH is UNWRITTEN today (P1.M3.T1 captures it).
# get_state returns "0". lp_viewport(T≤0) returns an EMPTY slice (all hidden) -> would render
# NO tabs + a "+N>" showing all hidden = BROKEN. GUARD: if width<=0, SKIP windowing — render
# ALL filtered tabs, NO indicators (the P1.M2.T1.S1 legacy behavior). Windowing auto-activates
# once P1.M3.T1 lands. This is non-negotiable for correctness today.

# CRITICAL (research FINDING 2): the indicator circle. T depends on indicator presence; presence
# depends on hidden counts; counts come from lp_viewport(T). Resolve: probe at T0 (no indicators);
# if no overflow -> done; else reserve indicator width, re-call lp_viewport, re-check left presence
# (converges <=2 iters; right is monotonic-once-overflow; left monotonic off->on). The %d in +N>
# is recomputed from the CONVERGED counts (it can grow as T shrinks).

# CRITICAL (research FINDING 7): query-empty overflow SUSPENDS status-justify (PRD §3.30: "if the
# tabs overflow: justification becomes moot; flow left-to-right from column 0 + indicators"). So
# branch (a) must branch on indicator presence: overflow -> ${left}${tabs}${right} (no pad); fits
# -> P1.M2.T1.S1's ${pad}${tabs} (justify emulation).

# CRITICAL (research FINDING 3): substitute %d with ${fmt//%d/$n} (literal bash param expansion),
# NOT printf. opt_overflow_right_format is USER DATA; printf would reinterpret % and \ in it.

# CRITICAL: the renderer stays PURE — it READS STATE_SCROLL for the slice but does NOT WRITE it.
# lp_viewport may ADVANCE scroll (scroll-into-view -> LPV_SCROLL); the renderer uses LPV_SCROLL
# only to pick the display slice. Persisting the clamped/advanced scroll is the input-handler's
# job (P1.M3.T2). Do NOT add a set_state in the renderer (violates §P6 purity).

# GOTCHA (research FINDING 8): indicators are CHROME — styled #[fg=$FG,bg=$BG]…#[default], NEVER
# HFG/HBG (never highlighted), NEVER counted in %d or the tab separator. Left goes immediately
# before the first visible tab (after the gap in query-active; at column 0 in query-empty-overflow);
# right immediately after the last visible tab. Layout: < …visible tabs… +N>.

# GOTCHA: query_block_width is 0 in query-EMPTY (no icon/query/gap rendered). Only query-ACTIVE
# subtracts icon+query+gap. (No-match has no tabs -> no viewport.) So T0 = width in query-empty;
# T0 = width - (icon+query+gap) in query-active.

# GOTCHA: lp_viewport takes the RANKED LIST (newline-joined filtered names), T, SCROLL, cidx
# (the highlight), and SEP_WIDTH=1 (plain-mode space). It does NOT take the styled tabs — it
# measures widths internally via lp_disp_width. Pass "$LIST"-ranked... actually pass the JOINED
# filtered names (lp_rank output), NOT $LIST. See Implementation Patterns (build the joined
# ranked list, or pass filtered[] via printf). The highlight arg is cidx (0-based into filtered).

# GOTCHA: the tab loop changes from `for i in "${!filtered[@]}"` to `for ((i=vis_start; i<=vis_end; i++))`.
# cidx is guaranteed in [vis_start,vis_end] (lp_viewport scroll-into-view keeps the highlight
# visible; width=0 degraded path renders all -> cidx in [0,FLEN-1]). So the highlight styling works.

# GOTCHA: `printf '%s' "..."` MUST be quoted everywhere. An unquoted ${left_ind}${tabs}... would
# word-split on the spaces inside the styled segments and shred the line. (§P6.)

# GOTCHA: read opt_overflow_left / opt_overflow_right_format ONCE (hoist before the resolve loop)
# to avoid repeated tmux option reads in the loop (§18 budget; the loop runs <=2x but still).

# STYLE: TABS (whole codebase; shfmt absent). The plain path is 1-tab inside render(); the
# viewport block + loop bodies at 2-3 tabs. SC2034 (unused out/seg) is file-wide disabled.
```

## Implementation Blueprint

### Data models and structure

No data model. The "structure" is the windowed plain path (building on P1.M2.T1.S1's 3 branches):

```
render() [shared reads incl. SHOW_COUNT; ws early-return UNTOUCHED]
 ── plain path (PRD §19, P1.M2.T1.S1 + THIS TASK) ──
 read LIST/FILTER/IDX/SCROLL; esc_filter; mapfile all/filtered(lp_rank); FLEN
 icon/gap
 (c) FLEN==0 -> no-match; return                          [UNCHANGED]
 clamp cidx
 ── NEW: viewport resolution ──
 width = STATE_CLIENT_WIDTH (0 if unset)
 if width<=0: vis=all, no indicators (legacy)             [FINDING 6 guard]
 else: qbw = (query-active? icon+query+gap : 0); T0=width-qbw
       lp_viewport(ranked, T0, SCROLL, cidx, 1)          [probe]
       if total_hidden==0: vis=all (fits), no indicators
       else: resolve loop (reserve ind_w, re-call, converge) -> vis=slice, left_ind/right_ind styled
 build tabs from filtered[vis_start..vis_end] (styled, joined, highlight cidx)
 (a) query-empty: overflow -> left_ind+tabs+right_ind (no pad); fits -> pad+tabs (justify)
 (b) query-active: icon+esc_filter+gap+left_ind+tabs+right_ind
```

### Implementation Tasks (ordered by dependencies)

```yaml
Task 1: MODIFY scripts/renderer.sh — EXTEND the plain-path locals
  - LOCATE (by content): the P1.M2.T1.S1 locals line:
        local out seg i cidx first esc_filter esc_name SCROLL icon gap tabs justify width pad padw tabs_w
  - APPEND the viewport/indicator locals:
        local out seg i cidx first esc_filter esc_name SCROLL icon gap tabs justify width pad padw tabs_w \
               vis_start vis_end left_ind right_ind qbw T0 vp_T th ind_w left_present new_lp ovl ovr_fmt ranked
  - (SC2034 file-wide disabled; declaring generously is safe. `out`/`seg` may be unused now — fine.)

Task 2: MODIFY scripts/renderer.sh — REPLACE the tab-build + branch region with the windowed version
  - LOCATE (by content): from the P1.M2.T1.S1 comment `# Build the tab segments (shared by query-empty
    + query-active)...` through the final branch-(b) printf
    (`printf '%s' "#[fg=$FG,bg=$BG]${icon}${esc_filter}#[default]${gap}${tabs}"`).
  - REPLACE with the verbatim windowed body from Implementation Patterns (viewport resolution +
    windowed loop + branch-(a) overflow-suspend-justify + branch-(b) indicators).
  - PRESERVE: the cidx clamp ABOVE it, the no-match branch (c) ABOVE that, the option-read prefix,
    the ws early-return, the closing `}` of render(), and the driver.
  - oldText anchors are VERBATIM from P1.M2.T1.S1's Task-3 newText (the implementer runs after T1).

Task 3: VALIDATE (L1 grep + L2 full suite + throwaway smoke)
  - RUN: bash -n scripts/renderer.sh ; shellcheck scripts/renderer.sh
  - RUN: grep cross-checks (lp_viewport called; loop is `for ((i=vis_start`; indicators styled FG/BG;
    width=0 guard present; ws path intact).
  - RUN: the throwaway smoke (fits / left-only / right-only / both / width=0-degraded); then DELETE it.
  - RUN: tests/run.sh (expect green — windowing is inert without STATE_CLIENT_WIDTH set, so the
    existing renderer tests see the full-list render; verify in L2).
```

### Implementation Patterns & Key Details

**Task 1 — extend the locals (the oldText is the P1.M2.T1.S1 locals line):**

```bash
# oldText:
	local out seg i cidx first esc_filter esc_name SCROLL icon gap tabs justify width pad padw tabs_w
# newText:
	local out seg i cidx first esc_filter esc_name SCROLL icon gap tabs justify width pad padw tabs_w \
		vis_start vis_end left_ind right_ind qbw T0 vp_T th ind_w left_present new_lp ovl ovr_fmt ranked
```

**Task 2 — the windowed tab-build + branch region (REPLACE the P1.M2.T1.S1 region).** The
`oldText` is the P1.M2.T1.S1 output from `# Build the tab segments` through the branch-(b)
printf. The `newText` (paste verbatim; TAB-indented):

```bash
# newText:
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
		lp_viewport "$ranked" "$T0" "$SCROLL" "$cidx" 1
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
				lp_viewport "$ranked" "$vp_T" "$SCROLL" "$cidx" 1
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
		if [ "$i" -eq "$cidx" ]; then
			seg="#[fg=$HFG,bg=$HBG]${esc_name}#[default]"
		else
			seg="#[fg=$FG,bg=$BG]${esc_name}#[default]"
		fi
		if [ "$first" -eq 1 ]; then
			tabs="$seg"
			first=0
		else
			tabs="$tabs $seg"
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
```

NOTE for the implementer: the `oldText` for Task 2 is the EXACT P1.M2.T1.S1 region (its PRP's
Task-3 newText, from `# Build the tab segments (shared by query-empty + query-active)...`
through `printf '%s' "#[fg=$FG,bg=$BG]${icon}${esc_filter}#[default]${gap}${tabs}"`). Match it
TAB-for-TAB. If P1.M2.T1.S1 hasn't landed, STOP — this task depends on it. Do NOT touch the
no-match branch, the ws path, or the option-read prefix.

### Integration Points

```yaml
CODE:
  - file: scripts/renderer.sh
    change: "+locals; plain-path tab-build+branch region REPLACED with windowed viewport + indicators"
    invariant: "fits -> all tabs, no indicators (P1.M2.T1.S1 behavior); overflow -> slice + </+N>;
               width=0 -> full-list (legacy); ws path + no-match byte-identical"

CONSUMERS / PRODUCERS:
  - P1.M2.T1.S1 (lands FIRST): PRODUCES the §19 3-branch plain path this builds on. SEQUENCE DEP.
  - P1.M3.T1 (client-width capture): will WRITE STATE_CLIENT_WIDTH -> ACTIVATES windowing (today
    width=0 -> degraded full-list render; correct, just not windowed).
  - P1.M3.T2 (scroll-into-view + reset): WRITES STATE_SCROLL (next/prev scroll into view; type/
    backspace/cancel reset to 0). The renderer READS it for the slice; it does NOT write it.
  - P1.M4.T1 (test_layout.sh): the §15.28 layout integration suite (fits/overflow/scroll).

CONFIG / DATABASE / ROUTES: none.
```

## Validation Loop

### Level 1: Syntax & Style (Immediate Feedback)

```bash
cd /home/dustin/.config/tmux/plugins/tmux-livepicker
bash -n scripts/renderer.sh && echo "OK: renderer syntax"
shellcheck scripts/renderer.sh   # expect 0 NEW findings (SC1091/SC2034 are the file's existing disables)
# lp_viewport is called in the plain path:
grep -c 'lp_viewport ' scripts/renderer.sh                  # -> >=1 (the plain-path probe + resolve)
# the tab loop is the windowed form:
grep -c 'for (( i = vis_start' scripts/renderer.sh          # -> 1
# indicators styled as chrome (FG/BG), never HFG/HBG:
grep -c 'fg=$FG,bg=$BG\]${ovl}\|fg=$FG,bg=$BG\]${ovr_fmt' scripts/renderer.sh  # -> present
# %d substitution is the literal param-expansion form (NOT printf):
grep -c 'ovr_fmt//%d/' scripts/renderer.sh                  # -> 2 (in-loop + final)
# width=0 guard present:
grep -c 'width" -gt 0' scripts/renderer.sh                  # -> 1
# STATE_CLIENT_WIDTH + STATE_SCROLL both read:
grep -c 'STATE_CLIENT_WIDTH\|STATE_SCROLL' scripts/renderer.sh   # -> >=2
# ws path + no-match branch intact (query> still in ws block; (no match) still present):
grep -c 'no match' scripts/renderer.sh                      # -> 2 (ws no-match + plain no-match)
# Tabs-not-spaces in the new region:
grep -nP '^ +[^#/]' scripts/renderer.sh | tail -20 && echo "WARN: space-indent" || echo "OK: tabs"
# Expected: syntax clean; shellcheck 0 new findings; lp_viewport called; windowed loop; chrome
# indicators; literal %d; width guard; ws/no-match intact.
```

### Level 2: Full suite (no regression)

```bash
cd /home/dustin/.config/tmux/plugins/tmux-livepicker
tests/run.sh
# Expected: exit 0, all green. RATIONALE: windowing activates ONLY when STATE_CLIENT_WIDTH is set.
# The existing renderer tests (test_functional hash-escape, test_responsiveness) do NOT set
# @livepicker-client-width -> width=0 -> the degraded full-list path renders ALL tabs -> their
# assertions (escaped names, icon presence) still hold. If any renderer test FAILS, check that the
# width=0 guard short-circuits to the full-list render (vis_start=0, vis_end=FLEN-1, no indicators).
```

### Level 3: Throwaway viewport smoke (prove windowing + indicators; then DELETE)

```bash
cat > /tmp/smoke_viewport.sh <<'SMOKE'
#!/usr/bin/env bash
set -u
cd /home/dustin/.config/tmux/plugins/tmux-livepicker
source tests/setup_socket.sh; source tests/helpers.sh
pass_n=0; fail_n=0
has()  { if [ -n "$2" ] && [[ "$2" == *"$1"* ]]; then pass_n=$((pass_n+1)); else fail_n=$((fail_n+1)); echo "FAIL: [$1] absent in [$2]"; fi; }
nohas(){ if [ -n "$2" ] && [[ "$2" != *"$1"* ]]; then pass_n=$((pass_n+1)); else fail_n=$((fail_n+1)); echo "FAIL: [$1] present (should be absent)"; fi; }

mklist() { printf '%s\n' "$@"; }

# --- (1) FITS: width generous -> all tabs, NO indicators (query-active) ---
setup_test "lp-vp-fits"
tmux set-option -g @livepicker-list "$(mklist alpha beta gamma)"
tmux set-option -g @livepicker-filter 'a'
tmux set-option -g @livepicker-index 0
tmux set-option -g @livepicker-scroll 0
tmux set-option -g @livepicker-client-width 200
tmux set-option -g @livepicker-nerd-fonts off
out="$(bash scripts/renderer.sh)"
has "alpha" "$out"; has "beta" "$out"; has "gamma" "$out"   # all visible
nohas "<" "$out"; nohas "+1>" "$out"; nohas "+2>" "$out"     # no indicators
teardown_test

# --- (2) OVERFLOW RIGHT: scroll=0, hl=0 -> +N> on right, NO < ---
setup_test "lp-vp-right"
tmux set-option -g @livepicker-list "$(mklist aaaaa bbbbb ccccc ddddd eeeee)"   # 5 tabs width 5
tmux set-option -g @livepicker-filter 'a'
tmux set-option -g @livepicker-index 0
tmux set-option -g @livepicker-scroll 0
tmux set-option -g @livepicker-client-width 20   # query block ~ icon0+1+gap2=3 -> T0=17; tabs total=29 -> overflow
tmux set-option -g @livepicker-nerd-fonts off
tmux set-option -g @livepicker-query-gap 2
out="$(bash scripts/renderer.sh)"
has "+4>" "$out"   # 5 tabs, only ~3 fit -> ~2 visible, 4 hidden? (count depends on T; assert +N> present)
nohas "<" "$out"   # scroll=0 -> no left indicator
has "aaaaa" "$out" # first tab visible
teardown_test

# --- (3) OVERFLOW BOTH: scroll>0 -> < on left AND +N> on right ---
setup_test "lp-vp-both"
tmux set-option -g @livepicker-list "$(mklist aaaaa bbbbb ccccc ddddd eeeee fffff ggggg)"
tmux set-option -g @livepicker-filter 'g'        # hl=6 (ggggg)
tmux set-option -g @livepicker-index 6
tmux set-option -g @livepicker-scroll 4          # scrolled right
tmux set-option -g @livepicker-client-width 20
tmux set-option -g @livepicker-nerd-fonts off
tmux set-option -g @livepicker-query-gap 2
out="$(bash scripts/renderer.sh)"
has "<" "$out"        # scroll>0 -> left indicator
has "ggggg" "$out"    # highlight visible (scroll-into-view)
# +N> present (overflow): match the +\d+> pattern
[[ "$out" =~ \+[0-9]+\> ]] && pass_n=$((pass_n+1)) || { fail_n=$((fail_n+1)); echo "FAIL: no +N> right indicator"; }
teardown_test

# --- (4) width=0 DEGRADED: full-list render, NO indicators (correct pre-P1.M3.T1) ---
setup_test "lp-vp-degraded"
tmux set-option -g @livepicker-list "$(mklist aaaaa bbbbb ccccc ddddd eeeee)"
tmux set-option -g @livepicker-filter 'a'
tmux set-option -g @livepicker-index 0
tmux set-option -g @livepicker-scroll 0
tmux set-option -gu @livepicker-client-width      # UNSET (simulate P1.M3.T1 not landed)
tmux set-option -g @livepicker-nerd-fonts off
out="$(bash scripts/renderer.sh)"
has "aaaaa" "$out"; has "eeeee" "$out"   # ALL tabs rendered (no windowing)
nohas "<" "$out"; nohas "+1>" "$out"     # no indicators
teardown_test

# --- (5) query-EMPTY overflow: justify suspended, < tabs +N> from column 0 ---
setup_test "lp-vp-empty-overflow"
tmux set-option -g @livepicker-list "$(mklist aaaaa bbbbb ccccc ddddd eeeee)"
tmux set-option -g @livepicker-filter ''
tmux set-option -g @livepicker-index 0
tmux set-option -g @livepicker-scroll 0
tmux set-option -g @livepicker-client-width 20
tmux set-option -g status-justify centre
out="$(bash scripts/renderer.sh)"
has "aaaaa" "$out"; nohas "<" "$out"; [[ "$out" =~ \+[0-9]+\> ]] && pass_n=$((pass_n+1)) || { fail_n=$((fail_n+1)); echo "FAIL: no +N> in empty-overflow"; }
teardown_test

echo "pass=$pass_n fail=$fail_n"; [ "$fail_n" -eq 0 ]
SMOKE
bash /tmp/smoke_viewport.sh; rc=$?; rm -f /tmp/smoke_viewport.sh; exit $rc
# Expected: all pass. (1) fits -> no indicators; (2) right overflow -> +N>, no <; (3) both -> < and +N>,
# highlight visible; (4) width=0 -> full-list, no indicators; (5) query-empty overflow -> indicators,
# justify suspended. The exact +N counts depend on T (recompute); assert PRESENCE + pattern, not exact N.
```

### Level 4: Visual scroll spot-check (optional; confirms the slice + indicators on a real client)

```bash
cd /home/dustin/.config/tmux/plugins/tmux-livepicker
source tests/setup_socket.sh; source tests/helpers.sh
setup_test "lp-vp-visual"; attach_test_client
# 12 sessions, narrow client, scroll mid-list -> expect < ...few tabs... +N>
tmux set-option -g @livepicker-list "$(printf 's%02d\n' $(seq 1 12))"
tmux set-option -g @livepicker-filter ''
tmux set-option -g @livepicker-index 5
tmux set-option -g @livepicker-scroll 4
tmux set-option -g @livepicker-client-width 40
tmux set-option -g status-format[0] "#($(pwd)/scripts/renderer.sh)"
tmux refresh-client -S; sleep 0.3
CLIENT="$(tmux list-clients -F '#{client_name}' | head -1)"
echo "line (expect < ... s05 highlighted ... +N>):"
tmux capture-pane -p -t "$CLIENT" | grep -E 's0[0-9]|<' | head -1 | sed 's/ *$//'
teardown_test
# Expected: a leading < , the highlighted s05, and a trailing +N>. (Visual; assert structure.)
```

## Final Validation Checklist

### Technical Validation
- [ ] `bash -n` + `shellcheck` clean on renderer.sh.
- [ ] Plain-path locals extended; tab-build + branch region replaced with the windowed version.
- [ ] `lp_viewport` called (probe + resolve); tab loop is `for ((i=vis_start; i<=vis_end; i++))`.
- [ ] width=0 guard present (degrades to full-list render, no indicators).
- [ ] Indicators styled FG/BG (chrome), `%d` via `${fmt//%d/$n}` (literal, not printf).
- [ ] ws path + no-match branch + option-read prefix byte-identical.

### Feature Validation
- [ ] (1) Fits → all tabs, no indicators; query-empty still justifies; query-active pins left.
- [ ] (2) Right overflow → `+N>` (N=total hidden), no `<` when scroll=0.
- [ ] (3) Both → `<` and `+N>`; highlight visible (scroll-into-view).
- [ ] (4) width=0 → full-list render, no indicators (correct pre-P1.M3.T1).
- [ ] (5) Query-empty overflow → indicators, justify suspended (flow from column 0).
- [ ] L2 `tests/run.sh` green (windowing inert without STATE_CLIENT_WIDTH set).

### Code Quality Validation
- [ ] Indicator-circle resolved via probe + converge (≤2 iterations; monotonic proof).
- [ ] Renderer stays PURE (reads SCROLL, does NOT write it; no per-keystroke tmux round-trip).
- [ ] `printf '%s' "..."` quoted everywhere; TABS; SC2034 file-wide disabled.
- [ ] Edits confined to the plain-path locals + tab-build/branch region; oldText from P1.M2.T1.S1.

### Documentation & Deployment
- [ ] Inline comments cross-reference PRD §19 (§3.30/§3.32/§3.33) + the FINDING 2/6/7 rules +
      the P1.M3.T1/P1.M3.T2/P1.M4.T1 seams.
- [ ] No README/CHANGELOG edit here (renderer output is internal; the changeset sync is P4.T1).

---

## Anti-Patterns to Avoid

- ❌ Don't run this task before P1.M2.T1.S1 lands — it builds on the §19 plain path. The oldText
  anchors are P1.M2.T1.S1's output. If T1 isn't in, STOP. (research FINDING 9.)
- ❌ Don't drop the width=0 guard. STATE_CLIENT_WIDTH is unwritten today (P1.M3.T1); without the
  guard, lp_viewport(T≤0) returns an empty slice and the renderer shows NO tabs + "+N> all hidden"
  — broken. Guard on `width > 0`; degrade to full-list render. (FINDING 6.)
- ❌ Don't ignore the indicator circle. T depends on indicator presence; presence on hidden counts;
  counts on lp_viewport(T). Probe at T0; if overflow, reserve indicator width + re-resolve (converges).
  Using T0 directly (no reservation) pushes indicators beyond the client width (clipped/lost). (FINDING 2.)
- ❌ Don't use printf for `%d` substitution. opt_overflow_right_format is USER DATA; printf reinterprets
  `%`/`\`. Use `${fmt//%d/$n}` (literal). (FINDING 3.)
- ❌ Don't suspend status-justify in query-empty when the tabs FIT. §3.30: justify is moot ONLY on
  overflow. Branch (a) on indicator presence: overflow → no pad; fits → P1.M2.T1.S1's pad. (FINDING 7.)
- ❌ Don't style indicators with HFG/HBG or count them as tabs. They are CHROME: FG/BG only, never
  highlighted, never in the %d or the inter-tab separator. (FINDING 8.)
- ❌ Don't write STATE_SCROLL from the renderer. The renderer is PURE (§P6); it reads scroll for the
  slice and uses lp_viewport's LPV_SCROLL internally, but does NOT persist it. Scroll-state is
  P1.M3.T2's job (scroll-into-view / reset). (purity gotcha.)
- ❌ Don't touch the ws path, the no-match branch, the option-read prefix (incl. SHOW_COUNT), or the
  header sources. The edit is confined to the plain-path locals + tab-build/branch region.
- ❌ Don't leave any `printf '%s' $unquoted`. Always `"$out"` / `"${left_ind}${tabs}…"`. (§P6.)
- ❌ Don't call opt_overflow_left/right_format inside the resolve loop without hoisting — read them
  ONCE before the loop (§18 budget; the loop runs ≤2x but repeated option reads are wasteful).
- ❌ Don't pass the STYLED tabs to lp_viewport — pass the newline-joined RANKED NAMES (filtered[]);
  lp_viewport measures widths internally via lp_disp_width. (layout.sh API.)
- ❌ Don't add a committed tests/ file — test_layout.sh is P1.M4.T1. Validate via the throwaway L3
  smoke (then delete it).
- ❌ Don't use spaces for indent — TABS only (the file is tab-indented; a space edit won't match).

---

## Confidence Score

**8 / 10** for one-pass success. Rationale: the windowed body is given verbatim (probe + converge
resolution, reusing the COMPLETE `lp_viewport`/`lp_disp_width`/`opt_*`/`get_state` idioms); every
load-bearing behavior is **live-verified** (FINDING 1 lp_viewport slices; FINDING 2 the circle
converges ≤2 iters; FINDING 3 `%d` substitution; FINDING 4 indicator widths; FINDING 6 the width=0
guard; FINDING 7 overflow-suspend-justify). The dependencies are all COMPLETE (rank/layout/options/
state). The residual risks: (1) the `oldText` anchors depend on P1.M2.T1.S1 landing verbatim — if T1's
final phrasing drifted, the edit won't match (mitigated: the anchors are quoted from T1's PRP; the
implementer runs after T1 and can re-quote); (2) the exact `+N` count depends on T (recompute per
case) — the smoke asserts PRESENCE + pattern, not exact N (the count is lp_viewport's job, already
verified); (3) the rare left-flip-0→1 case needs the 3rd lp_viewport call (handled by the convergence
loop, verified monotonic). All residuals are caught by the validation loop (L1 grep + L3 smoke + L2
suite-green). The 2-point deduction reflects the dependency on the in-flight P1.M2.T1.S1 (anchoring
risk) + the algorithmic complexity of the indicator-circle resolution (correct but intricate).
