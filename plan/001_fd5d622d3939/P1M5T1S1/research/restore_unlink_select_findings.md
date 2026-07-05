# Research: restore.sh unlink-window + select-window (P1.M5.T1.S1)

Empirically verified live on 2026-07-05 against `/usr/bin/tmux` (3.6b) on an
**isolated socket** (`tmux -L lp-restore-verify-$$`, killed on exit). All
commands below were run; the `expect` values are the observed rc / output.

## Setup (the exact script run)

```
SOCK="lp-restore-verify-$$"
T() { /usr/bin/tmux -L "$SOCK" "$@"; }
T new-session -d -s driver -x 80 -y 24
T new-session -d -s src    -x 80 -y 24
SRC_WIN="$(T list-windows -t '=src' -F '#{window_id}' -f '#{window_active}')"   # @1
T link-window -a -s "$SRC_WIN" -t 'driver:'
```

## Findings

### FINDING 1 — `unlink-window` (NO `-k`) removes ONLY the current session's link; source KEEPS its window  [VERIFIED]

```
driver windows BEFORE link: [@0 ]
driver windows  AFTER link: [@0 @1 ]        # @1 now linked into driver
src    windows  AFTER link: [@1 ]           # @1 STILL in src (link, not move)
T unlink-window -t "driver:@1"   -> rc=0     # removed from driver ONLY
driver windows AFTER unlink: [@0 ]          # @1 GONE from driver
src    windows AFTER unlink: [@1 ]          # @1 STILL in src  ✓
```
**Conclusion:** `unlink-window -t "$SESSION:$ID"` (no `-k`) is the correct
restore primitive. It deletes ONE link; the source session S is unharmed. This
is exactly what P1.M5.T1.S1 needs: the linked preview window is unlinked from
the driver while the candidate session S keeps its window. Matches
`tmux_primitives.md §1` and the work-item RESEARCH NOTE point 1.

### FINDING 2 — `unlink-window` on a SINGLY-linked window FAILS (rc=1); MUST ignore  [VERIFIED]

```
T unlink-window -t "src:@1"   -> rc=1
   stderr: "window only linked to one session"
```
**Conclusion:** tmux refuses to orphan a window linked into only one session.
At restore this edge is reachable: if the candidate session S was killed during
browsing (its window object gone) but the link survived in the driver, OR if for
any reason the link count dropped to 1, `unlink-window` fails. The work-item
CONTRACT says "Guard non-zero exit ... by ignoring" → append `2>/dev/null ||
true` to EVERY unlink call. **NEVER pass `-k`** — that would destroy the shared
window object in ALL sessions (`tmux_primitives.md §1`; preview.sh FINDING 11).

### FINDING 3 — `select-window -t "@<id>"` succeeds (window-id addressing)  [VERIFIED]

```
T select-window -t "@1"   -> rc=0
```
**Conclusion:** addressing the original window by its `@N` id (saved in
`@livepicker-orig-window` by activate STEP 2) works and is stable.
`renumber-windows on` makes INDICES unstable (system_context §2), so the
restore target MUST be the saved id, never an index. This matches the work-item
note "ORIG_WINDOW is a window ID (not index)".

### FINDING 4 — `display-message -p '#{session_name}'` is NON-DETERMINISTIC when detached  [VERIFIED — LOAD-BEARING GOTCHA]

```
T display-message -p '#{session_name}'   (no client attached)   ->  "src"   rc=0
```
The detached server has no client; `display-message -p '#{session_name}'`
returned **"src"** — the LAST-CREATED session, an arbitrary value, NOT the
driver session where the link actually lives. This is the SAME non-determinism
preview.sh's FINDING 9 warned about, and it is exactly why preview.sh reads
`current_session` from `@livepicker-orig-session` (client-independent) instead
of `display-message`.

