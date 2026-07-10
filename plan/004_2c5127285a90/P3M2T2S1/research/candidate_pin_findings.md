# Candidate Pin at Link Time — Implementation Synthesis (P3.M2.T2.S1, PRD §23)

> THIS task's synthesis. Read FIRST. Distills the GATE decision
> (`plan/004_2c5127285a90/architecture/pane_immutability_verification.md`,
> produced by COMPLETE P3.M1.T1.S1) into the exact edits for preview.sh +
> state.sh + restore.sh + README.md, plus the gotchas that override the work
> item's LITERAL command forms.
>
> **GATE VERDICT = CONDITIONAL YES** (not NO, not unconditional). Ship the pin
> for DETACHED candidates only; SKIP client-bearing candidates. See §1.

## §0. Decision (the fork in the work item §1)

The work item says: "If the decision is NO -> NO-OP + note in the file. If YES
-> proceed." The verification doc's Decision box + §7 verdict is **CONDITIONAL
YES — SHIP**. Therefore this task IMPLEMENTS the pin (it is NOT a no-op). The
README update reflects "candidate windows are now pinned (no resize) for the
detached common case; client-bearing candidates still need snapshot" (work item
§5 Mode A, YES branch).

## §1. The conditional — detached ONLY (the single most important rule)

`pane_immutability_verification.md` ARM E3 proved: setting `window-size manual`
on a candidate that HAS its own attached client **REVERTS its client view from
the fitted size (80×22) to the creation size (120×40)** — a BIGGER mutation
than leaving it alone. ARM E4 proved the bare `link-window` does NOT disturb a
client-bearing candidate (driver is manual → no downward pressure). So:

- **PIN** when the candidate has NO attached client: `[ -z "$(tmux list-clients -t "=$cand_sess" 2>/dev/null)" ]`. This is the common case (users browse other detached sessions). ARM B2: byte-identical, deterministic.
- **SKIP** (no code) when the candidate HAS a client. Strict §23 there ⇒ `@livepicker-preview-mode snapshot` (documented escape hatch, NOT this task's job to force).

`list-clients -t "=$S"` accepts the `=` prefix (verification uses it). This is
the gate that makes the pin SAFE on 3.6b. Do NOT omit it.

## §2. The work-item command forms are WRONG in two places — use the verified forms

The work item §3a/§3b literally writes `set-option -t "=$S"` and
`show-options -t "=$S"`. The verification doc **gotcha #1** is explicit and
load-bearing:

> `set-option -t "=alpha" ...` → rc=1 ("no such window"). Use the BARE name.
> The `=` prefix IS valid for `list-windows`/`display-message`/`link-window`/
> `select-window`/`list-clients`, NOT for `set-option`/`show-options`/
> `split-window`/`new-window`.

So the CORRECTED commands (use these, NOT the work-item literals):

| op | work-item (WRONG) | verified (USE) | prefix rule |
|---|---|---|---|
| list-clients | `list-clients -t "=$S"` | `list-clients -t "=$cand_sess"` ✓ | `=` OK |
| save ws | `show-options -t "=$S" -v window-size` | `show-options -t "$cand_sess" -v window-size` | BARE |
| set manual | `set-option -t "=$S" window-size manual` | `set-option -t "$cand_sess" window-size manual` | BARE |
| restore ws | `set-option -t "=$S" window-size "$cand_ws"` | `set-option -t "$pin_sess" window-size "$pin_ws"` | BARE |
| unset ws | (not in work item) | `set-option -u -t "$pin_sess" window-size` | BARE |
| height pin | `display-message -p -t "$src_id" '#{window_height}'` | same ✓ | @id OK |
| resize | `resize-window -y "$cand_h" -t "$src_id"` | same ✓ | @id OK |

The §22 driver clip (livepicker.sh line ~329, COMPLETE) already uses the BARE
form: `tmux set-option -t "$lp_fit_sess" window-size manual` + the comment
"NO '=' prefix on -t (set-option rejects it)". Mirror it EXACTLY.

## §3. Also gate the PIN on `opt_preview_fit == clip` (not in the work item, but correct)

The work item gates only on "NON-SELF candidate". Add a SECOND gate:
`[ "$(opt_preview_fit)" = "clip" ]`. Reasoning (verification §2 mechanism):

- `window-size` is per-SESSION. The shared window's size is set by the sessions
  holding it. The pin works ONLY when BOTH the driver AND the candidate are
  `manual` (no auto-resize pressure from either → window keeps the pinned size).
- In **reflow** mode the driver is NOT manual (the §22 clip is skipped —
  livepicker.sh T3 is `if opt_preview_fit == clip`). So the driver's `latest`
  client STILL drags the shared candidate window down to 22 regardless of the
  candidate's own pin. The candidate pin there is pointless churn (set manual +
  restore on unlink, no invariant benefit).
- In **clip** mode the driver IS manual (pinned at activate T3, before the first
  preview). So at preview.sh link time the driver is already manual → candidate
  manual → both manual → ARM B2 holds byte-identical.

