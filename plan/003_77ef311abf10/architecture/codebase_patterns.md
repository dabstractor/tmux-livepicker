# Codebase Patterns: established conventions for delta 003

> The shipped code follows strict, battle-tested patterns. New delta work MUST
> match them exactly so the 44-green suite stays green and the invariants hold.
> Each pattern below has a confirmed example in the existing source.

## P1 — Sourced library contract (NO source-time side effects)

Every `scripts/*.sh` that is `source`d (options/utils/state/filter, and the new
rank/layout) MUST define functions and constants ONLY. Sourcing it touches no tmux
state and prints nothing. The only files that have a `*_main "$@" || exit 1` driver
are EXECUTABLE entry points invoked via `run-shell`/`#()`:
`livepicker.sh`, `input-handler.sh`, `preview.sh`, `renderer.sh`, `restore.sh`,
and the new `session-mgmt.sh`.

- Header: `#!/usr/bin/env bash`, `set -u` (NOT `-e`, NOT `-o pipefail`).
- `# shellcheck disable=SC1091` (sources sibling libs via `$CURRENT_DIR`).
- Resolve dir: `CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"`.
- Source order is load-bearing: **options.sh → utils.sh → state.sh → (filter|
  rank|layout).sh** (state.sh needs utils.sh's helpers first).
- `rank.sh` and `layout.sh` are NEW sourced libs: define `lp_rank` / `lp_viewport`
  + measurement helpers, no driver. `# shellcheck source=` directives in consumers
  must switch from `filter.sh` to `rank.sh`.

## P2 — Option accessors (options.sh)

One `opt_<name>()` per option, one-liner:
```bash
opt_query_gap()  { get_opt "@livepicker-query-gap" "2"; }
```
- Defaults are PRD §11 verbatim.
- Space-list accessors (`opt_nav_next_keys`) are word-split by callers
  (`# shellcheck disable=SC2086`).
- **REMOVE `opt_show_count()`** (§19 drops the count). Add: `opt_nerd_fonts`,
  `opt_search_icon`, `opt_query_gap`, `opt_overflow_left`, `opt_overflow_right_format`
  (P1); `opt_rename_key`, `opt_delete_key`, `opt_confirm_delete` (P2);
  `opt_preview_fit` (P3).

## P3 — State contract (state.sh)

Runtime keys: `readonly STATE_X="@livepicker-x"`, then appended to
`_STATE_RUNTIME_KEYS` (MANDATORY clear-list). Saved-state keys: `readonly
ORIG_X="@livepicker-orig-x"`.

- **Add (P1):** `STATE_SCROLL` (`@livepicker-scroll`),
  `STATE_CLIENT_WIDTH` (`@livepicker-client-width`), `ORIG_CLIENT_RESIZED_HOOK`
  (`@livepicker-orig-client-resized`).
- **Add (P3):** `ORIG_WINDOW_SIZE` (`@livepicker-orig-window-size`).
- `clear_all_state` clears the runtime list + greps `@livepicker-orig-`. It MUST
  NOT unset §11 config (CORRECTION A). New keys in `_STATE_RUNTIME_KEYS` get torn
  down automatically; new `ORIG_*` keys get caught by the `@livepicker-orig-` grep.
- Read/write via `get_state "$STATE_X" "${default}"` / `set_state "$STATE_X" "$v"`.

## P4 — Hook save/restore (the only correct way)

`session-window-changed` and the new `client-resized` use the IDENTICAL shape:
1. Save: `tmux_get_hook <name>` returns the FULL multi-line `show-hooks -g` output
   (one `name[N] <cmd>` per index, incl. `-b`). Store verbatim in an `ORIG_*` key.
2. Clear: `tmux_clear_hook <name>` = `set-hook -gu <name>` (clears every index).
3. Restore: parse each saved `name[N] <cmd>` line, replay via
   `set-hook -g "name[$N]" "$cmd"` preserving index + `-b` + verbatim command
   (the index-less form clobbers multi-index hooks). Skip bare `name`/blank lines.

The `client-resized` hook refreshes `@livepicker-client-width` for the picker
duration; restore puts back the exact prior hook.

## P5 — The preview entry point (do NOT bypass)

All preview work routes through `input-handler.sh::_lp_preview_follow TARGET`,
which honors `@livepicker-preview-defer`:
- defer=on: `refresh-client -S` FIRST (synchronous status), then `_lp_fire_preview`
  (state writes + non-blocking `run-shell -b`).
- defer=off: synchronous `preview.sh` then refresh.

New input actions (scroll-into-view, rename/delete re-sync) update state, then call
`_lp_preview_follow` (or the no-op-if-empty guard). NEVER call `link-window` /
`select-window` inline in the input handler. `preview.sh` has the 3-guard seq
supersede (`STATE_PREVIEW_SEQ`) that makes a late `-b` job a no-op.

## P6 — Renderer rules (renderer.sh)

- Emit EXACTLY ONE line, NO trailing newline: `printf '%s' "$out"`.
- `#[default]` after every segment (resets fg AND bg; omitting leaks highlight).
- Read the list via process substitution: `mapfile -t all < <(printf '%s' "$LIST")`
  (here-string makes an empty list look like `[""]`).
- NO `set -e`; `set -u` inherited (every var defaulted). `render || fallback-red`.
- **`#()` stdout is NOT re-parsed for `#{…}`** — only `#[…]` applies. So the query
  text doubles every `#` (`${FILTER//\#/##}`); theme formats are pre-resolved
  (sentinel) and the cached `#[…]`-only templates render fine.
- The renderer must be PURE + FAST (<50ms): option reads + pure-bash rank/measure
  ONLY. **No `tmux` round-trip on the render path** (width from the cached
  `@livepicker-client-width`, separator/justify from a single read, not per-tab).

## P7 — Layout viewport (layout.sh, NEW, shared)

`lp_viewport` + the display-width measurement live ONCE in `scripts/layout.sh`,
sourced by BOTH `renderer.sh` (to slice the visible window) and `input-handler.sh`
(to scroll-into-view) so they can never disagree (§16 "Viewport measurement").
- Measure display width with `#[…]` directives stripped first (zero-width but
  inflate raw length). A bash strip: a function that removes `#[…]` runs, then
  `wc -m` / a width counter. Nerd-font icon is 1 or 2 columns — measure the glyph's
  rendered width (it is a single Unicode codepoint; treat as width 1 unless a
  wide-glyph check is needed — the default U+F002 is narrow).
- `T = client_width − query_block − active_indicators`. Recompute every redraw
  (query length changes). Clamp `scroll` to 0 when the list fits.

## P8 — Test harness (tests/)

- `setup_test [sock]` → fresh isolated `-L` socket + PATH shim + baseline
  fixtures (driver/alpha/beta + multi-pane windows). **Pins
  `@livepicker-preview-defer off` for determinism** (async `-b` would race the
  synchronous linked-id assertions). `tests/test_responsiveness.sh` flips it ON.
- `attach_test_client` (via `script` pty) for nav/preview/scroll tests.
- Renderer tests need NO client: seed `@livepicker-*` state → run
  `scripts/renderer.sh` → `assert_contains` on stdout.
- Assertion helpers: `assert_eq a b msg`, `assert_contains str sub msg`, `fail msg`
  (sets `TEST_STATUS=fail`, never exits).
- New test files mirror `test_functional.sh` (renderer-seed idiom) /
  `test_preview.sh` (lifecycle + `attach_test_client`).

## P9 — `set -u` safety + escaping

- Every `opt_*`/`get_opt` bakes a default; every `get_state` takes a default arg.
  No bare `tmux show-option` that can return empty under `set -u`.
- `command-prompt` rename uses `%%` inside a single-quoted `run-shell`; names with
  `'`/`"`/`` ` ``/`$` may break — known limitation (§21). tmux sanitizes `:`→`_`,
  leading `.`→`_`; detect a sanitized result (exact name ≠ input) and
  `display-message` rather than silently renaming under a different name.
