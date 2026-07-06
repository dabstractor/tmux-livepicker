# Research — Bugfix P1.M2.T2.S1: window-index-aware resolution in preview.sh (Issue 4)

> All findings below were verified LIVE against a fresh isolated tmux socket via
> `tests/setup_socket.sh` (the repo's own PATH-shim harness) on tmux 3.6b.
> Bug context: `plan/001_fd5d622d3939/bugfix/001_15442f34c366/architecture/bugfix_findings.md` §ISSUE 4.

---

## FINDING 1 — `base-index` is inherited from `~/.tmux.conf` (the contract's literal test setup FAILS)

**Live-verified.** `tests/setup_socket.sh` starts the isolated server with
`tmux new-session -d -s driver …` (via the shim `exec "$REAL_TMUX" -L "$SOCKET" "$@"`).
It does **NOT** pass `-f /dev/null`, so the isolated server READS the user's
`~/.tmux.conf`. On this machine that sets `base-index 1` (verified:
`tmux show-options -g base-index` → `base-index 1`).

**Consequence (CRITICAL for the test):** the contract's literal commands
```bash
tmux new-session -d -s multi -x 120 -y 40
tmux new-window -t multi -n secondwin      # <- FAILS
```
produce **`create window failed: index 1 in use`**. `new-session` already
created the first window at index 1 (base-index=1, not 0), and a bare
`new-window -t multi` then tries to insert at the same slot.

**Fix for the test:** use `tmux new-window -t multi -a` (append — deterministically
creates the next free index) AND detect every index/id **dynamically** (never
hardcode). Verified: with `-a`, the second window lands at index 2 (`@5`) while
the first stays at index 1 (`@4`). The shipped tests already follow the
"detect dynamically" discipline (e.g. `test_multipane_preview` reads
`#{window_id} -f '#{window_active}'` rather than assuming index 0).

---

## FINDING 2 — `new-window` makes the new window ACTIVE; the FIRST window is non-active

**Live-verified.** After `new-session -d -s multi` + `new-window -t multi -a -n secondwin`:
```
index:id:name:active
1:@4:multi:0        <- NON-active (created first)
2:@5:secondwin:1    <- ACTIVE (new-window selects it)
```
So the **highlighted non-active** window is index 1 (`@4`), NOT the
contract's phrasing "SECOND (non-active) window". The wording in the work-item
contract is imprecise; a robust test detects the non-active window by
`#{window_active}==0` and does not assume which index it is. This is exactly the
shape the bug needs: a session with ≥2 windows where the candidate the picker
highlights is **not** the session's active window.

---

## FINDING 3 — the awk index→@id resolution (the FIX) works

**Live-verified.** The proposed resolution:
```bash
src_id="$(tmux list-windows -t "=multi" -F '#{window_id}:#{window_index}' \
          | awk -F: -v idx="$w_idx" '$2==idx {print $1; exit}')"
```
For `multi:1` (w_idx=1) → returns `@4` (the non-active window). Correct.

**Why awk, not `-f '#{window_index} == N'`:** per bugfix_findings §External research
item 3 (and the work-item contract), `-f '#{window_index} == 5'` does **NOT**
filter — the expanded text `5 == 5` is non-empty for EVERY window → always
truthy → returns all windows. The robust approach is to list all windows and
match the index field in awk (or use `#{==:#{window_index},N}`, but the awk
approach is already used elsewhere in the codebase and is portable).

---

## FINDING 4 — the BUGGY active-filter ignores the index

**Live-verified.** The current (buggy) resolution:
```bash
src_id="$(tmux list-windows -t "=multi" -F '#{window_id}' -f '#{window_active}')"
```
returns `@5` (the active window) **regardless** of any index in the token. So
for token `multi:1` it returns `@5`, then link-window links `@5` (wrong window),
and `@livepicker-linked-id` becomes `@5` — the active window, not the
highlighted index-1 window. This is the exact bug the regression test must catch.

---

## FINDING 5 — token parsing works; the colon gate is portable

**Live-verified.** `w_sess="${S%%:*}"` / `w_idx="${S#*:}"` correctly split
`multi:1` → `w_sess=multi`, `w_idx=1`.

A portable, `[ ]`-style colon-presence test (fits preview.sh's existing POSIX-ish
`[ ]` discipline — no `[[ ]]` needed): `${var%%:*}` strips everything from the
first `:` onward, so if `var` contains a `:` then `"${var%%:*}" != "$var"` is TRUE,
else FALSE. This avoids `[[ ]]` and a separate `case`:
```bash
if [ "$(opt_type)" = "window" ] && [ "${S%%:*}" != "$S" ]; then … fi
```

This mirrors the confirm branch in `input-handler.sh` (`w_sess="${target%%:*}"`,
`select-window -t "$target"`) — the SAME split, already proven correct.

---

## FINDING 6 — `preview_fallback`'s target `"=$1:."` is MALFORMED for a token

**Live-verified.** The current fallback:
```bash
captured="$(tmux capture-pane -ep -t "=$1:." 2>/dev/null)"
```
With `$1 = "multi:1"` (window mode), the target string becomes `=multi:1:.`
(`=` + `multi:1` + `:.` = two colons). tmux rejects it:
```
can't find window: 1:
```
So in window mode the capture-pane fallback is ALSO broken (it never captures the
right window, and errors out). The contract's part (c) is therefore necessary,
not optional.

---

## FINDING 7 — the fixed fallback target `=$w_sess:$w_idx.` works; session mode unchanged

**Live-verified.** Building the target from the parsed token:
```bash
w_sess="${1%%:*}"; w_idx="${1#*:}"
target="$w_sess:$w_idx"            # -> "multi:1"
captured="$(tmux capture-pane -ep -t "=$target:." 2>/dev/null)"   # =multi:1.
```
`=multi:1.` resolves to session `multi` (exact `=` match), window index 1, active
pane (`.`) → **rc=0, captures successfully**. And the session-mode target
`=alpha:.` still works (rc=0). So the fallback fix is: parse the token in window
mode, keep `=$1:.` for session mode. This handles ALL 3 call sites uniformly
(snapshot gate, src_id-empty, link-window failure) because they all call
`preview_fallback "$S"`.

---

## FINDING 8 — NO file conflict with the parallel task P1.M2.T1.S1

**Verified by reading both PRPs.** The parallel task P1.M2.T1.S1 modifies:
- `scripts/renderer.sh` (+2 local vars, 5 substitutions)
- `tests/test_functional.sh` (+2 tests)

This task (P1.M2.T2.S1) modifies:
- `scripts/preview.sh` (+window branch in preview_main; +token parse in preview_fallback)
- `tests/test_preview.sh` (+1 test)

**Disjoint** — no shared file. No edit collision, no merge concern. (P1.M1.T2.S1,
the preview-sync helper, is already COMPLETE and modified `input-handler.sh` only;
it did NOT touch `preview.sh` — it just calls `preview.sh "$target"` which is the
unchanged argv contract.)

---

## FINDING 9 — preview.sh is CLIENT-INDEPENDENT; the test needs NO attach_test_client

**Verified (mirrors `tests/test_preview.sh` header + research).** preview.sh reads
the driver session from `@livepicker-orig-session` via `get_state` (NOT
`display-message`), so it runs on the detached isolated socket. The test reuses
`lp_preview_seed_state` (defined at the top of `tests/test_preview.sh`) which sets
`@livepicker-orig-session`, `@livepicker-orig-window`, `@livepicker-linked-id`.
The test additionally sets `@livepicker-type window` (opt_type gates the new
branch). No `attach_test_client` needed.

---

## FINDING 10 — the rest of preview_main is UNCHANGED (operates on $src_id @id handle)

**Verified by reading scripts/preview.sh.** Once `src_id` is the CORRECT window
@id (the highlighted one, not the active one), the downstream flow is unchanged
and correct:
- empty-src_id fallback → `preview_fallback "$S"` (now fixed for window mode)
- duplicate guard (`linked_id == src_id` → skip unlink+link, just select)
- unlink prior link (`unlink-window -t "$current_session:$linked_id"` — by @id)
- `link-window -a -s "$src_id" -t "$current_session:"` (links the @id window)
- `select-window -t "$src_id"` (by @id — the plugin's invariant)
- `set_state "$STATE_LINKED_ID" "$src_id"` (tracks the correct @id)

All operate on the `@id` handle (the plugin's invariant — never index), so they
work unchanged once `src_id` resolves to the right window.

---

## FINDING 11 — the "prove-it-catches-the-bug" check is deterministic

With the fix REVERTED (the window branch removed), preview.sh resolves `src_id`
via `#{window_active}` → returns the ACTIVE window's @id (`@5`) regardless of the
token index → links `@5` → sets `@livepicker-linked-id=@5`. The regression test
asserts `linked-id == <non-active @id>` (`@4`) → **FAILS**. So the test
deterministically fails before the fix and passes after — a real regression
guard, not a tautology.

---

## FINDING 12 — placement: add `w_sess w_idx` to the existing `local` declaration

preview_main currently declares:
```bash
local S="${1:-}"
local current_session orig_window linked_id src_id
```
Adding `w_sess w_idx` to the second line keeps declarations at the top (the
file's style). They are only ASSIGNED+READ inside the window branch, so they
remain `set -u`-safe (declared → never "unset"; empty in the else branch where
they are never read). preview_fallback declares its own `local` (it currently has
`local captured`; add `target` + inner `local w_sess w_idx` in the branch).

---

## FINDING 13 — indentation is TABS (system_context §9); shfmt NOT installed

All scripts/tests use TABS (verified: `grep -Pn '^    ' scripts/preview.sh` → no
space-indent hits). New code must use TABS to match. No `shellcheck` config for
the new lines (preview.sh already has a file-level `shellcheck disable=SC1091,SC2153`;
the `awk` pipe is fine under SC2086 since `$w_idx` is a sanitized integer passed
via `-v idx=` — no word-splitting of the value occurs).
