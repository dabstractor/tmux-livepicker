name: "P3.M1.T2.S1 — Add opt_preview_fit + ORIG_WINDOW_SIZE; freeze driver in activate; restore in restore.sh"
description: Implementation work item (PRD §22 clip). Add the `@livepicker-preview-fit` option (default `clip`) + the `ORIG_WINDOW_SIZE` saved-state key; in `scripts/livepicker.sh` activate T3, when clip mode, save the driver's window-size then FREEZE it (`set-option -t manual` + the load-bearing `resize-window -y <pre-grow-height>` pin) BEFORE the status grow; in `scripts/restore.sh` STEP 4, restore (byte-exact) the driver's window-size AFTER the status shrink. `reflow` skips both. Plus the README config row + the limitation-note reconciliation. GATED by P3.M1.T1.S1's `clip_verification.md` (which corrected the recipe: manual ALONE fails on 3.6b; the resize-window pin is load-bearing).

---

## Goal

**Feature Goal**: Kill the activation status-grow reflow jank (PRD §22): when the picker grows the status line 1→2, the driver's active (self/preview) window must NOT shrink/reflow its panes. Achieve this by freezing the driver session's window size — in clip mode (the new default) — before the status grows, and restoring it exactly on exit. Provide `@livepicker-preview-fit` (`clip` default / `reflow` legacy escape hatch) so a user can opt back into the old reflow behavior if clip misbehaves on their tmux/terminal.

