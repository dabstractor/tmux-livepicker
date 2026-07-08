# Research — P2.M1.T1.S1: rename/delete/confirm-delete options + activate binding step 5

Captured 2026-07-08 by direct inspection of the COMPLETE+shipped codebase.
Every finding below is verbatim from the source.

## FINDING 1 — options.sh accessor pattern + insertion point (§P2)

`scripts/options.sh` is a SOURCED library (NO `*_main` driver, NO side effects).
One `opt_<name>()` one-liner per `@livepicker-*` option, default PRD §11 verbatim:

```bash
opt_backspace_keys()       { get_opt "@livepicker-backspace-keys" "BSpace"; } # space-list
opt_preview_mode()         { get_opt "@livepicker-preview-mode" "live"; }     # enum: live|snapshot|off
```

The header comment states a load-bearing formatting rule: *"Argument formatting
uses single space so the Level 4 default cross-check grep matches each
`get_opt "@livepicker-<suffix>" "<default>"` exactly once."* So the literal
substring `get_opt "@livepicker-rename-key" "C-r"` must appear exactly once.

**The 3 accessors are SINGLE-KEY (not space-list) per PRD §11 / work-item §3.**
`opt_rename_key`/`opt_delete_key` are single keys (like `opt_next_key`); they
are NOT word-split by callers. `opt_confirm_delete` is a bool on/off (like
`opt_create`).

**Insertion point**: between `opt_backspace_keys()` (line 36) and
`opt_preview_mode()` (line 37). This groups the key/action accessors (nav,
confirm, cancel, backspace, rename, delete) and matches PRD §11's ordering
(rename-key, delete-key, confirm-delete sit between backspace-keys and
preview-mode). Accessors are column-0 (no indent); `{` alignment is cosmetic
but should be visually consistent with the neighboring line.

The 3 new accessors:
```bash
opt_rename_key()       { get_opt "@livepicker-rename-key" "C-r"; }        # single key (rename via tmux prompt; PRD §21)
opt_delete_key()       { get_opt "@livepicker-delete-key" "M-BSpace"; }   # single key (kill session; PRD §21; mirrors sessionx @sessionx-bind-kill-session)
opt_confirm_delete()   { get_opt "@livepicker-confirm-delete" "off"; }    # bool on/off (confirm-before kill; off=sessionx-style immediate)
```

## FINDING 2 — livepicker.sh activate T4 nav block + insertion point (the "step 5")

`scripts/livepicker.sh::activate_main` block T4 ("build livepicker key table")
binds keys in this exact order (each block runs AFTER the prior, so LATER binds
OVERRIDE earlier same-key binds — the load-bearing rule):

1. (1) COPY prefix+root -> livepicker via source-file (filtered to drop harmful
   bindings); skip next/prev keys.
2. (2a) typing: `for lp_c in {a..z} {A..Z} {0..9} - _ . /` -> `type $lp_c`
3. (2b) backspace / confirm / cancel (space-list `for` loops -> backspace/confirm/cancel)
4. (2c) nav: next-key+nav-next-keys -> next-session; prev-key+nav-prev-keys -> prev-session
5. **(2d) <-- THIS TASK adds step 5 here: rename + delete binds (the mgmt keys)**
6. (3) SWITCH key-table to livepicker (`set-option -g key-table livepicker`)

The EXACT insertion point (tabs shown as →): AFTER the prev-key `done` and the
blank line, BEFORE the `# (3) SWITCH` comment:

```
→for lp_c in $(opt_prev_key) $(opt_nav_prev_keys); do
→→    tmux bind-key -T livepicker "$lp_c" run-shell "$CURRENT_DIR/input-handler.sh prev-session"
→done
                                      ← INSERT THE 2 MGMT BINDS HERE (with a section comment)
→# (3) SWITCH the active key-table to livepicker (global; FINDING 3: -g is
→# mandatory and the standalone `key-table` cmd does not exist on 3.6b).
→tmux set-option -g key-table livepicker
```

