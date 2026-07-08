# PRP — P2.M1.T2.S2: Implement delete (guards + unlink-first + kill-session + re-sync) + input dispatch

---

## Goal

**Feature Goal**: Implement the **delete** management action for PRD §21.43:
pressing `M-BSpace` (bound by P2.M1.T1.S1) kills the highlighted session/window
**without leaking an orphaned preview window into the driver**, refuses the
driver session / driver's-only-window / last-session with a `display-message`
(no kill), optionally prompts `y/n` via `confirm-before` (`opt_confirm_delete`),
then drops the victim from `@livepicker-list`, clamps the highlight onto a
neighbour, re-ranks, and re-syncs the live preview to the new highlight — all
while the picker **stays open** (no restore). Adds the `delete)` / `do-delete)`
logic to the **`session-mgmt.sh`** that P2.M1.T2.S1 created (rename host), and
lights up the `delete)` dispatch in **`scripts/input-handler.sh`** (the seam
comment P2.M1.T2.S1 left).

**Deliverable** (2 file edits; NO new file):
1. **EDIT** `scripts/session-mgmt.sh` (created by P2.M1.T2.S1) — ADD
   `session_mgmt_delete` (resolve → guards → optional confirm-before → do-delete)
   + `session_mgmt_do_delete` (unlink-first → kill → rewrite list → clamp →
   re-rank → re-sync preview → refresh) functions, and add `delete)` /
   `do-delete)` branches to `session_mgmt_main` (replacing P2.M1.T2.S1's seam
   comment).
2. **EDIT** `scripts/input-handler.sh` — replace P2.M1.T2.S1's `delete)` seam
   comment (between the `rename)` branch and `refresh-width)`) with the real
   `delete)` dispatch branch (thin delegate to `session-mgmt.sh delete`).

**Success Definition**:
- `bash -n` / `shellcheck` clean on both files (existing file-level disables cover
  the new lines); `session-mgmt.sh` already `+x` (P2.M1.T2.S1).
- On an isolated socket + attached client, with the picker active:
  - `M-BSpace` kills the highlighted session; it disappears from the list; a
    neighbour is highlighted + previewed; the picker stays open; **no orphan
    window leaks into the driver** (verified: driver window count returns to its
    pre-preview baseline after the delete + re-sync).
  - Deleting the currently-previewed session **unlinks the preview from the driver
    FIRST**, so `kill-session` does not strand a permanent orphan (PRD §16 / §21.4).
  - The **driver session** (`ORIG_SESSION`) is refused: `display-message`, no kill,
    picker unchanged.
  - The **last session** (raw `@livepicker-list` length 1) is refused:
    `display-message`, no kill (killing it would shut the tmux server down).
  - `@livepicker-confirm-delete on` → `confirm-before -p "Kill session $S? (y/n)"`;
    `y` fires `do-delete $S` (a standalone run-shell); `n`/Escape cancels (no kill).
  - Window mode: `kill-window` on the highlighted window; the driver's-only-window
    is refused; the list is **rebuilt** (renumber shifts indices); re-sync works.
- `tests/run.sh` stays GREEN (delete is reachable only via `M-BSpace`, which no
  existing test presses; the full delete suite is P2.M2.T1.S1).

## User Persona (if applicable)

**Target User**: tmux users migrating from sessionx (the `M-BSpace` default mirrors
`@sessionx-bind-kill-session`), who want to prune sessions/windows without leaving
the picker and without corrupting the driver session.

**Use Case**: Activate the picker → navigate to a session you no longer want →
press `M-BSpace` (or `y` at the optional confirm) → the session is gone, the next
session is highlighted + previewed, the picker stays open for further browsing.

**User Journey**: Activate (P2.M1.T1.S1 bound `M-BSpace` → `input-handler.sh
delete`) → `input-handler.sh` delegates to `session-mgmt.sh delete` →
`session_mgmt_delete` resolves S, checks guards (driver/last-session), (optional)
`confirm-before` or calls `do-delete` → `session_mgmt_do_delete` unlinks the
preview (if it is S's), `kill-session`, drops S from the list, clamps the index
onto a neighbour, re-ranks, re-syncs the preview via `preview.sh`,
`refresh-client -S` → the list shrinks, a neighbour is highlighted + previewed,
picker open.

**Pain Points Addressed**: session-CRUD parity with sessionx; the subtle
**orphan-preview leak** (a window linked into the driver SURVIVES `kill-session`
of its source — PRD §16) is prevented by unlink-first; the picker host (driver
session) and the last session are protected from a footgun that would detach the
client / kill the server.

## Why

- **PRD §21.43 (Delete)** specifies the exact guards (driver / last-session), the
  optional `confirm-before`, the **unlink-first** rule, the list rewrite +
  index-clamp + re-sync, and `refresh-client -S`.
- **PRD §16 ("kill-session + linked preview leak")** is the load-bearing risk this
  task exists to neutralize: a window linked into the driver as the preview
  SURVIVES `kill-session` of its source. `do-delete` MUST `unlink-window` it from
  the driver FIRST (when `STATE_LINKED_ID` belongs to the victim), else it leaks.
- **PRD §13** lists `unlink-window -t <session>:<id>` (no `-k`), `kill-session -t
  "=S"`, `confirm-before -p "<prompt>" "<cmd>"`, `refresh-client -S`.
- **Decoupling**: P2.M1.T1.S1 bound the (inert) `M-BSpace` key + added
  `opt_confirm_delete`; P2.M1.T2.S1 created `session-mgmt.sh` (rename host) +
  left the `delete)`/`do-delete)` seams. THIS task fills those seams — no new
  file, no conflict with the rename sibling (disjoint code regions).
- `do-delete` is its own process (run via `run-shell`, standalone from
  `confirm-before`), so it is self-contained: it cannot call `input-handler.sh`'s
  `_lp_preview_follow` and invokes `preview.sh` directly for the re-sync (the
  contract explicitly allows "via _lp_preview_follow / preview.sh").

## What

1. **scripts/session-mgmt.sh** (EDIT — P2.M1.T2.S1 created it) — ADD two functions
   after `session_mgmt_do_rename` and before `session_mgmt_main`, and add two
   dispatch branches (replacing the seam comment):
   - `session_mgmt_delete` — resolve the highlighted target (reuse the sibling's
     `_lp_resolve_highlighted`); no-op if empty; **guards** (session mode:
     `S==ORIG_SESSION` → display-message + return; raw list length ≤1 →
     display-message + return; window mode: driver's-only-window → display-message
     + return); if `opt_confirm_delete on` → `confirm-before -p … "run-shell
     '…/session-mgmt.sh do-delete $S'"` + return; else call `do-delete` directly.
     Takes argv[1] only (MUST NOT reference `$2`).
   - `session_mgmt_do_delete` — `S="${2:-}"`; branch on `opt_type`:
     - **session**: defensive length-≤1 re-check; if `STATE_LINKED_ID` is set AND
       belongs to S (`list-windows -t "=S" | grep -Fxq`), `unlink-window -t
       "$ORIG_SESSION:$linked_id"` (no `-k`) **first**; `kill-session -t "=S"`;
       drop S from `STATE_LIST` (in-place line edit, like rename).
     - **window**: driver's-only-window re-check; `kill-window -t "$S"` (destroys
       the window in all sessions — no orphan, no unlink-first); **rebuild**
       `STATE_LIST` via `list-windows -a -F '#{session_name}:#{window_index}'`
       (renumber shifts indices).
     - **shared tail**: re-rank (`lp_rank`); clamp `STATE_INDEX` to
       `min(idx, new_filtered_len-1)`; re-sync preview via `preview.sh "$target"`
       (empty target → just refresh; honor `opt_preview_defer` ordering);
       `refresh-client -S`.
