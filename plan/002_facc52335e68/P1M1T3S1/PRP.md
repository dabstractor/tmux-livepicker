# PRP — P1.M1.T3.S1: Window-status render branch with placeholder swap and plain fallback

---

## Goal

**Feature Goal**: Add a **window-status render path** to `scripts/renderer.sh::render()`
that, when `@livepicker-tab-style = window-status` AND both cached templates are
populated, emits the picker list as **theme-matched tabs** — swapping the `__lp_tab__`
placeholder in each pre-resolved `#[…]-styled` template (cached at activation by
P1.M1.T2.S1) → each `#`-escaped session name, joined by `window-status-separator`. When
any precondition fails, execution **falls through to the existing plain path verbatim**
(the working highlight/filter/escape logic is left byte-for-byte untouched). The renderer
stays PURE (zero tmux mutations) and FAST (option reads + bash string ops only; no
per-item `display-message`).

**Deliverable**: One modified function `render()` in `scripts/renderer.sh` — a
self-contained `if`-block inserted between the `SHOW_COUNT` case and the plain path's
`LIST=` read. **No new files.** Consumes `opt_tab_style()` (P1.M1.T1.S1, landed) +
`STATE_TAB_CURRENT_TMPL`/`STATE_TAB_INACTIVE_TMPL` (P1.M1.T1.S1, landed) + the existing
`get_state`/`lp_build_filtered`/`#`-escape machinery.

**Success Definition**:
- With `@livepicker-tab-style=window-status` and both cache keys populated, `render()`
  outputs the joined tabs: the highlighted index uses the current template, the rest the
  inactive template, each with `__lp_tab__` swapped → the session name (`#` doubled),
  separated by `window-status-separator`, with the `SHOW_COUNT` query suffix appended.
- With `@livepicker-tab-style=plain` (the default), OR if either cache key is empty/unset,
  `render()` emits the **unchanged plain path** output (byte-identical to today).
- A session name containing `#` is emitted as `##` in the swapped segment (literal-`#`).
- `bash -n` + `shellcheck` clean; `tests/run.sh` stays green (plain is the default → the
  new block is a no-op for every existing test); the throwaway L2 smoke passes.

## User Persona (if applicable)

**Target User**: The end user (via the status line) and the validating test
(`tests/test_appearance.sh`, P1.M3.T2.S1). Not directly developer-facing.

**Use Case**: A tubular/catppuccin user sets `@livepicker-tab-style window-status`; at
activation the picker caches their theme's tab formats (P1.M1.T2.S1), and on every
redraw the renderer emits the picker list rendered through those formats — so the picker
looks like the user's own window tabs, not a foreign element (PRD §17).

**Pain Points Addressed**: PRD §17 fact #1 — a `#()` status command's stdout is NOT
re-parsed for `#{…}` (only `#[…]` styles apply), so theme formats cannot be emitted
verbatim. Pre-resolution happens once at activation (T2.S1); THIS task is the read/swap
half that turns the two cached `#[…]`-only templates into the live picker line. Without
it, `window-status` mode renders nothing (empty cache → falls to plain, so it degrades
gracefully, but the feature is inert).

---

## Why

- **Closes the §17 loop.** T2.S1 writes the two resolved templates; this task reads them
  and produces the user-visible tab line. It is the second half of the integration seam.
- **Zero risk to the working plain path.** The branch is a self-contained early-return
  inserted BEFORE the plain path; the plain highlight/filter/escape logic is never
  duplicated or forked. Default `tab-style=plain` means every existing test is unaffected.
- **Fast by construction.** No per-item `display-message` (that happened once at
  activation); the renderer does only option reads + bash `${var//pat/rep}` substitution,
  honoring the §18 responsiveness contract (renderer must stay <50ms; runs every keystroke).
- **Graceful fallback.** Empty/unset templates, plain mode, or any quirk → the unchanged
  plain path. The picker NEVER fails to render over a styling miss (PRD §17 Fallback, §16).

## What

