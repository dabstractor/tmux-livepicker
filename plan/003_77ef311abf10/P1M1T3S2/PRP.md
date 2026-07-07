# PRP — P1.M1.T3.S2: Add STATE_SCROLL, STATE_CLIENT_WIDTH, ORIG_CLIENT_RESIZED_HOOK + clear-list

---

## Goal

**Feature Goal**: Define the 3 new saved-state/runtime CONTRACT constants in
`scripts/state.sh` that the §19 viewport + §10 client-width-cache features need, and wire
the 2 new runtime keys into the mandatory clear-list so `clear_all_state` tears them down on
exit. These are the integration seams P1.M3.T1 (client-width capture + `client-resized` hook)
and P1.M3.T2 (scroll-into-view) will read/write — landing them now (definitions only, no
initialization) unblocks both without coupling to their implementation.

**Deliverable**: 3 new `readonly` constants in `scripts/state.sh` + the 2 new runtime keys
appended to `_STATE_RUNTIME_KEYS`. **No new files. No behavior change** (the constants are
unused until P1.M3.T1 wires them; `state.sh` is a no-side-effect sourced library).

**Success Definition**:
- The 3 constants resolve to `@livepicker-scroll`, `@livepicker-client-width`, and
  `@livepicker-orig-client-resized` respectively (verified live).
- `_STATE_RUNTIME_KEYS` expands to **11** keys (was 9), containing both new runtime keys.
- `clear_all_state` tears down all 3 new keys (the 2 runtime via the list; the ORIG key via
  the `@livepicker-orig-` grep) AND still clears the original runtime keys.
- **CORRECTION A holds**: §11 config (`@livepicker-fg`, …) and the `@livepicker-type`
  config-mirror are PRESERVED (not cleared).
- `bash -n` + `shellcheck` clean (0 NEW findings); the 44-test `tests/run.sh` suite stays
  green (the constants are unused until P1.M3, so no existing test is affected).

## User Persona (if applicable)

**Target User**: Downstream scripts — `renderer.sh` (P1.M2, reads `STATE_CLIENT_WIDTH` to
measure the viewport + `STATE_SCROLL` to slice the visible window), `input-handler.sh`
(P1.M3.T2, writes `STATE_SCROLL` on scroll-into-view/reset), and `livepicker.sh`/`restore.sh`
(P1.M3.T1, capture `STATE_CLIENT_WIDTH` + save/restore the `client-resized` hook into
`ORIG_CLIENT_RESIZED_HOOK`).

**Use Case**: At activate, P1.M3.T1 will `set_state "$STATE_CLIENT_WIDTH" "$(… client_width …)"`
and install the `client-resized` hook whose save goes to `ORIG_CLIENT_RESIZED_HOOK`. On each
redraw the renderer reads `get_state "$STATE_CLIENT_WIDTH"` + `get_state "$STATE_SCROLL"` with
no per-keystroke tmux round-trip. On exit, `clear_all_state` unsets both runtime keys (via the
list) and the saved hook (via the grep), leaving the server pristine.

**Pain Points Addressed**: Centralizes the 3 new key names as `readonly` constants (one
source of truth, no string typos across the renderer/input-handler/restore trio) and makes
the teardown automatic — adding a runtime key without appending it to
`_STATE_RUNTIME_KEYS` is the classic leak (the key survives across picker sessions, per the
`state.sh` header comment). This PRP makes that append MANDATORY and proves it.

---

## Why

- **Integration seam for §19 + §10.** The renderer rework (P1.M2) and the client-width +
  scroll wiring (P1.M3) need stable, named key constants before they're written. Defining
  them now (as pure constants) unblocks both without touching their logic.
- **The clear-list is the load-bearing part.** `clear_all_state` unsets EXACTLY the keys in
`_STATE_RUNTIME_KEYS` (plus the `@livepicker-orig-` grep). A new runtime key that is NOT
appended to the list is a silent leak across picker sessions (`codebase_patterns.md §P3`;
`state.sh` header: *"else they leak across picker sessions"*). The ORIG key needs NO list
entry (the grep catches it) — the contract is precise about which goes where.
- **Matches the established, battle-tested pattern.** Every existing `@livepicker-*` key is a
  `readonly STATE_X`/`ORIG_X` constant; the runtime ones are enumerated in the clear-list.
  These 3 follow the pattern exactly, so the no-side-effects contract + the 44-green suite
  hold by construction.

## What

Three `readonly` constant definitions + one list update in `scripts/state.sh`:

| constant | value | block | cleared by |
|---|---|---|---|
| `STATE_SCROLL` | `@livepicker-scroll` | runtime STATE_* block (tail) | `_STATE_RUNTIME_KEYS` list |
| `STATE_CLIENT_WIDTH` | `@livepicker-client-width` | runtime STATE_* block (tail) | `_STATE_RUNTIME_KEYS` list |
| `ORIG_CLIENT_RESIZED_HOOK` | `@livepicker-orig-client-resized` | saved-state ORIG_* block (after `ORIG_HOOK`) | `grep '@livepicker-orig-'` (auto) |