2. **scripts/input-handler.sh** (EDIT) — replace P2.M1.T2.S1's `delete)` seam
   comment with the real `delete)` branch: thin delegate
   `"$CURRENT_DIR/session-mgmt.sh" delete; return 0` (mirror of the `rename)`
   branch; MUST NOT reference `$2`).

### Success Criteria

- [ ] `session-mgmt.sh` has `session_mgmt_delete` + `session_mgmt_do_delete`;
      `session_mgmt_main` dispatches `delete)` / `do-delete)` (no seam comment
      remains); `bash -n` + `shellcheck` clean.
- [ ] `input-handler.sh` has a `delete)` branch (2-tab label) delegating to
      `session-mgmt.sh delete`; the seam comment is gone.
- [ ] `M-BSpace` kills the highlighted session, removes it from the list,
      highlights + previews a neighbour, and leaves the picker open — with NO
      orphan window in the driver (driver window count returns to baseline).
- [ ] Deleting the currently-previewed session unlinks the preview FIRST (no leak).
- [ ] Driver session + last session are refused (`display-message`, no kill).
- [ ] `@livepicker-confirm-delete on` → `confirm-before`; `y` kills, `n`/Esc does not.
- [ ] Window mode: `kill-window`, driver's-only-window refused, list rebuilt, re-synced.
- [ ] `tests/run.sh` stays GREEN.

## All Needed Context

### Context Completeness Check

_Pass_: A developer who has never seen this repo can implement both edits from
(a) the verbatim function bodies + insertion anchors in the Implementation
Blueprint, (b) the 10 findings in `research/findings.md` — most critically
**FINDING 3** (the CONFIRMED orphan leak + the unlink-first fix), **FINDING 4**
(the "belongs to S" ownership test), **FINDING 2** (the two guards; killing the
last session kills the server), **FINDING 6** (do-delete is its own process →
re-sync via `preview.sh` directly; re-sync safely handles a stale/dead
`linked_id`), **FINDING 7** (the index-clamp-lands-on-a-neighbour math), and
**FINDING 8** (window mode: kill-window destroys the shared window → no orphan,
rebuild the list). The resolution helper and the `_lp_resolve_highlighted` /
`get_state`/`set_state` / `lp_rank` patterns are reproduced verbatim from the
existing `input-handler.sh` / `session-mgmt.sh` (rename half), so no novel logic.

### Documentation & References

```yaml
# MUST READ — the file you EDIT #1 (add delete/do-delete). P2.M1.T2.S1 created it.
- file: scripts/session-mgmt.sh
  why: hosts _lp_resolve_highlighted (REUSE it for target resolution — VERBATIM
       the confirm pattern), session_mgmt_rename/do_rename (the sibling shape to
       mirror: set -u, ${2:-}, get_state defaults, display-message + return 0,
       the in-place mapfile STATE_LIST rewrite), session_mgmt_main (ADD delete)/
       do-delete) branches; replace the `# --- P2.M1.T2.S2 seam ---` comment).
  pattern: |
    session_mgmt_do_rename() { local _new="${2:-}"; ...; case "$_new" in ... esac;
        ... in-place mapfile rewrite ...; set_state "$STATE_LIST" "$_new_list";
        tmux refresh-client -S 2>/dev/null || true; return 0; }
    session_mgmt_main() { case "$_action" in rename) ...; do-rename) ...;
        # --- P2.M1.T2.S2 seam: delete / do-delete ... ---   <- REPLACE THIS
        *) return 0 ;; esac; }
  gotcha: the file uses TAB indentation, set -u (NOT -e), sources
          options/utils/state/rank (NOT layout). Reuse _lp_resolve_highlighted;
          do NOT re-implement target resolution.

# MUST READ — the file you EDIT #2 (add the delete) dispatch branch).
- file: scripts/input-handler.sh
  why: the `case "$action"` dispatch. P2.M1.T2.S1 added the `rename)` branch +
       a `# --- P2.M1.T2.S2 seam: \`delete)\` ... ---` comment between `rename)`'s
       `;;` and `refresh-width)`. Replace THAT comment with the `delete)` branch
       (2-tab label / 3-tab body, mirroring `rename)` exactly). $CURRENT_DIR is
       the house variable (== scripts/; NOT $SCRIPT_DIR).
  pattern: |
  		rename)
  			"$CURRENT_DIR/session-mgmt.sh" rename
  			return 0
  			;;
  		# --- P2.M1.T2.S2 seam: `delete)` -> ... ---   <- REPLACE WITH delete) branch
  		refresh-width)
  gotcha: the `delete)` branch MUST NOT reference $2 (the M-BSpace binding passes
          no char; mirror rename/confirm/cancel). It is a one-line delegate.

# MUST READ — the unlink-first + restore pattern do-delete mirrors.
- file: scripts/restore.sh
  why: STEP-1 (lines ~75-92) is the canonical "unlink the driver's preview window"
       pattern: read linked_id + ORIG_SESSION, `unlink-window -t
       "$current_session:$linked_id" 2>/dev/null || true` (NO -k; singly-linked
       rc=1 swallowed). do-delete's session-mode unlink-first is the SAME call.
  pattern: 'tmux unlink-window -t "$orig_session:$linked_id" 2>/dev/null || true'

# MUST READ — the re-sync target (do-delete invokes it directly; its own process).
- file: scripts/preview.sh
  why: preview_main "$target" (single-arg form SKIPS the seq supersede guard ->
       synchronous link). It reads STATE_LINKED_ID and unlinks the prior preview
       BEFORE linking the new one (rc on a dead/stale id swallowed by `|| true`),
       so a stale linked_id after unlink-first+kill is harmlessly re-unlinked and
       overwritten. This is WHY do-delete does NOT need to clear STATE_LINKED_ID.
  pattern: '"$CURRENT_DIR/preview.sh" "$target" 2>/dev/null || true'

