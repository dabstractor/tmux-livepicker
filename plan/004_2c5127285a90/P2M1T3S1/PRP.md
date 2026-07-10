# PRP — P2.M1.T3.S1: Add next-window / prev-window input actions

---

## Goal

**Feature Goal**: Add two new input-handler actions — `next-window` and
`prev-window` — that flip THROUGH the windows of the currently highlighted
session `S`, advancing `@livepicker-cand-win-cursor` within `S`'s ordered
window list (wrapping) and re-linking the chosen window into the DRIVER via
`preview.sh`. The window-axis keys (already bound in P1.M2.T1.S1 →
`input-handler.sh next-window`/`prev-window`) now drive the flip. Line 2's
window-status follows the flip; line 1 (session tabs) is unchanged. The flip
NEVER calls `select-window` on the candidate and NEVER `switch-client`
(Invariant A/B); it is deferred/supersedeable via the existing seq mechanism.

**Deliverable** (2 existing files edited, NO new file):
1. **`scripts/input-handler.sh`** — two new `case` branches (`next-window`,
   `prev-window`) inserted before the confirm branch. Each: invalidate → resolve
   `S` from the ranked list at `@livepicker-index` → lazily (re)derive the
   candidate's window list + reset cursor to active when the candidate differs →
   advance/wrap the cursor → set `STATE_CAND_WIN_CURSOR` + `STATE_PREVIEW_WIN_ID`
   → `_lp_status_redraw` → `_lp_preview_dispatch "$S" "$W"`.
