name: "P3.M2.T1.S1 — Capture pane-geometry snapshot at activate (PRD §9/§23 drift-detection baseline)"
description: Implementation work item (PRD §9 second bullet + §23 Invariant C). Add the `ORIG_PANE_GEOMETRY` saved-state constant to `scripts/state.sh` (ORIG_* block, auto-cleared by clear_all_state's grep) and capture the original window's per-pane geometry in `scripts/livepicker.sh` STEP 2 immediately after the `ORIG_LAYOUT` capture, BEFORE the T3 status grow — so restore (P3.M2.T1.S2) can compare the re-captured geometry to this snapshot and act ONLY if drift is detected. Format string is a CONTRACT with the consumer: `'#{pane_id}:#{pane_left},#{pane_top},#{pane_width},#{pane_height}'`. SCOPE = capture ONLY (the drift-gated restore is P3.M2.T1.S2; the candidate pin is P3.M2.T2).

---

## Goal

**Feature Goal**: Establish the activation-time pane-geometry baseline of the driver's original window that PRD §9 + §23 require for drift-gated restore. Restore must "compare the original window's current pane geometry to the activation snapshot ... act only if it drifted." That snapshot does not exist yet — STEP 2 captures `ORIG_LAYOUT` (the `window_layout` string) but NOT the per-pane geometry. This task adds the missing capture.

**Deliverable**: Two minimal edits, both to existing files:
1. `scripts/state.sh` — `readonly ORIG_PANE_GEOMETRY="@livepicker-orig-pane-geometry"` added to the ORIG_* block right after `ORIG_LAYOUT` (auto-cleared by `clear_all_state`'s `grep '@livepicker-orig-'` — zero edits there, mirroring `ORIG_WINDOW_SIZE`).
2. `scripts/livepicker.sh` STEP 2 — one `tmux set-option -g "$ORIG_PANE_GEOMETRY" "$(tmux list-panes -t "$(lp_client_format '#{window_id}')" -F '#{pane_id}:#{pane_left},#{pane_top},#{pane_width},#{pane_height}' 2>/dev/null)"` line inserted immediately after the `ORIG_LAYOUT` capture (line 175), before the option reads.

**Success Definition**: After a real `livepicker.sh` activate (attached client), `tmux show-option -gqv @livepicker-orig-pane-geometry` contains one line per pane of the original window in the pinned format (e.g. `%0:0,0,80,23`); on cancel `clear_all_state` leaves it unset (no trace). The capture is the PRE-GROW geometry (STEP 2 runs before T3). `bash tests/run.sh` stays green (existing byte-exact-restore + pollution suites unbroken). No restore-side logic is added (that is P3.M2.T1.S2).

## User Persona

**Target User**: The P3.M2.T1.S2 implementer (the very next agent), who needs the snapshot to exist in the `ORIG_PANE_GEOMETRY` key, in a stable format, captured at the right moment, to build the drift comparison. And the P3.M3.T1 test author, who asserts §23 byte-identical pane geometry across a browse→cancel cycle.

**Use Case**: Restore reads `ORIG_PANE_GEOMETRY`, re-captures the original window's current geometry with the IDENTICAL format, string-compares; equal → leave the window alone (the §23-preferred no-op); differ → act (resize-pin the size first, then restore — per `pane_immutability_verification.md` §3, the gate P3.M1.T1.S1 produces).

## Why

- PRD §9 (second bullet) explicitly requires saving BOTH the `window_layout` AND "a pane-geometry snapshot of that window (`#{pane_id}`/`#{pane_left}`/`#{pane_top}`/`#{pane_width}`/`#{pane_height}` per pane)." The `ORIG_LAYOUT` string captures the checksummed layout tree, but §23's drift detection needs the per-pane numbers so restore can detect a resize/reorder and decide whether to act. STEP 2 currently saves only the layout string — this task closes that gap.
- PRD §23 (Invariant C, absolute) + §9 step 5: restore must be a **no-op whenever the original window did not actually drift**, because `select-layout` is size-dependent and can itself move panes ("leaving the window untouched is always preferable to moving its panes"). A drift decision requires a baseline to compare against. Without this snapshot, restore cannot tell drift from no-drift and must either always-restore (risky) or never-restore (misses real drift).
- Integrates with the existing save/restore contract (PRD §9): `ORIG_PANE_GEOMETRY` joins the `@livepicker-orig-*` saved-state set, auto-cleared by `clear_all_state`, and is the conceptual pair of `ORIG_LAYOUT` (same window, captured at the same moment, both consumed by restore).

## What

A single new saved-state constant + a single capture line at activate. No user-visible behavior, no new options, no new keys on the runtime path. The snapshot is internal state (PRD §9: "not saved, live in `@livepicker-*`" — except this IS saved-state because it is captured-at-activate and read-at-restore).

### Success Criteria

- [ ] `ORIG_PANE_GEOMETRY` is a `readonly` constant in `state.sh`'s ORIG_* block, placed right after `ORIG_LAYOUT`, with an inline comment citing PRD §9/§23 + the auto-clear note.
- [ ] `ORIG_PANE_GEOMETRY` is auto-cleared by `clear_all_state` (it matches `@livepicker-orig-`) with ZERO edits to `clear_all_state` or `_STATE_RUNTIME_KEYS`.
- [ ] `livepicker.sh` STEP 2 captures the per-pane geometry of the original window AFTER `ORIG_LAYOUT` and BEFORE the T3 status grow, using the pinned format `'#{pane_id}:#{pane_left},#{pane_top},#{pane_width},#{pane_height}'`.
- [ ] The snapshot targets the ORIGINAL window (client-aware via `lp_client_format '#{window_id}'`, == the @N id `ORIG_WINDOW` just saved) and stores the multi-line `list-panes` output verbatim (newlines preserved).
- [ ] `bash tests/run.sh` stays green; `shellcheck scripts/state.sh scripts/livepicker.sh` reports no new errors.
- [ ] No restore-side drift logic, no candidate pin, no test file, no clear_all_state / _STATE_RUNTIME_KEYS edit (all out of scope).

## All Needed Context

### Context Completeness Check

_"If someone knew nothing about this codebase, would they have everything needed to implement this successfully?"_ — Yes. This PRP pins the exact two insertion anchors (verbatim surrounding lines with line numbers), the exact constant + capture line, the format-string contract (do not change it), the auto-clear mechanism (zero edit, with the `ORIG_WINDOW_SIZE` precedent), the gotchas (newlines preserved, `2>/dev/null` only, SC2034 already covered, SAVED-STATE not runtime, tabs), and the precise scope boundary (capture ONLY — restore/candidate-pin/test are other tasks). The consumer contract (P3.M2.T1.S2 re-captures with the identical format) is stated so the format is treated as load-bearing.

### Documentation & References

```yaml
# MUST READ — load into the context window before editing.

- file: plan/004_2c5127285a90/P3M2T1S1/research/pane_geometry_snapshot_findings.md
  why: THIS task's synthesis — the two exact edits, the format-string contract, the auto-clear
        proof, the target-resolution options, the timing/ordering (pre-grow baseline), and the
        gotchas. Read FIRST; it is the TL;DR of everything below.
  section: "§2 the two edits; §3 format is a contract; §4 auto-clear (zero edit); §7 gotchas"

- file: scripts/state.sh              # the ORIG_* block (lines ~54-62) + clear_all_state
  why: Edit A. Add `readonly ORIG_PANE_GEOMETRY="@livepicker-orig-pane-geometry"` right after
        ORIG_LAYOUT (line 56). clear_all_state's `grep '@livepicker-orig-'` heredoc loop (the
        teardown) already unsets every @livepicker-orig-* -> NO edit to clear_all_state needed.
  pattern: "readonly ORIG_WINDOW_SIZE=...  # ...; auto-cleared by clear_all_state's grep '@livepicker-orig-'"
  gotcha: "ORIG_PANE_GEOMETRY is SAVED-STATE (written activate, read restore), NOT a runtime key. Do NOT
        add it to _STATE_RUNTIME_KEYS (that list is the picker-internal runtime set; ORIG_* is the
        saved-state set, a different list). Mirror ORIG_WINDOW_SIZE exactly."

- file: scripts/livepicker.sh         # activate_main STEP 2 (lines 173-175) + T3 (line ~232)
  why: Edit B. The capture slots in IMMEDIATELY AFTER line 175 (`ORIG_LAYOUT`) and BEFORE line 176
        (the "# Three ordinary option reads" comment). STEP 2 runs BEFORE T3 (the status grow), so
        the snapshot is the PRE-GROW, pre-mutation baseline of the original window — exactly what
        restore needs for drift detection.
  pattern: 'tmux set-option -g "$ORIG_LAYOUT" "$(lp_client_format "#{window_layout}")"  # <- insert after this'
  gotcha: "ORIG_WINDOW (saved line 174 via lp_client_format '#{window_id}') holds the @N id of the
        original window. The list-panes target must be that same @N. lp_client_format '#{window_id}'
        re-resolves it (contract literal); equivalently get_state \"$ORIG_WINDOW\" \"\" reuses the
        just-saved id. The var/substitution already holds @N -> do NOT prepend @ (-> @@N, rc=1)."

- file: scripts/utils.sh              # lp_client_format (lines 166-181) + lp_resolve_client
  why: the client-aware format resolver used by STEP 2. lp_client_format FMT resolves FMT against the
        INVOKING client (MRU under run-shell); falls back to context-free display-message on the
        client-less edge. Identical to how ORIG_SESSION/WINDOW/LAYOUT are captured -> consistency.
  pattern: "lp_client_format '#{window_id}'  -> the @N id of the invoking client's active window"

- file: scripts/restore.sh            # STEP 5 (the ORIG_LAYOUT select-layout) — READ-ONLY (the consumer)
  why: CONTEXT for why the snapshot exists + the FORMAT CONTRACT. STEP 5 currently does
        `orig_layout="$(get_state "$ORIG_LAYOUT" "")"; [ -n ] && tmux select-layout "$orig_layout"`.
        P3.M2.T1.S2 will ADD: re-capture geometry with the IDENTICAL format, compare to
        ORIG_PANE_GEOMETRY, act only on drift (and per pane_immutability_verification.md §3, use
        resize-window -y H_orig size-first, NOT a bare select-layout). This task does NOT edit restore.sh.

- file: PRD.md                        # §9 second bullet (save list) + §9 restore step 5 + §23 Invariant C
  why: the spec. §9: save "window_layout ... plus a pane-geometry snapshot (#{pane_id}/#{pane_left}/
        #{pane_top}/#{pane_width}/#{pane_height} per pane)" so restore "can detect whether anything
        drifted and act only if it did." §23: "compare the pane-geometry snapshot captured at
        activation ... Only if drift is detected: restore the window's exact size first, then
        select-layout. Leaving the window untouched is always preferable to moving its panes."
  section: "§9 save list (bullet 2) + restore step 5; §23 'Prevention regime' bullet 3; §15.23"

- file: plan/004_2c5127285a90/P3M1T1S1/PRP.md   # the gate (running in parallel)
  why: P3.M1.T1.S1's pane_immutability_verification.md §3 CORRECTS the restore recipe: drift-restore
        must use `resize-window -y H_orig` (size-first), NOT a bare `select-layout` (which is the
        unreliable, size-dependent one). This INFORMS the consumer (P3.M2.T1.S2), NOT this task — but
        the snapshot this task captures is the baseline that comparison uses. Treat the gate as a
        CONTRACT for what the consumer will do; this task just provides the input.
  note: "Do NOT implement the restore comparison here — it is P3.M2.T1.S2. This task only WRITES the snapshot."

- url: https://github.com/tmux/tmux/blob/master/CHANGES  (list-panes format specifiers)
  why: confirms #{pane_id}/#{pane_left}/#{pane_top}/#{pane_width}/#{pane_height} are stable per-pane
        format specifiers; list-panes emits one line per pane in deterministic pane order; -t accepts a
        window @id; show-option/set-option -g preserve embedded newlines in @-option values.
  section: "list-panes -F format specifiers; pane addressing by window id"
```

### Current Codebase tree (run `ls scripts/` in the project root)

```bash
tmux-livepicker/
├── scripts/
│   ├── state.sh       # ORIG_* saved-state + clear_all_state — ADD ORIG_PANE_GEOMETRY here (Edit A)
│   ├── livepicker.sh  # activate_main STEP 2 — ADD the geometry capture after ORIG_LAYOUT (Edit B)
│   ├── utils.sh       # lp_client_format (the client-aware resolver — read-only; do NOT edit)
│   ├── restore.sh     # STEP 5 consumer (read-only — P3.M2.T1.S2 owns the drift logic)
│   ├── preview.sh / options.sh / input-handler.sh / renderer.sh / layout.sh / rank.sh / session-mgmt.sh  # untouched
├── tests/             # harness + test_*.sh (untouched — P3.M3.T1 owns the §23 test suite)
├── plan/004_2c5127285a90/
│   ├── architecture/  # system_context.md, gap_analysis_*.md (read); pane_immutability_verification.md (P3.M1.T1.S1 produces)
│   └── P3M2T1S1/{PRP.md (THIS file), research/pane_geometry_snapshot_findings.md}
├── PRD.md             # §9, §23, §15.23 (READ-ONLY)
└── README.md / CHANGELOG.md  (untouched — P4 owns changeset docs)
```

### Desired Codebase tree with files to be added and responsibility of file

```bash
# No NEW files. This task EDITS two existing files (both responsibilities already exist):
scripts/state.sh      # +1 readonly: ORIG_PANE_GEOMETRY (saved-state; auto-cleared by clear_all_state's grep)
scripts/livepicker.sh # +1 capture line in STEP 2 (after ORIG_LAYOUT, before the status grow)
# research/pane_geometry_snapshot_findings.md already written (this PRP's synthesis)
```

### Known Gotchas of our codebase & tmux 3.6b

```bash
# CRITICAL for this task:

# 1. ORIG_PANE_GEOMETRY is SAVED-STATE, NOT a runtime key. Add it to the ORIG_* block (state.sh ~L56,
#    right after ORIG_LAYOUT), NOT to _STATE_RUNTIME_KEYS. clear_all_state's `grep '@livepicker-orig-'`
#    heredoc loop already unsets every @livepicker-orig-* -> ZERO edit to clear_all_state (mirror the
#    ORIG_WINDOW_SIZE precedent, whose comment states exactly this).

# 2. The format string is a CONTRACT with the consumer. P3.M2.T1.S2 re-captures the current geometry
#    with the IDENTICAL format and string-compares to the snapshot. Do NOT change the separator, field
#    order, or add a sort. Use EXACTLY:
#      '#{pane_id}:#{pane_left},#{pane_top},#{pane_width},#{pane_height}'
#    (one line per pane; `:` after pane_id; `,` between dims). Unsorted (native list-panes order) so
#    drift detection catches BOTH a resize (dims change) AND a reorder (line order changes).

# 3. set-option -g preserves embedded newlines. A multi-pane window's list-panes output is multi-line;
#    set-option -g stores it verbatim (same as STATE_LIST), and get_state (show-option -gqv) reads the
#    full multi-line value back. Do NOT join/sed/sort the output. (Confirmed by the STATE_LIST pattern.)

# 4. `2>/dev/null` only (no `|| true` needed). list-panes could fail if the window vanished (a race);
#    under house `set -u` (NO `set -e`) a failing command inside $(...) yields empty stdout -> stores "".
#    restore's get_state default "" handles empty as "no snapshot" -> no-op. Match the contract literally.

# 5. The target is the @N id, already held by ORIG_WINDOW (saved line 174 via lp_client_format
#    '#{window_id}'). The contract-literal target is `$(lp_client_format '#{window_id}')` (re-resolves
#    the same @N). The substitution already yields e.g. @3 -> do NOT prepend @ (-> @@3, rc=1). An
#    equivalent, marginally-cheaper target is `$(get_state "$ORIG_WINDOW" "")` (reuses the saved id).

# 6. STEP 2 runs BEFORE T3 (status grow). So the snapshot is the PRE-GROW, pre-mutation baseline of the
#    original window — correct for drift detection (restore compares to "did browsing change it").

# 7. SC2034 already covered. The new readonly const is unused within state.sh (integration seam consumed
#    by livepicker.sh/restore.sh); state.sh's file-wide `# shellcheck disable=SC2034` covers it. The
#    `#{...}` in the single-quoted list-panes format is literal bash (shellcheck does not flag it). No
#    new shellcheck directive is needed.

# 8. TABS for indent (state.sh + livepicker.sh both use tabs). Match the surrounding 1-tab indent in
#    STEP 2 and the ORIG_* block. No new `local` (no new function).
```

## Implementation Blueprint

No new data models — this task adds one saved-state constant + one capture line. The "models" are the constant (state.sh) and the captured string (livepicker.sh).

### Data models and structure

```bash
# scripts/state.sh — new saved-state constant (PRD §9 bullet 2 + §23). 1 line + inline comment, mirror ORIG_WINDOW_SIZE.
readonly ORIG_PANE_GEOMETRY="@livepicker-orig-pane-geometry"   # per-pane geometry of the original window (PRD §9/§23); restore compares to detect drift, acts only if changed (Invariant C); auto-cleared by clear_all_state's grep '@livepicker-orig-'
```

The captured value (livepicker.sh) is a multi-line string, one pane per line, e.g. for a 3-pane window:
```
%0:0,0,40,11
%1:40,0,40,11
%3:0,12,40,11
```
Format: `#{pane_id}:#{pane_left},#{pane_top},#{pane_width},#{pane_height}` per pane, native (unsorted) list-panes order.

### Implementation Tasks (ordered by dependencies)

```yaml
Task 1: READ the cited research + the two insertion anchors (NO writes)
  - READ: plan/004_2c5127285a90/P3M2T1S1/research/pane_geometry_snapshot_findings.md (THIS task's synthesis — FIRST)
  - READ: scripts/state.sh (ORIG_* block lines ~54-62 incl. ORIG_LAYOUT + ORIG_WINDOW_SIZE; clear_all_state's grep loop)
  - READ: scripts/livepicker.sh activate_main STEP 2 (lines 173-175 SESSION/WINDOW/LAYOUT + line 176 the comment)
        and confirm STEP 2 precedes T3 (the status grow, ~line 232)
  - READ: scripts/utils.sh lp_client_format (the client-aware resolver)
  - READ (context only): scripts/restore.sh STEP 5 (the ORIG_LAYOUT select-layout — the consumer; do NOT edit)
  - PURPOSE: internalize the two exact anchors, the format-string contract, the auto-clear (zero edit), the
        SAVED-STATE-vs-runtime distinction, and the pre-grow timing.

Task 2: MODIFY scripts/state.sh — add ORIG_PANE_GEOMETRY to the ORIG_* block
  - ADD: one line `readonly ORIG_PANE_GEOMETRY="@livepicker-orig-pane-geometry"` with an inline comment
        (PRD §9/§23; per-pane geometry of the original window; restore compares to detect drift; auto-cleared
        by clear_all_state's grep '@livepicker-orig-'), placed IMMEDIATELY AFTER ORIG_LAYOUT (line 56) and
        BEFORE ORIG_KEY_TABLE. It is the conceptual pair of ORIG_LAYOUT (same window, same capture moment).
  - FOLLOW pattern: ORIG_WINDOW_SIZE (readonly UPPER_SNAKE; inline comment citing PRD + the auto-clear note).
  - DO NOT: add ORIG_PANE_GEOMETRY to _STATE_RUNTIME_KEYS (it is SAVED-STATE, not runtime); DO NOT edit
        clear_all_state (its `grep '@livepicker-orig-'` heredoc loop already unsets every @livepicker-orig-*
        incl. this one — PRD §9 step 6 auto-clear is satisfied with zero code there).
  - NAMING: ORIG_PANE_GEOMETRY (UPPER_SNAKE matching the ORIG_* family); @livepicker-orig-pane-geometry
        (matches the @livepicker-orig- grep prefix; hyphenated per the @-option convention).
  - PLACEMENT: scripts/state.sh, ORIG_* block, right after ORIG_LAYOUT.

Task 3: MODIFY scripts/livepicker.sh activate_main STEP 2 — capture the geometry snapshot
  - INSERT: one capture line in STEP 2, IMMEDIATELY AFTER line 175 (the ORIG_LAYOUT capture) and BEFORE
        line 176 (the "# Three ordinary option reads" comment). Add a P3.M2.T1.S1 comment citing PRD §9/§23
        (the snapshot is the drift-detection baseline; restore acts only on drift; pre-grow; format contract).
  - IMPLEMENT (verbatim — see Implementation Patterns below):
        tmux set-option -g "$ORIG_PANE_GEOMETRY" "$(tmux list-panes -t "$(lp_client_format '#{window_id}')" -F '#{pane_id}:#{pane_left},#{pane_top},#{pane_width},#{pane_height}' 2>/dev/null)"
  - DEPENDENCIES: ORIG_PANE_GEOMETRY (Task 2). ORIG_WINDOW is already saved on line 174 (the target window).
        lp_client_format is sourced (utils.sh, sourced before state.sh at the top of livepicker.sh).
  - FOLLOW pattern: the STEP 2 display-message captures (`tmux set-option -g "$ORIG_X" "$(lp_client_format ...)"`).
        House style: NO set -e (guard the list-panes with 2>/dev/null); TABS for indent; the format string
        is SINGLE-QUOTED (literal `#{...}` — tmux expands it, not bash).
  - GOTCHA: the target `$(lp_client_format '#{window_id}')` yields the @N id directly — do NOT prepend @.
        The equivalent reuse form `$(get_state "$ORIG_WINDOW" "")` is acceptable (same @N, one show-option
        fork instead of one display-message fork); the contract literal is preferred.
  - UPDATE in-code comments: note STEP 2 now saves the pane-geometry snapshot per PRD §9 bullet 2 (paired
        with ORIG_LAYOUT), consumed by restore STEP 5 (P3.M2.T1.S2) for drift-gated restore (§23).

Task 4: VALIDATE (see Validation Loop) — shellcheck + ad-hoc round-trip + full suite regression.
  - The formal §23 test suite is P3.M3.T1's deliverable (a SEPARATE task). This task validates via
        shellcheck + a Level 2 ad-hoc round-trip probe (capture at activate; assert multi-line; assert
        cleared after cancel) + the existing suite (Level 3) + non-pollution (Level 4).
```

### Implementation Patterns & Key Details

```bash
# === Edit A: scripts/state.sh — ORIG_* block (insert after ORIG_LAYOUT, before ORIG_KEY_TABLE) ===
readonly ORIG_SESSION="@livepicker-orig-session"
readonly ORIG_WINDOW="@livepicker-orig-window"                         # window ID, NOT index
readonly ORIG_LAYOUT="@livepicker-orig-layout"                         # window_layout string
readonly ORIG_PANE_GEOMETRY="@livepicker-orig-pane-geometry"           # per-pane geometry of the original window (PRD §9/§23); restore compares to detect drift, acts only if changed (Invariant C); auto-cleared by clear_all_state's grep '@livepicker-orig-'
readonly ORIG_KEY_TABLE="@livepicker-orig-key-table"
# ... (rest of the ORIG_* block unchanged) ...

# === Edit B: scripts/livepicker.sh activate_main STEP 2 (insert after ORIG_LAYOUT, before the option reads) ===
	tmux set-option -g "$ORIG_SESSION" "$(lp_client_format '#{session_name}')"
	tmux set-option -g "$ORIG_WINDOW"   "$(lp_client_format '#{window_id}')"      # @N id, NOT index
	tmux set-option -g "$ORIG_LAYOUT"   "$(lp_client_format '#{window_layout}')"
	# P3.M2.T1.S1 (PRD §9 bullet 2 / §23): per-pane geometry snapshot of the ORIGINAL window.
	# Restore (STEP 5, P3.M2.T1.S2) re-captures the current geometry with the IDENTICAL format and
	# compares to this snapshot — equal => no-op (leave the window untouched, the §23-preferred path);
	# differ => act (resize-pin size-first, then restore). Captured BEFORE the T3 status grow, so it
	# is the true pre-mutation baseline. FORMAT IS THE CONTRACT with restore: do NOT change/sort it.
	# set-option -g stores the multi-line list-panes output verbatim (newlines preserved, like STATE_LIST).
	tmux set-option -g "$ORIG_PANE_GEOMETRY" "$(tmux list-panes -t "$(lp_client_format '#{window_id}')" -F '#{pane_id}:#{pane_left},#{pane_top},#{pane_width},#{pane_height}' 2>/dev/null)"
	# Three ordinary option reads (orig_name == src_name -> tmux_save_opt idiom).
	tmux_save_opt key-table key-table
# ... (rest of STEP 2 + T2/T3/... unchanged) ...

# GOTCHA (target): `$(lp_client_format '#{window_id}')` yields the @N id of the original window (the same
#   @N ORIG_WINDOW holds). Do NOT write `-t "@$(lp_client_format ...)"` (-> @@N, rc=1). The equivalent
#   reuse `$(get_state "$ORIG_WINDOW" "")` is acceptable (same @N, one show-option fork).
# GOTCHA (format): the single-quoted `'#{...}'` is literal to bash; tmux's list-panes expands the format
#   specifiers. Keep the EXACT separators (`:` then `,`,`,`,`) — the consumer string-compares byte-for-byte.
# GOTCHA (auto-clear): ORIG_PANE_GEOMETRY is SAVED-STATE. clear_all_state's grep already unsets it. Do NOT
#   add it to _STATE_RUNTIME_KEYS and do NOT hand-clear it.
```

### Integration Points

```yaml
STATE CONTRACT (PRD §9):
  - add to saved-state set: ORIG_PANE_GEOMETRY="@livepicker-orig-pane-geometry" (written activate STEP 2,
    read restore STEP 5 by P3.M2.T1.S2).
  - auto-clear: satisfied with ZERO code — clear_all_state's `grep '@livepicker-orig-'` heredoc loop
    already unsets every @livepicker-orig-*. Do NOT add it to _STATE_RUNTIME_KEYS.
  - PRD §9 save list (bullet 2): now includes "a pane-geometry snapshot" alongside window_layout — the
    capture line implements it (paired with ORIG_LAYOUT, captured at the same STEP-2 moment).

CONSUMER (P3.M2.T1.S2 — restore STEP 5, NOT this task):
  - re-capture the original window's current geometry with the IDENTICAL format
    ('#{pane_id}:#{pane_left},#{pane_top},#{pane_width},#{pane_height}'), string-compare to ORIG_PANE_GEOMETRY;
    equal => no-op; differ => act. Per pane_immutability_verification.md §3 (the gate P3.M1.T1.S1 produces),
    the "act" path is resize-window -y H_orig (size-first), NOT a bare select-layout.

GATE (P3.M1.T1.S1 — running in parallel):
  - produces pane_immutability_verification.md which CORRECTS the restore recipe (resize-pin not select-layout).
    This task does NOT depend on the gate's verdict — it only WRITES the snapshot the consumer will compare.
    If the gate finds snapshot-based drift detection infeasible for some edge, the snapshot remains a harmless
    no-op input (restore reads it; if it never acts, fine). So this task is NOT blocked by the gate.

OUT OF SCOPE (do NOT implement here):
  - restore-side drift comparison + resize-pin/restore (P3.M2.T1.S2).
  - candidate-window pin at link time (P3.M2.T2, conditional on the gate).
  - the §23 test suite (P3.M3.T1).
  - clear_all_state / _STATE_RUNTIME_KEYS edits, restore.sh/preview.sh edits, PRD/README/CHANGELOG edits.
```

## Validation Loop

### Level 1: Syntax & Style (Immediate Feedback)

```bash
cd /home/dustin/.config/tmux/plugins/tmux-livepicker
# shellcheck the two modified files (both already pass; your edits must keep them clean).
shellcheck scripts/state.sh scripts/livepicker.sh
# Expected: zero NEW errors. The new readonly ORIG_PANE_GEOMETRY is covered by state.sh's file-wide
# SC2034 disable; the `#{...}` in single quotes is literal bash (not flagged). No new directive needed.
bash -n scripts/state.sh && bash -n scripts/livepicker.sh   # syntax sanity (no side effects on source)
# Expected: no syntax errors. Sourcing state.sh prints nothing (sourced-library contract).
# Confirm the new constant + the grep-prefix:
grep -n 'ORIG_PANE_GEOMETRY' scripts/state.sh                       # the readonly line, after ORIG_LAYOUT
grep -n '@livepicker-orig-pane-geometry' scripts/state.sh           # matches clear_all_state's grep
grep -n 'ORIG_PANE_GEOMETRY' scripts/livepicker.sh                  # the STEP 2 capture line
```

### Level 2: Ad-hoc round-trip through the REAL activate path

The formal §23 test suite is **P3.M3.T1** (a separate task). This task verifies the capture directly via the
harness + the real `livepicker.sh`/`restore.sh`, in the shape the consumer will rely on:

```bash
cd /home/dustin/.config/tmux/plugins/tmux-livepicker
source tests/setup_socket.sh
setup_socket "lp-geom-verify-$$"; attach_test_client
# the baseline driver has a multi-pane "extra" window (setup_socket creates it) — good for the snapshot.
# drive the REAL activate (writes ORIG_PANE_GEOMETRY in STEP 2):
"$LIVEPICKER_SCRIPTS/livepicker.sh" >/dev/null
# ASSERT: the snapshot is populated, multi-line, one line per pane, in the pinned format.
snap="$(tmux show-option -gqv @livepicker-orig-pane-geometry)"
[ -n "$snap" ] && echo "snapshot populated OK" || echo "snapshot EMPTY — FAIL"
# re-capture the CURRENT geometry with the IDENTICAL format and compare byte-for-byte (the consumer's test):
AW="$(tmux list-windows -t "=$TEST_DRIVER_SESSION" -F '#{window_id}' -f '#{window_active}')"
cur="$(tmux list-panes -t "$AW" -F '#{pane_id}:#{pane_left},#{pane_top},#{pane_width},#{pane_height}')"
[ "$snap" = "$cur" ] && echo "snapshot == current geometry (byte-identical, no drift at activate) OK" \
                      || echo "snapshot != current — FAIL (format mismatch or wrong window targeted)"
# line count sanity: snapshot lines == pane count
n_lines="$(printf '%s\n' "$snap" | grep -c .)"
n_panes="$(tmux list-panes -t "$AW" | grep -c .)"
[ "$n_lines" = "$n_panes" ] && echo "snapshot has one line per pane ($n_panes) OK" || echo "line count mismatch — FAIL"
# ASSERT: the snapshot is cleared on cancel (clear_all_state's grep auto-clears it).
"$LIVEPICKER_SCRIPTS/input-handler.sh" cancel >/dev/null
[ -z "$(tmux show-option -gqv @livepicker-orig-pane-geometry 2>/dev/null)" ] && echo "snapshot cleared on exit OK" \
    || echo "snapshot residue after cancel — FAIL (clear_all_state grep must unset it)"
teardown_socket
unset -f setup_socket teardown_socket attach_test_client
# Expected: populated + byte-identical re-capture + one-line-per-pane + cleared on exit.
# If the snapshot is EMPTY: the capture line did not run in STEP 2 — recheck Task 3 placement (after ORIG_LAYOUT).
# If snapshot != current: the format string or the target window differs from the consumer's re-capture — they
#   MUST be byte-identical (the format is the contract).
```

### Level 3: Regression — existing suite stays green

```bash
cd /home/dustin/.config/tmux/plugins/tmux-livepicker
bash tests/run.sh
# Expected: exit 0, all PASS. KEY suites to eyeball:
#   - test_restore.sh: byte-exact restore of status/status-format/key-table/hooks/window-size is UNBROKEN
#     (the new key is saved-state; it round-trips empty after clear — no residue).
#   - test_pollution.sh: browsing fires no client-session-changed (unchanged by this task).
#   - test_preview_clip.sh: the §22 clip freeze/restore still works (ORIG_WINDOW_SIZE untouched).
#   - test_window_flip.sh: window-cursor/flip still works (this task adds a save only, no behavior change).
# If test_restore byte-exact assertions now FAIL: a stale ORIG_PANE_GEOMETRY survived clear_all_state ->
#   impossible (it matches the grep), so investigate whether the key name was mistyped (must be @livepicker-orig-*).
```

### Level 4: Non-pollution (the core invariant, PRD §15)

```bash
cd /home/dustin/.config/tmux/plugins/tmux-livepicker
BEFORE="$(/usr/bin/tmux list-sessions -F '#{session_name}' 2>/dev/null | sort)"
bash tests/run.sh >/dev/null 2>&1
AFTER="$(/usr/bin/tmux list-sessions -F '#{session_name}' 2>/dev/null | sort)"
[ "$BEFORE" = "$AFTER" ] && echo "REAL SERVER UNTOUCHED" || echo "POLLUTION — abort"
# Expected: REAL SERVER UNTOUCHED. The snapshot is an isolated-socket @-option write only.
```

### Level 5: Creative & Domain-Specific Validation

```bash
cd /home/dustin/.config/tmux/plugins/tmux-livepicker
# Confirm the new key is an ORIG_* (saved-state), NOT in _STATE_RUNTIME_KEYS:
grep -n 'ORIG_PANE_GEOMETRY' scripts/state.sh                       # present in the ORIG_* block
! grep -q 'ORIG_PANE_GEOMETRY' <<<"$(sed -n '/_STATE_RUNTIME_KEYS=/p' scripts/state.sh)" \
  && echo "ORIG_PANE_GEOMETRY correctly ABSENT from _STATE_RUNTIME_KEYS" \
  || echo "FAIL: ORIG_PANE_GEOMETRY must NOT be in _STATE_RUNTIME_KEYS"
# Confirm clear_all_state was NOT hand-edited for the new key (the grep auto-clears it):
! grep -q 'pane-geometry' scripts/state.sh <<<"$(sed -n '/clear_all_state/,/^}/p' scripts/state.sh)" \
  && echo "clear_all_state unchanged (auto-clear via grep) OK" || echo "FAIL: do NOT hand-clear in clear_all_state"
# Confirm the format string matches the consumer's expected shape (pane_id:left,top,width,height):
grep -n "pane_id}:#{pane_left},#{pane_top},#{pane_width},#{pane_height}" scripts/livepicker.sh   # the capture line
# Expected: the capture line present; the key absent from _STATE_RUNTIME_KEYS; clear_all_state unchanged.
```

## Final Validation Checklist

### Technical Validation
- [ ] Level 1: `shellcheck scripts/state.sh scripts/livepicker.sh` clean (no new errors); `bash -n` passes.
- [ ] Level 2: snapshot populated at activate; byte-identical to a re-capture with the SAME format; one line per pane; cleared on cancel.
- [ ] Level 3: `bash tests/run.sh` exit 0 (test_restore byte-exact + pollution + clip + flip suites green).
- [ ] Level 4: real tmux server byte-identical before/after (PRD §15).
- [ ] Level 5: key in the ORIG_* block; absent from _STATE_RUNTIME_KEYS; clear_all_state unchanged; format line present.

### Feature Validation
- [ ] `ORIG_PANE_GEOMETRY` is a readonly constant in state.sh's ORIG_* block, right after ORIG_LAYOUT, auto-cleared by clear_all_state's grep (zero edit there).
- [ ] livepicker.sh STEP 2 captures the original window's per-pane geometry AFTER ORIG_LAYOUT and BEFORE the T3 status grow, in the pinned format.
- [ ] The snapshot targets the original window (client-aware @N == ORIG_WINDOW) and stores the multi-line list-panes output verbatim (newlines preserved).
- [ ] The snapshot is the PRE-GROW baseline (STEP 2 precedes T3) — correct for restore drift detection.
- [ ] NO restore-side drift logic, NO candidate pin, NO test file, NO clear_all_state/_STATE_RUNTIME_KEYS edit (all out of scope).

### Code Quality Validation
- [ ] Mirrors ORIG_WINDOW_SIZE's readonly+inline-comment style (1 line; PRD §9/§23 + auto-clear note).
- [ ] Mirrors the STEP 2 display-message capture idiom (`tmux set-option -g "$ORIG_X" "$(...)"`).
- [ ] No `set -e` added (house style); the list-panes guarded with `2>/dev/null` (no `|| true` needed under no -e).
- [ ] The format string is single-quoted (literal `#{...}`); separators byte-exact (`:` then `,`,`,`,`) — the consumer contract.
- [ ] TABS for indent; the new const's SC2034 is covered by the existing file-wide disable (no new directive).

### Documentation & Deployment
- [ ] The STEP 2 comment cites PRD §9 bullet 2 / §23 + notes the format is a contract with restore (P3.M2.T1.S2) + the pre-grow timing.
- [ ] state.sh const comment cites PRD §9/§23 + the auto-clear.
- [ ] PRD.md, README.md, CHANGELOG.md, restore.sh, preview.sh, clear_all_state, _STATE_RUNTIME_KEYS, and any tasks.json UNMODIFIED.

---

## Anti-Patterns to Avoid

- ❌ Don't implement the drift comparison / resize-pin restore in restore.sh — that is P3.M2.T1.S2. This task only WRITES the snapshot the consumer compares.
- ❌ Don't implement the candidate-window pin in preview.sh — that is P3.M2.T2 (gated by P3.M1.T1.S1). This task touches neither preview.sh nor candidate windows.
- ❌ Don't change the format string or sort the list-panes output. The format `'#{pane_id}:#{pane_left},#{pane_top},#{pane_width},#{pane_height}'` is a CONTRACT: P3.M2.T1.S2 re-captures with the IDENTICAL format and string-compares. Unsorted is correct (catches both resize and reorder). Any change desyncs the two halves.
- ❌ Don't add ORIG_PANE_GEOMETRY to `_STATE_RUNTIME_KEYS` or hand-clear it in `clear_all_state`. It is SAVED-STATE; the existing `grep '@livepicker-orig-'` loop already unsets it (zero code there — mirror ORIG_WINDOW_SIZE).
- ❌ Don't prepend `@` to the list-panes target. `$(lp_client_format '#{window_id}')` already yields `@N`; write `-t "$(lp_client_format '#{window_id}')"`, never `-t "@$(...)"` (→ `@@N`, rc=1).
- ❌ Don't join/sed/sort the multi-line list-panes output. `set-option -g` preserves embedded newlines (the STATE_LIST precedent); `get_state` reads the full multi-line value back. Store it verbatim.
- ❌ Don't add `|| true` inside the `$(...)` — under house `set -u` (NO `set -e`) a failing list-panes yields empty stdout (stored as "" → restore's get_state default handles it as "no snapshot" → no-op). The contract's `2>/dev/null` is sufficient.
- ❌ Don't capture the geometry AFTER the T3 status grow. STEP 2 runs before T3; the snapshot must be the PRE-GROW, pre-mutation baseline (that is the whole point of drift detection). Insert after ORIG_LAYOUT (line 175), not later.
- ❌ Don't target the wrong window. The snapshot is of the ORIGINAL window (the driver's active window at activate == ORIG_WINDOW). `lp_client_format '#{window_id}'` resolves it (same @N as ORIG_WINDOW). Do NOT capture a candidate or the active-after-nav window.
- ❌ Don't write the formal §23 test suite — that is P3.M3.T1. This task validates via shellcheck + the Level 2 ad-hoc round-trip + the existing suite.
- ❌ Don't touch PRD.md, README.md, CHANGELOG.md, restore.sh, preview.sh, clear_all_state, _STATE_RUNTIME_KEYS, or any tasks.json (all read-only / owned elsewhere). This task edits ONLY scripts/state.sh + scripts/livepicker.sh.
- ❌ Don't block on the P3.M1.T1.S1 gate. This task only WRITES the snapshot; the gate's verdict informs the consumer's restore recipe (P3.M2.T1.S2), not whether the snapshot should be captured. If the gate later finds drift detection infeasible for an edge, the snapshot is a harmless no-op input.

---

## Confidence Score: 9/10

This is a small, surgical task: one readonly constant (mirroring an exact existing precedent, ORIG_WINDOW_SIZE) + one capture line (mirroring the exact STEP 2 idiom, `tmux set-option -g "$ORIG_X" "$(...)"`), with the format string pinned by the contract and the auto-clear proven (the grep already covers it). The insertion anchors are verbatim from the live code (state.sh line 56; livepicker.sh line 175→176), the newlines-preserved behavior is established by STATE_LIST, and the SC2034 disable already covers the new const. The residual 1/10 is: (a) confirming the multi-pane baseline window in the harness produces a non-empty multi-line snapshot (Level 2 asserts it); (b) the consumer-contract risk — if P3.M2.T1.S2's re-capture uses a subtly different format/target, the comparison fails, so this PRP pins the format byte-exact and the Level 2 probe re-captures with the identical string to prove they match today. The implementer's job is to add a constant + a line in two exact spots — not to discover tmux behavior or design the drift logic.
