# PRP — P1.M4.T1.S1: livepicker.sh — double-activation guard + full state save

---

## Goal

**Feature Goal**: Create `scripts/livepicker.sh` — the **activate orchestrator**
entry point that `plugin.tmux`'s prefix-key binding invokes — implementing the
**first two** of PRD §6's seven activation steps: **(1) the double-activation
guard** (if `@livepicker-mode == on`, silently `exit 0` and change nothing), and
**(2) the full save of original state** into the `@livepicker-orig-*` saved-state
CONTRACT (PRD §9) that `restore.sh` (P1.M5) later reads back. It also initializes
`@livepicker-linked-id=''` (no preview linked yet) so `preview.sh`'s duplicate
guard has a clean starting state. The file is structured as an incrementally-
extended pipeline (`activate_main()` + trailing driver) with **clearly-marked
seam comments** for the four downstream subtasks (T2 list, T3 status, T4
key-table+hook, T5 first-preview+mode-on) that will edit it in place.

**Deliverable**: The single NEW file `scripts/livepicker.sh` (executable,
`chmod +x`; shebang `#!/usr/bin/env bash`). It sources the lib trio
(`options.sh → utils.sh → state.sh`, load-bearing order), defines
`activate_main()`, and ends with the trailing driver
`activate_main "$@" || exit 1; exit 0`. **`@livepicker-mode` is NOT set on by
this task** (the contract: "set last, in P1.M4.T5.S1") — so after S1, pressing
the key performs guard → save → init-linked-id → exit, but the picker does not
visibly appear yet (no status growth / key-table switch / mode-on). The save is
independently and fully testable.

**Success Definition**:
- `bash -n scripts/livepicker.sh` passes; `shellcheck scripts/livepicker.sh` is
  clean (0 findings; a file-level `# shellcheck disable=SC1091,SC2153` silences
  the source-line + ORIG_*/STATE_* infos, mirroring preview.sh).
- `scripts/livepicker.sh` is executable (`-rwxr-xr-x`); tabs only; NO `set -e`.
- **Mock (a) save test (socket shim + pty client):** running livepicker.sh on an
  isolated socket with a client attached populates EVERY `@livepicker-orig-*`
  key to match the live value (session, window-**id**, layout, key-table=root,
  status=on, renumber-windows=on, the FULL `session-window-changed[0] … -b …`
  hook line, status-format user-set-indices=""); and sets
  `@livepicker-linked-id=""`.
- **Mock (b) guard test:** pre-setting `@livepicker-mode=on` and sentinel
  `@livepicker-orig-*` values, then running livepicker.sh, **exits 0 and leaves
  every sentinel UNCHANGED** (the guard short-circuits before the save block) —
  proving idempotent re-activation is a true no-op.
- **Mock (c) status-format trap:** on the tubular-style env (status-format
  materializes only built-in defaults [0,1,2]), the save writes
  `@livepicker-orig-status-format-indices=""` and NO per-index keys — i.e. it
  does NOT capture/replay the default strings (TRAP 1; restore will just `-gu`).

## User Persona (if applicable)

**Target User**: The tmux prefix-key binding installed by `plugin.tmux` (P1.M1.T4.S1)
→ via `run-shell`. Transitively the end user pressing `C-Space` then the
`@livepicker-key`. Mode A (internal orchestrator — no user-facing surface beyond
the side effects; the README P1.M8.T1.S1 summarizes behavior).

**Use Case**: The user presses the activation key. tmux `run-shell`s
`scripts/livepicker.sh`. The guard checks `@livepicker-mode`; on a fresh
activation it is unset/off, so the script proceeds to snapshot the user's
current session/window/layout/options/hook into the `@livepicker-orig-*`
contract, initializes the linked-preview id to empty, and (in later subtasks)
goes on to build the picker. If the user somehow triggers activation while a
picker is already active (e.g. a second binding, a race), the guard silently
ignores it — no double-save, no corrupted state.

**User Journey** (S1 scope — the picker does not yet appear; this is the
foundation the later subtasks build on):
1. User presses `C-Space` then `Space` (the `@livepicker-key`).
2. `plugin.tmux`'s binding runs `scripts/livepicker.sh` via `run-shell`.
3. `activate_main()` reads `@livepicker-mode` → unset → "off" → proceeds.
4. Saves session=`#{session_name}`, window=`#{window_id}` (@id, not index),
   layout=`#{window_layout}`, key-table, status, renumber-windows, the FULL hook,
   and status-format (trap-aware) into `@livepicker-orig-*`; inits
   `@livepicker-linked-id=""`.
5. [T2–T5 seam comments mark where later subtasks insert list/status/keys/preview/mode-on.]
6. `return 0` → driver `exit 0`. (After S1: no visible picker yet — by design.)

**Pain Points Addressed**:
- (a) **Double-activation corruption.** Without the guard, a second activation
  mid-picker would re-save the *picker's* state (the livepicker key-table, the
  grown status, the linked preview) over the user's true originals — making
  restore (P1.M5) restore the picker's state instead of the user's. The guard is
  the cheap, load-bearing fence (PRD §16: "Guard with `@livepicker-mode`").
- (b) **Drifting save/restore key names.** The `@livepicker-orig-*` names are an
  integration seam shared by activate (M4) and restore (M5). state.sh (P1.M1.T3.S1)
  already named them as `readonly` constants (`ORIG_SESSION`, …); this task
  writes through those constants, so a typo is caught at `set -u`/shellcheck time.
- (c) **The status-format trap (TRAP 1).** A naive save that captures and replays
  the default `status-format[0..2]` strings fights tubular and is fragile. This
  task delegates to `state_status_format_save`, which stores ONLY genuinely
  user-set indices (≥3) and lets restore do the `-gu` reset.
- (d) **Window-restore correctness.** `renumber-windows on` makes indices
  unstable. Capturing `#{window_id}` (the stable @id) instead of
  `#{window_index}` is what lets restore's `select-window -t "$ORIG_WINDOW"`
  land on the exact original window.

## Why

- **The activation seam, started.** This is the first subtask of P1.M4 (Activate
  orchestration). PRD §5 data flow: `plugin.tmux → binds prefix → scripts/livepicker.sh`.
  Until livepicker.sh exists, the prefix key binding points at nothing. S1 creates
  the file and lands the two steps that must happen *first and unconditionally*
  on every activation: the guard, and the save. Everything downstream (T2 list,
  T3 status, T4 keys, T5 preview+mode-on) is inserted *after* the save.
