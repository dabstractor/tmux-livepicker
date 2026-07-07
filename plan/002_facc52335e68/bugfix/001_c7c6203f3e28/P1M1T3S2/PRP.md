# PRP — Bugfix P1.M1.T3.S2: Add sanitized-name create test

> **Context**: Issue 3 from the rev-002 QA pass
> (`plan/002_facc52335e68/bugfix/001_c7c6203f3e28/architecture/issue3_findings.md`,
> Major; reproduced in PRD §h2.2/h3.2). The shipped create tests
> (`tests/test_create.sh`) use PURE-ALPHANUMERIC queries (`zzzno`, `qwfx`, `mplg`) that
> tmux NEVER sanitizes — so the sanitization code path is **completely untested**
> (`issue3_findings.md` §"Test Coverage Gap"). This PRP adds ONE committed regression
> test that types a DOTTED query (`my.proj`) and asserts the client lands on the
> SANITIZED session (`my_proj`), closing the gap and locking in the S1 fix.
>
> **Test-only**: no production code changes. Appends one `test_*` function to
> `tests/test_create.sh`. The S1 fix (`-P -F '#{session_name}'` capture in
> `scripts/input-handler.sh`) is already applied; this test is its regression net.

---

## Goal

**Feature Goal**: A committed regression test (`test_create_sanitized_name_lands_on_session`)
in `tests/test_create.sh` that drives the REAL plugin with a query containing `.` (a PRD §6
typeable char), confirms on a no-match list, and asserts (1) the session is created under
the SANITIZED name `my_proj`, (2) no session exists under the raw name `my.proj`, (3) the
client LANDED on `my_proj` (not stranded on the driver — the load-bearing assertion), (4)
exactly one session was created (count = before + 1, no orphan of any name), and (5) the
picker was torn down. This makes the Issue 3 regression (orphan + stranding) visible to CI.

**Deliverable**: ONE new function appended to `tests/test_create.sh` —
`test_create_sanitized_name_lands_on_session`. No other files change.

**Success Definition**:
- The new test PASSES against the FIXED `input-handler.sh` (S1 applied): `my_proj` created,
  client on `my_proj`, count = before+1, `my.proj` absent, mode cleared. (PROVEN: research
  `sanitized_name_create_test_findings.md` FINDING 1 — pass=5 fail=0.)
- The new test FAILS against the buggy behavior (S1's gate reverted to
  `has-session -t "=$query"` + land on `$query`): assertion A3 (client landed on sanitized
  name) fires — `got[driver] want[my_proj]`. (PROVEN: FINDING 2 — pass=4 fail=1.)
- The full `tests/run.sh` suite stays green (the new test is additive; `run.sh`
  auto-discovers it via `compgen -A function | grep '^test_'`).
- `bash -n` + `shellcheck` clean on the edited file (0 NEW findings).

## User Persona (if applicable)

**Target User**: The maintainer (regression safety net). Not end-facing — it is a test that
locks in the S1 fix.

**Use Case**: A future change to `input-handler.sh`'s create gate regresses Issue 3 (e.g.
restores the `has-session -t "=$query"` check, or passes `$query` instead of `$created` to
`_confirm_land_on_session`). This test fails in CI before the regression ships.

