# Findings — tests/test_session_mgmt.sh (P2.M2.T1.S1)

Empirically verified on isolated `-L` sockets via a PATH shim (mirroring
`tests/setup_socket.sh`). Every command below was run; the real server was
verified byte-identical before/after each block (PRD §15 pollution invariant
holds). Abort messages are NOT observable without an attached client
(`display-message` needs a client) → tests assert on tmux STATE, not message
text.

## Verified mechanics

### E1 — seeded-state `do-rename` (no client needed)
Seed list `printf '%s\n' alpha beta gamma`, filter `""`, index `1`
(highlight=beta), orig-session=driver, mode `on`. Run
`$LIVEPICKER_SCRIPTS/session-mgmt.sh do-rename delta`.
- list → `alpha delta gamma`; index STILL `1`; beta gone; delta exists; mode on. ✅
- do-rename/do-delete are CLIENT-INDEPENDENT (rename-session +
  display-message -p -t "<id>" work without a client; refresh-client -S is
  guarded `|| true`).

### E2 — sanitized / collision abort (no client)
- `do-rename 'be:ta'` → abort: list UNCHANGED `alpha beta gamma`, beta still
  exists, NO `be_ta`/`be:ta` session. ✅ (pre-detect `:` rule)
- `do-rename '.dot'` → abort: list unchanged, beta exists, NO `.dot`/`_dot`. ✅
  (pre-detect leading `.` rule)
- `do-rename alpha` (collision) → abort: list unchanged, beta still beta, alpha
  unchanged. ✅ (rename-session rc!=0 path)
- The `display-message` abort text is NOT observable here → assert on state
  (list/session-name unchanged).

### E3 — seeded-state `do-delete` + clamp + re-sync (no client)
Seed list `alpha beta gamma`, index `1`. Run `do-delete beta`.
- beta gone; list → `alpha gamma`; index clamped to `1` (gamma is now the
  valid neighbour at index 1); `@livepicker-linked-id` = the re-synced preview
  window of the new highlight (gamma). ✅

### E4 — guards via the `delete` action (no client)
- Driver guard: orig-session=driver, highlight=driver (index 0). `delete` →
  driver NOT killed, list unchanged. ✅
- Last-session guard: list length 1 (`lonely`). `delete` → lonely NOT killed. ✅
- Use the `delete` action (not do-delete) to exercise the guards; do-delete has
  a defensive length re-check too but `delete` is the guard entry point.

### E5 — LEAK TEST (load-bearing, EXP D) — BOTH halves verified
Seed list `victim other`, index 0 (highlight victim), orig-session=driver,
linked-id `""`. Call `$LIVEPICKER_SCRIPTS/preview.sh victim` to link victim's
window into the driver (client-independent) → sets linked-id (e.g. `@1`); the
victim's window id appears in `driver`'s `list-windows`.
- CONTROL (reproduces the leak): `kill-session -t '=victim'` DIRECTLY (bypass
  do-delete) → victim's window id SURVIVES in the driver (orphan). ✅
  (This makes the do-delete assertion meaningful, not vacuous.)
- FIX: `$LIVEPICKER_SCRIPTS/session-mgmt.sh do-delete victim` → victim's window
  id is GONE from the driver (no orphan); victim session gone; driver re-synced
  to `other`'s window as the new preview. ✅
- Both should be asserted in the leak test (control + fix) so it is a true
  regression guard.

### E6 — confirm-delete (confirm-before; needs attached client)
- Set `@livepicker-confirm-delete on`. The `delete` action calls
  `tmux confirm-before -p "Kill session S? (y/n)" "run-shell ... do-delete S"`
  and RETURNS without killing. So immediately after `delete`, the victim is
  STILL ALIVE → assert victim survives (confirm-before intercepted). ✅
  (deterministic; no send-keys needed)
- Full exercise: attach a client (`script -qec "tmux attach -t driver" /dev/null
  >/dev/null 2>&1 &`; or the harness `attach_test_client`), run `delete`, then
  `tmux send-keys -t =driver "y" Enter`, sleep ~0.7s, assert victim killed
  (confirm-before → do-delete chain). send-keys targets the session
  (`-t =driver`); the prompt is in the attached client's status line.
- Contrast control: `@livepicker-confirm-delete off` → `delete` kills
  immediately (no prompt). Proves the confirm-before is what gates the kill.

## Pollution / isolation
- All of the above ran via a `TMUX_SOCK_DIR/tmux` shim
  (`exec /usr/bin/tmux -L "$SOCK" "$@"`) so the plugin's bare `tmux` calls hit
  the isolated socket. `/usr/bin/tmux list-sessions` on the REAL server was
  byte-identical before/after. The harness `setup_test` provides this shim +
  pins `@livepicker-preview-defer off` (so do-delete's synchronous
  `preview.sh <new_target>` re-sync is deterministic).

## Key reuse facts (from reading the codebase)
- `scripts/session-mgmt.sh` resolves the highlighted item via
  `_lp_resolve_highlighted()`: reads `@livepicker-list`/`@livepicker-filter`/
  `@livepicker-index`, runs `lp_rank`, clamps index. Empty ranked list → no-op.
- It NEVER reads `@livepicker-mode`; the "picker still active" assertion works
  because do-rename/do-delete simply don't tear down (no restore call).
- `scripts/preview.sh <S>` is CLIENT-INDEPENDENT (reads orig-session/window/
  linked-id from state) — see `tests/test_preview.sh lp_preview_seed_state`.
- `setup_test` (helpers.sh) seeds baseline driver/alpha/beta + pins defer off.
  Tests add their own sessions with bare `tmux new-session -d`.
