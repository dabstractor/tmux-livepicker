# PRP — P1.M7.T1.S1: `tests/setup_socket.sh` — PATH-wrapper tmux shim

---

## Goal

**Feature Goal**: **INVENT** the socket-isolation test harness for tmux-livepicker
(P1.M7, PRD §15). No sibling plugin ships one (system_context §7; sibling_plugins
§9 — verified: zero matches for `socket`/`TMUX_BIN`/`tmux -L`/PATH-wrapper across
session-history, sessionx, resurrect; the PRD §15 phrase "as in the session-
history test" describes a pattern that **does not exist**). The plugin scripts call
**bare `tmux`** (e.g. `utils.sh`'s `tmux show-option`, `restore.sh`'s
`tmux switch-client`). A **PATH shim** — an executable `tmux` wrapper placed FIRST
in `PATH` that rewrites every bare call to `"$REAL_TMUX" -L "$TEST_SOCKET" "$@"` —
lets those scripts hit an **isolated tmux server with ZERO code changes**. The
real user server (the live `/tmp/tmux-$UID/default` socket with its 15 sessions)
is never touched. This file IS the mocking infrastructure for the whole P1.M7
test suite: every later test (P1.M7.T2–T6) `source`s it and gets an isolated
`tmux`.

**Deliverable** (single NEW file `tests/setup_socket.sh`):
1. A **sourced bash library** (sourcing has NO side effects — defines functions
   only) providing:
   - `setup_socket [socket_name]` — create a temp dir; write+`chmod +x` the `tmux`
     shim (`exec "$REAL_TMUX" -L "$TEST_SOCKET" "$@"`, real binary by ABSOLUTE
     path → no recursion); `export PATH="<tmpdir>:$PATH"`; `export TEST_SOCKET`;
     start the isolated server (`tmux new-session -d -s driver`); spawn a small
     documented fixture set (a few sessions/windows/panes).
   - `teardown_socket` — `tmux kill-server` (via the shim, bare `tmux`) **+**
     `rm -rf "$TMUX_SOCK_DIR"` **+** `rm -f "$TMUX_SOCKET_PATH"` (idempotent).
   - (optional, socket-bound convenience for downstream tests)
     `attach_test_client [session]` / `detach_test_client`.
   - Exported env: `TEST_SOCKET`, `TMUX_SOCK_DIR`, `TMUX_SOCKET_PATH`,
     `REAL_TMUX`, `LIVEPICKER_ROOT`, `LIVEPICKER_SCRIPTS`.
2. A **built-in self-test**: when the file is **executed directly**
   (`bash tests/setup_socket.sh`) — NOT sourced — it runs `setup_socket_self_test`
   which exercises setup → the 4 isolation/cleanup assertion groups → teardown
   and exits 0/1. (Contract §5: "Self-test: run setup, assert `tmux list-sessions`
   shows only the test sessions, assert the real server via /usr/bin/tmux is
   unchanged, run teardown, assert the socket is gone.")

**Success Definition**:
- `bash -n` + `shellcheck` pass on `tests/setup_socket.sh` (0 findings beyond a
  file-level `disable=SC1091,SC2154` if needed; tabs only; `set -u` only).
- `source tests/setup_socket.sh` defines the functions and exports NOTHING / starts
  NO server (no side effects on source — FINDING 9/12).
- `bash tests/setup_socket.sh` prints a sequence of `ok` assertions and exits 0
  (the self-test), proving: (a) the shim intercepts bare `tmux`; (b) the isolated
  server sees ONLY the fixtures; (c) `/usr/bin/tmux` (absolute) does NOT see them
  and the real server's session list is byte-identical before/after; (d) teardown
  kills the server (`has-session` rc≠0) AND removes the socket file.
- `git diff --stat` shows ONLY `tests/setup_socket.sh` added (no `scripts/` edits,
  no PRD/tasks/prd_snapshot edits — FORBIDDEN).
- **The real user server is provably untouched** (the core PRD §15 invariant):
  after a full setup→teardown cycle, `/usr/bin/tmux list-sessions` is unchanged.

## User Persona (if applicable)

**Target User**: the test author (the P1.M7.T2–T6 implementers) and, transitively,
the contributor running the suite. The harness itself has no end-user surface
(DOCS: Mode A — none; it is test infra).

**Use Case**: a P1.M7.T3 functional test does `source tests/setup_socket.sh;
setup_socket; attach_test_client; …drive the real scripts/livepicker.sh against
the isolated `tmux`…; teardown_socket`. It never has to think about sockets,
PATH, or the user's real server again.

**User Journey** (T1.S1 scope — the shim):
1. The test file begins with `source "$(dirname "$0")/setup_socket.sh"`.
2. It calls `setup_socket`. A temp dir is created; a `tmux` wrapper is written
   there and prepended to `PATH`; `TEST_SOCKET`/`TMUX_SOCK_DIR`/`TMUX_SOCKET_PATH`
   are exported; an isolated server starts on `tmux -L "$TEST_SOCKET"`; a few
   fixture sessions/windows/panes spawn.
3. From now on ANY bare `tmux …` call (whether from the test OR from the plugin's
   real scripts sourced/execed later) transparently hits the **isolated** server.
   `/usr/bin/tmux …` (absolute) always reaches the REAL server unchanged.
4. The test asserts things, then calls `teardown_socket`: the isolated server is
   killed, the shim dir + the socket file are removed, PATH is left with a
   dangling (harmless) entry. The real server is exactly as it was.

**Pain Points Addressed**:
- (a) **No isolation existed.** Without this, any test driving the real scripts
  would mutate the user's live 15-session server. T1.S1 makes tests hermetic.
- (b) **The plugin calls bare `tmux`.** Refactoring every script to take a
  `$TMUX_BIN` indirection would be invasive and risk production regressions. The
  PATH shim is the zero-code-change interception layer.
- (c) **"As in the session-history test" was a dead reference.** T1.S1 replaces
  an aspirational PRD phrase with a real, self-validating harness.

## Why

- **PRD §15 (Validation)** is the controlling spec: "isolated scripted checks
  (separate tmux socket via a `tmux` PATH wrapper … so the real server is
  untouched)." T1.S1 builds the wrapper every §15 check depends on. Without it,
  P1.M7.T3–T6 cannot exist.
- **system_context §7 + sibling_plugins §9** (the work-item §1 RESEARCH NOTE) are
  explicit: the harness must be **invented** (no sibling template); resurrect's
  Vagrant+expect+real-`kill-server` pattern is explicitly the WRONG model (too
  heavy, not isolated — it nukes the user's server). T1.S1 uses the recommended
  PATH-wrapper shape (system_context §7 prints it verbatim).
- **Scope cohesion.** T1.S1 is the FOUNDATION of module P1.M7 (Validation). T2.S1
  (`helpers.sh` + `run.sh`) consumes `setup_socket.sh` (it `source`s it; its
  resurrect-style `fail`/`test_*` machinery + higher-level fixtures build ON TOP
  of the isolated `tmux` this file provides). T3–T6 (`test_functional.sh`,
  `test_preview.sh`, `test_pollution.sh`, `test_restore.sh`, `test_keyrepurpose.sh`,
  `test_create.sh`) each `source` this file and drive the REAL completed scripts
  (livepicker.sh/preview.sh/input-handler.sh/restore.sh — all COMPLETE per the
  parallel-execution contract with P1.M6.T4.S1) against the isolated server.
  The shared contract is the exported `TEST_SOCKET` + the PATH shim + the
  `setup_socket`/`teardown_socket` pair. T1.S1 owns ONLY socket isolation; it does
  NOT own assertion helpers (T2.S1) or test bodies (T3–T6).

## What

**CREATE** the single file `tests/setup_socket.sh`. No other file is touched
(the `scripts/` are COMPLETE and UNCHANGED; PRD/tasks/prd_snapshot are READ-ONLY).
The file has two modes:

1. **Sourced** (`source tests/setup_socket.sh`) — defines functions, exports
   nothing, starts nothing (CONTRACT: no side effects on source, mirror
   `utils.sh`).
2. **Executed** (`bash tests/setup_socket.sh`) — runs `setup_socket_self_test`
   and exits 0/1.

### Success Criteria

- [ ] `tests/setup_socket.sh` passes `bash -n` + `shellcheck` (file-level
      `disable` for SC1091/SC2154 at most); tabs only; `set -u` only (NO `-e`,
      NO `-o pipefail`).
- [ ] The `tmux` shim body is exactly `exec "$REAL_TMUX" -L "$TEST_SOCKET" "$@"`
      (one line), written with an **unquoted** heredoc so `$TEST_SOCKET` + the
      detected/`/usr/bin/tmux` `REAL_TMUX` bake in, while `"\$@"` passes the
      caller's argv through quoted (FINDING 5). `REAL_TMUX` is resolved by
      ABSOLUTE path **before** PATH is modified (FINDING 6) so the shim never
      recurses into itself.
- [ ] `setup_socket` exports `TEST_SOCKET` (default `livepicker-test-$$`,
      `$$`-unique — FINDING 11), `TMUX_SOCK_DIR` (the temp dir), `TMUX_SOCKET_PATH`
      (`${TMPDIR:-/tmp}/tmux-$(id -u)/$TEST_SOCKET` — FINDING 3), `REAL_TMUX`,
      and convenience `LIVEPICKER_ROOT`/`LIVEPICKER_SCRIPTS`; prepends
      `"$TMUX_SOCK_DIR"` to `PATH`; starts the isolated server
      (`tmux new-session -d -s driver -x 120 -y 40`); spawns the documented
      baseline fixtures (FINDING 8).
- [ ] `teardown_socket` performs **three** steps (FINDING 2): `tmux kill-server`
      (bare → shim → isolated socket) + `rm -rf "$TMUX_SOCK_DIR"` +
      `rm -f "$TMUX_SOCKET_PATH"`; is **idempotent** (safe when setup didn't run
      or already tore down — guard every step with `[ -n ]` / `2>/dev/null || true`);
      and `detach_test_client`s any attached client before `kill-server`.
- [ ] The **self-test** (run on direct execution) asserts all four groups
      (FINDING 4): (1) isolated `tmux list-sessions` == exactly the fixtures;
      (2) `/usr/bin/tmux list-sessions` lacks the fixtures AND is byte-identical
      before/after the cycle; (3) `"$TMUX_SOCKET_PATH" !=
      "${SOCKET_BASE}/default"`; (4) after teardown, `tmux has-session -t '=driver'`
      returns NONZERO (server dead) AND `[ ! -e "$TMUX_SOCKET_PATH" ]` (file gone).
- [ ] `source tests/setup_socket.sh` starts NO server and exports NOTHING (no side
      effects — verify `tmux list-sessions` socket count unchanged after a bare
      source in the self-test's preamble, or assert via a function-not-run guard).
- [ ] `git diff --stat` shows ONLY `tests/setup_socket.sh` added.

## All Needed Context

### Context Completeness Check

_Pass_: A developer who has never seen this repo can implement T1.S1 from
(a) the ready-to-paste `setup_socket.sh` in "Implementation Patterns & Key
Details"; (b) the 12 findings in `research/setup_socket_findings.md` — most
critically **FINDING 2** (`kill-server` leaves the socket FILE — teardown needs
the 3rd `rm -f` step and the self-test must assert server-DEAD not file-gone),
**FINDING 5** (unquoted heredoc bakes `$TEST_SOCKET`, escapes `\$@`), **FINDING 6**
(resolve `REAL_TMUX` by absolute path BEFORE PATH prepend — no recursion), and
**FINDING 9** (sourced = define-only; executed = self-test); and (c) the two PROBE
EVIDENCE blocks that verified every assertion live. The INPUT dependencies are
NONE (the work-item is greenfield test infra; `scripts/` are COMPLETE but this
task does not edit them — it only needs them to exist for the optional
`LIVEPICKER_SCRIPTS` export and for downstream tests).

### Documentation & References

```yaml
# MUST READ — the authoritative spec for WHY this is invented (no sibling template).
- docfile: plan/001_fd5d622d3939/architecture/system_context.md
  why: §7 prints the recommended PATH-wrapper shape verbatim (the contract's
        template); §3 INARIANT A (browsing never fires client-session-changed — the
        reason socket isolation is SUFFICIENT: tests can drive the real scripts
        without polluting the real @session-history); §9 shell style (set -u ONLY,
        no -e/pipefail; tabs; local for all function locals; CURRENT_DIR idiom;
        quote everything); §10 version floor (3.0; target 3.6b).
  section: "§7 Test harness reality", "§3 INVARIANT A", "§9 Shell style".
  critical: §7 is the work-item's RESEARCH NOTE made permanent. The "as in the
        session-history test" phrase is aspirational — do NOT look for a template
        in session-history; it does not exist.

# MUST READ — the sibling scout (confirms no harness exists + what to borrow).
- docfile: plan/001_fd5d622d3939/architecture/sibling_plugins_and_env.md
  why: §9 verifies zero matches for socket/TMUX_BIN/tmux -L/PATH-wrapper across
        siblings; prints the proposed wrapper shape; lists the resurrect
        tests/helpers/helpers.sh idioms to BORROW (fail/test_* discovery) and the
        ones to AVOID (teardown_helper does a REAL tmux kill-server — the
        anti-pattern). §4 the CURRENT_DIR + get_tmux_option idioms to mirror.
  section: "§9 Test harness", "§4 SCRIPT_DIR computation & helper sourcing".

# MUST READ — the empirical ground-truth for THIS task (12 findings + PROBE EVIDENCE).
- docfile: plan/001_fd5d622d3939/P1M7T1S1/research/setup_socket_findings.md
  why: FINDING 1 (shim intercepts bare tmux; isolation total); FINDING 2
        (kill-server leaves the socket FILE — teardown needs rm -f; self-test
        asserts server-dead); FINDING 3 (socket path = ${TMPDIR:-/tmp}/tmux-$UID/
        $SOCK); FINDING 4 (the 4 self-test assertion groups); FINDING 5 (unquoted
        heredoc: bake $TEST_SOCKET, escape \$@); FINDING 6 (resolve REAL_TMUX by
        absolute path BEFORE PATH prepend); FINDING 7 (script/util-linux attached
        client for downstream tests); FINDING 8 (baseline fixtures); FINDING 9
        (sourced vs executed idiom); FINDING 10 (borrow resurrect fail/test_*
        style ONLY); FINDING 11 ($$-unique socket names); FINDING 12 (house style).
  critical: Read BEFORE writing. FINDING 2 + FINDING 5 + FINDING 6 are the three
        non-obvious traps that would otherwise cause a false-failing self-test or
        an infinite-recursion shim.

# MUST READ — the house style template (sourced library with NO side effects).
- file: scripts/utils.sh
  why: the canonical "sourced library" file in this repo. Copy its CONTRACT line
        ("sourcing this file has NO side effects"), its shebang+set -u header
        (NOT -e/pipefail), its `local`-everywhere + tabs style, and its
        `CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"` idiom.
        setup_socket.sh is the TESTS-layer analogue: a sourced library.
  pattern: "# CONTRACT: sourcing this file has NO side effects …" header;
           set -u; local for all function locals; tabs.
  gotcha: utils.sh is COMPLETE/IMMUTABLE — do NOT edit it. Mirror its STYLE only.

# MUST READ (cross-reference) — the throwaway socket-shim mocks that PRE-FIGURE
#   this task (they prove the pattern end-to-end on an isolated socket).
- docfile: plan/001_fd5d622d3939/P1M6T4S1/research/cancel_mock.sh
- docfile: plan/001_fd5d622d3939/P1M6T3S1/research/confirm_mock.sh
  why: both build a self-cleaning isolated-`-L`-socket harness (cleanup trap:
        kill jobs + tmux -L kill-server + rm -rf) that drives the REAL scripts.
        They use a `T(){ tmux -L "$SOCK" "$@"; }` FUNCTION wrapper (calling `T`
        directly); T1.S1's contribution is the PATH SHIM so the PLUGIN's bare
        `tmux` calls are intercepted too (the mocks only proved the scripts work
        when called via `T`; the plugin's own internal `tmux …` calls need the
        shim). Borrow their `script -qec "tmux -L $SOCK attach" /dev/null &`
        attached-client pattern (FINDING 7) and their `ok`/`bad`/`assert`
        helper shape (FINDING 10).
  critical: the mocks are THROWAWAY (P1.M6 owned them; P1.M7 owns the real
        harness). Do NOT ship them. T1.S1 is the productionized, sourced,
        PATH-shim version of the pattern they proved.

# MUST READ — the PRD sections selected for this work item.
- docfile: PRD.md
  why: §15 Validation (the controlling spec — "separate tmux socket via a tmux
        PATH wrapper, as in the session-history test, so the real server is
        untouched"; lists the functional/pollution/preview/restore/key-repurpose/
        create-on-enter check CLUSTERS T3–T6 will implement ON TOP of this
        harness); §16 Implementation risks (tmux 3.0 floor; the `#()` renderer
        refresh-client -S need; the link-window edge cases the preview tests will
        exercise — all of which need an attached client on the isolated socket).
  section: "§15 Validation", "§16 Implementation risks and notes".

# MUST READ (parallel-execution contract) — what EXISTS when this task runs.
- docfile: plan/001_fd5d622d3939/P1M6T4S1/PRP.md
  why: P1.M6.T4.S1 (cancel) is the LAST input-handler seam; completing it
        finishes P1.M6 and unblocks P1.M7. Its PRP defines the COMPLETE
        scripts/input-handler.sh (+ livepicker.sh/preview.sh/restore.sh) that
        T3–T6 will drive against the isolated socket this harness provides.
        Treat those scripts as COMPLETE/IMMUTABLE — this task does not edit them.
```

### Current Codebase tree

```bash
tmux-livepicker/
  PRD.md                         # READ-ONLY (FORBIDDEN to edit).
  plugin.tmux                    # COMPLETE. Unchanged.
  plan/001_fd5d622d3939/{architecture/*.md, tasks.json, prd_snapshot.md, prd_index.txt}
  plan/001_fd5d622d3939/P1M6T4S1/{PRP.md, research/cancel_findings.md,
                                 research/cancel_mock.sh}          # parallel sibling (cancel) — assume COMPLETE
  plan/001_fd5d622d3939/P1M7T1S1/{PRP.md, research/setup_socket_findings.md}  # THIS
  scripts/
    options.sh utils.sh state.sh filter.sh renderer.sh preview.sh
    livepicker.sh restore.sh input-handler.sh    # ALL COMPLETE (P1.M1–M6). IMMUTABLE. This task does NOT edit them.
  .gitignore
  # NOTE: NO tests/ dir yet — THIS task creates it (tests/setup_socket.sh is the first file).
  # The throwaway *_mock.sh harnesses (P1.M6.T3/T4 research/) are NOT shipped; they
  # pre-figured the isolated-socket pattern this task productionizes.
```

### Desired Codebase tree with files to be added and responsibility of file

```bash
tmux-livepicker/
  tests/
    setup_socket.sh   # NEW (this task). Sourced bash library providing:
                      #   setup_socket [socket_name]  — temp dir + PATH shim (exec "$REAL_TMUX"
                      #       -L "$TEST_SOCKET" "$@") + export TEST_SOCKET/TMUX_SOCK_DIR/
                      #       TMUX_SOCKET_PATH/REAL_TMUX/LIVEPICKER_* + isolated server + fixtures.
                      #   teardown_socket             — kill-server + rm -rf shim dir + rm -f socket
                      #       file (idempotent).
                      #   attach_test_client/detach_test_client  (OPTIONAL, socket-bound, for T3-T6).
                      #   setup_socket_self_test                 (runs ONLY on direct execution).
                      # CONTRACT: sourcing has NO side effects. Executing runs the self-test (exit 0/1).
                      # T2.S1 (helpers.sh + run.sh) will source THIS; T3-T6 source THIS + drive the real scripts.
```

### Known Gotchas of our codebase & Library Quirks

```bash
# CRITICAL (research FINDING 2 — kill-server leaves the socket FILE): `tmux -L
#   "$SOCK" kill-server` kills the SERVER but does NOT unlink the socket file at
#   ${TMPDIR:-/tmp}/tmux-$UID/$SOCK. Verified live: after kill-server,
#   has-session rc=1 + list-sessions rc=1 (server DEAD) but [ -e socket ] is STILL
#   true (a dead/inert unix socket file). Evidence: /tmp/tmux-$UID/ already holds
#   ~24 orphaned lp-* sockets from the throwaway mocks. The contract's teardown
#   ("kill-server + rm -rf the temp dir") removes the SHIM dir but NOT the socket
#   file (it lives OUTSIDE the temp dir). RESOLUTION: teardown_socket does THREE
#   steps — tmux kill-server + rm -rf "$TMUX_SOCK_DIR" + rm -f "$TMUX_SOCKET_PATH"
#   (the rm -f is a justified SUPERSET of the contract; it predates this finding).
#   The self-test's "socket is gone" asserts server-DEADNESS (has-session rc!=0)
#   AND file-gone ([ ! -e socket ] — holds only because teardown rm -f'd it).

# CRITICAL (research FINDING 5 — heredoc quoting): the shim is written with an
#   UNQUOTED heredoc (<<EOF, NOT <<'EOF') so $TEST_SOCKET + $REAL_TMUX expand at
#   WRITE time (baked into the shim), while "\$@" is escaped to pass the caller's
#   argv through at runtime. A quoted heredoc would bake nothing -> the shim would
#   reference an unset $TEST_SOCKET -> empty -L -> wrong socket / set -u crash.
#   Use: cat > "$TMUX_SOCK_DIR/tmux" <<EOF  ...  exec "$REAL_TMUX" -L "$TEST_SOCKET" "\$@"  ...  EOF

# CRITICAL (research FINDING 6 — absolute path, NO recursion): the shim MUST call
#   the real tmux by ABSOLUTE PATH ($REAL_TMUX, default /usr/bin/tmux), NEVER bare
#   `tmux`. Bare `tmux` inside the shim would re-resolve via PATH -> find the shim
#   -> recurse forever. Resolve REAL_TMUX BEFORE prepending the shim dir to PATH
#   (so command -v tmux returns the REAL binary, not the shim). Paranoia: if the
#   detected REAL_TMUX already lives under TMUX_SOCK_DIR (re-source case), force
#   it to /usr/bin/tmux.

# CRITICAL (research FINDING 9 — sourced vs executed): `source tests/setup_socket.sh`
#   must define functions with NO side effects (start NO server, export NOTHING).
#   The self-test runs ONLY under direct execution: `if [ "${BASH_SOURCE[0]}" =
#   "${0}" ]; then setup_socket_self_test; fi`. Mirror utils.sh's CONTRACT line.

# CRITICAL (research FINDING 7 — downstream tests need an attached client): the
#   plugin's switch-client / display-message -p / refresh-client -S all REQUIRE a
#   client. The contract's setup LOGIC lists only "shim+server+fixtures" (no
#   client) — so the client helper is OPTIONAL. Provide attach_test_client/
#   detach_test_client (socket-bound: they need TEST_SOCKET + the shim) as a
#   convenience for T3-T6, marked optional + NOT exercised by setup_socket's own
#   self-test + NOT duplicating T2.S1's helpers.sh (which owns fail/test_*).
#   teardown_socket MUST detach any attached client BEFORE kill-server (an
#   attached client can delay server exit).

# GOTCHA (research FINDING 3 — socket path): tmux -L <name> puts the socket at
#   ${TMPDIR:-/tmp}/tmux-$(id -u)/<name>. The real server's socket is the same
#   dir + "default" (visible as $TMUX's first field when inside tmux). Compute
#   SOCKET_BASE="${TMPDIR:-/tmp}/tmux-$(id -u)"; TMUX_SOCKET_PATH="$SOCKET_BASE/
#   $TEST_SOCKET". $(id -u) is portable; $UID is bash-only (both work here).

# GOTCHA (research FINDING 11 — $$ uniqueness): TEST_SOCKET must be globally
#   unique so parallel test runs don't collide on the same -L socket. Use
#   "livepicker-test-$$" ($$ = sourcing shell PID; NOT subshell-local — stable).
#   NEVER a fixed name. Allow an optional override: setup_socket [socket_name].

# STYLE (research FINDING 12 / system_context §9): shebang #!/usr/bin/env bash;
#   set -u ONLY (NOT -e, NOT -o pipefail — show-option/has-session legitimately
#   return nonzero); local for ALL function locals; TABS for indent; quote
#   everything; CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)".

# GOTCHA: do NOT edit ANY scripts/ file, PRD.md, tasks.json, prd_snapshot.md, or
#   .gitignore (FORBIDDEN). This task ADDS exactly one file: tests/setup_socket.sh.
```

## Implementation Blueprint

### Data models and structure

No data model in the ORM/pydantic sense. The "model" is the **exported environment
contract** every downstream test relies on:

```bash
# Exported by setup_socket (read by every sourced test + every spawned subprocess):
TEST_SOCKET          # the -L socket name ("livepicker-test-$$", or the arg). UNIQUE per run.
TMUX_SOCK_DIR        # the temp dir holding the `tmux` shim (rm -rf'd on teardown).
TMUX_SOCKET_PATH     # the full path to the socket file (${TMPDIR:-/tmp}/tmux-$UID/$TEST_SOCKET).
REAL_TMUX            # absolute path to the REAL tmux (/usr/bin/tmux) baked into the shim.
PATH                 # "$TMUX_SOCK_DIR:$PATH"  (shim wins; /usr/bin/tmux still reachable by absolute path).
LIVEPICKER_ROOT      # repo root (…/tmux-livepicker) — convenience for tests.
LIVEPICKER_SCRIPTS   # "$LIVEPICKER_ROOT/scripts" — convenience so tests drive the real scripts.
# Baseline fixture names (documented; tests may add their own via bare `tmux new-session`):
TEST_DRIVER_SESSION  # "driver" (attached-client home + picker-activate origin + preview-link target).
TEST_FIXTURE_SESSIONS# e.g. "alpha beta" (populate the picker list; ≥2 choices for filter/nav tests).
```

### Implementation Tasks (ordered by dependencies)

```yaml
Task 1: CREATE tests/setup_socket.sh — header + exports + setup_socket
  - CREATE: tests/setup_socket.sh (NEW; the tests/ dir is created by this write).
  - HEADER: #!/usr/bin/env bash ; set -u ; a CONTRACT comment ("sourcing has NO
        side effects; executing runs setup_socket_self_test"); CURRENT_DIR idiom.
  - IMPLEMENT: setup_socket() — (a) resolve REAL_TMUX by absolute path BEFORE any
        PATH change (FINDING 6; default /usr/bin/tmux; paranoia guard); (b) honor
        optional $1 socket name else TEST_SOCKET="livepicker-test-$$" (FINDING 11);
        (c) TMUX_SOCK_DIR=$(mktemp -d); (d) write the shim via UNQUOTED heredoc
        (FINDING 5): exec "$REAL_TMUX" -L "$TEST_SOCKET" "$@"; chmod +x; (e) compute
        TMUX_SOCKET_PATH (FINDING 3); (f) export all the vars above + prepend
        "$TMUX_SOCK_DIR" to PATH; (g) start the isolated server (tmux new-session
        -d -s driver -x 120 -y 40); (h) spawn the baseline fixtures (FINDING 8).
  - FOLLOW pattern: scripts/utils.sh (sourced-library header, set -u, local, tabs,
        CURRENT_DIR idiom, no-side-effects CONTRACT line).
  - NAMING: setup_socket function; snake_case; TABS; local for ALL locals.
  - DO NOT: use bare `tmux` inside the shim body (recursion — FINDING 6); use a
        quoted heredoc (FINDING 5); add set -e/pipefail; edit any scripts/ file.

Task 2: ADD teardown_socket (+ optional attach_test_client/detach_test_client)
  - IMPLEMENT: teardown_socket() — idempotent. detach any attached client FIRST
        (FINDING 7); then THREE steps (FINDING 2): `tmux kill-server` (bare → shim
        → isolated socket, guarded `2>/dev/null || true`) + `rm -rf "$TMUX_SOCK_DIR"`
        (guard `[ -n ]`) + `rm -f "$TMUX_SOCKET_PATH"` (guard). Unset the exports
        is OPTIONAL (tests re-source fresh); do NOT clobber the user's real PATH
        beyond the prepend (leave the dangling entry — harmless; or strip it).
  - IMPLEMENT (OPTIONAL): attach_test_client [session] — spawn
        `script -qec "tmux attach -t ${1:-driver}" /dev/null >/dev/null 2>&1 &`,
        record the job/PID, sleep ~0.5. detach_test_client — kill the recorded
        PID, `wait`. Mark both clearly OPTIONAL (socket-bound convenience for
        T3-T6; not exercised by the self-test; not duplicating T2.S1's helpers.sh).
  - NAMING: teardown_socket, attach_test_client, detach_test_client; local; tabs.

Task 3: ADD setup_socket_self_test + the sourced-vs-executed guard
  - IMPLEMENT: setup_socket_self_test() — a tiny inline assert helper (ok/bad/
        assert — FINDING 10; do NOT depend on T2.S1's helpers.sh). Run setup_socket;
        assert the 4 groups (FINDING 4): (1) `tmux list-sessions -F '#{session_name}'`
        == exactly the fixtures (sorted compare); (2) `/usr/bin/tmux list-sessions`
        lacks every fixture name AND (snapshot before setup / after teardown)
        byte-identical; (3) `"$TMUX_SOCKET_PATH" != "$SOCKET_BASE/default"`; (4)
        run teardown_socket, then assert `tmux has-session -t '=driver'` rc!=0
        (server dead) AND `[ ! -e "$TMUX_SOCKET_PATH" ]` (file gone). Print
        PASS/FAIL; exit 0 on all-ok else 1.
  - GUARD: at file bottom, `if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
        setup_socket_self_test; fi` (FINDING 9) — so sourcing is side-effect-free.
  - NAMING: setup_socket_self_test; local; tabs.

Task 4: VALIDATE (Level 1 syntax/lint + Level 2 self-test)
  - RUN: bash -n tests/setup_socket.sh ; shellcheck tests/setup_socket.sh ;
        bash tests/setup_socket.sh  (expect "ALL ASSERTIONS PASSED", exit 0).
        ALSO: `source tests/setup_socket.sh` in a subshell and assert no server
        started (no side effects on source — FINDING 9).
```

### Implementation Patterns & Key Details

#### The shim (Task 1, step d) — UNQUOTED heredoc (FINDING 5/6)

```bash
	# Resolve the REAL tmux by ABSOLUTE path BEFORE prepending the shim dir to PATH,
	# so command -v returns the real binary (not a prior shim). Default /usr/bin/tmux
	# (verified: command -v tmux == /usr/bin/tmux on this machine). Paranoia: if the
	# detected path already lives under our shim dir (re-source), force the default.
	REAL_TMUX="${REAL_TMUX:-$(command -v tmux || echo /usr/bin/tmux)}"
	case "$REAL_TMUX" in
		"$TMUX_SOCK_DIR"/*) REAL_TMUX="/usr/bin/tmux" ;;
	esac
	# Write the shim. UNQUOTED heredoc (<<EOF) so $TEST_SOCKET + $REAL_TMUX expand
	# at WRITE time (baked into the shim); "\$@" is escaped so the caller's argv
	# passes through quoted at runtime. `exec` replaces the shim process (no fork).
	# The ABSOLUTE $REAL_TMUX means PATH is never consulted inside the shim -> NO
	# RECURSION (a bare `tmux` here would re-find the shim forever — FINDING 6).
	cat > "$TMUX_SOCK_DIR/tmux" <<EOF
#!/usr/bin/env bash
exec "$REAL_TMUX" -L "$TEST_SOCKET" "\$@"
EOF
	chmod +x "$TMUX_SOCK_DIR/tmux"
```

#### teardown_socket (Task 2) — THREE steps, idempotent (FINDING 2/7)

```bash
teardown_socket() {
	# Detach any client we attached FIRST (an attached client can delay kill-server).
	detach_test_client 2>/dev/null || true
	# kill-server kills the SERVER but LEAVES the socket file (FINDING 2). The bare
	# `tmux` resolves to our shim -> hits ONLY the isolated -L socket. The real
	# /usr/bin/tmux default server is never touched.
	[ -n "${TEST_SOCKET:-}" ] && tmux kill-server 2>/dev/null || true
	# Remove the shim dir ...
	[ -n "${TMUX_SOCK_DIR:-}" ] && [ -d "$TMUX_SOCK_DIR" ] && rm -rf "$TMUX_SOCK_DIR" 2>/dev/null || true
	# ... AND the orphaned socket file (lives OUTSIDE the shim dir, at
	# ${TMPDIR:-/tmp}/tmux-$UID/$TEST_SOCKET — FINDING 2/3). This is the justified
	# SUPERSET of the contract's "rm -rf the temp dir" (kill-server leaves the file).
	[ -n "${TMUX_SOCKET_PATH:-}" ] && rm -f "$TMUX_SOCKET_PATH" 2>/dev/null || true
}
```

#### attach_test_client / detach_test_client (Task 2, OPTIONAL — FINDING 7)

```bash
# OPTIONAL, socket-bound convenience for downstream tests (P1.M7.T3-T6) that need
# an attached client (switch-client / display-message -p / refresh-client -S all
# REQUIRE one). NOT exercised by setup_socket_self_test; does NOT duplicate T2.S1's
# helpers.sh (which owns fail/test_* discovery + higher-level fixtures).
TEST_CLIENT_PID=""
attach_test_client() {
	local sess="${1:-$TEST_DRIVER_SESSION}"
	# `script` (util-linux) gives a pty; attach to the isolated server via the shim.
	script -qec "tmux attach -t '$sess'" /dev/null >/dev/null 2>&1 &
	TEST_CLIENT_PID=$!
	sleep 0.5   # let the attach settle so list-clients/display-message see it
}
detach_test_client() {
	[ -n "$TEST_CLIENT_PID" ] && kill "$TEST_CLIENT_PID" 2>/dev/null || true
	[ -n "$TEST_CLIENT_PID" ] && wait "$TEST_CLIENT_PID" 2>/dev/null || true
	TEST_CLIENT_PID=""
}
```

#### The sourced-vs-executed guard (Task 3 — FINDING 9)

```bash
# Sourcing this file defines functions ONLY (no server started, nothing exported).
# Executing it directly runs the self-test. Mirror utils.sh's no-side-effects CONTRACT.
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
	setup_socket_self_test
fi
```

NOTE for the implementer:
- This is a SINGLE NEW FILE (greenfield test infra). No `scripts/` edits.
- The shim body is exactly ONE line: `exec "$REAL_TMUX" -L "$TEST_SOCKET" "$@"`.
  Do NOT add argument mangling, logging, or a fallback — keep it transparent.
- Resolve `REAL_TMUX` and write the shim BEFORE prepending to PATH (FINDING 6).
- `teardown_socket` is idempotent (callable when nothing's set up) — guard every
  step. The three steps are kill-server + rm -rf shim dir + rm -f socket file.
- The self-test must snapshot the REAL server (`/usr/bin/tmux list-sessions`)
  BEFORE setup and AFTER teardown and assert byte-identical — that is the gold-
  standard proof the harness never touched the user's server (PRD §15 invariant).

### Integration Points

```yaml
NEW FILE (the ONLY file this task creates):
  - tests/setup_socket.sh: sourced library (setup_socket/teardown_socket +
        optional attach/detach_test_client) + executed-direct self-test. No other
        file is created or edited.

CONSUMERS (downstream — NOT this task's responsibility, but the contract):
  - P1.M7.T2.S1 tests/helpers.sh + tests/run.sh: source setup_socket.sh; build the
        resurrect-style fail/test_* discovery + higher-level fixtures ON TOP of the
        isolated `tmux`. run.sh sources setup_socket.sh ONCE before the suite.
  - P1.M7.T3-T6 tests/test_*.sh: each does `source setup_socket.sh; setup_socket;
        (attach_test_client;) …drive the real scripts/…; teardown_socket`.

PROVIDES (the contract downstream tests rely on):
  - bare `tmux` -> isolated -L socket (transparent to the plugin's scripts).
  - TEST_SOCKET / TMUX_SOCK_DIR / TMUX_SOCKET_PATH / REAL_TMUX / LIVEPICKER_* exports.
  - setup_socket / teardown_socket (idempotent) + optional attach/detach_test_client.

DOES NOT PROVIDE (T2.S1's job): fail/test_* helpers, run.sh, per-cluster fixtures.

DATABASE / MIGRATIONS / ROUTES / CONFIG: none. No @livepicker-* options, no tmux
        mutations on the REAL server. The only real-server contact is READ-ONLY
        (the self-test snapshots /usr/bin/tmux list-sessions to prove non-pollution).
```

## Validation Loop

### Level 1: Syntax & Style (Immediate Feedback)

```bash
# Run after creating the file — fix before proceeding.
bash -n tests/setup_socket.sh
shellcheck tests/setup_socket.sh
#   expect 0 findings (a file-level `# shellcheck disable=SC1091,SC2154` is OK if
#   shellcheck flags the dynamic source / TEST_* use).

# Tabs-not-spaces sanity (shfmt NOT installed):
grep -Pn '^    ' tests/setup_socket.sh && echo "FAIL: 4-space indent, use tabs" || echo "OK: tabs only"

# House style (set -u only; NO -e / NO pipefail DECLARED):
grep -n 'set -e\|set -o pipefail' tests/setup_socket.sh \
  && echo "FAIL: set -e/pipefail present" || echo "OK: set -u only"

# The shim body is exactly ONE exec line with the ABSOLUTE real tmux (no recursion):
grep -n '^exec .* -L "\$TEST_SOCKET"' tests/setup_socket.sh   # inside the heredoc — the baked shim
# Verify the shim uses an ABSOLUTE path / REAL_TMUX, never bare `tmux`, in its body.

# Sourcing has NO side effects (FINDING 9): a bare source must NOT start a server.
before=$(tmux -L __side_effect_probe list-sessions 2>/dev/null | wc -l)   # expect 0 (no such socket)
# shellcheck disable=SC1091
( source tests/setup_socket.sh )   # in a subshell; must define fns, start nothing
after=$(tmux -L __side_effect_probe list-sessions 2>/dev/null | wc -l)
[ "$before" = "$after" ] && echo "OK: source is side-effect-free" || echo "FAIL: source started something"

# The sourced-vs-executed guard is present:
grep -n 'BASH_SOURCE\[0\].*=.*"\${0}"' tests/setup_socket.sh && echo "OK: guard present" || echo "FAIL: no guard"

# SCOPE: only tests/setup_socket.sh added (no scripts/ or PRD/tasks edits):
git status --porcelain | grep -E '^.M scripts/|PRD.md|tasks.json|prd_snapshot' \
  && echo "FAIL: edited an off-limits file" || echo "OK: only tests/setup_socket.sh"
```

### Level 2: The Built-in Self-Test (run on direct execution — FINDING 4/9)

```bash
# Run the file directly — it runs setup_socket_self_test (the contract §5 scenario).
bash tests/setup_socket.sh
# Expected: a sequence of `ok [n] …` lines ending in "ALL ASSERTIONS PASSED"; exit 0.
#   The self-test MUST exercise:
#     (1) isolated `tmux list-sessions` == exactly the fixtures (sorted compare);
#     (2) `/usr/bin/tmux list-sessions` lacks every fixture name AND is byte-identical
#         before setup vs after teardown (the gold-standard non-pollution proof);
#     (3) "$TMUX_SOCKET_PATH" != "${SOCKET_BASE}/default" (socket differs);
#     (4) after teardown: `tmux has-session -t '=driver'` rc!=0 (server dead) AND
#         [ ! -e "$TMUX_SOCKET_PATH" ] (file gone — only because teardown rm -f'd it).
# If (4) fails on the file-gone check, teardown is missing the `rm -f "$TMUX_SOCKET_PATH"`
#   step (FINDING 2 — kill-server leaves the file). If (4) fails on server-dead,
#   teardown didn't run kill-server against the isolated socket.
```

### Level 3: Integration (a sourced test drives the real scripts — smoke proof)

```bash
# Proof the shim intercepts the PLUGIN's own bare `tmux` calls (not just the test's).
# This is the property T3-T6 depend on. Run from the repo root:
cat > /tmp/lp_shim_smoke.sh <<'SMOKE'
#!/usr/bin/env bash
set -u
ROOT="$(cd "$(dirname "$1")" && pwd)"
# shellcheck disable=SC1091
source "$ROOT/tests/setup_socket.sh"
setup_socket
# The plugin's utils.sh calls bare `tmux show-option`. With the shim on PATH, that
# hits the ISOLATED socket — set an option and read it back via the shim only:
# (utils.sh is a sourced lib; source it then call its helper.)
# shellcheck disable=SC1091
source "$ROOT/scripts/utils.sh"
tmux_set_opt "@livepicker-smoke" "isolated-ok"
shim_val="$(tmux show-option -gqv @livepicker-smoke)"          # via shim -> isolated
real_val="$(/usr/bin/tmux show-option -gqv @livepicker-smoke 2>/dev/null)"  # via real -> UNSET
echo "shim_val=$shim_val  real_val=[$real_val]"
[ "$shim_val" = "isolated-ok" ] && [ -z "$real_val" ] && echo "SMOKE PASSED: plugin's bare tmux hit the isolated socket" || echo "SMOKE FAILED"
teardown_socket
SMOKE
bash /tmp/lp_shim_smoke.sh "$(pwd)"
rm -f /tmp/lp_shim_smoke.sh
# Expected: SMOKE PASSED — the option set via the plugin's bare-`tmux` helper is
#   visible on the ISOLATED socket and ABSENT from the real server. This proves
#   the shim intercepts the plugin's own internal calls (zero code changes).
```

### Level 4: Creative & Domain-Specific Validation (PRD §15 non-pollution + robustness)

```bash
# PRD §15 invariant (the real server is untouched) — the self-test's group (2) is
# the deterministic form. For a manual gold-standard check, snapshot the user's
# real session list around a full cycle:
real_before="$(/usr/bin/tmux list-sessions -F '#{session_name}' | sort)"
# shellcheck disable=SC1091
( source tests/setup_socket.sh; setup_socket >/dev/null; attach_test_client;
  /usr/bin/tmux -V; tmux new-session -d -s throwaway; detach_test_client;
  teardown_socket >/dev/null )
real_after="$(/usr/bin/tmux list-sessions -F '#{session_name}' | sort)"
[ "$real_before" = "$real_after" ] && echo "OK: real server byte-identical before/after" || { echo "FAIL: real server changed"; diff <(echo "$real_before") <(echo "$real_after"); }

# Robustness: teardown is idempotent — calling it twice / without setup must not error.
( source tests/setup_socket.sh; teardown_socket; teardown_socket; echo "idempotent teardown OK" )

# Robustness: parallel runs don't collide (FINDING 11) — two concurrent setups get
# distinct sockets:
for i in 1 2; do
  ( source tests/setup_socket.sh; setup_socket; echo "run$i socket=$TEST_SOCKET"; tmux list-sessions -F '#{session_name}'; teardown_socket ) &
done; wait

# Optional client helper (FINDING 7): attach + assert list-clients sees it + detach.
( source tests/setup_socket.sh; setup_socket; attach_test_client;
  [ "$(tmux list-clients -t "$TEST_DRIVER_SESSION" -F '#{client_session}' | head -1)" = "$TEST_DRIVER_SESSION" ] && echo "client attached OK";
  detach_test_client; teardown_socket )
```

## Final Validation Checklist

### Technical Validation

- [ ] Level 1 passes: `bash -n tests/setup_socket.sh` + `shellcheck` (0 new findings);
      tabs only; `set -u` only.
- [ ] Level 2 passes: `bash tests/setup_socket.sh` → "ALL ASSERTIONS PASSED", exit 0.
- [ ] Level 3 passes: the smoke script proves the plugin's own bare-`tmux` helper
      (`tmux_set_opt`) writes to the ISOLATED socket, not the real one.
- [ ] Level 4 passes: real server byte-identical before/after a full cycle; teardown
      idempotent; parallel runs get distinct sockets.
- [ ] `git status --porcelain` shows ONLY `tests/setup_socket.sh` added (?? tests/).

### Feature Validation

- [ ] **Isolation:** bare `tmux` (via PATH) → isolated `-L` socket; `/usr/bin/tmux`
      (absolute) → real server, unchanged (self-test groups 1+2).
- [ ] **Shim correctness:** `exec "$REAL_TMUX" -L "$TEST_SOCKET" "$@"` (one line,
      absolute path, unquoted heredoc — no recursion; FINDING 5/6).
- [ ] **Cleanup:** teardown kills the server (`has-session` rc≠0) AND removes the
      shim dir AND the orphaned socket file (FINDING 2; the 3-step teardown).
- [ ] **No side effects on source:** `source tests/setup_socket.sh` starts no server
      and exports nothing (FINDING 9).
- [ ] **Non-pollution (PRD §15):** the real user server's session list is byte-
      identical before/after a full setup→teardown cycle (self-test group 2).

### Code Quality Validation

- [ ] Mirrors `scripts/utils.sh`'s sourced-library style (CONTRACT line, set -u,
      local, tabs, CURRENT_DIR idiom, no side effects on source).
- [ ] File placement matches the desired tree (`tests/setup_socket.sh`); creates
      the `tests/` dir.
- [ ] `REAL_TMUX` resolved by absolute path before PATH prepend (no recursion);
      `/usr/bin/tmux` documented as the verified default + fallback.
- [ ] Optional helpers (`attach_test_client`/`detach_test_client`) clearly marked
      optional, socket-bound, not duplicating T2.S1's `helpers.sh`.
- [ ] Anti-patterns avoided (check against Anti-Patterns section).

### Documentation & Deployment

- [ ] Code is self-documenting (inline comments cite the findings: FINDING 2/5/6/7/9).
- [ ] DOCS: Mode A — none (test infra). No README/CHANGELOG changes for this task
      (P1.M8 owns README/CHANGELOG). A one-line `tests/README.md` is OPTIONAL.
- [ ] No new environment variables beyond the documented TEST_*/TMUX_*/REAL_TMUX/
      LIVEPICKER_* exports (all test-local; never written to the real server).

---

## Anti-Patterns to Avoid

- ❌ **Don't use bare `tmux` inside the shim body.** It would re-resolve via PATH
  → find the shim → **infinite recursion**. Use the absolute `$REAL_TMUX`
  (FINDING 6).
- ❌ **Don't use a quoted heredoc (`<<'EOF'`) for the shim.** It would bake
  nothing → the shim references an unset `$TEST_SOCKET` → empty `-L` → wrong
  socket / `set -u` crash. Use the **unquoted** `<<EOF` so `$TEST_SOCKET` +
  `$REAL_TMUX` bake in, with `"\$@"` escaped (FINDING 5).
- ❌ **Don't stop teardown at `kill-server` + `rm -rf` the temp dir.** `kill-server`
  leaves the socket FILE at `${TMPDIR:-/tmp}/tmux-$UID/$SOCK` (FINDING 2). teardown
  MUST also `rm -f "$TMUX_SOCKET_PATH"`. And the self-test's "socket is gone" must
  assert server-DEADNESS (`has-session` rc≠0), not just file-gone.
- ❌ **Don't start a server / export anything on `source`.** Sourcing defines
  functions only (no side effects — FINDING 9 / utils.sh CONTRACT). The self-test
  runs only under direct execution.
- ❌ **Don't add `set -e` / `set -o pipefail`.** House style is `set -u` only
  (system_context §9); `has-session`/`show-option`/`kill-server` legitimately
  return nonzero.
- ❌ **Don't borrow resurrect's `teardown_helper`.** It does a REAL `tmux
  kill-server` + `rm -rf ~/.tmux/` — the OPPOSITE of socket-isolated; it would
  nuke the user's real server. Borrow only the `fail`/`test_*` assertion STYLE
  (FINDING 10), and even that belongs to T2.S1's `helpers.sh`.
- ❌ **Don't hardcode a fixed socket name.** Use `livepicker-test-$$` (`$$`-unique;
  FINDING 11) so parallel runs don't collide.
- ❌ **Don't edit `scripts/`, `PRD.md`, `tasks.json`, `prd_snapshot.md`, or
  `.gitignore`.** This task ADDS exactly one file: `tests/setup_socket.sh`.
- ❌ **Don't duplicate T2.S1's job.** setup_socket owns socket isolation ONLY.
  Assertion helpers (`fail`/`test_*` discovery) + `run.sh` + per-cluster fixtures
  are T2.S1's. The optional `attach_test_client` is socket-bound (needs
  `TEST_SOCKET`), so it belongs HERE — but mark it optional and don't build
  higher-level test machinery.

---

## Confidence Score

**9/10** for one-pass implementation success.

This is greenfield test infrastructure (one NEW file, zero edits to existing
code), and the entire mechanism is **empirically verified** by two live probes
(research §PROBE EVIDENCE): the shim intercepts bare `tmux`; isolation is total
(`/usr/bin/tmux` never sees the fixtures); the socket path is known; `kill-server`
leaves the file (so the 3-step teardown is specified); the `script` attached-
client works. The ready-to-paste snippets (shim heredoc, 3-step teardown,
sourced-vs-executed guard, self-test) leave no ambiguity, and the three non-
obvious traps (FINDING 2 kill-server-leaves-file; FINDING 5 heredoc quoting;
FINDING 6 absolute-path-no-recursion) are each called out with the exact fix. The
self-test is a deterministic, self-contained validation gate (`bash
tests/setup_socket.sh` → exit 0/1) that proves the PRD §15 non-pollution invariant
byte-for-byte. The only residual risk (-1) is the `script`/pty edge for the
optional `attach_test_client` (util-linux version quirks across machines) and the
judgment call to include the optional client helper — but it is clearly marked
optional and not load-bearing for the core contract (`setup_socket`/`teardown_socket`
+ the self-test stand alone). The parallel-execution dependency on P1.M6.T4.S1 is
minimal: this task does not touch `scripts/`, so it composes cleanly regardless of
when cancel lands.
