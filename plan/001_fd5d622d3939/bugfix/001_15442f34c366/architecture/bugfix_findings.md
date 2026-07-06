# Bugfix Findings — Detailed Research (5 Issues)

Research performed by 3 parallel subagents (2 codebase scouts + 1 external tmux
researcher). All findings verified against the current working tree at
`/home/dustin/.config/tmux/plugins/tmux-livepicker`.

---

## ISSUE 1 (Critical) — Duplicate `restore.sh keep-window` call

### Location
`scripts/input-handler.sh`, `confirm` action, window-mode branch:
- **Line 300**: `"$CURRENT_DIR/restore.sh" keep-window` (legitimate first call)
- **Line 301**: `"$CURRENT_DIR/restore.sh" keep-window` (stray DUPLICATE — extra tab indent)

No `return`/`fi`/`;;` between them → both execute sequentially.

### Root cause
The first `restore.sh keep-window` performs full teardown including STEP 6
`clear_all_state`, which **unsets every `@livepicker-orig-*` saved-state key**.
The second call then runs `restore_main` again with all saved state now empty:
- STEP 4 `state_status_format_restore()`: `tmux set-option -gu status-format`
  (clears every index → tmux re-composes defaults) then replays the saved index
  list — which is now **empty** → custom `status-format[0..9]` wiped to defaults.
- `status` ← `get_state(ORIG_STATUS, "on")` → "on" (saved value gone) → non-`on`
  originals (`off`, `2`, `3`) clobbered to `on`.
- `renumber-windows` ← `get_state(ORIG_RENUMBER, "on")` → "on" → `off` clobbered.
- `key-table` ← `get_state(ORIG_KEY_TABLE, "root")` → "root".

### Contrast: session-mode confirm (correct)
`_confirm_land_on_session` (lines 62-118) calls `restore.sh keep` exactly ONCE
(line 117). No duplication. Issue 1 is confined to the window-mode branch.

### Fix
Delete line 301 (the duplicate). The window-mode branch then matches the
single-call discipline of `_confirm_land_on_session`.

### Test gap
`test_restore_preserves_custom_status_format_low_indices` (test_restore.sh:104-137)
covers the **cancel** path only. The window-mode **confirm** path has no
status-format coverage → regression test needed.

---

## ISSUE 2 (Major) — Preview doesn't follow highlight on type/backspace

### Location
`scripts/input-handler.sh`:
- `type` (lines 127-152): updates filter, sets index=0, refresh-client -S. **No preview.sh.**
- `backspace` (lines 159-184): trims filter, sets index=0, refresh-client -S. **No preview.sh.**
- `cancel` query-clear (lines 339-359): clears filter, sets index=0, refresh-client -S. **No preview.sh.**
- `next-session` (line 216): calls `preview.sh "$target"`. ✓
- `prev-session` (line 235): calls `preview.sh "$target"`. ✓

### Root cause
Only nav actions (next/prev) resolve the filtered top match and call preview.sh.
Type/backspace/cancel-clear update the status-line highlight but never sync the
preview pane → highlight and preview desync.

### Nav resolution pattern (the template for the fix)
```bash
cur_list="$(get_state "$STATE_LIST" "")"
cur_filter="$(get_state "$STATE_FILTER" "")"
mapfile -t filtered < <(lp_build_filtered "$cur_list" "$cur_filter")
L="${#filtered[@]}"
[ "$L" -eq 0 ] && return 0
target="${filtered[$new_idx]}"
"$CURRENT_DIR/preview.sh" "$target" 2>/dev/null || true
```

### Fix
For type/backspace/cancel-clear, after setting filter + index=0, resolve the top
filtered match (index 0) and call `preview.sh "$target" 2>/dev/null || true`.
A shared helper `_lp_sync_preview` avoids duplicating the resolution block 3×.
Guard empty filtered list (nothing matches → skip preview, leave prior as-is).

### PRD reconciliation
PRD §5 (data-flow) lists type/backspace as "refresh status" only, but §3
(user story 3) and the README promise the preview follows the top match. The
fix reconciles §5 in favour of §3 / the README.

---

## ISSUE 3 (Minor) — Renderer `#` injection

