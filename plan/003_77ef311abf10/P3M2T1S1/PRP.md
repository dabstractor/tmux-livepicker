name: "P3.M2.T1.S1 — Create tests/test_preview_clip.sh (clip no-reflow + candidate residual + restore window-size + reflow fallback)"
description: Validation work item (PRD §15.22 + §22 verification). Create ONE test file `tests/test_preview_clip.sh` — a sourced library (sourced by run.sh, defines `test_*` functions, per-test fresh socket) — that drives the REAL `scripts/livepicker.sh` activate + `scripts/restore.sh` (via `input-handler.sh cancel`) on the isolated `-L` harness WITH an attached client (clip needs `display-message -p '#{window_height}'`). Four hermetic `test_*` functions: (a) clip self-window no-reflow across the status 1→2 grow (byte-identical `window_layout`/`window_height`); (b) candidate residual — one-time link-time resize, NO per-nav reflow (byte-identical re-link); (c) restore — driver session-scoped `window-size` byte-exact (unset→unset) + global never touched + panes back to natural; (d) reflow fallback — `window-size` never touched, status DID grow, window DID reflow (23→22). Mirrors `test_scroll_width.sh`'s activate/restore lifecycle (NOT `test_preview.sh`, which skips the client). Cites `clip_verification.md` (P3.M1.T1.S1 GATE) + `clip_probe_findings.md` §4 assert shapes for the exact verifications.

---

## Goal

**Feature Goal**: Prove PRD §22 "clip instead of reflow" works end-to-end through the REAL activate/restore path and that the `reflow` escape hatch still behaves as the legacy one-row reflow. The clip implementation (P3.M1.T2.S1: `opt_preview_fit()` + `ORIG_WINDOW_SIZE` save → `manual` + `resize-window -y H0` freeze in activate T3 → byte-exact restore in restore STEP 4) is the system under test. This task writes the formal, hermetic, auto-discovered test that P3.M1.T2.S1 deferred (its Level 2 was an ad-hoc probe).

**Deliverable**: One NEW file `tests/test_preview_clip.sh` — a sourced library (NO runner, NO side effects on source) defining four `test_*` functions that run.sh auto-discovers via `compgen -A function | grep '^test_'` and runs each against a fresh isolated socket. Each test attaches a pty client, drives the real `livepicker.sh` → `input-handler.sh cancel`, and asserts observable tmux state via the shipped `assert_eq`/`assert_contains`/`fail` helpers. Nothing else is created or modified.

**Success Definition**: `bash tests/run.sh` stays green with the four new tests passing: (a) clip leaves the self-window `window_layout` BYTE-IDENTICAL across the status grow (no reflow); (b) a linked candidate reflows ONCE at link time and is BYTE-IDENTICAL on re-link (no per-nav reflow); (c) cancel leaves the driver's session-scoped `window-size` byte-identical to pre-activate (unset→unset) and the global untouched, with panes returned to natural size; (d) with `@livepicker-preview-fit reflow`, `window-size` is never touched, status DOES grow, and the window DOES reflow (the legacy path). The real tmux server is byte-identical before/after the suite (PRD §15).

## User Persona

**Target User**: The maintainer / future contributor who needs confidence that the §22 clip feature actually eliminates the activation status-grow jank and that the `reflow` fallback still works, expressed as repeatable, hermetic assertions rather than the throwaway probe in P3.M1.T2.S1's Level 2.

**Use Case**: `bash tests/run.sh` (or CI) runs the whole suite; the four `test_preview_clip_*` functions verify clip + reflow against the isolated harness, and a regression in the freeze recipe (e.g. someone removes the `resize-window -y H0` pin) turns `test_clip_*` red immediately.

## Why

- PRD §22 "Verification required (load-bearing)" + §16 "Preview clip feasibility" demand empirical proof that `manual` clips an oversized window. P3.M1.T1.S1 PROVED the recipe (clip_probe_findings.md / clip_verification.md) and corrected it (`manual` alone fails on 3.6b; the `resize-window -y H0` pin is load-bearing). P3.M1.T2.S1 CODED it. This task LOCKS that proof into the shipped suite so a regression is caught, not re-derived by hand.
- The clip freeze is the most version-sensitive, subtle piece of the plugin (window-size semantics + shared linked windows + the `=`/`@`/`-g` gotchas). A regression here silently re-introduces the single most visible activation artifact (the one-row pane reflow). The test must encode the EXACT byte-equality shape the probe used.
- Integrates with the existing test contract: run.sh sources it, setup_test gives each `test_*` a fresh socket, helpers.sh provides the assertions. It is a peer of test_scroll_width.sh / test_restore.sh — same lifecycle, different invariants.

## What

A new `tests/test_preview_clip.sh` with four `test_*` functions (auto-discovered, hermetic) + one shared `_lp_clip_setup` helper. Each test does `attach_test_client` → drive the real `livepicker.sh`/`input-handler.sh`/`preview.sh` → assert via `assert_eq`/`fail`. No new user-visible behavior; pure validation.

### Success Criteria

- [ ] `tests/test_preview_clip.sh` exists, is a sourced library (no runner, no side effects on source), and `shellcheck` clean (mirrors the sibling disable block).
- [ ] `test_clip_self_window_no_reflow`: driver active-window `window_layout` AND `window_height` are byte-identical before vs after a real `livepicker.sh` activate (status 1→2). Also asserts the freeze ran (`window-size`==`manual`, status==`2`).
- [ ] `test_clip_candidate_no_per_nav_reflow`: link alpha → beta → alpha; the alpha-linked window `window_layout` is byte-identical between the two alpha links (no per-nav reflow); the one-time link-time resize is observed/documented (bounded).
- [ ] `test_clip_restore_window_size_byte_exact`: a full activate→cancel cycle leaves `show-options -t driver -v window-size` byte-identical to pre-activate (unset→unset) and `show-options -g -v window-size` unchanged (global never touched); the self-window height returns to the pre-activate value (panes natural).
- [ ] `test_reflow_fallback_grows_and_restores`: with `@livepicker-preview-fit reflow`, `window-size` is never touched by activate OR restore, status DOES grow to 2, and the window DOES reflow (layout/height CHANGE 23→22); cancel restores byte-exact.
- [ ] `bash tests/run.sh` exits 0 (all existing tests + the four new ones green); the real tmux server's session list is byte-identical before/after (PRD §15).

## All Needed Context

### Context Completeness Check

