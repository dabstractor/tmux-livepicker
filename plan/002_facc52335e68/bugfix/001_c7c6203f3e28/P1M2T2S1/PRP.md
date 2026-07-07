# PRP — Bugfix P1.M2.T2.S1: stable sentinel session name + second renderer swap (Issue 5)

> **Bug context**: Issue 5 (Minor) from the rev-002 QA pass
> (`plan/002_facc52335e68/bugfix/001_c7c6203f3e28/architecture/issue4_5_6_findings.md` §Issue 5).
> The §17 theme-tab mechanism resolves the user's `window-status-format` /
> `window-status-current-format` against a short-lived hidden sentinel SESSION + WINDOW,
> caching the rendered template. The sentinel WINDOW is named `__lp_tab__` (a fixed
> placeholder) so `#W` bakes `__lp_tab__` and the renderer swaps it → the candidate name.
> BUT the sentinel SESSION is named `__lp_sent_$$_$(date +%s)` (unique per activation), so
> any SESSION-state specifier (`#S`, `#{session_name}`) bakes that UNIQUE name into the
> template — which the renderer does NOT swap. Result: every tab renders the literal
> `__lp_sent_<PID>_<EPOCH>` for themes that use session-state specifiers. The unexpanded-`#{`
> guard does not catch it (the specifier expanded fully). The fix: make the sentinel SESSION
> name a fixed placeholder `__lp_sentinel__` (pre-cleaning any stray), and add a SECOND
> renderer swap (`__lp_sentinel__` → candidate name) alongside the existing `__lp_tab__` swap.

---

## Goal

**Feature Goal**: When `@livepicker-tab-style` is `window-status`, a theme whose
`window-status-format` / `window-status-current-format` contains a SESSION-state specifier
(`#S`, `#{session_name}`) renders each tab with the candidate's actual name — not the
literal sentinel session name. The sentinel session is renamed to a fixed, swappable
placeholder `__lp_sentinel__` (with a pre-clean of any stray from a crashed prior run), and
the renderer swaps BOTH `__lp_tab__` (window-name placeholder) AND `__lp_sentinel__`
(session-name placeholder) → the candidate name.

**Deliverable**: Two small edits to existing files — **no new files, no committed test**
(Mode A: inline-comment updates).
1. `scripts/livepicker.sh::_lp_resolve_tab_templates`: change `sent_sess` from
   `__lp_sent_$$_$(date +%s)` to `__lp_sentinel__`, and add a pre-clean
   `tmux kill-session -t "__lp_sentinel__" 2>/dev/null || true` before `new-session`.
2. `scripts/renderer.sh` (window-status path): add a second swap
   `ws_seg="${ws_seg//__lp_sentinel__/$esc_wname}"` after the existing `__lp_tab__` swap.

**Success Definition**:
- A theme with `window-status-current-format '#[fg=red]#{session_name}#[default]'` (or `#S`)
  renders each tab as the candidate's actual session name (escaped), NOT `__lp_sentinel__`
  / `__lp_sent_<PID>_<EPOCH>`.
- A theme with `#W` (window name) STILL renders correctly (the `__lp_tab__` swap is
  unchanged) — no regression.
