# PRP — P1.M1.T3.S1: state.sh — @livepicker-* state accessors + saved-state CONTRACT + clear-all

---

## Goal

**Feature Goal**: A side-effect-free, sourceable Bash library `scripts/state.sh`
that is the **single integration seam** for the picker's runtime state and its
saved/restore contract. It (a) exposes `set_state`/`get_state` accessors over the
six `@livepicker-*` runtime options, (b) defines the **exact saved-state key
names** (the contract P1.M4 activate writes and P1.M5 restore reads), (c)
centralizes the load-bearing **status-format `-gu` trap** as a tested save/restore
helper pair, and (d) implements `clear_all_state` teardown that wipes all
picker-internal keys **without touching user CONFIG**.

**Deliverable**: The single file `scripts/state.sh` (created — it does not exist
yet). It defines constants + functions only; sourcing it touches no tmux state.

**Success Definition**:
- `bash -n scripts/state.sh` passes; `shellcheck scripts/state.sh` is clean.
- Sourcing the file (after sourcing `utils.sh`) defines all named state
  constants, `set_state`, `get_state`, `clear_all_state`,
  `state_status_format_save`, `state_status_format_restore`, and runs **zero**
  `tmux` invocations (no-side-effect proof).
- `clear_all_state` removes `@livepicker-mode`/`-list`/`-filter`/`-index`/
  `-linked-id` and every `@livepicker-orig-*`, yet **leaves `@livepicker-fg`
  `#ffffff` and `@livepicker-key Space` intact** (config-preservation proof).
- `state_status_format_save` then `state_status_format_restore` is a no-op
  round-trip when there are no user overrides (the tubular env), and correctly
  preserves a user-set `status-format[4]` across a `tmux set status-format[0]`
  clobber + restore.

## User Persona (if applicable)

**Target User**: The implementing AI agent and the downstream orchestrators
(`livepicker.sh` activate, `restore.sh`). Not end-user facing. Mode A — no
user-facing surface (internal state module).

**Use Case**: `livepicker.sh` (activate) calls `set_state` to write runtime keys,
`tmux_save_opt`/`state_status_format_save` to snapshot saved state, and sets
`@livepicker-mode on`. `restore.sh` calls `get_state` to read saved keys back,
`state_status_format_restore` to replay/reset status-format, and `clear_all_state`
to tear down. `input-handler.sh`/`preview.sh`/`renderer.sh` call `get_state` for
runtime probes (`@livepicker-mode`, `@livepicker-index`, `@livepicker-linked-id`).

**Pain Points Addressed**: (a) the saved-state key names are an integration seam
shared by activate (M4) and restore (M5) — without named constants they drift and
restore reads the wrong key; (b) the status-format `-gu` trap (TRAP 1) and its
is_set-probe limitation (FINDING 2) are the single most error-prone part of the
whole save/restore flow — centralizing them here prevents activate/restore from
re-deriving them incorrectly; (c) a naive `clear_all_state` that greps
`@livepicker-` and unsets each would **wipe the user's config** (verified live).

---

## Why

- **The integration seam.** This is the third of four foundation scripts
  (options → utils → **state** → plugin.tmux). PRD §9 enumerates exactly what is
  saved and restored; both the activate path (P1.M4.T1.S1) and the restore path
  (P1.M5.T3.S1) must agree on the *exact* `@livepicker-orig-*` key names. Naming
  them as `readonly` constants here is the contract — a typo in one path would
  silently break restore (read empty, skip a step).
- **Centralizes the status-format trap as code, not prose.** TRAP 1
  (system_context §4): restore MUST `set-option -gu status-format` (unset all →
  tmux re-composes defaults), NOT literal replay of captured strings. The
  work-item contract's suggested `is_set` probe for "genuinely user-set indices"
  is **empirically false** for `status-format[n]` (always rc=0 — utils research
  FINDING 2). state.sh encodes the corrected mechanism (bulk-dump enumeration +
  index≥3 heuristic + `-gu` replay) as a tested helper pair so activate/restore
  cannot propagate the false claim.
- **Config-safe teardown.** The literal contract ("grep `@livepicker-` and unset
  each") is a production bug: it unsets `@livepicker-fg`/`@livepicker-key`/etc.
  state.sh's `clear_all_state` clears only picker-internal keys (runtime + all
  `@livepicker-orig-*`) and never the PRD §11 config set — verified live.
- **Foundation for M4/M5/M6.** Every orchestrator and handler consumes these
  accessors and constants. Getting them right now unblocks four downstream
  milestones with a stable, tested interface.

## What

A sourced Bash library that exposes:

| Kind | Name | Signature / Value | Purpose |
|---|---|---|---|
| **Runtime constants** | `STATE_MODE` | `@livepicker-mode` | on/off double-activation guard |
| | `STATE_LIST` | `@livepicker-list` | newline-separated session names |
| | `STATE_FILTER` | `@livepicker-filter` | query string |
| | `STATE_INDEX` | `@livepicker-index` | int into filtered list |
| | `STATE_LINKED_ID` | `@livepicker-linked-id` | window id of linked preview, or empty |
| | `STATE_TYPE` | `@livepicker-type` | session\|window — **alias of the PRD §11 config option** (read-only mirror; never cleared) |
| **Saved-state constants (the CONTRACT)** | `ORIG_SESSION` | `@livepicker-orig-session` | original session name |
| | `ORIG_WINDOW` | `@livepicker-orig-window` | original **window ID** (not index) |
| | `ORIG_LAYOUT` | `@livepicker-orig-layout` | original `window_layout` string |
| | `ORIG_KEY_TABLE` | `@livepicker-orig-key-table` | original `key-table` value |
| | `ORIG_STATUS` | `@livepicker-orig-status` | original `status` line-count value |
| | `ORIG_RENUMBER` | `@livepicker-orig-renumber-windows` | original `renumber-windows` value |
| | `ORIG_HOOK` | `@livepicker-orig-session-window-changed` | FULL `show-hooks` output (multi-line/multi-index) |
| | `ORIG_STATUS_FORMAT_INDICES` | `@livepicker-orig-status-format-indices` | space-list of genuinely-user-set status-format indices |
| | `ORIG_STATUS_FORMAT_PREFIX` | `@livepicker-orig-status-format-` | per-index value key prefix (bracket-free; `+N` suffix) |
| **Accessors** | `set_state` | `key value` | write a runtime `@livepicker-*` option (delegates to `tmux_set_opt`) |
| | `get_state` | `key [default]` | read a runtime `@livepicker-*` option (delegates to `tmux_get_opt`; default optional, `set -u`-safe) |
| **Status-format trap** | `state_status_format_save` | — | enumerate materialized indices, store user-set list + per-index values (bracket-free keys) |
| | `state_status_format_restore` | — | `tmux_unset_opt status-format` (the `-gu` reset), then replay saved user-set indices |
| **Teardown** | `clear_all_state` | — | unset the 5 runtime keys + every `@livepicker-orig-*`; **skip config keys**; never error |

