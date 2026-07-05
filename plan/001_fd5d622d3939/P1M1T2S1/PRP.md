# PRP — P1.M1.T2.S1: utils.sh — safe tmux option helpers + is_set probe

---

## Goal

**Feature Goal**: A side-effect-free, sourceable Bash library `scripts/utils.sh`
that exposes the **general-purpose tmux option & hook primitives** every
save/restore path needs: read/write/unset any global option, snapshot an option
into a `@livepicker-orig-*` key, probe whether an `@`-option is genuinely
user-set, and read/clear the array-indexed `session-window-changed` hook. These
are the low-level safe wrappers around `show-option`/`set-option`/`show-hooks`/
`set-hook` that `state.sh`, `livepicker.sh` (save), `restore.sh` (restore), and
`preview.sh` build on — so none of them re-implements the two environment traps
(status-format `-gu` restore, array-indexed hook save) inline.

**Deliverable**: The single file `scripts/utils.sh` (created — it does not exist
yet). It defines functions only; sourcing it touches no tmux state and prints
nothing.

**Success Definition**:
- `bash -n scripts/utils.sh` passes; `shellcheck scripts/utils.sh` is clean.
- Sourcing the file defines all 7 helpers (`tmux_get_opt`, `tmux_set_opt`,
  `tmux_unset_opt`, `tmux_save_opt`, `tmux_is_set`, `tmux_get_hook`,
  `tmux_clear_hook`) and runs **zero** `tmux` invocations (no-side-effect proof).
- `tmux_is_set "@livepicker-fg"` → exit 0 (it is set); `tmux_is_set "@livepicker-type"`
  → exit 1 (unset) — proving the exit-code probe works for `@`-options.
- `tmux_save_opt status status` writes `@livepicker-orig-status` = the live
  `status` value; `tmux_clear_hook session-window-changed` clears every index of
  the hook (verified by `show-hooks` collapsing to the bare name).

## User Persona (if applicable)

**Target User**: The implementing AI agent (and downstream save/restore scripts).
Not end-user facing. Mode A — no user-facing surface (internal helper module).

**Use Case**: `livepicker.sh` save path calls `tmux_save_opt status status`,
`tmux_save_opt key-table key-table`, `tmux_get_hook session-window-changed`.
`restore.sh` calls `tmux_unset_opt status-format` (the TRAP-1 `-gu` restore),
`tmux_set_opt key-table "$ORIG"`, replays the saved hook. `state.sh` and
`preview.sh` call `tmux_get_opt`/`tmux_is_set` for `@livepicker-*` state probes.

**Pain Points Addressed**: (a) every consumer would otherwise re-type the
`show-option`/`set-option`/`-gu` incantations and re-discover the two traps;
(b) the array-indexed hook and the `-gu` status-format restore are easy to get
wrong if inlined; centralizing them here makes the traps explicit and tested.

---

## Why

- **Single source of truth for the save/restore primitives.** PRD §9 (state
  saved/restored) and §13 (tmux primitives) require reading, saving, restoring,
  and unsetting `status`, `status-format[n]`, `key-table`, `renumber-windows`,
  and the `session-window-changed` hook. Without a helper layer, ~4 scripts
  duplicate this logic and the two environment traps (system_context §4) get
  re-implemented per file — guaranteeing drift and a tubular-breaking restore.
- **Encodes the two load-bearing traps as code + comments.** TRAP 1
  (status-format restore MUST be `set-option -gu`, not literal replay) and TRAP 2
  (the hook is array-indexed with `-b`; save the whole `show-hooks` line) are
  expressed directly in `tmux_unset_opt` / `tmux_get_hook` / `tmux_clear_hook`
  with empirical proof in the comments.
- **Foundation for M1.T3+ .** `state.sh` (T3) layers `@livepicker-*` state
  accessors on top of these primitives; the activate/restore orchestrators
  (M4/M5) consume them directly. This is the second of four foundation scripts
  (options → **utils** → state → plugin.tmux).
- **Proven idiom.** `tmux_is_set` mirrors tubular's `__tubular_is_set` verbatim
  (system_context §4 / sibling_plugins §4); `tmux_get_opt` mirrors the
  `get_tmux_option` idiom shared by session-history/sessionx/resurrect (the same
  body options.sh::get_opt uses, in a separate namespace).

## What

A sourced Bash library that exposes exactly seven functions:

| Function | Signature | Wraps | One-line purpose |
|---|---|---|---|
| `tmux_get_opt` | `name [default]` | `show-option -gqv` | read any global option's effective value (default if unset) |
| `tmux_set_opt` | `name value` | `set-option -g` | set a global option (caller passes indexed name for arrays) |
| `tmux_unset_opt` | `name` | `set-option -gu` | unset → default; whole-array if `name` has no index |
| `tmux_save_opt` | `orig_name src_name` | `show-option -gqv` + `set-option -g` | snapshot `src_name`'s value into `@livepicker-orig-${orig_name}` |
| `tmux_is_set` | `name` | `show-options -g` | exit-code probe: is this `@`-option genuinely user-set? |
| `tmux_get_hook` | `hookname` | `show-hooks -g` | return FULL multi-line indexed hook output |
| `tmux_clear_hook` | `hookname` | `set-hook -gu` | clear every index of a hook |

