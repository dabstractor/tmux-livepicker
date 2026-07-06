# Research: tests/test_responsiveness.sh — PRD §15.23 / §18 deferred-preview validation (P1.M3.T1.S1)

> Test-only task (no production code). This file captures the verified harness
> contract, the deferred-preview implementation state, and — critically — the
> async-timing strategy that makes the 5 responsiveness tests deterministic
> (non-flaky) under `run.sh`.

## 1. Verified implementation state (all deps LANDED — grep-confirmed 2026-07-06)

| Dependency | Location | Confirmed |
|---|---|---|
| `_lp_fire_preview "$target"` | input-handler.sh:153 | ✅ bumps SEQ, sets TARGET, `run-shell -b "$CURRENT_DIR/preview.sh '$target' '$seq'"` (line 163) |
| `_lp_preview_follow "$target"` | input-handler.sh:175 | ✅ defer=on → refresh-then-fire; defer=off → sync-preview-then-refresh (lines 178/182) |
| `_lp_sync_preview_to_top_match` | input-handler.sh:130 | ✅ delegates to `_lp_preview_follow "$_top"` (line 143) |
| Call sites rewired | type:218, backspace:253, cancel-clear:438 (via `_lp_sync`); next:286, prev:304 (via `_lp_preview_follow`) | ✅ no stray `refresh-client -S` outside the dispatcher |
| preview.sh seq guard | preview.sh:76-97 | ✅ `expected_seq="${2:-}"`; if non-empty AND `cur_seq != expected_seq` → `return 0` (no-op); one-arg path (defer=off/activate) guard-skipped |
| `STATE_PREVIEW_SEQ` / `STATE_PREVIEW_TARGET` | state.sh:48-49 | ✅ both in `_STATE_RUNTIME_KEYS` (line 63) → cleared on teardown |
| `opt_preview_defer()` | options.sh:46 | ✅ default `"on"` |
| `setup_test` defer=off pin | helpers.sh:84-95 | ✅ pins `@livepicker-preview-defer off` per test |

**Consequence**: `tests/run.sh` runs the existing suite on the SYNCHRONOUS path
(defer=off via the pin). `test_responsiveness.sh` must OPT INTO defer=on per test
(`tmux set-option -g @livepicker-preview-defer on`), except the defer=off contrast
test which sets it off explicitly.

## 2. The async timing model (external_tmux_behavior.md Q5/Q6/Q7) — THE crux

- **Q5 — `run-shell -b` is detached/non-blocking AND non-cancellable.** tmux
  launches the command and returns immediately; the job cannot be killed mid-flight.
  Live proof (doc lines 316-324): fire `-b "sleep 1; tmux set @lp_after 1"`, read
  `@lp_after` immediately → EMPTY (job still sleeping) → non-blocking confirmed.
  After `sleep 2`, `@lp_after=1`.
- **Q6 — the supersede pattern.** A monotonic `@livepicker-preview-seq`, bumped at
  fire time (inside `_lp_fire_preview`, BEFORE `run-shell -b` returns), re-checked
  by the bg `preview.sh` job immediately before (line 95-97) AND optionally before
  the first mutation (line 160-162). A mismatch → `return 0` (TRUE no-op: never
  unlinks, never links, never clobbers a newer link). `clear_all_state` unsets the
  seq on teardown → a post-teardown job reads `"0"` ≠ its captured seq → no-op.
