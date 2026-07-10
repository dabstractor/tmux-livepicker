# PRP — P2.M1.T2.S1: Extend preview.sh signature + chosen-window link flow + self-session flip

---

## Goal

**Feature Goal**: Extend `scripts/preview.sh` to accept an optional **chosen
window-id** (the window the user has flipped to within the highlighted session)
and link/select THAT window instead of always the candidate's active window. The
signature changes from `preview.sh <session> <seq>` to
`preview.sh <session> [window-id] [seq]` (`$2` = chosen window-id, `$3` = the
deferred-preview supersede seq). Self-session flip selects among the driver's own
windows. Thread the window-id through `input-handler.sh`'s `_lp_fire_preview` /
`_lp_preview_dispatch` helpers. **Session-nav behavior is unchanged** (every
current caller passes no window-id → `$2=""` → all chosen-window branches skipped).

**Deliverable** (2 existing files edited, NO new file):
1. **`scripts/preview.sh`** — new 3-arg signature; chosen-window branch in
   `src_id` resolution; self-session flip (select `chosen_win`); snapshot
   chosen-window capture; `STATE_PREVIEW_WIN_ID` writes on the live paths; the 3
   seq guards repointed to `$3` via the binding.
2. **`scripts/input-handler.sh`** — `_lp_fire_preview`/`_lp_preview_dispatch`
   accept + thread an optional `WIN_ID` 2nd arg; the `run-shell -b` call passes
   3 positional args.

**Success Definition**:
- `bash -n`/`shellcheck` clean on both files.
- Session-nav/type/backspace/cancel-clear are **byte-identical** (no win_id →
  `$2=""` → chosen-win branches skipped): `tests/run.sh` stays GREEN.
- A direct `preview.sh "<S>" "@<id>"` (chosen-win, inline) links/shows THAT window
  in the driver and sets `@livepicker-linked-id` == `@livepicker-preview-win-id`
  == the chosen `@id` (non-self); for the self-session it selects the chosen
  driver window (no link), sets `@livepicker-preview-win-id` == chosen `@id`,
  leaves `@livepicker-linked-id` empty.
- Session-nav (no chosen-win): `@livepicker-preview-win-id` == the active window
  `@id` (non-self) / `ORIG_WINDOW` (self) — the new additive state write, cleared
  on exit.
- The 3 deferred-preview seq guards still supersede stale `-b` jobs (they now read
  `$3`).

## User Persona (if applicable)

**Target User**: Future work items — P2.M1.T3 (`next-window`/`prev-window` flip
actions, the FIRST caller to pass a real window-id) and P2.M2.T1 (confirm lands on
`(session, window)`). This task is the preview-side seam they consume; DOCS=none.

**Use Case**: (Post-P2.M1.T3) the user highlights a session, then flips through
ITS windows with the window-axis keys; the live preview follows to the flipped
window. Today this task only makes preview.sh ABLE to show a chosen window and
threads the arg; no key fires a flip yet.

**Pain Points Addressed**: PRD §3.6/§7 window navigation — the preview must show
"whichever window the user has flipped to", not always the candidate's active
window.

## Why

- **PRD §7 / §3.6**: "show window `W` of candidate session `S` (`W` defaults to
  `S`'s active window, and is whatever window the user has flipped to otherwise)".
  Today preview.sh ALWAYS resolves the active window (gap_analysis §a).
- **gap_analysis_confirm_preview.md §(a)/(c)/(d)**: the signature must shift to
  `<session> [window-id] [seq]`; src_id resolution must use the supplied window-id;
  the self-session edge case must select among the driver's own windows.
- **Decoupling**: making preview.sh chosen-window-aware + threading the arg now
  (backward-compat) lets P2.M1.T3 (the flip actions) land as a pure input-handler
  addition that calls `_lp_preview_dispatch "$target" "$win_id"`.
