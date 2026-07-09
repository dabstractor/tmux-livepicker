## Goal

**Feature Goal**: Create `tests/test_session_mgmt.sh` — a socket-isolated integration suite that drives the COMPLETE real `scripts/session-mgmt.sh` (P2.M1.T2, the rename + delete implementation) DIRECTLY against the existing harness and asserts the observable tmux state for all eight PRD §21 + §15.28 management behaviours: rename, sanitized-name abort, collision abort, delete (list rewrite + neighbour highlight + re-sync), driver-guard, last-session-guard, the kill-session/linked-preview leak, and confirm-delete.

**Deliverable**: A single new file `tests/test_session_mgmt.sh` (sourced by `tests/run.sh`, defining `test_*` functions). It is auto-discovered by `run.sh`'s `compgen -A function | grep '^test_'` — no registration edits required. It covers every §15.28 management item.

**Success Definition**: `bash tests/run.sh` passes with the new suite included (PASS on every `test_session_mgmt_*` function, no regressions in the existing suite), the real user tmux server is byte-identical before/after (PRD §15 pollution invariant), and every one of the eight contract behaviours (a)–(h) is asserted on deterministic tmux state.

## Why

- `scripts/session-mgmt.sh` shipped in P2.M1.T2 with NO automated coverage. Rename/delete mutate live sessions (`rename-session`, `kill-session`) and the picker's `@livepicker-list`; the leak/​unlink-first path (§16 risk) is the single most dangerous bug class — a regression there permanently orphans a window in the driver. This suite locks all of that in.
- It completes P2.M2 (Validation) and unblocks P2 closure (the plan's only remaining "Researching" leaf under P2).
- It is the regression guard referenced by PRD §15.28 "Layout, ranking, scroll, and management" (the `!heading:h2[15]/heading:h3[28]` selector maps here).

## What

A sourced test module defining one `test_*` function per contract behaviour. Each runs against a FRESH isolated `-L` socket provided by `setup_test` (per-test cycle in `run.sh`), pins the deterministic synchronous preview path (`setup_test` already sets `@livepicker-preview-defer off`), seeds the minimal `@livepicker-*` state `session-mgmt.sh` reads, invokes the real script action, and asserts observable tmux state via `fail/assert_eq/assert_contains`.

**The governing pattern (from the item's RESEARCH NOTE)**: `command-prompt`/`confirm-before` are interactive; under the harness we test the **submit handlers directly** — `$LIVEPICKER_SCRIPTS/session-mgmt.sh do-rename <NEW>` and `... do-delete <S>` with seeded state. This is the established "test the prompt-submit handler" idiom (mirrors how `test_create.sh` drives `input-handler.sh confirm`). The interactive `confirm-before` path additionally gets one send-keys exercise (E6) because it needs an attached client.

### Success Criteria

- [ ] (a) `do-rename <valid>` rewrites `@livepicker-list` (old name → new), leaves `@livepicker-index` unchanged (highlight preserved), `@livepicker-mode` still `on`, the renamed session exists under the new name and is gone under the old.
- [ ] (b) `do-rename` with `:` anywhere or a leading `.` aborts: list unchanged, original session still exists, NO session created under a sanitized variant.
- [ ] (c) `do-rename` to an existing session name aborts: list unchanged, original unchanged.
- [ ] (d) `do-delete <S>` (non-driver, list ≥3): session gone from `list-sessions`, dropped from `@livepicker-list`, `@livepicker-index` clamped to a valid neighbour, the new highlight's window re-linked as the preview (`@livepicker-linked-id`).
- [ ] (e) `delete` on `ORIG_SESSION` is refused: driver still alive, list unchanged.
- [ ] (f) `delete` when `@livepicker-list` has length 1 is refused: the lone session still alive.
- [ ] (g) Leak: after `preview.sh victim` links victim's window into the driver, `do-delete victim` leaves NO orphan window in the driver; AND a control (raw `kill-session` without unlink) IS shown to leak, proving the test reproduces the bug.
- [ ] (h) `@livepicker-confirm-delete on` → `delete` opens `confirm-before` (victim survives until confirmed); the `'y'` send-keys drive confirms the kill; contrast `confirm-delete off` kills immediately.
- [ ] Real tmux server (`/usr/bin/tmux`) byte-identical before/after the whole suite.

## All Needed Context

### Context Completeness Check

"If someone knew nothing about this codebase, would they have everything needed to implement this successfully?" — Yes. The PRP pins the exact harness contract (sourced module, per-test `setup_test`, in-scope symbols), the exact state keys the script reads, the exact invocation + read-back commands (empirically verified below), and the exact reference test to copy structure from. No guessing.

### Documentation & References

```yaml
# MUST READ — load these into the context window before writing any test.

- file: scripts/session-mgmt.sh
  why: The implementation under test. Defines the 4 actions (rename / do-rename
        NEW / delete / do-delete S) and `_lp_resolve_highlighted()`.
  pattern: "do-rename/do-delete are CLIENT-INDEPENDENT (refresh-client -S is
        guarded || true). rename pre-detects ':' and leading '.' BEFORE renaming
        and aborts; rename-session rc!=0 => collision abort. do-delete
        unlinks-window the linked preview FIRST (when it belongs to S), then
        kill-session, then rewrites list + clamps index + re-ranks + re-syncs
        preview via preview.sh <new_target>."
  gotcha: "session-mgmt.sh NEVER reads @livepicker-mode — the 'picker stays
        active' assertion holds simply because do-rename/do-delete do not call
        restore. _lp_resolve_highlighted re-ranks via lp_rank and CLAMPS the
        stored index, so seed a list+index that resolve to the intended target."

- file: tests/test_preview.sh
  why: THE reference for the seed-state + preview-link lifecycle idiom. Copy
        lp_preview_seed_state() structure; copy the 'link victim then assert
        before/after' shape for the leak test.
  pattern: "lp_preview_seed_state sets @livepicker-orig-session/orig-window/
        linked-id(\"\"), reads the driver's ACTIVE window id dynamically via
        `tmux list-windows -t \"=$TEST_DRIVER_SESSION\" -F '#{window_id}' -f
        '#{window_active}'`. preview.sh is CLIENT-INDEPENDENT (no
        attach_test_client)."
  gotcha: "Window ids (@N) are GLOBAL — read them DYNAMICALLY, never hardcode."

- file: tests/test_create.sh
  why: THE reference for attach_test_client + the 'test the submit handler
        directly with seeded state' idiom and the '@livepicker-mode torn down'
        assertion style.
  pattern: "attach_test_client FIRST when a client is needed (confirm-before,
        E6). set @livepicker-* options via set-option -g BEFORE invoking the
        script. signal failure ONLY via fail/assert_* (never exit)."

- file: tests/test_functional.sh
  why: THE reference for the full header/contract comment block + the
        lp_runtime_cleared() helper (read but not required here) + how a test
        module documents its SOURCED-by-run.sh contract.
  pattern: "Copy the top-of-file contract comment. set -u is INHERITED from
        helpers.sh — do NOT re-declare. This file SOURCES NOTHING and calls NO
        setup_test/teardown_test."

- file: tests/helpers.sh
  why: Defines the assertion API + setup_test/teardown_test contract.
  pattern: "fail(msg)->sets TEST_STATUS=fail (never exits); pass(msg); 
        assert_eq a b msg; assert_contains str sub msg (literal substring via
        case). setup_test[s] => setup_socket[s] (fresh -L socket + PATH shim +
        baseline driver/alpha/beta, pins @livepicker-preview-defer off)."

- file: tests/setup_socket.sh
  why: The isolation layer + attach_test_client. Confirms bare `tmux` inside
        test bodies + inside the plugin scripts hits the isolated socket.
  pattern: "attach_test_client [session] => `script -qec \"tmux attach -t
        '$sess'\" /dev/null >/dev/null 2>&1 &` then sleep 0.5; sets
        TEST_CLIENT_PID. Baseline: driver/alpha/beta; driver has 2 windows
        (orig + 'extra' w/ panes); beta has a split."

- file: tests/run.sh
  why: Discovery + per-test lifecycle. Confirms auto-discovery (no edit needed).
  pattern: "Sources every tests/test_*.sh; per test: setup_test lp-$$-<name>
        => TEST_STATUS=pass => run test_* in CURRENT shell => read
        TEST_STATUS => teardown_test. Socket name is per-test unique."

- file: scripts/state.sh
  why: The exact @livepicker-* key NAMES session-mgmt.sh reads.
  pattern: "@livepicker-list @livepicker-filter @livepicker-index
        @livepicker-linked-id @livepicker-orig-session @livepicker-orig-window
        @livepicker-mode (STATE_MODE). All are set via `tmux set-option -g`."

- file: scripts/options.sh
  why: opt_type()/opt_confirm_delete() defaults.
  pattern: "opt_type defaults 'session' (set @livepicker-type window ONLY if you
        ever test window mode — out of scope here). opt_confirm_delete defaults
        'off'; set @livepicker-confirm-delete on for the confirm test."

- docfile: plan/003_77ef311abf10/architecture/codebase_patterns.md
  why: §P8 (Test harness) + §P9 (set -u safety + escaping) — house rules.
  section: "P8 (attach_test_client, assert helpers, renderer-no-client seed
        idiom) and P9 (command-prompt %% / sanitized-name caveat)."