_"If someone knew nothing about this codebase, would they have everything needed to implement this successfully?"_ — Yes. This PRP pins the exact lifecycle to mirror (test_scroll_width.sh activate/restore, NOT test_preview.sh), the EXACT assert shapes from clip_probe_findings.md §4 + §3 + §2 (with verbatim expected layout strings + the corrected recipe), the harness contract (run.sh auto-discovery, per-test setup_test, attach_test_client mandatory), the four test functions' steps, and the gotchas (client-mandatory, @id not index, global-never-touched, empty-baseline window-size). The system under test (P3.M1.T2.S1's opt_preview_fit + freeze + restore) is treated as a CONTRACT per the parallel-execution note. No guessing about tmux behavior is required — every assertion was probed on 3.6b.

### Documentation & References

```yaml
# MUST READ — load into the context window before writing the test.

- file: plan/003_77ef311abf10/P3M1T1S1/research/clip_probe_findings.md
  why: THE evidence + assert shapes. §4 is the verbatim self-window no-reflow assert
        (window_layout + window_height byte-equal). §3 is the candidate residual (one-time
        link-time resize 40->22; byte-identical re-link = no per-nav reflow; source view also
        changes — shared window). §2 is the isolation check (driver=manual, alpha=empty,
        global=latest). §0 are the gotchas (= breaks set-option -t; pty 80x24; @id not index).
  critical: "use window_layout (embeds a 4-hex checksum + per-node dims -> CHANGES on reflow).
        byte-identical == no reflow. expected self-window: L0==L1==4a2d,80x23,..., H0==H1==23.
        expected alpha-linked: 6004,80x22,... read LIVE, never hardcode."

- file: plan/003_77ef311abf10/architecture/clip_verification.md
  why: THE GATE decision doc (P3.M1.T1.S1). §2 treatment == byte-identical layout across the
        grow (the proof). §4 candidate residual reconciled with README bugfix-001. §5 gotchas.
        Confirms clip is feasible + default; manual alone FAILS; the resize-pin is load-bearing.
  section: "§2 the treatment evidence; §3 the recipe (what P3.M1.T2 implemented); §4 the residual"

- file: plan/003_77ef311abf10/P3M1T2S1/PRP.md
  why: THE system-under-test CONTRACT (running in parallel). Its deliverables are exactly what
        these tests exercise: opt_preview_fit() (default clip), ORIG_WINDOW_SIZE save, the T3
        b.5 freeze (manual + resize-window -y H0 BEFORE the grow), the restore STEP 4 window-size
        restore (set-option -u -t when empty = byte-exact). Treat as implemented-as-specified.
  section: "Implementation Patterns (the freeze + restore verbatim); Validation Level 2 (the
        ad-hoc probe these tests FORMALIZE — its CLIP/REFLOW blocks are the test bodies' skeleton)"

- file: plan/003_77ef311abf10/P3M2T1S1/research/test_preview_clip_findings.md
  why: THIS task's own synthesis — the lifecycle reconciliation, the four test bodies' exact
        steps, the determinism decisions (preview.sh-direct for the candidate residual), and the
        test-specific gotchas. Read FIRST; it is the TL;DR of everything below.

- file: tests/test_scroll_width.sh            # THE lifecycle template to mirror
  why: THE mirror for activate/restore WITH an attached client. _lp_scroll_setup =
        attach_test_client + livepicker.sh; cancel via input-handler.sh; byte-exact restore
        assertion shape (test_client_resized_hook_restored_*). Copy its header (shellcheck
        disable block, set -u inherited note, CONTRACT comment) + its _lp_*_setup helper idiom.
  pattern: 'attach_test_client; "$LIVEPICKER_SCRIPTS/livepicker.sh" >/dev/null; <assert>;
        "$LIVEPICKER_SCRIPTS/input-handler.sh" cancel >/dev/null; <assert byte-exact>'

- file: tests/test_preview.sh                 # the DIRECT-preview seam + style (NOT the lifecycle)
  why: shows preview.sh can be driven DIRECTLY with a session name (the candidate-residual test
        reuses this: preview.sh alpha / beta). Also the @livepicker-* state-seeding idiom and the
        test_* function-discovery contract. NOTE: it deliberately skips attach_test_client because
        preview.sh is client-INDEPENDENT — do NOT copy THAT; clip needs the client (see findings §1).
  pattern: 'lp_preview_seed_state (seed ORIG_SESSION/ORIG_WINDOW); preview.sh <name>;
        assert via show-option -gqv @livepicker-linked-id'

- file: tests/setup_socket.sh                 # the harness (attach_test_client, baseline fixtures)
  why: attach_test_client (script pty, reports 80x24 -> driver usable 23/22); TEST_DRIVER_SESSION
        ="driver"; baseline fixtures alpha/beta (alpha/beta are detached, source size 40). teardown
        is per-test via run.sh's setup_test/teardown_test — the test does NOT call them.
  gotcha: "attach_test_client's pty is 80x24, NOT setup_socket's 120x40. window_height reads 23
        (status on) / 22 (status 2). Detached alpha/beta keep 40 (why a linked candidate resizes
        down at link time)."

- file: tests/helpers.sh                      # assert_eq / assert_contains / fail / pass / setup_test
  why: the assertion layer. assert_eq a b msg (POSIX eq); assert_contains str sub msg (case-glob);
        fail msg (sets TEST_STATUS=fail, never exits); pass msg (narration). setup_test pins
        @livepicker-preview-defer OFF -> nav preview is SYNCHRONOUS (no race on residual asserts).
  pattern: 'assert_eq "$L0" "$L1" "msg"; fail "msg"; [ "$x" != "$y" ] || fail "msg"'

- file: tests/run.sh                          # the runner (auto-discovery)
  why: run.sh sources setup_socket.sh + helpers.sh + every test_*.sh, then per test_*
        calls setup_test "lp-$$-<name>" -> runs test_* in the CURRENT shell -> reads TEST_STATUS
        -> teardown_test. So the test file SOURCES NOTHING and calls NO setup_test. Discovery is
        `compgen -A function | grep '^test_' | sort` -> name functions test_*.

- file: scripts/livepicker.sh                 # activate flow (READ-ONLY; the SUT)
  why: confirms the self-window is the active window at freeze time. T2 initial index == current
        session (driver); T3 b.5 (P3.M1.T2) freezes ORIG_WINDOW; T5 first preview is the
        SELF-SESSION (preview.sh "$orig_session" -> self guard -> select ORIG_WINDOW, NO link) ->
        active window stays ORIG_WINDOW. So post-activate the driver's active @id IS the pinned
        self-window. Line ~273: `case "$orig_status"` grows status on->2.
  pattern: "capture the active @id via list-windows -f '#{window_active}' -> it IS ORIG_WINDOW post-activate"

- file: scripts/restore.sh                    # restore flow (READ-ONLY; the SUT)
  why: confirms restore order. STEP 1 unlink preview; STEP 2 re-select ORIG_WINDOW; STEP 3
        switch-client; STEP 4 shrink status THEN (P3.M1.T2) restore window-size; STEP 5
        select-layout (ORIG_LAYOUT). So after cancel: status back to 'on', window-size unset,
        panes natural (height back to H0). cancel is invoked via input-handler.sh cancel.
  pattern: '"$LIVEPICKER_SCRIPTS/input-handler.sh" cancel >/dev/null -> full restore'

- file: scripts/options.sh                    # opt_preview_fit() (READ-ONLY; added by P3.M1.T2)
  why: opt_preview_fit() returns the enum (clip default / reflow). The reflow test sets
        @livepicker-preview-fit reflow explicitly; the clip tests set clip explicitly (or rely on
        the default). Clear_all_state PRESERVES @-config so the setting holds across a test.
  pattern: 'tmux set-option -g @livepicker-preview-fit reflow  (or clip)'

- url: https://github.com/tmux/tmux/blob/master/CHANGES  (window-size semantics, display-message)
  why: window-size is a SESSION option (-t isolates); manual leaves the window's size alone;
        resize-window -y accepts a value LARGER than the client (that IS the clip); display-message
        -p '#{window_height}'/'#{window_layout}' read the client-driven size (needs an attached client).
```

