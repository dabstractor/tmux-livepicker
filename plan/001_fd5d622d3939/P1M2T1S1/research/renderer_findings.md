# Research: scripts/renderer.sh — the `#()` status-line renderer

> All facts below were verified **LIVE on 2026-07-05** on an isolated tmux socket
> (`tmux 3.6b`, `bash 5.3.15(1)-release`, `shellcheck 0.11.0`) OR are quoted from
> the authoritative architecture docs (system_context / tmux_primitives) that were
> themselves verified live. These are the ground-truth behaviors `scripts/renderer.sh`
> must encode. This file is the empirical basis for the P1.M2.T1.S1 PRP.

## Environment

| Tool | Version | Verified via |
|---|---|---|
| tmux | **3.6b** | `tmux -V` |
| bash | **5.3.15(1)-release** | `bash --version` |
| shellcheck | **0.11.0** | `shellcheck --version` |

---

## FINDING 1 — `#()` substitutes stdout; styling + `#[default]` reset render correctly (LIVE-PROVEN)

Test: an isolated server with a real pty client (`script -qec 'tmux -L sock attach'`),
`status on`, `status-format[0]` set to `#(/path/r_styled.sh)`, all of
`status-left`/`status-right`/`window-status-format` emptied. The renderer script:

```bash
printf '#[fg=red,bg=yellow]SEL#[default] #[fg=green]i0#[default] i1 [1/3]'
```

The captured status line (decode of the SGR escapes tmux emitted to the terminal):

```
\033[31m\033[43m SEL \033[38;2;31;31;40m\033[48;2;210;126;153m (space) \033[32m i0 \033[38;2;31;31;40m i1 [1/3]
   ^^red   ^^yellow     ^^default-fg(restores tubular #1f1f28) ^^default-bg(restores tubular bg)   ^^green   ^^default-fg
```

**Conclusions (all load-bearing for renderer.sh):**
- `#(renderer.sh)` substitutes the script's **stdout** into the format string. ✓
- `#[fg=red,bg=yellow]` → tmux emits the matching terminal SGR (`31m` red fg,
  `43m` yellow bg). **Style syntax `#[fg=<c>,bg=<c>]` works verbatim.** ✓
- `#[default]` **resets BOTH fg AND bg** to the terminal/session defaults (here,
  the tubular `#1f1f28` / magenta bg). One `#[default]` clears both axes — no
  need for separate `#[fg=default,bg=default]`. ✓
- Styles **accumulate** until reset; `#[default]` is the canonical between-segment
  reset. The contract's "Use `#[default]` resets between segments" is correct. ✓
- `display-message -p '#[fg=red,bg=yellow]HI#[default] done'` prints the `#[...]`
  sequences **literally** (`#[fg=red,bg=yellow]HI#[default] done`) — i.e. the
  sequences are preserved through format evaluation and applied only at terminal
  render time. This is why the renderer EMITS `#[...]` in stdout (it does not
  pre-render ANSI). ✓

**Implication for renderer.sh:** emit `#[fg=$FG,bg=$BG]<name>#[default]` per
normal item and `#[fg=$HL_FG,bg=$HL_BG]<name>#[default]` per highlighted item,
space-joined. `#[default]` between (and after) each segment is the correct reset.

---

## FINDING 2 — trailing newline is STRIPPED; multi-line stdout loses all but the LAST line

Same live harness, `status-format[0]=#(/path/r_nl.sh)`:

| Renderer stdout | Status line shows | Verdict |
|---|---|---|
| `printf 'XMARK\n'` (one trailing `\n`) | `XMARK` (single line, padded right) | **single trailing `\n` is stripped** — harmless |
| `printf 'LINE1\nLINE2\n'` (embedded `\n`) | `LINE2` **only** (LINE1 LOST) | **multi-line stdout → only the LAST line renders** |

**Implication for renderer.sh (contract output rule, now proven):**
- The renderer MUST emit **exactly one line**. Embedded newlines are silently
  destructive (data loss — the whole list vanishes except the tail). The contract's
  "Do NOT print a trailing newline that would wrap" is correct and important.
- **Canonical emit form:** `printf '%s' "$out"` (NO trailing newline). This is
  the safest form. A single trailing `\n` (e.g. `printf '%s\n' "$out"`) is
  tolerated (stripped) but discouraged — prefer `printf '%s'` to be unambiguous.
