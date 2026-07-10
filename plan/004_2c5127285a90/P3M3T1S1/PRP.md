name: "P3.M3.T1.S1 — Write test_pane_immutability.sh Invariant C test suite (PRD §15.23 + §23)"
description: TEST-ONLY deliverable (PRD §15.23 "Pane immutability (Invariant C — load-bearing)" + §23). Create ONE new file `tests/test_pane_immutability.sh` defining 5 `test_*` functions (a–e) that validate §23 Invariant C (zero pane mutation of any session) against the REAL plugin on the isolated-socket harness WITH an attached client. This suite is the VALIDATION gate for the parallel §23 stack: the §22 driver clip (COMPLETE), the candidate pin (P3.M2.T2.S1 — parallel CONTRACT), the pane-geometry snapshot (P3.M2.T1.S1 — COMPLETE), and the drift-gated restore (P3.M2.T1.S2 — parallel CONTRACT). It CONSUMES all four; it adds NO production code. The assert shape is the COMPLETE gate's §4 recipe (`window_layout` + sorted `list-panes` byte-identical). run.sh AUTO-DISCovers `test_*.sh` via glob → NO run.sh edit needed (verified). SCOPE = `tests/test_pane_immutability.sh` ONLY (NEW file). Do NOT edit any script/PRD/CHANGELOG/tasks.json/run.sh.

---

## Goal

**Feature Goal**: Lock PRD §23 Invariant C ("Browsing, confirming, or cancelling must not move, resize, reorder, reset, or otherwise alter any property of any pane in any session") behind an executable, hermetic test suite that proves — with a REAL attached client on the isolated socket — that a candidate's pane geometry, the driver's original window, and bystander windows are all BYTE-IDENTICAL across the full open → flip → move-sessions → cancel / confirm cycle, and that the snapshot escape hatch holds the invariant trivially. This is the load-bearing validation the gate (`pane_immutability_verification.md` §7) "informs P3.M3.T1" target.

**Deliverable**: ONE new file — `tests/test_pane_immutability.sh` — defining exactly 5 public `test_*` functions (discovered + run by `tests/run.sh` via its existing `test_*.sh` glob) + 2 private `lp_immut_*` helpers:
- `test_no_candidate_pane_movement` — (a) candidate geometry byte-identical across flip+move+cancel.
- `test_no_status_grow_reflow` — (b) candidate geometry unchanged by the status 1→2 grow alone.
- `test_no_confirm_side_effects` — (c) on confirm, other windows + chosen window's pane geometry unchanged; only active-window selection moved.
- `test_original_window_intact` — (d) driver ORIG_WINDOW byte-identical after browse→cancel; the drift gate found no drift (snapshot==current → STEP 5 no-op → select-layout did NOT run).
- `test_snapshot_mode_invariant_holds` — (e) under `@livepicker-preview-mode snapshot`, no link → invariant holds trivially.

