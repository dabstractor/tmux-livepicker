# Research: P1.M1.T1.S2 — window-index assertion tests for the multi-window driver

> Empirical verification run on the repo's own isolated-socket harness
> (`tests/setup_socket.sh` + `tests/helpers.sh`), tmux 3.6b. This file records the
> ground-truth facts the PRP's test code + validation rely on.

## 1. Environment ground-truth (isolated server)

```
base-index(global)    = 1        # inherited from ~/.tmux.conf
renumber-windows      = on
```

**Implication**: a bare `tmux new-window -t driver` is RISKY — on base-index=1 it
collides ("index in use") the way `test_window_preview_shows_highlighted_window`
already documents (it uses `-a` explicitly for that reason). **Use `new-window -a`**
to append the 3rd window robustly. Confirmed: `new-window -a -n third` appended at
index 3 (after the active 'extra' at index 2) cleanly.

## 2. Baseline driver fixture (from `setup_socket.sh`)

After `setup_test` + `attach_test_client`, the driver has TWO windows:

```
1:zsh  (id=@0, active=0)   # the initial shell window (auto-named)
2:extra(id=@3, active=1)   # the 'extra' window (explicitly named; 3 panes)
```

Adding the 3rd with `new-window -a -n third` and selecting the FIRST window:

```
1:zsh  (active=1)   <- selected as FIRST (lowest index), resolves to @0
2:extra(active=0)
3:third(active=0)
```

The FIRST window is resolved by **lowest index via `@id`** (robust to base-index):

```bash
first_wid="$(tmux list-windows -t "=$TEST_DRIVER_SESSION" -F '#{window_index} #{window_id}' \
             | sort -n | head -n1 | cut -d' ' -f2)"   # -> @0
tmux select-window -t "$first_wid"
```

## 3. The snapshot catches the bug (the whole point of S2)

Snapshot format (per the work-item CONTRACT): `#{window_index}:#{window_name}`.

### With the BUG (`link-window -a`) — driver active = FIRST window (index 1):

```
before = [1:zsh / 2:extra / 3:third]
link-window -a -s @alpha -t driver:   ->  1:zsh 2:zsh(@alpha) 3:extra 4:third   (extra/third shifted!)
unlink-window -t driver:@alpha        ->  1:zsh 3:extra 4:third                   (GAP at 2; permanent)
after  = [1:zsh / 3:extra / 4:third]
byte-equal? NO  -> assert_eq FAILS  (the test CAUGHT Issue 1)
```

### With the FIX (bare `link-window`, S1) — same driver:

```
before = [1:zsh / 2:extra / 3:third]
link-window -s @alpha -t driver:      ->  1:zsh 2:extra 3:third 4:zsh(@alpha)   (appended at END; nothing shifted)
unlink-window -t driver:@alpha        ->  1:zsh 2:extra 3:third                  (CLEAN — original indices)
after  = [1:zsh / 2:extra / 3:third]
byte-equal? YES -> assert_eq PASSES
```

**Conclusion**: the `#{window_index}:#{window_name}` snapshot + `assert_eq` byte-
equality is a faithful oracle for Issue 1. It FAILS with `-a` and PASSES with S1's
bare `link-window`. This is exactly the gap the existing tests have (they assert on
`#{window_id}`, which is invariant under a shift — see issue1_2_findings.md
"Test Coverage Gap").

## 4. The confirm path DOES unlink the driver's preview window (critical)

The confirm test's before/after byte-equality is only valid if the driver's preview
window is removed on confirm. Verified in `scripts/input-handler.sh:79-118`
(`_confirm_land_on_session`):

