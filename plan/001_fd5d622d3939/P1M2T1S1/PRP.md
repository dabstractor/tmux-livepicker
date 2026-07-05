# PRP — P1.M2.T1.S1: renderer.sh — filter, highlight, count, style emission

---

## Goal

**Feature Goal**: A pure, fast (`<50 ms`) **`#()` status-line renderer** at
`scripts/renderer.sh` that, on every tmux status redraw, reads the picker's
runtime state + config options, filters the session/window list by the query
(case-insensitive substring), and emits **exactly one** tmux-format string for
`status-format[0]`: the filtered items with the current one highlighted, plus an
optional `query> <filter> [pos/total]` count suffix. It performs **zero** tmux
mutations — it only reads options and prints one line. This is the status-line
picker subsystem (PRD §5 data flow: `scripts/renderer.sh` →
`#() status command: draw filtered list with highlight, query, count`), invoked
as `status-format[0] = #($SCRIPT_DIR/renderer.sh)` by activate (P1.M4.T3.S1) and
re-evaluated on every `refresh-client -S` (P1.M6).

**Deliverable**: The single executable file `scripts/renderer.sh`. A straight-line
Bash script (`#!/usr/bin/env bash`; `set -u`, **NO** `set -e`) that sources
`options.sh → utils.sh → state.sh` (in that order), reads the 3 runtime state
keys + 6 config options, builds one styled line in a string, prints it with
`printf '%s'` (no trailing newline), and `exit 0` unconditionally with a red
fallback echo on any error so the bar is never blanked.

**Success Definition**:
- `bash -n scripts/renderer.sh` passes; `shellcheck scripts/renderer.sh` is clean
  (0 findings; `source` directives resolve `get_opt`/`get_state`/`opt_*`).
- File is executable (`-rwxr-xr-x`) with shebang `#!/usr/bin/env bash`; tabs only.
- **Mock validation (normal path):** with a fake `tmux` serving a known
  `@livepicker-list`/`@livepicker-filter`/`@livepicker-index`, the renderer's
  stdout contains the highlighted item's name wrapped in `#[fg=$HFG,bg=$HBG]…
  #[default]`, the other items wrapped in `#[fg=$FG,bg=$BG]…#[default]`, the
  query, and `[idx+1/flen]` — and contains **no trailing newline** and **no
  embedded newline**.
- **Mock validation (empty-filter path):** empty filter → full list rendered,
  count `[1/N]` (idx defaults 0).
- **Mock validation (empty-list path):** empty list → `query>  (no match) 0/N`
  (or `[0/N]`), zero index-out-of-range errors.
- **Mock validation (clamp path):** index out of range (≥ flen) → highlight lands
  on `filtered[flen-1]`, no wrap.
- **Mock validation (error path):** forcing `main` to fail → stdout is the red
  fallback string and the process still `exit 0`s.
- **Live render spot-check (already proven, see research FINDING 1):** under a
  real pty client on an isolated socket, `status-format[0]=#(renderer.sh)` renders
  the items with `#[fg=,bg=]` styling applied and `#[default]` resetting both fg
  and bg between segments.

## User Persona (if applicable)

**Target User**: The tmux status-line formatter (the `#()` consumer) and,
transitively, the end user pressing keys in the picker. Mode A (internal output —
renderer output is internal; styled appearance documented in final README
P1.M8.T1.S1). No user-facing surface beyond the rendered line itself.

**Use Case**: The user has activated the picker (P1.M4). They type `log` and
press `C-M-Tab` to move down. Each input action (P1.M6) updates
`@livepicker-filter`/`@livepicker-index` and runs `tmux refresh-client -S`, which
forces a status redraw → tmux re-evaluates `status-format[0]` → runs
`#(renderer.sh)` fresh → the user sees the filtered, highlighted list + query +
count update within ~100 ms (PRD §16) / `<50 ms` (contract §1).

