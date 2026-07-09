name: "P3.M1.T1.S1 — Clip verification on tmux 3.6b + clip-vs-reflow default decision"
description: Research/verification work item. Run a reproducible, harness-isolated experiment that mirrors the real `activate` ordering (freeze → grow status → self-window preview → candidate nav re-link) on tmux 3.6b, capture deterministic `window_layout` diffs, and write the decision + corrected freeze recipe to `architecture/clip_verification.md`. This GATES P3.M1.T2 (the freeze implementation).

---

## Goal

**Feature Goal**: Empirically settle, on the installed **tmux 3.6b**, whether the PRD §22 "clip" preview-sizing strategy is feasible as the shipped `@livepicker-preview-fit` default — i.e. whether freezing the driver's active (self/preview) window **before** the status grow prevents that window from reflowing — and record the decision plus the exact freeze recipe that the gated implementation (P3.M1.T2) must use.

**Deliverable**: Two artifacts, BOTH written by the implementing agent (NOT by this PRP author):
1. `plan/003_77ef311abf10/P3M1T1S1/research/clip_verify_probe.sh` — a self-contained, reproducible probe script (sourced-executable bash; sources `tests/setup_socket.sh`) that runs the control/treatment/candidate experiments against an isolated `-L` socket with an attached client and prints the raw `window_layout`/`window_height` evidence.
2. `plan/003_77ef311abf10/architecture/clip_verification.md` — the decision document: verdict (clip default YES/NO), the corrected freeze recipe, the verbatim evidence, the residual (linked-candidate link-time resize), the gotchas, and an explicit "GATES P3.M1.T2" statement.

**Success Definition**: `clip_verification.md` states unambiguously whether `clip` ships as default, documents the residual linked-candidate behavior (reconciled with the README "Detached candidate windows are resized" limitation), records the EXACT freeze recipe P3.M1.T2 must implement, and the probe script reproduces byte-identical `window_layout` strings across two independent runs while leaving the user's real tmux server (`/usr/bin/tmux list-sessions`) byte-identical before/after.

## User Persona

**Target User**: The P3.M1.T2 implementer (the very next agent) and any future maintainer reasoning about preview sizing.

**Use Case**: Opening `clip_verification.md` to learn, in one screen, (a) is clip the default, (b) what exact tmux commands produce a non-reflowing self-window, (c) what jank remains (the residual) and why it is accepted.

**Pain Points Addressed**: The PRD §22 "Mechanism (intended)" says the freeze is `set-option window-size manual` then grow status. That recipe, taken literally, FAILS on 3.6b (the window still reflows). This verification closes that gap so P3.M1.T2 does not implement a known-broken recipe.

## Why

- PRD §22 and §16 ("Preview clip feasibility (load-bearing, section 22)") both mark clip behavior as **version-dependent and unverified** and require empirical confirmation on 3.6b before it ships. This task is that confirmation; it is the explicit gate on P3.M1.T2.
- The existing `architecture/empirical_findings.md` Finding 2 is **partially wrong**: it claims `window-size manual` "protects" the self-session window from the status grow ("it does not dramatically reflow"). A fresh probe (see `research/clip_probe_findings.md`, already in the research dir) shows `manual` ALONE leaves the window reflowing 23→22. The load-bearing mechanism is an explicit `resize-window -y <pre-grow-height>` pin. `clip_verification.md` must record this correction so the implementation uses the proven recipe.
- The residual (a linked candidate undergoes a one-time link-time resize, and its source view is also resized because the window is shared) is the already-documented limitation (README "Detached candidate windows are resized during preview"; CHANGELOG bugfix-001 "Detached candidate resize"). The decision doc reconciles clip with that limitation rather than claiming clip eliminates all reflow.

## What

A reproducible experiment + a decision document. The experiment uses ONLY the project's own harness (`tests/setup_socket.sh` `setup_socket`/`teardown_socket`/`attach_test_client`) against an **isolated `-L` socket**, never the user's real server. It mirrors the real `activate` ordering (PRD §22 Mechanism + `scripts/livepicker.sh` activate T3 "grow status bar") reproduced with raw tmux primitives, because the freeze itself is not implemented yet (it is P3.M1.T2) — so driving the real `livepicker.sh` activate now would show the unfixed REFLOW (the control), while the treatment applies the candidate freeze recipe by hand.

