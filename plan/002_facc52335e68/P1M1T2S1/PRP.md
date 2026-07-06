# PRP — P1.M1.T2.S1: Sentinel-window format resolution and template caching in activate_main

---

## Goal

**Feature Goal**: At activation (when `@livepicker-tab-style = window-status`), resolve
the user's theme `window-status-current-format` / `window-status-format` against a
short-lived hidden sentinel window via `display-message -p`, fully expanding every
`#{…}` (including `#{E:@user_option}` and `#W`) to concrete `#[…]` styles with a unique
name placeholder (`__lp_tab__`) baked in, and cache the two rendered templates into
`@livepicker-tab-current-tmpl` / `@livepicker-tab-inactive-tmpl`. On any failure or
ambiguous result, leave both cache keys **set-empty** so the renderer (P1.M1.T3) falls
back to `plain`. This is the resolution half of PRD §17; the picker must NEVER fail to
open over a styling miss.

**Deliverable**: One new internal helper `_lp_resolve_tab_templates()` in
`scripts/livepicker.sh` (defined before `activate_main`, called inside it between the
first-preview block and `set_state MODE on`). **No new files.** Consumes
`opt_tab_style()` + `STATE_TAB_CURRENT_TMPL`/`STATE_TAB_INACTIVE_TMPL` from P1.M1.T1.S1
(already landed).

**Success Definition**:
- With `@livepicker-tab-style=window-status` and tubular active, after activation both
  cache keys hold fully-expanded templates (no raw `#{`), each containing the `__lp_tab__`
  placeholder. (Verified: tubular resolves to `#[fg=#7aa89f,…] __lp_tab__ […]`.)
- With `@livepicker-tab-style=plain` (the default), the helper is a no-op (early return);
  cache keys untouched.
- On ANY tmux failure (sentinel create/resolve/kill) OR a malformed theme (unexpanded
  `#{`), both cache keys are **set-empty** (`tmux set-option -g @x ""`, NOT unset) and
  activation proceeds — `tmux_is_set` returns "set" so the renderer can distinguish
  "resolved empty" from "not run".
- The sentinel session is ALWAYS killed (success + every failure path); it never leaks
  into the user's session list.
- `bash -n` + `shellcheck` clean; the full `tests/run.sh` suite stays green (the helper
  adds a best-effort step that cannot break existing paths).

## User Persona (if applicable)

**Target User**: The renderer (P1.M1.T3.S1) and, downstream, the end user who wants the
picker to match their theme's window tabs. Not directly user-facing.

**Use Case**: A tubular/catppuccin user sets `@livepicker-tab-style window-status`; at
activation the picker resolves their theme's tab format once and caches it, so every
picker row renders as a faithful copy of their window tabs (pill, caps, colors) without
any per-keystroke `display-message`.

**Pain Points Addressed**: PRD §17 fact #1 — a `#()` status command's stdout is NOT
re-parsed for `#{…}` (only `#[…]` styles apply), so theme formats cannot be emitted
verbatim by the renderer. Pre-resolving once at activation and caching the two concrete
templates is the only way to reuse the theme's tab look from a `#()` script.

---

## Why

- **Unblocks the §17 feature.** The renderer (T3) can only swap a placeholder into a
  pre-resolved `#[…]`-only template; it cannot expand `#{…}` itself. This task produces
  those two templates. Without it, `window-status` mode is impossible.
- **Fast + done once.** Resolution happens exactly once at activation (not per keystroke),
  honoring the §18 responsiveness contract. The sentinel window lives for milliseconds.
- **Leak-safe by construction.** The cache keys are `STATE_TAB_*` runtime keys that
  P1.M1.T1.S1 already added to `_STATE_RUNTIME_KEYS` → `clear_all_state` (restore STEP 6)
  unsets them on exit. No cross-session leak.
- **Never blocks activation.** Every step is best-effort with a `plain` fallback. A theme
  quirk or tmux hiccup degrades to the standalone coloring, never a broken picker (PRD §17
  "Fallback", §16 "window-status hijack fragility").

## What

A helper `_lp_resolve_tab_templates()`, gated on `opt_tab_style = window-status`, that:
1. Reads both format **values** via `show-options -gwv` (global-window scope).
2. Creates a unique hidden 2-window session (`__lp_anchor__` + `__lp_tab__`), forcing the
   anchor active so `__lp_tab__` is a clean non-active window.
3. Resolves both values fully against `__lp_tab__` via `display-message -p`.
4. Kills the sentinel session.
5. Guards: if either resolved template is empty OR contains an unexpanded `#{`, blank both.
6. Caches both into the `STATE_TAB_*` keys (set-empty on any failure).

Called in `activate_main` between the first-preview `if`-block and `set_state MODE on`.

### Success Criteria

- [ ] `_lp_resolve_tab_templates` defined before `activate_main` in livepicker.sh; called
      once between the first-preview block and `set_state "$STATE_MODE" "on"`.