# MUST READ — the existing re-sync helpers do-delete CANNOT call (other process).
- file: scripts/input-handler.sh
  why: _lp_preview_follow / _lp_sync_preview_to_top_match / _lp_fire_preview are
       defined HERE (input-handler's process), NOT available in session-mgmt.sh.
       do-delete replicates only the ORDERING (defer=on -> refresh first; off ->
       preview first) and invokes preview.sh directly. §P5.
  gotcha: do NOT source input-handler.sh from session-mgmt.sh (it has a driver that
          exits). Invoke preview.sh as an executable.

# MUST READ — the state keys delete reads/writes (NO new keys).
- file: scripts/state.sh
  why: STATE_LIST (newline-joined, no trailing \n; rewrite), STATE_INDEX (clamp),
       STATE_FILTER (re-rank), STATE_LINKED_ID (ownership test + the unlink target),
       ORIG_SESSION (the driver; guard + unlink target). get_state takes a default
       arg for set -u safety. tmux_unset_opt (from utils.sh) = `-gu` true-unset.
  pattern: 'linked_id="$(get_state "$STATE_LINKED_ID" "")"; orig="$(get_state "$ORIG_SESSION" "")"'

# MUST READ — the ranker (re-rank the post-delete list the SAME way the renderer does).
- file: scripts/rank.sh
  why: lp_rank "$LIST" "$FILTER" prints matching names best-first; removing one
       input element removes that one output element WITHOUT reordering the rest
       (pure score sort) -> clamping STATE_INDEX lands on the right neighbour.
  pattern: 'mapfile -t filtered < <(lp_rank "$new_list" "$filter")'

# MUST READ — option accessors (already added by P2.M1.T1.S1).
- file: scripts/options.sh
  why: opt_type() (session|window branch), opt_confirm_delete() (off default),
       opt_preview_defer() (on default; ordering of the re-sync). All bake defaults.

# MUST READ — the ground-truth findings for THIS task (10 live-verified).
- docfile: plan/003_77ef311abf10/P2M1T2S2/research/findings.md
  why: FINDING 1 (the seams P2.M1.T1.S1/P2.M1.T2.S1 left); FINDING 2 (guards;
       killing the last session kills the server); FINDING 3 (the CONFIRMED orphan
       leak + the unlink-first fix); FINDING 4 (the "belongs to S" grep test);
       FINDING 5 (confirm-before interpolates $S; space limitation); FINDING 6
       (do-delete is its own process -> preview.sh directly; re-sync safety);
       FINDING 7 (clamp-lands-on-neighbour); FINDING 8 (window mode: kill-window
       destroys the shared window; rebuild the list); FINDING 9 (STATE_LIST shapes);
       FINDING 10 (set -u, $CURRENT_DIR, no layout.sh, no scroll).
  critical: Read BEFORE writing the functions. FINDING 3 is the load-bearing leak
            prevention; deviating reintroduces the permanent-orphan bug. FINDING 6
            prevents re-implementing _lp_fire_preview / wrongly clearing linked_id.

# MUST READ — the rename sibling contract (the file + helper this task extends).
- docfile: plan/003_77ef311abf10/P2M1T2S1/PRP.md
  why: defines the EXACT session-mgmt.sh that exists when this task starts
       (_lp_resolve_highlighted signature; session_mgmt_main seam comment text;
       the in-place mapfile STATE_LIST rewrite to copy for the session-mode drop;
       the input-handler.sh `delete)` seam comment text to replace). Treat as a
       contract — assume P2.M1.T2.S1 landed verbatim.

# MUST READ — the PRD sections selected for this work item.
- docfile: PRD.md
  why: §21.43 Delete (guards, unlink-first, rewrite/clamp/re-sync); §21.44 Window
       mode (kill-window, driver's-only-window refuse, rebuild); §21.45 Delete key
       caveat; §13 (unlink-window/kill-session/confirm-before/refresh-client
       primitives); §16 (the kill-session+linked-preview-leak note).
  section: "§21 Session management (Delete / Window mode)", "§13 tmux primitives",
           "§16 Implementation risks (kill-session + linked preview leak)"

# MUST READ — architecture patterns.
- docfile: plan/003_77ef311abf10/architecture/codebase_patterns.md
  why: §P1 (session-mgmt.sh is an executable entry point; set -u not -e); §P3 (no
       new STATE_*/ORIG_* keys); §P5 (preview routes through preview.sh; do-delete
       invokes it directly as its own process); §P9 (set -u safety + escaping).
  section: "§P1 Sourced library contract", "§P5 Preview entry point", "§P9 set -u safety"
```

### Current Codebase tree

```bash
tmux-livepicker/
  scripts/
    options.sh utils.sh state.sh rank.sh layout.sh     # sourced libs (options has opt_confirm_delete/opt_delete_key from P2.M1.T1.S1).
    input-handler.sh  # +x; EDIT (replace the delete) seam with the dispatch branch).
                        # has _lp_preview_follow / _lp_resolve... (NOT callable cross-process).
    livepicker.sh renderer.sh preview.sh restore.sh    # +x; entry points (COMPLETE; M-BSpace bound by P2.M1.T1.S1).
    session-mgmt.sh   # +x; CREATED by P2.M1.T2.S1 (rename host + _lp_resolve_highlighted
                        #   + a delete/do-delete SEAM). THIS TASK fills the seam.
  tests/
    setup_socket.sh helpers.sh run.sh                  # harness (COMPLETE; pins defer off).
    test_*.sh                                           # suites (COMPLETE; delete suite = P2.M2.T1.S1).
  README.md CHANGELOG.md plugin.tmux PRD.md
```

### Desired Codebase tree with files to be added and responsibility of file

```bash
tmux-livepicker/        # NO new file. Two existing files edited:
  scripts/
    session-mgmt.sh     # + session_mgmt_delete (guards + confirm-before + delegate)
                        #   + session_mgmt_do_delete (unlink-first + kill + rewrite +
                        #   clamp + re-rank + re-sync). + delete)/do-delete) in main.
    input-handler.sh    # + `delete)` dispatch branch (replaces the P2.M1.T2.S2 seam).
```

### Known Gotchas of our codebase & Library Quirks

```bash
# CRITICAL (FINDING 3): kill-session does NOT remove a window linked into the
# driver — it SURVIVES as a permanent orphan. do-delete MUST unlink-window the
# linked preview from the driver FIRST (when STATE_LINKED_ID belongs to S), WITHOUT
# -k, THEN kill-session. unlink-window without -k removes ONE link (the driver's);
# the source keeps it; the subsequent kill-session destroys it in its only session.

# CRITICAL (FINDING 2): killing the LAST session (raw STATE_LIST length 1) returns
# rc=0 and SHUTS THE SERVER DOWN. Guard on raw list length ≤1 (session mode) and
# the driver's-only-window (window mode). Re-check the length-≤1 guard inside
# do-delete (the confirm-delete path has a time gap; a raced external kill could
# make S the last session). S==ORIG_SESSION is stable (no re-check needed).

# CRITICAL (FINDING 4): "linked preview belongs to S" = the linked id is one of S's
# windows: `tmux list-windows -t "=$S" -F '#{window_id}' | grep -Fxq "$linked_id"`.
# Only unlink-first when this is TRUE. If the preview lagged to another session
# (defer), the linked window does NOT belong to S -> do NOT unlink (it is not an
# orphan; the re-sync swaps it out).

# CRITICAL (FINDING 6): session-mgmt.sh is its OWN process (run-shell). It CANNOT
# call input-handler.sh's _lp_preview_follow/_lp_fire_preview. do-delete re-syncs
# by invoking preview.sh DIRECTLY (single-arg -> synchronous; skips the seq guard).
# Do NOT clear STATE_LINKED_ID: preview.sh's re-link unlinks the prior (now dead)
# preview (rc swallowed) and overwrites linked_id, so it self-cleans. (Clearing it
# unconditionally would drop tracking of a lagged non-victim preview -> a leak.)

# CRITICAL (FINDING 8): window mode has NO orphan leak — kill-window destroys the
# window OBJECT in all sessions (the driver link dies with it) -> NO unlink-first.
# But renumber-windows is ON -> killing window i shifts later indices -> the list
# MUST be REBUILT via `list-windows -a -F '#{session_name}:#{window_index}'`
# (verbatim activate form), NOT drop-a-line. Session mode drops one line (sessions
# are by name; no renumber).

# CRITICAL: session-mgmt.sh uses `set -u` and MUST NOT use `set -e`. kill-session /
# kill-window / unlink-window / display-message legitimately return non-zero
# (vanished target, singly-linked unlink). Check rc with `if !` or swallow with
# `|| true` — NEVER let a non-zero rc abort and strand the picker.

# GOTCHA (FINDING 7): STATE_INDEX indexes the RANKED list. After dropping S and
# re-ranking, the new filtered list = old minus S (same order). Keeping STATE_INDEX
# (when < new filtered len) lands on the NEXT neighbour; clamp to new_len-1 lands
# on the PREV neighbour when S was last. Clamp against the FILTERED length.

# GOTCHA (FINDING 5): confirm-before interpolates the resolved $S (NOT %%). A
# session name with a SPACE breaks run-shell word-split (do-delete gets argv[2]=
# first word only). Same limitation as rename's %%; documented; rides to P4.

# GOTCHA: session_mgmt_delete takes argv[1] ONLY — MUST NOT reference $2 (the
# M-BSpace binding passes no char). do_delete reads S="${2:-}". Both `return 0`
# (picker stays open).

# GOTCHA: use $CURRENT_DIR (house var, == scripts/, already defined by the
# P2.M1.T2.S1 header). NEVER $SCRIPT_DIR (undefined under set -u -> crash).

# GOTCHA: do NOT source layout.sh / do scroll work. The §19 renderer recomputes
# the viewport every redraw and keeps the highlight visible regardless of
# STATE_SCROLL (§P7). Delete leaves scroll alone.
```

## Implementation Blueprint

### Data models and structure

No new data model. No new constants in `state.sh` (delete reuses the existing
`STATE_LIST` / `STATE_INDEX` / `STATE_FILTER` / `STATE_LINKED_ID` / `ORIG_SESSION`
keys). The state mutations are: rewrite `STATE_LIST` (drop S / rebuild), clamp
`STATE_INDEX`. `STATE_LINKED_ID` is read for the ownership test + unlink target
and is left for `preview.sh`'s re-sync to overwrite (NOT cleared — see FINDING 6).

### Implementation Tasks (ordered by dependencies)

```yaml
Task 1: EDIT scripts/session-mgmt.sh — ADD session_mgmt_delete + session_mgmt_do_delete
  - FILE: ./scripts/session-mgmt.sh  (EXISTING; created by P2.M1.T2.S1; already +x).
  - INSERT: both functions AFTER session_mgmt_do_rename's closing `}` and BEFORE
    `session_mgmt_main() {` (keep the driver last, mirroring the sibling's order).
  - VERBATIM CODE (TAB-indented function bodies; set -u + ${2:-} + get_state defaults):

    # session_mgmt_delete — the `delete)` action (PRD §21 §3.43). Resolve the
    # highlighted session/window, apply the guards (refuse with a message + NO
    # kill), then either confirm-before (if opt_confirm_delete on) or call
    # do-delete directly. The picker STAYS OPEN (no restore). MUST NOT reference
    # $2 (the M-BSpace binding passes no char; mirror rename/confirm).
    session_mgmt_delete() {
    	local _target _pick_type _orig _t_sess _list
    	_target="$(_lp_resolve_highlighted)"
    	[ -z "$_target" ] && return 0   # ranked empty -> no-op (PRD §21 §3.43 step 1)
    	_pick_type="$(opt_type)"
    	_orig="$(get_state "$ORIG_SESSION" "")"
    	# Guard A: refuse the DRIVER (killing it detaches the client). Session mode:
    	# _target is the name; window mode: _target is "session:window_index" -> session part.
    	if [ "$_pick_type" = "window" ]; then _t_sess="${_target%%:*}"; else _t_sess="$_target"; fi
    	if [ -n "$_orig" ] && [ "$_t_sess" = "$_orig" ]; then
    		tmux display-message "livepicker: cannot delete the driver session"
    		return 0
    	fi
    	# Guard B: refuse when deleting would strand the client / kill the server.
    	if [ "$_pick_type" = "window" ]; then
    		# Window mode: refuse the driver's ONLY window (FINDING 8).
    		if [ -n "$_orig" ]; then
    			local _drv_wins
    			_drv_wins="$(tmux list-windows -t "=$_orig" 2>/dev/null | wc -l)"
    			if [ "$_drv_wins" -le 1 ] && [ "$_t_sess" = "$_orig" ]; then
    				tmux display-message "livepicker: cannot delete the driver's only window"
    				return 0
    			fi
    		fi
    	else
    		# Session mode: raw list must have >=2 entries (FINDING 2: killing the
    		# last session kills the server). mapfile makes "" a truly empty array.
    		local -a _l=()
    		_list="$(get_state "$STATE_LIST" "")"
    		mapfile -t _l < <(printf '%s' "$_list")
    		if [ "${#_l[@]}" -le 1 ]; then
    			tmux display-message "livepicker: cannot delete the last session"
    			return 0
    		fi
    	fi
    	# confirm-before (optional; PRD §21 §3.43 step 3; FINDING 5). $S is resolved
    	# here (NOT %%). On 'y' it fires do-delete $S as its own run-shell; on n/Esc
    	# nothing runs. While open it suspends the livepicker table; picker stays open.
    	if [ "$(opt_confirm_delete)" = "on" ]; then
    		if [ "$_pick_type" = "window" ]; then
    			tmux confirm-before -p "Kill window $_target? (y/n)" \
    				"run-shell '$CURRENT_DIR/session-mgmt.sh do-delete $_target'"
    		else
    			tmux confirm-before -p "Kill session $_target? (y/n)" \
    				"run-shell '$CURRENT_DIR/session-mgmt.sh do-delete $_target'"
    		fi
    		return 0
    	fi
    	# No confirm: call do-delete directly (pass S as the arg).
    	session_mgmt_do_delete "$_target"
    	return 0
    }

    # session_mgmt_do_delete S — the destructive half (PRD §21 §3.43 step 4).
    # argv[2] = S (session name OR "session:window_index"). Session mode: unlink the
    # preview FIRST if it belongs to S (prevents the orphan leak, FINDING 3), then
    # kill-session. Window mode: kill-window (destroys the shared window -> no
    # orphan, FINDING 8). Then rewrite STATE_LIST, clamp the index onto a neighbour,
    # re-rank, re-sync the preview to the new highlight, refresh. Runs as its own
    # process (from session_mgmt_delete, OR standalone from confirm-before).
    session_mgmt_do_delete() {
    	local _S="${2:-}"
    	[ -z "$_S" ] && return 0
    	local _pick_type _orig _linked _list _new_list
    	_pick_type="$(opt_type)"
    	_orig="$(get_state "$ORIG_SESSION" "")"
    	_linked="$(get_state "$STATE_LINKED_ID" "")"
    	_list="$(get_state "$STATE_LIST" "")"

    	# DEFENSIVE re-check of the catastrophic length-<=1 guard (FINDING 2). The
    	# confirm-delete path has a time gap; a raced external kill could make S the
    	# last session -> killing it shuts the server down. S==ORIG_SESSION is stable
    	# across the gap, so only the length guard is re-checked (session mode).
    	if [ "$_pick_type" != "window" ]; then
    		local -a _l=()
    		mapfile -t _l < <(printf '%s' "$_list")
    		if [ "${#_l[@]}" -le 1 ]; then
    			tmux display-message "livepicker: cannot delete the last session"
    			return 0
    		fi
    	fi

    	if [ "$_pick_type" = "window" ]; then
    		# ===== WINDOW MODE (FINDING 8) =====
    		# kill-window destroys the window OBJECT in every session -> the driver's
    		# link dies with it -> NO orphan leak, NO unlink-first. Re-guard the
    		# driver's-only-window (the confirm gap could race).
    		if [ -n "$_orig" ]; then
    			local _drv_wins
    			_drv_wins="$(tmux list-windows -t "=$_orig" 2>/dev/null | wc -l)"
    			if [ "$_drv_wins" -le 1 ] && [ "${_S%%:*}" = "$_orig" ]; then
    				tmux display-message "livepicker: cannot delete the driver's only window"
    				return 0
    			fi
    		fi
    		tmux kill-window -t "$_S" 2>/dev/null || true
    		# REBUILD the list: renumber-windows is ON -> killing window i shifts later
    		# indices -> surviving tokens are stale. Re-derive exactly as activate does
    		# (livepicker.sh:192). The killed window is simply absent.
    		_new_list="$(tmux list-windows -a -F '#{session_name}:#{window_index}' 2>/dev/null)"
    	else
    		# ===== SESSION MODE (FINDINGS 3, 4, 9) =====
    		# Unlink the linked preview from the driver FIRST when it belongs to S,
    		# else kill-session leaves it as a permanent orphan (FINDING 3). Ownership
    		# test (FINDING 4): the linked id is one of S's windows.
    		if [ -n "$_linked" ] && [ -n "$_orig" ] && [ -n "$_S" ]; then
    			if tmux list-windows -t "=$_S" -F '#{window_id}' 2>/dev/null | grep -Fxq "$_linked"; then
    				# unlink ONE link (the driver's); source keeps it; kill below destroys it.
    				tmux unlink-window -t "$_orig:$_linked" 2>/dev/null || true
    			fi
    		fi
    		tmux kill-session -t "=$_S" 2>/dev/null || true
    		# DROP S from the raw list (sessions do not renumber; in-place line edit,
    		# matches the rename sibling; preserves order; one unique match). NOTE: do
    		# NOT clear STATE_LINKED_ID — preview.sh's re-link (below) unlinks the now-
    		# dead id (rc swallowed) and overwrites it (FINDING 6).
    		local -a _lines=()
    		local _i _x _first
    		mapfile -t _lines < <(printf '%s' "$_list")
    		for _i in "${!_lines[@]}"; do
    			[ "${_lines[$_i]}" = "$_S" ] && unset '_lines[_i]'
    		done
    		_new_list=""; _first=1
    		for _x in "${_lines[@]}"; do   # "${arr[@]}" skips the unset index
    			if [ "$_first" = 1 ]; then _new_list="$_x"; _first=0
    			else _new_list="$_new_list"$'\n'"$_x"; fi
    		done
    	fi

    	set_state "$STATE_LIST" "$_new_list"

    	# ===== SHARED re-sync tail (FINDINGS 6, 7) =====
    	# Re-rank the new list (the SAME function the renderer uses), clamp the index
    	# onto a valid neighbour, re-sync the preview to the new highlight, refresh.
    	# do-delete is its own process -> invoke preview.sh DIRECTLY (single-arg
    	# synchronous form; honors defer ORDERING but not the async -b launcher).
    	local _filt _new_L _idx _new_target
    	local -a _filtered=()
    	_filt="$(get_state "$STATE_FILTER" "")"
    	mapfile -t _filtered < <(lp_rank "$_new_list" "$_filt")
    	_new_L="${#_filtered[@]}"
    	_idx="$(get_state "$STATE_INDEX" "0")"
    	[[ "$_idx" =~ ^[0-9]+$ ]] || _idx=0
    	if [ "$_new_L" -gt 0 ]; then
    		[ "$_idx" -ge "$_new_L" ] && _idx=$(( _new_L - 1 ))   # clamp to a neighbour
    		set_state "$STATE_INDEX" "$_idx"
    		_new_target="${_filtered[$_idx]}"
    	else
    		set_state "$STATE_INDEX" "0"
    		_new_target=""   # no match -> no preview re-link (mirror _lp_preview_follow)
    	fi
    	# Re-sync the preview + redraw (§P5). Empty target -> just refresh.
    	if [ -n "$_new_target" ]; then
    		if [ "$(opt_preview_defer)" = "on" ]; then
    			tmux refresh-client -S 2>/dev/null || true
    			"$CURRENT_DIR/preview.sh" "$_new_target" 2>/dev/null || true
    		else
    			"$CURRENT_DIR/preview.sh" "$_new_target" 2>/dev/null || true
    			tmux refresh-client -S 2>/dev/null || true
    		fi
    	else
    		tmux refresh-client -S 2>/dev/null || true
    	fi
    	return 0
    }

  - FOLLOW pattern: session_mgmt_do_rename (the sibling; in-place mapfile rewrite +
    set_state + refresh + return 0); input-handler.sh `cancel`/`confirm` (guards +
    display-message + return 0).
  - NAMING: session_mgmt_* functions; local vars _-prefixed (house style; mirrors
    the rename sibling's _lp_resolve_highlighted / _new / _list).
  - PLACEMENT: scripts/session-mgmt.sh, between session_mgmt_do_rename and session_mgmt_main.

Task 2: EDIT scripts/session-mgmt.sh — add the dispatch branches in session_mgmt_main
  - FILE: ./scripts/session-mgmt.sh  (EXISTING).
  - REPLACE the P2.M1.T2.S2 seam comment inside session_mgmt_main's `case`:
        # --- P2.M1.T2.S2 seam: delete / do-delete (guards + unlink-first +
        #     kill-session + re-sync). Add `delete)` + `do-delete)` branches here. ---
    WITH:
        delete)     session_mgmt_delete ;;
        do-delete)  session_mgmt_do_delete "${2:-}" ;;
  - RESULT (the case body, mirroring rename/do-rename):
        case "$_action" in
            rename)     session_mgmt_rename ;;
            do-rename)  session_mgmt_do_rename "${2:-}" ;;
            delete)     session_mgmt_delete ;;
            do-delete)  session_mgmt_do_delete "${2:-}" ;;
            *)          return 0 ;;
        esac
  - GOTCHA: align the `)` labels + the `;;` with the existing rename/do-rename rows
    (same column). do-delete forwards "${2:-}" (S) exactly like do-rename forwards NEW.

