# PRP — P1.M6.T4.S1: input-handler.sh `cancel`

---

## Goal

**Feature Goal**: **FILL** the `cancel)` seam in `scripts/input-handler.sh` — the
LAST seam left as `return 0` by P1.M6.T1.S1. (`type`/`backspace`/`next-session`/
`prev-session` are COMPLETE via T1.S1+T2.S1; `confirm` is being filled by the
parallel sibling T3.S1 — assume COMPLETE per the parallel-execution contract.)
This implements PRD §6 Cancel + §11's two-step cancel-key semantics + §9 (restore)
+ §14 (pollution) + the work-item CONTRACT §1-§5:

> The cancel key **clears the query, or cancels if the query is empty** —
> implement that two-step semantics: first press of cancel with a non-empty
> filter clears the filter (like backspace-to-empty); only when the filter is
> already empty does it fully cancel.

Two branches, decided by whether `@livepicker-filter` is non-empty:

- **filter NON-empty** → `set_state "$STATE_FILTER" ""`; `set_state "$STATE_INDEX" "0"`;
  `tmux refresh-client -S 2>/dev/null || true`; `return 0` (clear the query; the
  **picker STAYS OPEN** — mode/list/key-table/status untouched).
- **filter already empty** → `"$CURRENT_DIR/restore.sh" cancel` (full teardown:
  unlink preview, restore status/key-table/layout/hook, `switch-client` back to
  `ORIG_SESSION`, clear all `@livepicker-*` state, unbind the livepicker table).

**OUTPUT**: either the query is cleared (picker stays open, zero history) OR the
picker is fully torn down and the client is back on the original session (zero net
history — the engine dedups restore STEP-3's same-session switch).

This is the **simplest** of the six input-handler actions: no `switch-client` in
the branch itself, no creation, no target resolution, no new locals, no new
helper, no new files. The entire edit is a single surgical replacement of the
`cancel)` seam block. It mirrors the incremental-edit model P1.M5 used to grow
`restore.sh` across T1→T4 and P1.M6 used for `type`→`backspace/nav`→`confirm`→
`cancel`: **grow nothing, add nothing, fill the seam, leave every other branch +
the header + the driver byte-identical.**

**Deliverable** (all in `scripts/input-handler.sh`):
1. **REPLACE** the `cancel)` seam's `return 0` with the full two-step branch (the
   `cur_filter` non-empty guard → clear+reset+refresh+`return`; else
   `restore.sh cancel`). See "Implementation Patterns & Key Details".

**Success Definition**:
- `bash -n` + `shellcheck` pass on `scripts/input-handler.sh` (0 findings beyond
  the existing file-level `disable=SC1091,SC2153`). Tabs only; `set -u` only.
- **Two-step semantics (work-item §1/§5, PRD §11):** pressing cancel with a
  NON-empty filter clears the filter (`@livepicker-filter` == `""`,
  `@livepicker-index` == `0`) and the picker STAYS open (`@livepicker-mode` ==
  `on`, `@livepicker-list` still set, `key-table` == `livepicker`, `status`
  unchanged, client unmoved). Pressing cancel AGAIN (filter now empty) fully
  cancels (picker torn down, client on the original session). Verified by
  `research/cancel_mock.sh` clusters 1+2.
- **Zero net history pollution (Invariant A, PRD §14):** both steps record ZERO
  new `client-session-changed` navigations. The clear-filter step issues no
  `switch-client`; the full-cancel step's single switch (restore STEP-3 back to
  `ORIG_SESSION`) is a same-session switch the engine dedups (mock recorder ==
  seed line, 0 new).
- **No off-limits work:** the local line is UNCHANGED (cancel reuses `cur_filter`
  already declared by T1/T2; it does NOT add `pick_type query` — that is T3's
  growth, assumed landed); NO new helper is added; the `type`/`backspace`/
  `next-session`/`prev-session)`/`confirm)` branches + `*) return 0` default +
  the header + the driver are byte-identical; `restore.sh`/`filter.sh`/
  `state.sh`/`options.sh`/`preview.sh`/`livepicker.sh`/`renderer.sh` are UNCHANGED.

## User Persona (if applicable)

