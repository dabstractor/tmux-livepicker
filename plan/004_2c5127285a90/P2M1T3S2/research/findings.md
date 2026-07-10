# Research Findings — P2.M1.T3.S2 (Reset window-cursor on session-nav and type/backspace)

Ground-truth for the PRP. **Line numbers are ILLUSTRATIVE** — the file was
concurrently edited by the parallel sibling P2.M1.T3.S1 (next-window/prev-window
branches at L405/L466, +112 insertions between prev-session and confirm), which
shifted ONLY the cancel-clear line (526→638). The **TEXT `oldText` anchors are
AUTHORITATIVE** (all 6 verified UNIQUE in the current file — re-verify with
`grep -c` before editing). Status: P2.M1.T2.S1 COMPLETE (`_lp_fire_preview`/
`_lp_preview_dispatch` carry `win_id="${2:-}"`); P2.M1.T1.S1 COMPLETE (the 4
window-cursor state keys exist + are init'd + teardown-wired); **P2.M1.T3.S1
LANDED** (next-window L405, prev-window L466 — its lazy-derive is complementary,
see FINDING 6). Verified against tmux 3.6b on an isolated socket.

---

## FINDING 1 — The 4 window-cursor state keys EXIST + are wired (no state.sh edit)

`scripts/state.sh` defines (all `readonly`, all in `_STATE_RUNTIME_KEYS` →
teardown-wired by `clear_all_state`):

| Constant | tmux option | init (activate) | role |
|----------|-------------|-----------------|------|
| `STATE_CAND_WIN_SESSION` | `@livepicker-cand-win-session` | `ORIG_SESSION` | cache-invalidation key: the candidate the cached window-list belongs to |
| `STATE_CAND_WIN_LIST` | `@livepicker-cand-win-list` | `''` | newline-joined ordered window ids of the candidate |
| `STATE_CAND_WIN_CURSOR` | `@livepicker-cand-win-cursor` | `'0'` | 0-based index into STATE_CAND_WIN_LIST |
| `STATE_PREVIEW_WIN_ID` | `@livepicker-preview-win-id` | `''` | window currently shown (this task does NOT touch it) |

→ **THIS task MUST NOT edit state.sh.** It only READS/WRITES the 3 cursor keys
(SESSION/LIST/CURSOR) via `get_state`/`set_state`. `STATE_PREVIEW_WIN_ID` is the
flip subsystem's concern (P2.M1.T2.S1 + P2.M1.T3.S1) — NOT written by this task.

## FINDING 2 — The 5 branches to edit + the 1 helper edit (ALL in input-handler.sh)

This task is a SINGLE-FILE edit (`scripts/input-handler.sh`). DOCS = none (the
contract says "internal state reset behavior"). No README, no test file. Six
precise edits, each an additive 3-line `set_state` cluster (+ a comment):

| # | Branch / helper | Anchor (verified line) | Insertion point |
|---|-----------------|------------------------|-----------------|
| 1 | `_lp_sync_preview_to_top_match` | L146 `_lp_preview_dispatch "$_top"` | change call to `_lp_preview_dispatch "$_top" ""` (+ comment) |
| 2 | `type` | L272 `set_state "$STATE_INDEX" "0"` | AFTER it, BEFORE the scroll reset |
| 3 | `backspace` | L313 `set_state "$STATE_INDEX" "0"` | AFTER it, BEFORE the scroll reset |
| 4 | `next-session` | L354 `target="${filtered[$new_idx]}"` | AFTER it, BEFORE the REDRAW comment |
| 5 | `prev-session` | L387 `target="${filtered[$new_idx]}"` | AFTER it, BEFORE the REDRAW comment |
| 6 | `cancel` clear-path (inside `if [ -n "$cur_filter" ]`) | L638 `set_state "$STATE_INDEX" "0"` (4-tab indent) | AFTER it, BEFORE the scroll reset |

NOTE: only edit #6's line shifted (526→638) due to the sibling P2.M1.T3.S1's
insertion between prev-session and confirm; edits #1-5 are above that insertion
and are unchanged. The `oldText` blocks in the PRP are the AUTHORITATIVE anchors
(match on text, not line numbers).

**Indentation is load-bearing** (the file is TAB-indented): type/backspace/
next-session/prev-session branch bodies are **3 tabs**; the cancel clear-path is
**4 tabs** (it is nested inside `if [ -n "$cur_filter" ]; then`). A wrong indent
= a non-matching `oldText`. (`cat -A` verified: `^I^I^I` = 3 tabs, `^I^I^I^I` = 4.)

## FINDING 3 — session-nav vs type/backspace reset DIFFER (the contract's two clauses)

The contract specifies TWO distinct reset shapes — they are NOT identical:

**(a) session-nav (next-session/prev-session)** — the branch already RESOLVES the
new target session name into `$target` (the `target="${filtered[$new_idx]}"`
line). So the reset binds the cache to the KNOWN new candidate:
```bash
set_state "$STATE_CAND_WIN_SESSION" "$target"   # the new candidate's NAME
set_state "$STATE_CAND_WIN_LIST" ""             # invalidate (re-derived on next flip)
set_state "$STATE_CAND_WIN_CURSOR" "0"          # lazy default -> active window on next flip
```
The subsequent `_lp_preview_dispatch "$target"` (1 arg → win_id="") re-links the
new candidate's ACTIVE window into the preview (preview.sh chosen_win="" →
`#{window_active}`). The cursor='0' is a placeholder; P2.M1.T3.S1's flip will
re-derive the list and reset the cursor to the candidate's true active-window
index. Both are consistent (every candidate starts previewed on its own active
window — Invariant B).

