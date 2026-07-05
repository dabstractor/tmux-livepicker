# Research: restore.sh — status / status-format / key-table / renumber / hook (P1.M5.T3.S1)

Empirically verified live on 2026-07-05 against `/usr/bin/tmux` (3.6b) on an
**isolated socket** (`tmux -L lp-t3-verify<N>-$$`, killed on exit — the live
server was never the target and its `session-window-changed` hook was confirmed
+ restored to its verified value afterward). Implements PRD §9 restore **step 4**
+ §16 (restore the `-b` hook exactly) + system_context §4 TRAP 1 / TRAP 2.

## Setup (the verification shape)

```
SOCK="lp-t3-verifyN-$$"
TMX() { /usr/bin/tmux -L "$SOCK" "$@"; }
TMX new-session -d -s drv -x 80 -y 24
```

ACTIVATE (the matched writer, already COMPLETE) does, in order: T1 saves
`status`, every user-set `status-format[n]`, `key-table`, `renumber-windows`, the
FULL `show-hooks -g session-window-changed` output into `@livepicker-orig-*`
keys; T3 grows the status bar + installs the renderer at `status-format[IDX]`;
T4.S1 sets `key-table livepicker` (with `-g`); T4.S2 clears the live
`session-window-changed` hook when `@livepicker-suppress-window-hook == on`.
**T3.S1 (this task) must make every one of these byte-identical to pre-activate.**

## Findings

### FINDING 1 — `state_status_format_restore()` is ALREADY COMPLETE in state.sh; T3.S1 just CALLS it  [VERIFIED via state.sh read + §-byte-identical probe]

`scripts/state.sh` already implements the matched undo of T3's status grow:

```bash
state_status_format_restore() {
	local indices n val
	tmux_unset_opt status-format          # = set-option -gu status-format (TRAP 1)
	indices="$(tmux_get_opt "$ORIG_STATUS_FORMAT_INDICES" "")"
	for n in $indices; do
		val="$(tmux_get_opt "${ORIG_STATUS_FORMAT_PREFIX}${n}" "")"
		[ -n "$val" ] && tmux_set_opt "status-format[$n]" "$val"
	done
}
```

- `tmux_unset_opt status-format` → `set-option -gu status-format` (index-less)
  clears EVERY index of the array (including the renderer line T3 installed at
  `status-format[IDX]`) and tmux re-composes the built-in defaults `[0,1,2]`.
  This is TRAP 1 (system_context §4) — **never** replay captured default strings.
- In THIS env `ORIG_STATUS_FORMAT_INDICES` is `""` (tubular unsets status-format
  → no genuinely-user-set indices ≥3), so the replay loop is a no-op and the
  array returns to pure defaults. Correct.

**Byte-identical probe (isolated socket):**
```
SF_BEFORE="$(TMX show-options -g status-format)"     # defaults only
TMX set-option -gu status-format                      # the restore primitive
SF_AFTER="$(TMX show-options -g status-format)"
[ "$SF_BEFORE" = "$SF_AFTER" ]  -> YES   # status-format -gu is BYTE-IDENTICAL
```
**Conclusion:** T3.S1 does `state_status_format_restore` (one call). It owns the
status-format array entirely; T3.S1 adds NO status-format logic of its own.

### FINDING 2 — STATUS restore: `set-option -g status "$ORIG_STATUS"` round-trips byte-identically  [VERIFIED]

