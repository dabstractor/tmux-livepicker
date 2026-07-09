# Research — P1.M3.T2.S1 (attempt 2/3): the deferred-preview supersession race fix

> Re-plan ground truth. Attempt 1 shipped the scroll wiring verbatim (commit 91fd8be)
> and deterministically broke `test_superseded_preview_noop`. This file documents the
> proven root cause and the verified fix (10/10 green runs this session). All claims
> were re-checked against the LANDED working tree and re-run on tmux 3.6b.

## 1. What attempt 1 shipped (already in input-handler.sh at HEAD)

Commit `91fd8be` "Wire scroll into input paths" added — and these STAY:
- `source "$CURRENT_DIR/layout.sh"` (after rank.sh).
- `_lp_scroll_into_view IDX RANKED` helper: `get_state STATE_CLIENT_WIDTH` +
  `get_state STATE_SCROLL` + `lp_viewport` + `set_state STATE_SCROLL`.
- 2 nav call sites (next/prev), placed BETWEEN `set_state INDEX` and `_lp_preview_follow`.
- 3 scroll=0 resets (type / backspace / cancel-clear) next to the `STATE_INDEX` reset.

All of the above PASSES Level 1 (bash -n, shellcheck, the grep success criteria) and is
CORRECT in isolation. The bug is TIMING, not logic.

## 2. The race (proven, not a flake) — the nav scroll reads break supersession

`test_superseded_preview_noop` fires two rapid `next-session` (defer=on): seq=1 -> alpha,
seq=2 -> beta. The stale alpha fire (seq=1) MUST no-op in `preview.sh` GUARD 2 (the
re-check before the first mutation — the unlink). It no-ops iff `STATE_PREVIEW_SEQ` has
advanced past 1 by the time alpha's fire reaches GUARD 2.

Mechanism: **every tmux round-trip pumps the server event loop**, which RUNS pending
`run-shell -b` jobs (alpha's fire). The scroll helper's 2 `get_state` reads sit on nav
#2's PRE-seq-bump path (the bump is in `_lp_fire_preview`, called last via
`_lp_preview_follow`). Those extra round-trips (a) advance alpha's fire toward GUARD 2
AND (b) delay nav #2's seq bump -> alpha reaches GUARD 2 while seq is still 1 -> it links
alpha -> "stale alpha fire leaked a stray link into the driver".

Attempt 1's empirical proof (clean tree + N synthetic `show-option` round-trips on nav):
0 extra = 6/6 pass; 1 = 5/6 (borderline); 2 = 0/6 (fail). A 20ms `sleep` (NO round-trip)
did NOT reproduce it -> it is the round-trips (server-loop advancement), not latency. The
nav pre-seq-bump path's tolerance is effectively ZERO extra round-trips.

Re-confirmed this session on HEAD: 3/3 runs FAIL `test_superseded_preview_noop`. The
attempt-1 mention of `test_orig_session_client_aware` failing was a load CASCADE — it runs
defer=off and never navs; it passes cleanly on HEAD (3/3).

## 3. The fix — invalidate EARLY, gated on defer=on (the in-scope, single-file fix)

Bump `STATE_PREVIEW_SEQ` as the FIRST operation of the nav branch, BEFORE any get_state /
scroll round-trip. After the bump persists, alpha's fire re-reads the seq at GUARD 2 and
no-ops regardless of how many round-trips the scroll math adds afterward. `_lp_fire_preview`
(called last) bumps AGAIN and captures the final seq for THIS nav's own fire — the early
bump is a pure invalidation signal (one "spent" seq number; the guards compare equality,
so gaps are harmless).

```bash
_lp_invalidate_pending_preview() {
	[ "$(opt_preview_defer)" = "on" ] || return 0
	local s
	s="$(get_state "$STATE_PREVIEW_SEQ" "0")"
	set_state "$STATE_PREVIEW_SEQ" "$(( s + 1 ))"
}
```
Called as the first line of BOTH `next-session)` and `prev-session)`.

