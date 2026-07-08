# PRP — P2.M1.T1.S1: rename/delete/confirm-delete options + activate binding step 5

---

## Goal

**Feature Goal**: Add the three P2 session-management **option accessors**
(`opt_rename_key` default `C-r`, `opt_delete_key` default `M-BSpace`,
`opt_confirm_delete` default `off`) to `scripts/options.sh`, and wire the two
**management key bindings** (`rename` / `delete`) into `scripts/livepicker.sh`'s
activate T4 block as "step 5" (after the typing/nav blocks, before the key-table
switch). Add the three option rows to `README.md`'s Configuration table + brief
rename/delete keybind + driver/last-session-refuse + M-BSpace-terminal-caveat
notes to the Usage section (Mode A; full prose deferred to P4). The bindings are
**INERT** until P2.M1.T2 implements the `rename)`/`delete)` dispatch in
`input-handler.sh` + `session-mgmt.sh`.

**Deliverable**: Three edits to existing files (NO new file):
1. `scripts/options.sh` — 3 new one-liner accessors.
2. `scripts/livepicker.sh` — 2 `bind-key` lines (+ a comment) inserted as T4 step 5.
3. `README.md` — 3 new Configuration-table rows + a Usage note (Mode A).

**Success Definition**:
- `bash -n scripts/options.sh scripts/livepicker.sh` passes; `shellcheck` clean
  on the two scripts (the existing file-level disables cover them).
- After activating the picker on an isolated socket:
  - `tmux show-option -gqv @livepicker-rename-key` → `C-r`;
    `@livepicker-delete-key` → `M-BSpace`; `@livepicker-confirm-delete` → `off`.
  - `tmux list-keys -T livepicker C-r` → `run-shell "<abs>/input-handler.sh rename"`;
    `tmux list-keys -T livepicker M-BSpace` → `run-shell "<abs>/input-handler.sh delete"`.
  - Pressing `C-r` / `M-BSpace` is INERT (picker stays open, `@livepicker-mode`
    still `on`) — the `input-handler.sh` `*)` default no-op returns 0.
