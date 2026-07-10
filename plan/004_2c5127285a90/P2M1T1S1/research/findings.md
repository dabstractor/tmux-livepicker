# Research — P2.M1.T1.S1: 4 window-cursor state keys + activate init

Captured 2026-07-09 by direct inspection of the COMPLETE+shipped codebase (plan 004).
Every finding is verbatim from the source.

## FINDING 1 — state.sh structure (the two edit anchors)

`scripts/state.sh` is a SOURCED library (NO driver). Its layout:

- **Runtime keys block** (lines 40-52): `readonly STATE_<NAME>="@livepicker-<name>"`
  one per line, each ending with a `# ... Cleared via _STATE_RUNTIME_KEYS` comment.
  LAST line of the block is `STATE_RENDER_CACHE` (line 52). They are CONTIGUOUS
  (no blank lines between them).
- blank line (53).
- **Saved-state CONTRACT keys** (lines 54-63): `readonly ORIG_<NAME>=...`, headed
  by `# --- saved-state CONTRACT keys (PRD §9; written by activate, read by restore) ---`.
- blank line (67).
- **`_STATE_RUNTIME_KEYS`** (line 68): the space-list `clear_all_state` iterates.

The 4 new keys are RUNTIME keys (not ORIG_* saved-state). They belong in the
runtime block (contiguous with STATE_RENDER_CACHE) and MUST be appended to
`_STATE_RUNTIME_KEYS` (else they leak past teardown — gap_analysis §Gap (c)).

`set -u` is on; every `readonly` is assigned at definition (no unbound vars).
File has a file-wide `# shellcheck disable=SC2034` (each STATE_*/ORIG_* is an
integration seam referenced by external scripts — the new keys inherit this).

## FINDING 2 — the 4 new keys + their exact @livepicker-* names

Per the work-item contract + PRD §9 runtime-state list:

```bash
readonly STATE_CAND_WIN_SESSION="@livepicker-cand-win-session"  # cache-invalidation key: the candidate the cached window-list belongs to
readonly STATE_CAND_WIN_LIST="@livepicker-cand-win-list"        # newline-joined ordered window ids of that candidate
readonly STATE_CAND_WIN_CURSOR="@livepicker-cand-win-cursor"    # index into the list; defaults to the candidate's active window on entry
readonly STATE_PREVIEW_WIN_ID="@livepicker-preview-win-id"      # the window currently shown; overlaps STATE_LINKED_ID for non-self
```

