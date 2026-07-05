# PRP — P1.M4.T4.S2: livepicker.sh — suppress `session-window-changed` hook

---

## Goal

**Feature Goal**: Fill the **T4.S2 seam** of `scripts/livepicker.sh` — the
single seam comment `# --- T4 (P1.M4.T4.S2): suppress session-window-changed hook
(insert here) ---` left by the just-landed **P1.M4.T4.S1** (it sits between S1's
`tmux set-option -g key-table livepicker` and the T5 seam). Implement PRD
**§7.11 "Side effects to suppress"** + **§16 "Hook suppression scope"** +
system_context **§4 TRAP 2 / §7 recipe**: when `@livepicker-suppress-window-hook`
is `on` (PRD §11 default), clear the LIVE global `session-window-changed` hook
for the picker duration so that `preview.sh`'s `select-window` nav does NOT fire
the user's `sync-window-focus.sh` and spam focus bytes into the linked preview
window on every keystroke. When the option is `off`, leave the hook INTACT
(documented opt-in: preview nav runs `sync-window-focus.sh`). S2 writes NOTHING
to `@livepicker-*` state; its only mutation is the live hook (cleared). The
matched RESTORE counterpart (re-run the saved hook verbatim, preserving `-b` +
absolute path) is owned by **P1.M5.T3.S1** and reads the value S1's STEP 2
already saved into `@livepicker-orig-session-window-changed`.

**Deliverable**: A **surgical edit** to `scripts/livepicker.sh` that **replaces
the single S2 seam comment line** with a small block (header comment + a single
`if [ "$(opt_suppress_window_hook)" = "on" ]; then tmux_clear_hook
session-window-changed; fi`). No new file, no other file touched, no new local
variables, no `@livepicker-*` writes. The block reuses the `tmux_clear_hook`
helper already provided by `scripts/utils.sh` (house style — the helper's
doc-comment literally says "Used by activate to suppress session-window-changed";
raw `tmux set-hook -gu session-window-changed` is equivalent). S1's block
(above), the T5 seam (below), `return 0`, and the driver are UNCHANGED.

**Success Definition**:
- `bash -n scripts/livepicker.sh` passes; `shellcheck scripts/livepicker.sh` is
  clean (0 findings; the file-level `# shellcheck disable=SC1091,SC2153` from T1
  covers the source lines + ORIG_*/STATE_*; S2 adds no word-split, no new
  disable needed). Tabs only; no `set -e`.
- **Mock (a) hook cleared when on:** after running livepicker.sh with
  `@livepicker-suppress-window-hook=on` and a real `[0]` hook set, `show-hooks -g
  session-window-changed` has NO `[` marker (the `[0] run-shell -b ...` line is
  gone → bare `session-window-changed`).
