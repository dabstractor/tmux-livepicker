# Research — P1.M2.T3.S1: Rework window-status path through §19; remove opt_show_count + all SHOW_COUNT logic

> PRD §17 (tab appearance) + §19 (status-line layout). The §17 window-status (ws)
> render path currently BYPASSES §19 (it joins ALL tabs + a SHOW_COUNT suffix in a
> self-contained early-return). This task folds ws into the SAME §19 layout engine
> the plain path uses (P1.M2.T1.S1 + P1.M2.T2.S1), parameterized by a per-style
> "render one tab" strategy + separator, then DELETES `opt_show_count` and every
> SHOW_COUNT reference.

## FINDING 1 — Dependencies + the post-T2 state of renderer.sh (the contract I build on)

All P1.M1 deps are COMPLETE: `lp_rank` (rank.sh), `lp_viewport`/`lp_disp_width`
(layout.sh), the option accessors (options.sh incl. `opt_overflow_left`/
`opt_overflow_right_format`/`opt_nerd_fonts`/`opt_search_icon`/`opt_query_gap`/
`opt_tab_style`), and the state keys (`STATE_TAB_CURRENT_TMPL`/`STATE_TAB_INACTIVE_TMPL`
[§17 cached templates], `STATE_SCROLL`, `STATE_CLIENT_WIDTH`).