**User Journey**:
1. Activate → `@livepicker-list` = all sessions, `@livepicker-filter` = "",
   `@livepicker-index` = (current session's position). Renderer draws full list,
   current session highlighted, count `[k/N]`.
2. User types `l`, `o`, `g` → filter = "log"; input-handler resets index to top
   match → renderer draws the 3 matching sessions, top one highlighted, count
   `[1/3]`, query `log` shown.
3. User presses `C-M-Tab` twice → index advances within filtered list → renderer
   re-draws, now the 3rd match is highlighted, count `[3/3]`.
4. User types `zz` → no matches → renderer draws `query> logzz (no match) 0/N`.
5. Confirm/cancel (P1.M6) → restore (P1.M5) uninstalls `status-format[0]`; the
   renderer is no longer invoked.

**Pain Points Addressed**:
- (a) Without a renderer, `status-format[0] = #(renderer.sh)` would run a missing
  script → blank/error line 1. This is the literal "draw the picker" piece.
- (b) A renderer that emits a trailing newline, or multiple lines, would show
  only the last line (research FINDING 2 — **data loss**) — the contract's
  single-line + `printf '%s'` rule is the fix.
- (c) A renderer that does NOT reset styles with `#[default]` would leak the
  highlight color across items (research FINDING 1 — styles accumulate until
  reset).
- (d) A renderer that calls `set -e` would abort (rc≠0) on the first unset
  `@`-option read and blank the bar on every redraw where any option is unset
  (research FINDING 8).

## Why

- **The visible picker.** This is the sole user-visible surface of the whole
  plugin while active — every other P1.M2–M6 piece (preview, activate, restore,
  input-handler) is machinery; the renderer is what the user actually *sees*.
  PRD §5 data flow names it explicitly: `scripts/renderer.sh → #() status
  command: draw filtered list with highlight, query, count`. Without it the
  status bar's line 1 is blank/error during the picker.
- **Pure & fast by contract.** It runs as a `#()` status command on EVERY redraw
  (PRD §10; tmux_primitives.md §3). Every input action (P1.M6) forces a redraw
  via `refresh-client -S`, so a single keystroke can trigger dozens of
  renderer executions over a picker session. It MUST be pure (read options →
  print one line → exit; zero tmux mutations — mutating the server from a `#()`
  command is undefined/forbidden) and MUST be `<50 ms` or the status stutters
  (contract §1; research FINDING 7: ~40 ms on target). The default
  `status-interval` is 15 s, but the input handler forces sub-second redraws, so
  the renderer is the hot path.
- **Fail-safe by contract.** A renderer crash must NEVER blank the bar (contract
  §4). The `main || fallback; exit 0` shell (research FINDING 9) guarantees a
  visible (red) diagnostic on any error and rc=0 always — so a bug degrades to an
  ugly-but-present line, not a missing status line.
- **Foundation for M4 (activate).** `scripts/livepicker.sh` (P1.M4.T3.S1) sets
  `status-format[0] = #($CURRENT_DIR/scripts/renderer.sh)`. That step is a no-op
  until renderer.sh exists. This PRP unblocks the activate→status-install step
  and the input-handler redraw loop.
- **Boundary respect.** The renderer only READS `@livepicker-list` /
  `@livepicker-filter` / `@livepicker-index` (runtime, set by activate +
  input-handler) and the 6 config options (PRD §11). It writes nothing, so it
  cannot corrupt picker state or the saved-state contract (state.sh). It does
  not touch `@livepicker-mode`, `@livepicker-linked-id`, or any `@livepicker-orig-*`.

## What

A single executable Bash script at `scripts/renderer.sh` that:

1. Computes `CURRENT_DIR` (canonical idiom), sources `options.sh → utils.sh →
   state.sh` (that order — state.sh depends on utils.sh).
2. Defines a `render()` function (the body) that:
   - Reads config: `TYPE="$(opt_type)"`, `FG="$(opt_fg)"`, `BG="$(opt_bg)"`,
     `HFG="$(opt_highlight_fg)"`, `HBG="$(opt_highlight_bg)"`, and parses
     `SHOW_COUNT` from `opt_show_count` (on/off).
   - Reads runtime state: `LIST="$(get_state "$STATE_LIST" "")`,
     `FILTER="$(get_state "$STATE_FILTER" "")`,
     `IDX="$(get_state "$STATE_INDEX" "0")"`.
   - Reads the list into an array via **process substitution** (NOT here-string):
     `mapfile -t all < <(printf '%s' "$LIST")`. Captures `TOTAL=${#all[@]}`.
   - **Filters** case-insensitively into a second array `filtered[]`: keep entries
     where `${name,,}` contains `${FILTER,,}` (quoted glob `[[ == *"$low"''* ]]`).
   - Computes `FLEN=${#filtered[@]}`. If `FLEN == 0` → emit the no-match line
     (`query> <FILTER> (no match)` + count `0/$TOTAL` when show-count) and return.
   - **Clamps** the index: `IDX` as int; if `IDX < 0 → 0`; if `IDX >= FLEN →
     FLEN-1`. (Renderer clamps; input-handler owns wrap.)
   - **Builds** the item segment: for each `filtered[i]`, emit
     `#[fg=$FG,bg=$BG]<name>#[default]` (normal) or
     `#[fg=$HFG,bg=$HBG]<name>#[default]` (when `i == IDX`), space-joined.
   - If `SHOW_COUNT`: append ` #[fg=$FG,bg=$BG]query> $FILTER [$((IDX+1))/$FLEN]#[default]`.
   - Prints the assembled string with `printf '%s'` (NO trailing newline).
3. Calls `render || printf '%s' '#[fg=red]livepicker: renderer error#[default]'`,
   then `exit 0` unconditionally.

### Success Criteria

- [ ] File at `./scripts/renderer.sh`; shebang `#!/usr/bin/env bash`; executable.
- [ ] Sources `options.sh → utils.sh → state.sh` in that order (state.sh needs
      utils.sh first). All three contracts guarantee no source-time side effects.
- [ ] `set -u` active (inherited); **NO** `set -e`; **NO** `set -o pipefail`.
- [ ] Reads 3 runtime keys via `get_state "$STATE_LIST"/"$STATE_FILTER"/"$STATE_INDEX"`
      with defaults `""`/`""`/`"0"`; reads 6 config options via `opt_type`/`opt_fg`/
      `opt_bg`/`opt_highlight_fg`/`opt_highlight_bg`/`opt_show_count`.
- [ ] List read via `mapfile -t all < <(printf '%s' "$LIST")` (process subst, NOT
      here-string — empty-list artifact avoidance, research FINDING 3).
- [ ] Filter: case-insensitive substring (`${var,,}` + quoted glob); empty filter
      matches all.
- [ ] Index: clamped to `[0, FLEN-1]` (NOT wrapped); 0-based internal, `+1` in display.
- [ ] Empty filtered list → `query> <FILTER> (no match)` + `0/$TOTAL` count.
- [ ] Styling: `#[fg=$FG,bg=$BG]name#[default]` per normal item,
      `#[fg=$HFG,bg=$HBG]name#[default]` per highlighted item; `#[default]` after each.
- [ ] Count suffix (when show-count on): `query> $FILTER [($IDX+1)/$FLEN]`.
- [ ] Output: **exactly one line**, `printf '%s'` (no trailing `\n`, no embedded `\n`).
- [ ] `render || fallback-red-echo; exit 0` — rc=0 always, bar never blanked.
- [ ] `bash -n` clean; `shellcheck` 0 findings; tabs only.
- [ ] Mock validation: all 5 branches (normal/empty-filter/empty-list/clamp/error)
      pass the assertions in Validation Loop §2.

## All Needed Context

### Context Completeness Check

_Pass_: A developer who has never seen this repo can implement renderer.sh from
(a) the verbatim `render()` body in the Implementation Blueprint, (b) the 12
load-bearing findings (all live-proven in research/renderer_findings.md), (c) the
3 complete input dependencies (options.sh / utils.sh / state.sh — their exact
function signatures are quoted below), and (d) the mock-validation script that
exercises all 5 branches against a fake `tmux` on PATH (zero live-server impact).
Every styling and newline behavior is verified live on 3.6b.

### Documentation & References

```yaml
# MUST READ — the empirical ground-truth for THIS file (12 live-verified findings)
- docfile: plan/001_fd5d622d3939/P1M2T1S1/research/renderer_findings.md
  why: FINDING 1 (#() substitutes stdout; #[fg=,bg=] styling + #[default] reset
       BOTH fg+bg — live-rendered proof); FINDING 2 (single trailing \n stripped;
       multi-line stdout loses all but the LAST line → must emit ONE line);
       FINDING 3 (mapfile -t via PROCESS SUBSTITUTION < <(printf '%s' "$LIST"),
       NOT here-string — empty-list artifact); FINDING 4 (case-insensitive
       substring via ${var,,} + quoted glob); FINDING 5 (0-based index, display
       idx+1; empty→0/total denominator); FINDING 6 (renderer CLAMPS, not wraps);
       FINDING 7 (perf budget ~40ms < 50ms; 9 option reads dominate); FINDING 8
       (set -u yes, set -e NO); FINDING 9 (main||fallback;exit 0); FINDING 10
       (source order options→utils→state); FINDING 11 (window mode = no
       special-case); FINDING 12 (show-count on/off bool).
  critical: Read BEFORE writing the style-emit and mapfile lines. The
       #[default]-after-each-segment and printf-'%s'-no-newline rules are the
       two highest-consequence details (FINDINGS 1, 2).

# MUST READ — INPUT dependency 1 of 3 (COMPLETE; treat as a CONTRACT)
- docfile: plan/001_fd5d622d3939/P1M1T1S1/PRP.md
  why: Defines scripts/options.sh: get_opt(name, default) + opt_* accessors.
       renderer.sh sources it and calls opt_type/opt_fg/opt_bg/opt_highlight_fg/
       opt_highlight_bg/opt_show_count (each bakes in its PRD §11 default).
       options.sh begins with `set -u` (NO -e) — sourcing it leaves set -u active.
  section: "Implementation Patterns & Key Details" (the verbatim options.sh body)
  critical: signatures — opt_fg() returns @livepicker-fg or "default";
            opt_highlight_bg() returns @livepicker-highlight-bg or "yellow";
            opt_show_count() returns @livepicker-show-count or "on".

# MUST READ — INPUT dependency 2 of 3 (COMPLETE; treat as a CONTRACT)
- docfile: plan/001_fd5d622d3939/P1M1T2S1/PRP.md
  why: Defines scripts/utils.sh: tmux_get_opt(name, default) (used transitively by
       state.sh's get_state). renderer.sh sources it so state.sh resolves. utils.sh
       has NO source-time side effects.
  critical: state.sh's header explicitly says "the caller MUST source utils.sh
            BEFORE this file" — renderer.sh MUST source utils.sh before state.sh.

# MUST READ — INPUT dependency 3 of 3 (COMPLETE; treat as a CONTRACT)
- docfile: plan/001_fd5d622d3939/P1M1T3S1/PRP.md
  why: Defines scripts/state.sh: get_state(key, default) + the STATE_* readonly
       constants. renderer.sh reads the 3 runtime keys via get_state "$STATE_LIST"
       "" / "$STATE_FILTER" "" / "$STATE_INDEX" "0". Using the STATE_* constants
       (not hardcoded "@livepicker-list" strings) matches the picker-script
       convention and stays in sync if names change.
  critical: STATE_LIST="@livepicker-list", STATE_FILTER="@livepicker-filter",
            STATE_INDEX="@livepicker-index" (newline-separated / substring / 0-based
            int). get_state delegates to tmux_get_opt; ${2:-} makes the default
            OPTIONAL and set -u-safe.

# MUST READ — PRD sections selected for this work item
- docfile: PRD.md
  why: §6 Filtering (case-insensitive substring; "resets the index to the top
       match" on type — informs renderer CLAMP choice); §6 Session navigation
       ("wrapping" — owned by input-handler, NOT the renderer); §10 Status-line
       setup (status-format[0] = #($SCRIPT_DIR/renderer.sh); refresh-client -S
       re-runs #()); §11 Configuration options (the 6 config options + their PRD
       defaults: fg=default, bg=default, highlight-fg=black, highlight-bg=yellow,
       show-count=on, type=session); §5 data flow (renderer is the #() status
       command); §16 Implementation risks ("renderer must update within 100ms").
  section: "§6 Filtering", "§6 Session navigation", "§10 Status-line setup",
           "§11 Configuration options (the 6 rows)", "§5 Architecture/Data flow",
           "§16 Implementation risks (Status renderer refresh)"

# MUST READ — the load-bearing status-format / #() ground-truth (live-verified)
- docfile: plan/001_fd5d622d3939/architecture/system_context.md
  why: INVARIANT C (status=2, status-format[0]=#(renderer.sh), status-format[1]
       unset → line 1 = picker, line 2 = tubular default composite — VERIFIED).
       §9 Shell style (shebang, set -u only, tabs, CURRENT_DIR idiom, quote
       everything, local-first). §1 (pre-declared @livepicker-fg=#ffffff is LIVE —
       opt_fg will return #ffffff, not the "default" default; the renderer must
       pass whatever opt_fg returns straight through to #[fg=...]).
  section: "INVARIANT C", "§9 Shell style", "§1 Project state"

# MUST READ — per-primitive verification (#() mechanics, refresh-client -S)
- docfile: plan/001_fd5d622d3939/architecture/tmux_primitives.md
  why: §3 "status-format[n], #(), refresh-client -S" — #() runs on every redraw;
       refresh-client -S forces immediate re-evaluation (the renderer hot path);
       "#() runs on every redraw, so the renderer script must be FAST (<50ms) or
       the status will stutter." Confirms the contract's perf budget.
  section: "§3 status-format[n], #(), refresh-client -S"
```

### Current Codebase tree

```bash
tmux-livepicker/
  PRD.md
  plugin.tmux                 # (P1.M1.T4.S1 — in parallel) ENTRY POINT (repo root)
  plan/001_fd5d622d3939/{architecture/*.md, tasks.json, prd_snapshot.md, prd_index.txt}
  plan/001_fd5d622d3939/P1M1T1S1/PRP.md          # options.sh contract (INPUT — COMPLETE)
  plan/001_fd5d622d3939/P1M1T2S1/{PRP.md, research/}   # utils.sh contract (COMPLETE)
  plan/001_fd5d622d3939/P1M1T3S1/{PRP.md, research/}   # state.sh contract (COMPLETE)
  plan/001_fd5d622d3939/P1M1T4S1/{PRP.md, research/}   # plugin.tmux (IN PARALLEL)
  plan/001_fd5d622d3939/P1M2T1S1/{PRP.md, research/}   # THIS work item
  scripts/
    options.sh   # EXISTS (COMPLETE) — get_opt + opt_*. THIS file's INPUT dep 1.
    utils.sh     # EXISTS (COMPLETE) — tmux_*. THIS file's INPUT dep 2 (for state.sh).
    state.sh     # EXISTS (COMPLETE) — get_state + STATE_*. THIS file's INPUT dep 3.
    # renderer.sh   # ← DOES NOT EXIST YET (this task creates it HERE, in scripts/).
    # livepicker.sh, input-handler.sh, preview.sh, restore.sh  # (P1.M4–M6, future)
  .gitignore
  # NOTE: NO test harness (P1.M7). NO scripts/renderer.sh yet. Validate via throwaway mock.
```

### Desired Codebase tree with files to be added and responsibility of file

```bash
tmux-livepicker/
  scripts/
    options.sh   # (P1.M1.T1) INPUT dep — get_opt/opt_*. Unchanged by this task.
    utils.sh     # (P1.M1.T2) INPUT dep — tmux_* (transitively for state.sh). Unchanged.
    state.sh     # (P1.M1.T3) INPUT dep — get_state/STATE_*. Unchanged.
    renderer.sh  # NEW (this task). #() STATUS RENDERER. Sources options→utils→state;
                 #   reads 3 runtime + 6 config options; filters; emits ONE styled
                 #   tmux-format line (items + highlight + query + count). Pure (read-
                 #   only). <50ms. main||fallback; exit 0. chmod +x.
```

### Known Gotchas of our codebase & Library Quirks

```bash
# CRITICAL (research FINDING 2): the renderer MUST emit EXACTLY ONE line with NO
# trailing newline. Multi-line stdout from #() renders ONLY THE LAST LINE (data
# loss — the whole list vanishes). Canonical emit: `printf '%s' "$out"`. A single
# trailing `\n` (printf '%s\n') is tolerated (stripped) but discouraged.

# CRITICAL (research FINDING 1): tmux style escapes ACCUMULATE until reset. Every
# item segment MUST end with `#[default]`, which resets BOTH fg AND bg to the
# session/terminal defaults (proven: one #[default] clears both axes). Omitting it
# leaks the highlight color (yellow bg, black fg) onto the next item + the count.

# CRITICAL (research FINDING 3): read the list with PROCESS SUBSTITUTION:
#   mapfile -t all < <(printf '%s' "$LIST")
# NOT a here-string (`mapfile -t all <<< "$LIST"`). The here-string appends a \n,
# so an empty $LIST yields a 1-element array ("") — a phantom empty item that
# breaks the empty-list branch. Process substitution gives 0 elements for empty.

# CRITICAL (research FINDING 8): NO `set -e`. An unset @-option makes
# `tmux show-option -gqv` return rc=1 (and empty stdout); under set -e the FIRST
# unset option read would abort the renderer and blank line 1 on every redraw.
# `set -u` is fine (inherited from the sourced libs) — but EVERY variable must be
# defaulted at read time: get_state "$STATE_INDEX" "0", etc.

# CRITICAL (research FINDING 9): a renderer crash must NEVER blank the bar. Wrap
# the body so any failure still echoes something and exits 0:
#   render || printf '%s' '#[fg=red]livepicker: renderer error#[default]'
#   exit 0

# GOTCHA (research FINDING 5): index is 0-BASED (contract recommendation, matches
# array indexing). Display idx+1. Empty-filtered-list count denominator is the
# TOTAL (unfiltered) list length (0/N means "0 of your N sessions matched");
# non-empty denominator is the FILTERED length ([k/FLEN]).

# GOTCHA (research FINDING 6): the renderer CLAMPS the index (idx<0→0,
# idx>=FLEN→FLEN-1), it does NOT wrap. Wrapping is the input-handler's job
# (P1.M6.T2 owns next/prev wrap semantics). Wrapping in the renderer could
# highlight a different item than the stored index implies (stale index after
# filter-shrink). Clamp is the least-surprising read-only behavior.

# GOTCHA (research FINDING 4): case-insensitive substring filter. Lowercase both
# with ${var,,} (bash 4+; target is 5.3.15). Use the GLOB form with a QUOTED needle
# so filter chars like `*` `?` `[` match literally:
#   [[ "${name,,}" == *"${low_filter}"* ]]
# An empty filter matches everything (initial post-activate state). ✓

# GOTCHA (research FINDING 7): the renderer reads ~9 @-options per redraw (3
# runtime + 6 config) = ~9 tmux round-trips ≈ 30–45 ms on the target. This is
# within the <50ms contract but tight. The dominant cost is the round-trips; do
# NOT "optimize" by replacing with `show-options -g | grep` (the full global dump
# is larger/slower). If profiling later shows >50ms, the fix is to have ACTIVATE
# (P1.M4.T3) pre-bake a styled-config string into one option — NOT this PRP's job.

# GOTCHA (research FINDING 10): source order is LOAD-BEARING — state.sh's header
# says "the caller MUST source utils.sh BEFORE this file". renderer.sh sources:
#   options.sh → utils.sh → state.sh   (in that order)
# All three guarantee NO source-time side effects (no tmux calls, no output).

# GOTCHA: opt_fg() may return a HEX color (the live env has @livepicker-fg=#ffffff
# pre-declared — system_context §1). Pass whatever opt_fg/opt_bg/opt_highlight_*
# return STRAIGHT THROUGH into #[fg=...]/#[bg=...] — tmux accepts named colors
# (red, yellow, default), hex (#ffffff), and `default` verbatim. Do NOT validate
# or transform the color string.

# GOTCHA: session/window names can contain spaces ("job hunt") and hyphens
# ("remote-pi"). mapfile -t splits on \n ONLY, so "job hunt" stays one element
# (research FINDING 3). The substring filter and the #[...] wrapper treat the
# whole name as one token. Never word-split $name.

# GOTCHA (research FINDING 11): window mode (@livepicker-type=window) needs NO
# special-casing — tokens are `session:window` strings, opaque to the filter/
# highlight/count logic. The `:` is a literal char in the substring match. The
# renderer reads opt_type but does not branch on it for the core render path
# (reserved for a future session/window label; one ~4ms read, acceptable).

# GOTCHA: do NOT call any MUTATING tmux command (set-option, set-hook, bind-key,
# link-window, switch-client, refresh-client). The renderer is a #() status
# command; mutating the server from #() is forbidden and would recurse/corrupt.
# It is strictly read-options → print-one-line → exit.

# STYLE (system_context §9): indent with TABS (NOT 4-space). shfmt NOT installed;
# verify with `grep -Pn '^    ' scripts/renderer.sh` (expect empty).

# SHELLCHECK: add `# shellcheck source=scripts/options.sh` (and utils.sh,
# state.sh) directives on the source lines so shellcheck resolves get_opt/opt_*/
# get_state/STATE_* and does NOT emit SC1090/SC2154.
```

## Implementation Blueprint

### Data models and structure

No persistent data model. The renderer holds only function-local variables:
- `TYPE`, `FG`, `BG`, `HFG`, `HBG`, `SHOW_COUNT` (config, from `opt_*`)
- `LIST`, `FILTER`, `IDX` (runtime, from `get_state`)
- `all` / `filtered` (bash arrays)
- `TOTAL`, `FLEN` (array lengths)
- `out`, `seg`, `low_name`, `low_filter`, `i`, `cidx` (loop/build scratch)

There are no functions beyond `render()` (the body) plus the trailing
`render || fallback; exit 0` driver. It is a straight-line script (mirrors the
flat top-level structure of plugin.tmux / session_history.tmux, but wrapped in a
function so the `|| fallback` error shell works).

### Implementation Tasks (ordered by dependencies)

```yaml
Task 1: CREATE scripts/renderer.sh — header + CURRENT_DIR + source the trio
  - FILE: ./scripts/renderer.sh  (IN scripts/ — PRD §12 file layout lists it here:
    "renderer.sh   status-line #() renderer for the picker list".)
  - SHEBANG: #!/usr/bin/env bash  (REQUIRED — #() executes via shebang).
  - HEADER COMMENT: one block stating purpose (#() status renderer; reads 3 runtime
    + 6 config @livepicker-* options; filters case-insensitive; emits ONE styled
    line with highlight + query + count; pure read-only; <50ms), the load-bearing
    rules (printf '%s' NO trailing newline [FINDING 2]; #[default] after each
    segment resets BOTH fg+bg [FINDING 1]; mapfile via process-subst NOT
    here-string [FINDING 3]; NO set -e [FINDING 8]; render||fallback;exit 0
    [FINDING 9]), and the dependencies (sources options→utils→state; reads via
    opt_* and get_state/STATE_*).
  - CURRENT_DIR: the canonical sibling idiom, verbatim:
      CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  - SOURCE the trio IN ORDER (state.sh needs utils.sh first — FINDING 10):
      # shellcheck source=options.sh
      source "$CURRENT_DIR/scripts/options.sh"
      # shellcheck source=utils.sh
      source "$CURRENT_DIR/scripts/utils.sh"
      # shellcheck source=state.sh
      source "$CURRENT_DIR/scripts/state.sh"
  - NO `set -e`, NO `set -o pipefail` (FINDING 8). `set -u` is inherited from the
    libs; do NOT re-add it (redundant) and do NOT add `set +u` (masks bugs).
  - STYLE: tabs; quote every expansion.
  - PLACEMENT: ./scripts/renderer.sh

Task 2: IMPLEMENT render() — read config + runtime state + parse the list
  - DEFINE: render() { ... }   (wrap the body in a function so `|| fallback` works.)
  - CONFIG reads (each bakes in its PRD §11 default via opt_*):
      local TYPE FG BG HFG HBG SHOW_COUNT_RAW SHOW_COUNT
      TYPE="$(opt_type)"                 # "session"|"window" (currently unused in core path; reserved)
      FG="$(opt_fg)"                     # "default" or user color (e.g. #ffffff)
      BG="$(opt_bg)"                     # "default" or user color
      HFG="$(opt_highlight_fg)"          # "black" default
      HBG="$(opt_highlight_bg)"          # "yellow" default
      SHOW_COUNT_RAW="$(opt_show_count)" # "on" default
      case "${SHOW_COUNT_RAW,,}" in
          ''|off|0|no|false|disable) SHOW_COUNT=0 ;;
          *) SHOW_COUNT=1 ;;
      esac
  - RUNTIME reads (defaults make them set -u-safe even when unset):
      local LIST FILTER IDX
      LIST="$(get_state "$STATE_LIST" "")"
      FILTER="$(get_state "$STATE_FILTER" "")"
      IDX="$(get_state "$STATE_INDEX" "0")"
  - PARSE the list into an array (PROCESS SUBSTITUTION — FINDING 3):
      local -a all
      mapfile -t all < <(printf '%s' "$LIST")
      local TOTAL="${#all[@]}"

