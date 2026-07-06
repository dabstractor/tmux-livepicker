# PRP — P1.M3.T1.S1: tests/test_responsiveness.sh — PRD §15.23 / §18 deferred-preview validation

> **Scope**: Test-ONLY. Creates `tests/test_responsiveness.sh` (one new file, no
> production code). Validates PRD §18's interaction-first / deferred-preview
> contract under the shipped socket-isolated harness: typing/nav redraw the status
> **synchronously** and **defer** the preview to a background, supersedeable
> `run-shell -b` job; confirm never blocks on a preview; defer=off restores the
> legacy synchronous-preview path. All deferred-preview dependencies are LANDED
> (`_lp_fire_preview`/`_lp_preview_follow`, preview.sh's seq guard,
> `STATE_PREVIEW_SEQ`/`STATE_PREVIEW_TARGET`, `opt_preview_defer`, the
> `setup_test` defer=off pin). This task consumes them.

---

## Goal

**Feature Goal**: A new `tests/test_responsiveness.sh`, sourced by `run.sh`,
that deterministically validates the five §18 behaviors (PRD §15.23): (a) typing
defers the preview (status+seq sync, link async); (b) rapid typing + confirm
collapses to one link and lands correctly (no backlog); (c) a superseded preview
fire is a true no-op (only the latest target links); (d) nav moves the highlight
synchronously ahead of the deferred preview; (e) defer=off restores the
synchronous-preview path. Every test is non-flaky (sync assertions are immediate
and deterministic; async links are polled with a generous timeout).

**Deliverable**: The single file `tests/test_responsiveness.sh` — a sourced
library defining 5 `test_*` functions (auto-discovered by `run.sh` via
`compgen`) + 2 `lp_`/non-`test_` helpers (`wait_linked`, `_lp_active_wid`). No
production code change, no other test file touched, no new fixture machinery.

**Success Definition**:
- `bash -n tests/test_responsiveness.sh` clean; `shellcheck` 0 new findings.
- `bash tests/run.sh` exits 0 with all 5 new tests printing PASS (and the existing
  suite still green on the defer=off pin).
- Each test OPTS INTO the deferred path by setting `@livepicker-preview-defer on`
  (except (e), which sets it `off`), overriding the `setup_test` pin.
- (a) proves deferral: after `type`, SEQ bumped + renderer shows the new query
  synchronously + linked-id is still the pre-type value immediately, THEN (poll)
  linked-id becomes the target.
- (e) proves the contrast: defer=off → after `type`, linked-id is the target
  synchronously (no poll) and SEQ is unbumped.
- Zero flakiness: no test relies on a sleep-only race; every async link is polled.

## User Persona (if applicable)

**Target User**: The maintainer / automated QA (CI). Not end-user facing.

**Use Case**: A maintainer runs `bash tests/run.sh` to validate the §18
responsiveness contract did not regress (e.g. someone re-inlined a synchronous
preview into the type path, or broke the supersede guard). Each PASS proves one
§18 bullet holds on an isolated socket.

**Pain Points Addressed**: Before this task, the deferred path (defer=on) is
validated only by throwaway smokes in P1.M2.T3.S1 (deleted after). The committed
suite runs defer=off (via the `setup_test` pin) for determinism, so a regression
in the producer (`_lp_fire_preview`), the consumer (preview.sh guard), or their
`$2`-seq seam would slip through. This file is the permanent, committed guard.

## Why

- **PRD §15.23 mandates it.** The validation cluster "Responsiveness" requires
  tests proving the interaction-first contract. §18's contract (typing status-only
  + sync; nav sync-highlight + deferred preview; preview deferred + supersedeable;
  confirm never blocks) is the most concurrency-sensitive part of the plugin.
- **The seam is subtle and regress-prone.** The producer (`_lp_fire_preview`) and
  consumer (preview.sh `expected_seq` guard) communicate via `$2=<seq>` ↔
  `STATE_PREVIEW_SEQ`. A wrong arg order, a missing bump, a guard that runs after
  the mutation, or a teardown that doesn't clear the seq would each silently break
  supersede. These tests pin all four shapes.
- **The existing suite cannot cover this.** It runs defer=off (the pin is
  mandatory — without it `test_functional.sh`'s synchronous linked-id asserts race
  the async job). So defer=on behavior needs a dedicated file that opts in per test.
- **Cheap, isolated, zero prod risk.** One new test file; no script edits; disjoint
  from every production task. Auto-discovered by `run.sh`.

## What

A single new file `tests/test_responsiveness.sh`, sourced by `run.sh`, defining:

1. Two helpers: `wait_linked <want>` (polls `@livepicker-linked-id` to `want` or
   ~2s timeout) and `_lp_active_wid <session>` (reads a session's active window id).
2. Five `test_*` functions (a–e above), each: `attach_test_client` → set
   `@livepicker-preview-defer` on/off → drive `$LIVEPICKER_SCRIPTS/livepicker.sh`
   + `input-handler.sh` → assert via `assert_eq`/`assert_contains`/inline `case`+`fail`
   + `wait_linked`. Window ids captured dynamically.

### Success Criteria

- [ ] File at `tests/test_responsiveness.sh`; shebang `#!/usr/bin/env bash`;
      header documents the sourced-by-run.sh contract + the defer opt-in + the
      async-timing model.
- [ ] Defines exactly the helpers `wait_linked` + `_lp_active_wid` (non-`test_`
      prefix → not auto-run) and 5 `test_*` functions.
- [ ] (a) `test_typing_defers_preview`: defer=on; type → SEQ>0 + renderer shows
      query + linked-id still pre-type IMMEDIATELY; poll → linked-id == target.
- [ ] (b) `test_rapid_type_confirm_no_backlog`: defer=on; type 3 chars → SEQ==3;
      poll → linked-id == final target; confirm → client lands on target.
- [ ] (c) `test_superseded_preview_noop`: defer=on; 2 rapid next-session → poll →
      linked-id == LATEST target; driver has exactly one preview window.
- [ ] (d) `test_nav_moves_highlight_before_preview`: defer=on; next-session →
      index advanced + renderer highlights next session IMMEDIATELY; poll → linked-id.
- [ ] (e) `test_preview_defer_off_synchronous`: defer=off; type → linked-id ==
      target SYNCHRONOUSLY (no poll) + SEQ==0.
- [ ] `bash -n` clean; `shellcheck` 0 new findings; `bash tests/run.sh` exit 0
      with all 5 new tests PASS.

## All Needed Context

### Context Completeness Check

_Pass_: an implementer who has never seen this repo can do it from (a) the
verbatim test file body in the Implementation Blueprint (copy-paste), (b) the
async-timing model (sync seq/renderer/index vs polled link) that makes each
assertion deterministic, (c) the verified implementation state (all deps landed,
with grep markers), and (d) the harness contract (sourced by run.sh; assert API;
attach_test_client mandatory). No inference required.

### Documentation & References

```yaml
# MUST READ — the empirical ground-truth for THIS task (timing model + verified deps + design)
- docfile: plan/002_facc52335e68/P1M3T1S1/research/test_responsiveness_findings.md
  why: §1 (all deps grep-confirmed landed); §2 (THE async-timing model: seq/renderer/index
       are SYNCHRONOUS, the link is ASYNC + polled — the non-flakiness key); §3 (harness
       contract: sourced by run.sh, assert API, attach_test_client mandatory); §4 (the 5
       test designs mapped to reliable assertions); §5 (reliability checklist).
  critical: §2 is load-bearing — without the sync/async split, the "deferral" assertions
       become flaky sleep-races. The wait_linked poll (100×20ms) + the immediate linked-id-
       still-old read (bg job startup ~30-60ms >> read ~5ms) are what make (a)/(d) deterministic.

# MUST READ — the deferred-preview PRODUCER contract (treat as implemented exactly)
- docfile: plan/002_facc52335e68/P1M2T3S1/PRP.md
  why: defines _lp_fire_preview (bumps SEQ, sets TARGET, run-shell -b), _lp_preview_follow
       (defer=on refresh-then-fire; defer=off sync-preview-then-refresh), and the setup_test
       defer=off pin (THIS task opts back into on). Its L2/L3 throwaway smokes are the
       PROVEN timing pattern this file commits (wait_linked poll + the immediate-read lag).
  critical: the setup_test pin means EVERY test here must set @livepicker-preview-defer
            explicitly. Confirm never reads @livepicker-linked-id (§18 #4) — proven by (b).

# MUST READ — the deferred-preview CONSUMER (the seq guard this file exercises)
- docfile: plan/002_facc52335e68/P1M2T2S1/PRP.md
  why: preview.sh accepts `preview.sh <target> [expected_seq]` and NO-OPS when the seq is
       stale (the guard (c) relies on). One-arg calls (defer=off / activate first-preview)
       are guard-skipped — that is why (e) sees a synchronous link with SEQ unbumped.
  section: the guard semantics (expected_seq vs cur_seq)

# MUST READ — the harness contract (how run.sh discovers + runs tests; the assert API)
- docfile: plan/002_facc52335e68/architecture/test_harness.md
  why: §2 (run.sh sources setup_socket+helpers+test_*.sh; discovers test_* via compgen in
       the CURRENT shell; per-test setup_test/teardown_test); §3 (the COMPLETE assert API:
       fail/pass/assert_eq/assert_contains + inline case+fail for negatives; NEVER exit);
       §4 (test_functional.sh is the structural template; test_preview.sh the cleanest).
  critical: tests MUST signal failure only via fail/assert_* (set TEST_STATUS); a bare exit
            kills run.sh. Non-test helpers MUST be prefixed lp_ (or non-test_) so compgen
            does not discover them.

# MUST READ — async timing ground-truth (run-shell -b non-blocking; refresh-client -S needs a client)
- docfile: plan/002_facc52335e68/architecture/external_tmux_behavior.md
  why: Q5 (run-shell -b detached/non-blocking/non-cancellable — the bg job lags the fire);
       Q6 (the monotonic-seq supersede pattern + the read->mutate race guard); Q7
       (refresh-client -S forces #() re-eval BUT is a no-op on a client-less socket ->
       attach_test_client is MANDATORY).
  section: "Q5", "Q6", "Q7"

# MUST READ — the structural + lifecycle template (activate/attach/assert/cancel)
- file: tests/test_functional.sh
  why: the exact pattern to mirror — header contract block; attach_test_client FIRST;
        "$LIVEPICKER_SCRIPTS/livepicker.sh" to activate; input-handler.sh type/next/confirm;
        DYNAMIC window-id capture via list-windows; assert_eq/assert_contains + inline
        case+fail; the lp_runtime_cleared helper (for the confirm-lands assertion).
  pattern: test_activate_grows_status (attach+activate+assert), test_nav_moves_selection
           (dynamic wid + linked-id assert), test_typing_filters (seed fixtures BEFORE
           activate + renderer output assert + inline negative case).
  gotcha: test_functional.sh runs defer=OFF (via the setup_test pin) and asserts linked-id
          SYNCHRONOUSLY — do NOT copy that timing assumption; this file opts defer=ON and
          must POLL the async link.

# MUST READ — the activation origin + the refresh-client-needs-client helper
- file: tests/setup_socket.sh
  why: attach_test_client [sess="driver"] (spawns a script pty, sleep 0.5); the baseline
        fixtures (driver/alpha/beta; driver has a 2nd "extra" 3-pane window; beta is split).
        TEST_DRIVER_SESSION="driver"; TEST_FIXTURE_SESSIONS="alpha beta".
  gotcha: there is NO resize helper; responsiveness here is about timing/deferral, NOT
          window-size (the test_harness "responsiveness" note about resize is a red herring
          for THIS file — §18 is about input latency, validated via the seq/link split).

# Reference — PRD §18 (the feature spec) + §15.23 (the validation cluster)
- docfile: PRD.md
  why: §18 contract (typing status-only sync; nav sync-highlight + deferred preview;
       preview deferred + supersedeable via a sequence; confirm never blocks; defer=off
       restores legacy); §15.23 names the Responsiveness cluster.
  section: "§18 Responsiveness", "§15.23 Responsiveness"
```

### Current Codebase tree

```bash
tmux-livepicker/
  tests/
    run.sh                  # UNCHANGED — auto-sources test_*.sh via nullglob; discovers test_*
    setup_socket.sh         # UNCHANGED — attach_test_client + baseline fixtures (driver/alpha/beta)
    helpers.sh              # UNCHANGED — fail/pass/assert_eq/assert_contains; setup_test pins defer=off
    test_functional.sh      # UNCHANGED — the structural template (mirror its header/lifecycle)
    test_pollution.sh       # UNCHANGED — fixture-install pattern (not needed here)
    test_preview.sh         # UNCHANGED — cleanest seed-state template
    test_restore.sh, test_create.sh, test_keyrepurpose.sh, test_self.sh  # UNCHANGED
    test_responsiveness.sh  # NEW (this task) — the 5 §18/§15.23 tests
  scripts/                  # UNCHANGED (all §18 deps landed: input-handler/preview/state/options)
```

### Desired Codebase tree with files to be added and responsibility of file

```bash
tests/test_responsiveness.sh   # NEW. 5 test_* functions (a-e) + wait_linked/_lp_active_wid helpers.
                               #   Sourced by run.sh. Opts defer=on per test (off for (e)).
                               #   Validates PRD §15.23 / §18: sync status + deferred/supersedeable
                               #   preview + confirm-independence + defer=off contrast.
```

### Known Gotchas of our codebase & Library Quirks

```bash
# CRITICAL (research §2): the async split is what makes these tests non-flaky. The seq
# (STATE_PREVIEW_SEQ), the filter/index, and the renderer output are SYNCHRONOUS (set
# before _lp_fire_preview / input-handler returns). The actual link-window is ASYNC (the
# bg run-shell -b preview.sh job). So: assert seq/filter/index/renderer IMMEDIATELY (no
# sleep); assert the link via wait_linked POLL (2s timeout). The "linked-id still old
# immediately" read is reliable because the bg job's startup (fork+bash+libs+round-trips
# ~30-60ms) vastly exceeds the test's show-option read (~5ms).

# CRITICAL (research §1/helpers.sh:84): setup_test pins @livepicker-preview-defer OFF so
# the existing suite stays deterministic. EVERY test here MUST set it explicitly:
#   tmux set-option -g @livepicker-preview-defer on    # (a)-(d)
#   tmux set-option -g @livepicker-preview-defer off   # (e) — the legacy contrast
# Set it AFTER attach_test_client, BEFORE the first input action (activate's first preview
# is synchronous regardless, so the exact moment before/after activate is fine).

# CRITICAL (external_tmux_behavior Q7): refresh-client -S is a NO-OP on a client-less
# detached socket. attach_test_client is MANDATORY in every test (the input handler's
# _lp_preview_follow calls refresh-client -S; confirm needs switch-client; display-message
# -p needs a client). Without it, the status-redraw path is silently skipped.

# CRITICAL: NEVER `exit` or `return`-nonzero from a test body to signal failure — run.sh
# reads TEST_STATUS in the CURRENT shell; a bare exit kills the runner. Use fail()/
# assert_* (they set TEST_STATUS=fail). Early `return 0` to skip the rest of a body is OK.

# GOTCHA: window ids (@N) are GLOBAL and must be captured DYNAMICALLY per test (renumber-
# windows is on; hardcoded ids break). Use: tmux list-windows -t "=<sess>" -F '#{window_id}'
# -f '#{window_active}'. The helper _lp_active_wid wraps this.

# GOTCHA: the baseline list is driver/alpha/beta. For (a) "type a" to match alpha and NOT
# the driver, confirm "a" is not a substring of driver — it isn't ("driver" has no 'a').
# Actually 'alpha' contains 'a'; 'driver' does not; 'beta' does. So filter "a" matches
# alpha AND beta. To make (a) deterministic, type a char matching ONLY alpha: filter "al"
# (alpha matches; beta/driver don't). OR add a uniquely-matching session. (See test body:
# (a) types "a" then asserts the deferred link is alpha's wid — but "a" also matches beta,
# and the top match is whichever sorts first. To avoid ambiguity, (a) types "al" so the top
# match is unambiguously alpha. The contract says "type one char" — use "a" but resolve the
# top match dynamically from the renderer/list rather than hardcoding alpha. The committed
# test resolves the expected target from the filtered list, not a hardcoded session.)

# GOTCHA: there is NO assert_not_contains / assert_rc in the API. For negatives use an inline
#   case "$x" in *<bad>*) fail "<bad> leaked" ;; esac
# For a "wait for X or timeout" use the wait_linked helper (returns rc; `wait_linked X || fail`).

# GOTCHA: non-test helpers MUST be prefixed `lp_` or otherwise not start with `test_`, or
# run.sh's `compgen -A function | grep '^test_'` will try to run them as tests. wait_linked
# and _lp_active_wid are safe (no test_ prefix).

# GOTCHA: the file SOURCES NOTHING and calls NO setup_test/teardown_test at file scope
# (run.sh owns the per-test cycle). Each test_* body uses attach_test_client (in scope via
# run.sh's source of setup_socket.sh) + bare tmux (hits the isolated socket via the shim).

# GOTCHA (research §5): each test runs on a FRESH isolated socket (run.sh per-test
# setup_test/teardown_test), so the per-test @livepicker-preview-defer / created sessions
# never leak across tests. Cleanup is automatic.

# STYLE: indent with TABS (match test_functional.sh; shfmt NOT installed). `set -u` is
# INHERITED — declare every local. Mirror test_functional.sh's shellcheck disable line:
#   # shellcheck disable=SC2154,SC2016,SC2034,SC2086
# (SC2154: assert_*/attach_test_client/$LIVEPICKER_SCRIPTS/$TEST_DRIVER_SESSION defined by
#  run.sh's sources; SC2016: single-quoted tmux formats in assert messages; SC2034/SC2086
#  miror the sibling test files.)
```

## Implementation Blueprint

### Data models and structure

No data model. The "structure" is the timing model the tests encode:

```
input-handler.sh type/backspace/nav (defer=on)
 └─ _lp_preview_follow(target)
     ├─ refresh-client -S            # SYNCHRONOUS (status redraws now)
     └─ _lp_fire_preview(target)
         ├─ seq = SEQ+1 ; set SEQ ; set TARGET   # SYNCHRONOUS (state writes)
         └─ tmux run-shell -b "preview.sh 'target' 'seq'"  # ASYNC launch (returns immediately)
                                  └─ (bg) preview.sh: guard(seq) → link-window → set LINKED_ID

TEST ASSERTIONS:
  SYNCHRONOUS (immediate, no poll): SEQ bumped, filter/index set, renderer.sh output current,
                                    LINKED_ID still the pre-action value (the lag).
  ASYNC (poll ~2s):                 LINKED_ID == target's active window id (the deferred link).
```

### Implementation Tasks (ordered by dependencies)

```yaml
Task 1: CREATE tests/test_responsiveness.sh — header + 2 helpers
  - FILE: ./tests/test_responsiveness.sh
  - SHEBANG: #!/usr/bin/env bash
  - HEADER: mirror test_functional.sh's contract block (SOURCED by run.sh; defines test_*;
    run.sh owns the per-test cycle; bare tmux hits the isolated socket). ADD: this file
    OPTS INTO @livepicker-preview-defer=on per test (overriding the setup_test pin) except
    (e); the async-timing model (seq/filter/index/renderer SYNC; link ASYNC → polled); and
    the shellcheck disable line.
  - HELPER wait_linked <want>: poll @livepicker-linked-id up to 100×20ms (2s); return 0 if
    it equals want, 1 on timeout. (The bg run-shell -b job is async; healthy <50ms.)
  - HELPER _lp_active_wid <session>: print the session's active window id (dynamic; global).
  - STYLE: TAB indent; `set -u` inherited (do NOT re-declare); `local` for all locals.

Task 2: IMPLEMENT (a) test_typing_defers_preview
  - attach_test_client; set defer on; activate (first preview=self → linked-id "").
  - Resolve the top-match-for-"a" target dynamically (filtered list[0]); capture its wid + L0="".
  - input-handler.sh type a.
  - IMMEDIATE: assert SEQ > 0 (bumped sync); assert renderer output contains "a" (query sync);
    assert linked-id == "" (still the self-session — the bg job hasn't run; the lag).
  - POLL: wait_linked "<target_wid>" && assert linked-id == target_wid (deferred catch-up).

Task 3: IMPLEMENT (b) test_rapid_type_confirm_no_backlog
  - attach_test_client; set defer on; create "xyz" session BEFORE activate (unique match);
    activate.
  - Type x, y, z (3 rapid fires). IMMEDIATE: assert SEQ == 3 (3 sync fires).
  - POLL: wait_linked xyz_wid → assert linked-id == xyz_wid (burst collapsed to 1 link).
  - Confirm. assert client session == "xyz" (confirm independent of preview, §18 #4).
    (Use lp_runtime_cleared-style check or assert session via display-message -p.)

Task 4: IMPLEMENT (c) test_superseded_preview_noop
  - attach_test_client; set defer on; activate.
  - next-session (→alpha, seq1), next-session (→beta, seq2) rapidly.
  - POLL: wait_linked beta_wid → assert linked-id == beta_wid (latest wins; alpha fire no-op'd).
  - Assert driver window list contains beta_wid exactly ONCE and NOT alpha_wid (no stray link).
  - Assert alpha's window intact in alpha (source undamaged). sleep 0.2; re-assert beta_wid
    stable (a late stale job didn't clobber the newer link).

Task 5: IMPLEMENT (d) test_nav_moves_highlight_before_preview
  - attach_test_client; set defer on; activate. Capture pre-nav index.
  - next-session. IMMEDIATE: assert @livepicker-index advanced (sync); assert renderer output
    highlights the next session (sync); best-effort linked-id still "" (lag).
  - POLL: wait_linked alpha_wid → assert linked-id == alpha_wid (deferred catch-up).

Task 6: IMPLEMENT (e) test_preview_defer_off_synchronous
  - attach_test_client; set defer OFF (explicit). activate.
  - Resolve the top-match-for-"a" target dynamically; capture its wid.
  - input-handler.sh type a.
  - IMMEDIATE (NO poll): assert linked-id == target_wid (preview ran inline, sync — legacy
    restored); assert SEQ == 0 (defer=off path doesn't bump the seq / fire a bg job).

Task 7: VALIDATE (syntax + lint + full suite)
  - RUN: bash -n tests/test_responsiveness.sh
  - RUN: shellcheck tests/test_responsiveness.sh (expect 0 new findings; disable line matches
    test_functional.sh).
  - RUN: bash tests/run.sh (expect the 5 new tests PASS + existing suite green; exit 0).
```

### Implementation Patterns & Key Details

> The block below is the COMPLETE, ready file body. Use it as-is; the only allowed
> deviation is comment phrasing. TAB indent throughout (match test_functional.sh).
> Every test sets defer explicitly + attaches a client + captures window ids dynamically.
> Sync assertions are immediate; async links are polled via `wait_linked`.

```bash
#!/usr/bin/env bash
# tests/test_responsiveness.sh — tmux-livepicker PRD §15.23 Responsiveness / §18
# deferred-preview validation (P1.M3.T1.S1).
#
# SOURCED by run.sh (NEVER executed directly). Defines five test_* functions that
# validate PRD §18's interaction-first contract on the socket-isolated server:
# typing/nav redraw the status SYNCHRONOUSLY and DEFER the preview to a background,
# supersedeable run-shell -b job; confirm never blocks on a preview; defer=off
# restores the legacy synchronous-preview path.
#
# CONTRACT: run.sh sources setup_socket.sh + helpers.sh + every tests/test_*.sh,
# then PER test calls setup_test "lp-$$-<name>" (-> fresh isolated socket + PATH
# shim + baseline fixtures driver/alpha/beta) -> resets TEST_STATUS=pass -> runs
# the test_* in the CURRENT shell -> reads TEST_STATUS -> teardown_test. So when a
# test_* runs: bare `tmux` hits the isolated socket; $LIVEPICKER_SCRIPTS,
# attach_test_client, fail/pass/assert_eq/assert_contains are all IN SCOPE; this
# file SOURCES NOTHING and calls NO setup_test/teardown_test at file scope.
#
# DEFER OPT-IN (CRITICAL): setup_test (helpers.sh) pins @livepicker-preview-defer
# OFF so the existing functional/restore/etc. tests' SYNCHRONOUS @livepicker-
# linked-id assertions stay deterministic. THESE tests OPT INTO the deferred path
# by setting @livepicker-preview-defer ON per test (except (e), the legacy contrast,
# which sets it OFF explicitly).
#
# ASYNC TIMING (external_tmux_behavior.md Q5/Q6/Q7): run-shell -b is detached/
# non-blocking/non-cancellable. _lp_fire_preview bumps STATE_PREVIEW_SEQ and sets
# STATE_PREVIEW_TARGET SYNCHRONOUSLY (before run-shell -b returns); the actual
# link-window + set @livepicker-linked-id happens ASYNC in the bg preview.sh job.
# So this file asserts:
#   SYNCHRONOUS (immediate, no sleep): SEQ bumped, filter/index set, renderer.sh
#     output current, AND @livepicker-linked-id still the PRE-action value (the bg
#     job's fork+bash+libs+round-trips ~30-60ms >> the test's show-option read ~5ms,
#     so the immediate read reliably observes the lag).
#   ASYNC (poll ~2s via wait_linked): @livepicker-linked-id == the target's window id.
# refresh-client -S is a no-op on a client-less socket (Q7) -> attach_test_client is
# MANDATORY in every test.
#
# `set -u` is INHERITED from helpers.sh (do NOT re-declare; mirror test_self.sh).
# shellcheck disable=SC2154,SC2016,SC2034,SC2086
#   SC2154: assert_*/attach_test_client/$LIVEPICKER_SCRIPTS/$TEST_DRIVER_SESSION are
#           defined by run.sh's sources, not in this file.

# wait_linked WANT — poll @livepicker-linked-id until it equals WANT (rc 0) or ~2s
# timeout (rc 1). The bg run-shell -b preview job is async; on a healthy isolated
# socket it links in <50ms. Mirrors the P1.M2.T3.S1 defer-fire smoke. Callers use
# `wait_linked "$wid" || fail "...not linked"`.
wait_linked() {
	local want="$1" i
	for i in $(seq 1 100); do
		[ "$(tmux show-option -gqv @livepicker-linked-id)" = "$want" ] && return 0
		sleep 0.02
	done
	return 1
}

# _lp_active_wid SESSION — print SESSION's active window id (@N). Window ids are
# GLOBAL but renumber-windows=on makes indices unstable -> capture DYNAMICALLY.
_lp_active_wid() {
	tmux list-windows -t "=$1" -F '#{window_id}' -f '#{window_active}'
}

# (a) test_typing_defers_preview — PRD §18.1: typing is status-only + synchronous;
# the preview is DEFERRED. After one type, SEQ bumped + renderer shows the new query
# + linked-id UNCHANGED (the bg job hasn't run); the link arrives ASYNC (poll).
test_typing_defers_preview() {
	attach_test_client
	tmux set-option -g @livepicker-preview-defer on
	"$LIVEPICKER_SCRIPTS/livepicker.sh"
	# Activate's first preview is the SELF-session -> no link yet.
	assert_eq "$(tmux show-option -gqv @livepicker-linked-id)" "" \
		"initial self-session preview leaves no link"
	# Resolve the top filtered match for "a" DYNAMICALLY from @livepicker-list
	# (filter is now "a"). Mirrors lp_build_filtered: case-insensitive substring,
	# list order; "a" matches alpha + beta, so read the actual top match, never
	# hardcode it (do NOT parse the renderer's styled output — names with special
	# chars would break a sed extract; the list is the source of truth).
	"$LIVEPICKER_SCRIPTS/input-handler.sh" type a >/dev/null
	local top_wid top_sess
	top_sess="$(printf '%s\n' "$(tmux show-option -gqv @livepicker-list)" | grep -i 'a' | head -1)"
	top_wid="$(_lp_active_wid "$top_sess")"
	[ -n "$top_wid" ] || fail "resolved a top 'a' match from the live list (got empty)"
	# SYNCHRONOUS assertions (immediate — the input handler has returned; the bg job lags):
	# SEQ bumped (>0), renderer shows the query, linked-id STILL "" (the lag).
	local seq
	seq="$(tmux show-option -gqv @livepicker-preview-seq)"
	[ -n "$seq" ] && [ "$seq" != "0" ] \
		|| fail "type bumped @livepicker-preview-seq synchronously (got [$seq])"
	assert_contains "$("$LIVEPICKER_SCRIPTS/renderer.sh")" "query> a" \
		"status reflects the new query synchronously"
	assert_eq "$(tmux show-option -gqv @livepicker-linked-id)" "" \
		"preview link LAGS the status (still the self-session immediately after type)"
	# ASYNC: the deferred bg job eventually links the top match.
	wait_linked "$top_wid" \
		|| fail "deferred preview never linked the top match ($top_sess @ $top_wid)"
	assert_eq "$(tmux show-option -gqv @livepicker-linked-id)" "$top_wid" \
		"deferred preview linked the top match (async catch-up)"
	"$LIVEPICKER_SCRIPTS/input-handler.sh" cancel >/dev/null 2>&1 || true
}

# (b) test_rapid_type_confirm_no_backlog — PRD §18: a burst of typing collapses to a
# single trailing preview (supersede), and confirm lands correctly without waiting.
test_rapid_type_confirm_no_backlog() {
	attach_test_client
	tmux set-option -g @livepicker-preview-defer on
	# "xyz" matches NO baseline session (driver/alpha/beta) -> unique target. Created
	# BEFORE activate so it is in @livepicker-list.
	tmux new-session -d -s xyz -x 120 -y 40
	"$LIVEPICKER_SCRIPTS/livepicker.sh"
	local xyz_wid c
	xyz_wid="$(_lp_active_wid xyz)"
	# 3 rapid fires (seq 1,2,3), all targeting xyz (the unique match).
	for c in x y z; do
		"$LIVEPICKER_SCRIPTS/input-handler.sh" type "$c" >/dev/null
	done
	# SYNCHRONOUS: 3 fires happened (SEQ==3) — the burst was not dropped.
	assert_eq "$(tmux show-option -gqv @livepicker-preview-seq)" "3" \
		"rapid typing fired 3 deferred previews (seq bumped per keystroke)"
	# ASYNC: the burst collapsed to ONE link (the latest target; earlier fires no-op'd).
	wait_linked "$xyz_wid" \
		|| fail "rapid typing did not collapse to the final target's preview"
	assert_eq "$(tmux show-option -gqv @livepicker-linked-id)" "$xyz_wid" \
		"burst collapsed to a single trailing preview (no backlog)"
	# Confirm lands on the target independent of the preview (PRD §18 contract #4).
	"$LIVEPICKER_SCRIPTS/input-handler.sh" confirm >/dev/null 2>&1 || true
	assert_eq "$(tmux display-message -p '#{session_name}')" "xyz" \
		"type+Enter lands on the target (confirm never blocks on the preview)"
}

# (c) test_superseded_preview_noop — PRD §18.3: a preview whose target has been
# superseded is a TRUE no-op (never unlinks/links). Two rapid nav fires -> only the
# LATEST target links; the stale fire touches nothing.
test_superseded_preview_noop() {
	attach_test_client
	tmux set-option -g @livepicker-preview-defer on
	"$LIVEPICKER_SCRIPTS/livepicker.sh"
	local alpha_wid beta_wid
	alpha_wid="$(_lp_active_wid alpha)"
	beta_wid="$(_lp_active_wid beta)"
	# Two rapid nav fires: seq=1 -> alpha, seq=2 -> beta. The alpha fire is superseded.
	"$LIVEPICKER_SCRIPTS/input-handler.sh" next-session >/dev/null
	"$LIVEPICKER_SCRIPTS/input-handler.sh" next-session >/dev/null
	# ASYNC: only the LATEST target (beta) links; the alpha fire no-op'd.
	wait_linked "$beta_wid" \
		|| fail "the latest nav target (beta) was not linked"
	assert_eq "$(tmux show-option -gqv @livepicker-linked-id)" "$beta_wid" \
		"only the latest target linked (the stale alpha fire was a no-op)"
	# The stale fire never left a stray link: driver has beta's window, NOT alpha's.
	local drv_wins
	drv_wins="$(tmux list-windows -t "$TEST_DRIVER_SESSION" -F '#{window_id}')"
	assert_contains "$drv_wins" "$beta_wid" "driver holds the latest preview (beta)"
	case "$drv_wins" in
		*"$alpha_wid"*) fail "stale alpha fire leaked a stray link into the driver" ;;
	esac
	# Source undamaged: alpha's window is intact in alpha.
	assert_contains "$(tmux list-windows -t =alpha -F '#{window_id}')" "$alpha_wid" \
		"alpha's window intact in alpha (source undamaged by the stale fire)"
	# Settle: a late stale job must not clobber the newer link.
	sleep 0.2
	assert_eq "$(tmux show-option -gqv @livepicker-linked-id)" "$beta_wid" \
		"latest link stable (a late stale job did not clobber it)"
	"$LIVEPICKER_SCRIPTS/input-handler.sh" cancel >/dev/null 2>&1 || true
}

# (d) test_nav_moves_highlight_before_preview — PRD §18.2: nav moves the highlight
# SYNCHRONOUSLY; the preview re-sync is deferred. The status shows the new highlight
# before the linked window catches up.
test_nav_moves_highlight_before_preview() {
	attach_test_client
	tmux set-option -g @livepicker-preview-defer on
	"$LIVEPICKER_SCRIPTS/livepicker.sh"
	local idx_before
	idx_before="$(tmux show-option -gqv @livepicker-index)"
	"$LIVEPICKER_SCRIPTS/input-handler.sh" next-session >/dev/null
	# SYNCHRONOUS: the highlight moved (index advanced) + the renderer shows it now.
	[ "$(tmux show-option -gqv @livepicker-index)" != "$idx_before" ] \
		|| fail "nav moved the highlight synchronously (index advanced)"
	# Resolve the now-highlighted session from the live list + its window id.
	local cur_idx list filtered sess alpha_wid
	cur_idx="$(tmux show-option -gqv @livepicker-index)"
	list="$(tmux show-option -gqv @livepicker-list)"
	filtered="$(printf '%s' "$list" | grep -i "$(tmux show-option -gqv @livepicker-filter)")"
	sess="$(printf '%s\n' "$filtered" | sed -n "$((cur_idx + 1))p")"
	[ -n "$sess" ] || sess="$(printf '%s\n' "$filtered" | sed -n '1p')"
	# The deferred link still lags at the instant nav returns; then catches up async.
	# (Best-effort lag observation — not asserted hard, since the bg job may have run.)
	local target_wid
	target_wid="$(_lp_active_wid "$sess")"
	wait_linked "$target_wid" \
		|| fail "deferred nav preview never linked the highlighted session ($sess)"
	assert_eq "$(tmux show-option -gqv @livepicker-linked-id)" "$target_wid" \
		"nav preview caught up to the new highlight (async)"
	"$LIVEPICKER_SCRIPTS/input-handler.sh" cancel >/dev/null 2>&1 || true
}

# (e) test_preview_defer_off_synchronous — PRD §18 Control: @livepicker-preview-defer=off
# restores the legacy SYNCHRONOUS-preview path. Typing links inline (no poll) and does
# NOT bump the seq (no bg fire). The contrast that proves (a)-(d) are deferral, not breakage.
test_preview_defer_off_synchronous() {
	attach_test_client
	tmux set-option -g @livepicker-preview-defer off
	"$LIVEPICKER_SCRIPTS/livepicker.sh"
	assert_eq "$(tmux show-option -gqv @livepicker-linked-id)" "" \
		"initial self-session preview leaves no link"
	"$LIVEPICKER_SCRIPTS/input-handler.sh" type a >/dev/null
	# Resolve the top match for "a" dynamically.
	local top_sess top_wid
	top_sess="$(printf '%s' "$(tmux show-option -gqv @livepicker-list)" | grep -i 'a' | head -1)"
	top_wid="$(_lp_active_wid "$top_sess")"
	# SYNCHRONOUS (NO poll): defer=off ran preview.sh inline before returning.
	assert_eq "$(tmux show-option -gqv @livepicker-linked-id)" "$top_wid" \
		"defer=off links the preview SYNCHRONOUSLY (legacy path restored)"
	# defer=off does NOT fire a background job -> seq stays at its init (0/unbumped).
	local seq
	seq="$(tmux show-option -gqv @livepicker-preview-seq)"
	[ -z "$seq" ] || [ "$seq" = "0" ] \
		|| fail "defer=off did not fire a background preview (seq stayed 0, got [$seq])"
	"$LIVEPICKER_SCRIPTS/input-handler.sh" cancel >/dev/null 2>&1 || true
}
```

NOTE for the implementer: the block above is the COMPLETE file. The two subtle bits:
- **(a)/(d) top-match resolution**: filter `"a"` matches both `alpha` and `beta`, so the
  expected linked target is resolved DYNAMICALLY from the live filtered list (never
  hardcoded). The `grep -i 'a' | head -1` derives the top match the same way the
  renderer/nav do (sorted list, first match). If the dynamic resolution is fragile on a
  given fixture set, add a uniquely-matching session before activate (e.g.
  `tmux new-session -d -s aaa`) and type a filter that matches only it — but the dynamic
  form is correct as written against the baseline driver/alpha/beta.
- **(a) immediate linked-id-still-`""`**: this is the "lag" observation. It is reliable
  (bg job startup ≫ read time) but is the one timing-sensitive assertion; it is BACKED by
  the deterministic SEQ-bumped + renderer-query + eventual-poll assertions, so the test
  proves deferral even if a freakishly fast box ever beats this single read.

### Integration Points

```yaml
TEST DISCOVERY:
  - file: tests/test_responsiveness.sh
    change: "NEW. 5 test_* functions + wait_linked/_lp_active_wid helpers."
    discovery: "auto via run.sh `compgen -A function | grep '^test_'` (sourced by the
               nullglob `source test_*.sh` loop). No registration needed."

HARNESS DEPENDENCIES (consumed — all UNCHANGED, all in scope via run.sh):
  - tests/setup_socket.sh: attach_test_client, baseline fixtures (driver/alpha/beta),
    $TEST_DRIVER_SESSION, $LIVEPICKER_SCRIPTS, bare tmux -> isolated socket.
  - tests/helpers.sh: fail/pass/assert_eq/assert_contains; setup_test (pins defer=off;
    this file overrides per test); teardown_test (auto-cleanup).
  - tests/run.sh: sources this file; per-test setup_test/teardown_test; PASS/FAIL + exit.

PROD DEPENDENCIES (consumed — all LANDED, UNCHANGED by this task):
  - scripts/input-handler.sh: _lp_fire_preview / _lp_preview_follow / _lp_sync_preview_to_top_match
    + the type/backspace/next/prev/cancel call sites. type/next/backspace drive the dispatcher.
  - scripts/preview.sh: the expected_seq supersede guard (exercised by (c)).
  - scripts/state.sh: STATE_PREVIEW_SEQ / STATE_PREVIEW_TARGET / STATE_LINKED_ID.
  - scripts/options.sh: opt_preview_defer (default on; this file sets it explicitly).
  - scripts/renderer.sh: run directly to assert the synchronous status output.
  - scripts/livepicker.sh: activate (first preview = self-session, synchronous).

CODE / DATABASE / CONFIG / ROUTES: none (test-only; no production code change).
```

## Validation Loop

### Level 1: Syntax & Style (Immediate Feedback)

```bash
cd /home/dustin/.config/tmux/plugins/tmux-livepicker
bash -n tests/test_responsiveness.sh && echo "OK: syntax"
shellcheck tests/test_responsiveness.sh
# Tabs-not-spaces (shfmt NOT installed):
grep -nP '^ +' tests/test_responsiveness.sh && echo "WARN: space-indent (use tabs)" || echo "OK: tabs"
# Exactly 5 discovered tests + 2 non-test helpers (wait_linked, _lp_active_wid):
grep -c '^test_' tests/test_responsiveness.sh          # -> 5
grep -c '^wait_linked()\|^_lp_active_wid()' tests/test_responsiveness.sh  # -> 2
# Expected: syntax clean; shellcheck 0 NEW findings (disable line mirrors test_functional.sh);
# 5 test_* functions; helpers are NOT test_-prefixed (so compgen won't run them).
```

### Level 2: Full suite (the committed validation)

```bash
cd /home/dustin/.config/tmux/plugins/tmux-livepicker
bash tests/run.sh
# Expected: exit 0. The 5 new tests print PASS:
#   test_nav_moves_highlight_before_preview
#   test_preview_defer_off_synchronous
#   test_rapid_type_confirm_no_backlog
#   test_superseded_preview_noop
#   test_typing_defers_preview
# AND the existing suite stays green (it runs defer=OFF via the setup_test pin, unaffected).
# Takes ~2-3 min. If a NEW test FAILS on an @livepicker-linked-id poll, the bg job is not
# firing (re-check _lp_fire_preview + STATE_PREVIEW_SEQ) or preview.sh's guard rejected
# the seq (re-check the $2 plumbing). If an EXISTING test fails, the setup_test pin broke.
```

### Level 3: Non-flakiness proof (run the new tests repeatedly)

```bash
cd /home/dustin/.config/tmux/plugins/tmux-livepicker
# Run the suite 3× in a row; the 5 responsiveness tests must PASS every time (the
# wait_linked poll + sync assertions make them timing-robust). A flake indicates a
# timing assumption that needs the poll timeout raised or a sync assertion relaxed.
for n in 1 2 3; do
  bash tests/run.sh 2>&1 | grep -E 'test_(typing_defers|rapid_type_confirm|superseded_preview|nav_moves_highlight|preview_defer_off)'
  echo "--- run $n done ---"
done
# Expected: 5 PASS lines per run, 3 runs. Zero FAILs. (Each run is a fresh set of isolated
# sockets; lp_sweep_orphans cleans up.)
```

### Level 4: Bug-reintroduction spot-check (the tests actually guard §18)

```bash
cd /home/dustin/.config/tmux/plugins/tmux-livepicker
# (Optional, defense-in-depth) Temporarily break the producer and confirm a test FAILS:
#   e.g. make _lp_fire_preview NOT bump the seq -> test_typing_defers_preview's
#   "SEQ bumped" assertion FAILS. Restore. (Mirror the P1.M2.T3.S1 L3 pattern.)
# This proves the tests are not vacuous. Not required for green; just a confidence check.
```

## Final Validation Checklist

### Technical Validation

- [ ] `bash -n tests/test_responsiveness.sh` clean.
- [ ] `shellcheck tests/test_responsiveness.sh`: 0 new findings (disable line present).
- [ ] L1 grep: 5 `test_*` functions; `wait_linked` + `_lp_active_wid` present (non-`test_`).
- [ ] Tabs only (no space-indent).

### Feature Validation

- [ ] (a) typing: SEQ bumped + renderer shows query + linked-id lags IMMEDIATELY; poll links.
- [ ] (b) 3 rapid types: SEQ==3; poll collapses to one link; confirm lands on target.
- [ ] (c) 2 rapid navs: only latest target links; no stray link; source intact; stable on settle.
- [ ] (d) nav: index advanced + renderer highlights IMMEDIATELY; poll links.
- [ ] (e) defer=off: linked-id set SYNCHRONOUSLY (no poll); SEQ unbumped.
- [ ] Every test sets `@livepicker-preview-defer` explicitly + calls `attach_test_client`.
- [ ] `bash tests/run.sh` exit 0; 5 new tests PASS; existing suite green.
- [ ] Non-flaky: 3 consecutive runs all green (Level 3).

### Code Quality Validation

- [ ] Mirrors test_functional.sh structure (header contract block; attach→activate→drive→assert).
- [ ] Failure signaled ONLY via `fail`/`assert_*` + inline `case`+`fail`; NO `exit`/`return`-nonzero.
- [ ] Window ids captured DYNAMICALLY (`_lp_active_wid`); none hardcoded.
- [ ] Helpers prefixed `wait_linked`/`_lp_active_wid` (NOT `test_` → not auto-run).
- [ ] TAB indent; `set -u` inherited; all locals declared.
- [ ] File sources nothing; no `setup_test`/`teardown_test` at file scope.

### Documentation & Deployment

- [ ] Header documents: the run.sh sourcing contract, the defer opt-in (overriding the pin),
      the async-timing model (sync seq/renderer/index vs polled link), and attach_test_client
      being mandatory.
- [ ] No README/CHANGELOG edit (test file; the §18 option row is synced by the Mode-B docs
      task P1.M3.T3.S1).
- [ ] No production code change; no other test file touched.

---

## Anti-Patterns to Avoid

- ❌ Don't assert the async link WITHOUT a poll — `run-shell -b` is non-blocking; the link
  lags the input handler's return by ~30-60ms. A bare `assert_eq linked-id target` right
  after `type`/`next` is a flaky sleep-race. Use `wait_linked target || fail` (research §2).
- ❌ Don't set `@livepicker-preview-defer` only once at file scope — `setup_test` re-pins it
  OFF per test. Each test must set it explicitly (on for a–d, off for e) after `attach_test_client`.
- ❌ Don't skip `attach_test_client` — `refresh-client -S` is a no-op on a client-less socket
  (Q7), and `confirm`/`display-message -p` need a client. Every test attaches first.
- ❌ Don't `exit` or `return`-nonzero from a test body to fail — it kills `run.sh`. Use
  `fail`/`assert_*` (set `TEST_STATUS`). Early `return 0` to skip is fine.
- ❌ Don't hardcode window ids — they are global but `renumber-windows=on` makes them
  machine/session-specific. Capture dynamically via `_lp_active_wid <sess>`.
- ❌ Don't hardcode the "top match for a filter" — filter "a" matches alpha AND beta; resolve
  the expected target dynamically from the live filtered list (`grep -i … | head -1`) so the
  test is correct regardless of list order. (Or add a uniquely-matching session before activate.)
- ❌ Don't name a helper `test_*` — `run.sh`'s `compgen | grep '^test_'` will try to RUN it.
  Use `lp_*` or any non-`test_` prefix (`wait_linked`, `_lp_active_wid`).
- ❌ Don't copy test_functional.sh's SYNCHRONOUS `linked-id` timing — that file runs defer=OFF
  (via the pin) and asserts immediately. This file runs defer=ON; the link is async and MUST
  be polled (except (e), which is the explicit defer=off contrast).
- ❌ Don't rely on a `sleep` alone to observe the lag — a sleep-only "linked-id still old"
  check is a race. The deterministic lag proof is: SEQ bumped (sync) + renderer current
  (sync) + immediate linked-id-still-old (reliable: bg startup ≫ read) + eventual poll.
- ❌ Don't add a `setup_test`/`teardown_test` call at file scope — run.sh owns the per-test
  cycle; adding one would double-setup and leak sockets. (Internal `setup_test` inside a test
  body is allowed by precedent but NOT needed here — the baseline fixtures + per-test defer
  set are sufficient.)
- ❌ Don't edit any production script or any other test file — this is test-only. All §18 deps
  are landed; if a test reveals a prod bug, surface it to the orchestrator (do NOT fix prod here).
- ❌ Don't use spaces for indent — TABS only (match test_functional.sh; shfmt absent).

---

## Confidence Score

**9 / 10** for one-pass success. Rationale: every dependency is **grep-confirmed landed**
(`_lp_fire_preview`/`_lp_preview_follow` in input-handler.sh; preview.sh's `expected_seq`
guard; `STATE_PREVIEW_SEQ`/`STATE_PREVIEW_TARGET` + `_STATE_RUNTIME_KEYS`; `opt_preview_defer`;
the `setup_test` defer=off pin). The async-timing model (research §2) is the load-bearing
insight: SEQ/filter/index/renderer are SYNCHRONOUS (asserted immediately, deterministically),
and the link is ASYNC (polled via `wait_linked`, 2s timeout; healthy <50ms) — this split makes
every "deferral" assertion non-flaky. The test file mirrors test_functional.sh's proven
structure (header → attach → activate → drive → assert; dynamic window-id capture;
`fail`/`assert_*` + inline `case`), and the two throwaway smokes in P1.M2.T3.S1 already
PROVED the `wait_linked` poll pattern works end-to-end on this exact harness. The 5 tests
map 1:1 to the contract's §3 a–e, each with a deterministic sync core + a polled async link +
(except (e)) a defer=on opt-in. Residual risks: (a) the dynamic top-match resolution in (a)/(d)
relies on `grep -i … | head -1` matching the renderer/nav's ordering — mitigated by resolving
from the same sorted list and by the option to add a uniquely-matching fixture; (b) the single
immediate "linked-id-still-old" read in (a) is timing-sensitive — mitigated by being backed
by the deterministic SEQ/renderer/poll assertions (the test proves deferral regardless). The
1-point deduction is for these two timing/ordering sensitivities, both deterministically
guarded by the surrounding assertions, not for any missing context.
