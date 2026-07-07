# Bug Fix Requirements

## Overview

End-to-end QA of the tmux-livepicker implementation (rev 002: theme-matched tabs
§17 + deferred preview §18) against the PRD. Testing was performed on an isolated
tmux socket (separate `-L` socket via a PATH shim, mirroring `tests/setup_socket.sh`),
with attached clients where required, across session mode (default) and window mode,
with `@livepicker-preview-defer` both `on` (default) and `off`, and with the
real zoxide database for the create path.

The shipped test suite (40 tests) passes, but it asserts on window **IDs** rather
than window **indices**, and it uses single-window drivers, so it misses a class of
state-corruption bugs on the primary code path. Several issues were found that
violate the headline "full, exact restoration" invariant (PRD §9 / §15) or leave
the user in a confusing state.

**Summary of findings:**
- 3 Major issues (window-list corruption on every preview; window-mode duplicate
  links; create-on-confirm with sanitized names orphans a session and strands the
  user).
- 3 Minor issues (deferred-preview TOCTOU race; §17 sentinel does not handle
  session-context format specifiers; detached candidate window resized by linking).

Severity call: the index-corruption bug is the most impactful because it fires on
the default code path (session mode, browsing another session, then cancel/confirm)
for any user whose active window is not the last window in its session.

---

## Critical Issues (Must Fix)

None rise to "prevents core functionality from working" — the picker opens,
previews, filters, navigates, switches, and cancels. The issues below are filed as
Major because they silently corrupt session/window state or strand the user.

---

## Major Issues (Should Fix)

### Issue 1: `link-window -a` permanently shifts the driver's window indices (violates exact restoration)

