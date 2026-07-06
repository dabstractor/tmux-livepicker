# PRP — P1.M7.T6.S1: `tests/test_restore.sh` + `tests/test_keyrepurpose.sh` + `tests/test_create.sh`

---

## Goal

**Feature Goal**: **CREATE** three PRD §15.20–22 validation test files —
`tests/test_restore.sh`, `tests/test_keyrepurpose.sh`, `tests/test_create.sh` —
each a **sourced** bash library defining `test_*` functions that drive the COMPLETE
real plugin (`scripts/livepicker.sh` → `input-handler.sh` → `preview.sh` →
`restore.sh`, all COMPLETE P1.M1–M6) **directly** (contract §1: the scripts, NOT via
keypress) against the **socket-isolated** tmux server provided by the COMPLETE
harness (`tests/setup_socket.sh` P1.M7.T1.S1 + `tests/helpers.sh` P1.M7.T2.S1), and
assert the observable signals. Each test gets a fresh isolated server (run.sh's
per-test `setup_test`/`teardown_test` cycle), attaches a client (every driven script
needs one — FINDING 7), exercises one PRD §15.20–22 bullet, and signals pass/fail via
`fail`/`assert_*` (which set `TEST_STATUS`). `bash tests/run.sh` discovers and runs
them (alongside the sibling test files) and exits 0/1.

The crux of this cluster is **byte-exact restoration proof** (§15.21: snapshot
`show-options -g` + `show-hooks -g` + `#{window_layout}` before activate, drive
activate→nav→cancel, assert all three byte-identical after), the **key-repurpose
revert** (§15.20: `C-M-Tab`/`C-M-BTab` resolve to session-nav during the picker via
the `livepicker` table, and revert to window-nav after because `key-table` returns to
`root` — no binding save/restore), and **create-on-enter** (§15.22: session+create-on
creates+activates; create-off and window-mode create nothing).

**Deliverable** (THREE new files):
- `tests/test_restore.sh` — 2 `test_*` (PRD §15.21 Restore byte-exact proof).
- `tests/test_keyrepurpose.sh` — 2 `test_*` (PRD §15.20 Key repurpose).
- `tests/test_create.sh` — 3 `test_*` (PRD §15.22 Create-on-enter).

Each is a SOURCED library (run.sh sources `setup_socket.sh` + `helpers.sh` + every
`test_*.sh` first; the assert helpers, `$LIVEPICKER_SCRIPTS`, `$TEST_DRIVER_SESSION`,
`attach_test_client`, and the isolated bare-`tmux` shim are all in scope before any
`test_*` runs). No side effects on source (defines functions only).

**Success Definition**:
- `bash -n` + `shellcheck` pass on all three files (0 findings beyond a file-level
  `# shellcheck disable=SC2154,SC2016,SC2034,SC2086`; tabs only; `set -u` inherited —
  NOT re-declared, mirror `test_self.sh`/`test_functional.sh`).
- `bash tests/run.sh` runs all 7 new `test_*` (plus the sibling tests), each prints
  **PASS**, the suite summary is `N passed, 0 failed`, exit **0**.
- Each `test_*` attaches a client, drives the real `$LIVEPICKER_SCRIPTS/{livepicker,
  input-handler}.sh` directly, and asserts the exact PRD §15.20–22 observable signals
  verified empirically (research FINDINGS 3/4/5/6).
- **The real user server is provably untouched**: `/usr/bin/tmux list-sessions` is
  byte-identical before/after a full `run.sh` invocation (the harness owns isolation).
- `git diff --stat` shows ONLY the three new files added (NO edits to
  `setup_socket.sh`/`helpers.sh`/`run.sh`, NO `scripts/*`, NO PRD/tasks — FORBIDDEN).

## User Persona (if applicable)

**Target User**: the contributor running the suite (`bash tests/run.sh`) and the future
maintainer extending the restore/key/create checks. The test files have no end-user
surface (DOCS: Mode A — none; they are test infra).

**Use Case**: a contributor runs `bash tests/run.sh`; run.sh gives each `test_*`
function a fresh isolated socket, the function attaches a client, drives the real plugin
(activate + navigate + cancel/confirm, or type + confirm), and asserts tmux state via
`assert_*`/`fail`; run.sh reports PASS/FAIL + exits 0/1. Each test is hermetic (per-test
fresh server) so an option mutation in one cannot leak into another.

**User Journey** (per test): `setup_test` (run.sh) → `attach_test_client` → (optional
`set-option -g @livepicker-*`) → snapshot (restore only) → `livepicker.sh` activate →
(nav / type / confirm / cancel) → `show-options`/`show-hooks`/`list-keys`/
`display-message`/`has-session` → `assert_*`/`fail` → (control returns to run.sh) →
`teardown_test`.

**Pain Points Addressed**:
- (a) **No restore / key-repurpose / create tests existed.** T3.S1's functional tests
  assert activation/typing/nav/confirm/cancel integration (one display-message
  assertion each). T5.S1 owns the pollution proof. T6.S1 owns the **byte-exact restore
  proof** (§15.21), the **key-repurpose contract** (§15.20), and the **create-on-enter
  matrix** (§15.22). These three are the remaining §15 validation clusters.
- (b) **The "grep livepicker" false-fail (FINDING 2).** The contract's literal "assert
  `show-options -g | grep livepicker` is empty" FALSE-FAILS because the dormant §11
  config (`@livepicker-fg`/`@livepicker-key`, sourced from tmux.conf) survives cancel
  (CORRECTION A in state.sh). This PRP uses the **byte-identical full-options snapshot**
  (FINDING 3) as the correct, stronger substitute — it proves exact restore AND that no
  runtime/orig keys leaked.
- (c) **The "table unbound" nuance (FINDING 4).** After cancel the `livepicker` table is
  not merely empty — `unbind-key -a -T livepicker` makes tmux report it non-existent
  (`list-keys -T livepicker` rc=1, empty stdout). The assertion captures + empty-tests
  (robust under `set -u`/no-`-e`), not a raw rc check.

## Why

- **PRD §15.21 Restore** is the controlling spec for `test_restore.sh` (the byte-exact
  restore bullets), **§15.20 Key repurpose** for `test_keyrepurpose.sh` (during/after
  keys), **§15.22 Create-on-enter** for `test_create.sh` (the 3-bullet create matrix).
- **Scope cohesion.** T6.S1 is the Restore/Key/Create cluster of module P1.M7
  (Validation). T1.S1 (socket isolation), T2.S1 (assertions + discovery + runner),
  T3.S1 (functional), T4.S1 (preview), T5.S1 (pollution) are COMPLETE. T6.S1 owns the
  LAST three §15 validation clusters. It does NOT own the harness or the plugin scripts.
- **PRD §8/§9** (the repurposed-key subsystem + the state-save/restore contract) describe
  the mechanisms these tests prove. system_context INVARIANT B (a non-root key-table is
  fully modal; the root bindings are never consulted during the picker and never mutated)
  is the spine of the key-repurpose test. PRD §6 Confirm + §11 config describe the
  create-on-enter logic.

## What

**CREATE** three files: `tests/test_restore.sh`, `tests/test_keyrepurpose.sh`,
`tests/test_create.sh`. No other file is touched (`setup_socket.sh`/`helpers.sh`/
`run.sh` are owned by T1.S1/T2.S1 — COMPLETE, READ-ONLY here; `scripts/*` are
COMPLETE/IMMUTABLE — driven, never edited; PRD/tasks/prd_snapshot are READ-ONLY). Each
file is **SOURCED** by `run.sh` (defines `test_*` + any `lp_*` helpers only; NO side
effects on source; NO top-level execution; NO `setup_test`/`teardown_test` calls —
run.sh owns the per-test cycle).

### Success Criteria

- [ ] All three files pass `bash -n` + `shellcheck` (file-level `disable` for
      SC2154/SC2016/SC2034/SC2086 at most); tabs only; `set -u` inherited (NOT
      re-declared); no `set -e`/`pipefail`.
- [ ] `test_restore.sh` defines exactly 2 `test_*`; `test_keyrepurpose.sh` exactly 2;
      `test_create.sh` exactly 3. Each `test_*` calls `attach_test_client` (FINDING 7).
- [ ] Each `test_*` drives the real `$LIVEPICKER_SCRIPTS/{livepicker,input-handler}.sh`
      directly; signals failure ONLY via `fail`/`assert_*` (NEVER `exit`).
- [ ] `bash tests/run.sh` prints `PASS` for all 7 (+ the sibling tests), summary
      `N passed, 0 failed`, exit 0.
- [ ] `/usr/bin/tmux list-sessions` byte-identical before/after a full `run.sh`.
- [ ] `git diff --stat` shows ONLY the three new files added.

## All Needed Context

### Context Completeness Check

_Pass_: a developer who has never seen this repo can implement T6.S1 from (a) the
ready-to-paste test bodies in "Implementation Patterns & Key Details"; (b) the 9 findings
in `research/restore_keyrepurpose_create_findings.md` — most critically **FINDING 3**
(the byte-identical snapshot is the restore proof AND subsumes the corrected "grep"
clause), **FINDING 2** (the "grep livepicker" false-fail trap), **FINDING 4** (the table
is GONE, not empty), **FINDING 5** (key-repurpose during/after verbatim bindings), and
**FINDING 6** (the create matrix); and (c) the live probes that confirmed all scenarios
PASS on the isolated socket. The INPUTS are the COMPLETE harness (`tests/setup_socket.sh`
+ `tests/helpers.sh`, read in full), the COMPLETE runner (`tests/run.sh`), and the
COMPLETE driven scripts (`scripts/livepicker.sh`, `input-handler.sh`, `restore.sh`).

