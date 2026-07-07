# PRP — Bugfix P1.M1.T1.S1: Remove `-a` flag from link-window call in preview.sh

> **Re-planning context**: Issue 1 from the rev-002 QA pass
> (`plan/002_facc52335e68/bugfix/001_c7c6203f3e28/architecture/issue1_2_findings.md`).
> `preview.sh:187` calls `link-window -a`, which inserts the preview window AFTER
> the driver's active window. When the active window is not the last one, this
> shifts every subsequent window's index; `unlink-window` on exit leaves the gap
> (tmux does **not** renumber on unlink, even with `renumber-windows on`), so the
> driver's windows are permanently reindexed — violating the "full, exact
> restoration" invariant (PRD §9 / §15). This is a one-flag fix.

---

## Goal

**Feature Goal**: `preview.sh`'s preview-link call uses bare `link-window` (no
`-a`), so the linked preview window appends at the **end** of the driver session
(the next free index) and never shifts an existing window's index. After
`unlink-window` on exit, the driver's window list is byte-identical to before
activation.

**Deliverable**: One edit to `scripts/preview.sh` — remove `-a` from the
`link-window` call (line 187) and rewrite the preceding comment block (lines
185-186) to document (a) why bare `link-window` (append-at-end) is correct and
(b) the deviation from PRD §13's `-a` prescription. **No other files change.**

**Success Definition**:
- `grep -rn 'link-window -a' scripts/` returns **nothing**.
- A multi-window driver whose active window is in the MIDDLE, after
  activate → preview-another-session → cancel, has **unchanged** window indices
  (proved by an end-to-end repro on an isolated socket).
- `bash -n` + `shellcheck` clean; the surrounding `unlink-window` /
  `select-window` / `set_state` logic is untouched.

## User Persona (if applicable)

**Target User**: Any user whose active window is not the last window in its
session (i.e. almost everyone). Also the maintainer / automated QA.

**Use Case**: Open the picker, browse another session's preview, cancel — the
driver session's window tab order and indices must be exactly as before.

**Pain Points Addressed**: Silent permanent reindexing of the driver's windows
on the default code path (session mode, browsing, cancel/confirm); the user's
muscle-memory window numbers (e.g. `prefix 2`) now point at the wrong window.

---

## Why

- **Fires on the default path, borders Critical.** Session mode → browse another
  session → cancel/confirm, for any driver whose active window isn't last. This
  is the common case, not an edge case.
- **Violates the headline invariant.** PRD §9 / §15 promise exact restoration.
  Permanent index drift is the most visible possible breach (the user's window
  tabs literally move).
- **Root cause is one flag.** `-a` (insert-after-active) is the sole cause. Bare
  `link-window` (append-at-end) is empirically verified to preserve indices.

## What

1. **The fix**: in `scripts/preview.sh`, change line 187 from
   `if ! tmux link-window -a -s "$src_id" -t "$current_session:" 2>/dev/null; then`
   to `if ! tmux link-window -s "$src_id" -t "$current_session:" 2>/dev/null; then`
   (drop `-a`). Change **nothing else** in the call (the `-s "$src_id"`,
   `-t "$current_session:"`, the `2>/dev/null`, the `if ! … ; then` guard, and the
   `preview_fallback` branch are all correct).
2. **The comment**: rewrite the two comment lines immediately above (185-186) so
   they (a) describe the bare append-at-end behavior and why it preserves indices,
   and (b) note this is a deliberate deviation from PRD §13's `-a` prescription,
   citing the bugfix findings.

### Success Criteria

- [ ] `scripts/preview.sh:187` no longer contains `-a`.
- [ ] `grep -rn 'link-window -a' scripts/` → no matches.
- [ ] The comment above the call documents the §13 deviation + the append-at-end
      rationale + the empirical verification.
- [ ] End-to-end repro (multi-window driver, active=middle, preview+cancel) shows
      **unchanged** `#{window_index}` ordering before vs after.
- [ ] `bash -n` + `shellcheck` clean; no other logic changed.

## All Needed Context

### Context Completeness Check

_Pass_: The implementer needs (a) the exact one-line edit (given verbatim below),
(b) the empirical proof that bare `link-window` appends at the end (run in this
research, summarized below), and (c) awareness that the alternative `:99` form
(mentioned in `issue1_2_findings.md`) is inferior. No inference required.

