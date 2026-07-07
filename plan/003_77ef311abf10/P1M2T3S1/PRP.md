# PRP — P1.M2.T3.S1: Rework window-status path through §19; remove opt_show_count + all SHOW_COUNT logic

> **Scope**: Fold the §17 window-status (ws) render path into the SAME §19 layout engine the
> plain path uses (P1.M2.T1.S1 + the in-flight P1.M2.T2.S1), parameterized by a per-style
> "render one tab" strategy + inter-tab separator — so ws gets the query bar, viewport
> windowing, and overflow indicators it currently bypasses. Then DELETE `opt_show_count` and
> every SHOW_COUNT reference (the `index/total` count + `query>` label exist NOWHERE).
> The §17 Fallback (empty/unresolvable template → plain) is preserved. **Builds on T2's
> landed plain-path output** (sequenced: T1 done → T2 → T3); several edits target T2's
> verbatim output (quoted from its PRP).

---

## Goal

**Feature Goal**: `render()` has ONE §19-compliant layout engine for BOTH tab styles. The
ws path is no longer a separate early-return that joins all tabs + a count suffix; it runs
through the same query-empty / query-active / no-match / viewport / overflow-indicator
flow as plain, differing only in (a) how one tab renders (cached-template swap vs
fg/bg coloring) and (b) the inter-tab separator (`window-status-separator` vs single
space). `opt_show_count` and all SHOW_COUNT logic are deleted; the `index/total` count and
the `query>` label exist nowhere.

**Deliverable**: Edits to THREE files — **no new files, no committed test** (P1.M4.T1 owns
`test_layout.sh`; the existing `test_appearance.sh` stays green — FINDING 7).
1. `scripts/renderer.sh`: drop SHOW_COUNT from the first locals + the option-read prefix;
   DELETE the ws early-return block; add the §17 tab-style/template/separator decision;
   parameterize the tab-build loop (style conditional + `$sep` join); make the viewport
   separator-width arg dynamic (`$sep_w`).
2. `scripts/options.sh`: delete the `opt_show_count()` accessor.
3. `tests/test_appearance.sh`: remove the 2 stale `@livepicker-show-count off` lines +
   neutralize the stale comments (the option no longer exists).

**Success Definition**:
- ws mode (query-empty): tabs rendered via the cached templates (current vs inactive),
  joined by `window-status-separator`, justified per `status-justify` — byte-identical to
  today for the width=0 case (test_appearance.sh a/b/c/e still pass).
- ws mode (query-active): `<icon><query><gap><tabs windowed by scroll><indicators>` (NEW —
  previously ws bypassed this entirely).
- ws mode (no-match): `<icon><query> (no match)` (shared §19 format).
- plain mode: byte-identical to T2's output (sep=" ", sep_w=1).
- §17 Fallback: either ws template empty → plain styling (test (c) passes).
- `grep -rn 'show-count\|SHOW_COUNT\|opt_show_count' scripts/ tests/` → no matches
  (README row is P4.T1).
- `tests/run.sh` green.

## User Persona (if applicable)

**Target User**: A user with a themed tmux setup (tubular/catppuccin/gruvbox) who wants
the picker to look like their window tabs AND behave like a modern picker (query bar,
scrollable viewport, overflow indicators) — not the stripped-down "all tabs + count" the
old ws path showed.

**Use Case**: `@livepicker-tab-style window-status` + many sessions: the user types to
filter, sees their theme-styled tabs scroll within the available width with `<`/`+N>`
indicators, exactly like plain mode but with their tab look.

**Pain Points Addressed**: The old ws path ignored the query bar and viewport (it dumped
all tabs + a count suffix), so a long themed list overflowed silently and the query was
invisible inline. Folding it into §19 gives ws users the same layout UX plain users have.

## Why

- **PRD §17 diff (confirmed in delta_prd)**: "status-justify positions the tabs only when
  there is no query and the tabs fit; otherwise the section 19 viewport rules apply." The
  ws path must obey §19, not bypass it.
- **DRY / one engine.** The two styles differ in exactly two things (per-tab render +
  separator — FINDING 2). Duplicating the query-bar/viewport/indicator assembly would
  drift; factoring it into one parameterized engine is correct + maintainable (contract:
  "do NOT duplicate layout logic").
- **`opt_show_count` is obsolete.** §19 removed the count indicator entirely; T1 already
  dropped its plain-path use. The only remaining readers are the ws path (being folded in)
  and the accessor itself. Deleting it completes the §19 cleanup ("count exists NOWHERE").
