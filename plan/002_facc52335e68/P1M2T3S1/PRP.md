# PRP — P1.M2.T3.S1: Centralize deferred-preview fire helper + rewire type/backspace/nav/cancel-clear call sites (PRD §18)

> **Scope**: The PRODUCER side of §18 (deferred preview). Adds `_lp_fire_preview`
> (bumps `STATE_PREVIEW_SEQ`, writes `STATE_PREVIEW_TARGET`, launches a background,
> supersedeable `run-shell -b preview.sh '<target>' '<seq>'`) and a single defer-aware
> dispatcher `_lp_preview_follow`, then rewires the 5 input-handler call sites so that
> when `@livepicker-preview-defer=on` (the default) typing/backspace/cancel-clear/nav
> redraw the status **synchronously** and **defer** the preview to the background job,
> while `off` restores the legacy synchronous path byte-for-byte. The CONSUMER
> (preview.sh's `expected_seq` supersede guard — P1.M2.T2.S1) is **already landed**.
> Confirm and the cancel full-exit are UNCHANGED (already §18-compliant). Also pins
> `@livepicker-preview-defer off` in the shared `setup_test` so the existing
> synchronous-assertion test suite stays green and deterministic (the deferred path is
> validated by the dedicated `tests/test_responsiveness.sh`, P1.M3.T1.S1, + this task's
> throwaway smoke).

---

## Goal

**Feature Goal**: Implement PRD §18's interaction-first contract in `input-handler.sh`:
the status line tracks every keystroke/nav **synchronously** (filter/index +
`refresh-client -S`), and the live preview is **deferred** to a background
`run-shell -b` job that is **supersedeable** (only the latest target's job mutates; a
late/overtaken job no-ops in preview.sh). When `@livepicker-preview-defer=off`, the
pre-§18 synchronous-preview path is restored byte-for-byte. Confirm never blocks on a
preview (already true; untouched).

**Deliverable**: Edits to TWO files — **no new files**.
1. `scripts/input-handler.sh`:
   - ADD `_lp_fire_preview "$target"` (low-level background fire; contract-required).
   - ADD `_lp_preview_follow "$target"` (the defer-aware refresh+preview dispatcher).
   - REFACTOR `_lp_sync_preview_to_top_match` to compute `filtered[0]` (or `""`) and
     delegate to `_lp_preview_follow`.
   - REWIRE the 5 call sites: type/backspace/cancel-clear drop their explicit
     `refresh-client -S` (now inside the dispatcher); next/prev replace
     `preview.sh "$target"` + `refresh-client -S` with `_lp_preview_follow "$target"`.
2. `tests/helpers.sh`: pin `@livepicker-preview-defer off` in `setup_test` (so the
   existing suite stays green + deterministic; `test_responsiveness.sh` opts into `on`).

**Success Definition**:
- defer=on (default): after `type`/`backspace`/`cancel-clear`, `@livepicker-filter` +
  `@livepicker-index` are set and `refresh-client -S` runs **synchronously**;
  `@livepicker-preview-seq` is bumped, `@livepicker-preview-target` is the new top match,
  and a background `preview.sh '<top>' '<seq>'` is launched (proven by polling
  `@livepicker-linked-id` to the top match's window). After `next`/`prev`, ditto for the
  highlighted `$target`.
- defer=off: `preview.sh "$target"` runs synchronously (one arg, no seq) THEN
  `refresh-client -S` — byte-for-byte the pre-§18 behavior.
- Empty filtered list (no top match): NO preview fires (prior preview left as-is); the
  status still redraws.
- `tests/run.sh` stays green (existing tests run defer=off via the `setup_test` pin).
- Confirm reads authoritative filter/index and never blocks on a preview (unchanged).

## User Persona (if applicable)

**Target User**: The end user typing quickly / tab-moving fast in the picker. Also the
maintainer / QA (defer=off is the diagnostic escape hatch).

**Use Case**: The user opens the picker, hammers 3 letters within ~100 ms, and presses
Enter — landing in the target session with zero perceived lag, because each keystroke
only redraws the status (synchronous, cheap) and the expensive preview re-link is
deferred + superseded to a single trailing background job.

**Pain Points Addressed**: Today every keystroke runs `unlink-window`+`link-window`+
`select-window` **synchronously** before the status redraw, so fast typing waits on each
letter's preview round-trip (PRD §18 "Root cause"). Confirm could stall on a preview.
The fix decouples preview work from the input path.

## Why

- **PRD §18 is explicit**: typing is status-only + synchronous; nav is sync-highlight +
  deferred-preview; the preview is deferred and supersedeable; confirm never blocks.
- **The supersede CONSUMER is already done** (P1.M2.T2.S1 landed: `preview.sh <t> <seq>`
  no-ops on a stale seq). This task is the missing PRODUCER — without it, no one fires a
  background job with a seq, so the guard is inert and typing is still synchronous.
- **`run-shell -b` is non-cancellable** (Q5): a late job cannot be killed mid-flight, so
  it MUST be made a no-op by the seq re-check in preview.sh. `_lp_fire_preview` tags each
  job with the seq-at-fire; preview.sh re-reads the live seq and bails if a newer target
  won (research FINDING 3/10).
- **Teardown-safe by construction** (Q6): `clear_all_state` unsets `STATE_PREVIEW_SEQ`
  (it's in `_STATE_RUNTIME_KEYS`, P1.M2.T1.S1), so a late `-b` job post-cancel/confirm
  reads the `"0"` default ≠ its captured seq → no-op (never clobbers the restored window).
- **Cheap, surgical, low-risk**: 2 new helpers + 1 refactored + 5 single-line call-site
  edits + 1 harness pin. No new file, no sourcing change, no state-key change, no driver
  change. defer=off is the unchanged legacy branch. Confirm is untouched.
- **Disjoint from parallel work**: P1.M2.T2.S1 (preview.sh, already landed) and
  P1.M1.T3.S1 (renderer.sh, if still in flight) touch no file this task touches.

## What

1. **`_lp_fire_preview "$target"`** (NEW): empty-guard → `seq=$(get_state SEQ 0); seq=$((seq+1))`
   → `set_state SEQ $seq` → `set_state TARGET "$target"` →
   `tmux run-shell -b "$CURRENT_DIR/preview.sh '$target' '$seq'"`.
2. **`_lp_preview_follow "$target"`** (NEW): if `opt_preview_defer=on` →
   `refresh-client -S` (sync status first) then `_lp_fire_preview "$target"`; else →
   `[ -n "$target" ] && preview.sh "$target"` (sync) then `refresh-client -S`.
3. **`_lp_sync_preview_to_top_match`** (REFACTOR): compute `_top="${_sync_filtered[0]}"`
   (or `""` when empty), then `_lp_preview_follow "$_top"`.
4. **Call sites**: type/backspace/cancel-clear drop the explicit `refresh-client -S`;
   next/prev call `_lp_preview_follow "$target"`.
5. **`tests/helpers.sh::setup_test`**: pin `@livepicker-preview-defer off`.
6. **Do NOT change**: confirm, cancel full-exit, `_confirm_land_on_session`, the
   activation first-preview (stays synchronous — §18 mechanism note), `preview.sh`,
   `options.sh`, `state.sh`, `livepicker.sh`, any state shape, or any other script.

### Success Criteria

- [ ] `_lp_fire_preview` present; bumps `STATE_PREVIEW_SEQ`, sets `STATE_PREVIEW_TARGET`,
      fires `run-shell -b "$CURRENT_DIR/preview.sh '$target' '$seq'"`; no-op on empty target.
- [ ] `_lp_preview_follow` present; defer=on does refresh-then-fire; defer=off does
      sync-preview-then-refresh.
- [ ] `_lp_sync_preview_to_top_match` delegates to `_lp_preview_follow` (no direct
      `preview.sh` call remains in it).
- [ ] type/backspace/cancel-clear no longer call `refresh-client -S` directly (the 3
      explicit lines removed); next/prev call `_lp_preview_follow "$target"`.
- [ ] confirm + cancel full-exit + activation first-preview UNCHANGED.
- [ ] `setup_test` pins `@livepicker-preview-defer off`.
- [ ] defer=on smoke: type/nav bumps seq + (poll) links the right window; empty-match
      fires nothing; defer=off links synchronously.
- [ ] `bash -n` + `shellcheck` clean; `tests/run.sh` green (exit 0).

## All Needed Context

### Context Completeness Check

_Pass_: an implementer who has never seen this repo can do it from (a) the verbatim
old→new code blocks (anchored on unique content), (b) the refresh-ordering rule
(FINDING 5), (c) the test-breakage consequence + the `setup_test` pin (FINDING 6), and
(d) the throwaway smoke. All dependencies are confirmed landed (FINDING 1). The
producer/consumer seam (`$2` seq ↔ preview.sh guard) is fully specified.

### Documentation & References

```yaml
# MUST READ — the empirical ground-truth for THIS task (12 live-verified findings)
- docfile: plan/002_facc52335e68/P1M2T3S1/research/defer_fire_findings.md
  why: FINDING 1 (deps all landed, incl. preview.sh guard); FINDING 2 (5 call sites
       exact); FINDING 3 (Q6 reference helper + the TARGET write); FINDING 4 (the 3-helper
       design); FINDING 5 (refresh-vs-preview ordering); FINDING 6 (CRITICAL test-breakage
       + the setup_test pin); FINDING 7 (empty-target guard); FINDING 8 (confirm already
       independent); FINDING 9 (run-shell quoting); FINDING 10 (disjoint from preview.sh);
       FINDING 11 (set -u/TABs/shellcheck); FINDING 12 (validation plan).
  critical: FINDING 6 is the load-bearing one — WITHOUT the setup_test pin, tests/run.sh
            FAILS (test_functional.sh's synchronous linked-id asserts race the async job).

# MUST READ — the dependency CONTRACT (treat as implemented exactly)
- docfile: plan/002_facc52335e68/P1M2T2S1/PRP.md
  why: P1.M2.T2.S1 (already landed) made preview.sh accept `preview.sh <target>
       [expected_seq]` and NO-OP when the seq is stale (guard before the mode-gate + a
       2nd guard before the unlink). THIS task's `_lp_fire_preview` passes `$2=<seq>` —
       that is the producer side of the seam. preview.sh with ONE arg (defer=off /
       activation first-preview) is guard-skipped (unchanged).
  critical: the seq THIS task bumps at fire time is the SAME seq preview.sh re-reads;
            clear_all_state unsets it on teardown (STATE_PREVIEW_SEQ is in
            _STATE_RUNTIME_KEYS — P1.M2.T1.S1), so a late post-teardown job no-ops.

# MUST READ — the option/key foundation (already landed)
- docfile: plan/002_facc52335e68/P1M2T1S1/PRP.md
  why: defines opt_preview_defer() (default "on"), STATE_PREVIEW_SEQ,
       STATE_PREVIEW_TARGET, both in _STATE_RUNTIME_KEYS, and the seq=0 init at activate.
       THIS task READS opt_preview_defer (the dispatcher branch) and READS+WRITES both
       STATE_PREVIEW_* (the fire helper).
  section: "What" (the 3 edits), "Downstream contract this foundation enables"

# MUST READ — the supersede rationale (WHY the seq + the teardown safety)
- docfile: plan/002_facc52335e68/architecture/external_tmux_behavior.md
  why: Q5 (run-shell -b is detached/non-blocking/NOT cancellable — a late job must no-op
       via the seq); Q6 (the monotonic @livepicker-preview-seq pattern + the REFERENCE
       _lp_fire_preview + the "type/backspace: set filter/index, refresh-client -S, THEN
       _lp_fire_preview" ordering + the teardown gotcha + the debounce note).
  section: "Q5", "Q6"

# MUST READ — the authoritative current structure of input-handler.sh (the call sites)
- docfile: plan/002_facc52335e68/architecture/codebase_state.md
  why: §6 documents _lp_sync_preview_to_top_match (130-138) + the 5 call sites (type 172,
       backspace 210, cancel-clear 400, next 246, prev 265) + the §18 rework impact note
       ("centralize the bump+call"). NOTE: line numbers drift ~1 — anchor edits on CONTENT.
  section: "§6 input-handler.sh"

# MUST READ — the file being edited (the helper block + the 5 call sites)
- file: scripts/input-handler.sh
  why: Contains _lp_sync_preview_to_top_match (130-138) + input_main's case branches.
        CURRENT_DIR (line 51) is the house path var; opt_preview_defer / get_state /
        set_state are sourced (options.sh/utils.sh/state.sh, lines 53-60).
  pattern: the existing `_lp_sync_preview_to_top_match` is the natural anchor for the new
           helpers (place _lp_fire_preview + _lp_preview_follow right after it). Nav's
           `"$CURRENT_DIR/preview.sh" "$target" 2>/dev/null || true` is the anchor for the
           _lp_preview_follow swap. TAB indent (2 tabs for type/backspace/next/prev;
           3 tabs for cancel-clear inside its `if`).
  gotcha: next + prev have IDENTICAL preview+refresh lines — disambiguate the edits with
          each branch's UNIQUE preceding context (next: the "Guard a mid-nav failure"
          comment; prev: the `target="${filtered[$new_idx]}"` line). The "Sync the live
          preview..." comment is shared by type/backspace/cancel-clear — anchor each on its
          UNIQUE trailing refresh comment.

# MUST READ — the test-harness pin site (setup_test) + why it is MANDATORY
- file: tests/helpers.sh
  why: setup_test (line 84) is the per-test setup EVERY test calls (thin delegate to
        setup_socket). The default `@livepicker-preview-defer=on` would race
        test_functional.sh's synchronous @livepicker-linked-id asserts (research FINDING
        6). Pinning `off` here makes the whole suite deterministic on the sync path;
        test_responsiveness.sh (P1.M3.T1.S1) sets it back to `on`.
  gotcha: each test runs in a FRESH server (per-test socket), so the pin MUST be in
          setup_test (runs per test), not at file source-time. clear_all_state preserves
          §11 config, so the pin survives the picker lifetime within a test.

# Reference — PRD §18 (the feature spec) + §16 (concurrency risk)
- docfile: PRD.md
  why: §18 contract (typing status-only sync; nav sync-highlight + deferred preview;
       preview deferred + supersedeable via a sequence; a short debounce MAY gate the
       fire; confirm never blocks). §16 "Deferred-preview concurrency" mandates the guard.
  section: "§18 Responsiveness", "§16 Deferred-preview concurrency"
```

### Current Codebase tree

```bash
tmux-livepicker/
  scripts/
    input-handler.sh   # MODIFY: +_lp_fire_preview, +_lp_preview_follow, refactor _lp_sync_preview_to_top_match, rewire 5 call sites
    preview.sh          # UNCHANGED (P1.M2.T2.S1 landed: expected_seq + supersede guard — the CONSUMER)
    options.sh          # UNCHANGED (opt_preview_defer landed — READ by _lp_preview_follow)
    state.sh            # UNCHANGED (STATE_PREVIEW_* landed — READ+WRITTEN by _lp_fire_preview)
    livepicker.sh       # UNCHANGED (seq=0 init landed; activation first-preview stays synchronous)
    utils.sh, filter.sh, renderer.sh, restore.sh, plugin.tmux   # UNCHANGED
  tests/
    helpers.sh          # MODIFY: setup_test pins @livepicker-preview-defer off (keep existing suite green)
    test_functional.sh  # UNCHANGED (runs defer=off via the pin → stays green)
    test_responsiveness.sh  # (does NOT exist yet — P1.M3.T1.S1 writes it, sets defer=on)
    run.sh, setup_socket.sh, test_*.sh (others)   # UNCHANGED
```

### Desired Codebase tree with files to be added and responsibility of file

```bash
scripts/input-handler.sh  # +_lp_fire_preview (bg fire) + _lp_preview_follow (defer-aware dispatch);
                           #   _lp_sync_preview_to_top_match delegates; 5 call sites rewired
tests/helpers.sh          # setup_test: pin @livepicker-preview-defer off (deterministic existing suite)
```

### Known Gotchas of our codebase & Library Quirks

```bash
# CRITICAL (research FINDING 6): the default `on` BREAKS tests/run.sh. test_functional.sh
# asserts @livepicker-linked-id SYNCHRONOUSLY right after input-handler actions; the async
# run-shell -b job races those asserts. The setup_test pin (defer=off) is MANDATORY —
# without it the suite goes red. Do NOT skip it.

# CRITICAL (research FINDING 5): on defer=on, refresh-client -S runs FIRST (synchronous
# status redraw — §18.1/§18.2 latency priority), THEN _lp_fire_preview. _lp_fire_preview
# does NO synchronous preview work (only state writes + a non-blocking -b launch), so the
# typing path stays "status-only + synchronous". On defer=off the legacy order (sync
# preview THEN refresh) is preserved byte-for-byte. Do NOT reorder the else branch.

# CRITICAL (contract): confirm + cancel full-exit + activation first-preview are
# UNCHANGED. Confirm already resolves the target from authoritative filter/index and never
# reads @livepicker-linked-id, so "type and Enter before any preview" works by construction
# (§18 contract #4). Do NOT touch confirm.

# GOTCHA (research FINDING 4): centralize the defer logic in ONE dispatcher
# (_lp_preview_follow) — do NOT inline `if opt_preview_defer …` at each of the 5 sites
# (duplication + easy to get the refresh ordering wrong). The 3 top-match sites keep
# calling _lp_sync_preview_to_top_match (now defer-aware via delegation); the 2 nav sites
# call _lp_preview_follow directly.

# GOTCHA: next + prev have IDENTICAL `preview.sh "$target"` + `refresh-client -S` lines —
# when editing, anchor on each branch's UNIQUE context (next: the "Guard a mid-nav failure"
# comment above; prev: the `target="${filtered[$new_idx]}"` line above) so the edit tool
# matches the right occurrence. The shared "Sync the live preview..." comment above the 3
# top-match sites is NOT unique — anchor each on its UNIQUE trailing refresh comment.

# GOTCHA (research FINDING 7): empty target -> schedule nothing. _lp_fire_preview guards
# `[ -z "$target" ] && return 0`. Nav never reaches the dispatcher with an empty target
# (it returns on `[ "$L" -eq 0 ]`). Top-match passes "" when filtered is empty -> the
# dispatcher redraws the status but fires no preview (prior preview left as-is).

# GOTCHA (research FINDING 9): quote the target with SINGLE quotes inside the double-quoted
# run-shell command: "$CURRENT_DIR/preview.sh '$target' '$seq'". This matches the Q6
# reference AND the codebase's key-binding run-shell form (livepicker.sh:326). It handles
# session names with spaces. Do NOT separately single-quote the path (stay consistent with
# the binding convention; the plugin dir has no spaces in practice).

# GOTCHA: _lp_sync_preview_to_top_match's return value is not checked by callers (they call
# it on its own line). After refactor it delegates to _lp_preview_follow and falls through;
# that is fine. Do NOT add an explicit `return` that would mask the legacy refresh.

# GOTCHA (research FINDING 10): DISJOINT from P1.M2.T2.S1 (preview.sh). This task edits
# input-handler.sh + helpers.sh only. The producer ($2=seq) ↔ consumer (preview.sh guard)
# contract is already satisfied (preview.sh landed).

# STYLE: TAB indent (2 tabs for type/backspace/next/prev; 3 tabs for cancel-clear inside
# its `if`). set -u inherited — declare every new local. shfmt NOT installed. The file's
# shellcheck disable=SC1091,SC2153 covers sourced libs + STATE_*; the new run-shell string
# is ONE double-quoted arg to tmux (like the key-binding lines) — no new SC concern.
```

## Implementation Blueprint

### Data models and structure

No data-model change. The "model" is the producer side of the supersede seam + a
defer-aware dispatch decision:

```
_lp_sync_preview_to_top_match()         # top-match entry (type/backspace/cancel-clear)
 ├─ filtered = lp_build_filtered(LIST, FILTER)
 ├─ _top = filtered[0]  (or "" if empty)
 └─ _lp_preview_follow "$_top"

_lp_preview_follow(target)              # THE dispatcher (nav calls this directly too)
 ├─ if opt_preview_defer == "on":
 │     refresh-client -S        # status FIRST (synchronous, §18.1/§18.2)
 │     _lp_fire_preview target  # background, supersedeable
 └─ else (legacy):
       [ -n target ] && preview.sh target   # synchronous (one arg -> guard skipped)
       refresh-client -S

_lp_fire_preview(target)                # low-level (contract-required)
 ├─ [ -z target ] && return 0
 ├─ seq = get_state(SEQ,"0") + 1 ; set_state SEQ seq ; set_state TARGET target
 └─ tmux run-shell -b "$CURRENT_DIR/preview.sh '$target' '$seq'"
```

### Implementation Tasks (ordered by dependencies)

```yaml
Task 1: MODIFY scripts/input-handler.sh — refactor _lp_sync_preview_to_top_match + add the 2 helpers
  - LOCATE _lp_sync_preview_to_top_match()'s body (the anchor — content, ~line 130-138).
  - REPLACE its body so it computes _top (filtered[0] or "") and delegates to
    _lp_preview_follow, AND append the two new helpers (_lp_fire_preview,
    _lp_preview_follow) immediately after the closing `}`. Verbatim old→new in
    "Implementation Patterns" (Task 1 block).
  - WHY: one place for the defer logic; the 3 top-match sites keep calling
    _lp_sync_preview_to_top_match unchanged in spirit.
  - DEPENDS ON: opt_preview_defer, STATE_PREVIEW_SEQ, STATE_PREVIEW_TARGET (all landed).
  - STYLE: TAB indent (column 0 for the function defs — same as _lp_sync_preview_to_top_match).

Task 2: MODIFY scripts/input-handler.sh — rewire the type + backspace + cancel-clear call sites
  - At each of the 3 sites, DELETE the explicit `tmux refresh-client -S 2>/dev/null || true`
    line AND its now-stale "# Force the #() renderer to re-run ..." comment block (refresh
    moved into _lp_preview_follow). KEEP the `_lp_sync_preview_to_top_match` call.
  - 3 edits (anchored on each branch's UNIQUE refresh comment). Verbatim in
    "Implementation Patterns" (Task 2a/2b/2c). NOTE cancel-clear is 3-TAB indented.

Task 3: MODIFY scripts/input-handler.sh — rewire the next-session + prev-session call sites
  - At each, REPLACE the 2 lines (`"$CURRENT_DIR/preview.sh" "$target" 2>/dev/null || true`
    + `tmux refresh-client -S 2>/dev/null || true`) with a single
    `_lp_preview_follow "$target"`.
  - 2 edits (anchored on each branch's UNIQUE preceding context — see gotchas). Verbatim
    in "Implementation Patterns" (Task 3a/3b).

Task 4: MODIFY tests/helpers.sh — pin @livepicker-preview-defer off in setup_test
  - LOCATE setup_test() (line ~84): `setup_test() { setup_socket "${1:-}"; }`.
  - ADD after setup_socket: `tmux set-option -g @livepicker-preview-defer off 2>/dev/null || true`
    + a comment (verbatim in "Implementation Patterns", Task 4).
  - WHY: research FINDING 6 — keeps the existing synchronous-assertion suite green +
    deterministic. test_responsiveness.sh (P1.M3.T1.S1) sets it back to on.

Task 5: VALIDATE (throwaway smoke + full suite)
  - RUN: bash -n scripts/input-handler.sh tests/helpers.sh ; shellcheck both.
  - RUN: the defer-on/defer-off throwaway smoke (Validation Loop L2) — polls
    @livepicker-linked-id to prove the deferred fire links the right window; proves the
    empty-match guard; proves defer=off links synchronously. DELETE after.
  - RUN: tests/run.sh (expect green — existing tests run defer=off via the Task 4 pin).
```

### Implementation Patterns & Key Details

> All anchors are CONTENT-based (line numbers drift ~1). Indent is TABS: 2 tabs for the
> type/backspace/next/prev bodies, 3 tabs for cancel-clear (inside its `if`). Match the
> file's tabs EXACTLY in the `edit` tool's `oldText`.

**Task 1 — refactor `_lp_sync_preview_to_top_match` + add `_lp_fire_preview` +
`_lp_preview_follow`.** CURRENT (the whole function, column 0):

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
→ REPLACE WITH (refactored body + the two new helpers, column 0):

```bash
_lp_sync_preview_to_top_match() {
	local _list _filt _top
	local -a _sync_filtered=()
	_list="$(get_state "$STATE_LIST" "")"
	_filt="$(get_state "$STATE_FILTER" "")"
	mapfile -t _sync_filtered < <(lp_build_filtered "$_list" "$_filt")
	if [ "${#_sync_filtered[@]}" -eq 0 ]; then
		_top=""
	else
		_top="${_sync_filtered[0]}"
	fi
	# Delegate redraw + (deferred | synchronous) preview to _lp_preview_follow. Empty
	# filtered list -> _top="" -> no preview fires (leave the prior pane as-is).
	_lp_preview_follow "$_top"
}

# _lp_fire_preview TARGET — schedule a background, supersedeable preview of TARGET
# (PRD §18; external_tmux_behavior.md Q6). Bumps the monotonic STATE_PREVIEW_SEQ,
# records STATE_PREVIEW_TARGET, then launches preview.sh detached via run-shell -b
# (non-blocking — Q5). The job re-checks the seq in preview_main (P1.M2.T2.S1) and
# NO-OPS if a newer keystroke/nav won, so a late/superseded job never clobbers the
# current link (and clear_all_state unsets the seq on teardown -> a post-teardown
# job reads "0" != its seq -> no-op). No-op on an empty TARGET (no top match).
_lp_fire_preview() {
	local target="${1:-}" seq
	[ -z "$target" ] && return 0
	seq="$(get_state "$STATE_PREVIEW_SEQ" "0")"
	seq=$(( seq + 1 ))
	set_state "$STATE_PREVIEW_SEQ" "$seq"
	set_state "$STATE_PREVIEW_TARGET" "$target"
	# Absolute path (the server's cwd is NOT the plugin dir); bash shebang honored
	# under run-shell (Q5). Single-quote the target so session names with spaces
	# survive (matches the key-binding run-shell form, livepicker.sh:326).
	tmux run-shell -b "$CURRENT_DIR/preview.sh '$target' '$seq'"
}

# _lp_preview_follow TARGET — redraw the status line AND sync the preview to the
# current selection, honoring @livepicker-preview-defer (PRD §18.1/§18.2). Used by
# the nav branches (explicit TARGET) and by _lp_sync_preview_to_top_match (top match).
# defer=on: refresh-client -S FIRST (synchronous, latency-priority status redraw),
#   THEN the preview fires in the background (_lp_fire_preview does NO synchronous
#   preview work — only state writes + a non-blocking -b launch).
# defer=off (legacy): synchronous preview FIRST (one arg -> preview.sh guard skipped),
#   THEN refresh-client -S — byte-for-byte the pre-§18 order.
# Empty TARGET -> skip the preview, still redraw (leave the prior pane as-is).
_lp_preview_follow() {
	local target="${1:-}"
	if [ "$(opt_preview_defer)" = "on" ]; then
		tmux refresh-client -S 2>/dev/null || true
		_lp_fire_preview "$target"
	else
		[ -n "$target" ] && { "$CURRENT_DIR/preview.sh" "$target" 2>/dev/null || true; }
		tmux refresh-client -S 2>/dev/null || true
	fi
}
```

**Task 2a — type branch** (2-tab indent). CURRENT:

```bash
		_lp_sync_preview_to_top_match
		# Force the #() renderer to re-run (PRD §10/§16). Requires a client
		# (production always has one); guard the detached edge (FINDING 3).
		tmux refresh-client -S 2>/dev/null || true
```
→ REPLACE WITH:

```bash
		_lp_sync_preview_to_top_match
```

**Task 2b — backspace branch** (2-tab indent). CURRENT:

```bash
		_lp_sync_preview_to_top_match
		# Force the #() renderer to re-run (PRD §10/§16). Guard the detached
		# edge (FINDING 3; mirror the `type` branch / restore.sh STEP 6c).
		tmux refresh-client -S 2>/dev/null || true
```
→ REPLACE WITH:

```bash
		_lp_sync_preview_to_top_match
```

**Task 2c — cancel-clear branch** (3-tab indent, inside `if [ -n "$cur_filter" ]`). CURRENT:

```bash
			_lp_sync_preview_to_top_match
			# Force the #() renderer to re-run so the picker redraws with the
			# empty query + the full list (PRD §10/§16). Guard the detached edge
			# (mirror backspace / type / restore.sh STEP 6c).
			tmux refresh-client -S 2>/dev/null || true
```
→ REPLACE WITH:

```bash
			_lp_sync_preview_to_top_match
```

**Task 3a — next-session branch** (2-tab indent). CURRENT:

```bash
		# NEVER client-session-changed (Invariant A). Guard a mid-nav failure
		# (session gone) so nav still advances + redraws.
		"$CURRENT_DIR/preview.sh" "$target" 2>/dev/null || true
		tmux refresh-client -S 2>/dev/null || true
```
→ REPLACE WITH:

```bash
		# NEVER client-session-changed (Invariant A). _lp_preview_follow redraws +
		# (deferred | sync) preview; guard a mid-nav failure (session gone).
		_lp_preview_follow "$target"
```

**Task 3b — prev-session branch** (2-tab indent). CURRENT:

```bash
		set_state "$STATE_INDEX" "$new_idx"
		target="${filtered[$new_idx]}"
		"$CURRENT_DIR/preview.sh" "$target" 2>/dev/null || true
		tmux refresh-client -S 2>/dev/null || true
```
→ REPLACE WITH:

```bash
		set_state "$STATE_INDEX" "$new_idx"
		target="${filtered[$new_idx]}"
		_lp_preview_follow "$target"
```

**Task 4 — `tests/helpers.sh::setup_test` pin.** CURRENT:

```bash
setup_test() {
	setup_socket "${1:-}"
}
```
→ REPLACE WITH:

```bash
setup_test() {
	setup_socket "${1:-}"
	# PRD §18: the shipped default is @livepicker-preview-defer=on (background
	# run-shell -b preview). That makes the existing functional/restore/etc. tests'
	# SYNCHRONOUS @livepicker-linked-id assertions race the async job (they assert
	# immediately after input-handler.sh type/next/backspace). Pin OFF here so the
	# whole suite stays deterministic on the synchronous path it was written for;
	# the deferred path is validated by tests/test_responsiveness.sh (P1.M3.T1.S1),
	# which sets @livepicker-preview-defer back to ON. (Per-test: each test gets a
	# fresh server; clear_all_state preserves §11 config so the pin holds for the
	# picker lifetime within a test.)
	tmux set-option -g @livepicker-preview-defer off 2>/dev/null || true
}
```

### Integration Points

```yaml
CODE:
  - file: scripts/input-handler.sh
    change: "+_lp_fire_preview (bg fire, bumps SEQ + sets TARGET + run-shell -b);
             +_lp_preview_follow (defer-aware refresh+preview dispatcher);
             _lp_sync_preview_to_top_match delegates to _lp_preview_follow;
             5 call sites rewired (type/backspace/cancel-clear drop refresh; next/prev
             call _lp_preview_follow)"
    invariant: "defer=on -> status redraw synchronous + preview deferred/supersedeable;
               defer=off -> legacy sync preview + redraw (byte-identical); confirm +
               cancel-full-exit + activation-first-preview UNCHANGED"
  - file: tests/helpers.sh
    change: "setup_test pins @livepicker-preview-defer off (deterministic existing suite)"
    invariant: "tests/run.sh green; test_responsiveness.sh (P1.M3.T1.S1) opts into on"

CONSUMERS/CONTRACTS:
  - preview.sh (P1.M2.T2.S1, LANDED): consumes $2=<seq>; no-ops on stale seq; one-arg
    path (defer=off / activation) guard-skipped.
  - tests/test_responsiveness.sh (P1.M3.T1.S1, NOT yet written): sets defer=on; validates
    the async/supersede/timing behaviors. (Established contract: setup_test defaults off.)

CONFIG / DATABASE / ROUTES: none.
```

## Validation Loop

### Level 1: Syntax & Style (Immediate Feedback)

```bash
cd /home/dustin/.config/tmux/plugins/tmux-livepicker
bash -n scripts/input-handler.sh tests/helpers.sh && echo "OK: syntax"
shellcheck scripts/input-handler.sh tests/helpers.sh
# Tabs-not-spaces on the edited regions (shfmt NOT installed):
grep -nP '^ +' scripts/input-handler.sh && echo "WARN: space-indent (use tabs)" || echo "OK: tabs"
# The new helpers are present:
grep -c '^_lp_fire_preview()' scripts/input-handler.sh            # -> 1
grep -c '^_lp_preview_follow()' scripts/input-handler.sh          # -> 1
grep -c 'tmux run-shell -b "\$CURRENT_DIR/preview.sh' scripts/input-handler.sh  # -> 1  (the fire)
# _lp_sync_preview_to_top_match no longer calls preview.sh directly (delegates):
! grep -A20 '^_lp_sync_preview_to_top_match()' scripts/input-handler.sh | grep -q 'CURRENT_DIR/preview.sh' \
  && echo "OK: top-match delegates (no direct preview.sh)" || echo "FAIL"
# No explicit refresh-client -S remains in type/backspace/cancel-clear/next/prev
# (only _lp_preview_follow + _confirm/restore hold refresh calls):
grep -c 'tmux refresh-client -S' scripts/input-handler.sh    # -> 2  (both inside _lp_preview_follow)
# nav now calls _lp_preview_follow:
grep -c '_lp_preview_follow "\$target"' scripts/input-handler.sh   # -> 2  (next + prev)
# helpers.sh pin present:
grep -c '@livepicker-preview-defer off' tests/helpers.sh     # -> 1  (setup_test)
# Expected: syntax clean; shellcheck 0 NEW findings; all grep counts as shown.
```

### Level 2: Defer behavior smoke (throwaway — DELETE after; sets defer=on explicitly)

> The committed §18 test is P1.M3.T1.S1 (`test_responsiveness.sh`). This throwaway proves
> the wiring NOW. It mirrors `tests/test_functional.sh`'s real activate + input-handler
> flow, overriding the setup_test pin to `on`, and POLLS `@livepicker-linked-id` (the bg
> job is async — a short poll with a generous timeout; on a healthy socket it resolves in
> <50 ms). Run, confirm, then delete.

```bash
cat > /tmp/smoke_deferfire.sh <<'EOF'
#!/usr/bin/env bash
set -u
cd /home/dustin/.config/tmux/plugins/tmux-livepicker
source tests/setup_socket.sh
source tests/helpers.sh
pass_n=0; fail_n=0
ck() { if [ "$2" = "$3" ]; then pass_n=$((pass_n+1)); echo "  ok   $1"; else fail_n=$((fail_n+1)); echo "  FAIL $1: got[$2] want[$3]"; fi; }
# poll @livepicker-linked-id until it equals $1 (or timeout ~2s). bg job is async.
wait_linked() {
	local want="$1" i
	for i in $(seq 1 100); do
		[ "$(tmux show-option -gqv @livepicker-linked-id)" = "$want" ] && return 0
		sleep 0.02
	done
	return 1
}

setup_test "lp-smoke-deferfire"
attach_test_client
# OPT INTO the deferred path (setup_test pinned it off).
tmux set-option -g @livepicker-preview-defer on
"$LIVEPICKER_SCRIPTS/livepicker.sh"   # activate (first preview = self-session, sync)

alpha_wid="$(tmux list-windows -t =alpha -F '#{window_id}' -f '#{window_active}')"
beta_wid="$(tmux list-windows -t =beta -F '#{window_id}' -f '#{window_active}')"

# 1. type "a" -> top match alpha. seq bumps; deferred job links alpha (poll).
"$LIVEPICKER_SCRIPTS/input-handler.sh" type a
[ "$(tmux show-option -gqv @livepicker-preview-seq)" != "0" ] && ck "seq bumped on type" seq-bumped seq-bumped || ck "seq bumped on type" "$(tmux show-option -gqv @livepicker-preview-seq)" non-zero
wait_linked "$alpha_wid" && ck "deferred type links alpha" "$(tmux show-option -gqv @livepicker-linked-id)" "$alpha_wid" || { fail_n=$((fail_n+1)); echo "  FAIL deferred type did not link alpha"; }

# 2. next-session -> highlight beta; deferred job links beta (poll).
"$LIVEPICKER_SCRIPTS/input-handler.sh" next-session
wait_linked "$beta_wid" && ck "deferred next links beta" "$(tmux show-option -gqv @livepicker-linked-id)" "$beta_wid" || { fail_n=$((fail_n+1)); echo "  FAIL deferred next did not link beta"; }

# 3. type a NON-matching char -> empty filtered -> NO preview fires (linked-id unchanged).
before="$(tmux show-option -gqv @livepicker-linked-id)"
"$LIVEPICKER_SCRIPTS/input-handler.sh" type ZZZZZ   # no session matches
sleep 0.3   # give any stray -b job time to (not) run
ck "empty-match leaves preview as-is" "$(tmux show-option -gqv @livepicker-linked-id)" "$before"

# 4. defer=OFF -> next-session links SYNCHRONOUSLY (no poll needed).
tmux set-option -g @livepicker-preview-defer off
"$LIVEPICKER_SCRIPTS/input-handler.sh" next-session   # wraps to alpha
ck "defer-off sync link" "$(tmux show-option -gqv @livepicker-linked-id)" "$alpha_wid"

# cancel to tear down cleanly.
"$LIVEPICKER_SCRIPTS/input-handler.sh" cancel >/dev/null 2>&1 || true
teardown_test
echo "pass=$pass_n fail=$fail_n"
[ "$fail_n" -eq 0 ]
EOF
bash /tmp/smoke_deferfire.sh; rc=$?
rm -f /tmp/smoke_deferfire.sh
exit $rc
# Expected: pass=6 fail=0, exit 0. Cases 1-2 prove the deferred fire links the right
# window via the async job; case 3 proves the empty-match guard; case 4 proves defer=off
# preserves the synchronous link. If case 1/2 timeout, _lp_fire_preview is not firing or
# preview.sh's guard is rejecting the seq (re-check the $2 plumbing + STATE_PREVIEW_SEQ).
```

### Level 3: Confirm independence (the "type and Enter before any preview" path)

```bash
cat > /tmp/smoke_confirmindep.sh <<'EOF'
#!/usr/bin/env bash
set -u
cd /home/dustin/.config/tmux/plugins/tmux-livepicker
source tests/setup_socket.sh; source tests/helpers.sh
setup_test "lp-smoke-confirm"
tmux set-option -g @livepicker-preview-defer on   # defer ON
attach_test_client
"$LIVEPICKER_SCRIPTS/livepicker.sh"
# Type "alpha" then IMMEDIATELY confirm (no wait for the deferred preview). Confirm must
# land on alpha regardless of whether the bg preview ever ran.
for c in a l p h a; do "$LIVEPICKER_SCRIPTS/input-handler.sh" type "$c"; done
"$LIVEPICKER_SCRIPTS/input-handler.sh" confirm
[ "$(tmux display-message -p '#{session_name}')" = "alpha" ] \
  && echo "OK: type+Enter lands on alpha (confirm independent of preview)" \
  || echo "FAIL: confirm did not land on alpha"
teardown_test
EOF
bash /tmp/smoke_confirmindep.sh; rc=$?
rm -f /tmp/smoke_confirmindep.sh
exit $rc
# Expected: OK. Confirm reads authoritative filter/index and lands correctly even though
# the deferred preview jobs were still in flight (or superseded) at Enter time.
```

### Level 4: No regression (full suite — runs defer=off via the Task 4 pin)

```bash
cd /home/dustin/.config/tmux/plugins/tmux-livepicker
tests/run.sh
# Expected: exit 0, all existing tests green. setup_test pins defer=off, so the existing
# synchronous-assertion suite (test_functional.sh etc.) runs the legacy path deterministically.
# If a test FAILS on a @livepicker-linked-id assertion right after an input-handler action,
# the setup_test pin (Task 4) is missing or overridden — re-check it.
```

## Final Validation Checklist

### Technical Validation

- [ ] `bash -n scripts/input-handler.sh tests/helpers.sh` clean.
- [ ] `shellcheck` on both: 0 NEW findings.
- [ ] L1 grep checks: `_lp_fire_preview` ×1; `_lp_preview_follow` ×1; the run-shell fire ×1;
      `_lp_preview_follow "$target"` ×2 (nav); `refresh-client -S` ×2 (both in dispatcher);
      `_lp_sync_preview_to_top_match` no longer calls preview.sh directly;
      `@livepicker-preview-defer off` ×1 in helpers.sh.
- [ ] L2 defer smoke: pass=6 fail=0 (deferred type/next link via poll; empty-match no-op;
      defer=off sync link).
- [ ] L3 confirm-independence smoke: type+Enter lands on the target.

### Feature Validation

- [ ] defer=on: type/backspace/cancel-clear set filter/index + refresh synchronously, bump
      seq, set target, and (poll) link the top match's window in the background.
- [ ] defer=on: next/prev set index + refresh synchronously, then (poll) link `$target`.
- [ ] defer=on: empty filtered list -> no preview fires (linked-id unchanged), status redraws.
- [ ] defer=off: preview.sh runs synchronously (one arg) then refresh — legacy preserved.
- [ ] Confirm lands on the target independent of the background preview (§18 contract #4).
- [ ] `@livepicker-preview-seq` bumped only on defer=on fires; `@livepicker-preview-target`
      records the latest target.

### Code Quality Validation

- [ ] Defer logic centralized in `_lp_preview_follow` (NOT inlined at 5 sites).
- [ ] Refresh ordering: defer=on = refresh-then-fire; defer=off = preview-then-refresh.
- [ ] Empty-target guard in `_lp_fire_preview`; nav's `[ "$L" -eq 0 ]` early return kept.
- [ ] confirm + cancel full-exit + activation first-preview UNCHANGED.
- [ ] TAB indent (2 tabs type/backspace/next/prev; 3 tabs cancel-clear; column 0 for helpers).
- [ ] Edits confined to input-handler.sh (Task 1-3) + helpers.sh (Task 4).

### Documentation & Deployment

- [ ] No README/CHANGELOG edit here (the option row is synced by the Mode-B docs task
      P1.M3.T3.S1). Inline comments cross-reference PRD §18, Q5/Q6, and the consumer
      sibling (P1.M2.T2.S1) so the producer/consumer seam is self-documenting.
- [ ] The setup_test pin comment documents WHY (determinism) and the test_responsiveness.sh
      override contract for P1.M3.T1.S1.

---

## Anti-Patterns to Avoid

- ❌ Don't skip the `setup_test` defer=off pin (Task 4) — without it `tests/run.sh` FAILS
  (test_functional.sh's synchronous `@livepicker-linked-id` asserts race the async
  `run-shell -b` job — research FINDING 6). This is the single most common way this task
  fails validation.
- ❌ Don't inline `if opt_preview_defer …` at each of the 5 call sites — centralize in
  `_lp_preview_follow` (one place for the defer logic + the refresh ordering).
- ❌ Don't reorder the legacy (`else`) branch — defer=off MUST be sync-preview-then-refresh
  (byte-for-byte pre-§18). Only the defer=on branch is refresh-then-fire (§18.1/§18.2).
- ❌ Don't touch confirm / cancel full-exit / activation first-preview — they are already
  §18-compliant (confirm reads authoritative state; activation's first preview stays
  synchronous per the §18 mechanism note).
- ❌ Don't fire a preview for an empty target — `_lp_fire_preview` guards it; the
  empty-filtered top-match path passes `""` and must schedule nothing (leave the prior pane).
- ❌ Don't pass the seq as `$1` or omit it — `_lp_fire_preview` calls
  `preview.sh '<target>' '<seq>'` (target first, seq second). preview.sh's guard keys on
  `$2`; mismatched arg order silently disables the supersede.
- ❌ Don't double-quote the target inside the run-shell string (a `"...""$target""..."` would
  let tmux word-split a spaced session name) — use SINGLE quotes:
  `"$CURRENT_DIR/preview.sh '$target' '$seq'"` (research FINDING 9; matches Q6 + the
  key-binding form).
- ❌ Don't edit by line number — anchor every edit on CONTENT (line numbers drift ~1). For
  next/prev (identical preview+refresh lines), include each branch's UNIQUE preceding
  context so the edit tool matches the right occurrence.
- ❌ Don't remove the `_lp_sync_preview_to_top_match` call from the 3 top-match sites — only
  remove the explicit `refresh-client -S` (+ its stale comment); the call stays (now defer-aware).
- ❌ Don't add a committed `tests/test_responsiveness.sh` in this subtask — that is
  P1.M3.T1.S1; validate defer-on via the throwaway L2/L3 smokes only (then delete them).
- ❌ Don't add a debounce (`run-shell -b -d …`) unless explicitly requested — the contract
  says a debounce "may" gate the fire (optional). The seq-supersede already collapses a
  burst to one mutating job. Ship without `-d`; it can be added later if observed jank.
- ❌ Don't use spaces for indent — TABS only (match the file; shfmt absent).

---

## Confidence Score

**9 / 10** for one-pass success. Rationale: every dependency is **confirmed landed** in the
working tree (opt_preview_defer, STATE_PREVIEW_* + _STATE_RUNTIME_KEYS, the seq=0 init, AND
preview.sh's `expected_seq` supersede guard — research FINDING 1), so the producer/consumer
seam is fully wired on the consumer side; this task is purely the producer + call-site
rewire. The design centralizes all defer logic in one dispatcher (`_lp_preview_follow`) so
the 5 call-site edits are trivial (3 drop a refresh line; 2 swap to the dispatcher), with
verbatim old→new blocks anchored on unique content. The refresh-ordering rule (defer=on
refresh-first; defer=off legacy preview-first) is explicit and preserves legacy
byte-for-byte. The single load-bearing risk — the default-`on` change breaking
`test_functional.sh`'s synchronous `@livepicker-linked-id` asserts — is **identified and
addressed** by the mandatory `setup_test` defer=off pin (Task 4), with the tradeoff
(defer-on not in the main suite until P1.M3.T1.S1) mitigated by the thorough throwaway L2/L3
smokes that prove the deferred fire end-to-end. Fully disjoint from the parallel
P1.M2.T2.S1 (preview.sh). Residual risk: (a) an `edit`-tool `oldText` tab/whitespace
mismatch on the cancel-clear 3-tab site or the nav disambiguation — mitigated by the verbatim
blocks + the L1 grep post-checks; (b) the L2 poll timing on a heavily loaded CI box —
mitigated by the 2 s timeout (100 × 20 ms). The 1-point deduction is for the
defer-on-coverage gap until P1.M3.T1.S1 lands (a planned, accepted separation), not a defect.
