# PRP — P1.M6.T1.S1: input-handler.sh `type <char>`

---

## Goal

**Feature Goal**: **CREATE** `scripts/input-handler.sh` — the tmux-livepicker
input dispatcher — with its full skeleton (header, lib-trio source, `input_main`
dispatch on `argv[1]`, driver) and the **`type` action branch fully implemented**.
The `type` action appends a typed character to `@livepicker-filter`, resets
`@livepicker-index` to `0` (top filtered match), and forces a status redraw via
`tmux refresh-client -S`. Per PRD §6 Filtering + §10 + §16 and the work-item
CONTRACT (point 3): the handler does NOT filter — the **renderer**
(`scripts/renderer.sh`, COMPLETE) filters `@livepicker-list` by the query
(case-insensitive substring) and highlights `@livepicker-index` on each redraw.
So `type` is exactly three state ops + one refresh: (1) `new_filter = old_filter
+ char` → `set_state "$STATE_FILTER" "$new_filter"`; (2) `set_state
"$STATE_INDEX" "0"`; (3) `tmux refresh-client -S`.

This is the FIRST subtask of module P1.M6 (Input handler). Following the
established incremental-build pattern (see `scripts/restore.sh`, built across
T1→T2→T3→T4 with seam comments), T1.S1 creates the whole file skeleton and ships
ONLY the `type` branch, leaving seam comments for the remaining actions
(`backspace`/`next-session`/`prev-session` → P1.M6.T2; `confirm` → P1.M6.T3;
`cancel` → P1.M6.T4). Each future subtask edits this file in place to fill its
own seam — exactly as P1.M5 incrementally filled restore.sh.

**Deliverable**: ONE new file `scripts/input-handler.sh` (executable). It
sources `options.sh` + `utils.sh` + `state.sh` (its own process under `run-shell`,
so it must source its own trio — restore.sh FINDING 7), declares an
`input_main()` function with a single `local` line (house style), dispatches on
`argv[1]` via `case`, fully implements the `type` branch, and provides seam
comments for the other actions plus a `*) return 0` defensive default. Driver:
`input_main "$@" || exit 1` then `exit 0` (matches restore.sh / livepicker.sh
verbatim). No other file is touched.

**Success Definition**:
- `bash -n scripts/input-handler.sh` passes; `shellcheck scripts/input-handler.sh`
  is clean (0 findings; the file-level `# shellcheck disable=SC1091,SC2153`
  covers everything — `type` adds NO word-split on user input, so NO new
  disable). Tabs only; `set -u` inherited (NO `-e`, NO `-o pipefail`).
- **argv contract (work-item §2 + research FINDING 1):** the `type` branch reads
  `argv[1]='type'` (dispatch) and `argv[2]=<char>` (the typed character). Verified
  for `a` `L` `3` `-` `.` `/` `_` (all pass correctly as `$2`; `-` is NOT a flag
  because it is the 2nd positional, not the 1st — do NOT use `getopts`).
- **filter/index update (work-item §3 LOGIC, research FINDING 6):** after
  `input-handler.sh type l`, `@livepicker-filter == "l"` and `@livepicker-index
  == "0"`; after `type o` → `"lo"`, `0`; after `type g` → `"log"`, `0`. The
  RAW query is stored (case preserved — filtering is case-insensitive at render
  time, NOT in the handler).
- **renderer integration (work-item §3 NOTE + §5 MOCKING):** the handler does NOT
  touch `@livepicker-list` (research FINDING 2 — the data-flow "recompute list"
  is the RENDERER's filtered VIEW, recomputed on each `refresh-client -S`; the
  handler only updates filter/index + forces redraw). After typing, running
  `scripts/renderer.sh` reflects the filtered set with index 0 highlighted.
- **refresh within ~100ms (work-item §4 OUTPUT + PRD §16):** `tmux refresh-client
  -S` re-runs the `#()` renderer (PRD §10 / tmux_primitives §3). Production
  guarantee: the typing key fires from an attached client while
  `key-table==livepicker`, so `refresh-client -S` succeeds (research FINDING 3).
- **No off-limits work:** the `type` branch ONLY. NO `backspace`/`next-session`/
  `prev-session`/`confirm`/`cancel` logic (those are seam comments for T2/T3/T4).
  NO mutation of `@livepicker-list` / `@livepicker-mode` / `@livepicker-linked-id`
  / any `@livepicker-orig-*`. NO `select-window`/`link-window`/`switch-client`/
  `set-hook` (those belong to preview/confirm/restore).

## User Persona (if applicable)