### Success Criteria

- [ ] `clip_verify_probe.sh` exists in `research/`, sources `tests/setup_socket.sh`, runs to completion, and is deterministic (two independent invocations emit byte-identical `window_layout` strings).
- [ ] **Control** (no freeze): with an attached client + a multi-pane driver window, growing `status` 1→2 changes `window_layout`/`window_height` (the reflow/jank is reproduced). Recorded with the verbatim before/after strings.
- [ ] **Treatment** (freeze recipe applied BEFORE the grow): `window_layout` is **byte-identical** before vs after the status grow; `window_height` unchanged. This is the clip proof.
- [ ] **Per-session isolation**: `set-option -t driver window-size manual` sets only `driver` (alpha shows empty, global `window-size` is untouched). Recorded.
- [ ] **Candidate residual**: a candidate linked AFTER the status is grown undergoes a one-time link-time resize to the driver's usable size; navigating to a second candidate and back produces **no per-nav additional reflow** on the first; the candidate's SOURCE view is also resized (shared window). All recorded.
- [ ] `clip_verification.md` states the verdict (clip default YES or NO), the corrected freeze recipe, the residual, and an explicit "GATES P3.M1.T2: implement `<recipe>`" line.
- [ ] Real tmux server (`/usr/bin/tmux list-sessions -F '#{session_name}' | sort`) is byte-identical before/after the whole probe.

## All Needed Context

### Context Completeness Check

_"If someone knew nothing about this codebase, would they have everything needed to implement this successfully?"_ — Yes. This PRP pins the exact harness contract, the exact (already-probed) command sequence, the exact gotchas that broke the first probe passes, the exact output doc structure (mirroring the sibling `empirical_findings.md`), and the exact decision criteria. No guessing about tmux behavior is required; the probe script merely confirms what the cited research already established.

### Documentation & References

```yaml
# MUST READ — load into the context window before writing anything.

- file: plan/003_77ef311abf10/P3M1T1S1/research/clip_probe_findings.md
  why: THE primary evidence. A prior probe ALREADY ran this exact experiment on
        this box (tmux 3.6b) and recorded verbatim window_layout strings + a
        7-condition matrix (A-G). It found manual ALONE fails; resize-window pins.
        Your probe must reproduce this; your doc records it.
  critical: "Headline: manual ALONE reflowed 23->22 (cond B). manual + resize-window
        -y 23 gave byte-identical layout (cond C). resize-window -y 23 WITHOUT manual
        ALSO pinned (cond F). Global manual jumped to 40 (cond G) — never use -g.
        Linked candidate: one-time link-time resize to 22, no per-nav reflow, source
        view also became 22."

- file: plan/003_77ef311abf10/P3M1T1S1/research/tmux_window_size_docs.md
  why: External semantics (tmux man page / CHANGES / source) backing the decision.
        window-size is a SESSION option (so -t isolates); manual leaves the window
        alone (clip top-left); a linked window has ONE shared size and ANY non-manual
        session viewing it as current will resize it for everyone.
  section: "§1 four values; §2 session scope; §4 shared/linked sizing; §5 window_layout
        changes on reflow (good for diffing, cannot distinguish reflow from structural)"

- file: plan/003_77ef311abf10/architecture/empirical_findings.md
  why: The doc you are EXTENDING and CORRECTING. Finding 1 (resize-window -y 30 clips
        oversized non-shared window — CONFIRMED, keep). Finding 2 (manual 'protects'
        self-window — OVERLY OPTIMISTIC, your doc must correct it: manual alone does
        NOT pin on 3.6b; the resize-window pin is load-bearing). Findings 3/4/5
        (delete leak, client_width, etc.) are out of scope — do not restate them.
  gotcha: "Do NOT delete/rewrite empirical_findings.md (read-only research history).
        Your correction lives in clip_verification.md, which REFERENCES Finding 2 and
        supersedes it for the freeze question."

- file: tests/setup_socket.sh
  why: THE harness. Provides setup_socket/teardown_socket (isolated -L server, shim,
        cleanup), attach_test_client/detach_test_client (script-pty client), and
        documents the baseline fixtures (driver/alpha/beta at -x 120 -y 40). Your
        probe script sources this; nothing else.
  pattern: "attach_test_client spawns `script -qec \"tmux attach -t '<sess>'\"` and
        sleeps 0.5s. The pty reports 80x24 (NOT 120x40) — see gotcha. teardown_socket
        kills the server + removes the shim dir + the orphan socket file."