The file is **pure** — no `tmux` calls at source time, no global mutation beyond
the `readonly` constant definitions, no output, no `SCRIPT_DIR`. It assumes the
caller has already sourced `scripts/utils.sh` (it calls `tmux_get_opt`/
`tmux_set_opt`/`tmux_unset_opt`).

### Success Criteria

- [ ] File exists at `scripts/state.sh`; shebang `#!/usr/bin/env bash`; body
      starts with `set -u` (NO `set -e`, NO `set -o pipefail`).
- [ ] All 6 runtime + 9 saved-state constants present as `readonly` vars with the
      exact values in the table.
- [ ] `set_state`/`get_state`/`clear_all_state`/
      `state_status_format_save`/`state_status_format_restore` all present.
- [ ] `clear_all_state` removes runtime + orig keys but PRESERVES `@livepicker-fg`
      and `@livepicker-key` (config-preservation smoke proof).
- [ ] `state_status_format_save`→`restore` round-trips a user-set
      `status-format[4]` across a clobber (set `[0]` to a picker value, restore,
      assert `[4]` survives and `[0]` returns to default).
- [ ] `shellcheck scripts/state.sh` → 0 findings; `bash -n` → 0 errors; tabs only.
- [ ] No side effects: sourcing (after utils.sh) changes no tmux option.

## All Needed Context

### Context Completeness Check

_Pass_: A developer who has never seen this repo can implement this from
(a) the verbatim function/constant bodies quoted in the Implementation Blueprint,
(b) the two CONTRACT CORRECTIONS documented in the research findings
(clear_all_state config-safety; status-format is_set-probe is useless), and
(c) the validation commands. Every behavior is verified live on 3.6b.

### Documentation & References

```yaml
# MUST READ — the contract this module consumes (its INPUT dependency)
- docfile: plan/001_fd5d622d3939/P1M1T2S1/PRP.md
  why: Defines scripts/utils.sh: tmux_get_opt(name,[default]), tmux_set_opt(name,value),
       tmux_unset_opt(name), tmux_save_opt(orig_name,src_name), tmux_is_set(name) [with
       its @-options-only limitation]. state.sh delegates set_state/get_state to
       tmux_set_opt/tmux_get_opt and uses tmux_unset_opt in clear_all_state +
       state_status_format_restore. Treat this PRP as a CONTRACT — utils.sh will exist
       exactly as specified when state.sh is implemented.
  section: "Implementation Patterns & Key Details" (the verbatim utils.sh body)

# MUST READ — the empirical ground-truth for THIS module (two CONTRACT CORRECTIONS)
- docfile: plan/001_fd5d622d3939/P1M1T3S1/research/state_module_findings.md
  why: FINDING A (clear_all_state MUST NOT unset config keys — live proof that grep
       '@livepicker-' returns @livepicker-fg/#ffffff + @livepicker-key/Space);
       FINDING B (set-option -gu is safe on unset @-options, rc=0); FINDING C
       (status-format materializes exactly [0,1,2] as defaults; indices >=3 are
       user-set); FINDING D (status-format is_set probe is USELESS — the bulk-dump
       + index>=3 heuristic is the corrected mechanism); FINDING E (@livepicker-type
       is shared config+runtime, never cleared); FINDING F (state.sh depends on
       utils.sh, caller sources both, no SCRIPT_DIR).
  critical: Read BEFORE writing clear_all_state or the status-format helpers. The
            literal contract for clear_all_state is a production bug; the is_set-probe
            suggestion for status-format is empirically false.

# MUST READ — the canonical is_set / show-option idioms state.sh builds on
- file: scripts/utils.sh
  why: The actual implemented dependency. tmux_get_opt/tmux_set_opt/tmux_unset_opt
       are the primitives set_state/get_state/clear_all_state delegate to. Confirm
       their exact signatures (esp. tmux_get_opt's OPTIONAL default via ${2:-}).
  pattern: |
    tmux_get_opt()  { local v; v="$(tmux show-option -gqv "$1")"; [ -n "$v" ] && echo "$v" || echo "${2:-}"; }
    tmux_set_opt()  { tmux set-option -g "$1" "$2"; }
    tmux_unset_opt(){ tmux set-option -gu "$1"; }

# MUST READ — the coexisting sibling library (naming disjointness)
- file: scripts/options.sh
  why: get_opt/opt_* live alongside state.sh's set_state/get_state/STATE_*/ORIG_*.
       Confirm no collision (get_opt vs get_state; opt_* vs STATE_*/ORIG_*). state.sh
       does NOT depend on options.sh but coexists when both are sourced.
  pattern: one-line opt_<suffix>() accessors; STATE_*/ORIG_* are readonly string consts.

# MUST READ — the two traps + style this module encodes
- docfile: plan/001_fd5d622d3939/architecture/system_context.md
  why: §4 TRAP 1 (status-format restore = set-option -gu, NOT literal replay) is the
       load-bearing correctness rule state_status_format_restore enforces; §2 confirms
       the live env values (status=on, key-table=root, renumber-windows=on, the exact
       session-window-changed hook line, status-format[0..2] defaults); §9 mandates
       shell style (set -u, tabs, local, quote all expansions, no SCRIPT_DIR for
       sourced libs).
  section: "§4 Two environment-specific correctness traps", "§2 Verified environment", "§9 Shell style"

# MUST READ — PRD sections selected for this work item
- docfile: PRD.md
  why: §9 enumerates EXACTLY which options/hooks are saved & restored (the contract
       state.sh names); §5/§6 describe the runtime state keys (mode guard, list,
       filter, index, linked-id) and the clear-on-exit invariant; §11 lists the
       config options clear_all_state must PRESERVE.
  section: "§9 State saved and restored", "§5 Architecture", "§6 Behaviors", "§11 Configuration options"

# CONTEXT — tmux primitives (status-format array semantics, set-option -gu)
- docfile: plan/001_fd5d622d3939/architecture/tmux_primitives.md
  why: §3 verifies status-format[n] array + multi-line status mechanics; confirms
       set-option -gu on an array clears all indices and tmux re-composes defaults.
  section: "§3 status-format[n], #(), refresh-client -S"
```

### Current Codebase tree

```bash
tmux-livepicker/
  PRD.md
  plan/001_fd5d622d3939/{architecture/*.md, tasks.json, prd_snapshot.md, prd_index.txt}
  plan/001_fd5d622d3939/P1M1T1S1/PRP.md          # options.sh contract
  plan/001_fd5d622d3939/P1M1T2S1/{PRP.md, research/}   # utils.sh contract (THIS module's input)
  plan/001_fd5d622d3939/P1M1T3S1/{PRP.md, research/}   # THIS work item
  scripts/
    options.sh   # EXISTS (P1.M1.T1.S1 complete) — get_opt + 18 opt_* accessors
    utils.sh     # EXISTS (P1.M1.T2.S1 implemented) — tmux_* primitives (THIS module's dependency)
  .gitignore
  # NOTE: NO state.sh yet (this task). NO plugin.tmux, NO test harness (P1.M7).
```

