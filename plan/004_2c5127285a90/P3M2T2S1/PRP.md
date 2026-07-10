name: "P3.M2.T2.S1 — Pin candidate at link time + restore on unlink (CONDITIONAL on P3.M1.T1.S1; PRD §23 Invariant C)"
description: Implementation work item (PRD §23 "Prevention regime" bullet 2 / §22). The GATE (`architecture/pane_immutability_verification.md`, produced by COMPLETE P3.M1.T1.S1) returned a **CONDITIONAL YES**: ship the candidate pin for DETACHED candidates only, SKIP client-bearing candidates. At link time in `scripts/preview.sh`, when linking a NON-SELF candidate in `clip` mode and the candidate has NO attached client, freeze that candidate's session `window-size` to `manual` + pin its window height (`resize-window -y H_cand`), recording the candidate session + its prior window-size in two new RUNTIME state keys so it can be restored. Restore the prior window-size on every unlink: (a) preview.sh's self-session unlink path, (b) preview.sh's replace path (before linking the next), and (c) `scripts/restore.sh` STEP 1 (teardown, before unlinking the driver's preview link). Update `README.md` Known limitations: detached candidates are now pinned (no resize) in clip mode; client-bearing candidates still need `@livepicker-preview-mode snapshot`. SCOPE = preview.sh + state.sh + restore.sh + README.md (4 files; 2 new keys + 1 helper + pin/restore blocks + 1 doc bullet). The pane-geometry snapshot is P3.M2.T1.S1; the drift-gated restore is P3.M2.T1.S2 (parallel — append, do not conflict); the §23 test suite is P3.M3.T1.

---

## Goal

**Feature Goal**: Close the §23 "candidate windows linked in later are not pinned" gap. PRD §23 Prevention regime bullet 2: "Candidate windows linked in later must be protected just as well ... freeze each candidate at link time too: set the candidate's `window-size` to `manual` and pin its window to its captured geometry, and restore the candidate's prior `window-size` on unlink." Today an unpinned linked candidate's window is dragged to the driver's usable size (verification ARM A: 40→22) and its SOURCE session keeps that mutated size after the picker exits (the documented "Detached candidates still resize once at link time" limitation). This task pins the candidate at link time so its panes do NOT reflow, and restores its prior `window-size` on every unlink/teardown so no trace remains.

**Deliverable**: FOUR edited files:
1. `scripts/state.sh` — 2 new readonly RUNTIME keys (`STATE_CAND_PIN_SESSION`, `STATE_CAND_PIN_WS`) + both appended to `_STATE_RUNTIME_KEYS`.
2. `scripts/preview.sh` — 1 new helper `_preview_restore_cand_pin()` + the pin block before `link-window` + the helper call in BOTH unlink paths (self-session + replace) + 3 new locals.
3. `scripts/restore.sh` — the candidate-pin restore at the TOP of STEP 1 (inline copy of the helper logic) + 2 new locals.
4. `README.md` — replace the "Detached candidates still resize once at link time" Known-limitations bullet with the conditional-YES reality.

**Success Definition**: On a real `activate → browse detached candidate → (browse another | cancel | confirm)` cycle with an attached driver client (clip mode): (a) the detached candidate's pane geometry (`#{window_layout}` + per-pane dims) is BYTE-IDENTICAL before and after the link (verification ARM B2); (b) the candidate's session `window-size` is `manual` while linked and restored to its prior value (or unset) on unlink/teardown — no `@livepicker-*` residue; (c) a candidate WITH its own attached client is NOT pinned (the gate skips it — ARM E3 harm avoided); (d) `bash tests/run.sh` stays green; (e) the real tmux server is byte-identical before/after (PRD §15).

## User Persona

**Target User**: The end user browsing OTHER (detached) sessions with the picker on a real attached client, plus the P3.M3.T1 test author who will assert §23 byte-identical candidate pane geometry across a browse→cancel cycle, and the PRD §23 reviewer for whom "no pane in any session ever moves" is an absolute invariant.

**Use Case**: User opens the picker and flips through several detached candidate sessions. Before this task, each linked candidate's window was resized once to the driver's size and its source session kept that mutation. After this task, each detached candidate is frozen at its own geometry at link time and fully restored on unlink — the source session is untouched.

**Pain Points Addressed**: "I previewed a session and its panes were resized / its window stayed the wrong size after I cancelled." (PRD §23's namesake bug.) Plus the README-documented "Detached candidates still resize once at link time" limitation is REMOVED for the common detached+clip case.

## Why

- **PRD §23 (Invariant C, absolute) + Prevention regime bullet 2**: the §22 driver clip is "necessary but, as scoped today, insufficient: it pins the driver's `window-size` ... but candidate windows linked in later are not pinned." This task closes exactly that gap with the §23-prescribed candidate pin ("freeze each candidate at link time too ... and restore the candidate's prior `window-size` on unlink").
- **The GATE (P3.M1.T1.S1 — COMPLETE) makes the pin CONDITIONAL and corrects the recipe.** `pane_immutability_verification.md` verdict: ship the pin for DETACHED candidates (ARM B2 — byte-identical, deterministic) but SKIP client-bearing candidates (`window-size manual` REVERTS their client view to the creation size — ARM E3, harmful; the bare link does not disturb them anyway — ARM E4). The gate also corrects the work item's command forms: `set-option`/`show-options` REJECT the `=` prefix (gotcha #1) — use the BARE session name; and the pin only holds when the driver is ALSO manual, i.e. in `clip` mode (so gate on `opt_preview_fit == clip`).
- **Integration with existing features**: the §22 driver clip (livepicker.sh T3) already pins the DRIVER `window-size manual` + height at activate (COMPLETE), so at preview.sh link time the driver is already manual → candidate manual → both manual → the shared window holds its pinned size (ARM B2 conditions). restore.sh STEP 4 already restores the DRIVER's window-size; this task adds the symmetric CANDIDATE window-size save/restore. The candidate pin is the conceptual pair of the §22 driver pin.

## What

No user-visible behavior change in the successful (detached, clip) case beyond the FIX: detached candidates no longer resize at link time. Internal behavior:
- **pin (clip + detached + non-self)**: at link time, save the candidate's session `window-size`, set it `manual`, pin the window height (`resize-window -y H_cand`), record session + prior ws in state.
- **restore (every unlink)**: replay the candidate's prior `window-size` (or `set-option -u` when it had no override), clear the pin keys.
- **skip (client-bearing candidate)**: the gate skips the pin entirely; the bare link is safe (ARM E4); strict §23 there ⇒ `snapshot` (documented, not forced).
- **skip (reflow mode)**: the driver is not manual so the candidate pin cannot hold; skip to avoid pointless churn (reflow retains its documented resize behavior).

### Success Criteria

- [ ] `STATE_CAND_PIN_SESSION` + `STATE_CAND_PIN_WS` are readonly RUNTIME keys in state.sh (after `STATE_PREVIEW_WIN_ID`), both in `_STATE_RUNTIME_KEYS` (NOT in the ORIG_* block; NOT matched by the `@livepicker-orig-` grep).
- [ ] preview.sh pins the candidate BEFORE `link-window` iff `[ "$(opt_preview_fit)" = "clip" ] && [ -n "$cand_sess" ] && [ -z "$(tmux list-clients -t "=$cand_sess" 2>/dev/null)" ]`, using the BARE session name for `set-option`/`show-options` and `@src_id` for `display-message`/`resize-window`.
- [ ] preview.sh restores the previously-pinned candidate in BOTH unlink paths (self-session + replace) via the `_preview_restore_cand_pin` helper, BEFORE linking the next / selecting self.
- [ ] restore.sh STEP 1 restores the pinned candidate (inline copy) BEFORE the driver unlink, regardless of the H2 session-match guard.
- [ ] The candidate's prior `window-size` is replayed verbatim when non-empty, or `set-option -u` when it was empty/inherited (byte-exact, no trace — mirrors restore.sh STEP 4's driver window-size restore).
- [ ] README.md "Detached candidates..." bullet reflects the conditional-YES decision (pinned for detached+clip; client-bearing ⇒ snapshot).
- [ ] `bash tests/run.sh` exit 0; `shellcheck` clean on the 3 edited scripts; real tmux server byte-identical before/after.

## All Needed Context

### Context Completeness Check

_"If someone knew nothing about this codebase, would they have everything needed to implement this successfully?"_ — Yes. This PRP pins: the GATE verdict (CONDITIONAL YES — §1 of the research file); the TWO corrections to the work-item command forms (`=`-prefix rejection §2; clip-mode gate §3); the exact state-key design (RUNTIME, not ORIG_*, and WHY they must be in `_STATE_RUNTIME_KEYS` §4); the verbatim pin/restore blocks + the helper (Implementation Patterns); the three edit sites with their exact anchors (preview.sh local decl + self-session unlink block + replace-path unlink/link; restore.sh STEP 1 + local decl; state.sh runtime block + `_STATE_RUNTIME_KEYS`); the `check_session` reuse (candidate session in both modes); the §23 forbidden-list reconciliation (the candidate pin IS the §23-prescribed prevention, not a violation); the link-failure benign edge; the keep-vs-cancel restore correctness; the regression analysis; and the validation probes (shellcheck + an isolated-socket ARM-B2 reproduction via the REAL plugin + the negative client-bearing case + the existing suite + non-pollution).