The file is **pure** — no `tmux` calls at source time, no global mutation, no
output, no `SCRIPT_DIR` (it is a sourced library, not an entry point).

### Success Criteria

- [ ] File exists at `scripts/utils.sh`; shebang `#!/usr/bin/env bash`; body
      starts with `set -u` (NO `set -e`, NO `set -o pipefail`).
- [ ] All 7 functions present with the exact signatures/wrappers in the table.
- [ ] `tmux_is_set` is byte-identical in behavior to tubular's `__tubular_is_set`:
      `tmux show-options -g "$1" >/dev/null 2>&1` (return code = tmux exit code).
- [ ] `tmux_save_opt` writes to `@livepicker-orig-${orig_name}` (the FIRST arg),
      reading from `src_name` (the SECOND arg) — see Known Gotchas for why two
      args (brackets rejected in `@`-names).
- [ ] `tmux_get_hook` returns the raw `show-hooks -g` output unchanged
      (multi-line, `hookname[N] cmd` prefix intact).
- [ ] `shellcheck scripts/utils.sh` → 0 findings; `bash -n` → 0 errors; tabs only.
- [ ] No side effects: sourcing the file does not change any tmux option/hook.

## All Needed Context

### Context Completeness Check

_Pass_: A developer who has never seen this repo can implement this from
(a) the verbatim function bodies quoted in the Implementation Blueprint, (b) the
empirical probe findings cited below (which correct two claims in the contract),
and (c) the four validation commands. No inference about tmux internals is
required — every behavior is verified live.

### Documentation & References

```yaml
# MUST READ — the empirical ground-truth (corrects two contract claims)
- docfile: plan/001_fd5d622d3939/P1M1T2S1/research/tmux_option_probe_empirical.md
  why: Live-verified behavior of every primitive this module wraps. TWO CONTRACT
       CORRECTIONS are documented here and MUST be reflected in the code+comments:
         FINDING 2 — tmux_is_set exit code does NOT work for status-format[n]
                     (always rc=0); status-format restore MUST use -gu (TRAP 1).
         FINDING 4 — brackets are REJECTED in @-option names ("not an array"
                     error); tmux_save_opt dest key MUST be bracket-free.
  critical: Read this BEFORE writing any function body. It is the authoritative
            behavior reference; the contract's array-index exit-code claim is
            false on 3.6b and must not be propagated into tmux_is_set's comments.

# MUST READ — the canonical is_set idiom to mirror verbatim
- file: ~/.config/tmux/plugins/tubular-tmux/tubular.tmux
  why: Lines 36-41 define __tubular_is_set — the exact probe tmux_is_set mirrors.
       Note the comment (lines 36-38) explaining the exit-code semantics.
  pattern: |
    # Is a user option explicitly set? show-options errors (exit 1) on unknown /
    # unset options, and succeeds (exit 0) even when the option is set to "".
    __tubular_is_set() {
      tmux show-options -g "$1" >/dev/null 2>&1
    }
  gotcha: That comment is accurate ONLY for @-options (no built-in default). For
          built-in options and array indices (status-format[n]) the exit code is
          ALWAYS 0 — see research FINDING 2. tmux_is_set's comment must state
          this limitation explicitly.

# MUST READ — the get_tmux_option idiom (mirrors options.sh::get_opt)
- file: ~/.config/tmux/plugins/tmux-resurrect/scripts/helpers.sh
  why: Lines 19-26 — the same show-option -gqv idiom in a SOURCED helper library.
       Proves the pattern transfers to a sourced, no-side-effect module.
  pattern: |
    get_tmux_option() {
        local option="$1"
        local default_value="$2"
        local option_value=$(tmux show-option -gqv "$option")   # note: SC2155 here;
        if [ -z "$option_value" ]; then echo "$default_value"    # livepicker splits
        else echo "$option_value"; fi                              # local+assign
    }

# MUST READ — the prior PRP (contract for the sibling library this composes with)
- docfile: plan/001_fd5d622d3939/P1M1T1S1/PRP.md
  why: Defines options.sh (get_opt + opt_* accessors). utils.sh runs alongside
       it (both sourced by livepicker.sh/restore.sh). Confirm the naming is
       disjoint (get_opt/opt_* vs tmux_*) so there is no collision.
  section: "Implementation Patterns & Key Details" (the verbatim options.sh body)

# MUST READ — the two traps this module exists to centralize
- docfile: plan/001_fd5d622d3939/architecture/system_context.md
  why: §4 TRAP 1 (status-format restore = set-option -gu, NOT literal replay) and
       TRAP 2 (session-window-changed is array-indexed with -b; save whole
       show-hooks line). §7 gives the exact save/clear/restore hook recipe.
       §9 mandates shell style (set -u, tabs, local, quote all expansions).
  section: "§4 Two environment-specific correctness traps" and "§7 The session-window-changed hook"

# MUST READ — tmux primitives + hook array semantics
- docfile: plan/001_fd5d622d3939/architecture/tmux_primitives.md
  why: §4 verifies set-hook/show-hooks semantics (array-indexed, -b preserved,
       -gu clears all). Confirms the hook save/restore approach is sound.
  section: "§4 set-hook / session-window-changed / client-session-changed"

# MUST READ — option namespacing + sibling conventions
- docfile: plan/001_fd5d622d3939/architecture/sibling_plugins_and_env.md
  why: §3 confirms @livepicker-orig-* hyphen naming; §4 quotes the get_tmux_option
       + __tubular_is_set idioms; §5 mandates shell style.
  section: "§3 Option namespacing" and "§4 SCRIPT_DIR computation & helper sourcing"

# CONTEXT — PRD sections selected for this work item
- docfile: PRD.md
  why: §9 lists exactly which options/hooks are saved & restored (the consumers
       of these primitives); §13 is the tmux primitives reference; §16 calls out
       the -b hook flag and window-id addressing.
  section: "§9 State saved and restored", "§13 tmux primitives reference", "§16 Implementation risks"
```