- [ ] Gated: `[ "$(opt_tab_style)" = "window-status" ] || return 0` is the first line.
- [ ] Sentinel created with the **trailing-colon** `new-window -d -t "$sent_sess:"` form
      (the bare form FAILS under `base-index=1` — see Gotchas) + force-select anchor.
- [ ] Every fallback path does `set_state ""` on BOTH keys (set-empty, NOT unset) then
      `return 0`; the sentinel is killed on the failure paths too.
- [ ] Guard: a resolved template containing `#{` → blanked (malformed-theme fallback).
- [ ] `bash -n` + `shellcheck` clean; `tests/run.sh` green; no sentinel session leaks.

## All Needed Context

### Context Completeness Check

_Pass_: The implementer needs (a) the verbatim helper body (below), (b) the exact call-site
anchor (content-based), (c) the two contract corrections from the research file (the
`new-window` failure + the never-empty format value), and (d) the set-empty requirement.
No inference about tmux internals is required — every behavior is empirically verified.

### Documentation & References

```yaml
# MUST READ — the empirical ground-truth (corrects TWO contract errors)
- docfile: plan/002_facc52335e68/P1M1T2S1/research/sentinel_resolution_findings.md
  why: PROVES the sentinel mechanism live on the config-sourcing socket (the target env).
       TWO CONTRACT CORRECTIONS the code+comments MUST reflect:
         FINDING 1 — `new-window -d -t "$SENT"` FAILS under base-index=1/renumber
                     ("index in use"); use `-t "$SENT:"` (trailing colon) + force-select anchor.
         FINDING 3 — `show-options -gwv` NEVER returns empty for window-status-* (returns
                     the default); the step-(a) empty-check is defensive-only; step-(e) is
                     the real fallback.
       Also: FINDING 5 (set-empty vs unset — the writer's T1.S1 contract), FINDING 2
       (resolved tubular templates are clean, no raw #{), FINDING 6 (insertion point).
  critical: Read BEFORE writing the helper. The contract's literal new-window form is wrong
            for this environment and will silently produce a dirty (active) sentinel.

# MUST READ — the external-behavior rationale (Q1-Q4; marked [VERIFY], now proven by above)
- docfile: plan/002_facc52335e68/architecture/external_tmux_behavior.md
  why: Q1 (display-message -p expands the full #{…} tree incl. E: + #W — pass the OPTION
       VALUE not the literal #{window_status_current_format}); Q2 (#() stdout not re-parsed
       for #{…} — why pre-resolution is necessary); Q3 (2-window hidden session for clean
       #F); Q4 (window-state specifiers collapse to a clean tab).
  section: "Q1", "Q2", "Q3", "Q4"

# MUST READ — the activation flow + the EXACT insertion point
- docfile: plan/002_facc52335e68/architecture/codebase_state.md
  why: §3 documents activate_main's numbered steps and pins the insertion point: between
       the first-preview if-block (~line 326) and set_state MODE on (~line 327), so a
       sentinel failure can still roll back via restore cancel (MODE not yet armed).
  section: "## 3. livepicker.sh" → "EXACT insertion point for sentinel-window format resolution"

# MUST READ — the file being modified
- file: scripts/livepicker.sh
  why: activate_main (line 43); CURRENT_DIR (line 35); sources options/utils/state (37/39/41)
        → opt_tab_style, set_state, STATE_TAB_* all in scope. livepicker.sh does NOT source
        filter.sh (not needed — the helper reads format OPTIONS, not the session list).
  pattern: the T5 region (lines 292-330): first preview → `if ! preview.sh ...; then restore
           cancel; return 1; fi` → `set_state "$STATE_MODE" "on"` → `refresh-client -S`.
  gotcha: Anchor the call-site edit on CONTENT (the set_state MODE line + preceding fi),
          not line number. The helper def goes BEFORE activate_main (line 43).

# MUST READ — the foundation this consumes (P1.M1.T1.S1, LANDED)
- docfile: plan/002_facc52335e68/P1M1T1S1/PRP.md
  why: Defines opt_tab_style() (default "plain") + STATE_TAB_CURRENT_TMPL/STATE_TAB_INACTIVE_TMPL
        (+ _STATE_RUNTIME_KEYS membership). Its "Downstream contract" section REQUIRES this
        task (the writer) to set_state "" on failure (set-empty) so the renderer's tmux_is_set
        probe works. This task is the writer half of that contract.
  section: "Implementation Patterns & Key Details" → "Downstream contract this foundation enables"

# MUST READ — the accessor + state keys (verify they exist before consuming)
- file: scripts/options.sh
  why: Line 45 opt_tab_style() (verify present; returns "plain" | "window-status").
- file: scripts/state.sh
  why: Lines 46-47 STATE_TAB_CURRENT_TMPL/STATE_TAB_INACTIVE_TMPL; line 61 _STATE_RUNTIME_KEYS
        (both members → clear_all_state clears them). set_state/get_state helpers.

# MUST READ — PRD §17 (the feature spec) + §16 (the fragility/fallback note)
- docfile: PRD.md
  why: §17 specifies the sentinel resolution, the plain fallback, the #{…} wrinkle, and the
        window-state clean-tab requirement. §16 "Window-status hijack fragility" mandates
        the plain fallback on any resolution failure.
  section: "§17 Tab appearance" + "§16 Implementation risks (window-status hijack fragility)"
```

