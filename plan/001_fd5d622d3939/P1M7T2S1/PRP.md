# PRP — P1.M7.T2.S1: `tests/helpers.sh` + `tests/run.sh`

---

## Goal

**Feature Goal**: **BUILD** the assertion + discovery + runner layer of the
P1.M7 test harness, ON TOP of the socket-isolation shim delivered by P1.M7.T1.S1
(`tests/setup_socket.sh`, which is **COMPLETE and was read in full** — its
interface is the contract below). This task adds two files: `tests/helpers.sh`
(the resurrect-style assertion helpers + the per-test `setup_test`/`teardown_test`
pair that delegate to `setup_socket`/`teardown_socket`) and `tests/run.sh` (the
executable suite runner that sources the harness + every `tests/test_*.sh`,
discovers every `test_*` function via `compgen -A function | grep '^test_'`,
wraps each in a **fresh isolated socket** — `setup_test`→test→`teardown_test` —
prints PASS/FAIL per test, and exits non-zero if any failed). It also ships a
built-in self-test (`tests/test_self.sh` with `test_true`/`test_false`) that
proves the runner reports a pass and a fail and the exit code reflects it
(work-item §5 MOCKING). After this task: `bash tests/run.sh` runs the whole
suite against an isolated socket and exits 0/1 (work-item §4 OUTPUT).

**Deliverable** (THREE new files, all under `tests/`):
1. `tests/helpers.sh` — a **sourced bash library** (sourcing has NO side effects —
   defines functions + initializes the `TEST_STATUS` global only; starts NO
   server, sources nothing, prints nothing — mirrors `utils.sh`/`setup_socket.sh`).
   Provides the work-item §3 explicit helper set: `fail msg`, `pass msg`,
   `assert_eq a b msg`, `assert_contains str sub msg`, `setup_test [socket_name]`
   (→ `setup_socket` + the baseline fixtures it already seeds), `teardown_test`
   (→ `teardown_socket`). Plus the resurrect `TEST_STATUS` global.
2. `tests/run.sh` — the **executable** entry point. Sources `setup_socket.sh` +
   `helpers.sh` + every `tests/test_*.sh` (safe `nullglob` glob); discovers
   `test_*`; wraps each in a per-test fresh-socket cycle; prints PASS/FAIL +
   a summary; exits 0/1.
3. `tests/test_self.sh` — the §5 self-test: `test_true` (passes) + `test_false`
   (fails only under `LIVEPICKER_NEGATIVE_SELF_TEST=1`, so the default run stays
   green). A normal `test_*.sh` (no side effects on source; just defines functions).

**Success Definition**:
- `bash -n` + `shellcheck` pass on all three files (0 findings beyond a
  file-level `disable=SC1091,SC2154,SC2016,SC2034,SC2086` mirroring
  `setup_socket.sh`; tabs only; `set -u` only — NO `-e`, NO `pipefail`).
- `bash tests/run.sh` prints `PASS  test_true` + `PASS  test_false` (negative
  path gated off), a `N passed, 0 failed` summary, and exits **0**.
- `LIVEPICKER_NEGATIVE_SELF_TEST=1 bash tests/run.sh` prints `PASS  test_true` +
  `FAIL  test_false` + `1 passed, 1 failed` and exits **1** (proves the runner
  propagates both outcomes — work-item §5).
- The real user server is provably untouched across a full `run.sh` invocation:
  `/usr/bin/tmux list-sessions` is byte-identical before/after (delegates to
  `setup_socket`/`teardown_socket`, which never touch the real server — proven by
  P1.M7.T1.S1's self-test).
- `git diff --stat` shows ONLY `tests/helpers.sh`, `tests/run.sh`,
  `tests/test_self.sh` added (NO `setup_socket.sh` edits — it is COMPLETE/owned by
  T1.S1; NO `scripts/` edits; NO PRD/tasks/prd_snapshot edits — FORBIDDEN).

## User Persona (if applicable)

**Target User**: the P1.M7.T3–T6 test implementers (who write
`test_functional.sh`/`test_preview.sh`/`test_pollution.sh`/`test_restore.sh`/
`test_keyrepurpose.sh`/`test_create.sh`) and the contributor running the suite.
The harness has no end-user surface (DOCS: Mode A — none; it is test infra).

**Use Case**: a T5.S1 pollution test does, inside its `test_*` function:
`tmux show-option -gqv @session-history-hist` (snapshot) → drive the real
`scripts/livepicker.sh` (activate) + `scripts/input-handler.sh` (cancel) via bare
`tmux`/sourced calls → `assert_eq "$before" "$after" "history unchanged"` →
return. `run.sh` has ALREADY brought up a fresh isolated socket via `setup_test`
and WILL tear it down via `teardown_test`; the test body just uses bare `tmux`,
the baseline fixtures, and the `assert_*` helpers. It never thinks about sockets,
PATH, or per-test isolation.

**User Journey** (T2.S1 scope — the runner + helpers):
1. The contributor runs `bash tests/run.sh` from the repo root.
2. `run.sh` sources `setup_socket.sh` (defines the isolation fns), `helpers.sh`
   (defines the assert fns + `setup_test`/`teardown_test`), and every
   `tests/test_*.sh` (defines `test_*` functions — currently `test_self.sh`; later
   T3–T6 add more).
3. For each discovered `test_*`: `run.sh` calls `setup_test "lp-$$-<name>"`
   (→ `setup_socket` → a fresh isolated server + baseline fixtures on a unique
   socket), resets `TEST_STATUS=pass`, runs the test function in the current
   shell (so `fail`/`assert_*` can set `TEST_STATUS`), prints `PASS`/`FAIL`, then
   `teardown_test` (→ `teardown_socket` → kill the server + clean tmp — fresh for
   the next test).
4. `run.sh` prints `N passed, M failed (of T)` and exits 0 iff `M=0`.

**Pain Points Addressed**:
- (a) **No assertion/runner layer existed.** T1.S1 gave isolation; T2.S1 gives the
  ergonomics (`assert_eq`/`assert_contains`/`fail`) + discovery (`compgen`) +
  the per-test isolation cycle that T3–T6 build on.
- (b) **Cross-test interference.** Tests mutate shared tmux state (activate the
  picker → `key-table=livepicker`, `status=2`, `@livepicker-*` options, a linked
  preview). T2.S1's per-test fresh-socket cycle (FINDING 5) makes each test
  hermetic — a killed+respawned server cannot leak state.
- (c) **"As in the session-history test" / resurrect's `fail_helper`.** The
  work-item §1 RESEARCH NOTE + system_context §7 / sibling_plugins §9 point at
  resurrect's idioms. T2.S1 BORROWS `TEST_STATUS` + `fail` + `compgen` discovery
  and REJECTS resurrect's `teardown_helper` (a REAL `tmux kill-server` +
  `rm -rf ~/.tmux/` — the anti-pattern; it nukes the user's live server). Our
  `teardown_test` delegates to `teardown_socket` (kills ONLY the isolated `-L`).

## Why

- **PRD §15 (Validation)** is the controlling spec: "isolated scripted checks
  (separate tmux socket via a `tmux` PATH wrapper … so the real server is
  untouched)." T1.S1 built the wrapper; T2.S1 builds the runner + assertion layer
  that turns §15's check CLUSTERS (functional/pollution/preview/restore/
  key-repurpose/create-on-enter — T3–T6) into an automated, exit-coded suite.
  Without T2.S1, T3–T6 have no `assert_*`, no discovery, no `run.sh`, no per-test
  isolation.
- **system_context §7 + sibling_plugins §9** (the work-item §1 RESEARCH NOTE) are
  explicit: BORROW resurrect's `fail`/`TEST_STATUS`/`test_*`-discovery STYLE;
  AVOID resurrect's Vagrant/expect/`teardown_helper` (real `kill-server`). T2.S1
  implements exactly that.
- **Scope cohesion.** T2.S1 is the MIDDLE layer of module P1.M7 (Validation):
  T1.S1 owns socket isolation (COMPLETE); T2.S1 owns assertions + discovery +
  the runner + per-test isolation; T3–T6 own the test BODIES (each `source`s
  nothing at file scope — just defines `test_*` functions that use bare `tmux`,
  the baseline fixtures, and the `assert_*` helpers). The shared contract between
  the layers is: `helpers.sh`'s named helpers + `run.sh`'s per-test
  `setup_test`/`teardown_test` cycle. T2.S1 does NOT own test bodies (T3–T6) or
  socket mechanics (T1.S1).

