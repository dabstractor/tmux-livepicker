# Research Findings — P2.M3.T1.S1 (test_window_flip.sh test suite)

Ground-truth for the PRP. **ALL tmux behavior was verified empirically on an
isolated socket** (`tests/setup_socket.sh`) against **tmux 3.6b** via throwaway
probe scripts (7 probe batches). Line numbers refer to the CURRENT
`scripts/preview.sh` / `scripts/input-handler.sh` / `scripts/state.sh`.

This task VALIDATES the window-flip feature (P2.M1 + P2.M2). The validation
exposed ONE load-bearing correctness bug in `preview.sh` that MUST be fixed for
the LEAVE-NO-TRACE (b) and CURSOR-RESET (d) test cases to pass — see FINDING 3.

---

## FINDING 1 — The 5 test cases + validated assertion shapes (all PROVEN passing)

The work item's 5 test cases, each verified end-to-end on the isolated socket:

| case | name | what it asserts | passes? |
|------|------|-----------------|---------|
| (a) | FLIP | driver contains the chosen @id; driver active == chosen (line 2 follows); linked-id == chosen | ✅ as-is |
| (b) | LEAVE-NO-TRACE | candidate `window_active` AND `window_layout` byte-identical before/after a flip sequence | ✅ with FINDING 3 fix + FINDING 4 setup |
| (c) | CONFIRM-ON-WINDOW | flip a NON-active window, confirm lands on (S, W) not the prior active | ✅ (consumes P2.M2.T2.S1) |
| (d) | CURSOR RESET | flip A, go B, return to A → A re-previewed on its OWN active (flip history forgotten) | ✅ with FINDING 3 fix |
| (e) | SELF-SESSION FLIP | flip the driver's own windows, cancel → back on ORIG_WINDOW | ✅ as-is |

See the probe transcripts in the PRP's Validation Loop for the exact assertion
shapes that went GREEN.

---

## FINDING 2 — Deterministic highlighting: use `type <unique-name>`, NOT `next-session`

**CRITICAL**: `next-session` moves the highlight by EXACTLY ONE position in the
filtered list, in tmux's session-creation order (driver, alpha, beta, …then any
new sessions). It does NOT jump to a named candidate. A test that does
`next-session` once after creating `cand` lands on `alpha`, NOT `cand`
(verified — this caused 3 false failures in the first probe).

The DETERMINISTIC way to highlight a specific candidate is to **type its
(unique) name** so the filter reduces the list to exactly it:

```bash
tmux new-session -d -s zzcand -x 80 -y 24   # UNIQUE name (no baseline session matches)
"$LIVEPICKER_SCRIPTS/livepicker.sh"
for c in z z c a n d; do "$LIVEPICKER_SCRIPTS/input-handler.sh" type "$c" >/dev/null 2>&1; done
# now the highlight is provably on zzcand, and @livepicker-linked-id == zzcand's active window
```

`type` RESETS the window-cursor state (STATE_CAND_WIN_SESSION/LIST/CURSOR →
""/""/0 — see input-handler.sh type/backspace branches). That is CORRECT and
desired: the first `next-window` after a `type` lazily re-derives the list and
resets the cursor to the candidate's active window, then advances. So the test
sequence is always: `type <unique>` (land on candidate) → `next-window` (flip).

**Naming**: every fixture session in this suite uses a UNIQUE prefix that no
baseline session (driver/alpha/beta) and no sibling fixture contains as a
case-insensitive substring: `zzcand`, `qqmulti`, `xxA`, `yyB`. This guarantees
the filter reduces to exactly one match regardless of ranking.

---

## FINDING 3 — THE BUG: bare `select-window -t "$src_id"` drifts the candidate's active window (Invariant B violation); fix = session-scoped select