### Documentation & References

```yaml
# MUST READ — the empirical + idiomatic ground-truth for THIS task (9 findings + PROBES).
- docfile: plan/001_fd5d622d3939/P1M7T6S1/research/restore_keyrepurpose_create_findings.md
  why: FINDING 1 (isolated server sources tmux.conf -> root C-M-Tab/C-M-BTab present +
        dormant §11 config present); FINDING 2 (THE "grep livepicker" TRAP -> use the
        byte-identical snapshot); FINDING 3 (the byte-identical options+hooks+layout
        snapshot is the restore proof AND subsumes the corrected grep clause); FINDING 4
        (list-keys -T livepicker is GONE after cancel -> capture+empty-test); FINDING 5
        (key repurpose verbatim bindings during/after + root binding byte-identical);
        FINDING 6 (create-on exists+active / create-off nothing / window-mode nothing);
        FINDING 7 (attach_test_client FIRST); FINDING 8 (house style); FINDING 9 (validated).
  critical: Read BEFORE writing. FINDING 2 is the single most likely false-fail cause.

# MUST READ — the harness contract this task CONSUMES (read in full; COMPLETE).
- file: tests/setup_socket.sh
  why: the isolation layer. setup_socket seeds driver/alpha/beta baseline (driver has a
        2nd "extra" multi-pane window) + exports TEST_SOCKET/TMUX_SOCK_DIR/REAL_TMUX/
        LIVEPICKER_ROOT/LIVEPICKER_SCRIPTS/TEST_DRIVER_SESSION("driver")/
        TEST_FIXTURE_SESSIONS("alpha beta"). Provides attach_test_client/detach_test_client
        (the `script`-pty attach — needed because livepicker.sh activate uses display-message
        + refresh-client -S and confirm/cancel use switch-client — FINDING 7). SOURCED
        library (no side effects on source). Mirror its header STYLE. DO NOT EDIT IT.
  pattern: run.sh's setup_test calls setup_socket per test (fresh -L socket + PATH shim ->
        bare `tmux` hits ONLY the isolated socket). The isolated server sources the user
        tmux.conf -> root C-M-Tab/C-M-BTab bindings + dormant @livepicker-fg/@livepicker-key
        are present (FINDING 1).

# MUST READ — the assertion + per-test helpers this task CONSUMES (COMPLETE).
- file: tests/helpers.sh
  why: provides fail/pass/assert_eq/assert_contains + setup_test/teardown_test (THIN
        delegates to setup_socket) + the TEST_STATUS global. assert_eq is POSIX equality
        (handles the multi-line sorted options/hooks comparison). assert_contains uses a
        `case` with "$sub" quoted (literal substring, glob-safe). In scope because run.sh
        sources helpers.sh before test_*.sh. DO NOT EDIT IT.
  pattern: assert_eq a b msg -> [ "$a" = "$b" ] else fail; the b argument may contain an
        embedded newline ($() captured multi-line output) -> POSIX = compares the whole
        string. Signal failure ONLY via fail/assert_* (run.sh reads TEST_STATUS in the
        CURRENT shell).

# MUST READ — the runner (T2.S1; COMPLETE).
- file: tests/run.sh
  why: run.sh sources setup_socket.sh + helpers.sh + every tests/test_*.sh, then PER test:
        setup_test "lp-$$-<name>" (-> fresh isolated socket + PATH shim + baseline fixtures
        driver/alpha/beta) -> resets TEST_STATUS=pass -> runs the test_* in the CURRENT shell
        -> reads TEST_STATUS -> PASS/FAIL -> teardown_test. The CONTRACT for test bodies:
        define test_* ONLY (no side effects on source); signal failure ONLY via fail/assert_*
        (NEVER exit — run.sh reads TEST_STATUS in the current shell; a bare exit kills the
        runner). nullglob globs test_*.sh -> the 3 new files are picked up automatically.
  critical: run.sh sources ALL test_*.sh (alphabetical: test_create, test_functional,
        test_pollution, test_preview, test_restore, test_self) BEFORE discovering/running any
        test_*. test_functional.sh's lp_runtime_cleared IS defined at run time, but keep each
        file SELF-CONTAINED (do NOT rely on cross-file helpers — house style).

# MUST READ — the sibling functional-test FILE (the CONTRACT for style + attach idiom).
- file: tests/test_functional.sh
  why: the closest sibling — it ALSO drives livepicker.sh + input-handler.sh with an attached
        client (attach_test_client FIRST) and asserts display-message/list-windows state.
        Mirror its header CONTRACT comment, the lp_*-helper idiom, the dynamic display-message
        reads, the inline-`case` for negative assertions, and test_escape_restores's
        capture-orig-state-before-activate pattern. Its lp_runtime_cleared documents the SAME
        "grep livepicker" false-fail correction (FINDING 2 / its FINDING 2).
  critical: copy the "attach_test_client FIRST" discipline. test_escape_restores captures
        orig_sess/orig_win/orig_status/orig_kt via display-message/show-option BEFORE activate
        — test_restore.sh generalizes this to the FULL sorted show-options/show-hooks snapshot
        (byte-identical, not field-by-field).

# MUST READ — the sibling preview-test FILE (the structural template + lp_* idiom).
- file: tests/test_preview.sh
  why: the structural template — mirror its header CONTRACT, the lp_preview_seed_state helper
        idiom, the dynamic window-id reads, the inline-`case` negatives, and the file-skeleton
        style. (It is CLIENT-INDEPENDENT — NO attach; T6.S1 is the OPPOSITE: every test_*
        attaches a client — FINDING 7. Do NOT copy preview.sh's "no attach" rule.)

# MUST READ — the preceding pollution-test PRP (the module template for THIS PRP).
- docfile: plan/001_fd5d622d3939/P1M7T5S1/PRP.md
  why: T5.S1 is the immediately-preceding test-cluster PRP — mirror its section structure,
        header-contract style, the "SOURCED by run.sh / NO side effects on source / NEVER
        exit" rules, the 4-level validation loop, and the non-pollution Level-4 check. T6.S1
        is its analog for the Restore/Key/Create clusters (3 files, no stand-in recorder).
  critical: T5.S1's three correctness points (fixtures-before-attach, the recorder's baked
        shim path, the synchronous hook) are POLLUTION-specific and NOT needed here. T6.S1
        needs only attach_test_client FIRST + the byte-identical snapshot + list-keys/has-session
        assertions.

# MUST READ — the scripts this task DRIVES (COMPLETE P1.M4/M5/M6; read the relevant parts).
- file: scripts/livepicker.sh
  why: the activate orchestrator. STEP 2 saves ORIG_SESSION/WINDOW/LAYOUT (display-message),
        key-table/status/renumber-windows (tmux_save_opt), the FULL session-window-changed hook
        (tmux_get_hook), and the status-format array (state_status_format_save). T4 copies
        prefix+root bindings into livepicker, binds explicit keys LAST (override), switches
        key-table to livepicker (-g), suppresses the hook. T5 sets mode on + first preview.
        activate GROWS status + installs status-format[lp_idx]=#(renderer.sh). NONE of activate
        mutates the root table (INVARIANT B).
- file: scripts/input-handler.sh
  why: the input dispatcher. next-session = index=(idx+1)%L wrap + preview.sh target + refresh
        (NEVER switch-client — Invariant A). confirm = re-filter; if target: window mode ->
        select-window + restore keep (NO create); session mode -> _confirm_land_on_session
        (unlink driver preview BEFORE switch, switch once, restore keep). Empty filtered + session
        + create on -> new-session -d -s "$query" + has-session gate -> _confirm_land_on_session
        (create-on-enter). Empty + create off OR window mode -> restore cancel (nothing created).
        cancel = two-step: non-empty filter -> clear it; EMPTY filter -> restore.sh cancel.
- file: scripts/restore.sh
  why: the teardown. STEP 1 unlink preview (empty linked_id -> skip). STEP 2 select-window
        ORIG_WINDOW (always). STEP 3 cancel -> switch-client -t "=ORIG_SESSION"; keep -> no switch.
        STEP 4 restore status + status-format (-gu reset then replay saved indices) + key-table
        (-g) + renumber-windows (-g) + session-window-changed hook (index-preserving, gated on
        opt_suppress_window_hook, preserves -b + abs path). STEP 5 select-layout ORIG_LAYOUT
        (best-effort). STEP 6 clear_all_state + unbind-key -a -T livepicker (table GONE) +
        refresh-client -S. With cancel, the client returns to ORIG_SESSION/ORIG_WINDOW and ALL
        saved global options/hooks round-trip byte-exact (FINDING 3).

# MUST READ — the architecture ground-truth.
- docfile: plan/001_fd5d622d3939/architecture/system_context.md
  why: §2 (verified env: root C-M-Tab/C-M-BTab swap-window bindings + the session-window-changed[0]
        run-shell -b hook + dormant @livepicker-fg/@livepicker-key); §3 INVARIANT B (a non-root
        key-table is fully modal -> root bindings never consulted/mutated during the picker -> the
        revert is free); §4 TRAP 2 (the hook is array-indexed with -b -> restore preserves the
        index + -b + abs path); §9 (shell style: set -u ONLY; tabs; local; quote everything).
  section: "§3 INVARIANT B", "§4 TRAP 2", "§9 Shell style".

# MUST READ — the PRD sections selected for this work item.
- docfile: PRD.md
  why: §15.20 Key repurpose (during -> move sessions; after -> move windows); §15.21 Restore
        (status/status-format/key-table/renumber/hook restored; no @livepicker-* remain [CORRECTED
        to the byte-identical snapshot — FINDING 2/3]; pane layout exact); §15.22 Create-on-enter
        (session+create-on -> created; create-off -> nothing; window -> nothing); §8 (repurposed-key
        subsystem); §9 (state saved/restored contract); §6 Confirm (create-on-enter logic).
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
    setup_socket.sh     # COMPLETE (P1.M7.T1.S1). READ-ONLY. Isolation + exports + attach_test_client.
    helpers.sh          # COMPLETE (P1.M7.T2.S1). READ-ONLY. fail/pass/assert_* + setup_test/teardown_test.
    run.sh              # COMPLETE (P1.M7.T2.S1). READ-ONLY. The runner; sources the files + discovers test_*.
    test_self.sh        # COMPLETE (P1.M7.T2.S1). Sibling.
    test_functional.sh  # COMPLETE (P1.M7.T3.S1). Sibling — the attach + display-message + lp_* idiom source.
    test_preview.sh     # COMPLETE (P1.M7.T4.S1). Sibling — the structural template.
    test_pollution.sh   # (P1.M7.T5.S1 — being implemented in PARALLEL). Sibling — the module template.
  plan/001_fd5d622d3939/{architecture/*.md, tasks.json, prd_snapshot.md, prd_index.txt}
  plan/001_fd5d622d3939/P1M7T6S1/{PRP.md, research/restore_keyrepurpose_create_findings.md}   # THIS
  .gitignore
  # NOTE: tests/test_restore.sh, tests/test_keyrepurpose.sh, tests/test_create.sh do NOT exist yet —
  #       THIS task creates them.
```