### Documentation & References

```yaml
# MUST READ — load into the context window before editing.

- file: plan/004_2c5127285a90/P3M2T2S1/research/candidate_pin_findings.md
  why: THIS task's synthesis — the gate verdict, the two command-form corrections, the clip-mode gate,
        the state-key design, the three edit sites, the helper, the §23 reconciliation, the gotchas. Read FIRST.
  section: "§1 conditional (detached only); §2 command-form corrections; §3 clip gate; §4 state keys;
        §5 the three sites; §6 pin-before-link; §8 §23 reconciliation; §10 gotchas"

- file: plan/004_2c5127285a90/architecture/pane_immutability_verification.md   # THE GATE (COMPLETE)
  why: the CONDITIONAL-YES verdict this task implements. §4 has the verbatim recipes (pin + restore +
        assert shape). §1 ARM B2 = pin HOLDS byte-identically (detached); ARM E3 = pin HARMFUL
        (client-bearing); ARM E4 = bare link safe (client-bearing). §6 gotchas (#1 =-prefix, #5 detached
        reads creation size, #6 never -g window-size). §7 = the GATES P3.M2.T2 directive.
  section: "Decision box; §1 ARM B/E; §4 Recipes; §6 Gotchas #1/#5/#6; §7 GATES P3.M2.T2"

- file: plan/004_2c5127285a90/P3M1T1S1/research/candidate_pin_probe_findings.md   # the underlying probe
  why: the empirical evidence the gate synthesizes. §5 has the SAME recipes (pin/restore/assert). §6
        gotchas. §7 recommendation #1/#2 (conditional YES, skip client-bearing). Read for the raw evidence.
  section: "TL;DR; §5 CONFIRMED RECIPES; §6 gotchas; §7 recommendation"

- file: scripts/preview.sh            # Site B — the pin + helper + 2 unlink-path restores
  why: the link flow. preview_main local decl (~line 117) — append cand_sess cand_ws cand_h. The
        self-session unlink block (~lines 150-156) — add the helper call. The replace path: re-read
        linked_id (~line 216) + unlink (~line 221) + link-window (~line 230) + select (~line 237) —
        insert restore-previous after the re-read, insert the pin block BEFORE link-window. check_session
        (~line 142) already = candidate session in both modes (reuse as cand_sess).
  pattern: "tmux unlink-window -t "$current_session:$linked_id" 2>/dev/null || true   # mirror the guard idiom"
  gotcha: "the idempotent pre-link check (~line 196) + duplicate guard (~line 206) return 0 BEFORE the
        link flow — they re-preview the SAME already-linked window, so no restore/re-pin is wanted there.
        The restore-previous + pin-new logic goes ONLY in the actual-replace path (after both guards)."

- file: scripts/state.sh              # Site A — 2 new RUNTIME keys + _STATE_RUNTIME_KEYS
  why: the runtime-keys block (after STATE_PREVIEW_WIN_ID ~line 41) — add STATE_CAND_PIN_SESSION +
        STATE_CAND_PIN_WS. _STATE_RUNTIME_KEYS (~line 61) — append both. These are RUNTIME (transient),
        NOT ORIG_* (saved-state): they do NOT match clear_all_state's grep '@livepicker-orig-', so they
        MUST be in _STATE_RUNTIME_KEYS or they LEAK.
  pattern: "readonly STATE_PREVIEW_WIN_ID="@livepicker-preview-win-id"   # ... cleared via _STATE_RUNTIME_KEYS"
  gotcha: "name them @livepicker-cand-pin-* (a NEW family, distinct from @livepicker-cand-win-* flip-cursor
        keys). Do NOT put them in the ORIG_* block (they are written mid-browse, not at activate)."

- file: scripts/restore.sh            # Site C — candidate-pin restore at TOP of STEP 1 + 2 locals
  why: STEP 1 (~lines 57-79) — insert the candidate-pin restore as its own concern BEFORE the linked_id
        read / H2 session-match guard (the restore targets the CANDIDATE session, safe even if the driver
        unlink is skipped). restore_main local decl (line 57) — APPEND pin_sess pin_ws (P3.M2.T1.S2 may
        have ALREADY added saved_geom cur_geom h_orig in parallel; append to whatever is there — do not
        conflict). Header disable=SC1091,SC2153 covers the new STATE_CAND_PIN_* refs.
  pattern: "tmux set-option -u -t "$lp_rfit_ws_sess" window-size 2>/dev/null || true   # STEP 4 driver ws restore — MIRROR this exact unset-vs-replay logic"
  gotcha: "restore.sh is its OWN process under run-shell -> it CANNOT source preview.sh's helper. Inline
        the SAME logic (byte-for-byte identical). clear_all_state (STEP 6) clears STATE_CAND_PIN_* AFTER
        STEP 1, so they are readable here."

- file: scripts/livepicker.sh         # READ-ONLY — the §22 driver clip (the pattern to mirror + the clip gate)
  why: lines ~326-333 = T3 clip: `if [ "$(opt_preview_fit)" = "clip" ]; then ... tmux set-option -t
        "$lp_fit_sess" window-size manual; [ -n "$lp_fit_pre_h" ] && tmux resize-window -y "$lp_fit_pre_h"
        -t "$lp_fit_win" 2>/dev/null || true; fi` with the comment "NO '=' prefix on -t (set-option rejects
        it)". This is the EXACT pattern the candidate pin mirrors (manual + resize-window -y H), and the
        clip gate is the SAME gate the candidate pin reuses. Confirms the driver is manual at preview link time.
  pattern: 'tmux set-option -t "$lp_fit_sess" window-size manual   # NO "=" prefix; then resize-window -y H -t "$win"'
  gotcha: "the driver clip is gated on opt_preview_fit==clip; the candidate pin reuses the SAME gate (in
        reflow the driver is not manual so the candidate pin cannot hold)."

- file: scripts/utils.sh              # READ-ONLY — accessor signatures
  why: tmux_unset_opt (line 41) = the runtime-key clearer (does set-option -gu); used by preview.sh's
        self-path as `tmux_unset_opt "$STATE_LINKED_ID"`. set_state/get_state wrap tmux_set_opt/tmux_get_opt.
        The helper + restore use get_state / tmux_unset_opt / tmux set-option directly.
  pattern: "tmux_unset_opt "$STATE_LINKED_ID"   # the established runtime-key clearer idiom"

- file: README.md                     # Site D — Known limitations
  why: the "Detached candidates still resize once at link time" bullet (~line 213, under "Known
        limitations"). Replace it with the conditional-YES reality per work item §5 Mode A (YES branch).
  section: "'### Known limitations' -> the second bullet ('Detached candidates still resize...')"

- file: plan/004_2c5127285a90/P3M2T1S2/PRP.md   # the PARALLEL sibling (drift-gated restore) — CONTRACT
  why: P3.M2.T1.S2 is being implemented in parallel; it edits restore.sh STEP 5 + restore_main locals
        (adds saved_geom cur_geom h_orig). This task edits restore.sh STEP 1 + restore_main locals (adds
        pin_sess pin_ws). The two edits are in DIFFERENT steps (STEP 1 vs STEP 5) and APPEND different
        local names — no conflict. Treat P3.M2.T1.S2's local-decl extension as already present; APPEND to it.
  note: "Do NOT touch STEP 5 (P3.M2.T1.S2 owns it). Do NOT add saved_geom/cur_geom/h_orig (P3.M2.T1.S2 does)."

- file: PRD.md                        # READ-ONLY — the spec
  why: §23 (Invariant C + Prevention regime bullet 2 = the candidate pin prescription + the forbidden-list
        + the snapshot escape hatch) + §22 (clip mechanism + Control) + §15.23 (validation).
  section: "§23 'Prevention regime' bullet 2 + 'Forbidden during preview' + 'Control'; §22 Mechanism/Control; §15.23"

- url: https://github.com/tmux/tmux/blob/master/CHANGES  (window-size / set-option -t / list-clients semantics)
  why: confirms window-size is a per-SESSION option (-t isolates; -g is global); set-option -t accepts a
        bare session name but REJECTS the '='-prefixed target; list-clients -t "=$sess" accepts the '='
        prefix and returns empty for a detached session (the gate); resize-window -y N -t @id sets the
        shared window height; set-option -u -t sess unsets a session override (falls back to global).
  section: "set-option -t (session target, no '='); list-clients -t; window-size per-session; resize-window -y"
```