Task 3: IMPLEMENT render() — filter (case-insensitive substring)
  - LOWERCASE the filter ONCE:
      local low_filter="${FILTER,,}"
  - BUILD filtered[] keeping names whose lowercase contains the lowercase filter
    (quoted glob so filter glob-chars are literal — FINDING 4):
      local -a filtered
      local name low_name
      for name in "${all[@]}"; do
          low_name="${name,,}"
          if [[ "$low_name" == *"$low_filter"* ]]; then
              filtered+=("$name")
          fi
      done
      local FLEN="${#filtered[@]}"
  - NOTE: empty $low_filter → `[[ "$x" == *""* ]]` is always true → full list. ✓
  - GUARD: iterating an empty array under set -u — use `"${filtered[@]+"${filtered[@]}"}"`
    expansion OR (preferred, since filtered is populated inside render) the
    FLEN==0 early-return in Task 4 makes the loop body unreachable when empty.
    (Bash 5.3 tolerates `for x in "${a[@]}"` with empty a under set -u, but the
    early-return is the clean guard.)

Task 4: IMPLEMENT render() — empty-list branch + clamp + build item segment
  - EMPTY-LIST branch (contract §3c; FINDING 5 — denominator is TOTAL):
      local out=""
      if [ "$FLEN" -eq 0 ]; then
          if [ "$SHOW_COUNT" -eq 1 ]; then
              out="#[fg=$FG,bg=$BG]query> $FILTER (no match) 0/$TOTAL#[default]"
          else
              out="#[fg=$FG,bg=$BG]query> $FILTER (no match)#[default]"
          fi
          printf '%s' "$out"
          return 0
      fi
  - CLAMP the index (FINDING 6 — renderer clamps, does NOT wrap):
      local cidx="$IDX"
      # ensure integer; tolerate garbage by falling back to 0
      [[ "$cidx" =~ ^[0-9]+$ ]] || cidx=0
      [ "$cidx" -ge "$FLEN" ] && cidx=$((FLEN-1))
      [ "$cidx" -lt 0 ] && cidx=0
  - BUILD the item segment — for each filtered[i], wrap with the right style and
    #[default] reset (FINDING 1); space-join (FINDING 11 — name may contain spaces,
    so quote "$name"):
      local i seg first=1
      for i in "${!filtered[@]}"; do
          if [ "$i" -eq "$cidx" ]; then
              seg="#[fg=$HFG,bg=$HBG]${filtered[$i]}#[default]"
          else
              seg="#[fg=$FG,bg=$BG]${filtered[$i]}#[default]"
          fi
          if [ "$first" -eq 1 ]; then out="$seg"; first=0
          else out="$out $seg"; fi
      done
  - NOTE: `#[default]` is emitted after EVERY item (including the last) so the
    count suffix starts from a clean slate (FINDING 1).

