# Delta PRD 003: Status-line redesign, fuzzy ranking, session management, preview clip

> A changeset against the already-shipped, 44/44-green implementation (plan-001 +
> rev-002 §17 theme tabs / §18 deferred preview + bugfix-001). Four new PRD
> sections are added; nothing that already works is rebuilt.

## 0. What changed (diff: 002 → 003)

PRD diff is ~581 lines added across one cohesive theme: **turn the picker from a
substring filter with a trailing `index/total` into a fuzzy-ranked, scrollable,
query-bar status line with in-place session CRUD and a jank-free preview.** Four
new PRD sections drive it:

- **§19 — Status-line layout: query bar, viewport, overflow.** The line-1
  renderer is reworked: a query bar (nerd-font search icon + query) pinned to the
  far-left edge, shown only while typing; ranked tabs in a left-to-right
  scrollable viewport; overflow indicators (`+N>` right, `<` left). The
  `index/total` count indicator is **removed entirely**. Applies to **both**
  `plain` and `window-status` tab styles (§17).
- **§20 — Filtering and ranking (fuzzy).** Replaces the case-insensitive
  substring filter (`filter.sh::lp_build_filtered`) with a fuzzy subsequence
  match + score (`scripts/rank.sh::lp_rank`): matches in order, scored
  (prefix > word-boundary > contiguous > early-position), best-first; non-matches
  hidden; empty query preserves tmux order.
- **§21 — Session management (rename / delete).** `C-r` renames the highlighted
  session via tmux's prompt; `M-BSpace` kills it (with guards + optional confirm).
  Session-CRUD parity with tmux-sessionx so livepicker can replace it.
- **§22 — Preview sizing: clip instead of reflow.** Freeze the driver's
  `window-size` to `manual` before the status grows, so the live preview keeps
  its height and clips its bottom row instead of reflowing every pane. Kills the
  status-grow jank.

Cross-cutting modifications ride with the features (not standalone): §2 non-goals
(fuzzy note), §3 user stories (+6), §5 data flow, §6 behaviors (ranking, scroll,
mgmt summaries; cancel-clear now also resets scroll), §7 (+Sizing subsection),
§8 (+binding step 5), §9 (+window-size/client-width save, +scroll/client-width
clear), §10 (+window-size freeze, +client-width capture + `client-resized` hook),
§11 (options table), §12 (+3 files), §13 (+primitives), §15 (+Layout/ranking/
scroll/management validation §15.28), §16 (+risks), §17 (status-justify ↔ §19
viewport interaction), §18 (renderer PURE+FAST note).

## 1. Invariants that still hold (unchanged by this delta)

- **Invariant A (§4):** browsing never fires `client-session-changed`. The new
  ranking/layout/management/clip work operate inside the current session.
  `rename-session` / `kill-session` mutate *other* sessions, not the client's.
- **Deferred-preview supersede (§18):** all new input paths (scroll, rename,
  delete re-sync) route through the existing `_lp_preview_follow` /
  `_lp_fire_preview` / seq guard. No new inline `link-window`.
- **Save/restore contract (§9):** every new piece of saved state (window-size,
  client-width, client-resized hook) is paired with a restore step; every new
  runtime key is added to `_STATE_RUNTIME_KEYS` so `clear_all_state` tears it
  down. The existing `ORIG_*`/`STATE_*` patterns in `state.sh` are the template.
- **Single source of truth for the list order:** today `filter.sh::lp_build_filtered`
  is shared by renderer + input-handler so what is shown == what nav/confirm
  resolve. `lp_rank` preserves that contract (renderer + input-handler +
  session-mgmt all source `rank.sh`).

## 2. Dependency graph

```
P1 (§19+§20 layout & ranking) ──► P2 (§21 session mgmt: resolves highlight via lp_rank)
   ‖
P3 (§22 preview clip: window-size, orthogonal)   ← independent of P1/P2
   │
   └──► P4 (Mode B changeset-level docs) ◄── P1, P2, P3 all feed it
```

P1 and P3 may proceed in parallel. P2 depends on P1 (it indexes the **ranked**
list). P4 (README + CHANGELOG) runs last.

## 3. Completed work this builds on (do NOT re-implement)

- `scripts/state.sh`: `STATE_*` runtime block, `ORIG_*` saved-state contract,
  `_STATE_RUNTIME_KEYS` clear-list, `state_status_format_save/_restore`,
  `clear_all_state`. Add new keys by the established pattern.
