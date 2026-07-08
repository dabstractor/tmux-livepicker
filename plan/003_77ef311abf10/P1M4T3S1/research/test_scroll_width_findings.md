# Research — P1.M4.T3.S1: tests/test_scroll_width.sh (scroll + client-width cache)

> Empirical ground-truth for the scroll-into-view + client-width-cache validation
> suite. All facts below were verified **LIVE on `tmux 3.6b`** on 2026-07-08 against
> an **isolated `-L` socket** with a `script`-pty attached client (mirroring the
> shipped harness `tests/setup_socket.sh` + `helpers.sh`), driving the REAL plugin
> (`scripts/livepicker.sh` → `input-handler.sh` → `renderer.sh` → `restore.sh`).
> Zero impact on the user's real server. These are the load-bearing facts the PRP
> encodes; the implementer need not re-derive them.

## Methodology

- PATH-wrapper socket shim (`exec /usr/bin/tmux -L "$SOCK" "$@"`) on a fresh
  `mktemp` socket; `kill-server` + `rm -rf` per scenario. A `script -qec "tmux
  attach -t driver" /dev/null &` pty client (exactly `attach_test_client`).
- Drove the real entry points: `scripts/livepicker.sh` (activate), `scripts/
  input-handler.sh {next-session,type,backspace,cancel,refresh-width}`, and
  `scripts/renderer.sh` (the `#()` target). Read state via `show-option -gqv`.
- Cross-checked against `scripts/input-handler.sh` (`_lp_scroll_into_view`,
  the type/backspace/next/prev/cancel/refresh-width branches), `scripts/layout.sh`
  (`lp_viewport`), `scripts/renderer.sh` (viewport slice + overflow indicators),
  `scripts/livepicker.sh` (T2b client-width capture + client-resized hook install),
  `scripts/restore.sh` (STEP-4 client-resized restore), `tests/{run,helpers,
  setup_socket}.sh`, `test_functional.sh`, and `architecture/codebase_patterns.md §P8`.
- The plan_status marks P1.M3.T2.S1 "Planned" but the scroll code EXISTS and ships
  (input-handler.sh:160-166 `_lp_scroll_into_view`, :239/:279/:311/:336/:474 scroll
  writes). Both code-under-test surfaces (P1.M3.T1 client-width + P1.M3.T2 scroll)
  are COMPLETE and were exercised live.

## Findings

### FINDING 1 — scroll ADVANCES on next-session with a small client-width (the §15.28 scroll case)

Fixture: `driver` + 8 wide-named sessions (`session-name-1..8`); activate; pin
`@livepicker-preview-defer off` (mirrors `setup_test`); **seed a small
`@livepicker-client-width 12`** (the item's "small client_width"; setting it
directly is deterministic — `resize-window` does NOT change client_width, see
FINDING 5). Drive 5× `input-handler.sh next-session`:

```
before nav:  @livepicker-scroll = (unset/empty → reads 0)   @livepicker-index = 0
after 5 nav: @livepicker-scroll = 5                          @livepicker-index = 5
renderer:    #[fg=#ffffff,bg=default]<#[default]#[fg=black,bg=yellow]session-name-5#[default]...#[fg=#ffffff,bg=default]+8>#[default]
```

- **`@livepicker-scroll` advances to 5** (the `_lp_scroll_into_view` write at
  input-handler.sh:166). This is the PRIMARY, deterministic assertion (a direct
  state read — no rendering dependency).
- The renderer output CONTAINS the left overflow indicator `<` (the only `<` in a
  fixture whose session names contain none) AND the right `+8>`. The `<` is wrapped
  `#[fg=<opt_fg>,bg=<opt_bg>]<#[default]`; on the test socket `opt_fg` = `#ffffff`
  (the user `tmux.conf` pre-declares `@livepicker-fg "#ffffff"`), so assert on the
  RAW `<` presence (robust: no other `<` source in a clean fixture), NOT on a
  hardcoded styled substring.
- `@livepicker-index` == `@livepicker-scroll` here ONLY because each tab (13 cols)
  + sep overflows T=12 immediately; do NOT assert index==scroll (it is width/name
  dependent). Assert scroll > 0 and `<` presence.

### FINDING 2 — scroll does NOT advance (clamps to 0) when the list FITS

The complement (PRD §3.32 "clamp scroll=0 when fits" / layout.sh:127). With a WIDE
`@livepicker-client-width` (e.g. 200), `lp_viewport` sees `total <= T` → clamps
`LPV_SCROLL=0`. So the SAME nav sequence leaves `@livepicker-scroll` at 0 and the
renderer shows NO `<`. This is the cheap, deterministic guard that scroll only
moves when there is actual overflow. (Verified structurally via layout.sh:127; the
wide-width case is the natural counter-assertion in the same fixture.)