### Current Codebase tree (run `ls tests/` in the project root)

```bash
tmux-livepicker/
├── scripts/            # the system under test (P3.M1.T2 edited options/state/livepicker/restore)
│   ├── options.sh      #   opt_preview_fit() (clip|reflow)            [added by P3.M1.T2]
│   ├── state.sh        #   ORIG_WINDOW_SIZE                           [added by P3.M1.T2]
│   ├── livepicker.sh   #   T3 b.5 freeze (manual + resize -y H0)      [added by P3.M1.T2]
│   ├── restore.sh      #   STEP 4 window-size restore                 [added by P3.M1.T2]
│   ├── preview.sh / input-handler.sh / utils.sh / ...  (untouched by this task)
├── tests/
│   ├── run.sh                  # the runner (sources + discovers test_* + per-test setup_test)
│   ├── setup_socket.sh         # harness: attach_test_client, teardown_socket, baseline fixtures
│   ├── helpers.sh              # assert_eq/assert_contains/fail/pass + setup_test/teardown_test
│   ├── test_scroll_width.sh    # THE lifecycle mirror (activate/restore WITH a client)
│   ├── test_preview.sh         # direct-preview seam + style (client-INDEPENDENT — do NOT copy that)
│   ├── test_restore.sh         # byte-exact restore idiom (status/hooks round-trip)
│   ├── test_pollution.sh / test_functional.sh / ...  (the rest of the suite)
│   └── test_preview_clip.sh    # ← THIS TASK CREATES THIS FILE
├── plan/003_77ef311abf10/
│   ├── architecture/{clip_verification.md (GATE), empirical_findings.md (Finding 2 residual), ...}
│   ├── P3M1T1S1/research/clip_probe_findings.md   # the assert shapes + gotchas
│   ├── P3M1T2S1/PRP.md                            # the SUT contract
│   └── P3M2T1S1/{PRP.md (THIS file), research/test_preview_clip_findings.md}
├── PRD.md              # §22 + §15.22 + §16 (READ-ONLY)
└── README.md           # @livepicker-preview-fit row + limitation note (owned by P3.M1.T2 / P4)
```

### Desired Codebase tree with files to be added and responsibility of file

```bash
# ONE new file. Nothing else is created or modified by this task.
tests/test_preview_clip.sh   # NEW — sourced library; 4 test_* functions + _lp_clip_setup helper.
                             # Validates PRD §15.22 + §22 through the real activate/restore path.
                             # Auto-discovered by run.sh; per-test fresh socket via setup_test.
```

### Known Gotchas of our codebase & the harness (all probed on 3.6b)

```bash
# CRITICAL (clip_probe_findings.md §0 + clip_verification.md §5):

# 1. attach_test_client is MANDATORY (UNLIKE test_preview.sh). The freeze reads
#    display-message -p '#{window_height}' (the pin target); on a client-less socket
#    window_height reads the creation size 40 and window-size behavior reverts to
#    detached -> the whole test is meaningless. harness sleep 0.5 (attach) is enough;
#    add sleep 0.3 after activate/grow and sleep 0.2 after each preview.sh link.

# 2. window_layout embeds a 4-hex checksum + per-node dims -> it CHANGES on reflow.
#    byte-identical window_layout across the status grow == no reflow == the proof.
#    (clip_verification.md gotcha #7.) Assert L0 == L1 (string equality) + H0 == H1.

# 3. Address windows by @id, NEVER index. Driver windows are at index 1/2 (renumber
#    on); '=driver:0' -> "can't find window: 0". Read the active @id via
#    list-windows -t "=$TEST_DRIVER_SESSION" -F '#{window_id}' -f '#{window_active}'
#    and target it with -t "$AW" (the var already holds @3; NEVER -t "@$AW" -> @@3).

# 4. The baseline driver has NO session window-size override ->
#    `show-options -t "$TEST_DRIVER_SESSION" -v window-size` returns EMPTY pre-activate
#    (inherits global 'latest'). So the byte-exact restore asserts "" -> "". P3.M1.T2's
#    restore uses `set-option -u -t` for exactly that. (2>/dev/null || true: unset -> empty.)

# 5. NEVER assert/expect window-size on the GLOBAL scope to change. Clip sets ONLY the
#    per-session value (-t driver). `show-options -g -v window-size` must be byte-identical
#    across EVERY test (PRD §15 zero-trace). Assert it explicitly in the restore test.

# 6. The self-window is the driver's ACTIVE window at freeze time == ORIG_WINDOW. T5's
#    first preview is the SELF-SESSION (livepicker.sh ~420 preview.sh "$orig_session" ->
#    self guard -> select ORIG_WINDOW, NO link). So post-activate the driver's active @id
#    IS the pinned self-window — read it fresh each time (do not cache across cancel).

# 7. set -u is INHERITED from helpers.sh (do NOT re-declare; mirror the sibling shellcheck
#    disable block: SC2154/SC2016/SC2034/SC2086). fail() sets TEST_STATUS=fail and NEVER
#    exits — use it for every negative assertion; never `exit`/`return-nonzero-to-abort`
#    (run.sh reads TEST_STATUS in the CURRENT shell).

# 8. run.sh auto-discovers test_* via compgen -A function | grep '^test_' | sort. Name the
#    four functions test_* so they register. The file SOURCES NOTHING and calls NO
#    setup_test/teardown_test (run.sh does that per function -> each is hermetic).

# 9. setup_test pins @livepicker-preview-defer OFF -> nav preview (input-handler
#    next-session) runs preview.sh SYNCHRONOUSLY (no -b race). So the candidate-residual
#    sequence (preview.sh alpha/beta) is deterministic. (The deferred path is test_responsiveness.)

# 10. Determinism is GOOD (clip_verify_run1.log == run2.log byte-identical). The layout
#     strings are stable across fresh sockets, so byte-equality assertions are sound and
#     do not need fuzz/tolerance.
```

