# PRP — P1.M5.T3.S1: restore.sh — restore status, status-format (-gu trap), key-table, renumber, hook

---

## Goal

**Feature Goal**: **MODIFY** `scripts/restore.sh` (created by P1.M5.T1.S1, STEP 3
landed in parallel by P1.M5.T2.S1 — both treated as CONTRACTS here) to fill the
**T3 seam** — PRD §9 restore **step 4**: restore `status`, every `status-format[n]`,
`renumber-windows`, `key-table`, and the `session-window-changed` hook to be
**byte-identical to pre-activation**. This is the matched teardown of the ACTIVATE
writes T3 (status grow) + T4.S1 (key-table switch) + T4.S2 (hook suppress) +
the STEP-2 save. The single surgical edit replaces the T3 seam comment block
(left by T1.S1 between STEP 3 and the T4 seam) with the real restore logic:
(1) call `state_status_format_restore` (the already-COMPLETE helper in state.sh —
TRAP 1), (2) restore `status` / `key-table` / `renumber-windows` from their
`ORIG_*` saved values, (3) replay the saved `session-window-changed` hook
**index-preserving** (TRAP 2) when `@livepicker-suppress-window-hook == on`.

**Deliverable**: A single in-place edit to `scripts/restore.sh` inside
`restore_main`: (a) extend the `local` declaration to add the T3 locals
(`r_status r_kt r_renumber r_hook hk_line hk_idx hk_cmd`); (b) replace the
T3 seam comment block with the STEP 4 logic (status-format restore call + the
four option restores + the index-preserving hook replay under the suppress
gate). No other file is touched. STEP 1 (unlink), STEP 2 (select-window), STEP 3
(keep/cancel switch), the T4 seam, and the driver are all left untouched.

**Success Definition**:
- `bash -n scripts/restore.sh` passes; `shellcheck scripts/restore.sh` is clean
  (0 findings; the existing file-level `# shellcheck disable=SC1091,SC2153` from
  T1.S1 still covers everything — T3's one intentional word-split is annotated
  `# shellcheck disable=SC2086`). Tabs only; `set -u`, NO `set -e`.
- **Byte-identical restore (work-item §5 MOCKING):** under the socket shim with
  an attached client, snapshot `show-options -g` + `show-hooks -g session-window-changed`
  BEFORE activate; run activate; run `restore.sh cancel`; assert the snapshot
  diffs to **nothing** — `status`, every `status-format[n]`, `renumber-windows`,
  `key-table`, and the `session-window-changed` hook (incl. `-b` + abs path) are
  restored to their exact pre-activate values. This is the core invariant
  (PRD §15.21 "Restore").
- **Two CONTRACT CORRECTIONS encoded (load-bearing):**
  1. `key-table` restore uses **`-g`** (`set-option -g key-table "$r_kt"`). The
     work-item's literal `set-option key-table "$r_kt"` (no `-g`) is WRONG — the
     no-`-g` form does NOT take effect on `show-option -gv` (verified; mirrors
     T4.S1 FINDING 3, which mandated `-g` on the activate switch).
  2. the hook replay is **index-preserving**:
     `set-hook -g "session-window-changed[$hk_idx]" "$hk_cmd"`. The work-item's
     literal index-less form (`set-hook -g session-window-changed "<cmd>"`) is
     WRONG for multi-index — it ALWAYS writes `[0]`, so iterating two saved lines
     clobbers the first. The index-preserving form is byte-identical for BOTH
     single-index (the real env) and multi-index (verified).
- **No off-limits work:** STEP 4 ONLY. NO re-touching of STEP 1/2/3 (T1/T2), NO
  `select-layout` / `clear_all_state` / `unbind-key` (T4). Those seams stay as
  comments.

## User Persona (if applicable)

**Target User**: None directly (internal teardown step 4 of 6). Transitively: the
end user who pressed cancel or confirm (PRD §3 stories 3–4). T3.S1 is what makes
the **cancel** story ("I press Escape ... everything is exactly as it was")
literally true at the global-option level: after cancel the status bar is back to
one line, the renderer line is gone, the key-table is `root` again, renumbering
behaves as before, and the user's `sync-window-focus.sh` hook is re-installed
exactly (with `-b` + the absolute path). And it makes the **keep** story clean:
after confirm, the only visible difference is the one session switch — every
global option is byte-identical to before.

**Use Case**: The user browsed sessions, then pressed confirm or cancel →
`input-handler.sh` (P1.M6) invokes `restore.sh <keep|cancel>`. STEP 1 (unlink)
+ STEP 2 (select-window) + STEP 3 (keep/cancel switch) ran first inside
`restore_main`. **T3.S1 (this task)** runs NEXT: it undoes the ACTIVATE global
mutations — restores the status-format array (clears the renderer line + resets
to defaults), restores the status line count, restores `key-table` to `root`,
restores `renumber-windows`, and replays the saved hook. After T3, the global
option surface is byte-identical to pre-activate; T4 (sibling) then restores
the layout + clears `@livepicker-*` state + unbinds the `livepicker` table.

**User Journey** (T3.S1 scope — the global options + hook return to their originals):
1. …STEP 1 unlinked the preview; STEP 2 re-selected ORIG_WINDOW; STEP 3 switched
   the client (cancel) or did nothing (keep).
2. **T3.S1 (this task):**
   - `state_status_format_restore` → `set-option -gu status-format` (clears the
     renderer line T3 installed + every index; tmux re-composes defaults) then
     replays the saved user indices (none in this env).
   - `set-option -g status "$ORIG_STATUS"` (line count back to `on`).
   - `set-option -g key-table "$ORIG_KEY_TABLE"` (back to `root`, **with `-g`**).
   - `set-option -g renumber-windows "$ORIG_RENUMBER"` (back to `on`).
   - if `@livepicker-suppress-window-hook == on`: replay every saved
     `session-window-changed[N] <cmd>` line **index-preserving**
     (`set-hook -g "session-window-changed[$N]" "$cmd"`); if nothing was saved,
     the loop is a no-op → the hook stays cleared (leave unset).
3. T4 (sibling subtask, seam-marked) finishes: `select-layout ORIG_LAYOUT`;
   `clear_all_state`; `unbind-key -T livepicker`.

**Pain Points Addressed**:
- (a) **Stray renderer line / grown status after cancel.** Without the
  status-format restore, the picker's `#(renderer.sh)` line would persist at
  `status-format[0]` and the status bar would stay 2 lines tall after exit —
  a visible, permanent corruption of the user's status line. T3.S1's
  `state_status_format_restore` (the `-gu` reset) clears it and re-composes the
  defaults (TRAP 1 — never replay captured default strings, which would fight
  tubular on reload).
- (b) **Stuck in the `livepicker` key-table.** If `key-table` were left at
  `livepicker`, EVERY subsequent keypress would consult only that table (which
  T4 will unbind) → the user's tmux becomes unresponsive. T3.S1 restores
  `key-table` to `root` (the saved `ORIG_KEY_TABLE`), with `-g` (the no-`-g`
  form silently fails — FINDING 3).
- (c) **Lost focus-sync hook.** If the `session-window-changed` hook were not
  replayed, the user's `sync-window-focus.sh` (which tracks pane focus across
  window changes) would silently stop running for the rest of the session — a
  subtle, hard-to-diagnose regression. T3.S1 replays the saved hook **exactly**,
  `-b` flag and absolute path intact, index-preserving (FINDING 5).

## Why

- **PRD §9 "State saved and restored"** is the controlling spec. Restore step 4:
  "Restore `status`, every `status-format[n]`, `renumber-windows`, `key-table`,
  and the `session-window-changed` hook." T3.S1 owns exactly this step.
- **PRD §16 "Implementation risks and notes" / "Hook suppression scope":**
  "Clearing `session-window-changed` is global for the duration. Restore it
  exactly on exit, including the `-b` flag if present." T3.S1 replays the saved
  hook verbatim, `-b` + index preserved (FINDING 5).
- **system_context §4 TRAP 1 + TRAP 2:**
  - TRAP 1: status-format restore MUST be `set-option -gu status-format` (unset
    all → tmux re-composes defaults), NOT literal replay of captured default
    strings. `state_status_format_restore` already does this.
  - TRAP 2: the hook is array-indexed with `-b`; restore re-runs each saved
    `set-hook` preserving `-b`. The index must ALSO be preserved (FINDING 5
    correction to the work-item).