- docfile: plan/003_77ef311abf10/architecture/empirical_findings.md
  why: Finding 3 = EXP D: the leak is REAL. A window linked into the driver
        SURVIVES kill-session of its source unless unlinked first.
  section: "Finding 3 (EXP D) — load-bearing for the leak test design."

- docfile: plan/003_77ef311abf10/P2M2T1S1/research/session_mgmt_test_findings.md
  why: The empirically-verified command sequences (E1–E6) this PRP is built on.
        Every assertion in this PRP was run on an isolated socket; the real
        server was verified byte-identical before/after.
```

### Current Codebase tree (relevant slice)

```bash
tests/
  run.sh                 # entry point; sources every test_*.sh, per-test setup_test
  setup_socket.sh        # isolation shim + attach_test_client
  helpers.sh             # fail/pass/assert_eq/assert_contains + setup_test/teardown_test
  test_preview.sh        # <-- COPY: seed-state + preview link/unlink lifecycle idiom
  test_create.sh         # <-- COPY: attach_test_client + 'test submit handler directly'
  test_functional.sh     # <-- COPY: header/contract comment block + module style
  test_session_mgmt.sh   # <-- CREATE (this work item)
scripts/
  session-mgmt.sh        # implementation under test (rename/do-rename/delete/do-delete)
  preview.sh             # client-independent preview link (used by the leak test setup)
  state.sh options.sh rank.sh utils.sh   # sourced by session-mgmt.sh