Task 5: IMPLEMENT render() — count suffix + emit (NO trailing newline)
  - APPEND the query+count suffix when SHOW_COUNT (contract §3e; FINDING 5 —
    denominator is FLEN, position is cidx+1):
      if [ "$SHOW_COUNT" -eq 1 ]; then
          out="$out #[fg=$FG,bg=$BG]query> $FILTER [$((cidx+1))/$FLEN]#[default]"
      fi
  - EMIT exactly one line, NO trailing newline (FINDING 2):
      printf '%s' "$out"
  - (end of render())

Task 6: IMPLEMENT the driver — render || fallback; exit 0
  - DRIVER (FINDING 9 — bar never blanked, rc=0 always):
      render || printf '%s' '#[fg=red]livepicker: renderer error#[default]'
      exit 0
  - The fallback echo also uses #[default] (FINDING 1) and printf '%s' (FINDING 2).

Task 7: chmod +x  (REQUIRED — not cosmetic)
  - RUN: chmod +x scripts/renderer.sh
  - VERIFY: ls -la scripts/renderer.sh shows -rwxr-xr-x. The #() loading model
    executes the file via its shebang; non-executable → "Permission denied" and
    line 1 blanks/errors on every redraw.

Task 8: VALIDATE (Level 1 syntax/lint + Level 2 mock 5-branch — no harness yet)
  - RUN: bash -n scripts/renderer.sh            (expect exit 0, no output)
  - RUN: shellcheck scripts/renderer.sh         (expect 0 findings; the three
    `# shellcheck source=` directives resolve get_opt/opt_*/get_state/STATE_*.)
  - RUN: grep -Pn '^    ' scripts/renderer.sh   (expect no output — tabs only)
  - RUN the throwaway mock-validation script (Validation Loop §2) — exercises all
    5 branches (normal / empty-filter / empty-list / clamp / error) against a
    FAKE tmux on PATH (zero live-server impact). Then DELETE the throwaway (do
    NOT commit a tests/ file — the harness is P1.M7.T1/T2).
  - OPTIONAL live render spot-check (Validation §3) on an isolated socket with a
    real pty client — confirms styling + #[default] + no-newline render visually
    (re-runs the research FINDING 1 proof with the real renderer.sh).
