# PRP — P1.M2.T2.S1: `expected_seq` arg + supersede guard in preview_main (PRD §18)

> **Scope**: The supersede-safety seam for §18 (deferred preview). `preview.sh` gains
> an optional 2nd arg `<expected_seq>`: when present (the deferred background path from
> P1.M2.T3's fire helper), a job whose captured seq no longer matches the live
> `@livepicker-preview-seq` **no-ops** before touching any window — so a late /
> superseded / post-teardown `run-shell -b` job can never `unlink-window`/`link-window`
> over the current (or just-restored) link. When called with ONE arg (the activation
> first-preview + the `preview-defer=off` synchronous path), the guard is **skipped**
> and behavior is byte-for-byte unchanged. The existing link/unlink/select core is
> UNCHANGED — this only adds prechecks + a `linked_id` re-read.

---

## Goal

**Feature Goal**: `preview.sh` accepts `preview.sh <session> [expected_seq]` and is
**supersede-safe** when the seq is supplied: a background job whose seq has been
overtaken by a newer keystroke returns 0 WITHOUT mutating any window (no unlink /
link / select / state change). With one arg (no seq), preview.sh behaves exactly as
today. Additionally, `linked_id` is re-read immediately before the unlink step so a
job that raced a newer link unlinks the window actually linked now (race-narrowing).

**Deliverable**: One file edited — `scripts/preview.sh`. Three localized additions to
`preview_main()` (no new function, no new file):
1. Arg parsing: `local S="${1:-}" expected_seq="${2:-}"` (+ add `cur_seq` to the
   existing locals line).
2. A primary supersede guard immediately after the locals, BEFORE the preview-mode
   gate — bails a stale job before ANY work.
3. A `linked_id` re-read immediately before the unlink-previous block; and an
   optional second seq re-check immediately before the unlink block (the first
   mutation) — together these narrow the read→mutate race to a true no-op.
The entry point `preview_main "$@"` already forwards `$2` — **no change there**.

**Success Definition**:
- `preview.sh alpha` (one arg) → links `alpha`'s window, sets `@livepicker-linked-id`
  — UNCHANGED from today.
- `preview.sh alpha 3` where live `@livepicker-preview-seq == 3` → links `alpha`'s
  window (the job is current → mutates).
- `preview.sh alpha 3` where live `@livepicker-preview-seq == 5` → **no-op**: no
  window linked/unlinked/selected, `@livepicker-linked-id` UNCHANGED (a newer target
  won → this stale job bails).
- `preview.sh alpha 3` after teardown (`@livepicker-preview-seq` unset → reads `"0"`)
  → **no-op** (a late post-teardown `-b` job cannot clobber the restored window).
- The throwaway smoke proves all four cases; `tests/run.sh` stays green (the change is
  inert until P1.M2.T3 fires background jobs with a seq).

## User Persona (if applicable)

**Target User**: Downstream script — P1.M2.T3.S1 (input-handler.sh fire helper), which
on `preview-defer=on` bumps `STATE_PREVIEW_SEQ`, writes the target, and launches
`tmux run-shell -b "preview.sh '<target>' '<seq>'"`. Not end-user facing.

**Use Case**: The user types rapidly; each keystroke fires a deferred `-b` preview
job tagged with the seq at fire time. Only the job whose seq still matches the live
seq mutates; the rest no-op. If the user cancels/confirms while a `-b` job is
mid-flight, that late job re-reads the (now-cleared) seq, sees a mismatch, and no-ops
— it never clobbers the just-restored window.

**Pain Points Addressed**: Today preview.sh has no seq awareness, so a deferred `-b`
job (once P1.M2.T3 wires it) would unlink/link/select AFTER a newer keystroke or
AFTER teardown, clobbering the current link or the restored window (PRD §16
"Deferred-preview concurrency"; external_tmux_behavior.md Q6).

## Why

- **`run-shell -b` is non-cancellable (Q5).** tmux launches the command and returns
  immediately; there is no job handle / `kill-shell`. So a late job CANNOT be killed
  mid-flight — it MUST be made a no-op by re-checking the seq before it mutates. This
  is the single most important consequence of §18 for preview.sh.
- **The teardown case is mandatory (Q6 gotcha).** If the picker exits (cancel/confirm)
  while a `-b` job is mid-flight, the late job still runs and calls back into tmux.
  Without the seq guard it would `unlink-window`/`link-window` AFTER teardown —
  clobbering the user's restored window. `clear_all_state` (P1.M2.T1.S1 lists
  `STATE_PREVIEW_SEQ` in `_STATE_RUNTIME_KEYS`) unsets the seq on exit → the late job
  reads the `"0"` default ≠ its captured seq → no-op. **Verified live (research
  FINDING 2 case D).**
- **The top placement protects the self-session guard too (research FINDING 3).** The
  self-session guard (lines 101-113) MUTATES (`unlink-window` + `select-window`). The
  task contract's placement of the primary guard at the TOP (before the mode-gate)
  bails a stale job before ALL mutations, including the self-session guard's — strictly
  safer than Q6's literal "gate before the unlink/link/select" (which would let a stale
  job reach the self-session guard).
- **Cheap, surgical, low-risk.** One arg added to the locals, one `if` block at the
  top, one `linked_id` re-read, one optional re-check. No new function, no new file, no
  sourcing change, no driver change, no state-key change. The one-arg path is on the
  unchanged (guard-skipped) branch.
