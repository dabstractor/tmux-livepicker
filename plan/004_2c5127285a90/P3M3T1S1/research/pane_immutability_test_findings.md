# P3.M3.T1.S1 — `test_pane_immutability.sh` (Invariant C suite) research findings

Synthesis for writing `tests/test_pane_immutability.sh` (PRD §15.23 + §23). This
suite VALIDATES the full §23 stack that is landing in parallel: the §22 driver
clip (COMPLETE), the candidate pin (P3.M2.T2.S1 — parallel CONTRACT), the
pane-geometry snapshot (P3.M2.T1.S1 — COMPLETE), and the drift-gated restore
(P3.M2.T1.S2 — parallel CONTRACT). The test CONSUMES all four; it adds no code.

## 1. The assert shape (from the COMPLETE gate — pane_immutability_verification.md §4)

The gate's §4 "Assert shape for P3.M3.T1" is the literal recipe. Capture BOTH:

```bash
# window_layout embeds per-node dims + a 4-hex checksum → byte-identical == no mutation.
geom="$(tmux display-message -p -t "$wid" '#{window_layout}')"
# sorted list-panes = the explicit §23 per-pane proof (dims left/top/width/height).
panes="$(tmux list-panes -t "$wid" -F '#{pane_id}:#{pane_left},#{pane_top},#{pane_width},#{pane_height}' | sort)"
```

Assert `geom_before == geom_after` AND `panes_before == panes_after`. Use `assert_eq`
(from helpers.sh). This mirrors exactly what `test_preview_clip.sh` and
`test_window_flip.sh` capture, and what the gate proved byte-identical (ARM B).

## 2. Contract dependencies (all landing; this suite validates them)

| Dependency | Status | What the test relies on |
|---|---|---|
| §22 driver clip (`livepicker.sh` T3) | COMPLETE | driver `window-size manual` + height pin at activate → shared window not reflowed on status grow |
| Candidate pin (P3.M2.T2.S1) | parallel (CONTRACT) | preview.sh pins a DETACHED candidate (`window-size manual` + `resize-window -y H_cand`) before `link-window`, gated on `[ clip ] && [ -z list-clients ]`; restores on unlink/teardown. HOLDS candidate geometry byte-identical (gate ARM B) |
| Pane-geometry snapshot (P3.M2.T1.S1) | COMPLETE | `@livepicker-orig-pane-geometry` captured at activate (STEP 2, PRE-grow), format `'#{pane_id}:#{pane_left},#{pane_top},#{pane_width},#{pane_height}'` one line per pane |
| Drift-gated restore (P3.M2.T1.S2) | parallel (CONTRACT) | restore.sh STEP 5 cancel-only: re-capture current geometry, compare to snapshot; on NO drift → pure no-op (NO `select-layout`, NO `resize-window`); on drift → `resize-window -y H_orig` then `select-layout`. keep/keep-window skip STEP 5 |

This suite is the VALIDATION of the above; if any piece is missing/buggy the test
fails (that is the point — it is the load-bearing §23 gate per the gate doc §7).

## 3. Harness patterns to reuse (tests/setup_socket.sh + helpers.sh + run.sh)

- **run.sh** sources setup_socket.sh + helpers.sh + every `test_*.sh`, then PER test
  calls `setup_test "lp-$$-<name>"` (→ fresh isolated -L socket + PATH shim + baseline
  fixtures driver/alpha/beta, AND pins `@livepicker-preview-defer OFF` for synchronous
  preview) → resets `TEST_STATUS=pass` → runs `test_*` in the CURRENT shell →
  `teardown_test`. So when a `test_*` runs: bare `tmux` hits the isolated socket;
  `attach_test_client` / `$LIVEPICKER_SCRIPTS` / `$TEST_DRIVER_SESSION` / `fail` /
  `pass` / `assert_eq` / `assert_contains` are ALL IN SCOPE. **This file sources
  NOTHING and calls NO setup_test/teardown_test.** `set -u` is INHERITED (do NOT
  re-declare). Mirror `test_preview_clip.sh` / `test_window_flip.sh` headers.
- **attach_test_client [sess]**: spawns a `script` pty attached to the driver (default
  `$TEST_DRIVER_SESSION`). MUST be called before `livepicker.sh` (scripts need a client
  for `display-message -p '#{window_height}'`). teardown_test → detach_test_client.
- **Helpers**: `fail msg` (sets TEST_STATUS=fail, NEVER exits), `pass msg`, `assert_eq a b msg`,
  `assert_contains str sub msg`. Signal failure ONLY via fail/assert_*.