```

### Desired Codebase tree (file added by this work item)

```bash
tests/test_session_mgmt.sh   # NEW. Sourced by run.sh; defines ~8 test_* functions.
```

### Known Gotchas of our codebase & tmux Quirks

```bash
# CRITICAL: never invoke the script through `tmux run-shell` WITHOUT the PATH
# shim in a standalone probe — the bare `tmux` inside session-mgmt.sh would hit
# the WRONG socket. INSIDE the harness this is solved: setup_socket prepends a
# `tmux` shim dir to PATH so bare `tmux` => `/usr/bin/tmux -L "$TEST_SOCKET"`.
# All assertions below assume you are inside a test_* body (shim is active).

# CRITICAL: abort messages (display-message) are NOT observable without an
# attached client. For (b)/(c)/(e)/(f) assert on tmux STATE (list unchanged,
# session still exists / still dead), NOT on message text.

# CRITICAL: do-rename/do-delete are CLIENT-INDEPENDENT. Only the confirm-before
# test (h) and the optional send-keys drive of (h) need attach_test_client.

# CRITICAL: window ids (@N) are GLOBAL and assigned at creation; ALWAYS read
# them dynamically via list-windows -F '#{window_id}' -f '#{window_active}'.
# Never hardcode @1/@2 — renumber-windows and creation order shift them.

