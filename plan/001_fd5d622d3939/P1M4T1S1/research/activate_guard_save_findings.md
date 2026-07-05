# Research — P1.M4.T1.S1: livepicker.sh activate (guard + full state save)

> Empirical ground-truth for the activate orchestrator's first two PRD §6 steps
> (double-activation guard + save original state). All facts below were verified
> LIVE on the target machine (`tmux 3.6b`) on 2026-07-05, against the live server
> via read-only `show-*`/`display-message -p` commands (zero mutation). These
> findings are the load-bearing facts the PRP encodes; the implementer need not
> re-derive them.

## Methodology

- `tmux -V`, `show-options -gv {key-table,status,renumber-windows}`,
  `show-hooks -g session-window-changed`, `show-options -g status-format`,
  `show-options -g 'status-format[0]'` (exit-code probe), `show-options -g '@livepicker-nope'`
  (exit-code probe), `display-message -p '#{session_name}|#{window_id}|#{window_layout}'`,
  and a bracket-name set probe (`set-option -g '@livepicker-orig-status-format[0]'`).
- Cross-checked against `scripts/utils.sh`, `scripts/state.sh` (the INPUT contract),
  `system_context.md §2/§4`, and the parallel PRP `P1M3T1S2/PRP.md`.
- No web access was needed (tmux man-page behavior, all local).

## Findings

### FINDING 1 — Live env values (the save target) re-verified, all defaults

| Option | Live value | Save path |
|---|---|---|
| `key-table` | `root` | `tmux_save_opt key-table key-table` → `@livepicker-orig-key-table` |
| `status` | `on` | `tmux_save_opt status status` → `@livepicker-orig-status` |
| `renumber-windows` | `on` | `tmux_save_opt renumber-windows renumber-windows` → `@livepicker-orig-renumber-windows` |

These three are ordinary built-in options → `tmux_save_opt <name> <name>` (orig_name ==
src_name) is the documented idiom (utils.sh `tmux_save_opt`). `show-option -gqv` reads the
EFFECTIVE value. No special handling. **CONFIRMED identical to system_context §2.**

### FINDING 2 — `show-hooks -g session-window-changed` output format (CRITICAL for save)

Live raw output (single line; one index; `-b` flag; ABSOLUTE path):
```
session-window-changed[0] run-shell -b /home/dustin/.config/tmux/scripts/sync-window-focus.sh
```
- `show-hooks -g <hook>` exits **0** whether the hook is set OR cleared (the "cleared" form
  prints just the bare hook name with no `[N]` and no cmd). So **decide "is it set?" by
  grepping for `[`** (utils.sh `tmux_get_hook` comment + system_context §4 TRAP 2).
  Save does NOT need to decide this — it stores the FULL raw output verbatim and lets
  restore (P1.M5.T3.S1) parse it.
- `utils.sh::tmux_get_hook session-window-changed` returns EXACTLY this string. The save
  is: `tmux set-option -g "$ORIG_HOOK" "$(tmux_get_hook session-window-changed)"`.
- **Multi-line is OK in a tmux @-option**: if there were multiple indices, the output would
  be multi-line and tmux preserves the newlines through `set-option`/`show-option -gqv`.
  In THIS env there is exactly one index `[0]`, so the stored value is single-line.
  (Restore will strip the `session-window-changed[N] ` prefix and re-`set-hook` each line,
  preserving `-b` — P1.M5.T3.S1's job, NOT this task's.)

### FINDING 3 — `status-format` materialization: indices [0,1,2] are DEFAULTS, none ≥3 user-set

`show-options -g status-format` materializes exactly three indices in this env:
- `status-format[0]` — the long built-in window-status composite (status-left + W:… + status-right).
- `status-format[1]` — built-in pane-status composite.
- `status-format[2]` — built-in session-status composite.

All three are **tmux built-in defaults** (tubular UNSET status-format with `-gu`, so they
appear as defaults — system_context §2/§4 TRAP 1). **No index ≥ 3 is user-set.**