### Current Codebase tree (run `ls scripts/ tests/` in the project root)

```bash
tmux-livepicker/
├── scripts/
│   ├── preview.sh     # <-- Site B: helper + pin-before-link + 2 unlink-path restores + 3 locals
│   ├── state.sh       # <-- Site A: 2 new RUNTIME keys + _STATE_RUNTIME_KEYS
│   ├── restore.sh     # <-- Site C: candidate-pin restore at TOP of STEP 1 + 2 locals
│   ├── livepicker.sh  # READ-ONLY — §22 driver clip (the pattern + clip gate to mirror)
│   ├── utils.sh / options.sh / input-handler.sh / renderer.sh / layout.sh / rank.sh / session-mgmt.sh  # untouched
├── tests/
│   ├── test_preview_clip.sh / test_window_flip.sh / test_restore.sh  # regression guards (read-only)
│   ├── run.sh / setup_socket.sh / helpers.sh / test_*.sh  # untouched (P3.M3.T1 owns the §23 suite)
├── plan/004_2c5127285a90/
│   ├── architecture/pane_immutability_verification.md   # THE GATE (COMPLETE) — CONDITIONAL YES
│   ├── P3M1T1S1/research/candidate_pin_probe_findings.md # the underlying probe evidence
│   ├── P3M2T1S2/PRP.md                                   # parallel sibling (restore STEP 5) — CONTRACT
│   └── P3M2T2S1/{PRP.md (THIS file), research/candidate_pin_findings.md}
├── README.md          # <-- Site D: Known limitations bullet
├── PRD.md             # §22 / §23 / §15.23 (READ-ONLY)
└── CHANGELOG.md       # untouched (P4 owns changeset docs)
```

### Desired Codebase tree with files to be added and responsibility of file

```bash
# No NEW files. This task EDITS four existing files:
scripts/preview.sh    # +helper _preview_restore_cand_pin; +pin block before link-window; +helper call in 2 unlink paths; +3 locals
scripts/state.sh      # +2 readonly RUNTIME keys (STATE_CAND_PIN_SESSION/WS); +both in _STATE_RUNTIME_KEYS
scripts/restore.sh    # +candidate-pin restore at TOP of STEP 1 (inline); +2 locals (pin_sess pin_ws)
README.md             # Known limitations "Detached candidates..." bullet -> conditional-YES reality
# research/candidate_pin_findings.md already written (this PRP's synthesis)
```

### Known Gotchas of our codebase & tmux 3.6b

```bash
# CRITICAL for this task (all verified by the COMPLETE gate P3.M1.T1.S1):

# 1. set-option / show-options REJECT the '='-prefixed session target; list-clients / list-windows /
#    display-message / link-window / select-window ACCEPT it. The work item §3a/3b literally writes
#    `set-option -t "=$S"` — that rc=1's ("no such window"). Use the BARE session name for set-option/
#    show-options (mirror the §22 driver clip: `set-option -t "$lp_fit_sess" window-size manual`).
#    list-clients keeps the '=' prefix: `list-clients -t "=$cand_sess"` (the detached gate).

# 2. NEVER `set-option -g window-size` (global manual disconnects the window from the client -> jumps to
#    the creation size). Per-session `-t "$cand_sess"` only. (Same rule as the §22 driver clip, gotcha #6.)

# 3. The pin is CONDITIONAL on the candidate being DETACHED. `window-size manual` on a client-bearing
#    candidate REVERTS its client view to the creation size (ARM E3 — a BIGGER mutation than leaving it).
#    The bare link does NOT disturb a client-bearing candidate (ARM E4). So GATE the pin on
#    `[ -z "$(tmux list-clients -t "=$cand_sess" 2>/dev/null)" ]` and SKIP client-bearing candidates.
#    This is the single most important correctness rule.

# 4. ALSO gate the pin on `[ "$(opt_preview_fit)" = "clip" ]`. window-size is per-SESSION; the shared
#    window holds its pinned size ONLY when BOTH driver and candidate are manual. In reflow mode the
#    driver is NOT manual (the §22 clip is skipped), so the candidate pin cannot hold (the driver's latest
#    client still drags the shared window) — pinning there is pointless churn. reflow retains its
#    documented resize behavior. The RESTORE needs no clip gate — it is gated on STATE_CAND_PIN_SESSION
#    non-empty (only ever set in clip+detached), so it is a natural no-op in reflow mode.

# 5. `resize-window -y "$cand_h" -t "$src_id"` — src_id already holds @N; do NOT prepend '@' (-> @@N, rc=1).
#    cand_h via `display-message -p -t "$src_id" '#{window_height}'` reads the CREATION size for a detached
#    candidate — that is CORRECT here (we pin at the candidate's OWN natural size; ARM B2 pinned at 40).
#    The gate's gotcha #5 (window_height needs a client) is about ASSERT measuring, not pinning.

# 6. The candidate pin IS the §23-prescribed prevention, NOT a §23 violation. §23 forbids resize-window
#    "during preview" EXCEPT it explicitly prescribes "freeze each candidate at link time: set window-size
#    manual and pin its window to its captured geometry." So manual + resize-window -y H_cand (setting the
#    window to its OWN height = a freeze, not a reflow) is the sanctioned candidate mutation alongside the
#    §22 driver pin. Do NOT be paralyzed by the forbidden list. (restore-time resize is the OTHER sanctioned
#    exception — P3.M2.T1.S2.)

# 7. STATE_CAND_PIN_* are RUNTIME keys, NOT ORIG_* saved-state. They are written MID-BROWSE (preview.sh
#    link) and read on unlink/teardown. They do NOT match clear_all_state's grep '@livepicker-orig-' ->
#    they MUST be in _STATE_RUNTIME_KEYS or they LEAK. Do NOT put them in the ORIG_* block.

# 8. restore.sh is its OWN process under run-shell -> it CANNOT source preview.sh's helper. Inline the
#    SAME restore logic in restore.sh STEP 1 (byte-for-byte identical). clear_all_state (STEP 6) clears
#    STATE_CAND_PIN_* AFTER STEP 1, so the reads succeed in STEP 1.

# 9. check_session (preview.sh ~line 142) ALREADY holds the candidate session in BOTH modes (session mode
#    = $S; window mode = ${S%%:*}). Reuse it as cand_sess — do NOT re-derive. It is computed BEFORE the
#    self-session guard, so it is in scope throughout the link flow.

# 10. The restore-previous + pin-new logic goes ONLY in the actual-replace path (after the idempotent
#     pre-link check ~line 196 + the duplicate guard ~line 206, which return 0 for a SAME-window re-preview
#     — no restore/re-pin wanted there). The self-session path gets ONLY the restore-previous helper call.

# 11. TABS for indent; NO `set -e` (house style — guard each tmux call `2>/dev/null || true`); `set -u`
#     inherited (default every new var at read, e.g. cand_ws="" / cand_h=""). SC2153 (file-wide in all
#     three scripts) covers the new STATE_CAND_PIN_* readonly refs. No new shellcheck directive.

# 12. P3.M2.T1.S2 (parallel) extends restore_main's local decl with saved_geom cur_geom h_orig AND reworks
#     STEP 5. This task APPENDS pin_sess pin_ws to the local decl and edits STEP 1. Different steps, different
#     local names -> no conflict. When editing, APPEND to whatever the current local decl is.
```

## Implementation Blueprint

No new data models — this task adds 2 state keys + 1 bash helper + pin/restore blocks. The "models" are the two `@livepicker-cand-pin-*` options (session name string + prior window-size string).

### Data models and structure

```bash
# state.sh — 2 new RUNTIME keys (PRD §23 candidate-pin tracking). Mirror the STATE_* family.
readonly STATE_CAND_PIN_SESSION="@livepicker-cand-pin-session"   # session name of the candidate pinned at link time (P3.M2.T2.S1, PRD §23); empty = none pinned; cleared via _STATE_RUNTIME_KEYS
readonly STATE_CAND_PIN_WS="@livepicker-cand-pin-ws"             # that candidate's prior session window-size (empty = had no session override / inherited global -> restore UNSETS our manual); cleared via _STATE_RUNTIME_KEYS

# The captured values:
#   STATE_CAND_PIN_SESSION = bare session name, e.g. "alpha" (or the window-mode candidate's session).
#   STATE_CAND_PIN_WS      = the candidate's prior `show-options -t alpha -v window-size` value,
#                            e.g. "" (no override, the common detached case -> restore set-option -u),
#                                 "latest"/"manual"/"largest"/"smallest" (a prior override -> replay).
```

### Implementation Tasks (ordered by dependencies)