# CRITICAL: the leak test MUST include a CONTROL (raw kill-session, no unlink)
# that reproduces the orphan. Without it, the 'gone' assertion is vacuous — it
# could pass because the link never happened. EXP D (empirical_findings.md F3)
# proves raw kill-session leaves the window SURVIVING in the driver.

# CRITICAL: set -u is INHERITED from helpers.sh. Every tmux show-option read
# must tolerate empty: use `tmux show-option -gqv "<key>"` (empty string, not
# unset, under set -u). seed values with `tmux set-option -g`.

# CRITICAL: signal failure ONLY via fail()/assert_*() (they set TEST_STATUS).
# NEVER call exit, NEVER return-nonzero-to-abort — run.sh reads TEST_STATUS in
# the CURRENT shell; a bare exit kills the whole runner.

# QUIRK: setup_test pins @livepicker-preview-defer off so do-delete's
# synchronous `preview.sh <new_target>` re-sync is deterministic (the
# @livepicker-linked-id assertion lands immediately). Do NOT flip it on here.

# QUIRK: after do-delete, @livepicker-linked-id is NOT cleared — it is
# OVERWRITTEN by preview.sh's re-link to the new highlight's window. Assert it
# equals the new highlight's window id (or just assert the victim's id is gone).
```

## Implementation Blueprint

### Test "data models" (shared seed helper)

There is no ORM/pydantic here; the "data model" is the `@livepicker-*` state seed. Define ONE shared helper that seeds exactly the keys `session-mgmt.sh` reads (mirror `tests/test_preview.sh:lp_preview_seed_state`):

```bash
# lp_mgmt_seed_state <highlight_index> [list_lines...]
# Seeds the minimal state session-mgmt.sh reads: list, filter="", index,
# orig-session=driver, orig-window=driver's ACTIVE window id, linked-id="",
# mode=on. $1 = 0-based highlight index over the list given by remaining args
# (defaults to alpha beta gamma). Caller ensures those sessions EXIST
# (bare `tmux new-session -d -s <name>`). Window ids are dynamic => read here.
lp_mgmt_seed_state() {
	local _idx="${1:-0}"; shift
	local _drv_win
	_drv_win="$(tmux list-windows -t "=$TEST_DRIVER_SESSION" -F '#{window_id}' -f '#{window_active}')"
	tmux set-option -g @livepicker-orig-session "$TEST_DRIVER_SESSION"
	tmux set-option -g @livepicker-orig-window "$_drv_win"
	tmux set-option -g @livepicker-list "$(printf '%s\n' "$@")"
	tmux set-option -g @livepicker-filter ""
	tmux set-option -g @livepicker-index "$_idx"
	tmux set-option -g @livepicker-mode "on"
	tmux set-option -g @livepicker-linked-id ""
	tmux set-option -g @livepicker-confirm-delete off   # default; tests flip on
}
```

### Implementation Tasks (ordered by dependencies)

```yaml
Task 0: STUDY the references (no edit)
  - READ scripts/session-mgmt.sh end-to-end (the 4 actions + _lp_resolve_highlighted).
  - READ tests/test_preview.sh (lp_preview_seed_state + link/unlink lifecycle).
  - READ tests/test_create.sh (attach_test_client + 'test submit handler directly').
  - READ tests/test_functional.sh (header/contract comment block to mirror).
  - READ plan/003_77ef311abf10/P2M2T1S1/research/session_mgmt_test_findings.md
        (verified E1-E6 commands).

