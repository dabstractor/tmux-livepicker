# Research Findings — P2.M1.T3.S1 (next-window / prev-window input actions)

Ground-truth for the PRP. All tmux behavior verified on an isolated socket
(`tests/setup_socket.sh`) against tmux 3.6b. Line numbers refer to the CURRENT
`scripts/input-handler.sh` (pre-P2.M1.T2.S1) unless noted.

---

## FINDING 1 — tmux window-list primitives VERIFIED (the load-bearing one)

The flip branch derives the candidate's ordered window list and the 0-based
index of its ACTIVE window. Verified a 3-window session `alpha` with the MIDDLE
window (`a2`) active:

```
$ tmux list-windows -t '=alpha' -F '#{window_id}'            # FULL ordered list, NO -f filter
@1
@4
@5

$ tmux list-windows -t '=alpha' -F '#{window_id}:#{window_active}'
@1:0
@4:1          # the active window
@5:0

$ ... | awk -F: '$2==1{print NR-1; exit}'                    # 0-based index of the active window
1

$ list[1] == @4  ==  tmux list-windows -f '#{window_active}' # MATCH
```

**KEY INSIGHT**: the contract's literal `grep ':1' | cut -d: -f1` yields the
window **@id** (`@4`), NOT the **index** (`1`). STATE_CAND_WIN_CURSOR is a
0-based **index** into STATE_CAND_WIN_LIST, so the grep|cut result is the wrong
type. The correct, clean primitive is `awk -F: '$2==1{print NR-1; exit}'`
(NR is the 1-based line number in the SAME ordered list → NR-1 is the 0-based
index). It matches `list-windows -f '#{window_active}'` exactly (verified).
tmux always has exactly ONE active window per session, so awk always finds one;
default to 0 defensively if absent. Window ids are `@N` (no colon) → `awk -F:`
is safe.

Both `list-windows` forms (`#{window_id}` and `#{window_id}:#{window_active}`)
emit the SAME ordered list, so the awk index aligns with the array index of the
`#{window_id}` list. ✓

## FINDING 2 — Scope boundary: P2.M1.T2.S1 OWNS the fire/dispatch threading

The work-item "ALSO" paragraph says to update `_lp_fire_preview`/`_lp_preview_dispatch`
to thread a window-id arg. **That work is now owned by the parallel task
P2.M1.T2.S1** (its PRP Tasks 9 & 10). Treat P2.M1.T2.S1 as a CONTRACT — by the
time THIS task runs, the helpers ALREADY are:

```bash
_lp_fire_preview()       { local target="${1:-}" win_id="${2:-}" seq; ...; tmux run-shell -b "$CURRENT_DIR/preview.sh '$target' '$win_id' '$seq'"; }
_lp_preview_dispatch()   { local target="${1:-}" win_id="${2:-}"; defer=on: _lp_fire_preview "$target" "$win_id"; defer=off: "$CURRENT_DIR/preview.sh" "$target" "$win_id"; }
```

