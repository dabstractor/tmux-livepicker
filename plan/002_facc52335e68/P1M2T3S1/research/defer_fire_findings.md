# Research — P1.M2.T3.S1: Centralize deferred-preview fire helper + rewire call sites

> PRD §18 (interaction-first, deferred preview). This task adds `_lp_fire_preview`
> and rewires the 5 input-handler call sites to defer the preview to a background
> supersedeable `run-shell -b` job when `@livepicker-preview-defer=on` (the default),
> restoring the legacy synchronous path when `off`.

## FINDING 1 — All dependencies are ALREADY LANDED in the working tree (grep-confirmed)

| dependency | file:line | status |
|---|---|---|
| `opt_preview_defer()` (default `"on"`) | options.sh:46 | ✅ landed (P1.M2.T1.S1) |
| `STATE_PREVIEW_SEQ` = `@livepicker-preview-seq` | state.sh:48 | ✅ landed |
| `STATE_PREVIEW_TARGET` = `@livepicker-preview-target` | state.sh:49 | ✅ landed |
| both in `_STATE_RUNTIME_KEYS` | state.sh:63 | ✅ landed (clear_all_state clears them) |
| `set_state "$STATE_PREVIEW_SEQ" "0"` at activation | livepicker.sh:163 | ✅ landed |
| `preview.sh <target> [expected_seq]` + supersede guard | preview.sh:76-77, 86-97, 167-168 | ✅ landed (P1.M2.T2.S1 — status said "Implementing" but it is IN the tree) |

So the full supersede seam exists: a background job tagged with a seq is honored by
preview.sh — it no-ops if the live seq has advanced. This task is the **producer**
(bumps seq, sets target, fires the job); preview.sh is the **consumer** (already done).

## FINDING 2 — The 5 call sites (exact, codebase_state.md §6 + live grep)

`_lp_sync_preview_to_top_match()` is defined at input-handler.sh:130-138. Its body
(computes `filtered[0]` via `lp_build_filtered`, guards empty, calls `preview.sh`):

```bash
_lp_sync_preview_to_top_match() {
	local _list _filt
	local -a _sync_filtered=()
	_list="$(get_state "$STATE_LIST" "")"
	_filt="$(get_state "$STATE_FILTER" "")"
	mapfile -t _sync_filtered < <(lp_build_filtered "$_list" "$_filt")
	[ "${#_sync_filtered[@]}" -eq 0 ] && return 0
	"$CURRENT_DIR/preview.sh" "${_sync_filtered[0]}" 2>/dev/null || true
}
```