A single `if`-block added inside `render()`, placed immediately after the `SHOW_COUNT`
case (before the plain path's `LIST="$(get_state "$STATE_LIST" "")"` read). The block:

1. Branches on `[ "$(opt_tab_style)" = "window-status" ]`.
2. Reads both cached templates via `get_state "$STATE_TAB_CURRENT_TMPL" ""` /
   `"$STATE_TAB_INACTIVE_TMPL" ""`.
3. If EITHER is empty → does NOT enter the inner block → falls through to plain (untouched).
4. If BOTH non-empty: reads `STATE_LIST`/`STATE_FILTER`/`STATE_INDEX` + the separator
   (`tmux show-options -gwv window-status-separator`, default space); builds the filtered
   list via `mapfile -t ws_filtered < <(lp_build_filtered …)`; mirrors the plain no-match
   output when empty; clamps `cidx`; loops picking current-vs-inactive template, swapping
   `__lp_tab__` → the `#`-escaped name, joining with the separator; appends the
   `SHOW_COUNT` suffix; `printf '%s' "$ws_out"; return 0`.

The block is wrapped by the existing top-level crash guard (`render || printf
'#[fg=red]livepicker: renderer error#[default]'`), so a malformed template can never
blank the bar.

### Success Criteria

- [ ] The `if`-block is inserted between the `SHOW_COUNT` `esac` and the plain `LIST=` read.
- [ ] The plain path (from `LIST=` through the final `printf '%s' "$out"`) is byte-identical.
- [ ] Branch condition is `[ "$(opt_tab_style)" = "window-status" ]`; entry requires BOTH
      templates non-empty (`get_state` + `[ -n ]`).
- [ ] The swapped name is `#`-escaped (`${ws_name//\#/##}`) BEFORE the `${tpl//__lp_tab__/…}`
      substitution.
- [ ] Tabs are joined with `window-status-separator` (read via `show-options -gwv`,
      default space), NOT a plain space.
- [ ] no-match + SHOW_COUNT suffix mirror the plain path's output.
- [ ] Every happy path `printf '%s' …; return 0` (one line, no trailing newline).
- [ ] `bash -n` + `shellcheck` clean; `tests/run.sh` green; L2 smoke passes.

## All Needed Context

### Context Completeness Check

_Pass_: The implementer needs (a) the verbatim block (below), (b) the exact insertion
anchor (content-based), (c) the research findings (the resolved-template proof, the
get_state-vs-tmux_is_set decision, the `#`-escape reuse), and (d) the validation commands.
No inference about tmux internals is required — every behavior is verified live.

### Documentation & References

```yaml
# MUST READ — the empirical ground-truth for THIS block
- docfile: plan/002_facc52335e68/P1M1T3S1/research/renderer_ws_branch_findings.md
  why: FINDING 1 (tubular resolves to a clean #[...]-styled template with __lp_tab__
       baked in — the exact bytes the renderer consumes); FINDING 2 (separator is a
       plain space for tubular; #{...} in a themed separator is a known edge case);
       FINDING 3 (DECISION: get_state + non-empty, NOT tmux_is_set — equivalent for
       branching, leaner, honors the writer's set-empty contract); FINDING 4 (#->##
       escape reused from the plain path, applied BEFORE substitution); FINDING 5
       (branch placement — self-contained block after SHOW_COUNT case); FINDING 6/7/8.
  critical: Read BEFORE writing the block. The get_state-vs-tmux_is_set choice and the
            # escape-before-substitution ordering are the two load-bearing correctness points.

# MUST READ — the file being modified (the CURRENT render() body + the insertion anchor)
- file: scripts/renderer.sh
  why: render() (lines 47-131) is the function edited. The insertion point is between the
        SHOW_COUNT `esac` (~line 62) and `LIST="$(get_state "$STATE_LIST" "")"` (~line 64).
        The plain path (LIST= onward) must stay untouched. The top-level crash guard
        (line 132) already wraps render() — do NOT add a second guard inside the block.
  pattern: the load-bearing rules in the file header (ONE line, no trailing newline via
           `printf '%s'`; `#[default]` resets both axes; mapfile via process-substitution
           `< <(printf '%s' …)` NOT here-string; NO `set -e`; crash guard).
  gotcha: The window-status block must `return 0` on every happy path or it falls through
          to the plain path (double-render). The new locals are `ws_`-prefixed to stay
          visually distinct from the plain path's LIST/FILTER/… (only one path runs).

# MUST READ — the writer-side contract (what populates the cache this task reads)
- docfile: plan/002_facc52335e68/P1M1T2S1/PRP.md
  why: _lp_resolve_tab_templates (T2.S1) writes STATE_TAB_CURRENT_TMPL/INACTIVE_TMPL at
        activation. On ANY failure it SET-EMPTIES both (real `tmux set-option -g @x ""`,
        NOT unset). This task's get_state + [ -n ] check reads set-empty as "" → plain
        (correct). The resolved templates contain only #[...] styles + __lp_tab__ (no raw #{}).
  section: "Implementation Patterns & Key Details" (the verbatim helper body + the set-empty contract)

# MUST READ — the external-behavior rationale (Q2 is load-bearing for WHY pre-resolution)
- docfile: plan/002_facc52335e68/architecture/external_tmux_behavior.md
  why: Q2 — #() stdout is NOT re-parsed for #{...} (only #[...] styles apply). This is WHY
        the templates must be pre-resolved (T2.S1) and why the renderer can emit #[...]
        styling verbatim but must NOT try to expand #{...} itself. Q4 — window-state
        specifiers collapse to a clean tab for the sentinel.
  section: "Q2", "Q4"

# MUST READ — the codebase map (render() structure + the EXACT insertion point)
- docfile: plan/002_facc52335e68/architecture/codebase_state.md
  why: §4 documents render() line-by-line and pins the branch point: "right after the
        option reads (after line 60, the SHOW_COUNT case), before the out='' list-build
        block." Confirms the plain path's mechanics (mapfile via process-substitution,
        #->## escape, cidx clamp, SHOW_COUNT suffix, printf '%s').
  section: "## 4. renderer.sh" → "Window-status render branch point"

# MUST READ — the foundation this consumes (P1.M1.T1.S1, LANDED — verify before editing)
- file: scripts/options.sh
  why: Line 45 opt_tab_style() (verify present; returns "plain" | "window-status").
- file: scripts/state.sh
  why: STATE_TAB_CURRENT_TMPL/STATE_TAB_INACTIVE_TMPL (lines 37-38); get_state helper;
        both keys are in _STATE_RUNTIME_KEYS → clear_all_state clears them on exit (no leak).
