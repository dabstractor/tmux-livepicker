# Findings — P2.M2.T2.S1: Unify keep/keep-window to skip STEP-2 ORIG_WINDOW re-select

Research was performed against the live repo (post-P2.M1, P2.M2.T1.S1 treated as a
CONTRACT being implemented in parallel). Every claim below is backed by a direct
read/grep of the codebase.

## FINDING 1 — the change is ONE guard line (+ its comment) in ONE file

`scripts/restore.sh` STEP-2 (the "--- STEP 2 ---" block; guard at ~L105 today, the
work item's "97-106" is the comment block + guard — line numbers drifted slightly):

```bash
	orig_window="$(get_state "$ORIG_WINDOW" "")"
	if [ "${1:-}" != "keep-window" ] && [ -n "$orig_window" ]; then
		tmux select-window -t "$orig_window" 2>/dev/null || true
	fi
```

**The fix** (verbatim from the work-item contract):
```bash
	if [ "${1:-}" = "cancel" ] && [ -n "$orig_window" ]; then
```

So ONLY `cancel` re-selects ORIG_WINDOW; both `keep` and `keep-window` skip it. This
**mirrors STEP-3's existing guard** (`if [ "$mode" = "cancel" ] && ...` at ~L126),
making STEP-2/STEP-3 a consistent "cancel-only" pair. The select-window body, the
`orig_window` read, and the `2>/dev/null || true` guard are UNCHANGED.

## FINDING 2 — the three argv values restore.sh actually receives (caller matrix)

Verified via `grep -rn 'restore.sh" \(keep\|keep-window\|cancel\)' scripts/`. There
are exactly THREE distinct argv[1] values, from 8 call sites:

| argv[1]       | caller (input-handler.sh / livepicker.sh)              | semantic                                            |
|---------------|---------------------------------------------------------|-----------------------------------------------------|
| `cancel`      | L700 (cancel-clear), L706 (cancel-exit), L765 (mgmt-cancel), livepicker.sh:524 (deactivate) | hard reset → re-select ORIG_WINDOW + switch back. **STILL re-selects after fix.** |
| `keep`        | L119 (`_confirm_land_on_session`), L644 + L666 (P2.M2.T1.S1 session-confirm: non-self + self) | client already on chosen (S,W). **NOW skips re-select (the fix).** |
| `keep-window` | L603 (window-mode confirm)                              | client already on chosen window. **STILL skips (unchanged).** |

There is no 4th value. The guard `= "cancel"` therefore partitions the three values
exactly as the PRD §9 step-2 requires. (`_confirm_land_on_session` is STILL called by
the create-on-empty path at input-handler.sh L697, which itself calls `restore.sh keep`.)

## FINDING 3 — the bug this fixes (and why it is masked today)

PRD §9 restore step 2: *"`select-window -t "$ORIG_WINDOW"` (cancel only; `keep` skips
this so the client stays on the chosen `(S, W)`)."* Today the guard `!= "keep-window"`
makes `keep` (session-mode confirm) RE-SELECT ORIG_WINDOW — which yanks the client off
the chosen (S, W) the confirm just committed. It is currently *masked* because ORIG_WINDOW
(the driver @id) is not linked into the target session post-switch, so the stray
`select-window -t "$ORIG_WINDOW"` fails silently; once P2.M2.T1.S1's confirm does
`select-window -t "=$S:$W"` + `switch-client -t "=$S"`, the stray re-select either fails
differently or moves the active window. The fix makes `keep` skip, matching the PRD.

This applies to BOTH confirm sub-paths:
- **Non-self** (confirm to a different session): confirm does select-window =$S:$W →
  unlink driver → switch-client =$S → restore keep. The client is on S:W. STEP-2 keep
  must NOT re-select ORIG_WINDOW (a driver window) — doing so would move the driver's
  active window and is semantically wrong.
- **Self** (confirm on the driver itself): confirm does select-window -t "$W" (a driver
  window that is the chosen/flipped one, possibly != ORIG_WINDOW) → restore keep (no
  switch). STEP-2 keep re-selecting ORIG_WINDOW would move the driver OFF the chosen W
  back to ORIG_WINDOW — the exact "yank off the chosen window" bug.

## FINDING 4 — STEP-1 (the unlink) remains SAFE after the fix (verification the work item asks for)

The work item says: *"verify [STEP-1] still holds after the confirm rework."* Yes:
STEP-1's guard is `if [ -n "$orig_session" ] && [ "$current_session" = "$orig_session" ]`
(restore.sh ~L90). It only unlinks the driver preview when the resolved current session
== ORIG_SESSION.

