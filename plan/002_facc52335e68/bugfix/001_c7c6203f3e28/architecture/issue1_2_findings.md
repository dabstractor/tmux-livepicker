# Research: Issues 1 & 2 — link-window `-a` Index Shift + Window-Mode Self-Session Guard

> **Status:** Code-analysis findings with experiment script appendix. Supervisor confirmed
> empirical tmux runs will be executed separately. Confidence levels are marked per finding.
> Target tmux version: **3.6b** (verified in system_context.md §2).
>
> **Note:** This is a duplicate of `.pi-subagents/artifacts/outputs/research_issue1_2.md`
> (the authoritative runtime output path), placed here per supervisor request.

## Summary

**ISSUE 1** (confirmed by code analysis): `preview.sh:187` calls `link-window -a -s "$src_id"
-t "$current_session:"`. The `-a` flag inserts the linked window after the driver's active
window, shifting all subsequent windows to higher indices. When `unlink-window` later removes
the link, `renumber-windows` does NOT fire (the window still exists in the source session), so
the shifted indices persist permanently. Fix: replace `-a` with an explicit collision-free
target index (e.g., `-t "$current_session:99"` or dynamically computed next-free index).

**ISSUE 2** (confirmed with 100% certainty): `preview.sh:126` checks `[ "$S" = "$current_session" ]`.
In window mode, `$S` is a `session:index` token (e.g., `driver:1`), so this bare comparison
always evaluates to FALSE for driver-owned windows — the guard never fires. Fix: change to
`[ "${S%%:*}" = "$current_session" ]`, a one-token change that extracts the session name from
the token. This idiom is already used in two other places in the same file (lines 62, 144).

---

## ISSUE 1: `link-window -a` Permanently Shifts Driver Window Indices

### Bug Location

| File | Line | Code | Role |
|------|------|------|------|
| `scripts/preview.sh` | **187** | `if ! tmux link-window -a -s "$src_id" -t "$current_session:" 2>/dev/null; then` | **Root cause** — the `-a` flag |
| `scripts/preview.sh` | 182 | `tmux unlink-window -t "$current_session:$linked_id" 2>/dev/null \|\| true` | In-preview unlink (leaves gap) |
| `scripts/restore.sh` | 88 | `tmux unlink-window -t "$current_session:$linked_id" 2>/dev/null \|\| true` | Restore unlink (leaves gap) |

### Mechanism (high confidence — from tmux 3.6b man page + source model)

The tmux man page for `link-window` states:

> If -a is given, the window is moved to the next index up (or down if -b).

This is the same INSERT semantics as `new-window -a` ("inserted after the active one"). The
`-t "$current_session:"` target (bare session, trailing colon) resolves to the session's
**active window**. With `-a`, the linked window is placed at `active_index + 1`. If that
index is occupied, tmux shifts every window at that index and higher up by one to make room.

**Step-by-step failure scenario** (driver has 3 windows at indices 0,1,2; active = 0):

1. `link-window -a -s @cand -t driver:` → inserts @cand after index 0:
   - w0 stays at 0, @cand goes to 1, w1 shifts 1→2, w2 shifts 2→3.
   - Result: `[0:w0, 1:@cand, 2:w1, 3:w2]` — **indices shifted!**

2. `unlink-window -t driver:@cand` → removes the link at index 1:
   - The window @cand still exists in the source session (multiply-linked), so it is NOT
     "closed." The tmux man page for `renumber-windows` says:

     > If on, when a window is **closed** or a session is destroyed, the remaining windows
     > are renumbered to fill the gap.

   - `unlink-window` does NOT close the window → renumber-windows does NOT fire → the gap
     at index 1 persists.
   - Result: `[0:w0, GAP:1, 2:w1, 3:w2]` — **w1 and w2 permanently shifted from 1→2 and 2→3.**

