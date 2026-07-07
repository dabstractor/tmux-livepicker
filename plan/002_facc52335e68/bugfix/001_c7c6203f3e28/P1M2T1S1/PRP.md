# PRP — Bugfix P1.M2.T1.S1: third seq check (GUARD 3) + idempotent pre-link check in preview.sh (Issue 4)

> **Bug context**: Issue 4 (Minor) from the rev-002 QA pass
> (`plan/002_facc52335e68/bugfix/001_c7c6203f3e28/architecture/issue4_5_6_findings.md` §Issue 4).
> The deferred-preview supersede guard in `scripts/preview.sh` has a TOCTOU window:
> between GUARD 2 (the pre-mutation seq check) and the trailing
> `set_state "$STATE_LINKED_ID" "$src_id"`, the function performs three tmux
> round-trips (re-read linked_id, unlink, link, select). A newer keystroke/confirm/
> cancel that advances or unsets `STATE_PREVIEW_SEQ` during that window lets a stale
> job proceed to unlink/link/select/set_state — orphaning a linked window and/or
> clobbering the newer job's `@livepicker-linked-id` commit. Reproduced 5/5 with a
> 0.4s injected delay. The fix adds a THIRD seq check before the commit (Part A)
> and an idempotent pre-link probe (Part B).

---

## Goal

**Feature Goal**: Close the two harmful halves of the deferred-preview TOCTOU race in
`scripts/preview.sh::preview_main`: (A) a **GUARD 3** seq re-check immediately before
`set_state "$STATE_LINKED_ID"` (after `select-window`) so a job that went stale during
the unlink→link→select round-trips does NOT overwrite the newer job's commit; and (B) an
**idempotent pre-link check** that probes whether `src_id` is already linked into the
driver before unlinking+linking, so a losing interleave does not create a duplicate link.
Together they give the mutation block **three supersede guards** (entry / pre-mutation /
pre-commit) + an idempotent existence probe.

**Deliverable**: Two edits to `scripts/preview.sh::preview_main` — **no new files, no
committed test** (Mode A: inline-comment updates only).
1. **Part A (GUARD 3)**: insert a third `expected_seq` re-check between `select-window`
   (line ~218) and `set_state "$STATE_LINKED_ID" "$src_id"` (line ~221).
2. **Part B (idempotent)**: insert a `list-windows | grep -Fxq "$src_id"` existence probe
   immediately before the DUPLICATE GUARD block (line ~174) — if `src_id` is already in
   the driver, `select` + `set_state` + `return 0` (skip the link).
3. **(Recommended) Comment refinement**: a one-line forward-reference on the GUARD 2
   comment so its "do not move this before set_state" warning is not misread as prohibiting
   the new late GUARD 3.

**Success Definition**:
- A stale deferred job that passes GUARD 2 but is superseded during the unlink→link→select
  round-trips is caught by GUARD 3 before `set_state` → it does NOT clobber the newer job's
  `@livepicker-linked-id` (proven by the L3 throwaway: inject a delay, bump the seq
  mid-flight, assert LINKED_ID is not overwritten).
