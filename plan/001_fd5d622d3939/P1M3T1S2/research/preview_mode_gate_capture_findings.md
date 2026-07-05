# Research: preview.sh mode gate + capture-pane fallback + self-session (P1.M3.T1.S2)

> **Methodology:** all findings verified LIVE on an **isolated tmux socket**
> (`tmux -L lp-s2-*`) against **tmux 3.6b**, **bash 5.3.15**, **shellcheck 0.11.0**
> on 2026-07-05. Every rc and grep count below is real output. S2 EXTENDS the
> existing `scripts/preview.sh` (delivered COMPLETE by P1.M3.T1.S1 — see that
> file and its `preview_fallback()` stub + the marked mode-gate extension point).

S2 makes exactly THREE edits in place to `scripts/preview.sh`:
1. Replace the `preview_fallback()` stub with the real `capture-pane` snapshot.
2. Insert the `@livepicker-preview-mode` (live|snapshot|off) gate at the marked spot.
3. Refine the self-session branch to unlink any prior preview + clear `STATE_LINKED_ID`.

---

## FINDING A — ⚠️ CRITICAL: `capture-pane -ep -t "=$S"` FAILS (rc=1). The PRD/work-item target syntax is WRONG. Use `-t "=$S:."`.  [CONTRACT-CORRECTING]

The PRD §7 Fallbacks AND the S2 work-item contract both literally specify
`tmux capture-pane -ep -t "=$S"`. **Verified on 3.6b this FAILS:**

```
$ tmux capture-pane -ep -t "=myproj"
can't find pane: =myproj
rc=1
```

**Why:** `capture-pane`'s `-t` expects a **PANE** target. The `=` exact-match
prefix is a **session/window NAME** matcher; when applied to a bare session it
is interpreted as a pane spec (panes have no names), so tmux reports
`can't find pane: =S`. The `=` prefix that is CORRECT for `list-windows`
(FINDING 7 in S1 research) and `switch-client` (PRD §13) is **wrong** for
`capture-pane`. The `tmux_primitives.md §6` researcher flagged this as a gap
("no shell access"); the live proof closes it: **the `=` prefix must be
followed by an explicit pane/window resolution suffix**.

**Correct target variants (all verified rc=0, content captured):**

| Target               | rc  | exact-match? | captures            | notes |
|----------------------|-----|--------------|---------------------|-------|
| `=$S`   (PRD spec)   | **1** | —          | —                   | FAILS — "can't find pane: =S". NEVER USE. |
| `$S`                 | 0   | ✗ prefix-match | active pane       | AMBIGUOUS — see FINDING B. |
| `$S:.`               | 0   | ✗            | active pane         | works, no exact-match. |
| `$S:`                | 0   | ✗            | active window       | works, no exact-match. |
| `=$S:.`  ← CHOSEN    | 0   | ✓ exact      | active pane         | **exact-match + pane-resolvable. BEST.** |
| `%N` (explicit pane) | 0   | —            | that pane            | needs an extra list-panes call; overkill. |

**Decision (encoded in the PRP):** `tmux capture-pane -ep -t "=$S:."`.
- `=` → exact session-name match (consistent with the rest of preview.sh; safe
  against prefix collisions).
- `:.` → tmux's "active pane of the session's active window" resolution
  (the `.` token = active pane; mirrors `list-panes -f '#{pane_active}'`).
- This preserves the EXACT-MATCH invariant the whole file relies on (session
  names can be prefixes of each other) while satisfying capture-pane's
  pane-target requirement.