- **Boundary respect.** T3.S1 touches ONLY: the status-format array (via
  `state_status_format_restore`), the `status` / `key-table` / `renumber-windows`
  options, and the `session-window-changed` hook. It does NOT: re-touch
  unlink/select-window/switch (STEP 1/2/3), restore the layout / clear state /
  unbind keys (T4), run a preview, or call `link-window`/`capture-pane`.
- **Scope cohesion.** T3.S1 is the restore counterpart of three ACTIVATE writers:
  T3 (status grow) ↔ T3.S1 status-format+status restore; T4.S1 (key-table switch
  + renumber is untouched-by-activate, just restored for symmetry) ↔ T3.S1
  key-table restore; T4.S2 (hook suppress) ↔ T3.S1 hook replay. The shared
  contract is the `@livepicker-orig-*` keys activate STEP 2 wrote and T3.S1 reads.

## What

A surgical edit to the existing `scripts/restore.sh` (the file T1.S1 created,
STEP 3 landed by T2.S1). Two changes, both inside `restore_main`:

1. **Extend the `local` declaration** (currently
   `local linked_id orig_window current_session orig_session mode`) to add the
   T3 locals: `local linked_id orig_window current_session orig_session mode r_status r_kt r_renumber r_hook hk_line hk_idx hk_cmd`.
2. **Replace the T3 seam comment block** (the multi-line
   `# --- T3 (P1.M5.T3.S1): restore status / status-format / ...` block T1.S1
   left between STEP 3 and the T4 seam) with the STEP 4 logic:
   - `state_status_format_restore` (one call — the status-format array restore).
   - read `r_status` / `r_kt` / `r_renumber` via `get_state "$ORIG_*" "<default>"`;
     `tmux set-option -g status "$r_status"` / `key-table "$r_kt"` (**`-g`**) /
     `renumber-windows "$r_renumber"`.
   - `if [ "$(opt_suppress_window_hook)" = "on" ]; then` read `r_hook` via
     `get_state "$ORIG_HOOK" ""`; iterate each line; for each real
     `session-window-changed[N] <cmd>` line, extract the index + cmd and
     `tmux set-hook -g "session-window-changed[$hk_idx]" "$hk_cmd"` (index-preserving).
     Bare-name / blank lines are skipped (nothing saved → hook stays cleared).

The header doc-comment's seam map (lines describing "4. Restore `status`, every
`status-format[n]`, `renumber-windows`, `key-table`, and the ... hook. [T3 seam]")
already describes T3; T3.S1 may leave the header as-is (it remains accurate) —
no header edit is required. (Optional: change `[T3 seam]` to `[T3]` to mark it
done; not required for success.)

### Success Criteria

- [ ] `scripts/restore.sh` still passes `bash -n` + `shellcheck` (0 findings; the
      one intentional hook-loop is `# shellcheck disable=SC2086`-annotated if it
      word-splits — but the loop reads via heredoc, so no SC2086 is strictly
      needed; declare locals only).
- [ ] The `restore_main` `local` line now includes `r_status r_kt r_renumber r_hook
      hk_line hk_idx hk_cmd`.
- [ ] The T3 seam comment block is REPLACED by STEP 4 logic (the comment block is
      gone; the restore calls are present).
- [ ] status-format: `state_status_format_restore` is called (the helper does the
      `-gu` reset + saved-index replay). T3.S1 adds NO other status-format logic.
- [ ] status: `tmux set-option -g status "$r_status"` (with `-g`; `r_status` from
      `get_state "$ORIG_STATUS" "on"`).
- [ ] key-table: `tmux set-option -g key-table "$r_kt"` (**`-g`** — CORRECTION;
      `r_kt` from `get_state "$ORIG_KEY_TABLE" "root"`).
- [ ] renumber-windows: `tmux set-option -g renumber-windows "$r_renumber"` (with
      `-g`; `r_renumber` from `get_state "$ORIG_RENUMBER" "on"`).
- [ ] hook: under `if [ "$(opt_suppress_window_hook)" = "on" ]`, replay each saved
      `session-window-changed[N] <cmd>` line via
      `tmux set-hook -g "session-window-changed[$hk_idx]" "$hk_cmd"`
      (**index-preserving** — CORRECTION). Bare-name lines skipped.
- [ ] Tabs only (`grep -Pn '^    '` empty); `set -u`, NO `set -e`.
- [ ] NO off-limits work: STEP 1 (unlink), STEP 2 (select-window), STEP 3
      (keep/cancel switch) unchanged; the T4 seam comment still present and
      unchanged; the driver unchanged.
- [ ] Mock (work-item §5): snapshot `show-options -g` + `show-hooks -g
      session-window-changed` before activate; activate; `restore.sh cancel`;
      assert the snapshot diffs to NOTHING. Plus the multi-index hook variant
      (seed `[0]`+`[1]`) restores byte-identically. See Validation Loop §2.

## All Needed Context

### Context Completeness Check

_Pass_: A developer who has never seen this repo can implement T3.S1 from
(a) the verbatim STEP 4 block in "Implementation Patterns & Key Details" (complete,
ready to paste in place of the T3 seam comment), (b) the 10 live-verified findings
in `research/restore_status_keys_hook_findings.md` — most critically **FINDING 3**
(key-table restore MUST use `-g`; the work-item's no-`-g` literal does not take
effect — verified), **FINDING 5** (hook replay MUST be index-preserving; the
work-item's index-less literal overwrites `[0]` on multi-index — verified broken;
the index-preserving form is byte-identical for both single and multi), **FINDING
1** (`state_status_format_restore` is ALREADY COMPLETE in state.sh — just call it;
the `-gu` reset is byte-identical), and **FINDING 7** (the replay is GATED on
`@livepicker-suppress-window-hook == on`, mirroring activate T4.S2), and (c) the
socket-shim mock that snapshots before-activate, runs activate, runs
`restore.sh cancel`, and diffs the after-state to nothing. The INPUT dependencies
(`state.sh` ORIG_*/get_state/state_status_format_restore, `options.sh`
opt_suppress_window_hook, the `restore.sh` file with the T3 seam from T1.S1 +
STEP 3 from T2.S1) are COMPLETE/present.

### Documentation & References

```yaml
# MUST READ — the HOST FILE (the file this task edits). Created by P1.M5.T1.S1;
#   STEP 3 landed by P1.M5.T2.S1 (parallel; treated as CONTRACTS).
- file: scripts/restore.sh
  why: contains restore_main() with STEP 1 (unlink) + STEP 2 (select-window) +
       STEP 3 (keep/cancel switch) + the T3 seam comment block (the multi-line
       "# --- T3 (P1.M5.T3.S1): restore status / status-format / key-table /
       renumber-windows / session-window-changed hook (insert here) ---" + its
       trailing 3-line sub-comment, sitting between STEP 3 and the T4 seam) that
       T3.S1 REPLACES, plus the T4 seam. T3.S1 also extends the
       `local linked_id orig_window current_session orig_session mode` line to
       add `r_status r_kt r_renumber r_hook hk_line hk_idx hk_cmd`. The file
       already sources the lib trio and already has
       `# shellcheck disable=SC1091,SC2153`.
  pattern: STEP 1/2/3 use `2>/dev/null || true` on fail-possible tmux calls;
           `get_state "$ORIG_*" "<default>"` for state reads; ONE tab indent.
           T3's option restores follow the SAME get_state idiom; the hook replay
           calls bare `tmux set-hook` (no utils helper for set-hook — clear_all_state
           also calls tmux set-option -gu directly).
  critical: T3.S1 is a SURGICAL EDIT — touch ONLY the `local` line and the T3 seam
            block. Do NOT touch STEP 1, STEP 2, STEP 3, the T4 seam, or the driver.

# MUST READ — INPUT dependency: state.sh (ORIG_* / get_state / state_status_format_restore). COMPLETE.
- file: scripts/state.sh
  why: (1) state_status_format_restore() — ALREADY COMPLETE; does `tmux_unset_opt
       status-format` (= set-option -gu, TRAP 1) then replays saved user indices
       from ORIG_STATUS_FORMAT_INDICES (empty in this env). T3.S1 CALLS this.
       (2) readonly ORIG_STATUS, ORIG_KEY_TABLE, ORIG_RENUMBER, ORIG_HOOK constants
       (the saved-state CONTRACT keys activate wrote; T3.S1 reads). (3) get_state
       (thin accessor over tmux show-option -gqv; ${2:-} default is safe under set -u).
  critical: ORIG_HOOK holds the FULL raw show-hooks output (multi-line, one
            "session-window-changed[N] <cmd>" per index; or the bare
            "session-window-changed" when none was set). T3.S1 parses it line-by-line.
            state_status_format_restore owns the status-format array ENTIRELY;
            T3.S1 adds no other status-format logic.

