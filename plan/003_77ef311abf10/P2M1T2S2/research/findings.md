# Research Findings — P2.M1.T2.S2 (delete: guards + unlink-first + kill-session + re-sync)

Empirical probes run on the installed **tmux 3.6b** via isolated `-L` sockets (the
project's established method, `tests/setup_socket.sh`). Every fact below was
observed live unless marked "PRD-documented". The probes:
`/tmp/lp_del_probe.sh` (orphan-leak + unlink-first fix + guards) and
`/tmp/lp_del_probe2.sh` (ownership check + confirm-before + window mode + re-sync
safety). The numbered findings are aligned so **Finding 3 == the orphan-leak note**
the work-item contract cites ("empirical_findings.md Finding 3 (CONFIRMED)").

---

## FINDING 1 — the delete key is already bound; the dispatch is a seam P2.M1.T2.S1 left

- `scripts/options.sh` (COMPLETE, P2.M1.T1.S1) defines `opt_delete_key()` →
  `M-BSpace` and `opt_confirm_delete()` → `off` (defaults PRD §11 verbatim).
- `scripts/livepicker.sh` activate T4 step 5 (COMPLETE, P2.M1.T1.S1) binds:
  `tmux bind-key -T livepicker "$(opt_delete_key)" run-shell "$CURRENT_DIR/input-handler.sh delete"`
  → verified by `tmux list-keys -T livepicker M-BSpace`.
- `scripts/session-mgmt.sh` (CREATED by P2.M1.T2.S1, the parallel sibling) hosts
  `_lp_resolve_highlighted` + `session_mgmt_rename` + `session_mgmt_do_rename` +
  a `session_mgmt_main` driver, with a **seam comment** where `delete)` /
  `do-delete)` branches must be added (verbatim from P2.M1.T2.S1's PRP Task 1):
  ```
  # --- P2.M1.T2.S2 seam: delete / do-delete (guards + unlink-first +
  #     kill-session + re-sync). Add `delete)` + `do-delete)` branches here. ---
  ```
- `scripts/input-handler.sh` likewise has a seam comment (P2.M1.T2.S1 Task 2)
  sitting between the `rename)` branch and `refresh-width)`:
  ```
  		# --- P2.M1.T2.S2 seam: `delete)` -> "$CURRENT_DIR/session-mgmt.sh" delete. ---
  ```
- THIS task replaces BOTH seam comments with the real branches. No new file.
  No conflict with P2.M1.T2.S1 (disjoint seams; it owns rename, this owns delete).

---

## FINDING 2 — guards (PRD §21 §3.43): refuse with a message + NO kill

Two hard refusals, both confirmed live:

- **`S == ORIG_SESSION`** (the driver the client lives in). Killing it would
  destroy the picker host and detach the client. `ORIG_SESSION` is the saved
  driver name (state.sh; client-independent). Compare the resolved highlight `S`
  against it; equal → `display-message` + `return` (no kill).
- **`STATE_LIST` has length 1.** tmux requires ≥1 session. **CONFIRMED
  catastrophic**: `kill-session` on the LAST remaining session returns **rc=0**
  and the **entire server shuts down** (`sessions after kill last:` → empty; the
  `-L` socket is gone). So this guard is non-negotiable. Measure length on the
  RAW `STATE_LIST` (newline-joined), NOT the filtered view — the PRD says
  "@livepicker-list has length 1" (the full list). After the guard passes the raw
  list has ≥2 entries, so post-delete it has ≥1 (server survives).

Guards run in `session_mgmt_delete` (the `delete)` action) BEFORE confirm-before,
so a refused target never even prompts. For the `confirm-delete on` path there is
a time gap between the guard and `do-delete`; do-delete **re-checks the
catastrophic length-≤1 guard** defensively (cheap; prevents a raced server death).
`S == ORIG_SESSION` is stable across the gap (neither name mutates mid-picker).

---

## FINDING 3 — kill-session does NOT remove a linked preview window; unlink FIRST  (the load-bearing note)

