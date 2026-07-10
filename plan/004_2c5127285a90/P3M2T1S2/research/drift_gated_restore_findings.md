# Drift-gated restore (restore.sh STEP 5) — findings for P3.M2.T1.S2

> Focused synthesis for the drift-gated restore task. The contract (item §1-5) is precise.
> This file pins the exact replacement block, the mode gate, the H_orig derivation, the
> §23 "resize-window forbidden during preview vs sanctioned at restore" reconciliation, and
> the load-bearing regression risk (test_restore_cancel_layout_exact). Read alongside
> `P3M1T1S1/research/candidate_pin_probe_findings.md` §3 (the gate that sanctions the
> size-first repair) and `P3M2T1S1/research/pane_geometry_snapshot_findings.md` (the format
> contract / the snapshot this task CONSUMES).

## 0. Scope — this task CONSUMES the snapshot; it does NOT capture it

- **P3.M2.T1.S1** (Implementing, parallel) = WRITE `ORIG_PANE_GEOMETRY` in state.sh +
  capture it in livepicker.sh STEP 2 (after `ORIG_LAYOUT`, pre-grow). This task ASSUMES it
  is done: `ORIG_PANE_GEOMETRY` is a `readonly` const in state.sh's ORIG_* block and is
  populated by activate.
- **This task (P3.M2.T1.S2)** = READ `ORIG_PANE_GEOMETRY` in restore.sh STEP 5 and gate the
  layout restore on drift. ONE file edited: `scripts/restore.sh`.
- **P3.M2.T2** (separate) = candidate pin at link time. **P3.M3.T1** (separate) = formal §23
  test suite. NEITHER is this task.

## 1. The exact replacement — restore.sh STEP 5 (current lines 222-233)

CURRENT (unconditional select-layout — to be REPLACED):
```bash
	# --- STEP 5 (PRD §9 restore step 5): restore the original pane layout ---
	# ... (existing comment) ...
	orig_layout="$(get_state "$ORIG_LAYOUT" "")"
	[ -n "$orig_layout" ] && tmux select-layout "$orig_layout" 2>/dev/null || true
```

NEW (drift-gated; cancel-only; size-first repair per the gate §3):
- Read `ORIG_PANE_GEOMETRY` snapshot, re-capture current geometry of `$orig_window` with the
  IDENTICAL format (no sort), string-compare.
- equal → NO-OP (§23-preferred common case). differ → `resize-window -y H_orig` (size-first;
  deterministic per gate §3 / ARM C2) THEN `select-layout "$ORIG_LAYOUT"` (belt-and-suspenders).
- The whole block is gated on `mode == cancel` (keep/keep-window skip STEP 5 entirely).
- `orig_layout` read is MOVED INSIDE the cancel block (keep no longer needs it).
- New locals `saved_geom cur_geom h_orig` added to the `restore_main` local declaration
  (line 57) — house style declares all locals in one statement at the top.

See the PRP "Implementation Patterns" for the verbatim block.

## 2. The mode gate — cancel ONLY (work-item §3b/§3d)

- **cancel**: STEP 2 (P2.M2.T2) already ran `select-window -t "$ORIG_WINDOW"`, so ORIG_WINDOW
  IS active when STEP 5 runs → the drift check targets the right window, and any
  `select-layout` (active-window-scoped) applies to it. Run the full drift-gated restore.
- **keep / keep-window**: the client is already on the chosen target (NOT the original
  window); the original window was never the browse subject (keep mode commits the candidate
  window, it does not flip the driver back). STEP 2 SKIPPED re-selecting ORIG_WINDOW for keep
  → measuring/acting on it here would be wrong. SKIP STEP 5 entirely (no `else`).

`mode` is already set in STEP 3 (`mode="${1:-}"`). `orig_window` is set in STEP 2
(`orig_window="$(get_state "$ORIG_WINDOW" "")"`). Both are in scope for STEP 5.

## 3. H_orig — DERIVE FROM THE SNAPSHOT (do NOT re-read live)

At restore, if drift occurred, the window is at the WRONG (drifted) size. `resize-window -y`
needs the ORIGINAL height. Two sources:
- **Live `display-message -p '#{window_height}'`** — WRONG: reads the drifted/current size.
- **The snapshot** — CORRECT: `ORIG_PANE_GEOMETRY` is the pre-activate baseline.

Derive H_orig from the snapshot: `max(pane_top + pane_height)` over all panes == the
pre-activate window content height == what activate's §22 clip captured via
`#{window_height}` (livepicker.sh line 329) at the same pre-grow moment. Proven equivalent:
panes tile the window completely, so the bottom-most pane's (top+height) = window_height.