`STATE_SCROLL` + `STATE_CLIENT_WIDTH` are APPENDED to `_STATE_RUNTIME_KEYS` (the MANDATORY
clear-list). `ORIG_CLIENT_RESIZED_HOOK` is NOT added to the list (ORIG_* keys are
grep-cleared, never list-cleared — the file's convention). No values are initialized here
(activation does that in P1.M3.T1).

### Success Criteria

- [ ] `STATE_SCROLL="@livepicker-scroll"` and `STATE_CLIENT_WIDTH="@livepicker-client-width"`
      present at the tail of the runtime readonly block.
- [ ] `ORIG_CLIENT_RESIZED_HOOK="@livepicker-orig-client-resized"` present in the ORIG_* block.
- [ ] Both new runtime keys APPENDED to `_STATE_RUNTIME_KEYS` (list now expands to 11 keys).
- [ ] `ORIG_CLIENT_RESIZED_HOOK` is NOT in `_STATE_RUNTIME_KEYS` (grep-cleared only).
- [ ] No existing constant or function changed; no value initialized; no new sourcing/driver.
- [ ] `bash -n` + `shellcheck` clean; `tests/run.sh` green (44 tests).

## All Needed Context

### Context Completeness Check

_Pass_: The implementer needs (a) the 3 verbatim edits (oldText→newText in Implementation
Patterns), (b) the one load-bearing rule (runtime keys → list; ORIG key → grep, NOT the
list), and (c) the validation commands. Every behavior is verified live on a temp copy.

### Documentation & References

```yaml
# MUST READ — the empirical ground-truth (PROVES the edit + the clear-list contract)
- docfile: plan/003_77ef311abf10/P1M1T3S2/research/state_keys_findings.md
  why: PROVES the edit end-to-end on an isolated temp copy of the plugin. FINDING 1 (the 3
       constants resolve); FINDING 2 (_STATE_RUNTIME_KEYS -> 11 keys, both new keys present);
       FINDING 3 (clear_all_state tears down all 3 + preserves @livepicker-type/@livepicker-fg
       — CORRECTION A holds); FINDING 4 (zero behavior change; 44-green by construction);
       FINDING 5 (placement rationale); FINDING 6 (shellcheck SC2034 is file-wide disabled ->
       0 new findings); FINDING 7 (no parallel conflict with P1.M1.T3.S1 — different file).
  critical: Read BEFORE editing. The ORIG key is grep-cleared (NOT list-cleared) — do NOT add
            it to _STATE_RUNTIME_KEYS. The 2 runtime keys MUST be appended to the list or they
            leak across picker sessions.

# MUST READ — the file being edited (exact pattern + the 3 anchor lines)
- file: scripts/state.sh
  why: The runtime STATE_* block (10 keys; STATE_TYPE is a config mirror deliberately ABSENT
        from the clear-list), the saved-state ORIG_* block (9 keys), _STATE_RUNTIME_KEYS (9
        entries), and clear_all_state (iterates the list, then greps @livepicker-orig-). The 3
        UNIQUE anchor lines for the edits are STATE_PREVIEW_TARGET (runtime tail), ORIG_HOOK
        (the session-window-changed hook — co-locate the client-resized mirror after it), and
        the _STATE_RUNTIME_KEYS line. set -u; NO set -e.
  pattern: `readonly STATE_X="@livepicker-x"  # inline comment`; runtime keys echoed in
           _STATE_RUNTIME_KEYS; ORIG_* keys are NOT in the list (grep-cleared).
  gotcha: the header carries a file-wide `# shellcheck disable=SC2034` (every STATE_*/ORIG_*
          constant is an externally-consumed seam, intentionally unused in-file) — adding 3
          more of the same kind adds 0 new findings. Do NOT re-assert SC2034 per-line.

# MUST READ — the codebase conventions (the state contract + the hook-mirror rule)
- docfile: plan/003_77ef311abf10/architecture/codebase_patterns.md
  why: §P3 (state contract: "readonly STATE_X ... then appended to _STATE_RUNTIME_KEYS
        (MANDATORY clear-list)"; lists the 3 keys to add verbatim; "New keys in
        _STATE_RUNTIME_KEYS get torn down automatically; new ORIG_* keys get caught by the
        @livepicker-orig- grep"). §P4 (hook save/restore: client-resized is the IDENTICAL-shape
        mirror of session-window-changed -> co-locate ORIG_CLIENT_RESIZED_HOOK with ORIG_HOOK).
  section: "P3 — State contract (state.sh)", "P4 — Hook save/restore (the only correct way)"

# MUST READ — the empirical tmux behavior these keys encode (the §10/§19 cache + hook)
- docfile: plan/003_77ef311abf10/architecture/empirical_findings.md
  why: Finding 4 (display-message -p '#{client_width}' returns the width; client-resized hook
        installs via set-hook -g and shows as client-resized[0]; save/restore mirrors
        session-window-changed via tmux_get_hook verbatim -> replay incl. -b). This is WHY the
        3 constants exist; the wiring is P1.M3.T1 (NOT this task).
  section: "Finding 4 — client_width, status-justify, window-status-separator, client-resized hook"

# MUST READ — PRD §9 (restore clears the new runtime keys) + §10/§19 (what the keys mean)
- docfile: PRD.md  (repo root)
  why: §9 step 6 — "Clear every @livepicker-* option (this MUST include the new runtime keys
        @livepicker-scroll and @livepicker-client-width — add them to _STATE_RUNTIME_KEYS in
        state.sh)". §10 step 5 — capture client_width + install/save the client-resized hook.
        §19 §3.32/§3.35 — scroll offset + width source. These define the names + the teardown
        requirement this PRP implements.
  section: "§9 State saved and restored" (step 4 + 6), "§10 Status-line setup" (step 5),
           "§19 Status-line layout" (§3.32 viewport/scroll, §3.35 width source)

