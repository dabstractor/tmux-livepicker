name: "P3.M1.T1.S1 — Candidate-window pinning verification probe + pane-immutability gate decision"
description: Research/verification work item. Run a reproducible, harness-isolated experiment on tmux 3.6b (with a REAL attached client) that tests whether freezing a CANDIDATE's `window-size` + height at link time prevents the source-view pane disturbance that `clip_verification.md` §4 found. Record the GATE decision (ship candidate pin? under what conditions? or snapshot escape?) to `architecture/pane_immutability_verification.md`. This GATES P3.M2.T2 (conditional candidate-pin code) and informs P3.M2.T1 (drift-gated restore).

---

## Goal

**Feature Goal**: Empirically settle, on the installed **tmux 3.6b with a real attached client**, whether pinning a CANDIDATE's window (`window-size manual` + `resize-window -y H_cand`) at link time holds PRD §23 Invariant C (zero pane mutation of any session) — and under exactly which conditions — so P3.M2.T2 knows whether to ship the candidate-pin code, gate it, or skip it in favor of `@livepicker-preview-mode snapshot`.

**Deliverable**: Two artifacts, BOTH written by the implementing agent (NOT by this PRP author):
1. `plan/004_2c5127285a90/P3M1T1S1/research/pane_immutability_probe.sh` — a self-contained, reproducible probe script (sourced-executable bash; sources `tests/setup_socket.sh`) that runs the control / pin-before-link / pin-after-link (reversibility) / candidate-with-own-client / flip arms against an isolated `-L` socket with an attached client and prints the verbatim `window_layout` / `list-panes` / `window_height` evidence.
2. `plan/004_2c5127285a90/architecture/pane_immutability_verification.md` — the GATE decision document: verdict (ship pin YES/NO/CONDITIONAL), the exact pin recipe, the verbatim evidence matrix, the corrected reversibility finding, the residual + escape hatch, and an explicit "GATES P3.M2.T2" statement.

**Success Definition**: `pane_immutability_verification.md` states unambiguously whether candidate pinning ships (and the precise `list-clients` guard that gates it), documents the client-bearing-candidate failure mode (pin is harmful there → skip + snapshot), records the corrected reversibility finding (`resize-window -y H_orig` restores the exact layout, unlike `select-layout`), the probe script reproduces byte-identical `window_layout` strings across two independent runs, and the user's real tmux server (`/usr/bin/tmux list-sessions`) is byte-identical before/after.

## User Persona

**Target User**: The P3.M2.T2 implementer (the very next agent under P3), the P3.M2.T1 implementer (drift-gated restore), and the P3.M3.T1 test author.

**Use Case**: Opening `pane_immutability_verification.md` to learn, in one screen, (a) does the candidate pin hold Invariant C, (b) the EXACT recipe + the `list-clients` guard that makes it safe, (c) what to do for client-bearing candidates, (d) why `resize-window` (not `select-layout`) is the reliable restore.

**Pain Points Addressed**: PRD §23 + §16 mark candidate-window protection as unverifiable without a real multi-client setup and prescribe "freeze each candidate at link time … if the driver pin alone does not guarantee that." This task closes that open question with hard evidence instead of the spec's hedged "could not be fully verified."

## Why

- PRD §23 "Pane immutability — zero mutation" is an **absolute** invariant (Invariant C), and §16 names the shared-window root cause: a linked window is ONE object with ONE size, so resizing it in the driver reflows its panes in the candidate too, and §23 calls that mutation "permanent." The predecessor doc `clip_verification.md` §4 already PROVED the disturbance happens for an UNPINNED candidate (alpha source 40→22). This task tests whether the §23-prescribed candidate pin actually prevents it.
- The decision is **load-bearing for P3.M2.T2**: if the pin holds, P3.M2.T2 ships it; if it does not (or is too invasive), P3.M2.T2 is skipped and `snapshot` becomes the required mode for strict immutability. Building the pin blind would risk either shipping a no-op or shipping a pane-mutating regression.
- The probe ALSO produces a **correction to PRD §23** that benefits P3.M2.T1 (drift-gated restore): the mutation is reversible via `resize-window -y H_orig` (size-first), which restores the exact multi-pane layout — only `select-layout` (size-dependent) is unreliable. P3.M2.T1's restore path should use the resize-pin, not a bare `select-layout`.

## What