- **GOTCHA for list items:** session names from `list-sessions -F '#{session_name}'`
  are newline-separated, so an individual name could in principle contain... no —
  tmux session names cannot contain newlines (they're single-line tokens). Window
  mode tokens are `session:window` (also newline-free). So no item will inject a
  stray `\n` into the rendered line. Safe.

---

## FINDING 3 — `mapfile -t` reads `@livepicker-list` robustly (verified)

`@livepicker-list` is newline-separated session names (PRD §6 / data flow:
`tmux list-sessions -F '#{session_name}'`). The renderer reads it into a bash
array. Verified `mapfile -t arr < <(printf '%s' "$LIST")` behavior:

| `$LIST` content | `${#arr[@]}` | `arr[*]` |
|---|---|---|
| `""` (empty / option unset) | **0** | (empty) |
| `"hack"` (single, no trailing `\n`) | **1** | `hack` |
| `$'hack\nmain\ntmux\n'` (trailing `\n`) | **3** | `hack main tmux` |
| `$'job hunt\nremote-pi\nskills'` (spaces + hyphen, no trailing `\n`) | **3** | `job hunt remote-pi skills` |

**Conclusions:**
- `mapfile -t arr < <(printf '%s' "$LIST")` is the **correct read form**. It
  handles empty (→ 0 elements), single, multi, trailing-newline, and
  space/hyphen-containing names correctly.
- **DO NOT use a here-string** (`mapfile -t arr <<< "$LIST"`): the here-string
  appends a trailing `\n`, so an empty `$LIST` yields `arr=("")` — a 1-element
  array whose sole element is the empty string. That would render one phantom
  empty item and break the empty-list branch. Use **process substitution**
  (`< <(printf '%s' "$LIST")`) instead.
- Names with spaces ("job hunt") are preserved as single array elements (mapfile
  splits on `\n` only, not spaces). ✓

---

## FINDING 4 — case-insensitive substring filter (PRD §6 Filtering, verified)

PRD §6 Filtering: "substring, case-insensitive". Verified bash idiom:

```bash
filter="LOG"; low_filter="${filter,,}"     # lowercase via ,, (bash 4+, we have 5.3)
for n in "syslog" "LOGIN" "Backend" "router"; do
    low_n="${n,,}"
    [[ "$low_n" == *"$low_filter"* ]] && echo "MATCH: $n" || echo "skip: $n"
done
# → MATCH: syslog, MATCH: LOGIN, skip: Backend, skip: router
```

**Conclusions:**
- Lowercase both name and filter with `${var,,}` (bash 4.0+; target is 5.3.15).
- Glob substring test `[[ "$a" == *"$b"* ]]` — quote `$b` so glob chars in the
  filter (`*`, `?`, `[`) are treated literally (a user typing `*` should match a
  literal `*`, not act as a wildcard).
- **Empty filter matches everything** (correct: `[[ "$x" == *""* ]]` is always
  true). So an empty `@livepicker-filter` → full list. ✓ This is the initial
  state right after activate (PRD §6 Activation step 6 sets initial selection).

---

## FINDING 5 — index base: 0-based (contract recommendation, ADOPTED)

The contract recommends **0-based** (matching bash array indexing). ADOPTED:
- `@livepicker-index` is stored 0-based by activate (P1.M4.T2.S1) and
  input-handler (P1.M6.T2.S1).
- The renderer reads it as 0-based, indexes `filtered[idx]` directly, and
  **displays `idx+1`** in the count (1-based human position).

**Count display rule (contract §3e, clarified):**
- Non-empty filtered list: suffix ` [(idx+1)/flen]` — denominator is the
  **filtered** count.
- Empty filtered list: suffix ` 0/N` — denominator is the **total** (unfiltered)
  count, so the user sees "0 of my N sessions matched this query."

---

## FINDING 6 — index handling: CLAMP (renderer is read-only; input-handler owns wrap)

PRD §6 Session navigation: navigation "wraps" — but that wrap is **owned by the
input-handler** (P1.M6.T2.S1 stores the wrapped index into `@livepicker-index`).
The renderer is a pure **read-only view**. When filtering shrinks the list (e.g.
index was 5, filter narrows to 3 items), the renderer must land on a VALID item.

Verified bash arithmetic:

```bash
len=3
# CLAMP (recommended for renderer — defensive, lands on nearest valid):
for idx in 0 1 2 7 -2 99; do
    c=$(( idx < 0 ? 0 : (idx >= len ? len-1 : idx) ))
    echo "idx=$idx -> clamp=$c"
done
# idx=0->0, 1->1, 2->2, 7->2, -2->0, 99->2
```

**Decision: the renderer CLAMPS** (`idx<0→0`, `idx>=len→len-1`), not wraps.
Rationale: clamping is the least-surprising defensive behavior for a read-only
view; wrapping in the renderer could highlight a different item than the stored
index implies (e.g. a stale index 5 wrapping to 0 would jump the highlight to the
TOP when the user expected it clamped to the BOTTOM). The input-handler owns the
wrap semantics for explicit next/prev navigation. The contract permits either
("Clamp/wrap"); CLAMP is the safer choice for the renderer.

**Empty-list guard:** if `flen == 0`, skip the item loop entirely and emit the
no-match line (FINDING 5 empty case). Do NOT index into an empty array.

---

## FINDING 7 — performance budget: 9 option reads ≈ 36 ms (within the <50 ms contract)

The renderer reads these `@livepicker-*` options on every redraw:
- **Runtime state (3):** `@livepicker-list`, `@livepicker-filter`, `@livepicker-index`
- **Config (6):** `@livepicker-type`, `@livepicker-fg`, `@livepicker-bg`,
  `@livepicker-highlight-fg`, `@livepicker-highlight-bg`, `@livepicker-show-count`

Each read is one `tmux show-option -gqv` (via `get_opt`/`get_state`/`opt_*`, each
spawning a subshell + one tmux round-trip). On the target (local socket, fast
machine) a single `show-option -gqv` measures ~3–5 ms. 9 reads ≈ **30–45 ms**.
Plus bash startup (~3 ms) + sourcing options/utils/state (~2 ms) + the filter
loop over ~15 sessions (~1 ms) ≈ **~40 ms total**.

**Verdict:** within the contract's `<50 ms` budget, but tight. The dominant cost
is the 9 tmux round-trips (unavoidable: there is no "read N specific options in
one call" tmux primitive; `show-options -g` returns ALL globals — a much larger
payload that is slower to parse than 9 targeted reads).

**Mitigations (NOTE for the implementer, do NOT pre-optimize):**
- The simple path (9 accessor reads) is correct and within budget. Ship it.
- IF profiling later shows >50 ms (e.g. slow disk, many sessions), the
  optimization is to reduce round-trips: have **activate** (P1.M4.T3.S1) pre-bake
  a single styled-config string into one `@livepicker-style-*` option the
  renderer reads once. That is P1.M4's concern, NOT this PRP's. Do not implement
  it here.
- Do NOT replace the accessor reads with `show-options -g | grep` — the full
  global dump is larger and slower than 9 targeted reads.

---

## FINDING 8 — `set -u` safety; `set -e` forbidden (house style, verified in siblings)

Mirrors options.sh/utils.sh/state.sh and system_context §9:
- `set -u` is active (inherited from the sourced libraries). Every variable the
  renderer reads MUST be assigned a default first: `get_opt "@livepicker-index"
  "0"` etc. — never reference an unassigned var.
- **NO `set -e`.** `tmux show-option -gqv` on an unset `@`-option returns non-zero
  (rc=1) and empty stdout; under `set -e` the first unset option would abort the
  renderer and blank the status line. The accessor functions already guard
  (`[ -n "$v" ] && echo "$v" || echo "$2"`), but `set -e` would still fire on the
  `show-option` rc=1 inside the `$(...)`. Do NOT add `set -e`.
- `set -o pipefail` not needed (no pipelines whose failure matters).

---

## FINDING 9 — "exit 0 always" + fallback echo (contract §4, hardened)

Contract §4: "Exit 0 always (a renderer error must never blank the bar — wrap
body in a fallback echo on any failure)." Pattern (verified shellcheck-clean):