# MUST READ — INPUT dependency: utils.sh (tmux_set_opt / tmux_get_opt). COMPLETE.
- file: scripts/utils.sh
  why: tmux_set_opt(name,val) -> set-option -g name val; tmux_get_opt(name,default)
       -> show-option -gqv. T3.S1 MAY use tmux_set_opt for the status/key-table/
       renumber restores (equivalent to direct `tmux set-option -g`), OR call
       `tmux set-option -g` directly (house style permits both — clear_all_state
       calls tmux set-option -gu directly). There is NO tmux_set_hook helper; the
       hook replay calls bare `tmux set-hook`.
  critical: tmux_unset_opt status-format (the TRAP-1 reset) is INSIDE
            state_status_format_restore; T3.S1 must NOT call tmux_unset_opt itself.

# MUST READ — INPUT dependency: options.sh (the suppress gate accessor). COMPLETE.
- file: scripts/options.sh
  why: opt_suppress_window_hook() -> get_opt "@livepicker-suppress-window-hook" "on"
       (PRD §11 default "on"; bool on/off). T3.S1 reads it via
       `if [ "$(opt_suppress_window_hook)" = "on" ]; then` — the SAME idiom activate
       T4.S2 used to CLEAR the hook. Under the gate, replay; otherwise leave the
       hook untouched (activate didn't clear it, so it's already correct).
  critical: returns EXACTLY "on" or "off". The gate compares literally to "on"
            (mirrors activate T4.S2 + the guard at the top of activate_main).

# MUST READ — the SAVE side (what ORIG_* contains — the input contract).
- docfile: plan/001_fd5d622d3939/P1M4T1S1/PRP.md
  why: activate STEP 2 wrote ORIG_STATUS (the raw `show-option -gqv status` value,
       e.g. "on"), ORIG_KEY_TABLE ("root"), ORIG_RENUMBER ("on"), ORIG_HOOK (the
       FULL `tmux_get_hook session-window-changed` output), and the status-format
       keys (via state_status_format_save — empty user-index list in this env).
       T3.S1 reads these back. The save used `tmux_save_opt <name> <name>` for
       key-table/status/renumber (GLOBAL reads), so restore MUST use `-g`.
  section: "STEP 2 save" (the ORIG_* captures), "STATE WRITES".

# MUST READ — the matched ACTIVATE writer T3 (status grow).
- docfile: plan/001_fd5d622d3939/P1M4T3S1/PRP.md
  why: T3 grew the status bar (set status-format[IDX]=#(renderer.sh); set status
       to the normalized count). T3.S1 undoes it: state_status_format_restore does
       set-option -gu status-format (clears the renderer line + every index), then
       set-option -g status "$ORIG_STATUS" (count back). NOTE: the `case`
       normalization is GROW-ONLY (T3); restore replays the raw saved status string
       directly (no case needed).
  section: "Implementation Patterns & Key Details" (the status grow block).

# MUST READ — the matched ACTIVATE writer T4.S1 (key-table switch). CORRECTION SOURCE.
- docfile: plan/001_fd5d622d3939/P1M4T4S1/PRP.md
  why: T4.S1 switched key-table via `tmux set-option -g key-table livepicker`
       (WITH -g; FINDING 3 — the no-g form does NOT take effect on show-option -gv).
       T3.S1's restore MUST also use -g to be the matched pair. This is the basis
       for CORRECTION 1 (the work-item's literal `set-option key-table` omitted -g).
  section: "FINDING 3" (key-table -g mandatory).

# MUST READ — the matched ACTIVATE writer T4.S2 (hook suppress). GATE SOURCE.
- docfile: plan/001_fd5d622d3939/P1M4T4S2/PRP.md
  why: T4.S2 cleared the LIVE hook under `if [ "$(opt_suppress_window_hook)" = "on" ]`.
       T3.S1 replays the SAVED hook under the SAME gate. When off, neither clears
       nor replays (the hook is untouched). FINDING 1 (set-hook -gu clears [0]) +
       FINDING 2 (show-hooks always rc=0; "is set?" = grep '[') inform the mock.
  section: "Implementation Patterns & Key Details" (the suppress gate block).

# MUST READ — the empirical ground-truth for THIS task (10 live-verified findings).
- docfile: plan/001_fd5d622d3939/P1M5T3S1/research/restore_status_keys_hook_findings.md
  why: FINDING 1 (state_status_format_restore ALREADY COMPLETE; -gu byte-identical);
       FINDING 2 (status round-trips); FINDING 3 (LOAD-BEARING: key-table MUST use
       -g; no-g does not take effect); FINDING 4 (renumber round-trips); FINDING 5
       (LOAD-BEARING: hook replay MUST be index-preserving; the index-less form
       overwrites [0] on multi-index — verified broken; index-preserving is
       byte-identical for single AND multi); FINDING 6 (bare-name branch skips);
       FINDING 7 (gate on suppress==on); FINDING 8 (saved hook is multi-line;
       iterate); FINDING 10 (house style: set -u, tabs, local).
  critical: Read BEFORE writing the block. FINDINGS 3 + 5 are the two CORRECTIONS
            to the work-item's literal text (both are correctness showstoppers if
            the literal text is followed).

# MUST READ — the PRD sections selected for this work item.
- docfile: PRD.md
  why: §9 "State saved and restored" (restore step 4: status, every status-format[n],
       renumber-windows, key-table, the hook); §10 (status-line setup — the grow T3
       undoes); §16 "Implementation risks and notes" (Hook suppression scope: restore
       exactly on exit, incl. the -b flag; Window addressing); §14 "Pollution and
       compatibility analysis" (cancel: zero switch-client to a different session;
       restore composes with siblings because it restores global options).
  section: "§9 State saved and restored", "§10 Status-line setup", "§14 Pollution
           and compatibility analysis", "§16 Implementation risks and notes"

# MUST READ — system ground-truth (the two traps + live values + shell style).
- docfile: plan/001_fd5d622d3939/architecture/system_context.md
  why: §2 (live values: status=on, key-table=root, renumber-windows=on, the exact
       session-window-changed[0] hook line with -b + abs path); §4 TRAP 1
       (status-format restore MUST be -gu, not literal replay) + TRAP 2 (hook is
       array-indexed with -b; restore re-running each saved set-hook preserving -b);
       §9 shell style (set -u only NO -e, tabs, quote everything, || true on
       fail-possible tmux calls).
  section: "§2 Verified environment", "§4 Two environment-specific traps", "§9 Shell style"

# MUST READ — primitive verification (hook semantics + status-format + key-table).
- docfile: plan/001_fd5d622d3939/architecture/tmux_primitives.md
  why: §4 "set-hook / session-window-changed / client-session-changed" (set-hook -g
       global; the -b flag; restore preserves -b); §3 "status-format[n], #(),
       refresh-client -S" (the -gu reset re-composes defaults; the matched pair
       with the grow); §2 "key-table / bind-key -T fallthrough" (set via set-option
       key-table -g).
  section: "§4 set-hook / session-window-changed / client-session-changed",
           "§3 status-format[n]", "§2 key-table"

# MUST READ — the T1.S1 PRP (the CONTRACT for the host file's base + STEP 1/2).
- docfile: plan/001_fd5d622d3939/P1M5T1S1/PRP.md
  why: defines scripts/restore.sh's skeleton, STEP 1, STEP 2, and the exact T3/T4
       seam comments. T3.S1 assumes this file exists as specified.

# REFERENCE — the sibling PRPs that share this file (seam contract).
- docfile: plan/001_fd5d622d3939/P1M5T2S1/PRP.md
  why: T2 owns restore step 3 (keep/cancel switch). Its block sits ABOVE the T3
       seam. T3 must leave that block intact and insert at the T3 seam AFTER it.
