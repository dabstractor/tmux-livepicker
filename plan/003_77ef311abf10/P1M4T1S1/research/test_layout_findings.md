# Research — P1.M4.T1.S1: tests/test_layout.sh (renderer layout integration suite)

> Empirical ground-truth captured by running the REAL `scripts/renderer.sh` under
> the project's own isolated-socket harness (`tests/setup_socket.sh` + `helpers.sh`)
> on 2026-07-07. Every output byte below is what the renderer ACTUALLY emits for the
> given seeded state — these are the exact strings `test_layout.sh` asserts against.
> `cat -A` was used to make whitespace + UTF-8 visible (`M-oM-^@M-^B` = bytes
> `ef 80 82` = U+F002, the nerd-font search glyph; `$` would mark line ends — there
> is none because the renderer emits NO trailing newline).

## Methodology

- Reused the shipped harness exactly as `test_appearance.sh` does: `setup_test`
  (fresh isolated `-L` socket + PATH shim + baseline fixtures driver/alpha/beta),
  seed `@livepicker-*` state via `tmux set-option -g`, run
  `"$LIVEPICKER_SCRIPTS/renderer.sh"`, capture stdout. **NO client attached**
  (the renderer is PURE — reads state only, zero tmux mutations, client-independent).
- Seeded the PRD §11 DEFAULT colors via the same `lp_appearance_seed` shape
  `test_appearance.sh` uses: `fg=default bg=default highlight-fg=black
  highlight-bg=yellow`. This makes the output byte-deterministic regardless of the
  user's `tmux.conf` (which sets `@livepicker-fg "#ffffff"` on the isolated socket).