## Implementation Blueprint

No data models — this task writes one bash test library. The "structure" is the four `test_*` functions + one shared setup helper, mirroring `_lp_scroll_setup` in test_scroll_width.sh.

### Implementation Tasks (ordered by dependencies)

```yaml
Task 1: READ the cited research + the two lifecycle templates (NO writes)
  - READ: plan/003_77ef311abf10/P3M2T1S1/research/test_preview_clip_findings.md (THIS task's synthesis — FIRST)
  - READ: plan/003_77ef311abf10/P3M1T1S1/research/clip_probe_findings.md §0 + §2 + §3 + §4 (assert shapes + gotchas)
  - READ: plan/003_77ef311abf10/architecture/clip_verification.md §2 + §4 + §5 (the GATE proof + residual + gotchas)
  - READ: plan/003_77ef311abf10/P3M1T2S1/PRP.md "Implementation Patterns" + "Validation Level 2" (the SUT + the probe skeleton)
  - READ: tests/test_scroll_width.sh (THE lifecycle mirror: header, _lp_scroll_setup, attach_test_client,
        livepicker.sh, input-handler.sh cancel, byte-exact restore assert), tests/test_preview.sh
        (direct preview.sh seam + lp_*_seed_state idiom), tests/setup_socket.sh (attach_test_client +
        TEST_DRIVER_SESSION + baseline fixtures), tests/helpers.sh (assert_eq/assert_contains/fail/pass),
        tests/run.sh (auto-discovery contract)
  - PURPOSE: internalize the EXACT assert shapes (byte-equal window_layout/height), the corrected
        recipe under test (manual + resize-pin, NOT manual alone), the lifecycle (attach_test_client
        MANDATORY), and the four test bodies. Do NOT re-probe tmux — cite the findings.

Task 2: CREATE tests/test_preview_clip.sh — header + shared _lp_clip_setup helper
  - CREATE: tests/test_preview_clip.sh with the sibling header: shebang, the shellcheck disable block
        (SC2154/SC2016/SC2034/SC2086 — the harness provides TEST_STATUS/fail/assert_*/attach_test_client/
        $LIVEPICKER_SCRIPTS/$TEST_DRIVER_SESSION via run.sh's sources), the CONTRACT comment (sourced by
        run.sh; per-test setup_test; attach_test_client MANDATORY; set -u inherited — do NOT re-declare).
  - IMPLEMENT: `_lp_clip_setup [fit]` (default "clip"): attach_test_client; tmux set-option -g
        @livepicker-preview-fit "$fit" (explicit, not default-reliant); capture the driver's ACTIVE @id
        (AW) + its window_layout (L0) + window_height (H0) BEFORE activate; run
        `"$LIVEPICKER_SCRIPTS/livepicker.sh" >/dev/null`; sleep 0.3. Echo/return AW/L0/H0 via globals
        (e.g. set locals in each caller instead, OR print — simplest: have callers inline the capture
        so each test owns its locals). RECOMMENDATION: make _lp_clip_setup do attach+set+activate+sleep
        and have each test capture its own AW/L0/H0 (mirrors _lp_scroll_setup's "activate then caller
        asserts" split — but clip needs the BEFORE-capture, so the test captures BEFORE calling the
        helper OR the helper takes the capture responsibility; choose ONE and keep locals local).
  - FOLLOW pattern: _lp_scroll_setup (attach_test_client; "$LIVEPICKER_SCRIPTS/livepicker.sh"; set state).
  - NAMING: _lp_clip_setup; test_clip_self_window_no_reflow; test_clip_candidate_no_per_nav_reflow;
        test_clip_restore_window_size_byte_exact; test_reflow_fallback_grows_and_restores.
  - PLACEMENT: tests/test_preview_clip.sh (the ONLY file).

Task 3: test_clip_self_window_no_reflow — PRD §22 / §15.22 no-reflow (clip mode)
  - STEPS: attach_test_client; set @livepicker-preview-fit clip; capture AW (driver active @id),
        L0=display-message -p -t "$AW" '#{window_layout}', H0=...#'#{window_height}'; record
        ws_before=`show-options -t "$TEST_DRIVER_SESSION" -v window-size 2>/dev/null || true` (=="");
        run livepicker.sh >/dev/null; sleep 0.3; capture L1/H1 the SAME way (AW is unchanged — still
        the pinned ORIG_WINDOW); capture ws_after + status_now.
  - ASSERT: assert_eq "$L0" "$L1" 'self-window layout unchanged across status grow (no reflow)';
        assert_eq "$H0" "$H1" 'self-window height pinned (clip, not reflow)';
        assert_eq "$status_now" "2" 'status grew to 2';
        assert_eq "$ws_after" "manual" 'freeze set the driver window-size to manual'.
  - FOLLOW assert shape: clip_probe_findings.md §4 (verbatim). Read L/H LIVE; never hardcode 23/4a2d.
  - GOTCHA: the active window is ORIG_WINDOW (self-session first preview) — re-read the @id post-activate
        to be safe (list-windows -f '#{window_active}'); it must equal the pre-activate AW.
  - CLEANUP: input-handler.sh cancel >/dev/null (restores; teardown_test kills the socket anyway, but
        cancel proves restore is callable — optional; include for symmetry with the restore test).

Task 4: test_clip_candidate_no_per_nav_reflow — PRD §22 residual / §16 limitation (clip mode)
  - STEPS: _lp_clip_setup clip (self pinned, status grown). Then the deterministic residual sequence
        using the DIRECT preview.sh seam (mirrors test_preview.sh; avoids list-order fragility):
        "$LIVEPICKER_SCRIPTS/preview.sh" alpha; sleep 0.2  (link alpha: source 40 -> driver usable, one-time);
        alpha_wid=`list-windows -t "=$TEST_DRIVER_SESSION" -F '#{window_id}' -f '#{window_active}'`;
        LA1=`display-message -p -t "$alpha_wid" '#{window_layout}'`;
        "$LIVEPICKER_SCRIPTS/preview.sh" beta;  sleep 0.2  (unlink alpha, link beta);
        "$LIVEPICKER_SCRIPTS/preview.sh" alpha; sleep 0.2  (re-link alpha);
        alpha_wid2=`...active @id...`; LA2=`...layout...`.
  - ASSERT: assert_eq "$LA1" "$LA2" 'candidate: no per-nav additional reflow (link-time resize only)'.
  - DOCUMENT the residual (bounded): capture alpha's SOURCE height before the first link
        (`display-message -p -t "=$alpha_src_wid" '#{window_height}'` == 40) and note LA1's height is
        the driver usable size (22) — the one-time link-time resize IS the documented limitation
        (README bugfix-001). Optional assert that alpha-linked height (e.g. 22) != source (40) to prove
        the link-time resize happened once; the LOAD-BEARING assert is LA1==LA2.
  - FOLLOW shape: clip_probe_findings.md §3 / clip_verification.md §4. expected LA1==LA2==
        `6004,80x22,0,0{40x22,0,0,1,39x22,41,0,7}` (read live). preview.sh reads ORIG_SESSION/ORIG_WINDOW
        which activate set -> no re-seed needed.
  - CLEANUP: input-handler.sh cancel >/dev/null.

Task 5: test_clip_restore_window_size_byte_exact — PRD §9/§15 restore + zero-trace (clip mode)
  - STEPS: attach_test_client; set clip; record ws_sess_before=`show-options -t "$TEST_DRIVER_SESSION"
        -v window-size 2>/dev/null || true` (==""), ws_global_before=`show-options -g -v window-size`,
        H0 (active height); run livepicker.sh; sleep 0.3; assert frozen (ws==manual) as a precondition;
        run "$LIVEPICKER_SCRIPTS/input-handler.sh" cancel >/dev/null; sleep 0.3; record ws_sess_after,
        ws_global_after, H_after (active height).
  - ASSERT: assert_eq "$ws_sess_after" "$ws_sess_before" 'restore: driver window-size byte-exact (unset->unset)';
        assert_eq "$ws_global_after" "$ws_global_before" 'restore: global window-size never touched (PRD §15)';
        assert_eq "$H_after" "$H0" 'restore: panes returned to natural size (height back to pre-activate)';
        also assert status restored: `show-options -gv status` == the pre-activate value (on).
  - FOLLOW shape: test_scroll_width.sh test_client_resized_hook_restored_unset_prior (byte-exact before/after).
  - GOTCHA: the session-scoped read is EMPTY pre-activate (baseline has no override); 2>/dev/null||true
        normalizes unset->""; assert "" -> "". set -u: guard empties (use `|| true` on show-options).

Task 6: test_reflow_fallback_grows_and_restores — PRD §22 "Control" reflow escape hatch
  - STEPS: attach_test_client; tmux set-option -g @livepicker-preview-fit reflow; record ws_sess_before
        (==""), ws_global_before, L0/H0 (active layout/height); run livepicker.sh; sleep 0.3; record
        ws_sess_after, status_now, L1/H1; run input-handler.sh cancel; sleep 0.3; record ws_sess_post,
        ws_global_post.
  - ASSERT (the INVERSE of clip): assert_eq "$ws_sess_after" "$ws_sess_before" 'reflow: window-size
        untouched on activate (clip gate skipped)'; assert_eq "$status_now" "2" 'reflow: status DID grow';
        [ "$L0" != "$L1" ] || fail 'reflow: window SHOULD have reflowed across the grow (legacy path)';
        [ "$H0" != "$H1" ] || fail 'reflow: height SHOULD have changed (23->22)';  (layout/height CHANGE
        proves the one-row reflow fires when clip is off); assert_eq "$ws_sess_post" "$ws_sess_before"
        'reflow: window-size still untouched after restore'; assert_eq "$ws_global_post" "$ws_global_before"
        'reflow: global window-size never touched'.
  - FOLLOW shape: the reflow block of P3.M1.T2S1 PRP Validation Level 2 (the REFLOW probe skeleton).
  - GOTCHA: reflow's reflow makes L0 != L1 (23->22). The 80x24 pty => H0==23 (status on), H1==22 (status 2).
        Read live; assert CHANGE (not equality) — this is the one test where inequality is the pass signal.

Task 7: VALIDATE (see Validation Loop) — shellcheck + the full suite + non-pollution.
  - shellcheck tests/test_preview_clip.sh (clean; mirror the sibling disable block).
  - bash tests/run.sh (exit 0; the 4 new tests PASS; existing suite UNBROKEN).
  - Non-pollution: real server session list byte-identical before/after (PRD §15).
```

