# PRP — P1.M5.T1.S1: restore.sh — unlink preview + select-window to ORIG_WINDOW

---

## Goal

**Feature Goal**: **CREATE** `scripts/restore.sh` — the teardown orchestrator's
**first two steps** (PRD §9 restore steps 1–2). This is the FIRST subtask of the
P1.M5 restore module, so this task **creates the file** and its full skeleton
(shebang + `shellcheck` disables + header doc + lib-trio `source` +
`restore_main()` + driver), then implements **only** the unlink + select-window
logic, leaving in-place **seam comments** for the three sibling subtasks that
will EXTEND this file later (P1.M5.T2.S1 keep/cancel switch, P1.M5.T3.S1
status/key-table/renumber/hook restore, P1.M5.T4.S1 layout restore +
`clear_all_state` + unbind). The work-item CONTRACT (steps 1–2):

1. **Unlink the preview window** — read `@livepicker-linked-id`; if **non-empty**
   (a non-self session was being previewed), `tmux unlink-window -t
   "$CURRENT_SESSION:$LINKED_ID"` (**NO `-k`**; ignore failure — the singly-linked
   edge). If **empty** (the self-session was highlighted — preview.sh cleared it),
   there is nothing to unlink; skip. `CURRENT_SESSION` is derived via
   `tmux display-message -p '#{session_name}'` (the contract's stated form;
   client-attached at restore time — see FINDING 4).
2. **Select the original window** — `tmux select-window -t "$ORIG_WINDOW"` where
   `ORIG_WINDOW` is the **`@N` window ID** saved by activate STEP 2 (NOT an
   index — `renumber-windows on` makes indices unstable).

After steps 1–2: the linked preview window is gone from the driver session (the
candidate session S keeps its window — FINDING 1), and the original window is
active again. The picker's client has NOT switched sessions yet (that is step 3,
P1.M5.T2.S1 — `keep` stays, `cancel` switches back to `ORIG_SESSION`).

**Deliverable**: A **new file** `scripts/restore.sh` (executable; mirrors the
structure of `scripts/preview.sh` — the closest sibling). It contains the full
file skeleton + the `restore_main()` function with steps 1–2 implemented and
three seam comments (`# --- T2 ... ---`, `# --- T3 ... ---`, `# --- T4 ... ---`)
marking where the sibling subtasks insert. No other file is touched.

**Success Definition**:
- `bash -n scripts/restore.sh` passes; `shellcheck scripts/restore.sh` is clean
  (0 findings; the file-level `# shellcheck disable=SC1091,SC2153` mirrors
  preview.sh — SC1091 covers the `source` lines, SC2153 covers the
  ORIG_*/STATE_* readonly constants). Tabs only; `set -u`, NO `set -e`.
- **Unlink is conditional + safe:** when `@livepicker-linked-id` is non-empty,
  `unlink-window -t "$CURRENT_SESSION:$LINKED_ID"` runs WITHOUT `-k` and its
  non-zero rc is ignored (`2>/dev/null || true`). When empty, NO unlink call is
  made (the self-session case — nothing to unlink).
- **Source session unharmed:** after restore, the unlinked window id NO LONGER
  appears in the driver session's `list-windows` BUT STILL appears in its origin
  (candidate) session's `list-windows` (FINDING 1/5 — the core pollution
  invariant for the preview window).
- **Original window re-selected:** after restore, the driver session's active
  window id == `@livepicker-orig-window` (the `@N` id activate saved).
- **Mock end-to-end (work-item §5):** under the socket shim with an attached
  client: link a window via `preview.sh`, run `restore.sh`, assert (a) the
  window id is gone from the driver session, (b) it is still present in the
  origin session, (c) the active window is `ORIG_WINDOW`. Self-cleaning.
- **No off-limits work:** steps 1–2 ONLY. NO keep/cancel `switch-client` (T2),
  NO status / status-format / key-table / renumber / hook restore (T3), NO
  `select-layout` / `clear_all_state` / `unbind-key -T livepicker` (T4). Those
  are marked as seam comments only.

## User Persona (if applicable)