# CONTEXT — the parallel sibling (confirms no conflict)
- docfile: plan/003_77ef311abf10/P1M1T3S1/PRP.md
  why: P1.M1.T3.S1 edits scripts/options.sh + README.md (5 opt_* accessors + 5 config rows).
        It does NOT touch scripts/state.sh. Disjoint files -> no merge conflict; state.sh and
        options.sh are sibling sourced libs with disjoint namespaces (STATE_*/ORIG_* vs opt_*).
```

### Current Codebase tree

```bash
tmux-livepicker/
  scripts/
    state.sh     # MODIFY: +3 readonly constants (2 runtime, 1 ORIG); +2 entries in _STATE_RUNTIME_KEYS
    options.sh   # (P1.M1.T3.S1, IN PARALLEL) — does NOT touch state.sh
    rank.sh      # (P1.M1.T1, COMPLETE) — unchanged
    layout.sh    # (P1.M1.T2, COMPLETE) — unchanged; will READ STATE_SCROLL/STATE_CLIENT_WIDTH later via renderer/input-handler
    ... (utils/filter/livepicker/input-handler/preview/renderer/restore)  # UNCHANGED
  tests/         # UNCHANGED (these constants are unused until P1.M3; no test touches them)
```

### Desired Codebase tree with files to be added and responsibility of file

```bash
scripts/state.sh   # +STATE_SCROLL, +STATE_CLIENT_WIDTH (runtime; cleared via the list);
                    # +ORIG_CLIENT_RESIZED_HOOK (saved-state; cleared via the grep);
                    # +2 entries appended to _STATE_RUNTIME_KEYS. Definitions only — no init.
```

### Known Gotchas of our codebase & Library Quirks

```bash
# CRITICAL — the clear-list is MANDATORY for RUNTIME keys, and ONLY runtime keys go in it.
# _STATE_RUNTIME_KEYS is the space-list clear_all_state iterates (`for k in $_STATE_RUNTIME_KEYS`).
# A new runtime key NOT appended to it is a SILENT LEAK across picker sessions (state.sh header:
# "else they leak across picker sessions"). So STATE_SCROLL + STATE_CLIENT_WIDTH MUST be appended.
# Conversely, ORIG_* keys are cleared by the `grep '@livepicker-orig-'` branch — they MUST NOT be
# in _STATE_RUNTIME_KEYS (no existing ORIG_* key is; adding one would be redundant + inconsistent).
# Research FINDING 3 proves both mechanisms fire correctly with this split.

# CRITICAL — ORIG_CLIENT_RESIZED_HOOK is cleared by the GREP, not the list. Do NOT add it to
# _STATE_RUNTIME_KEYS. clear_all_state's second loop runs `show-options -g | grep '@livepicker-'`
# narrowed to '@livepicker-orig-', which catches @livepicker-orig-client-resized automatically
# (FINDING 3). Adding it to the list would not break anything, but it violates the convention
# (ORIG_* keys are grep-cleared) and misleads future readers.

# CRITICAL — do NOT initialize any value here. This task DEFINES the constants only. Activation
# (P1.M3.T1) captures STATE_CLIENT_WIDTH + installs the client-resized hook (saved to
# ORIG_CLIENT_RESIZED_HOOK); input-handler (P1.M3.T2) writes STATE_SCROLL. Defining a constant
# with a value (`readonly STATE_SCROLL="@livepicker-scroll"` is the NAME->OPTION mapping, NOT a
# runtime value) is correct; do NOT add `set_state "$STATE_SCROLL" 0` or any tmux call — state.sh
# is a no-side-effect sourced library (P1 in codebase_patterns.md).

