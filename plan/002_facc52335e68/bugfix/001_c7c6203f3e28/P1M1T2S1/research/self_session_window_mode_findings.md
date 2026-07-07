# Self-session guard window-mode extension — empirical grounding (tmux 3.6b)

> Verified LIVE on 2026-07-07 against isolated `-L` sockets (which source the
> user config → `base-index=1`, `renumber-windows=on`). The `issue1_2_findings.md`
> researcher had NO shell; its key empirical claims were marked "needs confirmation".
> This file proves them (and corrects one) on the real target.

## Environment

| Tool | Version |
|---|---|
| tmux | **3.6b** |
| isolated-socket config | `base-index=1`, `renumber-windows=on` (windows index from 1, not 0) |

## Current code state (post Issue 1 / S1 fix, which is Complete)

- `scripts/preview.sh` is 209 lines. The self-session guard is at **line 127**:
  `if [ -n "$current_session" ] && [ "$S" = "$current_session" ]; then`
- The locals declaration is at **line 82**: `local current_session orig_window linked_id src_id w_sess w_idx cur_seq`
- The window-mode `src_id` resolution is at **lines 144-149** (AFTER the guard).
- The deferred-preview supersede guards are at lines 90-94 (top) and 166 (pre-mutation).
- The link call (line 187) is now the BARE form `tmux link-window -s "$src_id" -t "$current_session:"` (no `-a`) — S1 landed.

---

## FINDING 1 — ⚠️ CORRECTION to issue1_2_findings.md: bare `link-window -s @id -t session:` WORKS

The findings doc (§ISSUE 1, "⚠️ NOT a valid fix") claimed bare `link-window -s @id -t session:`
(without `-a`) "resolves to the active window's occupied index and fails rc=1, silently
disabling live preview." **This is FALSE on tmux 3.6b.** Verified:

```
driver windows before: 1:shell(@0) 2:workA(@1) 3:workB(@2)
tmux link-window -s @3 -t 'driver:'   →  rc=0
driver windows after:  1:shell(@0) 2:workA(@1) 3:workB(@2) 4:apane(@3)
```

Bare `link-window -s @src -t session:` **appends at the next free index at the END**
(no shift, no collision, rc=0). So S1's fix (the bare form) is CORRECT and the foundation
is solid. (The findings researcher had no shell and reasoned from man-page wording; the
empirical behavior is append-at-end.) → The non-self link path works; my Issue 2 fix builds
on a working foundation.

---

## FINDING 2 — The `${S%%:*}` guard fix (100% pure bash, verified)

OLD guard `[ "$S" = "$current_session" ]` with `S="driver:1"`, `current_session="driver"`:
**NO MATCH** (misses → duplicate created). NEW guard `[ "${S%%:*}" = "$current_session" ]`:
**MATCH** (fires). Session-mode backward compat: `${S%%:*}` on `"driver"` (no colon) =
`"driver"` unchanged → identical behavior. Verified for `driver`, `driver:1`, `driver:2`,
`alpha:0`. This `${S%%:*}` idiom is ALREADY used 3× in the same file (lines 62, 144, 146).

---

## FINDING 3 — `select-window -t "$S"` works (the contract's simple approach)

`select-window -t 'driver:1'` → rc=0, selects window index 1. `select-window -t 'driver:2'`
→ selects workA. So in the self-session block, `select-window -t "$S"` (where `$S` is the
`session:index` token) directly selects the highlighted driver window. Verified.

**Why this is safe despite the codebase "@id, never index" invariant (line 30):** that
invariant guards against `renumber-windows` making indices stale. But the self-session guard
fires for the DRIVER's OWN windows, and `$S`'s index comes from the picker's SNAPSHOTTED list
(built once at activation). During the picker, NO driver window is closed/destroyed
(link/unlink don't trigger renumber), so the driver's indices are STABLE for the whole picker
lifetime → `$S`'s index is valid. (`base-index` 0-vs-1 is irrelevant: `$S`'s index always
matches the real index because both come from `#{window_index}`.) The @id approach was
considered (resolve src_id before the guard) but rejected: bigger diff, duplicates the
resolution logic, and gains nothing because indices are snapshot-stable.

---

## FINDING 4 — The duplicate-creation bug confirmed (the root of Issue 2)

Linking a window ALREADY linked into the target session does NOT fail — tmux silently
creates a DUPLICATE (rc=0):
```
driver BEFORE: 1:shell(@0) 2:workA(@1) 3:workB(@2)
tmux link-window -s @0 -t 'driver:'  → rc=0
driver AFTER:  1:shell(@0) 2:workA(@1) 3:workB(@2) 4:shell(@0)   ← DUPLICATE @0
```
This is exactly why the self-session guard must PREVENT reaching `link-window` for
driver-owned windows. (Documented in preview.sh header FINDING 4.)

---

## FINDING 5 — End-to-end fix simulation (the load-bearing proof)

Simulated the FULL fixed self-session block against an isolated socket. Setup: driver has
shell/workA/workB + a prior cross-session alpha preview linked at the end (linked_id=alpha's
@id). Preview `driver:2` (workA) in window mode:

```
driver BEFORE: 1:shell(@0) 2:workA(@1) 3:workB(@2) 4:apane(@3)
guard: check_session=[driver] = current_session=[driver] -> FIRES
select-window -t 'driver:2' -> rc=0
driver AFTER:  1:shell(@0) 2:workA(@1) 3:workB(@2)        ← alpha preview UNLINKED, NO dup of workA
active window: workA                                        ← correct window selected
```

Results:
- ✅ Guard fires for the driver-owned window (window mode).
- ✅ Prior cross-session preview (alpha) is unlinked (the `if [ -n "$linked_id" ]` block).
- ✅ NO duplicate of workA created (we `return 0` before reaching `link-window`).
- ✅ The specific highlighted window (workA = driver:2) is selected.
- ✅ Session-mode backward compat: `check_session` = `$S` unchanged for bare names → selects ORIG_WINDOW.
- ✅ Foreign-session window mode (`alpha:0`): guard does NOT fire → falls through to the normal link path.

---

## FINDING 6 — Interaction with the deferred-preview supersede guards

The self-session block sits AFTER the top-of-function seq guard (lines 90-94) and returns 0
BEFORE the second seq re-check (line 166). For a deferred (background) preview of a driver
window: the top guard already checked staleness; if current, the self-session block
unlinks+selects+returns without linking. No mutation needing the second re-check. This
exactly matches the EXISTING session-mode self-session behavior (which also unlinks+selects
without a second seq check). → No change to the seq guards; the window-mode extension is
consistent with the session-mode path. Do NOT add a seq check inside the self-session block.

---

## The exact fix (2 edits to preview.sh)

**Edit 1** — add `check_session` to the locals (line 82):
```bash
local current_session orig_window linked_id src_id w_sess w_idx cur_seq check_session
```

**Edit 2** — replace the self-session guard block (lines 121-134) with the window-mode-aware
version: compute `check_session` (extract session from the token in window mode), use it in
the condition, and branch the final select (window mode → `select-window -t "$S"`; session
mode → `select-window -t "$orig_window"` as before). Update the comment to document the
window-mode extension. Full verbatim block in the PRP's Implementation Patterns.
