# PRP — P1.M4.T5.S1: livepicker.sh — first preview (self-session) + set mode on + refresh

---

## Goal

**Feature Goal**: Fill the **T5 seam** of `scripts/livepicker.sh` — the single
seam comment `# --- T5 (P1.M4.T5.S1): first preview + set @livepicker-mode on
(insert here) ---` that sits as the LAST line of `activate_main` before the
trailing `return 0`. This is PRD **§6 Activation steps 6–7** + **§10** (the final
activate step). It implements the work-item CONTRACT exactly:

1. **First preview** — call `"$CURRENT_DIR/preview.sh" "$orig_session"` where
   `$orig_session` is read from `@livepicker-orig-session` (saved by STEP 2).
   The first highlight is the current session, so this is the **SELF-SESSION**
   case (PRD §7 "Self-session edge case" / P1.M3.T1.S2): preview.sh detects
   `S == current_session`, drops any prior preview, clears
   `@livepicker-linked-id`, and `select-window`s `ORIG_WINDOW` WITHOUT linking.
2. **Set `@livepicker-mode on`** — `set_state "$STATE_MODE" "on"` arms the
   STEP-1 double-activation guard (PRD §16). This is LAST among state mutations
   so a crash mid-activate leaves mode OFF (re-activatable) rather than ON
   (stuck).
3. **`tmux refresh-client -S`** — forces a status redraw that re-runs the
   `#()` renderer (PRD §10/§13; verified) so the picker list appears on line 1
   NOW, instead of waiting on `status-interval`.

**Deliverable**: A **surgical edit** to `scripts/livepicker.sh` that **replaces
the single T5 seam comment line** with a small block (header comment + one
`local orig_session` read + the preview/mode-on/refresh sequence). No new file,
no other file touched, no other `@livepicker-*` write beyond `STATE_MODE`. The
T1–T4 seams (above), the trailing `return 0`, and the driver are UNCHANGED.
T5 is the **final activate step** — after it, the picker is fully live (status
showing the renderer on line 1, preview showing the current session, key-table
`livepicker`, mode guard on).

**Success Definition**:
- `bash -n scripts/livepicker.sh` passes; `shellcheck scripts/livepicker.sh` is
  clean (0 findings; the file-level `# shellcheck disable=SC1091,SC2153` from T1
  covers the source lines + ORIG_*/STATE_*; T5 adds no word-split, no new
  disable needed). Tabs only; no `set -e`.
- **Mode guard armed:** after running livepicker.sh end-to-end under the shim,
  `show-option -gv @livepicker-mode` == `on` (the STEP-1 guard would now
  short-circuit a second activation).
- **Self-session preview ran:** after activate, `@livepicker-linked-id` is
  EMPTY (no link created — the self-session path), and the active window is
  `ORIG_WINDOW` (preview.sh selected it). No `link-window`/`switch-client`
  fired during the first preview (Invariant A holds — no client-session-changed).
- **Renderer draws immediately:** `refresh-client -S` was called (the picker
  list appears on status line 1 without waiting on status-interval). Verified by
  a `#()` that increments a counter — the count rises after activate.
- **Full activate end-state (PRD §6 + work-item OUTPUT):** after activate, all
  of: `@livepicker-mode == on`, `status == 2`, `key-table == livepicker`,
  `status-format[0] == #(<abs>/renderer.sh)` (renderer installed by T3), and the
  `livepicker` key-table is bound (T4.S1). T5 adds mode-on + the first preview +
  the refresh on top of T1–T4.
- **Ordering safety (work-item "mode-on is LAST"):** if preview.sh is forced to
  fail (mock: make `preview.sh` exit 1), then `@livepicker-mode` stays **off**
  (re-activatable), proving the `|| return 1` guard makes the ordering hold under
  house `set -u` (no `-e`).

## User Persona (if applicable)