**Deliverable**: Four code edits + one doc edit:
1. `scripts/options.sh` — new `opt_preview_fit()` accessor (default `clip`).
2. `scripts/state.sh` — new `readonly ORIG_WINDOW_SIZE="@livepicker-orig-window-size"` in the `ORIG_*` block (auto-cleared).
3. `scripts/livepicker.sh` `activate_main` T3 — a clip-gated freeze block inserted BEFORE the status-grow `case` (save window-size → `manual` → `resize-window -y <pre-grow-height>` pin).
4. `scripts/restore.sh` `restore_main` STEP 4 — a clip-gated restore block inserted AFTER the status-shrink (restore-or-unset the driver's window-size, byte-exact).
5. `README.md` — `@livepicker-preview-fit` row in the Configuration table + the "Detached candidate resize" limitation note reconciled (status-grow reflow is now fixed by clip; link-time resize persists).

**Success Definition**: With `@livepicker-preview-fit` at its default `clip`, driving the real `livepicker.sh` activate (attached client) leaves the driver's active-window `window_layout` BYTE-IDENTICAL across the status 1→2 grow (no reflow); on cancel, the driver's session-scoped `window-size` is byte-identical to pre-activate (unset stays unset) and the global `window-size` is never touched. With `@livepicker-preview-fit reflow`, neither activate nor restore touches `window-size` at all (the picker behaves exactly as before §22). `bash tests/run.sh` stays green (existing byte-exact-restore + pollution suites unbroken).

## User Persona

**Target User**: The tmux user running the picker who is bothered by the one-row pane reflow that fires every time the status bar grows on activation (and again on each preview re-link of a shrinking window).

**Use Case**: Activate the picker; the status bar grows to two lines; the preview panes stay rock-steady (their bottom row is clipped, not reflowed). On cancel the layout, window-size, and everything else snap back to exactly how they were.

**Pain Points Addressed**: The visible "jank" — panes shrinking/re-wrapping/re-rendering the instant the extra status line appears. This is the single most noticeable activation artifact.

## Why

- PRD §22 + §16 ("Preview clip feasibility, load-bearing") make eliminating the status-grow reflow a first-class goal, explicitly gated on empirical confirmation on 3.6b. P3.M1.T1.S1 (`clip_verification.md`, produced in parallel) CONFIRMS clip is feasible AND CORRECTS the recipe: `window-size manual` ALONE does NOT pin the height on 3.6b (condition B: reflow 23→22); the `resize-window -y <pre-grow-height>` pin is the load-bearing step (conditions C/F: byte-identical layout). This task implements that verified recipe.
- The freeze is the §22 "clip instead of reflow" fix. `reflow` is kept as the documented escape hatch (PRD §22 "Control") so a user on a tmux/terminal where clip misbehaves can fall back to the pre-§22 behavior without a code change.
- Integrates with the existing save/restore contract (PRD §9): `window-size` joins the `@livepicker-orig-*` saved-state set, auto-cleared by `clear_all_state` (which already greps `@livepicker-orig-`), and restored in STEP 4 after the status shrink.

## What

A clip-gated window-size freeze/restore wired into the existing activate T3 status-grow block and restore STEP 4 status-restore block, plus the option and state-key seams. User-visible: with the default `clip`, the status bar grows and the preview does NOT reflow; `@livepicker-preview-fit reflow` restores the legacy reflow. No new user-visible commands or keys.

### Success Criteria

- [ ] `opt_preview_fit()` exists in `options.sh`, returns `clip` by default, and `reflow` when the user sets `@livepicker-preview-fit reflow`.
- [ ] `ORIG_WINDOW_SIZE` is a `readonly` constant in `state.sh`'s `ORIG_*` block and is auto-cleared by `clear_all_state` (it matches the `@livepicker-orig-` grep).
- [ ] **clip mode (default):** activate, with an attached client, leaves the driver's active-window `window_layout` byte-identical across the status 1→2 grow (the freeze: `manual` + `resize-window -y H0` BEFORE the grow).
- [ ] **clip mode restore:** cancel leaves the driver's session-scoped `window-size` byte-identical to pre-activate (unset→unset; had-override→that override) and the GLOBAL `window-size` untouched (PRD §15 zero-trace).
- [ ] **reflow mode:** activate AND restore touch `window-size` not at all (the `if [ "$(opt_preview_fit)" = "clip" ]` gate skips both); the status grow reflows the preview one row (legacy behavior).
- [ ] `bash tests/run.sh` is green (existing byte-exact-restore / pollution / functional suites unbroken — `window-size` global never touched; session-scoped value round-trips).
- [ ] README Configuration table has the `@livepicker-preview-fit` row; the "Detached candidate resize" limitation distinguishes status-grow reflow (now fixed by clip) from link-time resize (persists; use `snapshot`).

## All Needed Context

### Context Completeness Check

_"If someone knew nothing about this codebase, would they have everything needed to implement this successfully?"_ — Yes. This PRP pins the verified freeze recipe (with the load-bearing correction the gate discovered), the exact insertion points (verbatim surrounding code), the byte-exact restore decision, the gotchas that tripped the probe, the option/state conventions to mirror, the README rows to edit, and the executable validation. No guessing about tmux behavior is required — every command in the recipe was probed on 3.6b by P3.M1.T1.S1.

### Documentation & References

```yaml
# MUST READ — load into the context window before writing anything.

- file: plan/003_77ef311abf10/P3M1T1S1/research/clip_probe_findings.md
  why: THE empirical proof + the corrected recipe. Condition B (manual alone → reflow
        23→22) vs C/F (manual+resize-window -y H0 → byte-identical). §4 is the exact
        freeze/restore command sequence. §0 are the gotchas that broke the first probes.
  critical: "THE FREEZE IS `manual` THEN `resize-window -y $H0`, in that order, BEFORE the
        status grow. manual ALONE FAILS. This CORRECTS the item description's 'manual only'
        and PRD §22's 'Mechanism (intended)' text (both predate this probe)."

- file: plan/003_77ef311abf10/P3M1T2S1/research/clip_freeze_recipe_findings.md
  why: THIS task's own synthesis — the central reconciliation (manual-only fails; pin is
        load-bearing), the byte-exact window-size restore decision, the exact insertion
        points, and the gotchas condensed. Read this FIRST; it is the TL;DR of everything below.
  section: "§1 the reconciliation; §4 byte-exact restore; §5 insertion points; §6 gotchas"

- file: plan/003_77ef311abf10/architecture/clip_verification.md
  why: P3.M1.T1.S1's decision doc (THE GATE). Its §3 names the exact freeze/restore recipe
        P3.M1.T2 implements and states `@livepicker-preview-fit` default = `clip`. Treat it
        as the contract for the recipe; do NOT re-derive from PRD §22.
  note: "Created by P3.M1.T1.S1 (running in parallel). If it is not yet present, the recipe
        is fully specified in clip_probe_findings.md §4 + this task's research/clip_freeze_recipe_findings.md."

- file: scripts/options.sh            # the opt_<name>() accessor pattern to mirror (1 line each)
  why: opt_preview_fit() is a 1-liner in the EXACT style of opt_preview_mode()/opt_preview_defer().
        get_opt "@livepicker-<suffix>" "<default>"; default "clip". Placement: next to the other
        @livepicker-preview-* options (after opt_preview_defer).
  pattern: "opt_preview_defer() { get_opt \"@livepicker-preview-defer\" \"on\"; }  # bool on|off"

- file: scripts/state.sh              # the ORIG_* block + clear_all_state
  why: add `readonly ORIG_WINDOW_SIZE=\"@livepicker-orig-window-size\"` to the ORIG_* block
        (alongside ORIG_RENUMBER). NO edit to _STATE_RUNTIME_KEYS and NO edit to clear_all_state
        needed — clear_all_state already unsets EVERY @livepicker-orig-* via its
        `grep '@livepicker-orig-'` heredoc loop, so ORIG_WINDOW_SIZE is auto-cleared (§9 step 6).
  pattern: "readonly ORIG_RENUMBER=\"@livepicker-orig-renumber-windows\"  # mirror this line"
  gotcha: "ORIG_WINDOW_SIZE is SAVED-STATE (written activate, read restore), NOT a runtime key.
        Do NOT add it to _STATE_RUNTIME_KEYS (that list is the explicit picker-internal set)."

- file: scripts/livepicker.sh         # activate_main, the T3 block (~the status-grow case)
  why: THE activate insertion point. The freeze slots in BETWEEN (b) install-renderer and
        (c) the status-grow `case "$orig_status"`. GATED on opt_preview_fit==clip. At this
        point ORIG_SESSION+ORIG_WINDOW are saved (STEP 2) and the active window is still
        ORIG_WINDOW (T2 list-build switches nothing; first preview is T5, AFTER the grow).
  pattern: "lp_client_format '#{window_id}' -> ORIG_WINDOW holds the @N id; resize-window -t
        \"$ORIG_WINDOW\" (var already holds @3; do NOT prepend @)."

- file: scripts/restore.sh            # restore_main, STEP 4 (the status restore block)
  why: THE restore insertion point. The window-size restore goes AFTER
        `tmux set-option -g status \"$r_status\"` (shrink status FIRST, then restore
        window-size so panes return to natural size). GATED on opt_preview_fit==clip.
        orig_session is already read in STEP 3 and in scope here.
  pattern: "r_status=\"$(get_state \"$ORIG_STATUS\" \"on\")\"; tmux set-option -g status \"$r_status\""

- file: scripts/utils.sh              # tmux_save_opt / tmux_set_opt / set_state / lp_client_format
  why: house wrappers. NOTE window-size is SESSION-scoped, so tmux_save_opt (which reads
        show-option -gqv) is NOT usable for the save — capture session-scoped via
        `tmux show-options -t \"$sess\" -v window-size` into a direct set-option -g of
        ORIG_WINDOW_SIZE (mirrors how the display-message ORIG_* captures are written).
  gotcha: "the `=` exact-match prefix BREAKS set-option -t (gotcha #1) — ORIG_SESSION holds a
        BARE name; never write set-option -t \"=$sess\". show-options -t tolerates it; set-option -t does not."

- file: README.md                     # Configuration table (~line 110) + "Detached candidate" limitation (~line 188)
  why: add the @livepicker-preview-fit row after @livepicker-preview-defer; reconcile the
        limitation note to distinguish status-grow reflow (fixed by clip) from link-time
        resize (persists; snapshot workaround). Full prose is deferred to P4.
  pattern: "| `@livepicker-preview-defer` | `on` | ... | (mirror column widths/spacing for the new row)"

- file: plan/003_77ef311abf10/architecture/empirical_findings.md   # Finding 1 (read scope) + Finding 2 (residual)
  why: Finding 1 documents window-size is PER-SESSION (-t isolates) and the global-read
        save assumption. Finding 2 (the residual: linked candidate one-time link-time resize)
        is what the README limitation reconciliation describes.
  gotcha: "Finding 2 is OVERLY OPTIMISTIC ('manual protects the self-window') — superseded by
        clip_probe_findings.md (manual alone fails). Do NOT cite Finding 2 as the freeze mechanism."

- file: tests/setup_socket.sh + tests/test_scroll_width.sh   # the harness + a sibling activate/restore test
  why: VALIDATION template. test_scroll_width.sh drives the REAL livepicker.sh -> restore.sh on
        the isolated -L socket with attach_test_client and asserts byte-exact hook restore — the
        EXACT shape the ad-hoc clip verification (Validation Level 2) and the future
        test_preview_clip.sh (P3.M2.T1.S1) follow. setup_socket's attach_test_client script-pty
        reports 80x24 (NOT 120x40): driver usable height is 23 (status on) / 22 (status 2).
  pattern: "attach_test_client; \"$LIVEPICKER_SCRIPTS/livepicker.sh\"; <assert>; <restore>; <assert>"

- url: https://github.com/tmux/tmux/blob/master/CHANGES  (window-size semantics)
  why: window-size is a SESSION option (so -t isolates); `manual` leaves the window's size alone;
        a linked window has ONE shared size influenced by every session it is linked into.
  section: "the 'manual' / 'latest' / 'largest' / 'smallest' values; per-session -t scope"
```

### Current Codebase tree (run `ls scripts/ tests/` in the project root)

```bash
tmux-livepicker/
├── scripts/
│   ├── options.sh     # opt_<name>() accessors — ADD opt_preview_fit() here
│   ├── state.sh       # ORIG_* saved-state + clear_all_state — ADD ORIG_WINDOW_SIZE here
│   ├── utils.sh       # tmux_* wrappers + lp_client_format (read-only; do NOT edit)
│   ├── livepicker.sh  # activate_main — ADD the clip freeze in T3 (before the status-grow case)
│   ├── restore.sh     # restore_main — ADD the clip restore in STEP 4 (after the status shrink)
│   ├── preview.sh     # link-window preview (OUT OF SCOPE — candidate link-time clip is future)
│   ├── renderer.sh / input-handler.sh / layout.sh / rank.sh / session-mgmt.sh  # untouched
├── tests/             # setup_socket.sh harness + test_*.sh (test_preview_clip.sh is P3.M2.T1.S1, NOT this task)
├── plan/003_77ef311abf10/
│   ├── architecture/{clip_verification.md (GATE), empirical_findings.md, codebase_patterns.md, system_context.md}
│   └── P3M1T2S1/{PRP.md (THIS file), research/clip_freeze_recipe_findings.md}
├── PRD.md             # §22, §9, §10, §16 (READ-ONLY)
├── README.md          # Configuration table + "Detached candidate" limitation (EDIT: 1 row + 1 note)
└── CHANGELOG.md       # bugfix-001 "Detached candidate resize" (READ-ONLY; P4 owns the new entry)
```

### Desired Codebase tree with files to be added and responsibility of file

```bash
# No NEW files. This task EDITS five existing files (all responsibilities already exist):
scripts/options.sh      # +1 accessor: opt_preview_fit() default "clip"  (enum clip|reflow)
scripts/state.sh        # +1 readonly: ORIG_WINDOW_SIZE (saved-state; auto-cleared)
scripts/livepicker.sh   # +1 clip-gated freeze block in activate T3 (before the status-grow case)
scripts/restore.sh      # +1 clip-gated restore block in restore STEP 4 (after the status shrink)
README.md               # +1 Configuration row + the limitation note reconciled
# research/clip_freeze_recipe_findings.md already written (this PRP's synthesis)
```

### Known Gotchas of our codebase & tmux 3.6b Library Quirks

```bash
# CRITICAL (all probed on 3.6b by P3.M1.T1.S1 — see clip_probe_findings.md §0):

# 1. window-size manual ALONE DOES NOT PIN the height on 3.6b (condition B: reflow 23->22).
#    The LOAD-BEARING step is resize-window -y <pre-grow-height> (conditions C/F: byte-identical).
#    => The freeze is BOTH: `set-option -t manual` THEN `resize-window -y $H0`. NOT manual alone.

# 2. The `=` exact-match prefix BREAKS `set-option -t` for SESSION options:
#    `set-option -t "=driver" window-size manual` -> rc=1 "no such window: =driver".
#    ORIG_SESSION holds a BARE name -> `set-option -t "$ORIG_SESSION" ...` is correct.
#    (show-options -t tolerates `=`; set-option -t does NOT.)

# 3. NEVER `set-option -g window-size` (global). Global manual disconnected the window from the
#    client entirely (jumped to creation size 40). Per-session `-t "$ORIG_SESSION"` ONLY.

# 4. Address windows by @id, never index (renumber-windows is on). ORIG_WINDOW IS the @N id
#    (saved via lp_client_format '#{window_id}'). `resize-window -y "$H0" -t "$ORIG_WINDOW"`
#    (the var already holds e.g. @3); do NOT write `-t "@$ORIG_WINDOW"` (-> @@3).

# 5. window_height needs an attached client to read the client-driven usable size. Activate
#    runs from a keypress -> a client is attached, so display-message -p '#{window_height}'
#    returns the right value (e.g. 23). resize-window accepts a value LARGER than the client
#    and that IS the clip (tmux renders the top, clips the overflow row).

# 6. ORDERING: capture H0 BEFORE manual/resize; set manual; resize-window -y H0; THEN grow status.
#    On restore: shrink status FIRST (already STEP 4), THEN restore window-size (panes re-fit).

# 7. clear_all_state PRESERVES §11 config (@livepicker-* options). So opt_preview_fit() reads
#    correctly during restore (the picker's config survives the picker lifetime). Do NOT add
#    @livepicker-preview-fit to any clear list — it is CONFIG, not runtime state.

# 8. set-option -u -t <sess> <opt> UNSETS a session-scoped option (falls back to global). Use it
#    for byte-exact restore when the driver had NO session override (the common case). Verify
#    it returns the driver to inheriting global (Validation Level 2).
```

## Implementation Blueprint

No new data models — this task edits option/state accessor libs + two orchestrator blocks + one doc. The "models" are the one new accessor and the one new state constant.

### Data models and structure

```bash
# scripts/options.sh — new accessor (PRD §11 / §22 "Control"). 1 line, mirror the existing style.
opt_preview_fit()        { get_opt "@livepicker-preview-fit" "clip"; }   # enum: clip|reflow (clip = freeze height + clip bottom row on status grow; reflow = legacy one-row reflow)

# scripts/state.sh — new saved-state constant (PRD §9). Add to the ORIG_* block, NOT _STATE_RUNTIME_KEYS.
readonly ORIG_WINDOW_SIZE="@livepicker-orig-window-size"   # driver's pre-activate window-size (PRD §9/§22; frozen to manual in clip mode; session-scoped value saved, empty=inherits global)
```

### Implementation Tasks (ordered by dependencies)

```yaml
Task 1: READ the cited research + the insertion points (NO writes)
  - READ: plan/003_77ef311abf10/P3M1T2S1/research/clip_freeze_recipe_findings.md (THIS task's synthesis — read FIRST)
  - READ: plan/003_77ef311abf10/P3M1T1S1/research/clip_probe_findings.md §0 + §4 (the verified recipe + gotchas)
  - READ: plan/003_77ef311abf10/architecture/clip_verification.md §3 (the GATE recipe; if present)
  - READ: scripts/options.sh (opt_preview_mode/opt_preview_defer style), scripts/state.sh (ORIG_* block +
        clear_all_state grep), scripts/livepicker.sh activate_main T3 block (the status-grow case),
        scripts/restore.sh restore_main STEP 4 (the status restore), scripts/utils.sh (lp_client_format)
  - PURPOSE: internalize the CORRECTED recipe (manual + resize-pin, NOT manual alone) + the exact
        insertion points + the gotchas. Do NOT trust the item description's "manual only" or PRD §22 text.

Task 2: MODIFY scripts/options.sh — add opt_preview_fit()
  - ADD: one line `opt_preview_fit() { get_opt "@livepicker-preview-fit" "clip"; }` with a trailing
        comment (enum clip|reflow), placed next to opt_preview_mode()/opt_preview_defer() (the other
        @livepicker-preview-* options).
  - FOLLOW pattern: opt_preview_defer() (1-line accessor; comment notes the enum).
  - NAMING: opt_preview_fit (snake_case; the @livepicker-preview-fit suffix). DEFAULT "clip" (NOT
        "reflow" — P3.M1.T1.S1 confirmed clip is feasible via the corrected recipe).
  - PLACEMENT: scripts/options.sh, in the preview-options cluster.

Task 3: MODIFY scripts/state.sh — add ORIG_WINDOW_SIZE
  - ADD: `readonly ORIG_WINDOW_SIZE="@livepicker-orig-window-size"` with an inline comment
        (PRD §9/§22; frozen to manual in clip mode), placed in the ORIG_* block next to ORIG_RENUMBER.
  - FOLLOW pattern: `readonly ORIG_RENUMBER="@livepicker-orig-renumber-windows"`.
  - DO NOT: add ORIG_WINDOW_SIZE to _STATE_RUNTIME_KEYS (it is SAVED-STATE, not runtime); DO NOT edit
        clear_all_state (its `grep '@livepicker-orig-'` heredoc loop already unsets every @livepicker-orig-*
        incl. this one — §9 step 6 auto-clear is satisfied with zero code there).
  - NAMING: ORIG_WINDOW_SIZE (UPPER_SNAKE matching the ORIG_* family).
  - PLACEMENT: scripts/state.sh, ORIG_* block.

Task 4: MODIFY scripts/livepicker.sh activate_main T3 — the clip freeze block
  - INSERT: a clip-gated freeze block in T3, BETWEEN (b) install-renderer and (c) the status-grow
        `case "$orig_status"`. Exact anchor: insert immediately AFTER
        `tmux set-option -g "status-format[$lp_idx]" "#($CURRENT_DIR/renderer.sh)"`
        and BEFORE `# (c) grow the status line count by one ...`.
  - IMPLEMENT (verbatim recipe — see Implementation Patterns below):
        if [ "$(opt_preview_fit)" = "clip" ]; then
            local lp_fit_pre_h lp_fit_sess lp_fit_win
            lp_fit_sess="$(get_state "$ORIG_SESSION" "")"
            lp_fit_win="$(get_state "$ORIG_WINDOW" "")"
            # SAVE the driver's session-scoped window-size (empty = inherits global; byte-exact restore)
            tmux set-option -g "$ORIG_WINDOW_SIZE" "$(tmux show-options -t "$lp_fit_sess" -v window-size 2>/dev/null || true)"
            # capture the active window's pre-grow height (the pin target value)
            lp_fit_pre_h="$(tmux display-message -p -t "$lp_fit_win" '#{window_height}' 2>/dev/null || true)"
            # FREEZE: manual (per-session; client-resized robustness) THEN the load-bearing resize-pin
            tmux set-option -t "$lp_fit_sess" window-size manual        # NO '=' prefix (gotcha #2)
            [ -n "$lp_fit_pre_h" ] && tmux resize-window -y "$lp_fit_pre_h" -t "$lp_fit_win" 2>/dev/null || true
        fi
  - DEPENDENCIES: opt_preview_fit (Task 2), ORIG_WINDOW_SIZE (Task 3). ORIG_SESSION+ORIG_WINDOW saved in
        STEP 2 (already present). The active window is ORIG_WINDOW at this point (T2 switches nothing;
        first preview is T5, after the grow).
  - FOLLOW pattern: the existing T3 sub-step comments ((a)/(b)/(c)); add a (b.5) P3.M1.T2.S1 comment
        citing PRD §10 step 4 + §22 + clip_verification.md. House style: NO set -e (guard tmux calls
        with `2>/dev/null || true`); `local` for all locals; TABS for indent.
  - UPDATE in-code comments: the T3 block header should note step (c) is now preceded by the §22 freeze
        (clip mode) per PRD §10 step 4 (reordered: freeze FIRST, then grow).

Task 5: MODIFY scripts/restore.sh restore_main STEP 4 — the clip restore block
  - INSERT: a clip-gated restore block in STEP 4, AFTER the status restore
        (`tmux set-option -g status "$r_status"`) and BEFORE the key-table restore. Exact anchor:
        insert immediately AFTER `tmux set-option -g status "$r_status"` (the status shrink MUST happen
        first so the panes return to natural size when window-size is freed).
  - IMPLEMENT (byte-exact restore — see Implementation Patterns below):
        if [ "$(opt_preview_fit)" = "clip" ]; then
            local lp_rfit_ws
            lp_rfit_ws="$(get_state "$ORIG_WINDOW_SIZE" "")"
            if [ -n "$lp_rfit_ws" ]; then
                tmux set-option -t "$orig_session" window-size "$lp_rfit_ws"   # replay prior override
            else
                tmux set-option -u -t "$orig_session" window-size 2>/dev/null || true  # unset ours (byte-exact)
            fi
        fi
  - DEPENDENCIES: opt_preview_fit (Task 2), ORIG_WINDOW_SIZE (Task 3). `orig_session` is read in STEP 3
        and in scope here (function-local). opt_preview_fit reads the live config (clear_all_state
        preserves §11 config, so it is correct during restore — but STEP 6 clear_all_state runs AFTER
        STEP 4, so ORIG_WINDOW_SIZE is still readable here; get_state it BEFORE any clear).
  - FOLLOW pattern: the existing STEP 4 sub-comments (status-format / status / key-table / ...); add a
        P3.M1.T2.S1 comment citing PRD §9 step 4 + §22 restore. Mirror the clip gate (symmetry with
        activate: reflow skips both).
  - UPDATE in-code comments: the STEP 4 header should note window-size is now restored here in clip mode
        (PRD §9 step 4 lists "the driver's window-size").

Task 6: MODIFY README.md — config row + limitation reconciliation (item description §5; Mode A)
  - ADD a Configuration-table row for `@livepicker-preview-fit` (default `clip`), placed after the
        `@livepicker-preview-defer` row. Purpose text: "`clip` freezes the preview height before the
        status bar grows so panes do not reflow (the bottom row is clipped); `reflow` is the legacy
        one-row reflow. Use `reflow` if `clip` misbehaves on your tmux/terminal."
  - RECONCILE the "Detached candidate windows are resized during preview" limitation note
        (~README line 188): distinguish the TWO effects —
          (1) STATUS-GROW reflow (panes shrinking when the extra status line appears): now ADDRESSED by
              the default `@livepicker-preview-fit clip`.
          (2) LINK-TIME resize of a detached candidate to the driver's size: PERSISTS (shared window;
              clip does not eliminate it). To avoid it, set `@livepicker-preview-mode snapshot`.
        Keep it tight; full prose is deferred to P4 (item description: "Full prose in P4").
  - FOLLOW pattern: the existing table column widths/spacing; the existing limitation-bullet tone.
  - PLACEMENT: README.md Configuration table + Known limitations section.
  - DO NOT: edit CHANGELOG.md (P4.T1.S2 owns the new entry); do NOT edit PRD.md.

Task 7: VALIDATE (see Validation Loop) — shellcheck + ad-hoc clip verification + full suite regression.
  - The formal test_preview_clip.sh is P3.M2.T1.S1's deliverable (a SEPARATE task, Planned). This task
        verifies via shellcheck + an ad-hoc harness probe (Level 2) + the existing suite (Level 3).
```

### Implementation Patterns & Key Details

```bash
# === ACTIVATE FREEZE (scripts/livepicker.sh activate_main T3, step b.5) ===
# Slot in BETWEEN (b) install-renderer and (c) the status-grow case. GATED on clip.
# (b) install the picker renderer at the configured index (default 0).
# lp_idx="$(opt_status_format_index)"
# tmux set-option -g "status-format[$lp_idx]" "#($CURRENT_DIR/renderer.sh)"
# --- (b.5) P3.M1.T2.S1: FREEZE the driver's window-size (clip mode) BEFORE the grow (PRD §10 step 4 / §22) ---
if [ "$(opt_preview_fit)" = "clip" ]; then
	# opt_preview_fit==clip: save the driver's window-size, pin the active window's height so the
	# impending status grow CANNOT reflow it (clip: tmux renders the top, clips the overflow row).
	# MANUAL ALONE FAILS on 3.6b (clip_probe_findings cond B); the resize-window -y H0 PIN is load-bearing (cond C/F).
	local lp_fit_pre_h lp_fit_sess lp_fit_win
	lp_fit_sess="$(get_state "$ORIG_SESSION" "")"
	lp_fit_win="$(get_state "$ORIG_WINDOW" "")"
	# SAVE the driver's SESSION-SCOPED window-size (NOT global): empty when the driver had no
	# override (inherits global "latest", the common case) -> restore UNSETS our override (byte-exact).
	tmux set-option -g "$ORIG_WINDOW_SIZE" "$(tmux show-options -t "$lp_fit_sess" -v window-size 2>/dev/null || true)"
	# capture the active window's height BEFORE any status change (the pin target value).
	lp_fit_pre_h="$(tmux display-message -p -t "$lp_fit_win" '#{window_height}' 2>/dev/null || true)"
	# FREEZE: per-session manual (client-resized robustness), then the load-bearing height pin.
	tmux set-option -t "$lp_fit_sess" window-size manual        # NO '=' prefix; NEVER -g (gotchas #2,#3)
	[ -n "$lp_fit_pre_h" ] && tmux resize-window -y "$lp_fit_pre_h" -t "$lp_fit_win" 2>/dev/null || true
fi
# (c) grow the status line count by one — NORMALIZED for tmux's on/off/2..5 ...  [UNCHANGED case block]

# === RESTORE (scripts/restore.sh restore_main STEP 4, after the status shrink) ===
# r_status="$(get_state "$ORIG_STATUS" "on")"
# tmux set-option -g status "$r_status"        # status shrink FIRST (already present)
# --- P3.M1.T2.S1: restore the driver's window-size (clip mode mirror; PRD §9 step 4 / §22) ---
# AFTER the status shrink so the panes return to natural size when window-size is freed.
if [ "$(opt_preview_fit)" = "clip" ]; then
	local lp_rfit_ws
	lp_rfit_ws="$(get_state "$ORIG_WINDOW_SIZE" "")"
	if [ -n "$lp_rfit_ws" ]; then
		tmux set-option -t "$orig_session" window-size "$lp_rfit_ws"               # replay prior session override
	else
		tmux set-option -u -t "$orig_session" window-size 2>/dev/null || true       # unset ours -> inherits global (byte-exact)
	fi
fi
# key-table / renumber-windows / hooks ...  [rest of STEP 4 UNCHANGED]

# GOTCHA (resize-window target): ORIG_WINDOW holds the @N id (e.g. @3). Write `-t "$lp_fit_win"`
# (the var holds @3). NEVER `-t "@$lp_fit_win"` (-> @@3, rc=1).
# GOTCHA (set-option -t vs show-options -t): the `=` prefix is rejected by set-option -t but accepted
# by show-options -t. ORIG_SESSION is a bare name either way; just never prepend `=` to a set-option -t.
# GOTCHA (reflow): the `if [ clip ]` gate makes reflow a no-op in BOTH activate and restore — no else
# branch needed. window-size is never touched in reflow mode (legacy one-row reflow on status grow).
```

### Integration Points

```yaml
STATE CONTRACT (PRD §9):
  - add to saved-state set: ORIG_WINDOW_SIZE="@livepicker-orig-window-size" (written activate, read restore).
  - auto-clear: satisfied with ZERO code — clear_all_state's `grep '@livepicker-orig-'` heredoc loop
    already unsets every @livepicker-orig-*. Do NOT add it to _STATE_RUNTIME_KEYS (that is the
    picker-INTERNAL runtime set; ORIG_* is the saved-state set, a different list).
  - PRD §9 step 4 (restore): now includes "the driver's window-size" — the restore block implements it.
  - PRD §9 step 2 (save list): now includes "Current window-size of the driver session" — the save line
    in the freeze block implements it (it lives in the freeze block rather than STEP 2 because it is
    clip-mode-only; mirror-symmetric with the clip-only restore).

OPTIONS (PRD §11):
  - add: @livepicker-preview-fit, default "clip", enum clip|reflow. Reads via get_opt (global @-option).

ACTIVATE ORDERING (PRD §10 step 4, REORDERED):
  - the freeze (manual + resize-pin) runs BEFORE the status grow (the existing T3 case block). This is
    the §22-critical ordering (clip_verification.md GATES it). The renderer install (T3 b) is unchanged.

RESTORE ORDERING (PRD §9 step 4):
  - status shrink FIRST (already present), THEN window-size restore. So the window-size block goes
    AFTER `tmux set-option -g status "$r_status"` and BEFORE the key-table restore. (Exact position
    relative to key-table/renumber is not load-bearing, but keep it right after the status restore.)

CANDIDATE LINK-TIME CLIP (preview.sh): OUT OF SCOPE. The optional one-time resize-window -y H at link
  time (PRD §22) is future polish, NOT this task. clip addresses the SELF-WINDOW status-grow reflow only.
```

## Validation Loop

### Level 1: Syntax & Style (Immediate Feedback)

```bash
cd /home/dustin/.config/tmux/plugins/tmux-livepicker
# shellcheck the modified scripts (project uses shellcheck; scripts carry disable directives).
shellcheck scripts/options.sh scripts/state.sh scripts/livepicker.sh scripts/restore.sh
# Expected: zero NEW errors. The four files already pass; your edits must keep them clean.
# (Existing SC2153/SC1091 disables for ORIG_*/STATE_* sourced consts already cover the new ORIG_WINDOW_SIZE.)
# Re-source sanity (no side effects on source):
bash -n scripts/options.sh && bash -n scripts/state.sh && bash -n scripts/livepicker.sh && bash -n scripts/restore.sh
# Expected: no syntax errors. Sourcing options.sh/state.sh prints nothing (sourced-library contract).
```

### Level 2: Ad-hoc clip verification through the REAL activate/restore path

The formal `tests/test_preview_clip.sh` is **P3.M2.T1.S1** (a separate Planned task). This task
verifies the implementation directly via the harness + the real `livepicker.sh`/`restore.sh`, in the
EXACT shape `test_preview_clip.sh` will later formalize. Run this throwaway probe (it sources the
shipped harness; it does NOT touch the real server):

```bash
cd /home/dustin/.config/tmux/plugins/tmux-livepicker
# CLIP mode (default): the driver's active-window window_layout is BYTE-IDENTICAL across the status grow.
source tests/setup_socket.sh
setup_socket "lp-clip-verify-$$"; attach_test_client
AW="$(tmux list-windows -t "$TEST_DRIVER_SESSION" -F '#{window_id}' -f '#{window_active}')"
L0="$(tmux display-message -p -t "$AW" '#{window_layout}')"; H0="$(tmux display-message -p -t "$AW" '#{window_height}')"
"$LIVEPICKER_SCRIPTS/livepicker.sh" >/dev/null          # activate (clip default) -> freeze + grow status
sleep 0.3
L1="$(tmux display-message -p -t "$AW" '#{window_layout}')"; H1="$(tmux display-message -p -t "$AW" '#{window_height}')"
[ "$L0" = "$L1" ] && echo "CLIP: no reflow (layout pinned) OK" || echo "CLIP: REFLOWED — FAIL (check the freeze ran)"
[ "$H0" = "$H1" ] && echo "CLIP: height pinned OK"      || echo "CLIP: height changed — FAIL"
# window-size was frozen: the driver session is now manual.
[ "$(tmux show-options -t "$TEST_DRIVER_SESSION" -v window-size)" = "manual" ] && echo "CLIP: frozen manual OK" || echo "CLIP: not manual — FAIL"
# restore: shrink status + restore window-size (byte-exact: unset->unset).
"$LIVEPICKER_SCRIPTS/input-handler.sh" cancel >/dev/null
[ -z "$(tmux show-options -t "$TEST_DRIVER_SESSION" -v window-size 2>/dev/null)" ] && echo "CLIP restore: window-size unset (byte-exact) OK" || echo "CLIP restore: window-size residue — FAIL"
teardown_socket

# REFLOW mode: window-size is NEVER touched (activate AND restore skip via the clip gate).
setup_socket "lp-reflow-verify-$$"; attach_test_client
tmux set-option -g @livepicker-preview-fit reflow
"$LIVEPICKER_SCRIPTS/livepicker.sh" >/dev/null; sleep 0.3
[ -z "$(tmux show-options -t "$TEST_DRIVER_SESSION" -v window-size 2>/dev/null)" ] && echo "REFLOW: window-size untouched OK" || echo "REFLOW: window-size touched — FAIL (the clip gate must skip)"
"$LIVEPICKER_SCRIPTS/input-handler.sh" cancel >/dev/null
teardown_socket
unset -f setup_socket teardown_socket  # cleanup the sourced funcs
# Expected: CLIP no-reflow + frozen manual + byte-exact restore; REFLOW window-size untouched.
# If CLIP shows a reflow: the freeze did NOT run before the grow — recheck Task 4 placement (BEFORE the case block).
```

### Level 3: Regression — existing suite stays green

```bash
cd /home/dustin/.config/tmux/plugins/tmux-livepicker
bash tests/run.sh
# Expected: exit 0, all PASS. KEY suites to eyeball:
#   - test_restore.sh: byte-exact restore of status/status-format/key-table/hooks is UNBROKEN
#     (window-size global is never touched; session-scoped value round-trips empty->empty).
#   - test_pollution.sh: browsing fires no client-session-changed (unchanged by this task).
#   - test_functional.sh / test_preview.sh: activate->nav->confirm/cancel still works under clip.
# If test_restore byte-exact assertions now FAIL: your restore left a session-scoped window-size
# residue -> use the unset-when-empty branch (Task 5) so unset->unset.
```

### Level 4: Non-pollution (the core invariant, PRD §15)

```bash
cd /home/dustin/.config/tmux/plugins/tmux-livepicker
BEFORE="$(/usr/bin/tmux list-sessions -F '#{session_name}' 2>/dev/null | sort)"
# (run the Level 2 probe here, or bash tests/run.sh)
bash tests/run.sh >/dev/null 2>&1
AFTER="$(/usr/bin/tmux list-sessions -F '#{session_name}' 2>/dev/null | sort)"
[ "$BEFORE" = "$AFTER" ] && echo "REAL SERVER UNTOUCHED" || echo "POLLUTION — abort"
# Expected: REAL SERVER UNTOUCHED. window-size is set per-session on the ISOLATED -L socket only.
```

### Level 5: Creative & Domain-Specific Validation

```bash
# README sanity: the new row + the reconciled limitation note are present + well-formed.
grep -n '@livepicker-preview-fit' README.md                 # the new config row
grep -n 'clip' README.md | head                            # the limitation note mentions clip
# Confirm the limitation note DISTINGUISHES the two effects (status-grow reflow vs link-time resize).
grep -A6 'Detached candidate windows are resized' README.md
# Confirm the global window-size is never touched by the plugin (only -t session-scoped):
grep -n 'set-option -g window-size' scripts/                # MUST be empty (never -g for window-size)
# Expected: the grep for '-g window-size' returns nothing (gotcha #3).
```

## Final Validation Checklist

### Technical Validation
- [ ] Level 1: `shellcheck scripts/{options,state,livepicker,restore}.sh` clean (no new errors); `bash -n` passes.
- [ ] Level 2: CLIP mode — driver active-window `window_layout` byte-identical across the status grow; height pinned; frozen `manual`; restore leaves session-scoped window-size unset (byte-exact).
- [ ] Level 2: REFLOW mode — `window-size` never touched (activate + restore both skip).
- [ ] Level 3: `bash tests/run.sh` exit 0 (test_restore byte-exact + pollution suites green).
- [ ] Level 4: real tmux server byte-identical before/after (PRD §15).
- [ ] Level 5: no `set-option -g window-size` anywhere in scripts/ (gotcha #3); README row + note present.

### Feature Validation
- [ ] `opt_preview_fit()` returns `clip` by default, `reflow` when set.
- [ ] `ORIG_WINDOW_SIZE` is in the `ORIG_*` block and is auto-cleared by `clear_all_state` (no edit to clear_all_state needed).
- [ ] clip mode freezes the driver BEFORE the status grow (manual + resize-window -y H0) and restores it on exit.
- [ ] reflow mode is byte-identical to the pre-§22 behavior (no window-size touches).
- [ ] The freeze is gated exactly where the item description says: BEFORE the status-grow `case` block in activate T3.
- [ ] The restore is exactly where the item description says: AFTER the status shrink in restore STEP 4.

### Code Quality Validation
- [ ] Follows existing accessor/state/orchestrator conventions (1-line accessor; readonly ORIG_*; house-style guarded tmux calls).
- [ ] Freeze block comment cites PRD §10 step 4 / §22 / clip_verification.md; restore block cites PRD §9 step 4 / §22.
- [ ] No `set -e` added (house style); all new tmux calls guarded `2>/dev/null || true`.
- [ ] `local` for all new variables; TABS for indent; no redeclaration of existing function-locals.
- [ ] The CORRECTED recipe (manual + resize-pin) is used, NOT the contract's/PD's "manual only" (which fails on 3.6b).

### Documentation & Deployment
- [ ] README Configuration table has the `@livepicker-preview-fit` row (default `clip`).
- [ ] README "Detached candidate resize" limitation distinguishes status-grow reflow (fixed by clip) from link-time resize (persists; snapshot workaround).
- [ ] CHANGELOG.md and PRD.md UNMODIFIED (CHANGELOG new entry is P4.T1.S2; PRD is read-only).

---

## Anti-Patterns to Avoid

- ❌ Don't implement "manual only" (the item description's literal LOGIC / PRD §22 "Mechanism (intended)") — it FAILS on 3.6b (reflow 23→22). The load-bearing step is `resize-window -y <pre-grow-height>`. This is the GATE's (clip_verification.md / clip_probe_findings.md) central correction; ignoring it makes the feature not work.
- ❌ Don't `set-option -g window-size` (global) — it disconnects the window from the client (jumped to creation size 40). Per-session `-t "$ORIG_SESSION"` only.
- ❌ Don't prepend `=` to a `set-option -t` target (`set-option -t "=driver"` → rc=1). ORIG_SESSION holds a bare name; use it directly. (`show-options -t` tolerates `=`; `set-option -t` does not.)
- ❌ Don't write `-t "@$ORIG_WINDOW"` (→ `@@3`). ORIG_WINDOW already holds `@N`; write `-t "$ORIG_WINDOW"`.
- ❌ Don't grow status BEFORE the freeze — the §22-critical ordering is freeze-FIRST (manual + resize-pin), THEN grow. The freeze block goes between (b) install-renderer and (c) the status-grow case.
- ❌ Don't restore window-size BEFORE shrinking status — shrink status FIRST (already STEP 4), THEN restore window-size, so panes return to natural size (item description: "panes return to natural size").
- ❌ Don't add ORIG_WINDOW_SIZE to `_STATE_RUNTIME_KEYS` or hand-clear it in `clear_all_state` — it is SAVED-STATE; the existing `grep '@livepicker-orig-'` loop already clears it (zero code there).
- ❌ Don't leave a session-scoped `window-size` residue on restore — when the driver had NO override (the common case), `set-option -u -t` to unset ours so restore is byte-exact (PRD §15 zero-trace). The contract's "read global + set -t" leaves a residue; the byte-exact branch avoids it.
- ❌ Don't implement the candidate link-time clip (`resize-window -y H` in preview.sh) — that is OUT OF SCOPE (future polish). This task is activate-freeze + restore only.
- ❌ Don't write the formal `tests/test_preview_clip.sh` — that is P3.M2.T1.S1's deliverable. This task validates via shellcheck + the Level 2 ad-hoc probe + the existing suite.
- ❌ Don't touch PRD.md, CHANGELOG.md, empirical_findings.md, clip_verification.md, or any tasks.json (all read-only / owned elsewhere).

---

## Confidence Score: 9/10

The freeze recipe is already empirically PROVEN on this exact box (clip_probe_findings.md conditions C/F: manual + resize-window -y H0 → byte-identical layout, stable across a 2nd grow), and the gate (P3.M1.T1.S1's clip_verification.md) names it verbatim. The insertion points, the byte-exact restore decision, the option/state conventions, and the gotchas are all pinned from the live codebase. The residual 1/10 is: (a) the `set-option -u -t` byte-exact restore branch — verify it returns the driver to inheriting global (Level 2 asserts empty→empty); (b) `display-message -p '#{window_height}'` returning a sane value at activate (always has a client there, so low risk); (c) the rare case where P3.M1.T1.S1's parallel run produces a different verdict — but the recipe is fully specified in clip_probe_findings.md regardless, so this task does not block on the doc file existing. The implementer's job is to wire a verified recipe into two exact insertion points + mirror an existing option/state pattern, not to discover tmux behavior.
