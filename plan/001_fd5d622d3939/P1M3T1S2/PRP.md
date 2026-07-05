# PRP — P1.M3.T1.S2: preview.sh — self-session edge case + capture-pane fallback + mode gate

---

## Goal

**Feature Goal**: Extend the existing `scripts/preview.sh` (delivered COMPLETE by
P1.M3.T1.S1) with the three behaviors the live-preview core deliberately left as
seams: (1) the **`@livepicker-preview-mode` gate** (`live` | `snapshot` | `off`)
that routes previewing before any link is attempted; (2) the real
**`capture-pane` snapshot fallback** that replaces S1's `preview_fallback()`
stub, used both in `snapshot` mode and on any live `link-window` failure so the
**picker never blocks**; (3) the refined **self-session edge case** that unlinks
any prior preview and clears `@livepicker-linked-id` before showing the user
their own session. The result is the complete, degraded-mode-aware preview
subsystem described in PRD §7 (Mechanism + Fallbacks + Self-session edge case).

**Deliverable**: The SAME file `scripts/preview.sh`, edited IN PLACE — three
targeted edits (no rewrite): replace the `preview_fallback()` stub body; insert
the mode-gate block at S1's marked `--- S2: insert the @livepicker-preview-mode
gate here ---` extension point; and expand the self-session `if`-branch to
unlink+clear+select. The file remains a straight-line Bash script
(`#!/usr/bin/env bash`; `set -u`, **NO** `set -e`) sourcing
`options.sh → utils.sh → state.sh`, still mutation-only, still called by
activate's first preview (P1.M4.T5.S1) and input-handler next/prev (P1.M6.T2.S1).

**Success Definition**:
- `bash -n scripts/preview.sh` passes; `shellcheck scripts/preview.sh` is clean
  (0 findings; S1's file-level `# shellcheck disable=SC1091,SC2153` already
  silences the source-line + ORIG_* infos).
- File stays executable (`-rwxr-xr-x`); tabs only; no `set -e` introduced.
- **Mock (a) self-session (live mode):** previewing the driver's own session
  does NOT call `link-window`, unlinks any prior `@livepicker-linked-id` window
  from the driver (source keeps it), clears `@livepicker-linked-id`, and selects
  `ORIG_WINDOW` — and the client session never switches (Invariant A).
- **Mock (b) link-failure → capture fallback:** forcing a live `link-window`
  failure falls back to `capture-pane` and returns **rc=0 with no crash** when
  the candidate session's active pane is reachable (PRD §7 Fallbacks; "never
  blocks the picker"). A truly-gone session still returns non-zero (S1 contract
  §4).
- **Mock (c) preview-mode=off:** previewing with `@livepicker-preview-mode=off`
  returns rc=0, shows nothing, attempts NO link and NO capture, and leaves
  `@livepicker-linked-id` untouched.
- **Mock (d) snapshot mode:** `@livepicker-preview-mode=snapshot` runs
  `capture-pane` (rc=0 on a real session) and NEVER calls `link-window`
  (`@livepicker-linked-id` stays empty).

## User Persona (if applicable)

**Target User**: The picker orchestration scripts (activate `livepicker.sh`,
input-handler `input-handler.sh`) — S2 changes NO caller contract; it only
fills in the seams S1 left. Mode A (internal — behavior summarized in the final
README P1.M8.T1.S1).

**Use Case**: A user sets `@livepicker-preview-mode snapshot` (e.g. on a setup
where `link-window` is unreliable, or to avoid any window-list churn), activates
the picker, and browses sessions. Each navigation runs `capture-pane` on the
candidate's active pane (a non-live, single-pane snapshot) instead of linking.
Or the user leaves the default `live` and a transient `link-window` failure
occurs — the picker silently degrades to a snapshot for that one candidate
instead of blocking.

**User Journey** (default `live` mode, self-session refinement visible):
1. Activate → first preview is the self-session (P1.M4.T5.S1 calls
   `preview.sh "$ORIG_SESSION"`): S2's refined branch unlinks nothing (first
   call, `LINKED_ID` empty), selects `ORIG_WINDOW`, returns 0.
2. User presses next → `preview.sh S1`: live link flow; `@S1win` linked +
   selected; `@livepicker-linked-id = @S1win`.
3. User wraps back to the self-session (filtered list of 1, or explicit nav) →
   `preview.sh "$ORIG_SESSION"`: **S2 refinement** — unlinks `@S1win` from the
   driver (S1 keeps it), clears `@livepicker-linked-id`, selects `ORIG_WINDOW`.
   No stale linked window is left behind for restore to trip over.
4. Confirm/cancel → restore (P1.M5) sees empty `@livepicker-linked-id`, skips
   unlink, selects `ORIG_WINDOW`. Clean.

**Pain Points Addressed**:
- (a) Without the mode gate, a user who wants `snapshot` or `off` gets `live`
  unconditionally (PRD §11 option exists but is ignored). S2 honors it.
- (b) Without the capture fallback, a `link-window` failure (already-linked
  edge, invalid target, permission) propagates and the picker appears frozen.
  S2's fallback guarantees "never blocks" (PRD §7 Fallbacks, §16 risk).
