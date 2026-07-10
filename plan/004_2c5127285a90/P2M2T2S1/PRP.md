# PRP — P2.M2.T2.S1: Unify keep/keep-window to skip STEP-2 ORIG_WINDOW re-select

---

## Goal

**Feature Goal**: Make `restore.sh` STEP-2 re-select `ORIG_WINDOW` **only on
`cancel`** — so both `keep` (session-mode confirm, P2.M2.T1.S1) and `keep-window`
(window-mode confirm) skip it and the client stays on the chosen `(S, W)` the
confirm just committed. PRD §9 restore step 2: *"`select-window -t "$ORIG_WINDOW"`
(cancel only; `keep` skips this so the client stays on the chosen `(S, W)`)."*

**Deliverable** (1 file edited, NO new file, NO docs):
- **EDIT `scripts/restore.sh`** — change the STEP-2 guard from
  `if [ "${1:-}" != "keep-window" ] && [ -n "$orig_window" ]; then` to
  `if [ "${1:-}" = "cancel" ] && [ -n "$orig_window" ]; then`, and update the
  STEP-2 comment block to reflect the unification (only cancel re-selects). The
  `orig_window` read, the `select-window` body, and `fi` are byte-unchanged.

**Success Definition**:
- `bash -n`/`shellcheck` clean on `scripts/restore.sh`.
- After a session-mode confirm to a flipped window, the client lands and STAYS on
  the chosen `(S, W)` — i.e. `#{window_id}` == the chosen W, NOT `ORIG_WINDOW`
  (the P2.M2.T1.S1 Level-3 smoke goes GREEN — this task is what un-blocks it).
- `cancel` STILL re-selects `ORIG_WINDOW` + switches back (cancel is a hard reset).
- `keep-window` (window-mode confirm) STILL skips the re-select (unchanged).
- `tests/run.sh` stays GREEN (verified: no existing test breaks — FINDING 6).

## User Persona (if applicable)

**Target User**: a tmux user who flips through a candidate session's windows and
presses `Enter` to confirm — they expect to land and STAY on the exact window they
were previewing, not be yanked back to the driver's original window by teardown.

**Use Case**: activate → highlight a multi-window session → `next-window`/`
prev-window` flip to window W → `Enter` → land and STAY on (S, W).

**Pain Points Addressed**: today teardown's `keep` path re-selects `ORIG_WINDOW`,
which (once confirm commits the chosen window via P2.M2.T1.S1) would move the active
window / strand the client off the chosen `(S, W)`. This task makes teardown leave
the client where confirm put it.

## Why

- **PRD §9 restore step 2** mandates the re-select be **cancel-only**; the current
  `!= "keep-window"` guard is a half-fix (M1) that left `keep` still re-selecting.
- **PRD §6 Cancel (h3.8)** — cancel is the hard reset that must restore the driver's
  original window + session; the `= "cancel"` guard preserves that exactly.
- **Decoupling / sibling contract**: P2.M2.T1.S1 (rework confirm session-mode to
  commit window) is the paired sibling and calls `restore.sh keep` from BOTH its
  non-self and self sub-paths. P2.M2.T1.S1's PRP lists THIS task as a HARD
  DEPENDENCY (its FINDING 6 / Anti-Patterns): "correctness of the window-landing
  depends on P2.M2.T2 landing." Both must land for `Enter` to leave the client on
  the chosen window. This task owns the teardown half of that contract.
- **Consistency**: STEP-3 already gates its `switch-client` on `[ "$mode" = "cancel" ]`.
  Making STEP-2 read identically turns STEP-2/STEP-3 into a uniform "cancel-only"
  pair — easier to reason about and test.

## What

1. **scripts/restore.sh** (EDIT) — in the STEP-2 block (the `# --- STEP 2 ...` comment
   through the closing `fi`), replace the comment block + the guard line so ONLY
   `cancel` re-selects `ORIG_WINDOW`. `keep` and `keep-window` skip it. Verbatim
   oldText/newText in the Blueprint.