### Desired Codebase tree with files to be added and responsibility of file

```bash
tmux-livepicker/
  tests/
    test_restore.sh       # NEW. SOURCED by run.sh (2 test_* only; NO side effects on source). Drives the
                          #   REAL plugin against the isolated socket; asserts PRD §15.21 byte-exact restore.
                          #   attach_test_client FIRST (FINDING 7).
                          #   test_restore_cancel_options_hooks_exact : snapshot `show-options -g | sort` +
                          #       `show-hooks -g | sort` before activate; activate; next-session (link a
                          #       preview); cancel; assert BOTH byte-identical after; assert list-keys -T
                          #       livepicker empty (table GONE — FINDING 4); assert @livepicker-mode empty.
                          #       (The options byte-identity SUBSUMES the corrected "grep livepicker" clause
                          #       — FINDING 2/3: dormant §11 config survives, runtime/orig keys do not.)
                          #   test_restore_cancel_layout_exact : snapshot `#{window_layout}` before activate;
                          #       activate; next-session; cancel; assert layout byte-identical after; assert
                          #       client back on ORIG_SESSION + ORIG_WINDOW (display-message).
    test_keyrepurpose.sh  # NEW. SOURCED by run.sh (2 test_* only; NO side effects on source). Drives the
                          #   REAL plugin; asserts PRD §15.20 key repurpose. attach_test_client FIRST.
                          #   test_keyrepurpose_during_picker : activate; assert list-keys -T livepicker
                          #       C-M-Tab contains "next-session" + C-M-BTab contains "prev-session"; assert
                          #       key-table == livepicker; cancel (cleanup).
                          #   test_keyrepurpose_reverts_after_exit : snapshot list-keys -T root C-M-Tab +
                          #       C-M-BTab before; activate; cancel; assert root C-M-Tab/C-M-BTab byte-
                          #       identical (still "swap-window"); assert key-table == root.
    test_create.sh        # NEW. SOURCED by run.sh (3 test_* only; NO side effects on source). Drives the
                          #   REAL plugin; asserts PRD §15.22 create-on-enter. attach_test_client FIRST.
                          #   test_create_on_creates_and_activates : @livepicker-create on; activate; type a
                          #       unique query char-by-char; confirm; assert has-session "=$query" + client
                          #       active == query + @livepicker-mode empty.
                          #   test_create_off_creates_nothing : @livepicker-create off; activate; type a
                          #       unique query; confirm; assert ! has-session "=$query" + client on driver.
                          #   test_window_mode_creates_nothing : @livepicker-type window; activate; type a
                          #       unique query; confirm; assert ! has-session "=$query".
```

### Known Gotchas of our codebase & Library Quirks

```bash
# CRITICAL (research FINDING 2 — THE "grep livepicker" FALSE-FAIL): the contract's literal "assert
#   `show-options -g | grep livepicker` is empty" FALSE-FAILS. The isolated server sources the user
#   tmux.conf -> the dormant §11 config (@livepicker-fg "#ffffff", @livepicker-key Space) is present,
#   and clear_all_state (state.sh CORRECTION A) PRESERVES §11 config -> those two options REMAIN after
#   cancel. So `grep livepicker` is non-empty.
#   THE FIX (verified, FINDING 3): snapshot the FULL `show-options -g | sort` BEFORE activate and assert
#   it is BYTE-IDENTICAL after activate→nav→cancel. The before-snapshot contains the dormant config but
#   NO runtime/orig @livepicker-* keys; byte-identity forces the after-snapshot to contain the dormant
#   config AND no runtime/orig keys -> it proves exact restore AND no runtime pollution in ONE assert.
#   This is the SAME correction test_functional.sh's lp_runtime_cleared encodes (its FINDING 2).

# CRITICAL (research FINDING 3 — byte-identical restore is PROVABLE): snapshot ALL THREE of
#   `show-options -g | sort`, `show-hooks -g | sort`, and `#{window_layout}` before activate; after
#   activate→nav→cancel assert EACH byte-identical (POSIX = on the captured strings). Verified live:
#   OPTIONS BYTE-IDENTICAL ✓, HOOKS BYTE-IDENTICAL ✓, LAYOUT BYTE-IDENTICAL ✓. sort BOTH sides
#   (dump order is not stable across a grow/restore cycle, but the sorted set is).

# CRITICAL (research FINDING 4 — the livepicker table is GONE, not empty): restore.sh STEP 6 does
#   `unbind-key -a -T livepicker`, which removes EVERY key; tmux then reports the table non-existent.
#   `list-keys -T livepicker` returns "table livepicker doesn't exist" (stderr) + rc=1 + EMPTY stdout.
#   ASSERT via capture + empty-test (robust under set -u/no -e), NOT a raw rc check:
#     out="$(tmux list-keys -T livepicker 2>/dev/null || true)"; assert_eq "$out" "" "table unbound".

# CRITICAL (research FINDING 5 — key repurpose): during the picker, `list-keys -T livepicker C-M-Tab`
#   returns `bind-key -T livepicker C-M-Tab run-shell "<abs>/input-handler.sh next-session"` (rc=0);
#   `list-keys -T livepicker C-M-BTab` returns the prev-session binding. AFTER cancel, the root-table
#   C-M-Tab/C-M-BTab bindings are BYTE-IDENTICAL to before (they were NEVER mutated — INVARIANT B;
#   activate only COPIES prefix+root into livepicker, it does not touch root). The "revert" is free
#   because key-table returns to root. ASSERT: during -> assert_contains "next-session"/"prev-session";
#   after -> assert_contains "swap-window" AND byte-identical to the pre-activate snapshot.
#   `list-keys -T <table> <key>` filters to one key (verified: one line + rc=0 when present, empty +
#   rc=1 when absent). Use assert_contains on the captured line.

# CRITICAL (research FINDING 7 — a CLIENT is required): the driven scripts use display-message -p
#   (activate), refresh-client -S (activate + nav), and switch-client (confirm/cancel). ALL require an
#   attached client. So EVERY test_* calls attach_test_client FIRST (mirrors T3.S1/T5.S1; UNLIKE T4.S1).

# GOTCHA (research FINDING 6 — create-on-enter query MUST be unique): type a query that is NOT a
#   substring of driver/alpha/beta (e.g. "zzzno", "newproj", "qwfx"). Type char-by-char via
#   `"$LIVEPICKER_SCRIPTS/input-handler.sh" type <c>`. With an empty filtered list + session mode +
#   create on, confirm creates the EXACT $query name and switches to it (has-session "=$query" gate).
#   create off OR window mode -> confirm takes the cancel path -> nothing created, client on driver.
#   Set @livepicker-create / @livepicker-type via `tmux set-option -g` BEFORE activate (activate reads
#   opt_type to build the list; confirm reads opt_create/opt_type — both correct when set before activate).

# GOTCHA (snapshot order — restore): capture show-options/show-hooks/window_layout BEFORE activate (the
#   baseline includes the dormant config + the live hook). Activate mutates status/status-format/key-
#   table/renumber/hook + adds runtime @livepicker-*; cancel restores. Compare AFTER cancel. Do NOT
#   capture a second time mid-picker.

# GOTCHA (the hook restore preserves -b + index): the live hook is
#   `session-window-changed[0] run-shell -b <abs>/sync-window-focus.sh`. restore.sh replays it with the
#   index + -b + abs path preserved (TRAP 2). The byte-identical show-hooks snapshot proves it (you do
#   NOT parse the hook line yourself — just diff the dump).

# GOTCHA (POSIX = on multi-line strings): assert_eq a b msg does `[ "$a" = "$b" ]`. a/b may be the
#   multi-line sorted show-options/show-hooks dump ($() strips ONLY the trailing newline; embedded
#   newlines are preserved). POSIX = compares the whole string including embedded newlines. Verified.