### Current Codebase tree

```bash
tmux-livepicker/
  scripts/
    livepicker.sh   # MODIFY: +_lp_resolve_tab_templates helper + 1 call site in activate_main
    options.sh      # (P1.M1.T1.S1, LANDED) opt_tab_style() — consumed, not edited
    state.sh        # (P1.M1.T1.S1, LANDED) STATE_TAB_* + _STATE_RUNTIME_KEYS — consumed, not edited
    utils.sh        # UNCHANGED (set_state delegates to tmux_set_opt — already present)
    renderer.sh     # UNCHANGED here (P1.M1.T3 reads the cache this task writes)
    ...
  tests/            # UNCHANGED (feature validation is P1.M3.T2 test_appearance.sh)
```

### Desired Codebase tree with files to be added and responsibility of file

```bash
scripts/livepicker.sh   # +1 helper _lp_resolve_tab_templates (resolve+cache or set-empty+fallback);
                         #   +1 call site in activate_main (between first-preview and mode-on)
```

### Known Gotchas of our codebase & Library Quirks

```bash
# CRITICAL (CONTRACT CORRECTION — research FINDING 1): `new-window -d -t "$sent_sess"` (bare)
# FAILS under the target config (base-index=1 + renumber-windows=on, set by tubular/the user
# tmux.conf that the isolated socket sources): "create window failed: index 1 in use". The
# result is a single ACTIVE sentinel -> #F='*' (dirty). USE THE TRAILING-COLON FORM:
#   tmux new-window -d -t "$sent_sess:" -n __lp_tab__
# (the colon = "target the session"; tmux appends at a free index). Then force the anchor
# active: `tmux select-window -t "$sent_sess:__lp_anchor__" 2>/dev/null || true`. Verified.

# CRITICAL (CONTRACT CORRECTION — research FINDING 3): `show-options -gwv window-status-*`
# NEVER returns empty — tmux always materializes a default (e.g. "#I:#W#{?window_flags,...}").
# So the step-(a) "if either empty -> fallback" check is DEFENSIVE ONLY (never fires here).
# The REAL fallback is step (e): an unexpanded '#{' in the resolved template. Keep the empty
# check (harmless, defensive) but do NOT rely on it as the primary gate. Use -gwv
# (global-WINDOW scope); -gv happens to work too but -gwv is the semantically correct scope.

# CRITICAL (T1.S1 downstream contract — research FINDING 5): on ANY failure/empty/guard,
# `set_state "$STATE_TAB_CURRENT_TMPL" ""` AND `set_state "$STATE_TAB_INACTIVE_TMPL" ""`
# (real set-empty = `tmux set-option -g @x ""`). Do NOT leave them unset, and do NOT use
# tmux_unset_opt/-gu. The renderer (P1.M1.T3) uses tmux_is_set to tell "resolved empty"
# (set, rc=0) from "not run" (unset, rc=1); get_state/get_opt CANNOT (both return "").
# Verified: set-option -g @x "" -> show-options -g rc=0; -gu -> rc=1.

# CRITICAL: the picker MUST NEVER fail to open over a styling miss (PRD §17 Fallback, §16).
# EVERY tmux call is best-effort (`2>/dev/null || true` or `|| { fallback; return 0; }`).
# The sentinel session is killed on BOTH the success path (step d) AND every failure path.
# The helper ALWAYS returns 0 (it is a cosmetic enhancement; never abort activation).

# CRITICAL: the helper is GATED on opt_tab_style == "window-status". In plain mode (the
# default) it early-returns WITHOUT touching the cache keys (the renderer takes the plain
# path regardless; the keys are cleared by clear_all_state on the prior restore). Do not
# set-empty in plain mode — it is unnecessary and would mask "not run" as "resolved empty".

# CRITICAL: make the sentinel session name UNIQUE (`__lp_sent_$$_$(date +%s)`) — PID + epoch
# avoids a collision if the picker is double-invoked or a prior sentinel leaked. new-session
# -s on an existing name errors; the unique name prevents that.

# GOTCHA: window-status-* are WINDOW options. Read with `show-options -gwv` (global-window,
# value-only), NOT `show-options -gv` (session-global). -gwv is the correct scope; the value
# is the theme-wide look the user sees. (The contract's -gwv is right.)

# GOTCHA: pass the OPTION VALUE (read via show-options) to display-message, NOT the literal
# `#{window_status_current_format}` (no such format variable exists — it would print
# literally). display-message -p -t <sentinel> "$value" expands the full tree (Q1).

# GOTCHA: NEVER omit display-message's `-p` (print to stdout). Without -p the resolved
# message goes to the status line / a popup — wrong destination, and you capture nothing.