# GOTCHA — placement: keep _STATE_RUNTIME_KEYS' list order parallel to the runtime-block
# definition order (the file's existing convention). Append STATE_SCROLL + STATE_CLIENT_WIDTH
# at the TAIL of BOTH the readonly block (after STATE_PREVIEW_TARGET) and the list. Place
# ORIG_CLIENT_RESIZED_HOOK immediately AFTER ORIG_HOOK (the session-window-changed hook): §P4
# says client-resized is its IDENTICAL-shape mirror, so co-locating the two ORIG_* hook keys
# documents that relationship. (Any ORIG_* position is functionally fine — the grep is
# order-independent — but the hook-pair grouping is the most readable.)

# GOTCHA — shellcheck SC2034 is FILE-WIDE disabled (state.sh header). Every STATE_*/ORIG_*
# constant is an externally-consumed seam (intentionally unused in-file); the 3 new ones are the
# same kind, so they inherit the suppression — 0 NEW findings. Do NOT add a per-line disable or
# "use" the constants to silence anything.

# GOTCHA — `set -u` is active (state.sh header). The readonly definitions reference only string
# literals (no unset var) — safe. _STATE_RUNTIME_KEYS references $STATE_SCROLL / $STATE_CLIENT_WIDTH,
# which are defined ABOVE it (the runtime block precedes the list), so the expansion is set-u-safe.
# Keep the runtime-block definitions ABOVE the _STATE_RUNTIME_KEYS line (do not reorder).

# GOTCHA — alignment of the inline `#` comments is COSMETIC (bash-irrelevant); the existing
# constants' comment columns are not perfectly uniform anyway. Align the 2 new STATE_ lines with
# each other (pad STATE_SCROLL's shorter value so the # lines up with STATE_CLIENT_WIDTH's); the
# ORIG line can reuse ORIG_HOOK's column. Do NOT realign existing lines.
```

## Implementation Blueprint

### Data models and structure

No data model — only 3 `readonly` constant definitions + 2 appended list tokens. The "model"
is the clear-list contract: runtime keys (STATE_*) → enumerated in `_STATE_RUNTIME_KEYS`;
saved-state keys (ORIG_*) → grep-caught. The 3 new keys (verbatim, with their inline
purpose comments):

```bash
readonly STATE_SCROLL="@livepicker-scroll"            # viewport scroll offset (PRD §19 §3.32): written by input-handler scroll-into-view/reset (P1.M3.T2); read by the renderer viewport slice; init 0 at activate (P1.M3.T1); cleared via _STATE_RUNTIME_KEYS
readonly STATE_CLIENT_WIDTH="@livepicker-client-width"  # invoking-client width cache (PRD §10 §3.35): captured at activate (P1.M3.T1) via display-message -p '#{client_width}', refreshed by the client-resized hook; the renderer measures the viewport against this (no per-keystroke tmux round-trip, §18); cleared via _STATE_RUNTIME_KEYS
readonly ORIG_CLIENT_RESIZED_HOOK="@livepicker-orig-client-resized"        # FULL show-hooks output (the IDENTICAL-shape mirror of ORIG_HOOK; §P4); saved/restored by activate/restore (P1.M3.T1); auto-cleared by clear_all_state's grep '@livepicker-orig-'
```

### Implementation Tasks (ordered by dependencies)

```yaml
Task 1: MODIFY scripts/state.sh — append the 2 runtime constants
  - LOCATE (by content): the STATE_PREVIEW_TARGET line (the LAST runtime key):
        readonly STATE_PREVIEW_TARGET="@livepicker-preview-target"  # latest session/window token (PRD §18): ...cleared via _STATE_RUNTIME_KEYS
  - INSERT the 2 new lines (STATE_SCROLL, STATE_CLIENT_WIDTH) IMMEDIATELY AFTER it, BEFORE the
    blank line that separates the runtime block from the saved-state block. Verbatim from
    Implementation Patterns.
  - NAMING: STATE_<UPPER> (matches every existing runtime key).
  - PRESERVE: every other runtime constant byte-identical; do NOT reorder (the runtime block
    MUST stay above _STATE_RUNTIME_KEYS so its $STATE_* expansion is set-u-safe).

Task 2: MODIFY scripts/state.sh — add ORIG_CLIENT_RESIZED_HOOK after ORIG_HOOK
  - LOCATE (by content): the ORIG_HOOK line:
        readonly ORIG_HOOK="@livepicker-orig-session-window-changed"           # FULL show-hooks output (multi-line)
  - INSERT ORIG_CLIENT_RESIZED_HOOK IMMEDIATELY AFTER it (verbatim from Implementation
    Patterns). Co-locating the two hook keys documents the §P4 mirror relationship.
  - PRESERVE: every other ORIG_* constant byte-identical.