- file: tests/helpers.sh
  why: Assertion helpers (fail/assert_eq/assert_contains) IF you choose to make the
        probe assert rather than just print. Optional — a print-evidence probe is
        equally valid for a research artifact. setup_test/teardown_test are thin
        delegates you may use instead of raw setup_socket/teardown_socket.

- file: scripts/livepicker.sh   # activate T3 block, ~lines 230-280
  why: The REAL status-grow ordering your experiment mirrors. T3 shifts status-format
        indices highest-first, installs the renderer, then grows `status` via a
        normalized case (on->2, 2->n+1, etc.). Your freeze recipe slots in
        IMMEDIATELY BEFORE that status grow — this ordering is the whole point of the
        experiment.
  pattern: "orig_status via get_state; case 'on' => `set-option -g status 2`. Your
        treatment applies the freeze BEFORE this set-option -g status 2 line's analog."

- file: PRD.md  # §22 "Preview sizing: clip instead of reflow" + §16 risk note
  why: The spec. §22 "Mechanism (intended)" says the freeze is window-size manual then
        grow — your verification shows that is insufficient on 3.6b and the corrected
        recipe adds resize-window. §22 "Verification required (load-bearing)" lists the
        three bullets you are confirming. §16 "Preview clip feasibility" is the risk
        note your doc resolves.

- file: README.md  # lines ~187-193 "Detached candidate windows are resized during preview"
  why: The residual you reconcile against. Your doc must state clip does NOT eliminate
        this; the link-time resize + source disturbance ARE this limitation, accepted.
```

### Current Codebase tree (run `ls` in the project root)

```
tmux-livepicker/
├── scripts/          # plugin runtime (livepicker.sh=activate, preview.sh=link, restore.sh, ...)
├── tests/            # harness: setup_socket.sh, helpers.sh, run.sh + test_*.sh
├── plan/003_77ef311abf10/
│   ├── architecture/         # empirical_findings.md (EXTEND/CORRECT), codebase_patterns.md, system_context.md
│   └── P3M1T1S1/
│       ├── PRP.md            # THIS file
│       └── research/         # clip_probe_findings.md, tmux_window_size_docs.md (DONE) + YOUR clip_verify_probe.sh
├── PRD.md            # §22, §16 (read-only)
├── README.md         # "Detached candidate windows are resized" limitation (read-only)
└── CHANGELOG.md      # bugfix-001 "Detached candidate resize" (read-only)
```

### Desired Codebase tree with files to be added

```bash
plan/003_77ef311abf10/P3M1T1S1/research/clip_verify_probe.sh   # ADD — reproducible experiment script
plan/003_77ef311abf10/architecture/clip_verification.md        # ADD — the decision doc (GATES P3.M1.T2)
```

`clip_verify_probe.sh` responsibility: source `tests/setup_socket.sh`, run the control + treatment + candidate experiments on a FRESH isolated socket with an attached client, print verbatim `window_layout`/`window_height` evidence + PASS/FAIL lines, leave the real server untouched. Re-runnable (`bash .../clip_verify_probe.sh`).

`clip_verification.md` responsibility: state the clip default verdict; record the corrected freeze recipe; embed the verbatim evidence; document the residual; explicitly gate P3.M1.T2.

### Known Gotchas of our codebase & tmux 3.6b Library Quirks

```bash
# CRITICAL (probed, tripped the first passes):
# 1. The '=' exact-match prefix BREAKS set-option -t for SESSION options.
#    `set-option -t "=driver" window-size manual` -> "no such window: =driver" (rc=1).
#    Use the BARE session name for set-option: `set-option -t driver window-size manual`.
#    (The '=' prefix IS valid for list-windows/display-message/new-session/link-window, just NOT set-option.)