## What

**CREATE** three files under `tests/`:
1. `tests/helpers.sh` — sourced library (assertion + per-test-setup helpers).
2. `tests/run.sh` — executable runner.
3. `tests/test_self.sh` — the §5 self-test.

No other file is touched (`tests/setup_socket.sh` is COMPLETE/owned by T1.S1 —
read-only for this task; `scripts/*` are COMPLETE/IMMUTABLE; PRD/tasks/prd_snapshot
are READ-ONLY). The files have these modes:

- **`helpers.sh`** — SOURCED (no side effects; defines functions + inits
  `TEST_STATUS`). It is NEVER executed directly (no self-test; no
  `BASH_SOURCE`/`$0` guard needed).
- **`run.sh`** — EXECUTED (`bash tests/run.sh`). It is the sole entry point.
- **`test_self.sh`** — SOURCED by `run.sh` (defines `test_true`/`test_false`
  only; no side effects; no file-scope execution).

### Success Criteria

- [ ] All three files pass `bash -n` + `shellcheck` (file-level `disable` for
      SC1091/SC2154/SC2016/SC2034/SC2086 at most — mirror `setup_socket.sh`);
      tabs only; `set -u` only (NO `-e`, NO `pipefail`).
- [ ] `helpers.sh` defines EXACTLY the work-item §3 helper set — `fail`,
      `pass`, `assert_eq`, `assert_contains`, `setup_test`, `teardown_test` —
      plus the `TEST_STATUS` global; sourcing it starts NO server and prints
      nothing (no side effects — verify in Level 1).
- [ ] `assert_eq a b msg` → `[ "$a" = "$b" ]` (POSIX, no subprocess); on mismatch
      calls `fail "$msg"` (sets `TEST_STATUS=fail`); quiet on success.
- [ ] `assert_contains str sub msg` → literal substring via `case "$str" in
      *"$sub"*) …` (quoting `$sub` disables glob specials; no subprocess); on
      absence calls `fail "$msg"`; quiet on success.
- [ ] `setup_test [socket_name]` delegates to `setup_socket "$1"` (the baseline
      fixture seed is ALREADY inside `setup_socket`); `teardown_test` delegates
      to `teardown_socket`. Neither re-implements socket mechanics.
- [ ] `run.sh` sources `setup_socket.sh` + `helpers.sh` + every `tests/test_*.sh`
      (safe `nullglob` glob that matches zero files without error); discovers
      `test_*` via `compgen -A function | grep '^test_' | sort`; wraps EACH in
      `setup_test "lp-$$-<name>"` → `TEST_STATUS=pass` → run (current shell) →
      read `TEST_STATUS` → print `PASS`/`FAIL` → `teardown_test`; prints a
      `N passed, M failed` summary; exits 0 iff `M=0` else 1.
- [ ] **§5 self-test:** `bash tests/run.sh` → `test_true` PASS, `test_false`
      PASS (gated) → exit 0. `LIVEPICKER_NEGATIVE_SELF_TEST=1 bash tests/run.sh`
      → `test_true` PASS, `test_false` FAIL → exit 1.
- [ ] `git diff --stat` shows ONLY `tests/helpers.sh`, `tests/run.sh`,
      `tests/test_self.sh` added.

## All Needed Context

### Context Completeness Check

_Pass_: A developer who has never seen this repo can implement T2.S1 from
(a) the ready-to-paste snippets in "Implementation Patterns & Key Details";
(b) the 9 findings in `research/helpers_run_findings.md` — most critically
**FINDING 1** (the resurrect idiom, verbatim — `TEST_STATUS`/`fail`/`compgen`
discovery; AVOID its `teardown_helper`), **FINDING 2** (the ACTUAL
`setup_socket.sh` interface — the contract T2.S1 delegates to), **FINDING 5**
(the per-test fresh-socket DECISION + the "runs setup_test once" reconciliation),
**FINDING 7** (`compgen` in the current shell + `nullglob` + `set -u` safety);
and (c) the PROBE in FINDING 6 that verified the per-test cycle live. The INPUT
dependency is `tests/setup_socket.sh` (P1.M7.T1.S1 — COMPLETE, read in full);
`scripts/*` are COMPLETE but this task does not edit them.

### Documentation & References

```yaml
# MUST READ — the authoritative spec for WHY (borrow resurrect idioms; avoid its teardown).
- docfile: plan/001_fd5d622d3939/architecture/system_context.md
  why: §7 prints the resurrect idiom to BORROW (TEST_STATUS/fail/test_* discovery)
        and the resurrect teardown_helper to AVOID (real tmux kill-server); §9 shell
        style (set -u ONLY, no -e/pipefail; tabs; local; CURRENT_DIR idiom; quote
        everything); §3 INVARIANT A (why socket isolation is sufficient).
  section: "§7 Test harness reality", "§9 Shell style", "§3 INVARIANT A".
  critical: §7's resurrect snippet is the work-item §1 RESEARCH NOTE made permanent.

# MUST READ — the sibling scout (confirms no harness exists + the exact resurrect idioms).
- docfile: plan/001_fd5d622d3939/architecture/sibling_plugins_and_env.md
  why: §9 prints resurrect's tests/helpers/helpers.sh idioms verbatim
        (TEST_STATUS/fail_helper/teardown_helper/exit_helper/run_tests + the
        `compgen -A function | grep '^test_'` discovery line) and labels
        teardown_helper the anti-pattern; §4 the CURRENT_DIR + get_tmux_option
        idioms to mirror.
  section: "§9 Test harness", "§4 SCRIPT_DIR computation & helper sourcing".

# MUST READ — the empirical + idiomatic ground-truth for THIS task (9 findings + PROBE).
- docfile: plan/001_fd5d622d3939/P1M7T2S1/research/helpers_run_findings.md
  why: FINDING 1 (resurrect idiom verbatim — borrow TEST_STATUS/fail/compgen;
        AVOID teardown_helper); FINDING 2 (the ACTUAL setup_socket.sh interface —
        the contract T2.S1 delegates to); FINDING 3 (the in-house assert idiom ->
        named assert_eq/assert_contains); FINDING 4 (the merged runner loop);
        FINDING 5 (the per-test fresh-socket DECISION + "runs setup_test once"
        reconciliation — reading B); FINDING 6 (PROBE: the per-test cycle is clean);
        FINDING 7 (compgen current-shell + nullglob + set -u gotchas); FINDING 8
        (the §5 self-test design); FINDING 9 (house style + FORBIDDEN edits).
  critical: Read BEFORE writing. FINDING 2 (delegate, don't re-implement) +
        FINDING 5 (per-test fresh socket) + FINDING 7 (current-shell compgen) are
        the three non-obvious traps.

# MUST READ — the INPUT dependency (the contract T2.S1 builds on). READ IN FULL.
- file: tests/setup_socket.sh
  why: the file T2.S1 consumes. It is COMPLETE (P1.M7.T1.S1). Provides setup_socket
        [socket_name] / teardown_socket / attach_test_client / detach_test_client +
        exports TEST_SOCKET/TMUX_SOCK_DIR/TMUX_SOCKET_PATH/REAL_TMUX/LIVEPICKER_*/
        TEST_DRIVER_SESSION("driver")/TEST_FIXTURE_SESSIONS("alpha beta"). It is a
        SOURCED library (no side effects on source). Mirror its header style
        (CONTRACT line, set -u, tabs, local, CURRENT_DIR, shellcheck disable).
  pattern: "# CONTRACT: sourcing this file has NO side effects …" header; the
        function-doc-comment style; the file-level `# shellcheck disable=SC2154,…`.
  gotcha: setup_socket is COMPLETE/IMMUTABLE — do NOT edit it. DELEGATE to it.