- Did NOT seed `@livepicker-client-width` for the structure tests (width 0/unset →
  renderer's documented degradation: full-list render, NO windowing, NO indicators).
  Seeded it ONLY for the overflow tests.
- `$LIVEPICKER_SCRIPTS` is exported by `setup_socket` (== `<repo>/scripts`).

## Captured renderer outputs (the assertion ground-truth)

### OUT-a — empty query, plain, nerd-fonts ON, index 0 (list `alpha\nbeta\ndriver`)
```
#[fg=black,bg=yellow]alpha#[default] #[fg=default,bg=default]beta#[default] #[fg=default,bg=default]driver#[default]
```
**Reading:** highlight (index 0) = `#[fg=black,bg=yellow]alpha#[default]`; inactive
items = `#[fg=default,bg=default]<name>#[default]`; joined by a SINGLE space. **NO
icon, NO query, NO gap, NO `[`, NO `query>`, NO `/`, NO count.** This is the §19
§3.30 "query empty" contract. The `nerd-fonts=on` setting is correctly IGNORED when
the query is empty (the icon only shows while a query is active).

### OUT-b — query `l`, nerd-fonts OFF, width 0 (list `alpha\nlogs-prod\nblog-engine\nfoo`)
```
#[fg=default,bg=default]l#[default]  #[fg=black,bg=yellow]logs-prod#[default] #[fg=default,bg=default]alpha#[default] #[fg=default,bg=default]blog-engine#[default]
```
**Reading:** icon EMPTY (nerd off) → the query block is just `#[fg=default,bg=default]l#[default]`;
then EXACTLY 2 spaces (the `opt_query_gap` default = 2, UNSTYLED — raw, not inside
`#[…]`); then the RANKED tabs left-to-right with the TOP match (`logs-prod`) highlighted
via HFG/HBG. Ranking: `logs-prod` (prefix `l`) outranks `alpha`/`blog-engine` (subsequence).
`foo` (no `l`) is HIDDEN. This is §19 §3.31. The 2-space gap is the load-bearing
separator the contract calls out ("exactly opt_query_gap spaces").

### OUT-b2 — query `l`, nerd-fonts ON, width 0 (same list)
```
#[fg=default,bg=default]<U+F002>l#[default]  #[fg=black,bg=yellow]logs-prod#[default] ...
```
(`cat -A`: `M-oM-^@M-^Bl` = `ef 80 82` + `l`.) **Reading:** the icon glyph U+F002 is
emitted as RAW UTF-8 bytes immediately before the query, INSIDE the `#[fg,bg]` segment.
`opt_search_icon` returns `$'\uf002'` (ANSI-C quoting → the 3 bytes). So `assert_contains`
on the renderer output with the icon works: the bytes match a `case` literal substring.

### OUT-d — no-match (query `zzz`, list `alpha\nbeta`), nerd-fonts OFF then ON
```
nerd OFF: #[fg=default,bg=default]zzz (no match)#[default]
nerd ON:  #[fg=default,bg=default]<U+F002>zzz (no match)#[default]
```
**Reading:** §19 §3.34. `<icon><query>` then a TRAILING ` (no match)` (plain ASCII,
leading space, INSIDE the `#[…]` segment). NO tabs, NO indicators. The ` (no match)`
text appears REGARDLESS of nerd-font mode (glyph coverage is uneven → plain ASCII).
`assert_contains " (no match)"` is the robust assertion (works in both modes).

### OUT-c — overflow, EMPTY query, scroll 0, width 20 (8 tabs of width 5: `aaaaa..hhhhh`)
```
#[fg=black,bg=yellow]aaaaa#[default] #[fg=default,bg=default]bbbbb#[default] #[fg=default,bg=default]ccccc#[default]#[fg=default,bg=default]+5>#[default]
```
**Reading:** 3 tabs visible (`aaaaa bbbbb ccccc`); right indicator `+5>` (8 total − 3
visible = 5 hidden = hidden_left(0) + hidden_right(5); the `%d` is the COMBINED total).
NO left indicator `<` (scroll == 0). `+5>` is styled as CHROME (`#[fg=FG,bg=BG]…#[default]`,
never highlighted) and is appended DIRECTLY after the last visible tab's `#[default]`
with NO separator. `assert_contains "+5>"` + negative `case "$out" in *"<"*) fail`.

### OUT-c2 — overflow, EMPTY query, scroll 3, index 3, width 20 (same 8 tabs)
```
#[fg=default,bg=default]<#[default]#[fg=black,bg=yellow]ddddd#[default] #[fg=default,bg=default]eeeee#[default]#[fg=default,bg=default]+6>#[default]
```
**Reading:** scroll=3 → visible starts at `ddddd` (index 3, highlighted) + `eeeee`
(index 4). LEFT indicator `<` now PRESENT (scroll > 0) at column 0; RIGHT indicator
`+6>` (hidden_left=3 + hidden_right=3 = 6). Both show at once: `< …tabs… +6>`.
`<` is chrome (`#[fg=FG,bg=BG]<#[default]`). The empty-query overflow format is
`${left_ind}${tabs}${right_ind}` (no query block). `assert_contains "<"` AND `+6>`.

### OUT-c3 — overflow WITH query active (`b`, nerd off, width 20, list `aaaaa..hhhhh`)
```
#[fg=default,bg=default]b#[default]  #[fg=black,bg=yellow]bbbbb#[default]
```
**Reading:** query `b` matches ONLY `bbbbb` → 1 tab → fits in width 20 → NO indicator.
(This particular seed does NOT overflow with a query — only `bbbbb` contains `b`.)
**DESIGN NOTE for the test:** to exercise overflow WITH a query active, seed tabs that
ALL share a common subsequence char (e.g. `s0 s1 s2 … s9`, query `s`) + a narrow width.
Then the output is `<icon><query><gap>[<]<tabs>[+N>]` per the query-active format
`printf '%s' "#[fg=$FG,bg=$BG]${icon}${esc_filter}#[default]${gap}${left_ind}${tabs}${right_ind}"`.

### OUT-f — window-status tab-style, query `b`, width 20, separator `|`
```
#[fg=default,bg=default]b#[default]  #[fg=red,bold]bbbbb#[default]
```
**Reading:** the §17 window-status path STILL emits the §19 query bar (`b` + 2 spaces)
and the viewport — it does NOT fall back to the old full-line join. The single match
renders through the CURRENT template (`#[fg=red,bold]__lp_tab__→bbbbb#[default]`).
**DESIGN NOTE:** to prove window-status ALSO honors overflow, seed many tabs sharing a
query char (e.g. `s0..s9`, query `s`) + narrow width + the two templates + separator.
Then assert the query bar AND `+N>` both appear (the §19 layout is shared by both styles).

### OUT-justify — empty query, fits, status-justify=centre, width 40 (list `a\nb`)
```
                  <tabs>
```
**Reading:** when the tabs fit AND there is no query, the renderer EMULATES
`status-justify` with LEADING padding (centre → `(width − tabs_w)/2` spaces). With
justify=left (the default) there is NO leading pad. The renderer reads
`tmux show-options -g -v status-justify` (a session option; set via
`tmux set-option -g status-justify centre`). **ROBUST ASSERTION:** assert the
centre output STARTS WITH a space (leading pad present) and CONTAINS the tab names;
assert the left output does NOT start with a space. (Avoids brittle exact-pad counts.)

## Deterministic facts encoded into the test assertions

1. **Default-color byte-exactness** (the seed pins these): highlight =
   `#[fg=black,bg=yellow]<name>#[default]`; inactive = `#[fg=default,bg=default]<name>#[default]`;
   query/icon block = `#[fg=default,bg=default]<icon><query>#[default]`; chrome (indicators)
   = `#[fg=default,bg=default]<text>#[default]`.
2. **Gap is EXACTLY 2 spaces**, UNSTYLED (raw, not in `#[…]`), between the query block and
   the first tab. Default `opt_query_gap=2`.
3. **Icon**: nerd-on → raw U+F002 bytes (`$'\uf002'`); nerd-off → empty (the query block is
   just the query). Icon appears ONLY while a query is active (empty query → no icon).
4. **`+N>`**: `%d` = total hidden (left+right combined); styled chrome; appended after the
   last visible tab with NO separator; shown iff overflow; never highlighted.
5. **`<`**: presence-only (no count); shown iff `scroll > 0`; chrome; at column 0 (empty
   query) or right after the gap (query active).
6. **` (no match)`**: plain ASCII, trailing, inside the `#[…]` segment; regardless of nerd mode.
7. **NO count anywhere**: there is NO `index/total` pattern (no `[0/5]`, no `/`, no `[` from
   the count) in ANY state — the count was removed entirely (P1.M2.T3.S1). A negative grep
   for `[0-9]/[0-9]` across all states is the §15.28 "no count" proof.
8. **`#` doubling** (`${FILTER//\#/##}`): a query containing `#` is emitted as `##` so tmux
   renders it literally. (Already covered by `test_functional.sh::test_renderer_escapes_hash_*`;
   `test_layout.sh` does NOT duplicate it — out of scope per the contract's item list.)

## Test-design decisions (how each contract item maps to a test_* function)

| Contract item | test_* function | Seed | Key asserts |
|---|---|---|---|
| (a) empty → tabs only | `test_layout_empty_query_tabs_only` | list, filter="", idx0 | contains tab names; NOT icon/query/`[`/`query>`/`/` |
| (b) query char, nerd off | `test_layout_query_active_structure` | filter="l", nerd off, width0 | icon empty, query present, EXACTLY 2 spaces, ranked tabs, top highlighted |
| (b) query char, nerd on | `test_layout_query_active_nerd_font_icon` | filter="l", nerd on | output contains U+F002 icon bytes |
| (c) overflow right | `test_layout_overflow_right_indicator` | 8 tabs, width20, scroll0 | contains `+5>`; NOT `<` |
| (c) overflow left | `test_layout_overflow_left_indicator` | 8 tabs, width20, scroll3, idx3 | contains `<` AND `+6>` |
| (c) fits → neither | `test_layout_overflow_fits_no_indicators` | 3 tabs, width80 | NOT `+` ; NOT `<` |
| (c)+(b) overflow+query | `test_layout_overflow_with_query_active` | `s0..s9`, filter="s", width20 | query bar AND `+N>` AND `<` (scroll>0 variant) |
| (d) no-match | `test_layout_no_match` | filter="zzz" | contains ` (no match)`; NOT tabs |
| (e) no count anywhere | `test_layout_no_count_anywhere` | sweep empty/active/no-match | NO `[0-9]/[0-9]` pattern in any |
| (f) window-status §19 | `test_layout_window_status_keeps_query_bar` | ws templates, `s0..s9`, filter="s", width20 | query bar AND viewport AND `+N>` (not old full-line join) |
| justify (contract note) | `test_layout_status_justify_empty` | empty, fits, justify centre vs left | centre → leading space; left → none |

All are RENDERER-ONLY (no `attach_test_client`): seed state → run renderer.sh →
`assert_contains`/`assert_eq`/negative `case`. Mirrors `test_appearance.sh`'s
`lp_appearance_seed` + direct-cache-seed idiom verbatim.

## Gaps

None material. Every assertion is backed by a captured renderer output above. The only
"designed" tests (overflow-with-query, window-status-overflow, justify) reuse the
verified renderer format strings (`printf '%s' "#[fg=$FG,bg=$BG]${icon}${esc_filter}#[default]${gap}${left_ind}${tabs}${right_ind}"`
for query-active; the leading-pad emulation for justify) — their structure is confirmed
by OUT-c/OUT-c2 (overflow mechanics) + OUT-b (query block) + OUT-f (window-status query
bar) + OUT-justify (pad), so the combined assertions are sound by construction.
