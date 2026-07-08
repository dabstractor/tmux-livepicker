# Research — P1.M3.T2.S1: wire scroll state into input paths (scroll-into-view + reset)

> Ground-truth for editing `scripts/input-handler.sh` (the SUT). All claims are
> read/grep-confirmed against the LANDED working tree (plan 003: rank.sh +
> layout.sh + the new state keys all COMPLETE; P1.M3.T1.S1 captures
> STATE_CLIENT_WIDTH at activate — treated as a CONTRACT). Paths are relative to
> the repo root.

## 1. The SUT — input-handler.sh dispatch (the 6 branches + their exact seams)

`input_main()` (line ~187) is a `case "$action"` over type/backspace/next-session/
prev-session/confirm/cancel/refresh-width/`*)`. Each relevant branch + its EXACT
insertion seam (content-anchored; line numbers drift):

| branch | current tail (the anchor) | the edit |
|---|---|---|
| `type)` | `set_state "$STATE_INDEX" "0"` then `_lp_sync_preview_to_top_match` | ADD `set_state "$STATE_SCROLL" "0"` right after the `STATE_INDEX` reset |
| `backspace)` | `set_state "$STATE_INDEX" "0"` then `_lp_sync_preview_to_top_match` | ADD `set_state "$STATE_SCROLL" "0"` right after the `STATE_INDEX` reset |
| `next-session)` | `set_state "$STATE_INDEX" "$new_idx"`; `target="${filtered[$new_idx]}"`; then `_lp_preview_follow "$target"` | INSERT scroll-into-view BETWEEN `target=…` and `_lp_preview_follow` |
| `prev-session)` | (mirror of next) | INSERT scroll-into-view BETWEEN `target=…` and `_lp_preview_follow` |
| `cancel)` (clear branch) | `set_state "$STATE_INDEX" "0"` then `_lp_sync_preview_to_top_match` (the NON-empty-filter branch) | ADD `set_state "$STATE_SCROLL" "0"` right after the `STATE_INDEX` reset |

`confirm` and the cancel full-teardown branch and `refresh-width` are NOT touched
(confirm tears down → restore clears state; refresh-width is width-only).

## 2. LOAD-BEARING: input-handler.sh does NOT source layout.sh (must add it)

Grep-confirmed: input-handler.sh sources `options.sh`, `utils.sh`, `state.sh`,
`rank.sh` — **NOT `layout.sh`**. `lp_viewport` is therefore UNDEFINED here today.
**The PRP MUST add `source "$CURRENT_DIR/layout.sh"`** (after the rank.sh source,
before the helpers) or `lp_viewport` is a "command not found" crash. This is the
single most important edit; without it the scroll-into-view crashes the picker.

Source order is load-bearing per §P1: options → utils → state → (rank|layout).
layout.sh sources NOTHING itself (it is a pure-math lib), so appending it after
rank.sh is safe and matches the renderer's own source order (renderer sources
rank.sh then layout.sh).

## 3. lp_viewport — signature + the self-correction insight (the key design fact)

`scripts/layout.sh::lp_viewport RANKED_LIST T SCROLL HIGHLIGHT [SEP_WIDTH=1]`
sets globals `LPV_SCROLL LPV_START LPV_END LPV_HIDDEN_LEFT LPV_HIDDEN_RIGHT`. The
scroll-into-view algorithm (PRD §19 §3.32), empirically verified:

```
T=12, 6 tabs w=5, scroll=0, hl=4  -> LPV_SCROLL=3  (advances: cumwidth(0,4)=29>12 -> scroll to 3 so hl fits; window [3,4])
T=12, 6 tabs w=5, scroll=3, hl=1  -> LPV_SCROLL=1  (step a: hl<scroll -> snap to hl)
T=100 (fits)                     -> LPV_SCROLL=0  (clamp scroll=0; all visible)
T=0   (width unknown/degraded)   -> LPV_SCROLL=0, LPV_END=-1 (scroll 0; empty slice)
```