# MUST READ — the house-style template (sourced library with NO side effects).
- file: scripts/utils.sh
  why: the canonical "sourced library" file. Copy its CONTRACT line ("sourcing this
        file has NO side effects"), its set -u header (NOT -e/pipefail), its
        local-everywhere + tabs style, its CURRENT_DIR idiom. helpers.sh is the
        TESTS-layer analogue of utils.sh (a sourced helper library).
  pattern: CONTRACT line + set -u + local + tabs + CURRENT_DIR.
  gotcha: utils.sh is COMPLETE/IMMUTABLE — do NOT edit it. Mirror its STYLE only.

# MUST READ (the resurrect SOURCE of the idiom — read to confirm verbatim).
- file: ~/.config/tmux/plugins/tmux-resurrect/lib/tmux-test/tests/helpers/helpers.sh
  why: the REAL origin of TEST_STATUS/fail_helper/exit_helper/run_tests + the
        `compgen -A function | grep '^test_'` discovery. Copy the STYLE (TEST_STATUS
        global; fail echoes to stderr + sets the flag; run_tests iterates compgen in
        the CURRENT shell). REJECT teardown_helper (real tmux kill-server + rm -rf
        ~/.tmux — the anti-pattern).
  pattern: TEST_STATUS="success"; fail_helper(){ echo "$1">&2; TEST_STATUS="fail"; };
        run_tests(){ for t in $(compgen -A function|grep '^test_'); do "$t"; done; … }.
  gotcha: resurrect runs ALL tests in ONE shared env with one trailing exit_helper.
        T2.S1 EXTENDS this: per-test TEST_STATUS reset + per-test setup/teardown +
        per-test PASS/FAIL reporting (the work-item wants more than resurrect).

# MUST READ (cross-reference) — the throwaway mocks that pre-figured the assert idiom.
- docfile: plan/001_fd5d622d3939/P1M6T4S1/research/cancel_mock.sh
- docfile: plan/001_fd5d622d3939/P1M6T3S1/research/confirm_mock.sh
  why: both use the counted `ok`/`bad`/`assert(){ n=$((n+1)); if eval "$1"; then ok;
        else bad; fi; }` shape (the resurrect style, productionized for a single
        throwaway run). T2.S1's helpers.sh PROMOTES this to NAMED, ergonomic helpers
        (assert_eq/assert_contains/fail/pass) that set the GLOBAL TEST_STATUS (so
        run.sh can read the result in the current shell) instead of a per-file local.
  critical: the mocks are THROWAWAY (P1.M6 owned them). Do NOT ship them. T2.S1 is
        the productionized, sourced, NAMED-helper version of their assert shape.

# MUST READ — the PRD sections selected for this work item.
- docfile: PRD.md
  why: §15 Validation (the controlling spec — "isolated scripted checks … so the
        real server is untouched"; lists the check CLUSTERS T3–T6 will implement
        ON TOP of this runner); §16 Implementation risks (tmux 3.0 floor; the
        client-attach need for switch-client/display-message/refresh-client — tests
        needing a client call attach_test_client themselves; setup_test does NOT
        attach by default).
  section: "§15 Validation", "§16 Implementation risks and notes".

# MUST READ (parallel-execution contract) — what EXISTS when this task runs.
- docfile: plan/001_fd5d622d3939/P1M7T1S1/PRP.md
  why: P1.M7.T1.S1 (setup_socket.sh) is the INPUT. Its PRP defines the
        setup_socket/teardown_socket contract + the exported env (TEST_SOCKET,
        LIVEPICKER_SCRIPTS, TEST_DRIVER_SESSION, TEST_FIXTURE_SESSIONS, …) that
        T2.S1 delegates to. The file is ALREADY IMPLEMENTED (read tests/setup_socket.sh
        in full — it matches the PRP). Treat setup_socket.sh as COMPLETE/IMMUTABLE.
```

### Current Codebase tree

```bash
tmux-livepicker/
  PRD.md                         # READ-ONLY (FORBIDDEN to edit).
  plugin.tmux                    # COMPLETE. Unchanged.
  plan/001_fd5d622d3939/{architecture/*.md, tasks.json, prd_snapshot.md, prd_index.txt}
  plan/001_fd5d622d3939/P1M7T1S1/{PRP.md, research/setup_socket_findings.md}
  plan/001_fd5d622d3939/P1M7T2S1/{PRP.md, research/helpers_run_findings.md}   # THIS
  scripts/
    options.sh utils.sh state.sh filter.sh renderer.sh preview.sh
    livepicker.sh restore.sh input-handler.sh    # ALL COMPLETE (P1.M1–M6). IMMUTABLE.
  tests/
    setup_socket.sh   # COMPLETE (P1.M7.T1.S1). READ-ONLY for this task. Provides
                      #   setup_socket/teardown_socket + attach_test_client/detach_test_client
                      #   + exports TEST_SOCKET/TMUX_*/REAL_TMUX/LIVEPICKER_*/TEST_DRIVER_SESSION/
                      #     TEST_FIXTURE_SESSIONS. SOURCED library (no side effects on source).
  .gitignore
  # NOTE: tests/helpers.sh, tests/run.sh, tests/test_self.sh do NOT exist yet — THIS task creates them.
```

### Desired Codebase tree with files to be added and responsibility of file

```bash
tmux-livepicker/
  tests/
    setup_socket.sh   # UNCHANGED (T1.S1 owns it).
    helpers.sh        # NEW (this task). SOURCED bash library (no side effects). Provides:
                      #   TEST_STATUS global (resurrect idiom; "" until a test runs).
                      #   fail msg            — echo to stderr + TEST_STATUS=fail (NEVER exit; accumulate).
                      #   pass msg            — echo a pass line (optional verbose narration).
                      #   assert_eq a b msg   — [ "$a" = "$b" ]; on mismatch -> fail "$msg".
                      #   assert_contains str sub msg — case "$str" in *"$sub"*) literal substring;
                      #                                 on absence -> fail "$msg".
                      #   setup_test [socket_name]  — delegate to setup_socket "$1" (baseline fixtures
                      #                               are seeded INSIDE setup_socket). Does NOT attach a client.
                      #   teardown_test             — delegate to teardown_socket (idempotent).
                      # CONTRACT: sourcing has NO side effects (mirrors utils.sh/setup_socket.sh).
    run.sh            # NEW (this task). EXECUTABLE entry point (`bash tests/run.sh`):
                      #   source setup_socket.sh + helpers.sh + every tests/test_*.sh (nullglob);
                      #   discover test_* via `compgen -A function | grep '^test_' | sort`;
                      #   PER TEST: setup_test "lp-$$-<name>" (fresh isolated socket) -> TEST_STATUS=pass
                      #     -> run $t in the CURRENT shell -> read TEST_STATUS -> print PASS/FAIL
                      #     -> teardown_test;
                      #   print "N passed, M failed (of T)"; exit 0 iff M=0 else 1.
    test_self.sh      # NEW (this task). SOURCED by run.sh (defines test_true + test_false only).
                      #   test_true  — assert_eq 1 1 + assert_contains (passes).
                      #   test_false — fails ONLY under LIVEPICKER_NEGATIVE_SELF_TEST=1 (keeps the
                      #                default suite green; proves the failure path + exit code). §5 self-test.
                      # CONTRACT: no side effects on source (only function defs).
```

### Known Gotchas of our codebase & Library Quirks

```bash
# CRITICAL (research FINDING 5 — the "runs setup_test once" ambiguity): the
#   work-item §3 says "runs setup_test once, iterates test_* (each gets its own
#   fresh fixture via per-test setup/teardown)". The robust + contract-faithful
#   reading is (B): setup_test/teardown_test ARE the PER-TEST pair — run.sh wraps
#   EACH test in setup_test->test->teardown_test, giving every test a FRESH
#   isolated tmux server. Rationale: (1) the contract names ONLY setup_test/
#   teardown_test (no extra per-test helpers) -> they must BE the per-test pair;
#   (2) "each gets its own fresh fixture via per-test setup/teardown" literally
#   describes per-test setup/teardown; (3) T3-T6 tests MUTATE shared state
#   (key-table=livepicker, status=2, @livepicker-*, linked preview) -> a soft
#   reset between them is fragile; a killed+respawned server is hermetic. "Runs
#   setup_test once" is satisfied as ONCE PER TEST FUNCTION. Do NOT use reading
#   (A) (one shared socket + invented per-test reset helpers) — it re-implements
#   restore.sh and risks flaky cross-test interference.

# CRITICAL (research FINDING 7 — compgen MUST run in the CURRENT shell): run.sh
#   discovers test_* with `compgen -A function | grep '^test_'` and calls each in
#   the CURRENT shell (NOT a subshell) so `fail`'s `TEST_STATUS=fail` is visible.
#   A subshell `( "$t" )` would lose TEST_STATUS. CONSEQUENCE: a test that calls
#   bare `exit` would kill the runner -> the CONTRACT for T3-T6 authors is: signal
#   failure ONLY via fail/assert_* (which set TEST_STATUS); NEVER `exit`/`return`
#   nonzero to abort. (Mirrors resurrect's fail_helper contract.) Document this.

# CRITICAL (research FINDING 2 — DELEGATE, do not re-implement): setup_socket/
#   teardown_socket/attach_test_client/detach_test_client + all TEST_*/TMUX_*/
#   REAL_TMUX/LIVEPICKER_* exports ALREADY exist in tests/setup_socket.sh (COMPLETE,
#   read in full). helpers.sh's setup_test/teardown_test are THIN WRAPPERS that
#   delegate (setup_test [name] -> setup_socket "$1"; teardown_test -> teardown_socket).
#   Do NOT re-implement socket/path/shim/fixture logic. Do NOT edit setup_socket.sh.

# GOTCHA (research FINDING 7 — safe glob): `for f in "$DIR"/test_*.sh` with NO
#   matching file expands to the LITERAL `test_*.sh` (which then fails to source).
#   Use `shopt -s nullglob` (non-matching glob -> nothing) around the loop, then
#   `shopt -u nullglob` (or scope in a subshell) so later globs aren't surprised.
#   At T2.S1 ship time only test_self.sh matches; T3-T6 add more later.

# GOTCHA (assert_contains literal match): use `case "$str" in *"$sub"*) … ;; *) … ;;
#   esac`. Quoting "$sub" in the case PATTERN disables glob specials (?,*,[) for
#   the quoted segment -> literal substring match, no subprocess, robust vs special
#   chars. Do NOT use `[[ "$str" == *"$sub"* ]]` (sub becomes a pattern; a sub of
#   "*" or "?" would mis-match) or `echo "$str" | grep -F -- "$sub"` (subprocess +
#   set -e/pipefail hazard; house style forbids pipefail).

# GOTCHA (per-test unique socket name): setup_socket defaults TEST_SOCKET to
#   "livepicker-test-$$" ($$ = run.sh PID, STABLE across calls in one process).
#   Called repeatedly, it REUSES the name — but teardown_socket kills that server +
#   rm -f's the socket file first, so a same-named re-setup works. To avoid ANY
#   collision and keep PATH clean, run.sh passes a per-test name:
#   setup_test "lp-$$-${t#test_}". PATH accumulates one DANGLING shim-dir entry per
#   test (the dir is rm -rf'd by teardown, so PATH lookup falls through to the next
#   live shim -> harmless; verified by FINDING 6 probe).

# STYLE (research FINDING 9 / system_context §9): shebang #!/usr/bin/env bash;
#   set -u ONLY (NOT -e — fail/assertions/tmux cmds legitimately "fail" without
#   aborting; NOT pipefail); local for ALL function locals; TABS for indent; quote
#   everything; CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)".
#   File-level `# shellcheck disable=SC1091,SC2154,SC2016,SC2034,SC2086` (mirror
#   setup_socket.sh) for the dynamic source + eval/quoting false positives.

# GOTCHA: do NOT edit tests/setup_socket.sh, any scripts/* file, PRD.md,
#   tasks.json, prd_snapshot.md, or .gitignore (FORBIDDEN). This task ADDS exactly
#   three files: tests/helpers.sh, tests/run.sh, tests/test_self.sh.
```

## Implementation Blueprint

### Data models and structure

No data model in the ORM/pydantic sense. The "model" is the **shared test-status
contract** between `helpers.sh`, `run.sh`, and every `tests/test_*.sh`:

```bash
# The resurrect-style global assertion flag (defined in helpers.sh; read by run.sh;
# set by fail/assert_*; reset by run.sh before each test):
TEST_STATUS        # "" (init) -> "pass" (run.sh, before each test) -> "fail" (fail/assert_*).
                   # run.sh treats a test as PASSED iff TEST_STATUS="pass" after it returns.

# The layering contract (who owns what — DO NOT cross these boundaries):
#   tests/setup_socket.sh (T1.S1, COMPLETE): socket isolation + PATH shim + baseline
#       fixtures + attach/detach_test_client + the TEST_*/TMUX_*/REAL_TMUX/LIVEPICKER_* exports.
#   tests/helpers.sh      (T2.S1, THIS): assert_*/fail/pass + setup_test/teardown_test
#       (THIN delegates to setup_socket/teardown_socket) + the TEST_STATUS global.
#   tests/run.sh          (T2.S1, THIS): source-all + compgen discovery + per-test
#       setup_test->test->teardown_test cycle + PASS/FAIL reporting + exit code.
#   tests/test_*.sh       (T2.S1 ships test_self.sh; T3-T6 ship the rest): define test_*
#       functions ONLY (no side effects on source); use bare `tmux`, the baseline
#       fixtures, and the assert_* helpers; signal failure ONLY via fail/assert_*.
```

### Implementation Tasks (ordered by dependencies)

```yaml
Task 1: CREATE tests/helpers.sh — header + TEST_STATUS + fail/pass + assert_*
  - CREATE: tests/helpers.sh (NEW; a sourced library — NEVER executed directly).
  - HEADER: #!/usr/bin/env bash ; a CONTRACT comment ("sourcing this file has NO
        side effects — it defines functions + initializes TEST_STATUS only; starts
        NO server, sources nothing, prints nothing — mirrors utils.sh/setup_socket.sh");
        set -u ONLY (NOT -e, NOT pipefail); CURRENT_DIR idiom; file-level
        `# shellcheck disable=SC1091,SC2154,SC2016,SC2034,SC2086`.
  - IMPLEMENT: `TEST_STATUS=""` (init; run.sh resets to "pass" before each test).
  - IMPLEMENT: `fail msg` — resurrect fail_helper: `echo "FAIL: $msg" >&2` (or to
        stdout with a marker) + `TEST_STATUS="fail"`. NEVER exit/return-nonzero-to-
        abort (accumulate; run.sh reads TEST_STATUS).
  - IMPLEMENT: `pass msg` — `echo "ok: $msg"` (optional verbose narration; does
        NOT set TEST_STATUS — only fail does).
  - IMPLEMENT: `assert_eq a b msg` — `if [ "$a" = "$b" ]; then :; else fail "$msg
        (got [$a] want [$b])"; fi`. POSIX `[ ]`, no subprocess. Quiet on success.
  - IMPLEMENT: `assert_contains str sub msg` — `case "$str" in *"$sub"*) : ;;
        *) fail "$msg (substring [$sub] absent in [$str])"; esac`. Quoted "$sub"
        in the pattern => literal match, no glob specials, no subprocess. Quiet on
        success.
  - FOLLOW pattern: scripts/utils.sh + tests/setup_socket.sh (sourced-library
        header, set -u, local, tabs, CURRENT_DIR, no-side-effects CONTRACT line,
        shellcheck disable header).
  - NAMING: fail/pass/assert_eq/assert_contains; snake_case; TABS; local for all
        locals (msg/a/b/str/sub).
  - DO NOT: re-implement socket/path/shim/fixture logic (that's setup_socket.sh);
        add set -e/pipefail; call exit inside fail; edit setup_socket.sh.

Task 2: ADD setup_test + teardown_test (THIN delegates — FINDING 2)
  - IMPLEMENT: `setup_test [socket_name]` — `setup_socket "${1:-}"`. The baseline
        fixtures (driver/alpha/beta + multi-pane windows) are seeded INSIDE
        setup_socket, so setup_test needs no extra seeding (the work-item "setup_test
        calls setup_socket + seeds fixtures" is satisfied: setup_socket IS the seeder).
        Does NOT attach a client (the contract lists only "setup_socket + seeds
        fixtures"; tests needing a client call attach_test_client themselves).
  - IMPLEMENT: `teardown_test` — `teardown_socket` (idempotent; kills the isolated
        server + cleans tmp; detaches any client first — all inside teardown_socket).
  - FOLLOW pattern: thin delegation; do NOT duplicate teardown_socket's 3-step
        cleanup or attach/detach logic.
  - NAMING: setup_test/teardown_test; local; tabs. Document the delegation in the
        doc comment (cite FINDING 2).

Task 3: CREATE tests/run.sh — source-all + discovery + per-test cycle + exit code
  - CREATE: tests/run.sh (NEW; the EXECUTABLE entry point — `bash tests/run.sh`).
  - HEADER: #!/usr/bin/env bash ; set -u ONLY ; CURRENT_DIR idiom ; a one-line
        doc comment ("entry point: runs every tests/test_*.sh's test_* functions
        against a fresh isolated socket per test; exits 0 iff all pass").
  - IMPLEMENT:
        (a) CURRENT_DIR; source "$CURRENT_DIR/setup_socket.sh"; source "$CURRENT_DIR/helpers.sh".
        (b) `shopt -s nullglob`; `for f in "$CURRENT_DIR"/test_*.sh; do source "$f"; done`;
            `shopt -u nullglob` (safe when zero files — FINDING 7).
        (c) `tests="$(compgen -A function | grep '^test_' | sort)"` (CURRENT shell;
            deterministic order).
        (d) `passed=0; failed=0; total=0`.
        (e) for t in $tests:
              total=$((total+1))
              setup_test "lp-$$-${t#test_}"   # per-test FRESH isolated socket (FINDING 5)
              TEST_STATUS="pass"             # resurrect idiom; reset per test
              "$t"                           # run in the CURRENT shell (NOT subshell — FINDING 7)
              if [ "$TEST_STATUS" = "pass" ]; then echo "PASS  $t"; passed=$((passed+1));
              else echo "FAIL  $t"; failed=$((failed+1)); fi
              teardown_test                  # kill server + clean tmp (fresh for next test)
        (f) echo a summary: "----"; echo "$passed passed, $failed failed (of $total)".
        (g) `[ "$failed" -eq 0 ] && exit 0 || exit 1`.
  - FOLLOW pattern: resurrect run_tests (compgen discovery, current shell) +
        run_tests_in_isolation (exit-value aggregation) — MERGED (FINDING 4).
  - NAMING: run.sh; local for loop locals (f/t/tests/passed/failed/total); TABS.
  - DO NOT: run tests in a subshell (loses TEST_STATUS); add set -e/pipefail;
        check $? after "$t" as the pass signal (a test may legitimately end on a
        nonzero tmux command — TEST_STATUS is the ONLY signal; FINDING 7).

Task 4: CREATE tests/test_self.sh — the §5 self-test (test_true + test_false)
  - CREATE: tests/test_self.sh (NEW; SOURCED by run.sh — defines test_* only; no
        side effects on source; no file-scope execution).
  - HEADER: #!/usr/bin/env bash ; a one-line doc comment ("§5 self-test: proves
        run.sh reports a pass (test_true) and a fail (test_false) and the exit code
        reflects it; test_false is gated so the default suite stays green").
  - IMPLEMENT: `test_true` — `assert_eq "1" "1" "sanity equality holds"` +
        `assert_contains "hello world" "world" "substring found"`. (Passes.)
  - IMPLEMENT: `test_false` — gated: `if [ "${LIVEPICKER_NEGATIVE_SELF_TEST:-0}"
        = "1" ]; then assert_eq "1" "2" "intentional self-test failure (expected)";`
        `else assert_eq "1" "1" "negative path disabled (LIVEPICKER_NEGATIVE_SELF_TEST=1)"; fi`.
        (Default: passes; under the flag: fails.)
  - NAMING: test_true/test_false (discovered by run.sh's compgen); TABS.
  - DO NOT: add side effects on source; call exit; call setup_test/teardown_test
        (run.sh owns the per-test cycle).

Task 5: VALIDATE (Level 1 syntax/lint + Level 2 self-test both modes + real-server untouched)
  - RUN: bash -n on all three; shellcheck on all three; `bash tests/run.sh`
        (expect test_true PASS, test_false PASS, exit 0);
        `LIVEPICKER_NEGATIVE_SELF_TEST=1 bash tests/run.sh` (expect test_true PASS,
        test_false FAIL, exit 1); snapshot `/usr/bin/tmux list-sessions` before/after
        a full run.sh invocation and assert byte-identical (non-pollution).
```

### Implementation Patterns & Key Details

#### helpers.sh — the assertion helpers (Task 1) + delegates (Task 2)

```bash
#!/usr/bin/env bash
# tests/helpers.sh — tmux-livepicker test assertion + per-test-setup helpers (P1.M7.T2.S1).
#
# Sourced library (NOT executed). Provides the resurrect-style assertion helpers
# (fail/pass/assert_eq/assert_contains) + the per-test setup_test/teardown_test
# pair (THIN delegates to tests/setup_socket.sh's setup_socket/teardown_socket —
# P1.M7.T1.S1). Builds the discovery/runner layer that run.sh + tests/test_*.sh
# (P1.M7.T3-T6) rely on.
#
# CONTRACT: sourcing this file has NO side effects — it defines functions +
# initializes the TEST_STATUS global only; it starts NO server, sources nothing,
# prints nothing (mirrors scripts/utils.sh + tests/setup_socket.sh). run.sh is the
# executable entry point that sources this + setup_socket.sh + every tests/test_*.sh.
#
# Borrows resurrect's TEST_STATUS/fail/test_*-discovery STYLE (system_context §7,
# sibling_plugins §9) and REJECTS resurrect's teardown_helper (a REAL tmux
# kill-server + rm -rf ~/.tmux — the anti-pattern; our teardown_test delegates to
# teardown_socket, which kills ONLY the isolated -L socket).
#
# set -u ONLY (NOT -e — fail/assertions/tmux cmds legitimately "fail" without
# aborting; NOT pipefail); local for all function locals; TABS for indent.
# See plan/001_fd5d622d3939/P1M7T2S1/research/helpers_run_findings.md (FINDING 1-9).
# shellcheck disable=SC2154,SC2016,SC2034,SC2086

set -u

CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# resurrect-style global assertion flag (FINDING 1). run.sh resets this to "pass"
# before each test; fail()/assert_*() set it to "fail"; run.sh reads it after each
# test to decide PASS/FAIL. Never exits on failure (accumulate — mirrors fail_helper).
TEST_STATUS=""

# fail msg — resurrect fail_helper: record a failure (stderr) + set TEST_STATUS=fail.
# Does NOT exit/abort — run.sh aggregates at the end. (Mirrors resurrect's fail_helper;
# the CONTRACT for test bodies is: signal failure ONLY via fail/assert_*.)
fail() {
	local msg="$1"
	echo "  ASSERT FAIL: $msg" >&2
	TEST_STATUS="fail"
}

# pass msg — optional explicit pass narration (verbose). Does NOT touch TEST_STATUS
# (only fail does). Use for human-readable progress inside a test body.
pass() {
	local msg="$1"
	echo "  ok: $msg"
}

# assert_eq a b msg — POSIX equality (no subprocess). Quiet on success; on mismatch
# calls fail (sets TEST_STATUS=fail) with a diff-style diagnostic.
assert_eq() {
	local a="$1" b="$2" msg="$3"
	if [ "$a" = "$b" ]; then
		:
	else
		fail "$msg (got [$a] want [$b])"
	fi
}

# assert_contains str sub msg — literal substring. Uses `case` with "$sub" QUOTED
# in the pattern so glob specials (?,*,[) are disabled for the quoted segment =>
# literal match, no subprocess, robust vs special chars (FINDING 3). Quiet on
# success; on absence calls fail with a diagnostic.
assert_contains() {
	local str="$1" sub="$2" msg="$3"
	case "$str" in
		*"$sub"*)
			:
			;;
		*)
			fail "$msg (substring [$sub] absent in [$str])"
			;;
	esac
}

# setup_test [socket_name] — bring up a FRESH isolated tmux server + baseline
# fixtures for ONE test. THIN delegate to setup_socket (P1.M7.T1.S1 — FINDING 2):
# the temp dir + PATH shim + exports + server start + baseline fixture seeding
# (driver/alpha/beta + multi-pane windows) ALL happen inside setup_socket. Does
# NOT attach a client (tests needing switch-client/display-message-p/refresh-client-S
# call attach_test_client themselves). run.sh calls this once PER test with a
# unique socket name (FINDING 5) so each test is hermetic.
setup_test() {
	setup_socket "${1:-}"
}

# teardown_test — kill the isolated server + clean tmp for the test just run. THIN
# delegate to teardown_socket (idempotent: detaches any client, kill-server, rm -rf
# the shim dir, rm -f the orphaned socket file — all inside teardown_socket).
teardown_test() {
	teardown_socket
}
```

#### run.sh — the runner (Task 3)

```bash
#!/usr/bin/env bash
# tests/run.sh — tmux-livepicker test suite entry point (P1.M7.T2.S1).
#
# Sources tests/setup_socket.sh (socket isolation — P1.M7.T1.S1) + tests/helpers.sh
# (assertions + setup_test/teardown_test) + every tests/test_*.sh, discovers every
# test_* function via `compgen -A function | grep '^test_'`, and runs each against
# a FRESH isolated tmux server (per-test setup_test -> test -> teardown_test). Prints
# PASS/FAIL per test + a summary; exits 0 iff all passed, else 1.
#
# DESIGN (research FINDING 5): setup_test/teardown_test are the PER-TEST pair (each
# test gets its own fresh fixture via per-test setup/teardown — the work-item §3
# operative clause). This is hermetic: a killed+respawned server cannot leak state
# between tests that mutate shared tmux state (key-table/status/@livepicker-*/linked
# preview). "Runs setup_test once" is satisfied as once-per-test-function.
#
# CONTRACT for test bodies (tests/test_*.sh — P1.M7.T3-T6): define test_* functions
# ONLY (no side effects on source); use bare `tmux` + the baseline fixtures + the
# assert_* helpers; signal failure ONLY via fail/assert_* (which set TEST_STATUS) —
# NEVER exit/return-nonzero-to-abort (run.sh reads TEST_STATUS in the CURRENT shell;
# a bare exit would kill the runner). run.sh brings up + tears down the socket.
#
# set -u ONLY (NOT -e/pipefail); local; TABS. See research/helpers_run_findings.md.
# shellcheck disable=SC1091,SC2154,SC2016,SC2034,SC2086

set -u

CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# (a) Source the isolation layer (setup_socket/teardown_socket) + the assertion
#     layer (assert_*/setup_test/teardown_test). Both are sourced libraries (no
#     side effects on source).
# shellcheck source=setup_socket.sh
source "$CURRENT_DIR/setup_socket.sh"
# shellcheck source=helpers.sh
source "$CURRENT_DIR/helpers.sh"

# (b) Source every test file (defines test_* functions). nullglob => a non-matching
#     glob expands to NOTHING (safe when zero files; FINDING 7). Restore after so
#     later globs aren't surprised.
shopt -s nullglob
for f in "$CURRENT_DIR"/test_*.sh; do
	# shellcheck source=/dev/null
	source "$f"
done
shopt -u nullglob

# (c) Discover test_* in the CURRENT shell (so fail()'s TEST_STATUS is visible —
#     FINDING 7). sort for deterministic order.
tests="$(compgen -A function | grep '^test_' | sort)"

# (d)(e) Per-test fresh-socket cycle.
passed=0
failed=0
total=0
for t in $tests; do
	total=$((total + 1))
	# Per-test UNIQUE socket name (FINDING 5/6): lp-$$-<testname>. setup_socket would
	# default to livepicker-test-$$ (stable $$) — passing a per-test name avoids any
	# collision and keeps the cycle clean across many tests.
	setup_test "lp-$$-${t#test_}"
	TEST_STATUS="pass"   # resurrect idiom; reset before each test.
	# Run in the CURRENT shell (NOT a subshell) so fail/assert_* can set TEST_STATUS.
	"$t"
	if [ "$TEST_STATUS" = "pass" ]; then
		echo "PASS  $t"
		passed=$((passed + 1))
	else
		echo "FAIL  $t"
		failed=$((failed + 1))
	fi
	teardown_test   # kill server + clean tmp — fresh for the next test.
done

# (f) Summary.
echo "----"
echo "$passed passed, $failed failed (of $total)"

# (g) Exit code reflects the aggregate (work-item §4 OUTPUT: exits 0/1).
[ "$failed" -eq 0 ] && exit 0 || exit 1
```

#### test_self.sh — the §5 self-test (Task 4)

```bash
#!/usr/bin/env bash
# tests/test_self.sh — P1.M7.T2.S1 §5 MOCKING self-test.
#
# SOURCED by run.sh (defines test_* only; NO side effects on source; no file-scope
# execution). Proves the runner reports a PASS (test_true) and a FAIL (test_false)
# and the exit code reflects it (work-item §5). test_false is GATED so the default
# suite stays green; enable the negative path to exercise the failure reporting:
#   bash tests/run.sh                                  # test_true PASS, test_false PASS, exit 0
#   LIVEPICKER_NEGATIVE_SELF_TEST=1 bash tests/run.sh  # test_true PASS, test_false FAIL, exit 1
#
# set -u is inherited from helpers.sh (sourced by run.sh before this file).
# shellcheck disable=SC2154

# test_true — a trivially-passing test (proves the PASS path).
test_true() {
	assert_eq "1" "1" "sanity equality holds"
	assert_contains "hello world" "world" "substring found"
}

# test_false — an intentionally-failing test (proves the FAIL path + exit code).
# Gated: only fails under LIVEPICKER_NEGATIVE_SELF_TEST=1, so `bash tests/run.sh`
# is green by default and the negative path is opt-in (keeps test_self.sh shippable).
test_false() {
	if [ "${LIVEPICKER_NEGATIVE_SELF_TEST:-0}" = "1" ]; then
		assert_eq "1" "2" "intentional self-test failure (expected)"
	else
		assert_eq "1" "1" "negative path disabled (set LIVEPICKER_NEGATIVE_SELF_TEST=1 to exercise)"
	fi
}
```

NOTE for the implementer:
- This is THREE NEW FILES under `tests/` (greenfield test infra). No edits to
  `setup_socket.sh` (T1.S1 owns it — COMPLETE), no `scripts/` edits, no PRD/tasks
  edits.
- `helpers.sh` is a SOURCED library (no self-test, no `BASH_SOURCE`/`$0` guard) —
  it is NEVER executed directly. `run.sh` is the ONLY executable.
- `run.sh` runs tests in the CURRENT shell (not a subshell) so `TEST_STATUS`
  propagates. The CONTRACT for T3–T6 test authors: signal failure ONLY via
  `fail`/`assert_*`; never `exit`.
- `setup_test`/`teardown_test` are THIN delegates. Do NOT re-implement socket
  mechanics. Do NOT edit `setup_socket.sh`.
- The §5 self-test is `test_self.sh` with `test_false` gated — keeps the default
  run green + proves the failure path under the flag.

### Integration Points

```yaml
NEW FILES (the ONLY files this task creates):
  - tests/helpers.sh:  sourced library (assert_*/fail/pass + setup_test/teardown_test
        delegates + TEST_STATUS global). No side effects on source.
  - tests/run.sh:      executable entry point (source-all + compgen discovery +
        per-test fresh-socket cycle + PASS/FAIL reporting + exit code).
  - tests/test_self.sh: §5 self-test (test_true + gated test_false). Sourced by run.sh.

CONSUMES (the INPUT — COMPLETE, do NOT edit):
  - tests/setup_socket.sh (P1.M7.T1.S1): setup_socket/teardown_socket +
        attach_test_client/detach_test_client + the TEST_*/TMUX_*/REAL_TMUX/
        LIVEPICKER_* exports. helpers.sh DELEGATES to it; run.sh sources it.

CONSUMERS (downstream — NOT this task's responsibility, but the contract):
  - P1.M7.T3-T6 tests/test_*.sh: each defines test_* functions ONLY (no side effects
        on source); uses bare `tmux`, the baseline fixtures (TEST_DRIVER_SESSION/
        TEST_FIXTURE_SESSIONS), and the assert_* helpers; signals failure ONLY via
        fail/assert_* (never exit). run.sh brings up + tears down the socket per test.
        Tests needing an attached client call attach_test_client themselves.

PROVIDES (the contract downstream tests rely on):
  - fail/pass/assert_eq/assert_contains (set TEST_STATUS; never abort).
  - setup_test [name] / teardown_test (per-test fresh isolated socket).
  - `bash tests/run.sh` -> runs every test_*.sh's test_* against isolated sockets,
        prints PASS/FAIL + summary, exits 0/1.

DATABASE / MIGRATIONS / ROUTES / CONFIG: none. No @livepicker-* options, no tmux
        mutations on the REAL server. The only real-server contact is READ-ONLY
        (optional: snapshot /usr/bin/tmux list-sessions around a run.sh invocation
        to prove non-pollution — a validation step, not part of the shipped code).
```

## Validation Loop

### Level 1: Syntax & Style (Immediate Feedback)

```bash
# Run after creating each file — fix before proceeding.
bash -n tests/helpers.sh tests/run.sh tests/test_self.sh
shellcheck tests/helpers.sh tests/run.sh tests/test_self.sh
#   expect 0 findings (file-level `# shellcheck disable=SC1091,SC2154,SC2016,SC2034,SC2086`
#   is OK — mirror setup_socket.sh).

# Tabs-not-spaces sanity (shfmt NOT installed):
for f in tests/helpers.sh tests/run.sh tests/test_self.sh; do
  grep -Pn '^    ' "$f" && echo "FAIL: 4-space indent in $f, use tabs" || echo "OK: tabs only in $f"
done

# House style (set -u only; NO -e / NO pipefail DECLARED — note: run.sh/sources may
# INHERIT set -u; the rule is no `set -e`/`set -o pipefail` statement):
for f in tests/helpers.sh tests/run.sh tests/test_self.sh; do
  grep -nE 'set -e|set -o pipefail' "$f" && echo "FAIL: set -e/pipefail in $f" || echo "OK: set -u only in $f"
done

# helpers.sh is side-effect-free on source (FINDING 9): a bare source must NOT
# start a server, print anything, or export test-only vars. Capture stdout/stderr
# + the real session list around a source.
real_before="$(/usr/bin/tmux list-sessions -F '#{session_name}' 2>/dev/null | sort)"
out="$( source tests/helpers.sh 2>&1 )"   # in a subshell; must define fns, do nothing
rc=$?
real_after="$(/usr/bin/tmux list-sessions -F '#{session_name}' 2>/dev/null | sort)"
[ -n "$out" ] && echo "FAIL: helpers.sh source printed: $out" || echo "OK: helpers.sh source is silent"
[ "$real_before" = "$real_after" ] && echo "OK: real server unchanged by source" || echo "FAIL: real server changed"
# Also assert the helpers are now defined:
( source tests/helpers.sh; declare -F fail pass assert_eq assert_contains setup_test teardown_test )

# run.sh is the executable; helpers.sh has NO BASH_SOURCE/$0 self-test guard (it's
# never executed directly):
grep -nE 'BASH_SOURCE\[0\].*=.*"\${0}"' tests/helpers.sh && echo "FAIL: helpers.sh has a self-test guard (should not)" || echo "OK: helpers.sh is source-only"

# SCOPE: only the three new files added (no setup_socket.sh / scripts/ / PRD / tasks edits):
git status --porcelain | grep -E '^.M (tests/setup_socket\.sh|scripts/|PRD\.md)|tasks\.json|prd_snapshot' \
  && echo "FAIL: edited an off-limits file" || echo "OK: only tests/helpers.sh + tests/run.sh + tests/test_self.sh added"
```

### Level 2: The §5 Self-Test — BOTH modes (work-item §5 MOCKING)

```bash
# (a) Default run: test_true PASS, test_false PASS (gated off) -> exit 0.
bash tests/run.sh
echo "exit=$?"
# Expected output (order may vary by sort, but both present):
#   PASS  test_false
#   PASS  test_true
#   ----
#   2 passed, 0 failed (of 2)
#   exit=0

# (b) Negative path: test_true PASS, test_false FAIL -> exit 1 (proves the runner
#     propagates a failure and the exit code reflects it — §5).
LIVEPICKER_NEGATIVE_SELF_TEST=1 bash tests/run.sh
echo "exit=$?"
# Expected:
#   ASSERT FAIL: intentional self-test failure (expected) (got [1] want [2])    <- on stderr
#   PASS  test_true
#   FAIL  test_false
#   ----
#   1 passed, 1 failed (of 2)
#   exit=1

# If (a) exits non-zero or (b) exits zero, the runner is broken: check that fail()
# sets TEST_STATUS and run.sh reads it (current shell, not subshell — FINDING 7).
```

### Level 3: Integration — a real test_*.sh drives the plugin scripts (smoke proof)

```bash
# Proof the harness (setup_socket shim + helpers + run.sh per-test cycle) lets a
# real test body drive the plugin's COMPLETED scripts against the isolated socket.
# This is the property T3-T6 depend on. Run from the repo root:
cat > tests/test_smoke.sh <<'SMOKE'
#!/usr/bin/env bash
# Throwaway smoke test (delete after). Proves: bare `tmux` hits the isolated socket;
# a real plugin helper (utils.sh's tmux_set_opt) writes there, not the real server;
# assert_eq passes; teardown leaves no @livepicker-smoke on the real server.
test_smoke_isolated() {
	# The plugin's utils.sh calls bare `tmux show-option`/`set-option` -> with the
	# shim on PATH (installed by setup_test), it hits the ISOLATED socket.
	# shellcheck disable=SC1091
	source "$LIVEPICKER_SCRIPTS/utils.sh"
	tmux_set_opt "@livepicker-smoke" "isolated-ok"
	local shim_val real_val
	shim_val="$(tmux show-option -gqv @livepicker-smoke)"                       # via shim -> isolated
	real_val="$(/usr/bin/tmux show-option -gqv @livepicker-smoke 2>/dev/null)"  # via real -> UNSET
	assert_eq "$shim_val" "isolated-ok" "plugin's bare-tmux helper wrote to the isolated socket"
	assert_eq "$real_val" "" "real server has no @livepicker-smoke (non-pollution)"
}
SMOKE
bash tests/run.sh
echo "exit=$?"
rm -f tests/test_smoke.sh
# Expected: PASS test_smoke_isolated, PASS test_true, PASS test_false, exit 0.
#   (Proves the full stack: setup_socket shim intercepts the PLUGIN's bare `tmux`;
#    helpers.sh assert_eq works; run.sh's per-test setup_test/teardown_test cycle
#    gives the test an isolated socket + cleans up. The smoke test is removed.)
```

### Level 4: Creative & Domain-Specific Validation (PRD §15 non-pollution + robustness)

```bash
# PRD §15 invariant (the real server is untouched) — snapshot the user's real
# session list around a FULL run.sh invocation (multiple per-test setup/teardown
# cycles). This is the gold-standard proof the harness never touches the real server.
real_before="$(/usr/bin/tmux list-sessions -F '#{session_name}' | sort)"
bash tests/run.sh >/dev/null 2>&1
LIVEPICKER_NEGATIVE_SELF_TEST=1 bash tests/run.sh >/dev/null 2>&1
real_after="$(/usr/bin/tmux list-sessions -F '#{session_name}' | sort)"
[ "$real_before" = "$real_after" ] && echo "OK: real server byte-identical before/after full run" \
  || { echo "FAIL: real server changed"; diff <(echo "$real_before") <(echo "$real_after"); }

# Robustness: no test_*.sh files at all -> run.sh exits 0 cleanly (nullglob; FINDING 7).
mkdir -p /tmp/lp_empty/tests && cp tests/setup_socket.sh tests/helpers.sh tests/run.sh /tmp/lp_empty/tests/
( cd /tmp/lp_empty && bash tests/run.sh; echo "exit=$?" )   # expect "0 passed, 0 failed (of 0)", exit 0
rm -rf /tmp/lp_empty

# Robustness: per-test isolation — two tests that mutate state don't interfere.
# (Add a throwaway tests/test_order.sh with test_a (creates a session) + test_b
#  (asserts the session is ABSENT — proves b got a fresh server, not a's leftovers).)
cat > tests/test_order.sh <<'ORD'
test_a_leaves_state() { tmux new-session -d -s dirty-leftover; assert_contains "$(tmux list-sessions -F '#{session_name}')" "dirty-leftover" "a created dirty-leftover"; }
test_b_is_fresh() { assert_eq "$(tmux list-sessions -F '#{session_name}' | grep -c dirty-leftover)" "0" "b's fresh server has no dirty-leftover (per-test isolation)"; }
ORD
bash tests/run.sh; echo "exit=$?"; rm -f tests/test_order.sh
# Expected: both PASS + exit 0 (or 1 if test_false gated-path ran) — the KEY assertion
#   is test_b_is_fresh passes: b's server does NOT have dirty-leftover => per-test
#   fresh-socket isolation works (FINDING 5/6).

# Discovery sanity: compgen finds test_* from ALL sourced files (test_self.sh + any
# throwaway). `bash tests/run.sh` line count == number of test_* functions discovered.
n_funcs="$(bash -c 'source tests/setup_socket.sh; source tests/helpers.sh; shopt -s nullglob; for f in tests/test_*.sh; do source "$f"; done; compgen -A function | grep -c "^test_"')"
n_lines="$(bash tests/run.sh 2>/dev/null | grep -cE '^(PASS|FAIL)  test_')"
[ "$n_funcs" = "$n_lines" ] && echo "OK: discovered $n_funcs test_* functions, ran $n_lines" || echo "FAIL: discovery/run mismatch ($n_funcs vs $n_lines)"
```

## Final Validation Checklist

### Technical Validation

- [ ] Level 1 passes: `bash -n` + `shellcheck` (0 new findings) on all three files;
      tabs only; `set -u` only (no `set -e`/`pipefail` statement).
- [ ] Level 2 passes: `bash tests/run.sh` → both PASS, exit 0;
      `LIVEPICKER_NEGATIVE_SELF_TEST=1 bash tests/run.sh` → test_true PASS,
      test_false FAIL, exit 1 (§5 MOCKING).
- [ ] Level 3 passes: the smoke `test_smoke.sh` proves the plugin's bare-`tmux`
      helper writes to the ISOLATED socket (via the shim), not the real one.
- [ ] Level 4 passes: real server byte-identical before/after a full run; empty-dir
      run exits 0; per-test isolation proven (test_b's fresh server lacks test_a's
      leftover); discovery count == run count.
- [ ] `git status --porcelain` shows ONLY `tests/helpers.sh`, `tests/run.sh`,
      `tests/test_self.sh` added (?? tests/...).

### Feature Validation

- [ ] **helpers.sh** defines exactly `fail`/`pass`/`assert_eq`/`assert_contains`/
      `setup_test`/`teardown_test` + the `TEST_STATUS` global; sourcing is silent +
      side-effect-free.
- [ ] **run.sh** sources setup_socket.sh + helpers.sh + every test_*.sh (nullglob);
      discovers test_* via `compgen -A function | grep '^test_'`; runs each in the
      CURRENT shell with a per-test fresh socket; prints PASS/FAIL + summary; exits
      0/1.
- [ ] **Per-test isolation (FINDING 5):** each test gets a fresh isolated socket
      (setup_test → test → teardown_test); tests do not interfere.
- [ ] **§5 self-test:** test_true passes; test_false fails (gated); exit code
      reflects the aggregate in both modes.
- [ ] **Non-pollution (PRD §15):** `/usr/bin/tmux list-sessions` byte-identical
      before/after a full `run.sh` invocation.

### Code Quality Validation

- [ ] Mirrors `scripts/utils.sh` + `tests/setup_socket.sh` sourced-library style
      (CONTRACT line, set -u, local, tabs, CURRENT_DIR, shellcheck disable header,
      no side effects on source).
- [ ] File placement matches the desired tree; `helpers.sh`/`run.sh`/`test_self.sh`
      under `tests/`.
- [ ] `setup_test`/`teardown_test` are THIN delegates (no re-implementation of
      socket/path/shim/fixture logic; no edit to setup_socket.sh).
- [ ] `assert_contains` uses quoted-`$sub` `case` (literal match; no subprocess;
      no glob-special hazard).
- [ ] Anti-patterns avoided (check against Anti-Patterns section).

### Documentation & Deployment

- [ ] Code is self-documenting (inline comments cite the findings: FINDING 1/2/5/7;
      the resurrect borrow-vs-reject rationale; the per-test-fresh-socket decision).
- [ ] DOCS: Mode A — none (test infra). No README/CHANGELOG changes for this task
      (P1.M8 owns README/CHANGELOG).
- [ ] No new environment variables beyond the documented `TEST_STATUS` (helpers.sh
      local) + the opt-in `LIVEPICKER_NEGATIVE_SELF_TEST` (test_self.sh gate). No
      vars are ever written to the real server.

---

## Anti-Patterns to Avoid

- ❌ **Don't re-implement socket/path/shim/fixture logic in helpers.sh.** That is
  `setup_socket.sh`'s job (T1.S1, COMPLETE). `setup_test`/`teardown_test` are THIN
  delegates (`setup_socket "$1"` / `teardown_socket`). Do NOT edit `setup_socket.sh`
  (FINDING 2).
- ❌ **Don't run tests in a subshell.** `fail`'s `TEST_STATUS=fail` would not
  propagate to `run.sh`. Run `"$t"` in the CURRENT shell (FINDING 7). The CONTRACT
  for test authors: never `exit` inside a test (it would kill the runner) — signal
  failure ONLY via `fail`/`assert_*`.
- ❌ **Don't use `set -e` / `set -o pipefail`.** House style is `set -u` only
  (system_context §9); `fail`/assertions/`tmux has-session`/`show-option`
  legitimately return nonzero, and the runner must keep going after a failed
  assertion to report per-test PASS/FAIL.
- ❌ **Don't check `$?` after `"$t"` as the pass signal.** A test may legitimately
  end on a nonzero tmux command. `TEST_STATUS` is the ONLY pass/fail signal (reset
  to "pass" before each test; set to "fail" by `fail`/`assert_*`). (FINDING 7.)
- ❌ **Don't use a shared socket + invented per-test reset helpers (reading A).**
  It forces inventing helpers the contract doesn't name AND re-implements
  `restore.sh` to undo an activated picker — fragile, flaky. Use per-test FRESH
  socket (reading B — FINDING 5): `setup_test "lp-$$-<name>"` per test.
- ❌ **Don't borrow resurrect's `teardown_helper`.** It does a REAL `tmux
  kill-server` + `rm -rf ~/.tmux/` — the OPPOSITE of socket-isolated; it nukes the
  user's live 15-session server. Borrow ONLY `TEST_STATUS`/`fail`/`compgen`
  discovery (FINDING 1). Our `teardown_test` delegates to `teardown_socket` (kills
  ONLY the isolated `-L` socket).
- ❌ **Don't make `test_false` unconditionally fail.** That leaves the default
  `bash tests/run.sh` permanently red. Gate it under `LIVEPICKER_NEGATIVE_SELF_TEST=1`
  so the default run is green and the negative path is opt-in (FINDING 8).
- ❌ **Don't use `[[ "$str" == *"$sub"* ]]` or `echo "$str" | grep` for
  `assert_contains`.** The `[[` form treats `$sub` as a glob pattern (a sub of
  `*`/`?` mis-matches); the `grep` form spawns a subprocess + risks a `pipefail`
  hazard. Use the quoted-`$sub` `case` (literal match, no subprocess — FINDING 3).
- ❌ **Don't leave the `nullglob` shopt set after the source loop.** Restore with
  `shopt -u nullglob` (or scope the loop in a subshell) so later globs in `run.sh`
  (or anything it sources) aren't surprised (FINDING 7).
- ❌ **Don't edit `tests/setup_socket.sh`, any `scripts/*`, `PRD.md`, `tasks.json`,
  `prd_snapshot.md`, or `.gitignore`.** This task ADDS exactly three files:
  `tests/helpers.sh`, `tests/run.sh`, `tests/test_self.sh`.

---

## Confidence Score

**9/10** for one-pass implementation success.

This is greenfield test infrastructure (three NEW files under `tests/`, zero edits
to existing code). The entire mechanism is **empirically verified**: the resurrect
idiom was read verbatim from the sibling source (`TEST_STATUS`/`fail`/`compgen`
discovery — FINDING 1); the INPUT dependency `tests/setup_socket.sh` was read in
FULL (its interface is the exact contract `setup_test`/`teardown_test` delegate to
— FINDING 2); the per-test fresh-socket cycle was PROBED live (a `setup_socket` →
test → `teardown_socket` loop sees exactly the fixtures each time, leaves the
server dead + the socket file gone, and never touches the real server — FINDING 6);
and the in-house assert shape (`ok`/`bad`/`assert`) is already battle-tested by the
P1.M6 throwaway mocks. The ready-to-paste snippets (helpers.sh, run.sh, test_self.sh
in full) leave no ambiguity, and the three non-obvious traps are each called out
with the exact fix: **FINDING 2** (delegate, don't re-implement setup_socket),
**FINDING 5** (per-test fresh socket — the "runs setup_test once" reconciliation),
and **FINDING 7** (run tests in the CURRENT shell so TEST_STATUS propagates;
nullglob + set -u safety). The §5 self-test is a deterministic, self-contained
validation gate (`bash tests/run.sh` → exit 0; `LIVEPICKER_NEGATIVE_SELF_TEST=1
bash tests/run.sh` → exit 1) that proves both the pass and fail paths. The only
residual risk (-1) is the judgment call in FINDING 5 (per-test fresh socket vs the
literal "once" reading) — but the decision is robust, contract-faithful (uses only
the named helpers), and fully documented with rationale + the alternative rejected,
so a reviewer can follow the reasoning even if they'd choose otherwise. The
parallel-execution dependency on P1.M7.T1.S1 is satisfied: `setup_socket.sh` is
already implemented and read in full; this task composes cleanly on top of it.
