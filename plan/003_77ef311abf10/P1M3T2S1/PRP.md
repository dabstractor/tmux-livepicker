name: "P1.M3.T2.S1 — Wire scroll state into input paths (race-safe re-plan, attempt 2/3)"
description: |

---

## Goal

**Feature Goal**: Navigation (`next-session`/`prev-session`) scrolls the highlight into view
by writing `@livepicker-scroll`; typing/backspace/cancel-clear reset scroll to 0 — all as a
synchronous status-state update (PRD §18 / §19 §3.32) — **without** breaking the deferred-preview
supersession race that the scroll reads trigger.

**Deliverable**: `scripts/input-handler.sh` carries the scroll-into-view + scroll-reset wiring
AND a small `_lp_invalidate_pending_preview` early-invalidation step on the nav path that keeps
`test_superseded_preview_noop` green. Single-file change (input-handler.sh only).

**Success Definition**:
- `bash tests/run.sh` passes **77/77**, run **5–10× in a row** (the failing test is timing-sensitive;
  one passing run is NOT sufficient). `test_superseded_preview_noop` MUST pass every run.
- `bash -n scripts/input-handler.sh` + `shellcheck` clean.
- Scroll behavior intact: `tests/test_scroll_width.sh` (defer=off) still advances scroll on nav,
  clamps to 0 when it fits, and resets to 0 on type/backspace/cancel-clear.

## Why

- PRD §19 §3.32: the viewport follows the highlight — nav must keep `@livepicker-scroll` tracking
  the keypress; type/backspace/cancel-clear snap it back to the top.
