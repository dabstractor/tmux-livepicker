# Research Findings — P1.M7.T2.S1: `tests/helpers.sh` + `tests/run.sh`

> Empirical + idiomatic ground-truth, gathered 2026-07-06 against the
> **already-implemented** `tests/setup_socket.sh` (P1.M7.T1.S1 — read in full;
> its interface below is the CONTRACT this task builds on) and the resurrect /
> in-house assertion idioms. This file is the authoritative reference for the PRP.

## 0. What this subtask is (one paragraph)

P1.M7.T1.S1 delivered the **socket-isolation shim** (`tests/setup_socket.sh`:
`setup_socket`/`teardown_socket` + the PATH `tmux` wrapper + baseline fixtures +
optional `attach_test_client`). This subtask (T2.S1) builds the **assertion +
discovery + runner layer** ON TOP of it: `tests/helpers.sh` provides the
resurrect-style assertion helpers (`assert_eq`/`assert_contains`/`fail`/`pass`)
+ the per-test `setup_test`/`teardown_test` pair (which delegate to
`setup_socket`/`teardown_socket`); `tests/run.sh` sources the harness + every
`tests/test_*.sh`, discovers every `test_*` function via
`compgen -A function | grep '^test_'`, runs each in a FRESH isolated socket
(per-test `setup_test`→test→`teardown_test`), prints PASS/FAIL per test, and
exits non-zero if any failed. A built-in self-test (`tests/test_self.sh` with
`test_true`/`test_false`) proves the runner reports a pass and a fail and the
exit code reflects it (work-item §5 MOCKING).

---

## FINDING 1 — the canonical resurrect idiom (verbatim from the sibling source)

Read the REAL file `tmux-resurrect/lib/tmux-test/tests/helpers/helpers.sh`
(symlinked into `tmux-resurrect/tests/helpers/helpers.sh`). It is the origin of
the `fail_helper`/`teardown_helper`/`exit_helper`/`run_tests` shape the work-item
§1 RESEARCH NOTE and system_context §7 / sibling_plugins §9 cite. Verbatim:

```bash
TEST_STATUS="success"
fail_helper()  { local message="$1"; echo "$message" >&2; TEST_STATUS="fail"; }
teardown_helper() { rm -f ~/.tmux.conf; rm -rf ~/.tmux/; tmux kill-server >/dev/null 2>&1; }
exit_helper()  { teardown_helper; if [ "$TEST_STATUS" == "fail" ]; then echo "FAIL!"; exit 1;
                 else echo "SUCCESS"; exit 0; fi; }
run_tests() {
	for test in $(compgen -A function | grep "^test_"); do   # DISCOVERY idiom
		"$test"
	done
	exit_helper
}
```

**BORROW (this task):** the `TEST_STATUS` global + `fail` sets it + the
`compgen -A function | grep '^test_'` discovery + "test functions never `exit`,
they call `fail`" contract. **DO NOT BORROW:** `teardown_helper` (it does a REAL
`tmux kill-server` + `rm -rf ~/.tmux/` — the OPPOSITE of socket-isolated; it
would nuke the user's live 15-session server). Our `teardown_test` delegates to
`teardown_socket`, which kills ONLY the isolated `-L` socket.

