# Pane-geometry snapshot at activate — findings for P3.M2.T1.S1

> Focused synthesis for the snapshot-capture task. The contract (item description §3)
> is precise; this file pins the exact insertion anchors, the convention to mirror, the
> format-string contract with the consumer (P3.M2.T1.S2), and the gotchas. Read
> alongside `P3M1T1S1/PRP.md` (the gate — informs the consumer's restore recipe).

## 1. Scope — capture ONLY; drift restore is a SEPARATE task

- **This task (P3.M2.T1.S1)** = WRITE the snapshot at activate (state.sh constant +
  one livepicker.sh STEP 2 line). NOTHING else.
- **P3.M2.T1.S2** (separate, Planned) = READ it in restore.sh STEP 5 and act on drift.
- **P3.M2.T2** (conditional, gated by P3.M1.T1.S1) = candidate pin at link time.
- Do NOT implement the restore comparison, the candidate pin, or any §23 "act on drift"
  logic here. Those are out of scope. This task only makes the snapshot AVAILABLE.

## 2. The two exact edits

### Edit A — scripts/state.sh: add ORIG_PANE_GEOMETRY to the ORIG_* block
The ORIG_* block (lines ~54-62) is the saved-state CONTRACT. ORIG_LAYOUT (line 56) is
the direct sibling — it is the `window_layout` string of the original window; the new
key is the PER-PANE geometry of the SAME window (PRD §9: "window_layout ... plus a
pane-geometry snapshot"). Add it IMMEDIATELY AFTER ORIG_LAYOUT (conceptually paired):

```bash
readonly ORIG_LAYOUT="@livepicker-orig-layout"                         # window_layout string
readonly ORIG_PANE_GEOMETRY="@livepicker-orig-pane-geometry"           # per-pane geometry of the original window (PRD §9/§23); restore compares to detect drift, acts only if changed (Invariant C); auto-cleared by clear_all_state's grep '@livepicker-orig-'
readonly ORIG_KEY_TABLE="@livepicker-orig-key-table"
```

Mirror the style of `ORIG_WINDOW_SIZE` (line 59): readonly UPPER_SNAKE, inline comment
citing PRD §9/§23 + the auto-clear note. Inline comment is a single line (match the
neighbors — ORIG_WINDOW_SIZE's comment is long but one logical line).

### Edit B — scripts/livepicker.sh STEP 2: capture the snapshot after ORIG_LAYOUT
STEP 2 (lines 173-175) captures SESSION/WINDOW/LAYOUT via `lp_client_format`. Insert the
geometry snapshot IMMEDIATELY AFTER line 175 (ORIG_LAYOUT) and BEFORE line 176 (the
"# Three ordinary option reads" comment):

```bash
	tmux set-option -g "$ORIG_SESSION" "$(lp_client_format '#{session_name}')"
	tmux set-option -g "$ORIG_WINDOW"   "$(lp_client_format '#{window_id}')"      # @N id, NOT index
	tmux set-option -g "$ORIG_LAYOUT"   "$(lp_client_format '#{window_layout}')"
	# PRD §9 / §23 (P3.M2.T1.S1): per-pane geometry snapshot of the ORIGINAL window.
	# Restore compares the re-captured geometry to this snapshot and acts ONLY if it
	# drifted (Invariant C). Captured BEFORE the T3 status grow, so it is the true
	# pre-mutation baseline. set-option -g stores the multi-line list-panes output
	# verbatim (newlines preserved — same as STATE_LIST). FORMAT IS THE CONTRACT with
	# restore (P3.M2.T1.S2): it re-captures with the IDENTICAL format + string-compares.
	tmux set-option -g "$ORIG_PANE_GEOMETRY" "$(tmux list-panes -t "$(lp_client_format '#{window_id}')" -F '#{pane_id}:#{pane_left},#{pane_top},#{pane_width},#{pane_height}' 2>/dev/null)"
	# Three ordinary option reads (orig_name == src_name -> tmux_save_opt idiom).
	tmux_save_opt key-table key-table
```

## 3. The format string is a CONTRACT (do not change it)

`'#{pane_id}:#{pane_left},#{pane_top},#{pane_width},#{pane_height}'` — one line per pane,
e.g. `%0:0,0,80,23`. The consumer (P3.M2.T1.S2) re-captures the current geometry with the
IDENTICAL format and string-compares to the snapshot. ANY change here (separator, field
order, adding sort) desyncs the two halves. Keep it byte-for-byte as the contract specifies.

Why UNsorted (list-panes native pane order), not sorted: drift detection must catch a pane
RESIZE (dims change) AND a pane REORDER (line order changes). Native order detects both;
sorted would mask a reorder. list-panes order is deterministic, so a byte-compare of the
unsorted multi-line string is a sound, maximally-sensitive drift signal. (The §23
ASSERTION suite — P3.M3.T1 — sorts for its own byte-identical proof; that is a different
consumer. The SNAPSHOT for restore must stay unsorted.)

## 4. clear_all_state — ZERO edits (the auto-clear covers it)

clear_all_state's teardown loop unsets every `@livepicker-orig-*` via
`grep '@livepicker-orig-'`. `@livepicker-orig-pane-geometry` matches that grep, so it is
auto-cleared on exit with NO code change — exactly like ORIG_WINDOW_SIZE (the established
precedent; its comment already says "auto-cleared by clear_all_state's grep"). Do NOT add
ORIG_PANE_GEOMETRY to `_STATE_RUNTIME_KEYS` (that list is the picker-INTERNAL runtime set;
this is SAVED-STATE, a different list). Do NOT hand-clear it in clear_all_state.

## 5. Target resolution — `lp_client_format '#{window_id}'` vs reusing ORIG_WINDOW

The contract's literal command targets `$(lp_client_format '#{window_id}')`. This re-resolves
the invoking client's active window — the SAME @N window ORIG_WINDOW just saved two lines
above (nothing has switched in STEP 2 before T3). Two equivalent options:
  - **Contract literal**: `tmux list-panes -t "$(lp_client_format '#{window_id}')" ...`
    (one extra display-message fork; self-contained — does not depend on the ORIG_WINDOW
    save having succeeded).
  - **Reuse**: `tmux list-panes -t "$(get_state "$ORIG_WINDOW" "")" ...` (one show-option
    fork; DRY — reuses the just-saved @N id).
Both yield the identical @N target. Use the contract literal (it is what was prescribed);
the reuse form is an acceptable, marginally-cheaper equivalent. On the client-less test/edge,
lp_client_format falls back to context-free `display-message -p` (returns the server's active
window) — identical to how ORIG_SESSION/WINDOW/LAYOUT are captured, so consistency holds.

## 6. Timing / ordering — the snapshot is the PRE-GROW baseline (correct for drift)

STEP 2 runs BEFORE T3 (the status-grow + renderer install). So the geometry is captured
BEFORE the status grows and BEFORE any preview link — it is the true pre-mutation baseline
of the ORIGINAL window. That is exactly what restore needs for drift detection: if browsing
left the original window's panes byte-identical (the §23 goal), the re-capture at restore
equals this snapshot → no-op restore; if anything drifted, they differ → act. ✓

## 7. Gotchas specific to this task

- **Newlines are preserved.** `tmux set-option -g` stores the multi-line list-panes output
  verbatim (established by the STATE_LIST pattern: "set_state -> tmux set-option -g preserves
  embedded newlines"). `get_state` (show-option -gqv) reads the full multi-line value back.
  So a multi-pane window round-trips as a multi-line string. Do NOT join/sed it.
- **`2>/dev/null` only (no `|| true` needed).** list-panes could fail if the window vanished
  (a race); under house `set -u` (NO `set -e`) a failing command inside `$(...)` yields empty
  stdout → stores "" — restore's get_state-default-"") handles empty as "no snapshot" → no-op.
  The contract's `2>/dev/null` silences stderr; no `|| true` is required inside the
  substitution (it cannot abort under no -e). Match the contract exactly.
- **SC2034 already covered.** The new readonly const is unused within state.sh (it is the
  integration seam consumed by livepicker.sh/restore.sh). state.sh's file-wide
  `# shellcheck disable=SC2034` already covers it — no new directive needed. livepicker.sh's
  `disable=SC1091,SC2153` covers the sourced consts. The `#{...}` in single quotes is literal
  bash (shellcheck does not flag it).
- **ORIG_PANE_GEOMETRY is SAVED-STATE, NOT runtime.** Do NOT add it to `_STATE_RUNTIME_KEYS`.
  Mirror ORIG_WINDOW_SIZE exactly (readonly in the ORIG_* block; auto-cleared by the grep).
- **TABS for indent** (state.sh + livepicker.sh both use tabs). `local` is N/A here (no new
  function). Match the surrounding 1-tab indent in STEP 2.

## 8. What is OUT OF SCOPE (do NOT do)

- The restore-side drift comparison + resize-pin/restore (P3.M2.T1.S2). This task only WRITES.
- The candidate-window pin at link time (P3.M2.T2, gated by P3.M1.T1.S1).
- Any test (P3.M3.T1 owns the §23 test suite). This task validates via shellcheck + an ad-hoc
  round-trip probe (Level 2) + the existing suite (Level 3).
- Editing clear_all_state, _STATE_RUNTIME_KEYS, restore.sh, preview.sh, PRD.md, README.md,
  CHANGELOG.md, any tasks.json.
- Changing the format string or sorting it (it is the contract with the consumer).