So: PIN iff `[ clip ] && [ detached ] && [ non-self ]`. The RESTORE (preview.sh
unlink paths + restore.sh STEP 1) needs NO clip gate of its own — it is gated on
`STATE_CAND_PIN_SESSION` non-empty, which is only ever set when we actually
pinned (i.e. clip+detached). In reflow mode the keys stay empty → restore is a
natural no-op. Symmetric and clean.

This also preserves reflow mode's documented "candidates resize" behavior
(reflow is the legacy escape hatch — PRD §22 Control).

## §4. State keys — TWO new RUNTIME keys (not ORIG_*)

Track the pinned candidate so restore works even if the user navigated away
(work item §3d). Add to state.sh's runtime-keys block (after
`STATE_PREVIEW_WIN_ID`):

```bash
readonly STATE_CAND_PIN_SESSION="@livepicker-cand-pin-session"  # session name of the candidate pinned at link time (P3.M2.T2.S1, PRD §23); empty = none pinned; cleared via _STATE_RUNTIME_KEYS
readonly STATE_CAND_PIN_WS="@livepicker-cand-pin-ws"            # that candidate's prior session window-size value (empty = had no override / inherited global -> restore UNSETS our manual); cleared via _STATE_RUNTIME_KEYS
```

Append BOTH to `_STATE_RUNTIME_KEYS` (they are picker-internal transient state,
like STATE_LINKED_ID — NOT saved-state, so NOT in the ORIG_* block and NOT
matched by clear_all_state's `@livepicker-orig-` grep; they MUST be in the
explicit runtime list to be cleared). `@livepicker-cand-pin-*` does NOT match
`@livepicker-orig-`, so without the _STATE_RUNTIME_KEYS entry they would LEAK.

Naming: a NEW `CAND_PIN` family (distinct from the `CAND_WIN` flip-cursor
family — different concern). UPPER_SNAKE const + @livepicker-cand-pin-* option.

## §5. The three edit sites

### Site A — state.sh: add 2 readonly + extend _STATE_RUNTIME_KEYS (3 lines)

Runtime block (after STATE_PREVIEW_WIN_ID, before the ORIG_* comment):
```bash
readonly STATE_CAND_PIN_SESSION="@livepicker-cand-pin-session"   # ... (comment)
readonly STATE_CAND_PIN_WS="@livepicker-cand-pin-ws"             # ... (comment)
```
_STATE_RUNTIME_KEYS: append `$STATE_CAND_PIN_SESSION $STATE_CAND_PIN_WS`.

### Site B — preview.sh: pin-before-link + restore-before-unlink + a helper

1. NEW helper `_preview_restore_cand_pin()` (after preview_fallback, before
   preview_main): reads STATE_CAND_PIN_SESSION; if set, replays pin_ws (or
   `set-option -u` when empty) on the BARE session name, then unsets both keys.
   Idempotent. Used by BOTH unlink paths. (restore.sh has its OWN inline copy —
   separate process, cannot source this helper.)
2. preview_main local decl: append `cand_sess cand_ws cand_h`.
3. self-session unlink path: call `_preview_restore_cand_pin` inside the
   `if [ -n "$linked_id" ]` block (when switching FROM a pinned candidate TO
   self — closes the dangling-pin-during-self-browse gap; restore.sh STEP 1
   covers it at teardown, but the contract §3b says "preview.sh's unlink path").
4. replace path (the actual different-window link): call
   `_preview_restore_cand_pin` right after re-reading linked_id (restore
   previous), THEN the new-candidate pin block BEFORE `link-window`:
   - `cand_sess="$check_session"` (check_session already = candidate session in
     both modes: session mode $S, window mode ${S%%:*}).
   - gate: `[ clip ] && [ -n "$cand_sess" ] && [ -z "$(list-clients -t "=$cand_sess")" ]`.
   - save ws (BARE), capture cand_h, set manual (BARE), resize-window -y cand_h,
     set_state both keys.

### Site C — restore.sh: candidate-pin restore at the TOP of STEP 1

Before reading linked_id, restore STATE_CAND_PIN_SESSION if set (same logic as
the helper, inlined — restore.sh is a separate process). Place it as its own
concern at the very start of STEP 1 so it runs regardless of the H2
session-match unlink guard (the pin restore targets the CANDIDATE session, safe
even if the driver unlink is skipped). Add `pin_sess pin_ws` to restore_main's
local decl (APPEND — P3.M2.T1.S2 may have already added saved_geom/cur_geom/
h_orig; append to whatever is there, do not conflict).

### Site D — README.md: Known limitations "Detached candidates..." note

Replace the "Detached candidates still resize once at link time" bullet with the
CONDITIONAL-YES reality: detached candidates are now PINNED (no resize) in clip
mode; client-bearing candidates cannot be pinned (manual reverts their client
view) → snapshot for strict immutability there.

## §6. Why pin BEFORE link (not after) — and the benign link-failure edge