The 2 binds are SINGLE bind-key lines (NOT `for` loops), because the accessors
are single keys, not space-lists:

```bash
	# mgmt: rename + delete (PRD §21). SINGLE keys (not space-lists -> no loop).
	tmux bind-key -T livepicker "$(opt_rename_key)" run-shell "$CURRENT_DIR/input-handler.sh rename"
	tmux bind-key -T livepicker "$(opt_delete_key)" run-shell "$CURRENT_DIR/input-handler.sh delete"
```

This mirrors the nav binding form EXACTLY: `tmux bind-key -T livepicker "$KEY"
run-shell "$CURRENT_DIR/input-handler.sh <action>"` where `$CURRENT_DIR` is the
`scripts/` dir global (resolved at the top of livepicker.sh). Indentation = TABS.

## FINDING 3 — the binding is INERT until P2.M1.T2 (the `*` default no-op)

The 2 binds store the command string `run-shell ".../input-handler.sh rename"`
/ `... delete`. tmux only RUNS that string when the key is pressed.
`input-handler.sh` dispatch (the `case "$action"`) currently has branches for
type/backspace/next-session/prev-session/confirm/cancel/refresh-width and a
DEFAULT:

```bash
	*)
		# Unknown action — defensive no-op (never crash the picker).
		return 0
		;;
```

