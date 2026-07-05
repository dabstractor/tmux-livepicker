# PRP — P1.M5.T2.S1: restore.sh — keep (no switch) / cancel (switch-client to ORIG_SESSION)

---

## Goal

**Feature Goal**: **MODIFY** `scripts/restore.sh` (created by P1.M5.T1.S1, which is
being implemented in parallel and is treated as a CONTRACT here) to fill the **T2
seam** — PRD §9 restore **step 3**, the keep/cancel client branch. This is a single,
surgical edit that replaces the T2 placeholder comment (left by T1.S1 between STEP 2
and `return 0`) with the real branch:

- **`cancel`** → `tmux switch-client -t "=$ORIG_SESSION"` (exact-match `=` prefix,
  PRD §13). This is the **only** `switch-client` in the cancel path. It returns the
  client to the session it started in.
- **`keep`** → **do nothing.** The ONE `switch-client` to the chosen target was
  already issued by `input-handler.sh confirm` (P1.M6.T3.S1 — PLANNED) before
  `restore.sh keep` ran; the client is already on the chosen target.

This is the **crux of the pollution invariant** (PRD §14): the cancel path must
yield **0 net session-history entries** and the keep path must yield **0
*additional*** entries (the single entry comes from confirm, not restore). Research
PROVES the invariant holds via the real `tmux-session-history` engine's same-session
dedup — NOT because the hook is silent (see FINDING A; it does fire).

**Deliverable**: A single in-place edit to `scripts/restore.sh`: (1) extend the
`restore_main` `local` line to add `orig_session` + `mode`; (2) replace the T2 seam
comment block with STEP 3 (read `mode="${1:-}"`, read `orig_session` via
`get_state "$ORIG_SESSION" ""`, and `if [ "$mode" = "cancel" ] && [ -n "$orig_session" ]:
tmux switch-client -t "=$orig_session" 2>/dev/null || true`). No other file is touched.
STEP 1 (unlink), STEP 2 (select-window), the T3 seam, the T4 seam, and the driver are
all left untouched.

**Success Definition**:
- `bash -n scripts/restore.sh` passes; `shellcheck scripts/restore.sh` is clean
  (0 findings; the existing file-level `# shellcheck disable=SC1091,SC2153` from
  T1.S1 still covers everything — T2 adds no new disable). Tabs only; `set -u`,
  NO `set -e`.
- **cancel switches exactly once** — to `=$ORIG_SESSION` via exact-match; guarded on
  `mode == "cancel"` AND `orig_session` non-empty; `2>/dev/null || true` (rc=1 when
  the session vanished — FINDING C).
- **keep is a true no-op** — no `switch-client`, no other mutation in the keep path.
- **Pollution invariant (work-item §5 MOCKING):** under the socket shim with a
  **deduping** recorder wired to `client-session-changed` (mirrors the real engine's
  `[ "$to" = "$CURRENT" ] && return`): browse → `restore.sh cancel` → **0** entries;
  browse → simulated confirm switch → `restore.sh keep` → **1** entry (the confirm
  switch; keep added 0). A naive recorder is explicitly WRONG (FINDING A/B).
- **No off-limits work:** STEP 3 ONLY. NO re-touching of STEP 1/STEP 2 (T1.S1), NO
  status / status-format / key-table / renumber / hook restore (T3), NO
  `select-layout` / `clear_all_state` / `unbind-key` (T4). Those seams stay as
  comments.

## User Persona (if applicable)

**Target User**: None directly (internal teardown step 3 of 6). Transitively: the end
user who pressed cancel or confirm (PRD §3 stories 3–4). T2.S1 is what makes the
**cancel** story ("I press Escape ... everything is exactly as it was") literally
true at the session-navigation level: it puts the client back on the original session
with the session-history timeline byte-for-byte unchanged. And it makes the **keep**
story ("I press Enter ... the client switches to it") stop at exactly one switch —
no double-switch pollution.

**Use Case**: The user browsed sessions (a foreign window was linked+selected inside
the driver; the client never left `ORIG_SESSION`). They pressed confirm or cancel →
`input-handler.sh` (P1.M6) invokes `restore.sh <keep|cancel>`. T1.S1 (steps 1–2) ran
FIRST inside `restore_main` (unlinked the preview, re-selected `ORIG_WINDOW`). **T2.S1
(this task)** runs NEXT: on `cancel` it switches the client back to `ORIG_SESSION`;
on `keep` it does nothing (confirm already switched). After T2, the client is on the
intended session; T3/T4 restore the rest (status/keys/layout/state).

**User Journey** (T2.S1 scope — the client lands on the right session):
1. …T1.S1 unlinked the preview window and re-selected `ORIG_WINDOW`. The client is
   still in `ORIG_SESSION` (browse never switched it — Invariant A).
2. **T2.S1 (this task):** reads `argv[1]` and `@livepicker-orig-session`.
   - `cancel` → `switch-client -t "=$ORIG_SESSION"`. The hook fires; the engine
     dedups (same session) → 0 history entries. The client is back where it started.
   - `keep` → nothing. Confirm already moved the client to the chosen target; the
     engine recorded that as the single navigation.
3. T3/T4 (sibling subtasks, seam-marked) finish: restore status/keys/hook, restore
   layout, clear state, unbind the table.

**Pain Points Addressed**:
- (a) **Stranded on the wrong session (cancel).** Without the cancel switch, the
  client would remain wherever the last preview left it — but since preview never
  switches the *client* (only links+selects within the driver), the client is in
  fact still on `ORIG_SESSION`. So why switch at all? Because the contract is
  **symmetric and defensive**: it guarantees the client is on `ORIG_SESSION`
  regardless of any future change to preview/activate, and it is the explicit
  counterpart of the keep switch. The switch is cheap (rc=0, hook deduped) and
  makes "everything is exactly as it was" provable rather than incidental.
- (b) **Double-switch pollution (keep).** If `keep` *also* issued a `switch-client`
  to the chosen target, the engine would record a SECOND navigation — breaking the
  "exactly one switch" invariant and corrupting the back/forward timeline. T2.S1's
  keep branch does nothing, so the count stays at one.

## Why

- **PRD §9 "State saved and restored"** is the controlling spec. Restore step 3:
  "If cancel: `switch-client -t "$ORIG_SESSION"` (return to the original session).
  If keep: do not switch (stay on the chosen target)." T2.S1 owns exactly this step.
- **PRD §13 "tmux primitives reference":** "`switch-client -t "=S"` for the single
  confirm-time session switch" — note the `=` exact-match prefix. T2.S1's cancel
  switch uses the identical exact-match form (verified — FINDING C).