**Consequence for save:** `state.sh::state_status_format_save` enumerates the bulk dump,
keeps only indices ≥ 3, and stores the user-set list + per-index values. In THIS env that
list is **EMPTY** → `@livepicker-orig-status-format-indices` stores "" and NO per-index
keys are written. Restore (P1.M5.T3.S1) then does JUST `tmux_unset_opt status-format`
(the `-gu` reset → tmux re-composes defaults) and replays nothing. This is exactly TRAP 1:
**restore is `-gu`, NOT literal replay of the captured default strings.**

The work-item contract's "probe indices 0..9 with utils is_set; store GENUINELY-user-set
indices" is satisfied by `state_status_format_save`'s ≥3 heuristic (it does NOT use the
useless `tmux_is_set` probe — FINDING 4 — it uses the bulk-dump enumeration). **This task
just CALLS `state_status_format_save`; it does NOT re-implement the probe.**

### FINDING 4 — `tmux_is_set` exit-code probe is USELESS for status-format[n], works for @-options

| Probe | rc | Meaning |
|---|---|---|
| `show-options -g 'status-format[0]' >/dev/null 2>&1` | **0** | USELESS — set/default/never-existed all return 0 |
| `show-options -g '@livepicker-nope' >/dev/null 2>&1` | **1** | WORKS — @-user-options have no built-in default |

This is utils.sh `tmux_is_set`'s documented LIMITATION, now re-verified live. **Do NOT use
`tmux_is_set` to decide status-format save/restore.** `state_status_format_save` already
avoids it (bulk-dump enumeration). The only legitimate `tmux_is_set` use in this codebase
is for @-user-options — NOT needed by this task.

### FINDING 5 — `display-message -p` formats resolve (WITH a client); the three save captures

`tmux display-message -p '#{FORMAT}'` against the live server returned:
| Format | Live value | Saves into |
|---|---|---|
| `#{session_name}` | `tmux` | `@livepicker-orig-session` |
| `#{window_id}` | `@40` | `@livepicker-orig-window` (ID, NOT index) |
| `#{window_layout}` | `73bc,319x77,0,0{126x77,…,192x77,…}` | `@livepicker-orig-layout` |

- **`window_id` is an `@N` token, NOT a numeric index.** `renumber-windows on` makes indices
  unstable (system_context §2, tmux_primitives FINDING 1). Save MUST capture `#{window_id}`
  (the stable handle) so restore (P1.M5.T1.S1) can `select-window -t "$ORIG_WINDOW"` safely.
  Capturing `#{window_index}` instead would be a latent restore bug.
- **`display-message -p` needs a client** (it targets the "current client"). On the live
  server a client was attached, so it resolved. The socket-shim MOCK must attach a pty
  client (P1.M3.T1.S2 Level 3 did this via `script -qec "tmux … attach"`) for deterministic
  capture, OR assert saved==re-read-consistency under a single stable client.
- These three are NOT option reads (no `show-option` source) → use
  `tmux set-option -g "$ORIG_X" "$(tmux display-message -p '…')"`, NOT `tmux_save_opt`.
  (`tmux_save_opt` reads via `show-option -gqv`; it cannot capture display-message formats.)

### FINDING 6 — Bracket gotcha in @-option names re-confirmed (why status-format uses a prefix)

```
$ tmux set-option -g '@livepicker-orig-status-format[0]' 'x'
not an array: @livepicker-orig-status-format[0]      # rc=1
$ tmux set-option -g '@livepicker-orig-status-format-0' 'x'   # rc=0  (bracket-free OK)
```
tmux rejects `[`/`]` in @-user-option names ("not an array"). That is why
`state.sh::ORIG_STATUS_FORMAT_PREFIX="@livepicker-orig-status-format-"` (bracket-free, `+N`
suffix) and `tmux_save_opt`'s docstring mandates bracket-free `orig_name`. **This task does
not introduce any new bracketed @-name** — it only writes the well-defined `ORIG_*` constants
from state.sh, all of which are bracket-free. No gotcha here; just don't invent one.

### FINDING 7 — Guard semantics: `@livepicker-mode == on` → silent `exit 0`, BEFORE any mutation