# STYLE (research FINDING 8 / system_context §9): shebang #!/usr/bin/env bash; `set -u` INHERITED
#   (helpers.sh/run.sh declare it) — do NOT re-declare (mirror test_self.sh: "`# set -u is inherited`");
#   local for ALL function locals; TABS; quote everything. Signal failure ONLY via fail/assert_* (NEVER
#   exit — run.sh reads TEST_STATUS in the CURRENT shell; a bare exit kills the runner). Each file is
#   SOURCED by run.sh: define test_* + lp_* ONLY; NO side effects on source; NO setup_test/teardown_test
#   calls (run.sh owns the per-test cycle); NO sourcing; NO self-test guard; NO BASH_SOURCE/$0 check.

# GOTCHA: do NOT edit tests/setup_socket.sh, tests/helpers.sh, tests/run.sh, any scripts/* file,
#   test_pollution.sh (parallel sibling), PRD.md, tasks.json, prd_snapshot.md, or .gitignore (FORBIDDEN).
#   This task ADDS exactly THREE files: tests/test_restore.sh, tests/test_keyrepurpose.sh, tests/test_create.sh.
```

## Implementation Blueprint

### Data models and structure

No data model. The "model" is the **byte-exact snapshot + the assertion surface** each
cluster consumes:

```bash
# The shared surface IN SCOPE when each test_* runs (provided by run.sh's sources + setup_test
# — each test_* file SOURCES NOTHING):
#   bare `tmux`              -> the PATH shim -> isolated -L socket (transparent).
#   $LIVEPICKER_SCRIPTS      -> repo scripts/ (exported by setup_socket).
#   $TEST_DRIVER_SESSION     -> "driver" (the attached client's home / activate origin).
#   attach_test_client       -> the `script`-pty attach (from setup_socket).
#   fail/pass/assert_eq/assert_contains + TEST_STATUS -> from helpers.sh.
#
# The CONTRACT for each test_* body:
#   - attach_test_client FIRST (the driven scripts require a client — FINDING 7).
#   - (create/keyrepurpose: optionally set @livepicker-create/@livepicker-type BEFORE activate.)
#   - (restore: snapshot show-options -g | sort + show-hooks -g | sort + window_layout BEFORE activate.)
#   - drive the REAL $LIVEPICKER_SCRIPTS/{livepicker,input-handler}.sh directly.
#   - assert observable state via assert_*/fail (NEVER exit).
#   - run.sh wraps you in setup_test -> test -> teardown_test; do NOT call those.
#
# The assertion primitives used (all from helpers.sh):
#   assert_eq "$captured_after" "$captured_before" "msg"   # POSIX =; multi-line byte-compare.
#   assert_contains "$line" "next-session" "msg"            # case-based literal substring.
#   [ -z "$(...)" ] ... for the "table empty" / "has-session" checks (inline, no subprocess beyond $()).
```

### Implementation Tasks (ordered by dependencies)

```yaml
Task 1: CREATE tests/test_restore.sh — header + 2 restore test_* (PRD §15.21)
  - CREATE: tests/test_restore.sh (NEW; SOURCED by run.sh — NEVER executed directly; no self-test
        guard; no BASH_SOURCE/$0 check).
  - HEADER: #!/usr/bin/env bash ; a CONTRACT comment ("sourced by run.sh; defines 2 test_* only; NO
        side effects on source; NO setup_test/teardown_test calls — run.sh owns the per-test cycle;
        the driven scripts REQUIRE an attached client so attach_test_client is called FIRST; the
        assert helpers, $LIVEPICKER_SCRIPTS, $TEST_DRIVER_SESSION, attach_test_client come from
        run.sh's sources"); `# set -u is inherited` (do NOT re-declare; mirror test_self.sh/
        test_functional.sh); file-level `# shellcheck disable=SC2154,SC2016,SC2034,SC2086`.
  - IMPLEMENT test_restore_cancel_options_hooks_exact:
        attach_test_client; `local opts_before hks_before opts_after hks_after lp_tbl`;
        `opts_before="$(tmux show-options -g | sort)"`; `hks_before="$(tmux show-hooks -g | sort)"`;
        `"$LIVEPICKER_SCRIPTS/livepicker.sh"` (activate); `"$LIVEPICKER_SCRIPTS/input-handler.sh"
        next-session` (link a preview window into the driver); `"$LIVEPICKER_SCRIPTS/input-handler.sh"
        cancel` (empty filter -> full restore cancel); capture `opts_after`/`hks_after` the same way;
        assert_eq "$opts_after" "$opts_before" "global options byte-identical after restore (status,
        status-format, key-table, renumber, AND no runtime @livepicker-* leaked — FINDING 3)";
        assert_eq "$hks_after" "$hks_before" "global hooks byte-identical after restore
        (session-window-changed[0] -b hook preserved — FINDING 3)";
        `lp_tbl="$(tmux list-keys -T livepicker 2>/dev/null || true)"`;
        assert_eq "$lp_tbl" "" "livepicker table unbound after cancel (FINDING 4)";
        assert_eq "$(tmux show-option -gqv @livepicker-mode)" "" "@livepicker-mode disarmed".
  - IMPLEMENT test_restore_cancel_layout_exact:
        attach_test_client; `local layout_before sess_before win_before layout_after`;
        `layout_before="$(tmux display-message -p '#{window_layout}')"`;
        `sess_before="$(tmux display-message -p '#{session_name}')"`;
        `win_before="$(tmux display-message -p '#{window_id}')"`;
        activate; next-session; cancel;
        assert_eq "$(tmux display-message -p '#{window_layout}')" "$layout_before" "original window's
        pane layout byte-exact after restore (select-layout ORIG_LAYOUT — FINDING 3)";
        assert_eq "$(tmux display-message -p '#{session_name}')" "$sess_before" "client back on the
        original session";
        assert_eq "$(tmux display-message -p '#{window_id}')" "$win_before" "client back on the
        original window".
  - DO NOT: use the literal `grep livepicker` (FALSE-FAILS — FINDING 2; the byte-identical options
        snapshot subsumes it); source anything; call setup_test/teardown_test; create fixtures after
        attach; assert a raw rc for list-keys (capture + empty-test).

Task 2: CREATE tests/test_keyrepurpose.sh — header + 2 key-repurpose test_* (PRD §15.20)
  - CREATE: tests/test_keyrepurpose.sh (NEW; SOURCED by run.sh — NEVER executed directly).
  - HEADER: same CONTRACT/style as Task 1 (attach FIRST; set -u inherited; shellcheck disable; tabs;
        NEVER exit). Add a CRITICAL note: "the isolated server sources the user tmux.conf -> the
        root-table C-M-Tab/C-M-BTab swap-window bindings are present before activate (FINDING 1); no
        fixture needed."
  - IMPLEMENT test_keyrepurpose_during_picker:
        attach_test_client; `local next_bind prev_bind`;
        activate;
        `next_bind="$(tmux list-keys -T livepicker C-M-Tab 2>/dev/null || true)"`;
        `prev_bind="$(tmux list-keys -T livepicker C-M-BTab 2>/dev/null || true)"`;
        assert_contains "$next_bind" "next-session" "C-M-Tab repurposed to next-session in the
        livepicker table (FINDING 5)";
        assert_contains "$prev_bind" "prev-session" "C-M-BTab repurposed to prev-session in the
        livepicker table (FINDING 5)";
        assert_eq "$(tmux show-option -gqv key-table)" "livepicker" "key-table is livepicker during
        the picker";
        cancel (cleanup — teardown kills the server anyway, but cancel leaves a clean mid-test state).
  - IMPLEMENT test_keyrepurpose_reverts_after_exit:
        attach_test_client; `local root_before root_after rootb_before rootb_after`;
        `root_before="$(tmux list-keys -T root C-M-Tab 2>/dev/null || true)"`;
        `rootb_before="$(tmux list-keys -T root C-M-BTab 2>/dev/null || true)"`;
        activate; cancel;
        `root_after="$(tmux list-keys -T root C-M-Tab 2>/dev/null || true)"`;
        `rootb_after="$(tmux list-keys -T root C-M-BTab 2>/dev/null || true)"`;
        assert_eq "$root_after" "$root_before" "root C-M-Tab byte-identical before/after (never
        mutated — the revert is free because key-table returns to root; FINDING 5)";
        assert_contains "$root_after" "swap-window" "after exit, C-M-Tab moves windows again";
        assert_contains "$rootb_after" "swap-window" "after exit, C-M-BTab moves windows again";
        assert_eq "$(tmux show-option -gqv key-table)" "root" "key-table reverted to root".
  - DO NOT: expect the root binding to change during/after (it never does — INVARIANT B); rely on
        copying the livepicker binding to root (there is none); source anything; exit.