- **Non-self keep** (P2.M2.T1.S1): confirm switched the client to S → `current_session`
  (== S) != ORIG_SESSION (== driver) → **STEP-1 unlink is SKIPPED**. Safe: the confirm
  path ALREADY H2-unlinked the driver preview BEFORE switch-client. No double work.
- **Self keep** (P2.M2.T1.S1): confirm did NOT switch → `current_session` == ORIG_SESSION
  → STEP-1's guard is TRUE. IF `STATE_LINKED_ID` is still set (a foreign link from an
  earlier non-self preview that the self-confirm only conditionally dropped), STEP-1
  attempts `unlink-window -t "$ORIG_SESSION:$linked_id"`. That window was already
  unlinked by confirm → tmux rc=1 → swallowed by `2>/dev/null || true`. **Harmless.**
  This is PRE-EXISTING behavior, NOT introduced or changed by the STEP-2 guard edit.

**Conclusion**: my STEP-2 guard change does not touch STEP-1, and STEP-1's client-aware
behavior is correct under the confirm rework for both sub-paths.

## FINDING 5 — STEP-3 is already cancel-only (consistency win)

STEP-3 (`if [ "$mode" = "cancel" ] && [ -n "$orig_session" ]; then switch-client ...`)
already gates the session switch on `cancel` only. `keep` and `keep-window` both skip it.
Changing STEP-2 to `= "cancel"` makes STEP-2 and STEP-3 read identically — easy to
reason about and to test. (`mode="${1:-}"` is set in STEP-3; STEP-2 uses `${1:-}` directly
— both are `set -u`-safe defaults of argv[1]. Keep using `${1:-}` in STEP-2 for the
minimal, single-line edit; do NOT refactor to share a `mode` var across steps.)

## FINDING 6 — NO test breaks (verified the full restore/confirm/window-mode suite)

Direct read of every test referencing `restore`/`keep`/`ORIG_WINDOW`:

- `test_restore_cancel_layout_exact` + `test_restore_cancel_options_hooks_exact` +
  `test_restore_preserves_custom_status_format_low_indices` + `test_preview_*_cancel`:
  all use `cancel`. cancel STILL re-selects ORIG_WINDOW after the fix → all GREEN.
- `test_window_confirm_lands_on_chosen_window` (test_functional.sh ~L184): window-mode
  confirm → `restore.sh keep-window`. keep-window STILL skips the re-select (now via
  `= "cancel"` instead of `!= "keep-window"`) → asserts `#{session_name}`==alpha and
  `#{window_name}`==chosenwin → GREEN.
- `test_window_confirm_preserves_custom_status_format` (test_restore.sh): window-mode
  confirm → keep-window → status-format round-trips → GREEN.
- `test_preview_preserves_window_indices_confirm` (test_restore.sh ~L228): session-mode
  confirm on alpha. Asserts the DRIVER's `#{window_index}:#{window_name}` ordering by
  querying `=driver`. STEP-2's `select-window` changes which window is ACTIVE, not the
  list's index/name ordering or count → the before/after byte-equality holds → GREEN.

The NEW behavior (session-mode `keep` skips the re-select) is positively asserted by
P2.M2.T1.S1's Level-3 confirm-on-window smoke (which this fix ENABLES — without it, the
landed window would read as ORIG_WINDOW). The formal window-flip + confirm-on-window
suite is P2.M3.T1.S1. So THIS task adds no new test file (Mode A: no DOCS, no test file).

## FINDING 7 — byte-exact anchors (TAB indentation; UTF-8 in the comment)

`cat -A` on the STEP-2 block confirms: every comment line + the guard begins with ONE
real TAB (`^I`); the `select-window` body line begins with TWO TABs. The comment
contains UTF-8: `§` (section sign) and `—` (em-dash). The `edit` oldText MUST match
byte-for-byte, including the TABs and the UTF-8 glyphs. Do NOT use spaces. The safest
edit is to replace the whole comment-block + guard (the 8 lines from the
`# --- STEP 2` comment through `fi`), updating both the comment (to reflect the P2.M2.T2
unification) and the guard. The `orig_window="$(get_state ...)"` read line + the
select-window body + `fi` stay byte-identical in the newText.

## FINDING 8 — `set -u` / house-style notes for the (tiny) edit

- restore.sh sources state.sh (which sets `set -u`). `${1:-}` is the idiomatic default
  of argv[1] and is ALREADY used in the current guard — keep it. Do NOT introduce
  `set -e` (restore deliberately never aborts on a non-zero tmux call).
- No new `local` vars, no new tmux calls, no new state keys, no new files. The edit
  touches ONLY the guard comparison operator + operand and the explanatory comment.
- `ORIG_WINDOW` is a readonly CONTRACT constant from state.sh (`# shellcheck disable=SC2153`
  header documents this). shellcheck stays clean.
