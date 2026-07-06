# PRP — P1.M2.T1.S1: Add `opt_preview_defer()` accessor + `STATE_PREVIEW_SEQ` / `STATE_PREVIEW_TARGET` state keys + seq init (PRD §18)

> **Scope**: The foundation seam for §18 (deferred preview). Adds (1) the
> `opt_preview_defer()` option accessor (`on` default), (2) two picker-internal
> **runtime** state-key constants — `STATE_PREVIEW_SEQ` (the monotonic supersede
> counter) / `STATE_PREVIEW_TARGET` (the latest target token) — wired into
> `_STATE_RUNTIME_KEYS` so `clear_all_state` clears them (no leak; no late-`-b`-job
> clobber), and (3) the seq→0 init at activation. This is the **exact analog of the
> already-COMPLETE P1.M1.T1.S1** (tab-style accessor + STATE_TAB_* keys), adapted for
> the preview-defer feature.

---

## Goal

**Feature Goal**: Lay the foundation for PRD §18 (interaction-first, deferred preview)
by adding the option toggle + the two state keys that the downstream supersede machinery
consumes: `opt_preview_defer()` in `scripts/options.sh` (returns `on`/`off`, default
`on`), and `STATE_PREVIEW_SEQ` / `STATE_PREVIEW_TARGET` runtime constants in
`scripts/state.sh` (read/writable via `set_state`/`get_state`, cleared on exit via
`_STATE_RUNTIME_KEYS`). Plus the authoritative reset: `set_state "$STATE_PREVIEW_SEQ" "0"`
at activation in `scripts/livepicker.sh`.

**Deliverable**: Three small edits to existing files — **no new files**.
1. `scripts/options.sh`: append one single-line accessor `opt_preview_defer()` after
   `opt_tab_style()` (the current last accessor).
2. `scripts/state.sh`: add two `readonly STATE_PREVIEW_*` constants to the runtime block
   (after `STATE_TAB_INACTIVE_TMPL`) + append both to `_STATE_RUNTIME_KEYS`.
3. `scripts/livepicker.sh`: add one `set_state "$STATE_PREVIEW_SEQ" "0"` in
   `activate_main`'s state-init region (right after the `STATE_LINKED_ID` init).

**Success Definition**:
- `opt_preview_defer` returns `"on"` when `@livepicker-preview-defer` is unset (the PRD
  §11 default) and surfaces a user override (`off`) via `get_opt`.
- `STATE_PREVIEW_SEQ` / `STATE_PREVIEW_TARGET` resolve to `@livepicker-preview-seq` /
  `@livepicker-preview-target`.
- Both keys are members of `_STATE_RUNTIME_KEYS`, so `clear_all_state` unsets them
  (proven: after `set_state` + `clear_all_state`, `tmux_is_set` → unset).
- At activation, `@livepicker-preview-seq` is `"0"` (proven after `activate_main`).
- Sourcing all three files has **no side effects**; `bash -n` + `shellcheck` clean.

## User Persona (if applicable)

**Target User**: Downstream scripts — P1.M2.T2.S1 (preview.sh seq guard, READS
`STATE_PREVIEW_SEQ`) and P1.M2.T3.S1 (input-handler.sh fire helper, BUMPS seq + WRITES
`STATE_PREVIEW_TARGET`). Not end-user facing.

**Use Case**: When `opt_preview_defer = on`, typing/nav no longer call the preview inline;
instead the fire helper bumps `STATE_PREVIEW_SEQ`, writes the target to
`STATE_PREVIEW_TARGET`, and launches a background `run-shell -b preview.sh '<target>'
'<seq>'`. The background job re-reads the live seq and no-ops if a newer target won — so a
late job can never clobber the current link. `off` restores the synchronous path
(diagnostic escape hatch). This subtask provides only the toggle + the keys + the init.

**Pain Points Addressed**: No mechanism yet to (a) read the `preview-defer` toggle or
(b) hold the supersede counter/target in clearable runtime state. Without the seq in
`_STATE_RUNTIME_KEYS`, a late background job post-teardown could match a stale seq and
clobber the user's restored window (Q6 gotcha, §16 "Deferred-preview concurrency").

## Why

- **Foundation for §18.** Every later subtask (P1.M2.T2 seq guard, P1.M2.T3 fire helper)
  needs these names to exist and to be cleared correctly. This subtask is the contract
  seam.
- **Leak + supersede safety (system_context §3 Q4; external_tmux_behavior Q6).**
  `clear_all_state` iterates `_STATE_RUNTIME_KEYS`. A runtime key NOT added there (a)
  LEAKS across picker sessions and (b) lets a late `-b` preview job match a stale seq
  after cancel/confirm and `unlink-window`/`link-window` over the just-restored window.
  Adding both keys here makes the foundation safe by construction; the activation-time
  `seq=0` init is the authoritative reset for the fresh session.
- **Runtime, not config (system_context §3 Q1).** The seq/target are written during the
  picker lifetime, not user-configured. They belong in `state.sh` as `STATE_*` runtime
  keys (cleared on exit), NOT in the `ORIG_*` saved-state contract (those are
  originals-to-restore per PRD §9). `opt_preview_defer` IS config (PRD §11 toggle) → it
  lives in `options.sh` and is NEVER cleared by `clear_all_state` (CORRECTION A).
- **Disjoint from the parallel task.** P1.M1.T3.S1 (in-flight) modifies `renderer.sh`
  ONLY. This task edits `options.sh`, `state.sh`, `livepicker.sh` — no collision. It
  appends after the already-complete T1.S1 (options/state tab-style) and T2.S1
  (livepicker sentinel).

## What

1. **options.sh**: append `opt_preview_defer()` after `opt_tab_style()` (currently the
   last accessor, line 45), matching the existing single-line
   `{ get_opt "@livepicker-<name>" "<default>"; }` pattern exactly. Default `"on"`.