**(b) type/backspace/cancel-clear** — the branch does NOT resolve the top match's
session name in-line (it sets `STATE_INDEX=0` and lets
`_lp_sync_preview_to_top_match` resolve `filtered[0]` later). So the reset
INVALIDATES the cache entirely (the top match may be ANY session after the filter
change):
```bash
set_state "$STATE_CAND_WIN_SESSION" ""          # invalidate (any session may now be top)
set_state "$STATE_CAND_WIN_LIST" ""             # invalidate
set_state "$STATE_CAND_WIN_CURSOR" "0"          # lazy default
```
The preview re-link is `_lp_sync_preview_to_top_match`'s job (it calls
`_lp_preview_dispatch "$_top" ""` → active window).

→ **Do NOT swap these.** session-nav binds SESSION=$target (known); type/backspace
sets SESSION="" (unknown until re-rank). Setting SESSION="" in session-nav would
still be CORRECT (the flip re-derives on `list==""` too), but the contract
explicitly says bind to the target — follow it.

## FINDING 4 — `set_state "$KEY" ""` is a SET-EMPTY, safe under `set -u`

The file ALREADY uses `set_state "$STATE_FILTER" ""` in the cancel clear-path
(L524) — verified. `set_state()` is `tmux_set_opt "$1" "$2"`; with `$2=""` the
positional is SET-but-empty (not unset) → `"$2"` expands to `""` safely under
`set -u`. `tmux set-option -g @x ""` is a SET-EMPTY (get_state reads it back as
"" via the default) — NOT an unset; restore's `clear_all_state` -gu teardown
handles the actual unset. So `set_state "$STATE_CAND_WIN_SESSION" ""` is the
correct, established invalidation idiom. (Do NOT use `tmux_unset_opt`/`-gu` —
that is restore's teardown concern, mid-browsing it would leave a gap.)

## FINDING 5 — preview.sh chosen_win="" → active window (VERIFIED)

`scripts/preview.sh` signature: `local S="${1:-}" chosen_win="${2:-}" expected_seq="${3:-}"`
(L89). When `chosen_win` is empty:
- L191: `src_id="$(tmux list-windows -t "=$S" -F '#{window_id}' -f '#{window_active}' 2>/dev/null)"`
  → resolves the candidate's ACTIVE window.
- The `elif [ -n "$chosen_win" ]` select-window branch (L162-164) is SKIPPED →
  the candidate's own active window is shown (NOT mutated — Invariant B).

So `_lp_sync_preview_to_top_match` calling `_lp_preview_dispatch "$_top"` (1 arg
→ win_id="") ALREADY yields "preview the top match on its active window" — the
CORRECT behavior. The contract asks to make it EXPLICIT (`_lp_preview_dispatch
"$_top" ""`). This is a functional NO-OP (win_id defaults to "" via `${2:-}`) but:
- documents the intent ("the top match is previewed on its active window"),
- is robust to any future change to `_lp_preview_dispatch`'s signature.

→ Include the explicit `""` 2nd arg (+ a comment). One-token change, zero risk.

## FINDING 6 — Scope boundary: NO conflict with the parallel sibling P2.M1.T3.S1 (NOW LANDED)

P2.M1.T3.S1 (next-window/prev-window) LANDED during this research (its branches
are now at L405 `next-window)` and L466 `prev-window)`, +112 insertions between
the end of prev-session and the `# --- seam: confirm ---` comment). It:
- ADDS two NEW case branches between the END of `prev-session` and the
  `# --- P1.M6.T3.S1 seam: confirm ---` comment. Its insertion anchor is
  `_lp_preview_dispatch "$target"\n return 0\n ;;\n # --- seam: confirm ---`.
- Edits README.md Usage (Mode A).

THIS task (S2):
- EDITS the EXISTING next-session/prev-session/type/backspace/cancel branches
  (inserting AFTER `target=` / `INDEX=0`, BEFORE the REDRAW/scroll lines) + the
  `_lp_sync_preview_to_top_match` helper.

→ **Zero textual overlap.** S2's edits are all ABOVE S1's insertion anchor (S2
touches prev-session's body at the `target=` line, which is BEFORE the
`_lp_preview_dispatch` call that is S1's anchor), except edit #6 (cancel-clear)
which is BELOW the insertion but in a region S1 never touched. The two land in
either order without conflict. **CONFIRMED live**: S1 already landed, and all 6
of S2's `oldText` anchors still match UNIQUELY in the current file (re-verified). Do NOT add next-window/prev-window branches (that's S1). Do NOT
edit `_lp_fire_preview`/`_lp_preview_dispatch`/preview.sh (that's P2.M1.T2.S1 —
ALREADY landed; just CALL them). Do NOT edit README (DOCS = none here).

**S1↔S2 runtime interaction is COHERENT (defense in depth):** S1's flip branches
re-derive the window list when `STATE_CAND_WIN_SESSION != S OR list == ""`. S2
sets `STATE_CAND_WIN_LIST=""` on every session-nav/type/backspace/cancel-clear,
so the NEXT flip ALWAYS re-derives for the current candidate. S2's reset is the
"authoritative" invalidation; S1's lazy-derive is the "catch-all" (it also fires
on `SESSION != S` if rename changed a name). Both together = correct under every
ordering (S2-before-S1, S1-before-S2, or S1-not-yet-landed).