# GOTCHA: the resolved template has `__lp_tab__` (the sentinel window name) baked in where
# #W was. The renderer (P1.M1.T3) swaps `__lp_tab__` -> each session name. Do NOT swap here.
# Do NOT strip #[…] styles or the window-flags field — they are the theme's tab appearance.

# GOTCHA: display-message -p does NOT escape `#` in its output (verified: 'a#b' -> 'a#b').
# So the cached template's literal `#` chars (e.g. in hex colors `#7aa89f`) are raw. When the
# renderer emits them in `#()` output, tmux treats `#[` as a style directive (correct) and a
# bare `#` as... handled by the theme. tubular's resolved template is clean (no stray #).

# GOTCHA: livepicker.sh runs under `set -u`. Every helper local MUST be declared `local`
# (cur_fmt, reg_fmt, cur_tpl, reg_tpl, sent_sess). No `set -e` (tmux calls legitimately
# return non-zero). Indent with TABS (whole codebase; shfmt absent).

# GOTCHA: do NOT add a committed tests/ file for this subtask. Feature validation is
# P1.M3.T2 (test_appearance.sh). Validate via a throwaway isolated-socket smoke (L2), then
# delete it. The helper is also exercised end-to-end by the full tests/run.sh suite (the
# activate path runs it; plain mode is a no-op so existing tests are unaffected).
```

## Implementation Blueprint

### Data models and structure

No data-model change. The "model" is the resolve+cache flow:

```
activate_main:
  ... STEP 2 save originals; T2 list; T3 status grow; T4 key table + hook suppress; T5 first preview ...
  if ! preview.sh "$orig_session"; then restore cancel; return 1; fi
  _lp_resolve_tab_templates          # <-- NEW (cosmetic; never blocks; gated on tab-style)
  set_state "$STATE_MODE" "on"       # mode-on LAST (so a sentinel failure could still roll back)
  refresh-client -S