2. **state.sh**: add two `readonly STATE_PREVIEW_*` constants to the **runtime** block
   (immediately after `STATE_TAB_INACTIVE_TMPL`, before the blank line + `ORIG_*` header),
   then append both to the `_STATE_RUNTIME_KEYS` space-list.
3. **livepicker.sh**: add one `set_state "$STATE_PREVIEW_SEQ" "0"` line in
   `activate_main`'s state-init region, immediately after the `set_state "$STATE_LINKED_ID"
   ""` line (anchored by content — the contract's "~line 82" is stale; actual is line 157).
4. **Do NOT** add these to the `ORIG_*` saved-state block (they are runtime, not
   originals-to-restore). **Do NOT** init `STATE_PREVIEW_TARGET` at activation (the
   contract initializes only the SEQ; TARGET starts unset/empty, read via
   `get_state "$STATE_PREVIEW_TARGET" ""`). **Do NOT** implement the seq guard or the fire
   helper here — those are P1.M2.T2 / P1.M2.T3.

### Success Criteria

- [ ] `opt_preview_defer()` present in options.sh; returns `"on"` when unset.
- [ ] `grep -c 'get_opt "@livepicker-preview-defer" "on"' scripts/options.sh` → **1**;
      `"off"` default → **0**.
- [ ] `STATE_PREVIEW_SEQ` / `STATE_PREVIEW_TARGET` defined in the runtime block of
      state.sh (after `STATE_TAB_INACTIVE_TMPL`, before the `ORIG_*` block).
- [ ] `_STATE_RUNTIME_KEYS` contains both new keys (appended).
- [ ] `clear_all_state` unsets both (leak-prevention smoke passes).
- [ ] After `activate_main`, `get_state "$STATE_PREVIEW_SEQ" "0"` == `"0"`.
- [ ] `bash -n` + `shellcheck` clean on all three files; sourcing = no side effects.

## All Needed Context

### Context Completeness Check

_Pass_: The implementer needs (a) the three exact edits (given verbatim below with
content anchors), (b) the `on`-not-`off` default, (c) the runtime-vs-ORIG classification,
and (d) the validation commands. Every behavior is verified against the current working
tree (post-T1.S1/T2.S1 landing) and the already-live-verified architecture docs.

### Documentation & References

```yaml
# MUST READ — the empirical ground-truth for THIS task (8 live-verified findings)
- docfile: plan/002_facc52335e68/P1M2T1S1/research/preview_defer_keys_findings.md
  why: FINDING 1 (targets absent; T1.S1 landed — append after opt_tab_style/STATE_TAB_*);
       FINDING 2 (default "on" — PRD §11 + system_context §2, doubly attested);
       FINDING 3 (SEQ is the monotonic supersede counter — Q6; run-shell -b is NOT
       cancellable, so a late job must no-op via the seq; clear_all_state + init=0 are
       the teardown safety); FINDING 4 (TARGET = latest token, observability + optional
       recheck; NO activation init — contract inits only SEQ); FINDING 5 (the EXACT three
       edits with verified line anchors: options.sh line 45, state.sh lines 44+49,
       livepicker.sh line 157); FINDING 6 (runtime-vs-config + runtime-vs-ORIG);
       FINDING 7 (no-side-effects); FINDING 8 (seq-init placement is before the first
       preview, correct).
  critical: FINDING 5C — anchor Edit C on CONTENT (the `set_state "$STATE_LINKED_ID" ""`
            line at line 157), NOT the contract's stale "~line 82".

# MUST READ — the closest sibling PRP (the tab-style analog; mirror its structure/shape)
- docfile: plan/002_facc52335e68/P1M1T1S1/PRP.md
  why: P1.M1.T1.S1 added opt_tab_style() + STATE_TAB_CURRENT_TMPL/STATE_TAB_INACTIVE_TMPL
       using the EXACT same edit pattern this task repeats for preview-defer. Its
       validation loop (L1 grep cross-checks, L2 leak-prevention smoke, L3 no-side-effects
       cksum, L4 default cross-check) is the template to reuse. Its GOTCHAs (stale line
       numbers, runtime-vs-ORIG, _STATE_RUNTIME_KEYS mandatory, SC2034 already disabled)
       all carry over verbatim.
  section: "Implementation Patterns & Key Details" (the verbatim oldText/newText pairs)

# MUST READ — the authoritative default + the seq-guard semantics
- docfile: plan/002_facc52335e68/architecture/system_context.md
  why: §2 (@livepicker-preview-defer default "on"); §3 Q3 (on = defer to bg run-shell -b
       supersedeable job; off = legacy synchronous; first preview stays synchronous);
       §3 Q4 (_STATE_RUNTIME_KEYS update is MANDATORY — a runtime key NOT listed leaks);
       §6 (insertion points table — options.sh after opt_status_format_index, state.sh
       runtime block + _STATE_RUNTIME_KEYS, livepicker.sh save/init region).
  section: "§2", "§3 Q3", "§3 Q4", "§6 Exact insertion points"

