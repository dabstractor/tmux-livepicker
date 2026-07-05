# PRP — P1.M5.T4.S1: restore.sh — select-layout ORIG_LAYOUT + clear_all_state + unbind livepicker

---

## Goal

**Feature Goal**: **MODIFY** `scripts/restore.sh` (CREATED by P1.M5.T1.S1;
STEP 3 landed by P1.M5.T2.S1; STEP 4 landed in parallel by P1.M5.T3.S1 — all
treated as CONTRACTS here) to fill the **T4 seam** — the FINAL two steps of
PRD §9 "State saved and restored": **step 5** `select-layout "$ORIG_LAYOUT"`
(byte-identical pane-geometry restore, best-effort) and **step 6** clear every
`@livepicker-*` picker state + unbind the `livepicker` key table. This is the
matched teardown of the ACTIVATE writes: the preview link (STEP 1 already
unlinked it), the window selection (STEP 2), and — most directly — the
**layout mutation** that browsing may have caused (none in the link/preview
path, but the picker MIGHT have been activated over a window whose layout a
concurrent app changed) + the **`@livepicker-*` option surface + the
`livepicker` key table** that activate STEP 2 (state save) + T4.S1 (key table
build) created. After T4, the PRD §15.21 "Restore" invariant holds: the
original window's pane layout is exact, zero picker runtime/orig state remains,
the `livepicker` table is gone, and the status redraws.

The single surgical edit replaces the T4 seam comment block (left by T1.S1
immediately above `return 0`) with the real restore logic:
(1) read `ORIG_LAYOUT` via `get_state` and `select-layout` it (best-effort,
guarded); (2) call `clear_all_state` (the ALREADY-COMPLETE helper in state.sh);
(3) `tmux unbind-key -a -T livepicker` (bulk table teardown); (4) a final
`tmux refresh-client -S` so the restored status draws.