This is a **justified correction** to the literal S2 contract item 3 (which
copies PRD §7's `-t "=$S"` verbatim). It is the S2 analog of S1's FINDING 4/5
duplicate-guard correction: the literal spec is empirically wrong on 3.6b.

---

## FINDING B — bare `$S` (no `=`) is AMBIGUOUS: prefix-name collision. Exact-match `=...` is REQUIRED.  [HIGH]

Sessions `log` and `logfile` both exist. Bare session target resolves by
**unique-prefix**:

```
capture-pane -ep -t "log"   → captured IN_LOGFILE_LONG (matched 'logfile'!)   rc=0
capture-pane -ep -t "=log:."  → captured IN_LOG_SHORT (exact)                rc=0
capture-pane -ep -t "=logfile:." → captured IN_LOGFILE_LONG (exact)          rc=0
```

**Implication:** dropping the `=` (the "just use `$S`" temptation after seeing
FINDING A) reintroduces target ambiguity — previewing `log` would snapshot
`logfile`. The exact-match `=` prefix is load-bearing for correctness, so the
fix is `=$S:.` (keep the `=`, add the `:.`), NOT bare `$S`.

---

## FINDING C — gone session: `=$S:.` returns rc=1 (the fallback signal is preserved)  [HIGH]

```
capture-pane -ep -t "=nope:."   → rc=1   (session gone)
```

This matches S1's gone-session behavior for `list-windows` (FINDING 7). So
`preview_fallback "$S"` returning capture-pane's exit code gives the caller
exactly the S1-contract-§4 semantics: **0 = fallback succeeded (captured);
non-zero = the candidate is truly gone**. The picker never *blocks* on either
(returning rc is not blocking), and a non-zero lets input-handler skip ahead.

---

## FINDING D — session names with spaces: `=$S:.` is safe when quoted  [HIGH]

```
capture-pane -ep -t "=job hunt:."   → rc=0, content captured   (session "job hunt")
```

As long as the expansion is double-quoted (`"$S"`), the space inside the name
is handled by tmux's exact-match resolution. (Reaffirms S1's "quote every
expansion" rule; "job hunt" is a real session name in the target environment.)

---

## FINDING E — clearing `STATE_LINKED_ID`: `tmux_unset_opt` (-gu) vs `set_state ""` (set empty)  [HIGH]

The self-session refinement must "clear `@livepicker-linked-id`". Two options:

```
tmux set-option -g "@livepicker-linked-id" ""     → show-options probe: still-present (rc=0)
tmux set-option -gu "@livepicker-linked-id"        → show-options probe: ABSENT (rc=1)
```

Both read back as `""` via `get_state "$STATE_LINKED_ID" ""` (tmux_get_opt
treats empty == unset for the default-fallback). So they are **functionally
equivalent** for restore (P1.M5.T1.S1 reads it and unlinks only if non-empty).

**Decision:** use **`tmux_unset_opt "$STATE_LINKED_ID"`** (the `-gu` path).
Rationale: (a) it is what `clear_all_state` in state.sh itself does
(`tmux set-option -gu "$k"`) — consistency with the teardown contract;
(b) it leaves the option genuinely absent (clean state) rather than
set-but-empty; (c) `tmux_unset_opt` is already available (sourced from
utils.sh). There is no `unset_state` accessor, so calling `tmux_unset_opt`
directly is the idiomatic clear path (state.sh's own teardown does the same).

---

## FINDING F — self-session refinement is SAFE: unlink prior + clear + select orig  [HIGH]

Simulated the self-session transition (live mode): a candidate window `@Swin`
was linked into `driver`; then previewing `driver` (self) must drop it:

```
driver windows before self unlink:  @1 @0       (@1 = the prior candidate preview; @0 = orig)
unlink-window -t "driver:@1" || true  → driver: @1   (prior preview dropped; rc=0)
S still has its window:              @0            (source kept it — FINDING 1/S1)
```

So the refined self-session sequence is provably correct:
1. if `linked_id` non-empty → `unlink-window -t "$current_session:$linked_id" 2>/dev/null || true`
   (drops the prior candidate from the driver; source keeps it; `|| true` for
   the singly-linked edge — S1 FINDING 2).
2. `tmux_unset_opt "$STATE_LINKED_ID"` (clear — FINDING E).
3. `select-window -t "$orig_window" 2>/dev/null || true` (show own session).
4. `return 0`.

**Why this is better than S1's minimal branch:** S1 left a stale `LINKED_ID`
in the self-session case (a prior candidate's window stayed linked-but-unselected
in the driver). S2 actively cleans it, so restore (P1.M5) sees an empty
`LINKED_ID` and does not try to unlink a window that is no longer the preview.
Self-healing either way, but S2 is tidier and matches the contract's
"Clear @livepicker-linked-id".

---

## FINDING G — mode gate ordering: off/snapshot BEFORE self-session; live falls through  [HIGH]

The three modes route at the S1-marked extension point (after reading inputs,
before the self-session guard):

```
mode="$(opt_preview_mode)"        # live | snapshot | off  (default live; options.sh)
if [ "$mode" = "off" ]:    return 0                          # show nothing; no state change
if [ "$mode" = "snapshot" ]: preview_fallback "$S"; return $?  # capture-pane; NEVER link
# live (default): fall through to the EXISTING S1 link flow below
```

- **off:** trivially correct — `@livepicker-preview-mode` is a config option
  constant for the picker's lifetime, so `off` means NO preview was ever linked
  (every nav call returns 0). `LINKED_ID` stays empty (activate set it empty);
  restore's empty-check skips unlink. No cleanup needed in this branch.
- **snapshot:** NEVER links (so `LINKED_ID` is never set by snapshot); capture
  is the whole job. Self-session needs no special handling in snapshot —
  capturing your own active pane is harmless (`=$S:.` resolves fine).
- **live:** falls through to S1's existing self-session guard (now refined per
  FINDING F), then src_id resolution, duplicate guard, unlink/link/select/track.

`opt_preview_mode` is defined in `scripts/options.sh` (P1.M1.T1.S1, COMPLETE)
and returns `live` by default — confirmed present (line `opt_preview_mode()`).

---

## FINDING H — preview_fallback returns capture-pane's rc (S1 contract §4 honored)  [HIGH]

S1's stub did `return 1` (so link-failure → exit non-zero). S2's real body:

```bash
preview_fallback() {
	local captured
	captured="$(tmux capture-pane -ep -t "=$1:." 2>/dev/null)" && return 0 || return 1
}
```

- Capture to a **local var** (discarded) — NOT bare stdout. Rationale: under
  `run-shell`, bare `capture-pane -ep` stdout (full of escape sequences) could
  be echoed into the status line / display-message area and corrupt the screen.
  Capturing into a var runs the command (verifying the pane is reachable +
  honoring "never blocks") without that side effect.
- Returns capture's rc: `0` if captured (FINDING A/C — real session rc=0, gone
  rc=1). This is exactly S1 contract §4 ("non-zero only if fallback also fails")
  and the S2 mock-test (b) requirement ("falls back to capture without error"
  — a real candidate session captures rc=0).