### Current Codebase tree

```bash
tmux-livepicker/
  PRD.md
  plan/001_fd5d622d3939/{architecture/*.md, tasks.json, prd_snapshot.md, prd_index.txt}
  plan/001_fd5d622d3939/P1M1T1S1/PRP.md          # prior PRP (options.sh contract)
  plan/001_fd5d622d3939/P1M1T2S1/{PRP.md, research/}   # THIS work item
  .gitignore
  # NOTE: scripts/ does NOT exist yet at research time. options.sh (P1.M1.T1.S1)
  # is being implemented IN PARALLEL — assume it will exist as specified.
  # NO plugin.tmux, NO state.sh, NO test harness yet (invented in P1.M7).
```

### Desired Codebase tree with files to be added and responsibility of file

```bash
scripts/
  options.sh   # (P1.M1.T1 — parallel) get_opt + opt_* config accessors. @livepicker-* config.
  utils.sh     # NEW (this task). tmux_* general option/hook primitives. Save/restore machinery.
```

### Known Gotchas of our codebase & Library Quirks

```bash
# CRITICAL (CONTRACT CORRECTION — research FINDING 2): tmux_is_set's exit-code
# probe is reliable ONLY for @-user-options (no built-in default). For built-in
# options (status, key-table, renumber-windows, ...) and array indices
# (status-format[n]) the exit code is ALWAYS 0 — set, unset, default, or
# never-existed all return 0. Verified on 3.6b:
#   show-options -g "status-format[0]"  → rc=0  (tubular -gu'd it: it's a default)
#   show-options -g "status-format[5]"  → rc=0  (never set, no default)
# DO NOT use tmux_is_set to decide status-format save/restore. Status-format
# restore MUST be unconditional `tmux_unset_opt status-format` (TRAP 1). State
# this limitation in tmux_is_set's comment so P1.M5.T3 is not misled.

# CRITICAL (CONTRACT CORRECTION — research FINDING 4): brackets are REJECTED in
# @-option names. tmux reads `[N]` as an array-index specifier, so:
#   tmux set-option -g "@livepicker-orig-status-format[0]" X
#   → "not an array: @livepicker-orig-status-format[0]"  (rc=1, option NOT set)
# Therefore tmux_save_opt's DESTINATION key (@livepicker-orig-<orig_name>) MUST
# be bracket-free. The TWO-arg signature exists for exactly this: pass a
# sanitized orig_name (e.g. "status-format-0") as arg 1 and the real (possibly
# bracketed) src_name (e.g. "status-format[0]") as arg 2. For non-array options
# pass both args identical: tmux_save_opt status status.

# CRITICAL: show-option (singular) vs show-options (plural). tmux accepts both
# as aliases. This module deliberately MIXES them to match its sources:
#   tmux_get_opt  -> show-option  -gqv  (singular, matches options.sh::get_opt + siblings)
#   tmux_is_set   -> show-options -g    (plural,  matches tubular __tubular_is_set verbatim)
#   setters       -> set-option -g/-gu, set-hook -gu  (singular, man-page convention)
# Do not "normalize" to all-singular or all-plural — follow the table exactly.

# CRITICAL: This file is SOURCED, not executed. It must NOT compute SCRIPT_DIR,
# NOT call tmux at top level, NOT print anything, NOT set globals. Functions
# only. tmux-resurrect/scripts/helpers.sh is the template for "sourced library,
# zero side effects". Sourcing must be safe under `set -u` and inside other
# strict scripts.

# GOTCHA: `show-option -gqv` returns the EFFECTIVE value of a built-in option
# even when it is unset (it returns the default). e.g. an unset `key-table`
# yields "root", unset `renumber-windows` yields "on". So tmux_get_opt tells you
# the effective value, NOT whether it was explicitly set. For "was it set?" use
# tmux_is_set (and only for @-options — see above).

# GOTCHA: window-scoped options (window_layout, window_name, ...) are NOT global
# and CANNOT be read by tmux_get_opt (which uses -g). PRD §9 saves window_layout
# for the active window — that read is the caller's job (targeted show-option -gv
# -t <window> or display-message -p '#{window_layout}'). utils.sh is strictly a
# GLOBAL option/hook helper layer. Do NOT add a -t target param here (YAGNI; the
# one window-scoped read is special-cased at its single call site).

# GOTCHA: show-hooks -g <hook> exits 0 even when the hook is cleared (it then
# prints the bare hook name with no [N] index and no command). So "is the hook
# set?" is NOT the exit code — it is whether the output contains a `[` index
# marker / a command. tmux_get_hook returns the raw output; the caller decides.
# (No tmux_hook_is_set helper is required by the contract — restore replays the
# saved blob, it does not re-probe.)

# GOTCHA: set-hook -gu <hook> clears ALL indices of the hook array (mirrors
# set-option -gu on an array option). Verified: 2 appended hooks collapse to the
# bare name after -gu. This is exactly what tmux_clear_hook wraps.

# GOTCHA: shellcheck SC2155 — never write `local x="$(cmd)"`. Always:
#   local x
#   x="$(cmd)"
# (Also masks the tmux return code — relevant if you ever want to inspect it.)

# GOTCHA: Indent with TABS (sessionx/resurrect/session-history majority), not
# spaces. shfmt is NOT installed; enforce tabs by hand.
```

## Implementation Blueprint

### Data models and structure

No runtime data model — only function definitions. There are no `readonly`
constants (the option-name prefix `@livepicker-orig-` is inlined in
`tmux_save_opt` as a literal; it is short, singular, and matches the PRD §9 /
system_context §3 naming).

### Implementation Tasks (ordered by dependencies)

```yaml
Task 1: CREATE scripts/utils.sh
  - STRUCTURE: shebang `#!/usr/bin/env bash`; header comment block stating
    module purpose ("general-purpose tmux option & hook primitives for the
    save/restore paths"), "sourced library, NO side effects", and the two traps
    it centralizes (TRAP 1 status-format -gu; TRAP 2 array hook). Then
    `set -u` on its own line (NO -e, NO -o pipefail).
  - IMPLEMENT tmux_get_opt(name, [default]):
      local v
      v="$(tmux show-option -gqv "$1")"
      [ -n "$v" ] && echo "$v" || echo "${2:-}"
    (The `${2:-}` makes the default OPTIONAL and safe under `set -u`.)
  - IMPLEMENT tmux_set_opt(name, value):
      tmux set-option -g "$1" "$2"
    (Caller passes the indexed name for arrays, e.g. "status-format[0]".)
  - IMPLEMENT tmux_unset_opt(name):
      tmux set-option -gu "$1"
    (Whole-array when `name` has no index: "status-format" clears all indices
    and tmux re-composes defaults — TRAP 1 restore. Indexed: "status-format[4]"
    clears just [4].)
  - IMPLEMENT tmux_save_opt(orig_name, src_name):
      local v
      v="$(tmux show-option -gqv "$2")"
      tmux set-option -g "@livepicker-orig-$1" "$v"
    (Reads src_name; writes @livepicker-orig-${orig_name}. orig_name MUST be
    bracket-free — see Known Gotchas. For non-array options call with both args
    identical: tmux_save_opt status status.)
  - IMPLEMENT tmux_is_set(name) — mirror tubular __tubular_is_set VERBATIM:
      tmux show-options -g "$1" >/dev/null 2>&1
    (Return code = tmux exit code. Reliable for @-options ONLY — comment must
    state the status-format[n] limitation per research FINDING 2.)
  - IMPLEMENT tmux_get_hook(hookname):
      tmux show-hooks -g "$1"
    (Returns FULL raw multi-line output: "hookname[0] cmd\nhookname[1] cmd".
    Caller strips the "hookname[N] " prefix to recover commands for replay —
    see system_context §7 recipe.)
  - IMPLEMENT tmux_clear_hook(hookname):
      tmux set-hook -gu "$1"
    (Clears ALL indices of the hook array.)
  - FOLLOW pattern: ~/.config/tmux/plugins/tmux-resurrect/scripts/helpers.sh
    (sourced library: functions only, no top-level tmux calls, no SCRIPT_DIR).
  - NAMING: tmux_<verb>_<noun>; snake_case; tmux_ prefix (disjoint from
    options.sh's get_opt/opt_* so both coexist when sourced together).
  - STYLE: tabs for indent; `local` for all locals (declared FIRST); double-
    quote every expansion.
  - COMMENTS: each function gets a # docblock: signature, what tmux command it
    wraps, return/exit semantics, and the relevant gotcha (esp. tmux_is_set's
    @-only limitation and tmux_save_opt's bracket-free dest requirement).
  - PLACEMENT: scripts/utils.sh
  - NO SIDE EFFECTS: do NOT call tmux at top level, do NOT echo at top level,
    do NOT set globals, do NOT compute SCRIPT_DIR.

Task 2: VALIDATE (manual smoke — no harness exists yet; P1.M7 invents one)
  - RUN: bash -n scripts/utils.sh
  - RUN: shellcheck scripts/utils.sh   (expect 0 findings)
  - RUN a throwaway smoke script (Validation Loop §2) against an ISOLATED test
    socket OR the live server, then DELETE it (do NOT commit a tests/ file).
  - VERIFY no-side-effects: snapshot `tmux show-options -g | sort | cksum` AND
    `tmux show-hooks -g | cksum` before & after sourcing utils.sh in a subshell;
    assert both identical.
  - VERIFY each primitive against the empirical findings (see Validation Loop).
```

### Implementation Patterns & Key Details

```bash
#!/usr/bin/env bash
# scripts/utils.sh — tmux-livepicker general-purpose tmux option & hook primitives.
#
# Sourced library (NOT executed). Provides the safe wrappers around show-option /
# set-option / show-hooks / set-hook that the save (livepicker.sh) and restore
# (restore.sh) paths build on, so neither re-implements the two environment traps
# documented in plan/001_fd5d622d3939/architecture/system_context.md §4:
#   TRAP 1 — status-format restore MUST be `set-option -gu status-format` (unset
#            all → tmux re-composes defaults), NOT literal replay of captured
#            strings. tmux_unset_opt status-format does exactly this.
#   TRAP 2 — session-window-changed is array-indexed with -b; save the WHOLE
#            show-hooks line. tmux_get_hook returns it verbatim; tmux_clear_hook
#            clears every index via set-hook -gu.
#
# CONTRACT: sourcing this file has NO side effects — it touches no tmux state
# and prints nothing. All work happens inside functions called by the consumer.
# Coexists with options.sh (get_opt/opt_*): the tmux_ prefix is disjoint.

set -u   # NOT -e (show-option/show-hooks legitimately return non-zero); NOT -o pipefail.

# $1: option name, $2: optional default (returned when option is unset/empty).
# Reads the EFFECTIVE global value (built-in options return their default even
# when unset — e.g. key-table -> "root"). For "was it explicitly set?" use
# tmux_is_set (and note its @-options-only limitation).
tmux_get_opt() {
	local v
	v="$(tmux show-option -gqv "$1")"
	[ -n "$v" ] && echo "$v" || echo "${2:-}"
}

# $1: option name, $2: value. Sets a global option. For array options pass the
# indexed name, e.g. tmux_set_opt "status-format[0]" "#(...)".
tmux_set_opt() {
	tmux set-option -g "$1" "$2"
}

# $1: option name. Unsets (→ tmux default). For an array option with NO index
# (e.g. "status-format") this clears EVERY index and tmux re-composes defaults —
# this is the TRAP-1 status-format restore. An indexed name ("status-format[4]")
# clears just that index.
tmux_unset_opt() {
	tmux set-option -gu "$1"
}

# $1: orig_name (bracket-free dest suffix), $2: src_name (option to read).
# Snapshots src_name's value into @livepicker-orig-${orig_name}.
# GOTCHA: tmux rejects brackets in @-option names ("not an array" error), so
# orig_name MUST be bracket-free. For status-format indices pass a sanitized
# suffix: tmux_save_opt "status-format-0" "status-format[0]". For ordinary
# options pass both args identical: tmux_save_opt status status.
tmux_save_opt() {
	local v
	v="$(tmux show-option -gqv "$2")"
	tmux set-option -g "@livepicker-orig-$1" "$v"
}

# $1: option name. Exit-code probe (return code = tmux exit code): 0 = set
# (even if set to ""), 1 = unset. Mirrors tubular's __tubular_is_set verbatim.
#
# LIMITATION (verified on tmux 3.6b): reliable ONLY for @-user-options (which
# have no built-in default). For built-in options (status, key-table, ...) and
# array indices (status-format[n]) the exit code is ALWAYS 0 — set, default, or
# never-existed all return 0. DO NOT use this to decide status-format save/
# restore; use unconditional tmux_unset_opt status-format there (TRAP 1).
tmux_is_set() {
	tmux show-options -g "$1" >/dev/null 2>&1
}

# $1: hook name. Prints the FULL raw show-hooks output (multi-line, one
# "hookname[N] <cmd>" per index). When the hook is cleared, prints just the bare
# hook name (no [N], no cmd) and still exits 0 — so "is it set?" is decided by
# grepping for a '[' marker, not by the exit code. Caller strips the
# "hookname[N] " prefix to recover commands for replay (system_context §7).
tmux_get_hook() {
	tmux show-hooks -g "$1"
}

# $1: hook name. Clears EVERY index of the hook array (mirrors set-option -gu
# on an array option). Used by activate to suppress session-window-changed.
tmux_clear_hook() {
	tmux set-hook -gu "$1"
}
```

NOTE for the implementer: the block above is the complete, ready file body. Use
it as-is; the only allowed deviation is comment phrasing. Do NOT add a
`tmux_hook_is_set` helper (not required by the contract; restore replays the
saved blob, it does not re-probe). Do NOT add a `-t target` parameter to any
helper (the single window-scoped read, `window_layout`, is special-cased at its
call site — utils.sh is strictly global).

### Integration Points

```yaml
SOURCING (consumed by, in later tasks — DO NOT implement these now):
  - scripts/state.sh          (P1.M1.T3) builds @livepicker-* state accessors on tmux_set_opt/tmux_get_opt/tmux_is_set
  - scripts/livepicker.sh     (P1.M4.T1) save path: tmux_save_opt status/key-table/renumber-windows; tmux_get_hook session-window-changed; tmux_clear_hook (if suppress on)
  - scripts/restore.sh        (P1.M5.T3) restore: tmux_unset_opt status-format (TRAP 1), tmux_set_opt for key-table/renumber-windows/status, replay saved hook
  - scripts/preview.sh        (P1.M3.T1) tmux_is_set "@livepicker-linked-id" / tmux_get_opt for state probes

CONFIG:
  - add to: nothing. This file defines helpers only. tmux_save_opt is the only
    writer and it writes @livepicker-orig-* keys at the caller's request, never
    at source time.

ROUTES / DATABASE / MIGRATIONS: none — tmux option/hook helper library only.
```

## Validation Loop

### Level 1: Syntax & Style (Immediate Feedback)

```bash
# Run after creating the file — fix before proceeding.
bash -n scripts/utils.sh                       # syntax check; expect no output, exit 0
shellcheck scripts/utils.sh                    # lint; expect 0 findings
# Tabs-not-spaces sanity (shfmt is NOT installed; verify manually):
grep -Pn '^    ' scripts/utils.sh && echo "FAIL: 4-space indent found, use tabs" || echo "OK: no leading 4-space groups"

# Expected: all three clean. If shellcheck reports SC2155 on any helper, you
# collapsed `local` + assign onto one line — split them (see Known Gotchas).
```

### Level 2: Unit Tests (Component Validation)

There is no test harness yet (P1.M7.T1/T2 invents the socket-isolation shim).
For THIS subtask, run a throwaway smoke script against the live server, then
delete it. (The probes below mutate only @livepicker-orig-* / @livepicker-test-*
keys and a throwaway hook, all cleaned up at the end — safe on the live server.
For full isolation, prefix with the P1.M7 socket shim once it exists.)

```bash
# Throwaway smoke (do NOT commit a tests/ dir):
cat > /tmp/smoke_utils.sh <<'EOF'
#!/usr/bin/env bash
set -u
source "$(dirname "$1")/scripts/utils.sh" "$1"

pass=0; fail=0
assert_rc() { # $1 desc $2 expected_rc  (function + args follow via eval-free shift)
    local desc="$1" exp="$2"; shift 2; "$@" >/dev/null 2>&1
    if [ "$?" = "$exp" ]; then pass=$((pass+1)); else fail=$((fail+1)); printf 'FAIL %s: got rc=%s want %s\n' "$desc" "$?" "$exp"; fi
}
assert_eq() { # $1 desc $2 actual $3 expected
    if [ "$2" = "$3" ]; then pass=$((pass+1)); else fail=$((fail+1)); printf 'FAIL %s: got [%s] want [%s]\n' "$1" "$2" "$3"; fi
}

# --- tmux_is_set: reliable for @-options ---
assert_rc "is_set @livepicker-fg (SET)"    0  tmux_is_set "@livepicker-fg"
assert_rc "is_set @livepicker-key (SET)"   0  tmux_is_set "@livepicker-key"
assert_rc "is_set @livepicker-type (UNSET)" 1 tmux_is_set "@livepicker-type"
# --- tmux_is_set LIMITATION: always 0 for status-format[n] (document this, do not "fix") ---
assert_rc "is_set status-format[5] (NEVER SET -> still 0)" 0 tmux_is_set "status-format[5]"

# --- tmux_get_opt / tmux_save_opt ---
assert_eq "get_opt status effective"   "$(tmux_get_opt status)"        "$(tmux show-option -gv status)"
assert_eq "get_opt key-table effective" "$(tmux_get_opt key-table)"    "$(tmux show-option -gv key-table)"
tmux_save_opt status status
assert_eq "save_opt wrote orig-status" "$(tmux show-option -gv "@livepicker-orig-status")" "$(tmux show-option -gv status)"
# --- tmux_save_opt bracket-free dest (GOTCHA): bracketed dest is REJECTED ---
tmux set-option -g "@livepicker-orig-status-format[0]" "X" >/dev/null 2>&1
assert_rc "bracketed @-dest REJECTED (rc=1)" 1 sh -c 'tmux set-option -g "@livepicker-orig-status-format[0]" X'

# --- tmux_set_opt / tmux_unset_opt ---
tmux_set_opt "@livepicker-test-set" "hello"; assert_eq "set_opt value" "$(tmux_get_opt "@livepicker-test-set")" "hello"
tmux_unset_opt "@livepicker-test-set"; assert_eq "unset_opt -> empty" "$(tmux_get_opt "@livepicker-test-set")" ""

# --- tmux_get_hook returns FULL multi-line output with [N] marker ---
hook_out="$(tmux_get_hook session-window-changed)"
case "$hook_out" in *"session-window-changed["*"] "*) pass=$((pass+1));; *) fail=$((fail+1)); printf 'FAIL get_hook: no [N] marker in [%s]\n' "$hook_out";; esac

# --- tmux_clear_hook collapses the hook to the bare name (clears all indices) ---
tmux set-hook -g window-linked "run-shell /tmp/a.sh"; tmux set-hook -ag window-linked "run-shell /tmp/b.sh"
tmux_clear_hook window-linked
cleared="$(tmux_get_hook window-linked)"
case "$cleared" in *"["*"] "*) fail=$((fail+1)); printf 'FAIL clear_hook: still has index in [%s]\n' "$cleared";; *) pass=$((pass+1));; esac

