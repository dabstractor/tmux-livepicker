# P1.M7.T3.S1 — `tests/test_functional.sh` research findings

Empirical ground-truth for the PRD §15.17 Functional validation tests. Every
finding was verified live on 2026-07-06 against tmux 3.6b on the isolated socket
the T1.S1/T2.S1 harness (both COMPLETE, read in full) provides. Read this BEFORE
writing test_functional.sh.

---

## FINDING 1 — The harness is COMPLETE; the test file only defines `test_*`

`tests/setup_socket.sh` (P1.M7.T1.S1) and `tests/helpers.sh` (P1.M7.T2.S1) BOTH
exist and were read in full. `tests/run.sh` (T2.S1) sources, in order:
`setup_socket.sh` → `helpers.sh` → every `tests/test_*.sh` (defines `test_*`),
then per discovered `test_*`: `setup_test "lp-$$-<name>"` → run the function in
the CURRENT shell → read `TEST_STATUS` → print PASS/FAIL → `teardown_test`.

**Consequence (the test's available surface — all in scope, no sourcing needed):**
- `setup_test`/`teardown_test` are CALLED BY run.sh (NOT by the test). The test
  body never calls them.
- `attach_test_client [session]` / `detach_test_client` (from setup_socket.sh)
  ARE in scope (helpers.sh/run.sh source setup_socket.sh). The test calls
  `attach_test_client` itself — run.sh's `setup_test` does NOT attach a client.
- `fail`/`pass`/`assert_eq`/`assert_contains` (helpers.sh) ARE in scope.
- `$LIVEPICKER_SCRIPTS` (== repo `scripts/`) is EXPORTED by `setup_socket`
  (called by `setup_test`), so it is set BEFORE the test function runs.
- bare `tmux` resolves to the PATH shim → isolated `-L` socket. So the test, AND
  the plugin scripts it execs, all hit the isolated server transparently.
- `TEST_DRIVER_SESSION` ("driver") + `TEST_FIXTURE_SESSIONS` ("alpha beta") are
  the baseline fixtures seeded by `setup_socket` (driver:extra multi-pane window
  + a split pane in beta).

**test_functional.sh therefore SOURCES NOTHING.** It just defines 5 `test_*`
functions. Add a file-level `# shellcheck disable=SC2154` (the assert_* helpers,
`attach_test_client`, `$LIVEPICKER_SCRIPTS` etc. come from run.sh's sources —
shellcheck sees no definition here; mirrors setup_socket.sh/helpers.sh). `set -u`
is INHERITED (helpers.sh declares it) — do NOT re-declare (mirror test_self.sh:
"`# set -u is inherited`").

## FINDING 2 — CRITICAL: the isolated server SOURCES the user tmux.conf (dormant
              @livepicker-* config survives teardown) — the "no @livepicker-*"
              trap

**Verified live:** a `tmux -L "$TEST_SOCKET"` server started by `setup_socket`
sources `~/.config/tmux/tmux.conf`. That config pre-declares (system_context §1)
two DORMANT config options:
```
@livepicker-fg "#ffffff"
@livepicker-key Space
```
Probe output from a harness-identical isolated server:
```
=== @livepicker-* options present ===
@livepicker-fg "#ffffff"
@livepicker-key Space
```

**The trap:** after `confirm`/`cancel`, `restore.sh` STEP-6 calls
`clear_all_state` (state.sh). `clear_all_state` implements **CORRECTION A**: it
clears ONLY the 5 picker-RUNTIME keys (`@livepicker-mode/list/filter/index/
linked-id`) + every `@livepicker-orig-*` saved-state key, and **PRESERVES PRD §11
config** (`@livepicker-fg`, `@livepicker-key`, …). So the dormant config REMAINS.

**Consequence:** `tmux show-options -g | grep livepicker` is **NOT empty** after
teardown — it prints the 2 config lines. The work-item's literal "no
@livepicker-*" / `grep -c '@livepicker' == 0` would **FALSE-FAIL** in this env.
(The PRD §15.21 phrase "grep livepicker prints nothing" is the aspirational
spec; CORRECTION A is the implemented reality — config MUST survive or the next
activation breaks. restore.sh research CORRECTION 2 documents this explicitly.)

