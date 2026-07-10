# Research Findings — P2.M1.T2.S1: preview.sh chosen-window + self-session flip

Empirical probes on tmux 3.6b (isolated `-L` sockets) + codebase analysis.

## FINDING 1 — the 3 seq guards reference the `expected_seq` LOCAL, not `$2`

preview.sh binds `local S="${1:-}" expected_seq="${2:-}"` (preview_main, line 80).
All THREE supersede guards reference the LOCAL `expected_seq`, never `$2` directly:

- GUARD 1 (top, ~line 91): `if [ -n "$expected_seq" ]; then cur_seq="$(get_state "$STATE_PREVIEW_SEQ" "0")"; [ "$cur_seq" != "$expected_seq" ] && return 0; fi`
- GUARD 2 (before unlink, ~line 210): `if [ -n "$expected_seq" ]; then [ "$(get_state "$STATE_PREVIEW_SEQ" "0")" != "$expected_seq" ] && return 0; fi`
- GUARD 3 (before set_state LINKED_ID, ~line 253): identical pattern.

CONSEQUENCE: the contract item (b) "update all 3 guards to read from $3" is
satisfied by ONE binding edit: `local S="${1:-}" chosen_win="${2:-}" expected_seq="${3:-}"`.
The guards inherit the new binding automatically. Do NOT edit the guards
themselves — they already use the local. (Editing 3 guards would be 3x the churn
and 3x the error surface for zero behavioral difference.)

## FINDING 2 — `select-window -t "@id"` (bare window-id) selects a driver window

VERIFIED (probe): a 3-window driver session; `select-window -t "@1"` (the second
window's id) → rc=0, the active window became "second". The existing codebase
already selects by bare `@id` everywhere (`tmux select-window -t "$src_id"` in the
idempotent check, the duplicate guard, and after link-window). So the self-session
flip (`tmux select-window -t "$chosen_win"` where chosen_win is `@N`) is the SAME
proven primitive. external_deps.md §1 also confirms `select-window -t "=S:@id"`
(rc=0); the bare form is what the code uses.

## FINDING 3 — `capture-pane -t "=session:@id."` is a valid pane target (rc=0)

VERIFIED (probe): `capture-pane -p -t "=driver:@1."` → rc=0 (valid target). This is
the snapshot target for a CHOSEN window: `=$S:$chosen_win.` — the trailing `.` is
the active pane of that window. It is the SAME structure as the existing
window-mode snapshot target `=${S%%:*}:${S#*:}.` (=session:index.) in preview_fallback
(lines 56-58), just with a window-id where the index goes. So the snapshot
chosen-window path is a one-line target-build: `target="=$S:$chosen_win."`.

## FINDING 4 — preview.sh call sites (all pass target only today; backward-compat)

preview.sh is invoked from 4 places, ALL passing only the session/target (no
window-id, no seq on the inline paths):

1. `_lp_fire_preview` (input-handler.sh:194) — `tmux run-shell -b "$CURRENT_DIR/preview.sh '$target' '$seq'"` (2 args).
2. `_lp_preview_dispatch` defer=off branch (input-handler.sh:234) — `"$CURRENT_DIR/preview.sh" "$target"` (1 arg; inline, no seq → guards skipped).
3. `_lp_sync_preview_to_top_match` → `_lp_preview_dispatch "$_top"` (1 arg; type/backspace/cancel-clear).
4. livepicker.sh first-preview (line 523) — `"$CURRENT_DIR/preview.sh" "$orig_session"` (1 arg; inline).

CONSEQUENCE: extending `_lp_fire_preview TARGET [WIN_ID]` and
`_lp_preview_dispatch TARGET [WIN_ID]` with `win_id="${2:-}"` is BACKWARD-
COMPATIBLE: every existing caller passes 1 arg → `win_id=""` → under the new
preview.sh signature, `$2=""`, `$3=seq` (defer=on) or `$3=""` (inline) → the
chosen_win branches are all skipped (chosen_win empty) → byte-identical session-nav
behavior. livepicker.sh's first-preview (line 523) needs NO change (1 arg →
chosen_win="", seq="" → unchanged). P2.M1.T3 (next-window/prev-window) will be the
FIRST caller to pass a real win_id: `_lp_preview_dispatch "$target" "$win_id"`.

## FINDING 5 — preview_main structure (edit regions, in execution order)

