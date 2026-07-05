# PRP — P1.M4.T3.S1: livepicker.sh — status grow (shift + install + set count)

---

## Goal

**Feature Goal**: Fill in the **T3 seam** of `scripts/livepicker.sh` (the file
CREATED by P1.M4.T1.S1, list/index populated in parallel by P1.M4.T2.S1) —
implementing **PRD §10 steps 2–4 verbatim**: (a) shift every *genuinely-user-set*
`status-format` index up by one (highest-first, race-free), (b) install the
picker renderer `#()` at the configured index `@livepicker-status-format-index`
(default `0`), and (c) grow the status bar line count by one. The block runs
**inside `activate_main()` after the T2 list-build seam** (so `ORIG_STATUS` and
`ORIG_STATUS_FORMAT_INDICES` are already populated by STEP 2) and **before the
T4 key-table seam**. After S1 the status bar has grown by one line, the picker
renderer is installed at the configured index, and the user's normal window-status
line still renders on the line below (Invariant C). The picker does NOT yet react
to input (no key-table switch / mode-on — those are T4/T5), but the renderer is
live and will draw on the next `refresh-client -S` (T4/T5/M6 force redraws).

**Deliverable**: A **surgical edit** to `scripts/livepicker.sh` that **replaces
the single T3 seam comment line** (left by T1) with the status-grow block. No new
file, no other file touched. The block is ~30 lines (locals + shift loop +
renderer install + normalized count `case`). It declares its own locals
(`sf_n`, `sf_val`, `sf_indices`, `lp_idx`, `orig_status`, `local -a sf_desc=()`)
that do **not** collide with T2's (`pick_type current list idx i` / `items`). The
T4/T5 seam comments and the trailing `return 0` / driver remain untouched.

**Success Definition**:
- `bash -n scripts/livepicker.sh` passes; `shellcheck scripts/livepicker.sh` is
  clean (0 findings; the file-level `# shellcheck disable=SC1091,SC2153` from T1
  covers it — the T3 block's one intentional word-split is annotated
  `# shellcheck disable=SC2086`).
- Tabs only; no `set -e`; no new files.
- **Mock (a) common case:** isolated socket, `status=on` (default), no user
  status-format overrides → after running livepicker.sh: `status-format[0]` ==
  `#(<abs>/scripts/renderer.sh)`, `status` == `2`, `status-format[1]` is NOT the
  renderer (untouched default), and `status-left`/`status-right`/
  `window-status-format` are **unchanged** before-vs-after.
- **Mock (b) shift case:** inject `status-format[3]=USERVAL` before activate →
  after: `status-format[4] == USERVAL`, `status-format[3]` unset, renderer at
  `[0]`, `status==2`.
- **Mock (c) adjacent-shift case:** inject `status-format[3]=A`,
  `status-format[4]=B` → after: `status-format[4]==A`, `status-format[5]==B`,
  `status-format[3]` unset (proves **highest-first** — ascending would clobber B).
- **Mock (d) normalization case:** `status=off` before activate → after
  `status==on`; `status=3` before activate → after `status==4`. (The naive
  `$((on+1))` would CRASH under `set -u` — see FINDING 1.)

## User Persona (if applicable)

**Target User**: None directly (internal orchestration step). Transitively: the
end user pressing the activation key (PRD §3 story 1 — "a picker appears overlaid
on my status line without disturbing my normal window list"). T3 is what makes the
picker VISIBLE (one status line is claimed for the renderer) while preserving the
user's existing window-status line directly below it.

**Use Case**: The user presses the activation key. T1 saves state; T2 builds the
list + initial highlight. **T3 (this task)** grows the status bar from 1 line to
2, installs the renderer on line 1 (index 0), and leaves line 2 (index 1) as the
default composite so the user's tubular window-status line keeps rendering. From
this point the renderer is live; once T4/T5 land (key-table + first preview +
mode-on + `refresh-client -S`), the user sees the filtered session list update in
real time on the top line, with their normal status line untouched below.

**User Journey** (S1 scope — the renderer is installed and live, but the picker
does not yet react to keys; that is T4/T5):
1. User presses activation key → T1 guard + save; T2 list + index.
2. **T3 (this task):** shift any user status-format overrides up one index
   (none in this env → no-op); install `#(renderer.sh)` at `status-format[0]`;
   set `status 2` (grown from `on`). The status bar now has 2 lines.
3. [T4 switches key-table + binds keys + suppresses hook; T5 runs the first
   preview + sets `@livepicker-mode on` + `refresh-client -S` — later tasks.]
4. Once T5's `refresh-client -S` fires, line 1 shows the picker (the list/index
   T2 populated, rendered by the already-COMPLETE renderer P1.M2.T1.S1).