- docfile: plan/001_fd5d622d3939/P1M5T4S1/PRP.md
  why: (PLANNED, not yet written) T4 owns restore steps 5-6 (select-layout +
       clear_all_state + unbind-key -T livepicker). Inserts at the T4 seam AFTER
       T3. T3 must leave that seam intact.
```

### Current Codebase tree

```bash
tmux-livepicker/
  PRD.md
  plugin.tmux                 # COMPLETE. Unchanged.
  plan/001_fd5d622d3939/{architecture/*.md, tasks.json, prd_snapshot.md, prd_index.txt}
  plan/001_fd5d622d3939/P1M5T1S1/{PRP.md, research/restore_unlink_select_findings.md}  # HOST FILE creator (STEP 1+2)
  plan/001_fd5d622d3939/P1M5T2S1/{PRP.md, research/restore_keep_cancel_findings.md}     # STEP 3 (parallel)
  plan/001_fd5d622d3939/P1M5T3S1/{PRP.md, research/restore_status_keys_hook_findings.md}  # THIS
  scripts/
    options.sh   # COMPLETE. Unchanged. (opt_suppress_window_hook — INPUT dep.)
    utils.sh     # COMPLETE. Unchanged.
    state.sh     # COMPLETE — ORIG_*/get_state/state_status_format_restore (INPUT deps). Unchanged.
    renderer.sh  # COMPLETE. Unchanged.
    preview.sh   # COMPLETE (P1.M3). Unchanged.
    livepicker.sh   # COMPLETE (P1.M4). Unchanged.
    restore.sh   # CREATED by P1.M5.T1.S1 (STEP 1+2 + T3/T4 seams); STEP 3 landed by T2.S1 (parallel).
                 # THIS task (T3.S1) EDITS it: extend `local` line + replace the T3 seam with STEP 4.
  .gitignore
  # NOTE: NO test harness (P1.M7); NO input-handler.sh yet (P1.M6). Validate via the throwaway
  #       socket-shim mock (MUST keep an attached client + snapshot before-vs-after diff).
  # The real session-window-changed hook on the LIVE server is
  #   session-window-changed[0] run-shell -b /home/dustin/.config/tmux/scripts/sync-window-focus.sh
  # (system_context §2). The mock seeds this (or a multi-index variant) on the ISOLATED socket.
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
                  #   (1) `local ... r_status r_kt r_renumber r_hook hk_line hk_idx hk_cmd`
                  #   (2) T3 seam comment block REPLACED by STEP 4:
                  #         state_status_format_restore
                  #         r_status=$(get_state "$ORIG_STATUS" "on");     tmux set-option -g status "$r_status"
                  #         r_kt=$(get_state "$ORIG_KEY_TABLE" "root");     tmux set-option -g key-table "$r_kt"      # -g (CORRECTION)
                  #         r_renumber=$(get_state "$ORIG_RENUMBER" "on"); tmux set-option -g renumber-windows "$r_renumber"
                  #         if [ "$(opt_suppress_window_hook)" = "on" ]; then
                  #             r_hook=$(get_state "$ORIG_HOOK" "")
                  #             while IFS= read -r hk_line; do
                  #                 case "$hk_line" in "session-window-changed"|"" ) continue ;; esac
                  #                 hk_idx=$(... sed extract N ...)
                  #                 hk_cmd=${hk_line#session-window-changed\[*\] }
                  #                 [ -n "$hk_idx" ] && tmux set-hook -g "session-window-changed[$hk_idx]" "$hk_cmd"  # index-preserving (CORRECTION)
                  #             done <<< "$r_hook"
                  #         fi
                  # After T3.S1: every global option + the hook are byte-identical to pre-activate.
                  # STEP 1/2/3/T4 seam/driver: UNCHANGED.
```

### Known Gotchas of our codebase & Library Quirks

```bash
# CRITICAL (research FINDING 3 — CORRECTION to the work-item): key-table restore
#   MUST use -g:
#     tmux set-option -g key-table "$r_kt"        # CORRECT (matched pair with activate T4.S1)
#     tmux set-option    key-table "$r_kt"        # WRONG — does not take effect on show-option -gv
#   The work-item's literal `set-option key-table "$ORIG_KEY_TABLE"` (no -g) is
#   INCORRECT. Verified on 3.6b: no-g leaves show-option -gv reading the old value.
#   Activate T4.S1 FINDING 3 mandated -g on the switch; restore must mirror it.

# CRITICAL (research FINDING 5 — CORRECTION to the work-item): the hook replay MUST
#   preserve the index:
#     tmux set-hook -g "session-window-changed[$hk_idx]" "$hk_cmd"   # CORRECT
#     tmux set-hook -g  session-window-changed            "$hk_cmd"   # WRONG (work-item literal)
#   The index-less form ALWAYS writes [0]; iterating two saved lines clobbers the
#   first. Verified: multi-index [0]+[1] → index-less yields only [0]=second-cmd
#   (NOT byte-identical); index-preserving yields both lines byte-identical. The
#   real env has a single [0] line (so the literal form happens to work there),
#   but the index-preserving form is correct for BOTH and is what the PRP encodes.

# CRITICAL (research FINDING 1): state_status_format_restore() is ALREADY COMPLETE
#   in state.sh — T3.S1 CALLS it; it does NOT re-implement the -gu reset. The
#   helper does `tmux_unset_opt status-format` (= set-option -gu status-format,
#   TRAP 1) then replays saved user indices. Do NOT call tmux_unset_opt yourself;
#   do NOT capture/replay the default [0,1,2] strings (TRAP 1: fragile, fights tubular).

# CRITICAL (research FINDING 7): the hook replay is GATED on
#   @livepicker-suppress-window-hook == "on" — the SAME gate activate T4.S2 used to
#   CLEAR the hook. Under the gate, replay the saved hook; otherwise leave the live
#   hook untouched (activate did not clear it, so it is already the user's original).
#   Do NOT replay unconditionally (a needless set-hook when off).

# CRITICAL (research FINDING 6): the saved ORIG_HOOK may be the BARE hook name
#   "session-window-changed" (when no hook was set at save time). The replay loop's
#   `case "$hk_line" in "session-window-changed"|"" ) continue ;; esac` SKIPS it →
#   no set-hook fires → the live hook stays cleared (which equals "leave unset"). No
#   explicit `set-hook -gu` is required before replay (activate already cleared it
#   under the suppress gate; the pre-replay state is "cleared" by construction).

# CRITICAL (research FINDING 8): the saved hook is MULTI-LINE (one
#   "session-window-changed[N] <cmd>" per index; tmux preserves newlines in
#   @-options). Iterate EVERY line via `while IFS= read -r hk_line; do ... done <<<
#   "$r_hook"` (heredoc <<< form keeps the loop in THIS shell so `hk_idx`/`hk_cmd`
#   accumulate correctly under set -u). Do NOT assume a single line.

# GOTCHA (research FINDING 2): status restore replays the RAW saved status string
#   directly (`set-option -g status "$r_status"`, where r_status="on"). NO `case`
#   normalization is needed on RESTORE — the `case` (T3 FINDING 1) was GROW-ONLY
#   (to avoid the $((on+1)) crash); restore just writes the saved value back.

# GOTCHA: `set -u` is in effect. Every variable is assigned first (r_status/r_kt/
#   r_renumber/r_hook via get_state with a default; hk_line/hk_idx/hk_cmd inside the
#   loop before use). get_state's ${2:-} default makes the read safe even when the
#   ORIG_* key is unset.

# GOTCHA: the index extraction `printf '%s\n' "$hk_line" | sed -n
#   's/^session-window-changed\[\([0-9]\+\)\].*/\1/p'` returns "" for a bare-name
#   line (no match) → the `[ -z "$hk_idx" ] && continue` guard skips it. Verified.

# GOTCHA: the cmd recovery `${hk_line#session-window-changed\[*\] }` (parameter
#   expansion) strips the "session-window-changed[N] " prefix and preserves the rest
#   verbatim, INCLUDING -b, the absolute path, and any embedded spaces/quotes. Pass
#   it to set-hook as ONE double-quoted arg: "$hk_cmd". Verified.

# GOTCHA (research FINDING 9): there is NO tmux_set_hook helper in utils.sh. The
#   hook replay calls bare `tmux set-hook` directly (mirrors clear_all_state, which
#   calls `tmux set-option -gu` directly). The status/key-table/renumber restores
#   may use tmux_set_opt OR direct `tmux set-option -g` — both equivalent.

# GOTCHA: this task is a SURGICAL EDIT to an EXISTING file. It REPLACES the T3 seam
#   comment block and EXTENDS the `local` line. It does NOT create a file, does NOT
#   touch STEP 1/2/3/T4/driver. Preserve the one-tab indent of restore_main's body.

# CRITICAL: NO `set -e`, NO `set -o pipefail` (house style; system_context §9).
#   `tmux set-option -g status/key-table/renumber` and `tmux set-hook` all succeed
#   on valid args (rc=0), but a future hook-arg edge or a vanished session could
#   return non-zero; under set -e that would abort a half-restored teardown.
#   The `set-hook` calls inside the loop may append `2>/dev/null || true` for
#   uniform safety (harmless; matches house style).

# STYLE (system_context §9): indent with TABS. Verify with `grep -Pn '^    ' scripts/restore.sh`
#   (expect empty). shfmt is NOT installed. `local` for ALL function locals.
```

## Implementation Blueprint

### Data models and structure

No new data model. T3.S1 adds function-locals to `restore_main`:
- `r_status`, `r_kt`, `r_renumber` — read from `ORIG_STATUS` / `ORIG_KEY_TABLE` /
  `ORIG_RENUMBER` via `get_state` (with defensive defaults `"on"`/`"root"`/`"on"`).
- `r_hook` — read from `ORIG_HOOK` via `get_state "$ORIG_HOOK" ""` (the full
  multi-line saved show-hooks output).
- `hk_line`, `hk_idx`, `hk_cmd` — the hook-replay loop variables (per saved line).

The **read set** is the saved-state contract (`ORIG_*`) + the suppress option.
The **write set** is the `status-format` array (via the helper), the `status` /
`key-table` / `renumber-windows` options, and the `session-window-changed` hook
indices. No new options, no new state keys, no new files.

### Implementation Tasks (ordered by dependencies)

```yaml
Task 1: EDIT scripts/restore.sh — extend the `local` line + replace the T3 seam with STEP 4
  - FILE: ./scripts/restore.sh  (EXISTING; created by P1.M5.T1.S1; STEP 3 by T2.S1).
  - EDIT 1: change
            `	local linked_id orig_window current_session orig_session mode`
            to
            `	local linked_id orig_window current_session orig_session mode r_status r_kt r_renumber r_hook hk_line hk_idx hk_cmd`
            (adds the 7 T3 locals; preserves T1.S1's three + T2.S1's two).
  - EDIT 2: REPLACE the T3 seam comment block (the multi-line block:
            "# --- T3 (P1.M5.T3.S1): restore status / status-format / key-table /
             renumber-windows / session-window-changed hook (insert here) ---"
            + its trailing 3-line sub-comment "# PRD §9 restore step 4. ...
             (TRAP 2: preserve -b).")
            with the STEP 4 block from "Implementation Patterns & Key Details" below
            (status-format restore call + 3 option restores + the index-preserving
            hook replay under the suppress gate).
  - DO NOT touch: STEP 1 (unlink block), STEP 2 (select-window block), STEP 3
            (keep/cancel switch block), the T4 seam, the header doc, the source trio,
            the driver. (The header's seam-map line "4. Restore status, every
            status-format[n], ... [T3 seam]" may optionally be updated to "[T3]" —
            NOT required.)
  - PRESERVE: one-tab indent of restore_main's body; the file-level
            `# shellcheck disable=SC1091,SC2153`; `set -u`; NO `set -e`.

Task 2: VERIFY house style + no off-limits work
  - RUN: bash -n scripts/restore.sh            (expect exit 0, no output)
  - RUN: shellcheck scripts/restore.sh         (expect 0 findings; no new disable)
  - RUN: grep -Pn '^    ' scripts/restore.sh   (expect empty — tabs only)
  - RUN: grep -n 'set -e\|set -o pipefail' scripts/restore.sh  (expect empty)
  - EXPECT: `state_status_format_restore` called once; `set-option -g status` /
    `set-option -g key-table` / `set-option -g renumber-windows` each present once
    (all WITH -g); the hook replay under `if [ "$(opt_suppress_window_hook)" = "on" ]`
    using the index-preserving `set-hook -g "session-window-changed[$hk_idx]"`
    form; STEP 1's unlink + STEP 2's select-window + STEP 3's switch unchanged; the
    T4 seam comment still present.

Task 3: VALIDATE (Level 1 syntax/lint + Level 2 socket-shim byte-identical mock:
        snapshot before activate; activate; restore.sh cancel; diff to nothing.
        Plus the multi-index hook variant.)
  - RUN the socket-shim mock (Validation Loop §2). Self-cleaning, isolated socket,
    attached client, real hook seeded. Runs the REAL restore.sh with argv 'cancel'.
```

### Implementation Patterns & Key Details

The complete, ready-to-paste STEP 4 block (the implementer replaces the T3 seam
comment block with this; indent is ONE tab to match restore_main's body):

```bash
	# --- STEP 4 (PRD §9 restore step 4): restore status / status-format /
	#     key-table / renumber-windows / session-window-changed hook ---
	# The matched teardown of ACTIVATE T3 (status grow) + T4.S1 (key-table switch)
	# + T4.S2 (hook suppress) + the STEP-2 save. Goal: byte-identical to
	# pre-activate (assertable by diffing show-options/show-hooks before vs after).
	#
	# status-format: TRAP 1 (system_context §4). Call the ALREADY-COMPLETE helper
	#   in state.sh — it does `set-option -gu status-format` (clears EVERY index,
	#   incl. the renderer line T3 installed, and tmux re-composes the [0,1,2]
	#   defaults) then replays the saved user-set indices (>=3; EMPTY in this env).
	#   NEVER replay captured default strings (fragile, fights tubular).
	state_status_format_restore
	# status: replay the RAW saved line-count value (e.g. "on"). NO case
	#   normalization on restore (that was T3 grow-only, to dodge the $((on+1))
	#   crash). -g required (T3's grow used -g; matched pair).
	r_status="$(get_state "$ORIG_STATUS" "on")"
	tmux set-option -g status "$r_status"
	# key-table: CORRECTION (research FINDING 3) — MUST use -g. The no-g form does
	#   NOT take effect on show-option -gv (verified; mirrors activate T4.S1
	#   FINDING 3, which mandated -g on the switch). Default "root" (system_context §2).
	r_kt="$(get_state "$ORIG_KEY_TABLE" "root")"
	tmux set-option -g key-table "$r_kt"
	# renumber-windows: round-trip the saved value (e.g. "on"). -g (matched pair).
	r_renumber="$(get_state "$ORIG_RENUMBER" "on")"
	tmux set-option -g renumber-windows "$r_renumber"
	# session-window-changed hook: TRAP 2 (system_context §4) + the index-
	#   preserving CORRECTION (research FINDING 5). GATED on the SAME option as
	#   activate T4.S2's clear (mirror symmetry). Under the gate: replay every
	#   saved `session-window-changed[N] <cmd>` line, preserving BOTH the index N
	#   AND the command verbatim (incl. -b + absolute path). The index-less form
	#   `set-hook -g session-window-changed "<cmd>"` ALWAYS writes [0] and would
	#   CLOBBER multi-index hooks — use `session-window-changed[$hk_idx]`.
	#   If nothing was saved (bare "session-window-changed" line), the loop skips
	#   it -> no set-hook fires -> the hook stays cleared (== "leave unset").
	if [ "$(opt_suppress_window_hook)" = "on" ]; then
		r_hook="$(get_state "$ORIG_HOOK" "")"
		while IFS= read -r hk_line; do
			case "$hk_line" in
				"session-window-changed"|"") continue ;;   # bare name / blank -> skip
			esac
			hk_idx="$(printf '%s\n' "$hk_line" | sed -n 's/^session-window-changed\[\([0-9]\+\)\].*/\1/p')"
			hk_cmd="${hk_line#session-window-changed\[*\] }"
			[ -z "$hk_idx" ] && continue
			tmux set-hook -g "session-window-changed[$hk_idx]" "$hk_cmd" 2>/dev/null || true
		done <<< "$r_hook"
	fi
	# When @livepicker-suppress-window-hook is "off": activate did NOT clear the
	# hook, so the live hook is still the user's original -> restore does nothing
	# here (the if skips). Symmetric with activate T4.S2.
```

NOTE for the implementer:
- This block is the **only** new logic. It goes where the T3 seam comment block
  currently sits (between STEP 3's keep/cancel switch block and the T4 seam).
- The `local` line edit is the **only** other change (add the 7 T3 locals).
- Use `tmux set-option -g key-table "$r_kt"` (**`-g`**). Do NOT use the no-`-g`
  form the work-item literally wrote.
- Use `tmux set-hook -g "session-window-changed[$hk_idx]" "$hk_cmd"` (index-
  preserving). Do NOT use the index-less `set-hook -g session-window-changed
  "$hk_cmd"` the work-item literally wrote (it overwrites `[0]` on multi-index).
- Call `state_status_format_restore` as-is; do NOT call `tmux_unset_opt
  status-format` yourself and do NOT re-implement the array restore.
- Gate the hook replay on `if [ "$(opt_suppress_window_hook)" = "on" ]`.
- Do NOT touch STEP 1, STEP 2, STEP 3, the T4 seam, the header, the source trio,
  or the driver. Do NOT create any file. Do NOT add `set -e`.

### Integration Points

```yaml
HOST FILE (what this task edits):
  - scripts/restore.sh: restore_main() — `local` line extended; T3 seam REPLACED by STEP 4.

CALLERS / CONSUMERS (this file's INPUT — provided by sibling subtasks + activate):
  - P1.M6.T3.S1 / T4.S1 (input-handler.sh confirm/cancel — PLANNED): invoke
        "$CURRENT_DIR/restore.sh" <keep|cancel>. T3.S1's STEP 4 runs after STEP 1-3.
  - activate STEP 2 (P1.M4.T1.S1 — COMPLETE): wrote the ORIG_* saved-state keys T3.S1 reads.

STATE READS (this task — T3.S1 step 4):
  - @livepicker-orig-status             (via get_state "$ORIG_STATUS" "on")
  - @livepicker-orig-key-table          (via get_state "$ORIG_KEY_TABLE" "root")
  - @livepicker-orig-renumber-windows   (via get_state "$ORIG_RENUMBER" "on")
  - @livepicker-orig-session-window-changed  (via get_state "$ORIG_HOOK" ""; multi-line)
  - @livepicker-orig-status-format-indices + per-index values  (read INSIDE state_status_format_restore)
  - @livepicker-suppress-window-hook    (via opt_suppress_window_hook; default "on" — the hook gate)

STATE WRITES (this task): NONE. (T3 clears no @livepicker-* key; T4's clear_all_state
  owns that.)

TMUX MUTATIONS (this task — PRD §13 primitives):
  - status-format array: cleared (set-option -gu, every index) + saved indices replayed
        — via state_status_format_restore (clears the renderer line + resets to defaults).
  - status option: set to the saved value (set-option -g status "$r_status").
  - key-table option: set to the saved value (set-option -g key-table "$r_kt") — WITH -g.
  - renumber-windows option: set to the saved value (set-option -g renumber-windows "$r_renumber").
  - session-window-changed hook: each saved index replayed (set-hook -g
        "session-window-changed[$N]" "<cmd>"), under the suppress gate, index-preserving.
  - NO re-touch of unlink-window/select-window/switch-client (STEP 1/2/3); NO
        select-layout/clear_all_state/unbind-key (T4); NO link-window/capture-pane.

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
# Confirm the `local` line was extended:
grep -n 'local linked_id orig_window current_session orig_session mode r_status r_kt r_renumber r_hook hk_line hk_idx hk_cmd' scripts/restore.sh   # expect 1
# Confirm T3's primitives are present (status-format helper, 3 option restores WITH -g, hook gate):
grep -n 'state_status_format_restore' scripts/restore.sh                                           # expect 1
grep -n 'set-option -g status "\$r_status"' scripts/restore.sh                                     # expect 1
grep -n 'set-option -g key-table "\$r_kt"' scripts/restore.sh                                      # expect 1
grep -n 'set-option -g renumber-windows "\$r_renumber"' scripts/restore.sh                          # expect 1
grep -n 'if \[ "\$(opt_suppress_window_hook)" = "on" \]' scripts/restore.sh                        # expect 1
# CORRECTIONS: key-table uses -g (NOT the work-item's no-g literal); hook replay is index-preserving:
grep -n 'set-option -g key-table' scripts/restore.sh && echo "OK: key-table -g (CORRECTION 1 applied)" || echo "FAIL: missing -g on key-table"
grep -n 'set-hook -g "session-window-changed\[\$hk_idx\]" "\$hk_cmd"' scripts/restore.sh && echo "OK: index-preserving hook (CORRECTION 2 applied)" || echo "FAIL: hook replay not index-preserving"
# Confirm the T3 seam comment block is GONE (replaced by STEP 4):
grep -n 'T3 (P1.M5.T3.S1): restore status' scripts/restore.sh \
  && echo "WARN: re-check — the seam header comment may remain (ok if relabeled [T3])" || echo "OK: T3 seam replaced by STEP 4"
# Confirm the T4 seam comment is STILL present (unchanged):
grep -n 'T4 (P1.M5.T4.S1): select-layout ORIG_LAYOUT' scripts/restore.sh       # expect 1
# Confirm T1.S1's STEP 1/2 + T2.S1's STEP 3 are UNCHANGED:
grep -n 'unlink-window -t "\$current_session:\$linked_id" 2>/dev/null || true' scripts/restore.sh   # expect 1
grep -n 'select-window -t "\$orig_window" 2>/dev/null || true' scripts/restore.sh                    # expect 1
grep -n 'switch-client -t "=\$orig_session" 2>/dev/null || true' scripts/restore.sh                  # expect 1
# Confirm NO off-limits work leaked in (no T4/preview mutations):
grep -n 'select-layout\|clear_all_state\|unbind-key\|link-window\|capture-pane' scripts/restore.sh \
  | grep -v 'T4\|#' \
  && echo "FAIL: T3 must not do T4/preview work" || echo "OK: only STEP 4 implemented"
# Run from the repo root.
```

### Level 2: Socket-Shim Mock Validation — byte-identical before-vs-after, zero live-server impact

Reuses the PATH-wrapper socket shim. Self-cleaning. Seeds the REAL env's hook
shape (single `[0] run-shell -b <abs>`) AND a multi-index variant, snapshots
`show-options -g` + `show-hooks -g session-window-changed` before activate,
runs activate, runs the REAL `restore.sh cancel`, and diffs the after-state to
nothing. **MUST keep an attached client** (display-message in activate needs one).

```bash
#!/usr/bin/env bash
# Throwaway socket-shim validation for scripts/restore.sh T3.S1 (do NOT commit).
set -u
REPO_ROOT="$(cd "$(dirname "$0")" && pwd)"
[ -f "$REPO_ROOT/scripts/restore.sh" ] || { echo "restore.sh missing"; exit 1; }
[ -f "$REPO_ROOT/scripts/livepicker.sh" ] || { echo "livepicker.sh missing (activate fixture)"; exit 1; }
for l in options utils state renderer preview; do
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
	rm -rf "$SHIM_DIR"
}
trap cleanup EXIT

pass=0; fail=0
assert() { if [ "$2" = "$3" ]; then pass=$((pass+1)); printf 'ok   %s\n' "$1"; else fail=$((fail+1)); printf 'FAIL %s: got=[%s] want=[%s]\n' "$1" "$2" "$3"; fi; }
attach() { TMUX="" script -qec "tmux -L $SOCK attach -t $1" /dev/null >/dev/null 2>&1 & AP=$!; sleep 0.5; }
detach() { kill "$AP" 2>/dev/null; wait "$AP" 2>/dev/null; }
# snapshot the options + hook T3.S1 restores
snap() {
	tmux show-options -g 2>/dev/null | grep -E '^(status|status-format|key-table|renumber-windows)(\[|$) ' | sort
	tmux show-hooks -g session-window-changed 2>/dev/null
}

run_round() {  # $1 = label, $2 = pre-activate hook seed cmd (may be multi-line via $'\n'), $3 = expect-hook-after
	local label="$1" seed="$2"
	# fresh state
	tmux kill-session -t driver 2>/dev/null
	for k in mode list filter index linked-id type orig-session orig-window orig-layout \
	         orig-key-table orig-status orig-renumber-windows orig-session-window-changed \
	         orig-status-format-indices; do tmux set-option -gu "@livepicker-$k" 2>/dev/null; done
	tmux set-option -g key-table root
	tmux set-option -g status on
	tmux set-option -g renumber-windows on
	tmux set-option -gu status-format 2>/dev/null
	tmux set-hook -gu session-window-changed 2>/dev/null
	# seed the user's hook
	local oldifs="$IFS"; IFS=$'\n'; set -f
	for l in $seed; do
		[ -z "$l" ] && continue
		case "$l" in
			"["*) ;; # "[0] cmd" or "[1] cmd" form
			*) l="[0] $l" ;;
		esac
		local idx="${l%%]*}"; idx="${idx#*[}"; local cmd="${l#] }"
		tmux set-hook -g "session-window-changed[$idx]" "$cmd"
	done
	set +f; IFS="$oldifs"
	tmux set-option -g "@livepicker-suppress-window-hook" "on"

	# snapshot BEFORE
	local before; before="$(snap)"
	# activate + restore cancel
	attach driver
	bash "$REPO_ROOT/scripts/livepicker.sh"
	bash "$REPO_ROOT/scripts/restore.sh" cancel; local rc=$?
	detach
	local after; after="$(snap)"
	assert "$label: restore exit 0" "$rc" "0"
	if [ "$before" = "$after" ]; then
		pass=$((pass+1)); printf 'ok   %s: byte-identical before-vs-after (status/status-format/key-table/renumber/hook)\n' "$label"
	else
		fail=$((fail+1)); printf 'FAIL %s: snapshot DIFFERS\n--- before ---\n%s\n--- after ---\n%s\n' "$label" "$before" "$after"
	fi
	# spot-check key-table is root (CORRECTION 1: -g took effect)
	assert "$label: key-table == root after restore" "$(tmux show-option -gv key-table)" "root"
}