- `tests/run.sh` stays GREEN (no existing test breaks; the new keys are distinct
  from `C-M-Tab`/`C-M-BTab` and are torn down by restore's `unbind-key -a -T
  livepicker`).
- README table has the 3 rows in PRD §11 order; Usage has the rename/delete note.

## User Persona (if applicable)

**Target User**: tmux users migrating from sessionx (the defaults mirror
`@sessionx-bind-rename-session`/`-kill-session`). Mode A docs here; the bindings
light up functionally in P2.M1.T2.

**Use Case**: A user activates the picker, browses to a session, and (once P2.M1.T2
lands) presses `C-r` to rename it or `M-BSpace` to kill it — without leaving the
picker. Today this task only makes the OPTIONS configurable + the keys BOUND;
the keys are reserved (inert) so a later dispatch lands without re-touching activate.

**User Journey**: (Post-P2.M1.T2) Activate → navigate to a target → press `C-r`
→ tmux prompt pre-filled → type new name → Enter. Or press `M-BSpace` → (if
`@livepicker-confirm-delete on`) `y/n` → kill. The driver + last session are
refused. **This task delivers only the option seams + bindings.**

**Pain Points Addressed**: Parity with sessionx management keys; reserving the
control-key namespace at activation time (PRD §21) so the dispatch task has
stable, documented defaults to bind against.

## Why

- **PRD §11** defines the three options (`@livepicker-rename-key`,
  `@livepicker-delete-key`, `@livepicker-confirm-delete`) with defaults that
  match sessionx.
- **PRD §21 / §8 step 5** requires the rename/delete keys be bound in the
  `livepicker` table AFTER the typing/nav blocks (override rule) as control keys
  (never collide with the typing set).
- **Decoupling**: separating "options + bindings" (this task) from "dispatch +
  session-mgmt.sh" (P2.M1.T2) keeps each change small, reviewable, and
  independently testable. The bindings are inert by construction (the `*` no-op).
- **Docs (Mode A)**: the option rows + keybind notes land now so the README tracks
  the surface as it grows; full prose (guards, leak, escaping) is P4.

## What

1. **options.sh** — add 3 one-liner accessors (§P2 pattern), defaults PRD §11
   verbatim, inserted between `opt_backspace_keys` and `opt_preview_mode`.
2. **livepicker.sh** — in `activate_main` T4, AFTER the prev-key nav `for` loop
   and BEFORE the `(3) SWITCH` comment, add 2 `bind-key` lines binding
   `$(opt_rename_key)` → `input-handler.sh rename` and `$(opt_delete_key)` →
   `input-handler.sh delete`.
3. **README.md** — add 3 Configuration-table rows (after `@livepicker-backspace-keys`,
   before `@livepicker-preview-mode`) + a Usage note covering the keybinds, the
   driver/last-session refuse guard, and the M-BSpace terminal caveat.

### Success Criteria

- [ ] `opt_rename_key()` / `opt_delete_key()` / `opt_confirm_delete()` exist in
      `scripts/options.sh` with defaults `C-r` / `M-BSpace` / `off`.
- [ ] `scripts/livepicker.sh` binds `C-r`→`rename` and `M-BSpace`→`delete` in the
      livepicker table (verified via `list-keys -T livepicker`).
- [ ] The 2 binds are placed AFTER the prev-key nav loop, BEFORE the
      `set-option -g key-table livepicker` switch.
- [ ] Pressing the keys is INERT (picker stays open; `@livepicker-mode` on) until
      P2.M1.T2 (the `*)` no-op).
- [ ] README Configuration table has the 3 rows in PRD §11 order.
- [ ] README Usage has the rename/delete keybind + driver/last-session refuse +
      M-BSpace terminal caveat notes (Mode A, brief).
- [ ] `tests/run.sh` stays green; `shellcheck` clean on the two scripts.

## All Needed Context

### Context Completeness Check

_Pass_: A developer who has never seen this repo can implement all three edits
from (a) the exact insertion anchors below (with verbatim oldText/newText in the
Implementation Blueprint), (b) the 10 findings in `research/findings.md` — most
critically **FINDING 1** (the options.sh one-liner + the "single space" grep
contract), **FINDING 2** (the exact livepicker.sh step-5 insertion point + the
single-`bind-key`-not-loop form), **FINDING 3** (the `*)` no-op that makes the
binds inert), and **FINDING 8** (the README table/Usage insertion points + the
stale-`show-count`-don't-touch caveat). No external library knowledge is needed
beyond the shipped nav-binding pattern in livepicker.sh (which is reproduced).

### Documentation & References

```yaml
# MUST READ — the file you EDIT #1 (option accessors). §P2 pattern.
- file: scripts/options.sh
  why: get_opt one-liner idiom; the "single space" grep contract (each
       get_opt "@livepicker-<suffix>" "<default>" appears exactly once); the
       insertion point between opt_backspace_keys (line 36) and opt_preview_mode (37).
  pattern: "opt_name()  { get_opt \"@livepicker-name\" \"default\"; }  # comment"
  gotcha: the new accessors are SINGLE-KEY (not space-list) — callers do NOT
          word-split them (unlike opt_nav_next_keys). opt_confirm_delete is a bool on/off.

# MUST READ — the file you EDIT #2 (activate bindings). The T4 block.
- file: scripts/livepicker.sh
  why: activate_main T4 binds keys in order (copy -> typing -> backspace/confirm/
       cancel -> nav -> [STEP 5 HERE] -> SWITCH). The nav `for` loops are the
       template; the single-key form is `tmux bind-key -T livepicker "$KEY"
       run-shell "$CURRENT_DIR/input-handler.sh <action>"`. $CURRENT_DIR == scripts/.
  pattern: |
    for lp_c in $(opt_prev_key) $(opt_nav_prev_keys); do
        tmux bind-key -T livepicker "$lp_c" run-shell "$CURRENT_DIR/input-handler.sh prev-session"
    done
    # STEP 5 (rename/delete) inserted here, then:
    tmux set-option -g key-table livepicker
  gotcha: indentation = TABS (the file uses tabs). The 2 binds are SINGLE lines,
          NOT loops (single-key accessors). They run AFTER typing -> override any
          same-key copied binding (C-r/M-BSpace are distinct from r/BSpace).