```

### Implementation Patterns & Key Details

```bash
#!/usr/bin/env bash
# scripts/renderer.sh — tmux-livepicker #() status-line renderer.
#
# Invoked as status-format[0] = #($SCRIPT_DIR/renderer.sh) by activate
# (P1.M4.T3.S1) and re-evaluated on EVERY status redraw — which the input handler
# (P1.M6) forces via `tmux refresh-client -S` after each keystroke. Therefore:
# PURE (read options → print ONE line → exit; ZERO tmux mutations) and FAST
# (<50ms; ~9 option reads ≈ 30-45ms on target — see research FINDING 7).
#
# LOAD-BEARING RULES (research/renderer_findings.md):
#  - Emit EXACTLY ONE line, NO trailing newline: `printf '%s' "$out"`. Multi-line
#    stdout from #() renders ONLY the last line (data loss). (FINDING 2)
#  - `#[default]` after EVERY segment resets BOTH fg AND bg (one reset, both
#    axes — proven live). Omitting it leaks the highlight color onward. (FINDING 1)
#  - Read the list via PROCESS SUBSTITUTION: `mapfile -t all < <(printf '%s' "$LIST")`,
#    NOT a here-string (which makes an empty list look like a 1-element [""]).
#    (FINDING 3)
#  - NO `set -e` — an unset @-option makes show-option return rc=1; set -e would
#    abort the renderer and blank line 1. set -u is inherited (every var defaulted).
#    (FINDING 8)
#  - render || fallback-red-echo; exit 0 — a renderer crash must NEVER blank the
#    bar. (FINDING 9)
#
# INDEX is 0-based (contract; matches array indexing). The renderer CLAMPS
# (idx<0→0, idx>=FLEN→FLEN-1); wrapping is the input-handler's job (P1.M6.T2).
# Display idx+1. Empty-filtered count denominator = TOTAL; non-empty = FLEN.
#
# DEPENDS ON (source order is load-bearing — state.sh needs utils.sh first):
#   options.sh (get_opt/opt_*), utils.sh (tmux_*), state.sh (get_state/STATE_*).
# All three guarantee NO source-time side effects.

CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=options.sh
source "$CURRENT_DIR/scripts/options.sh"
# shellcheck source=utils.sh
source "$CURRENT_DIR/scripts/utils.sh"
# shellcheck source=state.sh
source "$CURRENT_DIR/scripts/state.sh"

render() {
	local TYPE FG BG HFG HBG SHOW_COUNT_RAW SHOW_COUNT
	local LIST FILTER IDX
	local -a all filtered
	local TOTAL FLEN low_filter name low_name
	local out seg i cidx first

	TYPE="$(opt_type)"
	FG="$(opt_fg)"
	BG="$(opt_bg)"
	HFG="$(opt_highlight_fg)"
	HBG="$(opt_highlight_bg)"
	SHOW_COUNT_RAW="$(opt_show_count)"
	case "${SHOW_COUNT_RAW,,}" in
		'' | off | 0 | no | false | disable) SHOW_COUNT=0 ;;
		*) SHOW_COUNT=1 ;;
	esac

	LIST="$(get_state "$STATE_LIST" "")"
	FILTER="$(get_state "$STATE_FILTER" "")"
	IDX="$(get_state "$STATE_INDEX" "0")"

	mapfile -t all < <(printf '%s' "$LIST")
	TOTAL="${#all[@]}"

	low_filter="${FILTER,,}"
	for name in "${all[@]}"; do
		low_name="${name,,}"
		if [[ "$low_name" == *"$low_filter"* ]]; then
			filtered+=("$name")
		fi
	done
	FLEN="${#filtered[@]}"

	out=""
	if [ "$FLEN" -eq 0 ]; then
		if [ "$SHOW_COUNT" -eq 1 ]; then
			out="#[fg=$FG,bg=$BG]query> $FILTER (no match) 0/$TOTAL#[default]"
		else
			out="#[fg=$FG,bg=$BG]query> $FILTER (no match)#[default]"
		fi
		printf '%s' "$out"
		return 0
	fi

	cidx="$IDX"
	[[ "$cidx" =~ ^[0-9]+$ ]] || cidx=0
	[ "$cidx" -ge "$FLEN" ] && cidx=$((FLEN - 1))
	[ "$cidx" -lt 0 ] && cidx=0

	first=1
	for i in "${!filtered[@]}"; do
		if [ "$i" -eq "$cidx" ]; then
			seg="#[fg=$HFG,bg=$HBG]${filtered[$i]}#[default]"
		else
			seg="#[fg=$FG,bg=$BG]${filtered[$i]}#[default]"
		fi
		if [ "$first" -eq 1 ]; then
			out="$seg"
			first=0
		else
			out="$out $seg"
		fi
	done

	if [ "$SHOW_COUNT" -eq 1 ]; then
		out="$out #[fg=$FG,bg=$BG]query> $FILTER [$((cidx + 1))/$FLEN]#[default]"
	fi

	printf '%s' "$out"
}

render || printf '%s' '#[fg=red]livepicker: renderer error#[default]'
exit 0
```

NOTE for the implementer: the block above is the COMPLETE, ready file body. Use
it as-is; the only allowed deviation is comment phrasing. Do NOT add `set -e`. Do
NOT use a here-string for mapfile. Do NOT omit `#[default]` after any segment. Do
NOT print a trailing newline. Do NOT call any mutating tmux command. Do NOT create
any other file (no tests/, no livepicker.sh — those are P1.M7 / P1.M4).

### Integration Points

```yaml
STATUS FORMAT (how renderer.sh gets invoked — PRD §10; system_context INVARIANT C):
  - activate (P1.M4.T3.S1 — FUTURE) sets:
        tmux set-option -g status-format[0] "#($CURRENT_DIR/scripts/renderer.sh)"
        tmux set-option -g status <current+1>     # typically 2
  - With status=2 and status-format[1] UNSET, line 1 = renderer output, line 2 =
    tmux's default composite (tubular window-status). INVARIANT C (live-verified).
  - restore (P1.M5.T3.S1 — FUTURE) does `set-option -gu status-format` (TRAP 1)
    which clears the renderer install. NOT this task's job — the renderer just has
    to be correct + executable so activate's install step works.

REDRAW TRIGGER (how/when renderer.sh re-runs — PRD §10/§16; tmux_primitives §3):
  - input-handler (P1.M6 — FUTURE) calls `tmux refresh-client -S` after every
    type/backspace/next/prev, forcing status redraw → #() re-evaluates renderer.sh.
  - Also re-runs on the default status-interval (15s) and any other redraw. The
    renderer must be idempotent + fast for ALL of these.

DEPENDENCIES (consumed — all COMPLETE):
  - scripts/options.sh (P1.M1.T1.S1): opt_type/opt_fg/opt_bg/opt_highlight_fg/
    opt_highlight_bg/opt_show_count. Sourced first.
  - scripts/utils.sh (P1.M1.T2.S1): tmux_get_opt (transitively, for state.sh).
    Sourced second.
  - scripts/state.sh (P1.M1.T3.S1): get_state + STATE_LIST/STATE_FILTER/STATE_INDEX.
    Sourced third (needs utils.sh first).

STATE / CONFIG WRITES: NONE. The renderer is strictly read-only. It does NOT set
  any @livepicker-* option, does NOT touch @livepicker-mode/@livepicker-linked-id/
  @livepicker-orig-*, does NOT call refresh-client (the input-handler owns redraw
  triggering), does NOT bind keys or set hooks. Mutating the server from a #()
  status command is forbidden (would recurse/corrupt).

DATABASE / MIGRATIONS / ROUTES: none.
```