### Desired Codebase tree with files to be added and responsibility of file

```bash
scripts/
  options.sh   # (P1.M1.T1) get_opt + opt_* config accessors. @livepicker-* user config.
  utils.sh     # (P1.M1.T2) tmux_* general option/hook primitives. Save/restore machinery.
  state.sh     # NEW (this task). @livepicker-* runtime accessors + saved-state CONTRACT
               #   (named constants) + status-format -gu trap helpers + clear_all_state.
```

### Known Gotchas of our codebase & Library Quirks

```bash
# CRITICAL (CONTRACT CORRECTION — research FINDING A): clear_all_state MUST NOT
# unset PRD §11 config keys. The literal contract ("grep '@livepicker-' and unset
# each") is a PRODUCTION BUG: it wipes @livepicker-fg/#ffffff, @livepicker-key/Space,
# etc., so the next activation reads wrong defaults until tmux.conf is re-sourced.
# Verified live: `show-options -g | grep '@livepicker-'` returns BOTH config keys.
# clear_all_state clears ONLY: the 5 runtime keys + every @livepicker-orig-*.
# @livepicker-type is PRESERVED (shared config+runtime mirror; picker only reads it).

# CRITICAL (CONTRACT CORRECTION — research FINDING D / utils FINDING 2): the
# status-format "is this index genuinely user-set?" probe via tmux_is_set is USELESS
# — show-options -g "status-format[N]" returns rc=0 for set, default, AND never-existed.
# The corrected mechanism: enumerate materialized indices from the BULK dump
# `show-options -g status-format` (parse "status-format[N]"); tmux always materializes
# the 3 defaults [0,1,2]; indices >= 3 are user-set. state_status_format_save stores
# ONLY user-set indices (>= 3) + their values; state_status_format_restore does the
# -gu reset (TRAP 1) then replays them. Genuine overrides of [0,1,2] are NOT
# preserved — documented limitation, acceptable because the target env has none
# (tubular unsets status-format) and -gu is provably correct when [0,1,2] are defaults.

# CRITICAL (TRAP 1 — system_context §4): status-format restore MUST be
# `tmux_unset_opt status-format` (set-option -gu), NOT literal replay of captured
# default strings. Replaying the captured [0,1,2] default strings is fragile and
# fights tubular on reload. The -gu reset lets tmux re-compose defaults live.
# state_status_format_restore does -gu FIRST, then replays only user-set (>=3) indices.

# CRITICAL (utils FINDING 4): brackets are REJECTED in @-option names
# ("not an array" error). So per-index status-format values are stored under
# BRACKET-FREE keys: @livepicker-orig-status-format-4 (not ...[4]). The
# ORIG_STATUS_FORMAT_PREFIX constant + index suffix constructs these keys.

# CRITICAL: this file is SOURCED, not executed. It must NOT compute SCRIPT_DIR,
# NOT call tmux at top level, NOT print anything. Functions + readonly constants
# only. It DEPENDS on utils.sh: the caller MUST `source scripts/utils.sh` BEFORE
# `source scripts/state.sh`. state.sh assumes tmux_get_opt/tmux_set_opt/tmux_unset_opt
# are already defined (it does NOT source utils.sh itself — mirror the options/utils
# convention; resurrect helpers.sh is the template for "sourced, no SCRIPT_DIR").

# GOTCHA: show-option (singular, -gqv) is used to READ values (matches options.sh/
# utils.sh); show-options (plural, -g) is used to ENUMERATE keys in clear_all_state
# and state_status_format_save (matches the bulk-dump idiom). Do not "normalize" —
# read uses singular -gqv (returns "" for unset → default); enumerate uses plural
# -g (lists all materialized keys/indices).

# GOTCHA: `set-option -gu "@some-key"` on an already-unset @-option exits 0 and
# prints nothing (research FINDING B) — so clear_all_state's per-key unset is
# intrinsically safe. Still redirect stderr to /dev/null per unset for belt-and-
# braces (a future tmux quirk must not spam the picker).

# GOTCHA: `@livepicker-type` is BOTH a PRD §11 config option (default "session")
# AND the runtime "mirror of option for speed". There is NO separate runtime type
# key. STATE_TYPE aliases "@livepicker-type"; get_state "$STATE_TYPE" reads the
# config value directly. clear_all_state MUST NOT unset it (would reset the user's
# configured picker mode). The picker never WRITES @livepicker-type.

# GOTCHA: window-scoped reads (window_layout, window_id) are NOT state.sh's job.
# state.sh names the KEYS (ORIG_WINDOW, ORIG_LAYOUT) but the ACTUAL capture of the
# window id / layout string is the activate caller's job (targeted show-option -gv
# -t <window> / display-message -p '#{window_layout}'). state.sh provides the key
# names + the status-format trap; the simple scalar saves use utils.sh::tmux_save_opt.

# GOTCHA: shellcheck SC2155 — never write `local x="$(cmd)"`. Always:
#   local x
#   x="$(cmd)"
# Indent with TABS (not spaces); shfmt is NOT installed.
```

## Implementation Blueprint

### Data models and structure

No runtime data model — only `readonly` string constants + function definitions.
The constants ARE the contract (the integration seam). The complete constant set
(copy these EXACTLY — verified against PRD §9 + system_context §2 + live env):

```bash
# --- runtime state keys (picker-internal; cleared on exit) ---
readonly STATE_MODE="@livepicker-mode"             # on/off double-activation guard
readonly STATE_LIST="@livepicker-list"             # newline-separated session names
readonly STATE_FILTER="@livepicker-filter"         # query string
readonly STATE_INDEX="@livepicker-index"           # int into filtered list
readonly STATE_LINKED_ID="@livepicker-linked-id"   # window id of linked preview, or empty
readonly STATE_TYPE="@livepicker-type"             # session|window — ALIAS of PRD §11 config (read-only; NEVER cleared)

# --- saved-state contract keys (written by activate P1.M4.T1.S1, read by restore P1.M5.T3.S1) ---
readonly ORIG_SESSION="@livepicker-orig-session"
readonly ORIG_WINDOW="@livepicker-orig-window"                       # window ID, NOT index
readonly ORIG_LAYOUT="@livepicker-orig-layout"                       # window_layout string
readonly ORIG_KEY_TABLE="@livepicker-orig-key-table"
readonly ORIG_STATUS="@livepicker-orig-status"                       # status line-count value
readonly ORIG_RENUMBER="@livepicker-orig-renumber-windows"
readonly ORIG_HOOK="@livepicker-orig-session-window-changed"         # FULL show-hooks output (multi-line)
readonly ORIG_STATUS_FORMAT_INDICES="@livepicker-orig-status-format-indices"  # space-list of user-set indices
readonly ORIG_STATUS_FORMAT_PREFIX="@livepicker-orig-status-format-"          # +N suffix (bracket-free)
```