# MUST READ — why the binds are inert (the dispatch does NOT exist yet).
- file: scripts/input-handler.sh
  why: the `case "$action"` dispatch; the `*)` default returns 0 (no-op). So
       `input-handler.sh rename` / ` delete` today hit `*)` -> picker stays open.
       P2.M1.T2 adds the `rename)` / `delete)` branches + session-mgmt.sh.
  critical: DO NOT add rename)/delete) branches here (that is P2.M1.T2's contract).

# MUST READ — the file you EDIT #3 (docs).
- file: README.md
  why: Configuration table (insert 3 rows after @livepicker-backspace-keys, before
       @livepicker-preview-mode) + Usage section (add rename/delete note after step 5 Cancel).
  gotcha: the README still has a STALE @livepicker-show-count row (removed from
          options.sh in P1). DO NOT touch it — that is P4.T1's sync concern.

# MUST READ — the architecture patterns (option + hook + test conventions).
- docfile: plan/003_77ef311abf10/architecture/codebase_patterns.md
  why: §P2 (option accessor one-liners; lists the P2 additions: opt_rename_key,
       opt_delete_key, opt_confirm_delete); §P8 (test harness — pins defer off;
       the new keys don't collide with test_keyrepurpose's C-M-Tab/C-M-BTab checks;
       restore's unbind-key -a -T livepicker nukes the new binds too).
  section: "§P2 Option accessors", "§P8 Test harness"

# MUST READ — the PRD sections selected for this work item.
- docfile: PRD.md
  why: §11 (the 3 options + defaults); §21 (rename/delete semantics — Keys,
       Rename, Delete guards, Delete key caveat); §8 step 5 (mgmt binds run after
       typing/nav; control keys don't collide); §16 (override rule + delete key
       terminal caveat + linked-preview-leak note).
  section: "§11 Configuration options", "§21 Session management", "§8 Binding step 5",
           "§16 Implementation risks (delete caveat)"

# MUST READ — the ground-truth findings for THIS task (10 live-verified findings).
- docfile: plan/003_77ef311abf10/P2M1T1S1/research/findings.md
  why: FINDING 1 (options.sh accessor + single-space grep contract); FINDING 2
       (livepicker.sh step-5 insertion point + single-bind-key form); FINDING 3
       (the *) no-op = inert); FINDING 4 (override rule); FINDING 5 (sessionx
       parity); FINDING 6 (delete guards = README note); FINDING 7 (M-BSpace
       caveat = README note); FINDING 8 (README insertion points + stale show-count);
       FINDING 9 (no existing test breaks; list-keys/show-option validation);
       FINDING 10 (set -u / escaping safety).
  critical: Read BEFORE editing. FINDING 8's stale-show-count caveat prevents
            scope creep into P4. FINDING 2's tab-indent + single-line-not-loop
            form prevents a copy-paste of the nav `for` loop.
```

### Current Codebase tree

```bash
tmux-livepicker/
  PRD.md
  plugin.tmux
  scripts/
    options.sh utils.sh state.sh layout.sh rank.sh   # sourced libs.
    renderer.sh input-handler.sh preview.sh livepicker.sh restore.sh   # entry points (COMPLETE).
    session-mgmt.sh   # <-- DOES NOT EXIST yet (P2.M1.T2 creates it).
  tests/
    setup_socket.sh helpers.sh run.sh                 # harness (COMPLETE).
    test_functional.sh test_keyrepurpose.sh test_restore.sh ... test_scroll_width.sh  # suites.
    test_session_mgmt.sh   # <-- DOES NOT EXIST yet (P2.M2.T1.S1 creates it).
  README.md            # <-- EDIT (3 table rows + Usage note).
  CHANGELOG.md
  plan/003_77ef311abf10/{architecture, P2M1T1S1/{PRP.md, research/findings.md}}
```

### Desired Codebase tree with files to be added and responsibility of file

```bash
tmux-livepicker/        # NO new file. Three existing files edited:
  scripts/
    options.sh          # + opt_rename_key (C-r), opt_delete_key (M-BSpace),
                        #   opt_confirm_delete (off). 3 one-liners (§P2).
    livepicker.sh       # + 2 bind-key lines in activate_main T4 step 5
                        #   (rename -> input-handler.sh rename; delete -> ... delete).
  README.md             # + 3 Configuration-table rows; + Usage rename/delete note (Mode A).
```

### Known Gotchas of our codebase & Library Quirks

```bash
# CRITICAL (FINDING 3): the rename/delete binds are INERT until P2.M1.T2. Pressing
# C-r / M-BSpace hits input-handler.sh's `*)` default -> return 0 -> no-op. Do NOT
# add rename)/delete) case branches or create session-mgmt.sh here (P2.M1.T2's scope).

# CRITICAL (FINDING 2): the 2 binds are SINGLE `tmux bind-key` lines, NOT `for`
# loops. opt_rename_key/opt_delete_key are SINGLE-KEY accessors (like opt_next_key),
# not space-lists (unlike opt_nav_next_keys). A loop would be wrong. Mirror the
# single-key nav form exactly.

# CRITICAL (FINDING 2): livepicker.sh uses TAB indentation. The 2 binds + comment
# must be indented with a single leading TAB (the body of activate_main). Verify
# with `grep -Pn '^    ' scripts/livepicker.sh` AFTER editing (expect the only
# matches to be pre-existing, none on your new lines).

# CRITICAL (FINDING 4): placement AFTER the prev-key nav loop is load-bearing —
# tmux keeps the LAST binding for a key, so step 5 binds OVERRIDE any same-key
# copy from step 1. Do NOT move them before the typing/nav blocks.

# GOTCHA (FINDING 1): options.sh header mandates "single space" so the default
# cross-check grep matches `get_opt "@livepicker-<suffix>" "<default>"` exactly
# once. Use exactly ONE space between the option name's closing quote and the
# default's opening quote: `get_opt "@livepicker-rename-key" "C-r"`.

# GOTCHA (FINDING 8): the README still has a STALE `@livepicker-show-count` row
# (the accessor was removed in P1 per codebase_patterns.md §P2). DO NOT remove
# or edit it here — that is P4.T1's docs-sync concern. Touch ONLY the 3 new rows
# + the Usage note.

# GOTCHA (house style): options.sh has `set -u` (NOT -e). get_opt bakes a default
# so it never returns empty. The bind-key line `run-shell "$CURRENT_DIR/input-
# handler.sh rename"` is double-quoted (mirrors the shipping nav binds); the
# action arg `rename`/`delete` has no spaces -> no extra quoting needed.
```

## Implementation Blueprint

### Data models and structure

No data model. Three surgical text edits to existing files. No new constants in
`state.sh` (the 3 options are plain `@livepicker-*` config, read via `get_opt`;
they are NOT runtime `STATE_*` keys and NOT `ORIG_*` saved-state keys, so they
are untouched by `clear_all_state` — correct, they are user config).

### Implementation Tasks (ordered by dependencies)

```yaml
Task 1: EDIT scripts/options.sh — add 3 option accessors (§P2)
  - FILE: ./scripts/options.sh  (EXISTING; sourced lib).
  - INSERT BETWEEN:
      opt_backspace_keys()       { get_opt "@livepicker-backspace-keys" "BSpace"; } # space-list
      opt_preview_mode()         { get_opt "@livepicker-preview-mode" "live"; }     # enum: live|snapshot|off
  - ADD (column-0; one space inside get_opt per the grep contract):
      opt_rename_key()       { get_opt "@livepicker-rename-key" "C-r"; }        # single key (rename via tmux prompt; PRD §21; mirrors sessionx @sessionx-bind-rename-session)
      opt_delete_key()       { get_opt "@livepicker-delete-key" "M-BSpace"; }   # single key (kill session; PRD §21; mirrors sessionx @sessionx-bind-kill-session)
      opt_confirm_delete()   { get_opt "@livepicker-confirm-delete" "off"; }    # bool on/off (confirm-before kill; off=sessionx-style immediate)
  - NAMING: opt_rename_key / opt_delete_key / opt_confirm_delete (PRD §11 suffixes).
  - STYLE: column-0, matches the neighboring accessor line's `{`/comment alignment.

Task 2: EDIT scripts/livepicker.sh — bind rename + delete in activate_main T4 step 5
  - FILE: ./scripts/livepicker.sh  (EXISTING; entry point).
  - INSERT AFTER the prev-key nav loop's `done`, BEFORE the `# (3) SWITCH` comment:
      \tdone
      <INSERT HERE>
      \t# (3) SWITCH the active key-table to livepicker ...
  - ADD (TAB-indented; SINGLE bind-key lines, NOT loops):
      \t# --- P2.M1.T1.S1: session-mgmt keys (rename + delete), PRD §21 step 5. ---
      \t# SINGLE keys (not space-lists -> no loop). Bound AFTER the typing + nav
      \t# blocks so they OVERRIDE any same-key copy (C-r / M-BSpace are distinct
      \t# tmux keys from r / BSpace, so typing is unaffected — PRD §8/§16). INERT
      \t# until P2.M1.T2 adds the rename)/delete) dispatch in input-handler.sh (the
      \t# default * branch is a no-op return 0 -> picker stays open).
      \ttmux bind-key -T livepicker "$(opt_rename_key)" run-shell "$CURRENT_DIR/input-handler.sh rename"
      \ttmux bind-key -T livepicker "$(opt_delete_key)" run-shell "$CURRENT_DIR/input-handler.sh delete"
  - PATTERN: identical to the nav binding form (tmux bind-key -T livepicker "$KEY"
    run-shell "$CURRENT_DIR/input-handler.sh <action>"), but single-line (no loop).
  - DEPENDENCIES: opt_rename_key/opt_delete_key from Task 1; $CURRENT_DIR global.

Task 3: EDIT README.md — Configuration table (3 rows, Mode A)
  - FILE: ./README.md  (EXISTING).
  - INSERT BETWEEN (table row order = PRD §11):
      | `@livepicker-backspace-keys`       | `BSpace`   | Remove the last filter character. ... |
      <INSERT 3 ROWS HERE>
      | `@livepicker-preview-mode`         | `live`     | ... |
  - ADD:
      | `@livepicker-rename-key`           | `C-r`      | Rename the highlighted session via tmux's prompt. Control key; never collides with typing. |
      | `@livepicker-delete-key`           | `M-BSpace` | Delete (kill) the highlighted session. Matches sessionx's `@sessionx-bind-kill-session`. |
      | `@livepicker-confirm-delete`       | `off`      | When `on`, prompt `y/n` before killing a session (`confirm-before`). Default `off` = immediate, sessionx-style. |
  - GOTCHA: leave the STALE `@livepicker-show-count` row untouched (P4 concern).

Task 4: EDIT README.md — Usage note (Mode A; brief)
  - FILE: ./README.md  (EXISTING).
  - ADD a new numbered step after step 5 (Cancel), e.g. step 6 "Session management":
      6. **Rename / delete** — `C-r` (`@livepicker-rename-key`) renames the
         highlighted session via tmux's prompt; `M-BSpace`
         (`@livepicker-delete-key`) kills it. Deleting is refused for the driver
         session you launched the picker from and for the last remaining session.
         Set `@livepicker-confirm-delete on` to require a `y/n` prompt before a
         kill. Note: a few older terminals or SSH/mosh links strip Alt-modified
         keys; if `M-BSpace` does not fire, rebind `@livepicker-delete-key` to
         `C-h` or `DC` (Delete).
  - SCOPE: Mode A (changeset-level, brief). Full prose (guards, leak, escaping) is P4.

Task 5: VALIDATE (Level 1 + isolated-socket spot-check + run.sh)
  - RUN: bash -n scripts/options.sh scripts/livepicker.sh   (expect exit 0)
  - RUN: shellcheck scripts/options.sh scripts/livepicker.sh (expect 0 findings;
         existing file-level disables cover the new lines)
  - RUN: grep -Pn '^    ' scripts/livepicker.sh  (expect NO match on your new lines)
  - RUN: grep -c 'get_opt "@livepicker-rename-key" "C-r"' scripts/options.sh  (== 1)
  - RUN: the isolated-socket spot-check in Validation Level 3.
  - RUN: tests/run.sh  (expect: all GREEN; no regression).
```

### Implementation Patterns & Key Details

```bash
# === options.sh: the 3 one-liners (Task 1) ===
# Pattern = §P2: one opt_<name>() per option, default PRD §11 verbatim, single
# space inside get_opt (the cross-check grep contract). SINGLE-KEY accessors
# (callers do NOT word-split them; they are read once per activate).
opt_rename_key()       { get_opt "@livepicker-rename-key" "C-r"; }
opt_delete_key()       { get_opt "@livepicker-delete-key" "M-BSpace"; }
opt_confirm_delete()   { get_opt "@livepicker-confirm-delete" "off"; }

# === livepicker.sh: the 2 binds (Task 2) ===
# Place AFTER the prev-key nav `for ... done` and BEFORE `# (3) SWITCH`.
# SINGLE bind-key lines (NOT loops — single-key accessors). TAB-indented.
# The form mirrors the shipping nav binds EXACTLY:
	tmux bind-key -T livepicker "$(opt_rename_key)" run-shell "$CURRENT_DIR/input-handler.sh rename"
	tmux bind-key -T livepicker "$(opt_delete_key)" run-shell "$CURRENT_DIR/input-handler.sh delete"
# $(opt_rename_key) -> "C-r"; $CURRENT_DIR -> absolute scripts/ dir. No extra
# quoting: C-r has no special chars; `rename`/`delete` have no spaces.

# === WHY inert (do not implement the dispatch here) ===
# input-handler.sh dispatch `case "$action"` has branches for type/backspace/
# next-session/prev-session/confirm/cancel/refresh-width + a `*)` default that
# returns 0 (no-op). So `input-handler.sh rename`/`delete` today -> no-op.
# P2.M1.T2 adds the `rename)`/`delete)` branches + session-mgmt.sh.
```

### Integration Points

```yaml
ACTIVATION (livepicker.sh activate_main T4):
  - step 5 (NEW): 2 bind-key lines for rename/delete, after the nav block.
  - These run AFTER the copy+typing+nav blocks -> override any same-key copy.
  - No change to the SWITCH step or any other activate step.

INPUT DISPATCH (input-handler.sh):
  - NO CHANGE (read-only reference). The `*)` no-op makes the binds inert.
  - P2.M1.T2 will add rename)/delete) branches + create scripts/session-mgmt.sh.