Task 3: EDIT scripts/input-handler.sh — replace the delete seam with the dispatch branch
  - FILE: ./scripts/input-handler.sh  (EXISTING).
  - REPLACE the P2.M1.T2.S2 seam comment P2.M1.T2.S1 left (between rename)'s `;;`
    and `refresh-width)`):
        \t\t# --- P2.M1.T2.S2 seam: `delete)` -> "$CURRENT_DIR/session-mgmt.sh" delete. ---
    WITH (2-tab label / 3-tab body — mirror the rename) branch exactly):
        \t\t# --- P2.M1.T2.S2: delete the highlighted session/window (PRD §21 §3.43).
        \t\t#     Thin delegate — session-mgmt.sh hosts the guards + optional
        \t\t#     confirm-before + do-delete (unlink-first + kill + rewrite + clamp
        \t\t#     + re-rank + re-sync). MUST NOT reference $2 (the M-BSpace binding
        \t\t#     passes no char; mirror rename). The picker STAYS OPEN. ---
        \t\tdelete)
        \t\t\t"$CURRENT_DIR/session-mgmt.sh" delete
        \t\t\treturn 0
        \t\t\t;;
  - VERIFY: `grep -Pn '^\t\tdelete\)' scripts/input-handler.sh` -> 1 match; the seam
    comment is gone (`grep -c 'P2.M1.T2.S2 seam' scripts/input-handler.sh` -> 0).
  - DEPENDENCIES: $CURRENT_DIR (already defined); session-mgmt.sh delete from Task 1+2.