→ **THIS task MUST NOT edit `_lp_fire_preview` / `_lp_preview_dispatch` / preview.sh.**
It only CALLS `_lp_preview_dispatch "$S" "$W"`. Editing them duplicates P2.M1.T2.S1
and will conflict. (Confirmed: P2.M1.T2.S1 PRP Anti-Patterns: "Don't change the
existing callers ... P2.M1.T3 will be the first to pass a real win_id" — that caller is US.)

## FINDING 3 — Scope boundary: P2.M1.T3.S2 OWNS session-nav/type cursor resets

The work-item "ALSO" paragraph also says `_lp_sync_preview_to_top_match` (the
type/backspace/cancel-clear preview re-sync) "must also pass the top match's
active window as the window-id arg (or '' to let preview.sh default to active)".

Two facts make this NOT this task's job:
1. `_lp_sync_preview_to_top_match` currently calls `_lp_preview_dispatch "$_top"`
   (1 arg → win_id=""). Under P2.M1.T2.S1 that means preview.sh `chosen_win=""`
   → it resolves the candidate's **active** window. That is the CORRECT behavior
   for type/backspace (the top match is previewed on its own active window).
   Passing `''` explicitly changes nothing. **No edit is needed for correctness.**
2. The "reset window-cursor on session-nav and type/backspace" is a SEPARATE
   sibling task: **P2.M1.T3.S2** (per plan_status). That task owns mutating
   STATE_CAND_WIN_CURSOR / SESSION / LIST in the next-session/prev-session/type/
   backspace branches + any `_lp_sync_preview_to_top_match` cursor sync.

→ **THIS task MUST NOT edit `_lp_sync_preview_to_top_match` or the
session-nav/type/backspace/cancel branches.** Doing so collides with S2.
S1's flip branches are SELF-CONTAINED: they lazily (re)derive the list + reset
the cursor to active WHEN THE CANDIDATE DIFFERS (step c), so they are correct
even before S2 lands.

## FINDING 4 — The pattern to mirror: next-session / prev-session (input-handler.sh)

The existing session-nav branches are the template (PRD §3.6 says the flip
"follows the SAME pattern but operates on the candidate's window list instead
of the session list"):

```
_lp_invalidate_pending_preview          # RACE FIX first
cur_list = STATE_LIST; cur_filter = STATE_FILTER
mapfile -t filtered < <(lp_rank "$cur_list" "$cur_filter")   # SAME rank the renderer uses
L = ${#filtered[@]};  [ L -eq 0 ] && return 0
cur_index = STATE_INDEX (sanitized ^[0-9]+$ || 0)
new_idx = (cur_index ± 1 [±L]) % L
set_state STATE_INDEX new_idx;  target = filtered[new_idx]
_lp_status_redraw                        # highlight moves FIRST
_lp_scroll_into_view new_idx filtered    # SESSION-tab viewport (line 1)
_lp_preview_dispatch "$target"           # deferred/supersedeable re-link
```

The flip branch mirrors this but: (a) resolves `S = filtered[STATE_INDEX]` (the
HIGHLIGHTED session) and operates on S's WINDOW list; (b) advances
STATE_CAND_WIN_CURSOR instead of STATE_INDEX; (c) does NOT scroll-into-view
(scroll is the line-1 session-tab viewport — unchanged by a window flip);
(d) dispatches `_lp_preview_dispatch "$S" "$W"` (2 args).

## FINDING 5 — Insertion point + anchor (the ONLY input-handler.sh edit)

The two new case branches go BEFORE the confirm/cancel branches (work-item §3:
"Add two new case branches before the confirm/cancel branches"). The unique,
stable insertion anchor is the END of `prev-session` followed by the confirm
seam comment:

```
		_lp_preview_dispatch "$target"
		return 0
		;;
	# --- P1.M6.T3.S1 seam: confirm ---        <-- insert the 2 new branches BEFORE this
```

(`_lp_preview_dispatch "$target"\n return 0\n ;;` alone appears in BOTH next-session
and prev-session; the trailing `# --- P1.M6.T3.S1 seam: confirm ---` makes it
unique.) No other input-handler.sh edit. TAB-indented (the file is tab-indented;
a space oldText won't match — same gotcha as every prior task).

## FINDING 6 — Inline `local` is the file's own convention (no header edit)

`input_main` declares some locals at the top (`local action char ... target ...`),
but the `confirm` branch ALSO declares inline locals (`local w_sess`,
`local drv_wins drv_active`, `local z_target="" created="" new_session_args=(...)`).
So inline `local` inside a case branch is an ESTABLISHED pattern in THIS file
(function-scoped; case blocks create no scope). The flip branches declare their
fresh locals inline (`local S`, `local cand_win_sess win_list`, `local active_idx`,
`local -a win_arr=()`, `local wlen cur_cursor new_cursor W`) — consistent with the
confirm branch. Do NOT touch the top-of-function `local` line (larger, riskier edit).

## FINDING 7 — Self-session flip needs NO special case in input-handler

When the highlighted session S == the driver (ORIG_SESSION), the flip still
derives `list-windows -t "=$S"` (the driver's own windows) and dispatches
`_lp_preview_dispatch "$S" "$W"`. preview.sh (P2.M1.T2.S1) detects the self-session
and `select-window -t "$chosen_win"`s AMONG THE DRIVER's own windows (no link) —
PRD §3.13. So the input-handler branch is identical for self/non-self; preview.sh
owns the edge case. The only effect: while browsing the driver, flipping moves the
driver's active window; cancel's hard reset (restore STEP 2 `select-window
ORIG_WINDOW`) undoes it (PRD §3.13 / §3.8). Verified: this matches the activate
init (STATE_CAND_WIN_SESSION=ORIG_SESSION, so the first self-flip re-derives the
list because STATE_CAND_WIN_LIST is '' at activate → re-derive condition fires).

## FINDING 8 — STATE_PREVIEW_WIN_ID is set synchronously in the handler (redundant-safe)

Work-item step e: set STATE_PREVIEW_WIN_ID=W. This is redundant with preview.sh's
own STATE_PREVIEW_WIN_ID write (P2.M1.T2.S1 writes it on the link + self paths),
BUT it is load-bearing for RESPONSIVENESS: the preview is DEFERRED (default
`@livepicker-preview-defer on`), so the link+select (and preview.sh's state write)
happen in the BACKGROUND. Writing STATE_PREVIEW_WIN_ID synchronously in the handler
(step e, before `_lp_status_redraw`) means the redraw (step f) reflects the chosen
window's status immediately even before the bg link completes. preview.sh later
CONFIRMS the same value. Both writes are idempotent and agree. ✓ (STATE_PREVIEW_WIN_ID
is defined+init'd+teardown-wired by P2.M1.T1.S1 — already COMPLETE.)

## FINDING 9 — README.md Usage edit (Mode A); comprehensive prose is P4's job

Work-item DOCS = Mode A: add window-flip behavior to README Usage. Current Usage
step 3 ("Navigate: `C-M-Tab` / `C-M-BTab` or `Down` / `Up` move the selection")
is STALE relative to the two-axis rework (P1.M2.T1.S1): `C-M-Tab`/`C-M-BTab` are
now the WINDOW axis, `Down`/`Up` the SESSION axis. The minimal, NON-CONTRADICTORY
Mode A edit: split step 3 into session-nav + a new window-flip step (using the
contract's exact prose: "While previewing a session, your window-nav keys flip
its windows live. Line 2's window-status follows the flip. The session's own
active window is untouched — you are only looking."), and renumber. The
comprehensive two-axis + confirm-on-window prose is P4.M1.T1.S1's job — do NOT
pre-empt it. Do NOT claim confirm "lands on the flipped window" yet (that is
P2.M2.T1, not done) — the flip step explicitly says you are only LOOKING.

## FINDING 10 — Validation approach

- **L1**: `bash -n` + `shellcheck` on input-handler.sh; grep cross-checks (2 new
  branches, awk active_idx, 2-arg dispatch call, no edits to fire/dispatch).
- **L2**: `tests/run.sh` stays GREEN (no test asserts window-flip yet — the flip
  suite is P2.M3.T1.S1). The new branches only FIRE when a window-axis key is
  pressed; the suite's session-nav/type/confirm/cancel paths are untouched.
- **L3**: an isolated-socket SMOKE test (defer=off for determinism): give `alpha`
  3 windows, highlight alpha via `type alpha`, drive `next-window`/`prev-window`,
  assert STATE_CAND_WIN_SESSION/LIST/CURSOR/PREVIEW_WIN_ID evolve correctly
  (cursor numeric in range, preview-win-id == list[cursor], wrapping), AND assert
  alpha's OWN active window is UNCHANGED (Invariant B leave-no-trace — the flip
  links into the DRIVER, never select-window on alpha).
- No new test FILE (the formal flip suite is P2.M3.T1.S1); the L3 smoke is a
  throwaway `/tmp/smoke_flip.sh` mirroring the prior tasks' validation style.
