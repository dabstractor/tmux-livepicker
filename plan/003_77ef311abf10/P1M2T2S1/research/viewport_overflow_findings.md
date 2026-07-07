# Research — P1.M2.T2.S1: viewport windowing + overflow indicators in the renderer plain path (PRD §19)

> All findings verified LIVE on tmux 3.6b / bash 5.3 against the CURRENT working
> tree (plan 003: rank.sh + layout.sh + the new options/state keys all COMPLETE).
> Bug/feature context: PRD §19 §3.32 (viewport/scroll) + §3.33 (overflow indicators).
> The plain render path this builds on is established by the in-flight P1.M2.T1.S1
> (§19 3-branch restructure) — its PRP is treated as a CONTRACT.

---

## FINDING 1 — `lp_viewport` interface + behavior (verified)

`scripts/layout.sh::lp_viewport RANKED_LIST T SCROLL HIGHLIGHT [SEP_WIDTH=1]` sets
globals: `LPV_SCROLL LPV_START LPV_END LPV_HIDDEN_LEFT LPV_HIDDEN_RIGHT`.
- Fits (total ≤ T) → LPV_SCROLL=0, LPV_START=0, LPV_END=n-1, all hidden=0.
- Overflow → scroll-into-view (highlight always in slice), LPV_END = largest idx with
  cumwidth(scroll,end) ≤ T. LPV_HIDDEN_LEFT=scroll, LPV_HIDDEN_RIGHT=n-1-end.
- LPV_END = -1 signals an EMPTY slice (n=0 or T≤0): loop `for ((i=START;i<=END;i++))`
  is a no-op.
- Pure bash, no tmux, no state reads. The caller computes T (layout.sh does NOT resolve
the indicator circle — FINDING 5 of the layout research; the RENDERER does).

Verified cases: fits→all-visible/hidden=0; overflow T=10 tabs-w-5 → [0,0] hidden_R=4
(5+1+5=11>10); overflow hl=3 → scroll-into-view to [3,3] hidden_L=3 hidden_R=1. ✓

---

## FINDING 2 — the indicator-presence CIRCLE + two-pass resolution (verified, converges)

PRD §3.32: `T = client_width − query_block − active_indicators`. But:
- indicator presence depends on hidden counts (left iff scroll>0; right iff hidden>0);
- hidden counts come from `lp_viewport(T)`;
- T depends on indicator width. ← CIRCULAR.

**Resolution (layout research FINDING 5 says the renderer owns this): probe + converge.**
1. `T0 = client_width − query_block` (NO indicator reservation).
2. **Probe**: `lp_viewport list T0 scroll hl sep`.
   - If `LPV_HIDDEN_LEFT + LPV_HIDDEN_RIGHT == 0` → fits entirely → NO indicators, use
     the probe slice (scroll already clamped to 0 by lp_viewport). DONE (1 call).
   - Else → overflow. The right indicator IS present (overflow ⟺ hidden>0).
3. **Resolve** (bounded loop, converges in ≤2 iterations): reserve the indicator width
   the current belief says is active, re-call lp_viewport, re-check presence:
   - left_present = (LPV_HIDDEN_LEFT > 0); right always present (overflow).
   - `right_str = ${opt_overflow_right_format//%d/$(LPV_HIDDEN_LEFT+LPV_HIDDEN_RIGHT)}`.
   - `ind_w = lp_disp_width(left_str) + lp_disp_width(right_str)`; `T = T0 − ind_w`.
   - `lp_viewport list T scroll hl sep`; if new LPV_HIDDEN_LEFT>0 == old left_present →
     converged; else left flipped off→on, loop once more (it cannot flip back: T only
     shrinks → scroll only grows → hidden_left monotonic).

**Convergence proof (why ≤2 iterations):** right-present is monotonic (smaller T ⇒ weakly
more overflow ⇒ stays present). left-present is monotonic off→on (smaller T ⇒ scroll-into-
view weakly advances scroll ⇒ hidden_left weakly grows). So after the probe, at most ONE
off→on flip can occur → ≤2 lp_viewport calls in the resolve loop (≤3 total worst case;
common case is 1–2). Verified live: 8 tabs w=5, T0=30 → probe [0,4] hR=3; reserve right_w=3
→ T=27 → [0,3] hR=4, left stays off → CONVERGED in 2 calls. ✓

