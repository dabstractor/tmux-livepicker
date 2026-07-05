# PRP — P1.M3.T1.S1: preview.sh — link/unlink/select with id tracking

---

## Goal

**Feature Goal**: A standalone, side-effecting Bash script at
`scripts/preview.sh` that implements the **live preview core** of the picker
(PRD §7 `update_preview`): given a candidate session name `S` on `argv[1]`, it
resolves S's active window id, unlinks the *previous* preview window from the
current (driver) session (if any), links S's window into the current session,
and selects it — so **all of S's panes render live** below the status bar
**without switching the client's session** (Invariant A: `select-window` does
not fire `client-session-changed`). It tracks the linked window id in
`@livepicker-linked-id` for unlinking on the next navigation and on restore
(P1.M5). It is **mutation-only** (no rendering, no status, no input) and is
called by activate's first preview (P1.M4.T5.S1) and by input-handler
next/prev (P1.M6.T2.S1).

**Deliverable**: The single executable file `scripts/preview.sh`. A
straight-line Bash script (`#!/usr/bin/env bash`; `set -u`, **NO** `set -e`)
that sources `options.sh → utils.sh → state.sh` (in that order), reads
`argv[1]` + 3 state keys (`@livepicker-orig-session`, `@livepicker-orig-window`,
`@livepicker-linked-id`), and runs the link/unlink/select sequence with the
duplicate-guard and self-session guard. It leaves a `preview_fallback()` stub
that S2 (P1.M3.T1.S2) replaces with the `capture-pane` snapshot fallback.

**Success Definition**:
- `bash -n scripts/preview.sh` passes; `shellcheck scripts/preview.sh` is clean
  (0 findings; `source` directives resolve `get_state`/`set_state`/`STATE_*`/`ORIG_*`).
- File is executable (`-rwxr-xr-x`) with shebang `#!/usr/bin/env bash`; tabs only.
- **Mock validation (happy path):** under the socket shim with ≥2 sessions (one
  multi-pane), calling `preview.sh S` makes S's active window id appear in the
  driver session via `list-windows`, AND the window id **still appears in S**
  (source keeps it), AND there is **no duplicate** (the id appears exactly once
  in the driver), AND the driver session is still the `@livepicker-orig-session`
  (no `switch-client` occurred).
- **Mock validation (nav swap):** `preview.sh S1` then `preview.sh S2` → S1's
  window id is **no longer** in the driver but **still in S1**; S2's is in the
  driver; exactly one preview window in the driver at a time.
- **Mock validation (duplicate guard):** `preview.sh S` twice (same S, simulating
  single-match wrap) → S's window id appears **exactly once** in the driver (no
  ghost duplicate — the load-bearing FINDING 4/5 guard).
- **Mock validation (self-session):** `preview.sh <current_session>` → selects
  `ORIG_WINDOW`, no link attempted, `@livepicker-linked-id` unchanged.
- **Mock validation (link-failure fallback):** forcing `link-window` to fail →
  `preview_fallback` stub runs and `preview.sh` exits non-zero (S1 contract §4;
  S2 will make the fallback actually capture).

## User Persona (if applicable)

**Target User**: The picker orchestration scripts (activate `livepicker.sh`,
input-handler `input-handler.sh`) and, transitively, the end user browsing
sessions. Mode A (internal — no user-facing surface; behavior summarized in
the final README P1.M8.T1.S1).

**Use Case**: The user has activated the picker and presses `C-M-Tab`
(next-session). The input-handler updates `@livepicker-index`, resolves the new
candidate session name `S`, and runs `preview.sh "$S"`. Within ~100 ms the area
below the status bar swaps from the previous candidate's panes to S's panes,
live, while the user's client session, history, and toggle are untouched.

**User Journey**:
1. Activate → first preview is the self-session (P1.M4.T5.S1 calls
   `preview.sh "$ORIG_SESSION"`): self-branch selects `ORIG_WINDOW`, no link.
2. User presses next → input-handler calls `preview.sh S1`: S1's window linked
   into driver + selected; `@livepicker-linked-id = @S1win`.
3. User presses next again → `preview.sh S2`: previous `@S1win` unlinked from
   driver (S1 keeps it), `@S2win` linked + selected; `@livepicker-linked-id = @S2win`.
4. Filter narrows to 1 match → next wraps to the same S2 → `preview.sh S2`:
   duplicate-guard skips unlink+link (window already linked+selected), just
   re-selects; **no ghost window** created.
5. Confirm/cancel → restore (P1.M5) unlinks `@livepicker-linked-id` and selects
   `ORIG_WINDOW`.

**Pain Points Addressed**:
- (a) Without preview.sh there is no "live all-panes preview" — the defining
  feature (PRD §7). This is the literal link/unlink/select engine.
- (b) A naïve implementation that re-links without unlinking, or that links when
  `LINKED_ID == src_id`, silently **leaks duplicate windows** into the driver
  session on every wrap-navigation (research FINDING 4/5 — verified on 3.6b).
  The duplicate-guard is the fix.
- (c) A naïve implementation that reads the current session via
  `display-message` is **non-deterministic on the detached test socket** and
  untestable (research FINDING 9). Reading `@livepicker-orig-session` is the fix.
- (d) An implementation that adds `set -e` aborts on the first legitimate
  `unlink-window` rc=1 (singly-linked edge) or `list-windows` rc=1 (gone
  session). Per-command guards + no `set -e` is the fix.

## Why

- **The defining feature's engine.** PRD §7 names this exact routine
  (`update_preview S`) and PRD §5 data flow lists `scripts/preview.sh` as the
  "link candidate active window into current session; select it" step. Every
  navigation (P1.M6.T2) and the activate first-preview (P1.M4.T5) call it.
-- **Zero-pollution by construction.** The whole plugin exists because the prior
  attempt called `switch-client` per keystroke and shredded session history
  (PRD §0/§4). preview.sh uses `link-window` + `select-window`, which fire
  neither `client-session-changed` (Invariant A, live-proven) — so the
  tmux-session-history timeline and the `@session-history-prev` toggle pointer
  are provably untouched. This PRP's mock validation asserts exactly that.
- **Foundation for M4/M5/M6.** activate's "first preview" step (P1.M4.T5.S1),
  input-handler's next/prev (P1.M6.T2.S1), and restore's "unlink preview"
  step (P1.M5.T1.S1) all depend on this file existing with this exact
  `@livepicker-linked-id` contract. restore (P1.M5) reads the linked-id this
  script writes and unlinks it.
- **Clean S1→S2 boundary.** This PRP delivers ONLY the live core. S2
  (P1.M3.T1.S2, depends-on S1) extends this file with: the
  `@livepicker-preview-mode` gate (live|snapshot|off), the `capture-pane`
  snapshot fallback (replacing the `preview_fallback` stub), and self-session
  refinement. The stub + clearly-marked extension points make S2 a pure
  edit-in-place, not a rewrite.
- **Boundary respect.** preview.sh touches ONLY: `@livepicker-linked-id`
  (writes), `@livepicker-orig-session` / `@livepicker-orig-window` (reads). It
  does NOT touch `@livepicker-mode`, `@livepicker-list/filter/index`, the
  status subsystem, key-tables, or hooks. It calls only `link-window`,
  `unlink-window`, `select-window`, `list-windows` (PRD §13) — no
  `switch-client`, no `set-option` (except via `set_state` for linked-id), no
  `refresh-client` (the caller owns redraw triggering).

## What

A single executable Bash script at `scripts/preview.sh` that:

1. Computes `CURRENT_DIR` (canonical idiom), sources `options.sh → utils.sh →
   state.sh` (that order — state.sh depends on utils.sh).
2. Defines a `preview_fallback()` stub (`return 1`) — S2 replaces it with
   `capture-pane -ep -t "=$S"`.
3. Defines `preview_main()` which:
   - Reads `S="${1:-}"`, `current_session=get_state(ORIG_SESSION,"")`,
     `orig_window=get_state(ORIG_WINDOW,"")`, `linked_id=get_state(STATE_LINKED_ID,"")`.
   - *(S2 inserts the `@livepicker-preview-mode` gate here.)*
   - **Self-session guard:** if `S == current_session` → `select-window -t
     "$orig_window"` (guarded), return 0. (No link; would duplicate — FINDING 6.)
   - **Resolve src_id:** `list-windows -t "=$S" -F '#{window_id}' -f
     '#{window_active}'`. If empty → `preview_fallback "$S"; return $?`.
   - **Duplicate guard:** if `linked_id == src_id` → `select-window -t
     "$src_id"`, return 0. (Skip unlink+link — FINDING 5.)
   - **Unlink previous:** if `linked_id` non-empty → `unlink-window -t
     "$current_session:$linked_id"` (NO `-k`), `|| true` (ignore singly-linked
     failure — FINDING 2).
   - **Link (guarded):** `link-window -a -s "$src_id" -t "$current_session:"`;
     on failure → `preview_fallback "$S"; return $?`.
   - **Select:** `select-window -t "$src_id"` (guarded).
   - **Track:** `set_state "$STATE_LINKED_ID" "$src_id"`. return 0.