```yaml
Task 1: READ the cited research + the exact edit anchors (NO writes)
  - READ: plan/004_2c5127285a90/P3M2T2S1/research/candidate_pin_findings.md (THIS task's synthesis — FIRST)
  - READ: plan/004_2c5127285a90/architecture/pane_immutability_verification.md (THE GATE — Decision box,
        §1 ARM B/E, §4 Recipes, §6 Gotchas #1/#5/#6, §7 GATES P3.M2.T2)
  - READ: scripts/preview.sh — preview_main local decl (~117), check_session (~142), self-session unlink
        block (~150-156), idempotent pre-link check (~196), duplicate guard (~206), replace path
        (re-read linked_id ~216, unlink ~221, link-window ~230, select ~237). preview_fallback placement.
  - READ: scripts/state.sh — runtime-keys block (after STATE_PREVIEW_WIN_ID ~41), _STATE_RUNTIME_KEYS (~61),
        clear_all_state's grep '@livepicker-orig-' (confirms STATE_CAND_PIN_* need the explicit list).
  - READ: scripts/restore.sh — restore_main local decl (line 57), STEP 1 (~57-79, the linked_id read +
        H2 session-match guard + unlink), STEP 4 window-size restore (the unset-vs-replay pattern to mirror).
  - READ (context only): scripts/livepicker.sh lines ~326-333 (the §22 driver clip — the EXACT manual +
        resize-window -y H pattern + the clip gate + the "NO '=' prefix" comment), scripts/utils.sh
        (tmux_unset_opt line 41), README.md Known limitations (~213).
  - PURPOSE: internalize the conditional (detached only), the two command-form corrections, the clip gate,
        the state-key placement, the three edit sites, and the §23 reconciliation.

Task 2: MODIFY scripts/state.sh — add the 2 RUNTIME keys + extend _STATE_RUNTIME_KEYS
  - ADD: two readonly lines (STATE_CAND_PIN_SESSION, STATE_CAND_PIN_WS) in the runtime-keys block,
        IMMEDIATELY AFTER STATE_PREVIEW_WIN_ID and BEFORE the "--- saved-state CONTRACT keys" comment.
        Inline comments cite PRD §23 + the cleared-via-_STATE_RUNTIME_KEYS note.
  - APPEND: `$STATE_CAND_PIN_SESSION $STATE_CAND_PIN_WS` to the _STATE_RUNTIME_KEYS string (~line 61).
  - FOLLOW pattern: STATE_PREVIEW_WIN_ID / STATE_CAND_WIN_* (readonly UPPER_SNAKE; @livepicker-* option;
        "cleared via _STATE_RUNTIME_KEYS" comment).
  - DO NOT: put them in the ORIG_* block; do NOT hand-clear in clear_all_state (the explicit runtime list
        clears them); do NOT name them @livepicker-orig-* (they are transient, not saved-state).
  - NAMING: STATE_CAND_PIN_SESSION / STATE_CAND_PIN_WS (a NEW CAND_PIN family, distinct from CAND_WIN).
  - PLACEMENT: scripts/state.sh, runtime-keys block, after STATE_PREVIEW_WIN_ID.

Task 3: MODIFY scripts/preview.sh — add the helper + the pin block + 2 unlink-path restores + locals
  - ADD helper: `_preview_restore_cand_pin()` defined AFTER preview_fallback() and BEFORE preview_main()
        (see Implementation Patterns). Reads STATE_CAND_PIN_SESSION; if set, replays pin_ws (or set-option
        -u when empty) on the BARE session, then tmux_unset_opt both keys. Idempotent.
  - EXTEND preview_main local decl (~line 117): APPEND `cand_sess cand_ws cand_h`.
  - SELF-SESSION UNLINK PATH (~lines 150-156): inside the `if [ -n "$linked_id" ]` block (the cross-session
        preview is being dropped because the user navigated to self), call `_preview_restore_cand_pin`
        BEFORE the unlink-window. (Closes the dangling-pin-during-self-browse gap; restore.sh STEP 1 also
        covers it, but the contract §3b says "preview.sh's unlink path".)
  - REPLACE PATH (the actual different-window link, after both guards): AFTER re-reading linked_id (~216)
        and BEFORE the unlink-window (~221), call `_preview_restore_cand_pin` (restore the previous
        candidate). THEN, BEFORE `link-window` (~230), insert the pin block (see Implementation Patterns):
        cand_sess="$check_session"; gate [clip] && [detached]; save ws (BARE); capture cand_h; set manual
        (BARE); resize-window -y cand_h -t "$src_id"; set_state both keys.
  - FOLLOW pattern: the §22 driver clip (livepicker.sh ~329-333) for manual + resize-window -y H + the
        bare-session set-option; the existing `2>/dev/null || true` best-effort guards; tmux_unset_opt for
        clearing runtime keys (mirror the self-path's `tmux_unset_opt "$STATE_LINKED_ID"`).
  - GOTCHA: BARE session name for set-option/show-options (NO '='); '=' for list-clients; @src_id (no extra
        '@') for display-message/resize-window; reuse check_session as cand_sess; pin goes ONLY in the
        replace path (not the idempotent/duplicate guards); the pin is BEFORE link-window (ARM B2 verified).

Task 4: MODIFY scripts/restore.sh — candidate-pin restore at TOP of STEP 1 + 2 locals
  - EXTEND restore_main local decl (line 57): APPEND `pin_sess pin_ws` (P3.M2.T1.S2 may have already added
        saved_geom cur_geom h_orig — APPEND to whatever is there; do not conflict).
  - INSERT at the TOP of STEP 1 (before the `linked_id="$(get_state ...)"` read, as its own concern): read
        STATE_CAND_PIN_SESSION; if set, replay pin_ws (or set-option -u when empty) on the BARE session
        (inline copy of the helper logic — restore.sh is a separate process). Place it BEFORE the H2
        session-match guard so it runs regardless of whether the driver unlink is skipped (the restore
        targets the CANDIDATE session, always safe).
  - FOLLOW pattern: restore.sh STEP 4 driver window-size restore (the unset-vs-replay logic — `if [ -n
        "$lp_rfit_ws" ]; then set-option -t ... window-size "$lp_rfit_ws"; else set-option -u -t ...
        window-size; fi`); the `2>/dev/null || true` guards.
  - GOTCHA: inline (not the helper) — separate process; reads precede clear_all_state (STEP 6); BARE session.

Task 5: MODIFY README.md — Known limitations bullet (Mode A, YES branch)
  - REPLACE the "Detached candidates still resize once at link time" bullet (~line 213) with the
        conditional-YES reality: detached candidates are now PINNED (no resize) in clip mode; candidates
        with their own attached client cannot be pinned (manual reverts their client view) -> snapshot for
        strict immutability there. (See Implementation Patterns for the exact wording.)
  - DO NOT: edit any other README section; do NOT touch PRD.md / CHANGELOG.md (P4 owns changeset docs).

Task 6: VALIDATE (see Validation Loop) — shellcheck + isolated-socket ARM-B2 probe (pin holds byte-
        identical; restore on unlink/teardown; client-bearing candidate NOT pinned) + existing suite +
        non-pollution. The formal §23 test suite is P3.M3.T1's deliverable (a SEPARATE task).
```

### Implementation Patterns & Key Details

