# PRP — P1.M1.T1.S1: Replace 4 old nav accessors with 4 new two-axis accessors

---

## ⚠️ CHANGESET SEQUENCING — READ FIRST

This subtask is the **first step of a coordinated rename** (delta 004, PRD §8
two-axis keys). It renames the option-accessor *seam* in `options.sh`. By design
(contract point 4: "Old accessors MUST be removed … so any stale reference is
caught at runtime") it produces a **known non-green intermediate**:

- Removing the 4 old accessors **breaks `scripts/livepicker.sh` T4 binding block**
  at lines **388, 389, 423, 427** (they still call `opt_next_key` / `opt_prev_key`
  / `opt_nav_next_keys` / `opt_nav_prev_keys`). Verified by repo-wide grep.
- Those call sites are reworked by **P1.M2.T1.S1** (activate binding rework), which
  depends on **P1.M1.T2.S1** (`lp_discover_axis_keys` discovery helper in utils.sh).

**Therefore:** the full test suite (`tests/run.sh`) will NOT be green after S1
alone — every test that activates the picker hits the broken T4 block. That is
expected and intentional. S1's validation is **scoped to `options.sh` + README in
isolation** (see Validation Loop). The suite goes green again once M1.T2 + M2.T1
land. Do not attempt to "keep it green" by shimming/commenting the old accessors
or by editing `livepicker.sh` here — that is out of scope and would steal
M1.T2/M2.T1's work.

---

## Goal

**Feature Goal**: Rename the option-accessor seam from the old single-axis model
(1 repurposed window-nav key + 1 extra-keys list per direction) to the new
**two-axis, discovery-driven** model (PRD §8 / §11): one space-separated key-list
accessor per `{session,window} × {next,prev}` axis, each with an **empty default**
so "unset ⇒ discover".

**Deliverable**: Two edits — **no new files**.
1. `scripts/options.sh`: delete the 4 old accessors (lines 30-33); add 4 new
   accessors in their place.
2. `README.md`: replace the 4 old config-table rows (lines 100-103) with 4 new rows
   + update the one prose reference (line 171).

**Success Definition** (scoped — see sequencing note above):
- `options.sh` defines exactly `opt_session_next_keys`, `opt_session_prev_keys`,
  `opt_window_next_keys`, `opt_window_prev_keys`, each
  `get_opt "@livepicker-<suffix>" ""` (empty default ⇒ discover).
- The 4 old accessors are **gone** (not commented) — `declare -F opt_next_key`
  etc. return empty.
- Sourcing `options.sh` has no side effects; `bash -n` + `shellcheck` clean.
- README table has the 4 new rows (defaults `(discovered)`, "For this user"
  values, "Must be non-alphanumeric") and no old option-name rows; prose line 171
  updated.
- The 4 stale `livepicker.sh` call sites are documented (for M2.T1) — NOT fixed here.

## User Persona (if applicable)

**Target User**: The activate binding code (livepicker.sh T4, reworked in M2.T1)
and, through it, the end user who navigates the picker on two axes.

**Use Case**: Activate resolves each axis's keys: if the user set the
`@livepicker-*-keys` option explicitly, use it; otherwise discover from their live
key tables (M1.T2). These accessors are the "explicit override?" probe (empty ⇒
discover).

**Pain Points Addressed**: The old single-axis model repurposed the user's
window-nav keys into session-nav, fighting muscle memory (dropped per PRD §8). The
new model keeps window-nav as window-nav (scoped to the preview) and adds a
separate, discovered session axis.

---

## Why

- **Seam rename, first mover.** Everything downstream (discovery M1.T2, binding
  M2.T1) keys off these accessor names. Establishing the correct seam first lets
  the sibling subtasks compile against the right interface.
- **Empty default is the contract.** `""` is how activate distinguishes "explicitly
  set" (non-empty ⇒ use directly) from "discover" (empty ⇒ run
  `lp_discover_axis_keys`). A non-empty default would silently disable discovery.