# MUST READ — the supersede pattern (WHY the seq exists + the teardown-safety argument)
- docfile: plan/002_facc52335e68/architecture/external_tmux_behavior.md
  why: Q5 (run-shell -b is detached, non-blocking, NOT cancellable by id — a late job must
       be a no-op); Q6 (the monotonic @livepicker-preview-seq counter pattern: bump on
       fire, capture at fire time, re-check in preview.sh before mutating; "If the picker
       exits while a -b job is mid-flight ... the seq guard prevents it from clobbering
       restored state" — the load-bearing reason STATE_PREVIEW_SEQ must be in
       _STATE_RUNTIME_KEYS AND init'd to 0).
  section: "Q5", "Q6"

# MUST READ — the file edited for Edit A (the accessor pattern + insertion point)
- file: scripts/options.sh
  why: Line 45 opt_tab_style() (verify present; T1.S1 landed) is the LAST accessor —
        append opt_preview_defer() immediately after it. The block is single-line
        `opt_<suffix>()  { get_opt "@livepicker-<name>" "<default>"; }  # comment`.
  pattern: 'opt_preview_defer()        { get_opt "@livepicker-preview-defer" "on"; }      # bool on|off ...'
  gotcha: The comment block (~options.sh line 20-22) states the one-space arg formatting
          is load-bearing for the "Level-4 default cross-check grep" — match the format.

# MUST READ — the file edited for Edit B (runtime block + _STATE_RUNTIME_KEYS)
- file: scripts/state.sh
  why: Runtime STATE_* block (STATE_MODE..STATE_TAB_INACTIVE_TMPL, lines 40-44);
        _STATE_RUNTIME_KEYS (line 49, the space-list clear_all_state iterates); set_state/
        get_state helpers. Insert the two consts after STATE_TAB_INACTIVE_TMPL (line 44),
        before the blank + ORIG header (line 46). Append both to _STATE_RUNTIME_KEYS.
  pattern: 'readonly STATE_PREVIEW_SEQ="@livepicker-preview-seq"'  (runtime block);
           '_STATE_RUNTIME_KEYS="... $STATE_PREVIEW_SEQ $STATE_PREVIEW_TARGET"'.
  gotcha: state.sh header DEPENDS ON utils.sh — the caller sources utils.sh first (do not
          source it inside state.sh). SC2034 (unused var) is ALREADY disabled file-wide
          (covers the new consts). ORDER: declare the consts ABOVE the _STATE_RUNTIME_KEYS
          line so the $STATE_PREVIEW_SEQ expansion resolves (same layout as STATE_TAB_*).

# MUST READ — the file edited for Edit C (the state-init region in activate_main)
- file: scripts/livepicker.sh
  why: activate_main's picker-internal state init. The anchor (verified live, line 157):
           # Init the linked-preview id ...
           set_state "$STATE_LINKED_ID" ""
        Insert set_state "$STATE_PREVIEW_SEQ" "0" immediately AFTER it (1-tab indent).
        This is BEFORE the T2 list-build (line 160) and the first preview (line ~404) —
        correct: the seq must be 0 before any deferred fire (which happens only on
        subsequent type/nav input via P1.M2.T3).
  gotcha: The contract's "~line 82" is STALE (live file: line 157). Anchor on the
          `set_state "$STATE_LINKED_ID" ""` CONTENT, not a line number.

# MUST READ — PRD §18 (the feature spec) + §11 (the option default) + §16 (concurrency risk)
- docfile: PRD.md
  why: §18 specifies the deferred/supersedeable contract (typing = status-only sync; nav
       = sync highlight + deferred preview; preview is deferred and supersedeable via a
       pending sequence; confirm never blocks). §11 row `@livepicker-preview-defer` default
       `on`. §16 "Deferred-preview concurrency" mandates the supersede guard.
  section: "§18 Responsiveness", "§11 Configuration options (@livepicker-preview-defer row)",
           "§16 Implementation risks (Deferred-preview concurrency)"
```

### Current Codebase tree

```bash
tmux-livepicker/
  scripts/
    options.sh       # MODIFY: append opt_preview_defer() after opt_tab_style() (line 45)
    state.sh         # MODIFY: +2 readonly STATE_PREVIEW_* (runtime block, after STATE_TAB_*) + extend _STATE_RUNTIME_KEYS
    livepicker.sh    # MODIFY: +1 set_state "$STATE_PREVIEW_SEQ" "0" in activate_main (after STATE_LINKED_ID init, line 157)
    utils.sh         # UNCHANGED (tmux_set_opt/get_opt — already present)
    filter.sh / preview.sh / input-handler.sh / renderer.sh / restore.sh / plugin.tmux  # UNCHANGED
                     # NOTE: P1.M1.T3.S1 (parallel) modifies renderer.sh ONLY — DISJOINT from this task.
  tests/             # UNCHANGED (feature tests land in P1.M3.T1 test_responsiveness.sh)
```

### Desired Codebase tree with files to be added and responsibility of file

```bash
scripts/options.sh    # +1 accessor: opt_preview_defer() — the on|off toggle (PRD §11/§18; default on)
scripts/state.sh      # +2 runtime keys: STATE_PREVIEW_SEQ (supersede counter) / STATE_PREVIEW_TARGET (latest token);
                       #   both cleared by clear_all_state via _STATE_RUNTIME_KEYS
scripts/livepicker.sh # +1 set_state STATE_PREVIEW_SEQ "0" at activation (authoritative reset of the monotonic counter)
```

### Known Gotchas of our codebase & Library Quirks

```bash
# CRITICAL — DEFAULT IS `on`, NOT `off`/`plain`. PRD §11 + system_context §2 both attest
# default "on" for @livepicker-preview-defer. ("plain" is the tab-style default — do not
# confuse the two sibling features.) A wrong default here silently disables the §18
# deferred path (or forces it on against the user's `off`). Use "on".

# CRITICAL — CONTRACT LINE NUMBERS ARE STALE. The task contract cites "~line 82" for the
# livepicker.sh state init, but the live file has set_state STATE_LINKED_ID at line 157.
# state.sh's contract "line 49" for _STATE_RUNTIME_KEYS IS currently accurate, and the
# options.sh "after opt_tab_style()" anchor is accurate — but DO NOT edit by line number;
# anchor every edit on CONTENT. Verified live: `grep -n`.

# CRITICAL — these are RUNTIME keys, NOT ORIG_* saved-state. Add them to the runtime
# STATE_* block (after STATE_TAB_INACTIVE_TMPL) and to _STATE_RUNTIME_KEYS. Do NOT add
# them among the ORIG_SESSION/ORIG_WINDOW/... block — those are originals-to-restore
# (PRD §9); the seq/target are picker-internal, cleared on exit, not restored.

# CRITICAL — _STATE_RUNTIME_KEYS membership is MANDATORY (system_context §3 Q4; Q6 gotcha).
# clear_all_state iterates this space-list to `set-option -gu` each. A runtime key NOT
# listed (a) LEAKS across picker sessions and (b) lets a late -b preview job post-teardown
# match a stale seq and clobber the restored window. Append BOTH new keys.

# CRITICAL — init SEQ to "0" at activation (Edit C). Even though clear_all_state clears
# the seq on restore, the init is (a) the authoritative reset for the fresh activation,
# and (b) defense-in-depth if clear_all_state somehow didn't run. The monotonic counter
# must start at a known 0 so the first deferred fire (seq=1) compares correctly. Do NOT
# init STATE_PREVIEW_TARGET (contract inits only SEQ; TARGET starts unset/empty, read via
# get_state "$STATE_PREVIEW_TARGET" "").

# GOTCHA — opt_preview_defer is CONFIG (PRD §11 toggle); it is NEVER cleared by
# clear_all_state (CORRECTION A preserves §11 config). Only STATE_PREVIEW_SEQ/TARGET
# (runtime) are cleared. Do not add opt_preview_defer's @livepicker-preview-defer to
# _STATE_RUNTIME_KEYS.

# GOTCHA — shellcheck SC2034 (unused var) is ALREADY disabled file-wide in state.sh
# (every STATE_*/ORIG_* is an integration seam unused within the file). The two new
# constants are covered by that existing disable. Do NOT remove the disable directive.

# GOTCHA — options.sh column alignment is "best effort" (opt_suppress_window_hook uses 1
# space before `{`, others 2). Align opt_preview_defer's `{` near column 28 to match the
# block; exact column is cosmetic (shfmt NOT installed). The load-bearing constraint is
# the single-line shape + the exact `get_opt "@livepicker-preview-defer" "on"` substring
# for the cross-check grep.

# GOTCHA — Edit C in livepicker.sh runs INSIDE activate_main (a function), so sourcing
# livepicker.sh has NO new side effect (the set_state runs only when activate is invoked).
# Use ONE-TAB indent to match the surrounding set_state lines.

# GOTCHA — ORDER in state.sh: declare STATE_PREVIEW_SEQ/STATE_PREVIEW_TARGET (lines ~45-46)
# ABOVE the _STATE_RUNTIME_KEYS line (~49) so the `$STATE_PREVIEW_SEQ` expansion in the
# readonly line resolves. Same layout as the already-working STATE_TAB_* pair.

# GOTCHA — do NOT implement the seq guard (preview.sh, P1.M2.T2) or the fire helper
# (input-handler.sh, P1.M2.T3) in this subtask. This task only declares the seam. Scope
# creep risks merge friction with those siblings.

# STYLE — indent with TABS (whole codebase; shfmt absent). state.sh readonly consts and
# the _STATE_RUNTIME_KEYS line use NO leading indent (column 0); options.sh accessors use
# NO leading indent; the livepicker.sh set_state uses ONE-TAB indent (inside activate_main).
```

## Implementation Blueprint

### Data models and structure

No runtime data model. The "model" is two constant declarations + one accessor + one init:

```
@livepicker-preview-defer   (config, PRD §11)   → opt_preview_defer()   default "on"
@livepicker-preview-seq     (runtime)           → STATE_PREVIEW_SEQ     monotonic counter; init 0 at activate;
                                                                       bumped by fire helper (P1.M2.T3);
                                                                       re-checked by preview.sh (P1.M2.T2)
@livepicker-preview-target  (runtime)           → STATE_PREVIEW_TARGET  latest session/window token; written by
                                                                       fire helper; read/rechecked by preview.sh
```

Lifecycle (for context; this subtask implements only the boxed steps):
```
activate (Edit C):    set_state STATE_PREVIEW_SEQ "0"           # authoritative reset (alongside STATE_LINKED_ID init)
input type/nav (P1.M2.T3): seq=$(get_state SEQ 0); seq=$((seq+1)); set_state SEQ $seq;
                           set_state TARGET "$target";
                           tmux run-shell -b "$CURRENT_DIR/preview.sh '$target' '$seq'"
preview.sh (P1.M2.T2): my_seq="$2"; cur=$(get_state SEQ 0);
                       [ "$cur" != "$my_seq" ] && return 0      # supersede gate (no-op if a newer target won)
                       ... unlink/link/select ...
restore  (P1.M5):     clear_all_state → -gu each _STATE_RUNTIME_KEYS member (incl. SEQ + TARGET)
```

### Implementation Tasks (ordered by dependencies)

```yaml
Task 1: MODIFY scripts/options.sh — APPEND opt_preview_defer()
  - LOCATE: the accessor block; opt_tab_style (currently line 45) is LAST (T1.S1 landed).
  - ACTION: append one new line immediately after opt_tab_style.
  - EXACT LINE (column-0, matching the block's single-line shape; pad `{` near col 28):
      opt_preview_defer()        { get_opt "@livepicker-preview-defer" "on"; }      # bool on|off (PRD §18; on=defer preview to bg run-shell -b supersedeable job, off=legacy synchronous)
  - DEFAULT: "on" (PRD §11 + system_context §2). NOT "off", NOT "plain".
  - FOLLOW pattern: scripts/options.sh lines 26-45 (single-line { get_opt ...; } body).
  - DO NOT: reorder existing accessors, change get_opt, or add any other accessor.

Task 2: MODIFY scripts/state.sh — ADD two runtime constants + extend the clear-list
  - EDIT 2a: in the runtime STATE_* block, insert two readonly consts immediately
    AFTER the STATE_TAB_INACTIVE_TMPL line and BEFORE the blank line + "--- saved-state
    CONTRACT keys ---" comment header. (Anchor on content.) Add:
      readonly STATE_PREVIEW_SEQ="@livepicker-preview-seq"        # monotonic supersede counter (PRD §18; external_tmux_behavior.md Q6): bumped by the fire helper (P1.M2.T3), re-checked by preview.sh (P1.M2.T2) before mutating; init 0 at activate; cleared via _STATE_RUNTIME_KEYS
      readonly STATE_PREVIEW_TARGET="@livepicker-preview-target"  # latest session/window token (PRD §18): written by the fire helper (P1.M2.T3), read/rechecked by preview.sh (P1.M2.T2); cleared via _STATE_RUNTIME_KEYS
  - EDIT 2b: append both keys to _STATE_RUNTIME_KEYS. The current line reads:
      readonly _STATE_RUNTIME_KEYS="$STATE_MODE $STATE_LIST $STATE_FILTER $STATE_INDEX $STATE_LINKED_ID $STATE_TAB_CURRENT_TMPL $STATE_TAB_INACTIVE_TMPL"
    Change it to:
      readonly _STATE_RUNTIME_KEYS="$STATE_MODE $STATE_LIST $STATE_FILTER $STATE_INDEX $STATE_LINKED_ID $STATE_TAB_CURRENT_TMPL $STATE_TAB_INACTIVE_TMPL $STATE_PREVIEW_SEQ $STATE_PREVIEW_TARGET"
  - DO NOT: add these to the ORIG_* block; touch set_state/get_state/clear_all_state
    bodies; or remove the SC2034 file-wide disable (it covers the new consts).
  - NAMING: STATE_PREVIEW_SEQ / STATE_PREVIEW_TARGET (UPPER_SNAKE, matching STATE_MODE/...).
  - PLACEMENT: runtime block (after STATE_TAB_INACTIVE_TMPL), NOT the ORIG_* block.

Task 3: MODIFY scripts/livepicker.sh — INIT the seq to 0 at activation
  - LOCATE (by content, NOT line number): activate_main's picker-internal state-init
    block. The anchor is the pair:
        # Init the linked-preview id (no preview linked yet). preview.sh reads this
        # via get_state "$STATE_LINKED_ID" "" — empty means no prior link to unlink.
        set_state "$STATE_LINKED_ID" ""
    (currently at line 157; the contract's "~line 82" is STALE.)
  - ACTION: insert immediately AFTER `set_state "$STATE_LINKED_ID" ""` (1-tab indent):
        # Init the deferred-preview supersede counter (PRD §18 / external_tmux_behavior.md
        # Q6). Monotonic from 0; bumped by the fire helper (P1.M2.T3) and re-checked by
        # preview.sh (P1.M2.T2) so a late/superseded -b job is a no-op. clear_all_state
        # clears it on exit (via _STATE_RUNTIME_KEYS); this init is the authoritative
        # reset for the fresh session.
        set_state "$STATE_PREVIEW_SEQ" "0"
  - DO NOT: init STATE_PREVIEW_TARGET (contract inits only SEQ); touch any other
    activate_main logic; or move the existing STATE_LINKED_ID init.
  - WHY here: this is BEFORE the T2 list-build AND the first preview (line ~404) — the
    seq must be 0 before any deferred fire (which happens only on subsequent type/nav).

Task 4: VALIDATE (throwaway smoke via the existing socket-isolated harness)
  - RUN: bash -n scripts/options.sh scripts/state.sh scripts/livepicker.sh
  - RUN: shellcheck scripts/options.sh scripts/state.sh scripts/livepicker.sh
        (expect 0 NEW findings; SC2034 on the new consts is already covered file-wide)
  - RUN: grep cross-checks (see Validation Loop L1)
  - RUN: leak-prevention smoke (L2) against an isolated socket; then DELETE it.
  - RUN: tests/run.sh (expect full suite green — the additions are inert until
        P1.M2.T2/T3 consume them; no existing assertion can regress).
```

### Implementation Patterns & Key Details

**Exact edits (the implementer can paste these into the `edit` tool).**

*Task 1 — options.sh* (append after the last accessor):

```bash
# oldText (the current last accessor line):
opt_tab_style()            { get_opt "@livepicker-tab-style" "plain"; }       # enum: plain|window-status (PRD §17; plain=standalone fg/bg, window-status=reuse theme window-status-format)

# newText (same line + the new accessor):
opt_tab_style()            { get_opt "@livepicker-tab-style" "plain"; }       # enum: plain|window-status (PRD §17; plain=standalone fg/bg, window-status=reuse theme window-status-format)
opt_preview_defer()        { get_opt "@livepicker-preview-defer" "on"; }      # bool on|off (PRD §18; on=defer preview to bg run-shell -b supersedeable job, off=legacy synchronous)
```

*Task 2a — state.sh* (insert two consts between STATE_TAB_INACTIVE_TMPL and the ORIG block header):

```bash
# oldText (anchor: STATE_TAB_INACTIVE_TMPL line + blank + ORIG block header comment):
readonly STATE_TAB_INACTIVE_TMPL="@livepicker-tab-inactive-tmpl" # cached window-status-format         (PRD §17; written P1.M1.T2, read P1.M1.T3; cleared via _STATE_RUNTIME_KEYS)

# --- saved-state CONTRACT keys (PRD §9; written by activate, read by restore) ---

# newText (STATE_TAB_INACTIVE_TMPL + two new runtime consts + blank + ORIG header):
readonly STATE_TAB_INACTIVE_TMPL="@livepicker-tab-inactive-tmpl" # cached window-status-format         (PRD §17; written P1.M1.T2, read P1.M1.T3; cleared via _STATE_RUNTIME_KEYS)
readonly STATE_PREVIEW_SEQ="@livepicker-preview-seq"        # monotonic supersede counter (PRD §18; external_tmux_behavior.md Q6): bumped by the fire helper (P1.M2.T3), re-checked by preview.sh (P1.M2.T2) before mutating; init 0 at activate; cleared via _STATE_RUNTIME_KEYS
readonly STATE_PREVIEW_TARGET="@livepicker-preview-target"  # latest session/window token (PRD §18): written by the fire helper (P1.M2.T3), read/rechecked by preview.sh (P1.M2.T2); cleared via _STATE_RUNTIME_KEYS

# --- saved-state CONTRACT keys (PRD §9; written by activate, read by restore) ---
```

*Task 2b — state.sh* (extend the clear-list):

```bash
# oldText:
readonly _STATE_RUNTIME_KEYS="$STATE_MODE $STATE_LIST $STATE_FILTER $STATE_INDEX $STATE_LINKED_ID $STATE_TAB_CURRENT_TMPL $STATE_TAB_INACTIVE_TMPL"

# newText:
readonly _STATE_RUNTIME_KEYS="$STATE_MODE $STATE_LIST $STATE_FILTER $STATE_INDEX $STATE_LINKED_ID $STATE_TAB_CURRENT_TMPL $STATE_TAB_INACTIVE_TMPL $STATE_PREVIEW_SEQ $STATE_PREVIEW_TARGET"
```

*Task 3 — livepicker.sh* (init the seq, after the STATE_LINKED_ID init):

```bash
# oldText (the anchor — the linked-id init + its 2-line comment):
	# Init the linked-preview id (no preview linked yet). preview.sh reads this
	# via get_state "$STATE_LINKED_ID" "" — empty means no prior link to unlink.
	set_state "$STATE_LINKED_ID" ""

# newText (same + the seq init with its comment):
	# Init the linked-preview id (no preview linked yet). preview.sh reads this
	# via get_state "$STATE_LINKED_ID" "" — empty means no prior link to unlink.
	set_state "$STATE_LINKED_ID" ""
	# Init the deferred-preview supersede counter (PRD §18 / external_tmux_behavior.md
	# Q6). Monotonic from 0; bumped by the fire helper (P1.M2.T3) and re-checked by
	# preview.sh (P1.M2.T2) so a late/superseded -b job is a no-op. clear_all_state
	# clears it on exit (via _STATE_RUNTIME_KEYS); this init is the authoritative
	# reset for the fresh session.
	set_state "$STATE_PREVIEW_SEQ" "0"
```

**Downstream contract this foundation enables** (do NOT implement here — for P1.M2.T2/P1.M2.T3):

```bash
# P1.M2.T3 (input-handler.sh fire helper) — on preview-defer=on, bump seq + set target + bg fire:
#   _lp_fire_preview() {  # $1 = candidate session/window token
#       local seq; seq="$(get_state "$STATE_PREVIEW_SEQ" "0")"; seq=$(( seq + 1 ))
#       set_state "$STATE_PREVIEW_SEQ" "$seq"
#       set_state "$STATE_PREVIEW_TARGET" "$1"
#       tmux run-shell -b "$CURRENT_DIR/preview.sh '$1' '$seq'"
#   }
# (preview-defer=off keeps the legacy synchronous preview.sh call with one arg.)

# P1.M2.T2 (preview.sh seq guard) — re-check the seq immediately before mutating:
#   preview_main() {
#       local S="${1:-}" my_seq="${2:-}" cur_seq
#       ... cheap reads (mode/snapshot/self-session/fast-path) ...
#       cur_seq="$(get_state "$STATE_PREVIEW_SEQ" "0")"
#       [ "$cur_seq" != "$my_seq" ] && return 0   # superseded -> no-op (never clobber)
#       ... unlink-previous / link-window -a / select-window ...
#   }
```

### Integration Points

```yaml
CODE:
  - file: scripts/options.sh
    change: "+1 accessor opt_preview_defer() (default 'on')"
  - file: scripts/state.sh
    change: "+2 readonly STATE_PREVIEW_* runtime consts; +2 members in _STATE_RUNTIME_KEYS"
    invariant: "clear_all_state unsets both new keys (no leak; no late-job stale-seq match)"
  - file: scripts/livepicker.sh
    change: "+1 set_state STATE_PREVIEW_SEQ '0' in activate_main (after STATE_LINKED_ID init)"
    invariant: "@livepicker-preview-seq == '0' immediately after activation"

CONSUMERS (later subtasks — DO NOT implement now):
  - P1.M2.T2.S1 (preview.sh): READS STATE_PREVIEW_SEQ (supersede guard) + STATE_PREVIEW_TARGET.
  - P1.M2.T3.S1 (input-handler.sh): BUMPS STATE_PREVIEW_SEQ + WRITES STATE_PREVIEW_TARGET (the fire helper).
  - P1.M5 restore / clear_all_state: clears both (automatic once listed in _STATE_RUNTIME_KEYS).

CONFIG / DATABASE / ROUTES: none.
```

## Validation Loop

### Level 1: Syntax & Style (Immediate Feedback)

```bash
cd /home/dustin/.config/tmux/plugins/tmux-livepicker
bash -n scripts/options.sh scripts/state.sh scripts/livepicker.sh && echo "OK: syntax"
shellcheck scripts/options.sh scripts/state.sh scripts/livepicker.sh
# Cross-checks (load-bearing — these ARE the contract):
grep -c 'get_opt "@livepicker-preview-defer" "on"' scripts/options.sh            # -> 1  (default correct, single-line)
grep -c 'get_opt "@livepicker-preview-defer" "off"' scripts/options.sh           # -> 0  (wrong default NOT present)
grep -n 'STATE_PREVIEW_SEQ="@livepicker-preview-seq"' scripts/state.sh           # -> 1 match
grep -n 'STATE_PREVIEW_TARGET="@livepicker-preview-target"' scripts/state.sh     # -> 1 match
# _STATE_RUNTIME_KEYS now references BOTH new consts:
grep '_STATE_RUNTIME_KEYS=' scripts/state.sh | grep -q 'STATE_PREVIEW_SEQ'    && echo "OK: seq in list" || echo "FAIL"
grep '_STATE_RUNTIME_KEYS=' scripts/state.sh | grep -q 'STATE_PREVIEW_TARGET' && echo "OK: target in list" || echo "FAIL"
# New consts are in the RUNTIME block, NOT the ORIG_* block:
awk '/STATE_PREVIEW_/{print NR": "$0}' scripts/state.sh   # line numbers should precede the first ORIG_* line
# livepicker.sh seq init present (anchored on the STATE_LINKED_ID init):
grep -A1 'set_state "\$STATE_LINKED_ID" ""' scripts/livepicker.sh | grep -q 'STATE_PREVIEW_SEQ' \
  && echo "OK: seq init follows STATE_LINKED_ID init" || echo "FAIL"
# Expected: all green; the "off" default grep is 0.
```

### Level 2: Leak-prevention + init smoke (via the existing socket-isolated harness)

This subtask adds no committed test file (feature tests land in P1.M3.T1
`test_responsiveness.sh`). Run a throwaway smoke, then delete it. It reuses
`tests/setup_socket.sh` (PATH shim → bare `tmux` hits an isolated `-L` socket) +
`tests/helpers.sh` (assert_eq/fail/pass/setup_test/teardown_test):

```bash
cat > /tmp/smoke_previewkeys.sh <<'EOF'
#!/usr/bin/env bash
set -u
cd /home/dustin/.config/tmux/plugins/tmux-livepicker
source tests/setup_socket.sh
source tests/helpers.sh
setup_test "lp-smoke-previewkeys"
# state.sh depends on utils.sh (tmux_*); source order matters.
source scripts/utils.sh
source scripts/options.sh
source scripts/state.sh

pass_n=0; fail_n=0
ck() { if [ "$2" = "$3" ]; then pass_n=$((pass_n+1)); else fail_n=$((fail_n+1)); echo "FAIL $1: got[$2] want[$3]"; fi; }

# 1. accessor default (PRD §11 + system_context §2)
ck "opt_preview_defer default" "$(opt_preview_defer)" "on"
# 2. accessor surfaces a user override
tmux set-option -g @livepicker-preview-defer off
ck "opt_preview_defer override" "$(opt_preview_defer)" "off"
tmux set-option -gu @livepicker-preview-defer
# 3. constants resolve to the right @-names
ck "seq name"    "$STATE_PREVIEW_SEQ"    "@livepicker-preview-seq"
ck "target name" "$STATE_PREVIEW_TARGET" "@livepicker-preview-target"
# 4. both are members of _STATE_RUNTIME_KEYS
case " $_STATE_RUNTIME_KEYS " in *" $STATE_PREVIEW_SEQ "*)    ;; *) fail_n=$((fail_n+1)); echo "FAIL: seq not in runtime-keys";; esac
case " $_STATE_RUNTIME_KEYS " in *" $STATE_PREVIEW_TARGET "*) ;; *) fail_n=$((fail_n+1)); echo "FAIL: target not in runtime-keys";; esac
# 5. LEAK PREVENTION: set_state then clear_all_state -> both unset (tmux_is_set rc=1)
set_state "$STATE_PREVIEW_SEQ" "42"
set_state "$STATE_PREVIEW_TARGET" "blog"
clear_all_state
if tmux_is_set "$STATE_PREVIEW_SEQ";    then fail_n=$((fail_n+1)); echo "FAIL LEAK: seq survived clear_all_state";    else pass_n=$((pass_n+1)); fi
if tmux_is_set "$STATE_PREVIEW_TARGET"; then fail_n=$((fail_n+1)); echo "FAIL LEAK: target survived clear_all_state"; else pass_n=$((pass_n+1)); fi