# --- cleanup (restore user env; remove throwaway keys) ---
tmux set-hook -gu window-linked 2>/dev/null
tmux set-option -gu "@livepicker-orig-status" 2>/dev/null
tmux set-option -gu "@livepicker-test-set" 2>/dev/null
tmux set-option -gu "@livepicker-orig-status-format[0]" 2>/dev/null

printf 'PASS=%d FAIL=%d\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
EOF
bash /tmp/smoke_utils.sh "$(pwd)"; rc=$?
rm -f /tmp/smoke_utils.sh
exit $rc
# Expected: PASS=13 FAIL=0, exit 0. The two LIMITATION assertions (status-format[5]
# rc=0; bracketed dest rc=1) are EXPECTED behaviors, not failures — they prove
# the gotchas are encoded correctly.
```

### Level 3: Integration Testing (System Validation)

```bash
# No-side-effects proof: sourcing utils.sh must NOT change any tmux option OR hook.
before_opt="$(tmux show-options -g | sort | cksum)"
before_hook="$(tmux show-hooks -g | cksum)"
( set -u; source ./scripts/utils.sh; )   # subshell; source only
after_opt="$(tmux show-options -g | sort | cksum)"
after_hook="$(tmux show-hooks -g | cksum)"
[ "$before_opt" = "$after_opt" ] && [ "$before_hook" = "$after_hook" ] \
  && echo "OK: no side effects (options + hooks unchanged)" \
  || echo "FAIL: tmux state mutated"

