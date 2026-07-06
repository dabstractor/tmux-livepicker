# PRP — Bugfix P1.M2.T2.S1: window-index-aware resolution in preview.sh + regression test (Issue 4)

> **Bug context**: This is Issue 4 (Minor) from the adversarial QA pass
> (`plan/001_fd5d622d3939/bugfix/001_15442f34c366/architecture/bugfix_findings.md`).
> In window mode the picker lists **`session:window_index`** tokens
> (`livepicker.sh:103`: `list-windows -a -F '#{session_name}:#{window_index}'`),
> and `preview.sh` is called with such a token as `$S`. But `preview.sh` resolves
> the candidate window via `list-windows -t "=$S" -F '#{window_id}' -f '#{window_active}'`
> (line ~115), which **always returns the session's active window** regardless of
> the index. So previewing `alpha:5` shows whatever window happens to be `alpha`'s
> active window, not window 5. The `#{window_active}` filter ignores the index, and
> `-f '#{window_index} == N'` does NOT filter either (expands to non-empty text →
> always truthy). The fix: branch on `opt_type`; in window mode parse the token
> and resolve the **specific** window by index (list all windows, match the index
> field in `awk`, return its `@id`); in session mode keep the existing active-window
> path unchanged. Also fix `preview_fallback` whose `"=$1:."` target is **malformed**
> for a token (`=multi:1:.` → "can't find window 1:").

---

## Goal

**Feature Goal**: In window mode, `preview.sh` resolves the **specific window at
the highlighted index** (the `session:index` token's index), links it, and tracks
its `@id` — instead of always linking the session's active window. Session mode is
byte-for-byte unchanged. The `capture-pane` fallback is also corrected for window
mode (its target was malformed for a token).

**Deliverable**:
1. `scripts/preview.sh` — in `preview_main()`, add a `w_sess`/`w_idx` branch
   BEFORE the existing `src_id` resolution: when `opt_type` is `window` AND `$S`
   contains a `:`, parse the token and resolve the window `@id` by index via
   `awk`; otherwise keep the existing `#{window_active}` line unchanged. Also
   update `preview_fallback()` to build its capture-pane target from the parsed
   token in window mode.
2. `tests/test_preview.sh` — append `test_window_preview_shows_highlighted_window`,
   auto-discovered by `tests/run.sh`, that creates a session with TWO windows,
   dynamically detects the NON-active window's index + `@id`, calls
   `preview.sh 'multi:<non_active_index>'`, and asserts `@livepicker-linked-id`
   equals the highlighted window's `@id` (NOT the active window's `@id`).

**Success Definition**:
- In window mode, previewing `multi:1` (where window 1 is NON-active) sets
  `@livepicker-linked-id` to window 1's `@id` — the **highlighted** window. Today
  it links the **active** window's `@id` (the bug).
- In session mode, `preview.sh <session>` behaves EXACTLY as before (active window
  resolution, unchanged line).
- The `capture-pane` fallback no longer errors in window mode (target
  `=$w_sess:$w_idx.` is well-formed).
- `tests/run.sh` reports the new test PASS and the full suite stays green (the
  change adds one branch to preview.sh; no other behavior changes).
