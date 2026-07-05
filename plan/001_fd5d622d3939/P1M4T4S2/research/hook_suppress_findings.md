# Research — P1.M4.T4.S2: suppress `session-window-changed` hook

> Empirical ground-truth verified live on tmux 3.6b against an ISOLATED socket
> (`tmux -L lp-s2-verify-$$`). All commands below were actually run; outputs are
> copy-pasted, not assumed. These findings are the load-bearing facts the PRP
> block is built on.

## The seam (where S2 inserts)

**S1 (P1.M4.T4.S1) has LANDED.** `scripts/livepicker.sh` now contains, at the
tail of `activate_main` (re-read fresh at implementation time; line numbers
shift, the TEXT is stable):

```
		tmux set-option -g key-table livepicker          # S1's last line
	# --- T4 (P1.M4.T4.S2): suppress session-window-changed hook (insert here) ---
	# --- T5 (P1.M4.T5.S1): first preview + set @livepicker-mode on (insert here) ---
	return 0
```

**S2 replaces EXACTLY the single S2 seam-comment line** (one leading tab) with
the S2 block. S1's block (above), the T5 seam (below), `return 0`, and the
driver are UNTOUCHED. If the S2 seam comment is NOT present (S1 not yet landed),
STOP — S1 must land first; re-read the file. (As of this writing S1 IS landed.)

---

## FINDING 1 — `set-hook -gu session-window-changed` clears the `[0]` index (VERIFIED)

The user's live hook (system_context §2) is array-indexed with `-b`:
```
session-window-changed[0] run-shell -b /home/dustin/.config/tmux/scripts/sync-window-focus.sh
```

Verified sequence on an isolated socket:
```
$ tmux set-hook -g session-window-changed "run-shell -b /home/dustin/.config/tmux/scripts/sync-window-focus.sh"
$ tmux show-hooks -g session-window-changed       # BEFORE
session-window-changed[0] run-shell -b /home/dustin/.config/tmux/scripts/sync-window-focus.sh
$ tmux set-hook -gu session-window-changed        # the recipe
$ echo rc=$?                                       # rc=0
$ tmux show-hooks -g session-window-changed       # AFTER
session-window-changed
```

→ `set-hook -gu` (global, unset, NO index) clears EVERY index of the hook
array — exactly like `set-option -gu status-format` clears every status-format
index (TRAP 1). This is the system_context §7 recipe, now confirmed live.

---

## FINDING 2 — "is the hook set?" = grep for `[`, NOT the exit code (VERIFIED)

`show-hooks -g <name>` ALWAYS exits 0 — set, cleared, or never-existed all
return 0. When cleared it prints the BARE hook name (no `[N]`, no command):
```
$ tmux set-hook -gu session-window-changed
$ tmux show-hooks -g session-window-changed; echo rc=$?
session-window-changed
rc=0
```

→ The mock assertion for "hook was cleared" MUST grep for the array marker `[`:
```bash
# hook PRESENT (has an index):   show-hooks -g session-window-changed | grep -q '\['
# hook CLEARED (bare name only): ! show-hooks -g session-window-changed | grep -q '\['
```
This is exactly what `tmux_get_hook`'s doc-comment already warns
("decided by grepping for a '[' marker, not by the exit code"). Do NOT assert on
`$?` — it is always 0. (This is also why STEP 2's save does not branch on the
`tmux_get_hook` rc — it just stores the verbatim line.)

---

## FINDING 3 — `set-hook -gu` is a SAFE NO-OP on an already-cleared hook (VERIFIED)

Running `set-hook -gu` a second time (hook already cleared, or never set) still
returns rc=0 and prints nothing:
```
$ tmux set-hook -gu session-window-changed; echo rc=$?   # second clear
rc=0
```

→ NO defensive `if hook-is-set` guard is needed before clearing. Under the
house `set -u` (NO `-e`) this is unconditionally safe. The only gate is the
config flag `@livepicker-suppress-window-hook`.

---

## FINDING 4 — `set-hook -g` REPLACES `[0]`; the user's hook is a single `[0]`

Setting two hooks WITHOUT `-a` (append) does NOT accumulate — the second
REPLACES index `[0]`:
```
$ tmux set-hook -g session-window-changed "run-shell -b /a.sh"
$ tmux set-hook -g session-window-changed "run-shell /b.sh"
$ tmux show-hooks -g session-window-changed
session-window-changed[0] run-shell /b.sh     # /a.sh is GONE
```