**Pain Points Addressed**: The shipped suite has ZERO coverage for "create a session from a
query that tmux sanitizes" — exactly the path Issue 3 corrupts. Without this test, the S1
fix is unguarded and can regress undetected (the findings doc §"Test Coverage Gap" and the
PRD §h2.4 "Areas needing more attention" both call this out: *"Create path with sanitized
names — add cases that type `.` and assert no orphan session is left and the user lands
somewhere sensible (Issue 3)"*).

---

## Why

- **Closes the documented test gap.** `issue3_findings.md` §"Test Coverage Gap" states
  verbatim: *"All three existing create tests use pure-alphanumeric queries … that are NEVER
  sanitized. The sanitization code path is completely untested."* This test exercises it.
- **Guards the S1 fix (P1.M1.T3.S1), which lands in parallel.** S1 replaces the buggy
  `has-session -t "=$query"` gate with a `-P -F '#{session_name}'` capture and lands on the
  captured `$created`. This test is its regression net — it passes today (S1 applied) and
  fails the moment the gate regresses (FINDING 2).
- **One function, zero production risk.** Pure test addition; `run.sh` auto-discovers
  `test_*` via `compgen -A function | grep '^test_'`, so no registration/wiring is needed.

## What

Append `test_create_sanitized_name_lands_on_session` to `tests/test_create.sh`. It:
1. Attaches a client FIRST (`attach_test_client` — required for `display-message -p` /
   `switch-client`), then sets `@livepicker-create on` BEFORE activate (the sibling's order).
2. Snapshots the session count BEFORE (`before_n`) so the "no orphan" invariant is
   baseline-agnostic (does not hard-code 3).
3. Activates the picker (`livepicker.sh`), types `m y . p r o j` char-by-char via
   `input-handler.sh type`, and confirms.
4. Asserts the 5 contract invariants (sanitized created / raw absent / landed on sanitized /
   count == before+1 / mode cleared).

The pattern mirrors `test_create_on_creates_and_activates` EXACTLY (same setup order, same
helpers, same char-by-char type loop, same `pass`/`fail`/`assert_eq` style); the ONLY
deliberate difference is the dotted query. `@livepicker-zoxide-mode` defaults to `"off"`
(`scripts/options.sh:29`), so the zoxide branch never fires and NO extra option pin is
needed (the sibling relies on the same default).

### Success Criteria

- [ ] `test_create_sanitized_name_lands_on_session` is appended to `tests/test_create.sh`.
- [ ] It attaches the client BEFORE setting `@livepicker-create on` / activating.
- [ ] It types a DOTTED query (`m y . p r o j`) char-by-char via `input-handler.sh type`.
- [ ] It asserts `has-session -t "=my_proj"` succeeds (sanitized session created).
- [ ] It asserts `has-session -t "=my.proj"` fails (no session under the raw name).
- [ ] It asserts `display-message -p '#{session_name}'` == `my_proj` (client landed).
- [ ] It asserts the session count == `before_n + 1` (snapshot dynamically; no hard-coded 3).
- [ ] It asserts `@livepicker-mode` == "" (picker torn down).
- [ ] `bash tests/run.sh` is green; the new test auto-discovered and PASSes.

## All Needed Context

### Context Completeness Check

_Pass_: The implementer needs (a) the verbatim function to append (in Implementation
Patterns), (b) the file's header CONTRACT (sourced by run.sh; no setup_test/teardown_test;
`set -u` inherited; signal failure ONLY via `fail`/`assert_*`; never `exit`), (c) the
empirical proof it passes on the fix and fails on the bug, and (d) the sibling test to
mirror. All are supplied below.

### Documentation & References

```yaml
# MUST READ — the empirical ground-truth (PROVES the test passes on the fix + catches the bug)
- docfile: plan/002_facc52335e68/bugfix/001_c7c6203f3e28/P1M1T3S2/research/sanitized_name_create_test_findings.md
  why: PROVES the test end-to-end on the isolated harness. FINDING 1 (pass=5 fail=0 on the
       FIXED input-handler.sh); FINDING 2 (pass=4 fail=1 on the BUG simulation — the test is
       load-bearing, NOT vacuous); FINDING 3 (A3 "landed on sanitized name" is THE
       load-bearing assertion; A4 "count == before+1" is invariant across fix/bug — keeps it
       as belt-and-braces); FINDING 4 (follow the sibling EXACTLY; zoxide default is off, no
       pin needed); FINDING 5 (exact values: my_proj; snapshot before_n dynamically; wc -l
       needs tr -d '[:space:]'); FINDING 6 (no conflict with parallel S1 — different file).
  critical: Read BEFORE editing. Assert on the LITERAL "my_proj" (do NOT compute it from the
            typed query — that would replicate tmux's sanitization, the anti-pattern S1
            avoided). The orphan IS the +1 session; A3 is what flips on a regression.

# MUST READ — the file being modified (APPEND one function)
- file: tests/test_create.sh
  why: The header CONTRACT block (sourced by run.sh; no side effects on source; `set -u`
        inherited via helpers.sh; signal failure ONLY via fail/assert_* — NEVER exit; NO
        setup_test/teardown_test — run.sh owns the per-test socket cycle). The THREE tests to
        MIRROR — especially test_create_on_creates_and_activates (the EXACT template:
        attach_test_client → set-option -g @livepicker-create on → livepicker.sh → char-by-char
        input-handler.sh type → confirm → pass/fail/assert_eq). Its `local q="zzzno" c` +
        `for c in z z z n o` type loop is the idiom to copy (swap the chars for m y . p r o j).
  pattern: pass/fail/assert_eq from tests/helpers.sh; has-session rc as the predicate
           (`if tmux has-session -t "=$q" 2>/dev/null; then pass …; else fail …; fi`);
           display-message -p '#{session_name}' + show-option -gqv @livepicker-mode for the
           active-session / teardown assertions.
  gotcha: the file is SOURCED (defines functions ONLY; the shebang is documentation). Do NOT
          add setup_test/teardown_test. The new function must be named exactly
          `test_create_sanitized_name_lands_on_session` (underscore-separated) to be
          discovered by run.sh's `compgen -A function | grep '^test_' | sort`.

# MUST READ — the bug this test guards (root cause + the gap it fills)
- docfile: plan/002_facc52335e68/bugfix/001_c7c6203f3e28/architecture/issue3_findings.md
  why: Documents the root cause (new-session sanitizes '.'/'.' -> '_' rc=0; the OLD gate
       has-session -t "=$query" checked the unsanitized name and always failed -> orphan +
       stranding), the empirical sanitization table (my.proj -> my_proj), and §"Test Coverage
       Gap" — the EXACT missing test this PRP adds (type a dotted query; assert sanitized
       created + no orphan + user lands).
  section: "Empirical Sanitization Rules", "Test Coverage Gap"

# MUST READ — the fix under test (the S1 PRP — treat as a CONTRACT)
- docfile: plan/002_facc52335e68/bugfix/001_c7c6203f3e28/P1M1T3S1/PRP.md
  why: Defines what input-handler.sh's create block does post-fix: captures the actual name
       via `new-session -P -F '#{session_name}'`, gates on `[ -n "$created" ]`, and lands on
       `$created` (not `$query`). This test validates exactly that behavior. Read the "Goal"
       + "What" + "Known Gotchas" sections. The S1 PRP's L2 smoke is the throwaway PROTOTYPE
       of this committed test.
  critical: S1 is the code fix (already applied); THIS PRP (S2) is its test. Do NOT modify
            scripts/input-handler.sh here.

# Reference — the assertion helpers + the per-test socket cycle contract
- file: tests/helpers.sh
  why: The COMPLETE public assertion API: fail/pass/assert_eq/assert_contains + setup_test/
       teardown_test (thin delegates to setup_socket). assert_eq(a,b,msg) is POSIX equality
       (handles the wc -l count string once whitespace-normalized). No assert_not_contains —
       the "raw name absent" check is written inline as `if tmux has-session …; then fail;
       else pass; fi` (the same form test_create_off_creates_nothing uses).
  section: fail(), pass(), assert_eq()

# Reference — the harness (attach_test_client, baseline fixtures, TEST_DRIVER_SESSION)
- file: tests/setup_socket.sh
  why: attach_test_client [session] spawns a pty client on the isolated socket (REQUIRED for
       display-message -p / switch-client — FINDING 7). setup_socket seeds the baseline
       fixtures: driver + alpha + beta (= 3 sessions; do NOT hard-code — snapshot before_n).
       TEST_DRIVER_SESSION="driver" is where the client starts (and where it is STRANDED on
       the bug).
  section: attach_test_client(), setup_socket() (baseline fixtures)

# Reference — PRD §6 (the confirm/create contract) + §11 (the create/zoxide options)
- docfile: PRD.md
  why: §6 Confirm ("If creation fails (invalid name), cancel instead") + §6 Filtering (the
        typeable set includes '.') define the contract this test exercises. §11
        @livepicker-create / @livepicker-zoxide-mode are the options gating the branch.
  section: "§6 Behaviors → Confirm", "§6 Filtering", "§11 Configuration options"
```

### Current Codebase tree (run `ls scripts/ tests/` in the repo root)

```bash
tmux-livepicker/
  scripts/
    input-handler.sh  # UNCHANGED (S1 already applied: -P -F '#{session_name}' capture +
                      #   _confirm_land_on_session "$created"). This PRP does NOT touch it.
  tests/
    run.sh            # UNCHANGED (auto-discovers test_* — the new function is picked up free).
    setup_socket.sh   # UNCHANGED (baseline fixtures: driver + alpha + beta; attach_test_client).
    helpers.sh        # UNCHANGED (fail/pass/assert_eq + setup_test/teardown_test).
    test_create.sh    # MODIFY: APPEND test_create_sanitized_name_lands_on_session as the LAST
                      #   function (after test_window_mode_creates_nothing).
```

### Desired Codebase tree with files to be added and responsibility of file

```bash
tests/test_create.sh   # +test_create_sanitized_name_lands_on_session (appended LAST):
                        #   type a dotted query (my.proj) + confirm -> assert the sanitized
                        #   session (my_proj) is created AND the client lands on it; no orphan.
                        #   Regression net for Issue 3 / P1.M1.T3.S1.
```

### Known Gotchas of our codebase & Library Quirks

```bash
# CRITICAL — assert on the LITERAL "my_proj", do NOT compute it from the typed query. tmux
# sanitizes every '.' and ':' -> '_' (my.proj -> my_proj; verified in issue3_findings.md).
# Computing it in bash would replicate tmux's rules — the very anti-pattern S1 avoided by
# capturing the actual name. The test asserts the OUTCOME (the literal sanitized name) +
# that the client landed on it, which is what matters.

# CRITICAL — the LOAD-BEARING assertion is "the client landed on my_proj"
# (assert_eq display-message -p '#{session_name}' == "my_proj"). On the bug, the client is
# STRANDED on "driver" (the old has-session gate rejected the sanitized success -> restore.sh
# cancel -> client back on driver). research FINDING 2/3: this is the ONE assertion that
# flips fix-vs-bug. The count check (before+1) PASSES on both — keep it as belt-and-braces
# (it guards a double-orphan/leftover), but do not treat it as the regression detector.

# CRITICAL — attach_test_client FIRST. display-message -p '#{session_name}' and switch-client
# REQUIRE an attached client (tests/setup_socket.sh FINDING 7). The sibling test attaches
# first; so must this one. Without a client, display-message returns the SERVER's session
# (not the client's) or empty -> a false result. (research FINDING 5.)

# CRITICAL — snapshot before_n DYNAMICALLY; do NOT hard-code 3. setup_socket seeds
# driver/alpha/beta (= 3) today, but a future fixture change must not break the test. Assert
# after_count == before_n + 1. `wc -l` emits LEADING WHITESPACE ("  4") -> pipe through
# `tr -d '[:space:]'` before the string compare (assert_eq is POSIX equality). Normalize BOTH
# before_n and the after count identically. (research FINDING 5; same idiom as
# test_window_preview_driver_self_no_duplicate in tests/test_preview.sh.)

# CRITICAL — signal failure ONLY via fail()/assert_*(). NEVER `exit`, NEVER `return` nonzero
# to abort (run.sh reads TEST_STATUS in the CURRENT shell; a bare exit kills the runner).
# Mirror the sibling's `if tmux has-session …; then pass …; else fail …; fi` form for the
# has-session predicates, and assert_eq for the value comparisons.

# GOTCHA — @livepicker-zoxide-mode defaults to "off" (scripts/options.sh:29). The create
# path's `if [ "$(opt_zoxide)" = "on" ]` branch therefore never fires for this test, and the
# sibling test relies on the same default (it sets neither). Do NOT add an explicit
# `tmux set-option -g @livepicker-zoxide-mode off` — it would deviate from the sibling
# pattern and is redundant. (research FINDING 4.) setup_test only pins @livepicker-preview-defer
# off; it does not touch zoxide, so the default-off holds for the test's lifetime.

# GOTCHA — `set -u` is INHERITED (from helpers.sh via run.sh). Do NOT re-declare it. Declare
# EVERY function-local with `local` (before_n, c). The `for c in m y . p r o j` loop var must
# be declared `local` on the same line as before_n (mirror the sibling's `local q="zzzno" c`).

# GOTCHA — Indent with TABS (the file is tab-indented; shfmt is NOT installed). The function
# body is 1-tab; nested blocks are 2-tab. Match the surrounding functions EXACTLY (open
# test_create.sh and copy the indent of test_create_on_creates_and_activates).

# GOTCHA — the function name MUST be `test_create_sanitized_name_lands_on_session` (the
# work-item contract name). run.sh discovers it via `compgen -A function | grep '^test_' |
# sort`, so lexical sort places it LAST among the create tests (after
# test_window_mode_creates_nothing).

# GOTCHA — do NOT add a second function (e.g. a collision test). The contract is ONE test_*
# function focused on the sanitized-name-lands scenario. The collision case (sanitized name
# exists -> cancel) is a SEPARATE concern covered by S1's mechanism research; it is out of
# scope here.
```

## Implementation Blueprint

### Data models and structure

No data model. The "structure" is the assertion flow, mirroring
`test_create_on_creates_and_activates`:

```
test_create_sanitized_name_lands_on_session():
  attach_test_client                                  # REQUIRED for display-message -p
  set @livepicker-create on                           # BEFORE activate (sibling order)
  before_n = list-sessions | wc -l | tr -d space     # snapshot (baseline-agnostic)
  livepicker.sh
  for c in m y . p r o j: input-handler.sh type "$c"  # type the DOTTED query
  input-handler.sh confirm
  assert has-session "=my_proj"  (sanitized created)  # A1
  assert ! has-session "=my.proj" (raw name absent)   # A2 (belt-and-braces)
  assert display-message -p '#{session_name}' == my_proj   # A3 LOAD-BEARING (landed)
  assert list-sessions | wc -l == before_n + 1        # A4 (exactly one new session)
  assert @livepicker-mode == ""                       # A5 (picker torn down)
```

### Implementation Tasks (ordered by dependencies)

```yaml
PRECONDITION: S1 (P1.M1.T3.S1) is applied to scripts/input-handler.sh. Verify the capture
  gate is present (NOT the buggy has-session gate):
    grep -q -- "-P -F '#{session_name}'" scripts/input-handler.sh && echo "OK: S1 applied" || echo "FAIL: S1 missing"
    grep -q '_confirm_land_on_session "\$created"' scripts/input-handler.sh && echo "OK: lands on captured" || echo "FAIL: lands on query (bug)"
    # The has-session gate must appear ONLY in a comment now (line ~394), NOT as a real gate:
    grep -n 'has-session -t "=$query"' scripts/input-handler.sh   # expect a single COMMENT line
  (S1 is applied; the capture + land-on-$created are present. This test validates them.)

Task 1: MODIFY tests/test_create.sh — APPEND the new function as the LAST function
  - LOCATE: the file currently ENDS with test_window_mode_creates_nothing's closing block
    (the `pass "window mode created nothing ($q absent)"` … `fi` then the final `}`).
  - ACTION: append `test_create_sanitized_name_lands_on_session` AFTER that closing `}`.
  - oldText/newText: see Implementation Patterns (anchor on the unique trailing block).
  - DO NOT: touch any other function, the header CONTRACT comment, or any other file.
  - DO NOT: add setup_test/teardown_test (run.sh owns the cycle) or re-declare `set -u`.

Task 2: VALIDATE (syntax + targeted smoke + full suite + load-bearing proof)
  - RUN: `bash -n tests/test_create.sh` (expect OK); `shellcheck tests/test_create.sh`
    (expect 0 NEW findings — SC2154/SC2016/SC2034/SC2086 are the file's pre-existing
     silenced directives in the header; the new function inherits them).
  - RUN: `bash tests/run.sh` (expect the new test PASS + the rest green; count rises by 1).
  - RUN (load-bearing proof): temporarily revert input-handler.sh's gate to the buggy
    `has-session -t "=$query"` form + land on `$query`, re-run JUST the new test, confirm
    it FAILS (A3 fires: got[driver] want[my_proj]), then RESTORE input-handler.sh and
    confirm green again. See Validation Level 3.
```

### Implementation Patterns & Key Details

**The edit — APPEND after the file's last function.** The file currently ends with:

```bash
# oldText (the LAST function's tail — unique anchor; replace with itself + the new function):
	# PRD §15.22 b3: nothing created.
	if tmux has-session -t "=$q" 2>/dev/null; then
		fail "window mode created nothing ($q must not exist — FINDING 6)"
	else
		pass "window mode created nothing ($q absent)"
	fi
}
# newText (same tail + the appended function):
	# PRD §15.22 b3: nothing created.
	if tmux has-session -t "=$q" 2>/dev/null; then
		fail "window mode created nothing ($q must not exist — FINDING 6)"
	else
		pass "window mode created nothing ($q absent)"
	fi
}