**Success Definition**: `bash tests/run.sh` exits 0; the 5 new tests PASS alongside the existing suite; each asserts `window_layout` + sorted `list-panes` byte-identical for the relevant window(s) using `assert_eq`; the REAL tmux server is byte-identical before/after the whole run (PRD §15 non-pollution, guaranteed structurally by the harness's socket isolation). The suite's candidate names (`immA`, `immB`) do not collide with any existing test fixture.

## User Persona

**Target User**: The plugin maintainer shipping §23 (for whom "no pane in any session ever moves" is an absolute invariant), the PRD §23 reviewer, and any future contributor whose change to `preview.sh`/`restore.sh`/`livepicker.sh` must not regress pane immutability.

**Use Case**: A regression breaks the candidate pin or the drift-gated restore (e.g. someone removes the `list-clients` guard, or makes STEP 5 unconditional again). `bash tests/run.sh` runs `test_no_candidate_pane_movement` / `test_original_window_intact`, which FAIL with a byte-identity diff, catching the regression before release.

**Pain Points Addressed**: PRD §23's namesake bug — "I selected a session and some of its panes resized / swapped places" — currently has NO executable guard. The clip/flip suites cover adjacent behavior (§22 driver clip; Invariant B window_active leave-no-trace) but NOT §23's pane-geometry byte-identity across the full cycle. This suite is that guard.

## Why

- **PRD §23 (Invariant C, absolute) + §15.23**: the validation section literally lists the 5 assertions this suite encodes (no candidate pane movement; no status-grow reflow; no confirm side-effects; original window intact; snapshot escape hatch) and states they "MUST be verified with a real attached client ... use the isolated-socket harness with a real client, and restore the user's live state afterward." This suite is the executable form of that checklist.
- **The gate (P3.M1.T1.S1 — COMPLETE) PROVED the mechanism + gives the assert shape**: `pane_immutability_verification.md` §1 ARM B proved a detached candidate pin holds geometry byte-identical (`16ec` layout, deterministically); ARM D proved flip is safe under per-window pinning; §4 gives the literal `window_layout` + sorted `list-panes` assert recipe; §6 condenses the gotchas. This suite wraps that proven mechanism in the FULL plugin flow (input-handler → preview → restore) so a regression anywhere in the §23 stack is caught.
- **Integration with the parallel §23 stack**: this suite CONSUMES (does not duplicate) the candidate pin (P3.M2.T2.S1), the snapshot (P3.M2.T1.S1), and the drift-gated restore (P3.M2.T1.S2). It is the integration test that proves the four pieces compose into Invariant C. Unlike `test_window_flip.sh`'s `lp_winflip_match_size` (which PRE-SIZED the candidate to dodge the link-time reflow BEFORE the pin existed), this suite asserts the PIN itself holds geometry byte-identical with NO test-side pre-sizing — so a candidate-pin regression is not hidden.

## What

No user-visible behavior (test file only). Each test:
1. Builds a detached multi-pane (and multi-window where flipping) candidate on the isolated socket.
2. Attaches a real client (`attach_test_client`), activates the picker (`$LIVEPICKER_SCRIPTS/livepicker.sh`), drives it via `$LIVEPICKER_SCRIPTS/input-handler.sh` (`type`/`next-window`/`next-session`/`confirm`/`cancel`).
3. Captures `#{window_layout}` + sorted `#{pane_id}:#{pane_left},#{pane_top},#{pane_width},#{pane_height}` before and after, asserts byte-identical via `assert_eq`.
4. Ends the picker lifecycle (`cancel`, or `confirm` for (c)) before `teardown_test` reaps the socket.

### Success Criteria

- [ ] `tests/test_pane_immutability.sh` exists; defines exactly 5 functions starting with `test_` (+ `lp_immut_*` helpers that do NOT start with `test_`).
- [ ] (a) `test_no_candidate_pane_movement`: a detached 3-window multi-pane candidate's W1 `window_layout` + sorted `list-panes` are byte-identical before highlight vs after flip×3 + move-session + cancel; the candidate's session `window-size` is unset/no-trace after cancel.
- [ ] (b) `test_no_status_grow_reflow`: candidate W1 geometry byte-identical before activate vs after activate (status==2), candidate NOT previewed.
- [ ] (c) `test_no_confirm_side_effects`: after confirm on candidate's chosen (non-active) window W, the candidate's OTHER windows' `window_layout` byte-identical, W is now the candidate's active window, and W's pane geometry byte-identical.
- [ ] (d) `test_original_window_intact`: driver ORIG_WINDOW geometry byte-identical pre-activate vs post-cancel; AND the `@livepicker-orig-pane-geometry` snapshot (read during the picker) equals the in-picker re-capture (proving the drift gate will find no drift → STEP 5 no-op → select-layout did NOT run).
- [ ] (e) `test_snapshot_mode_invariant_holds`: with `@livepicker-preview-mode snapshot`, `@livepicker-linked-id` stays EMPTY and candidate geometry byte-identical (never linked).
- [ ] `bash tests/run.sh` exit 0 (all new + existing tests PASS); `shellcheck tests/test_pane_immutability.sh` clean (or matches the sibling-test disable header).
- [ ] Candidate names `immA`/`immB` do not collide with existing fixtures (verified); the test sources nothing and calls no `setup_test`/`teardown_test`/`exit`.

## All Needed Context

### Context Completeness Check

_"If someone knew nothing about this codebase, would they have everything needed to implement this successfully?"_ — Yes. This PRP pins: the exact assert shape (the COMPLETE gate §4 — `window_layout` + sorted `list-panes` byte-identical, the literal recipe); the 5 test bodies mapped to work-item (a)–(e) + the gate's §1 ARMs; the harness contract (run.sh glob auto-discovery — NO run.sh edit; `setup_test` per-test socket + defer-OFF pin; `attach_test_client`; `assert_eq`/`fail`/`pass` in scope; `set -u` inherited); the input-handler action names + call form; the contract dependencies (candidate pin P3.M2.T2.S1 gate `[ clip ] && [ -z list-clients ]`; snapshot P3.M2.T1.S1 key `@livepicker-orig-pane-geometry` + its format; drift-gate P3.M2.T1.S2 no-op-on-no-drift; §22 driver clip pinning the driver); the gotchas (detached-only pin; type-to-highlight; flip selects in driver only → candidate @ids/active stable; @id not index; snapshot cleared at restore STEP 6 so read it DURING the picker); the candidate-naming conflict check; and the validation probes (shellcheck + the full suite + non-pollution).

### Documentation & References

```yaml
# MUST READ — load into the context window before writing.

- file: plan/004_2c5127285a90/architecture/pane_immutability_verification.md   # THE GATE (COMPLETE)
  why: §4 = the LITERAL assert shape for P3.M3.T1 (window_layout + sorted list-panes byte-identical, for a
        detached 3-pane candidate across pin→link→browse→flip→cancel). §1 ARM B = pin HOLDS byte-identical
        (detached, deterministic 16ec); ARM D = flip safe under per-window pinning; ARM E = client-bearing
        candidate is the NEGATIVE case (pin SKIPPED — NOT asserted as a pass here). §6 = gotchas (#2 client
        pty is 80x24; #4 resize-window sets shared size; #7 window_layout has a checksum; #9 create 2nd
        window BEFORE manual). §7 = "informs P3.M3.T1 (the assert shape + flip case)".
  section: "Decision box; §1 ARM B/D/E; §4 Assert shape; §5 escape hatch (snapshot); §6 Gotchas; §7"

- file: plan/004_2c5127285a90/P3M3T1S1/research/pane_immutability_test_findings.md   # THIS task's synthesis
  why: the 5 test-case designs (a–e), the harness patterns, the candidate-naming conflict check, the
        gotchas condensed for the test author, the anti-patterns (do NOT pre-size; do NOT assert the
        client-bearing case as a pass). Read FIRST after the gate.
  section: "§4 the 5 cases; §3 harness patterns; §5 naming; §6 gotchas; §7 anti-patterns"

- file: tests/test_window_flip.sh            # the CLOSEST sibling — mirror its header + lifecycle + capture idiom
  why: SAME harness contract (sourced by run.sh; attach_test_client; input-handler type/next-window/
        confirm/cancel; assert_eq/pass/fail). Its `lp_winflip_match_size` is the PRE-PIN workaround this
        suite deliberately does NOT use (we assert the pin holds). Its leave-no-trace capture
        (`list-windows -F '#{window_id}:#{window_active}:#{window_layout}'`) is reused for test (c). Its
        confirm-on-window flow is the template for (c). FINDING 2 (type to highlight) + FINDING 3 (flip
        selects in driver only → candidate active unchanged) are load-bearing for (a)/(c).
  pattern: 'tmux list-windows -t "=immA" -F "#{window_id}:#{window_active}:#{window_layout}"   # all-windows blob'
  gotcha: "test_window_flip PRE-SIZES via lp_winflip_match_size because the candidate pin did not exist yet.
        This suite MUST NOT pre-size — it asserts the pin (P3.M2.T2.S1) holds geometry byte-identical on its own."

- file: tests/test_preview_clip.sh            # the §22 clip suite — mirror its activate/cancel lifecycle + height assert
  why: shows the canonical attach → set @livepicker-preview-fit → livepicker.sh activate → (ops) → input-handler
        cancel lifecycle, and the `display-message -p '#{window_height}'` / `'#{window_layout}'` capture +
        assert_eq idiom. Test (b) (no status-grow reflow) and (d) (original window intact) build on this.
  pattern: 'AW="$(tmux list-windows -t "=$TEST_DRIVER_SESSION" -F "#{window_id}" -f "#{window_active}")"   # active @id'

- file: tests/setup_socket.sh                 # the harness — attach_test_client + the baseline fixtures
  why: attach_test_client [sess] spawns the real client pty (MUST call before livepicker.sh). Baseline
        fixtures: driver (window 0 single-pane + "extra" 3-pane window, "extra" ACTIVE = ORIG_WINDOW), alpha,
        beta. lp_sweep_orphans + teardown_socket guarantee non-pollution (the "restore live state" contract).
  section: "attach_test_client/detach_test_client; setup_socket baseline fixtures (driver:extra 3 panes)"

- file: tests/helpers.sh                      # the assertion helpers + setup_test/teardown_test
  why: fail/pass/assert_eq/assert_contains (signal failure ONLY via these; NEVER exit). setup_test pins
        @livepicker-preview-defer OFF (synchronous preview — no race on the geometry asserts). TEST_STATUS
        is the run.sh-aggregated pass/fail flag.
  section: "fail/pass/assert_eq; setup_test (defer OFF pin)"

- file: tests/run.sh                          # the runner — GLOB auto-discovery (NO edit needed)
  why: run.sh sources EVERY tests/test_*.sh via `for f in "$CURRENT_DIR"/test_*.sh` then discovers `test_*`
        via compgen. Creating tests/test_pane_immutability.sh is SUFFICIENT — run.sh picks it up. The work
        item's "Add to tests/run.sh" is SATISFIED STRUCTURALLY by the glob; do NOT edit run.sh.
  section: "the `for f in "$CURRENT_DIR"/test_*.sh` glob + `compgen -A function | grep '^test_'`"

- file: scripts/preview.sh                    # READ-ONLY — the snapshot-mode gate + link path (contracts)
  why: lines 121-126 = the snapshot gate (`if [ "$mode" = "snapshot" ]; preview_fallback` → capture-pane, NEVER
        link-window). So in snapshot mode @livepicker-linked-id stays empty (test e asserts this). The link
        path (where the candidate pin lives, P3.M2.T2.S1) is what test (a)/(c) exercise.
  section: "lines 113-126 (@livepicker-preview-mode gate); the link-window path"

- file: scripts/state.sh                      # READ-ONLY — ORIG_PANE_GEOMETRY (the snapshot key, for test d)
  why: `ORIG_PANE_GEOMETRY="@livepicker-orig-pane-geometry"` (P3.M2.T1.S1 — COMPLETE). Captured at activate
        STEP 2 (PRE-grow), format `'#{pane_id}:#{pane_left},#{pane_top},#{pane_width},#{pane_height}'` one
        line per pane (UNSORTED, pane order). Read it via `tmux show-option -gqv @livepicker-orig-pane-geometry`
        DURING the picker (it is cleared at restore STEP 6, AFTER STEP 5 — so it is gone after cancel).
  pattern: 'readonly ORIG_PANE_GEOMETRY="@livepicker-orig-pane-geometry"   # the drift-detection baseline'

- file: plan/004_2c5127285a90/P3M2T2S1/PRP.md   # CONTRACT — the candidate pin (parallel)
  why: defines the pin this suite validates: preview.sh pins a DETACHED candidate (window-size manual +
        resize-window -y H_cand) before link-window, gated `[ "$(opt_preview_fit)" = "clip" ] && [ -n cand_sess ]
        && [ -z "$(tmux list-clients -t "=$cand_sess")" ]`; restores on unlink + restore.sh STEP 1. Test (a)
        asserts the pin holds W1 byte-identical; test (a) also asserts the candidate session window-size is
        restored (no manual trace) after cancel.
  section: "pin gate (clip + detached); restore on unlink/STEP 1"

- file: plan/004_2c5127285a90/P3M2T1S2/PRP.md   # CONTRACT — the drift-gated restore (parallel)
  why: defines restore.sh STEP 5 (cancel-only): re-capture ORIG_WINDOW geometry, compare to
        @livepicker-orig-pane-geometry; on NO drift → pure no-op (NO select-layout); on drift → resize-window
        -y H_orig then select-layout. keep/keep-window skip STEP 5. Test (d) asserts the no-drift path: the
        snapshot (read during the picker) == the in-picker re-capture → STEP 5 will no-op.
  section: "STEP 5 no-op-on-no-drift; keep/keep-window skip"

- file: PRD.md                                # READ-ONLY — the spec
  why: §15.23 (the 5 validation bullets this suite encodes) + §23 (Invariant C absolute + Prevention regime +
        escape hatch) + §22 (the driver clip that pins the driver). §15.23's "MUST be verified with a real
        attached client ... use the isolated-socket harness ... restore the user's live state" is the mandate.
  section: "§15.23 Pane immutability; §23 Invariant C + Prevention regime + escape hatch; §22 clip"
```

### Current Codebase tree (run `ls tests/` in the project root)

```bash
tmux-livepicker/
├── scripts/                # READ-ONLY — the SUT (livepicker.sh activate, preview.sh link/pin/snapshot, restore.sh drift-gate)
├── tests/
│   ├── run.sh              # GLOB auto-discovers test_*.sh (NO edit needed)
│   ├── setup_socket.sh     # attach_test_client + baseline fixtures (driver:extra 3-pane ACTIVE, alpha, beta)
│   ├── helpers.sh          # fail/pass/assert_eq/assert_contains + setup_test (defer OFF)
│   ├── test_preview_clip.sh / test_window_flip.sh / test_restore.sh / test_pollution.sh ...  # sibling suites (read-only)
│   └── test_pane_immutability.sh   # <-- NEW (THIS task): 5 test_* + 2 lp_immut_* helpers
├── plan/004_2c5127285a90/
│   ├── architecture/pane_immutability_verification.md   # THE GATE — §4 assert shape
│   ├── P3M2T2S1/PRP.md   # candidate pin (CONTRACT)
│   ├── P3M2T1S1/ + P3M2T1S2/   # snapshot + drift-gate (CONTRACTs)
│   └── P3M3T1S1/{PRP.md (THIS file), research/pane_immutability_test_findings.md}
├── README.md / PRD.md / CHANGELOG.md   # READ-ONLY (untouched)
```

### Desired Codebase tree with files to be added and responsibility of file

```bash
# ONE new file. NO other file is touched (run.sh's glob auto-discovers it).
tests/test_pane_immutability.sh   # 5 test_* (a-e) validating §23 Invariant C on the isolated harness w/ a real
                                  # client; 2 lp_immut_* helpers (geometry capture + candidate fixture build).
                                  # Sourced by run.sh; consumes the candidate pin + snapshot + drift-gate + clip.
```

### Known Gotchas of our codebase & tmux 3.6b (gate §6 + test_window_flip findings)

```bash
# CRITICAL for this task (all verified by the COMPLETE gate + the sibling suites):

# 1. MUST use a REAL attached client (work item + PRD §15.23). Call attach_test_client BEFORE livepicker.sh.
#    Sessions created with -x -y alone are size-locked and HIDE the shared-window resize bug. The candidate
#    pin + §22 clip only prove out with a client on the driver. attach_test_client's `script` pty reports
#    80x24 (gate gotcha #2) -> driver usable height 23 (status 1) / 22 (status 2); detached candidates keep
#    their creation size. Measure window_height/window_layout LIVE; never hardcode.

# 2. Candidates MUST be DETACHED for the candidate pin (P3.M2.T2.S1) to fire. Its gate is
#    `[ clip ] && [ -z "$(tmux list-clients -t "=$cand_sess")" ]`. All fixtures use `new-session -d` ->
#    detached. A client-bearing candidate is the NEGATIVE case (pin SKIPPED, gate ARM E) -> do NOT assert it
#    as a pass here (P3.M2.T2.S1's own Level-2 ARM4 covers the skip). This suite's (a)-(c) use detached
#    candidates; (e) uses snapshot.

# 3. clip is the DEFAULT @livepicker-preview-fit. Do NOT set it to reflow (that disables the candidate pin
#    AND reflows). Leave fit unset (clip) OR set it explicitly to `clip` for clarity. setup_test does NOT
#    touch fit, so the default clip holds.

# 4. TYPE to highlight a specific candidate (its unique subsequence); `next-session` moves the highlight by
#    ONE in creation order (lands on alpha, not a named candidate) — test_window_flip FINDING 2. The type
#    loop is: `for c in i m m A; do "$LIVEPICKER_SCRIPTS/input-handler.sh" type "$c" >/dev/null 2>&1; done`.

# 5. FLIP selects in the DRIVER only (Invariant B; test_window_flip FINDING 3). The candidate's own
#    window_active is UNCHANGED by next-window. So the candidate's @ids + active are stable across flips ->
#    read candidate geometry via its HOME session `=immA`. (Confirm DOES change the candidate's active to W
#    — that is what (c) asserts.)

# 6. Address windows by @id (NEVER index — base-index 1, renumber-windows on). When a var holds `@N`, write
#    `-t "$WID"`, NOT `-t "@$WID"` (-> @@N, rc=1). Capture the active @id dynamically.

# 7. window_layout embeds per-node dims + a 4-hex CHECKSUM -> changes on ANY reflow/resize. Byte-identical
#    window_layout across an operation = strong no-mutation proof. ALSO capture sorted list-panes as the
#    explicit §23 per-pane proof. Assert BOTH (gate §4 / §6 #7).

# 8. @livepicker-orig-pane-geometry (the snapshot, P3.M2.T1.S1) is captured at activate STEP 2 (PRE-grow) and
#    CLEARED at restore STEP 6 (cancel). So read it DURING the picker (after activate, before cancel), NOT
#    after cancel (it is gone). Its format is UNSORTED pane order; to compare, re-capture with the SAME
#    unsorted format: `list-panes -F '#{pane_id}:#{pane_left},#{pane_top},#{pane_width},#{pane_height}'`.

# 9. Create ALL candidate windows BEFORE activating the picker (gate gotcha #9 — creating a 2nd window AFTER
#    the manual state can collide on an index). new-window/new-session/split-window use the BARE session name
#    (NOT "=immA" for those — gate gotcha #1; `=` IS valid for list-windows/display-message/link-window).

# 10. sleep 0.3 after activate (status grow + clip pin settle), 0.2 after each preview/flip/move (synchronous
#     link settles — defer is OFF), 0.2 after cancel (restore settle). The candidate pin's resize + the §22
#     clip's pin need a tick to land before measuring.

# 11. run.sh discovers `test_*` via `compgen -A function | grep '^test_'` -> every PUBLIC function must start
#     with `test_`; helpers must NOT (prefix `lp_immut_`). TABS for indent; quote everything; `set -u`
#     inherited (default every new var at read: `local lay_before="" panes_before=""`); `local` for all
#     function locals. No `set -e`; `2>/dev/null || true` on optional tmux reads.

# 12. setup_test pins @livepicker-preview-defer OFF (synchronous preview) — so the geometry asserts do NOT
#     race the async preview job. Do NOT re-enable defer. For test (e) set @livepicker-preview-mode snapshot
#     AFTER setup_test (per-test, fresh server).
```

## Implementation Blueprint

No data models (test file only). The "models" are two capture formats:
- **byte-identity blob**: `#{window_layout}` + sorted `#{pane_id}:#{pane_left},#{pane_top},#{pane_width},#{pane_height}` (the gate §4 assert shape).
- **all-windows blob**: `#{window_id}:#{window_active}:#{window_layout}` (reused from test_window_flip, for test c).

### Data models and structure

```bash
# The geometry capture helper echoes a combined comparable blob (layout line + sorted pane lines).
# assert_eq on the before/after blobs = byte-identity proof (gate §4).
lp_immut_geom() {       # args: $1 = window target (an @id or "=sess:@id" form)
	local wid="$1"
	# line 1 = the checksummed layout tree; following lines = sorted per-pane geometry (the §23 explicit proof).
	printf '%s\n' "$(tmux display-message -p -t "$wid" '#{window_layout}')"
	tmux list-panes -t "$wid" -F '#{pane_id}:#{pane_left},#{pane_top},#{pane_width},#{pane_height}' | sort
}

# The detached multi-pane (and multi-window) candidate builder. Creates the fixture BEFORE the picker opens
# (gotcha #9). sess = name; panes = number of panes in window 1 (1|2|3); wins = number of windows (1|2|3).
lp_immut_make_candidate() {   # args: $1=sess  $2=panes(in W1)  $3=windows
	local sess="$1" panes="${2:-3}" wins="${3:-3}" i
	tmux new-session -d -s "$sess" -x 80 -y 24          # W1, detached (BARE name — gotcha #1)
	if [ "$panes" -ge 2 ]; then tmux split-window -h -t "$sess"; fi
	if [ "$panes" -ge 3 ]; then tmux split-window -v -t "$sess:0"; fi
	for ((i=2; i<=wins; i++)); do tmux new-window -t "$sess" -a -n "w$i"; done
	# W1 (the multi-pane window) is left ACTIVE so it is the first preview target.
	tmux select-window -t "$sess:0"
}
```

### Implementation Tasks (ordered by dependencies)

```yaml
Task 1: READ the cited research + the sibling tests (NO writes)
  - READ: plan/004_2c5127285a90/architecture/pane_immutability_verification.md (THE GATE — §1 ARM B/D/E,
        §4 Assert shape, §5 escape hatch, §6 Gotchas, §7).
  - READ: plan/004_2c5127285a90/P3M3T1S1/research/pane_immutability_test_findings.md (THIS task's synthesis).
  - READ: tests/test_window_flip.sh (the CLOSEST sibling — header disable block, attach/activate/type/flip/
        confirm/cancel lifecycle, the all-windows blob capture, FINDING 2/3). NOTE: do NOT copy its
        lp_winflip_match_size (this suite asserts the pin holds WITHOUT pre-sizing).
  - READ: tests/test_preview_clip.sh (the §22 clip lifecycle + display-message -p '#{window_height}' capture).
  - READ: tests/setup_socket.sh (attach_test_client; baseline driver:extra 3-pane ACTIVE window), tests/helpers.sh
        (assert_eq/fail/pass; setup_test defer-OFF), tests/run.sh (the test_*.sh GLOB — NO run.sh edit).
  - READ (context only): scripts/preview.sh lines 113-126 (snapshot gate -> @livepicker-linked-id empty in
        snapshot mode), scripts/state.sh ORIG_PANE_GEOMETRY (the snapshot key + format).
  - PURPOSE: internalize the 5 cases, the assert shape, the harness contract, and the gotchas.

Task 2: CREATE tests/test_pane_immutability.sh — header + 2 helpers
  - HEADER: mirror test_window_flip.sh's shebang + comment block + `# shellcheck disable=SC2154,SC2016,SC2034,SC2086`
        (TEST_STATUS/fail/pass/assert_*/attach_test_client/$LIVEPICKER_SCRIPTS/$TEST_DRIVER_SESSION provided by
        run.sh's sources; the single-quote format strings + word-split idioms). DO NOT re-declare `set -u`
        (inherited). State this file SOURCES NOTHING and calls NO setup_test/teardown_test (run.sh owns the
        lifecycle). Cite PRD §15.23 + §23 + the gate §4.
  - HELPERS: lp_immut_geom (geometry blob) + lp_immut_make_candidate (detached fixture builder) — see Data
        models. Helpers MUST NOT start with `test_` (run.sh discovery).
  - FOLLOW pattern: test_window_flip.sh's function style (`local` for all; TABS; quoted expansions).

Task 3: test_no_candidate_pane_movement  (case a — the core Invariant C)
  - lp_immut_make_candidate immA 3 3   (W1 3-pane + W2 + W3); also `lp_immut_make_candidate immB 1 1` (move target).
  - attach_test_client; "$LIVEPICKER_SCRIPTS/livepicker.sh" >/dev/null; sleep 0.3.
  - w1="$(tmux list-windows -t '=immA' -F '#{window_id}' | sed -n '1p')"   # W1 @id (stable; candidate active==W1).
  - geom_before="$(lp_immut_geom "$w1")".
  - type "immA" (loop i m m A); sleep 0.2.   # highlight immA -> preview links W1 -> candidate pin fires.
  - Flip: next-window x3 (W1->W2->W3->W1); sleep 0.2 each.   # gate ARM D: flip safe under per-window pin.
  - Move sessions: backspace x4 (clear), type "immB"; sleep 0.2.   # unlink immA (restore its pin), link immB.
  - backspace x4, type "immA" again (return to immA); sleep 0.2.   # re-link immA (re-pin).
  - cancel; sleep 0.3.
  - geom_after="$(lp_immut_geom "$w1")".
  - ASSERT: assert_eq "$geom_after" "$geom_before" "candidate W1 pane geometry byte-identical across flip+move+cancel (Invariant C, detached)".
  - ASSERT: candidate immA session window-size restored (no manual trace): assert_eq "$(tmux show-options -t immA -v window-size 2>/dev/null || true)" "" "candidate window-size restored (no pin trace) after cancel".
  - FOLLOW pattern: test_window_flip.sh's type-loop + flip sequence + assert_eq.
  - GOTCHA: read W1 via its HOME @id (=immA's W1 @id, stable). Flip selects in DRIVER only -> W1 stays immA's active
        (Invariant B) so the @id is the right target before AND after.

Task 4: test_no_status_grow_reflow  (case b)
  - lp_immut_make_candidate immA 3 1   (W1 3-pane, single window).
  - w1="$(tmux list-windows -t '=immA' -F '#{window_id}' | sed -n '1p')"; geom_before="$(lp_immut_geom "$w1")".
  - attach_test_client; "$LIVEPICKER_SCRIPTS/livepicker.sh" >/dev/null; sleep 0.3.   # status 1->2; candidate NOT previewed.
  - assert_eq "$(tmux show-options -gv status)" "2" "status grew to 2".
  - geom_after="$(lp_immut_geom "$w1")".
  - ASSERT: assert_eq "$geom_after" "$geom_before" "candidate geometry unchanged by status-grow alone (not yet linked; detached immune)".
  - cancel; sleep 0.3.
  - GOTCHA: a DETACHED candidate is immune to the global status grow (no client to reflow to; gate §5 — the grow
        only disturbs CLIENT-BEARING sessions by 1 row). The candidate is NOT linked here (we did not type/highlight it).

Task 5: test_no_confirm_side_effects  (case c)
  - lp_immut_make_candidate immA 3 3   (W1 3-pane ACTIVE, W2, W3).
  - attach_test_client; "$LIVEPICKER_SCRIPTS/livepicker.sh" >/dev/null; sleep 0.3.
  - all_before="$(tmux list-windows -t '=immA' -F '#{window_id}:#{window_active}:#{window_layout}')".   # all-windows blob.
  - type "immA"; sleep 0.2.   # highlight -> preview links W1 (active).
  - next-window; sleep 0.2.   # flip to W2 (the chosen, NON-active window).
  - W="$(tmux show-option -gqv @livepicker-linked-id)".   # the chosen window @id.
  - w_geom_before="$(lp_immut_geom "$W")".   # W2's pane geometry pre-confirm.
  - # guard: W MUST be a non-active window of immA (else the test is vacuous):
    pre_active="$(printf '%s\n' "$all_before" | awk -F: '$2==1{print $1}')"; [ "$W" != "$pre_active" ] || { fail "test setup invalid: flip landed on the active window"; cancel; return 0; }.
  - confirm; sleep 0.3.   # lands client on (immA, W).
  - all_after="$(tmux list-windows -t '=immA' -F '#{window_id}:#{window_active}:#{window_layout}')".
  - ASSERT (other windows unchanged): for each window != W, its window_layout in all_after == all_before. Compute:
        others_before="$(printf '%s\n' "$all_before" | awk -F: -v w="$W" '$1!=w{print $1":"$3}' | sort)";
        others_after="$(printf '%s\n'  "$all_after"  | awk -F: -v w="$W" '$1!=w{print $1":"$3}' | sort)";
        assert_eq "$others_after" "$others_before" "confirm: immA's OTHER windows unchanged".
  - ASSERT (W is now active + W geometry unchanged): assert_eq "$(tmux list-windows -t '=immA' -F '#{window_id}' -f '#{window_active}')" "$W" "confirm: W is now immA's active window (only selection moved)";
        assert_eq "$(lp_immut_geom "$W")" "$w_geom_before" "confirm: W's pane geometry byte-identical (no reflow)".
  - GOTCHA: confirm DOES change immA's active to W (that is the point); within W ONLY selection moved. The candidate
        pin held W's geometry through the link, so confirming (select-window in the target) does not reflow it.

Task 6: test_original_window_intact  (case d — driver ORIG_WINDOW + drift-gate no-op)
  - The baseline driver's ACTIVE window is "extra" (3 panes) = ORIG_WINDOW. Grab it:
        orig="$(tmux display-message -p '#{window_id}')" AFTER attach (the client's active window).
    (Precondition: orig has >=2 panes — assert it, else the byte-identity is vacuous: [ "$(tmux list-panes -t "$orig" | wc -l)" -ge 2 ] || fail "precondition: driver ORIG_WINDOW not multi-pane".)
  - geom_pre="$(lp_immut_geom "$orig")".   # pre-activate baseline.
  - attach_test_client; "$LIVEPICKER_SCRIPTS/livepicker.sh" >/dev/null; sleep 0.3.   # §22 clip pins driver; snapshot captured (STEP 2).
  - Full browse: lp_immut_make_candidate immA 3 2 (W1 3-pane + W2); type "immA"; sleep 0.2; next-window; sleep 0.2;
        backspace x4; lp_immut_make_candidate immB 1 1; type "immB"; sleep 0.2.
  - Read the snapshot DURING the picker (cleared at restore STEP 6):
        snap="$(tmux show-option -gqv @livepicker-orig-pane-geometry)";
        cur_in_picker="$(tmux list-panes -t "$orig" -F '#{pane_id}:#{pane_left},#{pane_top},#{pane_width},#{pane_height}')".
  - cancel; sleep 0.3.   # restore: STEP 4 un-pins driver + status 1; STEP 5 drift-gate (cancel-only).
  - geom_post="$(lp_immut_geom "$orig")".
  - ASSERT (snapshot == in-picker current -> drift gate finds NO drift -> STEP 5 no-op -> select-layout did NOT run):
        assert_eq "$cur_in_picker" "$snap" "drift gate: snapshot == current geometry (no drift -> STEP5 no-op, select-layout did NOT run)".
  - ASSERT (ORIG_WINDOW byte-identical across the whole cycle):
        assert_eq "$geom_post" "$geom_pre" "driver ORIG_WINDOW pane geometry byte-identical across browse->cancel (§22 clip held it)".
  - GOTCHA: read the snapshot DURING the picker (it is cleared after cancel). The §22 clip pins the driver at
        pre-grow height so the status grow does not reflow the panes; after cancel status is restored to 1 and the
        window re-fits to the SAME 23-row usable height -> geometry byte-identical -> no drift -> STEP 5 no-op.

Task 7: test_snapshot_mode_invariant_holds  (case e — escape hatch)
  - lp_immut_make_candidate immA 3 1   (W1 3-pane, single window).
  - w1="$(tmux list-windows -t '=immA' -F '#{window_id}' | sed -n '1p')"; geom_before="$(lp_immut_geom "$w1")".
  - attach_test_client; tmux set-option -g @livepicker-preview-mode snapshot.
  - "$LIVEPICKER_SCRIPTS/livepicker.sh" >/dev/null; sleep 0.3.
  - type "immA"; sleep 0.2.   # preview_fallback (capture-pane) — NEVER link-window (preview.sh:121-126).
  - next-window; sleep 0.2.   # still no link in snapshot mode.
  - ASSERT (no link -> @livepicker-linked-id EMPTY): assert_eq "$(tmux show-option -gqv @livepicker-linked-id)" "" "snapshot mode: no window linked (capture-pane only)".
  - cancel; sleep 0.3.
  - geom_after="$(lp_immut_geom "$w1")".
  - ASSERT: assert_eq "$geom_after" "$geom_before" "snapshot mode: candidate geometry byte-identical (never linked -> invariant holds trivially)".
  - GOTCHA: in snapshot mode preview.sh takes the preview_fallback branch (lines 121-126) and NEVER reaches
        link-window -> @livepicker-linked-id stays empty -> no shared-window disturbance -> invariant trivial.

Task 8: VALIDATE (see Validation Loop) — shellcheck + the full suite + non-pollution. Confirm run.sh picked up the
        new file (it will — the glob). NO run.sh edit.
```

### Implementation Patterns & Key Details

```bash
# === File header (mirror test_window_flip.sh) ===
#!/usr/bin/env bash
# tests/test_pane_immutability.sh — tmux-livepicker PRD §15.23 + §23 Invariant C validation (P3.M3.T1.S1).
#
# SOURCED by run.sh (NEVER executed directly). Defines 5 test_* functions (a-e) that validate §23 Invariant C
# (zero pane mutation of any session) against the REAL plugin on the isolated-socket harness WITH a real
# attached client. CONSUMES the parallel §23 stack: §22 driver clip (COMPLETE), candidate pin (P3.M2.T2.S1),
# pane-geometry snapshot (P3.M2.T1.S1), drift-gated restore (P3.M2.T1.S2). Adds NO production code.
#
# Assert shape = the COMPLETE gate pane_immutability_verification.md §4: window_layout + sorted list-panes
# byte-identical. Unlike test_window_flip.sh's lp_winflip_match_size (a PRE-PIN workaround), this suite asserts
# the candidate pin holds geometry byte-identical with NO test-side pre-sizing.
#
# CONTRACT: run.sh sources setup_socket.sh + helpers.sh + every tests/test_*.sh (the GLOB auto-discovers this
# file — NO run.sh edit), then PER test calls setup_test "lp-$$-<name>" (-> fresh isolated -L socket + baseline
# fixtures + @livepicker-preview-defer OFF) -> resets TEST_STATUS=pass -> runs test_* in the CURRENT shell ->
# teardown_test. So when a test_* runs: bare `tmux` hits the isolated socket; attach_test_client /
# $LIVEPICKER_SCRIPTS / $TEST_DRIVER_SESSION / fail / pass / assert_* are ALL IN SCOPE; this file SOURCES
# NOTHING and calls NO setup_test/teardown_test. set -u is INHERITED (do NOT re-declare).
# shellcheck disable=SC2154,SC2016,SC2034,SC2086
#   SC2154: TEST_STATUS/fail/pass/assert_*/attach_test_client/$LIVEPICKER_SCRIPTS/$TEST_DRIVER_SESSION are
#           provided by run.sh's sources. SC2016/SC2034/SC2086: the single-quote format strings + word-split
#           idioms (mirrors the sibling test files).

# === Helpers (see Data models) ===
lp_immut_geom() { ... }              # geometry blob: layout line + sorted pane lines
lp_immut_make_candidate() { ... }    # detached multi-pane (+multi-window) fixture builder

# === The canonical before/after assert (every case) ===
geom_before="$(lp_immut_geom "$wid")"
# ... activate + browse + (cancel|confirm) ...
geom_after="$(lp_immut_geom "$wid")"
assert_eq "$geom_after" "$geom_before" "<window> pane geometry byte-identical across <op> (Invariant C)"

# === The type-to-highlight loop (test_window_flip FINDING 2) ===
local c
for c in i m m A; do "$LIVEPICKER_SCRIPTS/input-handler.sh" type "$c" >/dev/null 2>&1; done
sleep 0.2

# === Read a candidate window's stable @id (flip selects in DRIVER only -> candidate active unchanged) ===
w1="$(tmux list-windows -t '=immA' -F '#{window_id}' | sed -n '1p')"   # W1 @id; stable across link/unlink/flip

# === Test (d): read the snapshot DURING the picker (cleared at restore STEP 6) ===
snap="$(tmux show-option -gqv @livepicker-orig-pane-geometry)"        # P3.M2.T1.S1 key; read before cancel
cur_in_picker="$(tmux list-panes -t "$orig" -F '#{pane_id}:#{pane_left},#{pane_top},#{pane_width},#{pane_height}')"  # UNSORTED (match snapshot format)
# ... cancel ...
assert_eq "$cur_in_picker" "$snap" "drift gate: snapshot == current (no drift -> STEP5 no-op -> select-layout did NOT run)"

# GOTCHA (case a): do NOT pre-size the candidate. The candidate pin (P3.M2.T2.S1) holds geometry byte-identical
#   on its own; pre-sizing (test_window_flip's lp_winflip_match_size) would hide a pin regression.
# GOTCHA (case c): confirm changes immA's active to W (intended). Within W ONLY selection moved; the pin held W's
#   geometry. Other windows are untouched (distinct @id windows are independent — gate ARM D).
# GOTCHA (case d): the snapshot is cleared at restore STEP 6, so read it DURING the picker. snapshot==current
#   during the picker PROVES the drift gate (STEP 5) will find no drift at cancel -> no-op -> no select-layout.
# GOTCHA (case e): snapshot mode takes preview_fallback (capture-pane) and NEVER link-window -> linked-id empty.
```

### Integration Points

```yaml
HARNESS (consumed, read-only):
  - run.sh: GLOB `for f in "$CURRENT_DIR"/test_*.sh` auto-discovers this file -> NO run.sh edit. compgen
        discovers the 5 test_* functions. Per-test setup_test/teardown_test (fresh socket + defer OFF).
  - setup_socket.sh: attach_test_client (real client pty); baseline driver:extra 3-pane ACTIVE = ORIG_WINDOW
        (test d); teardown_socket -> non-pollution (the "restore live state" contract).
  - helpers.sh: fail/pass/assert_eq/assert_contains; setup_test pins @livepicker-preview-defer OFF.

SUT CONTRACTS (consumed, read-only — all landing in parallel/COMPLETE):
  - §22 driver clip (livepicker.sh T3, COMPLETE): pins driver window-size manual + height at activate -> the
        status grow does not reflow the shared preview window. Tests (b)/(d) rely on this.
  - candidate pin (P3.M2.T2.S1, parallel): preview.sh pins a DETACHED candidate before link-window (gated clip +
        list-clients empty), restores on unlink/STEP 1. Test (a) asserts it holds W1 byte-identical + restores
        window-size; test (c) asserts the chosen window's geometry is held through confirm.
  - snapshot (P3.M2.T1.S1, COMPLETE): @livepicker-orig-pane-geometry captured at activate STEP 2 (PRE-grow).
        Test (d) reads it DURING the picker to prove the drift gate's no-op path.
  - drift-gated restore (P3.M2.T1.S2, parallel): restore.sh STEP 5 cancel-only no-op on no drift. Test (d)
        asserts the no-drift path (snapshot==current -> no select-layout).
  - snapshot mode (preview.sh:121-126): @livepicker-preview-mode snapshot -> preview_fallback (capture-pane),
        NEVER link-window. Test (e) asserts linked-id empty + geometry byte-identical.

OUT OF SCOPE (do NOT implement here):
  - ANY production code (scripts/*). This is a TEST-ONLY deliverable.
  - run.sh (the glob auto-discovers; NO edit). PRD.md / CHANGELOG.md / README.md / any tasks.json.
  - The client-bearing-candidate NEGATIVE case as a PASS (the gate SKIPS the pin there — ARM E; P3.M2.T2.S1's
        own Level-2 ARM4 covers the skip). This suite's (a)-(c) use detached candidates; (e) uses snapshot.
```

## Validation Loop

### Level 1: Syntax & Style (Immediate Feedback)

```bash
cd /home/dustin/.config/tmux/plugins/tmux-livepicker
shellcheck tests/test_pane_immutability.sh
# Expected: zero errors (or only the SC2154/SC2016/SC2034/SC2086 the sibling tests disable — copy that header).
bash -n tests/test_pane_immutability.sh   # syntax sanity; Expected: no errors.
# Confirm the 5 public test_* + 2 helpers (helpers must NOT start with test_):
grep -nE '^test_[a-z_]+\(\)|^lp_immut_[a-z_]+\(\)' tests/test_pane_immutability.sh
# Expected: exactly 5 test_* + 2 lp_immut_* (geom, make_candidate).
# Confirm NO setup_test/teardown_test/exit/source inside test_* (run.sh owns the lifecycle):
! grep -nE '^\s*(setup_test|teardown_test|exit |source )' tests/test_pane_immutability.sh && echo "lifecycle owned by run.sh OK"
# Confirm run.sh will discover it (the glob — NO run.sh edit):
grep -n 'for f in "$CURRENT_DIR"/test_\*.sh' tests/run.sh   # the glob that auto-discovers this file
```

### Level 2: The 5 tests pass on the isolated harness (the core validation)

```bash
cd /home/dustin/.config/tmux/plugins/tmux-livepicker
# Run JUST this suite (via run.sh's discovery — it runs all, but eyeball the 5 new lines):
bash tests/run.sh 2>&1 | grep -E 'test_no_candidate_pane_movement|test_no_status_grow_reflow|test_no_confirm_side_effects|test_original_window_intact|test_snapshot_mode_invariant_holds|passed, .* failed'
# Expected: PASS for all 5; "0 failed".
# If a geometry assert FAILS: it prints got=[...] want=[...] — the diff shows WHICH pane dim moved. Root-cause:
#   - candidate W1 moved (case a): the candidate pin (P3.M2.T2.S1) did not fire or did not hold. Check the pin
#     gate (clip + list-clients empty) fired for immA, and that immA is detached.
#   - ORIG_WINDOW moved (case d): the §22 clip did not pin the driver, OR the drift-gate (P3.M2.T1.S2) ran
#     select-layout spuriously. Check snapshot==cur_in_picker (if they DIFFER, there WAS drift -> the §22 clip
#     regressed; investigate before weakening the assert).
#   - snapshot==cur_in_picker FAILED (case d): the snapshot (P3.M2.T1.S1) format != the re-capture format, OR
#     the §22 clip let the panes reflow during the picker. Confirm the unsorted format matches exactly.
#   - linked-id NON-empty in snapshot mode (case e): preview.sh did not take the snapshot branch — check
#     @livepicker-preview-mode was set to "snapshot" AFTER setup_test.
# Do NOT weaken an assert to make it pass — a failure here is a real §23 regression the suite exists to catch.
```

### Level 3: Full suite regression (existing tests stay green)

```bash
cd /home/dustin/.config/tmux/plugins/tmux-livepicker
bash tests/run.sh
# Expected: exit 0, all PASS. KEY suites to eyeball (this suite CONSUMES their SUTs; it must not perturb them):
#   - test_preview_clip.sh: the §22 driver clip still holds (this suite reuses the same activate/cancel lifecycle).
#   - test_window_flip.sh: Invariant B still holds (this suite reuses the type-to-highlight + flip idiom).
#   - test_restore.sh: byte-exact driver restore unchanged.
#   - test_pollution.sh: no client-session-changed fired.
# This suite shares NO state with siblings (per-test fresh socket), so a sibling failure is independent — but
# if a sibling regressed, confirm this suite did not modify any script (it must not).
```

### Level 4: Non-pollution (the core invariant, PRD §15 — "restore the user's live state")

```bash
cd /home/dustin/.config/tmux/plugins/tmux-livepicker
BEFORE="$(/usr/bin/tmux list-sessions -F '#{session_name}' 2>/dev/null | sort)"
bash tests/run.sh >/dev/null 2>&1
AFTER="$(/usr/bin/tmux list-sessions -F '#{session_name}' 2>/dev/null | sort)"
[ "$BEFORE" = "$AFTER" ] && echo "REAL SERVER UNTOUCHED" || echo "POLLUTION — abort"
# Expected: REAL SERVER UNTOUCHED. The harness isolates the socket (setup_socket PATH shim); attach_test_client's
# pty + the candidate fixtures live ONLY on the isolated -L socket; teardown_socket reaps them. The work item's
# "ALWAYS restore the user's live state" is satisfied STRUCTURALLY by the harness isolation (+ each test cancels
# its picker lifecycle before teardown).
```

### Level 5: Creative & Domain-Specific Validation

```bash
cd /home/dustin/.config/tmux/plugins/tmux-livepicker
# Confirm the assert shape is the gate §4 pair (window_layout + sorted list-panes) in the helper:
grep -q "window_layout" tests/test_pane_immutability.sh && grep -q "pane_left},#{pane_top},#{pane_width},#{pane_height}" tests/test_pane_immutability.sh \
  && echo "gate §4 assert shape present OK" || echo "FAIL: missing the §4 assert shape"
# Confirm NO pre-sizing (the candidate pin is what holds geometry — a pre-size would hide a regression):
! grep -q 'lp_winflip_match_size\|resize-window -x\|resize-window -y' tests/test_pane_immutability.sh \
  && echo "no test-side pre-sizing (asserts the pin) OK" || echo "check: this suite must NOT pre-size candidates"
# Confirm the candidate names do not collide with existing fixtures:
! grep -rqE 'new-session -d -s (immA|immB)\b' tests/test_window_flip.sh tests/test_preview_clip.sh tests/test_functional.sh 2>/dev/null \
  && echo "candidate names immA/immB collision-free OK" || echo "FAIL: immA/immB collide with an existing fixture"
# Confirm the snapshot is read DURING the picker (before cancel), not after (it is cleared at restore STEP 6):
awk '/show-option -gqv @livepicker-orig-pane-geometry/{found=1} found && /cancel/{print "snapshot read before cancel OK"; exit}' tests/test_pane_immutability.sh
# Expected: gate §4 shape present; no pre-sizing; names collision-free; snapshot read before cancel.
```

## Final Validation Checklist

### Technical Validation
- [ ] Level 1: `shellcheck tests/test_pane_immutability.sh` clean (or sibling-test disable header); `bash -n` passes; 5 `test_*` + 2 `lp_immut_*`; no setup_test/teardown_test/exit/source inside test_*; run.sh glob confirms discovery.
- [ ] Level 2: all 5 tests PASS (`test_no_candidate_pane_movement`, `test_no_status_grow_reflow`, `test_no_confirm_side_effects`, `test_original_window_intact`, `test_snapshot_mode_invariant_holds`); 0 failed.
- [ ] Level 3: `bash tests/run.sh` exit 0 (test_preview_clip / test_window_flip / test_restore / test_pollution green).
- [ ] Level 4: real tmux server byte-identical before/after (PRD §15 non-pollution / "restore live state").
- [ ] Level 5: gate §4 assert shape present; no test-side pre-sizing; candidate names collision-free; snapshot read before cancel.

### Feature Validation
- [ ] (a) candidate W1 geometry byte-identical across flip+move+cancel + candidate window-size restored (no pin trace).
- [ ] (b) candidate geometry unchanged by the status 1→2 grow alone (detached, not yet linked).
- [ ] (c) confirm: other windows unchanged, W is now active, W's pane geometry byte-identical.
- [ ] (d) ORIG_WINDOW byte-identical across browse→cancel + snapshot==in-picker-current (drift gate no-op → select-layout did NOT run).
- [ ] (e) snapshot mode: linked-id empty + candidate geometry byte-identical (never linked).
- [ ] Every geometry assert uses BOTH `window_layout` AND sorted `list-panes` (gate §4 pair).
- [ ] A real client is attached before activate in every test (work item mandate).

### Code Quality Validation
- [ ] Mirrors test_window_flip.sh's header + lifecycle + capture idiom (NOT its lp_winflip_match_size pre-sizing).
- [ ] Helpers prefixed `lp_immut_` (NOT `test_` — run.sh discovery); all function locals `local`; TABS; quoted.
- [ ] `set -u` inherited (not re-declared); no `set -e`; `2>/dev/null || true` on optional reads; `sleep` after activate/preview/flip/cancel.
- [ ] Each test ends its picker lifecycle (`cancel`/`confirm`) before teardown_test reaps the socket.

### Documentation & Deployment
- [ ] File header cites PRD §15.23 + §23 + the gate (pane_immutability_verification.md §4) + the consumed contracts (candidate pin / snapshot / drift-gate / clip).
- [ ] NO production code, run.sh, PRD.md, CHANGELOG.md, README.md, or tasks.json modified. ONLY `tests/test_pane_immutability.sh` (NEW).

---

## Anti-Patterns to Avoid

- ❌ Don't pre-size the candidate (test_window_flip's `lp_winflip_match_size`). That was a workaround BEFORE the candidate pin existed. This suite asserts the PIN holds geometry byte-identical with NO pre-sizing; pre-sizing would hide a candidate-pin regression.
- ❌ Don't create candidate windows AFTER activating the picker (gate gotcha #9 — can collide on an index). Build all fixtures BEFORE `livepicker.sh`.
- ❌ Don't assert the client-bearing-candidate pin as a PASS. That is the NEGATIVE case — the gate SKIPS the pin there (ARM E; `window-size manual` reverts their client view). P3.M2.T2.S1's own Level-2 ARM4 covers the skip. This suite's (a)-(c) use detached candidates; (e) uses snapshot.
- ❌ Don't read `@livepicker-orig-pane-geometry` AFTER cancel — it is cleared at restore STEP 6. Read it DURING the picker (test d).
- ❌ Don't use `next-session` to REACH a named candidate — it moves the highlight by ONE in creation order (lands on alpha). TYPE the candidate's unique subsequence (test_window_flip FINDING 2).
- ❌ Don't address windows by index (base-index 1, renumber on). Use the stable @id; write `-t "$WID"`, not `-t "@$WID"` (→ `@@N`).
- ❌ Don't call `setup_test`/`teardown_test`/`exit`/`source` inside test_* — run.sh owns the lifecycle; an `exit` would kill the runner. Signal failure ONLY via fail/assert_*.
- ❌ Don't edit run.sh to "add" the test — the `for f in "$CURRENT_DIR"/test_*.sh` glob auto-discovers it (verified). Creating the file is sufficient.
- ❌ Don't edit any script/PRD/CHANGELOG/README/tasks.json. This is a TEST-ONLY deliverable.
- ❌ Don't weaken a geometry assert to make it pass. A failure here is a real §23 regression the suite exists to catch — root-cause the pin/clip/drift-gate, do not relax the byte-identity check.
- ❌ Don't omit the real client (`attach_test_client`). The shared-window resize bug is HIDDEN without one (PRD §15.23); the pin + clip only prove out with a client on the driver.
- ❌ Don't drop the `sleep` after activate/preview/flip/cancel. Defer is OFF (synchronous) but the resize pin + link still need a tick to settle before measuring geometry.

---

## Confidence Score: 9/10

This task encodes a COMPLETE gate's literal assert shape (pane_immutability_verification.md §4 — `window_layout` + sorted `list-panes` byte-identical), proven byte-identical for the detached case (ARM B, deterministic `16ec`) and flip-safe (ARM D). The 5 cases map 1:1 to PRD §15.23's checklist + the work item's (a)–(e). The harness contract is fully specified (run.sh glob auto-discovery — NO run.sh edit; per-test setup_test socket + defer-OFF; attach_test_client; assert_eq/fail/pass in scope) and mirrors the two closest siblings (test_window_flip.sh's type-to-highlight + flip + confirm lifecycle; test_preview_clip.sh's activate/cancel + display-message capture). The contract dependencies are pinned (candidate pin P3.M2.T2.S1 gate; snapshot P3.M2.T1.S1 key+format+clear-timing; drift-gate P3.M2.T1.S2 no-op-on-no-drift; §22 driver clip). The candidate names (immA/immB) are verified collision-free. The residual 1/10 is: (a) test (d)'s "select-layout did NOT run" is INFERRED from byte-identical geometry + snapshot==current (the deterministic observable; direct select-layout instrumentation via a tmux hook is over-engineering and not the gate's ask); (b) test (a)/(c) depend on the candidate pin (P3.M2.T2.S1, parallel) actually landing as specified — if it does, these tests pass; if it does not, they FAIL (which is the suite's purpose); (c) test (d) depends on the §22 clip pinning the driver so the panes do not reflow during the picker (snapshot==current) — proven by test_preview_clip, but re-asserted here as the drift-gate no-op precondition. The implementer's job is to write 5 test functions + 2 helpers following proven sibling patterns — not to discover tmux behavior or design the assert shape.