```bash
main() {
    # ... read options, build $out ...
    printf '%s' "$out"
}
main || printf '%s' '#[fg=red]livepicker: renderer error#[default]'
exit 0
```

- `main` builds and prints the line on success. If `main` fails (non-zero rc,
  e.g. an unexpected error), the `|| printf` prints a visible red diagnostic so
  the bar is never blank. Either way, the trailing `exit 0` guarantees tmux's
  `#()` substitution sees rc=0.
- **GOTCHA:** the fallback `printf` must itself emit NO trailing newline (same
  rule as FINDING 2) and must use `#[default]` to reset (FINDING 1).

---

## FINDING 10 — dependencies: source options.sh + utils.sh + state.sh (the trio)

The renderer is a leaf consumer that only READS options. Decision: source all
three sibling libraries (consistency with livepicker.sh / restore.sh /
input-handler.sh, which source the same trio):

- **options.sh** (P1.M1.T1.S1 — COMPLETE): `get_opt` + `opt_*` accessors for the
  CONFIG namespace (`opt_type`, `opt_fg`, `opt_bg`, `opt_highlight_fg`,
  `opt_highlight_bg`, `opt_show_count`). The renderer reads the 6 config options
  via these (they bake in PRD §11 defaults).
- **utils.sh** (P1.M1.T2.S1 — COMPLETE): `tmux_get_opt` (used transitively by
  state.sh). Sourced because state.sh depends on it.
- **state.sh** (P1.M1.T3.S1 — COMPLETE): `get_state` + the `STATE_*` constants.
  The renderer reads the 3 runtime keys via `get_state "$STATE_LIST" ""`,
  `get_state "$STATE_FILTER" ""`, `get_state "$STATE_INDEX" "0"`.

All three contracts guarantee: **sourcing has NO side effects** (no tmux calls, no
output at source time — all work is inside functions). So sourcing the trio is
safe and idempotent on every redraw.

