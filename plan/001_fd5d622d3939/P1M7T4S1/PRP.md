# PRP — P1.M7.T4.S1: `tests/test_preview.sh`

---

## Goal

**Feature Goal**: **CREATE** the PRD §15.19 *Live all-panes preview* validation
test suite — `tests/test_preview.sh` — a single **sourced** bash file that defines
one local helper (`lp_preview_seed_state`) + four `test_*` functions
(`test_multipane_preview`, `test_navigate_unlinks_intact`, `test_self_session_no_link`,
`test_capture_fallback`) which drive the COMPLETE real `scripts/preview.sh`
(P1.M3.T1.S1+S2, COMPLETE) **directly** (contract §1: `preview.sh S`; NOT via
keypress, NOT via `livepicker.sh` activate) against the **socket-isolated** tmux
server provided by the COMPLETE harness (`tests/setup_socket.sh` P1.M7.T1.S1 +
`tests/helpers.sh` P1.M7.T2.S1), and **assert observable tmux state**. Each test
gets a fresh isolated server (run.sh's per-test `setup_test`/`teardown_test` cycle),
seeds the minimal `@livepicker-*` state `preview.sh` reads, exercises one PRD §15.19
bullet (plus a §7 Fallbacks probe), and signals pass/fail via `fail`/`assert_*`
(which set `TEST_STATUS`). `bash tests/run.sh` discovers and runs them and exits 0/1.

**Deliverable** (ONE new file): `tests/test_preview.sh` — a SOURCED bash library
defining exactly these four `test_*` functions (discovered by run.sh's
`compgen -A function | grep '^test_'`) + the `lp_preview_seed_state` helper. It
SOURCES NOTHING (run.sh sources `setup_socket.sh` + `helpers.sh` + `test_*.sh`
first; the assert helpers, `$LIVEPICKER_SCRIPTS`, `TEST_DRIVER_SESSION`, and the
isolated bare-`tmux` shim are all in scope before any `test_*` runs). No side
effects on source (defines functions only).

**Success Definition**:
- `bash -n` + `shellcheck` pass on `tests/test_preview.sh` (0 findings beyond a
  file-level `# shellcheck disable=SC2154,SC2016,SC2034,SC2086`; tabs only;
  `set -u` inherited — NOT re-declared, mirror `test_self.sh`).
- `bash tests/run.sh` runs all four `test_*` (plus T2.S1's `test_self` + T3.S1's
  five `test_*`), each prints **PASS**, the suite summary is `N passed, 0 failed`,
  exit **0**.
- Each `test_*` seeds the minimal `preview.sh` state, drives the REAL
  `$LIVEPICKER_SCRIPTS/preview.sh` against the isolated socket (bare `tmux`),
  and asserts the exact PRD §15.19 observable signals (linked window present in
  BOTH driver+source; all panes visible; navigate-away unlinks from driver but
  source intact; self-session no-link; capture fallback rc=0 + no link).
- **The real user server is provably untouched**: `/usr/bin/tmux list-sessions`
  is byte-identical before/after a full `run.sh` invocation (the harness owns
  isolation; this task never touches `/usr/bin/tmux`).
- `git diff --stat` shows ONLY `tests/test_preview.sh` added (NO edits to
  `setup_socket.sh`/`helpers.sh`/`run.sh`, NO `scripts/*`, NO PRD/tasks —
  FORBIDDEN).

## User Persona (if applicable)

**Target User**: the contributor running the suite (`bash tests/run.sh`) and the
future maintainer extending the preview checks. The test file has no end-user
surface (DOCS: Mode A — none; it is test infra).

**Use Case**: a contributor runs `bash tests/run.sh`; run.sh gives each `test_*`
function a fresh isolated socket, the function seeds preview state, creates any
extra fixtures, calls `preview.sh <S>` directly, and asserts link/unlink/select
state; run.sh reports PASS/FAIL + exits 0/1. Each test is hermetic (per-test fresh
server) so a link mutation in one cannot leak into another.

**User Journey** (per test): `setup_test` (run.sh) → `lp_preview_seed_state` →
(optional extra fixtures, e.g. a 3-pane `multi` session) → `preview.sh <S>` →
`tmux list-windows`/`list-panes`/`show-option` → `assert_*`/`fail` → (control
returns to run.sh) → `teardown_test`.

**Pain Points Addressed**:
- (a) **No preview-semantics tests existed.** T3.S1 covers the nav→preview→linked-id
  INTEGRATION path; this task owns the link-window/unlink-window SEMANTICS cluster
  (§15.19: multi-pane visibility, unlink-keeps-source, self-no-link) + the §7
  capture-pane fallback probe — each a direct `preview.sh` call.
- (b) **The contract's fallback trigger is empirically invalid.** "preview a session
  whose active window is already linked singly" does NOT fail `link-window` on
  tmux 3.6b — it silently DUPLICATES (rc=0). This PRP specifies the TWO correct
  deterministic triggers (snapshot-mode gate + bogus-driver link failure) — FINDING 7/8.
- (c) **`preview.sh` needs no client.** Unlike T3.S1 (whose `livepicker.sh` activate
  uses `display-message -p`), `preview.sh` reads the driver name from
  `@livepicker-orig-session` — so no `attach_test_client` (no pty timing flakiness).

## Why

- **PRD §15.19 Live all-panes preview** is the controlling spec (selected
  `h2.15/h3.19`): its three bullets map to the first three `test_*` functions; the
  fourth (`test_capture_fallback`) probes PRD §7 Fallbacks (selected `h2.7`). §13
  tmux primitives reference (selected `h2.13`) enumerates `link-window -a`,
  `unlink-window`, `select-window`, `capture-pane -ep -t "=$S:."` — the exact
  primitives each assertion inspects. §16 risks (selected `h2.16`) flags the
  link-window edge cases this suite pins down.
- **Scope cohesion.** T4.S1 is the Preview cluster of module P1.M7 (Validation).
  T1.S1 owns socket isolation (COMPLETE); T2.S1 owns assertions + discovery + the
  runner (COMPLETE); T3.S1 owns the Functional test bodies (in-flight, its PRP is
  the contract). T4.S1 owns the PREVIEW test bodies (this file). T5/T6 (pollution/
  restore/keyrepurpose/create) are SIBLING test files — each a separate `test_*.sh`,
  each hermetic via run.sh's per-test cycle. This task does NOT own those clusters
  or the harness.
- **T3.S1's `test_nav_moves_selection`** already asserts the nav→preview→linked-id
  integration (next-session → linked-id == target's window id). T4.S1 does NOT
  duplicate that; it focuses on what the INTEGRATION test does NOT cover: that the
  linked window shows ALL panes (§15.19 b1), that navigating away preserves the
  source's window (§15.19 b2), that self-session never links (§15.19 b3), and that
  the capture-pane fallback runs cleanly (§7). These are `preview.sh` UNIT concerns.

## What

**CREATE** the single file `tests/test_preview.sh`. No other file is touched
(`setup_socket.sh`/`helpers.sh`/`run.sh` are owned by T1.S1/T2.S1 — COMPLETE,
READ-ONLY here; `scripts/*` are COMPLETE/IMMUTABLE — driven, never edited;
PRD/tasks/prd_snapshot are READ-ONLY). The file is **SOURCED** by `run.sh` (defines
`test_*` + `lp_preview_seed_state` only; NO side effects on source; NO top-level
execution; NO `setup_test`/`teardown_test` calls — run.sh owns the per-test cycle).

### Success Criteria

- [ ] `tests/test_preview.sh` passes `bash -n` + `shellcheck` (file-level
      `disable` for SC2154/SC2016/SC2034/SC2086 at most); tabs only; `set -u`
      inherited (NOT re-declared).
- [ ] Defines EXACTLY four `test_*` functions + `lp_preview_seed_state`. No other
      top-level code. NO `attach_test_client` (preview.sh is client-independent — FINDING 1).
- [ ] Each `test_*` seeds the minimal `preview.sh` state via `lp_preview_seed_state`
      (or the fallback variant) and drives the real `$LIVEPICKER_SCRIPTS/preview.sh`
      directly; signals failure ONLY via `fail`/`assert_*` (NEVER `exit`).
- [ ] `bash tests/run.sh` prints `PASS` for all four (+ the T2.S1/T3.S1 tests),
      summary `N passed, 0 failed`, exit 0.
- [ ] `/usr/bin/tmux list-sessions` byte-identical before/after a full run.
- [ ] `git diff --stat` shows ONLY `tests/test_preview.sh` added.

## All Needed Context

### Context Completeness Check

_Pass_: a developer who has never seen this repo can implement T4.S1 from
(a) the four ready-to-paste test bodies in "Implementation Patterns & Key
Details"; (b) the 12 findings in `research/preview_test_findings.md` — most
critically **FINDING 1** (preview.sh is client-independent → NO attach_test_client),
**FINDING 2** (the minimal state seed → `lp_preview_seed_state`), **FINDING 3**
(dynamic window ids), **FINDING 7** (link-window NEVER fails on duplicate — the
contract's trigger is INVALID), and **FINDING 8** (the TWO correct fallback
triggers); and (c) the live probes that confirmed every link/unlink/select
assertion target on the isolated socket. The INPUTS are the COMPLETE harness
(`tests/setup_socket.sh` + `tests/helpers.sh`, read in full) and the COMPLETE
`scripts/preview.sh` (read in full).

### Documentation & References

```yaml
# MUST READ — the empirical + idiomatic ground-truth for THIS task (12 findings + PROBES).
- docfile: plan/001_fd5d622d3939/P1M7T4S1/research/preview_test_findings.md
  why: FINDING 1 (preview.sh is CLIENT-INDEPENDENT -> NO attach_test_client); FINDING 2
        (the 3 keys preview.sh reads + the lp_preview_seed_state helper); FINDING 3
        (window ids are GLOBAL -> read DYNAMICALLY); FINDING 4 (multi-pane link shows
        ALL panes; pane-count assertion); FINDING 5 (navigate-away unlinks from driver,
        source KEEPS its window; before/after diff); FINDING 6 (self-session no-link);
        FINDING 7 (link-window NEVER fails on duplicate -> the contract's trigger is
        INVALID); FINDING 8 (the TWO correct deterministic fallback triggers); FINDING 9
        (capture-pane target is =$S:.); FINDING 10 (house style); FINDING 11 (snapshot
        state-inheritance trap); FINDING 12 (confidence).
  critical: Read BEFORE writing. FINDING 7/8 are the single non-obvious correctness
        issues — the work-item's literal "already-linked-singly" trigger CANNOT reach
        the fallback on tmux 3.6b; use snapshot-mode + bogus-driver instead.

# MUST READ — the harness contract this task CONSUMES (read in full; COMPLETE).
- file: tests/setup_socket.sh
  why: the isolation layer. setup_socket seeds driver/alpha/beta + driver:extra
        multi-pane window + a split pane in beta. Exports TEST_SOCKET/TMUX_*/REAL_TMUX/
        LIVEPICKER_ROOT/LIVEPICKER_SCRIPTS/TEST_DRIVER_SESSION("driver")/
        TEST_FIXTURE_SESSIONS("alpha beta"). SOURCED library (no side effects on
        source). Mirror its header STYLE (CONTRACT line, set -u, tabs, local,
        shellcheck disable). DO NOT EDIT IT.
  pattern: run.sh's setup_test calls setup_socket per test (fresh -L socket + PATH
        shim -> bare `tmux` hits ONLY the isolated socket).
  gotcha: window ids are GLOBAL — the seed consumes @0(driver),@1(alpha),@2(beta),
        @3(driver:extra); a test-created session's window is @4+. NEVER hardcode.

# MUST READ — the assertion + per-test helpers this task CONSUMES (COMPLETE).
- file: tests/helpers.sh
  why: provides fail/pass/assert_eq/assert_contains + setup_test/teardown_test
        (THIN delegates to setup_socket) + the TEST_STATUS global. assert_contains is
        POSITIVE only (for window-id membership in a list-windows dump). In scope
        because run.sh sources helpers.sh before test_*.sh. DO NOT EDIT IT.
  pattern: assert_eq a b msg -> [ "$a" = "$b" ] else fail; assert_contains str sub msg
        -> case "$str" in *"$sub"*) … ;; (literal substring, quoted -> glob-safe).

# MUST READ — the runner (T2.S1; the file is COMPLETE).
- file: tests/run.sh
  why: run.sh sources setup_socket.sh + helpers.sh + every tests/test_*.sh, then
        PER test: setup_test "lp-$$-<name>" (-> fresh isolated socket + PATH shim +
        baseline fixtures driver/alpha/beta) -> resets TEST_STATUS=pass -> runs the
        test_* in the CURRENT shell -> reads TEST_STATUS -> PASS/FAIL -> teardown_test.
        The CONTRACT for test bodies: define test_* ONLY (no side effects on source);
        signal failure ONLY via fail/assert_* (NEVER exit — run.sh reads TEST_STATUS in
        the current shell; a bare exit kills the runner). nullglob globs test_*.sh ->
        this file is picked up automatically once it exists.
  critical: the test function runs AFTER setup_test (so $LIVEPICKER_SCRIPTS + the shim
        are live) and in the SAME shell as helpers.sh (so assert_* is in scope).
        test_preview.sh SOURCES NOTHING and calls NO setup_test/teardown_test.

# MUST READ — the sibling functional-test PRP (the CONTRACT for style + the integration
# coverage that this task must NOT duplicate).
- docfile: plan/001_fd5d622d3939/P1M7T3S1/PRP.md
  why: T3.S1's test_nav_moves_selection ALREADY covers the nav->preview->linked-id
        integration (activate -> next-session -> assert @livepicker-linked-id == the
        target's live window id). T4.S1 does NOT repeat that; it owns the
        link-window/unlink-window SEMANTICS + the fallback. Mirror T3.S1's header
        style, the lp_*-helper idiom, the inline-`case` for negative substring, and
        the dynamic-window-id reads.
  critical: do NOT re-test nav->linked-id here. The four T4.S1 tests call preview.sh
        DIRECTLY (unit scope), not via livepicker.sh/input-handler.sh.

# MUST READ — the script this task DRIVES (COMPLETE P1.M3.T1.S1+S2; read in full).
- file: scripts/preview.sh
  why: the live-preview core. argv[1] = candidate session S. Reads current_session
        from @livepicker-orig-session (CLIENT-INDEPENDENT), orig_window from
        @livepicker-orig-window, linked_id from @livepicker-linked-id, mode from
        opt_preview_mode (live|snapshot|off; default live). Flow: off->noop;
        snapshot->preview_fallback; self-session(S==current)->unlink prior + clear
        linked_id + select orig_window; else read src_id (S's active window), dup-guard
        (linked_id==src_id -> just select), unlink prior from current_session, link
        src_id into current_session (on FAIL -> preview_fallback), select src_id, set
        linked_id=src_id.
  gotcha: preview.sh does NOT use display-message -> needs NO attached client.
        link-window NEVER fails on a duplicate (rc=0, duplicates) -> the dup-guard
        prevents it; the ONLY deterministic link-failure is a bogus current_session.
- file: scripts/preview.sh (preview_fallback)
  why: the capture-pane snapshot fallback. `tmux capture-pane -ep -t "=$1:."` (the
        `:.` active-pane target — bare `=$S` FAILS rc=1 on 3.6b). Returns capture's rc
        (0 = captured). Reached via (a) snapshot mode gate, or (b) a failed link-window.
- file: scripts/state.sh
  why: the STATE_*/ORIG_* constants. preview.sh reads ORIG_SESSION
        ("@livepicker-orig-session"), ORIG_WINDOW ("@livepicker-orig-window"),
        STATE_LINKED_ID ("@livepicker-linked-id"). lp_preview_seed_state uses the
        LITERAL key strings (stable contract constants) — NO sourcing (mirror T3.S1's
        lp_runtime_cleared).
- file: scripts/options.sh
  why: opt_preview_mode() reads @livepicker-preview-mode (default "live"). The
        snapshot-gate trigger sets this to "snapshot"; reset to "live" after.

# MUST READ — the architecture ground-truth.
- docfile: plan/001_fd5d622d3939/architecture/system_context.md
  why: §3 INVARIANT A (select-window/link/unlink NEVER fire client-session-changed);
        §9 shell style (set -u ONLY; tabs; local; quote everything; NO pipefail).
  section: "§3 INVARIANT A", "§9 Shell style".

# MUST READ — the PRD sections selected for this work item.
- docfile: PRD.md
  why: §15.19 Live all-panes preview (3 bullets -> test_multipane_preview /
        test_navigate_unlinks_intact / test_self_session_no_link); §7 Fallbacks (the
        capture-pane path -> test_capture_fallback); §13 tmux primitives reference
        (link-window -a / unlink-window / select-window / capture-pane -ep -t "=$S:.");
        §16 risks (link-window edge cases + the tmux 3.0 floor).
```

### Current Codebase tree

```bash
tmux-livepicker/
  PRD.md                                # READ-ONLY (FORBIDDEN to edit).
  plugin.tmux                           # COMPLETE. Unchanged.
  scripts/                              # ALL COMPLETE (P1.M1-M6). IMMUTABLE — this task DRIVES preview.sh, never edits.
    options.sh utils.sh state.sh filter.sh renderer.sh preview.sh
    livepicker.sh restore.sh input-handler.sh
  tests/
    setup_socket.sh   # COMPLETE (P1.M7.T1.S1). READ-ONLY. The isolation + exports.
    helpers.sh        # COMPLETE (P1.M7.T2.S1). READ-ONLY. fail/pass/assert_* + setup_test/teardown_test.
    run.sh            # COMPLETE (P1.M7.T2.S1). READ-ONLY. The runner; sources the 3 files + discovers test_*.
    test_self.sh      # COMPLETE (P1.M7.T2.S1). Sibling test_*.sh.
    # test_functional.sh lands via T3.S1 (in-flight). Sibling test_*.sh.
  plan/001_fd5d622d3939/{architecture/*.md, tasks.json, prd_snapshot.md, prd_index.txt}
  plan/001_fd5d622d3939/P1M7T4S1/{PRP.md, research/preview_test_findings.md}   # THIS
  .gitignore
  # NOTE: tests/test_preview.sh does NOT exist yet — THIS task creates it.
```

### Desired Codebase tree with files to be added and responsibility of file

```bash
tmux-livepicker/
  tests/
    test_preview.sh   # NEW (this task). SOURCED by run.sh (defines test_* + lp_preview_seed_state
                      #   only; NO side effects on source). Drives the REAL preview.sh DIRECTLY
                      #   against the isolated socket; seeds minimal @livepicker-* state; asserts
                      #   PRD §15.19 + §7 Fallbacks observable state. NO attach_test_client.
                      #   lp_preview_seed_state() : set @livepicker-orig-session=driver,
                      #                            @livepicker-orig-window=driver's ACTIVE window
                      #                            id (read DYNAMICALLY), @livepicker-linked-id="".
                      #   test_multipane_preview       : 3-pane session S; preview.sh S; assert the
                      #                                 linked window id is in BOTH driver + S; assert
                      #                                 driver's current window == S's active window;
                      #                                 assert the linked window's pane count == 3.
                      #   test_navigate_unlinks_intact : preview S (linked) then preview S2; assert
                      #                                 S's window NO LONGER in driver but STILL in S
                      #                                 (list-windows before/after diff).
                      #   test_self_session_no_link    : preview the driver's own session; assert
                      #                                 @livepicker-linked-id stays empty; driver's
                      #                                 current window == orig; NO duplicate window.
                      #   test_capture_fallback        : (a) @livepicker-preview-mode=snapshot ->
                      #                                 capture-pane, rc 0, no link; (b) bogus
                      #                                 @livepicker-orig-session -> link-window FAILS
                      #                                 -> capture-pane, rc 0, no link.
```

### Known Gotchas of our codebase & Library Quirks

```bash
# CRITICAL (research FINDING 1 — preview.sh is CLIENT-INDEPENDENT): preview.sh reads
#   the driver session name from @livepicker-orig-session (get_state), NOT display-message.
#   It uses only link-window/unlink-window/select-window/list-windows/capture-pane/
#   set-option — NONE require an attached client. CONSEQUENCE: test_preview.sh calls NO
#   attach_test_client (unlike T3.S1, whose livepicker.sh activate uses display-message
#   STEP 2). Verified: every probe ran detached with all rc=0.

# CRITICAL (research FINDING 2 — the minimal state seed): preview.sh reads EXACTLY 3 keys
#   at the top: @livepicker-orig-session (driver), @livepicker-orig-window (self-session
#   select), @livepicker-linked-id (prior link) + opt_preview_mode (default live). Seed
#   them via bare `tmux set-option -g` in lp_preview_seed_state. It does NOT read
#   @livepicker-mode/list/filter/index, status, or key-table -> no full activate needed.

# CRITICAL (research FINDING 3 — window ids are GLOBAL, read DYNAMICALLY): window ids
#   (@0,@1,…) are server-global + incremental; the baseline seed already consumes
#   @0(driver)+@3(driver:extra)+@1(alpha)+@2(beta); a new session "multi" is @4 (panes
#   %7 %8 %9). NEVER hardcode them. Read live: `tmux list-windows -t =multi -F
#   '#{window_id}' -f '#{window_active}'`. After preview.sh multi, @livepicker-linked-id
#   == that id AND driver's current active window == that id.

# CRITICAL (research FINDING 7 — the contract's fallback trigger is INVALID): the work-
#   item's literal "preview a session whose active window is already linked singly" does
#   NOT fail link-window on tmux 3.6b — it silently DUPLICATES (rc=0, verified). preview.sh's
#   duplicate-guard (linked_id==src_id -> skip) prevents this in normal flow, but the raw
#   primitive never fails this way. DO NOT use that trigger. Use FINDING 8's two triggers.

# CRITICAL (research FINDING 8 — the TWO deterministic fallback triggers): (a) set
#   @livepicker-preview-mode=snapshot -> preview.sh's snapshot gate -> preview_fallback
#   (capture-pane), rc=0, no link (RESET to live after); (b) seed @livepicker-orig-session
#   to a NON-EXISTENT name -> `link-window -t "no-such:"` FAILS rc=1 ("can't find session")
#   -> the REAL link-failure branch -> preview_fallback. Both run capture-pane on a REAL
#   candidate -> capture SUCCEEDS (rc=0). test_capture_fallback exercises BOTH.

# GOTCHA (research FINDING 9 — capture-pane target): preview_fallback captures
#   `capture-pane -ep -t "=$S:."` (the :. active-pane target). The bare =$S form FAILS
#   rc=1 on 3.6b. preview.sh already does this correctly — the tests only DRIVE it.

# GOTCHA (research FINDING 11 — snapshot state-inheritance): switching to snapshot mode
#   does NOT clear a prior linked-id (snapshot returns before state mutation). So within
#   test_capture_fallback, re-seed @livepicker-linked-id="" before each sub-assertion.

# GOTCHA (pane-count assertion): use mapfile (NO pipe — house style forbids pipefail):
#   `mapfile -t _panes < <(tmux list-panes -t "$wid" -F '#{pane_id}')` then
#   `${#_panes[@]}`. A linked window is the SAME object in both sessions, so listing its
#   panes by id shows ALL of them regardless of which session you query through.

# GOTCHA (window-id membership in a session): use assert_contains on the list-windows
#   dump: `assert_contains "$(tmux list-windows -t =driver -F '#{window_id}')" "$wid" msg`.
#   For ABSENCE ("no longer in driver"), use an inline `case "$(tmux list-windows …)" in
#   *"$wid"*) fail … ;; esac` (assert_contains is POSITIVE only — mirror T3.S1 FINDING 9).

# STYLE (research FINDING 10 / system_context §9): shebang #!/usr/bin/env bash;
#   `set -u` INHERITED (helpers.sh/run.sh declare it) — do NOT re-declare (mirror
#   test_self.sh: "`# set -u is inherited`"); local for ALL function locals; TABS;
#   quote everything. Signal failure ONLY via fail/assert_* (NEVER exit — run.sh reads
#   TEST_STATUS in the CURRENT shell; a bare exit kills the runner). The file is SOURCED
#   by run.sh: define test_* + lp_preview_seed_state ONLY; NO side effects on source; NO
#   setup_test/teardown_test calls (run.sh owns the per-test cycle).

# GOTCHA: do NOT edit tests/setup_socket.sh, tests/helpers.sh, tests/run.sh, any
#   scripts/* file, PRD.md, tasks.json, prd_snapshot.md, or .gitignore (FORBIDDEN).
#   This task ADDS exactly ONE file: tests/test_preview.sh.
```

## Implementation Blueprint

### Data models and structure

No data model. The "model" is the **test-body contract** between run.sh and
`test_preview.sh`:

```bash
# The shared surface IN SCOPE when each test_* runs (provided by run.sh's sources
# + setup_test — test_preview.sh SOURCES NOTHING):
#   bare `tmux`              -> the PATH shim -> isolated -L socket (transparent).
#   $LIVEPICKER_SCRIPTS      -> repo scripts/ (exported by setup_socket).
#   $TEST_DRIVER_SESSION     -> "driver" (the preview-link target / self-session).
#   fail/pass/assert_eq/assert_contains + TEST_STATUS -> from helpers.sh.
#
# The CONTRACT for each test_* body:
#   - seed the minimal preview.sh state via lp_preview_seed_state (NO attach_test_client).
#   - add any extra fixtures (e.g. a 3-pane session) BEFORE preview.sh.
#   - drive the REAL $LIVEPICKER_SCRIPTS/preview.sh DIRECTLY (argv[1] = S).
#   - read window ids DYNAMICALLY (global ids — FINDING 3).
#   - assert observable state via assert_*/fail (NEVER exit).
#   - run.sh wraps you in setup_test -> test -> teardown_test; do NOT call those.
```

### Implementation Tasks (ordered by dependencies)

```yaml
Task 1: CREATE tests/test_preview.sh — header + lp_preview_seed_state helper
  - CREATE: tests/test_preview.sh (NEW; SOURCED by run.sh — NEVER executed directly;
        no self-test guard; no BASH_SOURCE/$0 check).
  - HEADER: #!/usr/bin/env bash ; a CONTRACT comment ("sourced by run.sh; defines test_*
        + lp_preview_seed_state only; NO side effects on source; NO setup_test/
        teardown_test calls — run.sh owns the per-test cycle; preview.sh is CLIENT-
        INDEPENDENT so NO attach_test_client; the assert helpers, $LIVEPICKER_SCRIPTS,
        $TEST_DRIVER_SESSION come from run.sh's sources"); `# set -u is inherited`
        (do NOT re-declare; mirror test_self.sh); file-level
        `# shellcheck disable=SC2154,SC2016,SC2034,SC2086` (SC2154: assert_*/fail/
        $LIVEPICKER_SCRIPTS/$TEST_DRIVER_SESSION are defined by run.sh's sources, not here).
  - IMPLEMENT: `lp_preview_seed_state` (local helper; FINDING 2). Reads the driver's
        ACTIVE window id DYNAMICALLY (`tmux list-windows -t "=$TEST_DRIVER_SESSION" -F
        '#{window_id}' -f '#{window_active}'`), then sets the 3 keys preview.sh reads:
        @livepicker-orig-session="$TEST_DRIVER_SESSION", @livepicker-orig-window="$drv_win",
        @livepicker-linked-id="". Uses the LITERAL key strings (stable state.sh contract
        constants — NO sourcing). local drv_win. This is the ONLY setup each test needs.
  - FOLLOW pattern: tests/test_self.sh (sourced-by-run.sh file; no side effects;
        inherited set -u; shellcheck disable header) + T3.S1's lp_runtime_cleared (literal
        key strings, local, no sourcing).
  - DO NOT: source anything; call setup_test/teardown_test; attach a client; re-declare
        set -e/pipefail.

Task 2: test_multipane_preview (PRD §15.19 bullet 1)
  - IMPLEMENT: lp_preview_seed_state; create a 3-pane candidate session S: `tmux
        new-session -d -s multi -x 120 -y 40` + `tmux split-window -h -t multi` + `tmux
        split-window -v -t multi`; read DYNAMICALLY `multi_wid="$(tmux list-windows -t
        '=multi' -F '#{window_id}' -f '#{window_active}')"` (FINDING 3); run
        `"$LIVEPICKER_SCRIPTS/preview.sh" multi`; then:
          (a) assert_contains "$(tmux list-windows -t '=$TEST_DRIVER_SESSION' -F
              '#{window_id}')" "$multi_wid" "linked window present in the driver session";
          (b) assert_contains "$(tmux list-windows -t '=multi' -F '#{window_id}')" "$multi_wid"
              "source session KEEPS its window (link is shared, not moved)";
          (c) assert_eq "$(tmux list-windows -t '=$TEST_DRIVER_SESSION' -F '#{window_id}' -f
              '#{window_active}')" "$multi_wid" "driver's current window is multi's (all panes)";
          (d) `mapfile -t _panes < <(tmux list-panes -t "$multi_wid" -F '#{pane_id}')`;
              assert_eq "${#_panes[@]}" "3" "linked window shows all 3 panes live";
          (e) assert_eq "$(tmux show-option -gqv @livepicker-linked-id)" "$multi_wid"
              "@livepicker-linked-id tracks the linked window id".
  - WHY: a linked window is the SAME object (same id) in both sessions -> all panes
        render live; unlink never happened so source keeps it (FINDING 4).
  - DO NOT: hardcode @4 (global ids); use a pipe for the pane count (use mapfile).