- The captured text is a **best-effort hint** (PRD §7 / work-item: "the picker
  area is the live client area"). There is no separate buffer to render
  captured text into without a link — that is precisely what `live` mode
  provides. So we capture (reachable-check + non-blocking) and discard; display
  is a documented limitation, not a bug. (A future snapshot renderer could store
  the text in a state key; out of scope for S2 — no consumer reads one yet.)

---

## Summary of corrections to the literal S2 work-item contract

| # | Contract says | Empirical reality (3.6b) | PRP action |
|---|---|---|---|
| §2/§3 | `capture-pane -ep -t "=$S"` | `=$S` FAILS rc=1 "can't find pane" (FINDING A) | use `-t "=$S:."` (exact session + active pane) |
| §3 | (bare `$S` would be the obvious fallback) | bare `$S` is prefix-ambiguous (FINDING B) | keep the `=` exact-match; add `:.` |
| §3 | self-session "Clear @livepicker-linked-id" | empty-string vs unset are equivalent for reads (FINDING E) | use `tmux_unset_opt` (-gu) — matches state.sh teardown |
| §3 | "still unlink any prior LINKED_ID first" | verified safe (FINDING F) | unlink (no -k, `|| true`) → unset → select orig |

## Sources
- LIVE verification on tmux 3.6b, isolated socket, 2026-07-05 (every rc + grep above).
- `scripts/preview.sh` (S1 deliverable — the stub + marked extension point S2 edits).
- `plan/001_fd5d622d3939/P1M3T1S1/research/preview_link_unlink_findings.md` (S1 FINDINGS 1-13; S2 reuses 1/2/7/9/10/11 unchanged).
- `plan/001_fd5d622d3939/architecture/tmux_primitives.md` §6 (capture-pane — its flagged gap closed live here).
- `scripts/options.sh` (`opt_preview_mode` — confirmed present, default `live`).
- `scripts/utils.sh` (`tmux_unset_opt` — the `-gu` clear path).
- `PRD.md` §7 (Fallbacks + Self-session edge case), §11 (`@livepicker-preview-mode`), §16 (risks).