### Implementation Patterns & Key Details

```bash
#!/usr/bin/env bash
# tests/test_preview_clip.sh — tmux-livepicker PRD §15.22 + §22 clip/reflow validation (P3.M2.T1.S1).
# Drives the REAL scripts/livepicker.sh activate + scripts/restore.sh (via input-handler.sh cancel) +
# scripts/preview.sh (candidate link) on the isolated -L harness WITH an attached client (the freeze
# reads display-message -p '#{window_height}'). Cites P3.M1.T1.S1 clip_probe_findings.md (assert shapes)
# + clip_verification.md (the GATE) + P3.M1.T2.S1 PRP (the SUT). Mirrors test_scroll_width.sh's
# activate/restore lifecycle (NOT test_preview.sh, which skips the client — preview.sh is client-
# independent; clip is NOT).
# shellcheck disable=SC2154,SC2016,SC2034,SC2086
#   SC2154: TEST_STATUS/fail/assert_*/attach_test_client/$LIVEPICKER_SCRIPTS/$TEST_DRIVER_SESSION are
#           provided by run.sh's sources (setup_socket.sh + helpers.sh). set -u INHERITED (helpers.sh).

# _lp_clip_setup [fit] — attach a client, set @livepicker-preview-fit, ACTIVATE the picker. Caller
# captures the BEFORE state (AW/L0/H0/window-size) BEFORE calling this (it runs livepicker.sh).
_lp_clip_setup() {
	local fit="${1:-clip}"
	attach_test_client
	tmux set-option -g @livepicker-preview-fit "$fit"
	"$LIVEPICKER_SCRIPTS/livepicker.sh" >/dev/null
	sleep 0.3   # let the synchronous resize-pin + status grow settle
}

# (a) §22 no-reflow: the self-window (driver active == ORIG_WINDOW) is byte-identical across the grow.
test_clip_self_window_no_reflow() {
	attach_test_client
	tmux set-option -g @livepicker-preview-fit clip
	local AW L0 H0
	AW="$(tmux list-windows -t "=$TEST_DRIVER_SESSION" -F '#{window_id}' -f '#{window_active}')"
	L0="$(tmux display-message -p -t "$AW" '#{window_layout}')"
	H0="$(tmux display-message -p -t "$AW" '#{window_height}')"
	"$LIVEPICKER_SCRIPTS/livepicker.sh" >/dev/null
	sleep 0.3
	# the active window is still ORIG_WINDOW (first preview is the self-session -> select, no link)
	local AW2 L1 H1
	AW2="$(tmux list-windows -t "=$TEST_DRIVER_SESSION" -F '#{window_id}' -f '#{window_active}')"
	L1="$(tmux display-message -p -t "$AW2" '#{window_layout}')"
	H1="$(tmux display-message -p -t "$AW2" '#{window_height}')"
	assert_eq "$AW2" "$AW"  'self-session: active window unchanged (no link on first preview)'
	assert_eq "$L1" "$L0"   'clip: self-window layout unchanged across status grow (no reflow)'
	assert_eq "$H1" "$H0"   'clip: self-window height pinned (clip, not reflow)'
	assert_eq "$(tmux show-options -gv status)" "2"            'clip: status grew to 2'
	assert_eq "$(tmux show-options -t "$TEST_DRIVER_SESSION" -v window-size 2>/dev/null || true)" "manual" \
		'clip: driver window-size frozen to manual (the freeze ran)'
	"$LIVEPICKER_SCRIPTS/input-handler.sh" cancel >/dev/null
}

# (b) §22 residual / §16 limitation: linked candidate reflows ONCE at link time; NO per-nav reflow.
test_clip_candidate_no_per_nav_reflow() {
	_lp_clip_setup clip        # self pinned (status grown); activate set ORIG_SESSION/ORIG_WINDOW
	# alpha/beta are baseline detached sessions (source size 40) — link them via the direct seam.
	local alpha_wid LA1 alpha_wid2 LA2
	"$LIVEPICKER_SCRIPTS/preview.sh" alpha; sleep 0.2          # link alpha: 40 -> driver usable (one-time)
	alpha_wid="$(tmux list-windows -t "=$TEST_DRIVER_SESSION" -F '#{window_id}' -f '#{window_active}')"
	LA1="$(tmux display-message -p -t "$alpha_wid" '#{window_layout}')"
	"$LIVEPICKER_SCRIPTS/preview.sh" beta;  sleep 0.2          # unlink alpha, link beta
	"$LIVEPICKER_SCRIPTS/preview.sh" alpha; sleep 0.2          # re-link alpha
	alpha_wid2="$(tmux list-windows -t "=$TEST_DRIVER_SESSION" -F '#{window_id}' -f '#{window_active}')"
	LA2="$(tmux display-message -p -t "$alpha_wid2" '#{window_layout}')"
	assert_eq "$LA2" "$LA1" 'candidate: no per-nav additional reflow (link-time resize only)'
	"$LIVEPICKER_SCRIPTS/input-handler.sh" cancel >/dev/null
}

# (c) §9/§15 restore + zero-trace: window-size byte-exact (unset->unset); global never touched; panes natural.
test_clip_restore_window_size_byte_exact() {
	attach_test_client
	tmux set-option -g @livepicker-preview-fit clip
	local ws_sess_before ws_global_before status_before H0
	ws_sess_before="$(tmux show-options -t "$TEST_DRIVER_SESSION" -v window-size 2>/dev/null || true)"   # ""
	ws_global_before="$(tmux show-options -g -v window-size)"
	status_before="$(tmux show-options -gv status)"
	H0="$(tmux display-message -p -t "$(tmux list-windows -t "=$TEST_DRIVER_SESSION" -F '#{window_id}' -f '#{window_active}')" '#{window_height}')"
	"$LIVEPICKER_SCRIPTS/livepicker.sh" >/dev/null; sleep 0.3
	# precondition: the freeze ran (driver is manual)
	assert_eq "$(tmux show-options -t "$TEST_DRIVER_SESSION" -v window-size 2>/dev/null || true)" "manual" \
		'restore precondition: freeze set window-size manual'
	"$LIVEPICKER_SCRIPTS/input-handler.sh" cancel >/dev/null; sleep 0.3
	local ws_sess_after ws_global_after status_after H_after
	ws_sess_after="$(tmux show-options -t "$TEST_DRIVER_SESSION" -v window-size 2>/dev/null || true)"
	ws_global_after="$(tmux show-options -g -v window-size)"
	status_after="$(tmux show-options -gv status)"
	H_after="$(tmux display-message -p -t "$(tmux list-windows -t "=$TEST_DRIVER_SESSION" -F '#{window_id}' -f '#{window_active}')" '#{window_height}')"
	assert_eq "$ws_sess_after" "$ws_sess_before" 'restore: driver window-size byte-exact (unset->unset)'
	assert_eq "$ws_global_after" "$ws_global_before" 'restore: global window-size never touched (PRD §15)'
	assert_eq "$status_after" "$status_before" 'restore: status restored (2->on)'
	assert_eq "$H_after" "$H0" 'restore: panes returned to natural size (height back to pre-activate)'
}

# (d) §22 "Control" reflow escape hatch: window-size NEVER touched; status grows; window DOES reflow.
test_reflow_fallback_grows_and_restores() {
	attach_test_client
	tmux set-option -g @livepicker-preview-fit reflow
	local ws_sess_before ws_global_before L0 H0
	ws_sess_before="$(tmux show-options -t "$TEST_DRIVER_SESSION" -v window-size 2>/dev/null || true)"
	ws_global_before="$(tmux show-options -g -v window-size)"
	L0="$(tmux display-message -p -t "$(tmux list-windows -t "=$TEST_DRIVER_SESSION" -F '#{window_id}' -f '#{window_active}')" '#{window_layout}')"
	H0="$(tmux display-message -p -t "$(tmux list-windows -t "=$TEST_DRIVER_SESSION" -F '#{window_id}' -f '#{window_active}')" '#{window_height}')"
	"$LIVEPICKER_SCRIPTS/livepicker.sh" >/dev/null; sleep 0.3
	local ws_sess_after status_now L1 H1
	ws_sess_after="$(tmux show-options -t "$TEST_DRIVER_SESSION" -v window-size 2>/dev/null || true)"
	status_now="$(tmux show-options -gv status)"
	L1="$(tmux display-message -p -t "$(tmux list-windows -t "=$TEST_DRIVER_SESSION" -F '#{window_id}' -f '#{window_active}')" '#{window_layout}')"
	H1="$(tmux display-message -p -t "$(tmux list-windows -t "=$TEST_DRIVER_SESSION" -F '#{window_id}' -f '#{window_active}')" '#{window_height}')"
	assert_eq "$ws_sess_after" "$ws_sess_before" 'reflow: window-size untouched on activate (clip gate skipped)'
	assert_eq "$status_now" "2" 'reflow: status DID grow (legacy path)'
	[ "$L0" != "$L1" ] || fail 'reflow: window SHOULD have reflowed across the grow (layout changed 23->22)'
	[ "$H0" != "$H1" ] || fail 'reflow: height SHOULD have changed (23->22)'
	"$LIVEPICKER_SCRIPTS/input-handler.sh" cancel >/dev/null; sleep 0.3
	assert_eq "$(tmux show-options -t "$TEST_DRIVER_SESSION" -v window-size 2>/dev/null || true)" "$ws_sess_before" \
		'reflow: window-size still untouched after restore'
	assert_eq "$(tmux show-options -g -v window-size)" "$ws_global_before" 'reflow: global window-size never touched'
}
```