STATE (state.sh):
  - NO CHANGE. The 3 options are @livepicker-* config (get_opt), not STATE_*/ORIG_*.
  - They are NOT cleared by clear_all_state (correct — they are user config).

RESTORE (restore.sh):
  - NO CHANGE. STEP-6's `unbind-key -a -T livepicker` already nukes ALL livepicker
    binds including the 2 new ones.

DATABASE / MIGRATIONS / ROUTES / CONFIG-FILE: none.
```

## Validation Loop

### Level 1: Syntax & Style (Immediate Feedback)

```bash
# Run after each edit — fix before proceeding. Run from the repo root.
bash -n scripts/options.sh scripts/livepicker.sh        # syntax; expect exit 0, no output
shellcheck scripts/options.sh scripts/livepicker.sh     # lint; expect 0 findings (file-level disables cover)
# Tabs-not-spaces (livepicker.sh body uses tabs); confirm NO 4-space indent on your new lines:
grep -Pn '^    ' scripts/livepicker.sh && echo "check the flagged lines are pre-existing, not yours" || echo "OK"
# The single-space grep contract (each accessor matches exactly once):
grep -c 'get_opt "@livepicker-rename-key" "C-r"'         scripts/options.sh   # == 1
grep -c 'get_opt "@livepicker-delete-key" "M-BSpace"'    scripts/options.sh   # == 1
grep -c 'get_opt "@livepicker-confirm-delete" "off"'     scripts/options.sh   # == 1
# The 2 binds exist in livepicker.sh:
grep -n 'input-handler.sh rename' scripts/livepicker.sh    # one match
grep -n 'input-handler.sh delete' scripts/livepicker.sh    # one match
```

### Level 2: Unit / Component Validation (the existing suite must stay green)

```bash
# This task adds NO new test (test_session_mgmt.sh is P2.M2.T1.S1). The gate is
# that the EXISTING suite stays green — the new keys don't collide with any
# assertion (test_keyrepurpose checks C-M-Tab/C-M-BTab; restore's unbind-key -a
# covers the new binds).
tests/run.sh
# Expected: exit 0; "N passed, 0 failed". No regression.
```

### Level 3: Integration Testing (isolated-socket spot-check of the binds + inertness)

```bash
# Manual spot-check on a throwaway isolated -L socket with a pty client. Self-cleaning.
SOCK="lp-mgmt-$$"; SHIM="$(mktemp -d)"
cat > "$SHIM/tmux" <<EOF
#!/usr/bin/env bash
exec /usr/bin/tmux -L "$SOCK" "\$@"
EOF
chmod +x "$SHIM/tmux"
trap '/usr/bin/tmux -L "$SOCK" kill-server 2>/dev/null; rm -rf "$SHIM"' EXIT
export PATH="$SHIM:$PATH"
tmux new-session -d -s driver -x 120 -y 40
tmux new-session -d -s alpha  -x 120 -y 40          # a second session to point at
# activate the picker (needs a prefix-key binding; set one + use the entry point directly)
tmux set-option -g @livepicker-key Space
script -qec "tmux -L "$SOCK" attach -t driver" /dev/null >/dev/null 2>&1 & AP=$!; sleep 0.5
bash scripts/livepicker.sh                            # activate
# (a) the 3 options resolve to their defaults:
echo "rename-key:    [$(tmux show-option -gqv @livepicker-rename-key)]"      # C-r
echo "delete-key:    [$(tmux show-option -gqv @livepicker-delete-key)]"      # M-BSpace
echo "confirm-delete:[$(tmux show-option -gqv @livepicker-confirm-delete)]"  # off
# (b) the 2 keys are bound in the livepicker table:
echo "C-r bind:      $(tmux list-keys -T livepicker C-r)"
echo "M-BSpace bind: $(tmux list-keys -T livepicker M-BSpace)"
# (c) INERT: pressing them is a no-op (the *) branch). Send C-r then check mode stays on:
tmux send-keys -T livepicker C-r 2>/dev/null || true
sleep 0.2
echo "mode after C-r:[$(tmux show-option -gqv @livepicker-mode)]"            # on (inert -> still open)
kill "$AP" 2>/dev/null
# Expected: defaults match; C-r/M-BSpace bound to run-shell .../input-handler.sh rename|delete; mode still "on".
```

### Level 4: Creative & Domain-Specific Validation

```bash
# User-override path: confirm a custom @livepicker-rename-key is honored at bind time.
SOCK="lp-mgmt-ov-$$"; SHIM="$(mktemp -d)"
printf '#!/usr/bin/env bash\nexec /usr/bin/tmux -L "%s" "$@"\n' "$SOCK" > "$SHIM/tmux"
chmod +x "$SHIM/tmux"
trap '/usr/bin/tmux -L "$SOCK" kill-server 2>/dev/null; rm -rf "$SHIM"' EXIT
export PATH="$SHIM:$PATH"
tmux new-session -d -s driver -x 120 -y 40
tmux set-option -g @livepicker-rename-key "C-e"          # override the default
script -qec "tmux -L "$SOCK" attach -t driver" /dev/null >/dev/null 2>&1 & AP=$!; sleep 0.5
bash scripts/livepicker.sh
echo "C-e bind: $(tmux list-keys -T livepicker C-e)"     # -> run-shell .../input-handler.sh rename
kill "$AP" 2>/dev/null
# Expected: the override key C-e is bound to the rename action.

