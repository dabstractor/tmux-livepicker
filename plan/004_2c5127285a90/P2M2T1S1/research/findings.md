# Research Findings — P2.M2.T1.S1 (confirm session-mode commits the chosen window + self-session path)

Empirically grounded in the CURRENT working tree (git HEAD `4253c5c` "Add
window-flip actions…") + the plan/004 architecture docs. Every code fact below
was read live from the file; tmux facts come from `external_deps.md §1` (verified
on 3.6b). Numbered to align with the PRP's gotchas.

---

## FINDING 1 — the confirm branch: three sub-paths, only ONE changes

`scripts/input-handler.sh` `confirm)` (the `input_main` case body). It re-filters
via `lp_rank`, resolves `target = filtered[cur_index]` (clamped), then branches:

1. **`if [ -n "$target" ]; then`** (3-TAB indent, ~L551):
   - **`if [ "$pick_type" = "window" ]; then … fi`** (4-TAB) — the WINDOW-MODE
     picker. It already commits a window: unlink driver preview (H2-hardened),
     `switch-client -t "=$w_sess"`, `select-window -t "$target"` (session:index),
     `restore.sh keep-window`. **UNCHANGED by this task** (contract item h).
   - **`else … fi`** (4-TAB `else`, 5-TAB body) — **SESSION mode**. TODAY it is a
     single line: `_confirm_land_on_session "$target"` (~L608). **THIS is the body
     this task reworks.**
2. **Empty ranked list** (~L612): session-mode + `opt_create on` → new-session →
   `_confirm_land_on_session "$created"` (~L638); else `restore.sh cancel`.
   **UNCHANGED** (contract item g — a brand-new session has one window).

So the EDIT SURFACE is exactly the 5-TAB `else` body of the session-mode path
(the 3 comment lines + the `_confirm_land_on_session "$target"` call). The
window-mode branch, the create path, and `_confirm_land_on_session` itself are
all left intact (the create path still calls it).

## FINDING 2 — `_confirm_land_on_session` does NOT commit a window (the gap)

`_confirm_land_on_session TARGET` (~L81-112) does exactly three things:
1. H2-hardened unlink of the DRIVER's preview window (`ORIG_SESSION:$linked_id`,
   only when the driver retains another window) — **BEFORE** the switch.
2. `tmux switch-client -t "=$tgt"` (the ONE session switch).
3. `"$CURRENT_DIR/restore.sh" keep`.

There is **NO `select-window`**. The client therefore lands on the target
session's *pre-existing* active window, NOT on the window being previewed/flipped.
This is the gap `gap_analysis_confirm_preview.md §(b)` documents. The rework
adds the window commit (select-window) + the self-session short-circuit.

## FINDING 3 — W resolution: mirror the flip branch's lazy-derive (AUTHORITATIVE)