### Integration Points

```yaml
TEST RUNNER (tests/run.sh):
  - auto-discovery: run.sh sources setup_socket.sh + helpers.sh + every tests/test_*.sh (incl. the new
    file), then `compgen -A function | grep '^test_' | sort` -> name the 4 functions test_*.
  - per-test hermetic: run.sh calls setup_test "lp-$$-<name>" -> fresh isolated -L socket + baseline
    fixtures (driver/alpha/beta) + @livepicker-preview-defer OFF, runs test_* in the CURRENT shell,
    reads TEST_STATUS, teardown_test. The test file SOURCES NOTHING and calls NO setup_test/teardown_test.

SYSTEM UNDER TEST (P3.M1.T2.S1 — implemented in parallel; treat as CONTRACT):
  - scripts/options.sh opt_preview_fit()  -> clip (default) | reflow. The reflow test sets reflow
    explicitly; clip tests set clip explicitly (deterministic, not default-reliant).
  - scripts/state.sh ORIG_WINDOW_SIZE     -> saved activate, read restore, auto-cleared.
  - scripts/livepicker.sh T3 b.5          -> freeze (manual + resize-window -y H0) BEFORE the status grow.
  - scripts/restore.sh STEP 4             -> window-size restore AFTER the status shrink (set-option -u -t
    when the saved value was empty -> byte-exact unset->unset).

INVARIANTS THESE TESTS ENCODE:
  - clip never uses -g (global) window-size -> assert global byte-identical in (c) and (d).
  - clip never touches window-size in reflow mode -> assert session empty->empty in (d).
  - the freeze pins ORIG_WINDOW (the active self-window) -> assert byte-identical layout in (a).
  - the residual is one-time + per-nav-stable -> assert LA1==LA2 in (b).
```