The 5 runtime keys cleared by `clear_all_state` are grouped as a space-separated
list for the explicit-unset loop (see tasks). `STATE_TYPE` is intentionally NOT
in that list (config — preserved).

### Implementation Tasks (ordered by dependencies)

```yaml
Task 1: CREATE scripts/state.sh — header + constants
  - STRUCTURE: shebang `#!/usr/bin/env bash`; header comment block stating module
    purpose ("@livepicker-* runtime state accessors + the saved-state CONTRACT +
    the status-format -gu trap + config-safe clear_all_state"), "sourced library,
    NO side effects, DEPENDS on utils.sh (caller sources it first)", and the two
    CONTRACT CORRECTIONS it encodes (clear_all_state config-safety; status-format
    is_set-probe is useless → bulk-dump + index>=3 heuristic). Then `set -u` on
    its own line (NO -e, NO -o pipefail).
  - DEFINE all 6 STATE_* + 9 ORIG_* readonly constants EXACTLY as in the Data
    Models block above.
  - DEFINE the clear-list constant:
      readonly _STATE_RUNTIME_KEYS="$STATE_MODE $STATE_LIST $STATE_FILTER $STATE_INDEX $STATE_LINKED_ID"
    (the 5 keys clear_all_state unsets explicitly; STATE_TYPE deliberately absent.)
  - NAMING: UPPER_SNAKE readonly consts; set_state/get_state/state_* functions.
    Disjoint from options.sh (get_opt/opt_*) and utils.sh (tmux_*).
  - STYLE: tabs; double-quote every expansion.
  - PLACEMENT: scripts/state.sh
  - NO SIDE EFFECTS: no top-level tmux call, no top-level echo, no SCRIPT_DIR.

Task 2: IMPLEMENT set_state / get_state (thin accessors over utils primitives)
  - set_state(key, value):
      tmux_set_opt "$1" "$2"
    (Delegates to utils. Caller passes a STATE_* constant as the key.)
  - get_state(key, [default]):
      tmux_get_opt "$1" "${2:-}"
    (Delegates to utils; ${2:-} makes the default OPTIONAL and set -u-safe.)
  - COMMENTS: one docblock each — signature, that they delegate to utils
    tmux_set_opt/tmux_get_opt, and that the caller passes a STATE_* constant.

Task 3: IMPLEMENT state_status_format_save (the SAVE half of the trap)
  - PURPOSE: enumerate materialized status-format indices; store the genuinely-
    user-set list + per-index values. See Known Gotchas for the is_set limitation.
  - BODY:
      # 1. enumerate materialized indices from the bulk dump (parse "status-format[N]")
      local bulk idx user_indices n val
      bulk="$(tmux show-options -g status-format 2>/dev/null)"
      user_indices=""
      # 2. tmux always materializes defaults [0,1,2]; indices >= 3 are user-set.
      #    (FINDING D: the is_set exit-code probe is useless for status-format[n].)
      while IFS= read -r line; do
          idx="$(printf '%s\n' "$line" | sed -n 's/^status-format\[\([0-9]\+\)\].*/\1/p')"
          [ -z "$idx" ] && continue
          [ "$idx" -ge 3 ] || continue
          user_indices="${user_indices}${user_indices:+ }$idx"
      done <<EOF
$bulk
EOF
      # 3. store the user-set index list (empty if none — the tubular common case)
      tmux_set_opt "$ORIG_STATUS_FORMAT_INDICES" "$user_indices"
      # 4. store each user-set index's value in a BRACKET-FREE key (FINDING 4)
      for n in $user_indices; do
          val="$(tmux show-option -gqv "status-format[$n]" 2>/dev/null)"
          tmux_set_opt "${ORIG_STATUS_FORMAT_PREFIX}${n}" "$val"
      done
  - GOTCHA: `for n in $user_indices` deliberately WORD-SPLITS the space-list
    (no quotes) — that is the intent. $user_indices is internal/digit-only → safe.
  - GOTCHA: the heredoc feeds $bulk to the while-read so multi-line parsing works
    under `set -u` without a pipe (avoids a subshell scoping issue).
  - COMMENT: state the is_set limitation (FINDING D) and the [0,1,2]-as-defaults
    heuristic + its documented limitation (genuine [0..2] overrides not preserved).

Task 4: IMPLEMENT state_status_format_restore (the RESTORE half — TRAP 1)
  - PURPOSE: reset status-format to tmux defaults (-gu), then replay user-set.
  - BODY:
      # 1. TRAP 1 (system_context §4): -gu resets ALL indices → tmux re-composes
      #    defaults [0,1,2]. NEVER replay captured default strings.
      tmux_unset_opt status-format
      # 2. replay each genuinely-user-set index from the saved list
      local indices n val
      indices="$(tmux_get_opt "$ORIG_STATUS_FORMAT_INDICES" "")"
      for n in $indices; do
          val="$(tmux_get_opt "${ORIG_STATUS_FORMAT_PREFIX}${n}" "")"
          [ -n "$val" ] && tmux_set_opt "status-format[$n]" "$val"
      done
  - GOTCHA: `tmux_unset_opt status-format` (no index) clears EVERY index — this is
    the whole-array -gu (utils FINDING 3). The picker's renderer at [0] is removed.
  - COMMENT: state TRAP 1 explicitly; note this is the value-free restore path.

Task 5: IMPLEMENT clear_all_state (config-safe teardown)
  - PURPOSE: unset all picker-INTERNAL keys; PRESERVE PRD §11 config.
  - BODY:
      # 1. unset the 5 runtime keys explicitly (STATE_TYPE deliberately NOT here).
      local k
      for k in $_STATE_RUNTIME_KEYS; do
          tmux set-option -gu "$k" 2>/dev/null || true
      done
      # 2. unset every @livepicker-orig-* saved-state key (dynamic count: includes
      #    the per-index ORIG_STATUS_FORMAT_PREFIX-N keys). -gu is safe on unset.
      while IFS= read -r line; do
          k="${line%% *}"        # first token = the option name
          [ -n "$k" ] && tmux set-option -gu "$k" 2>/dev/null || true
      done <<EOF
$(tmux show-options -g 2>/dev/null | grep '@livepicker-orig-')
EOF
      # NOTE: we do NOT grep '@livepicker-' broadly — that would wipe CONFIG
      # (@livepicker-fg/#ffffff, @livepicker-key/Space, ...). See research FINDING A.
      # NOTE: key-table teardown (unbind-key -T livepicker) is NOT done here —
      # restore.sh owns it (P1.M5.T4.S1). clear_all_state clears OPTIONS only.
  - GOTCHA: `|| true` guards each unset so a missing key never aborts (belt-and-
    braces beyond -gu's intrinsic rc=0). stderr redirected to suppress noise.
  - GOTCHA: the heredoc + while-read avoids `grep ... | while` (subshell scope).
    `show-options -g | grep` output is captured into the heredoc at expansion time.
  - COMMENT: state the config-preservation CONTRACT CORRECTION prominently.

Task 6: VALIDATE (manual smoke — no harness exists yet; P1.M7 invents one)
  - RUN: bash -n scripts/state.sh
  - RUN: shellcheck scripts/state.sh   (expect 0 findings)
  - RUN the throwaway smoke script (Validation Loop §2) against the live server,
    then DELETE it (do NOT commit a tests/ file).
  - VERIFY no-side-effects: snapshot `tmux show-options -g | sort | cksum` before
    & after sourcing state.sh (after utils.sh) in a subshell; assert identical.
  - VERIFY config-preservation + status-format round-trip (Validation Loop §2/§3).
```

### Implementation Patterns & Key Details

```bash
#!/usr/bin/env bash
# scripts/state.sh — tmux-livepicker runtime state accessors + saved-state CONTRACT.
#
# Sourced library (NOT executed). Three responsibilities:
#   1. set_state/get_state — thin accessors over the 6 @livepicker-* runtime keys.
#   2. Named readonly constants for the saved-state CONTRACT (the integration seam
#      P1.M4.T1.S1 activate writes and P1.M5.T3.S1 restore reads — PRD §9).
#   3. The status-format -gu trap (state_status_format_save / _restore) +
#      clear_all_state teardown.
#
# DEPENDS ON scripts/utils.sh: the caller MUST `source scripts/utils.sh` BEFORE this
# file. We assume tmux_get_opt / tmux_set_opt / tmux_unset_opt are defined. We do NOT
# source utils.sh ourselves (mirror the options/utils convention; no SCRIPT_DIR).
#
# CONTRACT CORRECTIONS encoded here (see research/state_module_findings.md):
#   CORRECTION A — clear_all_state clears ONLY picker-internal keys (5 runtime +
#     every @livepicker-orig-*). It MUST NOT unset PRD §11 config (@livepicker-fg,
#     @livepicker-key, ...). The literal "grep '@livepicker-' and unset each" is a
#     production bug (wipes user config mid-session). @livepicker-type is preserved
#     (shared config+runtime mirror; the picker only reads it).
#   CORRECTION D — the status-format "is this index user-set?" probe via tmux_is_set
#     is USELESS (rc=0 for set/default/never-existed). The corrected mechanism:
#     enumerate materialized indices from the bulk dump; tmux always materializes
#     defaults [0,1,2]; indices >= 3 are user-set. Save stores only those; restore
#     does the -gu reset (TRAP 1) then replays them.
#
# CONTRACT: sourcing this file has NO side effects (beyond defining readonly consts).
# Coexists with options.sh (get_opt/opt_*) and utils.sh (tmux_*): disjoint namespacing.

set -u   # NOT -e (show-option legitimately returns non-zero); NOT -o pipefail.

# --- runtime state keys (picker-internal; cleared on exit by clear_all_state) ---
readonly STATE_MODE="@livepicker-mode"
readonly STATE_LIST="@livepicker-list"
readonly STATE_FILTER="@livepicker-filter"
readonly STATE_INDEX="@livepicker-index"
readonly STATE_LINKED_ID="@livepicker-linked-id"
readonly STATE_TYPE="@livepicker-type"   # session|window — ALIAS of PRD §11 config (read-only; NEVER cleared)

# --- saved-state CONTRACT keys (PRD §9; written by activate, read by restore) ---
readonly ORIG_SESSION="@livepicker-orig-session"
readonly ORIG_WINDOW="@livepicker-orig-window"                         # window ID, NOT index
readonly ORIG_LAYOUT="@livepicker-orig-layout"                         # window_layout string
readonly ORIG_KEY_TABLE="@livepicker-orig-key-table"
readonly ORIG_STATUS="@livepicker-orig-status"                         # status line-count value
readonly ORIG_RENUMBER="@livepicker-orig-renumber-windows"
readonly ORIG_HOOK="@livepicker-orig-session-window-changed"           # FULL show-hooks output (multi-line)
readonly ORIG_STATUS_FORMAT_INDICES="@livepicker-orig-status-format-indices"
readonly ORIG_STATUS_FORMAT_PREFIX="@livepicker-orig-status-format-"   # +N suffix (bracket-free)

# keys clear_all_state unsets explicitly (STATE_TYPE deliberately absent: it is config)
readonly _STATE_RUNTIME_KEYS="$STATE_MODE $STATE_LIST $STATE_FILTER $STATE_INDEX $STATE_LINKED_ID"

# $1: STATE_* key, $2: value. Writes a runtime @livepicker-* option (delegates to
# utils tmux_set_opt). Caller passes a STATE_* constant, not a raw string.
set_state() {
	tmux_set_opt "$1" "$2"
}

# $1: STATE_* key, $2: optional default (returned when unset/empty). Reads a runtime
# @livepicker-* option (delegates to utils tmux_get_opt). ${2:-} makes the default
# OPTIONAL and safe under `set -u`.
get_state() {
	tmux_get_opt "$1" "${2:-}"
}

# SAVE the status-format array for later restore. Enumerates materialized indices
# from `show-options -g status-format`; tmux always materializes the 3 built-in
# defaults [0,1,2], so only indices >= 3 are treated as genuinely user-set (FINDING
# D: the tmux_is_set exit-code probe is useless for status-format[n]). Stores the
# user-set index list in ORIG_STATUS_FORMAT_INDICES and each value in a bracket-free
# ORIG_STATUS_FORMAT_PREFIX+N key (brackets are rejected in @-names — utils FINDING 4).
# LIMITATION: a genuine user override of [0,1,2] is NOT preserved (acceptable: the
# target env has none — tubular unsets status-format — and the -gu restore is
# provably correct when [0,1,2] are defaults).
state_status_format_save() {
	local bulk idx user_indices n val
	bulk="$(tmux show-options -g status-format 2>/dev/null)"
	user_indices=""
	while IFS= read -r line; do
		idx="$(printf '%s\n' "$line" | sed -n 's/^status-format\[\([0-9]\+\)\].*/\1/p')"
		[ -z "$idx" ] && continue
		[ "$idx" -ge 3 ] || continue
		user_indices="${user_indices}${user_indices:+ }$idx"
	done <<EOF
$bulk
EOF
	tmux_set_opt "$ORIG_STATUS_FORMAT_INDICES" "$user_indices"
	for n in $user_indices; do
		val="$(tmux show-option -gqv "status-format[$n]" 2>/dev/null)"
		tmux_set_opt "${ORIG_STATUS_FORMAT_PREFIX}${n}" "$val"
	done
}

# RESTORE the status-format array (TRAP 1, system_context §4). Step 1: `set-option
# -gu status-format` clears EVERY index and tmux re-composes the [0,1,2] defaults —
# NEVER replay captured default strings (fragile, fights tubular). Step 2: replay
# each genuinely-user-set index saved by state_status_format_save.
state_status_format_restore() {
	local indices n val
	tmux_unset_opt status-format
	indices="$(tmux_get_opt "$ORIG_STATUS_FORMAT_INDICES" "")"
	for n in $indices; do
		val="$(tmux_get_opt "${ORIG_STATUS_FORMAT_PREFIX}${n}" "")"
		[ -n "$val" ] && tmux_set_opt "status-format[$n]" "$val"
	done
}

# Tear down ALL picker-INTERNAL state. Unsets the 5 runtime keys + every
# @livepicker-orig-* saved-state key. MUST NOT unset PRD §11 config (CORRECTION A):
# `grep '@livepicker-'` broadly would wipe @livepicker-fg/#ffffff, @livepicker-key,
# etc. We clear the runtime list explicitly and grep ONLY '@livepicker-orig-'.
# @livepicker-type is preserved (shared config+runtime mirror; never written by us).
# set-option -gu is safe on already-unset @-options (rc=0); `|| true` + 2>/dev/null
# belt-and-braces. Key-table teardown (unbind-key -T livepicker) is restore.sh's
# job (P1.M5.T4.S1) — clear_all_state clears OPTIONS only.
clear_all_state() {
	local k
	for k in $_STATE_RUNTIME_KEYS; do
		tmux set-option -gu "$k" 2>/dev/null || true
	done
	while IFS= read -r line; do
		k="${line%% *}"
		[ -n "$k" ] && tmux set-option -gu "$k" 2>/dev/null || true
	done <<EOF
$(tmux show-options -g 2>/dev/null | grep '@livepicker-orig-')
EOF
}
```

NOTE for the implementer: the block above is the complete, ready file body. Use it
as-is; the only allowed deviation is comment phrasing. Do NOT add a
`state_status_format_is_set` helper (the is_set probe is useless for status-format —
the bulk-dump heuristic replaces it). Do NOT have clear_all_state grep the broad
`@livepicker-` prefix (it wipes config). Do NOT source utils.sh inside this file.

### Integration Points

```yaml
SOURCING ORDER (consumers MUST source utils.sh BEFORE state.sh):
  - scripts/livepicker.sh  (P1.M4.T1) source utils.sh; source state.sh; source options.sh
      save path:  tmux_save_opt session ORIG_SESSION... ; set_state "$STATE_MODE" on
                  state_status_format_save ; (build list) set_state "$STATE_LIST" "$list"
  - scripts/restore.sh     (P1.M5.T3/T4) source utils.sh; source state.sh
      restore:   tmux_set_opt key-table "$(tmux_get_opt $ORIG_KEY_TABLE root)"
                  state_status_format_restore ; ... ; clear_all_state
  - scripts/input-handler.sh (P1.M6) source utils.sh; source state.sh
      reads:     get_state "$STATE_FILTER" "" ; get_state "$STATE_INDEX" 0
  - scripts/preview.sh     (P1.M3) source utils.sh; source state.sh
      reads:     get_state "$STATE_LINKED_ID" "" ; set_state "$STATE_LINKED_ID" "$id"
  - scripts/renderer.sh    (P1.M2) source utils.sh; source state.sh; source options.sh
      reads:     get_state "$STATE_LIST" ; get_state "$STATE_INDEX" ; get_state "$STATE_FILTER"

CONFIG:
  - add to: nothing. state.sh defines constants + helpers. The only writers are
    set_state (runtime, at caller request) and the status-format save helper; both
    act only when a consumer calls them, never at source time.

KEY-BINDING TEARDOWN: NOT here. clear_all_state clears OPTIONS only; restore.sh
  (P1.M5.T4.S1) owns `tmux unbind-key -T livepicker`.

ROUTES / DATABASE / MIGRATIONS: none — tmux option/state module only.
```

## Validation Loop

### Level 1: Syntax & Style (Immediate Feedback)

```bash
# Run after creating the file — fix before proceeding.
bash -n scripts/state.sh                        # syntax check; expect no output, exit 0
shellcheck scripts/state.sh                     # lint; expect 0 findings
# Tabs-not-spaces sanity (shfmt NOT installed; verify manually):
grep -Pn '^    ' scripts/state.sh && echo "FAIL: 4-space indent found, use tabs" || echo "OK: no leading 4-space groups"

# Expected: all three clean. shellcheck SC2155 only fires if you collapsed a
# `local x; x="$(...)"` onto one line — split them (see Known Gotchas).
# NOTE: shellcheck may flag the heredoc `<<EOF $bulk EOF` or the unquoted
# `for n in $user_indices` — these are INTENTIONAL (documented in comments). If
# shellcheck warns, add a `# shellcheck disable=SC...` directive with a comment
# explaining why (word-split is intended; heredoc avoids subshell scope).
```

### Level 2: Unit Tests (Component Validation)

There is no test harness yet (P1.M7.T1/T2 invents the socket-isolation shim). For
THIS subtask, run a throwaway smoke script against the live server, then delete it.
The probes below mutate only `@livepicker-*` picker-internal keys + a throwaway
`status-format[4]`, all cleaned up at the end — safe on the live server. (For full
isolation, prefix with the P1.M7 socket shim once it exists.)

```bash
# Throwaway smoke (do NOT commit a tests/ dir):
cat > /tmp/smoke_state.sh <<'EOF'
#!/usr/bin/env bash
set -u
source "$(dirname "$1")/scripts/utils.sh" "$1"
source "$(dirname "$1")/scripts/state.sh" "$1"

pass=0; fail=0
assert_eq() { # $1 desc $2 actual $3 expected
	if [ "$2" = "$3" ]; then pass=$((pass+1));
	else fail=$((fail+1)); printf 'FAIL %s: got [%s] want [%s]\n' "$1" "$2" "$3"; fi
}

# --- constants present + exact values ---
assert_eq "STATE_MODE"      "$STATE_MODE"      "@livepicker-mode"
assert_eq "STATE_LINKED_ID" "$STATE_LINKED_ID" "@livepicker-linked-id"
assert_eq "ORIG_WINDOW"     "$ORIG_WINDOW"     "@livepicker-orig-window"
assert_eq "ORIG_HOOK"       "$ORIG_HOOK"       "@livepicker-orig-session-window-changed"
assert_eq "ORIG_SF_INDICES" "$ORIG_STATUS_FORMAT_INDICES" "@livepicker-orig-status-format-indices"
assert_eq "ORIG_SF_PREFIX"  "$ORIG_STATUS_FORMAT_PREFIX"  "@livepicker-orig-status-format-"

# --- set_state / get_state round-trip + default ---
set_state "$STATE_FILTER" "abc"
assert_eq "get_state filter"   "$(get_state "$STATE_FILTER")"      "abc"
assert_eq "get_state default"  "$(get_state "$STATE_INDEX" "0")"   "0"
assert_eq "get_state empty-def" "$(get_state "$STATE_LINKED_ID" "")" ""

# --- clear_all_state: clears runtime + orig, PRESERVES config ---
set_state "$STATE_MODE" "on"
tmux set-option -g "$ORIG_SESSION" "myorig"
clear_all_state
assert_eq "mode cleared"      "$(get_state "$STATE_MODE")"      ""
assert_eq "filter cleared"    "$(get_state "$STATE_FILTER")"    ""
assert_eq "orig-session clr"  "$(tmux show-option -gqv "$ORIG_SESSION" 2>/dev/null)" ""
# CONFIG PRESERVATION (the CORRECTION A proof):
# NOTE: show-option -gqv returns the value UNQUOTED (#ffffff), not "#ffffff".
assert_eq "config fg preserved"   "$(tmux show-option -gqv "@livepicker-fg")"   "#ffffff"
assert_eq "config key preserved"  "$(tmux show-option -gqv "@livepicker-key")"  "Space"
assert_eq "config type preserved" "$(tmux show-option -gqv "@livepicker-type")" ""

# --- status-format round-trip (no user overrides = no-op; the tubular common case) ---
state_status_format_save
assert_eq "no user sf indices -> empty list" "$(tmux show-option -gqv "$ORIG_STATUS_FORMAT_INDICES" 2>/dev/null)" ""
tmux set-option -g "status-format[0]" "PICKER-RENDERER"     # simulate the picker install
state_status_format_restore
assert_eq "sf[0] reset to default-ish (not PICKER)" "$(tmux show-option -gqv "status-format[0]" 2>/dev/null | head -c 10)" "#[align=le"

# --- status-format round-trip WITH a user override at index [4] ---
tmux set-option -g "status-format[4]" "USER-OVERRIDE-4"
state_status_format_save
assert_eq "user sf[4] index saved" "$(tmux show-option -gqv "$ORIG_STATUS_FORMAT_INDICES" 2>/dev/null)" "4"
assert_eq "user sf[4] value saved" "$(tmux show-option -gqv "${ORIG_STATUS_FORMAT_PREFIX}4" 2>/dev/null)" "USER-OVERRIDE-4"
tmux set-option -g "status-format[4]" "CLOBBERED"            # simulate picker/other mutation
tmux set-option -g "status-format[0]" "PICKER"
state_status_format_restore
assert_eq "user sf[4] REPLAYED" "$(tmux show-option -gqv "status-format[4]" 2>/dev/null)" "USER-OVERRIDE-4"
assert_eq "sf[0] back to default" "$(tmux show-option -gqv "status-format[0]" 2>/dev/null | head -c 10)" "#[align=le"

# --- cleanup (restore user env) ---
clear_all_state
tmux set-option -gu "status-format[4]" 2>/dev/null || true

printf 'PASS=%d FAIL=%d\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
EOF
bash /tmp/smoke_state.sh "$(pwd)"; rc=$?
rm -f /tmp/smoke_state.sh
exit $rc
# Expected: PASS≈20 FAIL=0, exit 0. The two config-preservation assertions
# (@livepicker-fg still "#ffffff", @livepicker-key still Space) are the
# CORRECTION-A proof; the sf[4] replay is the CORRECTION-D / TRAP-1 proof.
```

### Level 3: Integration Testing (System Validation)

```bash
# No-side-effects proof: sourcing state.sh (after utils.sh) must NOT change any
# tmux option. (state.sh defines readonly consts only at source time — no tmux calls.)
before="$(tmux show-options -g | sort | cksum)"
( set -u; source ./scripts/utils.sh; source ./scripts/state.sh; )   # subshell; source only
after="$(tmux show-options -g | sort | cksum)"
[ "$before" = "$after" ] && echo "OK: no side effects" || echo "FAIL: tmux state mutated"

# CONTRACT consumer-simulation: a fake activate+restore using ONLY state.sh's
# named constants (proves the key names round-trip with a partner that uses them).
source ./scripts/utils.sh; source ./scripts/state.sh
# fake activate save:
tmux set-option -g "$ORIG_SESSION" "fakeSess"
tmux set-option -g "$ORIG_WINDOW"  "@42"
tmux set-option -g "$ORIG_LAYOUT"  "bbe9,80x24,0,0,2"
state_status_format_save
set_state "$STATE_MODE" "on"
# fake restore read:
got_sess="$(tmux_get_opt "$ORIG_SESSION" "")"
got_win="$(tmux_get_opt "$ORIG_WINDOW" "")"
got_lay="$(tmux_get_opt "$ORIG_LAYOUT" "")"
[ "$got_sess" = "fakeSess" ] && [ "$got_win" = "@42" ] && [ "$got_lay" = "bbe9,80x24,0,0,2" ] \
  && echo "OK: contract keys round-trip" || echo "FAIL: contract key mismatch ($got_sess/$got_win/$got_lay)"
clear_all_state
# verify clear removed the orig keys:
[ -z "$(tmux show-option -gqv "$ORIG_SESSION" 2>/dev/null)" ] && echo "OK: clear removed orig-session" || echo "FAIL: orig-session survived"
# Expected: all OK.

# Coexistence: options.sh + utils.sh + state.sh all sourced together (no name clash).
bash -c 'set -u; source ./scripts/options.sh; source ./scripts/utils.sh; source ./scripts/state.sh; \
         type get_opt opt_type tmux_get_opt tmux_is_set set_state get_state clear_all_state >/dev/null \
         && echo "OK: three libraries sourced, no collision" || echo "FAIL: name clash"'
# Expected: OK.
```

### Level 4: Creative & Domain-Specific Validation

```bash
# status-format restore is INVARIANT-CORRECT: after a picker install (renderer at
# [0]) + restore, the status line must return to the tubular-default composite
# (system_context §3 INVARIANT C). Verify [0] is non-empty (re-composed default)
# and contains the window-status markers after restore.
source ./scripts/utils.sh; source ./scripts/state.sh
tmux set-option -g "status-format[0]" "#(echo PICKER)"
state_status_format_save
state_status_format_restore
sf0="$(tmux show-option -gqv "status-format[0]" 2>/dev/null)"
case "$sf0" in
  *"window-status-current-format"*) echo "OK: [0] restored to tubular-default composite" ;;
  *) echo "FAIL: [0] is not the default composite: ${sf0:0:60}..." ;;