- **Disjoint from the parallel P1.M2.T1.S1 (research FINDING 7).** That task edits
  `options.sh`/`state.sh`/`livepicker.sh`; this task edits `preview.sh` ONLY. No file
  collision. preview.sh sources state.sh, so `STATE_PREVIEW_SEQ` is in scope at runtime
  once P1.M2.T1.S1 lands.

## What

1. **Arg parsing (Task 1)**: change `local S="${1:-}"` to
   `local S="${1:-}" expected_seq="${2:-}"`, and add `cur_seq` to the existing
   `local current_session …` declaration (so it is `set -u`-safe).
2. **Primary supersede guard (Task 2)**: immediately after the locals, BEFORE the
   preview-mode gate, insert:
   ```bash
   if [ -n "$expected_seq" ]; then
       cur_seq="$(get_state "$STATE_PREVIEW_SEQ" "0")"
       [ "$cur_seq" != "$expected_seq" ] && return 0
   fi
   ```
   With one arg (`expected_seq` empty) the guard is SKIPPED → unchanged. With a seq
   that no longer matches the live seq → `return 0` (no-op) before any work.
3. **`linked_id` re-read + optional 2nd guard (Task 3)**: immediately before the
   unlink-previous block, re-read `linked_id` (so the unlink targets the actually-linked
   window now), and optionally re-check the seq there too (before the FIRST mutation —
   see research FINDING 5 for why this placement avoids an untracked-link leak vs the
   contract's literal "before the final select").
4. **Do NOT change**: the mode-gate, self-session guard, src_id resolution, duplicate
   guard, `link-window`, `select-window`, `set_state`, the entry point
   `preview_main "$@"` (it already forwards `$2`), any other script, `options.sh`,
   `state.sh`, `utils.sh`, or any stored-state shape. The one-arg path is bit-for-bit
   identical (the guard is skipped).

### Success Criteria

- [ ] `preview_main` parses `expected_seq="${2:-}"`; declares `cur_seq` local.
- [ ] The primary guard sits ABOVE the preview-mode gate and bails (`return 0`) when
      `expected_seq` is non-empty AND `cur_seq != expected_seq`.
- [ ] With one arg (`expected_seq` empty), NO guard fires and behavior is unchanged.
- [ ] `linked_id` is re-read immediately before the unlink-previous block.
- [ ] (Optional) A second seq re-check sits immediately before the unlink block (first
      mutation), making a stale job a true no-op.
- [ ] The entry point `preview_main "$@"` is UNCHANGED (forwards `$2` already).
- [ ] `bash -n` + `shellcheck` clean on `preview.sh`; throwaway smoke passes (4 cases).
- [ ] `tests/run.sh` stays green (exit 0) — the change is inert until P1.M2.T3 fires
      jobs with a seq.

## All Needed Context

### Context Completeness Check

_Pass_: A developer who has never seen this repo can implement the fix from
(a) the exact old→new code blocks (quoted verbatim with content anchors, below),
(b) the verbatim 4-case throwaway smoke, and
(c) the load-bearing rules (guard keys on `$2`, NOT `opt_preview_defer`; primary guard
at the TOP before the mode-gate; re-read `linked_id` before unlink; one-arg path
unchanged). All live-proven in research/preview_supersede_guard_findings.md. The
dependency (`STATE_PREVIEW_SEQ`) is defined by the in-flight P1.M2.T1.S1 — its PRP is
treated as a CONTRACT.

### Documentation & References

```yaml
# MUST READ — the empirical ground-truth for THIS task (12 live-verified findings)
- docfile: plan/002_facc52335e68/P1M2T2S1/research/preview_supersede_guard_findings.md
  why: FINDING 1 (exact current preview_main structure with content anchors; line drift
       vs codebase_state.md); FINDING 2 (all 4 guard cases live-verified incl. the
       teardown case D); FINDING 3 (TOP placement is SAFER than Q6's "before mutations"
       because the self-session guard mutates); FINDING 4 (re-read linked_id before
       unlink targets the actually-linked window); FINDING 5 (the 2nd guard MUST go
       before the unlink, NOT before the select — placing it before select leaks an
       untracked link); FINDING 6 (opt_preview_defer NOT needed — keys on $2);
       FINDING 7 (DISJOINT from parallel P1.M2.T1.S1; STATE_PREVIEW_SEQ in scope once
       it lands); FINDING 8 (no committed test — feature tests are P1.M3.T1; validate
       via throwaway smoke); FINDING 9 (client-independent — no attach_test_client);
       FINDING 10 (set -u: declare expected_seq + cur_seq); FINDING 11 (entry point
       forwards $2 already — no change); FINDING 12 (TABS; file-wide shellcheck disable
       covers STATE_PREVIEW_SEQ).
  critical: FINDING 2 case D is the load-bearing teardown-safety proof. FINDING 5 is
            the single most important placement rule — do NOT put the 2nd guard before
            the final select (it leaks); put it before the unlink (first mutation).

# MUST READ — the DEPENDENCY CONTRACT (treat as implemented exactly as specified)
- docfile: plan/002_facc52335e68/P1M2T1S1/PRP.md
  why: P1.M2.T1.S1 (in-flight, parallel) adds the symbols THIS task consumes:
       STATE_PREVIEW_SEQ == "@livepicker-preview-seq" (readonly const in state.sh);
       STATE_PREVIEW_TARGET == "@livepicker-preview-target"; opt_preview_defer()
       (default "on"); BOTH keys in _STATE_RUNTIME_KEYS (so clear_all_state unsets
       them — the teardown-safety that makes case D work); set_state STATE_PREVIEW_SEQ
       "0" at activation. This task READS STATE_PREVIEW_SEQ only.
  critical: STATE_PREVIEW_SEQ is NOT yet present in the working tree (grep-confirmed).
            It will be once P1.M2.T1.S1 lands. The implementer runs the full preview.sh
            smoke AFTER P1.M2.T1.S1 lands (normal dependency ordering). The guard LOGIC
            is independently verifiable via the raw @livepicker-preview-seq option
            (research FINDING 2).

# MUST READ — the supersede rationale (WHY the seq + the teardown guard)
- docfile: plan/002_facc52335e68/architecture/external_tmux_behavior.md
  why: Q5 (run-shell -b is detached, non-blocking, NOT cancellable by id — a late job
       must no-op via the seq; "If the picker exits while a -b job is mid-flight ...
       the seq guard prevents it from clobbering restored state"); Q6 (the monotonic
       counter pattern: bump on fire, capture at fire, re-check in preview.sh before
       mutating; the reference impl; the gotchas — N jobs spawn, only the latest
       mutates; debounce collapses a burst; confirm is independent of the preview).
  section: "Q5", "Q6"

# MUST READ — the authoritative current structure of preview_main
- docfile: plan/002_facc52335e68/architecture/codebase_state.md
  why: §5 documents preview_main() lines 75-166 (arg parsing, mode-gate, self-session
       guard, src_id resolution, duplicate guard, unlink-previous, link+select+track).
       NOTE (research FINDING 1): the doc's line numbers are ~1 drifted from the live
       file — anchor edits on CONTENT, not line numbers.
  section: "§5 preview.sh — live preview core"

# MUST READ — the file being modified (the three edit anchors)
- file: scripts/preview.sh
  why: Contains preview_main() with the arg-parsing locals (line 75-76), the mode-gate
        (line 85), and the unlink-previous block (lines 145-149). The fix adds the
        expected_seq arg + cur_seq local, the primary guard (before the mode-gate),
        and the linked_id re-read + optional 2nd guard (before the unlink block).
  pattern: the existing locals line `local current_session orig_window linked_id src_id
           w_sess w_idx` — add `cur_seq` to it (set -u-safe; assigned only inside the
           guard's if, where it is read). The `local S="${1:-}"` line — append
           `expected_seq="${2:-}"`.
  gotcha: The file ALREADY has the window-index resolution + w_sess/w_idx locals
          (from the 001-bugfix pass). Do NOT re-add or move those. The entry point
          `preview_main "$@"` forwards ALL args — $2 is already plumbed (FINDING 11).

# MUST READ — the test harness (for the throwaway smoke) + the seed helper pattern
- file: tests/test_preview.sh
  why: Defines lp_preview_seed_state() (sets @livepicker-orig-session/window/linked-id
        — the MINIMAL state preview.sh reads; client-independent). The throwaway smoke
        mirrors this: seed state, set @livepicker-preview-seq, call preview.sh with 1
        or 2 args, assert @livepicker-linked-id. NO attach_test_client (FINDING 9).
- file: tests/setup_socket.sh
  why: setup_test/setup_socket: temp dir + PATH shim (bare `tmux` -> isolated -L
        socket) + baseline driver/alpha/beta fixtures + exports $LIVEPICKER_SCRIPTS.
- file: tests/helpers.sh
  why: assert_eq/assert_contains/fail (the smoke's assertions; though the smoke inlines
        its own checks — either is fine for a throwaway).

# Reference — PRD §18 (the feature spec) + §16 (concurrency risk)
- docfile: PRD.md
  why: §18 specifies the deferred/supersedeable contract (preview runs in the
       background via run-shell -b; superseded not queued; a late preview whose target
       has been superseded is a no-op). §16 "Deferred-preview concurrency" mandates the
       supersede guard ("discard a late result so a stale unlink-window/link-window
       never clobbers the current link").
  section: "§18 Responsiveness", "§16 Implementation risks (Deferred-preview concurrency)"
```

### Current Codebase tree

```bash
tmux-livepicker/
  scripts/
    preview.sh        # MODIFY: +expected_seq arg + primary guard + linked_id re-read (+optional 2nd guard)
    options.sh        # UNCHANGED (opt_preview_defer added by P1.M2.T1.S1 — READ elsewhere, NOT here)
    state.sh          # UNCHANGED (STATE_PREVIEW_SEQ/TARGET added by P1.M2.T1.S1 — READ here via get_state)
    utils.sh          # UNCHANGED (tmux_get_opt — get_state delegates to it)
    input-handler.sh  # UNCHANGED (the fire helper that passes $2 is P1.M2.T3 — NOT this task)
                      # NOTE: P1.M2.T1.S1 (parallel) modifies options.sh/state.sh/livepicker.sh — DISJOINT.
    livepicker.sh, restore.sh, renderer.sh, filter.sh, plugin.tmux  # UNCHANGED
  tests/              # UNCHANGED (feature tests land in P1.M3.T1 test_responsiveness.sh)
```

### Desired Codebase tree with files to be added and responsibility of file

```bash
scripts/preview.sh  # +expected_seq ($2) + primary supersede guard (top) + linked_id re-read before unlink (+optional 2nd guard before unlink)
                     #   one-arg path UNCHANGED; two-arg (seq) path supersede-safe (late jobs no-op)
```

### Known Gotchas of our codebase & Library Quirks

```bash
# CRITICAL (research FINDING 5): the OPTIONAL 2nd guard MUST go BEFORE THE UNLINK block
# (the first mutation), NOT "before the final select-window". Placing it before select
# (line 161) fires AFTER link-window (153) but BEFORE set_state (164) -> if it returns 0,
# the just-linked src_id is NOT tracked in @livepicker-linked-id -> a LEAK. Before-unlink
# placement makes a stale job a TRUE no-op (skips unlink+link+select+set_state). This is
# a safer reading of the contract's "close the read->mutate race" goal.

# CRITICAL (research FINDING 3): place the PRIMARY guard at the TOP (before the mode-gate),
# NOT "before the unlink/link/select" as Q6's literal reference shows. The self-session
# guard (lines 101-113) MUTATES (unlink + select); the TOP placement bails a stale job
# before it reaches that mutation. The contract specifies the top placement — follow it.

# CRITICAL (research FINDING 2 case D): the teardown-safety depends on clear_all_state
# (P1.M2.T1.S1) UNSETTING @livepicker-preview-seq so a late job reads the "0" default.
# This is WHY STATE_PREVIEW_SEQ must be in _STATE_RUNTIME_KEYS (P1.M2.T1.S1's job). Do
# NOT add a teardown step to preview.sh — the unset is restore.sh/clear_all_state's job.

# GOTCHA (research FINDING 6): the guard keys on $2 (expected_seq), NOT on opt_preview_defer.
# The synchronous-vs-deferred distinction is the CALLER's (P1.M2.T3): deferred passes $2;
# synchronous does not. preview.sh does NOT read opt_preview_defer or STATE_PREVIEW_TARGET.

# GOTCHA (research FINDING 7): STATE_PREVIEW_SEQ is NOT in the working tree yet (P1.M2.T1.S1
# in-flight, grep-confirmed). Run the full preview.sh smoke AFTER P1.M2.T1.S1 lands. The
# guard LOGIC is independently verifiable via the raw @livepicker-preview-seq option.

# GOTCHA (research FINDING 10): set -u is inherited. Declare `expected_seq="${2:-}"`
# (empty when $2 absent — safe) and `cur_seq` in the locals line (assigned only inside
# the guard's if; declared-but-unassigned is set -u-safe if never read before assignment).

# GOTCHA (research FINDING 11): the entry point `preview_main "$@"` (line 168) forwards
# ALL args already — $2 is plumbed. Do NOT change the entry point; only the locals line.

# GOTCHA: preview.sh already has the window-index resolution + w_sess/w_idx locals (001
# bugfix). Do NOT re-add or move them. Just add expected_seq + cur_seq to the existing
# local declarations.

# GOTCHA (research FINDING 9): preview.sh is CLIENT-INDEPENDENT (reads @livepicker-orig-
# session via get_state). The smoke needs NO attach_test_client.

# STYLE (research FINDING 12): TABS; the file has file-wide `shellcheck disable=SC1091,SC2153`
# which covers the STATE_PREVIEW_SEQ readonly-const reference (same as STATE_LINKED_ID).
# No new shellcheck disable needed.
```

## Implementation Blueprint

### Data models and structure

No data-model change. The "model" is one optional arg + three prechecks keyed on it:

```
preview_main($1=S, $2=expected_seq)
 ├─ locals: S, expected_seq (="${2:-}"), current_session, orig_window, linked_id, src_id,
 │          w_sess, w_idx, cur_seq
 ├─ PRIMARY GUARD (before mode-gate):                                # <- NEW (Task 2)
 │    if expected_seq non-empty AND get_state(SEQ,"0") != expected_seq: return 0   # stale -> no-op
 ├─ mode-gate (off/snapshot/live)                          # UNCHANGED
 ├─ self-session guard (unlink+unset+select ORIG_WINDOW)   # UNCHANGED (now protected by the top guard)
 ├─ src_id resolution (window-index awk | session active)  # UNCHANGED
 ├─ duplicate guard (linked_id==src_id -> just select)     # UNCHANGED
 ├─ 2ND GUARD + linked_id RE-READ (before unlink):                   # <- NEW (Task 3)
 │    if expected_seq non-empty AND get_state(SEQ,"0") != expected_seq: return 0   # optional; true no-op
 │    linked_id = get_state(LINKED_ID, "")                          # re-read the freshest
 ├─ unlink-previous / link-window -a / select-window / set_state    # UNCHANGED
 └─ entry: preview_main "$@"  (forwards $2 already)                  # UNCHANGED
```

### Implementation Tasks (ordered by dependencies)

```yaml
Task 1: MODIFY scripts/preview.sh — add expected_seq + cur_seq to the locals
  - LOCATE preview_main()'s two locals lines (the anchor — content, not line number):
        local S="${1:-}"
        local current_session orig_window linked_id src_id w_sess w_idx
  - CHANGE to (add expected_seq to the first, cur_seq to the second):
        local S="${1:-}" expected_seq="${2:-}"
        local current_session orig_window linked_id src_id w_sess w_idx cur_seq
  - WHY: expected_seq captures $2 (empty when absent -> set -u-safe; the [ -n ] gate
    handles empty). cur_seq is declared here so the guard's assignment is set -u-safe.
  - STYLE: TABS; keep the two-line local layout the file already uses.

Task 2: MODIFY scripts/preview.sh — insert the PRIMARY supersede guard before the mode-gate
  - LOCATE: the linked_id read immediately followed by the mode-gate comment. The anchor:
        linked_id="$(get_state "$STATE_LINKED_ID" "")"

        # --- @livepicker-preview-mode gate (PRD §7 Fallbacks / §11; default live) ---
  - INSERT between the linked_id read and the mode-gate comment (verbatim block in
    "Implementation Patterns" below): the guard reads STATE_PREVIEW_SEQ and bails if
    expected_seq is non-empty and mismatches.
  - WHY at the TOP (before the cheap reads would also work, but the contract places it
    here, above the mode-gate): a stale job returns 0 before ANY work, including the
    self-session guard's mutations (research FINDING 3). With one arg (expected_seq
    empty) the guard is skipped -> unchanged.
  - DEPENDS ON: STATE_PREVIEW_SEQ (P1.M2.T1.S1). In scope at runtime (preview.sh
    sources state.sh).

Task 3: MODIFY scripts/preview.sh — linked_id re-read + optional 2nd guard before unlink
  - LOCATE the unlink-previous block (the anchor — content):
        # Drop the previous preview from the current session (NO -k; source keeps it).
        # Ignore non-zero: singly-linked edge / already-gone (FINDING 2).
        if [ -n "$linked_id" ]; then
  - INSERT immediately BEFORE that comment: (a) the optional 2nd seq re-check (before
    the FIRST mutation — research FINDING 5: NOT before the select, to avoid an
    untracked-link leak), then (b) the linked_id re-read (verbatim in "Implementation
    Patterns"). The unlink then operates on the freshest linked_id.
  - WHY: the 2nd guard closes the read->mutate race that opens between the top guard
    and the unlink (a newer job may have bumped the seq in between). The re-read
    ensures the unlink targets the window actually linked now (research FINDING 4).
  - NOTE: the 2nd guard is OPTIONAL per the contract — but the PRP recommends it for
    defense-in-depth, placed before the unlink (NOT before the select).

Task 4: VALIDATE (throwaway smoke via the existing socket-isolated harness)
  - RUN: bash -n scripts/preview.sh
  - RUN: shellcheck scripts/preview.sh (expect 0 NEW findings; file-wide disables cover
    the STATE_PREVIEW_SEQ reference).
  - RUN: the 4-case throwaway smoke (L2 below) AFTER P1.M2.T1.S1 has landed (so
    STATE_PREVIEW_SEQ is a real const). Proves: one-arg mutate; two-arg-current
    mutate; two-arg-stale no-op; post-teardown no-op.
  - RUN: tests/run.sh (expect full suite green — the change is inert until P1.M2.T3).
  - DELETE the throwaway smoke (no committed test in this subtask — feature tests are
    P1.M3.T1).
```

### Implementation Patterns & Key Details

**Task 1 — the locals (paste verbatim).** CURRENT:

```bash
	local S="${1:-}"
	local current_session orig_window linked_id src_id w_sess w_idx
```
→
```bash
	local S="${1:-}" expected_seq="${2:-}"
	local current_session orig_window linked_id src_id w_sess w_idx cur_seq
```

**Task 2 — the primary supersede guard (paste verbatim).** CURRENT (the anchor — the
linked_id read + blank + the mode-gate comment):

```bash
	linked_id="$(get_state "$STATE_LINKED_ID" "")"

	# --- @livepicker-preview-mode gate (PRD §7 Fallbacks / §11; default live) ---
```
→ (insert the guard between the linked_id read and the mode-gate comment):

```bash
	linked_id="$(get_state "$STATE_LINKED_ID" "")"

	# --- deferred-preview supersede guard (PRD §18 / external_tmux_behavior.md Q6) ---
	# When called WITH an expected_seq ($2 — the deferred background path from
	# P1.M2.T3's fire helper), bail EARLY if the live seq has advanced past it: a
	# newer keystroke fired a newer preview, so THIS job is stale and must NOT touch
	# any window. (A run-shell -b job is non-cancellable — Q5 — so it no-ops here.)
	# When called with ONE arg ($2 empty — the activation first-preview and the
	# preview-defer=off synchronous path), the guard is SKIPPED: behavior is exactly
	# as before. clear_all_state unsets STATE_PREVIEW_SEQ on exit (P1.M2.T1.S1 lists
	# it in _STATE_RUNTIME_KEYS), so a late post-teardown job reads the "0" default
	# != its captured seq -> no-op too (the Q6 teardown-safety guarantee).
	if [ -n "$expected_seq" ]; then
		cur_seq="$(get_state "$STATE_PREVIEW_SEQ" "0")"
		[ "$cur_seq" != "$expected_seq" ] && return 0
	fi

	# --- @livepicker-preview-mode gate (PRD §7 Fallbacks / §11; default live) ---
```

**Task 3 — linked_id re-read + optional 2nd guard before unlink (paste verbatim).**
CURRENT (the anchor — the unlink-previous comment + block):

```bash
	# Drop the previous preview from the current session (NO -k; source keeps it).
	# Ignore non-zero: singly-linked edge / already-gone (FINDING 2).
	if [ -n "$linked_id" ]; then
		tmux unlink-window -t "$current_session:$linked_id" 2>/dev/null || true
	fi
```
→ (insert the 2nd guard + the re-read BEFORE the comment):

```bash
	# Optional second supersede re-check (PRD §18 / Q6 read->mutate race). Placed
	# here — BEFORE the first mutation (the unlink) — so a job that went stale
	# between the top-of-function guard and now is a TRUE no-op (it skips
	# unlink+link+select+set_state entirely, so no link is left untracked). Do NOT
	# move this to before the final select-window: that fires AFTER link-window but
	# BEFORE set_state LINKED_ID -> a stale job would link its window then bail,
	# leaving an UNTRACKED link (a leak). (research FINDING 5.)
	if [ -n "$expected_seq" ]; then
		[ "$(get_state "$STATE_PREVIEW_SEQ" "0")" != "$expected_seq" ] && return 0
	fi
	# Re-read LINKED_ID here (not just the snapshot at the top) so the unlink targets
	# the window ACTUALLY linked in the driver now (the freshest) — a newer -b job may
	# have linked a different window and updated @livepicker-linked-id since entry.
	linked_id="$(get_state "$STATE_LINKED_ID" "")"
	# Drop the previous preview from the current session (NO -k; source keeps it).
	# Ignore non-zero: singly-linked edge / already-gone (FINDING 2).
	if [ -n "$linked_id" ]; then
		tmux unlink-window -t "$current_session:$linked_id" 2>/dev/null || true
	fi
```

(The rest — `link-window`, `select-window`, `set_state "$STATE_LINKED_ID"` — is
UNCHANGED. The entry point `preview_main "$@"` is UNCHANGED.)

### Integration Points

```yaml
CODE:
  - file: scripts/preview.sh
    change: "+expected_seq arg + cur_seq local (Task 1); +primary guard before mode-gate
             (Task 2); +optional 2nd guard + linked_id re-read before unlink (Task 3)"
    invariant: "one-arg path byte-identical to today (guard skipped); two-arg (seq) path
               supersede-safe (late/stale/post-teardown jobs no-op before any mutation)"

CONSUMERS (later subtasks — DO NOT implement now):
  - P1.M2.T3.S1 (input-handler.sh fire helper): BUMPS STATE_PREVIEW_SEQ, writes
    STATE_PREVIEW_TARGET, fires `tmux run-shell -b "preview.sh '<target>' '<seq>'"`.
    The synchronous path (preview-defer=off, activation first-preview) calls
    preview.sh with ONE arg (no seq -> guard skipped).
  - P1.M3.T1.S1 (test_responsiveness.sh): the committed feature test for §15.23.

CONFIG / DATABASE / ROUTES: none.
```

## Validation Loop

### Level 1: Syntax & Style (Immediate Feedback)

```bash
cd /home/dustin/.config/tmux/plugins/tmux-livepicker
bash -n scripts/preview.sh && echo "OK: preview syntax"
shellcheck scripts/preview.sh
# Tabs-not-spaces sanity on the edited regions (shfmt NOT installed):
grep -nP '^ +' scripts/preview.sh && echo "WARN: space-indent found (use tabs)" || echo "OK: tabs"
# Confirm the new pieces are present:
grep -c 'expected_seq="\${2:-}"' scripts/preview.sh      # -> 1  (Task 1: arg parsing)
grep -c 'local .*cur_seq' scripts/preview.sh             # -> 1  (Task 1: cur_seq declared)
grep -c '\[ "\$cur_seq" != "\$expected_seq" \] && return 0' scripts/preview.sh  # -> 1  (Task 2: primary guard)
grep -c 'STATE_PREVIEW_SEQ' scripts/preview.sh           # -> 2  (Task 2 primary + Task 3 2nd guard)
# The linked_id re-read before the unlink block:
grep -B1 'Drop the previous preview' scripts/preview.sh | grep -q 'linked_id="$(get_state "\$STATE_LINKED_ID"' \
  && echo "OK: linked_id re-read precedes the unlink" || echo "FAIL"
# The 2nd guard sits BEFORE the unlink (the first mutation), NOT before the select:
awk '/second supersede re-check/{g=NR} /Drop the previous preview/{u=NR} END{if(g&&u&&g<u) print "OK: 2nd guard before unlink"; else print "FAIL: 2nd guard not before unlink"}' scripts/preview.sh
# The entry point is UNCHANGED (forwards all args):
grep -c '^preview_main "\$@"' scripts/preview.sh         # -> 1
# Expected: syntax clean; shellcheck 0 new findings; all grep checks green.
```

### Level 2: Supersede-guard behavior smoke (4 cases) — run AFTER P1.M2.T1.S1 lands

> `STATE_PREVIEW_SEQ` is added by the in-flight P1.M2.T1.S1. Run this smoke once that
> lands (normal dependency order). It mirrors `tests/test_preview.sh`'s
> `lp_preview_seed_state` (client-independent — NO attach_test_client). DELETE after.

```bash
cat > /tmp/smoke_seqguard.sh <<'EOF'
#!/usr/bin/env bash
set -u
cd /home/dustin/.config/tmux/plugins/tmux-livepicker
source tests/setup_socket.sh
source tests/helpers.sh
setup_test "lp-smoke-seqguard"
source scripts/utils.sh
source scripts/options.sh
source scripts/state.sh

pass_n=0; fail_n=0
ck() { if [ "$2" = "$3" ]; then pass_n=$((pass_n+1)); else fail_n=$((fail_n+1)); echo "FAIL $1: got[$2] want[$3]"; fi; }

# Seed the minimal state preview.sh reads (mirror lp_preview_seed_state).
drv_win="$(tmux list-windows -t "=driver" -F '#{window_id}' -f '#{window_active}')"
tmux set-option -g @livepicker-orig-session driver
tmux set-option -g @livepicker-orig-window "$drv_win"
tmux new-session -d -s cand -x 120 -y 40
cand_w="$(tmux list-windows -t '=cand' -F '#{window_id}' -f '#{window_active}')"

# --- case 1: ONE arg (synchronous path) -> guard SKIPPED -> mutates (unchanged) ---
tmux set-option -g @livepicker-linked-id ""
"$LIVEPICKER_SCRIPTS/preview.sh" cand
ck "case1 one-arg links" "$(tmux show-option -gqv @livepicker-linked-id)" "$cand_w"

# --- case 2: TWO args, seq CURRENT -> mutates ---
tmux set-option -g @livepicker-linked-id ""
tmux set-option -g @livepicker-preview-seq "7"
"$LIVEPICKER_SCRIPTS/preview.sh" cand 7
ck "case2 current-seq links" "$(tmux show-option -gqv @livepicker-linked-id)" "$cand_w"

# --- case 3: TWO args, seq STALE (live advanced to 9) -> NO-OP (linked-id unchanged) ---
tmux set-option -g @livepicker-linked-id "PRE-EXISTING-MARKER"
tmux set-option -g @livepicker-preview-seq "9"
"$LIVEPICKER_SCRIPTS/preview.sh" cand 7        # captured 7, but live is 9
ck "case3 stale-seq no-op (linked-id untouched)" "$(tmux show-option -gqv @livepicker-linked-id)" "PRE-EXISTING-MARKER"
# And the candidate window was NOT linked into the driver:
case "$(tmux list-windows -t "=driver" -F '#{window_id}')" in *"$cand_w"*)
  fail_n=$((fail_n+1)); echo "FAIL case3: stale job linked the candidate window";; esac

# --- case 4: post-TEARDOWN (seq UNSET -> default 0) vs captured 7 -> NO-OP ---
tmux set-option -g @livepicker-linked-id "RESTORE-MARKER"
tmux set-option -gu @livepicker-preview-seq    # simulate clear_all_state
"$LIVEPICKER_SCRIPTS/preview.sh" cand 7
ck "case4 post-teardown no-op" "$(tmux show-option -gqv @livepicker-linked-id)" "RESTORE-MARKER"

teardown_test
echo "pass=$pass_n fail=$fail_n"
[ "$fail_n" -eq 0 ]
EOF
bash /tmp/smoke_seqguard.sh; rc=$?
rm -f /tmp/smoke_seqguard.sh
exit $rc
# Expected: pass=4 fail=0, exit 0. Cases 3+4 are the critical supersede proofs: a stale
# job touches NO window and does NOT change @livepicker-linked-id. (If P1.M2.T1.S1 has
# NOT landed yet, STATE_PREVIEW_SEQ is unbound -> the smoke set -u-fails at the first
# STATE_PREVIEW_SEQ reference; that is expected — run after P1.M2.T1.S1 lands.)
```

### Level 3: Guard-LOGIC-only check (run NOW, before P1.M2.T1.S1 lands)

If P1.M2.T1.S1 has not landed, verify the guard LOGIC against the raw option name
(does not touch preview.sh — proves the condition is correct independently):

```bash
cat > /tmp/smoke_guardlogic.sh <<'EOF'
#!/usr/bin/env bash
set -u
cd /home/dustin/.config/tmux/plugins/tmux-livepicker
source tests/setup_socket.sh; setup_test "lp-smoke-logic"
SEQ="@livepicker-preview-seq"
gs() { local v; v="$(tmux show-option -gqv "$SEQ")"; [ -n "$v" ] && echo "$v" || echo "0"; }
# case A: expected empty -> skip
e=""; [ -n "$e" ] && { [ "$(gs)" != "$e" ] && echo A=noop || echo A=mutate; } || echo "A: skip (one-arg, unchanged)"
# case B: current
tmux set-option -g "$SEQ" 3; e=3; [ "$(gs)" != "$e" ] && echo B=noop || echo "B: mutate (current)"
# case C: stale
tmux set-option -g "$SEQ" 5; e=3; [ "$(gs)" != "$e" ] && echo "C: noop (stale)" || echo "C: mutate (BUG)"
# case D: teardown
tmux set-option -gu "$SEQ"; e=3; [ "$(gs)" != "$e" ] && echo "D: noop (post-teardown)" || echo "D: mutate (BUG)"
teardown_test
EOF
bash /tmp/smoke_guardlogic.sh; rm -f /tmp/smoke_guardlogic.sh
# Expected: A=skip, B=mutate, C=noop, D=noop.
```

### Level 4: No regression (full suite)

```bash
cd /home/dustin/.config/tmux/plugins/tmux-livepicker
tests/run.sh
# Expected: exit 0, all existing tests green. The change is inert until P1.M2.T3 fires
# jobs with a seq (no caller passes $2 yet), so no existing assertion can regress.
```

## Final Validation Checklist

### Technical Validation

- [ ] `bash -n scripts/preview.sh` clean.
- [ ] `shellcheck scripts/preview.sh`: 0 NEW findings (file-wide disables cover STATE_PREVIEW_SEQ).
- [ ] L1 grep checks green: `expected_seq="${2:-}"` ×1; `cur_seq` declared ×1; primary
      guard `[ "$cur_seq" != "$expected_seq" ] && return 0` ×1; `STATE_PREVIEW_SEQ` ×2;
      linked_id re-read precedes the unlink; 2nd guard before the unlink (not the select).
- [ ] L2 4-case smoke (after P1.M2.T1.S1 lands): pass=4 fail=0.
- [ ] L3 guard-logic check (now): A=skip, B=mutate, C=noop, D=noop.

### Feature Validation

- [ ] One-arg path: `preview.sh cand` links the candidate (unchanged from today).
- [ ] Two-arg current-seq: `preview.sh cand <cur>` links the candidate.
- [ ] Two-arg stale-seq: `preview.sh cand <stale>` is a no-op (no window touched,
      `@livepicker-linked-id` unchanged).
- [ ] Post-teardown (seq unset): late job no-ops (cannot clobber restored window).
- [ ] `linked_id` re-read before the unlink (targets the actually-linked window).
- [ ] Entry point `preview_main "$@"` UNCHANGED.

### Code Quality Validation

- [ ] `expected_seq` + `cur_seq` declared `local` (set -u-safe).
- [ ] Primary guard at the TOP (before the mode-gate), NOT "before the unlink/link/select".
- [ ] 2nd guard (if included) BEFORE the unlink (first mutation), NOT before the select
      (avoids the untracked-link leak — research FINDING 5).
- [ ] The one-arg path is byte-identical (guard skipped when `expected_seq` empty).
- [ ] TABS; no new sourcing; no new function; no new file.
- [ ] Edits confined to preview.sh (Task 1 + Task 2 + Task 3).

### Documentation & Deployment

- [ ] Inline comments cross-reference PRD §18, external_tmux_behavior.md Q5/Q6, and the
      consumer sibling (P1.M2.T3 fire helper) so the integration seam is self-documenting.
- [ ] No README/CHANGELOG edit in this subtask (Mode-A internal; the cross-cutting doc
      sync is P1.M3.T3.S1; no user-facing/config/API surface change).

---

## Anti-Patterns to Avoid

- ❌ Don't place the 2nd guard before the final `select-window` — it fires AFTER
  `link-window` but BEFORE `set_state LINKED_ID`, so a stale job would link its window
  then bail, leaving an UNTRACKED link (a leak). Place it before the unlink (first
  mutation) so a stale job is a true no-op (research FINDING 5).
- ❌ Don't place the primary guard "before the unlink/link/select" (Q6's literal
  reference) — the self-session guard (lines 101-113) MUTATES before that point. The
  contract's TOP placement (before the mode-gate) bails a stale job before ALL
  mutations. Follow the contract (research FINDING 3).