- file: scripts/filter.sh
  why: lp_build_filtered LIST FILTER — the SINGLE shared filter (renderer + input-handler).
        The window-status block reuses it so filtered[idx] matches the highlighted item.

# MUST READ — PRD §17 (the feature spec) + §16 (the fragility/fallback note)
- docfile: PRD.md
  why: §17 specifies the placeholder swap, the separator join, status-justify (applied by
        tmux to the whole line — the renderer just emits the joined string), and the plain
        fallback. §16 "Window-status hijack fragility" mandates the plain fallback on any
        resolution failure (→ empty template → plain, handled here by the [ -n ] check).
  section: "§17 Tab appearance" + "§16 Implementation risks (window-status hijack fragility)"
```

### Current Codebase tree

```bash
tmux-livepicker/
  scripts/
    renderer.sh   # MODIFY: +1 self-contained if-block in render() (window-status path)
    options.sh    # (P1.M1.T1.S1, LANDED) opt_tab_style() — consumed, not edited
    state.sh      # (P1.M1.T1.S1, LANDED) STATE_TAB_* + get_state — consumed, not edited
    filter.sh     # lp_build_filtered — consumed (shared filter), not edited
    utils.sh / livepicker.sh / preview.sh / input-handler.sh / restore.sh  # UNCHANGED
  tests/          # UNCHANGED (feature validation is P1.M3.T2 test_appearance.sh)
```

### Desired Codebase tree with files to be added and responsibility of file

```bash
scripts/renderer.sh   # +1 window-status render block in render() (between SHOW_COUNT case
                       #   and the plain LIST= read); plain path untouched. The user-visible
                       #   picker appearance in window-status mode.
```

### Known Gotchas of our codebase & Library Quirks

```bash
# CRITICAL (FINDING 3 — DECISION): use get_state + [ -n ], NOT tmux_is_set, to gate the
# window-status block. The writer (T2.S1) set-empties both keys on failure; get_state
# reads set-empty as "" → the [ -n ] check fails → plain (correct). tmux_is_set's
# set-vs-unset distinction adds NO branching signal (both → plain) and costs 2 extra tmux
# calls the renderer's <50ms budget can't spare. The item's explicit instruction is
# get_state + empty-check; follow it. (The writer's set-empty contract is honored either way.)

# CRITICAL (FINDING 4): escape # -> ## in the session name BEFORE the placeholder
# substitution: esc_wname="${ws_name//\#/##}"; then ws_seg="${ws_tpl//__lp_tab__/$esc_wname}".
# The template's OWN #[fg=#hex...] styles are NOT touched by the substitution (it only
# replaces __lp_tab__). A bare # in a session name would otherwise be read as a stray tmux
# directive; ## is the display-escape for literal-# (proven: renderer.sh lines 66/99, ship
# commit 066b733). ${var//pat/rep} does literal replacement (pat has no glob chars; rep is
# not re-scanned) so even a name == "__lp_tab__" cannot corrupt or recurse.

# CRITICAL: the window-status block is a SELF-CONTAINED early-return BEFORE the plain path.
# Insert it between the SHOW_COUNT `esac` and `LIST="$(get_state "$STATE_LIST" "")"`. The
# plain path (LIST= ... final printf) stays byte-identical — do NOT refactor or fork it.
# Every happy path in the block ends `printf '%s' "$ws_out"; return 0` so it never falls
# through to plain after emitting tabs (which would double-render).

# CRITICAL: the block is INSIDE render(), so the existing top-level crash guard
# (`render || printf '#[fg=red]livepicker: renderer error#[default]'`, line 132) already
# catches any error. Do NOT add a second try/catch inside the block. A malformed template
# tripping a bash error → red error message, never a blank bar.

# GOTCHA: read the separator via `tmux show-options -gwv window-status-separator` (global-
# WINDOW scope; window-status-separator is a window option). It is a plain space for
# tubular. Default to a space if empty (`[ -z "$ws_sep" ] && ws_sep=" "`). KNOWN EDGE CASE
# (documented, not solved): a theme that puts #{...} in its separator renders that #{...}
# literally between tabs (Q2: #() stdout is not re-parsed for #{...}); resolving it would
# need a 3rd cached template (out of scope; the item says read it fresh). The common case
# (plain string or #[...]-styled glyph) renders fine.

# GOTCHA: mapfile via PROCESS SUBSTITUTION `mapfile -t ws_filtered < <(lp_build_filtered …)`,
# NOT a here-string `<<<`. An empty list via here-string yields [""] (a 1-element array with
# an empty string); process-substitution + `printf '%s'` yields [] (the correct empty array).
# This is the plain path's idiom (renderer research FINDING 3) — reuse it verbatim.

# GOTCHA: `printf '%s' "$ws_out"` — NO trailing newline. Multi-line stdout from a #()
# status command renders ONLY the last line (data loss). The whole joined tab line is ONE
# logical line. (renderer.sh header FINDING 2.)

# GOTCHA: no `set -e` (an unset @-option makes show-option return rc=1; set -e would abort
# the renderer and blank line 1). `set -u` is inherited — every local is defaulted before use.

# GOTCHA: status-justify is applied by tmux to the WHOLE status line; the renderer only
# emits the joined string. Do NOT try to center/justify in bash (PRD §17).