- **Attempt 1 (commit `91fd8be`) shipped the scroll wiring verbatim and DETERMINISTICALLY broke
  `test_superseded_preview_noop`** (3/3 runs failed: "stale alpha fire leaked a stray link into the
  driver"). The wiring is logically correct but timing-incompatible with the supersession race.
- This PRP is the **minimal, single-file race fix** that lets the already-shipped scroll wiring stay.
  Root cause + verified fix are in `research/race_fix_findings.md`.

## What

### Current state of the SUT (READ THIS FIRST)

`scripts/input-handler.sh` at HEAD **already contains** the full scroll wiring from attempt 1
(commit `91fd8be`). These are CORRECT and STAY — do not remove or rewrite them:
- `source "$CURRENT_DIR/layout.sh"` (after the rank.sh source).
- `_lp_scroll_into_view IDX RANKED` helper (reads `STATE_CLIENT_WIDTH` + `STATE_SCROLL` via
  `get_state`, calls `lp_viewport`, writes `STATE_SCROLL`).
- 2 nav call sites: `_lp_scroll_into_view "$new_idx" "$(printf '%s\n' "${filtered[@]}")"` placed
  BETWEEN `set_state "$STATE_INDEX" "$new_idx"` and `_lp_preview_follow "$target"`.
- 3 scroll=0 resets (type / backspace / cancel-clear) right after each `set_state "$STATE_INDEX" "0"`.

**The ONLY thing missing is the race fix** — 3 small additions (1 helper + 2 one-line call sites).

### The race (so you understand the fix, not just paste it)

`test_superseded_preview_noop` fires two rapid `next-session` (defer=on): `seq=1 -> alpha`,
`seq=2 -> beta`. The stale alpha fire (seq=1) MUST no-op in `preview.sh` GUARD 2 (the supersede
re-check placed just before the first mutation — the `unlink-window`). It no-ops iff
`STATE_PREVIEW_SEQ` has advanced past 1 by the time alpha's fire reaches GUARD 2.

**Every tmux round-trip pumps the server event loop**, which RUNS pending `run-shell -b` jobs
(alpha's fire). The `_lp_scroll_into_view` helper's 2 `get_state` reads sit on nav #2's
**pre-seq-bump** path (the bump happens last, inside `_lp_fire_preview` via `_lp_preview_follow`).
Those extra round-trips (a) advance alpha's fire toward GUARD 2 and (b) delay nav #2's seq bump →
alpha reaches GUARD 2 while seq is still 1 → it links alpha → leak. Attempt 1 proved it (clean tree
+ N synthetic round-trips: 0 extra = 6/6 pass, 2 extra = 0/6 pass; a 20ms `sleep` with NO round-trip
did NOT reproduce it → it is the round-trips, not latency).

### Success Criteria

- [ ] `_lp_invalidate_pending_preview` helper added; called as the FIRST statement of both
      `next-session)` and `prev-session)` branches.
- [ ] The existing scroll wiring (source line, `_lp_scroll_into_view`, 3 resets, 2 nav call sites)
      is left UNTOUCHED.
- [ ] No other file is modified (preview.sh, state.sh, layout.sh, rank.sh, tests/* all unchanged).
- [ ] `tests/run.sh` passes 77/77 across 5–10 consecutive runs.

## All Needed Context

### Context Completeness Check

_Passed._ The SUT is a single file already containing the scroll wiring; the fix is a localized
nav-path invalidation. A fresh implementer needs: the race mechanism (above), the exact edit
anchors + code (Implementation Blueprint), and the multi-run validation (Validation Loop). All
verified empirically this session (10/10 green; source reverted to leave the tree clean).

### Documentation & References

```yaml
# MUST READ — the proven root cause + verified fix (this session, tmux 3.6b)
- docfile: plan/003_77ef311abf10/P1M3T2S1/research/race_fix_findings.md
  why: Full race analysis, the round-trip budget proof, why each alternative was rejected,
       the 10/10-green verification log, and the out-of-scope type-path note.
  critical: §3 (the fix + why the defer=on gate), §5 (DO NOT touch the type path — breaks seq==3).

# The original (attempt-1) research — still valid for the scroll math / helper design
- docfile: plan/003_77ef311abf10/P1M3T2S1/research/scroll_input_findings.md
  why: §3 (lp_viewport self-correction → T = STATE_CLIENT_WIDTH is safe), §5 (scroll is a
       synchronous STATE write, NOT preview work), §6 (the _lp_scroll_into_view helper).
  critical: §7 is now SUPERSEDED — it predicted the suite stays green on CORRECTNESS grounds only
       and missed the TIMING interaction. Trust race_fix_findings.md §2/§3 over it.

- file: scripts/input-handler.sh
  why: THE SUT (single file to edit). _lp_fire_preview (line ~169) bumps STATE_PREVIEW_SEQ;
       _lp_preview_follow (defer=on) does refresh-client -S THEN _lp_fire_preview; the nav branches
       (next-session ~line 285, prev-session ~line 321) are where the call sites go.
  pattern: the existing _lp_* helper convention (_lp_sync_preview_to_top_match, _lp_fire_preview,
           _lp_preview_follow, _lp_scroll_into_view) — add _lp_invalidate_pending_preview alongside.
  gotcha: _lp_fire_preview reads the CURRENT seq and increments (do NOT refactor it to skip its bump —
          the double-bump is intentional and correct; the seq guards compare equality so gaps are fine).

- file: scripts/preview.sh
  why: GUARD 1/2/3 — the 3 supersede re-checks of STATE_PREVIEW_SEQ (the early bump exploits GUARD 2).
  pattern: GUARD 2 sits BEFORE the unlink-window (the first mutation); a stale job that sees
           seq != its captured expected_seq returns 0 there and touches NO window.
  gotcha: DO NOT modify preview.sh. The early bump makes the existing guards sufficient.

- file: scripts/state.sh
  why: STATE_PREVIEW_SEQ / STATE_SCROLL / STATE_CLIENT_WIDTH constants + get_state/set_state signatures.
  gotcha: get_state "$KEY" "${default:-}" / set_state "$KEY" "$value". Do NOT touch state.sh.

- file: tests/test_responsiveness.sh
  why: test_superseded_preview_noop (the failing test) + the seq assertions that constrain the design.
  critical: seq is asserted ONLY on the TYPE path (test_rapid_type_confirm_no_backlog expects seq==3
            after 3 types; test_preview_defer_off_synchronous expects seq==0 after a defer=off type).
            NO test asserts seq after NAV. This is WHY the early invalidation is nav-only + defer-gated.

- file: tests/test_scroll_width.sh
  why: defer=off scroll suite (advances on nav, clamps when fits, resets on type/backspace/cancel).
  gotcha: runs defer=off (helpers.sh pins it) → the defer=on gate makes the fix a no-op here →
          scroll behavior is provably unaffected.

- docfile: plan/003_77ef311abf10/architecture/codebase_patterns.md
  why: §P5 (all preview work routes through _lp_preview_follow — NOT bypassed by this change),
       §P7 (shared lp_viewport), §P1 (sourced-library contract), §P8 (defer=off test pin).
```

### Current Codebase tree (focus)

```bash
scripts/
  input-handler.sh   # THE SUT — single file edited by this PRP (already has scroll wiring)
  preview.sh         # GUARD 1/2/3 supersede re-checks (READ-ONLY here)
  layout.sh          # lp_viewport (sourced by input-handler; READ-ONLY here)
  rank.sh            # lp_rank (sourced; READ-ONLY here)
  state.sh           # STATE_* keys + get_state/set_state (READ-ONLY here)
tests/
  test_responsiveness.sh   # test_superseded_preview_noop (the gate), seq==3/seq==0 constraints
  test_scroll_width.sh     # defer=off scroll behavior (must stay green)
  run.sh                   # entry point (sources all test_*.sh; runs each on a fresh socket)
```

### Desired Codebase tree with files to be added/changed

```bash
scripts/input-handler.sh   # MODIFIED ONLY — +_lp_invalidate_pending_preview helper, +2 nav call sites
# (no new files; no other file touched)
```

### Known Gotchas of our codebase & Library Quirks

```bash
# CRITICAL: tmux round-trips are not free. Every get_state/set_state/opt_*/refresh-client is a
# synchronous tmux show-option/set-option round-trip that PUMPS the server event loop, which RUNS
# pending `run-shell -b` background jobs (the deferred preview fires). This is the ENTIRE root cause.
# The fix is NOT "fewer round-trips on nav" (the scroll reads are required by the contract) — it is
# "invalidate stale fires FIRST so the round-trips that follow cannot let one leak".

# CRITICAL: keep the early invalidation nav-only + defer-gated. Adding it to the type/backspace path
# breaks test_rapid_type_confirm_no_backlog (it asserts @livepicker-preview-seq == 3 after 3 types —
# one bump per type). The type path's supersession is untested and out of scope (see research §5).

# GOTCHA: _lp_fire_preview bumps the seq and captures it for ITS OWN fire. The early invalidation
# bumps it once more (a "spent" number). This is intentional — do NOT try to de-duplicate the bumps.
# preview.sh's guards compare expected_seq == current_seq (equality), so a gap in the counter is harmless.

# GOTCHA: the failing test is timing-sensitive. A single green run of tests/run.sh is NOT proof —
# run it 5-10x. Attempt 1 passed Level 1 fully and STILL failed Level 2 every run.
```

## Implementation Blueprint

### Implementation Tasks (ordered by dependencies)

```yaml
Task 1: ADD the _lp_invalidate_pending_preview helper to scripts/input-handler.sh
  - INSERT immediately BEFORE the existing comment line:
        # _lp_fire_preview TARGET — schedule a background, supersedeable preview of TARGET
    (the _lp_fire_preview function definition — currently ~line 169).
  - PLACE it alongside the other _lp_* helpers (sourced-library convention; pure function, no side
    effects at definition time). It is a NAV-path helper, defined before input_main() like its siblings.
  - EXACT CODE (copy verbatim — tabs for indentation inside the function, the helper itself is
    column-0 like _lp_fire_preview/_lp_scroll_into_view):

    # _lp_invalidate_pending_preview — bump STATE_PREVIEW_SEQ FIRST (defer=on only) so any in-flight
    # background preview fire (run-shell -b from a prior keystroke/nav) is marked stale BEFORE the nav
    # path performs any tmux round-trips. Each tmux round-trip pumps the server event loop, which
    # ADVANCES pending -b jobs; bumping the seq up front means a stale fire re-checks the seq in
    # preview.sh (GUARD 2, before the unlink) and NO-OPS, regardless of how many round-trips the
    # scroll-into-view / reads add afterward. defer=off runs preview.sh INLINE (no -b job, no race)
    # -> the gate makes this a no-op. _lp_fire_preview (called later via _lp_preview_follow) bumps
    # AGAIN and captures the final seq for THIS nav's fire — the early bump is a pure invalidation
    # signal (one "spent" seq number; the seq guards compare equality, so gaps are harmless).
    # RACE-FIX for the scroll-into-view wiring (P1.M3.T2.S1 attempt 2). See research/race_fix_findings.md.
    _lp_invalidate_pending_preview() {
    	[ "$(opt_preview_defer)" = "on" ] || return 0
    	local s
    	s="$(get_state "$STATE_PREVIEW_SEQ" "0")"
    	set_state "$STATE_PREVIEW_SEQ" "$(( s + 1 ))"
    }

  - NAMING: _lp_ prefix (matches _lp_fire_preview / _lp_preview_follow / _lp_scroll_into_view).
  - DEPENDENCIES: opt_preview_defer (options.sh), get_state/set_state + STATE_PREVIEW_SEQ (state.sh)
    — ALL already sourced at the top of input-handler.sh. No new source line needed.

Task 2: CALL _lp_invalidate_pending_preview as the FIRST statement of next-session)
  - IN scripts/input-handler.sh, the `next-session)` branch (currently ~line 285) begins:
        next-session)
            # --- P1.M6.T2.S1: move the highlight DOWN within the FILTERED list
  - INSERT, as the FIRST executable line of the branch (right after `next-session)` and BEFORE the
    `# --- P1.M6.T2.S1` comment is fine, OR immediately after it — the only requirement is it runs
    BEFORE the first `get_state "$STATE_LIST"` read). Recommended exact insertion (immediately after
    the `next-session)` line):

        next-session)
            # RACE FIX: invalidate any pending background preview fire FIRST, before the nav path's
            # tmux round-trips (reads + scroll-into-view) pump the server loop and advance a stale
            # -b fire toward its GUARD 2 mutation. _lp_fire_preview below bumps again for THIS nav's
            # own fire. (defer=off -> no-op: inline preview.)
            _lp_invalidate_pending_preview
            # --- P1.M6.T2.S1: move the highlight DOWN within the FILTERED list
            ...existing body unchanged (the get_state reads, lp_rank, set_state INDEX,
               _lp_scroll_into_view, _lp_preview_follow all stay exactly as committed)...