- **PRD §14 "Pollution and compatibility analysis":** "Cancel: zero `switch-client`
  to a different session. History and toggle are exactly as before activation." T2.S1
  is what makes this TRUE. Research (FINDING A) proved the *mechanism*: the cancel
  switch fires `client-session-changed`, but the real engine's `do_hook` short-circuits
  on `[ "$to" = "$CURRENT" ] && return` → zero timeline mutation.
- **Boundary respect.** T2.S1 touches ONLY: (1) one argv read (`"${1:-}"`); (2) one
  state read (`@livepicker-orig-session` via `get_state`); (3) at most one tmux
  mutation (`switch-client`, cancel only). It does NOT: re-touch unlink/select
  (T1.S1), mutate status/status-format/key-table/renumber/hook (T3), restore layout
  or clear state or unbind keys (T4), or call `link-window`/`capture-pane` (preview.sh).
- **Scope cohesion.** T2.S1 is the restore counterpart of `input-handler.sh confirm`'s
  switch: confirm switches the client FORWARD to the chosen target (the one navigation);
  T2.S1 cancel switches the client BACK to the origin (deduped to a no-op). keep is
  the absence of a second switch. The two share the `@livepicker-orig-session` contract
  (activate STEP 2 writes it; T2.S1 reads it as the cancel switch target).

## What

A surgical edit to the existing `scripts/restore.sh` (the file T1.S1 created). Two
changes, both inside `restore_main`:

1. **Extend the `local` declaration** (line `local linked_id orig_window current_session`)
   to add the two T2 locals: `local linked_id orig_window current_session orig_session mode`.
2. **Replace the T2 seam comment block** (the 4-line `# --- T2 (P1.M5.T2.S1) ...` block
   T1.S1 left between STEP 2 and `return 0`) with STEP 3:
   - read `mode="${1:-}"` (defaulted for `set -u` safety);
   - read `orig_session="$(get_state "$ORIG_SESSION" "")"`;
   - `if [ "$mode" = "cancel" ] && [ -n "$orig_session" ]; then tmux switch-client -t "=$orig_session" 2>/dev/null || true; fi`
   - (keep: intentionally no else — doing nothing is the contract.)

The header doc-comment's seam map (lines describing "3. keep: do not switch. cancel:
switch-client -t "$ORIG_SESSION". [T2 seam]") already describes T2; T2.S1 may leave
the header as-is (it remains accurate) — no header edit is required. (Optional: change
`[T2 seam]` to `[T2]` on that line to mark it done; not required for success.)

### Success Criteria

- [ ] `scripts/restore.sh` still passes `bash -n` + `shellcheck` (0 findings; no new
      `disable` needed — T2 adds no word-split on user input; `${1:-}` is standard).
- [ ] The `restore_main` `local` line now includes `orig_session` and `mode`.
- [ ] The T2 seam comment block is REPLACED by STEP 3 logic (the comment block is gone;
      the branch is present).
- [ ] cancel: `switch-client -t "=$orig_session"` runs ONLY when `mode == "cancel"`
      AND `orig_session` is non-empty; uses the `=` exact-match prefix; ends with
      `2>/dev/null || true`.
- [ ] keep: NO `switch-client` and NO mutation (true no-op).
- [ ] Tabs only (`grep -Pn '^    '` empty); `set -u`, NO `set -e`.
- [ ] NO off-limits work: STEP 1 (unlink) and STEP 2 (select-window) unchanged; the
      T3 and T4 seam comments still present and unchanged; the driver unchanged.
- [ ] Mock (work-item §5): deduping recorder → cancel produces **0** net entries;
      simulated-confirm + keep produces **1** net entry (keep adds 0). See Validation
      Loop §2.

## All Needed Context

### Context Completeness Check

_Pass_: A developer who has never seen this repo can implement T2.S1 from
(a) the verbatim STEP 3 block in "Implementation Patterns & Key Details" (complete,
ready to paste in place of the T2 seam comment), (b) the 7 live-verified findings in
`research/restore_keep_cancel_findings.md` — most critically **FINDING A** (same-session
`switch-client` DOES fire `client-session-changed`; the invariant holds via the engine's
`do_hook` short-circuit, NOT a silent hook), **FINDING B** (the mock recorder MUST
dedup — a naive counter FALSE-FAILS cancel), **FINDING C** (`=` exact-match works;
rc=1 on a missing session → `2>/dev/null || true`), and **FINDING E** (read
`ORIG_SESSION` via `get_state`, not `display-message`), and (c) the socket-shim mock
that runs the REAL `restore.sh` under a deduping recorder and asserts cancel→0 /
confirm+keep→1. The INPUT dependencies (`state.sh` ORIG_SESSION/get_state, the
`restore.sh` file with the T2 seam from T1.S1) are COMPLETE/present. The real engine
source (`session_history.sh do_hook`) is quoted verbatim in the research file as the
ground-truth for the dedup.

### Documentation & References

```yaml
# MUST READ — the HOST FILE (the file this task edits). Created by P1.M5.T1.S1 (parallel;
#   treated as a CONTRACT — assume it exists exactly as T1.S1's PRP specifies).
- file: scripts/restore.sh
  why: contains restore_main() with STEP 1 (unlink) + STEP 2 (select-window) + the T2
       seam comment (the 4-line "# --- T2 (P1.M5.T2.S1): keep/cancel client branch
       (insert here) ---" block between STEP 2 and `return 0`) that T2.S1 REPLACES, plus
       the T3/T4 seams. T2.S1 also extends the `local linked_id orig_window current_session`
       line to add `orig_session mode`. The file already sources the lib trio and already
       has `# shellcheck disable=SC1091,SC2153`.
  pattern: STEP 1/STEP 2 use `2>/dev/null || true` on every fail-possible tmux call;
           `get_state "$STATE_*/ORIG_*" ""` for state reads; ONE tab indent. T2's
           switch-client follows the SAME `2>/dev/null || true` idiom.
  critical: T2.S1 is a SURGICAL EDIT — touch ONLY the `local` line and the T2 seam block.
            Do NOT touch STEP 1, STEP 2, the T3/T4 seams, or the driver.

# MUST READ — INPUT dependency: state.sh (ORIG_SESSION / get_state). COMPLETE, unchanged.
- file: scripts/state.sh
  why: readonly ORIG_SESSION="@livepicker-orig-session" (the driver/original session name
       activate STEP 2 saved via `tmux display-message -p '#{session_name}'`; the cancel
       switch target), get_state (the STATE_*/ORIG_* read accessor -> tmux show-option
       -gqv; ${2:-} default makes it safe under set -u). T2.S1 uses
       `get_state "$ORIG_SESSION" ""`.
  critical: ORIG_SESSION is the bare session NAME (e.g. "main"), not an id. The `=` prefix
            is prepended at the switch-client call site ("=$orig_session"), NOT stored.