The window-cursor state is written **synchronously** by the flip/nav actions
(P2.M1.T3.S1/S2); the preview link (`STATE_LINKED_ID`/`STATE_PREVIEW_WIN_ID`) may
LAG (deferred `-b` job). PRD §18 contract #4 + the work-item RESEARCH NOTE both
require confirm to read the window-cursor state **authoritatively** — never the
preview link. Resolution (mirrors `next-window`'s lazy-derive, ~L441-470):

- `cand_win_sess = STATE_CAND_WIN_SESSION`; `cand_list = STATE_CAND_WIN_LIST`;
  `cand_cursor = STATE_CAND_WIN_CURSOR` (sanitize to int, default 0).
- **If `cand_win_sess == S` AND `cand_list` non-empty AND `0 ≤ cursor < len`:**
  `W = list[cursor]` (the user flipped to this window on S).
- **Else:** `W =` S's ACTIVE window: `tmux list-windows -t "=$S" -F '#{window_id}' -f '#{window_active}'`.

Why `cand_win_sess == S` is always true when the list is non-empty: P2.M1.T3.S2
**invalidates** `STATE_CAND_WIN_LIST=""` on every session-nav and every filter
change, and the flip re-derives + binds `STATE_CAND_WIN_SESSION=$S` before
populating the list. So a non-empty list ⟹ it belongs to S. The `cand_win_sess
== S` guard is DEFENSE-IN-DEPTH (correct under any merge ordering with S2).

State at confirm, by last action (verified from P2.M1.T3.S2's reset shapes):
| last action | SESSION | LIST | CURSOR | W |
|---|---|---|---|---|
| session-nav to S (no flip) | `S` | `""` | `"0"` | S active window |
| flip on S | `S` | `<S windows>` | `<flipped idx>` | `list[cursor]` |
| type/backspace/cancel-clear | `""` | `""` | `"0"` | top match's active window |

## FINDING 4 — NON-SELF order: commit W in S → unlink driver → switch → restore keep

PRD §6 Confirm (h3.7) + the contract items (c)(e)(f). The verified window-id form
(`external_deps.md §1`: `select-window -t "=test_sess:@1"` → rc=0 on 3.6b) means
**no fallback** is needed.

1. `tmux select-window -t "=$S:$W"` — the single deliberate candidate mutation
   (Invariant B). Makes W active in S *before* the switch.
2. **H2-hardened unlink** of the driver's preview link, targeting `ORIG_SESSION`
   (NOT the post-switch current session), BEFORE the switch — verbatim the logic
   in `_confirm_land_on_session` (~L89-103) and the window-mode confirm (~L553-575):
   only unlink when `drv_wins > 1 OR drv_active != linked_id` (else unlinking the
   driver's only window would KILL the driver, rc=0). `linked_id` may be empty
   (self/no preview) → skip.
3. `tmux switch-client -t "=$S"` (the ONE switch; client lands on S:W because W is
   already active in S).
4. `"$CURRENT_DIR/restore.sh" keep`.

The select-before-unlink order is safe: `select-window -t "=$S:$W"` targets the
window in the S session context only; it does not touch the driver's link. If
`linked_id == W` (the previewed window == the chosen window), unlinking the
driver's link afterward leaves W active in S (its source) — no orphan.

## FINDING 5 — SELF-SESSION (S == ORIG_SESSION): no switch; one select-window

PRD §6 Confirm: "If `S == ORIG_SESSION` (self): skip the `switch-client`; the
single `select-window -t "$W"` is the whole commit." W is a DRIVER window @id
(the self-session flip selects among the driver's own windows; preview.sh records
it in `STATE_PREVIEW_WIN_ID` and leaves `STATE_LINKED_ID` empty).

- `tmux select-window -t "$W"` (current session == driver; bare `@id` form).
- Drop the driver's prior CROSS-session preview link ONLY when `STATE_LINKED_ID`
  is set AND `!= W`. (Self normally has `linked_id=""`; but a non-self candidate
  previewed earlier — with a deferred preview that hasn't run the self-session
  clear yet — can leave a foreign `linked_id`. `linked_id` is a foreign @id, `W`
  is a driver @id → they always differ; the guard is belt-and-suspenders.)
- NO `switch-client`. `"$CURRENT_DIR/restore.sh" keep`.

## FINDING 6 — `restore.sh keep` dependency: P2.M2.T2 owns the ORIG_WINDOW skip

`restore.sh` STEP-2 (~L97): `if [ "${1:-}" != "keep-window" ] → select-window
$ORIG_WINDOW`. So TODAY:
- `keep` → **re-selects ORIG_WINDOW** (would strand the client on the original
  window — WRONG for a window-commit confirm).
- `keep-window` → skips the re-select (window-mode confirm already uses this).

The contract item (f) mandates `restore.sh keep` and explicitly defers the
"keep must not re-select ORIG_WINDOW" fix to **P2.M2.T2** (unify keep/keep-window).
⇒ **This task calls `restore.sh keep`; correct window-landing depends on P2.M2.T2
landing** (same milestone P2.M2). If this task lands FIRST, the client will be
re-selected to ORIG_WINDOW until P2.M2.T2 lands. The PRP flags this hard
ordering dependency. (Using `keep-window` today would be order-independent, but
the contract specifies the canonical `keep`; follow the contract.)

## FINDING 7 — locals in scope + exact indentation (for the edit anchor)

`input_main`'s `local` declaration (~L249):
`local action char new_filter cur_filter cur_list cur_index L new_idx target pick_type query orig_session linked_id`
⇒ `target`, `pick_type`, `orig_session`, `linked_id` are ALL already in scope
(no new `local` needed for them; declare only the new `S`/`W`/`cand_*`/`drv_*`).

Indentation of the session-mode `else` body (verified via `cat`-style tab count):
- `if [ -n "$target" ]; then` → **3 tabs**
- `if [ "$pick_type" = "window" ]; then` / `else` / `fi` → **4 tabs**
- the session-mode body (the 3 comment lines + `_confirm_land_on_session "$target"`)
  → **5 tabs**

The edit REPLACES the 5-tab `else` body (3 comment lines + the helper call) with
the new W-resolution + self/non-self logic, all at **5-tab** indent. The `else`
(4-tab) and `fi` (4-tab) are preserved.

## FINDING 8 — activate init + teardown of the window-cursor keys (already wired)

`livepicker.sh` activate (~L248-251) inits: `STATE_CAND_WIN_SESSION=ORIG_SESSION`,
`STATE_CAND_WIN_LIST=""`, `STATE_CAND_WIN_CURSOR="0"`, `STATE_PREVIEW_WIN_ID=""`.
All four are in `_STATE_RUNTIME_KEYS` (state.sh ~L72) → `clear_all_state` wipes
them on restore. **No state.sh edit** — the keys exist (P2.M1.T1.S1, COMPLETE).

## FINDING 9 — `set -u` + non-zero rc handling (house style)

input-handler.sh runs `set -u` (inherited; NOT `set -e`). Every `get_state` takes
a default arg; `cand_cursor`/index sanitized via `[[ =~ ^[0-9]+$ ]] || =0`.
`select-window`/`switch-client`/`unlink-window` legitimately return non-zero
(vanished target, singly-linked unlink) → guard with `if` or `2>/dev/null || true`
(mirror the window-mode confirm + `_confirm_land_on_session`). `$CURRENT_DIR` is
the house variable (== scripts/); NEVER `$SCRIPT_DIR`.

## FINDING 10 — README prose anchors (Mode A docs)

- README L12-13: "Confirming lands you on the chosen session (optionally creating
  a new one from / your filter query); cancelling restores…"
- README L169-170: "5. **Confirm:** `Enter` lands on the selection, or creates a
  session from / your query in `session` mode with no match."

The contract's Mode A change: "Confirm now lands on the chosen session AND the
exact window being previewed, not just the session." Both anchors get a minimal
window mention (do not rewrite the surrounding paragraph).