**Verified (the smoking gun)**: a MINIMAL tmux sequence — `link-window -s @4
-t driver:` then `select-window -t "@4"` (bare window-id) — CHANGES the source
session's active window (@6 → @4). Root cause: **`select-window -t "@id"` with a
BARE window-id selects the window in its HOME/origin session** (the session it
was created in = the candidate), NOT in the current/driver session. tmux 3.6b.

`preview.sh` does exactly this on every link: `tmux select-window -t "$src_id"`
(bare @id) at lines **211, 221, 264**. So flipping to a NON-active window of a
candidate DRIFTS that candidate's active window to the flipped window — a direct
Invariant B violation ("the flip never selected a window in the candidate").
This breaks test (b) (candidate active not byte-identical) AND test (d) (after
flipping A and returning, A's active has drifted to the flipped window, so
"re-preview on own active" shows the wrong window).

**NOTE on session-nav**: previewing a candidate's ACTIVE window does NOT drift
(the selected window is already active, so selecting it is a no-op). Only the
FLIP path (selecting a NON-active window) triggers the drift. So existing tests
(test_preview.sh / test_functional.sh) are unaffected — they only preview active
windows. The flip path is the new surface this suite exercises.

**THE FIX (REQUIRED for (b) and (d) to pass)**: make the three `select-window
-t "$src_id"` calls SESSION-SCOPED — select in the DRIVER (`$current_session`),
never via the bare id that resolves to the candidate's home session:

```bash
# BEFORE (3 occurrences — preview.sh lines 211, 221, 264):
tmux select-window -t "$src_id" 2>/dev/null || true
# AFTER (session-scoped — selects in the DRIVER, leaves the candidate untouched):
tmux select-window -t "$current_session:$src_id" 2>/dev/null || true
```

`$current_session` IS in scope at all 3 sites (assigned at preview.sh:94,
`current_session="$(get_state "$ORIG_SESSION" "")"`; used by the self-session
guard above). The fix is STRICTLY MORE CORRECT: preview.sh always intends to
select in the driver (the linked window is in the driver); the bare form was an
oversight that happened to be harmless for the active-window (session-nav) path
but violates Invariant B on the flip path.

**Verified**: the session-scoped form (`select-window -t "=$TEST_DRIVER_SESSION:$nonactive"`)
PRESERVES the source session's active window (probe `lp_diag2.sh` TEST A: src
active stayed @6). `link-window` alone does NOT drift (TEST B) — only the bare
select does.

**Scope/safety**: this is a 3-line correctness fix to preview.sh (owned by the
COMPLETE P2.M1.T2). It does NOT conflict with the parallel P2.M2.T2.S1 (which
edits ONLY restore.sh STEP-2). It does NOT preempt P3.M2.T2 (candidate pinning)
— that task adds pane-GEOMETRY pinning (§23); this fix pins only the ACTIVE
window (§3.6 Invariant B). They are complementary. No existing test breaks
(driver active == linked window holds under both forms; candidate-active
preservation is strictly additive).

The 3 occurrences are byte-identical (`tmux select-window -t "$src_id"
2>/dev/null || true`) → a single `sed` replaces all 3 (the string
`select-window -t "$src_id"` appears NOWHERE ELSE in preview.sh — the
self-session path uses `$chosen_win`/`$orig_window`/`$S`; confirmed via grep).

---

## FINDING 4 — window_layout byte-identical IS achievable: dynamically pre-size the candidate to the driver + `window-size manual`