### Documentation & References

```yaml
# MUST READ - the bug report (root cause + repro + the two candidate fixes)
- docfile: plan/002_facc52335e68/bugfix/001_c7c6203f3e28/architecture/issue1_2_findings.md
  why: §Issue 1 gives the exact location (preview.sh:187), the mechanism (-a inserts
       after active; unlink leaves a gap; renumber does NOT fire on unlink), and the repro.
  critical: TWO candidate fixes are floated — bare `-t session:` (PRD §Issue 1 primary
            suggestion + this task's CONTRACT) vs explicit `-t session:99` (the findings
            doc's suggestion). EMPIRICALLY VERIFIED HERE: bare is correct and superior
            (appends contiguously at the end; :99 leaves a visible gap at index 99 during
            preview). USE THE BARE FORM. See "Empirical verification" below.

# MUST READ - the exact line to edit
- file: scripts/preview.sh
  why: Line 187 is the sole `link-window -a` call in the whole scripts/ tree (verified
        by `grep -rn 'link-window -a' scripts/` → exactly one match). Lines 185-186 are
        its preceding comment (currently MISLEADING: it says "bare index -> free slot"
        while the code used -a).
  pattern: The call is guarded `if ! tmux link-window … 2>/dev/null; then preview_fallback`.
           Keep the guard, the -s/-t args, the 2>/dev/null, and the fallback — only drop -a.
  gotcha: restore.sh:88 has an `unlink-window` (NOT a link) — it is CORRECT and untouched.
          The bug is only the link call. Do not "fix" the unlink.

# Reference - the PRD section this deviates from
- docfile: PRD.md
  why: §13 prescribes `link-window -a -s <id> -t <session>:`. This bugfix OVERRIDES that
        prescription. Note the deviation in the code comment (and the §13 doc text is
        owned by humans — do NOT edit PRD.md; just document the deviation inline).
  section: "§13. tmux primitives reference" (link-window)

# Reference - the existing tests that MISS this bug (why S2 is needed, separately)
- file: tests/test_preview.sh
  why: test_navigate_unlinks_intact (~line 84) and tests/test_restore.sh
       test_restore_cancel_layout_exact assert on window **IDs** (#{window_id}), which
       are unchanged by an index shift, so they pass despite the bug. They also use
       single-window drivers. Strengthening them to compare #{window_index} ordering on a
       MULTI-window driver is P1.M1.T1.S2 (a SEPARATE subtask) — do NOT add the committed
       test here; just run a throwaway repro (Validation L2) to prove this fix.
```

### Empirical verification (run during this research, tmux 3.6b, isolated `-L` socket)

The contract (bare form) and `issue1_2_findings.md` (`:99` form) disagreed. Both
were tested on a throwaway isolated socket. Results:

```
BASELINE (driver, active = MIDDLE window W1):  1:zsh  2:W1  3:W2

BUG (-a):   link-window -a -s @SRC -t drv:   ->  1:zsh  2:W1  3:<linked>  4:W2   (W2 shifted 3->4)
            unlink-window -t drv:@SRC        ->  1:zsh  2:W1  4:W2                    (GAP at 3; permanent)

FIX (bare): link-window -s @SRC -t drv:      ->  1:zsh  2:W1  3:W2  4:<linked>       (appended at END; nothing shifted)
            unlink-window -t drv:@SRC        ->  1:zsh  2:W1  3:W2                     (CLEAN — original indices)

ALT (:99):  link-window -s @SRC -t drv:99    ->  1:zsh  2:W1  3:W2  99:<linked>      (VISIBLE GAP at 99 during preview)
            unlink-window -t drv:@SRC        ->  1:zsh  2:W1  3:W2                     (CLEAN)
```