**THE self-correction insight (decisive for the T choice):** the renderer
(`renderer.sh`) ALREADY calls `lp_viewport "$ranked" "$T_renderer" "$SCROLL" "$cidx"
"$sep_w"` on EVERY redraw, passing the STORED `STATE_SCROLL` + the highlight. lp_viewport
re-runs steps (a)+(b) fresh each render, so **LPV_SCROLL (the value the renderer actually
slices with) is ALWAYS correct for the current highlight — regardless of what
STATE_SCROLL contains.** STATE_SCROLL is only the STARTING POINT for that advance; the
renderer is the source of truth for the visible window. Consequences:

- The input handler's STATE_SCROLL write is **state hygiene** (keep it tracking the
  highlight so it doesn't drift absurdly), NOT a render-correctness requirement.
- An imprecise T in the input handler is HARMLESS: if it under-advances scroll
  (T too wide), the renderer's own lp_viewport advances it further on the SAME redraw
  (no visible glitch — all in one render cycle). It can never hide the highlight.
- The exact renderer T (`client_width − query_block − indicators`, resolved via a
  bounded indicator-circle loop) does NOT need to be duplicated in the input handler.

So: **T = STATE_CLIENT_WIDTH** (the work-item's literal INPUT spec). This is a
conservative approximation (the renderer's tab-region T is narrower), self-corrected by
the renderer every redraw. SEP_WIDTH defaults to 1 (the renderer reserves more for a
multi-char window-status separator, but that small discrepancy is self-corrected too).

## 4. T = client_width + width=0 degradation (verified safe)

When `STATE_CLIENT_WIDTH` is 0/unset (detached edge, or P1.M3.T1 not yet run),
`lp_viewport list 0 …` returns `LPV_SCROLL=0` (the T<=0 early-return). So the input
handler writes `STATE_SCROLL=0` — exactly the "no windowing" degradation the renderer
takes (FINDING 6: width=0 → render the full list, no indicators). Consistent + safe
either way. No special-case `if width>0` guard needed in the input handler (lp_viewport
handles it); but the reset-on-type/backspace is a hard `set_state ""... "0"` regardless.

## 5. The §18 contract — scroll is a synchronous STATE write, NOT preview work

PRD §18.1: "the typing path is status-only and synchronous." Scroll reset is a STATE
write (one `set_state`), part of the same synchronous status update that writes
`STATE_INDEX`. It is NOT preview work (no `link-window`/`select-window`/`run-shell -b`).
The preview re-sync on type/backspace STAYS routed through `_lp_sync_preview_to_top_match`
(→ `_lp_preview_follow`, which honors `@livepicker-preview-defer`); on next/prev it stays
routed through `_lp_preview_follow "$target"`. The scroll-into-view is INSERTED in the
nav branches but does NOT touch the preview call (it sits between `set_state INDEX` and
`_lp_preview_follow`). §P5 (do NOT bypass the preview entry point) is respected.

## 6. The DRY helper — _lp_scroll_into_view IDX RANKED

next-session AND prev-session run identical scroll-into-view logic. Factor a tiny
`_lp_*` helper (matches the `_lp_sync_preview_to_top_match` / `_lp_preview_follow` /
`_lp_fire_preview` convention) so the two branches don't duplicate it:

```bash
_lp_scroll_into_view() {
	local idx="${1:-0}" ranked="${2:-}"
	local width scroll
	width="$(get_state "$STATE_CLIENT_WIDTH" "0")"
	scroll="$(get_state "$STATE_SCROLL" "0")"
	lp_viewport "$ranked" "$width" "$scroll" "$idx"   # sep defaults to 1
	set_state "$STATE_SCROLL" "$LPV_SCROLL"
}
```
Call sites pass the already-computed `filtered` (joined), avoiding a second `lp_rank`:
`_lp_scroll_into_view "$new_idx" "$(printf '%s\n' "${filtered[@]}")"`. (The `$(printf …)`
join mirrors the renderer's own `ranked="$(printf '%s\n' "${filtered[@]}")"`.)

## 7. Why the existing 9-file / ~44-test suite stays green

- No committed test references `STATE_SCROLL` / `lp_viewport` / `@livepicker-scroll`
  (scroll tests are P1.M4.T3, not started). So new scroll writes can't break assertions.
- test_functional.sh / test_responsiveness.sh ACTIVATE + NAVIGATE. After P1.M3.T1.S1,
  `STATE_CLIENT_WIDTH` ≈ 120 (the test pty width). The baseline list (driver/alpha/beta +
  a couple extras) is SHORT → total ≤ 120 → `lp_viewport` clamps `LPV_SCROLL=0`. So nav
  writes `STATE_SCROLL=0` (no change). type/backspace reset to 0 (no change). Harmless.
- Even if width were 0 (P1.M3.T1 not done), lp_viewport returns `LPV_SCROLL=0` →
  `STATE_SCROLL=0`. Same harmless result.
- The new `source layout.sh` adds a pure-math lib with NO source-time side effects (§P1) →
  no behavior change at source time.
- `lp_viewport` is PURE (no tmux calls, no subshells on the measurement path) → no
  pollution, no extra round-trips.

## 8. Edit summary (5 logical edits + 1 source line + comment notes)

1. ADD `source "$CURRENT_DIR/layout.sh"` after the rank.sh source (LOAD-BEARING).
2. ADD the `_lp_scroll_into_view` helper near the other `_lp_*` helpers.
3. type/backspace/cancel-clear: ADD `set_state "$STATE_SCROLL" "0"` next to the
   `set_state "$STATE_INDEX" "0"` reset (3 sites).
4. next-session/prev-session: ADD `_lp_scroll_into_view "$new_idx" "$(printf '%s\n'
   "${filtered[@]}")"` between `target=…` and `_lp_preview_follow "$target"` (2 sites).
5. Comment notes: the type/backspace branch headers + the new lines note "scroll reset
   is part of the synchronous status update (still status-only — a state write, no
   preview work; §18)". The nav scroll-into-view notes "scroll is a synchronous STATE
   write; the preview re-sync stays deferred via _lp_preview_follow (§18)".

Validation (no committed test): `bash -n` + `shellcheck`; the full `tests/run.sh`
(44-green gate); a THROWAWAY scroll smoke (seed a long list + STATE_CLIENT_WIDTH,
nav right → STATE_SCROLL advances; type → resets to 0; nav left → snaps), then DELETE
it. Committed scroll/client-width tests are P1.M4.T3.S1.

## 9. Sources / cross-refs

- `plan/003_77ef311abf10/architecture/codebase_patterns.md` §P5 (preview entry point),
  §P7 (shared layout viewport), §P1 (sourced-library contract), §P3 (state contract).
- `plan/003_77ef311abf10/P1M1T2S1/research/layout_viewport_findings.md` (lp_viewport math).
- `plan/003_77ef311abf10/P1M2T2S1/research/viewport_overflow_findings.md` (renderer T +
  the indicator-circle; FINDING 6 width=0 degradation; FINDING 2 the self-correction basis).
- `plan/003_77ef311abf10/P1M3T1S1/PRP.md` (the STATE_CLIENT_WIDTH producer — CONTRACT).
- `scripts/input-handler.sh` (the SUT), `scripts/layout.sh` (lp_viewport),
  `scripts/rank.sh` (lp_rank), `scripts/state.sh` (STATE_SCROLL/STATE_CLIENT_WIDTH),
  `scripts/renderer.sh` (the consumer that self-corrects scroll).
- Empirical probes run this session (§3 above): lp_viewport LPV_SCROLL advances/snaps/
  clamps/degrades exactly as designed.