# ---------- setup ----------
tmux new-session -d -s driver -x 120 -y 40
tmux new-window -t driver   # a 2nd window so select has somewhere to be

# ---------- (A) SINGLE-INDEX hook (the real env shape) ----------
run_round "(A) single-index" "run-shell -b /home/dustin/.config/tmux/scripts/sync-window-focus.sh"

# ---------- (B) MULTI-INDEX hook (proves index-preserving CORRECTION 2) ----------
run_round "(B) multi-index" $'[0] run-shell -b /home/dustin/.config/tmux/scripts/sync-window-focus.sh\n[1] run-shell "echo second-hook"'

# ---------- (C) NO hook set at activate (bare name) -> stays cleared ----------
tmux set-hook -gu session-window-changed 2>/dev/null
run_round "(C) no-hook" ""

# ---------- (D) suppress=off -> hook untouched (no replay, no clear) ----------
tmux kill-session -t driver 2>/dev/null
tmux new-session -d -s driver -x 120 -y 40; tmux new-window -t driver
for k in mode list filter index linked-id type orig-session orig-window orig-layout \
         orig-key-table orig-status orig-renumber-windows orig-session-window-changed \
         orig-status-format-indices; do tmux set-option -gu "@livepicker-$k" 2>/dev/null; done
tmux set-option -g key-table root; tmux set-option -g status on; tmux set-option -g renumber-windows on
tmux set-option -gu status-format 2>/dev/null
tmux set-hook -g session-window-changed "run-shell -b /home/dustin/.config/tmux/scripts/sync-window-focus.sh"
tmux set-option -g "@livepicker-suppress-window-hook" "off"
D_BEFORE="$(snap)"
attach driver
bash "$REPO_ROOT/scripts/livepicker.sh"
bash "$REPO_ROOT/scripts/restore.sh" cancel; rcD=$?
detach
D_AFTER="$(snap)"
assert "(D) restore exit 0 (suppress off)" "$rcD" "0"
[ "$D_BEFORE" = "$D_AFTER" ] && { pass=$((pass+1)); printf 'ok   (D): byte-identical (hook untouched, off path)\n'; } \
	|| { fail=$((fail+1)); printf 'FAIL (D): snapshot differs (off path should be a no-op for the hook)\n'; }