### Why the defer=on gate (not unconditional)
- defer=off runs preview.sh INLINE (no `-b` job, no race) -> invalidation is pointless.
- Keeps defer=off nav byte-for-byte unchanged (zero risk to the ~40 defer=off tests; no
  seq mutation on the legacy synchronous path).
- The responsiveness seq assertions are all on the TYPE path (which we do NOT touch), so an
  unconditional bump would technically also pass — but the gate is strictly safer and
  self-documenting.

### Why this is safe (round-trip budget)
The early bump persists after 3 round-trips (opt_preview_defer + seq read + seq set).
Those 3 are the ONLY round-trips that execute while the stale fire can still leak; every
later round-trip (scroll reads, `_lp_fire_preview`) runs POST-invalidation. The clean
(defailing) nav path tolerates ~6 round-trips before the bump; 3 < 6, so the gated early
bump is strictly SAFER than the pre-task nav path. Verified: 10/10 green.

### Scope — this is ENTIRELY within input-handler.sh
`_lp_invalidate_pending_preview` uses only existing `get_state`/`set_state`/`opt_preview_defer`
APIs. `_lp_fire_preview` is UNCHANGED (it reads the current seq and increments, as before).
`preview.sh`'s 3 guards are UNCHANGED. `state.sh` is UNCHANGED. No other file is touched.
(Attempt 1's framing that this "touches preview.sh/state flow owned by other tasks" only
holds if `_lp_fire_preview` were refactored to skip its own bump — which is unnecessary with
the double-bump approach.)

## 4. Why NOT the other options attempt 1 floated
- (b) "renderer owns STATE_SCROLL, drop the nav write" — contradicts PRD §19 §3.32 and the
  task contract (input-handler is the authoritative scroll writer).
- (c) "widen test_superseded_preview_noop" — weakens a real correctness invariant; the test
  is correct (a stale fire MUST no-op). The early-bump fix lets us keep it strict.
- "combine the 2 reads into one `display-message -p` round-trip" — attempt 1 proved 1 extra
  round-trip is already borderline (5/6) on the PRE-bump path; does not fix the root cause.

## 5. Out of scope — latent TYPE-path supersession race (DO NOT fix here)
The type/backspace path also bumps the seq late (in `_lp_fire_preview`) after several
read/write round-trips, so a rapid type sequence with CHANGING top-match targets could in
principle leak. It is NOT exercised by any current test: the only rapid-type test
(`test_rapid_type_confirm_no_backlog`) fires 3 keys that all match the SAME unique window
(xyz), and `preview.sh`'s idempotent pre-link check dedups a same-target link. We MUST NOT
add early invalidation to the type path here — `test_rapid_type_confirm_no_backlog` asserts
seq==3 (one bump per type), and a double-bump would yield seq==6. The nav fix is what the
test requires; the type path stays per the work-item contract.

## 6. Verification run this session (tmux 3.6b, isolated socket)
Applied the 3 edits to a clean HEAD checkout, ran `bash tests/run.sh`:
- syntax: `bash -n scripts/input-handler.sh` clean.
- RUNs 1-10: `77 passed, 0 failed (of 77)` every run (incl. test_superseded_preview_noop,
  test_rapid_type_confirm_no_backlog, all test_scroll_width.sh cases, test_orig_session_client_aware).
- Source then `git checkout`-reverted; tree clean. The implementer applies the delta from the PRP.

## 7. Cross-refs
- `scripts/input-handler.sh` (SUT): `_lp_fire_preview`, `_lp_preview_follow`,
  `_lp_scroll_into_view`, `_lp_sync_preview_to_top_match`, the nav branches.
- `scripts/preview.sh` GUARD 1/2/3 (the supersede re-checks the early bump exploits).
- `scripts/state.sh` STATE_PREVIEW_SEQ / STATE_SCROLL / STATE_CLIENT_WIDTH + get_state/set_state.
- `tests/test_responsiveness.sh::test_superseded_preview_noop` (the failing test, now green).
- `tests/test_scroll_width.sh` (defer=off scroll suite; unaffected by the defer=on gate).
- `architecture/codebase_patterns.md` §P5 (preview entry point — NOT bypassed), §P7 (shared viewport).
