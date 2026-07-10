name: "P3.M2.T1.S2 — Drift-gated restore in restore.sh STEP 5 (PRD §9 step 5 / §23 Invariant C)"
description: Implementation work item (PRD §9 restore step 5 + §23 Prevention-regime bullet 3). Replace the UNCONDITIONAL `select-layout "$ORIG_LAYOUT"` in `scripts/restore.sh` STEP 5 (current lines 222-233) with a DRIFT-GATED, CANCEL-ONLY restore that reads the `ORIG_PANE_GEOMETRY` snapshot (produced by P3.M2.T1.S1), re-captures the original window's CURRENT geometry with the IDENTICAL unsorted format, string-compares, and acts ONLY on drift: equal → no-op (the §23-preferred common case — leave the panes untouched); differ → restore the window's size first (`resize-window -y H_orig`, deterministic per the P3.M1.T1.S1 gate §3 / ARM C2 — NOT a bare select-layout), THEN `select-layout "$ORIG_LAYOUT"` as belt-and-suspenders. keep/keep-window SKIP STEP 5 entirely (client is on the chosen target, not the original window). H_orig is DERIVED from the snapshot (`max(pane_top+pane_height)`, == the pre-activate window height the §22 clip also used) — no new state key. SCOPE = restore.sh ONLY (one file, one block + 3 locals). The snapshot capture is P3.M2.T1.S1; the candidate pin is P3.M2.T2; the §23 test suite is P3.M3.T1.

---

## Goal

