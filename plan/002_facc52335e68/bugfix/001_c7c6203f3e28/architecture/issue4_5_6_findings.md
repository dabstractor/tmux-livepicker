# Issues 4, 5, 6 Findings: TOCTOU Race, Sentinel Resolution, Detached Resize

## Issue 4: TOCTOU race in the deferred-preview supersede guard

### Bug Location
**File:** `scripts/preview.sh`

| Anchor | Line | Description |
|--------|------|-------------|
| GUARD 1 (entry) | 100-103 | Seq check at top of preview_main |
| GUARD 2 (before mutation) | 172-174 | Seq check before unlink/link block |
| Re-read LINKED_ID | 178 | Freshest linked_id read |
| unlink-window | 182 | Mutation 1 |
| link-window | 187 | Mutation 2 |
| select-window | 195 | Mutation 3 |
| set_state LINKED_ID | 198 | Commit |

### The TOCTOU Window
Between GUARD 2 (line 173) and `set_state` (line 198), the function performs
three tmux server round-trips (unlink, link, select). If confirm/restore/
clear_all_state runs during that window (unsetting the seq), the late job has
already passed its guard and proceeds to unlink/link/select/set_state, orphaning
a linked window.

### Recommended Fix (A + B)

**A. Third seq check (minimal, highest-value):**
Insert between `select-window` (line 195) and `set_state` (line 198):
```bash
tmux select-window -t "$src_id" 2>/dev/null || true
# THIRD SUPERSede CHECK before committing LINKED_ID
if [ -n "$expected_seq" ]; then
    [ "$(get_state "$STATE_PREVIEW_SEQ" "0")" != "$expected_seq" ] && return 0
fi
set_state "$STATE_LINKED_ID" "$src_id"
```

**B. Idempotent pre-link check:**
Before unlinking+linking, probe whether `src_id` is already linked in the driver:
```bash
if tmux list-windows -t "=$current_session" -F '#{window_id}' 2>/dev/null \
     | grep -Fxq "$src_id"; then
    tmux select-window -t "$src_id" 2>/dev/null || true
    set_state "$STATE_LINKED_ID" "$src_id"
    return 0
fi
```
This belongs near the existing duplicate-guard (the `linked_id == src_id` check
at ~line 134). It prevents a losing interleave from creating a duplicate link.

### Empirical verification of idempotent check
`list-windows -t '=drv' -F '#{window_id}' | grep -Fxq '@1'` correctly detects
whether window @1 is already in the driver session (tested on isolated socket).

---

## Issue 5: Sentinel resolution does not handle session-context format specifiers

### Bug Location
**File:** `scripts/livepicker.sh`, `_lp_resolve_tab_templates()` (line 54)
**File:** `scripts/renderer.sh`, window-status render path (line 130)

### Root Cause
- Sentinel window name: `__lp_tab__` (fixed placeholder — renderer swaps it)
- Sentinel session name: `__lp_sent_$$_$(date +%s)` (unique per activation — NOT swappable)

When the format contains `#{session_name}` or `#S`, display-message resolves it
against the sentinel session, producing the unique sentinel session name (e.g.
`__lp_sent_1234_5678`). This string is baked into the cached template. The
renderer only swaps `__lp_tab__`, not the sentinel session name.

### Empirical Proof (isolated socket)
```
#W against sentinel -> '__lp_tab__' (swappable placeholder ✓)
#{session_name} against sentinel -> '__lp_sent_123_456' (NOT swappable ✗)
#S against sentinel -> '__lp_sent_123_456' (NOT swappable ✗)
```

### Recommended Fix: Stable sentinel session name + second renderer swap

**livepicker.sh line 76:**
```bash
# BEFORE: sent_sess="__lp_sent_$$_$(date +%s)"
# AFTER:  sent_sess="__lp_sentinel__"
# Pre-clean any stray sentinel from a crashed prior run:
tmux kill-session -t "__lp_sentinel__" 2>/dev/null || true
sent_sess="__lp_sentinel__"
```

**renderer.sh line 130 (add second swap):**
```bash
ws_seg="${ws_tpl//__lp_tab__/$esc_wname}"
ws_seg="${ws_seg//__lp_sentinel__/$esc_wname}"   # session-name placeholder
```

`${var//pat/rep}` does not re-scan the replacement, so no recursion risk.

### Collision safety
- The plugin is modal — `@livepicker-mode` guard blocks a second activation
- The sentinel lives only during `_lp_resolve_tab_templates` (killed at line 98)
- The pre-clean (`kill-session` before create) handles stray sentinels

---

## Issue 6: Detached candidate window is resized by linking

### Mechanism
tmux's `window-size` (default `latest`/`auto`) resizes a linked window to the
largest/smallest attached client across ALL sessions that have the window linked.
When a detached candidate (80x24) is linked into an attached driver (200x50) and
selected, the shared window object resizes to 200x50. On unlink, the candidate
has no attached client, so it does not restore to 80x24.

### Fix: Document as known limitation (README.md)
The README has no "Known Limitations" section. Recommended insertion: after
"How it works" (ends ~line 164) and before "## Compatibility" (~line 166).

Content:
- Note that linking a detached candidate into an attached driver resizes the
  candidate's window to the driver's dimensions
- On unlink, the candidate's size is NOT restored (inherent to tmux link-window)
- Mention `@livepicker-preview-mode snapshot` as the user-facing workaround
  (snapshot uses capture-pane and never links, so it cannot resize)

### Why not save/restore window-size?
Saving/restoring the candidate's `window-size` and layout around each preview
link is technically feasible but adds 2-3 tmux round-trips per navigation and
changes the visual behavior (panes render at their smaller original size with
empty space around them). Out of scope for this bugfix cycle; documented as a
known limitation instead.
