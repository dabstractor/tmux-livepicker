# Implementation Issue Feedback (Attempt 1/3)

The previous implementation attempt encountered an issue that requires re-planning.

## Issue Details

tests/test_pane_immutability.sh is complete and correct: 4 of 5 tests PASS (a no_candidate_pane_movement, b no_status_grow_reflow, c no_confirm_side_effects, e snapshot_mode_invariant_holds), Levels 1/3/4/5 pass, and the full suite is 100/101 (only test d fails). Test (d) test_original_window_intact CANNOT pass as specified by the PRP due to a fundamental flaw in the plan's premise: the PRP assumes the §22 driver clip (scripts/livepicker.sh T3 b.5, line 345) pins ORIG_WINDOW byte-identical, but the clip pins HEIGHT ONLY (resize-window -y). On tmux 3.6b with aggressive-resize on (the default), once the harness's 3 baseline sessions + the test's candidate sessions (immA/immB) reach >=4 sessions, `set-option -t driver window-size manual` reverts ORIG_WINDOW from 80-wide (client-fitted) to 120-wide (creation size); the clip restores height (23) but never width, so ORIG_WINDOW ends 120x23. This breaks BOTH test (d) asserts (geom_pre==geom_post AND snapshot==cur_in_picker). I proved via isolated probes that pinning BOTH width and height (resize-window -x 80 -y 23, the gate §3/ARM C recipe) makes test (d) pass byte-identically — so the root cause is the §22 clip's height-only pin, a production-code gap, NOT the test logic. The PRP forbids editing scripts ('Adds NO production code', 'SCOPE = tests/ ONLY'), forbids weakening the byte-identity asserts, AND mandates creating the immA/immB candidates that cross the 4-session threshold. These three constraints are unsatisfiable together for test (d). The test is correctly catching a real §23 regression; the fix belongs in scripts/livepicker.sh (pin width too), which is out of scope for this TEST-ONLY task. Recommended follow-up: a production task to extend the §22 clip to pin both width and height per gate §3.

## Full Agent Output

I have completed exhaustive analysis. Here is my report.

---

## Result: `issue` — Fundamental flaw found in the PRP plan for test (d); 4 of 5 tests pass.

### What I delivered

`tests/test_pane_immutability.sh` exists and is complete: **5 `test_*` functions** (a–e) + `lp_immut_*` helpers, mirroring `test_window_flip.sh`'s header/lifecycle/capture idiom, using the gate §4 assert shape (`window_layout` + sorted `list-panes` byte-identical), with NO test-side pre-sizing, real attached client in every test, snapshot read during the picker, candidate names `immA`/`immB` collision-free.

### Validation gate results

| Level | Result |
|---|---|
| **L1** Syntax & style | ✅ `shellcheck` clean, `bash -n` clean, 5 `test_*` + helpers, no lifecycle leaks, run.sh glob discovers it |
| **L2** The 5 tests | ⚠️ **4 PASS** (a, b, c, e), **1 FAIL** (d `test_original_window_intact`) |
| **L3** Full suite | ✅ 100 passed / 1 failed (of 101) — the 1 failure is test (d); all siblings (test_preview_clip, test_window_flip, test_restore, test_pollution) green |
| **L4** Non-pollution | ✅ Real tmux server byte-identical before/after (socket isolation holds) |
| **L5** Domain checks | ✅ gate §4 shape present, no pre-sizing (only a doc comment mentions `lp_winflip_match_size`), names collision-free, snapshot read before cancel |

### The fundamental issue (test d) — explained at a 10th-grade level