- A theme with BOTH `#W` and `#S` renders both placeholders as the candidate name (the
  findings doc's accepted behavior).
- The pre-clean removes a stray `__lp_sentinel__` from a crashed prior run; a normal
  (absent) sentinel is a silent no-op (`2>/dev/null || true`).
- The throwaway smoke proves both halves; `tests/run.sh` stays green (the change is confined
  to the window-status render path; the plain path + all existing tests are untouched).

## User Persona (if applicable)

**Target User**: The end user whose tmux theme puts a session-state specifier
(`#S`/`#{session_name}`) in `window-status-format` / `window-status-current-format`, and who
enables `@livepicker-tab-style window-status`. Also the maintainer / QA.

**Use Case**: The user activates the picker with `tab-style window-status`. Their theme's
window-status format references the session name. The tabs must show each candidate's actual
session name, styled per the theme — not the literal internal sentinel name.

**Pain Points Addressed**: Today those tabs all show `__lp_sent_<PID>_<EPOCH>` (a confusing
internal string) instead of the session names, making the window-status tab style unusable
for session-name themes. The fix makes it work as the README/PRD §17 promise.

## Why

- **Real, reachable bug.** Session-state specifiers in window-status-format are common in
  popular tmux themes (e.g. a tab showing the session name). With `tab-style window-status`,
  the sentinel resolution bakes the unique sentinel SESSION name, and the renderer misses it.
  Reproduced live (research FINDING 1).
- **The fix is the documented one.** The findings doc §Issue 5 recommends exactly this:
  stable sentinel session name + second renderer swap. Both halves are **live-verified**
  (research FINDING 2: `#{session_name}`/`#S` → `__lp_sentinel__` with the fixed name;
  FINDING 3: the double-swap is single-pass, no recursion).
- **Cheap, surgical, low-risk.** One assignment change + one pre-clean line in livepicker.sh;
  one swap line + a comment tweak in renderer.sh. No new function, no new state key, no new
  sourcing, no new file. The `__lp_tab__` swap and the plain render path are UNCHANGED.
- **Concurrency-safe.** The modal `@livepicker-mode` guard (livepicker.sh line 124) blocks a
  second activation, so two `_lp_resolve_tab_templates` calls cannot run concurrently (research
  FINDING 5). The sentinel lives only milliseconds (created line 77, killed line 98). The
  pre-clean handles crashed-prior-run strays (FINDING 4).
- **Disjoint from the parallel task.** P1.M2.T1.S1 (Issue 4, in-flight) edits `preview.sh`
  ONLY. This task edits `livepicker.sh` + `renderer.sh` — no shared file, no collision
  (research FINDING 8).

## What

1. **livepicker.sh `_lp_resolve_tab_templates`**: change the sentinel session name to a fixed
   placeholder. BEFORE creating it, pre-clean any stray sentinel
   (`tmux kill-session -t "__lp_sentinel__" 2>/dev/null || true`). Then
   `sent_sess="__lp_sentinel__"`. Update the block's comment to reflect "fixed stable
   placeholder name (swappable by the renderer) + pre-clean of strays" instead of the old
   "unique name (PID+epoch) avoids collision".
2. **renderer.sh (window-status path)**: after the existing
   `ws_seg="${ws_tpl//__lp_tab__/$esc_wname}"` swap, add a second swap
   `ws_seg="${ws_seg//__lp_sentinel__/$esc_wname}"`. Update the comment to note the
   session-name placeholder. (Both placeholders map to `$esc_wname` — the candidate's name.)
3. **Do NOT change**: the `__lp_tab__` swap, the plain render path, the cached-template state
   keys (`STATE_TAB_CURRENT_TMPL`/`STATE_TAB_INACTIVE_TMPL`), the unexpanded-`#{` guard, the
   sentinel window name (`__lp_tab__`), the `new-session`/`new-window`/`select-window`/
   `kill-session` structure, any other script, or any stored-state shape. The `#W`-only
  theme behavior is byte-for-byte identical.

### Success Criteria

- [ ] `livepicker.sh` uses `sent_sess="__lp_sentinel__"` (no `__lp_sent_$$_$(date +%s)`).
- [ ] A pre-clean `tmux kill-session -t "__lp_sentinel__" 2>/dev/null || true` precedes the
      `new-session -s "$sent_sess"`.
- [ ] `renderer.sh` has BOTH `ws_seg="${ws_tpl//__lp_tab__/$esc_wname}"` AND (after it)
      `ws_seg="${ws_seg//__lp_sentinel__/$esc_wname}"`.
- [ ] Throwaway smoke: a `#{session_name}`/`#S` theme renders candidate names, NOT
      `__lp_sentinel__`; a `#W` theme still renders names (no regression).
- [ ] `bash -n` + `shellcheck` clean on both files; `tests/run.sh` green (exit 0).

## All Needed Context

### Context Completeness Check

_Pass_: A developer who has never seen this repo can implement the fix from (a) the exact
old→new code blocks (quoted verbatim with content anchors, below), (b) the verbatim
throwaway smoke, and (c) the load-bearing rules (fixed placeholder name; pre-clean before
create; second swap is single-pass so no recursion; both placeholders → `$esc_wname`).
All live-proven in research/sentinel_session_name_findings.md.

### Documentation & References

```yaml
# MUST READ — the empirical ground-truth for THIS fix (12 live-verified findings)
- docfile: plan/002_facc52335e68/bugfix/001_c7c6203f3e28/P1M2T2S1/research/sentinel_session_name_findings.md
  why: FINDING 1 (bug repro: #{session_name}/#S -> __lp_sent_PID_EPOCH, not swappable);
       FINDING 2 (the fix: fixed __lp_sentinel__ -> both specifiers swappable); FINDING 3
       (the double-swap is single-pass, NO recursion — pathological case verified);
       FINDING 4 (pre-clean kill-session is idempotent, || true-guarded); FINDING 5 (the
       modal @livepicker-mode guard at line 124 blocks concurrent sentinel collisions);
       FINDING 6 (RESIDUAL: a user session named __lp_sentinel__ would be destroyed by the
       pre-clean — vanishing probability, accepted trade-off); FINDING 7 (#{session_id} ->
       $4 is NOT covered, out of scope); FINDING 8 (DISJOINT from parallel P1.M2.T1.S1);
       FINDING 9 (Mode A — no committed test; test_appearance.sh is the parent plan's);
       FINDING 10 (livepicker.sh runs activate on source — smoke must NOT source it);
       FINDING 11 (both placeholders -> same $esc_wname; a #W+#S theme renders the name
       twice, accepted); FINDING 12 (exact content anchors).
  critical: FINDING 6 (document the user-collision residual) + FINDING 3 (no recursion) +
            FINDING 5 (concurrency safety).

# MUST READ — the bug report (root cause + repro + the recommended fix with verbatim snippets)
- docfile: plan/002_facc52335e68/bugfix/001_c7c6203f3e28/architecture/issue4_5_6_findings.md
  why: §Issue 5 gives the exact bug locations (livepicker.sh _lp_resolve_tab_templates line
       76; renderer.sh window-status path line 130), the root cause (sentinel session name
       is unique, not a fixed placeholder), the empirical proof (#W -> __lp_tab__ swappable;
       #{session_name}/#S -> __lp_sent_123_456 NOT swappable), the recommended fix (stable
       sentinel name + pre-clean + second swap), and the collision-safety reasoning (modal
       guard + short lifetime + pre-clean).
  section: "Issue 5: Sentinel resolution does not handle session-context format specifiers"

# MUST READ — the file edited for Edit 1 (the sentinel creation block)
- file: scripts/livepicker.sh
  why: _lp_resolve_tab_templates() (lines 54-115) creates the sentinel session (line 76
        sent_sess, line 77 new-session), the sentinel window __lp_tab__ (line 83), resolves
        the formats (lines 94-95), kills the sentinel (line 98), guards on unexpanded '#{'
        (lines 102-103), caches (lines 112-113). Edit 1 changes line 76 + adds the pre-clean
        before line 77 + updates the block comment (lines 72-75).
  pattern: the existing kill-session idiom `tmux kill-session -t "$sent_sess" 2>/dev/null || true`
           (line 84, 98) — the pre-clean mirrors it with the literal name.
  gotcha: livepicker.sh ends with `activate_main "$@" || exit 1` — SOURCING it runs
          activate (needs an attached client). The smoke must NOT source it; test the
          resolution inline + the renderer via seeded state (research FINDING 10).

# MUST READ — the file edited for Edit 2 (the window-status swap block)
- file: scripts/renderer.sh
  why: render()'s window-status path (lines 60-150) builds the joined tabs. The swap block
        (lines 128-130) does `ws_seg="${ws_tpl//__lp_tab__/$esc_wname}"`. Edit 2 adds the
        second swap `ws_seg="${ws_seg//__lp_sentinel__/$esc_wname}"` after it + updates the
        comment. The surrounding loop (lines 116-136) computes $esc_wname per candidate.
  pattern: the existing `${var//pat/rep}` swap (line 130) — the second swap mirrors it on
           $ws_seg (the first swap's output). Both use the SAME $esc_wname.
  gotcha: ${var//pat/rep} does NOT re-scan the replacement (research FINDING 3) — so a name
          equal to __lp_sentinel__ cannot corrupt or recurse. The existing comment (lines
          128-129) documents this for __lp_tab__; it holds identically for __lp_sentinel__.

# MUST READ — the original §17 sentinel research (WHY the sentinel exists + the #W approach)
- docfile: plan/002_facc52335e68/P1M1T2S1/research/sentinel_resolution_findings.md
  why: Documents the sentinel mechanism (hidden 2-window session; display-message resolves
       #W -> __lp_tab__; cache once; the unexpanded-'#{' guard; the set-empty contract).
       This fix EXTENDS that mechanism to session-state specifiers by making the sentinel
       SESSION name a placeholder too. Understanding the original design prevents breaking it.
  section: the #W resolution + the cache-once + fallback contract

# Reference — PRD §17 (the theme-tab feature spec) + §16 (fragility)
- docfile: PRD.md
  why: §17 ("The sentinel window", "window-state specifiers resolve to the sentinel's state",
       the plain fallback). §16 "Window-status hijack fragility" (#{...} in a theme is NOT
       re-expanded in #() output — must be pre-resolved; fall back to plain on failure).
  section: "§17 Tab appearance", "§16 Implementation risks (Window-status hijack fragility)"

# Reference — the test landscape (NOT modified; for the suite-green claim)
- file: tests/test_appearance.sh
  why: The existing §17 window-status test (parent plan 002 P1.M3.T2). This task does NOT
        add to it (Mode A; owned by another milestone). The suite-green claim relies on it
        continuing to pass (the __lp_tab__ swap is unchanged; only a second swap is added).
- file: tests/setup_socket.sh / tests/helpers.sh
  why: The throwaway smoke reuses the PATH-shim isolation + assert helpers. setup_test brings
        the isolated -L socket + baseline fixtures.
```

### Current Codebase tree

```bash
tmux-livepicker/
  scripts/
    livepicker.sh   # MODIFY: _lp_resolve_tab_templates — sent_sess -> "__lp_sentinel__" + pre-clean kill-session
    renderer.sh     # MODIFY: window-status path — +second swap __lp_sentinel__ -> $esc_wname
    options.sh / utils.sh / state.sh / filter.sh   # UNCHANGED (opt_tab_style/STATE_TAB_*/get_state — read only)
    preview.sh / input-handler.sh / restore.sh / plugin.tmux  # UNCHANGED
                    # NOTE: P1.M2.T1.S1 (parallel) modifies preview.sh ONLY — DISJOINT from this task.
  tests/            # UNCHANGED (Mode A; test_appearance.sh is the parent plan's. Validate via throwaway smoke.)
```

### Desired Codebase tree with files to be added and responsibility of file

```bash
scripts/livepicker.sh  # sentinel session name is a fixed placeholder __lp_sentinel__ (swappable); pre-clean strays
scripts/renderer.sh    # +second swap: __lp_sentinel__ -> $esc_wname (session-name placeholder, alongside __lp_tab__)
```

### Known Gotchas of our codebase & Library Quirks

```bash
# CRITICAL (research FINDING 6): the FIXED sentinel name __lp_sentinel__ means the pre-clean
# `kill-session -t "__lp_sentinel__"` would destroy a USER session with that exact name.
# Vanishing probability (internal-looking double-underscore name), but DOCUMENT it. The old
# unique name (PID+epoch) was collision-free; the fixed name is REQUIRED so the renderer can
# swap a known placeholder. Mitigations: modal guard (no concurrent picker), short lifetime,
# pre-clean of strays. Accepted trade-off per the contract.

# CRITICAL (research FINDING 3): ${var//pat/rep} does NOT re-scan the replacement. The
# second swap is safe — a candidate name that happens to contain __lp_sentinel__ (or
# __lp_tab__) cannot trigger recursion. Verified with the pathological case. The existing
# renderer comment (lines 128-129) documents this for __lp_tab__; it holds for __lp_sentinel__.

# CRITICAL (research FINDING 5): concurrency safety relies on the modal @livepicker-mode guard
# (livepicker.sh line 124) blocking a 2nd activation. Do NOT remove/weaklen that guard. Two
# concurrent _lp_resolve_tab_templates calls would collide on the fixed sentinel name.

# GOTCHA (research FINDING 7): #{session_id} resolves to $4 (tmux internal id), NOT a stable
# placeholder. Out of scope (contract covers #{session_name}/#S). Document as a residual.

# GOTCHA (research FINDING 11): both __lp_tab__ and __lp_sentinel__ map to the SAME $esc_wname
# (the candidate's name). A theme with #W+#S renders the name twice (name:name). Accepted —
# the alternative (per-candidate display-message in the renderer) defeats the cache-once
# optimization.

# GOTCHA (research FINDING 10): livepicker.sh ends with `activate_main "$@" || exit 1`.
# SOURCING it runs activate (needs an attached client + switch-client). The smoke must NOT
# source livepicker.sh — test the resolution inline + the renderer via seeded @livepicker-*
# state (the renderer reads cached templates from state, not from livepicker).

# GOTCHA: the sentinel WINDOW name stays __lp_tab__ (UNCHANGED). Only the sentinel SESSION
# name changes to __lp_sentinel__. Do not touch the __lp_tab__ window name or its swap.

# GOTCHA: the pre-clean must come BEFORE new-session (so a stray sentinel from a crashed
# prior run is gone before we try to create a fresh one). new-session -s on an EXISTING
# session name FAILS (rc=1) -> would trigger the set-empty fallback -> plain tabs. The
# pre-clean prevents that.

# GOTCHA: keep `2>/dev/null || true` on the pre-clean kill-session — it returns rc=1 when
# the sentinel is absent (the normal case); without the guard, under set -e it would abort.
# livepicker.sh has NO set -e (confirmed), but the guard is correct hygiene regardless.

# STYLE: TABS (whole codebase; shfmt absent). livepicker.sh edits are at 1-tab indent inside
# _lp_resolve_tab_templates; the renderer swap is at 3-tab indent (inside the for-loop inside
# the if-inside-if window-status path). Match the existing surrounding indent.
```

## Implementation Blueprint

### Data models and structure

No data-model change. The "model" is one renamed constant string + one added swap line:

```
_lp_resolve_tab_templates (livepicker.sh):
  ... read cur_fmt/reg_fmt ...
  PRE-CLEAN: kill-session -t "__lp_sentinel__" (stray from crashed prior run)   # <- NEW
  sent_sess = "__lp_sentinel__"   # was: __lp_sent_$$_$(date +%s)                # <- CHANGED
  new-session -s "$sent_sess" -n __lp_anchor__   (UNCHANGED)
  new-window  -t "$sent_sess:" -n __lp_tab__     (UNCHANGED — sentinel window name stays)
  display-message ... -> cur_tpl/reg_tpl         (UNCHANGED — now bakes __lp_sentinel__ for #S)
  kill-session -t "$sent_sess"                   (UNCHANGED)
  ... unexpanded-'#{' guard, cache ...

render() window-status path (renderer.sh):
  for each candidate:
      esc_wname = candidate name, # escaped
      ws_seg = ws_tpl with __lp_tab__ -> esc_wname        (UNCHANGED)
      ws_seg = ws_seg with __lp_sentinel__ -> esc_wname   # <- NEW (session-name placeholder)
      join with ws_sep ...
```

### Implementation Tasks (ordered by dependencies)

```yaml
Task 1: MODIFY scripts/livepicker.sh — fixed sentinel name + pre-clean
  - LOCATE (by content) _lp_resolve_tab_templates's sentinel-creation block. The anchor:
        # (b) Create a unique hidden 2-window session (anchor + sentinel). CRITICAL (FINDING 1):
        # `new-window -d -t "$sent_sess"` (bare) FAILS under base-index=1/renumber ("index in
        # use"); the TRAILING-COLON form `-t "$sent_sess:"` picks a free slot. Force-select the
        # anchor so __lp_tab__ is NON-active -> clean window-state specifiers. Unique name
        # (PID+epoch) avoids a double-activation collision.
        sent_sess="__lp_sent_$$_$(date +%s)"
        if ! tmux new-session -d -s "$sent_sess" -n __lp_anchor__ 2>/dev/null; then
  - ACTION: (a) rewrite the comment to reflect the fixed-placeholder + pre-clean rationale;
    (b) insert the pre-clean `tmux kill-session -t "__lp_sentinel__" 2>/dev/null || true`
    BEFORE the `sent_sess=` assignment; (c) change `sent_sess="__lp_sent_$$_$(date +%s)"` to
    `sent_sess="__lp_sentinel__"`. See Implementation Patterns for the verbatim old→new.
  - WHY: the fixed name makes #{session_name}/#S bake a swappable placeholder (research
    FINDING 2). The pre-clean clears strays so new-session does not fail on a stale name
    (FINDING 4). Concurrency is safe via the modal guard (FINDING 5).
  - DO NOT: touch new-session/new-window/select-window/kill-session/display-message lines,
    the sentinel WINDOW name (__lp_tab__), the unexpanded-'#{' guard, or the cache logic.

Task 2: MODIFY scripts/renderer.sh — second swap in the window-status path
  - LOCATE (by content) the swap block. The anchor:
            # literal swap: ${var//pat/rep} does not re-scan the replacement, so a name
            # equal to __lp_tab__ cannot corrupt or recurse.
            ws_seg="${ws_tpl//__lp_tab__/$esc_wname}"
  - ACTION: add a second swap line AFTER it:
            ws_seg="${ws_seg//__lp_sentinel__/$esc_wname}"
    and extend the comment to mention the session-name placeholder. See Implementation
    Patterns for the verbatim old→new.
  - WHY: the cached template may contain __lp_sentinel__ (baked from #S/#{session_name});
    the renderer must swap it to the candidate name. Single-pass ${var//pat/rep} — no
    recursion (research FINDING 3).
  - DO NOT: touch the __lp_tab__ swap, $esc_wname computation, the loop, the join, the plain
    path, or any other line.

Task 3: VALIDATE (throwaway smoke via the existing socket-isolated harness)
  - RUN: bash -n scripts/livepicker.sh scripts/renderer.sh
  - RUN: shellcheck scripts/livepicker.sh scripts/renderer.sh (expect 0 NEW findings).
  - RUN: grep cross-checks (L1) — sent_sess is "__lp_sentinel__" (no PID+epoch); the pre-clean
    kill-session precedes new-session; BOTH swaps present in renderer.sh.
  - RUN: the throwaway smoke (L2) — proves a #{session_name}/#S theme renders candidate names
    (NOT __lp_sentinel__), and a #W theme still renders names (no regression). Then DELETE it.
  - RUN: tests/run.sh (expect full suite green — the change is confined to the window-status
    path; the plain path + test_appearance.sh's #W-based assertions are untouched).
```

### Implementation Patterns & Key Details

**Task 1 — livepicker.sh sentinel block (paste verbatim).** CURRENT:

```bash
	# (b) Create a unique hidden 2-window session (anchor + sentinel). CRITICAL (FINDING 1):
	# `new-window -d -t "$sent_sess"` (bare) FAILS under base-index=1/renumber ("index in
	# use"); the TRAILING-COLON form `-t "$sent_sess:"` picks a free slot. Force-select the
	# anchor so __lp_tab__ is NON-active -> clean window-state specifiers. Unique name
	# (PID+epoch) avoids a double-activation collision.
	sent_sess="__lp_sent_$$_$(date +%s)"
	if ! tmux new-session -d -s "$sent_sess" -n __lp_anchor__ 2>/dev/null; then
```
→

```bash
	# (b) Create a hidden 2-window sentinel session (anchor + tab). CRITICAL (FINDING 1):
	# `new-window -d -t "$sent_sess"` (bare) FAILS under base-index=1/renumber ("index in
	# use"); the TRAILING-COLON form `-t "$sent_sess:"` picks a free slot. Force-select the
	# anchor so __lp_tab__ is NON-active -> clean window-state specifiers. The sentinel
	# SESSION name is a FIXED placeholder `__lp_sentinel__` (not unique) so that a theme's
	# SESSION-state specifiers (#S / #{session_name}) bake a STABLE placeholder the renderer
	# can swap — mirroring the sentinel WINDOW name `__lp_tab__` (from #W). Issue 5.
	# Pre-clean any stray sentinel left by a crashed prior run (new-session on an existing
	# name would FAIL -> set-empty fallback -> plain tabs). Concurrency-safe: the modal
	# @livepicker-mode guard (activate_main) blocks a 2nd activation, so no two sentinels
	# coexist. RESIDUAL: a user session literally named __lp_sentinel__ would be destroyed
	# here (vanishing probability; the fixed name is required for the renderer swap).
	tmux kill-session -t "__lp_sentinel__" 2>/dev/null || true
	sent_sess="__lp_sentinel__"
	if ! tmux new-session -d -s "$sent_sess" -n __lp_anchor__ 2>/dev/null; then
```

**Task 2 — renderer.sh second swap (paste verbatim).** CURRENT:

```bash
			# literal swap: ${var//pat/rep} does not re-scan the replacement, so a name
			# equal to __lp_tab__ cannot corrupt or recurse.
			ws_seg="${ws_tpl//__lp_tab__/$esc_wname}"
```
→

```bash
			# literal swaps: ${var//pat/rep} does not re-scan the replacement, so a name
			# equal to a placeholder cannot corrupt or recurse. __lp_tab__ is the sentinel
			# WINDOW name (from #W); __lp_sentinel__ is the sentinel SESSION name (from #S /
			# #{session_name} — Issue 5). Both map to the SAME candidate name ($esc_wname):
			# each tab represents one candidate, whose display name is identical whether the
			# theme used #W or #S (a #W+#S theme renders the name twice — accepted).
			ws_seg="${ws_tpl//__lp_tab__/$esc_wname}"
			ws_seg="${ws_seg//__lp_sentinel__/$esc_wname}"
```

(The rest of the window-status path — the loop, the join, the SHOW_COUNT suffix, the
printf — is UNCHANGED. The plain render path is UNCHANGED.)

### Integration Points

```yaml
CODE:
  - file: scripts/livepicker.sh
    change: "_lp_resolve_tab_templates: sent_sess -> '__lp_sentinel__'; +pre-clean kill-session;
             comment updated"
    invariant: "the cached templates bake __lp_sentinel__ (not __lp_sent_PID_EPOCH) for #S;
               the __lp_tab__ window name + #W resolution unchanged"
  - file: scripts/renderer.sh
    change: "window-status path: +second swap __lp_sentinel__ -> $esc_wname"
    invariant: "a #S/#{session_name} theme renders candidate names; #W theme unchanged;
               both swaps single-pass (no recursion)"

CONSUMERS / PRODUCERS:
  - renderer.sh READS the cached STATE_TAB_CURRENT_TMPL/STATE_TAB_INACTIVE_TMPL that
    _lp_resolve_tab_templates WRITES. Both must agree on the placeholder name __lp_sentinel__
    (this task updates both sides together).
  - tests/test_appearance.sh (parent plan 002): exercises the #W window-status path. Unchanged
    by this fix (the __lp_tab__ swap is untouched); must still pass.

CONFIG / DATABASE / ROUTES: none.
```

## Validation Loop

### Level 1: Syntax & Style (Immediate Feedback)

```bash
cd /home/dustin/.config/tmux/plugins/tmux-livepicker
bash -n scripts/livepicker.sh scripts/renderer.sh && echo "OK: syntax"
shellcheck scripts/livepicker.sh scripts/renderer.sh   # expect 0 NEW findings
# livepicker.sh: fixed sentinel name (no PID+epoch) + pre-clean before new-session:
grep -c 'sent_sess="__lp_sentinel__"' scripts/livepicker.sh                       # -> 1
grep -c '__lp_sent_\$\$_\$(date' scripts/livepicker.sh                             # -> 0  (old unique form gone)
grep -B1 'sent_sess="__lp_sentinel__"' scripts/livepicker.sh | grep -q 'kill-session -t "__lp_sentinel__"' \
  && echo "OK: pre-clean precedes sent_sess" || echo "FAIL"
# renderer.sh: BOTH swaps present, __lp_sentinel__ swap AFTER __lp_tab__ swap:
grep -c 'ws_seg="\${ws_tpl//__lp_tab__/\$esc_wname}"' scripts/renderer.sh         # -> 1
grep -c 'ws_seg="\${ws_seg//__lp_sentinel__/\$esc_wname}"' scripts/renderer.sh    # -> 1
awk '/ws_tpl\/\/__lp_tab__/{t=NR} /ws_seg\/\/__lp_sentinel__/{s=NR} END{if(t&&s&&t<s) print "OK: __lp_sentinel__ swap after __lp_tab__"; else print "FAIL: swap order"}' scripts/renderer.sh
# Tabs-not-spaces in the edited regions:
grep -nP '^ +[^#/]' scripts/livepicker.sh scripts/renderer.sh && echo "WARN: space-indent" || echo "OK: tabs"
# Expected: syntax clean; shellcheck 0 new findings; sent_sess is __lp_sentinel__; the old
# PID+epoch form is gone; the pre-clean precedes new-session; BOTH swaps present in order.
```

### Level 2: Throwaway smoke — prove the fix (then DELETE)

```bash
cd /home/dustin/.config/tmux/plugins/tmux-livepicker
cat > /tmp/lp_issue5_smoke.sh <<'SMOKE'
#!/usr/bin/env bash
set -u
cd /home/dustin/.config/tmux/plugins/tmux-livepicker
source tests/setup_socket.sh
source tests/helpers.sh
setup_test "lp-issue5-smoke"
source scripts/utils.sh; source scripts/options.sh; source scripts/state.sh; source scripts/filter.sh
pass_n=0; fail_n=0
ck() { if [ "$2" = "$3" ]; then pass_n=$((pass_n+1)); else fail_n=$((fail_n+1)); echo "FAIL $1: got[$2] want[$3]"; fi; }

# --- (A) The sentinel resolution bakes __lp_sentinel__ for #S / #{session_name} ---
# Replicate _lp_resolve_tab_templates's sentinel (with the FIXED name) + display-message.
tmux kill-session -t "__lp_sentinel__" 2>/dev/null || true
tmux new-session -d -s "__lp_sentinel__" -n __lp_anchor__ 2>/dev/null
tmux new-window  -d -t "__lp_sentinel__:" -n __lp_tab__ 2>/dev/null
tmux select-window -t "__lp_sentinel__:__lp_anchor__" 2>/dev/null || true
# #S / #{session_name} must resolve to the FIXED placeholder (swappable), not a unique name:
s_val="$(tmux display-message -p -t "__lp_sentinel__:__lp_tab__" '#S')"
sn_val="$(tmux display-message -p -t "__lp_sentinel__:__lp_tab__" '#{session_name}')"
w_val="$(tmux display-message -p -t "__lp_sentinel__:__lp_tab__" '#W')"
ck "A: #S -> __lp_sentinel__"        "$s_val"  "__lp_sentinel__"
ck "A: #{session_name} -> placeholder" "$sn_val" "__lp_sentinel__"
ck "A: #W -> __lp_tab__ (unchanged)" "$w_val"  "__lp_tab__"
tmux kill-session -t "__lp_sentinel__" 2>/dev/null || true

# --- (B) The renderer swaps BOTH placeholders -> candidate names (end-to-end via state) ---
# Seed a cached template that baked __lp_sentinel__ (simulating a #S theme after resolution),
# set tab-style window-status, seed the list, run the REAL renderer, assert NO __lp_sentinel__
# in the output (it was swapped to the candidate names).
tmux set-option -g @livepicker-tab-style window-status
tmux set-option -g @livepicker-tab-current-tmpl '#[fg=red,bold]__lp_sentinel__#[default]'
tmux set-option -g @livepicker-tab-inactive-tmpl '#[fg=blue]__lp_sentinel__#[default]'
tmux set-option -g @livepicker-list $'alpha\nbeta\n#dev'
tmux set-option -g @livepicker-filter ""
tmux set-option -g @livepicker-index "0"
tmux set-option -g @livepicker-show-count off
out="$("$LIVEPICKER_SCRIPTS/renderer.sh")"
echo "renderer out: $out"
# NO residual placeholder (the swap replaced every __lp_sentinel__):
case "$out" in *"__lp_sentinel__"*) fail_n=$((fail_n+1)); echo "FAIL B: __lp_sentinel__ leaked into output";; *) pass_n=$((pass_n+1)); echo "ok B: no __lp_sentinel__ leak";; esac
# The candidate names ARE present (escaped): alpha, beta, ##dev (#dev -> ##dev).
case "$out" in *"alpha"*) ;; *) fail_n=$((fail_n+1)); echo "FAIL B: alpha missing";; esac
case "$out" in *"beta"*)  ;; *) fail_n=$((fail_n+1)); echo "FAIL B: beta missing";; esac
case "$out" in *"##dev"*) ;; *) fail_n=$((fail_n+1)); echo "FAIL B: ##dev (escaped #dev) missing";; esac

# --- (C) No regression: a #W theme (__lp_tab__) still renders names ---
tmux set-option -g @livepicker-tab-current-tmpl '#[fg=green]__lp_tab__#[default]'
tmux set-option -g @livepicker-tab-inactive-tmpl '#[fg=green]__lp_tab__#[default]'
out2="$("$LIVEPICKER_SCRIPTS/renderer.sh")"
case "$out2" in *"__lp_tab__"*) fail_n=$((fail_n+1)); echo "FAIL C: __lp_tab__ leaked";; *) pass_n=$((pass_n+1)); echo "ok C: __lp_tab__ swapped";; esac
case "$out2" in *"alpha"*) ;; *) fail_n=$((fail_n+1)); echo "FAIL C: alpha missing";; esac