Task 3: test_navigate_unlinks_intact (PRD §15.19 bullet 2)
  - IMPLEMENT: lp_preview_seed_state; create `multi` (2-pane suffices, or reuse a 3-pane)
        + a second candidate (use the baseline `alpha`); read `multi_wid` DYNAMICALLY;
        run `preview.sh multi` (links multi into driver); capture the BEFORE state of
        BOTH `multi_before="$(tmux list-windows -t '=multi' -F '#{window_id}')"` and
        `driver_before="$(tmux list-windows -t '=$TEST_DRIVER_SESSION' -F '#{window_id}')"`
        ; run `preview.sh alpha` (navigate away -> unlink multi from driver, link alpha);
        then:
          (a) NEGATIVE: `case "$(tmux list-windows -t '=$TEST_DRIVER_SESSION' -F '#{window_id}')"
              in *"$multi_wid"*) fail "multi's window still linked in driver after navigating
              away" ;; esac` (inline case — assert_contains is positive only);
          (b) assert_eq "$(tmux list-windows -t '=multi' -F '#{window_id}')" "$multi_before"
              "multi's window list UNCHANGED (intact in its own session — the before/after diff)";
          (c) assert_eq "$(tmux show-option -gqv @livepicker-linked-id)" "$alpha_wid" "linked-id
              now tracks alpha's window" (read alpha_wid DYNAMICALLY before preview alpha).
  - WHY: unlink-window WITHOUT -k removes ONE link (from driver); source KEEPS its window
        (preview.sh FINDING 1/11). The before/after list-windows diff is the §15.19 b2 proof.
  - DO NOT: assert multi_wid still in driver (it is GONE — that's the point); hardcode ids.

Task 4: test_self_session_no_link (PRD §15.19 bullet 3)
  - IMPLEMENT: lp_preview_seed_state; capture `drv_wid` from the seeded
        @livepicker-orig-window (= driver's active window) + `drv_before="$(tmux
        list-windows -t '=$TEST_DRIVER_SESSION' -F '#{window_id}')"`; run
        `"$LIVEPICKER_SCRIPTS/preview.sh" "$TEST_DRIVER_SESSION"` (preview own session);
        then:
          (a) assert_eq "$(tmux show-option -gqv @livepicker-linked-id)" "" "self-session
              leaves @livepicker-linked-id empty (no link)";
          (b) assert_eq "$(tmux list-windows -t '=$TEST_DRIVER_SESSION' -F '#{window_id}' -f
              '#{window_active}')" "$drv_wid" "self-session selects the ORIGINAL window";
          (c) assert_eq "$(tmux list-windows -t '=$TEST_DRIVER_SESSION' -F '#{window_id}')"
              "$drv_before" "self-session created NO duplicate window (no link-window attempted)".
  - WHY: the self-session guard (S==current_session) clears linked_id + select-window
        ORIG_WINDOW WITHOUT linking (a session cannot link its own window — would create
        an in-session duplicate). The unchanged window list is the "no link attempted" proof.
  - DO NOT: expect a foreign link to appear; expect linked-id to be set.