# 2. attach_test_client's `script` pty reports 80x24, NOT the session's -x 120 -y 40.
#    So an ATTACHED driver's usable height is 23 (status on=1 line; 24-1) and 22 (status 2).
#    Detached sessions (alpha/beta) keep their creation size 40 — which is why a linked
#    candidate comes in tall (40) and gets link-resized DOWN to 22. This is expected; do
#    not 'fix' it by resizing the pty.

# 3. Address windows by @id, NEVER index. After setup_socket, driver windows are at index
#    1 (@0 "driver") and 2 (@3 "extra"); `=driver:0` -> "can't find window: 0". Capture the
#    active window id dynamically: `tmux list-windows -t "=driver" -F '#{window_id}' -f '#{window_active}'`.
#    When a var holds '@3', write `-t "$WID"`, NOT `-t "@$WID"` (would become '@@3').

# 4. resize-window accepts a value LARGER than the client and that IS the clip
#    (tmux renders the top-left, clips overflow). resize-window -y 30 on a client-24 window
#    -> height 30, clipped. resize-window -y <current> -> pins current, no reflow.

# 5. window_height/window_layout only reflect the client-driven usable size WITH an attached
#    client. On a client-less socket they read the creation size (40). The clip experiment is
#    ONLY meaningful with attach_test_client. ALWAYS assert a client is attached before measuring
#    (the harness sleep 0.5 is sufficient; a too-fast probe sees list-clients empty).

# 6. NEVER set window-size with -g (global). Global manual disconnected the window from the
#    client entirely and jumped it to 40. Per-session -t "<sess>" only.

