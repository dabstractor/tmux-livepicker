# PRP — P1.M6.T3.S1: input-handler.sh `confirm` (incl. create-on-enter)

---

## Goal

**Feature Goal**: **FILL** the `confirm)` seam in `scripts/input-handler.sh`
(left as `return 0` by P1.M6.T1.S1; the `type`/`backspace`/`next-session`/
`prev-session` branches are COMPLETE via T1.S1 + T2.S1; the `cancel)` seam stays
for T4.S1). This is the **single most consequential branch in the whole plugin**:
it issues the **only** `switch-client` in the entire flow (PRD §4/§6/§14), so its
correctness *is* the pollution invariant (Invariant A).

Per PRD §6 Confirm + §15.22 Create-on-enter + §9 (restore) + §14 (pollution) +
the work-item CONTRACT §3, the branch resolves the highlighted item from the
filtered list and then **lands** on it:

- **target present, `type==session`** → `switch-client -t "=target"` (the ONE
  switch) → `restore.sh keep`.
- **target present, `type==window`** → `select-window -t "session:window_index"`
  (NO switch-client, NO creation) → `restore.sh keep`.
- **filtered list empty, `type==session`, `@livepicker-create==on`** →
  `tmux new-session -d -s "$query"`; **if it produced the EXACT `$query` name**
  → switch to it + restore keep; **else (invalid/sanitized/empty name)** →
  `restore.sh cancel`.
- **filtered empty otherwise (window mode, or `create==off`)** → `restore.sh cancel`.

**OUTPUT**: the client ends on the chosen target with **exactly one** session
switch (or zero, on cancel), and the picker is fully torn down by `restore.sh`
(keep leaves the client on the target; cancel returns it to the original).

This is a **pure EDIT-in-place** of `scripts/input-handler.sh` — **NO new files**
(unlike T2.S1, which created `filter.sh`). It mirrors the incremental-edit model
P1.M5 used to grow `restore.sh` across T1→T4: grow the `local` line, add ONE
private helper, split the seam into a full branch, leave every other branch +
the driver untouched.

**Deliverable** (all in `scripts/input-handler.sh`):
1. **EDIT** the `local` line — append `pick_type query` (the confirm-only locals).
2. **ADD** one file-scope helper `_confirm_land_on_session "$tgt"` (mirrors
   `preview.sh`'s `preview_fallback` convention) that encapsulates the
   load-bearing **unlink-the-driver-preview-BEFORE-switch** sequence and the
   `restore.sh keep` teardown — called by BOTH the session-target branch and the
   create-on-success branch, so the catastrophic FINDING 1/2 fix lives in ONE place.
3. **REPLACE** the `confirm)` seam's `return 0` with the full branch (5 decision
   paths above), delegating the switch-and-teardown to the helper.

**Success Definition**:
- `bash -n` + `shellcheck` pass on `scripts/input-handler.sh` (0 findings beyond
  the existing file-level `disable=SC1091,SC2153`). Tabs only; `set -u` only.
- **FINDING 1/2 regression (CATASTROPHIC) does NOT occur:** after a session-mode
  confirm on a match, the **driver** session is cleaned of the preview window
  (no leftover linked `@id`) AND the **target** session still has its window
  intact (not destroyed). Verified by `research/confirm_mock.sh` cluster (a).
- **Exactly one switch:** a confirm on a target ≠ current session produces
  **exactly one** `client-session-changed` navigation (forward history collapses,
  target appended at tip — browser-like, PRD §14); a confirm on the same session
  (or a cancel) produces **zero** (the engine dedups — FINDING 7).
- **Create gate is robust (FINDING 4/5):** query `"proj:two"` (`:` sanitized to
  `_`) or `""` → the branch cancels (does NOT strand the client on a name that
  does not exist); query `"clean123"` → the session is created AND active.
- **Window mode (PRD §15.22):** ZERO `new-session` calls; a `select-window` is
  issued; no creation (session count unchanged). (Known MVP limitation — FINDING
  8 — documented: restore keep's STEP-2 re-selects ORIG_WINDOW in window mode;
  out of scope, restore.sh is immutable.)
- **No off-limits work:** the `cancel)` seam stays `return 0` (T4 owns it); the
  `type`/`backspace`/`next-session`/`prev-session)` branches + `*) return 0`
  default are byte-identical; `restore.sh` / `filter.sh` / `state.sh` /
  `options.sh` / `preview.sh` are UNCHANGED.

## User Persona (if applicable)