Call sites (all inside `input_main`'s `case`):
- **type** (172): `set_state FILTER` → `set_state INDEX 0` → `_lp_sync_preview_to_top_match` → `refresh-client -S` (175).
- **backspace** (210): trim FILTER → `set_state INDEX 0` → `_lp_sync_preview_to_top_match` → `refresh-client -S` (213).
- **cancel-clear** (400): clear FILTER → `set_state INDEX 0` → `_lp_sync_preview_to_top_match` → `refresh-client -S` (404). [3-tab indent — inside `if [ -n "$cur_filter" ]`.]
- **next-session** (246): `set_state INDEX` → `target="${filtered[$new_idx]}"` → `"$CURRENT_DIR/preview.sh" "$target"` → `refresh-client -S` (247).
- **prev-session** (265): mirror of next.

The **confirm branch** (281-379) and the **cancel full-exit** (`restore.sh cancel`) are
ALREADY compliant (confirm resolves target from authoritative filter/index, never calls
preview.sh, never reads `@livepicker-linked-id` for the target). They stay UNCHANGED.

## FINDING 3 — The Q6 reference `_lp_fire_preview` (+ the contract's TARGET write)

`external_tmux_behavior.md` Q6 gives the reference helper:

```bash
_lp_fire_preview() {                       # $1 = candidate session/window token
    local seq
    seq="$(get_state "$STATE_PREVIEW_SEQ" "0")"; seq=$(( seq + 1 ))
    set_state "$STATE_PREVIEW_SEQ" "$seq"
    tmux run-shell -b "$CURRENT_DIR/preview.sh '$1' '$seq'"
}
#   type/backspace:  set filter/index, refresh-client -S, then _lp_fire_preview "${filtered[0]}"
#   next/prev:       set index, refresh-client -S, then _lp_fire_preview "$target"
```

The work-item CONTRACT adds `set_state "$STATE_PREVIEW_TARGET" "$1"` (observability +
optional recheck; the key exists for this). And an empty-target guard ("if there is no
top match, schedule nothing"). The merged helper (verbatim in the PRP) is FINDING 4.

## FINDING 4 — Design: 3 helpers (1 new low-level + 1 new dispatcher + 1 refactored)

To avoid duplicating the `if opt_preview_defer …` branch across all 5 call sites, the
defer logic is centralized in ONE dispatcher. The 5 sites collapse to single calls:

- **`_lp_fire_preview "$target"`** (NEW, contract-required, low-level): empty-guard →
  read seq → bump → set_state SEQ → set_state TARGET → `tmux run-shell -b "$CURRENT_DIR/preview.sh '$target' '$seq'"`.
- **`_lp_preview_follow "$target"`** (NEW, dispatcher): does refresh-client -S AND the
  (defer-fire | sync-preview), with the §18-correct ordering (see FINDING 5).
- **`_lp_sync_preview_to_top_match`** (REFACTORED): keeps computing `filtered[0]` (or
  `""` on empty), then delegates to `_lp_preview_follow "$_top"`. Its NAME + the 3
  top-match call sites are unchanged in SPIRIT; only the trailing explicit
  `refresh-client -S` line is removed at each (refresh moved into the dispatcher).

Resulting call-site edits:
- type/backspace/cancel-clear: DELETE the explicit `tmux refresh-client -S …` line (+ its
  now-stale comment); the `_lp_sync_preview_to_top_match` call remains.
- next/prev: REPLACE the 2 lines (`preview.sh "$target"` + `refresh-client -S`) with
  `_lp_preview_follow "$target"`.

## FINDING 5 — Refresh-vs-preview ordering (PRD §18.1/§18.2)

PRD §18.1 (typing): "does exactly two things synchronously: update filter/index, then
refresh-client -S." §18.2 (nav): "update index + refresh-client -S immediately; preview
deferred." Q6's comment also shows `set filter/index, refresh-client -S, THEN _lp_fire_preview`.

So for **defer=on**: `refresh-client -S` runs FIRST (synchronous status redraw — the
latency priority), THEN the background preview fires. `_lp_fire_preview` does NO
synchronous preview work (only state writes + a non-blocking `-b` launch), so inserting
it after refresh keeps the typing path "status-only + synchronous" per §18.1.

For **defer=off** (legacy): the synchronous preview runs FIRST, THEN refresh —
byte-for-byte the pre-§18 order. `_lp_preview_follow`'s `else` branch preserves this.
The end-state is identical either way; only the ordering differs (and ordering matters
only for the defer path's latency goal).

## FINDING 6 — CRITICAL: the default-`on` change BREAKS `test_functional.sh` (async race)

`test_functional.sh` asserts **synchronously** on `@livepicker-linked-id` immediately
after `input-handler.sh` actions (grep: 8 such asserts in that file; `test_preview.sh`'s
7 call `preview.sh` DIRECTLY and are unaffected; the other test files have 0):

```bash
"$LIVEPICKER_SCRIPTS/input-handler.sh" next-session
assert_eq "$(tmux show-option -gqv @livepicker-linked-id)" "$alpha_wid" …   # RACE
```

With defer=on, `next-session` → `_lp_preview_follow` → `_lp_fire_preview` launches a
**non-blocking** `run-shell -b` job and returns; the assertion's `tmux show-option` then
runs BEFORE the background `preview.sh` has linked the window → sees the STALE
`linked-id` → **FAIL**. This is a guaranteed race (the `-b` job must source libs, read
state, list-windows, unlink, link, select — far slower than one `show-option`).

Distribution (grep): test_functional.sh=8 (all the at-risk ones), test_preview.sh=7
(direct preview.sh — safe), test_create/restore/pollution/keyrepurpose/self=0.

**Resolution (deterministic, minimal): pin `@livepicker-preview-defer off` in the shared
per-test `setup_test` (`tests/helpers.sh`).** Every existing test then runs the
synchronous path it was written for → stays green and deterministic. The deferred path is
validated by (a) THIS task's throwaway smoke (sets defer=on, polls for the link) and
(b) the dedicated `tests/test_responsiveness.sh` (P1.M3.T1.S1), which sets defer=on.

Rationale for pin-over-poll: the existing suite is fully deterministic today; introducing
timeout-polling would add flakiness risk and is a larger change. The functional tests
verify mode-independent END-STATE correctness (the right window links) — identical on
sync or async — so running them defer=off loses no correctness coverage; the DISTINCT
defer behaviors (async timing, supersede, no-backlog) belong to test_responsiveness.sh.
Documented tradeoff: defer-on through input-handler has no committed coverage until
P1.M3.T1.S1 lands, hence the thorough throwaway smoke in this task.

`setup_test` is a thin delegate: `setup_test() { setup_socket "${1:-}"; }`. After
`setup_socket` the isolated server is up, so `tmux set-option -g @livepicker-preview-defer
off` applies to that server. `clear_all_state` preserves §11 config (CORRECTION A), so the
pin survives the picker lifetime within a test; each test gets a fresh server (fresh
default `on`), so the pin must be in `setup_test` (per-test), not at file scope.

## FINDING 7 — Empty-target guard ("schedule nothing for a non-existent target")

- Nav: `next`/`prev` return early on `[ "$L" -eq 0 ]`, so `target` is always non-empty
  when `_lp_preview_follow` is reached. The guard is belt-and-braces there.
- Top-match: `_lp_sync_preview_to_top_match` sets `_top=""` when `filtered` is empty;
  `_lp_preview_follow ""` → defer-on: `refresh-client -S` (status redraws, showing the
  empty filtered list) then `_lp_fire_preview ""` → empty-guard → no-op (prior preview
  left as-is). defer-off: `[ -n "" ]` false → skip preview, then refresh. Matches the
  contract's "leave the prior preview as-is."

## FINDING 8 — Confirm independence (§18 contract #4) is ALREADY satisfied

The confirm branch resolves target from authoritative `@livepicker-filter` /
`@livepicker-index` (set synchronously by type/nav), NOT from `@livepicker-linked-id`.
It never calls preview.sh. So "type and Enter within ~100ms, before any preview ran"
works by construction — confirm does not depend on the background job. This task does
NOT touch confirm. (Verified in the live confirm branch + codebase_state.md §6.)

## FINDING 9 — Quoting for `run-shell -b`

The codebase's established run-shell form (key bindings, livepicker.sh:326) is
`run-shell "$CURRENT_DIR/input-handler.sh type $lp_c"` — `$CURRENT_DIR` UNQUOTED within
the double-quoted command string. Q6's reference uses the SAME shape:
`"$CURRENT_DIR/preview.sh '$1' '$seq'"`. So `_lp_fire_preview` uses
`tmux run-shell -b "$CURRENT_DIR/preview.sh '$target' '$seq'"` — single-quote the TARGET
(handles session names with spaces; matches Q6 + the binding convention). A pathological
single-quote in a session name would break this, but (a) the contract specifies
single-quote wrapping, (b) it matches the reference + codebase convention, (c) such names
are exotic and tmux itself constrains them. NOT separately single-quoting the path keeps
consistency with the existing key-binding form (the plugin dir has no spaces in practice).

## FINDING 10 — Disjoint from the parallel P1.M2.T2.S1 (preview.sh)

P1.M2.T2.S1 edits `scripts/preview.sh` ONLY (already landed). This task edits
`scripts/input-handler.sh` + `tests/helpers.sh` (setup_test pin). No shared file → no
edit collision. The producer/consumer contract is: this task passes `$2` (seq);
preview.sh (already done) re-checks it.

## FINDING 11 — Style / set -u / shellcheck

input-handler.sh has `set -u` (inherited from sourced libs; NOT re-declared). All new
locals (`target`, `seq`, `_top`) are declared `local`. TAB indent throughout (shfmt NOT
installed). The file has `shellcheck disable=SC1091,SC2153` (sourced libs + STATE_*
readonlys); the new code adds no new shellcheck concerns (the `run-shell` string is
intentionally built with embedded single quotes — SC2086 does not fire because the whole
command is ONE double-quoted argument to tmux, exactly like the key-binding lines).

## FINDING 12 — Validation plan (throwaway smoke; no committed test in THIS subtask)

The committed §18 test is P1.M3.T1.S1 (`test_responsiveness.sh`, sets defer=on). This
task validates via a throwaway smoke (deleted after) that:
1. defer=ON, `input-handler.sh type a` → `@livepicker-preview-seq` bumped (≥1) AND
   (poll) `@livepicker-linked-id` reaches the top match's window (deferred fire worked).
2. defer=ON, `next-session` → (poll) target window linked.
3. defer=ON, type a non-matching char → no preview fired (linked-id unchanged) — empty guard.
4. defer=OFF → `next-session` links synchronously (no poll needed) — legacy preserved.
Plus `tests/run.sh` stays green (existing tests run defer=off via the setup_test pin).