teardown_test
echo "pass=$pass_n fail=$fail_n"
[ "$fail_n" -eq 0 ]
EOF
bash /tmp/smoke_previewkeys.sh; rc=$?
rm -f /tmp/smoke_previewkeys.sh
exit $rc
# Expected: pass=7 fail=0, exit 0. The two LEAK assertions are the critical ones —
# they FAIL if you forget Edit 2b (appending to _STATE_RUNTIME_KEYS).
```

### Level 3: Activation init proof (seq == "0" after activate)

```bash
cat > /tmp/smoke_seqinit.sh <<'EOF'
#!/usr/bin/env bash
set -u
cd /home/dustin/.config/tmux/plugins/tmux-livepicker
source tests/setup_socket.sh
source tests/helpers.sh
setup_test "lp-smoke-seqinit"
attach_test_client   # activate needs an attached client (display-message/switch-client)
# Before activate: SEQ is unset (or whatever). After activate_main: it MUST be "0".
"$LIVEPICKER_SCRIPTS/livepicker.sh"
seq="$(tmux show-option -gqv @livepicker-preview-seq 2>/dev/null)"
[ "$seq" = "0" ] && echo "OK: seq initialized to 0 at activation" || echo "FAIL: seq=[$seq] want[0]"
# Cancel to tear down cleanly (clear_all_state should then UNSET it).
"$LIVEPICKER_SCRIPTS/input-handler.sh" cancel >/dev/null 2>&1 || true
if tmux show-option -gqv @livepicker-preview-seq 2>/dev/null | grep -q .; then
    echo "FAIL: seq survived cancel (clear_all_state leak)"