Task 4: VALIDATE (Level 1-4 below)
  - RUN: bash -n + shellcheck on both files; the isolated-socket spot-checks (the
    orphan-leak prevention is the headline check); tests/run.sh (expect all GREEN).
```

### Implementation Patterns & Key Details

```bash
# === Target resolution: REUSE the sibling's _lp_resolve_highlighted (VERBATIM the
#     confirm pattern) so delete acts on the SAME item the renderer highlights. ===
_target="$(_lp_resolve_highlighted)"
[ -z "$_target" ] && return 0

# === Guard A — driver session (session + window mode). Window token = "sess:idx". ===
if [ "$_pick_type" = "window" ]; then _t_sess="${_target%%:*}"; else _t_sess="$_target"; fi
if [ -n "$_orig" ] && [ "$_t_sess" = "$_orig" ]; then
    tmux display-message "livepicker: cannot delete the driver session"; return 0
fi

# === Guard B — length (session) / driver's-only-window (window). mapfile: "" -> []. ===
mapfile -t _l < <(printf '%s' "$_list")
if [ "${#_l[@]}" -le 1 ]; then tmux display-message "livepicker: cannot delete the last session"; return 0; fi

# === confirm-before (optional) — $S resolved here, NOT %% (FINDING 5). ===
tmux confirm-before -p "Kill session $_target? (y/n)" \
    "run-shell '$CURRENT_DIR/session-mgmt.sh do-delete $_target'"