3. Even with `renumber-windows on` (the plugin's setting, confirmed system_context.md §2):
   the renumber trigger fires only on window CLOSE (`kill-window`) or session DESTROY —
   **not** on `unlink-window` of a multiply-linked window. The gap persists.

### Why It Matters

- The user's window indices drift permanently after every preview cycle. A window that was
  at index 1 might be at index 2 or 3 after browsing.
- Keybindings or scripts that address windows by index break.
- The status bar's window list shows wrong numbers.
- Accumulates across multiple preview cycles: previewing N candidates can shift windows by
  up to N positions.

### Proposed Fix Commands

**Option A — explicit high index (simplest):**
```bash
# Place at index 99 — collision-free for any realistic window count, no shift.
tmux link-window -s "$src_id" -t "$current_session:99"
```
The tmux man page: "If dst-window is specified and no such window exists, the src-window is
linked there." Index 99 is free → linked there, no shift. After unlink, the gap at 99 is
the last index → no visible gap. Downside: window briefly appears as "99" in the status bar
(masked by the picker overlay during browsing).

**Option B — dynamically computed next index (cleanest):**
```bash
# Append after the last window without shifting.
last_idx=$(tmux list-windows -t "=$current_session" -F '#{window_index}' 2>/dev/null | sort -n | tail -1)
tmux link-window -s "$src_id" -t "$current_session:$((last_idx + 1))"
```
Places at exactly one past the current maximum. No shift, no high-index ugliness.

**⚠️ NOT a valid fix — bare `-t session:` without `-a`:**
```bash
tmux link-window -s "$src_id" -t "$current_session:"   # FAILS
```
`session:` resolves to the active window. Without `-a`, tmux attempts to place at the
active window's index, which is occupied. Without `-k`, this returns rc=1 ("index in use")
→ the code falls back to `preview_fallback` (snapshot mode) every time. This would silently
disable live preview entirely. **Requires empirical confirmation** (see experiment script).

---

## ISSUE 2: Window-Mode Self-Session Guard Fails for Driver-Owned Windows

### Bug Location

| File | Line | Code | Problem |
|------|------|------|---------|
| `scripts/preview.sh` | **126** | `if [ -n "$current_session" ] && [ "$S" = "$current_session" ]; then` | Bare `$S` comparison — misses `session:index` tokens |

### Mechanism (100% certain — pure bash string semantics)

**In window mode**, `livepicker.sh:183` builds the candidate list as:
```bash
list="$(tmux list-windows -a -F '#{session_name}:#{window_index}' 2>/dev/null)"
```
Each candidate is a `session:index` token like `driver:1`, `alpha:0`, etc. When the user
highlights a driver-owned window, `$S = "driver:1"`.

The guard at line 126:
```bash
[ "$S" = "$current_session" ]    # "driver:1" = "driver" → FALSE → guard MISSES
```
Since `"driver:1" != "driver"`, the guard never fires for driver-owned windows in window
mode. The code falls through to `link-window -a -s @<driver_window_id> -t driver:`, which
silently creates a **DUPLICATE** of the driver's own window (rc=0 — documented in preview.sh
header FINDING 4: "link-window does NOT fail when the window is already linked — it silently
creates a DUPLICATE").

### The Fix (verified — pure bash semantics)

```bash
# Line 126 — change $S to ${S%%:*}:
if [ -n "$current_session" ] && [ "${S%%:*}" = "$current_session" ]; then
```

`${S%%:*}` removes the longest `:*` suffix (colon and everything after):

| `$S` value | `${S%%:*}` | Mode | `[ "${S%%:*}" = "$current_session" ]` |
|---|---|---|---|
| `"driver"` | `"driver"` | session (bare name) | `TRUE` ✓ (unchanged behavior) |
| `"driver:1"` | `"driver"` | window (token) | `TRUE` ✓ (NEW — guard now catches) |
| `"driver:2"` | `"driver"` | window (token) | `TRUE` ✓ |
| `"alpha:0"` | `"alpha"` | window (token) | `FALSE` ✓ (correctly not self) |

**Backward compatibility**: In session mode (`$S` has no colon), `${S%%:*}` returns `$S`
unchanged → identical behavior. **Zero risk of regression.**

**This idiom is already used in the same file** — proving it's a known, tested pattern:
- Line 62 (preview_fallback): `target="=${1%%:*}:${1#*:}."`
- Line 144 (window resolution): `w_sess="${S%%:*}"`
- Line 146 (detection check): `[ "${S%%:*}" != "$S" ]`

### What Happens When the Guard Misses (ISSUE 2 + ISSUE 1 interaction)

1. User highlights driver's own window `driver:1` in window mode.
2. Guard misses → code proceeds to `link-window -a -s @w1 -t driver:` at line 187.
3. tmux creates a DUPLICATE of `@w1` (rc=0) and inserts it with `-a` (ISSUE 1 shift applies!).
4. `set_state "$STATE_LINKED_ID" "$src_id"` tracks the duplicate.
5. On next navigation, `unlink-window -t driver:@w1` removes ONE link — but `@w1` still
   has its original link in the driver. The duplicate is removed, but the index shift from
   the `-a` insertion persists (ISSUE 1).
6. **Combined damage**: a phantom duplicate window appears briefly + permanent index shift.

---

## Test Coverage Gaps

### ISSUE 1 Gaps — No Test Asserts on `#{window_index}`

Every test in `test_preview.sh` and `test_restore.sh` asserts on `#{window_id}` (the stable
@N handle) or `#{window_active}`, but **none assert on `#{window_index}`**. Since `@id`
handles are invariant under renumbering/shift, these tests pass even when indices have drifted:

| Test | File | What It Asserts | Gap |
|------|------|-----------------|-----|
| `test_multipane_preview` | test_preview.sh:70 | linked `@id` present in driver + active | Does NOT verify the linked window's INDEX didn't shift existing windows |
| `test_navigate_unlinks_intact` | test_preview.sh:97 | source session's `@id` list unchanged | Does NOT verify the DRIVER's window indices are preserved through link/unlink |
| `test_restore_cancel_layout_exact` | test_restore.sh:109 | `#{window_id}` + `#{window_layout}` byte-exact | `#{window_id}` is stable through shifts → **masks the index drift entirely** |
| `test_self_session_no_link` | test_preview.sh:124 | no duplicate `@id` after self-preview | Only tests SESSION mode (bare name) — see ISSUE 2 gap |

**Missing test for ISSUE 1**: A test that:
1. Snapshots driver window indices (`#{window_index}` list) before preview.
2. Runs a preview → unlink cycle.
3. Asserts the driver's window INDEX list is unchanged.

### ISSUE 2 Gaps — No Test Exercises Self-Session Guard in Window Mode

| Test | File | What It Tests | Gap |
|------|------|--------------|-----|
| `test_self_session_no_link` | test_preview.sh:124 | Calls `preview.sh "$TEST_DRIVER_SESSION"` (SESSION mode bare name) | Does NOT call `preview.sh "driver:1"` (WINDOW mode token) |
| `test_window_preview_shows_highlighted_window` | test_preview.sh:158 | Window-mode preview of a DIFFERENT session (`multi`) | Does NOT preview the DRIVER's own window in window mode |

**Missing test for ISSUE 2**: A test that:
1. Sets `@livepicker-type window`.
2. Calls `preview.sh "$TEST_DRIVER_SESSION:1"` (driver's own window, window-mode token).
3. Asserts `@livepicker-linked-id` is empty (guard caught it, no link attempted).
4. Asserts no duplicate window was created in the driver.

---

## Edge Cases Discovered

1. **`${S%%:*}` safety**: tmux session names cannot contain colons (the colon is the
   `session:window` separator in tmux target syntax). So `${S%%:*}` is always safe — it
   extracts exactly the session name.

2. **Session-mode backward compatibility**: When `$S = "driver"` (no colon), `${S%%:*}`
   returns `"driver"` unchanged. The fix is a pure no-op in session mode.

3. **Active window position affects shift severity**: If the driver's window 0 is active
   (common during browsing — `select-window -t ORIG_WINDOW` at restore selects the original),
   `-a` inserts after 0, shifting ALL subsequent windows. If the last window is active, no
   shift occurs. The worst case is active=0 with many windows.

4. **Accumulating drift**: Each preview cycle (link → navigate → unlink) can add one unit
   of index drift. After browsing N candidates without restore, windows can shift by up to N.

5. **`preview_fallback` already uses `${1%%:*}`** (line 62) and the window-resolution branch
   already uses `${S%%:*}` (line 144) — proving the codebase already has this exact idiom
   working. The fix at line 126 brings it in line with its siblings.

6. **Restore double-unlink safety**: restore.sh line 88 also does `unlink-window` by `@id`.
   This correctly removes the right window (the @id is stable), but the INDEX gap from the
   original `-a` insertion persists. The fix at preview.sh line 187 prevents the gap from
   being created in the first place.

7. **`renumber-windows on` is a red herring**: The plugin's `renumber-windows on` setting
   does NOT help. It only fires on window CLOSE (kill-window) or session DESTROY — never on
   unlink-window of a multiply-linked window. This is by tmux design, not a bug.

---

## Findings

1. **ISSUE 1 root cause — `preview.sh:187`**: The `link-window -a` flag inserts the linked
   window after the active window position, shifting subsequent windows to higher indices.
   `unlink-window` does not trigger `renumber-windows` (window still exists in source session),
   so the shift is permanent. **Confidence: high** (from tmux man page semantics; exact
   insert-vs-find-free behavior needs empirical confirmation on 3.6b).

2. **ISSUE 1 fix — explicit index**: Replace `link-window -a -s "$src_id" -t "$current_session:"`
   with `link-window -s "$src_id" -t "$current_session:$next_idx"` where `$next_idx` is a
   collision-free index (static `99` or dynamically `max_index + 1`). No shift, no gap.
   **Confidence: high** (from man page: "If dst-window is specified and no such window exists,
   the src-window is linked there").

3. **ISSUE 1: bare `-t session:` without `-a` is NOT a fix**: It resolves to the active
   window's occupied index and fails (rc=1) without `-k`. Would silently disable live preview.
   **Confidence: moderate** — needs empirical confirmation.

4. **ISSUE 2 root cause — `preview.sh:126`**: `[ "$S" = "$current_session" ]` fails for
   `session:index` tokens. In window mode, driver-owned windows bypass the self-session guard
   and create silent duplicates. **Confidence: 100%** (pure bash string semantics).

5. **ISSUE 2 fix — `${S%%:*}`**: Change `$S` to `${S%%:*}` at line 126. One-token change,
   backward-compatible (no-colon strings pass through unchanged). Already used at lines 62
   and 144 in the same file. **Confidence: 100%**.

6. **Test gap — no `#{window_index}` assertions**: All 7 tests across test_preview.sh and
   test_restore.sh assert on `#{window_id}` or `#{window_active}`, never `#{window_index}`.
   ISSUE 1's index shift is invisible to every existing test. **Confidence: 100%**.

7. **Test gap — no window-mode self-session test**: `test_self_session_no_link` only tests
   session mode. No test calls `preview.sh "driver:N"`. ISSUE 2 is invisible to every
   existing test. **Confidence: 100%**.

---

## Gaps

- **Cannot empirically confirm** whether `link-window -a` INSERTS+SHIFTS or FINDS-NEXT-FREE
  on tmux 3.6b. The experiment script (Appendix A) is designed to determine this definitively.
  Supervisor will run it separately.
- **Cannot empirically confirm** whether `link-window -s @id -t session:` (no -a) fails or
  appends.
- **Cannot empirically confirm** whether `link-window -s @id -t session:99` works as expected.

### Suggested next steps (for the implementer):
1. Run Appendix A experiment script on an isolated socket to confirm `-a` behavior.
2. If `-a` confirms INSERT+SHIFT: implement fix Option B (dynamic next-index).
3. Add `test_driver_indices_preserved` test asserting `#{window_index}` list is stable.
4. Add `test_window_mode_self_session_no_link` test calling `preview.sh "driver:1"`.
5. Fix line 126: `$S` → `${S%%:*}` (one-token change, no risk).

---

## Appendix A: Experiment Script

The full experiment script is at `/tmp/lp_research_issue1_2.sh` (also in the authoritative
output at `.pi-subagents/artifacts/outputs/research_issue1_2.md`). It tests:
- `link-window -a` index shift behavior (INSERT+SHIFT vs FIND-FREE)
- `unlink-window` gap persistence with renumber-windows on/off
- `link-window -s @id -t session:0` (occupied, no -a) — expected to fail
- `link-window -s @id -t session:3` (explicit free index)
- `link-window -s @id -t session:99` (high index)
- `link-window -s @id -t session:` (bare, no -a) — fails or appends?
- Self-link duplicate creation (rc=0)
- `${S%%:*}` extraction verification for session and window mode tokens