**The PRP assumed the "§22 clip" (a piece of the plugin's production code) freezes the driver's original window so it can't change shape. That assumption is false when the test creates its candidate sessions.**

Here's the chain, which I verified with isolated probes:

1. The test starts the driver with a real 80-wide client, so the driver's active "extra" window is **80 wide × 23 tall**.
2. The baseline harness already creates 3 sessions (driver, alpha, beta). The test then creates candidate `immA` (+ `immB`) → **4–5 sessions total**.
3. On activate, the §22 clip runs `tmux set-option -t driver window-size manual`. On tmux 3.6b with `aggressive-resize on` (**the default**), once there are ≥4 sessions, that single command **reverts the driver's window to its creation size: 120 wide × 40 tall**.
4. The clip then runs `resize-window -y 23` — it re-pins the **height** back to 23, but it **never re-pins the width**. So the window ends up **120 wide × 23 tall**.
5. Result: ORIG_WINDOW changed from 80-wide to 120-wide. So:
   - `geom_pre == geom_post` **FAILS** (80-wide `4a2d` → 120-wide `5f6f`).
   - `snapshot == cur_in_picker` **FAILS** (snapshot captured pre-activate = 80-wide panes; in-picker re-capture = 120-wide panes) → the drift gate sees "drift" and runs `select-layout`, exactly the path the test is supposed to prove is a no-op.

**Why `test_preview_clip.sh` passes but this fails:** those tests never create a 4th session, so they stay under the threshold and the clip holds. The PRP author wrote "test (d) depends on the §22 clip pinning the driver … proven by test_preview_clip" — but test_preview_clip never crosses the 4-session line, so it never exposed this gap.

### Proof the root cause is production code, not the test

I simulated the clip pinning **both** width and height (`resize-window -x 80 -y 23`, exactly the recipe the gate's §3/ARM C prescribes for the candidate/drift restores): both test (d) assertions then pass byte-identically (`4a2d,80x23` before and after, snapshot == current → YES). So the fix is a one-line production change in `scripts/livepicker.sh` (line 345): pin width too. **But the PRP explicitly forbids editing any script** ("Adds NO production code", "SCOPE = tests/test_pane_immutability.sh ONLY").

### Why I halted instead of "fixing" it

The PRP's rules collide for test (d), with no test-only escape:
- **Forbidden** to edit production code (the §22 clip width gap).
- **Forbidden** to weaken the byte-identity asserts ("a failure here is a real §23 regression the suite exists to catch").
- **Forbidden** to pre-size ORIG_WINDOW to 120 (that's pre-sizing + it hides the regression).
- The PRP **mandates** creating `immA` + `immB` (which crosses the 4-session threshold that triggers the bug).

So test (d) **cannot pass as specified** without a production-code fix that is out of scope for this TEST-ONLY task. The test is doing exactly its job — catching a real §23 regression (the §22 clip's height-only pin) — but the regression lives in `scripts/`, which this task is not allowed to touch.

### Recommended next step (for the orchestrator / a follow-up production task)

File a sibling task to fix the **§22 driver clip** in `scripts/livepicker.sh` T3 (b.5): capture `lp_fit_pre_w` alongside `lp_fit_pre_h` and pin **both** dims (`resize-window -x "$lp_fit_pre_w" -y "$lp_fit_pre_h" -t "$lp_fit_win"`) — the gate's §3/ARM C "both dimensions" recipe. Once that lands, `test_original_window_intact` passes with zero test changes. This is consistent with the gate's own verdict that "height-only is not a general restore."

```json
{
  "result": "issue",
  "message": "tests/test_pane_immutability.sh is complete and correct: 4 of 5 tests PASS (a no_candidate_pane_movement, b no_status_grow_reflow, c no_confirm_side_effects, e snapshot_mode_invariant_holds), Levels 1/3/4/5 pass, and the full suite is 100/101 (only test d fails). Test (d) test_original_window_intact CANNOT pass as specified by the PRP due to a fundamental flaw in the plan's premise: the PRP assumes the §22 driver clip (scripts/livepicker.sh T3 b.5, line 345) pins ORIG_WINDOW byte-identical, but the clip pins HEIGHT ONLY (resize-window -y). On tmux 3.6b with aggressive-resize on (the default), once the harness's 3 baseline sessions + the test's candidate sessions (immA/immB) reach >=4 sessions, `set-option -t driver window-size manual` reverts ORIG_WINDOW from 80-wide (client-fitted) to 120-wide (creation size); the clip restores height (23) but never width, so ORIG_WINDOW ends 120x23. This breaks BOTH test (d) asserts (geom_pre==geom_post AND snapshot==cur_in_picker). I proved via isolated probes that pinning BOTH width and height (resize-window -x 80 -y 23, the gate §3/ARM C recipe) makes test (d) pass byte-identically — so the root cause is the §22 clip's height-only pin, a production-code gap, NOT the test logic. The PRP forbids editing scripts ('Adds NO production code', 'SCOPE = tests/ ONLY'), forbids weakening the byte-identity asserts, AND mandates creating the immA/immB candidates that cross the 4-session threshold. These three constraints are unsatisfiable together for test (d). The test is correctly catching a real §23 regression; the fix belongs in scripts/livepicker.sh (pin width too), which is out of scope for this TEST-ONLY task. Recommended follow-up: a production task to extend the §22 clip to pin both width and height per gate §3."
}
```

## Instructions

Review this feedback and create a revised PRP that addresses the issue.
If the issue is fundamentally impossible to resolve, output `"result": "fail"` with an explanation.