```
TMX set-option -g status on
S_ORIG="$(TMX show-option -gqv status)"     # "on"
TMX set-option -g status 2                  # T3 grew it to 2
TMX set-option -g status "$S_ORIG"          # restore
TMX show-option -gv status                  # -> "on"   (byte-identical)
```
**Conclusion:** read `ORIG_STATUS` via `get_state "$ORIG_STATUS" "on"`, then
`tmux set-option -g status "$r_status"`. Use `get_state`'s second arg `"on"` as
the defensive default (matches activate's `tmux_save_opt status status`, which
read the live `on`). The `-g` is REQUIRED (T3's grow used `-g`; matched pair).
NO `case`-normalization needed on RESTORE (that was T3's grow-time concern —
`$((on+1))` crashes; restore replays the raw saved string directly, which is a
valid tmux status value).

### FINDING 3 — KEY-TABLE restore MUST use `-g` (work-item literal text is WRONG)  [VERIFIED — LOAD-BEARING CORRECTION]

The work-item contract literally wrote `tmux set-option key-table "$ORIG_KEY_TABLE"`
(**no** `-g`). This is INCORRECT. ACTIVATE used `set-option -g key-table livepicker`
(T4.S1 FINDING 3) and SAVED it via `show-option -gqv key-table` (a GLOBAL read, via
`tmux_save_opt`). For restore to be the matched pair, it MUST ALSO use `-g`.

**Isolated-socket proof:**
```
TMX set-option -g key-table livepicker
TMX set-option key-table root            # NO -g (the work-item literal form)
TMX show-option -gv  key-table           # -> "livepicker"  (UNCHANGED — the switch FAILED)
TMX show-option -gqv key-table           # -> "livepicker"  (UNCHANGED)
TMX set-option -g  key-table root        # WITH -g (the corrected form)
TMX show-option -gv  key-table           # -> "root"        (took effect ✓)
TMX show-option -gqv key-table           # -> "root"        (took effect ✓)
```
**Conclusion:** restore is `tmux set-option -g key-table "$r_kt"` where
`r_kt="$(get_state "$ORIG_KEY_TABLE" "root")"` (default `"root"` — system_context
§2: the live value is `root`; activate's save captured it). The no-`-g` form
sets a session-scoped value that `show-option -gv` does not reflect (the same
T4.S1 FINDING 3 trap). This is a **correction** to the work-item's literal text;
the PRP encodes the `-g` form.

### FINDING 4 — RENUMBER-WINDOWS restore: `set-option -g renumber-windows "$ORIG"` round-trips  [VERIFIED]

```
TMX set-option -g renumber-windows on
R_ORIG="$(TMX show-option -gqv renumber-windows)"   # "on"
TMX set-option -g renumber-windows off
TMX set-option -g renumber-windows "$R_ORIG"
TMX show-option -gv renumber-windows                # -> "on"  (byte-identical)
```
**Conclusion:** `tmux set-option -g renumber-windows "$r_renumber"` where
`r_renumber="$(get_state "$ORIG_RENUMBER" "on")"`. `-g` required (activate's save
was global; matched pair). Default `"on"` (system_context §2).

### FINDING 5 — HOOK replay MUST preserve the index (work-item literal text is WRONG for multi-index)  [VERIFIED — LOAD-BEARING CORRECTION]

The work-item contract literally wrote, for each saved line
`session-window-changed[N] <cmd>`: `tmux set-hook -g session-window-changed "<cmd>"`
(**index-less**). This is CORRECT for the single-index real env but is **WRONG for
multi-index**: the index-less `set-hook -g session-window-changed "<cmd>"` ALWAYS
writes to index `[0]`, so iterating two saved lines both target `[0]` and the last
one clobbers the first.

**Isolated-socket proof — the index-less form FAILS multi-index:**
```
TMX set-hook -g "session-window-changed[0]" "run-shell -b /home/.../sync-window-focus.sh"
TMX set-hook -g "session-window-changed[1]" "run-shell 'echo second-hook'"
ORIG = two lines: [0]=sync-focus, [1]=echo second-hook
TMX set-hook -gu session-window-changed          # simulate activate suppress
# index-less replay (the work-item literal form):
TMX set-hook -g session-window-changed "run-shell -b .../sync-window-focus.sh"
TMX set-hook -g session-window-changed "run-shell 'echo second-hook'"
REST = ONE line: [0]=run-shell 'echo second-hook'   (clobbered!)   -> NOT byte-identical
```

**The CORRECT, index-preserving replay** parses the saved `[N]` and re-applies it:
```bash
while IFS= read -r line; do
	case "$line" in "session-window-changed"|"" ) continue ;; esac   # bare name -> skip
	idx="$(printf '%s\n' "$line" | sed -n 's/^session-window-changed\[\([0-9]\+\)\].*/\1/p')"
	cmd="${line#session-window-changed\[*\] }"
	[ -z "$idx" ] && continue
	tmux set-hook -g "session-window-changed[$idx]" "$cmd"            # PRESERVES the index
done <<< "$r_hook"
```

**Isolated-socket proof — the index-preserving form is byte-identical for BOTH:**
```
# SINGLE index (real env shape):
ORIG = [0] run-shell -b /home/.../sync-window-focus.sh
after clear + index-preserving replay -> [0] run-shell -b /home/.../sync-window-focus.sh
>>> SINGLE: BYTE-IDENTICAL YES

# MULTI index (general-case robustness):
ORIG = [0] run-shell -b .../sync-window-focus.sh ; [1] run-shell 'echo second-hook'
after clear + index-preserving replay -> BOTH lines restored
>>> MULTI: BYTE-IDENTICAL YES
```
- The `-b` flag is preserved (it is part of the recovered `<cmd>` string; nothing
  strips it). The absolute path is preserved identically.
- `sed -n 's/^session-window-changed\[\([0-9]\+\)\].*/\1/p'` extracts the index
  digit(s); `${line#session-window-changed\[*\] }` strips the
  `session-window-changed[N] ` prefix to recover the command. Both verified.
- The command may contain spaces / quotes (e.g. `run-shell "echo second-hook"`),
  so it is passed to set-hook as ONE quoted arg: `"$cmd"`. Verified.

**Conclusion:** restore replays the saved hook **index-preserving**. This is a
**correction** to the work-item's literal index-less text. The bare-name branch
(`session-window-changed` with no `[`) skips (no `set-hook` fires) → the live
hook stays cleared (which equals "leave unset" — FINDING 6).

### FINDING 6 — BARE-NAME / nothing-saved branch: skip → hook stays unset (correct)  [VERIFIED]

When no `session-window-changed` hook was set at save time, `show-hooks -g
session-window-changed` returns just the bare `session-window-changed` (rc=0).
The save stored that bare line in `ORIG_HOOK`. On restore, the loop's
`case "$line" in "session-window-changed") continue ;;` skips it → no `set-hook`
fires → the live hook stays cleared (activate's suppress already cleared it). This
exactly matches the work-item's "If nothing was saved, `set-hook -gu
session-window-changed` (leave unset)" — the no-op replay achieves the SAME end
state (cleared) as an explicit `set-hook -gu`. No explicit clear is required
before replay because, under the `suppress==on` gate, activate already cleared
the live hook (the pre-replay state is "cleared" by construction).

### FINDING 7 — the replay is GATED on `@livepicker-suppress-window-hook == on` (mirror of activate T4.S2)  [VERIFIED via contract symmetry]

Activate T4.S2 clears the LIVE hook ONLY when `opt_suppress_window_hook == "on"`.
Restore T3.S1 replays the SAVED hook under the SAME gate. When the option is `off`,
activate did NOT clear the hook (the live hook is still the user's original), so
restore does NOTHING for the hook (the `if` skips it) — the live hook is already
correct. Replaying under `off` would be harmless (it would set the hook to the
saved value, which equals the live value since activate didn't change it) but the
work-item contract gates it on `on`, so we follow that for symmetry and to avoid
a needless `set-hook`. Use `if [ "$(opt_suppress_window_hook)" = "on" ]; then ...`
— the SAME idiom as activate T4.S2 and the guard at the top of activate_main.

### FINDING 8 — the saved hook is the FULL `show-hooks` output, possibly multi-line; tmux preserves newlines in @-options  [VERIFIED via activate T1 + state.sh]

Activate T1's STEP 2 stored `ORIG_HOOK` via
`tmux set-option -g "$ORIG_HOOK" "$(tmux_get_hook session-window-changed)"`. The
value is the FULL raw `show-hooks` output — one `session-window-changed[N] <cmd>`
line per index, newline-separated. tmux preserves the newlines inside the
`@livepicker-orig-session-window-changed` option (verified by the multi-index
probe: both lines round-tripped through save→replay). So restore MUST iterate
every line of the saved value (the `while IFS= read -r line; do ... done <<<
"$r_hook"` heredoc form), not assume a single line. (The real env has exactly
one `[0]` line; the loop is general.)

### FINDING 9 — restore.sh runs as a SUBPROCESS under run-shell; source its own lib trio  [VERIFIED via restore.sh header / P1.M5T1S1 FINDING 7]

restore.sh is invoked via `run-shell` (from `input-handler.sh` P1.M6 confirm/cancel).
It already sources `options.sh → utils.sh → state.sh` via `$CURRENT_DIR`
(P1.M5.T1.S1 built this). T3.S1's hook-replay calls bare `tmux` (NOT a utils
helper — there is no `tmux_set_hook` helper; `set-hook` is straightforward enough
to call directly, mirroring how `clear_all_state` calls `tmux set-option -gu`
directly). The status/key-table/renumber restores can use `tmux_set_opt` from
utils.sh OR direct `tmux set-option -g`; both are equivalent. House style:
`tmux set-option -g` direct is fine and matches `clear_all_state`.

### FINDING 10 — house style: `set -u` ONLY; tabs; `|| true` on fail-possible tmux; `local` for all loop vars  [VERIFIED via system_context §9 / restore.sh header]

restore.sh inherits `set -u`, NO `-e`, NO `-o pipefail`. The hook-replay loop's
`tmux set-hook` calls do NOT need `|| true` (set-hook succeeds on a valid command;
FINDING: rc=0). But to be uniformly safe (a future hook-arg edge), the replay
calls may append `2>/dev/null || true` — harmless. `local` for ALL function
locals (the loop needs `hk_line hk_idx hk_cmd`; the option reads need `r_status
r_kt r_renumber r_hook`). Indent with TABS (`grep -Pn '^    '` must be empty).

## Sources

- Empirical: the isolated-socket scripts above (run 2026-07-05, 3.6b; live server
  untouched + its hook restored to the verified value afterward).
- `scripts/state.sh` — `state_status_format_restore()` (ALREADY COMPLETE; T3.S1 calls it),
  `ORIG_STATUS` / `ORIG_KEY_TABLE` / `ORIG_RENUMBER` / `ORIG_HOOK` constants,
  `get_state`.
- `scripts/utils.sh` — `tmux_set_opt` / `tmux_get_opt` / `tmux_unset_opt` (the
  status-format `-gu` primitive is `tmux_unset_opt status-format`).
- `scripts/options.sh` — `opt_suppress_window_hook` (default `"on"`; the gate).
- `plan/001_fd5d622d3939/P1M4T1S1/PRP.md` (the SAVE side — what ORIG_* contains).
- `plan/001_fd5d622d3939/P1M4T3S1/PRP.md` FINDINGS (status grow — the matched
  writer T3.S1 undoes; the `case` normalization is grow-only, not restore).
- `plan/001_fd5d622d3939/P1M4T4S1/PRP.md` FINDING 3 (key-table `-g` is mandatory;
  the no-g form does not take effect — T3.S1's restore reuses this).
- `plan/001_fd5d622d3939/P1M4T4S2/PRP.md` (the suppress gate T3.S1 mirrors).
- `plan/001_fd5d622d3939/architecture/system_context.md` §2 (live values), §4
  (TRAP 1 + TRAP 2), §9 (shell style).
- `PRD.md` §9 (restore step 4), §16 (restore the `-b` hook exactly).