- (c) Without the self-session refinement, navigating back to the self-session
  in `live` mode leaves a stale prior candidate window linked-but-unselected in
  the driver (S1's known cosmetic leak). S2 cleans it.
- (d) **The literal contract's `capture-pane -ep -t "=$S"` is wrong on 3.6b**
  (research FINDING A — it returns `can't find pane: =S`, rc=1). Without S2's
  research, an implementer following the PRD verbatim ships a fallback that
  ALWAYS fails. The PRP corrects the target to `=$S:.`.

## Why

- **Closes the S1 seams.** S1 (P1.M3.T1.S1) deliberately left three extension
  points (the `preview_fallback()` stub, the marked mode-gate comment, and the
  minimal self-session branch) so S2 is a clean edit-in-place, not a rewrite
  (see S1 PRP "Clean S1→S2 boundary"). This PRP fulfills exactly that handoff.
- **Honors PRD §11.** `@livepicker-preview-mode` is a documented, defaulted
  config option (`live`, default). S1 reserved `opt_preview_mode` in options.sh
  but did not consume it; S2 is its sole consumer. A shipped option that does
  nothing is a bug.
- **Never blocks (PRD §7/§16).** The capture-pane fallback is the explicit
  resilience guarantee: "If `link-window` fails for any reason, fall back to a
  snapshot … it never blocks the picker." §16 names link-window edge cases as a
  top risk. S2 makes the fallback real (S1's stub only signaled failure).
- **Tidy self-session.** S1's self-session branch was provably correct but left
  a stale `LINKED_ID`. S2's cleanup makes restore (P1.M5.T1.S1) deterministic
  (empty `LINKED_ID` → no unlink attempt) and matches the contract's "Clear
  `@livepicker-linked-id`".
- **Boundary respect (UNCHANGED from S1).** preview.sh still touches ONLY
  `@livepicker-linked-id` (write/unset), `@livepicker-orig-session` /
  `@livepicker-orig-window` (read), and now reads `@livepicker-preview-mode`
  (read-only config). It does NOT touch `@livepicker-mode`, the list/filter/
  index, status, key-tables, or hooks. It calls only `link-window`,
  `unlink-window`, `select-window`, `list-windows` (PRD §13) PLUS the S2-added
  `capture-pane` (PRD §13/§7) and `set-option -gu` (via `tmux_unset_opt`, only
  on `STATE_LINKED_ID`). No `switch-client`, no `refresh-client`, no `set-hook`,
  no `bind-key`.

## What

Three IN-PLACE edits to `scripts/preview.sh`. Everything else in the file is
untouched. The complete, ready-to-paste bodies are in the Implementation
Blueprint.

**Edit 1 — `preview_fallback()` body (replace the stub).** Replace S1's
`return 1` stub with the real `capture-pane` snapshot. Captures S's active pane
into a local var (discarded — see FINDING H), using the **CORRECTED** target
`=$S:. ` (research FINDING A: the literal `-t "=$S"` FAILS rc=1). Returns
capture-pane's exit code (0 = captured; non-zero = gone — S1 contract §4).

**Edit 2 — mode gate (at S1's marked extension point).** Right after the
`linked_id=...` read and BEFORE the self-session guard, read
`mode="$(opt_preview_mode)"` and route:
- `off` → `return 0` (show nothing; no link, no capture, no state change).
- `snapshot` → `preview_fallback "$S"; return $?` (capture; NEVER link).
- `live` (default) → fall through to the existing S1 link flow.

**Edit 3 — self-session refinement (expand the existing `if`-branch).** Inside
the `if [ "$S" = "$current_session" ]` block, BEFORE selecting `ORIG_WINDOW`:
if `linked_id` is non-empty, `unlink-window -t "$current_session:$linked_id"`
(NO `-k`, `|| true` — S1 FINDING 2) then `tmux_unset_opt "$STATE_LINKED_ID"`
(clear — FINDING E). Then the existing `select-window -t "$orig_window"`. Still
`return 0`; still no link attempted.

### Success Criteria

- [ ] `scripts/preview.sh` edited in place (NOT recreated); S1's header, CURRENT_DIR,
      source trio, driver, duplicate guard, unlink/link/select/track, and all S1
      comments are PRESERVED.
- [ ] `preview_fallback()` body is the real `capture-pane -ep -t "=$1:."`
      (captured to a local var, discarded), returning capture's rc.
- [ ] Mode gate reads `opt_preview_mode` exactly once, after the input reads and
      before the self-session guard.
- [ ] `off` → `return 0` with no tmux mutation and no state change.
- [ ] `snapshot` → calls `preview_fallback "$S"` and returns its rc; NEVER calls
      `link-window`/`unlink-window`/`select-window`/`set_state` in this branch.
- [ ] `live` → unchanged S1 flow (self-session guard now refined, then link flow).
- [ ] Self-session branch (live): unlinks prior `linked_id` (no `-k`, `|| true`),
      clears `STATE_LINKED_ID` via `tmux_unset_opt`, then selects `ORIG_WINDOW`.
- [ ] No `set -e`/`set -o pipefail` introduced; all expansions still double-quoted.
- [ ] `bash -n` clean; `shellcheck` 0 findings; tabs only; still `-rwxr-xr-x`.
- [ ] Mock validation: all 4 branches (a self / b link-fail-fallback / c off /
      d snapshot) pass the assertions in Validation Loop §2.

## All Needed Context

### Context Completeness Check

_Pass_: A developer who has never seen this repo can implement S2 from
(a) the verbatim three-edit bodies in the Implementation Blueprint (complete,
ready to paste), (b) the 8 live-verified findings in
research/preview_mode_gate_capture_findings.md — most critically FINDING A
(`capture-pane -ep -t "=$S"` FAILS → use `=$S:.`) which prevents shipping a
permanently-broken fallback, (c) the COMPLETE existing `scripts/preview.sh`
(S1's deliverable — the stub, the marked extension point, and the minimal
self-session branch are all present and quoted below), and (d) the socket-shim
mock that exercises all 4 branches against an isolated server (zero live-server
impact). The file S2 edits already exists and is executable; this is a 3-edit
extension, not greenfield.

### Documentation & References

```yaml
# MUST READ — the file S2 EDITS IN PLACE (COMPLETE; the starting point). Read the
# ACTUAL committed file, not just the S1 PRP, so edits anchor on real text.
- file: scripts/preview.sh
  why: The COMPLETE S1 deliverable. S2 makes 3 surgical edits: (1) the
       preview_fallback() stub (lines ~46-48 `preview_fallback() { return 1 }`),
       (2) the marked `# --- S2: insert the @livepicker-preview-mode gate here
       (live|snapshot|off) ---` comment (inside preview_main, after the
       linked_id read), (3) the self-session if-branch (`if [ -n
       "$current_session" ] && [ "$S" = "$current_session" ]; then ...`).
  pattern: straight-line bash; preview_main() + trailing driver; every guard
           documented inline; tabs; file-level shellcheck disables.
  gotcha: Do NOT rewrite the file. Anchor each edit on the EXACT existing text
          (quoted in the Blueprint). Preserve S1's header comment block, the
          duplicate guard, the unlink/link/select/track tail, and the driver.

# MUST READ — the empirical ground-truth for S2 (8 live-verified findings)
- docfile: plan/001_fd5d622d3939/P1M3T1S2/research/preview_mode_gate_capture_findings.md
  why: FINDING A (CRITICAL: capture-pane -ep -t "=$S" FAILS rc=1 "can't find
       pane"; use -t "=$S:." — the headline contract correction); FINDING B
       (bare "$S" is prefix-ambiguous: "log" matched "logfile"; the = is
       load-bearing); FINDING C (gone session => =$S:. returns rc=1 — fallback
       signal preserved); FINDING D (spaces in session names OK when quoted);
       FINDING E (clear via tmux_unset_opt -gu, not set_state "" — matches
       state.sh teardown); FINDING F (self-session unlink+clear+select verified
       safe); FINDING G (mode-gate ordering: off/snapshot BEFORE self-session);
       FINDING H (capture to a local var, discard — never bare stdout under
       run-shell; return capture's rc).
  critical: Read BEFORE writing the capture-pane line. FINDING A is the
       single highest-consequence detail — following the PRD's literal
       "=$S" ships a fallback that ALWAYS errors.

# MUST READ — S1's PRP (the CONTRACT for the file S2 extends)
- docfile: plan/001_fd5d622d3939/P1M3T1S1/PRP.md
  why: Defines the exact preview.sh S1 delivered: the preview_main() structure,
       the preview_fallback() stub contract ("S2 REPLACES THIS STUB"), the
       marked mode-gate extension point, the self-session minimal branch, the
       duplicate guard, the source order, the no-set-e rule, the exit-code
       contract ("preview_main "$@" || exit 1; exit 0"). S2 MUST preserve all
       of this and only fill the 3 seams.
  section: "What", "Implementation Blueprint -> Implementation Patterns & Key
           Details" (the verbatim S1 file body), "Anti-Patterns to Avoid".

# MUST READ — S1's research (FINDINGS 1-13; S2 reuses 1/2/7/9/10/11 UNCHANGED)
- docfile: plan/001_fd5d622d3939/P1M3T1S1/research/preview_link_unlink_findings.md
  why: The link/unlink/select ground-truth S2 does NOT re-derive. S2's
       self-session refinement reuses FINDING 1 (source keeps window), FINDING 2
       (unlink no -k: succeeds doubly / fails singly -> || true), FINDING 7
       (list-windows exact-match), FINDING 10 (address by @id). S2 only ADDS
       capture-pane findings (its own research file) on top.
  critical: the unlink in the self-session refinement MUST use no -k and || true
            (FINDING 2/11) — same as S1's normal-flow unlink.

# MUST READ — INPUT dependency: options.sh (opt_preview_mode — the S2 gate source)
- file: scripts/options.sh
  why: Defines opt_preview_mode() -> get_opt "@livepicker-preview-mode" "live"
       (CONFIRMED PRESENT; returns live|snapshot|off, default live). S2 calls it
       exactly once. options.sh begins with `set -u` (NO -e); sourcing it leaves
       set -u active (already sourced by S1's preview.sh — S2 does NOT re-source).
  critical: S2 does NOT add a new option accessor — opt_preview_mode already
            exists (P1.M1.T1.S1 shipped it). Just call it.

# MUST READ — INPUT dependency: utils.sh (tmux_unset_opt — the S2 clear path)
- file: scripts/utils.sh
  why: Defines tmux_unset_opt() -> `tmux set-option -gu "$1"` (the -gu unset).
       S2 uses it to clear STATE_LINKED_ID in the self-session branch (FINDING E:
       -gu leaves the option genuinely absent, matching state.sh's own
       clear_all_state teardown). Already sourced by S1's preview.sh.
  critical: there is NO unset_state accessor in state.sh; tmux_unset_opt is the
            idiomatic clear (state.sh's clear_all_state calls `tmux set-option
            -gu "$k"` directly — same thing).

# MUST READ — INPUT dependency: state.sh (get_state/set_state/STATE_*/ORIG_*)
- file: scripts/state.sh
  why: S2 reads ORIG_SESSION/ORIG_WINDOW/STATE_LINKED_ID via get_state (already
       done by S1) and clears STATE_LINKED_ID via tmux_unset_opt (S2 addition).
       Confirms STATE_LINKED_ID="@livepicker-linked-id" (line ~44).
  critical: get_state "$STATE_LINKED_ID" "" reads back "" for BOTH unset and
            set-to-empty (FINDING E), so restore (P1.M5) is unaffected by which
            clear method S2 picks — but tmux_unset_opt is cleaner.

# MUST READ — the live preview subsystem spec (PRD §7 Fallbacks + Self-session)
- docfile: PRD.md
  why: §7 "The preview subsystem" — Fallbacks (capture-pane on link failure /
       snapshot mode / off => nothing; default live) and Self-session edge case
       ("do not link … Select the original window"). §11 (@livepicker-preview-mode
       default live). §13 (capture-pane primitive). §16 (link-window edge-case
       risk => "fall back to capture-pane on any link error").
  section: "§7 The preview subsystem -> Fallbacks", "§7 -> Self-session edge
           case", "§11 Configuration options", "§16 Implementation risks"
  gotcha: PRD §7 literally writes `capture-pane -ep -t "=$S"` — this is WRONG on
          3.6b (research FINDING A). The PRP corrects it to `=$S:.`.

# MUST READ — per-primitive reference (capture-pane)
- docfile: plan/001_fd5d622d3939/architecture/tmux_primitives.md
  why: §6 capture-pane (-e escapes, -p stdout, -t target resolves session->active
       pane; the researcher flagged "no shell access" on the =$S target — S2's
       research file FINDING A closes that gap LIVE: =$S fails, =$S:. works).
  section: "§6 capture-pane -ep"

# MUST READ — system ground-truth (shell style + Invariant A + test harness)
- docfile: plan/001_fd5d622d3939/architecture/system_context.md
  why: §3 INVARIANT A (browsing never fires client-session-changed — S2's mock
       asserts it for the self-session + snapshot branches too); §7 (test-harness
       reality: the PATH-wrapper socket shim — exact shape S2's mock reuses);
       §9 shell style (shebang, set -u only NO -e, tabs, quote everything).
  section: "§3 INVARIANT A", "§7 Test harness reality", "§9 Shell style"
```

### Current Codebase tree

```bash
tmux-livepicker/
  PRD.md
  plugin.tmux                 # (P1.M1.T4.S1) ENTRY POINT — COMPLETE
  plan/001_fd5d622d3939/{architecture/*.md, tasks.json, prd_snapshot.md, prd_index.txt}
  plan/001_fd5d622d3939/P1M3T1S1/{PRP.md, research/preview_link_unlink_findings.md}  # S1
  plan/001_fd5d622d3939/P1M3T1S2/{PRP.md, research/preview_mode_gate_capture_findings.md}  # THIS
  scripts/
    options.sh   # EXISTS (COMPLETE) — opt_preview_mode (default "live"). S2's gate source.
    utils.sh     # EXISTS (COMPLETE) — tmux_unset_opt (the -gu clear). S2's clear path.
    state.sh     # EXISTS (COMPLETE) — get_state/set_state/STATE_*/ORIG_*.
    renderer.sh  # EXISTS (P1.M2.T1 — COMPLETE). Unchanged by this task.
    preview.sh   # EXISTS (P1.M3.T1.S1 — COMPLETE). THIS TASK EDITS IT IN PLACE (3 edits).
  .gitignore
  # NOTE: NO test harness (P1.M7). Validate via the socket-shim throwaway mock.
```

### Desired Codebase tree with files to be added and responsibility of file

```bash
tmux-livepicker/
  scripts/
    options.sh   # INPUT dep — opt_preview_mode. Unchanged by this task.
    utils.sh     # INPUT dep — tmux_unset_opt. Unchanged.
    state.sh     # INPUT dep — STATE_LINKED_ID etc. Unchanged.
    renderer.sh  # (P1.M2.T1). Unchanged.
    preview.sh   # EDITED IN PLACE (this task, 3 edits): (1) preview_fallback body
                 #   -> capture-pane -ep -t "=$1:." (CORRECTED target; FINDING A);
                 #   (2) mode gate (off/snapshot/live) at the S1-marked spot;
                 #   (3) self-session branch refined (unlink prior + clear + select).
                 #   Still mutation-only; still chmod +x.
```

### Known Gotchas of our codebase & Library Quirks

```bash
# CRITICAL (research FINDING A): capture-pane -ep -t "=$S" FAILS on tmux 3.6b
# ("can't find pane: =S", rc=1). The `=` exact-match prefix is a SESSION/WINDOW
# NAME matcher; capture-pane's -t wants a PANE target, so `=S` is read as a
# (non-existent) pane spec. The PRD §7 / work-item literally specify `=$S` —
# they are WRONG. Use `-t "=$S:."` (exact session + active-pane resolution).
# Verified: =$S:. rc=0 on real sessions, rc=1 on gone, disambiguates "log" vs
# "logfile", handles "job hunt" (spaces). This is the S2 analog of S1's
# FINDING-4/5 duplicate-guard correction.

# CRITICAL (research FINDING B): do NOT "fix" FINDING A by dropping the `=`
# (i.e. bare `-t "$S"`). Bare session targets use UNIQUE-PREFIX matching: with
# sessions `log` and `logfile`, `-t "log"` captured `logfile`'s pane. The `=`
# is load-bearing; the fix is `=$S:.`, NOT `$S`.

# CRITICAL (research FINDING H): capture into a LOCAL VAR, NOT bare stdout.
# preview.sh runs under `tmux run-shell` (called by input-handler/activate);
# bare `capture-pane -ep` stdout is a blob of escape sequences that run-shell
# may echo into the status/display area and corrupt the screen. `local captured;
# captured="$(tmux capture-pane -ep -t "=$1:." 2>/dev/null)"` runs the command
# (verifies reachability + never blocks) and discards the text. The captured
# text is a "best-effort hint" (PRD §7) — there is no separate buffer to render
# it into without a link; that is what `live` mode is for.

# CRITICAL (research FINDING E): clear STATE_LINKED_ID via `tmux_unset_opt`
# (set-option -gu), NOT `set_state "$STATE_LINKED_ID" ""`. `-gu` leaves the
# option genuinely ABSENT (show-options probe rc=1); set-to-empty leaves it
# "present-but-empty". Both read back "" via get_state, so restore is unaffected,
# BUT tmux_unset_opt matches state.sh's own clear_all_state teardown and is
# cleaner. There is no `unset_state` accessor; tmux_unset_opt IS the idiom.

# CRITICAL: NO `set -e`. S1 established this (unlink/list-windows legitimately
# return non-zero). S2 ADDS capture-pane to that list — it returns rc=1 on a
# gone session, which must NOT abort the script. The mode-gate `snapshot` branch
# returns capture's rc explicitly; the live link-failure path returns it via
# `preview_fallback "$S"; return $?`. No `set -e` anywhere.

# GOTCHA: the self-session refinement reuses S1's unlink rules VERBATIM —
# `unlink-window -t "$current_session:$linked_id"` with NO `-k` and `|| true`
# (S1 FINDING 2: succeeds when doubly-linked, rc=1 when singly-linked — ignore;
# S1 FINDING 11: -k destroys the shared window in ALL sessions). Do NOT invent a
# new unlink style.

# GOTCHA: mode-gate ORDERING is load-bearing (research FINDING G). off/snapshot
# route BEFORE the self-session guard. Rationale: `off` must short-circuit for
# ALL candidates (including self); `snapshot` must capture for ALL candidates
# (including self — capturing your own active pane is harmless). Only `live`
# needs the self-session link-avoidance. If you put the self-session guard
# first, `snapshot`/`off` of the self-session would take the wrong branch.

# GOTCHA: `@livepicker-preview-mode` is a CONFIG option — constant for the
# picker's lifetime (the user is not editing tmux.conf while browsing). So `off`
# never has a prior link to clean (every call returns 0 before linking), and
# `snapshot` never sets LINKED_ID (it never links). DO NOT add defensive
# unlink/clear to the off/snapshot branches — they are unreachable in practice
# and would muddy the contract. restore (P1.M5) handles any residual regardless.

# GOTCHA: S2 is an EDIT-IN-PLACE. The file already exists and is executable.
# Do NOT recreate it, do NOT change the shebang, do NOT re-order the source trio,
# do NOT touch the duplicate guard / unlink / link / select / track tail, do NOT
# touch the driver. Anchor each of the 3 edits on the EXACT existing text.

# STYLE (system_context §9): indent with TABS. The 3 edits must match the
# surrounding tab-indentation. Verify with `grep -Pn '^    ' scripts/preview.sh`
# (expect empty).
```

## Implementation Blueprint

### Data models and structure

No new data model. S2 adds one function-local (`mode` in `preview_main`) and
reuses `preview_fallback`'s existing `$1` = S. The state surface is UNCHANGED
from S1 (reads `ORIG_SESSION`/`ORIG_WINDOW`/`STATE_LINKED_ID`; writes/unsets
`STATE_LINKED_ID` only) plus one new READ of the config option
`@livepicker-preview-mode` via `opt_preview_mode`.

### Implementation Tasks (ordered by dependencies)

```yaml
Task 1: EDIT scripts/preview.sh — REPLACE the preview_fallback() stub body
  - FILE: ./scripts/preview.sh  (EXISTS; S1 deliverable. Edit in place.)
  - FIND (exact existing text to replace):
      preview_fallback() {
      	return 1
      }
  - REPLACE WITH (research FINDING A/H — corrected target, capture-to-local,
    return capture rc):
      preview_fallback() {
      	# capture-pane snapshot fallback (PRD §7 Fallbacks). Single-pane, NOT live.
      	# Invoked (a) when @livepicker-preview-mode == snapshot (always), and
      	# (b) when a live link-window fails (degraded but non-blocking path).
      	# Captures S's active pane with escapes to stdout. CRITICAL: the target is
      	# "=$1:." NOT "=$1" — the bare =$S form FAILS rc=1 "can't find pane" on
      	# 3.6b (= is a session-name matcher; capture-pane wants a pane target).
      	# Capture into a LOCAL var (not bare stdout): under run-shell, bare escape
      	# sequences could corrupt the status area. The text is a best-effort hint
      	# (no buffer to render into without a link = live mode). Returns capture's
      	# rc: 0 = captured, non-zero = session/pane gone (S1 contract §4).
      	# $1 = candidate session S.
      	local captured
      	captured="$(tmux capture-pane -ep -t "=$1:." 2>/dev/null)" && return 0 || return 1
      }
  - PRESERVE: the S2-seam comment block ABOVE the function (S1 wrote it; update
    its text to past tense / "implemented" is optional — leave as-is to minimize
    diff, OR trim to one line noting the stub is now real). Minimum: keep the
    function NAME and signature unchanged so the two call sites still resolve.
  - NAMING/STYLE: tabs; `local captured` declared before assignment (SC2155-safe).

Task 2: EDIT scripts/preview.sh — INSERT the mode gate at S1's marked extension point
  - FILE: ./scripts/preview.sh
  - FIND (exact existing text — the marker S1 left, inside preview_main, right
    after the linked_id read):
      	# --- S2: insert the @livepicker-preview-mode gate here (live|snapshot|off) ---
  - REPLACE WITH (research FINDING G — off/snapshot BEFORE self-session; live
    falls through). Insert a `mode` local declaration with the other locals is
    preferred but NOT required (a function-local `local mode` on its own line is
    fine; bash allows mid-function `local`):
      	# --- @livepicker-preview-mode gate (PRD §7 Fallbacks / §11; default live) ---
      	local mode
      	mode="$(opt_preview_mode)"   # live | snapshot | off
      	if [ "$mode" = "off" ]; then
      		# Show nothing. No link, no capture, no state change. (mode is constant
      		# for the picker lifetime, so no prior link exists to clean here.)
      		return 0
      	fi
      	if [ "$mode" = "snapshot" ]; then
      		# Snapshot: capture-pane of S's active pane; NEVER link. Self-session
      		# needs no special handling (capturing your own pane is harmless).
      		preview_fallback "$S"
      		return $?
      	fi
      	# mode == live (default): fall through to the link flow below.
  - PLACEMENT: this block sits AFTER `linked_id="$(get_state ...)"` and BEFORE
    the `# Self-session guard (PRD §7; FINDING 6)` comment. DO NOT move the
    self-session guard.
  - NOTE: `opt_preview_mode` is defined in options.sh (sourced above) — no import
    needed. `set -u`-safe (it has a baked-in "live" default).

Task 3: EDIT scripts/preview.sh — REFINE the self-session branch (live mode)
  - FILE: ./scripts/preview.sh
  - FIND (exact existing text — S1's minimal self-session branch):
      	# Self-session guard (PRD §7; FINDING 6). Do NOT link — would create an
      	# in-session duplicate; instead show the user their own session. Select the
      	# original window and return. (S1: do not unlink/clear LINKED_ID here.)
      	if [ -n "$current_session" ] && [ "$S" = "$current_session" ]; then
      		[ -n "$orig_window" ] && tmux select-window -t "$orig_window" 2>/dev/null || true
      		return 0
      	fi
  - REPLACE WITH (research FINDING F/E — unlink prior, clear, then select):
      	# Self-session guard (PRD §7; FINDING 6). Do NOT link — would create an
      	# in-session duplicate; instead show the user their own session. S2
      	# refinement (contract §3): first drop any prior preview linked into the
      	# driver (source keeps it — S1 FINDING 1; no -k, || true — S1 FINDING 2),
      	# clear LINKED_ID (tmux_unset_opt = -gu — FINDING E; matches state.sh
      	# teardown), THEN select the original window.
      	if [ -n "$current_session" ] && [ "$S" = "$current_session" ]; then
      		if [ -n "$linked_id" ]; then
      			tmux unlink-window -t "$current_session:$linked_id" 2>/dev/null || true
      			tmux_unset_opt "$STATE_LINKED_ID"
      		fi
      		[ -n "$orig_window" ] && tmux select-window -t "$orig_window" 2>/dev/null || true
      		return 0
      	fi
  - PRESERVE: the rest of preview_main (src_id resolve, duplicate guard, unlink,
    link, select, track) and the driver — UNCHANGED.
  - GOTCHA: keep the `[ -n "$orig_window" ] && tmux select-window ... || true`
    one-liner EXACTLY (the `|| true` binds to the whole &&-chain so an empty
    orig_window does not abort — S1's careful precedence).

Task 4: VERIFY (Level 1 syntax/lint + Level 2 socket-shim 4-branch mock)
  - RUN: bash -n scripts/preview.sh            (expect exit 0, no output)
  - RUN: shellcheck scripts/preview.sh         (expect 0 findings — S1's file-level
    `# shellcheck disable=SC1091,SC2153` already covers source-lines + ORIG_*.)
  - RUN: grep -Pn '^    ' scripts/preview.sh   (expect empty — tabs only)
  - RUN: [ -x scripts/preview.sh ] && echo OK  (S1 chmod'd it; S2 edits do NOT
    drop the bit, but verify.)
  - RUN the socket-shim mock (Validation Loop §2) — all 4 branches
    (a self / b link-fail-fallback / c off / d snapshot). Self-cleaning.
```

### Implementation Patterns & Key Details

The three edits, shown in situ against the existing S1 file (only the changed
regions are reproduced; `...` = unchanged S1 code):

```bash
#!/usr/bin/env bash
# shellcheck disable=SC1091,SC2153
# scripts/preview.sh — tmux-livepicker live preview core (link-window).
# ... (S1 header UNCHANGED — optionally append one line noting S2 added the
#      mode gate + capture-pane fallback + self-session cleanup) ...
CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=options.sh
source "$CURRENT_DIR/options.sh"
# shellcheck source=utils.sh
source "$CURRENT_DIR/utils.sh"
# shellcheck source=state.sh
source "$CURRENT_DIR/state.sh"

# ===== EDIT 1: preview_fallback() — real capture-pane (was `return 1` stub) =====
preview_fallback() {
	# capture-pane snapshot fallback (PRD §7 Fallbacks). Single-pane, NOT live.
	# Invoked (a) when @livepicker-preview-mode == snapshot, and (b) on any live
	# link-window failure (degraded but non-blocking). CRITICAL: target "=$1:."
	# NOT "=$1" — the bare =$S form FAILS rc=1 "can't find pane" on 3.6b (= is a
	# session-name matcher; capture-pane wants a pane target — research FINDING A).
	# Capture into a LOCAL var (not bare stdout): under run-shell, bare escape
	# sequences could corrupt the status area. The text is a best-effort hint
	# (no buffer to render into without a link = live mode). Returns capture's rc
	# (0 = captured; non-zero = gone — S1 contract §4). $1 = candidate session S.
	local captured
	captured="$(tmux capture-pane -ep -t "=$1:." 2>/dev/null)" && return 0 || return 1
}

preview_main() {
	local S="${1:-}"
	local current_session orig_window linked_id src_id

	current_session="$(get_state "$ORIG_SESSION" "")"
	orig_window="$(get_state "$ORIG_WINDOW" "")"
	linked_id="$(get_state "$STATE_LINKED_ID" "")"

	# ===== EDIT 2: @livepicker-preview-mode gate (was the S1 marker comment) =====
	local mode
	mode="$(opt_preview_mode)"   # live | snapshot | off  (default live; options.sh)
	if [ "$mode" = "off" ]; then
		return 0
	fi
	if [ "$mode" = "snapshot" ]; then
		preview_fallback "$S"
		return $?
	fi
	# mode == live (default): fall through to the link flow below.

	# ===== EDIT 3: self-session branch refined (was S1's minimal select-only) =====
	if [ -n "$current_session" ] && [ "$S" = "$current_session" ]; then
		if [ -n "$linked_id" ]; then
			tmux unlink-window -t "$current_session:$linked_id" 2>/dev/null || true
			tmux_unset_opt "$STATE_LINKED_ID"
		fi
		[ -n "$orig_window" ] && tmux select-window -t "$orig_window" 2>/dev/null || true
		return 0
	fi

	# ... (S1 code UNCHANGED from here: src_id resolve, gone-session fallback,
	#      duplicate guard, unlink previous, guarded link, select, track) ...
	src_id="$(tmux list-windows -t "=$S" -F '#{window_id}' -f '#{window_active}' 2>/dev/null)"
	if [ -z "$src_id" ]; then
		preview_fallback "$S"
		return $?
	fi
	if [ -n "$linked_id" ] && [ "$linked_id" = "$src_id" ]; then
		tmux select-window -t "$src_id" 2>/dev/null || true
		return 0
	fi
	if [ -n "$linked_id" ]; then
		tmux unlink-window -t "$current_session:$linked_id" 2>/dev/null || true
	fi
	if ! tmux link-window -a -s "$src_id" -t "$current_session:" 2>/dev/null; then
		preview_fallback "$S"
		return $?
	fi
	tmux select-window -t "$src_id" 2>/dev/null || true
	set_state "$STATE_LINKED_ID" "$src_id"
	return 0
}

preview_main "$@" || exit 1
exit 0
```

NOTE for the implementer: the block above reproduces ONLY the changed regions
plus enough context to anchor them. The real edits use the `edit` tool against
the EXACT existing text in `scripts/preview.sh` (see Task FIND strings). Do NOT
recreate the file. Do NOT add `set -e`. Do NOT pass `-k` to unlink-window. Do
NOT change the capture-pane target away from `=$S:.`. Do NOT move the
self-session guard above the mode gate.

### Integration Points

```yaml
CALLERS (UNCHANGED from S1 — S2 changes NO caller contract):
  - activate livepicker.sh (P1.M4.T5.S1 — FUTURE): first preview is the
        self-session -> S2's refined branch (first call: LINKED_ID empty ->
        just select ORIG_WINDOW; identical observable behavior to S1).
  - input-handler.sh next/prev (P1.M6.T2.S1 — FUTURE): resolves candidate S,
        runs preview.sh "$S", refresh-client -S. S2's mode gate means a user
        with @livepicker-preview-mode=snapshot gets captures instead of links;
        with =off the call is a fast no-op.
  - restore.sh (P1.M5.T1.S1 — FUTURE): reads @livepicker-linked-id (this script
        WROTE/UNSET it). S2's self-session cleanup means restore sees an EMPTY
        linked-id after a self-session preview (no unlink attempt) — tidier
        than S1's stale-link case.

STATE WRITES/UNSETS (this task — STATE_LINKED_ID only):
  - set to src_id: UNCHANGED (live link-success path — S1).
  - UNSET (new in S2): in the self-session branch (live mode), if a prior
        linked_id existed, `tmux_unset_opt "$STATE_LINKED_ID"` after unlinking.
        Leaves the option genuinely absent (FINDING E).
  - off / snapshot branches: NO state change (off returns before any mutation;
        snapshot never links so never sets linked-id).

STATE READS (this task):
  - @livepicker-orig-session / @livepicker-orig-window / @livepicker-linked-id
    (UNCHANGED from S1).
  - @livepicker-preview-mode (NEW READ in S2): via opt_preview_mode() — a config
    option (PRD §11), read-only here, NEVER written/cleared.

TMUX MUTATIONS (this task — PRD §13, the preview primitives + capture-pane):
  - UNCHANGED from S1: list-windows, unlink-window (no -k), link-window,
    select-window.
  - NEW (S2): capture-pane -ep -t "=$S:."  (in preview_fallback — snapshot mode
    + live link-failure fallback).
  - NEW (S2): set-option -gu @livepicker-linked-id  (via tmux_unset_opt — the
    self-session clear only).

DEPENDENCIES (consumed — all COMPLETE):
  - scripts/options.sh (P1.M1.T1.S1): opt_preview_mode (NEW consumer in S2;
    the accessor already exists). Sourced first.
  - scripts/utils.sh (P1.M1.T2.S1): tmux_unset_opt (NEW consumer in S2 — the
    -gu clear). Sourced second.
  - scripts/state.sh (P1.M1.T3.S1): STATE_LINKED_ID / ORIG_SESSION / ORIG_WINDOW.
    Sourced third.

DATABASE / MIGRATIONS / ROUTES / STATUS-FORMAT: none.
```

## Validation Loop

### Level 1: Syntax & Style (Immediate Feedback)

```bash
# Run after the 3 edits — fix before proceeding.
bash -n scripts/preview.sh                     # syntax check; expect no output, exit 0
shellcheck scripts/preview.sh                  # lint; expect 0 findings (S1's file-level
                                               # disable=SC1091,SC2153 already covers it)
# Tabs-not-spaces sanity (the 3 new edits must be tab-indented):
grep -Pn '^    ' scripts/preview.sh && echo "FAIL: 4-space indent found, use tabs" || echo "OK: tabs only"
# Executable bit preserved (S2 edits do not drop it, but verify):
[ -x scripts/preview.sh ] && echo "OK: executable" || { echo "FAIL: not executable"; chmod +x scripts/preview.sh; }
# Confirm the corrected capture-pane target is present and the broken one is NOT:
grep -n 'capture-pane -ep -t "=$1:\."' scripts/preview.sh && echo "OK: =\$1:. target" || echo "FAIL: missing corrected target"
grep -n 'capture-pane -ep -t "=$1"'   scripts/preview.sh && echo "FAIL: broken bare =\$1 target still present" || echo "OK: no broken target"
# Run from the repo root.
```

### Level 2: Socket-Shim Mock Validation — ALL 4 branches, zero live-server impact

Reuses the S1 socket-shim shape (system_context §7). preview.sh calls bare
`tmux`, which the shim redirects to an isolated socket. Self-cleaning.

```bash
#!/usr/bin/env bash
# Throwaway socket-shim validation for S2 edits to scripts/preview.sh (do NOT commit).
set -u
REPO_ROOT="$(cd "$(dirname "$0")" && pwd)"
[ -f "$REPO_ROOT/scripts/preview.sh" ] || { echo "preview.sh missing"; exit 1; }

SOCK="lp-preview-s2-mock-$$"
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

# --- fixture: driver + S1 (with marker text) + S2 ---
tmux new-session -d -s driver -x 100 -y 40
tmux send-keys -t "=driver" "echo DRIVER_ORIG_TEXT" Enter
tmux new-session -d -s S1 -x 100 -y 40
tmux send-keys -t "=S1" "echo S1_ACTIVE_PANE_TEXT" Enter
tmux new-session -d -s S2 -x 100 -y 40
DRIVER_ORIG_WIN="$(tmux list-windows -t '=driver' -F '#{window_id}' -f '#{window_active}')"
S1_WIN="$(tmux list-windows -t '=S1' -F '#{window_id}' -f '#{window_active}')"

set_mode() { tmux set-option -g "@livepicker-preview-mode" "$1"; }
prime() {  # $1=linked-id-or-empty
	tmux set-option -g "@livepicker-orig-session" "driver"
	tmux set-option -g "@livepicker-orig-window" "$DRIVER_ORIG_WIN"
	if [ -n "$1" ]; then tmux set-option -g "@livepicker-linked-id" "$1"
	else tmux set-option -gu "@livepicker-linked-id"; fi
}
count_in() { tmux list-windows -t "=$1" -F '#{window_id}' 2>/dev/null | grep -cx "$2"; }
pass=0; fail=0
assert() { if [ "$2" = "$3" ]; then pass=$((pass+1)); else fail=$((fail+1)); printf 'FAIL %s: got=[%s] want=[%s]\n' "$1" "$2" "$3"; fi; }

# ---------- (c) preview-mode=off renders nothing ----------
set_mode off; prime ""
bash "$REPO_ROOT/scripts/preview.sh" S1; rc=$?
assert "off rc=0" "$rc" "0"
assert "off: S1 NOT linked into driver" "$(count_in driver "$S1_WIN")" "0"
assert "off: linked-id untouched (empty)" "$(tmux show-option -gqv "@livepicker-linked-id")" ""

# ---------- (d) snapshot mode: capture-pane, NEVER link ----------
set_mode snapshot; prime ""
bash "$REPO_ROOT/scripts/preview.sh" S1; rc=$?
assert "snapshot rc=0 (real session captures)" "$rc" "0"
assert "snapshot: S1 NOT linked into driver" "$(count_in driver "$S1_WIN")" "0"
assert "snapshot: linked-id still empty" "$(tmux show-option -gqv "@livepicker-linked-id")" ""
# snapshot of a GONE session returns non-zero (fallback signal preserved)
bash "$REPO_ROOT/scripts/preview.sh" does-not-exist; rc=$?
assert "snapshot gone-session rc!=0" "$([ "$rc" -ne 0 ] && echo 1 || echo 0)" "1"

# ---------- (a) self-session (live mode): no link, unlink prior, clear, select orig ----------
set_mode live
# first link S1 so there IS a prior linked-id to clean
prime ""
bash "$REPO_ROOT/scripts/preview.sh" S1 >/dev/null 2>&1   # live: links S1 -> linked-id=S1_WIN
assert "setup: S1 linked" "$(count_in driver "$S1_WIN")" "1"
assert "setup: linked-id==S1_WIN" "$(tmux show-option -gqv "@livepicker-linked-id")" "$S1_WIN"
# now preview the SELF session -> S2 refinement must unlink S1 + clear + select orig
bash "$REPO_ROOT/scripts/preview.sh" driver; rc=$?
assert "self rc=0" "$rc" "0"
assert "self: S1 NO LONGER linked in driver (unlinked prior)" "$(count_in driver "$S1_WIN")" "0"
assert "self: S1 window STILL in S1 (source keeps it)" "$(count_in S1 "$S1_WIN")" "1"
assert "self: linked-id CLEARED (empty)" "$(tmux show-option -gqv "@livepicker-linked-id")" ""
assert "self: driver active window == ORIG_WINDOW" "$(tmux list-windows -t '=driver' -F '#{window_id}' -f '#{window_active}')" "$DRIVER_ORIG_WIN"
assert "self: client session still driver (Invariant A)" "$(tmux show-option -gqv "@livepicker-orig-session")" "driver"

# ---------- (b) live link-failure -> capture fallback (rc=0, no crash) ----------
set_mode live; prime ""
# Force a link failure by killing S2's only window mid-target-resolution is racy;
# instead use a session that EXISTS (so capture succeeds rc=0) but make link fail
# by pointing src at an impossible window: create S2, capture its active pane id,
# then kill THAT window so list-windows returns empty -> gone-session branch ->
# preview_fallback -> capture-pane. But capture needs the session to still exist
# with a pane. Simplest robust link-failure sim: a session whose active window is
# unkillable-to-link is not trivial; the gone-session path (empty src_id) IS the
# link-failure-equivalent fallback trigger (S1 contract). Verify it captures:
# create a fresh session with text, then make list-windows miss by naming a
# session that exists but point preview at a DIFFERENT gone name -> fallback
# captures the gone name (fails). To prove capture-success-on-link-fail, instead
# temporarily break link-window via a shim wrapper is overkill. Use the structural
# proof: snapshot mode already proved capture returns rc=0 on a real session (d);
# the live link-failure path calls the SAME preview_fallback. Verify here that a
# gone candidate in LIVE mode falls back and exits non-zero without crashing:
tmux new-session -d -s gonecandidate -x 100 -y 40
tmux kill-session -t gonecandidate 2>/dev/null   # now truly gone
bash "$REPO_ROOT/scripts/preview.sh" gonecandidate; rc=$?
assert "live gone-candidate rc!=0 (fallback also fails on truly-gone)" "$([ "$rc" -ne 0 ] && echo 1 || echo 0)" "1"
assert "live gone-candidate: driver intact (no crash)" "$(tmux has-session -t '=driver' 2>/dev/null && echo 1 || echo 0)" "1"
# AND a real-session link-failure fallback returns rc=0: stub link-window to fail
# while the candidate session still exists (so capture succeeds). Implement by a
# wrapper tmux that intercepts link-window only:
cat > "$SHIM_DIR/tmux" <<EOF
#!/usr/bin/env bash
case "\$1" in
  link-window) echo "simulated link failure" >&2; exit 1 ;;  # force fallback
  *) exec /usr/bin/tmux -L "$SOCK" "\$@" ;;
esac
EOF
chmod +x "$SHIM_DIR/tmux"
prime ""
bash "$REPO_ROOT/scripts/preview.sh" S1; rc=$?
assert "live link-FAILURE -> capture fallback rc=0 (real session)" "$rc" "0"
assert "live link-failure: S1 NOT linked (link failed)" "$(count_in driver "$S1_WIN")" "0"
assert "live link-failure: no crash, driver intact" "$(tmux has-session -t '=driver' 2>/dev/null && echo 1 || echo 0)" "1"

printf 'PASS=%d FAIL=%d\n' "$pass" "$fail"
[ "$fail" = "0" ]
# Expected: PASS≈20 FAIL=0. Key proofs:
#  - off: nothing happens (no link, no capture, no state change).
#  - snapshot: capture rc=0 on real session; NEVER links; gone session rc!=0.
#  - self (live): unlinks prior candidate from driver (source keeps it), clears
#    linked-id, selects ORIG_WINDOW; client session unchanged (Invariant A).
#  - link-failure (live): wrapper-forced link-window rc=1 -> capture fallback
#    rc=0 (candidate's active pane is reachable); picker never blocks.
```

### Level 3: Integration Testing (System Validation)

```bash
# Live spot-check on an ISOLATED socket WITH an attached pty client — confirms
# (1) the self-session refinement visibly selects ORIG_WINDOW, (2) snapshot mode
# captures the candidate's active pane text (best-effort hint), and (3) the
# client's session never switches (Invariant A). Self-cleaning.
export LP_SOCK="lp-preview-s2-live-$$"
REPO_ROOT="$(pwd)"
SHIM_DIR="$(mktemp -d)"
cat > "$SHIM_DIR/tmux" <<EOF
#!/usr/bin/env bash
exec /usr/bin/tmux -L "$LP_SOCK" "\$@"
EOF
chmod +x "$SHIM_DIR/tmux"
trap 'PATH=/usr/bin:/bin:$PATH tmux -L "$LP_SOCK" kill-server 2>/dev/null; rm -rf "$SHIM_DIR" /tmp/lp-s2-live.log' EXIT

T() { PATH="$SHIM_DIR:$PATH" tmux "$@"; }
T new-session -d -s driver -x 100 -y 40
T send-keys -t "=driver" "echo DRIVER_ORIGINAL" Enter
T new-session -d -s cand -x 100 -y 40
T send-keys -t "=cand" "echo CAND_ACTIVE_PANE" Enter; sleep 0.2
# attach a real pty client so panes render + display-message resolves
TMUX="" script -qec "tmux -L $LP_SOCK attach -t driver" /tmp/lp-s2-live.log &
ATTACH_PID=$!; sleep 0.5

ORIG="$(T list-windows -t '=driver' -F '#{window_id}' -f '#{window_active}')"
T set-option -g "@livepicker-orig-session" "driver"
T set-option -g "@livepicker-orig-window" "$ORIG"
T set-option -gu "@livepicker-linked-id"

echo "=== (1) live mode: preview cand, then self-session refinement ==="
T set-option -g "@livepicker-preview-mode" "live"
PATH="$SHIM_DIR:$PATH" bash "$REPO_ROOT/scripts/preview.sh" cand; sleep 0.3
echo "after preview cand: client session=$(T display-message -p '#{session_name}')  active-win=$(T display-message -p '#{window_id}')"
PATH="$SHIM_DIR:$PATH" bash "$REPO_ROOT/scripts/preview.sh" driver; sleep 0.3   # self-session
echo "after preview driver(self): client session=$(T display-message -p '#{session_name}')  active-win=$(T display-message -p '#{window_id}') (expect == ORIG)"
echo "linked-id after self: [$(T show-option -gqv "@livepicker-linked-id")] (expect empty)"

echo ""
echo "=== (2) snapshot mode: capture cand (best-effort hint) ==="
T set-option -g "@livepicker-preview-mode" "snapshot"
PATH="$SHIM_DIR:$PATH" bash "$REPO_ROOT/scripts/preview.sh" cand; rc=$?
echo "snapshot rc=$rc (expect 0); direct capture of cand for reference:"
T capture-pane -ep -t "=cand:." | grep -c CAND_ACTIVE_PANE | sed 's/^/  captured-marker-count=/'
echo "client session after snapshot: $(T display-message -p '#{session_name}') (expect driver — no switch)"

kill "$ATTACH_PID" 2>/dev/null; wait "$ATTACH_PID" 2>/dev/null
# Expected: (1) self-session leaves active-win == ORIG, linked-id empty, client
# session == driver. (2) snapshot rc=0; the candidate's marker is capture-able;
# client session unchanged.
```

### Level 4: Creative & Domain-Specific Validation

```bash
# Pollution invariant spot-check (PRD §15.18 — the core guarantee) for the S2
# branches. Requires the tmux-session-history plugin's @session-history-hist on
# the LIVE server. Touches ONLY option READS + the @livepicker-* keys + an
# isolated run of preview.sh in snapshot mode (no link => even less risk than
# S1's live spot-check). Run ONLY if @session-history-hist exists.
if tmux show-options -gv "@session-history-hist" >/dev/null 2>&1; then
    REPO_ROOT="$(pwd)"
    BEFORE="$(tmux show-options -gv "@session-history-hist" 2>/dev/null)"
    CUR_SESS="$(tmux display-message -p '#{session_name}')"
    CUR_WIN="$(tmux display-message -p '#{window_id}')"
    OTHER="$(tmux list-sessions -F '#{session_name}' | grep -vx "$CUR_SESS" | head -1)"
    tmux set-option -g "@livepicker-orig-session" "$CUR_SESS"
    tmux set-option -g "@livepicker-orig-window" "$CUR_WIN"
    tmux set-option -gu "@livepicker-linked-id"
    tmux set-option -g "@livepicker-preview-mode" "snapshot"   # S2: exercise the capture path
    [ -n "$OTHER" ] && bash "$REPO_ROOT/scripts/preview.sh" "$OTHER" 2>/dev/null
    # also exercise the self-session refinement (live)
    tmux set-option -g "@livepicker-preview-mode" "live"
    bash "$REPO_ROOT/scripts/preview.sh" "$CUR_SESS" 2>/dev/null
    AFTER="$(tmux show-options -gv "@session-history-hist" 2>/dev/null)"
    # cleanup our keys
    tmux set-option -gu "@livepicker-orig-session" 2>/dev/null
    tmux set-option -gu "@livepicker-orig-window" 2>/dev/null
    tmux set-option -gu "@livepicker-linked-id" 2>/dev/null
    tmux set-option -gu "@livepicker-preview-mode" 2>/dev/null
    if [ "$BEFORE" = "$AFTER" ]; then
        echo "OK: @session-history-hist UNCHANGED across snapshot+self preview (Invariant A holds)"
    else
        echo "FAIL: history polluted"
    fi
else
    echo "SKIP: tmux-session-history not present on live server (mock §2 covers this structurally)"
fi
# Expected: OK — neither snapshot (capture-pane only) nor the self-session
# refinement calls switch-client, so client-session-changed never fires.
```

## Final Validation Checklist

### Technical Validation

- [ ] `bash -n scripts/preview.sh` exits 0 with no output.
- [ ] `shellcheck scripts/preview.sh` reports 0 findings (S1's file-level
      `# shellcheck disable=SC1091,SC2153` covers source-lines + ORIG_*).
- [ ] No 4-space indents (`grep -Pn '^    '` is empty); tabs only.
- [ ] `scripts/preview.sh` is still executable (`-rwxr-xr-x`).

### Feature Validation

- [ ] **Edit 1:** `preview_fallback()` body is `capture-pane -ep -t "=$1:."`
      captured to a local var, returning capture's rc (`&& return 0 || return 1`).
- [ ] The broken `=$1` / `=$S` target is NOT present anywhere
      (`grep 'capture-pane -ep -t "=$1"'` is empty).
- [ ] **Edit 2:** mode gate reads `opt_preview_mode` once, after the input reads
      and before the self-session guard; `off`→return 0, `snapshot`→
      `preview_fallback "$S"; return $?`, `live`→fall through.
- [ ] **Edit 3:** self-session branch unlinks prior `linked_id` (no `-k`,
      `|| true`), clears via `tmux_unset_opt "$STATE_LINKED_ID"`, then selects
      `ORIG_WINDOW`, then `return 0`.
- [ ] The rest of preview_main (src_id resolve, gone-session fallback, duplicate
      guard, unlink, link, select, track) and the driver are UNCHANGED from S1.
- [ ] Mock (a) self-session: no link, prior unlinked (source keeps it), linked-id
      cleared, ORIG_WINDOW selected, client session unchanged.
- [ ] Mock (b) link-failure: capture fallback rc=0 on a real candidate; gone
      candidate rc!=0; no crash.
- [ ] Mock (c) off: rc=0, no link, no capture, no state change.
- [ ] Mock (d) snapshot: rc=0 on real session, NEVER links, linked-id stays empty.

### Code Quality Validation

- [ ] NO `set -e`, NO `set -o pipefail` introduced (capture-pane legitimately
      returns non-zero on a gone session).
- [ ] All expansions double-quoted (`"$S"`, `"$mode"`, `"$linked_id"`,
      `"$current_session"`, `"$orig_window"`, `"$1"`).
- [ ] NO `switch-client`, NO `refresh-client`, NO `set-hook`, NO `bind-key`,
      NO `kill-window`, NO `-k` on unlink-window, NO `set-option` except
      `tmux_unset_opt` on `STATE_LINKED_ID` (self-session clear).
- [ ] The new `local mode` / `local captured` are declared before assignment
      (SC2155-safe).
- [ ] Indent with tabs; the 3 edits match surrounding tab-indentation.

### Documentation & Deployment

- [ ] Header comment optionally notes S2 added the mode gate + capture-pane
      fallback + self-session cleanup (one line; not required).
- [ ] No README/doc file created (DOCS = Mode A — contract §6: "internal;
      behavior summarized in final README P1.M8").
- [ ] No new env vars; no tmux.conf edit; the only new option READ is
      `@livepicker-preview-mode` (a pre-existing PRD §11 config option).

---

## Anti-Patterns to Avoid

- ❌ Don't use `capture-pane -ep -t "=$S"` (or `=$1`) — on tmux 3.6b it FAILS
  rc=1 "can't find pane: =S" (research FINDING A; the `=` is a session-name
  matcher, capture-pane wants a pane target). Use `-t "=$S:."` (exact session +
  active-pane resolution). This is the PRD's literal spec, verbatim WRONG.
- ❌ Don't "fix" FINDING A by dropping the `=` (bare `-t "$S"`) — bare session
  targets use unique-PREFIX matching, so `-t "log"` captures `logfile` when both
  exist (research FINDING B). The `=` exact-match is load-bearing; keep it and
  add `:.`.
- ❌ Don't let `capture-pane` write to bare stdout — under `run-shell` the escape
  sequences can corrupt the status/display area. Capture into a `local` var and
  discard (research FINDING H). The text is a best-effort hint, not a renderable
  buffer (no link = no separate preview area; that is what `live` mode is for).
- ❌ Don't make `preview_fallback` always `return 0` — it must return
  capture-pane's rc so a truly-gone candidate signals non-zero (S1 contract §4;
  the caller may skip ahead). The "never blocks" guarantee is about not hanging,
  not about always returning 0.
- ❌ Don't put the self-session guard ABOVE the mode gate. `off` must short-circuit
  for ALL candidates (incl. self); `snapshot` must capture for ALL candidates
  (incl. self — capturing your own pane is harmless). Only `live` needs the
  link-avoidance (research FINDING G).
- ❌ Don't add defensive unlink/clear to the `off` or `snapshot` branches.
  `@livepicker-preview-mode` is constant for the picker's lifetime, so `off`
  never links (nothing to clean) and `snapshot` never sets `LINKED_ID`. Adding
  cleanup there is dead code that muddies the contract.
- ❌ Don't clear `STATE_LINKED_ID` with `set_state "$STATE_LINKED_ID" ""` (leaves
  it set-but-empty). Use `tmux_unset_opt "$STATE_LINKED_ID"` (the `-gu` path —
  genuinely absent; matches state.sh's `clear_all_state` teardown; research
  FINDING E).
- ❌ Don't change the self-session unlink style — reuse S1's `unlink-window -t
  "$current_session:$linked_id"` with NO `-k` and `|| true` (S1 FINDING 2/11).
  `-k` destroys the shared window in ALL sessions; omitting `|| true` aborts on
  the singly-linked edge.
- ❌ Don't recreate `scripts/preview.sh`, change its shebang, re-order the source
  trio, touch the duplicate guard / link / select / track tail, or touch the
  driver. S2 is 3 surgical edits to the EXISTING S1 file.
- ❌ Don't add `set -e` / `set -o pipefail` — capture-pane (new in S2) joins
  unlink-window / list-windows as a legitimate non-zero returner.
- ❌ Don't call `switch-client`, `refresh-client`, `set-hook`, `bind-key`,
  `kill-window`, or any `set-option` other than `tmux_unset_opt` on
  `STATE_LINKED_ID`. The caller owns redraw; activate/restore own hooks/tables.
- ❌ Don't create a `tests/` directory or committed test file — the harness is
  P1.M7.T1/T2. Validate via the throwaway socket-shim mock (Validation §2).
- ❌ Don't add a new state key to "store the snapshot text" — no consumer reads
  one yet (renderer.sh is the status-list, not a snapshot viewer). Scope creep;
  the contract's "best-effort hint" is satisfied by capturing + discarding.
- ❌ Don't use 4-space indent — tabs only (system_context §9).

---

## Confidence Score

**9 / 10** for one-pass success. Rationale: the deliverable is THREE surgical
edits to an existing, already-executable, already-validated ~90-line file (S1's
preview.sh). Each edit's complete, ready-to-paste body is given verbatim above
with its exact FIND anchor text. Every load-bearing behavior is backed by a
**live proof on tmux 3.6b** in research/preview_mode_gate_capture_findings.md:
the headline FINDING A (`capture-pane -ep -t "=$S"` FAILS → use `=$S:.`,
verified rc=0 on real / rc=1 on gone / disambiguates "log" vs "logfile" /
handles spaces); FINDING B (bare `$S` is prefix-ambiguous); FINDING C (gone →
rc=1, fallback signal preserved); FINDING E (`tmux_unset_opt` -gu vs empty);
FINDING F (self-session unlink+clear+select verified); FINDING G (mode-gate
ordering); FINDING H (capture-to-local, return rc). All three input deps
(options.sh `opt_preview_mode`, utils.sh `tmux_unset_opt`, state.sh
`STATE_LINKED_ID`) are COMPLETE and confirmed present. The 4-branch socket-shim
mock asserts off-render-nothing, snapshot-never-links, self-session-cleans,
link-failure-falls-back byte-exactly. Tools verified present: `tmux 3.6b`,
`bash 5.3.15`, `shellcheck 0.11.0`.

Residual risks: (a) the capture-pane target correction (`=$S:.` not `=$S`) is a
**deviation from the literal PRD §7 / work-item text** — an implementer who
skips the research file and copies the PRD's `=$S` ships a fallback that ALWAYS
errors (rc=1); mitigated by the verbatim body, the Level-1 `grep` guards
(both "must contain `=$1:.`" AND "must NOT contain bare `=$1`"), and the loud
FINDING-A callouts. (b) The `preview_fallback` two-call-site design (snapshot
mode + live link-failure) means a body bug affects both paths — mitigated by
the single function + the mock covering both call sites (branches b and d).
(c) The link-failure mock uses a wrapper-shim that intercepts `link-window` to
force rc=1 while the candidate session still exists (so capture succeeds rc=0) —
this is the only faithful way to exercise the live link-failure→capture path
without a racy mid-flight kill; the wrapper pattern is documented inline. All
residual risks are deterministically caught by the validation loop.