# TRAP 1 proof: tmux_unset_opt status-format returns to tmux defaults (re-composed).
tmux set-option -g "status-format[4]" "SENTINEL-$(date +%s)"
tmux_unset_opt "status-format[4]"
[ -z "$(tmux show-options -gv "status-format[4]" 2>/dev/null)" ] && echo "OK: indexed unset clears [4]" || echo "FAIL: [4] survived"
# Whole-array unset (do NOT run on the user's live bar without restore — instead
# verify the mechanism on a throwaway @-array-free surrogate: confirm
# `tmux_unset_opt status-format` leaves [0] at the default, which is the goal):
tmux_unset_opt status-format
[ -n "$(tmux show-options -gv "status-format[0]" 2>/dev/null)" ] && echo "OK: whole-array -gu re-composed default [0]" || echo "FAIL: [0] blank"

# Expected: all OK. (status-format is left at default after this — which is the
# correct tubular-compatible state. No cleanup needed.)
```

### Level 4: Creative & Domain-Specific Validation

```bash
# Hook save/restore round-trip (the TRAP-2 path end-to-end, using utils.sh only).
# Uses window-linked (a harmless hook) to avoid disturbing the user's real
# session-window-changed hook.
source ./scripts/utils.sh
tmux_clear_hook window-linked
tmux set-hook -g window-linked "run-shell -b /tmp/a.sh"
tmux set-hook -ag window-linked "run-shell /tmp/b.sh"
saved="$(tmux_get_hook window-linked)"
printf 'saved hook blob:\n%s\n' "$saved"
# Strip the "window-linked[N] " prefix per system_context §7 and replay each cmd:
while IFS= read -r line; do
    cmd="$(printf '%s\n' "$line" | sed 's/^window-linked\[[0-9]*\] //')"
    [ -n "$cmd" ] && tmux set-hook -g window-linked "$cmd"
