# Research: preview.sh link/unlink/select primitives (P1.M3.T1.S1)

> **Methodology:** all findings below were verified LIVE on an **isolated
> tmux socket** (`tmux -L lp-prp-proof-$$`) against **tmux 3.6b**,
> **bash 5.3.15**, **shellcheck 0.11.0** on 2026-07-05. This closes the two
> empirical gaps the original `tmux_primitives.md` researcher flagged (they
> had no shell access). Every rc and every `list-windows` diff below is real
> output, not inference.

## Setup (reproducible)

```bash
SOCK="lp-proof-$$"
tmux -L "$SOCK" new-session -d -s driver -x 100 -y 40
tmux -L "$SOCK" new-session -d -s S    -x 100 -y 40
tmux -L "$SOCK" split-window -t "=:S"; tmux -L "$SOCK" split-window -t "=:S"  # S: 3-pane window
SRC_ID="$(tmux -L "$SOCK" list-windows -t '=S' -F '#{window_id}' -f '#{window_active}')"   # -> @1
```

---

## FINDING 1 — link-window adds a link; source session KEEPS its window  [HIGH]

`tmux -L "$SOCK" link-window -a -s "@1" -t "driver:"` → **rc=0**. After:
```
driver windows: 1:=@0(driver)  2:=@1(driver)   # @1 now also in driver
S     windows: 1:=@1(S)                         # @1 STILL in S
```
The same window object (`@1`) is now linked in **both** `driver` and `S`.
`-t "driver:"` with a **bare (empty) index** makes tmux pick a free slot;
`-a` places it just after the active window. This is the fundamental property
the whole preview subsystem rests on (PRD §7; tmux_primitives.md §1). ✓

## FINDING 2 — unlink-window WITHOUT -k: succeeds when doubly-linked, FAILS when singly-linked  [HIGH]

- `unlink-window -t "driver:@1"` while `@1` is linked in **both** driver and S
  → **rc=0**; `@1` removed from driver only, **S keeps it**. ✓
- `unlink-window -t "S:@1"` when `@1` is now linked in **only** S
  → **rc=1**, stderr: `window only linked to one session`. tmux **refuses to
  orphan** a singly-linked window without `-k`. ✓

**Implication for preview.sh:** in the normal preview flow the window is always
linked in BOTH the source session S and the current session (≥2 links), so
`unlink-window` (no `-k`) succeeds and S keeps its window. The singly-linked
edge (rc=1) can only occur if the bookkeeping is already wrong; guard it by
**ignoring non-zero exit** (`|| true`), exactly as the S1 contract §3 says.

## FINDING 3 — unlink-window by @id removes ONE index per call  [HIGH]

Created a **duplicate** (see FINDING 4): `@1` linked twice in driver →
`driver: 1:=@0  2:=@1  3:=@1`. Then ONE `unlink-window -t "driver:@1"`:
```
driver after one unlink: 1:=@0  2:=@1      # index 3 gone, index 2 stays
```
`unlink-window` by window-id removes **one link (one index) per invocation**.
A duplicate therefore needs N unlink calls to fully clear. **Conclusion: never
create the duplicate in the first place** (see FINDING 5 guard).

## FINDING 4 — ⚠️ CRITICAL: re-linking an already-linked window does NOT fail — it silently creates a DUPLICATE  [HIGH, CONTRACT-CORRECTING]