- **STATE_PREVIEW_WIN_ID** (defined+init'd by P2.M1.T1.S1) is the logical
  shown-window tracker; this task writes it (overlaps `STATE_LINKED_ID` non-self,
  diverges for self).

## What

1. **preview.sh** — (a) signature `local S chosen_win expected_seq` = `$1 $2 $3`;
   (b) the 3 seq guards read `$3` via the binding; (c) `src_id` resolution adds a
   `[ -n "$chosen_win" ]` branch (session mode only); (d) self-session guard
   selects `chosen_win` when supplied (else `ORIG_WINDOW`) + writes
   `STATE_PREVIEW_WIN_ID`; (e) idempotent pre-link check + final commit ALSO write
   `STATE_PREVIEW_WIN_ID="$src_id"`; (f) snapshot path passes `chosen_win` to
   `preview_fallback` (which builds `=$S:$chosen_win.`); (g) leave-no-trace
   preserved (link/select always target the driver).
2. **input-handler.sh** — `_lp_fire_preview TARGET [WIN_ID]` and
   `_lp_preview_dispatch TARGET [WIN_ID]` thread the optional window-id; the
   `run-shell -b` call becomes 3 positional args; the defer=off inline call passes
   `target` + `win_id`.

### Success Criteria

- [ ] preview.sh signature is `local S="${1:-}" chosen_win="${2:-}" expected_seq="${3:-}"`.
- [ ] The 3 seq guards supersede on the `expected_seq` local (now bound from `$3`).
- [ ] `src_id` uses `chosen_win` directly when non-empty (session mode); window-mode
      token logic + `window_active` fallback unchanged.
- [ ] Self-session + `chosen_win` non-empty → `select-window -t "$chosen_win"` (no
      link) + `STATE_PREVIEW_WIN_ID="$chosen_win"`; `chosen_win` empty → ORIG_WINDOW
      + `STATE_PREVIEW_WIN_ID="$ORIG_WINDOW"`.
- [ ] Non-self idempotent check + final commit set BOTH `STATE_LINKED_ID` AND
      `STATE_PREVIEW_WIN_ID` = `$src_id`.
- [ ] Snapshot + `chosen_win` → captures `=$S:$chosen_win.`; `off` → no-op.
- [ ] `_lp_fire_preview`/`_lp_preview_dispatch` accept `[WIN_ID]`; run-shell passes
      3 args; existing 1-arg callers unchanged (win_id="").
- [ ] `tests/run.sh` stays GREEN; `bash -n`/`shellcheck` clean.

## All Needed Context

### Context Completeness Check

_Pass_: A developer who has never seen this repo can implement all edits from
(a) the verbatim oldText/newText anchors below (every edit region quoted from the
current file), (b) the 10 findings in `research/findings.md` — most critically
**FINDING 1** (the 3 seq guards reference the `expected_seq` LOCAL, so ONE binding
edit repoints all 3 — do NOT edit the guards themselves), **FINDING 2/3** (bare
`@id` select + `=session:@id.` capture both verified rc=0), **FINDING 4** (the
4 call sites + backward-compat), **FINDING 5** (preview_main structure / edit
regions in execution order), and **FINDING 6** (STATE_PREVIEW_WIN_ID vs
STATE_LINKED_ID — set both non-self, only PREVIEW_WIN_ID self). No external
library knowledge needed beyond the shipped link/unlink/select primitives.

### Documentation & References

```yaml
# MUST READ — the file you EDIT #1 (preview core).
- file: scripts/preview.sh
  why: preview_main signature (line 80); the 3 seq guards (~91/210/253 — all read
       the `expected_seq` local); the mode gate (~98-105); the self-session guard
       (~121-150); src_id resolution (~153-167); idempotent pre-link check
       (~174-188); duplicate guard (~191-196); unlink+link+select+commit
       (~210-259); preview_fallback (~44-62, the snapshot target build). TAB-indented.
  pattern: "local S=\"${1:-}\" expected_seq=\"${2:-}\"  ->  + chosen_win=\"${2:-}\", expected_seq=\"${3:-}\""
  gotcha: the guards use the LOCAL `expected_seq` — change the BINDING, not the guards.

# MUST READ — the file you EDIT #2 (the fire/dispatch helpers).
- file: scripts/input-handler.sh
  why: _lp_fire_preview (194) builds the run-shell -b cmd (currently 2 args);
       _lp_preview_dispatch (229) honors defer on/off; _lp_sync_preview_to_top_match
       (130) + next/prev-session (363/390) call dispatch with 1 arg (target only).
  pattern: "local target=\"${1:-}\"  ->  + win_id=\"${2:-}\"; thread into run-shell + inline call."
  gotcha: existing callers pass 1 arg -> win_id="" -> backward-compat. Do NOT change them.

# MUST READ — the state keys this task writes (defined+init'd by P2.M1.T1.S1).
- file: scripts/state.sh
  why: STATE_PREVIEW_WIN_ID (@livepicker-preview-win-id, line ~60) + STATE_LINKED_ID
       (@livepicker-linked-id) + STATE_PREVIEW_SEQ + ORIG_SESSION/ORIG_WINDOW.
       All in _STATE_RUNTIME_KEYS (teardown wired). get_state/set_state accessors.
  critical: STATE_PREVIEW_WIN_ID is ALREADY defined+init'd to "" at activate (P2.M1.T1.S1);
            this task only WRITES it. Do NOT add/rename keys.

# MUST READ — the gap analysis (the contract source for §a/§c/§d).
- docfile: plan/004_2c5127285a90/architecture/gap_analysis_confirm_preview.md
  why: §(a) preview resolves active window only (the gap); §(c) changes needed
       (signature shift, src_id from window-id, self-session flip); §(d) self-session
       edge case; "Window-id addressing verification" (select-window -t '=S:@id' rc=0).
  section: "(a) preview.sh resolves the active window only", "(c) Changes needed", "(d) Self-session edge case"

# MUST READ — empirical: bare @id select + =session:@id. capture (this task's findings).
- docfile: plan/004_2c5127285a90/architecture/external_deps.md
  why: §1 "select-window -t '=test_sess:@1' -> rc=0" (window-id addressing works).
  section: "## 1. Window-id addressing"

# MUST READ — the PRD preview subsystem (the "W = flipped window" requirement).
- docfile: PRD.md
  why: §7 "show window W of candidate session S (W defaults to S's active window,
       and is whatever window the user has flipped to otherwise)"; §3.6 window
       navigation; §3.13 self-session edge case (flip moves the driver's active
       window; cancel hard-resets to ORIG_WINDOW).
  section: "§7 The preview subsystem (Mechanism / Self-session edge case)", "§3.6 Window navigation"

# MUST READ — the parallel previous task (the state seam this consumes).
- docfile: plan/004_2c5127285a90/P2M1T1S1/PRP.md
  why: P2.M1.T1.S1 DEFINED+INIT'd the 4 window-cursor keys (incl. STATE_PREVIEW_WIN_ID
       = @livepicker-preview-win-id, init '') + wired teardown. This task WRITES
       preview-win-id; P2.M1.T3 will be the first to pass a real chosen_win.
  critical: assume STATE_PREVIEW_WIN_ID exists + is init'd to "" at activate (DONE).

# MUST READ — the ground-truth findings for THIS task (10 findings).
- docfile: plan/004_2c5127285a90/P2M1T2S1/research/findings.md
  why: FINDING 1 (binding edit repoints all 3 guards); FINDING 2/3 (verified @id
       select + =session:@id. capture); FINDING 4 (call sites + backward-compat);
       FINDING 5 (preview_main edit regions in order); FINDING 6 (PREVIEW_WIN_ID vs
       LINKED_ID); FINDING 8 (preview_fallback target build); FINDING 10 (no-regression proof).
  critical: FINDING 1 prevents editing 3 guards (one binding edit suffices).
```

### Current Codebase tree

```bash
tmux-livepicker/
  scripts/
    preview.sh          # MODIFY: signature + chosen-window + self-session flip + PREVIEW_WIN_ID writes.
    input-handler.sh    # MODIFY: _lp_fire_preview + _lp_preview_dispatch thread WIN_ID.
    state.sh            # UNCHANGED (STATE_PREVIEW_WIN_ID etc. already exist — P2.M1.T1.S1).
    options.sh utils.sh rank.sh layout.sh renderer.sh livepicker.sh restore.sh session-mgmt.sh  # UNCHANGED
  tests/
    *.sh                # UNCHANGED (no test asserts PREVIEW_WIN_ID; the window-flip suite is P2.M3.T1.S1).
  plan/004_2c5127285a90/{architecture/{gap_analysis_confirm_preview.md,external_deps.md}, P2M1T1S1/PRP.md, P2M1T2S1/research/findings.md}
```

### Desired Codebase tree with files to be added and responsibility of file

```bash
scripts/preview.sh         # +3-arg signature; chosen-window src_id branch; self-session flip;
                           #  PREVIEW_WIN_ID writes; snapshot chosen-window capture; guards read $3.
scripts/input-handler.sh   # _lp_fire_preview/_lp_preview_dispatch + [WIN_ID] arg; 3-arg run-shell.
```

### Known Gotchas of our codebase & Library Quirks

```bash
# CRITICAL (FINDING 1): the 3 seq guards reference the LOCAL `expected_seq`, NOT $2.
# Change the BINDING `expected_seq="${2:-}"` -> `"${3:-}"` (adding chosen_win="${2:-}"),
# and all 3 guards inherit the new position. Do NOT hand-edit the 3 guard blocks.

# CRITICAL (FINDING 6): set STATE_PREVIEW_WIN_ID == src_id on NON-SELF paths (idempotent
# check + final commit) ALONGSIDE STATE_LINKED_ID. On the SELF-SESSION path set ONLY
# STATE_PREVIEW_WIN_ID (chosen_win or ORIG_WINDOW) — STATE_LINKED_ID stays empty.
# The duplicate guard sets NEITHER (already tracked) — leave it untouched.

# CRITICAL (FINDING 4): every current caller of _lp_preview_dispatch/_lp_fire_preview
# passes 1 arg (target). win_id="${2:-}" -> "" -> preview.sh chosen_win="" -> all
# chosen-window branches skipped -> byte-identical session-nav. Do NOT change the
# existing callers; P2.M1.T3 will be the first to pass a real win_id.

# CRITICAL (FINDING 9): leave-no-trace is preserved by CONSTRUCTION — unlink/link/select
# always target $current_session (the driver). chosen_win only changes WHICH @id is
# resolved as src_id; it flows into the same driver-only sequence. No extra guard.

# GOTCHA: chosen_win is a server-global @id (e.g. @1), NOT an index. select-window -t
# "$chosen_win" (bare @id) is the SAME primitive the code uses everywhere (verified
# FINDING 2). For snapshot, the target is "=session:@id." (rc=0 — FINDING 3).

# GOTCHA: the chosen-window branch in src_id resolution is SESSION-MODE ONLY
# (opt_type != window). Window mode (flat picker) resolves from the session:index
# token — do NOT touch that branch (gap_analysis §e: two distinct "window" concepts).

# GOTCHA: snapshot/off do NOT write STATE_PREVIEW_WIN_ID (FINDING 7). Snapshot just
# captures (pass chosen_win to preview_fallback); off is a no-op. Mode is constant
# for the picker lifetime, so live/snapshot never interleave.

# GOTCHA (indentation): preview.sh + input-handler.sh use TABS. Every oldText/newText
# must use a leading TAB (the function bodies). A space-prefixed oldText won't match.

# GOTCHA (set -u): preview.sh has NO set -e; set -u inherited. chosen_win/expected_seq
# are defaulted at the binding ("${2:-}"/"${3:-}"). The header argv comment + the
# GUARD-1 comment reference "$2" — update them to "$3"/chosen_win for accuracy.
```

## Implementation Blueprint

### Data models and structure

No new data model. The signature is the contract:

| Position | Name | Meaning | Empty when |
|----------|------|---------|------------|
| `$1` | `S` | candidate session name (or `session:index` token in window mode) | never (caller guards) |
| `$2` | `chosen_win` | the flipped window `@id` (session mode) | session-nav, first preview, window mode |
| `$3` | `expected_seq` | deferred-preview supersede seq | inline calls (first preview, defer=off) |

`STATE_PREVIEW_WIN_ID` (`@livepicker-preview-win-id`) is written, not defined
(P2.M1.T1.S1 owns the definition + init).

### Implementation Tasks (ordered by dependencies)

```yaml
Task 1: EDIT scripts/preview.sh — the signature binding (FINDING 1: repoints ALL 3 guards)
  - FILE: ./scripts/preview.sh (EXISTING).
  - oldText (line 80; TAB-indented):
  	local S="${1:-}" expected_seq="${2:-}"
  - newText:
  	local S="${1:-}" chosen_win="${2:-}" expected_seq="${3:-}"
  - WHY: the 3 seq guards (~91/210/253) reference the LOCAL `expected_seq`; binding
    it from $3 repoints all 3 in ONE edit. chosen_win from $2 is the new arg.
  - DO NOT edit the guard blocks themselves (FINDING 1).

Task 2: EDIT scripts/preview.sh — update the GUARD-1 comment ($2 -> $3) for accuracy
  - FILE: ./scripts/preview.sh.
  - oldText:
  	# When called WITH an expected_seq ($2 — the deferred background path from
  - newText:
  	# When called WITH an expected_seq ($3 — the deferred background path from
  - ALSO (same comment block): oldText `# preview-defer=off synchronous path), the guard is SKIPPED` is fine;
    the "ONE arg ($2 empty" phrasing is now "TWO args (target + win_id, $3 empty)" —
    update if you want perfect accuracy, but the $2->$3 fix is the load-bearing part.

Task 3: EDIT scripts/preview.sh — snapshot path passes chosen_win to preview_fallback (item f)
  - FILE: ./scripts/preview.sh.
  - oldText:
  	if [ "$mode" = "snapshot" ]; then
  		# Snapshot: capture-pane of S's active pane; NEVER link. Self-session
  		# needs no special handling (capturing your own pane is harmless).
  		preview_fallback "$S"
  		return $?
  	fi
  - newText:
  	if [ "$mode" = "snapshot" ]; then
  		# Snapshot: capture-pane of S's (or the FLIPPED window's) active pane; NEVER
  		# link. chosen_win (session-mode flip) -> capture THAT window's active pane;
  		# else S's active window. Self-session needs no special handling (capturing
  		# your own pane is harmless). (PRD §7 Fallbacks; P2.M1.T2 chosen-window.)
  		preview_fallback "$S" "$chosen_win"
  		return $?
  	fi

Task 4: EDIT scripts/preview.sh — self-session flip (item d): select chosen_win + STATE_PREVIEW_WIN_ID
  - FILE: ./scripts/preview.sh.
  - oldText (the self-session select block):
  		# Select the target window: window mode -> the specific "session:index"
  		# ($S); session mode -> the original active window. NO link in either case.
  		if [ "$(opt_type)" = "window" ]; then
  			tmux select-window -t "$S" 2>/dev/null || true
  		else
  			[ -n "$orig_window" ] && tmux select-window -t "$orig_window" 2>/dev/null || true
  		fi
  		return 0
  - newText:
  		# Select the target window: window mode -> the specific "session:index" ($S);
  		# session mode -> the FLIPPED window ($chosen_win, P2.M1.T2) if supplied, else
  		# ORIG_WINDOW. NO link in any case. Record STATE_PREVIEW_WIN_ID (the logical
  		# shown window — overlaps STATE_LINKED_ID for non-self, DIVERGES here: linked-id
  		# stays empty for self; preview-win-id = the driver window now shown). Flipping
  		# the driver's own windows while browsing moves its active window; cancel's hard
  		# reset to ORIG_WINDOW (restore STEP 2) undoes it. (PRD §7 self-session; §3.6.)
  		if [ "$(opt_type)" = "window" ]; then
  			tmux select-window -t "$S" 2>/dev/null || true
  		elif [ -n "$chosen_win" ]; then
  			tmux select-window -t "$chosen_win" 2>/dev/null || true
  			set_state "$STATE_PREVIEW_WIN_ID" "$chosen_win"
  		else
  			[ -n "$orig_window" ] && tmux select-window -t "$orig_window" 2>/dev/null || true
  			[ -n "$orig_window" ] && set_state "$STATE_PREVIEW_WIN_ID" "$orig_window"
  		fi
  		return 0

Task 5: EDIT scripts/preview.sh — src_id resolution: chosen_win branch (item c)
  - FILE: ./scripts/preview.sh.
  - oldText:
  	if [ "$(opt_type)" = "window" ] && [ "${S%%:*}" != "$S" ]; then
  		w_sess="${S%%:*}"
  		w_idx="${S#*:}"
  		src_id="$(tmux list-windows -t "=$w_sess" -F '#{window_id}:#{window_index}' 2>/dev/null | awk -F: -v idx="$w_idx" '$2==idx {print $1; exit}')"
  	else
  		src_id="$(tmux list-windows -t "=$S" -F '#{window_id}' -f '#{window_active}' 2>/dev/null)"
  	fi
  - newText (add the elif [ -n "$chosen_win" ] branch for session mode):
  	if [ "$(opt_type)" = "window" ] && [ "${S%%:*}" != "$S" ]; then
  		w_sess="${S%%:*}"
  		w_idx="${S#*:}"
  		src_id="$(tmux list-windows -t "=$w_sess" -F '#{window_id}:#{window_index}' 2>/dev/null | awk -F: -v idx="$w_idx" '$2==idx {print $1; exit}')"
  	elif [ -n "$chosen_win" ]; then
  		# P2.M1.T2: session mode + a FLIPPED window — use the supplied window-id
  		# directly (skip the active-window lookup). chosen_win is a server-global @id
  		# (select-window -t "@id" verified — research FINDING 2). Only session mode
  		# supplies chosen_win; window mode is handled by the branch above.
  		src_id="$chosen_win"
  	else
  		src_id="$(tmux list-windows -t "=$S" -F '#{window_id}' -f '#{window_active}' 2>/dev/null)"
  	fi

Task 6: EDIT scripts/preview.sh — idempotent pre-link check: ALSO write STATE_PREVIEW_WIN_ID (item e)
  - FILE: ./scripts/preview.sh.
  - oldText:
  		tmux select-window -t "$src_id" 2>/dev/null || true
  		set_state "$STATE_LINKED_ID" "$src_id"
  		return 0
  	fi
  - newText:
  		tmux select-window -t "$src_id" 2>/dev/null || true
  		set_state "$STATE_LINKED_ID" "$src_id"
  		set_state "$STATE_PREVIEW_WIN_ID" "$src_id"   # P2.M1.T2: logical shown window (== LINKED_ID non-self)
  		return 0
  	fi
  - GOTCHA: this oldText appears in the idempotent check (the `grep -Fxq` block). The
    final-commit block (Task 7) is textually distinct (it has the preceding GUARD 3).

Task 7: EDIT scripts/preview.sh — final commit: ALSO write STATE_PREVIEW_WIN_ID (item e)
  - FILE: ./scripts/preview.sh.
  - oldText:
  	# Track the linked id (handle for the next unlink + for restore P1.M5).
  	set_state "$STATE_LINKED_ID" "$src_id"
  	return 0
  - newText:
  	# Track the linked id (handle for the next unlink + for restore P1.M5) AND the
  	# logical shown window (P2.M1.T2: STATE_PREVIEW_WIN_ID overlaps STATE_LINKED_ID
  	# for non-self candidates; both = src_id here).
  	set_state "$STATE_LINKED_ID" "$src_id"
  	set_state "$STATE_PREVIEW_WIN_ID" "$src_id"
  	return 0

Task 8: EDIT scripts/preview.sh — preview_fallback: accept chosen_win, build =$S:$chosen_win. (item f)
  - FILE: ./scripts/preview.sh.
  - oldText:
  	local captured target
  	if [ "$(opt_type)" = "window" ] && [ "${1%%:*}" != "$1" ]; then
  - newText:
  	local captured target chosen="${2:-}"
  	if [ -n "$chosen" ]; then
  		# P2.M1.T2: session mode + flipped window -> capture THAT window's active pane.
  		# "=session:@id." is a valid target (rc=0 verified — research FINDING 3).
  		target="=$1:$chosen."
  	elif [ "$(opt_type)" = "window" ] && [ "${1%%:*}" != "$1" ]; then
  - NOTE: preview_fallback is now called as `preview_fallback "$S" "$chosen_win"`
    (Task 3). The existing window-mode + session-default branches are UNCHANGED
    (chosen="" for them). Keep the trailing `captured="$(tmux capture-pane -ep ...)"` line.

Task 9: EDIT scripts/input-handler.sh — _lp_fire_preview: +WIN_ID arg, 3-arg run-shell (item a)
  - FILE: ./scripts/input-handler.sh.
  - oldText:
  _lp_fire_preview() {
  	local target="${1:-}" seq
  	[ -z "$target" ] && return 0
  	seq="$(get_state "$STATE_PREVIEW_SEQ" "0")"
  	seq=$(( seq + 1 ))
  	set_state "$STATE_PREVIEW_SEQ" "$seq"
  	set_state "$STATE_PREVIEW_TARGET" "$target"
  	# Absolute path (the server's cwd is NOT the plugin dir); bash shebang honored
  	# under run-shell (Q5). Single-quote the target so session names with spaces
  	# survive (matches the key-binding run-shell form, livepicker.sh:326).
  	tmux run-shell -b "$CURRENT_DIR/preview.sh '$target' '$seq'"
  }
  - newText:
  _lp_fire_preview() {
  	local target="${1:-}" win_id="${2:-}" seq
  	[ -z "$target" ] && return 0
  	seq="$(get_state "$STATE_PREVIEW_SEQ" "0")"
  	seq=$(( seq + 1 ))
  	set_state "$STATE_PREVIEW_SEQ" "$seq"
  	set_state "$STATE_PREVIEW_TARGET" "$target"
  	# Absolute path (the server's cwd is NOT the plugin dir); bash shebang honored
  	# under run-shell (Q5). Single-quote each arg so session names with spaces
  	# survive. THREE positional args now (P2.M1.T2): $1=session, $2=chosen window-id
  	# (empty for session-nav -> preview.sh chosen_win="" -> chosen-win branches
  	# skipped, byte-identical session-nav), $3=seq. (run-shell form: livepicker.sh.)
  	tmux run-shell -b "$CURRENT_DIR/preview.sh '$target' '$win_id' '$seq'"
  }

Task 10: EDIT scripts/input-handler.sh — _lp_preview_dispatch: +WIN_ID arg, thread to fire + inline (item a)
  - FILE: ./scripts/input-handler.sh.
  - oldText:
  _lp_preview_dispatch() {
  	local target="${1:-}"
  	if [ "$(opt_preview_defer)" = "on" ]; then
  		_lp_fire_preview "$target"
  	else
  		[ -n "$target" ] && { "$CURRENT_DIR/preview.sh" "$target" 2>/dev/null || true; }
  	fi
  }
  - newText:
  _lp_preview_dispatch() {
  	local target="${1:-}" win_id="${2:-}"
  	if [ "$(opt_preview_defer)" = "on" ]; then
  		_lp_fire_preview "$target" "$win_id"
  	else
  		# Inline (defer=off): pass target + win_id (no seq -> preview.sh seq guards
  		# skipped, as before). win_id empty for session-nav -> chosen_win="" -> unchanged.
  		[ -n "$target" ] && { "$CURRENT_DIR/preview.sh" "$target" "$win_id" 2>/dev/null || true; }
  	fi
  }

Task 11: UPDATE preview.sh header argv comment (docs accuracy)
  - FILE: ./scripts/preview.sh (the top-of-file comment block).
  - oldText:
  # argv[1] = candidate session name S. Links S's active window into the CURRENT
  # (driver) session and selects it, so all its panes render live below the status
  # bar — WITHOUT switching the client's session (Invariant A: select-window does
  # NOT fire client-session-changed). Tracks the linked window id in
  # @livepicker-linked-id for unlinking on the next navigation and on restore.
  - newText:
  # argv[1] = candidate session name S (or "session:index" token in window mode).
  # argv[2] = chosen window-id (session-mode flip target; "" for session-nav/first preview).
  # argv[3] = deferred-preview supersede seq ("" for inline calls -> seq guards skipped).
  # Links S's active window — or the chosen window (argv[2]) when supplied — into the
  # CURRENT (driver) session and selects it, so all its panes render live below the
  # status bar — WITHOUT switching the client's session (Invariant A: select-window
  # does NOT fire client-session-changed). Tracks the linked window id in
  # @livepicker-linked-id (non-self) and the logical shown window in
  # @livepicker-preview-win-id, for unlinking on the next navigation and on restore.

Task 12: VALIDATE (L1 grep + L2 suite + L3 chosen-window spot-check + L4 self-session flip)
  - RUN: bash -n scripts/preview.sh scripts/input-handler.sh ; shellcheck both.
  - RUN: grep cross-checks (signature, chosen_win branches, PREVIEW_WIN_ID writes, 3-arg run-shell).
  - RUN: tests/run.sh (expect GREEN — no regression; session-nav unchanged).
  - RUN: L3 chosen-window inline spot-check (seed state, call preview.sh S @id, assert link).
  - RUN: L4 self-session flip spot-check (driver session + chosen_win, assert select, no link).
```

### Implementation Patterns & Key Details

```bash
# === The ONE binding edit that repoints all 3 seq guards (FINDING 1) ===
# BEFORE:  local S="${1:-}" expected_seq="${2:-}"
# AFTER:   local S="${1:-}" chosen_win="${2:-}" expected_seq="${3:-}"
# The guards (~91/210/253) all read the LOCAL `expected_seq` — they now see $3.
# Do NOT touch the guard blocks.

# === src_id resolution: chosen_win short-circuits the active-window lookup (item c) ===
if [ "$(opt_type)" = "window" ] && [ "${S%%:*}" != "$S" ]; then
    ...  # window-mode token logic (UNCHANGED)
elif [ -n "$chosen_win" ]; then
    src_id="$chosen_win"          # session-mode flip: use the supplied @id directly
else
    src_id="$(tmux list-windows -t "=$S" -F '#{window_id}' -f '#{window_active}' ...)"  # default
fi

# === Self-session flip (item d): select the flipped driver window (no link) ===
if [ "$(opt_type)" = "window" ]; then
    tmux select-window -t "$S" 2>/dev/null || true          # flat picker (unchanged)
elif [ -n "$chosen_win" ]; then
    tmux select-window -t "$chosen_win" 2>/dev/null || true  # P2.M1.T2 flip (bare @id — FINDING 2)
    set_state "$STATE_PREVIEW_WIN_ID" "$chosen_win"
else
    [ -n "$orig_window" ] && tmux select-window -t "$orig_window" 2>/dev/null || true
    [ -n "$orig_window" ] && set_state "$STATE_PREVIEW_WIN_ID" "$orig_window"
fi

# === STATE_PREVIEW_WIN_ID writes (items d/e): co-written with STATE_LINKED_ID on non-self ===
# idempotent check + final commit (non-self): set BOTH (== src_id):
set_state "$STATE_LINKED_ID" "$src_id"; set_state "$STATE_PREVIEW_WIN_ID" "$src_id"
# self-session: set ONLY PREVIEW_WIN_ID (chosen_win or ORIG_WINDOW); LINKED_ID stays empty.

# === input-handler threading (item a): win_id="" for every current caller ===
_lp_fire_preview()  { local target="${1:-}" win_id="${2:-}" seq; ...; tmux run-shell -b "$CURRENT_DIR/preview.sh '$target' '$win_id' '$seq'"; }
_lp_preview_dispatch() { local target="${1:-}" win_id="${2:-}"; ... defer=off: "$CURRENT_DIR/preview.sh" "$target" "$win_id" ...; }
```

### Integration Points

```yaml
PREVIEW (preview.sh):
  - signature $1/$2/$3; chosen-win src_id branch; self-session flip; PREVIEW_WIN_ID writes;
    snapshot chosen-window capture. All leave-no-trace (driver-only link/select).

INPUT-HANDLER (input-handler.sh):
  - _lp_fire_preview + _lp_preview_dispatch accept [WIN_ID]; 3-arg run-shell; inline 2-arg.
  - EXISTING callers (_lp_sync_preview_to_top_match, next/prev-session) UNCHANGED (1 arg -> win_id="").

STATE (state.sh):
  - NO CHANGE. STATE_PREVIEW_WIN_ID (@livepicker-preview-win-id) ALREADY defined+init'd ""
    at activate + in _STATE_RUNTIME_KEYS (P2.M1.T1.S1). This task only WRITES it.

ACTIVATE (livepicker.sh): NO CHANGE. The first-preview call (line 523,
  "$CURRENT_DIR/preview.sh" "$orig_session") passes 1 arg -> chosen_win="", seq=""
  -> unchanged + now also sets STATE_PREVIEW_WIN_ID=ORIG_WINDOW on the self path (item d).

CONSUMERS (FUTURE — do not implement here):
  - P2.M1.T3: next-window/prev-window call _lp_preview_dispatch "$target" "$win_id".
  - P2.M2.T1: confirm resolves (S, W) from STATE_CAND_WIN_CURSOR.

CONFIG / DATABASE / ROUTES: none.
```

## Validation Loop

### Level 1: Syntax & Style (Immediate Feedback)

```bash
cd /home/dustin/.config/tmux/plugins/tmux-livepicker
bash -n scripts/preview.sh scripts/input-handler.sh && echo "OK: syntax"   # exit 0
shellcheck scripts/preview.sh scripts/input-handler.sh                     # 0 findings
# The new signature:
grep -c 'local S="\${1:-}" chosen_win="\${2:-}" expected_seq="\${3:-}"' scripts/preview.sh   # == 1
# chosen_win src_id branch present:
grep -c 'elif \[ -n "\$chosen_win" \]' scripts/preview.sh                                    # == 1
# STATE_PREVIEW_WIN_ID written (3 sites: self-session chosen, self-session orig, idempotent, commit = >=3):
grep -c 'set_state "\$STATE_PREVIEW_WIN_ID"' scripts/preview.sh                              # >= 3
# 3-arg run-shell + win_id threading in input-handler:
grep -c "preview.sh '\$target' '\$win_id' '\$seq'" scripts/input-handler.sh                   # == 1
grep -c '_lp_fire_preview "\$target" "\$win_id"' scripts/input-handler.sh                    # == 1
# Expected: all match; tabs only (no 4-space indent on new lines).
grep -Pn '^    [^#/]' scripts/preview.sh scripts/input-handler.sh | tail && echo "WARN: space-indent" || echo "OK: tabs"
```

### Level 2: Full suite (no regression — session-nav unchanged)

```bash
cd /home/dustin/.config/tmux/plugins/tmux-livepicker
tests/run.sh
# Expected: exit 0, all green. Every current caller passes 1 arg (target) -> win_id=""
# -> preview.sh chosen_win="" -> all chosen-win branches skipped -> byte-identical
# session-nav/type/backspace/cancel. The only additive side-effect is the extra
# STATE_PREVIEW_WIN_ID write (read by no current consumer; cleared by _STATE_RUNTIME_KEYS).
```

### Level 3: Chosen-window preview (inline, non-self) — the new capability

```bash
cat > /tmp/smoke_chosenwin.sh <<'EOF'
#!/usr/bin/env bash
set -u
cd /home/dustin/.config/tmux/plugins/tmux-livepicker
source tests/setup_socket.sh; source tests/helpers.sh
setup_test "lp-chosenwin"; attach_test_client
fail=0
# alpha gets a SECOND window; the picker's driver is the 'driver' session fixture.
tmux new-window -t "alpha:" -n secondwin
alpha2="$(tmux list-windows -t =alpha -F '#{window_id} #{window_name}' | awk '$2=="secondwin"{print $1}')"
echo "alpha secondwin @id=$alpha2"
# Seed minimal picker state (mirror activate): driver is ORIG_SESSION, mode on, no link yet.
tmux set-option -g @livepicker-orig-session driver
tmux set-option -g @livepicker-orig-window "$(tmux list-windows -t =driver -F '#{window_id}' -f '#{window_active}')"
tmux set-option -g @livepicker-linked-id ""
tmux set-option -g @livepicker-preview-win-id ""
# Call preview.sh INLINE for alpha's SECOND window (the chosen window): preview.sh alpha <@id>
"$LIVEPICKER_SCRIPTS/preview.sh" alpha "$alpha2"
lid="$(tmux show-option -gqv @livepicker-linked-id)"
pid="$(tmux show-option -gqv @livepicker-preview-win-id)"
echo "linked-id=[$lid] preview-win-id=[$pid] (expect both == $alpha2)"
[ "$lid" = "$alpha2" ] && echo "OK: linked the chosen window" || { echo "FAIL linked [$lid]"; fail=1; }
[ "$pid" = "$alpha2" ] && echo "OK: preview-win-id == chosen" || { echo "FAIL pid [$pid]"; fail=1; }
# alpha's OWN active window must be UNCHANGED (leave-no-trace / Invariant B):
aact="$(tmux list-windows -t =alpha -F '#{window_name}' -f '#{window_active}')"
echo "alpha active after preview: [$aact] (must be alpha's original active, NOT secondwin)"
# cleanup the link so teardown is clean
tmux unlink-window -t "driver:$alpha2" 2>/dev/null || true
teardown_test
[ "$fail" -eq 0 ]
EOF
bash /tmp/smoke_chosenwin.sh; rc=$?; rm -f /tmp/smoke_chosenwin.sh; exit $rc
# Expected: linked-id == preview-win-id == alpha's secondwin @id; alpha's own active window
# unchanged (leave-no-trace). Proves the chosen-window link flow + the PREVIEW_WIN_ID write.
```

### Level 4: Self-session flip (chosen driver window, no link)

```bash
cat > /tmp/smoke_selfflip.sh <<'EOF'
#!/usr/bin/env bash
set -u
cd /home/dustin/.config/tmux/plugins/tmux-livepicker
source tests/setup_socket.sh; source tests/helpers.sh
setup_test "lp-selfflip"; attach_test_client
fail=0
# Give the driver a second window; flip to it.
tmux new-window -t "driver:" -n drv2
drv2="$(tmux list-windows -t =driver -F '#{window_id} #{window_name}' | awk '$2=="drv2"{print $1}')"
orig="$(tmux list-windows -t =driver -F '#{window_id}' -f '#{window_active}')"
tmux set-option -g @livepicker-orig-session driver
tmux set-option -g @livepicker-orig-window "$orig"
tmux set-option -g @livepicker-linked-id "X"          # pretend a prior cross-session link
tmux set-option -g @livepicker-preview-win-id ""
# Self-session flip: preview.sh driver <drv2> (S == current_session, chosen_win non-empty)
"$LIVEPICKER_SCRIPTS/preview.sh" driver "$drv2"
lid="$(tmux show-option -gqv @livepicker-linked-id)"
pid="$(tmux show-option -gqv @livepicker-preview-win-id)"
shown="$(tmux list-windows -t =driver -F '#{window_name}' -f '#{window_active}')"
echo "linked-id=[$lid] (must be EMPTY — no link for self) preview-win-id=[$pid] shown=[$shown]"
[ -z "$lid" ] && echo "OK: no link for self-session flip" || { echo "FAIL linked [$lid]"; fail=1; }
[ "$pid" = "$drv2" ] && echo "OK: preview-win-id == flipped driver window" || { echo "FAIL pid [$pid]"; fail=1; }
[ "$shown" = "drv2" ] && echo "OK: driver active moved to flipped window" || { echo "FAIL shown [$shown]"; fail=1; }
teardown_test
[ "$fail" -eq 0 ]
EOF
bash /tmp/smoke_selfflip.sh; rc=$?; rm -f /tmp/smoke_selfflip.sh; exit $rc
# Expected: linked-id EMPTY (no link for self); preview-win-id == drv2 @id; the driver's
# active window moved to drv2 (flip moves it while browsing; cancel's hard reset undoes it).
```

## Final Validation Checklist

### Technical Validation

- [ ] `bash -n` + `shellcheck` clean on `scripts/preview.sh` + `scripts/input-handler.sh`.
- [ ] preview.sh signature binds `chosen_win="${2:-}"` + `expected_seq="${3:-}"`.
- [ ] 3 seq guards supersede on the `expected_seq` local (now from `$3`) — unchanged bodies.
- [ ] chosen_win src_id branch; self-session flip; 3+ STATE_PREVIEW_WIN_ID writes; 3-arg run-shell.
- [ ] Tabs only (no 4-space indent on new lines).

### Feature Validation

- [ ] Chosen-window inline preview links THAT window; linked-id == preview-win-id == @id (L3).
- [ ] Leave-no-trace: the candidate's own active window is unchanged (L3).
- [ ] Self-session flip selects the driver window (no link); linked-id empty; preview-win-id set (L4).
- [ ] Session-nav unchanged: `tests/run.sh` GREEN (L2); win_id="" → chosen-win branches skipped.

### Code Quality Validation

- [ ] chosen_win branch is SESSION-MODE only (window-mode token logic untouched).
- [ ] STATE_PREVIEW_WIN_ID co-written with STATE_LINKED_ID on non-self; self writes only it.
- [ ] snapshot passes chosen_win to preview_fallback; off is a no-op; neither writes PREVIEW_WIN_ID.
- [ ] Existing `_lp_preview_dispatch`/`_lp_fire_preview` callers unchanged (win_id defaults "").

### Documentation & Deployment

- [ ] No README/CHANGELOG edit (DOCS = none; the window-flip surface is Mode A'd in P2.M1.T3.S1).
- [ ] No new test file (the window-flip suite is P2.M3.T1.S1).
- [ ] preview.sh header argv comment + GUARD-1 comment updated for the new $2/$3 positions.

---

## Anti-Patterns to Avoid

- ❌ Don't hand-edit the 3 seq guards. They reference the LOCAL `expected_seq`; change the
  BINDING (`expected_seq="${3:-}"`) and all 3 inherit it. Editing the guards is 3x churn for
  zero difference. (FINDING 1.)
- ❌ Don't change the existing `_lp_preview_dispatch`/`_lp_fire_preview` callers (sync,
  next/prev-session). They pass 1 arg → `win_id=""` → preview.sh `chosen_win=""` → all
  chosen-win branches skipped → byte-identical session-nav. P2.M1.T3 is the first real caller.
  (FINDING 4/10.)
- ❌ Don't write STATE_PREVIEW_WIN_ID in snapshot/off mode. Snapshot just captures (pass
  chosen_win to preview_fallback); off is a no-op. Mode is constant per picker lifetime.
  (FINDING 7.)
- ❌ Don't set STATE_LINKED_ID on the self-session flip path. Nothing is linked for self;
  linked-id must stay empty. Set ONLY STATE_PREVIEW_WIN_ID there. (FINDING 6.)
- ❌ Don't forget the idempotent pre-link check when writing STATE_PREVIEW_WIN_ID. It sets
  LINKED_ID=src_id AND shows src_id → preview-win-id must also = src_id (else they diverge
  for non-self, where they must overlap). Write BOTH at the idempotent check AND the final
  commit. (FINDING 6, item e.)
- ❌ Don't touch the window-mode (flat picker) src_id branch or the duplicate guard. The
  chosen_win branch is SESSION-MODE only; the duplicate guard already has correct tracking
  (linked_id == src_id → preview-win-id already == src_id from the prior call). (FINDING 5/6.)
- ❌ Don't change livepicker.sh's first-preview call (line 523). It passes 1 arg → under the
  new signature chosen_win="" + seq="" → unchanged (and now also sets PREVIEW_WIN_ID=ORIG_WINDOW
  on the self path, which is correct). (FINDING 4.)
- ❌ Don't add a guard to "protect the candidate" for chosen-window previews. Leave-no-trace
  is preserved by construction: unlink/link/select always target `$current_session` (the
  driver). chosen_win only changes which @id is resolved as src_id. (FINDING 9.)
- ❌ Don't use spaces for indent — TABS only (both files are tab-indented; a space oldText
  won't match).
- ❌ Don't add a flip-action test here. The window-flip test suite is P2.M3.T1.S1; this task's
  validation is the chosen-window inline spot-check (L3) + self-session flip (L4) + suite-green (L2).

---

## Confidence Score

**9 / 10** for one-pass success. Rationale: every edit is anchored on verbatim current
content (oldText quoted from the file); the load-bearing insight (FINDING 1: one binding
edit repoints all 3 guards) eliminates the highest-churn risk; the two new mechanics (bare
`@id` select, `=session:@id.` capture) are verified rc=0 on 3.6b; the change is backward-
compatible by construction (win_id="" for every current caller); and the only additive
state write (STATE_PREVIEW_WIN_ID) is read by no current consumer and cleared by the
already-wired `_STATE_RUNTIME_KEYS`. Residual risk: the snapshot chosen-window target
`=session:@id.` is verified valid (rc=0) but its captured *content* depends on the pane
being live — harmless (snapshot is a degraded fallback). The `bash -n`/`shellcheck` +
full-suite-green + L3/L4 spot-checks are the firm gates.