**Pain Points Addressed**:
- (a) **The picker must be visible without clobbering the user's status.** The
  naive "set status-format[0]=renderer, done" works but ONLY if the user had no
  status-format overrides AND the count grows. T3 does all three sub-steps
  correctly: shift (preserve overrides), install (claim line `IDX`), grow
  (one extra line so the user's status moves DOWN, not away).
- (b) **The `on`→`1` arithmetic trap.** tmux's `status` option returns/accepts
  `on`/`off`/`2..5` — **never** `0`/`1`. The item's literal
  `status $((orig_status_count + 1))` would (i) crash under `set -u` (`on` is an
  unbound variable in arithmetic) and (ii) even if it yielded `1`, tmux rejects
  `set-option -g status 1` ("unknown value: 1"). T3 normalizes via a `case`
  statement (research FINDING 1) — the difference between a working picker and a
  hard crash.
- (c) **Race-free shifting.** Adjacent user-set indices (e.g. `[3]`,`[4]`) would
  clobber each other if shifted ascending. T3 reverses the saved ascending list
  to **descending** before shifting (research FINDING 2) — provably correct for
  any index set, even though this env's set is empty.

## Why

- **PRD §10 steps 2–4.** Step 2 (shift user `status-format[n]`→`[n+1]`,
  highest-first), step 3 (`status-format[0]=#($SCRIPT_DIR/renderer.sh)`), step 4
  (`status` = current+1, typically `2`). T3 owns all three.
- **The visibility seam.** Until T3 runs, the renderer (P1.M2.T1.S1 — COMPLETE)
  is never invoked: nothing points `status-format[0]` at it and the status bar has
  only one line. T3 is what makes the renderer draw. (The renderer reads
  `@livepicker-list/filter/index` — populated by T2 in parallel — so the first
  draw will show real sessions, not an empty bar.)
- **Boundary respect.** T3 touches ONLY: `status-format[$n]` / `[$((n+1))]` (the
  user-set indices from `ORIG_STATUS_FORMAT_INDICES`), `status-format[$IDX]` (the
  renderer install), and `status` (the count). It does NOT touch
  `status-left`/`status-right`/`window-status-format` (tubular owns them; Invariant
  C requires they persist so line 2 renders), does NOT set `@livepicker-mode` (T5),
  does NOT switch key-table / bind keys / suppress the hook (T4), does NOT run a
  preview / `refresh-client` (T5). It reads: `ORIG_STATUS`,
  `ORIG_STATUS_FORMAT_INDICES` (saved by T1), `opt_status_format_index` (config),
  and live `status-format[$n]` values for the shift.
- **Scope cohesion.** T3 is the visibility foundation for T4/T5 (the key-table +
  first-preview + mode-on + refresh that make the picker INTERACTIVE). Restore
  (P1.M5.T3.S1) tears down exactly what T3 sets: `set-option -gu status-format`
  (clear all → re-compose defaults) + replay saved user indices at their ORIGINAL
  `[n]` + restore the `status` count. T3's writes and restore's resets are a
  matched pair.

## What

A surgical in-place edit to `scripts/livepicker.sh` that replaces the T3 seam
comment with a block which:

1. Declares function-locals (`sf_n`, `sf_val`, `sf_indices`, `lp_idx`,
   `orig_status`, and `local -a sf_desc=()`). Names are distinct from T2's
   (`pick_type current list idx i` / `items`) and avoid shadowing bash builtins.
2. **(a) Shift** — reads `ORIG_STATUS_FORMAT_INDICES` (the digit-only space-list
   of genuinely-user-set indices saved by T1; empty in this env → no-op). Reverses
   it to **descending** (race-free for adjacent indices) via array prepend. For
   each index `sf_n`: captures the live `status-format[$sf_n]` value, writes it to
   `status-format[$((sf_n + 1))]`, then `set-option -gu "status-format[$sf_n]"`
   (single-index unset — verified to kill ONLY that index).
3. **(b) Install** — reads `lp_idx="$(opt_status_format_index)"` (default `0`),
   then `tmux set-option -g "status-format[$lp_idx]" "#($CURRENT_DIR/renderer.sh)"`
   with **DOUBLE quotes** so `$CURRENT_DIR` expands to an absolute path at
   set-time (single quotes would store a literal `$CURRENT_DIR` → renderer never
   runs; research FINDING 3).
4. **(c) Grow count** — reads `orig_status="$(get_state "$ORIG_STATUS" "on")"`,
   then a `case` that normalizes tmux's `on`/`off`/`2..5` to a settable new value:
   `off|0|"" → on`, `on → 2`, `2|3|4 → n+1`, `5 → 5` (clamp), `* → 2` (defensive).
   This is MANDATORY: the literal `$((on+1))` crashes under `set -u` AND
   `set-option -g status 1` is rejected (research FINDING 1).

### Success Criteria

- [ ] The T3 seam comment is REPLACED by the block; T2 (above) and T4/T5 (below)
      seam comments and the trailing `return 0` / driver are UNCHANGED.
- [ ] Shift loop reads `ORIG_STATUS_FORMAT_INDICES` via `get_state`; reverses to
      descending via array prepend (`sf_desc=("$sf_n" "${sf_desc[@]}")`); for each,
      `show-option -gqv "status-format[$sf_n]"` → `set-option -g
      "status-format[$((sf_n+1))]"` → `set-option -gu "status-format[$sf_n]"`.
- [ ] Renderer install uses **DOUBLE** quotes: `tmux set-option -g
      "status-format[$lp_idx]" "#($CURRENT_DIR/renderer.sh)"`; `lp_idx` from
      `opt_status_format_index`.
- [ ] Count growth uses a `case` on `orig_status` (NOT `$((orig_status+1))`);
      maps `on→2`, `off|0|""→on`, `2|3|4→n+1`, `5→5`, `*→2`.
- [ ] **NO** mutation of `status-left`/`status-right`/`window-status-format`;
      **NO** `@livepicker-mode on`; **NO** key-table/bind-key/set-hook/
      link-window/switch-client/`refresh-client` (T4/T5's jobs).
- [ ] `bash -n` clean; `shellcheck` 0 findings; tabs only; no `set -e`.
- [ ] Mock (a) common: renderer@0, status==2, `[1]`≠renderer, status-left/right/
      window-status-format unchanged.
- [ ] Mock (b) shift: injected `[3]=USERVAL` → `[4]==USERVAL`, `[3]` unset.
- [ ] Mock (c) adjacent: `[3]=A,[4]=B` → `[4]==A,[5]==B`, `[3]` unset
      (highest-first proof).
- [ ] Mock (d) normalize: `status=off`→`on`; `status=3`→`4`.

## All Needed Context

### Context Completeness Check

_Pass_: A developer who has never seen this repo can implement T3 from
(a) the verbatim T3 block in the Implementation Blueprint (complete, ready to
paste at the seam), (b) the 5 live-verified findings in
`research/status_grow_findings.md` — most critically **FINDING 1** (the `status`
arithmetic showstopper: `show-option -gv status` returns `on`/`off`/`2..5` NOT
`0`/`1`; `$((on+1))` crashes under `set -u`; `set-option -g status 1` is rejected
→ MANDATORY `case` normalization), **FINDING 2** (shift is race-free
highest-first; single-index `-gu` kills only that index), and **FINDING 3**
(renderer install needs DOUBLE quotes so `$CURRENT_DIR` expands to an absolute
path), and (c) the socket-shim mock that exercises common + shift + adjacent +
normalization cases against an isolated socket with a pty client (zero live-server
impact). The INPUT dependencies (`opt_status_format_index`, `ORIG_STATUS`,
`ORIG_STATUS_FORMAT_INDICES`, `get_state`, `CURRENT_DIR`, the COMPLETE renderer)
are all present. The host file `scripts/livepicker.sh` is created by T1 with the
T3 seam comment; this task replaces exactly that line.

### Documentation & References

```yaml
# MUST READ — INPUT dependency: state.sh (the saved-state CONTRACT T3 reads). COMPLETE.
- file: scripts/state.sh
  why: Defines the EXACT keys T3 reads. READS: ORIG_STATUS
       ("@livepicker-orig-status", saved by T1's `tmux_save_opt status status` —
       holds the raw `show-option -gqv status` value, i.e. "on"/"off"/"2".."5"),
       ORIG_STATUS_FORMAT_INDICES ("@livepicker-orig-status-format-indices" —
       the digit-only space-list of genuinely-user-set status-format indices from
       state_status_format_save's >=3 heuristic; EMPTY in this env). Also defines
       get_state (thin wrapper over utils tmux_get_opt).
  critical: ORIG_STATUS holds the LITERAL tmux value ("on" etc.), NOT a normalized
            integer — T3 MUST normalize before setting `status` (FINDING 1).
            ORIG_STATUS_FORMAT_INDICES is empty here -> the shift loop is a no-op,
            but the loop MUST still be correct (highest-first) for generality.

# MUST READ — INPUT dependency: options.sh (the index accessor). COMPLETE (P1.M1.T1.S1).
- file: scripts/options.sh
  why: Defines opt_status_format_index() -> get_opt "@livepicker-status-format-index"
       "0" (PRD §11; int 0-9; default 0). T3 calls it to decide which status-format
       line the renderer claims.
  critical: Returns the STRING "0" by default. Used directly in
            "status-format[$lp_idx]" -> "status-format[0]". No arithmetic on it.

# MUST READ — the host file this task EDITS (created by P1.M4.T1.S1; T2 fills its seam in parallel).
- docfile: plan/001_fd5d622d3939/P1M4T1S1/PRP.md
  why: T1 CREATES scripts/livepicker.sh with the seam-comment skeleton. The T3
       seam comment is EXACTLY:
         # --- T3 (P1.M4.T3.S1): grow status bar + install renderer (insert here) ---
       It sits AFTER the T2 seam (list/index) and BEFORE the T4 seam. T3 REPLACES
       that single line with the block. Read this PRP to confirm the seam text and
       the surrounding context (CURRENT_DIR is computed at top level and is in
       scope inside activate_main as a global).
  section: "Implementation Patterns & Key Details" (the seam skeleton),
           "Integration Points"

# MUST READ — the parallel sibling: T2 (list/index). Its seam sits ABOVE T3.
- docfile: plan/001_fd5d622d3939/P1M4T2S1/PRP.md
  why: T2 populates @livepicker-list/filter/index (the renderer's data source) in
       the seam IMMEDIATELY before T3. T3 does NOT depend on T2's values directly,
       BUT both edit the same function — T3's locals must not collide with T2's
       (T2: pick_type/current/list/idx/i/items; T3: sf_n/sf_val/sf_indices/lp_idx/
       orig_status/sf_desc). Confirm T2's local names before finalizing T3's.
  section: "Implementation Patterns & Key Details" (T2 block's `local` line)

# MUST READ — the consumer/verification of T3's install: the renderer. COMPLETE (P1.M2.T1.S1).
- file: scripts/renderer.sh
  why: T3 installs THIS script via #() into status-format[0]. It is a pure, fast
       (<50ms) reader of @livepicker-list/filter/index that prints exactly one line.
       Its existence + proven execution means T3 only needs to store the correct
       literal path; the #() invocation is already validated end-to-end.
  pattern: |
    # status-format[0] = "#(<abs path>/scripts/renderer.sh)"
    # tmux #() runs it on every status redraw; refresh-client -S (T5/M6) forces redraw.

# MUST READ — the empirical ground-truth for THIS seam (5 live-verified findings).
- docfile: plan/001_fd5d622d3939/P1M4T3S1/research/status_grow_findings.md
  why: FINDING 1 (THE showstopper: status returns on/off/2..5 NOT 0/1; $((on+1))
       crashes under set -u; set-option -g status 1 rejected -> MANDATORY case
       normalization with the full mapping table); FINDING 2 (shift race-free
       highest-first; single-index -gu kills ONLY that index; ascending clobbers
       adjacent indices); FINDING 3 (renderer install needs DOUBLE quotes for
       $CURRENT_DIR expansion; single quotes store a literal -> broken); FINDING 4
       (shift source is ORIG_STATUS_FORMAT_INDICES, empty here -> no-op; live-read
       == saved value); FINDING 5 (status-format[1] default is the "fragile
       assumption" — manual real-env gate; do NOT touch status-left/right/window-
       status-format).
  critical: Read BEFORE writing the block. FINDING 1 is the highest-consequence
            detail — the item's literal `$((orig_status_count + 1))` is a hard
            crash under set -u; the case statement is non-optional.

# MUST READ — the PRD sections selected for this work item.
- docfile: PRD.md
  why: §10 steps 2-4 (shift highest-first; install renderer at [0]; set status to
       current+1, typically 2); §11 @livepicker-status-format-index (default 0);
       §9 (save/restore contract — T3 reads what STEP 2 saved); §13 primitives
       (status-format[n] array, set-option -gu single-index, status line count).
  section: "§10 Status-line setup (steps 2-4)", "§11 Configuration options",
           "§9 State saved and restored", "§13 tmux primitives reference"

# MUST READ — system ground-truth (Invariant C + shell style + the fragile assumption).
- docfile: plan/001_fd5d622d3939/architecture/system_context.md
  why: §3 INVARIANT C (status=2 + status-format[0]=#() + [1] unset -> line 2 =
       user's window-status composite; VERIFIED on real tubular env); §4 TRAP 1
       (status-format restore is -gu, not literal replay — T3's shift + restore's
       -gu are a matched pair); §9 shell style (set -u only NO -e, tabs, quote
       everything); §10 version floor (3.2+ for multi-line status; target is 3.6b).
  section: "§3 INVARIANT C", "§4 TRAP 1", "§9 Shell style", "§10 Version floor"

# MUST READ — the fragile-assessment + fallback for status-format[1].
- docfile: plan/001_fd5d622d3939/architecture/tmux_primitives.md
  why: §3 documents the "fragile assumption" (line 2 default composite) and the
       SAFE FALLBACK: if line 2 is blank/pane-composite on the real env, explicitly
       set status-format[1] to a composite of the user's status pieces. Also
       confirms highest-first shift is race-free.
  section: "§3 status-format[n], #(), refresh-client -S"
```

### Current Codebase tree

```bash
tmux-livepicker/
  PRD.md
  plugin.tmux                 # (P1.M1.T4.S1) COMPLETE. Binds prefix key -> scripts/livepicker.sh.
  plan/001_fd5d622d3939/{architecture/*.md, tasks.json, prd_snapshot.md, prd_index.txt}
  plan/001_fd5d622d3939/P1M4T1S1/{PRP.md, research/activate_guard_save_findings.md}  # creator of livepicker.sh (save)
  plan/001_fd5d622d3939/P1M4T2S1/{PRP.md, research/list_index_findings.md}            # parallel: list/index seam (ABOVE T3)
  plan/001_fd5d622d3939/P1M4T3S1/{PRP.md, research/status_grow_findings.md}           # THIS
  scripts/
    options.sh   # COMPLETE — opt_status_format_index (INPUT dep). Unchanged.
    utils.sh     # COMPLETE — tmux_* (transitively used by state.sh). INPUT dep.
    state.sh     # COMPLETE — ORIG_STATUS + ORIG_STATUS_FORMAT_INDICES + get_state. INPUT dep.
    renderer.sh  # COMPLETE (P1.M2.T1.S1). T3 installs it via #(). Unchanged.
    preview.sh   # COMPLETE (P1.M3). Unchanged. Structural analog (seam-comment model).
    livepicker.sh   # CREATED by P1.M4.T1.S1; T2 (parallel) fills the list seam. THIS task
                    # EDITS it (replaces the T3 seam comment with the status-grow block).
  .gitignore
  # NOTE: NO test harness (P1.M7). Validate via the throwaway socket-shim mock (+ pty client).
```

### Desired Codebase tree with files to be added and responsibility of file

```bash
tmux-livepicker/
  scripts/
    options.sh   # INPUT dep — unchanged.
    utils.sh     # INPUT dep — unchanged.
    state.sh     # INPUT dep — unchanged.
    renderer.sh  # unchanged.
    preview.sh   # unchanged.
    livepicker.sh   # EDITED (this task). The T3 seam comment is REPLACED by:
                    #   - locals (sf_n/sf_val/sf_indices/lp_idx/orig_status + local -a sf_desc=())
                    #   - (a) shift: read ORIG_STATUS_FORMAT_INDICES, reverse to descending,
                    #         per-index live-read -> set [n+1] -> unset [n] (no-op when empty)
                    #   - (b) install: opt_status_format_index -> status-format[$lp_idx] =
                    #         "#($CURRENT_DIR/renderer.sh)" (DOUBLE quotes)
                    #   - (c) grow: case on ORIG_STATUS -> set status (on->2, off->on,
                    #         2|3|4->n+1, 5->5, *->2)
                    # T4/T5 seams + return 0 + driver UNCHANGED. Still no mode-on (T5).
```

### Known Gotchas of our codebase & Library Quirks

```bash
# CRITICAL (research FINDING 1 — SHOWSTOPPER): tmux 3.6b `show-option -gv status`
# returns the LITERAL "on"/"off"/"2".."5" — NEVER "0"/"1". Two compounding traps:
#   (1) `$((orig_status + 1))` with orig_status="on": bash treats "on" as a
#       variable name -> unset -> under `set -u` -> "unbound variable", exit 127.
#       The activate function ABORTS. Verified live.
#   (2) Even if it yielded 1, `set-option -g status 1` -> "unknown value: 1"
#       (rc!=0; status UNCHANGED). Verified live.
# FIX: a `case` statement mapping on->2, off|0|""->on, 2|3|4->n+1, 5->5, *->2.
# Do NOT use arithmetic on the raw saved status string.

# CRITICAL (research FINDING 3): the renderer install MUST use DOUBLE quotes:
#   tmux set-option -g "status-format[$lp_idx]" "#($CURRENT_DIR/renderer.sh)"   # CORRECT
#   tmux set-option -g "status-format[$lp_idx]" '#($CURRENT_DIR/renderer.sh)'   # WRONG (literal)
# $CURRENT_DIR is bash-expanded at set-time to an absolute path; tmux #() then
# runs that path on every redraw. Single quotes store a literal "$CURRENT_DIR"
# and the renderer NEVER runs (blank line). $CURRENT_DIR is already computed at
# the top of livepicker.sh (the scripts/ dir) and is in scope as a global.

# CRITICAL (research FINDING 2): shift status-format indices HIGHEST-FIRST.
# Ascending clobbers adjacent indices ([3]=A,[4]=B ascending -> 3->4 overwrites B,
# then reads corrupted [4]). Descending (4->5, then 3->4) -> [4]=A,[5]=B correct.
# Reverse the saved ascending list via array prepend: sf_desc=("$n" "${sf_desc[@]}").
# `set-option -gu "status-format[$n]"` (WITH index) kills ONLY index n — verified.
# Do NOT use bare `set-option -gu status-format` (NO index) — that clears the
# WHOLE array (that is restore's job, P1.M5.T3.S1, NOT T3's).

# CRITICAL (research FINDING 5 / system_context §3 INVARIANT C): do NOT touch
# status-left / status-right / window-status-format. Tubular owns them; they MUST
# persist so line 2 (status-format[1], left at its default) composes the user's
# normal window-status line. T3 touches ONLY status-format[$IDX] + shifted
# [n]/[n+1] + the status count. The line-2 visual is the "fragile assumption"
# (tmux_primitives §3) — verify manually on the real tubular env; if blank/pane-
# composite, the documented fallback is to explicitly set status-format[1].

# GOTCHA (research FINDING 4): the shift source is ORIG_STATUS_FORMAT_INDICES
# (the >=3 space-list from state_status_format_save). In THIS env it is EMPTY ->
# the shift loop is a no-op. Read it via get_state "$ORIG_STATUS_FORMAT_INDICES"
# ""; do NOT re-probe status-format (T1 already saved the canonical index list).
# Word-splitting the empty string yields zero iterations (safe under set -u).

# GOTCHA: variable naming. T2 (parallel, seam ABOVE T3) already declares locals
# pick_type/current/list/idx/i/items. T3 uses DISTINCT names (sf_n/sf_val/
# sf_indices/lp_idx/orig_status/sf_desc) to avoid confusion. Do NOT name a local
# `index` (collides conceptually with T2's idx) or `status` (shadows nothing but
# is confusing). `lp_idx` = the status-format line index; `orig_status` = saved.

# GOTCHA: this task is a SURGICAL EDIT at the T3 seam, not a rewrite. Replace
# EXACTLY the T3 seam comment line; leave T2's block (above), the T4/T5 seam
# comments (below), the trailing `return 0`, and the driver untouched. If T2 is
# still in flight in parallel, re-read the file fresh at implementation time and
# match whatever seam text T1 actually wrote.

# CRITICAL: NO `set -e`, NO `set -o pipefail` (house style; system_context §9).
# `show-option -gqv "status-format[$n]"` legitimately returns non-zero/rc=1 when
# the index is unset; under set -e that would abort mid-shift. The shift captures
# via $(...) with 2>/dev/null and proceeds (an unset source index just yields
# sf_val="" -> writes empty to [n+1] -> harmless because the index list only
# contains genuinely-set indices anyway). set -u is inherited; every var is
# assigned first (sf_n/sf_val/sf_indices/lp_idx/orig_status/sf_desc).

# STYLE (system_context §9): indent with TABS. Verify with
# `grep -Pn '^    ' scripts/livepicker.sh` (expect empty). shfmt is NOT installed.
```

## Implementation Blueprint

### Data models and structure

No new data model. The block adds function-locals to `activate_main`:
`sf_n`, `sf_val`, `sf_indices`, `lp_idx`, `orig_status`, and `local -a sf_desc=()`.
The state surface is the **read set**: `ORIG_STATUS`, `ORIG_STATUS_FORMAT_INDICES`
(saved by T1's STEP 2). The **write surface** is the tmux options:
`status-format[$n]` (unset), `status-format[$((n+1))]` (set), `status-format[$lp_idx]`
(set to the renderer), and `status` (set to the normalized count). No `@livepicker-*`
keys are written by T3 (the list/filter/index/mode/linked-id are owned by T1/T2/T5).

### Implementation Tasks (ordered by dependencies)

```yaml
Task 1: LOCATE the T3 seam in scripts/livepicker.sh
  - FILE: ./scripts/livepicker.sh  (CREATED by P1.M4.T1.S1; T2 fills its seam in parallel).
  - FIND the single seam comment line (T1's skeleton emits EXACTLY):
      # --- T3 (P1.M4.T3.S1): grow status bar + install renderer (insert here) ---
  - CONTEXT: it sits AFTER the T2 seam (list/index block, once T2 lands) and
    BEFORE the T4 seam comment:
      # --- T4 (P1.M4.T4.S1/S2): switch key-table + bind keys + suppress hook (insert here) ---
  - VERIFY (do not proceed if mismatched — T2 may still be in flight; re-read the
    file fresh at implementation time): the line exists exactly once.

Task 2: REPLACE the T3 seam comment with the status-grow block
  - OLD (exact): the single T3 seam comment line from Task 1.
  - NEW: the block below (indented with ONE tab to match activate_main's body;
    inner lines TWO tabs). See "Implementation Patterns & Key Details" for the
    complete ready-to-paste block.
  - NOTE: locals are DISTINCT from T2's (sf_n/sf_val/sf_indices/lp_idx/orig_status/
    sf_desc vs T2's pick_type/current/list/idx/i/items). If T2 is still in flight,
    confirm its local names fresh and adjust only if there is an actual collision
    (there is not, by design).

Task 3: VERIFY the edit left T2 (if present), T4/T5 seams + return 0 + driver intact
  - RUN: grep -n 'T2 (P1.M4.T2.S1)\|T4 (P1.M4.T4\|T5 (P1.M4.T5.S1\|return 0\|activate_main "\$@"' scripts/livepicker.sh
  - EXPECT: the T2 header (if T2 landed), the T4/T5 seam comments, a `return 0`,
    and the trailing driver are ALL still present and unchanged.
  - EXPECT: the OLD T3 seam comment is GONE (replaced); the new block header
    `# --- T3 (P1.M4.T3.S1): grow status bar + install renderer ---` is present once.

Task 4: VALIDATE (Level 1 syntax/lint + Level 2 socket-shim mock common/shift/adjacent/normalize)
  - RUN: bash -n scripts/livepicker.sh            (expect exit 0, no output)
  - RUN: shellcheck scripts/livepicker.sh         (expect 0 findings — file-level
    disable=SC1091,SC2153 from T1 covers source-lines + ORIG_*/STATE_*; the T3
    block's one intentional word-split is annotated # shellcheck disable=SC2086)
  - RUN: grep -Pn '^    ' scripts/livepicker.sh   (expect empty — tabs only)
  - RUN the socket-shim mock (Validation Loop §2) — common (a) + shift (b) +
    adjacent (c) + normalization (d), against an isolated socket WITH a pty
    client. Self-cleaning.
```

### Implementation Patterns & Key Details

The complete, ready-to-paste T3 block (the implementer replaces the T3 seam
comment with this; indent is one tab for the block, two tabs inside `for`/`case`):

```bash
	# --- T3 (P1.M4.T3.S1): grow status bar + install renderer ---
	# PRD §10 steps 2-4, in order:
	#   (a) SHIFT every genuinely-user-set status-format index up by one,
	#       HIGHEST-FIRST (race-free — PRD §10 step 2 / tmux_primitives §3).
	#       Source = ORIG_STATUS_FORMAT_INDICES (the >=3 space-list STEP 2 saved;
	#       EMPTY in this env -> no-op). We read the LIVE value and copy to [n+1],
	#       then unset [n] (single-index -gu kills ONLY [n] — research FINDING 2).
	#       Restore (P1.M5.T3.S1) replays the saved values at the ORIGINAL [n]
	#       after a -gu reset, so the user's overrides return to [n].
	#   (b) INSTALL the picker renderer at IDX (=@livepicker-status-format-index,
	#       default 0). DOUBLE quotes so $CURRENT_DIR expands to an ABSOLUTE path
	#       at set-time; tmux #() then runs it on every redraw. Single quotes
	#       would store a literal "$CURRENT_DIR" -> renderer never runs
	#       (research FINDING 3).
	#   (c) GROW the status line count by one (PRD §10 step 4). GOTCHA: tmux 3.6b
	#       show-option -gv status returns on/off/2..5 — NOT 0/1; the literal
	#       integer 1 is REJECTED ("unknown value: 1") and $((on+1)) CRASHES under
	#       set -u ("unbound variable"). So normalize via case: on->2, off->on,
	#       2..4->n+1, 5->5 (clamp). status-left/right/window-status-format are
	#       LEFT UNTOUCHED (tubular owns them; Invariant C: line 2 composes from
	#       them when status-format[1] is unset — research FINDING 5).
	local sf_n sf_val sf_indices lp_idx orig_status
	local -a sf_desc=()
	# (a) shift genuinely-user-set indices HIGHEST-FIRST (no-op when the saved
	# list is empty, as in this env). sf_indices is a digit-only space-list
	# (state.sh contract); word-split is intentional and safe.
	sf_indices="$(get_state "$ORIG_STATUS_FORMAT_INDICES" "")"
	# Reverse the ascending saved list to DESCENDING (race-free for adjacent
	# indices; ascending would overwrite the next index's original value).
	# shellcheck disable=SC2086
	for sf_n in $sf_indices; do sf_desc=("$sf_n" "${sf_desc[@]}"); done
	for sf_n in "${sf_desc[@]}"; do
		sf_val="$(tmux show-option -gqv "status-format[$sf_n]" 2>/dev/null)"
		tmux set-option -g "status-format[$((sf_n + 1))]" "$sf_val"
		tmux set-option -gu "status-format[$sf_n]"
	done
	# (b) install the picker renderer at the configured index (default 0).
	lp_idx="$(opt_status_format_index)"
	tmux set-option -g "status-format[$lp_idx]" "#($CURRENT_DIR/renderer.sh)"
	# (c) grow the status line count by one — NORMALIZED for tmux's on/off/2..5
	# (do NOT use $((orig_status + 1)): "on" crashes under set -u and 1 is rejected).
	orig_status="$(get_state "$ORIG_STATUS" "on")"
	case "$orig_status" in
		off|0|"") tmux set-option -g status on  ;;   # was off -> 1 picker line
		on)       tmux set-option -g status 2   ;;   # was 1 line -> 2 (typical)
		2|3|4)    tmux set-option -g status "$((orig_status + 1))" ;;
		5)        tmux set-option -g status 5   ;;   # 5-line cap; renderer overlays [lp_idx] (rare)
		*)        tmux set-option -g status 2   ;;   # defensive default
	esac
