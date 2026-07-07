# Research — Bugfix P1.M2.T1.S1: third seq check (GUARD 3) + idempotent pre-link check in preview.sh (Issue 4)

> All facts below are verified against the **current working tree** (the line
> numbers cited are live as of this research; the findings doc's line numbers
> were accurate at its write time and still match closely) and the already-live-
> verified `issue4_5_6_findings.md` §Issue 4 + `external_tmux_behavior.md` Q5/Q6.

## Environment

| Tool | Version |
|---|---|
| tmux | **3.6b** |
| bash | **5.3.x** (`/usr/bin/bash`) |
| shellcheck | **installed** (`/usr/bin/shellcheck`) |

---

## FINDING 1 — the TOCTOU window is real and located precisely (issue4_5_6_findings.md §Issue 4)

The shipped `scripts/preview.sh` checks `STATE_PREVIEW_SEQ` TWICE:
- **GUARD 1** (entry, lines 100-103): `if [ -n "$expected_seq" ]; then cur_seq=$(get_state...); [ "$cur_seq" != "$expected_seq" ] && return 0; fi`.
- **GUARD 2** (pre-mutation, lines 189-191): same check, placed BEFORE the unlink (the first mutation).

Between **GUARD 2** (line 189) and the trailing `set_state "$STATE_LINKED_ID" "$src_id"` (line 221), the function performs **three real tmux server round-trips**:
1. re-read `linked_id` (line 195) — 1 round-trip
2. `unlink-window` (line 199) — 1 round-trip
3. `link-window` (line 210) — 1 round-trip
4. `select-window` (line 218) — 1 round-trip
5. `set_state LINKED_ID` (line 221) — the commit

If a newer keystroke / confirm / cancel / `clear_all_state` advances or unsets the seq DURING those round-trips, the late job has already passed GUARD 2 and proceeds to `unlink`/`link`/`select`/`set_state`, **orphaning a linked window** in the (now backgrounded) driver session and/or **clobbering the newer job's `@livepicker-linked-id`** commit.

**Reproduction** (issue4_5_6_findings.md §Issue 4): with a 0.4s delay injected between GUARD 2 and the unlink, the race reproduces **5/5 runs** (`driver windows: @0 @1 @1` — a duplicate/orphaned @1). Without load the window is tight (tens of ms) but it is a genuine gap in the §18 supersede guarantee.

---

## FINDING 2 — the fix has two independent parts (contract §1A + §1B)

### Part A — GUARD 3 (third seq check, between select-window and set_state)

Insert a THIRD seq re-check between `select-window` (line 218) and `set_state LINKED_ID` (line 221):
```bash
if [ -n "$expected_seq" ]; then
    [ "$(get_state "$STATE_PREVIEW_SEQ" "0")" != "$expected_seq" ] && return 0
fi
```
This closes the **commit-clobber half**: a job that went stale during the unlink→link→select round-trips will NOT overwrite the newer job's `STATE_LINKED_ID`. Placement is load-bearing (contract §3): **AFTER `select-window`, BEFORE `set_state`** — do NOT move it earlier. A pre-link GUARD 3 would let a stale job link then bail, leaving an UNTRACKED link (the existing GUARD 2 comment at lines 182-188 warns of exactly this).

### Part B — idempotent pre-link check (before the duplicate-guard)