done <<EOF
$saved
EOF
echo "replayed hook:"; tmux_get_hook window-linked
tmux_clear_hook window-linked   # cleanup
# Expected: the replayed hook matches the saved blob (two indices, -b preserved
# on the first). Proves tmux_get_hook + tmux_clear_hook + the strip recipe work
# together — the exact sequence restore.sh (P1.M5.T3) will use for
# session-window-changed.

# Cross-check: utils.sh and options.sh coexist when both sourced (no name clash).
bash -c 'set -u; source ./scripts/options.sh; source ./scripts/utils.sh; \
         type get_opt opt_type >/dev/null && type tmux_get_opt tmux_is_set >/dev/null \
         && echo "OK: both libraries sourced, no collision" \
         || echo "FAIL: name clash"'
# Expected: OK (requires options.sh to exist from P1.M1.T1.S1; if that PRP is
# not yet landed, this check is deferred to integration — not a blocker for
# utils.sh itself).
```

## Final Validation Checklist

### Technical Validation

- [ ] `bash -n scripts/utils.sh` exits 0 with no output.
- [ ] `shellcheck scripts/utils.sh` reports 0 findings (no SC2155).
- [ ] No 4-space indents (`grep -Pn '^    '` is empty); tabs only.
- [ ] Smoke script: PASS=13 FAIL=0, including both LIMITATION assertions
      (status-format[5] rc=0; bracketed @-dest rc=1).

### Feature Validation

- [ ] All 7 functions present with the exact signatures/wrappers in the table.
- [ ] `tmux_is_set` body byte-identical to tubular `__tubular_is_set`.
- [ ] `tmux_is_set` comment states the @-options-only limitation (FINDING 2).
- [ ] `tmux_save_opt` writes to `@livepicker-orig-${orig_name}` (first arg);
      comment states the bracket-free requirement (FINDING 4).
- [ ] `tmux_get_hook` returns raw multi-line `show-hooks` output (prefix intact).
- [ ] `tmux_clear_hook` collapses a multi-index hook to the bare name.
- [ ] No-side-effects proof passes (options cksum AND hooks cksum unchanged).
- [ ] TRAP-1 proof: `tmux_unset_opt status-format` re-composes default `[0]`.

### Code Quality Validation

- [ ] Shebang `#!/usr/bin/env bash`; `set -u` only (no `-e`, no `-o pipefail`).
- [ ] `local` declared before assign in every helper that uses locals (SC2155-safe).
- [ ] All expansions double-quoted; tabs for indent.
- [ ] One docblock per function documenting signature, wrapped command, and gotcha.
- [ ] No top-level `tmux` call, no top-level `echo`, no `SCRIPT_DIR`, no globals.
- [ ] `tmux_` prefix disjoint from options.sh's `get_opt`/`opt_*` (no collision).