Task 1: CREATE tests/test_session_mgmt.sh — scaffold + header + seed helper
  - WRITE the SOURCED-by-run.sh contract header comment (mirror
        test_functional.sh: 'SOURCED by run.sh (NEVER executed directly). Defines
        test_* functions... CONTRACT: run.sh sources setup_socket.sh + helpers.sh
        + every tests/test_*.sh, then PER test calls setup_test ...'). Document
        that bare `tmux` hits the isolated socket; $LIVEPICKER_SCRIPTS,
        TEST_DRIVER_SESSION, attach_test_client, fail/pass/assert_* are in scope;
        this file SOURCES NOTHING and calls NO setup_test/teardown_test; set -u
        is INHERITED.
  - NAMING: `tests/test_session_mgmt.sh`.
  - PLACEMENT: tests/ (auto-discovered by run.sh — no registration edit).
  - DEFINE `lp_mgmt_seed_state` (the helper above).
  - shellcheck-disable the standard SC2154/SC2016/SC2034/SC2086 (in-scope symbols
        defined by run.sh's sources), mirroring the other test files.

Task 2: test_rename_updates_list_preserves_highlight  [contract (a)]
  - Seed sessions: ensure alpha/beta/gamma EXIST (baseline gives driver/alpha/
        beta; `tmux new-session -d -s gamma -x 120 -y 40`).
  - lp_mgmt_seed_state 1 alpha beta gamma   # highlight index 1 => beta
  - RUN: "$LIVEPICKER_SCRIPTS/session-mgmt.sh" do-rename delta
  - ASSERT:
      assert_eq "$(tmux show-option -gqv @livepicker-index)" "1" "highlight preserved"
      assert_contains "$(tmux show-option -gqv @livepicker-list)" "delta" "list has the new name"
      case "$(tmux show-option -gqv @livepicker-list)" in *"beta"*) fail "...beta still in list";; esac
      `tmux has-session -t =delta` (rc) => pass/fail "delta created"
      ! `tmux has-session -t =beta` => "beta gone"
      assert_eq "$(tmux show-option -gqv @livepicker-mode)" "on" "picker still active"
  - NO attach_test_client (do-rename is client-independent).

Task 3: test_rename_sanitized_aborts  [contract (b)] — TWO cases
  - (b1 colon) lp_mgmt_seed_state 1 alpha beta gamma; do-rename 'be:ta'
      => assert list UNCHANGED (== "alpha beta gamma"), beta still exists, NO
         be_ta / be:ta session (has-session both).
  - (b2 leading dot) fresh-ish: do-rename '.dot'
      => assert list unchanged, beta exists, NO .dot / _dot session.
  - Assert on STATE only (display-message not observable without a client).
  - NO attach_test_client.

Task 4: test_rename_collision_aborts  [contract (c)]
  - lp_mgmt_seed_state 1 alpha beta gamma; do-rename alpha   # alpha exists
      => assert list unchanged, beta still exists, alpha unchanged (==1 alpha).
  - NO attach_test_client.

Task 5: test_delete_rewrites_list_and_highlights_neighbour  [contract (d)]
  - Seed alpha/beta/gamma; lp_mgmt_seed_state 1 alpha beta gamma  # highlight beta
  - RUN: "$LIVEPICKER_SCRIPTS/session-mgmt.sh" do-delete beta
  - ASSERT:
      ! has-session =beta => "beta killed"
      list == "alpha gamma" (line compare; assert_eq on `tr '\n' ','` form)
      assert_eq index "1"  # clamped to the valid neighbour (gamma now idx 1)
      linked-id != "" AND == the new highlight (gamma) window id:
        gamma_wid="$(tmux list-windows -t '=gamma' -F '#{window_id}' -f '#{window_active}')"
        assert_eq "$(tmux show-option -gqv @livepicker-linked-id)" "$gamma_wid" "preview re-synced to neighbour"
  - NO attach_test_client.

Task 6: test_delete_refuses_driver  [contract (e)]
  - Seed driver/alpha/victim; lp_mgmt_seed_state 0 driver alpha victim
        # index 0 => highlight driver; orig-session=driver => guard A fires
  - RUN: "$LIVEPICKER_SCRIPTS/session-mgmt.sh" delete   # the GUARD entry action
  - ASSERT: has-session =driver (still alive); list UNCHANGED.
  - NO attach_test_client.

Task 7: test_delete_refuses_last_session  [contract (f)]
  - Reduce to ONE non-driver session: kill alpha/beta/gamma extras, leave e.g.
        `lonely` + driver. lp_mgmt_seed_state 0 lonely   # list length 1
  - RUN: "$LIVEPICKER_SCRIPTS/session-mgmt.sh" delete
  - ASSERT: has-session =lonely (still alive); list UNCHANGED.
  - NO attach_test_client.

Task 8: test_delete_unlinks_preview_no_orphan  [contract (g)] — the leak test
  - Seed list victim other; lp_mgmt_seed_state 0 victim other  # highlight victim
  - LINK the victim's window into the driver AS preview does:
        "$LIVEPICKER_SCRIPTS/preview.sh" victim
        vid="$(tmux show-option -gqv @livepicker-linked-id)"
  - SANITY (proves the link happened — guards against a vacuous pass):
        assert list-windows -t '=driver' CONTAINS $vid  (assert_contains)
  - FIX PATH:
        "$LIVEPICKER_SCRIPTS/session-mgmt.sh" do-delete victim
        assert ! (list-windows -t '=driver' contains $vid)  => "no orphan"
        assert ! has-session =victim
  - CONTROL (separate test_* OR a second phase on a fresh socket): reproduce the
        leak so the FIX assertion is meaningful:
        fresh setup, preview.sh victim, vid2=linked-id,
        `tmux kill-session -t '=victim'` DIRECTLY (NO do-delete / NO unlink),
        assert list-windows -t '=driver' STILL CONTAINS vid2 => "leak reproduced"
        (then `tmux unlink-window -t "=$TEST_DRIVER_SESSION:$vid2"` to clean up,
         or just teardown — the per-test teardown kills the whole server).
  - PREFER splitting into TWO test_* functions (test_delete_unlinks_preview_no_orphan
        + test_raw_kill_leaks_orphan) so each gets a pristine per-test socket from
        run.sh (cleaner than re-seeding mid-body). preview.sh is client-independent
        => NO attach_test_client.

Task 9: test_confirm_delete_gates_kill  [contract (h)] — needs a client
  - attach_test_client
  - Seed victim + other; lp_mgmt_seed_state 0 victim other
  - `tmux set-option -g @livepicker-confirm-delete on`
  - RUN: "$LIVEPICKER_SCRIPTS/session-mgmt.sh" delete   # opens confirm-before, returns
  - ASSERT (deterministic backbone): has-session =victim STILL ALIVE
        => "confirm-before intercepted (no kill without confirmation)"
  - DRIVE the prompt (full exercise):
        tmux send-keys -t "=$TEST_DRIVER_SESSION" "y" Enter
        sleep 0.7   # do-delete runs via run-shell
        assert ! has-session =victim => "confirm-before -> do-delete killed on y"
  - CONTRAST control (same test, or a sibling test_*):
        `tmux set-option -g @livepicker-confirm-delete off`; recreate victim;
        re-seed; `delete`; assert ! has-session => "immediate kill when off"
  - GOTCHA: confirm-before needs the attached client to display; send-keys
        targets the session (-t =driver). If the send-keys timing proves flaky
        in CI, KEEP the deterministic 'survives until confirmed' + 'off => kills'
        assertions (they alone prove the gate) and drop the 'y' drive. Do NOT
        remove the deterministic backbone to chase the interactive step.
```

### Implementation Patterns & Key Details

```bash
# PATTERN: read a window id DYNAMICALLY (never hardcode @N).
drv_win="$(tmux list-windows -t "=$TEST_DRIVER_SESSION" -F '#{window_id}' -f '#{window_active}')"

# PATTERN: seed the newline-joined list exactly as activate captures it.
tmux set-option -g @livepicker-list "$(printf '%s\n' alpha beta gamma)"

# PATTERN: assert on the list as a normalized comma-join (avoids newline ambiguity).
list_form() { tmux show-option -gqv @livepicker-list | tr '\n' ','; }
assert_eq "$(list_form)" "alpha,beta,gamma," "list unchanged"

# PATTERN: has-session rc is the predicate (do not echo raw rc under set -u).
if tmux has-session -t "=beta" 2>/dev/null; then fail "beta still exists"; else pass "beta killed"; fi

# PATTERN: literal 'is $vid present in driver window list' (no glob surprises).
case "$(tmux list-windows -t "=$TEST_DRIVER_SESSION" -F '#{window_id}')" in
	*"$vid"*) fail "victim window leaked into the driver" ;;
