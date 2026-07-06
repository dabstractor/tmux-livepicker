# renderer.sh window-status branch grounding (P1.M1.T3.S1)

> Verified LIVE on 2026-07-06 against the user's running tmux server
> (`tmux 3.6b`, `bash 5.3.15`, `shellcheck 0.11.0`) + the tubular theme config.
> These ground the window-status render branch in `scripts/renderer.sh` and surface
> the design decisions the PRP must encode.

## Environment

| Tool | Version |
|---|---|
| tmux | **3.6b** |
| bash | **5.3.15(1)-release** (mapfile supported) |
| shellcheck | **0.11.0** |

---

## FINDING 1 — tubular's resolved template is CLEAN #[…]-styled with `__lp_tab__` baked in

The writer side (P1.M1.T2.S1 `_lp_resolve_tab_templates`) resolves both
`window-status[-current]-format` against a hidden sentinel via `display-message -p`.
Verified live (the exact mechanism the renderer will consume):

```
$ fmt="$(tmux show-options -gwv window-status-current-format)"
$ # ... create sentinel __lp_anchor__ + __lp_tab__ in a hidden session, force anchor active ...
$ tmux display-message -p -t "$SENT:__lp_tab__" "$fmt"
#[fg=#1f1f28,bg=#d27e99,nobold,nounderscore,noitalics]#[fg=#d27e99,bg=#1f1f28] __lp_tab__ #[fg=#1f1f28,bg=#d27e99]
```

Properties (all asserted by the smoke in P1.M1.T2.S1):
- **0 raw `#{`** (every `#{E:@tubular_pill_bg}` etc. expanded to concrete `#hex`).
- **`__lp_tab__` present exactly once** — where `#W` (window name) was. The renderer
  swaps this placeholder → each session name.
- **Window-state bits collapsed to a clean tab**: the sentinel is a non-active,
  single-pane, no-bell window → `#F` empty, no flags (external_tmux_behavior.md Q4).
  The styled output has the pill caps + colors but NO flag glyph — exactly what a
  picker row should show.

→ The renderer's job is purely: pick current-vs-inactive template by index, swap
`__lp_tab__` → escaped session name, join with the separator. NO per-item
`display-message` (the §18 responsiveness contract holds).

## FINDING 2 — the separator is a plain space for tubular; themes MAY use `#{…}`

```
$ tmux show-options -gwv window-status-separator
" "        # (cat -A: a single space — the tmux default)
```

- For tubular (and most themes) the separator is a plain literal. Reading it fresh in
  the renderer via `show-options -gwv` is safe and correct.