Task 3: MODIFY scripts/state.sh — append the 2 runtime keys to _STATE_RUNTIME_KEYS (MANDATORY)
  - LOCATE (by content): the _STATE_RUNTIME_KEYS line:
        readonly _STATE_RUNTIME_KEYS="$STATE_MODE $STATE_LIST $STATE_FILTER $STATE_INDEX $STATE_LINKED_ID $STATE_TAB_CURRENT_TMPL $STATE_TAB_INACTIVE_TMPL $STATE_PREVIEW_SEQ $STATE_PREVIEW_TARGET"
  - APPEND ` $STATE_SCROLL $STATE_CLIENT_WIDTH` INSIDE the closing quote (verbatim from
    Implementation Patterns). The list now expands to 11 keys.
  - CRITICAL: do NOT add $ORIG_CLIENT_RESIZED_HOOK here (ORIG_* keys are grep-cleared).
  - PRESERVE: the leading `readonly _STATE_RUNTIME_KEYS="` and the closing `"`; the existing
    9 tokens unchanged.

Task 4: VALIDATE (syntax + clear-list smoke + full suite)
  - RUN: bash -n scripts/state.sh
  - RUN: shellcheck scripts/state.sh (expect 0 NEW findings — SC2034 is file-wide disabled)
  - RUN: the throwaway smoke (Validation Loop L2) — sources utils.sh+state.sh on an isolated
    socket, asserts the 3 constants resolve, _STATE_RUNTIME_KEYS -> 11 keys, clear_all_state
    tears down all 3 new keys + preserves @livepicker-type/@livepicker-fg (CORRECTION A).
    DELETE the smoke after.
  - RUN: tests/run.sh (expect: 44 tests green — the constants are unused until P1.M3, so no
    existing test can regress).
```

### Implementation Patterns & Key Details

**The 3 edits (apply with the `edit` tool — each oldText is unique in the file).**

**Edit 1 — append the 2 runtime constants (after STATE_PREVIEW_TARGET):**

```bash
# oldText (the unique runtime-tail line — anchor):
readonly STATE_PREVIEW_TARGET="@livepicker-preview-target"  # latest session/window token (PRD §18): written by the fire helper (P1.M2.T3), read/rechecked by preview.sh (P1.M2.T2); cleared via _STATE_RUNTIME_KEYS
# newText (same line + the 2 new runtime constants):
readonly STATE_PREVIEW_TARGET="@livepicker-preview-target"  # latest session/window token (PRD §18): written by the fire helper (P1.M2.T3), read/rechecked by preview.sh (P1.M2.T2); cleared via _STATE_RUNTIME_KEYS
readonly STATE_SCROLL="@livepicker-scroll"            # viewport scroll offset (PRD §19 §3.32): written by input-handler scroll-into-view/reset (P1.M3.T2); read by the renderer viewport slice; init 0 at activate (P1.M3.T1); cleared via _STATE_RUNTIME_KEYS
readonly STATE_CLIENT_WIDTH="@livepicker-client-width"  # invoking-client width cache (PRD §10 §3.35): captured at activate (P1.M3.T1) via display-message -p '#{client_width}', refreshed by the client-resized hook; the renderer measures the viewport against this (no per-keystroke tmux round-trip, §18); cleared via _STATE_RUNTIME_KEYS
```

**Edit 2 — add ORIG_CLIENT_RESIZED_HOOK (after ORIG_HOOK):**

```bash
# oldText (the unique ORIG_HOOK line — anchor):
readonly ORIG_HOOK="@livepicker-orig-session-window-changed"           # FULL show-hooks output (multi-line)
# newText (same line + the new saved-state hook constant):
readonly ORIG_HOOK="@livepicker-orig-session-window-changed"           # FULL show-hooks output (multi-line)
readonly ORIG_CLIENT_RESIZED_HOOK="@livepicker-orig-client-resized"        # FULL show-hooks output (the IDENTICAL-shape mirror of ORIG_HOOK; §P4); saved/restored by activate/restore (P1.M3.T1); auto-cleared by clear_all_state's grep '@livepicker-orig-'
```

**Edit 3 — append the 2 runtime keys to _STATE_RUNTIME_KEYS (MANDATORY):**

```bash
# oldText (the unique clear-list line — anchor):
readonly _STATE_RUNTIME_KEYS="$STATE_MODE $STATE_LIST $STATE_FILTER $STATE_INDEX $STATE_LINKED_ID $STATE_TAB_CURRENT_TMPL $STATE_TAB_INACTIVE_TMPL $STATE_PREVIEW_SEQ $STATE_PREVIEW_TARGET"
# newText (append the 2 new runtime keys inside the closing quote):
readonly _STATE_RUNTIME_KEYS="$STATE_MODE $STATE_LIST $STATE_FILTER $STATE_INDEX $STATE_LINKED_ID $STATE_TAB_CURRENT_TMPL $STATE_TAB_INACTIVE_TMPL $STATE_PREVIEW_SEQ $STATE_PREVIEW_TARGET $STATE_SCROLL $STATE_CLIENT_WIDTH"
```

NOTE for the implementer: the 3 edits are disjoint and each oldText is unique (verified — the
smoke applied exactly these anchors successfully). Apply them in any order (they don't
overlap). The ONLY load-bearing rule: the 2 runtime keys MUST land in `_STATE_RUNTIME_KEYS`
(Edit 3); the ORIG key MUST NOT. Do NOT initialize any value (no `set_state` calls).

### Integration Points

```yaml
CODE:
  - file: scripts/state.sh
    change: "+STATE_SCROLL, +STATE_CLIENT_WIDTH (runtime, cleared via list); +ORIG_CLIENT_RESIZED_HOOK
             (saved-state, cleared via grep); +2 entries in _STATE_RUNTIME_KEYS"
    invariant: "clear_all_state tears down all 3 new keys; §11 config + @livepicker-type preserved (CORRECTION A)"