**Feature Goal**: Make restore-time pane-layout repair on the original window **conditional on actual drift**, so the common case (browsing left the original window's panes untouched) does NOT run `select-layout` at all — eliminating the §23-identified risk that `select-layout` (size-dependent) itself moves panes. PRD §9 step 5 + §23 require: "compare the original window's current pane geometry to the activation snapshot. If it is unchanged, do nothing (the common case). Only if it drifted: restore the window's exact size first, then select-layout." restore.sh STEP 5 today does an UNCONDITIONAL `select-layout "$ORIG_LAYOUT"` (current lines 222-233) — this task closes that gap using the `ORIG_PANE_GEOMETRY` snapshot P3.M2.T1.S1 captures.

**Deliverable**: ONE edited file — `scripts/restore.sh`. Two surgical changes:
1. Add 3 locals (`saved_geom cur_geom h_orig`) to the `restore_main` local declaration (line 57).
2. Replace the STEP 5 block (current lines 222-233) with a cancel-only drift gate: read snapshot → re-capture current geometry (identical unsorted format) → compare → no-op on match / size-first repair (`resize-window -y H_orig` derived from the snapshot) + `select-layout "$ORIG_LAYOUT"` on drift. keep/keep-window skip STEP 5 entirely.

**Success Definition**: After this task, on a real `activate → (browse or not) → cancel` cycle with an attached client: (a) when the original window did NOT drift, `select-layout` is NOT called and the panes are byte-identical to pre-activate (the §23-preferred no-op); (b) when the original window DID drift (induced), `resize-window -y H_orig` then `select-layout` restore the layout byte-identical; (c) `keep`/`keep-window` perform NO layout restore on the original window. The existing `tests/run.sh` stays green — in particular `test_restore.sh::test_restore_cancel_layout_exact` (the byte-exact layout assertion) continues to pass. `bash tests/run.sh` exit 0; real tmux server byte-identical before/after (PRD §15).

## User Persona

**Target User**: The end user running tmux-livepicker on a real attached client, plus the P3.M3.T1 test author who will assert §23 byte-identical pane geometry across a browse→cancel cycle, and the PRD §23 reviewer for whom "no pane ever moves" is an absolute invariant.

**Use Case**: User opens the picker, browses/preview several sessions/windows, then cancels (or confirms). On cancel, the driver's original window — which the §22 clip froze — must be returned to its EXACT pre-activation pane geometry. Today restore always runs `select-layout`, which is size-dependent and can itself perturb panes; this task makes restore leave the window ALONE unless it actually drifted, and only then repair it (size-first, the reliable path).

## Why

- **PRD §23 (Invariant C, absolute)** + §9 step 5: restore-time `select-layout` "must be a no-op whenever the original window did not actually drift (compare the pane-geometry snapshot captured at activation). Only if drift is detected: restore the window's exact size first, then select-layout. Leaving the window untouched is always preferable to moving its panes." The unconditional `select-layout` today violates the "always preferable to leave it untouched" directive whenever the window did not drift (the dominant case under the §22 clip). This task implements the comparison + conditional act.
- **The gate (P3.M1.T1.S1 — COMPLETE) CORRECTS the repair recipe**: `candidate_pin_probe_findings.md` §3 / ARM C2 proved empirically that `resize-window -y H_orig` (size-first) restores the EXACT multi-pane layout byte-for-byte, whereas a bare `select-layout` is size-dependent and unreliable ("§23's 'select-layout failed' is about select-layout, not this"). So the drift path must be **resize-window -y H_orig FIRST, then select-layout** — not the naive "just select-layout". This task encodes that corrected recipe.
- **Integration with existing features**: STEP 2 (P2.M2.T2) already made the cancel path re-select ORIG_WINDOW (active), and already SKIPS that re-select for keep/keep-window. The §22 clip (livepicker.sh T3) already pins the driver height + `window-size manual`, and restore STEP 4 already undoes that pin + restores status. So at STEP 5 the window has reflowed back to its baseline — the drift gate is the last, conditional pane-geometry safeguard.

## What

No user-visible behavior change in the common (no-drift) case — restore already returned the window to its layout via select-layout, and this task returns it by NOT touching it (same end state, safer mechanism). The change is internal restore behavior:
- **cancel**: STEP 5 compares the snapshot to the re-captured geometry; on no-drift it is a pure no-op (no tmux command fires); on drift it runs `resize-window -y H_orig` then `select-layout "$ORIG_LAYOUT"`.
- **keep / keep-window**: STEP 5 is skipped entirely (no layout restore on the original window — the client is on the chosen target).

### Success Criteria

- [ ] restore.sh STEP 5 reads `ORIG_PANE_GEOMETRY` (the P3.M2.T1.S1 snapshot) and re-captures the current geometry of `$orig_window` with the IDENTICAL unsorted format `'#{pane_id}:#{pane_left},#{pane_top},#{pane_width},#{pane_height}'`, byte-string-compares them.
- [ ] On match (no drift): STEP 5 runs NO `select-layout` and NO `resize-window` (pure no-op).
- [ ] On drift (mismatch): STEP 5 restores size first (`resize-window -y H_orig -t "$orig_window"`, H_orig derived from the snapshot as `max(pane_top+pane_height)`), THEN `select-layout "$orig_layout"`. Both best-effort (`2>/dev/null || true`).
- [ ] The entire STEP 5 drift block is gated on `mode == cancel`; keep/keep-window execute NO part of it.
- [ ] Empty snapshot → falls through to the drift/restore path (no silent regression vs the pre-PRP always-restore behavior for that edge).
- [ ] `bash tests/run.sh` exit 0; `test_restore_cancel_layout_exact` stays green (byte-exact layout after cancel).
- [ ] `shellcheck scripts/restore.sh` reports no new errors; real tmux server byte-identical before/after.

## All Needed Context

### Context Completeness Check

_"If someone knew nothing about this codebase, would they have everything needed to implement this successfully?"_ — Yes. This PRP pins: the exact replacement block (verbatim, with the 3-local declaration edit), the format-string contract (do not change/sort it), the H_orig derivation (awk field map + why it must come from the snapshot not a live read), the mode gate (cancel-only; why keep skips), the §23 "resize-window forbidden during preview vs sanctioned at restore" reconciliation, the load-bearing regression analysis (why test_restore_cancel_layout_exact stays green in BOTH no-drift and drift cases), the STEP-2-active-window invariant (select-layout targets ORIG_WINDOW for cancel), the ordering (STEP 5 reads before STEP 6 clear_all_state), and the exact validation probes (shellcheck + an isolated-socket no-drift/drift round-trip + the existing suite + non-pollution).

### Documentation & References

```yaml
# MUST READ — load into the context window before editing.

- file: plan/004_2c5127285a90/P3M2T1S2/research/drift_gated_restore_findings.md
  why: THIS task's synthesis — the exact replacement, the mode gate, the H_orig derivation,
        the §23 reconciliation, the regression-risk analysis, and the gotchas. Read FIRST.
  section: "§1 the replacement; §3 H_orig; §4 §23 reconciliation; §5 format contract; §7 regression"

- file: scripts/restore.sh          # the ONLY file this task edits
  why: STEP 5 (current lines 222-233) is the block to REPLACE; line 57 is the `local` decl to
        EXTEND with 3 names. STEP 2 (lines ~96-104) sets orig_window + select-window for cancel;
        STEP 3 (~114) sets mode; STEP 4 (~120-218) restores status/window-size; STEP 6 (~235+)
        runs clear_all_state AFTER STEP 5. Header `disable=SC1091,SC2153` covers ORIG_* consts.
  pattern: "local linked_id orig_window ... orig_layout lp_rfit_ws   # line 57 — add saved_geom cur_geom h_orig"
  gotcha: "restore.sh is its OWN process under run-shell -> it sources its own options/utils/state
        trio at the top (lines 39-46). ORIG_PANE_GEOMETRY (from state.sh, added by P3.M2.T1.S1) is
        in scope once state.sh is sourced. No `set -e` (only `set -u`); every tmux call that can
        legitimately rc=1 is guarded `2>/dev/null || true` — mirror that exactly."

- file: scripts/state.sh            # READ-ONLY — the contract source
  why: ORIG_PANE_GEOMETRY (added by P3.M2.T1.S1, after ORIG_LAYOUT ~line 61), ORIG_WINDOW,
        ORIG_LAYOUT constants + get_state/set_state accessors + clear_all_state (auto-unsets
        every @livepicker-orig-* via grep). Confirms ORIG_PANE_GEOMETRY is still readable in
        STEP 5 (clear_all_state is STEP 6, AFTER).
  pattern: "readonly ORIG_PANE_GEOMETRY=\"@livepicker-orig-pane-geometry\"   # (P3.M2.T1.S1)"
  gotcha: "Do NOT add anything to state.sh for this task. ORIG_PANE_GEOMETRY already exists once
        P3.M2.T1.S1 lands (it is the parallel contract this task consumes)."

- file: plan/004_2c5127285a90/P3M2T1S1/research/pane_geometry_snapshot_findings.md
  why: the FORMAT CONTRACT. P3.M2.T1.S1 WRITES the snapshot as one line per pane
        `'#{pane_id}:#{pane_left},#{pane_top},#{pane_width},#{pane_height}'` UNSORTED. This task
        RE-CAPTURES with the IDENTICAL format and byte-compares. Any change (separator / field
        order / sort) desyncs the two halves -> false drift -> unneeded resize+select-layout.
  section: "§3 the format is a contract (do not change it); §5 target resolution"

- file: plan/004_2c5127285a90/P3M1T1S1/research/candidate_pin_probe_findings.md
  why: the gate (COMPLETE) that CORRECTS the restore recipe. §3 / ARM C2: `resize-window -y H_orig`
        restores the EXACT multi-pane layout byte-for-byte; a bare `select-layout` is
        size-dependent and unreliable. So the drift path is resize-FIRST then select-layout.
        Also reconciles §23's "resize-window forbidden" list (that is PREVIEW-scoped; restore-time
        drift repair is the sanctioned exception — PRD §9 step 5 / §23 explicitly require it).
  section: "§3 reversibility (resize-window -y H_orig); §5 confirmed recipes; §7 recommendation #4"

- file: scripts/livepicker.sh       # READ-ONLY — the §22 clip + snapshot-timing proof
  why: lines 173-175 = STEP 2 saves ORIG_SESSION/WINDOW/LAYOUT (P3.M2.T1.S1 inserts the
        ORIG_PANE_GEOMETRY capture right after, pre-grow). Lines 324-333 = the T3 clip:
        `set-option -t "$sess" window-size manual` + `resize-window -y "$lp_fit_pre_h" -t "$win"`
        where lp_fit_pre_h = `display-message -p '#{window_height}'` captured pre-grow. This
        proves H_orig derived from the snapshot (max top+height) == lp_fit_pre_h (both pre-grow).
  pattern: 'tmux resize-window -y "$lp_fit_pre_h" -t "$lp_fit_win" 2>/dev/null || true   # mirror this exactly'
  gotcha: "The §22 clip runs in T3, AFTER STEP 2. So the snapshot (STEP 2) is the PRE-CLIP,
        pre-grow baseline — exactly the geometry restore must compare against."

- file: tests/test_restore.sh       # READ-ONLY — the load-bearing regression guard
  why: test_restore_cancel_layout_exact asserts `#{window_layout}` byte-identical after
        activate→next-session→cancel. The OLD code held this via unconditional select-layout.
        This task's no-drift path holds it by NOT touching the window (the §22 clip + status
        round-trip keep W_orig at its baseline). See this PRP's regression analysis (§7 of the
        research file): the test passes in BOTH no-drift and drift cases.
  pattern: 'assert_eq "$(tmux display-message -p "#{window_layout}")" "$layout_before" "..."'
  gotcha: "If this test FAILS after the change, EITHER the snapshot/re-capture format differs
        (false drift -> unneeded repair, still byte-safe but investigate) OR a real §23 drift
        the gate must repair. Do NOT weaken the assert."

