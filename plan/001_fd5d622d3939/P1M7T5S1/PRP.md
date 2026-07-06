# PRP — P1.M7.T5.S1: `tests/test_pollution.sh`

---

## Goal

**Feature Goal**: **CREATE** the PRD §15.18 *Pollution (the core invariant)* validation
test suite — `tests/test_pollution.sh` — a single **sourced** bash file that defines
one local helper that installs a **stand-in `tmux-session-history` recorder**
(`lp_install_history_recorder`) + two tiny fixture/target helpers + three `test_*`
functions (`test_browse_cancel_no_pollution`, `test_browse_confirm_one_entry`,
`test_toggle_after_confirm`) which drive the COMPLETE real plugin
(`scripts/livepicker.sh` → `input-handler.sh` → `preview.sh` → `restore.sh`,
all COMPLETE P1.M1–M6) **directly** (contract §1: the scripts, NOT via keypress)
against the **socket-isolated** tmux server provided by the COMPLETE harness
(`tests/setup_socket.sh` P1.M7.T1.S1 + `tests/helpers.sh` P1.M7.T2.S1), and **assert
the core invariant** (PRD §4 / §14): **browsing the picker must not pollute
session-history, and the only navigation is the one confirm-time switch.** Each test
gets a fresh isolated server (run.sh's per-test `setup_test`/`teardown_test` cycle),
creates its fixtures **before** attaching the client (the load-bearing order), installs
the recorder, exercises one PRD §15.18 bullet, and signals pass/fail via `fail`/`assert_*`
(which set `TEST_STATUS`). `bash tests/run.sh` discovers and runs them and exits 0/1.

The crux of this task is **the MOCKING**: the real `tmux-session-history` plugin is NOT
loaded on the isolated socket (contract §1 RESEARCH NOTE), so the test installs a
**stand-in recorder** on `client-session-changed` that faithfully mirrors the real
engine's dedup + forward-collapse + `prev`-pointer semantics (read in full from the real
`scripts/session_history.sh`). This is PRD §15.18's "with `tmux-session-history`
installed" clause, satisfied deterministically without loading the real plugin.

**Deliverable** (ONE new file): `tests/test_pollution.sh` — a SOURCED bash library
defining exactly the three `test_*` functions (discovered by run.sh's
`compgen -A function | grep '^test_'`) + the `lp_install_history_recorder`,
`lp_poll_make_fixtures`, `lp_poll_resolve_target` helpers. It SOURCES NOTHING (run.sh
sources `setup_socket.sh` + `helpers.sh` + `test_*.sh` first; the assert helpers,
`$LIVEPICKER_SCRIPTS`, `$TEST_DRIVER_SESSION`, `$TMUX_SOCK_DIR`, `attach_test_client`,
and the isolated bare-`tmux` shim are all in scope before any `test_*` runs). No side
effects on source (defines functions only).

**Success Definition**:
- `bash -n` + `shellcheck` pass on `tests/test_pollution.sh` (0 findings beyond a
  file-level `# shellcheck disable=SC2154,SC2016,SC2034,SC2086`; tabs only; `set -u`
  inherited — NOT re-declared, mirror `test_self.sh`/`test_functional.sh`).