```bash
# snapshot line: '#{pane_id}:#{pane_left},#{pane_top},#{pane_width},#{pane_height}'
# awk -F'[:,]' -> $1=id $2=left $3=top $4=width $5=height -> top+height = $3+$5
h_orig="$(printf '%s\n' "$saved_geom" | awk -F'[:,]' '{ h=$3+$5; if(h>max) max=h } END{ print max+0 }')"
```
- `awk -F'[:,]'` is the house idiom (preview.sh line 183, input-handler.sh lines 471/521,
  session-mgmt.sh line 168 all use `awk -F:` / `awk -F'...'`).
- `max+0` → prints `0` if the snapshot were empty (guarded upstream, but safe).
- Guard `[ -n "$h_orig" ] && [ "$h_orig" -gt 0 ] 2>/dev/null` → skip resize if non-numeric/
  empty/zero (the `2>/dev/null` silences the "integer expression expected" bash error →
  rc=2 → && short-circuits → resize skipped, no abort under no `-e`).

This makes H_orig self-contained: NO new state key, NO change to P3.M2.T1.S1's scope.

## 4. §23 "resize-window forbidden" RECONCILED — preview-scoped; restore-time repair is sanctioned

§23 lists `resize-window` as "Forbidden during preview". This task uses `resize-window -y`
at RESTORE (cancel), AFTER the picker session ends. That is NOT "during preview" — it is the
documented drift-repair path:
- PRD §9 step 5: "Only if it drifted: restore the window's exact size first, then
  `select-layout`."
- PRD §23 Prevention regime bullet 3: "Only if drift is detected: restore the window's exact
  size first, then `select-layout`."
- The gate (candidate_pin_probe_findings.md §3 / ARM C2): "`resize-window -y H_orig`
  restored the EXACT multi-pane layout byte-for-byte … NOT a bare `select-layout` (which is
  size-dependent and unreliable)." This CORRECTS the naive "just select-layout" recipe: the
  SIZE must be restored first, deterministically.

So the drift-repair sequence is: `resize-window -y H_orig` (size-first, the reliable repair)
THEN `select-layout "$ORIG_LAYOUT"` (belt-and-suspenders, harmless once size is correct). Both
best-effort (`2>/dev/null || true`): a transient failure must NOT abort the teardown (no `set -e`
in restore.sh; the existing STEP-5 select-layout uses exactly this guard).

## 5. FORMAT IS THE CONTRACT — re-capture byte-identically, NO sort

The consumer (this task) re-captures with the IDENTICAL format P3.M2.T1.S1 used to WRITE the
snapshot:
```bash
cur_geom="$(tmux list-panes -t "$orig_window" -F '#{pane_id}:#{pane_left},#{pane_top},#{pane_width},#{pane_height}' 2>/dev/null)"
```
- Do NOT sort either side (the §23 ASSERTION suite P3.M3.T1 sorts for ITS own proof; the
  restore SNAPSHOT comparison must stay unsorted to catch BOTH a resize (dims change) AND a
  reorder (line order changes)).
- Byte-for-byte string compare `[ "$saved_geom" = "$cur_geom" ]`. set-option -g preserved the
  multi-line snapshot verbatim (STATE_LIST precedent); get_state reads the full multi-line
  value back. A multi-pane window round-trips as a multi-line string — the compare is sound.
- `2>/dev/null` only (no `|| true` inside the `$(...)`): under `set -u` (NO `set -e`) a
  failing list-panes (window vanished) yields empty stdout → stored "" → handled below.

## 6. The empty-snapshot edge — fall THROUGH to restore (no regression)

If `saved_geom` is empty (e.g. an older activate that pre-dates P3.M2.T1.S1, or a capture
race), there is no baseline to compare. Decision: treat empty as "cannot prove no-drift" →
fall through to the drift/restore path (resize-window only if h_orig derivable → it is NOT
when saved_geom empty → skip resize; then select-layout). This PRESERVES the pre-PRP
always-restore behavior for that edge (select-layout still runs) — no silent regression.

```bash
if [ -n "$saved_geom" ] && [ "$saved_geom" = "$cur_geom" ]; then
    :   # NO DRIFT — leave the window untouched (§23-preferred no-op)
else
    # DRIFT (or no snapshot — defensive). Restore size first, then select-layout.
    ...
fi
```

## 7. LOAD-BEARING regression risk — test_restore_cancel_layout_exact MUST stay green

`tests/test_restore.sh::test_restore_cancel_layout_exact` asserts: after activate →
next-session → cancel, `#{window_layout}` of the driver's original window is byte-identical to
pre-activate. The OLD code achieved this via unconditional `select-layout "$ORIG_LAYOUT"`.