# the hook is still present (off path did NOT clear/replay):
assert "(D) hook still present after off-path restore" "$(tmux show-hooks -g session-window-changed | grep -c 'run-shell -b')" "1"

printf '\n==== PASS=%d FAIL=%d ====\n' "$pass" "$fail"
[ "$fail" = "0" ]
# Expected: all PASS, 0 FAIL. Key proofs:
#  (A) single-index: status/status-format/key-table/renumber/hook all byte-identical;
#      key-table==root (CORRECTION 1 -g took effect).
#  (B) multi-index: BOTH [0] and [1] restored byte-identical (CORRECTION 2 index-
#      preserving works; the work-item's literal index-less form would have FAILED
#      this round by clobbering [0] -> [0]=second-hook, [1] missing).
#  (C) no hook: snapshot byte-identical; the bare-name branch skipped (hook stays cleared).
#  (D) suppress=off: snapshot byte-identical; hook UNTOUCHED (no clear, no replay).
```

### Level 3: Integration Testing (System Validation)

```bash
# Live spot-check on an ISOLATED socket WITH an attached client — confirms the REAL
# restore.sh returns the global options + hook to their pre-activate state after a
# full activate->cancel cycle. Self-cleaning.
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
T new-window -t demo
# seed the real env's hook
T set-hook -g session-window-changed "run-shell -b /home/dustin/.config/tmux/scripts/sync-window-focus.sh"
echo "BEFORE activate:"
echo "  status=[$(T show-option -gv status)] key-table=[$(T show-option -gv key-table)] renumber=[$(T show-option -gv renumber-windows)]"
echo "  hook=[$(T show-hooks -g session-window-changed)]"
echo "  status-format[0]=[$(T show-option -gqv 'status-format[0]' | head -c 30)]..."
TMUX="" script -qec "tmux -L $LP_SOCK attach -t demo" /dev/null >/dev/null 2>&1 &
AP=$!; sleep 0.5
PATH="$SHIM_DIR:$PATH" bash "$REPO_ROOT/scripts/livepicker.sh"; echo "activate rc=$? (expect 0)"
echo "AFTER activate (mutated):"
echo "  status=[$(T show-option -gv status)] key-table=[$(T show-option -gv key-table)]"
echo "  status-format[0]=[$(T show-option -gqv 'status-format[0]' | head -c 30)]... (expect #(<abs>/renderer.sh))"
echo "  hook=[$(T show-hooks -g session-window-changed)] (expect bare name — cleared)"
PATH="$SHIM_DIR:$PATH" bash "$REPO_ROOT/scripts/restore.sh" cancel; echo "restore rc=$? (expect 0)"
kill "$AP" 2>/dev/null; wait "$AP" 2>/dev/null
echo "AFTER restore cancel (should match BEFORE):"
echo "  status=[$(T show-option -gv status)] key-table=[$(T show-option -gv key-table)] renumber=[$(T show-option -gv renumber-windows)]"
echo "  hook=[$(T show-hooks -g session-window-changed)] (expect [0] run-shell -b <abs> back)"
echo "  status-format[0]=[$(T show-option -gqv 'status-format[0]' | head -c 30)]... (expect default composite, NOT renderer)"
# Expected: AFTER restore == BEFORE activate (status on, key-table root, hook [0] -b restored,
#   status-format[0] is the default composite NOT the renderer). The renderer line is GONE.
```

### Level 4: Creative & Domain-Specific Validation

```bash
# Structural + byte-identical guarantees for the restore (PRD §15.21 "Restore"),
# runnable WITHOUT a live tmux server (pure code-structure assertions):
REPO_ROOT="$(pwd)"
# 1. status-format restore delegates to the COMPLETE helper (no re-implementation):
n_sfr="$(grep -c 'state_status_format_restore' "$REPO_ROOT/scripts/restore.sh")"
[ "$n_sfr" -ge 1 ] && echo "OK: calls state_status_format_restore" || echo "FAIL: missing status-format restore"
# 2. the 3 option restores all use -g:
grep -q 'set-option -g status "\$r_status"' "$REPO_ROOT/scripts/restore.sh" && echo "OK: status -g" || echo "FAIL: status"
grep -q 'set-option -g key-table "\$r_kt"' "$REPO_ROOT/scripts/restore.sh" && echo "OK: key-table -g (CORRECTION 1)" || echo "FAIL: key-table"
grep -q 'set-option -g renumber-windows "\$r_renumber"' "$REPO_ROOT/scripts/restore.sh" && echo "OK: renumber -g" || echo "FAIL: renumber"
# 3. CORRECTION 2: hook replay is index-preserving (NOT the work-item's index-less literal):
grep -q 'set-hook -g "session-window-changed\[\$hk_idx\]" "\$hk_cmd"' "$REPO_ROOT/scripts/restore.sh" \
  && echo "OK: hook index-preserving (CORRECTION 2)" \
  || echo "FAIL: hook replay must preserve the index"