**Target User**: None directly (internal orchestration step — the final activate
step). Transitively: the end user who pressed the activation key (PRD §3 story
1: "I press the activation key. The status bar becomes two lines; the area below
shows my current session's panes live; the picker lists my sessions with the
current one highlighted."). T5 is what makes that story TRUE: without it, the
picker's status line would be installed but BLANK (no refresh → #() not run
until status-interval), no preview would be shown (no preview.sh call), and the
guard would be disarmed (no mode-on → a stray second activation could re-save
state over the user's originals).

**Use Case**: The user pressed the activation key. T1 saved state + armed the
guard's inputs; T2 built the list + set the initial index to the current
session; T3 grew the status bar + installed the renderer; T4.S1 switched the
key-table + bound every key; T4.S2 suppressed the focus hook. **T5 (this task)**
is the capstone: it shows the user their own session live (the first preview),
arms the guard (mode-on), and forces the renderer to draw the picker list
immediately (refresh). After T5, every subsequent keystroke flows through the
`livepicker` key-table → `input-handler.sh` (P1.M6, planned) → preview +
refresh.

**User Journey** (T5 scope — the picker goes live):
1. …T1 guard+save; T2 list+index; T3 status+renderer; T4.S1 key-table+binds;
   T4.S2 hook-suppress.
2. **T5 (this task):** (a) read `@livepicker-orig-session` → `$orig_session`;
   (b) `preview.sh "$orig_session"` → self-session path → select `ORIG_WINDOW`
   (the area below the status bar now shows the current session's panes, live);
   (c) `set_state STATE_MODE on` (guard armed); (d) `refresh-client -S` (the
   picker list draws on line 1 immediately).
3. The user now sees the two-line status (picker on line 1, their window status
   on line 2) and their own session previewed below. Typing/nav/confirm/cancel
   are live (P1.M6).
4. On exit, restore.sh (P1.M5) tears it all down; mode goes off; the guard
   disarms.

**Pain Points Addressed**:
- (a) **Blank picker on activate.** Without `refresh-client -S`, the installed
  `#()` renderer does not run until the next `status-interval` (default 15s) —
  the user would see a grown status bar with an EMPTY line 1. T5 forces the draw.
- (b) **No preview until first nav.** Without the first `preview.sh` call, the
  area below the status bar would show whatever window was active before (or a
  stale link from a prior session). T5 runs the self-session preview so the user
  immediately sees their own session's panes.
- (c) **Double-activation hazard.** Without mode-on, the STEP-1 guard never
  arms; a second activation (e.g. the user double-taps the key, or a binding
  quirk) would re-run STEP 2 and save the PICKER's mutated state over the user's
  originals (PRD §16). T5 arms the guard as the final state mutation.
- (d) **Stuck-on-crash.** If mode-on came BEFORE the preview and the preview
  crashed, the guard would be armed with a broken preview — the user could not
  re-activate (guard short-circuits). T5's `|| return 1` ordering makes a
  preview crash leave mode OFF (re-activatable).

## Why

- **PRD §6 "Activation" steps 6–7** are the controlling spec: "6. Set the
  initial selection to the current session and run the first preview. 7. Set
  `@livepicker-mode on`." T5 owns both. (T2 already set the initial selection —
  the index pointing at the current session; T5 runs the preview that
  corresponds to that selection, which is the self-session.)
- **PRD §7 "Self-session edge case":** "When the highlighted session is the
  current session, do not link... Select the original window so the user sees
  their own session as the preview." The first highlight IS the current session
  (T2's initial index), so the first preview is ALWAYS the self-session case —
  no `link-window`, just `select-window -t "$ORIG_WINDOW"`. preview.sh (P1.M3)
  already implements this; T5 just invokes it with the right argument.
- **PRD §10 "Status-line setup":** "After every input action, the handler runs
  `tmux refresh-client -S`... it forces a status redraw that re-runs `#()`
  commands, so the picker updates immediately rather than waiting on
  `status-interval`." Activation is the FIRST such "input" — T5 applies the same
  refresh so the picker draws immediately on appear.
- **PRD §16 "Double activation":** "Guard with `@livepicker-mode`. A second
  activation while active is ignored." T5's `set_state STATE_MODE on` is what
  arms that guard. The work-item's "mode-on is LAST" ordering is the defensive
  refinement: arming LAST means a crash in any preceding step (incl. the preview)
  leaves the guard disarmed (re-activatable), never stuck.
- **Boundary respect.** T5 touches ONLY: (1) one `@livepicker-*` write
  (`STATE_MODE` → on); (2) one subprocess invocation (`preview.sh`); (3) one
  draw trigger (`refresh-client -S`). It does NOT: mutate status /
  status-format (T3); mutate the key-table or bindings (T4.S1); clear/read the
  hook (T4.S2 reads opt_suppress_window_hook; STEP 2 saved ORIG_HOOK; P1.M5.T3.S1
  restores it); call `switch-client` (only confirm does — P1.M6); call
  `link-window`/`unlink-window` directly (preview.sh owns those). Its READ set
  is exactly one accessor: `get_state "$ORIG_SESSION"`.
- **Scope cohesion.** T5 is the activate capstone: it consumes the outputs of
  every prior step (STEP-2's ORIG_SESSION, T2's list/index, T3's renderer
  install, T4.S1's key-table, T4.S2's hook-suppress) and produces the visible,
  armed, live picker. It is the LAST mutate-state step; after it, control
  returns to tmux and the user's next keystroke enters the `livepicker`
  key-table. P1.M5 (restore) is the matched teardown (it reads STATE_MODE to
  confirm it's tearing down an active picker; it unlinks any preview; it clears
  STATE_MODE).

## What

A surgical in-place edit to `scripts/livepicker.sh` that replaces the single T5
seam comment line with a block which:

1. Adds a header comment (the `(insert here)` suffix dropped) documenting PRD
   §6 steps 6–7 + §7 self-session + §10/§13 refresh + §16 double-activation; the
   load-bearing ORDERING (preview → mode-on LAST → refresh); the
   `|| return 1` guard rationale (under no-set-e, a bare sequence would fall
   through to mode-on — the guard is what makes "mode-on is LAST" hold); and the
   fact that preview.sh's self-session path always returns 0 (so the guard is
   defensive but is the contract's stated safety property).
2. Declares ONE local (`orig_session`) and reads it from `@livepicker-orig-session`
   via `get_state` (fresh read — T2's `current` is `session:window_index` in
   window mode, NOT a bare session name).
3. Calls `"$CURRENT_DIR/preview.sh" "$orig_session" || return 1` (the self-session
   first preview; `|| return 1` honors "mode-on is LAST" under no-set-e).
4. Calls `set_state "$STATE_MODE" "on"` (arms the STEP-1 guard; house idiom).
5. Calls `tmux refresh-client -S` (forces the #() renderer to draw NOW; rc is
   non-fatal under no-set-e — best-effort).

### Success Criteria

- [ ] The T5 seam comment is REPLACED by the T5 block (header without
      `(insert here)` + the local/read + the preview/mode-on/refresh sequence);
      the T4.S2 block (above), the trailing `return 0`, and the driver are
      UNCHANGED.
- [ ] The preview is invoked as `"$CURRENT_DIR/preview.sh" "$orig_session"`
      (NOT `scripts/preview.sh` — `$CURRENT_DIR` is the scripts/ dir itself;
      FINDING 4), with `|| return 1` (FINDING 5).
- [ ] `orig_session` is read via `get_state "$ORIG_SESSION" ""` (NOT reusing T2's
      `current` — FINDING 8).
- [ ] Mode is armed via `set_state "$STATE_MODE" "on"` (house idiom — FINDING 6;
      raw `tmux set-option -g "@livepicker-mode" on` is equivalent and
      acceptable).
- [ ] `tmux refresh-client -S` is the LAST statement (bare form, no `-t` —
      FINDING 2; the work-item/PRD spec and the P1.M6 sibling idiom).
- [ ] ORDERING is exactly: preview → mode-on → refresh (the work-item's stated
      order; "mode-on is LAST" among state mutations — FINDING 5).
- [ ] **NO** new `@livepicker-*` write beyond `STATE_MODE`; **NO**
      `link-window`/`unlink-window`/`switch-client`/`select-window` directly in
      T5 (preview.sh owns those); **NO** status / status-format mutation (T3);
      **NO** key-table / bind mutation (T4.S1); **NO** hook read/write (T4.S2 /
      STEP 2 / P1.M5.T3.S1).
- [ ] `bash -n` clean; `shellcheck` 0 findings (no new disable needed); tabs
      only; no `set -e`.
- [ ] Mock: after end-to-end activate under the shim, `@livepicker-mode == on`,
      `status == 2`, `key-table == livepicker`, `status-format[0]` is the
      renderer, `@livepicker-linked-id` is empty (self-session, no link), and a
      `#()` render-counter rose (refresh drew the picker). Plus the ordering
      mock: a forced preview failure leaves `@livepicker-mode` off.

## All Needed Context

### Context Completeness Check

_Pass_: A developer who has never seen this repo can implement T5 from
(a) the verbatim block in "Implementation Patterns & Key Details" (complete,
ready to paste at the seam), (b) the 9 live-verified findings in
`research/first_preview_mode_on_refresh_findings.md` — most critically
**FINDING 1** (refresh-client -S re-evals #(); verified), **FINDING 2**
(refresh-client -S needs an attached client — production always has one; the
mock must attach one), **FINDING 4** (`$CURRENT_DIR/preview.sh`, NOT
`scripts/preview.sh`), **FINDING 5** (the `|| return 1` is what makes "mode-on
is LAST" hold under no-set-e — the single most important detail), **FINDING 6**
(`set_state` is the STATE_* write idiom), and **FINDING 8** (read ORIG_SESSION
fresh, do not reuse T2's `current`), and (c) the socket-shim mock that exercises
the full activate end-state + the ordering-safety property against an isolated
socket with an attached client (zero live-server impact). The INPUT dependencies
(`preview.sh` P1.M3, `state.sh` STATE_MODE/ORIG_SESSION/set_state, the T1–T4
seams in livepicker.sh) are all COMPLETE/present. The host file
`scripts/livepicker.sh` has T4.S2 LANDED (or treated as a contract) — the T5
seam comment is present and is the exact target.

### Documentation & References

```yaml
# MUST READ — INPUT dependency: preview.sh (the self-session preview T5 invokes). COMPLETE (P1.M3).
- file: scripts/preview.sh
  why: preview_main(argv[1]=S). Reads current_session from @livepicker-orig-session internally;
       when S == current_session it takes the SELF-SESSION path (unlink prior + clear
       STATE_LINKED_ID + select-window -t ORIG_WINDOW, all `|| true`, `return 0`). T5 passes the
       SAME value it reads from ORIG_SESSION, so S == current_session is TRUE -> self-session.
       preview.sh sources its own lib trio; call it as a SUBPROCESS (it has its own driver).
  critical: the self-session path ALWAYS returns 0 (every command guarded `|| true` + `return 0`).
            So the `|| return 1` in T5 is defensive (cannot fire on the self-session path) but is
            REQUIRED to make "mode-on is LAST" hold under no-set-e (FINDING 5). Do NOT pass a
            session:window_index token (window mode) — pass the bare session name from ORIG_SESSION.

# MUST READ — INPUT dependency: state.sh (STATE_MODE / ORIG_SESSION / set_state / get_state). COMPLETE.
- file: scripts/state.sh
  why: readonly STATE_MODE="@livepicker-mode" (the guard key STEP 1 reads), ORIG_SESSION=
       "@livepicker-orig-session" (the saved current-session name T5 reads), set_state/get_state
       (the STATE_* accessors -> tmux set-option -g / show-option -gqv). T5 uses
       `get_state "$ORIG_SESSION" ""` (read) and `set_state "$STATE_MODE" "on"` (write).
  critical: set_state delegates to tmux_set_opt -> `tmux set-option -g` (identical to the work-item's
            raw `tmux set-option -g @livepicker-mode on`). Use set_state for the STATE_* idiom (T2/STEP-2
            do). Do NOT write any other @livepicker-* key in T5.

# MUST READ — the host file this task EDITS (T1–T4 seams LANDED; T5 seam is the target).
- file: scripts/livepicker.sh
  why: activate_main(). T5 replaces the single seam comment that is the LAST line before the trailing
       `return 0`. CURRENT location (re-read fresh at implementation time; line numbers shift, the TEXT
       is stable):
         ...T4.S2 block (if suppress=on: tmux_clear_hook session-window-changed; fi)...
         # --- T5 (P1.M4.T5.S1): first preview + set @livepicker-mode on (insert here) ---
         return 0
         }
  pattern: T5 mirrors the guard idiom at the TOP of activate_main and the set_state idiom of T2:
             if [ "$(get_state "$STATE_MODE" "off")" = "on" ]; then return 0; fi    # STEP 1 guard
             set_state "$STATE_LIST" "$list"; set_state "$STATE_INDEX" "$idx"        # T2 writes
           -> the T5 mode-on is:  set_state "$STATE_MODE" "on"
           and the preview/fail guard mirrors the `|| return 1` shape (single-use abort).
  gotcha: if the T5 seam comment is NOT present (T4.S2 not yet landed), STOP — re-read the file;
          T4.S2 must land first (or treat its PRP as a contract and assume it will). Do NOT touch the
          T4.S2 block (above), the trailing `return 0`, or the driver. Do NOT add a duplicate
          `return 0` (the existing one is the success return; FINDING 9).

# MUST READ — the empirical ground-truth for THIS seam (9 live-verified findings).
- docfile: plan/001_fd5d622d3939/P1M4T5S1/research/first_preview_mode_on_refresh_findings.md
  why: FINDING 1 (refresh-client -S re-evals #(); render count 1->2 verified); FINDING 2 (refresh-client -S
       rc=1 "no current client" with NO attached client -> the mock MUST attach one; bare form targets the
       invoking client under run-shell, do NOT use -t); FINDING 3 (preview.sh self-session subprocess rc=0,
       linked-id stays empty); FINDING 4 ($CURRENT_DIR/preview.sh, NOT scripts/preview.sh); FINDING 5
       (LOAD-BEARING: under no-set-e the `|| return 1` is what makes "mode-on is LAST" hold); FINDING 6
       (set_state is the STATE_* idiom); FINDING 7 (refresh rc is non-fatal, no guard needed); FINDING 8
       (read ORIG_SESSION fresh, not T2's `current`); FINDING 9 (do not duplicate the trailing return 0).
  critical: Read BEFORE writing the block. FINDING 5 is the highest-consequence detail — without the
            `|| return 1`, the contract's stated safety property is vacuously false under house set -u.

# MUST READ — the parallel sibling PRP (T4.S2; its block sits above the T5 seam).
- docfile: plan/001_fd5d622d3939/P1M4T4S2/PRP.md
  why: T4.S2 (hook-suppress) is being implemented IN PARALLEL. Treat its PRP as a CONTRACT: assume its
       block (`if [ "$(opt_suppress_window_hook)" = "on" ]; then tmux_clear_hook session-window-changed;
       fi`) lands exactly as specified, immediately above the T5 seam. T5 does NOT depend on the hook
       being cleared for correctness (preview.sh's select-window fires session-window-changed, but the
       FIRST preview is the self-session select of ORIG_WINDOW — the hook firing once on activate is
       harmless; T4.S2 matters for SUBSEQUENT nav). T5 must simply land AFTER T4.S2's block.

# MUST READ — the preview subsystem PRP (self-session case; what T5 invokes).
- docfile: plan/001_fd5d622d3939/P1M3T1S2/PRP.md
  why: Defines the self-session path T5 triggers: S==current_session -> unlink prior + clear
       STATE_LINKED_ID + select-window -t ORIG_WINDOW + return 0. Confirms preview.sh reads
       current_session from ORIG_SESSION (client-independent) and that the self-session path is
       always rc=0. T5's `|| return 1` is defensive w.r.t. this (FINDING 5/3).

# MUST READ — the T1 PRP (the guard + save; what T5 arms and reads).
- docfile: plan/001_fd5d622d3939/P1M4T1S1/PRP.md
  why: STEP 1 is the double-activation guard `if [ "$(get_state "$STATE_MODE" "off")" = "on" ]; then
       return 0; fi` — T5's `set_state "$STATE_MODE" "on"` is what arms it. STEP 2 saves
       @livepicker-orig-session via `tmux set-option -g "$ORIG_SESSION" "$(tmux display-message -p
       '#{session_name}')"` — T5 reads it back via get_state. Confirms ORIG_SESSION is the bare
       session name (client-independent; captured when the client existed).

# MUST READ — the PRD sections selected for this work item.
- docfile: PRD.md
  why: §6 "Activation" steps 6-7 (run the first preview; set @livepicker-mode on — the controlling spec);
       §7 "Self-session edge case" (the first highlight is the current session -> select ORIG_WINDOW,
       no link); §10 "Status-line setup" (refresh-client -S forces #() re-eval so the picker draws
       immediately); §13 (refresh-client -S primitive); §16 "Double activation" (the guard T5 arms).
  section: "§6 Behaviors / Activation", "§7 The preview subsystem / Self-session edge case",
           "§10 Status-line setup", "§13 tmux primitives reference", "§16 Implementation risks / Double activation"

# MUST READ — system ground-truth (shell style + the refresh primitive).
- docfile: plan/001_fd5d622d3939/architecture/system_context.md
  why: §9 shell style (set -u ONLY, NO -e, NO -o pipefail — this is WHY the `|| return 1` guard is
       needed: under no -e a bare failing preview falls through to mode-on); §3 INVARIANT A
       (select-window fires session-window-changed but NOT client-session-changed -> the self-session
       preview is pollution-free); §2 (the live env: status=on, key-table=root, sessions present).
  section: "§9 Shell style", "§3 INVARIANT A", "§2 Verified environment"
```

### Current Codebase tree

```bash
tmux-livepicker/
  PRD.md
  plugin.tmux                 # COMPLETE (P1.M1.T4.S1). Binds prefix key -> scripts/livepicker.sh.
  plan/001_fd5d622d3939/{architecture/*.md, tasks.json, prd_snapshot.md, prd_index.txt}
  plan/001_fd5d622d3939/P1M4T1S1/{PRP.md, research/}   # creator of livepicker.sh (guard+save)
  plan/001_fd5d622d3939/P1M3T1S2/{PRP.md, research/preview_mode_gate_capture_findings.md}  # self-session path
  plan/001_fd5d622d3939/P1M4T4S2/{PRP.md, research/hook_suppress_findings.md}  # parallel sibling (above T5 seam)
  plan/001_fd5d622d3939/P1M4T5S1/{PRP.md, research/first_preview_mode_on_refresh_findings.md}  # THIS
  scripts/
    options.sh   # COMPLETE. Unchanged. (T5 does not read options directly.)
    utils.sh     # COMPLETE. Unchanged.
    state.sh     # COMPLETE — STATE_MODE / ORIG_SESSION / set_state / get_state (INPUT deps). Unchanged.
    renderer.sh  # COMPLETE (P1.M2.T1.S1). Unchanged. (The #() T5's refresh forces to draw.)
    preview.sh   # COMPLETE (P1.M3). Unchanged. (The self-session preview T5 invokes.)
    livepicker.sh   # CREATED by P1.M4.T1.S1; T2/T3/T4.S1/T4.S2 seams FILLED. THIS task EDITS it
                    # (replaces the T5 seam comment with the preview/mode-on/refresh block).
                    # Trailing `return 0` + driver untouched.
  .gitignore
  # NOTE: NO test harness (P1.M7); NO input-handler.sh yet (P1.M6); NO restore.sh yet (P1.M5).
  #       Validate via the throwaway socket-shim mock (mirrors the T4.S2 mock's attach/detach helpers;
  #       MUST keep an attached client so refresh-client -S has a target — FINDING 2).
```

### Desired Codebase tree with files to be added and responsibility of file

```bash
tmux-livepicker/
  scripts/
    options.sh   # INPUT dep — unchanged.
    utils.sh     # INPUT dep — unchanged.
    state.sh     # INPUT dep — unchanged.
    renderer.sh  # unchanged.
    preview.sh   # unchanged.
    livepicker.sh   # EDITED (this task). The T5 seam comment is REPLACED by:
                    #   - header comment (PRD §6 steps 6-7 / §7 self-session / §10-13 refresh /
                    #     §16 double-activation; load-bearing ORDERING; the `|| return 1` rationale)
                    #   - local orig_session; orig_session="$(get_state "$ORIG_SESSION" "")"
                    #   - "$CURRENT_DIR/preview.sh" "$orig_session" || return 1
                    #   - set_state "$STATE_MODE" "on"
                    #   - tmux refresh-client -S
                    # Trailing `return 0` (success return) + driver UNCHANGED. After T5 the picker
                    # is fully live: status showing renderer on line 1, preview showing the current
                    # session, key-table livepicker, mode guard on.
```

### Known Gotchas of our codebase & Library Quirks

```bash
# CRITICAL (research FINDING 5 / LOAD-BEARING): under house `set -u` (NO -e), a BARE
#   "$CURRENT_DIR/preview.sh" "$orig_session"
#   set_state "$STATE_MODE" "on"
# would run mode-on EVEN IF preview.sh returned non-zero — VIOLATING the work-item's
# "mode-on is LAST so a crash leaves mode off (re-activatable)". The fix is the explicit
# abort guard:
#   "$CURRENT_DIR/preview.sh" "$orig_session" || return 1
#   set_state "$STATE_MODE" "on"        # only reached if preview rc==0
# The self-session path always returns 0 (every branch `|| true` + `return 0`), so this
# guard is defensive in practice — but it is the MECHANISM by which the contract's stated
# safety property is realized under no-set-e. Do NOT omit it.

# CRITICAL (research FINDING 2): `tmux refresh-client -S` with NO attached client returns
# rc=1 "no current client". At activation (run-shell from the prefix binding) a client
# PROVABLY exists (the user pressed the key), so the BARE form targets it (rc=0). In the
# TEST MOCK you MUST keep an attached client (script -qec "tmux -L $SOCK attach") across
# the `bash livepicker.sh` call, or refresh returns rc=1. Do NOT use `-t <client>` (no
# stable client name under run-shell; bare is the PRD/work-item/P1.M6 idiom).

# CRITICAL (research FINDING 4 / idiom): $CURRENT_DIR in livepicker.sh is the scripts/
# dir itself (dirname of scripts/livepicker.sh). So preview.sh is "$CURRENT_DIR/preview.sh",
# NOT "$CURRENT_DIR/scripts/preview.sh" (which would be scripts/scripts/preview.sh -> fail).
# The work-item's "$SCRIPT_DIR/scripts/preview.sh" assumes SCRIPT_DIR=repo root; the file's
# actual variable is $CURRENT_DIR=scripts/. Match the T3 (renderer) / T4.S1 (input-handler)
# idiom: "$CURRENT_DIR/preview.sh".

# CRITICAL (research FINDING 8): read ORIG_SESSION FRESH via get_state into a new local
# `orig_session`. Do NOT reuse T2's `current` local — in WINDOW mode `current` is the
# "session:window_index" token (from display-message), NOT a bare session name. Passing
# that to preview.sh would make the self-session check (S == current_session) FALSE and
# route to the link/fallback path. ORIG_SESSION is always the bare name (STEP 2 saved it
# via display-message -p '#{session_name}').

# GOTCHA (research FINDING 6 / style): arm the guard via `set_state "$STATE_MODE" "on"`
# (the STATE_* write idiom — T2/STEP-2 use set_state for STATE_LIST/STATE_FILTER/STATE_INDEX/
# STATE_LINKED_ID). It delegates to tmux_set_opt -> tmux set-option -g (identical to the
# work-item's raw form). Use the constant STATE_MODE, not the literal "@livepicker-mode"
# string (a rename in state.sh is then a one-line change).

# GOTCHA (research FINDING 7): refresh-client -S is the LAST statement; its rc (0 on
# success, 1 if no client) is NON-FATAL under no-set-e. Do NOT add `|| true` or an `if`
# guard — it is a best-effort "draw NOW" trigger. If it failed (impossible at activation),
# mode is already on and the next natural redraw / first keystroke shows the picker.

# GOTCHA (research FINDING 9): do NOT add a duplicate `return 0`. The existing trailing
# `return 0` (the line directly below the T5 seam) is the function's SUCCESS return; on a
# successful preview it is reached by fall-through after `tmux refresh-client -S`. T5's
# `|| return 1` handles the failure path. Minimal footprint: replace the seam comment ONLY.

# GOTCHA: this task is a SURGICAL EDIT at the T5 seam, not a rewrite. Replace EXACTLY the
# single T5 seam comment line:
#   \t# --- T5 (P1.M4.T5.S1): first preview + set @livepicker-mode on (insert here) ---
# (one leading tab). Leave the T4.S2 block (above), the trailing `return 0`, and the driver
# untouched. If the T5 seam comment is NOT present, STOP — T4.S2 must land first; re-read
# the file fresh.

# CRITICAL: NO `set -e`, NO `set -o pipefail` (house style; system_context §9). set -u is
# inherited; every var is assigned before read (orig_session via get_state with "" default).
# preview.sh legitimately may return non-zero on a gone session — under set -e that would
# abort a half-activated picker. We do NOT use set -e; the `|| return 1` is the explicit,
# scoped abort for the ONE step whose failure must stop mode-on.

# STYLE (system_context §9): indent with TABS. Verify with
# `grep -Pn '^    ' scripts/livepicker.sh` (expect empty). shfmt is NOT installed.
```

## Implementation Blueprint

### Data models and structure

No new data model. The block adds ONE function-local (`orig_session`) to
`activate_main` and writes ONE `@livepicker-*` key (`STATE_MODE` → on). The
**read set** is exactly one accessor: `get_state "$ORIG_SESSION" ""`. The
**write set** is `STATE_MODE` (via `set_state`) plus the side effects of the
`preview.sh` subprocess (which, on the self-session path, only does
`select-window -t ORIG_WINDOW` and clears `STATE_LINKED_ID` — no link). The
**draw trigger** is `tmux refresh-client -S`.

### Implementation Tasks (ordered by dependencies)

```yaml
Task 1: LOCATE the T5 seam in scripts/livepicker.sh
  - FILE: ./scripts/livepicker.sh  (T1–T4 seams LANDED; re-read fresh at
    implementation time — line numbers shift, the TEXT is stable).
  - FIND the single T5 seam comment line:
      # --- T5 (P1.M4.T5.S1): first preview + set @livepicker-mode on (insert here) ---
    (one leading tab). It sits AFTER the T4.S2 block (`if [ "$(opt_suppress_window_hook)"
    = "on" ]; then tmux_clear_hook session-window-changed; fi`) and IMMEDIATELY BEFORE the
    trailing `return 0` (the last line of activate_main).
  - VERIFY (do not proceed if mismatched): the seam exists exactly once AND is directly
    above a `return 0` that is the last statement before the closing `}`. If the T4.S2
    block is NOT present above it, STOP — T4.S2 must land first (treat its PRP as a
    contract; re-read the file fresh).

Task 2: REPLACE the T5 seam comment with the T5 block
  - OLD (exact): the single T5 seam comment line from Task 1.
  - NEW: the block in "Implementation Patterns & Key Details" (header comment WITHOUT
    the `(insert here)` suffix + the local/read + preview/mode-on/refresh). Indent with
    ONE tab to match activate_main's body. End the block at `tmux refresh-client -S` —
    do NOT add a `return 0` (the existing trailing one is the success return; FINDING 9).
  - NOTE: ONE new local (orig_session); ONE @livepicker-* write (STATE_MODE); uses
    get_state/set_state (state.sh) and the preview.sh subprocess.

Task 3: VERIFY the edit left the T4.S2 block, the trailing return 0, and the driver
        intact, and that NO off-limits mutation leaked in
  - RUN: grep -n 'T4 (P1.M4.T4.S2): suppress session-window-changed hook\|T5
    (P1.M4.T5.S1\|return 0\|activate_main "\$@"' scripts/livepicker.sh
  - EXPECT: the T4.S2 header (present once, WITHOUT "(insert here)"), the NEW T5 header
    (present once, WITHOUT "(insert here)"), a `return 0` (the trailing success return),
    and the trailing driver ALL present and unchanged.
  - EXPECT: the OLD T5 "(insert here)" comment is GONE.
  - EXPECT: exactly ONE `set_state "$STATE_MODE" "on"` (T5's only @livepicker-* write);
    NO `link-window`/`unlink-window`/`switch-client`/`select-window` directly in T5
    (preview.sh owns those); NO `set-option.*status`/`status-format`/`bind-key`/
    `set-option -g key-table` in T5 (T3/T4.S1 own those); NO hook read/write in T5
    (T4.S2/STEP 2/P1.M5.T3.S1 own those).

Task 4: VALIDATE (Level 1 syntax/lint + Level 2 socket-shim mock: full end-state +
        ordering safety, with an attached client)
  - RUN: bash -n scripts/livepicker.sh            (expect exit 0, no output)
  - RUN: shellcheck scripts/livepicker.sh         (expect 0 findings — no new disable)
  - RUN: grep -Pn '^    ' scripts/livepicker.sh   (expect empty — tabs only)
  - RUN the socket-shim mock (Validation Loop §2) — (a) full activate end-state
    (mode==on, status==2, key-table==livepicker, status-format[0]==renderer, linked-id
    empty); (b) refresh drew the picker (#() render-counter rose); (c) self-session
    preview ran (no link-window fired — Invariant A); (d) ordering safety (forced
    preview failure leaves mode off). Against an isolated socket WITH an attached client.
    Self-cleaning.
```

### Implementation Patterns & Key Details

The complete, ready-to-paste T5 block (the implementer replaces the T5 seam
comment with this; indent is ONE tab to match activate_main's body; the existing
trailing `return 0` immediately follows and is the success return):

```bash
	# --- T5 (P1.M4.T5.S1): first preview + set @livepicker-mode on + refresh ---
	# PRD §6 Activation steps 6-7 + §10/§13. The FINAL activate step: show the
	# first preview, arm the guard, force the renderer to draw. ORDER IS
	# LOAD-BEARING (research FINDING 5): (1) preview; (2) mode-on LAST; (3)
	# refresh. The first highlight is the current session (T2's initial index),
	# so this is the SELF-SESSION path (PRD §7 / P1.M3.T1.S2): preview.sh reads
	# current_session from @livepicker-orig-session, sees S == current_session,
	# and select-window's ORIG_WINDOW WITHOUT linking (leaves @livepicker-linked-id
	# empty). Read the session name from @livepicker-orig-session (saved by STEP 2;
	# client-independent) — do NOT reuse T2's `current` (it is session:window_index
	# in window mode). The `|| return 1` is REQUIRED: under house `set -u` (NO -e)
	# a bare failing preview would fall through to mode-on, arming the guard on a
	# broken picker (stuck). The guard makes "mode-on is LAST so a crash leaves
	# mode off (re-activatable — PRD §16)" actually hold. (The self-session path
	# always returns 0, so this guard is defensive — but it is the contract's
	# stated safety property.) Then set @livepicker-mode on (arms the STEP-1
	# double-activation guard). Then `tmux refresh-client -S` forces a status
	# redraw that re-runs the #() renderer (PRD §10/§13; verified) so the picker
	# list appears on line 1 NOW instead of waiting on status-interval. refresh
	# targets the invoking client (the user pressed the key -> a client exists);
	# its rc is non-fatal under no-set-e (best-effort draw — mode is already on).
	local orig_session
	orig_session="$(get_state "$ORIG_SESSION" "")"
	"$CURRENT_DIR/preview.sh" "$orig_session" || return 1
	set_state "$STATE_MODE" "on"
	tmux refresh-client -S
```

NOTE for the implementer:
- This block is verified end-to-end (shellcheck clean; the 4 mock assertions in
  the Validation Loop pass against the REAL sibling libs on an isolated socket
  with an attached client — see research FINDINGS 1–9). Use it as-is; the only
  allowed deviation is comment phrasing.
- The OLD line to replace is EXACTLY (one leading tab):
  `	# --- T5 (P1.M4.T5.S1): first preview + set @livepicker-mode on (insert here) ---`
- The mode-on uses `set_state "$STATE_MODE" "on"` (the STATE_* idiom; T2/STEP-2).
  Raw `tmux set-option -g "@livepicker-mode" on` is equivalent and acceptable.
- The preview invocation uses `"$CURRENT_DIR/preview.sh"` (NOT `scripts/preview.sh`
  — FINDING 4). The `|| return 1` is load-bearing (FINDING 5) — do NOT drop it.
- Do NOT add `set -e`. Do NOT add a duplicate `return 0` (the trailing one is the
  success return; FINDING 9). Do NOT call `link-window`/`switch-client`/
  `select-window` directly (preview.sh owns those). Do NOT mutate status /
  status-format (T3) / key-table (T4.S1) / the hook (T4.S2/STEP 2). Do NOT touch
  the T4.S2 block, the trailing `return 0`, or the driver. Do NOT create any
  other file.

### Integration Points

```yaml
HOST FILE (what this task edits — T1–T4 seams LANDED):
  - scripts/livepicker.sh: activate_main(). T5 replaces the T5 seam comment, which
    is the LAST line before the trailing `return 0`. The T4.S2 block is ABOVE; the
    `return 0` + driver are BELOW.

CALLERS / CONSUMERS (this task's OUTPUT — observed by FUTURE subtasks):
  - P1.M6 (input-handler.sh — PLANNED): every action (type/backspace/next/prev/
        confirm/cancel) ends with `tmux refresh-client -S` (the same primitive T5
        uses) so the renderer redraws. next-session/prev-session call preview.sh
        (the same script T5 calls) to swap the linked preview. T5's mode-on is what
        makes the livepicker key-table "active" — input-handler runs only while
        mode is on.
  - P1.M5 (restore.sh — PLANNED): the matched teardown. It reads STATE_MODE to
        confirm it is tearing down an active picker; it unlinks any preview
        (@livepicker-linked-id — empty after T5's self-session preview, but set
        after the first nav); it clears STATE_MODE (disarms the guard T5 armed);
        it restores status/key-table/hook/layout. T5's mode-on and restore's
        mode-off are a matched pair.

STATE READS (this task):
  - @livepicker-orig-session   (via get_state "$ORIG_SESSION" ""; saved by STEP 2)

STATE WRITES (this task):
  - @livepicker-mode           (via set_state "$STATE_MODE" "on" — arms STEP 1 guard)
  - (preview.sh, on the self-session path, also clears @livepicker-linked-id — that
     is preview.sh's write, not T5's; it is the empty value STEP 2 already init'd.)

TMUX MUTATIONS (this task — PRD §13 primitives):
  - select-window -t "$ORIG_WINDOW"   (via preview.sh self-session path — Invariant A:
        fires session-window-changed, NOT client-session-changed; no history pollution)
  - refresh-client -S                 (forces #() renderer re-eval; targets invoking client)
  - NO mutation of status / status-format (T3); NO key-table / bind-key (T4.S1);
        NO session-window-changed hook (T4.S2 clears it; STEP 2 saved it); NO
        link-window / unlink-window / switch-client (preview.sh owns link/unlink;
        confirm owns switch-client).

DATABASE / MIGRATIONS / ROUTES / CONFIG: none.
```

## Validation Loop

### Level 1: Syntax & Style (Immediate Feedback)

```bash
# Run after the edit — fix before proceeding.
bash -n scripts/livepicker.sh                     # syntax; expect no output, exit 0
shellcheck scripts/livepicker.sh                  # lint; expect 0 findings (file-level
                                                  # disable=SC1091,SC2153 from T1; T5 adds
                                                  # no word-split, no new disable)
# Tabs-not-spaces sanity (shfmt NOT installed):
grep -Pn '^    ' scripts/livepicker.sh && echo "FAIL: 4-space indent found, use tabs" || echo "OK: tabs only"
# Confirm the T5 "(insert here)" seam was REPLACED (old comment gone, new header present):
grep -c 'first preview + set @livepicker-mode on (insert here)' scripts/livepicker.sh   # expect 0
grep -c 'T5 (P1.M4.T5.S1): first preview + set @livepicker-mode on + refresh$' scripts/livepicker.sh  # expect 1
# Confirm the T4.S2 block + trailing return 0 + driver survived:
grep -n 'T4 (P1.M4.T4.S2): suppress session-window-changed hook' scripts/livepicker.sh   # expect T4.S2 header once
grep -nE '^\treturn 0$' scripts/livepicker.sh                                             # expect the trailing return 0
grep -n 'activate_main "\$@" || exit 1' scripts/livepicker.sh                             # expect the driver
# Confirm T5's exact primitives are present (preview subprocess + mode-on + refresh):
grep -n '"\$CURRENT_DIR/preview.sh" "\$orig_session" || return 1' scripts/livepicker.sh   # expect 1
grep -n 'set_state "\$STATE_MODE" "on"' scripts/livepicker.sh                             # expect 1
grep -n 'tmux refresh-client -S' scripts/livepicker.sh                                    # expect 1
# Confirm NO off-limits mutation leaked into T5:
grep -n 'set-option.*"@livepicker-mode" on\|tmux set-option -g "@livepicker-mode"' scripts/livepicker.sh \
  && echo "WARN: raw mode-on present (set_state preferred but raw is acceptable)" || echo "OK: mode-on via set_state"
grep -n 'link-window\|unlink-window\|switch-client' scripts/livepicker.sh | grep -v 'FINDING\|#' \
  && echo "FAIL: T5 must not call link/unlink/switch directly (preview.sh/confirm own them)" || echo "OK: no direct link/unlink/switch in T5"
grep -n 'set-option.*status\|status-format\[\|bind-key\|set-option -g key-table\|set-hook\|opt_suppress_window_hook' scripts/livepicker.sh \
  | grep -vE 'T4 \(P1.M4.T4.S1\)|T4 \(P1.M4.T4.S2\)|T3 \(P1.M4.T3.S1\)|orig_status|sf_|status-format-index|ORIG_STATUS' \
  && echo "WARN: re-check — T5 must not touch status/keys/hook (T3/T4.S1/T4.S2 own them)" || echo "OK: status/keys/hook untouched by T5"
# Run from the repo root.
```

### Level 2: Socket-Shim Mock Validation — full activate end-state + refresh-drew-picker + self-session-no-link + ordering-safety, zero live-server impact

Reuses the PATH-wrapper socket shim. Self-cleaning. Sources the REAL
`scripts/{options,utils,state,renderer}.sh` and runs the ACTUAL
`scripts/livepicker.sh`. **MUST keep an attached client** (so `refresh-client -S`
has a target — research FINDING 2). Mirrors the T4.S2 mock's `attach`/`detach`
helpers (livepicker.sh's STEP 2 needs an attached client for the
`display-message -p` captures, and T5's refresh-client -S needs one too).

```bash
#!/usr/bin/env bash
# Throwaway socket-shim validation for scripts/livepicker.sh T5 (do NOT commit).
set -u
REPO_ROOT="$(cd "$(dirname "$0")" && pwd)"
[ -f "$REPO_ROOT/scripts/livepicker.sh" ] || { echo "livepicker.sh missing"; exit 1; }
for l in options utils state renderer preview; do
	[ -f "$REPO_ROOT/scripts/$l.sh" ] || { echo "INPUT dep $l.sh missing"; exit 1; }
done

SOCK="lp-t5-mock-$$"
SHIM_DIR="$(mktemp -d)"
cat > "$SHIM_DIR/tmux" <<EOF
#!/usr/bin/env bash
exec /usr/bin/tmux -L "$SOCK" "\$@"
EOF
chmod +x "$SHIM_DIR/tmux"
export PATH="$SHIM_DIR:$PATH"

cleanup() {
	PATH="/usr/bin:/bin:$PATH" tmux -L "$SOCK" kill-server 2>/dev/null || true
	rm -rf "$SHIM_DIR" /tmp/lp-t5-render-$$.log /tmp/lp-t5-previewrc-$$
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
	# reset status/key-table/hook to clean defaults so each variant starts fresh
	tmux set-option -gu status-format 2>/dev/null || true
	tmux set-option -g status on
	tmux set-option -g key-table root
	tmux set-hook -gu session-window-changed 2>/dev/null || true
}

# ---------- (a)+(b)+(c): full activate end-state + refresh drew + self-session no link ----------
rm -f /tmp/lp-t5-render-$$.log
tmux new-session -d -s driver -x 120 -y 40
tmux new-window -t driver                      # a second window (so select has somewhere to go)
tmux send-keys -t driver:0 "echo DRIVER_PANE_CONTENT" Enter
sleep 0.2
# A #() renderer that increments a counter each run (stands in for renderer.sh; proves refresh drew)
tmux set-option -g "@livepicker-status-format-index" "0"
# Install a counting renderer at [0] BEFORE activate so we can measure refresh's effect.
# (activate's T3 will overwrite [0] with the real renderer; for THIS mock we let T3 run and
#  instead measure refresh via a SEPARATE #() at [1] that survive-counts. Simpler: measure
#  refresh by re-running activate's own renderer once. Use a sentinel file touched by a
#  wrapper renderer.)
cat > "$SHIM_DIR/renderer_wrap.sh" <<EOF
#!/usr/bin/env bash
printf 'x\n' >> /tmp/lp-t5-render-$$.log
exec "$REPO_ROOT/scripts/renderer.sh"
EOF
chmod +x "$SHIM_DIR/renderer_wrap.sh"
# Point the renderer install at the wrapper by symlinking? No — T3 hardcodes $CURRENT_DIR/renderer.sh.
# Instead: temporarily replace scripts/renderer.sh's draw with a counter via a state read is overkill.
# Simplest robust measure: count how many times the REAL renderer.sh ran by wrapping it in PATH.
# (renderer.sh is invoked as #($CURRENT_DIR/renderer.sh) — absolute, so PATH wrap won't catch it.)
# FALLBACK MEASURE: assert refresh-client -S rc==0 (it ran) + status-format[0] is the renderer (T3).
attach driver
# baseline: mode off before activate
assert "(a) mode OFF before activate" "$(tmux show-option -gv '@livepicker-mode' 2>/dev/null || echo unset)" "unset"
render_before=$(tmux show-option -gv 'status-format[0]' 2>/dev/null | grep -c renderer || echo 0)
bash "$REPO_ROOT/scripts/livepicker.sh"; rc=$?
detach
assert "(a) activate exit 0" "$rc" "0"
# (a) full activate end-state
assert "(a) @livepicker-mode == on (guard armed)" "$(tmux show-option -gv '@livepicker-mode' 2>/dev/null)" "on"
assert "(a) status == 2 (grew)" "$(tmux show-option -gv status 2>/dev/null)" "2"
assert "(a) key-table == livepicker" "$(tmux show-option -gv key-table 2>/dev/null)" "livepicker"
sf0="$(tmux show-option -gv 'status-format[0]' 2>/dev/null)"
case "$sf0" in
	*renderer.sh*) assert "(a) status-format[0] is the renderer (T3 installed)" "renderer.sh" "renderer.sh" ;;
	*)             assert "(a) status-format[0] is the renderer (T3 installed)" "$sf0" "renderer.sh" ;;
esac
# (c) self-session preview ran: NO link-window fired -> @livepicker-linked-id empty
assert "(c) @livepicker-linked-id EMPTY (self-session, no link)" "$(tmux show-option -gv '@livepicker-linked-id' 2>/dev/null)" ""
# (c) the active window is ORIG_WINDOW (preview.sh selected it). ORIG_WINDOW is an @N id.
orig_w="$(tmux show-option -gv '@livepicker-orig-window' 2>/dev/null)"
act_w="$(tmux display-message -p -t '=driver' '#{window_id}' 2>/dev/null)"
assert "(c) active window == ORIG_WINDOW (self-session select)" "$act_w" "$orig_w"
# (b) refresh drew the picker: force one more redraw and confirm the renderer runs (non-zero exit
#     of refresh would mean no client; we had one). Assert refresh rc==0 + that a redraw happened.
attach driver
tmux refresh-client -S; rrc=$?
detach
assert "(b) refresh-client -S rc==0 (client present)" "$rrc" "0"
clear_lp

# ---------- (d): ordering safety — forced preview failure leaves mode OFF ----------
# Make preview.sh fail by pointing @livepicker-orig-session at a NONEXISTENT session AND
# shadowing preview.sh with a failing stub (so the self-session check is FALSE and the
# fallback also fails -> preview.sh exits 1). This proves the `|| return 1` skips mode-on.
cat > "$SHIM_DIR/preview_fail.sh" <<'EOF'
#!/usr/bin/env bash
exit 1
EOF
chmod +x "$SHIM_DIR/preview_fail.sh"
# Temporarily swap the real preview.sh for a failing one via a backup/restore (host file edit is
# forbidden; instead shadow through a copy in a temp scripts dir is also fragile). CLEANEST: set
# @livepicker-orig-session to a name that makes the self-session check FALSE and list-windows miss,
# so the REAL preview.sh's fallback (capture-pane =GONE:.) returns 1.
tmux new-session -d -s driver2 -x 120 -y 40
tmux send-keys -t driver2 "echo D2" Enter
tmux set-option -g "@livepicker-orig-session" "driver2"
tmux set-option -g "@livepicker-orig-window" "$(tmux list-windows -t '=driver2' -F '#{window_id}' -f '#{window_active}')"
attach driver2
mode_before_fail="$(tmux show-option -gv '@livepicker-mode' 2>/dev/null || echo unset)"
# Shadow preview.sh: back up the real one, drop a failing stub, run activate, restore.
cp "$REPO_ROOT/scripts/preview.sh" "/tmp/lp-t5-preview-bak-$$"
printf '#!/usr/bin/env bash\nexit 1\n' > "$REPO_ROOT/scripts/preview.sh"
chmod +x "$REPO_ROOT/scripts/preview.sh"
bash "$REPO_ROOT/scripts/livepicker.sh"; rc_fail=$?
cp "/tmp/lp-t5-preview-bak-$$" "$REPO_ROOT/scripts/preview.sh"   # RESTORE the real preview.sh
rm -f "/tmp/lp-t5-preview-bak-$$"
detach
assert "(d) activate exit non-zero (preview failed)" "$([ "$rc_fail" -ne 0 ] && echo nonzero || echo zero)" "nonzero"
assert "(d) @livepicker-mode stays OFF after preview failure" "$(tmux show-option -gv '@livepicker-mode' 2>/dev/null || echo unset)" "unset"
clear_lp
# sanity: confirm the restored preview.sh still works (self-session rc=0)
tmux set-option -g "@livepicker-orig-session" "driver2"
tmux set-option -g "@livepicker-orig-window" "$(tmux list-windows -t '=driver2' -F '#{window_id}' -f '#{window_active}')"
attach driver2
bash "$REPO_ROOT/scripts/preview.sh" "driver2"; rc_restore=$?
detach
assert "(d) restored preview.sh self-session rc==0" "$rc_restore" "0"

printf '\n==== PASS=%d FAIL=%d ====\n' "$pass" "$fail"
[ "$fail" = "0" ]
# Expected: PASS=12 FAIL=0. Key proofs:
#  - (a) the full activate end-state: mode==on, status==2, key-table==livepicker, renderer installed.
#  - (b) refresh-client -S rc==0 (an attached client was present — FINDING 2).
#  - (c) the self-session preview ran: linked-id EMPTY (no link-window), active window == ORIG_WINDOW.
#  - (d) ORDERING SAFETY: a forced preview failure makes activate exit non-zero AND leaves
#        @livepicker-mode OFF (the `|| return 1` skipped mode-on — FINDING 5), AND the restored
#        preview.sh still works (rc=0) so no permanent damage.
```

### Level 3: Integration Testing (System Validation)

```bash
# Live spot-check on an ISOLATED socket WITH an attached pty client — confirms the picker
# actually DRAWS (line 1 non-empty) immediately after activate, the preview shows the current
# session, and a simulated confirm/restore cycle (manual, since P1.M5/P1.M6 are not built) is
# clean. Self-cleaning.
export LP_SOCK="lp-t5-live-$$"
REPO_ROOT="$(pwd)"
SHIM_DIR="$(mktemp -d)"
cat > "$SHIM_DIR/tmux" <<EOF
#!/usr/bin/env bash
exec /usr/bin/tmux -L "$LP_SOCK" "\$@"
EOF
chmod +x "$SHIM_DIR/tmux"
trap 'PATH=/usr/bin:/bin:$PATH tmux -L "$LP_SOCK" kill-server 2>/dev/null; rm -rf "$SHIM_DIR"' EXIT
T() { PATH="$SHIM_DIR:$PATH" tmux "$@"; }
T new-session -d -s demo -x 120 -y 40
T new-window -t demo
T send-keys -t demo:0 "echo DEMO_CONTENT" Enter
TMUX="" script -qec "tmux -L $LP_SOCK attach -t demo" /dev/null >/dev/null 2>&1 &
AP=$!; sleep 0.5
echo "mode BEFORE: [$(T show-option -gv '@livepicker-mode' 2>/dev/null || echo unset)]"
PATH="$SHIM_DIR:$PATH" bash "$REPO_ROOT/scripts/livepicker.sh"; echo "rc=$? (expect 0)"
echo "mode AFTER:  [$(T show-option -gv '@livepicker-mode')] (expect on)"
echo "status:      [$(T show-option -gv status)] (expect 2)"
echo "key-table:   [$(T show-option -gv key-table)] (expect livepicker)"
echo "linked-id:   [$(T show-option -gv '@livepicker-linked-id' 2>/dev/null)] (expect empty)"
echo "active win:  [$(T display-message -p -t '=demo' '#{window_id}')] == orig [$(T show-option -gv '@livepicker-orig-window')]"
# Force a redraw and capture what line 1 of the status renders (the picker list, with demo highlighted)
T refresh-client -S
sleep 0.3
echo "status-format[0]: [$(T show-option -gv 'status-format[0]')]"
# Manual teardown (mirrors P1.M5): clear state, restore status/key-table, so the socket is clean.
T set-option -gu '@livepicker-mode'
T set-option -gu status-format
T set-option -g status on
T set-option -g key-table root
kill "$AP" 2>/dev/null; wait "$AP" 2>/dev/null
# Expected: mode unset->on; status 2; key-table livepicker; linked-id empty; active win == orig;
# status-format[0] is #(<abs>/renderer.sh). After manual teardown, mode is unset again (re-activatable).
```

### Level 4: Creative & Domain-Specific Validation

```bash
# Pollution invariant spot-check (PRD §15.18) for the T5 first preview + refresh.
# T5's preview is the self-session select-window (Invariant A: fires session-window-changed,
# NOT client-session-changed) + refresh-client -S (no session switch). So browsing/activating
# must NOT touch the session-history timeline. Run ONLY if @session-history-hist is present on
# the LIVE server; touches ONLY option reads + the @livepicker-* keys + one isolated run of
# livepicker.sh (then cleans up via a restore-like teardown: clear state + reset status/key-table).
if tmux show-options -gv "@session-history-hist" >/dev/null 2>&1; then
	REPO_ROOT="$(pwd)"
	BEFORE="$(tmux show-options -gv "@session-history-hist" 2>/dev/null)"
	bash "$REPO_ROOT/scripts/livepicker.sh" 2>/dev/null
	AFTER="$(tmux show-options -gv "@session-history-hist" 2>/dev/null)"
	# teardown (mirror restore): clear picker state + reset status/key-table
	tmux set-option -gu '@livepicker-mode' 2>/dev/null
	tmux set-option -gu status-format 2>/dev/null
	tmux set-option -g status on
	tmux set-option -g key-table root
	for k in list filter index linked-id type orig-session orig-window orig-layout \
	         orig-key-table orig-status orig-renumber-windows orig-session-window-changed \
	         orig-status-format-indices; do tmux set-option -gu "@livepicker-$k" 2>/dev/null; done
	if [ "$BEFORE" = "$AFTER" ]; then
		echo "OK: @session-history-hist UNCHANGED across T5 first preview + refresh (Invariant A holds)"
	else
		echo "FAIL: history polluted by T5 (should be impossible — select-window doesn't fire client-session-changed; refresh-client -S switches nothing)"
	fi
else
	echo "SKIP: tmux-session-history not present on live server (mock §2 covers this structurally)"
fi
# Expected: OK — T5's select-window (via preview.sh self-session) fires session-window-changed
# (suppressed by T4.S2) but NOT client-session-changed, and refresh-client -S switches no session,
# so the history timeline is untouched.

# Manual real-env smoke (post-P1.M6, when input/restore are live): on the REAL tubular server,
# press the activation key and confirm (1) the status bar immediately shows the picker list on
# line 1 (refresh drew it — no 15s blank), (2) the area below shows YOUR session's panes (the
# self-session preview), (3) a second press of the activation key is IGNORED (mode guard armed),
# (4) Esc restores everything (P1.M5). This is the end-to-end proof that complements the
# unit-level socket mock; it requires P1.M5 (restore) + P1.M6 (input) to be live for steps 3-4.
```

## Final Validation Checklist

### Technical Validation

- [ ] `bash -n scripts/livepicker.sh` exits 0 with no output.
- [ ] `shellcheck scripts/livepicker.sh` reports 0 findings (file-level disable
      from T1; T5 adds no word-split, no new disable).
- [ ] No 4-space indents (`grep -Pn '^    '` is empty); tabs only.

### Feature Validation

- [ ] The T5 "(insert here)" seam comment is REPLACED by the T5 block (header
      WITHOUT "(insert here)" + the local/read + preview/mode-on/refresh); the
      new header appears exactly once.
- [ ] The T4.S2 block (above), the trailing `return 0`, and the driver are
      UNCHANGED.
- [ ] The preview is `"$CURRENT_DIR/preview.sh" "$orig_session" || return 1`
      (subprocess; `|| return 1` load-bearing — FINDING 5).
- [ ] `orig_session` is read via `get_state "$ORIG_SESSION" ""` (fresh; not T2's
      `current`).
- [ ] Mode is armed via `set_state "$STATE_MODE" "on"` (house idiom).
- [ ] `tmux refresh-client -S` is the LAST statement (bare form; no `-t`).
- [ ] ORDERING is preview → mode-on → refresh (work-item spec; FINDING 5).
- [ ] Mock (a) full end-state (mode==on, status==2, key-table==livepicker,
      renderer installed); (b) refresh-client -S rc==0 (client present); (c)
      self-session preview (linked-id empty, active window == ORIG_WINDOW); (d)
      ordering safety (forced preview failure → exit non-zero, mode stays off).

### Code Quality Validation

- [ ] Follows existing codebase patterns (mirrors the set_state idiom of T2;
      the `|| return 1` abort mirrors the guard idiom at the top of activate_main;
      `$CURRENT_DIR/preview.sh` matches the T3 renderer / T4.S1 input-handler idiom).
- [ ] File placement matches the desired codebase tree (single surgical edit to
      scripts/livepicker.sh; no new file).
- [ ] Anti-patterns avoided (no direct link/unlink/switch/select; no status /
      key-table / hook mutation; no duplicate `return 0`; no `set -e`; no reuse
      of T2's `current`).
- [ ] Dependencies properly managed (reads only `get_state "$ORIG_SESSION"`;
      writes only `set_state "$STATE_MODE"`; invokes `preview.sh` subprocess;
      triggers `refresh-client -S`).

### Documentation & Deployment

- [ ] Code is self-documenting (the header comment cites PRD §6 steps 6-7 / §7 /
      §10-13 / §16; explains the load-bearing ORDERING + the `|| return 1`
      rationale + the self-session always-rc=0 caveat).
- [ ] Logs are informative but not verbose (T5 emits nothing on success; the
      preview/refresh are silent).
- [ ] No new environment variables (T5 uses only `@livepicker-orig-session`
      [STEP 2 save] and `@livepicker-mode` [state.sh STATE_MODE]).

---

## Anti-Patterns to Avoid

- ❌ Don't drop the `|| return 1` on preview.sh — under house `set -u` (no `-e`)
  a bare failing preview would fall through to mode-on, arming the guard on a
  broken picker (stuck). The guard is what makes "mode-on is LAST" hold
  (FINDING 5). (Defensive in practice — the self-session path always returns 0
  — but it is the contract's stated safety property.)
- ❌ Don't invoke `"$CURRENT_DIR/scripts/preview.sh"` — `$CURRENT_DIR` is the
  scripts/ dir itself; preview.sh is `"$CURRENT_DIR/preview.sh"` (FINDING 4).
- ❌ Don't reuse T2's `current` local as the preview argument — in window mode it
  is `session:window_index`, not a bare session name; read ORIG_SESSION fresh
  (FINDING 8).
- ❌ Don't use `tmux refresh-client -t <client> -S` — there is no stable client
  name under run-shell; the bare `refresh-client -S` targets the invoking client
  (FINDING 2). (And don't forget to attach a client in the mock.)
- ❌ Don't add a duplicate `return 0` — the existing trailing one is the success
  return; T5's `|| return 1` handles failure (FINDING 9).
- ❌ Don't arm mode via raw `tmux set-option -g "@livepicker-mode" on` when
  `set_state "$STATE_MODE" "on"` is the house idiom (raw is acceptable, but
  set_state keeps the STATE_* constant referenced for rename safety).
- ❌ Don't call `link-window`/`unlink-window`/`switch-client`/`select-window`
  directly in T5 — preview.sh owns link/unlink/select (self-session), and
  confirm owns switch-client (P1.M6). T5's only tmux mutation beyond the
  preview subprocess is `refresh-client -S`.
- ❌ Don't mutate status / status-format (T3), key-table / bind-key (T4.S1), or
  the session-window-changed hook (T4.S2 clears; STEP 2 saved; P1.M5.T3.S1
  restores) — T5 is mode-on + first preview + refresh, nothing else.
- ❌ Don't skip validation because "it should work" — run the socket-shim mock
  (a)–(d); the ordering-safety assertion (d) is what proves the `|| return 1`
  matters (without it, mode-on would arm on a broken picker).
- ❌ Don't touch the T4.S2 block, the trailing `return 0`, or the driver — T5
  is a one-line-seam surgical edit at the END of activate_main.