# test_create_sanitized_name_lands_on_session — Bugfix Issue 3 (P1.M1.T3.S2): typing a
# query containing '.' (a PRD §6 typeable char) and confirming on a no-match list must
# create the SANITIZED session (tmux maps '.' -> '_' => "my.proj" becomes "my_proj") AND
# land the client on it — not orphan the session and strand the user on the driver.
# Before P1.M1.T3.S1, the create gate checked `has-session -t "=$query"` (the ORIGINAL
# unsanitized name), which always failed after a sanitized `new-session` => the just-created
# session was orphaned and the client returned to the driver. S1 captures the actual name
# via `new-session -P -F '#{session_name}'` and switches to THAT; this test locks that in.
# Mirrors test_create_on_creates_and_activates EXACTLY (attach FIRST, @livepicker-create on
# BEFORE activate, type char-by-char, confirm) save that the query is dotted.
# @livepicker-zoxide-mode defaults to OFF (options.sh) so the zoxide branch never fires
# here — the sibling test relies on the same default (no explicit pin).
test_create_sanitized_name_lands_on_session() {
	attach_test_client
	tmux set-option -g @livepicker-create on
	local before_n c
	# Snapshot the session count BEFORE so the "no orphan" invariant is baseline-agnostic
	# (setup_socket seeds driver/alpha/beta = 3; a future fixture change must not break this).
	before_n="$(tmux list-sessions -F '#{session_name}' | wc -l | tr -d '[:space:]')"

	"$LIVEPICKER_SCRIPTS/livepicker.sh"
	for c in m y . p r o j; do
		"$LIVEPICKER_SCRIPTS/input-handler.sh" type "$c"
	done
	"$LIVEPICKER_SCRIPTS/input-handler.sh" confirm

	# Issue 3: the session is created under the SANITIZED name ("my.proj" -> "my_proj").
	if tmux has-session -t "=my_proj" 2>/dev/null; then
		pass "create-on-enter created the sanitized session my_proj"
	else
		fail "create-on-enter created the sanitized session my_proj (has-session = my_proj failed — Issue 3)"
	fi
	# Issue 3 (belt-and-braces): the RAW query name does NOT exist (no duplicate under "my.proj").
	if tmux has-session -t "=my.proj" 2>/dev/null; then
		fail "create-on-enter left a session under the raw name my.proj (should be sanitized to my_proj)"
	else
		pass "create-on-enter created no session under the raw name my.proj"
	fi
	# Issue 3 (LOAD-BEARING): the client LANDED on the sanitized session, not stranded on the driver.
	# (On the bug, restore.sh cancel returns the client to the driver -> this asserts my_proj.)
	assert_eq "$(tmux display-message -p '#{session_name}')" "my_proj" \
		"the client landed on the sanitized session my_proj (not stranded on the driver)"
	# Issue 3: exactly ONE session was created (count = before + 1); no orphan of any name.
	assert_eq "$(tmux list-sessions -F '#{session_name}' | wc -l | tr -d '[:space:]')" "$((before_n + 1))" \
		"exactly one new session created (no orphan left behind)"
	assert_eq "$(tmux show-option -gqv @livepicker-mode)" "" \
		"picker torn down after confirm"
}
```

Key pattern notes:
- The function is a direct mirror of `test_create_on_creates_and_activates` (same setup order,
  same `local … c` + `for c in …` type loop, same `pass`/`fail`/`assert_eq` style). The ONLY
  change is the query (`m y . p r o j`).
- `before_n` is snapshotted dynamically and asserted as `$((before_n + 1))` — baseline-agnostic.
- `wc -l | tr -d '[:space:]'` normalizes the count for the POSIX-equality `assert_eq`.
- The "raw name absent" check (A2) is written inline as `if has-session …; then fail; else pass; fi`
  (no `assert_not_contains` helper exists; this mirrors `test_create_off_creates_nothing`'s form).
- All assertions are quiet on success; `fail()` (directly or via `assert_eq`) sets `TEST_STATUS`
  on mismatch. No `exit`, no nonzero `return`.
- Indent is TABS throughout (1-tab body, 2-tab inside the `if`/`for`).

### Integration Points

```yaml
TESTS:
  - file: tests/test_create.sh
    change: "+test_create_sanitized_name_lands_on_session (appended as the LAST function)"
    discovery: "run.sh: compgen -A function | grep '^test_' | sort -> auto-registered, no wiring"
    invariant: "PASS on the fixed input-handler.sh; FAILS if the gate regresses to has-session/$query"

