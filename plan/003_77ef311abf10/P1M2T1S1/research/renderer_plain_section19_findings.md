# Research — Plan-003 P1.M2.T1.S1: restructure render() plain path into §19 layout; drop plain SHOW_COUNT

> Verified against the current working tree (rank.sh/layout.sh/options.sh complete;
> state.sh has STATE_SCROLL/STATE_CLIENT_WIDTH via P1.M1.T3.S2). The §19 layout spec
> is in PRD §19 (selected) + codebase_patterns.md §P6 (renderer rules).

## Environment

tmux 3.6b; bash 5.3; shellcheck installed. Isolated-socket pty probes were flaky
(socket-path/`script`-detach issues), so the status-justify determination below
rests on **codebase_patterns.md §P6 + PRD §19 §3.31 reasoning** (authoritative for
this codebase), flagged as a residual visual-verify item.

---

## FINDING 1 — the plain path is everything BELOW the window-status early-return `fi`

`scripts/renderer.sh::render()` (206 lines) has TWO paths:
- **window-status early-return** (lines ~46-135, inside `if [ "$(opt_tab_style)" = "window-status" ]; then ... fi`): **LEAVE UNTOUCHED** — P1.M2.T3 reworks it. It still uses SHOW_COUNT (the `query> $esc_wfilter [i/N]` suffix) and its own no-match branch; keep all of that intact.
- **plain path** (lines ~137-206, after the ws `fi`): THIS task reworks it. Currently it: reads LIST/FILTER/IDX; mapfile all/filtered (via lp_rank); no-match branch (with SHOW_COUNT); cidx clamp; highlight loop (space-joined `#[fg=...]name#[default]`); trailing SHOW_COUNT suffix (`query> $esc_filter [i/N]`); `printf '%s' "$out"`.

**The shared prefix stays**: the option reads at the top of render() (TYPE/FG/BG/HFG/HBG/SHOW_COUNT_RAW + the `case` → SHOW_COUNT) are **shared** with the ws path. KEEP them — P1.M2.T3 removes SHOW_COUNT entirely; this task only stops *using* it in the plain path.

---

## FINDING 2 — dependencies all present (rank/layout/options/state)

- `rank.sh::lp_rank LIST FILTER` (COMPLETE): subsequence ranker. **Empty FILTER → all names, ORIGINAL order** (byte-identical to the old behavior — keeps query-empty tests green). Non-matches HIDDEN. `mapfile -t filtered < <(lp_rank "$LIST" "$FILTER")`.
- `layout.sh::lp_disp_width STRING` (COMPLETE): strips `#[…]` styles, counts codepoints via `${#var}` (NOT `wc -m` — locale-dependent). Used here to measure the tabs' display width for status-justify emulation. `layout.sh` is NOT yet sourced by renderer.sh — **ADD `source "$CURRENT_DIR/layout.sh"`**.
- `options.sh` (COMPLETE, P1.M1.T3.S1): `opt_nerd_fonts` (default `on`), `opt_search_icon` (default `$'\uf002'` — nf-fa-search, ANSI-C quoted → bytes `ef 80 82`), `opt_query_gap` (default `"2"`).
- `state.sh` (COMPLETE, P1.M1.T3.S2): `STATE_SCROLL`=`@livepicker-scroll`, `STATE_CLIENT_WIDTH`=`@livepicker-client-width`. Both in `_STATE_RUNTIME_KEYS` (cleared on exit). **STATE_CLIENT_WIDTH is not yet WRITTEN by anyone** (P1.M3.T1 captures it at activate) — so at runtime today `get_state "$STATE_CLIENT_WIDTH" "0"` → `"0"`. The plain path must treat width=0 as "unknown → degrade to left."

---

## FINDING 3 — the 3 §19 branches (contract §3; PRD §19 §3.30/§3.31/§3.34)

The plain path branches on **FILTER emptiness** (not on FLEN, though no-match is FLEN==0):

| Branch | Trigger | Layout (column 0 →) | Status-justify |
|---|---|---|---|
| (a) Query EMPTY | `-z "$FILTER"` | ONLY tabs (space-joined), highlighted IDX | **emulated** (pad per status-justify) |
| (b) Query ACTIVE | `-n "$FILTER"` && FLEN>0 | `<icon><query><gap><tabs>` | **suspended** (pinned left, no pad) |
| (c) No-match | `FLEN -eq 0` (any filter) | `<icon><query> (no match)` (plain ASCII marker) | suspended (left) |