**Sequencing (load-bearing):** T1 (Complete) restructured the plain path into §19
3-branches + dropped the plain SHOW_COUNT use. **T2 (in-flight) adds viewport windowing
+ overflow indicators to the PLAIN path.** T2's PRP explicitly leaves the ws early-return,
the option-read prefix (incl. SHOW_COUNT), and the no-match branch UNTOUCHED. So when
THIS task runs (after T2), renderer.sh = current file + T2's two edits (locals extension
+ windowed tab-build/branch region). T2's exact output is quoted verbatim in its PRP
(Task-1 locals line + Task-2 windowed body) — THAT is my oldText source for the
T2-touched regions. The ws block / option-read prefix / first locals / no-match match
the CURRENT file (T2 doesn't touch them).

## FINDING 2 — The two paths differ in exactly TWO things (the factoring seam)

Comparing the current ws early-return vs the plain path (T1+T2), the ONLY differences
are:
1. **How ONE tab renders**: plain = `#[fg=$HFG,bg=$HBG]name#[default]` (current) /
   `#[fg=$FG,bg=$BG]name#[default]` (inactive); ws = swap `__lp_tab__`+`__lp_sentinel__`
   → name in the cached template (current vs inactive per index).
2. **The inter-tab separator**: plain = single space; ws = `window-status-separator`.

EVERYTHING else — the query bar (icon+query+gap), no-match, viewport windowing by
`@livepicker-scroll`, overflow indicators (`<` / `+N>`), query-empty (justify) vs
query-active (pinned-left) — is IDENTICAL. So the refactor parameterizes those two
things and runs both styles through ONE engine. **Do NOT duplicate the layout logic**
(contract).

## FINDING 3 — The shared-engine design (fold ws in; delete the early-return)

Target `render()` flow (one linear §19 engine):

```
read options (FG/BG/HFG/HBG/TYPE — NO SHOW_COUNT)            [Edit B/C: drop SHOW_COUNT]
read LIST/FILTER/IDX/SCROLL; esc_filter; mapfile all/filtered(lp_rank); FLEN; TOTAL
icon / gap
── §17 tab-style decision (NEW, Edit E) ──                                     [before viewport]
  tab_style=opt_tab_style; cur_tpl/reg_tpl=""; sep=" "; sep_w=1
  if ws: read cur_tpl/reg_tpl (STATE_TAB_*); if EITHER empty -> tab_style=plain (§17 Fallback)
         else sep=window-status-separator; sep_w=lp_disp_width("$sep")
(c) no-match (FLEN==0) -> icon+query+(no match); return        [SHARED, unchanged]
clamp cidx
── viewport resolution (T2's block, Edit H: pass "$sep_w" not 1) ──
  width=STATE_CLIENT_WIDTH; if width>0: qbw; T0; lp_viewport(probe, sep_w); converge -> vis_start/vis_end, left_ind/right_ind
  else (width=0): vis=all, no indicators (T2's FINDING 6 guard)
── tab-build loop (Edit F: style conditional + "$sep" join) ──
  for i in [vis_start,vis_end]:
    if ws: seg = swap(cur_tpl|reg_tpl); else: seg = plain styling
    tabs = first ? seg : tabs+$sep+seg
(a) query-empty: overflow -> left_ind+tabs+right_ind; fits -> pad+tabs (justify)
(b) query-active: icon+esc_filter+gap+left_ind+tabs+right_ind
```

The ws early-return block is DELETED (Edit D). `tab_style`/`cur_tpl`/`reg_tpl`/`sep`/
`sep_w` are new locals (Edit G appends them to T2's locals line).

## FINDING 4 — CRITICAL: the viewport separator-width arg must be dynamic (Edit H)

T2's `lp_viewport` calls hardcode the 5th arg (SEP_WIDTH) as `1` (plain's single space).
§19 §3.32 + the contract require ws tabs to be joined by `window-status-separator`, whose
display width is NOT always 1 (a theme may set ` | ` → width 3, or a nerd-font glyph).
So the viewport measurement MUST use `lp_disp_width "$sep"`, not `1`. For plain,
`sep=" "` → `sep_w=1` → identical to T2 (no behavior change). For ws, `sep_w` = the real
separator width → correct windowing. TWO `lp_viewport … 1` calls change to `… "$sep_w"`
(T2's probe at `$T0` + the in-converge-loop call at `$vp_T`). `lp_viewport`'s 5th arg is
`[SEP=1]` (layout.sh API). `lp_disp_width` strips `#[…]` styles first, so a STYLED
separator (e.g. `#[fg=blue] | #[default]`) is measured by its visible glyphs (` | ` = 3)
and emitted verbatim when joining — correct on both axes.

## FINDING 5 — Chrome (query bar / no-match / indicators) uses FG/BG for BOTH styles

§19 says indicators are "styled `@livepicker-fg`/`bg` (plain) or the theme style
(window-status)". The "theme style" for non-tab chrome is under-specified (the cached
templates are TAB-specific — current/inactive — and don't define a chrome style). The
simplest correct reading: chrome (query bar, no-match marker, `<` / `+N>` indicators)
ALWAYS uses `@livepicker-fg`/`bg`, regardless of tab style; ONLY the TABS differ. This
matches the current plain path AND the current ws no-match (both FG/BG). The contract
lists the SHARED elements (query bar/viewport/indicators/separator) without requiring
theme-styled chrome. → No special-casing needed; the T2 chrome code is reused verbatim.
(Theme-styled indicators in ws mode = a documented non-goal / future enhancement.)

## FINDING 6 — §17 Fallback preserved (empty/unresolvable template → plain)

The tab-style decision (Edit E) checks `[ -z "$cur_tpl" ] || [ -z "$reg_tpl" ]` →
`tab_style="plain"` (keeps `sep=" "`, `sep_w=1`). This is the EXACT §17 Fallback the
current ws block implements (and `test_appearance.sh::test_empty_template_falls_back_to_plain`
asserts). My refactor preserves it: with `tab_style=plain`, the tab-build loop takes the
plain styling branch. Verified by tracing test (c) through the new engine (FINDING 7).

## FINDING 7 — test_appearance.sh (plan 002) is BACKWARD-COMPATIBLE (suite stays green)

`tests/test_appearance.sh` has 5 ws tests. ALL use **query-EMPTY** (`lp_appearance_seed
$'…' "" <idx>`) and set **NO `@livepicker-client-width`** (→ `width=0` → T2's degraded
full-list render: `vis_start=0, vis_end=FLEN-1, no indicators`). Tracing each through the
new shared engine:
- (a) highlight uses current format: query-empty + width=0 → tabs only (ws swap + " " join,
  left-justify → no pad) → `assert_contains` the current/inactive styings. PASS.
- (b) separator `|`: query-empty + width=0 → `alpha|beta|gamma` (sep="|", sep_w=1).
  **EXACT** `assert_eq` matches byte-for-byte. PASS.
- (c) empty template → plain fallback: `tab_style` flips to plain → plain styling, " " join.
  PASS.
- (d) plain unchanged: plain styling, " " join. **EXACT** `assert_eq` matches. PASS.
- (e) sentinel end-to-end: activate populates cache; query-empty + width=0 → ws swap +
  separator join; `assert_contains` the styling + names; no `__lp_tab__`/`#{` leak. PASS.

The behavior CHANGE (query bar / viewport / indicators) only manifests when query is
ACTIVE or `client-width` is SET — which test_appearance.sh does NOT exercise. So the
refactor is backward-compatible for the existing suite. `tests/run.sh` stays green.
(The 2 `@livepicker-show-count off` lines in the test become no-ops once opt_show_count
is deleted — cleaned up in Edit I for consistency with "show-count exists NOWHERE".)

## FINDING 8 — SHOW_COUNT removal scope (grep-confirmed, complete)

`grep -rn 'show-count\|SHOW_COUNT\|opt_show_count' scripts/ tests/ README.md`:
- `scripts/options.sh:43` — `opt_show_count()` accessor → **Edit A deletes it**.
- `scripts/renderer.sh` — first locals (`SHOW_COUNT_RAW SHOW_COUNT`), option-read prefix
  (the `case` block), ws no-match branch, ws SHOW_COUNT suffix → **Edits B/C delete the
  prefix; Edit D deletes the ws block (carries its SHOW_COUNT branches)**. The plain path
  has NO SHOW_COUNT use (T1 already dropped it).
- `tests/test_appearance.sh:65,170` — `tmux set-option -g @livepicker-show-count off`
  (no-ops after deletion) + stale comments (lines 43/57/102) → **Edit I cleans them**.
- `README.md:114` — the config-table row `@livepicker-show-count` → **P4.T1's job** (DOCS
  contract: "note in P4 that show-count is removed"); NOT touched here.

After Edits A/B/C/D/I: `show-count`/`SHOW_COUNT`/`opt_show_count` exist NOWHERE in
scripts/ + tests/ (README row is P4's). Matches the contract OUTPUT.

## FINDING 9 — Disjoint from the parallel P1.M2.T2.S1 + sequencing

T2 (in-flight) edits `scripts/renderer.sh` ONLY (plain-path locals + tab-build/branch
region). This task edits `scripts/renderer.sh` (DIFFERENT regions: ws block, option-read
prefix, first locals, + the T2-touched regions parameterized) + `scripts/options.sh`
(delete opt_show_count) + `tests/test_appearance.sh` (stale show-count cleanup). Because
T2 and T3 BOTH edit renderer.sh, they are NOT parallel-safe on that file — T3 MUST run
AFTER T2 lands (T3's oldText for the tab-build loop + viewport = T2's output). The
plan_status sequences them (T1 done → T2 in-flight → T3 researching), and the
parallel_execution_context confirms T2 is the immediately-preceding item. So at
implementation time T3 consumes T2's landed output. No file conflict at runtime
(sequential). test_appearance.sh + options.sh are exclusively T3's.

## FINDING 10 — Style / set -u / shellcheck

renderer.sh: `set -u` inherited; `set -e` OFF; SC1091/SC2034 file-wide disabled (sourced
libs + unused locals). New locals (`tab_style cur_tpl reg_tpl sep sep_w`) declared on the
extended locals line (Edit G) — set -u-safe. `lp_disp_width`/`get_state`/`opt_*` already
sourced. The `${tpl//__lp_tab__/$esc_name}` swap is the SAME literal-substitution idiom
the current ws block uses (no re-scan → a name equal to a placeholder can't corrupt).
TABS throughout (shfmt absent). options.sh: single-line accessor pattern; deleting one
line is clean. test_appearance.sh: TABS, sourced by run.sh.