**Deliverable**: A single in-place edit to `scripts/restore.sh` inside
`restore_main`: (a) append `orig_layout` to the `local` declaration (which by
implementation time holds T1.S1's + T2.S1's + T3.S1's locals); (b) replace the
T4 seam comment block (the multi-line `# --- T4 (P1.M5.T4.S1): select-layout
ORIG_LAYOUT ... ---` + its trailing 3-line sub-comment, sitting immediately
above `return 0`) with the STEP 5 + STEP 6 block. No other file is touched.
STEP 1 (unlink), STEP 2 (select-window), STEP 3 (keep/cancel switch), STEP 4
(status/status-format/key-table/renumber/hook), and the driver are all left
untouched. This is the LAST subtask of the P1.M5 restore module — after it,
`restore.sh` is feature-complete for the MVP.

**Success Definition**:
- `bash -n scripts/restore.sh` passes; `shellcheck scripts/restore.sh` is clean
  (0 findings; the existing file-level `# shellcheck disable=SC1091,SC2153` from
  T1.S1 still covers everything — T4 adds NO new word-split on user input).
  Tabs only; `set -u`, NO `set -e`.
- **Byte-identical layout restore (work-item §5 MOCKING):** under the socket
  shim with an attached client, capture `#{window_layout}` of a 3-pane window
  BEFORE activate; activate + navigate (which links other windows into the
  driver); `restore.sh cancel`; assert `#{window_layout}` matches the
  pre-activation layout BYTE-FOR-BYTE. This is the PRD §15.21 "The original
  window's pane layout is exact" check.
- **Zero picker state remains (work-item §4 OUTPUT, SCOPED):**
  `tmux show-options -g | grep '@livepicker-orig-'` is EMPTY and the 5 runtime
  keys (`@livepicker-mode`/`-list`/`-filter`/`-index`/`-linked-id`) are EMPTY.
  (PRD §11 CONFIG keys — `@livepicker-key`, `@livepicker-fg`, `@livepicker-type`,
  ... — are PRESERVED by `clear_all_state` per state.sh CORRECTION A; the
  work-item's literal "no @livepicker-* options remain" is TOO BROAD and would
  wipe user config — see CORRECTION 2 below.)
- **The `livepicker` table is gone (work-item §4 OUTPUT):**
  `tmux list-keys -T livepicker` returns rc=1 ("table livepicker doesn't exist")
  — every key activate T4.S1 copied/bound (~169) has been removed.
- **THREE CONTRACT CORRECTIONS encoded (load-bearing):**
  1. **`kill-key-table` does NOT exist on tmux 3.6b** (`unknown command`,
     verified). The work-item's "`tmux kill-key-table livepicker` if available on
     3.6b (verify; if not, loop unbind)" resolves to the FALLBACK. T4 uses
     `tmux unbind-key -a -T livepicker` (bulk atomic teardown — FINDING 4), NOT
     the per-key loop (cleaner + race-free) and NOT the non-existent
     `kill-key-table`.
  2. **The "no @livepicker-* options remain" assertion is TOO BROAD.** Taken
     literally it would clear PRD §11 config (`@livepicker-key Space`,
     `@livepicker-fg #ffffff`, `@livepicker-type session`) — breaking the next
     activation (no key → guard refuses to bind) and the renderer colors.
     `clear_all_state` (state.sh CORRECTION A) clears ONLY runtime + `orig-*`,
     preserving config. T4 CALLS `clear_all_state` unchanged; the MOCK asserts
     the SCOPED grep (`@livepicker-orig-` + the 5 runtime names), not the broad
     `grep livepicker`.
  3. **`select-layout` is BEST-EFFORT + must read ORIG_LAYOUT BEFORE
     clear_all_state.** An invalid/vanished/empty layout returns rc=1 (verified)
     → guard `2>/dev/null || true`. And `clear_all_state` CLEARS
     `@livepicker-orig-layout`, so the read MUST precede the clear (ORDER is
     load-bearing — FINDING 8).
- **No off-limits work:** STEP 5 + STEP 6 ONLY. NO re-touching of STEP 1/2/3/4
  (T1/T2/T3), NO re-`select-window` (STEP 2 already did it — FINDING 7), NO
  `link-window`/`capture-pane` (preview.sh), NO status/status-format/key-table/
  renumber/hook mutation (T3 owns those).

## User Persona (if applicable)

**Target User**: None directly (internal teardown steps 5–6 of 6 — the FINAL
restore steps). Transitively: the end user who pressed cancel or confirm
(PRD §3 stories 3–4). T4.S1 is what makes BOTH stories literally TRUE at the
end: after **cancel** ("I press Escape ... everything is exactly as it was"),
the pane geometry is byte-identical, no picker litter remains, the `livepicker`
table is gone, and the status bar redraws to its original; after **keep** ("I
press Enter ... the client switches to it"), the ONLY visible difference is the
one session switch — every pane layout, every option surface, and the key table
are clean.

**Use Case**: The user browsed sessions, then pressed confirm or cancel →
`input-handler.sh` (P1.M6) invokes `restore.sh <keep|cancel>`. STEP 1 (unlink)
+ STEP 2 (select-window) + STEP 3 (keep/cancel switch) + STEP 4 (status/format/
key-table/renumber/hook) ran first inside `restore_main`. **T4.S1 (this task)**
runs LAST: it restores the original pane geometry (best-effort), clears every
picker-internal `@livepicker-*` option (runtime + saved-state, preserving
config), tears down the `livepicker` key table (so no stale bindings linger),
and fires a final `refresh-client -S` so the restored status draws. After T4,
restore is complete and the tmux server is indistinguishable from its
pre-activation state (modulo the one confirm-time session switch in the `keep`
path).

**User Journey** (T4.S1 scope — the layout is restored, state is cleared, the
table is unbound, the status redraws):
1. …STEP 1 unlinked the preview; STEP 2 re-selected ORIG_WINDOW; STEP 3 switched
   the client (cancel) or did nothing (keep); STEP 4 restored status/
   status-format/key-table/renumber/hook.
2. **T4.S1 (this task):**
   - read `@livepicker-orig-layout` (the exact `#{window_layout}` activate saved)
     via `get_state "$ORIG_LAYOUT" ""`;
   - `tmux select-layout "$orig_layout"` (best-effort, `2>/dev/null || true`) —
     the active window (ORIG_WINDOW, selected by STEP 2) regains its exact pane
     geometry;
   - `clear_all_state` → unsets the 5 runtime `@livepicker-*` keys + every
     `@livepicker-orig-*` key (incl. ORIG_LAYOUT, just read); PRESERVES PRD §11
     config;
   - `tmux unbind-key -a -T livepicker 2>/dev/null || true` → removes EVERY key
     activate T4.S1 copied/bound (~169); the `livepicker` table is gone;
   - `tmux refresh-client -S 2>/dev/null || true` → the restored status
     (status-format from T3) draws.
3. `return 0` (T1.S1's driver exits 0).

**Pain Points Addressed**:
- (a) **Pane geometry not restored.** Without `select-layout "$ORIG_LAYOUT"`,
  if anything mutated the active window's pane layout during the picker (a
  concurrent app, or a future feature that rearranges), the user would come back
  to a different pane split. T4.S1 restores it byte-for-byte (best-effort, so a
  race or a vanished window never blocks the teardown).
- (b) **Picker litter left behind.** Without `clear_all_state`, the
  `@livepicker-mode`/`-list`/`-filter`/`-index`/`-linked-id` runtime keys + every
  `@livepicker-orig-*` saved-state key would persist after exit — a permanent
  options-surface pollution (visible in `show-options -g`) and a stale-mode bug
  (a second activation's double-activation guard would see `@livepicker-mode=on`
  and refuse to fire). T4.S1 clears them all.
- (c) **Stale key bindings / dead table.** Without unbinding, the `livepicker`
  table (and its ~169 copied+explicit bindings) would persist FOREVER — invisible
  weight, and if `key-table` were ever flipped back to `livepicker` (a bug, or a
  future feature), every key would route to a now-meaningless `input-handler.sh`
  path. T4.S1 removes the entire table atomically (`unbind-key -a -T livepicker`).
- (d) **Status not redrawn.** Without the final `refresh-client -S`, the restored
  `status-format` (T3) might not draw until the next unrelated redraw — a visible
  flicker / lag. T4.S1 forces the redraw (PRD §16: "Every input action must call
  `refresh-client -S`").

## Why

- **PRD §9 "State saved and restored"** is the controlling spec. Restore steps
  5–6: "5. `select-layout "$ORIG_LAYOUT"` for the original window. 6. Clear every
  `@livepicker-*` option and unbind the `livepicker` table." T4.S1 owns BOTH
  (the file's last two steps). Steps 1–4 are T1/T2/T3.
- **PRD §15.21 "Restore"** is the validation invariant: "After exit ... The
  original window's pane layout is exact (`select-layout` to the saved layout).
  ... No `@livepicker-*` options remain (`tmux show-options -g | grep livepicker`
  prints nothing)." T4.S1 is what makes both literally true — with the
  CORRECTION 2 scoping (config keys persist; the assertion is on runtime+orig).
- **PRD §16 "Implementation risks and notes" / "Status renderer refresh":** "The
  `#()` renderer only re-runs on status redraw. Every input action must call
  `refresh-client -S`." T4.S1's final `refresh-client -S` is the teardown's
  contribution to that rule.
- **Boundary respect.** T4.S1 touches ONLY: (1) one state read
  (`@livepicker-orig-layout`); (2) four tmux mutations (`select-layout`,
  `clear_all_state` which is options-only, `unbind-key -a -T livepicker`,
  `refresh-client -S`), each guarded. It does NOT: re-unlink/re-select-window/
  re-switch (STEP 1/2/3), mutate status/status-format/key-table/renumber/hook
  (STEP 4 — T3 owns those), or call `link-window`/`capture-pane` (preview.sh).
- **Scope cohesion.** T4.S1 is the restore counterpart of TWO activate writers:
  activate STEP 2 (state save — wrote `ORIG_LAYOUT`) ↔ T4.S1 select-layout
  restore; activate T4.S1 (key table build — copied prefix/root + bound explicit
  keys into `livepicker`) ↔ T4.S1 `unbind-key -a -T livepicker` teardown. The
  shared contract is the `@livepicker-orig-*` keys activate wrote and the
  `livepicker` table activate populated. T4.S1 is the LAST subtask of P1.M5 —
  after it, `restore.sh` is feature-complete; the next module is P1.M6
  (input-handler.sh, the CALLER of restore.sh).

## What

A surgical edit to the existing `scripts/restore.sh` (the file T1.S1 created,
STEP 3 landed by T2.S1, STEP 4 landed in parallel by T3.S1). Two changes, both
inside `restore_main`:

1. **Append `orig_layout` to the `local` declaration.** By implementation time
   the line holds T1.S1's + T2.S1's + T3.S1's locals
   (`local linked_id orig_window current_session orig_session mode r_status r_kt
   r_renumber r_hook hk_line hk_idx hk_cmd` per the T3.S1 PRP). T4.S1 appends
   `orig_layout` to that line (it is the only new local T4 needs).
2. **Replace the T4 seam comment block** (the multi-line
   `# --- T4 (P1.M5.T4.S1): select-layout ORIG_LAYOUT + clear_all_state +
   # unbind-key -T livepicker (insert here) ---` + its trailing 3-line
   sub-comment `# PRD §9 restore steps 5-6. select-layout ... ; clear_all_state
   # ... ; then tmux unbind-key -T livepicker <each> ...`, sitting immediately
   above `return 0`) with the STEP 5 + STEP 6 block from "Implementation
   Patterns & Key Details" below.

The header doc-comment's seam map (lines describing "5. select-layout
"$ORIG_LAYOUT". [T4 seam]" / "6. clear_all_state + unbind the livepicker table.
[T4 seam]") already describes T4; T4.S1 may leave the header as-is (it remains
accurate) — no header edit is required. (Optional: relabel `[T4 seam]` → `[T4]`
on those two lines to mark them done; not required for success.)

### Success Criteria

- [ ] `scripts/restore.sh` still passes `bash -n` + `shellcheck` (0 findings;
      T4 adds NO word-split on user input → no new disable).
- [ ] The `restore_main` `local` line now includes `orig_layout` (appended after
      T3.S1's locals).
- [ ] The T4 seam comment block is REPLACED by STEP 5 + STEP 6 (the comment
      block is gone; the restore calls are present).
- [ ] STEP 5: `orig_layout="$(get_state "$ORIG_LAYOUT" "")"` then
      `[ -n "$orig_layout" ] && tmux select-layout "$orig_layout" 2>/dev/null || true`
      (best-effort, guarded, non-empty guard).
- [ ] STEP 6a: `clear_all_state` called once (the state.sh helper; no
      re-implementation).
- [ ] STEP 6b: `tmux unbind-key -a -T livepicker 2>/dev/null || true` (BULK —
      CORRECTION 1; NOT `kill-key-table` which doesn't exist; NOT a per-key loop).
- [ ] STEP 6c: `tmux refresh-client -S 2>/dev/null || true` (final redraw).
- [ ] ORDER: select-layout (reads ORIG_LAYOUT) BEFORE clear_all_state (clears
      ORIG_LAYOUT) — FINDING 8.
- [ ] Tabs only (`grep -Pn '^    '` empty); `set -u`, NO `set -e`.
- [ ] NO off-limits work: STEP 1 (unlink), STEP 2 (select-window), STEP 3
      (keep/cancel switch), STEP 4 (status/format/key-table/renumber/hook)
      unchanged; NO re-`select-window` (FINDING 7); the header, source trio, and
      driver unchanged.
- [ ] Mock (work-item §5): capture `#{window_layout}` of a 3-pane window before
      activate; activate + nav (link other windows); `restore.sh cancel`; assert
      `#{window_layout}` byte-identical AND `grep '@livepicker-orig-'` empty AND
      the 5 runtime keys empty AND `list-keys -T livepicker` rc=1 (table gone).
      Config keys (@livepicker-key/fg/type) PRESERVED. See Validation Loop §2.

## All Needed Context

### Context Completeness Check

_Pass_: A developer who has never seen this repo can implement T4.S1 from
(a) the verbatim STEP 5+6 block in "Implementation Patterns & Key Details"
(complete, ready to paste in place of the T4 seam comment), (b) the 9
live-verified findings in `research/restore_layout_clearstate_unbind_findings.md`
— most critically **FINDING 3** (`kill-key-table` does NOT exist on 3.6b → use
`unbind-key -a -T livepicker`), **FINDING 4** (the bulk `unbind-key -a -T
livepicker` removes ALL keys atomically, rc=0; rc=1 "table doesn't exist" when
empty → guard for idempotency), **FINDING 2** (`select-layout` is best-effort:
rc=1 on invalid/vanished/empty → guard), **FINDING 6** (`clear_all_state` clears
runtime+orig, PRESERVES config — the basis for CORRECTION 2), **FINDING 8**
(ORDER: select-layout BEFORE clear_all_state, since clear clears ORIG_LAYOUT),
and **FINDING 5** (`refresh-client -S` needs a client → guard), and (c) the
socket-shim mock that captures `#{window_layout}` before activate, runs the full
activate→nav→restore-cancel cycle, and asserts byte-identical layout + scoped
state clearance + table-gone. The INPUT dependencies (`state.sh` ORIG_LAYOUT/
get_state/clear_all_state, the `restore.sh` file with the T4 seam from T1.S1 +
STEP 4 from T3.S1) are COMPLETE/present (T3.S1 treated as a CONTRACT landing in
parallel).

### Documentation & References

```yaml
# MUST READ — the HOST FILE (the file this task edits). Created by P1.M5.T1.S1;
#   STEP 3 landed by T2.S1; STEP 4 lands in parallel by T3.S1 (all CONTRACTS).
- file: scripts/restore.sh
  why: contains restore_main() with STEP 1 (unlink) + STEP 2 (select-window) +
       STEP 3 (keep/cancel switch) + STEP 4 (status/format/key-table/renumber/hook
       — T3.S1) + the T4 seam comment block (the multi-line "# --- T4
       (P1.M5.T4.S1): select-layout ORIG_LAYOUT + clear_all_state + unbind-key
       -T livepicker (insert here) ---" + its trailing 3-line sub-comment, sitting
       immediately above `return 0`) that T4.S1 REPLACES. T4.S1 also appends
       `orig_layout` to the `local` declaration line (after T3.S1's locals). The
       file already sources the lib trio and already has
       `# shellcheck disable=SC1091,SC2153`.
  pattern: STEP 1/2/3/4 use `2>/dev/null || true` on fail-possible tmux calls;
           `get_state "$ORIG_*" "<default>"` for state reads; ONE tab indent.
           T4's select-layout/unbind/refresh follow the SAME guard idiom;
           clear_all_state is called bare (it self-guards internally).
  critical: T4.S1 is a SURGICAL EDIT — touch ONLY the `local` line (append
            orig_layout) and the T4 seam block. Do NOT touch STEP 1/2/3/4, the
            header, the source trio, or the driver. Do NOT re-select-window
            (STEP 2 already did — FINDING 7).

# MUST READ — INPUT dependency: state.sh (ORIG_LAYOUT / get_state / clear_all_state). COMPLETE.
- file: scripts/state.sh
  why: (1) clear_all_state() — ALREADY COMPLETE; unsets the 5 runtime keys
       ($STATE_MODE/$STATE_LIST/$STATE_FILTER/$STATE_INDEX/$STATE_LINKED_ID via
       set-option -gu) AND greps `show-options -g | grep '@livepicker-orig-'` to
       unset every saved-state key. PRESERVES PRD §11 config (CORRECTION A —
       @livepicker-type is explicitly NOT in the runtime clear list; the grep is
       scoped to '@livepicker-orig-'). T4.S1 CALLS this. (2) readonly
       ORIG_LAYOUT="@livepicker-orig-layout" (the saved-state CONTRACT key
       activate wrote; T4 reads it back). (3) get_state (thin accessor over
       tmux show-option -gqv; ${2:-} default is safe under set -u).
  critical: clear_all_state CLEARS @livepicker-orig-layout, so T4 MUST read
            ORIG_LAYOUT and run select-layout BEFORE calling clear_all_state
            (FINDING 8 — ORDER is load-bearing). clear_all_state owns the option
            teardown ENTIRELY; T4 adds no other option-clear logic.

# MUST READ — INPUT dependency: utils.sh (the option helpers — for context). COMPLETE.
- file: scripts/utils.sh
  why: tmux_get_opt(name,default) -> show-option -gqv (what get_state delegates
       to); tmux_set_opt/tmux_unset_opt. T4.S1 uses NONE of these directly — it
       reads ORIG_LAYOUT via get_state (state.sh) and the option teardown is
       entirely inside clear_all_state. There is NO tmux_unbind_keys or
       tmux_refresh_client helper; T4 calls bare `tmux unbind-key -a -T
       livepicker` and `tmux refresh-client -S` directly (mirrors clear_all_state
       which calls `tmux set-option -gu` directly).
  critical: do NOT add a utils helper for unbind/refresh — house style permits
            bare tmux calls for one-off teardown primitives (clear_all_state is
            the precedent).

# MUST READ — INPUT dependency: options.sh (NOT directly used by T4, but config-key context). COMPLETE.
- file: scripts/options.sh
  why: defines the PRD §11 config accessors (opt_key/opt_fg/opt_type/...). T4
       does NOT call these, but CORRECTION 2 depends on knowing these keys are
       CONFIG that clear_all_state PRESERVES (they are NOT @livepicker-orig-* and
       NOT in the 5-key runtime list). The mock seeds @livepicker-key/fg/type and
       asserts they SURVIVE restore.
  critical: the config keys are the reason the work-item's literal "no
            @livepicker-* options remain" is TOO BROAD (CORRECTION 2).

# MUST READ — the SAVE side (what ORIG_LAYOUT contains — the input contract).
- docfile: plan/001_fd5d622d3939/P1M4T1S1/PRP.md
  why: activate STEP 2 wrote @livepicker-orig-layout via
       `tmux set-option -g "$ORIG_LAYOUT" "$(tmux display-message -p '#{window_layout}')"`
       (PRP line 608 / 491). So ORIG_LAYOUT is the EXACT #{window_layout} string
       (e.g. `e79b,120x40,0,0[120x20,0,0,0,...]`) — a tmux layout tree. T4 feeds
       it back to select-layout UNCHANGED (no parsing). Confirmed round-trip
       byte-identical (research FINDING 1).
  section: "STEP 2 save" (the ORIG_LAYOUT capture), "STATE WRITES".

# MUST READ — the matched ACTIVATE writer T4.S1 (the key table T4 unbinds).
- docfile: plan/001_fd5d622d3939/P1M4T4S1/PRP.md
  why: activate T4.S1 built the `livepicker` key table: COPY prefix/root bindings
       (via source-file) + BIND explicit picker keys (typing/actions/nav) + SWITCH
       key-table. The result is ~169 keys in the `livepicker` table. T4.S1
       (restore) tears that table DOWN via `unbind-key -a -T livepicker` (bulk —
       FINDING 4). This is the matched pair: activate builds the table, restore
       removes it entirely. (Activate's key-table SWITCH is restored by T3.S1's
       `set-option -g key-table "$ORIG_KEY_TABLE"`; T4.S1 removes the BINDINGS.)
  section: "Goal" (the copy+bind+switch), research/key_table_findings.md FINDING 3.

# MUST READ — the parallel sibling PRP that shares this file (seam contract).
- docfile: plan/001_fd5d622d3939/P1M5T3S1/PRP.md
  why: T3 owns restore step 4 (status/status-format/key-table-option/renumber/
       hook). Its block sits ABOVE the T4 seam. T3.S1 ALSO extends the `local`
       line (adds r_status/r_kt/r_renumber/r_hook/hk_line/hk_idx/hk_cmd). T4.S1
       appends `orig_layout` AFTER T3.S1's locals. T4 must leave T3's block
       intact and insert at the T4 seam BELOW it. (T3.S1 lands in parallel; treat
       its output as a CONTRACT — assume STEP 4 + its locals are present when T4
       begins.)
  section: "What" (the local-line extension + the STEP 4 block), "Desired Codebase tree".

# MUST READ — the T1.S1 PRP (the CONTRACT for the host file's base + STEP 1/2 + seams).
- docfile: plan/001_fd5d622d3939/P1M5T1S1/PRP.md
  why: defines scripts/restore.sh's skeleton, STEP 1, STEP 2, and the exact T4
       seam comment (the text T4.S1 replaces). T4.S1 assumes this file exists as
       specified (with T2.S1's STEP 3 and T3.S1's STEP 4 landed above the seam).

# MUST READ — the empirical ground-truth for THIS task (9 live-verified findings).
- docfile: plan/001_fd5d622d3939/P1M5T4S1/research/restore_layout_clearstate_unbind_findings.md
  why: FINDING 1 (select-layout round-trips byte-identical); FINDING 2 (LOAD-
       BEARING: select-layout is best-effort — rc=1 on invalid/vanished/empty →
       guard + non-empty guard); FINDING 3 (LOAD-BEARING: kill-key-table does NOT
       exist on 3.6b → use unbind-key -a -T livepicker); FINDING 4 (LOAD-BEARING:
       unbind-key -a -T livepicker removes ALL keys atomically rc=0; rc=1 "table
       doesn't exist" when empty → guard for idempotency); FINDING 5 (refresh-
       client -S needs a client → guard); FINDING 6 (LOAD-BEARING: clear_all_state
       clears runtime+orig, PRESERVES config — basis for CORRECTION 2); FINDING 7
       (T4 does NOT re-select-window; STEP 2 did); FINDING 8 (LOAD-BEARING: ORDER
       — select-layout BEFORE clear_all_state); FINDING 9 (house style).
  critical: Read BEFORE writing the block. FINDINGS 3+4 are the unbind CORRECTION;
            FINDING 2 is the select-layout guard; FINDING 6 is the state-clearance
            CORRECTION; FINDING 8 is the ORDER constraint.

# MUST READ — the PRD sections selected for this work item.
- docfile: PRD.md
  why: §9 "State saved and restored" (restore steps 5-6: select-layout
       $ORIG_LAYOUT; clear every @livepicker-* option + unbind the livepicker
       table); §15.21 "Restore" (the layout-is-exact + no-state-remains invariant);
       §16 "Implementation risks and notes" (Status renderer refresh: every input
       action must call refresh-client -S); §5.2 "Data flow" (the restore path).
  section: "§9 State saved and restored", "§15 Validation / Restore", "§16
           Implementation risks and notes"

# MUST READ — system ground-truth (shell style + the invariants).
- docfile: plan/001_fd5d622d3939/architecture/system_context.md
  why: §3 INVARIANT A (select-layout/select-window/unlink fire neither
       client-session-changed — so restore steps 5-6 cannot pollute session
       history); §9 shell style (set -u ONLY, NO -e, NO -o pipefail; tabs; local
       for all function locals; || true on fail-possible tmux calls); §2 (live
       values: key-table=root, the exact hook line — confirms T3 restored them).
  section: "§3 The three load-bearing invariants", "§9 Shell style", "§2 Verified environment"

# MUST READ — primitive verification (select-layout / unbind-key / refresh-client).
- docfile: plan/001_fd5d622d3939/architecture/tmux_primitives.md
  why: the select-layout / window_layout round-trip; the unbind-key -T / -a flags;
       refresh-client -S (status redraw). (Note: kill-key-table and list-tables
       are NOT tmux 3.6b commands — verified in T4.S1 research FINDING 3; the
       primitives doc predates that verification, so trust the research file.)
  section: select-layout, key-table/bind-key/unbind-key, refresh-client.
```

### Current Codebase tree

```bash
tmux-livepicker/
  PRD.md
  plugin.tmux                 # COMPLETE. Unchanged.
  plan/001_fd5d622d3939/{architecture/*.md, tasks.json, prd_snapshot.md, prd_index.txt}
  plan/001_fd5d622d3939/P1M5T1S1/{PRP.md, research/restore_unlink_select_findings.md}  # HOST FILE creator (STEP 1+2)
  plan/001_fd5d622d3939/P1M5T2S1/{PRP.md, research/restore_keep_cancel_findings.md}     # STEP 3
  plan/001_fd5d622d3939/P1M5T3S1/{PRP.md, research/restore_status_keys_hook_findings.md}  # STEP 4 (parallel; CONTRACT)
  plan/001_fd5d622d3939/P1M5T4S1/{PRP.md, research/restore_layout_clearstate_unbind_findings.md}  # THIS
  scripts/
    options.sh   # COMPLETE. Unchanged. (config keys — context for CORRECTION 2.)
    utils.sh     # COMPLETE. Unchanged. (T4 calls no utils helper directly.)
    state.sh     # COMPLETE — ORIG_LAYOUT/get_state/clear_all_state (INPUT deps). Unchanged.
    renderer.sh  # COMPLETE. Unchanged.
    preview.sh   # COMPLETE (P1.M3). Unchanged.
    livepicker.sh   # COMPLETE (P1.M4). Unchanged.
    restore.sh   # CREATED by P1.M5.T1.S1 (STEP 1+2 + T2/T3/T4 seams); STEP 3 by T2.S1;
                 # STEP 4 by T3.S1 (parallel; CONTRACT). THIS task (T4.S1) EDITS it:
                 # append `orig_layout` to `local` + replace the T4 seam with STEP 5+6.
  .gitignore
  # NOTE: NO test harness (P1.M7); NO input-handler.sh yet (P1.M6 — the CALLER of
  #       restore.sh). Validate via the throwaway socket-shim mock (MUST keep an
  #       attached client so display-message + refresh-client -S work — FINDING 5).
  # The live session-window-changed hook + key-table=root are restored by T3.S1
  # (STEP 4); T4.S1 only does layout + state-clear + unbind + refresh.
```

### Desired Codebase tree with files to be added and responsibility of file

```bash
tmux-livepicker/
  scripts/
    options.sh   # unchanged.
    utils.sh     # unchanged.
    state.sh     # unchanged.
    renderer.sh  # unchanged.
    preview.sh   # unchanged.
    livepicker.sh   # unchanged.
    restore.sh   # EDITED (this task). ONLY two changes inside restore_main():
                  #   (1) `local ... r_status r_kt r_renumber r_hook hk_line hk_idx hk_cmd orig_layout`
                  #       (append orig_layout after T3.S1's locals)
                  #   (2) T4 seam comment block REPLACED by STEP 5 + STEP 6:
                  #         orig_layout="$(get_state "$ORIG_LAYOUT" "")"
                  #         [ -n "$orig_layout" ] && tmux select-layout "$orig_layout" 2>/dev/null || true
                  #         clear_all_state
                  #         tmux unbind-key -a -T livepicker 2>/dev/null || true     # bulk (CORRECTION 1)
                  #         tmux refresh-client -S 2>/dev/null || true
                  # After T4.S1: layout byte-identical; runtime+orig state cleared
                  # (config preserved — CORRECTION 2); livepicker table gone; status redrawn.
                  # STEP 1/2/3/4/header/source/driver: UNCHANGED. restore.sh is FEATURE-COMPLETE.
```

### Known Gotchas of our codebase & Library Quirks

```bash
# CRITICAL (research FINDING 3 — CORRECTION to the work-item): `kill-key-table`
#   does NOT exist on tmux 3.6b:
#     $ tmux kill-key-table livepicker
#     unknown command: kill-key-table            rc=1
#   The keys REMAIN bound. The work-item's "OR tmux kill-key-table livepicker if
#   available on 3.6b (verify; if not, loop unbind)" resolves to the FALLBACK.
#   T4 uses the BULK `unbind-key -a -T livepicker` (FINDING 4) — NOT the per-key
#   loop (cleaner, atomic, race-free) and NOT the non-existent kill-key-table.
#   (`list-tables` also does NOT exist on 3.6b — not needed by T4.)

# CRITICAL (research FINDING 4 — the unbind primitive): `unbind-key -a -T
#   livepicker` removes EVERY key in the table atomically (rc=0 when keys exist;
#   after it, list-keys -T livepicker rc=1 "table doesn't exist" = the work-item's
#   "livepicker table gone" success). When the table is ALREADY empty (double-
#   restore / restore-without-activate) it rc=1 -> MUST guard:
#     tmux unbind-key -a -T livepicker 2>/dev/null || true
#   (The per-key loop alternative — list-keys | while read | unbind-key -T
#   livepicker "$key" — ALSO works but is ~169 calls, needs the same empty guard,
#   and risks a re-bind race. Prefer the bulk -a form.)

# CRITICAL (research FINDING 2 — select-layout is best-effort): `select-layout`
#   returns rc=1 (and refuses to change the layout) when the layout string is
#   INVALID, the target window has VANISHED, OR the string is EMPTY. The work-item
#   contract: "Guard failure (layout may be invalid if windows changed) —
#   best-effort, do not block exit." So:
#     orig_layout="$(get_state "$ORIG_LAYOUT" "")"
#     [ -n "$orig_layout" ] && tmux select-layout "$orig_layout" 2>/dev/null || true
#   The non-empty guard avoids the empty-string rc=1 path; the || true covers
#   invalid/vanished. Under set -u (NO set -e) the || true is belt-and-braces but
#   is the documented idiom (mirror STEP 1/2).

# CRITICAL (research FINDING 6 + state.sh CORRECTION A — the state-clearance
#   CORRECTION): the work-item's "no @livepicker-* options remain" (`show-options
#   -g | grep livepicker` empty) is TOO BROAD. Taken literally it would clear PRD
#   §11 CONFIG (@livepicker-key Space, @livepicker-fg #ffffff, @livepicker-type
#   session) — breaking the next activation (no @livepicker-key → plugin.tmux's
#   guard refuses to bind) and the renderer colors. `clear_all_state` (state.sh
#   CORRECTION A) clears ONLY the 5 runtime keys + every @livepicker-orig-*, and
#   PRESERVES config. T4 CALLS clear_all_state unchanged; the MOCK asserts the
#   SCOPED clearance:
#     show-options -g | grep '@livepicker-orig-'            # EMPTY
#     show-option -gqv @livepicker-mode (etc., 5 runtime)   # EMPTY
#     show-option -gqv @livepicker-key/fg/type              # UNCHANGED (config preserved)
#   Do NOT broaden clear_all_state; do NOT add a `set-option -gu @livepicker-*`
#   wildcard (would wipe config).

# CRITICAL (research FINDING 8 — ORDER is load-bearing): clear_all_state CLEARS
#   @livepicker-orig-layout. T4 reads ORIG_LAYOUT via get_state and feeds it to
#   select-layout. If clear_all_state ran FIRST, ORIG_LAYOUT would be empty and
#   select-layout would no-op (or fail on empty — FINDING 2). So the ORDER is:
#     1. read orig_layout
#     2. select-layout "$orig_layout"      (STEP 5)
#     3. clear_all_state                   (STEP 6a — clears ORIG_LAYOUT + runtime)
#     4. unbind-key -a -T livepicker       (STEP 6b)
#     5. refresh-client -S                 (final)
#   This matches PRD §9 (step 5 select-layout, THEN step 6 clear+unbind).

# CRITICAL (research FINDING 7): T4 does NOT re-select-window. The work-item's
#   first bullet ("tmux select-window -t "$ORIG_WINDOW" (ensure target window is
#   active for layout apply)") is a NOTE about the PREREQUISITE for select-layout
#   (layout applies to the active window), NOT a new command. STEP 2 (T1.S1)
#   ALREADY ran `select-window -t "$orig_window"` above the T4 seam. T4 REUSES
#   that — do NOT add a redundant select-window call (would duplicate T1.S1's
#   work and muddy the seam boundary).

# GOTCHA (research FINDING 5): `refresh-client -S` redraws the status line (-S =
#   status only). With NO client attached it rc=1 ("no current client"); with a
#   client rc=0. Production always has a client (restore runs from a key press),
#   but the MOCK + detached edges rc=1 -> guard `2>/dev/null || true`. This is the
#   LAST call in restore_main (after select-layout + clear + unbind) so the redraw
#   reflects the FULLY restored state. PRD §16: "Every input action must call
#   refresh-client -S."

# GOTCHA: `set -u` is in effect. `orig_layout` is assigned first (via get_state
#   with a default of "") before any use. get_state's ${2:-} default makes the
#   read safe even when ORIG_LAYOUT is unset (returns "").

# GOTCHA (research FINDING 1): ORIG_LAYOUT is the EXACT #{window_layout} string
#   activate saved (e.g. `e79b,120x40,0,0[120x20,0,0,0,...]`). Feed it to
#   select-layout UNCHANGED — no parsing, no quoting games (it contains commas,
#   brackets, commas — pass it as ONE double-quoted arg: "$orig_layout").
#   Verified byte-identical round-trip.

# GOTCHA (research FINDING 9): there is NO tmux_unbind_keys / tmux_refresh_client
#   helper in utils.sh. T4 calls bare `tmux unbind-key -a -T livepicker` and
#   `tmux refresh-client -S` directly (mirrors clear_all_state, which calls
#   `tmux set-option -gu` directly — house style permits bare tmux calls for
#   one-off teardown primitives).

# GOTCHA: this task is a SURGICAL EDIT to an EXISTING file. It REPLACES the T4
#   seam comment block and APPENDS `orig_layout` to the `local` line. It does NOT
#   create a file, does NOT touch STEP 1/2/3/4/header/source/driver. Preserve the
#   one-tab indent of restore_main's body.

# CRITICAL: NO `set -e`, NO `set -o pipefail` (house style; system_context §9).
#   select-layout/unbind-key/refresh-client all legitimately return non-zero
#   (FINDINGS 2/4/5); under set -e that would abort a half-restored teardown.
#   Every T4 tmux call gets `2>/dev/null || true`.

# STYLE (system_context §9): indent with TABS. Verify with `grep -Pn '^    ' scripts/restore.sh`
#   (expect empty). shfmt is NOT installed. `local` for ALL function locals.
```

## Implementation Blueprint

### Data models and structure

No new data model. T4.S1 adds ONE function-local to `restore_main`:
- `orig_layout` — read from `ORIG_LAYOUT` via `get_state "$ORIG_LAYOUT" ""` (the
  exact `#{window_layout}` string activate saved; empty ⇒ skip select-layout).

The **read set** is one accessor (`get_state "$ORIG_LAYOUT"`). The **write set**
is four tmux mutations: `select-layout` (best-effort), `clear_all_state`
(options-only, via the state.sh helper), `unbind-key -a -T livepicker` (table
teardown), `refresh-client -S` (status redraw). No new options, no new state
keys, no new files.

### Implementation Tasks (ordered by dependencies)

```yaml
Task 1: EDIT scripts/restore.sh — append orig_layout to `local` + replace the T4 seam with STEP 5+6
  - FILE: ./scripts/restore.sh  (EXISTING; created by P1.M5.T1.S1; STEP 3 by T2.S1;
          STEP 4 by T3.S1 in parallel — all CONTRACTS).
  - EDIT 1: append `orig_layout` to the `local` declaration line. By implementation
            time the line is (per T3.S1 PRP):
            `	local linked_id orig_window current_session orig_session mode r_status r_kt r_renumber r_hook hk_line hk_idx hk_cmd`
            Change it to:
            `	local linked_id orig_window current_session orig_session mode r_status r_kt r_renumber r_hook hk_line hk_idx hk_cmd orig_layout`
            (If T3.S1's exact locals differ, simply APPEND ` orig_layout` to the
            end of whatever the `local` line is — do not rewrite T3's locals.)
  - EDIT 2: REPLACE the T4 seam comment block (the multi-line block:
            "# --- T4 (P1.M5.T4.S1): select-layout ORIG_LAYOUT + clear_all_state +
             unbind-key -T livepicker (insert here) ---"
            + its trailing 3-line sub-comment "# PRD §9 restore steps 5-6. ...
             then tmux unbind-key -T livepicker <each> (or unbind-key -aT livepicker).")
            with the STEP 5 + STEP 6 block from "Implementation Patterns & Key
            Details" below (read orig_layout + select-layout + clear_all_state +
            unbind-key -a -T livepicker + refresh-client -S).
  - DO NOT touch: STEP 1 (unlink block), STEP 2 (select-window block), STEP 3
            (keep/cancel switch block), STEP 4 (status/format/key-table/renumber/
            hook block — T3.S1), the header doc, the source trio, the driver. Do
            NOT re-select-window (FINDING 7). (The header's seam-map lines
            "5. select-layout ... [T4 seam]" / "6. clear_all_state + unbind ...
            [T4 seam]" may optionally be relabeled "[T4]" — NOT required.)
  - PRESERVE: one-tab indent of restore_main's body; the file-level
            `# shellcheck disable=SC1091,SC2153`; `set -u`; NO `set -e`.

Task 2: VERIFY house style + no off-limits work
  - RUN: bash -n scripts/restore.sh            (expect exit 0, no output)
  - RUN: shellcheck scripts/restore.sh         (expect 0 findings; no new disable)
  - RUN: grep -Pn '^    ' scripts/restore.sh   (expect empty — tabs only)
  - RUN: grep -n 'set -e\|set -o pipefail' scripts/restore.sh  (expect empty)
  - EXPECT: exactly ONE select-layout (best-effort, guarded, non-empty guard);
    exactly ONE clear_all_state call; exactly ONE `unbind-key -a -T livepicker`
    (bulk — NOT kill-key-table, NOT a per-key loop); exactly ONE refresh-client -S;
    NO re-select-window (STEP 2 owns it); NO status/status-format/key-table-option/
    renumber/hook mutation (STEP 4/T3 owns those); NO link-window/capture-pane.
  - EXPECT: the order is select-layout -> clear_all_state -> unbind -> refresh
    (FINDING 8; ORIG_LAYOUT is read BEFORE clear_all_state clears it).

Task 3: VALIDATE (Level 1 syntax/lint + Level 2 socket-shim byte-identical-layout
        mock: capture #{window_layout} before activate; activate + nav (link other
        windows); restore.sh cancel; assert layout byte-identical + scoped state
        clearance + table-gone + config-preserved. Plus the empty-layout +
        double-restore idempotency variants.)
  - RUN the socket-shim mock (Validation Loop §2). Self-cleaning, isolated socket,
    attached client (FINDING 5 for refresh-client -S). Runs the REAL restore.sh
    with argv 'cancel' after a REAL activate.
```

### Implementation Patterns & Key Details

The complete, ready-to-paste STEP 5 + STEP 6 block (the implementer replaces the
T4 seam comment block with this; indent is ONE tab to match restore_main's body):

```bash
	# --- STEP 5 (PRD §9 restore step 5): restore the original pane layout ---
	# select-layout applies to the ACTIVE window. STEP 2 (T1.S1) already ran
	# `select-window -t "$ORIG_WINDOW"` above, so the target window is active —
	# T4 does NOT re-select-window (FINDING 7). ORIG_LAYOUT is the EXACT
	# #{window_layout} string activate STEP 2 saved (e.g.
	# "e79b,120x40,0,0[120x20,0,0,0,...]"); feed it back UNCHANGED (byte-identical
	# round-trip — FINDING 1). BEST-EFFORT (FINDING 2): an invalid/vanished/empty
	# layout returns rc=1 and MUST NOT block the teardown. Guard on non-empty
	# first (defensive — get_state defaults to "" if activate failed mid-save),
	# then `2>/dev/null || true` on the call.
	orig_layout="$(get_state "$ORIG_LAYOUT" "")"
	[ -n "$orig_layout" ] && tmux select-layout "$orig_layout" 2>/dev/null || true

	# --- STEP 6 (PRD §9 restore step 6): clear picker state + unbind the table ---
	# (a) clear_all_state (state.sh — ALREADY COMPLETE, P1.M1.T3.S1) unsets the 5
	#     runtime @livepicker-* keys ($STATE_MODE/$STATE_LIST/$STATE_FILTER/
	#     $STATE_INDEX/$STATE_LINKED_ID) AND every @livepicker-orig-* saved-state
	#     key (incl. ORIG_LAYOUT, just read above — so this MUST run AFTER the
	#     select-layout read: FINDING 8). It PRESERVES PRD §11 config
	#     (@livepicker-key/fg/type/...) — CORRECTION A in state.sh; the work-item's
	#     literal "no @livepicker-* options remain" is TOO BROAD (CORRECTION 2) —
	#     config must survive or the next activation breaks. Clears OPTIONS only;
	#     the key-table teardown is (b) below.
	# (b) unbind the livepicker key table activate T4.S1 built (~169 copied+explicit
	#     keys). kill-key-table does NOT exist on tmux 3.6b (FINDING 3 ->
	#     CORRECTION 1); use the BULK `unbind-key -a -T livepicker` (FINDING 4),
	#     which atomically removes EVERY key. When the table is already empty
	#     (double-restore / restore-without-activate) it rc=1 "table doesn't exist"
	#     -> guarded (idempotent). After this list-keys -T livepicker rc=1 = gone.
	# (c) refresh-client -S redraws the status so the restored status-format (T3)
	#     draws (PRD §16: every input action must call refresh-client -S). Requires
	#     a client (FINDING 5); production always has one (restore runs from a key
	#     press); guard for the detached edge / mock.
	clear_all_state
	tmux unbind-key -a -T livepicker 2>/dev/null || true
	tmux refresh-client -S 2>/dev/null || true
```

NOTE for the implementer:
- This block is the **only** new logic. It goes where the T4 seam comment block
  currently sits (immediately above `return 0`, below STEP 4 / T3.S1's block).
- The `local` line edit is the **only** other change (append `orig_layout`).
- Use `tmux unbind-key -a -T livepicker` (**bulk** — CORRECTION 1). Do NOT use
  `kill-key-table` (doesn't exist on 3.6b — FINDING 3). Do NOT use a per-key
  `list-keys | while read | unbind-key -T livepicker "$key"` loop (the bulk form
  is cleaner, atomic, and race-free — FINDING 4).
- Call `clear_all_state` as-is; do NOT re-implement the option teardown and do
  NOT broaden it (CORRECTION 2 — config must be preserved).
- Read `orig_layout` and run `select-layout` BEFORE `clear_all_state` (FINDING 8
  — clear_all_state clears ORIG_LAYOUT).
- Do NOT add a `select-window` call (STEP 2 / T1.S1 already did it — FINDING 7).
- Do NOT touch STEP 1, STEP 2, STEP 3, STEP 4, the header, the source trio, or
  the driver. Do NOT create any file. Do NOT add `set -e`.

### Integration Points

```yaml
HOST FILE (what this task edits):
  - scripts/restore.sh: restore_main() — `local` line appended (orig_layout);
    T4 seam REPLACED by STEP 5 + STEP 6.

CALLERS / CONSUMERS (this file's INPUT — provided by sibling subtasks + activate):
  - P1.M6.T3.S1 / T4.S1 (input-handler.sh confirm/cancel — PLANNED): invoke
        "$CURRENT_DIR/restore.sh" <keep|cancel>. T4.S1's STEP 5+6 runs LAST
        (after STEP 1-4). After T4, restore returns 0 and the picker is fully
        torn down — input-handler's job is done.
  - activate STEP 2 (P1.M4.T1.S1 — COMPLETE): wrote @livepicker-orig-layout (the
        exact #{window_layout} string) — the input T4's select-layout consumes.
  - activate T4.S1 (P1.M4.T4.S1 — COMPLETE): built the livepicker key table
        (~169 keys) — the table T4's unbind-key -a -T livepicker tears down.

STATE READS (this task — T4.S1 step 5):
  - @livepicker-orig-layout   (via get_state "$ORIG_LAYOUT" ""; written by activate STEP 2)

STATE WRITES (this task — via clear_all_state): the 5 runtime @livepicker-* keys +
  every @livepicker-orig-* key are CLEARED. PRD §11 config PRESERVED (CORRECTION 2).

TMUX MUTATIONS (this task — PRD §13 primitives):
  - select-layout "$orig_layout"   (best-effort; || true; byte-identical pane
        restore; fires neither client-session-changed — Invariant A)
  - clear_all_state -> set-option -gu on 5 runtime + every @livepicker-orig-*
        (options-only; config preserved)
  - unbind-key -a -T livepicker    (bulk table teardown; || true; idempotent)
  - refresh-client -S              (status redraw; || true; needs a client)
  - NO re-unlink-window/select-window/switch-client (STEP 1/2/3); NO status/
        status-format/key-table-option/renumber/hook mutation (STEP 4/T3); NO
        link-window/capture-pane (preview.sh).

DATABASE / MIGRATIONS / ROUTES / CONFIG: none.
```

## Validation Loop

### Level 1: Syntax & Style (Immediate Feedback)

```bash
# Run after editing the file — fix before proceeding.
bash -n scripts/restore.sh                     # syntax; expect no output, exit 0
shellcheck scripts/restore.sh                  # lint; expect 0 findings (the file-level
                                               # disable=SC1091,SC2153 from T1.S1 still covers all)
# Tabs-not-spaces sanity (shfmt NOT installed):
grep -Pn '^    ' scripts/restore.sh && echo "FAIL: 4-space indent found, use tabs" || echo "OK: tabs only"
# Confirm house style (set -u only, NO -e / NO pipefail):
grep -n 'set -e\|set -o pipefail' scripts/restore.sh && echo "FAIL: set -e/pipefail present" || echo "OK: set -u only"
# Confirm the `local` line was extended with orig_layout:
grep -n 'local .*orig_layout' scripts/restore.sh   # expect 1 (orig_layout appended after T3.S1's locals)
# Confirm T4's primitives are present (select-layout best-effort + clear_all_state + bulk unbind + refresh):
grep -n 'get_state "\$ORIG_LAYOUT" ""' scripts/restore.sh                                              # expect 1
grep -n '\[ -n "\$orig_layout" \] && tmux select-layout "\$orig_layout" 2>/dev/null || true' scripts/restore.sh   # expect 1
grep -n 'clear_all_state' scripts/restore.sh                                                          # expect 1
grep -n 'unbind-key -a -T livepicker 2>/dev/null || true' scripts/restore.sh                           # expect 1 (BULK)
grep -n 'refresh-client -S 2>/dev/null || true' scripts/restore.sh                                     # expect 1
# CORRECTIONS: NO kill-key-table (doesn't exist); bulk unbind (not per-key loop):
grep -n 'kill-key-table' scripts/restore.sh && echo "FAIL: kill-key-table does not exist on 3.6b" || echo "OK: no kill-key-table (CORRECTION 1)"
grep -n 'unbind-key -a' scripts/restore.sh && echo "OK: bulk unbind (CORRECTION 1 applied)" || echo "FAIL: missing bulk unbind"
# Confirm the T4 seam comment block is GONE (replaced by STEP 5+6):
grep -n 'T4 (P1.M5.T4.S1): select-layout ORIG_LAYOUT' scripts/restore.sh \
  && echo "WARN: re-check — the seam header comment may remain (ok if relabeled [T4])" || echo "OK: T4 seam replaced by STEP 5+6"
# Confirm T1.S1's STEP 1/2 + T2.S1's STEP 3 + T3.S1's STEP 4 are UNCHANGED:
grep -n 'unlink-window -t "\$current_session:\$linked_id" 2>/dev/null || true' scripts/restore.sh   # expect 1
grep -n 'select-window -t "\$orig_window" 2>/dev/null || true' scripts/restore.sh                    # expect 1
grep -n 'switch-client -t "=\$orig_session" 2>/dev/null || true' scripts/restore.sh                  # expect 1
grep -n 'state_status_format_restore' scripts/restore.sh                                            # expect 1 (T3.S1)
# Confirm ORDER: select-layout appears BEFORE clear_all_state (FINDING 8):
awk '/select-layout "\$orig_layout"/{sl=NR} /clear_all_state/{ca=NR} END{if(sl>0 && ca>0 && sl<ca) print "OK: select-layout (line "sl") before clear_all_state (line "ca")"; else print "FAIL: order wrong sl="sl" ca="ca}' scripts/restore.sh
# Confirm NO re-select-window leaked into T4 (STEP 2 owns it — FINDING 7):
# (there should be exactly ONE select-window, in STEP 2's block, NOT in the T4 block)
grep -c 'select-window' scripts/restore.sh   # expect 1 (STEP 2 only)
# Confirm NO off-limits work leaked in (no T4-status/preview mutations):
grep -n 'set-option -g status\|set-option -g key-table\|set-hook\|link-window\|capture-pane' scripts/restore.sh \
  | grep -v 'T3\|#\|r_status\|r_kt' \
  && echo "WARN: re-check (T3's status/key-table restores are expected; T4 must not add more)" || echo "OK: T4 adds no status/key-table/hook mutations"
# Run from the repo root.
```

### Level 2: Socket-Shim Mock Validation — byte-identical layout + scoped state clearance + table-gone, zero live-server impact

Reuses the PATH-wrapper socket shim. Self-cleaning. Seeds a 3-pane window,
captures `#{window_layout}`, runs the REAL activate (livepicker.sh) + nav (which
links other windows into the driver), runs the REAL `restore.sh cancel`, and
asserts the layout matches byte-for-byte + scoped state clearance + the
livepicker table is gone + config preserved. **MUST keep an attached client**
(display-message in activate + refresh-client -S in T4 need one — FINDING 5).

```bash
#!/usr/bin/env bash
# Throwaway socket-shim validation for scripts/restore.sh T4.S1 (do NOT commit).
set -u
REPO_ROOT="$(cd "$(dirname "$0")" && pwd)"
[ -f "$REPO_ROOT/scripts/restore.sh" ] || { echo "restore.sh missing"; exit 1; }
[ -f "$REPO_ROOT/scripts/livepicker.sh" ] || { echo "livepicker.sh missing (activate fixture)"; exit 1; }
for l in options utils state renderer preview; do
	[ -f "$REPO_ROOT/scripts/$l.sh" ] || { echo "INPUT dep $l.sh missing"; exit 1; }
done

SOCK="lp-t4-mock-$$"
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

# ---------- setup: a 3-pane driver window + a foreign session to link in ----------
tmux new-session -d -s driver -x 120 -y 40
tmux split-window -t driver        # pane 2
tmux split-window -t driver        # pane 3 -> non-trivial window_layout
tmux new-session -d -s foreign -x 120 -y 40
tmux send-keys -t foreign:0 "echo FOREIGN" Enter; sleep 0.2
# seed PRD §11 config (MUST survive restore — CORRECTION 2)
tmux set-option -g "@livepicker-key" "Space"
tmux set-option -g "@livepicker-fg" "#ffffff"
tmux set-option -g "@livepicker-type" "session"

# capture the EXACT pre-activation layout of the driver's active (3-pane) window
LAYOUT_BEFORE="$(tmux display-message -p -t '=driver' '#{window_layout}')"
echo "layout BEFORE activate: [$LAYOUT_BEFORE]"

# ---------- activate + nav (links foreign's window into driver) + restore cancel ----------
attach driver
bash "$REPO_ROOT/scripts/livepicker.sh"; echo "activate rc=$? (expect 0)"
# the livepicker table should now exist (activate T4.S1 built it)
KEYS_DURING="$(tmux list-keys -T livepicker 2>/dev/null | wc -l)"
echo "livepicker keys DURING activate: $KEYS_DURING (expect >0)"
# simulate nav (preview.sh links foreign) — run preview to mutate linked-id
bash "$REPO_ROOT/scripts/preview.sh" "foreign" 2>/dev/null; echo "preview rc=$?"
detach

# restore cancel — runs the REAL restore.sh (STEP 1-4 by siblings + T4 by THIS task)
attach driver
bash "$REPO_ROOT/scripts/restore.sh" cancel; rc=$?
detach
assert "restore.sh cancel exit 0" "$rc" "0"

# ---------- (A) layout byte-identical (work-item §5 MOCKING) ----------
LAYOUT_AFTER="$(tmux display-message -p -t '=driver' '#{window_layout}')"
echo "layout AFTER restore:  [$LAYOUT_AFTER]"
assert "(A) layout byte-identical before-vs-after" "$LAYOUT_BEFORE" "$LAYOUT_AFTER"

# ---------- (B) zero picker state (SCOPED — CORRECTION 2) ----------
ORIG_LEFT="$(tmux show-options -g 2>/dev/null | grep -c '@livepicker-orig-' || true)"
assert "(B1) no @livepicker-orig-* remain" "$ORIG_LEFT" "0"
MODE_AFTER="$(tmux show-option -gqv '@livepicker-mode' 2>/dev/null)"
LIST_AFTER="$(tmux show-option -gqv '@livepicker-list' 2>/dev/null)"
FILT_AFTER="$(tmux show-option -gqv '@livepicker-filter' 2>/dev/null)"
IDX_AFTER="$(tmux show-option -gqv '@livepicker-index' 2>/dev/null)"
LINK_AFTER="$(tmux show-option -gqv '@livepicker-linked-id' 2>/dev/null)"
assert "(B2) @livepicker-mode empty" "$MODE_AFTER" ""
assert "(B3) @livepicker-list empty" "$LIST_AFTER" ""
assert "(B4) @livepicker-filter empty" "$FILT_AFTER" ""
assert "(B5) @livepicker-index empty" "$IDX_AFTER" ""
assert "(B6) @livepicker-linked-id empty" "$LINK_AFTER" ""

# ---------- (C) the livepicker table is GONE ----------
tmux list-keys -T livepicker >/dev/null 2>&1; lk_rc=$?
assert "(C) list-keys -T livepicker rc=1 (table gone)" "$lk_rc" "1"

# ---------- (D) PRD §11 config PRESERVED (CORRECTION 2) ----------
assert "(D1) @livepicker-key preserved" "$(tmux show-option -gv '@livepicker-key')" "Space"
assert "(D2) @livepicker-fg preserved"  "$(tmux show-option -gv '@livepicker-fg')" "#ffffff"
assert "(D3) @livepicker-type preserved" "$(tmux show-option -gv '@livepicker-type')" "session"

printf '\n==== PASS=%d FAIL=%d ====\n' "$pass" "$fail"
[ "$fail" = "0" ]
# Expected: all PASS, 0 FAIL. Key proofs:
#  (A) #{window_layout} byte-identical before activate vs after restore-cancel.
#  (B1-B6) zero @livepicker-orig-* + the 5 runtime keys empty (SCOPED clearance).
#  (C) the livepicker table is gone (unbind-key -a -T livepicker removed all keys).
#  (D) PRD §11 config (@livepicker-key/fg/type) PRESERVED (CORRECTION 2 — clear_all_state
#      does NOT wipe user config).
```

### Level 2b: Idempotency + Edge-Case Variants

```bash
# Variant (E): EMPTY ORIG_LAYOUT -> select-layout skipped, no error, rest still runs.
#   (Simulate a failed-activate that left ORIG_LAYOUT unset; restore must not crash.)
SOCK2="lp-t4-edge-$$"
SHIM2="$(mktemp -d)"; printf '#!/usr/bin/env bash\nexec /usr/bin/tmux -L "%s" "$@"\n' "$SOCK2" > "$SHIM2/tmux"; chmod +x "$SHIM2/tmux"
trap 'PATH=/usr/bin:/bin:$PATH tmux -L "$SOCK2" kill-server 2>/dev/null; rm -rf "$SHIM2"' EXIT
PATH="$SHIM2:$PATH" tmux new-session -d -s demo -x 120 -y 40
PATH="$SHIM2:$PATH" tmux set-option -gu "@livepicker-orig-layout"   # EMPTY
PATH="$SHIM2:$PATH" tmux bind-key -T livepicker a run-shell "echo x"  # a stray key to unbind
TMUX="" script -qec "tmux -L $SOCK2 attach -t demo" /dev/null >/dev/null 2>&1 & AP=$!; sleep 0.5
PATH="$SHIM2:$PATH" bash "$REPO_ROOT/scripts/restore.sh" cancel; rcE=$?
kill "$AP" 2>/dev/null; wait "$AP" 2>/dev/null
[ "$rcE" = "0" ] && echo "ok   (E) empty-ORIG_LAYOUT restore exit 0 (select-layout skipped)" || echo "FAIL (E): rc=$rcE"
# the stray key was still unbound (unbind ran regardless of layout):
PATH="$SHIM2:$PATH" tmux list-keys -T livepicker >/dev/null 2>&1; lkE=$?
[ "$lkE" = "1" ] && echo "ok   (E) livepicker table still cleared (unbind independent of layout)" || echo "FAIL (E): table not cleared"

# Variant (F): double-restore -> second call is a no-op (unbind rc=1 guarded; idempotent).
#   (Re-run restore.sh on the already-clean state from the main mock; expect exit 0,
#    no error spew, table-still-gone.)
# (Run as a second `bash restore.sh cancel` after the main mock's first one; the
#  2>/dev/null || true on unbind-key absorbs the "table doesn't exist" rc=1.)
```

### Level 3: Integration Testing (System Validation)

```bash
# Live spot-check on an ISOLATED socket WITH an attached client — confirms the REAL
# restore.sh returns the driver window's pane layout to its pre-activate geometry
# after a full activate->nav->cancel cycle, clears picker state, and removes the
# livepicker table. Self-cleaning.
export LP_SOCK="lp-t4-live-$$"
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
T split-window -t demo
T split-window -t demo
T new-session -d -s foreign -x 120 -y 40
T set-option -g "@livepicker-key" "Space"; T set-option -g "@livepicker-fg" "#ffffff"
echo "BEFORE activate: layout=[$(T display-message -p -t '=demo' '#{window_layout}')]"
echo "                 livepicker keys: $(T list-keys -T livepicker 2>/dev/null | wc -l) (expect 0)"
TMUX="" script -qec "tmux -L $LP_SOCK attach -t demo" /dev/null >/dev/null 2>&1 &
AP=$!; sleep 0.5
PATH="$SHIM_DIR:$PATH" bash "$REPO_ROOT/scripts/livepicker.sh"; echo "activate rc=$? (expect 0)"
echo "DURING activate: livepicker keys: $(T list-keys -T livepicker 2>/dev/null | wc -l) (expect >0)"
PATH="$SHIM_DIR:$PATH" bash "$REPO_ROOT/scripts/restore.sh" cancel; echo "restore rc=$? (expect 0)"
kill "$AP" 2>/dev/null; wait "$AP" 2>/dev/null
echo "AFTER restore:  layout=[$(T display-message -p -t '=demo' '#{window_layout}')] (expect == BEFORE)"
echo "                livepicker keys: $(T list-keys -T livepicker 2>/dev/null | wc -l) (expect 0 / table gone)"
echo "                @livepicker-orig-* count: $(T show-options -g 2>/dev/null | grep -c '@livepicker-orig-' || true) (expect 0)"
echo "                @livepicker-key preserved: [$(T show-option -gv '@livepicker-key')] (expect Space)"
# Expected: AFTER restore layout == BEFORE; livepicker table gone; zero @livepicker-orig-*;
#   config (@livepicker-key) preserved.
```

### Level 4: Creative & Domain-Specific Validation

```bash
# Structural + byte-identical guarantees for the restore (PRD §15.21 "Restore"),
# runnable WITHOUT a live tmux server (pure code-structure assertions):
REPO_ROOT="$(pwd)"
# 1. select-layout is best-effort (guarded + non-empty guard):
grep -q '\[ -n "\$orig_layout" \] && tmux select-layout "\$orig_layout" 2>/dev/null || true' "$REPO_ROOT/scripts/restore.sh" \
  && echo "OK: select-layout best-effort + guarded" || echo "FAIL: select-layout not guarded"
# 2. CORRECTION 1: bulk unbind (NOT kill-key-table, NOT per-key loop):
grep -q 'unbind-key -a -T livepicker 2>/dev/null || true' "$REPO_ROOT/scripts/restore.sh" \
  && echo "OK: bulk unbind-key -a -T livepicker (CORRECTION 1)" || echo "FAIL: missing bulk unbind"
grep -q 'kill-key-table' "$REPO_ROOT/scripts/restore.sh" \
  && echo "FAIL: kill-key-table used (does not exist on 3.6b)" || echo "OK: no kill-key-table"
# 3. clear_all_state is CALLED (not re-implemented):
grep -q 'clear_all_state' "$REPO_ROOT/scripts/restore.sh" && echo "OK: calls clear_all_state" || echo "FAIL: missing clear_all_state"
# 4. clear_all_state is NOT broadened (no @livepicker-* wildcard that would wipe config):
grep -qE "set-option -gu '@livepicker-" "$REPO_ROOT/scripts/restore.sh" \
  && echo "WARN: broad @livepicker- clear in restore.sh (would wipe config — CORRECTION 2)" \
  || echo "OK: no broad @livepicker- clear (config preserved via clear_all_state)"
# 5. ORDER: select-layout BEFORE clear_all_state (FINDING 8):
awk '/select-layout "\$orig_layout"/{sl=NR} /clear_all_state/{ca=NR} END{if(sl>0&&ca>0&&sl<ca) print "OK: select-layout before clear_all_state (ORDER)"; else print "FAIL: ORDER"}' "$REPO_ROOT/scripts/restore.sh"
# 6. refresh-client -S is the LAST tmux call (final redraw):
grep -q 'refresh-client -S 2>/dev/null || true' "$REPO_ROOT/scripts/restore.sh" && echo "OK: refresh-client -S present" || echo "FAIL: missing refresh-client -S"
# 7. NO re-select-window in T4 (STEP 2 owns it):
[ "$(grep -c 'select-window' "$REPO_ROOT/scripts/restore.sh")" = "1" ] && echo "OK: exactly one select-window (STEP 2 only)" || echo "FAIL: select-window count != 1"

# Real-env gate (optional, post-P1.M6 when the picker is fully live end-to-end):
# on the REAL tubular server, activate (prefix key), navigate a few sessions, then
# cancel; confirm (a) the active window's pane geometry is unchanged, (b)
# `show-options -g | grep '@livepicker-orig-'` is empty, (c) `list-keys -T
# livepicker` returns "table doesn't exist", (d) `@livepicker-key`/`@livepicker-fg`
# are still set. This is the end-to-end proof that complements the socket mock.
```

## Final Validation Checklist

### Technical Validation

- [ ] `bash -n scripts/restore.sh` exits 0 with no output.
- [ ] `shellcheck scripts/restore.sh` reports 0 findings (no new disable; T4 adds
      no word-split on user input).
- [ ] No 4-space indents (`grep -Pn '^    '` is empty); tabs only.
- [ ] `scripts/restore.sh` is still executable (T1.S1 set +x; T4's edit preserves it).

### Feature Validation

- [ ] The `local` line includes `orig_layout` (appended after T3.S1's locals).
- [ ] The T4 seam comment block is REPLACED by STEP 5 + STEP 6 (the comment is
      gone; the restore calls are present).
- [ ] STEP 5: `orig_layout="$(get_state "$ORIG_LAYOUT" "")"` then
      `[ -n "$orig_layout" ] && tmux select-layout "$orig_layout" 2>/dev/null || true`.
- [ ] STEP 6a: `clear_all_state` called once (no re-implementation).
- [ ] STEP 6b: `tmux unbind-key -a -T livepicker 2>/dev/null || true` (BULK —
      CORRECTION 1; NOT kill-key-table).
- [ ] STEP 6c: `tmux refresh-client -S 2>/dev/null || true`.
- [ ] ORDER: select-layout (reads ORIG_LAYOUT) BEFORE clear_all_state (clears it).
- [ ] Mock (§2): (A) layout byte-identical; (B1-B6) zero @livepicker-orig-* + 5
      runtime keys empty; (C) livepicker table gone; (D) config (@livepicker-key/
      fg/type) preserved.
- [ ] Mock (§2b): (E) empty-ORIG_LAYOUT → select-layout skipped, restore still
      exits 0, unbind still runs; (F) double-restore idempotent.

### Code Quality Validation

- [ ] Follows existing codebase patterns (mirrors T1/T2/T3's `get_state "$ORIG_*"
      "<default>"` + `2>/dev/null || true` idiom; one-tab indent; clear_all_state
      called like the other state helpers).
- [ ] Surgical edit (only the `local` line append + the T4 seam; STEP 1/2/3/4/
      header/driver untouched).
- [ ] Anti-patterns avoided (no kill-key-table; no per-key unbind loop; no broad
      @livepicker-* clear; no re-select-window; no set -e; no re-touch of T1/T2/
      T3 seams).
- [ ] Dependencies properly managed (reads ORIG_LAYOUT; calls clear_all_state;
      mutates only layout/options/table/status-redraw).

### Documentation & Deployment

- [ ] Code is self-documenting (the STEP 5+6 block cites PRD §9 steps 5-6 / §15.21 /
      §16; explains CORRECTION 1 (kill-key-table absent → bulk unbind), CORRECTION 2
      (config preserved via clear_all_state), the best-effort select-layout guard,
      the ORDER constraint (read before clear), and the refresh-client -S redraw).
- [ ] Logs are informative but not verbose (T4 emits nothing on success).
- [ ] No new environment variables (T4 uses only @livepicker-orig-layout [activate
      STEP 2 save]).

---

## Anti-Patterns to Avoid

- ❌ Don't use `kill-key-table livepicker` — it does NOT exist on tmux 3.6b
  (`unknown command: kill-key-table`, verified — research FINDING 3). The keys
  REMAIN bound after the failed call. Use the BULK `tmux unbind-key -a -T
  livepicker` (FINDING 4), which atomically removes every key (rc=0 when keys
  exist; rc=1 "table doesn't exist" when empty → guard). This is CORRECTION 1.
- ❌ Don't use a per-key `list-keys -T livepicker | while read ... unbind-key -T
  livepicker "$key"` loop — it works but is ~169 calls, needs the same empty-table
  guard (`list-keys -T livepicker` rc=1 when empty), and risks a re-bind race.
  The bulk `-a` form is cleaner, atomic, and one call. (The work-item offered the
  loop as a fallback; the bulk form supersedes it.)
- ❌ Don't run `select-layout` WITHOUT the `2>/dev/null || true` guard AND the
  non-empty check — `select-layout` returns rc=1 on an invalid/vanished/EMPTY
  layout string (research FINDING 2). The work-item contract is explicit: "best-
  effort, do not block exit." Pattern: `[ -n "$orig_layout" ] && tmux
  select-layout "$orig_layout" 2>/dev/null || true`.
- ❌ Don't call `clear_all_state` BEFORE `select-layout` — `clear_all_state` CLEARS
  `@livepicker-orig-layout` (research FINDING 6 / FINDING 8). If it runs first,
  `orig_layout` would be empty and select-layout would no-op (or fail on the empty
  string). Read ORIG_LAYOUT + run select-layout FIRST, then clear. The ORDER is
  load-bearing.
- ❌ Don't broaden the state clearance — the work-item's literal "no @livepicker-*
  options remain" (`show-options -g | grep livepicker` empty) is TOO BROAD
  (CORRECTION 2). It would clear PRD §11 config (`@livepicker-key Space`,
  `@livepicker-fg #ffffff`, `@livepicker-type session`) — breaking the next
  activation (no @livepicker-key → plugin.tmux's guard refuses to bind) and the
  renderer colors. `clear_all_state` (state.sh CORRECTION A) clears ONLY the 5
  runtime keys + every `@livepicker-orig-*`, preserving config. T4 CALLS it
  unchanged. Do NOT add a `set-option -gu '@livepicker-*'` wildcard.
- ❌ Don't re-implement the option teardown — `clear_all_state` is ALREADY COMPLETE
  in state.sh (P1.M1.T3.S1). Calling it is the whole job for the options side.
  A hand-rolled `for k in ...; tmux set-option -gu "@livepicker-$k"` loop would
  either miss keys (if the list is incomplete) or wipe config (if too broad).
- ❌ Don't re-`select-window` in T4 — STEP 2 (T1.S1) already ran `select-window -t
  "$orig_window"` above the T4 seam (research FINDING 7). select-layout applies to
  the ACTIVE window, which STEP 2 made active. A redundant select-window would
  duplicate T1.S1's work and muddy the seam boundary. The work-item's first bullet
  ("select-window -t $ORIG_WINDOW (ensure target window is active)") is a NOTE
  about the prerequisite, NOT a new command for T4.
- ❌ Don't drop the `2>/dev/null || true` on `refresh-client -S` — with no client
  attached it rc=1 ("no current client"; research FINDING 5). Production always
  has a client (restore runs from a key press), but the MOCK + detached edges rc=1.
  Under a future `set -e` (or just for uniform safety) append it. It is the LAST
  call so the redraw reflects the FULLY restored state.
- ❌ Don't touch STEP 1 / STEP 2 / STEP 3 / STEP 4 / the header / the driver —
  T4.S1 is a surgical edit of the `local` line (append) + the T4 seam only.
  Re-touching T1/T2/T3's work muddies the seam boundaries and risks merge
  conflicts (T3.S1 lands in parallel).
- ❌ Don't skip validation because "it should work" — run the socket-shim mock (§2);
  the byte-identical layout assertion (A) is the PRD §15.21 proof, and the
  config-preserved assertion (D) is the CORRECTION 2 proof (the work-item's
  literal "no @livepicker-* options remain" would FALSE-FAIL D if followed
  literally — the mock uses the SCOPED grep).