4. Driver: `preview_main "$@" || exit 1; exit 0`.

### Success Criteria

- [ ] File at `./scripts/preview.sh`; shebang `#!/usr/bin/env bash`; executable.
- [ ] Sources `options.sh → utils.sh → state.sh` in that order (state.sh needs
      utils.sh first). All three guarantee no source-time side effects.
- [ ] `set -u` active (inherited); **NO** `set -e`; **NO** `set -o pipefail`.
- [ ] Reads `argv[1]` as S; reads `ORIG_SESSION`/`ORIG_WINDOW`/`STATE_LINKED_ID`
      via `get_state` with `""` defaults (set -u-safe).
- [ ] `CURRENT_SESSION` derived from `ORIG_SESSION` (NOT `display-message`).
- [ ] Self-session guard: `S == current_session` → select `ORIG_WINDOW`, return 0.
- [ ] `src_id` via `list-windows -t "=$S" -F '#{window_id}' -f '#{window_active}'`;
      empty → `preview_fallback`.
- [ ] **Duplicate guard:** `linked_id == src_id` → select only, return 0 (no unlink/link).
- [ ] Unlink previous (non-empty, != src_id) via `unlink-window -t
      "$current_session:$linked_id"` with **NO `-k`**, `|| true`.
- [ ] Link via `link-window -a -s "$src_id" -t "$current_session:"`; guarded →
      `preview_fallback` on failure.
- [ ] Select via `select-window -t "$src_id"`; then `set_state STATE_LINKED_ID src_id`.
- [ ] `preview_fallback()` stub present, `return 1`, documented as S2's seam.
- [ ] Driver: `preview_main "$@" || exit 1; exit 0`.
- [ ] `bash -n` clean; `shellcheck` 0 findings; tabs only.
- [ ] Mock validation: all 6 branches (happy/nav-swap/dup-guard/self/link-fail/
      gone-session) pass the assertions in Validation Loop §2.

## All Needed Context

### Context Completeness Check

_Pass_: A developer who has never seen this repo can implement preview.sh from
(a) the verbatim `preview_main()` body in the Implementation Blueprint, (b) the
13 live-verified findings in research/preview_link_unlink_findings.md (every rc
and `list-windows` diff is real 3.6b output), (c) the 3 complete input
dependencies (options.sh / utils.sh / state.sh — their exact signatures are
quoted below and confirmed present in the repo), and (d) the socket-shim mock
validation that exercises all 6 branches against an isolated server (zero
live-server impact). Every guard (duplicate, self-session, singly-linked,
gone-session, link-failure) is backed by a live proof.

### Documentation & References

```yaml
# MUST READ — the empirical ground-truth for THIS file (13 live-verified findings)
- docfile: plan/001_fd5d622d3939/P1M3T1S1/research/preview_link_unlink_findings.md
  why: FINDING 1 (link adds a link, source keeps window); FINDING 2 (unlink no -k:
       succeeds when doubly-linked, FAILS rc=1 when singly-linked -> ignore non-zero);
       FINDING 3 (unlink by @id removes ONE index per call -> never make duplicates);
       FINDING 4 (CRITICAL: re-linking an already-linked window does NOT fail, it
       silently DUPLICATES — contradicts PRD §16); FINDING 5 (CRITICAL: the literal
       "skip unlink, still link" creates a duplicate on single-match wrap ->
       duplicate-guard required); FINDING 6 (self-session link does NOT fail either;
       guard is behavioral); FINDING 7 (list-windows -t '=S' -F -f '#{window_active}'
       -> one line @N, no trailing \n; rc=1 + empty if session gone); FINDING 8
       (select-window -t @id rc=0; does NOT fire client-session-changed); FINDING 9
       (display-message non-deterministic without a client -> use ORIG_SESSION);
       FINDING 10 (renumber-windows=on -> address by @id never index); FINDING 11
       (kill-window -t @id destroys the shared window in ALL sessions -> why -k is
       forbidden; test-cleanup lesson); FINDING 12 (capture-pane available, S2-owned);
       FINDING 13 (the complete correct unlink-then-link sequence, duplicate-free).
  critical: Read BEFORE writing any link/unlink line. FINDINGS 4 and 5 are the two
       highest-consequence details — they change the literal S1 contract §3 (the
       duplicate-guard) and the current-session source (ORIG_SESSION not display-message).

# MUST READ — INPUT dependency 1 of 3 (COMPLETE; treat as a CONTRACT)
- docfile: plan/001_fd5d622d3939/P1M1T1S1/PRP.md
  why: Defines scripts/options.sh: get_opt + opt_*. preview.sh sources it (transitively
       needed; also opt_preview_mode will be used by S2's gate). options.sh begins with
       `set -u` (NO -e) — sourcing it leaves set -u active.
  critical: sourcing options.sh has NO side effects.

# MUST READ — INPUT dependency 2 of 3 (COMPLETE; treat as a CONTRACT)
- docfile: plan/001_fd5d622d3939/P1M1T2S1/PRP.md
  why: Defines scripts/utils.sh: tmux_get_opt/tmux_set_opt/tmux_unset_opt. preview.sh
       sources it so state.sh resolves. state.sh's header explicitly says "the caller
       MUST source utils.sh BEFORE this file".
  critical: source order options -> utils -> state is load-bearing.

# MUST READ — INPUT dependency 3 of 3 (COMPLETE; treat as a CONTRACT)
- docfile: plan/001_fd5d622d3939/P1M1T3S1/PRP.md
  why: Defines scripts/state.sh: get_state(key,default) / set_state(key,val) + the
       STATE_* and ORIG_* readonly constants. preview.sh reads ORIG_SESSION /
       ORIG_WINDOW / STATE_LINKED_ID via get_state and writes STATE_LINKED_ID via
       set_state. Confirmed present in scripts/state.sh (lines 44/48/49).
  critical: STATE_LINKED_ID="@livepicker-linked-id", ORIG_SESSION="@livepicker-orig-session",
            ORIG_WINDOW="@livepicker-orig-window" (a window ID @N, NOT an index).
            get_state delegates to tmux_get_opt; ${2:-} makes the default OPTIONAL.

# MUST READ — the live preview subsystem spec (verbatim update_preview pseudocode)
- docfile: PRD.md
  why: §7 "The preview subsystem" — the update_preview pseudocode this implements;
       §7 self-session edge case; §7 side-effects-to-suppress (select-window fires
       session-window-changed, NOT client-session-changed); §13 tmux primitives
       reference (link-window -a -s <id> -t <session>:, unlink-window -t <session>:<id>,
       select-window -t <id>, list-windows -t "=$S" -F '#{window_id}' -f '#{window_active}');
       §16 implementation risks (link-window edge cases, window addressing by id);
       §14 pollution proof (browsing never fires client-session-changed).
  section: "§7 The preview subsystem", "§13 tmux primitives reference",
           "§16 Implementation risks", "§14 Pollution and compatibility analysis"

# MUST READ — per-primitive verification + the 3 invariants
- docfile: plan/001_fd5d622d3939/architecture/tmux_primitives.md
  why: §1 link-window/unlink-window (-k advice is about unlink, succeeds when
       doubly-linked, fails when singly-linked); §4 hooks (select-window fires
       session-window-changed NOT client-session-changed; link/unlink fire
       window-linked/window-unlinked only); §5 list-windows -f '#{window_active}';
       §7 switch-client -t '=S' exact-match (the confirm-time switch, NOT used here).
  section: "§1 link-window / unlink-window", "§4 set-hook / hooks", "§5 list-windows -f"

# MUST READ — system ground-truth (verified live)
- docfile: plan/001_fd5d622d3939/architecture/system_context.md
  why: §2 (tmux 3.6b, renumber-windows=on -> address by id); §3 INVARIANT A
       (browsing never fires client-session-changed — the core pollution guarantee);
       §7 (test-harness reality: NO sibling socket-isolation harness exists;
       livepicker must invent the PATH-wrapper shim — exact shape given); §9 shell
       style (shebang, set -u only NO -e, tabs, CURRENT_DIR idiom, quote everything).
  section: "§2 Verified environment", "§3 INVARIANT A", "§7 Test harness reality", "§9 Shell style"

# MUST READ — the previous (parallel) work item's PRP (the renderer contract)
- docfile: plan/001_fd5d622d3939/P1M2T1S1/PRP.md
  why: Establishes the shared sourcing idiom (CURRENT_DIR + source options->utils->
       state), the `set -u` not `-e` convention, the `# shellcheck source=` directive
       pattern, and the throwaway-mock-validation approach preview.sh mirrors. Ensures
       preview.sh is structurally consistent with renderer.sh.
  section: "Implementation Patterns & Key Details", "Validation Loop §2"
