# Research — P1.M4.T3.S1: livepicker.sh status grow (shift + install + set count)

> Empirical ground-truth for the **T3 seam** of `scripts/livepicker.sh` (PRD §10
> steps 2–4: shift user-set status-format indices, install the picker renderer at
> the configured index, grow the status line count by one). All facts below were
> verified **LIVE on `tmux 3.6b`** on 2026-07-05 against an **isolated `-L`
> socket** (zero impact on the real server). These are the load-bearing facts the
> PRP encodes; the implementer need not re-derive them.

## Methodology

- PATH-wrapper socket shim (`exec /usr/bin/tmux -L "$SOCK" "$@"`) on a fresh
  `mktemp` socket; `kill-server` + `rm -rf` on exit.
- `show-option -gv status` / `show-options -g status-format` / `show-option -gqv
  'status-format[n]'` (read + exit-code semantics), `set-option -g
  'status-format[n]'` / `set-option -gu 'status-format[n]'` (single-index unset),
  `set-option -g status {on,off,1,2,3,…}`, and a `set -u` arithmetic probe.
- Cross-checked against `scripts/state.sh` (`ORIG_STATUS`,
  `ORIG_STATUS_FORMAT_INDICES`, `ORIG_STATUS_FORMAT_PREFIX`, `set_state`/`get_state`,
  `state_status_format_save`), `scripts/options.sh` (`opt_status_format_index`),
  `scripts/renderer.sh` (the `#()` target), `system_context.md §3/§4`, and the
  parallel contracts `P1M4T1S1` (save) + `P1M4T2S1` (list/index).
- No web access needed (pure tmux man-page behavior, all local).

## Findings

### FINDING 1 — `status` value gotcha: `on`/`off`/`2..5`, NOT `0`/`1`. **SHOWSTOPPER if untreated.**

`tmux show-option -gv status` returns the **literal strings** `on`, `off`, or an
integer `2`–`5` — **never** `0` or `1`:

```
set-option -g status on  -> show-option -gv status == "on"
set-option -g status 2   -> show-option -gv status == "2"
set-option -g status 1   -> ERROR "unknown value: 1"  (rc!=0; status UNCHANGED)
```

Two compounding consequences for the item's literal `status $((orig_status_count + 1))`:

1. **`set -u` crash.** With `orig_status_count="on"` (the saved value), bash
   arithmetic `$((orig_status_count + 1))` evaluates `on` as a variable NAME;
   `on` is unset → under `set -u` (inherited from options.sh) → **`unbound
   variable`, exit 127**. Verified live: the activate function ABORTS.
2. **`1` is rejected.** Even if arithmetic yielded `1` (e.g. via `on`→0→+1),
   `set-option -g status 1` → **"unknown value: 1"**, status left unchanged.

**Fix (MANDATORY normalization).** Map the saved status to a *settable* new value:

| `@livepicker-orig-status` (saved by STEP 2) | new `status` to set | meaning |
|---|---|---|
| `off` / `0` / `""` | `on` | was off → grow to 1 line (picker only); `1` is invalid |
| `on` | `2` | was 1 line → 2 lines (THE typical case; target env is `on`) |
| `2`,`3`,`4` | `n+1` (numeric) | multi-line grow |
| `5` | `5` | already at the 5-line cap; renderer overlays `[IDX]` (rare) |
| anything else | `2` | defensive default |

A `case` statement (not arithmetic on the raw string) is the correct idiom.

### FINDING 2 — status-format index shift is race-free **highest-first**; single-index `-gu` kills ONLY that index.

Injected `status-format[3]=USER-SET-AT-3` and `status-format[5]=USER-SET-AT-5`,
then shifted **descending** (5, then 3): read live `[n]`, write `[n+1]`, unset `[n]`:

```
after shift: status-format[4]=USER-SET-AT-3 , status-format[6]=USER-SET-AT-5
             (indices 3 and 5 are GONE; no overwrites)
```

- **Ascending is UNSAFE for adjacent indices.** With `[3]=A,[4]=B`, ascending does
  `3→4` (clobbers original B with A) then reads the now-corrupted `[4]`. Descending
  (`4→5` then `3→4`) yields `[4]=A,[5]=B` correctly. PRD §10 step 2 + tmux_primitives
  §3 both mandate highest-first; verified.
- **`set-option -gu 'status-format[n]'` unsets ONLY index `n`** (not the whole
  array). Verified: with `[1]=TEMP-1,[2]=TEMP-2`, `set-option -gu 'status-format[1]'`
  → `[1]` gone, `[2]` survives. (Contrast: `set-option -gu status-format` with NO
  index clears the ENTIRE array — that is restore's job, NOT T3's.)

### FINDING 3 — renderer install MUST use DOUBLE quotes (path expansion at set-time).