teardown_test
echo "pass=$pass_n fail=$fail_n"
[ "$fail_n" -eq 0 ]
SMOKE
bash /tmp/lp_issue5_smoke.sh; rc=$?
rm -f /tmp/lp_issue5_smoke.sh
exit $rc
# Expected: pass≈10 fail=0. (A) proves the resolution bakes __lp_sentinel__ for #S/#S{session_name}
# and __lp_tab__ for #W. (B) proves the renderer swaps __lp_sentinel__ -> names (no leak; alpha/
# beta/##dev present). (C) proves the #W path is unchanged (no __lp_tab__ leak; alpha present).
```

### Level 3: Full suite (no regression)

```bash
cd /home/dustin/.config/tmux/plugins/tmux-livepicker
tests/run.sh
# Expected: exit 0, all tests green. The change is confined to the window-status render path:
#  - the __lp_tab__ swap is UNCHANGED -> test_appearance.sh's #W-based assertions still pass.
#  - the plain render path is UNCHANGED -> all other renderer tests still pass.
#  - livepicker.sh's sentinel creation changes only the SESSION name + adds a pre-clean; the
#    activate flow is otherwise identical -> activate/restore/pollution tests still pass.
# If test_appearance.sh FAILS, re-check that the __lp_tab__ swap line is intact and the second
# swap is ADDED (not replacing the first).
```

## Final Validation Checklist

### Technical Validation

- [ ] `bash -n scripts/livepicker.sh scripts/renderer.sh` clean.
- [ ] `shellcheck` on both: 0 NEW findings.
- [ ] L1 grep: `sent_sess="__lp_sentinel__"` ×1; old `__lp_sent_$$_$(date +%s)` ×0; pre-clean
      `kill-session -t "__lp_sentinel__"` precedes `new-session`; BOTH renderer swaps present
      in order (`__lp_tab__` then `__lp_sentinel__`).
- [ ] L2 throwaway smoke: pass≈10 fail=0 (resolution bakes placeholder; renderer swaps it;
      no #W regression).

### Feature Validation

- [ ] A `#{session_name}` / `#S` theme renders candidate names (not `__lp_sentinel__`).
- [ ] A `#W` theme renders candidate names (unchanged — no regression).
- [ ] A theme with both `#W` and `#S` renders both placeholders as the candidate name.
- [ ] The pre-clean removes a stray sentinel; an absent sentinel is a silent no-op.
- [ ] L3 `tests/run.sh` green (exit 0).