### Documentation & Deployment

- [ ] Header comment states: sourced library, no side effects, the two traps it
      centralizes (TRAP 1 status-format `-gu`; TRAP 2 array hook), and the
      coexistence with options.sh.
- [ ] No new env vars introduced (helpers only invoke `tmux`).
- [ ] No README/doc file created (DOCS = Mode A internal helper; surfaces in
      README at P1.M8.T1.S1).

---

## Anti-Patterns to Avoid

- ❌ Don't add `set -e`/`-o pipefail` — `show-option`/`show-hooks` legitimately
  return non-zero (unset options, cleared hooks) and must not abort the caller.
- ❌ Don't collapse `local v; v="$(...)"` into `local v="$(...)"` (SC2155; masks
  the tmux return code — relevant to tmux_is_set's semantics).
- ❌ Don't "fix" `tmux_is_set` to handle `status-format[n]` — the exit-code
  always-0 behavior is a tmux fact, not a bug. Document it; steer status-format
  restore to unconditional `tmux_unset_opt status-format` (TRAP 1).
- ❌ Don't write `@livepicker-orig-status-format[0]` (brackets rejected). Use a
  bracket-free `orig_name` arg: `tmux_save_opt "status-format-0" "status-format[0]"`.
- ❌ Don't add a `tmux_hook_is_set` helper — not required; restore replays the
  saved blob. (YAGNI; the contract lists only get_hook + clear_hook.)