**Implication for restore.sh:** the work-item CONTRACT specifies
`current_session = tmux display-message -p '#{session_name}'`. This is CORRECT
in production: restore runs under `run-shell` triggered by a key press (the user
hit cancel/confirm in the `livepicker` key-table), so an attached client
provably exists, and at restore-step-1 time NO session switch has happened yet
(switch is step 3 = P1.M5.T2.S1, which runs AFTER this task's unlink+select).
Therefore the attached client's session == the driver session ==
`@livepicker-orig-session`, and `display-message` returns the right value.

**BUT:** the socket-shim TEST MOCK must keep an attached client across the
`bash restore.sh` call (mirrors P1.M4.T5.S1's mock, which had the SAME constraint
for `refresh-client -S` — its FINDING 2). A detached mock would feed
`unlink-window -t "src:@1"` (wrong session), which fails rc=1 (harmless — we
ignore it — but the link would NOT be cleaned, so the assertion "window id no
longer appears in the driver session" would FALSE-FAIL).

**Robust alternative (client-independent):** the link was created by preview.sh
into `current_session`, and preview.sh's `current_session` is
`get_state "$ORIG_SESSION" ""`. So the unlink target is ALWAYS
`"$ORIG_SESSION:$LINKED_ID"`. Using `get_state "$ORIG_SESSION" ""` directly is
deterministic, client-independent, and yields the SAME value as the attached
`display-message` in production. It is an acceptable, more-robust form of the
contract. (The PRP presents `display-message` as primary per the contract and
notes `ORIG_SESSION` as the equivalent fallback / alternative.)

### FINDING 5 — `list-windows -t '=driver' -F '#{window_id}'` is the before/after assertion handle  [VERIFIED]

```
T list-windows -t '=driver' -F '#{window_id}'    # space/newline-joined @N ids
```
**Conclusion:** the work-item MOCKING step ("assert the window id no longer
appears in the driver session but still appears in its origin session") is
implementable by capturing this list before and after `restore`, then
`grep -c "@$ID"`. The `=$S` exact-match prefix avoids prefix-collision
(`tmux_primitives.md §7`). Source session retains the window (FINDING 1).

### FINDING 6 — `linked_id == src_id` (same window object); preview.sh tracks it in `@livepicker-linked-id`  [VERIFIED via preview.sh read]

preview.sh (P1.M3.T1.S1) does `set_state "$STATE_LINKED_ID" "$src_id"` after a
successful link. The linked window's id EQUALS the source window's id (it is
the same object, linked into two sessions). So `@livepicker-linked-id` holds
the exact `@N` token to pass to `unlink-window -t "$SESSION:$LINKED_ID"`. When
the self-session path ran (P1.M4.T5.S1 first preview, or re-selecting the
current session), preview.sh CLEARS `@livepicker-linked-id` (tmux_unset_opt) —
so an empty value means "nothing linked, skip unlink" (work-item point 1 +
preview.sh self-session guard).

### FINDING 7 — restore.sh runs as a SUBPROCESS under run-shell; source its own lib trio  [VERIFIED via preview.sh / livepicker.sh idiom]

Like preview.sh and livepicker.sh, restore.sh is invoked via `run-shell` (from
`input-handler.sh` P1.M6 confirm/cancel, ultimately from a `livepicker` key-table
binding). It is its own process — it MUST source its own lib trio
(`options.sh`, `utils.sh`, `state.sh`) via the resolved `$CURRENT_DIR`, because
sourced state does not cross process boundaries. The driver idiom is:

```bash
CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$CURRENT_DIR/options.sh"
source "$CURRENT_DIR/utils.sh"
source "$CURRENT_DIR/state.sh"
restore_main() { ... }
restore_main "$@" || exit 1
exit 0
```

`shellcheck disable=SC1091,SC2153` at the top mirrors preview.sh / livepicker.sh
(SC1091: sourced libs via `$CURRENT_DIR`; SC2153: ORIG_*/STATE_* are readonly
CONTRACT constants from state.sh, no assignment seen here).

### FINDING 8 — house style: `set -u` ONLY; tabs; `|| true` on every tmux call that may legitimately fail  [VERIFIED via system_context §9]

restore.sh inherits house style: `set -u`, NO `-e`, NO `-o pipefail`. Every
tmux call whose non-zero rc is expected (unlink singly-linked edge — FINDING 2;
select-window if ORIG_WINDOW vanished; display-message if no client) is guarded
with `2>/dev/null || true`. Indent with TABS (`grep -Pn '^    '` must be empty).
`local` for all function locals.

## Sources

- Empirical: the isolated-socket script above (run 2026-07-05, 3.6b).
- `plan/001_fd5d622d3939/architecture/tmux_primitives.md §1` (link/unlink),
  `§4` (hooks), `§7` (switch-client / `=` exact match).
- `plan/001_fd5d622d3939/architecture/system_context.md §3` (Invariant A),
  `§4` (traps), `§9` (shell style).
- `scripts/preview.sh` (the unlink/self-session/linked-id pattern this mirrors;
  FINDING 6/7/9 cross-refs).
- `scripts/state.sh` (STATE_LINKED_ID / ORIG_WINDOW / ORIG_SESSION / get_state).
- `PRD.md §9` (restore steps 1-2), `§13` (unlink-window / select-window
  primitives), `§16` (window addressing by id).