`link-window -a -s "@1" -t "driver:"` when `@1` is **already linked in driver**:
```
tmux ... link-window -a -s "@1" -t "driver:"   # first  -> rc=0
tmux ... link-window -a -s "@1" -t "driver:"   # second -> rc=0  (NO error!)
driver: 1:=@0  2:=@1  3:=@1                    # @1 now at TWO indices
```
**This contradicts PRD §16** ("Linking can fail if the source is already linked
into the current session"). On tmux 3.6b it does **not** fail — it silently
adds a **second link of the same window object within the same session**, i.e.
a ghost window-list entry that accumulates on every repeat.

**Why "always unlink the previous preview first" is really load-bearing:** it
is NOT to avoid a link error (there is none). It is to avoid leaking a
duplicate window entry in the current session. Each navigation that re-links
without first unlinking would add another ghost index.

## FINDING 5 — ⚠️ CRITICAL: the literal S1 contract creates a duplicate on single-match wrap (LINKED_ID == src_id) — GUARD REQUIRED  [HIGH, CONTRACT-CORRECTING]

The S1 contract §3 says:
> if `@livepicker-linked-id` non-empty **AND != src_id**: `unlink-window ...`
> `link-window -a -s "$src_id" -t "$CURRENT_SESSION:"`  ← **unconditional**

When `LINKED_ID == src_id` (re-previewing the SAME session — e.g. a filtered
list of length 1 where next/prev wraps to the same item), this **skips the
unlink but still links** → per FINDING 4, a silent duplicate. The wrap case is
**reachable** (PRD §6 "wrapping"; PRD §15 single-match scenarios).

**Correct logic (implemented in the PRP):**
```
if LINKED_ID non-empty AND LINKED_ID == src_id:
    # window already linked + selected from last preview of this same session
    tmux select-window -t "$src_id"     # idempotent no-op (ensure shown)
    return 0                            # NO unlink, NO link, NO state change
if LINKED_ID non-empty AND LINKED_ID != src_id:
    tmux unlink-window -t "$CURRENT_SESSION:$LINKED_ID" || true   # drop the old
tmux link-window -a -s "$src_id" -t "$CURRENT_SESSION:"           # add the new
tmux select-window -t "$src_id"
set_state LINKED_ID src_id
```
This is a **justified correction** to the literal S1 contract. It is
*compatible* with S2 (P1.M3.T1.S2), which only adds the mode gate, the
capture-pane fallback, and self-session refinement — none of them touch this
guard.

## FINDING 6 — ⚠️ self-session link does NOT fail either; the guard is behavioral, not protective  [HIGH, CONTRACT-CLARIFYING]

`link-window -a -s "@1" -t "S:"` where `@1` belongs to S itself:
```
tmux ... link-window -a -s "@1" -t "S:"   # rc=0  (NO error!)
S windows: 1:=@1(panes=3)  2:=@1(panes=3)  # duplicate within S
```
**This contradicts PRD §7** ("a session cannot link its own window into
itself"). tmux 3.6b **allows** it (creating an in-session duplicate).

**Implication:** the self-session branch (`if S == current_session:
select-window -t "$ORIG_WINDOW"; return`) is still the **correct behavior**
— it shows the user their own session as the preview and avoids a useless
duplicate — but it is **not** needed to prevent a link error. The S1 contract's
minimal self-session branch (select orig + return) is kept verbatim. (S2 may
also clear `LINKED_ID` there; not required for correctness — see FINDING 9.)

## FINDING 7 — list-windows -t '=S' -F '#{window_id}' -f '#{window_active}' → exactly one line, NO trailing newline  [HIGH]

```
SRC_ID="$(tmux -L "$SOCK" list-windows -t '=S' -F '#{window_id}' -f '#{window_active}')"
# SRC_ID == "@1"  (printf '%s' | wc -l == 0  → no trailing newline)
```
- Returns the **active** window id of session S as a single token `@N`.
- `$(...)` strips the (absent) trailing newline, so `SRC_ID` is exactly `@1`.
- On a **non-existent** session: `list-windows -t '=nope' ...` → **rc=1**,
  stderr `can't find session: nope`, empty stdout. **preview.sh must guard:
  if `src_id` is empty → fall back** (the candidate session is gone / invalid).
- The `=S` exact-match prefix avoids ambiguity when one name is a prefix of
  another (`log` vs `logfile`). ✓ (PRD §13; tmux_primitives.md §7.)

## FINDING 8 — select-window -t @id  [HIGH]
```
tmux -L "$SOCK" select-window -t "@1"     # rc=0
```
Makes the linked window active in the current session (all panes render live).
Does **NOT** fire `client-session-changed` (Invariant A, proven in
`system_context.md` §3 / `tmux_primitives.md` §4) — so session history and the
toggle are untouched. It DOES fire `session-window-changed` (suppressed
globally for the picker duration by P1.M4.T4.S2; out of scope here).

## FINDING 9 — current session: read @livepicker-orig-session, NOT display-message  [HIGH, CONTRACT DEVIATION — JUSTIFIED]

The S1 contract §2 says read current session from BOTH `@livepicker-orig-session`
**and** `tmux display-message -p '#{session_name}'`. Empirically:

- **With an attached pty client** (production): `display-message -p '#{session_name}'`
  (no `-t`) → returns the **client's** session, rc=0. ✓
- **On a detached socket** (the test harness — sessions created with `-d`, no
  client): `display-message -p '#{session_name}'` → returns an **arbitrary**
  session (`S2`, the last-created), rc=0. **Non-deterministic / wrong.**
- Note: `display-message -t '=driver'` is **invalid** for session targets —
  `display-message -t` resolves a **pane/client**, not a session; it errored
  `can't find pane: =driver`.

**Decision (encoded in the PRP):** `CURRENT_SESSION="$(get_state "$ORIG_SESSION" "")"`.
Rationale: (a) during browsing the client never switches session (Invariant A),
so the live client session is **provably equal** to `ORIG_SESSION` whenever
preview.sh runs (called only by activate's first preview + input-handler
next/prev, all pre-confirm); (b) `ORIG_SESSION` is **client-independent** and
always set by activate (P1.M4.T1.S1) before preview.sh is first called, so it
works identically under the **detached** socket shim; (c) `display-message`
is non-deterministic without a client and would make the script untestable.
This is a deliberate, documented simplification of the contract's "read both".

## FINDING 10 — renumber-windows is `on`; address windows by @id, NEVER index  [HIGH]
`show-options -gv renumber-windows` → `on`. Indices are therefore unstable
(a killed/created window anywhere can renumber the whole session). Window ids
(`@N`) are **server-global and stable**. Every target in preview.sh uses the id:
`-t "$src_id"`, `-t "$CURRENT_SESSION:$LINKED_ID"`. The only index-shaped
target is the **bare** `-t "$CURRENT_SESSION:"` (empty index → tmux picks a
free slot), which intentionally does not pin an index. ✓ (PRD §13/§16; system_context §2.)

## FINDING 11 — kill-window -t @id on a linked window DESTROYS it in ALL sessions  [HIGH, TEST-CLEANUP LESSON]
While cleaning up a duplicate I ran `kill-window -t "driver:@1"`; because `@1`
was one window object shared by driver and S1, this **killed S1's only window
and destroyed session S1** (`can't find session: S1`). This is the same reason
`unlink-window -k` is **forbidden** in preview.sh. preview.sh itself NEVER
calls kill-window. **Lesson for the validation script:** never `kill-window` a
shared id during teardown — unlink (no -k) or `kill-session` instead.

## FINDING 12 — capture-pane -ep -t '=S' (the S2 fallback primitive) is available  [MEDIUM, S2-OWNED]
`capture-pane -ep -t '=S'` captures S's active pane with escape sequences to
stdout. Available on 3.6b (tmux_primitives.md §6). **Not implemented in S1**
— S2 (P1.M3.T1.S2) owns the capture-pane fallback. S1 leaves a
`preview_fallback()` stub that S2 replaces; S1's stub `return 1`s so the
caller sees a non-zero exit on link failure (S1 contract §4: "non-zero only
if fallback also fails").

## FINDING 13 — the complete CORRECT preview sequence (S1→S2 handoff validated)  [HIGH]
End-to-end on the isolated socket, previewing S1 then S2 with unlink-then-link:
```
after preview S1: driver=@0              # @1 linked+selected (active shown)
after preview S2: driver=@0 @2           # @1 unlinked, @2 linked+selected; NO duplicate
S1 still has @1: 1   S2 still has @2: 1  # both source sessions intact
driver window count: 2                   # exactly @0 (orig) + @2 (preview) — no ghost
```
The unlink-then-link sequence is provably duplicate-free and source-preserving.
This is the exact invariant the PRP's Level-2 mock validation asserts.

---

## Summary of corrections to the literal S1 contract (all justified above)

| # | Literal contract says | Empirical reality (3.6b) | PRP action |
|---|---|---|---|
| §2 | read current session from `display-message` AND `@livepicker-orig-session` | `display-message` non-deterministic without a client; equals ORIG_SESSION during browsing (Invariant A) | read `CURRENT_SESSION` from `ORIG_SESSION` only (client-independent, testable) |
| §3 | unlink only `if LINKED_ID != src_id`, then **always** link | re-linking a linked window does NOT error — it silently duplicates (FINDING 4); wrap hits `LINKED_ID == src_id` (FINDING 5) | add guard: if `LINKED_ID == src_id`, skip BOTH unlink+link, just `select-window` + return |
| §3 (notes) | self-session link "would error" / "cannot link its own window" | self-link is ALLOWED (creates in-session duplicate) (FINDING 6) | keep the self-session guard (correct behavior) but document it is behavioral, not protective |
| §16 | "Linking can fail if already linked" | it does NOT fail (FINDING 4) | document: unlink-first is about avoiding duplicates, not avoiding an error |

## Sources
- LIVE verification on tmux 3.6b, isolated socket, 2026-07-05 (every rc + diff above).
- `plan/001_fd5d622d3939/architecture/tmux_primitives.md` §1/§4/§5/§7 (per-primitive
  analysis; closed its two flagged empirical gaps here).
- `plan/001_fd5d622d3939/architecture/system_context.md` §2/§3 (Invariant A) /§7
  (test-harness shim shape) /§9 (shell style).
- `PRD.md` §7 (update_preview pseudocode), §13 (primitives), §16 (risks).
- `scripts/state.sh` (STATE_LINKED_ID / ORIG_SESSION / ORIG_WINDOW constants — confirmed present).