The verification ARM B2 pinned BEFORE `link-window` and held byte-identical.
Pin-after-link is ALSO safe (candidate detached → its `latest` has no client →
no pressure during the brief unpinned window), but to match the VERIFIED recipe
exactly, pin BEFORE link. Edge: if `link-window` FAILS (→ preview_fallback /
snapshot), we already pinned the candidate (manual + resize -y cand_h). But
cand_h == the candidate's OWN current height → the resize is a size no-op, and
the manual gets restored on the next nav / teardown (STATE_CAND_PIN_SESSION is
set; preview.sh's replace path or restore.sh STEP 1 restores it). Benign,
trace-free. Noted; do not over-engineer.

## §7. Restore correctness on keep vs cancel

restore.sh STEP 1 runs for BOTH keep (confirm) and cancel. On keep, the
confirmed session may BE the pinned candidate; restoring its window-size to prior
(e.g. `latest`) lets the now-attached client re-fit it — that is NORMAL attach
behavior (not a §23 violation; §23 is preview-scoped; confirm activating the
chosen session is allowed, and leaving it `manual` would be the ARM E3 harm).
So restore-on-keep is CORRECT and required.

## §8. The §23 forbidden-list reconciliation (do not be paralyzed)

PRD §23 forbids `resize-window`/`resize-pane`/`select-layout`/etc. "during
preview" on any candidate. But §23 ALSO explicitly prescribes the candidate pin
("freeze each candidate at link time too: set the candidate's window-size to
manual and pin its window to its captured geometry"). So `set-option window-size
manual` + `resize-window -y H_cand` ARE the sanctioned candidate pin (the ONE
allowed candidate mutation alongside the §22 driver pin). The `resize-window`
here sets the window to its OWN height (a freeze, not a reflow) — exactly the
verified ARM B2 recipe. It is NOT a §23 violation; it is §23's prescribed
prevention. (Contrast: restore.sh's drift repair resize-window is the OTHER
sanctioned exception, at restore time — P3.M2.T1.S2.)

## §9. Existing-suite regression risk (load-bearing)

The pin fires in clip mode for detached candidates. Existing tests that browse
candidates (test_preview_clip.sh, test_window_flip.sh) will now pin+restore
them. Risk axes:
- Byte-exact DRIVER-option restore tests (test_restore.sh): UNAFFECTED — the pin
  touches CANDIDATE session window-size, not the driver's; restore replays it.
- Any test asserting a CANDIDATE session's window-size is unchanged: was BROKEN
  before (unpinned candidate resized 40→22); now HOLDS (pinned byte-identical).
  No existing test asserts the resize-as-a-bug, so none should break.
- The pin's `resize-window -y cand_h` targets the CANDIDATE window (@src_id),
  NOT the driver — does not perturb the driver clip assertions.
Validation (PRP Level 3) runs the full suite; if a candidate-window-size
assertion shifts, it is because we now correctly LEAVE NO TRACE (save+restore
byte-exact) — investigate, do not weaken.

## §10. Gotchas (condensed — all verified on 3.6b via the gate)

1. BARE session name for set-option/show-options (NO `=`). `=` OK for list-clients/list-windows/display-message/link-window/select-window.
2. NEVER `set-option -g window-size` (global manual disconnects from client → creation size). Per-session `-t` only. (Same as §22 driver clip.)
3. `resize-window -y cand_h -t "$src_id"` — src_id holds @N already; do NOT prepend @ (→ @@N, rc=1). -t "@$src_id" WRONG.
4. `display-message -p -t "$src_id" '#{window_height}'` reads the creation size for a DETACHED candidate — that is CORRECT here (we pin at the candidate's OWN natural size, ARM B2 used 40). (gotcha #5 is about ASSERT measuring, not pinning.)
5. Skip client-bearing candidates (ARM E3 harm). Gate on list-clients empty.
6. Gate the pin on clip mode (reflow can't hold it — driver not manual).
7. STATE_CAND_PIN_* are RUNTIME keys → MUST be in _STATE_RUNTIME_KEYS (else leak; they don't match the @livepicker-orig- grep).
8. Restore is naturally gated on STATE_CAND_PIN_SESSION non-empty (no separate clip gate needed) — empty in reflow mode / never-pinned → no-op.
9. The restore helper in preview.sh + the inline copy in restore.sh are DUPLICATES by necessity (separate processes under run-shell; sourced state does not cross). Keep them byte-for-byte identical in logic.
10. check_session already holds the candidate session in both modes (computed before the self-guard) — reuse it as cand_sess; do not re-derive.
11. TABS for indent; NO `set -e` (house style — guard each tmux call `2>/dev/null || true`); `set -u` inherited (default every new var at read).
12. SC2153 covers the new STATE_CAND_PIN_* readonly consts (same file-wide disable as the other STATE_* in state.sh; preview.sh/restore.sh already disable SC2153 for STATE_*/ORIG_*). No new directive.