- **Remove-don't-comment.** Deleting the old accessors makes any caller M2.T1
  misses fail loudly at runtime (a feature, per the contract), instead of lurking
  as a dead-but-defined function.

## What

1. **options.sh** — replace lines 30-33 (the 4 old accessors) in-place with the 4
   new accessors, preserving PRD §11 ordering (session-next, session-prev,
   window-next, window-prev sit between `opt_zoxide` and `opt_confirm_keys`).
2. **README.md** — replace the 4 old table rows (100-103) with the 4 new rows
   (mirror PRD §11 verbatim, incl. `(discovered)` default, "For this user" values,
  "Must be non-alphanumeric"); update the prose at line 171.

### Success Criteria

- [ ] 4 new accessors present; each body is `get_opt "@livepicker-<suffix>" ""`.
- [ ] 4 old accessors absent (`declare -F opt_next_key` etc. ⇒ empty).
- [ ] `grep -c 'get_opt "@livepicker-session-next-keys" ""' scripts/options.sh` ⇒ 1
      (and likewise for the other 3); the Level-4 cross-check still holds.
- [ ] No `@livepicker-next-key` / `-prev-key` / `-nav-next-keys` / `-nav-prev-keys`
      remains in `options.sh`.
- [ ] README: 4 new rows present, 4 old rows gone, prose line 171 updated.
- [ ] `bash -n` + `shellcheck scripts/options.sh` clean; sourcing ⇒ no side effects.
- [ ] Stale `livepicker.sh` call sites (388/389/423/427) listed for M2.T1 — untouched.

## All Needed Context

### Context Completeness Check

_Pass_: The implementer needs (a) the 4 old accessor lines + their 4 stale callers
(quoted below), (b) the 4 new accessor lines (quoted verbatim), (c) the README
old/new rows (quoted), and (d) the sequencing warning. No inference required.

### Documentation & References