- **Edge case (documented, not solved):** a theme that puts `#{…}` in its separator
  would render that `#{…}` LITERALLY between tabs — because `#()` stdout is NOT
  re-parsed for `#{…}` (external_tmux_behavior.md Q2; PRD §17 fact #1). Only `#[…]`
  styling in the separator is applied. This is acceptable: the separator is almost
  always a plain string or a `#[…]-styled` glyph (both render fine), and resolving it
  at activation would require a third cached template (out of scope for this subtask;
  the item says read it fresh via `show-options -gwv`). Default to a space if empty.

## FINDING 3 — DECISION: use `get_state` + non-empty check, NOT `tmux_is_set`

The writer-side contract (P1.M1.T1.S1 "Downstream contract" + P1.M1.T2.S1 FINDING 5)
requires `_lp_resolve_tab_templates` to SET-EMPTY both keys on failure (real
`tmux set-option -g @x ""`, NOT unset) "so the renderer's `tmux_is_set` probe works."
The item description (THIS task) instead says: read both via `get_state` and "if EITHER
is empty → fall through to the existing plain path."

**Analysis — the two are equivalent for the BRANCHING decision, and `get_state` is leaner:**

| Scenario | key state | `get_state` | `tmux_is_set` rc | branching result |
|---|---|---|---|---|
| resolved OK | SET, non-empty | non-empty | 0 | window-status |
| resolved FAILED (set-empty) | SET, `""` | `""` | 0 | **plain** (empty check) |
| helper not yet run (pre-activate refresh) | UNSET | `""` | 1 | **plain** (empty check) |

In EVERY scenario `get_state` + `[ -n ]` yields the correct branch (plain when empty).
`tmux_is_set`'s set-vs-unset distinction (resolved-empty vs not-run) changes NOTHING
about the outcome — both fall to plain. The writer's set-empty contract is still
HONORED (set-empty → "" → plain, exactly as intended).

**Why prefer `get_state`:** the renderer runs on EVERY `refresh-client -S` and has a
tight speed budget (<50ms; ~9 option reads ≈ 30–45ms — codebase_state §4, PRD §16).
Two extra `tmux_is_set` calls (~6–10ms) push that budget for zero branching benefit.
The item's explicit instruction ("Read both templates via get_state… If EITHER is
empty → fall through") is correct AND lean. Follow it. (The T1/T2 `tmux_is_set` note is
a suggested mechanism, not a hard requirement; the hard requirement — "fall to plain on
any empty/unavailable template" — is fully met by the non-empty check.)

## FINDING 4 — the `#`→`##` escape is REQUIRED on the swapped-in name (reuse plain path)

The resolved template contains literal `#` in its `#[fg=#hex…]` styles. When the
renderer emits the template via `#()`, tmux parses `#[…]` as live style directives
(Q2). A session NAME containing `#` must therefore be escaped to `##` so tmux treats
it as a literal `#` (not a stray directive) — this is the EXACT escape the existing
plain path already applies and ships tested (commit 066b733 "Escape hash in renderer
output with display-only doubling tests"; renderer.sh lines 66/99):

```bash
esc_name="${name//\#/##}"     # every # -> ##  (tmux literal-#; Issue 3)
```

**For the window-status path:** apply the escape to the name BEFORE the placeholder
substitution (so only the name's `#` is doubled; the template's own `#[…]` styles are
untouched by the substitution):

```bash
esc_wname="${ws_name//\#/##}"
ws_seg="${ws_tpl//__lp_tab__/$esc_wname}"
```

`${var//pat/rep}` does literal replacement (pat `__lp_tab__` has no glob chars; rep is
not re-scanned), so even a name literally equal to `__lp_tab__` cannot corrupt the
template or recurse. The near-impossible collision is acknowledged by the unique
sentinel name (PRD §17; the item's edge-case note).

## FINDING 5 — branch placement: self-contained block after the SHOW_COUNT case

The current `render()` (codebase_state §4, verified against scripts/renderer.sh):
```
[locals] → [option reads: TYPE/FG/BG/HFG/HBG/SHOW_COUNT + case] → [LIST/FILTER/IDX
reads + mapfile all→TOTAL + mapfile filtered→FLEN] → out="" → [no-match early return]
→ [cidx clamp] → [plain highlight loop] → [SHOW_COUNT suffix] → printf '%s'
```

The item's explicit instruction: "branch right after the option reads and the SHOW_COUNT
case (~line 60), BEFORE the existing plain `out=""` block" and "do NOT duplicate or
branch the plain path — just don't enter the window-status block."

→ The window-status block is a **self-contained early-return** inserted between the
SHOW_COUNT case and the plain path's `LIST=` read. It does its OWN state reads, filter
build (mapfile `lp_build_filtered`), no-match handling (mirror the plain output incl.
`0/$TOTAL`), cidx clamp, template-swap loop, and SHOW_COUNT suffix. The plain path
(everything from `LIST=` onward) is left **byte-for-byte untouched** — the strongest
guarantee that the working plain path cannot regress.

The "duplication" is ONLY the mechanical reads + filter + no-match + cidx (~14 lines of
simple `get_state`/`mapfile`/clamps) — explicitly endorsed by the item ("build the
filtered list the SAME way as plain"). The HIGHLIGHT LOGIC is NOT duplicated: the
window-status block has its own template-swap loop, not a copy of the plain
`#[fg=$FG,bg=$BG]` styling loop.

## FINDING 6 — no-match + SHOW_COUNT suffix mirror the plain path (consistency)

- **no-match (FLEN==0):** emit the SAME `#[fg=$FG,bg=$BG]query> $esc_filter (no match)
  [0/$TOTAL]#[default]` as the plain path. Requires computing a local `ws_total` from
  the unfiltered list (mapfile `ws_all`) — the plain path's `TOTAL`/`all` are in the
  untouched plain block, so the window-status block keeps its own. This is a degenerate
  "nothing to tabify" state; plain styling is correct (there are no theme tabs to draw).
- **SHOW_COUNT suffix:** append the SAME `#[fg=$FG,bg=$BG]query> $esc_filter
  [$((ws_cidx+1))/$ws_flen]#[default]` after the joined tabs. The item: "mirror the
  plain path for consistency." (Keeps the query + count visible under the tab aesthetic.)

## FINDING 7 — the crash guard already wraps the whole render()

renderer.sh line 132: `render || printf '%s' '#[fg=red]livepicker: renderer error#[default]'`.
The window-status block is INSIDE `render()`, so any crash (e.g. a malformed template
tripping a bash error) is caught → red error message, never a blank bar. **Do not** add
a second guard inside the window-status block; the existing top-level guard covers it.
The block must still `return 0` on its happy paths (no-match, normal render) so it
doesn't fall through to the plain path after emitting tabs.

## FINDING 8 — house style (unchanged)

`set -u` (inherited; no `set -e`); tabs for indent; `local` for all locals; double-quote
all expansions EXCEPT the intentional `printf '%s' "$ws_list"` process-substitution feed
(reuses the plain path's mapfile-via-`< <()` idiom — codebase_state §4, FINDING 3 of the
renderer research: process substitution, NOT here-string, so an empty list stays `[]` not
`[""]`). `printf '%s' "$out"` (NO trailing newline — multi-line #() stdout renders only
the last line). The new locals are `ws_`-prefixed to be visually distinct from the plain
path's `LIST/FILTER/...` (only one path runs, but the prefix avoids any confusion).