This task's no-drift path does NOT call select-layout. Will layout still be byte-identical?
**YES, by construction of the §22 clip + status round-trip**:
- snapshot captured at STEP 2 (pre-grow, status=S, window height H0).
- activate T3 clip: pin driver window-size manual + `resize-window -y H0` (H0 == pre-grow
  height → the pin is a no-op on size) + grow status to S+1.
- during browse: ORIG_WINDOW is a distinct @id; it stays pinned at H0 (manual driver never
  auto-resizes it; the linked candidate is a different @id object — gate ARM B2 proved no
  per-nav reflow).
- restore STEP 4: restore status to S (usable → H0) + unset window-size manual (→ latest,
  re-fit to client → H0). W_orig reflows back to H0.
- restore STEP 5 (this task): cur_geom (H0, same split) == saved_geom (H0) → NO DRIFT → no
  select-layout. layout_after == layout_before because the window NEVER actually moved.

If the reflow-back were NOT byte-identical (a real §23 violation), cur_geom != saved_geom →
DRIFT → this task's resize-window -y H0 + select-layout REPAIRS it → layout_after ==
layout_before. So the test passes in BOTH the no-drift AND drift cases — the drift gate only
changes WHICH mechanism holds the invariant, not WHETHER it holds.

The only failure mode: a snapshot/re-capture FORMAT MISMATCH (different separator/field
order/target) → cur_geom spuriously != saved_geom → an UNNEEDED resize+select-layout. That is
still byte-safe (select-layout of the original layout is idempotent on a correct-size window)
but wasteful. The PRP pins the format byte-exact to avoid it; the Level 2 probe asserts
saved_geom == cur_geom in the pure no-nav case.

## 8. STEP ordering — STEP 6 clear_all_state runs AFTER STEP 5

`clear_all_state` (STEP 6) unsets every `@livepicker-orig-*` including `ORIG_PANE_GEOMETRY`
and `ORIG_LAYOUT`. So STEP 5's `get_state` reads MUST happen before STEP 6 — they do (STEP 5
precedes STEP 6 in the file). The snapshot + layout are still populated when STEP 5 reads
them. (Existing invariant — the old code already read ORIG_LAYOUT in STEP 5 before STEP 6.)

## 9. select-layout applies to the ACTIVE window — ORIG_WINDOW is active for cancel

`select-layout` (no `-t`) applies to the active window. For cancel, STEP 2 made ORIG_WINDOW
active and nothing in STEPs 3-4 changes the active window (STEP 3 switches the CLIENT's
session to =ORIG_SESSION — the SAME session — which does not change the active window). So
select-layout targets ORIG_WINDOW. `resize-window -y ... -t "$orig_window"` targets by @id
explicitly (does not depend on active). Consistent with the existing STEP-5 comment
("select-layout applies to the ACTIVE window. STEP 2 … already ran select-window … target is
active — FINDING 7"). No re-select-window is needed in STEP 5.

## 10. Gotchas specific to this task

- **Do NOT re-select-window in STEP 5.** STEP 2 already did it for cancel; keep skips STEP 5.
  An extra select-window would fire a redundant window event.
- **Do NOT sort the geometry compare.** Unsorted native list-panes order on BOTH sides (catches
  reorder + resize).
- **Do NOT read H_orig from a live display-message.** It reads the drifted size. Derive from
  the snapshot.
- **Do NOT add a new state key for window height.** Derive H_orig from the snapshot (keeps
  P3.M2.T1.S1's scope unchanged).
- **resize-window + select-layout are BEST-EFFORT.** `2>/dev/null || true`. No `set -e` in
  restore.sh; a half-restored teardown must not abort.
- **Add 3 new locals** (`saved_geom cur_geom h_orig`) to the restore_main local declaration
  (line 57). House style = one `local` statement at the top.
- **TABS for indent.** restore.sh uses tabs throughout (1-tab indent inside restore_main).
- **`mode == cancel` gate FIRST.** The cheapest correct check — keep/keep-window short-circuit
  before any list-panes fork.
- **SC2153 already covered.** restore.sh's header `disable=SC1091,SC2153` covers the readonly
  ORIG_* constants (incl. the new ORIG_PANE_GEOMETRY from S1). No new shellcheck directive.

## 11. What is OUT OF SCOPE (do NOT do)

- The snapshot CAPTURE (P3.M2.T1.S1 — parallel; this task only READS it).
- The candidate-window pin at link time (P3.M2.T2).
- The formal §23 test suite (P3.M3.T1). This task validates via shellcheck + a Level 2
  ad-hoc no-drift/drift probe + the existing suite (test_restore_cancel_layout_exact).
- Editing state.sh, livepicker.sh, preview.sh, options.sh, utils.sh, PRD.md, README.md,
  CHANGELOG.md, any tasks.json, any test_*.sh. THIS TASK EDITS ONLY `scripts/restore.sh`.