- `scripts/options.sh`: `get_opt` + one `opt_<name>()` per option. Add accessors
  by the single-line pattern after `opt_preview_defer`.
- `scripts/filter.sh::lp_build_filtered`: the **current** shared filter. P1
  supersedes it with `rank.sh::lp_rank`; the 6 call sites switch over (renderer
  ws-path + plain-path; input-handler `_lp_sync_preview_to_top_match`,
  `next-session`, `prev-session`, `confirm`).
- `scripts/renderer.sh::render()`: the plain path + the §17 window-status early
  return. P1 restructures both into the §19 layout (query bar + viewport +
  overflow) and drops `SHOW_COUNT`.
- `scripts/input-handler.sh`: `_lp_preview_follow` / `_lp_fire_preview` /
  `_lp_sync_preview_to_top_match` (the §18 defer machinery), the two-step
  `cancel` (clear query, else cancel). P1 adds scroll-into-view + scroll reset;
  P2 adds `rename`/`delete` actions.
- `scripts/livepicker.sh::activate_main`: STEP 2 save, status grow (T3), key-table
  build (T4), first preview + mode-on (T5). P1 adds client-width capture +
  `client-resized` hook; P2 adds binding step 5; P3 adds window-size freeze.
- `scripts/restore.sh::restore_main`: the 6-step teardown. Each new saved value
  gets a restore line in STEP 4.
- `tests/` harness: `setup_test` isolated socket, `attach_test_client`,
  `assert_eq`/`assert_contains`, the renderer-seed idiom in `test_functional.sh`
  / `test_appearance.sh`. New tests mirror these.
- Prior research in `plan/002_facc52335e68/architecture/`
  (`external_tmux_behavior.md` Q1-Q8, `test_harness.md`) still applies.

---

## Phase P1 — Status-line layout & fuzzy ranking (§19 + §20)

> The central rework. §19 (layout) and §20 (ranking) are one phase because the
> layout renders the order the ranker produces, and both feed the same shared
> `lp_rank` the renderer and input-handler index into.

### Milestone P1.M1 — Foundation: `rank.sh`, `layout.sh`, options, state keys

Add the two new sourced libs, the new options, the new runtime state keys, and
remove the obsolete `show-count` option. No behavior change yet (the libs are
unused until M2/M3); this lands the seams.

**Mode A docs:** `README.md` Configuration table — remove the
`@livepicker-show-count` row; add rows for `@livepicker-nerd-fonts`,
`@livepicker-search-icon`, `@livepicker-query-gap`, `@livepicker-overflow-left`,
`@livepicker-overflow-right-format`. (Full prose notes land in P4.)

#### Task P1.M1.T1 — `rank.sh` fuzzy ranker (supersedes `filter.sh`)

Create `scripts/rank.sh` defining `lp_rank LIST FILTER` that prints matching
session names best-first, one per line (drop-in for `lp_build_filtered`'s
callers: `mapfile -t ranked < <(lp_rank "$LIST" "$FILTER")`). Match rule:
subsequence (every query char in the name, in order, case-insensitive).
Non-matches hidden. Empty filter → all names at score 0 in original order (no
reordering — honours the §2 non-goal). Score: prefix bonus > word-boundary bonus
> contiguity bonus > position penalty; stable tie-break on original order.
Constants not load-bearing; satisfy *exact-prefix > word-boundary substring >
deep subsequence*. Source-once-per-process, tight loop, **no per-name
subshell** (O(N·Q), must stay under the §18 renderer budget).

Delete `scripts/filter.sh` (or reduce `lp_build_filtered` to a thin delegation
to `lp_rank`) — it is fully superseded. Update the 6 call sites + their
`# shellcheck source=filter.sh` directives to source `rank.sh` (renderer
ws-path + plain-path; input-handler `_lp_sync_preview_to_top_match`,
`next-session`, `prev-session`, `confirm`). The behavior must be byte-identical
for an empty filter (order preserved) so existing tests stay green.

#### Task P1.M1.T2 — `layout.sh` viewport math + tab-width measurement

Create `scripts/layout.sh` defining the measurement + scroll helpers sourced by
**both** `renderer.sh` (to slice the visible window) and `input-handler.sh` (to
scroll-into-view), so they can never disagree. Two responsibilities:

1. **Display-width measurement** that strips `#[…]` style directives first (they
   are zero-width but inflate the raw string length — §16 "Viewport
   measurement"). Width of the icon glyph, query, gap, and each tab must all be
   measured this way.
2. **`lp_viewport`/scroll-into-view math**: given the ranked list, the
   available tab width `T = client_width − query_block − active_indicators`,
   and the highlight index, compute the first-visible `scroll` index and the
   set of hidden tabs (left + right, combined count for the `+N>` indicator).

Re-derive the slice every redraw; clamp `scroll` to 0 when the whole list now
fits. Pure functions (read args, return values; no tmux calls — width comes from
the cached `@livepicker-client-width`, M3).

#### Task P1.M1.T3 — options + state keys + remove show-count

`options.sh`: add `opt_nerd_fonts()` (`on`), `opt_search_icon()` (`\uf002`),
`opt_query_gap()` (`2`), `opt_overflow_left()` (`<`),
`opt_overflow_right_format()` (`+%d>`); **remove** `opt_show_count()`.
`state.sh`: add `STATE_SCROLL` (`@livepicker-scroll`) and
`STATE_CLIENT_WIDTH` (`@livepicker-client-width`) to the runtime `STATE_*`
block and append both to `_STATE_RUNTIME_KEYS` (mandatory — else they leak
across picker sessions, per system_context §3 Q4). Initialize both at activate
(scroll=0, client-width captured in M3). `opt_show_count` removal deletes the
`SHOW_COUNT` branch logic in `renderer.sh` (M2).

### Milestone P1.M2 — Renderer rework (query bar + ranked viewport + overflow)

Restructure `render()` so line 1 follows §19 for **both** tab styles. The §17
window-status path is NOT left as a separate early-return that ignores the
layout — both paths go through: query block (icon+query, only while typing) →
ranked tabs sliced by `@livepicker-scroll` → overflow indicators. Drop the
`index/total` count and the `query>` label everywhere.

**Mode A docs:** none beyond the M1 table rows — renderer output is internal
status-line content. (P4 covers user-facing description.)

#### Task P1.M2.T1 — Query-empty and query-active render branches

- **Query empty:** line 1 shows only the session tabs, justified per
  `status-justify`. No icon, no query, no gap, no count.
- **Query active (≥1 char):** `column 0: <icon><query><gap><tabs…><optional +N>>`.
  Icon from `opt_search_icon` if `opt_nerd_fonts` is `on` (emit raw UTF-8).
  Query from `@livepicker-filter` with every `#` doubled (`##`) so tmux renders
  it literally. Gap = exactly `opt_query_gap` spaces (status-justify suspended
  for the tabs while a query is active). Tabs joined by `window-status-separator`
  in window-status mode, single space in plain mode.
- **No-match:** `<icon><query> (no match)` (plain ASCII, shown regardless of
  nerd-font mode). No tabs, no indicators. Create-on-Enter still applies.

#### Task P1.M2.T2 — Viewport windowing + overflow indicators

Window the ranked list by `@livepicker-scroll` to width `T` (via `layout.sh`).
Right indicator `opt_overflow_right_format` with `%d` = **total** hidden tabs
(left + right combined); left indicator `opt_overflow_left` (presence only,
when `scroll > 0`); both can show at once (`< … +N>`); neither when everything
fits. Indicators are chrome (styled `@livepicker-fg`/`bg` or theme style),
never highlighted. Integrate into **both** the plain and window-status render
paths (the §17 early-return must still apply §19, not bypass it — §17 diff:
"status-justify positions the tabs only when there is no query and the tabs
fit; otherwise the section 19 viewport rules apply").

#### Task P1.M2.T3 — Drop SHOW_COUNT

Remove `opt_show_count`, the `SHOW_COUNT_RAW`/`SHOW_COUNT` locals, and every
`[ "$SHOW_COUNT" -eq 1 ]` suffix block in `render()` (plain path + window-status
path + no-match paths). The `query> FILTER [i/N]` suffix is gone entirely.

### Milestone P1.M3 — Input flow: scroll-into-view, scroll reset, client-width cache

Wire the scroll state into the input paths and add the client-width capture +
`client-resized` hook to activate/restore.

**Mode A docs:** none (internal input/activate/restore changes).

#### Task P1.M3.T1 — Client-width capture + `client-resized` hook (activate + restore)

`state.sh`: add `ORIG_CLIENT_RESIZED_HOOK` (`@livepicker-orig-client-resized`)
to the saved-state contract (mirror `ORIG_HOOK`). `livepicker.sh` activate:
after building the list, capture
`tmux display-message -p '#{client_width}'` (resolved against the invoking
client, via the existing `lp_client_format` helper) into `STATE_CLIENT_WIDTH`;
save the prior `client-resized` hook (full `show-hooks` output, mirroring
`session-window-changed`); install a `client-resized` hook that refreshes
`STATE_CLIENT_WIDTH` for the picker duration. `restore.sh` STEP 4: restore the
saved `client-resized` hook exactly (incl. `-b` if present), mirroring the
session-window-changed restore. This cache is what the renderer measures the
viewport against — **no per-keystroke tmux round-trip for width** (§18 budget).
Update the §9 save/restore list and the §10 setup steps to match.

#### Task P1.M3.T2 — Scroll-into-view on nav + scroll reset on type/backspace/cancel-clear

`input-handler.sh`: `next-session`/`prev-session` — after setting the new index,
run the `layout.sh` scroll-into-view rule (if `index < scroll`, set
`scroll = index`; if the highlight's right edge exceeds `scroll + T`, advance
`scroll` until it fits) **before** `_lp_preview_follow`. `type`/`backspace`/the
cancel-clear branch — set `STATE_SCROLL` to `0` alongside the existing
`STATE_INDEX` = 0 reset. Update the comments that claim type/backspace are
"status-only" to note scroll reset is part of the synchronous status update
(it is still status-only — no preview work; scroll is just a state write).

### Milestone P1.M4 — Validation (§15.28 layout/ranking/scroll)

New/updated tests under the existing socket-isolated harness, mirroring the
new §15.28 checklist. Renderer tests need no client (seed state → run
renderer.sh → `assert_contains`); nav/scroll tests need `attach_test_client`.

#### Task P1.M4.T1 — `test_layout.sh` / extend renderer tests

Assert: empty query → only tabs, justified, no icon/query/count; one char typed
→ `<icon><query>` at column 0, exactly `query-gap` spaces, then ranked tabs
left-to-right with top match highlighted; overflow (more tabs than fit) → `+N>`
right with N = total hidden, `<` left after scrolling right, neither when all
fit; no-match → `(no match)`; `show-count` produces no `index/total` anywhere.
Also assert the window-status tab-style path still honors §19 (query bar +
viewport + overflow), not the old full-line join.

#### Task P1.M4.T2 — `test_ranking.sh`

Assert: query `log` → `logs-prod` outranks `blog-engine` (prefix > deep
subsequence); a non-subsequence name is hidden; empty query preserves tmux order
(no reordering); renderer/nav/confirm all agree on `ranked[index]` (no drift —
the single-source-of-truth contract). Assert performance is within the §18
budget for N up to a few hundred (timing or bounded-iteration check).

#### Task P1.M4.T3 — Scroll-into-view + client-width cache tests

Assert: nav past the right edge scrolls the highlight into view and shows `<`;
resizing the client updates `@livepicker-client-width` via the `client-resized`
hook and the next redraw recomputes the viewport; after exit the prior
`client-resized` hook is restored exactly; type/backspace/cancel-clear reset
`scroll` to 0.

---

## Phase P2 — Session management: rename / delete (§21)

> Depends on P1: rename/delete resolve the highlighted item via `lp_rank` +
> `@livepicker-index`, and re-rank after the mutation. Adds `scripts/session-mgmt.sh`,
> three options, two key bindings (activate step 5), and two input-handler actions.

### Milestone P2.M1 — `session-mgmt.sh` + bindings + input dispatch + options

**Mode A docs:** `README.md` Configuration table — add `@livepicker-rename-key`,
`@livepicker-delete-key`, `@livepicker-confirm-delete` rows; `README.md` Usage —
add the rename/delete keybinds and the "driver/last-session refuse" + "delete
key terminal caveat" notes. (Full prose in P4.)

#### Task P2.M1.T1 — Options + key bindings (activate step 5)

`options.sh`: `opt_rename_key()` (`C-r`), `opt_delete_key()` (`M-BSpace`),
`opt_confirm_delete()` (`off`). `livepicker.sh` activate T4: after the nav
bindings (step 4), add step 5 — bind `opt_rename_key` →
`input-handler.sh rename`, `opt_delete_key` → `input-handler.sh delete`. Both
are control keys (distinct tmux keys from the letters `r`/backspace), so they
override any copied same-key binding without colliding with the typing set.

#### Task P2.M1.T2 — `session-mgmt.sh` rename + delete + input dispatch

`input-handler.sh`: add `rename` and `delete` actions that delegate to
`scripts/session-mgmt.sh`. `session-mgmt.sh`:

- **rename** → `tmux command-prompt -I "$S" -p "Rename session:" "run-shell
  '$SCRIPT_DIR/session-mgmt.sh do-rename %%"` (prompts pre-filled). **do-rename
  NEW:** re-resolve `S` from the current index; empty `NEW` → no-op;
  `rename-session -t "=$S" "$NEW"`; if the resulting exact name ≠ `$NEW` (tmux
  sanitizes `:`→`_`, leading `.`→`_`) or a session named `$NEW` exists,
  `display-message` and abort rather than silently mis-renaming; on success
  rewrite `@livepicker-list`, keep the highlight, `refresh-client -S` (no preview
  re-link — rename does not change the window id).
- **delete** → guards first (`S == ORIG_SESSION` → refuse; list length 1 →
  refuse; both via `display-message`, no kill); if `opt_confirm_delete` is `on`,
  `confirm-before` then return; else fall through to **do-delete S**. do-delete:
  if `STATE_LINKED_ID` belongs to `S`, `unlink-window` it from the driver FIRST
  (a window linked into the driver survives `kill-session` of its source — §16
  "kill-session + linked preview leak"); `kill-session -t "=$S"`; rewrite the
  list (drop `S`); clamp index to `min(index, new_len-1)`; re-rank; re-sync the
  preview to the new highlight; `refresh-client -S`.

Window mode (`@livepicker-type window`): `rename-window`/`kill-window` on the
highlighted window, same shape. Escaping caveat: `%%` inside the single-quoted
`run-shell` handles normal names; names with `'`/`"`/`` ` ``/`$` may break —
known limitation, document in README (P4).

### Milestone P2.M2 — Validation

#### Task P2.M2.T1 — `test_session_mgmt.sh`

Assert: rename opens the prompt pre-filled, a new name updates the tab in place,
keeps the highlight, picker stays open; sanitized/collision names abort with a
message and no rename; delete kills and removes the highlighted session, a
neighbour is highlighted+previewed; driver session and last session refuse with a
message and no kill; deleting the currently-previewed session unlinks the
preview window first (no orphan leak into the driver); `confirm-delete on`
prompts `y/n`. All under the isolated socket.

---

## Phase P3 — Preview sizing: clip instead of reflow (§22)

> Independent of P1/P2 (orthogonal — touches driver `window-size`, not the
> layout or ranking). Adds one option and one saved-state key, plus a freeze in
> activate and a restore in restore.sh. **Carries a load-bearing empirical
> verification requirement** (§22 "Verification required").

### Milestone P3.M1 — `window-size` save/freeze/restore + option

**Mode A docs:** `README.md` Configuration table — add `@livepicker-preview-fit`
row. **Reconcile** the bugfix-001 "Known limitations → Detached candidate windows
are resized during preview" note: §22 clip addresses the **status-grow reflow**
(the panes shrinking when the extra status line appears); it does NOT eliminate
the link-time resize of a detached candidate to the driver's size (that remains,
with the `snapshot` workaround). Update the limitation note to distinguish the
two, or note clip reduces the reflow class. (Full prose in P4.)

#### Task P3.M1.T1 — Empirical verification of clip feasibility on tmux 3.6b (load-bearing)

Before coding the freeze, confirm on the isolated socket (mirror the
`research/` findings pattern) that: (a) a `window-size manual` session shows an
oversized active window **clipped** (bottom row hidden), not force-resized back
down; (b) `set-option -t "$SESSION" window-size` isolates to the driver session
(else save/restore globally via `-g`); (c) a window linked into the manual
driver from a differently-sized source clips in the driver without disturbing
the source's attached clients. Record findings. **If any fail**, the feature
falls back to `reflow` (the documented legacy behavior) — do not ship a clip
that force-resizes. This task gates the implementation task.

#### Task P3.M1.T2 — `window-size` save/freeze/restore + `preview-fit` option

`options.sh`: `opt_preview_fit()` (`clip`). `state.sh`: add
`ORIG_WINDOW_SIZE` (`@livepicker-orig-window-size`) to the saved-state contract.
`livepicker.sh` activate: when `opt_preview_fit` is `clip`, save the driver
session's current `window-size`, then `set-option -t "$ORIG_SESSION" window-size
manual` **before** the status grow (§10 step 4 reorders: freeze first, then
grow `status`). `restore.sh` STEP 4: restore the driver's `window-size` to
`ORIG_WINDOW_SIZE` (shrink status back first is already STEP 4's status
restore). Update §9 save/restore list and §7 "Sizing: clip, don't reflow"
subsection to match. `reflow` mode skips the freeze/restore entirely (legacy).

### Milestone P3.M2 — Validation

#### Task P3.M2.T1 — `test_preview_clip.sh`

Assert: on activation (clip mode) the status grows to two lines but the
preview's panes do **not** reflow — the bottom row is clipped; navigating
between candidates re-links without per-nav reflow; after exit the driver's
`window-size` is restored and the panes return to natural size. If the P3.M1.T1
verification showed tmux force-resizes instead of clipping, assert the `reflow`
fallback path instead and document. Mirror the `test_preview.sh` lifecycle
(needs `attach_test_client`).

---

## Phase P4 — Sync changeset-level documentation (Mode B)

> Depends on P1, P2, P3. Sweeps all four features into the README overview and
> CHANGELOG. Do NOT edit `PRD.md` (read-only).

#### Task P4.T1 — README + CHANGELOG changeset sync

- **README.md** — fold the Mode-A table rows added per-feature into a coherent
  Configuration section; add a "Status line" subsection describing the new query
  bar / ranked tabs / scroll / overflow indicators (and that `index/total` is
  gone); add a "Session management" note (rename `C-r`, delete `M-BSpace`,
  driver/last-session guards, delete-key terminal caveat, escaping limitation);
  update the Appearance note (the §19 viewport governs window-status tabs too);
  reconcile the bugfix-001 "Detached candidate resize" limitation with §22 clip
  (distinguish status-grow reflow, now clipped, from link-time resize, which
  persists with the `snapshot` workaround).
- **CHANGELOG.md** — add an `[Unreleased]` entry for all four features noting
  defaults (preview-fit `clip`, preview-defer `on`, tab-style `plain`, nerd-fonts
  `on`, confirm-delete `off`), that none changes the pollution/restore
  invariants (no `client-session-changed` while browsing; `clear_all_state`
  still tears down everything including the new scroll/client-width/window-size
  keys), and the `reflow` / `plain` / `preview-defer off` escape hatches remain.
  Follow the existing entry format and the write-tech-docs style (no em dashes,
  no marketing tell-words).

---

## Open implementation notes (for the breakdown agent)

- **`filter.sh` disposition:** fully superseded by `rank.sh`. Prefer deleting it
  and switching all 6 call sites + `# shellcheck source=` directives; a thin
  delegation shim is acceptable if it reduces churn but the file must not retain
  divergent substring logic.
- **Renderer structure:** both the plain path and the §17 window-status early
  return must adopt §19. Avoid duplicating the layout logic in two places —
  factor the query-bar + viewport + indicator assembly (using `layout.sh`) and
  have both tab-styles plug into it (the only difference is how one tab renders:
  `#[fg=…,bg=…]name#[default]` vs the cached template with the name swapped in).
- **`client-resized` vs `session-window-changed` hooks:** identical save/restore
  shape — full `show-hooks` output captured verbatim, replayed exactly on exit
  (incl. `-b`). Reuse the existing `tmux_get_hook`/`tmux_clear_hook` utils.
- **P2 → P1 ordering is real:** rename/delete and the post-mutation re-rank index
  the **ranked** list, so they cannot land before `lp_rank`.
- **P3 verification gates P3 code:** if clip is infeasible on 3.6b, ship `reflow`
  and document; do not force a broken clip.
- **`set -u`:** every new option read goes through `get_opt`/`opt_*` (defaults
  baked in); every new state read goes through `get_state` with a default. No
  bare `tmux show-option` that can crash the renderer under `set -u`.