# === The load-bearing unlink-first (session mode; FINDING 3/4). ===
# ONLY when the linked preview belongs to the victim. grep -Fxq = exact @N id match.
if [ -n "$_linked" ] && [ -n "$_orig" ] && [ -n "$_S" ]; then
    if tmux list-windows -t "=$_S" -F '#{window_id}' 2>/dev/null | grep -Fxq "$_linked"; then
        tmux unlink-window -t "$_orig:$_linked" 2>/dev/null || true   # ONE link; no -k
    fi
fi
tmux kill-session -t "=$_S" 2>/dev/null || true
# ... drop S from _list via mapfile + unset + join (NO trailing \n) ...

# === Window mode: kill-window destroys the shared window (no orphan); REBUILD list. ===
tmux kill-window -t "$_S" 2>/dev/null || true
_new_list="$(tmux list-windows -a -F '#{session_name}:#{window_index}' 2>/dev/null)"

# === Shared re-sync tail (FINDINGS 6/7). do-delete is its own process -> preview.sh. ===
mapfile -t _filtered < <(lp_rank "$_new_list" "$_filt")
_new_L="${#_filtered[@]}"
[ "$_idx" -ge "$_new_L" ] && _idx=$(( _new_L - 1 ))   # clamp onto a neighbour
if [ -n "$_new_target" ]; then
    "$CURRENT_DIR/preview.sh" "$_new_target" 2>/dev/null || true   # sync; self-cleans linked_id
    tmux refresh-client -S 2>/dev/null || true
fi

# === input-handler.sh delegate (Task 3) — one line, NO $2. ===
delete)
    "$CURRENT_DIR/session-mgmt.sh" delete
    return 0
    ;;
```

### Integration Points

```yaml
INPUT DISPATCH (input-handler.sh case "$action"):
  - REPLACE the P2.M1.T2.S2 seam comment with `delete)` -> "$CURRENT_DIR/session-mgmt.sh delete".
  - The M-BSpace binding (P2.M1.T1.S1) -> input-handler.sh delete -> THIS branch.

NEW ENTRY-POINT BRANCHES (session-mgmt.sh session_mgmt_main):
  - ADD: `delete)` -> session_mgmt_delete ; `do-delete)` -> session_mgmt_do_delete "${2:-}".
  - Invoked two ways: (a) `session-mgmt.sh delete` (from input-handler); (b)
    `session-mgmt.sh do-delete <S>` (from confirm-before's run-shell on 'y', OR from
    session_mgmt_delete directly when confirm is off).

STATE (state.sh):
  - NO new keys. Reads STATE_LIST/STATE_FILTER/STATE_INDEX/STATE_LINKED_ID/ORIG_SESSION;
    REWRITES STATE_LIST (drop line / rebuild) + clamps STATE_INDEX. STATE_LINKED_ID is
    read for the ownership test + unlink target; left for preview.sh to overwrite (NOT cleared).