The candidate's `window_layout` (pane geometry) normally CHANGES when one of its
windows is linked into the driver, because the shared window object reflows to
the driver's (different) size — the §22/§23 "shared-window resize". This is NOT
fixed by FINDING 3 (which only pins the active window) and is formally Invariant
C (§23, P3.M3's domain).

**HOWEVER**: the literal work-item spec for (b) demands `window_layout`
byte-identical. It IS achievable in this P2 suite by **eliminating the reflow
confound**: after activate (so the driver's post-status-grow size is known),
query the driver's active-window dimensions, then resize the candidate's windows
to EXACTLY that size and lock the candidate's `window-size` to `manual`. A
manual, driver-sized candidate does NOT reflow when its (already-correct-size)
window is linked into the driver → geometry is byte-identical across flips.

**Verified (probe `lp_robust.sh`)**: after dynamically matching the candidate to
the driver's `${DW}x${DH}` + `window-size manual`, the candidate's
`#{window_id}:#{window_layout}` was BYTE-IDENTICAL across a 3-flip sequence
(`@4:b304,120x23,...|@6:b306,...|@5:8df9,...` unchanged). The driver size was
queried DYNAMICALLY (120x23 in that run) — robust to any pty size. Pane counts
per window are also a stable multiset (1,1,3) — no panes split/killed.

This is a legitimate, faithful setup: it ISOLATES the flip-selection invariant
(Invariant B — does the flip select in the candidate?) from the resize/geometry
invariant (Invariant C — does linking reflow panes?), which is P3.M3's job with
a real client. With the candidate pre-sized + manual, (b) can assert the FULL
`#{window_id}:#{window_active}:#{window_layout}` byte-identical (active via
FINDING 3, geometry via this setup).

The pre-size step runs as a small helper AFTER `livepicker.sh` activate and
BEFORE the before-snapshot (see the PRP's `lp_winflip_match_size` helper).

---

## FINDING 5 — window-cursor state keys (evolution the tests read)

From `state.sh` (all cleared by clear_all_state via `_STATE_RUNTIME_KEYS`):

| key | meaning | init (activate) | on `type`/`backspace`/session-nav | on `next-window`/`prev-window` |
|-----|---------|-----------------|-----------------------------------|--------------------------------|
| `@livepicker-cand-win-session` | the session the cached list belongs to | `=ORIG_SESSION` | `""` (invalidate) | `=S` (re-bind) |
| `@livepicker-cand-win-list` | newline-joined window ids of the candidate | `""` | `""` (invalidate) | `list-windows -t "=$S" -F '#{window_id}'` (lazy derive) |
| `@livepicker-cand-win-cursor` | 0-based index into the list | `0` | `0` | reset to active-idx on (re)derive, then ±1 wrap |
| `@livepicker-preview-win-id` | the window currently shown (== linked-id non-self, diverges for self) | `""` | (preview.sh sets) | `=W` (the chosen window) |
| `@livepicker-linked-id` | the window linked into the driver | `""` | (preview.sh sets) | `=W` (non-self); `""` (self) |

The chosen window W for a flip = `awk -v c="$cursor" 'NR==(c+1){print;exit}'`
over the cand-win-list. Tests read W either from `@livepicker-linked-id` (non-self,
== W) or by computing list[cursor].

---

## FINDING 6 — test harness contract (what's IN SCOPE inside a test_*)

`run.sh` sources `setup_socket.sh` + `helpers.sh` + every `tests/test_*.sh`,
then PER test: `setup_test "lp-$$-<name>"` (fresh isolated -L socket + PATH shim +
baseline fixtures driver/alpha/beta, AND pins `@livepicker-preview-defer OFF` for
deterministic synchronous preview) → `TEST_STATUS="pass"` → runs the test_* in
the CURRENT shell → reads TEST_STATUS → `teardown_test`.

So inside a test_* these are ALL in scope: bare `tmux` (→ isolated socket),
`$LIVEPICKER_SCRIPTS`, `$TEST_DRIVER_SESSION`, `attach_test_client`,
`detach_test_client`, `fail`/`pass`/`assert_eq`/`assert_contains`. The test file
SOURCES NOTHING and calls NO setup_test/teardown_test (run.sh owns the cycle).
`set -u` is INHERITED (do NOT re-declare — mirror test_preview.sh /
test_functional.sh).

**Client requirement**: `livepicker.sh` activate, `display-message -p`, and
`refresh-client -S` REQUIRE an attached client → every test in this suite calls
`attach_test_client` FIRST (mirror test_functional.sh / test_preview_clip.sh,
NOT test_preview.sh which is client-independent).

**Auto-discovery**: `run.sh` does `for f in "$CURRENT_DIR"/test_*.sh; do source
"$f"; done` then `compgen -A function | grep '^test_'`. So creating
`tests/test_window_flip.sh` with `test_*` functions AUTO-REGISTERS it — **NO
`run.sh` edit is needed** (the work item's "add the test to tests/run.sh" is
satisfied by the glob). Verified: every existing tests/test_*.sh is picked up
this way with no explicit registration.

---

## FINDING 7 — dependencies on sibling tasks (consume, don't duplicate)

- **P2.M1 (window-cursor + flip + preview chosen-window)**: COMPLETE. preview.sh
  argv is now `preview.sh S [chosen_win] [seq]`; input-handler has
  next-window/prev-window; state has the 4 cand-win keys. This suite EXERCISES
  that. (preview.sh has the FINDING 3 bug — this suite's PRP includes the fix.)
- **P2.M2.T1 (confirm commits window)**: COMPLETE. confirm resolves W from the
  cursor and does `select-window -t "=$S:$W"` (session-scoped — already correct,
  no drift). Test (c) consumes this.
- **P2.M2.T2.S1 (restore keep skips ORIG_WINDOW re-select)**: IMPLEMENTING (the
  parallel task). Test (c)'s "confirm lands and STAYS on (S, W)" assertion
  DEPENDS on it — if keep re-selected ORIG_WINDOW, the client would be yanked off
  the chosen W. The PRP notes this as a hard dependency; the test is correct
  regardless and goes GREEN once P2.M2.T2.S1 lands.
- **P3 (clip / pane immutability §23)**: PLANNED, NOT done. This suite does NOT
  depend on it — FINDING 4's pre-size+manual setup makes geometry stable WITHOUT
  clip mode. (Full real-client Invariant C validation is P3.M3.T1.S1.)

---

## FINDING 8 — self-session flip (case e) mechanics (verified)

On activate, the initial highlight is the driver (self-session). `next-window`
flips the DRIVER's own windows: input-handler derives `list-windows -t
"=$driver"` and dispatches `_lp_preview_dispatch "driver" "$W"`. preview.sh sees
`check_session == current_session` (driver == driver) → self-session path →
`select-window -t "$chosen_win"` (a DRIVER window, not multi-linked → no drift)
and CLEARS linked_id (no link attempted). So `@livepicker-linked-id == ""` and
`@livepicker-preview-win-id == W` (the flipped driver window != ORIG_WINDOW).

`cancel` → restore.sh cancel → STEP-2 re-selects ORIG_WINDOW (cancel-only after
P2.M2.T2.S1) + STEP-3 switches back (same-session, deduped). So after cancel,
`display-message -p '#{window_id}' == ORIG_WINDOW`. Verified GREEN. NOTE: the
self-session path's select uses `$chosen_win` (not `$src_id`), so FINDING 3's fix
does NOT touch it — (e) is unaffected by the fix and passes as-is.

---

## FINDING 9 — (c) confirm-on-window lands on the chosen window, NOT the prior active

Verified: with a 3-window candidate `qqmulti` (active = 3rd window), `type
qqmulti` + ONE `next-window` flips to a NON-active window (cursor =
(active_idx+1)%3, definitely a different index). confirm then does
`select-window -t "=qqmulti:$W"` (session-scoped, correct) and the client lands
on `qqmulti:$W`. `display-message -p '#{window_id}'` == W, and
`list-windows -t '=qqmulti' -f '#{window_active}'` == W (confirm committed it).
Mid-flip (before confirm), with FINDING 3's fix, qqmulti's active is STILL its
pre-flip active (the chosen W differs from it) — this is the meaningful
"non-active window" check that proves the test is not vacuous.