**Conclusion**: bare `link-window -s "$src_id" -t "$current_session:"` (the
contract's form) is correct AND superior — it appends contiguously at the end
(clean status bar during preview) and unlinks back to the exact original indices,
**regardless of which window is active**. The `:99` alternative preserves indices
too but leaves an ugly gap at 99 during the preview and uses a magic number that
could collide if a user has 100+ windows. **Use the bare form.**

Why bare is safe even with `renumber-windows off` or pre-existing gaps: bare
`link-window` takes the next free index. Appending/removing the highest element
never requires renumbering, so existing indices are immutable. (If the driver
already had a gap, bare fills the lowest hole — still no existing window moves;
unlink restores the hole exactly.)

### Current Codebase tree

```bash
tmux-livepicker/
  scripts/
    preview.sh    # MODIFY: line 187 drop -a; lines 185-186 rewrite comment
    restore.sh    # UNCHANGED (its unlink-window at ~line 88 is correct, not a link)
    ...           # (all other scripts unchanged)
  tests/          # UNCHANGED here (committed index-assertion test is P1.M1.T1.S2)
```

### Desired Codebase tree with files to be added and responsibility of file

```bash
scripts/preview.sh   # one flag removed + comment rewritten; behavior: preview link appends at end, indices preserved
```

### Known Gotchas of our codebase & Library Quirks

```bash
# CRITICAL — use the BARE form, NOT `:99`. issue1_2_findings.md suggests an explicit
# high index (`-t "$current_session:99"`); that is the INFERIOR alternative (leaves a
# visible gap at index 99 during the preview; magic-number collision risk at 100+ windows).
# The CONTRACT and PRD §Issue 1 primary suggestion both prescribe the bare form, which is
# empirically verified to append at the end and unlink cleanly. Drop ONLY the `-a`.

# CRITICAL — only ONE -a exists. `grep -rn 'link-window -a' scripts/` → preview.sh:187 only.
# restore.sh:88 is an unlink-window (correct, untouched). Do not touch restore.sh.

# CRITICAL — tmux does NOT renumber on unlink, even with renumber-windows on. That is the
# whole reason -a is fatal (mid-list insert + unlink = permanent gap). Bare append-at-end
# sidesteps this: the linked window is the LAST element, so removing it leaves no gap.

# CRITICAL — do NOT change anything else on the line: keep `-s "$src_id"`, the target
# `-t "$current_session:"`, the `2>/dev/null`, and the `if ! … ; then preview_fallback`
# guard. The fallback-on-failure contract (S2 capture-pane) depends on that guard intact.

# GOTCHA — the existing comment (line 185) is ALREADY misleading: it says "bare index ->
# free slot" while the code used -a. Your rewrite makes the comment match the (fixed) code.

# GOTCHA — the contract's "lines ~150-154 referencing link-window -a" is a red herring:
# that region is the src_id resolution (window-mode token parsing); it has no -a reference.
# The only -a is line 187 + its comment at 185-186. The file header (lines 1-30) also does
# NOT reference §13's -a (the LOAD-BEARING RULES at 20-30 don't mention it) — no header edit.

# GOTCHA — Indent with TABS (the file is tab-indented; shfmt is NOT installed). The edit
# oldText must use literal tabs to match.
```

## Implementation Blueprint

### Data models and structure

No data model. The fix is one flag + a comment. The relevant flow:

```
preview_main(candidate S):
  resolve src_id (the candidate's active window @id)
  unlink the previous preview (current_session:$linked_id)        # restore.sh also does this; correct
  link-window -s "$src_id" -t "$current_session:"                 # <-- was `-a`; now bare (append at END)
  select-window -t "$src_id"                                       # show it (Invariant A: no client-session-changed)
  set_state STATE_LINKED_ID "$src_id"                              # track for the next unlink + restore
```

### Implementation Tasks (ordered by dependencies)

```yaml
Task 1: MODIFY scripts/preview.sh — drop -a + rewrite the comment
  - LOCATE: the link-window call at line 187 + its preceding comment lines 185-186.
  - EDIT (exact oldText/newText below; both tab-indented — use literal tabs).
  - oldText (3 lines, each starts with ONE tab):
      \t# Link S's active window into the current session (bare index -> free slot).
      \t# GUARDED: on ANY failure, fall back (S1 stub -> exit non-zero; S2 -> capture-pane).
      \tif ! tmux link-window -a -s "$src_id" -t "$current_session:" 2>/dev/null; then
  - newText (comment rewritten to explain bare-append + §13 deviation; call has NO -a):
      \t# Link S's active window into the current session. BARE link-window (no -a)
      \t# appends at the next free index at the END, so NO existing window's index
      \t# shifts and unlink restores the original list exactly. PRD §13 prescribes
      \t# `-a` (insert AFTER active) — DEVIATION: that inserts mid-list when the active
      \t# window isn't last, permanently shifting later windows (unlink leaves a gap;
      \t# renumber-windows does NOT fire on unlink). Verified on tmux 3.6b. See
      \t# plan/002_facc52335e68/bugfix/001_c7c6203f3e28/architecture/issue1_2_findings.md §Issue 1.
      \t# GUARDED: on ANY failure, fall back (S1 stub -> exit non-zero; S2 -> capture-pane).
      \tif ! tmux link-window -s "$src_id" -t "$current_session:" 2>/dev/null; then
  - DO NOT: touch the unlink-window (line 182 / restore.sh:88), select-window,
    set_state, the src_id resolution, or any other line.
  - VERIFY after edit: `grep -rn 'link-window -a' scripts/` → no output.

Task 2: VALIDATE (throwaway end-to-end repro on the isolated socket harness)
  - RUN: bash -n scripts/preview.sh ; shellcheck scripts/preview.sh
  - RUN: the throwaway repro in Validation Loop §2 (multi-window driver, active in
    the MIDDLE, activate → next-session → cancel → assert indices unchanged). This
    FAILS on the un-fixed code and PASSES after. Delete the throwaway after.
  - NOTE: the COMMITTED index-assertion test is P1.M1.T1.S2 (separate subtask).
    Do NOT add a tests/ file here; run the repro inline and discard it.
```

### Implementation Patterns & Key Details

**Exact edit** (paste into the `edit` tool; `\t` = one literal tab — the file is tab-indented):

```bash
# oldText (3 tab-indented lines):
	# Link S's active window into the current session (bare index -> free slot).
	# GUARDED: on ANY failure, fall back (S1 stub -> exit non-zero; S2 -> capture-pane).
	if ! tmux link-window -a -s "$src_id" -t "$current_session:" 2>/dev/null; then

# newText (comment rewritten; -a removed from the call):
	# Link S's active window into the current session. BARE link-window (no -a)
	# appends at the next free index at the END, so NO existing window's index
	# shifts and unlink restores the original list exactly. PRD §13 prescribes
	# `-a` (insert AFTER active) — DEVIATION: that inserts mid-list when the active
	# window isn't last, permanently shifting later windows (unlink leaves a gap;
	# renumber-windows does NOT fire on unlink). Verified on tmux 3.6b. See
	# plan/002_facc52335e68/bugfix/001_c7c6203f3e28/architecture/issue1_2_findings.md §Issue 1.
	# GUARDED: on ANY failure, fall back (S1 stub -> exit non-zero; S2 -> capture-pane).
	if ! tmux link-window -s "$src_id" -t "$current_session:" 2>/dev/null; then
```

The `if ! … 2>/dev/null; then preview_fallback` guard is **preserved exactly** —
the S2 capture-pane fallback depends on link failure still routing to
`preview_fallback`. Only `-a` is removed.

### Integration Points

```yaml
CODE:
  - file: scripts/preview.sh
    change: "line 187: drop `-a` from the link-window call; rewrite comment 185-186"
    invariant: "preview link appends at the END; driver window indices never shift; unlink restores exactly"

CONSUMERS (unchanged behavior, now correct):
  - restore.sh:88 unlink-window — already correct; now unlinks a window that was at the END (clean)
  - input-handler.sh next-session/prev-session — re-preview unlinks the prior + links the new (both at end)
  - the pollution invariant (PRD §15.18) — unaffected (select-window still fires only session-window-changed)

CONFIG / DATABASE / ROUTES: none.
```

## Validation Loop

### Level 1: Syntax & Style (Immediate Feedback)

```bash
cd /home/dustin/.config/tmux/plugins/tmux-livepicker
bash -n scripts/preview.sh && echo "OK: syntax"
shellcheck scripts/preview.sh                # expect 0 NEW findings
# The fix is present and -a is gone everywhere:
grep -rn 'link-window -a' scripts/ && echo "FAIL: -a still present" || echo "OK: no link-window -a remains"
# The bare call is present exactly once:
grep -c 'link-window -s "\$src_id" -t "\$current_session:"' scripts/preview.sh   # -> 1
# Tabs-not-spaces on the edited region (shfmt absent):
sed -n '185,191p' scripts/preview.sh | grep -qP '^ *\t' || echo "WARN: check indent"
```

### Level 2: End-to-end repro on the isolated socket (proves the fix; delete after)

This mirrors the bug report's repro and is the template for S2's committed test.
It uses the repo's own harness (`tests/setup_socket.sh` + `tests/helpers.sh`) so
bare `tmux` hits an isolated `-L` socket, never the user's server.

```bash
cat > /tmp/repro_issue1.sh <<'EOF'
#!/usr/bin/env bash
set -u
cd /home/dustin/.config/tmux/plugins/tmux-livepicker
source tests/setup_socket.sh
source tests/helpers.sh
setup_test "lp-issue1"
attach_test_client
# Multi-window DRIVER with active window NOT last (the bug's trigger).
tmux new-window -t "$TEST_DRIVER_SESSION" -n W1
tmux new-window -t "$TEST_DRIVER_SESSION" -n W2
# Make W1 (a MIDDLE window) active via @id (robust to indices).
mid=$(tmux list-windows -t "=$TEST_DRIVER_SESSION" -F '#{window_id}:#{window_name}' | awk -F: '$2=="W1"{print $1}')
tmux select-window -t "$mid"
# Snapshot window INDEX ordering (the property the bug corrupts).
before="$(tmux list-windows -t "=$TEST_DRIVER_SESSION" -F '#{window_index}:#{window_name}')"
# Browse another session's preview, then cancel.
"$LIVEPICKER_SCRIPTS/livepicker.sh" >/dev/null
"$LIVEPICKER_SCRIPTS/input-handler.sh" next-session >/dev/null   # preview alpha/beta (links at END now)
"$LIVEPICKER_SCRIPTS/input-handler.sh" cancel        >/dev/null
after="$(tmux list-windows -t "=$TEST_DRIVER_SESSION" -F '#{window_index}:#{window_name}')"
assert_eq "$after" "$before" "driver window INDEX ordering unchanged after preview+cancel"
teardown_test
[ "$TEST_STATUS" = pass ]
EOF
bash /tmp/repro_issue1.sh; rc=$?
rm -f /tmp/repro_issue1.sh
exit $rc
# Expected: PASS (exit 0). To prove it catches the bug, temporarily re-add -a
# (edit preview.sh back to `link-window -a -s …`), rerun -> FAIL (indices shifted,
# e.g. W2 moved from 3->4 with a gap at 3), then restore the fix. See Level 3.
```

### Level 3: Prove the test catches the bug (critical)

```bash
cd /home/dustin/.config/tmux/plugins/tmux-livepicker
cp scripts/preview.sh /tmp/preview.fixed
# Re-introduce -a:
perl -0pi -e 's/tmux link-window -s "\$src_id"/tmux link-window -a -s "\$src_id"/' scripts/preview.sh
grep -q 'link-window -a' scripts/preview.sh && echo "bug re-introduced"
# (rerun the Level 2 repro here -> it should FAIL with an index-ordering mismatch)
bash -c 'set -u; cd /home/dustin/.config/tmux/plugins/tmux-livepicker
  source tests/setup_socket.sh; source tests/helpers.sh
  setup_test "lp-issue1-neg"; attach_test_client
  tmux new-window -t "$TEST_DRIVER_SESSION" -n W1; tmux new-window -t "$TEST_DRIVER_SESSION" -n W2
  mid=$(tmux list-windows -t "=$TEST_DRIVER_SESSION" -F "#{window_id}:#{window_name}" | awk -F: "\$2==\"W1\"{print \$1}")
  tmux select-window -t "$mid"
  b="$(tmux list-windows -t "=$TEST_DRIVER_SESSION" -F "#{window_index}:#{window_name}")"
  "$LIVEPICKER_SCRIPTS/livepicker.sh" >/dev/null
  "$LIVEPICKER_SCRIPTS/input-handler.sh" next-session >/dev/null
  "$LIVEPICKER_SCRIPTS/input-handler.sh" cancel >/dev/null
  a="$(tmux list-windows -t "=$TEST_DRIVER_SESSION" -F "#{window_index}:#{window_name}")"
  [ "$a" = "$b" ] && echo "UNEXPECTED PASS (bug not reproduced)" || echo "OK: bug reproduced (indices differ)"
  teardown_test'
# Restore the fix:
cp /tmp/preview.fixed scripts/preview.sh
rm -f /tmp/preview.fixed
grep -q 'link-window -a' scripts/preview.sh && echo "FAIL: -a still present" || echo "OK: fix restored"
# Expected: "OK: bug reproduced (indices differ)" with -a present; "OK: fix restored" after.
```

### Level 4: Mechanism proof (already run in research; re-runnable for confidence)

```bash
# Direct primitive proof (isolated socket) that bare link-window appends at END
# and unlinks cleanly, while -a inserts mid-list and leaves a gap. See the
# "Empirical verification" block above for expected output. Optional — only run
# if you want to re-confirm the tmux primitive behavior independently of the plugin.
```

## Final Validation Checklist

### Technical Validation

- [ ] `bash -n scripts/preview.sh` clean; `shellcheck` 0 new findings.
- [ ] `grep -rn 'link-window -a' scripts/` → no matches.
- [ ] Bare `link-window -s "$src_id" -t "$current_session:"` present exactly once.
- [ ] L2 end-to-end repro PASSES (driver window indices unchanged).

### Feature Validation

- [ ] Multi-window driver, active=middle: preview-another-session + cancel leaves
      `#{window_index}` ordering byte-identical to before activation.
- [ ] Bug-reintroduction check (L3): with `-a` restored, the repro FAILS.
- [ ] The `if ! … ; then preview_fallback` guard is intact (fallback still wired).

### Code Quality Validation

- [ ] Only `-a` removed; `-s`/`-t`/`2>/dev/null`/guard/fallback all preserved.
- [ ] restore.sh untouched (its unlink is correct).
- [ ] Comment rewritten to document the §13 deviation + append-at-end rationale.
- [ ] Tab indent preserved; no other lines changed.

### Documentation & Deployment

- [ ] Inline comment cites the bugfix findings (issue1_2_findings.md §Issue 1) and
      the empirical verification, so the deviation is self-documenting.
- [ ] No README/CHANGELOG change in this subtask (handled by the final sync task
      P1.M3.T1). PRD.md is human-owned — do NOT edit it; document the §13 deviation
      in the code comment only.

---

## Anti-Patterns to Avoid

- ❌ Don't use `-t "$current_session:99"` — it's the inferior alternative from
  issue1_2_findings.md (visible gap at 99 during preview; magic-number collision
  risk). Use the bare form the contract prescribes; it's empirically superior.
- ❌ Don't touch the `unlink-window` in preview.sh:182 or restore.sh:88 — those
  are correct; the bug is only the `-a` on the link.
- ❌ Don't change anything else on line 187 (`-s`, `-t`, `2>/dev/null`, the guard,
  the `preview_fallback` branch) — only `-a` is wrong.