So pressing `C-r` / `M-BSpace` during the picker TODAY (after this task, before
P2.M1.T2) hits the `*)` branch -> returns 0 -> no-op. The picker stays open, no
harm. P2.M1.T2 adds the `rename)` / `delete)` case branches + session-mgmt.sh.
**This is the documented "inert" guarantee.** Do NOT add the case branches here
(that is P2.M1.T2's contract).

## FINDING 4 — the override rule: why mgmt keys must be non-alphanumeric

PRD §16 "Navigation keys must be non-alphanumeric" + §8: in the modal
`livepicker` table, tmux keeps the LAST binding for a given key. The typing
block (step 2) binds every letter/digit; the nav/mgmt blocks (steps 3/4/5) run
AFTER, so a nav/mgmt key OVERRIDES a same-key typing binding.

`C-r` (rename) is a DISTINCT tmux key from `r` (typing). `M-BSpace` (delete) is
DISTINCT from `BSpace` (backspace). So they do NOT collide with the typing set —
the user can still type `r` and use `BSpace`. The override only matters vs a
COPIED user binding on the same key (e.g. if the user bound `C-r` in root, the
explicit picker `C-r` bind wins because it runs after the copy). This is why the
mgmt binds MUST run after the copy block — which step 5's placement guarantees.

## FINDING 5 — sessionx parity (default key naming)

PRD §21.1: the defaults match sessionx so livepicker can replace it:
- `@livepicker-rename-key` default `C-r` == sessionx `@sessionx-bind-rename-session ctrl-r`
- `@livepicker-delete-key` default `M-BSpace` == sessionx `@sessionx-bind-kill-session alt-bspace`
- `@livepicker-confirm-delete` default `off` == sessionx's immediate-kill (snappy) behavior;
  `on` wraps the kill in `confirm-before` (y/n prompt).

## FINDING 6 — delete guards (the "driver/last-session refuse" README note)

PRD §21 Delete step 2 — `do-delete` (P2.M1.T2) REFUSES with a display-message
(no kill) when:
- `S == ORIG_SESSION` (the driver session the client lives in): killing it would
  destroy the picker host + detach the client.
- `@livepicker-list` has length 1: tmux requires >=1 session.

Plus the linked-preview leak guard (PRD §16 "kill-session + linked preview
leak"): if the preview window id == `@livepicker-linked-id`, `unlink-window` it
from the driver FIRST, else it survives `kill-session` as a permanent orphan.

These are P2.M1.T2's implementation. For THIS task's README note, document the
REFUSE behavior (driver + last session) at a changeset level (Mode A); full
prose in P4.

## FINDING 7 — delete key terminal caveat (the README note)

PRD §16 "Delete key terminal caveat (minor)" + §21.5: `M-BSpace` is sent
reliably by most terminals. A few older terminals / SSH / mosh links STRIP
Alt-modified keys entirely; if delete does not fire there, rebind to `C-h` or
`DC` (Delete). Document this in the README Usage section.

## FINDING 8 — README structure (insertion points for Mode A docs)

`README.md`:

(a) **Configuration table** — markdown table, one row per option. Insert the 3
new rows AFTER `@livepicker-backspace-keys` and BEFORE `@livepicker-preview-mode`
(matches PRD §11 ordering). Row format (pipe-aligned, ~3-space col gap):

```
| `@livepicker-rename-key`      | `C-r`      | Rename the highlighted session via tmux's prompt. Control key; never collides with typing. |
| `@livepicker-delete-key`      | `M-BSpace` | Delete (kill) the highlighted session. Matches sessionx's `@sessionx-bind-kill-session`. |
| `@livepicker-confirm-delete`  | `off`      | When `on`, prompt `y/n` before killing a session (`confirm-before`). Default `off` = immediate, sessionx-style. |
```

NOTE: the README currently still has a STALE `@livepicker-show-count` row (the
accessor was removed in P1 per codebase_patterns.md §P2). That stale row is
P4.T1's sync concern — DO NOT touch it here (scope discipline).

(b) **Usage section** — numbered steps 1-5 (Activate, Filter, Navigate,
Confirm, Cancel). Add the rename/delete keybinds as a new step (after Cancel).
The note must cover: the two keybinds, the driver/last-session refuse guard, and
the M-BSpace terminal caveat. Mode A = changeset-level (brief); full prose in P4.

## FINDING 9 — no existing test breaks; validation is via list-keys + show-option

No test asserts the exact COUNT of `opt_*` functions or the exact number of
livepicker-table bindings. Existing relevant tests:
- `tests/test_keyrepurpose.sh` checks SPECIFIC keys: `C-M-Tab` -> next-session,
  `C-M-BTab` -> prev-session. The new `C-r` / `M-BSpace` binds do not touch these.
- `tests/test_restore.sh` asserts `unbind-key -a -T livepicker` clears the table
  on cancel/confirm (the `-a` nukes ALL livepicker binds including the new ones).

So adding 2 new binds + 3 accessors CANNOT break the existing suite. The new
bindings are torn down by restore's existing `unbind-key -a -T livepicker`
(restore.sh STEP-6) — no change needed there.

**Validation for THIS task** (deterministic, isolated socket):
- `show-option -gqv @livepicker-rename-key` -> `C-r` (default); after a user
  override it returns the override.
- `list-keys -T livepicker C-r` -> `bind-key -T livepicker C-r run-shell "<abs>/input-handler.sh rename"`
- `list-keys -T livepicker M-BSpace` -> `... run-shell "<abs>/input-handler.sh delete"`
- Pressing them is INERT (the `*` no-op; verify the picker stays open + mode on).

The FULL session-mgmt integration suite is P2.M2.T1.S1 (test_session_mgmt.sh),
which will exercise the dispatch once P2.M1.T2 lands.

## FINDING 10 — set -u / escaping safety (house style)

`options.sh` has `set -u` (NOT -e). `get_opt` bakes a default so it never
returns empty under set -u. The new accessors follow this (each has a default).

The bind-key line `tmux bind-key -T livepicker "$(opt_rename_key)" run-shell
"$CURRENT_DIR/input-handler.sh rename"`: `$(opt_rename_key)` expands to `C-r`
(no special chars); `$CURRENT_DIR` expands to the absolute scripts/ dir. The
double-quoted `run-shell "..."` mirrors the nav binding form exactly (which is
verified shipping). No extra quoting needed (the action arg `rename` has no
spaces). This is identical to the existing `next-session`/`prev-session` binds.