These match PRD §9 verbatim: *"the new window-cursor keys
`@livepicker-cand-win-session` (the candidate the cached list belongs to),
`@livepicker-cand-win-list` (that candidate's ordered window ids),
`@livepicker-cand-win-cursor` (index into it; defaults to the candidate's active
window on entry), and `@livepicker-preview-win-id` (the window currently shown)."*

## FINDING 3 — STATE_PREVIEW_WIN_ID vs STATE_LINKED_ID (keep BOTH)

PRD §9 + work-item §1: STATE_LINKED_ID (`@livepicker-linked-id`) tracks the
linked window HANDLE (written by preview.sh::preview_main line 187/230-ish via
`set_state "$STATE_LINKED_ID" "$src_id"`; read on unlink + restore). It is the
tmux `link-window`/`unlink-window` handle. For the SELF-session, preview.sh does
NOT link (the window is native to the driver) so linked-id stays EMPTY (line 190:
`set_state "$STATE_LINKED_ID" ""` at activate; preview self-path never sets it).

STATE_PREVIEW_WIN_ID is the LOGICAL "window currently shown" — it overlaps
linked-id for NON-self candidates (same window) but DIVERGES for the self-session
(linked-id empty, preview-win-id = the self window id). **Keep BOTH.** This task
only DEFINES + INITS preview-win-id to ''; the overlap/divergence logic is
P2.M1.T2 (preview shows chosen window) + P2.M1.T3 (flip actions). preview.sh is
NOT edited in this task.

## FINDING 4 — _STATE_RUNTIME_KEYS append (the teardown contract)

Current line 68 (verbatim, the trailing `$STATE_RENDER_CACHE"` is the anchor):
```
readonly _STATE_RUNTIME_KEYS="$STATE_MODE $STATE_LIST $STATE_FILTER $STATE_INDEX $STATE_LINKED_ID $STATE_TAB_CURRENT_TMPL $STATE_TAB_INACTIVE_TMPL $STATE_PREVIEW_SEQ $STATE_PREVIEW_TARGET $STATE_SCROLL $STATE_CLIENT_WIDTH $STATE_RENDER_CACHE"
```
Append the 4 new keys (single space separators, mirroring the existing entries
which reference the readonly NAME not the @-string):
```
... $STATE_RENDER_CACHE $STATE_CAND_WIN_SESSION $STATE_CAND_WIN_LIST $STATE_CAND_WIN_CURSOR $STATE_PREVIEW_WIN_ID"
```
`clear_all_state` (line 153: `for k in $_STATE_RUNTIME_KEYS; do tmux set-option -gu
"$k" ...; done`) then tears them down. This is the gap_analysis §Gap (c) fix —
without the append, the keys leak past teardown.

## FINDING 5 — livepicker.sh activate init site (T2 block, NOT T4)

`scripts/livepicker.sh::activate_main` T2 block (lines 198-239) builds the list
and initializes selection. The 3 sibling state writes are at the END of T2:

```
237:	set_state "$STATE_LIST" "$list"
238:	set_state "$STATE_FILTER" ""
239:	set_state "$STATE_INDEX" "$idx"
240:	# --- T2b (P1.M3.T1.S1): client-width cache + client-resized hook ...
```

The 4 new inits go AFTER line 239 (`set_state "$STATE_INDEX" "$idx"`) and BEFORE
line 240 (the T2b comment). This is the natural "initial selection" group.

**Use ORIG_SESSION (NOT the `current` var) for the session name.** `current` is
set at line 208 `current="$(get_state "$ORIG_SESSION" "")"` (session mode) but is
REASSIGNED at line 219 to `"$(lp_client_format '#{session_name}:#{window_index}')"`
in WINDOW mode (a `session:window_index` token). ORIG_SESSION is the stable
client-independent session name saved at STEP 2 (line 173). So:
`set_state "$STATE_CAND_WIN_SESSION" "$(get_state "$ORIG_SESSION" "")"`.

The 4 inits:
```bash
	set_state "$STATE_CAND_WIN_SESSION" "$(get_state "$ORIG_SESSION" "")"
	set_state "$STATE_CAND_WIN_LIST" ""
	set_state "$STATE_CAND_WIN_CURSOR" "0"
	set_state "$STATE_PREVIEW_WIN_ID" ""
```
- SESSION = current session (matches the initial highlight at `$idx`, which points
  at the current session) — keeps the cache-invalidation key in sync with the
  highlight on entry.
- LIST = '' (derived lazily on first flip — P2.M1.T3).
- CURSOR = '0' (the sentinel/initial index = candidate's active window on entry,
  per PRD §9 "defaults to the candidate's active window on entry").
- PREVIEW_WIN_ID = '' (no window shown yet at this point in activate; the first
  preview is T5, AFTER T4 — P2.M1.T2 will set the real value).

This is a NO-BEHAVIOR-CHANGE init: the keys are read only by P2.M1.T3's
next-window/prev-window actions (currently inert — input-handler `*)` no-op) and
P2.M1.T2's preview. Nothing reads them today; they sit idle + get cleared on exit.

## FINDING 6 — no conflict with the parallel P1.M2.T1.S1 task

P1.M2.T1.S1 (in parallel) reworks the **T4 key-binding block** (livepicker.sh
lines ~336-446: axis resolution, copy block, nav loops, stale comments). This
task (P2.M1.T1.S1) edits:
- `scripts/state.sh` (NOT touched by P1.M2.T1.S1 at all).
- `scripts/livepicker.sh` **T2 block** (lines 237-239) — DISJOINT from T4 (336+).

The anchor `set_state "$STATE_INDEX" "$idx"` + the T2b comment is STABLE and
untouched by the T4 rework. No overlap. (P1.M2.T1.S1's edits begin at the T4
"Discovery OMITTED" comment ~line 355.)

## FINDING 7 — no existing test asserts the state-key set (no regression)

Grep over `tests/` for `cand-win`/`preview-win-id`/`_STATE_RUNTIME_KEYS`/
`STATE_RENDER_CACHE`/`STATE_CLIENT_WIDTH`: ZERO matches. No test counts the
runtime keys or asserts the exact `_STATE_RUNTIME_KEYS` list. The relevant tests:
- `tests/test_restore.sh` — asserts `clear_all_state` PRESERVES §11 config
  (CORRECTION A) and clears `@livepicker-orig-*`. Adding 4 runtime keys to the
  list does not affect the config-preservation invariant (the new keys are
  runtime, not config).
- `tests/test_preview.sh` — seeds `@livepicker-orig-session`/`-window` directly;
  reads `STATE_LINKED_ID`. It does NOT reference the new keys.

So the 4 new keys + their teardown cannot break any existing test. The new keys
are written (via set_state) and cleared (via clear_all_state) like every other
runtime key.

## FINDING 8 — set_state / get_state contract (the accessors)

`set_state "$1" "$2"` (state.sh line 71) → `tmux_set_opt` (utils.sh) →
`tmux set-option -g "$1" "$2"`. `get_state "$1" "${2:-}"` (line 76) → `tmux_get_opt`
→ `tmux show-option -gqv "$1"` with the default returned when unset/empty.

- `set_state "$STATE_CAND_WIN_LIST" ""` is a SET-EMPTY (`tmux set-option -g @x ""`),
  NOT unset; `get_state "$STATE_CAND_WIN_LIST" ""` reads back "". This mirrors the
  existing `set_state "$STATE_FILTER" ""` / `set_state "$STATE_LINKED_ID" ""` at
  activate (lines 190, 238). Do NOT use tmux_unset_opt/-gu for init.
- The new keys use `get_state "$STATE_<X>" "<default>"` everywhere downstream; the
  '' / '0' inits are the canonical defaults consumers will read when nothing else
  has written them. (Defensive: even if a consumer runs before activate sets them,
  get_state's default arg covers it — but activate sets them, so this is belt-and-braces.)

## FINDING 9 — PRD §9 restore step 6 already names these keys for teardown

PRD §9 restore step 6: *"Clear every `@livepicker-*` option (this MUST include the
runtime keys ... and the window-cursor keys `@livepicker-cand-win-session`/`-list`/
`-cursor`/`@livepicker-preview-win-id` — add them to `_STATE_RUNTIME_KEYS` in
`state.sh`)"*. This task is exactly that PRD directive + the activate init. The
restore.sh code itself is UNCHANGED (it calls `clear_all_state`, which iterates
`_STATE_RUNTIME_KEYS` — so appending the 4 keys auto-wires teardown).

## FINDING 10 — validation approach (no new test file this task)

This task creates NO new test (the window-flip integration suite is P2.M3.T1.S1
test_window_flip.sh). Validation:
- L1: `bash -n`/`shellcheck` on state.sh + livepicker.sh; grep the 4 constants +
  the 4 _STATE_RUNTIME_KEYS entries + the 4 activate inits exist exactly once.
- L2: `tests/run.sh` stays GREEN (no regression — FINDING 7).
- L3: isolated-socket activate → assert the 4 keys are SET to their init values
  (session/current-session-name, list/'', cursor/'0', preview-win-id/''), and that
  a cancel restores them all to unset (clear_all_state teardown). This proves both
  the init AND the teardown wiring in one cycle.