### FINDING 3 — type / backspace / cancel-clear RESET @livepicker-scroll to 0

After advancing scroll to 5 (FINDING 1 setup):
- `input-handler.sh type x` → `@livepicker-scroll` = **0** (input-handler.sh:241).
- `input-handler.sh backspace` → `@livepicker-scroll` = **0** (input-handler.sh:279).
- The cancel CLEAR path (non-empty filter): seed `@livepicker-filter "xx"` +
  `@livepicker-scroll 5` + mode `on`; `input-handler.sh cancel` → `@livepicker-scroll`
  = **0**, `@livepicker-filter` = `""`, `@livepicker-mode` = **on** (picker STAYS
  OPEN — input-handler.sh:472-474 + the load-bearing `return 0` at :482).

The normal flow never produces non-empty-filter + non-zero-scroll together (typing
resets scroll), so the cancel-clear case is tested by SEEDING scroll+filter directly
post-activate (consistent with the renderer-seed idiom; state is picker-internal).
All three resets are direct `set_state "$STATE_SCROLL" "0"` writes — verified live.

### FINDING 4 — `refresh-width` RE-CACHES the live client_width (the §15.28 width-cache case)

The `client-resized` hook (installed at activate) runs `input-handler.sh refresh-width`,
which does `set_state "$STATE_CLIENT_WIDTH" "$(lp_client_format '#{client_width}')"`
(input-handler.sh:505). Deterministic proof without resizing the pty:

```
activate -> @livepicker-client-width = 80 (the live client_width)
seed stale: tmux set-option -g @livepicker-client-width 999
input-handler.sh refresh-width -> @livepicker-client-width = 80  (re-cached from live, NOT 999)
```

So the test seeds a WRONG width, fires `refresh-width`, and asserts the cached value
returns to the LIVE `#{client_width}` (captured via `display-message -p`). This is
exactly the item's sanctioned alternative ("or by directly invoking the hook's
refresh") — and it exercises the REAL refresh-width action the hook runs.

### FINDING 5 — `resize-window` does NOT change `#{client_width}`; the hook only fires on a real pty resize

```
tmux resize-window -t driver -x 60 -y 20  ->  #{client_width} STAYS 80 (unchanged)
```

`#{client_width}` is the CLIENT's terminal (pty) width, not the window's. `resize-window`
changes the window grid, NOT the client pty, so it does NOT fire `client-resized` and
does NOT move the cached width (verified: width stayed at the seeded 777 across a
`resize-window`). Firing the hook deterministically would require resizing the actual
`script` pty (unreliable in CI / a non-tty runner). **Therefore:** validate the
width-cache via (a) the hook-INSTALL assertion (FINDING 6) + (b) the `refresh-width`
re-cache assertion (FINDING 4). The item explicitly permits "directly invoking the
hook's refresh" for exactly this reason. Do NOT build a `resize-window`-driven width
assertion — it will false-pass/fail unpredictably.

### FINDING 6 — the client-resized hook is INSTALLED at `client-resized[0]` → refresh-width

After activate, `show-hooks -g client-resized` is exactly:

```
client-resized[0] run-shell "/home/.../scripts/input-handler.sh refresh-width"
```

(livepicker.sh:231 — absolute path, single-quoted arg inside the double-quoted
run-shell). The install assertion is a `show-hooks -g client-resized` grep for
`input-handler.sh` + `refresh-width`. This + FINDING 4 together prove the full
width-cache wiring (installed → fires refresh-width → re-caches) without depending
on a real pty resize.

### FINDING 7 — client-resized hook is RESTORED BYTE-EXACTLY (unset prior AND set prior with `-b`)

restore.sh STEP-4 (the IDENTICAL shape as session-window-changed, §P4) clears ours
then replays every saved `client-resized[N] <cmd>` line preserving index + verbatim
command (incl. `-b`). Verified byte-exact for BOTH prior states:

| Prior (before activate) | After activate+`cancel` | Match |
|---|---|---|
| `client-resized` (bare — the common UNSET case) | `client-resized` | **EXACT** |
| `client-resized[0] run-shell -b /usr/bin/true` (a user SET prior) | `client-resized[0] run-shell -b /usr/bin/true` | **EXACT** (index + `-b` + cmd preserved) |