**Target User**: None directly (cancel is an internal key-handler invoked by
tmux's `livepicker` key table). Transitively: the end user browsing sessions
(PRD §3: "I press Escape and I'm back where I started — nothing changed, my
session history is exactly as it was"). T4.S1 makes that sentence literally true.

**Use Case**: The picker is active; the user has typed a query and/or navigated.
The user presses `Escape` (the `@livepicker-cancel-keys` default) to either undo
their typing (first press clears the query) or abort the pick entirely (second
press tears down and returns to the original session).

**User Journey** (T4.S1 scope — the cancel key):
1. …activate (P1.M4) saved state, built the list, grew the status bar, switched
   `key-table` to `livepicker`, ran the first preview, set `@livepicker-mode on`.
   The user typed a query (e.g. `be`) — `@livepicker-filter` == `be`,
   `@livepicker-index` == the highlighted match, `preview.sh` linked the
   highlighted session's window live into the **driver** (`@livepicker-linked-id`).
2. The user presses `Escape`.
3. **T4.S1 (this task), first press (filter non-empty):**
   - tmux looks up `Escape` in the `livepicker` table → `run-shell
     "$CURRENT_DIR/input-handler.sh cancel"`.
   - `input_main` → `case "$action" in cancel) ...`.
   - `cur_filter = get_state "$STATE_FILTER" ""` == `be` → non-empty → clear:
     `set_state "$STATE_FILTER" ""`; `set_state "$STATE_INDEX" "0"`;
     `refresh-client -S`; `return 0`.
   - The picker redraws with an empty query (the FULL list, index 0 highlighted).
     The picker is still open; the client never moved; zero history entries.
4. The user presses `Escape` AGAIN (filter now empty):
   - `cur_filter == ""` → fall through to `"$CURRENT_DIR/restore.sh" cancel`.
   - restore tears down (unlink preview, select ORIG_WINDOW, `switch-client -t
     "=$ORIG_SESSION"` — a same-session switch the engine dedups, restore STEP-3,
     restore_findings FINDING A; restore status/key-table/renumber/hook; restore
     layout; `clear_all_state` + `unbind-key -a -T livepicker` + `refresh-client -S`).
5. The client is back on the original session; the status bar is normal; the
   livepicker key table is gone; the picker `@livepicker-*` state is cleared.
   History is unchanged (zero net entries).

**Pain Points Addressed**:
- (a) **Dead Escape key.** Without this branch, Escape is bound to `return 0` —
  pressing it does nothing. T4.S1 makes Escape the clear-then-cancel action.
- (b) **No graceful "undo my typing" path.** Without the two-step semantics, a
  single Escape would tear down the whole picker even if the user only wanted to
  retype their query. T4.S1 implements PRD §11's "clears the query, or cancels if
  the query is empty" UX detail.
- (c) **History pollution.** Any branch that accidentally issued a
  `switch-client` (or failed to clean up) would dirty the timeline. T4.S1 issues
  zero switches itself and delegates the (deduped) cancel switch to restore.

## Why

- **PRD §6 "Cancel"** is the controlling spec (verbatim): "Run `restore.sh cancel`:
  unlink the preview, restore the saved status layout and key table,
  `select-window` back to the original window, and (because cancel is not a
  navigation) `switch-client` back to the original session. Clear all
  `@livepicker-*` state."
- **PRD §11 (work-item §1 RESEARCH NOTE)** adds the two-step semantics: "the
  cancel key clears the query, or cancels if the query is empty" — the
  clear-filter-first press, then the full teardown. This is the work-item's
  explicit "small but important UX detail."
- **PRD §4 "The core rule"** + **PRD §14 "Pollution"** + **Invariant A**
  (system_context §3): cancel must produce ZERO net `client-session-changed`
  navigations. PROVEN (cancel_findings FINDING 4 / restore_keep_cancel FINDING A):
  during browse the client never left `ORIG`; restore STEP-3's
  `switch-client -t "=$ORIG_SESSION"` has `to == ORIG == current`, so the real
  `tmux-session-history` engine's `do_hook` short-circuits on
  `[ "$to" = "$CURRENT" ] && return` → zero net history entries.
- **Work-item §2/§4 (INPUT/OUTPUT)**: INPUT is `@livepicker-filter` + `restore.sh`;
  OUTPUT is either query-cleared (picker open) or full-cancel (client back where
  it started, zero history entries).
- **Scope cohesion.** T4.S1 is the cancel counterpart of: activate T4.S1 (bound
  `run-shell "$CURRENT_DIR/input-handler.sh cancel"`), activate T2.S1 (built
  `@livepicker-list`), the `type`/`backspace` actions (set/clear
  `@livepicker-filter`), and `restore.sh` cancel (P1.M5.T2.S1, owns the teardown +
  the deduped switch). The shared contract is the state keys
  (`STATE_FILTER`/`STATE_INDEX`) + `restore.sh`. T4.S1 reads two of them and writes
  two of them (in the clear path) or delegates everything (in the cancel path).
  **T4 is the LAST subtask of module P1.M6** (the input handler) — completing it
  finishes the T1.S1 skeleton and unblocks P1.M7 validation.

## What

**EDIT** the existing `scripts/input-handler.sh` IN PLACE. No other file is
touched. One edit:

1. **Replace the `cancel)` seam** (the `cancel)\n\t\t\treturn 0\n\t\t\t;;` block —
   leave the preceding `# --- P1.M6.T4.S1 seam ---` comment block, optionally
   refreshing it to describe the two-step logic) with the full two-step branch.
   See "Implementation Patterns & Key Details".

### Success Criteria

- [ ] `scripts/input-handler.sh` passes `bash -n` + `shellcheck` (only the
      existing file-level `disable=SC1091,SC2153`); tabs only; `set -u` only.
- [ ] The cancel branch reads `@livepicker-filter` via `get_state "$STATE_FILTER" ""`;
      if NON-empty it sets `@livepicker-filter` to `""` (via `set_state`), sets
      `@livepicker-index` to `"0"`, calls `tmux refresh-client -S 2>/dev/null || true`,
      and `return 0` WITHOUT calling restore.sh.
- [ ] If `@livepicker-filter` is already empty, the branch calls
      `"$CURRENT_DIR/restore.sh" cancel` (the house variable, NOT `$SCRIPT_DIR` —
      FINDING 6).
- [ ] The cancel branch does NOT reference `$2` (FINDING 5 — cancel takes argv[1]
      only, like confirm/nav/backspace); it does NOT grow the `local` line (reuses
      `cur_filter`); it does NOT add a helper.
- [ ] The cancel branch does NOT call `switch-client`, `new-session`, `select-window`,
      `unlink-window`, or `preview.sh` directly — the clear path only writes
      picker-internal options + refresh; the cancel path delegates ALL tmux
      mutation to `restore.sh`.
- [ ] The `confirm)` seam is whatever T3.S1 produced (assumed COMPLETE); the
      `type`/`backspace`/`next-session`/`prev-session)` branches + `*) return 0`
      + the header + the driver are byte-identical; `git diff --stat` shows only
      `input-handler.sh`.
- [ ] **Mock (work-item §5, `research/cancel_mock.sh`):** both clusters pass —
      (1) cancel with a non-empty filter clears it (filter `""`, index `0`) and
      the picker STAYS open (mode `on`, list set, key-table `livepicker`, status
      `2`, client unmoved, 0 history); (2) cancel AGAIN fully tears down
      (mode/filter/list/index/linked-id all unset, key-table `root`, client on
      original session, 0 net history).

## All Needed Context

### Context Completeness Check

_Pass_: A developer who has never seen this repo can implement T4.S1 from
(a) the ready-to-paste cancel branch in "Implementation Patterns & Key Details";
(b) the 9 findings in `research/cancel_findings.md` — most critically **FINDING 1**
(`set_state "$STATE_FILTER" ""` round-trips to `""` — set-empty, NOT unset, but
reads identically via `get_state`'s default), **FINDING 2** (the clear-filter step
KEEPS the picker alive — proven: mode/list/key-table/status untouched), **FINDING 3**
(the clear-filter step is a superset of `backspace` — mirror it exactly; NO
preview.sh call), **FINDING 4** (the full-cancel path delegates to restore.sh
cancel; the deduped same-session switch → 0 history), **FINDING 5** (cancel takes
argv[1] only), **FINDING 6** (`$CURRENT_DIR` is the house variable; the
work-item's `$SCRIPT_DIR` is descriptive), and **FINDING 7** (cancel needs NO new
locals / NO new helper); and (c) the throwaway socket-shim mock
`research/cancel_mock.sh` that seeds an isolated socket + attached client, drives
the REAL activate/preview/input-handler/restore, and asserts the 2 work-item
clusters + the 0-history invariant. The INPUT dependencies (`input-handler.sh`
skeleton with the cancel seam, `restore.sh`, `state.sh`, `options.sh`) are ALL
COMPLETE/present.

### Documentation & References

```yaml
# MUST READ — the file THIS task fills (the seam). COMPLETE skeleton (T1.S1) +
#   backspace/nav (T2.S1); confirm (T3.S1) is filled in parallel (assume landed).
- file: scripts/input-handler.sh
  why: T1.S1 CREATED this file (type branch + the 5 seams); T2.S1 added
        backspace/nav + sourced filter.sh; T3.S1 (parallel) fills confirm.
        T4.S1 EDITS IT IN PLACE: fills ONLY the cancel) seam. Copy the skeleton's
        header/source-block/driver/CURRENT_DIR idiom verbatim; only the cancel
        branch changes.
  pattern: incremental-edit (mirror how restore.sh grew across P1.M5.T1→T4 and
           input-handler.sh grew type→backspace/nav→confirm→cancel); the local
           line is UNCHANGED (cur_filter reused); set -u inherited; tabs; driver
           input_main "$@" || exit 1 / exit 0.
  gotcha: cancel reads ONLY $1 (FINDING 5). Under set -u it MUST NOT reference $2
          (the cancel binding passes no char). Use $CURRENT_DIR (NOT $SCRIPT_DIR —
          FINDING 6: $SCRIPT_DIR is undefined in this file -> set -u crash).

# MUST READ — the teardown the cancel path delegates to (filter empty). COMPLETE
#   (P1.M5). IMMUTABLE.
- file: scripts/restore.sh
  why: cancel calls "$CURRENT_DIR/restore.sh" cancel when the filter is empty.
        STEP-1 unlinks current_session:$linked_id — at cancel time current_session
        == driver (cancel never switched), so it cleans the RIGHT link (confirm
        FINDING 3: "any branch that does NOT switch leaves cleanup to restore").
        STEP-3 cancel does switch-client -t "=$ORIG_SESSION" — a SAME-SESSION
        switch (client never left ORIG during browse, Invariant A) the engine
        dedups -> 0 net history (cancel_findings FINDING 4 / restore_findings A).
        STEP-6 clear_all_state + unbind-key -a -T livepicker + refresh-client -S.
  critical: restore.sh is IMMUTABLE (P1.M5 COMPLETE). T4.S1 MUST NOT edit it. The
        cancel branch simply CALLS it; it does not re-implement any teardown step.

# MUST READ — the backspace branch (the EXACT precedent for the clear-filter step).
- file: scripts/input-handler.sh   # the backspace) branch (COMPLETE, T2.S1)
  why: the clear-filter step is a SUPERSET of backspace (cancel_findings FINDING
        3). backspace does: read cur_filter; if non-empty, write the trimmed
        value; ALWAYS set index=0; ALWAYS refresh-client -S || true. cancel's
        clear path is identical EXCEPT it writes "" (the WHOLE query) instead of
        ${cur_filter%?} (one char). Copy backspace's guard + set_state INDEX 0 +
        refresh idiom verbatim.
  pattern: cur_filter="$(get_state "$STATE_FILTER" "")"; [ -n "$cur_filter" ] && ...;
           set_state "$STATE_INDEX" "0"; tmux refresh-client -S 2>/dev/null || true.
  gotcha: backspace does NOT call preview.sh (T2 FINDING 4); cancel's clear path
          MUST NOT either (the contract lists ONLY filter+index+refresh; the live
          preview re-syncs on the next nav/confirm — the same documented minor UX
          gap as backspace).

# MUST READ — the state accessors cancel reads/writes. COMPLETE (P1.M1.T3.S1).
- file: scripts/state.sh
  why: get_state "$STATE_FILTER" "" (read); set_state "$STATE_FILTER" "" (write,
        clear); set_state "$STATE_INDEX" "0" (write). readonly STATE_FILTER /
        STATE_INDEX constants; get_state defaults make the read set -u safe.
  critical: set_state "" is a SET-EMPTY (tmux set-option -g @x ""), NOT an unset
        (-gu). get_state reads it back as "" (the [ -n "$v" ] test is false -> it
        returns the default "", which IS ""). Do NOT use tmux_unset_opt / -gu
        here (that is restore's teardown concern — FINDING 1). The cancel clear
        path writes ONLY @livepicker-filter + @livepicker-index (picker-internal);
        it writes NONE of mode/list/linked-id (restore clears those).

# MUST READ — the caller contract (the Escape binding). COMPLETE (P1.M4.T4.S1).
- file: scripts/livepicker.sh
  why: activate T4.S1 bound cancel VERBATIM (cancel_findings FINDING 5):
        for lp_c in $(opt_cancel_keys); do
            tmux bind-key -T livepicker "$lp_c" run-shell "$CURRENT_DIR/input-handler.sh cancel"
        done
        (opt_cancel_keys default "Escape", PRD §11). argv is JUST `cancel`.
  section: the cancel-key bind block (~line 230-232).

# MUST READ — the empirical ground-truth for THIS task (9 findings).
- docfile: plan/001_fd5d622d3939/P1M6T4S1/research/cancel_findings.md
  why: FINDING 1 (set_state "" round-trips to "" — verified live); FINDING 2 (the
        clear-filter step KEEPS the picker alive — verified: mode/list/key-table/
        status untouched); FINDING 3 (clear-filter is a superset of backspace —
        mirror it; NO preview); FINDING 4 (the full-cancel path -> restore.sh
        cancel; deduped same-session switch -> 0 history — verified); FINDING 5
        (argv[1] only); FINDING 6 ($CURRENT_DIR not $SCRIPT_DIR); FINDING 7 (no
        new locals / no helper); FINDING 8 (cancel is the LAST seam); FINDING 9
        (the 2-cluster mock).
  critical: Read BEFORE writing. FINDING 1 (set-empty != unset but reads same) and
        FINDING 6 ($CURRENT_DIR not $SCRIPT_DIR) are the two non-obvious traps.

# MUST READ — the throwaway socket-shim validator (the 2 clusters).
- docfile: plan/001_fd5d622d3939/P1M6T4S1/research/cancel_mock.sh
  why: a self-cleaning isolated-socket harness that drives the REAL
        activate/preview/input-handler/restore with an attached client + a
        smart-dedup client-session-changed recorder (FINDING 4) and asserts the 2
        work-item clusters (cancel clears filter + picker stays open; cancel again
        tears down + 0 history).
  critical: requires `script` (util-linux) for the attached-client pty. Run it to
        prove the implementation; do NOT ship it (P1.M7 owns the real harness).

# MUST READ — the PRD sections selected for this work item.
- docfile: PRD.md
  why: §6 Cancel (the spec, verbatim); §11 Configuration (cancel-keys default
        Escape + "clear query, else cancel" two-step semantics); §9 State saved
        and restored (the cancel teardown restore implements); §14 Pollution
        (cancel -> zero entries).
  section: "§6 Behaviors / Cancel", "§11 Configuration options",
           "§9 State saved and restored", "§14 Pollution and compatibility analysis".

# MUST READ — system ground-truth (Invariant A + shell style + history composition).
- docfile: plan/001_fd5d622d3939/architecture/system_context.md
  why: §3 INVARIANT A (browsing never fires client-session-changed; the only
        switch in the flow is confirm's — cancel issues none); §6 (the engine
        dedups a same-session switch -> 0 entries); §9 shell style (set -u ONLY;
        NO -e/pipefail; tabs; local for all function locals; quote everything).
  section: "§3 INVARIANT A", "§6 tmux-session-history composition", "§9 Shell style".

# MUST READ (cross-reference) — the confirm findings (the FINDING 3 rule + argv contract).
- docfile: plan/001_fd5d622d3939/P1M6T3S1/research/confirm_findings.md
  why: FINDING 3 ("any branch that issues switch-client must unlink the driver
        first; any branch that does NOT switch leaves cleanup to restore") — cancel
        does NOT switch, so it leaves ALL preview cleanup to restore STEP-1
        (correct: current_session==driver at cancel time). FINDING 9 (argv[1]-only
        contract — cancel mirrors confirm).
```

### Current Codebase tree

```bash
tmux-livepicker/
  PRD.md
  plugin.tmux                 # COMPLETE. Unchanged.
  plan/001_fd5d622d3939/{architecture/*.md, tasks.json, prd_snapshot.md, prd_index.txt}
  plan/001_fd5d622d3939/P1M6T1S1/{PRP.md, research/input_handler_type_findings.md}   # CREATED input-handler.sh
  plan/001_fd5d622d3939/P1M6T2S1/{PRP.md, research/backspace_nav_findings.md}        # added backspace/nav + filter.sh
  plan/001_fd5d622d3939/P1M6T3S1/{PRP.md, research/confirm_findings.md,
                                  research/confirm_mock.sh}                          # confirm (parallel, assume landed)
  plan/001_fd5d622d3939/P1M6T4S1/{PRP.md, research/cancel_findings.md,
                                  research/cancel_mock.sh}                           # THIS
  scripts/
    options.sh   # COMPLETE. Unchanged. (opt_cancel_keys -> default "Escape".)
    utils.sh     # COMPLETE. Unchanged. (tmux_* helpers; bare tmux for refresh-client.)
    state.sh     # COMPLETE. Unchanged. (STATE_FILTER/STATE_INDEX + get_state/set_state.)
    filter.sh    # COMPLETE (P1.M6.T2.S1). Unchanged.
    renderer.sh  # COMPLETE (P1.M2). Unchanged.
    preview.sh   # COMPLETE (P1.M3). Unchanged.
    livepicker.sh   # COMPLETE (P1.M4). Unchanged. (T4.S1 bound cancel; T2.S1 built the list.)
    restore.sh   # COMPLETE (P1.M5). UNCHANGED / IMMUTABLE. (cancel teardown.)
    input-handler.sh  # COMPLETE skeleton (T1.S1) + backspace/nav (T2.S1) + confirm (T3.S1).
                      # EDIT (this task): fill the cancel) seam (the LAST seam). The local line,
                      #   the helper (if T3 added one), the type/backspace/next/prev/confirm
                      #   branches + *) + the driver stay byte-identical.
  .gitignore
  # NOTE: NO test harness yet (P1.M7). Validate via research/cancel_mock.sh (throwaway).
```

### Desired Codebase tree with files to be added and responsibility of file

```bash
tmux-livepicker/
  scripts/
    options.sh        # unchanged.
    utils.sh          # unchanged.
    state.sh          # unchanged.
    filter.sh         # unchanged.
    renderer.sh       # unchanged.
    preview.sh        # unchanged.
    livepicker.sh     # unchanged.
    restore.sh        # unchanged (IMMUTABLE).
    input-handler.sh  # EDITED: ONLY the cancel) seam is filled (two-step: non-empty
                      #   filter -> clear+reset+refresh+return; empty -> restore.sh cancel).
                      #   The local line, any helper, and every other branch + the driver
                      #   are unchanged. This is the LAST seam — T1.S1 skeleton complete.
```

### Known Gotchas of our codebase & Library Quirks

```bash
# CRITICAL (research FINDING 1 — set-empty != unset, but reads identically):
#   set_state "$STATE_FILTER" "" -> tmux set-option -g @livepicker-filter "" (SET-EMPTY,
#   not unset). get_state reads it back as "" because tmux_get_opt does
#   [ -n "$v" ] && echo "$v" || echo "${2:-}" and the empty-set value has length 0 ->
#   the test is false -> it returns the default "" (which IS "" for STATE_FILTER). So
#   set_state "" round-trips to "". Do NOT use tmux_unset_opt / -gu here (that is
#   restore's teardown concern — it would unset the option entirely, which is
#   semantically "picker cleared its filter" but contractually the clear path should
#   set-empty to mirror backspace). Verified live (cancel_findings TEST 1).

# CRITICAL (research FINDING 6 — $CURRENT_DIR, NOT $SCRIPT_DIR): the work-item
#   CONTRACT §3 writes "$SCRIPT_DIR/scripts/restore.sh cancel". $SCRIPT_DIR is
#   NOT a variable in input-handler.sh (it would crash under set -u). The house
#   variable is CURRENT_DIR (resolved at the top to .../scripts). Every sibling
#   call uses "$CURRENT_DIR/<sibling>.sh" (T2 preview.sh, T3 restore.sh keep).
#   USE "$CURRENT_DIR/restore.sh" cancel. The work-item's $SCRIPT_DIR is just
#   descriptive (telling you WHICH script).

# CRITICAL (research FINDING 5 — argv[1] only): cancel is bound VERBATIM as
#   `run-shell "$CURRENT_DIR/input-handler.sh cancel"` — argv is JUST `cancel`,
#   NO char (unlike type). So the cancel branch reads ONLY $1. Under set -u it
#   MUST NOT reference $2 (unset -> crash). Mirror confirm/nav/backspace (T2
#   FINDING 1 / T3 FINDING 9).

# CRITICAL (research FINDING 4 — pollution safety is BY CONSTRUCTION): cancel
#   issues ZERO switch-client ITSELF. The only switch in the cancel path is
#   restore STEP-3 (switch-client -t "=$ORIG_SESSION"), and it is a SAME-SESSION
#   switch (the client never left ORIG during browse, Invariant A) the engine
#   dedups ([ "$to" = "$CURRENT" ] && return in do_hook) -> 0 net history entries.
#   Verified live (cancel_findings TEST 2). Unlike confirm (FINDING 1/2 — the
#   catastrophic switch-before-unlink target-destruction bug), cancel has NO such
#   hazard because it NEVER switches the client to a TARGET. The driver-preview
#   cleanup is handled entirely by restore STEP-1 (current_session==driver at
#   cancel time -> restore unlinks driver:$linked_id correctly — confirm FINDING
#   3's rule: any branch that does NOT switch leaves cleanup to restore).

# CRITICAL (research FINDING 2 — the clear-filter step KEEPS the picker alive):
#   the clear path writes ONLY @livepicker-filter + @livepicker-index (picker-
#   internal options) + a refresh-client -S. It does NOT touch @livepicker-mode,
#   @livepicker-list, key-table, status, status-format, or the hook. Verified
#   live: after the clear, mode=on, list=set, key-table=livepicker, status=2,
#   client=driver (picker provably still open). Do NOT add a set_state on mode/
#   list/linked-id in the clear path.

# CRITICAL (research FINDING 3 — mirror backspace; NO preview): the clear-filter
#   step is a SUPERSET of backspace. Copy backspace's read+guard+set INDEX 0+
#   refresh idiom; write "" instead of ${cur_filter%?}. Do NOT call preview.sh
#   (the contract lists ONLY filter+index+refresh; the live preview re-syncs on
#   the next nav/confirm — the same documented minor UX gap as backspace, T2
#   FINDING 4). Adding a preview call would diverge from the contract + risk
#   scope creep.

# GOTCHA: the cancel branch does NOT grow the local line. It uses cur_filter,
#   which is ALREADY declared by T1.S1/T2.S1 (local action char new_filter
#   cur_filter cur_list cur_index L new_idx target) and grown by T3.S1
#   (+pick_type query, assumed landed). cancel needs NEITHER pick_type NOR query.
#   Do NOT add a local; do NOT add a file-scope helper (contrast confirm's
#   _confirm_land_on_session). The edit is a single surgical seam replacement.

# GOTCHA: the clear-path `return 0` is LOAD-BEARING — it is what keeps the picker
#   open. If you omit it, execution falls through to `restore.sh cancel` after
#   clearing the filter (the picker would tear down on the FIRST press — the
#   exact UX bug the two-step semantics exists to prevent). The branch structure
#   is: if non-empty { clear; reset; refresh; return 0; } ; restore.sh cancel.

# STYLE (system_context §9): indent with TABS (the case branches are TWO tabs
#   deep: one for the case body, one for the branch body). Verify with
#   `grep -Pn '^    ' scripts/input-handler.sh` (expect empty). shfmt NOT installed.

# CRITICAL: NO set -e, NO set -o pipefail (house style; system_context §9).
#   refresh-client legitimately returns non-zero detached; under set -e that would
#   abort mid-cancel and strand the picker. set -u is inherited from the sourced
#   libs — do NOT re-declare it. Guard refresh-client with 2>/dev/null || true
#   (mirror backspace / type / restore.sh STEP 6c).
```

## Implementation Blueprint

### Data models and structure

No new data model. T4.S1 adds NO new state keys, NO new options, and NO new
helper. It reads one existing `@livepicker-*` key (`@livepicker-filter`), writes
two (`@livepicker-filter`, `@livepicker-index`) in the clear path, and delegates
ALL teardown (in the cancel path) to `restore.sh`.

- **READ:** `@livepicker-filter` (via `get_state "$STATE_FILTER" ""`).
- **WRITE (clear path only):** `@livepicker-filter` → `""`, `@livepicker-index` → `"0"`
  (via `set_state`).
- **DELEGATE (cancel path only):** `restore.sh cancel`.
- **WRITE (NONE to mode/list/linked-id/orig-*):** the clear path writes only the
  two filter/index keys; restore's `clear_all_state` (STEP-6) clears everything.

The function locals: **NO change.** `cur_filter` is reused (already on
`input_main`'s `local` line from T1.S1/T2.S1).

### Implementation Tasks (ordered by dependencies)

```yaml
Task 1: EDIT scripts/input-handler.sh — fill the cancel) seam
  - EDIT: replace
            cancel)
                return 0
                ;;
        WITH the full two-step branch (see "Implementation Patterns & Key
        Details"). Leave the preceding `# --- P1.M6.T4.S1 seam: cancel ---`
        comment block in place (it describes the contract; optionally refresh it
        to describe the two-step logic).
  - LOGIC (PRD §6 Cancel + §11 + work-item §1/§3):
        cur_filter = get_state "$STATE_FILTER" "";
        if cur_filter non-empty:
            set_state "$STATE_FILTER" "";   # clear the query (set-empty, FINDING 1)
            set_state "$STATE_INDEX" "0";   # highlight snaps to top match (PRD §6)
            tmux refresh-client -S 2>/dev/null || true;   # redraw (mirror backspace)
            return 0;                        # KEEP THE PICKER OPEN (load-bearing)
        "$CURRENT_DIR/restore.sh" cancel;    # filter empty -> full teardown
        return 0;
  - DO NOT: reference $2 (FINDING 5); grow the local line (FINDING 7); add a
        helper; call preview.sh/switch-client/new-session/select-window/unlink-
        window directly (FINDING 3/4); use $SCRIPT_DIR (FINDING 6 — use
        $CURRENT_DIR); edit restore.sh/filter.sh/state.sh/options.sh/preview.sh/
        renderer.sh/livepicker.sh; touch the type/backspace/next-session/
        prev-session/confirm branches or the *) default; add set -e.

Task 2: VALIDATE (Level 1 syntax/lint + Level 2 socket-shim mock)
  - RUN: bash plan/001_fd5d622d3939/P1M6T4S1/research/cancel_mock.sh
        (self-cleaning; requires `script` for the attached-client pty). Asserts
        the 2 work-item clusters + the 0-history pollution invariant.
```

### Implementation Patterns & Key Details

#### Task 1 — the `cancel)` branch (indent is TWO tabs; replaces the `return 0` seam)

This REPLACES the `cancel)\n\t\t\treturn 0\n\t\t\t;;` seam (leave the preceding
`# --- P1.M6.T4.S1 seam ---` comment block). The `type`/`backspace`/`next-session`/
`prev-session)` branches, the `confirm)` branch (T3.S1), and the `*) return 0`
default stay UNCHANGED.