**Target User**: None directly (confirm is an internal key-handler invoked by
tmux's `livepicker` key table). Transitively: the end user picking a session/window
(PRD §3: "I press Enter and I'm there — one switch, my session history stays clean").
T3.S1 makes the "I press Enter and I'm there" sentence literally true — and, just
as importantly, makes the "my session history stays clean" promise hold, because
confirm is the ONE place a `switch-client` is allowed.

**Use Case**: The picker is active; the user has browsed/narrowed to a candidate
(via `type`/`backspace`/nav — COMPLETE) and the live preview is showing it. The
user presses `Enter` (the `@livepicker-confirm-keys` default) to commit.

**User Journey** (T3.S1 scope — one Enter press):
1. …activate (P1.M4) saved state, built the list, grew the status bar, switched
   `key-table` to `livepicker`, ran the first preview, set `@livepicker-mode on`.
   The user typed/erased a query (T1/T2) and/or navigated (T2) to the desired
   highlight; `preview.sh` has linked the highlighted session's window live into
   the **driver** (tracked in `@livepicker-linked-id`).
2. The user presses `Enter`.
3. **T3.S1 (this task):**
   - tmux looks up `Enter` in the `livepicker` table → `run-shell
     "$CURRENT_DIR/input-handler.sh confirm"`.
   - `input_main` → `case "$action" in confirm) ...`.
   - Re-filter `@livepicker-list` by `@livepicker-filter` via the shared
     `lp_build_filtered` → `target = filtered[index]`.
   - target present, session mode → `_confirm_land_on_session "$target"`:
     **unlinks the driver's preview window first** (FINDING 1/2), then
     `switch-client -t "=target"` (the ONE switch), then `restore.sh keep`
     (tears down the picker; does NOT switch again).
4. The client is now on the target; the status bar is back to normal; the livepicker
   key table is gone; the picker `@livepicker-*` state is cleared. History has one
   new entry (or zero if the user confirmed their own session).

**Pain Points Addressed**:
- (a) **Dead Enter key.** Without this branch, Enter is bound to `return 0` —
  pressing it does nothing. T3.S1 makes Enter the commit action.
- (b) **Session destruction (the FINDING 1/2 bug).** A naive "switch then restore
  keep" makes `restore.sh`'s STEP-1 unlink the target session's OWN window and
  silently destroy it (the user sees the chosen session vanish). T3.S1 unlinks the
  driver's preview window BEFORE switching, so restore's redundant STEP-1 unlink
  targets a singly-linked origin and fails harmlessly.
- (c) **Client stranding on a sanitized name (FINDING 4/5).** A naive
  "new-session rc==0 → switch to =$query" strands the client when tmux silently
  sanitizes the name (`.hidden`→`_hidden`, `:`→`_`); the switch fails and restore
  keep tears down around a stranded client. T3.S1 gates on `new-session && has-session -t "=$query"`.
- (d) **Session-history pollution.** Any branch that accidentally issues a second
  `switch-client` would add a spurious history entry. T3.S1 issues exactly one
  switch (the helper), and `restore.sh keep` issues zero (PRD §14).

## Why

- **PRD §6 "Confirm"** is the controlling spec (verbatim): "Resolve the target
  from the filtered list at the current index. If a target exists:
  `switch-client -t "=target"`. One switch. This is the only session switch in
  the whole flow. If the filtered list is empty, the type is `session`, and
  `@livepicker-create` is on: create `new-session -d -s "<query>"`, then
  `switch-client` to it. If creation fails (invalid name), cancel instead. If the
  type is `window`: `select-window -t "<session>:<window>"`. No new session
  creation in window mode. Then run `restore.sh keep`."
- **PRD §4 "The core rule"** + **PRD §14 "Pollution"** + **Invariant A**
  (system_context §3): browsing must NEVER fire `client-session-changed`; the
  ONLY `client-session-changed` in the whole flow is confirm's single
  `switch-client`, treated by the history engine as exactly one navigation (or
  zero, deduped, on a same-session switch — FINDING 7). T3.S1 is the embodiment
  of that invariant.
- **PRD §15.22 "Create-on-enter"** governs the create branch: "Session mode, no
  match, Enter: session created and active. `@livepicker-create off`: nothing
  created. Window mode: nothing created."
- **Work-item §1 (verified invariant A)**: "this issues the ONLY switch-client in
  the whole flow… exact-match `=target`… on an invalid name [new-session] fails →
  cancel… After a successful target resolve/creation: call restore.sh keep
  (tears down the picker but LEAVES the client on the chosen target — restore keep
  does NOT switch)."
- **Scope cohesion.** T3.S1 is the commit counterpart of: activate T4.S1 (bound
  `run-shell "$CURRENT_DIR/input-handler.sh confirm"`), activate T2.S1 (built
  `@livepicker-list`), the `type`/`backspace`/nav actions (T1/T2 — set
  `STATE_FILTER`/`STATE_INDEX`), `preview.sh` (P1.M3 — owns `STATE_LINKED_ID`),
  and `restore.sh` (P1.M5 — owns the teardown). The shared contract is the
  state keys (`STATE_LIST`/`STATE_FILTER`/`STATE_INDEX`/`STATE_LINKED_ID`/
  `ORIG_SESSION`) + the shared `lp_build_filtered` (T2.S1). T3.S1 reads all of
  them and writes NONE of the picker-runtime keys directly (restore clears them).
  This module (P1.M6) is the LAST functional module before P1.M7 validation —
  T3.S1 is its commit core (T4.S1 cancel is the remaining seam).

## What

**EDIT** the existing `scripts/input-handler.sh` IN PLACE. No other file is
touched. Three edits:

1. **Grow the `local` line** (line ~65) — append `pick_type query`:
   `local action char new_filter cur_filter cur_list cur_index L new_idx target pick_type query`
   (`pick_type` caches `opt_type` once; `query` is the create-branch input =
   `@livepicker-filter`).
2. **Add ONE file-scope helper** `_confirm_land_on_session()` — insert it
   immediately before `input_main() {` (mirrors `preview.sh`'s `preview_fallback`
   placement). It reads `ORIG_SESSION` + `STATE_LINKED_ID` from state itself,
   **unlinks the driver's preview window BEFORE the switch** (FINDING 1/2), issues
   the single `switch-client -t "=target"`, and delegates teardown to
   `restore.sh keep`. See "Implementation Patterns" for the ready-to-paste body.
3. **Replace the `confirm)` seam** (lines ~182-189, the `confirm)\n\t\t\treturn 0\n\t\t\t;;`
   block — leave the preceding `# --- P1.M6.T3.S1 seam ---` comment block) with
   the full branch (5 decision paths). See "Implementation Patterns".

### Success Criteria

- [ ] `scripts/input-handler.sh` passes `bash -n` + `shellcheck` (only the
      existing file-level `disable=SC1091,SC2153`); tabs only; `set -u` only.
- [ ] The `local` line is grown by exactly `pick_type query`; `local -a filtered=()`
      is unchanged (reused by confirm via `mapfile`).
- [ ] `_confirm_land_on_session` is defined EXACTLY once (file scope, before
      `input_main`); it unlinks `"$ORIG_SESSION:$linked_id"` (guarded on
      `linked_id`) BEFORE `switch-client -t "=$tgt"`, then calls
      `"$CURRENT_DIR/restore.sh" keep`.
- [ ] The `confirm)` branch is fully implemented and calls `_confirm_land_on_session`
      from BOTH the session-target path and the create-success path; the window
      path calls `select-window` + `restore.sh keep`; the cancel paths call
      `restore.sh cancel`.
- [ ] The create branch uses the robust gate
      `tmux new-session -d -s "$query" && tmux has-session -t "=$query"` (NOT rc alone).
- [ ] The `cancel)` seam is still `return 0`; `type`/`backspace`/`next-session`/
      `prev-session)` + `*) return 0` + the header + the driver are byte-identical.
- [ ] The `confirm)` branch does NOT reference `$2` (FINDING 9 — confirm takes
      argv[1] only); `restore.sh`/`filter.sh`/`state.sh`/`options.sh`/`preview.sh`
      are UNCHANGED (`git diff --stat` shows only `input-handler.sh`).
- [ ] **Mock (work-item §5, `research/confirm_mock.sh`):** all 5 clusters pass —
      (a) match lands + driver cleaned + target intact + 1 entry; (b) valid create
      → created+active+1 entry; (c) create off → no creation+cancel+0 entries;
      (d) window mode → no creation+no switch; (e) sanitized name → cancel+0 entries.

## All Needed Context

### Context Completeness Check

_Pass_: A developer who has never seen this repo can implement T3.S1 from
(a) the ready-to-paste helper body + the full confirm branch in "Implementation
Patterns & Key Details"; (b) the 10 findings in `research/confirm_findings.md` —
most critically **FINDING 1/2** (the catastrophic switch-before-unlink bug + the
load-bearing fix: confirm must unlink `ORIG_SESSION:$linked_id` BEFORE
`switch-client`), **FINDING 3** (the unlink is only needed when a switch happens —
session mode + create-success; window mode + cancel leave cleanup to restore),
**FINDING 5** (the robust create gate `new-session && has-session -t "=$query"`),
**FINDING 6** (window-mode target is already `session:window_index` — no parsing),
**FINDING 7** (the history dedup — a same-session switch records zero entries),
**FINDING 8** (exact-match `=`; the window-mode STEP-2 caveat), and **FINDING 9**
(confirm takes argv[1] only); and (c) the throwaway socket-shim mock
`research/confirm_mock.sh` that seeds an isolated socket + attached client,
drives the REAL activate/preview/input-handler/restore, and asserts the 5
clusters + the FINDING 1/2 driver-cleaned regression. The INPUT dependencies
(`input-handler.sh` skeleton with the seam, `restore.sh`, `filter.sh`, `preview.sh`,
`state.sh`, `options.sh`) are ALL COMPLETE/present.

### Documentation & References

```yaml
# MUST READ — the file THIS task fills (the seam). COMPLETE (T1.S1 grew by T2.S1).
- file: scripts/input-handler.sh
  why: T1.S1 CREATED this file (type branch) ; T2.S1 added backspace/next/prev +
        the shared filter. T3.S1 EDITS IT IN PLACE: grows the local line, adds ONE
        helper, fills the confirm seam. Copy the skeleton's header/source-block/
        driver/CURRENT_DIR idiom verbatim; only the local line + helper + confirm
        branch change.
  pattern: incremental-edit (mirror how restore.sh grew across P1.M5.T1→T4);
           ONE local line; set -u inherited; tabs; driver
           input_main "$@" || exit 1 / exit 0.
  gotcha: confirm reads ONLY $1 (FINDING 9). Under set -u it MUST NOT reference $2
          (the confirm binding passes no char). The type branch still reads $2.

# MUST READ — the teardown confirm delegates to (keep vs cancel). COMPLETE (P1.M5).
- file: scripts/restore.sh
  why: confirm calls "$CURRENT_DIR/restore.sh" keep (after a switch) and cancel
        (on a no-target/create-fail). STEP-1 unlinks current_session:$linked_id —
        THIS IS THE FINDING 1/2 HAZARD: after switch-client, current_session==target,
        so restore STEP-1 would unlink-window target:$linked_id and (if singly-linked
        to target) the rc=1 protects it — but ONLY because confirm pre-unlinked the
        DRIVER. STEP-3 keep does NOT switch (the contract); cancel switches back to
        ORIG_SESSION. STEP-6 clear_all_state clears ALL picker state.
  critical: restore.sh is IMMUTABLE (P1.M5 COMPLETE). T3.S1 MUST NOT edit it. The
        fix for FINDING 1/2 lives in confirm's helper (pre-unlink the driver), NOT
        in restore. STEP-2 (select-window ORIG_WINDOW) is harmless in session mode
        (operates on the background driver) but UNDOES confirm's select-window in
        window mode (FINDING 8 — known limitation).

# MUST READ — the shared filtered-list builder (the target resolver). COMPLETE (T2.S1).
- file: scripts/filter.sh
  why: lp_build_filtered LIST FILTER — confirm re-filters @livepicker-list by
        @livepicker-filter EXACTLY as the renderer/nav do, so target == the session
        the renderer is highlighting. Already sourced by input-handler.sh (T2.S1).
  pattern: mapfile -t filtered < <(lp_build_filtered "$cur_list" "$cur_filter")
  gotcha: empty filter matches all; empty list -> filtered=() -> L=0 -> empty path.

# MUST READ — the state accessors confirm reads. COMPLETE (P1.M1.T3.S1).
- file: scripts/state.sh
  why: get_state "$STATE_LIST" "" / "$STATE_FILTER" "" / "$STATE_INDEX" "0" (reads);
        STATE_LINKED_ID + ORIG_SESSION (the helper reads these for the pre-unlink).
        readonly constants; get_state defaults make every read set -u safe.
  critical: confirm writes NONE of the runtime keys directly — restore clear_all_state
        (STEP-6) clears them. The helper unlinks a tmux WINDOW (not an option); it
        does NOT clear STATE_LINKED_ID (restore STEP-1 still reads it for its
        harmless redundant unlink).

# MUST READ — the option accessors (type + create gate). COMPLETE (P1.M1.T1.S1).
- file: scripts/options.sh
  why: opt_type() -> "session"|"window" (PRD §11; default session);
        opt_create() -> "on"|"off" (default on). confirm branches on BOTH.
  gotcha: cache opt_type in pick_type (called once at branch top) to avoid
        re-reading; opt_create is read only in the empty path.

# MUST READ — the caller contract (the Enter binding). COMPLETE (P1.M4.T4.S1).
- file: scripts/livepicker.sh
  why: activate T4.S1 bound confirm VERBATIM (research FINDING 9):
        tmux bind-key -T livepicker "$k" run-shell "$CURRENT_DIR/input-handler.sh confirm"
        (for each k in opt_confirm_keys, default Enter). argv is JUST `confirm`.
        ALSO (FINDING 6): the window-mode LIST is built as
        list-windows -a -F '#{session_name}:#{window_index}' — so a window-mode
        target is ALREADY "session:window_index" (no parsing needed).
  section: the key-table bind block (~line 215-216) + the list-build block (~line 93).

# MUST READ — preview linkage semantics (why the pre-unlink targets the DRIVER).
- file: scripts/preview.sh
  why: preview.sh links the candidate's window (-s src_id) INTO the DRIVER
        (-t "$current_session:", where current_session == ORIG_SESSION) and tracks
        it in @livepicker-linked-id. So the link LIVES IN THE DRIVER — that is why
        confirm's pre-unlink target is ORIG_SESSION:$linked_id, NOT target:$linked_id.
        unlink-window WITHOUT -k drops ONE link (source keeps the window).
  critical: COMPLETE (P1.M3); UNCHANGED. confirm does NOT call preview.sh.

# MUST READ — the empirical ground-truth for THIS task (10 findings).
- docfile: plan/001_fd5d622d3939/P1M6T3S1/research/confirm_findings.md
  why: FINDING 1/2 (the catastrophic switch-before-unlink target-destruction bug +
        the load-bearing pre-unlink-the-driver fix); FINDING 3 (pre-unlink only
        when a switch happens); FINDING 4 (new-session silently sanitizes names,
        rc=0 with a different name); FINDING 5 (the robust create gate); FINDING 6
        (window target is already session:window_index); FINDING 7 (same-session
        switch dedups to 0 entries); FINDING 8 (exact-match =; window STEP-2 caveat);
        FINDING 9 (confirm takes argv[1] only); FINDING 10 (the 5-cluster mock).
  critical: Read BEFORE writing. FINDING 1/2 is the highest-consequence finding in
        the whole task — get the unlink-before-switch order exactly right.

# MUST READ — the throwaway socket-shim validator (the 5 clusters).
- docfile: plan/001_fd5d622d3939/P1M6T3S1/research/confirm_mock.sh
  why: a self-cleaning isolated-socket harness that drives the REAL
        activate/preview/input-handler/restore with an attached client + a
        smart-dedup client-session-changed recorder (FINDING 7) and asserts the 5
        work-item clusters + the FINDING 1/2 driver-cleaned regression.
  critical: requires `script` (util-linux) for the attached-client pty. Run it to
        prove the implementation; do NOT ship it (P1.M7 owns the real harness).

# MUST READ — the PRD sections selected for this work item.
- docfile: PRD.md
  why: §6 Confirm (the spec, verbatim); §15.22 Create-on-enter (created+active /
        create off / window: nothing); §9 State saved and restored (the keep/cancel
        contract restore implements); §13 primitives (switch-client -t "=S" exact;
        new-session -d -s); §14 Pollution (exactly one switch, deduped).
  section: "§6 Behaviors / Confirm", "§15 Validation / Create-on-enter",
           "§9 State saved and restored", "§13 tmux primitives", "§14 Pollution".

# MUST READ — system ground-truth (Invariant A + shell style + history composition).
- docfile: plan/001_fd5d622d3939/architecture/system_context.md
  why: §3 INVARIANT A (the only client-session-changed is confirm's switch-client);
        §6 (the engine dedups a same-session switch -> 0 entries); §9 shell style
        (set -u ONLY; NO -e/pipefail; tabs; local for all function locals; quote
        everything).
  section: "§3 INVARIANT A", "§6 tmux-session-history composition", "§9 Shell style".
```

### Current Codebase tree

```bash
tmux-livepicker/
  PRD.md
  plugin.tmux                 # COMPLETE. Unchanged.
  plan/001_fd5d622d3939/{architecture/*.md, tasks.json, prd_snapshot.md, prd_index.txt}
  plan/001_fd5d622d3939/P1M6T1S1/{PRP.md, research/input_handler_type_findings.md}   # CREATED input-handler.sh
  plan/001_fd5d622d3939/P1M6T2S1/{PRP.md, research/backspace_nav_findings.md}        # added backspace/nav + filter.sh
  plan/001_fd5d622d3939/P1M6T3S1/{PRP.md, research/confirm_findings.md,
                                  research/confirm_mock.sh}                          # THIS
  scripts/
    options.sh   # COMPLETE. Unchanged. (opt_type/opt_create — the two config reads.)
    utils.sh     # COMPLETE. Unchanged. (tmux_* helpers; bare tmux for switch/new-session.)
    state.sh     # COMPLETE. Unchanged. (STATE_LIST/FILTER/INDEX/LINKED_ID + ORIG_SESSION.)
    filter.sh    # COMPLETE (P1.M6.T2.S1). Unchanged. (lp_build_filtered — the target resolver.)
    renderer.sh  # COMPLETE (P1.M2). Unchanged.
    preview.sh   # COMPLETE (P1.M3). Unchanged. (link direction -s src -t driver: — the
                 #   reason confirm's pre-unlink targets the DRIVER. ALSO the helper-placement
                 #   convention to mirror: preview_fallback is a file-scope helper.)
    livepicker.sh   # COMPLETE (P1.M4). Unchanged. (T4.S1 bound confirm; T2.S1 built the list.)
    restore.sh   # COMPLETE (P1.M5). UNCHANGED / IMMUTABLE. (keep/cancel teardown.)
    input-handler.sh  # COMPLETE skeleton (T1.S1) + backspace/nav (T2.S1). EDIT (this task):
                      #   grow local line; add _confirm_land_on_session helper; fill confirm)
                      #   seam. cancel seam + type/backspace/next/prev + *) stay.
  .gitignore
  # NOTE: NO test harness yet (P1.M7). Validate via research/confirm_mock.sh (throwaway).
```

### Desired Codebase tree with files to be added and responsibility of file

```bash
tmux-livepicker/
  scripts/
    options.sh        # unchanged.
    utils.sh          # unchanged.
    state.sh          # unchanged.
    filter.sh         # unchanged.
    renderer.sh       # unchanged.
    preview.sh        # unchanged.
    livepicker.sh     # unchanged.
    restore.sh        # unchanged (IMMUTABLE).
    input-handler.sh  # EDITED: local line grown (+pick_type query); ONE new file-scope
                      #   helper _confirm_land_on_session (unlink-driver-preview-BEFORE-switch
                      #   + the one switch-client + restore keep); the confirm) seam filled
                      #   (target->switch/select, empty->create-or-cancel). cancel seam + the
                      #   other branches + driver unchanged.
```

### Known Gotchas of our codebase & Library Quirks

```bash
# CRITICAL (research FINDING 1/2 — CATASTROPHIC): a naive "switch-client THEN
#   restore keep" DESTROYS the target session. restore.sh STEP-1 unlinks
#   current_session:$linked_id; after switch-client, current_session==target, so
#   it would unlink the target's OWN window. confirm's helper MUST unlink
#   "$ORIG_SESSION:$linked_id" (the DRIVER — where preview.sh put the link) BEFORE
#   switch-client. Then restore's redundant STEP-1 unlink targets target:$linked_id
#   and FAILS harmlessly (singly-linked origin -> rc=1, swallowed by restore's || true).
#   Verified live (research SCENARIO TEST A vs B). This is the whole reason the
#   helper exists and is centralized.

# CRITICAL (research FINDING 3): the driver-preview pre-unlink is ONLY needed when
#   confirm switches the client — i.e. session-target and create-success. Window
#   mode issues NO switch-client (current_session stays == driver), so restore
#   STEP-1 correctly cleans driver:$linked_id itself. The cancel paths also issue
#   no switch. NET RULE: any branch that calls switch-client pre-unlinks the driver;
#   any branch that does not leaves cleanup to restore.

# CRITICAL (research FINDING 4/5 — robust create gate): tmux new-session -d -s "$q"
#   does NOT reject special chars — it SILENTLY SANITIZES them ('.'->'_', ':'->'_')
#   and returns rc=0 with a DIFFERENT name. Checking rc alone would do
#   switch-client -t "=$q" -> rc=1 (no such session) -> the client is STRANDED and
#   restore keep tears down around it. The gate MUST be:
#       tmux new-session -d -s "$query" && tmux has-session -t "=$query"
#   BOTH rc=0 IFF the EXACT $query name now exists. (A duplicate cannot occur here:
#   if an exact-$query session existed it would be a case-insensitive match -> in
#   the filtered list -> the create branch is never reached.) Empty query ->
#   new-session rc=1 -> gate false -> cancel (short-circuit, has-session unrun).

# CRITICAL (research FINDING 6): window-mode targets are ALREADY "session:window_index"
#   tokens (livepicker.sh builds the list via list-windows -a -F
#   '#{session_name}:#{window_index}'). So the work-item "parse 'session:window'
#   from target" is satisfied by passing the WHOLE token straight to
#   select-window -t "$target". NO splitting/IFS-parsing. select-window does NOT
#   create a window and does NOT switch the client's session.

# CRITICAL (research FINDING 7 — history dedup): switch to a DIFFERENT session ->
#   client-session-changed fires -> 1 history entry (forward collapses, target at
#   tip — browser-like, PRD §14). switch to the SAME session (e.g. the user's own
#   driver is the only match) -> the hook STILL fires but the real
#   tmux-session-history engine short-circuits on [ "$to" = "$CURRENT" ] -> 0
#   entries. So "exactly 1" needs NO special-case in confirm; the engine dedups.
#   (The MOCK uses a smart-dedup recorder to model this — research/confirm_mock.sh.)

# CRITICAL (research FINDING 8 — exact-match = + the window-mode caveat):
#   switch-client -t "=S" is EXACT-match (disambiguates drive vs driver); rc=1 on
#   a missing name -> guard 2>/dev/null || true (a vanished session must not abort
#   the teardown). has-session -t "=S" likewise exact-match. CAVEAT (known MVP
#   limitation, OUT OF SCOPE): in window mode there is NO switch-client, so when
#   restore keep runs current_session==driver, and restore STEP-2 select-window
#   -t ORIG_WINDOW re-selects the driver's ORIGINAL window — UNDOING confirm's
#   select-window -t "target". So a window confirm tears down to ORIG_WINDOW, not
#   the picked window. restore.sh is immutable (P1.M5); implement the LITERAL
#   contract (select-window -t target + restore keep) and document this. The
#   work-item MOCKING for window mode asserts ONLY "no creation".

# CRITICAL (research FINDING 9 — caller contract): confirm is bound VERBATIM as
#   `run-shell "$CURRENT_DIR/input-handler.sh confirm"` — argv is JUST `confirm`,
#   NO char (unlike type). So the confirm branch reads ONLY $1. Under set -u it
#   MUST NOT reference $2 (unset -> would crash). Mirror nav/backspace (T2 FINDING 1).

# GOTCHA: the helper _confirm_land_on_session is a FILE-SCOPE function (NOT inside
#   input_main) — mirror preview.sh's preview_fallback. It has its OWN locals
#   (tgt/orig_session/linked_id) so they are NOT on input_main's local line. Define
#   it BEFORE input_main (bash needs the def before the input_main "$@" call at the
#   bottom; preview.sh puts preview_fallback before preview_main).

# GOTCHA: the helper must NOT clear STATE_LINKED_ID. restore STEP-1 reads it to do
#   its harmless redundant unlink (target:$linked_id -> rc=1 -> swallowed), and
#   STEP-6 clear_all_state clears it. The helper only issues tmux WINDOW commands
#   (unlink-window) + switch-client + restore keep; it writes NO @livepicker-* option.

# GOTCHA: mapfile -t filtered reuses the array T2.S1 declared (local -a filtered=()).
#   mapfile OVERWRITES (does not append), so reuse is safe. L/cur_index/cur_list/
#   cur_filter/target are all already on input_main's local line (T2.S1) — confirm
#   only ADDS pick_type query.

# CRITICAL: NO set -e, NO set -o pipefail (house style; system_context §9).
#   switch-client/new-session/has-session/select-window/unlink-window legitimately
#   return non-zero on edge cases (vanished session, sanitized name, singly-linked
#   window); under set -e that would abort mid-confirm and strand the picker. set -u
#   is inherited from the sourced libs — do NOT re-declare it. Guard every tmux
#   mutation with 2>/dev/null || true EXCEPT the create gate, whose rc is the signal.

# STYLE (system_context §9): indent with TABS (the case branches are TWO tabs deep:
#   one for the case body, one for the branch body). Verify with
#   `grep -Pn '^    ' scripts/input-handler.sh` (expect empty). shfmt NOT installed.
```

## Implementation Blueprint

### Data models and structure

No new data model. T3.S1 adds NO new state keys and NO new options — it reads
existing `@livepicker-*` keys via the state.sh accessors, branches on two PRD §11
config options (`opt_type`, `opt_create`), and delegates ALL teardown to
`restore.sh`. It introduces ONE pure shell helper (`_confirm_land_on_session`)
whose only state is its parameters + two state reads.

- **READ:** `@livepicker-list`, `@livepicker-filter`, `@livepicker-index` (the
  target resolver); `@livepicker-linked-id`, `@livepicker-orig-session` (the
  helper's pre-unlink); `opt_type()`, `opt_create()` (the two config branches).
- **WRITE (tmux, NOT options):** `switch-client` (once), `new-session`+`has-session`
  (the create gate), `select-window` (window mode), `unlink-window` (the driver
  pre-unlink).
- **DELEGATE:** `restore.sh keep` (after a land) / `restore.sh cancel` (otherwise).
- **WRITE (NONE to @livepicker-*):** restore's `clear_all_state` (STEP-6) clears
  all picker state. confirm writes zero `@livepicker-*` options.

The function locals: input_main's `local` line grows by `pick_type query`
(`pick_type` = cached `opt_type`; `query` = the create input = `@livepicker-filter`).
The helper has its own `local tgt orig_session linked_id`.

### Implementation Tasks (ordered by dependencies)

```yaml
Task 1: EDIT scripts/input-handler.sh — grow the local line
  - EDIT: line ~65
        BEFORE: local action char new_filter cur_filter cur_list cur_index L new_idx target
        AFTER:  local action char new_filter cur_filter cur_list cur_index L new_idx target pick_type query
  - WHY: pick_type caches opt_type() (read once; the branch + the empty-path both
        need it); query holds the create input. L/cur_list/cur_filter/cur_index/
        target/filtered are ALREADY declared (T2.S1) and reused by confirm.
  - DO NOT: touch the `local -a filtered=()` line (reused via mapfile).

Task 2: EDIT scripts/input-handler.sh — add the _confirm_land_on_session helper
  - INSERT: the helper body (see "Implementation Patterns") immediately BEFORE
        `input_main() {` (mirror preview.sh's preview_fallback placement — file
        scope, defined before the main function is called at the bottom).
  - WHY: centralizes the FINDING 1/2 fix (unlink-driver-preview-BEFORE-switch) so
        the two call sites (session-target + create-success) CANNOT diverge.
  - CONTRACT: reads ORIG_SESSION + STATE_LINKED_ID via get_state; if linked_id
        non-empty, unlink-window -t "$orig_session:$linked_id" (|| true); then
        switch-client -t "=$tgt" (|| true); then "$CURRENT_DIR/restore.sh" keep.
        Writes NO @livepicker-* option (does NOT clear STATE_LINKED_ID).

Task 3: EDIT scripts/input-handler.sh — fill the confirm) seam
  - EDIT: replace
            confirm)
                return 0
                ;;
        WITH the full branch (see "Implementation Patterns"). Leave the preceding
        `# --- P1.M6.T3.S1 seam: confirm ---` comment block in place (it describes
        the contract; optionally refresh it to point at the helper).
  - LOGIC (5 paths, PRD §6/§15.22):
        pick_type = opt_type; re-filter via lp_build_filtered -> filtered, L;
        sanitize+clamp index -> target ("" if L==0).
        if target present:
            window -> select-window -t "$target"; restore keep.
            session -> _confirm_land_on_session "$target".
        elif session AND create==on:
            query = cur_filter;
            if new-session -d -s "$query" && has-session -t "=$query":
                _confirm_land_on_session "$query".
            else: restore cancel.
        else (window OR create off): restore cancel.
  - DO NOT: reference $2 (FINDING 9); edit restore.sh/filter.sh/state.sh/options.sh/
        preview.sh; fill the cancel) seam (T4); change type/backspace/next/prev;
        add set -e; write any @livepicker-* option.

Task 4: VALIDATE (Level 1 syntax/lint + Level 2 socket-shim mock)
  - RUN: bash plan/001_fd5d622d3939/P1M6T3S1/research/confirm_mock.sh
        (self-cleaning; requires `script` for the attached-client pty). Asserts the
        5 work-item clusters + the FINDING 1/2 driver-cleaned regression.
```

### Implementation Patterns & Key Details

#### Task 2 — the `_confirm_land_on_session` helper (insert before `input_main()`; indent is ONE tab)

```bash
# _confirm_land_on_session TARGET — the shared "switch to a chosen session and
# tear down to leave the client there" sequence. Called by BOTH the session-mode
# target path and the create-on-success path in the confirm branch below.
#
# CRITICAL (research FINDING 1/2 — the catastrophic bug this helper exists to
# prevent): during browsing preview.sh linked the candidate's window into the
# DRIVER (@livepicker-orig-session), tracked in @livepicker-linked-id. restore.sh
# STEP-1 unlinks current_session:$linked_id — so if we switch-client FIRST,
# current_session becomes the TARGET and restore would unlink the target's OWN
# window and destroy the session. We therefore unlink the DRIVER's preview window
# (ORIG_SESSION:$linked_id) BEFORE the switch. restore's redundant STEP-1 unlink
# then targets target:$linked_id (a singly-linked origin) and fails harmlessly
# (rc=1, swallowed). Verified live (research SCENARIO TEST B).
#
# CRITICAL (research FINDING 3): ONLY call this from a branch that switches the
# client. Window mode and cancel issue no switch -> leave cleanup to restore.
_confirm_land_on_session() {
	local tgt="${1:-}"
	local orig_session linked_id
	orig_session="$(get_state "$ORIG_SESSION" "")"
	linked_id="$(get_state "$STATE_LINKED_ID" "")"
	# Drop the DRIVER's preview window BEFORE the switch (FINDING 1/2). unlink-window
	# WITHOUT -k removes ONE link; the source session KEEPS its window (preview.sh
	# FINDING 1). Singly-linked edge rc=1 is swallowed (preview.sh FINDING 2). Empty
	# linked_id (self-session was last previewed, or preview never ran) -> skip.
	if [ -n "$linked_id" ]; then
		tmux unlink-window -t "$orig_session:$linked_id" 2>/dev/null || true
	fi
	# The ONE session switch (PRD §4/§6/§14). exact-match = (FINDING 8); guard a
	# vanished session. Fires client-session-changed ONCE — the engine dedups a
	# same-session switch to 0 entries (FINDING 7), so no special-case is needed.
	tmux switch-client -t "=$tgt" 2>/dev/null || true
	# Tear down the picker (status/key-table/layout/hook/state) but LEAVE the client
	# on the target — keep does NOT switch again (P1.M5.T2.S1 restore contract).
	# restore STEP-1's redundant unlink (target:$linked_id) fails harmlessly; STEP-6
	# clear_all_state clears STATE_LINKED_ID + every @livepicker-* key.
	"$CURRENT_DIR/restore.sh" keep
}
```

#### Task 3 — the `confirm)` branch (indent is TWO tabs; replaces the `return 0` seam)

This REPLACES the `confirm)\n\t\t\treturn 0\n\t\t\t;;` seam (leave the preceding
`# --- P1.M6.T3.S1 seam ---` comment block). The `type`/`backspace`/`next-session`/
`prev-session)` branches above and the `cancel)` seam + `*) return 0` below stay
UNCHANGED.