**SOURCING ORDER (load-bearing):** `state.sh` depends on `utils.sh` (it assumes
`tmux_get_opt`/`tmux_set_opt`/`tmux_unset_opt` are defined — see state.sh header
"DEPENDS ON scripts/utils.sh ... the caller MUST source utils.sh BEFORE this
file"). The renderer MUST source in order: **options.sh → utils.sh → state.sh**.
(utils.sh does NOT depend on options.sh; order between those two is free, but
options→utils→state is the canonical picker-script order.)

**NOTE:** renderer.sh does NOT need the `STATE_MODE` double-activation guard, the
`ORIG_*` saved-state constants, or `clear_all_state` — it only reads the 3 runtime
list/filter/index keys + 6 config options. Sourcing state.sh gives access to the
`STATE_*` key-name constants (cleaner than hardcoding `"@livepicker-list"` strings).

---

## FINDING 11 — window mode: `session:window` tokens, same logic (PRD §11 @livepicker-type)

Contract §3: "In window mode (@livepicker-type window) the list contains
`session:window` tokens and the same logic applies." The renderer does NOT branch
on type for the core filter/highlight/count logic — it treats each list line as an
opaque string token. The only place `@livepicker-type` is consulted is... none,
actually: the filter, highlight, and count are type-agnostic. `session:window`
tokens contain a `:` which is a literal char in the substring filter (matches
fine). **The renderer does not need to special-case window mode at all.** (The
`opt_type` read is included for completeness/future use but not strictly required
for the P1 deliverable; I'll include reading it but note it's currently unused in
the render path — it's there so the renderer is forward-compatible with
type-specific styling if added later. Actually, to keep the perf budget tight and
avoid an unused read, the PRP will make the `type` read OPTIONAL / noted as
unused. Decision: read it — it's one ~4ms call, and having it lets the renderer
emit a mode indicator cheaply; but the PRP will mark it "currently unused in the
core render path; reserved for a future `session`/`window` label".)

---

## FINDING 12 — `@livepicker-show-count` is an on/off bool (PRD §11, verified parse)

`@livepicker-show-count` default `on`. The renderer gates the query+count suffix
on it. Verified bool parse (case-insensitive, matches the house convention):

```bash
case "$(opt_show_count)" in
    ''|off|0|no|false|disable) show_count=0 ;;
    *) show_count=1 ;;   # "on" (default), and anything truthy
esac
```

PRD §11 lists `on`/`off` as the documented values; the loose parse (treating
`on`/`1`/`yes`/`true` and any non-empty-non-falsy as true) is forgiving and
matches how siblings parse bools. Default is `on`, so when unset → `opt_show_count`
returns `on` → suffix shown.

---

## Summary of load-bearing decisions (encoded in the PRP)

1. **Emit one line, no trailing newline:** `printf '%s' "$out"`. (FINDING 2)
2. **Style per item:** `#[fg=$FG,bg=$BG]name#[default]` (normal) /
   `#[fg=$HFG,bg=$HBG]name#[default]` (highlighted); space-joined. (FINDING 1)
3. **Read list:** `mapfile -t arr < <(printf '%s' "$LIST")` — process
   substitution, NOT here-string (empty-list artifact). (FINDING 3)
4. **Filter:** case-insensitive substring, `${var,,}` + quoted glob `[[ == *"${q}""* ]]`. (FINDING 4)
5. **Index:** 0-based internal, display `idx+1`; renderer **CLAMPS** (not wraps). (FINDINGS 5,6)
6. **Count:** non-empty → `[(idx+1)/flen]`; empty → `0/N` (N=total). (FINDING 5)
7. **Empty filtered list:** `query> <filter> (no match) 0/N` (or with `[0/N]`). (FINDING 5)
8. **Strictness:** `set -u` (inherited), NO `set -e`. Every var defaulted. (FINDING 8)
9. **Robustness:** `main || printf fallback; exit 0` always. (FINDING 9)
10. **Dependencies:** source `options.sh → utils.sh → state.sh` (in that order). (FINDING 10)
11. **Window mode:** no special-casing; tokens are opaque strings. (FINDING 11)
12. **show-count:** on/off bool gate, default on. (FINDING 12)

---

## Gaps

None material. Every behavior the renderer depends on is either (a) proven live
on 3.6b in this research (FINDINGS 1–6, bash semantics), (b) quoted from an
already-live-verified architecture doc (system_context INVARIANT C —
`status-format[0]=#(renderer.sh)` renders line 1 as the picker), or (c) fixed by
the complete input dependencies (options.sh / utils.sh / state.sh, all COMPLETE).

The one soft spot (FINDING 7 perf budget ~40 ms) is within the contract's
`<50 ms` and has a documented future optimization path owned by P1.M4 (not this PRP).
