# state.sh grounding findings (P1.M1.T3.S1)

> Verified LIVE on 2026-07-05 against the user's running tmux server
> (`tmux 3.6b`, `bash 5.3.15`, `shellcheck 0.11.0`). These ground the design of
> `scripts/state.sh` and surface **one CONTRACT CORRECTION** (clear_all_state)
> plus the **status-format contract design** (the load-bearing trap).

## Environment

| Tool | Version |
|---|---|
| tmux | **3.6b** |
| bash | **5.3.15(1)-release** |
| shellcheck | **0.11.0** |

---

## FINDING A — ⚠️ CONTRACT CORRECTION: `clear_all_state` must NOT unset config keys

The work-item contract says: *"iterate `tmux show-options -g | grep '@livepicker-'`
and unset each (set-option -gu)"*. **This would wipe user CONFIG options**, which is
a production bug.

Live proof — `tmux show-options -g | grep '@livepicker-'` currently returns:
```
@livepicker-fg "#ffffff"      ← USER CONFIG (tmux.conf)
@livepicker-key Space         ← USER CONFIG (tmux.conf)
```

If `clear_all_state` unsets these on picker exit, the NEXT activation reads
`opt_fg → "default"` (not `#ffffff`) and `opt_key → ""` (binding guard fails)
until `tmux.conf` is re-sourced. The user's config is silently lost mid-session.

**Resolution (what state.sh implements):** `clear_all_state` clears ONLY picker-
INTERNAL keys, never the PRD §11 config set:
1. The 5 runtime keys: `@livepicker-mode`, `@livepicker-list`, `@livepicker-filter`,
   `@livepicker-index`, `@livepicker-linked-id` (explicit `set-option -gu` each).
2. Every `@livepicker-orig-*` saved-state key, found dynamically via
   `show-options -g | grep '@livepicker-orig-'` (handles the dynamic
   `@livepicker-orig-status-format-N` keys whose count is data-dependent).
3. SKIP every PRD §11 config key (the 18 user-tunable `@livepicker-*` knobs).

`@livepicker-type` is intentionally PRESERVED: it is both a config option
(PRD §11 default `session`) AND a runtime mirror; the picker only READS it, never
sets it, so it always holds the user's value and must survive teardown.

The whitelist (5 runtime keys + `@livepicker-orig-*` grep) is preferred over a
config blacklist because it is shorter, stable, and self-documenting; the only dev
cost is adding a new runtime key to the explicit list if one is introduced later.

## FINDING B — `set-option -gu` is safe on already-unset `@`-options (the guard)

```
$ tmux set-option -gu "@livepicker-mode"; echo rc=$?      # never set before
rc=0                                                        # NO error
$ tmux show-options -gv "@livepicker-mode"                 # then a read
invalid option: @livepicker-mode                            # SHOW errors (exit 1) — expected
```

- `set-option -gu <@key>` on an unset/unknown `@`-option exits **0** and prints
  nothing to stderr. → `clear_all_state`'s per-key unset is intrinsically guarded.
- `show-options -gv <@key>` on an unset `@`-option exits **1** with "invalid
  option" — so DO NOT use a bare `show-options` to read state without a default;
  use `tmux_get_opt` (which uses `show-option -gqv`, returns "" → default).
- Belt-and-braces: `clear_all_state` still redirects each unset's stderr to
  `/dev/null` so any future tmux quirk can't spam the picker.

## FINDING C — status-format materializes EXACTLY indices [0,1,2] as defaults

```
$ tmux show-options -g status-format | sed -n 's/^status-format\[\([0-9]*\)\].*/\1/p'
0 1 2
```

tmux always materializes the 3 built-in default status-format lines `[0]`,`[1]`,
`[2]` (verified: this env's tubular UNSET status-format with `-gu`, yet these 3
re-appear as re-composed defaults). Indices `>= 3` appear **only** if a user set
them. This is the empirical basis for the status-format save/restore contract.

## FINDING D — status-format index exit-code probe is USELESS (re-confirm FINDING 2)

`tmux show-options -gv "status-format[9]"` on a never-set index → empty, **rc=0**.
`show-options -g "status-format[5]"` → rc=0 always (set, default, never-existed).
→ The contract's "(via utils is_set probe)" suggestion for status-format does NOT
work. The only signal is **presence in the bulk dump** (FINDING C), and even that
cannot distinguish a user-overridden `[0]` from the default `[0]`.

**status-format contract design (the load-bearing part of this module):**