1. **binding** (line 80): `local S="${1:-}" expected_seq="${2:-}"` — FINDING 1 edits here.
2. **GUARD 1** (~91): supersede — inherited, no edit (FINDING 1).
3. **mode gate** (~98-105): `off` → return 0; `snapshot` → `preview_fallback "$S"; return $?`; `live` → fall through. Item (f): snapshot passes chosen_win.
4. **self-session guard** (~121-150): `check_session == current_session` → unlink prior + select + return 0. Item (d): branch on chosen_win.
5. **src_id resolution** (~153-167): window-mode token OR `window_active` fallback. Item (c): add `chosen_win` branch.
6. **idempotent pre-link check** (~174-188): src_id already linked → select + `set_state LINKED_ID src_id` + return 0. Item (e): ALSO set STATE_PREVIEW_WIN_ID here (src_id IS shown).
7. **duplicate guard** (~191-196): `linked_id == src_id` → select + return 0 (no state write; already tracked).
8. **GUARD 2** (~210): supersede — inherited, no edit.
9. **unlink** (~217): drop prior link.
10. **link** (~243): `link-window -s "$src_id" -t "$current_session:"`.
11. **select** (~251): `select-window -t "$src_id"`.
12. **GUARD 3** (~253): supersede — inherited, no edit.
13. **commit** (~259): `set_state "$STATE_LINKED_ID" "$src_id"`. Item (e): ALSO set STATE_PREVIEW_WIN_ID.

## FINDING 6 — STATE_PREVIEW_WIN_ID vs STATE_LINKED_ID (distinct; set both on non-self)

- `STATE_LINKED_ID` (`@livepicker-linked-id`): the LINK HANDLE for unlink on next
  nav / restore. Empty for self-session (nothing linked). Written only on non-self.
- `STATE_PREVIEW_WIN_ID` (`@livepicker-preview-win-id`): the LOGICAL window shown.
  Overlaps LINKED_ID for non-self; DIVERGES for self-session (= chosen_win or
  ORIG_WINDOW, while linked-id stays empty). DEFINED+INIT'd to "" by P2.M1.T1.S1.

RULE (items d/e): wherever a non-self path shows `src_id`, set BOTH
`STATE_LINKED_ID="$src_id"` AND `STATE_PREVIEW_WIN_ID="$src_id"` (idempotent check
+ final commit). On the self-session path, set ONLY `STATE_PREVIEW_WIN_ID`
(chosen_win or ORIG_WINDOW); LINKED_ID stays empty (nothing linked). The duplicate
guard (~196) sets NEITHER (already tracked) — leave it untouched.

## FINDING 7 — snapshot/off do not write STATE_PREVIEW_WIN_ID (contract item f)

- `off` mode: no-op `return 0` (no window shown) — leave STATE_PREVIEW_WIN_ID as-is
  (init ""). No change.
- `snapshot` mode: contract item (f) only requires capturing the chosen window's
  active pane; it does NOT mention STATE_PREVIEW_WIN_ID. Snapshot is a degraded
  (non-live) path and no current consumer reads STATE_PREVIEW_WIN_ID (P2.M2.T1
  confirm reads STATE_CAND_WIN_CURSOR). So snapshot captures only — pass
  chosen_win to preview_fallback so the target is `=$S:$chosen_win.` when a window
  is flipped; no STATE_PREVIEW_WIN_ID write. (Mode is constant for the picker
  lifetime, so live/snapshot never interleave mid-session.)

## FINDING 8 — preview_fallback target build (extend for chosen_win)

Current preview_fallback (lines ~44-62) builds the capture target from `$1`:
- window mode + `$1` has `:`: `target="=${1%%:*}:${1#*:}."` (=session:index.)
- else (session mode): `target="=$1:."` (=session:. = active window's active pane)

EXTEND (item f): accept `chosen_win="${2:-}"`. When chosen_win is non-empty
(session mode + flipped), `target="=$1:$chosen_win."` (=session:@id. — FINDING 3,
rc=0). Keep the existing two branches as-is for the no-chosen_win paths. This is a
pure ADDITION (a new first branch); the existing window-mode and session-mode
default paths are byte-unchanged.

## FINDING 9 — leave-no-trace is already satisfied; the chosen-window branch preserves it

The link flow NEVER targets the candidate session: `unlink-window -t
"$current_session:$linked_id"` and `link-window -s "$src_id" -t "$current_session:"`
both target the DRIVER (`$current_session`), and `select-window -t "$src_id"`
selects the (now-linked) window in the driver. The new `chosen_win` only changes
WHICH window id is resolved as `src_id` (FINDING 5 step 5) — it flows into the same
unlink/link/select-on-the-driver sequence. So Invariant B (leave-no-trace on the
candidate) is preserved by construction; no extra guard needed.

## FINDING 10 — backward-compat proof (session-nav unchanged)

With chosen_win="" (every current caller): the src_id resolution takes the existing
`window_active` fallback (chosen_win branch skipped); the self-session guard
selects ORIG_WINDOW (chosen_win branch skipped); the non-self link flow is
identical. The ONLY new side-effect on session-nav is the ADDITIONAL
`set_state "$STATE_PREVIEW_WIN_ID" "$src_id"` (non-self) / `=ORIG_WINDOW`
(self) writes (item d/e) — pure STATE additions, read by no current consumer, and
cleared by `_STATE_RUNTIME_KEYS` (P2.M1.T1.S1 wired teardown). So no existing test
can regress (the existing functional/preview/restore suites assert on LINKED_ID,
index, session — none assert PREVIEW_WIN_ID; PREVIEW_WIN_ID is additive).