esac

# GOTCHA (rename highlight): lp_rank with an empty filter preserves list order,
# so index 1 over [alpha,beta,gamma] resolves to beta. Confirm by reading
# _lp_resolve_highlighted's clamp (it clamps idx into range; an out-of-range
# seed index resolves to the LAST item, not the intended one — seed correctly).

# GOTCHA (delete re-sync): do-delete calls preview.sh <new_target> which
# OVERWRITES @livepicker-linked-id with the new highlight's window. Do NOT assert
# linked-id is "" after delete; assert it equals the neighbour's window id (Task 5).
```

### Integration Points

```yaml
DISCOVERY:
  - none: run.sh auto-sources tests/test_*.sh and auto-discovers test_* funcs.
        Creating the file at tests/test_session_mgmt.sh is sufficient.

CONFIG (per-test, via set-option -g inside test bodies):
  - "@livepicker-preview-defer off"  # already pinned by setup_test — leave it.
  - "@livepicker-confirm-delete off" # default in lp_mgmt_seed_state; flip on for (h).

STATE (the seed contract session-mgmt.sh reads):
  - "@livepicker-list" "@livepicker-filter" "@livepicker-index"
  - "@livepicker-orig-session" "@livepicker-orig-window" "@livepicker-linked-id"
  - "@livepicker-mode"