A reproducible experiment + a decision document. The experiment uses ONLY the project's harness (`tests/setup_socket.sh`) against an **isolated `-L` socket**, never the user's real server, and crucially uses a **real attached client** (`attach_test_client`) because sessions created with `-x/-y` are size-locked and hide the shared-window resize (confirmed: `system_context.md` empirical-verification #2 saw "no change" on detached `-x/-y` sessions; `clip_verification.md` §4 reproduced the resize only with the driver client attached).

It is a **control-vs-treatment matrix** across five arms (detached control, detached pin-before-link, detached pin-after-link/reversibility, candidate-with-own-client, flip), diffing the candidate's SOURCE-view pane geometry (`window_layout` byte-identical + sorted `list-panes`) before-link vs after-link-and-grow.

### Success Criteria

- [ ] `pane_immutability_probe.sh` exists in `research/`, sources `tests/setup_socket.sh`, runs to completion, and is deterministic (two independent invocations emit byte-identical `window_layout` strings).
- [ ] **ARM A (control)**: an UNPINNED candidate linked into a manual+pinned driver is disturbed (source `window_layout` changes, height 40→22) — reproduces `clip_verification.md` §4.
- [ ] **ARM B (pin before link, detached)**: a candidate pinned (`manual` + `resize-window -y H_cand`) BEFORE `link-window` has its source `window_layout` AND sorted `list-panes` **byte-identical** before vs after link+grow. The decisive data point.
- [ ] **ARM C (pin after link / reversibility)**: after an unpinned link disturbs the candidate, `resize-window -y H_orig` restores the EXACT pre-link multi-pane `window_layout`. (Corrects §23's "permanent" claim for the resize-pin path.)
- [ ] **ARM E (candidate with its OWN client)**: pinning a client-bearing candidate is HARMFUL — `window-size manual` reverts its client view to the creation size; AND the bare `link-window` alone does NOT disturb a client-bearing candidate. Both recorded.
- [ ] `pane_immutability_verification.md` states the verdict + the `list-clients` guard + the escape hatch + an explicit "GATES P3.M2.T2" line.
- [ ] Real tmux server (`/usr/bin/tmux list-sessions -F '#{session_name}' | sort`) byte-identical before/after the whole probe.

## All Needed Context

### Context Completeness Check

_"If someone knew nothing about this codebase, would they have everything needed to implement this successfully?"_ — Yes. This PRP pins the exact harness contract, the exact (already-probed) command matrix, the exact gotchas that broke early probe passes (including the new `split-window`/`new-window` bare-session-name gotcha and the second-pty spawn for the candidate's own client), the exact output doc structure (mirroring `clip_verification.md`), and the exact decision criteria. The probe script confirms what the cited research already established; no tmux-behavior guessing is required.

### Documentation & References

```yaml
# MUST READ — load into the context window before writing anything.

- file: plan/004_2c5127285a90/P3M1T1S1/research/candidate_pin_probe_findings.md
  why: THE primary evidence. A prior probe ALREADY ran this exact 5-arm matrix on
        this box (tmux 3.6b + attach_test_client) and recorded verbatim window_layout
        + list-panes strings + the verdict. Your probe reproduces this; your doc
        records it. This is your template + your answer key.
  critical: "VERDICT = CONDITIONAL YES. Detached candidate pin = byte-identical
        (ARM B2, layout 16ec, deterministic). Client-bearing candidate pin = HARMFUL
        (ARM E3: manual reverts client view 80x22 -> 120x40). Bare link alone does NOT
        disturb a client-bearing candidate (ARM E4). Pin-after-link IS reversible via
        resize-window -y H_orig (ARM C2 restores exact 16ec layout) — corrects §23
        'permanent' (that was about select-layout, not resize-pin)."

- file: plan/003_77ef311abf10/architecture/clip_verification.md   # §4 + §3
  why: The predecessor finding this task EXTENDS. §4 proved an UNPINNED linked
        candidate's window drops 40->22 AND disturbs the source view (shared window).
        §3 has the driver-side freeze recipe (manual + resize-window -y H0) that your
        probe sets up FIRST in every arm. §5 gotchas are identical to yours.
  gotcha: "clip_verification.md is READ-ONLY history. Reference + extend it in your
        doc; do NOT edit it."

- file: plan/003_77ef311abf10/P3M1T1S1/research/clip_probe_findings.md   # §4 CONFIRMED RECIPES + §5 gotchas
  why: The harness mechanics cookbook. §4 has the exact driver-freeze recipe +
        assert shape; §5 has the determinism/timing notes (sleep 0.5 attach, 0.3
        grow/link, assert list-clients non-empty). Reuse verbatim.

- file: plan/003_77ef311abf10/P3M1T1S1/research/tmux_window_size_docs.md
  why: External tmux semantics backing the mechanism section of your doc. window-size
        is a SESSION option (so -t isolates); manual = no auto-resize pressure; a
        linked window has ONE shared size and ANY non-manual session viewing it as
        current will resize it for everyone. This explains WHY the pin works (both
        sessions manual -> no pressure) and WHY it harms client-bearing candidates
        (manual there = 'ignore my client' -> reverts to creation size).

- file: tests/setup_socket.sh   # attach_test_client ~L196-215, setup_socket -x 120 -y 40
  why: THE harness. Your probe sources this. attach_test_client spawns ONE script-pty
        (overwrites the single TEST_CLIENT_PID); to attach a SECOND client to the
        candidate you must spawn a pty MANUALLY (see gotcha #8). teardown_socket kills
        the server + removes the shim dir + orphan socket.

- file: tests/test_preview_clip.sh   # existing pane-geometry assertions (plan 003 shipped it)
  why: The reference for the assert shape your doc prescribes for P3.M3.T1. It uses
        `display-message -p -t "$wid" '#{window_layout}'` byte-identical comparisons.
        Your doc's §assert-shape mirrors + extends it with sorted list-panes.

- file: scripts/preview.sh   # the link flow (lines ~200-288): src_id resolution, GUARDs, link-window, select-window
  why: CONTEXT ONLY (you do NOT edit it — that is P3.M2.T2). Understand WHERE the
        candidate pin would slot in: right before `tmux link-window -s "$src_id" -t
        "$current_session:"` (~L256), gated on `[ -z "$(tmux list-clients -t "=$S")" ]`.
        Note P2.M3.T1.S1 (parallel) makes the select-window calls session-scoped
        (`"$current_session:$src_id"`) — your probe must mirror that session-scoped form.

- file: PRD.md   # §23 Pane immutability + §15.23 Pane immutability verification + §16 risks + §22 clip
  why: The spec. §23 root cause + 'Prevention regime' (candidate pin if driver pin
        insufficient) + 'Verification (load-bearing, requires a real client)'. §15.23
        is the exact assertion list (byte-identical pane geometry across open->flip->
        move->cancel and open->flip->confirm). §16 'Shared-window pane mutation' +
        'Preview clip feasibility' are the risk notes your doc resolves.
```

### Current Codebase tree (run `ls` in the project root)

```
tmux-livepicker/
├── scripts/          # plugin runtime (preview.sh=link core; livepicker.sh=activate; restore.sh=teardown)
├── tests/            # harness: setup_socket.sh, helpers.sh, run.sh + test_*.sh (incl. test_preview_clip.sh)
├── plan/
│   ├── 003_77ef311abf10/architecture/clip_verification.md   # §4 predecessor (READ-ONLY, extend it)
│   └── 004_2c5127285a90/
│       ├── architecture/         # system_context.md, gap_analysis_*.md (READ)
│       └── P3M1T1S1/
│           ├── PRP.md            # THIS file
│           └── research/         # candidate_pin_probe_findings.md (DONE) + YOUR pane_immutability_probe.sh
├── PRD.md            # §23, §22, §16, §15.23 (read-only)
└── README.md         # 'Detached candidate windows are resized' limitation (read-only)
```

### Desired Codebase tree with files to be added

```bash
plan/004_2c5127285a90/P3M1T1S1/research/pane_immutability_probe.sh       # ADD — reproducible 5-arm experiment
plan/004_2c5127285a90/architecture/pane_immutability_verification.md    # ADD — the GATE decision doc
```

`pane_immutability_probe.sh` responsibility: source `tests/setup_socket.sh`; for each arm run a FRESH isolated socket + attached driver client (+ a manually-spawned second pty for the candidate in ARM E); capture `window_layout` + sorted `list-panes` + `window_height` for the candidate's SOURCE view before vs after; print labeled banners + PASS/FAIL; leave the real server untouched. Re-runnable.

`pane_immutability_verification.md` responsibility: state the CONDITIONAL verdict; embed the verbatim evidence matrix; document the mechanism, the reversibility correction, the client-bearing failure mode, the recipes, the gotchas; explicitly gate P3.M2.T2 and inform P3.M2.T1.

### Known Gotchas of our codebase & tmux 3.6b Library Quirks

```bash
# CRITICAL (all probed on this box; tripped early probe passes):
# 1. Bare session name for set-option/split-window/new-window. `set-option -t "=alpha" ...`
#    -> rc=1 ("no such window"). `split-window -t "=alpha"` -> "can't find pane". Use the
#    BARE name: `set-option -t alpha`, `split-window -t alpha`. The '=' prefix IS valid for
#    list-windows/display-message/link-window/select-window, NOT for set-option/split-window/new-window.
# 2. attach_test_client's `script` pty reports 80x24 (NOT the session's -x 120 -y 40). So an
#    attached driver's usable height is 23 (status 1) / 22 (status 2); detached sessions keep 40.
#    This size mismatch is WHY the shared-window resize reproduces. Measure window_height live.
# 3. Address windows by @id, NEVER index (base-index 1, renumber-windows on). Capture the active
#    @id dynamically: `tmux list-windows -t "=alpha" -F '#{window_id}' -f '#{window_active}'`.
#    When a var holds '@1', write `-t "$WID"`, NOT `-t "@$WID"` (becomes '@@1').
# 4. resize-window -y H sets the SHARED window's size globally (all linked sessions). H larger
#    than the client = clip (tmux renders top-left, hides overflow). H = current = pin (no reflow).
# 5. window_height/window_layout need an attached client to reflect client-driven usable size;
#    on a client-less socket they read creation size 40. ALWAYS assert `tmux list-clients`
#    non-empty before measuring. sleep 0.5 (attach) + 0.3 (after grow/link/pin) is sufficient.
# 6. NEVER `set-option -g window-size` (global manual disconnects from client -> jumps to 40).
#    Per-session -t only.
# 7. window_layout embeds per-node dims + a 4-hex checksum -> CHANGES on reflow/resize. Byte-
#    identical window_layout across an operation = strong no-mutation proof. ALSO capture sorted
#    list-panes (`#{pane_id}:#{pane_left},#{pane_top},#{pane_width},#{pane_height}`) as the
#    explicit §23 per-pane assertion.
# 8. SECOND client for the candidate: attach_test_client overwrites the single TEST_CLIENT_PID.
#    Spawn a pty MANUALLY for the candidate's own client (ARM E):
#      script -qec "tmux attach -t 'alpha'" /dev/null >/dev/null 2>&1 & CAND_PID=$!; sleep 0.5
#    Kill it yourself on teardown (`kill "$CAND_PID"; wait "$CAND_PID" 2>/dev/null`).
# 9. ARM D (flip) harness quirk: creating a SECOND window AFTER the candidate is manual+linked
#    via `new-window -t alpha` can fail with "index N in use" in this fixture. Create distinct
#    candidate windows BEFORE the manual/link state, or reason from clip_verification.md §4's
#    proven no-per-nav-reflow (independent @id windows are independent shared objects).
```

## Implementation Blueprint

This is a research/verification task: no runtime data models or service classes. The "blueprint" is the experiment matrix + the output doc structure.

### Experiment design (5 arms; candidate = multi-pane `alpha`)

The decision is rigorous only if it (a) reproduces the known disturbance without the pin (control), (b) proves the pin prevents it for the common detached case, (c) tests reversibility, and (d) tests the client-bearing edge case where the pin may be harmful. Snapshot the candidate's SOURCE-view geometry (`window_layout` + sorted `list-panes` + `window_height`) before vs after each operation.

```bash
# Shared geometry helper (define once; $1 = target spec, e.g. "$ALPHA_WID" or "=alpha:"):
#   tmux display-message -p -t "$1" '#{window_height}'
#   tmux display-message -p -t "$1" '#{window_layout}'
#   tmux list-panes -t "$1" -F '#{pane_id}:#{pane_left},#{pane_top},#{pane_width},#{pane_height}' | sort
#
# Driver setup (every arm): setup_socket; attach_test_client; freeze driver:
#   drv_wid="$(tmux list-windows -t "=driver" -F '#{window_id}' -f '#{window_active}')"
#   H_drv="$(tmux display-message -p -t "$drv_wid" '#{window_height}')"
#   tmux set-option -t driver window-size manual          # bare name (gotcha #1)
#   tmux resize-window -y "$H_drv" -t "$drv_wid"
#   tmux set-option -g status 2; sleep 0.3                # grow (status already 2 before candidate link)
# Make alpha multi-pane: tmux split-window -h -t alpha; tmux split-window -v -t alpha
# ALPHA_WID="$(tmux list-windows -t "=alpha" -F '#{window_id}' -f '#{window_active}')"
#
# ARM A — CONTROL (no candidate pin): snapshot alpha pre; link; select; snapshot alpha source post.
#   EXPECT: disturbed (40->22, layout changes). Reproduces clip_verification.md §4.
#
# ARM B — PIN BEFORE LINK (the proposed fix), detached alpha:
#   snapshot alpha pre; set-option -t alpha window-size manual;
#   H_cand="$(display-message -p -t "$ALPHA_WID" '#{window_height}')"; resize-window -y "$H_cand" -t "$ALPHA_WID";
#   snapshot alpha post-pin (did the pin itself change it?); link-window -s "$ALPHA_WID" -t "driver:";
#   select-window -t "driver:$ALPHA_WID"; sleep 0.3; snapshot alpha source post-link. Compare to pre.
#   EXPECT: BYTE-IDENTICAL (the decisive data point).
#
# ARM C — PIN AFTER LINK (reversibility): snapshot alpha pre; link unpinned (alpha disturbed);
#   resize-window -y "$H_cand_pre" -t "$ALPHA_WID"; snapshot alpha post-pin-back. Compare to pre.
#   EXPECT: exact restoration (corrects §23 'permanent' for the resize-pin path).
#
# ARM D — FLIP: candidate pinned (as B); create a SECOND distinct window in alpha BEFORE manual state;
#   pin it; link W2; re-select W1; snapshot W1 source before vs after the W2 flip. EXPECT no resize.
#   (If new-window post-manual fails, note the harness quirk + reason from clip §4 no-per-nav-reflow.)
#
# ARM E — CANDIDATE WITH OWN CLIENT: attach a SECOND pty to alpha (gotcha #8); snapshot alpha (now
#   client-fitted ~80x23); global status grow already done (alpha client -> 22). Two sub-arms:
#   E3 WITH pin: set-option -t alpha manual + resize-window -> EXPECT alpha REVERTS to 120x40 (HARMFUL).
#   E4 NO pin:   link only -> EXPECT alpha byte-identical (bare link does NOT disturb client-bearing cand).
#   DECISION INPUT: pin must be SKIPPED for client-bearing candidates (gate on list-clients).
#
# teardown after EACH arm (detach_test_client; kill any CAND_PID; teardown_socket).
# /usr/bin/tmux (real server) list-sessions byte-identical pre/post whole probe.
```

### Implementation Tasks (ordered by dependencies)

```yaml
Task 1: READ the cited research + harness + clip_verification.md §4 (NO writes)
  - READ: plan/004_2c5127285a90/P3M1T1S1/research/candidate_pin_probe_findings.md (the prior probe = template + answer key)
  - READ: plan/003_77ef311abf10/architecture/clip_verification.md §3-§5 (driver-freeze recipe + gotchas you reuse)
  - READ: plan/003_77ef311abf10/P3M1T1S1/research/clip_probe_findings.md §4-§5 (assert shape + timing)
  - READ: tests/setup_socket.sh (attach_test_client + second-pty spawn gotcha #8)
  - READ: scripts/preview.sh ~L200-288 (WHERE the pin slots in — context only; do NOT edit)
  - PURPOSE: internalize the verified matrix + gotchas so your probe/doc reproduce them exactly.

Task 2: CREATE plan/004_2c5127285a90/P3M1T1S1/research/pane_immutability_probe.sh
  - IMPLEMENT: a `set -u` bash script. Header comment citing this PRP + candidate_pin_probe_findings.md.
    `source` the repo-root `tests/setup_socket.sh` (resolve via "$(dirname "$0")/../../../.."/tests/setup_socket.sh).
    Define a `snap()` geometry helper (height + layout + sorted list-panes). For each arm
    (arm_control / arm_pin_before / arm_pin_after / arm_flip / arm_candidate_with_client):
      setup_socket <unique-name> ; driver-freeze ; attach_test_client ; <arm body> ; detach_test_client ;
      kill any manual cand pty ; teardown_socket
    Print a labeled banner per arm + verbatim snapshots + a PASS/FAIL line. For ARM E spawn the
    second pty per gotcha #8 and kill it.
  - FOLLOW pattern: plan/003's clip_verify_probe.sh (if present) style; else mirror
    tests/setup_socket.sh setup_socket_self_test print style (banner + ok/bad lines).
  - NAMING: pane_immutability_probe.sh. Factor arms as functions if helpful.
  - GOTCHAS: all 9 above — esp. #1 (bare session name for set-option/split-window/new-window),
    #8 (manual second pty for the candidate), #9 (create flip windows BEFORE manual state).
  - PLACEMENT: plan/004_2c5127285a90/P3M1T1S1/research/pane_immutability_probe.sh

Task 3: RUN pane_immutability_probe.sh TWICE; capture both outputs to research/
  - RUN: `bash .../pane_immutability_probe.sh > .../research/pane_immutability_run1.log 2>&1` then run2.log.
  - VERIFY: run1 and run2 emit BYTE-IDENTICAL window_layout strings per arm (determinism). If they
    differ, fix settle timing / the list-clients-non-empty guard before proceeding.
  - VERIFY: ARM A reproduces the disturbance; ARM B is byte-identical; ARM C restores; ARM E3 is
    harmful + E4 is clean. If any diverges from candidate_pin_probe_findings.md, record the ACTUAL
    observed result honestly (do not force agreement — environment may differ).

Task 4: CREATE plan/004_2c5127285a90/architecture/pane_immutability_verification.md  (THE deliverable)
  - IMPLEMENT: the decision document. Use clip_verification.md STYLE (decision box table, numbered
    sections, verbatim evidence, summary). Required sections (see Template below):
      1. Decision box — CONDITIONAL YES: ship the pin for DETACHED candidates; SKIP for client-bearing.
         The gate is `[ -z "$(tmux list-clients -t "=$S" 2>/dev/null)" ]`. Strict immutability for
         client-bearing candidates => @livepicker-preview-mode snapshot.
      2. The 5-arm evidence matrix — verbatim window_layout + sorted list-panes + height before/after
         per arm (cite research/pane_immutability_run1.log). The ARM B byte-identical string is the proof.
      3. Mechanism — WHY the pin works (both sessions manual -> no auto-resize pressure on the shared
         window) and WHY it harms client-bearing candidates (manual = 'ignore my client' -> reverts to
         creation size). Reference tmux_window_size_docs.md.
      4. Reversibility correction — resize-window -y H_orig restores the EXACT multi-pane layout (ARM C);
         §23's 'permanent / select-layout failed' is true ONLY for select-layout. Implication for
         P3.M2.T1 drift-gated restore: prefer resize-pin (size-first) over bare select-layout.
      5. The candidate-pin recipe (conditional) + restore-on-unlink recipe + the list-clients guard.
      6. Residual + escape hatch — client-bearing candidates + the global-status-grow disturbance are
         NOT fixed by the pin; snapshot is the strict escape. Reconcile with README 'Detached candidate
         windows are resized' limitation.
      7. Gotchas (the 9 above, condensed).
      8. "GATES P3.M2.T2" statement — ship the conditional pin (recipe §5 + list-clients guard).
         Inform P3.M2.T1 (resize-pin restore). P3.M3.T1 locks it (assert shape + a distinct-window flip case).
  - FOLLOW pattern: plan/003_77ef311abf10/architecture/clip_verification.md (tone, table, summary).
  - NAMING: pane_immutability_verification.md.
  - PLACEMENT: plan/004_2c5127285a90/architecture/pane_immutability_verification.md
  - GOTCHA: do NOT edit clip_verification.md (read-only); reference + extend it IN your doc.

# No Task 5: this work item produces research artifacts ONLY. Do NOT touch scripts/, tests/, PRD.md,
# README.md, or any tasks.json. The conditional candidate-pin CODE is P3.M2.T2 (gated by THIS doc).
```

### pane_immutability_verification.md — required structure (Template)

```markdown
# Pane-Immutability Verification — tmux 3.6b (candidate-window pinning, PRD §23 Invariant C)

> Verdict + evidence for PRD §23 "candidate windows linked in later must be protected."
> Extends clip_verification.md §4. Corrects §23 "permanent mutation" for the resize-pin
> path. GATES P3.M2.T2; informs P3.M2.T1.

## Decision box
| Question | Answer |
|---|---|
| Does candidate pinning hold Invariant C for a DETACHED candidate? | YES (byte-identical) |
| Does it hold for a candidate WITH its own attached client? | NO — and the pin is HARMFUL (reverts client view to creation size) |
| Does the bare link disturb a client-bearing candidate? | NO (driver manual -> no downward pressure) |
| Is the link-time mutation reversible? | YES via resize-window -y H_orig (NOT via select-layout) |
| Verdict | CONDITIONAL YES: ship the pin, gated on `[ -z "$(tmux list-clients -t "=$S")" ]` |

## 1. Evidence matrix (5 arms) — verbatim window_layout + list-panes + height
... (A control=disturbed; B pin-before=byte-identical; C pin-after=restored; D flip=safe; E3 harmful/E4 clean) ...

## 2. Mechanism
... (shared window one size; manual = no auto-resize pressure; both sessions manual -> pin holds;
client-bearing candidate: manual reverts client view -> harmful) ...

## 3. Reversibility correction (informs P3.M2.T1)
... (resize-window -y H_orig restores exact layout; select-layout is the unreliable one) ...

## 4. Recipes (for P3.M2.T2)
```bash
# candidate pin at link time — CONDITIONAL on NO attached client of the candidate's own:
if [ -z "$(tmux list-clients -t "=$S" 2>/dev/null)" ]; then
	# save candidate's effective window-size for restore
	tmux set-option -t "$S" window-size manual          # bare name
	H_cand="$(tmux display-message -p -t "$src_id" '#{window_height}')"
	tmux resize-window -y "$H_cand" -t "$src_id"
fi
tmux link-window -s "$src_id" -t "$current_session:"
# restore on unlink: tmux set-option -t "$S" window-size "$ORIG_WS_CAND"
```

## 5. Residual + escape hatch
... (client-bearing candidates + global status grow NOT fixed by pin; snapshot is strict escape;
reconcile with README 'Detached candidate windows are resized') ...

## 6. Gotchas (condensed)
... (bare session name; pty 80x24; @id not index; second-pty spawn; never -g) ...

## 7. GATES P3.M2.T2 (conditional pin) + informs P3.M2.T1 (resize-pin restore) + P3.M3.T1 (assert shape + flip case)
```

### Integration Points

```yaml
DECISION CONSUMER:
  - P3.M2.T2 (candidate-window pinning at link time — CONDITIONAL on this doc) READS §4 recipe + the
    list-clients guard. Ships the pin ONLY for detached candidates; skips it (no code) for client-bearing.
  - P3.M2.T1 (drift-gated restore) READS §3: use resize-window -y H_orig (size-first) when drift is
    detected, NOT a bare select-layout.
  - P3.M3.T1 (test_pane_immutability.sh) READS the assert shape (window_layout + sorted list-panes
    byte-identical) + must add an explicit distinct-window flip case (§1 ARM D / gotcha #9).

RECONCILIATION:
  - README 'Detached candidate windows are resized during preview': the conditional pin REMOVES this
    for detached candidates; client-bearing candidates still hit it -> snapshot.
  - clip_verification.md §4 (predecessor): EXTENDED here (the §4 disturbance is prevented by the pin
    for detached candidates). Do NOT edit clip_verification.md.

READ-ONLY (do NOT modify): PRD.md, clip_verification.md, README.md, CHANGELOG.md, any tasks.json,
scripts/*, tests/*.
```

## Validation Loop

### Level 1: Probe runs + is deterministic (Immediate Feedback)

```bash
cd /home/dustin/.config/tmux/plugins/tmux-livepicker
bash plan/004_2c5127285a90/P3M1T1S1/research/pane_immutability_probe.sh > plan/004_2c5127285a90/P3M1T1S1/research/pane_immutability_run1.log 2>&1
bash plan/004_2c5127285a90/P3M1T1S1/research/pane_immutability_probe.sh > plan/004_2c5127285a90/P3M1T1S1/research/pane_immutability_run2.log 2>&1
# Determinism: the window_layout strings in run1 == run2 (grep + diff per arm).
for f in pane_immutability_run1 pane_immutability_run2; do
  grep -oE '[0-9a-f]{4},[0-9]+x[0-9]+,.*' plan/004_2c5127285a90/P3M1T1S1/research/$f.log
done | sort | uniq -c   # each layout string should appear an even number of times across both runs
# Expected: DETERMINISTIC. If not, lengthen sleeps + assert list-clients non-empty before measuring.
```

### Level 2: Experiment outcomes match the decision (Component Validation)

```bash
# ARM A must DISTURB (reproduce §4); ARM B must be BYTE-IDENTICAL; ARM C must RESTORE;
# ARM E3 must be HARMFUL; ARM E4 must be CLEAN.
grep -E 'ARM |SAME|DIFF|DISTURBED|BYTE-IDENTICAL|RESTORED|HARMFUL|REVERTED|PASS|FAIL' \
  plan/004_2c5127285a90/P3M1T1S1/research/pane_immutability_run1.log
# Expected: A=DIFF/DISTURBED; B=SAME/BYTE-IDENTICAL; C=SAME-restored; E3=REVERTED/HARMFUL; E4=SAME.
# If ARM B is NOT byte-identical (candidate pin does NOT hold), record an honest verdict: the pin is
# infeasible -> P3.M2.T2 skipped -> snapshot required. Do NOT force a pass (Anti-Patterns).
```

### Level 3: Non-pollution (the core invariant)

```bash
cd /home/dustin/.config/tmux/plugins/tmux-livepicker
BEFORE="$(/usr/bin/tmux list-sessions -F '#{session_name}' 2>/dev/null | sort)"
bash plan/004_2c5127285a90/P3M1T1S1/research/pane_immutability_probe.sh >/dev/null 2>&1
AFTER="$(/usr/bin/tmux list-sessions -F '#{session_name}' 2>/dev/null | sort)"
[ "$BEFORE" = "$AFTER" ] && echo "REAL SERVER UNTOUCHED" || echo "POLLUTION — abort"
# Expected: REAL SERVER UNTOUCHED (probe uses only the isolated -L socket via the shim).
```

### Level 4: Decision-doc completeness (Domain-Specific Validation)

```bash
DOC=plan/004_2c5127285a90/architecture/pane_immutability_verification.md
for needle in "Decision box" "CONDITIONAL" "list-clients" "resize-window -y" "reversib" \
              "select-layout" "GATES P3.M2.T2" "snapshot" "Detached candidate"; do
  grep -q "$needle" "$DOC" && echo "ok: $needle" || echo "MISSING: $needle"
done
# Expected: every needle present. The doc states the conditional verdict + guard + escape + gate.
```

## Final Validation Checklist

### Technical Validation
- [ ] Level 1: probe runs twice, byte-identical window_layout strings (DETERMINISTIC).
- [ ] Level 2: A disturbs, B byte-identical, C restores, E3 harmful, E4 clean (or honest INFEASIBLE verdict).
- [ ] Level 3: real tmux server byte-identical before/after (PRD §15 pollution invariant).
- [ ] Level 4: pane_immutability_verification.md contains every required section/needle.

### Feature Validation
- [ ] `pane_immutability_verification.md` states the CONDITIONAL verdict + the `list-clients` guard.
- [ ] The candidate-pin recipe (manual + resize-window -y H_cand, detached only) is recorded verbatim.
- [ ] The reversibility correction (resize-pin, not select-layout) is recorded for P3.M2.T1.
- [ ] The client-bearing failure mode + snapshot escape hatch are documented.
- [ ] The doc explicitly GATES P3.M2.T2 (ship conditional pin) and informs P3.M2.T1 + P3.M3.T1.

### Research-Hygiene Validation
- [ ] `clip_verification.md`, `PRD.md`, `README.md`, `CHANGELOG.md`, all `tasks.json`, `scripts/*`, `tests/*` are UNMODIFIED.
- [ ] No writes outside `plan/004_2c5127285a90/P3M1T1S1/research/` and `plan/004_2c5127285a90/architecture/pane_immutability_verification.md`.
- [ ] The probe sources the SHIPPED harness (`tests/setup_socket.sh`); no hand-rolled `tmux -L` that could touch the real server.

### Documentation
- [ ] `pane_immutability_probe.sh` has a header comment citing this PRP + candidate_pin_probe_findings.md.
- [ ] `pane_immutability_verification.md` cites `research/pane_immutability_run1.log` as the evidence source.
- [ ] Verdict is grounded in the observed numbers, not assumption.

---

## Anti-Patterns to Avoid

- ❌ Don't edit `clip_verification.md` or `empirical_findings.md` — read-only history. Reference + extend them IN `pane_immutability_verification.md`.
- ❌ Don't implement the candidate pin in `scripts/preview.sh` — that is P3.M2.T2, gated by THIS doc. This task writes research + a decision, nothing in `scripts/` or `tests/`.
- ❌ Don't use `set-option -t "=alpha"`/`split-window -t "=alpha"` (the `=` prefix breaks set-option and split-window). Bare session name only.
- ❌ Don't set `window-size` with `-g` (global) — disconnects from client, jumps to creation size. Per-session `-t` only.
- ❌ Don't assume the pty is 120x40 — `attach_test_client`'s pty is 80x24. Measure live; don't hardcode.
- ❌ Don't hardcode window indices — use the active window's `@id`, captured dynamically.
- ❌ Don't forget the candidate's OWN client in ARM E — `attach_test_client` won't give you a second client; spawn a pty manually (gotcha #8) and kill it.
- ❌ Don't create the flip's second window AFTER the candidate is manual+linked (gotcha #9 quirk) — create distinct windows first, or reason from clip §4.
- ❌ Don't massage the experiment to force ARM B to pass. If the pin does not hold on this box, record INFEASIBLE (flat NO) and prescribe snapshot — that is a valid, valuable outcome.
- ❌ Don't touch the real tmux server — source the harness; it isolates via the `-L` shim. Verify non-pollution (Level 3).
- ❌ Don't skip the determinism re-run — a nondeterministic probe undermines the gate decision.

---

## Confidence Score: 9/10

The decision is already strongly evidenced: a prior probe (`research/candidate_pin_probe_findings.md`) ran this exact 5-arm matrix on this box and found a clean CONDITIONAL YES — detached candidate pin is byte-identical (deterministic), client-bearing candidate pin is harmful (skip + snapshot), and the resize-pin path is reversible (correcting §23). The residual 1/10 is environmental nondeterminism (pty settle timing, the ARM D `new-window` fixture quirk) and the small chance a re-run diverges — both caught by the determinism re-run (Level 1), the ARM-D reasoning fallback (clip §4 no-per-nav-reflow), and the honest-INFEASIBLE path (Level 2). The implementer's job is to reproduce, record, and gate — not to discover from scratch.