else
    echo "OK: seq cleared by cancel/clear_all_state"
fi
teardown_test
EOF
bash /tmp/smoke_seqinit.sh; rc=$?
rm -f /tmp/smoke_seqinit.sh
exit $rc
# Expected: both OK. Proves Edit C (init to 0) AND Edit 2b (clear on exit) end-to-end
# through the REAL activate/cancel flow. (If attach_test_client or activate is flaky in
# the harness, the L2 smoke already proves the unit-level contract; this is the
# integration confirmation.)
```

### Level 4: Cross-check against PRD §11 (defense against a wrong default)

```bash
# Every @livepicker-* option should appear exactly once with its PRD default.
grep -oE 'get_opt "@livepicker-[a-z-]+" "[^"]*"' scripts/options.sh | sort | uniq -c | sort -rn | head
# Expected: each option count == 1; the preview-defer line reads
#   1 get_opt "@livepicker-preview-defer" "on"
# If you see "off" here, or any count > 1, fix before finishing.
```

### Level 5: No regression (full suite)

```bash
cd /home/dustin/.config/tmux/plugins/tmux-livepicker
tests/run.sh
# Expected: exit 0, all existing tests green. The additions are inert until P1.M2.T2/T3
# consume them (no code reads STATE_PREVIEW_* yet, and opt_preview_defer() is defined but
# uncalled), so no existing assertion can regress.
```

## Final Validation Checklist

### Technical Validation

- [ ] `bash -n scripts/options.sh scripts/state.sh scripts/livepicker.sh` clean.
- [ ] `shellcheck` on all three: 0 NEW findings (SC2034 on new consts already covered).
- [ ] L1 grep cross-checks all green; `get_opt "@livepicker-preview-defer" "off"` → 0.
- [ ] L2 leak-prevention smoke: pass=7 fail=0 (the two clear_all_state LEAK asserts pass).
- [ ] L3 activation init: `@livepicker-preview-seq == "0"` after activate; cleared after cancel.

### Feature Validation

- [ ] `opt_preview_defer` returns `"on"` (unset) and `"off"` (override).
- [ ] Both `STATE_PREVIEW_*` constants resolve to the correct `@livepicker-*` names.
- [ ] Both are in `_STATE_RUNTIME_KEYS` → `clear_all_state` unsets them (no leak).
- [ ] `@livepicker-preview-seq` is `"0"` immediately after `activate_main` (Edit C).
- [ ] Sourcing all three files has no side effects.

### Code Quality Validation

- [ ] `opt_preview_defer` follows the single-line `{ get_opt ...; } # comment` pattern.
- [ ] New constants are in the RUNTIME block (after STATE_TAB_INACTIVE_TMPL), NOT ORIG_*.
- [ ] Naming matches conventions (`opt_<suffix>`; `STATE_UPPER_SNAKE`).
- [ ] Edit C anchored on CONTENT (`set_state "$STATE_LINKED_ID" ""`), not the stale line number.
- [ ] No scope creep: seq guard (P1.M2.T2) + fire helper (P1.M2.T3) NOT implemented here.
- [ ] No other logic changed (set_state/get_state/clear_all_state bodies untouched).

