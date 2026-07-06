# Test Harness Map — `tests/`

Target: give a planner everything needed to write `test_responsiveness.sh` and
`test_appearance.sh` that fit the existing patterns. All paths are relative to
the repo root `/home/dustin/.config/tmux/plugins/tmux-livepicker`.

## Files Retrieved

1. `tests/setup_socket.sh` (full file, ~230 lines) — socket isolation + PATH shim + orphan sweeper + attach/detach client + self-test.
2. `tests/run.sh` (full file, ~75 lines) — the runner: sources libs + test files, discovers `test_*`, per-test fresh socket, PASS/FAIL + exit code.
3. `tests/helpers.sh` (full file, ~95 lines) — the assertion helpers + `setup_test`/`teardown_test` thin delegates.
4. `tests/test_preview.sh` (full file, ~180 lines) — BEST TEMPLATE for state-seeding + direct-script invocation tests (no client attach needed). Includes the `lp_preview_seed_state` helper pattern.
5. `tests/test_pollution.sh` (full file, ~175 lines) — BEST TEMPLATE for "install a fixture/stand-in on the isolated socket" pattern (the `client-session-changed` recorder). Includes `attach_test_client` usage.
6. `tests/test_functional.sh` (full file) — best examples of (a) live-script activation via `$LIVEPICKER_SCRIPTS/livepicker.sh`, (b) `attach_test_client` + dynamic window-id capture, (c) `renderer.sh` output assertions with `assert_contains`, (d) **the only test in the suite that calls `setup_test` itself internally** (the two `test_renderer_escapes_hash_*` cases — important precedent for self-contained renderer tests).
7. `tests/test_self.sh` (full file) — minimal `test_true`/`test_false` template; defines the no-side-effect-on-source contract.
8. `scripts/options.sh` lines 27-44 — the appearance config getters (`opt_fg`/`opt_bg`/`opt_highlight_fg`/`opt_highlight_bg`/`opt_status_format_index`/`opt_type`/`opt_preview_mode`) and the `@livepicker-*` option keys a `test_appearance.sh` would seed.
9. `scripts/renderer.sh` lines 55-115 — what `renderer.sh` actually emits: `#[fg=…,bg=…]…#[default]` segments, highlighted vs non-highlighted items, `query> FILTER [i/N]` suffix. This is the SUT for appearance tests.
10. `scripts/livepicker.sh` lines 165-173 — status-line grow logic (`status on/off/2..5` normalization → `set-option -g status 2`) — relevant for responsiveness/status-height tests.

Verified the harness runs green: `bash tests/run.sh` → 16 PASS, 0 FAIL, EXIT 0.

---

## 1. `setup_socket.sh` — socket isolation

**Contract:** SOURCED (not executed). Sourcing has NO side effects — defines functions only, exports nothing, starts no server. Executing directly (`bash tests/setup_socket.sh`) runs `setup_socket_self_test` and exits 0/1.

### The PATH shim approach (the whole mocking mechanism)
`set -u` only (NOT `-e`, NOT `-o pipefail` — tmux commands legitimately return nonzero).