```bash
		cancel)
			# --- P1.M6.T4.S1: two-step cancel (PRD §6 Cancel + §11 + work-item §1).
			#     "clears the query, or cancels if the query is empty."
			# Research FINDING 5: cancel takes argv[1] ONLY — it MUST NOT reference $2
			# (the cancel binding passes no char; mirror confirm/nav/backspace).
			cur_filter="$(get_state "$STATE_FILTER" "")"
			if [ -n "$cur_filter" ]; then
				# First press with a NON-empty filter: CLEAR the query (like
				# backspace-to-empty) and KEEP THE PICKER OPEN. This is the
				# load-bearing UX detail (work-item §1). Mirror backspace (T2.S1)
				# exactly: set filter, set index=0, refresh — but write "" (the
				# WHOLE query) instead of ${cur_filter%?} (one char).
				# FINDING 1: set_state "" is a SET-EMPTY (tmux set-option -g @x ""),
				# NOT an unset; get_state reads it back as "" (the default). Do NOT
				# use tmux_unset_opt / -gu (that is restore's teardown concern).
				set_state "$STATE_FILTER" ""
				# Reset the highlight to the top filtered match (PRD §6). Always
				# safe — the renderer clamps + handles FLEN=0 (empty filter matches
				# ALL names; renderer FINDING 4 / filter.sh).
				set_state "$STATE_INDEX" "0"
				# Force the #() renderer to re-run so the picker redraws with the
				# empty query + the full list (PRD §10/§16). Guard the detached edge
				# (mirror backspace / type / restore.sh STEP 6c).
				tmux refresh-client -S 2>/dev/null || true
				# LOAD-BEARING return: this is what keeps the picker OPEN. Omitting
				# it would fall through to restore.sh cancel (the picker would tear
				# down on the FIRST press — the exact bug the two-step semantics
				# prevents). The clear path writes ONLY @livepicker-filter +
				# @livepicker-index (picker-internal); mode/list/key-table/status
				# are untouched (FINDING 2). No switch-client -> 0 history.
				return 0
			fi
			# Filter ALREADY empty: full cancel (PRD §6 Cancel + §9). Delegate ALL
			# teardown to restore.sh cancel (P1.M5, IMMUTABLE): it unlinks the
			# preview (STEP-1, on current_session==driver — correct: cancel never
			# switched, confirm FINDING 3's "no-switch -> leave cleanup to restore"),
			# selects ORIG_WINDOW (STEP-2), switch-client -t "=$ORIG_SESSION"
			# (STEP-3 — a SAME-SESSION switch the engine dedups -> 0 net history,
			# FINDING 4 / restore_findings A), restores status/key-table/renumber/
			# hook (STEP-4) + layout (STEP-5), clear_all_state + unbind-key -a -T
			# livepicker + refresh-client -S (STEP-6).
			# FINDING 6: use $CURRENT_DIR (the house variable; == scripts/). Do NOT
			# use $SCRIPT_DIR (undefined here -> set -u crash).
			"$CURRENT_DIR/restore.sh" cancel
			return 0
			;;
```