**Target User**: None directly (internal teardown step — the first half of
restore). Transitively: the end user who pressed cancel or confirm (PRD §3
stories 3–4: "I press Escape ... everything is exactly as it was"; "I press
Enter ... the client switches to it"). T1.S1 is what makes "everything is
exactly as it was" start to become TRUE: it removes the foreign preview window
the user was just looking at and puts their original window back in focus —
BEFORE the (T2) session switch and (T3/T4) full state restore.

**Use Case**: The user was browsing sessions (a foreign session's window was
linked into the driver and live-previewed). They pressed confirm or cancel.
`input-handler.sh` (P1.M6) invokes `restore.sh <keep|cancel>`. **T1.S1 (this
task)** runs FIRST inside `restore_main`: it unlinks the preview window from the
driver (S keeps it) and re-selects the user's original window. After T1.S1, the
visible preview is gone and the user's own window is back; T2 then either
switches the client (cancel → `ORIG_SESSION`) or stays (keep), and T3/T4 restore
the rest.

**User Journey** (T1.S1 scope — the preview is torn down):
1. …activate (P1.M4) saved state, grew the status, installed the key-table,
   previewed sessions (linking foreign windows into the driver); the user
   browsed; `@livepicker-linked-id` holds the currently-previewed window id (or
   is empty if the self-session is highlighted).
2. User presses confirm/cancel → `input-handler.sh` → `restore.sh`.
3. **T1.S1 (this task):** (a) read `@livepicker-linked-id` + `@livepicker-orig-window`;
   (b) if linked-id non-empty, derive `current_session` and `unlink-window -t
   "$current_session:$linked_id"` (no `-k`, ignore failure); (c) `select-window
   -t "$orig_window"`.
4. T2/T3/T4 (sibling subtasks, seam-marked) finish the teardown: switch-or-stay,
   restore status/keys/hook, restore layout, clear state, unbind the table.

**Pain Points Addressed**:
- (a) **Foreign window left behind.** Without the unlink, the linked preview
  window would REMAIN in the driver session after restore — a permanent,
  visible, duplicate of some other session's window polluting the user's
  session (a window-list pollution, distinct from but adjacent to the
  session-history pollution of Invariant A). T1.S1 removes exactly that one
  link.
- (b) **Wrong window in focus.** Without the `select-window -t "$ORIG_WINDOW"`,
  the driver's active window would be whichever window was left active after
  unlink (often the linked preview's neighbor, or the last-browsed state) — not
  the window the user was in when they activated the picker. T1.S1 restores the
  exact original window (by id, not the now-unstable index).
- (c) **Destroyed source window.** A naive `unlink-window -k` would KILL the
  window object in ALL sessions (the candidate session S loses its window
  permanently — `tmux_primitives.md §1`). T1.S1 NEVER passes `-k` (FINDING 2 /
  preview.sh FINDING 11).

## Why

- **PRD §9 "State saved and restored"** is the controlling spec. Its restore
  list, in order: "1. Unlink the preview window from the current session if
  `@livepicker-linked-id` is set. 2. `select-window -t "$ORIG_WINDOW"`." T1.S1
  owns BOTH (the file's first two steps). Steps 3–6 are T2/T3/T4.
- **PRD §13 "tmux primitives reference":** "`unlink-window -t <session>:<id>` to
  remove the linked preview window" and "`select-window -t <id>` to show the
  linked window." Both are the exact primitives T1.S1 uses (verified — FINDING
  1/3).
- **PRD §16 "Window addressing":** "Use window ids, not indices.
  `renumber-windows on` makes indices unstable." T1.S1 targets `$ORIG_WINDOW`
  (the saved `@N` id) and `$LINKED_ID` (also an `@N` id), never an index.
- **Boundary respect.** T1.S1 touches ONLY: (1) two state reads
  (`@livepicker-linked-id`, `@livepicker-orig-window`); (2) one client-context
  read (`display-message -p '#{session_name}'`); (3) at most two tmux mutations
  (`unlink-window`, `select-window`), each guarded. It does NOT: switch the
  client (T2), mutate status / status-format / key-table / renumber / the hook
  (T3), restore the layout or clear state or unbind keys (T4), or call
  `link-window`/`capture-pane` (preview.sh owns those).
- **Scope cohesion.** T1.S1 is the restore counterpart of preview.sh's link
  half: preview.sh LINKS a foreign window in + selects it; T1.S1 UNLINKS it +
  re-selects the original. The two share the `@livepicker-linked-id` contract
  (preview.sh writes it; T1.S1 reads + uses it as the unlink target). T1.S1
  CREATES the file the rest of P1.M5 will extend, so its skeleton + seam
  comments are the integration contract for T2/T3/T4.

## What

A new file `scripts/restore.sh` (executable) that:

1. Mirrors `scripts/preview.sh`'s structure: `#!/usr/bin/env bash` + file-level
   `# shellcheck disable=SC1091,SC2153` + a header doc-comment (purpose, PRD
   refs, load-bearing rules, dependencies, the seam map) + the resolved
   `$CURRENT_DIR` + `source` of the lib trio (`options.sh`, `utils.sh`,
   `state.sh`) + `restore_main()` + the driver (`restore_main "$@" || exit 1`
   / `exit 0`).
2. Defines `restore_main()` which:
   - Reads `linked_id` via `get_state "$STATE_LINKED_ID" ""` and `orig_window`
     via `get_state "$ORIG_WINDOW" ""`.
   - **STEP 1:** if `linked_id` is non-empty, derives `current_session` via
     `tmux display-message -p '#{session_name}'` (guarded `2>/dev/null || true`)
     and runs `tmux unlink-window -t "$current_session:$linked_id" 2>/dev/null
     || true` (NO `-k`). If `linked_id` is empty, skips the unlink entirely
     (self-session case).
   - **STEP 2:** `tmux select-window -t "$orig_window" 2>/dev/null || true`
     (only if `orig_window` is non-empty — defensive).
   - Ends with `return 0`.
   - Contains three in-place seam comments (T2/T3/T4) AFTER step 2, BEFORE the
     `return 0`, each describing what the sibling subtask inserts there.

### Success Criteria

- [ ] `scripts/restore.sh` EXISTS, is executable (`chmod +x`), and `bash -n` +
      `shellcheck` are clean (0 findings; file-level `disable=SC1091,SC2153`).
- [ ] The file mirrors preview.sh's skeleton (shebang, shellcheck disables,
      header doc, `$CURRENT_DIR`, source trio, `restore_main`, driver).
- [ ] `restore_main` reads `linked_id` (`get_state "$STATE_LINKED_ID" ""`) and
      `orig_window` (`get_state "$ORIG_WINDOW" ""`).
- [ ] STEP 1: unlink runs ONLY when `linked_id` is non-empty; uses
      `unlink-window -t "$current_session:$linked_id"` with **NO `-k`** and
      `2>/dev/null || true`; `current_session` from `display-message -p
      '#{session_name}'`.
- [ ] STEP 2: `select-window -t "$orig_window"` (the `@N` id; `2>/dev/null ||
      true`); guarded on `orig_window` non-empty.
- [ ] Three seam comments present (T2/T3/T4) between step 2 and `return 0`.
- [ ] Tabs only (`grep -Pn '^    '` empty); `set -u`, NO `set -e`.
- [ ] NO off-limits work: no `switch-client` (T2), no status/status-format/
      key-table/renumber/hook restore (T3), no `select-layout`/`clear_all_state`/
      `unbind-key` (T4), no `link-window`/`capture-pane` (preview.sh).
- [ ] Mock (work-item §5): link via preview.sh → run restore.sh → (a) window id
      gone from driver session, (b) still in origin session, (c) active window
      == ORIG_WINDOW. Self-cleaning, isolated socket, attached client.

## All Needed Context

### Context Completeness Check

_Pass_: A developer who has never seen this repo can implement T1.S1 from
(a) the verbatim file in "Implementation Patterns & Key Details" (complete,
ready to write to `scripts/restore.sh`), (b) the 8 live-verified findings in
`research/restore_unlink_select_findings.md` — most critically **FINDING 1**
(unlink no-`-k` removes one link, source keeps window — verified), **FINDING 2**
(singly-linked unlink fails rc=1 → MUST ignore, NEVER `-k`), **FINDING 3**
(select-window -t @id rc=0), **FINDING 4** (LOAD-BEARING: display-message is
non-deterministic detached → the mock MUST attach a client; ORIG_SESSION is the
client-independent equivalent), and **FINDING 5** (list-windows before/after is
the assertion handle), and (c) the socket-shim mock that links via the REAL
preview.sh, runs the REAL restore.sh, and asserts the three pollution/focus
properties against an isolated socket WITH an attached client. The INPUT
dependencies (`state.sh` STATE_LINKED_ID/ORIG_WINDOW/get_state, `preview.sh` for
the mock's link setup) are all COMPLETE/present. `scripts/preview.sh` is the
structural template (mirror its skeleton exactly).

### Documentation & References

```yaml
# MUST READ — INPUT dependency: state.sh (STATE_LINKED_ID / ORIG_WINDOW / ORIG_SESSION / get_state). COMPLETE.
- file: scripts/state.sh
  why: readonly STATE_LINKED_ID="@livepicker-linked-id" (the linked preview window id preview.sh
       wrote; empty when self-session is highlighted -> nothing to unlink), ORIG_WINDOW=
       "@livepicker-orig-window" (the @N id activate STEP 2 saved; the select target), ORIG_SESSION=
       "@livepicker-orig-session" (the driver session name; T2's switch target, NOT used by T1.S1's
       steps 1-2 but listed in the work-item INPUT), get_state (the STATE_* read accessor ->
       tmux show-option -gqv; ${2:-} default makes it safe under set -u). T1.S1 uses
       `get_state "$STATE_LINKED_ID" ""` and `get_state "$ORIG_WINDOW" ""`.
  critical: ORIG_WINDOW is a window ID (@N), NEVER an index (renumber-windows on). STATE_LINKED_ID
            empty means "self-session highlighted / no link" -> skip unlink (work-item point 1).

# MUST READ — the structural TEMPLATE (mirror this file's skeleton exactly).
- file: scripts/preview.sh
  why: preview.sh is the closest sibling: same shebang, same file-level
       `# shellcheck disable=SC1091,SC2153`, same header-doc style, same
       `$CURRENT_DIR` + source-trio + `<thing>_main()` + driver idiom. T1.S1's
       restore.sh mirrors it. preview.sh ALSO defines the unlink pattern T1.S1
       reuses: `tmux unlink-window -t "$current_session:$linked_id" 2>/dev/null || true`
       (NO -k) — see its self-session guard + its "Drop the previous preview"
       block. T1.S1's unlink is the SAME call, just at the top of restore.
  pattern: the file skeleton (lines 1-~25 of preview.sh) + the unlink idiom
           (preview.sh's `tmux unlink-window -t "$current_session:$linked_id" 2>/dev/null || true`).
  gotcha: preview.sh's self-session path CLEARS @livepicker-linked-id (tmux_unset_opt) — so when
          the self-session was the last-highlighted, restore sees an EMPTY linked_id and correctly
          skips the unlink (work-item point 1). Do NOT re-link or re-clear in restore.

# MUST READ — the empirical ground-truth for THIS task (8 live-verified findings).
- docfile: plan/001_fd5d622d3939/P1M5T1S1/research/restore_unlink_select_findings.md
  why: FINDING 1 (unlink no-`-k` removes one link, source KEEPS window — verified end-to-end on an
       isolated socket); FINDING 2 (singly-linked unlink FAILS rc=1 "window only linked to one
       session" -> MUST ignore; NEVER `-k` which would destroy the window in ALL sessions);
       FINDING 3 (select-window -t @id rc=0); FINDING 4 (LOAD-BEARING: display-message -p
       '#{session_name}' returned "src" — an ARBITRARY session — when detached; production has a
       client so it's correct, but the MOCK MUST attach one; ORIG_SESSION is the client-independent
       equivalent); FINDING 5 (list-windows -t '=driver' -F '#{window_id}' is the before/after
       assertion handle); FINDING 6 (linked_id == src_id; preview.sh tracks it); FINDING 7
       (restore.sh is a subprocess -> source its own lib trio); FINDING 8 (house style: set -u only,
       tabs, || true on every fail-expected tmux call).
  critical: Read BEFORE writing the file. FINDING 4 is the highest-consequence testability detail
            (a detached mock FALSE-FAILS the "gone from driver" assertion because the unlink targets
            the wrong session). FINDING 2 is the highest-consequence correctness detail (a missing
            `|| true` would abort under a future set -e; a stray `-k` would destroy data).

# MUST READ — the PRD sections selected for this work item.
- docfile: PRD.md
  why: §9 "State saved and restored" (restore steps 1-2 — the controlling spec: "1. Unlink the
       preview window from the current session if @livepicker-linked-id is set. 2. select-window -t
       $ORIG_WINDOW"); §13 "tmux primitives reference" (unlink-window -t <session>:<id>;
       select-window -t <id>); §16 "Implementation risks" (window addressing by id, not index).
  section: "§9 State saved and restored", "§13 tmux primitives reference", "§16 Implementation risks and notes"

# MUST READ — system ground-truth (shell style + the unlink semantics).
- docfile: plan/001_fd5d622d3939/architecture/tmux_primitives.md
  why: §1 link-window/unlink-window (unlink without -k removes ONE link, source keeps window;
       unlink on a singly-linked window FAILS — must ignore; NEVER -k); §7 the `=$S` exact-match
       target prefix (for list-windows assertions); §4 hooks (unlink fires window-unlinked, NOT
       session-window-changed / client-session-changed — so T1.S1's unlink is history-pollution-free).
  section: "§1 link-window / unlink-window", "§4 set-hook / session-window-changed", "§7 switch-client"

# MUST READ — system ground-truth (shell style + the saved-state contract).
- docfile: plan/001_fd5d622d3939/architecture/system_context.md
  why: §3 INVARIANT A (unlink-window fires neither session-window-changed nor client-session-changed
       -> restore's unlink cannot pollute session history); §9 shell style (set -u ONLY, NO -e, NO
       -o pipefail; tabs; local for all function locals; CURRENT_DIR idiom); §4 TRAP 1/2 (status-
       format/hook restore — NOT T1.S1's concern, but T3's; mentioned so the seam comments are
       accurate).
  section: "§3 The three load-bearing invariants", "§9 Shell style", "§4 Two environment-specific traps"

# MUST READ — the activate PRP (what SAVED the state T1.S1 reads).
- docfile: plan/001_fd5d622d3939/P1M4T1S1/PRP.md
  why: STEP 2 saves @livepicker-orig-window via `tmux display-message -p '#{window_id}'` (an @N id)
       and @livepicker-orig-session via `#{session_name}`. Confirms ORIG_WINDOW is the bare @N id and
       ORIG_SESSION is the bare session name. T1.S1 reads both back via get_state.

# MUST READ — the parallel sibling PRPs that will EXTEND this file (seam contract).
- docfile: plan/001_fd5d622d3939/P1M5T2S1/PRP.md
  why: (if present) T2 owns restore step 3: if argv[1]==cancel, switch-client -t "$ORIG_SESSION";
       if keep, do not switch. T2 reads argv[1] + ORIG_SESSION. Its block inserts at the T2 seam
       comment. T1.S1 must leave that seam + NOT read $1/ORIG_SESSION itself (avoid unused-var).
- docfile: plan/001_fd5d622d3939/P1M5T3S1/PRP.md
  why: (if present) T3 owns restore step 4: restore status, status-format (TRAP 1 via
       state_status_format_restore), key-table, renumber-windows, the session-window-changed hook
       (TRAP 2). Inserts at the T3 seam.
- docfile: plan/001_fd5d622d3939/P1M5T4S1/PRP.md
  why: (if present) T4 owns restore steps 5-6: select-layout "$ORIG_LAYOUT" + clear_all_state +
       unbind-key -T livepicker. Inserts at the T4 seam. clear_all_state is already in state.sh.
```

### Current Codebase tree

```bash
tmux-livepicker/
  PRD.md
  plugin.tmux                 # COMPLETE. Binds prefix key -> scripts/livepicker.sh.
  plan/001_fd5d622d3939/{architecture/*.md, tasks.json, prd_snapshot.md, prd_index.txt}
  plan/001_fd5d622d3939/P1M3T1S1/{PRP.md, research/preview_link_unlink_findings.md}   # preview.sh creator (unlink idiom)
  plan/001_fd5d622d3939/P1M4T1S1/{PRP.md, research/activate_guard_save_findings.md}    # livepicker.sh creator (state save)
  plan/001_fd5d622d3939/P1M4T5S1/{PRP.md, research/first_preview_mode_on_refresh_findings.md}  # parallel (preview invokes)
  plan/001_fd5d622d3939/P1M5T1S1/{PRP.md, research/restore_unlink_select_findings.md}  # THIS
  scripts/
    options.sh   # COMPLETE. Unchanged. (T1.S1 does not read options directly.)
    utils.sh     # COMPLETE. Unchanged.
    state.sh     # COMPLETE — STATE_LINKED_ID / ORIG_WINDOW / ORIG_SESSION / get_state (INPUT deps). Unchanged.
    renderer.sh  # COMPLETE. Unchanged.
    preview.sh   # COMPLETE (P1.M3). Unchanged. (Structural TEMPLATE + the unlink idiom + mock link setup.)
    livepicker.sh   # COMPLETE (P1.M4). Unchanged. (Parallel; T5 invokes preview.sh.)
    # NOTE: restore.sh does NOT exist yet — THIS task CREATES it.
  .gitignore
  # NOTE: NO test harness (P1.M7); NO input-handler.sh yet (P1.M6). Validate via the throwaway
  #       socket-shim mock (mirrors P1.M4.T5.S1's attach/detach helpers; MUST keep an attached
  #       client so display-message + the unlink target are correct — FINDING 4).
```

### Desired Codebase tree with files to be added and responsibility of file

```bash
tmux-livepicker/
  scripts/
    options.sh   # INPUT dep — unchanged.
    utils.sh     # INPUT dep — unchanged.
    state.sh     # INPUT dep — unchanged.
    renderer.sh  # unchanged.
    preview.sh   # unchanged (structural template + mock link-setup).
    livepicker.sh   # unchanged.
    restore.sh   # CREATED (this task). Executable. Mirrors preview.sh's skeleton.
                  # restore_main(argv[1]=keep|cancel):
                  #   STEP 1 (T1.S1): if @livepicker-linked-id non-empty ->
                  #     current_session=display-message; unlink-window -t "$current_session:$linked_id"
                  #     (NO -k; || true). Else skip.
                  #   STEP 2 (T1.S1): select-window -t "$orig_window" (|| true).
                  #   # --- T2 seam (P1.M5.T2.S1): keep/cancel switch-client ---
                  #   # --- T3 seam (P1.M5.T3.S1): status/key-table/renumber/hook restore ---
                  #   # --- T4 seam (P1.M5.T4.S1): select-layout + clear_all_state + unbind ---
                  #   return 0
                  # driver: restore_main "$@" || exit 1 ; exit 0
                  # After T1.S1: preview unlinked (S keeps window), original window selected.
```

### Known Gotchas of our codebase & Library Quirks

```bash
# CRITICAL (research FINDING 2 / preview.sh FINDING 11): unlink-window WITHOUT -k removes ONE
#   link; the source session KEEPS its window. On a SINGLY-linked window it FAILS rc=1
#   ("window only linked to one session") — tmux refuses to orphan. ALWAYS append
#   `2>/dev/null || true`. NEVER pass -k — that would DESTROY the window object in ALL
#   sessions (the candidate session S permanently loses its window).
#     tmux unlink-window -t "$current_session:$linked_id" 2>/dev/null || true    # ✓
#     tmux unlink-window -k -t ...                                               # ✗ NEVER

# CRITICAL (research FINDING 4 / LOAD-BEARING for the MOCK): `tmux display-message -p
#   '#{session_name}'` is NON-DETERMINISTIC when no client is attached — on the isolated
#   socket it returned "src" (an arbitrary session), NOT the driver. In PRODUCTION this is
#   safe: restore runs under run-shell from a key press (cancel/confirm in the livepicker
#   table), so a client provably exists, and at step-1 time NO switch has happened yet
#   (switch is step 3 / T2), so the client's session == the driver == ORIG_SESSION. BUT
#   the test MOCK MUST keep an attached client across `bash restore.sh` (mirror
#   P1.M4.T5.S1's attach/detach helpers). A detached mock would feed unlink-window the
#   WRONG session -> rc=1 (ignored, harmless) but the link would NOT be cleaned -> the
#   "gone from driver" assertion FALSE-FAILS.

# GOTCHA (research FINDING 4 alt): the link was created by preview.sh into current_session,
#   and preview.sh's current_session is `get_state "$ORIG_SESSION" ""`. So the unlink target
#   is ALWAYS "$ORIG_SESSION:$LINKED_ID". Using `get_state "$ORIG_SESSION" ""` directly is
#   DETERMINISTIC and client-independent and yields the SAME value as the attached
#   display-message in production. The work-item CONTRACT specifies display-message; the PRP
#   uses display-message (faithful) but notes ORIG_SESSION as the robust equivalent. Either
#   is correct; do NOT mix (pick one). If you pick display-message, the mock MUST attach.

# CRITICAL (research FINDING 3 / system_context §2): address windows by @id, NEVER index.
#   ORIG_WINDOW is the @N id activate saved (display-message -p '#{window_id}').
#   renumber-windows is on -> indices are unstable. select-window -t "$orig_window" (the id).

# CRITICAL (house style / system_context §9): `set -u` ONLY. NO `set -e`, NO `set -o pipefail`.
#   unlink-window legitimately returns non-zero (singly-linked edge — FINDING 2); select-window
#   may return non-zero if ORIG_WINDOW vanished; display-message may return non-zero without a
#   client. Under set -e ANY of these would abort a half-restored teardown. We do NOT use set -e;
#   `2>/dev/null || true` is the scoped "ignore this rc" idiom (mirror preview.sh).

# GOTCHA (research FINDING 7): restore.sh is its OWN PROCESS under run-shell. Sourced state
#   does NOT cross process boundaries -> it MUST source its own lib trio (options/utils/state)
#   via the resolved $CURRENT_DIR, exactly like preview.sh and livepicker.sh. Do NOT assume
#   state.sh is already sourced.

# GOTCHA (shellcheck): file-level `# shellcheck disable=SC1091,SC2153` mirrors preview.sh.
#   SC1091 = can't follow the `source "$CURRENT_DIR/..."` lines (dynamic path). SC2153 =
#   ORIG_WINDOW/STATE_LINKED_ID look like possible typos of ORIG_SESSION/STATE_LIST to
#   shellcheck (it sees no assignment) but they are readonly CONTRACT constants in state.sh.
#   restore.sh adds NO new word-split on user input -> NO new disable needed.

# GOTCHA (preview.sh self-session interaction): preview.sh's self-session path CLEARS
#   @livepicker-linked-id (tmux_unset_opt). So when the user's LAST highlighted session was
#   their own (the self-session), restore sees linked_id == "" and CORRECTLY skips the unlink
#   (work-item point 1: "if empty ... there is nothing to unlink"). Do NOT add a fallback link
#   or re-clear; the empty check is the entire self-session handling for restore.

# STYLE (system_context §9): indent with TABS. Verify with `grep -Pn '^    ' scripts/restore.sh`
#   (expect empty). shfmt is NOT installed. `local` for ALL function locals.
```

## Implementation Blueprint

### Data models and structure

No new data model. `restore_main` declares three function-locals:
- `linked_id` — read from `@livepicker-linked-id` (empty ⇒ self-session ⇒ skip unlink).
- `orig_window` — read from `@livepicker-orig-window` (the `@N` select target).
- `current_session` — derived via `display-message -p '#{session_name}'` (only when unlinking).

The **read set** is two accessors (`get_state "$STATE_LINKED_ID"`, `get_state
"$ORIG_WINDOW"`) + one client-context capture (`display-message`). The **write
set** is at most two tmux mutations (`unlink-window`, `select-window`), each
guarded. `argv[1]` (`keep`|`cancel`) is available as `"$1"` for T2; T1.S1 does
NOT read it (avoids an unused-variable smell; T2's seam owns the branch).

### Implementation Tasks (ordered by dependencies)

```yaml
Task 1: CREATE scripts/restore.sh (full skeleton + STEP 1 + STEP 2 + T2/T3/T4 seams)
  - FILE: ./scripts/restore.sh  (NEW; mirror scripts/preview.sh's skeleton).
  - WRITE the complete file from "Implementation Patterns & Key Details" below:
    shebang; file-level shellcheck disable=SC1091,SC2153; header doc (purpose,
    PRD §9 steps 1-2 / §13 / §16 refs, load-bearing rules, deps, the seam map);
    CURRENT_DIR + source trio; restore_main() with STEP 1 + STEP 2 + 3 seam
    comments + return 0; driver (restore_main "$@" || exit 1 ; exit 0).
  - chmod +x scripts/restore.sh   (preview.sh/livepicker.sh are executable).

Task 2: VERIFY house style + no off-limits work
  - RUN: bash -n scripts/restore.sh            (expect exit 0, no output)
  - RUN: shellcheck scripts/restore.sh         (expect 0 findings; no new disable)
  - RUN: grep -Pn '^    ' scripts/restore.sh   (expect empty — tabs only)
  - RUN: grep -n 'set -e\|set -o pipefail' scripts/restore.sh  (expect empty — set -u only)
  - EXPECT: exactly ONE unlink-window WITHOUT -k; exactly ONE select-window -t "$orig_window";
    NO switch-client (T2); NO set-option status/status-format/key-table/renumber or set-hook (T3);
    NO select-layout/clear_all_state/unbind-key (T4); NO link-window/capture-pane (preview.sh).

Task 3: VALIDATE (Level 1 syntax/lint + Level 2 socket-shim mock: link via preview.sh,
        run restore.sh, assert gone-from-driver + still-in-origin + active==ORIG_WINDOW,
        with an attached client)
  - RUN the socket-shim mock (Validation Loop §2). Self-cleaning, isolated socket,
    attached client (FINDING 4). Sources the REAL scripts/{options,utils,state}.sh,
    runs the REAL scripts/preview.sh to link, then the REAL scripts/restore.sh.
```

### Implementation Patterns & Key Details

The complete, ready-to-write `scripts/restore.sh` (the implementer writes this
verbatim; indent inside `restore_main` is ONE tab to match preview.sh):

```bash
#!/usr/bin/env bash
# shellcheck disable=SC1091,SC2153
#   SC1091: sources sibling libs (options/utils/state) via the resolved $CURRENT_DIR;
#           follow with `shellcheck -x` if you want them traced.
#   SC2153: ORIG_WINDOW/STATE_LINKED_ID are readonly CONTRACT constants defined in
#           state.sh (sourced above); shellcheck sees no assignment here.
# scripts/restore.sh — tmux-livepicker teardown orchestrator.
#
# argv[1] = 'keep' | 'cancel' (consumed by P1.M5.T2.S1's switch branch; NOT read
# by T1.S1's steps 1-2). Implements PRD §9 "State saved and restored", restore
# list, in order — THIS FILE owns steps 1-2; steps 3-6 land in the T2/T3/T4
# seams below:
#   1. Unlink the preview window from the current session if @livepicker-linked-id is set.  [T1.S1]
#   2. select-window -t "$ORIG_WINDOW".                                            [T1.S1]
#   3. keep: do not switch. cancel: switch-client -t "$ORIG_SESSION".              [T2 seam]
#   4. Restore status, status-format[n], renumber-windows, key-table, the hook.    [T3 seam]
#   5. select-layout "$ORIG_LAYOUT".                                               [T4 seam]
#   6. clear_all_state + unbind the livepicker table.                             [T4 seam]
#
# LOAD-BEARING RULES (research/restore_unlink_select_findings.md):
#  - unlink-window WITHOUT -k removes ONE link; the source session KEEPS its
#    window (FINDING 1). It FAILS (rc=1) only when singly-linked -> ALWAYS
#    `2>/dev/null || true`. NEVER pass -k (would destroy the shared window in
#    ALL sessions — FINDING 2 / preview.sh FINDING 11).
#  - @livepicker-linked-id is EMPTY when the self-session was the last highlight
#    (preview.sh's self-session path clears it). Empty => nothing to unlink ->
#    skip the unlink entirely (work-item point 1).
#  - Address windows by @id, NEVER index (renumber-windows on — FINDING 3 /
#    system_context §2). ORIG_WINDOW is the @N id activate STEP 2 saved.
#  - current_session via `tmux display-message -p '#{session_name}'`. In
#    production a client is attached (restore runs from a key press) and NO
#    switch has happened yet (switch is step 3 / T2), so the client's session ==
#    the driver == ORIG_SESSION (FINDING 4). The test mock MUST attach a client
#    or display-message returns an arbitrary session (detached non-determinism).
#  - unlink-window fires window-unlinked ONLY — NOT session-window-changed, NOT
#    client-session-changed (Invariant A; system_context §3). So this unlink
#    cannot pollute session history.
#  - NO `set -e` (unlink/select/display legitimately return non-zero; a transient
#    failure must not abort a half-restored teardown). `set -u` inherited; every
#    var defaulted at read.
#
# DEPENDS ON (source order load-bearing — state.sh needs utils.sh first):
#   options.sh (opt_*), utils.sh (tmux_*), state.sh (get_state/STATE_*/ORIG_*).
#   restore.sh is its OWN process under run-shell -> it MUST source its own trio
#   (sourced state does not cross process boundaries — FINDING 7).

CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=options.sh
source "$CURRENT_DIR/options.sh"
# shellcheck source=utils.sh
source "$CURRENT_DIR/utils.sh"
# shellcheck source=state.sh
source "$CURRENT_DIR/state.sh"

# argv[1] = 'keep' | 'cancel' (T2's branch; T1.S1's steps 1-2 do not read it).
restore_main() {
	local linked_id orig_window current_session

	# --- STEP 1 (PRD §9 restore step 1): unlink the preview window ---
	# @livepicker-linked-id is empty when the self-session was the last highlight
	# (preview.sh cleared it) -> nothing to unlink (work-item point 1). Non-empty
	# means a foreign window is linked into the driver -> unlink it from the
	# CURRENT session only (NO -k; source keeps it — FINDING 1; ignore the
	# singly-linked rc=1 — FINDING 2).
	linked_id="$(get_state "$STATE_LINKED_ID" "")"
	if [ -n "$linked_id" ]; then
		current_session="$(tmux display-message -p '#{session_name}' 2>/dev/null || true)"
		# display-message is non-deterministic without a client (FINDING 4); in
		# production a client is attached (== ORIG_SESSION at this point). If it
		# came back empty, fall back to the client-independent saved driver name.
		[ -n "$current_session" ] || current_session="$(get_state "$ORIG_SESSION" "")"
		tmux unlink-window -t "$current_session:$linked_id" 2>/dev/null || true
	fi

	# --- STEP 2 (PRD §9 restore step 2): re-select the original window ---
	# ORIG_WINDOW is the @N id activate saved (NOT an index — renumber-windows on).
	# Guard on non-empty + ignore rc (ORIG_WINDOW could have vanished in a race).
	orig_window="$(get_state "$ORIG_WINDOW" "")"
	[ -n "$orig_window" ] && tmux select-window -t "$orig_window" 2>/dev/null || true

	# --- T2 (P1.M5.T2.S1): keep/cancel client branch (insert here) ---
	# PRD §9 restore step 3: if argv[1]=='cancel', switch-client -t "$ORIG_SESSION"
	# (return to the original session); if 'keep', do NOT switch (stay on the
	# chosen target). Reads "$1" and get_state "$ORIG_SESSION" "".

	# --- T3 (P1.M5.T3.S1): restore status / status-format / key-table /
	#     renumber-windows / session-window-changed hook (insert here) ---
	# PRD §9 restore step 4. status-format via state_status_format_restore
	# (TRAP 1: -gu reset then replay saved indices). key-table/renumber/status
	# via tmux_set_opt from ORIG_*. Hook via the saved ORIG_HOOK verbatim
	# (TRAP 2: preserve -b).

	# --- T4 (P1.M5.T4.S1): select-layout ORIG_LAYOUT + clear_all_state +
	#     unbind-key -T livepicker (insert here) ---
	# PRD §9 restore steps 5-6. select-layout "$ORIG_LAYOUT"; clear_all_state
	# (state.sh — clears the 5 runtime keys + every @livepicker-orig-*); then
	# tmux unbind-key -T livepicker <each> (or unbind-key -aT livepicker).

	return 0
}

restore_main "$@" || exit 1
exit 0
```

NOTE for the implementer:
- This file is the structural twin of `scripts/preview.sh` (same shebang, same
  shellcheck disables, same header-doc shape, same `$CURRENT_DIR` + source trio
  + `<thing>_main` + driver). Use it as-is; the only allowed deviation is
  comment phrasing.
- The unlink call is the SAME idiom preview.sh uses internally
  (`tmux unlink-window -t "$current_session:$linked_id" 2>/dev/null || true`) —
  restore just runs it at the top level instead of inside the preview flow.
- The `display-message` fallback to `ORIG_SESSION` (the `[ -n "$current_session"
  ] || ...` line) is a one-line hardening: in production display-message is
  non-empty and correct, so the fallback never fires; in a detached edge it
  keeps the unlink targeting the right session. It is a faithful superset of
  the contract (which specifies display-message). If you prefer to follow the
  contract literally, drop the fallback line — but then the MOCK MUST attach a
  client (it must anyway, per FINDING 4).
- `chmod +x scripts/restore.sh` after writing (preview.sh and livepicker.sh are
  executable; restore.sh is invoked via run-shell like them).
- Do NOT read `"$1"` or `ORIG_SESSION` for T1.S1's own logic — T2's seam owns
  both (avoids an unused-variable smell). `$1` is available throughout
  `restore_main` for T2.
- Do NOT add `set -e`. Do NOT pass `-k` to unlink-window. Do NOT call
  `switch-client` (T2), status/key-table/hook mutations (T3), or
  `select-layout`/`clear_all_state`/`unbind-key` (T4). Do NOT create any other
  file.

### Integration Points

```yaml
HOST FILE (what this task creates):
  - scripts/restore.sh: NEW. restore_main() with STEP 1 + STEP 2 + T2/T3/T4 seams + driver.

CALLERS / CONSUMERS (this file's OUTPUT — observed by FUTURE subtasks):
  - P1.M6 (input-handler.sh — PLANNED): the confirm + cancel actions invoke
        "$CURRENT_DIR/restore.sh" keep | cancel (the same $CURRENT_DIR/.. idiom
        T3/T4.S1 use for renderer/input-handler). restore.sh is a SUBPROCESS.
  - P1.M5.T2.S1 (PLANNED): fills the T2 seam — reads "$1" + ORIG_SESSION, does
        the keep/cancel switch-client branch.
  - P1.M5.T3.S1 (PLANNED): fills the T3 seam — restores status/status-format
        (state_status_format_restore)/key-table/renumber/hook.
  - P1.M5.T4.S1 (PLANNED): fills the T4 seam — select-layout ORIG_LAYOUT +
        clear_all_state (state.sh) + unbind-key -T livepicker.

STATE READS (this task — T1.S1 steps 1-2):
  - @livepicker-linked-id   (via get_state "$STATE_LINKED_ID" ""; written by preview.sh)
  - @livepicker-orig-window (via get_state "$ORIG_WINDOW" "";   written by activate STEP 2)
  - (client context) current session via display-message -p '#{session_name}'
        (+ ORIG_SESSION fallback only if display-message returned empty)

STATE WRITES (this task): NONE. (T1.S1 clears no @livepicker-* key; T4's
  clear_all_state owns that. The unlink removes a tmux WINDOW LINK, not an option.)

TMUX MUTATIONS (this task — PRD §13 primitives):
  - unlink-window -t "$current_session:$linked_id"  (NO -k; || true — removes ONE link;
        source session keeps the window; fires window-unlinked ONLY — Invariant A)
  - select-window -t "$orig_window"                 (|| true; the @N id; fires
        session-window-changed, NOT client-session-changed — Invariant A)
  - NO switch-client (T2); NO status/status-format/key-table/renumber/set-hook (T3);
        NO select-layout/clear_all_state/unbind-key (T4); NO link-window/capture-pane.

DATABASE / MIGRATIONS / ROUTES / CONFIG: none.
```

## Validation Loop

### Level 1: Syntax & Style (Immediate Feedback)

```bash
# Run after creating the file — fix before proceeding.
bash -n scripts/restore.sh                     # syntax; expect no output, exit 0
shellcheck scripts/restore.sh                  # lint; expect 0 findings (file-level
                                               # disable=SC1091,SC2153 mirrors preview.sh)
# Tabs-not-spaces sanity (shfmt NOT installed):
grep -Pn '^    ' scripts/restore.sh && echo "FAIL: 4-space indent found, use tabs" || echo "OK: tabs only"
# Confirm house style (set -u only, NO -e / NO pipefail):
grep -n 'set -e\|set -o pipefail' scripts/restore.sh && echo "FAIL: set -e/pipefail present" || echo "OK: set -u only"
# Confirm the file is executable (preview.sh / livepicker.sh are):
[ -x scripts/restore.sh ] && echo "OK: executable" || { chmod +x scripts/restore.sh; echo "fixed: chmod +x"; }
# Confirm T1.S1's exact primitives are present (conditional unlink WITHOUT -k + select by id):
grep -n 'unlink-window -t "\$current_session:\$linked_id" 2>/dev/null || true' scripts/restore.sh   # expect 1
grep -n 'tmux unlink-window -k' scripts/restore.sh && echo "FAIL: -k would destroy the window" || echo "OK: no -k"
grep -n 'select-window -t "\$orig_window" 2>/dev/null || true' scripts/restore.sh                    # expect 1
grep -n 'if \[ -n "\$linked_id" \]' scripts/restore.sh                                              # expect 1 (conditional)
# Confirm the three sibling seams + the driver are present:
grep -n 'T2 (P1.M5.T2.S1): keep/cancel client branch (insert here)' scripts/restore.sh   # expect 1
grep -n 'T3 (P1.M5.T3.S1): restore status' scripts/restore.sh                            # expect 1
grep -n 'T4 (P1.M5.T4.S1): select-layout ORIG_LAYOUT' scripts/restore.sh                 # expect 1
grep -n 'restore_main "\$@" || exit 1' scripts/restore.sh                                # expect 1 (driver)
# Confirm NO off-limits work leaked in:
grep -n 'switch-client\|set-option.*status\|status-format\[\|set-option -g key-table\|set-hook\|select-layout\|clear_all_state\|unbind-key\|link-window\|capture-pane' scripts/restore.sh \
  | grep -v 'insert here\|T2\|T3\|T4\|#' \
  && echo "FAIL: T1.S1 must not do T2/T3/T4/preview work (seam comments only)" || echo "OK: only steps 1-2 implemented"
# Run from the repo root.
```

### Level 2: Socket-Shim Mock Validation — link via preview.sh → restore.sh → gone-from-driver + still-in-origin + active==ORIG_WINDOW, zero live-server impact

Reuses the PATH-wrapper socket shim. Self-cleaning. Sources the REAL
`scripts/{options,utils,state}.sh`, runs the ACTUAL `scripts/preview.sh` to link
a foreign window, then the ACTUAL `scripts/restore.sh` to tear it down.
**MUST keep an attached client** (so `display-message` returns the driver
session, not an arbitrary one — FINDING 4; same constraint as P1.M4.T5.S1's
mock). Mirrors the T5 mock's `attach`/`detach` helpers.

```bash
#!/usr/bin/env bash
# Throwaway socket-shim validation for scripts/restore.sh T1.S1 (do NOT commit).
set -u
REPO_ROOT="$(cd "$(dirname "$0")" && pwd)"
[ -f "$REPO_ROOT/scripts/restore.sh" ] || { echo "restore.sh missing"; exit 1; }
for l in options utils state preview; do
	[ -f "$REPO_ROOT/scripts/$l.sh" ] || { echo "INPUT dep $l.sh missing"; exit 1; }
done

SOCK="lp-restore-mock-$$"
SHIM_DIR="$(mktemp -d)"
cat > "$SHIM_DIR/tmux" <<EOF
#!/usr/bin/env bash
exec /usr/bin/tmux -L "$SOCK" "\$@"
EOF
chmod +x "$SHIM_DIR/tmux"
export PATH="$SHIM_DIR:$PATH"

cleanup() {
	PATH="/usr/bin:/bin:$PATH" tmux -L "$SOCK" kill-server 2>/dev/null || true
	rm -rf "$SHIM_DIR"
}
trap cleanup EXIT

pass=0; fail=0
assert() { if [ "$2" = "$3" ]; then pass=$((pass+1)); printf 'ok   %s\n' "$1"; else fail=$((fail+1)); printf 'FAIL %s: got=[%s] want=[%s]\n' "$1" "$2" "$3"; fi; }

attach() { TMUX="" script -qec "tmux -L $SOCK attach -t $1" /dev/null >/dev/null 2>&1 & AP=$!; sleep 0.5; }
detach() { kill "$AP" 2>/dev/null; wait "$AP" 2>/dev/null; }
clear_lp() {
	for k in mode list filter index linked-id type orig-session orig-window orig-layout \
	         orig-key-table orig-status orig-renumber-windows orig-session-window-changed \
	         orig-status-format-indices; do tmux set-option -gu "@livepicker-$k" 2>/dev/null; done
}

# ---------- (a)+(b)+(c): link via preview.sh -> restore.sh -> assertions ----------
tmux new-session -d -s driver -x 120 -y 40
tmux new-window -t driver                       # a second driver window (so select has somewhere to return from)
tmux new-session -d -s foreign -x 120 -y 40
tmux send-keys -t foreign:0 "echo FOREIGN_PANE_CONTENT" Enter
sleep 0.2

# Seed the saved-state contract the way activate STEP 2 would (restore reads these).
# driver is the session the picker runs INSIDE; its active window is ORIG_WINDOW.
tmux set-option -g "@livepicker-orig-session" "driver"
tmux set-option -g "@livepicker-orig-window" "$(tmux list-windows -t '=driver' -F '#{window_id}' -f '#{window_active}')"
orig_window="$(tmux show-option -gv '@livepicker-orig-window')"

# Use the REAL preview.sh to link foreign's active window into driver (the live path).
# preview.sh needs ORIG_SESSION (current_session) + ORIG_WINDOW set (done above).
attach driver
bash "$REPO_ROOT/scripts/preview.sh" "foreign"; prc=$?
detach
assert "preview.sh link rc==0" "$prc" "0"
linked_id="$(tmux show-option -gv '@livepicker-linked-id' 2>/dev/null)"
assert "preview.sh set @livepicker-linked-id (non-empty)" "$([ -n "$linked_id" ] && echo set || echo empty)" "set"
# (pre) the foreign window id IS now in driver AND still in foreign
drv_before="$(tmux list-windows -t '=driver'  -F '#{window_id}' | tr '\n' ' ')"
for_before="$(tmux list-windows -t '=foreign' -F '#{window_id}' | tr '\n' ' ')"
assert "(pre) linked id present in driver"  "$(echo " $drv_before " | grep -c " $linked_id ")" "1"
assert "(pre) linked id present in foreign" "$(echo " $for_before " | grep -c " $linked_id ")" "1"

# Run the REAL restore.sh (T1.S1). Attach so display-message -> "driver".
attach driver
bash "$REPO_ROOT/scripts/restore.sh"; rrc=$?
detach
assert "restore.sh exit 0" "$rrc" "0"

# (a) the linked window id is GONE from the driver session
drv_after="$(tmux list-windows -t '=driver'  -F '#{window_id}' | tr '\n' ' ')"
assert "(a) linked id GONE from driver after restore" "$(echo " $drv_after " | grep -c " $linked_id ")" "0"
# (b) the linked window id is STILL in its origin (foreign) session
for_after="$(tmux list-windows -t '=foreign' -F '#{window_id}' | tr '\n' ' ')"
assert "(b) linked id STILL in foreign after restore" "$(echo " $for_after " | grep -c " $linked_id ")" "1"
# (c) the driver's active window is ORIG_WINDOW again
act_w="$(tmux display-message -p -t '=driver' '#{window_id}' 2>/dev/null)"
assert "(c) driver active window == ORIG_WINDOW" "$act_w" "$orig_window"
clear_lp

# ---------- (d): self-session case — empty linked_id -> NO unlink, NO error ----------
# preview.sh's self-session path CLEARS @livepicker-linked-id. Simulate that end
# state directly and confirm restore handles empty gracefully (skip + still select).
tmux set-option -g "@livepicker-orig-session" "driver"
tmux set-option -g "@livepicker-orig-window" "$(tmux list-windows -t '=driver' -F '#{window_id}' -f '#{window_active}')"
orig_window2="$(tmux show-option -gv '@livepicker-orig-window')"
# Force a DIFFERENT window active first (so select-window has an observable effect).
other_w="$(tmux list-windows -t '=driver' -F '#{window_id}' | grep -v "$orig_window2" | head -1)"
[ -n "$other_w" ] && tmux select-window -t "$other_w" 2>/dev/null
tmux set-option -gu "@livepicker-linked-id"        # EMPTY — self-session was highlighted
attach driver
bash "$REPO_ROOT/scripts/restore.sh"; rrc2=$?
detach
assert "(d) restore exit 0 with empty linked_id" "$rrc2" "0"
act_w2="$(tmux display-message -p -t '=driver' '#{window_id}' 2>/dev/null)"
assert "(d) driver active window == ORIG_WINDOW (select ran, unlink skipped)" "$act_w2" "$orig_window2"
clear_lp

printf '\n==== PASS=%d FAIL=%d ====\n' "$pass" "$fail"
[ "$fail" = "0" ]
# Expected: PASS=11 FAIL=0. Key proofs:
#  - preview.sh linked foreign's window into driver (linked-id set, present in both sessions).
#  - (a) restore unlinked it from driver (gone from driver).
#  - (b) foreign STILL has the window (source unharmed — FINDING 1; the pollution invariant).
#  - (c) the driver's active window is back to ORIG_WINDOW (FINDING 3).
#  - (d) the self-session empty-linked_id case skips unlink + still selects (work-item point 1).
```

### Level 3: Integration Testing (System Validation)

```bash
# Live spot-check on an ISOLATED socket WITH an attached client — confirms restore
# leaves the driver session with exactly its original windows (no foreign leftover)
# and the foreign session intact. Self-cleaning. (P1.M5.T2-T4 are not built yet, so
# this checks ONLY steps 1-2: the status bar / key-table / state are NOT restored here.)
export LP_SOCK="lp-restore-live-$$"
REPO_ROOT="$(pwd)"
SHIM_DIR="$(mktemp -d)"
cat > "$SHIM_DIR/tmux" <<EOF
#!/usr/bin/env bash
exec /usr/bin/tmux -L "$LP_SOCK" "\$@"
EOF
chmod +x "$SHIM_DIR/tmux"
trap 'PATH=/usr/bin:/bin:$PATH tmux -L "$LP_SOCK" kill-server 2>/dev/null; rm -rf "$SHIM_DIR"' EXIT
T() { PATH="$SHIM_DIR:$PATH" tmux "$@"; }
T new-session -d -s driver -x 120 -y 40
T new-session -d -s foreign -x 120 -y 40
T set-option -g "@livepicker-orig-session" "driver"
T set-option -g "@livepicker-orig-window" "$(T list-windows -t '=driver' -F '#{window_id}' -f '#{window_active}')"
echo "driver windows BEFORE: [$(T list-windows -t '=driver' -F '#{window_id}' | tr '\n' ' ')]"
TMUX="" script -qec "tmux -L $LP_SOCK attach -t driver" /dev/null >/dev/null 2>&1 &
AP=$!; sleep 0.5
PATH="$SHIM_DIR:$PATH" bash "$REPO_ROOT/scripts/preview.sh" "foreign"; echo "preview rc=$? (expect 0)"
echo "linked-id: [$(T show-option -gv '@livepicker-linked-id')]  driver windows AFTER link: [$(T list-windows -t '=driver' -F '#{window_id}' | tr '\n' ' ')]"
PATH="$SHIM_DIR:$PATH" bash "$REPO_ROOT/scripts/restore.sh"; echo "restore rc=$? (expect 0)"
echo "driver windows AFTER restore: [$(T list-windows -t '=driver' -F '#{window_id}' | tr '\n' ' ')] (foreign window gone)"
echo "foreign windows AFTER restore: [$(T list-windows -t '=foreign' -F '#{window_id}' | tr '\n' ' ')] (unchanged)"
echo "driver active: [$(T display-message -p -t '=driver' '#{window_id}')] == orig [$(T show-option -gv '@livepicker-orig-window')]"
kill "$AP" 2>/dev/null; wait "$AP" 2>/dev/null
# Expected: after link, driver has the foreign @id; after restore, driver does NOT;
# foreign always has it; driver active == ORIG_WINDOW.
```

### Level 4: Creative & Domain-Specific Validation

```bash
# Pollution invariant spot-check (PRD §15.18) for the restore unlink.
# unlink-window fires window-unlinked ONLY — NOT client-session-changed (Invariant A,
# tmux_primitives §4) — so restore cannot pollute session history. Run ONLY if
# @session-history-hist is present on the LIVE server; touches ONLY option reads +
# one isolated run of preview.sh then restore.sh (then cleans up).
if tmux show-options -gv "@session-history-hist" >/dev/null 2>&1; then
	REPO_ROOT="$(pwd)"
	# Set up a throwaway linked window on the LIVE server is risky; instead assert
	# structurally: restore.sh contains ONLY unlink-window + select-window (no
	# switch-client), and unlink-window is documented (tmux_primitives §4) to fire
	# neither session-window-changed nor client-session-changed.
	BEFORE="$(tmux show-options -gv "@session-history-hist" 2>/dev/null)"
	if grep -q 'switch-client' "$REPO_ROOT/scripts/restore.sh"; then
		echo "FAIL: restore.sh must not switch-client in T1.S1 (T2 owns it)"
	else
		echo "OK: restore.sh T1.S1 has no switch-client -> no client-session-changed -> history-safe"
	fi
	# (A full live pollution diff belongs in P1.M7.T5's test_pollution.sh, which
	# exercises the full activate→browse→restore cycle.)
else
	echo "SKIP: tmux-session-history not present on live server (mock §2 covers this structurally)"
fi
# Expected: OK — T1.S1's unlink-window (window-unlinked) + select-window
# (session-window-changed) fire NEITHER client-session-changed, so the history
# timeline is untouched by restore steps 1-2.
```

## Final Validation Checklist

### Technical Validation

- [ ] `bash -n scripts/restore.sh` exits 0 with no output.
- [ ] `shellcheck scripts/restore.sh` reports 0 findings (file-level disable
      from preview.sh; T1.S1 adds no word-split, no new disable).
- [ ] No 4-space indents (`grep -Pn '^    '` is empty); tabs only.
- [ ] `scripts/restore.sh` is executable (`chmod +x`).

### Feature Validation

- [ ] `scripts/restore.sh` EXISTS and mirrors preview.sh's skeleton (shebang,
      shellcheck disables, header doc, `$CURRENT_DIR`, source trio,
      `restore_main`, driver).
- [ ] STEP 1: unlink runs ONLY when `linked_id` is non-empty; uses
      `unlink-window -t "$current_session:$linked_id"` with **NO `-k`** and
      `2>/dev/null || true`; `current_session` from `display-message -p
      '#{session_name}'` (with ORIG_SESSION fallback).
- [ ] STEP 2: `select-window -t "$orig_window"` (the `@N` id; `2>/dev/null ||
      true`); guarded on `orig_window` non-empty.
- [ ] Three seam comments (T2/T3/T4) present between step 2 and `return 0`.
- [ ] Mock (a) linked id gone from driver; (b) still in origin; (c) active
      window == ORIG_WINDOW; (d) empty-linked_id self-session case skips unlink
      + still selects.

### Code Quality Validation

- [ ] Follows existing codebase patterns (mirrors preview.sh's skeleton; reuses
      preview.sh's exact `unlink-window ... || true` idiom; `get_state` for
      STATE_*/ORIG_* reads; `$CURRENT_DIR` source trio).
- [ ] File placement matches the desired codebase tree (new file
      `scripts/restore.sh`; no other file touched).
- [ ] Anti-patterns avoided (no `-k` on unlink; no `switch-client` (T2); no
      status/key-table/hook mutation (T3); no select-layout/clear/unbind (T4);
      no `set -e`; no index addressing).
- [ ] Dependencies properly managed (sources its own lib trio; reads only
      STATE_LINKED_ID + ORIG_WINDOW; mutates at most unlink-window + select-window).

### Documentation & Deployment

- [ ] Code is self-documenting (the header cites PRD §9 steps 1-2 / §13 / §16;
      explains the no-`-k` rule, the empty-linked_id self-session skip, the
      display-message client requirement, and the seam map for T2/T3/T4).
- [ ] Logs are informative but not verbose (T1.S1 emits nothing on success; the
      unlink/select are silent).
- [ ] No new environment variables (T1.S1 uses only `@livepicker-linked-id`
      [preview.sh write] and `@livepicker-orig-window` [activate STEP 2 save]).

---

## Anti-Patterns to Avoid

- ❌ Don't pass `-k` to `unlink-window` — that DESTROYS the window object in ALL
  sessions (the candidate session S permanently loses its window). Use the bare
  `unlink-window -t "$session:$id"` (removes ONE link; source keeps it —
  FINDING 1) and ignore the singly-linked rc=1 with `|| true` (FINDING 2).
- ❌ Don't unlink unconditionally — guard on `linked_id` non-empty. When the
  self-session was the last highlight, preview.sh CLEARED
  `@livepicker-linked-id`, so there is nothing to unlink (work-item point 1).
  An unconditional `unlink-window -t "$session:"` (empty id) is a malformed
  target.
- ❌ Don't address the window by INDEX — `renumber-windows on` makes indices
  unstable. Use the saved `@N` id (`ORIG_WINDOW` / `linked_id`), never an index
  (FINDING 3 / system_context §2).
- ❌ Don't run the mock WITHOUT an attached client — `display-message -p
  '#{session_name}'` is non-deterministic detached (returned an arbitrary
  session — FINDING 4). A detached mock feeds unlink the wrong session (rc=1,
  ignored, but the link isn't cleaned → the "gone from driver" assertion
  FALSE-FAILS). Attach a client (mirror P1.M4.T5.S1's mock).
- ❌ Don't do T2/T3/T4 work in T1.S1 — no `switch-client` (T2), no
  status/status-format/key-table/renumber/hook restore (T3), no
  `select-layout`/`clear_all_state`/`unbind-key` (T4). Those are seam comments
  only. T1.S1 owns restore steps 1-2, nothing else.
- ❌ Don't add `set -e` / `set -o pipefail` — unlink/select/display legitimately
  return non-zero; a transient failure must not abort a half-restored teardown
  (house style; system_context §9).
- ❌ Don't forget to `source` the lib trio — restore.sh is its own process under
  run-shell; sourced state does not cross process boundaries (FINDING 7). Mirror
  preview.sh's `source "$CURRENT_DIR/{options,utils,state}.sh"`.
- ❌ Don't read `"$1"` or `ORIG_SESSION` for T1.S1's own logic — T2's seam owns
  both (the keep/cancel branch). Reading them in T1.S1 invites an unused-variable
  smell and muddies the seam boundary.
- ❌ Don't skip validation because "it should work" — run the socket-shim mock
  (a)–(d); assertion (b) ("still in origin") is what proves the no-`-k` rule
  matters (a stray `-k` would make (b) FAIL — the window would be gone from
  foreign too).
