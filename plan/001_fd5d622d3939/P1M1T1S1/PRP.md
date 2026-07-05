# PRP — P1.M1.T1.S1: options.sh — get_opt helper + all defaults

---

## Goal

**Feature Goal**: A side-effect-free, sourceable Bash library `scripts/options.sh`
that exposes (a) a `get_opt(name, default)` helper mirroring the exact idiom used
by every sibling plugin, and (b) one named accessor function per `@livepicker-*`
option (PRD §11) with the PRD default baked in — so every downstream script
(P1.M2–P1.M6) can read configuration without re-typing default literals.

**Deliverable**: The single file `scripts/options.sh` (created — it does not
exist yet). It defines functions only; sourcing it touches no tmux state.

**Success Definition**:
- `bash -n scripts/options.sh` passes; `shellcheck scripts/options.sh` is clean.
- Sourcing the file defines `get_opt` plus all 18 `opt_*` accessors and runs **zero**
  `tmux` invocations (verified by a no-side-effect smoke check).
- `opt_fg` returns `#ffffff` (the live user override already set in `tmux.conf` —
  proving `show-option -gqv` surfaces overrides over defaults), while an unset
  option like `opt_type` returns its PRD default `session`.

## User Persona (if applicable)

**Target User**: The implementing AI agent (and downstream scripts) consuming
configuration. Not end-user facing.

**Use Case**: Any script in P1.M2–P1.M6 writes `opt_type`, `opt_next_key`,
`opt_preview_mode`, etc. instead of repeating `tmux show-option` + default literals.

**Pain Points Addressed**: Default-literal duplication/typos across ~8 scripts
(e.g. mistyping `C-M-Tab` vs `C-M-TAB`); inconsistent override surfacing.

---

## Why

- **Single source of truth for defaults.** PRD §11 lists 18 options with exact
  defaults; hardcoding these in every consumer guarantees drift. Centralizing them
  in named accessors means a default change is a one-line edit.
- **Foundation for the whole MVP.** This is the first script (M1.T1) —
  `utils.sh` (T2), `state.sh` (T3), `plugin.tmux` (T4), and every renderer/preview/
  input-handler/restore script sources or mirrors the conventions established here.
- **Proven idiom.** All three relevant siblings (session-history, sessionx,
  resurrect) ship the identical helper body. Reusing it is zero-risk and keeps
  livepicker stylistically consistent with its closest sibling (session-history).

## What

A sourced Bash library that:
1. Implements `get_opt(name, default)` with the EXACT sibling idiom.
2. Exposes `opt_<suffix>()` accessors for all 18 PRD §11 options, each baking in
   its exact default.
3. Is **pure** — no `tmux` calls at source time, no global mutation, no output.

### Success Criteria

- [ ] File exists at `scripts/options.sh`, shebang `#!/usr/bin/env bash`, body
      starts with `set -u` (NO `set -e`, NO `set -o pipefail`).
- [ ] `get_opt()` body is byte-identical in behavior to the sibling idiom:
      `local v; v="$(tmux show-option -gqv "$1")"; [ -n "$v" ] && echo "$v" || echo "$2"`.
- [ ] All 18 accessors exist and return their exact PRD default when the option is
      unset (table below).
- [ ] User overrides win: with the live `@livepicker-fg #ffffff`, `opt_fg` → `#ffffff`.
- [ ] `@livepicker-key` (REQUIRED, no default) is surfaced via `opt_key` returning
      the user value or empty string (guard lives in `plugin.tmux`, P1.M1.T4).
- [ ] `shellcheck scripts/options.sh` → 0 findings; `bash -n` → 0 errors.
- [ ] No side effects: sourcing the file does not change any tmux option.

## All Needed Context

### Context Completeness Check

_Pass_: A developer who has never seen this repo can implement this from (a) the
verbatim sibling helper quoted below, (b) the 18-row default table, and (c) the
two validation commands. No inference about tmux internals is required.

