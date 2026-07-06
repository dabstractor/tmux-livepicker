# PRP — P1.M1.T1.S1: Add opt_tab_style() accessor + STATE_TAB_* template-cache state keys

---

## Goal

**Feature Goal**: Lay the foundation for PRD §17 (theme-matched tabs) by adding
(1) the `opt_tab_style()` option accessor in `scripts/options.sh` (returns `plain`
or `window-status` per PRD §11), and (2) two picker-internal **runtime** state-key
constants in `scripts/state.sh` — `STATE_TAB_CURRENT_TMPL` /
`STATE_TAB_INACTIVE_TMPL` — wired into `_STATE_RUNTIME_KEYS` so `clear_all_state`
clears them on exit (no cross-session leak).

**Deliverable**: Two small edits to existing files — **no new files**.
1. `scripts/options.sh`: append one single-line accessor `opt_tab_style()`.
2. `scripts/state.sh`: add two `readonly STATE_TAB_*` constants to the runtime
   block + append them to `_STATE_RUNTIME_KEYS`.

**Success Definition**:
- `opt_tab_style` returns `"plain"` when `@livepicker-tab-style` is unset (the PRD
  §11 default), and surfaces a user override (`window-status`) via `get_opt`.
- `STATE_TAB_CURRENT_TMPL`/`STATE_TAB_INACTIVE_TMPL` resolve to
  `@livepicker-tab-current-tmpl` / `@livepicker-tab-inactive-tmpl`.
- Both keys are members of `_STATE_RUNTIME_KEYS`, so `clear_all_state` unsets them
  (proven: after `set_state` + `clear_all_state`, `tmux_is_set` → unset).
- Sourcing both files has **no side effects**; `bash -n` + `shellcheck` clean.

## User Persona (if applicable)

**Target User**: Downstream scripts (P1.M1.T2.S1 activate writes the cached
templates; P1.M1.T3.S1 renderer reads them) and the `opt_tab_style()` consumer.
Not end-user facing.

**Use Case**: At activation, if `opt_tab_style` = `window-status`, the sentinel
step resolves `window-status-current-format`/`window-status-format` and caches them
into the two `STATE_TAB_*` keys; the renderer reads them to render picker rows that
match the user's theme tabs. This subtask provides only the accessor + the keys.

**Pain Points Addressed**: No mechanism yet to (a) read the `tab-style` toggle or
(b) hold/cache the resolved templates in clearable runtime state.

---

## Why

- **Foundation for §17.** Every later subtask (P1.M1.T2 writer, P1.M1.T3 reader)
  needs these names to exist and to be cleared correctly. This subtask is the
  contract seam.
- **Leak prevention (system_context §3 Q4).** `clear_all_state` iterates
  `_STATE_RUNTIME_KEYS`. A runtime key NOT added there LEAKS across picker
  sessions — the resolved templates would persist after exit and pollute the next
  activation. Adding the keys here makes the foundation leak-safe by construction.
- **Runtime, not config (system_context §3 Q1).** The templates are resolved once
  at activation, not user-configured. They belong in `state.sh` as `STATE_*`
  runtime keys (cleared on exit), NOT in the `ORIG_*` saved-state contract (those
  are originals-to-restore; these are picker-internal cache).

## What

1. **options.sh**: append `opt_tab_style()` after `opt_status_format_index`
   (currently the last accessor, line 44), matching the existing single-line
   `{ get_opt "@livepicker-<name>" "<default>"; }` pattern exactly.
2. **state.sh**: add two `readonly STATE_TAB_*` constants to the **runtime**
   `STATE_*` block (immediately after `STATE_TYPE`), then append both to the
   `_STATE_RUNTIME_KEYS` space-list.
3. **Do NOT** add these to the `ORIG_*` saved-state block (they are not originals
   to restore). **Do NOT** add `opt_preview_defer` here (that is a separate
   subtask, P1.M2.T1.S1).

### Success Criteria