NOTE for the implementer:
- This is an EDIT-IN-PLACE (T1.S1 created the file; T2.S1 grew it; T3.S1 fills
  confirm in parallel). Do NOT recreate it. Apply the single edit precisely;
  leave the rest byte-identical.
- The cancel branch reads ONLY `$1` (research FINDING 5) — never `$2`.
- `cur_filter` is ALREADY on `input_main`'s `local` line (T1.S1/T2.S1); do NOT
  add it or any other local. Do NOT add a helper.
- The `return 0` after the clear is LOAD-BEARING (it keeps the picker open). The
  `return 0` after `restore.sh cancel` is stylistic (matches every other branch's
  explicit return; restore.sh is the last statement either way).
- `set_state "$STATE_FILTER" ""` is a SET-EMPTY, not an unset (FINDING 1). Do NOT
  switch to `tmux_unset_opt` / `-gu`.
- Use `"$CURRENT_DIR/restore.sh" cancel`, NOT `"$SCRIPT_DIR/scripts/restore.sh"`
  (FINDING 6).
- Every tmux call in the branch is `refresh-client -S 2>/dev/null || true`
  (the only direct tmux call); restore.sh owns all the rest. There is no
  `switch-client`/`new-session`/`select-window`/`unlink-window`/`preview.sh` in
  the cancel branch.