- file: PRD.md                      # READ-ONLY — the spec
  why: §9 restore step 5 (the drift-gated restore directive) + §23 Invariant C (pane
        immutability; "leaving the window untouched is always preferable to moving its panes";
        the forbidden-during-preview list vs the sanctioned restore-time repair) + §15.23.
  section: "§9 restore step 5; §23 'Prevention regime' bullet 3 + 'Forbidden during preview'; §15.23"

- url: https://github.com/tmux/tmux/blob/master/CHANGES  (list-panes / resize-window / select-layout semantics)
  why: confirms `list-panes -t @id -F '#{pane_id}:#{pane_left},#{pane_top},#{pane_width},#{pane_height}'`
        emits one line per pane in deterministic pane order (unsorted is a sound drift signal);
        `resize-window -y N -t @id` sets the window height to N rows (panes tile N completely so
        bottom-pane top+height == N == #{window_height}); `select-layout` (no -t) applies to the
        active window; set-option -g preserves embedded newlines in @-option values (round-trip).
  section: "list-panes -F specifiers; resize-window -y; select-layout active-window scoping"
```

### Current Codebase tree (run `ls scripts/ tests/` in the project root)

```bash
tmux-livepicker/
├── scripts/
│   ├── restore.sh      # <-- THE ONLY FILE THIS TASK EDITS (STEP 5 block + 3 locals in restore_main)
│   ├── state.sh        # ORIG_PANE_GEOMETRY lives here (added by P3.M2.T1.S1) — read-only for us
│   ├── livepicker.sh   # activate STEP 2 (snapshot capture, P3.M2.T1.S1) + T3 §22 clip — read-only
│   ├── utils.sh / options.sh / preview.sh / input-handler.sh / renderer.sh / layout.sh / rank.sh / session-mgmt.sh  # untouched
├── tests/
│   ├── test_restore.sh # test_restore_cancel_layout_exact — load-bearing regression guard (read-only)
│   ├── run.sh / setup_socket.sh / helpers.sh / test_*.sh  # untouched (P3.M3.T1 owns the §23 suite)
├── plan/004_2c5127285a90/
│   ├── P3M1T1S1/research/candidate_pin_probe_findings.md  # the gate (COMPLETE) — §3 sanctions resize-first
│   ├── P3M2T1S1/{PRP.md, research/pane_geometry_snapshot_findings.md}  # the snapshot contract (parallel)
│   └── P3M2T1S2/{PRP.md (THIS file), research/drift_gated_restore_findings.md}
├── PRD.md              # §9 step 5 / §23 / §15.23 (READ-ONLY)
└── README.md / CHANGELOG.md  (untouched — P4 owns changeset docs)
```

### Desired Codebase tree with files to be added and responsibility of file

```bash
# No NEW files. This task EDITS one existing file (its responsibility already exists):
scripts/restore.sh   # STEP 5 becomes drift-gated + cancel-only; restore_main gains 3 locals
# research/drift_gated_restore_findings.md already written (this PRP's synthesis)
```

### Known Gotchas of our codebase & tmux 3.6b

```bash
# CRITICAL for this task:

# 1. resize-window is §23-FORBIDDEN "during preview" but SANCTIONED at restore-time drift repair.
#    §23's forbidden list is PREVIEW-scoped; PRD §9 step 5 / §23 Prevention-regime bullet 3 explicitly
#    REQUIRE "restore the window's exact size first, then select-layout" on drift. The gate §3/ARM C2
#    proved resize-window -y H_orig is the RELIABLE repair (bare select-layout is size-dependent).
#    Do NOT be afraid to call resize-window in the drift branch — it is the prescribed repair.

# 2. H_orig must come from the SNAPSHOT, NOT a live display-message. At restore-after-drift the window
#    is at the WRONG (drifted) size; display-message -p '#{window_height}' would read that wrong size.
#    Derive H_orig = max(pane_top + pane_height) over the snapshot's panes (== pre-activate height ==
#    what the §22 clip captured via #{window_height} at the same pre-grow moment).

# 3. FORMAT IS THE CONTRACT. Re-capture cur_geom with the IDENTICAL single-quoted format
#    '#{pane_id}:#{pane_left},#{pane_top},#{pane_width},#{pane_height}', UNSORTED, byte-compared to
#    saved_geom. Unsorted catches BOTH a resize (dims change) AND a reorder (line order changes).
#    set-option -g preserved the multi-line snapshot verbatim (STATE_LIST precedent) -> the multi-line
#    byte-compare is sound. Do NOT sort either side (the §23 ASSERTION suite P3.M3.T1 sorts for ITS
#    own proof; the restore drift gate must NOT).

# 4. MODE GATE first and cheap. The whole STEP 5 drift block runs ONLY for mode==cancel. keep/keep-window
#    SKIP it entirely (the client is on the chosen target; STEP 2 already skipped the ORIG_WINDOW
#    re-select for keep). Put `if [ "$mode" = "cancel" ] && [ -n "$orig_window" ]; then` BEFORE any
#    list-panes fork so keep short-circuits with zero tmux round-trips.

# 5. ORIG_WINDOW is already ACTIVE for cancel (STEP 2 P2.M2.T2). `select-layout` (no -t) applies to
#    the active window == ORIG_WINDOW. Do NOT add a re-select-window in STEP 5 (redundant; fires an
#    event). resize-window -t "$orig_window" targets by @id explicitly (active-independent).

# 6. STEP 6 clear_all_state runs AFTER STEP 5. So get_state ORIG_PANE_GEOMETRY / ORIG_LAYOUT in STEP 5
#    still see the populated values (the old code already relied on this for ORIG_LAYOUT). Keep the
#    reads in STEP 5; do not move them after STEP 6.

# 7. NO `set -e` in restore.sh (only `set -u`). resize-window / select-layout / list-panes can rc=1
#    legitimately (vanished window, invalid layout, race). Guard every such call `2>/dev/null || true`
#    exactly as the existing STEP-5 select-layout does. A transient failure must NOT abort a
#    half-restored teardown.

# 8. Empty snapshot -> fall THROUGH to the restore path (no regression). If saved_geom is "" (older
#    activate pre-P3.M2.T1.S1, or a capture race), `[ -n "$saved_geom" ]` is false -> the no-drift
#    branch is skipped -> the else (drift/restore) branch runs (resize skipped since h_orig not
#    derivable from empty, then select-layout). This preserves the pre-PRP always-select-layout behavior
#    for that edge.

# 9. awk -F'[:,]' is the house idiom (preview.sh:183, input-handler.sh:471/521, session-mgmt.sh:168).
#    Snapshot line `%0:0,0,80,23` split on [:,] -> $1=%0 $2=left $3=top $4=width $5=height -> top+height
#    = $3+$5. H_orig = max($3+$5). `END{ print max+0 }` yields 0 for empty input (guarded upstream).

# 10. Add 3 new locals to the restore_main `local` declaration (line 57): saved_geom cur_geom h_orig.
#     House style = ONE `local` statement listing every local at the top of the function. Do not use
#     inline `local` (inconsistent with the file). TABS for indent throughout.

# 11. SC2153 already covered. restore.sh's header `# shellcheck disable=SC1091,SC2153` covers the
#     readonly ORIG_* CONTRACT constants from state.sh (incl. ORIG_PANE_GEOMETRY once P3.M2.T1.S1 lands).
#     The `#{...}` inside single quotes is literal bash (not flagged). No new shellcheck directive.
```

## Implementation Blueprint

No new data models — this task replaces one bash block in restore.sh and adds 3 locals. The "models" are the snapshot string (consumed read-only) and the derived H_orig integer.

### Data models and structure

```bash
# The snapshot (CONSUMED — written by P3.M2.T1.S1, e.g. for a 3-pane window):
#   %0:0,0,40,11
#   %1:40,0,40,11
#   %3:0,12,40,11
# Format per line: '#{pane_id}:#{pane_left},#{pane_top},#{pane_width},#{pane_height}' (unsorted).

# The re-capture at restore (cur_geom) uses the IDENTICAL format -> byte-comparable.
# H_orig (derived): max(pane_top + pane_height) over the snapshot = the pre-activate window height.
#   For the example above: max(0+11, 0+11, 12+11) = 23 -> resize-window -y 23.
```

### Implementation Tasks (ordered by dependencies)

```yaml
Task 1: READ the cited research + the exact replacement anchors (NO writes)
  - READ: plan/004_2c5127285a90/P3M2T1S2/research/drift_gated_restore_findings.md (THIS task's synthesis — FIRST)
  - READ: scripts/restore.sh — restore_main local decl (line 57) + STEP 5 (current lines 222-233) +
        STEP 2 (orig_window + cancel select-window) + STEP 3 (mode=) + STEP 4 (status/window-size restore)
        + STEP 6 (clear_all_state ordering). Header disable=SC1091,SC2153.
  - READ: plan/004_2c5127285a90/P3M1T1S1/research/candidate_pin_probe_findings.md §3 (resize-first recipe)
  - READ: plan/004_2c5127285a90/P3M2T1S1/research/pane_geometry_snapshot_findings.md §3 (format contract)
  - READ (context only): scripts/state.sh (ORIG_* block + get_state + clear_all_state), scripts/livepicker.sh
        lines 324-333 (the §22 clip resize-window pattern to mirror), tests/test_restore.sh
        (test_restore_cancel_layout_exact — the load-bearing regression guard).
  - PURPOSE: internalize the exact block to replace, the 3-local extension, the mode gate, the H_orig
        derivation, the format contract, the §23 reconciliation, and the regression analysis.

Task 2: MODIFY scripts/restore.sh — extend restore_main's local declaration (line 57)
  - ADD: `saved_geom cur_geom h_orig` to the existing `local linked_id orig_window ... orig_layout
        lp_rfit_ws` statement (keep it ONE local line; append the 3 names before the closing newline).
  - FOLLOW pattern: the existing single-statement local decl (house style; no inline `local`).
  - DO NOT: remove or reorder existing names; do not split into multiple `local` lines.
  - NAMING: saved_geom (the snapshot), cur_geom (the re-capture), h_orig (derived window height).
  - PLACEMENT: line 57, inside `restore_main()`, before STEP 1.

Task 3: MODIFY scripts/restore.sh — REPLACE the STEP 5 block (current lines 222-233)
  - REPLACE: the current STEP 5 block (the `# --- STEP 5 (PRD §9 restore step 5): ...` comment +
        `orig_layout="$(get_state "$ORIG_LAYOUT" "")"` + `[ -n "$orig_layout" ] && tmux select-layout ...`)
        with the drift-gated, cancel-only block in Implementation Patterns below.
  - IMPLEMENT (verbatim — see Implementation Patterns):
        * Mode gate: `if [ "$mode" = "cancel" ] && [ -n "$orig_window" ]; then ... fi` (no else).
        * Read orig_layout + saved_geom (get_state) inside the gate.
        * Re-capture cur_geom (tmux list-panes -t "$orig_window" -F '<identical format>' 2>/dev/null).
        * Compare: `[ -n "$saved_geom" ] && [ "$saved_geom" = "$cur_geom" ]` -> no-op `:` (no-drift).
        * Else (drift / empty-snapshot): derive h_orig via awk -F'[:,]' max($3+$5); if numeric>0,
          `tmux resize-window -y "$h_orig" -t "$orig_window" 2>/dev/null || true`; then
          `[ -n "$orig_layout" ] && tmux select-layout "$orig_layout" 2>/dev/null || true`.
  - DEPENDENCIES: ORIG_PANE_GEOMETRY (state.sh, from P3.M2.T1.S1), ORIG_WINDOW/ORIG_LAYOUT (existing),
        mode (STEP 3), orig_window (STEP 2). All in scope (restore.sh sources options/utils/state).
  - FOLLOW pattern: the existing best-effort guards (`2>/dev/null || true`); the §22 clip's
        `resize-window -y "$H" -t "$win" 2>/dev/null || true` (livepicker.sh line 333); the existing
        STEP-5 `[ -n "$orig_layout" ] && tmux select-layout ... || true`.
  - GOTCHA: re-capture format MUST be byte-identical to the snapshot's (single-quoted, unsorted);
        H_orig from the snapshot (NOT a live display-message); no re-select-window (ORIG_WINDOW active
        for cancel); keep skips the whole block.
  - UPDATE the STEP 5 comment to cite PRD §9 step 5 / §23, the gate (resize-first per P3.M1.T1.S1 §3),
        the mode gate (cancel-only; keep skips), the no-op-on-no-drift directive, and the format contract.

Task 4: VALIDATE (see Validation Loop) — shellcheck + isolated-socket no-drift/drift probe + full suite + non-pollution.
  - The formal §23 test suite is P3.M3.T1's deliverable (a SEPARATE task). This task validates via
        shellcheck + a Level 2 isolated-socket probe (no-drift no-op; induced-drift repair) + the
        existing suite (Level 3, esp. test_restore_cancel_layout_exact) + non-pollution (Level 4).
```

### Implementation Patterns & Key Details

```bash
# === Edit 1: scripts/restore.sh line 57 — extend the local declaration (append 3 names) ===
# BEFORE:
#	local linked_id orig_window current_session orig_session mode r_status r_kt r_renumber r_hook hk_line hk_idx hk_cmd r_cr_hook cr_line cr_idx cr_cmd orig_layout lp_rfit_ws
# AFTER (append saved_geom cur_geom h_orig — keep ONE local line):
	local linked_id orig_window current_session orig_session mode r_status r_kt r_renumber r_hook hk_line hk_idx hk_cmd r_cr_hook cr_line cr_idx cr_cmd orig_layout lp_rfit_ws saved_geom cur_geom h_orig

# === Edit 2: scripts/restore.sh — REPLACE the STEP 5 block (current lines 222-233) ===
# (Delete the current STEP 5 comment + orig_layout read + unconditional select-layout; insert:)

	# --- STEP 5 (PRD §9 restore step 5 / §23 Invariant C): DRIFT-GATED pane-geometry restore ---
	# P3.M2.T1.S2: replace the unconditional select-layout with a drift-gated, cancel-only restore.
	# select-layout is size-dependent and can itself MOVE panes, so it is a LAST RESORT, never
	# routine. The common case (no drift) leaves the panes UNTOUCHED — the §23-preferred no-op
	# ("leaving the window untouched is always preferable to moving its panes").
	#
	# MODE GATE (work-item §3d): only `cancel` runs the drift check. For keep/keep-window the client
	# is already on the chosen target (NOT the original window); the original window was never the
	# browse subject, and STEP 2 already SKIPPED re-selecting ORIG_WINDOW for keep (P2.M2.T2) — so
	# measuring/acting on it here would be wrong. keep/keep-window SKIP STEP 5 entirely.
	#
	# For cancel: STEP 2 already ran `select-window -t "$ORIG_WINDOW"`, so ORIG_WINDOW IS active
	# (select-layout below applies to the active window). Re-capture its CURRENT pane geometry with
	# the IDENTICAL format the activate snapshot used (P3.M2.T1.S1; FORMAT IS THE CONTRACT — do NOT
	# change/sort it) and byte-compare to ORIG_PANE_GEOMETRY:
	#   equal  -> NO DRIFT: leave the window untouched (the §23-preferred no-op; no tmux call).
	#   differ -> DRIFT: restore the window's exact SIZE first (`resize-window -y H_orig`; deterministic
	#             per the P3.M1.T1.S1 gate §3 / ARM C2 — NOT a bare select-layout, which is
	#             size-dependent and unreliable), THEN `select-layout "$ORIG_LAYOUT"` as
	#             belt-and-suspenders (PRD §9 step 5). H_orig is DERIVED from the snapshot:
	#             max(pane_top + pane_height) over all panes (== the pre-activate window height the
	#             §22 clip also captured via #{window_height} at the same pre-grow moment). Both calls
	#             BEST-EFFORT (`2>/dev/null || true`): a transient failure MUST NOT abort a
	#             half-restored teardown (no `set -e`). STEP 6 clear_all_state runs AFTER this, so
	#             ORIG_PANE_GEOMETRY / ORIG_LAYOUT are still readable here.
	# DEFENSIVE: an empty snapshot (older activate pre-P3.M2.T1.S1 / capture race) has no baseline to
	# compare -> fall through to the drift (restore) path so we do NOT regress the pre-PRP always-
	# restore behavior for that edge (resize is skipped — h_orig not derivable — then select-layout).
	if [ "$mode" = "cancel" ] && [ -n "$orig_window" ]; then
		orig_layout="$(get_state "$ORIG_LAYOUT" "")"
		saved_geom="$(get_state "$ORIG_PANE_GEOMETRY" "")"
		cur_geom="$(tmux list-panes -t "$orig_window" -F '#{pane_id}:#{pane_left},#{pane_top},#{pane_width},#{pane_height}' 2>/dev/null)"
		if [ -n "$saved_geom" ] && [ "$saved_geom" = "$cur_geom" ]; then
			: # NO DRIFT — the common case. Leave the original window's panes untouched (§23).
		else
			# DRIFT (or no snapshot — defensive). Restore size first, then select-layout.
			if [ -n "$saved_geom" ]; then
				# H_orig = max(pane_top + pane_height) over the snapshot's panes.
				# Snapshot line '#{pane_id}:#{pane_left},#{pane_top},#{pane_width},#{pane_height}'
				# -> awk -F'[:,]' fields: $1=id $2=left $3=top $4=width $5=height -> top+height = $3+$5.
				h_orig="$(printf '%s\n' "$saved_geom" | awk -F'[:,]' '{ h=$3+$5; if(h>max) max=h } END{ print max+0 }')"
				if [ -n "$h_orig" ] && [ "$h_orig" -gt 0 ] 2>/dev/null; then
					tmux resize-window -y "$h_orig" -t "$orig_window" 2>/dev/null || true
				fi
			fi
			[ -n "$orig_layout" ] && tmux select-layout "$orig_layout" 2>/dev/null || true
		fi
	fi
	# keep/keep-window: STEP 5 is intentionally a no-op (no else — no layout restore on the original).

# GOTCHA (mode gate): `mode` is set in STEP 3 (`mode="${1:-}"`); `orig_window` in STEP 2. Both in scope.
# GOTCHA (format): the single-quoted '#{...}' is literal to bash; tmux's list-panes expands it. The
#   separators (`:` then `,`,`,`,`) and field order MUST match P3.M2.T1.S1's capture byte-for-byte.
# GOTCHA (H_orig): do NOT read #{window_height} live — at restore-after-drift it is the WRONG size.
#   Derive from the snapshot (the pre-activate baseline) as above.
# GOTCHA (active window): for cancel ORIG_WINDOW is active (STEP 2); select-layout targets it. For
#   keep the block is skipped, so select-layout never runs on the wrong (target) window.
# GOTCHA (awk rc): `printf ... | awk` runs awk in a subshell; under no pipefail a failing awk yields
#   "" -> h_orig="" -> the `[ -n "$h_orig" ]` guard skips resize. Safe.
```

### Integration Points

```yaml
STATE CONTRACT (consumed read-only):
  - ORIG_PANE_GEOMETRY (P3.M2.T1.S1): the per-pane geometry snapshot, written activate STEP 2 (pre-grow),
    read restore STEP 5 (this task). One line per pane, format '#{pane_id}:#{pane_left},#{pane_top},
    #{pane_width},#{pane_height}', unsorted. Byte-compared to a same-format re-capture.
  - ORIG_WINDOW / ORIG_LAYOUT (existing): the @N id + the window_layout string. orig_layout is now read
    INSIDE the cancel gate (keep no longer needs it).
  - clear_all_state (STEP 6) auto-unsets ORIG_PANE_GEOMETRY via its grep '@livepicker-orig-' — runs AFTER
    STEP 5, so the reads succeed. NO change to state.sh / clear_all_state.

MODE GATE (P2.M2.T2 unification, consumed):
  - STEP 2 re-selects ORIG_WINDOW for cancel ONLY; keep/keep-window skip it. This task's STEP 5 mirrors
    that exactly: drift check runs for cancel ONLY; keep/keep-window skip STEP 5 entirely. STEP-2/STEP-5
    are a uniform cancel-only pair for the original-window handling.

§22 CLIP (consumed, read-only):
  - livepicker.sh T3 pins driver window-size manual + resize-window -y H0 (pre-grow height); restore
    STEP 4 undoes the pin + restores status. So at STEP 5 the window has reflowed to baseline ->
    cur_geom == saved_geom in the common (no-drift) case -> no-op. This task does NOT touch the clip.

OUT OF SCOPE (do NOT implement here):
  - The snapshot CAPTURE (P3.M2.T1.S1 — parallel; this task only READS it).
  - The candidate-window pin at link time (P3.M2.T2 — conditional on the gate, separate).
  - The formal §23 test suite (P3.M3.T1 — separate). This task validates via shellcheck + a Level 2
    isolated-socket probe + the existing suite + non-pollution.
  - Editing state.sh, livepicker.sh, preview.sh, options.sh, utils.sh, any test_*.sh, PRD.md,
    README.md, CHANGELOG.md, any tasks.json.
```

## Validation Loop

### Level 1: Syntax & Style (Immediate Feedback)

```bash
cd /home/dustin/.config/tmux/plugins/tmux-livepicker
# shellcheck the ONE modified file (it already passes; the edit must keep it clean).
shellcheck scripts/restore.sh
# Expected: zero NEW errors. The new ORIG_PANE_GEOMETRY reference is covered by the header
# disable=SC1091,SC2153 (readonly ORIG_* from state.sh). The `#{...}` in single quotes is literal
# bash (not flagged). awk in a pipe is fine (no pipefail in restore.sh). No new directive needed.
bash -n scripts/restore.sh    # syntax sanity (no side effects — restore_main is not invoked here)
# Expected: no syntax errors.
# Confirm the 3 new locals + the drift gate are present:
grep -n 'saved_geom cur_geom h_orig' scripts/restore.sh                 # the extended local decl (line 57)
grep -n 'ORIG_PANE_GEOMETRY' scripts/restore.sh                         # the snapshot read in STEP 5
grep -n 'resize-window -y' scripts/restore.sh                           # the size-first repair
grep -n 'saved_geom" = "$cur_geom' scripts/restore.sh                   # the drift compare
grep -n 'mode" = "cancel"' scripts/restore.sh                           # the mode gate (STEP 3 + STEP 5)
```

### Level 2: Isolated-socket no-drift + induced-drift round-trip (the core behavior)

The formal §23 suite is **P3.M3.T1** (separate). This task verifies the drift gate directly via the
project harness against the REAL plugin (P3.M2.T1.S1's snapshot capture MUST be in place for this —
it is the parallel contract this task consumes):

```bash
cd /home/dustin/.config/tmux/plugins/tmux-livepicker
source tests/setup_socket.sh
setup_socket "lp-drift-$$"; attach_test_client
# The baseline driver has a multi-pane "extra" window (setup_socket creates it) — the snapshot target.

# === ARM 1: NO-DRIFT path (activate -> immediate cancel, no nav). Expect NO select-layout, byte-identical. ===
W="$(tmux list-windows -t "=$TEST_DRIVER_SESSION" -F '#{window_id}:#{window_name}' | awk -F: '$2=="extra"{print $1; exit}')"
lay_before="$(tmux display-message -p -t "$W" '#{window_layout}')"
"$LIVEPICKER_SCRIPTS/livepicker.sh" >/dev/null            # activate: STEP 2 captures ORIG_PANE_GEOMETRY (pre-grow)
# (no nav — ORIG_WINDOW is never perturbed)
snap="$(tmux show-option -gqv @livepicker-orig-pane-geometry)"
cur="$(tmux list-panes -t "$W" -F '#{pane_id}:#{pane_left},#{pane_top},#{pane_width},#{pane_height}' 2>/dev/null)"
[ "$snap" = "$cur" ] && echo "ARM1 pre-cancel: snapshot == current (no drift at cancel entry) OK" \
                     || echo "ARM1 pre-cancel: snapshot != current — investigate format/window mismatch"
"$LIVEPICKER_SCRIPTS/input-handler.sh" cancel >/dev/null   # restore cancel: STEP 5 drift gate -> NO-OP
lay_after="$(tmux display-message -p -t "$W" '#{window_layout}')"
[ "$lay_after" = "$lay_before" ] && echo "ARM1 no-drift: layout byte-identical, NO select-layout fired OK" \
                                 || echo "ARM1 no-drift: layout CHANGED — FAIL (drift gate mis-fired or real drift)"

# === ARM 2: INDUCED-DRIFT path (activate -> perturb ORIG_WINDOW panes -> cancel). Expect resize+select-layout REPAIR. ===
setup_socket "lp-drift2-$$"; attach_test_client   # fresh cycle
W="$(tmux list-windows -t "=$TEST_DRIVER_SESSION" -F '#{window_id}:#{window_name}' | awk -F: '$2=="extra"{print $1; exit}')"
lay_before="$(tmux display-message -p -t "$W" '#{window_layout}')"
"$LIVEPICKER_SCRIPTS/livepicker.sh" >/dev/null            # activate: snapshot captured
# INDUCE drift on ORIG_WINDOW: resize a pane (changes geometry) — simulates a real §23 perturbation.
tmux resize-pane -t "$W" -D 3 2>/dev/null || tmux resize-pane -t "$W.0" -D 3 2>/dev/null || true
snap="$(tmux show-option -gqv @livepicker-orig-pane-geometry)"
cur="$(tmux list-panes -t "$W" -F '#{pane_id}:#{pane_left},#{pane_top},#{pane_width},#{pane_height}' 2>/dev/null)"
[ "$snap" != "$cur" ] && echo "ARM2 drift induced: snapshot != current (drift DETECTED) OK" \
                      || echo "ARM2: drift NOT detected — perturbation did not change geometry (adjust probe)"
"$LIVEPICKER_SCRIPTS/input-handler.sh" cancel >/dev/null   # restore cancel: STEP 5 -> resize-window -y H_orig + select-layout
lay_after="$(tmux display-message -p -t "$W" '#{window_layout}')"
[ "$lay_after" = "$lay_before" ] && echo "ARM2 drift REPAIRED: layout byte-identical after resize+select-layout OK" \
                                 || echo "ARM2 drift NOT repaired — FAIL (resize-first recipe check)"

# === ARM 3: keep/keep-window SKIPS STEP 5 (no layout restore on the original). ===
setup_socket "lp-drift3-$$"; attach_test_client
tmux set-option -g @livepicker-type window
tmux new-window -t alpha -n chosenwin
W="$(tmux list-windows -t "=$TEST_DRIVER_SESSION" -F '#{window_id}:#{window_name}' | awk -F: '$2=="extra"{print $1; exit}')"
lay_orig="$(tmux display-message -p -t "$W" '#{window_layout}')"
"$LIVEPICKER_SCRIPTS/livepicker.sh" >/dev/null
for c in a l p h a; do "$LIVEPICKER_SCRIPTS/input-handler.sh" type "$c" >/dev/null; done
"$LIVEPICKER_SCRIPTS/input-handler.sh" confirm >/dev/null    # keep-window: client lands on alpha:chosenwin
# ORIG_WINDOW (extra) was never the browse subject in keep -> STEP 5 skipped -> its layout untouched by restore.
lay_orig_after="$(tmux display-message -p -t "$W" '#{window_layout}')"
[ "$lay_orig_after" = "$lay_orig" ] && echo "ARM3 keep-window: original window untouched (STEP 5 skipped) OK" \
                                    || echo "ARM3 keep-window: original window changed — FAIL (STEP 5 should be skipped)"

teardown_socket
unset -f setup_socket teardown_socket attach_test_client
# Expected: ARM1 no-drift no-op + byte-identical; ARM2 drift detected + repaired byte-identical; ARM3 keep skips STEP 5.
# If ARM1 FAILS (layout changed): the §22 clip / status round-trip did not hold W_orig at baseline for the
#   no-nav case — re-check that STEP 4's window-size/status restore ran (it is unchanged by this task) AND that
#   the snapshot/re-capture formats match byte-for-byte (the probe prints snap vs cur above).
# If ARM2 FAILS (not repaired): the resize-window -y H_orig derivation is wrong — print h_orig (awk) and
#   compare to the pre-activate #{window_height}; ensure the awk field map is $3+$5 (top+height).
# If ARM3 FAILS: STEP 5 ran for keep — the mode gate `[ "$mode" = "cancel" ]` is missing/mis-placed.
```

### Level 3: Regression — existing suite stays green (load-bearing: test_restore_cancel_layout_exact)

```bash
cd /home/dustin/.config/tmux/plugins/tmux-livepicker
bash tests/run.sh
# Expected: exit 0, all PASS. KEY suite to eyeball:
#   - test_restore.sh::test_restore_cancel_layout_exact: #{window_layout} byte-identical after
#     activate->next-session->cancel. With this task the no-drift path holds it by NOT touching the
#     window (the §22 clip + status round-trip keep W_orig at baseline); if a real drift occurred the
#     drift path repairs it. Either way the assert holds. (See research §7 for the full analysis.)
#   - test_restore.sh::test_restore_cancel_options_hooks_exact: global options/hooks byte-identical
#     (unchanged by this task — STEP 5 edits pane geometry only, not options/hooks).
#   - test_window_flip.sh: window-cursor/flip still works (this task changes restore STEP 5 only).
#   - test_preview_clip.sh: the §22 clip freeze/restore still works (untouched).
# If test_restore_cancel_layout_exact FAILS: read research §7 — determine whether it is a false-drift
#   (format mismatch -> unneeded but byte-safe repair) or a real §23 drift the gate must repair. Do NOT
#   weaken the assert; fix the root cause (format / H_orig derivation / mode gate).
```

### Level 4: Non-pollution (the core invariant, PRD §15)

```bash
cd /home/dustin/.config/tmux/plugins/tmux-livepicker
BEFORE="$(/usr/bin/tmux list-sessions -F '#{session_name}' 2>/dev/null | sort)"
bash tests/run.sh >/dev/null 2>&1
AFTER="$(/usr/bin/tmux list-sessions -F '#{session_name}' 2>/dev/null | sort)"
[ "$BEFORE" = "$AFTER" ] && echo "REAL SERVER UNTOUCHED" || echo "POLLUTION — abort"
# Expected: REAL SERVER UNTOUCHED. The edit is to the isolated-socket restore path only.
```

### Level 5: Creative & Domain-Specific Validation

```bash
cd /home/dustin/.config/tmux/plugins/tmux-livepicker
# Confirm STEP 5 is cancel-only (keep/keep-window skip it): the mode gate wraps the WHOLE block.
sed -n '/--- STEP 5/,/keep\/keep-window: STEP 5 is intentionally/p' scripts/restore.sh | grep -c 'mode" = "cancel"'   # expect >=1 (the gate)
# Confirm the drift compare uses the IDENTICAL unsorted format on both sides (no `sort` in STEP 5).
! grep -q 'sort' <<<"$(sed -n '/--- STEP 5/,/intentionally a no-op/p' scripts/restore.sh)" \
  && echo "STEP 5 geometry compare is UNSORTED (correct — catches reorder+resize)" \
  || echo "FAIL: do NOT sort the geometry compare"
# Confirm H_orig is derived from the snapshot (awk), NOT a live display-message, in STEP 5.
grep -q "awk -F'\[:,\]'" scripts/restore.sh && echo "H_orig derived from snapshot via awk OK" \
                                            || echo "FAIL: H_orig derivation missing"
# Confirm STEP 6 clear_all_state still runs AFTER STEP 5 (the reads precede the clear).
awk '/--- STEP 5/{s5=NR} /clear_all_state$/{print "STEP5 line",s5," clear_all_state line",NR; exit}' scripts/restore.sh
# Expected: the mode gate present; no sort; awk derivation present; STEP 5 line < clear_all_state line.
```

## Final Validation Checklist

### Technical Validation
- [ ] Level 1: `shellcheck scripts/restore.sh` clean (no new errors); `bash -n` passes; the 3 new locals + drift gate + resize-window + format line grep-confirmed.
- [ ] Level 2: ARM1 no-drift → NO select-layout + layout byte-identical; ARM2 induced drift → detected + repaired (resize-window -y H_orig + select-layout) byte-identical; ARM3 keep-window → original window untouched (STEP 5 skipped).
- [ ] Level 3: `bash tests/run.sh` exit 0; `test_restore_cancel_layout_exact` green (byte-exact layout after cancel).
- [ ] Level 4: real tmux server byte-identical before/after (PRD §15).
- [ ] Level 5: STEP 5 mode-gate present; geometry compare unsorted; H_orig via awk from the snapshot; clear_all_state runs after STEP 5.

### Feature Validation
- [ ] restore.sh STEP 5 reads `ORIG_PANE_GEOMETRY` and re-captures `$orig_window` geometry with the identical unsorted format; byte-compares.
- [ ] No-drift (match) → NO select-layout, NO resize-window (pure no-op).
- [ ] Drift (mismatch) → `resize-window -y H_orig` (H_orig = max top+height from snapshot) THEN `select-layout "$ORIG_LAYOUT"`; both best-effort.
- [ ] The whole STEP 5 drift block is gated on `mode == cancel`; keep/keep-window skip it entirely.
- [ ] Empty snapshot → falls through to the restore path (no regression vs pre-PRP always-restore for that edge).
- [ ] NO snapshot capture, NO candidate pin, NO test file, NO state.sh / livepicker.sh / preview.sh edits (all out of scope).

### Code Quality Validation
- [ ] Mirrors the existing best-effort guard idiom (`2>/dev/null || true`) for resize-window + select-layout.
- [ ] Mirrors the §22 clip's `resize-window -y "$H" -t "$win"` pattern (livepicker.sh line 333).
- [ ] 3 new locals appended to the single restore_main `local` statement (house style; no inline `local`).
- [ ] The format string is single-quoted (literal `#{...}`); separators byte-exact — the contract with P3.M2.T1.S1.
- [ ] TABS for indent; no `set -e` added; SC2153 already covers the new ORIG_* reference.

### Documentation & Deployment
- [ ] The STEP 5 comment cites PRD §9 step 5 / §23 + the gate (resize-first per P3.M1.T1.S1 §3) + the mode gate (cancel-only; keep skips) + the no-op-on-no-drift directive + the format contract + the H_orig derivation.
- [ ] PRD.md, README.md, CHANGELOG.md, state.sh, livepicker.sh, preview.sh, options.sh, utils.sh, any test_*.sh, and any tasks.json UNMODIFIED. ONLY scripts/restore.sh is edited.

---

## Anti-Patterns to Avoid

- ❌ Don't run `select-layout` unconditionally. The whole point (PRD §9 step 5 / §23) is that it is a LAST RESORT, gated on actual drift. The common case is a no-op.
- ❌ Don't use a bare `select-layout` as the drift repair. The gate (P3.M1.T1.S1 §3 / ARM C2) proved it is size-dependent and unreliable; restore the SIZE first (`resize-window -y H_orig`), THEN select-layout as belt-and-suspenders.
- ❌ Don't read H_orig from a live `display-message -p '#{window_height}'`. At restore-after-drift the window is at the WRONG size; the live read returns that wrong size. Derive H_orig from the SNAPSHOT (the pre-activate baseline): `max(pane_top + pane_height)` via `awk -F'[: ,]'`.
- ❌ Don't sort either side of the geometry compare. The snapshot is unsorted (P3.M2.T1.S1 contract); the re-capture must match byte-for-byte UNSORTED so the compare catches BOTH a resize (dims change) AND a reorder (line order changes). Sorting would mask a reorder. (The §23 ASSERTION suite P3.M3.T1 sorts for ITS own proof — that is a different consumer; do not copy it here.)
- ❌ Don't change the format string. `'#{pane_id}:#{pane_left},#{pane_top},#{pane_width},#{pane_height}'` is the CONTRACT with P3.M2.T1.S1's capture. Any change (separator / field order) desyncs the two halves → false drift → unneeded repair.
- ❌ Don't run STEP 5 for keep/keep-window. The client is on the chosen target (NOT the original window); STEP 2 already skipped the ORIG_WINDOW re-select for keep. Measuring/acting on the original window in keep mode is wrong. Gate the WHOLE block on `mode == cancel`.
- ❌ Don't add a re-`select-window` in STEP 5. For cancel, STEP 2 already made ORIG_WINDOW active; `select-layout` (active-window-scoped) targets it. A redundant select-window fires a window event.
- ❌ Don't add `set -e` or drop the `2>/dev/null || true` guards. restore.sh intentionally has no `set -e`; resize-window/select-layout/list-panes can legitimately rc=1 (vanished window / invalid layout / race). A transient failure must NOT abort a half-restored teardown.
- ❌ Don't add a new state key for the original window height. Derive H_orig from the snapshot (keeps P3.M2.T1.S1's scope unchanged and avoids expanding the saved-state set).
- ❌ Don't edit state.sh, livepicker.sh, preview.sh, or any test file. The snapshot capture is P3.M2.T1.S1; the candidate pin is P3.M2.T2; the §23 suite is P3.M3.T1. THIS TASK EDITS ONLY scripts/restore.sh.
- ❌ Don't be paralyzed by §23's "resize-window forbidden" list. That list is PREVIEW-scoped. PRD §9 step 5 + §23 Prevention-regime bullet 3 explicitly REQUIRE "restore the window's exact size first, then select-layout" on drift, and the gate §3 proved `resize-window -y H_orig` is the RELIABLE repair. The drift branch MUST call it.
- ❌ Don't move the `get_state ORIG_PANE_GEOMETRY` / `ORIG_LAYOUT` reads after STEP 6. clear_all_state (STEP 6) unsets them; the reads MUST stay in STEP 5 (the old code already relied on this for ORIG_LAYOUT).

---

## Confidence Score: 9/10

This is a single-file, single-block replacement with a precise contract (the work-item §1-5 pins the exact logic; the gate §3 pins the corrected resize-first recipe; the P3.M2.T1.S1 findings pin the format contract). The insertion anchors are verbatim from the live code (restore.sh line 57 local decl; lines 222-233 STEP 5 block). The `resize-window -y H -t @id` pattern is already proven in livepicker.sh's §22 clip (line 333); the `awk -F'[:,]'` idiom is already used in 3 sibling scripts; the best-effort `2>/dev/null || true` guard mirrors the existing STEP-5 select-layout exactly. The load-bearing regression risk (test_restore_cancel_layout_exact) is analyzed end-to-end (research §7): the test passes in BOTH the no-drift path (clip + status round-trip hold W_orig at baseline → no select-layout → byte-identical) AND the drift path (resize + select-layout repair → byte-identical). The residual 1/10 is: (a) confirming the reflow-back after STEP 4's window-size/status restore is byte-identical in the no-nav case on the target tmux (Level 2 ARM1 asserts it; if it is not, the drift path repairs it — either way the invariant holds); (b) the induced-drift probe (ARM2) relies on `resize-pane` actually changing the captured geometry on the pinned driver window — the probe prints snap-vs-cur so a no-op perturbation is caught and the probe adjusted. The implementer's job is to replace one block + extend one local line in two exact spots — not to discover tmux behavior or design the drift logic.