- [ ] `opt_tab_style()` present in options.sh; returns `"plain"` when unset.
- [ ] `grep -c 'get_opt "@livepicker-tab-style" "plain"' scripts/options.sh` → **1**.
- [ ] `STATE_TAB_CURRENT_TMPL`/`STATE_TAB_INACTIVE_TMPL` defined in the runtime
      block of state.sh (after `STATE_TYPE`, before the `ORIG_*` block).
- [ ] `_STATE_RUNTIME_KEYS` contains both new keys (appended).
- [ ] `clear_all_state` unsets both (leak-prevention smoke passes).
- [ ] `bash -n` + `shellcheck` clean on both files; sourcing = no side effects.

## All Needed Context

### Context Completeness Check

_Pass_: The implementer needs (a) the two exact accessor/constant lines (given
verbatim below), (b) the exact edit anchors (content-based, since line numbers in
the task contract are stale — see Gotchas), and (c) the `plain`-not-`tabs` default
correction. No inference required.

### Documentation & References

```yaml
# MUST READ - the authoritative default (overrides a STALE example elsewhere)
- docfile: PRD.md
  why: §11 table row `@livepicker-tab-style` default = `plain`; purpose =
       "plain (standalone fg/bg highlight) or window-status (reuse theme tab format)".
       §17 gives full semantics + the sentinel resolution + the plain fallback.
  critical: THE DEFAULT IS `plain`. NOT `tabs`, NOT `off`. plan/.../codebase_state.md
            §1 shows a STALE example `get_opt "@livepicker-tab-style" "tabs"` that
            PREDATES the final PRD — do NOT copy it. The PRD table is authoritative.

# MUST READ - the accessor pattern to mirror exactly
- file: scripts/options.sh
  why: Lines 26-44 are the existing single-line accessors; line 44
       (opt_status_format_index) is the insertion point (append after it).
  pattern: 'opt_<suffix>()  { get_opt "@livepicker-<name>" "<default>"; }  # comment'
  gotcha: The comment block (options.sh ~line 20-22) states the one-space arg
          formatting is load-bearing: a "Level-4 cross-check grep" matches each
          `get_opt "@livepicker-<suffix>" "<default>"` exactly once. Match the format.

# MUST READ - the runtime STATE_* block + _STATE_RUNTIME_KEYS to extend
- file: scripts/state.sh
  why: Runtime STATE_* constants (STATE_MODE..STATE_TYPE); _STATE_RUNTIME_KEYS
        (the space-list clear_all_state iterates); set_state/get_state helpers.
  pattern: 'readonly STATE_<NAME>="@livepicker-<name>"'  (runtime block);
           '_STATE_RUNTIME_KEYS="$STATE_A $STATE_B ..."'.
  gotcha: state.sh header DEPENDS ON utils.sh (tmux_get_opt/tmux_set_opt/tmux_unset_opt/
          tmux_is_set) — the caller sources utils.sh first. Do not source utils.sh
          inside state.sh.

# MUST READ - the leak-prevention rationale + runtime-vs-config decision
- docfile: plan/002_facc52335e68/architecture/system_context.md
  why: §3 Q1 (templates are RUNTIME, set-empty initially, cleared via _STATE_RUNTIME_KEYS)
       and §3 Q4 (any runtime key NOT in _STATE_RUNTIME_KEYS LEAKS across sessions).
  section: "## 3. Open questions RESOLVED" → Q1, Q4

# Reference - the baseline state map (NOTE its stale defaults — trust PRD over it)
- docfile: plan/002_facc52335e68/architecture/codebase_state.md
  why: §1 documents the options.sh accessor pattern + insertion point (after line 44);
       §2 documents state.sh runtime block + _STATE_RUNTIME_KEYS + clear_all_state.
  critical: §1's example accessor uses default "tabs" — THIS IS STALE/WRONG. Use "plain".
            Also: §1's claimed line numbers (31-36, 49) are from an earlier snapshot;
            verify live with grep (actual: STATE_MODE..STATE_TYPE = lines 40-45,
            _STATE_RUNTIME_KEYS = line 59).

# Reference - the is_set probe (downstream renderer contract, NOT implemented here)
- file: scripts/utils.sh
  why: tmux_is_set (line ~65) — exit-code probe: 0 = set (even ""), 1 = unset. Reliable
       for @-user-options only. This is how the renderer (P1.M1.T3) will distinguish
       "resolved empty" from "not resolved yet". get_state/get_opt CANNOT (both → "").
  section: tmux_is_set() comment block
```