- **Cheap, surgical, low-risk.** The layout engine (T2's viewport + indicators + branches)
  is reused verbatim; only the tab-build loop gets a style conditional + `$sep` join, plus
  a small tab-style decision block + the dynamic `sep_w`. SHOW_COUNT removal is deletions.
- **Backward-compatible with the existing suite.** test_appearance.sh exercises only
  query-empty + width=0, where the new engine is byte-identical to the old ws output
  (FINDING 7). No committed test breaks.

## What

1. **Drop SHOW_COUNT** from renderer's first locals + option-read prefix (Edits B, C).
2. **Delete the ws early-return block** (Edit D) — the whole `if opt_tab_style=window-status
   … fi` + its comments.
3. **Add the §17 tab-style decision** (Edit E) after the `cidx` clamp, before T2's viewport
   block: read `opt_tab_style`; if ws, read the two cached templates + `window-status-separator`,
   compute `sep` + `sep_w`; if either template empty → fall back to plain.
4. **Parameterize the tab-build loop** (Edit F): ws swaps `__lp_tab__`/`__lp_sentinel__` →
   name in the current/inactive template; plain uses fg/bg; join with `$sep`.
5. **Dynamic viewport separator width** (Edit H): the two `lp_viewport … 1` calls → `…
   "$sep_w"` (correct ws windowing when the separator is multi-char).
6. **Delete `opt_show_count`** from options.sh (Edit A) + clean stale refs in
   test_appearance.sh (Edit I).
7. **Do NOT change**: the no-match branch, the viewport resolution algorithm (T2's probe +
   converge), the overflow-indicator styling/placement, the query-empty/query-active
   branch logic, the header sources, the driver, `livepicker.sh`/`restore.sh`, any state
   shape, or the README (P4.T1).

### Success Criteria

- [ ] `grep -c 'opt_show_count' scripts/options.sh` → `0`.
- [ ] `grep -rn 'SHOW_COUNT\|opt_show_count\|show-count' scripts/ tests/` → no matches.
- [ ] renderer has NO `if [ "$(opt_tab_style)" = "window-status" ]` early-return (folded in).
- [ ] The tab-build loop branches on `$tab_style` (ws template-swap vs plain fg/bg) + joins
      with `$sep`.
- [ ] The two `lp_viewport` calls pass `"$sep_w"` (not `1`).
- [ ] §17 Fallback: empty `cur_tpl` OR `reg_tpl` → `tab_style=plain`.
- [ ] test_appearance.sh: 5/5 pass; the 2 `@livepicker-show-count off` lines removed.
- [ ] `bash -n` + `shellcheck` clean; `tests/run.sh` green.

## All Needed Context

### Context Completeness Check

_Pass_: an implementer who has never seen this repo can do it from (a) the verbatim
old→new blocks (T2-untouched regions from the live file; T2-touched regions quoted from
T2's PRP), (b) the shared-engine design (FINDING 3), (c) the dynamic `sep_w` rule
(FINDING 4), (d) the test_appearance.sh backward-compat proof (FINDING 7), and (e) the
SHOW_COUNT removal scope (FINDING 8). All deps COMPLETE; T2's output is the contract.

### Documentation & References

```yaml
# MUST READ — the empirical ground-truth for THIS task (10 verified findings)
- docfile: plan/003_77ef311abf10/P1M2T3S1/research/ws_path_section19_findings.md
  why: FINDING 1 (deps + post-T2 state reconstruction); FINDING 2 (the 2-thing factoring
       seam); FINDING 3 (the shared-engine design + flow); FINDING 4 (CRITICAL: dynamic
       sep_w for the viewport — T2 hardcodes 1); FINDING 5 (chrome uses FG/BG for both
       styles); FINDING 6 (§17 fallback preserved); FINDING 7 (test_appearance.sh
       backward-compatible — suite green); FINDING 8 (SHOW_COUNT removal scope); FINDING 9
       (sequenced on T2, NOT parallel-safe on renderer.sh); FINDING 10 (style/set -u).
  critical: FINDING 4 (sep_w) + FINDING 7 (suite stays green) + FINDING 9 (run AFTER T2).

# MUST READ — the CONTRACT this task builds on (T2's windowed plain path; assume landed)
- docfile: plan/003_77ef311abf10/P1M2T2S1/PRP.md
  why: T2 (in-flight, lands FIRST) adds viewport windowing + overflow indicators to the
       plain path. THIS task's oldText for the tab-build loop, the locals line, and the two
       lp_viewport calls = T2's Task-1/Task-2 output (VERBATIM). T2 leaves the ws early-
       return, the option-read prefix, and no-match UNTOUCHED (those match the live file).
  section: "Implementation Patterns / Task 1 (locals)" + "Task 2 (windowed body)"

# MUST READ — the plain-path §19 restructure (T1, landed; the engine T2 extended)
- docfile: plan/003_77ef311abf10/P1M2T1S1/PRP.md
  why: T1 (Complete) restructured the plain path into 3 §19 branches (query-empty/active/
       no-match) + dropped the plain SHOW_COUNT use + read STATE_SCROLL/STATE_CLIENT_WIDTH.
       This task removes the SHOW_COUNT COMPUTATION T1 kept (ws still used it) now that ws
       is folded in. The no-match branch T1 wrote is the SHARED no-match (unchanged here).

# MUST READ — PRD §17 (tab appearance / the ws mechanism + fallback) + §19 (the layout)
- docfile: PRD.md
  why: §17 (the cached templates with __lp_tab__ baked in; @livepicker-tab-style plain|
       window-status; Fallback: empty/unresolvable template -> plain; inter-tab gap =
       window-status-separator). §19 §3.30/§3.31/§3.32/§3.33/§3.34 (query-empty justify /
       query-active pinned-left / viewport windowing by scroll / overflow indicators /
       no-match) — the SHARED layout both styles now use. §3.32 "joined by window-status-
       separator in window-status mode, or a single space in plain mode" = the sep_w rule.
  section: "§17 Tab appearance", "§19 Status-line layout"

# MUST READ — the file being modified (both paths + SHOW_COUNT)
- file: scripts/renderer.sh
  why: render() — the ws early-return block (deleted), the option-read prefix + first
        locals (SHOW_COUNT dropped), the no-match branch (shared, unchanged), and T2's
        plain-path region (parameterized). CURRENT_DIR + sources already include layout.sh.
  pattern: the current ws block already does the __lp_tab__/__lp_sentinel__ swap + the
           window-status-separator read + the empty-template fallback — this task MOVES
           those into the shared engine (they're not new logic, just relocated + de-duped).
  gotcha: the ws block, option-read prefix, first locals, and no-match match the LIVE file
          (T2 doesn't touch them); the tab-build loop + the two lp_viewport calls + the
          locals line match T2's OUTPUT (quote from T2's PRP). Run AFTER T2 lands.

# MUST READ — the option accessors (incl. the one being deleted + the ws ones)
- file: scripts/options.sh
  why: opt_show_count (line 43 — DELETED); opt_tab_style (the style switch); the layout
        accessors (opt_overflow_left/right_format/nerd_fonts/search_icon/query_gap) — all
        COMPLETE. Single-line `{ get_opt ...; } # comment` pattern.
  gotcha: deleting opt_show_count leaves its @livepicker-show-count option unreferenced in
          code; the README row (line 114) is P4.T1's job — do NOT edit README here.

# MUST READ — lp_viewport / lp_disp_width (the viewport this task keeps + re-parameterizes)
- file: scripts/layout.sh
  why: lp_viewport RANKED T SCROLL HIGHLIGHT [SEP=1] sets LPV_START/END/HIDDEN_LEFT/RIGHT.
       The 5th arg SEP is the inter-tab SEPARATOR WIDTH (T2 passed 1; this task passes
       sep_w). lp_disp_width strips #[…] + counts codepoints (use it on $sep). Pure bash.
  gotcha: a STYLED separator (e.g. #[fg=blue] | #[default]) is measured by lp_disp_width
          (visible glyphs) and emitted verbatim when joining — correct on both axes.

# MUST READ — the cached ws templates + scroll/width state keys
- file: scripts/state.sh
  why: STATE_TAB_CURRENT_TMPL / STATE_TAB_INACTIVE_TMPL (§17 cached templates; read by the
        tab-style decision; written at activate by _lp_resolve_tab_templates). STATE_SCROLL
        / STATE_CLIENT_WIDTH (read for the viewport; width=0 -> degraded full-list render).
  gotcha: STATE_CLIENT_WIDTH is UNWRITTEN until P1.M3.T1 -> width=0 -> full-list render ->
          test_appearance.sh (which doesn't set it) sees byte-identical output (FINDING 7).

# MUST READ — the test that exercises ws (proves backward-compat; + the stale-ref cleanup)
- file: tests/test_appearance.sh
  why: 5 ws tests, ALL query-empty + width=0 -> the new engine is byte-identical to the old
        ws output (FINDING 7). Lines 65 + 170 set @livepicker-show-count off (no-ops after
        Edit A) -> Edit I removes them. Comments at 43/57/102 reference show-count -> Edit I.
  gotcha: do NOT change the test ASSERTIONS (they still hold); only remove the 2 stale
          set-option lines + neutralize the stale comment phrases.

# Reference — renderer load-bearing rules (§P6)
- docfile: plan/003_77ef311abf10/architecture/codebase_patterns.md
  why: §P6 — ONE line no trailing newline (printf '%s' "$out" QUOTED); #[default] after
       every segment; NO set -e; render||fallback-red; PURE+FAST (option reads + pure-bash
       only; width from cached STATE_CLIENT_WIDTH, NEVER display-message per-keystroke).
  section: "P6 — Renderer rules (renderer.sh)"
```

### Current Codebase tree

```bash
tmux-livepicker/
  scripts/
    renderer.sh     # MODIFY: drop SHOW_COUNT; delete ws early-return; +tab-style decision;
                    #   parameterize tab-build loop (style + $sep); dynamic sep_w in lp_viewport
    options.sh      # MODIFY: DELETE opt_show_count()
    layout.sh       # UNCHANGED (lp_viewport/lp_disp_width — consumed; 5th arg now sep_w)
    rank.sh         # UNCHANGED (lp_rank — the ranked list)
    state.sh        # UNCHANGED (STATE_TAB_*/SCROLL/CLIENT_WIDTH — read only)
    livepicker.sh, input-handler.sh, preview.sh, restore.sh, utils.sh   # UNCHANGED
  tests/
    test_appearance.sh   # MODIFY: remove 2 stale @livepicker-show-count off lines + comment phrases
    test_functional.sh, test_responsiveness.sh   # UNCHANGED (T1 already dropped query>; no show-count refs)
    test_layout.sh       # (does NOT exist yet — P1.M4.T1)
    run.sh, setup_socket.sh, helpers.sh   # UNCHANGED
```

### Desired Codebase tree with files to be added and responsibility of file

```bash
scripts/renderer.sh        # ONE §19 layout engine for both tab styles; SHOW_COUNT gone; ws folded in
scripts/options.sh         # opt_show_count deleted
tests/test_appearance.sh   # stale show-count references removed (assertions unchanged)
```

### Known Gotchas of our codebase & Library Quirks

```bash
# CRITICAL (research FINDING 9): this task is NOT parallel-safe with T2 on renderer.sh.
# RUN AFTER T2 LANDS. The oldText for the tab-build loop, the locals line, and the two
# lp_viewport calls is T2's OUTPUT (quote it from T2's PRP). The ws block / option-read
# prefix / first locals / no-match match the LIVE file. If T2 hasn't landed, STOP.

# CRITICAL (research FINDING 4): the viewport separator-width arg. T2 hardcodes `1` in
# both lp_viewport calls (plain's single space). ws uses window-status-separator, which
# can be multi-char (e.g. " | " -> width 3). Pass "$sep_w" (= lp_disp_width "$sep"; 1 for
# plain, the real width for ws). Forgetting this mis-windows ws tabs when the separator
# is wide. (For plain sep_w=1 -> no behavior change vs T2.)

# CRITICAL (research FINDING 8): SHOW_COUNT must be gone EVERYWHERE in scripts/ + tests/.
# Edits: A (options.sh accessor), B+C (renderer prefix), D (ws block — carries its SHOW_COUNT
# branches), I (test_appearance.sh stale set-option + comments). README row (line 114) is
# P4.T1 — do NOT edit README here, but NOTE it for P4.

# CRITICAL: preserve BOTH __lp_tab__ AND __lp_sentinel__ swaps in the ws tab-render (the
# Issue 5 fix from plan 002). The cached template may contain either placeholder (#W ->
# __lp_tab__; #S/#{session_name} -> __lp_sentinel__). Both map to the SAME candidate name.

# GOTCHA (research FINDING 5): chrome (query bar / no-match / overflow indicators) uses
# FG/BG for BOTH styles. Do NOT try to theme-style the indicators in ws mode (under-
# specified; the templates are tab-specific). Reuse T2's chrome code verbatim.

# GOTCHA (research FINDING 6): §17 Fallback — if EITHER ws template is empty, set
# tab_style="plain" (keep sep=" ", sep_w=1). The tab-build loop then takes the plain branch.
# test_empty_template_falls_back_to_plain asserts this.

# GOTCHA: the tab-style decision reads opt_tab_style every redraw (1 read). For PLAIN mode
# (default) it stops there — no template/separator reads (no penalty). For ws it reads 2
# get_state + 1 show-options (same as the old ws block). Within the §18 budget.

# GOTCHA: lp_disp_width on the separator handles a STYLED separator (#[...] stripped for
# the width count; emitted verbatim when joining). Do NOT strip styles from $sep yourself.

# GOTCHA (research FINDING 7): test_appearance.sh tests are query-EMPTY + width=0 -> the
# new engine is byte-identical to the old ws output. Do NOT change their ASSERTIONS. Only
# remove the 2 stale @livepicker-show-count off lines + neutralize comment phrases.

# GOTCHA: the ws block deletion (Edit D) is a LARGE contiguous block. Anchor on its unique
# start (`# --- PRD §17: window-status render path (theme-matched tabs) ---`) and end (the
# outer `fi` + `# (else: a template is empty -> fall through to the plain path below)`),
# leaving `LIST="$(get_state "$STATE_LIST" "")"` as the next line.

# STYLE: TABS throughout (shfmt absent). renderer plain path is 1-tab inside render(); the
# viewport/loop bodies at 2-3 tabs. SC1091/SC2034 file-wide disabled (new locals covered).
# `printf '%s' "..."` MUST be quoted everywhere (§P6).
```

## Implementation Blueprint

### Data models and structure

No data model. The "structure" is the unified render() flow (FINDING 3): the §17 tab-style
decision feeds `tab_style`/`cur_tpl`/`reg_tpl`/`sep`/`sep_w` into the SHARED §19 engine
(no-match → clamp → viewport → tab-build → query-empty/query-active branches). The two
styles plug in at exactly two seams: the per-tab segment (loop body) + the join (`$sep`).

### Implementation Tasks (ordered by dependencies)

```yaml
Task 1: MODIFY scripts/options.sh — DELETE opt_show_count (Edit A)
  - LOCATE the accessor line (line ~43): opt_show_count() { get_opt "@livepicker-show-count" "on"; }
  - DELETE it (anchor on it + a neighbor so the line vanishes cleanly). Verbatim in Patterns.

Task 2: MODIFY scripts/renderer.sh — drop SHOW_COUNT from the first locals + prefix (Edits B, C)
  - Edit B: first locals line — drop `SHOW_COUNT_RAW SHOW_COUNT`.
  - Edit C: option-read prefix — delete the SHOW_COUNT_RAW/case block (keep HBG= above).

Task 3: MODIFY scripts/renderer.sh — DELETE the ws early-return block (Edit D)
  - Delete the entire `# --- PRD §17: window-status render path ---` … outer `fi` + the
    trailing `# (else: ...)` comment. The next line `LIST="$(get_state "$STATE_LIST" "")"`
    STAYS. (Large block; anchor on its unique start/end — see Patterns.)

Task 4: MODIFY scripts/renderer.sh — extend the plain-path locals (Edit G)
  - T2's locals line — APPEND `tab_style cur_tpl reg_tpl sep sep_w`. (oldText = T2's output.)

Task 5: MODIFY scripts/renderer.sh — INSERT the §17 tab-style decision (Edit E)
  - Insert AFTER the `cidx` clamp, BEFORE T2's `# --- viewport windowing` block. Computes
    tab_style/cur_tpl/reg_tpl/sep/sep_w (with the §17 empty-template fallback). Verbatim in Patterns.

Task 6: MODIFY scripts/renderer.sh — parameterize the tab-build loop (Edit F)
  - T2's loop — add the `if tab_style=window-status` branch (template swap) + the plain
    `else`; change the join `tabs="$tabs $seg"` -> `tabs="$tabs$sep$seg"`. (oldText = T2's loop.)

Task 7: MODIFY scripts/renderer.sh — dynamic viewport separator width (Edit H)
  - The TWO `lp_viewport "$ranked" "$T0"…"$cidx" 1` and `…"$vp_T"…"$cidx" 1` calls -> `"$sep_w"`.

Task 8: MODIFY tests/test_appearance.sh — remove stale show-count refs (Edit I)
  - Delete the `tmux set-option -g @livepicker-show-count off` line in lp_appearance_seed
    (line ~65) and in test (e) (line ~170). Neutralize the stale comment phrases (lines ~43/57/102).
    Do NOT touch any assertion.

Task 9: VALIDATE (L1 grep + L2 full suite + L3 throwaway ws smoke)
  - RUN: bash -n scripts/renderer.sh scripts/options.sh tests/test_appearance.sh ; shellcheck all three.
  - RUN: grep cross-checks (SHOW_COUNT/opt_show_count = 0; no ws early-return; loop branches on
    tab_style; lp_viewport passes sep_w; §17 fallback present).
  - RUN: tests/run.sh (expect green — test_appearance.sh 5/5 backward-compatible; the rest unaffected).
  - RUN: the throwaway ws §19 smoke (query-active ws shows icon+query+gap+tabs; viewport+indicators
    with a wide separator); then DELETE it. (Committed ws-layout tests are P1.M4.T1.)
```

### Implementation Patterns & Key Details

> All anchors are CONTENT-based. Indent is TABS. **Run AFTER T2 lands** — Edits F/G/H's
> oldText is T2's output (quoted from T2's PRP); Edits B/C/D's oldText is the live file.

**Edit A — options.sh: delete opt_show_count.**

```bash
# oldText (the accessor + its neighbors, so the line deletes cleanly):
opt_highlight_bg()         { get_opt "@livepicker-highlight-bg" "yellow"; }   # tmux color
opt_show_count()           { get_opt "@livepicker-show-count" "on"; }         # bool on/off
opt_status_format_index()  { get_opt "@livepicker-status-format-index" "0"; } # int 0-9
# newText:
opt_highlight_bg()         { get_opt "@livepicker-highlight-bg" "yellow"; }   # tmux color
opt_status_format_index()  { get_opt "@livepicker-status-format-index" "0"; } # int 0-9
```

**Edit B — renderer first locals: drop SHOW_COUNT.**

```bash
# oldText:
	local TYPE FG BG HFG HBG SHOW_COUNT_RAW SHOW_COUNT
# newText:
	local TYPE FG BG HFG HBG
```

**Edit C — renderer option-read prefix: drop the SHOW_COUNT block.**

```bash
# oldText:
	HBG="$(opt_highlight_bg)"
	SHOW_COUNT_RAW="$(opt_show_count)"
	case "${SHOW_COUNT_RAW,,}" in
		'' | off | 0 | no | false | disable) SHOW_COUNT=0 ;;
		*) SHOW_COUNT=1 ;;
	esac
# newText:
	HBG="$(opt_highlight_bg)"
```

**Edit D — DELETE the ws early-return block.** Anchor: from the unique comment
`# --- PRD §17: window-status render path (theme-matched tabs) ---` through the outer
`fi` that closes `if [ "$(opt_tab_style)" = "window-status" ]` AND the trailing comment
`# (else: a template is empty -> fall through to the plain path below)`. The line
`LIST="$(get_state "$STATE_LIST" "")"` (immediately after) MUST remain. Replace the whole
block with a single orienting comment:

```bash
# newText (replaces the ENTIRE ws early-return block):
	# (§17 window-status is handled by the shared §19 engine below — the tab-style
	#  decision picks the per-tab render strategy + separator; no separate early-return.)
```

(The block is the whole `if [ "$(opt_tab_style)" = "window-status" ]; then … fi` construct
plus its leading `# --- PRD §17` comment block and the trailing `# (else: …)` comment.
Match it TAB-for-TAB; it is contiguous and bounded by the two unique anchors above. All
its logic — template read, `__lp_tab__`/`__lp_sentinel__` swap, separator join, empty-
template fall-through, no-match — is RELOCATED into Edits E/F, not lost.)

**Edit G — extend T2's plain-path locals.** oldText = T2's Task-1 output:

```bash
# oldText:
	local out seg i cidx first esc_filter esc_name SCROLL icon gap tabs justify width pad padw tabs_w \
		vis_start vis_end left_ind right_ind qbw T0 vp_T th ind_w left_present new_lp ovl ovr_fmt ranked
# newText (append the 5 new locals):
	local out seg i cidx first esc_filter esc_name SCROLL icon gap tabs justify width pad padw tabs_w \
		vis_start vis_end left_ind right_ind qbw T0 vp_T th ind_w left_present new_lp ovl ovr_fmt ranked \
		tab_style cur_tpl reg_tpl sep sep_w
```

**Edit E — INSERT the §17 tab-style decision** (after the `cidx` clamp `[ "$cidx" -lt 0 ] && cidx=0`,
before T2's `# --- viewport windowing + overflow indicators` block):

```bash
# newText (insert between the cidx clamp and the viewport block):
	# --- §17 tab style + per-tab render strategy + inter-tab separator (shared §19 engine).
	# plain: standalone fg/bg coloring, joined by a single space. window-status: each tab
	# renders by swapping __lp_tab__/__lp_sentinel__ -> the # escaped name in the cached
	# template (current vs inactive per index), joined by window-status-separator. If EITHER
	# ws template is empty (resolution failed / not yet cached), fall back to plain (§17
	# Fallback) so the option never breaks a setup. The §19 layout (query bar / viewport /
	# overflow indicators / query-empty vs query-active / no-match) is IDENTICAL for both.
	tab_style="$(opt_tab_style)"
	cur_tpl=""; reg_tpl=""; sep=" "; sep_w=1
	if [ "$tab_style" = "window-status" ]; then
		cur_tpl="$(get_state "$STATE_TAB_CURRENT_TMPL" "")"
		reg_tpl="$(get_state "$STATE_TAB_INACTIVE_TMPL" "")"
		if [ -z "$cur_tpl" ] || [ -z "$reg_tpl" ]; then
			tab_style="plain"   # §17 Fallback: empty/unresolvable template -> plain
		else
			sep="$(tmux show-options -gwv window-status-separator 2>/dev/null)"
			[ -z "$sep" ] && sep=" "
			sep_w="$(lp_disp_width "$sep")"
		fi
	fi
```

**Edit F — parameterize the tab-build loop.** oldText = T2's loop; newText adds the style
conditional + `$sep` join (the plain branch is byte-identical to T2's, just nested):

```bash
# oldText (T2's loop):
	first=1
	tabs=""
	for (( i = vis_start; i <= vis_end; i++ )); do
		esc_name="${filtered[$i]//\#/##}"
		if [ "$i" -eq "$cidx" ]; then
			seg="#[fg=$HFG,bg=$HBG]${esc_name}#[default]"
		else
			seg="#[fg=$FG,bg=$BG]${esc_name}#[default]"
		fi
		if [ "$first" -eq 1 ]; then
			tabs="$seg"
			first=0
		else
			tabs="$tabs $seg"
		fi
	done
# newText:
	first=1
	tabs=""
	for (( i = vis_start; i <= vis_end; i++ )); do
		esc_name="${filtered[$i]//\#/##}"
		if [ "$tab_style" = "window-status" ]; then
			# §17: swap __lp_tab__/__lp_sentinel__ -> name in the cached template (current
			# vs inactive per index). ${var//pat/rep} does not re-scan the replacement, so
			# a name equal to a placeholder cannot corrupt or recurse.
			if [ "$i" -eq "$cidx" ]; then
				seg="${cur_tpl//__lp_tab__/$esc_name}"
				seg="${seg//__lp_sentinel__/$esc_name}"
			else
				seg="${reg_tpl//__lp_tab__/$esc_name}"
				seg="${seg//__lp_sentinel__/$esc_name}"
			fi
		else
			if [ "$i" -eq "$cidx" ]; then
				seg="#[fg=$HFG,bg=$HBG]${esc_name}#[default]"
			else
				seg="#[fg=$FG,bg=$BG]${esc_name}#[default]"
			fi
		fi
		if [ "$first" -eq 1 ]; then
			tabs="$seg"
			first=0
		else
			tabs="$tabs$sep$seg"
		fi
	done
```

**Edit H — dynamic viewport separator width.** TWO occurrences in T2's viewport block
(the probe + the in-converge-loop call). Change the trailing `1` arg to `"$sep_w"`:

```bash
# oldText (probe — after `ranked="$(printf '%s\n' "${filtered[@]}")"`):
		lp_viewport "$ranked" "$T0" "$SCROLL" "$cidx" 1
# newText:
		lp_viewport "$ranked" "$T0" "$SCROLL" "$cidx" "$sep_w"
```
```bash
# oldText (inside the converge `while :; do` loop, after vp_T is computed):
				lp_viewport "$ranked" "$vp_T" "$SCROLL" "$cidx" 1
# newText:
				lp_viewport "$ranked" "$vp_T" "$SCROLL" "$cidx" "$sep_w"
```
(The two are distinguished by `$T0` vs `$vp_T`. For plain `sep_w=1` → identical to T2.)

**Edit I — test_appearance.sh: remove stale show-count refs.**

```bash
# oldText (in lp_appearance_seed, the show-count pin line + its neighbor):
	tmux set-option -g @livepicker-highlight-bg   "yellow"
	tmux set-option -g @livepicker-show-count     off
	tmux set-option -g @livepicker-list   "$1"
# newText (drop the show-count line):
	tmux set-option -g @livepicker-highlight-bg   "yellow"
	tmux set-option -g @livepicker-list   "$1"
```
```bash
# oldText (in test_sentinel_resolution_end_to_end, after the tab-style set):
	tmux set-option -g @livepicker-tab-style window-status
	tmux set-option -g @livepicker-show-count off
# newText:
	tmux set-option -g @livepicker-tab-style window-status
```
Also neutralize the 3 stale comment phrases (do NOT touch assertions):
- file header ~line 43: `…pins the colors/type/show-count; each…` → `…pins the colors/type; each…`
- ~line 57: `show-count OFF -> no query suffix -> exact-output assert_eq is safe.` →
  `no count suffix is ever emitted (PRD §19) -> exact-output assert_eq is safe.`
- ~line 102: `(show-count off -> no suffix)` → `(no count suffix per PRD §19)`

**Verification after all edits (copy-paste):**

```bash
cd /home/dustin/.config/tmux/plugins/tmux-livepicker
grep -c 'opt_show_count' scripts/options.sh                          # -> 0
grep -rn 'SHOW_COUNT\|opt_show_count\|show-count' scripts/ tests/    # -> (no matches)
grep -c 'if \[ "$(opt_tab_style)" = "window-status" \]; then' scripts/renderer.sh  # -> 0 (early-return gone)
grep -c 'tab_style' scripts/renderer.sh                             # -> >=3 (decision + loop branch + fallback)
grep -c 'lp_viewport "\$ranked" "\$T0" "\$SCROLL" "\$cidx" "\$sep_w"' scripts/renderer.sh   # -> 1
grep -c 'lp_viewport "\$ranked" "\$vp_T" "\$SCROLL" "\$cidx" "\$sep_w"' scripts/renderer.sh # -> 1
grep -c '__lp_sentinel__' scripts/renderer.sh                       # -> 2 (both swaps preserved)
sed -n '/## All Needed Context/,/## Validation Loop/p' /dev/null    # (placeholder)
```

### Integration Points

```yaml
CODE:
  - file: scripts/renderer.sh
    change: "drop SHOW_COUNT (locals + prefix); DELETE ws early-return; +tab-style decision;
             parameterize tab-build loop (style + $sep); dynamic sep_w in lp_viewport"
    invariant: "ONE §19 engine for both styles; plain byte-identical to T2 (sep= , sep_w=1);
               ws gets query-bar/viewport/indicators; §17 fallback (empty template -> plain);
               count/query> exist nowhere"
  - file: scripts/options.sh
    change: "DELETE opt_show_count()"
  - file: tests/test_appearance.sh
    change: "remove 2 stale @livepicker-show-count off lines + neutralize 3 comment phrases"
    invariant: "all 5 assertions unchanged -> 5/5 pass (query-empty + width=0 = byte-identical)"

CONSUMERS / PRODUCERS:
  - P1.M2.T2.S1 (lands FIRST): PRODUCES the windowed plain path (the engine). SEQUENCE DEP.
  - P1.M3.T1 (client-width): will WRITE STATE_CLIENT_WIDTH -> ACTIVATES ws viewport/indicators
    (today width=0 -> degraded full-list; ws still correct, just not windowed).
  - P1.M4.T1 (test_layout.sh): the §15.28 layout suite (will cover ws query-active/overflow).
  - P4.T1 (README sync): removes the @livepicker-show-count config-table row (line 114).

CONFIG / DATABASE / ROUTES: none.
```

## Validation Loop

### Level 1: Syntax & Style (Immediate Feedback)

```bash
cd /home/dustin/.config/tmux/plugins/tmux-livepicker
bash -n scripts/renderer.sh scripts/options.sh tests/test_appearance.sh && echo "OK: syntax"
shellcheck scripts/renderer.sh scripts/options.sh tests/test_appearance.sh
# SHOW_COUNT is gone everywhere in scripts/ + tests/:
grep -rn 'SHOW_COUNT\|opt_show_count\|show-count' scripts/ tests/   # -> (no matches)
# the ws early-return is gone; tab_style drives the shared engine:
grep -c 'window-status render path (theme-matched tabs)' scripts/renderer.sh  # -> 0
grep -c 'tab_style' scripts/renderer.sh                                        # -> >=3
# both __lp_tab__ AND __lp_sentinel__ swaps preserved (Issue 5):
grep -c '__lp_sentinel__' scripts/renderer.sh                                  # -> 2
# the two lp_viewport calls pass sep_w (not 1):
grep -c 'lp_viewport "\$ranked" "\$T0" "\$SCROLL" "\$cidx" "\$sep_w"' scripts/renderer.sh    # -> 1
grep -c 'lp_viewport "\$ranked" "\$vp_T" "\$SCROLL" "\$cidx" "\$sep_w"' scripts/renderer.sh  # -> 1
# §17 fallback present:
grep -c 'tab_style="plain"' scripts/renderer.sh                                # -> >=1
# test_appearance.sh has no show-count refs but its assertions intact:
grep -c 'show-count' tests/test_appearance.sh                                  # -> 0
grep -c 'assert_eq\|assert_contains' tests/test_appearance.sh                  # -> (unchanged count)
# Tabs-not-spaces in the new regions:
grep -nP '^ +[^#/]' scripts/renderer.sh | tail && echo "WARN: space-indent" || echo "OK: tabs"
# Expected: syntax clean; shellcheck 0 new findings; all grep counts as shown.
```

### Level 2: Full suite (no regression — the load-bearing gate)

```bash
cd /home/dustin/.config/tmux/plugins/tmux-livepicker
tests/run.sh
# Expected: exit 0, ALL green. RATIONALE (research FINDING 7): test_appearance.sh's 5 ws
# tests use query-EMPTY + NO @livepicker-client-width -> width=0 -> T2's degraded full-list
# render -> the new shared engine emits byte-identical output to the old ws path (ws swap +
# separator join; no query bar / no indicators). The 2 stale show-count lines were no-ops
# already (now removed). test_functional/test_responsiveness have no show-count refs (T1
# cleaned them). If a test FAILS, check that: (a) the ws tab-swap still emits BOTH
# __lp_tab__ and __lp_sentinel__; (b) plain mode still joins with " " (sep=" "); (c) the
# §17 fallback flips tab_style=plain on an empty template.
```

### Level 3: Throwaway ws §19 smoke (prove ws now obeys §19; then DELETE)

```bash
cat > /tmp/smoke_ws19.sh <<'SMOKE'
#!/usr/bin/env bash
set -u
cd /home/dustin/.config/tmux/plugins/tmux-livepicker
source tests/setup_socket.sh; source tests/helpers.sh
pass_n=0; fail_n=0
has()  { if [[ "$2" == *"$1"* ]]; then pass_n=$((pass_n+1)); else fail_n=$((fail_n+1)); echo "FAIL: [$1] absent in [$2]"; fi; }
nohas(){ if [[ "$2" != *"$1"* ]]; then pass_n=$((pass_n+1)); else fail_n=$((fail_n+1)); echo "FAIL: [$1] present (should be absent)"; fi; }

# --- (1) ws query-EMPTY + width=0: byte-identical to the old ws path (regression) ---
setup_test "lp-ws19-empty"
tmux set-option -g @livepicker-fg default; tmux set-option -g @livepicker-bg default
tmux set-option -g @livepicker-highlight-fg black; tmux set-option -g @livepicker-highlight-bg yellow
tmux set-option -g @livepicker-list $'alpha\nbeta\ngamma'
tmux set-option -g @livepicker-filter ''
tmux set-option -g @livepicker-index 1
tmux set-option -g @livepicker-tab-style window-status
tmux set-option -gw window-status-separator '|'
tmux set-option -g @livepicker-tab-current-tmpl  "#[fg=cyan,bold]__lp_tab__#[default]"
tmux set-option -g @livepicker-tab-inactive-tmpl "#[fg=gray]__lp_tab__#[default]"
out="$(bash scripts/renderer.sh)"
# exact: alpha(gray) | beta(cyan) | gamma(gray)
[ "$out" = "#[fg=gray]alpha#[default]|#[fg=cyan,bold]beta#[default]|#[fg=gray]gamma#[default]" ] && pass_n=$((pass_n+1)) || { fail_n=$((fail_n+1)); echo "FAIL ws-empty exact: [$out]"; }
teardown_test

# --- (2) ws query-ACTIVE: now shows <icon>?<query><gap><tabs> (NEW — was bypassed) ---
setup_test "lp-ws19-active"
tmux set-option -g @livepicker-fg default; tmux set-option -g @livepicker-bg default
tmux set-option -g @livepicker-highlight-fg black; tmux set-option -g @livepicker-highlight-bg yellow
tmux set-option -g @livepicker-list $'alpha\nbeta\ngamma'
tmux set-option -g @livepicker-filter 'b'
tmux set-option -g @livepicker-index 0      # beta is the only match -> index 0
tmux set-option -g @livepicker-tab-style window-status
tmux set-option -gw window-status-separator '|'
tmux set-option -g @livepicker-tab-current-tmpl  "#[fg=cyan,bold]__lp_tab__#[default]"
tmux set-option -g @livepicker-tab-inactive-tmpl "#[fg=gray]__lp_tab__#[default]"
tmux set-option -g @livepicker-nerd-fonts off
tmux set-option -g @livepicker-query-gap 2
tmux set-option -gu @livepicker-client-width    # width=0 -> full-list (beta only match)
out="$(bash scripts/renderer.sh)"
has "beta" "$out"            # the query filters to beta; it renders via the CURRENT template
has "#[fg=cyan,bold]beta#[default]" "$out"   # ws current styling applied
nohas "alpha" "$out"         # filtered out
# query-active prefix present: "b" + gap(2 spaces) before the tabs
[[ "$out" == *"b  "* ]] && pass_n=$((pass_n+1)) || { fail_n=$((fail_n+1)); echo "FAIL: no query+gap prefix in [$out]"; }
teardown_test

# --- (3) ws §17 fallback: empty current template -> plain styling ---
setup_test "lp-ws19-fallback"
tmux set-option -g @livepicker-fg default; tmux set-option -g @livepicker-bg default
tmux set-option -g @livepicker-highlight-fg black; tmux set-option -g @livepicker-highlight-bg yellow
tmux set-option -g @livepicker-list $'alpha\nbeta'
tmux set-option -g @livepicker-filter ''
tmux set-option -g @livepicker-index 1
tmux set-option -g @livepicker-tab-style window-status
tmux set-option -g @livepicker-tab-current-tmpl  ""       # EMPTY -> fallback
tmux set-option -g @livepicker-tab-inactive-tmpl "#[fg=gray]__lp_tab__#[default]"
out="$(bash scripts/renderer.sh)"
has "#[fg=black,bg=yellow]beta#[default]" "$out"   # plain highlight
nohas "#[fg=gray]" "$out"                           # ws template did NOT leak
teardown_test

echo "pass=$pass_n fail=$fail_n"; [ "$fail_n" -eq 0 ]
SMOKE
bash /tmp/smoke_ws19.sh; rc=$?; rm -f /tmp/smoke_ws19.sh; exit $rc
# Expected: all pass. (1) ws query-empty = exact old output (regression-safe); (2) ws
# query-active now shows the query+gap prefix + ws-styled tabs (the §19 fold WORKS);
# (3) empty template -> plain fallback. (Committed ws-layout tests are P1.M4.T1.)
```

### Level 4: Wide-separator windowing spot-check (optional; proves sep_w correctness)

```bash
cd /home/dustin/.config/tmux/plugins/tmux-livepicker
source tests/setup_socket.sh; source tests/helpers.sh
setup_test "lp-ws19-sepw"
tmux set-option -g @livepicker-fg default; tmux set-option -g @livepicker-bg default
tmux set-option -g @livepicker-highlight-fg black; tmux set-option -g @livepicker-highlight-bg yellow
tmux set-option -g @livepicker-list "$(printf 'aaaaa\nbbbbb\nccccc\nddddd\neeeee')"
tmux set-option -g @livepicker-filter ''
tmux set-option -g @livepicker-index 0
tmux set-option -g @livepicker-scroll 0
tmux set-option -g @livepicker-client-width 30         # narrow -> overflow
tmux set-option -g @livepicker-tab-style window-status
tmux set-option -gw window-status-separator ' | '      # WIDTH 3 (sep_w=3, not 1)
tmux set-option -g @livepicker-tab-current-tmpl  "__lp_tab__"
tmux set-option -g @livepicker-tab-inactive-tmpl "__lp_tab__"
out="$(bash scripts/renderer.sh)"
# expect overflow indicator +N> (tabs hidden because the 3-wide separator eats width)
[[ "$out" =~ \+[0-9]+\> ]] && pass || echo "NOTE: if no +N>, the windowing may be ignoring sep_w"
teardown_test
# Expected: a +N> indicator appears. If windowing used 1 instead of sep_w=3, MORE tabs would
# (incorrectly) appear to fit and the indicator might be absent or under-count. (Visual;
# asserts the sep_w path is exercised with a multi-char separator.)
```

## Final Validation Checklist

### Technical Validation
- [ ] `bash -n` + `shellcheck` clean on renderer.sh, options.sh, test_appearance.sh.
- [ ] `grep -rn 'SHOW_COUNT\|opt_show_count\|show-count' scripts/ tests/` → no matches.
- [ ] `opt_show_count` deleted from options.sh; renderer first locals + prefix carry no SHOW_COUNT.
- [ ] ws early-return block deleted; `tab_style` decision present; tab-build loop branches on style.
- [ ] Both `lp_viewport` calls pass `"$sep_w"`; both `__lp_tab__`+`__lp_sentinel__` swaps present.
- [ ] §17 fallback (`tab_style=plain` on empty template) present.

### Feature Validation
- [ ] ws query-empty + width=0 → byte-identical to the old ws output (test_appearance.sh a/b/c/e).
- [ ] ws query-active → `<icon><query><gap><ws-styled tabs>` (the §19 fold; L3 smoke case 2).
- [ ] ws no-match → shared `<icon><query> (no match)`.
- [ ] plain mode → byte-identical to T2 (sep=" ", sep_w=1).
- [ ] §17 fallback → plain styling when either template is empty (L3 smoke case 3).
- [ ] `count`/`[i/N]`/`query>` exist NOWHERE in renderer output.

### Code Quality Validation
- [ ] ONE §19 layout engine (no duplicated query-bar/viewport/indicator logic).
- [ ] The two styles differ ONLY at the per-tab render + the `$sep` join.
- [ ] Dynamic `sep_w` for ws (multi-char separator windowing); plain unchanged.
- [ ] `printf '%s' "..."` quoted everywhere; TABS; renderer stays PURE (no state writes).
- [ ] test_appearance.sh assertions UNCHANGED (only stale show-count refs removed).

### Documentation & Deployment
- [ ] No README/CHANGELOG edit here (renderer output is internal; the @livepicker-show-count
      config-table row removal is P4.T1 — NOTE it for P4).
- [ ] Inline comments cross-reference PRD §17/§19 + the §17 Fallback + the sep_w rule.

---

## Anti-Patterns to Avoid

- ❌ Don't run before T2 lands — Edits F/G/H's oldText is T2's output. If T2 isn't in, STOP.
  (research FINDING 9; this task is sequenced on T2, not parallel-safe on renderer.sh.)
- ❌ Don't DUPLICATE the layout logic for ws — fold it into the ONE engine (style conditional
  in the tab-build loop + `$sep` join). The query-bar/viewport/indicator/branch code is shared.
  (contract; FINDING 2.)
- ❌ Don't leave the viewport separator-width hardcoded at `1`. ws uses window-status-separator
  (can be multi-char). Pass `"$sep_w"` (= lp_disp_width "$sep"). Forgetting this mis-windows
  ws tabs under a wide separator. (FINDING 4.)
- ❌ Don't drop the `__lp_sentinel__` swap — the cached template may contain it (#S/
   #{session_name} themes, Issue 5). Keep BOTH `__lp_tab__` and `__lp_sentinel__` swaps.
- ❌ Don't theme-style the chrome (query bar / no-match / indicators) in ws mode — they use
  FG/BG for both styles (under-specified otherwise; FINDING 5). Reuse T2's chrome verbatim.
- ❌ Don't change the no-match branch, the viewport algorithm, the indicator styling/placement,
  or the query-empty/query-active branch logic. Those are SHARED and unchanged.
- ❌ Don't touch the test_appearance.sh ASSERTIONS — they still hold (query-empty + width=0 =
  byte-identical). Only remove the 2 stale `@livepicker-show-count off` lines + comment phrases.
- ❌ Don't edit README.md (the show-count config-table row is P4.T1's job). NOTE it for P4.
- ❌ Don't break the §17 Fallback — empty `cur_tpl` OR `reg_tpl` must flip `tab_style=plain`
  (test_empty_template_falls_back_to_plain asserts it).
- ❌ Don't re-add SHOW_COUNT anywhere. After Edits A/B/C/D/I it exists NOWHERE in scripts/+tests/.
- ❌ Don't forget `set -u` — declare `tab_style cur_tpl reg_tpl sep sep_w` on the extended
  locals line (Edit G) before Edit E assigns them.
- ❌ Don't use spaces for indent — TABS only (the file is tab-indented; a space edit won't match).