The right indicator's `%d` is recomputed from the FINAL (converged) hidden counts (it can
grow as T shrinks: 3→4 in the test). Use the converged counts for the rendered `%d`.

---

## FINDING 3 — `%d` substitution in opt_overflow_right_format

`opt_overflow_right_format` default `+%d>`. Substitute via bash parameter expansion:
`${fmt//%d/$total_hidden}` (literal global replace; single `%d`). Verified:
- `+%d>` + 12 → `+12>` (width 4). `+%d>` + 3 → `+3>` (width 3).
- A custom format `+%d hidden>` + 12 → `+12 hidden>`.
- A format with NO `%d` (e.g. `>>`) → used unchanged (no-op substitution).
Do NOT use printf for this (printf reinterprets `%` and `\\` in the format — the user's
format string is data, not a printf template). `${fmt//%d/$n}` is the safe literal swap.

---

## FINDING 4 — indicator widths via lp_disp_width

Measure the indicator strings with the SAME `lp_disp_width` used for tabs (strip #[…],
count codepoints), so the budget is in display columns:
- left `<` → width 1. right `+12>` → 4. right `+3>` → 3. right `+128>` → 5.
Use `lp_disp_width "$left_str"` and `lp_disp_width "$right_str"`. (The indicators are
plain ASCII in the default, but a custom format could contain anything; measure, don't
assume.)

---

## FINDING 5 — query_block_width (per query state)

PRD §3.32: "width(query block) = len(icon) + len(query) + gap".
- **Query-ACTIVE** (`-n FILTER`): icon (1 codepoint iff `opt_nerd_fonts=on`, else 0) +
  `lp_disp_width "$FILTER"` (the raw query; == `${#FILTER}` since FILTER has no styles) +
  `opt_query_gap` (the space count). Verified: icon=1 + "log"=3 + gap=2 = 6.
- **Query-EMPTY** (`-z FILTER`): NO query block is rendered (no icon/query/gap) →
  query_block_width = **0**. So `T0 = client_width − 0 = client_width`.
- **No-match** (FLEN==0): no tabs → no viewport/indicators (branch (c) returns early).
The icon is `$icon` (empty when nerd_fonts off) → its width is `${#icon}` (0 or 1).

---

## FINDING 6 — CRITICAL: width=0 degradation (STATE_CLIENT_WIDTH unwritten today)

`STATE_CLIENT_WIDTH` is NOT yet written by anyone (P1.M3.T1 captures it at activate).
`get_state "$STATE_CLIENT_WIDTH" "0"` returns `"0"` today. With width=0:
- `T0 = 0 − query_block ≤ 0` → `lp_viewport(T≤0)` returns an EMPTY slice (LPV_END=-1,
  all tabs "hidden"). That would render NO tabs + a right indicator showing ALL hidden —
  WRONG (when the width is unknown, hiding everything is broken).

**Resolution: GUARD on `width > 0`.** When width ≤ 0, SKIP windowing entirely — render ALL
filtered tabs with NO indicators (the P1.M2.T1.S1 legacy behavior). tmux clips the
overflow at the line edge (same as today). Windowing activates automatically once P1.M3.T1
captures the width. This mirrors how P1.M2.T1.S1's status-justify emulation degrades to
left when width=0. Verified: `lp_viewport list 0 0 0 1` → START=0 END=-1 (empty).

---

## FINDING 7 — overflow SUSPENDS status-justify in query-empty (PRD §3.30)

PRD §3.30 (query-empty): "If the tabs fit: they are justified per status-justify. If the
tabs overflow: justification becomes moot (every column is occupied); the tabs flow
left-to-right from column 0 and the overflow indicators below apply."