PRD §6 Activation step 1: "If already active (`@livepicker-mode on`), ignore." The guard is
the **first** statement of activate, before the save block. Verified mechanics:
- `get_state "$STATE_MODE" "off"` reads `@livepicker-mode`; absent → "off" (the default).
- On the live server `@livepicker-mode` is currently UNSET → guard reads "off" → proceeds.
- **Idempotency proof strategy (mock):** pre-set `@livepicker-mode on`, pre-set sentinel
  values on the `@livepicker-orig-*` keys, run livepicker.sh, then assert (a) exit 0, (b) the
  sentinel `@livepicker-orig-*` values are UNCHANGED (the save block never ran), (c)
  `@livepicker-linked-id` unchanged. This proves the guard short-circuits before any mutation.
- **`@livepicker-mode` is NOT set on by this task** (the contract: "set last, in
  P1.M4.T5.S1"). So after S1, running livepicker.sh performs guard → save → init linked-id →
  exit, but the picker does not actually appear (no status growth / key-table switch / mode-on
  — those are T2–T5). The save is independently testable.

### FINDING 8 — File-structure conventions (mirror the established entry-point + function+driver pattern)

- **livepicker.sh is an ENTRY POINT** (executed via `run-shell` from the prefix binding that
  `plugin.tmux` installed). Like `plugin.tmux` it: has shebang `#!/usr/bin/env bash`; computes
  `CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"`; sources the lib trio
  `options.sh → utils.sh → state.sh` (load-bearing order — state.sh needs utils.sh first);
  and performs tmux side effects at top level (unlike the pure libs). `set -u`, **NO `set -e`**
  (display-message/show-hooks legitimately return non-zero under edge cases; system_context §9).
- **Function + trailing driver** mirrors `scripts/preview.sh` (P1.M3.T1.S1):
  ```bash
  activate_main() {
      …steps…
      return 0
  }
  activate_main "$@" || exit 1
  exit 0
  ```
  The guard lives as the FIRST statement of `activate_main` (`return 0` to short-circuit; the
  driver's `exit 0` produces the silent exit). The save block follows. **T2–T5 are inserted
  between the save block and the trailing `return 0`** via clearly-marked seam comments
  (exactly how preview.sh S1 left `# --- S2: insert … ---` markers). This keeps each later
  subtask a clean edit-in-place, not a rewrite.
- **`@livepicker-linked-id` initialization:** the contract says "Initialize
  `@livepicker-linked-id=''` (no preview linked yet)." Use `set_state "$STATE_LINKED_ID" ""`
  (state.sh accessor; delegates to `tmux_set_opt` = `set-option -g`). preview.sh (P1.M3)
  reads this via `get_state "$STATE_LINKED_ID" ""`; initializing to "" here means the first
  preview sees empty (no prior link to unlink) — required by preview.sh's FINDING-4/5
  duplicate guard.

## Summary table (save block → which primitive → which ORIG_* constant)

| Saved item | Capture primitive | ORIG_* constant (state.sh) |
|---|---|---|
| session name | `tmux display-message -p '#{session_name}'` | `ORIG_SESSION` |
| window **id** | `tmux display-message -p '#{window_id}'` | `ORIG_WINDOW` |
| window layout | `tmux display-message -p '#{window_layout}'` | `ORIG_LAYOUT` |
| key-table | `tmux_save_opt key-table key-table` | `ORIG_KEY_TABLE` |
| status | `tmux_save_opt status status` | `ORIG_STATUS` |
| renumber-windows | `tmux_save_opt renumber-windows renumber-windows` | `ORIG_RENUMBER` |
| hook (full, multi-line) | `tmux set-option -g "$ORIG_HOOK" "$(tmux_get_hook session-window-changed)"` | `ORIG_HOOK` |
| status-format array | `state_status_format_save` (trap-aware; ≥3 heuristic) | `ORIG_STATUS_FORMAT_INDICES` + `ORIG_STATUS_FORMAT_PREFIX`+N |
| linked-id init | `set_state "$STATE_LINKED_ID" ""` | `STATE_LINKED_ID` |

## Gaps

None material. Every save target has a verified capture primitive already provided by
utils.sh / state.sh. The only empirical caveat (display-message needs a client) is handled
in the mock by attaching a pty client (P1.M3.T1.S2 Level 3 pattern). The status-format
"none user-set in this env" fact is confirmed live and matches state.sh's design assumption.