Task 3: CREATE tests/test_create.sh — header + 3 create-on-enter test_* (PRD §15.22)
  - CREATE: tests/test_create.sh (NEW; SOURCED by run.sh — NEVER executed directly).
  - HEADER: same CONTRACT/style as Task 1 (attach FIRST; set -u inherited; shellcheck disable; tabs;
        NEVER exit). Add a note: "set @livepicker-create/@livepicker-type via set-option -g BEFORE
        activate (activate reads opt_type; confirm reads opt_create/opt_type — FINDING 6)."
  - IMPLEMENT test_create_on_creates_and_activates:
        attach_test_client; `tmux set-option -g @livepicker-create on`;
        `local q="zzzno" c`;
        activate;
        `for c in z z z n o; do "$LIVEPICKER_SCRIPTS/input-handler.sh" type "$c"; done`;
        `"$LIVEPICKER_SCRIPTS/input-handler.sh" confirm`;
        assert the session exists: `[ "$(tmux has-session -t "=$q" 2>/dev/null && echo yes || echo no)" =
        "yes" ] || fail "create-on-enter created the session $q (FINDING 6)"`;
        assert_eq "$(tmux display-message -p '#{session_name}')" "$q" "the new session is active";
        assert_eq "$(tmux show-option -gqv @livepicker-mode)" "" "picker torn down after confirm".
  - IMPLEMENT test_create_off_creates_nothing:
        attach_test_client; `tmux set-option -g @livepicker-create off`;
        `local q="qwfx" c`;
        activate; `for c in q w f x; do ... type "$c"; done`; confirm;
        assert the session does NOT exist: `[ "$(tmux has-session -t "=$q" 2>/dev/null && echo yes ||
        echo no)" != "yes" ] || fail "create-off created nothing ($q must not exist — FINDING 6)"`;
        assert_eq "$(tmux display-message -p '#{session_name}')" "$TEST_DRIVER_SESSION" "client stayed
        on the driver (cancel path)".
  - IMPLEMENT test_window_mode_creates_nothing:
        attach_test_client; `tmux set-option -g @livepicker-type window`;
        `local q="mplg" c`;
        activate; `for c in m p l g; do ... type "$c"; done`; confirm;
        assert the session does NOT exist: `[ "$(tmux has-session -t "=$q" 2>/dev/null && echo yes ||
        echo no)" != "yes" ] || fail "window mode created nothing ($q must not exist — FINDING 6)"`.
  - DO NOT: use a query that is a substring of driver/alpha/beta (use unique tokens); set
        @livepicker-create/@livepicker-type AFTER activate; source anything; exit.