### Documentation & References

```yaml
# MUST READ - the single authoritative pattern to mirror
- file: ~/.config/tmux/plugins/tmux-session-history/session_history.tmux
  why: Lines 14-18 are the canonical get_tmux_option idiom this task mirrors as get_opt.
  pattern: |
    # $1: option name, $2: default value
    get_tmux_option() {
        local value
        value="$(tmux show-option -gqv "$1")"
        [ -n "$value" ] && echo "$value" || echo "$2"
    }
  critical: Declare `local` FIRST, then assign on a separate line. This avoids
            shellcheck SC2155 (declare+assign masks return code). Do NOT collapse to
            `local value="$(...)"`.

- file: ~/.config/tmux/plugins/tmux-session-history/scripts/session_history.sh
  why: Lines 1-30 establish the house style: `#!/usr/bin/env bash`, `set -u` (NO -e),
       `local` everywhere, heavy "$var" quoting. Mirror exactly.
  pattern: Top-of-file header comment block explaining the module; `set -u` on its own
           line after the comment; functions use `local` locals.

- file: ~/.config/tmux/plugins/tmux-resurrect/scripts/helpers.sh
  why: Lines 19-26 — the SAME idiom in a sourced helper library (proves the pattern
       transfers to a sourced, non-entry-point module like options.sh).
  pattern: Sourced library defines functions only; no top-level side effects.

- docfile: plan/001_fd5d622d3939/architecture/sibling_plugins_and_env.md
  why: §4 quotes the identical helper across session-history/sessionx/resurrect/tubular
       and mandates `get_opt` mirror it; §5 mandates shebang + `set -u` + tabs + `local`.
  section: "§4 SCRIPT_DIR computation & helper sourcing" and "§5 Shell style"

- docfile: plan/001_fd5d622d3939/architecture/sibling_plugins_and_env.md
  why: §0 fact 1 confirms `show-option -gqv` surfaces live user overrides (the
       `@livepicker-fg #ffffff` already declared in tmux.conf is the proof point).
  section: "§0 TL;DR" + "§2 Plugin loading model" (the two pre-declared options)

- docfile: PRD.md
  why: The options table is the authoritative default source. Copy defaults verbatim.
  section: "§11. Configuration options" (table) and "§12. File layout" (scripts/options.sh)
```

### Current Codebase tree

```bash
tmux-livepicker/
  PRD.md
  plan/001_fd5d622d3939/{architecture/, tasks.json, prd_snapshot.md}
  .gitignore
  # NOTE: NO scripts/ dir yet — greenfield. NO plugin.tmux yet.
  # NO test harness yet (invented in P1.M7).
```

### Desired Codebase tree with files to be added and responsibility of file

```bash
scripts/
  options.sh   # NEW. Sourced library: get_opt() + 18 opt_* accessors. No side effects.
```

### Known Gotchas of our codebase & Library Quirks

```bash
# CRITICAL: `show-option` vs `show-options`. tmux accepts both, but the siblings
# use the SINGULAR `show-option` (session_history.tmux:16, resurrect helpers.sh:20).
# Use `show-option -gqv` to match siblings exactly. (`-g` global, `-q` quiet,
# `-v` value-only.) For @-prefixed user options `-gqv` is correct (no `-w`).

# CRITICAL: `@livepicker-key` is REQUIRED and has NO default. Its accessor must
# return the user value OR empty string (get_opt with "" default does this).
# The "is it set?" guard + display-message is plugin.tmux's job (P1.M1.T4), NOT
# options.sh. Do NOT add is_set logic here — out of scope (that probe pattern,
# `__tubular_is_set`, belongs to utils.sh P1.M1.T2.S1).