- **input-handler.sh actions** (verified at scripts/input-handler.sh): `type <char>`,
  `backspace`, `next-session`, `prev-session`, `next-window`, `prev-window`, `confirm`,
  `cancel`. Call as `"$LIVEPICKER_SCRIPTS/input-handler.sh" <action> [arg] >/dev/null 2>&1`.
  Synchronous when defer is OFF (setup_test pins it off).
- **non-pollution / "restore live state"**: the harness isolates the socket (setup_socket
  PATH shim → `tmux -L "$TEST_SOCKET"`); the REAL server (`/tmp/tmux-$UID/default`) is
  NEVER touched. teardown_test kills the isolated server + cleans tmp. So "ALWAYS restore
  the user's live state" (work item) is satisfied structurally — but each test should still
  end its picker lifecycle cleanly (`cancel`) for determinism before teardown.

## 4. The 5 test cases (mapped to work item a–e + gate §4)

### (a) NO CANDIDATE PANE MOVEMENT (the core Invariant C)
- Fixture: detached candidate `immA` with window W1 (3 panes: `split -h` + `split -v`) +
  W2 + W3 (so flipping has targets). Create BEFORE the picker opens.
- Flow: attach → activate (clip default) → capture W1 geometry (`window_layout` + sorted
  list-panes) → type `immA` to highlight (preview links W1 → candidate pin fires) →
  `next-window` ×N (flip through W1/W2/W3) → move to another candidate `immB` (clear filter
  + type `immB`) → `cancel`.
- Assert: W1 geometry byte-identical before/after (gate ARM B + ARM D — flip is safe under
  per-window pinning). Read W1 via `=immA:$wid` (@id stable; candidate active unchanged
  by flip — Invariant B, verified test_window_flip FINDING 3).
- ALSO assert `immA` session `window-size` is restored (unset/no-trace) after cancel (the
  candidate pin restore — P3.M2.T2.S1 STEP 1).

### (b) NO STATUS-GROW REFLOW (candidate not yet linked)
- Fixture: detached candidate `immA` with multi-pane window.
- Flow: capture W1 geometry → attach + activate (status 1→2) → assert `status==2` →
  re-capture W1 geometry. (Candidate NOT previewed/linked — just the status grow.)
- Assert: W1 geometry byte-identical. (For a DETACHED candidate the global status grow
  exerts no reflow — no client. The §22 driver clip pins the driver; the candidate is
  untouched until linked. Gate §5: global status grow only disturbs CLIENT-BEARING
  sessions by 1 row; detached candidates are immune.)

### (c) NO CONFIRM SIDE-EFFECTS
- Fixture: `immA` with W1 (3 panes, active), W2, W3.
- Flow: attach + activate → type `immA` → capture ALL windows (`window_id:window_active:window_layout`)
  + W1 pane geometry → `next-window` to flip to a NON-active window W (e.g. W2) → capture
  W's geometry → `confirm` → lands on (immA, W).