- **SAVE** (`state_status_format_save`):
  1. Enumerate materialized indices from `show-options -g status-format` (parse
     `status-format[N]`).
  2. "Genuinely user-set" = materialized index **AND N >= 3** (since [0,1,2] are
     always tmux defaults in this env). Store the user-set index list (space-
     separated) in `@livepicker-orig-status-format-indices`; store each value in
     the bracket-free key `@livepicker-orig-status-format-N` (brackets are rejected
     in `@`-names — FINDING 4 of the utils probe).
  3. If none (the common case — tubular env), store an empty index list.
- **RESTORE** (`state_status_format_restore`):
  1. `tmux_unset_opt status-format` — the **TRAP-1 `-gu` reset**: clears ALL
     indices, tmux re-composes defaults [0,1,2]. This is the load-bearing
     correctness step (never replay captured default strings).
  2. Replay each genuinely-user-set index from the saved list via
     `tmux_set_opt "status-format[N]" "$saved_value"`.

**Documented limitation:** a genuine USER override of status-format[0..2] is NOT
preserved (those indices are treated as defaults). This is acceptable because
(a) the target env has no such overrides (tubular unsets them), (b) the `-gu`
restore is provably correct when [0,1,2] are defaults, and (c) the contract
explicitly forbids storing literal default strings (TRAP 1). Indices >= 3 are
always preserved correctly.

## FINDING E — `@livepicker-type` is shared config+runtime; never cleared

Re-affirms FINDING A's handling: `@livepicker-type` is a PRD §11 config option
(default `session`) that the picker also reads at runtime as a "mirror for speed".
There is no SEPARATE runtime type key. state.sh exposes `STATE_TYPE="@livepicker-type"`
as an alias and reads it via `get_state`; `clear_all_state` MUST NOT unset it
(it would reset the user's configured picker mode to the default).

## FINDING F — state.sh depends on utils.sh (caller sources both)

state.sh consumes `tmux_get_opt` / `tmux_set_opt` / `tmux_unset_opt` / `tmux_save_opt`
from `scripts/utils.sh` (P1.M1.T2.S1). Per the established convention (utils PRP,
resurrect helpers.sh), state.sh is a **pure sourced library**: it does NOT compute
`SCRIPT_DIR`, does NOT call tmux at source time, and does NOT source utils.sh
itself. The CALLER (livepicker.sh / restore.sh / the test harness) sources
`utils.sh` THEN `state.sh` in that order. state.sh assumes the `tmux_*` helpers
are already defined. This mirrors how options.sh and utils.sh coexist (consumers
source both). state.sh does NOT depend on options.sh (it reads `@livepicker-type`
directly via `tmux_get_opt`).

## FINDING G — the saved-state key CONTRACT (the integration seam)

P1.M4.T1.S1 (activate save) and P1.M5.T3.S1 (restore) BOTH depend on the exact
key names state.sh defines. The contract (verified against PRD §9 + system_context
§2/§4 + live env):

| Key (constant) | Value | Written by | Read by |
|---|---|---|---|
| `ORIG_SESSION` | `@livepicker-orig-session` | activate | restore (cancel switch-client) |
| `ORIG_WINDOW` | `@livepicker-orig-window` | activate | restore (select-window -t) — **window ID not index** |
| `ORIG_LAYOUT` | `@livepicker-orig-layout` | activate | restore (select-layout) |
| `ORIG_KEY_TABLE` | `@livepicker-orig-key-table` | activate | restore (tmux_set_opt key-table) |
| `ORIG_STATUS` | `@livepicker-orig-status` | activate | restore (tmux_set_opt status) |
| `ORIG_RENUMBER` | `@livepicker-orig-renumber-windows` | activate | restore (tmux_set_opt) |
| `ORIG_HOOK` | `@livepicker-orig-session-window-changed` | activate | restore (replay set-hook -g, preserve -b) |
| `ORIG_STATUS_FORMAT_INDICES` | `@livepicker-orig-status-format-indices` | state_status_format_save | state_status_format_restore |
| `ORIG_STATUS_FORMAT_PREFIX` | `@livepicker-orig-status-format-` | state_status_format_save (per-N) | state_status_format_restore |

Runtime keys (mode/list/filter/index/linked-id) are also named constants so every
script uses the same literal (no typo drift).

## FINDING H — House style (unchanged from options.sh/utils.sh)

Shebang `#!/usr/bin/env bash`; `set -u` ONLY; tabs; `local` declared before assign
(SC2155-safe); double-quote all expansions; functions only; NO top-level tmux
calls; NO `SCRIPT_DIR`. Mirror `tmux-resurrect/scripts/helpers.sh`.