Details:
- **icon**: `"$(opt_search_icon)"` IFF `[ "$(opt_nerd_fonts)" = "on" ]`, else `""`. Emit raw bytes (the glyph is already byte-correct via options.sh's `$'\uf002'`).
- **query**: `$esc_filter` (`${FILTER//\#/##}` — every `#` doubled; `#()` output is NOT re-parsed for `#{…}`, §P6).
- **gap**: exactly `opt_query_gap` spaces. Build with `printf '%*s' "$(opt_query_gap)" ''`. Plain (unstyled) spaces.
- **tabs**: ranked list (`filtered[]`), each name `#`-escaped, styled `#[fg=$HFG,bg=$HBG]<name>#[default]` (highlighted IDX) / `#[fg=$FG,bg=$BG]<name>#[default]` (others), joined by a single space (plain mode).
- **no `query>` prefix, no `[i/N]` count** anywhere in the plain path. The `SHOW_COUNT` suffix block is REMOVED from the plain path (kept in the ws path).

Styling decision: style the query bar (icon+query) with `#[fg=$FG,bg=$BG]…#[default]`; emit the **gap as plain spaces** (so the gap isn't a colored bar); tabs are per-item styled as before. No-match line: `#[fg=$FG,bg=$BG]${icon}${esc_filter} (no match)#[default]`.

---

## FINDING 4 — status-justify is EMULATED by the renderer (load-bearing; §P6 + §19 §3.31)

**Determination**: `tmux status-justify` does NOT auto-apply to an explicitly-set `#()` `status-format[0]` line; the **renderer emulates it** via leading padding spaces in branch (a). Evidence:
1. **codebase_patterns.md §P6**: "separator/justify from a single read, not per-tab" — the renderer READS justify because it USES it (emulation). If tmux auto-applied it, the renderer would not read it.
2. **PRD §19 §3.31**: "While a query is active, `status-justify` is **suspended** for the tabs." Suspension is only possible if the RENDERER controls the padding (tmux has no per-redraw suspend of status-justify). This REQUIRES renderer-side emulation.
3. tmux man page: `status-justify` governs the window-status region of the DEFAULT status composition; an explicit `status-format[N]` override replaces that composition.

**Emulation** (branch (a) only):
```
justify="$(tmux show-options -g -v status-justify 2>/dev/null)"; [ -z "$justify" ] && justify=left
width="$(get_state "$STATE_CLIENT_WIDTH" "0")"
[[ "$width" =~ ^[0-9]+$ ]] || width=0
pad=""
if [ "$justify" != left ] && [ "$width" -gt 0 ]; then
    tabs_w="$(lp_disp_width "$tabs")"   # strips #[…] styles, counts codepoints
    if [ "$tabs_w" -lt "$width" ]; then
        case "$justify" in
            centre|absolute-centre) padw=$(( (width - tabs_w) / 2 )) ;;
            right)                  padw=$(( width - tabs_w )) ;;
            *)                      padw=0 ;;
        esac
        pad="$(printf '%*s' "$padw" '')"
    fi
fi
out="$pad$tabs"
```
- Branches (b) and (c): `pad=""` (pinned left = "suspended").
- **width=0 (STATE_CLIENT_WIDTH unset — P1.M3.T1 not landed)** → `pad=""` (degrade to left). Forward-compatible: once P1.M3.T1 captures width, centre/right users get correct positioning.
- The padding is ONE `tmux show-options` read + ONE `lp_disp_width` call per redraw (NOT per-tab) — within §P6's "single read" allowance + the §18 budget.

**RESIDUAL RISK (visual-verify)**: if a given tmux build DID auto-apply status-justify to `#()` output, the renderer's padding would double-justify (tabs shifted right of centre). §P6 + §19 §3.31 indicate it does NOT, but this MUST be visually spot-checked in Level 4 (a real client render of the empty-query centre case). If double-justify is observed, the fix is to DROP the emulation (let tmux handle it) — but that would break the query-active suspend, so the emulation is the design-intended path.

---

## FINDING 5 — KEEP the SHOW_COUNT computation; remove only its plain-path USE

The shared option-read prefix at the top of render() computes `SHOW_COUNT_RAW` + `SHOW_COUNT` (the `case` parse). The **ws path still uses SHOW_COUNT** (its no-match + suffix branches). P1.M2.T3 removes SHOW_COUNT entirely. So THIS task:
- **KEEPS** `SHOW_COUNT_RAW="$(opt_show_count)"` + the `case … SHOW_COUNT=…` block (ws path needs it).
- **REMOVES** every `[ "$SHOW_COUNT" -eq 1 ]` block in the PLAIN path: the no-match count line (`0/$TOTAL`) and the trailing `[i/N]` suffix.
- The plain no-match branch becomes just `<icon><query> (no match)` (no `0/$TOTAL`).
- Do NOT remove `opt_show_count` / the SHOW_COUNT locals (P1.M2.T3 does that, after reworking the ws path).

---

## FINDING 6 — STATE_SCROLL is READ but not USED for slicing (windowing is P1.M2.T2)

Contract: "Use STATE_SCROLL to slice the visible tabs (full windowing/overflow lands in P1.M2.T2; here just read scroll and show the full ranked list)." So:
- `SCROLL="$(get_state "$STATE_SCROLL" "0")"` — read into a local (the seam exists; P1.M2.T2 will slice `filtered[]` by it).
- Do NOT slice; render the FULL ranked list. No overflow indicators (`<` / `+N>`) — those are P1.M2.T2.
- renderer.sh's header already carries `# shellcheck disable=SC1091,SC2034` — SC2034 (unused local) is file-wide disabled, so an unread-after-write `SCROLL` local raises NO warning. Add a comment: `# read; windowing/slicing lands in P1.M2.T2`.

---

## FINDING 7 — 3 existing test assertions reference the old plain `query> …` / count output (must update as the TDD step)

Grep of `tests/` for `query>` / count brackets in PLAIN-path assertions:

| File:line | Current assertion | Why it breaks | Update |
|---|---|---|---|
| `tests/test_functional.sh:332` | `assert_contains "$out" "query> ##dev"` (match branch) | §19 drops the `query>` prefix; query text `##dev` now appears as `<icon>##dev<gap><tabs>` (it also appears in the tab). | `assert_contains "$out" "##dev"` (escaped query/tab present; `query>` gone). |
| `tests/test_functional.sh:337` | `assert_contains "$out" "query> ##zz"` (no-match branch) | §19 no-match = `<icon>##zz (no match)` (no `query>`). `##zz` can ONLY be the query here (no tabs) — the clean query-escape proof. | `assert_contains "$out" "##zz"` (query escape proven; no tabs to confound). |
| `tests/test_responsiveness.sh:94` | `assert_contains "$(... renderer.sh)" "query> a"` | §19 query-active = `<icon>a<gap><tabs>` (no `query>`). The bare `"a"` is too weak (matches session names). | Assert the **search icon** (U+F002) is present — it ONLY renders in query-active/no-match branches, so its presence proves the typed `a` made the query non-empty (status reflected). Pin `@livepicker-nerd-fonts on`. Form: `case "$out" in *$'\uf002'*) pass;; *) fail;; esac`. (The SEQ bump on the prior line remains the load-bearing deferral proof.) |

- `test_functional.sh::test_renderer_escapes_hash_in_names` (filter="") → **NO change**: query-empty shows the tabs (escaped `##dev` still present); the `@livepicker-list`-unchanged assertion still holds.
- `test_functional.sh::test_typing_filters` — does NOT assert `query>` or the count (grep-confirmed); it asserts the filtered tab names appear + index==0. Those still hold under §19 (tabs still rendered). **NO change.**
- `tests/test_appearance.sh` — about the window-status (§17) path, which is UNTOUCHED here. **NO change.**

---

## FINDING 8 — no conflict with the parallel P1.M1.T3.S2 (state.sh only)

P1.M1.T3.S2 (Implementing) edits `scripts/state.sh` (adds STATE_SCROLL/STATE_CLIENT_WIDTH/ORIG_CLIENT_RESIZED_HOOK). It does NOT touch renderer.sh or any test file. This task edits `scripts/renderer.sh` + 2 test assertions. **Zero file overlap.** (State.sh already has the constants — verified by grep — so P1.M1.T3.S2 has effectively landed its definitions.)

---

## Summary of load-bearing decisions (encoded in the PRP)

1. **3 branches on FILTER emptiness** (empty→tabs+justify; active→icon+query+gap+tabs pinned-left; no-match→icon+query+" (no match)"). (FINDING 3)
2. **Source layout.sh** (ADD `source "$CURRENT_DIR/layout.sh"`) for lp_disp_width. (FINDING 2)
3. **status-justify EMULATED** via leading padding in branch (a) only; suspended (no pad) in (b)/(c). Degrade to left when STATE_CLIENT_WIDTH unset (P1.M3.T1). Visual-verify the centre case (Level 4). (FINDING 4)
4. **KEEP SHOW_COUNT computation** (ws path needs it); REMOVE its plain-path USE (no-match count + trailing [i/N]). (FINDING 5)
5. **READ STATE_SCROLL** but do NOT slice (windowing is P1.M2.T2; SC2034 is file-wide disabled). (FINDING 6)
6. **Update 3 test assertions** (test_functional.sh:332,337; test_responsiveness.sh:94). (FINDING 7)
7. **icon = opt_search_icon iff opt_nerd_fonts=on**; query = `${FILTER//\#/##}`; gap = `opt_query_gap` plain spaces. Style icon+query with FG/BG; gap plain; tabs per-item styled. (FINDING 3)
8. **ws path UNTOUCHED** (P1.M2.T3 owns it). (FINDING 1)

---

## Gaps

1. **status-justify auto-application to `#()` output** was not empirically confirmed (pty probes flaky). The §P6 + §19 §3.31 reasoning is authoritative for the emulation decision, but the centre/right empty-query case MUST be visually spot-checked (Level 4). If double-justify is observed, drop the emulation (documented fallback).
2. **STATE_CLIENT_WIDTH is unwritten today** (P1.M3.T1 captures it). The emulation degrades to left until then — acceptable (centre/right positioning activates once P1.M3.T1 lands). The §15.28 layout tests (P1.M4.T1) will exercise the full width path.