- Bug-reintroduction check: reverting the window branch makes the new test FAIL
  (linked-id becomes the active window's `@id`).

## User Persona (if applicable)

**Target User**: The end user running the picker in **window mode**
(`@livepicker-type window`) with sessions that have multiple windows. Also the
maintainer / QA.

**Use Case**: The user activates the picker in window mode, navigates the
highlight to a specific window (e.g. `alpha:5`), and the live preview area must
show **window 5**'s panes — not whatever window happens to be `alpha`'s active
window.

**Pain Points Addressed**: Today the window-mode preview shows the wrong window
(the session's active one) whenever the highlighted window is not the active one,
degrading the window-picker UX to the point of being misleading. The fix makes
the preview track the actual highlight.

## Why

- **Real, reachable bug.** In window mode the picker token is `session:index`
  (livepicker.sh:103). preview.sh is called with that token (input-handler nav
  + the P1.M1.T2.S1 sync helper). The `#{window_active}` filter discards the
  index and always returns the active window — so any non-active highlight shows
  the wrong preview. Reproduced live (research FINDING 4).
- **The naive `-f '#{window_index} == N'` does NOT work.** Per external research,
  it expands to non-empty text for every window → always truthy (returns all
  windows). The robust fix lists all windows and matches the index field in
  `awk`, returning the `@id` (research FINDING 3).
- **`@id` is the plugin's invariant.** The rest of preview.sh (duplicate guard,
  unlink, link-window, select-window, set_state) operates on the `@id` handle and
  is correct UNCHANGED once `src_id` resolves to the right window (research
  FINDING 10). So the fix is confined to the one resolution step.
- **The fallback is also broken in window mode.** `"=$1:."` with a token becomes
  `=multi:1:.` → "can't find window 1:" (research FINDING 6). Fixing it is
  necessary for the degraded path (snapshot mode / link failure) to work at all
  in window mode.
- **Cheap, surgical, low-risk.** One `if/else` around the existing `src_id=`
  line, one token-parse in `preview_fallback`. No new sourcing, no state change,
  no driver change, no `options.sh` change. Session mode is on the unchanged
  `else` branch.
- **Closes a real test gap.** No existing test exercises window-mode preview of a
  non-active window (bugfix_findings §Testing Summary: "window-mode preview
  correctness"). The new test guarantees this exact shape can't regress.
- **Disjoint from the parallel task.** P1.M2.T1.S1 touches `renderer.sh` +
  `test_functional.sh`; this task touches `preview.sh` + `test_preview.sh` — no
  shared file, no edit collision (research FINDING 8).

## What

1. **In `scripts/preview.sh::preview_main()`**: declare `w_sess w_idx` (add to the
   existing `local` line) and replace the single `src_id=…#{window_active}…` line
   with an `if/else`:
   - **window mode + token** (`opt_type` = `window` AND `$S` contains `:`):
     `w_sess="${S%%:*}"`, `w_idx="${S#*:}"`, then resolve the specific window
     `@id` by index: `list-windows -t "=$w_sess" -F '#{window_id}:#{window_index}' | awk -F: -v idx="$w_idx" '$2==idx {print $1; exit}'`.
   - **else (session mode, or window-mode-without-token)**: the EXISTING line
     unchanged: `list-windows -t "=$S" -F '#{window_id}' -f '#{window_active}'`.
2. **In `scripts/preview.sh::preview_fallback()`**: parse the token in window mode
   so the capture-pane target is `=$w_sess:$w_idx.` (well-formed) instead of the
   malformed `=$1:.`. Session mode keeps `=$1:.` unchanged.
3. **Do NOT change**: the duplicate guard, the unlink, `link-window`,
   `select-window`, `set_state "$STATE_LINKED_ID"`, the self-session guard, the
   `@livepicker-preview-mode` gate, `options.sh`, `state.sh`, `utils.sh`, any
   other script, or any stored state shape. Session-mode behavior is bit-for-bit
   identical (it is literally the unchanged `else` branch).

### Success Criteria

- [ ] `preview_main` branches on `opt_type`; the window+token branch resolves the
      window `@id` by index via `awk` (NOT `#{window_active}`).
- [ ] The session-mode path is the EXISTING line, unchanged (the `else` branch).
- [ ] `preview_fallback` builds a well-formed target (`=$w_sess:$w_idx.`) in
      window mode; session mode keeps `=$1:.`.
- [ ] `@livepicker-type` is READ via `opt_type` (already sourced) — NOT a new
      option or state key.
- [ ] NO change to any other script, to `options.sh`/`state.sh`/`utils.sh`, or to
      stored state.
- [ ] `bash -n` + `shellcheck` clean on `preview.sh` and `test_preview.sh`.
- [ ] `tests/run.sh`: new test PASS, full suite green (exit 0).
- [ ] Bug-reintroduction check: revert the window branch → new test FAILS.

## All Needed Context

### Context Completeness Check

_Pass_: A developer who has never seen this repo can implement the fix from
(a) the exact old→new code blocks (quoted verbatim with line numbers),
(b) the verbatim test body (below, with the dynamic-detection approach that
survives `base-index` 0 or 1), and
(c) the load-bearing rules (resolve by index via `awk`, NOT `-f '#{window_index}'`;
address windows by `@id`; session mode is the unchanged `else`; the fallback
target must be reparsed). All live-proven in
research/preview_window_index_findings.md. No tmux-internals inference required.

### Documentation & References

```yaml
# MUST READ — the bug report (root cause + the fix directive)
- docfile: plan/001_fd5d622d3939/bugfix/001_15442f34c366/architecture/bugfix_findings.md
  why: §ISSUE 4 gives the exact buggy line (preview.sh ~115), the root cause
       (#{window_active} ignores the index; -f '#{window_index} == N' does NOT
       filter), the confirm-branch reference (w_sess="${target%%:*}"), and the
       fix directive ("branch on opt_type; window mode: parse S, resolve by
       index; session mode: unchanged"). §External tmux research item 3/4
       confirms the -f truthiness trap and the @id invariant.
  critical: The rest of preview.sh operates on $src_id (@id handle) and works
            UNCHANGED — the fix is confined to the resolution step.

# MUST READ — the empirical ground-truth for THIS fix (13 live-verified findings)
- docfile: plan/001_fd5d622d3939/bugfix/001_15442f34c366/P1M2T2S1/research/preview_window_index_findings.md
  why: FINDING 1 (CRITICAL test gotcha: base-index is INHERITED from ~/.tmux.conf;
       the contract's literal `new-window -t multi -n secondwin` FAILS "index 1
       in use" -> use -a + dynamic detection); FINDING 2 (new-window makes the
       new window ACTIVE -> the non-active window is the FIRST one; detect by
       #{window_active}==0, never assume the index); FINDING 3 (the awk
       index->@id resolution works, verified); FINDING 4 (the buggy active-filter
       ignores the index, verified); FINDING 5 (token parse + portable [ ] colon
       gate: "${S%%:*}" != "$S"); FINDING 6 (preview_fallback's "=$1:." is
       MALFORMED for a token -> "=multi:1:." -> "can't find window 1:"); FINDING 7
       (the fixed target =$w_sess:$w_idx. works; session mode =alpha:. unchanged);
       FINDING 8 (NO file conflict with parallel P1.M2.T1.S1); FINDING 9 (preview.sh
       is client-independent -> NO attach_test_client; reuse lp_preview_seed_state);
       FINDING 10 (the rest of preview_main is UNCHANGED); FINDING 11 (the
       prove-it-catches-the-bug check is deterministic); FINDING 12 (add w_sess w_idx
       to the existing local declaration); FINDING 13 (TABS).
  critical: FINDING 1 is the single most important test-design rule — the
            contract's literal setup commands FAIL on a base-index=1 server. Use
            `new-window -t multi -a` and detect indices dynamically.

# MUST READ — the file being modified (the resolution step + the fallback)
- file: scripts/preview.sh
  why: Contains preview_main() with the buggy src_id resolution (~line 115) and
        preview_fallback() with the malformed target. The fix wraps the src_id
        line in an if/else and reparses the fallback target in window mode.
  pattern: preview_main already sources options.sh (line 38) so opt_type() is
           available; it reads current_session from @livepicker-orig-session
           (client-independent). The existing local declaration is
           `local current_session orig_window linked_id src_id` — add w_sess w_idx.
  gotcha: opt_type() defaults to "session" (options.sh:27); the test MUST set
          @livepicker-type window or the window branch never fires. The
          self-session guard compares $S to current_session — in window mode $S
          is "multi:1" != "driver", so the guard is correctly skipped.

# MUST READ — the token-parsing reference (already proven correct in confirm)
- file: scripts/input-handler.sh
  why: The window-mode confirm branch ALREADY splits the token correctly:
        `w_sess="${target%%:*}"` then `select-window -t "$target"`. This is the
        SAME split preview.sh must use (research FINDING 5). Mirroring it keeps
        the two paths consistent.
  section: confirm / window-mode branch (~line 300)

# MUST READ — where the token comes from (the picker list format)
- file: scripts/livepicker.sh
  why: Window mode builds the list with `list-windows -a -F '#{session_name}:#{window_index}'`
       (~line 103), so the candidate passed to preview.sh is ALWAYS
       'session:index' in window mode. This is why the colon-gate is correct.
  section: lp_build_list window branch (~line 100-108)

# MUST READ — the test file + the pattern to mirror + the seed helper
- file: tests/test_preview.sh
  why: Defines lp_preview_seed_state() (sets @livepicker-orig-session/window/-
        linked-id — the MINIMAL state preview.sh reads; client-independent) and
        four test_* functions that call preview.sh DIRECTLY and assert tmux state.
        The new test mirrors this style: lp_preview_seed_state + set type=window +
        create windows + call preview.sh + assert @livepicker-linked-id.
  critical: lp_preview_seed_state does NOT set @livepicker-type — the new test
            MUST set it to "window" itself (opt_type gates the branch). preview.sh
            is client-independent -> NO attach_test_client (research FINDING 9).

# MUST READ — the assertion helpers in scope inside test bodies
- file: tests/helpers.sh
  why: assert_eq a b msg + assert_contains str sub msg (literal `case` match) +
        fail msg (sets TEST_STATUS, never exits). The new test uses assert_eq for
        the linked-id comparison and `|| fail` for the active-id belt-and-braces
        check.
  critical: Never exit/return-nonzero from a test body — signal failure ONLY via
            fail()/assert_* (run.sh reads TEST_STATUS in the current shell).

# MUST READ — how tests are discovered + the per-test socket cycle
- file: tests/run.sh
  why: Auto-discovers every test_* via `compgen -A function | grep '^test_'`; per
        test runs setup_test "lp-$$-<name>" (fresh isolated socket + PATH shim +
        baseline fixtures) -> resets TEST_STATUS=pass -> runs the test in the
        CURRENT shell -> teardown_test. Adding a test_* fn to test_preview.sh is
        sufficient (no registration).
  critical: The isolated server INHERITS ~/.tmux.conf (no -f /dev/null) ->
            base-index may be 0 or 1 (research FINDING 1). Never hardcode an index.

# MUST READ — the isolation layer (what setup_test gives the test)
- file: tests/setup_socket.sh
  why: setup_test -> setup_socket: temp dir + PATH shim (bare `tmux` -> isolated
        -L socket) + baseline driver/alpha/beta fixtures + exports
        $LIVEPICKER_SCRIPTS / $TEST_DRIVER_SESSION. attach_test_client is OPTIONAL
        (NOT needed by the preview test).
  critical: Window IDs are GLOBAL and assigned in creation order; read them
            DYNAMICALLY (mirror test_multipane_preview's `list-windows ... -f
            '#{window_active}'`). base-index is inherited — use -a for new-window.

# Reference — PRD context for the bug
- docfile: PRD.md
  why: §2 non-goals notes "the preview shows the candidate's active window" —
        arguably by-design for SESSION mode, but in WINDOW mode the candidate IS
        a specific window (the token carries the index), so showing the active
        window is a correctness bug. §7 Fallbacks (capture-pane) + §11 config.
  section: "§2 Non-goals", "§7 Fallbacks", "§11 Configuration"
```

### Current Codebase tree

```bash
tmux-livepicker/
  scripts/
    preview.sh        # MODIFY: +window branch in preview_main(); +token parse in preview_fallback()
    options.sh        # UNCHANGED (opt_type — READ ONLY; already sourced by preview.sh)
    state.sh          # UNCHANGED (get_state/set_state/STATE_*/ORIG_* — read only)
    utils.sh          # UNCHANGED (tmux_* — read only)
    input-handler.sh  # UNCHANGED (calls preview.sh "$target" — argv contract unchanged)
                      # NOTE: P1.M2.T1.S1 (parallel) modifies renderer.sh — DISJOINT from this task.
    livepicker.sh, restore.sh, renderer.sh, filter.sh, plugin.tmux  # UNCHANGED
  tests/
    test_preview.sh   # MODIFY: append test_window_preview_shows_highlighted_window
                      # NOTE: P1.M2.T1.S1 (parallel) appends to test_functional.sh — DISJOINT.
    run.sh, helpers.sh, setup_socket.sh  # UNCHANGED
    test_*.sh (others)  # UNCHANGED
```

### Desired Codebase tree with files to be added and responsibility of file

```bash
scripts/preview.sh     # +window-mode index resolution (awk) in preview_main; +token-aware capture target in preview_fallback
tests/test_preview.sh  # +test_window_preview_shows_highlighted_window — proves the linked window is the highlighted one, not the active one
```

### Known Gotchas of our codebase & Library Quirks

```bash
# CRITICAL (research FINDING 1): the isolated tmux server INHERITS ~/.tmux.conf
# (setup_socket does NOT pass -f /dev/null), so base-index may be 0 OR 1. The
# contract's literal `new-window -t multi -n secondwin` FAILS "index 1 in use"
# when base-index=1. The test MUST use `new-window -t multi -a` (append) and
# detect every index/id DYNAMICALLY. Never hardcode an index.

# CRITICAL (research FINDING 2): `new-window` makes the NEW window ACTIVE. So with
# two windows, the SECOND-created window is active and the FIRST is non-active.
# The highlighted (non-active) window is the FIRST — detect it by
# #{window_active}==0, do not assume the index. (The work-item contract's phrase
# "SECOND (non-active) window" is imprecise; dynamic detection sidesteps it.)

# CRITICAL (research FINDING 3 + bugfix_findings): `-f '#{window_index} == N'`
# does NOT filter (expands to non-empty text -> always truthy -> returns all
# windows). Resolve the window by listing all windows and matching the index
# field in awk: `list-windows -F '#{window_id}:#{window_index}' | awk -F: -v
# idx="$w_idx" '$2==idx {print $1; exit}'`. Returns the @id.

# CRITICAL (research FINDING 6): preview_fallback's target "=$1:." is MALFORMED
# for a token: $1="multi:1" -> "=multi:1:." -> tmux error "can't find window 1:".
# Build the target from the parsed token: =$w_sess:$w_idx. (verified rc=0).

# GOTCHA (research FINDING 5): the colon-presence test must be PORTABLE (preview.sh
# uses [ ], not [[ ]]). Use `"${S%%:*}" != "$S"` — ${var%%:*} strips from the
# first ':' onward, so it differs from $var iff $var contains a ':'. This mirrors
# the confirm branch's `w_sess="${target%%:*}"` (input-handler.sh, proven).

# GOTCHA: opt_type() defaults to "session" (options.sh:27). The window branch
# fires ONLY when @livepicker-type == window. The test MUST set it. Session mode
# is the unchanged else branch — its behavior is byte-identical to today.

# GOTCHA (research FINDING 9): preview.sh is CLIENT-INDEPENDENT (reads
# @livepicker-orig-session via get_state, NOT display-message). The test needs NO
# attach_test_client. Reuse lp_preview_seed_state (top of test_preview.sh).

# GOTCHA (research FINDING 10): the rest of preview_main operates on $src_id (@id
# handle) — duplicate guard, unlink, link-window, select-window, set_state all
# work UNCHANGED once src_id is the correct window. Do NOT touch them.

# GOTCHA: window @ids are GLOBAL (e.g. @4, @5). Read them DYNAMICALLY via
# list-windows; never assume an id. The plugin's invariant is to address windows
# by @id, NEVER index (renumber-windows is on during the picker — bugfix_findings
# FINDING 10). The LIST is snapshotted at activation (stable for picker lifetime),
# so index->@id resolution at preview time is correct.

# STYLE (system_context §9, FINDING 13): indent with TABS (NOT 4-space). shfmt NOT
# installed; verify with `grep -Pn '^    '`. preview.sh already has
# `shellcheck disable=SC1091,SC2153`; the new awk pipe is clean (idx is passed via
# -v, no word-splitting of the value).
```

## Implementation Blueprint

### Data models and structure

No data-model change. The "model" is a single resolution decision in
`preview_main` and a single target-construction decision in `preview_fallback`,
both keyed on `opt_type()` + token presence:

```
preview_main($S)
 ├─ read current_session/orig_window/linked_id (UNCHANGED)
 ├─ @livepicker-preview-mode gate (UNCHANGED: off->return; snapshot->fallback)
 ├─ self-session guard (UNCHANGED: "multi:1" != "driver" -> skipped in window mode)
 ├─ RESOLVE src_id:                                          # <- THE FIX
 │    if opt_type==window AND $S has ':':
 │        w_sess=${S%%:*}; w_idx=${S#*:}
 │        src_id = list-windows =$w_sess | awk match index   # specific window @id
 │    else:
 │        src_id = list-windows =$S -f #{window_active}      # UNCHANGED (session mode)
 ├─ empty src_id -> preview_fallback $S (now token-aware) -> return
 ├─ duplicate guard / unlink / link-window / select-window / set_state  # UNCHANGED
 └─ (all operate on the @id handle)

preview_fallback($1)
 ├─ if opt_type==window AND $1 has ':':
 │      target = ${1%%:*}:${1#*:}        # "multi:1"
 │    else:
 │      target = $1                       # bare session name (session mode)
 └─ capture-pane -t "=$target:."         # =multi:1. (window) / =alpha:. (session)
```

### Implementation Tasks (ordered by dependencies)

```yaml
Task 1: MODIFY scripts/preview.sh — add w_sess/w_idx to preview_main's locals
  - LOCATE preview_main()'s existing local declaration line:
        local current_session orig_window linked_id src_id
    ADD w_sess w_idx to it:
        local current_session orig_window linked_id src_id w_sess w_idx
  - WHY: keeps declarations at the top (the file's style); w_sess/w_idx are only
    ASSIGNED+READ inside the window branch (Task 2), so they stay set -u-safe
    (declared -> never "unbound"; empty in the else branch where they are never read).
  - STYLE: TABS; one local line (matches the existing declaration).
  - NO new sourcing; NO strictness change; NO driver change.

Task 2: MODIFY scripts/preview.sh — wrap the src_id resolution in an if/else
  - LOCATE the single src_id resolution line (~line 115):
        # Resolve S's active window id (exact-match =S; one line @N; FINDING 7).
        src_id="$(tmux list-windows -t "=$S" -F '#{window_id}' -f '#{window_active}' 2>/dev/null)"
  - REPLACE it with an if/else (verbatim code in "Implementation Patterns" below):
      * window + token branch: parse w_sess/w_idx, resolve the @id by index via awk.
      * else branch: the EXISTING #{window_active} line, UNCHANGED.
  - FOLLOW pattern: the token split mirrors input-handler.sh confirm
    (`w_sess="${target%%:*}"`); the awk index match is research FINDING 3.
  - GOTCHA: use the portable colon gate `"${S%%:*}" != "$S"` (NOT [[ ]]).

Task 3: MODIFY scripts/preview.sh — make preview_fallback token-aware
  - LOCATE preview_fallback()'s body (the capture-pane line):
        local captured
        # ... (existing comment) ...
        captured="$(tmux capture-pane -ep -t "=$1:." 2>/dev/null)" && return 0 || return 1
  - INSERT a token-parse branch BEFORE the capture: declare `local target="$1"`;
    if opt_type==window AND $1 has ':', set `target="$w_sess:$w_idx"`; else
    target stays $1. Change the capture target from "=$1:." to "=$target:.".
  - WHY: "=$1:." is malformed for a token (research FINDING 6); "=$target:."
    (=multi:1.) is well-formed (research FINDING 7). Handles all 3 call sites
    (snapshot gate, src_id-empty, link failure) uniformly — they all call
    preview_fallback "$S".
  - VERBATIM code in "Implementation Patterns" below.

Task 4: MODIFY tests/test_preview.sh — APPEND the regression test at EOF
  - LOCATE: the file's TRUE end (after its last test_* function — currently
    test_capture_fallback; anchor on the final `}` / EOF, not a named fn, in case
    a parallel task moved the tail — though this file is exclusively this task's).
  - APPEND test_window_preview_shows_highlighted_window (full body in
    "Implementation Patterns" below).
  - FOLLOW pattern: lp_preview_seed_state (brings orig-session/window/linked-id);
    set @livepicker-type window; create multi with -a; detect the non-active
    window DYNAMICALLY; call preview.sh "multi:$na_idx"; assert @livepicker-linked-id
    == na_id (and != active_id). NO attach_test_client (research FINDING 9).
  - NAMING: test_window_preview_shows_highlighted_window.
  - STYLE: TABS; local for all vars; set -u-safe; NO exit in the body (signal via
    fail/assert_*).
  - CRITICAL (research FINDING 1/2): use `new-window -t multi -a` (NOT bare
    `new-window -t multi -n secondwin`, which FAILS on base-index=1) and detect
    the non-active window by #{window_active}==0 (new-window makes the new window
    active, so the FIRST window is non-active).

Task 5: VALIDATE (full harness; prove the test catches the bug)
  - RUN: bash -n scripts/preview.sh ; bash -n tests/test_preview.sh
  - RUN: shellcheck scripts/preview.sh tests/test_preview.sh (expect clean)
  - RUN: tests/run.sh (expect: new test PASS, full suite green, exit 0)
  - PROVE-IT-CATCHES-THE-BUG: temporarily revert the window branch (sed the
    if/else back to the single active-filter line), run the suite, confirm the
    new test FAILS (linked-id == active_id), then restore. (See Validation Loop §3.)
```

### Implementation Patterns & Key Details

**Task 1+2 — preview_main src_id resolution (paste verbatim).** First add
`w_sess w_idx` to the existing local declaration, then replace the single
resolution line with the if/else. The exact CURRENT code to anchor on:

```bash
	local current_session orig_window linked_id src_id
```
→
```bash
	local current_session orig_window linked_id src_id w_sess w_idx
```

And the resolution block. CURRENT (the line to replace):

```bash
	# Resolve S's active window id (exact-match =S; one line @N; FINDING 7).
	src_id="$(tmux list-windows -t "=$S" -F '#{window_id}' -f '#{window_active}' 2>/dev/null)"
```
→
```bash
	# Resolve the candidate window id. SESSION mode: the session's active window
	# (exact-match =S; one line @N; FINDING 7) — UNCHANGED. WINDOW mode: $S is a
	# 'session:window_index' token (livepicker.sh:103); resolve the SPECIFIC window
	# at that index, NOT the session's active window (bugfix ISSUE 4). The
	# #{window_active} filter ignores the index, and -f '#{window_index} == N'
	# does NOT filter (expands to non-empty text -> always truthy), so list all
	# windows and match the index field, returning the @id (address by @id — the
	# plugin's invariant; renumber-windows is on but the list is snapshotted).
	if [ "$(opt_type)" = "window" ] && [ "${S%%:*}" != "$S" ]; then
		w_sess="${S%%:*}"
		w_idx="${S#*:}"
		src_id="$(tmux list-windows -t "=$w_sess" -F '#{window_id}:#{window_index}' 2>/dev/null | awk -F: -v idx="$w_idx" '$2==idx {print $1; exit}')"
	else
		src_id="$(tmux list-windows -t "=$S" -F '#{window_id}' -f '#{window_active}' 2>/dev/null)"
	fi
```

(The `if [ -z "$src_id" ]; then preview_fallback "$S" …` block immediately BELOW
stays UNCHANGED — an empty src_id [window gone / race / index miss] still falls
through to the fallback, which Task 3 now makes window-aware.)

**Task 3 — preview_fallback token-aware target (paste verbatim).** CURRENT:

```bash
preview_fallback() {
	# capture-pane snapshot fallback (PRD §7 Fallbacks). Single-pane, NOT live.
	# ... (existing comment) ...
	local captured
	# shellcheck disable=SC2034  # best-effort hint; text intentionally unused.
	captured="$(tmux capture-pane -ep -t "=$1:." 2>/dev/null)" && return 0 || return 1
}
```
→ (add a `target` local + the token-parse branch; change the capture target):

```bash
preview_fallback() {
	# capture-pane snapshot fallback (PRD §7 Fallbacks). Single-pane, NOT live.
	# Invoked (a) when @livepicker-preview-mode == snapshot (always), and
	# (b) when a live link-window fails (degraded but non-blocking path).
	# Captures the candidate's active pane with escapes. CRITICAL: the target is
	# "=$target:." where $target is the session name (session mode) OR the parsed
	# "session:index" (window mode). The bare "=$1:." form is MALFORMED in window
	# mode: $1="multi:1" -> "=multi:1:." -> "can't find window 1:". So in window
	# mode parse the token and build "=$w_sess:$w_idx." (the active pane of the
	# specific window). Returns capture's rc: 0 = captured, non-zero = gone.
	local captured target="$1"
	if [ "$(opt_type)" = "window" ] && [ "${1%%:*}" != "$1" ]; then
		local w_sess="${1%%:*}" w_idx="${1#*:}"
		target="$w_sess:$w_idx"
	fi
	# shellcheck disable=SC2034  # best-effort hint; text intentionally unused.
	captured="$(tmux capture-pane -ep -t "=$target:." 2>/dev/null)" && return 0 || return 1
}
```

(Keep the existing leading comment block; only the `local captured` line + the
capture line change. `opt_type` is already in scope — preview.sh sources
options.sh at line 38.)

**Task 4 — the regression test (copy verbatim; append at EOF of
`tests/test_preview.sh`; TAB indent to match the file):**

```bash
# test_window_preview_shows_highlighted_window — Bugfix Issue 4: in WINDOW mode
# the picker lists 'session:window_index' tokens (livepicker.sh:103) and preview.sh
# is called with such a token. The candidate may be the session's NON-active window.
# preview.sh must link the window at the given INDEX, NOT the session's active
# window (the #{window_active} filter ignores the index). Creates a session with
# TWO windows, dynamically detects the NON-active window's index + @id (base-index
# may be 0 or 1 — the isolated server inherits ~/.tmux.conf; `new-window -t multi`
# FAILS "index 1 in use" on base-index=1, so use -a + detect dynamically), calls
# preview.sh 'multi:<non_active_index>', and asserts @livepicker-linked-id equals
# the HIGHLIGHTED window's @id (NOT the active window's @id). Before the fix,
# linked-id == the active window's @id (the bug). preview.sh is client-independent
# (reads @livepicker-orig-session from state) -> NO attach_test_client.
test_window_preview_shows_highlighted_window() {
	lp_preview_seed_state
	# Window mode: opt_type gates the new resolution branch. lp_preview_seed_state
	# does NOT set type -> set it explicitly.
	tmux set-option -g @livepicker-type window
	# A candidate session with TWO windows. base-index may be 0 or 1 (inherited
	# from ~/.tmux.conf); create the 2nd window with -a (append — a bare
	# `new-window -t multi` FAILS "index 1 in use" on base-index=1). new-window
	# makes the new window ACTIVE, so the FIRST window is NON-active.
	tmux new-session -d -s multi -x 120 -y 40
	tmux new-window -t multi -a -n secondwin
	# Dynamically detect the NON-active window's index + @id (the highlight target).
	# Space-delimited to avoid any ':' ambiguity in @ids (which are clean @N).
	local nonactive na_idx na_id active_id
	nonactive="$(tmux list-windows -t '=multi' -F '#{window_index} #{window_id} #{window_active}' | awk '$3==0 {print $1" "$2; exit}')"
	na_idx="${nonactive%% *}"
	na_id="${nonactive#* }"
	active_id="$(tmux list-windows -t '=multi' -F '#{window_id}' -f '#{window_active}')"
	# Sanity: the non-active window differs from the active one (proves the bug is
	# reachable — if equal, the test would be vacuous; fail loudly on bad setup).
	assert_contains "$na_id" "@" "non-active window resolved to a @id handle"
	if [ "$na_id" = "$active_id" ]; then
		fail "test setup invalid: non-active window == active window (need 2 distinct windows)"
		return 0
	fi
	# Preview the NON-active window's token (session:index).
	"$LIVEPICKER_SCRIPTS/preview.sh" "multi:$na_idx"
	# The linked window MUST be the HIGHLIGHTED (non-active) window, NOT the
	# session's active window. Before the fix, linked-id == active_id (the bug).
	assert_eq "$(tmux show-option -gqv @livepicker-linked-id)" "$na_id" \
		"window-mode preview links the highlighted window (by index), not the active window"
	# Belt-and-braces: prove it is NOT the active window's id.
	if [ "$(tmux show-option -gqv @livepicker-linked-id)" = "$active_id" ]; then
		fail "window-mode preview linked the ACTIVE window (the bug)"
	fi
}
```

Key pattern notes:
- **No `attach_test_client`** — preview.sh reads `@livepicker-*` options + the
  saved orig-session only.
- `lp_preview_seed_state` brings orig-session/window/linked-id; teardown is
  automatic (run.sh's per-test `teardown_test` kills the server, so `@livepicker-type`
  does not leak).
- **Dynamic detection** (`awk '$3==0'` on the non-active window) survives both
  `base-index` 0 and 1 — the test never assumes an index or id (research FINDING 1/2).
- The `na_id` extraction uses SPACE as the delimiter (research FINDING: @ids are
  `@N`, no spaces) to avoid `:`-splitting ambiguity.

### Integration Points

```yaml
CODE:
  - file: scripts/preview.sh
    change: "preview_main: +w_sess w_idx local; +if/else around src_id (window
             branch = awk index match; else = unchanged #{window_active}).
             preview_fallback: +target local + token parse; capture target
             =$1:. -> =$target:."
    invariant: "window mode links the window at the token's INDEX (by @id);
               session mode byte-identical to today (unchanged else branch);
               fallback target well-formed in both modes"

TESTS:
  - file: tests/test_preview.sh
    change: "+test_window_preview_shows_highlighted_window (append at EOF)"
    discovery: "auto via run.sh compgen -A function | grep '^test_'"

DATABASE / CONFIG / ROUTES: none.
```

## Validation Loop

### Level 1: Syntax & Style (Immediate Feedback)

```bash
cd /home/dustin/.config/tmux/plugins/tmux-livepicker
bash -n scripts/preview.sh    && echo "OK: preview syntax"
bash -n tests/test_preview.sh && echo "OK: test_preview syntax"
shellcheck scripts/preview.sh tests/test_preview.sh
# Tabs-not-spaces sanity on the edited regions (shfmt NOT installed):
grep -nP '^ +' scripts/preview.sh && echo "WARN: space-indent found (use tabs)" || echo "OK: tabs"
# Confirm the window branch + token-aware fallback are present:
grep -c 'awk -F: -v idx' scripts/preview.sh   # -> 1 (the index match in preview_main)
grep -c "opt_type" scripts/preview.sh          # -> 2 (preview_main branch + preview_fallback branch)
grep -c 'target="\$1"' scripts/preview.sh      # -> 1 (preview_fallback local target)
grep -c '=\$target:\.' scripts/preview.sh      # -> 1 (the capture target now uses $target)
grep -c '=\$1:\.' scripts/preview.sh           # -> 0 (the old malformed target is gone)
# Expected: syntax clean; shellcheck 0 new findings; the awk index match + the
# $target capture target are present; no remaining bare "=$1:." target.
```

### Level 2: Unit Tests (the regression test)

```bash
cd /home/dustin/.config/tmux/plugins/tmux-livepicker
# Full hermetic suite (fresh isolated socket per test):
tests/run.sh
# Expected: test_window_preview_shows_highlighted_window prints PASS, the existing
# tests stay green, exit 0. (If P1.M2.T1.S1 landed in parallel, its renderer tests
# also pass — disjoint files.)
```

### Level 3: Prove the test actually catches the bug (critical)

```bash
cd /home/dustin/.config/tmux/plugins/tmux-livepicker
# Snapshot the fixed preview.sh, then REVERT the window branch (force the
# single active-filter line for ALL modes -> the bug):
cp scripts/preview.sh /tmp/preview.fixed
# Surgical revert: replace the if-condition so it NEVER takes the window branch
# (force the else / active-filter path regardless of opt_type):
sed -i 's/if \[ "$(opt_type)" = "window" \] && \[ "${S%%:\*}" != "$S" \]; then/if false; then/' scripts/preview.sh
grep -c 'if false; then' scripts/preview.sh   # -> 1 (window branch disabled)
tests/run.sh 2>&1 | grep 'window_preview_shows_highlighted'
# Expected: the test FAILS (linked-id == active_id, not na_id).
# Restore the fix:
cp /tmp/preview.fixed scripts/preview.sh
tests/run.sh 2>&1 | grep 'window_preview_shows_highlighted'
# Expected: the test PASSES again.
# If the test PASSES even when reverted, it is not exercising the index-resolution
# path (re-check that @livepicker-type=window is set and na_id != active_id).
```

### Level 4: Live resolution spot-check (optional, manual — confirms the @id mapping)

```bash
cd /home/dustin/.config/tmux/plugins/tmux-livepicker
# Manual repro on an isolated socket: prove the awk resolution returns the
# non-active window's @id (mirrors research FINDING 3/4):
source tests/setup_socket.sh; source tests/helpers.sh
setup_test "lp-bug4-live"
tmux new-session -d -s multi -x 120 -y 40
tmux new-window -t multi -a -n secondwin
echo "all windows (index:id:active):"
tmux list-windows -t '=multi' -F '#{window_index}:#{window_id}:#{window_active}'
na_idx="$(tmux list-windows -t '=multi' -F '#{window_index} #{window_active}' | awk '$2==0{print $1;exit}')"
echo "non-active window index: $na_idx"
echo "FIX resolves multi:$na_idx -> @id:"
tmux list-windows -t "=multi" -F '#{window_id}:#{window_index}' | awk -F: -v idx="$na_idx" '$2==idx {print $1; exit}'
echo "BUG (active filter) would return:"
tmux list-windows -t "=multi" -F '#{window_id}' -f '#{window_active}'
teardown_test
# Expected: the FIX's @id != the active filter's @id (they differ iff the
# highlighted window is non-active, which is the whole point).
```

## Final Validation Checklist

### Technical Validation

- [ ] `bash -n scripts/preview.sh` and `bash -n tests/test_preview.sh` clean.
- [ ] `shellcheck` on both files: 0 new findings.
- [ ] `preview_main` declares `w_sess w_idx`; branches on `opt_type`; the window
      branch resolves the `@id` by index via `awk` (NOT `#{window_active}`).
- [ ] The session-mode path is the EXISTING `#{window_active}` line (the `else`).
- [ ] `preview_fallback` builds `=$target:.` (token-aware); no bare `=$1:.` remains
      (Level 1 grep checks).
- [ ] NO change to any other script, `options.sh`/`state.sh`/`utils.sh`, or stored state.

### Feature Validation

- [ ] New test discovered and PASS; full `tests/run.sh` suite green (exit 0).
- [ ] Bug-reintroduction check: with the window branch disabled, the new test FAILS.
- [ ] Window mode: previewing a non-active window's token links THAT window's `@id`.
- [ ] Session mode: behavior byte-identical to before (unchanged `else` branch).
- [ ] The fallback target is well-formed in window mode (`=multi:1.`, rc=0).

### Code Quality Validation

- [ ] `w_sess w_idx` added to the existing `local` declaration; TABS; set -u-safe.
- [ ] Tests follow conventions: NO attach_test_client (client-independent), `local`
      vars, `new-window -a` + dynamic index/id detection, assert_eq + `|| fail`,
      TABS, no exit.
- [ ] Test appended at EOF (robust to parallel tasks; this file is exclusively
      this task's).
- [ ] Edits confined to preview.sh (1 local + if/else + fallback target) +
      test_preview.sh (1 test).

### Documentation & Deployment

- [ ] Inline comments note the window-mode index resolution + the fallback
      target fix (Mode A — internal; no user-facing/config/API surface change).
- [ ] No README/CHANGELOG edit in this subtask (the cross-cutting doc sync is
      P1.M3.T1.S1; preview is internal and no option/config surface changes).

---

## Anti-Patterns to Avoid

- ❌ Don't use `-f '#{window_index} == N'` to filter by index — it expands to
  non-empty text for every window → always truthy → returns ALL windows
  (bugfix_findings §External research item 3; research FINDING 3). List all
  windows and match the index field in `awk`.
- ❌ Don't change the session-mode path — it is the UNCHANGED `else` branch (the
  existing `#{window_active}` line). Session-mode behavior must be byte-identical.
- ❌ Don't touch the duplicate guard / unlink / link-window / select-window /
  set_state — they operate on the `@id` handle and are correct UNCHANGED once
  `src_id` resolves to the right window (research FINDING 10).
- ❌ Don't leave `preview_fallback` using `=$1:.` — it is MALFORMED for a token
  (`=multi:1:.` → "can't find window 1:"). Reparse to `=$w_sess:$w_idx.`
  (research FINDING 6/7).
- ❌ Don't hardcode a window index or id in the test — `base-index` is inherited
  from `~/.tmux.conf` (0 or 1) and window ids are global/creation-ordered. Use
  `new-window -t multi -a` and detect the non-active window dynamically
  (research FINDING 1/2). The contract's literal `new-window -t multi -n secondwin`
  FAILS on base-index=1.
- ❌ Don't assume the "second" window is non-active — `new-window` makes the NEW
  window active. Detect the non-active window by `#{window_active}==0`.
- ❌ Don't forget to set `@livepicker-type window` in the test — `opt_type()`
  defaults to "session" and the window branch won't fire without it.
- ❌ Don't add `attach_test_client` — preview.sh is client-independent (reads
  `@livepicker-orig-session` via get_state, not display-message) (research FINDING 9).
- ❌ Don't `exit`/return-nonzero from a test body — signal failure ONLY via
  `fail()`/`assert_*` (run.sh reads `TEST_STATUS` in the current shell).
- ❌ Don't skip the "prove it catches the bug" step (Level 3) — a regression test
  that passes both before AND after the fix is worthless.
- ❌ Don't use spaces for indent — TABS only (match the file; shfmt absent).
- ❌ Don't use `[[ ]]` for the colon check — preview.sh uses POSIX-ish `[ ]`; use
  the portable `"${S%%:*}" != "$S"` idiom (research FINDING 5).

---

## Confidence Score

**9 / 10** for one-pass success. Rationale: the fix is a single `if/else` wrapping
the existing `src_id=` line (window branch = a 3-line token-parse + an `awk`
index match; else branch = the unchanged `#{window_active}` line) plus a
token-parse in `preview_fallback`. Every load-bearing behavior is **live-proven**
on 3.6b: the `awk` index→`@id` resolution returns the correct non-active window
(FINDING 3); the buggy `#{window_active}` filter ignores the index (FINDING 4);
the token split mirrors the already-proven confirm branch (FINDING 5); the
malformed `=$1:.` fallback target is confirmed broken and the `=$w_sess:$w_idx.`
form confirmed working (FINDING 6/7); the rest of preview_main operates on the
`@id` handle and is unchanged (FINDING 10). The regression test's two subtleties
are both explicitly verified: (a) the `base-index`-inherited gotcha defeats the
contract's literal setup commands → the test uses `-a` + dynamic detection
(FINDING 1/2); (b) `new-window` makes the new window active → the test detects the
non-active window by `#{window_active}==0`. The test is a near-clone of the
existing `test_multipane_preview` pattern (lp_preview_seed_state + direct
preview.sh call + assert @livepicker-linked-id), needs no attached client, and the
`sed`-revert "prove-it-catches-the-bug" check (Level 3) deterministically proves it
guards this regression. Disjoint from the parallel P1.M2.T1.S1 (renderer.sh +
test_functional.sh) — no shared file. Residual risk: an `edit`-tool `oldText`
mismatch due to tab/whitespace or the exact surrounding comment block — mitigated
by the verbatim old→new pairs in Implementation Patterns and the Level 1 grep
post-checks.
