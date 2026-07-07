# PRP — Bugfix P1.M1.T2.S1: Extend self-session guard in preview.sh for window mode

> **Context**: Issue 2 from the rev-002 QA pass
> (`plan/002_facc52335e68/bugfix/001_c7c6203f3e28/architecture/issue1_2_findings.md` §Issue 2,
> Major). In window mode, previewing a window that belongs to the driver (current) session
> silently creates a DUPLICATE window link, because the self-session guard compares the bare
> `session:index` token to the session name and never matches. This pollutes the driver's
> window list, shifts indices (compounding Issue 1), and makes later navigation resolve the
> wrong window. This PRP extends the guard to window mode.

---

## Goal

**Feature Goal**: `preview.sh`'s self-session guard fires for driver-owned windows in
**window mode** (where `$S` is a `"session:index"` token), so previewing one's own window
selects it instead of creating a silent duplicate link. The guard continues to behave
identically in session mode (zero regression).

**Deliverable**: Two small edits to `scripts/preview.sh` — **no new files**.
1. Add `check_session` to the `preview_main` locals (line 82).
2. Replace the self-session guard block (lines 121-134) with a window-mode-aware version:
   compute `check_session` via `${S%%:*}` extraction, use it in the condition, and branch
   the final `select-window` (window mode → `select-window -t "$S"`; session mode →
   `select-window -t "$orig_window"` as before). Update the inline comment.

**Success Definition**:
- In window mode, `preview.sh "driver:1"` (a driver-owned window) does NOT create a
  duplicate link; `@livepicker-linked-id` is cleared; window 1 is selected. (FAILS today —
  a duplicate `@id` appears and `linked-id` tracks it.)
- In session mode, `preview.sh "driver"` behaves exactly as before (selects `ORIG_WINDOW`,
  no link, clears `linked-id`). Zero regression.
- A foreign window (`preview.sh "alpha:0"`) still falls through to the normal link path
  (guard does NOT fire for non-driver sessions).
- `bash -n` + `shellcheck` clean; the full `tests/run.sh` suite stays green (the change is
  confined to the self-session block; every existing session-mode test is unaffected).

## User Persona (if applicable)