## Validation Loop

### Level 1: Syntax & Style (Immediate Feedback)

```bash
# Run after creating + chmod +x the file — fix before proceeding.
bash -n scripts/renderer.sh                     # syntax check; expect no output, exit 0
shellcheck scripts/renderer.sh                  # lint; expect 0 findings
# Tabs-not-spaces sanity (shfmt NOT installed):
grep -Pn '^    ' scripts/renderer.sh && echo "FAIL: 4-space indent found, use tabs" || echo "OK: tabs only"
# Executable bit (REQUIRED — #() executes via shebang):
[ -x scripts/renderer.sh ] && echo "OK: executable" || { echo "FAIL: not executable"; chmod +x scripts/renderer.sh; }

# Expected: all clean. shellcheck must NOT emit SC1090/SC2154 — the three
# `# shellcheck source=scripts/*.sh` directives resolve get_opt/opt_*/get_state/STATE_*.
# If shellcheck cannot find the libs, run from the repo root:
#   cd <repo-root> && shellcheck scripts/renderer.sh
```

### Level 2: Mock Validation — ALL 5 branches, zero live-server impact

The P1.M7 socket-isolation shim does not exist yet. We validate with a **fake
`tmux` on PATH** that serves configurable `@livepicker-*` values. This touches NO
live tmux state. Run from the repo root, then delete the throwaway.

```bash
# Throwaway mock validation (do NOT commit a tests/ dir):
REPO_ROOT="$(pwd)"
MOCK_DIR="$(mktemp -d)"

# Fake tmux: serves the @livepicker-* options the renderer reads (via the libs).
# Env vars MOCK_LIST / MOCK_FILTER / MOCK_INDEX / MOCK_*_STYLE control each branch.
cat > "$MOCK_DIR/tmux" <<'EOF'
#!/usr/bin/env bash
# fake tmux for renderer.sh validation
if [ "$1" = "show-option" ] && [ "$2" = "-gqv" ]; then
	case "$3" in
		"@livepicker-list")          printf '%s' "${MOCK_LIST:-}" ;;
		"@livepicker-filter")        printf '%s' "${MOCK_FILTER:-}" ;;
		"@livepicker-index")         printf '%s' "${MOCK_INDEX:-0}" ;;
		"@livepicker-type")          printf '%s' "${MOCK_TYPE:-session}" ;;
		"@livepicker-fg")            printf '%s' "${MOCK_FG:-default}" ;;
		"@livepicker-bg")            printf '%s' "${MOCK_BG:-default}" ;;
		"@livepicker-highlight-fg")  printf '%s' "${MOCK_HFG:-black}" ;;
		"@livepicker-highlight-bg")  printf '%s' "${MOCK_HBG:-yellow}" ;;
		"@livepicker-show-count")    printf '%s' "${MOCK_SHOW_COUNT:-on}" ;;
		*)                           printf '' ;;
	esac
fi
exit 0
EOF
chmod +x "$MOCK_DIR/tmux"

pass=0; fail=0
assert() { # $1 desc $2 cond(0/1)
	if [ "$2" = "0" ]; then pass=$((pass+1)); else fail=$((fail+1)); printf 'FAIL %s\n' "$1"; fi
}
run_renderer() {
	MOCK_LIST="$MOCK_LIST" MOCK_FILTER="$MOCK_FILTER" MOCK_INDEX="$MOCK_INDEX" \
	MOCK_TYPE="$MOCK_TYPE" MOCK_FG="$MOCK_FG" MOCK_BG="$MOCK_BG" \
	MOCK_HFG="$MOCK_HFG" MOCK_HBG="$MOCK_HBG" MOCK_SHOW_COUNT="$MOCK_SHOW_COUNT" \
	PATH="$MOCK_DIR:$PATH" bash "$REPO_ROOT/scripts/renderer.sh"
}

# ---------- BRANCH 1: normal path (filter matches some, highlight + count) ----------
MOCK_LIST=$'hack\nmain\ntmux\nskills'; MOCK_FILTER="tm"; MOCK_INDEX=0
out="$(run_renderer)"; rc=$?
assert "branch1 exit 0" "$([ "$rc" = "0" ] && echo 0 || echo 1)"
# no trailing newline (byte count of last char != \n)
last=$(printf '%s' "$out" | tail -c1 | od -An -c | tr -d ' \n')
assert "branch1 NO trailing newline" "$([ "$last" != "\\n" ] && echo 0 || echo 1)"
# no embedded newline
assert "branch1 NO embedded newline" "$([ -z "$(printf '%s' "$out" | tr -cd "\n")" ] && echo 0 || echo 1)"
# highlighted item wrapped with #[fg=black,bg=yellow]...#[default]  (tmux is the top match at idx 0)
assert "branch1 highlight wraps 'tmux'" "$(printf '%s' "$out" | grep -cF '#[fg=black,bg=yellow]tmux#[default]')"
# count suffix present [1/2]  (2 matches: tmux, skills? no — 'tm' matches 'tmux' only among hack/main/tmux/skills? 'skills' has no 'tm' → only 'tmux')
assert "branch1 count [1/1]" "$(printf '%s' "$out" | grep -cF '[1/1]')"
# query shown
assert "branch1 query 'tm' shown" "$(printf '%s' "$out" | grep -cF 'query> tm')"

# ---------- BRANCH 2: empty filter (full list, count [1/N]) ----------
MOCK_LIST=$'a\nb\nc'; MOCK_FILTER=""; MOCK_INDEX=0
out="$(run_renderer)"
assert "branch2 all 3 items rendered" "$([ "$(printf '%s' "$out" | grep -oF '#[default]' | wc -l)" -ge 3 ] && echo 0 || echo 1)"
assert "branch2 count [1/3]" "$(printf '%s' "$out" | grep -cF '[1/3]')"

# ---------- BRANCH 3: empty list (no match line + 0/total) ----------
MOCK_LIST=""; MOCK_FILTER="zz"; MOCK_INDEX=5
out="$(run_renderer)"
assert "branch3 (no match) emitted" "$(printf '%s' "$out" | grep -cF '(no match)')"
assert "branch3 count 0/0" "$(printf '%s' "$out" | grep -cF '0/0')"
assert "branch3 query 'zz' shown" "$(printf '%s' "$out" | grep -cF 'query> zz')"

# ---------- BRANCH 4: clamp (index >= FLEN → lands on last, no wrap) ----------
MOCK_LIST=$'one\ntwo\nthree'; MOCK_FILTER=""; MOCK_INDEX=99
out="$(run_renderer)"
# idx 99 clamped to 2 (three) — highlighted, count [3/3]
assert "branch4 clamp lands on 'three'" "$(printf '%s' "$out" | grep -cF '#[fg=black,bg=yellow]three#[default]')"
assert "branch4 count [3/3]" "$(printf '%s' "$out" | grep -cF '[3/3]')"

# ---------- BRANCH 5: show-count off (no count suffix) ----------
MOCK_LIST=$'a\nb'; MOCK_FILTER=""; MOCK_INDEX=0; MOCK_SHOW_COUNT="off"
out="$(run_renderer)"
assert "branch5 NO count bracket" "$([ -z "$(printf '%s' "$out" | grep -oF '[1/2]')" ] && echo 0 || echo 1)"
assert "branch5 NO query> suffix" "$([ -z "$(printf '%s' "$out" | grep -oF 'query>')" ] && echo 0 || echo 1)"

# ---------- BRANCH 6: error path (main fails → fallback red echo + exit 0) ----------
# Force render to fail by making mapfile impossible: serve a LIST that triggers a
# subshell error is hard; instead verify the driver shell directly by stubbing
# render. Simpler: break an internal dep — unset PATH so the libs' tmux calls fail
# is not enough. Use a sed-injected broken copy to confirm `|| fallback; exit 0`:
cp "$REPO_ROOT/scripts/renderer.sh" "$MOCK_DIR/broken.sh"
# replace 'render()' with a function that always fails, keep the driver line:
sed -i 's/^render() {$/render() { return 1; #/' "$MOCK_DIR/broken.sh"
out="$(PATH="$MOCK_DIR:$PATH" bash "$MOCK_DIR/broken.sh" 2>/dev/null)"; rc=$?
assert "branch6 exit 0 despite render failure" "$([ "$rc" = "0" ] && echo 0 || echo 1)"
assert "branch6 fallback red echo emitted" "$(printf '%s' "$out" | grep -cF '#[fg=red]livepicker: renderer error#[default]')"

