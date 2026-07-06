# P1.M7.T4.S1 — `tests/test_preview.sh` research findings

Empirical ground-truth gathered by probing an **isolated `tmux -L` socket** (the same
isolation mechanism `tests/setup_socket.sh` provides) AND by driving the **real
`scripts/preview.sh`** (COMPLETE P1.M3.T1.S1+S2) directly through the **actual
harness files** (`tests/setup_socket.sh` + `tests/helpers.sh`, COMPLETE). Every claim
below was verified live on the installed tmux 3.6b. These findings are the
non-obvious correctness basis for `tests/test_preview.sh`.

The work item (PRD §15.19 "Live all-panes preview" + a §7 Fallbacks probe) defines
FOUR test functions, all of which call `preview.sh <S>` **directly** (contract §1:
"preview.sh S"; INPUT: preview.sh). This is a focused UNIT test of the live-preview
core — distinct from T3.S1's integration tests (which drive `livepicker.sh` →
`input-handler.sh` nav → `preview.sh`). T3.S1's `test_nav_moves_selection` already
covers the nav→preview→linked-id integration; T4.S1 owns the **link-window /
unlink-window SEMANTICS** (multi-pane visibility, unlink-keeps-source, self-no-link,
capture fallback).

---

### FINDING 1 — `preview.sh` is CLIENT-INDEPENDENT; NO `attach_test_client` needed.

`preview.sh` reads the driver (current) session name from the saved state key
`@livepicker-orig-session` (`current_session="$(get_state "$ORIG_SESSION" "")"`),
NOT from `tmux display-message -p`. `display-message -p` is the only primitive that
needs an attached client; `preview.sh` uses NONE of: link-window / unlink-window /
select-window / list-windows / capture-pane / set-option — all operate on the
session+window directly and work on a DETACHED socket.

**Verified**: every probe ran with ZERO attached clients; all `preview.sh`
invocations returned rc=0 and produced the expected tmux state. This is a
SIMPLIFICATION vs T3.S1 (whose `livepicker.sh` activate uses `display-message -p`
in STEP 2 → REQUIRED a client). **`test_preview.sh` calls NO `attach_test_client`.**

### FINDING 2 — The minimal state `preview.sh` reads; the `lp_preview_seed_state` helper.

`preview_main` reads exactly THREE `@livepicker-*` keys at the top:
  - `@livepicker-orig-session` — the driver (the session windows get linked INTO).
  - `@livepicker-orig-window`  — the driver's window to re-select on the self-session path.
  - `@livepicker-linked-id`    — the prior linked window id (handle for the next unlink).

Plus `opt_preview_mode` (`@livepicker-preview-mode`, default `live`) — the mode gate.

It does NOT read `@livepicker-mode`, `@livepicker-list`, the status, or the
key-table. So a focused preview test seeds ONLY those 3 keys via bare
`tmux set-option -g` and calls `preview.sh <S>`. The seed helper
`lp_preview_seed_state` sets orig-session=driver, orig-window=**driver's ACTIVE
window id read DYNAMICALLY** (FINDING 3), linked-id="". The literal key STRINGS are
used (stable contract constants from `scripts/state.sh`) — NO sourcing (mirror
T3.S1's `lp_runtime_cleared`, which also uses the literal key strings).

### FINDING 3 — Window IDs are GLOBAL; ALWAYS read them DYNAMICALLY (never hardcode).

Window ids (`@0`,`@1`,…) are server-global and assigned incrementally. The baseline
`setup_socket` seed consumes `@0`(driver), `@1`(alpha), `@2`(beta), `@3`(driver:extra);
a test-created session's first window is `@4`+ (its panes are `%N`, also global and
incremental — a probe showed `%7 %8 %9`). NEVER assert `@1`/`@2`/`@4`. Read the
expected id live:

```bash
multi_win="$(tmux list-windows -t '=multi' -F '#{window_id}' -f '#{window_active}')"
```

After `preview.sh multi`, `@livepicker-linked-id == "$multi_win"` AND the driver's
current active window == `$multi_win`.

### FINDING 4 — Multi-pane link shows ALL panes (PRD §15.19 bullet 1). **VERIFIED.**