- `bash tests/run.sh` runs all three `test_*` (plus T2.S1's `test_self` + T3.S1's five
  + T4.S1's four), each prints **PASS**, the suite summary is `N passed, 0 failed`,
  exit **0**.
- Each `test_*` installs the faithful recorder, drives the REAL plugin (activate →
  5× `next-session` → cancel/confirm/toggle) against the isolated socket, and asserts
  the exact PRD §15.18 observable signals:
  - **browse+cancel** → `@test-hist` UNCHANGED + client back on the original session;
  - **browse+confirm** → EXACTLY ONE new entry appended (the target), no intermediates;
  - **toggle after confirm** → returns to the pre-pick session.
- **The real user server is provably untouched**: `/usr/bin/tmux list-sessions` is
  byte-identical before/after a full `run.sh` invocation (the harness owns isolation;
  the recorder's baked absolute shim path guarantees it never hits `/usr/bin/tmux`).
- `git diff --stat` shows ONLY `tests/test_pollution.sh` added (NO edits to
  `setup_socket.sh`/`helpers.sh`/`run.sh`, NO `scripts/*`, NO PRD/tasks — FORBIDDEN).

## User Persona (if applicable)

**Target User**: the contributor running the suite (`bash tests/run.sh`) and the future
maintainer extending the pollution checks. The test file has no end-user surface
(DOCS: Mode A — none; it is test infra).

**Use Case**: a contributor runs `bash tests/run.sh`; run.sh gives each `test_*`
function a fresh isolated socket, the function creates fixtures, attaches a client,
installs the session-history stand-in recorder, drives the real plugin (activate +
navigate + cancel/confirm/toggle), and asserts `@test-hist` / the client's session;
run.sh reports PASS/FAIL + exits 0/1. Each test is hermetic (per-test fresh server) so a
recorder mutation in one cannot leak into another.

**User Journey** (per test): `setup_test` (run.sh) → `lp_poll_make_fixtures` (BEFORE
attach) → `attach_test_client` → `lp_install_history_recorder` → snapshot `@test-hist`
→ `livepicker.sh` activate → 5× `input-handler.sh next-session` → (cancel |
confirm | confirm+toggle) → `tmux show-option`/`display-message` → `assert_*`/`fail` →
(control returns to run.sh) → `teardown_test`.

**Pain Points Addressed**:
- (a) **No pollution-semantics tests existed.** T3.S1's `test_nav_moves_selection` asserts
  the *integration* that navigation never switches the client (Invariant A, one assertion).
  T5.S1 owns the **end-to-end pollution proof** — that the *session-history timeline* and
  the *toggle pointer* are untouched by browsing, and that exactly one navigation is
  recorded on confirm. This is PRD §4's "single most important invariant," and these
  three tests are its proof.
- (b) **The real `tmux-session-history` engine is not on the isolated socket.** Loading
  it would couple the test to an external plugin's internals. The work-item recommends a
  stand-in "for determinism." This PRP ships a stand-in that mirrors the real engine's
  `do_hook` (same-session short-circuit + forward-collapse) + `do_toggle` exactly — read
  in full from the real `scripts/session_history.sh` (research FINDING 1).
- (c) **The `display-message` pointer trap.** `tmux display-message -p '#{session_name}'`
  (no `-t`) returns the LAST-CREATED/switched session, NOT necessarily the client's. If
  fixtures are created AFTER attach, `livepicker.sh` activate saves the wrong
  `ORIG_SESSION` → cancel's same-session switch becomes a real navigation → **false
  pollution**. This PRP encodes the verified fix: create fixtures BEFORE attach (research
  FINDING 3).

## Why

- **PRD §15.18 Pollution (the core invariant)** is the controlling spec (selected
  `h2.15/h3.18`): its three bullets map 1:1 to the three `test_*` functions. PRD §4
  (selected `h2.4`) is "the single most important invariant" this suite proves — browsing
  must not change the client's session. PRD §14 (selected `h2.14`) is the pollution +
  compatibility analysis that enumerates the exact assertions (browse → 0 entries; confirm
  → exactly 1; cancel → exactly 0; toggle → returns to pre-pick). PRD §5/§6 (selected
  `h2.5`/`h2.6`) describe the activate/navigation/confirm/cancel flows the tests drive.
- **Scope cohesion.** T5.S1 is the Pollution cluster of module P1.M7 (Validation).
  T1.S1 owns socket isolation (COMPLETE); T2.S1 owns assertions + discovery + the runner
  (COMPLETE); T3.S1 owns the Functional test bodies (COMPLETE); T4.S1 owns the Preview
  test bodies (COMPLETE). T5.S1 owns the POLLUTION test bodies (this file). T6 (restore /
  key-repurpose / create-on-enter) is a SIBLING test file — hermetic via run.sh's per-test
  cycle. This task does NOT own those clusters or the harness.
- **T3.S1's `test_nav_moves_selection`** already asserts the nav-never-switches-client
  integration (one `display-message` assertion). T5.S1 does NOT duplicate that; it proves
  the *consequence* on the session-history timeline + toggle — what the integration test
  does NOT cover. These tests install the recorder (which T3.S1 has no need for).

## What

**CREATE** the single file `tests/test_pollution.sh`. No other file is touched
(`setup_socket.sh`/`helpers.sh`/`run.sh` are owned by T1.S1/T2.S1 — COMPLETE,
READ-ONLY here; `scripts/*` are COMPLETE/IMMUTABLE — driven, never edited; PRD/tasks/
prd_snapshot are READ-ONLY). The file is **SOURCED** by `run.sh` (defines `test_*` +
the `lp_*` helpers only; NO side effects on source; NO top-level execution; NO
`setup_test`/`teardown_test` calls — run.sh owns the per-test cycle).

### Success Criteria

- [ ] `tests/test_pollution.sh` passes `bash -n` + `shellcheck` (file-level `disable`
      for SC2154/SC2016/SC2034/SC2086 at most); tabs only; `set -u` inherited (NOT
      re-declared).
- [ ] Defines EXACTLY three `test_*` functions + `lp_install_history_recorder` +
      `lp_poll_make_fixtures` + `lp_poll_resolve_target`. No other top-level code. Each
      `test_*` calls `attach_test_client` (the driven scripts require a client — FINDING 7).
- [ ] Each `test_*` creates its fixtures BEFORE `attach_test_client` (FINDING 3), installs
      the recorder via `lp_install_history_recorder`, drives the real
      `$LIVEPICKER_SCRIPTS/{livepicker,input-handler}.sh` directly; signals failure ONLY
      via `fail`/`assert_*` (NEVER `exit`).
- [ ] `bash tests/run.sh` prints `PASS` for all three (+ the T2/T3/T4 tests), summary
      `N passed, 0 failed`, exit 0.
- [ ] `/usr/bin/tmux list-sessions` byte-identical before/after a full run.
- [ ] `git diff --stat` shows ONLY `tests/test_pollution.sh` added.

## All Needed Context

### Context Completeness Check

_Pass_: a developer who has never seen this repo can implement T5.S1 from
(a) the three ready-to-paste test bodies + the ready-to-paste recorder in "Implementation
Patterns & Key Details"; (b) the 11 findings in `research/pollution_test_findings.md` —
most critically **FINDING 1** (the real engine's exact semantics → the model for the
stand-in), **FINDING 3** (the `display-message` pointer trap → fixtures BEFORE attach),
**FINDING 5** (the recorder must bake the ABSOLUTE shim path), **FINDING 7** (a client is
required), **FINDING 8** (navigation never fires the hook), and **FINDING 9** (the toggle
simulation); and (c) the live probes that confirmed all three scenarios PASS on the
isolated socket. The INPUTS are the COMPLETE harness (`tests/setup_socket.sh` +
`tests/helpers.sh`, read in full), the COMPLETE runner (`tests/run.sh`), and the COMPLETE
driven scripts (`scripts/livepicker.sh`, `input-handler.sh`, `restore.sh`, `filter.sh`).

### Documentation & References

```yaml
# MUST READ — the empirical + idiomatic ground-truth for THIS task (11 findings + PROBES + a
# verified end-to-end run). This is THE source — every design choice below traces to a finding.
- docfile: plan/001_fd5d622d3939/P1M7T5S1/research/pollution_test_findings.md
  why: FINDING 1 (the real engine's do_hook same-session short-circuit + forward-collapse +
        do_toggle -> the EXACT model for the stand-in recorder; @test-* mirrors
        @session-history-*); FINDING 3 (THE load-bearing trap: display-message -p
        '#{session_name}' returns the LAST-CREATED/switched session, NOT the client's ->
        create fixtures BEFORE attach + the recorder's force-switch belt-and-braces);
        FINDING 4 (the recorder is SYNCHRONOUS -> run-shell WITHOUT -b -> the test's next
        read sees the update, NO sleep); FINDING 5 (the recorder MUST bake the ABSOLUTE
        shim path $TMUX_SOCK_DIR/tmux so run-shell hits the isolated socket); FINDING 6
        (write the recorder into $TMUX_SOCK_DIR -> auto-cleaned by teardown_socket);
        FINDING 7 (a CLIENT is required -> attach_test_client FIRST); FINDING 8 (navigation
        NEVER fires client-session-changed -> 0 entries during 5 next-session calls);
        FINDING 9 (the toggle simulation: switch-client -t "=$(show @test-prev)");
        FINDING 10 (house style + the recorder exception: NO set -u in the recorder);
        FINDING 11 (the validated end-to-end run: T1/T2/T3 ALL PASS).
  critical: Read BEFORE writing. FINDING 3 is the single most likely false-fail cause: if
        fixtures are created AFTER attach, activate saves the wrong ORIG_SESSION and cancel
        records a real navigation. The recorder block at the bottom of the research file is
        READY TO PASTE.

# MUST READ — the harness contract this task CONSUMES (read in full; COMPLETE).
- file: tests/setup_socket.sh
  why: the isolation layer. setup_socket seeds driver/alpha/beta baseline (driver + a 2nd
        "extra" multi-pane window) + exports TEST_SOCKET/TMUX_SOCK_DIR/TMUX_SOCKET_PATH/
        REAL_TMUX/LIVEPICKER_ROOT/LIVEPICKER_SCRIPTS/TEST_DRIVER_SESSION("driver")/
        TEST_FIXTURE_SESSIONS("alpha beta"). Provides attach_test_client/detach_test_client
        (the `script`-pty attach — needed because livepicker.sh activate uses display-message
        + refresh-client -S and confirm/cancel use switch-client — FINDING 7). SOURCED
        library (no side effects on source). Mirror its header STYLE (CONTRACT line,
        set -u, tabs, local, shellcheck disable). DO NOT EDIT IT.
  pattern: run.sh's setup_test calls setup_socket per test (fresh -L socket + PATH shim ->
        bare `tmux` hits ONLY the isolated socket). $TMUX_SOCK_DIR is rm -rf'd by
        teardown_socket -> the recorder file written there is auto-cleaned (FINDING 6).
  gotcha: window ids are GLOBAL; this task does NOT read window ids (it reads session names +
        @test-* + @livepicker-list/index) so no id-ordering hazard.

# MUST READ — the assertion + per-test helpers this task CONSUMES (COMPLETE).
- file: tests/helpers.sh
  why: provides fail/pass/assert_eq/assert_contains + setup_test/teardown_test (THIN
        delegates to setup_socket) + the TEST_STATUS global. assert_eq is POSIX equality
        (handles the multi-line @test-hist comparison). In scope because run.sh sources
        helpers.sh before test_*.sh. DO NOT EDIT IT.
  pattern: assert_eq a b msg -> [ "$a" = "$b" ] else fail; the b argument may contain an
        embedded newline ($snap$'\n'$target) -> POSIX = compares the whole string. Signal
        failure ONLY via fail/assert_* (run.sh reads TEST_STATUS in the CURRENT shell).

# MUST READ — the runner (T2.S1; COMPLETE).
- file: tests/run.sh
  why: run.sh sources setup_socket.sh + helpers.sh + every tests/test_*.sh, then PER test:
        setup_test "lp-$$-<name>" (-> fresh isolated socket + PATH shim + baseline fixtures
        driver/alpha/beta) -> resets TEST_STATUS=pass -> runs the test_* in the CURRENT shell
        -> reads TEST_STATUS -> PASS/FAIL -> teardown_test. The CONTRACT for test bodies:
        define test_* ONLY (no side effects on source); signal failure ONLY via fail/assert_*
        (NEVER exit — run.sh reads TEST_STATUS in the current shell; a bare exit kills the
        runner). nullglob globs test_*.sh -> this file is picked up automatically once it exists.
  critical: the test function runs AFTER setup_test (so $LIVEPICKER_SCRIPTS + $TMUX_SOCK_DIR +
        the shim are live) and in the SAME shell as helpers.sh (so assert_* is in scope).
        test_pollution.sh SOURCES NOTHING and calls NO setup_test/teardown_test.

# MUST READ — the sibling functional-test FILE (the CONTRACT for style + attach idiom + the
# integration coverage this task must NOT duplicate).
- file: tests/test_functional.sh
  why: the closest sibling — it ALSO drives livepicker.sh + input-handler.sh with an attached
        client (attach_test_client FIRST) and asserts display-message state. Mirror its header
        style, the lp_*-helper idiom, the dynamic display-message reads, and the inline-`case`
        for negative assertions. Its test_nav_moves_selection ALREADY asserts "navigation never
        switches the client" (one display-message == driver line) — T5.S1 does NOT repeat that
        bare assertion; it proves the session-history-timeline consequence via the recorder.
  critical: copy the "attach_test_client FIRST" + "fixtures before activate" discipline. The
        @livepicker-list is captured at ACTIVATE time (its test_typing_filters creates fixtures
        BEFORE activate) — T5.S1 creates fixtures BEFORE attach (one step earlier, for FINDING 3).

# MUST READ — the sibling preview-test PRP (the structural template for THIS PRP's module).
- docfile: plan/001_fd5d622d3939/P1M7T4S1/PRP.md
  why: T4.S1 is the immediately-preceding test-cluster PRP — mirror its section structure,
        header-contract style, the lp_*-helper idiom, the "SOURCED by run.sh / NO side effects
        on source / NEVER exit" rules, and the 4-level validation loop. T5.S1 is its analog
        for the Pollution cluster.
  critical: T4.S1's preview.sh is CLIENT-INDEPENDENT (no attach_test_client). T5.S1 is the
        OPPOSITE — the driven scripts (livepicker/confirm/cancel) REQUIRE a client. Do NOT copy
        T4.S1's "no attach" rule.

# MUST READ — the scripts this task DRIVES (COMPLETE P1.M4/M5/M6; read the relevant parts).
- file: scripts/livepicker.sh
  why: the activate orchestrator. STEP 2 saves @livepicker-orig-session =
        "$(tmux display-message -p '#{session_name}')" — THIS is the line FINDING 3 is about
        (the pointer must be `driver` at activate time -> fixtures BEFORE attach). T2 builds
        @livepicker-list = list-sessions + resolves @livepicker-index to the current session's
        position. T5 runs preview.sh (self-session, no switch) + sets @livepicker-mode on.
        NONE of activate fires client-session-changed (FINDING 8).
- file: scripts/input-handler.sh
  why: the input dispatcher. next-session = index=(idx+1)%L wrap + preview.sh target + refresh
        (NEVER switch-client — Invariant A). confirm = resolve target=filtered[idx], then
        _confirm_land_on_session: unlink driver preview, switch-client -t "=target" (the ONE
        switch), restore.sh keep. cancel = two-step: non-empty filter -> clear it; EMPTY filter
        -> restore.sh cancel. With no typing (this suite), filter stays "" -> first cancel press
        -> restore.sh cancel directly.
  gotcha: confirm resolves target from filtered[@livepicker-index]. With an EMPTY filter,
        filtered == the full @livepicker-list (filter.sh). lp_poll_resolve_target reads exactly
        those two keys to predict the target.
- file: scripts/restore.sh
  why: the teardown. STEP 3 (cancel branch): `tmux switch-client -t "=$orig_session"` — the
        ONLY switch in the cancel path. Because cancel never switched before, orig_session ==
        the client's current session (driver) -> SAME-SESSION -> the recorder dedups it to 0
        entries (FINDING 1 short-circuit). keep: NO switch (confirm already did the one switch).
        The plugin NEVER touches client-session-changed (it saves/restores only
        session-window-changed in @livepicker-orig-session-window-changed) -> the recorder
        persists across activate/confirm/cancel and catches the confirm + cancel switches.
- file: scripts/filter.sh
  why: lp_build_filtered — the single filter. With an empty filter it matches ALL names (so
        filtered == the full list). lp_poll_resolve_target relies on this property to predict
        confirm's target from @livepicker-list + @livepicker-index WITHOUT sourcing filter.sh
        (house style: test files source nothing).

# MUST READ — the architecture ground-truth.
- docfile: plan/001_fd5d622d3939/architecture/system_context.md
  why: §3 INVARIANT A (select-window/link/unlink NEVER fire client-session-changed -> browsing
        leaves the timeline + toggle untouched; the single confirm switch is the only
        client-session-changed); §6 (tmux-session-history composition: history is newline-
        separated, deduped, in @session-history-hist; driven by client-session-changed; @test-*
        mirrors @session-history-*); §9 (shell style: set -u ONLY; tabs; local; quote
        everything; NO pipefail). §7 (the harness-is-invented reality + the PATH-wrapper shim).
  section: "§3 INVARIANT A", "§6 tmux-session-history composition", "§9 Shell style".

# MUST READ — the PRD sections selected for this work item.
- docfile: PRD.md
  why: §15.18 Pollution (3 bullets -> the 3 test_*); §4 (the core rule: preview without
        switching — the invariant this suite proves); §14 (pollution + compatibility analysis:
        browse=0, confirm=1, cancel=0, toggle returns to pre-pick); §5 (architecture + data
        flow); §6 (behaviors: activation/navigation/confirm/cancel — the flows the tests drive).
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
    setup_socket.sh   # COMPLETE (P1.M7.T1.S1). READ-ONLY. Isolation + exports + attach_test_client.
    helpers.sh        # COMPLETE (P1.M7.T2.S1). READ-ONLY. fail/pass/assert_* + setup_test/teardown_test.
    run.sh            # COMPLETE (P1.M7.T2.S1). READ-ONLY. The runner; sources the 3 files + discovers test_*.
    test_self.sh      # COMPLETE (P1.M7.T2.S1). Sibling test_*.sh.
    test_functional.sh# COMPLETE (P1.M7.T3.S1). Sibling — the attach + display-message idiom source.
    test_preview.sh   # COMPLETE (P1.M7.T4.S1). Sibling — the structural template.
  plan/001_fd5d622d3939/{architecture/*.md, tasks.json, prd_snapshot.md, prd_index.txt}
  plan/001_fd5d622d3939/P1M7T5S1/{PRP.md, research/pollution_test_findings.md}   # THIS
  .gitignore
  # NOTE: tests/test_pollution.sh does NOT exist yet — THIS task creates it.
```

### Desired Codebase tree with files to be added and responsibility of file

```bash
tmux-livepicker/
  tests/
    test_pollution.sh   # NEW (this task). SOURCED by run.sh (defines test_* + lp_* helpers
                        #   only; NO side effects on source). Drives the REAL plugin against the
                        #   isolated socket; installs a stand-in session-history recorder;
                        #   asserts PRD §15.18. attach_test_client FIRST (FINDING 7).
                        #   lp_install_history_recorder() : write $TMUX_SOCK_DIR/session_history_rec.sh
                        #       (bakes the ABSOLUTE shim path — FINDING 5; mirrors the real
                        #       do_hook: same-session short-circuit + forward-collapse + @test-prev —
                        #       FINDING 1); set-hook -g client-session-changed (NO -b — FINDING 4);
                        #       seed @test-hist/current/prev/idx = driver; force switch-client to
                        #       driver (belt-and-braces — FINDING 3).
                        #   lp_poll_make_fixtures() : create nav1..nav5 (BEFORE attach — FINDING 3)
                        #       so the picker has ≥6 sessions and 5 next-session steps never wrap
                        #       back to `driver`.
                        #   lp_poll_resolve_target() : read @livepicker-list + @livepicker-index ->
                        #       the session confirm will land on (empty filter -> full list).
                        #   test_browse_cancel_no_pollution : snapshot @test-hist; activate; 5×
                        #       next-session; assert @test-hist UNCHANGED through nav; cancel; assert
                        #       @test-hist STILL unchanged + client back on driver.
                        #   test_browse_confirm_one_entry : snapshot; activate; 5× next-session;
                        #       resolve target; confirm; assert @test-hist == snapshot + "\n" + target
                        #       (exactly ONE new entry, no intermediates) + client on target.
                        #   test_toggle_after_confirm : activate; 5× next-session; confirm; read
                        #       @test-prev; switch-client -t "=@test-prev"; assert client back on
                        #       the pre-pick session (driver).
```

### Known Gotchas of our codebase & Library Quirks

```bash
# CRITICAL (research FINDING 3 — THE load-bearing trap): `tmux display-message -p
#   '#{session_name}'` (no -t) returns the server's "current session" = the LAST session
#   CREATED or SWITCHED TO, NOT necessarily the attached client's. new-session -d /
#   select-window / new-window / split-window do NOT reset it; only attach + switch-client do.
#   livepicker.sh activate STEP 2 saves ORIG_SESSION via display-message. If fixtures are
#   created AFTER attach_test_client, the pointer is the LAST fixture -> activate saves the
#   WRONG ORIG_SESSION -> cancel's switch-client -t "=$ORIG_SESSION" becomes a REAL navigation
#   -> the recorder appends -> FALSE POLLUTION (the test FALSE-FAILS).
#   THE FIX (verified): create ALL fixtures BEFORE attach_test_client. The attach
#   (tmux attach -t driver) resets the pointer to `driver`. The recorder ALSO force-switches
#   to driver at install (belt-and-braces — a same-session switch the recorder dedups).

# CRITICAL (research FINDING 5 — the recorder MUST bake the ABSOLUTE shim path): the recorder
#   maintains @test-* OPTIONS, so it calls `tmux show-option`/`set-option`. It is invoked by
#   the tmux SERVER's run-shell, which inherits the SERVER's environment — NOT the test shell's
#   PATH. A bare `tmux` inside the recorder may resolve to /usr/bin/tmux (the REAL server) ->
#   would corrupt the user's REAL @session-history-* and miss the isolated socket.
#   THE FIX (verified, mirrors setup_socket's shim-heredoc): write the recorder via an UNQUOTED
#   heredoc so `T="$TMUX_SOCK_DIR/tmux"` bakes the ABSOLUTE shim path at write time (the shim
#   does `exec REAL_TMUX -L TEST_SOCKET`). `\$1` etc. stay literal.

# CRITICAL (research FINDING 4 — the recorder is SYNCHRONOUS): set-hook WITHOUT -b runs the
#   recorder synchronously — the tmux server blocks the triggering switch-client until run-shell
#   completes. So when input-handler.sh confirm/cancel returns, the recorder has ALREADY updated
#   @test-*. The test's very next `tmux show-option -gqv @test-hist` sees the post-switch state.
#   DO NOT use -b (async -> the recorder might not finish before the read -> flaky false-fails).
#   NO sleep is needed.

# CRITICAL (research FINDING 7 — a CLIENT is required): the driven scripts use display-message -p
#   (activate STEP 2), refresh-client -S (activate + nav), and switch-client (confirm/cancel).
#   ALL require an attached client. So EVERY pollution test_* calls attach_test_client
#   (mirrors T3.S1). UNLIKE T4.S1 (preview.sh is client-independent — NO attach).

# CRITICAL (research FINDING 8 — navigation NEVER fires the hook): 5 next-session calls produce
#   ZERO client-session-changed events (next-session -> preview.sh -> link-window + select-window;
#   those fire only window-linked/unlinked + session-window-changed [suppressed by activate], NEVER
#   client-session-changed). So @test-hist is byte-identical before/after the 5 navs. This is the
#   empirical proof of PRD §4/§14 (Invariant A).

# CRITICAL (research FINDING 1 — the stand-in mirrors the real engine): the real
#   tmux-session-history do_hook does: (0) ignore empty `to`; (1) first-fire -> init timeline;
#   (2) SAME-SESSION (to==current) -> return WITHOUT touching the timeline (the dedup that makes
#   cancel -> 0 entries); (3) NAVIGATION -> keep backward HIST[0..idx] MINUS `to`, APPEND `to`,
#   idx=len-1 (forward collapses), @test-prev=from (old current). do_toggle: switch-client -t
#   "$PREV". The stand-in recorder implements (1)(2)(3) + maintains @test-prev. @test-hist maps
#   to @session-history-hist; @test-prev to @session-history-prev.

# GOTCHA (research FINDING 6 — recorder temp file auto-cleaned): write the recorder to
#   $TMUX_SOCK_DIR/session_history_rec.sh. teardown_socket (run.sh's per-test teardown_test)
#   does `rm -rf "$TMUX_SOCK_DIR"` -> the recorder is removed automatically. NO manual cleanup,
#   NO trap (run.sh owns the per-test lifecycle). The P1.M6 throwaway mocks used a separate
#   mktemp + trap because they were standalone; the real test is SOURCED by run.sh.

# GOTCHA (research FINDING 9 — the toggle simulation): after a confirm pick (driver->target),
#   @test-prev == driver (from=driver). Simulate the toggle with ONE line:
#   `tmux switch-client -t "=$(tmux show-option -gqv @test-prev)"`. It fires the recorder
#   (a navigation — target->driver, driver appended at the tip) and the CLIENT lands on driver
#   (the pre-pick session). Read @test-prev BEFORE the toggle (it changes after).

# GOTCHA (the @test-hist "exactly one new entry" assertion): after confirm, @test-hist ==
#   "$snapshot_hist"<newline>"$target". Build the expected value with a real newline:
#   `local want="$snap"$'\n'"$target"` then assert_eq "$(show @test-hist)" "$want". POSIX
#   string = compares the whole (multi-line) value. If ANY intermediate session were recorded
#   (the old switch-on-browse bug), @test-hist would have >2 lines -> assert fails (correctly).

# GOTCHA (resolve the target DYNAMICALLY — do NOT hardcode): after 5 next-session calls, the
#   highlight is at @livepicker-index. The target confirm will land on == filtered[index].
#   With an EMPTY filter (this suite never types), filtered == the full @livepicker-list.
#   So lp_poll_resolve_target reads @livepicker-list + @livepicker-index and returns
#   items[index] — byte-identical to what input-handler.sh confirm resolves. NEVER assume
#   list-sessions ordering (it is server order, not sorted); read it live.

# GOTCHA (fixture count — 5 navs must not wrap to driver): the baseline is driver/alpha/beta
#   (3). To "browse 5 sessions" faithfully AND ensure 5 next-session steps from `driver` never
#   land back on `driver` (which would make confirm a same-session switch -> deduped -> 0 entries
#   -> T2 false-fails), create ≥5 extra sessions (nav1..nav5 -> 8 total). (driver_idx+5)%8 !=
#   driver_idx for any 8-element list. Belt-and-braces: lp_poll_resolve_target's caller asserts
#   target != driver before confirming.

# STYLE (research FINDING 10 / system_context §9): shebang #!/usr/bin/env bash; `set -u`
#   INHERITED (helpers.sh/run.sh declare it) — do NOT re-declare (mirror test_self.sh:
#   "`# set -u is inherited`"); local for ALL function locals; TABS; quote everything. Signal
#   failure ONLY via fail/assert_* (NEVER exit — run.sh reads TEST_STATUS in the CURRENT shell;
#   a bare exit kills the runner). The file is SOURCED by run.sh: define test_* + lp_* ONLY;
#   NO side effects on source; NO setup_test/teardown_test calls (run.sh owns the per-test cycle).
#   RECORDER EXCEPTION: the recorder (session_history_rec.sh) is a SEPARATE script invoked by the
#   tmux server's run-shell. It is written WITHOUT `set -u` (a crash mid-hook leaves @test-*
#   inconsistent -> mysterious false-fails) and with explicit defaults on every read (:-0,
#   2>/dev/null). Robustness > house style for a hook-invoked stand-in (mirrors the P1.M6 mock).

# GOTCHA: do NOT edit tests/setup_socket.sh, tests/helpers.sh, tests/run.sh, any scripts/* file,
#   PRD.md, tasks.json, prd_snapshot.md, or .gitignore (FORBIDDEN). This task ADDS exactly ONE
#   file: tests/test_pollution.sh.
```

## Implementation Blueprint

### Data models and structure

No data model. The "model" is the **stand-in recorder** (a faithful mirror of the real
`tmux-session-history` engine) + the **test-body contract** between run.sh and
`test_pollution.sh`:

```bash
# The stand-in recorder's STATE (mirrors @session-history-* — research FINDING 1):
#   @test-hist     -> ordered timeline, NO DUPLICATES, newline-separated (== @session-history-hist).
#   @test-current  -> last-known current session (so the hook can diff from->to).
#   @test-prev     -> the session the toggle flips to (= from on navigation).
#   @test-idx      -> cursor position (index of the current session).
#
# The recorder's do_hook(to) logic (mirrors the real engine):
#   (1) first-fire / @test-current empty -> init: hist=(to); idx=0; current=prev=to.
#   (2) to == current       -> SHORT-CIRCUIT (the dedup that makes cancel -> 0 entries).
#   (3) else NAVIGATION     -> keep hist[0..idx] MINUS to; APPEND to; idx=len-1 (forward
#                              collapses); prev = old current; current = to.
#
# The shared surface IN SCOPE when each test_* runs (provided by run.sh's sources + setup_test
# — test_pollution.sh SOURCES NOTHING):
#   bare `tmux`              -> the PATH shim -> isolated -L socket (transparent).
#   $LIVEPICKER_SCRIPTS      -> repo scripts/ (exported by setup_socket).
#   $TEST_DRIVER_SESSION     -> "driver" (the attached client's home / activate origin).
#   $TMUX_SOCK_DIR           -> the temp dir holding the shim + the recorder (auto-cleaned).
#   attach_test_client       -> the `script`-pty attach (from setup_socket).
#   fail/pass/assert_eq/assert_contains + TEST_STATUS -> from helpers.sh.
#
# The CONTRACT for each test_* body:
#   - create fixtures via lp_poll_make_fixtures BEFORE attach_test_client (FINDING 3).
#   - attach a client (the driven scripts require one — FINDING 7).
#   - install the recorder via lp_install_history_recorder (seeds @test-* + force-switch).
#   - snapshot @test-hist; drive the REAL $LIVEPICKER_SCRIPTS/{livepicker,input-handler}.sh.
#   - assert observable state via assert_*/fail (NEVER exit).
#   - run.sh wraps you in setup_test -> test -> teardown_test; do NOT call those.
```

### Implementation Tasks (ordered by dependencies)

```yaml
Task 1: CREATE tests/test_pollution.sh — header + lp_install_history_recorder
  - CREATE: tests/test_pollution.sh (NEW; SOURCED by run.sh — NEVER executed directly; no
        self-test guard; no BASH_SOURCE/$0 check).
  - HEADER: #!/usr/bin/env bash ; a CONTRACT comment ("sourced by run.sh; defines test_* +
        lp_install_history_recorder + lp_poll_make_fixtures + lp_poll_resolve_target only; NO
        side effects on source; NO setup_test/teardown_test calls — run.sh owns the per-test
        cycle; the driven scripts REQUIRE an attached client so attach_test_client is called
        FIRST; the assert helpers, $LIVEPICKER_SCRIPTS, $TEST_DRIVER_SESSION, $TMUX_SOCK_DIR,
        attach_test_client come from run.sh's sources; the real tmux-session-history is NOT
        loaded on the isolated socket so a stand-in recorder is installed"); `# set -u is
        inherited` (do NOT re-declare; mirror test_self.sh/test_functional.sh); file-level
        `# shellcheck disable=SC2154,SC2016,SC2034,SC2086` (SC2154: assert_*/attach_test_client/
        $LIVEPICKER_SCRIPTS/$TEST_DRIVER_SESSION/$TMUX_SOCK_DIR are defined by run.sh's sources).
  - IMPLEMENT: `lp_install_history_recorder` (FINDING 1/5/6). Write the recorder to
        "$TMUX_SOCK_DIR/session_history_rec.sh" via an UNQUOTED heredoc (so T="$TMUX_SOCK_DIR/tmux"
        bakes the ABSOLUTE shim path at write time; \$1/\$T/\$cur stay literal). The recorder
        body mirrors do_hook (same-session short-circuit + forward-collapse + @test-prev) and is
        written WITHOUT set -u, with explicit defaults on every read (the recorder exception —
        FINDING 10). chmod +x. Then:
          tmux set-hook -g client-session-changed "run-shell '$rec #{session_name}'"   (NO -b — FINDING 4)
          tmux set-option -g @test-hist "$TEST_DRIVER_SESSION"
          tmux set-option -g @test-current "$TEST_DRIVER_SESSION"
          tmux set-option -g @test-prev "$TEST_DRIVER_SESSION"
          tmux set-option -g @test-idx 0
          tmux switch-client -t "=$TEST_DRIVER_SESSION"   # force the pointer (FINDING 3); same-session -> deduped
  - FOLLOW pattern: tests/setup_socket.sh (the UNQUOTED heredoc that bakes an absolute shim
        path — the `cat > "$TMUX_SOCK_DIR/tmux" <<EOF` block) + the research's "validated
        stand-in recorder" block (ready to paste).
  - DO NOT: use -b on set-hook; use a bare `tmux` inside the recorder (use the baked $T);
        add set -u to the recorder; source anything; call setup_test/teardown_test.

Task 2: lp_poll_make_fixtures + lp_poll_resolve_target helpers
  - IMPLEMENT: `lp_poll_make_fixtures` — create 5 detached sessions nav1..nav5
        (`tmux new-session -d -s navN -x 120 -y 40`). MUST be called BEFORE attach_test_client
        (FINDING 3). 5 extra + baseline driver/alpha/beta = 8 sessions -> 5 next-session steps
        from `driver` never wrap back to `driver` (gotcha: fixture count).
  - IMPLEMENT: `lp_poll_resolve_target` — read @livepicker-list + @livepicker-index; declare
        `local list idx` + `local -a items`; sanitize idx (`[[ "$idx" =~ ^[0-9]+$ ]] || idx=0`);
        `mapfile -t items < <(printf '%s' "$list")`; if idx < ${#items[@]} print items[idx]
        else print "". This predicts confirm's target (empty filter -> filtered == full list —
        filter.sh). NEVER hardcode a session name (list-sessions order is server order).
  - DO NOT: source filter.sh (house style — test files source nothing; the empty-filter
        property makes filtered == the raw list, so reading @livepicker-list is exact).

Task 3: test_browse_cancel_no_pollution (PRD §15.18 bullet 1)
  - IMPLEMENT: lp_poll_make_fixtures; attach_test_client; lp_install_history_recorder;
        `local snap i; snap="$(tmux show-option -gqv @test-hist)"` (= "driver");
        `"$LIVEPICKER_SCRIPTS/livepicker.sh"` (activate — fires NO client-session-changed);
        `for i in 1 2 3 4 5; do "$LIVEPICKER_SCRIPTS/input-handler.sh" next-session; done`;
        assert_eq "$(tmux show-option -gqv @test-hist)" "$snap" "browse added no history entries
        (Invariant A — navigation never fires client-session-changed)";
        `"$LIVEPICKER_SCRIPTS/input-handler.sh" cancel` (empty filter -> restore.sh cancel);
        assert_eq "$(tmux show-option -gqv @test-hist)" "$snap" "cancel added no history
        (same-session switch deduped)";
        assert_eq "$(tmux display-message -p '#{session_name}')" "$TEST_DRIVER_SESSION" "client
        returned to the original session".
  - WHY: navigation is link+select (Invariant A) -> 0 client-session-changed; cancel's switch is
        same-session (client never left driver) -> the recorder's short-circuit -> 0 entries
        (FINDING 1 step 2). display-message == driver because cancel's switch-client reset the
        pointer (FINDING 3 section E).
  - DO NOT: create fixtures after attach (FINDING 3); assert @test-hist changed (it must NOT).

Task 4: test_browse_confirm_one_entry (PRD §15.18 bullet 2)
  - IMPLEMENT: lp_poll_make_fixtures; attach_test_client; lp_install_history_recorder;
        `local snap i target want; snap="$(tmux show-option -gqv @test-hist)"`; activate;
        5× next-session; `target="$(lp_poll_resolve_target)"`;
        `[ "$target" != "$TEST_DRIVER_SESSION" ] || fail "nav did not move off the original
        session"`; `"$LIVEPICKER_SCRIPTS/input-handler.sh" confirm`;
        `want="$snap"$'\n'"$target"`; assert_eq "$(tmux show-option -gqv @test-hist)" "$want"
        "confirm appended exactly one entry (the target); no intermediates (forward history
        collapsed)";
        assert_eq "$(tmux display-message -p '#{session_name}')" "$target" "confirm landed the
        client on the target".
  - WHY: confirm issues the ONE switch-client (driver->target) -> the recorder's NAVIGATION
        branch (FINDING 1 step 3): keep hist[0..0]=[driver] minus target, append target ->
        "driver\ntarget", idx=1. The 4 intermediates were NEVER recorded (Invariant A) so the
        timeline grew by EXACTLY one line == target. If the old switch-on-browse bug were
        present, @test-hist would have >2 lines -> assert fails (correctly).
  - DO NOT: hardcode the target name (resolve it dynamically); expect >1 new entry.

Task 5: test_toggle_after_confirm (PRD §15.18 bullet 3)
  - IMPLEMENT: lp_poll_make_fixtures; attach_test_client; lp_install_history_recorder;
        `local i target prev`; activate; 5× next-session; `target="$(lp_poll_resolve_target)"`;
        `"$LIVEPICKER_SCRIPTS/input-handler.sh" confirm`;
        `prev="$(tmux show-option -gqv @test-prev)"` (read BEFORE the toggle);
        assert_eq "$prev" "$TEST_DRIVER_SESSION" "@test-prev points at the pre-pick session
        (driver)";
        `tmux switch-client -t "=$prev"` (simulate do_toggle — FINDING 9);
        assert_eq "$(tmux display-message -p '#{session_name}')" "$TEST_DRIVER_SESSION" "toggle
        returned to the pre-pick session (driver)".
  - WHY: after a confirm pick (driver->target), the recorder set @test-prev=from=driver
        (FINDING 1 step 3). The toggle (switch to @test-prev=driver) lands the client on driver —
        the pre-pick session — because only ONE switch occurred (PRD §14 "toggle after confirm").
        The toggle itself is a navigation (target->driver) and updates @test-* accordingly, but
        the assertion is the CLIENT's resulting session, which is driver.
  - DO NOT: read @test-prev AFTER the toggle (it changes to target); expect @test-hist unchanged
        (the toggle is a real navigation).

Task 6: VALIDATE (Level 1 lint + Level 2 suite green + Level 4 non-pollution)
  - RUN: bash -n + shellcheck on the file; `bash tests/run.sh` (expect all three PASS +
        test_self + T3.S1's five + T4.S1's four PASS, exit 0); snapshot
        `/usr/bin/tmux list-sessions` before/after a full run.sh and assert byte-identical
        (non-pollution); `git diff --stat` shows ONLY tests/test_pollution.sh added.
```

### Implementation Patterns & Key Details

#### The file skeleton + the recorder helper (Task 1)

```bash
#!/usr/bin/env bash
# tests/test_pollution.sh — tmux-livepicker PRD §15.18 Pollution (the core invariant)
# validation (P1.M7.T5.S1).
#
# SOURCED by run.sh (NEVER executed directly). Defines three test_* functions that drive the
# COMPLETE real plugin (scripts/livepicker.sh -> input-handler.sh -> preview.sh -> restore.sh,
# all COMPLETE P1.M1-M6) DIRECTLY (contract §1: the scripts; NOT via keypress) against the
# socket-isolated server the harness provides (tests/setup_socket.sh P1.M7.T1.S1 +
# tests/helpers.sh P1.M7.T2.S1), and assert the core invariant (PRD §4/§14): browsing must not
# pollute session-history, and the only navigation is the one confirm-time switch. Each test
# installs a stand-in tmux-session-history recorder (the real plugin is NOT loaded on the
# isolated socket), exercises one §15.18 bullet, and signals pass/fail via fail/assert_* (which
# set TEST_STATUS; run.sh reads it in the current shell).
#
# CONTRACT: run.sh sources setup_socket.sh + helpers.sh + every tests/test_*.sh, then PER test
# calls setup_test "lp-$$-<name>" (-> fresh isolated socket + PATH shim + baseline fixtures
# driver/alpha/beta) -> resets TEST_STATUS=pass -> runs the test_* in the CURRENT shell -> reads
# TEST_STATUS -> teardown_test. So when a test_* runs: bare `tmux` hits the isolated socket;
# $LIVEPICKER_SCRIPTS, $TEST_DRIVER_SESSION, $TMUX_SOCK_DIR, attach_test_client,
# fail/pass/assert_eq/assert_contains are all IN SCOPE; this file SOURCES NOTHING and calls NO
# setup_test/teardown_test.
#
# CRITICAL (research FINDING 3): `display-message -p '#{session_name}'` returns the LAST-CREATED/
# switched session, NOT necessarily the client's. So create ALL fixtures BEFORE attach_test_client
# (the attach resets the pointer to `driver`); the recorder force-switches to `driver` too.
#
# CRITICAL (research FINDING 7): the driven scripts (livepicker/confirm/cancel) REQUIRE an
# attached client. So every test_* calls attach_test_client FIRST (mirrors T3.S1; UNLIKE T4.S1).
#
# CRITICAL (research FINDING 5): the recorder bakes the ABSOLUTE shim path ($TMUX_SOCK_DIR/tmux)
# so run-shell hits the isolated socket, never /usr/bin/tmux.
#
# `set -u` is INHERITED from helpers.sh (do NOT re-declare; mirror test_self.sh).
# shellcheck disable=SC2154,SC2016,SC2034,SC2086
#   SC2154: assert_*/attach_test_client/$LIVEPICKER_SCRIPTS/$TEST_DRIVER_SESSION/$TMUX_SOCK_DIR
#           are defined by run.sh's sources, not in this file.

# lp_install_history_recorder — install a stand-in tmux-session-history engine on the isolated
# socket. The real plugin is NOT loaded there (contract §1 RESEARCH NOTE), so this recorder
# faithfully mirrors its do_hook (same-session short-circuit + forward-collapse) + do_toggle,
# read in full from the real scripts/session_history.sh (research FINDING 1). State lives in
# @test-* (== @session-history-*). The recorder file is written into $TMUX_SOCK_DIR (auto-cleaned
# by teardown_socket — FINDING 6) via an UNQUOTED heredoc so `T="$TMUX_SOCK_DIR/tmux"` bakes the
# ABSOLUTE shim path at write time (FINDING 5). The recorder is written WITHOUT set -u + with
# explicit defaults (the recorder exception — FINDING 10: a crash mid-hook leaves @test-*
# inconsistent). set-hook uses NO -b (FINDING 4: synchronous -> the test's next read sees the
# update). The trailing switch-client forces the display-message pointer to `driver` (FINDING 3
# belt-and-braces); the client is already on `driver` post-attach -> same-session -> deduped.
lp_install_history_recorder() {
	local rec="$TMUX_SOCK_DIR/session_history_rec.sh"
	# UNQUOTED heredoc: $TMUX_SOCK_DIR expands at WRITE time (bakes the absolute shim path);
	# \$1 / \$T / \$cur etc. stay literal (runtime). NO set -u in the recorder (FINDING 10).
	cat > "$rec" <<EOF
#!/usr/bin/env bash
T="$TMUX_SOCK_DIR/tmux"
to="\$1"
cur="\$(\$T show-option -gqv @test-current 2>/dev/null)"
if [ -z "\$cur" ]; then
	\$T set-option -g @test-hist "\$to"
	\$T set-option -g @test-current "\$to"
	\$T set-option -g @test-prev "\$to"
	\$T set-option -g @test-idx 0
	exit 0
fi
# SAME-SESSION short-circuit (the dedup that makes cancel -> 0 entries).
[ "\$to" = "\$cur" ] && exit 0
# NAVIGATION: keep backward hist[0..idx] MINUS `to`, append `to`, idx=len-1 (forward collapses).
idx="\$(\$T show-option -gqv @test-idx 2>/dev/null)"; [ -z "\$idx" ] && idx=0
mapfile -t HIST < <(\$T show-option -gqv @test-hist 2>/dev/null)
nh=(); i=0
for line in "\${HIST[@]}"; do
	[ "\$i" -gt "\$idx" ] && break
	[ "\$line" != "\$to" ] && nh+=("\$line")
	i=\$((i+1))
done
nh+=("\$to"); newidx=\$(( \${#nh[@]} - 1 ))
LF=\$'\n'; newhist=""
for line in "\${nh[@]}"; do newhist="\${newhist:+\$newhist\$LF}\$line"; done
\$T set-option -g @test-hist "\$newhist"
\$T set-option -g @test-idx "\$newidx"
\$T set-option -g @test-prev "\$cur"
\$T set-option -g @test-current "\$to"
EOF
	chmod +x "$rec"
	# Synchronous hook (NO -b — FINDING 4). #{session_name} is tmux format, not shell.
	tmux set-hook -g client-session-changed "run-shell '$rec #{session_name}'"
	# Seed the timeline so the first real switch is a NAVIGATION (not a first-fire init).
	tmux set-option -g @test-hist     "$TEST_DRIVER_SESSION"
	tmux set-option -g @test-current  "$TEST_DRIVER_SESSION"
	tmux set-option -g @test-prev     "$TEST_DRIVER_SESSION"
	tmux set-option -g @test-idx      0
	# Force the display-message pointer to `driver` (FINDING 3). Same-session -> deduped -> 0 entries.
	tmux switch-client -t "=$TEST_DRIVER_SESSION"
}

# lp_poll_make_fixtures — create 5 detached sessions so the picker has 8 total (driver/alpha/
# beta + nav1..nav5). MUST be called BEFORE attach_test_client (FINDING 3). 8 sessions => 5
# next-session steps from `driver` never wrap back to `driver` (so confirm lands on a real
# target != original — gotcha: fixture count).
lp_poll_make_fixtures() {
	local n
	for n in nav1 nav2 nav3 nav4 nav5; do
		tmux new-session -d -s "$n" -x 120 -y 40
	done
}

# lp_poll_resolve_target — predict the session confirm will land on, from the picker's OWN state.
# With an EMPTY filter (this suite never types), filtered == the full @livepicker-list (filter.sh),
# so target == items[@livepicker-index] — byte-identical to what input-handler.sh confirm resolves.
# NEVER hardcode a name (list-sessions order is server order, not sorted).
lp_poll_resolve_target() {
	local list idx
	local -a items=()
	list="$(tmux show-option -gqv @livepicker-list)"
	idx="$(tmux show-option -gqv @livepicker-index)"
	[[ "$idx" =~ ^[0-9]+$ ]] || idx=0
	mapfile -t items < <(printf '%s' "$list")
	if [ "$idx" -lt "${#items[@]}" ]; then
		printf '%s' "${items[$idx]}"
	else
		printf '%s' ""
	fi
}
```

#### test_browse_cancel_no_pollution (Task 3)

```bash
# PRD §15.18 bullet 1: browse 5 sessions then cancel -> @test-hist UNCHANGED + client on origin.
test_browse_cancel_no_pollution() {
	# Fixtures BEFORE attach (FINDING 3): attach resets the display-message pointer to `driver`.
	lp_poll_make_fixtures
	attach_test_client
	lp_install_history_recorder

	local snap i
	snap="$(tmux show-option -gqv @test-hist)"   # "driver" (seeded)

	"$LIVEPICKER_SCRIPTS/livepicker.sh"           # activate (self-session preview; NO switch)

	# Invariant A: 5 navigations fire ZERO client-session-changed (link+select only).
	for i in 1 2 3 4 5; do
		"$LIVEPICKER_SCRIPTS/input-handler.sh" next-session
	done
	assert_eq "$(tmux show-option -gqv @test-hist)" "$snap" \
		"browse added no history entries (navigation never fires client-session-changed)"

	# PRD §15.18 b1: cancel -> restore.sh cancel -> switch-client -t "=driver" (SAME-session,
	# the client never left driver) -> the recorder dedups it -> 0 entries.
	"$LIVEPICKER_SCRIPTS/input-handler.sh" cancel   # empty filter -> full restore cancel
	assert_eq "$(tmux show-option -gqv @test-hist)" "$snap" \
		"cancel added no history (same-session switch deduped)"
	assert_eq "$(tmux display-message -p '#{session_name}')" "$TEST_DRIVER_SESSION" \
		"client returned to the original session"
}
```

#### test_browse_confirm_one_entry (Task 4)

```bash
# PRD §15.18 bullet 2: browse 5, confirm on the target -> EXACTLY ONE new entry (the target),
# no intermediates (forward history collapsed).
test_browse_confirm_one_entry() {
	lp_poll_make_fixtures
	attach_test_client
	lp_install_history_recorder

	local snap i target want
	snap="$(tmux show-option -gqv @test-hist)"   # "driver"

	"$LIVEPICKER_SCRIPTS/livepicker.sh"
	for i in 1 2 3 4 5; do
		"$LIVEPICKER_SCRIPTS/input-handler.sh" next-session
	done

	# Resolve the highlighted target DYNAMICALLY (empty filter -> full list; mirror confirm).
	target="$(lp_poll_resolve_target)"
	[ "$target" != "$TEST_DRIVER_SESSION" ] \
		|| fail "navigation did not move the highlight off the original session"

	"$LIVEPICKER_SCRIPTS/input-handler.sh" confirm   # the ONE switch (driver -> target)

	# PRD §15.18 b2: exactly ONE new entry appended (the target); the 4 intermediates were
	# NEVER recorded (Invariant A). The recorder's navigation: keep [driver] minus target,
	# append target -> "driver\ntarget". A real newline in the expected value (POSIX = compares
	# the whole multi-line string).
	want="$snap"$'\n'"$target"
	assert_eq "$(tmux show-option -gqv @test-hist)" "$want" \
		"confirm appended exactly one entry (the target); no intermediates (forward history collapsed)"
	assert_eq "$(tmux display-message -p '#{session_name}')" "$target" \
		"confirm landed the client on the target"
}
```

#### test_toggle_after_confirm (Task 5)

```bash
# PRD §15.18 bullet 3: after a confirmed pick, the toggle returns to the pre-pick session.
test_toggle_after_confirm() {
	lp_poll_make_fixtures
	attach_test_client
	lp_install_history_recorder

	local i target prev

	"$LIVEPICKER_SCRIPTS/livepicker.sh"
	for i in 1 2 3 4 5; do
		"$LIVEPICKER_SCRIPTS/input-handler.sh" next-session
	done
	target="$(lp_poll_resolve_target)"
	"$LIVEPICKER_SCRIPTS/input-handler.sh" confirm   # driver -> target (the ONE switch)

	# After the pick, @test-prev == the pre-pick session (driver) — the recorder set prev=from.
	# Read it BEFORE the toggle (the toggle itself is a navigation that flips @test-prev).
	prev="$(tmux show-option -gqv @test-prev)"
	assert_eq "$prev" "$TEST_DRIVER_SESSION" \
		"@test-prev points at the pre-pick session (driver)"

	# PRD §15.18 b3 / §14: simulate the session-history toggle (do_toggle: switch-client -t
	# "$PREV"). Because only ONE switch occurred, it returns to the pre-pick session.
	tmux switch-client -t "=$prev"
	assert_eq "$(tmux display-message -p '#{session_name}')" "$TEST_DRIVER_SESSION" \
		"toggle returned to the pre-pick session (driver)"
}
```

NOTE for the implementer:
- This is ONE NEW FILE under `tests/`. No edits to `setup_socket.sh`/`helpers.sh`/`run.sh`,
  no `scripts/` edits, no PRD/tasks edits.
- The file is SOURCED by run.sh — define `test_*` + the `lp_*` helpers ONLY; NO side effects on
  source; NO `setup_test`/`teardown_test`; NO sourcing.
- `set -u` is inherited; do NOT re-declare it. Do NOT add `set -e`/`pipefail`. (The RECORDER
  script is the documented exception — it is written WITHOUT `set -u` for hook robustness.)
- Signal failure ONLY via `fail`/`assert_*` (never `exit`).
- EVERY `test_*` calls `attach_test_client` (the driven scripts require a client — FINDING 7).
- Create fixtures via `lp_poll_make_fixtures` BEFORE `attach_test_client` (FINDING 3).
- Resolve the confirm target DYNAMICALLY via `lp_poll_resolve_target`; NEVER hardcode a name.
- The three most important correctness points are FINDING 3 (fixtures-before-attach), FINDING 5
  (the recorder's baked absolute shim path), and FINDING 4 (the synchronous, no-`-b` hook).

### Integration Points

```yaml
NEW FILE (the ONLY file this task creates):
  - tests/test_pollution.sh: sourced-by-run.sh test bodies (3 test_* + lp_install_history_recorder
        + lp_poll_make_fixtures + lp_poll_resolve_target). No side effects on source; drives the
        real plugin against the isolated socket; installs a stand-in session-history recorder.

CONSUMES (the INPUT — COMPLETE/READ-ONLY; do NOT edit):
  - tests/setup_socket.sh (T1.S1): setup_socket/teardown_socket + the TEST_*/TMUX_*/REAL_TMUX/
        LIVEPICKER_*/TEST_DRIVER_SESSION exports + the baseline fixtures + attach_test_client/
        detach_test_client. run.sh's setup_test calls setup_socket per test.
  - tests/helpers.sh (T2.S1): fail/pass/assert_eq/assert_contains + setup_test/teardown_test +
        TEST_STATUS. In scope (run.sh sources helpers.sh).
  - tests/run.sh (T2.S1): the runner — sources the 3 files, discovers test_*, runs each in a
        per-test fresh-socket cycle, exits 0/1. nullglob picks up test_pollution.sh automatically.
  - scripts/livepicker.sh + input-handler.sh + restore.sh + filter.sh (COMPLETE/IMMUTABLE):
        driven directly (activate / next-session / confirm / cancel).

CONSUMERS (downstream — NOT this task's responsibility):
  - `bash tests/run.sh` discovers + runs test_pollution.sh's test_* alongside test_self +
        T3.S1's functional + T4.S1's preview tests + the future T6 test_*.sh (each hermetic).

PROVIDES:
  - 3 PRD §15.18 pollution test_* functions + the stand-in session-history recorder (the proof
        of PRD §4 / §14 — the core invariant).

DATABASE / MIGRATIONS / ROUTES / CONFIG: none. No @livepicker-* or @test-* writes on the REAL
        server (the isolated socket only). The only real-server contact is READ-ONLY (snapshot
        /usr/bin/tmux list-sessions around run.sh — a validation step).
```

## Validation Loop

### Level 1: Syntax & Style (Immediate Feedback)

```bash
# Run after creating the file — fix before proceeding.
bash -n tests/test_pollution.sh
shellcheck tests/test_pollution.sh
#   expect 0 findings (file-level `# shellcheck disable=SC2154,SC2016,SC2034,SC2086`
#   is OK — mirror setup_socket.sh/helpers.sh/test_functional.sh/test_preview.sh).

# Tabs-not-spaces sanity (shfmt NOT installed):
grep -Pn '^    ' tests/test_pollution.sh && echo "FAIL: 4-space indent, use tabs" || echo "OK: tabs only"

# House style: set -u inherited (NOT re-declared); NO set -e/pipefail statement:
grep -nE 'set -e|set -o pipefail|^set -u' tests/test_pollution.sh \
  && echo "FAIL: found a disallowed set statement (set -u is inherited; -e/pipefail forbidden)" \
  || echo "OK: no set statement (set -u inherited)"

# attach_test_client IS used (the driven scripts require a client — FINDING 7):
grep -q 'attach_test_client' tests/test_pollution.sh \
  && echo "OK: attaches a client" || echo "FAIL: no attach_test_client (scripts need a client)"

# Fixtures created BEFORE attach (FINDING 3): lp_poll_make_fixtures must precede attach in each test.
grep -nE 'lp_poll_make_fixtures|attach_test_client' tests/test_pollution.sh
#   Expect, per test: lp_poll_make_fixtures line number < attach_test_client line number.

# No side effects on source: a bare source must NOT start a server, call setup_test, print, or
# run a test. (run.sh owns the per-test cycle.)
out="$( source tests/test_pollution.sh 2>&1 )"
[ -z "$out" ] && echo "OK: source is silent" || echo "FAIL: source printed: $out"
( source tests/test_pollution.sh; declare -F test_browse_cancel_no_pollution \
    test_browse_confirm_one_entry test_toggle_after_confirm lp_install_history_recorder \
    lp_poll_make_fixtures lp_poll_resolve_target )

# The file SOURCES NOTHING (run.sh owns sourcing):
grep -nE '^[[:space:]]*source |^[[:space:]]*\. ' tests/test_pollution.sh \
  && echo "FAIL: test_pollution.sh sources something (it must not)" || echo "OK: no sourcing"

# Never exits / never calls setup_test/teardown_test directly:
grep -nE '\bexit\b|setup_test|teardown_test' tests/test_pollution.sh \
  && echo "FAIL: test body exits or touches the per-test cycle" || echo "OK: no exit / no setup_test"

# The recorder uses the baked ABSOLUTE shim path (NOT a bare `tmux`) + NO -b on set-hook:
grep -q 'T="$TMUX_SOCK_DIR/tmux"' tests/test_pollution.sh && echo "OK: recorder bakes shim path" \
  || echo "FAIL: recorder must use T=\"\$TMUX_SOCK_DIR/tmux\" (FINDING 5)"
grep -q 'set-hook -g client-session-changed' tests/test_pollution.sh && echo "OK: hook installed" \
  || echo "FAIL: no client-session-changed hook"
grep -q 'set-hook .*-b' tests/test_pollution.sh && echo "FAIL: hook uses -b (must be synchronous — FINDING 4)" \
  || echo "OK: synchronous hook (no -b)"

# SCOPE: only the one new file added (no harness/scripts/PRD/tasks edits):
git status --porcelain | grep -E '^.M (tests/setup_socket|tests/helpers|tests/run)\.sh|^.M scripts/|PRD\.md|tasks\.json|prd_snapshot' \
  && echo "FAIL: edited an off-limits file" || echo "OK: only tests/test_pollution.sh added"
```

### Level 2: The Suite (work-item §4 OUTPUT — runner aggregates)

```bash
# Run the full suite. Expect all three pollution tests PASS + test_self + T3.S1's five +
# T4.S1's four PASS, summary "N passed, 0 failed", exit 0.
bash tests/run.sh
echo "exit=$?"
# Expected (order may vary by sort): test_browse_cancel_no_pollution,
#   test_browse_confirm_one_entry, test_toggle_after_confirm PASS (+ the T2/T3/T4 tests). exit=0.
#
# If a test FAILS: run.sh prints "FAIL  <name>" + the ASSERT FAIL line on stderr.
#   - "browse added no history entries" fails -> a navigation fired client-session-changed
#     (an Invariant A regression in preview.sh/next-session); or the recorder was not installed
#     before activate (check lp_install_history_recorder runs before livepicker.sh).
#   - "cancel added no history" fails -> ORIG_SESSION was wrong at activate (fixtures created
#     AFTER attach — FINDING 3); check lp_poll_make_fixtures precedes attach_test_client.
#   - "confirm appended exactly one entry" fails (got >2 lines) -> browse is switching (Invariant
#     A regression); fails (got == snap, 0 new) -> confirm didn't switch (target == driver — check
#     the fixture count / the nav count so 5 steps don't wrap to driver).
#   - "toggle returned to the pre-pick session" fails -> @test-prev wasn't driver (the recorder's
#     prev=from logic) OR the toggle switch target was wrong.
```

### Level 3: Per-test targeted proof (drive the recorder + plugin inline — smoke-level)

```bash
# Prove the recorder + the plugin interoperate on the isolated socket (run from repo root).
# Mirror the harness: source setup_socket + helpers, run ONE scenario inline.
# shellcheck disable=SC1091
source tests/setup_socket.sh
# shellcheck disable=SC1091
source tests/helpers.sh
# pull in the helpers under test:
# shellcheck disable=SC1091
source tests/test_pollution.sh
setup_test "lp-manual-$$"
LIVEPICKER_SCRIPTS="$LIVEPICKER_SCRIPTS"   # exported by setup_socket
lp_poll_make_fixtures
attach_test_client
lp_install_history_recorder
snap="$(tmux show-option -gqv @test-hist)"; echo "snap=[$snap]"
"$LIVEPICKER_SCRIPTS/livepicker.sh"
for i in 1 2 3 4 5; do "$LIVEPICKER_SCRIPTS/input-handler.sh" next-session; done
echo "hist after 5 navs=[$(tmux show-option -gqv @test-hist)]"   # expect == snap (Invariant A)
target="$(lp_poll_resolve_target)"; echo "target=[$target]"
"$LIVEPICKER_SCRIPTS/input-handler.sh" confirm
echo "hist after confirm=[$(tmux show-option -gqv @test-hist)]"  # expect "driver\ntarget"
echo "client=[$(tmux display-message -p '#{session_name}')]"     # expect == target
echo "prev=[$(tmux show-option -gqv @test-prev)]"                # expect == driver
tmux switch-client -t "=$(tmux show-option -gqv @test-prev)"
echo "client after toggle=[$(tmux display-message -p '#{session_name}')]"  # expect == driver
teardown_test
# (Re-run with run.sh for the full assertion suite — this just proves reachability.)
```

### Level 4: Creative & Domain-Specific Validation (PRD §15 non-pollution + robustness)

```bash
# PRD §15 invariant (the REAL server is untouched) — snapshot the user's REAL session list
# around a FULL run.sh invocation (multiple per-test setup/teardown cycles). This is the
# gold-standard proof that the recorder's baked shim path never escapes the isolated socket.
real_before="$(/usr/bin/tmux list-sessions -F '#{session_name}' | sort)"
bash tests/run.sh >/dev/null 2>&1
real_after="$(/usr/bin/tmux list-sessions -F '#{session_name}' | sort)"
[ "$real_before" = "$real_after" ] && echo "OK: real server byte-identical before/after" \
  || { echo "FAIL: real server changed (the recorder may have hit /usr/bin/tmux — FINDING 5)"; \
       diff <(echo "$real_before") <(echo "$real_after"); }

# Robustness: confirm that BROWSING truly records nothing (Invariant A), proven directly by the
# recorder. Source the helpers + drive one browse with the recorder watching.
# shellcheck disable=SC1091
( source tests/setup_socket.sh; source tests/helpers.sh; source tests/test_pollution.sh
  setup_test "lp-ia-$$"
  lp_poll_make_fixtures; attach_test_client; lp_install_history_recorder
  snap="$(tmux show-option -gqv @test-hist)"
  "$LIVEPICKER_SCRIPTS/livepicker.sh"
  for i in 1 2 3 4 5; do "$LIVEPICKER_SCRIPTS/input-handler.sh" next-session; done
  now="$(tmux show-option -gqv @test-hist)"
  [ "$snap" = "$now" ] && echo "OK: 5 navigations recorded ZERO entries (Invariant A)" \
    || echo "FAIL: browsing polluted: was[$snap] now[$now]"
  teardown_test )

# Robustness: the recorder's same-session short-circuit makes a no-op switch (cancel path)
# record nothing. Prove a switch-client to the CURRENT session leaves @test-hist unchanged.
# shellcheck disable=SC1091
( source tests/setup_socket.sh; source tests/helpers.sh; source tests/test_pollution.sh
  setup_test "lp-sc-$$"
  lp_poll_make_fixtures; attach_test_client; lp_install_history_recorder
  snap="$(tmux show-option -gqv @test-hist)"
  tmux switch-client -t "=$TEST_DRIVER_SESSION"   # same-session (client is on driver)
  now="$(tmux show-option -gqv @test-hist)"
  [ "$snap" = "$now" ] && echo "OK: same-session switch deduped (cancel path -> 0 entries)" \
    || echo "FAIL: same-session switch recorded: was[$snap] now[$now]"
  teardown_test )
```

## Final Validation Checklist

### Technical Validation

- [ ] All 4 validation levels completed successfully.
- [ ] `bash tests/run.sh` exits 0; summary `N passed, 0 failed`.
- [ ] `bash -n tests/test_pollution.sh` clean; `shellcheck tests/test_pollution.sh` clean
      (file-level `disable` for SC2154/SC2016/SC2034/SC2086 at most).
- [ ] Tabs only; `set -u` inherited (NOT re-declared); no `set -e`/`pipefail`.
- [ ] `/usr/bin/tmux list-sessions` byte-identical before/after a full `run.sh`.

### Feature Validation

- [ ] All PRD §15.18 success criteria met (3 bullets -> 3 passing `test_*`).
- [ ] `test_browse_cancel_no_pollution` PASS: browse 5 + cancel leaves `@test-hist` unchanged
      AND the client on the original session.
- [ ] `test_browse_confirm_one_entry` PASS: browse 5 + confirm appends EXACTLY ONE entry (the
      target), no intermediates; client lands on the target.
- [ ] `test_toggle_after_confirm` PASS: after confirm, the toggle returns to the pre-pick session.
- [ ] Each `test_*` creates fixtures BEFORE `attach_test_client` (FINDING 3) and installs the
      recorder via `lp_install_history_recorder`.
- [ ] The recorder uses the baked absolute shim path (FINDING 5) + a synchronous hook (no `-b`,
      FINDING 4); the recorder has NO `set -u` (FINDING 10).

### Code Quality Validation

- [ ] Follows the sibling test-file conventions (test_functional.sh / test_preview.sh): header
      CONTRACT comment, `lp_*` helper idiom, dynamic reads, inline-`case` for negatives, tabs.
- [ ] File placement matches the desired tree (the single new file `tests/test_pollution.sh`).
- [ ] Anti-patterns avoided (check against the Anti-Patterns section).
- [ ] No sourcing; no `setup_test`/`teardown_test` calls; no `exit` in test bodies.
- [ ] Target resolved dynamically (never hardcoded); fixture count chosen so 5 navs don't wrap
      to the original.

### Documentation & Deployment

- [ ] Code is self-documenting with clear variable/function names + WHY comments tracing each
      assertion to a research FINDING.
- [ ] DOCS: Mode A — none (test infra; no end-user surface).
- [ ] No new environment variables (all inputs come from the harness exports).

---

## Anti-Patterns to Avoid

- ❌ Don't create fixtures AFTER `attach_test_client` (FINDING 3 — the display-message pointer
  trap; activate would save the wrong `ORIG_SESSION` → false pollution on cancel).
- ❌ Don't write the recorder with a bare `tmux` call (use the baked `T="$TMUX_SOCK_DIR/tmux"` —
  FINDING 5; run-shell inherits the server's PATH, not the test's).
- ❌ Don't use `set-hook ... -b` (the recorder must be synchronous — FINDING 4; `-b` makes it
  async → flaky false-fails).
- ❌ Don't add `set -u` to the recorder script (FINDING 10 — a crash mid-hook leaves `@test-*`
  inconsistent; the recorder uses explicit defaults instead).
- ❌ Don't skip `attach_test_client` (the driven scripts require a client — FINDING 7; this is
  NOT T4.S1, whose `preview.sh` is client-independent).
- ❌ Don't hardcode the confirm target name (list-sessions order is server order; resolve it
  dynamically via `lp_poll_resolve_target`).
- ❌ Don't create new patterns when existing ones work (mirror `test_functional.sh`'s attach +
  display-message idiom, `test_preview.sh`'s `lp_*`-helper + header style, `setup_socket.sh`'s
  unquoted-heredoc-bakes-a-path pattern).
- ❌ Don't ignore failing tests — fix the root cause (an Invariant A regression in the plugin
  would surface here as real pollution).
- ❌ Don't `exit` from a test body, don't call `setup_test`/`teardown_test`, don't source
  anything (run.sh owns the per-test cycle and the sourcing).
- ❌ Don't edit `setup_socket.sh`/`helpers.sh`/`run.sh`, any `scripts/*`, PRD.md, tasks.json,
  prd_snapshot.md, or .gitignore (FORBIDDEN — this task adds exactly ONE file).

---

## Confidence Score

**9/10** for one-pass implementation success.

Rationale: the research file (`research/pollution_test_findings.md`) is unusually complete —
11 empirically-verified findings (run live on isolated sockets on tmux 3.6b on 2026-07-06), the
real `tmux-session-history` engine read in full (the authoritative model for the stand-in), a
ready-to-paste recorder block, and a verified end-to-end run that printed `ALL PASSED` for all
three scenarios. Every non-obvious trap (FINDING 3 the pointer trap, FINDING 5 the shim path,
FINDING 4 the synchronous hook) is documented with its verified fix. The implementation is a
single sourced file mirroring two existing sibling test files (`test_functional.sh`,
`test_preview.sh`) whose exact style and helpers are read in full. The residual 1 point of
uncertainty is the standard hermetic-test risk (pty attach timing in `attach_test_client`, which
the harness already mitigates with `sleep 0.5` and which T3.S1's functional tests already exercise
green) — not a logic gap.