### Integration Points

```yaml
EDITED FILE (the ONLY file this task modifies):
  - scripts/input-handler.sh: the cancel) seam is filled (two-step: non-empty
        filter -> clear+reset+refresh+return; empty -> restore.sh cancel). The
        local line, any helper, and every other branch + the driver are unchanged.

CALLERS (the binding that invokes cancel — COMPLETE sibling):
  - activate T4.S1 (P1.M4.T4.S1): bound `run-shell "$CURRENT_DIR/input-handler.sh
        cancel"` for each key in opt_cancel_keys (default Escape). argv = JUST `cancel`.

CONSUMERS (what the cancel branch calls):
  - scripts/restore.sh cancel — full teardown + deduped switch-client back to ORIG_SESSION.
        (ONLY in the filter-empty path. The clear path consumes nothing — it writes
        two picker-internal options + refreshes.)

STATE READS (this task):
  - @livepicker-filter  (via get_state "$STATE_FILTER" "")

STATE WRITES (this task, clear path ONLY):
  - @livepicker-filter  -> ""  (via set_state; set-empty, FINDING 1)
  - @livepicker-index   -> "0" (via set_state)

STATE WRITES (NONE in the cancel path): restore clear_all_state (STEP-6) clears them.

CONFIG READS (this task): NONE (cancel does not branch on opt_type/opt_create — it
        is mode-agnostic; the same two-step logic applies in session AND window mode).