A tmux window linked into a second session is the SAME window object (same global
id) in BOTH sessions; ALL of its panes render live in both. Probe (3-pane `multi`
window `@4`, panes `%7 %8 %9`):

| assertion target | result |
|---|---|
| `list-windows -t =driver` contains `@4` | YES (`@0 @3 @4`) |
| `list-windows -t =multi`  contains `@4` | YES (`@4`) — source KEEPS it |
| driver's CURRENT active window == `@4` | YES |
| `list-panes -t @4` pane count | 3 (`%7 %8 %9`) — all panes visible |

So `test_multipane_preview` asserts: (a) the linked window id is present in BOTH the
driver and the source session; (b) the driver's current active window id == the
source's active window id; (c) the linked window's pane count == 3 (strong "all
panes visible" proof). Use `mapfile -t _panes < <(tmux list-panes …)` +
`${#_panes[@]}` for the count (NO pipe — house style; `wc -l` pipe also works but
mapfile is cleaner under `set -u`).

### FINDING 5 — Navigate-away UNLINKS from the driver; the source KEEPS its window (PRD §15.19 bullet 2). **VERIFIED.**

`unlink-window` WITHOUT `-k` removes ONE link (from the driver); the source session
keeps its window (preview.sh FINDING 1/11). Probe (`preview multi` then `preview
alpha`):

| assertion target | result |
|---|---|
| `list-windows -t =driver` after preview alpha | `@0 @3` — `@4` (multi) GONE (unlinked) |
| `list-windows -t =multi`  after preview alpha | `@4` — STILL present (intact) |
| `@livepicker-linked-id` after preview alpha | `@1` (alpha's window) |

So `test_navigate_unlinks_intact` captures the source session's window list BEFORE
navigating away and asserts it is byte-identical AFTER (the `list-windows -t` before/
after diff the contract calls for), AND asserts the previously-linked window id is NO
longer in the driver.

### FINDING 6 — Self-session does NOT link (PRD §15.19 bullet 3). **VERIFIED.**

When the candidate `S == current_session` (the driver), `preview.sh`'s self-session
guard fires: it (optionally) unlinks any prior preview, CLEARS `@livepicker-linked-id`
(`-gu`), and `select-window -t "$ORIG_WINDOW"` — WITHOUT linking (a session cannot
link its own window into itself; linking would create an in-session duplicate).
Probe (seed linked-id="" then `preview driver`):

| assertion target | result |
|---|---|
| `@livepicker-linked-id` after self preview | `` (empty — STAYS empty) |
| driver's current active window | `@0` (the ORIG_WINDOW) |
| driver window list | unchanged (no duplicate from a self-link) |

So `test_self_session_no_link` asserts: linked-id stays empty; the driver's current
window == the seeded orig window; the driver's window list is UNCHANGED before/after
(the "no link-window was attempted" proof — no duplicate window appears). The STRONGER
variant (a prior foreign link, then self-preview clears it) is documented but the
primary test mirrors activate's real first-preview (linked-id="" in → "" out).

### FINDING 7 — `link-window` NEVER fails on a duplicate (rc=0, it DUPLICATES). **CORRECTION of the contract's example.**

The contract's literal trigger for `test_capture_fallback` — "preview a session whose
active window is already linked singly" — is **empirically invalid** on tmux 3.6b.
Probe (raw `link-window -a -s <id> -t driver:` twice on the SAME window):

```
link1 rc=0
link2 rc=0          # does NOT fail — silently creates a DUPLICATE link
driver windows: @0 @3 @1 @1   # alpha's window linked TWICE
```

`preview.sh`'s duplicate-guard (`linked_id == src_id` → skip BOTH unlink and link)
prevents this in normal flow, but the raw tmux primitive does NOT fail. **Do NOT use
this trigger** — it cannot reach the `if ! tmux link-window …` fallback branch.

### FINDING 8 — TWO deterministic capture-pane fallback triggers (use BOTH in `test_capture_fallback`).

`preview_fallback` (capture-pane) is reachable via two distinct code paths in
`preview.sh`; both are deterministic on 3.6b and both run capture-pane on a REAL
candidate session so capture SUCCEEDS (rc=0):

**(a) The `@livepicker-preview-mode=snapshot` gate** — `preview.sh` reads the mode
FIRST and, on `snapshot`, calls `preview_fallback` and returns BEFORE any link. Probe:
`set @livepicker-preview-mode snapshot; preview.sh cand` → rc=0, linked-id stays "".
Covers PRD §7 "If @livepicker-preview-mode is snapshot, always use capture-pane and
skip linking." **Reset to `live` after.**

**(b) The genuine link-FAILURE branch** — seed `@livepicker-orig-session` to a
NON-EXISTENT session name. Then `tmux link-window -a -s "$src_id" -t "no-such:"`
FAILS with rc=1 ("can't find session: no-such-session-xyz"), so `preview.sh`'s
`if ! tmux link-window …; then preview_fallback "$S"` branch fires. The candidate
`S` is a REAL session, so `capture-pane -ep -t "=$S:."` succeeds (rc=0). Probe:
rc=0, linked-id="", driver has no extra window. This is the FAITHFUL "force a link
failure" test (it exercises the real link-failure branch, not just the config gate).

So `test_capture_fallback` runs BOTH sub-scenarios (snapshot gate + bogus-driver
link failure) and asserts each: preview.sh rc==0 (`|| fail`), linked-id stays "".

### FINDING 9 — `capture-pane` target is `=$S:.` NOT `=$S` (preview.sh already handles this).

`preview_fallback` captures `tmux capture-pane -ep -t "=$1:."`. The bare `=$S` form
FAILS rc=1 ("can't find pane") on 3.6b (`=` is a session-name matcher; capture-pane
wants a pane target). The `:.` suffix selects the active pane. **preview.sh already
does this correctly** — the tests only DRIVE it; this finding explains WHY capture
succeeds and guards against a "fix" that would break it.

### FINDING 10 — House style: SOURCED by run.sh; NO client; NO sourcing; `set -u` inherited.

Mirror `tests/test_self.sh` and the T3.S1 contract EXACTLY:
  - `test_preview.sh` is **SOURCED** by `run.sh` (which sources `setup_socket.sh` +
    `helpers.sh` first, then globs `test_*.sh`). Define `test_*` +
    `lp_preview_seed_state` ONLY; **NO side effects on source** (no top-level
    execution, no `setup_test`/`teardown_test` calls — run.sh owns the per-test cycle).
  - `set -u` is **INHERITED** from `helpers.sh` — do NOT re-declare it; do NOT add
    `set -e` / `set -o pipefail` (house style; `show-option`/`list-windows`/unlink
    legitimately return non-zero).
  - File-level `# shellcheck disable=SC2154,SC2016,SC2034,SC2086` (SC2154:
    `assert_*`/`fail`/`$LIVEPICKER_SCRIPTS`/`$TEST_DRIVER_SESSION` are defined by
    run.sh's sources, not here).
  - Signal failure ONLY via `fail`/`assert_*` (which set `TEST_STATUS`); **NEVER
    `exit`** (run.sh reads `TEST_STATUS` in the CURRENT shell — a bare `exit` kills
    the runner).
  - TABS for indent; `local` for all function locals; quote everything.
  - **NO `attach_test_client`** (FINDING 1) — unlike T3.S1, preview tests need no client.

### FINDING 11 — Snapshot-mode state-inheritance trap (intra-test).

Switching to `@livepicker-preview-mode=snapshot` does NOT clear a prior `linked-id`
(the snapshot path `return`s before any state mutation). So within
`test_capture_fallback`, re-seed `@livepicker-linked-id=""` BEFORE the snapshot
sub-assertion (or seed fresh, then toggle the mode). Each test_*.sh already gets a
FRESH socket via run.sh's `setup_test`, so the trap is only INTRA-function — re-seed
between the two fallback sub-scenarios.

### FINDING 12 — Confidence 9/10.

One NEW sourced test file (zero edits to existing code) driving the COMPLETE
`preview.sh` directly. Every driving pattern + assertion target is **empirically
verified** on the isolated socket via the actual harness files: multi-pane link
visibility (F4), unlink-keeps-source (F5), self-no-link (F6), and BOTH capture
fallback triggers (F8). The residual risk (-1): the two non-obvious traps — the
contract's INVALID "already-linked-singly" trigger (F7) and the snapshot
state-inheritance (F11) — both explicitly corrected below.