2. **`README.md`** — Usage section (Mode A): split the stale Navigate step into
   session-nav + a new window-flip step (the contract's exact prose) + renumber.

**Success Definition**:
- `bash -n`/`shellcheck` clean on `scripts/input-handler.sh`.
- The new branches are SELF-CONTAINED: typing/session-nav/confirm/cancel are
  byte-identical (`tests/run.sh` stays GREEN — the branches only fire on a
  window-axis key).
- On an isolated socket: highlighting `alpha` (3 windows) and pressing
  `next-window` advances `@livepicker-cand-win-cursor` (numeric, in range,
  wrapping), sets `@livepicker-cand-win-session`=`alpha`, populates
  `@livepicker-cand-win-list`, and sets `@livepicker-preview-win-id`==`list[cursor]`.
- **Leave-no-trace (Invariant B)**: after any number of flips, `alpha`'s OWN
  active window is UNCHANGED (the flip links into the driver; never
  `select-window` on the candidate — enforced by preview.sh, P2.M1.T2.S1).
- `prev-window` mirrors `next-window` with `(cursor − 1 + len) % len`.

## User Persona (if applicable)

**Target User**: An end user browsing the picker who wants to inspect not just
which SESSION a candidate is, but WHICH WINDOW of it — flipping its windows live
in the preview without committing. (Internal seam for P2.M2.T1 confirm-on-window
+ P2.M3.T1.S1 the flip test suite; DOCS = Mode A here.)

**Use Case**: Activate the picker, move the highlight to a multi-window session,
then press the window-nav keys (e.g. `C-M-Tab`/`C-M-BTab`, `M-n`/`M-p`) to flip
through that session's windows live in the preview area.

**User Journey**: highlight a session → preview shows its active window → press
window-next → preview flips to the next window, line 2's window-status follows →
keep flipping (wraps) → the candidate's own active window is never touched →
confirm (P2.M2.T1) or cancel returns everything to exactly as it was.

**Pain Points Addressed**: PRD §3.6 — without the window axis the user can only
ever preview each candidate's *active* window and cannot choose a specific window
to land on.

## Why

- **PRD §3.6 / §3.2 (data flow)** explicitly lists `next-window`/`prev-window` as
  the window axis: "advance `@livepicker-cand-win-cursor` within the current
  candidate's window list (wrapping); defer a re-link of the chosen window;
  `refresh -S` so line 2's window-status follows the flip."
- **gap_analysis_two_axis.md §Gap (b)**: `input-handler.sh` has NO
  `next-window`/`prev-window` case branches today — this task adds them.
- **Decoupling**: the supporting seams are ALL already landed (or in flight as a
  hard contract): the 4 state keys + activate init + teardown (P2.M1.T1.S1 —
  COMPLETE), the chosen-window preview + `_lp_fire_preview`/`_lp_preview_dispatch`
  WIN_ID threading (P2.M1.T2.S1 — assumed COMPLETE, see Context), and the
  window-axis key BINDINGS (P1.M2.T1.S1 — COMPLETE, bind to
  `input-handler.sh next-window`/`prev-window`). This task is the pure
  input-handler addition that makes those keys actually flip.
- **Invariant-safe by delegation**: the branch only mutates picker-internal STATE
  and delegates the ONE side-effect (`preview.sh`) that links into the DRIVER
  only — never `switch-client` (Invariant A), never `select-window` on the
  candidate (Invariant B).

## What

1. **`scripts/input-handler.sh`** — add `next-window` and `prev-window` `case`
   branches (before the `confirm` branch). Each resolves the highlighted session
   `S = filtered[@livepicker-index]` via the shared `lp_rank` (same call
   next/prev-session use), lazily (re)derives `S`'s ordered window list
   (`list-windows -t "=$S" -F '#{window_id}'`) when `STATE_CAND_WIN_SESSION != S`
   (or the list is empty) and resets the cursor to `S`'s ACTIVE window, then
   advances/wraps the cursor, sets `STATE_CAND_WIN_CURSOR` + `STATE_PREVIEW_WIN_ID`,
   `_lp_status_redraw`, and `_lp_preview_dispatch "$S" "$W"`.
2. **`README.md`** — Usage: replace the stale single Navigate step with a
   session-nav step + a new window-flip step (contract prose), renumber 3→3,4,5,6,7.

### Success Criteria

- [ ] `next-window` + `prev-window` case branches exist (each exactly once) in
      `scripts/input-handler.sh`, before the `confirm` branch.
- [ ] Both branches resolve `S` via the shared `lp_rank` (filtered[STATE_INDEX]).
- [ ] Both branches lazily (re)derive `STATE_CAND_WIN_LIST` + reset
      `STATE_CAND_WIN_CURSOR` to the active window's index when
      `STATE_CAND_WIN_SESSION != S` (or list empty).
- [ ] `next-window` advances `(cursor+1)%len`; `prev-window` `(cursor-1+len)%len`.
- [ ] Both set `STATE_PREVIEW_WIN_ID=W` then `_lp_status_redraw` then
      `_lp_preview_dispatch "$S" "$W"` (2-arg).
- [ ] Neither branch calls `switch-client` or `select-window` on the candidate.
- [ ] Neither branch touches `_lp_fire_preview`/`_lp_preview_dispatch`/preview.sh
      (owned by P2.M1.T2.S1 — assumed done) NOR the session-nav/type/backspace/
      cancel branches NOR `_lp_sync_preview_to_top_match` (owned by P2.M1.T3.S2).
- [ ] README Usage adds the window-flip step with the contract's exact prose.
- [ ] `tests/run.sh` GREEN; `bash -n`/`shellcheck` clean.

## All Needed Context

### Context Completeness Check

_Pass_: A developer who has never seen this repo implements both edits from
(a) the verbatim oldText/newText anchors below (every region quoted from the
current file), and (b) the 10 findings in `research/findings.md` — most
critically **FINDING 1** (the `awk -F: '$2==1{print NR-1; exit}'` primitive
VERIFIED; the contract's `grep|cut` yields the @id NOT the index — use awk),
**FINDING 2** (do NOT edit `_lp_fire_preview`/`_lp_preview_dispatch`/preview.sh
— owned by P2.M1.T2.S1, assumed done), **FINDING 3** (do NOT touch the
session-nav/type/backspace branches or `_lp_sync_preview_to_top_match` — owned by
P2.M1.T3.S2), **FINDING 5** (the unique insertion anchor), **FINDING 6** (inline
`local` is the file's own confirm-branch convention), and **FINDING 7** (self-
session needs NO special case — preview.sh owns it). No external library
knowledge beyond the shipped `lp_rank`/`get_state`/`set_state`/`_lp_*` helpers.

### Documentation & References

```yaml
# MUST READ — the ONLY source file you EDIT #1.
- file: scripts/input-handler.sh
  why: the case dispatch (input_main). next-session (~line 320) + prev-session
       (~line 367) are the template to MIRROR (FINDING 4): invalidate -> resolve via
       lp_rank -> set_state INDEX -> _lp_status_redraw -> _lp_scroll_into_view ->
       _lp_preview_dispatch. The confirm branch (~line 396) shows inline `local`
       declarations inside a case branch (FINDING 6 — the style to copy). Helpers
       _lp_invalidate_pending_preview / _lp_status_redraw / _lp_preview_dispatch
       already exist (the latter accepts WIN_ID once P2.M1.T2.S1 lands — FINDING 2).
  pattern: "the next-session branch shape; the confirm branch's inline `local w_sess` style"
  gotcha: TAB-indented (a space oldText won't match). Insert BEFORE the confirm seam
          comment (FINDING 5). Do NOT touch _lp_fire_preview/_lp_preview_dispatch
          (FINDING 2) nor _lp_sync_preview_to_top_match/session-nav/type/cancel (FINDING 3).

# MUST READ — the state keys you read/write (DEFINED+INIT'd+TEARDOWN-WIRED by P2.M1.T1.S1 — COMPLETE).
- file: scripts/state.sh
  why: STATE_CAND_WIN_SESSION (@livepicker-cand-win-session), STATE_CAND_WIN_LIST
       (@livepicker-cand-win-list), STATE_CAND_WIN_CURSOR (@livepicker-cand-win-cursor),
       STATE_PREVIEW_WIN_ID (@livepicker-preview-win-id) — all readonly, all in
       _STATE_RUNTIME_KEYS (teardown wired), all init'd at activate (SESSION=ORIG_SESSION,
       LIST='', CURSOR='0', PREVIEW_WIN_ID=''). Also STATE_LIST/STATE_FILTER/STATE_INDEX
       (the ranked-list + highlight the flip reads), STATE_SCROLL (NOT touched by flip).
  critical: these keys ALREADY EXIST. Do NOT add/rename keys. get_state/set_state accessors.

# MUST READ — the parallel previous task's CONTRACT (the preview seam you consume).
- docfile: plan/004_2c5127285a90/P2M1T2S1/PRP.md
  why: P2.M1.T2.S1 (assumed COMPLETE) makes preview.sh accept `<session> [window-id] [seq]`
       AND makes _lp_fire_preview/_lp_preview_dispatch accept a 2nd `WIN_ID` arg threaded
       into the 3-arg run-shell. THIS task is "the FIRST caller to pass a real win_id"
       (its Anti-Patterns say so verbatim). You ONLY call _lp_preview_dispatch "$S" "$W".
  critical: DO NOT edit _lp_fire_preview / _lp_preview_dispatch / preview.sh. They are
            P2.M1.T2.S1's deliverables. Editing them = a merge conflict + duplicate work.

# MUST READ — the sibling task boundary (do NOT pre-empt P2.M1.T3.S2).
- docfile: plan/004_2c5127285a90/architecture/gap_analysis_two_axis.md
  why: §Gap (b) is the contract source for these two branches; the existing
       next-session/prev-session branches are the pattern. §Gap (c) names the 4
       window-cursor keys. Confirms the flip "follows the SAME pattern but operates
       on the candidate's window list instead of the session list" and "NEVER calls
       select-window on the candidate (Invariant B)".
  section: "Gap (b): Input-handler actions", "Gap (c): Window-cursor state", "Files needing change"

# MUST READ — PRD §3.6 (the exact window-navigation spec) + §3.2 (data flow) + §4 (invariants).
- docfile: PRD.md
  why: §3.6 — "advance @livepicker-cand-win-cursor within that session's ordered window
       list (wrapping; the list comes from list-windows -t '=$S' -F '#{window_id}',
       re-derived when the candidate changes)"; "refresh-client -S so line 2's
       window-status follows the flip"; "never calls select-window on the candidate".
       §3.2 data flow — the next-window/prev-window line. §4 Invariant A (no switch-client
       while browsing) / B (no candidate mutation). §3.13 self-session note (preview.sh
       owns it — FINDING 7).
  section: "§3.6 Window navigation", "§3.2 Data flow", "§4 The core rule", "§3.13 Self-session edge case"

# MUST READ — the activate init site (proves the 4 keys are init'd; the lazy-derive re-fires on first flip).
- docfile: plan/004_2c5127285a90/P2M1T1S1/PRP.md
  why: P2.M1.T1.S1 init'd STATE_CAND_WIN_SESSION=ORIG_SESSION, LIST='', CURSOR='0',
       PREVIEW_WIN_ID='' at activate. Because LIST='' at activate, the FIRST flip on any
       candidate re-derives (the `|| [ -z "$win_list" ]` clause) — correct.
  critical: assume the 4 keys exist + are init'd + teardown-wired. DONE.

# MUST READ — the README Usage section (the file you EDIT #2, Mode A).
- file: README.md
  why: Usage section (steps 1-6). Step 3 ("Navigate: C-M-Tab / C-M-BTab or Down / Up
       move the selection") is STALE post-two-axis (C-M-Tab/C-M-BTab are now the WINDOW
       axis). The Mode A edit splits it into session-nav + window-flip (FINDING 9).
  pattern: the numbered-step Usage list; the contract's exact window-flip prose.
  gotcha: do NOT claim confirm "lands on the flipped window" (that's P2.M2.T1, not done);
          the flip step says you are only LOOKING. Comprehensive prose is P4.M1.T1.S1.

# MUST READ — the ground-truth findings for THIS task (10 findings).
- docfile: plan/004_2c5127285a90/P2M1T3S1/research/findings.md
  why: FINDING 1 (awk active_idx VERIFIED; grep|cut gives the wrong type); FINDING 2/3
       (scope boundaries — do NOT duplicate P2.M1.T2.S1 / S2); FINDING 4 (the pattern);
       FINDING 5 (insertion anchor); FINDING 6 (inline local convention); FINDING 7
       (no self-session special case); FINDING 8 (synchronous PREVIEW_WIN_ID write);
       FINDING 9 (README edit); FINDING 10 (validation).
  critical: FINDING 1 (use awk not grep|cut) + FINDING 2/3 (scope) are the two things
            most likely to be mis-done. Read BEFORE editing.
```

### Current Codebase tree

```bash
tmux-livepicker/
  scripts/
    input-handler.sh   # MODIFY: +next-window/+prev-window case branches (before confirm).
    state.sh           # UNCHANGED (4 window-cursor keys already exist — P2.M1.T1.S1).
    preview.sh         # UNCHANGED (chosen-window link — owned by P2.M1.T2.S1, assumed done).
    options.sh utils.sh rank.sh layout.sh renderer.sh livepicker.sh restore.sh session-mgmt.sh  # UNCHANGED
  README.md            # MODIFY: Usage step 3 -> session-nav + window-flip (Mode A); renumber.
  tests/
    *.sh               # UNCHANGED (no test asserts window-flip; the flip suite is P2.M3.T1.S1).
  plan/004_2c5127285a90/{architecture/gap_analysis_two_axis.md, P2M1T1S1/PRP.md, P2M1T2S1/PRP.md, P2M1T3S1/research/findings.md}
```

### Desired Codebase tree with files to be added and responsibility of file

```bash
scripts/input-handler.sh   # +next-window: invalidate -> resolve S -> lazy-derive list +
                           #   reset cursor to active -> advance+wrap -> set CURSOR+PREVIEW_WIN_ID
                           #   -> _lp_status_redraw -> _lp_preview_dispatch "$S" "$W".
                           # +prev-window: mirror ((cursor-1+len)%len).
                           # Calls _lp_preview_dispatch with 2 args (WIN_ID threaded by P2.M1.T2.S1).
README.md                  # Usage: session-nav step + window-flip step (Mode A); renumber 3..7.
```

### Known Gotchas of our codebase & Library Quirks

```bash
# CRITICAL (FINDING 1): STATE_CAND_WIN_CURSOR is a 0-based INDEX, not a window id. The
# contract's literal `grep ':1' | cut -d: -f1` yields the @id (e.g. @4), NOT the index.
# Use the VERIFIED primitive:
#   active_idx="$(tmux list-windows -t "=$S" -F '#{window_id}:#{window_active}' | awk -F: '$2==1{print NR-1; exit}')"
# NR is the 1-based line number in the SAME ordered list as the `#{window_id}` derivation
# -> NR-1 is the 0-based index that aligns with the array index of STATE_CAND_WIN_LIST.

# CRITICAL (FINDING 2): do NOT edit _lp_fire_preview / _lp_preview_dispatch / preview.sh.
# They are P2.M1.T2.S1's deliverables (assumed COMPLETE). They ALREADY accept a WIN_ID
# 2nd arg (run-shell passes 3 positionals: session, win_id, seq). You ONLY CALL
# _lp_preview_dispatch "$S" "$W". Editing them duplicates work + causes a merge conflict.

# CRITICAL (FINDING 3): do NOT touch _lp_sync_preview_to_top_match nor the
# next-session/prev-session/type/backspace/cancel branches. The cursor reset on
# session-nav/type/backspace is the SEPARATE sibling task P2.M1.T3.S2. The flip branches
# are SELF-CONTAINED (lazy-derive + reset-to-active when the candidate differs), so they
# are correct with or without S2.

# CRITICAL (FINDING 5): the insertion anchor is prev-session's END + the confirm seam
# comment. `_lp_preview_dispatch "$target"\n\t\treturn 0\n\t\t;;` alone is NOT unique
# (it appears in both next-session and prev-session); the trailing
# `# --- P1.M6.T3.S1 seam: confirm ---` makes it unique.

# GOTCHA (FINDING 6): declare the new locals INLINE in the case branch with `local`
# (mirror the confirm branch's `local w_sess` / `local drv_wins drv_active` style). Do
# NOT edit the top-of-function `local` line. Case blocks create no scope; `local` is
# function-scoped — safe + matches the file's own convention.

# GOTCHA (FINDING 7): NO self-session special case. When S == the driver, the branch is
# identical (it derives the driver's window list + dispatches). preview.sh (P2.M1.T2.S1)
# detects the self-session and selects among the driver's own windows (no link). The only
# effect: flipping the driver moves its active window while browsing; cancel's hard reset
# (restore STEP 2 select-window ORIG_WINDOW) undoes it (PRD §3.13/§3.8).

# GOTCHA (FINDING 8): set STATE_PREVIEW_WIN_ID=W synchronously in the handler BEFORE
# _lp_status_redraw. The preview is DEFERRED (default defer=on), so preview.sh's own
# STATE_PREVIEW_WIN_ID write happens in the background; the synchronous write lets the
# redraw reflect the chosen window immediately. preview.sh later confirms the same value
# (idempotent, agree). Redundant-but-load-bearing for responsiveness.

# GOTCHA: no _lp_scroll_into_view on the flip path. Scroll is the SESSION-tab viewport
# (line 1), which a window flip does NOT change (PRD §3.6: "The flip does not change line 1").
# Session-nav scrolls because it moves the line-1 highlight; window-flip does not.

# GOTCHA (indentation): input-handler.sh uses TABS. Every oldText/newText uses a leading
# TAB for the case-body lines. A space-prefixed oldText won't match.

# GOTCHA (set -u): every get_state takes a default; cur_index/cur_cursor/active_idx are
# sanitized with [[ ... =~ ^[0-9]+$ ]] || var=0 before the modulo (mirror session-nav's
# sanitize, which guards a stale STRING option). Bash `%` can return negatives for
# negative operands — the +len in prev-window dodges it (mirror prev-session).
```

## Implementation Blueprint

### Data models and structure

No new data model. The contract is the two case branches + the state keys
(already defined by P2.M1.T1.S1). The flip state machine per branch:

| Step | Read | Write | Notes |
|------|------|-------|-------|
| invalidate | STATE_PREVIEW_SEQ | STATE_PREVIEW_SEQ (+1) | `_lp_invalidate_pending_preview` (defer=on only) |
| resolve S | STATE_LIST, STATE_FILTER, STATE_INDEX | — | `lp_rank` → `filtered[index]` (same as session-nav) |
| lazy derive | STATE_CAND_WIN_SESSION, STATE_CAND_WIN_LIST | STATE_CAND_WIN_SESSION, _LIST, _CURSOR | only if session differs OR list empty; cursor ← active index |
| advance | STATE_CAND_WIN_CURSOR | STATE_CAND_WIN_CURSOR | `(cursor ± 1 [±len]) % len` |
| track | — | STATE_PREVIEW_WIN_ID=W | synchronous (deferred preview confirms) |
| redraw | — | — | `_lp_status_redraw` (line 2 follows) |
| dispatch | — | — | `_lp_preview_dispatch "$S" "$W"` (link into driver, leave-no-trace) |

### Implementation Tasks (ordered by dependencies)

```yaml
Task 1: EDIT scripts/input-handler.sh — insert the next-window + prev-window case branches
  - FILE: ./scripts/input-handler.sh (EXISTING).
  - PLACEMENT: between the END of the prev-session branch and the `# --- P1.M6.T3.S1 seam: confirm ---`
    comment (FINDING 5). Do NOT touch any other branch or helper.
  - oldText (verbatim, TAB-indented; the unique anchor = prev-session end + confirm seam comment):
  		_lp_preview_dispatch "$target"
  		return 0
  		;;
  	# --- P1.M6.T3.S1 seam: confirm ---
  - newText (prev-session end UNCHANGED + the 2 new branches + the confirm seam comment):
  		_lp_preview_dispatch "$target"
  		return 0
  		;;
  	# --- P2.M1.T3.S1: window-flip actions (PRD §3.6). Flip THROUGH the windows of the
  	#     highlighted session S (advance @livepicker-cand-win-cursor, wrapping) and re-link
  	#     the chosen window via preview.sh (P2.M1.T2 chosen-window). Mirror session-nav's
  	#     shape: invalidate -> resolve S -> (lazy derive list) -> advance cursor -> redraw
  	#     -> dispatch. NEVER select-window on the candidate, NEVER switch-client (Invariant
  	#     A/B). Line 1 (session tabs) unchanged; only line 2's window-status follows the flip.
  	#     NO scroll-into-view here (scroll is the SESSION-tab viewport — line 1, unchanged).
  	#     The flip is deferred/supersedeable via the existing seq mechanism (§18).
  	next-window)
  		# RACE FIX: invalidate any pending background preview fire FIRST (mirror session-nav).
  		_lp_invalidate_pending_preview
  		# Resolve the HIGHLIGHTED session S the SAME way next/prev-session do: re-rank via the
  		# shared lp_rank (so filtered[index] == the session the renderer is highlighting).
  		cur_list="$(get_state "$STATE_LIST" "")"
  		cur_filter="$(get_state "$STATE_FILTER" "")"
  		mapfile -t filtered < <(lp_rank "$cur_list" "$cur_filter")
  		L="${#filtered[@]}"
  		[ "$L" -eq 0 ] && return 0
  		cur_index="$(get_state "$STATE_INDEX" "0")"
  		[[ "$cur_index" =~ ^[0-9]+$ ]] || cur_index=0
  		[ "$cur_index" -ge "$L" ] && cur_index=$(( L - 1 ))
  		local S="${filtered[$cur_index]}"
  		# LAZILY derive the candidate's window list when the cache is stale (belongs to a
  		# different session, or never built). PRD §3.6: the list is the FULL ordered window list
  		# (list-windows -t "=$S" -F '#{window_id}', NO -f filter), re-derived when the candidate
  		# changes. On (re)derivation, reset the cursor to the candidate's ACTIVE window so every
  		# candidate starts previewed on its own active window (Invariant B). (P2.M1.T3.S2 also
  		# resets the cursor on session-nav/type/backspace; this lazy path keeps the flip correct
  		# independently — defense in depth.)
  		local cand_win_sess win_list
  		cand_win_sess="$(get_state "$STATE_CAND_WIN_SESSION" "")"
  		win_list="$(get_state "$STATE_CAND_WIN_LIST" "")"
  		if [ "$cand_win_sess" != "$S" ] || [ -z "$win_list" ]; then
  			win_list="$(tmux list-windows -t "=$S" -F '#{window_id}' 2>/dev/null)"
  			set_state "$STATE_CAND_WIN_SESSION" "$S"
  			set_state "$STATE_CAND_WIN_LIST" "$win_list"
  			# Reset the cursor to the candidate's ACTIVE window: 0-based index of the window
  			# whose #{window_active}==1 in the SAME ordered list (research FINDING 1 — awk NR-1;
  			# the contract's grep|cut yields the @id, NOT the index). tmux always has exactly one
  			# active window; default 0 if absent (defensive — FINDING 1).
  			local active_idx
  			active_idx="$(tmux list-windows -t "=$S" -F '#{window_id}:#{window_active}' 2>/dev/null | awk -F: '$2==1{print NR-1; exit}')"
  			[[ "$active_idx" =~ ^[0-9]+$ ]] || active_idx=0
  			set_state "$STATE_CAND_WIN_CURSOR" "$active_idx"
  		fi
  		# Read the cached list into an array; advance the cursor (wrapping). PRD §3.6.
  		local -a win_arr=()
  		mapfile -t win_arr < <(printf '%s\n' "$win_list")
  		local wlen
  		wlen="${#win_arr[@]}"
  		[ "$wlen" -eq 0 ] && return 0
  		local cur_cursor new_cursor
  		cur_cursor="$(get_state "$STATE_CAND_WIN_CURSOR" "0")"
  		[[ "$cur_cursor" =~ ^[0-9]+$ ]] || cur_cursor=0
  		new_cursor=$(( (cur_cursor + 1) % wlen ))
  		set_state "$STATE_CAND_WIN_CURSOR" "$new_cursor"
  		local W="${win_arr[$new_cursor]}"
  		# Synchronous shown-window track (the deferred preview confirms it via preview.sh's
  		# STATE_PREVIEW_WIN_ID write — P2.M1.T2; redundant-but-safe so line 2's redraw reflects
  		# the new window even before the background link completes — FINDING 8).
  		set_state "$STATE_PREVIEW_WIN_ID" "$W"
  		# Line 2's window-status follows the flip (refresh -S); line 1 (session tabs) unchanged.
  		_lp_status_redraw
  		# Delegate the live link/select to preview.sh (P2.M1.T2 chosen-window). It links W into
  		# the DRIVER and selects it there — never select-window on the candidate, never
  		# switch-client. Deferred/supersedeable via seq. _lp_preview_dispatch takes (TARGET, WIN_ID).
  		_lp_preview_dispatch "$S" "$W"
  		return 0
  		;;
  	prev-window)
  		# Mirror of next-window (PRD §3.6): cursor = (cursor - 1 + len) % len (wrapping, reverse).
  		# Same invalidate -> resolve S -> lazy-derive -> redraw -> dispatch shape; only the
  		# cursor arithmetic differs. See next-window above for the full rationale comments.
  		_lp_invalidate_pending_preview
  		cur_list="$(get_state "$STATE_LIST" "")"
  		cur_filter="$(get_state "$STATE_FILTER" "")"
  		mapfile -t filtered < <(lp_rank "$cur_list" "$cur_filter")
  		L="${#filtered[@]}"
  		[ "$L" -eq 0 ] && return 0
  		cur_index="$(get_state "$STATE_INDEX" "0")"
  		[[ "$cur_index" =~ ^[0-9]+$ ]] || cur_index=0
  		[ "$cur_index" -ge "$L" ] && cur_index=$(( L - 1 ))
  		local S="${filtered[$cur_index]}"
  		local cand_win_sess win_list
  		cand_win_sess="$(get_state "$STATE_CAND_WIN_SESSION" "")"
  		win_list="$(get_state "$STATE_CAND_WIN_LIST" "")"
  		if [ "$cand_win_sess" != "$S" ] || [ -z "$win_list" ]; then
  			win_list="$(tmux list-windows -t "=$S" -F '#{window_id}' 2>/dev/null)"
  			set_state "$STATE_CAND_WIN_SESSION" "$S"
  			set_state "$STATE_CAND_WIN_LIST" "$win_list"
  			local active_idx
  			active_idx="$(tmux list-windows -t "=$S" -F '#{window_id}:#{window_active}' 2>/dev/null | awk -F: '$2==1{print NR-1; exit}')"
  			[[ "$active_idx" =~ ^[0-9]+$ ]] || active_idx=0
  			set_state "$STATE_CAND_WIN_CURSOR" "$active_idx"
  		fi
  		local -a win_arr=()
  		mapfile -t win_arr < <(printf '%s\n' "$win_list")
  		local wlen
  		wlen="${#win_arr[@]}"
  		[ "$wlen" -eq 0 ] && return 0
  		local cur_cursor new_cursor
  		cur_cursor="$(get_state "$STATE_CAND_WIN_CURSOR" "0")"
  		[[ "$cur_cursor" =~ ^[0-9]+$ ]] || cur_cursor=0
  		# The +wlen dodges bash's negative-modulo quirk (mirror prev-session's +L).
  		new_cursor=$(( (cur_cursor - 1 + wlen) % wlen ))
  		set_state "$STATE_CAND_WIN_CURSOR" "$new_cursor"
  		local W="${win_arr[$new_cursor]}"
  		set_state "$STATE_PREVIEW_WIN_ID" "$W"
  		_lp_status_redraw
  		_lp_preview_dispatch "$S" "$W"
  		return 0
  		;;
  	# --- P1.M6.T3.S1 seam: confirm ---
  - WHY: PRD §3.6 — the flip mirrors session-nav but operates on the candidate's WINDOW
    list; the awk active_idx is VERIFIED (FINDING 1); the inline `local`s mirror the
    confirm branch (FINDING 6); no self-session special case (FINDING 7).
  - DO NOT edit _lp_fire_preview / _lp_preview_dispatch / preview.sh (FINDING 2).
  - DO NOT touch the session-nav / type / backspace / cancel branches or
    _lp_sync_preview_to_top_match (FINDING 3).