→ Multiple indices require `-a` (append → `[1]`, `[2]`). The user's REAL hook
is a single `[0]` (system_context §2). So:
- **S2 (this task):** `set-hook -gu` clears that single `[0]` (and any others).
- **Restore (P1.M5.T3.S1):** re-run `set-hook -g session-window-changed "<cmd>"`
  with the saved command (verbatim, preserving `-b` + abs path) — that
  re-materializes `[0]`. S2 does NOT touch the saved value; restore reads it.

S2's write surface is ONLY the LIVE `session-window-changed` hook (cleared). It
does NOT read or write `@livepicker-orig-session-window-changed` (ORIG_HOOK) —
that is restore's input. S2 and restore are a clean matched pair.

---

## FINDING 5 — `utils.sh` ALREADY provides `tmux_clear_hook` (house style = USE IT)

`scripts/utils.sh` defines (and documents) the exact helper:
```bash
# $1: hook name. Clears EVERY index of the hook array (mirrors set-option -gu
# on an array option). Used by activate to suppress session-window-changed.
tmux_clear_hook() {
	tmux set-hook -gu "$1"
}
```

→ House style (mirrors T1 using `tmux_save_opt` / `tmux_get_hook`): S2 calls
`tmux_clear_hook session-window-changed`. The raw equivalent
`tmux set-hook -gu session-window-changed` (the contract's verbatim phrasing) is
IDENTICAL in effect — the helper exists precisely so activate/restore do not
re-implement TRAP 2. Either form is correct; the helper is preferred for
consistency with the lib trio.

---

## FINDING 6 — `select-window` fires `session-window-changed` (the thing suppressed)

Confirmed by PRD §7.11 + system_context §4 TRAP 2: changing the active window
in a session fires `session-window-changed` (the user's `sync-window-focus.sh`
runs on it). During live preview, `preview.sh`'s `select-window` nav would fire
it on every keystroke → focus bytes spam into the linked preview window. That is
the side effect S2 suppresses. `select-window` does NOT fire
`client-session-changed` (Invariant A) → session-history pollution is zero
regardless of suppression; this is purely a focus-hook concern.

The mock exploits this directly: set a hook that appends to a log, run
select-window, assert the log's growth (baseline) then NON-growth (after S2).

---

## FINDING 7 — `opt_suppress_window_hook()` default = "on"; "off" is an INTENTIONAL no-op

`scripts/options.sh`:
```bash
opt_suppress_window_hook() { get_opt "@livepicker-suppress-window-hook" "on"; } # bool on/off
```

PRD §11 default = `on`. PRD §7.11: when on, clear the hook for the picker
duration + restore on exit. The contract is explicit that `off` is a DOCUMENTED
opt-in: "If off: leave the hook intact (preview navigation will run
sync-window-focus.sh — documented behavior)." So the S2 block is a single gate:

```bash
if [ "$(opt_suppress_window_hook)" = "on" ]; then
	tmux_clear_hook session-window-changed
fi
```

This mirrors the guard at the TOP of activate_main
(`if [ "$(get_state "$STATE_MODE" "off")" = "on" ]; then return 0`) — the same
`"$(accessor)" = "on"` idiom. No new local variable is needed (single-use read;
declaring one is optional and adds no safety).

---

## FINDING 8 — variable/namespace budget: S2 needs NO new locals

S2 writes no `@livepicker-*` key, declares no function-local (the `if` reads the
accessor inline). It does not collide with T2's (`pick_type current list idx i`
/ `items`), T3's (`sf_n sf_val sf_indices lp_idx orig_status` / `sf_desc`), or
S1's (`lp_key lp_keys lp_tf lp_c`) locals. The only NEW symbol introduced is
the block's header comment. This keeps the surgical-edit footprint to the
minimum: one seam line → one small block.

---

## Summary: the load-bearing facts for the PRP block

| # | Fact | Consequence |
|---|---|---|
| 1 | `set-hook -gu session-window-changed` clears `[0]` (verified) | This IS the suppression primitive. |
| 2 | show-hooks always rc=0; "set?" = grep `[` | Mock asserts presence/absence via `grep -q '\['`, NOT `$?`. |
| 3 | `set-hook -gu` is a safe no-op on cleared/absent hook | No guard needed; only the config flag gates it. |
| 4 | `set-hook -g` replaces `[0]`; user has one `[0]`; restore replays it | S2 clears LIVE only; never touches ORIG_HOOK (restore's input). |
| 5 | `utils.sh tmux_clear_hook` already does this (house style) | USE the helper; raw form equivalent. |
| 6 | select-window fires session-window-changed (the spam source) | Mock: hook→log, select-window, assert log stalls after S2. |
| 7 | default on; off = intentional no-op | Single `if opt=on` gate; mirror the guard idiom. |
| 8 | No new locals, no `@livepicker-*` writes | Minimal surgical edit; zero namespace collision. |