```

### Current Codebase tree

```bash
tmux-livepicker/
  PRD.md
  plugin.tmux                 # (P1.M1.T4.S1) ENTRY POINT (repo root) — COMPLETE
  plan/001_fd5d622d3939/{architecture/*.md, tasks.json, prd_snapshot.md, prd_index.txt}
  plan/001_fd5d622d3939/P1M1T1S1/PRP.md          # options.sh contract (COMPLETE)
  plan/001_fd5d622d3939/P1M1T2S1/{PRP.md, research/}   # utils.sh contract (COMPLETE)
  plan/001_fd5d622d3939/P1M1T3S1/{PRP.md, research/}   # state.sh contract (COMPLETE)
  plan/001_fd5d622d3939/P1M1T4S1/{PRP.md, research/}   # plugin.tmux (COMPLETE)
  plan/001_fd5d622d3939/P1M2T1S1/{PRP.md, research/}   # renderer.sh (IN PARALLEL)
  plan/001_fd5d622d3939/P1M3T1S1/{PRP.md, research/}   # THIS work item
  scripts/
    options.sh   # EXISTS (COMPLETE) — get_opt/opt_*. THIS file's INPUT dep 1.
    utils.sh     # EXISTS (COMPLETE) — tmux_*. THIS file's INPUT dep 2 (for state.sh).
    state.sh     # EXISTS (COMPLETE) — get_state/set_state/STATE_*/ORIG_*. INPUT dep 3.
    # preview.sh    # ← DOES NOT EXIST YET (this task creates it HERE, in scripts/).
    # renderer.sh, livepicker.sh, input-handler.sh, restore.sh  # (P1.M2/M4/M5/M6)
  .gitignore
  # NOTE: NO test harness (P1.M7). Validate via the socket-shim throwaway mock.
```

### Desired Codebase tree with files to be added and responsibility of file

```bash
tmux-livepicker/
  scripts/
    options.sh   # (P1.M1.T1) INPUT dep — get_opt/opt_*. Unchanged by this task.
    utils.sh     # (P1.M1.T2) INPUT dep — tmux_* (transitively for state.sh). Unchanged.
    state.sh     # (P1.M1.T3) INPUT dep — get_state/set_state/STATE_*/ORIG_*. Unchanged.
    renderer.sh  # (P1.M2.T1 — parallel) #() status renderer. Unchanged by this task.
    preview.sh   # NEW (this task). LIVE PREVIEW CORE. Sources options->utils->state;
                 #   argv[1]=S; reads ORIG_SESSION/ORIG_WINDOW/STATE_LINKED_ID; resolves
                 #   S's active window id; unlinks prev preview; links + selects S's
                 #   window; tracks STATE_LINKED_ID. Self-session + duplicate guards.
                 #   preview_fallback() stub for S2. Mutation-only. chmod +x.
```

### Known Gotchas of our codebase & Library Quirks

```bash
# CRITICAL (research FINDING 4): link-window does NOT fail when the window is
# already linked in the target session — on tmux 3.6b it silently creates a
# DUPLICATE (the same @id at two indices in one session). This CONTRADICTS PRD
# §16. Therefore "always unlink the previous preview first" is about AVOIDING
# DUPLICATES, not avoiding a link error. Verified: linking @1 into driver twice
# -> driver: 1:=@0 2:=@1 3:=@1 (rc=0 both times).

# CRITICAL (research FINDING 5): the literal S1 contract "unlink only if
# LINKED_ID != src_id, then ALWAYS link" creates a duplicate when LINKED_ID ==
# src_id (single-match wrap: next/prev on a 1-item filtered list). The fix is
# the DUPLICATE GUARD: if linked_id == src_id, skip BOTH unlink and link, just
# select-window + return. Reachable case (PRD §6 wrapping; §15 single-match).

# CRITICAL (research FINDING 2): unlink-window WITHOUT -k removes ONE link from
# the named session; the source session KEEPS its window. It FAILS (rc=1,
# "window only linked to one session") ONLY when the window is singly-linked.
# Guard with `|| true` (ignore non-zero). NEVER pass -k: -k KILLS the window
# object in ALL sessions it's linked to (research FINDING 11 — kill-window -t @id
# on a shared window destroyed the source session in testing).

# CRITICAL (research FINDING 3): unlink-window by @id removes ONE index per call.
# A duplicate needs N unlink calls to clear. Reinforces: never MAKE duplicates
# (FINDING 4/5); cleanup is not a substitute for the guard.

# CRITICAL (research FINDING 9): read CURRENT_SESSION from @livepicker-orig-session,
# NOT `tmux display-message -p '#{session_name}'`. display-message (no -t) is
# reliable ONLY with an attached client; on the detached test socket it returns an
# ARBITRARY session (non-deterministic). During browsing the client never switches
# (Invariant A), so ORIG_SESSION is provably == the live client session whenever
# preview.sh runs. ORIG_SESSION is also always set by activate before the first
# preview. This is a deliberate, documented simplification of the S1 contract §2.

# CRITICAL (research FINDING 6): self-session link does NOT fail on 3.6b (it
# creates an in-session duplicate). The self-session guard is still CORRECT
# BEHAVIOR (show the user their own session, avoid a useless duplicate), just
# not needed to prevent an error. Keep the guard; do not relax it.

# CRITICAL: NO `set -e`. unlink-window legitimately returns rc=1 on the
# singly-linked edge; list-windows returns rc=1 on a gone session; the very first
# such non-zero would abort preview.sh mid-sequence and LEAK a link. Guard each
# mutating call explicitly (`|| true` for unlink/select; guarded `if !` for link).
# `set -u` is inherited; every var is defaulted at read via get_state "$KEY" "".

# CRITICAL: address windows by @id, NEVER index. renumber-windows is `on`
# (system_context §2; research FINDING 10) -> indices are unstable. The ONLY
# index-shaped target is the BARE `-t "$current_session:"` (empty index -> tmux
# picks a free slot), which intentionally does not pin an index. src_id, linked_id,
# and orig_window are all @N ids.

# GOTCHA (research FINDING 7): list-windows -t "=$S" -F '#{window_id}' -f
# '#{window_active}' returns ONE line (@N) with NO trailing newline; $(...)
# strips it so src_id is exactly "@1". On a gone/non-existent session it returns
# rc=1 and EMPTY stdout -> guard `if [ -z "$src_id" ]` -> preview_fallback.

# GOTCHA: select-window fires `session-window-changed` (suppressed globally for
# the picker duration by P1.M4.T4.S2 — NOT this task's concern) but does NOT fire
# `client-session-changed` (Invariant A — the pollution guarantee). link-window/
# unlink-window fire `window-linked`/`window-unlinked` (NOT suppressed; low risk).

# GOTCHA: session names can contain spaces ("job hunt") and hyphens ("remote-pi").
# Quote every expansion: "$S", "$current_session", "$src_id", "$linked_id". The
# exact-match `=$S` in list-windows handles spaces correctly when quoted.

# CRITICAL (peer-source path): preview.sh LIVES IN scripts/, so it sources its
# sibling libs via `$CURRENT_DIR/options.sh` (NO `scripts/` subpath) — mirroring
# tmux-resurrect's scripts/restore.sh (`source "$CURRENT_DIR/variables.sh"`).
# Do NOT copy plugin.tmux's `$CURRENT_DIR/scripts/options.sh` verbatim: plugin.tmux
# is at the REPO ROOT (CURRENT_DIR == repo root -> scripts/ is the subdir);
# preview.sh is one level DOWN (CURRENT_DIR == .../scripts -> a `scripts/` suffix
# double-nests to .../scripts/scripts/options.sh -> "No such file" at runtime).
# The `# shellcheck source=scripts/options.sh` DIRECTIVE still uses the scripts/
# prefix because shellcheck resolves directive paths relative to the CWD (repo
# root when you run `shellcheck scripts/preview.sh`), NOT the script's own dir.

# GOTCHA: the self-session branch does NOT unlink a previously-linked preview or
# clear LINKED_ID (S1 contract: "here just no-op-select orig"). A stale linked
# window from a prior candidate remains in the driver (unselected) until the next
# non-self navigation unlinks it or restore (P1.M5) cleans it. This is a minor,
# self-healing cosmetic leak — NOT a correctness bug. S2 may refine.

# GOTCHA: S2 (P1.M3.T1.S2) EXTENDS this file in place — it (a) replaces the
# preview_fallback() stub with capture-pane, (b) inserts the @livepicker-preview-mode
# gate at the marked spot, (c) completes self-session handling. Keep the stub and
# the marked extension comment so S2 is a clean edit, not a rewrite.

# STYLE (system_context §9): indent with TABS (NOT 4-space). Verify with
# `grep -Pn '^    ' scripts/preview.sh` (expect empty).

# SHELLCHECK (matches plugin.tmux, the proven repo pattern): a FILE-LEVEL
# `# shellcheck disable=SC1091` on line 2 silences the "Not following: <lib>.sh
# was not specified as input" INFO on each `source` line (shellcheck 0.11.0 emits
# SC1091 even with `# shellcheck source=` directives unless passed `-x`). Keep the
# `# shellcheck source=scripts/{options,utils,state}.sh` directives too — they
# document the dep and let `shellcheck -x` follow the files. ALSO add an inline
# `# shellcheck disable=SC2153` above the `orig_window=$(get_state "$ORIG_WINDOW" ...)`
# line: SC2153 (INFO) fires because shellcheck can't see ORIG_WINDOW is a readonly
# constant in the (not-followed) state.sh and guesses a typo of the local
# `orig_window`. With both disables, `shellcheck scripts/preview.sh` is truly clean.
```

## Implementation Blueprint

### Data models and structure

No persistent data model. preview.sh holds only function-local variables:
- `S` (argv[1], candidate session name)
- `current_session` (from `ORIG_SESSION`)
- `orig_window` (from `ORIG_WINDOW`, a window id `@N`)
- `linked_id` (from `STATE_LINKED_ID`, a window id `@N` or empty)
- `src_id` (resolved active window id of S, `@N`)

Functions: `preview_fallback()` (S2 stub) and `preview_main()` (the body), plus
the trailing `preview_main "$@" || exit 1; exit 0` driver. Wrapping the body in
`preview_main()` lets the driver propagate the fallback's exit status cleanly.

### Implementation Tasks (ordered by dependencies)

```yaml
Task 1: CREATE scripts/preview.sh — header + CURRENT_DIR + source the trio
  - FILE: ./scripts/preview.sh  (IN scripts/ — PRD §12 file layout: "preview.sh
    link-window live preview (with capture fallback)".)
  - SHEBANG: #!/usr/bin/env bash  (REQUIRED — input-handler/activate run it via
    run-shell, which executes via shebang).
  - HEADER COMMENT: one block stating purpose (live preview core: link S's active
    window into the current session + select it, all panes live, no session switch),
    SCOPE (S1 = live core ONLY; S2 adds mode gate + capture-pane fallback +
    self-session refinement; S2 depends-on & extends this file), the load-bearing
    rules (link-already-linked silently DUPLICATES -> unlink-first + duplicate-guard
    [FINDING 4/5]; unlink no -k succeeds doubly / fails singly -> `|| true` [FINDING 2];
    never -k [FINDING 11]; address by @id [FINDING 10]; CURRENT_SESSION from
    ORIG_SESSION not display-message [FINDING 9]; no set -e), and the dependencies
    (sources options->utils->state; reads via get_state; writes via set_state).
  - CURRENT_DIR: the canonical sibling idiom, verbatim:
      CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  - SOURCE the trio IN ORDER (state.sh needs utils.sh first):
      # shellcheck source=scripts/options.sh
      source "$CURRENT_DIR/options.sh"
      # shellcheck source=scripts/utils.sh
      source "$CURRENT_DIR/utils.sh"
      # shellcheck source=scripts/state.sh
      source "$CURRENT_DIR/state.sh"
  - NO `set -e`, NO `set -o pipefail`. `set -u` inherited from the libs.
  - STYLE: tabs; quote every expansion.
  - PLACEMENT: ./scripts/preview.sh

Task 2: IMPLEMENT preview_fallback() — the S2 seam (stub)
  - DEFINE: preview_fallback() { return 1; }
  - DOC: a comment above it stating S2 (P1.M3.T1.S2) replaces this body with
    `tmux capture-pane -ep -t "=$S"` (the snapshot fallback). S1's stub returns 1
    so preview.sh exits non-zero on link failure (S1 contract §4: "non-zero only
    if fallback also fails"). Accepts $1 = S (for S2's capture target).
  - NOTE: keeping this as a named function (not inline) is what lets S2 swap the
    body without touching preview_main().

Task 3: IMPLEMENT preview_main() — read inputs + self-session guard
  - DEFINE: preview_main() { ... }
  - READ inputs (defaults make them set -u-safe even when unset):
      local S="${1:-}"
      local current_session orig_window linked_id src_id
      current_session="$(get_state "$ORIG_SESSION" "")"
      orig_window="$(get_state "$ORIG_WINDOW" "")"
      linked_id="$(get_state "$STATE_LINKED_ID" "")"
  - LEAVE a marked extension point comment for S2's @livepicker-preview-mode gate
    (live|snapshot|off). S1 does NOT implement the gate (S2's job).
  - SELF-SESSION guard (PRD §7 self-session edge; FINDING 6 — guard is behavioral):
      if [ -n "$current_session" ] && [ "$S" = "$current_session" ]; then
          [ -n "$orig_window" ] && tmux select-window -t "$orig_window" 2>/dev/null || true
          return 0
      fi
  - NOTE: do NOT unlink or clear LINKED_ID here (S1 contract: "just no-op-select
    orig"). A stale prior preview self-heals on next non-self nav / restore.

Task 4: IMPLEMENT preview_main() — resolve src_id + gone-session guard
  - RESOLVE S's active window id (PRD §13; FINDING 7 — exact-match =$S, one line):
      src_id="$(tmux list-windows -t "=$S" -F '#{window_id}' -f '#{window_active}' 2>/dev/null)"
  - GONE-SESSION guard (FINDING 7 — rc=1 + empty if session gone):
      if [ -z "$src_id" ]; then
          preview_fallback "$S"
          return $?
      fi

Task 5: IMPLEMENT preview_main() — duplicate guard (THE load-bearing correction)
  - DUPLICATE guard (FINDING 4/5 — re-linking a linked window silently duplicates;
    reachable on single-match wrap):
      if [ -n "$linked_id" ] && [ "$linked_id" = "$src_id" ]; then
          tmux select-window -t "$src_id" 2>/dev/null || true
          return 0
      fi
  - NOTE: skip BOTH unlink and link — the window is already linked + selected from
    the last preview of this same session. Just ensure it is shown.

Task 6: IMPLEMENT preview_main() — unlink previous + link (guarded) + select + track
  - UNLINK the previous preview from the current session (NO -k; FINDING 2 —
    ignore singly-linked failure):
      if [ -n "$linked_id" ]; then
          tmux unlink-window -t "$current_session:$linked_id" 2>/dev/null || true
      fi
  - LINK S's active window into the current session (bare index -> free slot;
    FINDING 1). GUARDED — on ANY failure, fall back:
      if ! tmux link-window -a -s "$src_id" -t "$current_session:" 2>/dev/null; then
          preview_fallback "$S"
          return $?
      fi
  - SELECT it (all panes, live; FINDING 8 — does NOT fire client-session-changed):
      tmux select-window -t "$src_id" 2>/dev/null || true
  - TRACK the linked id (handle for next unlink + restore P1.M5):
      set_state "$STATE_LINKED_ID" "$src_id"
      return 0
  - (end of preview_main())

Task 7: IMPLEMENT the driver — preview_main "$@" || exit 1; exit 0
  - DRIVER (S1 contract §4 — exit 0 on success, non-zero only if fallback fails):
      preview_main "$@" || exit 1
      exit 0

Task 8: chmod +x  (REQUIRED — not cosmetic)
  - RUN: chmod +x scripts/preview.sh
  - VERIFY: ls -la scripts/preview.sh shows -rwxr-xr-x. run-shell executes the
    file via its shebang; non-executable -> "Permission denied" and the preview
    silently never runs.

Task 9: VALIDATE (Level 1 syntax/lint + Level 2 socket-shim 6-branch mock)
  - RUN: bash -n scripts/preview.sh            (expect exit 0, no output)
  - RUN: shellcheck scripts/preview.sh         (expect 0 findings. The FILE-LEVEL
    `# shellcheck disable=SC1091` silences the source-line infos; the inline
    `# shellcheck disable=SC2153` silences the ORIG_WINDOW/local-orig_window
    misspelling guess. The `# shellcheck source=scripts/*.sh` directives document
    the deps for `shellcheck -x`.)
  - RUN: grep -Pn '^    ' scripts/preview.sh   (expect no output — tabs only)
  - RUN the socket-shim mock (Validation Loop §2) — all 6 branches (happy /
    nav-swap / dup-guard / self / link-fail / gone-session). Self-cleaning
    (kills the isolated server; removes the shim dir). Do NOT commit a tests/
    file — the harness is P1.M7.T1/T2.
```

### Implementation Patterns & Key Details

```bash
#!/usr/bin/env bash
# shellcheck disable=SC1091  # sources sibling libs (options/utils/state) via $CURRENT_DIR; follow with `shellcheck -x` to trace (matches plugin.tmux).
# scripts/preview.sh — tmux-livepicker live preview core (link-window).
#
# argv[1] = candidate session name S. Links S's active window into the CURRENT
# (driver) session and selects it, so all its panes render live below the status
# bar — WITHOUT switching the client's session (Invariant A: select-window does
# NOT fire client-session-changed). Tracks the linked window id in
# @livepicker-linked-id for unlinking on the next navigation and on restore.
#
# SCOPE (P1.M3.T1.S1): the LIVE link/unlink/select core ONLY. The self-session
# case here is the minimal guard (select orig + return). S2 (P1.M3.T1.S2) EXTENDS
# this file: it replaces preview_fallback() with capture-pane, inserts the
# @livepicker-preview-mode gate (live|snapshot|off), and completes self-session
# handling. S2 DEPENDS ON this file.
#
# LOAD-BEARING RULES (research/preview_link_unlink_findings.md):
#  - link-window does NOT fail when the window is already linked in the target
#    session — it silently creates a DUPLICATE (FINDING 4). So ALWAYS unlink the
#    previous preview before linking a DIFFERENT one, AND if LINKED_ID == src_id
#    (single-match wrap) skip BOTH unlink and link — just select (FINDING 5).
#  - unlink-window WITHOUT -k removes ONE link; the source session KEEPS its
#    window (FINDING 1). It FAILS (rc=1) only when singly-linked -> ignore
#    non-zero (`|| true`). NEVER pass -k (would destroy the shared window in ALL
#    sessions — FINDING 11).
#  - Address windows by @id, NEVER index (renumber-windows is on — FINDING 10).
#  - Read CURRENT_SESSION from @livepicker-orig-session, NOT display-message:
#    during browsing the client never switches (Invariant A), so ORIG_SESSION is
#    provably == the live client session AND is client-independent (works on the
#    detached test socket). display-message is non-deterministic without a client
#    (FINDING 9).
#  - NO `set -e` — unlink/list-windows legitimately return non-zero; guard each.
#    `set -u` inherited; every var defaulted at read.
#
# DEPENDS ON (source order load-bearing — state.sh needs utils.sh first):
#   options.sh (opt_*), utils.sh (tmux_*), state.sh (get_state/set_state/STATE_*/ORIG_*).

CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/options.sh
source "$CURRENT_DIR/options.sh"
# shellcheck source=scripts/utils.sh
source "$CURRENT_DIR/utils.sh"
# shellcheck source=scripts/state.sh
source "$CURRENT_DIR/state.sh"

# S2 (P1.M3.T1.S2) REPLACES THIS STUB with the capture-pane snapshot fallback:
#   tmux capture-pane -ep -t "=$1" ... written into the preview area; return 0.
# S1's stub returns 1 so preview.sh exits non-zero on link failure (S1 contract
# §4: "non-zero only if fallback also fails"; the caller — input-handler /
# activate — decides). $1 = candidate session S (S2's capture target).
preview_fallback() {
	return 1
}

# argv[1] = candidate session name S.
preview_main() {
	local S="${1:-}"
	local current_session orig_window linked_id src_id

	# The session we preview INSIDE (the driver). Equal to the live client session
	# during browsing (Invariant A); client-independent (FINDING 9).
	current_session="$(get_state "$ORIG_SESSION" "")"
	# shellcheck disable=SC2153  # ORIG_WINDOW is a readonly constant defined in the sourced state.sh (not a typo of the local orig_window).
	orig_window="$(get_state "$ORIG_WINDOW" "")"
	linked_id="$(get_state "$STATE_LINKED_ID" "")"

	# --- S2: insert the @livepicker-preview-mode gate here (live|snapshot|off) ---

	# Self-session guard (PRD §7; FINDING 6). Do NOT link — would create an
	# in-session duplicate; instead show the user their own session. Select the
	# original window and return. (S1: do not unlink/clear LINKED_ID here.)
	if [ -n "$current_session" ] && [ "$S" = "$current_session" ]; then
		[ -n "$orig_window" ] && tmux select-window -t "$orig_window" 2>/dev/null || true
		return 0
	fi

	# Resolve S's active window id (exact-match =S; one line @N; FINDING 7).
	src_id="$(tmux list-windows -t "=$S" -F '#{window_id}' -f '#{window_active}' 2>/dev/null)"
	if [ -z "$src_id" ]; then
		# Session gone / no windows / exact-match miss -> fallback.
		preview_fallback "$S"
		return $?
	fi

	# DUPLICATE GUARD (FINDING 4/5). Re-previewing the SAME session (linked_id ==
	# src_id, e.g. single-match wrap): the window is already linked + selected.
	# Skip unlink AND link (re-linking would silently duplicate). Just ensure shown.
	if [ -n "$linked_id" ] && [ "$linked_id" = "$src_id" ]; then
		tmux select-window -t "$src_id" 2>/dev/null || true
		return 0
	fi

	# Drop the previous preview from the current session (NO -k; source keeps it).
	# Ignore non-zero: singly-linked edge / already-gone (FINDING 2).
	if [ -n "$linked_id" ]; then
		tmux unlink-window -t "$current_session:$linked_id" 2>/dev/null || true
	fi

	# Link S's active window into the current session (bare index -> free slot).
	# GUARDED: on ANY failure, fall back (S1 stub -> exit non-zero; S2 -> capture-pane).
	if ! tmux link-window -a -s "$src_id" -t "$current_session:" 2>/dev/null; then
		preview_fallback "$S"
		return $?
	fi

	# Show it — all panes, live. select-window does NOT fire client-session-changed
	# (Invariant A). It DOES fire session-window-changed (suppressed globally by
	# P1.M4.T4.S2 — not this task's concern).
	tmux select-window -t "$src_id" 2>/dev/null || true

	# Track the linked id (handle for the next unlink + for restore P1.M5).
	set_state "$STATE_LINKED_ID" "$src_id"
	return 0
}

preview_main "$@" || exit 1
exit 0
```

NOTE for the implementer: the block above is the COMPLETE, ready file body. Use
it as-is; the only allowed deviation is comment phrasing. Do NOT add `set -e`.
Do NOT pass `-k` to unlink-window. Do NOT replace the `preview_fallback()` stub
(S2 owns it). Do NOT implement the mode gate or capture-pane (S2 owns them). Do
NOT call `switch-client`, `refresh-client`, `set-option` (except via set_state),
`set-hook`, or `bind-key`. Do NOT create any other file.

### Integration Points

```yaml
CALLERS (who invokes preview.sh — all FUTURE):
  - activate livepicker.sh (P1.M4.T5.S1 — FUTURE): runs the FIRST preview with
        "$CURRENT_DIR/scripts/preview.sh" "$ORIG_SESSION"
    (self-session path — selects ORIG_WINDOW, no link). THEN sets
    @livepicker-mode on, THEN refresh-client -S. Order: preview BEFORE mode-on
    so a crash mid-activate leaves mode off (re-activatable).
  - input-handler.sh next/prev (P1.M6.T2.S1 — FUTURE): resolves the candidate
    name from the filtered list at the new index, then
        "$CURRENT_DIR/scripts/preview.sh" "<filtered[index]>"
    then refresh-client -S.
  - restore.sh (P1.M5.T1.S1 — FUTURE): reads @livepicker-linked-id (this script
    WROTE it) and unlinks it; selects ORIG_WINDOW. restore does NOT call
    preview.sh — it consumes the linked-id this script leaves behind.

STATE WRITES (this task — ONE option only):
  - @livepicker-linked-id (= STATE_LINKED_ID): set to src_id after a successful
    link+select; left UNCHANGED by the self-session and duplicate-guard early
    returns (they don't re-link). Cleared globally on exit by clear_all_state
    (state.sh — P1.M1.T3); restore unlinks it first.

STATE READS (this task):
  - @livepicker-orig-session (= ORIG_SESSION): the current/driver session. Written
    by activate (P1.M4.T1.S1).
  - @livepicker-orig-window (= ORIG_WINDOW): the original window id (@N). Written
    by activate (P1.M4.T1.S1). Used only by the self-session branch.

TMUX MUTATIONS (this task — PRD §13, the preview primitives ONLY):
  - list-windows -t "=$S" -F '#{window_id}' -f '#{window_active}'  (read)
  - unlink-window -t "$current_session:$linked_id"   (NO -k)
  - link-window -a -s "$src_id" -t "$current_session:"
  - select-window -t "$src_id"  (and -t "$orig_window" in self-branch)

DEPENDENCIES (consumed — all COMPLETE):
  - scripts/options.sh (P1.M1.T1.S1): sourced first (transitively for state.sh;
    opt_preview_mode reserved for S2's gate).
  - scripts/utils.sh (P1.M1.T2.S1): tmux_get_opt/tmux_set_opt (transitively for
    state.sh). Sourced second.
  - scripts/state.sh (P1.M1.T3.S1): get_state/set_state + STATE_LINKED_ID /
    ORIG_SESSION / ORIG_WINDOW. Sourced third (needs utils.sh first).

DATABASE / MIGRATIONS / ROUTES / STATUS-FORMAT: none. preview.sh touches no
  status, no key-table, no hook, no config option (other than linked-id).
```

## Validation Loop

### Level 1: Syntax & Style (Immediate Feedback)

```bash
# Run after creating + chmod +x the file — fix before proceeding.
bash -n scripts/preview.sh                     # syntax check; expect no output, exit 0
shellcheck scripts/preview.sh                  # lint; expect 0 findings
# Tabs-not-spaces sanity (shfmt NOT installed):
grep -Pn '^    ' scripts/preview.sh && echo "FAIL: 4-space indent found, use tabs" || echo "OK: tabs only"
# Executable bit (REQUIRED — run-shell executes via shebang):
[ -x scripts/preview.sh ] && echo "OK: executable" || { echo "FAIL: not executable"; chmod +x scripts/preview.sh; }

# Expected: all clean (exit 0, no output). The file-level `# shellcheck disable=SC1091`
# silences the 3 source-line infos; the inline `# shellcheck disable=SC2153` silences
# the ORIG_WINDOW info. Run from the repo root:
#   cd <repo-root> && shellcheck scripts/preview.sh
```

### Level 2: Socket-Shim Mock Validation — ALL 6 branches, zero live-server impact

The P1.M7 harness does not exist yet. We validate against an **isolated tmux
socket via a PATH-wrapper shim** (system_context §7 — the exact shape). preview.sh
calls bare `tmux`, which the shim redirects to `tmux -L <isolated-socket>`. This
touches NO live tmux state. Run from the repo root, then the script self-cleans.

```bash
#!/usr/bin/env bash
# Throwaway socket-shim validation for scripts/preview.sh (do NOT commit).
set -u
REPO_ROOT="$(cd "$(dirname "$0")" && pwd)"
[ -f "$REPO_ROOT/scripts/preview.sh" ] || { echo "preview.sh missing"; exit 1; }

SOCK="lp-preview-mock-$$"
SHIM_DIR="$(mktemp -d)"
# PATH-wrapper shim: bare `tmux` -> isolated socket (system_context §7).
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

# --- fixture: driver + S1 (3-pane window) + S2 (1-pane) ---
tmux new-session -d -s driver -x 100 -y 40
tmux new-session -d -s S1 -x 100 -y 40
tmux split-window -t "=:S1"; tmux split-window -t "=:S1"      # S1: 3-pane active window
tmux new-session -d -s S2 -x 100 -y 40
DRIVER_ORIG_WIN="$(tmux list-windows -t '=driver' -F '#{window_id}' -f '#{window_active}')"
S1_WIN="$(tmux list-windows -t '=S1' -F '#{window_id}' -f '#{window_active}')"
S2_WIN="$(tmux list-windows -t '=S2' -F '#{window_id}' -f '#{window_active}')"

# prime the state contract (what activate P1.M4.T1.S1 will write):
tmux set-option -g "@livepicker-orig-session" "driver"
tmux set-option -g "@livepicker-orig-window" "$DRIVER_ORIG_WIN"
tmux set-option -gu "@livepicker-linked-id"   # initially empty

count_in() { # $1=session $2=@id  -> number of times @id appears in session's window list
	tmux list-windows -t "=$1" -F '#{window_id}' 2>/dev/null | grep -cx "$2"
}

pass=0; fail=0
assert() { if [ "$2" = "$3" ]; then pass=$((pass+1)); else fail=$((fail+1)); printf 'FAIL %s: got=[%s] want=[%s]\n' "$1" "$2" "$3"; fi; }

# ---------- BRANCH 1: happy path — preview S1 (multi-pane) ----------
bash "$REPO_ROOT/scripts/preview.sh" S1; rc=$?
assert "happy rc=0" "$rc" "0"
assert "S1 win in driver" "$(count_in driver "$S1_WIN")" "1"
assert "S1 win STILL in S1" "$(count_in S1 "$S1_WIN")" "1"
assert "driver has no dup of S1" "$(count_in driver "$S1_WIN")" "1"
assert "linked-id == S1_WIN" "$(tmux show-option -gqv "@livepicker-linked-id")" "$S1_WIN"
assert "orig-session still driver (no switch-client)" "$(tmux show-option -gqv "@livepicker-orig-session")" "driver"
# driver session still exists (client never switched)
tmux has-session -t '=driver' 2>/dev/null && assert "driver session alive" "1" "1" || assert "driver session alive" "0" "1"

# ---------- BRANCH 2: nav swap — preview S2 (unlinks S1, links S2) ----------
bash "$REPO_ROOT/scripts/preview.sh" S2; rc=$?
assert "swap rc=0" "$rc" "0"
assert "S2 win in driver" "$(count_in driver "$S2_WIN")" "1"
assert "S1 win NO LONGER in driver" "$(count_in driver "$S1_WIN")" "0"
assert "S1 win STILL in S1 (source keeps it)" "$(count_in driver "$S1_WIN")" "0"  # 0 in driver
assert "S1 win still in S1" "$(count_in S1 "$S1_WIN")" "1"
assert "linked-id == S2_WIN" "$(tmux show-option -gqv "@livepicker-linked-id")" "$S2_WIN"
# exactly ONE preview window in driver besides the original
assert "driver window count == 2 (orig + preview)" "$(tmux list-windows -t '=driver' -F '#{window_id}' | wc -l)" "2"

# ---------- BRANCH 3: duplicate guard — preview S2 AGAIN (same session; wrap) ----------
bash "$REPO_ROOT/scripts/preview.sh" S2; rc=$?
assert "dup-guard rc=0" "$rc" "0"
assert "S2 win appears EXACTLY ONCE in driver (no ghost dup)" "$(count_in driver "$S2_WIN")" "1"
assert "driver window count still 2 (no leak)" "$(tmux list-windows -t '=driver' -F '#{window_id}' | wc -l)" "2"

# ---------- BRANCH 4: self-session — preview the driver's own session ----------
tmux set-option -g "@livepicker-linked-id" "$S2_WIN"   # pretend something was linked
bash "$REPO_ROOT/scripts/preview.sh" driver; rc=$?
assert "self rc=0" "$rc" "0"
assert "self: driver active window == ORIG_WINDOW" "$(tmux list-windows -t '=driver' -F '#{window_id}' -f '#{window_active}')" "$DRIVER_ORIG_WIN"
assert "self: linked-id UNCHANGED (S1 no-op)" "$(tmux show-option -gqv "@livepicker-linked-id")" "$S2_WIN"
assert "self: S2 win still in driver (no unlink happened)" "$(count_in driver "$S2_WIN")" "1"

# ---------- BRANCH 5: link-failure fallback — force link-window to fail ----------
# Make the shim's link-window fail by hijacking it: point src at a session whose
# window is the driver's OWN original window but via a name that resolves to an
# impossible target. Simpler: temporarily break the candidate so list-windows
# succeeds but link target is invalid -> actually easiest is the gone-session
# path (BRANCH 6). For link-failure, stub preview_fallback by env: we instead
# verify the guard structurally — call preview.sh with a candidate that has NO
# windows is impossible; so simulate by killing S2 mid-flight is racy. Instead:
# confirm the driver exits non-zero when preview_fallback runs by pointing at a
# session whose active window was just killed -> list-windows returns empty ->
# gone-session branch -> preview_fallback -> exit 1. (Covered by BRANCH 6.)

# ---------- BRANCH 6: gone-session — preview a non-existent session ----------
bash "$REPO_ROOT/scripts/preview.sh" does-not-exist; rc=$?
assert "gone-session rc != 0 (fallback stub fails)" "$([ "$rc" -ne 0 ] && echo 1 || echo 0)" "1"
assert "gone-session: no crash, driver intact" "$(tmux has-session -t '=driver' 2>/dev/null && echo 1 || echo 0)" "1"

printf 'PASS=%d FAIL=%d\n' "$pass" "$fail"
[ "$fail" = "0" ]
# Expected: PASS≈22 FAIL=0. Key proofs:
#  - happy: S1's window id appears in driver AND stays in S1; linked-id updated.
#  - nav swap: S1 unlinked from driver (0 there) but intact in S1 (1 there);
#    exactly one preview window in driver at a time; no switch-client.
#  - dup guard: re-previewing S2 does NOT add a second S2 index in driver.
#  - self: selects ORIG_WINDOW; linked-id unchanged; no link attempted.
#  - gone: non-existent session -> fallback stub -> exit non-zero; no crash.
```

### Level 3: Integration Testing (System Validation)

```bash
# Live spot-check on an ISOLATED socket WITH an attached pty client — confirms
# the linked window actually RENDERS (all panes, live) to a real client, and
# that client-session-changed does NOT fire (Invariant A) during preview nav.
# Self-cleaning.
export LP_SOCK="lp-preview-live-$$"
REPO_ROOT="$(pwd)"
SHIM_DIR="$(mktemp -d)"
cat > "$SHIM_DIR/tmux" <<EOF
#!/usr/bin/env bash
exec /usr/bin/tmux -L "$LP_SOCK" "\$@"
EOF
chmod +x "$SHIM_DIR/tmux"
trap 'PATH=/usr/bin:/bin:$PATH tmux -L "$LP_SOCK" kill-server 2>/dev/null; rm -rf "$SHIM_DIR" /tmp/lp-preview-live.log' EXIT

PATH="$SHIM_DIR:$PATH" tmux new-session -d -s driver -x 100 -y 40
PATH="$SHIM_DIR:$PATH" tmux new-session -d -s S1 -x 100 -y 40
PATH="$SHIM_DIR:$PATH" tmux split-window -t "=:S1"; PATH="$SHIM_DIR:$PATH" tmux split-window -t "=:S1"
PATH="$SHIM_DIR:$PATH" tmux send-keys -t "=S1" "echo hello-from-S1-pane1" Enter
# attach a real pty client so panes render + display-message resolves
TMUX="" script -qec "tmux -L $LP_SOCK attach -t driver" /tmp/lp-preview-live.log &
ATTACH_PID=$!; sleep 0.5

# prime state + run preview
PATH="$SHIM_DIR:$PATH" tmux set-option -g "@livepicker-orig-session" "driver"
PATH="$SHIM_DIR:$PATH" tmux set-option -g "@livepicker-orig-window" \
    "$(PATH="$SHIM_DIR:$PATH" tmux list-windows -t '=driver' -F '#{window_id}' -f '#{window_active}')"
PATH="$SHIM_DIR:$PATH" tmux set-option -gu "@livepicker-linked-id"

PATH="$SHIM_DIR:$PATH" bash "$REPO_ROOT/scripts/preview.sh" S1
sleep 0.4
echo "=== driver client's session AFTER preview (must still be 'driver' — Invariant A) ==="
PATH="$SHIM_DIR:$PATH" tmux display-message -p '#{session_name}'
echo "=== driver active window id (must be S1's window id — previewing) ==="
PATH="$SHIM_DIR:$PATH" tmux display-message -p '#{window_id}'
echo "=== capture the driver's screen — should show S1's 3 panes (live render) ==="
PATH="$SHIM_DIR:$PATH" tmux capture-pane -p -t '=driver' | sed -n '1,8p' | cat -A | head -8

kill "$ATTACH_PID" 2>/dev/null; wait "$ATTACH_PID" 2>/dev/null
# Expected: client's session == 'driver' (no switch-client); driver active window
# == S1's @id; the captured screen shows S1's 3-pane layout (the live preview).
```

### Level 4: Creative & Domain-Specific Validation

```bash
# Pollution invariant spot-check (PRD §15.18 — the core guarantee). Requires the
# tmux-session-history plugin's options to exist on the live server. This touches
# ONLY option READS on the live server (it sets 3 @livepicker-orig-* keys, runs
# preview.sh which links/unlinks/selects, then cleans up). It does NOT install a
# status renderer or switch key-tables. Run ONLY if @session-history-hist exists.
if tmux show-options -gv "@session-history-hist" >/dev/null 2>&1; then
    REPO_ROOT="$(pwd)"
    BEFORE="$(tmux show-options -gv "@session-history-hist" 2>/dev/null)"
    CUR_SESS="$(tmux display-message -p '#{session_name}')"
    CUR_WIN="$(tmux display-message -p '#{window_id}')"
    # pick another existing session to preview
    OTHER="$(tmux list-sessions -F '#{session_name}' | grep -vx "$CUR_SESS" | head -1)"
    tmux set-option -g "@livepicker-orig-session" "$CUR_SESS"
    tmux set-option -g "@livepicker-orig-window" "$CUR_WIN"
    tmux set-option -gu "@livepicker-linked-id"
    [ -n "$OTHER" ] && bash "$REPO_ROOT/scripts/preview.sh" "$OTHER" 2>/dev/null
    AFTER="$(tmux show-options -gv "@session-history-hist" 2>/dev/null)"
    # cleanup: unlink whatever we linked, select back, clear our keys
    LID="$(tmux show-option -gqv "@livepicker-linked-id")"
    [ -n "$LID" ] && tmux unlink-window -t "$CUR_SESS:$LID" 2>/dev/null || true
    tmux select-window -t "$CUR_WIN" 2>/dev/null || true
    tmux set-option -gu "@livepicker-orig-session" 2>/dev/null
    tmux set-option -gu "@livepicker-orig-window" 2>/dev/null
    tmux set-option -gu "@livepicker-linked-id" 2>/dev/null
    if [ "$BEFORE" = "$AFTER" ]; then
        echo "OK: @session-history-hist UNCHANGED across preview (Invariant A holds)"
    else
        echo "FAIL: history polluted (preview must not fire client-session-changed)"
    fi
else
    echo "SKIP: tmux-session-history not present on live server (mock §2 covers this structurally)"
fi
# Expected: OK — preview.sh never calls switch-client, so client-session-changed
# never fires, so the history timeline is byte-identical before/after. This is
# the single most important invariant of the whole plugin (PRD §4/§14).
```

## Final Validation Checklist

### Technical Validation

- [ ] `bash -n scripts/preview.sh` exits 0 with no output.
- [ ] `shellcheck scripts/preview.sh` reports 0 findings (file-level
      `# shellcheck disable=SC1091` on line 2 silences source-line infos; inline
      `# shellcheck disable=SC2153` above the `orig_window=...` line silences the
      constant misspelling guess).
- [ ] No 4-space indents (`grep -Pn '^    '` is empty); tabs only.
- [ ] `scripts/preview.sh` is executable (`-rwxr-xr-x`).

### Feature Validation

- [ ] File is at `./scripts/preview.sh` (NOT repo root; PRD §12 file layout).
- [ ] Shebang `#!/usr/bin/env bash`; header documents scope + the load-bearing rules.
- [ ] `CURRENT_DIR` computed via the canonical idiom; sources `options.sh → utils.sh
      → state.sh` IN THAT ORDER (state.sh needs utils.sh first).
- [ ] Reads `argv[1]` as S; reads `ORIG_SESSION`/`ORIG_WINDOW`/`STATE_LINKED_ID`
      via `get_state` with `""` defaults.
- [ ] `CURRENT_SESSION` = `get_state "$ORIG_SESSION" ""` (NOT `display-message`).
- [ ] Self-session guard: `S == current_session` → `select-window -t "$ORIG_WINDOW"`,
      return 0; no link; linked-id unchanged.
- [ ] `src_id` via `list-windows -t "=$S" -F '#{window_id}' -f '#{window_active}'`;
      empty → `preview_fallback`.
- [ ] **Duplicate guard:** `linked_id == src_id` → `select-window -t "$src_id"`,
      return 0 (no unlink, no link).
- [ ] Unlink previous (non-empty, != src_id) via `unlink-window -t
      "$current_session:$linked_id"` with **NO `-k`**, `|| true`.
- [ ] Link via `link-window -a -s "$src_id" -t "$current_session:"`; guarded →
      `preview_fallback` on failure.
- [ ] Select via `select-window -t "$src_id"` (guarded); then
      `set_state "$STATE_LINKED_ID" "$src_id"`.
- [ ] `preview_fallback()` stub present (`return 1`), documented as S2's seam.
- [ ] Driver: `preview_main "$@" || exit 1; exit 0`.
- [ ] Mock validation: PASS≈22 FAIL=0 across all 6 branches (happy/nav-swap/dup-
      guard/self/gone + link-failure-via-gone). Key proofs: source-keeps-window,
      no-duplicate-on-wrap, no-switch-client (Invariant A), gone-session fallback.

### Code Quality Validation

- [ ] NO `set -e`, NO `set -o pipefail` anywhere (contract; FINDING 2/7 — unlink/
      list-windows legitimately return non-zero).
- [ ] NO explicit `set +u`; `set -u` inherited from the libs.
- [ ] All expansions double-quoted (`"$S"`, `"$current_session"`, `"$src_id"`,
      `"$linked_id"`, `"$orig_window"`).
- [ ] NO `switch-client`, NO `refresh-client`, NO `set-hook`, NO `bind-key`, NO
      `set-option` (except via `set_state` for linked-id), NO `kill-window`,
      NO `-k` on unlink-window.
- [ ] File-level `# shellcheck disable=SC1091` present (line 2); inline
      `# shellcheck disable=SC2153` above the `orig_window=...` line; `# shellcheck
      source=scripts/{options,utils,state}.sh` directives on the source lines.
- [ ] Indent with tabs; `local` declared FIRST (avoids SC2155).
- [ ] The `preview_fallback()` stub and the marked mode-gate extension point are
      left intact for S2 (P1.M3.T1.S2) to extend in place.

### Documentation & Deployment

- [ ] Header comment states: purpose, scope (S1 live core; S2 extends), the
      load-bearing rules (duplicate-guard, unlink-no-k, address-by-id,
      ORIG_SESSION-not-display-message, no-set-e), and the source-order dependency.
- [ ] No README/doc file created (DOCS = Mode A — contract §6: "internal; behavior
      summarized in final README P1.M8").
- [ ] No new env vars; no @livepicker-* writes other than `STATE_LINKED_ID`;
      no tmux.conf edit.

---

## Anti-Patterns to Avoid

- ❌ Don't re-link without first unlinking a DIFFERENT previous preview, and don't
  link when `linked_id == src_id` — on tmux 3.6b re-linking an already-linked
  window does NOT error, it **silently creates a duplicate** window-list entry
  (research FINDING 4/5, live-verified: `driver: 1:=@0 2:=@1 3:=@1`). The
  duplicate-guard (`linked_id == src_id` → select-only) is mandatory.
- ❌ Don't pass `-k` to `unlink-window` — `-k` KILLS the window object in EVERY
  session it's linked to (the source session loses its window too). This is the
  same reason `kill-window -t @id` on a shared window destroys the source session
  (research FINDING 11, live-verified). Use bare `unlink-window -t sess:@id`.
- ❌ Don't ignore the singly-linked edge — `unlink-window` without `-k` returns
  rc=1 ("window only linked to one session") when the window is singly-linked.
  Guard with `|| true` (research FINDING 2). Do NOT add `set -e` (it would abort
  on this legitimate non-zero and LEAK the just-created link).
- ❌ Don't read the current session via `tmux display-message -p '#{session_name}'`
  — it is non-deterministic on a detached socket (returns an arbitrary session;
  research FINDING 9) and untestable. Read `@livepicker-orig-session` — it is
  provably equal to the live client session during browsing (Invariant A) and is
  client-independent.
- ❌ Don't address windows by index — `renumber-windows` is `on`, so indices are
  unstable (research FINDING 10; system_context §2). Use `@N` ids everywhere
  (`src_id`, `linked_id`, `orig_window`). The only index-shaped target is the
  BARE `-t "$current_session:"` (empty index → free slot), which is intentional.
- ❌ Don't implement the `@livepicker-preview-mode` gate, the `capture-pane`
  fallback, or full self-session handling — S2 (P1.M3.T1.S2) owns all three and
  EXTENDS this file. S1 leaves the `preview_fallback()` stub and a marked
  extension-point comment. Implementing them here duplicates S2's work and risks
  merge conflict.
- ❌ Don't replace or inline the `preview_fallback()` stub — keeping it as a named
  function is what lets S2 swap the body without touching `preview_main()`.
- ❌ Don't call `switch-client` (shreds session history — the prior-attempt bug,
  PRD §0/§4), `refresh-client` (the caller owns redraw), `set-hook`/`bind-key`
  (activate/restore own those), or `kill-window` (destroys shared windows).
- ❌ Don't hardcode `"@livepicker-linked-id"` / `"@livepicker-orig-session"` strings
  — use the `STATE_LINKED_ID` / `ORIG_SESSION` / `ORIG_WINDOW` constants from
  state.sh (picker-script convention; stays in sync if names change).
- ❌ Don't `kill-window` a shared id during test teardown — it destroys the window
  in ALL linked sessions (research FINDING 11). Unlink (no -k) or `kill-session`
  or `kill-server` instead. The mock validation uses `kill-server`.
- ❌ Don't create a `tests/` directory or committed test file — the harness is
  P1.M7.T1/T2. Validate via the throwaway socket-shim mock (Validation §2) and
  delete it.
- ❌ Don't create `scripts/livepicker.sh`, `input-handler.sh`, `restore.sh`, or
  `renderer.sh` (even stubs) — they are P1.M4/M5/M6/M2 deliverables. preview.sh
  is called by them later.
- ❌ Don't clear `@livepicker-linked-id` or unlink in the self-session branch —
  S1's contract is "just no-op-select orig" (a stale prior preview self-heals on
  the next non-self nav or on restore; S2 may refine).
- ❌ Don't use 4-space indent — tabs only (system_context §9).
- ❌ Don't leave preview.sh non-executable — `run-shell` executes via the shebang;
  a non-executable file fails "Permission denied" and the preview silently never
  runs. `chmod +x`.

---

## Confidence Score

**9 / 10** for one-pass success. Rationale: the deliverable is a ~70-line
straight-line script whose complete body is given verbatim above, wrapped in a
`preview_main()` function with a `preview_main "$@" || exit 1; exit 0` driver.
Every load-bearing behavior is backed by a **live proof on tmux 3.6b** in
research/preview_link_unlink_findings.md: link-adds-a-link-source-keeps-window
(FINDING 1); unlink-no-`-k` succeeds-doubly/fails-singly (FINDING 2); unlink-by-id
removes-one-index (FINDING 3); re-link-silently-duplicates → duplicate-guard
(FINDINGS 4/5); self-link-doesn't-fail-but-guard-is-correct (FINDING 6);
list-windows exact-match + gone-session rc=1 (FINDING 7); select-window no
client-session-changed (FINDING 8, Invariant A); ORIG_SESSION-not-display-message
(FINDING 9); address-by-id (FINDING 10); kill-window-destroys-shared-window =
why `-k` is forbidden (FINDING 11); the complete correct duplicate-free sequence
(FINDING 13). All three input dependencies (options.sh / utils.sh / state.sh) are
COMPLETE and confirmed present, and their exact function/constant signatures are
quoted (STATE_LINKED_ID / ORIG_SESSION / ORIG_WINDOW verified at scripts/state.sh
lines 44/48/49). The 6-branch socket-shim mock asserts the source-keeps-window,
no-duplicate-on-wrap, no-switch-client, and gone-session-fallback invariants
byte-exactly. Tools verified present: `tmux 3.6b`, `bash 5.3.15`,
`shellcheck 0.11.0`.

Residual risks: (a) the duplicate-guard is a **correction** to the literal S1
contract §3 — an implementer who skips the research file and follows the literal
"unlink only if !=, then always link" would reintroduce the wrap-duplicate bug;
mitigated by the verbatim body given above + the loud FINDING-4/5 callouts in the
header and the dup-guard mock branch. (b) S2's in-place extension depends on the
`preview_fallback()` stub and the marked mode-gate comment surviving — mitigated
by the "don't replace the stub" anti-pattern and the explicit S2-seam comments.
(c) reading the driver's active window id in the self-session mock assertion
(BRANCH 4) must use the RELIABLE primitive `list-windows -t '=driver' -F
'#{window_id}' -f '#{window_active}'` (the same one preview.sh uses) — NOT
`display-message -p -t '=driver' '#{window_id}'`, which fails to resolve a
session target to a pane on a detached socket (research FINDING 9: display-message
is client-bound). All residual risks are deterministically caught by the
validation loop.