```bash
		confirm)
			# --- P1.M6.T3.S1: resolve the highlighted item and LAND on it. This is
			#     the ONE branch in the whole flow that calls switch-client (PRD §4/
			#     §6/§14; Invariant A). Research FINDING 9: confirm takes argv[1]
			#     ONLY — it MUST NOT reference $2 (set -u).
			# Re-filter via the SAME function the renderer/nav use (T2.S1 shared
			# filter) so target == the session the renderer is highlighting.
			pick_type="$(opt_type)"
			cur_list="$(get_state "$STATE_LIST" "")"
			cur_filter="$(get_state "$STATE_FILTER" "")"
			mapfile -t filtered < <(lp_build_filtered "$cur_list" "$cur_filter")
			L="${#filtered[@]}"
			# Sanitize the stored index (a STRING option; mirror nav T2.S1).
			cur_index="$(get_state "$STATE_INDEX" "0")"
			[[ "$cur_index" =~ ^[0-9]+$ ]] || cur_index=0
			if [ "$L" -gt 0 ]; then
				# Clamp into range (matches the renderer's clamp; nav keeps index
				# valid — this guards a stale value after an external list shrink).
				[ "$cur_index" -ge "$L" ] && cur_index=$(( L - 1 ))
				target="${filtered[$cur_index]}"
			else
				target=""
			fi
			if [ -n "$target" ]; then
				if [ "$pick_type" = "window" ]; then
					# Window mode (PRD §6/§15.22; FINDING 6/8). target is ALREADY a
					# full "session:window_index" token (livepicker.sh builds the
					# list that way) -> pass it straight to select-window. NO
					# switch-client, NO creation, NO driver-preview unlink (FINDING
					# 3: no switch => current_session stays == driver => restore
					# STEP-1 cleans the link correctly). CAVEAT (FINDING 8, known
					# MVP limitation): restore keep's STEP-2 re-selects ORIG_WINDOW
					# in the driver, so a window confirm tears down to ORIG_WINDOW.
					# restore.sh is immutable (P1.M5 COMPLETE); this implements the
					# literal contract. The work-item MOCKING asserts only "no
					# creation".
					tmux select-window -t "$target" 2>/dev/null || true
					"$CURRENT_DIR/restore.sh" keep
				else
					# Session mode: the helper unlinks the driver preview BEFORE
					# switch-client (FINDING 1/2 — load-bearing), switches once,
					# and tears down with restore keep.
					_confirm_land_on_session "$target"
				fi
				return 0
			fi
			# Empty filtered list.
			if [ "$pick_type" = "session" ] && [ "$(opt_create)" = "on" ]; then
				query="$cur_filter"
				# Robust create gate (FINDING 4/5). new-session SILENTLY SANITIZES
				# names (':'->'_', leading '.'->'_') and returns rc=0 with a
				# DIFFERENT name, so checking rc alone would strand the client
				# (switch-client -t "=.hidden" -> rc=1, no such session). Require
				# BOTH new-session rc=0 AND the EXACT $query name to now exist
				# (has-session exact-match =). A duplicate cannot occur here: if
				# an exact-$query session existed it would be a case-insensitive
				# match -> in the filtered list -> this branch is never reached.
				# Empty query -> new-session rc=1 -> gate false -> cancel.
				if tmux new-session -d -s "$query" 2>/dev/null && tmux has-session -t "=$query" 2>/dev/null; then
					_confirm_land_on_session "$query"
				else
					# Invalid/sanitized/empty name -> cancel (PRD §6 Confirm).
					"$CURRENT_DIR/restore.sh" cancel
				fi
				return 0
			fi
			# Window mode, OR session mode with @livepicker-create off: nothing to
			# create -> cancel (PRD §6/§15.22).
			"$CURRENT_DIR/restore.sh" cancel
			return 0
			;;
```