**CORRECT "picker torn down" assertion** (test_confirm_lands + test_escape_restores):
assert the picker-INTERNAL keys are unset, NOT a broad grep==0. Provide a small
local helper in the test:
```bash
# Returns 0 iff every picker-INTERNAL key is unset (config like @livepicker-fg
# /@livepicker-key legitimately REMAINS — CORRECTION A; FINDING 2).
lp_runtime_cleared() {
	local k
	for k in @livepicker-mode @livepicker-list @livepicker-filter \
	         @livepicker-index @livepicker-linked-id; do
		[ -z "$(tmux show-option -gqv "$k" 2>/dev/null)" ] || return 1
	done
	# No @livepicker-orig-* saved-state keys either.
	[ -z "$(tmux show-options -g 2>/dev/null | grep '@livepicker-orig-')" ] || return 1
	return 0
}
```
Use: `lp_runtime_cleared || fail "picker runtime state not cleared (CORRECTION A: config may remain)"`.

(This is the single most important finding in this file — it converts the
work-item's broad "no @livepicker-*" into a correct, env-faithful assertion.)

## FINDING 3 — Driving the scripts (the test's API); the client is REQUIRED

The work-item §1 RESEARCH NOTE is explicit: drive activation by calling
`scripts/livepicker.sh` directly (NOT via keypress); assert observable state;
filter by reading `renderer.sh` output; nav by `input-handler.sh next/prev`;
confirm/cancel likewise. `status==2` + `key-table==livepicker` are the activation
signals.

- **Activate:** `"$LIVEPICKER_SCRIPTS/livepicker.sh"` — executable (+x), no args,
  runs `activate_main`. It uses `tmux display-message -p '#{session_name}'`,
  `'#{window_id}'`, `'#{window_layout}'` in STEP 2 → **REQUIRES an attached
  client**. So EVERY test calls `attach_test_client` (default target =
  `$TEST_DRIVER_SESSION` = "driver") near its start. run.sh's `setup_test` does
  NOT attach.
- **Input:** `"$LIVEPICKER_SCRIPTS/input-handler.sh" <action> [char]` — action ∈
  `type|backspace|next-session|prev-session|confirm|cancel`. `type` takes
  argv[2]=the char (e.g. `input-handler.sh type l`). Each is +x.
- **Renderer:** `"$LIVEPICKER_SCRIPTS/renderer.sh"` — run directly, capture
  stdout (the one-line filtered+highlighted status line). PURE read (zero
  mutation); its internal bare `tmux show-option` calls hit the isolated socket
  via the shim. +x (it is also the `#()` status command).
- **Confirm/cancel:** observable via the attached client's session
  (`tmux display-message -p '#{session_name}'`) + the `@livepicker-*` keys.

The mocks `P1M6T3S1/research/confirm_mock.sh` + `P1M6T4S1/research/cancel_mock.sh`
PRE-FIGURE every one of these patterns (they drove the real scripts against an
isolated `-L` socket with one `script -qec`-attached client). Borrow their shape;
the harness productionizes the socket/client/assert machinery.

## FINDING 4 — Observable activation signals (test_activate_grows_status)

After `livepicker.sh` (with an attached client on driver), assert EXACTLY:
- `tmux show-option -gqv status` == **"2"**. Verified: a fresh server's default
  `status` is **"on"** (probe: `status=[on]`); activate's normalize turns "on"→2
  (livepicker.sh T3 case). So status grows 1→2 deterministically.
- `tmux show-option -gqv 'status-format[0]'` **contains "renderer.sh"**. activate
  installs `#($CURRENT_DIR/renderer.sh)` at `opt_status_format_index` (default 0),
  OVERRIDING the tubular default composite (probe shows the long default at [0];
  activate replaces it). NOTE: quote the bracketed name: `'status-format[0]'`.
- `tmux show-option -gqv key-table` == **"livepicker"** (default "root"; probe
  `key-table=[root]`).
- `tmux show-option -gqv @livepicker-mode` == **"on"** (set LAST by activate T5).

## FINDING 5 — test_typing_filters: add 'log' fixtures BEFORE activate

The list is captured at activate time (`tmux list-sessions -F '#{session_name}'`
→ `@livepicker-list`); typing only mutates `@livepicker-filter`/`index`
(input-handler.sh FINDING 2: the handler NEVER touches the list). The baseline
fixtures (driver/alpha/beta) contain no "log" substring, so the test must ADD
'log'-matching sessions BEFORE running `livepicker.sh` or the filtered view is
empty (exercises the "no match" path, not the filter path the work-item wants).

Sequence:
```bash
attach_test_client
tmux new-session -d -s syslog -x 120 -y 40      # matches 'log'
tmux new-session -d -s blog   -x 120 -y 40      # matches 'log'
"$LIVEPICKER_SCRIPTS/livepicker.sh"             # captures list incl. syslog,blog
"$LIVEPICKER_SCRIPTS/input-handler.sh" type l   # filter=l, index=0
"$LIVEPICKER_SCRIPTS/input-handler.sh" type o   # filter=lo, index=0
"$LIVEPICKER_SCRIPTS/input-handler.sh" type g   # filter=log, index=0
out="$("$LIVEPICKER_SCRIPTS/renderer.sh")"      # the filtered+highlighted view
assert_contains "$out" "syslog" "filtered view shows the 'log' match syslog"
assert_contains "$out" "blog"   "filtered view shows the 'log' match blog"
# NEGATIVE (FINDING 9): non-matches must NOT appear:
case "$out" in *alpha*) fail "alpha leaked into filtered view" ;; esac
case "$out" in *driver*) fail "driver leaked into filtered view" ;; esac
assert_eq "$(tmux show-option -gqv @livepicker-index)" "0" "type resets index to 0"
```
Renderer output shape: space-joined `#[fg=..,bg=..]NAME#[default]` segments
(highlighted = index 0 = `#[fg=black,bg=yellow]..`), plus (show_count default on)
a trailing `query> log [1/2]`. The NAME is a literal substring → `assert_contains`
works regardless of the `#[..]` style codes.

## FINDING 6 — test_nav_moves_selection: read target window ids DYNAMICALLY

Window ids (`@0`,`@1`,…) are GLOBAL across the server, assigned incrementally;
**never hardcode them.** Read the expected id live:
```bash
alpha_wid="$(tmux list-windows -t =alpha -F '#{window_id}' -f '#{window_active}')"
```
Probe confirms alpha=@1, beta=@2 (driver's own windows are @0 + @3 "extra").
After `next-session`, preview.sh links the target's active window into the driver
and sets `@livepicker-linked-id` = that id.

Sequence:
```bash
attach_test_client
"$LIVEPICKER_SCRIPTS/livepicker.sh"             # initial preview = SELF (driver)
# SELF-session path CLEARS linked_id (preview.sh FINDING 6) -> empty after activate
assert_eq "$(tmux show-option -gqv @livepicker-linked-id)" "" "self-session: no link"
alpha_wid="$(tmux list-windows -t =alpha -F '#{window_id}' -f '#{window_active}')"
"$LIVEPICKER_SCRIPTS/input-handler.sh" next-session   # index 1 -> alpha
assert_eq "$(tmux show-option -gqv @livepicker-linked-id)" "$alpha_wid" "preview linked alpha's window"
beta_wid="$(tmux list-windows -t =beta -F '#{window_id}' -f '#{window_active}')"
"$LIVEPICKER_SCRIPTS/input-handler.sh" next-session   # index 2 -> beta
assert_eq "$(tmux show-option -gqv @livepicker-linked-id)" "$beta_wid" "preview linked beta's window"
```
NOTE: nav NEVER calls switch-client (Invariant A — the client stays on driver the
whole time; `tmux display-message -p '#{session_name}'` stays "driver"). Optional
3rd `next-session` → index wraps to 0 → driver → SELF → linked_id cleared again.

## FINDING 7 — test_confirm_lands: navigate to a target, then confirm

After activate the highlight = current session (driver); confirming on driver is
trivial. To test landing on a real target, `next-session` to alpha first, then
confirm. `confirm` → `_confirm_land_on_session alpha`: unlinks `driver:linked_id`
(the FINDING 1/2 catastrophic-bug guard — clean the preview BEFORE the switch),
`switch-client -t "=alpha"` (the ONE session switch in the whole flow), then
`restore.sh keep` (clears runtime+orig state, restores status/key-table/layout,
but does NOT switch again).
```bash
attach_test_client
"$LIVEPICKER_SCRIPTS/livepicker.sh"
"$LIVEPICKER_SCRIPTS/input-handler.sh" next-session   # highlight -> alpha
"$LIVEPICKER_SCRIPTS/input-handler.sh" confirm
assert_eq "$(tmux display-message -p '#{session_name}')" "alpha" "client landed on alpha"
lp_runtime_cleared || fail "picker torn down (runtime+orig cleared; config may remain — FINDING 2)"
```
BONUS regression check (confirm_mock FINDING 1/2): the driver must NOT still hold
the preview window. Capture `linked_id` before confirm; after confirm assert
`tmux list-windows -t driver -F '#{window_id}'` does not contain it. (Optional but
cheap; it guards the switch-before-unlink destruction bug.)

## FINDING 8 — test_escape_restores: capture orig dynamically + EMPTY filter for
              a single cancel

`cancel` is TWO-STEP (input-handler.sh): a NON-empty filter → CLEAR the filter +
keep the picker OPEN; an EMPTY filter → full `restore.sh cancel`. So a single
`cancel` only tears down when the filter is empty. The recommended flow exercises
"escape AFTER browsing" (PRD §3 user story): activate → next-session (links a
window into the driver) → cancel (restore must unlink it + restore layout). Nav
does not change the filter, so it is still "" when cancel runs → full teardown.

Capture the client's ORIGINAL state BEFORE activate (dynamic — the active window
id depends on fixture creation order; probe shows driver's active window = @3
"extra"):
```bash
attach_test_client
orig_sess="$(tmux display-message -p '#{session_name}')"     # driver
orig_win="$(tmux display-message -p '#{window_id}')"          # @3 (extra) — read live
orig_status="$(tmux show-option -gqv status)"                 # on
orig_kt="$(tmux show-option -gqv key-table)"                  # root
"$LIVEPICKER_SCRIPTS/livepicker.sh"
"$LIVEPICKER_SCRIPTS/input-handler.sh" next-session           # link a preview window
"$LIVEPICKER_SCRIPTS/input-handler.sh" cancel                 # filter empty -> full cancel
assert_eq "$(tmux display-message -p '#{session_name}')" "$orig_sess" "session restored"
assert_eq "$(tmux display-message -p '#{window_id}')"  "$orig_win"  "window restored"
assert_eq "$(tmux show-option -gqv status)"     "$orig_status" "status restored"
assert_eq "$(tmux show-option -gqv key-table)"  "$orig_kt"     "key-table restored"
lp_runtime_cleared || fail "picker torn down after cancel"
```
(Simpler variant — activate → cancel with no nav — also passes and tests the
no-preview-link path; the nav-then-cancel variant is STRONGER and matches the
"escape after browsing" story. Prefer the stronger one.)

## FINDING 9 — Negative substring assertions (helpers.sh is positive-only)

`assert_contains str sub msg` is POSITIVE only. For ABSENCE ("renderer does NOT
show alpha", "no @livepicker-orig-*"), use an inline `case` + `fail` (literal
substring via quoted pattern, no subprocess, set -u safe — mirrors
assert_contains's own implementation):
```bash
case "$out" in *alpha*) fail "alpha leaked into filtered view" ;; esac
```
Do NOT add a `refute_contains` helper to helpers.sh — it is COMPLETE (T2.S1-owned,
read-only). Do NOT use `echo "$out" | grep -v` (subprocess + pipefail hazard;
house style forbids pipefail).

## FINDING 10 — House style + scope (FORBIDDEN edits)

- `#!/usr/bin/env bash`; `set -u` INHERITED (do not re-declare; mirror
  test_self.sh); `local` for ALL function locals; TABS; quote everything.
- Signal failure ONLY via `fail`/`assert_*` (they set `TEST_STATUS`); NEVER
  `exit`/`return`-nonzero-to-abort — run.sh reads `TEST_STATUS` in the CURRENT
  shell (a bare `exit` would kill the runner). Mirrors the resurrect
  `fail_helper` contract.
- The test file is SOURCED by run.sh: define `test_*` ONLY; NO side effects on
  source (no top-level execution); NO `setup_test`/`teardown_test` calls (run.sh
  owns the per-test cycle).
- FORBIDDEN edits: `tests/setup_socket.sh`, `tests/helpers.sh`, `tests/run.sh`,
  any `scripts/*`, `PRD.md`, `tasks.json`, `prd_snapshot.md`, `.gitignore`. This
  task ADDS exactly ONE file: `tests/test_functional.sh`.
- shellcheck: file-level `# shellcheck disable=SC2154` (the assert_* helpers,
  `attach_test_client`, `$LIVEPICKER_SCRIPTS` come from run.sh's sources) +
  `SC2016,SC2034,SC2086` if any eval/quoting false positives arise (mirror
  setup_socket.sh).

## FINDING 11 — Confidence + the one residual risk

High confidence (9/10): every driving pattern is empirically proven by the two
P1.M6 throwaway mocks + the probe above; the harness is COMPLETE; the dormant-
config trap (FINDING 2) is the only non-obvious correctness issue and it is fully
specified with the correct `lp_runtime_cleared` assertion. Residual risk (-1): the
`script -qec` pty-attach timing (`attach_test_client` sleeps 0.5s) is inherited
from setup_socket/T1.S1 and is occasionally racy on a loaded machine — if a test
intermittently fails on `display-message` resolving to the wrong client, the fix
is a slightly longer settle (bump the sleep in attach_test_client, owned by
T1.S1 — NOT this task). The tests themselves are deterministic given the attach
settles.