**Target User**: Window-mode users browsing their own session's windows. Not directly
end-facing (it's a correctness fix). Mode A — internal fix, comment-only docs.

**Use Case**: A user sets `@livepicker-type window`, activates the picker, and navigates
onto one of the driver's own windows (`driver:1`). The preview should show that window's
panes (by selecting it), NOT spawn a phantom duplicate that corrupts their window list.

**Pain Points Addressed**: Silent window-list corruption (duplicate + index shift) on a
common window-mode action; later navigation resolving the wrong window because the duplicate
occupies a shifted index.

---

## Why

- **State-corruption bug on a reachable path.** Window mode + navigating onto a driver-owned
  window creates a duplicate every time. The duplicate pollutes the list, shifts indices
  (Issue 1, now fixed for foreign previews but re-introduced by the duplicate here), and
  breaks subsequent `"session:index"` resolution. PRD §7 mandates "do not link ... select the
  original window" for the current session — the guard must honor that in window mode too.
- **One-token root cause, one-token fix.** The guard compares `"driver:1" = "driver"` which
  is always false. `${S%%:*}` extracts `"driver"` — an idiom already used 3× in the same
  file (lines 62, 144, 146). The fix is minimal, proven, and backward-compatible.
- **Closes a test gap (T2.S2).** No existing test exercises the self-session guard in window
  mode (`test_self_session_no_link` only calls session mode). This fix + the T2.S2 test make
  the class durable. (This PRP is the code fix; the committed test is the sibling T2.S2.)

## What

Two edits to `scripts/preview.sh`:
1. **Locals (line 82)**: append `check_session` to the `local` declaration.
2. **Self-session guard (lines 121-134)**: before the condition, compute `check_session`
   (in window mode, `${S%%:*}` extracts the session from the `"session:index"` token; in
   session mode it's the identity). Change `[ "$S" = "$current_session" ]` to
   `[ "$check_session" = "$current_session" ]`. In the body, branch the final `select-window`:
   window mode → `select-window -t "$S"` (selects the specific highlighted window); session
   mode → `select-window -t "$orig_window"` (unchanged). The unlink-prior-preview +
   clear-LINKED_ID steps stay identical. Update the comment.

### Success Criteria

- [ ] `check_session` declared in `preview_main` locals; computed before the guard.
- [ ] Guard condition uses `$check_session` (not bare `$S`).
- [ ] Window-mode self-session → `select-window -t "$S"`; session-mode → `select-window -t "$orig_window"`.
- [ ] `bash -n` + `shellcheck` clean on preview.sh; `tests/run.sh` green (no regression).
- [ ] Throwaway smoke: `preview.sh "driver:1"` in window mode leaves NO duplicate + selects
      window 1 + clears linked-id (L2).
- [ ] Bug-reintroduction check: reverting to `[ "$S" = ... ]` re-creates the duplicate (L3).

## All Needed Context

### Context Completeness Check

_Pass_: The implementer needs (a) the verbatim replacement block (below), (b) the exact
content anchors (line numbers are stable here — S1 already landed and only T1.S2's test-only
work runs in parallel, which does not touch preview.sh), and (c) the empirical proof that
`select-window -t "$S"` works and indices are snapshot-stable. No inference required.

### Documentation & References

```yaml
# MUST READ — the empirical ground-truth (proves the fix + corrects one findings claim)
- docfile: plan/002_facc52335e68/bugfix/001_c7c6203f3e28/P1M1T2S1/research/self_session_window_mode_findings.md
  why: PROVES the fix end-to-end on an isolated socket. FINDING 1 (the shipped bare link-window
       WORKS — overturns the findings doc's "would fail rc=1" warning; foundation solid);
       FINDING 2 (${S%%:*} guard); FINDING 3 (select-window -t "$S" works + why it's safe vs
       the @id invariant); FINDING 4 (duplicate bug confirmed); FINDING 5 (full e2e simulation).
  critical: Read BEFORE editing. The issue1_2_findings.md researcher had no shell; this file is
            the verified ground-truth.

# MUST READ — the bug report (root cause + repro)
- docfile: plan/002_facc52335e68/bugfix/001_c7c6203f3e28/architecture/issue1_2_findings.md
  why: §ISSUE 2 gives the root cause (line 126 bare comparison; "driver:1" != "driver"), the
       duplicate-creation mechanism, and the exact suggested fix (${S%%:*}). Notes the idiom is
       already used at lines 62/144/146 of the same file.
  critical: the findings doc's §ISSUE 1 "bare link-window fails rc=1" warning is WRONG (corrected
            by research FINDING 1 above — it works). Do NOT "fix" the bare link-window call; it
            is correct (S1, Complete).

# MUST READ — the file being modified
- file: scripts/preview.sh
  why: preview_main (line 80); locals (line 82); self-session guard (lines 121-134); the
        window-mode src_id resolution (lines 144-149 — AFTER the guard, unchanged); the bare
        link-window call (line 187 — S1's fix, unchanged). sources options/utils/state (44/46/48).
  pattern: the ${S%%:*} idiom is used at line 62 (preview_fallback), 144 (w_sess), 146 (detection).
  gotcha: the guard is AFTER the top seq guard (90-94) and returns before the 2nd seq re-check
          (166) — do NOT add a seq check inside the self-session block (matches session-mode).

# Reference — the sibling test task (what guards this fix; do NOT implement here)
- docfile: plan/002_facc52335e68/bugfix/001_c7c6203f3e28/P1M1T1S2/PRP.md
  why: Documents the test-harness contract (attach_test_client, assert_eq, run.sh auto-discovery,
        base-index=1 => new-window -a). T2.S2 (the window-mode self-session test) will mirror
        test_self_session_no_link but call preview.sh "driver:1". This PRP is the CODE FIX only.
  section: "Known Gotchas" (base-index=1; assert via fail/assert_*; never exit from a test body)

# Reference — PRD §7 (the self-session rule this enforces)
- docfile: PRD.md
  why: §7 "When the highlighted session is the current session, do not link ... Select the
       original window" — the rule the guard implements, now extended to window mode.
  section: "§7 The preview subsystem" (Self-session edge case)
```

### Current Codebase tree

```bash
tmux-livepicker/
  scripts/
    preview.sh   # MODIFY: +check_session local; rewrite self-session guard block (lines 121-134) for window mode
    ...          # (all other scripts unchanged; S1's bare link-window at line 187 stays)
  tests/         # UNCHANGED here (the window-mode self-session test is T2.S2; validate via throwaway smoke)
```

### Desired Codebase tree with files to be added and responsibility of file

```bash
scripts/preview.sh   # self-session guard now fires for driver-owned windows in window mode;
                      #   selects the specific window instead of creating a duplicate link
```

### Known Gotchas of our codebase & Library Quirks

```bash
# CRITICAL — the guard comparison must use $check_session (the extracted session), NOT bare $S.
# In window mode $S is "driver:1" which never equals "driver" (the bug). ${S%%:*} extracts
# "driver". tmux session names CANNOT contain colons (':' is the session:window separator),
# so ${S%%:*} is always exactly the session name. Session-mode ($S has no colon) is the
# identity -> zero regression. (research FINDING 2.)

# CRITICAL — the self-session block must SELECT the specific window in window mode, not
# ORIG_WINDOW. The user is browsing the driver's OWN windows; previewing driver:2 should
# SELECT window 2 (show its panes), not snap back to ORIG_WINDOW. Use select-window -t "$S"
# (the "session:index" token works directly — verified rc=0). (research FINDING 3.)

# CRITICAL — do NOT change the unlink-prior-preview / clear-LINKED_ID steps in the block.
# When a cross-session preview (e.g. alpha:0) was shown before navigating onto a driver
# window, that prior linked window MUST still be unlinked + linked-id cleared. Only the
# final select-window line branches on opt_type.

# CRITICAL — the bare link-window call at line 187 (S1's fix) is CORRECT; do NOT re-add -a
# or otherwise touch it. issue1_2_findings.md's warning that bare link-window "fails rc=1"
# was WRONG (research FINDING 1: it appends at the END, rc=0). The non-self path's foundation
# is solid; this fix only adds an early-return for driver-owned windows so they never reach
# that call.

# CRITICAL — do NOT add a deferred-preview seq check inside the self-session block. The top
# seq guard (lines 90-94) already ran; the block returns 0 before the 2nd re-check (line 166).
# This matches the EXISTING session-mode self-session behavior (unlink+select, no 2nd check).
# Adding one here would diverge from the session-mode path for no benefit. (research FINDING 6.)

# GOTCHA — ${S%%:*} vs ${S%%:*}. Use %% (longest suffix match) not % (shortest). For
# "driver:1", both yield "driver" (only one colon), but %% is the codebase's idiom (lines 62,
# 144) and is correct for pathological multi-colon strings. Match the siblings: %% .

# GOTCHA — select-window -t "$S" is safe despite the codebase "@id, never index" invariant
# (header line 30). That invariant guards vs renumber-windows staleness, but the self-session
# guard fires for the DRIVER's OWN windows whose index comes from the SNAPSHOTTED picker list;
# no driver window is closed during the picker -> indices are stable -> $S's index is valid.
# (research FINDING 3.) The @id approach (resolve src_id before the guard) was considered and
# rejected: bigger diff, duplicates the resolution logic, no gain.

# GOTCHA — preview.sh runs under `set -u` (inherited). `check_session` MUST be declared `local`
# (add to line 82). Initialize it to "$S" so the window-mode branch only overrides when needed.
# Do NOT use `local check_session="$(cmd)"` (SC2155); `local check_session="$S"` is fine (no
# command substitution, matches line 81's `local S="${1:-}"` style).

# GOTCHA — every tmux call in the block stays best-effort (`2>/dev/null || true`), matching
# the existing lines. select-window on a vanished window returns non-zero; swallow it.

# GOTCHA — Indent with TABS (the file is tab-indented; shfmt is NOT installed). The guard
# block lives inside preview_main at 1-tab indent; the body is 2-tab; nested ifs are 3-tab.

# GOTCHA — do NOT touch the window-mode src_id resolution (lines 144-149), the duplicate
# guard (160), or the link flow (166+). They are correct and only reached when the guard
# does NOT fire (foreign session/window). This fix is confined to the self-session block.
```

## Implementation Blueprint

### Data models and structure

No data-model change. The "model" is the self-session detection + selection flow, now
mode-aware:

```
preview_main(S, [expected_seq]):
  read current_session, orig_window, linked_id
  [seq guard / mode gate unchanged]
  compute check_session:  S  (session mode)  |  ${S%%:*}  (window mode, "session:index" token)
  if check_session == current_session:    # self-session (BOTH modes now)
      unlink prior cross-session preview (linked_id) + clear STATE_LINKED_ID
      window mode? -> select-window -t "$S"        (the specific highlighted window)
      session mode? -> select-window -t "$orig_window"   (unchanged)
      return 0   # NO link -> NO duplicate
  [resolve src_id / duplicate guard / link flow unchanged — reached only for foreign targets]
```

### Implementation Tasks (ordered by dependencies)

```yaml
PRECONDITION: S1 (P1.M1.T1.S1) is applied — preview.sh:187 is the BARE link-window (no -a).
  Verify: grep -n 'link-window' scripts/preview.sh  # expect NO -a. (S1 is Complete; stable.)

Task 1: MODIFY scripts/preview.sh — add check_session to the locals
  - LOCATE (line 82): `local current_session orig_window linked_id src_id w_sess w_idx cur_seq`
  - ACTION: append `check_session` to that local list.
  - oldText/newText: see Implementation Patterns (Edit 1).

Task 2: MODIFY scripts/preview.sh — rewrite the self-session guard block
  - LOCATE (lines 120-134): the comment + `if [ -n "$current_session" ] && [ "$S" = ...`
    through the closing `fi` (before the "Resolve the candidate window id" comment at ~136).
  - ACTION: replace the whole block with the window-mode-aware version (compute check_session;
    use it in the condition; branch the select-window). Update the comment to document the
    window-mode extension + the ${S%%:*} extraction.
  - oldText/newText: see Implementation Patterns (Edit 2). Anchor: the block is unique
    (the `unlink-window -t "$current_session:$linked_id"` + `tmux_unset_opt` + the
    `[ "$S" = "$current_session" ]` condition appear only here).
  - DO NOT touch: the mode gate, the seq guards, the src_id resolution, the duplicate guard,
    the link flow, or any other file. The deferred-preview path is unchanged (research FINDING 6).

Task 3: VALIDATE (throwaway smoke + full suite)
  - RUN: bash -n scripts/preview.sh ; shellcheck scripts/preview.sh (expect 0 NEW findings)
  - RUN: the throwaway smoke (Validation L2) — window-mode self-session (driver:1) leaves NO
    duplicate + selects window 1 + clears linked-id; session-mode + foreign-window unchanged.
    Then DELETE the smoke.
  - RUN: tests/run.sh (expect full suite green; session-mode tests unaffected).
  - RUN: the bug-reintroduction check (L3) — revert the condition to `[ "$S" = ... ]` and
    confirm the duplicate re-appears; restore the fix.
```

### Implementation Patterns & Key Details

**Edit 1 — locals (line 82):**

```bash
# oldText:
	local current_session orig_window linked_id src_id w_sess w_idx cur_seq
# newText:
	local current_session orig_window linked_id src_id w_sess w_idx cur_seq check_session
```

**Edit 2 — the self-session guard block (replace lines 120-134 verbatim):**

```bash
# oldText (the current block — comment + guard + body, through the closing fi):
	# Self-session guard (PRD §7; FINDING 6). Do NOT link — would create an
	# in-session duplicate; instead show the user their own session. S2
	# refinement (contract §3): first drop any prior preview linked into the
	# driver (source keeps it — S1 FINDING 1; no -k, || true — S1 FINDING 2),
	# clear LINKED_ID (tmux_unset_opt = -gu — FINDING E; matches state.sh
	# teardown), THEN select the original window.
	if [ -n "$current_session" ] && [ "$S" = "$current_session" ]; then
		if [ -n "$linked_id" ]; then
			tmux unlink-window -t "$current_session:$linked_id" 2>/dev/null || true
			tmux_unset_opt "$STATE_LINKED_ID"
		fi
		[ -n "$orig_window" ] && tmux select-window -t "$orig_window" 2>/dev/null || true
		return 0
	fi

# newText (window-mode-aware):
	# Self-session guard (PRD §7; FINDING 6). Do NOT link — would create an
	# in-session duplicate; instead select the user's own window. Bugfix ISSUE 2
	# (window-mode extension): in window mode $S is a "session:index" token
	# (e.g. "driver:1") which never equals the bare session name, so the OLD bare
	# comparison let driver-owned windows fall through to link-window, silently
	# creating a DUPLICATE (link-window rc=0 on already-linked windows). Fix:
	# compare ${S%%:*} (the token's session) — the SAME idiom used at lines 62/144.
	# Session mode ($S has no colon) is the identity -> zero regression. When the
	# guard fires in window mode, select the SPECIFIC highlighted window ($S token
	# works directly with select-window); in session mode, select ORIG_WINDOW as
	# before. (research/self_session_window_mode_findings.md FINDING 2/3/5.)
	check_session="$S"
	if [ "$(opt_type)" = "window" ] && [ "${S%%:*}" != "$S" ]; then
		check_session="${S%%:*}"
	fi
	if [ -n "$current_session" ] && [ "$check_session" = "$current_session" ]; then
		# Drop any prior CROSS-session preview linked into the driver (source keeps
		# it — S1 FINDING 1; no -k, || true — S1 FINDING 2), then clear LINKED_ID.
		if [ -n "$linked_id" ]; then
			tmux unlink-window -t "$current_session:$linked_id" 2>/dev/null || true
			tmux_unset_opt "$STATE_LINKED_ID"
		fi
		# Select the target window: window mode -> the specific "session:index"
		# ($S); session mode -> the original active window. NO link in either case.
		if [ "$(opt_type)" = "window" ]; then
			tmux select-window -t "$S" 2>/dev/null || true
		else
			[ -n "$orig_window" ] && tmux select-window -t "$orig_window" 2>/dev/null || true
		fi
		return 0
	fi
```

Key pattern notes:
- `check_session="$S"` then override in window mode — avoids `local x="$(cmd)"` (SC2155);
  matches line 81's `local S="${1:-}"` style. `check_session` is declared in Edit 1.
- The `[ "${S%%:*}" != "$S" ]` guard mirrors the EXISTING detection at line 144/146 (a token
  with a colon vs a bare name), so window-mode detection is consistent across the function.
- The unlink-prior-preview + clear-LINKED_ID steps are UNCHANGED (still needed when a foreign
  preview preceded this self-session preview).
- `select-window -t "$S"` is safe (research FINDING 3: snapshot-stable indices; the token
  resolves correctly regardless of base-index).

### Integration Points

```yaml
CODE:
  - file: scripts/preview.sh
    change: "+check_session local; self-session guard uses ${S%%:*} + mode-branched select-window"
    invariant: "driver-owned windows in window mode select (no duplicate link); session mode unchanged"

TESTS (sibling subtask — DO NOT implement here):
  - P1.M1.T2.S2 (tests/test_preview.sh): test_window_mode_self_session_no_link — calls preview.sh "driver:1",
    asserts no duplicate + linked-id empty. This PRP validates via a throwaway smoke (L2) only.

DATABASE / CONFIG / ROUTES: none.
```

## Validation Loop

### Level 1: Syntax & Style (Immediate Feedback)

```bash
cd /home/dustin/.config/tmux/plugins/tmux-livepicker
bash -n scripts/preview.sh && echo "OK: preview syntax"
shellcheck scripts/preview.sh          # expect 0 NEW findings (SC1091/SC2153 are pre-existing + silenced)
# check_session is declared + used:
grep -c 'check_session' scripts/preview.sh   # -> 4 (1 local decl + 1 init + 1 override-cond + 1 guard-cond)
# the OLD bare comparison is GONE; the new one is present:
grep -q '\[ "\$S" = "\$current_session" \]' scripts/preview.sh && echo "FAIL: old bare guard still present" || echo "OK: old guard removed"
grep -q '\[ "\$check_session" = "\$current_session" \]' scripts/preview.sh && echo "OK: new guard present" || echo "FAIL: new guard missing"
# PRECONDITION — S1 applied (bare link-window, no -a):
grep -n 'link-window' scripts/preview.sh | grep -q ' -a ' && echo "FAIL: -a present (S1 not landed)" || echo "OK: bare link-window (S1 in)"
# Tabs-not-spaces on the new region:
grep -nP '^    [^#/]' scripts/preview.sh | tail -20 && echo "WARN: space-indent" || echo "OK: tabs"
```

### Level 2: Window-mode self-session smoke (via the existing socket-isolated harness)

Throwaway smoke (DELETE after; the committed test is T2.S2). Reuses `tests/setup_socket.sh`
(PATH shim → bare `tmux` hits an isolated `-L` socket; sources the user config → base-index=1)
+ `tests/helpers.sh`. Sources the REAL preview.sh libs and calls `preview_main` directly
(mirror `test_self_session_no_link`'s `lp_preview_seed_state` pattern):

```bash
cat > /tmp/smoke_iss2.sh <<'EOF'
#!/usr/bin/env bash
set -u
cd /home/dustin/.config/tmux/plugins/tmux-livepicker
source tests/setup_socket.sh
source tests/helpers.sh
setup_test "lp-smoke-iss2"
source scripts/utils.sh
source scripts/options.sh
source scripts/state.sh

pass_n=0; fail_n=0
ck() { if [ "$2" = "$3" ]; then pass_n=$((pass_n+1)); else fail_n=$((fail_n+1)); echo "FAIL $1: got[$2] want[$3]"; fi; }

# Seed: driver is the current session; give it a 2nd window (workA) so driver:2 exists.
tmux set-option -g @livepicker-orig-session "$TEST_DRIVER_SESSION"
drv_win="$(tmux list-windows -t "=$TEST_DRIVER_SESSION" -F '#{window_id}' -f '#{window_active}')"
tmux set-option -g @livepicker-orig-window "$drv_win"
tmux set-option -g @livepicker-linked-id ""
tmux new-window -t "$TEST_DRIVER_SESSION" -a -n workA
workA_idx="$(tmux list-windows -t "=$TEST_DRIVER_SESSION" -F '#{window_index}:#{window_name}' | awk -F: '$2=="workA"{print $1;exit}')"

# --- (1) WINDOW-mode self-session: preview "driver:<workA_idx>" -> NO duplicate, selected ---
tmux set-option -g @livepicker-type window
before="$(tmux list-windows -t "=$TEST_DRIVER_SESSION" -F '#{window_id}')"
before_n="$(tmux list-windows -t "=$TEST_DRIVER_SESSION" | wc -l)"
"$LIVEPICKER_SCRIPTS/preview.sh" "$TEST_DRIVER_SESSION:$workA_idx" 2>/dev/null
after="$(tmux list-windows -t "=$TEST_DRIVER_SESSION" -F '#{window_id}')"
after_n="$(tmux list-windows -t "=$TEST_DRIVER_SESSION" | wc -l)"
ck "window-mode self: no new window (no duplicate)" "$after_n" "$before_n"
ck "window-mode self: linked-id cleared" "$(tmux show-option -gqv @livepicker-linked-id)" ""
ck "window-mode self: workA selected" "$(tmux list-windows -t "=$TEST_DRIVER_SESSION" -F '#{window_name}' -f '#{window_active}')" "workA"

# --- (2) SESSION-mode backward compat: preview "driver" -> selects ORIG_WINDOW, no link ---
tmux set-option -g @livepicker-type session
tmux set-option -g @livepicker-linked-id ""
"$LIVEPICKER_SCRIPTS/preview.sh" "$TEST_DRIVER_SESSION" 2>/dev/null
ck "session-mode self: linked-id cleared" "$(tmux show-option -gqv @livepicker-linked-id)" ""
ck "session-mode self: ORIG_WINDOW selected" "$(tmux list-windows -t "=$TEST_DRIVER_SESSION" -F '#{window_id}' -f '#{window_active}')" "$drv_win"

# --- (3) FOREIGN window: preview "alpha:0" -> guard does NOT fire, normal link path ---
tmux set-option -g @livepicker-type window
tmux set-option -g @livepicker-linked-id ""
alpha_win="$(tmux list-windows -t =alpha -F '#{window_id}' -f '#{window_active}')"
"$LIVEPICKER_SCRIPTS/preview.sh" "alpha:0" 2>/dev/null
ck "foreign window: linked-id tracks alpha" "$(tmux show-option -gqv @livepicker-linked-id)" "$alpha_win"

teardown_test
echo "pass=$pass_n fail=$fail_n"
[ "$fail_n" -eq 0 ]
EOF
bash /tmp/smoke_iss2.sh; rc=$?
rm -f /tmp/smoke_iss2.sh
exit $rc
# Expected: pass=7 fail=0. (1) is the core fix proof: NO duplicate, workA selected, linked-id cleared.
# (2) proves zero session-mode regression. (3) proves the foreign path still links normally.
```

### Level 3: Prove the fix catches the bug (critical — do not skip)

Temporarily revert the guard to the OLD bare comparison; the window-mode duplicate MUST
re-appear. Restore the fix and confirm it's gone. This proves the fix is load-bearing.

```bash
cd /home/dustin/.config/tmux/plugins/tmux-livepicker
cp scripts/preview.sh /tmp/preview.t2fixed
# Re-introduce the bug: revert the guard condition + drop the mode branch (simplest: change
# check_session back to bare S in the condition by forcing check_session="$S" always).
perl -0pi -e 's/\tcheck_session="\$S"\n\tif \[ "\$\(opt_type\)" = "window" \] && \[ "\$\{S%%:\*\}" != "\$S" \]; then\n\t\tcheck_session="\$\{S%%:\*\}"\n\tfi/\tcheck_session="$S"  # BUG: no token extraction/' scripts/preview.sh
grep -q 'BUG: no token extraction' scripts/preview.sh && echo "bug re-introduced (check_session=\$S always)"
# Re-run the smoke -> expect the window-mode-self test to FAIL (duplicate created).
bash /tmp/smoke_iss2.sh 2>/dev/null || true   # (re-create /tmp/smoke_iss2.sh from L2 first if removed)
# Expected: the "window-mode self: no new window (no duplicate)" assertion FAILS (after_n > before_n).
# Restore the fix:
cp /tmp/preview.t2fixed scripts/preview.sh
rm -f /tmp/preview.t2fixed
grep -q 'BUG: no token extraction' scripts/preview.sh && echo "FAIL: bug not restored" || echo "OK: fix restored"
# Re-run -> expect pass=7 fail=0 again.
```

### Level 4: Full suite (no regression)

```bash
cd /home/dustin/.config/tmux/plugins/tmux-livepicker
bash tests/run.sh
# Expected: the same count as before this change passes (session-mode tests are unaffected;
# the change is confined to the window-mode self-session block). If a window-mode test now
# behaves differently, it is BECAUSE the duplicate is no longer created — that is the fix
# working, not a regression (T2.S2's test will codify the new correct behavior).
```

## Final Validation Checklist

### Technical Validation

- [ ] `bash -n scripts/preview.sh` clean; `shellcheck` 0 NEW findings.
- [ ] `check_session` declared (Edit 1) + used in the guard condition (Edit 2).
- [ ] OLD bare `[ "$S" = "$current_session" ]` is GONE; new `[ "$check_session" = ... ]` present.
- [ ] L2 smoke: pass=7 fail=0 (window-mode no-duplicate, session-mode compat, foreign links).
- [ ] L3 bug-reintroduction: reverting to `check_session="$S"` re-creates the duplicate; restore -> gone.
- [ ] L4 full suite: green (no regression to session-mode paths).

### Feature Validation

- [ ] Window mode: `preview.sh "driver:N"` creates NO duplicate; selects window N; clears linked-id.
- [ ] Session mode: `preview.sh "driver"` selects ORIG_WINDOW, no link (unchanged).
- [ ] Foreign window mode: `preview.sh "alpha:0"` still links normally (guard does not fire).
- [ ] Prior cross-session preview is still unlinked when navigating onto a driver window.

### Code Quality Validation

- [ ] `${S%%:*}` idiom matches the 3 existing uses (lines 62/144/146) — `%%` not `%`.
- [ ] `select-window -t "$S"` is the simple, verified approach (documented why it's @id-invariant-safe).
- [ ] Unlink-prior-preview + clear-LINKED_ID steps unchanged; only the final select branches.
- [ ] No seq check added inside the self-session block (matches session-mode; research FINDING 6).
- [ ] No change to the bare link-window call (line 187 — S1's correct fix), the src_id resolution,
      the duplicate guard, or the link flow.
- [ ] Tab indent; `local` for check_session; `set -u`-safe.

### Documentation & Deployment

- [ ] Inline comment updated to document the window-mode extension + the `${S%%:*}` extraction +
      the ISSUE 2 reference (Mode A — internal comment, no README/CHANGELOG change here).
- [ ] Doc sync (CHANGELOG) is P1.M3.T1's scope — do NOT edit docs in this subtask.

---

## Anti-Patterns to Avoid

- ❌ Don't compare bare `$S` to `$current_session` — that is the bug (`"driver:1" != "driver"`).
  Use `$check_session` (the `${S%%:*}` extraction).
- ❌ Don't select ORIG_WINDOW in window-mode self-session — the user is browsing their own
  windows; select the SPECIFIC highlighted window (`select-window -t "$S"`).
- ❌ Don't change the unlink-prior-preview / clear-LINKED_ID steps — a foreign preview may have
  preceded this one and must still be cleaned up. Only the final select branches.
- ❌ Don't re-add `-a` to or otherwise touch the link-window call (line 187). S1's bare form is
  CORRECT (research FINDING 1 overturns the findings doc's "fails rc=1" warning — it appends
  at the END). The non-self foundation is solid.
- ❌ Don't resolve src_id before the guard / select by @id. Indices are snapshot-stable for the
  picker lifetime (no driver window is closed during browsing), so `select-window -t "$S"` is
  correct and is a smaller, cleaner diff. (research FINDING 3.)
- ❌ Don't add a deferred-preview seq check inside the self-session block — it matches the
  existing session-mode path (unlink+select+return, no 2nd check). (research FINDING 6.)
- ❌ Don't use `${S%:*}` (% shortest) — use `${S%%:*}` (%% longest) to match the codebase idiom
  (lines 62/144). For single-colon tokens both work, but %% is the house style + robust.
- ❌ Don't use `local check_session="$(cmd)"` (SC2155). `check_session="$S"` then override — no
  command substitution, matches line 81's style.
- ❌ Don't edit by line number blindly — S1 already landed and T1.S2 (parallel) is test-only
  (doesn't touch preview.sh), so line numbers are stable, but always anchor the edit on the
  unique block content (the `[ "$S" = "$current_session" ]` condition + the unlink/clear body).
- ❌ Don't commit a tests/ file here — the window-mode self-session test is T2.S2. Validate via
  the throwaway L2 smoke only.

---

## Confidence Score

**10 / 10** for one-pass success. Rationale: the fix is a minimal, pure-bash extension
(`${S%%:*}` extraction — an idiom already used 3× in the same file) plus a mode-branched
`select-window`; both edits are given verbatim with exact oldText/newText anchored on unique
block content; every mechanism is empirically PROVEN on an isolated socket (the guard fires
for `driver:N`, no duplicate is created, the right window is selected, session-mode is
unchanged, foreign windows still link); the foundation (S1's bare link-window) is confirmed
working (overturning the no-shell findings doc's warning); and the L2 smoke + L3 bug-
reintroduction check deterministically prove the fix is load-bearing. The change is confined
to the self-session block (every other path untouched), so the blast radius is nil.