# 7. window_layout embeds per-node dimensions AND a 4-hex checksum prefix, so it CHANGES on
#    reflow. A byte-identical window_layout across the status grow is therefore a STRONG
#    no-reflow proof. (It cannot distinguish a reflow from a structural change, but our
#    experiment changes nothing structural, so identical == no reflow == no resize.)
```

## Implementation Blueprint

This is a research/verification task: there are no runtime data models or service classes. The "blueprint" is the experiment design + the output doc structure.

### Experiment design (control vs treatment vs candidate)

The decision is rigorous only if it shows the jank EXISTS without the fix (control) and DISAPPEARS with the fix (treatment). Run all three on FRESH `setup_socket` cycles with `attach_test_client`, diffing `window_layout`/`window_height`.

```bash
# Shared setup for each arm (control + treatment):
#   setup_socket                       # isolated -L server; driver/alpha/beta at 120x40
#   attach_test_client                 # script-pty client on driver (reports 80x24)
#   tmux split-window -h -t "=driver"  # make the self/preview window multi-pane
#   tmux split-window -v -t "=driver"
#   AW="$(tmux list-windows -t "=driver" -F '#{window_id}' -f '#{window_active}')"   # active @id
#
# CONTROL (reproduce the jank): no freeze, just grow status.
#   H0="$(tmux display-message -p -t "$AW" '#{window_height}')"; L0="...#{window_layout}'"
#   tmux set-option -g status 2; sleep 0.3
#   H1="..."; L1="..."
#   EXPECT: H0 != H1 (e.g. 23 -> 22) and L0 != L1  -> reflow CONFIRMED (the problem exists)
#
# TREATMENT (the clip recipe): freeze BEFORE the grow, then grow.
#   H0="$(... window_height)"  ; L0="$(... window_layout)"        # capture pre-grow
#   tmux set-option -t driver window-size manual                  # NO '=' prefix (gotcha #1)
#   tmux resize-window -y "$H0" -t "$AW"                           # LOAD-BEARING pin (gotcha #4)
#   tmux set-option -g status 2; sleep 0.3
#   H1="..."; L1="..."
#   EXPECT: H0 == H1 and L0 == L1  -> NO reflow = clip WORKS
#
#   (Optional robustness: grow again to status 3; assert still byte-identical -> pin survives.)
#
# CANDIDATE RESIDUAL (with status already grown to 2, self-window pinned):
#   tmux split-window -h -t "=alpha"
#   tmux link-window -s "alpha:." -t "driver:<free-idx>"; tmux select-window -t "driver:<linked>"
#   record linked candidate's window_height/window_layout in DRIVER
#   record alpha's OWN window_height/window_layout (source view)   -> expect both == usable (22)
#   link a SECOND candidate (beta), then re-select the alpha-linked window
#   EXPECT: alpha-linked window_layout byte-identical before/after the 2nd nav -> NO per-nav reflow
#
# teardown_socket after EACH arm. Assert /usr/bin/tmux (real server) byte-identical pre/post.
```

### Implementation Tasks (ordered by dependencies)

```yaml
Task 1: READ the cited research + harness + empirical_findings.md (NO writes)
  - READ: plan/003_77ef311abf10/P3M1T1S1/research/clip_probe_findings.md (the prior probe — your template)
  - READ: plan/003_77ef311abf10/P3M1T1S1/research/tmux_window_size_docs.md (semantics backing the why)
  - READ: plan/003_77ef311abf10/architecture/empirical_findings.md (Finding 1 keep; Finding 2 you correct)
  - READ: tests/setup_socket.sh (attach_test_client contract; gotchas #1,#2,#5)
  - READ: scripts/livepicker.sh activate T3 block (~lines 230-280) — the ordering you mirror
  - PURPOSE: internalize the verified recipe + gotchas so your probe/doc reproduce them exactly.

Task 2: CREATE plan/003_77ef311abf10/P3M1T1S1/research/clip_verify_probe.sh
  - IMPLEMENT: a `set -u` bash script. Header comment citing this PRP + clip_probe_findings.md.
    `source "$(cd "$(dirname "$0")/../../../.." && pwd)/tests/setup_socket.sh"` (resolve to repo root's tests/).
    Then a `main()` (or top-level) that, for EACH arm (control, treatment, candidate-residual):
      setup_socket <unique-name> ; attach_test_client ; <arm body from the design above> ; teardown_socket
    Print a labeled banner per arm + the verbatim window_layout/window_height strings + a PASS/FAIL line.
  - FOLLOW pattern: the prior probe used /tmp scripts; YOURS is a committed, re-runnable research artifact
    that sources the shipped harness (NOT hand-rolled tmux -L). Mirror tests/setup_socket_self_test's
    print style (banner + ok/bad lines).
  - NAMING: clip_verify_probe.sh. Functions arm_control / arm_treatment / arm_candidate if you factor them.
  - GOTCHAS (all 7 above): bare session name for set-option; do not assume 120x40 (pty is 80x24);
    capture active @id dynamically; sleep 0.3 after status grow + assert list-clients non-empty before measuring;
    NEVER -g for window-size; diff window_layout as the no-reflow proof.
  - PLACEMENT: plan/003_77ef311abf10/P3M1T1S1/research/clip_verify_probe.sh

Task 3: RUN clip_verify_probe.sh TWICE; capture both outputs to research/
  - RUN: `bash plan/003_77ef311abf10/P3M1T1S1/research/clip_verify_probe.sh > plan/003_77ef311abf10/P3M1T1S1/research/clip_verify_run1.log 2>&1`
    then a second time to `..._run2.log`.
  - VERIFY: run1 and run2 emit BYTE-IDENTICAL window_layout strings (determinism). If they differ, the
    experiment has nondeterminism — fix the settle timing / client-attached guard before proceeding.
  - VERIFY: both runs show the CONTROL reflowing (H0!=H1) and the TREATMENT pinned (L0==L1). If the
    treatment does NOT pin, that is a real negative result — record it honestly (see Anti-Patterns).

Task 4: CREATE plan/003_77ef311abf10/architecture/clip_verification.md  (THE deliverable)
  - IMPLEMENT: the decision document. Use the empirical_findings.md STYLE (decision box table, numbered
    sections, verbatim evidence, summary). Required sections (see Template below):
      1. Decision box (clip default YES/NO + one-line why).
      2. Correction note: manual ALONE is insufficient on 3.6b; resize-window -y H0 is load-bearing.
         Explicitly supersede empirical_findings.md Finding 2 for the freeze question (reference it; do not edit it).
      3. The experiment: control (reflow reproduced) + treatment (clip proven) with verbatim window_layout strings
         (cite research/clip_verify_run1.log). Per-session isolation result.
      4. The corrected freeze recipe (exact commands, in order) + the restore recipe.
      5. The residual: linked-candidate one-time link-time resize + source-view disturbance; NO per-nav reflow.
         Reconcile with README "Detached candidate windows are resized" + CHANGELOG bugfix-001.
      6. Gotchas (the 7 above, condensed).
      7. "GATES P3.M1.T2" statement: the freeze P3.M1.T2 implements is
         `set-option -t "$ORIG_SESSION" window-size manual` THEN `resize-window -y "$PRE_GROW_HEIGHT" -t "$active_window_id"`,
         applied BEFORE the status grow. @livepicker-preview-fit default = `clip`.
      8. Fallback ladder (clip -> reflow -> snapshot) for non-3.6b terminals.
  - FOLLOW pattern: plan/003_77ef311abf10/architecture/empirical_findings.md (tone, table, summary table at end).
  - NAMING: clip_verification.md. Section headers in sentence case, like the sibling doc.
  - PLACEMENT: plan/003_77ef311abf10/architecture/clip_verification.md
  - GOTCHA: do NOT edit empirical_findings.md (read-only history); reference + supersede it IN your doc.

# No Task 5: this work item produces research artifacts ONLY. Do NOT touch scripts/, tests/, PRD.md, README.md,
# or any tasks.json. The freeze implementation is P3.M1.T2 (gated by THIS doc).
```

### clip_verification.md — required structure (Template)

```markdown
# Clip Verification — tmux 3.6b (clip vs reflow default decision)

> Verdict + evidence for PRD §22 "clip instead of reflow". Supersedes
> empirical_findings.md Finding 2 for the freeze question. GATES P3.M1.T2.

## Decision box
| Question | Answer |
|---|---|
| Is `clip` feasible as the `@livepicker-preview-fit` default on 3.6b? | YES / NO |
| Freeze recipe that actually pins the self-window | `<manual + resize-window -y H0>` |
| Does `window-size manual` ALONE pin? | NO (window still reflowed <h0>-><h1>) |
| Linked-candidate residual | one-time link-time resize to <usable>; no per-nav reflow; source view also resized |

## 1. Correction to empirical_findings.md Finding 2
... (manual alone insufficient; resize-window pin is load-bearing; reference Finding 2 by name) ...

## 2. Experiment (control vs treatment) — verbatim evidence
... (pre/post window_layout + window_height for control = reflow, treatment = clip; cite research/clip_verify_run1.log) ...
### Per-session isolation
... (driver=manual, alpha=empty, global=latest) ...

## 3. The corrected freeze recipe + restore recipe
```bash
# freeze (slot into activate IMMEDIATELY BEFORE the status grow):
tmux set-option -t "$ORIG_SESSION" window-size manual      # NO '=' prefix
tmux resize-window -y "$PRE_GROW_HEIGHT" -t "$ACTIVE_WID"  # the load-bearing pin
# ... grow status (on -> 2) ...
# restore:
tmux set-option -g status "$ORIG_STATUS"
tmux set-option -t "$ORIG_SESSION" window-size "$ORIG_WINDOW_SIZE"
```

## 4. Residual (linked candidate) — reconciled with README "Detached candidate..." + bugfix-001
... (link-time resize magnitude; no per-nav reflow; source disturbance = the shared-window single size) ...

## 5. Gotchas (condensed)
... (bare session name for set-option; pty 80x24; @id not index; settle time; never -g) ...

## 6. GATES P3.M1.T2
P3.M1.T2 implements the recipe in §3. `@livepicker-preview-fit` default = `clip`.
Fallback ladder: clip -> reflow -> snapshot.
```

### Integration Points

```yaml
DECISION CONSUMER:
  - P3.M1.T2 (window-size save/freeze/restore + preview-fit option) READS this doc as its contract.
    The freeze it codes is the recipe in §3 of clip_verification.md — NOT the PRD §22 "manual only" text.
  - P3.M2.T1 (test_preview_clip.sh) READS this doc to know the assert shape
    (assert_eq window_layout before/after the status grow).

RECONCILIATION:
  - README.md "Detached candidate windows are resized during preview" (lines ~187-193): clip does NOT
    remove this; §4 of the doc states it remains and WHY (shared window, link-time resize).
  - CHANGELOG.md bugfix-001 "Detached candidate resize": same limitation, same reconciliation.

READ-ONLY (do NOT modify): PRD.md, empirical_findings.md, README.md, CHANGELOG.md, any tasks.json.
```

## Validation Loop

### Level 1: Probe runs + is deterministic (Immediate Feedback)

```bash
cd /home/dustin/.config/tmux/plugins/tmux-livepicker
# Run twice; both must emit byte-identical window_layout strings.
bash plan/003_77ef311abf10/P3M1T1S1/research/clip_verify_probe.sh > plan/003_77ef311abf10/P3M1T1S1/research/clip_verify_run1.log 2>&1
bash plan/003_77ef311abf10/P3M1T1S1/research/clip_verify_probe.sh > plan/003_77ef311abf10/P3M1T1S1/research/clip_verify_run2.log 2>&1
# Determinism check: the window_layout strings in run1 == run2 (grep them out + diff).
grep -oE '[0-9a-f]{4},[0-9]+x[0-9]+,.*' plan/003_77ef311abf10/P3M1T1S1/research/clip_verify_run1.log \
  > /tmp/p3_layouts_1
grep -oE '[0-9a-f]{4},[0-9]+x[0-9]+,.*' plan/003_77ef311abf10/P3M1T1S1/research/clip_verify_run2.log \
  > /tmp/p3_layouts_2
diff /tmp/p3_layouts_1 /tmp/p3_layouts_2 && echo "DETERMINISTIC" || echo "NONDETERMINISTIC — fix settle timing"

# Expected: DETERMINISTIC. If NONDETERMINISTIC, add/lengthen the post-attach + post-grow sleeps and
# assert `tmux list-clients` is non-empty before every measurement.
```

### Level 2: Experiment outcomes match the decision (Component Validation)

```bash
# The CONTROL arm MUST show a reflow (proves the jank exists); the TREATMENT arm MUST show no reflow.
grep -E 'CONTROL|TREATMENT|PASS|FAIL|window_height' plan/003_77ef311abf10/P3M1T1S1/research/clip_verify_run1.log
# Expected: CONTROL ... reflow (H0 != H1) ; TREATMENT ... pinned (L0 == L1).

# If TREATMENT shows a reflow (L0 != L1) despite manual + resize-window -y H0:
#   that is a REAL NEGATIVE RESULT. Record it in clip_verification.md: clip is INFEASIBLE on this
#   environment, default must be `reflow` (or `snapshot`), and P3.M1.T2 is blocked/redirected.
#   Do NOT massage the experiment to force a pass (Anti-Patterns).
```

### Level 3: Non-pollution (the core invariant)

```bash
# The user's REAL tmux server must be byte-identical before/after the probe (PRD §15).
cd /home/dustin/.config/tmux/plugins/tmux-livepicker
BEFORE="$(/usr/bin/tmux list-sessions -F '#{session_name}' 2>/dev/null | sort)"
bash plan/003_77ef311abf10/P3M1T1S1/research/clip_verify_probe.sh >/dev/null 2>&1
AFTER="$(/usr/bin/tmux list-sessions -F '#{session_name}' 2>/dev/null | sort)"
[ "$BEFORE" = "$AFTER" ] && echo "REAL SERVER UNTOUCHED" || echo "POLLUTION — abort"
# Expected: REAL SERVER UNTOUCHED. The probe uses only the isolated -L socket via the shim.
```

### Level 4: Decision-doc completeness (Domain-Specific Validation)

```bash
# clip_verification.md must contain the decision + the gate statement + the residual reconciliation.
DOC=plan/003_77ef311abf10/architecture/clip_verification.md
for needle in "Decision box" "Correction to empirical_findings.md" "GATES P3.M1.T2" \
              "resize-window -y" "link-time resize" "Detached candidate"; do
  grep -q "$needle" "$DOC" && echo "ok: $needle" || echo "MISSING: $needle"
done
# Expected: every needle present. The doc states the verdict + recipe + residual + gate.
```

## Final Validation Checklist

### Technical Validation
- [ ] Level 1: probe runs twice, byte-identical window_layout strings (DETERMINISTIC).
- [ ] Level 2: CONTROL reproduces the reflow; TREATMENT proves the clip (or, if it fails, the doc records an honest INFEASIBLE verdict).
- [ ] Level 3: real tmux server byte-identical before/after (PRD §15 pollution invariant).
- [ ] Level 4: clip_verification.md contains every required section/needle.

### Feature Validation
- [ ] `clip_verification.md` states the clip default verdict unambiguously.
- [ ] The corrected freeze recipe (manual + resize-window -y H0) is recorded verbatim.
- [ ] The residual (linked-candidate link-time resize + source disturbance) is documented and reconciled with README + bugfix-001.
- [ ] The doc explicitly GATES P3.M1.T2 and names the recipe P3.M1.T2 implements.

### Research-Hygiene Validation
- [ ] `empirical_findings.md`, `PRD.md`, `README.md`, `CHANGELOG.md`, all `tasks.json` are UNMODIFIED.
- [ ] No writes outside `plan/003_77ef311abf10/P3M1T1S1/research/` and `plan/003_77ef311abf10/architecture/clip_verification.md`.
- [ ] The probe sources the SHIPPED harness (`tests/setup_socket.sh`); no hand-rolled `tmux -L` that could touch the real server.

### Documentation
- [ ] `clip_verify_probe.sh` has a header comment citing this PRP + the prior probe findings.
- [ ] `clip_verification.md` cites `research/clip_verify_run1.log` as the evidence source.
- [ ] Verdict is grounded in the observed numbers, not assumption.

---

## Anti-Patterns to Avoid

- ❌ Don't edit `empirical_findings.md` to "fix" Finding 2 — it is read-only research history. Reference + supersede it IN `clip_verification.md`.
- ❌ Don't implement the freeze in `scripts/livepicker.sh` or `restore.sh` — that is P3.M1.T2, gated by THIS doc. This task writes research + a decision, nothing in `scripts/` or `tests/`.
- ❌ Don't use `set-option -t "=driver" ...` (the `=` prefix breaks session-option `set-option`). Bare session name only.
- ❌ Don't set `window-size` with `-g` (global) — it disconnects the window from the client (jumped to 40). Per-session `-t` only.
- ❌ Don't assume the pty is 120x40 — `attach_test_client`'s `script` pty reports 80x24. Measure `window_height` live; don't hardcode.
- ❌ Don't hardcode window indices — use the active window's `@id`, captured dynamically.
- ❌ Don't massage the experiment to force a PASS. If the treatment still reflows on this box, record INFEASIBLE and prescribe `reflow`/`snapshot` — that is a valid, valuable outcome.
- ❌ Don't touch the real tmux server — source the harness; it isolates via the `-L` shim. Verify non-pollution (Level 3).
- ❌ Don't skip the determinism re-run — a nondeterministic probe undermines the decision.

---

## Confidence Score: 9/10

The decision is already strongly evidenced: a prior probe (`research/clip_probe_findings.md`) ran this exact experiment on this box and found manual-alone fails (reflow 23→22) while manual+resize-window pins (byte-identical layout), with a linked-candidate one-time link-time resize and no per-nav reflow. The residual 1/10 is environmental nondeterminism (pty settle timing) and the small chance a re-run surfaces a different behavior — both caught by the determinism re-run (Level 1) and the honest-negative path (Level 2). The implementer's job is to reproduce, record, and gate — not to discover from scratch.