CONSUMERS (later subtasks — DO NOT implement now):
  - P1.M3.T1 (activate + restore): set_state STATE_CLIENT_WIDTH via display-message -p '#{client_width}';
    install the client-resized hook; save the prior hook to ORIG_CLIENT_RESIZED_HOOK (tmux_get_hook);
    restore it on exit (tmux replay, mirroring session-window-changed — §P4).
  - P1.M3.T2 (input-handler): write STATE_SCROLL on scroll-into-view + reset on type/backspace/cancel.
  - P1.M2 (renderer): read STATE_CLIENT_WIDTH + STATE_SCROLL to slice the §19 viewport (no tmux round-trip).

CONFIG / DATABASE / ROUTES: none.
```

## Validation Loop

### Level 1: Syntax & Style (Immediate Feedback)

```bash
cd /home/dustin/.config/tmux/plugins/tmux-livepicker
bash -n scripts/state.sh && echo "OK: state syntax"
shellcheck scripts/state.sh          # expect 0 NEW findings (SC2034 is file-wide disabled in the header)
# Confirm the 3 constants are present with the exact @livepicker-* values:
grep -c '^readonly STATE_SCROLL="@livepicker-scroll"'            scripts/state.sh   # -> 1
grep -c '^readonly STATE_CLIENT_WIDTH="@livepicker-client-width"' scripts/state.sh   # -> 1
grep -c '^readonly ORIG_CLIENT_RESIZED_HOOK="@livepicker-orig-client-resized"' scripts/state.sh   # -> 1
# Confirm the 2 runtime keys were appended to the clear-list (and the ORIG key was NOT):
grep -c '\$STATE_SCROLL \$STATE_CLIENT_WIDTH"$' scripts/state.sh   # -> 1  (the list now ends with these)
grep -c 'ORIG_CLIENT_RESIZED' scripts/state.sh                      # -> 1  (only the constant def, NOT in the list)
# Sanity: the runtime block still precedes _STATE_RUNTIME_KEYS (set -u-safe expansion):
awk '/STATE_PREVIEW_TARGET=/{rt=NR} /_STATE_RUNTIME_KEYS=/{kl=NR} END{print "runtime_tail="rt" keys_line="kl; exit (kl>rt?0:1)}' scripts/state.sh \
  && echo "OK: runtime block above the list" || echo "FAIL: list not below runtime block"
# Expected: syntax clean; shellcheck 0 new findings; the 3 constants + the list append present.
```

### Level 2: Clear-list smoke (throwaway; sources the REAL state.sh on an isolated socket)

Throwaway smoke (DELETE after). Proves the constants resolve, the list expands to 11 keys,
and `clear_all_state` tears down all 3 new keys while preserving §11 config (CORRECTION A).
This is EXACTLY the validation that produced research FINDING 1–3:

```bash
cat > /tmp/smoke_state.sh <<'EOF'
#!/usr/bin/env bash
set -u
cd /home/dustin/.config/tmux/plugins/tmux-livepicker
source tests/setup_socket.sh
source tests/helpers.sh
setup_test "lp-state-smoke"
source scripts/utils.sh
source scripts/state.sh

pass_n=0; fail_n=0
ck() { if [ "$2" = "$3" ]; then pass_n=$((pass_n+1)); else fail_n=$((fail_n+1)); echo "  FAIL $1: got[$2] want[$3]"; fi; }

# (1) the 3 constants resolve to the exact @livepicker-* strings
ck "STATE_SCROLL"             "$STATE_SCROLL"             "@livepicker-scroll"
ck "STATE_CLIENT_WIDTH"       "$STATE_CLIENT_WIDTH"       "@livepicker-client-width"
ck "ORIG_CLIENT_RESIZED_HOOK" "$ORIG_CLIENT_RESIZED_HOOK" "@livepicker-orig-client-resized"