# CRITICAL: Some options are SPACE-SEPARATED MULTI-KEY LISTS, not single keys:
#   nav-next-keys="Down j", nav-prev-keys="Up k", confirm-keys=Enter (single),
#   cancel-keys=Escape (single), backspace-keys=BSpace (single).
# The accessor returns the RAW string. Callers (input-handler/livepicker) must
# WORD-SPLIT (e.g. `for k in $(opt_nav_next_keys)`) — do NOT pre-split here.
# Keep accessors dumb string-returners.

# CRITICAL: next-key/prev-key (C-M-Tab / C-M-BTab) are SINGLE repurposed
# window-nav keys — DISTINCT from nav-next-keys/nav-prev-keys (supplemental
# Down/j, Up/k). Do not merge them. Discovery-of-window-nav-keys is OPTIONAL
# and lives in livepicker.sh (P1.M4.T4), NOT here — options.sh only surfaces
# the literal hardcoded defaults.

# CRITICAL: Booleans are the literal strings "on"/"off" (create, suppress-window-hook,
# show-count). Downstream compares `[ "$(opt_create)" = "on" ]`. Do NOT normalize
# to 0/1 here — that is downstream's concern and would diverge from PRD §11 wording.

# CRITICAL: This file is SOURCED, not executed. It must NOT compute SCRIPT_DIR,
# NOT call tmux at top level, NOT print anything. Functions only. Resurrect's
# helpers.sh is the template for "sourced library, zero side effects".

# GOTCHA: shellcheck SC2155 — never write `local x="$(cmd)"`. Always:
#   local x
#   x="$(cmd)"