- **Q7 — `refresh-client -S` forces `#()` re-evaluation BUT is a no-op on a
  client-less detached socket.** → `attach_test_client` is MANDATORY for every
  responsiveness test (the input handler's `_lp_preview_follow` calls
  `refresh-client -S`; without a client it's a silent no-op). The renderer's
  OUTPUT can be asserted by running `$LIVEPICKER_SCRIPTS/renderer.sh` directly
  (it reads state, client-independent) OR via `display-message -p` (needs client).

### The synchronous-vs-async split (load-bearing for non-flaky tests)

Inside `_lp_preview_follow` (defer=on), in order:
1. `refresh-client -S` — **synchronous** (status redraws now).
2. `_lp_fire_preview`: bump SEQ, set TARGET, launch `run-shell -b` — **synchronous**
   (the state writes + the launch return before `_lp_fire_preview` returns; the bg
   job has NOT run yet).
3. `_lp_fire_preview` returns → `_lp_preview_follow` returns → `input-handler.sh`
   exits. At this instant: **SEQ is bumped, TARGET is set, but `@livepicker-linked-id`
   is UNCHANGED** (the bg `preview.sh` job has only just been launched; it must
   fork bash, source 3 libs, re-check the seq, list-windows, link-window,
   select-window, then `set_state LINKED_ID` — ~30-60ms).

**Therefore** — deterministic, non-flaky assertions:
- **SYNCHRONOUS (immediate read, no sleep, no poll):**
  - `@livepicker-preview-seq` advanced (>0, or == the expected count).
  - `@livepicker-index` moved (nav) / `@livepicker-filter` changed (type).
  - `renderer.sh` output reflects the new query/highlight (it reads state directly).
  - **`@livepicker-linked-id` is STILL the pre-action value** — reliable because the
    bg job's startup (fork+bash+libs+round-trips ≈ 30-60ms) is vastly slower than
    the test's immediate `show-option` read (~5ms). The read completes before the
    bg job's `set_state LINKED_ID` step. (This is the "deferral" proof.)
- **ASYNC (poll with a generous timeout):**
  - `@livepicker-linked-id` EVENTUALLY becomes the target's active window id. Use a
    `wait_linked` poll (100 × 20ms = 2s; healthy sockets link in <50ms). This proves
    the bg job DID run (deferred, not dropped).

The combination (sync seq bump + sync renderer + immediate linked-id-still-old +
eventual linked-id-catches-up) proves deferral deterministically. The eventual-poll
is the reliability backstop: even if the immediate "still old" read were ever beaten
by a freakishly fast job, the seq/renderer/poll assertions still hold.

## 3. Harness contract (test_harness.md — verified)

- Tests are **SOURCED** by `run.sh` (never executed directly). Define `test_*`
  functions ONLY; no side effects at file scope; no `setup_test`/`teardown_test` at
  file scope (run.sh owns the per-test cycle: `setup_test "lp-$$-<name>"` → reset
  `TEST_STATUS=pass` → run the `test_*` in the CURRENT shell → read `TEST_STATUS` →
  `teardown_test`).
- Signal failure ONLY via `fail()` / `assert_eq()` / `assert_contains()` (they set
  `TEST_STATUS=fail`). **NEVER `exit`, NEVER `return`-nonzero-to-abort** (a bare
  `exit` kills `run.sh`). Early `return 0` to skip the rest of a body is OK.
- `set -u` is INHERITED (do not re-declare). Declare every local.
- Public assertion API (the COMPLETE set): `fail msg`, `pass msg`, `assert_eq a b msg`,
  `assert_contains str sub msg`. NO `assert_not_contains`/regex/rc — for negatives,
  write an inline `case "$x" in *<bad>*) fail … ;; esac`; for rc, `cmd || fail …`.
- Non-test helpers MUST be prefixed `lp_` (or anything non-`test_`) so `compgen` does
  not try to run them.
- In scope per test (run.sh sources setup_socket.sh + helpers.sh): bare `tmux` →
  isolated socket; `$LIVEPICKER_SCRIPTS`, `$TEST_DRIVER_SESSION` ("driver"),
  `$TEST_FIXTURE_SESSIONS` ("alpha beta"), `$TMUX_SOCK_DIR`, `attach_test_client`,
  `detach_test_client`, `fail`/`pass`/`assert_*`.
- Baseline fixtures: `driver` (attached-client home; 2 windows: @0 + "extra" 3-pane),
  `alpha`, `beta` (each 1 window; beta split into 2 panes). Created at `-x 120 -y 40`.
- Cleanup is AUTOMATIC (run.sh's `teardown_test` → kill-server + rm shim dir). Tests
  only seed + invoke + assert.
- `attach_test_client [sess="driver"]` spawns a `script` pty client (sleep 0.5 to
  settle); REQUIRED for refresh-client -S / switch-client / display-message -p /
  livepicker.sh activate / confirm / cancel.

## 4. Test design — 5 functions (mapping contract §3 a–e → reliable assertions)

All tests: `attach_test_client` FIRST → set `@livepicker-preview-defer` (on for a–d,
off for e) → drive `$LIVEPICKER_SCRIPTS/livepicker.sh` + `input-handler.sh` → assert.
Window ids are GLOBAL → capture DYNAMICALLY via `tmux list-windows -t "=<sess>" -F
'#{window_id}' -f '#{window_active}'`.

### (a) test_typing_defers_preview — type advances status+seq synchronously, link lags
- defer=on. Activate (first preview = self-session → linked-id ""). Capture L0=linked-id ("").
- Type one char (e.g. "a" → matches alpha). 
- IMMEDIATE: assert SEQ > 0 (bumped synchronously). assert renderer output contains
  the new query "a". assert linked-id == L0 (still "" — bg job hasn't run; the lag).
- POLL: wait_linked alpha_wid → assert linked-id == alpha_wid (eventual deferred link).

### (b) test_rapid_type_confirm_no_backlog — 3 rapid fires collapse to 1 link; confirm lands
- defer=on. Create "xyz" session BEFORE activate (uniquely matches "xyz"; no baseline
  session contains x/y/z). Activate.
- Type x, y, z rapidly (3 fires). IMMEDIATE: assert SEQ == 3 (3 synchronous fires).
- POLL: wait_linked xyz_wid → assert linked-id == xyz_wid (the burst collapsed to ONE
  link via supersede — no backlog). 
- Confirm. Assert client's session == "xyz" (confirm independent of preview, §18 #4).

### (c) test_superseded_preview_noop — two rapid nav fires; only the LATEST target links
- defer=on. Activate. 
- next-session (→ alpha, seq=1), next-session (→ beta, seq=2) — rapidly.
- POLL: wait_linked beta_wid → assert linked-id == beta_wid (the latest target won;
  the alpha fire was superseded → no-op).
- Assert driver has exactly ONE preview window (beta's) — no stray alpha link (the
  stale job never linked/unlinked). Assert alpha's window intact in alpha (source
  undamaged). Settle-sleep + re-assert beta_wid stable (stale job didn't clobber).

### (d) test_nav_moves_highlight_before_preview — nav moves highlight synchronously
- defer=on. Activate (linked-id ""). Capture the pre-nav index.
- next-session. IMMEDIATE: assert @livepicker-index advanced (sync). assert renderer
  output highlights the next session (sync, via refresh-client -S + state read). 
  best-effort: linked-id still "" (lag). 
- POLL: wait_linked alpha_wid → assert linked-id == alpha_wid (deferred catch-up).

### (e) test_preview_defer_off_synchronous — defer=off links synchronously (legacy contrast)
- defer=off (explicit). Activate (linked-id ""). 
- Type one char matching a non-current session (e.g. "a" → alpha). 
- IMMEDIATE (NO poll): assert linked-id == alpha_wid (preview ran inline, synchronously
  — the pre-§18 behavior restored). Assert SEQ == 0 (no fire happened — defer=off path
  doesn't bump the seq).

## 5. Reliability checklist (non-flaky under run.sh)

- ✅ Every async link asserted via `wait_linked` poll (2s timeout; healthy <50ms).
- ✅ Every "deferral/lag" claim backed by a DETERMINISTIC sync assertion (seq/index/
  renderer) + the eventual poll — never the laggy read alone.
- ✅ Every test sets defer explicitly (on/off) — independent of the setup_test pin.
- ✅ `attach_test_client` in every test (refresh-client -S / confirm need a client).
- ✅ Window ids captured DYNAMICALLY (global; never hardcoded).
- ✅ Failure via `fail`/`assert_*` only; no `exit`/`return`-nonzero.
- ✅ TAB indent; `set -u` inherited; locals declared; `lp_`/non-`test_` helper prefix.
- ✅ Each test runs on a FRESH socket (run.sh per-test setup_test/teardown_test) → no leak.
- ✅ File sources nothing; no setup_test/teardown_test at file scope.

## 6. Validation
- `bash -n tests/test_responsiveness.sh` + `shellcheck tests/test_responsiveness.sh`
  (mirror test_functional.sh's `disable=SC2154,SC2016,SC2034,SC2086`).
- `bash tests/run.sh` → all tests PASS (the 5 new + existing suite green on defer=off).
- The 5 new test names appear in run.sh's PASS list (auto-discovered via compgen).