## FINDING 7 — No cursor reset needed for rename/delete/refresh-width

- **rename** (session-mgmt.sh): the session is RENAMED but is the SAME session
  (same windows). STATE_CAND_WIN_SESSION (old name) != S (new name) → S1's
  lazy-derive re-derives on the next flip. No S2 edit. (Out of file scope anyway.)
- **delete** (session-mgmt.sh): re-ranks + clamps + re-syncs. The highlight may
  move to a DIFFERENT session → S1's lazy-derive (`SESSION != S`) re-derives. If
  the highlight stays on the same session, the cached list is still valid. No S2
  edit. (Out of file scope.)
- **refresh-width**: changes client width, not index/candidate. No reset.

The contract lists ONLY next-session/prev-session/type/backspace/cancel-clear.
Stay within that scope. (rename/delete live in session-mgmt.sh, a different file.)

## FINDING 8 — Validation approach (deterministic, independent of S1)

- **L1**: `bash -n` + `shellcheck` on input-handler.sh; grep cross-checks:
  - the explicit `""` sync arg: `_lp_preview_dispatch "$_top" ""` (count == 1).
  - session-nav binds: `set_state "$STATE_CAND_WIN_SESSION" "$target"` (== 2:
    next + prev).
  - type/backspace/cancel invalidation: `set_state "$STATE_CAND_WIN_SESSION" ""`
    (== 3: type + backspace + cancel-clear).
  - total `set_state "$STATE_CAND_WIN_LIST" ""` (== 5) +
    `set_state "$STATE_CAND_WIN_CURSOR" "0"` (== 5).
  - NO edits to `_lp_fire_preview`/`_lp_preview_dispatch`/preview.sh/state.sh
    (still carry P2.M1.T2.S1's `win_id="${2:-}"` — assert unchanged).
- **L2**: `tests/run.sh` GREEN — the cursor resets are pure picker-internal STATE
  writes (no behavior change to the existing paths; the sync `""` arg is a
  no-op). No test asserts window-cursor state today.
- **L3**: an isolated-socket SMOKE test that PRE-SEEDS stale window-cursor state
  (`tmux set-option -g @livepicker-cand-win-session STALE ...`) then drives each
  action and asserts the reset. This is DETERMINISTIC and DOES NOT depend on
  S1's next-window/prev-window branches (which may not be landed):
  - drive `next-session` → assert SESSION==filtered[1], LIST=='', CURSOR=='0'.
  - drive `type x` → assert SESSION=='', LIST=='', CURSOR=='0'.
  - drive `backspace` → assert SESSION=='', LIST=='', CURSOR=='0'.
  - drive `cancel` (non-empty filter → clear path) → assert SESSION=='',
    LIST=='', CURSOR=='0'.
  - drive `prev-session` → assert SESSION==target, LIST=='', CURSOR=='0'.
- No new test FILE (the formal window suite is P2.M3.T1.S1); L3 is a throwaway
  `/tmp/smoke_cursor_reset.sh` mirroring the prior tasks' validation style.