# GOTCHA: Indent with TABS (sessionx/resurrect/session-history majority), not spaces.
# shfmt is NOT installed in this env, so do not rely on it; enforce tabs by hand.
```

## Implementation Blueprint

### Data models and structure

There is no runtime data model — only function definitions and (optionally)
`readonly` default constants. The authoritative option→default mapping (copy these
EXACTLY — they are PRD §11 verbatim):

| Option (`@livepicker-<suffix>`) | Accessor | Exact default | Kind |
|---|---|---|---|
| `key` | `opt_key` | *(none — required)* | single key, required |
| `type` | `opt_type` | `session` | enum: session\|window |
| `create` | `opt_create` | `on` | bool (on/off) |
| `next-key` | `opt_next_key` | `C-M-Tab` | single key |
| `prev-key` | `opt_prev_key` | `C-M-BTab` | single key |
| `nav-next-keys` | `opt_nav_next_keys` | `Down j` | space-list |
| `nav-prev-keys` | `opt_nav_prev_keys` | `Up k` | space-list |
| `confirm-keys` | `opt_confirm_keys` | `Enter` | space-list |
| `cancel-keys` | `opt_cancel_keys` | `Escape` | space-list |
| `backspace-keys` | `opt_backspace_keys` | `BSpace` | space-list |
| `preview-mode` | `opt_preview_mode` | `live` | enum: live\|snapshot\|off |
| `suppress-window-hook` | `opt_suppress_window_hook` | `on` | bool (on/off) |
| `fg` | `opt_fg` | `default` | tmux style/color |
| `bg` | `opt_bg` | `default` | tmux style/color |
| `highlight-fg` | `opt_highlight_fg` | `black` | tmux style/color |
| `highlight-bg` | `opt_highlight_bg` | `yellow` | tmux style/color |
| `show-count` | `opt_show_count` | `on` | bool (on/off) |
| `status-format-index` | `opt_status_format_index` | `0` | integer (0–9) |

Accessor-name rule: `opt_` + the option suffix with each `-` → `_`
(e.g. `next-key` → `opt_next_key`, `nav-next-keys` → `opt_nav_next_keys`).
This keeps accessor names bash-idiomatic (hyphens in function names are legal but
fragile/subtraction-ambiguous; underscores are the safe, conventional choice).

Behavioral semantics (NOT implemented here — documented so options.sh comments
are accurate and downstream tasks have a contract):
- `create=on`: in **session** mode, create a new session from the query on Enter
  when nothing matches; in **window** mode nothing is ever created. (PRD §6/§11,
  consumed by input-handler P1.M6.T3.)
- `cancel-keys`: "Clear the query, or cancel if the query is empty." — behavior
  lives in input-handler P1.M6.T4; options.sh only returns the key list.
- `next-key`/`prev-key` default to THIS user's window-nav keys so the feature
  works out-of-the-box; explicit options always win over discovery (P1.M4.T4).

### Implementation Tasks (ordered by dependencies)

```yaml
Task 1: CREATE scripts/options.sh
  - STRUCTURE: shebang line; header comment block (module purpose, "sourced, no
    side effects"); `set -u` on its own line (NO -e, NO -o pipefail).
  - IMPLEMENT get_opt(name, default): mirror session_history.tmux:14-18 EXACTLY
    (`local` first, assign next, SC2155-safe). Public API.
  - IMPLEMENT 18 accessors opt_<suffix>() per the table above. Each body is a
    ONE-LINER delegating to get_opt with the baked-in default, e.g.:
      opt_type()            { get_opt "@livepicker-type" "session"; }
      opt_next_key()        { get_opt "@livepicker-next-key" "C-M-Tab"; }
      opt_nav_next_keys()   { get_opt "@livepicker-nav-next-keys" "Down j"; }
      opt_preview_mode()    { get_opt "@livepicker-preview-mode" "live"; }
      opt_key()             { get_opt "@livepicker-key" ""; }   # required, no default
    ...one per row of the table.
  - FOLLOW pattern: ~/.config/tmux/plugins/tmux-resurrect/scripts/helpers.sh
    (sourced library: functions only, no top-level tmux calls, no SCRIPT_DIR).
  - NAMING: opt_<suffix-with-underscores>; snake_case; one accessor per option.
  - STYLE: tabs for indent; `local` for all locals; double-quote all expansions.
  - COMMENTS: a short one-line comment above each accessor giving its PRD §11
    default and kind (single/space-list/bool/enum) so the file is self-documenting.
  - PLACEMENT: scripts/options.sh
  - NO SIDE EFFECTS: do NOT call tmux, do NOT echo at top level, do NOT set globals.

Task 2: VALIDATE (manual smoke — no harness exists yet; P1.M7 invents one)
  - RUN: bash -n scripts/options.sh
  - RUN: shellcheck scripts/options.sh   (expect 0 findings)
  - RUN a one-off smoke script (see Validation Loop §2) and then DELETE it (do not
    commit a tests/ file — the real harness is P1.M7.T1/T2).
  - VERIFY no-side-effects: snapshot `tmux show-options -g` before & after sourcing
    options.sh in a subshell; assert identical.
  - VERIFY override-surfacing: assert `opt_fg` == `#ffffff` (live user override),
    and `opt_type` == `session` (unset → default).
```

### Implementation Patterns & Key Details

```bash
#!/usr/bin/env bash
# scripts/options.sh — tmux-livepicker option accessors.
#
# Sourced library (NOT executed). Defines get_opt() plus one opt_<name>()
# accessor per @livepicker-* option (PRD §11), each baking in its PRD default.
# Mirrors the get_tmux_option idiom shared by session-history / sessionx /
# resurrect (see plan/001_fd5d622d3939/architecture/sibling_plugins_and_env.md §4).
#
# CONTRACT: sourcing this file has NO side effects — it touches no tmux state
# and prints nothing. All work happens inside functions called by the consumer.

set -u   # NOT -e (option reads legitimately return non-zero); NOT -o pipefail.

# $1: option name (e.g. "@livepicker-type"), $2: default value
get_opt() {
	local value
	value="$(tmux show-option -gqv "$1")"
	[ -n "$value" ] && echo "$value" || echo "$2"
}

# --- per-option accessors (defaults are PRD §11 verbatim) ---------------------
# Each accessor returns the user-set value if present, else the PRD default.

opt_key()                 { get_opt "@livepicker-key"                 ""; }        # required: empty if unset (guard lives in plugin.tmux)
opt_type()                { get_opt "@livepicker-type"                "session"; } # enum: session|window
opt_create()              { get_opt "@livepicker-create"              "on"; }      # bool on/off (session mode only)
opt_next_key()            { get_opt "@livepicker-next-key"            "C-M-Tab"; } # single key (repurposed window-nav)
opt_prev_key()            { get_opt "@livepicker-prev-key"            "C-M-BTab"; }# single key (repurposed window-nav)
opt_nav_next_keys()       { get_opt "@livepicker-nav-next-keys"       "Down j"; }  # space-list (caller word-splits)
opt_nav_prev_keys()       { get_opt "@livepicker-nav-prev-keys"       "Up k"; }    # space-list (caller word-splits)
opt_confirm_keys()        { get_opt "@livepicker-confirm-keys"        "Enter"; }   # space-list
opt_cancel_keys()         { get_opt "@livepicker-cancel-keys"         "Escape"; }  # space-list (clear query, else cancel)
opt_backspace_keys()      { get_opt "@livepicker-backspace-keys"      "BSpace"; }  # space-list
opt_preview_mode()        { get_opt "@livepicker-preview-mode"        "live"; }    # enum: live|snapshot|off
opt_suppress_window_hook(){ get_opt "@livepicker-suppress-window-hook" "on"; }      # bool on/off
opt_fg()                  { get_opt "@livepicker-fg"                  "default"; } # tmux color
opt_bg()                  { get_opt "@livepicker-bg"                  "default"; } # tmux color
opt_highlight_fg()        { get_opt "@livepicker-highlight-fg"        "black"; }   # tmux color
opt_highlight_bg()        { get_opt "@livepicker-highlight-bg"        "yellow"; }  # tmux color
opt_show_count()          { get_opt "@livepicker-show-count"          "on"; }      # bool on/off
opt_status_format_index() { get_opt "@livepicker-status-format-index" "0"; }       # int 0-9
```

NOTE for the implementer: the block above is the complete, ready file body. Use
it as-is; the only allowed deviation is comment phrasing. Do NOT add a
"defaults lookup array" variant — the accessor functions ARE the lookup, and a
parallel array would be a second source of truth that can drift.

### Integration Points

```yaml
SOURCING (consumed by, in later tasks — DO NOT implement these now):
  - scripts/utils.sh          (P1.M1.T2) may source for the @livepicker- prefix convention
  - scripts/state.sh          (P1.M1.T3) consumes opt_* for defaults of internal state
  - plugin.tmux               (P1.M1.T4) calls opt_key for the binding + required-guard
  - scripts/renderer.sh       (P1.M2.T1) consumes opt_fg/bg/highlight_*/show_count
  - scripts/preview.sh        (P1.M3.T1) consumes opt_preview_mode
  - scripts/livepicker.sh     (P1.M4.T4) consumes opt_next_key/prev_key/nav-*/confirm/cancel/backspace, opt_suppress_window_hook, opt_status_format_index
  - scripts/restore.sh        (P1.M5.T3) consumes opt_suppress_window_hook, opt_status_format_index
  - scripts/input-handler.sh  (P1.M6.T3/T4) consumes opt_create, opt_cancel_keys

CONFIG:
  - add to: nothing. This file only READS @livepicker-* options. It sets none.

ROUTES / DATABASE / MIGRATIONS: none — tmux option library only.
```

## Validation Loop

### Level 1: Syntax & Style (Immediate Feedback)

```bash
# Run after creating the file — fix before proceeding.
bash -n scripts/options.sh                       # syntax check; expect no output, exit 0
shellcheck scripts/options.sh                    # lint; expect 0 findings
# Tabs-not-spaces sanity (shfmt is NOT installed; verify manually):
grep -Pn '^    ' scripts/options.sh && echo "FAIL: 4-space indent found, use tabs" || echo "OK: no leading 4-space groups"

# Expected: all three clean. If shellcheck reports SC2155 on get_opt, you collapsed
# `local` + assign onto one line — split them (see Known Gotchas).
```

### Level 2: Unit Tests (Component Validation)

There is no test harness yet (P1.M7.T1/T2 will invent the socket-isolation
shim). For THIS subtask, run a throwaway smoke script, then delete it:

```bash
# Throwaway smoke (do NOT commit a tests/ dir):
cat > /tmp/smoke_options.sh <<'EOF'
#!/usr/bin/env bash
set -u
source "$(dirname "$1")/scripts/options.sh" "$1"

pass=0; fail=0
assert_eq() { # $1 desc $2 actual $3 expected
	if [ "$2" = "$3" ]; then pass=$((pass+1));
	else fail=$((fail+1)); printf 'FAIL %s: got [%s] want [%s]\n' "$1" "$2" "$3"; fi
}

# Override surfacing: @livepicker-fg is live-set to #ffffff in tmux.conf
assert_eq "fg override surfaced"   "$(opt_fg)"                 "#ffffff"
# Defaults for unset options:
assert_eq "type default"          "$(opt_type)"                "session"
assert_eq "next-key default"      "$(opt_next_key)"            "C-M-Tab"
assert_eq "nav-next-keys default" "$(opt_nav_next_keys)"       "Down j"
assert_eq "preview-mode default"  "$(opt_preview_mode)"        "live"
assert_eq "create default"        "$(opt_create)"              "on"
assert_eq "status-idx default"    "$(opt_status_format_index)" "0"
assert_eq "highlight-bg default"  "$(opt_highlight_bg)"        "yellow"
# Required key is set to Space in this env:
assert_eq "key value"             "$(opt_key)"                 "Space"

printf 'PASS=%d FAIL=%d\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
EOF
bash /tmp/smoke_options.sh "$(pwd)"; rc=$?
rm -f /tmp/smoke_options.sh
exit $rc
# Expected: PASS=9 FAIL=0, exit 0. If opt_fg != #ffffff, get_opt is not using
# `show-option -gqv` (or the global was queried from the wrong scope).
```

### Level 3: Integration Testing (System Validation)

```bash
# No-side-effects proof: sourcing options.sh must NOT change any tmux option.
before="$(tmux show-options -g | sort | cksum)"
( set -u; source ./scripts/options.sh; )   # subshell; source only
after="$(tmux show-options -g | sort | cksum)"
[ "$before" = "$after" ] && echo "OK: no side effects" || echo "FAIL: tmux state mutated"

# get_opt idiom equivalence: directly verify it matches the sibling helper on a
# known-live option (uses the live @livepicker-fg #ffffff).
bash -c 'source ./scripts/options.sh; v="$(get_opt "@livepicker-fg" "default")"; [ "$v" = "#ffffff" ] && echo OK || echo "FAIL got=$v"'
# Expected: OK, OK
```

### Level 4: Creative & Domain-Specific Validation

```bash
# Cross-check every accessor default against PRD §11 programmatically (catches
# a typo'd default the smoke script might miss). Unset a sentinel by checking the
# literal strings emitted by the FILE match the PRD table:
for pair in \
  "type:session" "create:on" "next-key:C-M-Tab" "prev-key:C-M-BTab" \
  "nav-next-keys:Down j" "nav-prev-keys:Up k" "confirm-keys:Enter" \
  "cancel-keys:Escape" "backspace-keys:BSpace" "preview-mode:live" \
  "suppress-window-hook:on" "fg:default" "bg:default" "highlight-fg:black" \
  "highlight-bg:yellow" "show-count:on" "status-format-index:0"; do
  suf="${pair%%:*}"; want="${pair#*:}"
  hit="$(grep -c "get_opt \"@livepicker-${suf}\" \"${want}\"" scripts/options.sh)"
  [ "$hit" = "1" ] || echo "MISMATCH: @livepicker-${suf} default '${want}' not found exactly once (hits=$hit)"