# MUST READ — the empirical ground-truth for THIS task (7 live-verified findings).
- docfile: plan/001_fd5d622d3939/P1M5T2S1/research/restore_keep_cancel_findings.md
  why: FINDING A (LOAD-BEARING: switch-client to the SAME session DOES fire
       client-session-changed — naive counter 1->2; the invariant holds because the real
       engine's do_hook short-circuits on [ "$to" = "$CURRENT" ] && return); FINDING B
       (the mock recorder MUST dedup, mirroring the engine, or cancel FALSE-FAILS);
       FINDING C (= exact-match disambiguates; rc=1 on missing session -> || true);
       FINDING D (keep is a true no-op; confirm owns the ONE switch); FINDING E (read
       ORIG_SESSION via get_state, NOT display-message — deterministic, client-independent);
       FINDING G (the T2 seam is an in-place replacement of the comment block; extend the
       local line).
  critical: Read BEFORE writing the branch. FINDING A is the highest-consequence
            correctness+testability detail (it explains WHY cancel->0 despite the hook
            firing, and WHY the mock recorder must dedup). FINDING C is the highest-
            consequence robustness detail (a missing || true would abort under a future
            set -e; a non-exact-match target could collide with a prefix-named session).

# MUST READ — the real engine source (the ground-truth for the dedup that makes cancel->0).
- file: /home/dustin/.config/tmux/plugins/tmux-session-history/scripts/session_history.sh
  why: do_hook() — the reactive handler wired to client-session-changed. The line
       `[ "$to" = "$CURRENT" ] && { S "$(H walk)" ""; return; }` is the SAME-SESSION
       SHORT-CIRCUIT that proves cancel->0 (the hook fires, the engine records nothing).
       Confirms the work-item RESEARCH NOTE point 1 and PRD §14's cancel claim.
  section: do_hook (search for `"[ "$to" = "$CURRENT" ]"`)

# MUST READ — the real engine's hook wire (the exact pattern the mock recorder copies).
- file: /home/dustin/.config/tmux/plugins/tmux-session-history/session_history.tmux
  why: line 22 — `tmux set-hook -g client-session-changed "run-shell '${SCRIPT} hook
       \"#{session_name}\"'"`. The mock's deduping recorder wires identically:
       `run-shell '$REC \"#{session_name}\"'` (passes the new session as $1).
  section: line 22

# MUST READ — the PRD sections selected for this work item.
- docfile: PRD.md
  why: §9 "State saved and restored" (restore step 3: cancel -> switch-client -t
       "$ORIG_SESSION"; keep -> do not switch); §13 "tmux primitives reference"
       (switch-client -t "=S" exact-match); §14 "Pollution and compatibility analysis"
       (cancel: zero switch-client to a different session; confirm: exactly one).
  section: "§9 State saved and restored", "§13 tmux primitives reference", "§14 Pollution and compatibility analysis"

# MUST READ — system ground-truth.
- docfile: plan/001_fd5d622d3939/architecture/system_context.md
  why: §3 INVARIANT A (browsing never fires client-session-changed -> the client is still
       on ORIG_SESSION at cancel time, so the cancel switch is a same-session event ->
       engine dedups -> 0 entries); §6 (session-history composition: newline-separated,
       deduped, driven by client-session-changed); §9 shell style (set -u ONLY, NO -e,
       tabs, local for all function locals, || true on fail-possible tmux calls).
  section: "§3 The three load-bearing invariants", "§6 tmux-session-history composition", "§9 Shell style"

# MUST READ — primitive ground-truth.
- docfile: plan/001_fd5d622d3939/architecture/tmux_primitives.md
  why: §4 (client-session-changed fires on switch-client — verified; this is why the
       cancel hook fires at all); §7 (switch-client -t '=S' exact-match prefix; the only
       command in the flow that fires client-session-changed).
  section: "§4 set-hook / session-window-changed / client-session-changed", "§7 switch-client -t '=S' exact-match"

# MUST READ — the T1.S1 PRP (the CONTRACT for the host file this task edits).
- docfile: plan/001_fd5d622d3939/P1M5T1S1/PRP.md
  why: defines scripts/restore.sh's full skeleton, STEP 1, STEP 2, and the exact T2/T3/T4
       seam comments. T2.S1 assumes this file exists as specified. T1.S1's FINDING 4
       (display-message non-deterministic detached) is why T2 reads ORIG_SESSION via
       get_state instead.
  section: "Implementation Patterns & Key Details" (the complete restore.sh listing, incl. the T2 seam)

# REFERENCE — the sibling PRPs that share this file (seam contract).
- docfile: plan/001_fd5d622d3939/P1M5T3S1/PRP.md
  why: (if present) T3 owns restore step 4 (status/status-format/key-table/renumber/hook).
       Inserts at the T3 seam AFTER T2's block. T2 must leave that seam intact.
- docfile: plan/001_fd5d622d3939/P1M5T4S1/PRP.md
  why: (if present) T4 owns restore steps 5-6 (select-layout + clear_all_state + unbind).
       Inserts at the T4 seam AFTER T3. T2 must leave that seam intact.
- docfile: plan/001_fd5d622d3939/P1M6T3S1/PRP.md
  why: (PLANNED, not yet written) confirm issues the ONE switch-client to the chosen
       target BEFORE invoking `restore.sh keep`. T2's keep branch does nothing precisely
       because confirm already switched. T2 reads argv[1]='keep'|'cancel' that confirm/
       cancel (P1.M6.T4.S1) pass.
```

### Current Codebase tree

```bash
tmux-livepicker/
  PRD.md
  plugin.tmux                 # COMPLETE. Unchanged.
  plan/001_fd5d622d3939/{architecture/*.md, tasks.json, prd_snapshot.md, prd_index.txt}
  plan/001_fd5d622d3939/P1M5T1S1/{PRP.md, research/restore_unlink_select_findings.md}   # HOST FILE creator (parallel)
  plan/001_fd5d622d3939/P1M5T2S1/{PRP.md, research/restore_keep_cancel_findings.md}      # THIS
  scripts/
    options.sh   # COMPLETE. Unchanged. (T2 does not read options.)
    utils.sh     # COMPLETE. Unchanged.
    state.sh     # COMPLETE — ORIG_SESSION / get_state (INPUT deps). Unchanged.
    renderer.sh  # COMPLETE. Unchanged.
    preview.sh   # COMPLETE (P1.M3). Unchanged.
    livepicker.sh   # COMPLETE (P1.M4). Unchanged.
    restore.sh   # CREATED by P1.M5.T1.S1 (parallel; assumed present with STEP 1+2 + T2/T3/T4 seams).
                 # THIS task (T2.S1) EDITS it: extend `local` line + replace the T2 seam with STEP 3.
  .gitignore
  # NOTE: NO test harness (P1.M7); NO input-handler.sh yet (P1.M6). Validate via the throwaway
  #       socket-shim mock (MUST keep an attached client + a DEDUPING recorder — FINDINGS A/B).
  # The real tmux-session-history engine lives at ~/.config/tmux/plugins/tmux-session-history/
  # (READ for ground-truth; NOT modified — it is a sibling plugin).
```

### Desired Codebase tree with files to be added and responsibility of file

```bash
tmux-livepicker/
  scripts/
    options.sh   # unchanged.
    utils.sh     # unchanged.
    state.sh     # unchanged.
    renderer.sh  # unchanged.
    preview.sh   # unchanged.
    livepicker.sh   # unchanged.
    restore.sh   # EDITED (this task). ONLY two changes inside restore_main():
                  #   (1) `local linked_id orig_window current_session orig_session mode`
                  #   (2) T2 seam comment block REPLACED by STEP 3:
                  #         mode="${1:-}"
                  #         orig_session="$(get_state "$ORIG_SESSION" "")"
                  #         if [ "$mode" = "cancel" ] && [ -n "$orig_session" ]; then
                  #             tmux switch-client -t "=$orig_session" 2>/dev/null || true
                  #         fi
                  #       (keep: no else — doing nothing is the contract.)
                  # After T2.S1: cancel switches the client back to ORIG_SESSION (exact-match,
                  #   deduped to 0 history entries by the engine); keep is a no-op.
                  # STEP 1/STEP 2/T3 seam/T4 seam/driver: UNCHANGED.
```

### Known Gotchas of our codebase & Library Quirks

```bash
# CRITICAL (research FINDING A): switch-client -t "=S" to the session the client is
#   ALREADY in DOES fire client-session-changed (naive counter 1->2). The cancel path
#   switches back to ORIG_SESSION where the client still is (browse never switched it —
#   Invariant A). So the hook FIRES. The pollution invariant (cancel->0) holds ONLY
#   because the real engine's do_hook short-circuits on [ "$to" = "$CURRENT" ] && return.
#   Do NOT assume the hook is silent — it is not. (This is the #1 misconception to avoid.)

# CRITICAL (research FINDING B / LOAD-BEARING for the MOCK): the work-item MOCKING
#   "fake history recorder on client-session-changed" CANNOT be a naive event counter.
#   A naive counter records 1 for the cancel switch (FALSE-FAIL). The recorder MUST
#   dedup: record $1 (#{session_name}) ONLY when it differs from the last-recorded
#   session. Mirror the engine's same-session short-circuit. Wire it EXACTLY like the
#   real plugin: `set-hook -g client-session-changed "run-shell '$REC \"#{session_name}\"'"`
#   (session_history.tmux:22).

# CRITICAL (research FINDING C): the `=` prefix is EXACT-MATCH (PRD §13). Use
#   "=$orig_session", never the bare name. A bare name would match a prefix-colliding
#   session (e.g. `log` vs `logfile`). switch-client returns rc=1 if the session
#   vanished (session killed during browse) -> ALWAYS append `2>/dev/null || true`
#   (house style; a transient failure must not abort a half-restored teardown).
#     tmux switch-client -t "=$orig_session" 2>/dev/null || true    # ✓
#     tmux switch-client -t "$orig_session"                         # ✗ no exact-match
#     tmux switch-client -t "=$orig_session"                        # ✗ missing || true

# CRITICAL (research FINDING E / T1.S1 FINDING 4): read ORIG_SESSION via
#   `get_state "$ORIG_SESSION" ""`, NOT via `tmux display-message -p '#{session_name}'`.
#   display-message is NON-DETERMINISTIC without an attached client (returned an
#   arbitrary session on the isolated socket). get_state reads the saved option —
#   deterministic and client-independent, and equals the attached display-message
#   value in production.

# GOTCHA (research FINDING F): `set -u` is in effect. T1.S1's restore_main does NOT
#   read "$1" yet. T2 reads it as `mode="${1:-}"` — the `${1:-}` default prevents a
#   set -u crash if restore.sh is ever invoked bare (defensive; input-handler.sh
#   always passes keep|cancel). Add `orig_session` + `mode` to the `local` line.

# GOTCHA (research FINDING D): keep is a TRUE no-op. Do NOT add an else branch that
#   does anything. Confirm (P1.M6.T3.S1) already issued the ONE switch-client to the
#   chosen target; a second switch here would be a SECOND navigation (pollution).
#   "keep -> 1" in the work-item OUTPUT counts the confirm switch, not a restore switch.

# GOTCHA (research FINDING G): T2.S1 is a SURGICAL EDIT to an EXISTING file. It
#   REPLACES the T2 seam comment block (4 lines) and EXTENDS the `local` line. It
#   does NOT create a file, does NOT touch STEP 1/STEP 2/T3/T4/driver. Preserve the
#   one-tab indent of restore_main's body.

# STYLE (system_context §9): indent with TABS. Verify with `grep -Pn '^    ' scripts/restore.sh`
#   (expect empty). shfmt is NOT installed. `local` for ALL function locals.
#   `2>/dev/null || true` on every fail-possible tmux call (switch-client included).
```

## Implementation Blueprint

### Data models and structure

No new data model. T2.S1 adds two function-locals to `restore_main`:
- `mode` — `argv[1]`, read as `"${1:-}"` (defaulted for `set -u`); expected `"keep"` or `"cancel"`.
- `orig_session` — read from `@livepicker-orig-session` via `get_state "$ORIG_SESSION" ""`
  (the bare session name; the `=` exact-match prefix is prepended at the call site).

The **read set** is one argv slot + one state accessor (`get_state "$ORIG_SESSION"`).
The **write set** is at most one tmux mutation (`switch-client`, cancel only), guarded.
No new options, no new state keys, no new files.

### Implementation Tasks (ordered by dependencies)

```yaml
Task 1: EDIT scripts/restore.sh — extend the `local` line + replace the T2 seam with STEP 3
  - FILE: ./scripts/restore.sh  (EXISTING; created by P1.M5.T1.S1).
  - EDIT 1: change `local linked_id orig_window current_session`
            to     `local linked_id orig_window current_session orig_session mode`
            (adds the two T2 locals; preserves T1.S1's three).
  - EDIT 2: REPLACE the T2 seam comment block
            (the 4 lines: "# --- T2 (P1.M5.T2.S1): keep/cancel client branch (insert here) ---"
             through "Reads "$1" and get_state "$ORIG_SESSION" "".")
            with the STEP 3 block from "Implementation Patterns & Key Details" below
            (read mode + orig_session; the guarded cancel switch-client; keep no-op).
  - DO NOT touch: STEP 1 (unlink block), STEP 2 (select-window block), the T3 seam,
            the T4 seam, the header doc, the source trio, the driver. (The header's
            seam-map line "3. keep: do not switch. cancel: switch-client -t ... [T2 seam]"
            may optionally be updated to "[T2]" — NOT required.)
  - PRESERVE: one-tab indent of restore_main's body; the file-level
            `# shellcheck disable=SC1091,SC2153`; `set -u`; NO `set -e`.

Task 2: VERIFY house style + no off-limits work
  - RUN: bash -n scripts/restore.sh            (expect exit 0, no output)
  - RUN: shellcheck scripts/restore.sh         (expect 0 findings; no new disable)
  - RUN: grep -Pn '^    ' scripts/restore.sh   (expect empty — tabs only)
  - RUN: grep -n 'set -e\|set -o pipefail' scripts/restore.sh  (expect empty)
  - EXPECT: exactly ONE `switch-client -t "=$orig_session"` (cancel only) with
    `2>/dev/null || true`; the keep path has NO switch-client; STEP 1's unlink +
    STEP 2's select-window are UNCHANGED (still present, still no -k / still by id);
    the T3/T4 seam comments are still present.

Task 3: VALIDATE (Level 1 syntax/lint + Level 2 socket-shim mock with a DEDUPING
        recorder: cancel->0 entries; simulated-confirm + keep->1 entry)
  - RUN the socket-shim mock (Validation Loop §2). Self-cleaning, isolated socket,
    attached client, deduping recorder (FINDINGS A/B). Runs the REAL restore.sh
    with argv 'cancel' and 'keep'.
```

### Implementation Patterns & Key Details

The complete, ready-to-paste STEP 3 block (the implementer replaces the T2 seam
comment block with this; indent is ONE tab to match restore_main's body):

```bash
	# --- STEP 3 (PRD §9 restore step 3): keep/cancel client branch ---
	# cancel: switch the client back to the ORIGINAL session (exact-match `=`).
	#   This is the ONLY switch-client in the cancel path. It DOES fire
	#   client-session-changed (FINDING A), but the history engine dedups a
	#   same-session event ([ "$to" = "$CURRENT" ] && return in do_hook) -> zero
	#   net history entries. The client is back where it started.
	# keep: do NOT switch. Confirm (P1.M6.T3.S1) already issued the ONE
	#   switch-client to the chosen target; a second switch here would pollute
	#   history. "keep -> 1" counts the confirm switch, not a restore switch.
	#
	# ${1:-} defaults the arg for `set -u` safety (input-handler always passes
	# keep|cancel). ORIG_SESSION via get_state (client-independent; display-message
	# is non-deterministic detached — FINDING E / T1.S1 FINDING 4). The `=` prefix
	# is exact-match (PRD §13); `2>/dev/null || true` because the session may have
	# vanished (FINDING C).
	mode="${1:-}"
	orig_session="$(get_state "$ORIG_SESSION" "")"
	if [ "$mode" = "cancel" ] && [ -n "$orig_session" ]; then
		tmux switch-client -t "=$orig_session" 2>/dev/null || true
	fi
	# keep: intentionally no else — doing nothing is the contract (FINDING D).
```

NOTE for the implementer:
- This block is the **only** new logic. It goes where the 4-line T2 seam comment
  currently sits (between STEP 2's `select-window` line and the T3 seam comment).
- The `local` line edit is the **only** other change (add `orig_session mode`).
- Use the exact-match `"=$orig_session"` form. Do NOT use the bare `"$orig_session"`.
  Do NOT drop the `2>/dev/null || true`.
- Do NOT add an `else` branch for keep. An empty else (or no else) is the contract.
- Do NOT read `display-message` for the session — use `get_state "$ORIG_SESSION" ""`.
- Do NOT touch STEP 1, STEP 2, the T3 seam, the T4 seam, the header, the source trio,
  or the driver. Do NOT create any file. Do NOT add `set -e`.
- Optional (not required): in the header doc-comment, change `[T2 seam]` to `[T2]`
  on the "3. keep: do not switch. cancel: ..." line to mark T2 done.

### Integration Points

```yaml
HOST FILE (what this task edits):
  - scripts/restore.sh: restore_main() — `local` line extended; T2 seam REPLACED by STEP 3.

CALLERS / CONSUMERS (this file's INPUT — provided by FUTURE subtasks):
  - P1.M6.T3.S1 (input-handler.sh confirm — PLANNED): issues the ONE switch-client to the
        chosen target, then invokes "$CURRENT_DIR/restore.sh" keep. T2's keep branch
        relies on confirm having already switched.
  - P1.M6.T4.S1 (input-handler.sh cancel — PLANNED): invokes "$CURRENT_DIR/restore.sh"
        cancel. T2's cancel branch does the switch back to ORIG_SESSION.

STATE READS (this task — T2.S1 step 3):
  - @livepicker-orig-session (via get_state "$ORIG_SESSION" ""; written by activate STEP 2)
  - argv[1] (mode = keep|cancel; passed by input-handler.sh confirm/cancel)

STATE WRITES (this task): NONE. (T2 clears no @livepicker-* key; T4's clear_all_state
  owns that.)

TMUX MUTATIONS (this task — PRD §13 primitive):
  - switch-client -t "=$orig_session"   (cancel ONLY; exact-match; || true — fires
        client-session-changed, which the engine DEDUPS for a same-session event -> 0
        history entries; Invariant A + engine do_hook short-circuit)
  - keep: NONE.
  - NO re-touch of unlink-window/select-window (T1.S1); NO status/status-format/
        key-table/renumber/set-hook (T3); NO select-layout/clear_all_state/unbind-key (T4).

DATABASE / MIGRATIONS / ROUTES / CONFIG: none.
```

## Validation Loop

### Level 1: Syntax & Style (Immediate Feedback)

```bash
# Run after editing the file — fix before proceeding.
bash -n scripts/restore.sh                     # syntax; expect no output, exit 0
shellcheck scripts/restore.sh                  # lint; expect 0 findings (the file-level
                                               # disable=SC1091,SC2153 from T1.S1 still covers all)
# Tabs-not-spaces sanity (shfmt NOT installed):
grep -Pn '^    ' scripts/restore.sh && echo "FAIL: 4-space indent found, use tabs" || echo "OK: tabs only"
# Confirm house style (set -u only, NO -e / NO pipefail):
grep -n 'set -e\|set -o pipefail' scripts/restore.sh && echo "FAIL: set -e/pipefail present" || echo "OK: set -u only"
# Confirm the `local` line was extended:
grep -n 'local linked_id orig_window current_session orig_session mode' scripts/restore.sh   # expect 1
# Confirm T2's exact primitive is present (cancel-only, exact-match, || true):
grep -n 'switch-client -t "=\$orig_session" 2>/dev/null || true' scripts/restore.sh            # expect 1
grep -n 'mode="\${1:-}"' scripts/restore.sh                                                    # expect 1
grep -n 'get_state "\$ORIG_SESSION" ""' scripts/restore.sh                                     # expect >=1
# Confirm the T2 seam comment block is GONE (replaced by STEP 3):
grep -n 'T2 (P1.M5.T2.S1): keep/cancel client branch (insert here)' scripts/restore.sh \
  && echo "FAIL: T2 seam comment still present (should be replaced by STEP 3)" || echo "OK: T2 seam replaced"
# Confirm the T3/T4 seam comments are STILL present (unchanged):
grep -n 'T3 (P1.M5.T3.S1): restore status' scripts/restore.sh                 # expect 1
grep -n 'T4 (P1.M5.T4.S1): select-layout ORIG_LAYOUT' scripts/restore.sh       # expect 1
# Confirm T1.S1's STEP 1/STEP 2 are UNCHANGED (still present):
grep -n 'unlink-window -t "\$current_session:\$linked_id" 2>/dev/null || true' scripts/restore.sh   # expect 1
grep -n 'select-window -t "\$orig_window" 2>/dev/null || true' scripts/restore.sh                    # expect 1
# Confirm NO off-limits work leaked in (no second switch, no T3/T4 mutations):
grep -n 'switch-client' scripts/restore.sh | grep -v '=\$orig_session' \
  && echo "WARN: unexpected switch-client — verify it is not a second switch" || echo "OK: exactly one switch-client (cancel)"
grep -n 'set-option.*status\|status-format\[\|set-option -g key-table\|set-hook\|select-layout\|clear_all_state\|unbind-key\|link-window\|capture-pane' scripts/restore.sh \
  | grep -v 'T3\|T4\|#' \
  && echo "FAIL: T2 must not do T3/T4/preview work" || echo "OK: only STEP 3 implemented"
# Run from the repo root.
```

### Level 2: Socket-Shim Mock Validation — cancel→0 / confirm+keep→1 history entries, via a DEDUPING recorder, zero live-server impact

Reuses the PATH-wrapper socket shim. Self-cleaning. Runs the REAL
`scripts/restore.sh` (with argv `cancel` and `keep`). **MUST keep an attached
client** (so switch-client has a target) AND use a **DEDUPING recorder** (a naive
counter FALSE-FAILS cancel — FINDINGS A/B). The recorder mirrors the real engine's
`do_hook` same-session short-circuit and is wired EXACTLY like the real plugin's
hook (`run-shell '$REC "#{session_name}"'`).

Because `input-handler.sh confirm` (P1.M6.T3.S1) is not built yet, the mock
**simulates** confirm's single switch (`switch-client -t "=chosen"`) before running
`restore.sh keep`, to prove keep adds 0 additional entries.

```bash
#!/usr/bin/env bash
# Throwaway socket-shim validation for scripts/restore.sh T2.S1 (do NOT commit).
set -u
REPO_ROOT="$(cd "$(dirname "$0")" && pwd)"
[ -f "$REPO_ROOT/scripts/restore.sh" ] || { echo "restore.sh missing"; exit 1; }
for l in options utils state; do
	[ -f "$REPO_ROOT/scripts/$l.sh" ] || { echo "INPUT dep $l.sh missing"; exit 1; }
done

SOCK="lp-t2-mock-$$"
SHIM_DIR="$(mktemp -d)"
cat > "$SHIM_DIR/tmux" <<EOF
#!/usr/bin/env bash
exec /usr/bin/tmux -L "$SOCK" "\$@"
EOF
chmod +x "$SHIM_DIR/tmux"
export PATH="$SHIM_DIR:$PATH"

cleanup() {
	PATH="/usr/bin:/bin:$PATH" tmux -L "$SOCK" kill-server 2>/dev/null || true
	rm -rf "$SHIM_DIR" /tmp/lp-t2-mock-$$.*
}
trap cleanup EXIT

# --- deduping recorder (mirrors the real engine's do_hook same-session short-circuit) ---
REC=/tmp/lp-t2-mock-$$.rec.sh; HIST=/tmp/lp-t2-mock-$$.hist; LAST=/tmp/lp-t2-mock-$$.last; NAIVE=/tmp/lp-t2-mock-$$.naive
cat > "$REC" <<EOF
#!/usr/bin/env bash
to="\$1"; last="\$(cat "$LAST" 2>/dev/null)"
printf 'x' >> "$NAIVE"                       # naive fire counter (proves the hook fires)
[ "\$to" = "\$last" ] && exit 0              # mimic engine: same-session -> no record
printf '%s\n' "\$to" >> "$HIST"; printf '%s' "\$to" > "$LAST"
EOF
chmod +x "$REC"
hcount() { wc -l < "$HIST" 2>/dev/null || echo 0; }
ncount() { wc -c < "$NAIVE" 2>/dev/null || echo 0; }
reset_rec() { : > "$HIST"; echo -n "ORIG" > "$LAST"; : > "$NAIVE"; }   # engine init: CURRENT=ORIG

pass=0; fail=0
assert() { if [ "$2" = "$3" ]; then pass=$((pass+1)); printf 'ok   %s\n' "$1"; else fail=$((fail+1)); printf 'FAIL %s: got=[%s] want=[%s]\n' "$1" "$2" "$3"; fi; }

attach() { TMUX="" script -qec "tmux -L $SOCK attach -t ORIG" /dev/null >/dev/null 2>&1 & AP=$!; sleep 0.5; }
detach() { kill "$AP" 2>/dev/null; wait "$AP" 2>/dev/null; }
seed_state() {
	# Seed the saved-state contract restore_main reads (T1.S1 steps 1-2 + T2 step 3).
	tmux set-option -g "@livepicker-orig-session" "ORIG"
	tmux set-option -g "@livepicker-orig-window" "$(tmux list-windows -t '=ORIG' -F '#{window_id}' -f '#{window_active}')"
	tmux set-option -gu "@livepicker-linked-id"   # empty -> T1.S1 skips unlink (no foreign link in this mock)
}

# ---------- setup ----------
tmux new-session -d -s ORIG -x 120 -y 40
tmux new-window -t ORIG                         # a 2nd ORIG window (so select has somewhere to be)
tmux new-session -d -s chosen -x 120 -y 40
# Wire the deduping recorder EXACTLY like the real plugin (session_history.tmux:22):
tmux set-hook -g client-session-changed "run-shell '$REC \"#{session_name}\"'"

# ---------- (A) CANCEL path: browse -> restore.sh cancel -> 0 entries ----------
attach; reset_rec; seed_state
CHOSEN_WIN="$(tmux list-windows -t '=chosen' -F '#{window_id}' -f '#{window_active}')"
tmux link-window -a -s "$CHOSEN_WIN" -t 'ORIG:'   # browse: link (NO switch-client)
tmux select-window -t "$CHOSEN_WIN"                # browse: select (NO switch-client)
sleep 0.3
assert "(A1) browse fires NEITHER client-session-changed (naive)" "$(ncount)" "0"
assert "(A1) browse adds 0 history entries (smart)" "$(hcount)" "0"
# Run the REAL restore.sh cancel (T1.S1 steps 1-2 run first, then T2 STEP 3):
bash "$REPO_ROOT/scripts/restore.sh" cancel; crc=$?
assert "(A2) restore.sh cancel exit 0" "$crc" "0"
sleep 0.3
assert "(A3) cancel switch fired client-session-changed (naive grew)" "$([ "$(ncount)" -ge 1 ] && echo grew || echo no)" "grew"
assert "(A3) cancel added 0 history entries (smart — engine deduped same-session)" "$(hcount)" "0"
assert "(A4) client back on ORIG after cancel" "$(tmux display-message -p '#{session_name}')" "ORIG"
detach

# ---------- (B) CONFIRM+KEEP path: browse -> simulated confirm switch -> restore.sh keep -> 1 entry ----------
attach; reset_rec; seed_state
tmux select-window -t "$CHOSEN_WIN" 2>/dev/null    # browse
sleep 0.2
assert "(B1) browse adds 0 entries (smart)" "$(hcount)" "0"
# SIMULATE confirm (P1.M6.T3.S1, not built yet): the ONE switch-client to the chosen target.
tmux switch-client -t "=chosen"; sleep 0.3
assert "(B2) simulated confirm switch added exactly 1 entry (smart)" "$(hcount)" "1"
assert "(B2) client now on chosen" "$(tmux display-message -p '#{session_name}')" "chosen"
# Run the REAL restore.sh keep (T2 STEP 3 must be a NO-OP — no second switch):
bash "$REPO_ROOT/scripts/restore.sh" keep; krc=$?
assert "(B3) restore.sh keep exit 0" "$krc" "0"
sleep 0.3
assert "(B4) keep added 0 additional entries (still 1, not 2)" "$(hcount)" "1"
detach

# ---------- (C) defensive: cancel with empty ORIG_SESSION -> no switch, no crash ----------
attach; reset_rec
tmux set-option -g "@livepicker-orig-session" ""   # empty (shouldn't happen, but guard)
tmux set-option -g "@livepicker-orig-window" "$(tmux list-windows -t '=ORIG' -F '#{window_id}' -f '#{window_active}')"
tmux set-option -gu "@livepicker-linked-id"
bash "$REPO_ROOT/scripts/restore.sh" cancel; crc2=$?
assert "(C1) restore.sh cancel exit 0 with empty ORIG_SESSION" "$crc2" "0"
assert "(C2) no entries recorded (guarded, no switch)" "$(hcount)" "0"
detach

printf '\n==== PASS=%d FAIL=%d ====\n' "$pass" "$fail"
[ "$fail" = "0" ]
# Expected: PASS=14 FAIL=0. Key proofs:
#  (A3) cancel switch FIRES client-session-changed (naive grew) BUT smart=0 (engine dedup).
#       This is the crux: it proves cancel->0 holds via dedup, NOT a silent hook.
#  (B4) keep adds 0 additional entries (confirm's 1 switch is the only one).
#  (C)  empty ORIG_SESSION is guarded (no crash, no switch).
```

### Level 3: Integration Testing (System Validation)

```bash
# Live spot-check on an ISOLATED socket WITH an attached client — confirms the cancel
# switch lands the client on ORIG_SESSION and the keep path issues no switch. Self-cleaning.
# (P1.M5.T3/T4 are not built yet, so this checks ONLY step 3; status/key-table/state are
#  NOT restored here. The real pollution diff belongs in P1.M7.T5's test_pollution.sh.)
export LP_SOCK="lp-t2-live-$$"
REPO_ROOT="$(pwd)"
SHIM_DIR="$(mktemp -d)"
cat > "$SHIM_DIR/tmux" <<EOF
#!/usr/bin/env bash
exec /usr/bin/tmux -L "$LP_SOCK" "\$@"
EOF
chmod +x "$SHIM_DIR/tmux"
trap 'PATH=/usr/bin:/bin:$PATH tmux -L "$LP_SOCK" kill-server 2>/dev/null; rm -rf "$SHIM_DIR"' EXIT
T() { PATH="$SHIM_DIR:$PATH" tmux "$@"; }
T new-session -d -s ORIG -x 120 -y 40
T new-window -t ORIG
T new-session -d -s chosen -x 120 -y 40
T set-option -g "@livepicker-orig-session" "ORIG"
T set-option -g "@livepicker-orig-window" "$(T list-windows -t '=ORIG' -F '#{window_id}' -f '#{window_active}')"
T set-option -gu "@livepicker-linked-id"
echo "client session BEFORE: [$(T display-message -p '#{session_name}' 2>/dev/null)] (expect ORIG)"
TMUX="" script -qec "tmux -L $LP_SOCK attach -t ORIG" /dev/null >/dev/null 2>&1 &
AP=$!; sleep 0.5
echo "--- cancel ---"
PATH="$SHIM_DIR:$PATH" bash "$REPO_ROOT/scripts/restore.sh" cancel; echo "restore cancel rc=$? (expect 0)"
echo "client session AFTER cancel: [$(T display-message -p '#{session_name}')] (expect ORIG)"
echo "--- keep (after a simulated confirm switch to chosen) ---"
T switch-client -t "=chosen"; echo "simulated confirm -> client on: [$(T display-message -p '#{session_name}')] (expect chosen)"
PATH="$SHIM_DIR:$PATH" bash "$REPO_ROOT/scripts/restore.sh" keep; echo "restore keep rc=$? (expect 0)"
echo "client session AFTER keep: [$(T display-message -p '#{session_name}')] (expect STILL chosen — keep did not switch)"
kill "$AP" 2>/dev/null; wait "$AP" 2>/dev/null
# Expected: cancel lands on ORIG; keep leaves the client on chosen (no switch).
```

### Level 4: Creative & Domain-Specific Validation

```bash
# Pollution invariant spot-check (PRD §15.18) for the restore keep/cancel branch,
# against the REAL tmux-session-history engine on the live server. Run ONLY if you are
# comfortable touching the live server's @session-history-* options; otherwise the
# isolated-socket deduping-recorder mock (§2) is the authoritative proof (it mirrors
# the engine's do_hook exactly). This is a STRUCTURAL assertion (safe, no live switch):
REPO_ROOT="$(pwd)"
# 1. restore.sh contains exactly ONE switch-client (cancel-only, exact-match, || true):
n_switch="$(grep -c 'switch-client' "$REPO_ROOT/scripts/restore.sh")"
[ "$n_switch" = "1" ] && echo "OK: exactly one switch-client in restore.sh" || echo "FAIL: found $n_switch"
# 2. the keep path has no switch-client (the cancel is inside `if mode==cancel`):
grep -q 'if \[ "\$mode" = "cancel" \]' "$REPO_ROOT/scripts/restore.sh" \
  && echo "OK: switch-client is cancel-guarded -> keep is a no-op" \
  || echo "FAIL: switch-client not cancel-guarded"
# 3. exact-match prefix present:
grep -q 'switch-client -t "=\$orig_session"' "$REPO_ROOT/scripts/restore.sh" \
  && echo "OK: exact-match = prefix used" || echo "FAIL: missing = exact-match prefix"
# Expected: all OK. The full live activate->browse->restore pollution diff (cancel->0,
# confirm->1) is exercised by P1.M7.T5.S1 test_pollution.sh against the real engine.
```

## Final Validation Checklist

### Technical Validation

- [ ] `bash -n scripts/restore.sh` exits 0 with no output.
- [ ] `shellcheck scripts/restore.sh` reports 0 findings (no new disable; T2 adds no
      word-split, no new shellcheck concern).
- [ ] No 4-space indents (`grep -Pn '^    '` is empty); tabs only.
- [ ] `scripts/restore.sh` is still executable (T1.S1 set +x; T2's edit preserves it).

### Feature Validation

- [ ] The `local` line includes `orig_session` and `mode`.
- [ ] The T2 seam comment block is REPLACED by STEP 3 (the comment is gone; the branch
      is present).
- [ ] cancel: `switch-client -t "=$orig_session"` runs ONLY when `mode == "cancel"` AND
      `orig_session` non-empty; exact-match `=`; `2>/dev/null || true`.
- [ ] keep: NO switch-client, NO mutation (true no-op).
- [ ] Mock (§2): (A3) cancel switch fires client-session-changed (naive grew) BUT smart=0
      (engine deduped); (B4) keep adds 0 additional entries (still 1); (C) empty
      ORIG_SESSION guarded.

### Code Quality Validation

- [ ] Follows existing codebase patterns (mirrors T1.S1's `2>/dev/null || true` idiom;
      `get_state "$ORIG_*" ""` for state reads; `${1:-}` for argv under `set -u`;
      one-tab indent).
- [ ] Surgical edit (only the `local` line + the T2 seam; STEP 1/STEP 2/T3/T4/driver
      untouched).
- [ ] Anti-patterns avoided (no bare session name — always `=`; no missing `|| true`;
      no `display-message` for the session; no keep-else doing work; no `set -e`;
      no re-touch of T1/T3/T4 seams).
- [ ] Dependencies properly managed (reads only argv[1] + ORIG_SESSION; mutates at most
      switch-client, cancel only).

### Documentation & Deployment

- [ ] Code is self-documenting (the STEP 3 block cites PRD §9 step 3 / §13; explains the
      dedup mechanism [FINDING A], why keep is a no-op [FINDING D], the exact-match
      prefix, and the `|| true`).
- [ ] Logs are informative but not verbose (T2 emits nothing on success; the switch is
      silent).
- [ ] No new environment variables (T2 uses only argv[1] and `@livepicker-orig-session`
      [activate STEP 2 save]).

---

## Anti-Patterns to Avoid

- ❌ Don't use a **naive** recorder in the mock — switch-client to the SAME session
  DOES fire `client-session-changed` (FINDING A: naive counter 1→2). A naive recorder
  FALSE-FAILS cancel (records 1 instead of 0). The recorder MUST dedup (mirror the
  engine's `[ "$to" = "$CURRENT" ] && return`). The invariant holds via the engine's
  dedup, NOT a silent hook.
- ❌ Don't drop the `=` exact-match prefix — `switch-client -t "$orig_session"` (bare)
  matches a prefix-colliding session (`log` vs `logfile`). Always `switch-client -t
  "=$orig_session"` (PRD §13; FINDING C).
- ❌ Don't drop `2>/dev/null || true` — `switch-client` returns rc=1 if `ORIG_SESSION`
  vanished (session killed during browse). Under a future `set -e` that would abort a
  half-restored teardown. House style: `|| true` on every fail-possible tmux call.
- ❌ Don't read the session via `display-message` — it's non-deterministic without an
  attached client (T1.S1 FINDING 4; returned an arbitrary session on the isolated
  socket). Use `get_state "$ORIG_SESSION" ""` (deterministic, client-independent).
- ❌ Don't add an `else` (keep) branch that does anything — keep is a TRUE no-op.
  Confirm (P1.M6.T3.S1) already issued the ONE switch; a second switch would pollute
  history ("keep → 1" counts the confirm switch, not a restore switch — FINDING D).
- ❌ Don't forget the `${1:-}` default — `restore.sh` runs under `set -u`; reading bare
  `$1` crashes if invoked without an arg. `${1:-}` is the safe form (input-handler.sh
  always passes keep|cancel, but defensive coding is house style).
- ❌ Don't touch STEP 1 / STEP 2 / the T3 seam / the T4 seam / the driver — T2.S1 is a
  surgical edit of the `local` line + the T2 seam only. Re-touching T1.S1's work or
  pre-empting T3/T4 muddies the seam boundaries and risks merge conflicts.
- ❌ Don't assume the cancel switch is unnecessary — the contract is symmetric and
  defensive: it GUARANTEES the client is on `ORIG_SESSION` regardless of future
  preview/activate changes, and it is the explicit counterpart of the keep switch.
  The switch is cheap (rc=0, hook deduped to 0 entries) and makes "everything is
  exactly as it was" provable.
- ❌ Don't skip validation because "it should work" — run the socket-shim mock (§2);
  assertion (A3) (naive grew BUT smart=0) is what proves the dedup mechanism is real,
  and (B4) (keep stays at 1) is what proves keep is a true no-op.