ROUTES: none (no plugin/source edits — this is a test-only work item).
```

## Validation Loop

### Level 1: Syntax & Style (Immediate Feedback)

```bash
# bash syntax check the new file (fast; no tmux needed).
bash -n tests/test_session_mgmt.sh && echo "syntax ok"

# shellcheck (the repo's other test files carry SC2154/SC2016/SC2034/SC2086
# disables for in-scope symbols; mirror those — they are expected here).
shellcheck -x tests/test_session_mgmt.sh || true
# Expected: only the documented in-scope-symbol disables; no real errors.
```

### Level 2: Run JUST the new suite (fast feedback, isolated)

run.sh runs the WHOLE suite. To iterate on ONLY the new tests, use a throwaway
runner that sources the harness + just this file (keeps the real server safe
via the same shim):

```bash
# /tmp/run_only.sh — minimal runner mirroring tests/run.sh for ONE file.
cat > /tmp/run_only.sh <<'EOF'
#!/usr/bin/env bash
set -u
cd /home/dustin/.config/tmux/plugins/tmux-livepicker
source tests/setup_socket.sh
source tests/helpers.sh
source tests/test_session_mgmt.sh
lp_sweep_orphans 2>/dev/null || true
trap 'lp_sweep_orphans 2>/dev/null || true' EXIT
passed=0 failed=0
for t in $(compgen -A function | grep '^test_' | sort); do
	setup_test "lp-$$-${t#test_}"
	TEST_STATUS="pass"
	"$t"
	if [ "$TEST_STATUS" = pass ]; then echo "PASS  $t"; passed=$((passed+1))
	else echo "FAIL  $t"; failed=$((failed+1)); fi
	teardown_test
done
echo "----"; echo "$passed passed, $failed failed"
[ "$failed" -eq 0 ]
EOF
bash /tmp/run_only.sh
# Expected: all test_session_mgmt_* PASS, real server untouched (PRD §15).
```

### Level 3: Full suite integration (no regressions)

```bash
# The real deliverable gate: the WHOLE suite passes with the new file included.
bash tests/run.sh
# Expected: existing tests still PASS; the new test_session_mgmt_* all PASS;
# exit code 0. The real user tmux server is byte-identical before/after.