done
echo "PRD §11 default cross-check done"
# Expected: only the "(none)" key row is absent by design; every other default
# appears exactly once. Any MISMATCH line = a default typo to fix.
```

## Final Validation Checklist

### Technical Validation

- [ ] `bash -n scripts/options.sh` exits 0 with no output.
- [ ] `shellcheck scripts/options.sh` reports 0 findings (no SC2155 on get_opt).
- [ ] No 4-space indents (`grep -Pn '^    '` is empty); tabs only.
- [ ] Smoke script: PASS=9 FAIL=0, including `opt_fg == #ffffff` (override proof).

### Feature Validation

- [ ] `get_opt()` present with sibling-identical body.
- [ ] All 18 `opt_*` accessors present (cross-checked against the PRD §11 table).
- [ ] No-side-effects proof passes (tmux `show-options -g` cksum unchanged).
- [ ] `opt_key` returns `""` when unset / the value when set (no crash under `set -u`).
- [ ] File is a pure sourced library (no top-level `tmux` call, no top-level `echo`).

### Code Quality Validation

- [ ] Shebang `#!/usr/bin/env bash`; `set -u` only (no `-e`, no `-o pipefail`).
- [ ] `local` declared before assign in get_opt (SC2155-safe).
- [ ] All expansions double-quoted; tabs for indent.
- [ ] One-line comment per accessor documenting default + kind.
- [ ] No parallel "defaults array" — accessors are the single source of truth.