Task 2: EDIT README.md — Usage: session-nav step + window-flip step (Mode A); renumber
  - FILE: ./README.md (EXISTING).
  - oldText (the Usage numbered steps 3-6):
  	3. **Navigate:** `C-M-Tab` / `C-M-BTab` or `Down` / `Up` move the
  	   selection; the preview follows live.
  	4. **Confirm:** `Enter` lands on the selection, or creates a session from
  	   your query in `session` mode with no match.
  	5. **Cancel:** `Escape` clears the query if non-empty, otherwise cancels and
  	   restores everything exactly.
  	6. **Rename / delete:** `C-r` renames the highlighted session; `M-BSpace`
  	   kills it. See [Session management](#session-management).
  - newText (split Navigate into session-nav + window-flip; renumber 4->5,5->6,6->7):
  	3. **Navigate sessions:** `Down` / `Up` (or your `@livepicker-session-next-keys` /
  	   `-session-prev-keys`) move the selection between candidates; the preview
  	   follows live.
  	4. **Flip windows:** while previewing a session, your window-nav keys
  	   (`@livepicker-window-next-keys` / `-window-prev-keys`, discovered from your
  	   own `next-window` / `previous-window` bindings) flip its windows live. Line
  	   2's window-status follows the flip. The session's own active window is
  	   untouched — you are only looking.
  	5. **Confirm:** `Enter` lands on the selection, or creates a session from
  	   your query in `session` mode with no match.
  	6. **Cancel:** `Escape` clears the query if non-empty, otherwise cancels and
  	   restores everything exactly.
  	7. **Rename / delete:** `C-r` renames the highlighted session; `M-BSpace`
  	   kills it. See [Session management](#session-management).
  - WHY: the old step 3 is STALE post-two-axis (C-M-Tab/C-M-BTab are now the WINDOW axis,
    not session-nav). The split is minimal, NON-CONTRADICTORY, and uses the contract's
    exact window-flip prose (FINDING 9). Do NOT claim confirm "lands on the flipped
    window" — that's P2.M2.T1 (not done); the flip step says you are only LOOKING. The
    comprehensive two-axis + confirm-on-window prose is P4.M1.T1.S1's job.
  - NOTE: README uses SPACE indentation (3-space continuation) — match the existing
    style (NOT tabs). The oldText above uses the file's actual 3-space continuation indent.

Task 3: VALIDATE (L1 grep + L2 suite + L3 flip smoke + leave-no-trace)
  - RUN: bash -n scripts/input-handler.sh ; shellcheck scripts/input-handler.sh.
  - RUN: grep cross-checks (2 new branches, awk active_idx, 2-arg dispatch call, NO edits
    to _lp_fire_preview/_lp_preview_dispatch/preview.sh, NO edits to session-nav/type/cancel).
  - RUN: tests/run.sh (expect GREEN — the new branches only fire on a window-axis key).
  - RUN: L3 isolated-socket flip smoke (defer=off): highlight alpha (3 windows), drive
    next-window/prev-window, assert STATE_CAND_WIN_* + PREVIEW_WIN_ID evolve + wrap, AND
    assert alpha's OWN active window is UNCHANGED (Invariant B).
```

### Implementation Patterns & Key Details

```bash
# === The branch shape (mirror session-nav; FINDING 4) ===
next-window)
    _lp_invalidate_pending_preview                       # RACE FIX first
    # resolve S = filtered[STATE_INDEX] (SAME lp_rank the renderer/session-nav use)
    cur_list=STATE_LIST; cur_filter=STATE_FILTER
    mapfile -t filtered < <(lp_rank "$cur_list" "$cur_filter")
    L=${#filtered[@]}; [ "$L" -eq 0 ] && return 0
    cur_index=STATE_INDEX (sanitized); S="${filtered[$cur_index]}"
    # LAZY derive when the candidate differs OR the list is empty (FINDING: list is '' at activate)
    if STATE_CAND_WIN_SESSION != S || win_list == ""; then
        win_list="$(tmux list-windows -t "=$S" -F '#{window_id}')"   # FULL ordered list, NO -f
        set STATE_CAND_WIN_SESSION=S; set STATE_CAND_WIN_LIST=win_list
        active_idx="$(... | awk -F: '$2==1{print NR-1; exit}')"      # VERIFIED 0-based index (FINDING 1)
        set STATE_CAND_WIN_CURSOR=active_idx
    fi
    mapfile -t win_arr < <(printf '%s\n' "$win_list")
    wlen=${#win_arr[@]}; [ wlen -eq 0 ] && return 0
    cur_cursor=STATE_CAND_WIN_CURSOR (sanitized)
    new_cursor=$(( (cur_cursor + 1) % wlen ))            # prev-window: (cur_cursor - 1 + wlen) % wlen
    set STATE_CAND_WIN_CURSOR=new_cursor
    W="${win_arr[$new_cursor]}"; set STATE_PREVIEW_WIN_ID=W   # synchronous (FINDING 8)
    _lp_status_redraw                                    # line 2 follows; line 1 unchanged
    _lp_preview_dispatch "$S" "$W"                       # 2-arg; links into DRIVER only (FINDING 2)
    return 0
    ;;

# === The VERIFIED active-index primitive (FINDING 1 — do NOT use grep|cut) ===
active_idx="$(tmux list-windows -t "=$S" -F '#{window_id}:#{window_active}' 2>/dev/null | awk -F: '$2==1{print NR-1; exit}')"
# grep ':1' | cut -d: -f1 would yield the @id (e.g. @4), NOT the index (1) — WRONG TYPE for the cursor.

# === Inline locals (FINDING 6 — mirror the confirm branch) ===
#   local S=... ; local cand_win_sess win_list ; local active_idx ; local -a win_arr=()
#   local wlen ; local cur_cursor new_cursor ; local W=...
# Do NOT edit input_main's top-of-function `local` line.
```

### Integration Points

```yaml
INPUT-HANDLER (input-handler.sh):
  - +next-window / +prev-window case branches (before confirm). Inline `local` style.
  - NO change to _lp_fire_preview / _lp_preview_dispatch / preview.sh (P2.M1.T2.S1).
  - NO change to session-nav / type / backspace / cancel / _lp_sync_preview_to_top_match (P2.M1.T3.S2).

STATE (state.sh): NO CHANGE. STATE_CAND_WIN_SESSION/LIST/CURSOR + STATE_PREVIEW_WIN_ID
  ALREADY defined+init'd+teardown-wired (P2.M1.T1.S1 — COMPLETE). This task only
  reads/writes them.

PREVIEW (preview.sh): NO CHANGE (P2.M1.T2.S1 — assumed COMPLETE). The flip dispatches
  _lp_preview_dispatch "$S" "$W" which (defer=on) fires the 3-arg run-shell, (defer=off)
  runs preview.sh inline with chosen_win="$W". preview.sh links W into the DRIVER and
  selects it there (non-self) / selects among the driver's own windows (self) — never
  select-window on the candidate (Invariant B).

ACTIVATE (livepicker.sh): NO CHANGE. The window-axis keys are ALREADY bound to
  `input-handler.sh next-window`/`prev-window` (P1.M2.T1.S1 — COMPLETE). This task makes
  those bindings actually flip (previously they hit the `*)` no-op branch).

README.md: Usage step 3 -> session-nav + window-flip (Mode A); renumber. (FINDING 9.)

CONSUMERS (FUTURE — do not implement here):
  - P2.M1.T3.S2: reset window-cursor on session-nav/type/backspace (+ _lp_sync sync).
  - P2.M2.T1: confirm resolves (S, W) from STATE_CAND_WIN_CURSOR and commits the window.
  - P2.M3.T1.S1: the formal test_window_flip.sh suite.

CONFIG / DATABASE / ROUTES: none.
```

## Validation Loop

### Level 1: Syntax & Style (Immediate Feedback)

```bash
cd /home/dustin/.config/tmux/plugins/tmux-livepicker
bash -n scripts/input-handler.sh && echo "OK: syntax"            # expect exit 0
shellcheck scripts/input-handler.sh                               # expect 0 findings
# The 2 new branches exist (each exactly once):
grep -c 'next-window)' scripts/input-handler.sh                   # == 1
grep -c 'prev-window)' scripts/input-handler.sh                   # == 1
# The VERIFIED awk active_idx primitive is used (NOT grep|cut):
grep -c "awk -F: '\$2==1{print NR-1; exit}'" scripts/input-handler.sh   # == 2 (both branches)
# The 2-arg dispatch call is used (WIN_ID threaded by P2.M1.T2.S1):
grep -c '_lp_preview_dispatch "\$S" "\$W"' scripts/input-handler.sh     # == 2
# SCOPE GUARD: _lp_fire_preview / _lp_preview_dispatch / preview.sh were NOT edited by THIS task.
# (They were edited by P2.M1.T2.S1. Here we only ASSERT we did not re-touch them.)
# The fire/dispatch helpers still have the WIN_ID binding from P2.M1.T2.S1:
grep -c 'win_id="\${2:-}"' scripts/input-handler.sh               # == 2 (_lp_fire_preview + _lp_preview_dispatch)
# No 4-space indent on the new branch lines (tabs only):
grep -Pn '^\t*    [^#/]' scripts/input-handler.sh | tail && echo "WARN: space-indent" || echo "OK: tabs"
# Expected: all match; each branch count == 1; awk + 2-arg dispatch == 2; tabs only.
```

### Level 2: Full suite (no regression)

```bash
cd /home/dustin/.config/tmux/plugins/tmux-livepicker
tests/run.sh
# Expected: exit 0, all green. The new branches fire ONLY when a window-axis key is
# pressed; the suite's session-nav/type/confirm/cancel/restore paths are byte-identical
# (no branch body changed, no helper changed). NOTE: this suite does NOT exercise
# window-flip yet (that's P2.M3.T1.S1) — it only proves NO REGRESSION in the existing
# paths. If the suite was red from the parallel P2.M1.T2.S1 broken-intermediate state,
# that task fixes it; the L3 smoke below is THIS task's positive gate.
```

### Level 3: Window-flip state machine + leave-no-trace (isolated socket)

```bash
cat > /tmp/smoke_flip.sh <<'EOF'
#!/usr/bin/env bash
set -u
cd /home/dustin/.config/tmux/plugins/tmux-livepicker
source tests/setup_socket.sh; source tests/helpers.sh
setup_test "lp-flip"; attach_test_client
fail=0
# Give alpha 3 windows; make the MIDDLE one (a2) active. Remember alpha's active @id.
tmux new-window -t alpha: -n a2
tmux new-window -t alpha: -n a3
tmux select-window -t alpha:a2
alpha_active_before="$(tmux list-windows -t =alpha -F '#{window_id}' -f '#{window_active}')"
echo "alpha active window before flip: [$alpha_active_before]"
# Inline preview so the flip is deterministic (defer=off -> preview.sh runs inline).
tmux set-option -g @livepicker-preview-defer off
"$LIVEPICKER_SCRIPTS/livepicker.sh"                       # activate; highlight = driver (index 0)
# Highlight alpha deterministically: type "alpha" -> filtered[0] == alpha, index 0.
for c in a l p h a; do "$LIVEPICKER_SCRIPTS/input-handler.sh" type "$c" >/dev/null 2>&1 || true; done
# next-window: lazily derive alpha's list, reset cursor to a2 (active), advance to next.
"$LIVEPICKER_SCRIPTS/input-handler.sh" next-window >/dev/null 2>&1 || true
list="$(tmux show-option -gqv @livepicker-cand-win-list)"
curs="$(tmux show-option -gqv @livepicker-cand-win-cursor)"
pid="$(tmux show-option -gqv @livepicker-preview-win-id)"
sess="$(tmux show-option -gqv @livepicker-cand-win-session)"
echo "after next-window: session=[$sess] cursor=[$curs] preview-win-id=[$pid] list=[$(printf '%s ' $list)]"
[ "$sess" = "alpha" ] || { echo "FAIL: cand-win-session != alpha [$sess]"; fail=1; }
[ -n "$list" ]        || { echo "FAIL: cand-win-list empty"; fail=1; }
# cursor advanced from the active index; preview-win-id == list[cursor]
mapfile -t arr < <(printf '%s\n' "$list")
[[ "$curs" =~ ^[0-9]+$ ]] || { echo "FAIL: cursor not numeric [$curs]"; fail=1; }
[ "$pid" = "${arr[$curs]}" ] || { echo "FAIL: preview-win-id [$pid] != list[$curs]=${arr[$curs]}"; fail=1; }
# Wrap test: alpha has 3 windows -> cursor cycles within 0..2 across repeated next-window.
for _ in 1 2 3 4; do "$LIVEPICKER_SCRIPTS/input-handler.sh" next-window >/dev/null 2>&1 || true; done
curs2="$(tmux show-option -gqv @livepicker-cand-win-cursor)"
echo "cursor after 4 more next-window (wraps): [$curs2]"
[[ "$curs2" =~ ^[0-9]+$ ]] && [ "$curs2" -ge 0 ] && [ "$curs2" -le 2 ] \
  || { echo "FAIL: cursor out of wrap range [$curs2]"; fail=1; }
# prev-window decrements (wraps).
"$LIVEPICKER_SCRIPTS/input-handler.sh" prev-window >/dev/null 2>&1 || true
curs3="$(tmux show-option -gqv @livepicker-cand-win-cursor)"
echo "cursor after prev-window: [$curs3]"
[[ "$curs3" =~ ^[0-9]+$ ]] && [ "$curs3" -ge 0 ] && [ "$curs3" -le 2 ] \
  || { echo "FAIL: prev cursor out of range [$curs3]"; fail=1; }
# LEAVE-NO-TRACE (Invariant B): alpha's OWN active window must be UNCHANGED after all flips.
# The flip links the chosen window into the DRIVER and selects it THERE; it never calls
# select-window on alpha (enforced by preview.sh — P2.M1.T2.S1).
alpha_active_after="$(tmux list-windows -t =alpha -F '#{window_id}' -f '#{window_active}')"
echo "alpha active window after flips: [$alpha_active_after]"
[ "$alpha_active_before" = "$alpha_active_after" ] \
  && echo "OK: alpha active window untouched (Invariant B)" \
  || { echo "FAIL: alpha active window changed [$alpha_active_before] -> [$alpha_active_after]"; fail=1; }
"$LIVEPICKER_SCRIPTS/input-handler.sh" cancel >/dev/null 2>&1 || true
teardown_test
[ "$fail" -eq 0 ]
EOF
bash /tmp/smoke_flip.sh; rc=$?; rm -f /tmp/smoke_flip.sh; exit $rc
# Expected: all OK. Proves the flip state machine (lazy derive, cursor advance, wrapping,
# prev-window) + STATE_PREVIEW_WIN_ID tracking + LEAVE-NO-TRACE (the candidate's own active
# window is never mutated). The isolated socket sources the user conf so the driver + alpha
# fixtures are real sessions; defer=off makes the preview inline/deterministic.
# NOTE: this L3 smoke REQUIRES P2.M1.T2.S1's preview.sh chosen-window link (it delegates the
# link to _lp_preview_dispatch "$S" "$W"). If that task is not yet merged, the leave-no-trace
# assertion is the canary that reveals it (alpha's active would change). Coordinate merge order.
```

### Level 4: Self-session flip (driver windows, no link)

```bash
cat > /tmp/smoke_selfflip_nav.sh <<'EOF'
#!/usr/bin/env bash
set -u
cd /home/dustin/.config/tmux/plugins/tmux-livepicker
source tests/setup_socket.sh; source tests/helpers.sh
setup_test "lp-selfflip"; attach_test_client
fail=0
# Give the driver a SECOND window so a flip has somewhere to go.
tmux new-window -t driver: -n drv2
tmux select-window -t driver:0            # back to the original (index 0) window
tmux set-option -g @livepicker-preview-defer off
"$LIVEPICKER_SCRIPTS/livepicker.sh"       # highlight = driver (index 0) == the self-session
# next-window flips among the DRIVER's own windows (preview.sh self path: select, no link).
"$LIVEPICKER_SCRIPTS/input-handler.sh" next-window >/dev/null 2>&1 || true
pid="$(tmux show-option -gqv @livepicker-preview-win-id)"
curs="$(tmux show-option -gqv @livepicker-cand-win-cursor)"
sess="$(tmux show-option -gqv @livepicker-cand-win-session)"
drv="$(tmux display-message -p '#{session_name}')"
shown="$(tmux list-windows -t =driver -F '#{window_name}' -f '#{window_active}')"
echo "self flip: session=[$sess] (driver=[$drv]) cursor=[$curs] preview-win-id=[$pid] shown=[$shown]"
[ "$sess" = "$drv" ] && echo "OK: flip derived the driver's own list" || { echo "FAIL session [$sess]"; fail=1; }
[ "$shown" = "drv2" ] && echo "OK: driver active moved to flipped window (self-session flip)" || { echo "FAIL shown [$shown]"; fail=1; }
# cancel's hard reset restores the driver's original window (restore STEP 2).
"$LIVEPICKER_SCRIPTS/input-handler.sh" cancel >/dev/null 2>&1 || true
teardown_test
[ "$fail" -eq 0 ]
EOF
bash /tmp/smoke_selfflip_nav.sh; rc=$?; rm -f /tmp/smoke_selfflip_nav.sh; exit $rc
# Expected: the self-session flip derives the driver's window list, advances the cursor,
# and (via preview.sh's self path) selects the flipped driver window — NO link. The driver's
# active window moves while browsing; cancel restores it (PRD §3.13). Confirms FINDING 7
# (no self-session special case in input-handler — preview.sh owns the edge).
```

## Final Validation Checklist

### Technical Validation

- [ ] `bash -n` + `shellcheck` clean on `scripts/input-handler.sh`.
- [ ] `next-window` + `prev-window` branches present (each once), before `confirm`.
- [ ] Both use the VERIFIED `awk -F: '$2==1{print NR-1; exit}'` active-index (NOT grep|cut).
- [ ] Both call `_lp_preview_dispatch "$S" "$W"` (2-arg); both set STATE_PREVIEW_WIN_ID.
- [ ] Tabs only on the new branch lines; inline `local` declarations.
- [ ] SCOPE: `_lp_fire_preview`/`_lp_preview_dispatch`/`preview.sh` NOT edited here
      (still carry P2.M1.T2.S1's `win_id="${2:-}"` binding — L1 asserts it).
- [ ] SCOPE: session-nav/type/backspace/cancel/`_lp_sync_preview_to_top_match` NOT touched.

### Feature Validation

- [ ] Flip advances STATE_CAND_WIN_CURSOR (numeric, wrapping) on a 3-window candidate (L3).
- [ ] Flip populates STATE_CAND_WIN_LIST + sets STATE_CAND_WIN_SESSION=S + STATE_PREVIEW_WIN_ID=W (L3).
- [ ] prev-window decrements/wraps (L3).
- [ ] LEAVE-NO-TRACE: the candidate's OWN active window is unchanged after flips (L3 — Invariant B).
- [ ] Self-session flip selects among the driver's own windows (no link); cancel restores (L4).
- [ ] `tests/run.sh` GREEN (L2 — no regression in the existing paths).

### Code Quality Validation

- [ ] Branch shape mirrors session-nav (invalidate → resolve → derive → advance → redraw → dispatch).
- [ ] No scroll-into-view on the flip (line 1 is unchanged by a window flip).
- [ ] Lazy list derivation is robust to the activate-time `LIST=''` init (re-derives on first flip).
- [ ] cursor sanitized (`[[ =~ ^[0-9]+$ ]] || 0`) before modulo; prev uses `+wlen` (no negative modulo).
- [ ] README Usage is non-contradictory (window keys flip; session keys move) and does NOT claim
      confirm-on-window (that's P2.M2.T1).

### Documentation & Deployment

- [ ] README.md Usage updated (Mode A): session-nav step + window-flip step (contract prose); renumbered.
- [ ] No CHANGELOG edit here (the changeset CHANGELOG is P4.M1.T1.S2).
- [ ] No new test FILE (the formal flip suite is P2.M3.T1.S1); L3/L4 are throwaway smoke probes.

---

## Anti-Patterns to Avoid

- ❌ Don't use `grep ':1' | cut -d: -f1` for the active-window index. That yields the @id
  (e.g. `@4`), NOT the 0-based index STATE_CAND_WIN_CURSOR needs. Use the VERIFIED
  `awk -F: '$2==1{print NR-1; exit}'` (FINDING 1 — the single most likely mis-step).
- ❌ Don't edit `_lp_fire_preview` / `_lp_preview_dispatch` / `preview.sh`. They are
  P2.M1.T2.S1's deliverables (assumed COMPLETE) — they ALREADY accept the WIN_ID 2nd arg
  and thread it into the 3-arg run-shell. You only CALL `_lp_preview_dispatch "$S" "$W"`.
  Editing them duplicates work and causes a merge conflict. (FINDING 2.)
- ❌ Don't touch `_lp_sync_preview_to_top_match` or the next/prev-session/type/backspace/
  cancel branches. The cursor reset on session-nav/type/backspace is the SEPARATE sibling
  task P2.M1.T3.S2. `_lp_sync_preview_to_top_match` passing `''` (its current 1-arg call →
  win_id="") is ALREADY correct (preview defaults to active). (FINDING 3.)
- ❌ Don't add a self-session special case in the branch. When S == the driver the branch is
  identical; preview.sh (P2.M1.T2.S1) detects the self-session and selects among the driver's
  own windows. (FINDING 7.)
- ❌ Don't call `_lp_scroll_into_view` on the flip. Scroll is the line-1 SESSION-tab viewport;
  a window flip does not move the line-1 highlight (PRD §3.6: "The flip does not change line 1").
- ❌ Don't call `switch-client` or `select-window` (on the candidate) in the branch. The flip
  only mutates picker-internal STATE + delegates the single, driver-only side-effect to
  preview.sh (Invariant A/B). (PRD §4, gap_analysis §Gap b.)
- ❌ Don't edit `input_main`'s top-of-function `local` line. Declare the new locals INLINE in
  the case branch with `local` — the file's OWN confirm branch does exactly this
  (`local w_sess`, `local drv_wins drv_active`). (FINDING 6.)
- ❌ Don't hardcode window indices or assume contiguous @ids. Re-derive the list each time the
  candidate changes; address windows by `@id` (the cursor is an index into the just-derived
  list, and `W=list[cursor]` is the @id preview.sh takes). (FINDING 1/4.)
- ❌ Don't skip the `STATE_PREVIEW_WIN_ID=W` synchronous write. It is redundant with
  preview.sh's write BUT load-bearing for responsiveness (the preview is deferred; the write
  lets line 2's redraw reflect the chosen window before the bg link completes). (FINDING 8.)
- ❌ Don't claim confirm "lands on the flipped window" in the README. That's P2.M2.T1 (not
  done). The window-flip Usage step says you are only LOOKING; the candidate's active window
  is untouched. The comprehensive two-axis prose is P4.M1.T1.S1. (FINDING 9.)
- ❌ Don't use spaces for indent in input-handler.sh — TABS only (a space oldText won't match).
  (README.md, by contrast, uses SPACE indentation — match each file's own style.)

---

## Confidence Score

**9 / 10** for one-pass success. Rationale: the change is a pure additive (two new case
branches + a README Usage reword) — no existing branch body or helper is modified, so the
regression surface is near-zero (the new branches fire only on a window-axis key). The one
load-bearing non-obvious primitive — the active-window 0-based INDEX — is VERIFIED
empirically (FINDING 1: `awk -F: '$2==1{print NR-1; exit}'` matches `list-windows -f
'#{window_active}'` exactly; the contract's literal `grep|cut` is the wrong type and is
explicitly called out). The branch shape mirrors the existing next/prev-session branches
verbatim (FINDING 4), and the inline-`local` style is the file's own confirm-branch
convention (FINDING 6). The two scope boundaries (don't touch P2.M1.T2.S1's fire/dispatch/
preview; don't touch S2's session-nav/type/cursor-reset branches) are stated as hard
anti-patterns. Residual risk: the L3/L4 smoke gates DEPEND on P2.M1.T2.S1 being merged
(the flip delegates the link to `_lp_preview_dispatch "$S" "$W"`); the leave-no-trace
assertion is the canary — coordinate merge order so P2.M1.T2.S1 lands before/at the same
time as this task. The `bash -n`/`shellcheck` + suite-green + L3/L4 smoke are the firm gates.