**Target User**: None directly (the `type` action is an internal key-handler
invoked by tmux's `livepicker` key table). Transitively: the end user typing a
query to filter the session/window list (PRD §3 story 1: "I press the prefix +
@livepicker-key and a picker appears at the bottom ... I type a few characters
and the list filters live"). T1.S1 is what makes the "I type a few characters
and the list filters live" sentence literally TRUE: each keystroke appends to
the query, the highlight snaps to the top match, and the picker redraws within
~100ms — all without the handler knowing or caring what matches.

**Use Case**: The picker is active (`@livepicker-mode=on`, `key-table=livepicker`).
The user types e.g. `log`. For each keystroke, tmux (consulting ONLY the
`livepicker` table — INVARIANT B) runs the bound `run-shell "$CURRENT_DIR/
input-handler.sh type <char>"`. The `type` branch appends the char to
`@livepicker-filter`, resets `@livepicker-index` to `0`, and calls
`tmux refresh-client -S`. The refresh re-evaluates `status-format[0]` (the
`#($SCRIPT_DIR/renderer.sh)` activate T3.S1 installed), which re-reads the
(now-longer) filter and re-filters/highlights the list. The user sees the list
narrow and the highlight move to the top match, one keystroke at a time.

**User Journey** (T1.S1 scope — a single typed char):
1. …activate (P1.M4) saved state, built the list, grew the status bar, installed
   the renderer, switched `key-table` to `livepicker`, bound the typing keys, ran
   the first preview, and set `@livepicker-mode on`.
2. The user presses a typing key (e.g. `l`).
3. **T1.S1 (this task):**
   - tmux looks up `l` in the `livepicker` table → finds `run-shell
     "$CURRENT_DIR/input-handler.sh type l"`.
   - `run-shell` execs the handler → `input_main` → `case "$action" in type) ...`.
   - `char="${2:-}"` = `l`; `new_filter="$(get_state "$STATE_FILTER" "")l"` =
     `l` (was empty at activate).
   - `set_state "$STATE_FILTER" "l"`; `set_state "$STATE_INDEX" "0"`.
   - `tmux refresh-client -S` → redraws the status → `#(renderer.sh)` re-runs →
     reads `@livepicker-filter=l`, filters the list case-insensitively,
     highlights index 0.
4. The user presses `o`, then `g`. After each, the filter is `lo`, then `log`;
   the index stays `0`; the renderer shows the filtered set.

**Pain Points Addressed**:
- (a) **No live filtering.** Without the `type` handler, typing a key in the
  `livepicker` table would either be DROPPED (unbound key — INVARIANT B) or, if
  a key were accidentally bound, do nothing visible. T1.S1 makes each typed char
  extend the query and the list narrow in real time (the picker's core UX).
- (b) **Stale highlight.** Without resetting `@livepicker-index` to `0`, a
  shrinking filtered set could leave the index pointing past the new list end
  (the renderer clamps, but the highlight would jump unpredictably). T1.S1 snaps
  the highlight to the top match after every keystroke (PRD §6 Filtering).
- (c) **Laggy redraw.** Without `refresh-client -S`, the `#()` renderer only
  re-runs on `status-interval` (default 15s) — the picker would lag a keystroke
  (or 15s) behind. T1.S1 forces the redraw per keystroke (PRD §16).

## Why

- **PRD §6 "Filtering"** is the controlling spec: "Each typed character appends
  to `@livepicker-filter` and resets the index to the top match. ... After each
  change, run `tmux refresh-client -S` so the status renderer re-evaluates and
  the picker redraws. The renderer filters `@livepicker-list` by the query
  (substring, case-insensitive) and highlights the item at
  `@livepicker-index`." T1.S1 implements EXACTLY the input side of this; the
  renderer (P1.M2.T1.S1) implements the filter+highlight side.
- **PRD §10 / §13 / §16** confirm the redraw mechanism: `refresh-client -S`
  forces a status redraw that re-runs `#()` commands (tmux_primitives §3,
  LIVE-PROVEN). PRD §16: "Every input action must call `refresh-client -S`.
  Verify the renderer updates within 100 ms of a keystroke."
- **Boundary respect.** T1.S1 touches ONLY: (1) one state read
  (`@livepicker-filter`); (2) two state writes (`@livepicker-filter`,
  `@livepicker-index`); (3) one tmux mutation (`refresh-client -S`). It does NOT:
  mutate `@livepicker-list`/`@livepicker-mode`/`@livepicker-linked-id`, call
  `select-window`/`link-window`/`switch-client` (preview/confirm), or touch any
  `@livepicker-orig-*` (save/restore).
- **Scope cohesion.** T1.S1 is the input-side counterpart of: activate T2.S1
  (which set `@livepicker-filter=""` and the initial `@livepicker-index`) and
  activate T4.S1 (which bound `run-shell "$CURRENT_DIR/input-handler.sh type
  $lp_c"` for each typing char). The shared contract is the THREE state keys
  (`STATE_FILTER`/`STATE_INDEX`/`STATE_LIST`) the renderer reads. T1.S1 writes
  two of them (filter/index); it never writes the third (list). This module
  (P1.M6) is the LAST functional module before P1.M7 validation — T1.S1 is its
  foundation (the file + dispatch + the simplest action).

## What

A NEW file `scripts/input-handler.sh` (executable). It mirrors the skeleton of
`scripts/restore.sh` / `scripts/livepicker.sh` (the two existing top-level
dispatch scripts):

1. **Header doc-comment** + file-level `# shellcheck disable=SC1091,SC2153`
   (SC1091: sources sibling libs via `$CURRENT_DIR`; SC2153: `$STATE_*` are
   readonly CONTRACT constants defined in state.sh, sourced above).
2. **`CURRENT_DIR` idiom** + source the lib trio (`options.sh`, `utils.sh`,
   `state.sh` — order load-bearing: state.sh needs utils.sh first).
3. **`input_main()`** dispatch function with ONE `local` line declaring all
   locals (`action char new_filter`), then a `case "$action" in` that:
   - **`type)`** — FULLY IMPLEMENTED (the deliverable): read `$2` (the char,
     `${2:-}` for `set -u` safety), guard on non-empty, append to the current
     filter, reset index to `0`, `tmux refresh-client -S`, `return 0`.
   - **`backspace|next-session|prev-session)`** — seam comment for P1.M6.T2
     (placeholder `return 0` so an accidental key does not crash).
   - **`confirm)`** — seam comment for P1.M6.T3.
   - **`cancel)`** — seam comment for P1.M6.T4.
   - **`*)`** — `return 0` (unknown action — defensive; never crash the picker).
4. **Driver:** `input_main "$@" || exit 1` then `exit 0`.

### Success Criteria

- [ ] `scripts/input-handler.sh` is executable and passes `bash -n` + `shellcheck`
      (0 findings; only the file-level `disable=SC1091,SC2153`).
- [ ] Tabs only (`grep -Pn '^    ' scripts/input-handler.sh` empty); `set -u`
      inherited from the sourced libs (NO `set -e`, NO `set -o pipefail`).
- [ ] Sources `options.sh` + `utils.sh` + `state.sh` via `$CURRENT_DIR` (in that
      order); `CURRENT_DIR` resolved from `${BASH_SOURCE[0]}`.
- [ ] `input_main` declares ALL locals in ONE `local` line (`action char new_filter`);
      dispatches on `case "$action" in`.
- [ ] **`type` branch:** `char="${2:-}"`; `[ -z "$char" ] && return 0`;
      `new_filter="$(get_state "$STATE_FILTER" "")$char"`;
      `set_state "$STATE_FILTER" "$new_filter"`;
      `set_state "$STATE_INDEX" "0"`;
      `tmux refresh-client -S`; `return 0`.
- [ ] Reads `argv[1]` for dispatch and `argv[2]` for the char (research FINDING 1).
      Uses POSITIONAL args, NOT `getopts` (the `-` char must pass as `$2`).
- [ ] Does NOT mutate `@livepicker-list` / `@livepicker-mode` /
      `@livepicker-linked-id` / any `@livepicker-orig-*`.
- [ ] Seam comments present for `backspace`/`next-session`/`prev-session` (T2),
      `confirm` (T3), `cancel` (T4); a `*) return 0` default.
- [ ] Mock (work-item §5): under the socket shim with a known list + an attached
      client, run `input-handler.sh type l|o|g` char-by-char; after each assert
      `@livepicker-filter` == `l`/`lo`/`log` AND `@livepicker-index` == `0`;
      then run `scripts/renderer.sh` and assert its stdout reflects the filtered
      set (e.g. for list `syslog\nlogin\nbackend\nrouter`, query `log` matches
      `syslog` and `login`, highlights index 0). See Validation Loop §2.

## All Needed Context

### Context Completeness Check

_Pass_: A developer who has never seen this repo can implement T1.S1 from
(a) the complete, ready-to-paste `type` branch + skeleton in "Implementation
Patterns & Key Details" below, (b) the 7 live-verified findings in
`research/input_handler_type_findings.md` — most critically **FINDING 1** (argv
contract: `$1=type`, `$2=char`; the `-` char passes as `$2`, do NOT use
`getopts`), **FINDING 2** (LOAD-BEARING: the handler does NOT filter — the
renderer does; "recompute list" is the renderer's filtered VIEW; never touch
`@livepicker-list`), **FINDING 3** (`refresh-client -S` works from run-shell with
a client attached; filter round-trips; guard `2>/dev/null || true`), **FINDING 6**
(append idiom `"$(get_state "$STATE_FILTER" "")$char"`), and (c) the socket-shim
mock that seeds a known list + attached client, types `log` char-by-char, asserts
filter/index after each, and runs the REAL renderer.sh to check the filtered
output. The INPUT dependencies (`state.sh` STATE_FILTER/STATE_INDEX/set_state/
get_state, `renderer.sh` for the integration check, `livepicker.sh` T4.S1's key
binding) are ALL COMPLETE/present.

### Documentation & References

```yaml
# MUST READ — the KEY BINDING that invokes this script (the caller contract).
- docfile: plan/001_fd5d622d3939/P1M4T4S1/PRP.md
  why: activate T4.S1 (COMPLETE) built the livepicker key table and bound each
       typing char as `tmux bind-key -T livepicker "$lp_c" run-shell
       "$CURRENT_DIR/input-handler.sh type $lp_c"` for {a..z} {A..Z} {0..9} - _ . /.
       THIS IS THE CALLER. So input-handler.sh is invoked as a fresh process per
       keystroke with argv[1]='type', argv[2]=<char>. (Confirmed live — research
       FINDING 1.) The binding's `$CURRENT_DIR` is the scripts/ dir; run-shell
       execs the whole string via the shell (word-split on spaces).
  section: "Goal" (the typing-key binds), research/key_table_findings.md FINDING 5
           (the `-` char binds with no `--`).

# MUST READ — the INPUT dependency: state.sh (STATE_FILTER/STATE_INDEX/set_state/get_state). COMPLETE.
- file: scripts/state.sh
  why: (1) `set_state "$1" "$2"` → `tmux_set_opt` → `tmux set-option -g` (writes a
       runtime @livepicker-* option; preserves embedded chars — FINDING 3). (2)
       `get_state "$STATE_FILTER" ""` → reads the current query (default "" — safe
       under set -u). (3) readonly `STATE_FILTER="@livepicker-filter"`,
       `STATE_INDEX="@livepicker-index"` (the two keys `type` writes). (4) ALSO
       defines STATE_LIST/STATE_MODE/STATE_LINKED_ID — which `type` MUST NOT touch
       (research FINDING 2: the list is the renderer's input, immutable during
       the picker).
  critical: `type` writes ONLY STATE_FILTER + STATE_INDEX. It MUST NOT write
            STATE_LIST (the renderer filters it at render time), STATE_MODE
            (activate/restore own it), or STATE_LINKED_ID (preview owns it).

# MUST READ — the FILTERING engine (the integration partner). COMPLETE.
- file: scripts/renderer.sh
  why: the `#()` status command activate T3.S1 installed. Re-runs on EVERY
       `refresh-client -S`. Reads STATE_LIST (full list) + STATE_FILTER +
       STATE_INDEX; computes the FILTERED array at render time (case-insensitive
       substring, `${FILTER,,}` / `[[ "$low_name" == *"$low_filter"* ]]`);
       highlights the item at STATE_INDEX (clamped to [0, FLEN-1]); emits ONE
       line. This is WHY the handler only updates filter/index + refresh — the
       renderer does the rest. The mock runs renderer.sh directly to assert the
       filtered output.
  critical: the handler does NOT need to know whether the filter matches — the
            renderer handles FLEN=0 ("no match") itself. Setting index=0 is
            always safe (research FINDING 4).

# MUST READ — the SKELETON MODEL (copy its structure). COMPLETE.
- file: scripts/restore.sh
  why: the canonical pattern for a top-level dispatch script in this repo: header
       + `# shellcheck disable=SC1091,SC2153`; `CURRENT_DIR` idiom; source the lib
       trio (options/utils/state — order load-bearing); a `*_main()` with ONE
       `local` line for all locals; seam comments for incremental subtasks;
       driver `restore_main "$@" || exit 1` / `exit 0`; `set -u` only; tabs. T1.S1
       MIRRORS this (input_main + seam comments for T2/T3/T4). restore.sh is also
       the PROOF that a script under run-shell must source its OWN trio (sourced
       state does not cross process boundaries — FINDING 7).
  critical: copy the driver verbatim (`input_main "$@" || exit 1` then `exit 0`);
            use ONE `local` line; seam comments must be clear enough that T2/T3/T4
            can edit in place.

# MUST READ — the ACTIVATE orchestrator (sets the initial filter/index + the table). COMPLETE.
- file: scripts/livepicker.sh
  why: (1) T2.S1 set `@livepicker-filter=""` and the initial `@livepicker-index`
       (idx of the current session). So when the FIRST typing key fires, the
       filter is empty and `type` appends to "". (2) T4.S1 bound the typing keys
       (the caller). (3) T5.S1 set `@livepicker-mode on` (the guard context).
       Confirms the handler runs only when the picker is fully active.
  critical: the initial filter is "" and the initial index is the current
            session's index — `type` RESETS the index to 0 on the first keystroke
            (PRD §6), so the highlight moves from the current session to the top
            filtered match as soon as the user types.

# MUST READ — the empirical ground-truth for THIS task (7 live-verified findings).
- docfile: plan/001_fd5d622d3939/P1M6T1S1/research/input_handler_type_findings.md
  why: FINDING 1 (argv contract — $1=type, $2=char; `-`/`.`/`/`/`_` all pass as
       $2; NO getopts); FINDING 2 (LOAD-BEARING: the renderer filters, NOT the
       handler; "recompute list" = renderer's filtered VIEW; never touch
       @livepicker-list); FINDING 3 (refresh-client -S works from run-shell w/
       client; filter round-trips; guard `2>/dev/null || true`); FINDING 4 (index
       reset to 0 always safe — renderer handles FLEN=0); FINDING 5 (file skeleton
       + dispatch table + seam model); FINDING 6 (append idiom
       `"$(get_state "$STATE_FILTER" "")$char"`); FINDING 7 (no tmux_refresh_client
       helper — call bare `tmux refresh-client -S`).
  critical: Read BEFORE writing the file. FINDING 2 is the #1 trap (don't
            "recompute" the list); FINDING 1 is the argv contract.

# MUST READ — the PRD sections selected for this work item.
- docfile: PRD.md
  why: §6 "Filtering" (the handler appends char + resets index + refresh; the
       renderer filters+highlights); §10 "Status-line setup" (refresh-client -S
       re-runs #()); §11 "Configuration options" (the typing keys are bound from
       opt_*; the handler does NOT read config, but the binding does); §16
       "Implementation risks and notes" ("Every input action must call
       refresh-client -S ... within 100ms").
  section: "§6 Behaviors / Filtering", "§10 Status-line setup", "§11 Configuration",
           "§16 Implementation risks and notes"

# MUST READ — primitive verification (refresh-client -S re-runs #()).
- docfile: plan/001_fd5d622d3939/architecture/tmux_primitives.md
  why: §3 — `refresh-client -S` forces an immediate status-line redraw that
       re-evaluates format strings including `#()`. This is the standard plugin
       technique for sub-`status-interval` updates (default 15s). Confirms the
       redraw mechanism the `type` branch relies on.
  section: "§3 status-format[n], #(), refresh-client -S"

# MUST READ — system ground-truth (shell style + the modal-table invariant).
- docfile: plan/001_fd5d622d3939/architecture/system_context.md
  why: §3 INVARIANT B (when key-table==livepicker, tmux consults ONLY that table;
       unbound keys are DROPPED — so the typing keys MUST be bound for typing to
       work, which activate T4.S1 did); §9 shell style (set -u ONLY, NO -e/pipefail;
       tabs; `local` for all function locals; `CURRENT_DIR` idiom; quote
       everything).
  section: "§3 INVARIANT B", "§9 Shell style"
```

### Current Codebase tree

```bash
tmux-livepicker/
  PRD.md
  plugin.tmux                 # COMPLETE. Unchanged.
  plan/001_fd5d622d3939/{architecture/*.md, tasks.json, prd_snapshot.md, prd_index.txt}
  plan/001_fd5d622d3939/P1M5T1S1..P1M5T4S1/{PRP.md, research/}   # restore.sh module (COMPLETE incl. T4.S1)
  plan/001_fd5d622d3939/P1M6T1S1/{PRP.md, research/input_handler_type_findings.md}  # THIS
  scripts/
    options.sh   # COMPLETE. Unchanged. (config accessors; type does not read config.)
    utils.sh     # COMPLETE. Unchanged. (tmux_* option helpers; NO tmux_refresh_client — FINDING 7.)
    state.sh     # COMPLETE — STATE_FILTER/STATE_INDEX/set_state/get_state (INPUT deps). Unchanged.
    renderer.sh  # COMPLETE (P1.M2). Unchanged. (the FILTERING engine; integration-check target.)
    preview.sh   # COMPLETE (P1.M3). Unchanged.
    livepicker.sh   # COMPLETE (P1.M4). Unchanged. (T4.S1 bound the typing keys — the CALLER.)
    restore.sh   # COMPLETE (P1.M5, incl. T4.S1). Unchanged. (skeleton model + driver pattern.)
    input-handler.sh  # DOES NOT EXIST YET. THIS task CREATES it (skeleton + `type` branch + seams).
  .gitignore
  # NOTE: NO test harness yet (P1.M7). Validate via the throwaway socket-shim mock
  #       (MUST keep an attached client so refresh-client -S works — FINDING 3).
  #       input-handler.sh is the LAST functional script; P1.M6.T2-T4 fill its seams.
```

### Desired Codebase tree with files to be added and responsibility of file

```bash
tmux-livepicker/
  scripts/
    options.sh        # unchanged.
    utils.sh          # unchanged.
    state.sh          # unchanged.
    renderer.sh       # unchanged.
    preview.sh        # unchanged.
    livepicker.sh     # unchanged.
    restore.sh        # unchanged.
    input-handler.sh  # NEW (this task). Executable. Sources the lib trio; dispatches
                      # on argv[1]. The `type` branch: append argv[2] to
                      # @livepicker-filter, reset @livepicker-index to 0, refresh-client -S.
                      # Seam comments for backspace/next-session/prev-session (T2),
                      # confirm (T3), cancel (T4). After T1.S1: typing filters the
                      # picker live (the renderer does the filtering on each refresh).
```

### Known Gotchas of our codebase & Library Quirks

```bash
# CRITICAL (research FINDING 2 — the #1 trap): the handler does NOT filter. The
#   data-flow diagram's "type / backspace: update @livepicker-filter; recompute
#   list; refresh status" is AMBIGUOUS. "Recompute list" means the RENDERER
#   recomputes the FILTERED VIEW at render time (renderer.sh reads STATE_LIST +
#   STATE_FILTER + STATE_INDEX, filters case-insensitively, highlights index).
#   The handler NEVER touches @livepicker-list (it is immutable for the picker's
#   lifetime — set once by activate T2.S1). The handler's ENTIRE job for `type`:
#   (1) append char to @livepicker-filter; (2) @livepicker-index=0; (3) refresh.
#   Do NOT add any list-filtering logic, do NOT write @livepicker-list.

# CRITICAL (research FINDING 1 — argv contract): the key binding is
#   `run-shell "$CURRENT_DIR/input-handler.sh type $lp_c"`. run-shell execs the
#   WHOLE string via the shell (word-split on spaces). So $1='type', $2=<char>.
#   Verified for a L 3 - . / _ — ALL pass correctly as $2. The `-` char is NOT a
#   flag (it is the 2nd positional, not the 1st). Do NOT use `getopts` (it would
#   mis-parse `-`, `.`, `/`); use POSITIONAL $1/$2 directly. Under set -u, read
#   $2 as `char="${2:-}"` (the binding always passes a char, but a manual/stale
#   invocation without one would crash under set -u without the default).

# CRITICAL (research FINDING 3 + PRD §16): `refresh-client -S` forces a status
#   redraw that re-runs the #() renderer (PRD §10 / tmux_primitives §3). It
#   requires a CLIENT — production always has one (the typing key fires from an
#   attached client while key-table==livepicker). With no client it rc=1
#   ("no current client"); under set -u (NO set -e) this does NOT abort the
#   script, but the picker won't redraw for that keystroke. Mirror restore.sh
#   STEP 6c: `tmux refresh-client -S 2>/dev/null || true` (belt-and-braces; safer
#   for a per-keystroke handler — a detached edge during rapid typing must never
#   break the chain).

# CRITICAL (research FINDING 4): setting @livepicker-index=0 is ALWAYS safe.
#   The renderer clamps idx to [0, FLEN-1] and handles FLEN=0 itself ("no match"
#   branch). The handler does NOT need to know whether the filter matches. Do NOT
#   add a "does the filter match?" check — that is the renderer's concern.

# GOTCHA (research FINDING 6 — append idiom): `new_filter="$(get_state
#   "$STATE_FILTER" "")$char"` — pure bash string concatenation via parameter
#   expansion. NO bash `+=` (options are not bash variables). NO shell-escaping
#   of $char (it is already a single positional arg; re-quoting is a no-op and
#   risks mangling). The double-quoted `set_state` arg preserves `-`/`.`/`/`/`_`.

# GOTCHA (research FINDING 7): there is NO tmux_refresh_client / tmux_run helper
#   in utils.sh. House style (mirror clear_all_state's bare `tmux set-option -gu`,
#   restore.sh STEP 6c's bare `tmux refresh-client -S`) permits DIRECT bare `tmux`
#   calls for one-off primitives that have no accessor. Do NOT add a utils helper.

# GOTCHA: this task is a NEW FILE (the FIRST of module P1.M6). It CREATES the
#   full skeleton + the `type` branch + seam comments for T2/T3/T4. It does NOT
#   implement backspace/nav/confirm/cancel (seam comments only). chmod +x the
#   file (it is run via run-shell; tmux execs it directly).

# GOTCHA: input-handler.sh is its OWN process under run-shell -> it MUST source
#   its OWN lib trio (options/utils/state). Sourced state does NOT cross process
#   boundaries (restore.sh FINDING 7). Mirror restore.sh's source block verbatim.

# GOTCHA: declare ALL function locals in ONE `local` line at the top of
#   input_main (house style — restore.sh/livepicker.sh do this). For T1.S1 that
#   is `action char new_filter`. (T2/T3/T4 will append their own locals to this
#   line, exactly as restore.sh's `local` line grew across T1→T2→T3→T4.)

# CRITICAL: NO `set -e`, NO `set -o pipefail` (house style; system_context §9).
#   refresh-client legitimately returns non-zero on the detached edge; under
#   set -e that would abort mid-keystroke. `set -u` is inherited from the sourced
#   libs — do NOT add a `set -u` line (it is already in effect; doubling it is
#   harmless but unnecessary — restore.sh does not re-declare it).

# STYLE (system_context §9): indent with TABS. Verify with `grep -Pn '^    '
#   scripts/input-handler.sh` (expect empty). shfmt is NOT installed.
```

## Implementation Blueprint

### Data models and structure

No new data model. T1.S1 adds NO new state keys and NO new options — it reads
and writes EXISTING `@livepicker-*` keys via the state.sh accessors:

- **READ:** `@livepicker-filter` (via `get_state "$STATE_FILTER" ""`) — the
  current raw query.
- **WRITE:** `@livepicker-filter` (the appended query) and `@livepicker-index`
  (`0`) — via `set_state`.
- **READ (none):** `@livepicker-list` — NEVER (research FINDING 2; the renderer
  owns it).

The function locals (declared in ONE `local` line): `action` (argv[1]),
`char` (argv[2]), `new_filter` (the appended result).

### Implementation Tasks (ordered by dependencies)

```yaml
Task 1: CREATE scripts/input-handler.sh — full skeleton + `type` branch + seam comments
  - FILE: ./scripts/input-handler.sh  (NEW; chmod +x).
  - WRITE: the complete file from "Implementation Patterns & Key Details" below:
           header + `# shellcheck disable=SC1091,SC2153`; CURRENT_DIR idiom;
           source the lib trio (options/utils/state — order load-bearing);
           `input_main()` with ONE `local action char new_filter` line + the
           `case "$action" in` dispatch; the fully-implemented `type` branch;
           seam-commented `backspace|next-session|prev-session)` / `confirm)` /
           `cancel)` branches (each a placeholder `return 0`); the `*) return 0`
           default; the driver `input_main "$@" || exit 1` / `exit 0`.
  - `type` branch EXACT logic (research FINDINGS 1/2/4/6):
        char="${2:-}"
        [ -z "$char" ] && return 0
        new_filter="$(get_state "$STATE_FILTER" "")$char"
        set_state "$STATE_FILTER" "$new_filter"
        set_state "$STATE_INDEX" "0"
        tmux refresh-client -S 2>/dev/null || true
        return 0
  - DO NOT: implement backspace/nav/confirm/cancel (seam comments only); mutate
            @livepicker-list / @livepicker-mode / @livepicker-linked-id / any
            @livepicker-orig-*; call select-window/link-window/switch-client/
            set-hook; use getopts; add `set -e`/`set -o pipefail`.

Task 2: MAKE EXECUTABLE + VERIFY house style + no off-limits work
  - RUN: chmod +x scripts/input-handler.sh
  - RUN: bash -n scripts/input-handler.sh            (expect exit 0, no output)
  - RUN: shellcheck scripts/input-handler.sh         (expect 0 findings; only
        the file-level disable=SC1091,SC2153)
  - RUN: grep -Pn '^    ' scripts/input-handler.sh   (expect empty — tabs only)
  - RUN: grep -n 'set -e\|set -o pipefail' scripts/input-handler.sh  (expect empty)
  - EXPECT: exactly ONE `case "$action"`; the `type)` branch reads `${2:-}`,
        appends via get_state+set_state, resets STATE_INDEX to "0", calls
        `tmux refresh-client -S 2>/dev/null || true`, returns 0; seam comments
        for backspace/next-session/prev-session/confirm/cancel; a `*) return 0`.
  - EXPECT: NO reference to STATE_LIST / STATE_MODE / STATE_LINKED_ID / any
        ORIG_*; NO select-window/link-window/switch-client/set-hook.

Task 3: VALIDATE (Level 1 syntax/lint + Level 2 socket-shim mock: seed a known
        list + attached client; type 'log' char-by-char; assert filter/index
        after each; run the REAL renderer.sh and assert the filtered output.)
  - RUN the socket-shim mock (Validation Loop §2). Self-cleaning, isolated
        socket, attached client (FINDING 3 for refresh-client -S). Calls the REAL
        input-handler.sh with argv `type l|o|g`, then the REAL renderer.sh.
```

### Implementation Patterns & Key Details

The complete, ready-to-write `scripts/input-handler.sh` (indent is ONE tab to
match the repo's house style — restore.sh / livepicker.sh):

```bash
#!/usr/bin/env bash
# shellcheck disable=SC1091,SC2153
#   SC1091: sources sibling libs (options/utils/state) via the resolved $CURRENT_DIR;
#           follow with `shellcheck -x` if you want them traced.
#   SC2153: STATE_* are readonly CONTRACT constants defined in state.sh
#           (sourced above); shellcheck sees no assignment here.
# scripts/input-handler.sh — tmux-livepicker input dispatcher.
#
# Invoked via `run-shell` from the livepicker key table that activate
# (P1.M4.T4.S1, COMPLETE) installed. Each typing key is bound as:
#   tmux bind-key -T livepicker "$lp_c" run-shell "$CURRENT_DIR/input-handler.sh type $lp_c"
# run-shell execs the WHOLE string via the shell (word-split on spaces), so:
#   argv[1] = action (type | backspace | next-session | prev-session | confirm | cancel)
#   argv[2] = the typed char (for `type`) — verified to pass correctly for
#             a-z A-Z 0-9 - _ . / (the `-` is the 2nd positional, NOT a flag).
#
# THIS FILE (P1.M6.T1.S1) implements ONLY the `type` action. The remaining
# actions are seam comments filled by P1.M6.T2-T4 (mirror the incremental build
# of scripts/restore.sh across P1.M5.T1-T4):
#   type           -> append char to @livepicker-filter, index=0, refresh      [T1.S1 — HERE]
#   backspace      -> remove last char, index=0, refresh                       [T2 seam]
#   next-session   -> index+1 (wrap), refresh preview + status                 [T2 seam]
#   prev-session   -> index-1 (wrap), refresh preview + status                 [T2 seam]
#   confirm        -> resolve target / create / switch-client once / restore   [T3 seam]
#   cancel         -> restore.sh cancel                                        [T4 seam]
#
# LOAD-BEARING RULES (research/input_handler_type_findings.md):
#  - The handler does NOT filter. The RENDERER (scripts/renderer.sh, COMPLETE)
#    filters @livepicker-list by @livepicker-filter (case-insensitive substring)
#    and highlights @livepicker-index on each redraw. The data-flow diagram's
#    "recompute list" is the RENDERER's filtered VIEW — the handler NEVER touches
#    @livepicker-list (FINDING 2). For `type`: append char to filter, index=0,
#    refresh — that is all.
#  - read $2 as `char="${2:-}"` (set -u safety; the binding always passes a char,
#    but a manual/stale invocation without one would crash under set -u — FINDING 1).
#  - append via parameter expansion: `new_filter="$(get_state "$STATE_FILTER" "")$char"`
#    (NO bash += ; NO shell-escaping of $char — FINDING 6).
#  - index=0 is ALWAYS safe (renderer clamps + handles FLEN=0 — FINDING 4). Do
#    NOT check whether the filter matches — that is the renderer's concern.
#  - `tmux refresh-client -S` re-runs the #() renderer (PRD §10/§13, primitives
#    §3). Requires a client (production always has one — the typing key fires
#    from an attached client while key-table==livepicker). Guard for the detached
#    edge: `2>/dev/null || true` (FINDING 3; mirror restore.sh STEP 6c).
#  - NO `set -e` (refresh legitimately returns non-zero detached); `set -u`
#    inherited from the sourced libs — do NOT re-declare it. NO getopts (it would
#    mis-parse `-`, `.`, `/` — use positional $1/$2 — FINDING 1).
#
# DEPENDS ON (source order load-bearing — state.sh needs utils.sh first):
#   options.sh (opt_*), utils.sh (tmux_*), state.sh (get_state/set_state/STATE_*).
#   input-handler.sh is its OWN process under run-shell -> it MUST source its own
#   trio (sourced state does not cross process boundaries — restore.sh FINDING 7).

CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=options.sh
source "$CURRENT_DIR/options.sh"
# shellcheck source=utils.sh
source "$CURRENT_DIR/utils.sh"
# shellcheck source=state.sh
source "$CURRENT_DIR/state.sh"

# argv[1] = action; argv[2] = the typed char (for `type`). Dispatch + act.
input_main() {
	local action char new_filter
	action="${1:-}"

	case "$action" in
		type)
			# --- P1.M6.T1.S1: append the typed char to the query, reset the
			#     highlight to the top filtered match, force a status redraw.
			# PRD §6 Filtering: "Each typed character appends to @livepicker-filter
			# and resets the index to the top match. After each change, run
			# `tmux refresh-client -S` so the status renderer re-evaluates and the
			# picker redraws." The renderer (scripts/renderer.sh) does the actual
			# filtering + highlighting — the handler only updates filter/index +
			# refresh (research FINDING 2: never touch @livepicker-list).
			char="${2:-}"
			# No char (manual/stale invocation) -> no-op (never crash the picker).
			[ -z "$char" ] && return 0
			# Append via parameter expansion (FINDING 6). get_state defaults to ""
			# so the FIRST keystroke appends to an empty query. The RAW query is
			# stored (case preserved — filtering is case-insensitive at RENDER
			# time, not here).
			new_filter="$(get_state "$STATE_FILTER" "")$char"
			set_state "$STATE_FILTER" "$new_filter"
			# Reset the highlight to the top filtered match (PRD §6). Always safe
			# — the renderer clamps + handles FLEN=0 itself (FINDING 4).
			set_state "$STATE_INDEX" "0"
			# Force the #() renderer to re-run (PRD §10/§16). Requires a client
			# (production always has one); guard the detached edge (FINDING 3).
			tmux refresh-client -S 2>/dev/null || true
			return 0
			;;
		# --- P1.M6.T2.S1 seam: backspace / next-session / prev-session ---
		# backspace:      new_filter="${old_filter%?}"; set_state FILTER; index=0; refresh.
		# next-session:   index = (index+1) % FLEN (wrap); refresh preview.sh + refresh -S.
		# prev-session:   index = (index-1+FLEN) % FLEN (wrap); refresh preview.sh + refresh -S.
		# (FLEN comes from re-filtering @livepicker-list by @livepicker-filter —
		#  the same case-insensitive substring the renderer uses.)
		backspace|next-session|prev-session)
			return 0
			;;
		# --- P1.M6.T3.S1 seam: confirm ---
		# Resolve the target from the filtered list at @livepicker-index. If a
		# target exists: switch-client -t "=target" (the ONE switch). If empty +
		# session mode + @livepicker-create on: new-session -d -s "<query>"; switch.
		# window mode: select-window -t "<session>:<window>". Then restore.sh keep.
		confirm)
			return 0
			;;
		# --- P1.M6.T4.S1 seam: cancel ---
		# restore.sh cancel (unlink preview, restore status/key-table/layout/hook,
		# switch-client back to ORIG_SESSION, clear @livepicker-* state).
		cancel)
			return 0
			;;
		*)
			# Unknown action — defensive no-op (never crash the picker).
			return 0
			;;
	esac
}

input_main "$@" || exit 1
exit 0
```

NOTE for the implementer:
- This is a NEW FILE — write it in full (the block above is complete). Then
  `chmod +x scripts/input-handler.sh` (it is exec'd by run-shell).
- The `type` branch is the ONLY implemented logic. Leave the seam-commented
  branches as `return 0` placeholders (T2/T3/T4 fill them).
- Use POSITIONAL `$1`/`$2` (NOT `getopts`) — research FINDING 1.
- Do NOT touch `@livepicker-list` — research FINDING 2.
- Read `$2` as `char="${2:-}"` (set -u safety) and guard `[ -z "$char" ] && return 0`.
- The append is `"$(get_state "$STATE_FILTER" "")$char"` (parameter expansion; no `+=`).
- `tmux refresh-client -S 2>/dev/null || true` (guarded; FINDING 3).
- ONE `local` line; tabs; driver `input_main "$@" || exit 1` / `exit 0`.

### Integration Points

```yaml
NEW FILE (what this task creates):
  - scripts/input-handler.sh: executable; sources the lib trio; dispatches on
        argv[1]; `type` branch appends argv[2] to @livepicker-filter, resets
        @livepicker-index to 0, refresh-client -S.

CALLERS (this file's INPUT — provided by COMPLETE siblings):
  - activate T4.S1 (P1.M4.T4.S1 — COMPLETE): bound each typing char as
        `run-shell "$CURRENT_DIR/input-handler.sh type $lp_c"` for {a..z} {A..Z}
        {0..9} - _ . /. So input-handler.sh runs as a fresh process per keystroke
        with argv[1]='type', argv[2]=<char>. THIS IS THE CALLER CONTRACT.
  - activate T2.S1 (P1.M4.T2.S1 — COMPLETE): set @livepicker-filter="" and the
        initial @livepicker-index (idx of the current session). So the first
        keystroke appends to "".
  - activate T5.S1 (P1.M4.T5.S1 — COMPLETE): set @livepicker-mode on (the picker
        is fully active when a typing key fires).

CONSUMERS (what this file feeds):
  - scripts/renderer.sh (COMPLETE): re-runs on refresh-client -S, re-reads
        @livepicker-filter (now longer) + @livepicker-index (now 0), re-filters
        @livepicker-list, re-highlights, redraws.
  - P1.M6.T2-T4 (PLANNED): fill the backspace/nav/confirm/cancel seams in THIS file.

STATE READS (this task — type branch):
  - @livepicker-filter   (via get_state "$STATE_FILTER" ""; default "")

STATE WRITES (this task — type branch):
  - @livepicker-filter   (appended query, via set_state)
  - @livepicker-index    ("0", via set_state)

TMUX MUTATIONS (this task — type branch):
  - refresh-client -S    (status redraw; || true; re-runs the #() renderer)

DATABASE / MIGRATIONS / ROUTES / CONFIG: none.
```

## Validation Loop

### Level 1: Syntax & Style (Immediate Feedback)

```bash
# Run after creating the file — fix before proceeding.
chmod +x scripts/input-handler.sh
bash -n scripts/input-handler.sh                 # syntax; expect no output, exit 0
shellcheck scripts/input-handler.sh              # lint; expect 0 findings (only the
                                                  # file-level disable=SC1091,SC2153)
# Tabs-not-spaces sanity (shfmt NOT installed):
grep -Pn '^    ' scripts/input-handler.sh && echo "FAIL: 4-space indent found, use tabs" || echo "OK: tabs only"
# Confirm house style (set -u inherited; NO -e / NO pipefail declared):
grep -n 'set -e\|set -o pipefail' scripts/input-handler.sh && echo "FAIL: set -e/pipefail present" || echo "OK: set -u inherited (no -e)"
# Confirm it sources its OWN lib trio (own process under run-shell):
grep -n 'source "$CURRENT_DIR/options.sh"' scripts/input-handler.sh   # expect 1
grep -n 'source "$CURRENT_DIR/utils.sh"'   scripts/input-handler.sh   # expect 1 (AFTER options)
grep -n 'source "$CURRENT_DIR/state.sh"'   scripts/input-handler.sh   # expect 1 (AFTER utils)
# Confirm the dispatch + driver:
grep -n 'case "$action" in' scripts/input-handler.sh                  # expect 1
grep -n 'input_main "$@" || exit 1' scripts/input-handler.sh          # expect 1
# Confirm the `type` branch is EXACTLY the contract:
grep -n 'char="\${2:-}"' scripts/input-handler.sh                                            # expect 1
grep -n '\[ -z "\$char" \] && return 0' scripts/input-handler.sh                             # expect 1
grep -n 'new_filter="\$(get_state "\$STATE_FILTER" "")\$char"' scripts/input-handler.sh      # expect 1
grep -n 'set_state "\$STATE_FILTER" "\$new_filter"' scripts/input-handler.sh                 # expect 1
grep -n 'set_state "\$STATE_INDEX" "0"' scripts/input-handler.sh                             # expect 1
grep -n 'tmux refresh-client -S 2>/dev/null || true' scripts/input-handler.sh                # expect 1
# Confirm POSITIONAL args (NO getopts — the `-` char must pass as $2):
grep -n 'getopts' scripts/input-handler.sh && echo "FAIL: getopts mis-parses -/./  use positional \$1/\$2" || echo "OK: positional args (FINDING 1)"
# Confirm the seams + default:
grep -n 'P1.M6.T2.S1 seam' scripts/input-handler.sh   # expect 1 (backspace/nav)
grep -n 'P1.M6.T3.S1 seam' scripts/input-handler.sh   # expect 1 (confirm)
grep -n 'P1.M6.T4.S1 seam' scripts/input-handler.sh   # expect 1 (cancel)
grep -n '\*)' scripts/input-handler.sh                # expect 1 (default return 0)
# Confirm NO off-limits state mutation / NO off-limits tmux calls:
grep -n 'STATE_LIST\|STATE_MODE\|STATE_LINKED_ID\|ORIG_' scripts/input-handler.sh \
  && echo "FAIL: type must not touch list/mode/linked-id/orig" || echo "OK: only filter+index (FINDING 2)"
grep -n 'select-window\|link-window\|switch-client\|set-hook\|new-session' scripts/input-handler.sh \
  && echo "FAIL: type must not call preview/confirm/restore primitives" || echo "OK: type only mutates filter/index + refresh"
# Run from the repo root.
```

### Level 2: Socket-Shim Mock Validation — filter/index after each char + renderer reflects the filtered set, zero live-server impact

Reuses the PATH-wrapper socket shim. Self-cleaning. Seeds a known list, sets
mode on + filter/index, attaches a client (FINDING 3 for refresh-client -S),
runs the REAL `input-handler.sh type <char>` char-by-char for `log`, asserts
`@livepicker-filter` and `@livepicker-index` after each, then runs the REAL
`scripts/renderer.sh` and asserts its stdout reflects the filtered set.

```bash
#!/usr/bin/env bash
# Throwaway socket-shim validation for scripts/input-handler.sh T1.S1 (do NOT commit).
set -u
REPO_ROOT="$(cd "$(dirname "$0")" && pwd)"
[ -f "$REPO_ROOT/scripts/input-handler.sh" ] || { echo "input-handler.sh missing"; exit 1; }
[ -f "$REPO_ROOT/scripts/renderer.sh" ]      || { echo "renderer.sh missing"; exit 1; }
for l in options utils state; do
	[ -f "$REPO_ROOT/scripts/$l.sh" ] || { echo "INPUT dep $l.sh missing"; exit 1; }
done

SOCK="lp-t1-mock-$$"
SHIM_DIR="$(mktemp -d)"
cat > "$SHIM_DIR/tmux" <<EOF
#!/usr/bin/env bash
exec /usr/bin/tmux -L "$SOCK" "\$@"
EOF
chmod +x "$SHIM_DIR/tmux"
export PATH="$SHIM_DIR:$PATH"

cleanup() {
	PATH="/usr/bin:/bin:$PATH" tmux -L "$SOCK" kill-server 2>/dev/null || true
	rm -rf "$SHIM_DIR"
}
trap cleanup EXIT

pass=0; fail=0
assert() { if [ "$2" = "$3" ]; then pass=$((pass+1)); printf 'ok   %s\n' "$1"; else fail=$((fail+1)); printf 'FAIL %s: got=[%s] want=[%s]\n' "$1" "$2" "$3"; fi; }
attach() { TMUX="" script -qec "tmux -L $SOCK attach -t $1" /dev/null >/dev/null 2>&1 & AP=$!; sleep 0.5; }
detach() { kill "$AP" 2>/dev/null; wait "$AP" 2>/dev/null; }

# ---------- setup: a driver session + a known picker list ----------
tmux new-session -d -s driver -x 120 -y 40
attach driver   # refresh-client -S needs an attached client (FINDING 3)

# Seed the picker state exactly as activate T2.S1 would (list + empty filter + idx).
# List chosen so 'log' matches syslog + login (case-insensitive substring), not
# backend/router.
tmux set-option -g "@livepicker-list"   $'syslog\nlogin\nbackend\nrouter'
tmux set-option -g "@livepicker-filter" ""
tmux set-option -g "@livepicker-index"  "2"   # pretend the highlight was on 'backend'
tmux set-option -g "@livepicker-mode"   "on"  # picker active

# ---------- char-by-char: type 'log', assert filter + index after each ----------
EXP_FILTER=""
for c in l o g; do
	EXP_FILTER="${EXP_FILTER}${c}"
	bash "$REPO_ROOT/scripts/input-handler.sh" type "$c"
	assert "after type '$c': filter" "$(tmux show-option -gqv '@livepicker-filter')" "$EXP_FILTER"
	assert "after type '$c': index"  "$(tmux show-option -gqv '@livepicker-index')"  "0"
done

# ---------- renderer reflects the filtered set ----------
# renderer.sh reads list+filter+index and prints the filtered list, highlighting
# index 0. For filter 'log' the filtered set is [syslog, login] (both contain
# 'log'); backend/router are dropped.
OUT="$(tmux set-option -g status-format\[0\] "#($REPO_ROOT/scripts/renderer.sh)" >/dev/null 2>&1; \
       tmux refresh-client -S 2>/dev/null; \
       bash "$REPO_ROOT/scripts/renderer.sh")"
printf 'renderer out: %s\n' "$OUT"
assert "renderer contains syslog"          "$(printf '%s' "$OUT" | grep -c 'syslog')"      "1"
assert "renderer contains login"           "$(printf '%s' "$OUT" | grep -c 'login')"       "1"
assert "renderer excludes backend"         "$(printf '%s' "$OUT" | grep -c 'backend')"     "0"
assert "renderer excludes router"          "$(printf '%s' "$OUT" | grep -c 'router')"      "0"
# the highlight (index 0) is the FIRST filtered match -> syslog. Renderer emits
# #[fg=black,bg=yellow] for the highlighted item (PRD §11 defaults).
assert "renderer highlights syslog (index 0)" "$(printf '%s' "$OUT" | grep -c 'fg=black,bg=yellow]syslog')" "1"

# ---------- edge: empty argv[2] is a no-op (set -u safety) ----------
tmux set-option -g "@livepicker-filter" "abc"
bash "$REPO_ROOT/scripts/input-handler.sh" type   # no char
assert "empty char is a no-op on filter" "$(tmux show-option -gqv '@livepicker-filter')" "abc"
assert "empty char is a no-op on index"  "$(tmux show-option -gqv '@livepicker-index')"  "0"

# ---------- edge: the '-' char appends literally (research FINDING 1) ----------
tmux set-option -g "@livepicker-filter" ""
bash "$REPO_ROOT/scripts/input-handler.sh" type -
assert "'-' appends as a literal char" "$(tmux show-option -gqv '@livepicker-filter')" "-"

detach
echo "=========================================="
echo "pass=$pass fail=$fail"
[ "$fail" -eq 0 ] && echo "ALL GREEN" || echo "HAS FAILURES"
exit "$fail"
```

### Level 3: Integration Testing (System Validation)

```bash
# input-handler.sh is invoked by tmux's livepicker key table (activate T4.S1).
# Full end-to-end (activate -> type -> see filter narrow) is exercised by the
# P1.M7 functional test harness (PLANNED). For T1.S1, the Level 2 mock covers the
# handler's contract directly (filter/index/refresh + renderer integration).

# If you want a manual smoke test against the LIVE picker (optional, AFTER the
# socket mock passes): set @livepicker-key, activate, and type — the status bar
# should narrow. (Not required for T1.S1 success; the mock is authoritative.)
```

### Level 4: Creative & Domain-Specific Validation

```bash
# (Domain-specific for this plugin = PRD §15 functional/pollution tests, owned by
#  P1.M7. T1.S1 contributes the `type` action they will exercise. No extra
#  domain validation here — the Level 2 mock is the gate.)

# Optional: shellcheck strict mode (informational; the file-level disable covers
# the expected findings):
shellcheck -x scripts/input-handler.sh   # -x traces the sourced libs; expect clean
```

## Final Validation Checklist

### Technical Validation

- [ ] Level 1 (syntax/lint/style) completed: `bash -n` + `shellcheck` clean; tabs
      only; `set -u` inherited (no `-e`/`pipefail`).
- [ ] Level 2 (socket-shim mock) ALL GREEN: filter/index after each char of `log`;
      renderer reflects [syslog, login] with syslog highlighted; empty-char no-op;
      `-` appends literally.
- [ ] File is executable (`chmod +x`); sources its own lib trio.
- [ ] No linting errors: `shellcheck scripts/input-handler.sh`
- [ ] No formatting issues: `grep -Pn '^    ' scripts/input-handler.sh` empty.

### Feature Validation

- [ ] All success criteria from "What" section met.
- [ ] argv contract holds: `$1=type`, `$2=char` for all bound chars (incl. `-`/`.`/`/`/`_`).
- [ ] `type` appends the char to `@livepicker-filter` and resets
      `@livepicker-index` to `0`; stores the RAW query (case preserved).
- [ ] `tmux refresh-client -S` is called (guarded) after each keystroke.
- [ ] The handler does NOT touch `@livepicker-list` (renderer owns filtering).
- [ ] Seam comments present for backspace/nav (T2), confirm (T3), cancel (T4);
      unknown action returns 0 (never crashes the picker).

### Code Quality Validation

- [ ] Follows existing codebase patterns (mirrors restore.sh / livepicker.sh
      skeleton, driver, `local` line, seam-comment incremental-build model).
- [ ] File placement matches the desired codebase tree (`scripts/input-handler.sh`).
- [ ] Anti-patterns avoided (check against Anti-Patterns section).
- [ ] Dependencies properly sourced (options/utils/state in load-bearing order).

### Documentation & Deployment

- [ ] Code is self-documenting (the header doc-comment explains the dispatch
      table, the load-bearing rules, and the seam model).
- [ ] No new environment variables or config options (the handler reads/writes
      only existing `@livepicker-*` keys).
- [ ] Mode A docs: none (per work-item §6).

---

## Anti-Patterns to Avoid

- ❌ Don't "recompute the list" in the handler — the RENDERER filters
  `@livepicker-list` at render time (research FINDING 2). The handler only
  updates `@livepicker-filter` + `@livepicker-index` + refresh.
- ❌ Don't touch `@livepicker-list` / `@livepicker-mode` / `@livepicker-linked-id`
  / any `@livepicker-orig-*` — those belong to activate/preview/restore.
- ❌ Don't use `getopts` — it mis-parses the `-`, `.`, `/` chars. Use positional
  `$1`/`$2` (research FINDING 1).
- ❌ Don't read `$2` without a default under `set -u` — use `char="${2:-}"`.
- ❌ Don't add `set -e` / `set -o pipefail` (house style; refresh legitimately
  returns non-zero detached).
- ❌ Don't add a `tmux_refresh_client` utils helper — call bare
  `tmux refresh-client -S` (house style; research FINDING 7).
- ❌ Don't check "does the filter match?" in the handler — the renderer handles
  FLEN=0 itself (research FINDING 4). Always set index=0.
- ❌ Don't implement backspace/nav/confirm/cancel in T1.S1 — those are seam
  comments for P1.M6.T2/T3/T4.
- ❌ Don't forget `chmod +x` — the file is exec'd by `run-shell`.
- ❌ Don't skip validation because "it should work" — run the Level 2 mock.
