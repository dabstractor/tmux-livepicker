# Empirical tmux option/hook probe findings (utils.sh grounding)

> All facts below were verified LIVE on 2026-07-05 against the user's running
> tmux server (`tmux 3.6b`, `bash 5.3.15`, `shellcheck 0.11.0`). These are the
> ground-truth behaviors `scripts/utils.sh` must encode. Two findings CORRECT
> claims made in the work-item contract / `system_context.md §4`.

## Environment

| Tool | Version |
|---|---|
| tmux | **3.6b** (`tmux -V`) |
| bash | **5.3.15(1)-release** |
| shellcheck | **0.11.0** |

---

## FINDING 1 — `tmux_is_set` exit-code probe: reliable for `@`-options ONLY

The tubular idiom `tmux show-options -g "$1" >/dev/null 2>&1` (return code =
tmux exit code) distinguishes set-vs-unset **only for options with no built-in
default** — i.e. `@`-prefixed user options.

Verified (clean re-test):

| Option | State | `show-options -g` rc |
|---|---|---|
| `@livepicker-key` | SET (`Space` in tmux.conf:120) | **0** |
| `@livepicker-fg` | SET (`#ffffff` in tmux.conf:121) | **0** |
| `@tubular_bg`, `@session-history-current` | SET | **0** |
| `@livepicker-type` | unset | **1** |
| `@livepicker-nonexistent-xyz` | unset | **1** |

**→ For `@`-options the probe is sound.** This is the primary use case
(`@livepicker-mode` double-activation guard, `@livepicker-linked-id`, all
`@livepicker-orig-*` saved-state keys).

---

## FINDING 2 — ⚠️ CONTRACT CORRECTION: array-index exit code does NOT distinguish set-vs-default

The contract states: *"for array indices, `tmux show-options -g "status-format[$n]"`
exit code distinguishes set-vs-default in tmux 3.x"*. **This is FALSE on 3.6b.**

| Query | Reality | rc |
|---|---|---|
| `show-options -g "status-format[0]"` | tubular `-gu`'d it → it is a DEFAULT | **0** |
| `show-options -g "status-format[5]"` | NEVER set, NO default | **0** |
| `show-options -g "status-format[5]"` after `set-option -g status-format[5] TEST` | user-SET | **0** |

The exit code is **always 0** for `status-format[n]`, whether the index is
user-set, default, or never-existed. There is no exit-code signal.

**The only reliable distinguisher** is presence of the index in the BULK
`show-options -g` dump — and even THAT is imperfect for low indices because tmux
always materializes the built-in default formats:

| Index | In bulk `show-options -g`? | Why |
|---|---|---|
| `status-format[0]` | **yes** (always) | tmux always emits the 3 built-in default formats `[0]`,`[1]`,`[2]` |
| `status-format[4]` after `set-option -g status-format[4] X` | **yes** | user-set |
| `status-format[4]` after `set-option -gu status-format[4]` | **no** (gone) | cleared |
| `status-format[7]` (never touched) | **no** | no default, never set |

**→ Downstream consequence (P1.M5.T3 restore):** do NOT build a probe-gated
status-format replay. Use the unconditional `set-option -gu status-format`
restore (TRAP 1 primary recommendation). `tmux_is_set` must document this
limitation explicitly so the restore author is not misled.

---

## FINDING 3 — `set-option -gu` behavior (whole-array vs per-index)

| Command | Effect | Verified |
|---|---|---|
| `set-option -gu status-format` | clears ALL user-set indices → tmux re-composes built-in defaults (`[0]`,`[1]`,`[2]` reappear) | ✅ |
| `set-option -gu "status-format[4]"` | clears ONLY index `[4]`; `[3]` untouched | ✅ |
| After whole-array `-gu`: `show-options -g status-format` | still rc=0 (defaults present) | ✅ |

This is the **desired restore behavior** (TRAP 1 / INVARIANT C): unsetting
returns the status line to tubular's live-composed default.

---

## FINDING 4 — ⚠️ CONTRACT CORRECTION: brackets are REJECTED in `@`-option names

`tmux set-option -g "@livepicker-orig-status-format[0]" "MARKER"` →
**`not an array: @livepicker-orig-status-format[0]`**, rc=1.