PREVIEW (preview.sh):
  - Re-sync via DIRECT invocation `"$CURRENT_DIR/preview.sh" "$new_target"` (do-delete
    is its own process; cannot call input-handler's _lp_preview_follow — §P5/FINDING 6).
    preview.sh unlinks the now-dead prior preview (rc swallowed) + links the new one.

RESTORE (restore.sh): NO CALL. The picker STAYS OPEN after a delete (mode on).

ACTIVATION (livepicker.sh): NO CHANGE. The M-BSpace binding is P2.M1.T1.S1's output.

DATABASE / MIGRATIONS / ROUTES / CONFIG-FILE: none.
```

## Validation Loop

### Level 1: Syntax & Style (Immediate Feedback)

```bash
# Run from the repo root after editing both files.
bash -n scripts/session-mgmt.sh scripts/input-handler.sh          # syntax; expect exit 0
shellcheck scripts/session-mgmt.sh scripts/input-handler.sh       # lint; expect 0 findings
# session-mgmt.sh has both new functions + the dispatch branches; no seam remains:
grep -n 'session_mgmt_delete\b' scripts/session-mgmt.sh           # >= 3 (def + 2 calls in main)
grep -n 'session_mgmt_do_delete\b' scripts/session-mgmt.sh        # >= 3 (def + 2 calls)
grep -c 'P2.M1.T2.S2 seam' scripts/session-mgmt.sh                # == 0 (seam replaced)
grep -Pn '^\t\t\tdelete)' scripts/session-mgmt.sh                 # 0 (main uses inline labels)
grep -Pn 'delete)' scripts/session-mgmt.sh                        # the `delete)` label in main
# input-handler.sh has the dispatch branch (2-tab label) + no seam:
grep -Pn '^\t\tdelete\)' scripts/input-handler.sh && echo "delete) branch present" || echo "MISSING"
grep -c 'P2.M1.T2.S2 seam' scripts/input-handler.sh               # == 0 (seam replaced)
# session-mgmt.sh is still +x (P2.M1.T2.S1 set it):
[ -x scripts/session-mgmt.sh ] && echo "executable OK" || chmod +x scripts/session-mgmt.sh
```

### Level 2: Unit / Component Validation (do-delete logic, NO client needed)

```bash
# do-delete is testable DIRECTLY (call it with seeded state — no client). Throwaway
# isolated socket (self-cleaning). Exercises session-mode kill + orphan-leak
# prevention + index-clamp-on-neighbour + guards.
SOCK="lp-del-$$"; SHIM="$(mktemp -d)"
printf '#!/usr/bin/env bash\nexec /usr/bin/tmux -L "%s" "$@"\n' "$SOCK" > "$SHIM/tmux"
chmod +x "$SHIM/tmux"
trap '/usr/bin/tmux -L "$SOCK" kill-server 2>/dev/null; rm -rf "$SHIM"' EXIT
export PATH="$SHIM:$PATH"
tmux new-session -d -s driver -x 120 -y 40
tmux new-session -d -s alpha  -x 120 -y 40
tmux new-session -d -s beta   -x 120 -y 40
# Seed picker state as activate would (highlight on alpha at index 1; preview = alpha's window).
SRC="$(tmux list-windows -t '=alpha' -F '#{window_id}' -f '#{window_active}')"
tmux link-window -s "$SRC" -t 'driver:'                       # simulate the live preview link
tmux set-option -g @livepicker-list $'driver\nalpha\nbeta'
tmux set-option -g @livepicker-filter ''
tmux set-option -g @livepicker-index 1
tmux set-option -g @livepicker-linked-id "$SRC"
tmux set-option -g @livepicker-orig-session driver
tmux set-option -g @livepicker-preview-defer off
drv_before="$(tmux list-windows -t '=driver' | wc -l)"
# (a) happy path: delete the highlighted+previewed session (alpha) -> no orphan, neighbour highlighted.
bash scripts/session-mgmt.sh do-delete alpha
tmux has-session -t '=alpha' 2>/dev/null && echo "KILL FAIL (alpha alive)" || echo "KILL OK (alpha gone)"
echo "list now: [$(tmux show-option -gqv @livepicker-list)]"            # driver\nbeta (alpha dropped)
echo "index:    [$(tmux show-option -gqv @livepicker-index)]"           # 1 (clamped; beta is the neighbour)
drv_after="$(tmux list-windows -t '=driver' | wc -l)"
echo "driver windows before=$drv_before after=$drv_after"
# ORPHAN-LEAK CHECK: alpha's window must NOT survive in the driver. The driver's
# window count drops by 1 (the preview was unlinked-first, then alpha killed).
[ "$drv_after" -lt "$drv_before" ] && echo "NO-ORPHAN OK (driver shrank)" || echo "ORPHAN LEAK (driver unchanged)"
echo "linked-id now: [$(tmux show-option -gqv @livepicker-linked-id)]"   # re-linked to beta's window (or '' if self)

# (b) GUARD: driver session refused (no kill). Re-seed.
tmux set-option -g @livepicker-list $'driver\nbeta'
tmux set-option -g @livepicker-index 0
bash scripts/session-mgmt.sh do-delete driver
tmux has-session -t '=driver' && echo "DRIVER-GUARD OK (driver alive)" || echo "DRIVER-GUARD FAIL (killed driver!)"

# (c) GUARD: last session refused. Kill beta so only driver remains in the list.
tmux set-option -g @livepicker-list $'driver'
bash scripts/session-mgmt.sh do-delete driver
tmux has-session -t '=driver' && echo "LAST-SESSION-GUARD OK (server alive)" || echo "LAST-SESSION-GUARD FAIL (server died!)"

# (d) clamp-to-prev when deleting the LAST ranked item. Re-seed 3 sessions, index at last.
tmux new-session -d -s g1 -x 120 -y 40; tmux new-session -d -s g2 -x 120 -y 40
tmux set-option -g @livepicker-list $'driver\ng1\ng2'
tmux set-option -g @livepicker-index 2          # highlight on g2 (the last)
bash scripts/session-mgmt.sh do-delete g2
echo "index after deleting last: [$(tmux show-option -gqv @livepicker-index)]"   # 1 (clamped to g1)
# Expected: alpha killed, NO orphan in driver, list=driver\nbeta, index=1 (beta);
#           driver guard keeps driver alive; last-session guard keeps the server up;
#           deleting the last ranked item clamps the index to the previous (g1).
```

### Level 3: Integration Testing (the input dispatch + picker-stays-open)

```bash
# Manual spot-check on an isolated socket WITH an attached client (the M-BSpace key +
# confirm-before are client commands). Self-cleaning.
SOCK="lp-del-i-$$"; SHIM="$(mktemp -d)"
printf '#!/usr/bin/env bash\nexec /usr/bin/tmux -L "%s" "$@"\n' "$SOCK" > "$SHIM/tmux"
chmod +x "$SHIM/tmux"
trap '/usr/bin/tmux -L "$SOCK" kill-server 2>/dev/null; rm -rf "$SHIM"' EXIT
export PATH="$SHIM:$PATH"
tmux new-session -d -s driver -x 120 -y 40
tmux new-session -d -s alpha  -x 120 -y 40
tmux set-option -g @livepicker-key Space
tmux set-option -g @livepicker-confirm-delete off
script -qec "tmux -L "$SOCK" attach -t driver" /dev/null >/dev/null 2>&1 & AP=$!; sleep 0.5
bash scripts/livepicker.sh                                     # activate (binds M-BSpace via P2.M1.T1.S1)
echo "M-BSpace bind: $(tmux list-keys -T livepicker M-BSpace)"  # run-shell .../input-handler.sh delete
# Drive delete directly through the dispatch path (input-handler delete -> session-mgmt delete):
tmux send-keys -T livepicker M-BSpace 2>/dev/null || true
sleep 0.3
echo "mode after delete: [$(tmux show-option -gqv @livepicker-mode)]"   # on (picker stays open)
# Confirm alpha was killed (highlight was on it post-activate):
tmux has-session -t '=alpha' 2>/dev/null && echo "INTEG: alpha still alive (nav may have moved highlight)" || echo "INTEG OK (alpha killed via M-BSpace)"
# confirm-before path: turn it on, send delete, answer 'n' -> no kill.
tmux set-option -g @livepicker-confirm-delete on
tmux new-session -d -s gamma -x 120 -y 40
tmux send-keys -T livepicker M-BSpace 2>/dev/null || true; sleep 0.2
tmux send-keys 'n' 2>/dev/null || true; sleep 0.2
tmux set-option -g @livepicker-confirm-delete off
kill "$AP" 2>/dev/null
# Expected: M-BSpace is bound; pressing it kills the highlighted session via the
# dispatch path; the picker stays open (mode on). (Interactive confirm-before y/n
# is a manual check; the do-delete logic is proven in Level 2.)
```

### Level 4: Creative & Domain-Specific Validation

```bash
# (1) Full regression: the existing suite must stay GREEN (delete is reachable only
#     via M-BSpace, which no existing test presses; the full delete suite is P2.M2.T1.S1).
tests/run.sh
# Expected: exit 0; "N passed, 0 failed".

# (2) WINDOW MODE: kill-window + rebuild (renumber) + driver's-only-window refuse.
SOCK="lp-del-w-$$"; SHIM="$(mktemp -d)"
printf '#!/usr/bin/env bash\nexec /usr/bin/tmux -L "%s" "$@"\n' "$SOCK" > "$SHIM/tmux"
chmod +x "$SHIM/tmux"; trap '/usr/bin/tmux -L "$SOCK" kill-server 2>/dev/null; rm -rf "$SHIM"' EXIT
export PATH="$SHIM:$PATH"
tmux new-session -d -s drv -x 120 -y 40 -n w0
tmux new-window -t drv -n w1
tmux new-session -d -s other -x 120 -y 40 -n ow0
tmux set-option -g @livepicker-type window
tmux set-option -g @livepicker-list "$(tmux list-windows -a -F '#{session_name}:#{window_index}')"
tmux set-option -g @livepicker-filter ''
tmux set-option -g @livepicker-index 1            # highlight on drv:1 (w1)
tmux set-option -g @livepicker-orig-session drv
tmux set-option -g @livepicker-preview-defer off
# kill drv:1 (driver has 2 windows -> allowed). List must REBUILD (indices shift).
bash scripts/session-mgmt.sh do-delete 'drv:1'
echo "list rebuilt: [$(tmux show-option -gqv @livepicker-list)]"   # drv:0 + other:0 (no drv:1)
# refuse the driver's ONLY window: kill down to one driver window, try to delete it.
tmux kill-window -t 'drv:0' 2>/dev/null || true
tmux new-window -t drv -n only
tmux set-option -g @livepicker-list "$(tmux list-windows -a -F '#{session_name}:#{window_index}')"
bash scripts/session-mgmt.sh do-delete "$(tmux list-windows -a -F '#{session_name}:#{window_index}' | grep '^drv:' | head -1)"
tmux list-windows -t '=drv' >/dev/null 2>&1 && echo "WINDOW: driver's-only-window REFUSED OK" || echo "WINDOW FAIL (driver destroyed)"
# Expected: window-mode kill rebuilds the list (indices correct); the driver's only
# window is refused (driver survives).

# (3) Interactive confirm-before (manual, real client): activate, set
#     @livepicker-confirm-delete on, press M-BSpace, see "Kill session X? (y/n)";
#     press 'y' -> session killed, neighbour highlighted; press 'n'/Esc -> no kill,
#     picker stays open. (The non-interactive do-delete + guard logic is proven above.)

# (4) ORPHAN-LEAK regression (the headline invariant): repeat Level 2a and ASSERT
#     the driver window count drops by exactly the preview window (no survival).
#     This is the single most important check for this task (PRD §16 / §21.4).
```

## Final Validation Checklist

### Technical Validation

- [ ] `bash -n scripts/session-mgmt.sh scripts/input-handler.sh` exits 0, no output.
- [ ] `shellcheck scripts/session-mgmt.sh scripts/input-handler.sh` reports 0 findings.
- [ ] `session-mgmt.sh` has `session_mgmt_delete` + `session_mgmt_do_delete`;
      `session_mgmt_main` dispatches `delete)` / `do-delete)`; no seam comment remains.
- [ ] `input-handler.sh` has the `delete)` branch at 2-tab indent; no seam comment.
- [ ] `session-mgmt.sh` is still `chmod +x`; uses `set -u` (NOT `-e`).

### Feature Validation

- [ ] `M-BSpace` kills the highlighted session; it leaves the list; a neighbour is
      highlighted + previewed; the picker stays open (Level 2a/3).
- [ ] **NO orphan leak**: deleting the currently-previewed session unlinks the
      preview FIRST; the driver window count drops (no survival) (Level 2a / 4.4).
- [ ] The driver session is refused (`display-message`, no kill) (Level 2b).
- [ ] The last session is refused (`display-message`, server stays up) (Level 2c).
- [ ] Deleting the last ranked item clamps the index to the previous neighbour (2d).
- [ ] `@livepicker-confirm-delete on` -> `confirm-before`; `y` kills, `n`/Esc does not.
- [ ] Window mode: `kill-window`, list rebuilt (correct indices), driver's-only-window
      refused, re-sync works (Level 4.2).
- [ ] The picker stays open after a delete (`@livepicker-mode` still `on`).

### Code Quality Validation

- [ ] `session_mgmt_delete` reuses `_lp_resolve_highlighted` (does NOT re-implement
      resolution) so delete acts on the same item the renderer highlights.
- [ ] do-delete unlinks the preview FIRST **only when `STATE_LINKED_ID` belongs to S**
      (grep -Fxq ownership test) — never unlinks a non-victim preview (FINDING 4).
- [ ] do-delete re-syncs via `preview.sh` directly (its own process; does NOT call
      input-handler's `_lp_preview_follow`); honors `opt_preview_defer` ordering.
- [ ] `STATE_LINKED_ID` is NOT cleared (preview.sh's re-link self-cleans it).
- [ ] Window mode REBUILDS the list (`list-windows -a`); session mode drops one line.
- [ ] `set -u` honored (`${2:-}`, `get_state … ""`); non-zero rc swallowed (`|| true`).
- [ ] Uses `$CURRENT_DIR` (NOT `$SCRIPT_DIR`); sources options/utils/state/rank only.

### Documentation & Deployment

- [ ] NO docs edit (the README note landed in P2.M1.T1.S1; full prose is P4.T1).
- [ ] NO new test file (`test_session_mgmt.sh` is P2.M2.T1.S1).
- [ ] NO CHANGELOG edit (P4.T2 owns the [Unreleased] entry).

---

## Anti-Patterns to Avoid

- ❌ Don't `kill-session` WITHOUT unlinking the linked preview first (when it belongs
  to the victim). The window SURVIVES in the driver as a permanent orphan (PRD §16;
  FINDING 3 — CONFIRMED live). `unlink-window -t "$ORIG_SESSION:$linked_id"` (no `-k`)
  FIRST, then kill.
- ❌ Don't unlink the preview UNCONDITIONALLY. Only unlink when `STATE_LINKED_ID`
  belongs to S (the grep -Fxq ownership test). If the preview lagged to another
  session (defer), unlinking a non-victim window would wrongly detach it (FINDING 4).
- ❌ Don't use `unlink-window -k`. `-k` destroys the shared window in ALL sessions
  (preview.sh FINDING 11). The driver's preview removal must be a ONE-link unlink.
- ❌ Don't skip the guards. Killing the last session SHUTS THE SERVER DOWN (rc=0;
  FINDING 2). Killing the driver detaches the client. Guard on raw list length ≤1
  (session) and the driver's-only-window (window), in BOTH `delete)` and `do-delete`
  (the confirm path has a time gap — re-check the catastrophic length guard).
- ❌ Don't call `_lp_preview_follow` / `_lp_fire_preview` from `do-delete`.
  `session-mgmt.sh` is its own process (run-shell); those helpers live in
  `input-handler.sh` and are NOT available. Invoke `preview.sh` directly (single-arg
  synchronous form). The contract explicitly allows "via _lp_preview_follow /
  preview.sh" (FINDING 6).
- ❌ Don't clear `STATE_LINKED_ID` in do-delete. `preview.sh`'s re-link unlinks the
  now-dead prior preview (rc swallowed) and overwrites `linked_id` — it self-cleans.
  Clearing it unconditionally would drop tracking of a lagged non-victim preview,
  leaking that window into the driver (FINDING 6).
- ❌ Don't "drop one line" to rewrite the list in WINDOW mode. `renumber-windows` is
  ON, so killing window `i` shifts every later index → surviving `session:window_index`
  tokens are stale. REBUILD via `list-windows -a -F '#{session_name}:#{window_index}'`
  (verbatim activate form). Session mode DOES drop one line (sessions are by name).
  (FINDING 8.)
- ❌ Don't use `set -e` in session-mgmt.sh. `kill-session`/`kill-window`/`unlink-window`
  legitimately return non-zero (vanished target, singly-linked unlink). Swallow with
  `|| true` or check rc with `if !`. House style is `set -u` only.
- ❌ Don't find S's position and decrement the index. Drop S, re-rank, clamp to
  `min(idx, new_filtered_len-1)` — the new filtered list is the old minus S (same
  order), so clamping naturally lands on a neighbour (next, or prev if S was last).
  (FINDING 7.)
- ❌ Don't reference `$2` in `session_mgmt_delete` / the input-handler `delete)` branch
  (the M-BSpace binding passes no char; mirror rename/confirm/cancel). `do_delete`
  is the only function that reads `${2:-}` (S).
- ❌ Don't add `STATE_*`/`ORIG_*` keys, source layout.sh, or touch scroll. Delete
  reuses the existing keys; the renderer recomputes the viewport every redraw and
  keeps the highlight visible regardless of `STATE_SCROLL` (§P7).
- ❌ Don't create tests here. `test_session_mgmt.sh` is P2.M2.T1.S1. The gate for THIS
  task is the existing suite stays GREEN + the Level 2-4 spot-checks (the orphan-leak
  check is the headline).