Task 5: test_capture_fallback (PRD §7 Fallbacks — BOTH deterministic triggers; FINDING 8)
  - IMPLEMENT: lp_preview_seed_state; create a REAL candidate `cand` (2-pane):
        `tmux new-session -d -s cand -x 120 -y 40` + `tmux split-window -h -t cand`.
        --- (a) SNAPSHOT-mode gate ---
        `tmux set-option -g @livepicker-preview-mode snapshot`; re-seed
        @livepicker-linked-id="" (FINDING 11 — snapshot does not clear it); run
        `"$LIVEPICKER_SCRIPTS/preview.sh" cand || fail "snapshot-mode preview returned
        non-zero (capture-pane path errored)"`; assert_eq
        "$(tmux show-option -gqv @livepicker-linked-id)" "" "snapshot mode leaves no link";
        reset `tmux set-option -g @livepicker-preview-mode live`.
        --- (b) LINK-FAILURE branch (the faithful "force a link failure") ---
        seed a NON-EXISTENT driver: `tmux set-option -g @livepicker-orig-session
        "no-such-session-xyz"` + `tmux set-option -g @livepicker-linked-id ""`; run
        `"$LIVEPICKER_SCRIPTS/preview.sh" cand || fail "link-failure preview returned
        non-zero (capture-pane path errored)"`; assert_eq
        "$(tmux show-option -gqv @livepicker-linked-id)" "" "failed link leaves no
        linked-id".
  - WHY: (a) the snapshot gate calls preview_fallback before any link (PRD §7); (b) a
        bogus current_session makes `link-window -t "no-such:"` FAIL rc=1 ("can't find
        session") -> the `if ! tmux link-window …; then preview_fallback` branch fires.
        cand is REAL -> capture-pane succeeds (rc=0). This is the CORRECT deterministic
        trigger (the contract's "already-linked-singly" CANNOT fail — FINDING 7).
  - DO NOT: try to trigger the fallback by re-linking an already-linked window (it
        duplicates, rc=0 — FINDING 7); use a bogus session name for the link-failure
        branch; expect linked-id to be set.

Task 6: VALIDATE (Level 1 lint + Level 2 suite green + Level 4 non-pollution)
  - RUN: bash -n + shellcheck on the file; `bash tests/run.sh` (expect all four PASS +
        test_self + T3.S1's five PASS, exit 0); snapshot `/usr/bin/tmux list-sessions`
        before/after a full run.sh and assert byte-identical (non-pollution);
        `git diff --stat` shows ONLY tests/test_preview.sh added.
```

### Implementation Patterns & Key Details

#### The file skeleton + the seed helper (Task 1)

```bash
#!/usr/bin/env bash
# tests/test_preview.sh — tmux-livepicker PRD §15.19 Live all-panes preview + §7
# Fallbacks validation (P1.M7.T4.S1).
#
# SOURCED by run.sh (NEVER executed directly). Defines four test_* functions that drive
# the COMPLETE real scripts/preview.sh (P1.M3.T1.S1+S2) DIRECTLY (contract §1:
# `preview.sh S`; NOT via keypress, NOT via livepicker.sh) against the socket-isolated
# server the harness provides (tests/setup_socket.sh P1.M7.T1.S1 + tests/helpers.sh
# P1.M7.T2.S1), and assert observable tmux state. Each test seeds the minimal
# @livepicker-* state preview.sh reads, exercises one §15.19 bullet (+ a §7 fallback
# probe), and signals pass/fail via fail/assert_* (which set TEST_STATUS; run.sh reads
# it in the current shell).
#
# CONTRACT: run.sh sources setup_socket.sh + helpers.sh + every tests/test_*.sh, then
# PER test calls setup_test "lp-$$-<name>" (-> fresh isolated socket + PATH shim +
# baseline fixtures driver/alpha/beta) -> resets TEST_STATUS=pass -> runs the test_* in
# the CURRENT shell -> reads TEST_STATUS -> teardown_test. So when a test_* runs: bare
# `tmux` hits the isolated socket; $LIVEPICKER_SCRIPTS, TEST_DRIVER_SESSION, fail/pass/
# assert_eq/assert_contains are all IN SCOPE; this file SOURCES NOTHING and calls NO
# setup_test/teardown_test.
#
# CRITICAL (research FINDING 1): preview.sh is CLIENT-INDEPENDENT — it reads the driver
# session name from @livepicker-orig-session (NOT display-message). So NO
# attach_test_client (unlike T3.S1, whose livepicker.sh activate uses display-message).
#
# CRITICAL (research FINDING 7): the work-item's literal "already-linked-singly" trigger
# CANNOT fail link-window on tmux 3.6b (it duplicates, rc=0). test_capture_fallback uses
# the TWO correct deterministic triggers (FINDING 8: snapshot-mode gate + bogus-driver
# link failure).
#
# `set -u` is INHERITED from helpers.sh (do NOT re-declare; mirror test_self.sh).
# shellcheck disable=SC2154,SC2016,SC2034,SC2086
#   SC2154: assert_*/fail/$LIVEPICKER_SCRIPTS/$TEST_DRIVER_SESSION are defined by run.sh's
#           sources, not in this file.

# lp_preview_seed_state — set the MINIMAL @livepicker-* state preview.sh reads. preview.sh
# is CLIENT-INDEPENDENT (FINDING 1): it reads the driver from @livepicker-orig-session
# (get_state), the self-session window from @livepicker-orig-window, and the prior link
# from @livepicker-linked-id. It does NOT read @livepicker-mode/list/filter/index, status,
# or key-table -> no full activate needed. The literal key strings are stable state.sh
# contract constants (NO sourcing — mirror T3.S1's lp_runtime_cleared).
lp_preview_seed_state() {
	local drv_win
	# The driver's ACTIVE window id, read DYNAMICALLY (window ids are GLOBAL; the
	# baseline seed makes driver's active window the "extra" @N, NOT @0 — FINDING 3).
	drv_win="$(tmux list-windows -t "=$TEST_DRIVER_SESSION" -F '#{window_id}' -f '#{window_active}')"
	tmux set-option -g @livepicker-orig-session "$TEST_DRIVER_SESSION"
	tmux set-option -g @livepicker-orig-window "$drv_win"
	tmux set-option -g @livepicker-linked-id ""
}
```

#### test_multipane_preview (Task 2)

```bash
test_multipane_preview() {
	lp_preview_seed_state
	# A candidate session with a 3-pane active window (PRD §15.19 b1).
	tmux new-session -d -s multi -x 120 -y 40
	tmux split-window -h -t multi
	tmux split-window -v -t multi
	# Window ids are GLOBAL — read the candidate's active window id DYNAMICALLY (FINDING 3).
	local multi_wid
	multi_wid="$(tmux list-windows -t '=multi' -F '#{window_id}' -f '#{window_active}')"
	"$LIVEPICKER_SCRIPTS/preview.sh" multi
	# PRD §15.19 b1: the linked window id appears in BOTH the driver AND the source; all
	# panes render live (a linked window is the SAME object in both sessions).
	assert_contains "$(tmux list-windows -t "=$TEST_DRIVER_SESSION" -F '#{window_id}')" \
		"$multi_wid" "linked window present in the driver session"
	assert_contains "$(tmux list-windows -t '=multi' -F '#{window_id}')" \
		"$multi_wid" "source session keeps its window (link is shared, not moved)"
	assert_eq "$(tmux list-windows -t "=$TEST_DRIVER_SESSION" -F '#{window_id}' -f '#{window_active}')" \
		"$multi_wid" "driver's current window is multi's linked window (all panes visible)"
	# All panes visible: a linked window's panes are queryable by id from either session.
	local _panes
	mapfile -t _panes < <(tmux list-panes -t "$multi_wid" -F '#{pane_id}')
	assert_eq "${#_panes[@]}" "3" "linked window renders all 3 panes live"
	assert_eq "$(tmux show-option -gqv @livepicker-linked-id)" "$multi_wid" \
		"@livepicker-linked-id tracks the linked window id"
}
```

#### test_navigate_unlinks_intact (Task 3)

```bash
test_navigate_unlinks_intact() {
	lp_preview_seed_state
	# Two candidates: a fresh `multi` + the baseline `alpha`.
	tmux new-session -d -s multi -x 120 -y 40
	tmux split-window -h -t multi
	local multi_wid alpha_wid
	multi_wid="$(tmux list-windows -t '=multi' -F '#{window_id}' -f '#{window_active}')"
	# preview multi first (links multi into the driver).
	"$LIVEPICKER_SCRIPTS/preview.sh" multi
	# Capture the BEFORE state of BOTH sessions (the §15.19 b2 before/after diff).
	local multi_before
	multi_before="$(tmux list-windows -t '=multi' -F '#{window_id}')"
	# Navigate away: preview alpha -> unlink multi from the driver, link alpha.
	alpha_wid="$(tmux list-windows -t '=alpha' -F '#{window_id}' -f '#{window_active}')"
	"$LIVEPICKER_SCRIPTS/preview.sh" alpha
	# PRD §15.19 b2: multi's window is NO LONGER in the driver (unlinked)...
	case "$(tmux list-windows -t "=$TEST_DRIVER_SESSION" -F '#{window_id}')" in
		*"$multi_wid"*) fail "multi's window still linked in the driver after navigating away" ;;
	esac
	# ...but multi's window list is UNCHANGED (intact in its own session — unlink without -k
	# removes ONE link; the source keeps its window — preview.sh FINDING 1/11).
	assert_eq "$(tmux list-windows -t '=multi' -F '#{window_id}')" "$multi_before" \
		"multi's window intact in its own session (before/after diff)"
	assert_eq "$(tmux show-option -gqv @livepicker-linked-id)" "$alpha_wid" \
		"@livepicker-linked-id now tracks alpha's window"
}
```

#### test_self_session_no_link (Task 4)

```bash
test_self_session_no_link() {
	lp_preview_seed_state
	# The driver's ORIGINAL active window + its window list (for the "no link attempted" proof).
	local drv_wid drv_before
	drv_wid="$(tmux show-option -gqv @livepicker-orig-window)"
	drv_before="$(tmux list-windows -t "=$TEST_DRIVER_SESSION" -F '#{window_id}')"
	# PRD §15.19 b3: preview the driver's OWN session -> no link (would create an in-session
	# duplicate). preview.sh's self-session guard clears linked_id + select-window ORIG_WINDOW.
	"$LIVEPICKER_SCRIPTS/preview.sh" "$TEST_DRIVER_SESSION"
	assert_eq "$(tmux show-option -gqv @livepicker-linked-id)" "" \
		"self-session leaves @livepicker-linked-id empty (no link)"
	assert_eq "$(tmux list-windows -t "=$TEST_DRIVER_SESSION" -F '#{window_id}' -f '#{window_active}')" \
		"$drv_wid" "self-session selects the ORIGINAL window"
	assert_eq "$(tmux list-windows -t "=$TEST_DRIVER_SESSION" -F '#{window_id}')" "$drv_before" \
		"self-session created no duplicate window (no link-window attempted)"
}
```

#### test_capture_fallback (Task 5 — BOTH deterministic triggers)

```bash
test_capture_fallback() {
	lp_preview_seed_state
	# A REAL candidate (capture-pane needs a live pane — FINDING 9: target is =$S:.).
	tmux new-session -d -s cand -x 120 -y 40
	tmux split-window -h -t cand

	# --- (a) SNAPSHOT-mode gate (PRD §7): capture-pane path, never links. ---
	tmux set-option -g @livepicker-preview-mode snapshot
	# FINDING 11: snapshot returns before state mutation -> re-seed linked-id="".
	tmux set-option -g @livepicker-linked-id ""
	"$LIVEPICKER_SCRIPTS/preview.sh" cand \
		|| fail "snapshot-mode preview returned non-zero (capture-pane path errored)"
	assert_eq "$(tmux show-option -gqv @livepicker-linked-id)" "" \
		"snapshot mode leaves no link"
	tmux set-option -g @livepicker-preview-mode live   # reset

	# --- (b) LINK-FAILURE branch (the faithful "force a link failure"): a NON-EXISTENT
	#     driver makes `link-window -t "no-such:"` FAIL rc=1 ("can't find session") -> the
	#     real `if ! tmux link-window …` fallback branch fires. cand is REAL -> capture
	#     succeeds. (The contract's "already-linked-singly" CANNOT fail — FINDING 7.) ---
	tmux set-option -g @livepicker-orig-session "no-such-session-xyz"
	tmux set-option -g @livepicker-linked-id ""
	"$LIVEPICKER_SCRIPTS/preview.sh" cand \
		|| fail "link-failure preview returned non-zero (capture-pane path errored)"
	assert_eq "$(tmux show-option -gqv @livepicker-linked-id)" "" \
		"failed link leaves no linked-id"
}
```

NOTE for the implementer:
- This is ONE NEW FILE under `tests/`. No edits to `setup_socket.sh`/`helpers.sh`/
  `run.sh`, no `scripts/` edits, no PRD/tasks edits.
- The file is SOURCED by run.sh — define `test_*` + `lp_preview_seed_state` ONLY; NO
  side effects on source; NO `setup_test`/`teardown_test`; NO sourcing.
- `set -u` is inherited; do NOT re-declare it. Do NOT add `set -e`/`pipefail`.
- Signal failure ONLY via `fail`/`assert_*` (never `exit`).
- NO `attach_test_client` (preview.sh is client-independent — FINDING 1).
- Read ALL window ids DYNAMICALLY (global ids — FINDING 3); NEVER hardcode @N.
- The single most important correctness point is FINDING 7/8: do NOT try to trigger
  the fallback by re-linking an already-linked window (it duplicates, rc=0); use the
  snapshot-mode gate AND the bogus-driver link failure.

### Integration Points

```yaml
NEW FILE (the ONLY file this task creates):
  - tests/test_preview.sh: sourced-by-run.sh test bodies (4 test_* + lp_preview_seed_state).
        No side effects on source; drives preview.sh directly against the isolated socket.

CONSUMES (the INPUT — COMPLETE/READ-ONLY; do NOT edit):
  - tests/setup_socket.sh (T1.S1): setup_socket/teardown_socket + the TEST_*/TMUX_*/
        REAL_TMUX/LIVEPICKER_* exports + the baseline fixtures. run.sh's setup_test calls
        setup_socket per test.
  - tests/helpers.sh (T2.S1): fail/pass/assert_eq/assert_contains + setup_test/
        teardown_test + TEST_STATUS. In scope (run.sh sources helpers.sh).
  - tests/run.sh (T2.S1): the runner — sources the 3 files, discovers test_*, runs each
        in a per-test fresh-socket cycle, exits 0/1. nullglob picks up test_preview.sh
        automatically.
  - scripts/preview.sh (P1.M3.T1.S1+S2, COMPLETE/IMMUTABLE): driven directly with argv[1]=S.

CONSUMERS (downstream — NOT this task's responsibility):
  - `bash tests/run.sh` discovers + runs test_preview.sh's test_* alongside test_self +
        T3.S1's functional tests + the future T5/T6 test_*.sh (each hermetic).

PROVIDES:
  - 4 PRD §15.19 + §7 preview test_* functions + the lp_preview_seed_state seed helper.

DATABASE / MIGRATIONS / ROUTES / CONFIG: none. No @livepicker-* writes on the REAL
        server (the isolated socket only). The only real-server contact is READ-ONLY
        (snapshot /usr/bin/tmux list-sessions around run.sh — a validation step).
```

## Validation Loop

### Level 1: Syntax & Style (Immediate Feedback)

```bash
# Run after creating the file — fix before proceeding.
bash -n tests/test_preview.sh
shellcheck tests/test_preview.sh
#   expect 0 findings (file-level `# shellcheck disable=SC2154,SC2016,SC2034,SC2086`
#   is OK — mirror setup_socket.sh/helpers.sh/test_self.sh).

# Tabs-not-spaces sanity (shfmt NOT installed):
grep -Pn '^    ' tests/test_preview.sh && echo "FAIL: 4-space indent, use tabs" || echo "OK: tabs only"

# House style: set -u inherited (NOT re-declared); NO set -e/pipefail statement:
grep -nE 'set -e|set -o pipefail|^set -u' tests/test_preview.sh \
  && echo "FAIL: found a disallowed set statement (set -u is inherited; -e/pipefail forbidden)" \
  || echo "OK: no set statement (set -u inherited)"

# NO attach_test_client (preview.sh is client-independent — FINDING 1):
grep -n 'attach_test_client' tests/test_preview.sh \
  && echo "FAIL: attach_test_client called (preview.sh needs NO client)" || echo "OK: no client attach"

# No side effects on source: a bare source must NOT start a server, call setup_test,
# print, or run a test. (run.sh owns the per-test cycle.)
out="$( source tests/test_preview.sh 2>&1 )"
[ -z "$out" ] && echo "OK: source is silent" || echo "FAIL: source printed: $out"
( source tests/test_preview.sh; declare -F test_multipane_preview test_navigate_unlinks_intact \
    test_self_session_no_link test_capture_fallback lp_preview_seed_state )

# The file SOURCES NOTHING (run.sh owns sourcing):
grep -nE '^[[:space:]]*source |^[[:space:]]*\. ' tests/test_preview.sh \
  && echo "FAIL: test_preview.sh sources something (it must not)" || echo "OK: no sourcing"

# Never exits / never calls setup_test/teardown_test directly:
grep -nE '\bexit\b|setup_test|teardown_test' tests/test_preview.sh \
  && echo "FAIL: test body exits or touches the per-test cycle" || echo "OK: no exit / no setup_test"

# SCOPE: only the one new file added (no harness/scripts/PRD/tasks edits):
git status --porcelain | grep -E '^.M (tests/setup_socket|tests/helpers|tests/run)\.sh|^.M scripts/|PRD\.md|tasks\.json|prd_snapshot' \
  && echo "FAIL: edited an off-limits file" || echo "OK: only tests/test_preview.sh added"
```

### Level 2: The Suite (work-item §4 OUTPUT — runner aggregates)

```bash
# Run the full suite. Expect all four preview tests PASS + test_self + T3.S1's five
# functional tests PASS, summary "N passed, 0 failed", exit 0.
bash tests/run.sh
echo "exit=$?"
# Expected (order may vary by sort): test_capture_fallback, test_multipane_preview,
#   test_navigate_unlinks_intact, test_self_session_no_link PASS (+ the T2/T3 tests).
#   exit=0
#
# If a test FAILS: run.sh prints "FAIL  <name>" + the ASSERT FAIL line on stderr.
#   - "linked window present in the driver session" fails -> preview.sh didn't link;
#     check lp_preview_seed_state set @livepicker-orig-session (FINDING 2) and that the
#     candidate exists BEFORE preview.sh (FINDING: fixtures before the call).
#   - "pane count == 3" fails -> the candidate isn't 3-pane; ensure 2 split-windows ran.
#   - "link-failure preview returned non-zero" -> @livepicker-orig-session wasn't set to a
#     NON-EXISTENT name (it must be bogus so link-window fails — FINDING 8b).
#   - "@livepicker-linked-id" not empty after fallback -> you forgot to re-seed linked-id=""
#     between the snapshot and link-failure sub-assertions (FINDING 11).
```

### Level 3: Per-test targeted proofs (drive preview.sh directly — smoke-level)

```bash
# Proof preview.sh is reachable + the isolated socket is hit (run from repo root).
# Mirror the harness: source setup_socket + helpers, run ONE test body inline.
# shellcheck disable=SC1091
source tests/setup_socket.sh
# shellcheck disable=SC1091
source tests/helpers.sh
setup_test "lp-manual-$$"
LIVEPICKER_SCRIPTS="$LIVEPICKER_SCRIPTS"   # exported by setup_socket
drv_win="$(tmux list-windows -t "=$TEST_DRIVER_SESSION" -F '#{window_id}' -f '#{window_active}')"
tmux set-option -g @livepicker-orig-session "$TEST_DRIVER_SESSION"
tmux set-option -g @livepicker-orig-window "$drv_win"
tmux set-option -g @livepicker-linked-id ""
tmux new-session -d -s multi -x 120 -y 40; tmux split-window -h -t multi; tmux split-window -v -t multi
"$LIVEPICKER_SCRIPTS/preview.sh" multi
echo "linked-id=[$(tmux show-option -gqv @livepicker-linked-id)]"
echo "driver windows=[$(tmux list-windows -t "=$TEST_DRIVER_SESSION" -F '#{window_id}' | tr '\n' ' ')]"
echo "multi windows=[$(tmux list-windows -t '=multi' -F '#{window_id}' | tr '\n' ' ')]"
# Expected: linked-id=[@4]; driver windows include @4; multi windows=[@4].
teardown_test
# (Re-run with run.sh for the full assertion suite — this just proves reachability.)
```

### Level 4: Creative & Domain-Specific Validation (PRD §15 non-pollution + robustness)

```bash
# PRD §15 invariant (the real server is untouched) — snapshot the user's REAL session
# list around a FULL run.sh invocation (multiple per-test setup/teardown cycles).
real_before="$(/usr/bin/tmux list-sessions -F '#{session_name}' | sort)"
bash tests/run.sh >/dev/null 2>&1
real_after="$(/usr/bin/tmux list-sessions -F '#{session_name}' | sort)"
[ "$real_before" = "$real_after" ] && echo "OK: real server byte-identical before/after" \
  || { echo "FAIL: real server changed"; diff <(echo "$real_before") <(echo "$real_after"); }

# Robustness: the snapshot-mode trigger truly does NOT link. Prove preview.sh under
# snapshot leaves the driver's window count unchanged (no link).
# shellcheck disable=SC1091
( source tests/setup_socket.sh; source tests/helpers.sh
  setup_test "lp-snap-$$"
  drv_win="$(tmux list-windows -t "=$TEST_DRIVER_SESSION" -F '#{window_id}' -f '#{window_active}')"
  tmux set-option -g @livepicker-orig-session "$TEST_DRIVER_SESSION"
  tmux set-option -g @livepicker-orig-window "$drv_win"; tmux set-option -g @livepicker-linked-id ""
  tmux new-session -d -s cand -x 120 -y 40; tmux split-window -h -t cand
  before="$(tmux list-windows -t "=$TEST_DRIVER_SESSION" -F '#{window_id}')"
  tmux set-option -g @livepicker-preview-mode snapshot
  "$LIVEPICKER_SCRIPTS/preview.sh" cand
  after="$(tmux list-windows -t "=$TEST_DRIVER_SESSION" -F '#{window_id}')"
  [ "$before" = "$after" ] && echo "OK: snapshot mode added no window (no link)" \
    || echo "FAIL: snapshot mode changed the driver window list"
  teardown_test )

# Robustness: the link-failure trigger genuinely FAILS link-window (bogus session) and
# preview.sh still exits 0 via the capture-pane fallback.
# shellcheck disable=SC1091
( source tests/setup_socket.sh; source tests/helpers.sh
  setup_test "lp-lf-$$"
  tmux set-option -g @livepicker-orig-session "no-such-session-xyz"
  tmux set-option -g @livepicker-orig-window "@0"; tmux set-option -g @livepicker-linked-id ""
  tmux new-session -d -s cand -x 120 -y 40; tmux split-window -h -t cand
  if "$LIVEPICKER_SCRIPTS/preview.sh" cand; then
    echo "OK: link-failure -> capture-pane fallback -> rc 0"
  else
    echo "FAIL: link-failure preview exited non-zero"
  fi
  teardown_test )
```

## Final Validation Checklist

### Technical Validation

- [ ] Level 1 passes: `bash -n` + `shellcheck` (0 new findings); tabs only; `set -u`
      inherited (no `set -e`/`pipefail`); no sourcing; no `exit`/`setup_test`;
      NO `attach_test_client`.
- [ ] Level 2 passes: `bash tests/run.sh` -> all four PASS + test_self + T3.S1 PASS, exit 0.
- [ ] Level 3 passes: the inline manual probe shows linked-id == the candidate's window
      id + the driver + source both list it after a real preview on the isolated socket.
- [ ] Level 4 passes: real server byte-identical before/after a full run; snapshot mode
      adds no window; the link-failure trigger exits 0 via the fallback.
- [ ] `git status --porcelain` shows ONLY `tests/test_preview.sh` added.

### Feature Validation

- [ ] **test_multipane_preview**: a 3-pane candidate links into the driver; the window id
      is in BOTH driver + source; the driver's current window == the candidate's window;
      the linked window's pane count == 3.
- [ ] **test_navigate_unlinks_intact**: after preview S then preview S2, S's window is NO
      LONGER in the driver but its window list is UNCHANGED in its own session.
- [ ] **test_self_session_no_link**: previewing the driver leaves @livepicker-linked-id
      empty, selects the ORIGINAL window, and creates NO duplicate window.
- [ ] **test_capture_fallback**: BOTH the snapshot-mode gate AND the bogus-driver link
      failure make preview.sh run capture-pane (rc 0) with no link.
- [ ] Error cases handled via `fail` (never `exit`); the suite aggregates exit 0/1.

### Code Quality Validation

- [ ] Mirrors `tests/test_self.sh`'s sourced-by-run.sh style (no side effects on source;
      inherited `set -u`; shellcheck disable header; tabs; local).
- [ ] File placement matches the desired tree (`tests/test_preview.sh`).
- [ ] Drives the REAL preview.sh (no mocks/stubs); uses the harness's isolation + assert
      helpers (no re-implementation); NO attach_test_client (client-independent).
- [ ] Anti-patterns avoided (check against Anti-Patterns section).

### Documentation & Deployment

- [ ] Code is self-documenting (inline comments cite the findings: F1/F2/F3/F7/F8/F11).
- [ ] DOCS: Mode A — none (test infra). No README/CHANGELOG changes (P1.M8 owns those).
- [ ] No new environment variables (uses only the harness exports).

---

## Anti-Patterns to Avoid

- ❌ **Don't call `attach_test_client`.** `preview.sh` reads the driver session from
  `@livepicker-orig-session` (NOT `display-message`); it uses only link/unlink/select/
  list/capture primitives that work on a DETACHED socket. The attach adds pty timing
  flakiness for zero benefit — FINDING 1.
- ❌ **Don't try to trigger the fallback by re-linking an already-linked window.** tmux
  3.6b's `link-window` SUCCEEDS (rc=0) and silently DUPLICATES; the contract's literal
  "already-linked-singly" trigger CANNOT reach the `if ! tmux link-window` branch. Use
  the snapshot-mode gate AND the bogus-`@livepicker-orig-session` link failure — FINDING 7/8.
- ❌ **Don't hardcode window ids (@4, @5).** They are server-global + depend on the fixture
  seed order. Read the candidate's active window id live via `list-windows -t =<sess> -F
  '#{window_id}' -f '#{window_active}'` — FINDING 3.
- ❌ **Don't drive via `livepicker.sh`/`input-handler.sh` for THESE tests.** That is
  T3.S1's integration scope (test_nav_moves_selection already covers nav→linked-id).
  T4.S1 calls `preview.sh <S>` DIRECTLY to pin down link/unlink/select semantics — unit
  scope. Driving through activate also drags in status-grow/key-table/hook side effects
  that are irrelevant to preview semantics + require a client.
- ❌ **Don't forget to re-seed `@livepicker-linked-id=""` between the two `test_capture_fallback`
  sub-assertions.** The snapshot path returns before state mutation, so a prior linked-id
  survives; assert_empty would then false-pass on stale state — FINDING 11.
- ❌ **Don't `exit` / `return`-nonzero-to-abort in a test body.** run.sh reads
  `TEST_STATUS` in the CURRENT shell; a bare `exit` kills the runner. Signal failure
  ONLY via `fail`/`assert_*` (resurrect fail_helper contract).
- ❌ **Don't source anything / call `setup_test`/`teardown_test`/re-declare `set -u`.**
  The file is sourced by run.sh; the helpers, `$LIVEPICKER_SCRIPTS`, `$TEST_DRIVER_SESSION`,
  and `set -u` are all in scope. Define `test_*` + `lp_preview_seed_state` only.
- ❌ **Don't add `set -e` / `set -o pipefail` / use `echo | grep` or a `wc -l` pipe for the
  pane count.** House style is `set -u` only (system_context §9); use `mapfile` +
  `${#arr[@]}` (no subprocess, no pipefail hazard).
- ❌ **Don't edit `setup_socket.sh`/`helpers.sh`/`run.sh`, any `scripts/*`, `PRD.md`,
  `tasks.json`, `prd_snapshot.md`, or `.gitignore`.** This task ADDS exactly ONE file:
  `tests/test_preview.sh`.

---

## Confidence Score

**9/10** for one-pass implementation success.

This is one NEW sourced test file (zero edits to existing code) driving the COMPLETE
`preview.sh` directly. Every driving pattern + assertion target is **empirically
verified** on the isolated socket via the ACTUAL harness files: multi-pane link shows
all 3 panes + the window is in both sessions (FINDING 4); navigate-away unlinks from the
driver while the source keeps its window (FINDING 5); self-session leaves linked-id empty
+ selects orig + no duplicate (FINDING 6); and BOTH capture fallback triggers run
capture-pane with rc=0 (FINDING 8). The ready-to-paste test bodies leave no ambiguity,
and the two non-obvious traps are each called out with the exact fix: the contract's
INVALID "already-linked-singly" trigger (FINDING 7 → use snapshot-mode + bogus-driver),
and the snapshot state-inheritance (FINDING 11 → re-seed linked-id). The residual risk
(-1): the test relies on `preview.sh`'s current internal contract (reads exactly the 3
seeded keys + the mode) — if a future P1.M3 refactor changes that surface, the seed
helper would need updating; mitigated by the inline comments citing the exact state.sh
keys. The parallel-execution dependency on T3.S1 is clean: this file only defines
`test_*` that consume the in-scope helpers; it composes regardless of when the sibling
test files land (run.sh's `nullglob` glob picks up `test_preview.sh` automatically).