### Code Quality Validation

- [ ] The sentinel WINDOW name `__lp_tab__` and its swap are UNCHANGED.
- [ ] The second swap mirrors the first's `${var//pat/rep}` shape; single-pass (no recursion).
- [ ] Both placeholders map to `$esc_wname` (the candidate's escaped name).
- [ ] Comments cross-reference PRD §17, issue4_5_6_findings.md §Issue 5, and the residual
      (user-collision + `#{session_id}`).
- [ ] TABS; no new sourcing/function/state-key/file.

### Documentation & Deployment

- [ ] Inline comments document the session-name placeholder + the pre-clean + the residual
      (Mode A).
- [ ] No README/CHANGELOG edit here (Mode A internal; the cross-cutting doc sync is P1.M3.T1).

---

## Anti-Patterns to Avoid

- ❌ Don't keep the unique `__lp_sent_$$_$(date +%s)` sentinel name — the renderer cannot swap
  a per-activation-unique string. The fix REQUIRES the fixed `__lp_sentinel__` name (research
  FINDING 1/2).
- ❌ Don't forget the pre-clean `kill-session` before `new-session`. Without it, a stray
  sentinel from a crashed prior run makes `new-session -s "__lp_sentinel__"` FAIL → set-empty
  fallback → plain tabs (silent regression after a crash) (research FINDING 4).
- ❌ Don't drop the `2>/dev/null || true` on the pre-clean — `kill-session` returns rc=1 when
  the sentinel is absent (the normal case).
- ❌ Don't touch the `__lp_tab__` swap or the sentinel WINDOW name — only the SESSION name
  changes. The `#W` path must stay byte-identical (research FINDING 11).
- ❌ Don't worry about recursion in the second swap — `${var//pat/rep}` is single-pass and does
  NOT re-scan the replacement (research FINDING 3; verified with the pathological case).
- ❌ Don't change the cached-template state keys, the unexpanded-`#{` guard, or the cache
  logic — the fix is purely the sentinel NAME + the renderer SWAP.
- ❌ Don't source livepicker.sh in the smoke — it runs `activate_main` on source (needs an
  attached client). Test the resolution inline + the renderer via seeded state (research
  FINDING 10).