```yaml
# MUST READ - the authoritative new option names + defaults + "For this user" values
- docfile: PRD.md
  why: §11 table rows for @livepicker-session-next-keys / -session-prev-keys /
        -window-next-keys / -window-prev-keys give the exact default ("(discovered)"),
        purpose text, "For this user" values, and the "Must be non-alphanumeric" note.
        §8 (h3.18/h3.19) gives the discovery + binding semantics these accessors feed.
  critical: The DEFAULT IS EMPTY (""), NOT the discovered values. Discovery runs at
            activate (M1.T2); the accessor only reports the explicit override (or "").
            Do NOT bake "C-M-Tab"/"Down"/etc. into the accessor — that would disable discovery.

# MUST READ - the file being edited (exact old accessor lines + get_opt helper)
- file: scripts/options.sh
  why: Lines 30-33 are the 4 accessors to delete. get_opt at lines 15-19 is the helper
        each new accessor wraps. Line 23-24 note: a "Level-4 cross-check grep" matches
        each `get_opt "@livepicker-<suffix>" "<default>"` exactly once — match the format.
  pattern: 'opt_<suffix>()  { get_opt "@livepicker-<name>" "<default>"; }  # comment'

# MUST READ - the discovery defaults (for the README "For this user" text only)
- docfile: plan/004_2c5127285a90/architecture/system_context.md
  why: §"Confirmed user key bindings (live tmux 3.6b)" lists the discovered keys:
        window next `C-M-Tab M-n C-n C-l`, window prev `C-M-BTab M-p C-p C-h`,
        session next `) Down`, session prev `( Up`. These go in the README rows; NOT in the accessors.
  section: "## Confirmed user key bindings (live tmux 3.6b)"

# MUST READ - the stale callers that WILL break (for the sequencing note; NOT fixed here)
- file: scripts/livepicker.sh
  why: Lines 388 (opt_next_key), 389 (opt_prev_key), 423 (opt_next_key + opt_nav_next_keys),
        427 (opt_prev_key + opt_nav_prev_keys), + comment 386. These are the T4 binding block
        reworked by P1.M2.T1.S1. S1 must NOT touch them.
  gotcha: After S1 these are "command not found" at runtime — that is the intended signal.

# Reference - the gap analysis (why the rename)
- docfile: plan/004_2c5127285a90/architecture/gap_analysis_key_discovery.md
  why: Documents the old single-axis model vs the new two-axis discovered model.
```

### Current Codebase tree (relevant slices)

```bash
scripts/
  options.sh       # MODIFY: lines 30-33 (4 old accessors) -> 4 new two-axis accessors
  livepicker.sh    # UNCHANGED in S1 (lines 388/389/423/427 become stale -> fixed in M2.T1)
  utils.sh         # UNCHANGED in S1 (lp_discover_axis_keys added in M1.T2)
README.md          # MODIFY: table rows 100-103 + prose line 171
tests/             # UNCHANGED (no test names these accessors directly; suite breaks via livepicker.sh)
```

### Desired Codebase tree with files to be added and responsibility of file

```bash
scripts/options.sh   # 4 old nav accessors removed; 4 new two-axis accessors added (empty default = discover)
README.md            # config table: 4 old rows -> 4 new rows; prose ref updated
```

### Known Gotchas of our codebase & Library Quirks

```bash
# CRITICAL — NON-GREEN INTERMEDIATE (see the sequencing banner at top). Removing the
# 4 accessors breaks livepicker.sh:388/389/423/427. The full suite is NOT green after S1.
# Do NOT shim/comment the old accessors and do NOT edit livepicker.sh here. Scope validation
# to options.sh + README only.

# CRITICAL — DEFAULT IS EMPTY (""), not a discovered value. The accessor is the "did the
# user set an explicit override?" probe: non-empty => use directly; empty => discover
# (M1.T2). Baking "C-M-Tab"/"Down"/etc. here would silently disable discovery.

# CRITICAL — REMOVE, DON'T COMMENT. The contract (point 4) mandates deletion so stale
# references fail at runtime. A commented-out accessor is still "defined enough" to hide
# a missed call site. Delete the lines outright.

# CRITICAL — the new accessors return a SPACE-SEPARATED LIST (caller word-splits), like
# opt_confirm_keys/opt_cancel_keys. The OLD opt_next_key/opt_prev_key returned a SINGLE
# key; that single-vs-list semantic change is why livepicker.sh T4 needs real rework
# (M2.T1), not a 1:1 name swap.

# GOTCHA — the Level-4 cross-check grep (options.sh line 23-24 comment) expects exactly one
# `get_opt "@livepicker-<suffix>" "<default>"` per option. Empty default is fine:
# `get_opt "@livepicker-session-next-keys" ""` is a valid unique substring.

# GOTCHA — column alignment in options.sh is "best effort" (opt_status_format_index uses 2
# spaces before `{`); the load-bearing part is the single-line shape + the exact get_opt
# substring. Align the 4 new lines' `{` roughly with the block (shfmt is NOT installed).

# GOTCHA — README markdown tables don't require aligned pipes (renderers ignore padding),
# but mirror the surrounding rows' shape for diff cleanliness. The new option names are
# longer (@livepicker-session-next-keys = 30 chars) — widen the first column.

# GOTCHA — keep PRD §11 ordering: the 4 accessors sit between opt_zoxide (line 29) and
# opt_confirm_keys (line 34). Replace lines 30-33 IN PLACE (don't append at EOF).

# GOTCHA — do NOT add discovery logic, lp_discover_axis_keys, or any utils.sh change here.
# Discovery is P1.M1.T2.S1. S1 is options.sh + README only.
```

## Implementation Blueprint

### Data models and structure

No runtime data model — just 4 one-liner accessors. The seam change:

```
OLD (single-axis, session-nav only):           NEW (two-axis, discovery-driven):
  opt_next_key()      -> "C-M-Tab"  (single)     opt_session_next_keys() -> "" (list; discover switch-client -n + Down)
  opt_prev_key()      -> "C-M-BTab" (single)     opt_session_prev_keys() -> "" (list; discover switch-client -p + Up)
  opt_nav_next_keys() -> "Down"     (list)       opt_window_next_keys()  -> "" (list; discover next-window keys)
  opt_nav_prev_keys() -> "Up"       (list)       opt_window_prev_keys()  -> "" (list; discover prev-window keys)
```

Resolution flow (for context; S1 implements only the boxed accessors):
```
activate (M2.T1):  v="$(opt_window_next_keys)"          # the accessor S1 provides
                   if [ -n "$v" ]; then use "$v"         # explicit override
                   else lp_discover_axis_keys window next # M1.T2 discovery
```

### Implementation Tasks (ordered by dependencies)

```yaml
Task 1: MODIFY scripts/options.sh — replace the 4 accessors (lines 30-33)
  - DELETE lines 30-33 (opt_next_key, opt_prev_key, opt_nav_next_keys, opt_nav_prev_keys).
  - ADD 4 new accessors IN THEIR PLACE (between opt_zoxide line 29 and opt_confirm_keys):
      opt_session_next_keys() { get_opt "@livepicker-session-next-keys" ""; }  # space-list; empty=discover (PRD §8/§11 session axis; switch-client -n + Down)
      opt_session_prev_keys() { get_opt "@livepicker-session-prev-keys" ""; }  # space-list; empty=discover (session axis; switch-client -p + Up)
      opt_window_next_keys()  { get_opt "@livepicker-window-next-keys" ""; }   # space-list; empty=discover (window axis; next-window keys)
      opt_window_prev_keys()  { get_opt "@livepicker-window-prev-keys" ""; }   # space-list; empty=discover (window axis; prev-window keys)
  - DEFAULT: "" for all four (NOT a discovered value). See Gotchas.
  - FOLLOW pattern: the existing single-line `{ get_opt "@livepicker-<name>" "<d>"; } # comment` shape.
  - DO NOT: add discovery logic, touch utils.sh/livepicker.sh, comment out the old
    accessors, or change any other accessor.

Task 2: MODIFY README.md — config table (lines 100-103) + prose (line 171)
  - DELETE the 4 old table rows (100-103): @livepicker-next-key, -prev-key,
    -nav-next-keys, -nav-prev-keys.
  - ADD 4 new rows mirroring PRD §11 (exact text in Implementation Patterns).
  - UPDATE prose line 171: change `@livepicker-nav-next-keys` / `-prev-keys` to
    `@livepicker-session-next-keys` / `-prev-keys`.
  - DO NOT: touch any other README section (full prose sync is P4.M1.T1.S1).

Task 3: VALIDATE (scoped — options.sh + README in isolation; NOT the full suite)
  - RUN: bash -n scripts/options.sh ; shellcheck scripts/options.sh
  - RUN: the structural + isolated-socket checks in Validation Loop §1/§2.
  - RUN: the stale-caller grep (Validation §3) and RECORD the 4 livepicker.sh sites
    for M2.T1 (do not fix them).
```

### Implementation Patterns & Key Details

**Task 1 — options.sh exact edit** (paste into `edit`; the 4 old lines → 4 new lines):

```bash
# oldText (current lines 30-33):
opt_next_key()             { get_opt "@livepicker-next-key" "C-M-Tab"; }      # single key (repurposed window-nav)
opt_prev_key()             { get_opt "@livepicker-prev-key" "C-M-BTab"; }     # single key (repurposed window-nav)
opt_nav_next_keys()        { get_opt "@livepicker-nav-next-keys" "Down"; }    # space-list (caller word-splits)
opt_nav_prev_keys()        { get_opt "@livepicker-nav-prev-keys" "Up"; }      # space-list (caller word-splits)

# newText (4 new two-axis accessors, empty default = discover):
opt_session_next_keys()    { get_opt "@livepicker-session-next-keys" ""; }    # space-list; empty=discover session axis (switch-client -n + Down; PRD §8/§11)
opt_session_prev_keys()    { get_opt "@livepicker-session-prev-keys" ""; }    # space-list; empty=discover session axis (switch-client -p + Up)
opt_window_next_keys()     { get_opt "@livepicker-window-next-keys" ""; }     # space-list; empty=discover window axis (next-window keys)
opt_window_prev_keys()     { get_opt "@livepicker-window-prev-keys" ""; }     # space-list; empty=discover window axis (prev-window keys)
```

**Task 2 — README exact edits:**

*Table rows* (replace lines 100-103):

```markdown
<!-- oldText (current lines 100-103): -->
| `@livepicker-next-key`             | `C-M-Tab`  | Key that moves to the next session. Defaults to this user's next-window key.                         |
| `@livepicker-prev-key`             | `C-M-BTab` | Key that moves to the previous session. Defaults to this user's prev-window key.                     |
| `@livepicker-nav-next-keys`        | `Down`     | Extra next-session keys. Must be non-alphanumeric; a letter/digit here is intercepted and not typeable. |
| `@livepicker-nav-prev-keys`        | `Up`       | Extra previous-session keys. Must be non-alphanumeric; a letter/digit here is intercepted and not typeable. |

<!-- newText (mirror PRD §11 verbatim): -->
| `@livepicker-session-next-keys` | `(discovered)` | Next-session keys (session axis). Default: discovered `switch-client -n` bindings + `Down`. For this user: `)`, `Down`. Must be non-alphanumeric; a plain letter/digit is intercepted and not typeable. Section 8. |
| `@livepicker-session-prev-keys` | `(discovered)` | Previous-session keys (session axis). Default: discovered `switch-client -p` bindings + `Up`. For this user: `(`, `Up`. Must be non-alphanumeric. Section 8. |
| `@livepicker-window-next-keys`  | `(discovered)` | Next-window keys (window axis — flip the previewed session's windows). Default: discovered next-window bindings. For this user: `C-M-Tab`, `M-n`, `C-n`, `C-l`. Must be non-alphanumeric. Section 8. |
| `@livepicker-window-prev-keys`  | `(discovered)` | Previous-window keys (window axis). Default: discovered prev-window bindings. For this user: `C-M-BTab`, `M-p`, `C-p`, `C-h`. Must be non-alphanumeric. Section 8. |
```

*Prose* (line 171):

```markdown
<!-- oldText: -->
- Letters and digits go to the query by default; set `@livepicker-nav-next-keys` / `-prev-keys` to `j` / `k` for vim-style navigation at the cost of typing them.

<!-- newText: -->
- Letters and digits go to the query by default; set `@livepicker-session-next-keys` / `-session-prev-keys` to `j` / `k` for vim-style navigation at the cost of typing them.
```

### Integration Points

```yaml
CODE:
  - file: scripts/options.sh
    change: "4 old nav accessors removed; 4 new two-axis accessors added (empty default)"
    invariant: "new accessors return '' when unset (=> discover); old names are undefined"

DOCS:
  - file: README.md
    change: "config table 4 rows swapped; 1 prose ref updated"

CONSUMERS (BROKEN until sibling subtasks land — do NOT fix here):
  - scripts/livepicker.sh:388  opt_next_key          -> reworked by P1.M2.T1.S1
  - scripts/livepicker.sh:389  opt_prev_key          -> reworked by P1.M2.T1.S1
  - scripts/livepicker.sh:423  opt_next_key + opt_nav_next_keys -> reworked by P1.M2.T1.S1
  - scripts/livepicker.sh:427  opt_prev_key + opt_nav_prev_keys -> reworked by P1.M2.T1.S1
  - scripts/utils.sh                                    -> lp_discover_axis_keys added by P1.M1.T2.S1

CONFIG / DATABASE / ROUTES: none.
```

## Validation Loop

> **Scope reminder:** S1 is a non-green intermediate (see banner). The full
> `tests/run.sh` suite is NOT expected to pass — it breaks via livepicker.sh T4
> until M1.T2 + M2.T1 land. Validate `options.sh` + README in isolation only.

### Level 1: Syntax & Style (options.sh only)

```bash
cd /home/dustin/.config/tmux/plugins/tmux-livepicker
bash -n scripts/options.sh && echo "OK: syntax"
shellcheck scripts/options.sh          # expect 0 findings
# Old accessors fully gone from options.sh (no commented-out remnants):
grep -nE 'opt_next_key|opt_prev_key|opt_nav_next_keys|opt_nav_prev_keys' scripts/options.sh && echo "FAIL: old accessor present" || echo "OK: old accessors removed"
# Old option NAMES gone from options.sh:
grep -nE '@livepicker-next-key"|@livepicker-prev-key"|@livepicker-nav-next-keys"|@livepicker-nav-prev-keys"' scripts/options.sh && echo "FAIL: old option name present" || echo "OK: old option names gone"
# New accessors present, each exactly once with empty default (Level-4 cross-check):
for s in session-next-keys session-prev-keys window-next-keys window-prev-keys; do
  c="$(grep -c "get_opt \"@livepicker-$s\" \"\"" scripts/options.sh)"
  [ "$c" = 1 ] && echo "OK: @livepicker-$s (x$c)" || echo "FAIL: @livepicker-$s count=$c"
done
```

### Level 2: Structural + isolated-socket behavioral check (no full suite)

```bash
cd /home/dustin/.config/tmux/plugins/tmux-livepicker
# (a) STRUCTURAL — sourcing defines the 4 new fns and NOT the 4 old (no tmux needed):
bash -c 'set -u; source scripts/options.sh
  for f in opt_session_next_keys opt_session_prev_keys opt_window_next_keys opt_window_prev_keys; do
    declare -F "$f" >/dev/null && echo "OK defined: $f" || echo "FAIL missing: $f"
  done
  for f in opt_next_key opt_prev_key opt_nav_next_keys opt_nav_prev_keys; do
    declare -F "$f" >/dev/null && echo "FAIL still defined: $f" || echo "OK removed: $f"
  done'
# Expected: 4 "OK defined" + 4 "OK removed".

# (b) BEHAVIORAL — each new accessor returns "" when the option is unset (=> discover),
#     on an ISOLATED -L socket (never the user's server):
SOCK="lp-s1-$$"; /usr/bin/tmux -L "$SOCK" new-session -d -s x 2>/dev/null
bash -c 'set -u; source scripts/options.sh
  for f in opt_session_next_keys opt_session_prev_keys opt_window_next_keys opt_window_prev_keys; do
    v="$("$f")"; [ -z "$v" ] && echo "OK $f -> empty (discover)" || echo "FAIL $f -> [$v]"
  done'
/usr/bin/tmux -L "$SOCK" kill-server 2>/dev/null
# (get_opt calls bare `tmux`; this bash inherits your shell's tmux — to truly isolate,
#  use the test harness PATH shim, or accept that the options are unset on any socket.)
# Expected: 4 "OK ... -> empty (discover)". A non-empty result means you baked a default.
```

### Level 3: Stale-caller inventory (for M2.T1 — record, do not fix)

```bash
cd /home/dustin/.config/tmux/plugins/tmux-livepicker
echo "=== stale references that WILL break (fixed by P1.M2.T1.S1) ==="
grep -nE 'opt_next_key|opt_prev_key|opt_nav_next_keys|opt_nav_prev_keys' scripts/livepicker.sh
# Expected (record these for M2.T1): livepicker.sh:388, 389, 423, 427 (+ comment 386).
# Do NOT edit livepicker.sh here.
echo "=== confirm NO test names the old accessors directly (so S1's own validation is clean) ==="
grep -nE 'opt_next_key|opt_prev_key|opt_nav_next_keys|opt_nav_prev_keys' tests/ && echo "WARN: test references old accessor" || echo "OK: no test names old accessors"
```

### Level 4: README checks

```bash
cd /home/dustin/.config/tmux/plugins/tmux-livepicker
# Old rows gone from the config table:
grep -nE '\@livepicker-next-key\`|\@livepicker-prev-key\`|\@livepicker-nav-next-keys\`|\@livepicker-nav-prev-keys\`' README.md && echo "WARN: old option still in README" || echo "OK: old options gone from README"
# New rows present:
for s in session-next-keys session-prev-keys window-next-keys window-prev-keys; do
  grep -q "@livepicker-$s" README.md && echo "OK: README has @livepicker-$s" || echo "FAIL: README missing @livepicker-$s"
done
# Defaults say (discovered), not a baked key:
grep -E '@livepicker-(session|window)-(next|prev)-keys' README.md | grep -v '(discovered)' | grep '|' && echo "WARN: a new row lacks (discovered) default" || echo "OK: all new rows default (discovered)"
# Prose ref updated:
grep -q '@livepicker-session-next-keys' README.md && grep -q 'vim-style' README.md && echo "OK: prose updated" || echo "WARN: check prose line ~171"
```

## Final Validation Checklist

### Technical Validation (scoped — see sequencing banner)
- [ ] `bash -n scripts/options.sh` clean; `shellcheck` 0 findings.
- [ ] L1: 4 old accessors + 4 old option names gone from options.sh; 4 new accessors each x1 with `""` default.
- [ ] L2: sourcing defines the 4 new fns, NOT the 4 old; each new accessor ⇒ `""` when unset (discover).
- [ ] **NOT a gate for S1**: `tests/run.sh` full suite (breaks via livepicker.sh T4 until M1.T2 + M2.T1).

### Feature Validation
- [ ] New accessors are space-list with empty default (explicit-override probe).
- [ ] README: 4 new rows (PRD §11 verbatim: `(discovered)`, "For this user", "Must be non-alphanumeric"); 4 old rows gone; prose updated.
- [ ] Stale livepicker.sh call sites (388/389/423/427) inventoried for M2.T1; untouched here.

### Code Quality Validation
- [ ] Single-line `{ get_opt …; } # comment` shape; PRD §11 ordering preserved (between zoxide and confirm).
- [ ] Old accessors DELETED (not commented); no shim.
- [ ] No scope creep: no discovery logic, no utils.sh/livepicker.sh/test changes.

### Documentation & Deployment
- [ ] README table + prose updated (Mode A, per contract point 5). Full README/CHANGELOG prose sync is P4.M1.T1.S1 — do not expand scope here.
- [ ] options.sh accessor comments cite PRD §8/§11 + the empty=discover contract.

---

## Anti-Patterns to Avoid

- ❌ Don't keep the suite green by shimming/commenting the old accessors or editing
  livepicker.sh — that steals M1.T2/M2.T1's work and hides the rename signal. S1 is a
  non-green intermediate by design.
- ❌ Don't bake a discovered default ("C-M-Tab", "Down", etc.) into the accessors —
  empty `""` is the contract (empty ⇒ discover). A baked default disables discovery.
- ❌ Don't change single-key → list semantics implicitly — the new accessors return a
  space-list; that's why T4 needs real rework (M2.T1), not a 1:1 swap.
- ❌ Don't append the new accessors at EOF — replace lines 30-33 in place to keep PRD §11
  ordering and the cross-check invariant.
- ❌ Don't add `lp_discover_axis_keys` or any utils.sh change here (that's P1.M1.T2.S1).
- ❌ Don't expand the README edit beyond the 4 rows + 1 prose line (full sync is P4.M1.T1.S1).
- ❌ Don't claim the full suite passes — it can't, mid-changeset. Scope validation honestly.
- ❌ Don't run the behavioral check against the user's real tmux server — use an isolated
  `-L` socket (or the test harness PATH shim).

---

## Confidence Score

**9 / 10** for one-pass success *within S1's scoped definition*. Rationale: the edit
is 4 lines out / 4 lines in (exact oldText/newText provided, anchored on the verbatim
current content), the README old/new rows are quoted word-for-word from PRD §11, the
empty-default contract and the remove-don't-comment rule are unambiguous, and the
validation is honestly scoped to options.sh + README (structural + isolated-socket
checks) with the stale-caller inventory handed off to M2.T1. The one residual risk
is the orchestrator treating S1 as independently shippable (it is NOT) — which the
sequencing banner addresses head-on. Within its scope, nothing is left to inference.