- **The guard is load-bearing and cheap.** PRD §6 step 1 + §16 ("Double
  activation. Guard with `@livepicker-mode`. A second activation while active is
  ignored."). The guard is a single `get_state` read + a `return 0`; it prevents
  the catastrophic re-save-over-picker-state bug. It is the first statement of
  `activate_main` so it short-circuits before ANY mutation.
- **The save is the restore contract's writer.** PRD §9 enumerates exactly what
  is saved; restore (P1.M5.T3.S1) reads it back in order. Getting the save right
  now (every key, correct capture primitive, the `-gu`-compatible status-format
  treatment) unblocks four downstream milestones (M4.T2–T5, M5) with a stable,
  tested writer.
- **Boundary respect.** livepicker.sh touches ONLY the `@livepicker-orig-*`
  saved-state keys + `@livepicker-linked-id` (init to ""). It does NOT set
  `@livepicker-mode` (T5), does NOT touch the list/filter/index, does NOT grow
  status / switch key-table / suppress the hook / run a preview (T2–T5). It calls
  only: `display-message -p`, `show-option -gqv` (via `tmux_save_opt`),
  `show-hooks -g` (via `tmux_get_hook`), `set-option -g` (via `set_state` /
  `tmux_set_opt` / direct), and `state_status_format_save`. No `switch-client`,
  no `select-window`, no `link-window`, no `set-hook`/`set-hook -gu`, no
  `bind-key`, no `refresh-client`.

## What

A single NEW executable Bash entry point at `scripts/livepicker.sh` that:

1. Computes `CURRENT_DIR` via the canonical sibling idiom; sources the lib trio
   in load-bearing order (`options.sh → utils.sh → state.sh`).
2. Defines `activate_main()`:
   - **STEP 1 — guard (PRD §6.1):** `if [ "$(get_state "$STATE_MODE" "off")" = "on" ]; then return 0; fi`
     (silent short-circuit; the driver's `exit 0` produces the silent exit).
   - **STEP 2 — save (PRD §6.2 / §9):** capture each saved item via the correct
     primitive (see the summary table in research FINDING 8) into its `ORIG_*`
     constant; call `state_status_format_save` for the status-format array; init
     `@livepicker-linked-id=""` via `set_state`.
   - **T2–T5 seam comments** (no-op placeholders) marking where later subtasks
     insert their steps.
   - `return 0`.
3. Trailing driver: `activate_main "$@" || exit 1; exit 0`.

### Success Criteria

- [ ] `scripts/livepicker.sh` EXISTS, executable (`-rwxr-xr-x`), shebang
      `#!/usr/bin/env bash`; `set -u`, **NO** `set -e`, NO `set -o pipefail`.
- [ ] Sources `options.sh`, `utils.sh`, `state.sh` via resolved `$CURRENT_DIR`
      in THAT order (state.sh needs utils.sh — its own header says so).
- [ ] `activate_main()` defined; guard is its FIRST statement; `return 0` on
      `@livepicker-mode == on`.
- [ ] Save writes (via `tmux set-option -g "$ORIG_X" "$(…)"` for the three
      display-message captures; via `tmux_save_opt` for key-table/status/
      renumber-windows; via `tmux_get_hook` for the hook; via
      `state_status_format_save` for status-format):
      `ORIG_SESSION`, `ORIG_WINDOW` (window **id**), `ORIG_LAYOUT`,
      `ORIG_KEY_TABLE`, `ORIG_STATUS`, `ORIG_RENUMBER`, `ORIG_HOOK` (FULL
      `show-hooks` line), and the status-format user-set list/indices.
- [ ] `@livepicker-linked-id` initialized to `""` via `set_state "$STATE_LINKED_ID" ""`.
- [ ] **NO** `set-option -g "@livepicker-mode" on` anywhere in S1 (T5's job).
- [ ] T2–T5 each have a clearly-marked seam comment (so the later edits are
      unambiguous) but contain NO logic.
- [ ] Trailing driver `activate_main "$@" || exit 1; exit 0` present.
- [ ] `bash -n` clean; `shellcheck` 0 findings (file-level disable for SC1091
      + SC2153, mirroring preview.sh); tabs only.
- [ ] Mock (a) save: every `@livepicker-orig-*` matches the live value; linked-id="".
- [ ] Mock (b) guard: mode=on → exit 0, all sentinels unchanged, linked-id unchanged.
- [ ] Mock (c) status-format trap: indices="" and no per-index keys on the tubular env.

## All Needed Context

### Context Completeness Check

_Pass_: A developer who has never seen this repo can implement S1 from
(a) the verbatim file body in the Implementation Blueprint (complete, ready to
paste), (b) the 8 live-verified findings in
`research/activate_guard_save_findings.md` — most critically FINDING 2 (the hook
output format: single `[0]` index, `-b`, abs path; `show-hooks` exits 0 set OR
cleared), FINDING 3/4 (status-format materializes only defaults [0,1,2]; the
`tmux_is_set` probe is useless for it → delegate to `state_status_format_save`),
and FINDING 5 (`display-message -p` needs a client; capture `#{window_id}` NOT
`#{window_index}`), and (c) the socket-shim mock that exercises save + guard
against an isolated server with a pty client attached (zero live-server impact).
The INPUT dependencies (`options.sh`, `utils.sh`, `state.sh`) are all COMPLETE
and their function/constant signatures are fixed and quoted below. This is a
single-file greenfield entry point, structurally a strict subset of the
preview.sh function+driver pattern (P1.M3.T1.S1).

### Documentation & References

```yaml
# MUST READ — INPUT dependency: utils.sh (the save primitives). COMPLETE (P1.M1.T2.S1).
- file: scripts/utils.sh
  why: Defines the save primitives this task calls. tmux_save_opt(orig,src) ->
       read src via show-option -gqv, write @livepicker-orig-${orig} (use for
       key-table/status/renumber-windows where orig==src). tmux_get_hook(hook) ->
       FULL raw show-hooks output (use for session-window-changed). tmux_set_opt/
       tmux_unset_opt/tmux_get_opt/tmux_is_set also present (the last NOT used here
       — FINDING 4: useless for status-format). Begins with `set -u`, NO -e.
  critical: tmux_save_opt's orig_name MUST be bracket-free (tmux rejects '[' in
            @-names -> "not an array"). All ORIG_* constants from state.sh ARE
            bracket-free, so pass them verbatim. Do NOT invent a bracketed @-name.

# MUST READ — INPUT dependency: state.sh (the saved-state CONTRACT). COMPLETE (P1.M1.T3.S1).
- file: scripts/state.sh
  why: Defines the readonly ORIG_* / STATE_* constants (the integration seam this
       task WRITES and restore P1.M5 READS), set_state/get_state accessors, AND the
       trap-aware state_status_format_save() / state_status_format_restore() pair.
       This task calls state_status_format_save() for the status-format array
       (FINDING 3/4: it enumerates the bulk dump, keeps only indices>=3, stores the
       user-set list — in this env empty — so restore's -gu reset is correct).
  critical: ORIG_SESSION/WINDOW/LAYOUT/KEY_TABLE/STATUS/RENUMBER/HOOK +
            ORIG_STATUS_FORMAT_INDICES + ORIG_STATUS_FORMAT_PREFIX are the EXACT
            key names; write through these constants only. STATE_MODE="@livepicker-mode"
            (the guard read), STATE_LINKED_ID="@livepicker-linked-id" (init to "").

# MUST READ — INPUT dependency: options.sh (sourced first; provides get_opt/opt_*).
- file: scripts/options.sh
  why: Defines get_opt + the opt_* accessors. livepicker.sh sources it FIRST
       (before utils.sh, before state.sh) — the load-bearing source order. This
       task does not call any opt_* directly in S1 (config is read by later
       subtasks: opt_type T2, opt_suppress_window_hook T4, opt_preview_mode T5),
       but sourcing it is required because state.sh/utils.sh assume the trio is
       present and it establishes `set -u`.
  critical: Sourcing options.sh activates `set -u` for the rest of the script.
            Every variable livepicker.sh reads must be assigned first (it is).

# MUST READ — the empirical ground-truth for THIS file (8 live-verified findings).
- docfile: plan/001_fd5d622d3939/P1M4T1S1/research/activate_guard_save_findings.md
  why: FINDING 1 (live env: key-table=root, status=on, renumber-windows=on);
       FINDING 2 (hook output: "session-window-changed[0] run-shell -b <abs path>";
       show-hooks exits 0 set-or-cleared; multi-line ok in @-options); FINDING 3
       (status-format materializes [0,1,2] defaults, none>=3 user-set -> empty
       user list -> restore is just -gu); FINDING 4 (tmux_is_set rc=0 for
       status-format[n] USELESS, rc=1 for unset @-options WORKS); FINDING 5
       (display-message -p resolves session_name/window_id=@N/window_layout WITH a
       client; window_id NOT index); FINDING 6 (bracket gotcha re-confirmed);
       FINDING 7 (guard: mode==on -> silent exit 0 BEFORE any mutation; mode NOT
       set on by S1); FINDING 8 (file structure: entry-point + activate_main() +
       driver; T2-T5 inserted via seam comments like preview.sh S1->S2).
  critical: Read BEFORE writing the save block. FINDING 5 (window_id not index)
            and FINDING 2/3 (hook/status-format treatment) are the highest-
            consequence details.

# MUST READ — the closest structural analog: preview.sh (function + driver + seam comments).
- file: scripts/preview.sh
  why: preview.sh (P1.M3.T1.S1 -> S2) established the EXACT pattern livepicker.sh
       mirrors: shebang + file-level shellcheck disable; CURRENT_DIR idiom; source
       trio (options/utils/state); a _main() function; trailing
       `<name>_main "$@" || exit 1; exit 0` driver; and marked seam comments
       ("# --- S2: insert ... ---") that let a later subtask edit in place. preview.sh
       is the template for "entry-point script extended across subtasks". Copy its
       shape; swap preview_main for activate_main and the seams for T2-T5.
  pattern: |
    CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    source "$CURRENT_DIR/options.sh"; source utils.sh; source state.sh
    activate_main() { …; return 0 }
    activate_main "$@" || exit 1
    exit 0
  gotcha: preview.sh ends each command with `2>/dev/null || true` where the tmux
          call legitimately fails (unlink/list-windows). livepicker.sh's save calls
          do NOT need that — display-message/show-hooks/show-option succeed on the
          happy path; but do NOT add `set -e` (a transient failure must not abort
          the whole activate silently).

# MUST READ — the PRD sections selected for this work item (activation + state + risks).
- docfile: PRD.md
  why: §6 Activation steps 1-2 (guard + save — the literal spec this task
       implements); §9 State saved and restored (the EXACT save list: session,
       window id, window_layout, key-table, status + every status-format[n],
       renumber-windows, session-window-changed hook, linked-id initially empty);
       §16 Implementation risks (Double activation -> guard with @livepicker-mode;
       Window addressing -> use ids not indices; Hook suppression scope -> restore
       the -b flag — a RESTORE concern, but the SAVE must capture the full line);
       §5 Architecture/data flow (plugin.tmux -> livepicker.sh is the top).
  section: "§6 Behaviors -> Activation (steps 1-2)", "§9 State saved and restored",
           "§16 Implementation risks and notes (Double activation, Window addressing)",
           "§5 Architecture / Data flow"

# MUST READ — system ground-truth (shell style + live env + the two traps).
- docfile: plan/001_fd5d622d3939/architecture/system_context.md
  why: §2 (verified env: status=on, key-table=root, renumber-windows=on, the exact
       session-window-changed[0] hook line, status-format as defaults); §4 TRAP 1
       (status-format restore MUST be -gu, not literal replay) + TRAP 2 (hook is
       array-indexed with -b; save the WHOLE show-hooks line); §9 shell style
       (shebang, set -u only NO -e, tabs, CURRENT_DIR idiom, quote everything);
       §7 (test-harness reality: the PATH-wrapper socket shim — the mock reuses it).
  section: "§2 Verified environment", "§4 Two environment-specific traps",
           "§9 Shell style", "§7 Test harness reality"

# MUST READ — the entry-point that BINDS this script (so the path/invocation is clear).
- docfile: plan/001_fd5d622d3939/P1M1T4S1/PRP.md
  why: plugin.tmux binds `tmux bind-key "$KEY" run-shell "$CURRENT_DIR/scripts/livepicker.sh"`
       (prefix table). So livepicker.sh is invoked via `run-shell` with NO argv from
       the binding. The trailing driver's `"$@"` is therefore empty in practice
       (harmless; kept for parity with preview.sh and manual invocation).
  section: "What" (the bind line), "Integration Points -> BIND TARGET"
```

### Current Codebase tree

```bash
tmux-livepicker/
  PRD.md
  plugin.tmux                 # (P1.M1.T4.S1) ENTRY POINT — COMPLETE. Binds prefix key -> scripts/livepicker.sh.
  plan/001_fd5d622d3939/{architecture/*.md, tasks.json, prd_snapshot.md, prd_index.txt}
  plan/001_fd5d622d3939/P1M4T1S1/{PRP.md, research/activate_guard_save_findings.md}  # THIS
  scripts/
    options.sh   # EXISTS (COMPLETE) — get_opt + opt_* (incl opt_type/opt_suppress_window_hook/opt_preview_mode for LATER subtasks).
    utils.sh     # EXISTS (COMPLETE) — tmux_save_opt / tmux_get_hook / tmux_set_opt / tmux_get_opt. THIS task's save primitives.
    state.sh     # EXISTS (COMPLETE) — ORIG_*/STATE_* constants, set_state/get_state, state_status_format_save. THE CONTRACT.
    renderer.sh  # EXISTS (P1.M2.T1 — COMPLETE). Unchanged by this task.
    preview.sh   # EXISTS (P1.M3.T1.S1 + S2 in parallel). Unchanged by this task. Structural TEMPLATE for livepicker.sh.
    # livepicker.sh  # ← DOES NOT EXIST YET (this task CREATES it).
  .gitignore
  # NOTE: NO test harness (P1.M7). Validate via the socket-shim throwaway mock (+ pty client).
```

### Desired Codebase tree with files to be added and responsibility of file

```bash
tmux-livepicker/
  scripts/
    options.sh   # INPUT dep — unchanged.
    utils.sh     # INPUT dep — unchanged.
    state.sh     # INPUT dep — unchanged.
    renderer.sh  # unchanged.
    preview.sh   # unchanged (parallel S2 may edit it; this task does not).
    livepicker.sh   # NEW (this task). ENTRY POINT (run-shell from prefix binding).
                    #   activate_main(): STEP1 guard (@livepicker-mode==on -> return 0);
                    #   STEP2 save (session/window-id/layout/key-table/status/renumber/
                    #   hook/status-format into @livepicker-orig-*; init linked-id="");
                    #   T2-T5 seam comments; return 0. Trailing driver. chmod +x.
                    #   Does NOT set @livepicker-mode on (T5's job).
```

### Known Gotchas of our codebase & Library Quirks

```bash
# CRITICAL (research FINDING 5): capture window via '#{window_id}' (the @N token),
# NOT '#{window_index}'. renumber-windows is ON (system_context §2), so numeric
# indices are unstable — restore's select-window -t "$ORIG_WINDOW" would land on the
# WRONG window after any renumber. window_id (@N) is the stable handle. Verified
# live: window_id=@40. The PRD §9 / work-item contract explicitly say "window id".

# CRITICAL (research FINDING 2 + TRAP 2): save the FULL `show-hooks -g
# session-window-changed` output VERBATIM into ORIG_HOOK — do NOT parse/strip it
# at save time. The live value is a single line
#   "session-window-changed[0] run-shell -b /home/dustin/.config/tmux/scripts/sync-window-focus.sh"
# but it CAN be multi-line (multiple indices). tmux preserves newlines in @-options.
# show-hooks exits 0 whether set OR cleared (the cleared form prints just the bare
# hook name) — so do NOT branch on its exit code. Restore (P1.M5.T3.S1) parses +
# re-applies each line preserving -b. utils.sh::tmux_get_hook returns it verbatim.

# CRITICAL (research FINDING 3/4 + TRAP 1): do NOT capture/replay the default
# status-format[0..2] strings. They are tmux built-in defaults (tubular -gu'd them).
# Capturing+replaying them "happens to work" but fights tubular and is fragile. This
# task CALLS state_status_format_save() (state.sh) which enumerates the bulk dump,
# keeps only indices>=3 (genuinely user-set), and stores the list — EMPTY in this
# env. Restore (P1.M5.T3.S1) then does `tmux_unset_opt status-format` (-gu reset ->
# tmux re-composes defaults) and replays the (empty) user list. Do NOT use
# tmux_is_set to probe status-format[n] — it returns rc=0 for set/default/never-
# existed (useless; FINDING 4). state_status_format_save already avoids it.

# CRITICAL (research FINDING 7): the guard MUST be the FIRST statement of
# activate_main, before ANY mutation. If @livepicker-mode == on, return 0
# immediately (the driver's exit 0 makes it a silent exit). This is the fence
# against double-activation re-saving the picker's state over the user's originals.
# @livepicker-mode is NOT set on by this task — that is T5's last step — so a
# fresh run always proceeds past the guard.

# CRITICAL (research FINDING 6): tmux rejects '[' in @-option names
# ("not an array: @livepicker-orig-status-format[0]"). All ORIG_* constants from
# state.sh are bracket-free (ORIG_STATUS_FORMAT_PREFIX is "@livepicker-orig-
# status-format-" +N suffix). This task introduces NO new bracketed @-name; it
# writes only the existing ORIG_* constants verbatim.

# CRITICAL: NO `set -e`, NO `set -o pipefail`. system_context §9 mandates set -u
# only. A transient display-message/show-hooks non-zero (e.g. a session vanishing
# mid-capture on a heavily-churning server) must NOT abort the whole activate
# silently and leave @livepicker-mode unset with a half-saved state. (In S1 mode
# is never set on anyway, so a half-save is non-fatal — but the no-set-e rule is
# the codebase-wide convention; preview.sh/utils.sh/state.sh all follow it.)

# GOTCHA: the three display-message captures (session/window/layout) are NOT
# option reads — there is no `show-option` source for them. Use
#   tmux set-option -g "$ORIG_SESSION" "$(tmux display-message -p '#{session_name}')"
# NOT tmux_save_opt (tmux_save_opt reads via show-option -gqv; it cannot capture
# display-message formats). The three option-based saves (key-table/status/
# renumber-windows) DO use tmux_save_opt <name> <name> (orig==src). The hook uses
# tmux_get_hook. status-format uses state_status_format_save. See the summary
# table in research FINDING 8.

# GOTCHA: `tmux display-message -p '#{...}'` targets the CURRENT client. Under
# `run-shell` from the prefix binding there IS a client (the user pressed the
# key), so it resolves correctly. In the socket-shim MOCK there is no client
# until you attach one — attach a pty client (P1.M3.T1.S2 Level 3 did this via
# `script -qec "tmux -L $SOCK attach -t driver"`) for deterministic capture, or
# assert saved==re-read-consistency under a single stable attached client.

# GOTCHA: livepicker.sh is an ENTRY POINT (executed via run-shell), NOT a sourced
# library. Like plugin.tmux it computes CURRENT_DIR and calls tmux at top level
# (inside activate_main). Unlike the pure libs (options/utils/state — no side
# effects on source), its PURPOSE is the side effect of saving state. This is
# correct for an entry point.

# GOTCHA (T2-T5 seams): the four later subtasks EDIT THIS FILE IN PLACE,
# inserting their steps between the save block and the trailing return 0. Leave
# a clearly-marked seam comment for each (mirroring preview.sh's
# "# --- S2: insert ... ---"). Do NOT add placeholder logic — just the comment.
# This keeps each later subtask a clean surgical edit, not a rewrite.

# STYLE (system_context §9): indent with TABS. Verify with
# `grep -Pn '^    ' scripts/livepicker.sh` (expect empty). shfmt is NOT installed.

# STYLE: file-level shellcheck disable. preview.sh uses
# `# shellcheck disable=SC1091,SC2153` (SC1091 = can't follow non-constant source;
# SC2153 = ORIG_*/STATE_* referenced but "not assigned" — they ARE, in state.sh,
# which shellcheck can't see across the source). livepicker.sh needs the SAME
# disable (it sources the trio and references ORIG_*/STATE_*). Put it on line 2,
# right after the shebang, exactly as preview.sh does.
```

## Implementation Blueprint

### Data models and structure

No new data model. livepicker.sh holds `CURRENT_DIR` and the function-local
variables inside `activate_main` (the three captured display-message strings
could be inlined; declaring them as named locals is cleaner and SC2155-safe).
The state surface is the **write set**: `ORIG_SESSION`, `ORIG_WINDOW`,
`ORIG_LAYOUT`, `ORIG_KEY_TABLE`, `ORIG_STATUS`, `ORIG_RENUMBER`, `ORIG_HOOK`,
the status-format keys (written by `state_status_format_save`), and
`STATE_LINKED_ID` (init to ""). The read set is just `STATE_MODE` (the guard).

### Implementation Tasks (ordered by dependencies)

```yaml
Task 1: CREATE scripts/livepicker.sh — header + CURRENT_DIR + source trio
  - FILE: ./scripts/livepicker.sh  (NEW; PRD §12 file layout puts activate at scripts/livepicker.sh).
  - SHEBANG: #!/usr/bin/env bash  (REQUIRED — run-shell executes via shebang).
  - LINE 2 shellcheck disable (mirror preview.sh EXACTLY):
      # shellcheck disable=SC1091,SC2153
  - HEADER COMMENT block stating: purpose (activate orchestrator; PRD §6 steps
    1-2 = guard + save, the first of the M4 subtasks); the load-bearing rules
    (guard is FIRST; window_id not index; hook saved verbatim; status-format via
    state_status_format_save NOT literal replay; @livepicker-mode NOT set on here
    -> T5); the dependency (sources options/utils/state; invoked via run-shell
    from plugin.tmux's prefix binding, no argv); the no-set-e rule; the T2-T5
    seam model (later subtasks edit in place).
  - CURRENT_DIR (canonical idiom, verbatim):
      CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  - SOURCE trio in load-bearing order (state.sh needs utils.sh — its header says so):
      # shellcheck source=options.sh
      source "$CURRENT_DIR/options.sh"
      # shellcheck source=utils.sh
      source "$CURRENT_DIR/utils.sh"
      # shellcheck source=state.sh
      source "$CURRENT_DIR/state.sh"
  - NO `set -e` (contract; system_context §9). Do NOT add `set -u` explicitly —
    it is inherited from options.sh (sourcing options.sh activates it; preview.sh
    relies on the same inheritance). Adding it is harmless but redundant.
  - STYLE: tabs; quote every expansion.
  - PLACEMENT: ./scripts/livepicker.sh

Task 2: DEFINE activate_main() — STEP 1 guard (FIRST statement)
  - BODY (the guard is the first statement of activate_main — PRD §6.1; §16):
      activate_main() {
      	# --- STEP 1 (PRD §6.1 / §16): double-activation guard ---
      	# If a picker is already active, ignore the second activation silently.
      	# This MUST be the first statement: it short-circuits before ANY mutation,
      	# so a re-activation cannot re-save the picker's state over the user's
      	# originals. @livepicker-mode is set on ONLY by P1.M4.T5.S1 (the last
      	# activate step), so a fresh run always proceeds past here.
      	if [ "$(get_state "$STATE_MODE" "off")" = "on" ]; then
      		return 0
      	fi
      	... (Task 3 save block continues here) ...
  - NOTE: get_state "$STATE_MODE" "off" reads @livepicker-mode; absent -> "off"
    (the default). `return 0` short-circuits activate_main; the driver's exit 0
    produces the silent exit (PRD: "ignore"). Do NOT use `exit 0` mid-function —
    `return 0` + driver-exit is the preview.sh convention and keeps exit
    semantics in one place.

Task 3: IMPLEMENT STEP 2 save block (PRD §6.2 / §9) — the 9 captures
  - BODY (continues inside activate_main, immediately after the guard):
      	# --- STEP 2 (PRD §6.2 / §9): save original state into @livepicker-orig-* ---
      	# Three display-message captures (NOT option reads -> direct set-option -g,
      	# NOT tmux_save_opt). Resolved against the current client (the user pressed
      	# the prefix key, so a client exists under run-shell).
      	tmux set-option -g "$ORIG_SESSION" "$(tmux display-message -p '#{session_name}')"
      	tmux set-option -g "$ORIG_WINDOW"   "$(tmux display-message -p '#{window_id}')"     # @N id, NOT index
      	tmux set-option -g "$ORIG_LAYOUT"   "$(tmux display-message -p '#{window_layout}')"
      	# Three ordinary option reads (orig_name == src_name -> tmux_save_opt idiom).
      	tmux_save_opt key-table key-table
      	tmux_save_opt status status
      	tmux_save_opt renumber-windows renumber-windows
      	# The session-window-changed hook: FULL raw show-hooks output verbatim
      	# (single line "[0] run-shell -b <abs path>" in this env; multi-line ok).
      	# show-hooks exits 0 set-or-cleared -> do NOT branch on its rc.
      	tmux set-option -g "$ORIG_HOOK" "$(tmux_get_hook session-window-changed)"
      	# The status-format array: TRAP 1 (system_context §4). Delegate to the
      	# trap-aware helper — it keeps ONLY genuinely-user-set indices (>=3) and
      	# stores the list (empty in this env) + per-index values. Restore will
      	# `tmux_unset_opt status-format` (-gu reset) and replay the (empty) list.
      	# Do NOT capture/replay the default [0,1,2] strings; do NOT use tmux_is_set.
      	state_status_format_save
      	# Init the linked-preview id (no preview linked yet). preview.sh (P1.M3)
      	# reads this via get_state "$STATE_LINKED_ID" "" — empty means "no prior
      	# link to unlink" on the first preview (its FINDING-4/5 duplicate guard).
      	set_state "$STATE_LINKED_ID" ""
  - GOTCHA: ORIG_SESSION/WINDOW/LAYOUT captures use `$(tmux display-message -p '…')`
    which needs a client (the run-shell invocation has one). In the MOCK, attach a
    pty client. ORIG_WINDOW stores the @N id (FINDING 5). ORIG_HOOK stores the full
    hook line (FINDING 2). state_status_format_save handles status-format (FINDING 3).

Task 4: INSERT T2-T5 seam comments + trailing return 0 + driver
  - BODY (continues inside activate_main, after the save block):
      	# --- T2 (P1.M4.T2.S1): build session list + initial selection (insert here) ---
      	# --- T3 (P1.M4.T3.S1): grow status bar + install renderer (insert here) ---
      	# --- T4 (P1.M4.T4.S1/S2): switch key-table + bind keys + suppress hook (insert here) ---
      	# --- T5 (P1.M4.T5.S1): first preview + set @livepicker-mode on (insert here) ---
      	return 0
      }
      activate_main "$@" || exit 1
      exit 0
  - NOTE: each seam is a single comment line (no logic). Later subtasks replace
    their comment with their step(s). The trailing `return 0` is what makes the
    S1 activate a clean no-op-after-save. The driver mirrors preview.sh exactly.

Task 5: chmod +x  (REQUIRED — not cosmetic)
  - RUN: chmod +x scripts/livepicker.sh
  - VERIFY: ls -la scripts/livepicker.sh shows -rwxr-xr-x (run-shell executes via
    shebang; non-executable fails "Permission denied" — same as plugin.tmux /
    preview.sh / session_history.tmux).

Task 6: VALIDATE (Level 1 syntax/lint + Level 2 socket-shim mock + Level 3 pty spot-check)
  - RUN: bash -n scripts/livepicker.sh            (expect exit 0, no output)
  - RUN: shellcheck scripts/livepicker.sh         (expect 0 findings — file-level
    disable=SC1091,SC2153 covers source-lines + ORIG_*/STATE_*)
  - RUN: grep -Pn '^    ' scripts/livepicker.sh   (expect empty — tabs only)
  - RUN the socket-shim mock (Validation Loop §2) — save test (a) + guard test (b)
    + status-format trap (c), against an isolated socket WITH a pty client. Self-cleaning.
```

### Implementation Patterns & Key Details

The complete, ready-to-paste file body (the implementer may use it as-is; the
only allowed deviation is comment phrasing):

```bash
#!/usr/bin/env bash
# shellcheck disable=SC1091,SC2153
#   SC1091: sources the lib trio (options/utils/state) via $CURRENT_DIR; follow
#           with `shellcheck -x` if you want them traced.
#   SC2153: ORIG_*/STATE_* are readonly CONTRACT constants defined in state.sh
#           (sourced above); shellcheck sees no assignment here.
# scripts/livepicker.sh — tmux-livepicker ACTIVATE orchestrator.
#
# Invoked via `run-shell` from the prefix-key binding plugin.tmux installed
# (P1.M1.T4.S1). Implements PRD §6 Activation steps 1-2 (guard + save); steps 3-7
# (list, status, key-table+hook, first preview, mode-on) are added in place by
# P1.M4.T2-T5 (see the seam comments below).
#
# LOAD-BEARING RULES (research/activate_guard_save_findings.md):
#  - The GUARD is the FIRST statement of activate_main. If @livepicker-mode == on
#    (set only by P1.M4.T5.S1), return 0 silently — a second activation must NOT
#    re-save the picker's state over the user's originals (PRD §16 double-activation).
#  - Capture window via '#{window_id}' (@N token), NOT '#{window_index}'.
#    renumber-windows is on -> indices are unstable (system_context §2).
#  - Save the FULL `show-hooks -g session-window-changed` output VERBATIM into
#    ORIG_HOOK (TRAP 2). show-hooks exits 0 set-or-cleared -> do NOT branch on rc.
#  - status-format: delegate to state_status_format_save (TRAP 1). It keeps ONLY
#    indices>=3 (genuinely user-set; empty in this env) so restore's -gu reset is
#    correct. Do NOT capture/replay the default [0,1,2] strings; do NOT use
#    tmux_is_set (useless for status-format[n] — FINDING 4).
#  - @livepicker-mode is NOT set on here — that is P1.M4.T5.S1's LAST step.
#  - NO `set -e` (display-message/show-hooks legitimately return non-zero on edge
#    cases; a transient failure must not abort a half-saved activate). `set -u`
#    is inherited from options.sh (every var is assigned first).
#
# DEPENDS ON (source order load-bearing — state.sh needs utils.sh first):
#   options.sh (get_opt/opt_*), utils.sh (tmux_save_opt/tmux_get_hook/tmux_set_opt),
#   state.sh (get_state/set_state/STATE_*/ORIG_*/state_status_format_save).

CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=options.sh
source "$CURRENT_DIR/options.sh"
# shellcheck source=utils.sh
source "$CURRENT_DIR/utils.sh"
# shellcheck source=state.sh
source "$CURRENT_DIR/state.sh"

activate_main() {
	# --- STEP 1 (PRD §6.1 / §16): double-activation guard ---
	# If a picker is already active, ignore the second activation silently. This
	# MUST be the first statement: it short-circuits before ANY mutation, so a
	# re-activation cannot re-save the picker's state over the user's originals.
	# @livepicker-mode is set on ONLY by P1.M4.T5.S1, so a fresh run proceeds.
	if [ "$(get_state "$STATE_MODE" "off")" = "on" ]; then
		return 0
	fi

	# --- STEP 2 (PRD §6.2 / §9): save original state into @livepicker-orig-* ---
	# Three display-message captures (NOT option reads -> direct set-option -g,
	# NOT tmux_save_opt). Resolved against the current client (under run-shell the
	# user pressed the prefix key, so a client exists).
	tmux set-option -g "$ORIG_SESSION" "$(tmux display-message -p '#{session_name}')"
	tmux set-option -g "$ORIG_WINDOW"   "$(tmux display-message -p '#{window_id}')"      # @N id, NOT index
	tmux set-option -g "$ORIG_LAYOUT"   "$(tmux display-message -p '#{window_layout}')"
	# Three ordinary option reads (orig_name == src_name -> tmux_save_opt idiom).
	tmux_save_opt key-table key-table
	tmux_save_opt status status
	tmux_save_opt renumber-windows renumber-windows
	# The session-window-changed hook: FULL raw show-hooks output verbatim (single
	# line "session-window-changed[0] run-shell -b <abs path>" here; multi-line ok).
	# show-hooks exits 0 set-or-cleared -> do NOT branch on its rc.
	tmux set-option -g "$ORIG_HOOK" "$(tmux_get_hook session-window-changed)"
	# The status-format array: TRAP 1 (system_context §4). Delegate to the
	# trap-aware helper — it keeps ONLY genuinely-user-set indices (>=3) and
	# stores the list (empty here) + per-index values. Restore does the -gu reset.
	state_status_format_save
	# Init the linked-preview id (no preview linked yet). preview.sh reads this
	# via get_state "$STATE_LINKED_ID" "" — empty means no prior link to unlink.
	set_state "$STATE_LINKED_ID" ""

	# --- T2 (P1.M4.T2.S1): build session list + initial selection (insert here) ---
	# --- T3 (P1.M4.T3.S1): grow status bar + install renderer (insert here) ---
	# --- T4 (P1.M4.T4.S1/S2): switch key-table + bind keys + suppress hook (insert here) ---
	# --- T5 (P1.M4.T5.S1): first preview + set @livepicker-mode on (insert here) ---
	return 0
}

activate_main "$@" || exit 1
exit 0
```

NOTE for the implementer: the block above is the COMPLETE, ready file body. Use
it as-is; the only allowed deviation is comment phrasing. Do NOT add `set -e`.
Do NOT capture `#{window_index}`. Do NOT parse/strip the hook at save time. Do
NOT use `tmux_is_set` for status-format. Do NOT set `@livepicker-mode on`. Do
NOT add placeholder logic to the T2-T5 seams (comments only). Do NOT create any
other file. The mock (Validation §2) proves every behavior.

### Integration Points

```yaml
INVOCATION (how livepicker.sh gets called — P1.M1.T4.S1):
  - plugin.tmux binds: tmux bind-key "$KEY" run-shell "$CURRENT_DIR/scripts/livepicker.sh"
    (prefix table; @livepicker-key). On key press, tmux run-shell's this file with
    NO argv. The trailing driver's "$@" is therefore empty in practice (harmless;
    kept for parity with preview.sh + manual invocation in the mock).

CALLERS / CONSUMERS (this task's OUTPUT — read by FUTURE subtasks):
  - P1.M4.T2.S1 (list): reads nothing from S1; inserts its step at the T2 seam.
  - P1.M4.T3.S1 (status): inserts at the T3 seam.
  - P1.M4.T4.S1/S2 (keys+hook): inserts at the T4 seam (hook SUPPRESSION is its
        job; S1 only CAPTURES the hook).
  - P1.M4.T5.S1 (preview+mode-on): inserts at the T5 seam; sets @livepicker-mode
        on as the LAST step. Until T5 lands, @livepicker-mode stays unset -> the
        guard always proceeds -> S1's save is independently re-runnable/testable.
  - P1.M5.T3.S1 (restore): READS the @livepicker-orig-* keys S1 wrote (the
        contract). The exact key names are fixed in state.sh ORIG_* constants.
  - P1.M3 (preview.sh): reads @livepicker-orig-session / @livepicker-orig-window
        (to know the driver session/window) and @livepicker-linked-id (which S1
        inits to "" — preview's first call sees empty).

STATE WRITES (this task — the save set):
  - @livepicker-orig-session, -window (@N id), -layout (display-message captures).
  - @livepicker-orig-key-table, -status, -renumber-windows (tmux_save_opt).
  - @livepicker-orig-session-window-changed (FULL show-hooks line).
  - @livepicker-orig-status-format-indices (+ per-index -<N> values, via
        state_status_format_save — empty list in this env, so just the indices="").
  - @livepicker-linked-id = "" (init via set_state).

STATE READS (this task):
  - @livepicker-mode (the guard; absent -> "off").

TMUX MUTATIONS (this task — PRD §13 primitives):
  - display-message -p '#{session_name}|#{window_id}|#{window_layout}' (read-only capture).
  - show-option -gqv (via tmux_save_opt, x3) + show-options -g status-format (via
        state_status_format_save) + show-hooks -g (via tmux_get_hook) (read-only).
  - set-option -g @livepicker-orig-* / @livepicker-linked-id (the writes).
  - NO switch-client, NO select-window, NO link-window/unlink-window, NO set-hook/
        set-hook -gu (hook SUPPRESSION is T4), NO bind-key, NO refresh-client, NO
        set-option key-table / status / status-format[*] (those are T3/T4/restore).

DATABASE / MIGRATIONS / ROUTES / CONFIG: none.
```

## Validation Loop

### Level 1: Syntax & Style (Immediate Feedback)

```bash
# Run after creating + chmod +x the file — fix before proceeding.
bash -n scripts/livepicker.sh                     # syntax; expect no output, exit 0
shellcheck scripts/livepicker.sh                  # lint; expect 0 findings (file-level
                                                  # disable=SC1091,SC2153 covers it)
# Tabs-not-spaces sanity (shfmt NOT installed):
grep -Pn '^    ' scripts/livepicker.sh && echo "FAIL: 4-space indent found, use tabs" || echo "OK: tabs only"
# Executable bit (REQUIRED — run-shell loading model):
[ -x scripts/livepicker.sh ] && echo "OK: executable" || { echo "FAIL: not executable"; chmod +x scripts/livepicker.sh; }
# Confirm @livepicker-mode is NOT set on by this task (T5's job):
grep -n 'set-option -g "@livepicker-mode" on\|set_state "$STATE_MODE" "on"' scripts/livepicker.sh \
  && echo "FAIL: S1 must NOT turn mode on" || echo "OK: mode-on deferred to T5"
# Confirm window_id (not index) is captured:
grep -n "display-message -p '#{window_id}'" scripts/livepicker.sh && echo "OK: window_id" \
  || echo "FAIL: must capture #{window_id}"
# Run from the repo root.
```

### Level 2: Socket-Shim Mock Validation — save + guard + status-format trap, zero live-server impact

Reuses the P1.M3.T1.S2 / system_context §7 PATH-wrapper socket shim, PLUS a pty
client (display-message needs one). Self-cleaning.

```bash
#!/usr/bin/env bash
# Throwaway socket-shim validation for scripts/livepicker.sh (do NOT commit).
set -u
REPO_ROOT="$(cd "$(dirname "$0")" && pwd)"
[ -f "$REPO_ROOT/scripts/livepicker.sh" ] || { echo "livepicker.sh missing"; exit 1; }

SOCK="lp-activate-s1-mock-$$"
SHIM_DIR="$(mktemp -d)"
cat > "$SHIM_DIR/tmux" <<EOF
#!/usr/bin/env bash
exec /usr/bin/tmux -L "$SOCK" "\$@"
EOF
chmod +x "$SHIM_DIR/tmux"
export PATH="$SHIM_DIR:$PATH"

cleanup() {
	PATH="/usr/bin:/bin:$PATH" tmux -L "$SOCK" kill-server 2>/dev/null || true
	rm -rf "$SHIM_DIR" /tmp/lp-activate-s1.log
}
trap cleanup EXIT

# --- fixture: a driver session + window with text (so layout is non-trivial) ---
tmux new-session -d -s driver -x 100 -y 40
tmux send-keys -t "=driver" "echo DRIVER_TEXT" Enter
tmux split-window -t "=driver"                      # 2 panes -> non-trivial window_layout
sleep 0.2
# attach a pty client so display-message -p resolves session/window/layout deterministically
TMUX="" script -qec "tmux -L $SOCK attach -t driver" /tmp/lp-activate-s1.log &
ATTACH_PID=$!; sleep 0.5

pass=0; fail=0
assert() { if [ "$2" = "$3" ]; then pass=$((pass+1)); else fail=$((fail+1)); printf 'FAIL %s: got=[%s] want=[%s]\n' "$1" "$2" "$3"; fi; }
readg() { tmux show-option -gqv "$1"; }   # read a saved @livepicker-orig-* key

# ---------- (a) SAVE TEST: every @livepicker-orig-* matches the live value ----------
# prime a clean state (mode off, no prior orig/linked keys)
tmux set-option -gu "@livepicker-mode" 2>/dev/null || true
tmux set-option -gu "@livepicker-linked-id" 2>/dev/null || true

bash "$REPO_ROOT/scripts/livepicker.sh"; rc=$?
assert "save: exit 0" "$rc" "0"
# session
assert "save: orig-session == live session_name" "$(readg "@livepicker-orig-session")" "$(tmux display-message -p '#{session_name}')"
# window ID (@N), NOT index
assert "save: orig-window == live window_id (@N)" "$(readg "@livepicker-orig-window")" "$(tmux display-message -p '#{window_id}')"
assert "save: orig-window starts with @" "$(readg "@livepicker-orig-window" | cut -c1)" "@"
# layout (non-empty, contains the split)
LIVE_LAYOUT="$(tmux display-message -p '#{window_layout}')"
assert "save: orig-layout non-empty" "$([ -n "$(readg "@livepicker-orig-layout")" ] && echo 1 || echo 0)" "1"
assert "save: orig-layout == live window_layout" "$(readg "@livepicker-orig-layout")" "$LIVE_LAYOUT"
# option reads
assert "save: orig-key-table == root" "$(readg "@livepicker-orig-key-table")" "root"
assert "save: orig-status == on" "$(readg "@livepicker-orig-status")" "on"
assert "save: orig-renumber-windows == on" "$(readg "@livepicker-orig-renumber-windows")" "on"
# hook: FULL show-hooks line (verbatim, incl [0] and -b)
LIVE_HOOK="$(tmux show-hooks -g session-window-changed)"
assert "save: orig-hook non-empty" "$([ -n "$(readg "@livepicker-orig-session-window-changed")" ] && echo 1 || echo 0)" "1"
assert "save: orig-hook == live show-hooks line" "$(readg "@livepicker-orig-session-window-changed")" "$LIVE_HOOK"
assert "save: orig-hook contains 'session-window-changed[0]'" "$(readg "@livepicker-orig-session-window-changed" | grep -c 'session-window-changed\[0\]')" "1"
# linked-id initialized to empty
assert "save: linked-id == '' (init)" "$(readg "@livepicker-linked-id")" ""

# ---------- (c) STATUS-FORMAT TRAP: empty user-set list, NO per-index keys ----------
# (the tubular-style env: status-format materializes only built-in defaults [0,1,2])
assert "trap: status-format-indices == '' (no user overrides)" "$(readg "@livepicker-orig-status-format-indices")" ""
assert "trap: NO per-index key -0 written" "$([ -z "$(readg "@livepicker-orig-status-format-0")" ] && echo 1 || echo 0)" "1"
# mode NOT turned on by S1
assert "trap: @livepicker-mode still unset/off after S1 save" "$(readg "@livepicker-mode")" ""

# ---------- (b) GUARD TEST: mode=on -> exit 0, no mutation (idempotent no-op) ----------
# Pre-set mode on + sentinel orig values; run again; sentinels must survive.
tmux set-option -g "@livepicker-mode" "on"
tmux set-option -g "@livepicker-orig-session" "SENTINEL_SESSION"
tmux set-option -g "@livepicker-orig-window" "@SENTINEL_WIN"
tmux set-option -g "@livepicker-orig-layout" "SENTINEL_LAYOUT"
tmux set-option -g "@livepicker-orig-key-table" "SENTINEL_KT"
tmux set-option -g "@livepicker-linked-id" "@SENTINEL_LINKED"
bash "$REPO_ROOT/scripts/livepicker.sh"; rc=$?
assert "guard: exit 0 (silent ignore)" "$rc" "0"
assert "guard: orig-session UNCHANGED (no re-save)" "$(readg "@livepicker-orig-session")" "SENTINEL_SESSION"
assert "guard: orig-window UNCHANGED" "$(readg "@livepicker-orig-window")" "@SENTINEL_WIN"
assert "guard: orig-layout UNCHANGED" "$(readg "@livepicker-orig-layout")" "SENTINEL_LAYOUT"
assert "guard: orig-key-table UNCHANGED" "$(readg "@livepicker-orig-key-table")" "SENTINEL_KT"
assert "guard: linked-id UNCHANGED" "$(readg "@livepicker-linked-id")" "@SENTINEL_LINKED"

kill "$ATTACH_PID" 2>/dev/null; wait "$ATTACH_PID" 2>/dev/null
printf 'PASS=%d FAIL=%d\n' "$pass" "$fail"
[ "$fail" = "0" ]
# Expected: PASS≈24 FAIL=0. Key proofs:
#  - save: every @livepicker-orig-* matches the live value; window is @N (not index);
#    hook is the FULL line; linked-id is "".
#  - trap: status-format-indices="" and no per-index key (no default-string replay).
#  - guard: mode=on short-circuits before the save block -> all sentinels survive.
```

### Level 3: Integration Testing (System Validation)

```bash
# Live spot-check on an ISOLATED socket WITH an attached pty client — confirms the
# save block writes the REAL live values (not shim artifacts) and the guard is a
# true no-op. Self-cleaning. (This is the same shape as Level 2 but run against a
# second isolated socket to rule out shim-wrapper artifacts; optional but cheap.)
export LP_SOCK="lp-activate-s1-live-$$"
REPO_ROOT="$(pwd)"
SHIM_DIR="$(mktemp -d)"
cat > "$SHIM_DIR/tmux" <<EOF
#!/usr/bin/env bash
exec /usr/bin/tmux -L "$LP_SOCK" "\$@"
EOF
chmod +x "$SHIM_DIR/tmux"
trap 'PATH=/usr/bin:/bin:$PATH tmux -L "$LP_SOCK" kill-server 2>/dev/null; rm -rf "$SHIM_DIR" /tmp/lp-s1-live.log' EXIT
T() { PATH="$SHIM_DIR:$PATH" tmux "$@"; }
T new-session -d -s driver -x 120 -y 40
T send-keys -t "=driver" "echo LIVE_DRIVER" Enter; T split-window -t "=driver"; sleep 0.2
TMUX="" script -qec "tmux -L $LP_SOCK attach -t driver" /tmp/lp-s1-live.log &
ATTACH_PID=$!; sleep 0.5
echo "before: mode=[$(T show-option -gqv "@livepicker-mode")] (expect empty)"
PATH="$SHIM_DIR:$PATH" bash "$REPO_ROOT/scripts/livepicker.sh"; echo "rc=$? (expect 0)"
echo "after save:"
echo "  orig-session=[$(T show-option -gqv "@livepicker-orig-session")] (expect driver)"
echo "  orig-window=[$(T show-option -gqv "@livepicker-orig-window")] (expect @<N>)"
echo "  orig-layout=[$(T show-option -gqv "@livepicker-orig-layout")] (expect non-empty split layout)"
echo "  orig-key-table=[$(T show-option -gqv "@livepicker-orig-key-table")] (expect root)"
echo "  orig-hook=[$(T show-option -gqv "@livepicker-orig-session-window-changed")] (expect empty — no hook set on the fresh socket; restore handles empty)"
echo "  linked-id=[$(T show-option -gqv "@livepicker-linked-id")] (expect empty)"
echo "  mode=[$(T show-option -gqv "@livepicker-mode")] (expect empty — NOT set by S1)"
kill "$ATTACH_PID" 2>/dev/null; wait "$ATTACH_PID" 2>/dev/null
# Expected: all saved keys populated to the live values; mode still empty (T5's job).
# NOTE: on the FRESH isolated socket there is NO session-window-changed hook set, so
# orig-hook will be EMPTY here (vs the live server where it is the sync-window-focus
# line). The save handles both (it stores whatever show-hooks returns, incl. the bare
# hook name when cleared). The Level 2 mock sets the hook via the live fixture or
# asserts against the live show-hooks output; either is valid.
```

### Level 4: Creative & Domain-Specific Validation

```bash
# Pollution invariant spot-check (PRD §15.18 — the core guarantee) for the S1 save.
# The save must NOT fire client-session-changed (it never calls switch-client). If
# the tmux-session-history plugin's @session-history-hist is present on the LIVE
# server, diff it across a save. Touches ONLY option reads + the @livepicker-orig-*
# keys + one isolated run of livepicker.sh. Run ONLY if @session-history-hist exists.
if tmux show-options -gv "@session-history-hist" >/dev/null 2>&1; then
    REPO_ROOT="$(pwd)"
    BEFORE="$(tmux show-options -gv "@session-history-hist" 2>/dev/null)"
    bash "$REPO_ROOT/scripts/livepicker.sh" 2>/dev/null
    AFTER="$(tmux show-options -gv "@session-history-hist" 2>/dev/null)"
    # cleanup our keys (so we don't leave a half-state on the live server)
    for k in mode linked-id orig-session orig-window orig-layout orig-key-table \
             orig-status orig-renumber-windows orig-session-window-changed \
             orig-status-format-indices; do
        tmux set-option -gu "@livepicker-$k" 2>/dev/null
    done
    # also clear any per-index status-format keys we may have written (none in this env)
    if [ "$BEFORE" = "$AFTER" ]; then
        echo "OK: @session-history-hist UNCHANGED across S1 save (Invariant A holds)"
    else
        echo "FAIL: history polluted by S1 save (should be impossible — no switch-client)"
    fi
else
    echo "SKIP: tmux-session-history not present on live server (mock §2 covers this structurally)"
fi
# Expected: OK — the save never calls switch-client, so client-session-changed never
# fires. This is the cheapest possible proof of the plugin's central invariant, and
# it holds for S1 precisely because the save is read-only w.r.t. the client.
```

## Final Validation Checklist

### Technical Validation

- [ ] `bash -n scripts/livepicker.sh` exits 0 with no output.
- [ ] `shellcheck scripts/livepicker.sh` reports 0 findings (file-level
      `# shellcheck disable=SC1091,SC2153` covers source-lines + ORIG_*/STATE_*).
- [ ] No 4-space indents (`grep -Pn '^    '` is empty); tabs only.
- [ ] `scripts/livepicker.sh` is executable (`-rwxr-xr-x`).

### Feature Validation

- [ ] File at `scripts/livepicker.sh`; shebang + line-2 shellcheck disable.
- [ ] Sources `options.sh → utils.sh → state.sh` via `$CURRENT_DIR` in THAT order.
- [ ] `activate_main()` defined; **guard is its FIRST statement**
      (`if [ "$(get_state "$STATE_MODE" "off")" = "on" ]; then return 0; fi`).
- [ ] Save captures `#{session_name}`, `#{window_id}` (@N, NOT index),
      `#{window_layout}` via `tmux set-option -g "$ORIG_*" "$(tmux display-message -p …)"`.
- [ ] key-table/status/renumber-windows saved via `tmux_save_opt <name> <name>`.
- [ ] Hook saved as FULL `tmux_get_hook session-window-changed` output (verbatim).
- [ ] status-format delegated to `state_status_format_save` (NOT literal capture;
      NOT `tmux_is_set`).
- [ ] `@livepicker-linked-id` init to `""` via `set_state "$STATE_LINKED_ID" ""`.
- [ ] **NO** `@livepicker-mode on` anywhere (grep from Level 1 confirms; T5's job).
- [ ] T2/T3/T4/T5 seam comments present (single comment each, no logic).
- [ ] Trailing driver `activate_main "$@" || exit 1; exit 0`.
- [ ] Mock (a) save: all `@livepicker-orig-*` match live; window is @N; hook is full
      line; linked-id=""; PASS for every assert.
- [ ] Mock (b) guard: mode=on → exit 0, all sentinels survive (no re-save).
- [ ] Mock (c) status-format trap: indices="" and no per-index key.

### Code Quality Validation

- [ ] NO `set -e`, NO `set -o pipefail` (system_context §9).
- [ ] All expansions double-quoted (`"$STATE_MODE"`, `"$ORIG_SESSION"`, `"$(…)"`, …).
- [ ] NO `switch-client`, NO `select-window`, NO `link-window`/`unlink-window`, NO
      `set-hook`, NO `bind-key`, NO `refresh-client`, NO `set-option key-table/status`
      in S1 (those are T3/T4/restore).
- [ ] Structure mirrors preview.sh (shebang + file-level disable; CURRENT_DIR;
      source trio; `_main()` + trailing driver; marked seam comments).
- [ ] Indent with tabs; file-level shellcheck disable on line 2.

### Documentation & Deployment

- [ ] Header comment states: activate purpose (PRD §6 steps 1-2); the guard-first
      rule; window_id-not-index; hook-saved-verbatim; status-format-via-helper;
      mode-on-deferred-to-T5; the no-set-e rule; the T2-T5 seam model.
- [ ] No README/doc file created (DOCS = Mode A; covered by README P1.M8.T1.S1).
- [ ] No tmux.conf edit; no other source file touched; no tests/ dir committed.
- [ ] No new env vars introduced beyond the documented @livepicker-orig-* saves.

---

## Anti-Patterns to Avoid

- ❌ Don't put ANY mutation before the guard. The guard is the FIRST statement of
  `activate_main` — if `@livepicker-mode == on`, `return 0` before a single
  `set-option`. A save that runs on a double-activation re-saves the picker's
  state over the user's originals and breaks restore (PRD §16).
- ❌ Don't capture `#{window_index}` instead of `#{window_id}`. `renumber-windows`
  is on (system_context §2); indices are unstable; restore's
  `select-window -t "$ORIG_WINDOW"` would land on the wrong window. The @N id is
  the stable handle (research FINDING 5).
- ❌ Don't parse/strip the hook at save time. Store the FULL `show-hooks -g
  session-window-changed` output verbatim (it may be multi-line; restore parses
  it). Don't branch on `show-hooks`' exit code — it's 0 set OR cleared (FINDING 2).
- ❌ Don't capture/replay the default `status-format[0..2]` strings. Delegate to
  `state_status_format_save` (TRAP 1). Don't use `tmux_is_set` to probe
  `status-format[n]` — rc=0 for set/default/never-existed (useless; FINDING 4).
- ❌ Don't set `@livepicker-mode on` in S1. That is P1.M4.T5.S1's LAST step. S1's
  contract is explicit: mode is NOT yet on (so the save is independently
  re-runnable, and the guard always proceeds in S1-only testing).
- ❌ Don't use `tmux_save_opt` for the display-message captures (session/window/
  layout). `tmux_save_opt` reads via `show-option -gqv`; there is no option source
  for `#{session_name}`/`#{window_id}`/`#{window_layout}`. Use
  `tmux set-option -g "$ORIG_*" "$(tmux display-message -p '…')"`. Reserve
  `tmux_save_opt` for the three option-based saves (key-table/status/renumber).
- ❌ Don't add `set -e`/`set -o pipefail`. A transient display-message/show-hooks
  non-zero must not abort a half-saved activate. `set -u` only (system_context §9).
- ❌ Don't invent a bracketed `@livepicker-orig-status-format[N]` name — tmux
  rejects `[` in @-names ("not an array"). Use the existing `ORIG_*` constants
  (all bracket-free); status-format indices go through `state_status_format_save`
  which uses the `ORIG_STATUS_FORMAT_PREFIX`+N form (FINDING 6).
- ❌ Don't add placeholder LOGIC to the T2-T5 seams. One comment line each. Later
  subtasks replace their comment with their step(s); placeholder logic would
  collide and confuse the diff.
- ❌ Don't create a `tests/` directory or committed test file — the harness is
  invented in P1.M7.T1/T2. Validate via the throwaway socket-shim mock (Level 2)
  and delete it.
- ❌ Don't edit any other source file (options/utils/state/preview/renderer/plugin.tmux)
  — they are COMPLETE or in-parallel. S1 only CREATES `scripts/livepicker.sh`.
- ❌ Don't use 4-space indent — tabs only (system_context §9).

---

## Confidence Score

**9 / 10** for one-pass success. Rationale: the deliverable is a single ~45-line
entry-point script whose complete body is given verbatim in the Implementation
Blueprint, structurally a near-clone of `scripts/preview.sh` (shebang + file-level
shellcheck disable; CURRENT_DIR; source trio; `_main()` + trailing driver; marked
seam comments). Every save target has a verified capture primitive already
provided by the COMPLETE INPUT dependencies (`utils.sh::tmux_save_opt` /
`tmux_get_hook`; `state.sh::state_status_format_save` + the `ORIG_*`/`STATE_*`
constants), and every live fact the save depends on was re-verified live on the
target `tmux 3.6b` (key-table=root, status=on, renumber-windows=on; the exact
`session-window-changed[0] … -b …` hook line; status-format materializing only
defaults [0,1,2]; window_id=@N; display-message resolving with a client). The
three load-bearing correctness decisions — **guard-first**, **window_id-not-index**,
**status-format-via-helper (TRAP 1)** — are each backed by a live finding and a
dedicated mock assertion. The mock (Level 2) exercises save + guard + trap against
an isolated socket with a pty client (zero live-server impact) and asserts ≈24
specific outcomes. Residual risks: (a) the implementer forgetting `chmod +x`
(called out as a hard requirement + Level 1 check); (b) the pty-client attachment
in the mock being flaky on some kernels (mitigated by the Level 3 second-socket
spot-check and by `script`'s wide availability); (c) shellcheck needing the
file-level disable to silence SC1091/SC2153 (handled; matches preview.sh). All
residual risks are deterministically caught by the validation loop.