### Documentation & Deployment

- [ ] No user-facing/config/API surface change beyond the option row (README config table
      is synced in the Mode-B docs task P1.M3.T3.S1 — do NOT edit README here).
- [ ] Inline comments on the new lines cross-reference PRD §18 + Q6 + the consumer
      sibling subtasks (P1.M2.T2/T3) so the integration seam is self-documenting.

---

## Anti-Patterns to Avoid

- ❌ Don't use `"off"` (or `"plain"`) as the default — PRD §11 + system_context §2 both
  say `"on"`. (`"plain"` is the tab-style default — a different sibling feature.)
- ❌ Don't edit by line number — the contract's "~line 82" for livepicker.sh is stale
  (actual: line 157). Anchor edits on content (the `set_state "$STATE_LINKED_ID" ""` line,
  the STATE_TAB_INACTIVE_TMPL line, the `_STATE_RUNTIME_KEYS=` line).
- ❌ Don't add the new constants to the `ORIG_*` saved-state block — they are RUNTIME
  (cleared on exit), not originals-to-restore (PRD §9).
- ❌ Don't forget Edit 2b (appending to `_STATE_RUNTIME_KEYS`) — that is the whole
  leak-prevention + late-job-supersede-safety point (Q4 + Q6); without it a late `-b`
  preview post-teardown could clobber the restored window.