```bash
# === Site A: scripts/state.sh — runtime-keys block (insert after STATE_PREVIEW_WIN_ID) ===
readonly STATE_PREVIEW_WIN_ID="@livepicker-preview-win-id"      # ... (existing)
readonly STATE_CAND_PIN_SESSION="@livepicker-cand-pin-session"  # session name of the candidate pinned at link time (P3.M2.T2.S1, PRD §23); empty = none pinned; cleared via _STATE_RUNTIME_KEYS
readonly STATE_CAND_PIN_WS="@livepicker-cand-pin-ws"            # that candidate's prior session window-size (empty = had no session override / inherited global -> restore UNSETS our manual pin); cleared via _STATE_RUNTIME_KEYS
# ... (the "--- saved-state CONTRACT keys" comment + ORIG_* block unchanged) ...

# === Site A: scripts/state.sh — _STATE_RUNTIME_KEYS (append the 2 new keys) ===
readonly _STATE_RUNTIME_KEYS="$STATE_MODE $STATE_LIST $STATE_FILTER $STATE_INDEX $STATE_LINKED_ID $STATE_TAB_CURRENT_TMPL $STATE_TAB_INACTIVE_TMPL $STATE_PREVIEW_SEQ $STATE_PREVIEW_TARGET $STATE_SCROLL $STATE_CLIENT_WIDTH $STATE_RENDER_CACHE $STATE_CAND_WIN_SESSION $STATE_CAND_WIN_LIST $STATE_CAND_WIN_CURSOR $STATE_PREVIEW_WIN_ID $STATE_CAND_PIN_SESSION $STATE_CAND_PIN_WS"


# === Site B: scripts/preview.sh — NEW helper (after preview_fallback, before preview_main) ===
# P3.M2.T2.S1 (PRD §23): restore a previously-pinned candidate's window-size. Called from preview.sh's
# TWO unlink paths (self-session + replace) BEFORE the unlink/link, so the candidate session returns to
# its prior window-size (no trace of our manual pin). Reads STATE_CAND_PIN_SESSION/WS; if set, replays the
# prior window-size (or UNSETS the session override when the prior value was empty/inherited) on the BARE
# session name, then clears both keys. No-op when nothing was pinned. Idempotent (clears state after
# restoring). restore.sh STEP 1 has its OWN inline copy (separate process under run-shell — cannot source
# this helper). The pin was detached-only (preview.sh gate), so restoring window-size is safe (no client
# to fight). NO '=' prefix on set-option -t (gotcha #1; mirror the §22 driver clip).
_preview_restore_cand_pin() {
	local pin_sess pin_ws
	pin_sess="$(get_state "$STATE_CAND_PIN_SESSION" "")"
	[ -z "$pin_sess" ] && return 0
	pin_ws="$(get_state "$STATE_CAND_PIN_WS" "")"
	if [ -n "$pin_ws" ]; then
		tmux set-option -t "$pin_sess" window-size "$pin_ws" 2>/dev/null || true
	else
		tmux set-option -u -t "$pin_sess" window-size 2>/dev/null || true
	fi
	tmux_unset_opt "$STATE_CAND_PIN_SESSION"
	tmux_unset_opt "$STATE_CAND_PIN_WS"
}

# === Site B: scripts/preview.sh — preview_main local decl (append 3 locals) ===
# BEFORE: local S="${1:-}" chosen_win="${2:-}" expected_seq="${3:-}" current_session orig_window linked_id src_id w_sess w_idx cur_seq check_session
# AFTER (append cand_sess cand_ws cand_h):
	local S="${1:-}" chosen_win="${2:-}" expected_seq="${3:-}" current_session orig_window linked_id src_id w_sess w_idx cur_seq check_session cand_sess cand_ws cand_h

# === Site B: scripts/preview.sh — SELF-SESSION UNLINK PATH (add the helper call) ===
# Inside the `if [ -n "$current_session" ] && [ "$check_session" = "$current_session" ]; then` block,
# at the start of the `if [ -n "$linked_id" ]; then` sub-block (BEFORE the unlink-window):
	if [ -n "$linked_id" ]; then
		# P3.M2.T2.S1 (PRD §23): restore a pinned candidate before dropping its link (switching to self).
		_preview_restore_cand_pin
		tmux unlink-window -t "$current_session:$linked_id" 2>/dev/null || true
		tmux_unset_opt "$STATE_LINKED_ID"
	fi

# === Site B: scripts/preview.sh — REPLACE PATH (restore previous + pin new, around the link) ===
# After `linked_id="$(get_state "$STATE_LINKED_ID" "")"` (the re-read) and BEFORE the unlink-window:
	# P3.M2.T2.S1 (PRD §23): restore the PREVIOUSLY-pinned candidate's window-size before unlinking its
	# window + linking the next. Idempotent (clears STATE_CAND_PIN_*). No-op if nothing was pinned.
	_preview_restore_cand_pin
	# Drop the previous preview from the current session (NO -k; source keeps it).
	if [ -n "$linked_id" ]; then
		tmux unlink-window -t "$current_session:$linked_id" 2>/dev/null || true
	fi

	# P3.M2.T2.S1 (PRD §23 Prevention-regime bullet 2): PIN THE NEW CANDIDATE at link time, CONDITIONAL.
	# GATE (pane_immutability_verification.md §1/§7): (1) clip mode — the driver must be manual too, else
	# its latest client drags the shared window and the candidate pin cannot hold (reflow retains its
	# documented resize behavior); (2) NON-SELF (we are past the self-session guard); (3) DETACHED — a
	# client-bearing candidate is HARMED by `window-size manual` (ARM E3: reverts its client view to the
	# creation size); the bare link does NOT disturb it (ARM E4), so skipping the pin there is safe.
	# Under the gate: freeze the candidate's session window-size to manual + pin its window height, so the
	# shared window keeps the candidate's geometry (ARM B2: byte-identical, deterministic). Record the
	# candidate session + prior window-size so _preview_restore_cand_pin / restore.sh STEP 1 can undo it.
	# BARE session name for set-option/show-options (gotcha #1 — set-option REJECTS '='; list-clients takes
	# it). cand_h reads the detached candidate's creation size — CORRECT (we pin at its OWN natural size).
	# resize-window -y cand_h is the §23-SANCTIONED candidate pin (NOT a violation — §23 prescribes it).
	cand_sess="$check_session"
	if [ "$(opt_preview_fit)" = "clip" ] && [ -n "$cand_sess" ] \
		&& [ -z "$(tmux list-clients -t "=$cand_sess" 2>/dev/null)" ]; then
		cand_ws="$(tmux show-options -t "$cand_sess" -v window-size 2>/dev/null || true)"
		cand_h="$(tmux display-message -p -t "$src_id" '#{window_height}' 2>/dev/null || true)"
		tmux set-option -t "$cand_sess" window-size manual 2>/dev/null || true
		if [ -n "$cand_h" ]; then
			tmux resize-window -y "$cand_h" -t "$src_id" 2>/dev/null || true
		fi
		set_state "$STATE_CAND_PIN_SESSION" "$cand_sess"
		set_state "$STATE_CAND_PIN_WS" "$cand_ws"
	fi
	# (If link-window below FAILS -> preview_fallback/snapshot: the pin was manual + a size-no-op resize
	#  (cand_h == the candidate's own height); STATE_CAND_PIN_* is set, so the next nav / teardown restores
	#  it. Benign + trace-free. Do not over-engineer.)

	# Link S's window into the current session. (unchanged)
	if ! tmux link-window -s "$src_id" -t "$current_session:" 2>/dev/null; then
		preview_fallback "$S"
		return $?
	fi
	# ... (select-window + GUARD 3 + set_state LINKED_ID/PREVIEW_WIN_ID unchanged) ...

# === Site C: scripts/restore.sh — restore_main local decl (APPEND 2 locals) ===
# P3.M2.T1.S2 (parallel) may have ALREADY added `saved_geom cur_geom h_orig`. APPEND pin_sess pin_ws to
# WHATEVER the current decl is. Example final form:
	local linked_id orig_window current_session orig_session mode r_status r_kt r_renumber r_hook hk_line hk_idx hk_cmd r_cr_hook cr_line cr_idx cr_cmd orig_layout lp_rfit_ws pin_sess pin_ws
# (if P3.M2.T1.S2 landed: ... lp_rfit_ws saved_geom cur_geom h_orig pin_sess pin_ws)

# === Site C: scripts/restore.sh — TOP of STEP 1 (insert BEFORE the linked_id read) ===
	# --- STEP 1 (PRD §9 restore step 1): unlink the preview window + restore any candidate pinned at
	#     link time (P3.M2.T2.S1, PRD §23 Invariant C) ---
	# P3.M2.T2.S1: restore a pinned candidate's window-size BEFORE the driver unlink. STATE_CAND_PIN_SESSION
	# holds the last-pinned candidate session (set by preview.sh at link time; mid-browse-restored by
	# preview.sh's two unlink paths). If it is still set here (the last preview was a pinned cross-session
	# candidate and the user did not navigate away), replay its prior window-size (or UNSET the override
	# when the prior was empty/inherited) so NO trace of our manual pin remains. This is the inline copy of
	# preview.sh's _preview_restore_cand_pin (restore.sh is its OWN process under run-shell — cannot source
	# it). Runs for BOTH keep and cancel (STEP 1 is unconditional): on keep the confirmed session may BE the
	# pinned candidate -> restoring window-size lets the now-attached client re-fit it (normal attach
	# behavior; leaving it manual would be the ARM E3 harm). Detached-only pin => safe to restore. Placed
	# BEFORE the H2 session-match guard so it runs even if the driver unlink is skipped (the restore targets
	# the CANDIDATE session, always safe). clear_all_state (STEP 6) clears STATE_CAND_PIN_* AFTER, so the
	# reads succeed here. BARE session name for set-option (gotcha #1; mirror STEP 4's driver ws restore).
	pin_sess="$(get_state "$STATE_CAND_PIN_SESSION" "")"
	if [ -n "$pin_sess" ]; then
		pin_ws="$(get_state "$STATE_CAND_PIN_WS" "")"
		if [ -n "$pin_ws" ]; then
			tmux set-option -t "$pin_sess" window-size "$pin_ws" 2>/dev/null || true
		else
			tmux set-option -u -t "$pin_sess" window-size 2>/dev/null || true
		fi
	fi
	# (then the EXISTING STEP 1 body: linked_id read + H2 session-match guard + unlink-window, unchanged)
	linked_id="$(get_state "$STATE_LINKED_ID" "")"
	... (existing STEP 1 unchanged) ...

# === Site D: README.md — Known limitations (replace the 2nd bullet) ===
# BEFORE:
#   - **Detached candidates still resize once at link time.** When you navigate to a detached candidate,
#     tmux links its window into the driver and resizes it once to the driver's size. ... `clip` does not
#     change this. Set `@livepicker-preview-mode` `snapshot` to preview with `capture-pane` and never link
#     (and never resize) the candidate.
# AFTER:
- **Detached candidates are pinned (no resize) in `clip` mode.** When you navigate to a detached
  candidate, the picker freezes that candidate's `window-size` and window height at link time (and
  restores them when you leave), so its panes are not reflowed by the live link and its own session keeps
  its original geometry after the picker exits. Candidates that carry their own attached client cannot be
  pinned this way (freezing `window-size` would revert that client's view to the window's creation size),
  so for strict pane-immutability across client-bearing sessions set `@livepicker-preview-mode` `snapshot`
  (preview with `capture-pane` and never link a live window). In `@livepicker-preview-fit` `reflow` mode
  candidates still resize at link time (reflow is the legacy escape hatch); use `clip` (the default) or
  `snapshot` to avoid it.

# GOTCHA (Site B gate order): the pin block MUST come AFTER both the idempotent pre-link check (~196) and
#   the duplicate guard (~206) — those return 0 for a SAME-window re-preview (no restore/re-pin wanted).
#   It goes in the actual-replace path only. The self-session path gets ONLY the _preview_restore_cand_pin
#   call (no pin — self is never a cross-session candidate).
# GOTCHA (Site B cand_sess): check_session is computed before the self-guard and == the candidate session
#   in both modes. Reuse it; do not re-derive w_sess (only set in the window-mode src_id branch).
# GOTCHA (Site C parallel): do NOT add saved_geom/cur_geom/h_orig or touch STEP 5 — P3.M2.T1.S2 owns those.
```