```

NOTE for the implementer:
- This block is verified end-to-end (shellcheck clean; all mock assertions in the
  Validation Loop pass against the REAL sibling libs on an isolated socket with a
  pty client — see research/status_grow_findings.md FINDINGS 1–5). Use it as-is;
  the only allowed deviation is comment phrasing.
- The OLD line to replace is EXACTLY:
  `	# --- T3 (P1.M4.T3.S1): grow status bar + install renderer (insert here) ---`
  (one leading tab). If T1's emitted comment differs in whitespace/wording, match
  whatever T1 actually wrote (re-read the file fresh at implementation time; T2
  may still be in flight in parallel — confirm T2's local names if needed).
- Do NOT add `set -e`. Do NOT use arithmetic on the raw `orig_status` string (use
  the `case`). Do NOT single-quote the renderer install (double quotes only). Do
  NOT use bare `set-option -gu status-format` (always include the `[n]` index in
  the shift; the index-less form clears the whole array — restore's job). Do NOT
  touch status-left/status-right/window-status-format. Do NOT set
  `@livepicker-mode on`. Do NOT touch T2's block, the T4/T5 seams, `return 0`, or
  the driver. Do NOT create any other file.

### Integration Points

```yaml
HOST FILE (what this task edits — created by P1.M4.T1.S1; T2 fills its seam in parallel):
  - scripts/livepicker.sh: activate_main(). T3 replaces the T3 seam comment,
    which sits after the T2 seam (list/index) and before the T4 seam. The guard
    (STEP 1) and save (STEP 2) are ABOVE; T4/T5 and `return 0` are BELOW. T3 runs
    only after the guard passes and STEP 2 saved ORIG_STATUS +
    ORIG_STATUS_FORMAT_INDICES. CURRENT_DIR (computed at top level) is in scope.

CALLERS / CONSUMERS (this task's OUTPUT — read/observed by FUTURE subtasks + the renderer):
  - renderer.sh (P1.M2.T1.S1 — COMPLETE): is invoked by tmux #() on every status
        redraw BECAUSE T3 pointed status-format[$lp_idx] at it. Before T3, the
        renderer is never called; after T3, the next redraw (or T5's
        refresh-client -S) draws the picker.
  - P1.M4.T5.S1 (first preview + mode-on + refresh): calls refresh-client -S,
        which forces the #() re-eval T3 installed -> the picker draws with the
        list/index T2 populated. T5 also sets @livepicker-mode on LAST.
  - P1.M6 (input handler): each keystroke ends with refresh-client -S -> the T3-
        installed renderer re-draws the filtered list.
  - P1.M5.T3.S1 (restore status-format + status): tears down EXACTLY what T3 set:
        set-option -gu status-format (clear ALL -> re-compose defaults), replay
        saved user indices at ORIGINAL [n], restore the status count from
        ORIG_STATUS. T3's shift (n -> n+1) and restore's replay (back to n) are a
        matched pair.

STATE READS (this task):
  - @livepicker-orig-status                (via get_state "$ORIG_STATUS"; saved by T1)
  - @livepicker-orig-status-format-indices (via get_state "$ORIG_STATUS_FORMAT_INDICES";
                                            saved by state_status_format_save in STEP 2)
  - @livepicker-status-format-index        (via opt_status_format_index; config — default "0")

STATE WRITES (this task): NONE (no @livepicker-* keys written by T3).

TMUX MUTATIONS (this task — PRD §13 primitives):
  - status-format[$((n+1))] set (the shifted user overrides; none in this env)
  - status-format[$n] unset (single-index -gu; none in this env)
  - status-format[$lp_idx] set to "#($CURRENT_DIR/renderer.sh)" (the renderer install)
  - status set to the normalized count (on->2 typical)
  - NO mutation of status-left / status-right / window-status-format / window-status-
    current-format / window-status-separator (tubular-owned; Invariant C).
  - NO switch-client, NO select-window, NO link-window/unlink-window, NO set-hook,
        NO bind-key, NO refresh-client, NO set-option key-table, NO @livepicker-mode.

DATABASE / MIGRATIONS / ROUTES / CONFIG: none.
```

## Validation Loop

### Level 1: Syntax & Style (Immediate Feedback)

```bash
# Run after the edit — fix before proceeding.
bash -n scripts/livepicker.sh                     # syntax; expect no output, exit 0
shellcheck scripts/livepicker.sh                  # lint; expect 0 findings (file-level
                                                  # disable=SC1091,SC2153 from T1 covers it;
                                                  # the T3 word-split is annotated SC2086)
# Tabs-not-spaces sanity (shfmt NOT installed):
grep -Pn '^    ' scripts/livepicker.sh && echo "FAIL: 4-space indent found, use tabs" || echo "OK: tabs only"
# Confirm the T3 seam was REPLACED (old comment gone, new header present once):
grep -c 'grow status bar + install renderer (insert here)' scripts/livepicker.sh   # expect 0
grep -c 'T3 (P1.M4.T3.S1): grow status bar + install renderer' scripts/livepicker.sh  # expect 1
# Confirm T2 (if landed) + T4/T5 seams + return 0 + driver survived:
grep -n 'T2 (P1.M4.T2.S1)\|T4 (P1.M4.T4\|T5 (P1.M4.T5.S1' scripts/livepicker.sh   # expect the seam comments
grep -nE '^\treturn 0$' scripts/livepicker.sh                                     # expect the trailing return 0
grep -n 'activate_main "\$@" || exit 1' scripts/livepicker.sh                     # expect the driver
# Confirm NO mode-on / key-table / hook / preview / refresh leaked into T3:
grep -n 'set-option -g "@livepicker-mode" on\|set_state "$STATE_MODE" "on"' scripts/livepicker.sh \
  && echo "FAIL: T3 must NOT turn mode on" || echo "OK: mode-on deferred to T5"
grep -n 'link-window\|switch-client\|set-hook\|bind-key\|refresh-client\|set-option.*key-table' scripts/livepicker.sh \
  && echo "FAIL: T3 must not mutate keys/hook/preview/refresh" || echo "OK: T3 is status-only"
# Confirm T3 did NOT touch tubular-owned status pieces:
grep -n 'set-option.*status-left\|set-option.*status-right\|set-option.*window-status-format' scripts/livepicker.sh \
  && echo "FAIL: T3 must not touch status-left/right/window-status-format" || echo "OK: tubular status untouched"
# Run from the repo root.
```

### Level 2: Socket-Shim Mock Validation — common + shift + adjacent + normalize, zero live-server impact

Reuses the PATH-wrapper socket shim PLUS a pty client (T1's display-message save
needs one; T3 reads its saved result). Self-cleaning. Sources the REAL
`scripts/{options,utils,state}.sh` and runs the ACTUAL `scripts/livepicker.sh`.

```bash
#!/usr/bin/env bash
# Throwaway socket-shim validation for scripts/livepicker.sh T3 (do NOT commit).
set -u
REPO_ROOT="$(cd "$(dirname "$0")" && pwd)"
[ -f "$REPO_ROOT/scripts/livepicker.sh" ] || { echo "livepicker.sh missing"; exit 1; }
for l in options utils state renderer; do
	[ -f "$REPO_ROOT/scripts/$l.sh" ] || { echo "INPUT dep $l.sh missing"; exit 1; }
done

SOCK="lp-t3-mock-$$"
SHIM_DIR="$(mktemp -d)"
cat > "$SHIM_DIR/tmux" <<EOF
#!/usr/bin/env bash
exec /usr/bin/tmux -L "$SOCK" "\$@"
EOF
chmod +x "$SHIM_DIR/tmux"
export PATH="$SHIM_DIR:$PATH"

cleanup() {
	PATH="/usr/bin:/bin:$PATH" tmux -L "$SOCK" kill-server 2>/dev/null || true
	rm -rf "$SHIM_DIR" /tmp/lp-t3-pty.log
}
trap cleanup EXIT

pass=0; fail=0
assert() { if [ "$2" = "$3" ]; then pass=$((pass+1)); printf 'ok   %s\n' "$1"; else fail=$((fail+1)); printf 'FAIL %s: got=[%s] want=[%s]\n' "$1" "$2" "$3"; fi; }
rg() { tmux show-option -gqv "$1"; }
attach() { TMUX="" script -qec "tmux -L $SOCK attach -t $1" /dev/null >/dev/null 2>&1 & AP=$!; sleep 0.5; }
detach() { kill "$AP" 2>/dev/null; wait "$AP" 2>/dev/null; }
clear_lp() {
	for k in mode list filter index linked-id type orig-session orig-window orig-layout \
	         orig-key-table orig-status orig-renumber-windows orig-session-window-changed \
	         orig-status-format-indices; do tmux set-option -gu "@livepicker-$k" 2>/dev/null; done
}

# ---------- (a) COMMON CASE: status on (default), no user status-format overrides ----------
tmux new-session -d -s aaa -x 80 -y 24
SL_BEFORE="$(rg status-left)"; SR_BEFORE="$(rg status-right)"; WSF_BEFORE="$(rg window-status-format)"
tmux set-option -g "@livepicker-type" "session"
attach aaa
bash "$REPO_ROOT/scripts/livepicker.sh"; rc=$?
detach
assert "common: exit 0" "$rc" "0"
assert "common: status grown on->2" "$(rg status)" "2"
assert "common: renderer at [0]" "$(rg 'status-format[0]')" "#($REPO_ROOT/scripts/renderer.sh)"
assert "common: [1] is NOT the renderer (untouched default)" "$(rg 'status-format[1]' | head -c 20)" "#[align=left]#{R: ,#{n"
assert "common: status-left unchanged" "$(rg status-left)" "$SL_BEFORE"
assert "common: status-right unchanged" "$(rg status-right)" "$SR_BEFORE"
assert "common: window-status-format unchanged" "$(rg window-status-format)" "$WSF_BEFORE"
assert "common: no user indices saved (env has none)" "$(rg "@livepicker-orig-status-format-indices")" ""
clear_lp
tmux set-option -gu 'status-format[0]' 2>/dev/null; tmux set-option -g status on  # reset for next test

# ---------- (b) SHIFT CASE: inject a genuinely-user-set status-format[3] ----------
tmux set-option -g 'status-format[3]' 'USERVAL'
attach aaa
bash "$REPO_ROOT/scripts/livepicker.sh"; rc=$?
detach
assert "shift: exit 0" "$rc" "0"
assert "shift: [3] value moved to [4]" "$(rg 'status-format[4]')" "USERVAL"
assert "shift: [3] unset (single-index -gu)" "$(rg 'status-format[3]')" ""
assert "shift: renderer still at [0]" "$(rg 'status-format[0]')" "#($REPO_ROOT/scripts/renderer.sh)"
assert "shift: status==2" "$(rg status)" "2"
clear_lp
tmux set-option -gu 'status-format[3]' 2>/dev/null; tmux set-option -gu 'status-format[4]' 2>/dev/null
tmux set-option -g status on

# ---------- (c) ADJACENT-SHIFT CASE: [3]=A, [4]=B (proves HIGHEST-FIRST) ----------
tmux set-option -g 'status-format[3]' 'A'
tmux set-option -g 'status-format[4]' 'B'
attach aaa
bash "$REPO_ROOT/scripts/livepicker.sh"; rc=$?
detach
assert "adjacent: exit 0" "$rc" "0"
assert "adjacent: [4]==A (3->4, no clobber)" "$(rg 'status-format[4]')" "A"
assert "adjacent: [5]==B (4->5, original B survived)" "$(rg 'status-format[5]')" "B"
assert "adjacent: [3] unset" "$(rg 'status-format[3]')" ""
assert "adjacent: renderer at [0]" "$(rg 'status-format[0]')" "#($REPO_ROOT/scripts/renderer.sh)"
clear_lp
for i in 3 4 5; do tmux set-option -gu "status-format[$i]" 2>/dev/null; done
tmux set-option -g status on

# ---------- (d) NORMALIZATION CASE: status off -> on; status 3 -> 4 ----------
tmux set-option -g status off
attach aaa
bash "$REPO_ROOT/scripts/livepicker.sh" 2>/dev/null; rc=$?
detach
assert "norm off: exit 0 (no set -u crash)" "$rc" "0"
assert "norm off->on (1 is rejected; use on)" "$(rg status)" "on"
clear_lp
tmux set-option -gu 'status-format[0]' 2>/dev/null; tmux set-option -g status 3
attach aaa
bash "$REPO_ROOT/scripts/livepicker.sh" 2>/dev/null; rc=$?
detach
assert "norm 3->4" "$(rg status)" "4"
assert "norm 3->4: renderer at [0]" "$(rg 'status-format[0]')" "#($REPO_ROOT/scripts/renderer.sh)"

printf '\n==== PASS=%d FAIL=%d ====\n' "$pass" "$fail"
[ "$fail" = "0" ]
# Expected: PASS=20 FAIL=0. Key proofs:
#  - common: renderer@0, status on->2, [1] is the default composite (NOT renderer),
#    status-left/right/window-status-format UNCHANGED (Invariant C boundary).
#  - shift: injected [3]=USERVAL -> [4]==USERVAL, [3] unset (single-index -gu).
#  - adjacent: [3]=A,[4]=B -> [4]==A,[5]==B (highest-first; ascending would lose B).
#  - normalize: off->on (NOT 1, which is rejected); 3->4. Proves the case-statement
#    avoids the $((on+1)) set -u crash and the status-1 rejection.
```

### Level 3: Integration Testing (System Validation)

```bash
# Live spot-check on an ISOLATED socket WITH an attached pty client — confirms the
# installed #() path is the ACTUAL renderer and that a refresh-client -S forces a
# redraw (the mechanism T5/M6 will use). Self-cleaning.
export LP_SOCK="lp-t3-live-$$"
REPO_ROOT="$(pwd)"
SHIM_DIR="$(mktemp -d)"
cat > "$SHIM_DIR/tmux" <<EOF
#!/usr/bin/env bash
exec /usr/bin/tmux -L "$LP_SOCK" "\$@"
EOF
chmod +x "$SHIM_DIR/tmux"
trap 'PATH=/usr/bin:/bin:$PATH tmux -L "$LP_SOCK" kill-server 2>/dev/null; rm -rf "$SHIM_DIR"' EXIT
T() { PATH="$SHIM_DIR:$PATH" tmux "$@"; }
T new-session -d -s demo -x 120 -y 40
T set-option -g "@livepicker-type" "session"
TMUX="" script -qec "tmux -L $LP_SOCK attach -t demo" /dev/null >/dev/null 2>&1 &
AP=$!; sleep 0.5
PATH="$SHIM_DIR:$PATH" bash "$REPO_ROOT/scripts/livepicker.sh"; echo "rc=$? (expect 0)"
kill "$AP" 2>/dev/null; wait "$AP" 2>/dev/null
echo "status=[$(T show-option -gv status)] (expect 2)"
echo "status-format[0]=[$(T show-option -gqv 'status-format[0]')] (expect #(abs path)/scripts/renderer.sh)"
echo "orig-status=[$(T show-option -gqv '@livepicker-orig-status')] (expect on)"
echo "orig-status-format-indices=[$(T show-option -gqv '@livepicker-orig-status-format-indices')] (expect empty)"
# Confirm the renderer WOULD draw: invoke it directly with the state T2 populated.
echo "renderer direct output: [$(PATH="$SHIM_DIR:$PATH" bash "$REPO_ROOT/scripts/renderer.sh")]"
# Expected: status==2; status-format[0]==#(<abs>/scripts/renderer.sh); renderer
# prints the picker line for the demo session (proves the install target is live).
```

### Level 4: Creative & Domain-Specific Validation

```bash
# MANUAL real-env gate (the "fragile assumption" — tmux_primitives §3 / FINDING 5).
# On the REAL tubular server (NOT the isolated socket), after a real activation:
#   1. Confirm the status bar grew to 2 lines.
#   2. Confirm line 1 (top) shows the picker (the renderer output).
#   3. Confirm line 2 (bottom) shows the user's NORMAL window-status line
#      (status-left + window list + status-right) — NOT a blank line and NOT the
#      pane-status composite.
# This is the ONE behavior the socket-shim mock cannot fully prove (the isolated
# socket materializes status-format defaults; tubular UNSETS them, so the line-2
# composition differs). Invariant C (system_context §3) was verified on the real
# tubular env, so the expected result is: line 2 == the window list.
#
# FALLBACK (only if line 2 is blank or shows the pane composite): explicitly set
# status-format[1] to a composite of the user's status pieces, e.g.:
#   tmux set-option -g 'status-format[1]' \
#     '#{?#{==:#{E:status-left-length},0},,#[align=left range=left]#{status-left}}#{W:...}#{status-right}'
# (tmux_primitives §3 "Safe fallback".) Document the finding; do NOT silently rely
# on the default if the real-env test shows otherwise. In the target env this is
# expected to be UNNECESSARY (Invariant C verified).

# Pollution invariant spot-check (PRD §15.18) for the T3 status grow. Growing the
# status bar + installing the renderer must NOT fire client-session-changed (T3
# never calls switch-client). Run ONLY if @session-history-hist is present on the
# LIVE server; touches ONLY option reads + the @livepicker-* keys + one isolated
# run of livepicker.sh.
if tmux show-options -gv "@session-history-hist" >/dev/null 2>&1; then
    REPO_ROOT="$(pwd)"
    BEFORE="$(tmux show-options -gv "@session-history-hist" 2>/dev/null)"
    bash "$REPO_ROOT/scripts/livepicker.sh" 2>/dev/null
    AFTER="$(tmux show-options -gv "@session-history-hist" 2>/dev/null)"
    for k in mode list filter index linked-id type; do
        tmux set-option -gu "@livepicker-$k" 2>/dev/null
    done
    if [ "$BEFORE" = "$AFTER" ]; then
        echo "OK: @session-history-hist UNCHANGED across T3 status grow (Invariant A holds)"
    else
        echo "FAIL: history polluted by T3 (should be impossible — no switch-client)"
    fi
else
    echo "SKIP: tmux-session-history not present on live server (mock §2 covers this structurally)"
fi
# Expected: OK — T3 never calls switch-client, so client-session-changed never fires.
```

## Final Validation Checklist

### Technical Validation

- [ ] `bash -n scripts/livepicker.sh` exits 0 with no output.
- [ ] `shellcheck scripts/livepicker.sh` reports 0 findings (file-level disable
      from T1 covers source-lines + ORIG_*/STATE_*; the T3 word-split is SC2086-annotated).
- [ ] No 4-space indents (`grep -Pn '^    '` is empty); tabs only.

### Feature Validation

- [ ] The T3 seam comment is REPLACED by the block; the new header comment
      `# --- T3 (P1.M4.T3.S1): grow status bar + install renderer ---` appears
      exactly once; the old `(insert here)` comment is gone.
- [ ] T2's block (if landed), T4/T5 seam comments, `return 0`, and the trailing
      driver are UNCHANGED.
- [ ] Shift loop: reads `ORIG_STATUS_FORMAT_INDICES` via `get_state`; reverses to
      descending via `sf_desc=("$sf_n" "${sf_desc[@]}")`; per-index
      `show-option -gqv "status-format[$sf_n]"` → `set-option -g
      "status-format[$((sf_n+1))]"` → `set-option -gu "status-format[$sf_n]"`.
- [ ] Renderer install: `lp_idx="$(opt_status_format_index)"`; DOUBLE-quoted
      `"#($CURRENT_DIR/renderer.sh)"`.
- [ ] Count growth: `case "$orig_status"` with `off|0|""→on`, `on→2`,
      `2|3|4→n+1`, `5→5`, `*→2`. NO `$((orig_status+1))` on the raw string.
- [ ] **NO** mutation of status-left/status-right/window-status-format.
- [ ] **NO** `@livepicker-mode on`; **NO** key-table/bind-key/set-hook/
      link-window/switch-client/refresh-client.
- [ ] Mock (a) common: renderer@0, status==2, `[1]`≠renderer, tubular status
      pieces unchanged; PASS all.
- [ ] Mock (b) shift: `[3]=USERVAL` → `[4]==USERVAL`, `[3]` unset.
- [ ] Mock (c) adjacent: `[3]=A,[4]=B` → `[4]==A,[5]==B`, `[3]` unset.
- [ ] Mock (d) normalize: off→on; 3→4.

### Code Quality Validation

- [ ] NO `set -e`, NO `set -o pipefail` (house style; system_context §9).
- [ ] All expansions double-quoted (`"$sf_val"`, `"status-format[$((sf_n+1))]"`,
      `"#($CURRENT_DIR/renderer.sh)"`, `"$orig_status"`).
- [ ] Shift uses single-index `set-option -gu "status-format[$n]"` (WITH `[n]`),
      never the index-less whole-array form.
- [ ] Locals distinct from T2's; none shadow bash builtins.
- [ ] No new files created; no other source file touched.

### Documentation & Deployment

- [ ] Block header comment states: PRD §10 steps 2-4; highest-first shift rationale;
      the empty-env no-op; DOUBLE-quote install rationale; the status `on`/`1`
      gotcha + case normalization; the Invariant C boundary (do not touch
      status-left/right/window-status-format).
- [ ] No README/doc file created (DOCS = Mode A; covered by README P1.M8.T1.S1).
- [ ] No tmux.conf edit; no tests/ dir committed.

---

## Anti-Patterns to Avoid

- ❌ Don't use `$((orig_status + 1))` on the raw saved status string. tmux returns
  `on`/`off`/`2..5` (never `0`/`1`); `on` is an unbound variable under `set -u`
  arithmetic → crash; and `set-option -g status 1` is rejected. Use the `case`
  normalization (research FINDING 1). This is the single highest-risk mistake.
- ❌ Don't single-quote the renderer install. `'#($CURRENT_DIR/renderer.sh)'`
  stores a literal `$CURRENT_DIR` and the renderer NEVER runs (blank line). Use
  DOUBLE quotes so bash expands `$CURRENT_DIR` to an absolute path at set-time
  (research FINDING 3).
- ❌ Don't shift ascending. Adjacent user-set indices (`[3]`,`[4]`) would clobber
  each other (3→4 overwrites original [4], then reads the corrupted value). Reverse
  to DESCENDING first (`sf_desc=("$sf_n" "${sf_desc[@]}")`) (research FINDING 2).
- ❌ Don't use the index-less `set-option -gu status-format` in the shift. That
  clears the WHOLE array (it is restore's job, P1.M5.T3.S1). The shift unsets ONE
  index at a time: `set-option -gu "status-format[$n]"` (WITH `[n]`) (research FINDING 2).
- ❌ Don't touch status-left / status-right / window-status-format /
  window-status-current-format / window-status-separator. Tubular owns them;
  Invariant C requires they persist so line 2 renders the user's window list
  (research FINDING 5 / system_context §3). T3 touches ONLY status-format[IDX] +
  shifted [n]/[n+1] + the status count.
- ❌ Don't re-probe status-format for "which indices are user-set." T1 already
  saved the canonical list in `ORIG_STATUS_FORMAT_INDICES` (the ≥3 heuristic;
  state.sh). T3 reads THAT; re-probing would duplicate T1's logic and risk
  divergence.
- ❌ Don't set `@livepicker-mode on`, don't switch key-table / bind keys / suppress
  the hook, don't run a preview, don't `refresh-client`. Those are T4/T5. T3 owns
  ONLY the status bar (shift + install + count) (research: boundary).
- ❌ Don't rewrite `livepicker.sh` or touch any other file. This is a SURGICAL
  EDIT: replace the single T3 seam comment with the block. Leave T1's guard/save,
  T2's block, the T4/T5 seams, `return 0`, and the driver exactly as written.
- ❌ Don't add `set -e`/`set -o pipefail`. `show-option -gqv "status-format[$n]"`
  returns non-zero when the index is unset; under `set -e` that would abort
  mid-shift. Guard captures with `2>/dev/null`, not `set -e`.
- ❌ Don't rely on the socket-shim mock to prove line-2 renders the user's window
  list. The isolated socket materializes status-format defaults (so `[1]` = pane
  composite); only the REAL tubular env (which UNSETS status-format) exhibits
  Invariant C. Use the Level 4 manual gate for that one behavior (research FINDING 5).
- ❌ Don't create a `tests/` directory or committed test file — the harness is
  invented in P1.M7. Validate via the throwaway socket-shim mock (Level 2).
- ❌ Don't use 4-space indent — tabs only (system_context §9).

---

## Confidence Score

**9 / 10** for one-pass success. Rationale: the deliverable is a ~30-line surgical
insertion into a file created by T1 (with T2 filling the seam above in parallel),
whose complete body is given verbatim in the Implementation Blueprint and whose
every behavior was verified LIVE on `tmux 3.6b` against an isolated socket with a
pty client: `bash -n` clean, `shellcheck` 0 findings, tabs only, and 20/20 mock
assertions pass across the common / shift / adjacent-shift / normalization cases.
The single highest-risk trap — the `status` arithmetic crash under `set -u`
(`on` is an unbound variable; `1` is rejected) — is resolved by the mandatory
`case` normalization (research FINDING 1), which was verified to map `off→on`,
`on→2`, `3→4` correctly. The shift mechanism was verified race-free highest-first
(FINDING 2: `[3]=A,[4]=B` → `[4]=A,[5]=B`, no clobber), and the renderer install
was verified to store the correct absolute `#()` path only under DOUBLE quotes
(FINDING 3). The INPUT dependencies (`opt_status_format_index`, `ORIG_STATUS`,
`ORIG_STATUS_FORMAT_INDICES`, `get_state`, `CURRENT_DIR`, the COMPLETE renderer)
are all present, and restore (P1.M5.T3.S1) is a matched teardown. Residual risks:
(a) T2 still in flight in parallel — mitigated by Task 1's "re-read fresh; confirm
T2's local names; T3's are distinct by design" instruction; (b) the line-2 visual
composite (Invariant C) cannot be proven on the isolated socket — mitigated by the
Level 4 manual real-env gate with a documented fallback (FINDING 5); (c) the
`@livepicker-status-format-index` being set to a non-zero value colliding with a
default index — low-risk (default 0; defaults are [0,1,2]; genuinely-user-set are
≥3 so shifting never collides with the renderer at [0]). All residual risks are
deterministically caught by the validation loop.