- ❌ Don't init `STATE_PREVIEW_TARGET` at activation — the contract initializes ONLY the
  SEQ (to "0"). TARGET starts unset/empty, read via `get_state "$STATE_PREVIEW_TARGET" ""`.
- ❌ Don't add `@livepicker-preview-defer` to `_STATE_RUNTIME_KEYS` — it is CONFIG
  (opt_preview_defer); clear_all_state preserves §11 config (CORRECTION A). Only the two
  STATE_PREVIEW_* runtime keys are cleared.
- ❌ Don't implement the seq guard (preview.sh) or the fire helper (input-handler.sh) —
  those are P1.M2.T2 / P1.M2.T3. This task only declares the seam.
- ❌ Don't change `get_opt`/`set_state`/`get_state`/`clear_all_state` bodies.
- ❌ Don't commit a `tests/` file for this subtask — feature tests are P1.M3.T1
  (`test_responsiveness.sh`); validate via the throwaway L2/L3 smokes only.
- ❌ Don't reorder/reformat the existing accessors — append only (the tab-style accessor
  is the last; preview-defer appends right after it).

---

## Confidence Score

**10 / 10** for one-pass success. Rationale: three trivial, fully-specified edits (the
exact oldText/newText are given verbatim, anchored on content so stale line numbers can't
mislead); this is the **exact analog of the already-COMPLETE P1.M1.T1.S1** (tab-style),
which used the identical edit pattern and landed cleanly — so the pattern is proven in
this very codebase. The only real trap — a wrong default — is doubly attested (`"on"` by
PRD §11 AND system_context §2) and caught by the L4 grep. The leak-prevention +
activation-init requirements are proven by executable L2/L3 smokes against the existing
isolated-socket harness. The additions are inert until P1.M2.T2/T3 consume them, so
`tests/run.sh` stays green by construction. Fully disjoint from the in-flight parallel
P1.M1.T3.S1 (renderer.sh-only). `shellcheck`/`bash -n` are verified-present. No ambiguity
remains.