## Validation Loop

### Level 1: Syntax & Style (Immediate Feedback)

```bash
cd /home/dustin/.config/tmux/plugins/tmux-livepicker
# shellcheck the new file (project uses shellcheck; mirror the sibling disable block — SC2154/SC2016/
# SC2034/SC2086 are the documented harness-contract false positives).
shellcheck tests/test_preview_clip.sh
# Expected: zero errors (the disable block covers the harness-provided globals + the eval/word-split idioms).
bash -n tests/test_preview_clip.sh        # syntax sanity (sourcing has no side effects by contract)
# Expected: no syntax errors. Sourcing the file defines functions ONLY (no server, no output).
```

### Level 2: The four new tests pass (the core deliverable)

```bash
cd /home/dustin/.config/tmux/plugins/tmux-livepicker
bash tests/run.sh 2>&1 | grep -E 'test_(clip|reflow)' || true
# Expected (4 PASS):
#   PASS  test_clip_candidate_no_per_nav_reflow
#   PASS  test_clip_restore_window_size_byte_exact
#   PASS  test_clip_self_window_no_reflow
#   PASS  test_reflow_fallback_grows_and_restores
# If test_clip_self_window_no_reflow FAILS on the layout assert: the freeze did NOT pin the self-window
#   -> P3.M1.T2.S1's freeze is missing the resize-window -y H0 pin (manual alone fails on 3.6b).
#   Report as a P3.M1.T2.S1 bug (clip_probe_findings.md cond B); do NOT weaken the assertion.
# If test_clip_restore_window_size_byte_exact FAILS (session window-size residue): P3.M1.T2.S1's restore
#   left a session-scoped value -> it must use the set-option -u -t branch (unset->unset). Report, do NOT weaken.
# If test_reflow_fallback FAILS on the layout-CHANGED assert: reflow is accidentally still freezing -> the
#   clip gate (`if [ clip ]`) is not skipping reflow. Report, do NOT weaken.
```

### Level 3: Regression — existing suite stays green

```bash
cd /home/dustin/.config/tmux/plugins/tmux-livepicker
bash tests/run.sh
# Expected: exit 0. KEY suites to eyeball (the clip feature must NOT have regressed them — though this
# task writes ONLY a test file, a wrong assert that mutates shared state could):
#   - test_restore.sh: byte-exact status/status-format/key-table/hooks restore (window-size global untouched).
#   - test_pollution.sh: browsing fires no client-session-changed.
#   - test_preview.sh / test_scroll_width.sh: activate->nav->confirm/cancel under clip default.
# If any pre-existing test newly FAILS: a test_* in test_preview_clip.sh mutated shared state without
#   canceling (every test_* MUST end with input-handler.sh cancel, and teardown_test kills the socket
#   anyway). Ensure each test_* restores/cancels before returning.
```

### Level 4: Non-pollution (the core invariant, PRD §15)

```bash
cd /home/dustin/.config/tmux/plugins/tmux-livepicker
BEFORE="$(/usr/bin/tmux list-sessions -F '#{session_name}' 2>/dev/null | sort)"
bash tests/run.sh >/dev/null 2>&1
AFTER="$(/usr/bin/tmux list-sessions -F '#{session_name}' 2>/dev/null | sort)"
[ "$BEFORE" = "$AFTER" ] && echo "REAL SERVER UNTOUCHED" || echo "POLLUTION — abort"
# Expected: REAL SERVER UNTOUCHED. All window-size/layout mutations are on the isolated -L socket only.
```

### Level 5: Creative & Domain-Specific Validation

```bash
cd /home/dustin/.config/tmux/plugins/tmux-livepicker
# Confirm the test file is a SOURCED LIBRARY (no side effects on source, no runner):
bash -c 'source tests/test_preview_clip.sh; compgen -A function | grep "^test_" | sort'
# Expected (4 functions listed, no server started, no output side effects):
#   test_clip_candidate_no_per_nav_reflow
#   test_clip_restore_window_size_byte_exact
#   test_clip_self_window_no_reflow
#   test_reflow_fallback_grows_and_restores
# Confirm the test never references global window-size mutation (clip is per-session -t only):
grep -nE 'set-option -g window-size|set-option -g .*window-size' tests/test_preview_clip.sh   # MUST be empty
# Confirm every test_* cancels/restores (no leaked picker state across the suite):
grep -c 'input-handler.sh cancel' tests/test_preview_clip.sh   # >= number of test_* that activate
# Expected: the disable block lists SC2154/SC2016/SC2034/SC2086 (matches the sibling headers).
```

## Final Validation Checklist

