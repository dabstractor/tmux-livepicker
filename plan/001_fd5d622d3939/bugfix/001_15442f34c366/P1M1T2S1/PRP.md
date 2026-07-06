# PRP — Bugfix P1.M1.T2.S1: shared preview-sync helper + wire into type/backspace/cancel-clear + regression test

> **Re-planning context**: This is Issue 2 (Major) from the adversarial QA pass
> (`plan/001_fd5d622d3939/bugfix/001_15442f34c366/architecture/bugfix_findings.md`).
> The live preview pane does NOT follow the status-line highlight when the user
> types, backspaces, or clears the query — only `next-session`/`prev-session`
> call `preview.sh`. This contradicts PRD §3 user story 3 ("the preview follows
> the top match") and the README ("The preview follows live"). The PRD's own §5
> data-flow diagram contradicts §3 (it lists type/backspace as "refresh status"
> only); this fix reconciles §5 in favour of §3 / the README.

---

## Goal

**Feature Goal**: The large live-preview pane stays in sync with the status-line
highlight whenever the query changes — typing a filter, backspacing, or pressing
cancel-to-clear all re-link the preview to the new **top filtered match** (index
0), exactly as `next-session`/`prev-session` already do. A shared helper
eliminates the 3× duplication of the nav resolution pattern.

**Deliverable**:
1. A new internal helper `_lp_sync_preview_to_top_match()` in
   `scripts/input-handler.sh` (placed after `_confirm_land_on_session`, before
   `input_main`).
2. Three call sites inserted into the `type`, `backspace`, and `cancel`
   query-clear branches (after `set_state "$STATE_INDEX" "0"`, before
   `tmux refresh-client -S`).
3. Updated inline comments in the `backspace` branch (the stale "known minor UX
   gap" note) and `type`/`cancel` branches documenting the now-correct sync.
4. Two regression tests in `tests/test_functional.sh`
   (`test_preview_follows_type_filter`, `test_preview_follows_backspace`),
   auto-discovered by `tests/run.sh`.

**Success Definition**:
- After typing a filter that uniquely matches a non-current session, `@livepicker-linked-id`
  equals that session's active window id (FAILS today — it stays `""`).
- After backspace-to-clear, `@livepicker-linked-id` re-syncs to the top of the
  full list (FAILS today — it stays frozen on the last-typed match).
- `tests/run.sh` reports both new tests PASS and the full suite stays green (no
  other test regresses — the change adds a preview call to 3 branches that
  previously had none; it touches no nav/confirm/cancel-teardown logic).

## User Persona (if applicable)

**Target User**: The end user browsing sessions. Also the maintainer / QA.

**Use Case**: The user activates the picker and types `log` to filter; the large
preview area below the status bar must show the panes of the top-matching session
in real time, staying aligned with the highlighted list entry.

**Pain Points Addressed**: The highlight and the preview desync on every
keystroke — the user sees the highlight move but the preview stays frozen until
they press a nav key. This makes the picker feel broken and contradicts the
README's explicit "the preview follows live" promise.

---

## Why

- **User-visible correctness bug.** PRD §3 story 3 and the README both require the
  preview to follow the top match on filter changes. The shipped code only follows
  on nav. This is the single most-visible defect after the Issue-1 data-loss bug.
- **Cheap, isolated, low-risk fix.** The resolution pattern already exists
  verbatim in `next-session`/`prev-session` (lines ~216/~235). Extracting it into
  a helper and calling it from 3 more branches is a mechanical, well-understood
  change. preview.sh's link/select is the SAME operation nav performs — it is
  proven safe (Invariant A: never fires `client-session-changed`).
- **Closes a real test gap.** No existing test asserts the preview tracks the
  highlight on `type` (bugfix_findings §Testing Summary). The new regression tests
  guarantee this exact shape can't regress.
- **Reconciles a PRD contradiction.** §5 (data-flow) vs §3 (user story) disagree.
  The fix chooses §3 / the README — the user-facing, documented behaviour.

## What

1. **The helper**: `_lp_sync_preview_to_top_match()` reads `@livepicker-list` +
   `@livepicker-filter`, runs `lp_build_filtered` (the SAME function the renderer
   uses → `filtered[0]` is provably the highlighted session), and — if the list is
   non-empty — calls `preview.sh "${filtered[0]}" 2>/dev/null || true` (index 0
   because type/backspace/cancel-clear always reset `@livepicker-index` to 0).
   Empty list → skip (leave the prior preview, mirroring nav's
   `[ "$L" -eq 0 ] && return 0` guard).
2. **The call sites**: insert `_lp_sync_preview_to_top_match` between
   `set_state "$STATE_INDEX" "0"` and `tmux refresh-client -S` in the `type`,
   `backspace`, and `cancel` query-clear branches.
3. **The comments**: rewrite the `backspace` "known minor UX gap" comment; lightly
   update `type` and `cancel` comments to state the preview now syncs.
4. **The tests**: `test_preview_follows_type_filter` (type `blog` → linked-id ==
   blog's window) + `test_preview_follows_backspace` (type `blog`, backspace to
   clear → linked-id re-syncs to the top of the full list).

### Success Criteria

- [ ] `_lp_sync_preview_to_top_match` defined after `_confirm_land_on_session`,
      before `input_main`; mirrors the nav resolution (lp_build_filtered + index 0
      + `preview.sh … 2>/dev/null || true`).
- [ ] Helper called in the `type`, `backspace`, and `cancel` query-clear branches,
      each AFTER `set_state "$STATE_INDEX" "0"` and BEFORE `tmux refresh-client -S`.
- [ ] `backspace` "known minor UX gap" comment rewritten; nav/confirm/cancel-teardown
      logic otherwise UNCHANGED.
- [ ] `bash -n` + `shellcheck` clean on `input-handler.sh` and `test_functional.sh`.
- [ ] `tests/run.sh`: both new tests PASS, full suite green (exit 0).
- [ ] With the helper temporarily neutered (e.g. `return 0` at its top), the new
      tests FAIL (proving they guard this regression).

## All Needed Context

### Context Completeness Check

_Pass_: The implementer needs (a) the verbatim helper body (below), (b) the
content-based edit anchors (NOT line numbers — they drift, see Gotchas), (c) the
nav pattern to mirror (quoted), and (d) the verbatim test bodies (below). No
inference about tmux internals is required.

### Documentation & References

```yaml
# MUST READ — the bug report (root-cause + repro + the nav pattern template)
- docfile: plan/001_fd5d622d3939/bugfix/001_15442f34c366/architecture/bugfix_findings.md
  why: §ISSUE 2 gives the exact location (type 127-152 / backspace 159-184 / cancel-clear
       339-359 all set filter+index+refresh but NO preview.sh; only nav at 216/235 does),
       the nav resolution pattern to mirror, and the PRD §3-vs-§5 reconciliation.
  critical: The fix reconciles PRD §5 in favour of §3 / the README. Do NOT "preserve
            §5" — the user-facing behaviour and the docs require the preview to follow.

# MUST READ — exact edit anchors + the verbatim helper body + test design
- docfile: plan/001_fd5d622d3939/bugfix/001_15442f34c366/P1M1T2S1/research/preview_sync_findings.md
  why: §1 gives current line numbers + the DRIFT CAVEAT (parallel task P1.M1.T1.S1
       deletes a line at ~301, shifting the cancel branch). §2 gives CONTENT anchors.
       §3 is the verbatim helper. §5 lists the comments to update. §6 is the test design.
  critical: Anchor every edit by CONTENT (the set_state INDEX 0 + refresh pair), NOT
            by line number — the cancel branch line numbers shift after T1.S1 lands.

# MUST READ — the file being modified
- file: scripts/input-handler.sh
  why: The helper goes after _confirm_land_on_session (~line 79-119) and before
        input_main (~line 121). The 3 call sites are in the type/backspace/cancel
        branches. The nav branches (next/prev) are the REFERENCE implementation.
  pattern: next-session does: mapfile -t filtered < <(lp_build_filtered "$cur_list" "$cur_filter");
           target="${filtered[$new_idx]}"; "$CURRENT_DIR/preview.sh" "$target" 2>/dev/null || true;
           tmux refresh-client -S 2>/dev/null || true
  gotcha: $CURRENT_DIR is a module-level global (set ~line 57) — in scope inside the
          helper (same as _confirm_land_on_session uses "$CURRENT_DIR/restore.sh").
          filter.sh + state.sh are already sourced at the top of input-handler.sh.

# MUST READ — what preview.sh does when called (confirms safety)
- file: scripts/preview.sh
  why: argv[1] = candidate session name; links its active window into the driver,
        select-window it (all panes render live), tracks @livepicker-linked-id. The
        SAME operation nav performs. Self-session case clears linked_id (no link).
  critical: Calling preview.sh from type/backspace is provably safe — it NEVER fires
            client-session-changed (Invariant A). It fires session-window-changed
            (suppressed globally by activate P1.M4.T4.S2). No new side effects vs nav.

# MUST READ — the shared filter function (the load-bearing sync guarantee)
- file: scripts/filter.sh
  why: lp_build_filtered LIST FILTER — the EXACT function renderer.sh AND nav use.
        Using it here guarantees filtered[0] == the session the status bar highlights.
  pattern: mapfile -t filtered < <(lp_build_filtered "$list" "$filter"); empty filter
           matches all (so cancel-clear's "" -> full list, top = first session).

# MUST READ — the state accessors + constants
- file: scripts/state.sh
  why: get_state "$STATE_LIST" "" / get_state "$STATE_FILTER" "" / STATE_LINKED_ID.
        set_state writes @livepicker-* runtime keys.

# MUST READ — the test to mirror (activate→type→assert pattern)
- file: tests/test_functional.sh
  why: test_typing_filters (creates syslog+blog BEFORE activate, types "log", asserts
        the filtered view) and test_nav_moves_selection (asserts @livepicker-linked-id
        == the target's dynamically-read window id) are the EXACT patterns. Both call
        attach_test_client first (livepicker.sh activate needs an attached client).
  critical: attach_test_client MUST be called before livepicker.sh. Window ids are
            GLOBAL — read the target's id DYNAMICALLY (tmux list-windows -t =blog -F
            '#{window_id}' -f '#{window_active}'), never hardcode.

# MUST READ — the test harness contract (how a new test gets discovered/run)
- file: tests/run.sh
  why: Auto-discovers every test_* function via compgen -A function | grep '^test_',
        runs each on a FRESH isolated socket (per-test setup_test/teardown_test),
        resets TEST_STATUS="pass" before each, prints PASS/FAIL, exits 0/1.
  critical: Test bodies MUST signal failure ONLY via fail()/assert_* (set TEST_STATUS);
            NEVER exit/return-nonzero-to-abort (run.sh reads TEST_STATUS in the CURRENT
            shell). Adding a test_* function to test_functional.sh is sufficient.

# Reference — the test helpers in scope inside test bodies
- file: tests/helpers.sh
  why: assert_eq a b msg, assert_contains str sub msg, fail msg, pass msg.
- file: tests/setup_socket.sh
  why: attach_test_client [sess] (spawns a script-pty client on the isolated socket);
        $LIVEPICKER_SCRIPTS, $TEST_DRIVER_SESSION (="driver"), setup_test/teardown_test.

# Reference — PRD contradiction this fix resolves
- docfile: PRD.md
  why: §3 user story 3 ("the preview follows the top match") vs §5 data-flow (lists
        type/backspace as "refresh status" only). The fix chooses §3.
  section: "§3 User stories" (story 3) and "§5 Architecture / data flow"
```

### Current Codebase tree

```bash
tmux-livepicker/
  scripts/
    input-handler.sh   # MODIFY: add _lp_sync_preview_to_top_match + 3 call sites + comment updates
    preview.sh          # UNCHANGED (called as-is; same as nav does)
    filter.sh           # UNCHANGED (lp_build_filtered reused)
    state.sh            # UNCHANGED (get_state/STATE_* reused)
    livepicker.sh       # UNCHANGED
    ...
  tests/
    test_functional.sh  # MODIFY: append test_preview_follows_type_filter + test_preview_follows_backspace
    run.sh              # UNCHANGED (auto-discovers the new test_*)
    helpers.sh          # UNCHANGED (assert_eq/attach_test_client reused)
    setup_socket.sh     # UNCHANGED (fixtures/client reused)
```

### Desired Codebase tree with files to be added and responsibility of file

```bash
scripts/input-handler.sh   # +1 helper, +3 call sites, updated comments; preview now follows the highlight
tests/test_functional.sh   # +2 test_ functions; close the "preview tracks type" gap
```

### Known Gotchas of our codebase & Library Quirks

```bash
# CRITICAL — LINE NUMBERS DRIFT. The parallel task P1.M1.T1.S1 deletes a duplicate
# restore.sh keep-window line at ~301 in the confirm branch, shifting the cancel
# branch (338+) up by 1. So do NOT anchor edits by line number. Anchor by CONTENT:
# each target branch has the pair
#     set_state "$STATE_INDEX" "0"
#     tmux refresh-client -S 2>/dev/null || true
# Insert the helper call BETWEEN them. Disambiguate the 3 occurrences via their
# branch-specific surrounding lines (see research §2).

# CRITICAL — $CURRENT_DIR is a module-level GLOBAL (set ~line 57, before any
# function def). It is in scope inside _lp_sync_preview_to_top_match (the helper
# is defined after that line and called from input_main). Do NOT re-resolve it;
# just use "$CURRENT_DIR/preview.sh" (same as _confirm_land_on_session uses
# "$CURRENT_DIR/restore.sh").

# CRITICAL — filter.sh + state.sh are ALREADY sourced at the top of
# input-handler.sh. lp_build_filtered, get_state, STATE_LIST, STATE_FILTER are all
# in scope inside the helper. Do NOT re-source anything.

# CRITICAL — the helper MUST use index 0 (filtered[0]), NOT the stored index.
# type/backspace/cancel-clear all reset @livepicker-index to 0 immediately before
# calling the helper, so the top match is ALWAYS filtered[0]. (nav uses
# filtered[$new_idx] because it moves the index; these branches reset it.)

# CRITICAL — empty filtered list (no matches) -> SKIP the preview call, leave the
# prior pane as-is. This mirrors nav's `[ "$L" -eq 0 ] && return 0` guard. Do NOT
# call preview.sh with an empty/"" argument (it would try to preview a non-existent
# session and fall through to capture-pane of nothing).

# CRITICAL — attach_test_client BEFORE livepicker.sh in the tests. activate uses
# lp_client_format (display-message) which needs an attached client. Without it,
# activate fails silently and @livepicker-list is never seeded.

# GOTCHA — window ids are GLOBAL and assigned dynamically. Read blog's active
# window id at test time via: tmux list-windows -t =blog -F '#{window_id}' -f '#{window_active}'.
# NEVER hardcode @N (the baseline fixtures + created sessions make ids non-@0).

# GOTCHA — the backspace variant's expected linked-id depends on list ORDER (the
# top of the full list after clearing the filter). Compute it DYNAMICALLY from
# @livepicker-list's first line; expected is "" if that session is the driver
# (self-session path clears linked_id), else that session's active window id.
# blog (created last) is never the top of the full list -> the bug (linked-id
# frozen on blog) deterministically FAILS the assertion.

# GOTCHA — test bodies run in the CURRENT shell under set -u. Every var MUST be
# declared local. NEVER exit from a test body — signal failure ONLY via fail()/assert_*.

# GOTCHA — calling preview.sh from type/backspace fires session-window-changed
# (select-window). This is ALREADY suppressed globally by activate P1.M4.T4.S2.
# It does NOT fire client-session-changed (Invariant A) -> zero session-history
# pollution. No new suppression is needed.

# GOTCHA — Indent with TABS (this whole codebase uses tabs; shfmt is NOT installed).
# The helper uses 0-indent for the def line, 1 tab for the body (matches
# _confirm_land_on_session). Call sites use the SAME indent as the surrounding
# branch lines (2 tabs inside input_main's case; 3 tabs inside cancel's if).

# GOTCHA — the type branch comment does NOT currently reference "the gap"; the
# backspace branch comment DOES ("a known minor UX gap that re-syncs on the next
# nav/confirm"). The backspace comment MUST be rewritten; the type/cancel comments
# should be lightly extended for accuracy (see research §5).
```

## Implementation Blueprint

### Data models and structure

No data-model change. The "model" is the preview-sync flow now shared across all
query-mutating actions:

```
query-mutating action (type | backspace | cancel-clear)
  ├─ update @livepicker-filter (append / trim / clear)
  ├─ set_state @livepicker-index 0
  ├─ _lp_sync_preview_to_top_match   ← NEW (re-link preview to filtered[0])
  │     ├─ get_state LIST, FILTER
  │     ├─ mapfile lp_build_filtered (SAME fn as renderer -> filtered[0] == highlight)
  │     ├─ empty? -> return (leave prior pane)
  │     └─ preview.sh filtered[0]   (link/select the top match; sets linked-id)
  └─ tmux refresh-client -S          (redraw the status bar / picker list)
```

### Implementation Tasks (ordered by dependencies)

```yaml
Task 1: MODIFY scripts/input-handler.sh — ADD the helper
  - LOCATE (by content): the closing `}` of _confirm_land_on_session, immediately
    followed by the comment `# argv[1] = action; argv[2] = the typed char ...` and
    `input_main() {`. Insert the helper BETWEEN them.
  - IMPLEMENT _lp_sync_preview_to_top_match() — paste the verbatim body from
    "Implementation Patterns" below (research §3).
  - NAMING: _lp_sync_preview_to_top_match (leading _ = internal helper; matches
    _confirm_land_on_session).
  - DEPENDENCIES: get_state, STATE_LIST, STATE_FILTER (state.sh — sourced);
    lp_build_filtered (filter.sh — sourced); $CURRENT_DIR (module global).
  - STYLE: 0-indent def line, 1-tab body; local for _list/_filt; local -a
    _sync_filtered=(); quote all expansions; the preview.sh call ends with
    `2>/dev/null || true` (mirror nav).
  - NO new sourcing; NO top-level side effects (it's a function def).

Task 2: MODIFY scripts/input-handler.sh — WIRE the 3 call sites (by content)
  - For EACH of type / backspace / cancel query-clear: find the pair
        set_state "$STATE_INDEX" "0"
        tmux refresh-client -S 2>/dev/null || true
    and insert ONE line between them:
        _lp_sync_preview_to_top_match
  - DISAMBIGUATE the 3 occurrences (each oldText must be UNIQUE):
      * type branch: include the preceding unique lines (e.g. the
        `set_state "$STATE_FILTER" "$new_filter"` + the comment above INDEX).
      * backspace branch: include the unique comment "(a known minor UX gap ...)"
        ABOVE the pair (this comment is ALSO rewritten in Task 3 — merge the two
        edits into ONE edit block to avoid overlap).
      * cancel query-clear: the pair is at 3-tab indent (inside the
        `if [ -n "$cur_filter" ]; then`) and preceded by `set_state "$STATE_FILTER" ""`
        (writes empty string) — unique vs type/backspace which write "$new_filter".
  - ORDER within branch is load-bearing: helper AFTER set_state INDEX 0, BEFORE
    refresh (so the link/select happens, THEN the status redraws — same order as nav).
  - DO NOT touch: nav (next/prev) branches, confirm branch, cancel-teardown path
    (the `restore.sh cancel` after the `if`). P1.M1.T1.S1 owns the confirm-branch
    duplicate-line fix; do not edit that region.

Task 3: MODIFY scripts/input-handler.sh — UPDATE the stale comments
  - backspace branch: rewrite the block
        # CONTRACT (work-item §3): backspace = filter+index+refresh ONLY.
        # It does NOT call preview.sh (FINDING 4) — the top match is already
        # shown; shortening the filter may re-admit a different top match
        # (a known minor UX gap that re-syncs on the next nav/confirm).
    to state that backspace now syncs the preview to the (possibly new) top match
    via _lp_sync_preview_to_top_match (PRD §3 / README "preview follows live";
    reconciles §5 in favour of §3). (Merge this rewrite with the Task-2 call-site
    insertion for this branch into ONE edit.)
  - type branch: lightly extend its comment to note the preview now follows the
    top match (it does not reference "the gap", so this is accuracy-only).
  - cancel query-clear: update its "Mirror backspace (T2.S1) exactly: set filter,
    set index=0, refresh" comment to note it ALSO re-syncs the preview to the
    (now-unfiltered) top match. (Merge with the Task-2 insertion here.)

Task 4: MODIFY tests/test_functional.sh — APPEND the 2 regression tests
  - LOCATE: end of file (after test_window_confirm_lands_on_chosen_window, for
    logical grouping near test_typing_filters / test_nav_moves_selection).
  - IMPLEMENT test_preview_follows_type_filter + test_preview_follows_backspace
    (full bodies in "Implementation Patterns" below; research §6).
  - FOLLOW pattern: test_typing_filters (syslog+blog before activate, type loop) +
    test_nav_moves_selection (assert linked-id == dynamic window id).
  - NAMING: test_preview_follows_type_filter, test_preview_follows_backspace.
  - DEPENDENCIES: attach_test_client, $LIVEPICKER_SCRIPTS, $TEST_DRIVER_SESSION,
    assert_eq, fail — all in scope (helpers.sh + setup_socket.sh sourced by run.sh).
  - STYLE: TABS for indent; local for all vars; set -u-safe; no exit in the body.

Task 5: VALIDATE (full harness; prove the tests catch the bug)
  - RUN: bash -n scripts/input-handler.sh ; bash -n tests/test_functional.sh
  - RUN: shellcheck scripts/input-handler.sh tests/test_functional.sh (expect clean)
  - RUN: tests/run.sh (expect: both new tests PASS, full suite green, exit 0)
  - PROVE-IT-CATCHES-THE-BUG: temporarily neuter the helper (insert `return 0` at
    its top), run the suite, confirm the 2 new tests FAIL, then restore. (See
    Validation Loop §3 for the one-liner.)
```

### Implementation Patterns & Key Details

**The helper (Task 1) — paste verbatim, placed after `_confirm_land_on_session`'s
closing `}` and before the `# argv[1] = action...` / `input_main()` block:**

```bash
# _lp_sync_preview_to_top_match — re-link the live preview to the TOP filtered
# match (index 0), so the preview pane tracks the status-line highlight when the
# user types / backspaces / clears the query (PRD §3 story 3 + README "the preview
# follows live"). Reconciles PRD §5 (which lists type/backspace as status-only) in
# favour of §3 / the README. Mirrors the nav (next/prev) resolution: same
# lp_build_filtered the renderer uses (so filtered[0] == the highlighted session),
# same preview.sh call + `2>/dev/null || true` guard. type/backspace/cancel-clear
# always reset @livepicker-index to 0, so the top match is ALWAYS filtered[0].
# Empty filtered list (no matches) -> skip the preview (leave the prior pane as-is,
# mirroring nav's `[ "$L" -eq 0 ] && return 0` guard).
_lp_sync_preview_to_top_match() {
	local _list _filt
	local -a _sync_filtered=()
	_list="$(get_state "$STATE_LIST" "")"
	_filt="$(get_state "$STATE_FILTER" "")"
	mapfile -t _sync_filtered < <(lp_build_filtered "$_list" "$_filt")
	[ "${#_sync_filtered[@]}" -eq 0 ] && return 0
	"$CURRENT_DIR/preview.sh" "${_sync_filtered[0]}" 2>/dev/null || true
}
```

**Call site (Task 2) — the shape in each of the 3 branches (indent matches the
branch; shown at 2-tab indent for type/backspace, 3-tab for cancel-clear):**

```bash
			set_state "$STATE_INDEX" "0"
			# Sync the live preview to the new top filtered match (PRD §3 / README;
			# mirror next/prev). Always index 0 — these branches just reset it.
			_lp_sync_preview_to_top_match
			tmux refresh-client -S 2>/dev/null || true
```

**Backspace comment rewrite (Task 3) — replace the stale block:**

```bash
			# CONTRACT: backspace trims the query and re-syncs the preview to the
			# (possibly new) top filtered match (PRD §3 story 3 + README "the
			# preview follows live"; reconciles PRD §5 in favour of §3). Shortening
			# the filter may re-admit a different top match -> _lp_sync_preview
			# re-links it so the preview pane stays aligned with the highlight.
```

**Test bodies (Task 4) — copy verbatim; append at EOF of `tests/test_functional.sh`
(TAB indent to match the file):**

```bash
# test_preview_follows_type_filter — Bugfix Issue 2: typing a filter must sync the
# live preview to the TOP filtered match (PRD §3 story 3 + README "the preview
# follows live"). Before the fix, type set filter+index+refresh but never called
# preview.sh -> the preview stayed frozen on the self-session (linked-id "") while
# the highlight moved. Mirror test_typing_filters (syslog+blog before activate) +
# test_nav_moves_selection (assert linked-id == dynamic window id).
test_preview_follows_type_filter() {
	attach_test_client
	# 'log'-matching fixtures BEFORE activate (the list is captured at activate time).
	tmux new-session -d -s syslog -x 120 -y 40
	tmux new-session -d -s blog   -x 120 -y 40
	"$LIVEPICKER_SCRIPTS/livepicker.sh"
	# Activate's first preview is the SELF-session (driver) -> no link yet.
	assert_eq "$(tmux show-option -gqv @livepicker-linked-id)" "" \
		"initial self-session preview leaves no link"
	# Type "blog" -> uniquely matches blog (no other session contains "blog").
	# Window ids are GLOBAL -> read blog's active id DYNAMICALLY.
	local blog_wid
	blog_wid="$(tmux list-windows -t =blog -F '#{window_id}' -f '#{window_active}')"
	local c
	for c in b l o g; do
		"$LIVEPICKER_SCRIPTS/input-handler.sh" type "$c" >/dev/null
	done
	# PRD §3: the preview follows the top match. Before the fix this stayed "" (FAIL).
	assert_eq "$(tmux show-option -gqv @livepicker-linked-id)" "$blog_wid" \
		"type filter synced the preview to the top match (blog)"
}

# test_preview_follows_backspace — Bugfix Issue 2 (backspace half): backspacing to
# clear the query must re-sync the preview to the top of the FULL list. Before the
# fix, backspace left the preview frozen on the last-typed match. The expected
# linked-id is computed DYNAMICALLY from @livepicker-list's first line (empty if it
# is the driver/self — the self-session path clears linked_id; else that session's
# active window id). blog (created last) is never the list's top -> the bug
# (linked-id frozen on blog) deterministically FAILS this assertion.
test_preview_follows_backspace() {
	attach_test_client
	tmux new-session -d -s syslog -x 120 -y 40
	tmux new-session -d -s blog   -x 120 -y 40
	"$LIVEPICKER_SCRIPTS/livepicker.sh"
	# Type "blog" -> preview synced to blog (proven by test_preview_follows_type_filter;
	# re-assert here as the starting point for the backspace sequence).
	local blog_wid c
	blog_wid="$(tmux list-windows -t =blog -F '#{window_id}' -f '#{window_active}')"
	for c in b l o g; do
		"$LIVEPICKER_SCRIPTS/input-handler.sh" type "$c" >/dev/null
	done
	assert_eq "$(tmux show-option -gqv @livepicker-linked-id)" "$blog_wid" \
		"starting point: type synced the preview to blog"
	# Backspace 4x -> filter cleared -> full list; index reset to 0.
	local i
	for i in 1 2 3 4; do
		"$LIVEPICKER_SCRIPTS/input-handler.sh" backspace >/dev/null
	done
	assert_eq "$(tmux show-option -gqv @livepicker-filter)" "" \
		"backspace cleared the filter"
	# The top match is now the FIRST session in the full list. Compute its expected
	# linked-id dynamically: "" if it is the driver (self-session clears linked_id),
	# else that session's active window id.
	local first_sess expected
	first_sess="$(printf '%s\n' "$(tmux show-option -gqv @livepicker-list)" | sed -n '1p')"
	if [ "$first_sess" = "$TEST_DRIVER_SESSION" ]; then
		expected=""
	else
		expected="$(tmux list-windows -t "=$first_sess" -F '#{window_id}' -f '#{window_active}')"
	fi
	# PRD §3: backspace re-syncs the preview. Before the fix linked-id stayed blog_wid
	# (FAIL, because blog is never the top of the full list).
	assert_eq "$(tmux show-option -gqv @livepicker-linked-id)" "$expected" \
		"backspace-to-clear re-synced the preview to the top of the full list"
}
```

Key pattern notes:
- `attach_test_client` FIRST — activate needs an attached client.
- Fixtures created BEFORE `livepicker.sh` (the list is captured at activate time).
- Window ids read DYNAMICALLY (global, non-deterministic); never hardcoded.
- The backspace variant's dynamic `expected` makes it robust to list ordering AND
  handles the contract's "(or self-session)" hedge.

### Integration Points

```yaml
CODE:
  - file: scripts/input-handler.sh
    change: "+_lp_sync_preview_to_top_match helper; +3 call sites (type/backspace/cancel-clear); comment updates"
    invariant: "every query-mutating action (type/backspace/cancel-clear/nav) now syncs the preview to the highlighted match"

TESTS:
  - file: tests/test_functional.sh
    change: "+test_preview_follows_type_filter, +test_preview_follows_backspace"
    discovery: "auto via run.sh compgen -A function | grep '^test_'"

DATABASE / CONFIG / ROUTES: none.
```

## Validation Loop

### Level 1: Syntax & Style (Immediate Feedback)

```bash
cd /home/dustin/.config/tmux/plugins/tmux-livepicker
bash -n scripts/input-handler.sh   && echo "OK: input-handler syntax"
bash -n tests/test_functional.sh   && echo "OK: test_functional syntax"
shellcheck scripts/input-handler.sh tests/test_functional.sh
# Tabs-not-spaces sanity on the edited regions (shfmt NOT installed):
grep -nP '^ +' scripts/input-handler.sh && echo "WARN: space-indent found (use tabs)" || echo "OK: tabs"
# Confirm the helper + 3 call sites are present:
grep -c '_lp_sync_preview_to_top_match' scripts/input-handler.sh   # -> 5 (1 def comment-block
                                                                   #    + 1 def + 3 call sites,
                                                                   #    adjust for comment mentions)
grep -nE '^\s*_lp_sync_preview_to_top_match$' scripts/input-handler.sh   # the 3 bare call sites
# Expected: syntax clean; shellcheck 0 findings; the helper defined once + called in 3 branches.
```

### Level 2: Unit Tests (the regression tests)

```bash
# Full hermetic suite (fresh isolated socket per test):
tests/run.sh
# Expected: test_preview_follows_type_filter + test_preview_follows_backspace print PASS,
# the existing 24 tests stay green, exit 0.
```

### Level 3: Prove the tests actually catch the bug (critical)

```bash
cd /home/dustin/.config/tmux/plugins/tmux-livepicker
# Temporarily NEUTER the helper (early return -> no preview sync, == the bug):
cp scripts/input-handler.sh /tmp/ih.fixed
# Insert `return 0` as the first statement of the helper body:
perl -0pi -e 's/(_lp_sync_preview_to_top_match\(\) \{\n)/$1\treturn 0\n/' scripts/input-handler.sh
grep -A1 '_lp_sync_preview_to_top_match() {' scripts/input-handler.sh   # confirm the early return
tests/run.sh 2>&1 | grep -E 'preview_follows_(type_filter|backspace)'
# Expected: BOTH new tests FAIL (linked-id stays "" on type; stays blog_wid on backspace).
# Restore the fix:
cp /tmp/ih.fixed scripts/input-handler.sh
tests/run.sh 2>&1 | grep -E 'preview_follows_(type_filter|backspace)'
# Expected: BOTH new tests PASS again.
# If a test PASSES even with the helper neutered, it is not exercising the sync path
# (re-check attach_test_client before livepicker.sh + the type loop + dynamic window id).
```

### Level 4: Cross-check the highlight/preview agreement (optional, manual)

```bash
# Manual repro on an isolated socket (mirrors bugfix_findings §ISSUE 2 repro):
cd /home/dustin/.config/tmux/plugins/tmux-livepicker
source tests/setup_socket.sh; source tests/helpers.sh
setup_test "lp-bug2"; attach_test_client
tmux switch-client -t "=driver" >/dev/null
tmux new-session -d -s syslog -x 120 -y 40
tmux new-session -d -s blog   -x 120 -y 40
scripts/livepicker.sh
for c in b l o g; do scripts/input-handler.sh type "$c"; done
echo "filter=[$(tmux show-option -gqv @livepicker-filter)] idx=[$(tmux show-option -gqv @livepicker-index)]"
echo "linked-id=[$(tmux show-option -gqv @livepicker-linked-id)]  (must == blog's window id now)"
echo "blog wid=[$(tmux list-windows -t =blog -F '#{window_id}' -f '#{window_active}')]"
teardown_test
# Expected after the fix: linked-id == blog's window id (non-empty). Before the fix: linked-id == "".
```

## Final Validation Checklist

### Technical Validation

- [ ] `bash -n scripts/input-handler.sh` and `bash -n tests/test_functional.sh` clean.
- [ ] `shellcheck` on both files: 0 new findings.
- [ ] `_lp_sync_preview_to_top_match` defined once; called in type/backspace/cancel-clear.
- [ ] Nav (next/prev), confirm, and cancel-teardown logic UNCHANGED (diff is confined
      to the 3 query-mutating branches + the new helper + comments).

### Feature Validation

- [ ] Both new tests discovered and PASS; full `tests/run.sh` suite green (exit 0).
- [ ] Bug-reintroduction check: with the helper neutered, both new tests FAIL.
- [ ] Typing a unique filter syncs `@livepicker-linked-id` to the top match's window.
- [ ] Backspace-to-clear re-syncs `@livepicker-linked-id` to the top of the full list.
- [ ] No `client-session-changed` pollution (Invariant A holds — preview.sh never switches).

### Code Quality Validation

- [ ] Helper mirrors the nav resolution (lp_build_filtered + index 0 + preview.sh guard).
- [ ] Edits anchored by CONTENT (not line number) — robust to P1.M1.T1.S1's drift.
- [ ] Stale "known minor UX gap" comment rewritten; type/cancel comments accurate.
- [ ] New tests follow conventions: attach_test_client first, local vars, assert_eq,
      dynamic window ids, TAB indent, set -u-safe, no exit in the body.
- [ ] Tests placed in tests/test_functional.sh next to their typing/nav siblings.

### Documentation & Deployment

- [ ] Inline comments updated to reflect "preview follows the highlight" (Mode A).
- [ ] No README change required here (the README already promises "the preview
      follows live" — the implementation now matches; the cross-cutting README/
      CHANGELOG sync is the final Mode B task P1.M3.T1.S1).
- [ ] Do NOT edit CHANGELOG/README in this subtask (plan splits doc sync into P1.M3).

---

## Anti-Patterns to Avoid

- ❌ Don't anchor edits by line number — P1.M1.T1.S1 (parallel) deletes a line at
  ~301, shifting the cancel branch. Anchor by CONTENT (the set_state INDEX 0 +
  refresh pair, disambiguated by surrounding unique lines).
- ❌ Don't duplicate the resolution block 3× — extract `_lp_sync_preview_to_top_match`
  once and call it. (The whole point of the helper is avoiding drift.)
- ❌ Don't use the stored `@livepicker-index` in the helper — these branches reset it
  to 0 immediately before the call, so the top match is ALWAYS `filtered[0]`. Using
  the stored index would race the just-written 0.
- ❌ Don't call `preview.sh ""` on an empty filtered list — guard
  `[ "${#_sync_filtered[@]}" -eq 0 ] && return 0` first (mirror nav).
- ❌ Don't touch the nav/confirm/cancel-teardown branches. P1.M1.T1.S1 owns the
  confirm-branch fix; nav already works; cancel-teardown (`restore.sh cancel`) is
  out of scope.
- ❌ Don't add a new suppression for `session-window-changed` — activate
  P1.M4.T4.S2 already suppresses it globally; preview.sh's select-window is covered.
- ❌ Don't `exit`/`return`-nonzero from a test body — signal failure ONLY via
  `fail()`/`assert_*` (run.sh reads TEST_STATUS in the current shell).
- ❌ Don't forget `attach_test_client` before `livepicker.sh` (activate needs a client).
- ❌ Don't hardcode window ids — read them dynamically (`list-windows -t =blog ...`).
- ❌ Don't use spaces for indent — TABS only (match the file; shfmt absent).
- ❌ Don't skip the "prove it catches the bug" step (Level 3) — a regression test
  that passes both before AND after the fix is worthless.
- ❌ Don't preserve PRD §5's "type/backspace = status-only" data-flow at the expense
  of §3/README — the fix deliberately reconciles in favour of the user-facing story.

---

## Confidence Score

**9 / 10** for one-pass success. Rationale: the resolution pattern already exists
verbatim in the nav branches (next/prev) and is proven safe (Invariant A); the
helper is a faithful generalization of it (always index 0); the call-site shape is
given verbatim with content-based anchors robust to the parallel task's line drift;
the two tests are near-clones of existing passing tests (test_typing_filters +
test_nav_moves_selection) with dynamic window-id reads and a dynamic expected-value
for the backspace variant that handles the self-session case; and the
"neuter-the-helper → tests FAIL" check (Level 3) deterministically proves the tests
guard this regression. Residual risk: an edit-tool `oldText` not matching exactly
due to tab/space mismatch — mitigated by the content-anchor guidance and the
grep-based post-edit verification in Level 1.
