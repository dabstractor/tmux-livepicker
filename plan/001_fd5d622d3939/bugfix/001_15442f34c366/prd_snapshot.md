# Bug Fix Requirements

## Overview

End-to-end validation of tmux-livepicker against the original PRD, performed as a
creative/adversarial QA pass on top of the shipped `tests/run.sh` suite (which
passes 24/24). The existing suite covers the happy paths well, but several
issues slipped through because the tests do not exercise **window-mode confirm
combined with custom `status-format`**, and none of them assert that **the live
preview tracks the highlight while typing**.

Testing method: every finding below was verified against a fresh **isolated tmux
socket** (the repo's own `tests/setup_socket.sh` PATH-shim harness), driving the
real plugin scripts directly. None of these bugs touches the user's real server.

Summary of findings:

- **1 Critical** — a literal duplicate `restore.sh keep-window` call in the
  window-mode confirm branch that permanently destroys custom `status-format`
  configuration (and force-resets `status`/`renumber-windows`/`key-table`).
- **1 Major** — the live preview does not follow the highlighted candidate when
  the user types or backspaces (only `next-session`/`prev-session` refresh the
  preview). This contradicts PRD §3 user story 3 and the README's "the preview
  follows live" promise.
- **3 Minor** — renderer format-injection with `#` in session names; window-mode
  preview shows the session's active window rather than the highlighted window;
  README references a non-existent `./validate.sh`.

## Critical Issues (Must Fix)

### Issue 1: Duplicate `restore.sh keep-window` call in window-mode confirm destroys user `status-format` (and force-resets global options)

**Severity**: Critical

**PRD Reference**: §2 ("Full, exact restoration of status layout, key table, and
focus on exit"), §9 ("Restore … in order … 4. Restore `status`, every
`status-format[n]`, `renumber-windows`, `key-table`"), §10 (status-format
save/restore).

**Location**: `scripts/input-handler.sh`, the `confirm` action, window-mode
branch, lines 300–301:

```bash
				"$CURRENT_DIR/restore.sh" keep-window
					"$CURRENT_DIR/restore.sh" keep-window
```

There are two consecutive calls to `restore.sh keep-window` (the second has a
different, stray indentation level — it is an accidental duplicate). The first
call performs the full teardown correctly, **including `clear_all_state` which
unsets every `@livepicker-orig-*` saved-state key**. The second call then runs
`restore.sh` *again* with all saved state now empty, which causes permanent
damage:

1. `state_status_format_restore()` runs `tmux set-option -gu status-format`
   (clears **every** index → tmux re-composes defaults) and then replays the
   saved index list — which is now **empty** (cleared by the first call). Net
   effect: **every custom `status-format[n]` override is wiped to tmux defaults.**
2. `status` is set to `get_state(ORIG_STATUS, "on")` → `"on"` (the saved value is
   gone), so any non-`on` original (`off`, or a multi-line `2`/`3`) is clobbered
   to `on`.
3. `renumber-windows` is set to `get_state(ORIG_RENUMBER, "on")` → `"on"`,
   clobbering an original `off`.
4. `key-table` is set to `get_state(ORIG_KEY_TABLE, "root")` → `"root"`.

This is the exact regression that the M2 fix
(`test_restore_preserves_custom_status_format_low_indices`) was meant to prevent
— but that test only covers the **cancel** path. The window-mode **confirm**
path regenerates the duplicate and is uncovered.

**Expected Behavior**: Window-mode confirm tears the picker down exactly once and
leaves `status`/`status-format[*]`/`renumber-windows`/`key-table` byte-identical
to their pre-activation values (same as session-mode confirm and cancel).

**Actual Behavior**: After a window-mode confirm, all custom `status-format`
indices are reset to tmux defaults, and `status`/`renumber-windows`/`key-table`
are forced to `on`/`on`/`root`.

**Steps to Reproduce** (isolated socket; mirrors the repo's test idiom):

```bash
cd /home/dustin/.config/tmux/plugins/tmux-livepicker
source tests/setup_socket.sh; source tests/helpers.sh
setup_test "lp-bug1"; attach_test_client
tmux switch-client -t "=driver" >/dev/null
tmux set-option -g @livepicker-type window
# Genuine user overrides at indices 0..3:
tmux set-option -g 'status-format[0]' '#[fg=red]custom-zero'
tmux set-option -g 'status-format[1]' '#[fg=green]custom-one'
tmux set-option -g 'status-format[2]' '#[fg=yellow]custom-two'
tmux set-option -g 'status-format[3]' '#[fg=blue]custom-three'
tmux new-window -t alpha -n chosenwin
scripts/livepicker.sh
for c in a l p h a; do scripts/input-handler.sh type "$c"; done
scripts/input-handler.sh confirm
# Assert: every status-format[n] still equals the value set above. THEY DO NOT.
for n in 0 1 2 3; do echo "[$n] $(tmux show-option -gqv status-format[$n] | head -c 30)"; done
teardown_test
```

Observed: `status-format[0]` becomes tmux's long default composite,
`status-format[3]` becomes empty. (Control: the **same** overrides are preserved
correctly after a **session-mode** confirm or a cancel, because those paths call
`restore.sh` only once.)

**Suggested Fix**: Delete the stray duplicate line 301 in
`scripts/input-handler.sh` so the window-mode branch calls
`"$CURRENT_DIR/restore.sh" keep-window` exactly once. Add a regression test
(`tests/test_restore.sh` or `tests/test_create.sh`) that sets custom
`status-format[0..3]`, performs a **window-mode confirm**, and asserts each index
round-trips — closing the gap left by the cancel-only M2 test.

---

## Major Issues (Should Fix)

### Issue 2: Live preview does not follow the highlighted candidate when typing or backspacing

**Severity**: Major

**PRD Reference**: §3 user story 3 ("I type `log`. The list filters to matching
sessions; **the preview follows the top match**."), §7 ("Live preview … updating
in real time"), §1 ("previews candidates live, in place"). Also the README,
which states "the area below it shows a live, all-panes preview of the
highlighted candidate" and (Usage §3) "**The preview follows live**."

**Location**: `scripts/input-handler.sh` — the `type`, `backspace`, and
`cancel` (query-clear) actions. Each of them updates `@livepicker-filter` /
`@livepicker-index` and runs `tmux refresh-client -S`, but **none of them calls
`preview.sh`**. Only `next-session`/`prev-session` invoke `preview.sh`
(lines 216 and 235). The backspace branch even documents this as "a known minor
UX gap"; the `type` branch does not acknowledge it at all.

**Root cause / PRD note**: The PRD's own data-flow diagram (§5) lists
`type / backspace: … refresh status` vs `next-session / prev-session: … refresh
preview + status`, so the implementation literally follows §5. However §3 (the
user-facing story) and the README both require the **preview** to follow the top
match when filtering. The two PRD sections contradict each other; the
implementation chose the interpretation that breaks the user-visible behaviour
and the README's explicit promise.

**Expected Behavior**: When the user types (or backspaces) and the top filtered
match changes, the live preview area below the status bar switches to show that
new top match's panes, staying in sync with the highlighted entry.

**Actual Behavior**: Typing moves the status-line highlight to the top match, but
the large preview area stays frozen on whatever session was being shown before
(self-session after activate, or the last navigated session). The highlight and
the preview are out of sync until the user presses a navigation key.

**Steps to Reproduce** (isolated socket):

```bash
cd /home/dustin/.config/tmux/plugins/tmux-livepicker
source tests/setup_socket.sh; source tests/helpers.sh
setup_test "lp-bug2"; attach_test_client
tmux switch-client -t "=driver" >/dev/null
tmux new-session -d -s syslog -x 120 -y 40
tmux new-session -d -s blog   -x 120 -y 40
scripts/livepicker.sh
# Activate's first preview is the self-session (driver) -> @livepicker-linked-id == ""
for c in l o g; do scripts/input-handler.sh type "$c"; done
# After typing "log" the highlight is at the top match (blog), index 0...
echo "filter=[$(tmux show-option -gqv @livepicker-filter)] idx=[$(tmux show-option -gqv @livepicker-index)]"
# ...but the preview was never updated:
echo "linked-id=[$(tmux show-option -gqv @livepicker-linked-id)]  (empty == still showing driver, NOT blog)"
teardown_test
```

Observed: `@livepicker-filter=log`, `@livepicker-index=0`, but
`@livepicker-linked-id=""` — the preview is still the self-session while the
highlight is on `blog`. A second scenario (navigate to `alpha`, then type `log`)
leaves `linked-id` pointing at `alpha` while the highlight jumps to `blog`.

**Suggested Fix**: In `input-handler.sh`, after recomputing the filter and
resetting the index in the `type` and `backspace` actions (and in the
`cancel` query-clear branch), resolve the top filtered match and call
`preview.sh "<top_match>"` (guarding failure like the nav actions do), so the
live preview tracks the highlight. (Reconcile PRD §3 vs §5 in favour of §3 /
the README.) Add a regression test: type a filter matching a non-current session
and assert `@livepicker-linked-id` becomes that session's active window id.

---

## Minor Issues (Nice to Fix)

### Issue 3: Renderer injects session names raw into tmux format strings (`#` causes mis-rendering)

**Severity**: Minor

**PRD Reference**: §10 (renderer draws the list); robustness/§16 (edge cases).

**Location**: `scripts/renderer.sh` — names are interpolated unescaped into
`#[...]` style segments, e.g. `seg="#[fg=$HFG,bg=$HBG]${filtered[$i]}#[default]"`.

**Expected Behavior**: A session name containing `#` (e.g. `#dev`, `csharp#`,
`C#-proj`) renders literally in the picker.

**Actual Behavior**: tmux allows `#` in session names (verified:
`new-session -s "#dev"` succeeds). The renderer emits the name raw inside a
format string, so tmux interprets format specifiers inside the name — e.g. `#dev`
becomes `<day-of-month>ev` (`#d` is tmux's day format). A name like
`#[fg=red]x` would inject styling. (The list/navigation/confirm still work; only
the status-line rendering is wrong.)

**Steps to Reproduce** (isolated socket):

```bash
source tests/setup_socket.sh; source tests/helpers.sh
setup_test "lp-bug3"
tmux new-session -d -s "#dev"
tmux set-option -g @livepicker-list "#dev"
tmux set-option -g @livepicker-filter ""; tmux set-option -g @livepicker-index 0
scripts/renderer.sh   # emits "#dev" raw inside #[...] -> tmux renders #d as day
teardown_test
```

**Suggested Fix**: Escape `#` → `##` (tmux's literal-`#` escape) when emitting
names in the renderer (and in the query/count display if the query can contain
`#`; typing `#` is not bound, but a pre-existing filter value could).

### Issue 4: Window-mode preview shows the session's *active* window, not the specific highlighted window

**Severity**: Minor

**PRD Reference**: §2 non-goals ("the preview shows the candidate's active
window") — arguably by-design, but it degrades the window-picker UX.

**Location**: `scripts/preview.sh` — it always resolves the candidate's window
via `list-windows -t "=$S" -f '#{window_active}'`. In window mode the argument
`$S` is a `session:index` token, but the `#{window_active}` filter ignores the
index.

**Expected Behavior**: In window mode, previewing `session:5` shows window 5.

**Actual Behavior**: preview.sh links the session's *active* window regardless of
the highlighted index; if the highlighted window is not the active one, the
preview either shows the wrong (active) window or falls back to a single-pane
`capture-pane` snapshot.

**Steps to Reproduce**: In window mode with a session that has multiple windows,
navigate the highlight to a non-active window and observe the linked window id —
it is the session's active window, not the highlighted one.

**Suggested Fix**: When `@livepicker-type` is `window`, resolve and link the
specific window at the highlighted index rather than the session's active window
(falling back to `capture-pane` if it cannot be linked).

### Issue 5: README references a non-existent `./validate.sh`

**Severity**: Minor (documentation)

**PRD Reference**: — (documentation accuracy)

**Location**: `README.md` → "Validation" section: "a `VALIDATE_SKIP_SLOW=1`
budget is available in `./validate.sh` for faster static + E2E checks."

**Expected Behavior**: The documented file exists, or the sentence is removed.

**Actual Behavior**: No `validate.sh` exists at the repo root (only
`tests/run.sh`). Users following the README will get "No such file or
directory."

**Suggested Fix**: Either ship a `validate.sh` wrapper or remove/fix the
sentence to reference `tests/run.sh` only.

---

## Testing Summary

- **Total exploratory scenarios run**: 8 (each against a fresh isolated socket,
  in addition to the 24 shipped `tests/run.sh` cases which all pass).
- **Passing**: the shipped 24/24 suite passes; the core invariants
  (no `client-session-changed` while browsing, exactly one switch on confirm,
  byte-exact restore on cancel, key repurpose, create-on-enter, self-session
  preview, double-activation guard) all hold.
- **Failing (newly found)**:
  - Critical 1 (window-mode confirm destroys custom `status-format`) — reproduced.
  - Major 2 (preview does not follow highlight on type/backspace) — reproduced.
  - Minor 3 (renderer `#` injection) — reproduced.
  - Minor 4 (window-mode preview shows active window) — reproduced.
  - Minor 5 (missing `validate.sh`) — confirmed absent.
- **Areas with good coverage**: session-mode happy path, pollution invariant,
  cancel restore, key repurpose, create-on-enter, self-session preview,
  capture-pane fallback.
- **Areas needing more attention**: **window-mode confirm** (Issue 1 slipped
  through because restore tests only cover cancel/session-confirm); **preview
  sync during typing** (Issue 2 — no test asserts the preview tracks the
  highlight on `type`); renderer robustness with special characters (Issue 3);
  window-mode preview correctness (Issue 4).