NOTE for the implementer:
- This is an EDIT-IN-PLACE (T1.S1 created the file; T2.S1 grew it). Do NOT recreate
  it. Apply the three edits precisely; leave the rest byte-identical.
- The confirm branch reads ONLY `$1` (research FINDING 9) — never `$2`.
- `mapfile -t filtered` reuses the array declared at the top of `input_main`
  (T2.S1); `mapfile` overwrites, so reuse is safe. `L`/`cur_list`/`cur_filter`/
  `cur_index`/`target` are already on the `local` line — only `pick_type query`
  is new.
- The helper is the SINGLE owner of the FINDING 1/2 fix. Do NOT inline the
  unlink+switch sequence in the call sites (a second copy could drift and
  reintroduce the target-destruction bug). Both session-target and create-success
  call the helper.
- The create gate's `&&` is load-bearing: `new-session ... && has-session ...`.
  Do NOT split it into two `if`s or check rc alone (FINDING 4/5).
- Every tmux mutation EXCEPT the create gate is guarded `2>/dev/null || true`. The
  create gate's rc IS the signal (so it is NOT `|| true`'d) — but its failure
  falls through to `restore.sh cancel`, so a non-zero never aborts the script
  (there is no `set -e`).
- Window mode passes the WHOLE `target` token to `select-window` — do NOT split on
  `:` (FINDING 6: the token is already `session:window_index`).

