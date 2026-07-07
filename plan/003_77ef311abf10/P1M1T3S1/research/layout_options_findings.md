# Layout option accessors grounding (P1.M1.T3.S1)

> Verified LIVE on 2026-07-07 (`tmux 3.6b`, `bash 5.3.15`, `shellcheck 0.11.0`).
> Grounds the 5 new option accessors in `scripts/options.sh` + the 5 README rows.
> The one non-trivial point is the `@livepicker-search-icon` default (a Nerd-Font glyph).

## Environment

| Tool | Version |
|---|---|
| tmux | **3.6b** |
| bash | **5.3.15(1)-release** |
| shellcheck | **0.11.0** |

---

## FINDING 1 — the accessor pattern + insertion point

`scripts/options.sh` is a sourced library (NO side effects; `set -u`, no `-e`). Each
option is a one-liner delegating to `get_opt`:
```bash
opt_query_gap()  { get_opt "@livepicker-query-gap" "2"; }
```
- The LAST accessor today is `opt_preview_defer()` (line 46). The 5 new accessors go
  AFTER it, in PRD §11 order.
- `get_opt "$1" "$2"` returns the user-set value if non-empty, else `$2` (the baked
  default). Every default is PRD §11 verbatim.
- The header comment (lines 21-24) notes the ARGUMENT formatting (single space) is for a
  Level-4 grep cross-check that matches `get_opt "@livepicker-<suffix>" "<default>"`
  once each. The `{` column alignment is cosmetic (bash-irrelevant); align the new block
  internally to its longest name (`opt_overflow_right_format`).

## FINDING 2 — `opt_show_count` is KEPT (contract override of codebase_patterns.md)

`plan/003_77ef311abf10/architecture/codebase_patterns.md` (P2, line 34) says "REMOVE
`opt_show_count()`". The WORK-ITEM CONTRACT explicitly overrides: "Do NOT remove
opt_show_count (deferred to P1.M2.T3 where its last consumer is removed atomically)."
→ KEEP `opt_show_count()` (line 43) and its README row (line 114) UNTOUCHED. The atomic
removal happens in P1.M2.T3.S1 (window-status path), not here. This PRP only ADDS.

## FINDING 3 — the search-icon default: `$'\uf002'` ANSI-C quoting (PRIMARY)

`@livepicker-search-icon` default is U+F002 (`nf-fa-search`), a 3-byte UTF-8 glyph
(`ef 80 82`). Three ways to write the default were tested:

| Source form | What bash stores as $2 | Bytes returned | Verdict |
|---|---|---|---|
| `"\uf002"` (double-quoted) | the 6-char literal `\uf002` | `5c 75 66 30 30 32` | ❌ WRONG (bash doesn't expand `\u` in `"…"`) |
| `$'\uf002'` (ANSI-C quoting) | the 3-byte glyph (expanded at parse time) | `ef 80 82` | ✅ CORRECT + readable |
| literal glyph bytes in `"…"` | the 3-byte glyph | `ef 80 82` | ✅ CORRECT but invisible/fragile in transit |

Proven live (both correct forms are byte-identical):
```
$ opt_A() { get_opt_default "@livepicker-search-icon" "$glyph"; }   # literal glyph
$ opt_B() { get_opt_default "@livepicker-search-icon" $'\uf002'; }  # ANSI-C
$ opt_A | xxd   → ef 80 82
$ opt_B | xxd   → ef 80 82
# [ "$(opt_A | xxd)" = "$(opt_B | xxd)" ] → YES — identical bytes
```

**PRIMARY recommendation: `$'\uf002'` ANSI-C quoting.** Rationale:
- **Plain ASCII in the source** (`$'\uf002'`) — no invisible bytes to mangle through the
  PRP/edit-tool transit (the literal-glyph form is fragile to copy/paste/terminal mangling).
- **Bash expands it ONCE at parse time** (when the function is defined at source time),
  storing the 3-byte glyph in the function body. Each call passes the already-expanded
  glyph — zero runtime overhead (the renderer calls it on every redraw).
- **Self-documenting** — a reader sees `\uf002` and knows the codepoint.
- **Byte-identical** to the literal glyph (proven), so it satisfies the contract's "emit the
  raw UTF-8 byte sequence U+F002" at runtime.

This is a deliberate, documented ONE-LINE deviation from the file's double-quote
convention, justified solely because the default is a non-ASCII Unicode glyph. The Level-4
default cross-check (grep) cannot match an invisible glyph anyway; for THIS accessor,
verify by NAME (`@livepicker-search-icon`) + byte inspection (`xxd`), not a literal-string
grep. (The literal-glyph-in-`"…"` form is an acceptable alternative if strict byte-literalism
in the source is preferred; generate it via `printf '\uf002'` and verify `ef 80 82`.)

## FINDING 4 — the other 4 defaults are plain ASCII (no gotchas)

| accessor | option | default | kind |
|---|---|---|---|
| `opt_nerd_fonts` | `@livepicker-nerd-fonts` | `on` | bool on/off (opt-out for the icon) |
| `opt_query_gap` | `@livepicker-query-gap` | `2` | int (spaces between query and first tab) |
| `opt_overflow_left` | `@livepicker-overflow-left` | `<` | string (left overflow indicator; presence-only) |
| `opt_overflow_right_format` | `@livepicker-overflow-right-format` | `+%d>` | format string (`%d` = total hidden tabs) |

All are plain ASCII, double-quoted, matching the file convention. `+%d>` and `<` contain
no bash-special chars inside double quotes (no backtick/`$`/`"`). The `%d` is a printf-style
placeholder consumed by the renderer (PRD §19); it is NOT expanded by bash (it's a literal
in the string). `<` is a literal less-than (no redirection risk inside `"…"`).

## FINDING 5 — no `set -u` / sourcing concern

- The new accessors are pure one-liners delegating to `get_opt`; no new locals, no new
  sourcing. options.sh already sources nothing (it IS the leaf library). Adding 5 function
  defs cannot break the no-side-effects contract.
- Under `set -u`: every default is a literal (no unset-var risk). `$'\uf002'` is parse-time
  expansion, not a variable — `set -u`-safe.

## FINDING 6 — README table insertion point + row content

README.md `## Configuration` table (lines 93-115) currently ends at
`@livepicker-status-format-index` (line 115), followed by a blank line + "Set any option…"
(line 117). The 5 new rows are appended AFTER line 115 (before the blank line), in PRD §11
order. The README "Default" column shows `\uf002` (the codepoint NOTATION, matching PRD §11)
for the search icon — NOT the raw glyph (markdown-transit-fragile and invisible to readers).
The raw glyph lives in options.sh.

No markdown-table gotchas: none of the 5 defaults contain a `|` (pipe) so no cell-escaping
needed. `<` and `+%d>` render literally in a table cell. Wrap option names + defaults in
backticks to match the existing rows.

## FINDING 7 — no parallel conflict

P1.M1.T2.S1 (running in parallel) creates `scripts/layout.sh` (pure math: `lp_viewport` +
display-width measurement). It explicitly does NOT touch options.sh / `opt_*` / `get_opt`
(its PRP states "NO get_state/opt_* reads — the caller passes T"). So this options.sh edit
cannot conflict with it. layout.sh will CONSUME these accessors later (via the renderer/
input-handler), but that wiring is P1.M2/P1.M3, not this task.