2. **Docs / tests**: NONE (Mode A — internal teardown behavior; the work item says
   "DOCS: none — internal teardown behavior". The formal window-flip + confirm-on-window
   suite is P2.M3.T1.S1).

### Success Criteria

- [ ] STEP-2 guard reads `[ "${1:-}" = "cancel" ]` (L1 grep == 1 in restore.sh).
- [ ] `keep-window` is no longer referenced by the STEP-2 guard (L1 grep for
      `!= "keep-window"` in restore.sh == 0; the window-mode caller at
      input-handler.sh still passes `keep-window` — that is OUT OF SCOPE and unchanged).
- [ ] The STEP-2 comment describes the cancel-only re-select + the keep/keep-window skip.
- [ ] `bash -n` + `shellcheck` clean on `scripts/restore.sh`.
- [ ] `cancel` still re-selects `ORIG_WINDOW` (cancel tests stay GREEN).
- [ ] `keep` no longer re-selects `ORIG_WINDOW` (session-mode confirm leaves the
      client on the chosen `(S, W)` — P2.M2.T1.S1's Level-3 smoke turns GREEN).
- [ ] `tests/run.sh` GREEN (no regression).

## All Needed Context

### Context Completeness Check

_Pass_: a developer who has never seen this repo implements the single guard edit
from (a) the byte-exact oldText/newText below (TAB-indented — the comment + guard are
1 TAB; the select-window body is 2 TABs; the comment contains UTF-8 `§` and `—`),
(b) FINDING 2 (the three argv values restore.sh receives + their 8 call sites), FINDING
3 (the bug + both confirm sub-paths), FINDING 4 (STEP-1 stays safe — the verification
the work item asks for), FINDING 5 (STEP-3 is already cancel-only), FINDING 6
(no test breaks), FINDING 7 (byte-exact anchors). The edit touches ONLY the guard
operator/operand + the comment — no new vars, calls, state keys, or files.

### Documentation & References

```yaml
# MUST READ — the ONLY file you EDIT.
- file: scripts/restore.sh
  why: the STEP-2 block (~L98-108) is the edit surface. STEP-1 (client-aware unlink,
       ~L59-95) and STEP-3 (cancel-only switch, ~L109-128) define the surrounding
       teardown contract you must NOT disturb. STEP-2 today gates on `!= "keep-window"`;
       change it to `= "cancel"` + update the comment.
  pattern: |
    # the CURRENT STEP-2 (TAB-indented; § and — are UTF-8):
    	# --- STEP 2 (PRD §9 restore step 2): re-select the original window ---
    	... comment ...
    	orig_window="$(get_state "$ORIG_WINDOW" "")"
    	if [ "${1:-}" != "keep-window" ] && [ -n "$orig_window" ]; then
    		tmux select-window -t "$orig_window" 2>/dev/null || true
    	fi
  gotcha: TAB-indented (comment + guard = 1 TAB; select-window body = 2 TABs). The §
          and — are UTF-8 — copy byte-exact in oldText. set -u (NOT -e); keep the
          `2>/dev/null || true` on select-window. Do NOT touch STEP-1/STEP-3/STEP-4/5/6.

# MUST READ — the sibling whose confirm path calls `restore.sh keep` (HARD DEPENDENCY).
- docfile: plan/004_2c5127285a90/P2M2T1S1/PRP.md
  why: its FINDING 6 + Anti-Patterns name THIS task as the teardown half of the
       confirm-on-window contract. Both its non-self (L644) and self (L666) sub-paths
       call `restore.sh keep`. Its Level-3 smoke asserts the client lands on the chosen
       W — that smoke turns GREEN only after THIS task lands.
  critical: treat the P2.M2.T1.S1 PRP as a CONTRACT. Do NOT change the argv value its
            confirm path passes (it passes `keep` per the mandate); this task makes `keep`
            skip the re-select. Do NOT edit input-handler.sh.

# MUST READ — the gap analysis (the documented bug this closes).
- docfile: plan/004_2c5127285a90/architecture/gap_analysis_confirm_preview.md
  why: §(f) documents the exact divergence: "STEP 2 ... keep RE-SELECTS (divergence
       from PRD §9 — must be fixed so keep also skips)." and confirms STEP-1 is skipped
       on confirm/keep (client already switched).

# MUST READ — PRD §9 (restore order) + §6 Cancel (h3.8) + §6 Confirm (h3.7).
- docfile: PRD.md
  why: §9 restore step 2 ("cancel only; keep skips so the client stays on the chosen
       (S, W)"); §6 h3.8 (cancel = hard reset: re-select ORIG_WINDOW + switch back);
       §6 h3.7 (confirm commits the window; the client lands on S:W).
  section: "§9 State saved and restored", "§6 Behaviors > Cancel", "§6 Confirm"

# MUST READ — the ground-truth findings for THIS task (8 findings).
- docfile: plan/004_2c5127285a90/P2M2T2S1/research/findings.md
  why: FINDING 1 (the one-line guard change); FINDING 2 (argv matrix); FINDING 3 (the
       bug + both confirm sub-paths); FINDING 4 (STEP-1 stays safe — the work-item
       verification); FINDING 5 (STEP-3 already cancel-only); FINDING 6 (no test breaks);
       FINDING 7 (byte-exact anchors); FINDING 8 (set -u / house style).
  critical: FINDING 2 + 4 + 6 + 7 are load-bearing. Read BEFORE editing.
```

### Current Codebase tree (run `tree` in the repo root)

```bash
tmux-livepicker/
  scripts/
    restore.sh           # MODIFY: STEP-2 guard `!= "keep-window"` -> `= "cancel"` + comment.
    input-handler.sh     # UNCHANGED (the 3 confirm sub-paths + window-mode pass keep/keep-window).
    state.sh             # UNCHANGED (ORIG_WINDOW/STATE_LINKED_ID readonly constants).
    preview.sh options.sh utils.sh rank.sh layout.sh renderer.sh livepicker.sh session-mgmt.sh  # UNCHANGED
  tests/                 # UNCHANGED (no new test; formal window suite is P2.M3.T1.S1).
  README.md PRD.md       # UNCHANGED (Mode A: no docs).
  plan/004_2c5127285a90/{architecture/gap_analysis_confirm_preview.md, P2M2T1S1/PRP.md}
```

### Desired Codebase tree with files to be added and responsibility of file

```bash
scripts/restore.sh   # STEP-2: ONLY `cancel` re-selects ORIG_WINDOW. keep + keep-window skip
                     #   (the client stays where confirm put it). STEP-1/3/4/5/6 UNCHANGED.
```

### Known Gotchas of our codebase & Library Quirks

```bash
# CRITICAL (FINDING 7 — byte-exact match): the STEP-2 block is TAB-indented (comment +
# guard = 1 TAB; the select-window body = 2 TABs). The comment contains UTF-8 § and —.
# Copy them byte-exact in oldText; a space/ASCII-substitute will NOT match. Preserve the
# `2>/dev/null || true` on select-window (ORIG_WINDOW may have vanished in a race).

# CRITICAL (FINDING 2 — do NOT change the argv contract): restore.sh receives EXACTLY three
# argv values — `keep`, `keep-window`, `cancel` — from 8 call sites in input-handler.sh +
# livepicker.sh. The guard `= "cancel"` partitions them correctly. Do NOT edit any caller;
# do NOT rename argv[1]; do NOT switch keep->keep-window or vice versa (P2.M2.T1.S1's
# contract MANDATES `keep` from its session-confirm sub-paths).

# CRITICAL (FINDING 4 — STEP-1 stays safe, do NOT touch it): STEP-1's client-aware unlink
# (guard: current_session == ORIG_SESSION) is SKIPPED on non-self keep (client switched to
# S; the driver preview was already H2-unlinked by confirm before the switch) and harmlessly
# no-ops on self keep (a redundant unlink of an already-dropped foreign link, swallowed by
# `2>/dev/null || true`). This STEP-2 edit does not affect STEP-1. Leave STEP-1 alone.

# GOTCHA (FINDING 5 — consistency, not refactor): STEP-3 already reads `[ "$mode" = "cancel" ]`.
# After the fix STEP-2 reads `[ "${1:-}" = "cancel" ]` — the same cancel-only shape. Do NOT
# refactor the two steps to share a `mode` var; keep STEP-2 using `${1:-}` (the minimal,
# single-line, low-risk edit). STEP-3's `mode="${1:-}"` is its own local.

# GOTCHA (FINDING 8): restore.sh runs under `set -u` (state.sh). `${1:-}` already defaults
# argv[1] — keep it. NEVER add `set -e` (restore must not abort on a non-zero tmux call).
# No new `local`, no new tmux call, no new state key, no new file.
```

## Implementation Blueprint

### Data models and structure

No data model / state change. STEP-2 reads `ORIG_WINDOW` (a readonly CONTRACT constant
from state.sh) and argv[1] (`keep`|`keep-window`|`cancel`). It mutates only the active
window of whatever session ORIG_WINDOW belongs to — and ONLY on `cancel` after the fix.

The argv → STEP-2 behavior table after the fix:

| argv[1]   | STEP-2 re-selects ORIG_WINDOW? | why                                                    |
|-----------|-------------------------------|--------------------------------------------------------|
| `cancel`  | YES                            | hard reset — restore the driver's pre-activation window |
| `keep`    | NO (the fix)                  | client is already on the chosen (S, W) confirm committed |
| `keep-window` | NO (unchanged)            | client is already on the chosen window (window-mode confirm) |

### Implementation Tasks (ordered by dependencies)

```yaml
Task 1: EDIT scripts/restore.sh — STEP-2 guard + comment (the ONLY change)
  - FILE: ./scripts/restore.sh (EXISTING). The STEP-2 block — the `# --- STEP 2 ...`
    comment line through the closing `fi`. Today the guard is `!= "keep-window"`.
  - oldText — COLUMN-0 fenced block; each leading char is a real TAB (comment + guard
    = 1 TAB; the select-window body = 2 TABs). The § and — are UTF-8. Copy byte-exact:

```bash
	# --- STEP 2 (PRD §9 restore step 2): re-select the original window ---
	# ORIG_WINDOW is the @N id activate saved (NOT an index — renumber-windows on).
	# Guard on non-empty + ignore rc (ORIG_WINDOW could have vanished in a race).
	# M1 FIX: the `keep-window` mode (window-mode confirm) SKIPS this re-select so
	# the chosen window selection survives — the caller already switched the
	# client to the target session and selected the target window. Re-selecting
	# ORIG_WINDOW here would strand the client on the original window.
	orig_window="$(get_state "$ORIG_WINDOW" "")"
	if [ "${1:-}" != "keep-window" ] && [ -n "$orig_window" ]; then
		tmux select-window -t "$orig_window" 2>/dev/null || true
	fi
```

  - newText — COLUMN-0 fenced block (comment + guard = 1 TAB; select-window body = 2
    TABs). The orig_window read + select-window body + fi are byte-identical to the
    oldText; ONLY the comment text + the guard line change. Copy byte-exact:

```bash
	# --- STEP 2 (PRD §9 restore step 2): re-select the original window ---
	# ORIG_WINDOW is the @N id activate saved (NOT an index — renumber-windows on).
	# Guard on non-empty + ignore rc (ORIG_WINDOW could have vanished in a race).
	# P2.M2.T2 UNIFICATION: ONLY `cancel` re-selects ORIG_WINDOW (undoing any
	# self-session window-flip and restoring the driver to its pre-activation
	# window). Both `keep` (session-mode confirm — PRD §6/h3.7; the client is
	# already on the chosen (S, W) that confirm just committed) and `keep-window`
	# (window-mode confirm — the client is already on the chosen window) SKIP this
	# so the client stays where the confirm put it. Re-selecting ORIG_WINDOW on
	# `keep` would yank the client off the chosen (S, W). STEP-3's switch is
	# cancel-only too (below) — STEP-2/STEP-3 are now a uniform cancel-only pair.
	orig_window="$(get_state "$ORIG_WINDOW" "")"
	if [ "${1:-}" = "cancel" ] && [ -n "$orig_window" ]; then
		tmux select-window -t "$orig_window" 2>/dev/null || true
	fi
```

  - FOLLOW pattern: STEP-3's cancel guard directly below (`if [ "$mode" = "cancel" ]`).
  - NAMING: none new — reuse `${1:-}` (argv[1]) + `$orig_window` (already declared in
    restore_main's `local` line).
  - DEPENDENCIES: P2.M2.T1.S1 (the session-confirm that calls `restore.sh keep`) — this
    task is the teardown half of that contract.

Task 2: VALIDATE (L1 grep + L2 suite + L3 confirm-on-window smoke)
  - RUN: bash -n scripts/restore.sh ; shellcheck scripts/restore.sh.
  - RUN: grep cross-checks (STEP-2 cancel-only; keep-window gone from restore.sh's guard;
        no unintended edits to STEP-1/3/4/5/6 or any caller).
  - RUN: tests/run.sh (expect GREEN; no test breaks — FINDING 6).
  - RUN: L3 isolated-socket session-confirm-on-flipped-window smoke (activate → flip →
        Enter → assert #{window_id} == the chosen W, NOT ORIG_WINDOW). This is the
        P2.M2.T1.S1 Level-3 smoke; it goes GREEN only after THIS task lands (with
        defer off, deterministic). See the Validation Loop.
```

### Implementation Patterns & Key Details

```bash
# === The entire change: the STEP-2 guard (FINDING 1). ===
# BEFORE:
# 	if [ "${1:-}" != "keep-window" ] && [ -n "$orig_window" ]; then
# 		tmux select-window -t "$orig_window" 2>/dev/null || true
# 	fi
# AFTER (cancel-only — mirrors STEP-3's `if [ "$mode" = "cancel" ]`):
# 	if [ "${1:-}" = "cancel" ] && [ -n "$orig_window" ]; then
# 		tmux select-window -t "$orig_window" 2>/dev/null || true
# 	fi

# === Why cancel-only is correct (FINDING 2 + 3) ===
# cancel  -> re-select ORIG_WINDOW (hard reset; PRD §6 h3.8).  [STILL re-selects]
# keep    -> SKIP (client on chosen S,W; PRD §9 step 2).       [THE FIX — was re-selecting]
# keep-window -> SKIP (client on chosen window; window-mode).  [unchanged]
```

### Integration Points

```yaml
RESTORE (restore.sh STEP-2): REPLACE the guard `!= "keep-window"` with `= "cancel"` + update
  the comment. STEP-1 (client-aware unlink), STEP-3 (cancel-only switch), STEP-4/5/6
  UNCHANGED.

INPUT-HANDLER (input-handler.sh): NO CHANGE. The 3 confirm sub-paths keep passing
  keep / keep-window; the cancel paths keep passing cancel. (window-mode confirm at L603
  -> keep-window; session-mode confirm at L644/L666 -> keep; cancel at L700/L706/L765;
  _confirm_land_on_session at L119 -> keep; livepicker.sh:524 deactivate -> cancel.)

STATE (state.sh): NO CHANGE. ORIG_WINDOW + STATE_LINKED_ID are readonly constants.

PREVIEW / ACTIVATE / OPTIONS / README / DOCS: NO CHANGE (Mode A — internal teardown).

DATABASE / MIGRATIONS / ROUTES / CONFIG-FILE: none.
```

## Validation Loop

### Level 1: Syntax & Style (Immediate Feedback)

```bash
cd /home/dustin/.config/tmux/plugins/tmux-livepicker
bash -n scripts/restore.sh && echo "OK: syntax"            # expect exit 0
shellcheck scripts/restore.sh                               # expect 0 findings
# STEP-2 is now cancel-only (EXACTLY one guard):
grep -c '\[ "\${1:-}" = "cancel" \] && \[ -n "\$orig_window" \]' scripts/restore.sh   # == 1
# The old keep-window guard is GONE from restore.sh:
grep -c '!= "keep-window"' scripts/restore.sh               # == 0
# SCOPE GUARD: STEP-3's cancel-only switch is untouched (still present):
grep -c '\[ "\$mode" = "cancel" \]' scripts/restore.sh      # == 1
# SCOPE GUARD: the select-window -t "$orig_window" body + 2>/dev/null || true survive:
grep -c 'select-window -t "\$orig_window" 2>/dev/null || true' scripts/restore.sh   # == 1
# SCOPE GUARD: STEP-1's client-aware unlink guard is untouched:
grep -c '\[ "\$current_session" = "\$orig_session" \]' scripts/restore.sh   # == 1
# SCOPE GUARD: the window-mode CALLER (input-handler.sh) still passes keep-window (out of scope):
grep -c 'restore.sh" keep-window' scripts/input-handler.sh  # == 1
# No space-indent on the new lines (tabs only) — the block is TAB-indented:
grep -nPn '^\t*    [^#/]' scripts/restore.sh | tail && echo "WARN: space-indent" || echo "OK: tabs"
# Expected: cancel-guard == 1; keep-window-in-restore == 0; mode-cancel == 1; select-body == 1;
#           STEP-1 guard == 1; caller keep-window == 1; tabs only.
```

### Level 2: Full suite (no regression)

```bash
cd /home/dustin/.config/tmux/plugins/tmux-livepicker
tests/run.sh
# Expected: exit 0, all green. cancel tests still re-select ORIG_WINDOW (FINDING 6);
# test_window_confirm_lands_on_chosen_window uses keep-window (still skips); the session-mode
# confirm index-ordering test queries the driver by name (unaffected by which window is active).
# No existing test asserts that session-mode `keep` RE-SELECTS ORIG_WINDOW, so none break.
```

### Level 3: Session-mode confirm leaves the client on the chosen (S, W)

```bash
# This is the P2.M2.T1.S1 Level-3 smoke — it goes GREEN only after THIS task lands
# (before, keep re-selected ORIG_WINDOW and the landed window read as ORIG_WINDOW).
# Deterministic: defer off. Requires P2.M2.T1.S1's confirm rework to have landed.
cat > /tmp/smoke_keep_skip.sh <<'EOF'
#!/usr/bin/env bash
set -u
cd /home/dustin/.config/tmux/plugins/tmux-livepicker
source tests/setup_socket.sh; source tests/helpers.sh
fail=0
setup_test "lp-keepskip"; attach_test_client
tmux set-option -g @livepicker-preview-defer off   # deterministic synchronous preview
tmux new-session -d -s multi -x 120 -y 40
tmux new-window -t multi -n secondwin        # multi has 2 windows
"$LIVEPICKER_SCRIPTS/livepicker.sh"
"$LIVEPICKER_SCRIPTS/input-handler.sh" next-session >/dev/null 2>&1 || true   # highlight -> multi
"$LIVEPICKER_SCRIPTS/input-handler.sh" next-window  >/dev/null 2>&1 || true   # flip multi's windows
sleep 0.2
# Resolve the chosen W from the window cursor (mirror confirm's authoritative read).
_cl="$(tmux show-option -gqv @livepicker-cand-win-list)"
_cur="$(tmux show-option -gqv @livepicker-cand-win-cursor)"
[[ "$_cur" =~ ^[0-9]+$ ]] || _cur=0
exp_id="$(awk -v c="$_cur" 'NR==(c+1){print; exit}' <<<"$_cl")"
"$LIVEPICKER_SCRIPTS/input-handler.sh" confirm >/dev/null 2>&1 || true   # commit + restore keep
sleep 0.2
got_sess="$(tmux display-message -p '#{session_name}' 2>/dev/null)"
got_win="$(tmux display-message -p '#{window_id}'  2>/dev/null)"
echo "[keep-skip] want sess=multi win=$exp_id ; got sess=$got_sess win=$got_win"
[ "$got_sess" = "multi"  ] || { echo "FAIL: session != multi"; fail=1; }
[ "$got_win"  = "$exp_id" ] || { echo "FAIL: window != $exp_id (did keep re-select ORIG_WINDOW?)"; fail=1; }
teardown_test
[ "$fail" -eq 0 ] && echo "ALL OK: keep skipped the ORIG_WINDOW re-select" || exit 1
EOF
bash /tmp/smoke_keep_skip.sh; rc=$?; rm -f /tmp/smoke_keep_skip.sh; exit $rc
# Expected: the client lands and STAYS on multi:<the flipped window id>. If got_win is the
# driver's ORIG_WINDOW, the keep-skip did NOT land — re-check the STEP-2 guard == "= "cancel"".
#
# CANCEL regression variant (cancel MUST still re-select ORIG_WINDOW): in a fresh setup,
# activate -> next-session -> cancel -> assert #{session_name}==driver AND #{window_id}==ORIG_WINDOW
# (cancel is a hard reset). This is already covered by test_restore_cancel_layout_exact (Level 2).
```

### Level 4: Creative & Domain-Specific Validation

```bash
# (1) Self-session confirm (P2.M2.T1.S1 self path): flip the DRIVER to a non-ORIG window,
#     Enter, assert #{session_name}==driver (no switch) AND #{window_id}==the flipped driver
#     window (NOT ORIG_WINDOW). Before this fix, keep re-selected ORIG_WINDOW and moved the
#     driver off the chosen W — the smoke catches that regression.
# (2) STEP-1 no-leak regression (non-self confirm): after confirm on a flipped window, the
#     driver must NOT retain the preview link. Assert the driver's window-id list no longer
#     contains the previously-linked candidate window (confirm H2-unlinked it before the
#     switch; STEP-1 then correctly no-ops because current_session != ORIG_SESSION). This
#     verifies FINDING 4 (STEP-1 stays safe) empirically.
# (3) keep-window parity (window-mode confirm): the window-mode confirm smoke
#     (test_window_confirm_lands_on_chosen_window in test_functional.sh) stays GREEN —
#     keep-window still skips the re-select (now via the cancel-only guard).
```

## Final Validation Checklist

### Technical Validation

- [ ] `bash -n` + `shellcheck` clean on `scripts/restore.sh`.
- [ ] STEP-2 guard reads `[ "${1:-}" = "cancel" ]` (L1 == 1); `!= "keep-window"` gone
      from restore.sh (L1 == 0); the window-mode CALLER still passes keep-window (L1 == 1).
- [ ] STEP-3's `[ "$mode" = "cancel" ]` untouched (L1 == 1); STEP-1's
      `[ "$current_session" = "$orig_session" ]` untouched (L1 == 1).
- [ ] The select-window body + `2>/dev/null || true` survive (L1 == 1); tabs only.

### Feature Validation

- [ ] `cancel` STILL re-selects ORIG_WINDOW + switches back (Level 2 cancel tests GREEN).
- [ ] `keep` (session-mode confirm) no longer re-selects ORIG_WINDOW — the client lands
      and STAYS on the chosen (S, W) (Level 3).
- [ ] `keep-window` (window-mode confirm) still skips the re-select (Level 4.3 /
      test_window_confirm_lands_on_chosen_window GREEN).
- [ ] STEP-1 does not leak the driver preview on a non-self confirm (Level 4.2 — FINDING 4).
- [ ] Self-session confirm leaves the driver on the chosen W, not ORIG_WINDOW (Level 4.1).
- [ ] `tests/run.sh` GREEN (Level 2).

### Code Quality Validation

- [ ] The change is the minimal single-guard edit (+ comment); no new vars/calls/keys/files.
- [ ] `set -u` honored (`${1:-}`); NEVER `set -e`; `2>/dev/null || true` preserved.
- [ ] No caller edited; argv contract (`keep`/`keep-window`/`cancel`) unchanged.
- [ ] TAB indentation + UTF-8 §/— preserved in the comment.

### Documentation & Deployment

- [ ] No README / CHANGELOG / docs edit (Mode A — internal teardown; DOCS: none per the
      work item; the changeset CHANGELOG is P4.M1.T1.S2).
- [ ] No new test file (the formal window-flip + confirm-on-window suite is P2.M3.T1.S1);
      L3 is a throwaway smoke.

---

## Anti-Patterns to Avoid

- ❌ Don't change the guard to anything other than `= "cancel"`. The work-item contract is
  literal: ONLY cancel re-selects; keep + keep-window skip. `!= "keep"` would also work
  numerically but diverges from the contract's stated form and from STEP-3's `= "cancel"`
  pattern. Use `= "cancel"` for the uniform cancel-only pair. (FINDING 1, 5.)
- ❌ Don't edit any CALLER. P2.M2.T1.S1's session-confirm sub-paths MANDATE `restore.sh keep`
  (its Anti-Patterns forbid switching to keep-window to dodge this task). This task makes
  `keep` skip; it does not rename the argv value. Leave input-handler.sh byte-unchanged.
  (FINDING 2.)
- ❌ Don't touch STEP-1. Its client-aware unlink guard (`current_session == ORIG_SESSION`)
  is correct under the confirm rework: skipped on non-self keep (client switched; driver
  preview already H2-unlinked by confirm), harmlessly no-ops on self keep (redundant unlink
  of an already-dropped link, swallowed by `|| true`). This STEP-2 edit does not affect it.
  (FINDING 4.)
- ❌ Don't refactor STEP-2/STEP-3 to share a `mode` var. Keep STEP-2's `${1:-}` (the minimal,
  single-line edit); STEP-3's `mode="${1:-}"` is its own local. Low risk > cleverness.
  (FINDING 5, 8.)
- ❌ Don't add a new test file or docs. Mode A (DOCS: none); the formal window suite is
  P2.M3.T1.S1. L3 is a throwaway smoke that re-uses P2.M2.T1.S1's.
- ❌ Don't use SPACES for indent or ASCII for §/—. The block is TAB-indented (comment + guard
  = 1 TAB; select-window body = 2 TABs); the comment has UTF-8 § and —. Copy byte-exact in
  oldText or the edit will not match. (FINDING 7.)
- ❌ Don't drop the `2>/dev/null || true` on the select-window, and don't add `set -e`. restore
  must never abort on a non-zero tmux call (ORIG_WINDOW may have vanished in a race; a
  transient failure must not abort a half-restored teardown). (FINDING 8.)

---

## Confidence Score

**9 / 10** for one-pass success. Rationale: the change is ONE guard comparison operator +
operand (`!= "keep-window"` → `= "cancel"`) plus a comment update, in ONE file, with the
`orig_window` read / select-window body / `fi` byte-identical. It mirrors STEP-3's
already-shipped `[ "$mode" = "cancel" ]` pattern (a proven, identical shape). The argv
contract is fully pinned (exactly three values from 8 verified call sites — FINDING 2), the
bug and both confirm sub-paths are documented (FINDING 3), STEP-1's continued safety is
verified (FINDING 4 — the work-item's explicit verification ask), and no existing test
breaks (FINDING 6). The only residual coupling is the HARD DEPENDENCY on P2.M2.T1.S1
landing its confirm rework (both sub-paths call `restore.sh keep`) — but THIS task is
teardown-only and is independently correct: the Level-3 smoke goes GREEN once the sibling
lands, and the Level-2 suite is GREEN unconditionally. The byte-exact TAB/UTF-8 anchors
(FINDING 7) remove the only mechanical risk.
