# PRP — Bugfix P1.M2.T1.S1: escape `#`→`##` for candidate names + filter query in renderer.sh + regression test (Issue 3)

> **Bug context**: This is Issue 3 (Minor) from the adversarial QA pass
> (`plan/001_fd5d622d3939/bugfix/001_15442f34c366/architecture/bugfix_findings.md`).
> `scripts/renderer.sh` emits user-controlled strings (candidate session/window
> names + the live filter query) **raw** into tmux `#[...]` format strings. tmux
> treats `#` as a format-specifier introducer (`#[...]=style`, `##=literal #`,
> `#(...)=shell`, `#{...}=format`), so a name like `#dev` is mis-interpreted and
> a name like `#[fg=red]x` injects styling. Session names CAN contain `#`
> (live-proven). The fix doubles every `#`→`##` (tmux's literal-`#` escape) at
> the 5 emission sites, on LOCAL copies only (stored state + `filter.sh` are
> untouched so confirm/nav keep resolving the real name).

---

## Goal

**Feature Goal**: Every user-derived string the renderer emits into a tmux format
string — candidate names (`${filtered[$i]}`) and the filter query (`$FILTER`) —
has each `#` doubled to `##` so tmux renders them **literally** instead of
interpreting them as format specifiers / style injections. The escaping is
confined to two `local` variables substituted at the 5 emission sites; stored
state, `filter.sh`, color config, and arithmetic are untouched.

**Deliverable**:
1. `scripts/renderer.sh` — add `local esc_name` + `local esc_filter` inside
   `render()`; substitute the escaped forms at all 5 emission sites (the empty-
   list query line ×2, the highlighted item segment, the normal item segment, the
   count-suffix query line).
2. `tests/test_functional.sh` — append two regression tests
   (`test_renderer_escapes_hash_in_names`, `test_renderer_escapes_hash_in_filter`),
   auto-discovered by `tests/run.sh`, that seed minimal `@livepicker-*` state and
   assert the renderer's stdout contains the **escaped** `##` form.

**Success Definition**:
- A session/window name containing `#` (e.g. `#dev`, `csharp#`, `C#-proj`) is
  emitted by the renderer as `##dev` / `csharp##` / `C##-proj` (every `#` doubled).
- A filter query containing `#` is emitted escaped in the `query> …` display
  (match branch: `query> ##dev [..]`; no-match branch: `query> ##zz (no match)`).
- `@livepicker-list` / `@livepicker-filter` / `@livepicker-index` are **not**
  modified by the renderer (escaping is local-copy-only → nav/confirm still
  resolve the real name; `filter.sh` unchanged).
- `tests/run.sh` reports both new tests PASS and the full suite stays green
  (no other test regresses — the change touches only two local vars in renderer.sh).
- Bug-reintroduction check: reverting the escaping makes both new tests FAIL.

## User Persona (if applicable)

**Target User**: The end user whose tmux sessions or windows are named with `#`
(e.g. `#dev` for a dev channel, `C#-proj`, `csharp#`). Also the maintainer / QA.

**Use Case**: The user activates the picker. One of their sessions is named
`#dev`. In the status-line list, `#dev` must render as the literal text `#dev`
(highlighted when current), not as `<format-expansion>` or with injected styling.

**Pain Points Addressed**: Today a `#` in a session name silently corrupts the
status-line rendering (the name is re-interpreted by tmux's format engine); a
malicious/quirky name like `#[fg=red]x` injects red styling into the whole line.
The fix makes names render literally and closes the format-injection vector.

## Why

- **Real, reachable bug.** Session names CAN contain `#` (live-proven: research
  FINDING 1 — `new-session -s "#dev"` + `has-session -t "=#dev"` both succeed).
  `@livepicker-list` is built from `list-sessions`, so a `#`-name WILL reach the
  renderer. The bug is not theoretical.
- **Format injection is the real risk.** `##` is the ONLY literal-`#` escape
  (live-proven: research FINDING 2 — `##dev` renders as literal `#dev` inside a
  styled segment, styling intact). A raw `#` lets the name's bytes be parsed as
  format specifiers (style injection via `#[...]`, or `<expansion>` via other
  `#X` sequences). The fix is the standard, documented tmux idiom for literal `#`.
- **Cheap, surgical, low-risk.** Two `local` parameter expansions
  (`${var//\#/##}`) substituted at 5 sites. No new function, no sourcing change,
  no driver change, no state change, no `filter.sh` change. The renderer's
  pure/fast/`set -u`-safe properties are preserved.
- **Isolated from confirm/nav.** Escaping is a LOCAL copy used only for display;
  the stored `@livepicker-list` and `lp_build_filtered`'s output keep the raw
  name, so `input-handler.sh` confirm/nav and `preview.sh` keep resolving the
  REAL session name (`#dev`, not `##dev`). (research FINDING 5.)
- **Closes a real test gap.** No existing test exercises special characters in
  names (bugfix_findings §Testing Summary: "renderer robustness with special
  characters"). The two new tests guarantee this exact shape can't regress.

## What

1. **In `scripts/renderer.sh::render()`**: declare two `local` variables and
   compute their escaped values once, then use them at the 5 emission sites:
   - `local esc_filter="${FILTER//\#/##}"` — escape the query (use wherever the
     raw `$FILTER` was emitted: the empty-list `query>` lines and the count
     suffix `query>` line).
   - `local esc_name="${filtered[$i]//\#/##}"` — escape the current candidate
     name (use inside the item-segment loop, both the highlighted and normal
     branches).
2. **In `tests/test_functional.sh`**: append `test_renderer_escapes_hash_in_names`
   (seed `@livepicker-list="#dev"`, empty filter, index 0; assert stdout contains
   `##dev`) and `test_renderer_escapes_hash_in_filter` (assert the query display
   is escaped in BOTH the match branch `query> ##dev` and the no-match branch
   `query> ##zz`).
3. **Do NOT escape**: the code-authored `#[fg=...]`/`#[default]` tokens, the
   `$FG`/`$BG`/`$HFG`/`$HBG` color values (PRD §11 config; may be `#ffffff` hex —
   correct inside the attribute list), `$TOTAL`, `$FLEN`, `$((cidx + 1))`.

### Success Criteria

- [ ] `renderer.sh` declares `local esc_filter` and `local esc_name`; both
      computed via `${var//\#/##}` before use.
- [ ] The 5 emission sites use the escaped forms: empty-list query (×2) use
      `$esc_filter`; item segment (highlighted + normal) uses `$esc_name`;
      count-suffix query uses `$esc_filter`.
- [ ] NO change to `$FG`/`$BG`/`$HFG`/`$HBG`/`$TOTAL`/`$FLEN`/`$((cidx+1))`
      (these stay raw — they are code-authored, not user data).
- [ ] NO change to `filter.sh`, `@livepicker-*` stored state, or any other file.
- [ ] `bash -n` + `shellcheck` clean on `renderer.sh` and `test_functional.sh`.
- [ ] `tests/run.sh`: both new tests PASS, full suite green (exit 0).
- [ ] Bug-reintroduction check: revert the escaping → both new tests FAIL.

## All Needed Context

### Context Completeness Check

_Pass_: A developer who has never seen this repo can implement the fix from
(a) the exact 5 emission sites (quoted with current line numbers + code),
(b) the verbatim two-line escape + the verbatim test bodies (below), and
(c) the load-bearing "escape ONLY user-derived strings" + "assert the POSITIVE
`##` form" rules (all live-proven in research/renderer_hash_escape_findings.md).
No tmux-internals inference is required.

### Documentation & References

```yaml
# MUST READ — the bug report (root-cause + the 5 sites + the escape rule)
- docfile: plan/001_fd5d622d3939/bugfix/001_15442f34c366/architecture/bugfix_findings.md
  why: §ISSUE 3 lists the 5 exact sites (lines 78, 80, 94, 96, 107) with the raw
       user strings, the root cause (tmux `#` = format introducer; `##` = literal),
       and the fix directive ("escape # -> ## ... do NOT escape stored state ...
       filter.sh preserves original bytes"). §External tmux research confirms
       `##` is the ONLY literal-`#` escape and `#` is legal in session names.
  critical: The escape must NOT touch filter.sh or stored state — confirm/nav
            resolve the REAL name (#dev), not the escaped one (##dev).

# MUST READ — the empirical ground-truth for THIS fix (10 live-verified findings)
- docfile: plan/001_fd5d622d3939/bugfix/001_15442f34c366/P1M2T1S1/research/renderer_hash_escape_findings.md
  why: FINDING 1 (session names CAN contain # — live-proven); FINDING 2 (## is
       the ONLY literal-# escape; ##dev renders as literal #dev inside a styled
       segment — live-rendered + SGR-decoded); FINDING 3 (${var//\#/##} works for
       every edge case — verified table); FINDING 4 (the exact 5 sites + the
       DO-NOT-ESCAPE list incl. the hex-color gotcha); FINDING 5 (filter.sh keeps
       raw bytes — do not change); FINDING 6 (CRITICAL: assert the POSITIVE ##dev,
       NOT a negative #dev — ##dev CONTAINS #dev so a negative check false-fails);
       FINDING 7 (test needs NO attach_test_client — renderer is client-independent);
       FINDING 9 (append to test_functional.sh, auto-discovered); FINDING 10 (no
       conflict with the parallel P1.M1.T2.S1 — append at EOF).
  critical: FINDING 6 is the single most important test-design rule — a naive
            `! assert_contains "$out" "#dev"` FALSE-FAILS after the fix.

# MUST READ — the file being modified (the 5 sites)
- file: scripts/renderer.sh
  why: Contains render() with the 5 emission sites. The fix adds 2 local vars and
        substitutes them at the 5 sites. The rest (sourcing, strictness, driver,
        mapfile, filter, clamp, #[default] resets) is UNCHANGED.
  pattern: the item loop builds seg="#[fg=$HFG,bg=$HBG]${filtered[$i]}#[default]"
           (highlighted) / seg="#[fg=$FG,bg=$BG]${filtered[$i]}#[default]" (normal);
           the query lines interpolate $FILTER. Swap ${filtered[$i]}->$esc_name
           and $FILTER->$esc_filter at those 5 points ONLY.
  gotcha: $FG/$BG/$HFG/$HBG may be #ffffff (hex). Do NOT escape them — they are
          config color specs inside #[fg=...], correct as-is.

# MUST READ — what NOT to change (filter.sh keeps the raw name)
- file: scripts/filter.sh
  why: lp_build_filtered prints the ORIGINAL $name (lowercases only for MATCHING;
        emits the raw name). This is correct: confirm/nav/preview resolve the REAL
        name. Escaping belongs ONLY in renderer.sh at emission, on a local copy.
  critical: Do NOT modify filter.sh. Do NOT escape in stored @livepicker-list.

# MUST READ — the test file + the pattern to mirror
- file: tests/test_functional.sh
  why: test_typing_filters already captures renderer output via
        `out="$("$LIVEPICKER_SCRIPTS/renderer.sh")"` then assert_contains — the
        EXACT pattern the new tests mirror. Also documents the CONTRACT: test
        bodies signal failure ONLY via fail()/assert_* (never exit); local for
        all vars; TABS; set -u inherited.
  critical: The renderer test does NOT call attach_test_client (renderer is
            client-independent — it only reads @livepicker-* options).

# MUST READ — the assertion helpers in scope inside test bodies
- file: tests/helpers.sh
  why: assert_contains str sub msg uses `case` with "$sub" QUOTED (literal match,
        glob specials disabled) — robust for the `##`/`#` substrings. fail msg
        sets TEST_STATUS (run.sh reads it in the current shell).
  critical: assert_contains "$out" "##dev" is the operative positive assertion.

# MUST READ — how tests are discovered + the per-test socket cycle
- file: tests/run.sh
  why: Auto-discovers every test_* via `compgen -A function | grep '^test_'`; per
        test runs setup_test "lp-$$-<name>" (fresh isolated socket + PATH shim +
        baseline fixtures) -> resets TEST_STATUS=pass -> runs the test in the
        CURRENT shell -> teardown_test. Adding a test_* fn to test_functional.sh
        is sufficient (no registration).
  critical: Never exit/return-nonzero from a test body — signal failure ONLY via
            fail()/assert_*.

# MUST READ — the isolation layer (what setup_test gives the test)
- file: tests/setup_socket.sh
  why: setup_test -> setup_socket: temp dir + PATH shim (bare `tmux` -> isolated
        -L socket) + baseline driver/alpha/beta fixtures + exports
        $LIVEPICKER_SCRIPTS / $TEST_DRIVER_SESSION. attach_test_client is OPTIONAL
        (not needed by the renderer test).

# Reference — PRD context for the bug
- docfile: PRD.md
  why: §10 (renderer draws the list), §16 (robustness / edge cases). The bug is a
        renderer-robustness gap; the fix makes names render literally.
  section: "§10 Status-line setup", "§16 Implementation risks"
```

### Current Codebase tree

```bash
tmux-livepicker/
  scripts/
    renderer.sh     # MODIFY: add local esc_name + esc_filter; substitute at the 5 sites
    filter.sh       # UNCHANGED (lp_build_filtered keeps raw bytes — do not touch)
    options.sh      # UNCHANGED (opt_fg/etc — color values NOT escaped)
    utils.sh        # UNCHANGED
    state.sh        # UNCHANGED (get_state/STATE_* — stored state NOT escaped)
    input-handler.sh, livepicker.sh, preview.sh, restore.sh, plugin.tmux  # UNCHANGED
                    # NOTE: P1.M1.T2.S1 (parallel) modifies input-handler.sh — DISJOINT from this task.
  tests/
    test_functional.sh  # MODIFY: append test_renderer_escapes_hash_in_names
                        #                + test_renderer_escapes_hash_in_filter
                        # NOTE: P1.M1.T2.S1 (parallel) also appends 2 tests here — append at EOF.
    run.sh, helpers.sh, setup_socket.sh  # UNCHANGED
    test_*.sh (others)  # UNCHANGED
```

### Desired Codebase tree with files to be added and responsibility of file

```bash
scripts/renderer.sh        # +2 local vars (esc_name, esc_filter); 5 substitutions; # in names/filter render literally
tests/test_functional.sh   # +2 test_ functions (names escaping; filter escaping) — close the special-char gap
```

### Known Gotchas of our codebase & Library Quirks

```bash
# CRITICAL (research FINDING 2): `##` is the ONLY literal-`#` escape in tmux
# format strings. A raw `#` in a user string is a format-injection vector
# (#[...] injects styling; other #X sequences expand). The fix doubles every #
# at emission. Verified live: `##dev` renders as literal `#dev` inside a styled
# #[...] segment, with styling intact.

# CRITICAL (research FINDING 4 + bugfix_findings): escape ONLY the two USER-DERIVED
# variables ($FILTER, ${filtered[$i]}). Do NOT escape:
#   - the code-authored #[fg=...]/#[default] tokens;
#   - $FG/$BG/$HFG/$HBG (PRD §11 config color values — may be #ffffff hex; correct
#     inside the #[fg=...] attribute list; escaping #ffffff->##ffffff would BREAK
#     the color spec);
#   - $TOTAL/$FLEN/$((cidx+1)) (numeric, no #).

# CRITICAL (research FINDING 5): do NOT change filter.sh or stored @livepicker-*
# state. lp_build_filtered prints the ORIGINAL name (lowercases only for matching);
# confirm/nav/preview resolve the REAL name (#dev). Escaping is a LOCAL copy used
# for display ONLY. If you escaped stored state, confirm would switch to a
# non-existent "##dev" session and break.

# CRITICAL (research FINDING 6 — TEST DESIGN): assert the POSITIVE escaped form
# (##dev), NOT a negative "#dev". The escaped "##dev" CONTAINS the substring
# "#dev", so `! assert_contains "$out" "#dev"` would FALSE-FAIL after the fix.
# Use: assert_contains "$out" "##dev" (absent before fix, present after).

# GOTCHA (research FINDING 3): the escape is ${var//\#/##} (global replace every
# # with ##). Handles leading/trailing/multiple/adjacent-# names and empty string
# (no-op). Verified for #dev, csharp#, C#-proj, a##b->a####b, ##->####, empty.

# GOTCHA (research FINDING 7): the renderer test does NOT need attach_test_client.
# renderer.sh is client-independent (reads @livepicker-* options via show-option;
# no switch-client/display-message/refresh-client). Seed the 3 options directly.

# GOTCHA (research FINDING 8): renderer.sh already has set -u (inherited) and
# NO set -e. The two new locals must be ASSIGNED before use (esc_name=...;
# esc_filter=...) to stay set -u-safe. No sourcing/strictness/driver change.

# GOTCHA (research FINDING 10): P1.M1.T2.S1 (parallel) ALSO appends tests to
# test_functional.sh. To avoid an edit collision, APPEND at the file's TRUE EOF
# (anchor the edit on the file's final lines, not on a named function that the
# parallel task may have moved past). The two new test_* names are distinct from
# the parallel task's, so discovery/order is unaffected.

# GOTCHA: the renderer reads $FILTER via get_state "$STATE_FILTER" "". An empty
# filter has no # -> esc_filter="" (no-op). A filter could contain # if set
# externally or via window-mode tokens (PRD §8 types a-z A-Z 0-9 -_. /, NOT #,
# but a pre-existing @livepicker-filter value could). Defensive escaping of
# $FILTER is correct and cheap — apply it.

# STYLE (system_context §9): indent with TABS (NOT 4-space). shfmt NOT installed;
# verify with `grep -Pn '^    '`. The new locals go at 1-tab indent inside
# render() (matching the existing local declarations); the substitutions keep
# their existing indent.
```

## Implementation Blueprint

### Data models and structure

No data-model change. The "model" is a display-only escape applied to local
copies of two user-derived variables, immediately before they are interpolated
into `#[...]` format segments:

```
render()
 ├─ read FILTER (raw)  ──► esc_filter = FILTER with every # -> ##   (display copy)
 ├─ read filtered[] (raw, from lp_build_filtered — UNCHANGED)
 │   └─ for each filtered[$i]:
 │        esc_name = filtered[$i] with every # -> ##                (display copy)
 │        seg = "#[fg=...]<esc_name>#[default]"                     (was: ${filtered[$i]})
 ├─ empty-list branch:  query> <esc_filter> (no match) ...          (was: $FILTER)
 └─ count suffix:       query> <esc_filter> [k/FLEN]                (was: $FILTER)
```

The raw `$FILTER` / `${filtered[$i]}` are NEVER emitted; only `esc_filter` /
`esc_name`. Stored state and `lp_build_filtered` output are untouched.

### Implementation Tasks (ordered by dependencies)

```yaml
Task 1: MODIFY scripts/renderer.sh — add the two escaped locals
  - LOCATE render()'s existing local declaration block (the line beginning
    `local out seg i cidx first`). Add esc_filter and esc_name to it, OR add a
    new `local esc_filter esc_name` line immediately after FILTER/filtered are
    available (esc_filter needs $FILTER; esc_name needs the loop).
  - esc_filter: place AFTER `FILTER="$(get_state "$STATE_FILTER" "")"` (line ~73),
    e.g. a new line:
        esc_filter="${FILTER//\#/##}"
    (assigned once; reused at 3 sites — lines 78, 80, 107.)
  - esc_name: place INSIDE the item loop, at the TOP of the `for i in ...` body
    (line ~92), BEFORE the highlighted/normal branch, e.g.:
        esc_name="${filtered[$i]//\#/##}"
    (recomputed per item; used in both branches — lines 94, 96.)
  - NAMING: esc_filter, esc_name (clear, short, _filter/_name mirror the source).
  - STYLE: TABS; `local` declared (set -u-safe). If folding into the existing
    `local out seg i cidx first` line, keep it one statement; else a separate
    `local esc_filter` near FILTER and `local esc_name` in the loop.
  - NO new sourcing; NO strictness change; NO driver change.

Task 2: MODIFY scripts/renderer.sh — substitute the escaped forms at the 5 sites
  - Site 1 (line 78, empty-list + show-count): replace $FILTER with $esc_filter:
        out="#[fg=$FG,bg=$BG]query> $esc_filter (no match) 0/$TOTAL#[default]"
  - Site 2 (line 80, empty-list, no count): replace $FILTER with $esc_filter:
        out="#[fg=$FG,bg=$BG]query> $esc_filter (no match)#[default]"
  - Site 3 (line 94, highlighted item): replace ${filtered[$i]} with $esc_name:
        seg="#[fg=$HFG,bg=$HBG]${esc_name}#[default]"
  - Site 4 (line 96, normal item): replace ${filtered[$i]} with $esc_name:
        seg="#[fg=$FG,bg=$BG]${esc_name}#[default]"
  - Site 5 (line 107, count-suffix query): replace $FILTER with $esc_filter:
        out="$out #[fg=$FG,bg=$BG]query> $esc_filter [$((cidx + 1))/$FLEN]#[default]"
  - DO NOT change anything else: #[fg=...]/#[default] tokens, $FG/$BG/$HFG/$HBG,
    $TOTAL, $FLEN, $((cidx + 1)), the printf '%s' emit, the render||fallback driver.

Task 3: MODIFY tests/test_functional.sh — APPEND the two regression tests at EOF
  - LOCATE: the file's TRUE end (after its last test_* function — currently
    test_window_confirm_lands_on_chosen_window, but the parallel task P1.M1.T2.S1
    may have appended after it; anchor on the final `}` / EOF, not a named fn).
  - APPEND test_renderer_escapes_hash_in_names + test_renderer_escapes_hash_in_filter
    (full bodies in "Implementation Patterns" below).
  - FOLLOW pattern: test_typing_filters (`out="$("$LIVEPICKER_SCRIPTS/renderer.sh")"`
    + assert_contains). NO attach_test_client (renderer is client-independent).
  - NAMING: test_renderer_escapes_hash_in_names, test_renderer_escapes_hash_in_filter.
  - DEPENDENCIES: setup_test (brings the isolated socket + $LIVEPICKER_SCRIPTS),
    assert_contains, fail — all in scope (run.sh sources helpers.sh + setup_socket.sh).
  - STYLE: TABS; local for all vars; set -u-safe; NO exit in the body (signal via
    fail/assert_*).
  - ASSERTION RULE (research FINDING 6): assert the POSITIVE escaped form (`##dev`,
    `query> ##dev`, `query> ##zz`) — NOT a negative `#dev` (which false-fails).

Task 4: VALIDATE (full harness; prove the tests catch the bug)
  - RUN: bash -n scripts/renderer.sh ; bash -n tests/test_functional.sh
  - RUN: shellcheck scripts/renderer.sh tests/test_functional.sh (expect clean)
  - RUN: tests/run.sh (expect: both new tests PASS, full suite green, exit 0)
  - PROVE-IT-CATCHES-THE-BUG: temporarily revert the escaping (e.g. sed the 5 sites
    back to raw $FILTER/${filtered[$i]}), run the suite, confirm the 2 new tests
    FAIL, then restore. (See Validation Loop §3.)
```

### Implementation Patterns & Key Details

**The two escapes (Task 1) — paste verbatim.** `esc_filter` near the FILTER read
(line ~73); `esc_name` at the top of the item loop (line ~92):

```bash
	FILTER="$(get_state "$STATE_FILTER" "")"
	esc_filter="${FILTER//\#/##}"   # display escape: every # -> ## (tmux literal-#)
```

```bash
	for i in "${!filtered[@]}"; do
		esc_name="${filtered[$i]//\#/##}"   # display escape: every # -> ##
		if [ "$i" -eq "$cidx" ]; then
			seg="#[fg=$HFG,bg=$HBG]${esc_name}#[default]"
		else
			seg="#[fg=$FG,bg=$BG]${esc_name}#[default]"
		fi
```

(The exact surrounding lines are quoted from the current renderer.sh; match the
file's existing content for the `edit` anchors. Add `esc_filter` and `esc_name` to
the existing `local` declaration line, OR add separate `local` lines — either is
shellcheck-clean as long as each is assigned before use.)

**The 5 substitutions (Task 2) — old → new:**

```bash
# Site 1 (line 78):
out="#[fg=$FG,bg=$BG]query> $FILTER (no match) 0/$TOTAL#[default]"
#  ->  out="#[fg=$FG,bg=$BG]query> $esc_filter (no match) 0/$TOTAL#[default]"

# Site 2 (line 80):
out="#[fg=$FG,bg=$BG]query> $FILTER (no match)#[default]"
#  ->  out="#[fg=$FG,bg=$BG]query> $esc_filter (no match)#[default]"

# Site 3 (line 94):
seg="#[fg=$HFG,bg=$HBG]${filtered[$i]}#[default]"
#  ->  seg="#[fg=$HFG,bg=$HBG]${esc_name}#[default]"

# Site 4 (line 96):
seg="#[fg=$FG,bg=$BG]${filtered[$i]}#[default]"
#  ->  seg="#[fg=$FG,bg=$BG]${esc_name}#[default]"

# Site 5 (line 107):
out="$out #[fg=$FG,bg=$BG]query> $FILTER [$((cidx + 1))/$FLEN]#[default]"
#  ->  out="$out #[fg=$FG,bg=$BG]query> $esc_filter [$((cidx + 1))/$FLEN]#[default]"
```

**Test bodies (Task 3) — copy verbatim; append at EOF of `tests/test_functional.sh`
(TAB indent to match the file):**

```bash
# test_renderer_escapes_hash_in_names — Bugfix Issue 3: a candidate name containing
# `#` must be emitted DOUBLED (`##`) so tmux renders it literally instead of
# interpreting it as a format specifier (#d=day, #[...]=style, ##=literal #). The
# renderer reads @livepicker-list/filter/index directly (client-independent: NO
# attach_test_client). Seeds the 3 options, runs renderer.sh, asserts the stdout
# contains the escaped `##dev` form (NOT the raw `#dev`). Before the fix this
# asserted substring is absent (test FAILS). NOTE: assert the POSITIVE `##dev`,
# not a negative `#dev` — `##dev` CONTAINS the substring `#dev`, so a negative
# check would FALSE-FAIL after the fix (research FINDING 6).
test_renderer_escapes_hash_in_names() {
	setup_test "lp-bug3-names"
	# `#` is a legal session name char (research FINDING 1) — create it to mirror
	# how activate's list-sessions would capture it.
	tmux new-session -d -s "#dev" -x 120 -y 40
	# Seed the minimal state the renderer reads (mirror lp_preview_seed_state,
	# inline). @livepicker-list holds the raw name (escaping is display-only).
	tmux set-option -g "@livepicker-list" "#dev"
	tmux set-option -g "@livepicker-filter" ""
	tmux set-option -g "@livepicker-index" "0"
	local out
	out="$("$LIVEPICKER_SCRIPTS/renderer.sh")"
	# POSITIVE assertion: the escaped form is present. (Highlighted item segment.)
	assert_contains "$out" "##dev" "renderer escaped # -> ## in the candidate name"
	# Sanity: stored state is UNCHANGED (escaping is display-only — confirm/nav
	# still resolve the real name). @livepicker-list must still be the raw #dev.
	assert_eq "$(tmux show-option -gqv @livepicker-list)" "#dev" \
		"renderer did NOT mutate stored @livepicker-list (escape is display-only)"
}

# test_renderer_escapes_hash_in_filter — Bugfix Issue 3 (filter half): the live
# query `$FILTER` is also emitted into the `query> …` display at 3 sites (empty-
# list no-match branch ×2, count-suffix match branch). A filter containing `#`
# must be escaped to `##` in BOTH branches. Exercises the match branch (filter
# `#dev`, list `#dev` -> query> ##dev [1/1]) and the no-match branch (filter
# `#zz`, list `#dev` -> query> ##zz (no match)). Asserts the POSITIVE escaped
# form `query> ##...` (research FINDING 6).
test_renderer_escapes_hash_in_filter() {
	setup_test "lp-bug3-filter"
	tmux new-session -d -s "#dev" -x 120 -y 40
	# --- match branch: filter `#dev` matches the `#dev` name ---
	tmux set-option -g "@livepicker-list" "#dev"
	tmux set-option -g "@livepicker-filter" "#dev"
	tmux set-option -g "@livepicker-index" "0"
	local out
	out="$("$LIVEPICKER_SCRIPTS/renderer.sh")"
	assert_contains "$out" "query> ##dev" \
		"renderer escaped # -> ## in the query (match branch, count suffix)"
	# --- no-match branch: filter `#zz` matches nothing ---
	tmux set-option -g "@livepicker-filter" "#zz"
	out="$("$LIVEPICKER_SCRIPTS/renderer.sh")"
	assert_contains "$out" "query> ##zz" \
		"renderer escaped # -> ## in the query (no-match branch)"
	assert_contains "$out" "(no match)" "no-match branch rendered the (no match) line"
}
```

Key pattern notes:
- **No `attach_test_client`** — the renderer reads `@livepicker-*` options only.
- `setup_test` brings the isolated socket + `$LIVEPICKER_SCRIPTS`; teardown is
  automatic (run.sh's per-test `teardown_test`).
- **Positive `##` assertions** everywhere (the negative `#dev` would false-fail).
- The names test also asserts stored `@livepicker-list` is UNCHANGED (proves the
  escape is display-only — confirm/nav still see the real `#dev`).

### Integration Points

```yaml
CODE:
  - file: scripts/renderer.sh
    change: "+local esc_filter (line ~73); +local esc_name (in item loop, ~92);
             5 substitutions (lines 78/80/94/96/107: $FILTER->$esc_filter,
             ${filtered[$i]}->$esc_name)"
    invariant: "user-derived strings (#-bearing names/queries) render literally;
                stored state + filter.sh + color config + arithmetic UNCHANGED"

TESTS:
  - file: tests/test_functional.sh
    change: "+test_renderer_escapes_hash_in_names, +test_renderer_escapes_hash_in_filter (append at EOF)"
    discovery: "auto via run.sh compgen -A function | grep '^test_'"

DATABASE / CONFIG / ROUTES: none.
```

## Validation Loop

### Level 1: Syntax & Style (Immediate Feedback)

```bash
cd /home/dustin/.config/tmux/plugins/tmux-livepicker
bash -n scripts/renderer.sh    && echo "OK: renderer syntax"
bash -n tests/test_functional.sh && echo "OK: test_functional syntax"
shellcheck scripts/renderer.sh tests/test_functional.sh
# Tabs-not-spaces sanity on the edited regions (shfmt NOT installed):
grep -nP '^ +' scripts/renderer.sh && echo "WARN: space-indent found (use tabs)" || echo "OK: tabs"
# Confirm the escape is present and applied at the 5 sites:
grep -c 'esc_filter' scripts/renderer.sh    # -> 4 (1 assign + 3 uses: lines 78/80/107)
grep -c 'esc_name'  scripts/renderer.sh     # -> 3 (1 assign + 2 uses: lines 94/96)
grep -c '\${filtered\[\$i\]}' scripts/renderer.sh  # -> 0 (raw name no longer emitted directly)
grep -c 'query> \$FILTER'   scripts/renderer.sh    # -> 0 (raw filter no longer emitted in query>)
# Expected: syntax clean; shellcheck 0 findings; esc_filter appears 4x, esc_name 3x;
# NO remaining raw ${filtered[$i]} or query> $FILTER emission.
```

### Level 2: Unit Tests (the regression tests)

```bash
cd /home/dustin/.config/tmux/plugins/tmux-livepicker
# Full hermetic suite (fresh isolated socket per test):
tests/run.sh
# Expected: test_renderer_escapes_hash_in_names + test_renderer_escapes_hash_in_filter
# print PASS, the existing tests stay green, exit 0.
# (If P1.M1.T2.S1 landed in parallel, its 2 preview-sync tests also pass.)
```

### Level 3: Prove the tests actually catch the bug (critical)

```bash
cd /home/dustin/.config/tmux/plugins/tmux-livepicker
# Snapshot the fixed renderer, then REVERT the escaping (raw $FILTER/${filtered[$i]}):
cp scripts/renderer.sh /tmp/renderer.fixed
# Revert all 5 sites to the raw (pre-fix) form:
sed -i 's/\$esc_filter/\$FILTER/g; s/\${esc_name}/${filtered[$i]}/g' scripts/renderer.sh
grep -c 'esc_' scripts/renderer.sh   # -> 0 (fully reverted)
tests/run.sh 2>&1 | grep -E 'renderer_escapes_hash'
# Expected: BOTH new tests FAIL (the escaped `##dev` / `query> ##...` substrings
# are absent because the renderer emits the raw single-# form).
# Restore the fix:
cp /tmp/renderer.fixed scripts/renderer.sh
tests/run.sh 2>&1 | grep -E 'renderer_escapes_hash'
# Expected: BOTH new tests PASS again.
# If a test PASSES even when reverted, it is not exercising the escape path
# (re-check the seed values + the positive `##` assertion).
```

### Level 4: Live render spot-check (optional, manual — confirms visual correctness)

```bash
cd /home/dustin/.config/tmux/plugins/tmux-livepicker
# Manual repro on an isolated socket with a real pty client (mirrors bugfix_findings
# §ISSUE 3 repro + research FINDING 2 proof, now with the FIXED renderer):
source tests/setup_socket.sh; source tests/helpers.sh
setup_test "lp-bug3-live"; attach_test_client
tmux switch-client -t "=driver" >/dev/null
tmux new-session -d -s "#dev" -x 120 -y 40
tmux set-option -g "@livepicker-list" "#dev"
tmux set-option -g "@livepicker-filter" ""
tmux set-option -g "@livepicker-index" "0"
# Install the renderer on line 1 (mimics activate's status-format[0] install):
tmux set-option -g status on
tmux set-option -g status-format[0] "#($(pwd)/scripts/renderer.sh)"
tmux set-option -g status-left ''; tmux set-option -g status-right ''
tmux set-option -g window-status-format ''; tmux set-option -g window-status-current-format ''
tmux refresh-client -S; sleep 0.3
echo "renderer stdout (the format string):"
scripts/renderer.sh | cat -v
echo "rendered line 1 (must show literal '#dev', styled):"
tmux capture-pane -p -t driver | sed -n '1p' | sed 's/ *$//'
teardown_test
# Expected: stdout contains `##dev` (escaped); the rendered terminal line shows
# the LITERAL `#dev` (tmux collapsed ##->#), styled. Before the fix the terminal
# would show a format-expansion of `#dev` (or injected styling).
```

## Final Validation Checklist

### Technical Validation

- [ ] `bash -n scripts/renderer.sh` and `bash -n tests/test_functional.sh` clean.
- [ ] `shellcheck` on both files: 0 new findings.
- [ ] `renderer.sh` declares `esc_filter` + `esc_name` (both assigned before use).
- [ ] The 5 emission sites use the escaped forms; NO raw `${filtered[$i]}` or
      `query> $FILTER` remains (Level 1 grep checks).
- [ ] `$FG`/`$BG`/`$HFG`/`$HBG`/`$TOTAL`/`$FLEN`/`$((cidx+1))` UNCHANGED (not escaped).
- [ ] `filter.sh`, `state.sh`, stored `@livepicker-*` UNCHANGED.

### Feature Validation

- [ ] Both new tests discovered and PASS; full `tests/run.sh` suite green (exit 0).
- [ ] Bug-reintroduction check: with the escaping reverted, both new tests FAIL.
- [ ] A `#`-bearing name (`#dev`) renders literally (`##dev` in the format string;
      literal `#dev` on the terminal).
- [ ] A `#`-bearing filter query is escaped in both the match and no-match branches.
- [ ] Stored `@livepicker-list` is NOT mutated by the renderer (display-only escape).

### Code Quality Validation

- [ ] Two locals mirror the existing `local` style; TABS; set -u-safe.
- [ ] Tests follow conventions: NO attach_test_client (renderer is client-independent),
      `local` vars, assert_contains with POSITIVE `##` substrings, TABS, no exit.
- [ ] Tests appended at EOF (robust to the parallel P1.M1.T2.S1 also appending).
- [ ] Edits confined to renderer.sh (2 locals + 5 subs) + test_functional.sh (2 tests).

### Documentation & Deployment

- [ ] Inline comments note the `#`→`##` display escape (Mode A — internal; the
      rendered output is visually identical for names without `#`).
- [ ] No README/CHANGELOG edit in this subtask (the cross-cutting doc sync is
      P1.M3.T1.S1; README has no `#`-escaping surface to document).

---

## Anti-Patterns to Avoid

- ❌ Don't escape the code-authored `#[fg=...]`/`#[default]` tokens or the color
  variables `$FG`/`$BG`/`$HFG`/`$HBG` — those are config color specs (may be
  `#ffffff` hex); escaping `#ffffff`→`##ffffff` BREAKS the color. Escape ONLY the
  two user-derived variables (`$FILTER`, `${filtered[$i]}`) (research FINDING 4).
- ❌ Don't change `filter.sh` or stored `@livepicker-list`/`@livepicker-filter` —
  `lp_build_filtered` and confirm/nav/preview must keep resolving the REAL name
  (`#dev`). Escaping is a LOCAL display copy (research FINDING 5).
- ❌ Don't assert a NEGATIVE `#dev` in the regression test — `##dev` CONTAINS the
  substring `#dev`, so `! assert_contains "$out" "#dev"` FALSE-FAILS after the
  fix. Assert the POSITIVE `##dev` / `query> ##dev` (research FINDING 6).
- ❌ Don't add `attach_test_client` to the renderer tests — the renderer reads
  `@livepicker-*` options only and is client-independent (research FINDING 7).
- ❌ Don't escape `$TOTAL`/`$FLEN`/`$((cidx + 1))` — they are numeric (no `#`).
- ❌ Don't add new sourcing/strictness/driver logic to renderer.sh — the fix is
  exactly two `local` expansions + five substitutions, nothing else.
- ❌ Don't anchor the test-file edit on a named function (e.g. after
  `test_window_confirm_lands_on_chosen_window`) — the parallel task P1.M1.T2.S1
  may have moved the EOF. Anchor on the file's TRUE tail (research FINDING 10).
- ❌ Don't `exit`/return-nonzero from a test body — signal failure ONLY via
  `fail()`/`assert_*` (run.sh reads `TEST_STATUS` in the current shell).
- ❌ Don't skip the "prove it catches the bug" step (Level 3) — a regression test
  that passes both before AND after the fix is worthless.
- ❌ Don't use spaces for indent — TABS only (match the file; shfmt absent).

---

## Confidence Score

**9 / 10** for one-pass success. Rationale: the fix is two one-line bash parameter
expansions (`${var//\#/##}`) substituted at 5 precisely-located sites, with the
escape mechanism (`##`→literal `#`) and its applicability inside styled `#[...]`
segments both **live-proven** on 3.6b (research FINDINGS 1–3). The "escape only
user-derived strings / never color config or stored state" boundary is documented
with the hex-color gotcha (FINDING 4) and the filter.sh-unchanged contract
(FINDING 5). The regression-test design's single subtlety — assert the POSITIVE
`##dev`, not a negative `#dev` (which false-fails because `##dev` contains `#dev`)
— is explicitly verified (FINDING 6) and the assertion-discrimination is confirmed
for all three branches (name, filter-match, filter-no-match). The two tests are
near-clones of the existing `test_typing_filters` renderer-capture pattern, need
no attached client, and the `sed`-revert "prove-it-catches-the-bug" check
(Level 3) deterministically proves they guard this regression. Disjoint from the
parallel P1.M1.T2.S1 (input-handler.sh) except for a shared test-file append,
handled by the EOF-anchor guidance. Residual risk: an `edit`-tool `oldText`
mismatch due to tab/whitespace or the exact surrounding lines — mitigated by the
verbatim old→new pairs in Implementation Patterns and the Level 1 grep post-checks.