```bash
# line 95-108: unlink the DRIVER's preview window BEFORE switch-client
if [ -n "$linked_id" ] && [ -n "$orig_session" ]; then
    drv_wins="$(tmux list-windows -t "=$orig_session" 2>/dev/null | wc -l)"   # 4 (3 + linked) > 1
    drv_active="..."
    if [ "$drv_wins" -gt 1 ] || [ "$drv_active" != "$linked_id" ]; then
        tmux unlink-window -t "$orig_session:$linked_id" 2>/dev/null || true  # targets DRIVER by name
    fi
fi
tmux switch-client -t "=$tgt"           # line 112: NOW switch to alpha
"$CURRENT_DIR/restore.sh" keep          # line 117: teardown (keep: no switch back)
```

Key: the unlink targets `$orig_session:$linked_id` (the DRIVER, by saved name),
NOT `current_session`. So it runs BEFORE the client moves to alpha. With a 3-window
driver (+1 linked = 4 windows), `drv_wins > 1` is true → the unlink fires.

Then `restore.sh keep`:
- STEP 1: `current_session`(alpha) != `orig_session`(driver) → unlink SKIPPED (no
  double-unlink; harmless).
- STEP 2 (`keep`, not `keep-window`): `select-window -t "$ORIG_WINDOW"` re-selects
  window 0 in the driver (changes the driver's ACTIVE window, NOT its indices).
- STEP 3 `keep`: no switch-client (client stays on alpha).

**Result**: after session-mode confirm, the driver's window LIST is restored to its
pre-activate 3 windows (preview unlinked), so with S1's fix the indices are
byte-identical to before. The confirm test's assertion is valid. (Cross-checked
against `test_confirm_lands` in test_functional.sh, which already asserts the driver
does NOT hold the preview window after confirm.)

## 5. The cancel path (straightforward)

`input-handler.sh cancel` → `restore.sh cancel`. At cancel time the client is STILL
on the driver (cancel never switches), so `current_session == orig_session == driver`
→ restore STEP 1 unlinks the driver's preview window (the linked alpha window).
Re-selects ORIG_WINDOW, switch-client back to driver. With S1's fix, indices intact.
(Mirrors `test_restore_cancel_layout_exact`, which already exercises this path.)

## 6. Window-name determinism

Window 0 is auto-named ('zsh' here — derived from the login shell). It is STABLE
across the link/unlink cycle because nothing runs in window 0's pane (automatic-rename
only re-evaluates the ACTIVE window's foreground process, and window 0's stays the
shell). To make the snapshot fully deterministic (and diagnostics clearer), the test
explicitly RENAMES window 0 to 'first' after selecting it (`rename-window -t "$first_wid" first`),
which also pins automatic-rename off for that window. The 'extra' window keeps its
baseline name; the 3rd is created with `-n third`. Snapshot: `1:first 2:extra 3:third`.

Renaming is safe: restore does NOT touch window names (names are display-only;
restore replays `#{window_layout}`, key-table, status, etc., by @id), and each test
gets a FRESH isolated server (no cross-test contamination).

## 7. Placement decision: tests/test_restore.sh

Both new tests use the FULL flow (`attach_test_client` → `livepicker.sh` activate →
`input-handler.sh next-session` → `cancel`/`confirm`), which is EXACTLY
test_restore.sh's pattern (see `test_restore_cancel_layout_exact`,
`test_restore_preserves_custom_status_format_low_indices`). test_preview.sh's pattern
(`lp_preview_seed_state` + DIRECT `preview.sh` calls, NO client) does NOT match.
test_restore.sh also owns the exact-restoration invariant (PRD §15.21/§9) these
tests strengthen, and `issue1_2_findings.md` names `test_restore_cancel_layout_exact`
(in that file) as one of the tests that MISSED the bug — so the fix belongs beside it.

## 8. Dependency on S1 (P1.M1.T1.S1)

S2 assumes S1 is applied: `preview.sh`'s link call is BARE `link-window` (no `-a`).
- With S1 applied: both new tests PASS.
- Without S1 (bug present, `-a`): both new tests FAIL — which is the POINT (they
  catch Issue 1).

S2 implementation runs AFTER S1 (per the plan: S1 Implementing, S2 Researching).
The PRP's Validation Loop L3 re-introduces `-a` to PROVE the tests fail without it.