# (2) _STATE_RUNTIME_KEYS expands to 11 keys and contains both new runtime keys
ck "runtime-list count" "$(printf '%s\n' $_STATE_RUNTIME_KEYS | wc -l | tr -d '[:space:]')" "11"
case " $_STATE_RUNTIME_KEYS " in *" @livepicker-scroll "*) pass_n=$((pass_n+1));; *) fail_n=$((fail_n+1)); echo "  FAIL: @livepicker-scroll not in list";; esac
case " $_STATE_RUNTIME_KEYS " in *" @livepicker-client-width "*) pass_n=$((pass_n+1));; *) fail_n=$((fail_n+1)); echo "  FAIL: @livepicker-client-width not in list";; esac
# belt-and-braces: the ORIG key is NOT in the list (grep-cleared only)
case " $_STATE_RUNTIME_KEYS " in *@livepicker-orig-client-resized*) fail_n=$((fail_n+1)); echo "  FAIL: ORIG key must NOT be in the list";; *) pass_n=$((pass_n+1));; esac

# (3) clear_all_state tears down all 3 new keys; preserves §11 config (CORRECTION A)
tmux set-option -g @livepicker-scroll 3
tmux set-option -g @livepicker-client-width 80
tmux set-option -g @livepicker-orig-client-resized "client-resized[0] 'echo hi'"
tmux set-option -g @livepicker-type window          # config mirror — must SURVIVE
tmux set-option -g @livepicker-fg "#ffffff"          # §11 config — must SURVIVE
tmux set-option -g @livepicker-mode on               # ordinary runtime key — cleared
clear_all_state
ck "@livepicker-scroll cleared"           "$(tmux show-option -gqv @livepicker-scroll)"           ""
ck "@livepicker-client-width cleared"     "$(tmux show-option -gqv @livepicker-client-width)"    ""
ck "@livepicker-orig-client-resized cleared" "$(tmux show-option -gqv @livepicker-orig-client-resized)" ""
ck "@livepicker-mode cleared"             "$(tmux show-option -gqv @livepicker-mode)"             ""
ck "@livepicker-type PRESERVED"           "$(tmux show-option -gqv @livepicker-type)"             "window"
ck "@livepicker-fg PRESERVED (CORRECTION A)" "$(tmux show-option -gqv @livepicker-fg)"            "#ffffff"