_lp_resolve_tab_templates:
  opt_tab_style != window-status? -> return 0 (plain mode; no-op)
  read cur_fmt, reg_fmt (show-options -gwv)
  create unique hidden 2-window session (anchor + __lp_tab__, force anchor active)
  resolve cur_tpl, reg_tpl (display-message -p -t sentinel)
  kill sentinel
  blank either if empty or contains unexpanded '#{'
  cache both (set-empty on any failure so renderer's tmux_is_set probe works)
  return 0 (ALWAYS)
```

### Implementation Tasks (ordered by dependencies)

```yaml
Task 1: MODIFY scripts/livepicker.sh — ADD the helper
  - LOCATE (by content): the `activate_main() {` function definition (line 43). Insert the
    helper IMMEDIATELY BEFORE it (after the sourced-libs block / any file-level comments,
    before the function). livepicker.sh currently has activate_main as its only function.
  - IMPLEMENT _lp_resolve_tab_templates() — paste the verbatim body from "Implementation
    Patterns" below (research FINDING 1/3/5 baked in).
  - NAMING: _lp_resolve_tab_templates (leading _ = internal helper; matches the _lp_sync_*
    convention in input-handler.sh).
  - DEPENDENCIES: opt_tab_style (options.sh — sourced at livepicker.sh:37); set_state +
    STATE_TAB_CURRENT_TMPL/STATE_TAB_INACTIVE_TMPL (state.sh — sourced at :41); CURRENT_DIR
    (module global, line 35); tmux (bare — PATH shim in tests, real tmux in prod).
  - STYLE: 0-indent def line, 1-tab body; `local` for ALL locals; quote every expansion;
    every tmux call best-effort; ALWAYS returns 0.
  - NO new sourcing (filter.sh NOT needed — the helper reads format options, not the list).

Task 2: MODIFY scripts/livepicker.sh — ADD the call site (by content)
  - LOCATE the T5 region (by content): the block
        if ! "$CURRENT_DIR/preview.sh" "$orig_session"; then
            "$CURRENT_DIR/restore.sh" cancel 2>/dev/null || true
            return 1
        fi
        set_state "$STATE_MODE" "on"
        tmux refresh-client -S
        return 0
  - ACTION: insert ONE line between the closing `fi` of the preview-if and `set_state "$STATE_MODE" "on"`:
        _lp_resolve_tab_templates
  - oldText must include enough context to be UNIQUE (the `fi` + `set_state "$STATE_MODE" "on"`
    + `tmux refresh-client -S` + `return 0` tail of activate_main). The string
    `set_state "$STATE_MODE" "on"` is the load-bearing anchor.
  - ORDER is load-bearing: helper AFTER the first-preview if-block (so a sentinel failure
    could still roll back — MODE not yet armed), BEFORE mode-on. Mirrors the codebase_state
    §3 recommended insertion.
  - DO NOT touch: any other step of activate_main, the restore cancel rollback, or any
    other file. P1.M1.T3 owns the renderer read side; this task only WRITES the cache.

Task 3: VALIDATE (throwaway isolated-socket smoke + full suite)
  - RUN: bash -n scripts/livepicker.sh
  - RUN: shellcheck scripts/livepicker.sh (expect 0 NEW findings)
  - RUN: the throwaway smoke (Validation Loop L2) — resolves tubular formats, asserts the
    cache is populated + sentinel cleaned up; then DELETE the smoke file.
  - RUN: tests/run.sh (expect: full suite green, exit 0 — plain mode is the default so the
    helper is a no-op for every existing test; no regression).
```

### Implementation Patterns & Key Details

**The helper (Task 1) — paste verbatim, placed immediately before `activate_main() {`:**

```bash
# _lp_resolve_tab_templates — PRD §17: resolve the theme's window-status[-current]-format
# against a short-lived hidden sentinel window and cache the two rendered templates, so the
# renderer (P1.M1.T3) can emit theme-matched tabs from a #() status command (whose stdout is
# NOT re-parsed for #{…} — only #[…] styles apply). Done ONCE at activation (fast; no
# per-keystroke display-message). Gated on @livepicker-tab-style == window-status; in plain
# mode it is a no-op. On ANY failure/ambiguity it leaves both cache keys SET-EMPTY (real
# `tmux set-option -g @x ""`, NOT unset) so the renderer's tmux_is_set probe detects "resolved
# empty" and falls back to plain (PRD §17 Fallback, §16 fragility). ALWAYS returns 0 — this
# is a cosmetic enhancement; it must NEVER block activation. See research/
# sentinel_resolution_findings.md (FINDING 1 new-window form, FINDING 3 never-empty value,
# FINDING 5 set-empty contract).
_lp_resolve_tab_templates() {
	# plain mode (the default) -> no-op; the renderer takes the plain path regardless.
	[ "$(opt_tab_style)" = "window-status" ] || return 0

	local cur_fmt reg_fmt cur_tpl reg_tpl sent_sess

	# (a) Read both format VALUES (window options -> -gwv global-window scope). NOTE: these
	# NEVER read empty (tmux always materializes a default); the empty-check below is
	# defensive. The real fallback is the unexpanded-'#{' check in (e). (FINDING 3)
	cur_fmt="$(tmux show-options -gwv window-status-current-format 2>/dev/null)"
	reg_fmt="$(tmux show-options -gwv window-status-format 2>/dev/null)"
	if [ -z "$cur_fmt" ] || [ -z "$reg_fmt" ]; then
		set_state "$STATE_TAB_CURRENT_TMPL" ""
		set_state "$STATE_TAB_INACTIVE_TMPL" ""
		return 0
	fi

	# (b) Create a unique hidden 2-window session (anchor + sentinel). CRITICAL (FINDING 1):
	# `new-window -d -t "$sent_sess"` (bare) FAILS under base-index=1/renumber ("index in
	# use"); the TRAILING-COLON form `-t "$sent_sess:"` picks a free slot. Force-select the
	# anchor so __lp_tab__ is NON-active -> clean window-state specifiers. Unique name
	# (PID+epoch) avoids a double-activation collision.
	sent_sess="__lp_sent_$$_$(date +%s)"
	if ! tmux new-session -d -s "$sent_sess" -n __lp_anchor__ 2>/dev/null; then
		set_state "$STATE_TAB_CURRENT_TMPL" ""
		set_state "$STATE_TAB_INACTIVE_TMPL" ""
		return 0
	fi
	# (trailing colon = target the session; tmux appends at a free index)
	if ! tmux new-window -d -t "$sent_sess:" -n __lp_tab__ 2>/dev/null; then
		tmux kill-session -t "$sent_sess" 2>/dev/null || true
		set_state "$STATE_TAB_CURRENT_TMPL" ""
		set_state "$STATE_TAB_INACTIVE_TMPL" ""
		return 0
	fi
	tmux select-window -t "$sent_sess:__lp_anchor__" 2>/dev/null || true

	# (c) Resolve both formats FULLY against the non-active sentinel window. Pass the OPTION
	# VALUE (not the literal #{window_status_current_format} — no such var). -p = stdout.
	# Expands every #{…} incl. #{E:@user_option} and #W (-> __lp_tab__ placeholder). (Q1)
	cur_tpl="$(tmux display-message -p -t "$sent_sess:__lp_tab__" "$cur_fmt" 2>/dev/null)"
	reg_tpl="$(tmux display-message -p -t "$sent_sess:__lp_tab__" "$reg_fmt" 2>/dev/null)"

	# (d) Kill the sentinel (tears down anchor + tab together; never leaks).
	tmux kill-session -t "$sent_sess" 2>/dev/null || true

	# (e) Guard: an unexpanded '#{' means a malformed theme (nested a format in a user-option
	# WITHOUT #{E:…}); blank it so the renderer falls back to plain. (FINDING 4: this fires
	# precisely for the tubular-misuse case; a plain unset @-opt resolves to empty, not '#{'.)
	case "$cur_tpl" in *"#{"*) cur_tpl="" ;; esac
	case "$reg_tpl" in *"#{"*) reg_tpl="" ;; esac

	# (f) Cache. If EITHER is empty (resolution failed OR the guard blanked it), set BOTH
	# empty (set-empty, NOT unset — FINDING 5: the renderer's tmux_is_set probe needs "set").
	if [ -z "$cur_tpl" ] || [ -z "$reg_tpl" ]; then
		set_state "$STATE_TAB_CURRENT_TMPL" ""
		set_state "$STATE_TAB_INACTIVE_TMPL" ""
	else
		set_state "$STATE_TAB_CURRENT_TMPL" "$cur_tpl"
		set_state "$STATE_TAB_INACTIVE_TMPL" "$reg_tpl"
	fi
	return 0
}
```

**Call site (Task 2) — insert between the first-preview `fi` and `set_state MODE on`
(anchor on the `set_state "$STATE_MODE" "on"` line):**

```bash
		fi
		# PRD §17: resolve theme tab formats once + cache (no-op in plain mode; never blocks).
		_lp_resolve_tab_templates
		set_state "$STATE_MODE" "on"
		tmux refresh-client -S
		return 0