- ❌ Don't add a committed `tests/` file here — the index-assertion test is a
  separate subtask (P1.M1.T1.S2). Validate via the throwaway L2/L3 repro only.
- ❌ Don't trust the existing `test_navigate_unlinks_intact` /
  `test_restore_cancel_layout_exact` to catch this — they assert on window **IDs**
  (unchanged by a shift) and use single-window drivers. That's exactly why the
  bug slipped through; S2 closes that gap.
- ❌ Don't edit PRD.md §13 to "fix" the prescription — PRD is human-owned;
  document the deviation in the code comment instead.
- ❌ Don't skip the bug-reintroduction check (L3) — a fix you can't prove fails
  without is a fix you can't trust.

---

## Confidence Score

**10 / 10** for one-pass success. Rationale: the change is the removal of a single
flag on a single line (exact oldText/newText provided, tab-anchored); the
contract-vs-findings.md discrepancy (bare vs `:99`) was resolved by direct
empirical testing on tmux 3.6b proving the bare form appends at the end and
unlinks cleanly while `:99` leaves a gap; the bug itself was reproduced (`-a`
shifts mid-list windows; unlink leaves a permanent gap); and the validation
includes an executable end-to-end repro plus a reintroduce-the-bug check that
proves the fix is load-bearing. No ambiguity remains.