CODE: none (input-handler.sh is owned by S1; do NOT modify it here).
DATABASE / CONFIG / ROUTES: none.
```

## Validation Loop

### Level 1: Syntax & Style (Immediate Feedback)

```bash
cd /home/dustin/.config/tmux/plugins/tmux-livepicker
bash -n tests/test_create.sh && echo "OK: test_create syntax"
shellcheck tests/test_create.sh          # expect 0 NEW findings (SC2154/SC2016/SC2034/SC2086
                                          #   are the file's pre-existing silenced header directives)
# the new function is present + named correctly + is the LAST function:
grep -q '^test_create_sanitized_name_lands_on_session()' tests/test_create.sh \
  && echo "OK: function present" || echo "FAIL: function missing"
# the dotted query is typed char-by-char (NOT a single "my.proj" type call):
grep -q 'for c in m y . p r o j' tests/test_create.sh && echo "OK: dotted query typed" || echo "FAIL: query wrong"
# the load-bearing assertion + the dynamic count snapshot are present:
grep -q 'display-message -p .#{session_name}.' tests/test_create.sh && echo "OK: landed-on assertion"
grep -q 'wc -l | tr -d' tests/test_create.sh && echo "OK: count normalized"
# Tabs-not-spaces in the new region:
grep -nP '^    [^#/]' tests/test_create.sh | tail -20 && echo "WARN: space-indent" || echo "OK: tabs"
# PRECONDITION — S1 applied (the capture this test exercises):
grep -q -- "-P -F '#{session_name}'" scripts/input-handler.sh && echo "OK: S1 applied" || echo "FAIL: S1 missing"
grep -q '_confirm_land_on_session "\$created"' scripts/input-handler.sh && echo "OK: lands on captured" || echo "FAIL: lands on query"
```

### Level 2: Full suite (the new test auto-discovered + green)

```bash
cd /home/dustin/.config/tmux/plugins/tmux-livepicker
bash tests/run.sh
# Expected: the suite count rises by exactly 1 (the new test) and ALL tests PASS,
# including "PASS  test_create_sanitized_name_lands_on_session". The new test runs against
# a FRESH isolated socket (run.sh's per-test setup_test "lp-$$-...").
# If the new test FAILS, READ its ASSERT FAIL line — the most likely cause is S1 not
# actually being applied (re-check the PRECONDITION grep in Level 1).
```

### Level 3: Load-bearing proof (the test MUST fail when the bug is present — do not skip)

Temporarily revert input-handler.sh's create gate to the buggy form; the new test's
"landed on sanitized name" assertion (A3) MUST fail (got[driver] want[my_proj]). Restore
input-handler.sh and confirm green. This proves the test is not vacuous — it catches the
Issue 3 regression.

```bash
cd /home/dustin/.config/tmux/plugins/tmux-livepicker
cp scripts/input-handler.sh /tmp/input-handler.t3s2.bak
# Re-introduce the bug in a TEMP COPY first (safer than editing the live file): copy the
# plugin to /tmp, revert the gate there, and run the suite against the copy. If you edit
# the live file instead, RESTORE it immediately after.
# --- minimal live-file revert (fast; restore after) ---
python3 - <<'PY'
import pathlib
p = pathlib.Path("scripts/input-handler.sh")
s = p.read_text()
old_local = "\t\t\t\tlocal z_target=\"\" created=\"\" new_session_args=(-d -P -F '#{session_name}' -s \"$query\")"
new_local = "\t\t\t\tlocal z_target=\"\" new_session_args=(-d -s \"$query\")"
assert old_local in s, "local line (fixed) not found — S1 not applied?"
s = s.replace(old_local, new_local, 1)
old_gate = '\t\t\t\tcreated="$(tmux new-session "${new_session_args[@]}" 2>/dev/null)"\n\t\t\t\tif [ -n "$created" ]; then\n\t\t\t\t\t_confirm_land_on_session "$created"'
new_gate = '\t\t\t\tif tmux new-session "${new_session_args[@]}" 2>/dev/null && tmux has-session -t "=$query" 2>/dev/null; then\n\t\t\t\t\t_confirm_land_on_session "$query"'
assert old_gate in s, "gate (fixed) not found — S1 not applied?"
s = s.replace(old_gate, new_gate, 1)
p.write_text(s)
print("bug re-introduced (Issue 3 gate restored)")
PY
# Run the suite; the new test MUST FAIL (A3: got[driver] want[my_proj]); others stay PASS.
bash tests/run.sh 2>&1 | grep -E 'test_create_sanitized_name_lands_on_session|passed,'
# Expected: "FAIL  test_create_sanitized_name_lands_on_session" + "(N-1) passed, 1 failed".
# Restore the fix:
cp /tmp/input-handler.t3s2.bak scripts/input-handler.sh
rm -f /tmp/input-handler.t3s2.bak
grep -q -- "-P -F '#{session_name}'" scripts/input-handler.sh && echo "OK: fix restored" || echo "FAIL: fix NOT restored"
bash tests/run.sh 2>&1 | grep -E 'test_create_sanitized_name_lands_on_session|passed,'
# Expected: "PASS  test_create_sanitized_name_lands_on_session" + "N passed, 0 failed".
```

### Level 4: Creative & Domain-Specific Validation

```bash
# (Optional) Direct harness smoke mirroring run.sh's per-test cycle, isolating the new
# test from the full suite (useful if the suite is slow and you want a tight loop). This
# is EXACTLY the validation that produced research FINDING 1/2:
cd /home/dustin/.config/tmux/plugins/tmux-livepicker
cat > /tmp/lp_t3s2_isolated.sh <<'SMOKE'
#!/usr/bin/env bash
set -u
cd /home/dustin/.config/tmux/plugins/tmux-livepicker
source tests/setup_socket.sh
source tests/helpers.sh
source tests/test_create.sh           # defines the new test_*
setup_test "lp-t3s2-iso"
TEST_STATUS="pass"
test_create_sanitized_name_lands_on_session
echo "RESULT: $TEST_STATUS"
teardown_test
[ "$TEST_STATUS" = "pass" ]
SMOKE
bash /tmp/lp_t3s2_isolated.sh; rc=$?; rm -f /tmp/lp_t3s2_isolated.sh
echo "isolated smoke exit=$rc"   # Expected: RESULT: pass, exit 0
# Expected: RESULT: pass, exit 0.
```

## Final Validation Checklist

### Technical Validation

- [ ] `bash -n tests/test_create.sh` clean; `shellcheck` 0 NEW findings.
- [ ] `test_create_sanitized_name_lands_on_session` is appended as the LAST function.
- [ ] L2 full suite: green; the new test PASSes; count rises by exactly 1.
- [ ] L3 load-bearing: reverting input-handler.sh's gate to `has-session`/`$query` makes the
      new test FAIL (A3: got[driver] want[my_proj]); restoring makes it PASS again.

### Feature Validation

- [ ] All 5 contract assertions present: sanitized created (A1) / raw name absent (A2) /
      client landed on sanitized name (A3, load-bearing) / count == before+1 (A4) / mode
      cleared (A5).
- [ ] The test attaches a client FIRST (required for `display-message -p`).
- [ ] The count is snapshotted dynamically (no hard-coded 3) and whitespace-normalized.

### Code Quality Validation

- [ ] Mirrors `test_create_on_creates_and_activates` exactly (attach → create on → activate →
      char-by-char type → confirm → pass/fail/assert_eq); the dotted query is the only change.
- [ ] `set -u`-safe: every local declared; `wc -l` output whitespace-normalized.
- [ ] Tab indent; `fail`/`assert_*` only (no `exit`, no nonzero `return` to abort).
- [ ] No production code touched (input-handler.sh belongs to S1).

### Documentation & Deployment

- [ ] The function's header comment documents: what it tests (Issue 3), the sanitization
      (`.` -> `_`), why A3 is load-bearing, the S1 regression it guards, and the pattern it
      mirrors.
- [ ] Doc sync (CHANGELOG/README) is NOT this task's scope (test-only; P1.M3.T1 owns docs).

---

## Anti-Patterns to Avoid

- ❌ Don't compute the sanitized name from the typed query in bash (e.g. `${query//./_}`).
  That replicates tmux's sanitization rules — the fragile anti-pattern S1 avoided by
  capturing the actual name. Assert on the literal `my_proj` (the OUTCOME).
- ❌ Don't hard-code the baseline session count (3). `setup_socket` seeds driver/alpha/beta
  today; a future fixture change would silently break the test. Snapshot `before_n` and
  assert `after == before_n + 1`.
- ❌ Don't drop the `tr -d '[:space:]'` on `wc -l`. `wc -l` emits leading whitespace
  (`"      4"`); `assert_eq` is a POSIX string compare and would fail on `"  4"` vs `"4"`.
  Normalize BOTH the before and after counts.
- ❌ Don't skip `attach_test_client`. `display-message -p '#{session_name}'` and
  `switch-client` REQUIRE an attached client (setup_socket.sh FINDING 7). Without one the
  "landed on" assertion is meaningless. Attach FIRST (the sibling's order).
- ❌ Don't add `tmux set-option -g @livepicker-zoxide-mode off`. `@livepicker-zoxide-mode`
  defaults to `"off"` (options.sh:29); the sibling test relies on that default. Adding the
  pin deviates from the pattern and is redundant. (research FINDING 4.)
- ❌ Don't type the query as a single `input-handler.sh type "my.proj"` call. The plugin
  types char-by-char (each keystroke refilters); the sibling uses a `for c in …` loop. Mirror
  it: `for c in m y . p r o j`.
- ❌ Don't treat the count assertion (A4) as the regression detector. It PASSES on both fix
  and bug (the orphan IS the +1 session). The LOAD-BEARING assertion is A3 (landed on
  `my_proj`). Keep A4 as belt-and-braces (it guards a double-orphan/leftover) but don't
  remove A3 thinking A4 covers it.
- ❌ Don't `exit` or `return` nonzero to signal failure — run.sh reads `TEST_STATUS` in the
  current shell; a bare exit kills the runner. Use `fail()`/`assert_*()` only.
- ❌ Don't split the assertions into multiple `test_*` functions, and don't add a collision
  test. The contract is ONE function focused on the sanitized-name-lands scenario.
- ❌ Don't modify `scripts/input-handler.sh` — that is S1's scope (applied). This task is
  test-only. The L3 load-bearing check temporarily reverts input-handler.sh but RESTORES it.
- ❌ Don't edit by guessing the file's tail — open `tests/test_create.sh`, confirm the last
  function is `test_window_mode_creates_nothing`, and anchor the append on its unique closing
  block (the `pass "window mode created nothing ($q absent)"` … `fi` + final `}`).

---

## Confidence Score

**10 / 10** for one-pass success. Rationale: the test is a single append of one function whose
verbatim body is supplied; every assertion is EMPIRICALLY PROVEN on the isolated harness
(research FINDING 1: pass=5 fail=0 against the fixed input-handler.sh; FINDING 2: pass=4 fail=1
against the reverted bug — the test is load-bearing, not vacuous, with A3 the single
load-bearing assertion); it mirrors `test_create_on_creates_and_activates` exactly (the dotted
query is the only change); `run.sh` auto-discovers it (no wiring); it touches no production
code (zero regression risk to the rest of the suite); and the L3 load-bearing check
deterministically proves it catches the Issue 3 regression. The zoxide default-off removes the
only nondeterminism risk, so the test is portable across configs. The S1 fix is already
applied, so the test is green on first run.