### Technical Validation
- [ ] Level 1: `shellcheck tests/test_preview_clip.sh` clean; `bash -n` passes; sourcing has no side effects.
- [ ] Level 2: the four `test_*` functions PASS via `bash tests/run.sh`.
- [ ] Level 3: `bash tests/run.sh` exit 0 (existing suite UNBROKEN).
- [ ] Level 4: real tmux server byte-identical before/after (PRD §15).
- [ ] Level 5: the file is a sourced library (4 `test_*` discoverable; no `-g window-size`; cancels present).

### Feature Validation
- [ ] (a) clip: self-window `window_layout` AND `window_height` byte-identical across the status grow; driver frozen `manual`; status grew to 2.
- [ ] (b) clip candidate: linked window byte-identical on re-link (no per-nav reflow); the one-time link-time resize is observed/bounded.
- [ ] (c) clip restore: session-scoped `window-size` byte-exact (unset→unset); global never touched; status restored; panes back to natural (height == pre-activate).
- [ ] (d) reflow: `window-size` untouched on activate AND restore; status grew to 2; window DID reflow (layout/height CHANGED); restore byte-exact.
- [ ] The assertions match the EXACT shapes in clip_probe_findings.md §4 (self) + §3 (candidate) + P3.M1.T2S1 PRP Level 2 (reflow) — byte-equality for clip, byte-inequality for reflow.

### Code Quality Validation
- [ ] Mirrors test_scroll_width.sh's header (shellcheck disable block, set -u inherited note, CONTRACT comment).
- [ ] Uses the shipped helpers (assert_eq/assert_contains/fail/pass) — NO custom assertion machinery.
- [ ] `attach_test_client` in EVERY test_* (clip is NOT client-independent, unlike test_preview.sh).
- [ ] `local` for all function locals; TABS for indent; addresses windows by @id (never index, never `@$AW`).
- [ ] Every test_* ends with `input-handler.sh cancel` (restore symmetry); teardown_test kills the socket regardless.
- [ ] Reads L/H/window-size LIVE; never hardcodes 23 / 22 / 4a2d / 6004 / `manual`.

### Documentation & Deployment
- [ ] The header comment cites PRD §15.22 + §22, P3.M1.T1.S1 (clip_probe_findings.md / clip_verification.md), P3.M1.T2.S1 (the SUT), and explains WHY it mirrors test_scroll_width.sh not test_preview.sh.
- [ ] No edits to scripts/, README.md, CHANGELOG.md, PRD.md, or any tasks.json (this task writes ONE test file).

---

## Anti-Patterns to Avoid

- ❌ Don't mirror test_preview.sh's lifecycle (client-INDEPENDENT). Clip lives in the ACTIVATE path and reads `display-message -p '#{window_height}'`; without `attach_test_client`, window_height reads the creation size (40) and the freeze never pins — the test is meaningless. Mirror test_scroll_width.sh (attach_test_client → livepicker.sh → input-handler.sh cancel).
- ❌ Don't assert `manual`-alone pins the window — it does NOT on 3.6b (clip_probe_findings.md cond B). The load-bearing step is `resize-window -y H0`. If the self-window reflows, that is a P3.M1.T2.S1 BUG (missing pin) — REPORT it, do NOT weaken the byte-identical assertion to tolerate a reflow.
- ❌ Don't `set-option -g window-size` or assert the GLOBAL window-size changes — clip is per-session (`-t driver`) only. The global must be byte-identical across every test (PRD §15). Assert it.
- ❌ Don't address windows by index (`=driver:0` → "can't find window") or write `-t "@$AW"` (→ `@@3`). Read the active `@id` via `list-windows -f '#{window_active}'` and use `-t "$AW"` (the var already holds `@N`).
- ❌ Don't hardcode 23/22/4a2d/6004. The pty is 80x24 here but a real client may differ; the layout checksum is environment-specific. Read `window_height`/`window_layout` LIVE and assert equality/inequality, not literal values.
- ❌ Don't rely on the DEFAULT of `opt_preview_fit` in the clip tests — set `@livepicker-preview-fit clip` explicitly (and `reflow` in the reflow test). Deterministic + self-documenting; survives a future default change.
- ❌ Don't `exit`/`return-nonzero-to-abort` on failure — run.sh reads `TEST_STATUS` in the CURRENT shell; a bare `exit` kills the runner. Signal failure ONLY via `fail`/`assert_*`.
- ❌ Don't redeclare `set -u` (inherited from helpers.sh) or omit the shellcheck disable block (the harness globals are the documented SC2154 false positives).
- ❌ Don't write a runner/main in the file or call setup_test/teardown_test — run.sh sources the file, auto-discovers `test_*`, and runs the per-test socket cycle. The file defines functions ONLY.
- ❌ Don't re-probe tmux behavior or re-derive the recipe — cite clip_probe_findings.md / clip_verification.md (READ-ONLY). The test ENCODES their conclusions; it does not rediscover them.
- ❌ Don't test the candidate LINK-TIME clip (`resize-window -y H` in preview.sh) — that is future polish, NOT shipped by P3.M1.T2. The residual test (b) asserts the CURRENT behavior: one-time link-time resize to usable size + no per-nav reflow.
- ❌ Don't weaken a failing assertion to "make it pass". If (a)/(c)/(d) fail, the bug is in P3.M1.T2.S1 (the SUT), not in this test. Report it; the byte-equality/byte-inequality assertions are the load-bearing proof.
- ❌ Don't touch scripts/, README.md, CHANGELOG.md, PRD.md, empirical_findings.md, clip_verification.md, or any tasks.json (all read-only / owned elsewhere). This task writes ONLY tests/test_preview_clip.sh.

---

## Confidence Score: 9/10

The assertions are already PROVEN on this exact box: clip_probe_findings.md §2/§3/§4 + clip_verification.md §2 give the byte-identical layout strings (self `4a2d,80x23`, candidate `6004,80x22`) and the corrected recipe (manual + resize-pin). The lifecycle mirror (test_scroll_width.sh) is a shipping sibling that already does attach_test_client → livepicker.sh → input-handler.sh cancel with byte-exact restore asserts. The harness contract (run.sh auto-discovery, per-test setup_test, attach_test_client mandatory) is fully documented. The SUT (P3.M1.T2.S1) is treated as a contract per the parallel-execution note. Residual 1/10: (a) the exact settle sleeps (0.3 after activate, 0.2 after each link) — the probe used these; if a test flakes, bump them (the operations are synchronous, so this is cheap insurance, not a correctness risk); (b) the candidate-residual test assumes `preview.sh alpha/beta` re-seeds nothing (activate set ORIG_SESSION/ORIG_WINDOW) — confirmed by reading preview.sh + test_preview.sh, but verify the re-link leaves alpha byte-identical (the shared-window behavior makes this deterministic per clip_probe_findings.md §3). The implementer's job is to translate four proven probe blocks into four hermetic `test_*` functions using the shipped harness + assertions — not to discover tmux behavior.