# Pollution proof (PRD §15 invariant) — run around the suite:
REAL_BEFORE="$(/usr/bin/tmux list-sessions -F '#{session_name}' 2>/dev/null | sort)"
bash tests/run.sh
REAL_AFTER="$(/usr/bin/tmux list-sessions -F '#{session_name}' 2>/dev/null | sort)"
[ "$REAL_BEFORE" = "$REAL_AFTER" ] && echo "POLLUTION CLEAN" || echo "POLLUTION DETECTED"
# Expected: POLLUTION CLEAN.
```

### Level 4: Behaviour-specific spot checks (the leak regression guard)

```bash
# Confirm the leak test is a TRUE guard: the CONTROL reproduces the orphan,
# the FIX removes it. (Already empirically verified in
# research/session_mgmt_test_findings.md E5; re-run to be sure after edits.)
# In an isolated -L socket (via a tmp PATH shim), after preview.sh victim:
#   - raw `kill-session -t =victim` (no unlink)   => victim @id SURVIVES in driver
#   - `session-mgmt.sh do-delete victim`          => victim @id GONE from driver
# If either half flips, the leak test would be vacuous or the impl regressed.
```

## Final Validation Checklist

### Technical Validation
- [ ] `bash -n tests/test_session_mgmt.sh` clean.
- [ ] `bash /tmp/run_only.sh` → all `test_session_mgmt_*` PASS.
- [ ] `bash tests/run.sh` → exit 0, no regressions in the existing suite.
- [ ] Real `/usr/bin/tmux` server byte-identical before/after `tests/run.sh` (POLLUTION CLEAN).

### Feature Validation (the 8 contract behaviours)
- [ ] (a) rename: list updated, index preserved, mode on, old gone/new exists.
- [ ] (b) sanitized (`:` and leading `.`): abort, list unchanged, no sanitized variant.
- [ ] (c) collision: abort, list unchanged.
- [ ] (d) delete: gone, dropped from list, index clamped to neighbour, preview re-synced.
- [ ] (e) driver guard: refused, driver alive, list unchanged.
- [ ] (f) last-session guard: refused, lone session alive.
- [ ] (g) leak: do-delete leaves NO orphan (and the control reproduces the orphan).
- [ ] (h) confirm-delete on: victim survives until `y`; off: immediate kill.

### Code Quality Validation
- [ ] Header/contract comment mirrors test_functional.sh (SOURCED-by-run.sh, no side effects on source, no setup_test/teardown_test calls in-body, set -u inherited).
- [ ] No hardcoded window ids (@N read dynamically).
- [ ] Failure signalled ONLY via fail/assert_* (no exit / no nonzero-to-abort).
- [ ] The seed helper mirrors test_preview.sh:lp_preview_seed_state.
- [ ] shellcheck-disable set matches the sibling test files (SC2154/SC2016/SC2034/SC2086).

### Documentation & Deployment
- [ ] No source/docs changes (test-only work item; DOCS: none per the contract).
- [ ] The module header documents WHY each test asserts on state not messages (display-message needs a client).

---

## Anti-Patterns to Avoid

- ❌ Don't drive `command-prompt` interactively for the rename submit logic — test `do-rename` directly with seeded state (the harness idiom; the RESEARCH NOTE). The interactive prompt is fragile and unobservable.
- ❌ Don't assert on `display-message` abort text without an attached client — it's not observable. Assert on tmux STATE (list/session existence).
- ❌ Don't write a leak test without the CONTROL (raw kill reproduces the orphan) — a bare "gone after do-delete" can pass vacuously if the link never happened.
- ❌ Don't hardcode window ids (`@1`,`@2`) — read them dynamically via `list-windows -F '#{window_id}'`.
- ❌ Don't call `exit` or `return` nonzero from a test body — it kills run.sh. Use `fail/assert_*`.
- ❌ Don't flip `@livepicker-preview-defer` on — `setup_test` pins it off for deterministic synchronous re-sync assertions.
- ❌ Don't edit `run.sh`, source files, or PRD/tasks.json — discovery is automatic; this is a test-only work item.

---

## Confidence Score: 9/10

All eight behaviours were empirically reproduced and asserted on isolated `-L` sockets via a PATH shim (see `research/session_mgmt_test_findings.md` E1–E6); the real server was verified byte-identical before/after. The one residual uncertainty is the interactive `'y'` send-keys step in (h): if it proves timing-flaky, the deterministic backbone (`confirm-before intercepts` + `off ⇒ immediate kill`) already proves the gate — drop the send-keys step rather than the deterministic assertions. No source/impl changes are in scope; this is pure test authoring against a fixed, already-shipped `session-mgmt.sh`.