tmux interprets `[N]` in any option name as an array-index specifier. Since
`@`-user-options are scalars (not arrays), the bracketed name is rejected.

**→ `tmux_save_opt` must write to a BRACKET-FREE key.** This is why the contract
signature is `tmux_save_opt orig_name src_name` (TWO args): `orig_name` is the
sanitized destination suffix (e.g. `status-format-0`), `src_name` is the actual
option to read (e.g. `status-format[0]`, with brackets). For non-array options
the caller passes both args identical: `tmux_save_opt status status`.

---

## FINDING 5 — `show-hooks -g <hook>` output format

Live hook (the user's real one):
```
$ tmux show-hooks -g session-window-changed
session-window-changed[0] run-shell -b /home/dustin/.config/tmux/scripts/sync-window-focus.sh
```

Properties:
- **Multi-line, array-indexed.** Appending a 2nd hook (`set-hook -ag`) yields:
  ```
  session-window-changed[0] run-shell -b /tmp/x.sh
  session-window-changed[1] run-shell /tmp/y.sh
  ```
  One line per index. `tmux_get_hook` MUST capture the full multi-line blob.
- **`-b` flag preserved verbatim** in output. Restore re-runs
  `set-hook -g session-window-changed "<cmd>"` with the `-b` intact.
- **Exit code is 0 even when the hook is cleared** (after `set-hook -gu`,
  `show-hooks` prints the bare hook name `session-window-changed` with no `[N]`
  and no command). → "is the hook set?" = grep for the `[` index marker or for
  non-empty command text, NOT the exit code.
- **Strip recipe** (system_context §7): `sed "s/^${hookname}\\[[0-9]*\\] //"`
  recovers the bare command(s) for replay.

---

## FINDING 6 — `set-hook -gu <hook>` clears all indices (verified)

After appending 2 hooks then `set-hook -gu session-window-changed`:
`show-hooks` output collapses to the bare name (no indices, no commands).
`-gu` on a hook clears the **entire array**, exactly mirroring `set-option -gu`
on an array option. This is what `tmux_clear_hook` wraps.

---

## FINDING 7 — `set-option -g` (plain, no `-q`) is sibling-standard

`tmux set-option -g "@livepicker-orig-test" "v"` → rc=0. No `-q` needed.
resurrect/session-history/sessionx all use plain `set-option -g`. `tmux_set_opt`
and `tmux_save_opt` use plain `-g`.

---

## FINDING 8 — Relationship to `options.sh` (P1.M1.T1)

`options.sh` exposes `get_opt(name, default)` + 18 `opt_*` accessors for the
`@livepicker-*` CONFIG namespace (user-tunable knobs with PRD defaults).

`utils.sh` exposes `tmux_get_opt`/`tmux_set_opt`/`tmux_unset_opt`/`tmux_save_opt`/
`tmux_is_set`/`tmux_get_hook`/`tmux_clear_hook` for ANY tmux option/hook (the
save/restore machinery: `status`, `key-table`, `renumber-windows`,
`status-format[n]`, `session-window-changed`, etc.).

- **No name collision:** `get_opt`/`opt_*` vs `tmux_*` prefixes are disjoint.
- **Both are sourced by the same scripts** (livepicker.sh, restore.sh source
  both). `utils.sh` does NOT source `options.sh` — it is self-contained.
- `tmux_get_opt` is functionally identical to `options.sh::get_opt` but lives in
  a separate namespace so both can coexist when sourced together.

---

## FINDING 9 — House style (mirror options.sh / resurrect helpers.sh / system_context §9)

- Shebang `#!/usr/bin/env bash`; `set -u` ONLY (no `-e`, no `-o pipefail` —
  `show-option`/`show-hooks` legitimately return non-zero).
- **Sourced library:** functions only; NO top-level side effects; NO `tmux`
  calls at source time; NO `SCRIPT_DIR`/`CURRENT_DIR` computation. Mirror
  `tmux-resurrect/scripts/helpers.sh`.
- Tabs for indent; `local` declared FIRST, assign on a separate line (avoids
  shellcheck SC2155); double-quote every expansion.