printf 'PASS=%d FAIL=%d\n' "$pass" "$fail"
rm -rf "$MOCK_DIR"
[ "$fail" = "0" ]
# Expected: PASS≈17 FAIL=0, exit 0. Key proofs: no-trailing-newline, no-embedded-
# newline, #[default]-after-each (highlight wrapper byte-exact), count format
# [k/FLEN] vs 0/total, clamp-lands-on-last (no wrap), show-count-off hides suffix,
# and the render-fail → fallback + exit-0 invariant.
```

### Level 3: Integration Testing (System Validation)

```bash
# Live render spot-check on an ISOLATED socket with a real pty client (re-runs the
# research FINDING 1 proof with the REAL renderer.sh). Self-cleaning.
export LP_SOCK="lp-renderer-live-$$"
REPO_ROOT="$(pwd)"
tmux -L "$LP_SOCK" new-session -d -s driver -x 80 -y 24
# attach a real pty client so the status line renders
TMUX="" script -qec "tmux -L '$LP_SOCK' attach -t driver" /tmp/lp-renderer-live.log &
SCRIPT_PID=$!
sleep 0.5

# Prime the picker state on the isolated server (mimics what activate will do):
tmux -L "$LP_SOCK" set-option -g "@livepicker-list" $'hack\nmain\ntmux\nskills'
tmux -L "$LP_SOCK" set-option -g "@livepicker-filter" "tm"
tmux -L "$LP_SOCK" set-option -g "@livepicker-index" "0"
tmux -L "$LP_SOCK" set-option -g "@livepicker-highlight-bg" "yellow"
tmux -L "$LP_SOCK" set-option -g "@livepicker-highlight-fg" "black"
# install the renderer
tmux -L "$LP_SOCK" set-option -g status on
tmux -L "$LP_SOCK" set-option -g status-format[0] "#($REPO_ROOT/scripts/renderer.sh)"
tmux -L "$LP_SOCK" set-option -g status-left ''
tmux -L "$LP_SOCK" set-option -g status-right ''
tmux -L "$LP_SOCK" set-option -g window-status-format ''
tmux -L "$LP_SOCK" set-option -g window-status-current-format ''
tmux -L "$LP_SOCK" refresh-client -S
sleep 0.4
CLIENT=$(tmux -L "$LP_SOCK" list-clients -F '#{client_name}' 2>/dev/null | head -1)
echo "=== rendered line 1 (decode SGR to confirm yellow-bg highlight on 'tmux') ==="
tmux -L "$LP_SOCK" capture-pane -e -p -t "$CLIENT" 2>/dev/null | sed -n '1p' | cat -v | head -c 400
echo ""
echo "=== plain-text line 1 (should show: tmux query> tm [1/1], styled) ==="
tmux -L "$LP_SOCK" capture-pane -p -t "$CLIENT" 2>/dev/null | sed -n '1p' | cat -A

kill "$SCRIPT_PID" 2>/dev/null
tmux -L "$LP_SOCK" kill-server 2>/dev/null
rm -f /tmp/lp-renderer-live.log
# Expected: line 1 shows 'tmux' highlighted (yellow bg SGR \033[43m, black fg \033[30m)
# followed by #[default] reset, then 'query> tm [1/1]'. Confirms the REAL renderer
# renders correctly through the full #() → status-format pipeline.
```

### Level 4: Creative & Domain-Specific Validation

```bash
# Performance budget spot-check (<50ms contract — research FINDING 7).
# Measure renderer wall-clock on the LIVE server with a realistic 15-session list.
# (Touches the live server's OPTIONS only — sets 3 @livepicker-* runtime keys,
# reads them, then cleans up. Does NOT touch status-format/status/key-table.)
LP_LIVE_LIST="$(tmux list-sessions -F '#{session_name}' | head -15 | paste -sd'\n' -)"
tmux set-option -g "@livepicker-list" "$LP_LIVE_LIST"
tmux set-option -g "@livepicker-filter" ""
tmux set-option -g "@livepicker-index" "7"
# time 20 runs of the renderer (each forks bash + sources 3 libs + 9 tmux reads):
times_ms=()
for n in $(seq 1 20); do
    start=$(date +%s%N)
    bash "$(pwd)/scripts/renderer.sh" >/dev/null 2>&1
    end=$(date +%s%N)
    times_ms+=( $(( (end - start) / 1000000 )) )
done
# cleanup the 3 runtime keys (do NOT leave picker state on the live server):
tmux set-option -gu "@livepicker-list"   2>/dev/null
tmux set-option -gu "@livepicker-filter" 2>/dev/null
tmux set-option -gu "@livepicker-index"  2>/dev/null
echo "renderer wall-clock (ms) over 20 runs: ${times_ms[*]}"
avg=$(printf '%s\n' "${times_ms[@]}" | awk '{s+=$1} END {print s/NR}')
max=$(printf '%s\n' "${times_ms[@]}" | sort -n | tail -1)
echo "avg=${avg}ms max=${max}ms  (contract: <50ms; expect avg ~30-45ms on target)"
[ "$max" -lt 50 ] && echo "OK: within <50ms budget" || echo "WARN: max ${max}ms >= 50ms — see FINDING 7 (consider P1.M4 pre-bake optimization)"
# Expected: avg ~30-45ms, max <50ms on the target machine. If max >= 50ms, NOTE it
# for P1.M4 (the optimization — activate pre-bakes a styled-config string — lives
# there, NOT in this PRP). This is informational; the renderer logic is correct.

# Case-insensitive + special-char filter sanity (mock, no live server):
MOCK_DIR="$(mktemp -d)"
cat > "$MOCK_DIR/tmux" <<'EOF'
#!/usr/bin/env bash
[ "$1" = "show-option" ] && [ "$2" = "-gqv" ] && case "$3" in
"@livepicker-list") printf '%s' "${MOCK_LIST:-}";; "@livepicker-filter") printf '%s' "${MOCK_FILTER:-}";;
"@livepicker-index") printf '%s' "${MOCK_INDEX:-0}";; "@livepicker-show-count") printf '%s' "on";;
"@livepicker-highlight-fg") printf 'black';; "@livepicker-highlight-bg") printf 'yellow';;
"@livepicker-fg") printf 'default';; "@livepicker-bg") printf 'default';; "@livepicker-type") printf 'session';; esac
exit 0
EOF
chmod +x "$MOCK_DIR/tmux"
# filter 'JOB' (uppercase) must match 'job hunt' (lowercase) — case-insensitive
MOCK_LIST=$'job hunt\nremote-pi\nskills' MOCK_FILTER="JOB" MOCK_INDEX=0
out=$(PATH="$MOCK_DIR:$PATH" bash "$(pwd)/scripts/renderer.sh")
printf '%s' "$out" | grep -qF '#[fg=black,bg=yellow]job hunt#[default]' \
  && echo "OK: case-insensitive match (JOB → job hunt)" || echo "FAIL: no match"
# window-mode token with ':' filters as a literal
MOCK_LIST=$'main:1\nmain:2\nother:0' MOCK_FILTER="main:" MOCK_INDEX=1
out=$(PATH="$MOCK_DIR:$PATH" bash "$(pwd)/scripts/renderer.sh")
printf '%s' "$out" | grep -qF '[2/2]' \
  && echo "OK: window-mode ':' token substring match ([2/2])" || echo "FAIL"