Task 3: CALL _lp_invalidate_pending_preview as the FIRST statement of prev-session)
  - MIRROR of Task 2 on the `prev-session)` branch (currently ~line 321). Insert as the first
    executable line after `prev-session)`:

        prev-session)
            # RACE FIX: invalidate any pending background preview fire FIRST (mirror next-session).
            # _lp_fire_preview below bumps again for THIS nav's own fire.
            _lp_invalidate_pending_preview
            # --- P1.M6.T2.S1: move the highlight UP within the FILTERED list
            ...existing body unchanged...

Task 4: VERIFY no other change is needed
  - CONFIRM (grep) the scroll wiring from attempt 1 is present and unmodified:
      * `source "$CURRENT_DIR/layout.sh"` present (1 occurrence).
      * `_lp_scroll_into_view` defined once + called at 2 nav sites.
      * `set_state "$STATE_SCROLL" "0"` present at 3 sites (type / backspace / cancel-clear).
  - CONFIRM no edit to preview.sh / state.sh / layout.sh / rank.sh / any tests/* file.
  - DO NOT add _lp_invalidate_pending_preview to type / backspace / cancel / confirm / refresh-width.
```

### Implementation Patterns & Key Details

```bash
# The nav branch order AFTER this change (next-session, mirror for prev):
#   1. _lp_invalidate_pending_preview   <-- NEW: bumps seq, invalidates stale fires (defer=on)
#   2. get_state LIST / FILTER          <-- reads now happen POST-invalidation (safe)
#   3. lp_rank -> filtered[]
#   4. get_state INDEX; set_state INDEX new_idx
#   5. _lp_scroll_into_view new_idx filtered   <-- the 2 get_state reads here can no longer leak
#   6. _lp_preview_follow target        <-- refresh-client -S; _lp_fire_preview bumps seq AGAIN
#                                            and fires THIS nav's preview with the final seq

# WHY the order matters: steps 2-5 perform tmux round-trips. Before this fix they all ran while a
# stale prior-nav fire could still be alive (seq not yet bumped). By bumping at step 1, steps 2-6
# execute with the stale fire already marked superseded -> preview.sh GUARD 2 no-ops it.

# Round-trip budget (why 3 early round-trips is safe): the early bump persists after 3 round-trips
# (opt_preview_defer + seq read + seq set). Those are the ONLY round-trips a stale fire can exploit;
# everything after is post-invalidation. The clean (pre-task) nav path tolerates ~6 round-trips before
# its (late) bump and passed; 3 < 6, so this is strictly SAFER. Verified 10/10 green this session.
```

### Integration Points

```yaml
# NONE new. This change reuses existing seams only:
STATE:
  - reads/writes: STATE_PREVIEW_SEQ (existing key, state.sh); get_state/set_state (existing API).
OPTIONS:
  - reads: opt_preview_defer (existing accessor, options.sh).
PREVIEW:
  - _lp_preview_follow / _lp_fire_preview / preview.sh GUARDs: ALL UNCHANGED (do not edit them).
SCROLL:
  - _lp_scroll_into_view + STATE_SCROLL writes: ALREADY shipped (attempt 1), left as-is.
```

## Validation Loop

### Level 1: Syntax & Style (Immediate Feedback)

```bash
# Run after the 3 edits — fix before proceeding.
bash -n scripts/input-handler.sh                 # syntax; expect no output (clean)
shellcheck scripts/input-handler.sh              # lint; expect no new warnings
# Confirm the fix is present and the scroll wiring is intact:
grep -c '_lp_invalidate_pending_preview' scripts/input-handler.sh   # expect >= 3 (1 def + 2 calls)
grep -c 'source "$CURRENT_DIR/layout.sh"' scripts/input-handler.sh  # expect 1
grep -c '_lp_scroll_into_view' scripts/input-handler.sh             # expect 3 (1 def + 2 calls)
grep -c 'set_state "$STATE_SCROLL" "0"' scripts/input-handler.sh    # expect 3 (type/bs/cancel-clear)
# Expected: all counts as above. The file should diff from HEAD by only +1 helper def + 2 call lines
#           (+ their comments). `git diff --stat scripts/input-handler.sh` shows a small additive delta.
```

### Level 2: Unit / Integration Tests (the gate that attempt 1 failed)

```bash
# The race is timing-sensitive — run the WHOLE suite MULTIPLE times. One pass is NOT enough.
for i in $(seq 1 10); do bash tests/run.sh 2>&1 | tail -1 | sed "s/^/RUN $i: /"; done
# Expected: every run prints "77 passed, 0 failed (of 77)".
# CRITICAL test that MUST pass every run:
bash tests/run.sh 2>&1 | grep -E 'superseded_preview_noop|rapid_type_confirm|scroll_(advances|clamps|resets)'
# Expected: all PASS; in particular test_superseded_preview_noop is PASS (it FAILed 3/3 on HEAD pre-fix).
# If test_superseded_preview_noop still fails: the early invalidation is missing/misplaced on a nav
#   branch, or the gate is wrong (must be defer=on, called BEFORE the first get_state). Re-read Task 1-3.
# If test_rapid_type_confirm_no_backlog fails with seq != 3: you accidentally added the invalidation
#   to the TYPE path — remove it (type stays untouched; see Known Gotchas).
# If a test_scroll_width.sh case fails: you altered defer=off nav behavior — the gate must be
#   `[ "$(opt_preview_defer)" = "on" ] || return 0` exactly.
```

### Level 3: Behavioral spot-check (scroll actually moves)

```bash
# (Optional, already covered by test_scroll_width.sh, but useful to reason about.) The scroll suite
# runs defer=off (helpers.sh pins it), where the gate is a no-op — so it proves the scroll math itself
# is intact and the fix did not perturb defer=off nav:
bash tests/run.sh 2>&1 | grep -E 'scroll_advances_on_nav|scroll_clamps_zero|scroll_resets_on_(type|backspace|cancel)'
# Expected: all PASS. scroll advances on nav (>0), clamps to 0 when the list fits, resets to 0 on
#           type/backspace/cancel-clear.
```

### Level 4: Race-robustness stress (confidence, not a hard gate)

```bash
# Because the failure is a race, lean on repetition. 10 clean consecutive full-suite runs (Level 2)
# is the real signal. There is no faster isolated repro than the suite's test_superseded_preview_noop
# (it already fires the two rapid navs on a fresh isolated socket). Do NOT add sleeps or test changes.
```

## Final Validation Checklist

### Technical Validation
- [ ] `bash -n scripts/input-handler.sh` clean.
- [ ] `shellcheck scripts/input-handler.sh` introduces no new warnings.
- [ ] `tests/run.sh` passes 77/77 on **5–10 consecutive runs** (not one).
- [ ] `git diff --stat` shows ONLY `scripts/input-handler.sh` changed (no preview.sh/state.sh/tests).
- [ ] grep counts match Task 4 expectations.

### Feature Validation
- [ ] `test_superseded_preview_noop` PASSES every run (the gate this PRP exists to fix).
- [ ] `test_rapid_type_confirm_no_backlog` still PASS (seq==3 — type path untouched).
- [ ] `test_scroll_width.sh` cases PASS (defer=off scroll behavior intact).
- [ ] Scroll-into-view on nav + scroll reset on type/backspace/cancel-clear behave per PRD §19 §3.32.

### Code Quality Validation
- [ ] Follows the existing `_lp_*` helper convention (naming, placement, pure definition).
- [ ] No new source line beyond what attempt 1 already added (layout.sh already sourced).
- [ ] The defer=on gate is present and exact (`[ "$(opt_preview_defer)" = "on" ] || return 0`).
- [ ] `_lp_fire_preview` is NOT refactored (the double-bump is intentional).

### Scope Discipline
- [ ] ONLY `scripts/input-handler.sh` modified.
- [ ] The type/backspace/cancel-clear/confirm/refresh-width branches are NOT given the early invalidation.

---

## Anti-Patterns to Avoid

- ❌ Don't "optimize" by merging the two seq bumps or refactoring `_lp_fire_preview` to skip its bump —
  the double-bump is the design (early invalidation + per-fire capture). The seq guards compare equality;
  a spent number is harmless.
- ❌ Don't drop the `defer=on` gate to "save a round-trip" — it keeps defer=off nav byte-for-byte unchanged
  (zero risk to ~40 defer=off tests) and is self-documenting. 3 early round-trips is provably safe (10/10).
- ❌ Don't add the invalidation to the type path "for consistency" — it breaks `seq==3`.
- ❌ Don't widen `test_superseded_preview_noop` or add sleeps — the test is correct (a stale fire MUST
  no-op); the early-bump fix keeps it strict. The fix is the right answer, not a test relaxation.
- ❌ Don't move scroll-into-view to the renderer / drop the nav scroll write — that contradicts PRD §19
  §3.32 and the task contract (input-handler is the authoritative scroll writer).
- ❌ Don't trust a single green `tests/run.sh` run — the failure is a race; run it repeatedly.

---

## Confidence Score: 9/10

The fix is verified empirically this session: applied the exact 3 edits to a clean HEAD checkout of
`scripts/input-handler.sh`, ran `bash tests/run.sh` **10× → 77/77 every run** (including the previously
failing `test_superseded_preview_noop` and the seq-constraining `test_rapid_type_confirm_no_backlog`),
then `git checkout`-reverted the source to leave the tree clean for the implementer. The −1 is residual
race-timing risk on other tmux/CI machines; the 10-repeat Level-2 loop is the mitigation. Full proof in
`research/race_fix_findings.md`.