teardown_test
echo "pass=$pass_n fail=$fail_n"
[ "$fail_n" -eq 0 ]
EOF
bash /tmp/smoke_state.sh; rc=$?
rm -f /tmp/smoke_state.sh
exit $rc
# Expected: pass~=13 fail=0. The 3 "cleared" assertions prove the list + grep mechanisms;
# the 2 "PRESERVED" assertions prove CORRECTION A still holds.
```

### Level 3: Full suite (no regression)

```bash
cd /home/dustin/.config/tmux/plugins/tmux-livepicker
tests/run.sh
# Expected: exit 0, all 44 tests green. The 3 new constants are not yet read by any script
# (P1.M3 wires them), so sourcing state.sh defines 3 extra no-side-effect constants + adds 2
# unset-at-test-time keys to the clear loop. No existing assertion can regress (the L2 smoke
# already confirmed @livepicker-mode + config preservation are intact).
```

### Level 4: Cross-check (the runtime-block-above-list ordering + the hook-mirror co-location)

```bash
cd /home/dustin/.config/tmux/plugins/tmux-livepicker
# The runtime block must precede _STATE_RUNTIME_KEYS (the list expands $STATE_* at source time):
grep -nE 'readonly STATE_(MODE|PREVIEW_TARGET|SCROLL|CLIENT_WIDTH)=' scripts/state.sh
grep -nE 'readonly _STATE_RUNTIME_KEYS=' scripts/state.sh
# Expected: the STATE_* line numbers are ALL < the _STATE_RUNTIME_KEYS line number.
# (If STATE_SCROLL/STATE_CLIENT_WIDTH appear BELOW the list, set -u would fire on the expansion
#  — but $STATE_* are defined at parse time for a `readonly` assignment on the same line as the
#  list... actually the list references them by expansion at the `readonly` line, so they MUST be
#  defined above it. The smoke (L2) sources cleanly under set -u, proving this holds.)
# Hook-mirror co-location: ORIG_CLIENT_RESIZED_HOOK sits right after ORIG_HOOK:
grep -nE 'readonly ORIG_(HOOK|CLIENT_RESIZED_HOOK)=' scripts/state.sh
# Expected: two adjacent line numbers.
```

## Final Validation Checklist

### Technical Validation

- [ ] `bash -n scripts/state.sh` clean.
- [ ] `shellcheck scripts/state.sh`: 0 NEW findings.
- [ ] The 3 constants present with exact `@livepicker-*` values (L1 grep counts = 1 each).
- [ ] The runtime block definitions precede `_STATE_RUNTIME_KEYS` (set -u-safe; L4).

### Feature Validation

- [ ] `_STATE_RUNTIME_KEYS` expands to 11 keys, containing `@livepicker-scroll` +
      `@livepicker-client-width` (L2).
- [ ] `ORIG_CLIENT_RESIZED_HOOK` is NOT in `_STATE_RUNTIME_KEYS` (L2 case check).
- [ ] `clear_all_state` tears down `@livepicker-scroll`, `@livepicker-client-width`,
      `@livepicker-orig-client-resized` (L2).
- [ ] CORRECTION A holds: `@livepicker-type` + `@livepicker-fg` (§11 config) PRESERVED (L2).
- [ ] Full `tests/run.sh` suite green (exit 0); no regression.

### Code Quality Validation

- [ ] Follows the `readonly STATE_X`/`ORIG_X` pattern exactly; inline comment per constant.
- [ ] Runtime keys appended to BOTH the readonly block tail AND `_STATE_RUNTIME_KEYS` (parallel order).
- [ ] `ORIG_CLIENT_RESIZED_HOOK` co-located with `ORIG_HOOK` (the §P4 mirror).
- [ ] No value initialized; no `set_state`/tmux call added (sourced-library contract holds).
- [ ] Existing constants/functions byte-identical (diff shows ONLY the 3 added lines + the 2 list tokens).

### Documentation & Deployment

- [ ] Each constant has an inline comment (purpose, writer/reader subtask, clear mechanism).
- [ ] No README/CHANGELOG change here (internal state keys; the changeset-level sync is P4.T1).

---

## Anti-Patterns to Avoid

- ❌ Don't forget to append `STATE_SCROLL` + `STATE_CLIENT_WIDTH` to `_STATE_RUNTIME_KEYS`. A
  runtime key absent from the list is a SILENT LEAK across picker sessions (state.sh header;
  §P3). The ORIG key is the opposite — see next.
- ❌ Don't add `ORIG_CLIENT_RESIZED_HOOK` to `_STATE_RUNTIME_KEYS`. ORIG_* keys are cleared by
  the `grep '@livepicker-orig-'` branch, NEVER the list (no existing ORIG_* key is in it).
  Adding it is redundant + violates the convention (FINDING 3).
- ❌ Don't initialize any value (no `set_state "$STATE_SCROLL" 0`, no `tmux` call). This task
  DEFINES the constants only; activation (P1.M3.T1) and input-handler (P1.M3.T2) write them.
  state.sh is a no-side-effect sourced library (P1).
- ❌ Don't reorder the blocks. The runtime `readonly` definitions MUST stay ABOVE
  `_STATE_RUNTIME_KEYS` (the list expands `$STATE_*` at source time; set -u would fire if a
  referenced constant were defined below it). Append within each block; do not move lines.
- ❌ Don't "use" the constants in-file to silence shellcheck. SC2034 is FILE-WIDE disabled
  (every STATE_*/ORIG_* is an externally-consumed seam); the 3 new ones inherit it — 0 new
  findings. Adding a per-line disable or a dummy use is wrong.
- ❌ Don't place `ORIG_CLIENT_RESIZED_HOOK` far from `ORIG_HOOK`. §P4 says client-resized is the
  IDENTICAL-shape mirror of session-window-changed; co-locating the two ORIG_* hook keys
  documents that. (Any ORIG_* position is functionally fine — the grep is order-independent —
  but the pairing is the readable choice.)
- ❌ Don't wire the constants into the renderer/input-handler/activate — that's P1.M2/P1.M3.
  This task only DEFINES them.
- ❌ Don't add a committed tests/ file — these are leaf constant definitions; validate via the
  throwaway L2 smoke. (The §19 layout/scroll/client-width tests are P1.M4.T3.)
- ❌ Don't edit by line number — anchor on the unique content (`STATE_PREVIEW_TARGET` line,
  `ORIG_HOOK` line, `_STATE_RUNTIME_KEYS` line).

---

## Confidence Score

**10 / 10** for one-pass success. Rationale: the deliverable is 3 `readonly` constant lines +
2 tokens appended to a space-list, each given verbatim with byte-exact anchors, following a
pattern every existing key already establishes. The one load-bearing rule (runtime keys →
list; ORIG key → grep, NOT the list) is empirically proven (research FINDING 3: all 3 keys
cleared; CORRECTION A intact) and asserted in the L2 smoke with a case-check that FAILS loudly
if the ORIG key is wrongly added to the list. The constants are unused until P1.M3, so
`tests/run.sh` stays green by construction (sourcing defines 3 extra no-side-effect constants;
the clear loop reaches 2 unset-at-test-time keys harmlessly). No parallel conflict
(P1.M1.T3.S1 is options.sh + README.md). Residual risk: near-zero — the only plausible slip
(the list append) is the exact thing the L2 smoke + the L1 grep counts pin down.