- Assert: (1) immA's OTHER windows (W1, W3) `window_layout` byte-identical (unchanged);
  (2) within W only active-window selection changed (W is now immA's active —
  `list-windows -f window_active` == W); (3) W's pane geometry byte-identical.
  (Confirm re-selects the chosen window as active in the target session; the candidate pin
  held W's geometry through the link, so confirming does not reflow it.)

### (d) ORIGINAL WINDOW INTACT + drift gate no-op
- Fixture: the driver's ORIG_WINDOW is the active window at activate. Baseline driver has
  a 3-pane `extra` window that is active — OR use `display-message -p '#{window_id}'` to
  grab the active @id as ORIG_WINDOW, and give it a multi-pane layout if needed.
- Flow: attach → capture ORIG_WINDOW geometry (pre-activate snapshot) + read
  `@livepicker-orig-pane-geometry` (P3.M2.T1.S1 captures it at activate) → activate →
  full browse (type `immA`, flip windows, move to `immB`) → `cancel`.
- Assert: (1) ORIG_WINDOW geometry byte-identical before/after (the §22 clip held it);
  (2) "select-layout did NOT run" — proxy: the re-captured ORIG_WINDOW geometry EQUALS the
  `@livepicker-orig-pane-geometry` snapshot (proving the drift gate found NO drift →
  STEP 5 no-op, no `select-layout`). Cannot directly observe select-layout; byte-identical
  geometry + snapshot==current is the deterministic proof of the no-op path (P3.M2.T1.S2).

### (e) SNAPSHOT MODE (escape hatch — invariant holds trivially)
- Flow: set `@livepicker-preview-mode snapshot` → attach + activate → type `immA` →
  the preview calls `preview_fallback` (capture-pane, NEVER `link-window` — verified
  scripts/preview.sh:121-126) → `next-window` (still no link) → `cancel`.
- Assert: (1) `@livepicker-linked-id` stays EMPTY (no link attempted); (2) immA's W1
  geometry byte-identical (trivially — never linked). This is the gate's escape hatch
  (§5): for setups where live linking cannot hold the invariant, snapshot never touches
  a live window → invariant holds trivially.

## 5. Candidate naming (conflict-free — verified)

Names already used across `tests/*.sh`: driver, alpha, beta, zzcand, qqmulti, xxA, yyB,
cand, multi, gamma, lonely, other, stale, victim, xyz, blog, syslog. **Use `immA`, `immB`**
(immutability) — none is a subsequence of any existing name; type loops `i m m A` /
`i m m B`. "type to highlight" is the deterministic highlight mechanism (test_window_flip
FINDING 2 — do NOT use next-session to reach a named candidate).

## 6. Gotchas (condensed — gate §6 + test_window_flip findings)

1. **MUST use a real attached client** (work item): `attach_test_client` before activate.
   Sessions created with `-x -y` alone are size-locked and hide the shared-window resize
   bug (PRD §15.23). The candidate pin + §22 clip only prove out with a client on the driver.
2. **Candidates MUST be detached** for the candidate pin to fire (P3.M2.T2.S1 gate
   `[ -z list-clients ]`). All my fixtures use `new-session -d` → detached. ✓ (A client-
   bearing candidate is the NEGATIVE case the gate SKIPS — NOT asserted here as a pass;
   P3.M2.T2.S1's own Level-2 probe covers it. This suite focuses on the common detached case
   the pin was built for, + the snapshot escape hatch.)
3. **clip mode is the default** — do NOT set `@livepicker-preview-fit reflow` (that disables
   the candidate pin + reflows). Leave fit unset (clip) OR set it explicitly to `clip`.
4. **type to highlight** a specific candidate (its unique subsequence); next-session moves by
   ONE in creation order (lands on alpha, not a named candidate).
5. **flip selects in the DRIVER only** (Invariant B) — the candidate's own `window_active` is
   unchanged by `next-window`. So the candidate's @ids + active are stable across flips; read
   candidate geometry via its home session `=immA`.
6. **Address windows by @id** (never index — base-index 1, renumber on). When a var holds `@N`,
   write `-t "$WID"`, NOT `-t "@$WID"` (→ `@@N`).
7. **`window_layout` + sorted `list-panes`** are the byte-identical proof pair (gate §6 #7).
   Capture BOTH; assert BOTH.
8. **sleep** 0.3 after activate (status grow + clip pin settle), 0.2 after each preview/flip/
   move (synchronous link settles), 0.2 after cancel (restore settle). Defer is OFF so preview
   is synchronous, but the resize pin still needs a tick.
9. **TABS** for indent; `2>/dev/null || true` on optional tmux reads; quote everything; `set -u`
   inherited (default every new var at read). `local` for all function locals.
10. **run.sh discovers `test_*`** via `compgen -A function | grep '^test_'` — so every public
    function must start with `test_`; helper functions must NOT (prefix `lp_immut_`).

## 7. Anti-patterns to avoid

- ❌ Do NOT pre-size the candidate (test_window_flip's `lp_winflip_match_size`) — that was a
  workaround BEFORE the candidate pin existed. This suite asserts the PIN holds geometry
  byte-identical WITHOUT test-side pre-sizing. Pre-sizing would hide a candidate-pin regression.
- ❌ Do NOT create candidate windows AFTER the manual/link state (gate gotcha #9 — can collide
  on an index). Create all fixture windows BEFORE activating the picker.
- ❌ Do NOT assert the client-bearing candidate pin (that is the NEGATIVE case — the gate SKIPS
  it; P3.M2.T2.S1's own Level-2 probe ARM4 covers the skip). This suite's (a)-(c) use detached
  candidates; (e) uses snapshot.
- ❌ Do NOT call `setup_test`/`teardown_test`/`exit` inside test_* (run.sh owns the lifecycle;
  an exit would kill the runner). Signal failure ONLY via fail/assert_*.
- ❌ Do NOT edit any script/PRD/CHANGELOG/tasks.json. This is a TEST-ONLY deliverable:
  `tests/test_pane_immutability.sh` (NEW) + append one line to `tests/run.sh`'s discovery
  (run.sh already globs `test_*.sh` → NO run.sh edit needed — confirm; the glob auto-discovers).