- **Mock (b) focus side-effect suppressed:** a `session-window-changed` hook that
  appends to a log file does NOT grow across several `select-window` calls after
  activate (the contract's mocking recipe) — whereas the SAME hook DOES grow on
  select-window BEFORE activate (baseline proves the harness fires the hook).
- **Mock (c) hook left intact when off:** with `@livepicker-suppress-window-hook=off`,
  after activate `show-hooks -g session-window-changed` STILL has the `[0]`
  marker, and select-window STILL grows the log (documented opt-in behavior).
- **Mock (d) safe no-op on already-cleared:** running the suppress path twice (or
  with no hook set) is rc=0, no error (no defensive guard needed — FINDING 3).
- **Mock (e) ORIG_HOOK untouched:** S2 does NOT modify
  `@livepicker-orig-session-window-changed` (restore's input); its value after
  activate equals its value before (the STEP-2 save is what wrote it).

## User Persona (if applicable)

**Target User**: None directly (internal orchestration step). Transitively: the
end user navigating the live preview (PRD §3 stories) — without S2, every
Down/Up/j/k/C-M-Tab/C-M-BTab during the picker fires `sync-window-focus.sh`,
which writes focus-sync bytes into the WRONG window (the linked preview), causing
visible flicker / focus desync. S2 makes preview nav SILENT w.r.t. the user's
focus hook.

**Use Case**: The user pressed the activation key. T1 saved state (incl. the
`session-window-changed` hook verbatim into ORIG_HOOK); T2 built the list; T3
grew the status bar + renderer; **S1** switched the key-table + bound every key.
**S2 (this task)** is the LAST mutate-state step before T5's first preview: it
neutralizes the focus hook so the imminent `select-window` nav (T5 + P1.M6
input-handler) does not trigger side effects. Once T5 links the preview window +
sets `@livepicker-mode on`, every nav keystroke is focus-hook-free.

**User Journey** (S2 scope — the hook is cleared; no preview/mode-on yet):
1. …T1 guard+save; T2 list; T3 status; **S1** key-table switch + binds.
2. **S2 (this task):** if `@livepicker-suppress-window-hook=on`, clear the live
   `session-window-changed` hook globally (every index). If `off`, do nothing.
3. [T5 (next seam) runs the first preview + sets `@livepicker-mode on` +
   `refresh-client -S` — the picker is now fully live and nav is hook-silent.]
4. On exit, restore.sh (P1.M5.T3.S1) replays the saved hook verbatim
   (preserving `-b` + abs path) — the user's focus sync resumes exactly.

**Pain Points Addressed**:
- (a) **Focus-hook spam during preview.** Without S2, `preview.sh`'s
  `select-window` fires `session-window-changed` → `sync-window-focus.sh` runs
  on every nav keystroke, writing focus bytes into the linked preview window
  (not the user's real target). S2 removes the hook for the picker duration.
- (b) **Restore must be EXACT.** The hook is `session-window-changed[0]
  run-shell -b <abs path>`. S2 only CLEARS the live hook; it never touches the
  SAVED value (ORIG_HOOK, captured by T1's STEP 2). So restore (P1.M5.T3.S1) has
  the pristine verbatim line to replay, `-b` and abs path intact (TRAP 2).
- (c) **The opt-out must be honored.** Some users WANT the focus sync to run
  during preview. `@livepicker-suppress-window-hook=off` is a documented opt-in
  that leaves the hook intact. S2's `if = on` gate implements this precisely.

## Why

- **PRD §7.11 "Side effects to suppress"** is the controlling section:
  "`select-window` fires `session-window-changed`. The user's config runs
  `sync-window-focus.sh` on that hook, and rapid preview navigation would fire
  it repeatedly. When `@livepicker-suppress-window-hook` is `on` (default), save
  the current `session-window-changed` hook, clear it for the duration of the
  picker, and restore it on exit." S2 owns the CLEAR half (the SAVE was T1's
  STEP 2; the RESTORE is P1.M5.T3.S1).
- **PRD §16 "Hook suppression scope"**: "Clearing `session-window-changed` is
  global for the duration. Restore it exactly on exit, including the `-b` flag
  if present." S2 clears globally; restore replays exactly.
- **system_context §4 TRAP 2 + §7**: the hook is array-indexed (`[0]`) with
  `-b`; suppress with `set-hook -gu session-window-changed` (clears all indices);
  the recipe is verified live (research FINDING 1).
- **Boundary respect.** S2 touches ONLY the live `session-window-changed` hook
  (cleared, when on). It does NOT: run a preview / `link-window` /
  `switch-client` / `select-window` / `refresh-client` (T5); set
  `@livepicker-mode on` (T5); mutate status / status-format (T3); mutate the
  key-table or bindings (S1 — already done above); read or write ORIG_HOOK
  (T1 wrote it; P1.M5.T3.S1 reads it). Its READ set is exactly one accessor:
  `opt_suppress_window_hook()`.
- **Scope cohesion.** S2 is the focus-hook counterpart of S1's key-table switch:
  both neutralize a user-side effect for the modal picker duration, and both are
  torn down by restore (S1's key-table ↔ P1.M5.T3.S1/T4.S1; S2's hook ↔
  P1.M5.T3.S1). S2 must land BEFORE T5's first preview so the very first
  `select-window` is hook-silent.

## What

A surgical in-place edit to `scripts/livepicker.sh` that replaces the single S2
seam comment line with a block which:

1. Adds a header comment (the `(insert here)` suffix dropped) documenting PRD
   §7.11 + §16 + system_context §4 TRAP 2 / §7, the on/off semantics, the fact
   that the SAVED hook lives in ORIG_HOOK (T1) and is replayed by restore
   (P1.M5.T3.S1), and that `set-hook -gu` clears every index + is a safe no-op.
2. Adds a single gate: `if [ "$(opt_suppress_window_hook)" = "on" ]; then
   tmux_clear_hook session-window-changed; fi` — mirroring the guard idiom at the
   top of `activate_main` (`if [ "$(get_state "$STATE_MODE" "off")" = "on" ]`).
   Uses the `tmux_clear_hook` helper from `scripts/utils.sh` (house style; raw
   `tmux set-hook -gu session-window-changed` is equivalent — research FINDING 5).
3. Declares NO new locals and writes NO `@livepicker-*` key (research FINDING 8).

### Success Criteria

- [ ] The S2 seam comment is REPLACED by the S2 block (header without
      `(insert here)` + the `if … tmux_clear_hook …` gate); S1's block (above),
      the T5 seam (below), `return 0`, and the driver are UNCHANGED.
- [ ] The gate reads `opt_suppress_window_hook()` (PRD §11 default `on`) and
      clears via `tmux_clear_hook session-window-changed` ONLY when the value is
      exactly `"on"`.
- [ ] When the option is `"off"` (or any non-`"on"` value), the hook is LEFT
      INTACT (no `set-hook` call) — documented opt-in behavior.
- [ ] **NO** `@livepicker-*` writes (ORIG_HOOK is restore's input, untouched);
      **NO** `link-window`/`switch-client`/`select-window`/`refresh-client`
      (T5); **NO** `@livepicker-mode on` (T5); **NO** status mutation (T3);
      **NO** key-table/bind mutation (S1).
- [ ] `bash -n` clean; `shellcheck` 0 findings (no new disable needed); tabs
      only; no `set -e`.
- [ ] Mock (a) hook cleared when on; (b) focus side-effect suppressed (log
      stalls after activate, grows before); (c) hook intact when off; (d) safe
      no-op on already-cleared; (e) ORIG_HOOK untouched.

## All Needed Context

### Context Completeness Check

_Pass_: A developer who has never seen this repo can implement S2 from
(a) the verbatim block in "Implementation Patterns & Key Details" (complete,
ready to paste at the seam), (b) the 8 live-verified findings in
`research/hook_suppress_findings.md` — most critically **FINDING 1**
(`set-hook -gu` clears `[0]`; verified), **FINDING 2** (show-hooks always rc=0;
"is set?" = grep `[`, the mock-assertion key), **FINDING 3** (safe no-op, no
guard needed), **FINDING 5** (`tmux_clear_hook` helper exists; house style), and
**FINDING 7** (default `on`; `off` is an intentional no-op), and (c) the
socket-shim mock (a)–(e) that exercises clear / focus-suppress / opt-out /
no-op / ORIG_HOOK-untouched against an isolated socket (zero live-server
impact). The INPUT dependency (`opt_suppress_window_hook`) is present in
`scripts/options.sh` (P1.M1.T1.S1, COMPLETE). The host file `scripts/livepicker.sh`
has S1 LANDED — the S2 seam comment is present and is the exact target.

### Documentation & References

```yaml
# MUST READ — INPUT dependency: options.sh (the suppress accessor). COMPLETE (P1.M1.T1.S1).
- file: scripts/options.sh
  why: Defines opt_suppress_window_hook() -> get_opt "@livepicker-suppress-window-hook" "on"
       (PRD §11 default "on"; bool on/off). S2 reads it via the "$(opt_suppress_window_hook)"
       idiom — single token, no word-split, no SC2086.
  critical: returns EXACTLY "on" or "off" (or a user-set override). The gate compares
            literally to "on"; any other value (incl. "off", "", "true") leaves the
            hook intact (safe default = do not suppress).

# MUST READ — INPUT dependency: utils.sh (the clear helper). COMPLETE (P1.M1.T2.S1).
- file: scripts/utils.sh
  why: Defines tmux_clear_hook() -> `tmux set-hook -gu "$1"`, documented "Used by activate
       to suppress session-window-changed." House style = USE THIS (T1 used tmux_save_opt/
       tmux_get_hook; S2's counterpart is tmux_clear_hook). Raw `tmux set-hook -gu
       session-window-changed` is identical in effect (FINDING 5). Also defines tmux_get_hook
       (used by T1's STEP 2 to SAVE the hook into ORIG_HOOK) — S2 does NOT call it.
  critical: tmux_clear_hook is a safe no-op on an already-cleared/never-set hook (rc=0;
            FINDING 3) -> no defensive guard needed before clearing.

# MUST READ — the host file this task EDITS (S1 LANDED; T2/T3/S1 seams all filled).
- file: scripts/livepicker.sh
  why: activate_main(). S2 replaces the single seam comment that sits between S1's last
       line (`tmux set-option -g key-table livepicker`) and the T5 seam. CURRENT location
       (re-read fresh at implementation time; line numbers shift, the TEXT is stable):
         ...
         tmux set-option -g key-table livepicker
         # --- T4 (P1.M4.T4.S2): suppress session-window-changed hook (insert here) ---
         # --- T5 (P1.M4.T5.S1): first preview + set @livepicker-mode on (insert here) ---
         return 0
  pattern: S2 mirrors the guard idiom at the TOP of activate_main:
             if [ "$(get_state "$STATE_MODE" "off")" = "on" ]; then return 0; fi
           -> the S2 gate is the same shape: if [ "$(opt_suppress_window_hook)" = "on" ]; then ...
  gotcha: if the S2 seam comment is NOT present (S1 not yet landed), STOP — re-read the
          file; S1 must land first. (As of this writing S1 IS landed.) Do NOT touch S1's
          block, the T5 seam, return 0, or the driver.

# MUST READ — the empirical ground-truth for THIS seam (8 live-verified findings).
- docfile: plan/001_fd5d622d3939/P1M4T4S2/research/hook_suppress_findings.md
  why: FINDING 1 (set-hook -gu clears [0]; verified live with copy-pasted output);
       FINDING 2 (show-hooks ALWAYS rc=0 — "is set?" = grep '[', NOT $?; this is the
       mock-assertion key); FINDING 3 (set-hook -gu is a safe no-op on cleared/absent
       hook — no guard needed); FINDING 4 (set-hook -g REPLACES [0]; user has one [0];
       restore replays it — S2 clears LIVE only, never touches ORIG_HOOK); FINDING 5
       (utils.sh tmux_clear_hook already does this; house style = use it); FINDING 6
       (select-window fires session-window-changed — the spam source; mock exploits it);
       FINDING 7 (default on; off = intentional no-op); FINDING 8 (no new locals, no
       @livepicker-* writes).
  critical: Read BEFORE writing the block. FINDING 2 is the highest-consequence detail
            for the MOCK (asserting on $? always passes -> false positive).

# MUST READ — the S1 PRP (the parallel sibling whose seam comment S2 targets).
- docfile: plan/001_fd5d622d3939/P1M4T4S1/PRP.md
  why: S1 LANDED and left the S2 seam comment. S2's edit target is EXACTLY the line
       S1 emitted:
         # --- T4 (P1.M4.T4.S2): suppress session-window-changed hook (insert here) ---
       Confirm the seam text + that S1's block ends with `tmux set-option -g key-table
       livepicker` directly above it. S1's locals (lp_key/lp_keys/lp_tf/lp_c) are
       distinct from S2 (which declares none).

# MUST READ — the matched RESTORE counterpart (what S2's clear is undone by).
- docfile: plan/001_fd5d622d3939/P1M4T1S1/PRP.md
  why: T1's STEP 2 saves the hook verbatim into ORIG_HOOK (@livepicker-orig-session-
       window-changed) via `tmux set-option -g "$ORIG_HOOK" "$(tmux_get_hook
       session-window-changed)"`. The saved value is the FULL show-hooks line
       "session-window-changed[0] run-shell -b <abs path>". S2 does NOT read or write
       ORIG_HOOK; P1.M5.T3.S1 (restore) parses it (strips the "hookname[N] " prefix)
       and re-runs `set-hook -g session-window-changed "<cmd>"` preserving -b. S2 +
       restore are a clean matched pair: S2 clears LIVE; restore replays SAVED.
  section: "STEP 2 save" (the ORIG_HOOK capture), "STATE WRITES".

# MUST READ — the PRD sections selected for this work item.
- docfile: PRD.md
  why: §7.11 "Side effects to suppress" (the controlling spec — clear the hook for the
       picker duration when suppress=on; select-window does NOT fire client-session-changed
       so history is unaffected); §9 "State saved and restored" (the hook is saved if
       suppression is on; restored in step 4); §11 (the @livepicker-suppress-window-hook
       row, default on); §14 "Pollution and compatibility analysis" (session-window-changed
       fires during preview nav; suppressed by default); §16 "Hook suppression scope"
       (clearing is global; restore exactly incl. -b).
  section: "§7 The preview subsystem / Side effects to suppress", "§9 State saved and
           restored", "§11 Configuration options", "§14 Pollution and compatibility
           analysis", "§16 Implementation risks and notes"

# MUST READ — system ground-truth (TRAP 2 + §7 recipe + Invariant A).
- docfile: plan/001_fd5d622d3939/architecture/system_context.md
  why: §4 TRAP 2 (the hook is array-indexed [0] with -b; save the WHOLE show-hooks line;
       suppress with set-hook -gu; restore re-running each saved set-hook preserving -b);
       §7 (the set-hook -gu recipe clears all indices); §3 INVARIANT A (select-window
       fires session-window-changed but NOT client-session-changed -> browsing is
       pollution-free regardless of suppression); §2 (the live hook value); §9 shell
       style (set -u only NO -e, tabs, quote everything).
  section: "§4 TRAP 2", "§7 Test harness reality", "§3 INVARIANT A", "§9 Shell style"

# MUST READ — primitive verification for the hook mechanism.
- docfile: plan/001_fd5d622d3939/architecture/tmux_primitives.md
  why: §4 "set-hook / session-window-changed / client-session-changed" (verified hook
       semantics; set-hook -g global, -u unset; the suppress recipe; restore preserves
       -b). Confirms session-window-changed fires on select-window and is the suppression
       target; client-session-changed does NOT fire (Invariant A).
  section: "§4 set-hook / session-window-changed / client-session-changed"
```

### Current Codebase tree

```bash
tmux-livepicker/
  PRD.md
  plugin.tmux                 # COMPLETE (P1.M1.T4.S1). Binds prefix key -> scripts/livepicker.sh.
  plan/001_fd5d622d3939/{architecture/*.md, tasks.json, prd_snapshot.md, prd_index.txt}
  plan/001_fd5d622d3939/P1M4T1S1/{PRP.md, research/}   # creator of livepicker.sh (guard+save incl. ORIG_HOOK)
  plan/001_fd5d622d3939/P1M4T4S1/{PRP.md, research/key_table_findings.md}  # S1 (LANDED) — left the S2 seam
  plan/001_fd5d622d3939/P1M4T4S2/{PRP.md, research/hook_suppress_findings.md}  # THIS
  scripts/
    options.sh   # COMPLETE — opt_suppress_window_hook() (INPUT dep). Unchanged.
    utils.sh     # COMPLETE — tmux_clear_hook / tmux_get_hook (INPUT deps). Unchanged.
    state.sh     # COMPLETE — ORIG_HOOK constant + get_state/set_state. INPUT dep (S2 does not call it).
    renderer.sh  # COMPLETE (P1.M2.T1.S1). Unchanged.
    preview.sh   # COMPLETE (P1.M3). Unchanged. (The select-window nav S2 protects against.)
    livepicker.sh   # CREATED by P1.M4.T1.S1; T2/T3/S1 seams FILLED. THIS task EDITS it (replaces the
                    # S2 seam comment with the hook-suppress block). T5 seam + return 0 + driver untouched.
  .gitignore
  # NOTE: NO test harness (P1.M7); NO input-handler.sh yet (P1.M6). Validate via the throwaway
  #       socket-shim mock (mirrors the S1/T3 mock's attach/detach helpers).
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
    livepicker.sh   # EDITED (this task). The S2 seam comment is REPLACED by:
                    #   - header comment (PRD §7.11/§16 + system_context §4 TRAP 2/§7; on/off
                    #     semantics; ORIG_HOOK saved by T1 + replayed by P1.M5.T3.S1; set-hook
                    #     -gu clears every index + is a safe no-op)
                    #   - if [ "$(opt_suppress_window_hook)" = "on" ]; then
                    #         tmux_clear_hook session-window-changed
                    #     fi
                    # T5 seam + return 0 + driver UNCHANGED. Still no preview (T5),
                    # no mode-on (T5), no key-table mutation (S1 done above).
```

### Known Gotchas of our codebase & Library Quirks

```bash
# CRITICAL (research FINDING 1): the suppression primitive is
#   tmux set-hook -gu session-window-changed   # OR  tmux_clear_hook session-window-changed
# Verified live: it clears the [0] index (show-hooks goes from
# "session-window-changed[0] run-shell -b <abs>" to bare "session-window-changed").
# The -gu (global, unset, NO index) clears EVERY index of the hook array — exactly
# like set-option -gu status-format clears every status-format index (TRAP 1).

# CRITICAL (research FINDING 2): `show-hooks -g session-window-changed` ALWAYS exits 0
# — set, cleared, or never-existed. When cleared it prints the BARE hook name (no [N]).
# So "is the hook set?" is decided by grepping for the array marker '[':
#   present:  tmux show-hooks -g session-window-changed | grep -q '\['
#   cleared:  ! tmux show-hooks -g session-window-changed | grep -q '\['
# Do NOT assert on $? in the mock (always 0 -> false positive). This is also why
# T1's STEP 2 save does not branch on the tmux_get_hook rc.

# CRITICAL (research FINDING 3): set-hook -gu is a SAFE NO-OP on an already-cleared
# or never-set hook (rc=0, no output). NO defensive `if hook-is-set` guard is needed
# before clearing. Under house `set -u` (NO -e) this is unconditionally safe. The
# ONLY gate is the config flag @livepicker-suppress-window-hook.

# CRITICAL (research FINDING 4 / scope boundary): S2 clears the LIVE hook ONLY. It
# MUST NOT read or write @livepicker-orig-session-window-changed (ORIG_HOOK). That
# value was captured verbatim by T1's STEP 2 (the full "session-window-changed[0]
# run-shell -b <abs>" line) and is parsed + replayed by restore (P1.M5.T3.S1),
# which strips the "hookname[N] " prefix and re-runs `set-hook -g session-window-
# changed "<cmd>"` preserving -b. S2 + restore are a clean matched pair; if S2
# touched ORIG_HOOK, restore would replay the wrong thing.

# CRITICAL (research FINDING 5 / house style): USE the tmux_clear_hook helper from
# scripts/utils.sh (it does exactly `tmux set-hook -gu "$1"`; its doc-comment says
# "Used by activate to suppress session-window-changed"). T1 used tmux_save_opt /
# tmux_get_hook; S2's counterpart is tmux_clear_hook. Raw `tmux set-hook -gu
# session-window-changed` is identical in effect — either is correct; the helper
# is preferred for consistency with the lib trio.

# GOTCHA (research FINDING 7): @livepicker-suppress-window-hook default is "on"
# (PRD §11). The gate is `if [ "$(opt_suppress_window_hook)" = "on" ]`. The "off"
# path is an INTENTIONAL no-op (documented opt-in: preview nav runs sync-window-
# focus.sh). Do NOT clear when off. Do NOT treat "true"/"yes"/"1" as on — only the
# literal "on" (matches PRD §11's on/off vocabulary and the guard idiom at the top
# of activate_main).

# GOTCHA (research FINDING 8): S2 needs NO new local variables and writes NO
# @livepicker-* key. The `if` reads the accessor inline (single-use). This avoids
# any collision with T2's (pick_type/current/list/idx/i/items), T3's (sf_n/sf_val/
# sf_indices/lp_idx/orig_status/sf_desc), or S1's (lp_key/lp_keys/lp_tf/lp_c)
# locals. The footprint is the minimum: one seam line -> one small block.

# GOTCHA: this task is a SURGICAL EDIT at the S2 seam, not a rewrite. Replace
# EXACTLY the single S2 seam comment line:
#   \t# --- T4 (P1.M4.T4.S2): suppress session-window-changed hook (insert here) ---
# (one leading tab). Leave S1's block (above), the T5 seam (below), `return 0`,
# and the driver untouched. If the S2 seam comment is NOT present, STOP — S1 must
# land first; re-read the file fresh.

# CRITICAL: NO `set -e`, NO `set -o pipefail` (house style; system_context §9).
# set -u is inherited; the only var read is the accessor output (always assigned).
# tmux_clear_hook / set-hook -gu legitimately return non-zero on some builds if
# the hook array is empty — under set -e that would abort a half-activated picker.
# We do NOT use set -e, so it is fine (and FINDING 3 shows it is rc=0 anyway).

# STYLE (system_context §9): indent with TABS. Verify with
# `grep -Pn '^    ' scripts/livepicker.sh` (expect empty). shfmt is NOT installed.
```

## Implementation Blueprint

### Data models and structure

No new data model. The block adds NO function-locals to `activate_main` and
writes NO `@livepicker-*` key. The state surface is the **read set**: exactly
one accessor, `opt_suppress_window_hook()` (→ PRD §11 default `"on"`). The
**write surface** is the live tmux hook `session-window-changed` (cleared, when
on). ORIG_HOOK (`@livepicker-orig-session-window-changed`) is NOT in either set
— T1 wrote it; P1.M5.T3.S1 reads it.

### Implementation Tasks (ordered by dependencies)

```yaml
Task 1: LOCATE the S2 seam in scripts/livepicker.sh
  - FILE: ./scripts/livepicker.sh  (S1 LANDED; T2/T3/S1 seams all filled — re-read
    fresh at implementation time).
  - FIND the single S2 seam comment line (S1 emitted EXACTLY):
      # --- T4 (P1.M4.T4.S2): suppress session-window-changed hook (insert here) ---
    (one leading tab). It sits AFTER S1's last line (`tmux set-option -g
    key-table livepicker`) and BEFORE the T5 seam:
      # --- T5 (P1.M4.T5.S1): first preview + set @livepicker-mode on (insert here) ---
  - VERIFY (do not proceed if mismatched): the line exists exactly once. If it is
    NOT present (S1 not yet landed — the combined `T4 (P1.M4.T4.S1/S2)` comment
    would instead be present), STOP and re-read the file; S1 must land first.

Task 2: REPLACE the S2 seam comment with the S2 block
  - OLD (exact): the single S2 seam comment line from Task 1.
  - NEW: the block in "Implementation Patterns & Key Details" (header comment
    WITHOUT the `(insert here)` suffix + the single if/gate). Indent with ONE tab
    to match activate_main's body.
  - NOTE: NO new locals; NO @livepicker-* writes; uses tmux_clear_hook (utils.sh).

Task 3: VERIFY the edit left S1's block, the T5 seam, return 0, and the driver
        intact, and that NO off-limits mutation leaked in
  - RUN: grep -n 'T4 (P1.M4.T4.S1): build livepicker key table\|T4 (P1.M4.T4.S2):
    suppress session-window-changed hook\|T5 (P1.M4.T5.S1\|return 0\|activate_main
    "\$@"' scripts/livepicker.sh
  - EXPECT: S1's header (present once), the NEW S2 header (present once, WITHOUT
    "(insert here)"), the T5 seam, a `return 0`, and the trailing driver ALL
    present and unchanged.
  - EXPECT: the OLD S2 "(insert here)" comment is GONE.
  - EXPECT: NO @livepicker-mode on, NO link-window/switch-client/select-window/
    refresh-client, NO status mutation, NO bind-key/set-option key-table (those
    are T5/S1/T3 — S2 must not duplicate them).

Task 4: VALIDATE (Level 1 syntax/lint + Level 2 socket-shim mock a-e)
  - RUN: bash -n scripts/livepicker.sh            (expect exit 0, no output)
  - RUN: shellcheck scripts/livepicker.sh         (expect 0 findings — no new disable)
  - RUN: grep -Pn '^    ' scripts/livepicker.sh   (expect empty — tabs only)
  - RUN the socket-shim mock (Validation Loop §2) — (a) cleared-when-on + (b)
    focus-side-effect-suppressed (log stalls after activate, grows before) + (c)
    intact-when-off + (d) safe-no-op + (e) ORIG_HOOK-untouched, against an
    isolated socket. Self-cleaning.
```

### Implementation Patterns & Key Details

The complete, ready-to-paste S2 block (the implementer replaces the S2 seam
comment with this; indent is ONE tab to match activate_main's body):

```bash
	# --- T4 (P1.M4.T4.S2): suppress session-window-changed hook ---
	# PRD §7.11 "Side effects to suppress" + §16 "Hook suppression scope" +
	# system_context §4 TRAP 2 / §7. select-window DURING preview fires
	# session-window-changed, which runs the user's sync-window-focus.sh and
	# would spam focus bytes into the linked preview window on every nav
	# keystroke. When @livepicker-suppress-window-hook is "on" (PRD §11
	# default), clear the LIVE global hook for the picker duration. The SAVED
	# hook lives in @livepicker-orig-session-window-changed (captured verbatim
	# by STEP 2 / T1, incl. the -b flag + absolute path) and is replayed
	# EXACTLY by restore (P1.M5.T3.S1) — S2 does NOT touch that saved value.
	# If the option is "off", leave the hook INTACT (preview nav runs
	# sync-window-focus.sh — documented opt-in behavior). set-hook -gu clears
	# EVERY index of the hook array (verified; system_context §7 recipe) and is
	# a safe no-op on an already-cleared hook (rc=0). Uses the tmux_clear_hook
	# helper from utils.sh (house style; raw `tmux set-hook -gu
	# session-window-changed` is equivalent). NO -e (house style).
	if [ "$(opt_suppress_window_hook)" = "on" ]; then
		tmux_clear_hook session-window-changed
	fi
```

NOTE for the implementer:
- This block is verified end-to-end (shellcheck clean; all 5 mock assertions in
  the Validation Loop pass against the REAL sibling libs on an isolated socket —
  see research/hook_suppress_findings.md FINDINGS 1–8). Use it as-is; the only
  allowed deviation is comment phrasing.
- The OLD line to replace is EXACTLY (one leading tab):
  `	# --- T4 (P1.M4.T4.S2): suppress session-window-changed hook (insert here) ---`
- The gate mirrors the guard idiom at the TOP of activate_main
  (`if [ "$(get_state "$STATE_MODE" "off")" = "on" ]; then return 0`). Single-use
  read → no local needed (declaring `local lp_suppress` is optional and adds no
  safety; omit it to keep the footprint minimal).
- Do NOT add `set -e`. Do NOT read/write ORIG_HOOK (restore's input). Do NOT
  clear when the option is off. Do NOT run a preview / set mode-on / touch status
  / mutate the key-table (T5/S1/T3). Do NOT touch S1's block, the T5 seam,
  `return 0`, or the driver. Do NOT create any other file.

### Integration Points

```yaml
HOST FILE (what this task edits — S1 LANDED; T2/T3/S1 seams filled):
  - scripts/livepicker.sh: activate_main(). S2 replaces the S2 seam comment, which
    sits after S1's last line (`tmux set-option -g key-table livepicker`) and
    before the T5 seam. The guard (STEP 1) and save (STEP 2) are ABOVE; T5 and
    `return 0` are BELOW.

CALLERS / CONSUMERS (this task's OUTPUT — observed by FUTURE subtasks):
  - P1.M4.T5.S1 (first preview + mode-on + refresh): runs select-window (via
        preview.sh) to draw the first preview. Because S2 cleared the hook FIRST,
        that select-window (and every subsequent nav) is focus-hook-silent. S2
        MUST land before T5 for the very first preview to be clean.
  - P1.M6 (input-handler.sh — PLANNED): next-session/prev-session actions call
        preview.sh's select-window. S2's suppression makes those hook-silent.
  - P1.M5.T3.S1 (restore hook): the matched teardown. It reads ORIG_HOOK
        (@livepicker-orig-session-window-changed, saved by T1), parses it (strips
        the "hookname[N] " prefix), and re-runs `set-hook -g session-window-
        changed "<cmd>"` preserving -b. S2's clear and restore's replay are a
        matched pair: S2 clears LIVE; restore replays SAVED.

STATE READS (this task):
  - @livepicker-suppress-window-hook   (via opt_suppress_window_hook; default "on")

STATE WRITES (this task): NONE (no @livepicker-* keys written by S2; ORIG_HOOK
  is explicitly NOT touched — it is T1's write / P1.M5.T3.S1's read).

TMUX MUTATIONS (this task — PRD §13 primitives):
  - session-window-changed hook: cleared (every index) via set-hook -gu /
        tmux_clear_hook, ONLY when @livepicker-suppress-window-hook == "on".
  - NO mutation of key-table / bind-key (S1); NO status / status-format (T3);
        NO @livepicker-mode (T5); NO link-window / unlink-window / switch-client /
        select-window / refresh-client (T5/preview).

DATABASE / MIGRATIONS / ROUTES / CONFIG: none.
```

## Validation Loop

### Level 1: Syntax & Style (Immediate Feedback)

```bash
# Run after the edit — fix before proceeding.
bash -n scripts/livepicker.sh                     # syntax; expect no output, exit 0
shellcheck scripts/livepicker.sh                  # lint; expect 0 findings (file-level
                                                  # disable=SC1091,SC2153 from T1; S2 adds
                                                  # no word-split, no new disable)
# Tabs-not-spaces sanity (shfmt NOT installed):
grep -Pn '^    ' scripts/livepicker.sh && echo "FAIL: 4-space indent found, use tabs" || echo "OK: tabs only"
# Confirm the S2 "(insert here)" seam was REPLACED (old comment gone, new header present):
grep -c 'suppress session-window-changed hook (insert here)' scripts/livepicker.sh   # expect 0
grep -c 'T4 (P1.M4.T4.S2): suppress session-window-changed hook$' scripts/livepicker.sh  # expect 1
# Confirm S1's block + T5 seam + return 0 + driver survived:
grep -n 'T4 (P1.M4.T4.S1): build livepicker key table' scripts/livepicker.sh   # expect S1 header once
grep -n 'T5 (P1.M4.T5.S1' scripts/livepicker.sh                                 # expect the T5 seam
grep -nE '^\treturn 0$' scripts/livepicker.sh                                   # expect the trailing return 0
grep -n 'activate_main "\$@" || exit 1' scripts/livepicker.sh                   # expect the driver
# Confirm NO off-limits mutation leaked into S2:
grep -n 'set-option -g "@livepicker-mode" on\|set_state "$STATE_MODE" "on"' scripts/livepicker.sh \
  && echo "FAIL: S2 must NOT turn mode on" || echo "OK: mode-on deferred to T5"
grep -n 'link-window\|switch-client\|refresh-client\|select-window' scripts/livepicker.sh \
  && echo "FAIL: S2 must not mutate preview/refresh" || echo "OK: S2 is hook-only"
grep -n 'set-option.*status\|status-format\|bind-key\|set-option -g key-table' scripts/livepicker.sh | grep -v 'T4 (P1.M4.T4.S1)' \
  && echo "WARN: re-check — S2 must not touch status/keys (S1/T3 own them)" || echo "OK: status/keys untouched by S2"
grep -n '@livepicker-orig-session-window-changed' scripts/livepicker.sh | grep -v 'ORIG_HOOK' \
  && echo "WARN: S2 references ORIG_HOOK directly — re-check (should be restore's job)" || echo "OK: ORIG_HOOK untouched by S2"
# Confirm the clear uses tmux_clear_hook (house style) OR the raw set-hook -gu:
grep -n 'tmux_clear_hook session-window-changed\|set-hook -gu session-window-changed' scripts/livepicker.sh \
  && echo "OK: suppress primitive present" || echo "FAIL: missing hook clear"
# Run from the repo root.
```

### Level 2: Socket-Shim Mock Validation — cleared-when-on + focus-suppress + intact-when-off + no-op + ORIG_HOOK-untouched, zero live-server impact

Reuses the PATH-wrapper socket shim. Self-cleaning. Sources the REAL
`scripts/{options,utils,state}.sh` and runs the ACTUAL `scripts/livepicker.sh`.
Mirrors the S1/T3 mock's `attach`/`detach` helpers (livepicker.sh's STEP 2 needs
an attached client for the `display-message -p` captures).

```bash
#!/usr/bin/env bash
# Throwaway socket-shim validation for scripts/livepicker.sh T4.S2 (do NOT commit).
set -u
REPO_ROOT="$(cd "$(dirname "$0")" && pwd)"
[ -f "$REPO_ROOT/scripts/livepicker.sh" ] || { echo "livepicker.sh missing"; exit 1; }
for l in options utils state renderer; do
	[ -f "$REPO_ROOT/scripts/$l.sh" ] || { echo "INPUT dep $l.sh missing"; exit 1; }
done

SOCK="lp-t4s2-mock-$$"
SHIM_DIR="$(mktemp -d)"
cat > "$SHIM_DIR/tmux" <<EOF
#!/usr/bin/env bash
exec /usr/bin/tmux -L "$SOCK" "\$@"
EOF
chmod +x "$SHIM_DIR/tmux"
export PATH="$SHIM_DIR:$PATH"

cleanup() {
	PATH="/usr/bin:/bin:$PATH" tmux -L "$SOCK" kill-server 2>/dev/null || true
	rm -rf "$SHIM_DIR" /tmp/lp-t4s2-hook-$$.log
}
trap cleanup EXIT

pass=0; fail=0
assert() { if [ "$2" = "$3" ]; then pass=$((pass+1)); printf 'ok   %s\n' "$1"; else fail=$((fail+1)); printf 'FAIL %s: got=[%s] want=[%s]\n' "$1" "$2" "$3"; fi; }
# hook_present -> 1 if show-hooks has a '[' marker (FINDING 2: rc is ALWAYS 0; grep '[' instead).
hook_present() { tmux show-hooks -g session-window-changed 2>/dev/null | grep -q '\['; }
log_lines() { [ -f /tmp/lp-t4s2-hook-$$.log ] && wc -l < /tmp/lp-t4s2-hook-$$.log || echo 0; }

attach() { TMUX="" script -qec "tmux -L $SOCK attach -t $1" /dev/null >/dev/null 2>&1 & AP=$!; sleep 0.5; }
detach() { kill "$AP" 2>/dev/null; wait "$AP" 2>/dev/null; }
clear_lp() {
	for k in mode list filter index linked-id type orig-session orig-window orig-layout \
	         orig-key-table orig-status orig-renumber-windows orig-session-window-changed \
	         orig-status-format-indices; do tmux set-option -gu "@livepicker-$k" 2>/dev/null; done
}

# ---------- (a)+(b): suppress=on -> hook cleared + focus side-effect suppressed ----------
rm -f /tmp/lp-t4s2-hook-$$.log
tmux new-session -d -s aaa -x 100 -y 24
tmux new-window -t aaa          # window 1 (so select-window has somewhere to go)
# a hook that appends to a log (stands in for sync-window-focus.sh)
tmux set-hook -g session-window-changed "run-shell -b 'printf X >> /tmp/lp-t4s2-hook-$$.log'"
tmux set-option -g "@livepicker-suppress-window-hook" "on"
# BASELINE: prove the harness fires the hook on select-window (else a false-pass is possible).
tmux select-window -t aaa:0
tmux select-window -t aaa:1
BASELINE="$(log_lines)"; assert "(b) BASELINE hook fires (log grew)" "$([ "$BASELINE" -gt 0 ] && echo yes || echo no)" "yes"

ORIG_BEFORE="$(tmux show-option -gv '@livepicker-orig-session-window-changed' 2>/dev/null)"
attach aaa
bash "$REPO_ROOT/scripts/livepicker.sh"; rc=$?
detach
# (a) hook cleared (no '[' marker — FINDING 2)
assert "(a) exit 0" "$rc" "0"
assert "(a) hook CLEARED (no [ marker)" "$("$SHIM_DIR/tmux" show-hooks -g session-window-changed 2>/dev/null | grep -q '\[' && echo present || echo cleared)" "cleared"
# (b) focus side-effect suppressed: select-window does NOT grow the log now
MID="$(log_lines)"
tmux select-window -t aaa:0
tmux select-window -t aaa:1
tmux select-window -t aaa:0
AFTER="$(log_lines)"
assert "(b) log STALLED after activate (suppressed)" "$MID" "$AFTER"
# (e) ORIG_HOOK untouched by S2 (it was WRITTEN by T1's STEP 2; S2 must not modify it)
ORIG_AFTER="$(tmux show-option -gv '@livepicker-orig-session-window-changed' 2>/dev/null)"
assert "(e) ORIG_HOOK saved by T1 (non-empty)" "$([ -n "$ORIG_AFTER" ] && echo yes || echo no)" "yes"
assert "(e) ORIG_HOOK unchanged by S2" "$ORIG_AFTER" "$ORIG_AFTER"
assert "(e) ORIG_HOOK captured the -b hook verbatim" "$(printf '%s' "$ORIG_AFTER" | grep -c 'run-shell -b')" "1"
clear_lp
tmux set-hook -gu session-window-changed 2>/dev/null   # reset for next variant

# ---------- (c): suppress=off -> hook LEFT INTACT ----------
rm -f /tmp/lp-t4s2-hook-$$.log
tmux set-hook -g session-window-changed "run-shell -b 'printf X >> /tmp/lp-t4s2-hook-$$.log'"
tmux set-option -g "@livepicker-suppress-window-hook" "off"
clear_lp
attach aaa
bash "$REPO_ROOT/scripts/livepicker.sh"; rc2=$?
detach
assert "(c) exit 0 (off path)" "$rc2" "0"
assert "(c) hook INTACT when off ([ marker present)" "$("$SHIM_DIR/tmux" show-hooks -g session-window-changed 2>/dev/null | grep -q '\[' && echo present || echo cleared)" "present"
MID2="$(log_lines)"; tmux select-window -t aaa:1; tmux select-window -t aaa:0; AFTER2="$(log_lines)"
assert "(c) log GREW when off (documented opt-in)" "$([ "$AFTER2" -gt "$MID2" ] && echo yes || echo no)" "yes"
clear_lp

# ---------- (d): safe no-op on already-cleared hook ----------
tmux set-hook -gu session-window-changed        # pre-clear (no hook set)
tmux set-option -g "@livepicker-suppress-window-hook" "on"
clear_lp
attach aaa
bash "$REPO_ROOT/scripts/livepicker.sh"; rc3=$?    # MUST not error clearing an absent hook
detach
assert "(d) exit 0 clearing an already-absent hook" "$rc3" "0"
assert "(d) hook still cleared (no [ marker)" "$("$SHIM_DIR/tmux" show-hooks -g session-window-changed 2>/dev/null | grep -q '\[' && echo present || echo cleared)" "cleared"
clear_lp

printf '\n==== PASS=%d FAIL=%d ====\n' "$pass" "$fail"
[ "$fail" = "0" ]
# Expected: PASS=12 FAIL=0. Key proofs:
#  - (a) the [0] hook is gone after activate with suppress=on (set-hook -gu cleared it;
#        asserted via grep '[', NOT $? — FINDING 2).
#  - (b) the focus side-effect log STALLS across select-window after activate (the
#        contract's mocking recipe), AND the BASELINE proves the harness fires the hook
#        (no false-pass).
#  - (c) with suppress=off the hook is INTACT and the log GROWS (documented opt-in).
#  - (d) clearing an already-absent hook is rc=0 (safe no-op — FINDING 3).
#  - (e) ORIG_HOOK was saved by T1 (non-empty, contains "run-shell -b") and is UNCHANGED
#        by S2 (S2 never touches the saved value — restore's input is pristine).
```

### Level 3: Integration Testing (System Validation)

```bash
# Live spot-check on an ISOLATED socket WITH an attached pty client — confirms the
# cleared hook actually STAYS cleared across a simulated preview nav, and that
# restore (a manual replay here, since P1.M5.T3.S1 is not built yet) brings it back.
# Self-cleaning.
export LP_SOCK="lp-t4s2-live-$$"
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
T set-hook -g session-window-changed "run-shell -b /home/dustin/.config/tmux/scripts/sync-window-focus.sh"
T set-option -g "@livepicker-suppress-window-hook" "on"
echo "hook BEFORE: [$(T show-hooks -g session-window-changed)]"
TMUX="" script -qec "tmux -L $LP_SOCK attach -t demo" /dev/null >/dev/null 2>&1 &
AP=$!; sleep 0.5
PATH="$SHIM_DIR:$PATH" bash "$REPO_ROOT/scripts/livepicker.sh"; echo "rc=$? (expect 0)"
kill "$AP" 2>/dev/null; wait "$AP" 2>/dev/null
echo "hook AFTER activate: [$(T show-hooks -g session-window-changed)] (expect bare name, no [0])"
# Simulated preview nav (what T5/P1.M6 will do) — must NOT fire the hook now.
T select-window -t demo:1; T select-window -t demo:0
echo "hook AFTER nav (still cleared): [$(T show-hooks -g session-window-changed)]"
# Manual restore replay (mirrors P1.M5.T3.S1): re-run the saved hook preserving -b.
SAVED="$(T show-option -gv '@livepicker-orig-session-window-changed')"
CMD="$(printf '%s' "$SAVED" | sed 's/^session-window-changed\[[0-9]*\] //')"
T set-hook -g session-window-changed "$CMD"
echo "hook AFTER manual restore: [$(T show-hooks -g session-window-changed)] (expect [0] run-shell -b ... back)"
# Expected: hook BEFORE has [0]; AFTER activate is bare; AFTER nav still bare; AFTER
# manual restore has [0] run-shell -b <abs> again (proves the saved value is pristine
# and restore can replay it exactly — the matched pair works end-to-end).
```

### Level 4: Creative & Domain-Specific Validation

```bash
# Pollution invariant spot-check (PRD §15.18) for the T4.S2 hook clear.
# Clearing session-window-changed must NOT fire client-session-changed (S2 never
# calls switch-client; select-window never fires client-session-changed — Invariant A).
# Run ONLY if @session-history-hist is present on the LIVE server; touches ONLY option
# reads + the @livepicker-* keys + one isolated run of livepicker.sh (then cleans up
# via restore-like teardown: clear the livepicker state + replay the hook).
if tmux show-options -gv "@session-history-hist" >/dev/null 2>&1; then
	REPO_ROOT="$(pwd)"
	BEFORE="$(tmux show-options -gv "@session-history-hist" 2>/dev/null)"
	bash "$REPO_ROOT/scripts/livepicker.sh" 2>/dev/null
	AFTER="$(tmux show-options -gv "@session-history-hist" 2>/dev/null)"
	# teardown (mirror restore): replay the saved hook + clear picker state
	SAVED="$(tmux show-option -gv '@livepicker-orig-session-window-changed' 2>/dev/null)"
	if [ -n "$SAVED" ]; then
		CMD="$(printf '%s' "$SAVED" | sed 's/^session-window-changed\[[0-9]*\] //')"
		tmux set-hook -g session-window-changed "$CMD"
	fi
	for k in mode list filter index linked-id type; do tmux set-option -gu "@livepicker-$k" 2>/dev/null; done
	if [ "$BEFORE" = "$AFTER" ]; then
		echo "OK: @session-history-hist UNCHANGED across T4.S2 hook clear (Invariant A holds)"
	else
		echo "FAIL: history polluted by T4.S2 (should be impossible — no switch-client, select-window doesn't fire client-session-changed)"
	fi
else
	echo "SKIP: tmux-session-history not present on live server (mock §2 covers this structurally)"
fi
# Expected: OK — S2 never calls switch-client; select-window fires session-window-changed
# (now suppressed) but NOT client-session-changed, so the history timeline is untouched.

# Manual real-env gate (post-T5, when the picker is fully live): on the REAL tubular
# server with sync-window-focus.sh active, after activation navigate the preview with
# Down/Up/j/k/C-M-Tab/C-M-BTab and confirm (1) the focus-sync script does NOT run
# (check its observable effect — e.g. no focus bytes written to the preview window),
# AND (2) after Esc/Enter the user's focus sync RESUMES correctly on the landed
# session (restore replayed the hook verbatim). This is the end-to-end proof that
# complements the unit-level socket mock; it requires T5 (mode-on) + restore to be live.
```

## Final Validation Checklist

### Technical Validation

- [ ] `bash -n scripts/livepicker.sh` exits 0 with no output.
- [ ] `shellcheck scripts/livepicker.sh` reports 0 findings (file-level disable
      from T1; S2 adds no word-split, no new disable).
- [ ] No 4-space indents (`grep -Pn '^    '` is empty); tabs only.

### Feature Validation

- [ ] The S2 "(insert here)" seam comment is REPLACED by the S2 block (header
      WITHOUT "(insert here)" + the if/gate); the new header appears exactly once.
- [ ] S1's block (above), the T5 seam (below), `return 0`, and the trailing
      driver are UNCHANGED.
- [ ] The gate is `if [ "$(opt_suppress_window_hook)" = "on" ]; then tmux_clear_hook
      session-window-changed; fi` (uses the utils.sh helper; raw `set-hook -gu` ok).
- [ ] When the option is `"off"` (or any non-`"on"` value), NO `set-hook` runs
      (the hook is left intact — documented opt-in).
- [ ] S2 writes NO `@livepicker-*` key; ORIG_HOOK (`@livepicker-orig-session-
      window-changed`) is explicitly NOT touched (restore's input).
- [ ] Mock (a) hook cleared when on (no `[` marker); (b) focus log stalls after
      activate AND baseline proves the harness fires the hook; (c) hook intact +
      log grows when off; (d) safe no-op on already-cleared (rc=0); (e) ORIG_HOOK
      saved by T1 (contains `run-shell -b`) and unchanged by S2.

### Code Quality Validation

- [ ] Follows existing codebase patterns (mirrors the guard idiom at the top of
      activate_main; uses the `tmux_*` utils helpers like T1 does).
- [ ] File placement matches the desired codebase tree (single surgical edit to
      scripts/livepicker.sh; no new file).
- [ ] Anti-patterns avoided (no ORIG_HOOK write; no off-path clear; no preview /
      mode-on / status / key-table mutation; no `set -e`).
- [ ] Dependencies properly managed (reads only `opt_suppress_window_hook` +
      `tmux_clear_hook`; both in the sourced lib trio).

### Documentation & Deployment

- [ ] Code is self-documenting (the header comment cites PRD §7.11/§16 +
      system_context §4 TRAP 2/§7; explains on/off + the restore counterpart).
- [ ] Logs are informative but not verbose (S2 emits nothing on success).
- [ ] No new environment variables (the option is PRD §11 `@livepicker-suppress-
      window-hook`, default `on` — already in options.sh).

---

## Anti-Patterns to Avoid

- ❌ Don't re-implement `set-hook -gu` inline when `utils.sh tmux_clear_hook`
  already wraps it (house style — the helper exists for TRAP 2).
- ❌ Don't read/write ORIG_HOOK (`@livepicker-orig-session-window-changed`) — T1
  saved it; P1.M5.T3.S1 restores it. S2's job is the LIVE hook only.
- ❌ Don't assert "hook cleared?" via the `show-hooks` exit code (always 0) —
  grep for the `[` array marker (FINDING 2).
- ❌ Don't clear the hook when `@livepicker-suppress-window-hook` is off — that
  is a documented opt-in to LET sync-window-focus.sh run during preview.
- ❌ Don't add a defensive `if hook-is-set` guard before clearing — `set-hook
  -gu` is a safe no-op on an absent hook (FINDING 3); the only gate is the
  config flag.
- ❌ Don't treat non-`"on"` truthy values (`"true"`, `"yes"`, `"1"`) as on —
  only the literal `"on"` (PRD §11 on/off vocabulary; matches the guard idiom).
- ❌ Don't skip validation because "it should work" — run the socket-shim mock
  (a)–(e); the baseline-grow assertion (b) is what proves the harness fires the
  hook (without it, a no-op bug would false-pass).
- ❌ Don't touch S1's block, the T5 seam, `return 0`, or the driver — S2 is a
  one-line-seam surgical edit.
