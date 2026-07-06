# PRP — P1.M7.T3.S1: `tests/test_functional.sh`

---

## Goal

**Feature Goal**: **CREATE** the PRD §15.17 *Functional* validation test suite —
`tests/test_functional.sh` — a single **sourced** bash file that defines five
`test_*` functions (`test_activate_grows_status`, `test_typing_filters`,
`test_nav_moves_selection`, `test_confirm_lands`, `test_escape_restores`) which
**drive the COMPLETE real plugin** (`scripts/livepicker.sh` →
`scripts/input-handler.sh` → `scripts/renderer.sh` → `scripts/preview.sh` →
`scripts/restore.sh`, all COMPLETE P1.M1–M6) **directly** (NOT via keypress —
work-item §1 RESEARCH NOTE) against the **socket-isolated** tmux server provided
by the COMPLETE harness (`tests/setup_socket.sh` P1.M7.T1.S1 +
`tests/helpers.sh` P1.M7.T2.S1), and **assert observable tmux state**. Each test
gets a fresh isolated server (run.sh's per-test `setup_test`/`teardown_test`
cycle), attaches a real client, exercises one PRD §15.17 bullet, and signals
pass/fail via `fail`/`assert_*` (which set `TEST_STATUS`). `bash tests/run.sh`
discovers and runs them and exits 0/1.

**Deliverable** (ONE new file): `tests/test_functional.sh` — a SOURCED bash
library defining exactly these five `test_*` functions (discovered by run.sh's
`compgen -A function | grep '^test_'`) + a small local `lp_runtime_cleared`
helper. It SOURCES NOTHING (run.sh sources `setup_socket.sh` + `helpers.sh` +
`test_*.sh` first; the assert helpers, `attach_test_client`, `$LIVEPICKER_SCRIPTS`,
`TEST_DRIVER_SESSION`, and the isolated bare-`tmux` shim are all in scope before
any `test_*` runs). No side effects on source (defines functions only).

**Success Definition**:
- `bash -n` + `shellcheck` pass on `tests/test_functional.sh` (0 findings beyond a
  file-level `# shellcheck disable=SC2154,SC2016,SC2034,SC2086`; tabs only;
  `set -u` inherited — NOT re-declared, mirror `test_self.sh`).