esac
# Expected: OK. (Confirms the -gu reset re-composes the live default, TRAP 1.)

# clear_all_state idempotency: running it twice must not error and must leave
# config intact both times.
source ./scripts/utils.sh; source ./scripts/state.sh
clear_all_state; clear_all_state
[ "$(tmux show-option -gqv "@livepicker-fg")" = "#ffffff" ] && echo "OK: config survives double-clear" || echo "FAIL"
# Expected: OK.

# Edge: clear_all_state when NO @livepicker-orig-* exist (fresh state) — must not error.
tmux show-options -g 2>/dev/null | grep '@livepicker-orig-' | while read -r l; do tmux set-option -gu "${l%% *}" 2>/dev/null; done
clear_all_state && echo "OK: clear_all_state on empty orig-set is safe" || echo "FAIL"
# Expected: OK (the while-loop body simply doesn't execute; `|| true` guards each unset).
```

## Final Validation Checklist

### Technical Validation

- [ ] `bash -n scripts/state.sh` exits 0 with no output.
- [ ] `shellcheck scripts/state.sh` reports 0 findings (intentional word-split /
      heredoc sites carry a `# shellcheck disable=` directive with rationale).
- [ ] No 4-space indents (`grep -Pn '^    '` is empty); tabs only.
- [ ] Smoke script: PASS≈20 FAIL=0, including the config-preservation + sf[4]
      replay proofs.

