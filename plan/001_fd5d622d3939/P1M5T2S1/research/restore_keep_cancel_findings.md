# Research: restore.sh keep/cancel client branch (P1.M5.T2.S1)

Empirically verified live on 2026-07-05 against `/usr/bin/tmux` (3.6b) on
**isolated sockets** (`tmux -L lp-t2-verify-$$` / `lp-t2-e2e2-$$` / `lp-t2-conf-$$`,
each `kill-server`'d on exit). All commands below were run; the `expect` values
are the observed rc / output. The real `tmux-session-history` engine source was
also read in full (`~/.config/tmux/plugins/tmux-session-history/scripts/session_history.sh`)
to confirm the dedup semantics that make the cancel path pollution-safe.

## The work-item crux (restated)

T2.S1 fills the T2 seam in `scripts/restore.sh` (created by P1.M5.T1.S1):
- `argv[1] == "cancel"` → `tmux switch-client -t "=$ORIG_SESSION"` (exact-match).
- `argv[1] == "keep"`   → do nothing (confirm P1.M6.T3.S1 already did the ONE switch).

The pollution invariant (PRD §14): **cancel → 0 history entries; confirm → exactly 1**.
This research PROVES why that invariant holds and pins down the ONE subtlety that
makes the work-item MOCKING instruction correct (and a naive recorder WRONG).

## Findings

### FINDING A — `switch-client -t "=S"` to the session the client is ALREADY in DOES fire `client-session-changed`  [VERIFIED — LOAD-BEARING]

This is the highest-consequence finding. A client was attached to session `ORIG`.
A naive counter was wired to `client-session-changed` (`run-shell 'printf x >> log'`).
Then:

```
switch-client -t "=ORIG"   (client ALREADY in ORIG)   ->  naive log: 1 byte   (hook FIRED)
switch-client -t "=ORIG"   (same session again)       ->  naive log: 2 bytes  (hook FIRED AGAIN)
```

**Conclusion:** tmux fires `client-session-changed` on a same-session `switch-client`
— it does NOT suppress the hook when the target equals the current session. So the
cancel path's `switch-client -t "=ORIG_SESSION"` (where the client never left
ORIG during browse) **does** fire the hook. A naive recorder that counts every
`client-session-changed` event would record **1** for cancel and FALSE-FAIL the
work-item's "cancel → 0 entries" assertion.

**Why the invariant still holds:** the real `tmux-session-history` engine DEDUPS.
Read the engine source (`session_history.sh`, `do_hook`) — the very first check:

```bash
do_hook() {
    local to="$1" from i
    [ -z "$to" ] && to="$(attached_session)"; [ -z "$to" ] && return
    if [ -z "$CURRENT" ]; then HIST=("$to"); IDX=0; CURRENT="$to"; PREV="$to"; ...; return; fi
    [ "$to" = "$CURRENT" ] && { S "$(H walk)" ""; return; }   # <<< SAME-SESSION SHORT-CIRCUIT
    ...navigation branch (append + dedup, collapse forward)...
}
```

When `to == CURRENT` the engine clears the walk flag and **returns without touching
the timeline**. During browse the client never left ORIG (Invariant A), so
`@session-history-current` is still ORIG; the cancel switch fires the hook with
`to == ORIG == CURRENT` → short-circuit → **zero net history entries**. ✓

This is the definitive proof of PRD §14 "Cancel: zero `switch-client` to a different
session. History and toggle are exactly as before activation." The hook DOES fire;
the engine treats a same-session event as a no-op.

### FINDING B — the work-item MOCKING recorder MUST dedup (mirror the engine)  [VERIFIED — TESTABILITY CRUX]

Because of FINDING A, the T2.S1 mock's "fake history recorder on client-session-changed"
CANNOT be a naive event counter. It MUST replicate the engine's same-session
short-circuit. Verified end-to-end with a smart recorder (`$1 = #{session_name}`;
record only when `to != last`):

```
CANCEL  path: browse(link+select) smart=0 naive=0 ; switch-client -t =ORIG -> smart=0 naive=1   ✓ (0 entries)
CONFIRM path: browse(link+select) smart=0 naive=0 ; switch-client -t =chosen -> smart=1 naive=1  ✓ (1 entry)
KEEP    after confirm: no switch -> smart stays 1                                               ✓ (0 additional)
```