### Integration Points

```yaml
STATE CONTRACT (PRD §9 + §23):
  - add 2 RUNTIME keys: STATE_CAND_PIN_SESSION/WS (written preview.sh link, read preview.sh unlink paths +
        restore.sh STEP 1). NOT saved-state; NOT in the ORIG_* block; auto-cleared via _STATE_RUNTIME_KEYS.
  - clear_all_state (STEP 6) clears them via the runtime list; the reads in restore.sh STEP 1 + preview.sh
        precede the clear.

§22 CLIP (consumed, read-only):
  - livepicker.sh T3 pins the DRIVER window-size manual + height at activate (gated on opt_preview_fit==clip).
        So at preview.sh link time the driver is ALREADY manual -> candidate manual -> both manual -> ARM B2
        holds. This task reuses the SAME clip gate for the candidate pin (in reflow the driver is not manual
        -> the candidate pin cannot hold -> skip). restore.sh STEP 4 already restores the DRIVER window-size;
        this task adds the symmetric CANDIDATE window-size restore in STEP 1.

PARALLEL SIBLING (P3.M2.T1.S2 — drift-gated restore, being implemented):
  - edits restore.sh STEP 5 + restore_main locals (saved_geom cur_geom h_orig). This task edits STEP 1 +
        restore_main locals (pin_sess pin_ws). DIFFERENT steps, DIFFERENT local names -> no conflict.
        APPEND to the local decl; do not duplicate or reorder P3.M2.T1.S2's names.

GATE (P3.M1.T1.S1 — COMPLETE):
  - pane_immutability_verification.md = CONDITIONAL YES. This task implements §4 recipes verbatim (with the
        gotcha-#1 command-form correction + the clip gate). The assert shape (§4) is consumed by P3.M3.T1.

OUT OF SCOPE (do NOT implement here):
  - The pane-geometry snapshot capture (P3.M2.T1.S1 — COMPLETE; this task does not read it).
  - The drift-gated restore in restore.sh STEP 5 (P3.M2.T1.S2 — parallel; do not touch STEP 5).
  - The formal §23 test suite (P3.M3.T1 — separate). This task validates via shellcheck + a Level 2
        isolated-socket probe + the existing suite + non-pollution.
  - Editing livepicker.sh, options.sh, utils.sh, input-handler.sh, any test_*.sh, PRD.md, CHANGELOG.md,
        any tasks.json. (README.md IS in scope — Site D.)
```

## Validation Loop

### Level 1: Syntax & Style (Immediate Feedback)

```bash
cd /home/dustin/.config/tmux/plugins/tmux-livepicker
# shellcheck the THREE modified scripts (all already pass; the edits must keep them clean).
shellcheck scripts/state.sh scripts/preview.sh scripts/restore.sh
# Expected: zero NEW errors. The new STATE_CAND_PIN_* readonly consts are covered by state.sh's file-wide
# SC2034 disable; preview.sh/restore.sh already disable SC2153 (readonly STATE_*/ORIG_* from state.sh).
# The list-clients/set-option/display-message calls are plain tmux invocations (not flagged). No new directive.
bash -n scripts/state.sh && bash -n scripts/preview.sh && bash -n scripts/restore.sh   # syntax sanity
# Expected: no syntax errors.
# Confirm the new keys + the pin/restore wiring:
grep -n 'STATE_CAND_PIN_SESSION\|STATE_CAND_PIN_WS' scripts/state.sh          # 2 readonly + 2 in _STATE_RUNTIME_KEYS
grep -n 'STATE_CAND_PIN_SESSION\|STATE_CAND_PIN_WS' scripts/preview.sh         # the helper + set_state in the pin block
grep -n 'STATE_CAND_PIN_SESSION\|STATE_CAND_PIN_WS' scripts/restore.sh         # the STEP 1 restore read
grep -n '_preview_restore_cand_pin' scripts/preview.sh                         # def + 2 call sites (self + replace)
grep -n 'window-size manual' scripts/preview.sh                                # the candidate pin (BARE session, NO '=')
grep -n 'list-clients -t "=' scripts/preview.sh                                # the detached gate
grep -n 'pin_sess pin_ws' scripts/restore.sh                                   # the 2 new locals
# Expected: all grep hits present; the set-option -t uses a BARE var (no "=$"); list-clients uses "=$".
```

### Level 2: Isolated-socket ARM-B2 reproduction via the REAL plugin (the core behavior)

The formal §23 suite is **P3.M3.T1** (separate). This task verifies the conditional pin directly against
the REAL plugin (the §22 driver clip MUST be in place — it is COMPLETE). Drives `preview.sh` directly
(the same entry the renderer/input uses) with the candidate session name:

```bash
cd /home/dustin/.config/tmux/plugins/tmux-livepicker
source tests/setup_socket.sh
setup_socket "lp-candpin-$$"; attach_test_client
# Create a DETACHED candidate "alpha" with a 3-pane window (the ARM B2 fixture).
tmux new-session -d -s alpha -x 120 -y 40
tmux split-window -h -t alpha
tmux split-window -v -t alpha
# Create a second detached candidate "beta" (for the replace-path restore test).
tmux new-session -d -s beta -x 120 -y 40
alpha_w="$(tmux list-windows -t alpha -F '#{window_id}' -f '#{window_active}')"
beta_w="$(tmux list-windows -t beta -F '#{window_id}' -f '#{window_active}')"

# === ARM 1: PIN holds byte-identical (the fix). clip mode (default) + detached alpha. ===
geom_before="$(tmux display-message -p -t "$alpha_w" '#{window_layout}')"
panes_before="$(tmux list-panes -t "$alpha_w" -F '#{pane_id}:#{pane_left},#{pane_top},#{pane_width},#{pane_height}' | sort)"
ws_before="$(tmux show-options -t alpha -v window-size 2>/dev/null || true)"   # prior ws (likely "" = inherits global)
"$LIVEPICKER_SCRIPTS/livepicker.sh" >/dev/null            # activate: §22 driver clip (driver manual); sets ORIG_*
"$LIVEPICKER_SCRIPTS/preview.sh" alpha >/dev/null         # preview alpha: PIN (clip + detached) -> manual + resize -y H
geom_after="$(tmux display-message -p -t "$alpha_w" '#{window_layout}')"
panes_after="$(tmux list-panes -t "$alpha_w" -F '#{pane_id}:#{pane_left},#{pane_top},#{pane_width},#{pane_height}' | sort)"
[ "$geom_after" = "$geom_before" ] && echo "ARM1 layout: BYTE-IDENTICAL (pin held) OK" || echo "ARM1 layout CHANGED — FAIL"
[ "$panes_after" = "$panes_before" ] && echo "ARM1 panes: BYTE-IDENTICAL OK" || echo "ARM1 panes CHANGED — FAIL"
[ "$(tmux show-options -t alpha -v window-size 2>/dev/null)" = "manual" ] && echo "ARM1 alpha window-size=manual (pinned) OK" \
  || echo "ARM1 alpha NOT manual — FAIL (pin gate did not fire: check clip mode / list-clients)"
[ "$(tmux show-option -gqv @livepicker-cand-pin-session)" = "alpha" ] && echo "ARM1 pin-session tracked OK" \
  || echo "ARM1 pin-session NOT tracked — FAIL"

# === ARM 2: RESTORE on replace (preview beta -> alpha restored). ===
"$LIVEPICKER_SCRIPTS/preview.sh" beta >/dev/null          # preview beta: restore alpha (replace path), pin beta
ws_alpha_after="$(tmux show-options -t alpha -v window-size 2>/dev/null || true)"
[ "$ws_alpha_after" = "$ws_before" ] && echo "ARM2 alpha window-size RESTORED to prior OK" \
  || echo "ARM2 alpha window-size NOT restored (got '$ws_alpha_after' vs prior '$ws_before') — FAIL"
[ "$(tmux show-option -gqv @livepicker-cand-pin-session)" = "beta" ] && echo "ARM2 pin-session now beta OK" \
  || echo "ARM2 pin-session NOT beta — FAIL"

# === ARM 3: RESTORE on teardown (cancel -> restore.sh STEP 1). ===
"$LIVEPICKER_SCRIPTS/input-handler.sh" cancel >/dev/null   # teardown: restore.sh STEP 1 restores beta
ws_beta_after="$(tmux show-options -t beta -v window-size 2>/dev/null || true)"
[ "$ws_beta_after" = "" ] && echo "ARM3 beta window-size UNSET (no trace) OK" \
  || echo "ARM3 beta window-size residue '$ws_beta_after' — FAIL"
[ -z "$(tmux show-option -gqv @livepicker-cand-pin-session 2>/dev/null)" ] && echo "ARM3 pin keys cleared OK" \
  || echo "ARM3 pin keys residue — FAIL (clear_all_state / _STATE_RUNTIME_KEYS)"

# === ARM 4 (NEGATIVE): client-bearing candidate is NOT pinned. ===
setup_socket "lp-candpin-neg-$$"; attach_test_client
tmux new-session -d -s gamma -x 120 -y 40; tmux split-window -h -t gamma
# attach a SECOND client to gamma (its OWN client) — the ARM E3/E4 fixture.
script -qec "tmux -L \"$TEST_SOCKET\" attach -t gamma" /dev/null >/dev/null 2>&1 & GC=$!; sleep 0.5
gamma_w="$(tmux list-windows -t gamma -F '#{window_id}' -f '#{window_active}')"
g_before="$(tmux display-message -p -t "$gamma_w" '#{window_layout}')"
"$LIVEPICKER_SCRIPTS/livepicker.sh" >/dev/null
"$LIVEPICKER_SCRIPTS/preview.sh" gamma >/dev/null         # gamma HAS a client -> pin SKIPPED
[ "$(tmux show-options -t gamma -v window-size 2>/dev/null)" != "manual" ] && echo "ARM4 gamma NOT pinned (client-bearing skip) OK" \
  || echo "ARM4 gamma WAS pinned — FAIL (list-clients gate missing)"
g_after="$(tmux display-message -p -t "$gamma_w" '#{window_layout}')"
[ "$g_after" = "$g_before" ] && echo "ARM4 gamma byte-identical (bare link safe) OK" || echo "ARM4 gamma changed — investigate"
[ -z "$(tmux show-option -gqv @livepicker-cand-pin-session 2>/dev/null)" ] && echo "ARM4 no pin tracked (skip) OK" \
  || echo "ARM4 pin tracked despite skip — FAIL"
"$LIVEPICKER_SCRIPTS/input-handler.sh" cancel >/dev/null
kill "$GC" 2>/dev/null; wait "$GC" 2>/dev/null

teardown_socket
unset -f setup_socket teardown_socket attach_test_client
# Expected: ARM1 pin holds byte-identical + alpha manual + tracked; ARM2 alpha restored + beta tracked;
#   ARM3 beta unset + keys cleared; ARM4 gamma NOT pinned (client-bearing) + bare link byte-identical.
# If ARM1 layout CHANGED: the pin did not hold — confirm clip mode is on (default), the driver clip fired at
#   activate (livepicker.sh T3), AND alpha is detached (list-clients empty). Re-check the gate conditions.
# If ARM1 alpha NOT manual: the list-clients gate or the clip gate mis-fired. Print opt_preview_fit + the
#   list-clients output for alpha. Confirm set-option uses the BARE name (no '=' -> rc=1 silent).
# If ARM2/ARM3 NOT restored: _preview_restore_cand_pin / restore.sh STEP 1 logic — confirm pin_ws replay
#   (non-empty) vs set-option -u (empty), and the BARE session name. Check the keys are in _STATE_RUNTIME_KEYS.
# If ARM4 gamma WAS pinned: the `[ -z "$(list-clients -t "=$cand_sess")" ]` gate is missing/inverted.
```

### Level 3: Regression — existing suite stays green

```bash
cd /home/dustin/.config/tmux/plugins/tmux-livepicker
bash tests/run.sh
# Expected: exit 0, all PASS. KEY suites to eyeball:
#   - test_preview_clip.sh: the §22 driver clip freeze/restore still works (this task adds the candidate pin
#     alongside it; the candidate pin targets the CANDIDATE window, not the driver -> driver assertions hold).
#   - test_window_flip.sh: window-cursor/flip still works; flipping a candidate's windows does not resize the
#     non-current one (verification ARM D — distinct @id windows are independent under per-window pinning).
#   - test_restore.sh: byte-exact DRIVER-option restore (status/key-table/window-size of ORIG_SESSION) is
#     UNCHANGED — the candidate pin touches CANDIDATE session window-size, restored byte-exact (save+replay /
#     unset). If a candidate-window-size assertion shifts, it is because we now correctly LEAVE NO TRACE.
#   - test_pollution.sh: browsing fires no client-session-changed (unchanged).
# If a candidate-session window-size assertion FAILS: the pin saved/restored the wrong value — confirm
#   cand_ws capture (show-options -t BARE) and the restore replay-vs-unset mirror STEP 4's driver logic.
#   Do NOT weaken asserts; fix the root cause.
```

### Level 4: Non-pollution (the core invariant, PRD §15)

```bash
cd /home/dustin/.config/tmux/plugins/tmux-livepicker
BEFORE="$(/usr/bin/tmux list-sessions -F '#{session_name}' 2>/dev/null | sort)"
bash tests/run.sh >/dev/null 2>&1
AFTER="$(/usr/bin/tmux list-sessions -F '#{session_name}' 2>/dev/null | sort)"
[ "$BEFORE" = "$AFTER" ] && echo "REAL SERVER UNTOUCHED" || echo "POLLUTION — abort"
# Expected: REAL SERVER UNTOUCHED. The pin/restore are isolated-socket candidate-session options only.
```

### Level 5: Creative & Domain-Specific Validation

```bash
cd /home/dustin/.config/tmux/plugins/tmux-livepicker
# Confirm the pin gate has ALL THREE conditions (clip + non-empty cand_sess + detached list-clients):
grep -q 'opt_preview_fit" = "clip"' scripts/preview.sh && grep -q 'list-clients -t "=$cand_sess"' scripts/preview.sh \
  && echo "pin gate = clip + detached OK" || echo "FAIL: pin gate incomplete"
# Confirm set-option/show-options use the BARE session (NO "=$") in the pin block:
sed -n '/PIN THE NEW CANDIDATE/,/set_state "$STATE_CAND_PIN_SESSION"/p' scripts/preview.sh | grep -E 'set-option|show-options' \
  | grep -v '="\$cand_sess"' >/dev/null && echo "BARE session for set-option/show-options OK" \
  || echo "check: pin block set-option/show-options must use BARE \$cand_sess (no '=')"
# Confirm the candidate pin uses resize-window -y H (the sanctioned freeze), NOT resize-pane/select-layout:
! grep -qE 'resize-pane|select-layout|swap-|move-|break-pane|join-pane|pipe-pane' scripts/preview.sh \
  && echo "no §23-forbidden pane ops in preview.sh OK" || echo "FAIL: forbidden pane op present"
# Confirm STATE_CAND_PIN_* are in _STATE_RUNTIME_KEYS (auto-clear) and NOT in the ORIG_* block:
grep -q 'STATE_CAND_PIN_SESSION\|STATE_CAND_PIN_WS' <<<"$(sed -n '/_STATE_RUNTIME_KEYS=/p' scripts/state.sh)" \
  && echo "pin keys in _STATE_RUNTIME_KEYS (auto-clear) OK" || echo "FAIL: pin keys must be in _STATE_RUNTIME_KEYS"
# Confirm restore.sh STEP 1 restore is BEFORE the linked_id read + uses the BARE session:
awk '/restore a pinned candidate/{found=1} found && /linked_id="\$\(get_state/{print "STEP1 pin-restore precedes linked_id read OK"; exit}' scripts/restore.sh
# Expected: gate complete; BARE session; no forbidden ops; keys auto-clear; STEP 1 ordering correct.
```

## Final Validation Checklist