### Feature Validation

- [ ] All 6 STATE_* + 9 ORIG_* constants present as `readonly` with exact values.
- [ ] `set_state`/`get_state` delegate to utils `tmux_set_opt`/`tmux_get_opt`;
      `get_state`'s default is OPTIONAL (`${2:-}`, `set -u`-safe).
- [ ] `clear_all_state` removes the 5 runtime keys + every `@livepicker-orig-*`
      AND preserves `@livepicker-fg`/`@livepicker-key`/`@livepicker-type` (CORRECTION A).
- [ ] `clear_all_state` does NOT call `unbind-key` (restore.sh owns key teardown).
- [ ] `state_status_format_save` stores only indices >= 3 (user-set) in
      `ORIG_STATUS_FORMAT_INDICES` + bracket-free per-index value keys.
- [ ] `state_status_format_restore` does `tmux_unset_opt status-format` (TRAP 1)
      FIRST, then replays saved user-set indices.
- [ ] No-side-effects proof passes (sourcing changes no tmux option).
- [ ] Contract round-trip proof: a partner using the named constants reads back
      what activate wrote.

### Code Quality Validation

- [ ] Shebang `#!/usr/bin/env bash`; `set -u` only (no `-e`, no `-o pipefail`).
- [ ] `local` declared before assign in every helper (SC2155-safe).
- [ ] All expansions double-quoted EXCEPT the intentional word-split
      (`for n in $user_indices`, `for k in $_STATE_RUNTIME_KEYS`) — documented.
