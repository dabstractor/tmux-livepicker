# PRP — P1.M1.T3.S1: Add P1 layout option accessors to options.sh

---

## Goal

**Feature Goal**: Add the 5 PRD §19/§11 layout option accessors to `scripts/options.sh`
(`opt_nerd_fonts`, `opt_search_icon`, `opt_query_gap`, `opt_overflow_left`,
`opt_overflow_right_format`), each baking in its PRD §11 default, and add the 5
corresponding rows to README.md's Configuration table. These are the integration seams
the renderer (P1.M2) and input-handler (P1.M3) consume for the §19 query-bar + viewport +
overflow layout. `opt_show_count` is KEPT (its atomic removal is P1.M2.T3).

**Deliverable**: (a) 5 new one-liner accessors appended after `opt_preview_defer` in
`scripts/options.sh`; (b) 5 new rows appended to the README.md Configuration table.
**No new files.** No existing accessor or row is changed.

**Success Definition**:
- All 5 accessors return their PRD §11 default when the option is unset (verified live),
  INCLUDING `opt_search_icon` returning the 3-byte U+F002 glyph (`ef 80 82`).
- `opt_show_count` and every other existing accessor are byte-identical (diff shows ONLY
  the 5 new lines).
- README.md Configuration table has the 5 new rows with correct defaults/purposes.
- `bash -n` + `shellcheck` clean; the 44-test `tests/run.sh` suite stays green (the new
  accessors are unused until P1.M2 wires them, so no existing test is affected).

## User Persona (if applicable)

**Target User**: Downstream scripts (renderer.sh P1.M2, input-handler.sh P1.M3) and, via
the README, the end user configuring the picker's status-line layout.

**Use Case**: The renderer reads `opt_search_icon`/`opt_query_gap`/`opt_overflow_*` to draw
the §19 query bar + overflow indicators; `opt_nerd_fonts` gates whether the icon shows at
all. A user sets `@livepicker-nerd-fonts off` (no Nerd Font installed) → the renderer omits
the icon and shows query text only.

**Pain Points Addressed**: Centralizes the 5 new defaults so downstream scripts don't
hardcode them (drift/typos); makes the options discoverable in the README config table.

---

## Why

- **Integration seam for §19.** The renderer rework (P1.M2) and scroll wiring (P1.M3) need
  stable accessor names + defaults before they're written. Landing them now (with the
  README rows) unblocks both without coupling to their implementation.
- **Matches the established, battle-tested pattern.** Every `@livepicker-*` option already
  has a one-liner `opt_<name>()` accessor baking in its PRD default. These 5 follow it
  exactly, so the 44-green suite and the no-side-effects contract hold by construction.
- **The search-icon default is the one subtlety** — a Nerd-Font glyph (U+F002). This PRP
  encodes the empirically-proven way to embed it (`$'\uf002'` ANSI-C quoting) so the
  implementer doesn't rediscover that `"\uf002"` (double-quoted) is the WRONG 6-char literal.

## What

Five new accessors appended after `opt_preview_defer()` (the current last accessor),
followed by 5 new rows in the README Configuration table. The accessors:

| accessor | option | default | kind |
|---|---|---|---|
| `opt_nerd_fonts` | `@livepicker-nerd-fonts` | `on` | bool on/off (opt-out for the icon; tmux can't detect the font) |
| `opt_search_icon` | `@livepicker-search-icon` | U+F002 (`nf-fa-search`, bytes `ef 80 82`) | glyph string |
| `opt_query_gap` | `@livepicker-query-gap` | `2` | int (spaces between query and first tab) |
| `opt_overflow_left` | `@livepicker-overflow-left` | `<` | string (left overflow indicator; presence-only) |
| `opt_overflow_right_format` | `@livepicker-overflow-right-format` | `+%d>` | format (`%d` = total hidden tabs) |

### Success Criteria

- [ ] 5 accessors present after `opt_preview_defer`, each a one-liner delegating to `get_opt`.
- [ ] `opt_search_icon` returns the 3-byte glyph `ef 80 82` when unset (NOT the 6-char
      literal `\uf002`).
- [ ] The other 4 return their exact PRD default (`on`, `2`, `<`, `+%d>`).
- [ ] `opt_show_count` UNTOUCHED (kept; removal is P1.M2.T3).
- [ ] README Configuration table has the 5 new rows (defaults: `on`, `\uf002`, `2`, `<`,
      `+%d>`) after `@livepicker-status-format-index`.
- [ ] `bash -n` + `shellcheck` clean; `tests/run.sh` green.

## All Needed Context

### Context Completeness Check

_Pass_: The implementer needs (a) the verbatim 5 accessor lines + 5 README rows (below),
(b) the one critical gotcha (`$'\uf002'` not `"\uf002"`), and (c) the validation commands.
Every default is PRD §11 verbatim; every behavior is verified live.

### Documentation & References

```yaml
# MUST READ — the empirical ground-truth (the search-icon gotcha is load-bearing)
- docfile: plan/003_77ef311abf10/P1M1T3S1/research/layout_options_findings.md
  why: FINDING 3 (the search-icon default: "\uf002" double-quoted is WRONG — bash leaves it
       as the 6-char literal; use $'\uf002' ANSI-C, proven byte-identical to the glyph ef 80 82);
       FINDING 2 (KEEP opt_show_count — contract overrides codebase_patterns.md's "REMOVE");
       FINDING 4 (the other 4 defaults are plain ASCII, no gotchas); FINDING 6 (README insertion
       point + showing \uf002 notation in the table, not the raw glyph); FINDING 7 (no parallel conflict).
  critical: Read BEFORE writing opt_search_icon. The double-quoted "\uf002" form is the one
            mistake to avoid; it would emit literal backslash-u-f-0-0-2 on the status line.

# MUST READ — the file being edited (exact pattern + insertion point)
- file: scripts/options.sh
  why: The one-liner pattern `opt_<name>() { get_opt "@livepicker-<suffix>" "<default>"; }`.
        The LAST accessor is opt_preview_defer (line 46); insert the 5 new ones AFTER it.
        get_opt (line 15) returns the user value if non-empty, else $2. set -u, NO set -e.
  pattern: every default is PRD §11 verbatim; single space between get_opt args (the header
           comment notes this is for a Level-4 grep cross-check).
  gotcha: opt_search_icon uses $'\uf002' (ANSI-C), NOT "\uf002" (double-quoted) — see FINDING 3.

# MUST READ — the codebase conventions (accessor shapes; the show_count note)
- docfile: plan/003_77ef311abf10/architecture/codebase_patterns.md
  why: P2 shows the accessor pattern + lists the 5 new accessors to add. NOTE line 34 says
        "REMOVE opt_show_count" — the WORK-ITEM CONTRACT OVERRIDES this: KEEP it (P1.M2.T3
        removes it atomically with its last consumer). Follow the contract, not this line.
  section: "P2 — Option accessors (options.sh)"

# MUST READ — PRD §11 (the authoritative defaults) + §19 (what the options mean)
- docfile: PRD.md  (repo root)
  why: §11 is the verbatim default source for all 5 options. §19 (query bar / viewport /
        overflow) defines what each option DOES — the README "Purpose" text is drawn from it.
  section: "§11 Configuration options" (the 5 rows) + "§19 Status-line layout"

# MUST READ — the README table being extended
- file: README.md
  why: The ## Configuration table (lines 93-115) ends at @livepicker-status-format-index.
        Insert the 5 new rows AFTER line 115 (before the blank line + "Set any option…").
        Wrap option names + defaults in backticks; match the existing column layout.
  pattern: existing rows are `| \`@livepicker-x\` | \`default\` | purpose |`.
  gotcha: show \uf002 (the codepoint NOTATION) in the README Default column, NOT the raw
          glyph (markdown-transit-fragile + invisible to readers). The raw glyph is in options.sh.

# CONTEXT — the parallel sibling (confirms no conflict)
- docfile: plan/003_77ef311abf10/P1M1T2S1/PRP.md
  why: P1.M1.T2.S1 creates scripts/layout.sh (pure viewport math). Its PRP states it does NOT
        touch options.sh/opt_*/get_opt ("NO get_state/opt_* reads"). So this options.sh edit
        cannot conflict. layout.sh will CONSUME these accessors later (via renderer/input-handler).
```

### Current Codebase tree

```bash
tmux-livepicker/
  scripts/
    options.sh   # MODIFY: +5 accessors after opt_preview_defer (line 46)
    rank.sh      # (P1.M1.T1, COMPLETE) — unchanged
    layout.sh    # (P1.M1.T2, IN PARALLEL) — does NOT touch options.sh
    ... (utils/state/filter/livepicker/input-handler/preview/renderer/restore)  # UNCHANGED
  README.md      # MODIFY: +5 rows in the Configuration table
  tests/         # UNCHANGED (these accessors are unused until P1.M2; no test touches them)
```

### Desired Codebase tree with files to be added and responsibility of file

```bash
scripts/options.sh   # +5 layout option accessors (the §19 integration seams)
README.md            # +5 Configuration-table rows (Mode A docs ride with the work)
```

### Known Gotchas of our codebase & Library Quirks

```bash
# CRITICAL (FINDING 3): opt_search_icon's default is the U+F002 GLYPH (bytes ef 80 82), NOT
# the 6-char literal "\uf002". bash does NOT expand \u inside DOUBLE quotes:
#   get_opt "@livepicker-search-icon" "\uf002"   # WRONG — returns the literal \uf002 (6 chars)
# Use ANSI-C quoting $'\uf002' — bash expands it to the 3-byte glyph ONCE at parse time:
#   get_opt "@livepicker-search-icon" $'\uf002'  # CORRECT — returns ef 80 82
# Proven live: $'\uf002' and the literal glyph produce byte-identical output (ef 80 82).
# This is the ONE accessor that deviates from the double-quote convention, because the
# default is a non-ASCII Unicode glyph. The literal-glyph-in-"…" form also works but is
# fragile to copy/paste/terminal mangling (invisible bytes); $'\uf002' is plain ASCII in
# the source and self-documenting.

# CRITICAL (FINDING 2 — contract override): KEEP opt_show_count (line 43) and its README row
# (line 114). codebase_patterns.md says "REMOVE" it, but the work-item contract defers the
# removal to P1.M2.T3.S1 (where the last SHOW_COUNT consumer — the window-status render path
# — is removed atomically). Removing it here would break the still-live plain render path.
# This task ONLY ADDS; it does not remove.

# GOTCHA: the Level-4 default cross-check grep (header comment, lines 21-24) matches
# `get_opt "@livepicker-<suffix>" "<default>"` once each. For opt_search_icon the source is
# `get_opt "@livepicker-search-icon" $'\uf002'` (ANSI-C, not double-quoted), so a literal-string
# grep won't match. Verify THIS accessor by NAME + byte inspection (xxd), not a string grep.
# The other 4 new accessors match the grep convention normally.

# GOTCHA: options.sh is a SOURCED library (NO side effects). Adding 5 function defs cannot
# break the contract (no top-level tmux calls, no echo, no SCRIPT_DIR). Do NOT add a driver.

# GOTCHA: `+%d>` and `<` defaults contain no bash-special chars inside double quotes (no
# backtick/$/"). The `%d` is a printf-style placeholder consumed by the RENDERER (PRD §19),
# NOT expanded by bash — it's a literal in the string. Do NOT escape it.

# GOTCHA: indent with TABS is NOT required for these accessors — they are top-level (column 0)
# function defs, matching every other opt_*() in the file (none are indented). Align the `{`
# within the new 5-line block (longest name: opt_overflow_right_format); bash-irrelevant but
# matches the file's tidy style. Do NOT realign existing rows.

# GOTCHA: README markdown table — none of the 5 defaults contain a `|` (pipe), so no cell
# escaping is needed. Show `\uf002` (codepoint notation) in the README Default column for
# @livepicker-search-icon (NOT the raw glyph — invisible + markdown-fragile); the raw glyph
# lives in options.sh.
```

## Implementation Blueprint

### Data models and structure

No data model — only 5 function defs + 5 table rows. The accessor block (defaults are PRD
§11 verbatim; `opt_search_icon` uses `$'\uf002'` per FINDING 3):

```bash
opt_nerd_fonts()             { get_opt "@livepicker-nerd-fonts" "on"; }             # bool on/off (opt-out for the search icon; tmux can't detect the font)
opt_search_icon()            { get_opt "@livepicker-search-icon" $'\uf002'; }       # glyph: nf-fa-search U+F002 (ANSI-C -> bytes ef 80 82; NOT "\uf002")
opt_query_gap()              { get_opt "@livepicker-query-gap" "2"; }               # int: spaces between query and first tab while a query is active (PRD §19)
opt_overflow_left()          { get_opt "@livepicker-overflow-left" "<"; }           # left overflow indicator (presence-only; shown when @livepicker-scroll > 0)
opt_overflow_right_format()  { get_opt "@livepicker-overflow-right-format" "+%d>"; } # right overflow; %d = total hidden tabs (PRD §19)
```

### Implementation Tasks (ordered by dependencies)

```yaml
Task 1: MODIFY scripts/options.sh — append the 5 accessors
  - LOCATE (by content): the opt_preview_defer line (the current last accessor, line 46):
        opt_preview_defer()        { get_opt "@livepicker-preview-defer" "on"; }      # bool on|off (PRD §18; ...)
  - INSERT the 5 new accessors IMMEDIATELY AFTER it (verbatim block from "Implementation
    Patterns" below). Keep the trailing-comment style (one per line, after `}`).
  - CRITICAL: opt_search_icon uses $'\uf002' (ANSI-C quoting), NOT "\uf002". This is the
    one load-bearing detail — see Known Gotchas / FINDING 3.
  - NAMING: opt_<suffix-with-underscores> (matches every existing accessor).
  - ALIGN: align the `{` within the new 5-line block (longest name opt_overflow_right_format);
    do NOT realign existing rows.
  - PRESERVE: opt_show_count (line 43) and every other accessor byte-identical.
  - NO new sourcing, NO driver, NO side effects.

Task 2: MODIFY README.md — append 5 rows to the Configuration table
  - LOCATE (by content): the table row ending the current table:
        | `@livepicker-status-format-index`  | `0`        | Which status line the picker takes.                                                                  |
    (the row BEFORE the blank line + "Set any option before the plugin loads".)
  - INSERT the 5 new rows IMMEDIATELY AFTER it (verbatim from "Implementation Patterns").
    Wrap option names + defaults in backticks; match the existing column widths roughly.
  - DEFAULT COLUMN for @livepicker-search-icon: show `\uf002` (the codepoint NOTATION),
    NOT the raw glyph (markdown-fragile + invisible). The raw glyph is in options.sh.
  - DO NOT touch the existing @livepicker-show-count row (kept; removal is P1.M2.T3 + P4 docs).

Task 3: VALIDATE (syntax + accessor-default smoke + full suite)
  - RUN: bash -n scripts/options.sh
  - RUN: shellcheck scripts/options.sh (expect 0 NEW findings)
  - RUN: the throwaway smoke (Validation Loop L2) — sources options.sh, asserts each new
    accessor returns its default (opt_search_icon via xxd → ef 80 82; the other 4 via string
    equality); confirms opt_show_count still present. DELETE the smoke after.
  - RUN: tests/run.sh (expect: 44 tests green — the new accessors are unused until P1.M2, so
    no existing test can regress).
```

### Implementation Patterns & Key Details

**Task 1 — the 5 accessors (paste verbatim after `opt_preview_defer`):**

```bash
opt_nerd_fonts()             { get_opt "@livepicker-nerd-fonts" "on"; }             # bool on/off (opt-out for the search icon; tmux can't detect the font)
opt_search_icon()            { get_opt "@livepicker-search-icon" $'\uf002'; }       # glyph: nf-fa-search U+F002 (ANSI-C quoting -> bytes ef 80 82; do NOT use "\uf002")
opt_query_gap()              { get_opt "@livepicker-query-gap" "2"; }               # int: spaces between the query and the first session tab while a query is active (PRD §19)
opt_overflow_left()          { get_opt "@livepicker-overflow-left" "<"; }           # left overflow indicator (presence-only; shown when @livepicker-scroll > 0)
opt_overflow_right_format()  { get_opt "@livepicker-overflow-right-format" "+%d>"; } # right overflow indicator; %d = total hidden tabs, left+right combined (PRD §19)
```

**Task 2 — the 5 README rows (paste verbatim after the `@livepicker-status-format-index` row):**

```markdown
| `@livepicker-nerd-fonts`            | `on`       | Opt-out for the search icon (tmux cannot detect the terminal font). `on` shows the icon; `off` shows query text only. |
| `@livepicker-search-icon`           | `\uf002`   | The icon glyph shown before the query while typing. Default is `nf-fa-search` (U+F002); raw UTF-8 bytes in the source. |
| `@livepicker-query-gap`             | `2`        | Spaces between the query and the first session tab while a query is active. |
| `@livepicker-overflow-left`         | `<`        | Left overflow indicator (presence only; shown when `@livepicker-scroll > 0`). |
| `@livepicker-overflow-right-format` | `+%d>`     | Right overflow indicator; `%d` = total hidden tabs (left + right combined). |
```

NOTE for the implementer: the accessor block + README rows above are the complete, ready
insertions. The ONLY subtlety is `opt_search_icon`'s `$'\uf002'` (ANSI-C) — do NOT
"normalize" it to `"\uf002"` (that breaks it). Everything else is mechanical.

### Integration Points

```yaml
CODE:
  - file: scripts/options.sh
    change: "+5 accessors after opt_preview_defer"
    invariant: "each returns the user value or the PRD default; opt_show_count kept"

DOCS:
  - file: README.md
    change: "+5 Configuration-table rows after @livepicker-status-format-index"
    invariant: "Mode A — config-table rows ride with the work (SOW §5); full prose/overview is P4"

CONSUMERS (later subtasks — DO NOT implement now):
  - P1.M2 (renderer.sh rework): reads opt_search_icon/opt_query_gap/opt_overflow_*/opt_nerd_fonts
    for the §19 query bar + viewport + overflow layout.
  - P1.M2.T3.S1: REMOVES opt_show_count + all SHOW_COUNT logic atomically (NOT this task).
  - P4.T1.S1: full README prose/overview sync.

CONFIG / DATABASE / ROUTES: none.
```

## Validation Loop

### Level 1: Syntax & Style (Immediate Feedback)

```bash
cd /home/dustin/.config/tmux/plugins/tmux-livepicker
bash -n scripts/options.sh && echo "OK: options syntax"
shellcheck scripts/options.sh
# Confirm the 5 accessors + opt_show_count are present:
for fn in opt_nerd_fonts opt_search_icon opt_query_gap opt_overflow_left opt_overflow_right_format opt_show_count; do
  grep -q "^${fn}()" scripts/options.sh && echo "OK: $fn" || echo "FAIL: $fn missing"
done
# Confirm the search-icon default is ANSI-C $'\uf002' (NOT the broken "\uf002"):
grep -c "get_opt \"@livepicker-search-icon\" \$'\\\\uf002'" scripts/options.sh   # -> 1
# (if 0, the implementer used the wrong "\uf002" double-quoted form — fix it)
# README rows present:
grep -c '@livepicker-nerd-fonts\|@livepicker-search-icon\|@livepicker-query-gap\|@livepicker-overflow-left\|@livepicker-overflow-right-format' README.md  # -> 5
# Expected: syntax clean; shellcheck 0 new findings; all 6 accessors present; search-icon ANSI-C.
```

### Level 2: Accessor-default smoke (throwaway; the harness exists but these are leaf reads)

Throwaway smoke (DELETE after). Sources the REAL options.sh and asserts each new accessor
returns its default against an isolated socket (so `show-option -gqv` reads unset → default):

```bash
cat > /tmp/smoke_opts.sh <<'EOF'
#!/usr/bin/env bash
set -u
cd /home/dustin/.config/tmux/plugins/tmux-livepicker
source tests/setup_socket.sh
source tests/helpers.sh
setup_test "lp-opts-smoke"
# ensure all 5 options are UNSET (so get_opt returns the default)
for o in nerd-fonts search-icon query-gap overflow-left overflow-right-format; do
    tmux set-option -gu "@livepicker-$o" 2>/dev/null || true
done
source scripts/options.sh

pass_n=0; fail_n=0
ck() { if [ "$2" = "$3" ]; then pass_n=$((pass_n+1)); else fail_n=$((fail_n+1)); echo "FAIL $1: got[$2] want[$3]"; fi; }

ck "nerd_fonts default"   "$(opt_nerd_fonts)"            "on"
ck "query_gap default"    "$(opt_query_gap)"             "2"
ck "overflow_left default" "$(opt_overflow_left)"        "<"
ck "overflow_right_format" "$(opt_overflow_right_format)" "+%d>"
ck "show_count still present" "$(opt_show_count)"        "on"    # KEPT (contract)

# search-icon: assert the EXACT 3-byte glyph ef 80 82 (NOT the 6-char "\uf002" literal)
# Capture via $(...) first (strips echo's trailing newline, as a real consumer does);
# piping opt_search_icon straight to xxd/wc would include the newline (ef80820a / 4).
icon="$(opt_search_icon)"
icon_bytes="$(printf '%s' "$icon" | xxd -p)"
if [ "$icon_bytes" = "ef8082" ]; then pass_n=$((pass_n+1));
else fail_n=$((fail_n+1)); echo "FAIL search_icon bytes: got [$icon_bytes] want [ef8082] (if 5c7566303032 you used \"\\uf002\" — use \$'\\uf002')"; fi
ck "search_icon is 3 bytes (not 6)" "$(printf '%s' "$icon" | wc -c)" "3"
# NOTE: ${#icon} is 1 (one Unicode CODEPOINT), not 3 — ${#var} counts chars, not bytes.
# The byte checks above (xxd ef8082 / wc -c 3) are authoritative; do not assert on ${#icon}.

# override surfacing: set nerd-fonts off -> opt returns the override
tmux set-option -g @livepicker-nerd-fonts off
ck "nerd_fonts override" "$(opt_nerd_fonts)" "off"

teardown_test
echo "pass=$pass_n fail=$fail_n"
[ "$fail_n" -eq 0 ]
EOF
bash /tmp/smoke_opts.sh; rc=$?
rm -f /tmp/smoke_opts.sh
exit $rc
# Expected: pass~=7 fail=0. The search_icon byte check (ef8082) is the load-bearing
# assertion — it FAILS if the implementer used "\uf002" (would be 5c7566303032, 6 bytes).
```

### Level 3: Full suite (no regression)

```bash
cd /home/dustin/.config/tmux/plugins/tmux-livepicker
tests/run.sh
# Expected: exit 0, all 44 tests green. The 5 new accessors are not yet called by any
# script (P1.M2 wires them), so sourcing options.sh defines 5 extra no-side-effect
# functions and nothing else changes. No existing assertion can regress.
```

### Level 4: Cross-check + raw-glyph alternative sanity

```bash
cd /home/dustin/.config/tmux/plugins/tmux-livepicker
# Cross-check the 4 plain-ASCII defaults appear exactly once in the source (grep convention):
for pair in "nerd-fonts:on" "query-gap:2" "overflow-left:<" "overflow-right-format:+%d>"; do
  suf="${pair%%:*}"; want="${pair#*:}"
  hits="$(grep -c "get_opt \"@livepicker-${suf}\" \"${want}\"" scripts/options.sh)"
  [ "$hits" = "1" ] && echo "OK: @livepicker-${suf} default '${want}' once" || echo "MISMATCH: ${suf} hits=$hits"
done
# search-icon is ANSI-C (not double-quoted) — verify by bytes, not a string grep:
echo -n "source form: "; grep '^opt_search_icon' scripts/options.sh
echo -n "runtime bytes: "; bash -c 'source scripts/options.sh 2>/dev/null; opt_search_icon' | xxd   # needs tmux; use the L2 smoke instead for the unset path

# Raw-glyph alternative sanity (if the implementer chose the literal-glyph form, confirm it
# is also 3 bytes ef 80 82 — byte-identical to $'\uf002'):
glyph="$(printf '\uf002')"
printf 'literal-glyph bytes: '; printf '%s' "$glyph" | xxd   # expect ef 80 82
# Expected: the 4 string defaults match once each; the search-icon line shows $'\uf002' in
# source and resolves to ef 80 82 at runtime (L2 smoke asserts the runtime bytes).
```

## Final Validation Checklist

### Technical Validation

- [ ] `bash -n scripts/options.sh` clean.
- [ ] `shellcheck scripts/options.sh`: 0 NEW findings.
- [ ] The 5 new accessors present after `opt_preview_defer`; `opt_show_count` still present.
- [ ] `opt_search_icon` source uses `$'\uf002'` (ANSI-C), NOT `"\uf002"`.

### Feature Validation

- [ ] `opt_nerd_fonts` → `on`; `opt_query_gap` → `2`; `opt_overflow_left` → `<`;
      `opt_overflow_right_format` → `+%d>` (L2 smoke).
- [ ] `opt_search_icon` → bytes `ef 80 82` (3 bytes), NOT `5c7566303032` (L2 smoke — the
      load-bearing assertion).
- [ ] Override surfacing: `@livepicker-nerd-fonts off` → `opt_nerd_fonts` → `off` (L2).
- [ ] README Configuration table: 5 new rows after `@livepicker-status-format-index`.
- [ ] Full `tests/run.sh` suite green (exit 0); no regression.

### Code Quality Validation

- [ ] One-liner pattern matching every existing `opt_*`; defaults PRD §11 verbatim.
- [ ] `opt_search_icon` uses `$'\uf002'` with a comment explaining why (not `"\uf002"`).
- [ ] `{` aligned within the new block; existing rows NOT realigned.
- [ ] No new sourcing, no driver, no side effects (sourced library contract holds).
- [ ] README rows wrapped in backticks; `\uf002` notation (not raw glyph) in the Default column.

### Documentation & Deployment

- [ ] Mode A: the 5 README config rows ride with the work (SOW §5). Full prose/overview is P4.
- [ ] Each accessor has a trailing comment (default + purpose + the §19/§11 reference).
- [ ] No CHANGELOG entry here (the changeset-level sync is P4.T1.S2).

---

## Anti-Patterns to Avoid

- ❌ Don't use `"\uf002"` (double-quoted) for the search-icon default — bash leaves it as the
  6-char literal `\uf002` (renders as garbage on the status line). Use `$'\uf002'` (ANSI-C),
  proven to expand to the glyph bytes `ef 80 82`. (FINDING 3 — THE one mistake to avoid.)
- ❌ Don't remove `opt_show_count` — codebase_patterns.md says to, but the work-item contract
  defers it to P1.M2.T3.S1 (atomic removal with its last consumer). KEEP it + its README row.
- ❌ Don't show the raw glyph in the README Default column — use `\uf002` (codepoint notation,
  matching PRD §11). The raw glyph is markdown-fragile and invisible to readers.
- ❌ Don't realign the existing accessor rows — align only the new 5-line block internally.
- ❌ Don't add a driver (`*_main`) or top-level tmux calls — options.sh is a sourced library.
- ❌ Don't escape `+%d>` or `<` — they contain no bash-special chars inside double quotes;
  `%d` is a renderer-side printf placeholder, not a bash expansion.
- ❌ Don't wire the accessors into the renderer/input-handler — that's P1.M2/P1.M3. This task
  only DEFINES them (+ the README rows).
- ❌ Don't collapse the search-icon into a computed default (`$(printf '\uf002')`) — that
  runs a subshell on every call (the renderer calls it each redraw). `$'\uf002'` expands once
  at parse time; the literal glyph is stored in the function def (zero runtime cost).
- ❌ Don't add a committed tests/ file — these are leaf accessors; validate via the throwaway
  L2 smoke. (The §19 layout/ranking tests are P1.M4.)
- ❌ Don't edit by line number — anchor on the `opt_preview_defer` content (Task 1) and the
  `@livepicker-status-format-index` README row (Task 2).

---

## Confidence Score

**9 / 10** for one-pass success. Rationale: the deliverable is 5 one-liner accessors + 5
README rows, each given verbatim, following a pattern every existing accessor already
establishes. The single load-bearing subtlety (`opt_search_icon`'s `$'\uf002'` ANSI-C
default, not `"\uf002"`) is empirically proven (both forms tested; `ef 80 82` vs the broken
`5c7566303032`) and asserted in the L2 smoke with a byte-level check that FAILS loudly if the
wrong form is used. `opt_show_count` is explicitly kept (contract override, documented).
The 5 accessors are unused until P1.M2, so `tests/run.sh` stays green by construction
(sourcing defines 5 extra no-side-effect functions). No parallel conflict (P1.M1.T2.S1 is
layout.sh-only). Residual risk: the implementer "normalizes" `$'\uf002'` to `"\uf002"`
(mitigated by the L2 byte assertion + the Anti-Patterns callout) and a README markdown-table
column-width nit (cosmetic; the rows render correctly regardless).