**EXTENSION beyond resurrect:** resurrect runs ALL tests in ONE shared
environment with a single trailing `exit_helper`. The work-item contract wants
MORE: **per-test PASS/FAIL reporting** + **per-test fresh fixtures** ("each gets
its own fresh fixture via per-test setup/teardown"). So T2.S1 resets
`TEST_STATUS=pass` before each test, runs the test, reports PASS/FAIL, and wraps
each test in `setup_test`/`teardown_test` for isolation (see FINDING 5).

---

## FINDING 2 — the ACTUAL `tests/setup_socket.sh` interface (read in full — the contract)

`tests/setup_socket.sh` EXISTS (11677 bytes; created by the parallel T1.S1 task)
and matches its PRP contract exactly. It is a **sourced library** (sourcing has
NO side effects — defines functions only; the self-test runs only under direct
execution via `if [ "${BASH_SOURCE[0]}" = "${0}" ]; then setup_socket_self_test; fi`).
House style: `#!/usr/bin/env bash`, `set -u` ONLY (no `-e`, no `pipefail`), tabs,
`local`, `CURRENT_DIR` idiom, file-level `# shellcheck disable=SC2154,SC2016,SC2034,SC2086`.

It PROVIDES (T2.S1 consumes these — do NOT re-implement):

| Symbol | Kind | What it does |
|---|---|---|
| `setup_socket [socket_name]` | function | mktemp dir → write `tmux` shim (`exec "$REAL_TMUX" -L "$TEST_SOCKET" "$@"`) → `chmod +x` → prepend shim dir to `PATH` → `export` the env contract → `tmux new-session -d -s driver -x 120 -y 40` → spawn baseline fixtures (`alpha`, `beta`, + `driver:extra` 3-pane window + `beta` multi-pane window). Honors an optional socket name; else `TEST_SOCKET="livepicker-test-$$"`. |
| `teardown_socket` | function | **idempotent** 3-step cleanup: `detach_test_client` → `tmux kill-server` (via shim → isolated socket) → `rm -rf "$TMUX_SOCK_DIR"` → `rm -f "$TMUX_SOCKET_PATH"`. Safe when setup didn't run / already tore down (every step guarded `2>/dev/null \|\| true`). |
| `attach_test_client [session]` / `detach_test_client` | OPTIONAL fns | socket-bound; spawn/kill a `script -qec "tmux attach …"` pty client (needed by switch-client / display-message -p / refresh-client -S). NOT exercised by setup_socket's own self-test. |
| `setup_socket_self_test` | function | runs only on direct execution; exits 0/1. (T2.S1 does NOT call it.) |
| `TEST_SOCKET`, `TMUX_SOCK_DIR`, `TMUX_SOCKET_PATH`, `REAL_TMUX` | exports | the isolated-socket environment (set inside `setup_socket`). |
| `LIVEPICKER_ROOT`, `LIVEPICKER_SCRIPTS` | exports | repo root + `…/scripts` (so tests drive the real plugin scripts). |
| `TEST_DRIVER_SESSION` (`"driver"`), `TEST_FIXTURE_SESSIONS` (`"alpha beta"`) | exports | baseline fixture names (documented; tests may add their own via bare `tmux new-session`). |
| `PATH` | export | `"$TMUX_SOCK_DIR:$PATH"` (shim wins; `/usr/bin/tmux` still reachable by absolute path for the non-pollution probe). |

**Implication for T2.S1:** `setup_test [name]` = `setup_socket "$1"` (the baseline
fixture seed is ALREADY inside `setup_socket` — "setup_test calls setup_socket +
seeds fixtures" is satisfied: setup_socket IS the seeder). `teardown_test` =
`teardown_socket`. T2.S1 does NOT touch sockets, PATH, or the shim directly — it
delegates. This keeps the two files cleanly layered (setup_socket owns isolation;
helpers/run own assertions + discovery).

---

## FINDING 3 — the in-house `assert` idiom (from the P1.M6 throwaway mocks + setup_socket self-test)

The throwaway `confirm_mock.sh` / `cancel_mock.sh` and the setup_socket
`setup_socket_self_test` all use the SAME counted-assert shape (the resurrect
style, productionized):

```bash
fail=0; n=0
ok()  { echo "  ok   [$n] $1"; }
bad() { echo "  FAIL [$n] $1"; fail=1; }
assert() { n=$((n+1)); if eval "${1:?}"; then ok "$2"; else bad "$2 [$1]"; fi; }
```

T2.S1's `helpers.sh` PROMOTES this to NAMED, ergonomic helpers (the work-item §3
explicit list) that set the global `TEST_STATUS` (resurrect idiom) instead of a
local `fail` flag (so `run.sh` can read the result in the current shell):

```bash
# fail msg          — resurrect fail_helper: record failure, do NOT exit (accumulate).
# pass msg          — optional explicit pass narration (verbose).
# assert_eq a b msg — equality; on mismatch -> fail "$msg" (sets TEST_STATUS=fail).
# assert_contains str sub msg — literal substring; on absence -> fail "$msg".
```

`assert_eq` uses `[ "$a" = "$b" ]` (POSIX, no subprocess). `assert_contains` uses
a `case` (literal match — quoting `$sub` in the pattern disables glob specials, no
subprocess, robust against special chars): `case "$str" in *"$sub"*) pass-path ;;
*) fail "$msg" ;; esac`. Both are quiet on success (the per-test PASS line from
`run.sh` is the summary) and loud (`fail` → stderr) on failure — matching the
setup_socket self-test's `ok`(quiet)/`bad`(loud) split, but reporting via the
shared `TEST_STATUS` global instead of a per-file local.

---

## FINDING 4 — the runner loop (run_tests_in_isolation + resurrect run_tests, merged)

Two sibling sources define the loop, and T2.S1 MERGES them:

- `resurrect/helpers.sh:run_tests` — discovers `test_*` via
  `compgen -A function | grep '^test_'` and calls each in the CURRENT shell
  (so `TEST_STATUS` is visible). One trailing `exit_helper`.
- `resurrect/lib/tmux-test/tests/run_tests_in_isolation` — per-test-FILE exit-value
  aggregation: `EXIT_VALUE=0`; for each file, run it, capture `$?`, if nonzero
  `EXIT_VALUE=1`; `exit "$EXIT_VALUE"`.

T2.S1's `run.sh` combines: discover `test_*` functions (not files) in the current
shell; wrap EACH in `setup_test` → reset `TEST_STATUS=pass` → run → read
`TEST_STATUS` → report PASS/FAIL → `teardown_test`; aggregate a `failed` counter;
`exit 0` iff `failed=0`. See FINDING 5 for the per-test wrap.

---

## FINDING 5 — DESIGN DECISION: per-test FRESH socket (interpretation of "runs setup_test once")

The work-item §3 says: *"run.sh … runs setup_test once, iterates test_* functions
(each gets its own fresh fixture via per-test setup/teardown) …"*. This is
internally tense: "runs setup_test once" (singular) vs "each gets its own fresh
fixture via per-test setup/teardown" (per-test). Two readings:

- **(A) shared socket:** `setup_test` once at suite start; per-test there are
  EXTRA reset/cleanup functions giving fresh fixtures. Problem: the contract's
  explicit helper list names ONLY `setup_test`/`teardown_test` (no
  `setup_each`/`reset_state`), so reading (A) forces INVENTING per-test functions
  the contract doesn't name; AND a soft-reset that perfectly undoes an activated
  picker (key-table=livepicker, status=2, linked preview, dirty @livepicker-*)
  basically re-implements `restore.sh` — fragile, high risk of cross-test
  interference (flaky tests).
- **(B) per-test fresh socket:** `setup_test`/`teardown_test` ARE the per-test
  pair; run.sh wraps each test in `setup_test "$testname"` → test → `teardown_test`,
  giving EVERY test a brand-new isolated tmux server. Bulletproof isolation (a
  killed+respawned server cannot leak state). Uses ONLY the named contract
  functions. "Runs setup_test once" is satisfied as **once per test function**.

**DECISION: (B).** Rationale: (1) it is the only reading that uses solely the
contract's named helpers; (2) the parenthetical "each gets its own fresh fixture
via per-test setup/teardown" literally describes per-test setup/teardown; (3) it
is the robust choice — the tests in T3–T6 MUTATE shared tmux state (activate the
picker → `key-table=livepicker`, `status=2`, `@livepicker-*` options, a linked
preview window; pollution tests even install tmux-session-history and browse 5
sessions). A soft-reset between them is brittle; a fresh server per test is
hermetic. PRD §15's whole premise is isolation — (B) extends that isolation to
between tests, not just test-vs-real-server.

**Per-test unique socket name:** `setup_socket` defaults to
`TEST_SOCKET="livepicker-test-$$"` (`$$` = run.sh PID, stable across calls).
Calling it repeatedly in one process REUSES the name — but `teardown_socket`
kills that server + `rm -f`s the socket file first, so a same-named re-setup
works. To avoid ANY collision and keep PATH clean, `run.sh` passes a per-test
name: `setup_test "lp-$$-${t#test_}"` (unique per test). PATH accumulates one
dangling shim-dir entry per test (the dir is `rm -rf`'d by teardown, so PATH
lookup falls through to the next live shim → harmless; confirmed by FINDING 6
probe). `setup_socket`'s documented optional `[socket_name]` arg supports this.

**Cost:** each `setup_test` ≈ mktemp + shim write + `tmux new-session` + a few
fixture spawns ≈ 80–150 ms; ×~30 future test functions ≈ a few seconds. A client
attach (only for tests that need one) adds ~0.5 s each. `setup_test` does NOT
attach a client by default (the contract lists only "setup_socket + seeds
fixtures" — no client); tests needing one call `attach_test_client` themselves.

---

## FINDING 6 — PROBE: per-test setup/teardown cycle is clean (run live)

Verified the exact cycle T2.S1's `run.sh` will repeat, against the real
`tests/setup_socket.sh`:

```
source tests/setup_socket.sh
for t in test_a test_b; do
  setup_socket "lp-probe-$$-$t"
  tmux list-sessions -F '#{session_name}'   # -> driver + alpha + beta each time
  teardown_socket
  tmux has-session -t '=driver' 2>/dev/null; echo "rc=$?"   # rc=1 (dead) each time
done
ls "${TMPDIR:-/tmp}/tmux-$(id -u)"/lp-probe-* 2>/dev/null   # NONE (rm -f removed them)
/usr/bin/tmux list-sessions -F '#{session_name}' | grep -c driver   # 0 (real server untouched)
```
Result: each iteration sees exactly `driver alpha beta`; after teardown the server
is dead (`has-session` rc=1) and the socket file is gone; the real server never
acquires `driver`. The dangling PATH entries are harmless (`type tmux` still
resolves to the CURRENT shim after the next `setup_socket`; `/usr/bin/tmux` is
always reachable by absolute path). Confirms FINDING 5's (B) is sound.

---

## FINDING 7 — `compgen` discovery + safe test-file glob (gotchas)

- **Discovery:** `compgen -A function` lists ALL defined functions (including
  sourced setup_socket/helpers ones). `grep '^test_'` selects only test bodies.
  `sort` for deterministic order. Run in the CURRENT shell (not a subshell) so
  `TEST_STATUS` set by `fail` inside the test is visible to `run.sh`. A test that
  calls bare `exit` would kill the runner — so the CONTRACT for T3–T6 authors is:
  **signal failure ONLY via `fail`/`assert_*` (which set `TEST_STATUS`); never
  `exit`/`return` nonzero to abort.** (Mirrors resurrect's `fail_helper` contract.)
- **Safe glob of `test_*.sh`:** with `shopt -s nullglob` a non-matching glob
  expands to NOTHING (not the literal `test_*.sh`), so `for f in "$DIR"/test_*.sh`
  is safe when no test files exist yet (T2.S1 ships only `test_self.sh`; T3–T6 are
  "Planned"). Restore with `shopt -u nullglob` (or scope in a subshell) to avoid
  surprising later globs. Alternative `[ -e "$f" ]` guard per file; `nullglob` is
  cleaner.
- **`set -u` safety:** `run.sh` resets `TEST_STATUS=pass` before every test (so it
  is always bound). `helpers.sh` initializes `TEST_STATUS=""` at definition. Test
  args are read via `"${1:-}"` defaults inside assert helpers. No bare `$X`
  without a default anywhere.

---

## FINDING 8 — the §5 self-test (MOCKING): prove pass AND fail + exit code

Work-item §5: *"Self-test: a trivial test_true passes and a test_false fails,
runner exit code reflects it."* Shipped as `tests/test_self.sh` (a normal
`test_*.sh`, so `run.sh` discovers it like any other):

```bash
test_true()  { assert_eq "1" "1" "sanity equality"; assert_contains "hello world" "world" "substring"; }
test_false() {
	# Intentional failure — proves run.sh reports FAIL + exits nonzero.
	# Gated so the DEFAULT suite stays green; enable to exercise the failure path.
	if [ "${LIVEPICKER_NEGATIVE_SELF_TEST:-0}" = "1" ]; then
		assert_eq "1" "2" "intentional self-test failure (expected)"
	else
		assert_eq "1" "1" "negative path disabled (LIVEPICKER_NEGATIVE_SELF_TEST=1)"
	fi
}
```
Validation gate (in the PRP) runs BOTH:
- `bash tests/run.sh` → `test_true` PASS, `test_false` PASS (no-op) → **exit 0**.
- `LIVEPICKER_NEGATIVE_SELF_TEST=1 bash tests/run.sh` → `test_true` PASS,
  `test_false` **FAIL** → **exit 1**.

This proves the runner propagates both outcomes and the exit code reflects the
aggregate. The gate keeps `test_self.sh` permanently shippable (a green default
run + an on-demand negative proof) without leaving an always-red test behind.

---

## FINDING 9 — house style + FORBIDDEN edits (consistency with P1.M7.T1.S1)

- `helpers.sh` and `run.sh`: `#!/usr/bin/env bash`; `set -u` ONLY (NO `-e` —
  `fail`/assertions/tmux commands legitimately "fail" without aborting; NO
  `pipefail`); `local` for all function locals; TABS; quote everything;
  `CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"`.
- `helpers.sh` is a SOURCED LIBRARY → NO side effects on source (mirrors
  `utils.sh` + `setup_socket.sh` CONTRACT lines): it defines functions + initializes
  the `TEST_STATUS` global only; it starts NO server, sources nothing, prints
  nothing. `run.sh` is the EXECUTABLE entry point (it does the sourcing + running).
- File-level `# shellcheck disable=` for the dynamic-source + eval/SC2154/SC2016/
  SC2086 false positives (mirror `setup_socket.sh`'s header).
- **FORBIDDEN:** edit `setup_socket.sh` (T1.S1 owns it — it is COMPLETE), any
  `scripts/*` (P1.M1–M6 COMPLETE/IMMUTABLE), `PRD.md`, `tasks.json`,
  `prd_snapshot.md`, `.gitignore`. T2.S1 ADDS exactly: `tests/helpers.sh`,
  `tests/run.sh`, `tests/test_self.sh` (the self-test). `git diff --stat` shows
  only those three (under `tests/`).

---

## TL;DR for the PRP

- **`helpers.sh`** (sourced lib, no side effects): `fail`/`pass`/`assert_eq`/
  `assert_contains` (set the global `TEST_STATUS`, resurrect-style, never exit);
  `setup_test [name]`→`setup_socket` (baseline fixtures already inside);
  `teardown_test`→`teardown_socket`. Initialize `TEST_STATUS=""`.
- **`run.sh`** (executable): source `setup_socket.sh`+`helpers.sh`+every
  `tests/test_*.sh` (`nullglob`); discover `test_*` via `compgen -A function |
  grep '^test_'`; **per test**: `setup_test "lp-$$-${t#test_}"` (fresh isolated
  socket) → `TEST_STATUS=pass` → run `$t` (current shell) → read `TEST_STATUS` →
  print PASS/FAIL → `teardown_test`; print `N passed, M failed`; `exit 0` iff
  `M=0` else `1`.
- **`test_self.sh`**: `test_true` (passes) + `test_false` (fails under
  `LIVEPICKER_NEGATIVE_SELF_TEST=1`). Gate runs both modes.
- **Style:** `set -u` only; tabs; `local`; `CURRENT_DIR`; shellcheck disable header.
- **Decision:** per-test FRESH socket (FINDING 5 reading B) — bulletproof, uses
  only the named contract helpers, matches "each gets its own fresh fixture."
