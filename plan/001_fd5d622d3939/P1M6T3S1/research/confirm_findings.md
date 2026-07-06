# Research: input-handler.sh `confirm` (P1.M6.T3.S1)

Empirically verified live on 2026-07-06 against `/usr/bin/tmux` (3.6b) on
**isolated sockets** (`tmux -L lp-t3-verify-$$` / `lp-t3b-$$` / `lp-t3c-$$`,
each `kill-server`'d on exit, each with an attached client via `script -qec`).
Every `rc` / output below was observed. This file is the ground-truth that makes
the confirm branch safe: the single most consequential finding (FINDING 1/2)
proved a naive order would **destroy the chosen session**.

## The work-item crux (restated)

T3.S1 fills the `confirm)` seam in `scripts/input-handler.sh` (left as
`return 0` by P1.M6.T1.S1; the backspace/next/prev seams are filled by the
parallel sibling P1.M6.T2.S1 — assume COMPLETE per the parallel-execution
contract). CONTRACT (work-item §3), PRD §6 Confirm + §9 + §14 + §15.22:

- Compute the filtered list; `target = filtered[index]` if non-empty.
- target present, type==session  → `switch-client -t "=target"` (the ONE switch).
- target present, type==window   → `select-window -t "session:window"` (no switch, no creation).
- empty, session, create==on     → `new-session -d -s "$query"`; success → `switch-client -t "=$query"`; fail → cancel.
- empty otherwise                 → restore cancel.
- After a SUCCESSFUL resolve/create → `restore.sh keep` (tears down picker, LEAVES client on target).
- OUTPUT: client on chosen target with EXACTLY ONE session switch; picker torn down by restore keep.

## Findings

### FINDING 1 — [CATASTROPHIC] switch-client BEFORE restore's STEP-1 unlink DESTROYS the target session  [VERIFIED]

This is the highest-consequence finding in the whole task. `restore.sh` (COMPLETE,
P1.M5) runs its STEP-1 unlink **unconditionally** on `current_session` (the live
client session, via `display-message -p '#{session_name}'`):

```bash
# restore.sh STEP 1 (immutable; this task MUST NOT touch restore.sh)
linked_id="$(get_state "$STATE_LINKED_ID" "")"
if [ -n "$linked_id" ]; then
    current_session="$(tmux display-message -p '#{session_name}' 2>/dev/null || true)"
    [ -n "$current_session" ] || current_session="$(get_state "$ORIG_SESSION" "")"
    tmux unlink-window -t "$current_session:$linked_id" 2>/dev/null || true
fi
```

During browsing, `preview.sh` linked the candidate's window (`linked_id`) into
the **DRIVER** (ORIG_SESSION), NOT into the candidate. So the link lives in the
driver. After confirm issues `switch-client -t "=target"`, the client is in the
target, so `current_session == target`, and restore STEP-1 becomes
`unlink-window -t "target:$linked_id"` — which removes the link to the window
**in the target session** (the window's origin). Verified live (SCENARIO TEST A):

```
driver(attached,@0) + beta(@1); preview: link-window -a -s @1 -t driver:  -> driver has @0,@1 ; beta has @1
switch-client -t "=beta"            -> current_session = beta
unlink-window -t "beta:@1"          -> beta nwindows=0  "can't find session: beta"   <<< TARGET DESTROYED
```

`beta` lost its only window and was torn down. **This is the exact failure a naive
"switch then restore keep" produces.** It is silent in production too (restore's
`|| true` swallows the rc) — the user would see the chosen session VANISH.

### FINDING 2 — [LOAD-BEARING FIX] confirm MUST unlink the driver preview BEFORE switch-client  [VERIFIED]

The correct order: confirm itself unlinks the preview from ORIG_SESSION (the
driver — where the link actually is) BEFORE issuing switch-client. Then restore
keep's STEP-1 redundant unlink targets `target:$linked_id` and FAILS harmlessly
(singly-linked origin window → rc=1, swallowed). Verified live (SCENARIO TEST B):

```
preview link @1 into driver ; driver has @0,@1 ; beta has @1
unlink-window -t "driver:@1"          -> driver nwindows=1 (preview cleaned) ; beta nwindows=1 (intact)
switch-client -t "=beta"             -> current_session = beta
restore STEP-1 redundant: unlink-window -t "beta:@1"  -> "window only linked to one session" rc=1 (HARMLESS)
RESULT: driver cleaned (1 win), beta intact (1 win @1), client in beta.  ✓ CORRECT
```

The unlink target is `"$ORIG_SESSION:$linked_id"` — the driver name + the global
window @id. `ORIG_SESSION` is read via `get_state` (client-independent, deterministic).
This is robust against the **backspace-mismatch** case too: backspace (T2.S1) does
NOT call preview, so after a backspace the highlight (target) can differ from the
session `linked_id` last previewed. Unlinking `ORIG_SESSION:$linked_id` ALWAYS hits
the real link location (the driver), regardless of which session is highlighted, so
the driver is always cleaned. (If `linked_id` is empty — self-session was last
previewed, or preview never ran — the guard `[ -n "$linked_id" ]` skips; nothing to clean.)

### FINDING 3 — the driver-preview unlink is ONLY needed when confirm switches the client  [VERIFIED by reasoning + TEST C]

`restore.sh` STEP-1 unlinks from `current_session`. That is correct IFF
`current_session == driver` (no switch happened). So:
- **session mode (switch happens):** confirm MUST do the driver unlink itself (FINDING 2).
- **window mode (NO switch-client):** `current_session` stays == driver, so restore
  STEP-1 correctly unlinks `driver:$linked_id`. confirm does NOT need to unlink.
- **cancel paths (no switch):** same — restore cancel runs with `current_session == driver`.

Net rule: **any branch that issues `switch-client` must unlink `ORIG_SESSION:$linked_id`
first.** Any branch that does NOT switch leaves cleanup to restore (correct).

`restore.sh` STEP-2 (`select-window -t "$ORIG_WINDOW"`) was also verified (TEST C):
after a session-mode switch it operates on the background DRIVER session (selects
ORIG_WINDOW there) and does NOT disturb the target — rc=0, target's active window
unchanged. **Harmless in session mode.** (See FINDING 8 for the window-mode caveat.)

### FINDING 4 — new-session SANITIZES characters and returns rc=0 with a DIFFERENT name  [VERIFIED — robustness crux]

`tmux new-session -d -s "$query"` on 3.6b does NOT reject special chars — it
SILENTLY SANITIZES them and returns rc=0, but the resulting session name differs
from `$query`:

```
q=".hidden"    -> created rc=0 ; actual session "_hidden"   (leading . -> _)
q="has:colon"  -> created rc=0 ; actual session "has_colon" ( : -> _ )
q="tab\there"  -> created rc=0 ; actual session "tab\\there" (tab escaped)
q="with space" -> created rc=0 ; actual "with space"        (spaces KEPT)
q="valid"      -> created rc=0 ; actual "valid"
q=""           -> FAILED rc=1
q="dup" (exists) -> FAILED rc=1
```

**Consequence:** checking ONLY new-session's rc is INSUFFICIENT. If the user types
`.hidden`, new-session rc=0 → the literal contract ("if it succeeded, switch to
=$query") would do `switch-client -t "=.hidden"` → rc=1 (no such session; it is
"_hidden") → the client does NOT switch, silently stranded in the driver, and
restore keep tears down around it. This is a realistic input (`.`, `:` appear in
project names), so the PRP MUST use the robust gate.

### FINDING 5 — [LOAD-BEARING] the robust create gate: `new-session && has-session -t "=$query"`  [VERIFIED]

```
new-session -d -s "$query" && has-session -t "=$query"
  -> BOTH rc=0  IFF the EXACT "$query" name now exists (valid, un-sanitized)  -> switch to "=$query" is safe
  -> else (rc!=0 from new-session: empty ; OR has-session rc!=0: sanitized name) -> CANCEL
```

Verified: query "proj:two" → new-session rc=0 BUT `has-session -t "=proj:two"` rc=1
(actual "proj_two") → the `&&` is FALSE → cancel. query "clean123" → new-session rc=0
AND has-session rc=0 → switch to "=clean123" rc=0, client lands there. The gate is
contract-faithful ("if it failed [to produce the exact name], cancel") AND closes
the sanitization hole. `switch-client` itself is ALSO guarded `2>/dev/null || true`
(belt-and-braces; FINDING 8). **The duplicate-name case cannot occur in the create
branch**: the list is all sessions filtered case-insensitively by `$query`; if a
session with the exact `$query` name existed it would be a case-insensitive match →
in the filtered list → the list would NOT be empty → the create branch is never
reached. So `&&`-short-circuit on a duplicate is moot here.

### FINDING 6 — window-mode target format is `session_name:window_index`  [VERIFIED via livepicker.sh:93]

`scripts/livepicker.sh` (activate T2.S1, COMPLETE) builds the window-mode list as:
```bash
list="$(tmux list-windows -a -F '#{session_name}:#{window_index}' 2>/dev/null)"
```
So a window-mode `target` is already a full `session:window_index` specifier (e.g.
`beta:1`). The work-item "parse 'session:window' from target" is satisfied by
passing the WHOLE token straight to `select-window -t "session:window_index"`
(tmux accepts `session:window` where window is an index). **No parsing/splitting
needed** — `target` is already the correct `select-window` argument. select-window
does NOT create a window (verified: rc=0, window count unchanged) and does NOT
switch the client's session (it only changes the named session's active window).

### FINDING 7 — client-session-changed fires on EVERY switch (incl. same-session); the engine DEDUPS  [VERIFIED]

Mirrors restore_keep_cancel FINDING A. switch to a DIFFERENT session → hook fires
(1 navigation recorded). switch to the SAME session → hook STILL fires, but the
real `tmux-session-history` `do_hook` short-circuits on `[ "$to" = "$CURRENT" ] &&
return` → 0 net entries. So:
- confirm on a target != current session → exactly **1** history entry (browser-like;
  forward collapses, target appended at tip — same as a sessionx jump). ✓ PRD §14.
- confirm on a target == current session (e.g. the user's own driver is the only
  match) → **0** entries (you're already there). Correct, no special-case needed.

The MOCKING "one history entry" assertion (cluster a) therefore REQUIRES a smart
deduping recorder (record only when `to != last`), NOT a naive event counter — a
naive counter would also count the same-session dedup and false-pass/fail. See
restore_keep_cancel FINDING B for the exact recorder wire.

### FINDING 8 — exact-match `=` prefix; rc=1 on a missing session; STEP-2 caveat in window mode  [VERIFIED]

- `switch-client -t "=S"` is exact-match (disambiguates `drive` vs `driver`);
  rc=1 "can't find session" on a missing name → guard `2>/dev/null || true`
  (house style; a vanished session must not abort the teardown).
- `select-window -t "session:window_index"` (window mode) does NOT create a window
  and does NOT switch the client. **Caveat (known MVP limitation, OUT of MOCKING
  scope):** in window mode there is NO switch-client, so `current_session == driver`
  when restore keep runs, and restore STEP-2 `select-window -t "$ORIG_WINDOW"`
  re-selects the driver's ORIGINAL window — undoing confirm's `select-window -t
  "target"`. So a window-mode confirm tears down to ORIG_WINDOW rather than landing
  on the picked window. restore.sh is immutable (P1.M5 COMPLETE); this task does NOT
  fix it (the work-item MOCKING for window mode asserts ONLY "no creation"). The PRP
  implements the literal contract (`select-window -t "target"` + restore keep) and
  documents this interaction as a known gotcha. (Session mode is unaffected: after a
  switch, STEP-2 operates on the background driver and leaves the target alone.)

### FINDING 9 — caller contract: confirm takes argv[1] ONLY (no char)  [VERIFIED via livepicker.sh bind block]

activate T4.S1 (COMPLETE) bound the confirm key (from `opt_confirm_keys`, default
`Enter`) VERBATIM as:
```
tmux bind-key -T livepicker "$k" run-shell "$CURRENT_DIR/input-handler.sh confirm"
```
So argv is JUST `confirm` — NO `$2`. Under `set -u` the confirm branch MUST NOT
reference `$2` (it is unset → would crash). Mirror the nav/backspace branches (T2
FINDING 1). The `type` branch is the only one that reads `$2` as `char`.

### FINDING 10 — MOCKING design (5 clusters) + the pollution canary  [VERIFIED shape]

The work-item §5 clusters, mapped to assertions over an isolated socket with an
attached client + a deduping `client-session-changed` recorder (FINDING 7) + a
check that the driver retains NO leftover linked window after confirm (FINDING 2):
- (a) match lands on target + exactly **1** history entry; driver cleaned of preview.
- (b) empty + session + create==on + VALID name → session created (has-session) AND
      client active there; **1** history entry; driver cleaned.
- (c) empty + create==off → NO new session; restore cancel; client back on driver;
      **0** history entries.
- (d) window mode (type=window) → ZERO new-session calls; select-window issues;
      no creation (count sessions before/after).
- (e) sanitized/invalid name (e.g. query `proj:two`, or empty) → cancel; client
      stays on driver; **0** entries; the `&& has-session` gate caught it.

The canary: a `set-hook -g client-session-changed` smart recorder that appends
`#{session_name}` to a log ONLY when it differs from the last-seen name; assert the
log length matches the expected (1 for a/b, 0 for c/e). AND assert
`list-windows -t driver` has no window whose `@id == linked_id` after a session-mode
confirm (the driver-preview leak that FINDING 1 would otherwise cause).

## Sources

- Empirical: isolated-socket scripts run 2026-07-06 on tmux 3.6b (3 verify scripts:
  confirm-flow pollution/damage TEST A vs B; new-session validity + has-session gate;
  switch-client exact-match + same-session dedup).
- `scripts/restore.sh` (COMPLETE P1.M5) — STEP-1 unlink-on-current-session (the
  FINDING 1 hazard), STEP-2 select ORIG_WINDOW, STEP-3 keep/cancel branch.
- `scripts/preview.sh` (COMPLETE P1.M3) — link direction `-s src_id -t driver:` and
  the `@livepicker-linked-id` semantics confirm's cleanup relies on.
- `scripts/livepicker.sh:93` — window-mode list format `#{session_name}:#{window_index}`.
- `scripts/options.sh` — `opt_type()` (default `session`), `opt_create()` (default `on`).
- `scripts/state.sh` — `STATE_LINKED_ID`, `ORIG_SESSION`, `STATE_LIST/FILTER/INDEX`,
  `get_state`/`set_state`.
- `plan/001_fd5d622d3939/P1M5T2S1/research/restore_keep_cancel_findings.md` FINDING
  A/B/E (same-session dedup, smart recorder, get_state for ORIG_SESSION).
- `plan/001_fd5d622d3939/architecture/system_context.md` §3 (Invariant A), §6
  (session-history composition/dedup), §9 (shell style).
- `PRD.md` §6 Confirm, §9, §13, §14, §15.22 (Create-on-enter).
