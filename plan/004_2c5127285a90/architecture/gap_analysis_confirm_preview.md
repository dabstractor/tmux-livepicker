# Gap Analysis: Confirm & Preview mechanics vs PRD §6/§7

## (a) preview.sh resolves the active window only

`preview.sh:80` signature: `preview_main() { local S="${1:-}" expected_seq="${2:-}"`.
`$2` is the deferred-preview supersede-seq, NOT a window-id.

Session-mode src_id resolution at line 166:
```sh
src_id="$(tmux list-windows -t "=$S" -F '#{window_id}' -f '#{window_active}' 2>/dev/null)"
```
Always the candidate's ACTIVE window. No path accepts a flipped-to window.

Window-mode (opt_type=window) resolution at lines 157-165 resolves a specific
index from the `session:index` token — this is the flat window-picker, NOT the
per-session window-flip axis.

## (b) Confirm resolves session only (no window commit)

`input-handler.sh:398-495` confirm branch. For session mode with a non-empty
target, delegates to `_confirm_land_on_session "$target"` (line 459).

`_confirm_land_on_session` (line 81-112):
1. Unlinks driver preview window `ORIG_SESSION:$linked_id` (H2-hardened)
2. `tmux switch-client -t "=$tgt"` (the one switch)
3. `restore.sh keep`

NO `select-window` for the chosen window. Client lands on the target session's
own active window (whatever it was before browsing).

Window-mode confirm (lines 424-453) DOES commit a window
(`select-window -t "$target"` at line 451), but target is a `session:window_index`
token from the list, not a window-cursor-resolved choice.

Self-session: no explicit `S == ORIG_SESSION` branch. Falls through to
`_confirm_land_on_session`, which issues `switch-client -t "=$ORIG_SESSION"` (a
same-session deduped switch) and performs no `select-window`.

## (c) Changes needed for window-cursor-based preview/confirm

1. **State**: Add `STATE_CAND_WIN_SESSION`/`STATE_CAND_WIN_LIST`/`STATE_CAND_WIN_CURSOR`/
   `STATE_PREVIEW_WIN_ID` to state.sh + `_STATE_RUNTIME_KEYS`.
2. **Preview**: Shift signature to `<session> [window-id] [seq]`. When window-id
   supplied, link THAT window. Self-session flip selects among driver's own windows.
3. **Confirm**: Resolve W from `STATE_CAND_WIN_CURSOR`. Commit with
   `select-window -t "=$S:$W"`. Self-session skips switch-client.
4. **Restore**: STEP 2 `keep` skips `ORIG_WINDOW` re-select.

## (d) Self-session edge case (preview.sh:121-150)

When `check_session == current_session` (== ORIG_SESSION):
1. Drop prior cross-session preview (unlink `$current_session:$linked_id`)
2. Select target: window mode → `select-window -t "$S"`; session mode → `select-window -t "$orig_window"`
3. Return 0 (no link)

Self-session always selects `ORIG_WINDOW` in session mode — no chosen-window concept.
Once window-flip lands, self-session flip must select among driver's own windows.

## (e) Window mode (opt_type=window) vs window-flip axis

Two distinct "window" concepts:
1. **Window-flip axis** (missing): flip through the highlighted session's windows
   via next-window/prev-window, tracked by @livepicker-cand-win-cursor.
2. **Window mode** (@livepicker-type window): flat cross-session window picker.
   Candidate token is `session:window_index` across ALL sessions.

Window mode IS implemented and commits a window at confirm. But it's a different
surface and does not provide per-session flip preview.

## (f) restore.sh keep vs cancel (lines 56-255)

- **STEP 1** (59-95): unlink preview from current_session if == ORIG_SESSION.
  On confirm/keep the client has already switched, so STEP-1 unlink is skipped
  (safe — _confirm_land_on_session already unlinked before the switch).
- **STEP 2** (97-106): `if [ "${1:-}" != "keep-window" ]` → re-select ORIG_WINDOW.
  cancel re-selects (correct); keep-window skips (correct); **keep RE-SELECTS**
  (divergence from PRD §9 — must be fixed so keep also skips).
- **STEP 3** (109-128): cancel → switch-client back to ORIG_SESSION; keep → no switch.
- **STEP 5** (217-228): unconditional `select-layout "$ORIG_LAYOUT"`. Must be
  drift-gated (only if pane geometry changed) per §23.

## Window-id addressing verification

**VERIFIED on 3.6b (isolated socket):** `select-window -t "=test_sess:@1"` → rc=0,
correct window becomes active. The `=$S:@id` form works. No fallback needed.