### Current Codebase tree

```bash
tmux-livepicker/
  scripts/
    options.sh   # MODIFY: append opt_tab_style() after opt_status_format_index (line 44)
    state.sh     # MODIFY: +2 readonly STATE_TAB_* consts (runtime block) + extend _STATE_RUNTIME_KEYS
    utils.sh     # UNCHANGED (provides tmux_set_opt/get_opt/unset_opt/is_set — already present)
    ...          # (other scripts unchanged)
  tests/         # UNCHANGED (feature tests land in P1.M3.T2 test_appearance.sh)
```

### Desired Codebase tree with files to be added and responsibility of file

```bash
scripts/options.sh   # +1 accessor: opt_tab_style() — the plain|window-status toggle (PRD §11/§17)
scripts/state.sh     # +2 runtime keys: STATE_TAB_CURRENT_TMPL / STATE_TAB_INACTIVE_TMPL (cached
                      #   window-status formats); both cleared by clear_all_state via _STATE_RUNTIME_KEYS
```

### Known Gotchas of our codebase & Library Quirks

```bash
# CRITICAL — DEFAULT IS `plain`, NOT `tabs`. plan/.../codebase_state.md §1 shows a
# STALE example: `opt_tab_style() { get_opt "@livepicker-tab-style" "tabs"; }`.
# That predated the final PRD. The PRD §11 table is authoritative → default "plain".
# A wrong default here makes the renderer take the window-status path by accident
# (or vice-versa) and silently breaks the §15.24 appearance contract. Use "plain".

# CRITICAL — CONTRACT LINE NUMBERS ARE STALE. The task contract cites "lines 31-36"
# and "line 49" for state.sh, but the live file has STATE_MODE..STATE_TYPE at lines
# 40-45 and _STATE_RUNTIME_KEYS at line 59. DO NOT edit by line number — anchor
# every edit on CONTENT (the STATE_TYPE line, the ORIG block comment, the
# _STATE_RUNTIME_KEYS line). Verified live: `grep -n 'readonly STATE_\|_STATE_RUNTIME_KEYS' scripts/state.sh`.

# CRITICAL — these are RUNTIME keys, NOT ORIG_* saved-state. Add them to the runtime
# STATE_* block (after STATE_TYPE) and to _STATE_RUNTIME_KEYS. Do NOT add them among
# the ORIG_SESSION/ORIG_WINDOW/... block — those are originals-to-restore (PRD §9);
# the tab templates are picker-internal cache that is cleared, not restored.

# CRITICAL — _STATE_RUNTIME_KEYS membership is MANDATORY (system_context §3 Q4).
# clear_all_state (state.sh ~line 139) iterates this space-list to `set-option -gu`
# each. A runtime key NOT listed LEAKS across picker sessions. Append BOTH new keys.

# CRITICAL — set-empty vs unset (downstream contract; NOT implemented in this subtask,
# but the foundation must enable it). The renderer (P1.M1.T3) must distinguish
# "resolved empty" from "not resolved yet". get_state/get_opt CANNOT (both return ""),
# because the get_opt idiom is `[ -n "$v" ] && echo "$v" || echo "$2"`. The renderer
# must use tmux_is_set (utils.sh) for that distinction. For tmux_is_set to work, the
# WRITER (P1.M1.T2) must `set_state "$STATE_TAB_CURRENT_TMPL" ""` (real set-empty,
# i.e. `tmux set-option -g @x ""`) when resolution yields empty/fails — NOT leave it
# unset. set_state "" → tmux_set_opt → `tmux set-option -g @x ""` = set-empty (rc 0).
# This subtask only declares the keys; document this contract for the siblings.

# GOTCHA — shellcheck SC2034 (unused var) already disabled file-wide in state.sh
# (every STATE_*/ORIG_* is an integration seam unused within the file). The two new
# constants are covered by that existing disable. Do NOT remove the disable directive.

# GOTCHA — options.sh column alignment is "best effort" (not perfectly uniform:
# opt_suppress_window_hook uses 1 space before `{`, opt_status_format_index uses 2).
# Align opt_tab_style's `{` near column 28 to match the block; exact column is cosmetic
# (shfmt is NOT installed). The load-bearing constraint is the single-line shape +
# the exact `get_opt "@livepicker-tab-style" "plain"` substring for the cross-check grep.

# GOTCHA — do NOT add opt_preview_defer here. That accessor (default `on`, per PRD §11)
# is a SEPARATE subtask (P1.M2.T1.S1). Scope creep risks merge friction with that sibling.

# GOTCHA — Indent with TABS (whole codebase; shfmt absent). The state.sh readonly
# consts and the _STATE_RUNTIME_KEYS line use NO leading indent (column 0); match that.
```

## Implementation Blueprint

### Data models and structure

No runtime data model. The "model" is two constant declarations + one accessor:

```
@livepicker-tab-style   (config, PRD §11)  → opt_tab_style()  default "plain"
@livepicker-tab-current-tmpl   (runtime cache) → STATE_TAB_CURRENT_TMPL   (written P1.M1.T2, read P1.M1.T3)
@livepicker-tab-inactive-tmpl  (runtime cache) → STATE_TAB_INACTIVE_TMPL  (written P1.M1.T2, read P1.M1.T3)
```

Lifecycle (for context; this subtask implements only the boxed steps):
```
activate (P1.M1.T2):  if opt_tab_style == window-status:
                         resolve formats via sentinel → set_state STATE_TAB_CURRENT_TMPL "<rendered>"
                                                          set_state STATE_TAB_INACTIVE_TMPL "<rendered>"
                      (on failure/empty: set_state "" — set-empty, NOT unset)
renderer (P1.M1.T3):  if opt_tab_style != window-status → plain path
                      elif tmux_is_set STATE_TAB_CURRENT_TMPL && get_state non-empty → window-status path
                      else → plain fallback
restore  (P1.M5):     clear_all_state → -gu each _STATE_RUNTIME_KEYS member (incl. the two new keys)
```

### Implementation Tasks (ordered by dependencies)

```yaml
Task 1: MODIFY scripts/options.sh — APPEND opt_tab_style()
  - LOCATE: the accessor block; opt_status_format_index (currently line 44) is last.
  - ACTION: append one new line immediately after opt_status_format_index.
  - EXACT LINE (TAB-free, column-0, matching the block's single-line shape):
      opt_tab_style()            { get_opt "@livepicker-tab-style" "plain"; }       # enum: plain|window-status (PRD §17; plain=standalone fg/bg, window-status=reuse theme window-status-format)
    (pad with spaces so `{` sits near column 28 — match the existing accessors.)
  - DEFAULT: "plain" (PRD §11). NOT "tabs" (codebase_state.md §1 example is STALE).
  - FOLLOW pattern: scripts/options.sh lines 26-44 (single-line { get_opt ...; } body).
  - DO NOT: add opt_preview_defer (separate subtask), reorder existing accessors,
    or change get_opt.

Task 2: MODIFY scripts/state.sh — ADD two runtime constants + extend the clear-list
  - EDIT 2a: in the runtime STATE_* block, insert two readonly consts immediately
    AFTER the STATE_TYPE line and BEFORE the blank line + "--- saved-state CONTRACT
    keys ---" comment header. (Anchor on content; the contract's "line 36/38" are stale.)
    Add:
      readonly STATE_TAB_CURRENT_TMPL="@livepicker-tab-current-tmpl"   # cached window-status-current-format (PRD §17; written P1.M1.T2, read P1.M1.T3; cleared via _STATE_RUNTIME_KEYS)
      readonly STATE_TAB_INACTIVE_TMPL="@livepicker-tab-inactive-tmpl" # cached window-status-format         (PRD §17; written P1.M1.T2, read P1.M1.T3; cleared via _STATE_RUNTIME_KEYS)
  - EDIT 2b: append both keys to _STATE_RUNTIME_KEYS (currently the line reading
    `readonly _STATE_RUNTIME_KEYS="$STATE_MODE $STATE_LIST $STATE_FILTER $STATE_INDEX $STATE_LINKED_ID"`):
      readonly _STATE_RUNTIME_KEYS="$STATE_MODE $STATE_LIST $STATE_FILTER $STATE_INDEX $STATE_LINKED_ID $STATE_TAB_CURRENT_TMPL $STATE_TAB_INACTIVE_TMPL"
  - DO NOT: add these to the ORIG_* block; touch set_state/get_state/clear_all_state
    bodies; or remove the SC2034 file-wide disable (it covers the new consts).
  - NAMING: STATE_TAB_CURRENT_TMPL / STATE_TAB_INACTIVE_TMPL (UPPER_SNAKE readonly
    const convention, matching STATE_MODE/STATE_LIST/...).
  - PLACEMENT: runtime block (after STATE_TYPE), NOT the ORIG_* saved-state block.

Task 3: VALIDATE (throwaway smoke via the existing socket-isolated harness)
  - RUN: bash -n scripts/options.sh scripts/state.sh
  - RUN: shellcheck scripts/options.sh scripts/state.sh  (expect 0 NEW findings;
    SC2034 on the new consts is already covered by the file-wide disable in state.sh)
  - RUN: grep cross-checks (see Validation Loop L1)
  - RUN: leak-prevention smoke (L2) against an isolated socket; then DELETE it.
```

### Implementation Patterns & Key Details

**Exact edits (the implementer can paste these into the `edit` tool).**

*Task 1 — options.sh* (append after the last accessor; match the block shape):

```bash
# oldText (the current last accessor line):
opt_status_format_index()  { get_opt "@livepicker-status-format-index" "0"; } # int 0-9

# newText (same line + the new accessor):
opt_status_format_index()  { get_opt "@livepicker-status-format-index" "0"; } # int 0-9
opt_tab_style()            { get_opt "@livepicker-tab-style" "plain"; }       # enum: plain|window-status (PRD §17; plain=standalone fg/bg, window-status=reuse theme window-status-format)
```

*Task 2a — state.sh* (insert two consts between STATE_TYPE and the ORIG block header):

```bash
# oldText (anchor: STATE_TYPE line + blank + ORIG block header comment):
readonly STATE_TYPE="@livepicker-type"   # session|window — ALIAS of PRD §11 config (read-only; NEVER cleared)

# --- saved-state CONTRACT keys (PRD §9; written by activate, read by restore) ---

# newText (STATE_TYPE + two new runtime consts + blank + ORIG header):
readonly STATE_TYPE="@livepicker-type"   # session|window — ALIAS of PRD §11 config (read-only; NEVER cleared)
readonly STATE_TAB_CURRENT_TMPL="@livepicker-tab-current-tmpl"   # cached window-status-current-format (PRD §17; written P1.M1.T2, read P1.M1.T3; cleared via _STATE_RUNTIME_KEYS)
readonly STATE_TAB_INACTIVE_TMPL="@livepicker-tab-inactive-tmpl" # cached window-status-format         (PRD §17; written P1.M1.T2, read P1.M1.T3; cleared via _STATE_RUNTIME_KEYS)

# --- saved-state CONTRACT keys (PRD §9; written by activate, read by restore) ---
```

*Task 2b — state.sh* (extend the clear-list):

```bash
# oldText:
readonly _STATE_RUNTIME_KEYS="$STATE_MODE $STATE_LIST $STATE_FILTER $STATE_INDEX $STATE_LINKED_ID"

# newText:
readonly _STATE_RUNTIME_KEYS="$STATE_MODE $STATE_LIST $STATE_FILTER $STATE_INDEX $STATE_LINKED_ID $STATE_TAB_CURRENT_TMPL $STATE_TAB_INACTIVE_TMPL"
```

**Downstream contract this foundation enables** (do NOT implement here — for P1.M1.T2/P1.M1.T3):

```bash
# P1.M1.T2 (activate/writer) — on tab-style=window-status, AFTER resolving via the
# sentinel window, cache the rendered templates. On failure/empty, set-state EMPTY
# (real set-option -g @x ""), NOT leave-unset, so the renderer can tell "resolved
# empty" from "not resolved yet":
#   set_state "$STATE_TAB_CURRENT_TMPL"  "${cur:-}"   # "" if unresolved -> set-empty
#   set_state "$STATE_TAB_INACTIVE_TMPL" "${ina:-}"
# (set_state "" -> tmux_set_opt -> `tmux set-option -g @x ""` = set-empty, rc 0 for tmux_is_set)

# P1.M1.T3 (renderer/reader) — get_state CANNOT distinguish set-empty from unset
# (both -> ""). Use tmux_is_set (utils.sh) for the "is the cache populated?" probe:
#   if [ "$(opt_tab_style)" != "window-status" ]; then plain_path
#   elif tmux_is_set "$STATE_TAB_CURRENT_TMPL" && [ -n "$(get_state "$STATE_TAB_CURRENT_TMPL" "")" ]; then
#       window_status_path   # swap sentinel placeholder -> each session name
#   else plain_fallback   # empty/unresolved -> plain (PRD §17 "Fallback")
#   fi
```

### Integration Points

```yaml
CODE:
  - file: scripts/options.sh
    change: "+1 accessor opt_tab_style() (default 'plain')"
  - file: scripts/state.sh
    change: "+2 readonly STATE_TAB_* runtime consts; +2 members in _STATE_RUNTIME_KEYS"
    invariant: "clear_all_state unsets both new keys (no leak)"

CONSUMERS (later subtasks — DO NOT implement now):
  - P1.M1.T2.S1 (livepicker.sh activate): writes STATE_TAB_CURRENT_TMPL / STATE_TAB_INACTIVE_TMPL
  - P1.M1.T3.S1 (renderer.sh): reads opt_tab_style + the two template keys (via tmux_is_set)
  - P1.M5 restore: clear_all_state clears them (automatic once listed in _STATE_RUNTIME_KEYS)

CONFIG / DATABASE / ROUTES: none.
```

## Validation Loop

### Level 1: Syntax & Style (Immediate Feedback)

```bash
cd /home/dustin/.config/tmux/plugins/tmux-livepicker
bash -n scripts/options.sh scripts/state.sh && echo "OK: syntax"
shellcheck scripts/options.sh scripts/state.sh
# Cross-checks (load-bearing — these ARE the contract):
grep -c 'get_opt "@livepicker-tab-style" "plain"' scripts/options.sh           # -> 1  (default correct, single-line)
grep -c 'get_opt "@livepicker-tab-style" "tabs"'  scripts/options.sh           # -> 0  (STALE default NOT present)
grep -n 'STATE_TAB_CURRENT_TMPL="@livepicker-tab-current-tmpl"' scripts/state.sh   # -> 1 match
grep -n 'STATE_TAB_INACTIVE_TMPL="@livepicker-tab-inactive-tmpl"' scripts/state.sh # -> 1 match
# _STATE_RUNTIME_KEYS now references BOTH new consts:
grep '_STATE_RUNTIME_KEYS=' scripts/state.sh | grep -q 'STATE_TAB_CURRENT_TMPL' && echo "OK: current in list" || echo "FAIL"
grep '_STATE_RUNTIME_KEYS=' scripts/state.sh | grep -q 'STATE_TAB_INACTIVE_TMPL' && echo "OK: inactive in list" || echo "FAIL"
# New consts are in the RUNTIME block, NOT the ORIG_* block:
awk '/STATE_TAB_/{print NR": "$0}' scripts/state.sh   # line numbers should precede the first ORIG_* line
# Expected: all green; the "tabs" grep is 0 (the stale default must NOT appear).
```

### Level 2: Leak-prevention smoke (via the existing socket-isolated harness)

This subtask adds no committed test file (feature tests land in P1.M3.T2
`test_appearance.sh`). Run a throwaway smoke, then delete it. It reuses
`tests/setup_socket.sh` (PATH shim → bare `tmux` hits an isolated `-L` socket) +
`tests/helpers.sh` (assert_eq/fail/pass/setup_test/teardown_test):

```bash
cat > /tmp/smoke_tabkeys.sh <<'EOF'
#!/usr/bin/env bash
set -u
cd /home/dustin/.config/tmux/plugins/tmux-livepicker
source tests/setup_socket.sh
source tests/helpers.sh
setup_test "lp-smoke-tabkeys"
# state.sh depends on utils.sh (tmux_*); source order matters.
source scripts/utils.sh
source scripts/options.sh
source scripts/state.sh

pass_n=0; fail_n=0
ck() { if [ "$2" = "$3" ]; then pass_n=$((pass_n+1)); else fail_n=$((fail_n+1)); echo "FAIL $1: got[$2] want[$3]"; fi; }

# 1. accessor default (PRD §11)
ck "opt_tab_style default" "$(opt_tab_style)" "plain"
# 2. accessor surfaces a user override
tmux set-option -g @livepicker-tab-style window-status
ck "opt_tab_style override" "$(opt_tab_style)" "window-status"
tmux set-option -gu @livepicker-tab-style
# 3. constants resolve to the right @-names
ck "current tmpl name" "$STATE_TAB_CURRENT_TMPL" "@livepicker-tab-current-tmpl"
ck "inactive tmpl name" "$STATE_TAB_INACTIVE_TMPL" "@livepicker-tab-inactive-tmpl"
# 4. both are members of _STATE_RUNTIME_KEYS
case " $_STATE_RUNTIME_KEYS " in *" $STATE_TAB_CURRENT_TMPL "*) ;; *) fail_n=$((fail_n+1)); echo "FAIL: current not in runtime-keys";; esac
case " $_STATE_RUNTIME_KEYS " in *" $STATE_TAB_INACTIVE_TMPL "*) ;; *) fail_n=$((fail_n+1)); echo "FAIL: inactive not in runtime-keys";; esac
# 5. LEAK PREVENTION: set_state then clear_all_state -> both unset (tmux_is_set rc=1)
set_state "$STATE_TAB_CURRENT_TMPL" "rendered-cur"
set_state "$STATE_TAB_INACTIVE_TMPL" "rendered-ina"
tmux_is_set "$STATE_TAB_CURRENT_TMPL"  && ck "current set before clear" set set || ck "current set before clear" unset set
clear_all_state
if tmux_is_set "$STATE_TAB_CURRENT_TMPL";  then fail_n=$((fail_n+1)); echo "FAIL LEAK: current tmpl survived clear_all_state"; else pass_n=$((pass_n+1)); fi
if tmux_is_set "$STATE_TAB_INACTIVE_TMPL"; then fail_n=$((fail_n+1)); echo "FAIL LEAK: inactive tmpl survived clear_all_state"; else pass_n=$((fail_n+1)); fi

teardown_test
echo "pass=$pass_n fail=$fail_n"
[ "$fail_n" -eq 0 ]
EOF
bash /tmp/smoke_tabkeys.sh; rc=$?
rm -f /tmp/smoke_tabkeys.sh
exit $rc
# Expected: pass=7 fail=0, exit 0. The two LEAK assertions are the critical ones —
# they FAIL if you forget Edit 2b (appending to _STATE_RUNTIME_KEYS).
```

### Level 3: No-side-effects proof

```bash
cd /home/dustin/.config/tmux/plugins/tmux-livepicker
# Sourcing must not mutate any tmux option (both files are pure libraries).
before="$(tmux show-options -g 2>/dev/null | sort | cksum)"
( set -u; source scripts/utils.sh; source scripts/options.sh; source scripts/state.sh; )
after="$(tmux show-options -g 2>/dev/null | sort | cksum)"
[ "$before" = "$after" ] && echo "OK: no side effects" || echo "FAIL: tmux state mutated"
# Expected: OK. (Runs against whatever socket `tmux` resolves; the smoke above uses
# the isolated one — run this no-side-effect check on the isolated socket too if preferred.)
```

### Level 4: Cross-check against PRD §11 (defense against the stale-default trap)

```bash
# Every @livepicker-* option should appear exactly once with its PRD default.
# This guards the "tabs" vs "plain" mistake deterministically.
grep -oE 'get_opt "@livepicker-[a-z-]+" "[^"]*"' scripts/options.sh | sort | uniq -c | sort -rn | head
# Expected: each option count == 1; the tab-style line reads
#   1 get_opt "@livepicker-tab-style" "plain"
# If you see "tabs" here, or any count > 1, fix before finishing.
```

## Final Validation Checklist

### Technical Validation

- [ ] `bash -n scripts/options.sh scripts/state.sh` clean.
- [ ] `shellcheck` on both files: 0 NEW findings (SC2034 on new consts already covered).
- [ ] L1 grep cross-checks all green; `get_opt "@livepicker-tab-style" "tabs"` → 0 matches.
- [ ] L2 leak-prevention smoke: pass=7 fail=0 (the two clear_all_state LEAK asserts pass).

### Feature Validation

- [ ] `opt_tab_style` returns `"plain"` (unset) and `"window-status"` (override).
- [ ] Both `STATE_TAB_*` constants resolve to the correct `@livepicker-*` names.
- [ ] Both are in `_STATE_RUNTIME_KEYS` → `clear_all_state` unsets them (no leak).
- [ ] Sourcing both files has no side effects (L3 cksum unchanged).

### Code Quality Validation

- [ ] `opt_tab_style` follows the single-line `{ get_opt ...; } # comment` pattern.
- [ ] New constants are in the RUNTIME block (after STATE_TYPE), NOT the ORIG_* block.
- [ ] Naming matches conventions (`opt_<suffix>`; `STATE_UPPER_SNAKE`).
- [ ] No scope creep: `opt_preview_defer` NOT added (separate subtask P1.M2.T1.S1).
- [ ] No other logic changed (set_state/get_state/clear_all_state bodies untouched).

### Documentation & Deployment

- [ ] No user-facing/config/API surface change beyond the option row (README config
      table is synced in the Mode-B docs task P1.M3.T3.S1 — do NOT edit README here).
- [ ] Inline comments on the new lines cross-reference PRD §17 + the writer/reader
      sibling subtasks so the integration seam is self-documenting.

---

## Anti-Patterns to Avoid

- ❌ Don't use `"tabs"` as the default — it is a STALE value from codebase_state.md §1;
  the PRD §11 default is `"plain"`. (And `"off"` is wrong too.)
- ❌ Don't edit by line number — the contract's line numbers (31-36, 49) are stale.
  Anchor edits on content (STATE_TYPE line, ORIG block header, _STATE_RUNTIME_KEYS line).
- ❌ Don't add the new constants to the `ORIG_*` saved-state block — they are RUNTIME
  cache (cleared on exit), not originals-to-restore.
- ❌ Don't forget Edit 2b (appending to `_STATE_RUNTIME_KEYS`) — that is the whole
  leak-prevention point; without it the templates persist across sessions (Q4).
- ❌ Don't add `opt_preview_defer` in this subtask — it is P1.M2.T1.S1 (default `on`).
- ❌ Don't change `get_opt`/`set_state`/`get_state`/`clear_all_state` bodies.
- ❌ Don't use `get_state` to distinguish set-empty from unset downstream — it can't;
  the renderer must use `tmux_is_set` (documented above, not implemented here).
- ❌ Don't commit a `tests/` file for this subtask — feature tests are P1.M3.T2
  (`test_appearance.sh`); validate via the throwaway L2 smoke only.
- ❌ Don't reorder/reformat the existing accessors — append only (minimizes merge
  friction with the parallel preview-defer sibling subtask).

---

## Confidence Score

**10 / 10** for one-pass success. Rationale: two trivial, fully-specified edits
(the exact oldText/newText are given verbatim, anchored on content so stale line
numbers can't mislead); the only real trap — the stale `"tabs"` default — is
flagged in four places and caught by the L4 grep; the leak-prevention requirement
is proven by an executable L2 smoke against the existing isolated-socket harness;
and `shellcheck`/`bash -n` are verified-present. No ambiguity remains.