# GOTCHA: indent with TABS (whole codebase; shfmt absent). The new block sits at 1-tab
# indent inside render(); its inner `if`/`for` bodies at 2-3 tabs. Declare `local` vars
# (SC2155-safe: declare FIRST, assign on a separate line).
```

## Implementation Blueprint

### Data models and structure

No data-model change. The block consumes two cached strings (`STATE_TAB_*`) and emits one
joined line. The "model" is the swap-and-join flow:

```
render():
  [option reads: TYPE/FG/BG/HFG/HBG/SHOW_COUNT + case]      # SHARED, unchanged
  --- NEW window-status block (PRD §17) ---
  if opt_tab_style == window-status:
      cur_tpl = get_state STATE_TAB_CURRENT_TMPL
      reg_tpl = get_state STATE_TAB_INACTIVE_TMPL
      if cur_tpl != "" and reg_tpl != "":
          read LIST/FILTER/IDX + separator
          ws_filtered = lp_build_filtered(LIST, FILTER)   # the shared filter
          if empty: printf plain-no-match; return 0
          clamp cidx
          for each filtered[i]:
              esc_name = name (# -> ##)
              tpl = (i == cidx) ? cur_tpl : reg_tpl
              seg = tpl with __lp_tab__ -> esc_name
              join ws_out with separator
          append SHOW_COUNT suffix (mirror plain)
          printf '%s' ws_out; return 0
      # (else fall through)
  --- plain path (UNCHANGED from here) ---
  LIST/FILTER/IDX reads; mapfile all/filtered; out=""; no-match; cidx clamp;
  highlight loop; SHOW_COUNT suffix; printf '%s' out
```

### Implementation Tasks (ordered by dependencies)

```yaml
Task 1: MODIFY scripts/renderer.sh — INSERT the window-status block
  - LOCATE (by content): inside render(), the SHOW_COUNT case close + the plain LIST read:
        esac

        LIST="$(get_state "$STATE_LIST" "")"
    This pair is UNIQUE in the file. The block goes BETWEEN them.
  - ACTION: insert the verbatim block from "Implementation Patterns" below. The edit's
    oldText is the `esac\n\n\tLIST="$(get_state "$STATE_LIST" "")"` sequence; newText is
    `esac\n\n\t<NEW BLOCK>\n\n\tLIST="$(get_state "$STATE_LIST" "")"`. This leaves the
    plain path (LIST= onward) byte-identical.
  - NAMING: ws_-prefixed locals (ws_list/ws_filter/ws_idx/ws_sep/ws_out/ws_first/ws_total/
    ws_flen/ws_cidx/ws_i/ws_name/esc_wname/ws_tpl/ws_seg + cur_tpl/reg_tpl + ws_all[]/
    ws_filtered[]) — visually distinct from the plain path's LIST/FILTER/… so a reader
    never confuses the two (only one path runs, but clarity matters).
  - DEPENDENCIES: opt_tab_style (options.sh — sourced at renderer.sh header); get_state +
    STATE_TAB_CURRENT_TMPL/STATE_TAB_INACTIVE_TMPL/STATE_LIST/STATE_FILTER/STATE_INDEX
    (state.sh — sourced at header); lp_build_filtered (filter.sh — sourced at header);
    FG/BG/SHOW_COUNT (already read in the shared option block above the insertion).
  - STYLE: tabs; `local` declared FIRST then assign (SC2155-safe); double-quote all
    expansions; `printf '%s'` (no newline); `return 0` on every happy path.
  - NO new sourcing (all four libs already sourced at the renderer header). NO second
    crash guard (the top-level one covers the block).

Task 2: VALIDATE (syntax + throwaway isolated-socket smoke + full suite)
  - RUN: bash -n scripts/renderer.sh
  - RUN: shellcheck scripts/renderer.sh (expect 0 NEW findings)
  - RUN: the throwaway smoke (Validation Loop L2) against the socket-isolated harness —
    sets up state, runs the renderer, asserts the swapped/highlighted/joined output for
    window-status mode AND the unchanged plain output for plain/empty-cache; then DELETE
    the smoke file.
  - RUN: tests/run.sh (expect: full suite green, exit 0 — plain is the default so the new
    block is a no-op for every existing test; no regression).
```

### Implementation Patterns & Key Details

**The block (Task 1) — paste verbatim, inserted between the SHOW_COUNT `esac` and the
plain `LIST=` read:**

```bash
	# --- PRD §17: window-status render path (theme-matched tabs) ---
	# Self-contained early-return. Entered only when @livepicker-tab-style is
	# window-status AND both cached templates are non-empty (cached once at activation
	# by _lp_resolve_tab_templates, P1.M1.T2.S1). If EITHER fails, execution falls
	# through to the existing plain path below (untouched). The cached templates are
	# fully-resolved #[...]-styled strings with __lp_tab__ baked in where #W was; here
	# we swap __lp_tab__ -> each # escaped session name and join with
	# window-status-separator. #[...] styling in #() output IS applied
	# (external_tmux_behavior.md Q2); #{...} is NOT (why pre-resolution is needed).
	# See research/renderer_ws_branch_findings.md (FINDING 1-8).
	if [ "$(opt_tab_style)" = "window-status" ]; then
		local cur_tpl reg_tpl
		local ws_list ws_filter ws_idx esc_wfilter ws_sep ws_out ws_first ws_total
		local -a ws_all=() ws_filtered=()
		local ws_flen ws_cidx ws_i ws_name esc_wname ws_tpl ws_seg

		cur_tpl="$(get_state "$STATE_TAB_CURRENT_TMPL" "")"
		reg_tpl="$(get_state "$STATE_TAB_INACTIVE_TMPL" "")"
		# If EITHER template is empty (resolution failed -> set-empty by the writer, or
		# helper not yet run -> unset), fall through to the plain path. (FINDING 3:
		# get_state + [ -n ] fully honors the writer's set-empty contract and is leaner
		# than a tmux_is_set probe, which adds no branching signal.)
		if [ -n "$cur_tpl" ] && [ -n "$reg_tpl" ]; then
			ws_list="$(get_state "$STATE_LIST" "")"
			ws_filter="$(get_state "$STATE_FILTER" "")"
			esc_wfilter="${ws_filter//\#/##}"   # display escape: every # -> ## (tmux literal-#; Issue 3)
			ws_idx="$(get_state "$STATE_INDEX" "0")"
			ws_sep="$(tmux show-options -gwv window-status-separator 2>/dev/null)"
			[ -z "$ws_sep" ] && ws_sep=" "       # default to a space (window option; -gwv scope)

			mapfile -t ws_all < <(printf '%s' "$ws_list")
			ws_total="${#ws_all[@]}"
			mapfile -t ws_filtered < <(lp_build_filtered "$ws_list" "$ws_filter")
			ws_flen="${#ws_filtered[@]}"

			# no-match: mirror the plain path's no-match output (consistency; FINDING 6).
			if [ "$ws_flen" -eq 0 ]; then
				if [ "$SHOW_COUNT" -eq 1 ]; then
					printf '%s' "#[fg=$FG,bg=$BG]query> $esc_wfilter (no match) 0/$ws_total#[default]"
				else
					printf '%s' "#[fg=$FG,bg=$BG]query> $esc_wfilter (no match)#[default]"
				fi
				return 0
			fi

			# clamp cidx (same rule as the plain path; 0-based, wrap is input-handler's job).
			ws_cidx="$ws_idx"
			[[ "$ws_cidx" =~ ^[0-9]+$ ]] || ws_cidx=0
			[ "$ws_cidx" -ge "$ws_flen" ] && ws_cidx=$((ws_flen - 1))
			[ "$ws_cidx" -lt 0 ] && ws_cidx=0

			# Build the joined tabs: current template for the highlighted index, inactive
			# for the rest; swap __lp_tab__ -> the # escaped name (FINDING 4).
			ws_first=1
			ws_out=""
			for ws_i in "${!ws_filtered[@]}"; do
				ws_name="${ws_filtered[$ws_i]}"
				esc_wname="${ws_name//\#/##}"   # escape # BEFORE substitution (tmux literal-#)
				if [ "$ws_i" -eq "$ws_cidx" ]; then
					ws_tpl="$cur_tpl"
				else
					ws_tpl="$reg_tpl"
				fi
				# literal swap: ${var//pat/rep} does not re-scan the replacement, so a name
				# equal to __lp_tab__ cannot corrupt or recurse.
				ws_seg="${ws_tpl//__lp_tab__/$esc_wname}"
				if [ "$ws_first" -eq 1 ]; then
					ws_out="$ws_seg"
					ws_first=0
				else
					ws_out="$ws_out$ws_sep$ws_seg"
				fi
			done

			# SHOW_COUNT suffix — mirror the plain path for consistency (FINDING 6).
			if [ "$SHOW_COUNT" -eq 1 ]; then
				ws_out="$ws_out #[fg=$FG,bg=$BG]query> $esc_wfilter [$((ws_cidx + 1))/$ws_flen]#[default]"
			fi

			printf '%s' "$ws_out"   # ONE line, NO trailing newline (multi-line #() renders last only)
			return 0
		fi
		# (else: a template is empty -> fall through to the plain path below)
	fi
```

NOTE for the implementer: the block above is the complete, ready insertion. The only
allowed deviation is comment phrasing. Do NOT add a `tmux_is_set` gate (FINDING 3). Do NOT
escape `#` after the substitution (escape BEFORE — FINDING 4). Do NOT join with a plain
space (use `$ws_sep`). Do NOT touch the plain path. Do NOT add a second crash guard.

### Integration Points

```yaml
CODE:
  - file: scripts/renderer.sh
    change: "+1 if-block in render() (between SHOW_COUNT case and the plain LIST= read)"
    invariant: "window-status mode emits joined theme tabs; plain mode OR empty cache -> unchanged plain path"

CONSUMERS / PRODUCERS:
  - P1.M1.T2.S1 (livepicker.sh _lp_resolve_tab_templates): WRITES STATE_TAB_* this task READS.
    Contract: set-empty on failure -> get_state "" -> plain (correct); non-empty on success.
  - P1.M3.T2.S1 (tests/test_appearance.sh): validates §15.24 (this render path end-to-end).
  - restore.sh clear_all_state: clears STATE_TAB_* automatically (already in _STATE_RUNTIME_KEYS).

CONFIG / DATABASE / ROUTES: none.
```

## Validation Loop

### Level 1: Syntax & Style (Immediate Feedback)

```bash
cd /home/dustin/.config/tmux/plugins/tmux-livepicker
bash -n scripts/renderer.sh && echo "OK: renderer syntax"
shellcheck scripts/renderer.sh
# Tabs-not-spaces on the new region (shfmt NOT installed):
grep -nP '^ +[^#/]' scripts/renderer.sh && echo "WARN: space-indent (use tabs)" || echo "OK: tabs"
# Confirm the block is present + the plain path is intact:
grep -c 'opt_tab_style' scripts/renderer.sh        # -> 1 (the branch condition)
grep -c '__lp_tab__' scripts/renderer.sh           # -> 1 (the swap)
grep -c 'window-status-separator' scripts/renderer.sh  # -> 1 (the separator read)
# Confirm T1.S1 foundation is present (prerequisite):
grep -q 'opt_tab_style' scripts/options.sh && grep -q 'STATE_TAB_CURRENT_TMPL' scripts/state.sh \
  && echo "OK: T1.S1 foundation present" || echo "FAIL: P1.M1.T1.S1 not landed yet"
# Expected: syntax clean; shellcheck 0 new findings; block markers present once each.
```

### Level 2: Render-path smoke (via the existing socket-isolated harness)

Throwaway smoke (DELETE after; feature tests are P1.M3.T2). Reuses `tests/setup_socket.sh`
(PATH shim → bare `tmux` hits an isolated `-L` socket) + `tests/helpers.sh`. It populates
state directly (decoupled from T2.S1 — simulates the writer's cached output) and runs the
REAL renderer.sh as a subprocess (it is a `#()` command; its stdout is the render output):

```bash
cat > /tmp/smoke_render_ws.sh <<'EOF'
#!/usr/bin/env bash
set -u
cd /home/dustin/.config/tmux/plugins/tmux-livepicker
source tests/setup_socket.sh
source tests/helpers.sh
setup_test "lp-smoke-render-ws"

pass_n=0; fail_n=0
has() { if [ -n "$2" ] && [[ "$2" == *"$1"* ]]; then pass_n=$((pass_n+1)); else fail_n=$((fail_n+1)); echo "FAIL: missing [$1] in out"; fi; }
nohas() { if [[ "$2" != *"$1"* ]]; then pass_n=$((pass_n+1)); else fail_n=$((fail_n+1)); echo "FAIL: unexpected [$1] in out"; fi; }

# --- (1) window-status mode: both templates populated -> joined theme tabs ---
tmux set-option -g @livepicker-list $'alpha\nbeta\ngamma'
tmux set-option -g @livepicker-filter ''
tmux set-option -g @livepicker-index 1                 # highlight beta (index 1)
tmux set-option -g @livepicker-tab-style window-status
tmux set-option -g @livepicker-show-count on
tmux set-option -g @livepicker-tab-current-tmpl '#[fg=white,bg=blue]CUR=__lp_tab__#[default]'
tmux set-option -g @livepicker-tab-inactive-tmpl '#[fg=gray]REG=__lp_tab__#[default]'
out="$(bash scripts/renderer.sh)"
has "REG=alpha" "$out"     # index 0 inactive
has "CUR=beta"  "$out"     # index 1 highlighted (current template)
has "REG=gamma" "$out"     # index 2 inactive
has "query>"   "$out"      # SHOW_COUNT suffix mirrored
has "2/3"      "$out"      # count [cidx+1/FLEN] = [2/3]
nohas "__lp_tab__" "$out"  # placeholder fully swapped (none remain)
teardown_test

# --- (2) # escaping: a session name with # -> ## in the swapped segment ---
setup_test "lp-smoke-hash"
tmux set-option -g @livepicker-list $'foo#bar\nplain'
tmux set-option -g @livepicker-filter ''
tmux set-option -g @livepicker-index 0
tmux set-option -g @livepicker-tab-style window-status
tmux set-option -g @livepicker-show-count off
tmux set-option -g @livepicker-tab-current-tmpl '#[fg=white]CUR=__lp_tab__#[default]'
tmux set-option -g @livepicker-tab-inactive-tmpl '#[fg=gray]REG=__lp_tab__#[default]'
out="$(bash scripts/renderer.sh)"
has "CUR=foo##bar" "$out"   # # doubled (literal-#); NOT "CUR=foo#bar"
nohas "CUR=foo#bar" "$out"  # the unescaped form must NOT appear (#[ would be a directive)
teardown_test

# --- (3) FALLBACK: plain mode -> unchanged plain path ---
setup_test "lp-smoke-plain"
tmux set-option -g @livepicker-list $'alpha\nbeta'
tmux set-option -g @livepicker-filter ''
tmux set-option -g @livepicker-index 0
tmux set-option -g @livepicker-tab-style plain
tmux set-option -g @livepicker-show-count off
tmux set-option -g @livepicker-fg default
tmux set-option -g @livepicker-bg default
tmux set-option -g @livepicker-highlight-fg black
tmux set-option -g @livepicker-highlight-bg yellow
out="$(bash scripts/renderer.sh)"
has "#[fg=black,bg=yellow]alpha#[default]" "$out"   # plain highlight (NOT the template)
nohas "__lp_tab__" "$out"
nohas "CUR=" "$out"; nohas "REG=" "$out"             # templates not used
teardown_test

# --- (4) FALLBACK: window-status mode but a template is EMPTY -> plain path ---
setup_test "lp-smoke-emptycache"
tmux set-option -g @livepicker-list $'alpha\nbeta'
tmux set-option -g @livepicker-filter ''
tmux set-option -g @livepicker-index 0
tmux set-option -g @livepicker-tab-style window-status
tmux set-option -g @livepicker-show-count off
tmux set-option -g @livepicker-tab-current-tmpl ''    # EMPTY (simulates set-empty failure)
tmux set-option -g @livepicker-tab-inactive-tmpl '#[fg=gray]REG=__lp_tab__#[default]'
out="$(bash scripts/renderer.sh)"
has "#[fg=black,bg=yellow]alpha#[default]" "$out"    # fell through to PLAIN (unchanged)
nohas "REG=" "$out"; nohas "__lp_tab__" "$out"
teardown_test

# --- (5) no-match in window-status mode -> plain no-match output ---
setup_test "lp-smoke-nomatch"
tmux set-option -g @livepicker-list $'alpha\nbeta'
tmux set-option -g @livepicker-filter 'zzz'          # no match
tmux set-option -g @livepicker-index 0
tmux set-option -g @livepicker-tab-style window-status
tmux set-option -g @livepicker-show-count on
tmux set-option -g @livepicker-tab-current-tmpl '#[fg=white]CUR=__lp_tab__#[default]'
tmux set-option -g @livepicker-tab-inactive-tmpl '#[fg=gray]REG=__lp_tab__#[default]'
out="$(bash scripts/renderer.sh)"
has "(no match)" "$out"
has "0/2" "$out"          # 0 matches / 2 total (TOTAL mirrored)
nohas "__lp_tab__" "$out"
teardown_test

echo "pass=$pass_n fail=$fail_n"
[ "$fail_n" -eq 0 ]
EOF
bash /tmp/smoke_render_ws.sh; rc=$?
rm -f /tmp/smoke_render_ws.sh
exit $rc
# Expected: pass~=20 fail=0. (1) proves joined theme tabs + highlight + count; (2) proves
# the #-escape-before-substitution; (3)+(4) prove the plain fallback (plain mode AND empty
# cache); (5) proves the no-match mirror. Decoupled from T2.S1 (templates set directly).
```

### Level 3: Full suite (no regression)

```bash
cd /home/dustin/.config/tmux/plugins/tmux-livepicker
tests/run.sh
# Expected: exit 0, all existing tests green. The default tab-style is "plain" → the new
# block's outer `if` is false for every existing test → render() takes the unchanged plain
# path. No existing assertion can regress. (If a future test sets tab-style=window-status
# and asserts plain output, it would need updating — but none exists; appearance tests
# land in P1.M3.T2.)
```

### Level 4: Real-tubular template render (read-only sanity, end-to-end §17)

```bash
cd /home/dustin/.config/tmux/plugins/tmux-livepicker
# Resolve the REAL tubular formats (the T2.S1 sentinel mechanism) and feed them to the
# renderer, confirming the joined output contains the pill styles + swapped names. Uses a
# throwaway hidden session; no mutation of user state.
source tests/setup_socket.sh
source tests/helpers.sh
setup_test "lp-real-tubular"
SENT="__lp_man_$$_$(date +%s)"
tmux new-session -d -s "$SENT" -n __lp_anchor__
tmux new-window  -d -t "$SENT:" -n __lp_tab__
tmux select-window -t "$SENT:__lp_anchor__" 2>/dev/null || true
cur_fmt="$(tmux show-options -gwv window-status-current-format)"
reg_fmt="$(tmux show-options -gwv window-status-format)"
cur_tpl="$(tmux display-message -p -t "$SENT:__lp_tab__" "$cur_fmt" 2>/dev/null)"
reg_tpl="$(tmux display-message -p -t "$SENT:__lp_tab__" "$reg_fmt" 2>/dev/null)"
tmux kill-session -t "$SENT" 2>/dev/null
# Feed them to the renderer:
tmux set-option -g @livepicker-list $'hack\nmain\ntmux'
tmux set-option -g @livepicker-filter ''
tmux set-option -g @livepicker-index 0
tmux set-option -g @livepicker-tab-style window-status
tmux set-option -g @livepicker-show-count off
tmux set-option -g @livepicker-tab-current-tmpl "$cur_tpl"
tmux set-option -g @livepicker-tab-inactive-tmpl "$reg_tpl"
out="$(bash scripts/renderer.sh)"
printf 'rendered (head): %s\n' "${out:0:120}"
case "$out" in *"hack"*) echo "OK: session name swapped in";; *) echo "FAIL: name missing";; esac
case "$out" in *"#{"*) echo "FAIL: unexpanded #{} leaked";; *) echo "OK: no raw #{}";; esac
teardown_test
# Expected: the rendered line contains the session names inside the tubular pill styles,
# no raw #{, no leftover __lp_tab__. (Confirms the full §17 path with real theme templates.)
```

## Final Validation Checklist

### Technical Validation

- [ ] `bash -n scripts/renderer.sh` clean.
- [ ] `shellcheck scripts/renderer.sh`: 0 NEW findings (the `local`-inside-`if` and
      `${var//pat/rep}` usages are valid bash; add a `# shellcheck disable=` directive only
      if a specific SC fires, with rationale).
- [ ] Block inserted between the SHOW_COUNT `esac` and the plain `LIST=` read; plain path
      byte-identical (diff shows ONLY the inserted block).
- [ ] T1.S1 foundation present (opt_tab_style + STATE_TAB_* — verify at edit time).

### Feature Validation

- [ ] window-status + both templates: joined tabs emitted; highlighted index uses the
      current template, rest inactive; `__lp_tab__` swapped → name (L2 §1).
- [ ] Session name with `#` emitted as `##` (L2 §2).
- [ ] plain mode → unchanged plain output (L2 §3).
- [ ] window-status + empty cache → unchanged plain output (L2 §4, the fallback).
- [ ] no-match in window-status → plain no-match output incl. `0/$TOTAL` (L2 §5).
- [ ] Real tubular templates render with names swapped, no raw `#{` (L4).
- [ ] Full `tests/run.sh` suite green (exit 0); no regression.

### Code Quality Validation

- [ ] Block is a self-contained early-return; plain path never forked/duplicated.
- [ ] Branch on `opt_tab_style == window-status`; entry requires BOTH templates `[ -n ]`.
- [ ] `#`-escape applied BEFORE the `${tpl//__lp_tab__/…}` substitution.
- [ ] Tabs joined with `$ws_sep` (window-status-separator), not a plain space.
- [ ] Every happy path `printf '%s' …; return 0` (one line, no trailing newline).
- [ ] `ws_`-prefixed locals; `local` declared before assign (SC2155-safe); tabs; `set -u`-safe.
- [ ] No second crash guard (the top-level one covers the block).

### Documentation & Deployment

- [ ] Inline comments cross-reference PRD §17/§16 + the research FINDINGs + the T2.S1 writer.
- [ ] No README/CHANGELOG change here (Mode-A internal render step; the §17 config row +
      docs sync is P1.M3.T3.S1). The README already documents `@livepicker-tab-style`.
- [ ] Do NOT commit a tests/ file (feature tests are P1.M3.T2 test_appearance.sh).

---

## Anti-Patterns to Avoid

- ❌ Don't gate the block on `tmux_is_set` — `get_state` + `[ -n ]` is equivalent for
  branching (both set-empty and unset → "" → plain), honors the writer's set-empty
  contract, and is 2 fewer tmux calls the renderer's budget can't spare. (FINDING 3.)
- ❌ Don't escape `#` AFTER the substitution, or skip the escape — a session name with `#`
  would be read as a stray tmux directive. `${ws_name//\#/##}` BEFORE
  `${ws_tpl//__lp_tab__/$esc_wname}`. (FINDING 4.)
- ❌ Don't join tabs with a plain space — use `$ws_sep` (window-status-separator). A space
  is only the DEFAULT when the separator reads empty.
- ❌ Don't fork/duplicate the plain highlight logic — the window-status block has its OWN
  template-swap loop; the plain path (LIST= onward) stays byte-identical.
- ❌ Don't forget `return 0` on every happy path (no-match, normal render) — without it the
  block falls through to the plain path and double-renders.
- ❌ Don't add a second crash guard inside the block — the top-level
  `render || printf '…renderer error…'` already covers it.
- ❌ Don't use a here-string `<<<` for the list — use process-substitution
  `< <(printf '%s' …)` so an empty list yields `[]` not `[""]` (renderer research FINDING 3).
- ❌ Don't emit a trailing newline — `printf '%s'` (multi-line `#()` stdout renders only
  the last line; data loss).
- ❌ Don't try to expand `#{…}` or resolve the separator's `#{…}` in the renderer — that's
  the activation sentinel's job (T2.S1); the renderer only swaps `__lp_tab__` and emits
  pre-resolved `#[…]` styles. A themed separator with `#{…}` is a documented edge case.
- ❌ Don't touch `out=""` / the plain no-match / the plain loop / the plain SHOW_COUNT
  suffix — those belong to the untouched plain path.
- ❌ Don't commit a tests/ file — feature validation is P1.M3.T2; use the throwaway L2 smoke.
- ❌ Don't edit by line number — anchor on the SHOW_COUNT `esac` + `LIST=` content.
- ❌ Don't add `set -e` — unset options make `show-option` return rc=1 (would blank line 1).

---

## Confidence Score

**9 / 10** for one-pass success. Rationale: the block body is given verbatim and is pure
bash string-op + the already-shipped `get_state`/`lp_build_filtered`/`#`-escape idioms;
the branch placement is pinned by content (the SHOW_COUNT `esac` + `LIST=` pair is unique);
the two load-bearing correctness points (get_state-vs-tmux_is_set; `#`-escape-before-
substitution) are empirically reasoned in the research findings and asserted in the L2
smoke (§2 proves `foo#bar` → `foo##bar`); the plain fallback is proven twice (plain mode §3
AND empty-cache §4); and the real-tubular L4 confirms the full §17 path with live theme
templates. The plain path is byte-identical (diff-verifiable) so the default mode cannot
regress — `tests/run.sh` stays green by construction. Residual risk: a shellcheck SC on the
`local`-inside-`if` or the `${var//pat/rep}` (both valid bash; mitigated by a directive if
one fires) and the themed-separator-`#{…}` edge case (documented; out of scope, rare).