- ❌ Don't add a `-t target` parameter to any helper — utils.sh is strictly
  GLOBAL. The one window-scoped read (`window_layout`) is special-cased at its
  single call site in livepicker.sh.
- ❌ Don't have utils.sh source options.sh — keep it self-contained. The two
  libraries are independent; consumers source both as needed.
- ❌ Don't strip the `hookname[N] ` prefix inside `tmux_get_hook` — return RAW
  `show-hooks` output (the contract says "FULL multi-line output"). Stripping is
  the caller's job (restore.sh), per the system_context §7 recipe.
- ❌ Don't create a `tests/` directory or committed test file — the harness is
  invented in P1.M7.T1/T2; this subtask validates via throwaway smoke only.
- ❌ Don't compute `SCRIPT_DIR`/`CURRENT_DIR` — this is a sourced library, not an
  entry point (mirror resurrect's helpers.sh).
- ❌ Don't run `tmux` at the top level of the file (violates "no side effects"
  and breaks sourcing inside other strict scripts).
- ❌ Don't "normalize" show-option vs show-options to one form — follow the table:
  `tmux_get_opt` uses singular (matches options.sh/siblings); `tmux_is_set` uses
  plural (matches tubular verbatim). The mix is intentional and documented.

---

## Confidence Score

**9 / 10** for one-pass success. Rationale: the deliverable is a single small
sourced library whose seven function bodies are given nearly verbatim above,
each mirroring an idiom already proven in tubular/resurrect/session-history. The
two environment traps it centralizes (TRAP 1 status-format `-gu`; TRAP 2 array
hook) are verified live and encoded directly in the wrappers + comments. The
two CONTRACT CORRECTIONS (the false array-index exit-code claim and the
bracket-rejection gotcha) are backed by empirical proof in the research file and
explicitly surfaced in Known Gotchas + the smoke assertions, so the implementer
cannot accidentally propagate them. Tools verified present: `tmux 3.6b`,
`bash 5.3.15`, `shellcheck 0.11.0`. Residual risk: a typo in a function name or
a missed `local`-before-assign — both caught deterministically by `shellcheck`
and the 13-assertion smoke script.