The smart recorder recorded **0** for cancel (deduped the same-session event) and
**1** for confirm (a genuine navigation). The naive counter recorded 1 for the
cancel switch — proving a naive recorder FALSE-FAILS cancel. **The mock recorder
must be the deduping kind.** Reference shape (passes `#{session_name}` exactly like
the real plugin's hook wire):

```bash
# Wired EXACTLY like the real engine (session_history.tmux:22):
tmux set-hook -g client-session-changed "run-shell '$REC \"#{session_name}\"'"
# $REC records ONLY when $1 != last-seen (mirrors do_hook's [ "$to" = "$CURRENT" ] && return)
```

### FINDING C — exact-match `=` prefix disambiguates; rc=1 on a missing session  [VERIFIED]

```
sessions: driver, driver2, drive          # 'drive' is a PREFIX of 'driver'
switch-client -t "=drive"   -> client lands in 'drive' (NOT 'driver')   rc=0   ✓ exact-match
switch-client -t "=nope"    -> "can't find session: nope"              rc=1   ✗ must ignore
```

**Conclusion:** `"=$ORIG_SESSION"` is the correct exact-match target (PRD §13,
`tmux_primitives.md §7`). It avoids prefix-collision (e.g. a session `log` vs
`logfile`). If `ORIG_SESSION` has vanished by restore time (session killed during
browse), `switch-client` returns rc=1 → **append `2>/dev/null || true`** (house
style; a transient failure must not abort a half-restored teardown —
`system_context §9`; same idiom T1.S1 uses on unlink/select).

### FINDING D — keep is a true no-op; confirm owns the ONE switch  [VERIFIED by reading the contract + engine]

T2.S1's `keep` branch does NOTHING. The ONE `switch-client` to the chosen target
is issued by `input-handler.sh confirm` (P1.M6.T3.S1 — PLANNED) BEFORE
`restore.sh keep` runs. The work-item RESEARCH NOTE is explicit: "keep does NOT
switch here because confirm already issued the ONE switch-client to the chosen
target." Verified the engine treats that single switch as one navigation
(FINDING B's confirm run: smart=1). restore.sh keep must not issue a second
switch (a second switch would be a SECOND navigation, polluting history —
"keep → 1" in the work-item OUTPUT counts the confirm switch, not a restore switch).

### FINDING E — read ORIG_SESSION via `get_state`, NOT `display-message`  [VERIFIED — consistency with T1.S1 FINDING 4]

T1.S1's FINDING 4 established `tmux display-message -p '#{session_name}'` is
**non-deterministic when no client is attached** (returned an arbitrary session).
For the SWITCH TARGET, the robust client-independent source is the saved option
`@livepicker-orig-session` via `get_state "$ORIG_SESSION" ""` (the same accessor
T1.S1 uses for its fallback). This is deterministic and equals the attached
`display-message` value in production (a client is attached at restore time).
T2.S1 uses `get_state "$ORIG_SESSION" ""` directly — no `display-message` needed.

### FINDING F — `"$1"` under `set -u` must be defaulted; restore_main locals must be extended  [VERIFIED via restore.sh read + state.sh read]

`restore.sh` runs under `set -u` (house style). T1.S1's `restore_main` declares
`local linked_id orig_window current_session` and does NOT yet read `"$1"`. T2.S1:
- adds `orig_session` and `mode` to the `local` line;
- reads the arg as `mode="${1:-}"` (the `${1:-}` default prevents a `set -u` crash
  if `restore.sh` is ever invoked bare — defensive; in production `input-handler.sh`
  always passes `keep`|`cancel`).
- `ORIG_SESSION` is the readonly constant `"@livepicker-orig-session"` from
  `state.sh` (already sourced by restore.sh's trio).

### FINDING G — the T2 seam is an in-place replacement of a comment block  [VERIFIED via restore.sh read]

T1.S1 left this exact seam in `scripts/restore.sh` (between STEP 2 and `return 0`):

```bash
	# --- T2 (P1.M5.T2.S1): keep/cancel client branch (insert here) ---
	# PRD §9 restore step 3: if argv[1]=='cancel', switch-client -t "$ORIG_SESSION"
	# (return to the original session); if 'keep', do NOT switch (stay on the
	# chosen target). Reads "$1" and get_state "$ORIG_SESSION" "".
```

T2.S1 REPLACES that comment block with the real branch. It must NOT touch STEP 1
(unlink), STEP 2 (select-window), the T3 seam, the T4 seam, the `local` line
(EXCEPT extending it), or the driver. T2.S1 is a single, surgical edit.

## Sources

- Empirical: the isolated-socket scripts run 2026-07-05 on tmux 3.6b (cancel/confirm
  smart+naive recorder runs; exact-match disambiguation; same-session hook-fire proof;
  rc=1 on missing session).
- `~/.config/tmux/plugins/tmux-session-history/scripts/session_history.sh` — the real
  engine's `do_hook` (the `[ "$to" = "$CURRENT" ] && return` short-circuit is the
  load-bearing line proving cancel→0).
- `~/.config/tmux/plugins/tmux-session-history/session_history.tmux:22` — the exact
  hook wire `run-shell 'SCRIPT hook "#{session_name}"'` (the mock recorder copies this).
- `plan/001_fd5d622d3939/architecture/system_context.md §3` (Invariant A), `§6`
  (session-history composition + dedup), `§9` (shell style).
- `plan/001_fd5d622d3939/architecture/tmux_primitives.md §4` (client-session-changed
  fires on switch-client), `§7` (`=` exact-match).
- `scripts/restore.sh` (the host file T1.S1 created — the T2 seam location).
- `scripts/state.sh` (ORIG_SESSION readonly const + get_state accessor).
- `PRD.md §9` (restore step 3), `§13` (switch-client -t '=S'), `§14` (pollution proof).