### Integration Points

```yaml
EDITED FILE (the ONLY file this task modifies):
  - scripts/input-handler.sh: local line grown (+pick_type query); ONE new file-scope
        helper _confirm_land_on_session; the confirm) seam filled (5 decision paths).
        cancel seam + type/backspace/next/prev + *) + header + driver unchanged.

CALLERS (the binding that invokes confirm — COMPLETE sibling):
  - activate T4.S1 (P1.M4.T4.S1): bound `run-shell "$CURRENT_DIR/input-handler.sh
        confirm"` for each key in opt_confirm_keys (default Enter). argv = JUST `confirm`.

CONSUMERS (what confirm's branches call):
  - scripts/restore.sh keep  — teardown, leave client on target (no further switch).
  - scripts/restore.sh cancel — teardown + switch-client back to ORIG_SESSION.
  - scripts/filter.sh lp_build_filtered — the target resolver (shared w/ renderer+nav).
  - (window mode) tmux select-window directly (no script delegation).

STATE READS (this task):
  - @livepicker-list    (via get_state "$STATE_LIST" "")
  - @livepicker-filter  (via get_state "$STATE_FILTER" "")
  - @livepicker-index   (via get_state "$STATE_INDEX" "0")
  - @livepicker-linked-id   (helper only; via get_state "$STATE_LINKED_ID" "")
  - @livepicker-orig-session(helper only; via get_state "$ORIG_SESSION" "")

STATE WRITES (NONE): confirm writes ZERO @livepicker-* options. restore clear_all_state
  (STEP-6) clears them. The helper unlinks a tmux WINDOW, not an option.

CONFIG READS (this task):
  - opt_type()   -> "session"|"window" (cached in pick_type)
  - opt_create() -> "on"|"off" (read only in the empty path)

TMUX MUTATIONS (this task):
  - switch-client -t "=S"  (the ONE switch; helper; exact-match; || true)
  - new-session -d -s "$q" (create gate; rc is the signal, NOT || true'd)
  - has-session -t "=S"    (create gate; exact-match; rc is the signal)
  - select-window -t "session:window_index" (window mode; || true)
  - unlink-window -t "driver:linked_id" (helper pre-unlink; no -k; || true)

DATABASE / MIGRATIONS / ROUTES: none.
```

## Validation Loop

### Level 1: Syntax & Style (Immediate Feedback)

```bash
# Run after the edits — fix before proceeding.
bash -n scripts/input-handler.sh
shellcheck scripts/input-handler.sh
#   expect 0 findings beyond the file-level disable=SC1091,SC2153.

# Tabs-not-spaces sanity (shfmt NOT installed):
grep -Pn '^    ' scripts/input-handler.sh && echo "FAIL: 4-space indent, use tabs" || echo "OK: tabs only"

# Confirm house style (set -u only; NO -e / NO pipefail DECLARED in this file):
grep -n 'set -e\|set -o pipefail' scripts/input-handler.sh \
  && echo "FAIL: set -e/pipefail present" || echo "OK: set -u inherited only"

# local line grown by EXACTLY pick_type query (and filtered array intact):
grep -n 'local action char new_filter cur_filter cur_list cur_index L new_idx target pick_type query' scripts/input-handler.sh  # expect 1
grep -n 'local -a filtered=()' scripts/input-handler.sh   # expect 1 (unchanged)

# The helper is defined EXACTLY once (file scope, before input_main):
grep -n '_confirm_land_on_session()' scripts/input-handler.sh   # expect 1 (the definition)
grep -c '_confirm_land_on_session "' scripts/input-handler.sh   # expect 2 (session-target + create-success)

# FINDING 1/2 ordering: in the helper, unlink-window appears BEFORE switch-client:
awk '/_confirm_land_on_session\(\)/{f=1} f&&/^\}/{print; f=0} f' scripts/input-handler.sh \
  | grep -n 'unlink-window\|switch-client'   # expect unlink-window BEFORE switch-client

# The robust create gate (FINDING 4/5) — new-session && has-session on ONE line:
grep -n 'new-session -d -s "\$query" 2>/dev/null && tmux has-session -t "=\$query"' scripts/input-handler.sh  # expect 1

# Window mode passes the WHOLE target token (no IFS/: splitting) — FINDING 6:
grep -n 'select-window -t "\$target"' scripts/input-handler.sh   # expect 1 (confirm window branch)

# restore.sh keep + cancel are both called from confirm:
grep -n 'restore.sh" keep' scripts/input-handler.sh   # expect >=1 (helper; +window branch)
grep -n 'restore.sh" cancel' scripts/input-handler.sh # expect >=2 (create-fail + empty-otherwise)

# The confirm seam is GONE (replaced by the branch):
! grep -A2 '^\t\tconfirm)' scripts/input-handler.sh | grep -q 'return 0' \
  && echo "OK: confirm seam filled" || echo "FAIL: confirm still return 0"

# PRESERVED: cancel seam still return 0 (T4 owns it); default unchanged:
grep -n 'P1.M6.T4.S1 seam' scripts/input-handler.sh   # expect 1 (cancel)
grep -n '^\t\t\*)' scripts/input-handler.sh           # expect 1 (default return 0)

# confirm does NOT reference $2 (FINDING 9) — the confirm branch only:
awk '/^\t\tconfirm\)/,/^\t\t;;/' scripts/input-handler.sh | grep -n '\$2' \
  && echo "FAIL: confirm must not reference \$2" || echo "OK: confirm reads \$1 only"

# SCOPE: only input-handler.sh changed:
git diff --stat | grep -q 'restore.sh\|filter.sh\|state.sh\|options.sh\|preview.sh\|renderer.sh\|livepicker.sh' \
  && echo "FAIL: edited an off-limits file" || echo "OK: only input-handler.sh changed"
# Run from the repo root.
```

### Level 2: Socket-Shim Mock Validation — the 5 work-item clusters + the FINDING 1/2 regression

`research/confirm_mock.sh` is a self-cleaning, isolated-socket harness that drives
the REAL `livepicker.sh` (activate), `preview.sh` (to build a preview link),
`input-handler.sh` (confirm), and `restore.sh` (keep/cancel) with ONE attached
client (via `script -qec` — `switch-client`/`display-message`/`refresh-client`
all require a client) and a smart-dedup `client-session-changed` recorder
(FINDING 7). It asserts the work-item §5 clusters:

- **(a) session match** — client lands on target; **driver cleaned of the preview
  window** (the FINDING 1/2 regression — `list-windows -t driver` has no window
  with `@id == linked_id`); target still has its window (intact, not destroyed);
  exactly 1 history entry.
- **(b) create-on valid** — `clean123` created (has-session) AND active; count +1;
  1 entry.
- **(c) create-off** — NO new session; cancel; client back on driver; 0 entries.
- **(d) window mode** — ZERO new-session; no client session change.
- **(e) invalid/sanitized name** — `proj:two` → cancel; client on driver; no stray
  session; 0 entries.

```bash
# Run from anywhere (self-cleaning; requires `script` from util-linux for the pty):
bash plan/001_fd5d622d3939/P1M6T3S1/research/confirm_mock.sh
# Expected: "ALL CLUSTERS PASSED". If cluster (a) fails on "driver cleaned of
# preview", the FINDING 1/2 fix is wrong (unlink order / target) — re-read
# research/confirm_findings.md FINDING 1/2. If cluster (b)/(e) fail, the create
# gate is wrong (FINDING 4/5). If (d) creates a session, the window-mode branch
# is missing its no-creation guard.
```

### Level 3: Integration Testing (Manual / Live tmux)

```bash
# The mock (Level 2) IS the integration test (it drives the real activate→confirm→
# restore chain end-to-end on an isolated socket). For an in-session smoke test on
# the LIVE socket (optional, manual):
#   1. tmux set -g @livepicker-key L ; tmux set -g @livepicker-create on
#   2. tmux source ./plugin.tmux
#   3. Create 2-3 sessions (tmux new -d -s alpha ; tmux new -d -s beta).
#   4. prefix L -> type "be" -> Enter.
#   5. Expect: client now on beta; the livepicker status bar + key table are GONE;
#      `tmux show-options -g | grep @livepicker-mode` is empty (cleared by restore).
#   6. prefix L (tmux-session-history toggle, or your prev-session key) returns to
#      the pre-pick session (exactly one switch occurred — PRD §14 toggle-after-confirm).
```

### Level 4: Creative & Domain-Specific Validation (PRD §15.22 + §14 pollution)

```bash
# PRD §14 pollution (the core invariant) — re-affirmed by the mock's recorder:
#   a confirm on a DIFFERENT session records exactly 1 client-session-changed
#   navigation; a same-session confirm or a cancel records 0 (engine dedups).
# The mock's smart-dedup recorder (research/confirm_mock.sh) models this; the real
# tmux-session-history engine does the dedup in do_hook ([ "$to" = "$CURRENT" ]).

# PRD §15.22 Create-on-enter matrix (the mock covers all three rows):
#   session + no match + Enter        -> created + active        (cluster b)
#   session + @livepicker-create off  -> nothing created         (cluster c)
#   window mode                       -> nothing created         (cluster d)

# Hardening (optional, beyond MVP scope): fuzz the create gate with names that
# exercise tmux's sanitizer — '.', ':', leading/trailing space, control chars —
# and assert NONE strand the client (the && has-session gate catches them all).
```

## Final Validation Checklist

### Technical Validation

- [ ] Level 1 passes: `bash -n scripts/input-handler.sh` + `shellcheck` (0 new findings).
- [ ] Level 2 passes: `bash research/confirm_mock.sh` → ALL CLUSTERS PASSED.
- [ ] Tabs only; `set -u` only (NO `-e`, NO `-o pipefail`).
- [ ] `git diff --stat` shows ONLY `scripts/input-handler.sh` changed.

### Feature Validation

- [ ] **FINDING 1/2:** after a session-mode confirm, the driver has NO leftover
      preview window AND the target's window is intact (mock cluster a).
- [ ] **Exactly one switch:** a cross-session confirm = 1 history entry; same-session
      / cancel = 0 (mock recorder).
- [ ] **Create gate:** valid name → created+active; sanitized/invalid/empty → cancel,
      no stray session, client on driver (mock clusters b/e).
- [ ] **Window mode:** zero `new-session`; `select-window` issued; no creation (mock d).
- [ ] **create off / window:** cancel path taken, nothing created (mock c/d).
- [ ] restore.sh keep (after a land) / cancel (otherwise) both wired correctly.

### Code Quality Validation

- [ ] The helper `_confirm_land_on_session` is the SINGLE owner of the
      unlink-before-switch fix (called from 2 sites, no duplication).
- [ ] The create gate is `new-session && has-session -t "=$query"` (NOT rc alone).
- [ ] Window-mode target passed whole to `select-window` (no `:` splitting).
- [ ] confirm reads `$1` only (no `$2`); writes zero `@livepicker-*` options.
- [ ] The `cancel)` seam + `type`/`backspace`/`next`/`prev` + `*)` are byte-identical.
- [ ] Follows existing codebase patterns (incremental-edit, file-scope helper like
      preview_fallback, shared lp_build_filtered, restore delegation).

### Documentation & Deployment

- [ ] Code is self-documenting (every decision path comments its PRD § + FINDING).
- [ ] The known window-mode STEP-2 caveat (FINDING 8) is documented in-line.
- [ ] No new environment variables (uses `@livepicker-type` / `@livepicker-create`).

---

## Anti-Patterns to Avoid

- ❌ **Do NOT switch-client BEFORE unlinking the driver preview** (FINDING 1/2 — it
  silently destroys the target session). The helper unlinks FIRST, always.
- ❌ **Do NOT check `new-session`'s rc alone** to decide create-success (FINDING 4/5
  — tmux silently sanitizes names). Use `new-session && has-session -t "=$query"`.
- ❌ **Do NOT duplicate the unlink+switch sequence** in the call sites — centralize
  it in `_confirm_land_on_session` so it cannot drift back into the bug.
- ❌ **Do NOT split the window-mode target on `:`** (FINDING 6 — it is already
  `session:window_index`; pass the whole token to `select-window`).
- ❌ **Do NOT edit `restore.sh`** (immutable, P1.M5 COMPLETE). The FINDING 1/2 fix
  belongs in confirm, not restore.
- ❌ **Do NOT clear `STATE_LINKED_ID` in the helper** — restore STEP-1 reads it for
  its harmless redundant unlink; STEP-6 clear_all_state clears it.
- ❌ **Do NOT add `set -e`** — switch/new-session/has-session/select/unlink all
  legitimately return non-zero on edge cases; `set -e` would strand the picker.
- ❌ **Do NOT reference `$2` in the confirm branch** (FINDING 9 — confirm takes
  argv[1] only; `$2` is unset → crash under `set -u`).
- ❌ **Do NOT fill the `cancel)` seam** or touch the other branches (T4 owns cancel;
  T1/T2 own the rest).

---

**Confidence Score: 9/10** for one-pass implementation success.

The task is a pure seam-fill of ONE file with ready-to-paste code (helper + branch).
The -1 is the inherent fragility of the FINDING 1/2 ordering (the single
highest-consequence detail in the plugin) — mitigated by centralizing it in the
helper AND by the mock's explicit driver-cleaned regression assertion (cluster a),
which will catch any ordering mistake immediately. The robust create gate (FINDING
4/5) and the window-mode no-creation guard (FINDING 6/8) are similarly pinned by
mock clusters (b)/(e) and (d). All INPUT dependencies (the skeleton, restore.sh,
filter.sh, state.sh, options.sh, preview.sh) are COMPLETE.