TMUX MUTATIONS (this task):
  - refresh-client -S  (clear path; redraw; || true)
  - (cancel path delegates ALL mutation to restore.sh — switch-client, select-window,
    unlink-window, set-option on status/key-table/etc., unbind-key, refresh-client.)

DATABASE / MIGRATIONS / ROUTES: none.
```

## Validation Loop

### Level 1: Syntax & Style (Immediate Feedback)

```bash
# Run after the edit — fix before proceeding.
bash -n scripts/input-handler.sh
shellcheck scripts/input-handler.sh
#   expect 0 findings beyond the file-level disable=SC1091,SC2153.

# Tabs-not-spaces sanity (shfmt NOT installed):
grep -Pn '^    ' scripts/input-handler.sh && echo "FAIL: 4-space indent, use tabs" || echo "OK: tabs only"

# Confirm house style (set -u only; NO -e / NO pipefail DECLARED in this file):
grep -n 'set -e\|set -o pipefail' scripts/input-handler.sh \
  && echo "FAIL: set -e/pipefail present" || echo "OK: set -u inherited only"

# The local line is UNCHANGED by T4 (cur_filter reused; pick_type query are T3's):
#   (Run AFTER T3 has landed; if T3 has not landed yet, the line is the T1/T2 form
#   WITHOUT pick_type query — either way T4 adds NOTHING.)
grep -c '^	local action char' scripts/input-handler.sh   # expect 1 (the local line, unchanged)