# 4. the replay is gated on the SAME option as activate T4.S2:
grep -q 'if \[ "\$(opt_suppress_window_hook)" = "on" \]' "$REPO_ROOT/scripts/restore.sh" \
  && echo "OK: hook replay gated on suppress==on" || echo "FAIL: missing suppress gate"
# 5. no default status-format strings are captured/replayed (TRAP 1):
grep -q 'tmux_unset_opt status-format\|set-option -gu status-format' "$REPO_ROOT/scripts/restore.sh" \
  && echo "WARN: T3 should NOT call -gu status-format directly (delegate to the helper)" \
  || echo "OK: no direct status-format -gu in restore.sh (delegated to helper)"

# Real-env gate (optional, post-T4 when the picker is fully live): on the REAL
# tubular server, do a real activate (prefix key), navigate, then cancel; confirm
# the status bar is back to ONE line, the renderer is gone, the key-table is root,
# and `show-hooks -g session-window-changed` is EXACTLY
#   session-window-changed[0] run-shell -b /home/dustin/.config/tmux/scripts/sync-window-focus.sh
# This is the end-to-end proof that complements the socket mock; it requires T4 to
# be live (so clear_all_state + unbind complete the teardown).
```

## Final Validation Checklist

### Technical Validation

- [ ] `bash -n scripts/restore.sh` exits 0 with no output.
- [ ] `shellcheck scripts/restore.sh` reports 0 findings (no new disable; T3's
      hook loop reads via heredoc, so no SC2086 is strictly needed).
- [ ] No 4-space indents (`grep -Pn '^    '` is empty); tabs only.
- [ ] `scripts/restore.sh` is still executable (T1.S1 set +x; T3's edit preserves it).

### Feature Validation

- [ ] The `local` line includes `r_status r_kt r_renumber r_hook hk_line hk_idx hk_cmd`.
- [ ] The T3 seam comment block is REPLACED by STEP 4 (the comment is gone; the
      restore calls are present).
- [ ] status-format: `state_status_format_restore` called once (no direct `-gu`).
- [ ] status: `set-option -g status "$r_status"` (`r_status` from
      `get_state "$ORIG_STATUS" "on"`).
- [ ] key-table: `set-option -g key-table "$r_kt"` (**`-g`** — CORRECTION 1).
- [ ] renumber-windows: `set-option -g renumber-windows "$r_renumber"`.
- [ ] hook: under `if [ "$(opt_suppress_window_hook)" = "on" ]`, the loop replays
      each saved line via `set-hook -g "session-window-changed[$hk_idx]" "$hk_cmd"`
      (**index-preserving** — CORRECTION 2); bare-name lines skipped.
- [ ] Mock (§2): (A) single-index byte-identical; (B) multi-index byte-identical
      (proves CORRECTION 2); (C) no-hook byte-identical (bare-name branch); (D)
      suppress=off byte-identical (hook untouched).

### Code Quality Validation

- [ ] Follows existing codebase patterns (mirrors T1/T2's `get_state "$ORIG_*"
      "<default>"` idiom; one-tab indent; the gate idiom matches activate T4.S2).
- [ ] Surgical edit (only the `local` line + the T3 seam; STEP 1/2/3/T4/driver
      untouched).
- [ ] Anti-patterns avoided (no no-`-g` key-table; no index-less hook replay; no
      default status-format replay; no un-gated hook replay; no `set -e`; no
      re-touch of T1/T2/T4 seams).
- [ ] Dependencies properly managed (reads ORIG_* + opt_suppress_window_hook;
      calls state_status_format_restore; mutates only status/status-format/
      key-table/renumber/hook).

### Documentation & Deployment

- [ ] Code is self-documenting (the STEP 4 block cites PRD §9 step 4 / §16; explains
      TRAP 1 (status-format -gu via helper), CORRECTION 1 (key-table -g), CORRECTION 2
      (index-preserving hook replay), the suppress gate, and the bare-name branch).
- [ ] Logs are informative but not verbose (T3 emits nothing on success).
- [ ] No new environment variables (T3 uses only the `@livepicker-orig-*` keys
      [activate STEP 2 save] + `@livepicker-suppress-window-hook` [config]).

---

## Anti-Patterns to Avoid

- ❌ Don't restore `key-table` WITHOUT `-g` — the work-item's literal
  `set-option key-table "$r_kt"` does NOT take effect on `show-option -gv`
  (verified; the no-`-g` form sets a session-scoped value that -gv does not read).
  Activate T4.S1 used `-g` and the save was a GLOBAL read; restore MUST mirror it.
  Always `set-option -g key-table "$r_kt"` (CORRECTION 1).
- ❌ Don't replay the hook INDEX-LESS — the work-item's literal
  `set-hook -g session-window-changed "<cmd>"` ALWAYS writes `[0]`, so iterating
  two saved lines clobbers the first (multi-index breaks). Use the index-
  preserving `set-hook -g "session-window-changed[$hk_idx]" "$hk_cmd"` (CORRECTION 2;
  verified byte-identical for single AND multi). The real env has one `[0]`, so the
  literal form "happens to work" — but the index-preserving form is correct always.
- ❌ Don't re-implement the status-format `-gu` reset yourself — `state.sh`'s
  `state_status_format_restore` is ALREADY COMPLETE (it does the `-gu` reset + the
  saved-index replay). Calling it is the whole job for status-format. A direct
  `tmux set-option -gu status-format` would skip the saved-index replay (losing any
  genuine user overrides) and re-implements TRAP 1 inline (house style says use the
  helper). Do NOT capture/replay the default `[0,1,2]` strings (TRAP 1: fragile).
- ❌ Don't replay the hook UNGATED — activate T4.S2 cleared the hook ONLY when
  `@livepicker-suppress-window-hook == "on"`; restore replays under the SAME gate.
  When off, activate did not clear the hook (it's already the user's original), so
  restore does nothing for the hook. Unconditional replay is harmless but wrong by
  symmetry and adds a needless `set-hook`.
- ❌ Don't assume the saved hook is a single line — it is the FULL `show-hooks`
  output (multi-line; tmux preserves newlines in `@-options`). Iterate every line
  via `while IFS= read -r ... done <<< "$r_hook"`. The real env has one `[0]` line,
  but the loop must be general.
- ❌ Don't forget the bare-name branch — when no hook was set at save time,
  `show-hooks` returned the bare `session-window-changed` (stored in ORIG_HOOK).
  The loop's `case "$hk_line" in "session-window-changed"|"") continue ;;` skips
  it → no `set-hook` fires → the hook stays cleared (== "leave unset"). Without
  this guard, the `${hk_line#...}` expansion on the bare name yields garbage and
  `sed` extracts an empty index (caught by `[ -z "$hk_idx" ] && continue`), but the
  explicit `case` is clearer and the documented intent.
- ❌ Don't `case`-normalize the status on restore — the `case` (T3 grow FINDING 1)
  was to avoid the `$((on+1))` set -u crash + the `status 1` rejection. Restore
  replays the RAW saved value (`"on"`) directly; it is already a valid tmux status
  value. Adding a `case` here is dead code.
- ❌ Don't drop the `2>/dev/null || true` on the `set-hook` calls — house style
  (system_context §9): every fail-possible tmux call gets it. `set-hook` succeeds
  on valid args, but a future hook-arg edge or vanished session could return
  non-zero; under a future `set -e` (or just for uniform safety) append it.
- ❌ Don't touch STEP 1 / STEP 2 / STEP 3 / the T4 seam / the driver — T3.S1 is a
  surgical edit of the `local` line + the T3 seam only. Re-touching T1/T2's work
  or pre-empting T4 muddies the seam boundaries and risks merge conflicts.
- ❌ Don't skip validation because "it should work" — run the socket-shim mock (§2);
  round (B) (multi-index byte-identical) is what PROVES CORRECTION 2 (the work-
  item's literal index-less form would FAIL round B by clobbering `[0]`).