### Documentation & Deployment

- [ ] Header comment states: sourced library, no side effects, mirrors sibling idiom.
- [ ] No new env vars introduced (options only read `@livepicker-*`).
- [ ] No README/doc file created in this subtask (DOCS = Mode A greenfield; full
      options table surfaces in README at P1.M8.T1.S1).

---

## Anti-Patterns to Avoid

- ❌ Don't add `set -e`/`-o pipefail` — siblings deliberately omit them because
  `show-option` legitimately returns non-zero on unset options under some flows.
- ❌ Don't collapse `local value; value="$(...)"` into `local value="$(...)"`
  (SC2155; also masks the `tmux` return code).
- ❌ Don't use `show-options` (plural) if you want byte-identical sibling style —
  use `show-option -gqv`.
- ❌ Don't implement the required-key guard or `is_set` probe here — those belong
  to `plugin.tmux` (P1.M1.T4) and `utils.sh` (P1.M1.T2) respectively.
- ❌ Don't pre-split space-list options (nav-*/confirm/cancel/backspace keys) —
  return the raw string; let callers word-split.
- ❌ Don't normalize booleans to 0/1 — keep `"on"`/`"off"` literals (PRD §11 wording).
- ❌ Don't add a second source of truth (a defaults array alongside the accessors).
- ❌ Don't create a `tests/` directory or committed test file — the harness is
  invented in P1.M7.T1/T2; this subtask validates via throwaway smoke only.
- ❌ Don't compute `SCRIPT_DIR`/`CURRENT_DIR` — this is a sourced library, not an
  entry point.
- ❌ Don't run `tmux` at the top level of the file (would violate "no side effects"
  and break sourcing inside other strict scripts).

---

## Confidence Score

**9 / 10** for one-pass success. Rationale: the deliverable is a single small
library file whose body is given nearly verbatim above, the idiom is copied from
three working siblings, the default table is exhaustive, and the validation
commands are concrete and verified-present (`shellcheck 0.11.0`, `bash 5.3.15`,
`tmux 3.6b`, live `@livepicker-fg #ffffff` as the override proof point). The only
residual risk is an accessor-name typo, which the Level 4 PRD cross-check catches
deterministically.