rm -rf "$MOCK_DIR"
# Expected: both OK. Confirms case-insensitivity (FINDING 4) and window-mode
# opaque-token handling (FINDING 11) with the real renderer.
```

## Final Validation Checklist

### Technical Validation

- [ ] `bash -n scripts/renderer.sh` exits 0 with no output.
- [ ] `shellcheck scripts/renderer.sh` reports 0 findings (the three `# shellcheck
      source=scripts/*.sh` directives resolve all symbols; no SC1090/SC2154).
- [ ] No 4-space indents (`grep -Pn '^    '` is empty); tabs only.
- [ ] `scripts/renderer.sh` is executable (`-rwxr-xr-x`).

### Feature Validation

- [ ] File is at `./scripts/renderer.sh` (NOT repo root; PRD §12 file layout).
- [ ] Shebang `#!/usr/bin/env bash`; header documents the 5 load-bearing rules.
- [ ] `CURRENT_DIR` computed via the canonical idiom; sources `options.sh → utils.sh
      → state.sh` IN THAT ORDER (state.sh needs utils.sh first).
- [ ] Reads 3 runtime keys via `get_state "$STATE_LIST/STATE_FILTER/STATE_INDEX"`
      with defaults `""`/`""`/`"0"`; reads 6 config via `opt_type/opt_fg/opt_bg/
      opt_highlight_fg/opt_highlight_bg/opt_show_count`.
- [ ] List parsed via `mapfile -t all < <(printf '%s' "$LIST")` (process subst).
- [ ] Filter: case-insensitive substring (`${var,,}` + quoted glob); empty→all.
- [ ] Index clamped `[0, FLEN-1]` (NOT wrapped); 0-based internal, `+1` displayed.
- [ ] Empty filtered list → `query> <FILTER> (no match)` + `0/$TOTAL`.
- [ ] Styling: `#[fg=$FG,bg=$BG]name#[default]` (normal) /
      `#[fg=$HFG,bg=$HBG]name#[default]` (highlighted); `#[default]` after EACH.
- [ ] Count suffix (show-count on): `query> $FILTER [($cidx+1)/$FLEN]`.
- [ ] Output is ONE line via `printf '%s'` (no trailing `\n`, no embedded `\n`).
- [ ] `render || printf '%s' '#[fg=red]...error...#[default]'; exit 0` — rc=0 always.
- [ ] Mock validation: PASS≈17 FAIL=0 across all 6 mock branches (incl. no-newline,
      no-embedded-newline, byte-exact highlight wrapper, count format, clamp, show-
      count-off, render-fail fallback).
- [ ] Live render spot-check (isolated socket + pty client) shows the highlighted
      item in yellow-bg/black-fg with `#[default]` reset and the count suffix.

### Code Quality Validation

- [ ] NO `set -e`, NO `set -o pipefail` anywhere (contract; FINDING 8).
- [ ] NO explicit `set +u` (masks bugs); `set -u` inherited from the libs.
- [ ] All expansions double-quoted (`"$name"`, `"${filtered[$i]}"`, etc.).
- [ ] NO mutating tmux command anywhere (no set-option/set-hook/bind-key/link-window/
      switch-client/refresh-client). Pure read-only.
- [ ] `# shellcheck source=scripts/{options,utils,state}.sh` directives present.
- [ ] Indent with tabs; `local` declared FIRST (avoids SC2155).
- [ ] Performance within `<50ms` (Level 4 spot-check; informational — optimization
      path is P1.M4 if exceeded).

### Documentation & Deployment

- [ ] Header comment states: purpose, the 5 load-bearing rules (printf-'%s',
      #[default]-after-each, mapfile-process-subst, no-set-e, render||fallback),
      the index convention (0-based, clamp), and the source-order dependency.
- [ ] No README/doc file created (DOCS = Mode A — contract §6: "renderer output is
      internal; styled appearance documented in final README P1.M8.T1.S1").
- [ ] No new env vars; no @livepicker-* writes; no tmux.conf edit.

---

## Anti-Patterns to Avoid

- ❌ Don't emit a trailing newline (`printf '%s\n'`) or multiple lines — `#()`
  renders ONLY the last line of multi-line stdout (research FINDING 2 — data loss).
  Use `printf '%s' "$out"` (no newline).
- ❌ Don't omit `#[default]` after a styled segment — styles ACCUMULATE; the
  highlight bg/fg would leak onto the next item and the count. One `#[default]`
  resets BOTH axes (research FINDING 1, live-proven).
- ❌ Don't read the list with a here-string (`mapfile -t all <<< "$LIST"`) — the
  here-string appends `\n`, so an empty list becomes a 1-element `("")` array (a
  phantom empty item). Use process substitution
  `mapfile -t all < <(printf '%s' "$LIST")` (research FINDING 3).
- ❌ Don't add `set -e` — an unset `@`-option makes `show-option -gqv` return rc=1
  inside `$(...)`; `set -e` would abort the renderer and blank line 1 on every
  redraw where any option is unset. The libs already guard; `set -u` is enough
  (research FINDING 8).
- ❌ Don't WRAP the index in the renderer — wrapping is the input-handler's job
  (P1.M6.T2). The renderer CLAMPS (`idx>=FLEN→FLEN-1`) so a stale/high index lands
  on the nearest valid item, not a wrapped-to-top surprise (research FINDING 6).
- ❌ Don't call any MUTATING tmux command (set-option, refresh-client, bind-key,
  link-window, switch-client, set-hook). The renderer is a `#()` status command;
  mutating the server from `#()` is forbidden and would recurse/corrupt.
- ❌ Don't "optimize" by replacing 9 accessor reads with `show-options -g | grep` —
  the full global dump is larger and slower than 9 targeted reads. The simple path
  is within budget (~40ms; research FINDING 7). If budget is ever exceeded, the
  fix is activate (P1.M4) pre-baking a styled-config string — NOT the renderer.
- ❌ Don't hardcode `"@livepicker-list"` strings — use the `STATE_LIST`/
  `STATE_FILTER`/`STATE_INDEX` constants from state.sh (picker-script convention;
  stays in sync if names change).
- ❌ Don't validate or transform the color string returned by `opt_fg`/`opt_bg`/
  `opt_highlight_*` — pass it straight through to `#[fg=...]/#[bg=...]`. tmux
  accepts named colors, hex (`#ffffff`), and `default` verbatim. The live env has
  `@livepicker-fg=#ffffff` pre-declared (system_context §1).
- ❌ Don't word-split `$name` — names can contain spaces ("job hunt"). mapfile -t
  splits on `\n` only; quote `"${filtered[$i]}"` everywhere (research FINDING 3/11).
- ❌ Don't create a `tests/` directory or committed test file — the harness is
  P1.M7.T1/T2. Validate via the throwaway mock (Validation §2) and delete it.
- ❌ Don't create `scripts/livepicker.sh` (even a stub) — it is P1.M4.T1.S1's
  deliverable. renderer.sh is installed by activate (P1.M4.T3.S1) later.
- ❌ Don't special-case window mode (`@livepicker-type=window`) in the render path —
  `session:window` tokens are opaque strings; the `:` is a literal in the substring
  match (research FINDING 11). Reading `opt_type` is fine (reserved for a future
  label) but do NOT branch the core logic on it.
- ❌ Don't use 4-space indent — tabs only (system_context §9).
- ❌ Don't leave the renderer non-executable — `#()` executes via the shebang; a
  non-executable file fails "Permission denied" and blanks line 1. `chmod +x`.

---

## Confidence Score

**9 / 10** for one-pass success. Rationale: the deliverable is a ~60-line straight-
line script whose complete body is given verbatim above, wrapped in a `render()`
function with a `|| fallback; exit 0` driver. Every load-bearing behavior is backed
by a **live proof on 3.6b** in research/renderer_findings.md: `#()` substitution +
`#[fg=,bg=]` styling + `#[default]`-resets-both-axes (FINDING 1, rendered to a real
pty client and SGR-decoded); single-newline-stripped / multi-line-loses-all-but-last
(FINDING 2); `mapfile -t` via process-substitution for empty/single/multi/space names
(FINDING 3); case-insensitive substring + quoted-glob (FINDING 4); 0-based index +
clamp + count-format (FINDINGS 5, 6); perf budget ~40ms < 50ms (FINDING 7); set -u
not -e (FINDING 8); render||fallback;exit 0 (FINDING 9); source order options→utils
→state (FINDING 10). All three input dependencies (options.sh / utils.sh / state.sh)
are COMPLETE and their exact function signatures are quoted. The 6 mock branches
(normal / empty-filter / empty-list / clamp / show-count-off / error) assert the
byte-exact output including the no-trailing-newline and `#[default]`-after-each
invariants. Tools verified present: `tmux 3.6b`, `bash 5.3.15`, `shellcheck 0.11.0`.
Residual risks: (a) the ~40ms perf budget is tight — caught by the Level 4
spot-check, with a documented (P1.M4-owned, not-this-PRP) optimization path;
(b) shellcheck needing the `source` directives to resolve symbols (handled by the
directives; caught at Level 1); (c) the live `@livepicker-fg=#ffffff` pre-declaration
making `opt_fg` return a hex — handled by passing the color through verbatim
(anti-pattern). All residual risks are deterministically caught by the validation
loop.