# cancel reads ONLY $1 (FINDING 5) — the cancel branch only:
awk '/^\t\tcancel\)/,/^\t\t;;/' scripts/input-handler.sh | grep -n '\$2' \
  && echo "FAIL: cancel must not reference \$2" || echo "OK: cancel reads \$1 only"

# cancel does NOT grow the local line / add a helper (FINDING 7):
grep -c '_cancel_' scripts/input-handler.sh   # expect 0 (no helper added by T4)

# The two-step structure: set_state FILTER "" + set_state INDEX 0 + refresh + return
#   BEFORE restore.sh cancel (the load-bearing clear-then-return ordering):
awk '/^\t\tcancel\)/,/^\t\t;;/' scripts/input-handler.sh \
  | grep -nE 'set_state .*\$STATE_FILTER.*""|set_state .*\$STATE_INDEX.*"0"|refresh-client -S|return 0|restore\.sh" cancel' \
  # expect: FILTER "" , INDEX 0 , refresh , return 0  BEFORE  restore.sh cancel

# FINDING 6: uses $CURRENT_DIR (house variable), NOT $SCRIPT_DIR:
grep -n 'restore.sh" cancel' scripts/input-handler.sh | grep -q '\$CURRENT_DIR' \
  && echo "OK: uses \$CURRENT_DIR" || echo "FAIL: not \$CURRENT_DIR"
grep -n '\$SCRIPT_DIR' scripts/input-handler.sh \
  && echo "FAIL: \$SCRIPT_DIR is undefined here (set -u crash)" || echo "OK: no \$SCRIPT_DIR"

# The cancel seam is FILLED (the bare `return 0` seam is replaced by the two-step
# branch). Verify the branch contains BOTH the clear-filter guard AND the restore
# delegation (the bare seam had neither):
awk '/^\t\tcancel\)/,/^\t\t;;/' scripts/input-handler.sh > /tmp/cancel_branch.txt
if grep -q '\[ -n "\$cur_filter" \]' /tmp/cancel_branch.txt \
   && grep -q 'set_state "\$STATE_FILTER" ""' /tmp/cancel_branch.txt \
   && grep -q 'restore.sh" cancel' /tmp/cancel_branch.txt; then
  echo "OK: cancel seam filled (clear guard + restore cancel both present)"
else
  echo "FAIL: cancel seam not fully filled"
fi
rm -f /tmp/cancel_branch.txt

# cancel does NOT call switch-client/new-session/select-window/unlink-window/preview.sh:
awk '/^\t\tcancel\)/,/^\t\t;;/' scripts/input-handler.sh \
  | grep -nE 'switch-client|new-session|select-window|unlink-window|preview\.sh' \
  && echo "FAIL: cancel must not mutate tmux directly (delegate to restore)" \
  || echo "OK: cancel only writes picker options + refresh (clear path)"

# SCOPE: only input-handler.sh changed:
git diff --stat | grep -q 'restore.sh\|filter.sh\|state.sh\|options.sh\|preview.sh\|renderer.sh\|livepicker.sh' \
  && echo "FAIL: edited an off-limits file" || echo "OK: only input-handler.sh changed"
# Run from the repo root.
```

### Level 2: Socket-Shim Mock Validation — the 2 work-item clusters + the 0-history invariant

`research/cancel_mock.sh` is a self-cleaning, isolated-socket harness that drives
the REAL `livepicker.sh` (activate), `preview.sh` (to build a preview link),
`input-handler.sh` (cancel), and `restore.sh` (cancel) with ONE attached client
(via `script -qec` — `switch-client`/`display-message`/`refresh-client` all require
a client) and a smart-dedup `client-session-changed` recorder (FINDING 4 /
restore_keep_cancel FINDING B). It asserts the work-item §5 scenario:

- **(1) cancel with a non-empty filter** — `@livepicker-filter` cleared to `""`;
  `@livepicker-index` == `"0"`; **picker STAYS OPEN** (`@livepicker-mode` == `on`,
  `@livepicker-list` still set, `key-table` == `livepicker`, `status` == `2`,
  `@livepicker-linked-id` unchanged — restore owns cleanup); client never moved;
  **0** history entries (no switch happened).
- **(2) cancel AGAIN (filter now empty)** — picker fully torn down
  (`@livepicker-mode`/`@livepicker-filter`/`@livepicker-list`/`@livepicker-index`/
  `@livepicker-linked-id` all unset; `key-table` == `root`); client back on the
  original session (driver); **0 net history entries** (restore STEP-3's same-
  session switch deduped); the livepicker table has no cancel binding
  (`unbind-key -a -T livepicker`).

```bash
# Run from anywhere (self-cleaning; requires `script` from util-linux for the pty):
bash plan/001_fd5d622d3939/P1M6T4S1/research/cancel_mock.sh
# Expected: "ALL CLUSTERS PASSED". If cluster (1) fails on "picker STAYS OPEN"
# (@livepicker-mode cleared), the clear path is falling through to restore.sh
# (missing the `return 0`) — re-read the load-bearing-return gotcha. If cluster
# (2) fails on "0 history entries", check the recorder is the deduping kind
# (FINDING 4) — a naive counter would false-fail the same-session switch.
```

### Level 3: Integration Testing (Manual / Live tmux)

```bash
# The mock (Level 2) IS the integration test (it drives the real activate→cancel→
# restore chain end-to-end on an isolated socket). For an in-session smoke test on
# the LIVE socket (optional, manual):
#   1. tmux set -g @livepicker-key L
#   2. tmux source ./plugin.tmux
#   3. Create 2-3 sessions (tmux new -d -s alpha ; tmux new -d -s beta).
#   4. prefix L -> type "be" -> Escape.
#   5. Expect: the query clears; the picker is STILL open showing the full list;
#      `tmux show-options -gqv @livepicker-mode` is "on".
#   6. Escape again.
#   7. Expect: the picker is gone (status bar normal, @livepicker-mode empty,
#      key-table back to root); the client is on the original session.
#   8. Pollution check: `tmux show-options -gv @session-history-hist` is byte-
#      identical to before step 4 (cancel -> 0 entries, PRD §14).
```

### Level 4: Creative & Domain-Specific Validation (PRD §14 pollution + §11 semantics)

```bash
# PRD §14 pollution (the core invariant) — re-affirmed by the mock's recorder:
#   cancel (either step) records ZERO client-session-changed navigations. The
#   clear step issues no switch; the cancel step's single switch (restore STEP-3)
#   is a deduped same-session switch (the engine's [ "$to" = "$CURRENT" ] short-
#   circuit). The mock's smart-dedup recorder models this.