Task 4: VALIDATE (Level 1 lint + Level 2 suite green + Level 4 non-pollution)
  - RUN: bash -n + shellcheck on all three files; `bash tests/run.sh` (expect all 7 new PASS +
        test_self + T3.S1's five + T4.S1's four + T5.S1's three PASS, exit 0); snapshot
        `/usr/bin/tmux list-sessions` before/after a full run.sh and assert byte-identical
        (non-pollution); `git diff --stat` shows ONLY the three new files added.
```

### Implementation Patterns & Key Details

#### test_restore.sh (Task 1)

```bash
#!/usr/bin/env bash
# tests/test_restore.sh — tmux-livepicker PRD §15.21 Restore validation (P1.M7.T6.S1).
#
# SOURCED by run.sh (NEVER executed directly). Defines two test_* functions that drive the
# COMPLETE real plugin (scripts/livepicker.sh -> input-handler.sh -> preview.sh -> restore.sh,
# all COMPLETE P1.M1-M6) DIRECTLY (NOT via keypress — work-item §1) against the socket-
# isolated server the harness provides (tests/setup_socket.sh P1.M7.T1.S1 +
# tests/helpers.sh P1.M7.T2.S1), and assert PRD §15.21: after exit, status / every
# status-format[n] / key-table / renumber-windows / the session-window-changed hook / the
# pane layout are byte-exact, the livepicker table is unbound, and no picker-INTERNAL
# state leaks. Each test attaches a client (the scripts need one), exercises an activate ->
# nav -> cancel cycle, and signals pass/fail via fail/assert_* (which set TEST_STATUS; run.sh
# reads it in the current shell).
#
# CONTRACT: run.sh sources setup_socket.sh + helpers.sh + every tests/test_*.sh, then PER test
# calls setup_test "lp-$$-<name>" (-> fresh isolated socket + PATH shim + baseline fixtures
# driver/alpha/beta) -> resets TEST_STATUS=pass -> runs the test_* in the CURRENT shell -> reads
# TEST_STATUS -> teardown_test. So when a test_* runs: bare `tmux` hits the isolated socket;
# $LIVEPICKER_SCRIPTS, $TEST_DRIVER_SESSION, attach_test_client, fail/pass/assert_eq/
# assert_contains are all IN SCOPE; this file SOURCES NOTHING and calls NO setup_test/teardown_test.
#
# CRITICAL (research FINDING 2 — THE "grep livepicker" FALSE-FAIL): the contract's literal
# "assert `show-options -g | grep livepicker` is empty" FALSE-FAILS — the isolated server sources
# the user tmux.conf so the dormant §11 config (@livepicker-fg/@livepicker-key) is present, and
# clear_all_state PRESERVES §11 config -> those options REMAIN after cancel. THE FIX (FINDING 3):
# snapshot the FULL `show-options -g | sort` BEFORE activate and assert it BYTE-IDENTICAL after.
# The before-snapshot has the dormant config but NO runtime/orig keys -> byte-identity proves exact
# restore AND no runtime pollution in ONE assert (subsumes the corrected grep clause).
#
# CRITICAL (research FINDING 4): the livepicker table is GONE after cancel (unbind-key -a -T
# livepicker -> tmux reports it non-existent). Assert via capture + empty-test, NOT a raw rc.
#
# CRITICAL (research FINDING 7): the driven scripts REQUIRE an attached client -> attach FIRST.
#
# `set -u` is INHERITED from helpers.sh (do NOT re-declare; mirror test_self.sh).
# shellcheck disable=SC2154,SC2016,SC2034,SC2086
#   SC2154: assert_*/attach_test_client/$LIVEPICKER_SCRIPTS/$TEST_DRIVER_SESSION are defined by
#           run.sh's sources, not in this file.

# test_restore_cancel_options_hooks_exact — PRD §15.21 bullets 1-3: after activate -> nav ->
# cancel, the global options + hooks are BYTE-IDENTICAL to pre-activate (status / status-format[*] /
# key-table / renumber-windows restored AND no @livepicker-* runtime/orig keys leaked AND the
# dormant §11 config preserved), the livepicker table is unbound, and @livepicker-mode is disarmed.
test_restore_cancel_options_hooks_exact() {
	attach_test_client
	local opts_before hks_before opts_after hks_after lp_tbl

	# Snapshot the FULL sorted global options + hooks BEFORE activate (the baseline includes the
	# dormant §11 config + the live session-window-changed hook). sort -> stable set compare.
	opts_before="$(tmux show-options -g | sort)"
	hks_before="$(tmux show-hooks -g | sort)"

	"$LIVEPICKER_SCRIPTS/livepicker.sh"                     # activate (grows status, switches key-table)
	"$LIVEPICKER_SCRIPTS/input-handler.sh" next-session     # link a preview window into the driver
	"$LIVEPICKER_SCRIPTS/input-handler.sh" cancel           # empty filter -> full restore cancel

	opts_after="$(tmux show-options -g | sort)"
	hks_after="$(tmux show-hooks -g | sort)"

	# PRD §15.21 b1/b2: options byte-identical (status, status-format[*], key-table, renumber-windows
	# restored) AND no runtime/orig @livepicker-* leaked (the before-snapshot has none -> byte-identity
	# forces the after-snapshot to have none) AND the dormant §11 config correctly survives. This
	# single assert SUBSUMES the corrected "grep livepicker empty" clause (FINDING 2/3).
	assert_eq "$opts_after" "$opts_before" \
		"global options byte-identical after restore (status/format/key-table/renumber restored; no @livepicker-* leaked; §11 config preserved)"
	# PRD §15.21 b2: the session-window-changed[0] run-shell -b hook is restored exactly (index + -b +
	# abs path preserved — TRAP 2). Diffing the whole hook dump proves it (no manual parsing).
	assert_eq "$hks_after" "$hks_before" \
		"global hooks byte-identical after restore (session-window-changed hook with -b preserved)"

	# PRD §15.21 / work-item: the livepicker table is unbound (FINDING 4: unbind-key -a -T livepicker
	# makes tmux report it non-existent -> list-keys stdout is EMPTY; capture + empty-test, not rc).
	lp_tbl="$(tmux list-keys -T livepicker 2>/dev/null || true)"
	assert_eq "$lp_tbl" "" "livepicker key table unbound after cancel (no bindings remain)"

	# The double-activation guard is disarmed (restore clear_all_state).
	assert_eq "$(tmux show-option -gqv @livepicker-mode)" "" "@livepicker-mode disarmed after restore"
}

# test_restore_cancel_layout_exact — PRD §15.21 bullet 4: the original window's pane layout is
# byte-exact (select-layout "$ORIG_LAYOUT") and the client returns to the original session/window.
test_restore_cancel_layout_exact() {
	attach_test_client
	local layout_before sess_before win_before

	# Capture the client's ORIGINAL active-window layout + session + window id BEFORE activate
	# (the driver's active window is the baseline 'extra' multi-pane window — read it live).
	layout_before="$(tmux display-message -p '#{window_layout}')"
	sess_before="$(tmux display-message -p '#{session_name}')"
	win_before="$(tmux display-message -p '#{window_id}')"

	"$LIVEPICKER_SCRIPTS/livepicker.sh"
	"$LIVEPICKER_SCRIPTS/input-handler.sh" next-session     # link a candidate window (changes the layout)
	"$LIVEPICKER_SCRIPTS/input-handler.sh" cancel           # restore: unlink + select ORIG_WINDOW + select-layout

	# PRD §15.21 b4: the pane layout round-trips through select-layout ORIG_LAYOUT byte-for-byte.
	assert_eq "$(tmux display-message -p '#{window_layout}')" "$layout_before" \
		"original window's pane layout byte-exact after restore (select-layout ORIG_LAYOUT)"
	assert_eq "$(tmux display-message -p '#{session_name}')" "$sess_before" \
		"client back on the original session"
	assert_eq "$(tmux display-message -p '#{window_id}')" "$win_before" \
		"client back on the original window"
}
```

#### test_keyrepurpose.sh (Task 2)

```bash
#!/usr/bin/env bash
# tests/test_keyrepurpose.sh — tmux-livepicker PRD §15.20 Key repurpose validation (P1.M7.T6.S1).
#
# SOURCED by run.sh (NEVER executed directly). Defines two test_* functions that drive the
# COMPLETE real plugin DIRECTLY against the socket-isolated server and assert PRD §15.20:
# during the picker C-M-Tab/C-M-BTab move SESSIONS (they are bound in the livepicker table to
# input-handler next-session/prev-session), and after exit they move WINDOWS again (the root-
# table bindings are byte-identical to before — never mutated — and key-table reverts to root).
# Each test attaches a client, exercises one bullet, and signals pass/fail via fail/assert_*.
#
# CONTRACT: (same as test_restore.sh — SOURCED by run.sh; NO side effects on source; NO
# setup_test/teardown_test; attach_test_client FIRST; $LIVEPICKER_SCRIPTS/$TEST_DRIVER_SESSION/
# assert_*/attach_test_client in scope; this file SOURCES NOTHING.)
#
# CRITICAL (research FINDING 1): the isolated server sources the user tmux.conf -> the root-table
# C-M-Tab/C-M-BTab swap-window bindings ARE present before activate (no fixture needed):
#   bind-key -T root C-M-Tab swap-window -t +1 \; select-window -t +1
#   bind-key -T root C-M-BTab swap-window -t -1 \; select-window -t -1
# CRITICAL (research FINDING 5): the root binding is NEVER mutated (INVARIANT B — activate only
# COPIES prefix+root into livepicker); the revert is free because key-table returns to root.
#   during: list-keys -T livepicker C-M-Tab -> run-shell "<abs>/input-handler.sh next-session"
#   after:   list-keys -T root C-M-Tab      -> swap-window -t +1 \; select-window -t +1  (byte-identical)
# CRITICAL (research FINDING 7): attach_test_client FIRST.
#
# `set -u` is INHERITED from helpers.sh (do NOT re-declare; mirror test_self.sh).
# shellcheck disable=SC2154,SC2016,SC2034,SC2086

# test_keyrepurpose_during_picker — PRD §15.20 bullet 1: while the picker is active, C-M-Tab /
# C-M-BTab are repurposed to session navigation in the livepicker table.
test_keyrepurpose_during_picker() {
	attach_test_client
	local next_bind prev_bind

	"$LIVEPICKER_SCRIPTS/livepicker.sh"                     # activate -> key-table = livepicker

	# list-keys -T <table> <key> filters to one key (one line + rc=0 when present; empty + rc=1
	# when absent). Capture with 2>/dev/null || true so an absent binding yields "" (assert fails).
	next_bind="$(tmux list-keys -T livepicker C-M-Tab 2>/dev/null || true)"
	prev_bind="$(tmux list-keys -T livepicker C-M-BTab 2>/dev/null || true)"

	# PRD §15.20 b1: during the picker, C-M-Tab/C-M-BTab move SESSIONS (FINDING 5).
	assert_contains "$next_bind" "next-session" \
		"C-M-Tab repurposed to next-session in the livepicker table"
	assert_contains "$prev_bind" "prev-session" \
		"C-M-BTab repurposed to prev-session in the livepicker table"
	assert_eq "$(tmux show-option -gqv key-table)" "livepicker" \
		"key-table is livepicker during the picker"

	# Cleanup: cancel leaves a clean mid-test state (teardown kills the server anyway).
	"$LIVEPICKER_SCRIPTS/input-handler.sh" cancel
}

# test_keyrepurpose_reverts_after_exit — PRD §15.20 bullet 2: after the picker closes, the same
# keys move WINDOWS again. The root-table binding is byte-identical before/after (never mutated).
test_keyrepurpose_reverts_after_exit() {
	attach_test_client
	local root_before root_after rootb_before rootb_after

	# Snapshot the ROOT-table bindings BEFORE activate (the revert target).
	root_before="$(tmux list-keys -T root C-M-Tab 2>/dev/null || true)"
	rootb_before="$(tmux list-keys -T root C-M-BTab 2>/dev/null || true)"

	"$LIVEPICKER_SCRIPTS/livepicker.sh"
	"$LIVEPICKER_SCRIPTS/input-handler.sh" cancel           # key-table reverts to root

	root_after="$(tmux list-keys -T root C-M-Tab 2>/dev/null || true)"
	rootb_after="$(tmux list-keys -T root C-M-BTab 2>/dev/null || true)"

	# PRD §15.20 b2: after exit, C-M-Tab/C-M-BTab move WINDOWS again. The root binding was NEVER
	# mutated (INVARIANT B); byte-identical before/after is the proof. The revert is free because
	# key-table returned to root (FINDING 5).
	assert_eq "$root_after" "$root_before" \
		"root C-M-Tab byte-identical before/after (never mutated; reverts for free)"
	assert_contains "$root_after" "swap-window" \
		"after exit, C-M-Tab moves windows again (swap-window)"
	assert_contains "$rootb_after" "swap-window" \
		"after exit, C-M-BTab moves windows again (swap-window)"
	assert_eq "$(tmux show-option -gqv key-table)" "root" \
		"key-table reverted to root after exit"
}
```

#### test_create.sh (Task 3)

```bash
#!/usr/bin/env bash
# tests/test_create.sh — tmux-livepicker PRD §15.22 Create-on-enter validation (P1.M7.T6.S1).
#
# SOURCED by run.sh (NEVER executed directly). Defines three test_* functions that drive the
# COMPLETE real plugin DIRECTLY against the socket-isolated server and assert PRD §15.22:
# session mode + create on + no match + Enter -> a new session is created and active; create off
# -> nothing created; window mode -> nothing created. Each test attaches a client, types a unique
# query, confirms, and signals pass/fail via fail/assert_*.
#
# CONTRACT: (same as test_restore.sh — SOURCED by run.sh; NO side effects on source; NO
# setup_test/teardown_test; attach_test_client FIRST; this file SOURCES NOTHING.)
#
# CRITICAL (research FINDING 6): type a UNIQUE query (not a substring of driver/alpha/beta) char-
# by-char via input-handler.sh type <c>. With an empty filtered list + session mode + create on,
# confirm creates the EXACT $query name (has-session "=$query" gate) and switches to it. create
# off OR window mode -> confirm takes the cancel path -> nothing created, client on driver. Set
# @livepicker-create / @livepicker-type via set-option -g BEFORE activate (activate reads opt_type
# to build the list; confirm reads opt_create/opt_type — correct when set before activate).
# CRITICAL (research FINDING 7): attach_test_client FIRST.
#
# `set -u` is INHERITED from helpers.sh (do NOT re-declare; mirror test_self.sh).
# shellcheck disable=SC2154,SC2016,SC2034,SC2086

# test_create_on_creates_and_activates — PRD §15.22 bullet 1: session mode + create on + no match
# + Enter -> the new session EXISTS and is ACTIVE.
test_create_on_creates_and_activates() {
	attach_test_client
	tmux set-option -g @livepicker-create on
	local q="zzzno" c

	"$LIVEPICKER_SCRIPTS/livepicker.sh"
	for c in z z z n o; do
		"$LIVEPICKER_SCRIPTS/input-handler.sh" type "$c"
	done
	"$LIVEPICKER_SCRIPTS/input-handler.sh" confirm

	# PRD §15.22 b1: the session was created (has-session exact-match =) AND is active.
	# has-session rc is the predicate; echo yes/no + compare (no raw rc under set -u/no -e).
	if tmux has-session -t "=$q" 2>/dev/null; then
		pass "create-on-enter created the session $q"
	else
		fail "create-on-enter created the session $q (has-session = $q failed — FINDING 6)"
	fi
	assert_eq "$(tmux display-message -p '#{session_name}')" "$q" \
		"the new session is active (client landed on it)"
	assert_eq "$(tmux show-option -gqv @livepicker-mode)" "" \
		"picker torn down after confirm"
}

# test_create_off_creates_nothing — PRD §15.22 bullet 2: @livepicker-create off + no match + Enter
# -> nothing is created (confirm takes the cancel path); the client stays on the driver.
test_create_off_creates_nothing() {
	attach_test_client
	tmux set-option -g @livepicker-create off
	local q="qwfx" c

	"$LIVEPICKER_SCRIPTS/livepicker.sh"
	for c in q w f x; do
		"$LIVEPICKER_SCRIPTS/input-handler.sh" type "$c"
	done
	"$LIVEPICKER_SCRIPTS/input-handler.sh" confirm

	# PRD §15.22 b2: nothing created.
	if tmux has-session -t "=$q" 2>/dev/null; then
		fail "create-off created nothing ($q must not exist — FINDING 6)"
	else
		pass "create-off created nothing ($q absent)"
	fi
	assert_eq "$(tmux display-message -p '#{session_name}')" "$TEST_DRIVER_SESSION" \
		"client stayed on the driver (cancel path)"
}

# test_window_mode_creates_nothing — PRD §15.22 bullet 3: window mode + no match + Enter ->
# nothing created (window mode has no create path; confirm takes the cancel path).
test_window_mode_creates_nothing() {
	attach_test_client
	tmux set-option -g @livepicker-type window
	local q="mplg" c

	"$LIVEPICKER_SCRIPTS/livepicker.sh"
	for c in m p l g; do
		"$LIVEPICKER_SCRIPTS/input-handler.sh" type "$c"
	done
	"$LIVEPICKER_SCRIPTS/input-handler.sh" confirm

	# PRD §15.22 b3: nothing created.
	if tmux has-session -t "=$q" 2>/dev/null; then
		fail "window mode created nothing ($q must not exist — FINDING 6)"
	else
		pass "window mode created nothing ($q absent)"
	fi
}
```

NOTE for the implementer:
- This is THREE NEW FILES under `tests/`. No edits to `setup_socket.sh`/`helpers.sh`/`run.sh`,
  no `scripts/` edits, no PRD/tasks edits, no edits to the parallel `test_pollution.sh`.
- Each file is SOURCED by run.sh — define `test_*` (+ any `lp_*` helpers) ONLY; NO side effects on
  source; NO `setup_test`/`teardown_test`; NO sourcing; NO self-test guard.
- `set -u` is inherited; do NOT re-declare it. Do NOT add `set -e`/`pipefail`.
- Signal failure ONLY via `fail`/`assert_*` (never `exit`).
- EVERY `test_*` calls `attach_test_client` (the driven scripts require a client — FINDING 7).
- The three most important correctness points are FINDING 2 (the "grep livepicker" false-fail →
  use the byte-identical options snapshot), FINDING 4 (the table is GONE → capture+empty-test),
  and FINDING 5 (key repurpose: root binding never mutated; revert is free).

### Integration Points

```yaml
NEW FILES (the ONLY files this task creates):
  - tests/test_restore.sh:       2 test_* (PRD §15.21 byte-exact restore). SOURCED by run.sh.
  - tests/test_keyrepurpose.sh:  2 test_* (PRD §15.20 key repurpose). SOURCED by run.sh.
  - tests/test_create.sh:        3 test_* (PRD §15.22 create-on-enter). SOURCED by run.sh.

CONSUMES (the INPUT — COMPLETE/READ-ONLY; do NOT edit):
  - tests/setup_socket.sh (T1.S1): setup_socket/teardown_socket + exports + baseline fixtures +
        attach_test_client/detach_test_client. run.sh's setup_test calls setup_socket per test.
  - tests/helpers.sh (T2.S1): fail/pass/assert_eq/assert_contains + setup_test/teardown_test +
        TEST_STATUS. In scope (run.sh sources helpers.sh).
  - tests/run.sh (T2.S1): the runner — sources the files, discovers test_*, runs each in a
        per-test fresh-socket cycle, exits 0/1. nullglob picks up the 3 new files automatically.
  - scripts/livepicker.sh + input-handler.sh + restore.sh (COMPLETE/IMMUTABLE): driven directly
        (activate / next-session / confirm / cancel).

CONSUMERS (downstream — NOT this task's responsibility):
  - `bash tests/run.sh` discovers + runs the 7 new test_* alongside test_self + T3.S1's functional
        + T4.S1's preview + T5.S1's pollution tests (each hermetic).

PROVIDES:
  - 2 PRD §15.21 restore test_* (the byte-exact restore proof).
  - 2 PRD §15.20 key-repurpose test_* (during/after the repurpose).
  - 3 PRD §15.22 create-on-enter test_* (the create matrix).

DATABASE / MIGRATIONS / ROUTES / CONFIG: none. No @livepicker-* writes on the REAL server (the
        isolated socket only). The only real-server contact is READ-ONLY (snapshot
        /usr/bin/tmux list-sessions around run.sh — a validation step).
```

## Validation Loop

### Level 1: Syntax & Style (Immediate Feedback)

```bash
# Run after creating each file — fix before proceeding.
for f in tests/test_restore.sh tests/test_keyrepurpose.sh tests/test_create.sh; do
  bash -n "$f"
  shellcheck "$f"
  # expect 0 findings (file-level `# shellcheck disable=SC2154,SC2016,SC2034,SC2086` is OK).
done

# Tabs-not-spaces sanity (shfmt NOT installed):
for f in tests/test_restore.sh tests/test_keyrepurpose.sh tests/test_create.sh; do
  grep -Pn '^    ' "$f" && echo "FAIL: 4-space indent in $f, use tabs" || echo "OK: tabs only ($f)"
done

# House style: set -u inherited (NOT re-declared); NO set -e/pipefail statement:
for f in tests/test_restore.sh tests/test_keyrepurpose.sh tests/test_create.sh; do
  grep -nE 'set -e|set -o pipefail|^set -u' "$f" \
    && echo "FAIL: disallowed set statement in $f (set -u inherited; -e/pipefail forbidden)" \
    || echo "OK: no set statement ($f)"
done

# attach_test_client IS used in every test_* (FINDING 7):
for f in tests/test_restore.sh tests/test_keyrepurpose.sh tests/test_create.sh; do
  grep -q 'attach_test_client' "$f" && echo "OK: attaches a client ($f)" \
    || echo "FAIL: no attach_test_client in $f (scripts need a client)"
done

# No side effects on source: a bare source must NOT start a server, call setup_test, print, or
# run a test. (run.sh owns the per-test cycle.)
for f in tests/test_restore.sh tests/test_keyrepurpose.sh tests/test_create.sh; do
  out="$( source "$f" 2>&1 )"
  [ -z "$out" ] && echo "OK: source is silent ($f)" || echo "FAIL: $f source printed: $out"
done

# The files SOURCE NOTHING (run.sh owns sourcing):
for f in tests/test_restore.sh tests/test_keyrepurpose.sh tests/test_create.sh; do
  grep -nE '^[[:space:]]*source |^[[:space:]]*\. ' "$f" \
    && echo "FAIL: $f sources something (it must not)" || echo "OK: no sourcing ($f)"
done

# Never exits / never calls setup_test/teardown_test directly:
for f in tests/test_restore.sh tests/test_keyrepurpose.sh tests/test_create.sh; do
  grep -nE '\bexit\b|setup_test|teardown_test' "$f" \
    && echo "FAIL: $f exits or touches the per-test cycle" || echo "OK: no exit / no setup_test ($f)"
done

# test_restore.sh does NOT use the literal `grep livepicker` (FALSE-FAILS — FINDING 2):
grep -nE 'grep.*livepicker' tests/test_restore.sh \
  && echo "FAIL: test_restore.sh uses 'grep livepicker' (FALSE-FAILS — use the byte-identical snapshot)" \
  || echo "OK: test_restore.sh avoids the grep-livepicker trap"

# SCOPE: only the three new files added (no harness/scripts/PRD/tasks edits):
git status --porcelain | grep -E '^.M (tests/setup_socket|tests/helpers|tests/run)\.sh|^.M scripts/|PRD\.md|tasks\.json|prd_snapshot' \
  && echo "FAIL: edited an off-limits file" || echo "OK: only the 3 new test files added"
git diff --stat -- tests/
```

### Level 2: The Suite (work-item §4 OUTPUT — runner aggregates)

```bash
# Run the full suite. Expect all 7 new tests PASS + test_self + T3.S1's five + T4.S1's four +
# T5.S1's three PASS, summary "N passed, 0 failed", exit 0.
bash tests/run.sh
echo "exit=$?"
# Expected (order may vary by sort): test_restore_cancel_options_hooks_exact,
#   test_restore_cancel_layout_exact, test_keyrepurpose_during_picker,
#   test_keyrepurpose_reverts_after_exit, test_create_on_creates_and_activates,
#   test_create_off_creates_nothing, test_window_mode_creates_nothing PASS (+ siblings). exit=0.
#
# If a test FAILS: run.sh prints "FAIL  <name>" + the ASSERT FAIL line on stderr.
#   - "global options byte-identical" fails -> a restore step did not round-trip an option
#     (status/status-format/key-table/renumber/hook) OR a runtime @livepicker-* key leaked
#     (clear_all_state regression). `diff <(before) <(after)` shows the delta.
#   - "livepicker key table unbound" fails -> unbind-key -a -T livepicker did not run (restore
#     STEP 6) OR the capture caught a stderr line (ensure 2>/dev/null || true).
#   - "C-M-Tab repurposed to next-session" fails -> activate did not bind the explicit nav keys
#     (T4.S1) OR the key changed (check opt_next_key default C-M-Tab on the isolated socket).
#   - "root C-M-Tab byte-identical" fails -> something mutated the root table (an INVARIANT B
#     regression — activate must only COPY, never mutate root).
#   - "create-on-enter created the session" fails -> confirm's create gate (new-session + has-session)
#     did not fire; check @livepicker-create is on + the query is unique + session mode.
#   - "create-off created nothing" fails -> confirm created despite create off (the gate regression).
```

### Level 3: Per-test targeted proof (drive the plugin inline — smoke-level)

```bash
# Prove each scenario on the isolated socket (run from repo root). Mirror the harness inline.
# shellcheck disable=SC1091
( source tests/setup_socket.sh; source tests/helpers.sh; source tests/test_restore.sh
  setup_test "lp-restore-$$"; attach_test_client
  ob="$(tmux show-options -g | sort)"; hb="$(tmux show-hooks -g | sort)"
  "$LIVEPICKER_SCRIPTS/livepicker.sh"
  "$LIVEPICKER_SCRIPTS/input-handler.sh" next-session
  "$LIVEPICKER_SCRIPTS/input-handler.sh" cancel
  oa="$(tmux show-options -g | sort)"; ha="$(tmux show-hooks -g | sort)"
  [ "$ob" = "$oa" ] && echo "OK: options byte-identical" || { echo "FAIL: options differ"; diff <(echo "$ob") <(echo "$oa") | head; }
  [ "$hb" = "$ha" ] && echo "OK: hooks byte-identical" || echo "FAIL: hooks differ"
  echo "table empty? [$([ -z "$(tmux list-keys -T livepicker 2>/dev/null || true)" ] && echo YES || echo NO)]"
  teardown_test )
# shellcheck disable=SC1091
( source tests/setup_socket.sh; source tests/helpers.sh; source tests/test_keyrepurpose.sh
  setup_test "lp-key-$$"; attach_test_client
  "$LIVEPICKER_SCRIPTS/livepicker.sh"
  echo "during [C-M-Tab]: $(tmux list-keys -T livepicker C-M-Tab 2>/dev/null)"
  "$LIVEPICKER_SCRIPTS/input-handler.sh" cancel
  echo "after  [C-M-Tab]: $(tmux list-keys -T root C-M-Tab 2>/dev/null)"
  teardown_test )
# shellcheck disable=SC1091
( source tests/setup_socket.sh; source tests/helpers.sh; source tests/test_create.sh
  setup_test "lp-create-$$"; attach_test_client
  tmux set-option -g @livepicker-create on
  "$LIVEPICKER_SCRIPTS/livepicker.sh"
  for c in n e w p r o j; do "$LIVEPICKER_SCRIPTS/input-handler.sh" type "$c"; done
  "$LIVEPICKER_SCRIPTS/input-handler.sh" confirm
  echo "has newproj? [$(tmux has-session -t '=newproj' 2>/dev/null && echo YES || echo NO)]"
  echo "active=[$(tmux display-message -p '#{session_name}')]"
  teardown_test )
# (Re-run with run.sh for the full assertion suite — this just proves reachability.)
```

### Level 4: Creative & Domain-Specific Validation (PRD §15 non-pollution + the corrected grep)

```bash
# PRD §15 invariant (the REAL server is untouched) — snapshot the user's REAL session list
# around a FULL run.sh invocation (many per-test setup/teardown cycles).
real_before="$(/usr/bin/tmux list-sessions -F '#{session_name}' | sort)"
bash tests/run.sh >/dev/null 2>&1
real_after="$(/usr/bin/tmux list-sessions -F '#{session_name}' | sort)"
[ "$real_before" = "$real_after" ] && echo "OK: real server byte-identical before/after" \
  || { echo "FAIL: real server changed"; diff <(echo "$real_before") <(echo "$real_after"); }

# Prove the corrected "no @livepicker-* runtime leak" claim directly (FINDING 2/3): after a clean
# cancel, the dormant §11 config REMAINS but NO runtime/orig keys leak. The byte-identical
# full-options snapshot is the proof; this inline check shows the residual @livepicker-* set.
# shellcheck disable=SC1091
( source tests/setup_socket.sh; source tests/helpers.sh
  setup_test "lp-grep-$$"; attach_test_client
  before="$(tmux show-options -g | grep '@livepicker' | sort)"
  "$LIVEPICKER_SCRIPTS/livepicker.sh"
  "$LIVEPICKER_SCRIPTS/input-handler.sh" next-session
  "$LIVEPICKER_SCRIPTS/input-handler.sh" cancel
  after="$(tmux show-options -g | grep '@livepicker' | sort)"
  echo "@livepicker-* BEFORE activate:"; echo "$before"
  echo "@livepicker-* AFTER cancel:";    echo "$after"
  [ "$before" = "$after" ] && echo "OK: @livepicker-* set byte-identical (dormant config survives; no runtime leak)" \
    || echo "FAIL: @livepicker-* set changed"
  teardown_test )
# Expected: both before AND after show ONLY @livepicker-fg + @livepicker-key (the dormant config).
# This is WHY the literal "grep livepicker empty" FALSE-FAILS and the byte-identical snapshot is used.
```

## Final Validation Checklist

### Technical Validation

- [ ] All 4 validation levels completed successfully.
- [ ] `bash tests/run.sh` exits 0; summary `N passed, 0 failed`.
- [ ] `bash -n` clean + `shellcheck` clean on all three files (file-level `disable` for
      SC2154/SC2016/SC2034/SC2086 at most).
- [ ] Tabs only; `set -u` inherited (NOT re-declared); no `set -e`/`pipefail`.
- [ ] `/usr/bin/tmux list-sessions` byte-identical before/after a full `run.sh`.

### Feature Validation

- [ ] `test_restore_cancel_options_hooks_exact` PASS: show-options + show-hooks byte-identical
      after activate→nav→cancel; livepicker table unbound; @livepicker-mode disarmed.
- [ ] `test_restore_cancel_layout_exact` PASS: window_layout byte-exact; client back on the
      original session + window.
- [ ] `test_keyrepurpose_during_picker` PASS: C-M-Tab→next-session + C-M-BTab→prev-session in
      the livepicker table; key-table==livepicker.
- [ ] `test_keyrepurpose_reverts_after_exit` PASS: root C-M-Tab/C-M-BTab byte-identical
      before/after (still swap-window); key-table==root.
- [ ] `test_create_on_creates_and_activates` PASS: the query session exists + is active.
- [ ] `test_create_off_creates_nothing` PASS: nothing created; client on driver.
- [ ] `test_window_mode_creates_nothing` PASS: nothing created.
- [ ] Each `test_*` calls `attach_test_client` FIRST (FINDING 7).
- [ ] `test_restore.sh` does NOT use the literal `grep livepicker` (FINDING 2; uses the byte-
      identical options snapshot instead).

### Code Quality Validation

- [ ] Follows the sibling test-file conventions (test_functional.sh / test_preview.sh /
      test_pollution.sh): header CONTRACT comment, dynamic reads, inline-`case`/predicate for
      has-session negatives, tabs.
- [ ] File placement matches the desired tree (the three new files under `tests/`).
- [ ] Anti-patterns avoided (check against the Anti-Patterns section).
- [ ] No sourcing; no `setup_test`/`teardown_test` calls; no `exit` in test bodies.
- [ ] Each file is SELF-CONTAINED (does not rely on test_functional.sh's `lp_runtime_cleared`).

### Documentation & Deployment

- [ ] Code is self-documenting with clear variable/function names + WHY comments tracing each
      assertion to a research FINDING.
- [ ] DOCS: Mode A — none (test infra; no end-user surface).
- [ ] No new environment variables (all inputs come from the harness exports).

---

## Anti-Patterns to Avoid

- ❌ Don't use the literal `show-options -g | grep livepicker` to assert "no @livepicker-* remain"
  (FINDING 2 — it FALSE-FAILS: the dormant §11 config sourced from tmux.conf survives cancel).
  Use the byte-identical full-options snapshot (FINDING 3), which proves exact restore AND no
  runtime leak in one assert.
- ❌ Don't assert on the raw rc of `list-keys -T livepicker` after cancel (FINDING 4 — it's
  non-deterministic across capturing styles under `set -u`/no-`-e`). Capture the output with
  `2>/dev/null || true` and empty-test it.
- ❌ Don't expect the root-table C-M-Tab/C-M-BTab binding to CHANGE during/after the picker
  (FINDING 5 / INVARIANT B — it is never mutated; the "revert" is free because key-table returns
  to root). Assert it is byte-identical before/after, not that it was "restored".
- ❌ Don't skip `attach_test_client` (the driven scripts require a client — FINDING 7; this is NOT
  T4.S1, whose `preview.sh` is client-independent).
- ❌ Don't use a create-on-enter query that is a substring of driver/alpha/beta (use a unique token;
  an accidental match would make the filtered list non-empty -> confirm lands instead of creating).
- ❌ Don't set `@livepicker-create`/`@livepicker-type` AFTER activate (activate reads opt_type to
  build the list; set them before activate — FINDING 6).
- ❌ Don't create new patterns when existing ones work (mirror test_functional.sh's attach +
  display-message idiom, test_preview.sh's header + helper style, test_functional.sh's
  test_escape_restores capture-orig-before-activate pattern — generalized to the full sorted snapshot).
- ❌ Don't ignore failing tests — fix the root cause (a restore/key/create regression in the plugin
  would surface here).
- ❌ Don't `exit` from a test body, don't call `setup_test`/`teardown_test`, don't source
  anything (run.sh owns the per-test cycle and the sourcing).
- ❌ Don't edit `setup_socket.sh`/`helpers.sh`/`run.sh`, any `scripts/*`, `test_pollution.sh`
  (parallel sibling), PRD.md, tasks.json, prd_snapshot.md, or .gitignore (FORBIDDEN — this task
  adds exactly THREE files).

---

## Confidence Score

**9/10** for one-pass implementation success.

Rationale: the research file (`research/restore_keyrepurpose_create_findings.md`) is unusually
complete — 9 empirically-verified findings (run live on isolated sockets on tmux 3.6b on
2026-07-06), with every scenario (`/tmp/probe_t6.sh` + `/tmp/probe_t6b.sh`) confirmed PASS: the
byte-identical options/hooks/layout restore, the gone-after-cancel livepicker table, the key-
repurpose during/after bindings, and the full create-on-enter matrix (on/off/window). Every
non-obvious trap is documented with its verified fix — FINDING 2 (the "grep livepicker" false-fail
→ the byte-identical snapshot), FINDING 4 (the table is GONE → capture+empty-test), FINDING 5
(root binding never mutated). The implementation is three sourced files mirroring three existing
sibling test files (`test_functional.sh`, `test_preview.sh`, `test_pollution.sh`) whose exact style
and helpers are read in full. The residual 1 point is the standard hermetic-test risk (pty attach
timing in `attach_test_client`, mitigated by the harness's `sleep 0.5` and already exercised green
by T3.S1's functional tests) — not a logic gap.