`setup_socket [socket_name]`:
- Picks `TEST_SOCKET` = arg, else `"livepicker-test-$$"` (the sourcing shell PID — stable + unique per run, so parallel runs don't collide).
- `TMUX_SOCK_DIR="$(mktemp -d)"`.
- **Resolves `REAL_TMUX` to an ABSOLUTE path BEFORE touching PATH** (`REAL_TMUX="${REAL_TMUX:-$(command -v tmux || echo /usr/bin/tmux)}"`). Paranoia guard: if that path is already inside `TMUX_SOCK_DIR`, force `/usr/bin/tmux`. This is the anti-recursion guarantee.
- Writes the one-line shim via an **UNQUOTED heredoc** so `$TEST_SOCKET` and `$REAL_TMUX` bake in at write time, while `"\$@"` stays literal to pass argv through quoted at runtime:
  ```bash
  cat > "$TMUX_SOCK_DIR/tmux" <<EOF
  #!/usr/bin/env bash
  exec "$REAL_TMUX" -L "$TEST_SOCKET" "\$@"
  EOF
  chmod +x "$TMUX_SOCK_DIR/tmux"
  ```
- Computes the socket file path: `TMUX_SOCKET_PATH="${TMPDIR:-/tmp}/tmux-$(id -u)/$TEST_SOCKET"`.
- Exports `TEST_SOCKET`, `TMUX_SOCK_DIR`, `TMUX_SOCKET_PATH`, `REAL_TMUX`, `LIVEPICKER_ROOT`, `LIVEPICKER_SCRIPTS`, `TEST_DRIVER_SESSION`, `TEST_FIXTURE_SESSIONS`, then **prepends the shim dir to PATH**: `PATH="$TMUX_SOCK_DIR:$PATH"`.
- Starts the isolated server via the now-shimmed bare `tmux`: `tmux new-session -d -s "$TEST_DRIVER_SESSION" -x 120 -y 40` (fixed 120×40 for capture-pane golden comparisons).
- Baseline fixtures: spawns `alpha`/`beta` (detached), adds a 2nd window `extra` to `driver`, splits it twice (h then v) for a 3-pane window; splits `beta` horizontally for a multi-pane live-preview candidate.

### How a test sources it
A test file **never** sources `setup_socket.sh` directly. `run.sh` sources it once, then calls `setup_test` (a thin delegate to `setup_socket`) once per test. Within a test body, every bare `tmux …` call transparently hits the isolated `-L` socket.

### Other exported entry points (test bodies use these)
- `teardown_socket()` — idempotent: `detach_test_client` → `tmux kill-server` → `rm -rf "$TMUX_SOCK_DIR"` → `rm -f "$TMUX_SOCKET_PATH"` (kill-server leaves the socket file behind — the `rm -f` is load-bearing).
- `lp_sweep_orphans()` — kills orphaned `lp-*`/`livepicker-test-*` servers + removes their socket files left by interrupted runs. Uses `$REAL_TMUX` (absolute) to bypass the shim. NEVER touches the real `default`-socket server. `run.sh` calls it on startup and via an EXIT trap.
- `attach_test_client [session="${TEST_DRIVER_SESSION}"]` — OPTIONAL. Spawns `script -qec "tmux attach -t '$sess'" /dev/null` in the background (gives a real pty); stores its PID in `TEST_CLIENT_PID`; `sleep 0.5` to let it settle. **Required** by any test that drives `livepicker.sh`/`input-handler.sh confirm|cancel`/`restore.sh`/`switch-client`/`display-message -p`/`refresh-client -S` (they all need an attached client).
- `detach_test_client()` — kills `$TEST_CLIENT_PID` and `wait`s. Idempotent.
- **Note for `test_responsiveness.sh`:** there is NO existing helper to resize a window/pane or change `window-size`. The driver is fixed at `-x 120 -y 40`. A responsiveness test will need to add its own `tmux resize-window`/`resize-pane`/`set-option -g window-size …` calls against the isolated socket (they go through the shim just like any bare `tmux`).
- **Note for `test_appearance.sh`:** colors/styles are NOT tmux server state — they are output of `renderer.sh` reading `@livepicker-fg/bg/highlight-*` options (see `scripts/options.sh:39-42`). The renderer is **client-independent** (reads state only), so appearance tests can mirror `test_renderer_escapes_hash_*` and skip `attach_test_client`.

### Documented constants (populated by setup_socket; tests may rely on them)
- `TEST_DRIVER_SESSION="driver"` — the attached-client home / activate origin.
- `TEST_FIXTURE_SESSIONS="alpha beta"` — ≥2 picker-list choices for filter/nav tests.

---

## 2. `run.sh` — discovery + runner contract

### Sourcing order (lines 18-32)
1. `source "$CURRENT_DIR/setup_socket.sh"` (isolation layer).
2. `source "$CURRENT_DIR/helpers.sh"` (assertion + setup_test/teardown_test).
3. `shopt -s nullglob` then `source "$CURRENT_DIR"/test_*.sh` for every test file (restore nullglob after). Test files define `test_*` functions ONLY — no side effects on source.

### Discovery (lines 35-36)
`tests="$(compgen -A function | grep '^test_' | sort)"` — discovers every `test_*` function in the CURRENT shell (NOT a subshell). Sorted for deterministic order.

### Per-test fresh-socket cycle (lines 43-63)
- `lp_sweep_orphans` on entry + `trap 'lp_sweep_orphans' EXIT`.
- For each `$t` in `$tests`:
  1. `setup_test "lp-$$-${t#test_}"` — passes a UNIQUE per-test socket name so cycles are hermetic.
  2. `TEST_STATUS="pass"` (reset — the resurrect idiom).
  3. Run `"$t"` **in the current shell** (so `fail`/`assert_*` can mutate `TEST_STATUS`).
  4. Read `TEST_STATUS`; print `PASS  $t` or `FAIL  $t`.
  5. `teardown_test` — fresh for the next test.
- Summary line `"$passed passed, $failed failed (of $total)"`.
- Exit 0 iff `$failed -eq 0`, else 1.

### Runner contract for a test body
- Define one or more functions named exactly `test_<words>` (underscore-separated; discovered by the `^test_` prefix + sorted lexically).
- **Signal failure ONLY via `fail()` / `assert_*()`** (they set `TEST_STATUS=fail`). NEVER `exit`, NEVER `return` nonzero to abort the runner (a bare `exit` would kill `run.sh`). Early `return 0` to skip the rest of a test body is acceptable (used in `test_window_preview_shows_highlighted_window`).
- `set -u` is INHERITED — do NOT re-declare it.
- A test file SOURCES NOTHING and calls NO `setup_test`/`teardown_test` at file scope (run.sh owns the cycle). **Exception precedent:** a test may call `setup_test` *internally* to get a different/narrower fixture for one specific test function — see `test_renderer_escapes_hash_in_names`/`test_renderer_escapes_hash_in_filter` in `test_functional.sh`, which call `setup_test "lp-bug3-…"`. This is the right pattern if a renderer/appearance test needs a custom session name like `#dev` rather than the baseline `driver/alpha/beta`.
- Output format: `run.sh` prints `PASS/FAIL  <name>` per test; tests print free-form diagnostics (assert helpers prefix `  ASSERT FAIL:` / `  ok:`).

---

## 3. `helpers.sh` — EVERY assertion helper (exact signatures)

`set -u` only. The single global: `TEST_STATUS=""` (run.sh resets to `"pass"` before each test).

| Function | Exact signature | What it asserts / does |
|---|---|---|
| `fail()` | `fail msg` | Records a failure: echoes `  ASSERT FAIL: $msg` to **stderr** + sets `TEST_STATUS="fail"`. **Never exits** (run.sh aggregates). THE canonical failure signal. |
| `pass()` | `pass msg` | Optional explicit pass narration: echoes `  ok: $msg` to stdout. Does NOT touch `TEST_STATUS` (only `fail` does). |
| `assert_eq()` | `assert_eq a b msg` | POSIX `[ "$a" = "$b" ]`. Quiet on success; on mismatch calls `fail "$msg (got [$a] want [$b])"`. Handles multi-line strings (used with embedded `\n` in `test_pollution.sh`). |
| `assert_contains()` | `assert_contains str sub msg` | Literal substring via `case "$str" in *"$sub"*) …`. `$sub` is QUOTED in the pattern so glob specials `?`/`*`/`[` are disabled → literal match, no subprocess, robust vs special chars. On absence: `fail "$msg (substring [$sub] absent in [$str])"`. |
| `setup_test()` | `setup_test [socket_name]` | Thin delegate to `setup_socket "${1:-}"`. Brings up a FRESH isolated server + PATH shim + baseline fixtures for ONE test. Does NOT attach a client. run.sh passes `"lp-$$-<testname>"`. |
| `teardown_test()` | `teardown_test` | Thin delegate to `teardown_socket` (idempotent). |

**That is the COMPLETE public assertion API.** There is no `assert_not_contains`, no `assert_match`/regex, no `assert_rc`. Tests that need a "must-not-contain" check write an inline `case` + `fail` (see `test_typing_filters`'s `case "$out" in *alpha*) fail …; esac`, and `test_navigate_unlinks_intact`). Tests that need a return-code check write `cmd || fail "…"`. Tests that need a TRUE/FALSE predicate define a local helper returning rc (see `lp_runtime_cleared` in `test_functional.sh`: `lp_runtime_cleared || fail "…"`).

**Naming convention for non-assert (fixture/seed) helpers:** prefix with `lp_` (e.g. `lp_preview_seed_state`, `lp_install_history_recorder`, `lp_poll_make_fixtures`, `lp_poll_resolve_target`, `lp_runtime_cleared`). The `test_` prefix is reserved for discovered tests, so seed helpers MUST use a different prefix or `compgen` will try to run them.

---

## 4. Best template + how a test installs fixtures

### Recommendation
- **For `test_appearance.sh`** (colors/styles of renderer output): copy **`test_functional.sh`**'s `test_renderer_escapes_hash_in_names` / `test_renderer_escapes_hash_in_filter` — they are the existing precedent for "seed `@livepicker-*` options + run `$LIVEPICKER_SCRIPTS/renderer.sh` + `assert_contains` on stdout". No `attach_test_client` needed (renderer is client-independent). `test_preview.sh`'s `lp_preview_seed_state` is also a clean seed-state helper template.
- **For `test_responsiveness.sh`** (window/pane sizing, status-line height, resize behavior): copy **`test_functional.sh`**'s `test_activate_grows_status` and `test_escape_restores` for the activate→assert-status→cancel lifecycle (needs `attach_test_client`), and **`test_pollution.sh`**'s top-of-test fixture-install block if you need to install a custom hook/recorder on the socket.
- **Best general-purpose structural template: `test_preview.sh`** — clean header contract block, a single `lp_preview_seed_state` helper, then one `test_*` function per behavior, each with dynamic-id capture and a mix of `assert_eq`/`assert_contains`/inline `case`.

### Full structural template (annotated from `test_preview.sh`)
```bash
#!/usr/bin/env bash
# tests/test_<area>.sh — <PRD reference> validation (<work-item id>).
#
# SOURCED by run.sh (NEVER executed directly). Defines test_* functions that ...
# CONTRACT: run.sh sources setup_socket.sh + helpers.sh + every tests/test_*.sh,
#   then PER test calls setup_test "lp-$$-<name>" -> resets TEST_STATUS=pass ->
#   runs the test_* in the CURRENT shell -> reads TEST_STATUS -> teardown_test.
#   So when a test_* runs: bare `tmux` hits the isolated socket; $LIVEPICKER_SCRIPTS,
#   $TEST_DRIVER_SESSION, fail/pass/assert_eq/assert_contains are all IN SCOPE;
#   this file SOURCES NOTHING and calls NO setup_test/teardown_test.
#
# `set -u` is INHERITED from helpers.sh (do NOT re-declare; mirror test_self.sh).
# shellcheck disable=SC2154,SC2016,SC2034,SC2086
#   SC2154: assert_*/fail/$LIVEPICKER_SCRIPTS/$TEST_DRIVER_SESSION are defined by
#           run.sh's sources, not in this file.

# lp_<area>_seed_state — set the MINIMAL @livepicker-* state the SUT reads.
# (Literal key strings are stable state.sh contract constants — NO sourcing.)
lp_<area>_seed_state() {
	local drv_win
	drv_win="$(tmux list-windows -t "=$TEST_DRIVER_SESSION" -F '#{window_id}' -f '#{window_active}')"
	tmux set-option -g @livepicker-orig-session "$TEST_DRIVER_SESSION"
	tmux set-option -g @livepicker-orig-window "$drv_win"
	tmux set-option -g @livepicker-linked-id ""
}

# test_<behavior> — <PRD bullet / issue>: <one-sentence what>.
test_<behavior>() {
	lp_<area>_seed_state          # or attach_test_client FIRST if SUT needs a client
	# ... seed extra fixtures BEFORE activate (the list is captured at activate time) ...
	# ... invoke the SUT: "$LIVEPICKER_SCRIPTS/<script>.sh" [args] ...
	# ... assert observable tmux state ...
	assert_eq    "$(tmux show-option -gqv <opt>)" "<want>" "<msg>"
	assert_contains "$out" "<sub>" "<msg>"
	# negative check: inline case + fail
	case "$out" in *<bad>*) fail "<bad> leaked" ;; esac
}
```

### Cleanup model
Tests do **NOT** write their own teardown. `run.sh` calls `teardown_test` (→ `teardown_socket`) after every test function. Anything a test writes into `$TMUX_SOCK_DIR` (a recorder file, a fixture script) is `rm -rf`'d automatically; any `tmux set-hook`/`set-option -g @livepicker-*`/created session is wiped by `kill-server`. Tests only need to seed state + invoke + assert.

### How `test_pollution.sh` installs a stand-in recorder on the isolated socket
This is the canonical "install a fixture that survives across tmux calls" pattern. The recorder is a real shell script written into `$TMUX_SOCK_DIR` (auto-cleaned by teardown) via an **UNQUOTED heredoc** that bakes the ABSOLUTE shim path at write time, then wired in with a **synchronous** `set-hook` (NO `-b`, so the test's next read sees the update):

```bash
lp_install_history_recorder() {
	local rec="$TMUX_SOCK_DIR/session_history_rec.sh"
	# UNQUOTED heredoc: $TMUX_SOCK_DIR expands at WRITE time (bakes absolute shim path);
	# \$1 / \$T etc. stay literal (runtime). NO set -u in the recorder (hook safety).
	cat > "$rec" <<EOF
#!/usr/bin/env bash
T="$TMUX_SOCK_DIR/tmux"
to="\$1"
cur="\$(\$T show-option -gqv @test-current 2>/dev/null)"
# ... do_hook logic mirroring scripts/session_history.sh ...
EOF
	chmod +x "$rec"
	# Synchronous hook (NO -b). #{session_name} is tmux format, not shell.
	tmux set-hook -g client-session-changed "run-shell '$rec #{session_name}'"
	# Seed the timeline ...
	tmux set-option -g @test-hist     "$TEST_DRIVER_SESSION"
	tmux set-option -g @test-current  "$TEST_DRIVER_SESSION"
	# ...
	tmux switch-client -t "=$TEST_DRIVER_SESSION"   # force the display-message pointer
}
```
Key points a planner reusing this pattern must preserve:
1. Write the recorder into **`$TMUX_SOCK_DIR`** (teardown cleans it; do NOT write to `/tmp`).
2. Bake `$TMUX_SOCK_DIR/tmux` (the ABSOLUTE shim path) into the recorder via an **unquoted** heredoc so any `run-shell` inside it hits the isolated socket, never `/usr/bin/tmux`.
3. Wire via `tmux set-hook -g <hook> "run-shell '<rec> #{format}'>"` — synchronous (no `-b`).
4. Do NOT put `set -u` in the recorder (a crash mid-hook leaves `@test-*` inconsistent).
5. A test using the recorder calls `attach_test_client` (the recorder hook needs a client to fire) and seeds fixtures **before** attach (display-message pointer reset).

### The `setup_test`-internal precedent (for self-contained renderer/appearance tests)
`test_functional.sh`'s `test_renderer_escapes_hash_in_names` calls `setup_test "lp-bug3-names"` as its FIRST line — overriding run.sh's per-test socket with a fresh one named for the bug, so it can create a `#dev` session without polluting the baseline. This is exactly the pattern a `test_appearance.sh` color/style test should use if it needs unusual session names or a clean baseline that differs from `driver/alpha/beta`. Note: after an internal `setup_test`, the test is still responsible only for assertions — `run.sh`'s outer `teardown_test` still cleans up.

---

## Appearance-specific entry points (for `test_appearance.sh`)
From `scripts/options.sh:39-44` and `scripts/renderer.sh:55-115`:
- `opt_fg()` ← `@livepicker-fg` (default `"default"`)
- `opt_bg()` ← `@livepicker-bg` (default `"default"`)
- `opt_highlight_fg()` ← `@livepicker-highlight-fg` (default `"black"`)
- `opt_highlight_bg()` ← `@livepicker-highlight-bg` (default `"yellow"`)
- `opt_status_format_index()` ← `@livepicker-status-format-index` (default `"0"`)
- `opt_type()` ← `@livepicker-type` (default `"session"`; enum `session|window`)
- `opt_preview_mode()` ← `@livepicker-preview-mode` (default `"live"`; enum `live|snapshot|off`)

`renderer.sh` emits one line, no trailing newline (`printf '%s' "$out"`). Styling grammar:
- Every item segment: `#[fg=$FG,bg=$BG]<name>#[default]` (non-highlight) or `#[fg=$HFG,bg=$HBG]<name>#[default]` (highlighted = at `@livepicker-index`).
- Query suffix (match branch): ` #[fg=$FG,bg=$BG]query> $FILTER [i/N]#[default]`.
- No-match branch: `#[fg=$FG,bg=$BG]query> $FILTER (no match) 0/$TOTAL#[default]` (or without count if `$TOTAL` empty).
- A `#` in a name/filter is emitted DOUBLED (`##`) — already covered by `test_renderer_escapes_hash_*`; do not re-test that.
- Renderer crash fallback: `render || printf '%s' '#[fg=red]livepicker: renderer error#[default]'`.

So an appearance test seeds e.g. `tmux set-option -g @livepicker-fg red` etc., seeds `@livepicker-list`/`@livepicker-filter`/`@livepicker-index`, runs `out="$("$LIVEPICKER_SCRIPTS/renderer.sh")"`, and `assert_contains "$out" "#[fg=red,bg=…]" "…"`.

## Responsiveness-specific entry points (for `test_responsiveness.sh`)
- `livepicker.sh:165-173` grows the status line: normalizes the prior `status` value (`on`→`set-option -g status 2`, numeric `N`→`N+1` clamped 2..5, `off`/`*`→`2`). Restore (`restore.sh` step 4) restores the saved count + `status-format`.
- The driver session is created at `-x 120 -y 40`. There is no helper to resize — use bare `tmux resize-window -t … -x … -y …` / `resize-pane` / `set-option -g window-size manual|largest|smallest` against the shim (works like any bare `tmux`).
- The renderer does NOT truncate/wrap based on width — it always emits the full line; tmux truncates at display time. So "responsiveness" testing here is about (a) status-line height after activate at various prior `status` values, and/or (b) the picker surviving a window/terminal resize (state intact after `resize-window`/`refresh-client -S`).

## Start Here
Open `tests/test_preview.sh` first — it is the cleanest full example of the header contract block + a seed-state helper + one `test_*` per behavior + a mix of assertion styles + dynamic window-id capture, with NO `attach_test_client` complexity. Then read `tests/test_functional.sh`'s two `test_renderer_escapes_hash_*` functions for the exact "seed options → run renderer.sh → assert_contains on stdout" idiom that `test_appearance.sh` will mirror, and its `test_activate_grows_status` for the `attach_test_client` + status-height lifecycle that `test_responsiveness.sh` will mirror.