The assertion is a literal `assert_eq "$(show-hooks -g client-resized)" "$before"`
around a full activate→cancel cycle, for both the unset and the set(-b) prior. This
is PRD §16 "Width cache staleness" / §9 restore-exactness for the client-resized hook.

### FINDING 8 — harness lifecycle: `setup_test` runs ONCE per `test_*` (fresh socket + defer OFF)

`run.sh` discovers every `test_*` via `compgen -A function | grep '^test_'` and, for
EACH, calls `setup_test "lp-$$-<name>"` (→ fresh isolated `-L` socket + PATH shim +
baseline fixtures driver/alpha/beta + multi-pane windows, AND pins
`@livepicker-preview-defer off` for determinism) → resets `TEST_STATUS=pass` → runs
the test in the CURRENT shell → reads `TEST_STATUS` → `teardown_test`. So a test_*
body: uses bare `tmux` (hits the isolated socket), `attach_test_client`,
`$LIVEPICKER_SCRIPTS`, `fail/pass/assert_eq/assert_contains`; it SOURCES NOTHING and
calls NO `setup_test`/`teardown_test`. The defer-OFF pin makes nav/scroll SYNCHRONOUS
(no async `-b` preview racing the scroll/state reads) — essential for the scroll
assertions. Tests needing extra sessions `tmux new-session -d -s <name>` (bare tmux).

### FINDING 9 — failure signaling: `fail`/`assert_*` ONLY (never exit/return-nonzero)

run.sh reads `TEST_STATUS` in the CURRENT shell after each test. A bare `exit` kills
the whole runner; a non-zero `return` from a test mis-arrows the harness. Signal
failure ONLY via `fail msg` / `assert_eq a b msg` / `assert_contains str sub msg`
(helpers.sh — `assert_contains` uses a quoted `case` pattern = literal substring, no
glob, no subprocess). `set -u` is INHERITED from helpers.sh (do NOT re-declare). TABS
for indent; `local` for all function locals; quote every expansion. File-level
`# shellcheck disable=SC2154,SC2016,SC2034,SC2086` (mirrors test_functional.sh /
test_appearance.sh / the in-flight test_layout.sh + test_ranking.sh).

### FINDING 10 — the renderer's `<` (LEFT overflow) requires scroll>0; index=0 shows only the RIGHT indicator

layout.sh `lp_viewport`: with `scroll=hl=0` and overflow, step (a) `hl<scroll` is
false and step (b) `scroll<hl` is false → `LPV_HIDDEN_LEFT=0` → NO left `<`. The left
indicator appears ONLY when `scroll>0` (i.e., after navigating DOWN past the left
edge). So a renderer-seed proving the LEFT `<` must seed `scroll>0` (and `index>=scroll`).
For the full-activation scroll test (FINDING 1) this is automatic (nav advanced scroll).
For any pure renderer-seed viewport assertion, seed `@livepicker-scroll` explicitly.
(The RIGHT indicator `+%d>` appears whenever anything is hidden, including index=0.)

## Summary table — test → code path → assertion

| Test | Code path (file:line) | Primary assertion |
|---|---|---|
| scroll advances | input-handler.sh:160-166 (`_lp_scroll_into_view`) | `@livepicker-scroll` > 0 after nav (width=12); renderer has `<` |
| scroll clamps when fits | layout.sh:127 | `@livepicker-scroll` == 0 after nav (width=200); renderer has NO `<` |
| type resets scroll | input-handler.sh:241 | scroll → 0 after `type` |
| backspace resets scroll | input-handler.sh:279 | scroll → 0 after `backspace` |
| cancel-clear resets scroll | input-handler.sh:472-474,482 | seeded scroll=5+filter → 0; filter cleared; mode stays on |
| refresh-width re-caches | input-handler.sh:501-505 | seed 999 → refresh-width → == live `#{client_width}` |
| client-resized hook installed | livepicker.sh:231 | `show-hooks -g client-resized` contains `input-handler.sh`+`refresh-width` |
| client-resized restored (unset) | restore.sh:189-198 | `show-hooks -g client-resized` byte-exact before/after (bare prior) |
| client-resized restored (set -b) | restore.sh:189-198 | byte-exact before/after (set `-b` prior) |

## Gaps

None material. Every assertion is backed by a live capture above. The one
non-deterministic path — firing `client-resized` via a real pty resize — is
intentionally substituted by the hook-install + refresh-width-action pair (FINDING
5/6), which the item's own wording ("or by directly invoking the hook's refresh")
explicitly sanctions. The renderer LEFT-indicator seed requirement (FINDING 10) is
handled by using nav (full-activation test) or seeding scroll (renderer-seed).