---

## Confidence Score

**8 / 10** for one-pass success. Rationale: the shared-engine design is clean (the two styles
plug in at exactly two seams — per-tab render + `$sep` join — FINDING 2), the §17 tab-swap +
separator + fallback logic is RELOCATED from the deleted ws block (not invented), and every
T2-touched oldText is quoted verbatim from T2's PRP. The critical correctness detail (dynamic
`sep_w` for ws — FINDING 4) is explicit, and the backward-compat proof (test_appearance.sh
5/5 stay green because they're query-empty + width=0 — FINDING 7) is verified by tracing each
test. SHOW_COUNT removal is grep-scoped and complete (FINDING 8). Residual risks: (1) the large
ws-block deletion (Edit D) — a tab/whitespace mismatch could fail the match (mitigated: unique
start/end anchors + the block is contiguous); (2) anchoring on T2's exact output — if T2's
final phrasing drifted from its PRP, Edits F/G/H won't match (mitigated: the implementer runs
after T2 and can re-quote the live text); (3) the dynamic `sep_w` only matters for ws with a
multi-char separator (an uncommon config) — covered by the L4 spot-check. All residuals are
caught by the validation loop (L1 grep + L2 suite-green + L3/L4 smokes). The 2-point deduction
reflects the dependency on the in-flight T2 (anchoring risk) + the breadth of the refactor
(3 files, 9 edits, one large deletion). No logic is unverified.