**Severity**: Major (borders Critical; fires on the default code path)
**PRD Reference**: §9 ("Full, exact restoration of status layout, key table, and
focus on exit"), §15 Restore ("The original window's pane layout is exact"), §13
(`link-window -a -s <id> -t <session>:`)

**Expected Behavior**: Browsing the picker (linking candidate windows into the
driver session for preview, then unlinking on exit) must leave the driver
session's window list byte-identical to before activation. In particular, window
indices must not shift.

**Actual Behavior**: `preview.sh` links the candidate window with
`tmux link-window -a -s "$src_id" -t "$current_session:"`. The `-a` flag means
"insert AFTER the active window". When the driver's active window is not the last
window, the linked preview window is inserted in the MIDDLE of the window list,
shifting every subsequent window's index up by one. On exit, `unlink-window`
removes the linked window but leaves the gap (tmux does not renumber on unlink,
even with `renumber-windows on`). The indices never shift back. Result: the
driver's windows are permanently reindexed.

**Steps to Reproduce** (isolated socket):
```
tmux new-session -d -s main -x 200 -y 50
tmux new-window -t main -n editor     # main now: 0:shell 1:editor
tmux new-window -t main -n terms      # main now: 0:shell 1:editor 2:terms
tmux select-window -t main:0          # active = index 0 (shell)
tmux new-session -d -s other
# attach a client to main, then:
tmux set-option -g @livepicker-key C-f
scripts/livepicker.sh
scripts/input-handler.sh next-session   # preview 'other' -> links other's window with -a after index 0
scripts/input-handler.sh next-session   # back to main (self)
scripts/input-handler.sh cancel
tmux list-windows -t '=main' -F '#{window_index}:#{window_name}'
# EXPECTED: 0:shell 1:editor 2:terms
# ACTUAL:   0:shell 2:editor 3:terms   (gap at 1, editor/terms shifted +1)
```
Verified across all four combinations of `@livepicker-preview-defer` (on/off) and
exit mode (cancel/confirm): the shift occurs identically every time. It also
occurs in window mode.

Direct proof of the mechanism:
```
tmux new-session -d -s drv; tmux new-window -t drv -n W1; tmux new-window -t drv -n W2
tmux select-window -t drv:0
# drv: 0:shell 1:W1 2:W2
tmux link-window -a -s @SRC -t drv:      # -> 0:shell 1:<linked> 2:W1 3:W2  (W1/W2 shifted!)
tmux unlink-window -t drv:@SRC           # -> 0:shell 2:W1 3:W2  (gap persists)
```

**Suggested Fix**: Drop the `-a` flag and link at the end of the session so no
existing window is shifted. Verified that `tmux link-window -s "$src_id" -t
"$current_session:"` (no `-a`) appends at the next free index at the END and
unlinks cleanly back to the original indices (`0:shell 1:W1 2:W2` before and
after). Alternatively, link at an explicit high index. The PRD §13 prescription
of `-a` is the root cause and should be revisited. NOTE: the existing tests
(`test_navigate_unlinks_intact`, `test_restore_cancel_layout_exact`) compare
window **IDs**, which are unchanged by a shift; they must be strengthened to also
compare `#{window_index}` ordering before/after.

---

### Issue 2: Window-mode preview of a window in the driver session creates a duplicate link

**Severity**: Major
**PRD Reference**: §7 ("When the highlighted session is the current session, do
not link ... Select the original window"), §7 Mechanism (link-window),
§15 (candidate window intact)

**Expected Behavior**: In window mode, previewing a window that belongs to the
driver (current) session must NOT link it (a session cannot link its own window
into itself usefully); it should simply select that window, mirroring the
session-mode self-session guard.

**Actual Behavior**: `preview.sh`'s self-session guard tests
`[ "$S" = "$current_session" ]`. In window mode `$S` is a `"session:index"`
token (e.g. `driver:1`), which never equals the bare session name `driver`, so
the guard never fires for the driver's own windows. `preview.sh` then calls
`link-window` on a window that is already linked into the current session. tmux
does not fail; it silently creates a DUPLICATE window link. The duplicate
pollutes the driver's window list, shifts indices (compounding Issue 1), and
causes subsequent navigation to resolve the wrong window (because the duplicate
occupies a shifted index, the `"session:index"` token no longer points at the
intended window).

**Steps to Reproduce** (isolated socket, window mode):
```
tmux new-session -d -s driver; tmux new-window -t driver -n workA; tmux new-window -t driver -n workB
tmux select-window -t driver:0
tmux new-session -d -s alpha
# attach client, then:
tmux set-option -g @livepicker-type window
scripts/livepicker.sh
# list is: alpha:0 driver:0 driver:1 driver:2
scripts/input-handler.sh next-session    # alpha:0
scripts/input-handler.sh next-session    # driver:1 (workA) -> links DUPLICATE of @1 into driver
scripts/input-handler.sh next-session    # driver:2 -> resolves the DUPLICATE, not workB
tmux list-windows -t '=driver' -F '#{window_index}:#{window_name}(id=#{window_id})'
# ACTUAL shows a duplicate @1: e.g. 0:zsh(@0) 1:workA(@1) 2:workA(@1) 3:workB(@2)
```
Confirming on `driver:2` then lands on the wrong window (the duplicate, not
workB), and after cancel the driver's window indices are permanently shifted
(see Issue 1).

**Suggested Fix**: Extend the self-session guard in `preview.sh` to window mode:
when `opt_type == window`, compare `${S%%:*}` (the token's session) to
`$current_session`; if equal, skip linking and just `select-window` the resolved
window id. Equivalently, refuse to `link-window` when the source window is
already a member of the current session (check before linking).

---

### Issue 3: Create-on-confirm with a sanitized name orphans the session and strands the user

**Severity**: Major
**PRD Reference**: §6 Confirm ("If creation fails (invalid name), cancel
instead"), §6 Filtering (the typeable set explicitly includes `.`), §11
(`@livepicker-create`, `@livepicker-zoxide-mode`)

**Expected Behavior**: When the user types a query that does not match any
session and presses Enter, either (a) land on the newly created session, or
(b) if the name is genuinely invalid, cancel WITHOUT leaving a created session
behind. In no case should a session be created and then abandoned.

**Actual Behavior**: `.` is in the typeable character set (`a`-`z`, `A`-`Z`,
`0`-`9`, `-`, `_`, `.`, `/`). tmux silently sanitizes session names containing
`.` (and `:`) by replacing them with `_` (`my.proj` becomes `my_proj`). The
confirm path runs `tmux new-session` (which SUCCEEDS with the sanitized name),
then gates on `tmux has-session -t "=$query"` using the ORIGINAL (unsanitized)
query. The exact-match check fails (the live session is `my_proj`, not
`my.proj`), so the branch falls through to `restore.sh cancel`. The session that
was already created (`my_proj`) is NEVER cleaned up, and the user is returned to
their original session with no message, while a phantom `my_proj` session lingers.

**Steps to Reproduce** (isolated socket, session mode, create on):
```
tmux new-session -d -s driver; tmux new-session -d -s alpha
# attach client, then:
tmux set-option -g @livepicker-create on
scripts/livepicker.sh
for c in m y . p r o j; do scripts/input-handler.sh type "$c"; done
# filter is now "my.proj", no match
scripts/input-handler.sh confirm
tmux list-sessions -F '#{session_name}'
# EXPECTED: either land on a session named "my.proj" (impossible) OR no new session
# ACTUAL:   sessions = alpha driver my_proj   (phantom "my_proj" created, user still on "driver")
tmux display-message -p '#{session_name}'   # -> driver (stranded, not my_proj)
```
Reproduced with `my.proj` -> `my_project`, `a:b` -> `a_b`, `.hidden` ->
`_hidden`, `foo bar.baz` -> `foo bar_baz`. In every case an orphan session is
left behind and the user is stranded on the original session with no feedback.

**Suggested Fix**: Either (a) resolve the actual created name after
`new-session` (capture `#{session_name}` of the new session, or parse
`new-session`'s output) and land on THAT, or (b) validate/sanitize the query
BEFORE calling `new-session` and, on detection of an invalid name, cancel
WITHOUT creating it. If the gate fails after a successful `new-session`, the
created session must be killed (`kill-session -t "=$sanitized"`) before
cancelling.

---

## Minor Issues (Nice to Fix)

### Issue 4: TOCTOU race in the deferred-preview supersede guard can orphan a linked window

**Severity**: Minor (narrow window; proven only with an injected delay)
**PRD Reference**: §18 ("A preview whose target was superseded ... must not
clobber the newer link"), §16 ("a late/superseded -b job ... must not clobber
the current link")

**Expected Behavior**: A deferred background preview job whose target was
superseded (by a newer keystroke, navigation, confirm, or cancel) must be a true
no-op and must never leave a linked window behind in the driver.

**Actual Behavior**: `preview.sh` checks `STATE_PREVIEW_SEQ` twice (at entry and
just before the mutating unlink/link block). Between the second check and the
trailing `set_state "$STATE_LINKED_ID" "$src_id"` there is a window that contains
real tmux round-trips (re-read linked_id, unlink-window, link-window,
select-window). If confirm/restore/clear_all_state runs during that window
(unsetting the seq), the late job has already passed its guard and proceeds to
unlink/link/select/set_state, orphaning a linked window in the (now backgrounded)
driver session. With a 0.4s delay injected between the second seq-check and the
unlink, this reproduces 5/5 runs (`driver windows: @0 @1 @1`).

**Suggested Fix**: Re-check the seq one final time immediately before
`set_state "$STATE_LINKED_ID"` (after select-window), and/or make the link
idempotent by checking whether the window is already linked into the current
session before linking. In practice this race is tight (tens of ms) and hard to
hit without load, but it is a genuine gap in the supersede guarantee.

---

### Issue 5: §17 sentinel resolution does not handle session-context format specifiers

**Severity**: Minor (niche; only themes that put session-state specifiers in
window-status-format)
**PRD Reference**: §17 ("The sentinel window", "window-state specifiers resolve
to the sentinel's state")

**Expected Behavior**: With `@livepicker-tab-style window-status`, the renderer
should emit the user's theme-styled tabs with each session's name substituted,
falling back to plain on any resolution failure.

**Actual Behavior**: The sentinel approach bakes `__lp_tab__` (the sentinel
WINDOW name) into the resolved template by resolving `#W`. The renderer then
swaps `__lp_tab__` -> each session name. But if the user's
`window-status-format` / `window-status-current-format` contains a SESSION-state
specifier (e.g. `#S`, `#{session_name}`, `#{session_id}`), the sentinel
resolution expands it to the sentinel SESSION name (e.g.
`__lp_sent_1234_5678`), NOT to `__lp_tab__`. The `__lp_tab__` swap then misses
it, and EVERY tab renders the literal sentinel session name. The unexpanded-`#{`
fallback guard does not catch this because the specifier expanded fully (to the
sentinel's session name), leaving no residual `#{`.

**Steps to Reproduce** (isolated socket):
```
tmux set-option -g window-status-current-format '#[fg=red]#{session_name}#[default]'
tmux set-option -g window-status-format '#[fg=blue]#{session_name}#[default]'
tmux set-option -g @livepicker-tab-style window-status
scripts/livepicker.sh
scripts/renderer.sh
# ACTUAL: every tab shows "__lp_sent_<pid>_<epoch>" instead of the session names
```

**Suggested Fix**: Either document that `window-status` tab style supports only
window-name (`#W`) based themes (and detect/fallback when a session-state
specifier is present), or use a sentinel whose SESSION name is also a stable
placeholder and swap both the window-name and session-name placeholders in the
renderer.

---

### Issue 6: Detached candidate window is resized by linking (pane dimensions change)

**Severity**: Minor (inherent to tmux link-window; affects detached candidates)
**PRD Reference**: §7 ("A linked window is the same window object"), §15
("candidate's window is intact in its own session")

**Expected Behavior**: Previewing a candidate session should not alter the
candidate window's pane layout or size in its own session.

**Actual Behavior**: When a detached candidate's window is linked into the
attached driver (sized, say, 200x50) and selected, tmux's `window-size auto`
resizes the shared window object to the driver's size while it is linked+active.
On unlink, because the candidate has no attached client, the window shrinks to
the no-client default (e.g. 80x24). The pane COUNT and window id are intact, but
the pixel dimensions/geometry change. (If the candidate had its own attached
client, it would size to that client, so this primarily affects detached
candidates.)

**Suggested Fix**: Acceptable as documented tmux behavior, but worth noting in
the README under known limitations, or mitigated by saving/restoring the
candidate window's layout around the preview link (out of scope for the current
restore contract, which only covers the driver's ORIG_WINDOW).

---

## Testing Summary

- Total tests performed (custom QA probes): ~22 scenarios across session/window
  mode, defer on/off, cancel/confirm, special characters, zoxide create,
  status-format restoration, hook restoration, sentinel resolution, and
  injected-delay race forcing.
- Passing: the 40 shipped tests pass; the happy paths (activate, filter,
  navigate, confirm-on-match, cancel, zoxide create with a resolving query,
  theme-tab rendering with `#W`-based formats, status/hook restoration) all work.
- Failing (bugs found): 3 Major + 3 Minor as detailed above.
- Areas with good coverage: status-format save/restore (incl. custom indices),
  session-window-changed hook restore (incl. `-b` flag), pollution invariants
  (client-session-changed never fires while browsing), zoxide resolve + fallback,
  cancel two-step (clear-then-exit), special characters in session names for
  display/filter, sentinel session cleanup.
- Areas needing more attention:
  - **Window INDICES** (not just IDs) before/after a picker cycle — the shipped
    suite never asserts on `#{window_index}` ordering, which is why Issue 1
    escaped detection. Recommend adding a test that snapshots
    `list-windows -F '#{window_index}:#{window_name}'` for a multi-window driver
    and asserts byte-equality after cancel AND after confirm (the driver is left
    corrupted in both cases).
  - **Window mode with driver-owned windows** — the shipped window-mode tests use
    targets in OTHER sessions; none preview/confirm a window that lives in the
    driver session (Issue 2).
  - **Create path with sanitized names** — the shipped create test uses a
    name with no `.`/`:`; add cases that type `.` and assert no orphan session is
    left and the user lands somewhere sensible (Issue 3).
  - **Deferred-preview teardown races** — add a test that injects a delay inside
    preview.sh's mutating block and confirms no orphan link survives confirm
    (Issue 4).