`tmux set-option -g "status-format[$IDX]" "#($CURRENT_DIR/renderer.sh)"`:

```
DOUBLE-quoted -> stored == "#(/abs/path/to/scripts/renderer.sh)"   ✓ (#() runs it)
SINGLE-quoted -> stored == "#($CURRENT_DIR/renderer.sh)"           ✗ (literal, never runs)
```

`$CURRENT_DIR` is bash-expanded at `set-option` time (it is already computed at the
top of `scripts/livepicker.sh` as the `scripts/` dir, so the renderer lives at
`$CURRENT_DIR/renderer.sh`). The stored value becomes a literal absolute path that
tmux's `#()` executes on every status redraw. **Single quotes silently break the
picker** (line renders blank / error). The `#()` execution itself is already proven
end-to-end by P1.M2.T1.S1 (renderer COMPLETE); T3 only stores the correct literal.

### FINDING 4 — the shift source is `ORIG_STATUS_FORMAT_INDICES` (the ≥3 list; EMPTY here → no-op).

T1's save (`state.sh::state_status_format_save`) enumerates `show-options -g
status-format`, keeps ONLY indices `≥ 3` (genuinely user-set; tmux always
materializes built-in defaults `[0,1,2]`), and stores the digit-only space-list in
`ORIG_STATUS_FORMAT_INDICES` + each value in `ORIG_STATUS_FORMAT_PREFIX`+N.

- **In THIS env there are NO user-set indices** (tubular unsets status-format →
  only the [0,1,2] defaults materialize → none ≥3). Re-verified live.
  → The T3 shift loop is a **no-op**; `status-format[1]` stays at its default and
  (per Invariant C) composes the user's window-status line on line 2.
- T3 reads the **live** value `show-option -gqv "status-format[$n]"` for the shift
  (the literal "shift it" of PRD §10 step 2). This equals the saved per-index value
  (T1's save did not mutate status-format). Either source works; live-read is the
  literal interpretation and needs no extra state key.
- Restore (P1.M5.T3.S1) does `set-option -gu status-format` (clear ALL → re-compose
  defaults) then replays the saved values at their ORIGINAL index `[n]`. So during
  the picker's life the user's override sits at `[n+1]`; after restore it is back at
  `[n]`. Consistent.

### FINDING 5 — status-format[1] default-composite is the "fragile assumption" (manual real-env gate).

On the **isolated socket** (status-format materialized as defaults), `[1]` is the
**pane-status** composite (`P: …`), NOT the window-status composite. **Invariant C**
(system_context §3, marked VERIFIED on the REAL tubular server) states that when
tubular has UNSET status-format (`-gu`) and `status=2` with `[0]=#(renderer)` and
`[1]` unset, line 2 renders the **window-status** composite (status-left +
window-status-format + status-right) — i.e. the user's normal status line.

- The discrepancy is the **materialized-default vs unset** distinction: the isolated
  socket shows materialized defaults; tubular's unset array re-composes at runtime.
  The item contract and PRD §10 both TRUST Invariant C for the default env.
- **T3 must NOT touch status-left / status-right / window-status-format** — tubular
  owns them and they must persist so line 2 renders (item contract point 3;
  system_context §10). Verified: T3 touches ONLY `status-format[IDX]` + shifted
  `[n]`/`[n+1]` + the `status` count.
- **Manual gate (Level 4):** on the real tubular env, visually confirm line 2 shows
  the window list. If it shows the pane composite or is blank, apply the documented
  fallback (tmux_primitives §3): explicitly set `status-format[1]` to a composite of
  the user's status pieces. The deterministic shift/install/count are fully covered
  by the socket-shim mock; ONLY this visual line-2 behavior needs the real env.

## Summary table — T3 sub-step → primitive → tmux effect

| Sub-step (PRD §10) | Primitive | tmux effect | Reads (state) |
|---|---|---|---|
| (a) shift user indices highest-first | `show-option -gqv "status-format[$n]"` + `set-option -g "status-format[$((n+1))]"` + `set-option -gu "status-format[$n]"` | user override `n→n+1`; no-op when empty | `ORIG_STATUS_FORMAT_INDICES` |
| (b) install renderer | `set-option -g "status-format[$IDX]" "#($CURRENT_DIR/renderer.sh)"` (DOUBLE quotes) | line `IDX` = picker | `opt_status_format_index` (default `0`) |
| (c) grow line count | `set-option -g status <normalized>` (`on`→`2`, `off`→`on`, `2..4`→`n+1`, `5`→`5`) | status bar +1 line | `ORIG_STATUS` |

## Gaps

None material for the deterministic surface. Every primitive is verified live; the
only non-deterministic item (line-2 visual composite) is the documented manual gate
with a known fallback. The one true showstopper (`status` arithmetic under `set -u`)
is fully resolved by the `case`-based normalization in FINDING 1.
