# PRP — P2.M1.T3.S2: Reset window-cursor on session-nav and type/backspace

---

## Goal

**Feature Goal**: On every session move (`next-session`/`prev-session`) and every
filter change (`type`/`backspace`/`cancel`-clear-path), **reset the window-cursor
state** (`@livepicker-cand-win-session` / `-cand-win-list` / `-cand-win-cursor`)
so that each candidate starts previewed on its OWN active window and per-candidate
flip history is NOT remembered across session moves or filter changes
(**Invariant B** — PRD §6 h3.5 'Session navigation' + h3.4 'Filtering and ranking').
Also make `_lp_sync_preview_to_top_match` pass `''` as the window-id explicitly so
preview.sh defaults the top match to its active window (the "preview follows the
top match" behavior — PRD §3.4/§3.5).

**Deliverable** (1 existing file edited, NO new file, NO README — DOCS = none):
**`scripts/input-handler.sh`** — six precise additive edits:
1. `_lp_sync_preview_to_top_match`: `_lp_preview_dispatch "$_top"` → `_lp_preview_dispatch "$_top" ""`.
2. `type` branch: after `STATE_INDEX=0`, invalidate the window-cursor cache (SESSION='', LIST='', CURSOR='0').
3. `backspace` branch: same invalidation after `STATE_INDEX=0`.
4. `cancel` clear-path: same invalidation after `STATE_INDEX=0` (4-tab indent).
5. `next-session` branch: after resolving `$target`, bind SESSION=`$target` + invalidate LIST/CURSOR.
6. `prev-session` branch: same as next-session (mirror).

**Success Definition**:
- `bash -n`/`shellcheck` clean on `scripts/input-handler.sh`.
- `tests/run.sh` stays GREEN (the resets are pure picker-internal STATE writes;
  the sync `""` arg is a functional no-op — win_id already defaulted to "").
- On an isolated socket: pre-seed stale window-cursor state, drive each action
  (`next-session`, `prev-session`, `type`, `backspace`, `cancel`-clear), and
  assert the window-cursor keys reset exactly as specified (L3 smoke).
- No edits to `_lp_fire_preview`/`_lp_preview_dispatch`/`preview.sh`/`state.sh`
  (P2.M1.T2.S1 already landed the `win_id="${2:-}"` signature; this task only
  CALLS them) NOR to `next-window`/`prev-window` (the parallel sibling
  P2.M1.T3.S1) NOR README (DOCS = none).

## User Persona (if applicable)

**Target User**: An end user browsing the picker who moves between candidates and
refines the query. (Internal state-hygiene seam for the window-flip subsystem
P2.M1.T3.S1 + the confirm-on-window P2.M2.T1; DOCS = none here.)

**Use Case**: Without this task, stale window-cursor state from a previously
flipped candidate could bleed across a session move or filter change — e.g. move
to candidate B and the preview/flipped-window remembers candidate A's window
index (violating Invariant B: "every candidate starts previewed on its own active
window; per-candidate flip history is not remembered across session moves").

**User Journey**: highlight A → flip A's windows (cursor advances) → move to B →
the preview shows B's OWN active window (not A's flipped index) → type a query →
the top match is previewed on its own active window. The window-cursor cache is
invalidated on every move/filter change so the next flip always re-derives for the
current candidate.

**Pain Points Addressed**: PRD §3.5 — "per-candidate flip history is not
remembered across session moves (Invariant B)"; §3.4 — "type/backspace reset
index to 0 — the top match is re-previewed. The cursor must follow."

## Why

- **PRD §6 h3.5** (Session navigation): "Entering a new candidate also resets the
  window cursor to that candidate's current active window (every candidate starts
  previewed on its own active window; per-candidate flip history is not remembered
  across session moves — Invariant B)."
- **PRD §6 h3.4** (Filtering and ranking): "After each change the handler sets
  `@livepicker-index` and `@livepicker-scroll` to `0` (top-ranked match). The
  top-ranked match is index 0 and is what the preview follows." The window cursor
  must follow — the top match is previewed on its OWN active window.
- **Invariant B** (PRD §4): browsing must never mutate any candidate's state, and
  a stale window-cursor index pointing at the wrong candidate would either show
  the wrong window or, once the flip subsystem lands, advance the wrong list.
- **Defense in depth with P2.M1.T3.S1**: S1's flip branches re-derive the window
  list when `STATE_CAND_WIN_SESSION != S OR list == ""`. S2's invalidation
  (`LIST=""` on every move/filter change) guarantees the next flip ALWAYS
  re-derives for the current candidate — the two are coherent under every merge
  ordering (FINDING 6).

## What

Six additive edits to `scripts/input-handler.sh` (single file). Each is a 3-line
`set_state` cluster + an explanatory comment, inserted at the precise point the
contract specifies. Two reset shapes (FINDING 3):

- **session-nav** (`next-session`/`prev-session`): AFTER resolving `$target`, bind
  the cache to the KNOWN new candidate:
  `SESSION="$target"`; `LIST=""`; `CURSOR="0"`.