# README sanity: the 3 rows are present in the table in the right order.
grep -n '@livepicker-rename-key\|@livepicker-delete-key\|@livepicker-confirm-delete' README.md
grep -n 'Rename / delete\|driver session\|SSH/mosh' README.md    # the Usage note anchors
```

## Final Validation Checklist

### Technical Validation

- [ ] `bash -n scripts/options.sh scripts/livepicker.sh` exits 0 with no output.
- [ ] `shellcheck scripts/options.sh scripts/livepicker.sh` reports 0 findings.
- [ ] No 4-space indent introduced in `scripts/livepicker.sh` (tabs only).
- [ ] Each of the 3 `get_opt` accessors matches the grep contract exactly once.

### Feature Validation

- [ ] `opt_rename_key` → `C-r`, `opt_delete_key` → `M-BSpace`, `opt_confirm_delete`
      → `off` (defaults), and each honors a user override (Level 4).
- [ ] `list-keys -T livepicker C-r` → `run-shell "<abs>/input-handler.sh rename`;
      `list-keys -T livepicker M-BSpace` → `run-shell "<abs>/input-handler.sh delete".
- [ ] The 2 binds sit AFTER the prev-key nav loop, BEFORE the key-table SWITCH.
- [ ] Pressing `C-r`/`M-BSpace` is INERT (mode stays `on`; `*)` no-op) — dispatch
      is NOT added here (P2.M1.T2).
- [ ] README Configuration table has the 3 rows after `@livepicker-backspace-keys`.
- [ ] README Usage has the rename/delete + driver/last-session-refuse + M-BSpace caveat note.
- [ ] `tests/run.sh` stays green (no regression).

### Code Quality Validation

- [ ] options.sh accessors follow §P2 (one-liner, default PRD §11 verbatim, single space).
- [ ] livepicker.sh binds mirror the shipping nav-binding form (single-line, not a loop).
- [ ] TAB indentation in livepicker.sh; column-0 accessors in options.sh.
- [ ] No `set -e`/`pipefail` introduced; `set -u` honored (defaults baked).
- [ ] The stale `@livepicker-show-count` README row is NOT touched (P4 concern).

### Documentation & Deployment

- [ ] README rows describe purpose + sessionx parity; Usage note is Mode A (brief).
- [ ] No CHANGELOG edit (P4.T2 owns the [Unreleased] entry).
- [ ] No new test file (P2.M2.T1.S1 owns test_session_mgmt.sh).

---

## Anti-Patterns to Avoid

- ❌ Don't implement the `rename)`/`delete)` dispatch or create `session-mgmt.sh`
  here. That is P2.M1.T2's contract; the binds are intentionally INERT (the `*)`
  no-op). Adding the dispatch would blow this task's scope and collide with P2.M1.T2.
- ❌ Don't write the 2 binds as `for` loops. `opt_rename_key`/`opt_delete_key` are
  SINGLE-KEY accessors (PRD §11), not space-lists. A single `tmux bind-key` line
  each mirrors the nav single-key form (`opt_next_key`).
- ❌ Don't place the binds before the typing/nav blocks. Placement AFTER them is
  load-bearing: tmux keeps the LAST binding for a key, so step 5 must run last to
  override any same-key copy (PRD §8 step 5 / §16).
- ❌ Don't touch the stale `@livepicker-show-count` README row. It was removed from
  options.sh in P1 but the README row lags; P4.T1 syncs it. Scope discipline.
- ❌ Don't add `STATE_*`/`ORIG_*` keys to state.sh for these options. They are
  user `@livepicker-*` config read via `get_opt`, not picker runtime/saved state.
- ❌ Don't reformat neighboring options.sh accessors or README rows. Surgical
  insertions only — match the existing alignment of the immediately adjacent line.
- ❌ Don't add spaces inside `get_opt "@livepicker-rename-key" "C-r"` beyond the
  single required space — the header's cross-check grep depends on exactly one.
- ❌ Don't skip the isolated-socket spot-check. "Binds exist" is only proven by
  `list-keys -T livepicker` after a real activate, and "inert" is only proven by
  the picker staying open after the key fires.