```

(The exact surrounding lines in the current file are the T5 tail; the `oldText` for the edit
is the `fi` + `set_state "$STATE_MODE" "on"` + `tmux refresh-client -S` + `return 0` sequence,
anchored uniquely by `set_state "$STATE_MODE" "on"`.)

### Integration Points

```yaml
CODE:
  - file: scripts/livepicker.sh
    change: "+_lp_resolve_tab_templates helper (before activate_main); +1 call site (T5, before mode-on)"
    invariant: "window-status mode caches two resolved templates; plain mode is a no-op; any failure -> set-empty both -> plain fallback"

CONSUMERS (later subtasks — DO NOT implement now):
  - P1.M1.T3.S1 (renderer.sh): reads opt_tab_style + STATE_TAB_* (via tmux_is_set); swaps __lp_tab__ -> each session name
  - P1.M5 restore: clear_all_state clears STATE_TAB_* (automatic — already in _STATE_RUNTIME_KEYS via T1.S1)

CONFIG / DATABASE / ROUTES: none.
```

## Validation Loop

### Level 1: Syntax & Style (Immediate Feedback)

```bash
cd /home/dustin/.config/tmux/plugins/tmux-livepicker
bash -n scripts/livepicker.sh && echo "OK: livepicker syntax"
shellcheck scripts/livepicker.sh
# Tabs-not-spaces on the new region (shfmt NOT installed):
grep -nP '^ +[^#/]' scripts/livepicker.sh && echo "WARN: space-indent (use tabs)" || echo "OK: tabs"
# Confirm the helper + call site are present:
grep -c '_lp_resolve_tab_templates' scripts/livepicker.sh   # -> 3 (1 def-comment + 1 def + 1 call)
grep -nE '^\s*_lp_resolve_tab_templates$' scripts/livepicker.sh   # the 1 bare call site
# Confirm T1.S1 foundation is present (prerequisite):
grep -q 'opt_tab_style' scripts/options.sh && grep -q 'STATE_TAB_CURRENT_TMPL' scripts/state.sh \
  && echo "OK: T1.S1 foundation present" || echo "FAIL: T1.M1.T1.S1 not landed yet"
# Expected: syntax clean; shellcheck 0 new findings; helper defined once + called once.
```

### Level 2: Resolve-and-cache smoke (via the existing socket-isolated harness)

Throwaway smoke (DELETE after; feature tests are P1.M3.T2). Reuses `tests/setup_socket.sh`
(PATH shim → bare `tmux` hits an isolated `-L` socket that sources the tubular config) +
`tests/helpers.sh`. It sources the REAL livepicker.sh libs and calls the REAL helper:

```bash
cat > /tmp/smoke_sentinel.sh <<'EOF'
#!/usr/bin/env bash
set -u
cd /home/dustin/.config/tmux/plugins/tmux-livepicker
source tests/setup_socket.sh
source tests/helpers.sh
setup_test "lp-smoke-sentinel"
# livepicker.sh sources its own libs, but to call the helper directly we source the trio:
source scripts/utils.sh
source scripts/options.sh
source scripts/state.sh
# pull in the helper definition from livepicker.sh without running activate_main:
# (extract just the function via a guarded source — livepicker.sh only defines + calls
#  activate_main at the bottom, so sourcing it would run activate; instead, define a shim
#  by sourcing the helper text. Simplest robust approach: copy-call the helper's body via
#  `source <(sed -n '/^_lp_resolve_tab_templates()/,/^}/p' scripts/livepicker.sh)`.)
source <(sed -n '/^_lp_resolve_tab_templates()/,/^}/p' scripts/livepicker.sh)

pass_n=0; fail_n=0
ck() { if [ "$2" = "$3" ]; then pass_n=$((pass_n+1)); else fail_n=$((fail_n+1)); echo "FAIL $1: got[$2] want[$3]"; fi; }