### Location
`scripts/renderer.sh` — user-controlled strings emitted raw into `#[...]` format:
- **Line 78**: `query> $FILTER (no match) 0/$TOTAL` — `$FILTER`
- **Line 80**: `query> $FILTER (no match)` — `$FILTER`
- **Line 94**: `seg="#[fg=$HFG,bg=$HBG]${filtered[$i]}#[default]"` — candidate name
- **Line 96**: `seg="#[fg=$FG,bg=$BG]${filtered[$i]}#[default]"` — candidate name
- **Line 107**: `query> $FILTER [$((cidx + 1))/$FLEN]` — `$FILTER`

### Root cause
tmux treats `#` as a format-specifier introducer in all format strings. A name
like `#dev` → `#d` expands to day-of-month → `<day>ev`. `#[fg=red]` in a name
injects styling. The ONLY literal-`#` escape is `##` (doubling).

### Fix
Escape every `#` → `##` at emission point using bash parameter expansion:
`esc_name="${filtered[$i]//\#/##}"`. Apply to candidate names (lines 94, 96) and
`$FILTER` (lines 78, 80, 107). **Do NOT escape stored state** — filter.sh and
confirm/select need the raw name.

### filter.sh — no change needed
filter.sh (`lp_build_filtered`) preserves original bytes for matching and confirm
resolution. Escaping belongs only in renderer.sh at emission.

---

## ISSUE 4 (Minor) — Window-mode preview shows active window

### Location
`scripts/preview.sh`, line 115:
```bash
src_id="$(tmux list-windows -t "=$S" -F '#{window_id}' -f '#{window_active}' 2>/dev/null)"
```

### Root cause
`#{window_active}` filter ALWAYS returns the session's active window. In window
mode `$S` is a `session:window_index` token (from `livepicker.sh:103`:
`list-windows -a -F '#{session_name}:#{window_index}'`), but the `#{window_active}`
filter ignores the index. If the highlighted window ≠ active window, src_id is
empty → falls back to capture-pane which also fails.

### Fix
In `preview_main`, branch on `opt_type`:
- **window mode**: parse `S` into `w_sess="${S%%:*}"` + `w_idx="${S#*:}"`,
  resolve the specific window id by index (NOT active):
  `list-windows -t "=$w_sess" -F '#{window_id}:#{window_index}' | awk -F: -v idx="$w_idx" '$2==idx{print $1;exit}'`
- **session mode**: unchanged (the `#{window_active}` path).

The rest of the flow (duplicate guard, unlink, link-window, select-window,
set_state STATE_LINKED_ID) operates on `$src_id` (@id handle) → works unchanged.

### Note
`renumber-windows` is ON during the picker, but the LIST is snapshotted at
activation (stable for picker lifetime). Index→@id resolution at preview time is
correct. Confirm already splits the token correctly (`w_sess="${target%%:*}"`).

---

## ISSUE 5 (Minor) — README references non-existent `./validate.sh`

### Location
`README.md`, line 182 (Validation section):
> a `VALIDATE_SKIP_SLOW=1` budget is available in `./validate.sh` for faster
> static + E2E checks.

### Confirmation
No `validate.sh` exists anywhere in the repo. `tests/run.sh` has no
`VALIDATE_SKIP_SLOW` handling. Users get "No such file or directory."

### Fix
Remove the trailing clause from lines 181-182 so the paragraph ends at
"...sources the user config);" and continues with "The suites cover the PRD §15
clusters:". The real entry point is `bash tests/run.sh` (already documented on
the preceding line).

---

## External tmux research (confirmed)

1. **`#` escape rule**: `##` is the ONLY way to produce a literal `#` in a tmux
   format string. No other character needs escaping for literal output. Standalone
   `{`, `[`, `(` are literal (only special after `#`).

2. **Session/window names CAN contain `#`**: `new-session -s "#dev"` succeeds. tmux
   only sanitizes `:`→`_` and leading `.`→`_`. `#` is legal and stored literally.

3. **`list-windows -f` truthiness**: `-f '#{window_active}'` includes iff expanded
   result is non-empty and non-zero. `-f '#{window_index} == 5'` does NOT filter
   (expands to `5 == 5` → non-empty text → always truthy). Must use
   `#{==:#{window_index},5}` for index comparison, or resolve via target syntax.

4. **Window resolution**: prefer `@id` (stable, server-global) over index
   (fragile under renumber-windows). The plugin's discipline is to address by @id.