- ❌ Don't read `opt_preview_defer` or `STATE_PREVIEW_TARGET` in preview.sh — the guard
  keys on `$2` (expected_seq), not on the toggle. The caller (P1.M2.T3) decides
  sync-vs-deferred by passing `$2` or not (research FINDING 6).
- ❌ Don't change the entry point `preview_main "$@"` — it already forwards `$2`
  (research FINDING 11). Only the locals line + the inserted guards change.
- ❌ Don't re-add / move the existing `w_sess`/`w_idx`/window-index resolution — it's
  already present (001 bugfix). Only ADD `expected_seq` + `cur_seq` + the guards.
- ❌ Don't add a teardown step to preview.sh — the seq unset is `clear_all_state`'s job
  (P1.M2.T1.S1 lists `STATE_PREVIEW_SEQ` in `_STATE_RUNTIME_KEYS`). preview.sh only
  READS the seq.
- ❌ Don't forget to declare `cur_seq` `local` — preview.sh has `set -u`; an undeclared
  var read errors. Declare it in the locals line (assigned only inside the guard's if).
- ❌ Don't run the full preview.sh L2 smoke before P1.M2.T1.S1 lands — `STATE_PREVIEW_SEQ`
  is unbound until then (set -u-fail). Use the L3 logic-only check meanwhile (research
  FINDING 7).
- ❌ Don't commit a `tests/` file for this subtask — feature tests are P1.M3.T1
  (`test_responsiveness.sh`); validate via the throwaway L2/L3 smokes only.
- ❌ Don't edit by line number — the contract's "~line 86/143/158" and codebase_state.md's
  "75-166" are ~1 line drifted. Anchor edits on CONTENT (research FINDING 1).
- ❌ Don't add `attach_test_client` to the smoke — preview.sh is client-independent
  (reads `@livepicker-orig-session` via get_state) (research FINDING 9).
- ❌ Don't use spaces for indent — TABS only (match the file; shfmt absent).

---

## Confidence Score

**9 / 10** for one-pass success. Rationale: the change is three localized, verbatim
additions to `preview_main` (an arg + a local in the existing declaration; one `if`
block before the mode-gate; one `if` + one reassignment before the unlink), with every
piece of logic **live-verified** on 3.6b (research FINDING 2 — all 4 guard cases
including the load-bearing teardown case D; the re-read/re-check placement analyzed in
FINDING 4/5). The single subtlety — the 2nd guard's placement (before the unlink, not
the select, to avoid an untracked-link leak) — is documented with the exact reasoning
and a Level-1 awk check that proves the ordering. The one-arg path is provably
unchanged (the guard is skipped when `expected_seq` is empty). The dependency
(`STATE_PREVIEW_SEQ`) is a sourced readonly const that will be in scope once the
parallel P1.M2.T1.S1 lands (disjoint files — no collision), and the guard LOGIC is
independently verifiable now via the raw option (L3). Disjoint from the in-flight
parallel P1.M2.T1.S1 (options.sh/state.sh/livepicker.sh). Residual risk: an `edit`-tool
`oldText` mismatch due to tab/whitespace or the exact surrounding comment block —
mitigated by the verbatim old→new pairs in Implementation Patterns and the Level 1 grep
+ awk post-checks. The 1-point deduction is for the dependency on the not-yet-landed
`STATE_PREVIEW_SEQ` constant (the L2 smoke must run after P1.M2.T1.S1), which is normal
ordered-delivery risk, not a defect in this PRP.