- [ ] One docblock per function documenting signature, delegation, and the
      relevant gotcha/correction.
- [ ] No top-level `tmux` call, no top-level `echo`, no `SCRIPT_DIR`, no globals
      beyond the readonly constants.
- [ ] `STATE_*`/`ORIG_*`/`set_state`/`get_state`/`state_*` names disjoint from
      options.sh (`get_opt`/`opt_*`) and utils.sh (`tmux_*`).
- [ ] state.sh does NOT source utils.sh (caller sources it first); does NOT
      source options.sh.

### Documentation & Deployment

- [ ] Header comment states: sourced library, no side effects, depends on utils.sh
      (caller sources first), the two CONTRACT CORRECTIONS (A: config-safe clear;
      D: status-format is_set-probe is useless → bulk-dump heuristic).
- [ ] No new env vars introduced (helpers only invoke `tmux` via utils).
- [ ] No README/doc file created (DOCS = Mode A internal module; surfaces in
      README at P1.M8.T1.S1).

---

## Anti-Patterns to Avoid

- ❌ Don't have `clear_all_state` grep the broad `@livepicker-` prefix and unset
  each — that wipes user CONFIG (`@livepicker-fg`, `@livepicker-key`, ...). Grep
  ONLY `@livepicker-orig-` + explicitly unset the 5 runtime keys (CORRECTION A).