So in branch (a) (query-empty):
- **No overflow** (fits, no indicators) → P1.M2.T1.S1's justify emulation (leading pad).
- **Overflow** (indicators present) → SUSPEND justify (no pad); emit
  `[left_ind]<tabs>[right_ind]` from column 0. The left indicator goes at column 0
  (there's no gap in query-empty), before the first tab.

This means the windowing must branch the query-empty emit on whether indicators are present.

---

## FINDING 8 — indicators are CHROME (PRD §3.33): styled FG/BG, never highlighted

- **Left indicator**: `opt_overflow_left` (default `<`), presence-only (no count). Placed
  immediately after the gap (query-active) / at column 0 (query-empty-overflow), BEFORE the
  first visible tab.
- **Right indicator**: `opt_overflow_right_format` with `%d`→total hidden (left+right
  combined). Placed at the far right of the tab region (immediately after the last visible
  tab — the viewport slice fills T, so the last tab is at the right edge).
- **Styling**: `#[fg=$FG,bg=$BG]${indicator}#[default]` (plain-mode chrome colors). They
  are NEVER highlighted (no HFG/HBG), NEVER counted as tabs (not in the %d, not in the
  tab-join separator). Adjacent to the tab block (no inter-tab space between an indicator
  and the neighboring tab — only the single-space separator BETWEEN tabs).
- Layout: `< …visible tabs… +N>` (both can show at once; neither when it all fits).

---

## FINDING 9 — DISJOINT-but-SEQUENCED from the parallel P1.M2.T1.S1

Both tasks edit `scripts/renderer.sh`'s PLAIN path — but **sequentially**, not concurrently.
P1.M2.T1.S1 (§19 3-branch restructure) is "Ready"/in-flight and lands FIRST; my task builds
on its output. The implementer of P1.M2.T2 runs AFTER P1.M2.T1.S1 completes, so my
`oldText` anchors match the P1.M2.T1.S1 output (quoted verbatim from its PRP's Task-3
newText). No merge conflict (T1 before T2 in the plan).

My edits are TARGETED on the P1.M2.T1.S1 output (do NOT duplicate its no-match branch,
option-read prefix, or the ws path):
- Insert viewport-resolution BEFORE the "Build the tab segments" loop.
- Change the loop bounds from `${!filtered[@]}` to `((i=vis_start; i<=vis_end; i++))`.
- Branch (a): add overflow-suspends-justify + indicators.
- Branch (b): add indicators.
- (c) no-match: UNCHANGED (no tabs → no viewport).

---

## FINDING 10 — no committed test (P1.M4.T1 owns the layout suite)

`tests/test_layout.sh` (§15.28 layout/ranking/scroll) is P1.M4.T1's milestone. This task
validates via a throwaway smoke (then delete), matching P1.M2.T1.S1's discipline. The smoke
seeds `@livepicker-list/filter/index/scroll/client-width`, runs the renderer, asserts the
slice + indicators for fits / overflow-left / overflow-right / both / width=0-degraded.

---

## FINDING 11 — tab-building loop bounds change + highlight always visible

The P1.M2.T1.S1 loop is `for i in "${!filtered[@]}"` (all tabs). My change:
`for ((i=vis_start; i<=vis_end; i++))` (the visible slice). The highlight `cidx` is
guaranteed to be in `[vis_start, vis_end]` because lp_viewport's scroll-into-view keeps the
highlight visible (and the width=0 degraded path renders ALL tabs, so cidx ∈ [0,FLEN-1]).
So the `if [ "$i" -eq "$cidx" ]` highlight styling in the loop works unchanged.

LPV_END=-1 (empty slice, degenerate T≤0) → the loop is a no-op → no tabs rendered (only
indicators, if any). This is the width=0-degraded case's sub-edge; the width=0 guard
(FINDING 6) short-circuits before reaching here in practice.

---

## FINDING 12 — exact anchors + the %d recompute timing

The P1.M2.T1.S1 plain path (the contract) builds `tabs` then emits `${pad}${tabs}` (a) /
`${icon}${query}${gap}${tabs}` (b). My windowing:
- Computes `vis_start/vis_end/left_str/right_str` from lp_viewport (FINDING 2).
- Builds `tabs` from the slice (FINDING 11).
- `left_str` / `right_str` are the FINAL indicator strings (recomputed from the converged
  LPV_HIDDEN_* counts AFTER the resolve loop). The `%d` uses the converged total hidden.
- Emits with indicators inserted: (a) overflow → `${left}${tabs}${right}` (no pad); (a)
  fits → `${pad}${tabs}`; (b) → `${icon}${esc_filter}#[default]${gap}${left}${tabs}${right}`.

Indent: TABS. The plain path is 1-tab inside render(); the viewport block + loop bodies at
2 tabs. SC2034 (unused `out`/`seg`) is file-wide disabled in renderer.sh.