Before unlinking+linking, probe whether `src_id` is ALREADY linked into the driver:
```bash
if tmux list-windows -t "=$current_session" -F '#{window_id}' 2>/dev/null | grep -Fxq "$src_id"; then
    tmux select-window -t "$src_id" 2>/dev/null || true
    set_state "$STATE_LINKED_ID" "$src_id"
    return 0
fi
```
This closes the **duplicate-link half**: a losing interleave that already linked `src_id` (or a re-preview of the same window where `LINKED_ID` hasn't been committed yet) is caught by the authoritative driver-state probe, so `link-window` is not called a second time (which would silently create a DUPLICATE — `link-window` returns rc=0 on already-linked windows, FINDING 4 of the original preview research).

**Verified empirically** (issue4_5_6_findings.md): `list-windows -t '=drv' -F '#{window_id}' | grep -Fxq '@1'` correctly detects whether window `@1` is already in the driver session on the isolated socket.

---

## FINDING 3 — the two parts address DIFFERENT halves; neither alone is sufficient

| Scenario | Without fix | Part A (GUARD 3) | Part B (idempotent) | Both |
|---|---|---|---|---|
| Stale job clobbers newer job's LINKED_ID commit | clobber → mis-tracked → wrong unlink on next nav/restore | **prevented** (bails before set_state) | not addressed (different scenario) | **prevented** |
| Losing interleave links src_id a 2nd time (duplicate window) | duplicate (@0 @1 @1) | not addressed (link already happened) | **prevented** (skips link; selects+records) | **prevented** |
| Stale job links a DIFFERENT window than the newer job (A=srcX, B=srcY) | both windows linked; one untracked | prevents LINKED_ID clobber but srcX stays linked (untracked) | does not fire (srcX not yet in driver when A checks) | **partial** — fundamentally unsolvable without per-window locking (tmux has none); documented as residual |

**Implication**: implement BOTH parts (the contract requires A + B). Document the residual (row 3) honestly in the comments — GUARD 3 prevents the WORSE outcome (commit clobber → mis-tracked → wrong-window unlink on restore, which can orphan/destroy); the untracked-extra-window case is caught on the NEXT navigation by the re-read `linked_id` + unlink, and by restore's unlink of LINKED_ID. This is the same honest acknowledgment the findings doc makes.

---

## FINDING 4 — exact edit anchors in the CURRENT preview.sh (content-based; line numbers verified)

The findings doc's line numbers (GUARD 2 at 172-174, select at 195, set_state at 198) are STALE relative to the current file (which has grown with verbose comments). The CURRENT anchors (verified by grep):

**Part B insertion point** — immediately BEFORE the DUPLICATE GUARD comment block (lines 174-180):
```
	# DUPLICATE GUARD (FINDING 4/5). Re-previewing the SAME session (linked_id ==
	# src_id, e.g. single-match wrap): the window is already linked + selected.
	# Skip unlink AND link (re-linking would silently duplicate). Just ensure shown.
	if [ -n "$linked_id" ] && [ "$linked_id" = "$src_id" ]; then
		tmux select-window -t "$src_id" 2>/dev/null || true
		return 0
	fi
```
Insert the idempotent check BEFORE this block (the contract allows "before or fused with it"; "before" is cleaner — keeps the duplicate-guard as the cheap `linked_id == src_id` fast path and adds the idempotent probe as the authoritative race-catcher). `$src_id` is resolved and non-empty at this point (the `[ -z "$src_id" ]` fallback at line 168 returns early); `$current_session` is in scope (read at line 86).

**Part A insertion point** — between `select-window` (line 218) and `set_state` (line 221):
```
	tmux select-window -t "$src_id" 2>/dev/null || true

	# Track the linked id (handle for the next unlink + for restore P1.M5).
	set_state "$STATE_LINKED_ID" "$src_id"
	return 0
```
Insert GUARD 3 in the blank line between `select-window` and the `# Track the linked id` comment. `$expected_seq` and `$STATE_PREVIEW_SEQ` are in scope (function args/locals + the sourced state.sh).

**Both edits are inside the `mode == live` path** (after the preview-mode gate at lines 106-123 and the self-session guard at lines 125-151) — the contract requires this (§3). Verified: the DUPLICATE GUARD and the select/set_state block are both after the `mode == live` fall-through and the self-session `return 0`.

---

## FINDING 5 — variables in scope; no new sourcing/strictness (verified)

At both insertion points, every referenced symbol is already in scope:
- `$expected_seq` — `preview_main` local (line 81: `local S="${1:-}" expected_seq="${2:-}"`).
- `$src_id` — `preview_main` local (line 82), resolved at lines 162-166.
- `$current_session` — `preview_main` local (line 82), read at line 86.
- `get_state` / `$STATE_PREVIEW_SEQ` / `$STATE_LINKED_ID` / `set_state` — from the sourced `state.sh` (preview.sh header sources options+utils+state).
- `tmux` — bare (the PATH shim in tests / the real server in prod).

No new `source`, no `local` declaration needed (the guards reuse existing locals; the idempotent check reuses `$current_session`/`$src_id`/`$STATE_LINKED_ID`). `set -u` is inherited and safe (every var is defaulted: `expected_seq="${2:-}"`, `get_state "$STATE_PREVIEW_SEQ" "0"`). No `set -e` (preview.sh has none; the `|| true` / `2>/dev/null` guards remain).

---

## FINDING 6 — the idempotent check does NOT need its own seq guard (reasoned)

The contract's Part B snippet does NOT gate the idempotent check on `expected_seq`. This is correct:
- The idempotent check fires ONLY when `src_id` is ALREADY linked in the driver. In that state, `select-window -t "$src_id"` (changes the active window within the session — non-destructive; does not fire `client-session-changed`) and `set_state LINKED_ID = src_id` (records the already-true linked id) are **non-destructive**. The destructive operation (`link-window`, which would duplicate) is SKIPPED.
- So even a stale job (seq advanced) hitting the idempotent check does no harm: it selects an already-linked window and records its already-true id. It does NOT unlink/link a stale window, and it does NOT clobber a newer job's LINKED_ID with a DIFFERENT id (it sets LINKED_ID to `src_id`, which is the window actually linked).
- GUARD 1/2/3 own the supersede semantics (bail before destructive ops); the idempotent check owns the duplicate-link prevention. Keeping them separate is cleaner and matches the contract. Do NOT add a seq guard to the idempotent check.

---

## FINDING 7 — GUARD 2 comment should get a one-line forward-reference (clarity)

The existing GUARD 2 comment (lines 182-188) says: "Do NOT move this to before the final select-window: that fires AFTER link-window but BEFORE set_state LINKED_ID -> a stale job would link its window then bail, leaving an UNTRACKED link (a leak). (research FINDING 5.)"

This warning refers to **GUARD 2's own placement** (stay before the unlink). Adding GUARD 3 (which IS before set_state) does NOT move GUARD 2 — but a future reader could misread the comment as "no guard may sit before set_state, yet GUARD 3 does." A one-line forward-reference on the GUARD 2 comment ("GUARD 3 below is an ADDITIVE late commit-clobber check (Issue 4); this warning is about THIS guard's own placement, not a prohibition on a late guard.") prevents that confusion. This is within the contract's DOCS scope ("update inline comments at the GUARD 3 insertion point and the idempotent check") in spirit — a minimal, high-value clarification. Mark it as a recommended-but-secondary edit so the implementer doesn't over-edit.

---

## FINDING 8 — test landscape + validation strategy (no committed test; contract is code-only)

- The contract DOCS (§6) specifies **Mode A — inline comments only**. No committed regression test is required from this subtask. `tests/test_responsiveness.sh` (owned by P1.M3.T1, a different milestone) already exercises the deferred path (`@livepicker-preview-defer on`, `STATE_PREVIEW_SEQ`, `run-shell -b`); adding a test here would collide with that milestone's scope.
- `tests/helpers.sh` line 95 pins `@livepicker-preview-defer off` for the bulk of the suite (functional/restore/etc.), so the deferred path is NOT exercised by most existing tests → the additions are **inert** for them → `tests/run.sh` stays green by construction.
- The race is **timing-dependent** (reproduces 5/5 only with an injected 0.4s delay). A deterministic committed test would require injecting a delay into preview.sh (fragile, not ship-able). Validation strategy:
  1. **L1**: `bash -n` + `shellcheck` + grep cross-checks (GUARD 3 present once; idempotent `grep -Fxq` present once; both inside `mode == live`).
  2. **L2**: full `tests/run.sh` green (no regression; the additions are no-ops on the defer=off path most tests use, and additive on the defer=on path test_responsiveness.sh uses).
  3. **L3** (throwaway, prove-it-catches-the-bug): inject a `sleep 0.3` between GUARD 2 and the unlink, fire a deferred preview with expected_seq=1, bump the seq to 2 mid-flight (simulating a newer keystroke), wait, and assert LINKED_ID was NOT clobbered by the stale job (it stays empty or the newer value) — proves GUARD 3. Then separately: pre-link src_id into the driver, call preview.sh with that src_id, assert the window count does NOT increase (no duplicate) — proves Part B. DELETE the throwaway after.

---

## FINDING 9 — disjoint from the parallel task P1.M1.T3.S2 (test_create.sh only)

The parallel task P1.M1.T3.S2 appends `test_create_sanitized_name_lands_on_session` to `tests/test_create.sh` — it touches **no production code** (input-handler.sh was S1, already applied). This task modifies `scripts/preview.sh` ONLY. **Zero file overlap** → no edit collision. Both can land concurrently.

---

## Summary of load-bearing decisions (encoded in the PRP)

1. **GUARD 3 (Part A)**: third `expected_seq` re-check between `select-window` (line 218) and `set_state LINKED_ID` (line 221). Closes the commit-clobber half. (FINDINGS 1, 2, 4)
2. **Idempotent pre-link check (Part B)**: `list-windows -t "=$current_session" -F '#{window_id}' | grep -Fxq "$src_id"` BEFORE the DUPLICATE GUARD (line 174). Skip link; select+set_state+return. Closes the duplicate-link half. No seq guard on this check. (FINDINGS 2, 4, 6)
3. **Both inside `mode == live`** (after the preview-mode gate + self-session guard). (FINDING 4)
4. **Anchor edits on CONTENT** (DUPLICATE GUARD comment block; select+set_state pair), NOT line numbers (the findings doc's line numbers are slightly stale). (FINDING 4)
5. **Document the residual** (a stale job linking a different window than the newer job is unsolvable without locking) honestly in the GUARD 3 comment. (FINDING 3)
6. **Optional one-line forward-reference** on the GUARD 2 comment to prevent misreading. (FINDING 7)
7. **No committed test** (Mode A; test_responsiveness.sh is P1.M3.T1's scope). Validate via L1 grep + L2 full suite + L3 throwaway race proof. (FINDING 8)
8. **No conflict** with parallel P1.M1.T3.S2 (test_create.sh only). (FINDING 9)

---

## Gaps

None material. The two edits are anchored on verified-current content (FINDING 4); the
semantics (commit-clobber vs duplicate-link) are reasoned in FINDING 3; the idempotent
probe is empirically proven (issue4_5_6_findings.md); the residual is acknowledged. The
only soft spot is the L3 throwaway race proof (timing-dependent), which is best-effort by
nature — the deterministic L1 grep + L2 suite-green are the firm gates.