# (1) plain mode (default) -> no-op: cache keys unset both before & after.
_lp_resolve_tab_templates
ck "plain mode is no-op (current unset)" "$(tmux show-options -g "$STATE_TAB_CURRENT_TMPL" >/dev/null 2>&1; echo $?)" "1"
ck "plain mode is no-op (inactive unset)" "$(tmux show-options -g "$STATE_TAB_INACTIVE_TMPL" >/dev/null 2>&1; echo $?)" "1"

# (2) window-status mode + tubular formats (the socket sourced the user config) -> resolved.
tmux set-option -g @livepicker-tab-style window-status
_lp_resolve_tab_templates
cur="$(tmux show-option -gqv "$STATE_TAB_CURRENT_TMPL" 2>/dev/null)"
ina="$(tmux show-option -gqv "$STATE_TAB_INACTIVE_TMPL" 2>/dev/null)"
ck "current tmpl non-empty" "$([ -n "$cur" ] && echo yes || echo no)" "yes"
ck "inactive tmpl non-empty" "$([ -n "$ina" ] && echo yes || echo no)" "yes"
# fully resolved (no raw #{):
case "$cur" in *"#{"*) fail_n=$((fail_n+1)); echo "FAIL: current has unexpanded #{";; *) pass_n=$((pass_n+1));; esac
case "$ina" in *"#{"*) fail_n=$((fail_n+1)); echo "FAIL: inactive has unexpanded #{";; *) pass_n=$((pass_n+1));; esac
# placeholder baked in (renderer swaps it):
case "$cur" in *__lp_tab__*) pass_n=$((pass_n+1));; *) fail_n=$((fail_n+1)); echo "FAIL: current missing __lp_tab__ placeholder";; esac

# (3) sentinel session did NOT leak (kill-session cleaned up):
case "$(tmux list-sessions -F '#{session_name}' 2>/dev/null)" in *__lp_sent_*) 
    fail_n=$((fail_n+1)); echo "FAIL: sentinel session leaked";; *) pass_n=$((pass_n+1));; esac

# (4) malformed-theme guard: a format nesting a format WITHOUT E: -> set-empty both.
tmux set-option -gw window-status-format '#[fg=#{@lp_inner_no_E}]#W'
tmux set-option -g @lp_inner_no_E '#{?#{==:#I,0},X,Y}'
_lp_resolve_tab_templates
ina2="$(tmux show-option -gqv "$STATE_TAB_INACTIVE_TMPL" 2>/dev/null)"
case "$ina2" in *"#{"*) fail_n=$((fail_n+1)); echo "FAIL: malformed theme not blanked";; *) pass_n=$((pass_n+1));; esac
# (set-empty, not unset — tmux_is_set rc=0:)
ck "malformed -> set-empty (not unset)" "$(tmux show-options -g "$STATE_TAB_INACTIVE_TMPL" >/dev/null 2>&1; echo $?)" "0"

teardown_test
echo "pass=$pass_n fail=$fail_n"
[ "$fail_n" -eq 0 ]
EOF
bash /tmp/smoke_sentinel.sh; rc=$?
rm -f /tmp/smoke_sentinel.sh
exit $rc
# Expected: pass~=12 fail=0. The (2) assertions prove tubular resolves cleanly; (3) proves
# no leak; (4) proves the malformed-theme guard + set-empty contract.
```

### Level 3: Full suite (no regression)

```bash
cd /home/dustin/.config/tmux/plugins/tmux-livepicker
tests/run.sh
# Expected: exit 0, all existing tests green. The helper is gated on tab-style=window-status;
# the default is "plain" (a no-op), so every existing test's activate path is unchanged.
# (If any test sets @livepicker-tab-style window-status and asserts plain rendering, it would
#  need updating — but no such test exists yet; appearance tests land in P1.M3.T2.)
```

### Level 4: Manual resolve against the LIVE tubular environment (read-only sanity)

```bash
cd /home/dustin/.config/tmux/plugins/tmux-livepicker
# Reuse the proven sentinel incantation against a throwaway hidden session on the LIVE server
# (no mutation of user state; the sentinel is killed). Confirms the real tubular formats resolve.
SENT="__lp_manual_$$_$(date +%s)"
tmux new-session -d -s "$SENT" -n __lp_anchor__
tmux new-window  -d -t "$SENT:" -n __lp_tab__
tmux select-window -t "$SENT:__lp_anchor__" 2>/dev/null || true
cur="$(tmux show-options -gwv window-status-current-format)"
echo "cur_tpl: [$(tmux display-message -p -t "$SENT:__lp_tab__" "$cur")]"
echo "  raw-#{ count: $(tmux display-message -p -t "$SENT:__lp_tab__" "$cur" | grep -c '#{')  (0=fully resolved)"
echo "  placeholder: $(tmux display-message -p -t "$SENT:__lp_tab__" "$cur" | grep -c __lp_tab__)"
tmux kill-session -t "$SENT" 2>/dev/null
# Expected: a fully-resolved #[...]-styled template with __lp_tab__ baked in, 0 raw #{.
```

## Final Validation Checklist

### Technical Validation

- [ ] `bash -n scripts/livepicker.sh` clean.
- [ ] `shellcheck scripts/liveplayer.sh`: 0 NEW findings.
- [ ] `_lp_resolve_tab_templates` defined once (before activate_main) + called once (T5).
- [ ] T1.S1 foundation present (opt_tab_style + STATE_TAB_* — verify at edit time).

### Feature Validation

- [ ] window-status mode + tubular: both cache keys hold fully-resolved templates (no `#{`),
      each containing `__lp_tab__` (L2 smoke pass~=12 fail=0).