- `bash tests/run.sh` runs all five `test_*` (plus T2.S1's `test_self`),
  each prints **PASS**, the suite summary is `N passed, 0 failed`, exit **0**.
- Each `test_*` drives the REAL scripts against the isolated socket (bare `tmux`
  + `$LIVEPICKER_SCRIPTS/*.sh`), attaches a real client, and asserts the exact
  PRD §15.17 observable signals (status==2, key-table==livepicker,
  @livepicker-mode==on, renderer filtering, @livepicker-linked-id, client lands
  on target, cancel restores origin).
- **The real user server is provably untouched**: `/usr/bin/tmux list-sessions`
  is byte-identical before/after a full `run.sh` invocation (the harness owns
  isolation; this task never touches `/usr/bin/tmux`).
- `git diff --stat` shows ONLY `tests/test_functional.sh` added (NO edits to
  `setup_socket.sh`/`helpers.sh`/`run.sh`, NO `scripts/*`, NO PRD/tasks —
  FORBIDDEN).

## User Persona (if applicable)

**Target User**: the contributor running the suite (`bash tests/run.sh`) and the
future maintainer extending the checks. The test file has no end-user surface
(DOCS: Mode A — none; it is test infra).

**Use Case**: a contributor runs `bash tests/run.sh`; run.sh gives each
`test_*` function a fresh isolated socket, the function attaches a client,
activates the picker, drives input, and asserts state; run.sh reports PASS/FAIL +
exits 0/1. Each test is hermetic (per-test fresh server) so a mutation in one
(filter set, key-table switched, preview linked) cannot leak into another.

**User Journey** (per test): `setup_test` (run.sh) → `attach_test_client` →
(optional extra fixtures) → `livepicker.sh` → `input-handler.sh …` →
`renderer.sh` (read-only) / `tmux show-option` / `tmux display-message -p` →
`assert_*` / `fail` → (control returns to run.sh) → `teardown_test`.

**Pain Points Addressed**:
- (a) **No functional tests existed.** T1.S1/T2.S1 built the harness; this task
  adds the FIRST test bodies that actually exercise the COMPLETE plugin end-to-end
  against the isolated server (the §15.17 Functional cluster).
- (b) **"No @livepicker-*" is a trap in this env.** The isolated server sources
  the user's tmux.conf, pre-setting dormant `@livepicker-fg`/`@livepicker-key`
  (research FINDING 2). The naive `grep -c == 0` false-fails; this PRP specifies
  the correct `lp_runtime_cleared` assertion (runtime+orig keys unset; config
  legitimately remains — CORRECTION A).
- (c) **Driving scripts needs a client.** `livepicker.sh`/`confirm`/`cancel` use
  `display-message -p` / `switch-client` which REQUIRE an attached client; the
  work-item's "call livepicker.sh directly" only works after `attach_test_client`.
  This PRP makes that explicit per-test.

## Why

- **PRD §15.17 Functional** is the controlling spec (selected `h2.15/h3.17`): the
  five bullets map 1:1 to the five `test_*` functions. §6 Behaviors (selected
  `h2.6`) defines Activation/Filtering/Session-navigation/Confirm/Cancel — the
  exact flows each test drives. §3 User stories (selected `h2.3`) is the "why"
  ("I type `log`..."; "I press Enter... I am in that session"; "I press Escape...
  exactly where I was").
- **Scope cohesion.** T3.S1 is the Functional cluster of module P1.M7
  (Validation). T1.S1 owns socket isolation (COMPLETE); T2.S1 owns
  assertions + discovery + the runner (will exist — its PRP is the contract);
  T3.S1 owns the Functional test BODIES (this file). T4–T6 (preview/pollution/
  restore/keyrepurpose/create) are SIBLING test files — each a separate
  `test_*.sh`, each hermetic via run.sh's per-test cycle. This task does NOT own
  those clusters or the harness.
- **system_context §7 + the P1.M6 throwaway mocks** (`confirm_mock.sh` /
  `cancel_mock.sh`) are the proven patterns: drive the real scripts against an
  isolated `-L` socket with one `script -qec`-attached client; assert observable
  state. T3.S1 productionizes those throwaway assertions into the harness-backed,
  sourced, `test_*`-discovered suite.

## What

**CREATE** the single file `tests/test_functional.sh`. No other file is touched
(`setup_socket.sh`/`helpers.sh`/`run.sh` are owned by T1.S1/T2.S1 — COMPLETE or
in-flight, READ-ONLY here; `scripts/*` are COMPLETE/IMMUTABLE; PRD/tasks/
prd_snapshot are READ-ONLY). The file is **SOURCED** by `run.sh` (defines `test_*`
functions + the `lp_runtime_cleared` helper only; NO side effects on source; NO
top-level execution; NO `setup_test`/`teardown_test` calls — run.sh owns the
per-test cycle).

### Success Criteria

- [ ] `tests/test_functional.sh` passes `bash -n` + `shellcheck` (file-level
      `disable` for SC2154/SC2016/SC2034/SC2086 at most); tabs only; `set -u`
      inherited (NOT re-declared).
- [ ] Defines EXACTLY five `test_*` functions (discovered by run.sh's `compgen`)
      + the local `lp_runtime_cleared` helper. No other top-level code.
- [ ] Each `test_*` calls `attach_test_client` (the scripts need a client) and
      drives the real `$LIVEPICKER_SCRIPTS/*.sh` against the isolated socket;
      signals failure ONLY via `fail`/`assert_*` (NEVER `exit`).
- [ ] `bash tests/run.sh` prints `PASS` for all five (+ `test_self`), summary
      `N passed, 0 failed`, exit 0.
- [ ] `/usr/bin/tmux list-sessions` byte-identical before/after a full run.
- [ ] `git diff --stat` shows ONLY `tests/test_functional.sh` added.

## All Needed Context

### Context Completeness Check

_Pass_: a developer who has never seen this repo can implement T3.S1 from
(a) the five ready-to-paste test bodies in "Implementation Patterns & Key
Details"; (b) the 11 findings in `research/functional_test_findings.md` — most
critically **FINDING 2** (the dormant-config trap → `lp_runtime_cleared`, NOT
`grep==0`), **FINDING 3** (the driving API + the REQUIRED client), **FINDING 5**
(add `log` fixtures BEFORE activate), **FINDING 6** (read window ids DYNAMICALLY);
and (c) the live probe that confirmed the isolated server's defaults
(status=on→2, key-table=root, dormant @livepicker-fg/@livepicker-key present).
The INPUTS are the COMPLETE harness (`tests/setup_socket.sh` + `tests/helpers.sh`,
read in full) and the COMPLETE plugin (`scripts/*`, read in full).

### Documentation & References

```yaml
# MUST READ — the empirical + idiomatic ground-truth for THIS task (11 findings + PROBE).
- docfile: plan/001_fd5d622d3939/P1M7T3S1/research/functional_test_findings.md
  why: FINDING 1 (the harness is COMPLETE; the test SOURCES NOTHING; the available
        surface); FINDING 2 (THE dormant-config trap — isolated server sources the
        user tmux.conf -> @livepicker-fg/@livepicker-key survive teardown -> use
        lp_runtime_cleared, NOT grep==0); FINDING 3 (the driving API + REQUIRED
        client); FINDING 4 (activation signals); FINDING 5 (add 'log' fixtures
        BEFORE activate); FINDING 6 (dynamic window ids); FINDING 7 (navigate then
        confirm); FINDING 8 (dynamic orig capture + empty-filter cancel);
        FINDING 9 (negative-substring via inline case); FINDING 10 (house style);
        FINDING 11 (confidence).
  critical: Read BEFORE writing. FINDING 2 is the single non-obvious correctness
        issue — the work-item's literal "no @livepicker-*" FALSE-FAILS here.

# MUST READ — the harness contract this task CONSUMES (read in full; COMPLETE).
- file: tests/setup_socket.sh
  why: the isolation layer. Provides setup_socket/teardown_socket +
        attach_test_client/detach_test_client (the `script -qec` pty attach —
        REQUIRED for display-message/switch-client/refresh-client -S); exports
        TEST_SOCKET/TMUX_*/REAL_TMUX/LIVEPICKER_ROOT/LIVEPICKER_SCRIPTS/
        TEST_DRIVER_SESSION("driver")/TEST_FIXTURE_SESSIONS("alpha beta"). SOURCED
        library (no side effects on source). Mirror its header STYLE (CONTRACT line,
        set -u, tabs, local, shellcheck disable). DO NOT EDIT IT.
  pattern: attach_test_client [session] spawns `script -qec "tmux attach -t '<sess>'"
        /dev/null >/dev/null 2>&1 &` + sleeps 0.5 (FINDING 3 client).
  gotcha: setup_socket seeds driver/alpha/beta + driver:extra multi-pane window +
        a split pane in beta. driver's ACTIVE window after seed = the "extra" @N
        window (new-window makes it active) — capture orig window DYNAMICALLY.

# MUST READ — the assertion + per-test helpers this task CONSUMES (COMPLETE).
- file: tests/helpers.sh
  why: provides fail/pass/assert_eq/assert_contains + setup_test/teardown_test
        (THIN delegates to setup_socket) + the TEST_STATUS global. assert_contains
        is POSITIVE only (FINDING 9: use inline `case` for absence). These are in
        scope because run.sh sources helpers.sh before test_*.sh. DO NOT EDIT IT.
  pattern: assert_eq a b msg -> [ "$a" = "$b" ] else fail; assert_contains str sub
        msg -> case "$str" in *"$sub"*) … ;; quiet on success.

# MUST READ — the runner (T2.S1 PRP = the contract; the file lands with this task).
- docfile: plan/001_fd5d622d3939/P1M7T2S1/PRP.md
  why: run.sh sources setup_socket.sh + helpers.sh + every tests/test_*.sh, then
        PER test: setup_test "lp-$$-<name>" -> TEST_STATUS=pass -> run $t in the
        CURRENT shell -> read TEST_STATUS -> PASS/FAIL -> teardown_test. The
        CONTRACT for test bodies: define test_* ONLY (no side effects on source);
        signal failure ONLY via fail/assert_* (NEVER exit — run.sh reads
        TEST_STATUS in the current shell; a bare exit kills the runner).
  critical: the test function runs AFTER setup_test (so $LIVEPICKER_SCRIPTS +
        the shim are live) and in the SAME shell as helpers.sh (so assert_* +
        attach_test_client are in scope). test_functional.sh SOURCES NOTHING.

# MUST READ — the scripts this task DRIVES (all COMPLETE P1.M1-M6; read in full).
- file: scripts/livepicker.sh
  why: the ACTIVATE entry (`"$LIVEPICKER_SCRIPTS/livepicker.sh"`, no args). STEP 2
        uses display-message -p '#{session_name/window_id/window_layout}' -> REQUIRES
        a client (attach first). Sets status=2 (normalize on->2), status-format[0]
        = #(…/renderer.sh), key-table=livepicker, @livepicker-mode=on (LAST). The
        initial preview is the SELF-session (driver) -> @livepicker-linked-id EMPTY.
  gotcha: capture orig session/window/status/key-table BEFORE calling it (dynamic).
- file: scripts/input-handler.sh
  why: the input dispatcher. `input-handler.sh <action> [char]`, action ∈
        type|backspace|next-session|prev-session|confirm|cancel. `type` argv[2]=char.
        `type`/`backspace`: mutate @livepicker-filter + index=0 + refresh (NEVER
        touch @livepicker-list). `next/prev-session`: index wrap modulo filtered
        list + call preview.sh + refresh (NEVER switch-client — Invariant A).
        `confirm`: resolve target, _confirm_land_on_session (unlink driver preview
        FIRST, switch-client ONCE, restore keep) — or create-on-enter, or cancel.
        `cancel`: TWO-STEP — non-empty filter CLEARS it (picker OPEN); empty filter
        -> restore.sh cancel (full teardown).
  gotcha: for a single `cancel` to tear down, the filter must be EMPTY.
- file: scripts/renderer.sh
  why: the PURE read-only #() renderer. Run directly: `out="$(renderer.sh)"`.
        Reads @livepicker-list/filter/index, filters via lp_build_filtered, prints
        ONE line: space-joined #[fg,bg]NAME#[default] segments (highlighted = index
        0 = black-on-yellow) + optional `query> <filter> [idx+1/FLEN]`. assert the
        NAMEs (literal substrings despite #[..] codes).
- file: scripts/preview.sh
  why: the live-preview core (called internally by nav/confirm/activate). Links the
        target's active window into the driver, sets @livepicker-linked-id = target's
        window id. SELF-session (target==driver) CLEARS linked_id + selects
        ORIG_WINDOW. Observable state for test_nav_moves_selection.
- file: scripts/restore.sh
  why: the teardown (keep|cancel). cancel: switch-client to ORIG_SESSION (dedup),
        select-window ORIG_WINDOW, restore status/key-table/renumber/hook,
        select-layout ORIG_LAYOUT, clear_all_state + unbind livepicker table. keep:
        no switch (confirm already switched). Both end with runtime+orig cleared.
- file: scripts/state.sh
  why: the STATE_*/ORIG_* constants + clear_all_state. CORRECTION A: clear_all_state
        clears ONLY the 5 runtime keys + @livepicker-orig-* (PRESERVES §11 config).
        This is WHY lp_runtime_cleared checks the runtime+orig keys, not grep==0
        (FINDING 2).
- file: scripts/options.sh
  why: the defaults. opt_type=session, opt_create=on, opt_status_format_index=0,
        opt_show_count=on, opt_highlight_fg/bg=black/yellow, opt_fg/bg=default
        (BUT @livepicker-fg=#ffffff is dormant-config-set in this env — cosmetic
        only; does not affect the assertions).

# MUST READ (cross-reference) — the throwaway mocks that PRE-FIGURED every pattern.
- docfile: plan/001_fd5d622d3939/P1M6T3S1/research/confirm_mock.sh
- docfile: plan/001_fd5d622d3939/P1M6T4S1/research/cancel_mock.sh
  why: both drive the real scripts against an isolated -L socket with ONE
        script-qec-attached client and assert observable state (cur_session via
        display-message -p; @livepicker-linked-id; history recorder). They use a
        per-file `T(){ tmux -L "$SOCK" "$@"; }` + inline ok/bad/assert — the
        harness productionizes the socket (PATH shim -> bare `tmux`) + the asserts
        (helpers.sh). Borrow their DRIVING SEQUENCE + assertion TARGETS verbatim;
        swap `T …` -> bare `tmux` and `assert 'expr' msg` -> `assert_eq`/inline-case.
  critical: the mocks are THROWAWAY (P1.M6 owned them). Do NOT ship them. T3.S1 is
        the harness-backed, sourced, test_*-discovered version.

# MUST READ — the architecture ground-truth.
- docfile: plan/001_fd5d622d3939/architecture/system_context.md
  why: §3 INVARIANT A (select-window/link/unlink NEVER fire client-session-changed
        -> browsing keeps the client on driver; only confirm's switch-client moves
        it); §7 (the harness is INVENTED here — no sibling template); §9 shell
        style (set -u ONLY; tabs; local; CURRENT_DIR; quote everything); §1 (the
        dormant @livepicker-key Space / @livepicker-fg #ffffff in the user config —
        the SOURCE of FINDING 2).
  section: "§3 INVARIANT A", "§7 Test harness reality", "§9 Shell style", "§1".

# MUST READ — the PRD sections selected for this work item.
- docfile: PRD.md
  why: §15.17 Functional (the 5 bullets -> the 5 test_*); §6 Behaviors
        (Activation/Filtering/Session-navigation/Confirm/Cancel — the flows); §3
        User stories (the "why"); §16 risks (tmux 3.0 floor; the client-attach
        need; #() refresh-client -S).
```

### Current Codebase tree

```bash
tmux-livepicker/
  PRD.md                                # READ-ONLY (FORBIDDEN to edit).
  plugin.tmux                           # COMPLETE. Unchanged.
  scripts/                              # ALL COMPLETE (P1.M1-M6). IMMUTABLE — this task DRIVES them, never edits.
    options.sh utils.sh state.sh filter.sh renderer.sh preview.sh
    livepicker.sh restore.sh input-handler.sh
  tests/
    setup_socket.sh   # COMPLETE (P1.M7.T1.S1). READ-ONLY. The isolation + client helpers + exports.
    helpers.sh        # COMPLETE (P1.M7.T2.S1). READ-ONLY. fail/pass/assert_eq/assert_contains + setup_test/teardown_test.
    run.sh            # P1.M7.T2.S1 (lands with this task). The runner; sources the 3 files + discovers test_*.
    test_self.sh      # P1.M7.T2.S1. The §5 self-test. Sibling test_*.sh.
  plan/001_fd5d622d3939/{architecture/*.md, tasks.json, prd_snapshot.md, prd_index.txt}
  plan/001_fd5d622d3939/P1M7T3S1/{PRP.md, research/functional_test_findings.md}   # THIS
  .gitignore
  # NOTE: tests/test_functional.sh does NOT exist yet — THIS task creates it.
```

### Desired Codebase tree with files to be added and responsibility of file

```bash
tmux-livepicker/
  tests/
    test_functional.sh   # NEW (this task). SOURCED by run.sh (defines test_* + lp_runtime_cleared only;
                         #   NO side effects on source). Drives the REAL scripts against the isolated
                         #   socket; attaches a client per test; asserts PRD §15.17 observable state.
                         #   test_activate_grows_status  : status==2, status-format[0]~renderer.sh,
                         #                                key-table==livepicker, @livepicker-mode==on.
                         #   test_typing_filters         : type 'log' char-by-char; renderer shows ONLY
                         #                                syslog/blog; @livepicker-index==0.
                         #   test_nav_moves_selection    : next-session -> @livepicker-linked-id == each
                         #                                target's live window id (read dynamically).
                         #   test_confirm_lands          : navigate then confirm -> client session==target;
                         #                                picker runtime+orig cleared (lp_runtime_cleared).
                         #   test_escape_restores        : nav then cancel -> session/window/status/
                         #                                key-table == orig; runtime cleared.
                         #   lp_runtime_cleared()        : local helper — the 5 runtime keys + @livepicker-orig-*
                         #                                are unset (CORRECTION A: §11 config may remain; FINDING 2).
```

### Known Gotchas of our codebase & Library Quirks

```bash
# CRITICAL (research FINDING 2 — the dormant-config trap): the isolated `tmux -L`
#   server SOURCES the user's ~/.config/tmux/tmux.conf, which pre-sets the DORMANT
#   config @livepicker-fg "#ffffff" + @livepicker-key Space (system_context §1;
#   verified live). After confirm/cancel, clear_all_state (CORRECTION A) PRESERVES
#   §11 config -> those two options REMAIN. CONSEQUENCE: `show-options -g | grep
#   livepicker` is NOT empty after teardown; the work-item's literal "no
#   @livepicker-*" / `grep -c == 0` FALSE-FAILS. CORRECT: assert the 5 RUNTIME
#   keys (@livepicker-mode/list/filter/index/linked-id) AND every @livepicker-orig-*
#   are unset, via the lp_runtime_cleared() helper. (PRD §15.21 "prints nothing" is
#   the aspirational spec; CORRECTION A is the implemented reality.)

# CRITICAL (research FINDING 3 — the client is REQUIRED): livepicker.sh STEP 2
#   (display-message -p '#{session_name/window_id/window_layout}'), confirm
#   (switch-client), cancel (display-message + switch-client), and every
#   refresh-client -S REQUIRE an attached client. run.sh's setup_test does NOT
#   attach. So EVERY test_* calls attach_test_client (default target =
#   TEST_DRIVER_SESSION = "driver") near its start. With exactly ONE client,
#   display-message -p resolves deterministically to it. (The mocks proved this.)

# CRITICAL (research FINDING 5 — add fixtures BEFORE activate): @livepicker-list is
#   captured at activate time (tmux list-sessions). The baseline driver/alpha/beta
#   contain no 'log' substring, so test_typing_filters MUST add 'log'-matching
#   sessions (e.g. syslog, blog) via bare `tmux new-session -d` BEFORE running
#   livepicker.sh, or the filtered view is empty (the "no match" path, not the
#   filter path). input-handler.sh NEVER mutates @livepicker-list (FINDING 2 of its
#   own research) — typing only changes @livepicker-filter/index.

# CRITICAL (research FINDING 6 — window ids are GLOBAL, read DYNAMICALLY): window
#   ids (@0,@1,...) are server-global + assigned incrementally; the baseline seed
#   already consumes @0(driver)+@3(driver:extra)+@1(alpha)+@2(beta). NEVER hardcode
#   them. Read the expected id live: `tmux list-windows -t =alpha -F '#{window_id}'
#   -f '#{window_active}'`. After next-session, @livepicker-linked-id == that id.

# GOTCHA (research FINDING 8 — cancel is TWO-STEP): input-handler.sh `cancel` with
#   a NON-empty filter CLEARS the filter + keeps the picker OPEN; only an EMPTY
#   filter triggers full restore.sh cancel. So test_escape_restores must have an
#   empty filter when it cancels (activate sets filter=""; nav does not change it).
#   To exercise restore-after-browse, do activate -> next-session (link a window) ->
#   cancel (restore unlinks it + restores layout). Nav keeps the client on driver
#   (Invariant A), so cancel's switch-client to ORIG_SESSION is a dedup no-op.

# GOTCHA (research FINDING 9 — negative substring): helpers.sh's assert_contains is
#   POSITIVE only. For ABSENCE ("renderer does NOT show alpha"), use an inline
#   `case "$out" in *alpha*) fail "..."; esac` (literal substring, no subprocess,
#   set -u safe). Do NOT add a refute_contains to helpers.sh (COMPLETE/T2.S1-owned).
#   Do NOT use `echo | grep -v` (pipefail hazard; house style forbids pipefail).

# GOTCHA (capture orig DYNAMICALLY): driver's ACTIVE window after the baseline seed
#   is the "extra" window (@N, made active by new-window) — NOT @0. So
#   test_escape_restores captures orig_win via `display-message -p '#{window_id}'`
#   BEFORE activate (do not assume @0). Same for orig_sess/status/key-table.

# GOTCHA (status value): a fresh server's default `status` is "on" (verified);
#   activate's normalize turns "on" -> 2. So `show-option -gqv status` == "2" after
#   activate (the work-item's signal holds). Do NOT assert a different number.

# GOTCHA (status-format[0] quoting): the bracketed name is shell-special — quote
#   it: `tmux show-option -gqv 'status-format[0]'`. activate overwrites the tubular
#   default composite at [0] with `#($CURRENT_DIR/renderer.sh)`, so it CONTAINS
#   "renderer.sh" (assert_contains).

# STYLE (research FINDING 10 / system_context §9): shebang #!/usr/bin/env bash;
#   `set -u` INHERITED (helpers.sh/run.sh declare it) — do NOT re-declare (mirror
#   test_self.sh: "`# set -u is inherited`"); local for ALL function locals; TABS;
#   quote everything. Signal failure ONLY via fail/assert_* (NEVER exit — run.sh
#   reads TEST_STATUS in the CURRENT shell; a bare exit kills the runner). The file
#   is SOURCED by run.sh: define test_* ONLY; NO side effects on source; NO
#   setup_test/teardown_test calls (run.sh owns the per-test cycle).

# GOTCHA: do NOT edit tests/setup_socket.sh, tests/helpers.sh, tests/run.sh, any
#   scripts/* file, PRD.md, tasks.json, prd_snapshot.md, or .gitignore (FORBIDDEN).
#   This task ADDS exactly ONE file: tests/test_functional.sh.
```

## Implementation Blueprint

### Data models and structure

No data model. The "model" is the **test-body contract** between run.sh and
`test_functional.sh`:

```bash
# The shared surface IN SCOPE when each test_* runs (provided by run.sh's sources
# + setup_test — test_functional.sh SOURCES NOTHING):
#   bare `tmux`              -> the PATH shim -> isolated -L socket (transparent).
#   $LIVEPICKER_SCRIPTS      -> repo scripts/ (exported by setup_socket).
#   $TEST_DRIVER_SESSION     -> "driver" (the client home / activate origin).
#   attach_test_client [sess]-> the script-qec pty attach (REQUIRED for the scripts).
#   fail/pass/assert_eq/assert_contains + TEST_STATUS -> from helpers.sh.
#
# The CONTRACT for each test_* body:
#   - attach a client FIRST (the scripts need one).
#   - drive the REAL $LIVEPICKER_SCRIPTS/*.sh (NOT keypresses — work-item §1).
#   - assert observable state via assert_*/fail (NEVER exit).
#   - add any extra fixtures (e.g. syslog/blog) BEFORE activate where the list matters.
#   - run.sh wraps you in setup_test -> test -> teardown_test; do NOT call those.
```

### Implementation Tasks (ordered by dependencies)

```yaml
Task 1: CREATE tests/test_functional.sh — header + lp_runtime_cleared helper
  - CREATE: tests/test_functional.sh (NEW; SOURCED by run.sh — NEVER executed
        directly; no self-test guard; no BASH_SOURCE/$0 check).
  - HEADER: #!/usr/bin/env bash ; a CONTRACT comment ("sourced by run.sh; defines
        test_* + lp_runtime_cleared only; NO side effects on source; NO setup_test/
        teardown_test calls — run.sh owns the per-test cycle; the assert helpers,
        attach_test_client, $LIVEPICKER_SCRIPTS come from run.sh's sources");
        `# set -u is inherited` (do NOT re-declare; mirror test_self.sh); file-level
        `# shellcheck disable=SC2154,SC2016,SC2034,SC2086` (SC2154: the assert_* +
        attach_test_client + $LIVEPICKER_SCRIPTS are defined by run.sh's sources,
        not here).
  - IMPLEMENT: `lp_runtime_cleared` (local helper; FINDING 2). Returns 0 iff the 5
        picker-RUNTIME keys (@livepicker-mode/list/filter/index/linked-id) are all
        unset AND no @livepicker-orig-* saved-state keys remain. Loops the 5 names,
        `[ -z "$(tmux show-option -gqv "$k" 2>/dev/null)" ] || return 1`; then
        `[ -z "$(tmux show-options -g 2>/dev/null | grep '@livepicker-orig-')" ] ||
        return 1`; `return 0`. local k. THIS IS THE CORRECT "picker torn down"
        assertion (CORRECTION A: §11 config like @livepicker-fg/@livepicker-key
        legitimately REMAINS — do NOT use `grep -c '@livepicker' == 0`).
  - FOLLOW pattern: tests/test_self.sh (sourced-by-run.sh file; no side effects;
        inherited set -u; shellcheck disable header).
  - DO NOT: source anything; call setup_test/teardown_test; re-declare set -e/pipefail.

Task 2: test_activate_grows_status (PRD §15.17 bullet 1)
  - IMPLEMENT: attach_test_client; run `"$LIVEPICKER_SCRIPTS/livepicker.sh"`; then
        assert_eq "$(tmux show-option -gqv status)" "2" "status grew to 2 lines";
        assert_contains "$(tmux show-option -gqv 'status-format[0]')" "renderer.sh"
        "status-format[0] installs the renderer";
        assert_eq "$(tmux show-option -gqv key-table)" "livepicker" "key-table switched";
        assert_eq "$(tmux show-option -gqv @livepicker-mode)" "on" "mode armed".
  - WHY these signals: FINDING 4 (default status=on->2; activate installs
        status-format[0]=#(renderer.sh); key-table->livepicker; mode=on LAST).
  - DO NOT: attach is REQUIRED (display-message in STEP 2); quote 'status-format[0]'.

Task 3: test_typing_filters (PRD §15.17 bullet 2)
  - IMPLEMENT: attach_test_client; `tmux new-session -d -s syslog -x 120 -y 40` +
        `tmux new-session -d -s blog -x 120 -y 40` (BEFORE activate — FINDING 5);
        run livepicker.sh; `input-handler.sh type l`; `type o`; `type g`;
        `out="$("$LIVEPICKER_SCRIPTS/renderer.sh")"`; assert_contains "$out" "syslog"
        "filtered view shows syslog"; assert_contains "$out" "blog" "...shows blog";
        NEGATIVE (FINDING 9): `case "$out" in *alpha*) fail "alpha leaked" ;; esac`
        and the same for *driver*; assert_eq "$(tmux show-option -gqv @livepicker-index)"
        "0" "type resets index to top match".
  - WHY: the list is captured at activate; renderer filters case-insensitively; each
        `type` sets index=0.
  - DO NOT: add syslog/blog AFTER activate (they won't be in the list); use grep -v.

Task 4: test_nav_moves_selection (PRD §15.17 bullet 3)
  - IMPLEMENT: attach_test_client; run livepicker.sh; assert_eq "@livepicker-linked-id"
        "" "self-session initial preview leaves no link"; read
        `alpha_wid="$(tmux list-windows -t =alpha -F '#{window_id}' -f '#{window_active}')"`
        (DYNAMIC — FINDING 6); `input-handler.sh next-session`;
        assert_eq "$(tmux show-option -gqv @livepicker-linked-id)" "$alpha_wid" "preview
        linked alpha's window"; read beta_wid the same way; `input-handler.sh next-session`;
        assert_eq "$(tmux show-option -gqv @livepicker-linked-id)" "$beta_wid" "preview
        linked beta's window"; (optional) assert client still on driver
        (assert_eq "$(tmux display-message -p '#{session_name}')" "driver" "nav never switches").
  - WHY: nav wraps the filtered list; preview.sh links the target's window + sets
        linked-id; Invariant A (no switch-client).
  - DO NOT: hardcode @1/@2 (global ids; read live); assert linked-id after the
        SELF wrap without accounting for the clear.

Task 5: test_confirm_lands (PRD §15.17 bullet 4)
  - IMPLEMENT: attach_test_client; run livepicker.sh; (optional capture linked_id
        before confirm for the FINDING 1/2 regression); `input-handler.sh
        next-session` (highlight -> alpha); `input-handler.sh confirm`;
        assert_eq "$(tmux display-message -p '#{session_name}')" "alpha" "client landed
        on the confirmed target"; `lp_runtime_cleared || fail "picker torn down"`.
        (OPTIONAL regression: after confirm, assert the driver does NOT still hold
        the preview window — `case "$(tmux list-windows -t driver -F '#{window_id}')"
        in *"$linked_id"*) fail "driver not cleaned (FINDING 1/2)" ;; esac`.)
  - WHY: confirm resolves the target, switch-client ONCE (the only switch), restore
        keep clears state. lp_runtime_cleared (FINDING 2) — NOT grep==0.
  - DO NOT: confirm on the initial highlight (driver) — navigate to a real target
        first; assert grep -c '@livepicker' == 0 (FALSE-FAILS — FINDING 2).

Task 6: test_escape_restores (PRD §15.17 bullet 5)
  - IMPLEMENT: attach_test_client; capture orig DYNAMICALLY BEFORE activate:
        orig_sess="$(tmux display-message -p '#{session_name}')" (driver),
        orig_win="$(tmux display-message -p '#{window_id}')" (read live — the active
        window, NOT assumed @0), orig_status="$(tmux show-option -gqv status)" (on),
        orig_kt="$(tmux show-option -gqv key-table)" (root); run livepicker.sh;
        `input-handler.sh next-session` (link a preview window — exercises restore's
        unlink + layout); `input-handler.sh cancel` (filter empty -> full teardown);
        assert_eq "$(tmux display-message -p '#{session_name}')" "$orig_sess" "session
        restored"; assert_eq "$(tmux display-message -p '#{window_id}')" "$orig_win"
        "window restored"; assert_eq "$(tmux show-option -gqv status)" "$orig_status"
        "status restored"; assert_eq "$(tmux show-option -gqv key-table)" "$orig_kt"
        "key-table restored"; `lp_runtime_cleared || fail "picker torn down after cancel"`.
  - WHY: cancel is two-step (empty filter -> full cancel); restore switches back to
        ORIG_SESSION (dedup), selects ORIG_WINDOW, restores status/key-table, clears
        state. The nav-then-cancel variant is STRONGER (matches "escape after
        browsing") than activate->cancel.
  - DO NOT: cancel with a non-empty filter (that only clears the query); assume
        orig_win==@0.

Task 7: VALIDATE (Level 1 lint + Level 2 suite green + Level 4 non-pollution)
  - RUN: bash -n + shellcheck on the file; `bash tests/run.sh` (expect all five
        PASS + test_self PASS, exit 0); snapshot `/usr/bin/tmux list-sessions`
        before/after a full run.sh and assert byte-identical (non-pollution);
        `git diff --stat` shows ONLY tests/test_functional.sh added.
```

### Implementation Patterns & Key Details

#### The file skeleton + the critical helper (Tasks 1)

```bash
#!/usr/bin/env bash
# tests/test_functional.sh — tmux-livepicker PRD §15.17 Functional validation (P1.M7.T3.S1).
#
# SOURCED by run.sh (NEVER executed directly). Defines five test_* functions that
# drive the COMPLETE real plugin (scripts/livepicker.sh -> input-handler.sh ->
# renderer.sh -> preview.sh -> restore.sh, all COMPLETE P1.M1-M6) DIRECTLY (NOT via
# keypress — work-item §1) against the socket-isolated server the harness provides
# (tests/setup_socket.sh P1.M7.T1.S1 + tests/helpers.sh P1.M7.T2.S1), and assert
# observable tmux state. Each test attaches a real client (the scripts need one),
# exercises one §15.17 bullet, and signals pass/fail via fail/assert_* (which set
# TEST_STATUS; run.sh reads it in the current shell).
#
# CONTRACT: run.sh sources setup_socket.sh + helpers.sh + every tests/test_*.sh,
# then PER test calls setup_test "lp-$$-<name>" (-> fresh isolated socket + PATH
# shim + baseline fixtures driver/alpha/beta) -> resets TEST_STATUS=pass -> runs
# the test_* in the CURRENT shell -> reads TEST_STATUS -> teardown_test. So when a
# test_* runs: bare `tmux` hits the isolated socket; $LIVEPICKER_SCRIPTS,
# attach_test_client, fail/pass/assert_eq/assert_contains are all IN SCOPE; this
# file SOURCES NOTHING and calls NO setup_test/teardown_test.
#
# CRITICAL (research FINDING 2): the isolated server sources the user tmux.conf ->
# @livepicker-fg "#ffffff" + @livepicker-key Space are pre-set (dormant §11 config).
# clear_all_state (CORRECTION A) PRESERVES config -> after confirm/cancel those two
# options REMAIN. So `show-options -g | grep livepicker` is NOT empty; the work-
# item's literal "no @livepicker-*" FALSE-FAILS. Use lp_runtime_cleared() (runtime+
# orig keys unset), NOT grep==0.
#
# `set -u` is INHERITED from helpers.sh (do NOT re-declare; mirror test_self.sh).
# shellcheck disable=SC2154,SC2016,SC2034,SC2086
#   SC2154: assert_*/attach_test_client/$LIVEPICKER_SCRIPTS/$TEST_DRIVER_SESSION are
#           defined by run.sh's sources, not in this file.

# lp_runtime_cleared — TRUE (rc 0) iff every picker-INTERNAL key is unset after a
# teardown (confirm keep / cancel). CORRECTION A (state.sh): clear_all_state clears
# ONLY the 5 runtime keys + @livepicker-orig-* and PRESERVES §11 config. In THIS
# env the dormant @livepicker-fg/@livepicker-key (sourced from the user tmux.conf)
# legitimately REMAIN -> the broad `grep livepicker` is non-empty (FINDING 2). This
# helper is the CORRECT "picker torn down" predicate.
lp_runtime_cleared() {
	local k
	for k in @livepicker-mode @livepicker-list @livepicker-filter \
	         @livepicker-index @livepicker-linked-id; do
		[ -z "$(tmux show-option -gqv "$k" 2>/dev/null)" ] || return 1
	done
	# No @livepicker-orig-* saved-state keys either (grep is READ-ONLY here; safe).
	[ -z "$(tmux show-options -g 2>/dev/null | grep '@livepicker-orig-')" ] || return 1
	return 0
}
```

#### test_activate_grows_status (Task 2)

```bash
test_activate_grows_status() {
	attach_test_client
	"$LIVEPICKER_SCRIPTS/livepicker.sh"
	# PRD §15.17 bullet 1: activation grows the status bar; line 1 shows the picker.
	assert_eq "$(tmux show-option -gqv status)" "2" "status grew to two lines"
	assert_contains "$(tmux show-option -gqv 'status-format[0]')" "renderer.sh" \
		"status-format[0] installs the renderer"
	assert_eq "$(tmux show-option -gqv key-table)" "livepicker" "key-table switched to livepicker"
	assert_eq "$(tmux show-option -gqv @livepicker-mode)" "on" "@livepicker-mode armed"
}
```

#### test_typing_filters (Task 3)

```bash
test_typing_filters() {
	attach_test_client
	# Add 'log'-matching fixtures BEFORE activate: @livepicker-list is captured at
	# activate time; the baseline driver/alpha/beta contain no 'log' substring.
	tmux new-session -d -s syslog -x 120 -y 40
	tmux new-session -d -s blog   -x 120 -y 40
	"$LIVEPICKER_SCRIPTS/livepicker.sh"
	"$LIVEPICKER_SCRIPTS/input-handler.sh" type l
	"$LIVEPICKER_SCRIPTS/input-handler.sh" type o
	"$LIVEPICKER_SCRIPTS/input-handler.sh" type g
	# PRD §15.17 bullet 2: typing filters the list and updates the highlight.
	out="$("$LIVEPICKER_SCRIPTS/renderer.sh")"
	assert_contains "$out" "syslog" "filtered view shows the 'log' match syslog"
	assert_contains "$out" "blog"   "filtered view shows the 'log' match blog"
	# NEGATIVE (FINDING 9): non-matches must NOT appear (inline case — no subprocess).
	case "$out" in *alpha*)  fail "alpha leaked into the filtered view"  ;; esac
	case "$out" in *driver*) fail "driver leaked into the filtered view" ;; esac
	assert_eq "$(tmux show-option -gqv @livepicker-index)" "0" "type resets highlight to the top match"
}
```

#### test_nav_moves_selection (Task 4)

```bash
test_nav_moves_selection() {
	attach_test_client
	"$LIVEPICKER_SCRIPTS/livepicker.sh"
	# Activate's first preview is the SELF-session (driver) -> no link yet.
	assert_eq "$(tmux show-option -gqv @livepicker-linked-id)" "" "initial self-session preview leaves no link"
	# PRD §15.17 bullet 3: nav moves the selection; the preview follows live. Window
	# ids are GLOBAL — read the target's id DYNAMICALLY (FINDING 6).
	alpha_wid="$(tmux list-windows -t =alpha -F '#{window_id}' -f '#{window_active}')"
	"$LIVEPICKER_SCRIPTS/input-handler.sh" next-session
	assert_eq "$(tmux show-option -gqv @livepicker-linked-id)" "$alpha_wid" \
		"preview linked alpha's window (highlight moved to alpha)"
	beta_wid="$(tmux list-windows -t =beta -F '#{window_id}' -f '#{window_active}')"
	"$LIVEPICKER_SCRIPTS/input-handler.sh" next-session
	assert_eq "$(tmux show-option -gqv @livepicker-linked-id)" "$beta_wid" \
		"preview linked beta's window (highlight moved to beta)"
	# Invariant A: nav never switches the client (still on driver).
	assert_eq "$(tmux display-message -p '#{session_name}')" "driver" \
		"navigation never calls switch-client (Invariant A)"
}
```

#### test_confirm_lands (Task 5)

```bash
test_confirm_lands() {
	attach_test_client
	"$LIVEPICKER_SCRIPTS/livepicker.sh"
	"$LIVEPICKER_SCRIPTS/input-handler.sh" next-session   # highlight -> alpha
	# PRD §15.17 bullet 4: Enter on a match closes the picker and lands on the session.
	linked_id="$(tmux show-option -gqv @livepicker-linked-id)"   # for the regression
	"$LIVEPICKER_SCRIPTS/input-handler.sh" confirm
	assert_eq "$(tmux display-message -p '#{session_name}')" "alpha" \
		"confirm landed the client on the target (alpha)"
	lp_runtime_cleared || fail "picker torn down (runtime+orig cleared; §11 config may remain — FINDING 2)"
	# Optional regression (confirm_mock FINDING 1/2): the driver must NOT still hold
	# the preview window after a session-mode confirm (switch-before-unlink bug guard).
	case "$(tmux list-windows -t driver -F '#{window_id}')" in
		*"$linked_id"*) fail "driver not cleaned of the preview window (FINDING 1/2)" ;;
	esac
}
```

#### test_escape_restores (Task 6)

```bash
test_escape_restores() {
	attach_test_client
	# Capture the client's ORIGINAL state DYNAMICALLY before activate (driver's
	# active window is the 'extra' window, NOT @0 — read it live; FINDING 8).
	orig_sess="$(tmux display-message -p '#{session_name}')"
	orig_win="$(tmux display-message -p '#{window_id}')"
	orig_status="$(tmux show-option -gqv status)"
	orig_kt="$(tmux show-option -gqv key-table)"
	"$LIVEPICKER_SCRIPTS/livepicker.sh"
	"$LIVEPICKER_SCRIPTS/input-handler.sh" next-session   # link a preview window
	# PRD §15.17 bullet 5: Escape closes the picker; client back on the original
	# session/window; status restored. cancel is two-step: the empty filter (activate
	# sets "") -> full restore cancel; nav did not change the filter.
	"$LIVEPICKER_SCRIPTS/input-handler.sh" cancel
	assert_eq "$(tmux display-message -p '#{session_name}')" "$orig_sess" "session restored to origin"
	assert_eq "$(tmux display-message -p '#{window_id}')" "$orig_win" "window restored to origin"
	assert_eq "$(tmux show-option -gqv status)" "$orig_status" "status restored to origin"
	assert_eq "$(tmux show-option -gqv key-table)" "$orig_kt" "key-table restored to origin"
	lp_runtime_cleared || fail "picker torn down after cancel"
}
```

NOTE for the implementer:
- This is ONE NEW FILE under `tests/`. No edits to `setup_socket.sh`/`helpers.sh`/
  `run.sh`, no `scripts/` edits, no PRD/tasks edits.
- The file is SOURCED by run.sh — define `test_*` + `lp_runtime_cleared` ONLY; NO
  side effects on source; NO `setup_test`/`teardown_test`; NO sourcing.
- `set -u` is inherited; do NOT re-declare it. Do NOT add `set -e`/`pipefail`.
- Signal failure ONLY via `fail`/`assert_*` (never `exit`).
- The single most important correctness point is FINDING 2: use `lp_runtime_cleared`
  for "picker torn down", NEVER `grep -c '@livepicker' == 0` (the dormant config
  makes that false-fail).

### Integration Points

```yaml
NEW FILE (the ONLY file this task creates):
  - tests/test_functional.sh: sourced-by-run.sh test bodies (5 test_* + lp_runtime_cleared).
        No side effects on source; drives the real scripts against the isolated socket.

CONSUMES (the INPUT — COMPLETE/READ-ONLY; do NOT edit):
  - tests/setup_socket.sh (T1.S1): setup_socket/teardown_socket + attach_test_client/
        detach_test_client + the TEST_*/TMUX_*/REAL_TMUX/LIVEPICKER_* exports + the
        baseline fixtures. run.sh's setup_test calls setup_socket per test.
  - tests/helpers.sh (T2.S1): fail/pass/assert_eq/assert_contains + setup_test/
        teardown_test + TEST_STATUS. In scope (run.sh sources helpers.sh).
  - tests/run.sh (T2.S1): the runner — sources the 3 files, discovers test_*, runs
        each in a per-test fresh-socket cycle, exits 0/1.
  - scripts/* (P1.M1-M6, COMPLETE/IMMUTABLE): livepicker.sh/input-handler.sh/
        renderer.sh/preview.sh/restore.sh — driven directly, never edited.

CONSUMERS (downstream — NOT this task's responsibility):
  - `bash tests/run.sh` discovers + runs test_functional.sh's test_* alongside
        T2.S1's test_self + the future T4-T6 test_*.sh (each hermetic).

PROVIDES:
  - 5 PRD §15.17 Functional test_* functions + the lp_runtime_cleared predicate.
  - (Reusable by T4-T6 if they want the same CORRECTION-A-correct teardown check.)

DATABASE / MIGRATIONS / ROUTES / CONFIG: none. No @livepicker-* writes on the REAL
        server (the isolated socket only). The only real-server contact is READ-ONLY
        (snapshot /usr/bin/tmux list-sessions around run.sh — a validation step).
```

## Validation Loop

### Level 1: Syntax & Style (Immediate Feedback)

```bash
# Run after creating the file — fix before proceeding.
bash -n tests/test_functional.sh
shellcheck tests/test_functional.sh
#   expect 0 findings (file-level `# shellcheck disable=SC2154,SC2016,SC2034,SC2086`
#   is OK — mirror setup_socket.sh/helpers.sh).

# Tabs-not-spaces sanity (shfmt NOT installed):
grep -Pn '^    ' tests/test_functional.sh && echo "FAIL: 4-space indent, use tabs" || echo "OK: tabs only"

# House style: set -u inherited (NOT re-declared); NO set -e/pipefail statement:
grep -nE 'set -e|set -o pipefail|^set -u' tests/test_functional.sh \
  && echo "FAIL: found a disallowed set statement (set -u is inherited; -e/pipefail forbidden)" \
  || echo "OK: no set statement (set -u inherited)"

# No side effects on source: a bare source must NOT start a server, call setup_test,
# print, or run a test. (run.sh owns the per-test cycle.)
out="$( source tests/test_functional.sh 2>&1 )"
[ -z "$out" ] && echo "OK: source is silent" || echo "FAIL: source printed: $out"
( source tests/test_functional.sh; declare -F test_activate_grows_status test_typing_filters \
    test_nav_moves_selection test_confirm_lands test_escape_restores lp_runtime_cleared )

# The file SOURCES NOTHING (run.sh owns sourcing):
grep -nE '^[[:space:]]*source |^[[:space:]]*\. ' tests/test_functional.sh \
  && echo "FAIL: test_functional.sh sources something (it must not)" || echo "OK: no sourcing"

# Never exits / never calls setup_test/teardown_test directly:
grep -nE '\bexit\b|setup_test|teardown_test' tests/test_functional.sh \
  && echo "FAIL: test body exits or touches the per-test cycle" || echo "OK: no exit / no setup_test"

# SCOPE: only the one new file added (no harness/scripts/PRD/tasks edits):
git status --porcelain | grep -E '^.M (tests/setup_socket|tests/helpers|tests/run)\.sh|^.M scripts/|PRD\.md|tasks\.json|prd_snapshot' \
  && echo "FAIL: edited an off-limits file" || echo "OK: only tests/test_functional.sh added"
```

### Level 2: The Suite (work-item §4 OUTPUT — runner aggregates)

```bash
# Run the full suite. Expect all five functional tests PASS + T2.S1's test_self PASS,
# summary "N passed, 0 failed", exit 0.
bash tests/run.sh
echo "exit=$?"
# Expected (order may vary by sort):
#   PASS  test_activate_grows_status
#   PASS  test_confirm_lands
#   PASS  test_escape_restores
#   PASS  test_nav_moves_selection
#   PASS  test_self
#   PASS  test_typing_filters
#   ----
#   6 passed, 0 failed (of 6)
#   exit=0
#
# If a test FAILS: run.sh prints "FAIL  <name>" + the ASSERT FAIL line on stderr.
#   - "picker torn down" failure with @livepicker-fg/@livepicker-key present -> you
#     used grep==0 instead of lp_runtime_cleared (FINDING 2). FIX: use the helper.
#   - display-message returned the wrong client -> attach_test_client didn't settle
#     (racy pty); ensure attach_test_client is the FIRST call in the test body.
#   - "alpha leaked into the filtered view" -> you added syslog/blog AFTER activate
#     (FINDING 5) OR the filter wasn't applied; add them BEFORE livepicker.sh.
```

### Level 3: Per-test targeted proofs (drive the real scripts — smoke-level)

```bash
# Proof each script is reachable + the isolated socket is hit (run from repo root).
# Mirror the harness: source setup_socket + helpers, run ONE test body inline.
# shellcheck disable=SC1091
source tests/setup_socket.sh
# shellcheck disable=SC1091
source tests/helpers.sh
setup_test "lp-manual-$$"
attach_test_client
echo "sessions: $(tmux list-sessions -F '#{session_name}' | tr '\n' ' ')"   # driver alpha beta (isolated)
"$LIVEPICKER_SCRIPTS/livepicker.sh"
echo "status=[$(tmux show-option -gqv status)] kt=[$(tmux show-option -gqv key-table)] mode=[$(tmux show-option -gqv @livepicker-mode)]"
echo "sf0=[$(tmux show-option -gqv 'status-format[0]')]"
# Expected: status=[2] kt=[livepicker] mode=[on] ; sf0 contains renderer.sh.
teardown_test
# (Re-run with run.sh for the full assertion suite — this just proves reachability.)
```

### Level 4: Creative & Domain-Specific Validation (PRD §15 non-pollution + robustness)

```bash
# PRD §15 invariant (the real server is untouched) — snapshot the user's REAL
# session list around a FULL run.sh invocation (multiple per-test setup/teardown
# cycles). This is the gold-standard proof the harness + these tests never touch
# the real server.
real_before="$(/usr/bin/tmux list-sessions -F '#{session_name}' | sort)"
bash tests/run.sh >/dev/null 2>&1
real_after="$(/usr/bin/tmux list-sessions -F '#{session_name}' | sort)"
[ "$real_before" = "$real_after" ] && echo "OK: real server byte-identical before/after" \
  || { echo "FAIL: real server changed"; diff <(echo "$real_before") <(echo "$real_after"); }

# Robustness: lp_runtime_cleared is CORRECTION-A-correct — after a confirm it is
# true even though @livepicker-fg/@livepicker-key (dormant config) remain. Prove it
# does NOT false-pass: after an ACTIVE picker (no teardown) it must be FALSE.
# shellcheck disable=SC1091
( source tests/setup_socket.sh; source tests/helpers.sh
  setup_test "lp-neg-$$"; attach_test_client
  "$LIVEPICKER_SCRIPTS/livepicker.sh"   # picker ACTIVE -> runtime keys set
  if lp_runtime_cleared; then echo "FAIL: lp_runtime_cleared true with picker active (false-pass)"; else echo "OK: lp_runtime_cleared correctly false while picker active"; fi
  teardown_test )

# Robustness: each test is hermetic — a prior test's mutation (e.g. test_typing_filters
# leaves @livepicker-filter if it crashed) must NOT affect the next, because run.sh
# gives each a fresh server. (Implicitly proven by Level 2 running them in series.)
```

## Final Validation Checklist

### Technical Validation

- [ ] Level 1 passes: `bash -n` + `shellcheck` (0 new findings); tabs only; `set -u`
      inherited (no `set -e`/`pipefail`); no sourcing; no `exit`/`setup_test`.
- [ ] Level 2 passes: `bash tests/run.sh` -> all five PASS + test_self PASS, exit 0.
- [ ] Level 3 passes: the inline manual probe shows status=2/key-table=livepicker/
      mode=on + status-format[0]~renderer.sh after a real activate on the isolated socket.
- [ ] Level 4 passes: real server byte-identical before/after a full run; lp_runtime_cleared
      is correctly false while the picker is active (no false-pass).
- [ ] `git status --porcelain` shows ONLY `tests/test_functional.sh` added.

### Feature Validation

- [ ] **test_activate_grows_status**: status==2, status-format[0]~renderer.sh,
      key-table==livepicker, @livepicker-mode==on after `livepicker.sh`.
- [ ] **test_typing_filters**: after typing 'log', the renderer output shows ONLY
      the 'log'-matching sessions (syslog/blog); @livepicker-index==0.
- [ ] **test_nav_moves_selection**: next-session moves the highlight; @livepicker-linked-id
      == each target's live window id; the client never switches (Invariant A).
- [ ] **test_confirm_lands**: confirm lands the client on the target; the picker's
      runtime+orig state is cleared (lp_runtime_cleared — NOT grep==0).
- [ ] **test_escape_restores**: cancel restores session/window/status/key-table to
      the captured originals; runtime state cleared.
- [ ] Error cases handled via `fail` (never `exit`); the suite aggregates exit 0/1.

### Code Quality Validation

- [ ] Mirrors `tests/test_self.sh`'s sourced-by-run.sh style (no side effects on
      source; inherited `set -u`; shellcheck disable header; tabs; local).
- [ ] File placement matches the desired tree (`tests/test_functional.sh`).
- [ ] Drives the REAL scripts (no mocks/stubs of the plugin); uses the harness's
      isolation + client + assert helpers (no re-implementation).
- [ ] Anti-patterns avoided (check against Anti-Patterns section).
- [ ] `lp_runtime_cleared` is the CORRECTION-A-correct teardown predicate (FINDING 2).

### Documentation & Deployment

- [ ] Code is self-documenting (inline comments cite the findings: FINDING 2/3/5/6/8/9).
- [ ] DOCS: Mode A — none (test infra). No README/CHANGELOG changes (P1.M8 owns those).
- [ ] No new environment variables (uses only the harness exports).

---

## Anti-Patterns to Avoid

- ❌ **Don't assert `grep -c '@livepicker' == 0` for "picker torn down".** The
  isolated server sources the user tmux.conf, which pre-sets dormant `@livepicker-fg`
  /`@livepicker-key`; clear_all_state (CORRECTION A) preserves them. It FALSE-FAILS.
  Use `lp_runtime_cleared` (the 5 runtime keys + @livepicker-orig-* unset) — FINDING 2.
- ❌ **Don't call `livepicker.sh`/`confirm`/`cancel` without `attach_test_client`.**
  They use `display-message -p`/`switch-client`/`refresh-client -S` which REQUIRE a
  client; without one, display-message is non-deterministic and the test is flaky.
  Attach FIRST in every test body — FINDING 3.
- ❌ **Don't add fixtures AFTER activate for a filtering test.** `@livepicker-list`
  is captured at activate time. Add 'log'-matching sessions (syslog/blog) BEFORE
  `livepicker.sh` — FINDING 5.
- ❌ **Don't hardcode window ids (@1, @2).** They are server-global + depend on the
  fixture seed order. Read the target's id live via `list-windows -t =<sess> -F
  '#{window_id}' -f '#{window_active}'` — FINDING 6.
- ❌ **Don't `cancel` with a non-empty filter and expect teardown.** `cancel` is
  two-step: non-empty -> clear query (picker OPEN); empty -> full cancel. Ensure
  the filter is empty when you want a teardown — FINDING 8.
- ❌ **Don't `exit` / `return`-nonzero-to-abort in a test body.** run.sh reads
  `TEST_STATUS` in the CURRENT shell; a bare `exit` kills the runner. Signal failure
  ONLY via `fail`/`assert_*` (resurrect `fail_helper` contract).
- ❌ **Don't source anything / call `setup_test`/`teardown_test`/re-declare `set -u`.**
  The file is sourced by run.sh; the helpers, the client, `$LIVEPICKER_SCRIPTS`, and
  `set -u` are all in scope. Define `test_*` + `lp_runtime_cleared` only.
- ❌ **Don't add `set -e` / `set -o pipefail` / use `echo | grep`.** House style is
  `set -u` only (system_context §9); `show-option`/`has-session` legitimately return
  nonzero; pipefail would abort on the first nonzero tmux rc. Use inline `case` for
  negative substring (no subprocess) — FINDING 9.
- ❌ **Don't edit `setup_socket.sh`/`helpers.sh`/`run.sh`, any `scripts/*`, `PRD.md`,
  `tasks.json`, `prd_snapshot.md`, or `.gitignore`.** This task ADDS exactly ONE
  file: `tests/test_functional.sh`.

---

## Confidence Score

**9/10** for one-pass implementation success.

This is one NEW sourced test file (zero edits to existing code) driving the
COMPLETE plugin, and every driving pattern + assertion target is **empirically
verified**: the harness (T1.S1/T2.S1) is COMPLETE and read in full; the two P1.M6
throwaway mocks (`confirm_mock.sh`/`cancel_mock.sh`) pre-figured the exact
activate→input→renderer→assert sequences; and a live probe confirmed the isolated
server's defaults (status=on→2, key-table=root, dormant `@livepicker-fg`/
`@livepicker-key` present — the source of FINDING 2). The ready-to-paste test
bodies leave no ambiguity, and the five non-obvious traps (FINDING 2 grep-trap →
`lp_runtime_cleared`; FINDING 3 REQUIRED client; FINDING 5 fixtures-before-activate;
FINDING 6 dynamic window ids; FINDING 8 two-step cancel) are each called out with
the exact fix. The residual risk (-1) is the inherited `script -qec` pty-attach
timing (0.5s settle in `attach_test_client`, owned by T1.S1) which is occasionally
racy under load — mitigated by making `attach_test_client` the FIRST call in each
test body. The parallel-execution dependency on T2.S1 (`helpers.sh`/`run.sh`) is
clean: this file only defines `test_*` that consume the in-scope helpers; it
composes regardless of when run.sh lands (run.sh's `nullglob` glob picks up
`test_functional.sh` automatically once it exists).