- ❌ Don't add a committed `tests/` file — Mode A. `test_appearance.sh` is owned by the parent
  plan (002 P1.M3.T2); validate via the throwaway L2 smoke (then delete it).
- ❌ Don't claim the fix covers `#{session_id}` — it resolves to `$4` (a tmux internal id),
  not a placeholder. Out of scope; document as a residual (research FINDING 7).
- ❌ Don't ignore the user-collision residual — a user session named `__lp_sentinel__` would be
  destroyed by the pre-clean. Document it; the fixed name is required for the swap (FINDING 6).
- ❌ Don't edit by line number — anchor on content (the `sent_sess=` assignment and the
  `ws_seg="${ws_tpl//__lp_tab__...` line) (research FINDING 12).
- ❌ Don't use spaces for indent — TABS only (match the files; shfmt absent).

---

## Confidence Score

**9 / 10** for one-pass success. Rationale: two small, fully-specified edits (one assignment
+ one pre-clean line in livepicker.sh; one swap line + comment in renderer.sh) with verbatim
old→new anchors pinned to verified-current content. Every load-bearing claim is
**live-verified** on 3.6b: the bug repro (FINDING 1), the fix (FINDING 2), the single-pass
no-recursion swap (FINDING 3), the idempotent pre-clean (FINDING 4), and the modal-guard
concurrency safety (FINDING 5). The mechanism is a direct extension of the already-shipped
`__lp_tab__` sentinel-window approach (proven in this codebase) to the sentinel SESSION name.
The `#W` path is untouched (no regression surface). Disjoint from the in-flight parallel
P1.M2.T1.S1 (preview.sh-only). Residual risks: (a) an `edit`-tool `oldText` mismatch on the
multi-line comment block — mitigated by the verbatim anchors + L1 grep post-checks; (b) the
user-collision residual (vanishing probability, documented); (c) `#{session_id}` not covered
(out of scope, documented). The 1-point deduction reflects the user-collision residual being
a genuine (if near-zero) trade-off of the fixed-name design, accepted per the contract.