- A losing interleave that already linked `src_id` is caught by the idempotent probe → no
  duplicate `link-window` (proven by the L3 throwaway: pre-link `src_id`, call preview,
  assert the driver's window count does not increase).
- `bash -n` + `shellcheck` clean; `tests/run.sh` stays green (the additions are inert on
  the `preview-defer=off` path the bulk of the suite uses, and additive on the `defer=on`
  path `test_responsiveness.sh` uses).

## User Persona (if applicable)

**Target User**: The maintainer / QA. Not end-facing — this closes an internal concurrency
gap. The user-visible effect (a stale preview orphaning a window or corrupting the next
navigation's unlink) is rare (tens-of-ms window, needs load) but genuine.

**Use Case**: Under `@livepicker-preview-defer on` (the default), rapid typing/nav spawns
multiple background `run-shell -b` preview jobs. Only the latest should win; the losers
must be true no-ops. GUARD 1 + GUARD 2 already catch most losers; GUARD 3 + the idempotent
probe close the two residual windows (commit-clobber + duplicate-link).

**Pain Points Addressed**: PRD §18 ("A preview whose target was superseded ... must not
clobber the newer link") + §16 ("a late/superseded -b job ... must not clobber the current
link"). Without the fix, a confirm/cancel during the round-trip window can leave an
orphaned linked window in the driver and mis-track `LINKED_ID`, so the NEXT navigation or
restore unlinks the WRONG window (potentially orphaning/destroying a user window).

## Why

- **Closes a real (if narrow) gap in the headline §18 supersede guarantee.** The shipped
  two-guard scheme (entry + pre-mutation) leaves the round-trip window between GUARD 2 and
  the commit unguarded. The findings doc reproduced it 5/5 with an injected delay; under
  load it is reachable. PRD §18/§16 explicitly require a late job to never clobber the
  current link.
- **Two independent halves, both required.** Part A (GUARD 3) prevents the commit clobber
  (the worse outcome: mis-tracked LINKED_ID → wrong-window unlink on next nav/restore →
  orphan/destroy). Part B (idempotent) prevents the duplicate link (`@0 @1 @1`). Neither
  alone covers the other (research FINDING 3). The contract mandates both.
- **Cheap, surgical, additive.** Two small edits reusing in-scope locals (`$expected_seq`,
  `$src_id`, `$current_session`, `$STATE_PREVIEW_SEQ`/`$STATE_LINKED_ID` via the sourced
  state.sh). No new sourcing, no new functions, no strictness change, no committed test.
  The idempotent probe is one extra `list-windows` round-trip per preview (acceptable: nav
  is less frequent than typing; the deferred path runs in background).
- **Disjoint from the parallel task.** P1.M1.T3.S2 (in-flight) appends a test to
  `tests/test_create.sh` — it touches no production code. This task edits `scripts/preview.sh`
  ONLY. Zero file overlap.
- **Honest about the residual.** A stale job that links a DIFFERENT window than the newer
  job (A=srcX, B=srcY) leaves srcX linked-but-untracked — fundamentally unsolvable without
  per-window locking (tmux has none). GUARD 3 prevents the WORSE outcome (commit clobber →
  mis-tracked → wrong unlink); the untracked-extra-window case is caught by the next
  navigation's re-read `linked_id` + unlink, and by restore's unlink of LINKED_ID. The
  comments document this honestly (research FINDING 3).

## What

1. **Part A (GUARD 3)** — insert between `tmux select-window -t "$src_id" 2>/dev/null || true`
   and `set_state "$STATE_LINKED_ID" "$src_id"`:
   ```bash
   if [ -n "$expected_seq" ]; then
       [ "$(get_state "$STATE_PREVIEW_SEQ" "0")" != "$expected_seq" ] && return 0
   fi
   ```
   (Mirrors GUARD 1/GUARD 2's shape exactly. Placement is load-bearing: AFTER select-window,
   BEFORE set_state — do NOT move earlier.)
2. **Part B (idempotent pre-link check)** — insert immediately BEFORE the DUPLICATE GUARD
   comment block (`# DUPLICATE GUARD (FINDING 4/5)...`):
   ```bash
   if tmux list-windows -t "=$current_session" -F '#{window_id}' 2>/dev/null | grep -Fxq "$src_id"; then
       tmux select-window -t "$src_id" 2>/dev/null || true
       set_state "$STATE_LINKED_ID" "$src_id"
       return 0
   fi
   ```
   (No seq guard on this check — research FINDING 6: it only fires when src_id is already
   linked, so select+set_state are non-destructive and link-window is skipped.)
3. **(Recommended) GUARD 2 comment refinement** — append one line to the GUARD 2 comment
   block clarifying that its "do not move this before set_state" warning refers to ITS OWN
   placement, and that GUARD 3 below is an additive late check (prevents misreading).
4. **Do NOT**: add a seq guard to the idempotent check (FINDING 6); move GUARD 2 or GUARD 3
   out of their specified positions; touch the self-session guard, the preview-mode gate,
   the DUPLICATE GUARD body, or the unlink/link calls themselves; add a committed test
   (Mode A; `test_responsiveness.sh` is P1.M3.T1's scope).

### Success Criteria

- [ ] GUARD 3 present exactly once, between `select-window` and `set_state LINKED_ID`.
- [ ] Idempotent pre-link check present exactly once, before the DUPLICATE GUARD block.
- [ ] Both inside the `mode == live` path (after the preview-mode gate + self-session guard).
- [ ] GUARD 3 reuses `$expected_seq`/`get_state`/`$STATE_PREVIEW_SEQ` (no new locals).
- [ ] Idempotent check reuses `$current_session`/`$src_id`/`$STATE_LINKED_ID` (no new locals).
- [ ] `bash -n` + `shellcheck` clean on preview.sh; `tests/run.sh` green.
- [ ] L3 throwaway: GUARD 3 prevents the LINKED_ID clobber (inject delay + bump seq); the
      idempotent check prevents a duplicate (pre-link src_id; count unchanged).

## All Needed Context

### Context Completeness Check

_Pass_: The implementer needs (a) the verbatim two edits (below, with content anchors),
(b) the placement constraints (GUARD 3 after select/before set_state; idempotent before
the duplicate-guard; both in `mode == live`), (c) the "no seq guard on the idempotent
check" reasoning, and (d) the validation commands. Every behavior is verified against the
current working tree + the already-live-verified findings doc.

### Documentation & References

```yaml
# MUST READ — the empirical ground-truth for THIS fix (9 verified findings)
- docfile: plan/002_facc52335e68/bugfix/001_c7c6203f3e28/P1M2T1S1/research/issue4_toctou_fix_findings.md
  why: FINDING 1 (the TOCTOU window is between GUARD 2 line 189 and set_state line 221;
       3 round-trips span it; reproduces 5/5 with 0.4s delay); FINDING 2 (Part A = GUARD 3
       between select+set_state; Part B = list-windows|grep -Fxq before the duplicate-guard);
       FINDING 3 (the two parts address DIFFERENT halves — a table of scenarios; neither
       alone suffices; the residual honest acknowledgment); FINDING 4 (EXACT content anchors
       in the CURRENT file: DUPLICATE GUARD lines 174-180, select line 218, set_state line
       221 — the findings doc's own line numbers are slightly stale); FINDING 5 (all vars in
       scope; no new sourcing/strictness); FINDING 6 (idempotent check needs NO seq guard —
       it only fires when src_id already linked, so select+set_state are non-destructive);
       FINDING 7 (GUARD 2 comment one-line forward-reference to avoid misreading); FINDING 8
       (no committed test — Mode A; test_responsiveness.sh is P1.M3.T1; helpers.sh pins
       defer=off for the bulk); FINDING 9 (disjoint from parallel P1.M1.T3.S2).
  critical: FINDING 4 (content anchors, not line numbers) + FINDING 6 (no seq guard on B).

# MUST READ — the bug report (root cause + repro + the A/B fix specification)
- docfile: plan/002_facc52335e68/bugfix/001_c7c6203f3e28/architecture/issue4_5_6_findings.md
  why: §Issue 4 gives the exact GUARD locations (entry/GUARD2/re-read/unlink/link/select/
       set_state), the TOCTOU window, the 5/5 reproduction with 0.4s delay, and the
       recommended A (GUARD 3) + B (idempotent) fixes with verbatim snippets. Also confirms
       the idempotent probe is empirically proven on the isolated socket.
  section: "Issue 4: TOCTOU race in the deferred-preview supersede guard"

# MUST READ — the file being modified (the CURRENT preview_main body + the two anchors)
- file: scripts/preview.sh
  why: preview_main (lines 80-223) is the function edited. The two anchors (verified live):
        - Part B insertion: immediately BEFORE the `# DUPLICATE GUARD (FINDING 4/5)...`
          comment block (line 174).
        - Part A insertion: the blank line between `tmux select-window -t "$src_id"...`
          (line 218) and `# Track the linked id...` / `set_state "$STATE_LINKED_ID"...`
          (lines 220-221).
        Both are inside the `mode == live` path (after the gate at 106-123 + self-session
        guard at 125-151). GUARD 1 (100-103) and GUARD 2 (189-191) are the existing pattern
        to mirror for GUARD 3's shape.
  pattern: the existing seq-check idiom (mirror it for GUARD 3):
           `if [ -n "$expected_seq" ]; then [ "$(get_state "$STATE_PREVIEW_SEQ" "0")" != "$expected_seq" ] && return 0; fi`
  gotcha: the findings doc's line numbers (GUARD 2 at 172-174, select at 195, set_state at
          198) are STALE — the live file has GUARD 2 at 189-191, select at 218, set_state
          at 221. Anchor on CONTENT, not line numbers.

# MUST READ — WHY the seq guard exists (the supersede pattern; run-shell -b is non-cancellable)
- docfile: plan/002_facc52335e68/architecture/external_tmux_behavior.md
  why: Q5 (run-shell -b is detached/non-blocking AND not cancellable by id — a late job MUST
       be a no-op via the seq guard); Q6 (the monotonic @livepicker-preview-seq counter
       pattern; "If the picker exits while a -b job is mid-flight, the seq guard prevents it
       from clobbering restored state" — the load-bearing rationale for GUARD 3).
  section: "Q5", "Q6"

# MUST READ — PRD §18 (the supersede guarantee) + §16 (the concurrency risk)
- docfile: PRD.md
  why: §18 contract #3 ("The preview is deferred and supersedeable ... if a new keystroke/
       selection arrives before the pending preview runs, the pending one is cancelled (or
       its result discarded) and the latest target wins ... never clobber a newer link");
       §16 "Deferred-preview concurrency" (track a pending sequence; discard a late result
       so a stale unlink/link never clobbers the current link).
  section: "§18 Responsiveness" (contract #3), "§16 Implementation risks (Deferred-preview concurrency)"

# Reference — the state accessors + constants in scope
- file: scripts/state.sh
  why: get_state/set_state + STATE_PREVIEW_SEQ/STATE_LINKED_ID (declared P1.M2.T1.S1; in
        _STATE_RUNTIME_KEYS so clear_all_state clears them). preview.sh sources state.sh at
        its header, so these are in scope inside preview_main.

# Reference — the test landscape (NOT modified; for understanding the L2 suite-green claim)
- file: tests/helpers.sh
  why: Line 95 pins @livepicker-preview-defer OFF per test (so the bulk of the suite uses the
        synchronous path; the additions here are inert for them). test_responsiveness.sh
        (P1.M3.T1) re-pins it ON to exercise the deferred path.
- file: tests/test_responsiveness.sh
  why: The existing deferred-path tests (preview-defer on; STATE_PREVIEW_SEQ). This task does
        NOT add to it (Mode A); the L2 suite-green claim relies on these continuing to pass.
```

### Current Codebase tree

```bash
tmux-livepicker/
  scripts/
    preview.sh   # MODIFY: +GUARD 3 (between select-window and set_state LINKED_ID) +
                 #   idempotent pre-link check (before the DUPLICATE GUARD); +GUARD 2
                 #   comment forward-reference (recommended). Mode A (inline comments).
    options.sh / utils.sh / state.sh / filter.sh   # UNCHANGED (provide opt_*/tmux_*/STATE_*/get_state)
    input-handler.sh / livepicker.sh / renderer.sh / restore.sh / plugin.tmux  # UNCHANGED
    # NOTE: P1.M1.T3.S2 (parallel) modifies tests/test_create.sh ONLY — DISJOINT from this task.
  tests/          # UNCHANGED (no committed test; Mode A. test_responsiveness.sh is P1.M3.T1's scope.)
```

### Desired Codebase tree with files to be added and responsibility of file

```bash
scripts/preview.sh   # +GUARD 3 (third seq check before the LINKED_ID commit) +
                      #  idempotent pre-link check (list-windows existence probe before the
                      #  duplicate-guard) + GUARD 2 comment forward-reference. Closes the
                      #  Issue 4 TOCTOU commit-clobber + duplicate-link halves.
```

### Known Gotchas of our codebase & Library Quirks

```bash
# CRITICAL — GUARD 3 placement is load-bearing: AFTER select-window, BEFORE set_state
# LINKED_ID. Do NOT move it earlier (the contract §3 is explicit). A pre-link GUARD 3
# would let a stale job link then bail, leaving an UNTRACKED link (the existing GUARD 2
# comment warns of exactly this). GUARD 3's job is to prevent the COMMIT CLOBBER, not to
# prevent the link — that is unavoidable for a job that already passed GUARD 2.

# CRITICAL — anchor edits on CONTENT, not line numbers. The findings doc's line numbers
# (GUARD 2 at 172-174, select at 195, set_state at 198) are STALE; the live file has
# GUARD 2 at 189-191, select at 218, set_state at 221. Anchor Part A on the
# `tmux select-window -t "$src_id"... ` + `# Track the linked id` pair; anchor Part B on
# the `# DUPLICATE GUARD (FINDING 4/5)...` comment block. Verified live.

# CRITICAL — do NOT add a seq guard to the idempotent pre-link check (Part B). It fires
# ONLY when src_id is already linked in the driver, so select-window + set_state are
# non-destructive (select changes the active window within the session — no
# client-session-changed; set_state records the already-true linked id) and link-window
# (the destructive, duplicating op) is SKIPPED. A stale job hitting it does no harm.
# GUARD 1/2/3 own the supersede semantics; Part B owns duplicate-link prevention.
# (research FINDING 6.)

# CRITICAL — both edits MUST be inside the `mode == live` path (after the preview-mode
# gate at lines 106-123 and the self-session guard at 125-151). The DUPLICATE GUARD and
# the select/set_state block both are — verify the insertion points are after the
# `mode == live` fall-through. (research FINDING 4.)

# GOTCHA — GUARD 2's existing comment says "Do NOT move this to before the final
# select-window ... a stale job would link then bail, leaving an UNTRACKED link." This
# refers to GUARD 2's OWN placement. Adding GUARD 3 (which IS before set_state) does NOT
# move GUARD 2 — but a future reader could misread it. Add the recommended one-line
# forward-reference to the GUARD 2 comment ("GUARD 3 below is an ADDITIVE late
# commit-clobber check; this warning is about THIS guard's placement") to prevent that.
# (research FINDING 7.)

# GOTCHA — the idempotent probe uses `grep -Fxq "$src_id"` (fixed-string, exact-line
# match). `-F` = literal string (so a window id like @1 is not a regex); `-x` = whole-line
# match (so @1 does not match @10/@11); `-q` = quiet. Verified in the findings doc.

# GOTCHA — `list-windows -t "=$current_session"` uses the `=` exact-match prefix (the
# plugin's idiom for session targets; avoids ambiguity when one session name is a prefix of
# another). $current_session is read from ORIG_SESSION at line 86 (client-independent).

# GOTCHA — no new `local` declarations needed. Both edits reuse in-scope function locals
# ($expected_seq, $src_id, $current_session) and the sourced state.sh symbols
# (get_state, $STATE_PREVIEW_SEQ, $STATE_LINKED_ID, set_state). `set -u` is safe (every
# var defaulted: expected_seq="${2:-}", get_state "$STATE_PREVIEW_SEQ" "0").

# GOTCHA — no `set -e` (preview.sh has none; keep the `|| true` / `2>/dev/null` guards on
# the tmux calls). The idempotent probe's `grep -Fxq` returns rc=1 when src_id is absent —
# that is the common fall-through path; under `set -e` it would abort. preview.sh has NO
# `set -e` (confirmed), so the `if ... | grep -Fxq ...; then` form is correct.

# GOTCHA — Indent with TABS (whole codebase; shfmt NOT installed). The new blocks sit at
# 1-tab indent inside preview_main (matching the surrounding DUPLICATE GUARD / select /
# set_state lines); their inner bodies at 2 tabs.

# GOTCHA — do NOT add a committed tests/ file. Mode A (inline comments). The deferred-path
# tests live in tests/test_responsiveness.sh (P1.M3.T1's milestone). Validate via the L1
# grep cross-checks + L2 full suite + the throwaway L3 race proof (then delete it).
```

## Implementation Blueprint

### Data models and structure

No data-model change. The "structure" is the now-four-guard mutation flow:

```
preview_main(S, expected_seq):
  read current_session / orig_window / linked_id
  GUARD 1 (entry seq check)                         # existing — bail if stale at entry
  preview-mode gate (off/snapshot/live)             # existing
  self-session guard (select orig + return)         # existing
  resolve src_id; fallback if empty                 # existing
  --- NEW: idempotent pre-link check (Part B) ---   # if src_id already in driver -> select+set_state+return
  DUPLICATE GUARD (linked_id == src_id)             # existing — cheap fast path
  GUARD 2 (pre-mutation seq check)                  # existing — bail before unlink if stale
  re-read linked_id; unlink previous                # existing mutation 1
  link-window (fallback on failure)                 # existing mutation 2
  select-window                                     # existing mutation 3
  --- NEW: GUARD 3 (pre-commit seq check, Part A) --# bail before set_state if stale during round-trips
  set_state LINKED_ID = src_id                      # the commit
```

### Implementation Tasks (ordered by dependencies)

```yaml
Task 1: MODIFY scripts/preview.sh — INSERT the idempotent pre-link check (Part B)
  - LOCATE (by content): the DUPLICATE GUARD comment block:
        # DUPLICATE GUARD (FINDING 4/5). Re-previewing the SAME session (linked_id ==
        # src_id, e.g. single-match wrap): the window is already linked + selected.
        # Skip unlink AND link (re-linking would silently duplicate). Just ensure shown.
        if [ -n "$linked_id" ] && [ "$linked_id" = "$src_id" ]; then
  - ACTION: insert the idempotent check block IMMEDIATELY BEFORE that comment (1-tab
    indent for the `if`; 2-tab for the body). See Implementation Patterns for the verbatim
    oldText/newText.
  - DEPENDENCIES: $current_session (line 86), $src_id (lines 162-166, non-empty — the
    line-168 fallback returns early), set_state/$STATE_LINKED_ID (state.sh).
  - NO seq guard on this check (FINDING 6).
  - DO NOT: touch the DUPLICATE GUARD body, the unlink, the link, or GUARD 2.

Task 2: MODIFY scripts/preview.sh — INSERT GUARD 3 (Part A)
  - LOCATE (by content): the select-window + set_state pair:
        tmux select-window -t "$src_id" 2>/dev/null || true

        # Track the linked id (handle for the next unlink + for restore P1.M5).
        set_state "$STATE_LINKED_ID" "$src_id"
  - ACTION: insert GUARD 3 in the blank line between `select-window` and the `# Track the
    linked id` comment. Mirror GUARD 1/GUARD 2's shape exactly. See Implementation Patterns.
  - DEPENDENCIES: $expected_seq (line 81), get_state/$STATE_PREVIEW_SEQ (state.sh).
  - PLACEMENT: AFTER select-window, BEFORE set_state — load-bearing (do NOT move earlier).
  - DO NOT: move GUARD 2; touch the select-window or set_state lines themselves.

Task 3 (RECOMMENDED): MODIFY scripts/preview.sh — refine the GUARD 2 comment
  - LOCATE: the GUARD 2 comment block (the "Optional second supersede re-check ... Do NOT
    move this to before the final select-window ... leaving an UNTRACKED link (a leak)."
    comment, ~lines 182-188).
  - ACTION: append ONE line clarifying that the "do not move this" warning refers to
    GUARD 2's own placement, and GUARD 3 below is an additive late check. See Patterns.
  - WHY: prevents a future reader from misreading the warning as prohibiting GUARD 3.
  - This is a COMMENT-ONLY change; no behavioral risk.

Task 4: VALIDATE (L1 grep + L2 full suite + L3 throwaway race proof)
  - RUN: bash -n scripts/preview.sh ; shellcheck scripts/preview.sh
  - RUN: grep cross-checks (GUARD 3 once; idempotent grep -Fxq once; both after the
    self-session guard).
  - RUN: tests/run.sh (expect full suite green — additions are inert on defer=off, the
    bulk; additive on defer=on for test_responsiveness.sh).
  - RUN: the throwaway L3 (inject a delay; prove GUARD 3 prevents the clobber; prove the
    idempotent check prevents a duplicate); then DELETE it.
```

### Implementation Patterns & Key Details

**Task 1 — Part B (idempotent pre-link check), pasted verbatim, inserted BEFORE the
DUPLICATE GUARD comment block:**

```bash
# oldText (the DUPLICATE GUARD comment + its `if` opener — unique anchor):
	# DUPLICATE GUARD (FINDING 4/5). Re-previewing the SAME session (linked_id ==
	# src_id, e.g. single-match wrap): the window is already linked + selected.
	# Skip unlink AND link (re-linking would silently duplicate). Just ensure shown.
	if [ -n "$linked_id" ] && [ "$linked_id" = "$src_id" ]; then

# newText (the NEW idempotent check + the unchanged DUPLICATE GUARD):
	# IDEMPOTENT PRE-LINK CHECK (bugfix Issue 4 / issue4_5_6_findings.md §Issue 4 part B).
	# Probe whether src_id is ALREADY linked into the driver session — an AUTHORITATIVE
	# check that does not rely on @livepicker-linked-id (which a racing deferred job may
	# not have committed yet, or which clear_all_state may have unset). If src_id is
	# already here (a re-preview of the same window, OR a losing interleave that already
	# linked it), skip unlink+link — re-linking would silently create a DUPLICATE
	# (link-window rc=0 on already-linked windows — FINDING 4) — and just select +
	# record, exactly like the duplicate-guard below. No seq guard here: this fires only
	# when src_id is already linked, so select+set_state are non-destructive and the
	# duplicating link-window is skipped (research FINDING 6). GUARD 1/2/3 own supersede.
	if tmux list-windows -t "=$current_session" -F '#{window_id}' 2>/dev/null \
		| grep -Fxq "$src_id"; then
		tmux select-window -t "$src_id" 2>/dev/null || true
		set_state "$STATE_LINKED_ID" "$src_id"
		return 0
	fi

	# DUPLICATE GUARD (FINDING 4/5). Re-previewing the SAME session (linked_id ==
	# src_id, e.g. single-match wrap): the window is already linked + selected.
	# Skip unlink AND link (re-linking would silently duplicate). Just ensure shown.
	if [ -n "$linked_id" ] && [ "$linked_id" = "$src_id" ]; then
```

**Task 2 — Part A (GUARD 3), pasted verbatim, inserted between select-window and set_state:**

```bash
# oldText (the select-window + blank + the set_state comment/line — unique anchor):
	tmux select-window -t "$src_id" 2>/dev/null || true

	# Track the linked id (handle for the next unlink + for restore P1.M5).
	set_state "$STATE_LINKED_ID" "$src_id"

# newText (select-window + GUARD 3 + the set_state comment/line):
	tmux select-window -t "$src_id" 2>/dev/null || true

	# GUARD 3 — third supersede re-check before the LINKED_ID commit (bugfix Issue 4 /
	# issue4_5_6_findings.md §Issue 4 part A; PRD §18 contract #3). Closes the
	# commit-clobber TOCTOU window: between GUARD 2 (above) and here the function
	# performed unlink + link + select (three tmux round-trips). If a newer keystroke /
	# confirm / cancel advanced STATE_PREVIEW_SEQ (or clear_all_state unset it) during
	# those round-trips, THIS job is stale -> bail BEFORE set_state so it does NOT
	# overwrite the newer job's @livepicker-linked-id commit. Placed AFTER select-window
	# and BEFORE set_state (the contract is explicit: do NOT move earlier — a pre-link
	# guard would let a stale job link then bail, leaving an UNTRACKED link). Residual:
	# a stale job that already linked+selected a now-superseded window is unavoidable
	# without per-window locking (tmux has none); GUARD 3 prevents the WORSE outcome
	# (clobbering the newer commit -> mis-tracked -> wrong-window unlink on next
	# nav/restore), and the idempotent pre-link check above prevents a same-target
	# duplicate. GUARD 2 above remains the primary early no-op guard; THIS is additive.
	if [ -n "$expected_seq" ]; then
		[ "$(get_state "$STATE_PREVIEW_SEQ" "0")" != "$expected_seq" ] && return 0
	fi

	# Track the linked id (handle for the next unlink + for restore P1.M5).
	set_state "$STATE_LINKED_ID" "$src_id"
```

**Task 3 — GUARD 2 comment refinement (RECOMMENDED, comment-only).** Append one line to
the GUARD 2 comment's "Do NOT move this ..." paragraph:

```bash
# oldText (the tail of the GUARD 2 comment — the "Do NOT move this" sentence):
	# move this to before the final select-window: that fires AFTER link-window but
	# BEFORE set_state LINKED_ID -> a stale job would link its window then bail,
	# leaving an UNTRACKED link (a leak). (research FINDING 5.)

# newText (same + the clarifying forward-reference):
	# move this to before the final select-window: that fires AFTER link-window but
	# BEFORE set_state LINKED_ID -> a stale job would link its window then bail,
	# leaving an UNTRACKED link (a leak). (research FINDING 5.) NOTE: this warning is
	# about THIS guard's OWN placement (stay before the unlink). GUARD 3 below is an
	# ADDITIVE late commit-clobber check (Issue 4) placed intentionally before
	# set_state; it does NOT move or replace this guard.
```

NOTE for the implementer: the three oldText blocks above are the complete, ready edit
anchors (match the current file content exactly). The only allowed deviation is comment
phrasing. Do NOT add a seq guard to the idempotent check (Task 1). Do NOT move GUARD 3
(Task 2). Do NOT touch the DUPLICATE GUARD body, the unlink/link/select calls, GUARD 1,
GUARD 2's code, or the self-session guard.

### Integration Points

```yaml
CODE:
  - file: scripts/preview.sh
    change: "+GUARD 3 (seq re-check between select-window and set_state LINKED_ID);
             +idempotent pre-link check (list-windows existence probe before the DUPLICATE GUARD);
             +GUARD 2 comment forward-reference (recommended)"
    invariant: "a stale deferred job cannot clobber the newer job's LINKED_ID commit (GUARD 3);
               a losing interleave cannot create a duplicate link (idempotent check)"

CONSUMERS / PRODUCERS:
  - P1.M2.T3.S1 (input-handler.sh _lp_fire_preview): PRODUCES the expected_seq arg + bumps
    STATE_PREVIEW_SEQ. GUARD 3 consumes the same expected_seq/STATE_PREVIEW_SEQ as GUARD 1/2.
  - P1.M5 restore / clear_all_state: unsets STATE_PREVIEW_SEQ (so a late post-teardown job
    reads "0" != its captured seq -> no-op at GUARD 1 already; GUARD 3 is belt-and-braces).
  - tests/test_responsiveness.sh (P1.M3.T1): exercises the deferred path end-to-end.

CONFIG / DATABASE / ROUTES: none.
```

## Validation Loop

### Level 1: Syntax & Style (Immediate Feedback)

```bash
cd /home/dustin/.config/tmux/plugins/tmux-livepicker
bash -n scripts/preview.sh && echo "OK: preview syntax"
shellcheck scripts/preview.sh          # expect 0 NEW findings (SC1091/SC2153 are the file's
                                      #   pre-existing silenced header directives)
# GUARD 3 present exactly once (the third seq check), between select-window and set_state:
grep -c '\[ "$(get_state "$STATE_PREVIEW_SEQ" "0")" != "$expected_seq" \] && return 0' scripts/preview.sh  # -> 3 (GUARD 1, 2, 3)
# Confirm GUARD 3 is the one AFTER select-window (the select-then-guard-then-set_state sequence):
awk '/tmux select-window -t "\$src_id"/{f=1} f && /STATE_PREVIEW_SEQ.*expected_seq.*return 0/{print "GUARD 3 at line " NR; f=0} f && /set_state "\$STATE_LINKED_ID"/{print "FAIL: set_state before GUARD 3"; exit}' scripts/preview.sh
# Idempotent pre-link check present exactly once:
grep -c 'grep -Fxq "\$src_id"' scripts/preview.sh   # -> 1
grep -c 'list-windows -t "=\$current_session" -F' scripts/preview.sh   # -> 1
# Both edits are AFTER the self-session guard (mode==live path) — sanity:
grep -n 'IDEMPOTENT PRE-LINK CHECK\|GUARD 3\|DUPLICATE GUARD\|set_state "\$STATE_LINKED_ID" "\$src_id"' scripts/preview.sh
# Tabs-not-spaces in the new regions:
grep -nP '^ +[^#/]' scripts/preview.sh && echo "WARN: space-indent" || echo "OK: tabs"
# Expected: syntax clean; shellcheck 0 new findings; GUARD 3 sits between select-window and
# set_state; the idempotent grep -Fxq appears exactly once; both after the DUPLICATE GUARD
# comment region (which is after the self-session guard).
```

### Level 2: Full suite (no regression)

```bash
cd /home/dustin/.config/tmux/plugins/tmux-livepicker
tests/run.sh
# Expected: exit 0, all tests green. helpers.sh pins @livepicker-preview-defer OFF for the
# bulk of the suite (functional/restore/create/pollution/keyrepurpose/self/preview) -> the
# deferred path is not exercised there -> the additions are inert (the idempotent check
# runs on the synchronous path too, but it is a no-op when src_id is NOT already linked,
# which is the normal first-preview case). test_responsiveness.sh re-pins defer ON and
# exercises the deferred path -> it must still PASS (GUARD 3 + the idempotent check are
# additive and correct). If test_responsiveness.sh FAILS, re-check GUARD 3's placement
# (it must be AFTER select-window, not before link-window) and the idempotent check's
# grep flags (-Fxq, not -q alone).
```

### Level 3: Throwaway race proof (prove-it-catches-the-bug — then DELETE)

The race is timing-dependent (reproduces 5/5 only with an injected delay). This throwaway
injects the delay to prove GUARD 3 closes the commit-clobber half, and pre-links src_id to
prove the idempotent check closes the duplicate-link half. Run, confirm, then DELETE.

```bash
cd /home/dustin/.config/tmux/plugins/tmux-livepicker
cat > /tmp/lp_issue4_proof.sh <<'SMOKE'
#!/usr/bin/env bash
set -u
cd /home/dustin/.config/tmux/plugins/tmux-livepicker
source tests/setup_socket.sh
source tests/helpers.sh
setup_test "lp-issue4-proof"
attach_test_client
# Source the libs preview.sh uses (to call get_state/set_state directly).
source scripts/utils.sh; source scripts/options.sh; source scripts/state.sh
pass_n=0; fail_n=0
ck() { if [ "$2" = "$3" ]; then pass_n=$((pass_n+1)); else fail_n=$((fail_n+1)); echo "FAIL $1: got[$2] want[$3]"; fi; }

# --- (A) GUARD 3 prevents the LINKED_ID commit clobber ---
# Make a patched preview.sh copy with a 0.3s sleep injected between GUARD 2 and the unlink
# (widens the TOCTOU window so we can bump the seq mid-flight deterministically).
cp scripts/preview.sh /tmp/preview.issue4.orig
python3 - <<'PY'
import pathlib, re
p = pathlib.Path("scripts/preview.sh"); s = p.read_text()
# Inject a sleep right after the re-read of linked_id (before the unlink), inside the live path.
anchor = '\tlinked_id="$(get_state "$STATE_LINKED_ID" "")"\n'
inj = anchor + '\t# INJECTED DELAY (Issue 4 proof — remove after)\n\tsleep 0.3\n'
assert s.count(anchor) == 1, "anchor not unique/found"
s = s.replace(anchor, inj, 1)
p.write_text(s)
PY
# Set up picker state: driver previews session "alpha". Seed list + a preview-defer=on look.
tmux new-session -d -s alpha -x 120 -y 40   # baseline already has driver/alpha/beta; ensure alpha exists
# Simulate the fire helper's synchronous half: bump seq to 1, then call preview.sh with expected_seq=1
# in the BACKGROUND, and DURING its injected sleep bump seq to 2 (a "newer keystroke").
set_state "$STATE_PREVIEW_SEQ" "1"
( bash scripts/preview.sh alpha 1 >/dev/null 2>&1 ) &   # the stale job (expected_seq=1)
sleep 0.15                                               # let it pass GUARD 1 + GUARD 2 + reach the injected sleep
set_state "$STATE_PREVIEW_SEQ" "2"                       # newer keystroke supersedes it
wait                                                     # let the stale job finish
# GUARD 3 should have bailed -> LINKED_ID is NOT set to alpha's window by the stale job.
linked_after="$(tmux show-option -gqv @livepicker-linked-id 2>/dev/null)"
if [ -n "$linked_after" ]; then
    fail_n=$((fail_n+1)); echo "FAIL A: stale job committed LINKED_ID=[$linked_after] (GUARD 3 did not catch it)"
else
    pass_n=$((pass_n+1)); echo "ok A: GUARD 3 prevented the stale commit (LINKED_ID empty)"
fi
# Restore the un-delayed preview.sh.
cp /tmp/preview.issue4.orig scripts/preview.sh
teardown_test

# --- (B) Idempotent pre-link check prevents a duplicate link ---
setup_test "lp-issue4-idem"
attach_test_client
source scripts/utils.sh; source scripts/options.sh; source scripts/state.sh
tmux new-session -d -s alpha -x 120 -y 40
# Seed picker state so preview.sh takes the live link path for alpha.
tmux set-option -g @livepicker-list "alpha"
tmux set-option -g @livepicker-filter ""
tmux set-option -g @livepicker-index "0"
tmux set-option -g @livepicker-preview-mode live
# Count driver windows BEFORE.
before="$(tmux list-windows -t "=driver" -F '#{window_id}' | wc -l | tr -d '[:space:]')"
# Preview alpha once (links it).
bash scripts/preview.sh alpha >/dev/null 2>&1
linked1="$(tmux show-option -gqv @livepicker-linked-id 2>/dev/null)"
# Now preview alpha AGAIN — the idempotent check should find src_id already linked and
# NOT call link-window a second time (no duplicate).
bash scripts/preview.sh alpha >/dev/null 2>&1
after="$(tmux list-windows -t "=driver" -F '#{window_id}' | wc -l | tr -d '[:space:]')"
ck "B: no duplicate link (count stable)" "$after" "$before"   # IDEAL: after == before+1 (one link, no dup)
# (Note: the FIRST preview links alpha -> after = before+1. The SECOND preview must NOT add
# another -> after stays before+1. So assert after == before+1, i.e. the second call added 0.)
ck "B: second preview added 0 windows" "$after" "$((before + 1))"
teardown_test

echo "pass=$pass_n fail=$fail_n"
[ "$fail_n" -eq 0 ]
SMOKE
bash /tmp/lp_issue4_proof.sh; rc=$?
rm -f /tmp/lp_issue4_proof.sh /tmp/preview.issue4.orig
exit $rc
# Expected: pass=3 fail=0 (A: GUARD 3 prevented the stale commit; B: count stable + second
# preview added 0). The injected-delay proof for A is the load-bearing one — it fails if
# GUARD 3 is missing or misplaced (before link-window). The idempotent proof for B fails if
# the grep -Fxq check is missing/wrong.
# NOTE: timing proofs are best-effort; if (A) flakes, re-run. The firm gates are L1 + L2.
```

### Level 4: Real deferred-path smoke (optional; confirms no behavioral regression on defer=on)

```bash
cd /home/dustin/.config/tmux/plugins/tmux-livepicker
# Mirror test_responsiveness.sh's deferred-preview lifecycle once, manually, to confirm the
# three-guard + idempotent path still links/unlinks correctly under defer=on (no behavioral
# regression from the additive checks).
source tests/setup_socket.sh; source tests/helpers.sh
setup_test "lp-issue4-defer"; attach_test_client
tmux set-option -g @livepicker-preview-defer on
tmux new-session -d -s alpha -x 120 -y 40
scripts/livepicker.sh
scripts/input-handler.sh next-session    # fires a deferred preview of alpha
sleep 0.5                                 # let the bg run-shell -b job settle
echo "linked-id=[$(tmux show-option -gqv @livepicker-linked-id)]  (should be alpha's window id)"
echo "alpha wid=[$(tmux list-windows -t =alpha -F '#{window_id}' -f '#{window_active}')]"
scripts/input-handler.sh cancel >/dev/null 2>&1 || true
teardown_test
# Expected: linked-id == alpha's active window id after nav (the deferred job linked it);
# cancel tears down cleanly (no orphan). Confirms the additive checks did not break the
# normal deferred-preview flow.
```

## Final Validation Checklist

### Technical Validation

- [ ] `bash -n scripts/preview.sh` clean; `shellcheck` 0 NEW findings.
- [ ] GUARD 3 present exactly once, between `select-window` and `set_state LINKED_ID`.
- [ ] Idempotent pre-link check present exactly once (`grep -Fxq "$src_id"`), before the
      DUPLICATE GUARD block.
- [ ] Both inside the `mode == live` path (after the preview-mode gate + self-session guard).
- [ ] GUARD 2 comment forward-reference added (recommended Task 3).
- [ ] L1 grep cross-checks all green; L2 full suite green (exit 0).

### Feature Validation

- [ ] L3 (A): with an injected delay + mid-flight seq bump, GUARD 3 prevents the stale job
      from committing LINKED_ID (stays empty).
- [ ] L3 (B): a second preview of an already-linked src_id does NOT increase the driver's
      window count (idempotent check skips the link).
- [ ] L4: the real deferred path (defer=on, next-session) still links alpha's window and
      cancels cleanly (no behavioral regression).
- [ ] No `client-session-changed` pollution (Invariant A holds — preview.sh never switches).

### Code Quality Validation

- [ ] GUARD 3 mirrors GUARD 1/GUARD 2's idiom exactly (same `expected_seq`/`get_state` shape).
- [ ] Idempotent check uses `grep -Fxq` (fixed-string, exact-line); `=` exact-match session
      target; `|| true` / `2>/dev/null` on tmux calls.
- [ ] No new `local`/sourcing/strictness; `set -u`-safe; no `set -e` (the `grep -Fxq` rc=1
      fall-through is correct under the file's no-`set -e` stance).
- [ ] Edits anchored on CONTENT (not the findings doc's stale line numbers).
- [ ] Comments document the two halves + the honest residual (research FINDING 3).

### Documentation & Deployment

- [ ] GUARD 3 + idempotent comments cross-reference PRD §18, issue4_5_6_findings.md §Issue 4,
      and the GUARD 2 relationship.
- [ ] No README/CHANGELOG edit here (Mode A internal; the doc sync is P1.M3.T1).

---

## Anti-Patterns to Avoid

- ❌ Don't move GUARD 3 earlier (before link-window). The contract is explicit: AFTER
  select-window, BEFORE set_state. A pre-link guard lets a stale job link then bail, leaving
  an UNTRACKED link. GUARD 3's job is preventing the COMMIT CLOBBER. (research FINDING 2/4.)
- ❌ Don't add a seq guard to the idempotent pre-link check (Part B). It fires only when
  src_id is already linked → select+set_state are non-destructive and link-window (the
  duplicating op) is skipped. GUARD 1/2/3 own supersede. (research FINDING 6.)
- ❌ Don't anchor edits on line numbers — the findings doc's numbers (GUARD 2 at 172-174,
  select at 195, set_state at 198) are STALE (live: 189-191, 218, 221). Anchor on content.
- ❌ Don't place either edit outside the `mode == live` path. Both must be after the
  preview-mode gate + self-session guard. (research FINDING 4.)
- ❌ Don't use `grep -q "$src_id"` (substring) — use `grep -Fxq "$src_id"` (fixed-string +
  exact-line) so `@1` does not match `@10`/`@11` and is treated literally, not as a regex.
- ❌ Don't touch the DUPLICATE GUARD body, the unlink/link/select calls, GUARD 1, GUARD 2's
  CODE, or the self-session guard. The edits are purely ADDITIVE (two new blocks + one
  comment refinement).
- ❌ Don't add `set -e` — the `grep -Fxq` returns rc=1 when src_id is absent (the common
  fall-through); under `set -e` that would abort preview.sh. The file correctly has NO
  `set -e`; the `if ... | grep -Fxq ...; then` form handles it.
- ❌ Don't add a committed tests/ file — Mode A. The deferred-path tests are P1.M3.T1's
  scope (tests/test_responsiveness.sh). Validate via the throwaway L3 (then delete it).
- ❌ Don't claim the fix makes the deferred preview fully race-free. It closes the two
  HARMFUL halves (commit-clobber + duplicate-link); a stale job linking a DIFFERENT window
  than the newer job is residual (unsolvable without locking). Document this honestly.
- ❌ Don't use spaces for indent — TABS only (match the file; shfmt absent).
- ❌ Don't skip the GUARD 2 comment refinement (Task 3) thinking it's optional cosmetics —
  without it, a future reader may misread the "do not move this before set_state" warning
  as contradicting GUARD 3's placement.

---

## Confidence Score

**9 / 10** for one-pass success. Rationale: two small, fully-specified additive edits with
verbatim oldText/newText anchors pinned to verified-current content; the GUARD 3 idiom is
copied verbatim from the existing GUARD 1/GUARD 2 (same `$expected_seq`/`get_state`/
`$STATE_PREVIEW_SEQ` shape — proven correct by the two already-shipped guards); the
idempotent probe (`list-windows | grep -Fxq`) is empirically proven on the isolated socket
in the findings doc; both edits reuse in-scope locals (no new sourcing/strictness/locals);
the contract and findings doc agree exactly on placement and semantics. The firm gates
(L1 grep + L2 full-suite-green) deterministically confirm structure + no regression; the
L3 throwaway proves the race closure (best-effort due to timing, but the injected-delay
reproduction is the findings doc's own 5/5 method). Disjoint from the parallel P1.M1.T3.S2
(test_create.sh only). Residual risk: (a) the L3 timing proof could flake (mitigated:
re-run; the L1/L2 gates are firm); (b) a shellcheck SC on the piped `grep -Fxq` (unlikely;
valid bash, and the file already pipes). All residual risks are caught by the validation
loop.