- [ ] plain mode: helper is a no-op (cache keys untouched).
- [ ] Any failure / malformed theme / empty: both keys SET-EMPTY (tmux_is_set rc=0), not unset.
- [ ] Sentinel session NEVER leaks (killed on success + every failure path).
- [ ] Full `tests/run.sh` suite green (exit 0); no regression in plain-mode paths.

### Code Quality Validation

- [ ] Helper gated on `opt_tab_style = window-status`; early-returns 0 in plain mode.
- [ ] Uses the trailing-colon `new-window -d -t "$sent_sess:"` form (FINDING 1) + force-select anchor.
- [ ] Reads formats via `show-options -gwv` (global-window scope); display-message `-p` always present.
- [ ] Every tmux call best-effort; helper ALWAYS returns 0 (never blocks activation).
- [ ] Every fallback path `set_state ""` BOTH keys (FINDING 5 set-empty contract).
- [ ] Edits anchored by CONTENT (the `set_state "$STATE_MODE" "on"` line), not line number.
- [ ] `local` for all locals; tabs for indent; `set -u`-safe.

### Documentation & Deployment

- [ ] Inline comments cross-reference PRD §17/§16 + the research FINDINGs + the renderer sibling.
- [ ] No README/CHANGELOG change here (Mode-A internal step; the §17 config row + docs sync is
      P1.M3.T3.S1). The README already documents `@livepicker-tab-style` at a high level.
- [ ] Do NOT commit a tests/ file (feature tests are P1.M3.T2 test_appearance.sh).

---

## Anti-Patterns to Avoid

- ❌ Don't use `new-window -d -t "$sent_sess"` (bare) — it FAILS under `base-index=1`/renumber
  ("index in use"), leaving a single ACTIVE sentinel (`#F=*`, dirty). Use `-t "$sent_sess:"`
  (trailing colon) + `select-window -t "$sent_sess:__lp_anchor__"`. (FINDING 1.)
- ❌ Don't rely on the step-(a) empty-check as the primary fallback — `show-options -gwv`
  NEVER returns empty for window-status-* (returns the default). The real gate is the
  unexpanded-`#{` check (step e). (FINDING 3.)
- ❌ Don't leave the cache keys UNSET on failure, and don't use `tmux_unset_opt`/`-gu`.
  `set_state ""` (set-empty) so the renderer's `tmux_is_set` probe works. (FINDING 5.)
- ❌ Don't pass the literal `#{window_status_current_format}` to display-message (no such
  variable — prints literally). Pass the OPTION VALUE read via `show-options -gwv`. (Q1.)
- ❌ Don't omit display-message's `-p` — without it the resolved text goes to the status line.
- ❌ Don't ever `return` non-zero or `exit` from the helper — it is cosmetic; it must NEVER
  block activation (PRD §17 Fallback, §16). Always `return 0`.
- ❌ Don't forget to kill the sentinel on the FAILURE paths (new-session/new-window failure) —
  a leaked `__lp_sent_*` session pollutes the user's session list.
- ❌ Don't swap `__lp_tab__` → session names here, or strip `#[…]`/flags — that is the
  renderer's job (P1.M1.T3). This task only resolves + caches the raw templates.
- ❌ Don't set-empty in PLAIN mode (early-return untouched) — it would mask "not run" as
  "resolved empty" and is unnecessary (the renderer branches on opt_tab_style first).
- ❌ Don't edit by line number — anchor on the `set_state "$STATE_MODE" "on"` content.
- ❌ Don't source filter.sh or add new sourcing — the helper reads format OPTIONS, not the list.
- ❌ Don't commit a tests/ file — feature validation is P1.M3.T2; use the throwaway L2 smoke.

---

## Confidence Score

**9 / 10** for one-pass success. Rationale: the helper body is given verbatim with both
contract corrections (the `new-window` trailing-colon form and the never-empty format value)
baked in and empirically proven against the real tubular config on an isolated socket; the
resolved tubular templates are confirmed clean (no raw `#{`, placeholder present); the
set-empty contract is verified (rc=0 set vs rc=1 unset); the call-site is a single content-
anchored insertion that cannot conflict with the parallel sibling subtasks (T1.S1 already
landed; T3 owns the renderer read side); and the L2 smoke deterministically proves resolve +
leak-prevention + the malformed-theme guard. Residual risk: an edit-tool `oldText` mismatch
on the call-site (mitigated by the unique `set_state "$STATE_MODE" "on"` anchor + the grep
verification in L1) and the `#F`→`##` window-flags quirk on non-tubular themes (harmless for
the tubular target; documented).