**CONFIRMED** (the contract's "empirical_findings.md Finding 3"). Probe sequence
on an isolated socket (driver + alpha, alpha has 1 window `awin0` id `@2`):

```
link alpha's @2 into driver            -> driver windows: @0,@1,@2
kill-session alpha  (NO prior unlink)  -> driver windows: @0,@1,@2   <-- @2 SURVIVES
```

The window `@2` linked into the driver as the preview **SURVIVES** `kill-session`
of its source (it is still linked into the driver) → a **permanent orphan**. This
matches PRD §16 ("kill-session + linked preview leak") and §21 §3.43 step 4.

**The fix is CONFIRMED** — `unlink-window` the linked preview from the driver
FIRST (when it belongs to the victim), WITHOUT `-k`, THEN kill-session:

```
link gamma's @4 into driver            -> driver windows: ...,@4
unlink-window -t driver:@4  (no -k)    -> driver windows: ...(no @4); gamma STILL has @4
kill-session gamma                      -> driver windows: ...(no @4)   <-- CLEAN, no orphan
```

`unlink-window` without `-k` removes ONE link (the driver's); the source session
keeps its window (preview.sh FINDING 1). Then `kill-session` destroys the window
in its now-only (source) session. No orphan. This is the EXACT pattern
`restore.sh` STEP-1 uses (lines 75-92) and `input-handler.sh::_confirm_land_on_session`
uses (the H2-hardened driver unlink) — do-delete mirrors it.

**WHEN to unlink-first**: only when `STATE_LINKED_ID` is set AND the linked window
**belongs to the victim S**. See Finding 4 for the ownership test. If the preview
is showing a *different* session's window (deferred job lagged), the linked window
does NOT belong to S → do NOT unlink it (it is not an orphan — its source is
alive; the post-delete re-sync will swap it out). If `STATE_LINKED_ID` is empty
(self-session was previewed, or preview never ran / mode off) → nothing to unlink.

**After unlink+kill, CLEAR `STATE_LINKED_ID`** (the window is dead). The re-sync
(Finding 6) then re-links the new highlight cleanly. (Leaving it stale is also
safe — `unlink-window` on the dead id returns rc=1 swallowed by `|| true`, see
Finding 6 — but clearing is cleaner and matches "the unlink+kill cleared the old
preview".)

---

## FINDING 4 — "belongs to S": list the victim's windows and grep for the linked id

Probe (driver + alpha + beta; alpha's `@1` linked into driver as preview):

```
linked_id=@1
list-windows -t '=alpha' -F '#{window_id}'   -> @1     ; grep -Fxq @1 -> YES (alpha owns it)
list-windows -t '=beta'  -F '#{window_id}'   -> @2     ; grep -Fxq @1 -> NO  (beta does not)
```

So the ownership test is:

```bash
tmux list-windows -t "=$S" -F '#{window_id}' 2>/dev/null | grep -Fxq "$linked_id"
```

- `grep -Fxq` = fixed-string, whole-line, quiet → matches the exact `@N` id once.
- Robust against the victim's active window having changed since preview time: a
  window linked into the driver from S is still listed under S even if S's *active*
  window moved. So this is more robust than comparing `linked_id` to S's active id.
- `2>/dev/null || false` guards a victim that already vanished (race) — treat as
  "does not belong" → skip the unlink (the re-sync handles it).

Window mode does NOT need this check: `kill-window` destroys the window OBJECT in
ALL sessions it is linked into, so the driver link dies with it (no orphan). See
Finding 8.

---

## FINDING 5 — confirm-before primitive (PRD §13 / §21 §3.43 step 3)

`confirm-before` is a **client command** (like `command-prompt`): it errored
`no current client` on the detached probe, and its `-p` form was otherwise
accepted (no "unknown command"). It needs the attached client the picker always
has (the user pressed M-BSpace). On `y` it runs the command; on `n`/Escape it
runs nothing.

The PRD §21 form (this task interpolates the already-resolved `S`, NOT `%%` —
unlike rename, at delete time we already KNOW the target):

```
tmux confirm-before -p "Kill session $S? (y/n)" "run-shell '$CURRENT_DIR/session-mgmt.sh do-delete $S'"
```

- `$S` is substituted at command-construction time (double-quoted outer string →
  `$CURRENT_DIR` and `$S` expand; the inner `run-shell '...'` is single-quoted so
  tmux receives it literally, then run-shell word-splits on fire).
- The confirm path therefore passes `S` as **argv[2] to do-delete** (`do-delete
  $S`). The no-confirm path calls do-delete directly with the same arg. do-delete
  reads `S="${2:-}"`.
- **Space limitation** (rides to P4, same as rename's `%%`): a session name with a
  space (`my sess`) → run-shell word-splits → `do-delete my sess` → argv[2]=`my`
  only. The session id is NOT used here (the confirm path is invoked from
  `session_mgmt_delete`, which only has the name `S`); this is consistent with the
  rename limitation and acceptable (session names rarely contain spaces; tmux
  rejects `:`). Documented.
- `confirm-before` captures input while open (livepicker table suspended); tmux
  restores the table on y/n/Escape → no extra binding work (same as rename's
  command-prompt). The picker STAYS OPEN (mode stays `on`).

---

## FINDING 6 — do-delete is its OWN process → re-sync via preview.sh directly (§P5)

`session-mgmt.sh` runs under `run-shell` (from `input-handler.sh delete`, or
standalone from `confirm-before`'s run-shell). It is a separate process and
sources options/utils/state/rank — it does NOT source input-handler.sh, so the
helpers `_lp_preview_follow` / `_lp_fire_preview` / `_lp_sync_preview_to_top_match`
are NOT available. The contract explicitly allows "re-sync the preview ...
via _lp_preview_follow (or invoke preview.sh)". **do-delete invokes `preview.sh`
directly** (`"$CURRENT_DIR/preview.sh" "$new_target"` — the single-arg form skips
the seq supersede guard; it is the synchronous link path).

- §P5 ("all preview work routes through _lp_preview_follow") is honored in spirit:
  do-delete replicates the defer ordering (refresh-client -S FIRST when
  `@livepicker-preview-defer on` = latency-priority status; preview-then-refresh
  when `off` = legacy order). The async `-b` supersedeable launcher is NOT
  replicated — delete is a rare, user-initiated action (not the per-keystroke hot
  path the §18 defer optimization targets), so one synchronous `preview.sh` link is
  acceptable latency. `opt_preview_defer` is available via options.sh.
- **Re-sync safety (CONFIRMED)**: after unlink-first + kill-session the old
  `STATE_LINKED_ID` window is GONE. Probe: `unlink-window -t "driver:@1"` on an
  orphan whose source was already killed → **rc=0, removed**. So even a stale
  `linked_id` is harmlessly unlink-attempted by `preview.sh` (rc=0 or rc=1, both
  swallowed by `|| true`). do-delete CLEARS `STATE_LINKED_ID` first (cleaner) so
  `preview.sh`'s unlink step is skipped entirely; `preview.sh` then links the new
  highlight and records the new id. Either way, no leak.
- Empty new highlight (no item matches the filter after the drop — only possible
  when filter is non-empty, since the length-1 guard guarantees ≥1 raw entry) →
  do NOT call `preview.sh` (its empty-target path is messy); just
  `refresh-client -S` (renderer shows no-match state; the old preview is already
  gone). Mirror `_lp_preview_follow`'s "Empty TARGET -> skip the preview".

---

## FINDING 7 — index clamp lands on a neighbour (drop S, re-rank, clamp)

`STATE_INDEX` indexes into the RANKED list (`filtered = lp_rank(STATE_LIST,
STATE_FILTER)`); the renderer highlights `filtered[STATE_INDEX]`. At delete time
`filtered[STATE_INDEX] == S` (S is the highlight). After dropping S from the raw
list and re-ranking, the new filtered list is the old one MINUS S, same order:

```
old filtered = [a, b, S, c, d]   index=2 -> S
new filtered = [a, b,    c, d]   keep index=2 -> c (the NEXT neighbour)   ✓
old filtered = [a, b, c, S]      index=3 -> S (last)
new filtered = [a, b, c]         clamp min(3, 3-1)=2 -> c (the PREV neighbour) ✓
```

So the recipe is: drop S from STATE_LIST → re-rank → `new_L = len(filtered)` →
clamp `STATE_INDEX` to `min(cur_index, new_L-1)` → new highlight =
`filtered[clamped]` (or `""` if `new_L == 0`). **No need to find S's position and
decrement** — dropping S and clamping naturally lands on a neighbour. Clamp
against the FILTERED length (index is into filtered; if the filter is empty,
filtered length == raw length, same thing).

---

## FINDING 8 — window mode: kill-window destroys the shared window (no orphan); rebuild the list

Window mode (`@livepicker-type window`) target is a `session:window_index` token
(built by `livepicker.sh:192`: `tmux list-windows -a -F '#{session_name}:#{window_index}'`).

- **kill-window destroys the window OBJECT in every session it is linked into**
  (unlike `kill-session`, which leaves linked-into-other-sessions windows alive).
  So killing the highlighted/previewed window removes the driver's link too —
  **NO orphan leak, NO unlink-first needed** in window mode. (Same family of
  object as rename-window's "index unchanged", but here the window is destroyed.)
- **Guard**: refuse to kill the driver's ONLY window (killing it would empty the
  driver session and detach the client). The token's session part == ORIG_SESSION
  AND `list-windows -t "=$ORIG_SESSION"` has exactly 1 window → `display-message`
  + return. (Killing a NON-driver session's only window simply destroys that
  session — acceptable, that is what kill-window does.) Confirmed live:
  `kill-window -t 'drv:1'` (2-window driver) → rc=0, drv retains w0.
- **STATE_LIST rewrite MUST REBUILD, not drop-a-line**: `renumber-windows` is ON
  (activate saves/restores it), so killing window `i` shifts every later window in
  that session down by one → the surviving `session:window_index` tokens are now
  WRONG. The correct rewrite is to re-derive the list exactly as activate does:
  `tmux list-windows -a -F '#{session_name}:#{window_index}'`. (Session mode drops
  one line because sessions do not renumber — sessions are by name.) Clear
  `STATE_LINKED_ID` (the window is dead) before the re-sync.
- No `confirm-before` sanitization concern (window names are not sanitized; this
  is kill not rename). The PRD §21.44 "same shape" = resolve token, guard, kill,
  rebuild, clamp, re-sync.

---

## FINDING 9 — STATE_LIST format + the two rewrite shapes + clear LINKED_ID

- `STATE_LIST` is newline-joined with embedded `\n`, NO trailing `\n` (activate
  captures via `$(tmux list-sessions …)` which `$()` strips the trailing newline;
  `set_state` preserves embedded newlines). Read via `get_state "$STATE_LIST" ""`.
- **Session-mode rewrite (drop S)**: mirror the rename in-place edit
  (`mapfile -t lines < <(printf '%s' "$list")`, blank the line equal to `S`,
  rebuild with a join loop emitting NO trailing newline). Session names are unique
  → exactly one match. Whole-line compare handles spaces.
- **Window-mode rewrite (rebuild)**: `new_list="$(tmux list-windows -a -F
  '#{session_name}:#{window_index}' 2>/dev/null)"` (verbatim activate form); the
  killed window is simply absent. `set_state "$STATE_LIST" "$new_list"`.
- **Clear `STATE_LINKED_ID`** after the kill (both modes) via
  `tmux_unset_opt "$STATE_LINKED_ID"` (the `-gu` true-unset; matches preview.sh's
  self-session path) — so the re-sync's `preview.sh` starts with no prior link.
- `set -u` honored: every `get_state` takes a default arg; `S="${2:-}"`. No new
  `STATE_*`/`ORIG_*` keys are added (delete reuses the existing `STATE_LIST` /
  `STATE_INDEX` / `STATE_FILTER` / `STATE_LINKED_ID` / `ORIG_SESSION`).

---

## FINDING 10 — conventions: set -u (NOT -e), $CURRENT_DIR, no scroll work, no layout.sh

- `session-mgmt.sh` uses `set -u` and NOT `set -e` (mirrors input-handler.sh /
  restore.sh / the rename half). `kill-session`/`kill-window`/`unlink-window`/
  `display-message` legitimately return non-zero (vanished target, singly-linked
  unlink); check rc explicitly with `if ! …` or swallow with `|| true` — never let
  a non-zero rc abort the script and strand the picker. Sources
  options/utils/state/rank (NOT layout — delete does no viewport/scroll work; the
  §19 renderer recomputes the viewport every redraw and keeps the highlight
  visible regardless of `STATE_SCROLL`, so delete does not touch scroll, §P7).
- Use `$CURRENT_DIR` (house variable, == scripts/, already defined by the
  P2.M1.T2.S1 header). NEVER `$SCRIPT_DIR` (undefined under `set -u` → crash; the
  PRD §21 template says `$SCRIPT_DIR` but the codebase convention — and the rename
  sibling — uses `$CURRENT_DIR`; the two are the same directory).
- `session_mgmt_delete` takes argv[1] only (`delete`); it MUST NOT reference `$2`
  (the M-BSpace binding passes no char — mirror rename/confirm/cancel). do-delete
  reads `S="${2:-}"`. Both branches `return 0` (picker stays open).
- NO docs edit (the README note already landed in P2.M1.T1.S1; full prose is
  P4.T1). NO new test file (`test_session_mgmt.sh` is P2.M2.T1.S1).