# PRD §11 two-step semantics matrix (the mock covers both rows):
#   cancel + NON-empty filter -> query cleared, picker open   (cluster 1)
#   cancel + EMPTY filter     -> full teardown, client back   (cluster 2)

# Edge cases worth a manual probe (beyond the mock):
#   - cancel immediately after activate (filter is "" by default) -> the FIRST
#     press tears down (no clear step). Confirm: picker gone, client on ORIG.
#   - cancel after typing a single char -> first press clears to "", picker open;
#     second press tears down.
#   - cancel in WINDOW mode -> same two-step logic (cancel is mode-agnostic; it
#     does not read opt_type). Confirm: clears the query first, then tears down.
```

## Final Validation Checklist

### Technical Validation

- [ ] Level 1 passes: `bash -n scripts/input-handler.sh` + `shellcheck` (0 new findings).
- [ ] Level 2 passes: `bash research/cancel_mock.sh` → ALL CLUSTERS PASSED.
- [ ] Tabs only; `set -u` only (NO `-e`, NO `-o pipefail`).
- [ ] `git diff --stat` shows ONLY `scripts/input-handler.sh` changed.

### Feature Validation

- [ ] **Two-step semantics:** cancel with a non-empty filter clears it (filter `""`,
      index `0`) and the picker STAYS open (mock cluster 1); cancel again fully
      tears down (mock cluster 2).
- [ ] **Picker stays open:** after the first cancel, `@livepicker-mode` == `on`,
      `@livepicker-list` set, `key-table` == `livepicker`, `status` grown, client
      unmoved (mock cluster 1).
- [ ] **Full teardown:** after the second cancel, all `@livepicker-*` runtime keys
      unset, `key-table` == `root`, client on the original session (mock cluster 2).
- [ ] **Zero net history:** both steps record 0 new `client-session-changed`
      navigations (mock recorder == seed line; PRD §14).

### Code Quality Validation

- [ ] The cancel branch mirrors `backspace`'s read+guard+set INDEX 0+refresh idiom
      (writes `""` instead of `${cur_filter%?}`).
- [ ] cancel reads ONLY `$1` (FINDING 5); uses `$CURRENT_DIR` (FINDING 6); does
      NOT grow the local line (FINDING 7); does NOT add a helper.
- [ ] cancel does NOT call `switch-client`/`new-session`/`select-window`/
      `unlink-window`/`preview.sh` directly (only `refresh-client -S` in the clear
      path; the cancel path delegates ALL mutation to `restore.sh`).
- [ ] File placement matches the desired codebase tree (no new files).
- [ ] Anti-patterns avoided (check against Anti-Patterns section).
- [ ] Dependencies properly managed (no new sources — `state.sh` already sourced).

### Documentation & Deployment

- [ ] Code is self-documenting with clear variable/function names + inline comments
      citing the findings (FINDING 1/2/3/4/5/6).
- [ ] The `# --- P1.M6.T4.S1 seam ---` comment block is refreshed to describe the
      two-step logic (or left as-is if it already does).
- [ ] No new environment variables (cancel reads none).

---

## Anti-Patterns to Avoid

- ❌ **Don't omit the `return 0` after the clear.** It is load-bearing — it keeps
  the picker open. Without it, the first cancel press tears the whole picker down
  (the exact UX bug the two-step semantics exists to prevent).
- ❌ **Don't call `preview.sh`/`switch-client`/etc. directly in the cancel branch.**
  The clear path writes only picker-internal options + refresh; the cancel path
  delegates ALL tmux mutation to `restore.sh`. cancel issues ZERO `switch-client`
  itself (the only switch in the cancel flow is restore STEP-3, deduped).
- ❌ **Don't use `tmux_unset_opt` / `-gu` to clear the filter.** `set_state ""` is
  a set-empty that reads back as `""` (FINDING 1) — that is the correct "clear the
  query" semantic and it mirrors `backspace`. Unsetting is restore's teardown job.
- ❌ **Don't use `$SCRIPT_DIR`.** It is undefined in `input-handler.sh` (→ `set -u`
  crash). Use `$CURRENT_DIR` (the house variable; already resolved at the top).
- ❌ **Don't reference `$2`.** cancel takes argv[1] only (FINDING 5); `$2` is unset.
- ❌ **Don't grow the local line or add a helper.** cancel reuses `cur_filter`
  (already declared); it is the simplest of the six actions (FINDING 7).
- ❌ **Don't skip validation because "it should work".** Run the mock.
- ❌ **Don't edit `restore.sh`/`filter.sh`/`state.sh`/`options.sh`/`preview.sh`/
  `renderer.sh`/`livepicker.sh`.** Only `input-handler.sh` changes.
- ❌ **Don't add `set -e` / `set -o pipefail`.** House style is `set -u` only
  (system_context §9); `refresh-client` legitimately returns non-zero detached.

---

## Confidence Score

**9/10** for one-pass implementation success.

This is the simplest of the six input-handler actions: a single ~12-line
surgical seam replacement with NO new locals, NO new helper, NO new files, and
NO catastrophic-class hazard (unlike confirm's FINDING 1/2 target-destruction
bug — cancel never switches the client to a target). The two non-obvious traps
(`set_state ""` is set-empty-not-unset but reads identically — FINDING 1; and
`$CURRENT_DIR` not `$SCRIPT_DIR` — FINDING 6) are both documented with the
ready-to-paste branch and verified by the throwaway mock. The pollution invariant
holds BY CONSTRUCTION (cancel issues zero switches; restore STEP-3's switch is a
deduped same-session switch — FINDING 4, verified live). The only residual risk is
the merge-ordering with the parallel T3.S1 (confirm) — but the two edits are in
disjoint textual regions (the cancel seam is below the confirm seam; T4 touches
neither the local line nor any helper), so they compose cleanly. The -1 is for
that serialization dependency (T4 must run against the post-T3 file) and the
inherent fragility of any mock that relies on `script`'s pty + a deduping recorder.