- **type/backspace/cancel-clear**: AFTER `STATE_INDEX=0`, INVALIDATE the cache (the
  top match's session is not resolved in-line):
  `SESSION=""`; `LIST=""`; `CURSOR="0"`.
- **`_lp_sync_preview_to_top_match`**: pass `''` explicitly as the window-id.

### Success Criteria

- [ ] `_lp_sync_preview_to_top_match` calls `_lp_preview_dispatch "$_top" ""`
      (explicit empty window-id) — exactly once.
- [ ] `next-session` + `prev-session` each, after `target="${filtered[$new_idx]}"`,
      set `STATE_CAND_WIN_SESSION="$target"`, `STATE_CAND_WIN_LIST=""`,
      `STATE_CAND_WIN_CURSOR="0"`.
- [ ] `type` + `backspace` + `cancel`-clear each, after `STATE_INDEX=0`, set
      `STATE_CAND_WIN_SESSION=""`, `STATE_CAND_WIN_LIST=""`,
      `STATE_CAND_WIN_CURSOR="0"`.
- [ ] The cancel-clear cluster is **4-tab** indented (nested in `if`); the other
      five edits are **3-tab** indented (FINDING 2).
- [ ] `tests/run.sh` GREEN; `bash -n`/`shellcheck` clean.
- [ ] NO edits to `_lp_fire_preview`/`_lp_preview_dispatch`/`preview.sh`/`state.sh`;
      NO `next-window`/`prev-window` branches; NO README edit.

## All Needed Context

### Context Completeness Check

_Pass_: a developer who has never seen this repo implements all six edits from
(a) the verbatim oldText/newText anchors below (every region quoted from the
CURRENT `scripts/input-handler.sh`, TAB-indented, with the §/— UTF-8 chars
preserved), and (b) the 8 findings in `research/findings.md` — most critically
**FINDING 2** (the 6 edit points + exact indentation: 3 tabs vs 4 tabs),
**FINDING 3** (session-nav binds SESSION=$target; type/backspace sets SESSION=""),
**FINDING 4** (`set_state "$KEY" ""` is a safe SET-EMPTY under `set -u`),
**FINDING 5** (the sync `""` arg is a documented no-op; preview.sh chosen_win=""
→ active window), **FINDING 6** (zero overlap with the parallel P2.M1.T3.S1).
No external library knowledge beyond the shipped `set_state`/`get_state`/
`_lp_preview_dispatch`/`_lp_sync_preview_to_top_match` helpers.

### Documentation & References

```yaml
# MUST READ — the ONLY file you EDIT.
- file: scripts/input-handler.sh
  why: the 6 edit points — _lp_sync_preview_to_top_match helper (L146), type (L272),
       backspace (L313), next-session (L354), prev-session (L387), cancel clear-path
       (L638) — verified present + their TEXT anchors UNIQUE in the current file (the
       sibling P2.M1.T3.S1 landed next-window L405 / prev-window L466 concurrently;
       its insertion only shifted the cancel-clear line 526→638). _lp_preview_dispatch
       ALREADY accepts win_id="${2:-}" (P2.M1.T2.S1 landed). The cancel clear-path is
       the model for set_state "".
  pattern: "set_state \"$STATE_FILTER\" \"\" in the cancel clear-path — the
           SET-EMPTY idiom this task reuses for the SESSION='' invalidation."
  gotcha: TAB-indented (3 tabs for branch bodies; 4 tabs for the cancel clear-path).
          A space oldText won't match. The § and — chars are UTF-8 — preserve them.

# MUST READ — the state keys you read/write (DEFINED+INIT'd+TEARDOWN-WIRED by P2.M1.T1.S1 — COMPLETE).
- file: scripts/state.sh
  why: STATE_CAND_WIN_SESSION (@livepicker-cand-win-session), STATE_CAND_WIN_LIST
       (@livepicker-cand-win-list), STATE_CAND_WIN_CURSOR (@livepicker-cand-win-cursor)
       — all readonly, all in _STATE_RUNTIME_KEYS (teardown wired), all init'd at
       activate (SESSION=ORIG_SESSION, LIST='', CURSOR='0'). set_state/get_state accessors.
  critical: these keys ALREADY EXIST. Do NOT add/rename keys. Do NOT edit state.sh.

# MUST READ — the preview seam you consume (the sync '' arg delegates here).
- file: scripts/preview.sh
  why: argv[2]=chosen window-id ("" for session-nav/type/top-match -> active window).
       L89 local chosen_win="${2:-}"; L191 when chosen_win is empty it resolves the
       candidate's ACTIVE window via list-windows -f '#{window_active}'; the
       elif [ -n "$chosen_win" ] select-window branch (L162) is skipped -> candidate
       unchanged (Invariant B). Confirms the sync '' arg = active-window preview.
  critical: DO NOT edit preview.sh. It is P2.M1.T2.S1's deliverable (COMPLETE).

# MUST READ — the parallel sibling task boundary (do NOT collide with P2.M1.T3.S1).
- docfile: plan/004_2c5127285a90/P2M1T3S1/PRP.md
  why: P2.M1.T3.S1 ADDS next-window/prev-window case branches (between prev-session's
       end and the confirm seam comment) + edits README. THIS task EDITS the EXISTING
       next-session/prev-session/type/backspace/cancel branches + _lp_sync. Zero
       textual overlap (FINDING 6). Treat S1 as a non-conflicting contract.
  critical: Do NOT add next-window/prev-window branches. Do NOT edit README
            (DOCS = none here). Do NOT edit _lp_fire_preview/_lp_preview_dispatch.

# MUST READ — PRD §3.5 + §3.4 (the exact spec) + §4 (Invariant B).
- docfile: PRD.md
  why: §3.5 — "Entering a new candidate also resets the window cursor to that
       candidate's current active window ... per-candidate flip history is not
       remembered across session moves (Invariant B)." §3.4 — type/backspace reset
       index to 0; the top match is what the preview follows. §4 Invariant B (no
       candidate state mutation while browsing). §3.13 self-session note (preview.sh
       owns it; the cursor reset is identical for self/non-self — the dispatch passes
       the session only, no win_id).
  section: "§3.5 Session navigation", "§3.4 Filtering and ranking", "§4 The core rule"

# MUST READ — the ground-truth findings for THIS task (8 findings).
- docfile: plan/004_2c5127285a90/P2M1T3S2/research/findings.md
  why: FINDING 1 (4 keys exist — no state.sh edit); FINDING 2 (the 6 edit points +
       3-tab vs 4-tab indentation); FINDING 3 (session-nav binds SESSION=$target vs
       type/backspace sets SESSION=""); FINDING 4 (set_state "" is safe); FINDING 5
       (sync '' is a documented no-op); FINDING 6 (no conflict with S1); FINDING 7
       (no rename/delete/refresh-width edit); FINDING 8 (validation).
  critical: FINDING 2 + FINDING 3 are the two things most likely to be mis-done
            (wrong indent, swapped reset shape). Read BEFORE editing.
```

### Current Codebase tree (run `tree` in the root of the project)

```bash
tmux-livepicker/
  scripts/
    input-handler.sh     # MODIFY: 6 edits (5 cursor-resets + 1 sync '' arg).
    state.sh             # UNCHANGED (4 window-cursor keys already exist — P2.M1.T1.S1).
    preview.sh           # UNCHANGED (chosen_win="" -> active window — P2.M1.T2.S1).
    options.sh utils.sh rank.sh layout.sh renderer.sh livepicker.sh restore.sh session-mgmt.sh  # UNCHANGED
  README.md              # UNCHANGED (DOCS = none — internal state reset behavior).
  tests/                 # UNCHANGED (no test asserts window-cursor state; the window suite is P2.M3.T1.S1).
  plan/004_2c5127285a90/{P2M1T3S2/research/findings.md, P2M1T3S1/PRP.md, P2M1T2S1/PRP.md, P2M1T1S1/PRP.md}
```

### Desired Codebase tree with files to be added and responsibility of file

```bash
scripts/input-handler.sh   # +5 window-cursor reset clusters (next/prev-session bind SESSION=$target +
                           #   invalidate LIST/CURSOR; type/backspace/cancel-clear invalidate all 3)
                           #   + _lp_sync_preview_to_top_match passes '' window-id explicitly.
                           # Every candidate starts previewed on its own active window; flip history
                           # is not remembered across session moves / filter changes (Invariant B).
```

### Known Gotchas of our codebase & Library Quirks

```bash
# CRITICAL (FINDING 2 — indentation): input-handler.sh is TAB-indented. The branch
# bodies (type/backspace/next-session/prev-session) are 3 TABS; the cancel CLEAR-path
# is 4 TABS (nested inside `if [ -n "$cur_filter" ]; then`). Every oldText/newText
# uses leading TABS. A space-prefixed oldText won't match. The § and — are UTF-8 —
# preserve them in the anchors (copy them verbatim from the file).

# CRITICAL (FINDING 3 — two reset shapes): session-nav binds SESSION=$target (the new
# candidate's NAME, known in-line). type/backspace/cancel-clear set SESSION="" (the
# top match's session is NOT resolved in-line — _lp_sync_preview_to_top_match does it
# later). Do NOT swap. Both set LIST="" + CURSOR="0".

# CRITICAL (FINDING 4): set_state "$KEY" "" is a SET-EMPTY (tmux set-option -g @x ""),
# NOT an unset. get_state reads it back as "" (the default). Safe under set -u ($2 is
# SET-but-empty). The file ALREADY uses this idiom (cancel clear-path L524). Do NOT
# use tmux_unset_opt / -gu (restore's teardown concern).

# GOTCHA (FINDING 5): _lp_preview_dispatch "$_top" (1 arg) ALREADY yields win_id=""
# via the ${2:-} default. Adding the explicit "" 2nd arg is a documented NO-OP for
# correctness but makes the "top match previewed on its active window" intent explicit
# (the contract asks for it). preview.sh chosen_win="" -> active window (L191).

# GOTCHA (FINDING 6): the parallel sibling P2.M1.T3.S1 adds next-window/prev-window
# branches (between prev-session end + confirm seam comment) + README. This task edits
# the EXISTING branches ABOVE that anchor. Zero overlap — land in either order. Do NOT
# add next-window/prev-window, do NOT edit _lp_fire_preview/_lp_preview_dispatch/
# preview.sh (P2.M1.T2.S1), do NOT edit README (DOCS=none).

# GOTCHA (FINDING 7): NO cursor reset for rename/delete/refresh-width. rename (same
# session, new name) + delete (highlight moves) are handled by S1's lazy-derive
# (SESSION != S -> re-derive). They live in session-mgmt.sh anyway (out of file scope).

# GOTCHA: the cursor reset is picker-INTERNAL STATE only — no switch-client, no
# select-window, no preview work in the reset itself. The preview re-link is the
# EXISTING _lp_preview_dispatch "$target" (session-nav) / _lp_sync_preview_to_top_match
# (type/backspace/cancel) call that ALREADY follows in each branch. This task only adds
# the 3 set_state writes BEFORE those existing calls (Invariants A/B untouched).
```

## Implementation Blueprint

### Data models and structure

No new data model. The contract is six edits to `scripts/input-handler.sh`. The
window-cursor reset state machine:

| Branch | Trigger | SESSION | LIST | CURSOR | Why |
|--------|---------|---------|------|--------|-----|
| next-session | after `target=` | `$target` | `""` | `"0"` | new candidate known; bind cache |
| prev-session | after `target=` | `$target` | `""` | `"0"` | mirror next-session |
| type | after `INDEX=0` | `""` | `""` | `"0"` | top match unknown; invalidate |
| backspace | after `INDEX=0` | `""` | `""` | `"0"` | top match unknown; invalidate |
| cancel-clear | after `INDEX=0` | `""` | `""` | `"0"` | top match unknown; invalidate |
| _lp_sync | (call site) | — | — | — | `_lp_preview_dispatch "$_top" ""` |

### Implementation Tasks (ordered by dependencies)

```yaml
Task 1: EDIT scripts/input-handler.sh — _lp_sync_preview_to_top_match passes '' window-id
  - FILE: ./scripts/input-handler.sh (EXISTING).
  - PLACEMENT: the _lp_preview_dispatch call at the END of _lp_sync_preview_to_top_match (L146 — above the sibling's insertion, unchanged).
  - oldText (verbatim, 1-TAB indent — the helper is top-level, not in input_main):
  		# Delegate the preview to _lp_preview_dispatch (the caller has ALREADY issued
  		# _lp_status_redraw so the highlight moves before this runs). Empty filtered
  		# list -> _top="" -> no preview fires (leave the prior pane as-is).
  		_lp_preview_dispatch "$_top"
  - newText (unchanged comment + the explicit '' arg + an intent comment):
  		# Delegate the preview to _lp_preview_dispatch (the caller has ALREADY issued
  		# _lp_status_redraw so the highlight moves before this runs). Empty filtered
  		# list -> _top="" -> no preview fires (leave the prior pane as-is).
  		# P2.M1.T3.S2: pass '' as the window-id explicitly. The top match (index 0) is
  		# previewed on its OWN active window (PRD §3.4/§3.5). win_id="" -> preview.sh
  		# chosen_win="" -> it resolves the candidate's active window (the "preview
  		# follows the top match" behavior). Making it explicit documents the intent.
  		_lp_preview_dispatch "$_top" ""
  - WHY: PRD §3.4 — "the top-ranked match is index 0 and is what the preview follows";
         §3.5 — every candidate is previewed on its own active window. FINDING 5 (the
         arg is a documented no-op; preview.sh chosen_win="" -> active window L191).

Task 2: EDIT scripts/input-handler.sh — type branch invalidates the window-cursor cache
  - FILE: ./scripts/input-handler.sh (EXISTING). 3-TAB indent (branch body inside input_main).
  - oldText (verbatim, 3 TABS; the "now ALSO follows the top match" comment is the unique anchor):
  			# follows live") via _lp_sync_preview_to_top_match, mirroring nav.
  			set_state "$STATE_INDEX" "0"
  			# Reset the viewport scroll to the top (PRD §19 §3.32). A status-only STATE write
  - newText (the reset cluster inserted AFTER INDEX=0, BEFORE the scroll reset):
  			# follows live") via _lp_sync_preview_to_top_match, mirroring nav.
  			set_state "$STATE_INDEX" "0"
  			# Invalidate the cached window list so the next window-flip re-derives it for the
  			# (possibly new) top match (PRD §3.4 / P2.M1.T3.S2). The top match (index 0) is
  			# re-previewed on its OWN active window by _lp_sync_preview_to_top_match below
  			# (which passes '' as the window-id -> preview.sh defaults to active — PRD §3.5).
  			# Per-candidate flip history is NOT remembered across filter changes (Invariant B).
  			set_state "$STATE_CAND_WIN_SESSION" ""
  			set_state "$STATE_CAND_WIN_LIST" ""
  			set_state "$STATE_CAND_WIN_CURSOR" "0"
  			# Reset the viewport scroll to the top (PRD §19 §3.32). A status-only STATE write
  - WHY: the top match's session is NOT resolved in-line (_lp_sync resolves filtered[0]
         later), so INVALIDATE (SESSION="") — FINDING 3. FINDING 4 (set_state "" is safe).

Task 3: EDIT scripts/input-handler.sh — backspace branch invalidates the window-cursor cache
  - FILE: ./scripts/input-handler.sh (EXISTING). 3-TAB indent.
  - oldText (verbatim, 3 TABS; "safe — the renderer clamps + handles FLEN=0 itself." (no
    "(FINDING 4). The preview" suffix) distinguishes backspace from type):
  			# safe — the renderer clamps + handles FLEN=0 itself.
  			set_state "$STATE_INDEX" "0"
  			# Reset the viewport scroll to the top (PRD §19 §3.32). A status-only STATE write
  - newText (mirror Task 2's reset cluster):
  			# safe — the renderer clamps + handles FLEN=0 itself.
  			set_state "$STATE_INDEX" "0"
  			# Invalidate the cached window list so the next window-flip re-derives it for the
  			# (possibly new) top match (PRD §3.4 / P2.M1.T3.S2). The top match (index 0) is
  			# re-previewed on its OWN active window by _lp_sync_preview_to_top_match below
  			# (passes '' window-id -> preview.sh defaults to active — PRD §3.5; Invariant B).
  			set_state "$STATE_CAND_WIN_SESSION" ""
  			set_state "$STATE_CAND_WIN_LIST" ""
  			set_state "$STATE_CAND_WIN_CURSOR" "0"
  			# Reset the viewport scroll to the top (PRD §19 §3.32). A status-only STATE write
  - WHY: mirror type (FINDING 3 — type/backspace/cancel-clear all INVALIDATE).

Task 4: EDIT scripts/input-handler.sh — cancel CLEAR-path invalidates the window-cursor cache
  - FILE: ./scripts/input-handler.sh (EXISTING). 4-TAB indent (nested in `if [ -n "$cur_filter" ]`). Now at L638 after the sibling's insertion (was L526).
  - oldText (verbatim, 4 TABS; "(empty filter matches" distinguishes the cancel-clear comment):
  				# safe — the renderer clamps + handles FLEN=0 (empty filter matches
  				# ALL names; renderer FINDING 4 / rank.sh).
  				set_state "$STATE_INDEX" "0"
  				# Reset the viewport scroll to the top (PRD §19 §3.32). A status-only STATE write
  - newText (4-TAB indent reset cluster — MIRROR the type/backspace logic):
  				# safe — the renderer clamps + handles FLEN=0 (empty filter matches
  				# ALL names; renderer FINDING 4 / rank.sh).
  				set_state "$STATE_INDEX" "0"
  				# Invalidate the cached window list so the next window-flip re-derives it for the
  				# (possibly new) top match (PRD §3.4 / P2.M1.T3.S2). The top match (index 0) is
  				# re-previewed on its OWN active window by _lp_sync_preview_to_top_match below
  				# (passes '' window-id -> preview.sh defaults to active — PRD §3.5; Invariant B).
  				set_state "$STATE_CAND_WIN_SESSION" ""
  				set_state "$STATE_CAND_WIN_LIST" ""
  				set_state "$STATE_CAND_WIN_CURSOR" "0"
  				# Reset the viewport scroll to the top (PRD §19 §3.32). A status-only STATE write
  - WHY: the cancel CLEAR-path is a "backspace-to-empty" (sets filter "", index 0) — it is a
         filter change, so the cursor must follow (same as type/backspace). FINDING 2 (4-TAB).
         NOTE: the cancel TEAR-DOWN path (empty filter -> restore.sh cancel) needs NO edit —
         restore's clear_all_state clears every @livepicker-* key including the 4 cursor keys.

Task 5: EDIT scripts/input-handler.sh — next-session binds the cache to the new candidate
  - FILE: ./scripts/input-handler.sh (EXISTING). 3-TAB indent.
  - oldText (verbatim, 3 TABS; "REDRAW NOW (the instant the highlight changes)" is unique to next-session):
  			target="${filtered[$new_idx]}"
  			# REDRAW NOW (the instant the highlight changes): the renderer is async and
  - newText (the reset cluster AFTER target=, BEFORE the REDRAW comment):
  			target="${filtered[$new_idx]}"
  			# Reset the window cursor for the new candidate (PRD §3.5 / Invariant B / P2.M1.T3.S2):
  			# every candidate starts previewed on its OWN active window; per-candidate flip history
  			# is NOT remembered across session moves. Bind SESSION to the new target + invalidate the
  			# cached list (CURSOR='0' is the lazy default; the next window-flip re-derives the list
  			# and resets the cursor to the candidate's active window). The _lp_preview_dispatch
  			# below passes the SESSION only (no win_id) so preview.sh shows the candidate's active window.
  			set_state "$STATE_CAND_WIN_SESSION" "$target"
  			set_state "$STATE_CAND_WIN_LIST" ""
  			set_state "$STATE_CAND_WIN_CURSOR" "0"
  			# REDRAW NOW (the instant the highlight changes): the renderer is async and
  - WHY: the branch already resolved $target (the new candidate's name) — BIND SESSION to it
         (FINDING 3). The subsequent _lp_preview_dispatch "$target" (1 arg -> win_id="") re-links
         the new candidate's ACTIVE window (preview.sh chosen_win="" -> active). CURSOR='0' is a
         placeholder; the next flip re-derives the list and resets cursor to the true active index.

Task 6: EDIT scripts/input-handler.sh — prev-session binds the cache to the new candidate (mirror)
  - FILE: ./scripts/input-handler.sh (EXISTING). 3-TAB indent.
  - oldText (verbatim, 3 TABS; "REDRAW NOW (mirror next-session)" is unique to prev-session):
  			target="${filtered[$new_idx]}"
  			# REDRAW NOW (mirror next-session): the renderer is async and self-corrects
  - newText (the reset cluster AFTER target=, BEFORE the REDRAW comment — MIRROR next-session):
  			target="${filtered[$new_idx]}"
  			# Reset the window cursor for the new candidate (PRD §3.5 / Invariant B / P2.M1.T3.S2):
  			# mirror next-session — bind SESSION to the new target + invalidate the cached list.
  			set_state "$STATE_CAND_WIN_SESSION" "$target"
  			set_state "$STATE_CAND_WIN_LIST" ""
  			set_state "$STATE_CAND_WIN_CURSOR" "0"
  			# REDRAW NOW (mirror next-session): the renderer is async and self-corrects
  - WHY: mirror next-session (FINDING 3). The same $target is the new candidate.

Task 7: VALIDATE (L1 grep + L2 suite + L3 cursor-reset smoke)
  - RUN: bash -n scripts/input-handler.sh ; shellcheck scripts/input-handler.sh.
  - RUN: grep cross-checks (6 edits, no edits to fire/dispatch/preview/state/README).
  - RUN: tests/run.sh (expect GREEN — pure STATE writes + a no-op sync arg).
  - RUN: L3 isolated-socket cursor-reset smoke (pre-seed stale window-cursor state, drive
         each action, assert the reset — deterministic, independent of P2.M1.T3.S1).
```

### Implementation Patterns & Key Details

```bash
# === The TWO reset shapes (FINDING 3 — do NOT swap) ===
# session-nav (next/prev-session): the branch ALREADY resolved $target -> BIND it.
#   set_state "$STATE_CAND_WIN_SESSION" "$target"
#   set_state "$STATE_CAND_WIN_LIST" ""
#   set_state "$STATE_CAND_WIN_CURSOR" "0"
# type/backspace/cancel-clear: the top match is NOT resolved in-line -> INVALIDATE.
#   set_state "$STATE_CAND_WIN_SESSION" ""
#   set_state "$STATE_CAND_WIN_LIST" ""
#   set_state "$STATE_CAND_WIN_CURSOR" "0"

# === The SET-EMPTY idiom (FINDING 4 — already used at cancel L524) ===
set_state "$STATE_CAND_WIN_SESSION" ""   # tmux set-option -g @x "" -> get_state reads ""
# Safe under set -u: $2 is SET-but-empty (positional), not unset. NOT tmux_unset_opt/-gu.

# === The sync '' arg (FINDING 5 — documented no-op) ===
_lp_preview_dispatch "$_top" ""   # was: _lp_preview_dispatch "$_top" (win_id already "")
# preview.sh chosen_win="" -> list-windows -f '#{window_active}' -> candidate's ACTIVE window.

# === Indentation (FINDING 2) ===
# type/backspace/next-session/prev-session branch bodies: 3 TABS (^I^I^I).
# cancel CLEAR-path (nested in `if [ -n "$cur_filter" ]`): 4 TABS (^I^I^I^I).
# _lp_sync_preview_to_top_match helper (top-level function): 1 TAB (^I).
```

### Integration Points

```yaml
INPUT-HANDLER (input-handler.sh):
  - 5 cursor-reset clusters (next/prev-session bind SESSION=$target; type/backspace/
    cancel-clear invalidate) + _lp_sync '' arg. Pure picker-internal STATE writes.
  - NO change to _lp_fire_preview / _lp_preview_dispatch / preview.sh (P2.M1.T2.S1 — COMPLETE).
  - NO change to next-window/prev-window branches (the parallel sibling P2.M1.T3.S1).
  - NO change to rename/delete/refresh-width (FINDING 7 — out of scope; S1 lazy-derive handles).

STATE (state.sh): NO CHANGE. STATE_CAND_WIN_SESSION/LIST/CURSOR ALREADY defined+init'd+
  teardown-wired (P2.M1.T1.S1 — COMPLETE). This task only reads/writes them via set_state.

PREVIEW (preview.sh): NO CHANGE (P2.M1.T2.S1 — COMPLETE). The session-nav dispatch
  _lp_preview_dispatch "$target" (1 arg -> win_id="") links the new candidate's ACTIVE
  window (chosen_win="" -> list-windows -f '#{window_active}'). The sync '' arg is the
  same path for the top match. Candidate's own active window is NEVER mutated (Invariant B).

ACTIVATE (livepicker.sh): NO CHANGE. The 4 cursor keys are init'd at activate
  (SESSION=ORIG_SESSION, LIST='', CURSOR='0') — the activate init is already correct.

README.md: NO CHANGE (DOCS = none — internal state reset behavior).

CONSUMERS (FUTURE — do not implement here):
  - P2.M1.T3.S1: the next-window/prev-window flip branches (parallel sibling) re-derive
    the window list when STATE_CAND_WIN_SESSION != S OR list=="" — S2's invalidation
    (LIST="") guarantees the next flip re-derives for the current candidate.
  - P2.M2.T1: confirm resolves (S, W) from STATE_CAND_WIN_CURSOR — relies on S2's reset
    so the cursor reflects the candidate being confirmed (not a stale flipped index).
  - P2.M3.T1.S1: the formal test_window_flip.sh suite.

CONFIG / DATABASE / ROUTES: none.
```

## Validation Loop

### Level 1: Syntax & Style (Immediate Feedback)

```bash
cd /home/dustin/.config/tmux/plugins/tmux-livepicker
bash -n scripts/input-handler.sh && echo "OK: syntax"            # expect exit 0
shellcheck scripts/input-handler.sh                               # expect 0 findings
# The sync '' arg is present (exactly once):
grep -c '_lp_preview_dispatch "\$_top" ""' scripts/input-handler.sh        # == 1
# session-nav binds SESSION=$target (next + prev):
grep -c 'set_state "\$STATE_CAND_WIN_SESSION" "\$target"' scripts/input-handler.sh   # == 2
# type/backspace/cancel-clear invalidate SESSION (3 branches):
grep -c 'set_state "\$STATE_CAND_WIN_SESSION" ""' scripts/input-handler.sh           # == 3
# LIST="" + CURSOR="0" appear in all 5 reset clusters:
grep -c 'set_state "\$STATE_CAND_WIN_LIST" ""' scripts/input-handler.sh              # == 5
grep -c 'set_state "\$STATE_CAND_WIN_CURSOR" "0"' scripts/input-handler.sh           # == 5
# SCOPE GUARD: _lp_fire_preview/_lp_preview_dispatch still carry P2.M1.T2.S1's binding (NOT re-edited):
grep -c 'win_id="\${2:-}"' scripts/input-handler.sh               # == 2 (_lp_fire_preview + _lp_preview_dispatch)
# SCOPE GUARD: no next-window/prev-window branches added by THIS task (that's P2.M1.T3.S1):
! grep -q 'next-window)' scripts/input-handler.sh && echo "OK: no flip branch added" || echo "NOTE: S1 may have landed (ok)"
# No space-indent on the new lines (tabs only):
grep -Pn '^\t*    [^#/]' scripts/input-handler.sh | tail && echo "WARN: space-indent" || echo "OK: tabs"
# Expected: sync '' == 1; SESSION=$target == 2; SESSION="" == 3; LIST==5; CURSOR==5; win_id binding == 2; tabs only.
```

### Level 2: Full suite (no regression)

```bash
cd /home/dustin/.config/tmux/plugins/tmux-livepicker
tests/run.sh
# Expected: exit 0, all green. The cursor resets are pure picker-internal STATE writes
# (no behavior change to the existing type/backspace/session-nav/confirm/cancel paths),
# and the _lp_sync '' arg is a functional no-op (win_id already defaulted to ""). No
# test asserts window-cursor state today (that's P2.M3.T1.S1). NOTE: if the suite was
# red from the parallel P2.M1.T3.S1 broken-intermediate state, that task fixes it; the
# L3 smoke below is THIS task's positive gate (it is independent of S1).
```

### Level 3: Window-cursor reset state machine (isolated socket, deterministic)

```bash
cat > /tmp/smoke_cursor_reset.sh <<'EOF'
#!/usr/bin/env bash
set -u
cd /home/dustin/.config/tmux/plugins/tmux-livepicker
source tests/setup_socket.sh; source tests/helpers.sh
setup_test "lp-cursorreset"; attach_test_client
fail=0
seed_stale() {  # simulate a previously-flipped candidate's stale window-cursor state
	tmux set-option -g @livepicker-cand-win-session "STALE_SESS"
	tmux set-option -g @livepicker-cand-win-list "@9\n@8\n@7"
	tmux set-option -g @livepicker-cand-win-cursor "99"
}
check_invalidated() {  # SESSION=='' LIST=='' CURSOR=='0' (type/backspace/cancel-clear shape)
	local label="$1" sess list curs
	sess="$(tmux show-option -gqv @livepicker-cand-win-session)"
	list="$(tmux show-option -gqv @livepicker-cand-win-list)"
	curs="$(tmux show-option -gqv @livepicker-cand-win-cursor)"
	echo "[$label] session=[$sess] list=[$list] cursor=[$curs]"
	[ "$sess" = "" ]  || { echo "FAIL [$label]: SESSION != '' [$sess]"; fail=1; }
	[ "$list" = "" ]  || { echo "FAIL [$label]: LIST != '' [$list]"; fail=1; }
	[ "$curs" = "0" ] || { echo "FAIL [$label]: CURSOR != '0' [$curs]"; fail=1; }
}
# Inline preview so the dispatch is deterministic (defer=off -> preview.sh runs inline).
tmux set-option -g @livepicker-preview-defer off
"$LIVEPICKER_SCRIPTS/livepicker.sh"                       # activate; highlight = driver (index 0)
# --- type resets the window-cursor cache (INVALIDATE shape) ---
seed_stale
"$LIVEPICKER_SCRIPTS/input-handler.sh" type x >/dev/null 2>&1 || true
check_invalidated "type"
# --- backspace resets the window-cursor cache (INVALIDATE shape) ---
seed_stale
"$LIVEPICKER_SCRIPTS/input-handler.sh" backspace >/dev/null 2>&1 || true
check_invalidated "backspace"
# --- cancel CLEAR-path resets the window-cursor cache (INVALIDATE shape) ---
# (need a non-empty filter so cancel takes the CLEAR branch, not restore.sh cancel)
for c in a b c; do "$LIVEPICKER_SCRIPTS/input-handler.sh" type "$c" >/dev/null 2>&1 || true; done
seed_stale
"$LIVEPICKER_SCRIPTS/input-handler.sh" cancel >/dev/null 2>&1 || true
check_invalidated "cancel-clear"
# --- next-session binds SESSION=$target + invalidates LIST/CURSOR (BIND shape) ---
seed_stale
"$LIVEPICKER_SCRIPTS/input-handler.sh" next-session >/dev/null 2>&1 || true
ns_sess="$(tmux show-option -gqv @livepicker-cand-win-session)"
ns_list="$(tmux show-option -gqv @livepicker-cand-win-list)"
ns_curs="$(tmux show-option -gqv @livepicker-cand-win-cursor)"
echo "[next-session] session=[$ns_sess] list=[$ns_list] cursor=[$ns_curs]"
[ "$ns_list" = "" ]  || { echo "FAIL [next-session]: LIST != '' [$ns_list]"; fail=1; }
[ "$ns_curs" = "0" ] || { echo "FAIL [next-session]: CURSOR != '0' [$ns_curs]"; fail=1; }
[ "$ns_sess" != "STALE_SESS" ] || { echo "FAIL [next-session]: SESSION still STALE"; fail=1; }
[ -n "$ns_sess" ] || { echo "FAIL [next-session]: SESSION empty (should be the new target)"; fail=1; }
# --- prev-session binds SESSION=$target + invalidates LIST/CURSOR (BIND shape) ---
seed_stale
"$LIVEPICKER_SCRIPTS/input-handler.sh" prev-session >/dev/null 2>&1 || true
ps_sess="$(tmux show-option -gqv @livepicker-cand-win-session)"
ps_list="$(tmux show-option -gqv @livepicker-cand-win-list)"
ps_curs="$(tmux show-option -gqv @livepicker-cand-win-cursor)"
echo "[prev-session] session=[$ps_sess] list=[$ps_list] cursor=[$ps_curs]"
[ "$ps_list" = "" ]  || { echo "FAIL [prev-session]: LIST != '' [$ps_list]"; fail=1; }
[ "$ps_curs" = "0" ] || { echo "FAIL [prev-session]: CURSOR != '0' [$ps_curs]"; fail=1; }
[ "$ps_sess" != "STALE_SESS" ] || { echo "FAIL [prev-session]: SESSION still STALE"; fail=1; }
[ -n "$ps_sess" ] || { echo "FAIL [prev-session]: SESSION empty (should be the new target)"; fail=1; }
"$LIVEPICKER_SCRIPTS/input-handler.sh" cancel >/dev/null 2>&1 || true   # filter now empty -> restore
teardown_test
[ "$fail" -eq 0 ] && echo "ALL OK: window-cursor resets verified" || exit 1
EOF
bash /tmp/smoke_cursor_reset.sh; rc=$?; rm -f /tmp/smoke_cursor_reset.sh; exit $rc
# Expected: all OK. Proves the two reset shapes — type/backspace/cancel-clear INVALIDATE
# (SESSION='', LIST='', CURSOR='0'); next/prev-session BIND (SESSION=<new target>, LIST='',
# CURSOR='0') — on every session move and filter change (PRD §3.5/§3.4, Invariant B).
# Deterministic + independent of P2.M1.T3.S1 (pre-seeds stale state directly; does not
# require the flip branches to exist).
```

### Level 4: S1↔S2 interaction (optional — only if P2.M1.T3.S1 has landed)

```bash
# If P2.M1.T3.S1's next-window/prev-window branches are present, verify the re-derive:
# highlight alpha, next-session to beta, then next-window -> it re-derives beta's window
# list (STATE_CAND_WIN_LIST populated for beta, cursor reset to beta's active window),
# NOT alpha's stale flipped index. This is the "flip history not remembered across
# session moves" guarantee. Skip if S1 is not yet landed (the L3 smoke above is the
# authoritative gate for THIS task; the interaction is S1's positive behavior).
```

## Final Validation Checklist

### Technical Validation

- [ ] `bash -n` + `shellcheck` clean on `scripts/input-handler.sh`.
- [ ] `_lp_sync_preview_to_top_match` calls `_lp_preview_dispatch "$_top" ""` (L1 == 1).
- [ ] next-session + prev-session each set `STATE_CAND_WIN_SESSION="$target"` (L1 == 2).
- [ ] type + backspace + cancel-clear each set `STATE_CAND_WIN_SESSION=""` (L1 == 3).
- [ ] `STATE_CAND_WIN_LIST=""` appears 5×; `STATE_CAND_WIN_CURSOR="0"` appears 5× (L1).
- [ ] SCOPE: `_lp_fire_preview`/`_lp_preview_dispatch` still carry `win_id="${2:-}"` (L1 == 2).
- [ ] SCOPE: no next-window/prev-window branch added by THIS task; no README edit.
- [ ] Indentation correct (3 tabs for branch bodies; 4 tabs for cancel clear-path; 1 tab for helper).

### Feature Validation

- [ ] type/backspace/cancel-clear invalidate the cache: SESSION='', LIST='', CURSOR='0' (L3).
- [ ] next/prev-session bind the cache: SESSION=<new target>, LIST='', CURSOR='0' (L3).
- [ ] STALE seeded window-cursor state is never retained after a move/filter change (L3).
- [ ] `tests/run.sh` GREEN (L2 — no regression; pure STATE writes + a no-op sync arg).

### Code Quality Validation

- [ ] Two reset shapes are correct (session-nav BINDS $target; filter-change INVALIDATES).
- [ ] `set_state "$KEY" ""` SET-EMPTY idiom matches the existing cancel clear-path (L524).
- [ ] No switch-client / select-window / preview work in the reset itself (Invariants A/B).
- [ ] The reset clusters are placed AFTER the existing INDEX/target write, BEFORE the
      existing scroll/redraw/dispatch lines (logically grouped with the highlight change).

### Documentation & Deployment

- [ ] NO README edit (DOCS = none — internal state reset behavior).
- [ ] No CHANGELOG edit (the changeset CHANGELOG is P4.M1.T1.S2).
- [ ] No new test FILE (the formal window suite is P2.M3.T1.S1); L3 is a throwaway smoke.

---

## Anti-Patterns to Avoid

- ❌ Don't swap the two reset shapes. session-nav (next/prev-session) BINDS
  `STATE_CAND_WIN_SESSION="$target"` (the new candidate's name, resolved in-line);
  type/backspace/cancel-clear set `STATE_CAND_WIN_SESSION=""` (the top match's session
  is NOT resolved in-line). Setting SESSION="" in session-nav is still correct
  (the flip re-derives on `list==""`) but the contract explicitly says bind to the
  target — follow it. (FINDING 3.)
- ❌ Don't use SPACES for indent. input-handler.sh is TAB-indented — 3 tabs for the
  type/backspace/next-session/prev-session branch bodies, 4 tabs for the cancel
  CLEAR-path (nested in `if`), 1 tab for the `_lp_sync_preview_to_top_match` helper.
  A space-prefixed oldText won't match. Preserve the § and — UTF-8 chars. (FINDING 2.)
- ❌ Don't edit `_lp_fire_preview` / `_lp_preview_dispatch` / `preview.sh` /
  `state.sh`. They are P2.M1.T2.S1 / P2.M1.T1.S1 deliverables (COMPLETE). This task
  only CALLS `_lp_preview_dispatch` (with the `''` arg) and READS/WRITES the cursor
  keys via `set_state`. Editing them duplicates work and causes a merge conflict.
- ❌ Don't add next-window/prev-window branches or edit README. Those are the parallel
  sibling P2.M1.T3.S1 (it adds the flip branches between prev-session end + the confirm
  seam comment, and edits README Usage). This task edits the EXISTING branches ABOVE
  that anchor — zero overlap. DOCS = none here. (FINDING 6.)
- ❌ Don't use `tmux_unset_opt` / `-gu` to invalidate the cache. `set_state "$KEY" ""`
  is a SET-EMPTY (tmux set-option -g @x "") — the correct mid-browsing invalidation
  idiom (get_state reads it back as ""). `-gu` is restore's teardown concern; using it
  here would leave a gap until the next set_state. (FINDING 4.)
- ❌ Don't add a cursor reset to rename / delete / refresh-width. rename (same session,
  new name) and delete (highlight moves) are handled by P2.M1.T3.S1's lazy-derive
  (`STATE_CAND_WIN_SESSION != S` → re-derive); refresh-width changes client width, not
  the candidate. They live in session-mgmt.sh anyway (out of file scope). The contract
  lists ONLY next-session/prev-session/type/backspace/cancel-clear. (FINDING 7.)
- ❌ Don't touch `STATE_PREVIEW_WIN_ID`. It is the flip/preview subsystem's concern
  (P2.M1.T2.S1 + P2.M1.T3.S1). This task resets only SESSION/LIST/CURSOR. The session-nav
  dispatch `_lp_preview_dispatch "$target"` (1 arg → win_id="") lets preview.sh write
  STATE_PREVIEW_WIN_ID itself (the candidate's active window).
- ❌ Don't reorder the reset to AFTER the existing dispatch call. The contract says
  "AFTER setting the new STATE_INDEX and resolving the new target" (session-nav) /
  "AFTER setting STATE_INDEX=0" (type/backspace/cancel-clear). Place the reset cluster
  right after those existing writes (BEFORE the scroll/redraw/dispatch), so the cache is
  invalidated before any preview re-link reads it.
- ❌ Don't skip the `_lp_sync_preview_to_top_match` `''` arg. It is a functional no-op
  (win_id already defaulted to "" via `${2:-}`) BUT the contract explicitly asks for it,
  it documents the "top match previewed on its active window" intent, and it is robust
  to future signature changes. (FINDING 5.)
- ❌ Don't edit the cancel TEAR-DOWN path (empty filter → restore.sh cancel). restore's
  `clear_all_state` already clears every `@livepicker-*` key including the 4 cursor keys.
  Only the cancel CLEAR-path (non-empty filter) needs the reset.

---

## Confidence Score

**9 / 10** for one-pass success. Rationale: the change is six small, purely-additive
STATE-write clusters + a one-token sync-arg change in a SINGLE file — no existing
branch logic or helper is modified, so the regression surface is near-zero (the resets
are picker-internal writes; the sync `''` arg is a documented no-op). The two load-bearing
non-obvious details are both VERIFIED: (1) the two distinct reset shapes (session-nav
BINDS `$target` because it's resolved in-line; filter-changes INVALIDATE because the top
match's session is resolved later by `_lp_sync_preview_to_top_match`) — FINDING 3; and
(2) the exact indentation (3 tabs for branch bodies, 4 tabs for the cancel clear-path) —
FINDING 2. The `set_state "$KEY" ""` SET-EMPTY idiom is ALREADY used in the file (cancel
L524) — FINDING 4. The three scope boundaries (don't touch P2.M1.T2.S1's
fire/dispatch/preview; don't add P2.M1.T3.S1's flip branches; don't edit README) are
stated as hard anti-patterns. Zero textual overlap with the parallel sibling S1 (FINDING 6)
means the two land in either order. The L3 smoke is deterministic and independent of S1
(it pre-seeds stale window-cursor state and asserts the reset directly). Residual risk:
the §/— UTF-8 chars in the oldText anchors must be preserved verbatim (a careless copy
could break the match) — but the PRP quotes them exactly as they appear in the file.
The `bash -n`/`shellcheck` + suite-green + L3 smoke are the firm gates.