### Technical Validation
- [ ] Level 1: `shellcheck scripts/state.sh scripts/preview.sh scripts/restore.sh` clean (no new errors); `bash -n` passes; the grep checks confirm keys + helper + pin/restore + BARE session + locals.
- [ ] Level 2: ARM1 pin holds byte-identical (layout + panes) + alpha window-size=manual + tracked; ARM2 alpha restored on replace + beta tracked; ARM3 beta unset on teardown + keys cleared; ARM4 client-bearing gamma NOT pinned + bare link byte-identical.
- [ ] Level 3: `bash tests/run.sh` exit 0 (test_preview_clip / test_window_flip / test_restore / test_pollution green).
- [ ] Level 4: real tmux server byte-identical before/after (PRD §15).
- [ ] Level 5: pin gate = clip + detached; BARE session for set-option/show-options; no §23-forbidden pane ops; pin keys in _STATE_RUNTIME_KEYS; restore.sh STEP 1 pin-restore precedes linked_id read.

### Feature Validation
- [ ] state.sh: STATE_CAND_PIN_SESSION/WS are readonly RUNTIME keys (after STATE_PREVIEW_WIN_ID), both in _STATE_RUNTIME_KEYS, NOT in the ORIG_* block.
- [ ] preview.sh: pin block before link-window, gated `[ clip ] && [ -n cand_sess ] && [ -z list-clients ]`, BARE session for set-option/show-options, @src_id for display-message/resize-window; records session + prior ws.
- [ ] preview.sh: _preview_restore_cand_pin helper called in BOTH unlink paths (self-session + replace) before the unlink/link.
- [ ] restore.sh: candidate-pin restore at the TOP of STEP 1 (inline), before the linked_id read / H2 guard; runs for keep + cancel; prior ws replayed or unset.
- [ ] README.md: "Detached candidates..." bullet reflects the conditional-YES reality (pinned for detached+clip; client-bearing ⇒ snapshot; reflow still resizes).
- [ ] A detached candidate's pane geometry is byte-identical across pin→link→browse→flip→cancel (ARM B2); a client-bearing candidate is NOT pinned (ARM E3/E4).

### Code Quality Validation
- [ ] Mirrors the §22 driver clip pattern (manual + resize-window -y H -t "$win"; BARE session for set-option; `2>/dev/null || true`).
- [ ] Mirrors restore.sh STEP 4's driver window-size restore (unset-vs-replay) for the candidate restore.
- [ ] 2/3 new locals appended to the existing single `local` statements (house style; no inline `local`).
- [ ] The helper is defined before preview_main; restore.sh inlines an identical copy (separate process).
- [ ] TABS for indent; no `set -e` added; SC2153/SC2034 already cover the new consts; no new shellcheck directive.

### Documentation & Deployment
- [ ] The pin block + helper + STEP 1 comments cite PRD §23 Prevention-regime bullet 2 + the gate (pane_immutability_verification.md §1/§4/§7) + the conditional (detached only) + the clip gate + the BARE-session gotcha + the §23 sanctioned-pin reconciliation.
- [ ] README.md Known limitations updated (Site D).
- [ ] PRD.md, CHANGELOG.md, livepicker.sh, options.sh, utils.sh, input-handler.sh, restore.sh STEP 5, any test_*.sh, and any tasks.json UNMODIFIED. ONLY state.sh + preview.sh + restore.sh + README.md are edited.

---

## Anti-Patterns to Avoid

- ❌ Don't use `set-option -t "=$S"` / `show-options -t "=$S"` (the work item's literal form). set-option/show-options REJECT the `=` prefix (verification gotcha #1 — rc=1 "no such window"). Use the BARE session name. (`=` IS valid for list-clients/list-windows/display-message/link-window/select-window.)
- ❌ Don't pin a client-bearing candidate. `window-size manual` REVERTS its client view to the creation size (ARM E3 — harmful). GATE on `[ -z "$(tmux list-clients -t "=$cand_sess" 2>/dev/null)" ]` and SKIP. This is the single most important correctness rule.
- ❌ Don't omit the `opt_preview_fit == clip` gate. In reflow mode the driver is not manual, so its latest client drags the shared window and the candidate pin cannot hold — pinning there is pointless churn. (The RESTORE needs no clip gate — it is gated on STATE_CAND_PIN_SESSION non-empty, a natural no-op in reflow.)
- ❌ Don't `set-option -g window-size` (global manual disconnects the window from the client → creation size). Per-session `-t` only (same as the §22 driver clip, gotcha #6).
- ❌ Don't prepend `@` to src_id in resize-window/display-message. src_id already holds @N; `-t "@$src_id"` → `@@N` (rc=1). Use `-t "$src_id"`.
- ❌ Don't put STATE_CAND_PIN_* in the ORIG_* block or rely on the `@livepicker-orig-` grep. They are RUNTIME keys (written mid-browse); they do NOT match that grep and MUST be in _STATE_RUNTIME_KEYS or they LEAK.
- ❌ Don't restore the candidate only in restore.sh. The contract (§3b) requires it in preview.sh's unlink paths too (self-session + replace). Use the helper in both; the self-session path closes the dangling-pin-during-self-browse gap.
- ❌ Don't move the pin block into the idempotent pre-link check or the duplicate guard. Those return 0 for a SAME-window re-preview (no restore/re-pin wanted). The pin + restore-previous go ONLY in the actual-replace path (after both guards).
- ❌ Don't be paralyzed by §23's "resize-window forbidden during preview" list. That list is PREVIEW-scoped; §23 Prevention-regime bullet 2 EXPLICITLY prescribes the candidate pin ("freeze each candidate at link time: set window-size manual and pin its window to its captured geometry"). `manual` + `resize-window -y H_cand` (setting the window to its OWN height = a freeze) is the sanctioned candidate mutation alongside the §22 driver pin. (restore-time resize is the OTHER sanctioned exception — P3.M2.T1.S2.)
- ❌ Don't capture cand_h from a live `#{window_height}` expecting the "usable" size. For a DETACHED candidate it reads the CREATION size — that is CORRECT here (we pin at the candidate's own natural size; ARM B2 pinned at 40). The gate's gotcha #5 is about ASSERT measuring, not pinning.
- ❌ Don't touch restore.sh STEP 5 or add saved_geom/cur_geom/h_orig — P3.M2.T1.S2 (parallel) owns those. APPEND pin_sess pin_ws to the local decl; edit STEP 1 only.
- ❌ Don't edit livepicker.sh, options.sh, utils.sh, input-handler.sh, any test_*.sh, PRD.md, or CHANGELOG.md. The §22 driver clip is COMPLETE; the drift-gated restore is P3.M2.T1.S2; the §23 suite is P3.M3.T1; changeset docs are P4. THIS TASK edits state.sh + preview.sh + restore.sh + README.md ONLY.
- ❌ Don't add `set -e` or drop the `2>/dev/null || true` guards. House style is `set -u` only; set-option/resize-window/list-clients can legitimately rc=1 (vanished session/window/race). A transient failure must NOT abort a half-linked preview or a half-restored teardown.

---

## Confidence Score: 9/10

This task implements a verified, prescribed recipe (the gate P3.M1.T1.S1 returned CONDITIONAL YES with verbatim §4 recipes; ARM B2 proved the pin holds byte-identically for detached candidates, deterministically). The three edit sites have exact anchors: state.sh runtime block (after STATE_PREVIEW_WIN_ID) + _STATE_RUNTIME_KEYS; preview.sh local decl (~117) + self-session unlink block (~150-156) + replace path (re-read ~216, unlink ~221, link ~230); restore.sh local decl (line 57) + STEP 1 top (~57). The `manual + resize-window -y H` pattern is already proven in the COMPLETE §22 driver clip (livepicker.sh ~329-333), and the candidate pin mirrors it exactly; the unset-vs-replay restore mirrors restore.sh STEP 4's driver window-size restore exactly; the helper idiom mirrors the self-path's `tmux_unset_opt "$STATE_LINKED_ID"`. The two corrections to the work-item command forms (BARE session for set-option; clip-mode gate) are load-bearing and documented with the verification gotcha references. The parallel-sibling conflict surface (P3.M2.T1.S2) is nil — different restore.sh steps (STEP 1 vs STEP 5) and disjoint local names (append, do not reorder). The residual 1/10 is: (a) the Level 2 ARM1 probe relies on the detached candidate actually staying detached through the link (the probe prints list-clients so a leak is caught); (b) the client-bearing NEGATIVE case (ARM4) depends on the harness `script`-pty attach reporting as a client of gamma (the probe asserts both the skip AND byte-identical bare link so a mis-detection is visible); (c) confirming the full existing suite stays green when the candidate pin now fires during test browses (Level 3 — the pin saves+restores byte-exact, so driver-option asserts are unaffected; a candidate-window-size assert would now correctly pass). The implementer's job is to add 2 keys + 1 helper + 3 pin/restore blocks in exact spots mirroring proven patterns — not to discover tmux behavior or design the pin logic.