- ❌ Don't unset `@livepicker-type` in `clear_all_state` — it is a PRD §11 config
  option aliased as the runtime mirror; the picker only READS it. Unsetting it
  resets the user's configured picker mode to the default.
- ❌ Don't use `tmux_is_set` to decide which `status-format[n]` indices are
  user-set — it always returns rc=0 for `status-format[n]` (useless). Use the
  bulk-dump enumeration + index>=3 heuristic (CORRECTION D).
- ❌ Don't replay captured `status-format[0..2]` default strings on restore (TRAP
  1). Do `tmux_unset_opt status-format` (the `-gu` reset) FIRST, then replay only
  the saved user-set (>=3) indices.
- ❌ Don't store status-format values under bracketed keys
  (`@livepicker-orig-status-format[4]`) — brackets are rejected in `@`-names. Use
  the bracket-free `ORIG_STATUS_FORMAT_PREFIX` + `N` suffix.
- ❌ Don't add `set -e`/`-o pipefail` — `show-option`/`show-options` legitimately
  return non-zero on unset/unknown options.
- ❌ Don't collapse `local x; x="$(...)"` into `local x="$(...)"` (SC2155).
- ❌ Don't have `clear_all_state` call `tmux unbind-key -T livepicker` — key-table
  teardown is restore.sh's job (P1.M5.T4.S1). clear_all_state clears OPTIONS only.
- ❌ Don't source utils.sh (or options.sh) inside state.sh — it's a pure sourced
  library; the CALLER sources utils.sh first. (Mirror options/utils convention.)
- ❌ Don't compute `SCRIPT_DIR`/`CURRENT_DIR` — sourced library, not an entry point.
- ❌ Don't run `tmux` at the top level of the file (violates "no side effects" and
  breaks sourcing inside other strict scripts).
- ❌ Don't create a `tests/` directory or committed test file — the harness is
  invented in P1.M7.T1/T2; this subtask validates via throwaway smoke only.
- ❌ Don't add window-scoped reads (window_layout / window_id capture) to state.sh
  — it NAMES the keys (ORIG_WINDOW/ORIG_LAYOUT) but the targeted capture is the
  activate caller's job (utils.sh is strictly global).
- ❌ Don't quote the intentional word-splits (`for n in $user_indices`,
  `for k in $_STATE_RUNTIME_KEYS`) — splitting is the intent; the values are
  internal/digit-or-constant-only → safe. Add a shellcheck directive if needed.

---

## Confidence Score

**9 / 10** for one-pass success. Rationale: the deliverable is a single sourced
library whose constant set and function bodies are given nearly verbatim above,
each delegating to utils.sh primitives that already exist and are tested
(P1.M1.T2.S1 complete). The two load-bearing CONTRACT CORRECTIONS (clear_all_state
config-safety; status-format is_set-probe is useless → bulk-dump + index>=3
heuristic + `-gu` restore) are backed by live empirical proof in the research
findings and asserted in the smoke script (config keys survive; `status-format[4]`
replays; `[0]` returns to the tubular-default composite). The integration seam
(named constants) is stable and round-trip-tested. Tools verified present:
`tmux 3.6b`, `bash 5.3.15`, `shellcheck 0.11.0`. Residual risk: (a) a shellcheck
directive needed for the intentional word-split/heredoc (caught at Level 1);
(b) the `idx -ge 3` arithmetic if an index is non-numeric — guarded by the `sed`
parse (only digits captured) and `[ -z "$idx" ] && continue`. Both are
deterministically caught by the validation loop.
