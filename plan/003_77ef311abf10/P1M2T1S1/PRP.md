# PRP — P1.M2.T1.S1: Restructure render() plain path into §19 layout; drop plain SHOW_COUNT branch

> **Scope**: Rework the **plain render path** of `scripts/renderer.sh::render()` into
> the PRD §19 status-line layout (3 branches: query-empty / query-active / no-match),
> drop the `SHOW_COUNT` (`query> FILTER [i/N]`) suffix from the plain path, and update
> the 3 existing renderer-test assertions that encoded the old plain output. The
> **window-status (§17) early-return path is LEFT UNTOUCHED** (P1.M2.T3 reworks it,
> including removing SHOW_COUNT entirely). This is the layout restructure only — full
> viewport windowing + overflow indicators land in P1.M2.T2.

---

## Goal

**Feature Goal**: The plain render path emits the §19 layout: (a) query EMPTY → only the
ranked session tabs, positioned per `status-justify` (emulated by the renderer); (b) query
ACTIVE → `<icon><query><gap><tabs>` pinned at column 0 (`status-justify` suspended); (c)
no-match → `<icon><query> (no match)`. The highlight is `STATE_INDEX`. The `[i/N]` count
and the `query>` prefix are GONE from the plain path. The window-status path is unchanged.

**Deliverable**: Edits to `scripts/renderer.sh` (source `layout.sh`; extend locals;
replace the plain-path body) + 2 test-assertion updates (`tests/test_functional.sh`,
`tests/test_responsiveness.sh`). **No new files.**

**Success Definition**:
- Query-empty: renderer stdout = the tabs only (highlighted index styled), no icon/query/
  gap/count; positioned per status-justify when `STATE_CLIENT_WIDTH` is set (left when unset).
- Query-active: stdout = `<icon><query><gap><tabs>` at column 0; no `query>` prefix, no count.
- No-match: stdout = `<icon><query> (no match)`.
- The `query> FILTER [i/N]` text appears NOWHERE in the plain path (grep-confirmed).
- The window-status path is byte-identical (its SHOW_COUNT usage intact).
- The 3 updated test assertions PASS; `tests/run.sh` green (no other test regresses).

## User Persona (if applicable)

**Target User**: The end user (via the status line) + the §15.28 layout tests (P1.M4.T1).
Not developer-facing.

**Use Case**: The user opens the picker (query empty) → sees only the session tabs, centered
like their normal window tabs. They type `log` → the `🔍 log  syslog blog …` query bar
appears at column 0, tabs flow left. No matches → `🔍 logzz (no match)`. The count is gone
(per §19 — it was noise).

**Pain Points Addressed**: The old plain path appended `query> FILTER [i/N]` at the line end
— inconsistent with §17 window-tabs and noisy. §19 makes the picker line look like native
window tabs (query-empty) / a clean pinned query bar (query-active). PRD §19 is the single
source of truth for line 1; this task implements it for the plain path.

## Why

- **§19 is the new source of truth for line 1.** The old "query and count at line end" is
  replaced (PRD §19: "It replaces the earlier 'query and count shown at the line end'
  behavior. The `index/total` count indicator is removed entirely."). This task implements
  that for the plain path.
- **Interaction-first (§18).** The renderer is the hot path (runs every keystroke). The §19
  plain path stays PURE+FAST (option reads + pure-bash measure only; one status-justify read;
  width from the cached `STATE_CLIENT_WIDTH`, NEVER `display-message`). No per-tab tmux round-trip.
- **Foundation for P1.M2.T2 (windowing) + P1.M2.T3 (ws path).** This task establishes the 3-branch
  structure + reads STATE_SCROLL/STATE_CLIENT_WIDTH (the seams P1.M2.T2 slices by and P1.M3.T1
  captures). P1.M2.T3 mirrors this restructure onto the ws path then removes SHOW_COUNT entirely.
- **Disjoint from the parallel P1.M1.T3.S2** (state.sh-only; constants already present).

## What

1. **Header**: `source "$CURRENT_DIR/layout.sh"` (for `lp_disp_width`).
2. **Locals**: extend the plain-path `local` line with `SCROLL icon gap tabs justify width pad padw tabs_w`.
3. **Plain-path body** (replace wholesale): read LIST/FILTER/IDX/SCROLL; `mapfile` all/filtered via `lp_rank`; compute icon + gap; **branch**:
   - no-match (`FLEN==0`) → `<icon><query> (no match)`.
   - clamp `cidx`; build `tabs` (ranked, `#`-escaped, styled, space-joined, highlighted IDX).
   - query-empty (`-z FILTER`) → emulate status-justify (leading padding) + `tabs`.
   - query-active (`-n FILTER`) → `<icon><query><gap><tabs>` (pinned left).
4. **KEEP** `SHOW_COUNT_RAW`/`SHOW_COUNT` computation (ws path uses it); **REMOVE** its plain-path use.
5. **Tests**: update `test_functional.sh:332` (`"query> ##dev"`→`"##dev"`), `:337` (`"query> ##zz"`→`"##zz"`); `test_responsiveness.sh:94` (`"query> a"`→ assert the search icon U+F002 present, proving query-active fired).

### Success Criteria

- [ ] `source "$CURRENT_DIR/layout.sh"` added after the rank.sh source.
- [ ] Plain path has 3 branches (empty / active / no-match) keyed on FILTER emptiness + FLEN.
- [ ] No `query>`, no `[i/N]`, no `SHOW_COUNT` *use* in the plain path (grep: 0 matches for `query>`/`\[[0-9]/` outside the ws block).
- [ ] Query-empty emulates status-justify (reads `status-justify` once + `STATE_CLIENT_WIDTH`; pads centre/right; left when width=0).
- [ ] Query-active emits `<icon><query><gap><tabs>` (icon iff `opt_nerd_fonts=on`; query `#`-doubled; gap = `opt_query_gap` plain spaces).
- [ ] STATE_SCROLL read (unused — windowing is P1.M2.T2; SC2034 file-wide disabled).
- [ ] Window-status path byte-identical (diff confined to the plain path + header + locals).
- [ ] 3 test assertions updated; `tests/run.sh` green.

## All Needed Context

### Context Completeness Check

_Pass_: The implementer needs (a) the verbatim edits (below), (b) the §19 layout rules, (c)
the status-justify-emulation decision + its residual visual-verify, (d) the 3 test updates.
Every behavior is anchored to the current working tree + §P6 + §19.

### Documentation & References

```yaml
# MUST READ — the empirical ground-truth for THIS task (8 findings)
- docfile: plan/003_77ef311abf10/P1M2T1S1/research/renderer_plain_section19_findings.md
  why: FINDING 1 (plain path = below the ws early-return fi; shared SHOW_COUNT prefix STAYS);
       FINDING 2 (deps present: lp_rank empty-filter=original order; lp_disp_width; ADD source
       layout.sh; opt_search_icon=$'\uf002'; STATE_CLIENT_WIDTH unwritten today -> width=0);
       FINDING 3 (the 3 branches + icon/query/gap/tabs/styling decisions); FINDING 4 (status-
       justify EMULATED via padding, branch (a) only; suspended in (b)/(c); degrade to left when
       width=0; RESIDUAL visual-verify the centre case); FINDING 5 (KEEP SHOW_COUNT compute,
       remove plain-path USE); FINDING 6 (READ SCROLL, don't slice — P1.M2.T2; SC2034 disabled);
       FINDING 7 (the 3 test assertions to update, with exact old→new); FINDING 8 (no conflict
       with parallel P1.M1.T3.S2).
  critical: FINDING 4 (the emulation decision) + FINDING 7 (the test updates) are the two
            things most likely to be gotten wrong. Read BEFORE editing.

# MUST READ — the renderer load-bearing rules (§P6)
- docfile: plan/003_77ef311abf10/architecture/codebase_patterns.md
  why: §P6 — ONE line no trailing newline (`printf '%s' "$out"` QUOTED); #[default] after every
       segment; process-substitution list read; NO set -e; render||fallback-red; #() stdout NOT
       re-parsed for #{} (=> query doubles #); PURE+FAST (option reads + pure-bash ONLY; one
       status-justify/separator read is allowed — "not per-tab"; width from cached STATE_CLIENT_WIDTH).
  section: "P6 — Renderer rules (renderer.sh)"

# MUST READ — PRD §19 (the layout spec this implements)
- docfile: PRD.md
  why: §19 §3.29 (two independent visibility rules: query-bar only while query non-empty;
       overflow only when tab region overflows); §3.30 (query-empty: only tabs, positioned per
       status-justify); §3.31 (query-active: <icon><query><gap><tabs>; status-justify SUSPENDED;
       icon=@livepicker-search-icon iff nerd-fonts on; query # doubled; gap=@livepicker-query-gap
       spaces; tabs joined by single space in plain mode); §3.34 (no-match: <icon><query> +
       " (no match)" plain ASCII); §3.35 (width from @livepicker-client-width, no per-keystroke
       tmux round-trip). §18 (the renderer is the hot path; must stay cheap).
  section: "§19 Status-line layout" (§3.29/§3.30/§3.31/§3.34/§3.35)

# MUST READ — the file being modified (the plain path + the ws path boundary)
- file: scripts/renderer.sh
  why: render() (206 lines). The ws early-return (lines ~46-135, inside `if opt_tab_style ==
        window-status ... fi`) is LEFT UNTOUCHED. The plain path (lines ~137-206) is REPLACED.
        The shared option-read prefix (TYPE/FG/BG/HFG/HBG/SHOW_COUNT_RAW + case->SHOW_COUNT, top
        of render()) STAYS — the ws path still uses SHOW_COUNT. The header (source options/utils/
        state/rank) gets layout.sh added. The `local out seg i cidx first esc_filter esc_name` line
        is extended. The driver (`render || printf ...; exit 0`) is unchanged.
  pattern: the existing seq/escape idioms to reuse: `${FILTER//\#/##}`, `mapfile -t filtered < <(lp_rank ...)`,
           `#[fg=$HFG,bg=$HBG]name#[default]` per tab, `printf '%s' "$out"` (QUOTED).
  gotcha: the contract's `printf '%s' $out` (unquoted) is a TYPO — always quote ("$out"); an
          unquoted printf word-splits on whitespace (would shred the styled line). §P6 says quoted.

# MUST READ — lp_rank (the ranker) + lp_disp_width (the measure)
- file: scripts/rank.sh
  why: lp_rank LIST FILTER — subsequence ranker. Empty FILTER -> ALL names ORIGINAL order (byte-
        identical to the old behavior -> query-empty tests stay green). mapfile -t filtered < <(lp_rank "$LIST" "$FILTER").
- file: scripts/layout.sh
  why: lp_disp_width STRING — strips #[...] styles, counts codepoints via ${#var} (NOT wc -m —
        locale-dependent). Used to measure the tabs' display width for status-justify emulation.
        layout.sh is NOT yet sourced by renderer.sh -> ADD it. NO source-time side effects.

# MUST READ — the option accessors (P1.M1.T3.S1, landed) + state keys (P1.M1.T3.S2, landed)
- file: scripts/options.sh
  why: opt_nerd_fonts (default "on"), opt_search_icon (default $'\uf002' = bytes ef 80 82),
        opt_query_gap (default "2"). opt_fg/bg/highlight_fg/highlight_bg/show_count (existing).
- file: scripts/state.sh
  why: STATE_LIST/FILTER/INDEX/SCROLL/CLIENT_WIDTH (all get_state). STATE_CLIENT_WIDTH is NOT yet
        written by anyone (P1.M3.T1 captures it) -> get_state returns "0" today -> emulate degrades
        to left. SCROLL is not yet written either (P1.M3.T2) -> get_state returns "0".

# MUST READ — the tests being updated (the 3 plain-output assertions)
- file: tests/test_functional.sh
  why: test_renderer_escapes_hash_in_filter (lines 332/337) asserts the old `query> ##...` form;
        §19 drops the `query>` prefix. test_renderer_escapes_hash_in_names (filter="") NEEDS NO
        change (query-empty still shows escaped tabs). test_typing_filters NEEDS NO change (no
        query>/count assertion).
- file: tests/test_responsiveness.sh
  why: line 94 asserts `query> a`; §19 drops the prefix. The load-bearing deferral proof is the
        SEQ bump on the prior line; the renderer assertion just confirms the query took effect.
        Assert the search icon (U+F002) present (it only renders in query-active/no-match).

# Reference — PRD §18 (the renderer is the hot path; must stay <50ms)
- docfile: PRD.md
  section: "§18 Responsiveness" (contract #1: the #() renderer is cheap — option reads only)
```

### Current Codebase tree

```bash
tmux-livepicker/
  scripts/
    renderer.sh   # MODIFY: +source layout.sh; +locals; REPLACE plain-path body (3 §19 branches; drop SHOW_COUNT use)
    rank.sh       # (COMPLETE) lp_rank — consumed
    layout.sh     # (COMPLETE) lp_disp_width — NEWLY sourced by renderer
    options.sh    # (COMPLETE) opt_search_icon/opt_nerd_fonts/opt_query_gap — consumed
    state.sh      # (COMPLETE, P1.M1.T3.S2) STATE_SCROLL/STATE_CLIENT_WIDTH — consumed
    ... (utils/livepicker/input-handler/preview/restore)  # UNCHANGED
    # NOTE: P1.M1.T3.S2 (parallel) is state.sh-only — DISJOINT.
  tests/
    test_functional.sh        # MODIFY: 2 assertions (lines 332, 337)
    test_responsiveness.sh    # MODIFY: 1 assertion (line 94)
    run.sh / helpers.sh / setup_socket.sh / (others)  # UNCHANGED
```

### Desired Codebase tree with files to be added and responsibility of file

```bash
scripts/renderer.sh        # plain path -> §19 (query-empty/active/no-match); SHOW_COUNT use dropped from plain path;
                           #   ws path untouched. +source layout.sh. The user-visible picker line (plain mode).
tests/test_functional.sh   # 2 assertions updated (drop obsolete `query> ` prefix).
tests/test_responsiveness.sh  # 1 assertion updated (icon-presence proves query-active).
```

### Known Gotchas of our codebase & Library Quirks

```bash
# CRITICAL — QUOTE the printf: `printf '%s' "$out"` (or "${pad}${tabs}" etc). The contract's
# `printf '%s' $out` (unquoted) is a TYPO — unquoted, printf word-splits the styled line on
# whitespace, shredding it. §P6 mandates the quoted form. Every emit must be `printf '%s' "..."`.

# CRITICAL — status-justify is EMULATED by the renderer (not auto-applied by tmux to #() output).
# §P6 + §19 §3.31 (status-justify is SUSPENDED while query active — only possible if the renderer
# controls padding). Emulate in branch (a) only (leading padding spaces); branches (b)/(c) emit
# at column 0 (the "suspend"). Degrade to left when STATE_CLIENT_WIDTH is unset (P1.M3.T1 not
# landed -> get_state returns "0" -> width=0 -> no pad). RESIDUAL: visually verify the empty-query
# centre case (Level 4); if double-justified, drop the emulation (documented fallback). (FINDING 4.)

# CRITICAL — KEEP the SHOW_COUNT computation (SHOW_COUNT_RAW + the case->SHOW_COUNT block at the
# top of render()). The ws path STILL uses SHOW_COUNT (its no-match + [i/N] suffix). P1.M2.T3
# removes SHOW_COUNT entirely (after reworking the ws path). Removing it HERE would break the ws
# path. Only remove the plain-path USE of SHOW_COUNT (the no-match `0/$TOTAL` line + the trailing
# `[i/N]` suffix). (FINDING 5.)

# CRITICAL — branch on FILTER emptiness for (a) vs (b); branch on FLEN==0 for (c). Order the
# no-match check (c) BEFORE the cidx clamp (cidx is meaningless when FLEN==0; the old code did
# this). Then build tabs (shared by a/b), THEN branch on -z/-n FILTER.

# CRITICAL — the icon is `$icon` (empty string when opt_nerd_fonts != "on"). Embed it INSIDE the
# styled segment for the query bar: `#[fg=$FG,bg=$BG]${icon}${esc_filter}#[default]`. The gap is
# PLAIN (unstyled) spaces emitted AFTER the #[default] reset (so the gap is not a colored bar):
# `...#[default]${gap}${tabs}`. For no-match: `#[fg=$FG,bg=$BG]${icon}${esc_filter} (no match)#[default]`.

# CRITICAL — the query text MUST double every #: esc_filter="${FILTER//\#/##}" (read at the top
# of the plain path, reused). #() stdout is NOT re-parsed for #{...} (§P6) — an unescaped # would
# be a stray tmux directive. The ws path already does this (esc_wfilter); mirror it.

# GOTCHA — `printf '%*s' "$n" ''` builds a string of $n spaces (the gap; and the justify padding).
# Validate n is a non-negative integer (opt_query_gap defaults "2"; opt_search_icon is a glyph).
# If opt_query_gap is garbage, `printf '%*s'` errors — guard with a regex or default. (opt_query_gap
# is a user option; default "2"; treat non-numeric as 0 via a `[[ =~ ]]` guard.)

# GOTCHA — lp_disp_width "$tabs" strips #[...] styles and counts codepoints. $tabs contains
# multiple `#[fg=...]name#[default]` segments joined by spaces; lp_disp_width returns the correct
# visible width (names + joining spaces). Used ONLY in the justify emulation (branch a).

# GOTCHA — READ STATE_SCROLL but do NOT slice filtered[] by it. Windowing/overflow is P1.M2.T2.
# SC2034 (unused local) is FILE-WIDE disabled in renderer.sh (header) -> the unread SCROLL raises
# NO warning. Add a comment: "# read; viewport slicing lands in P1.M2.T2".

# GOTCHA — NO `set -e` (renderer has none; keep the `|| true`/`2>/dev/null` on tmux reads).
# `set -u` inherited — every new local is defaulted before use (SCROLL/width get "...", "0"; icon/
# gap/pad/tabs assigned before the branch that reads them).

# GOTCHA — indent with TABS (whole codebase; shfmt absent). The plain-path body is 1-tab inside
# render(); nested case/if bodies at 2-3 tabs. The edit's oldText/newText must use TABS (the file
# is tab-indented — a space-indented edit won't match).

# GOTCHA — do NOT touch the ws path (the `if [ "$(opt_tab_style)" = "window-status" ]; then ... fi`
# block). It still emits `query> ...` + SHOW_COUNT — that's correct FOR NOW (P1.M2.T3 reworks it).
# The grep cross-check for "no query> in the plain path" must EXCLUDE the ws block (use awk range
# or grep -n + eyeball the line numbers are above ~135).
```

## Implementation Blueprint

### Data models and structure

No data model. The "structure" is the 3-branch §19 flow:

```
render() [shared option reads incl. SHOW_COUNT]
 [ws early-return: UNTOUCHED]
 ── plain path (PRD §19) ──
 read LIST/FILTER/IDX/SCROLL; esc_filter = FILTER with # -> ##
 mapfile all/filtered(lp_rank); FLEN
 icon = opt_search_icon iff opt_nerd_fonts=on else ""
 gap  = opt_query_gap spaces
 (c) if FLEN==0: printf "<#[fg=$FG,bg=$BG]><icon><esc_filter> (no match)<#[default]>"; return
 clamp cidx
 build tabs (ranked, # escaped, styled, space-joined, highlight cidx)
 (a) if FILTER=="": emulate status-justify (pad) ; printf "<pad><tabs>"; return
 (b) else        : printf "<#[fg=$FG,bg=$BG]><icon><esc_filter>#[default]><gap><tabs>"
```

### Implementation Tasks (ordered by dependencies)

```yaml
Task 1: MODIFY scripts/renderer.sh — SOURCE layout.sh
  - LOCATE the header source block; the rank.sh source (2 lines: `# shellcheck source=rank.sh`
    + `source "$CURRENT_DIR/rank.sh"`).
  - APPEND the layout.sh source immediately after it:
        # shellcheck source=layout.sh
        source "$CURRENT_DIR/layout.sh"
  - DO NOT reorder the existing sources (options -> utils -> state -> rank -> layout; state
    needs utils first; layout is last — it depends on nothing sourced here).

Task 2: MODIFY scripts/renderer.sh — EXTEND the plain-path locals
  - LOCATE: `local out seg i cidx first esc_filter esc_name` (the plain-path local declaration).
  - APPEND the new locals: SCROLL icon gap tabs justify width pad padw tabs_w.
  - newText: `local out seg i cidx first esc_filter esc_name SCROLL icon gap tabs justify width pad padw tabs_w`
  - (out stays declared though now unused in the plain path — SC2034 is file-wide disabled; harmless.)

Task 3: MODIFY scripts/renderer.sh — REPLACE the plain-path body (LIST= ... final printf)
  - LOCATE the plain path: from `LIST="$(get_state "$STATE_LIST" "")"` (immediately after the ws
    block's closing `fi`) through the trailing `printf '%s' "$out"` (just before render()'s
    closing `}`). This is the WHOLE plain path.
  - REPLACE with the verbatim §19 body from Implementation Patterns (3 branches; no SHOW_COUNT use).
  - PRESERVE: the closing `}` of render() and the `render || printf ...; exit 0` driver (unchanged).
  - PRESERVE: the ws early-return block above (byte-identical).

Task 4: MODIFY tests/test_functional.sh — UPDATE the 2 hash-escape-in-filter assertions
  - Line 332: `assert_contains "$out" "query> ##dev"` -> `assert_contains "$out" "##dev"` (match
    branch; §19 drops `query>`; ##dev appears in query+tab). Update the message.
  - Line 337: `assert_contains "$out" "query> ##zz"` -> `assert_contains "$out" "##zz"` (no-match
    branch; query escape proven — no tabs). Update the message.
  - Line 339 (`(no match)`) UNCHANGED. test_renderer_escapes_hash_in_names + test_typing_filters UNCHANGED.

Task 5: MODIFY tests/test_responsiveness.sh — UPDATE the type-reflects-query assertion (line 94)
  - Pin `@livepicker-nerd-fonts on` before the renderer call (default, but pin for robustness).
  - Replace `assert_contains "$(... renderer.sh)" "query> a"` with an icon-presence check: the
    search glyph U+F002 ONLY renders in query-active/no-match -> its presence proves the typed `a`
    made the query non-empty. Form (see Patterns): `case "$out" in *$'\uf002'*) pass...;; *) fail...;; esac`.
  - The SEQ-bump assertion on the prior line is the load-bearing deferral proof (unchanged).

Task 6: VALIDATE (L1 grep + L2 full suite + L4 visual justify spot-check)
  - RUN: bash -n scripts/renderer.sh ; shellcheck scripts/renderer.sh tests/test_functional.sh tests/test_responsiveness.sh
  - RUN: grep cross-checks (no `query>`/`[i/N]`/SHOW_COUNT use in the PLAIN path; ws path intact).
  - RUN: tests/run.sh (expect green; the 3 updated assertions PASS; no other test regresses).
  - RUN: L4 visual spot-check of the empty-query status-justify=centre case (residual verify, FINDING 4).
```

### Implementation Patterns & Key Details

**Task 1 — source layout.sh (append after the rank.sh source):**

```bash
# oldText:
# shellcheck source=rank.sh
source "$CURRENT_DIR/rank.sh"

# newText:
# shellcheck source=rank.sh
source "$CURRENT_DIR/rank.sh"
# shellcheck source=layout.sh
source "$CURRENT_DIR/layout.sh"
```

**Task 2 — extend the locals:**

```bash
# oldText:
	local out seg i cidx first esc_filter esc_name
# newText:
	local out seg i cidx first esc_filter esc_name SCROLL icon gap tabs justify width pad padw tabs_w
```

**Task 3 — the new plain-path body (REPLACE from `LIST=` through the final `printf '%s' "$out"`).**
The `oldText` is the entire current plain path (the `LIST=…` … `printf '%s' "$out"` block). The
`newText` is the §19 body:

```bash
# newText (the complete §19 plain path — paste verbatim; TAB-indented):
	LIST="$(get_state "$STATE_LIST" "")"
	FILTER="$(get_state "$STATE_FILTER" "")"
	esc_filter="${FILTER//\#/##}"   # display escape: every # -> ## (tmux literal-#; §P6)
	IDX="$(get_state "$STATE_INDEX" "0")"
	SCROLL="$(get_state "$STATE_SCROLL" "0")"   # read; viewport slicing lands in P1.M2.T2

	mapfile -t all < <(printf '%s' "$LIST")
	TOTAL="${#all[@]}"
	mapfile -t filtered < <(lp_rank "$LIST" "$FILTER")
	FLEN="${#filtered[@]}"

	# icon: the search glyph (U+F002) iff nerd-fonts on; else empty (raw UTF-8 bytes either way).
	if [ "$(opt_nerd_fonts)" = "on" ]; then
		icon="$(opt_search_icon)"
	else
		icon=""
	fi
	# gap: exactly opt_query_gap PLAIN (unstyled) spaces between the query and the tabs.
	[[ "$(opt_query_gap)" =~ ^[0-9]+$ ]] && gap="$(printf '%*s' "$(opt_query_gap)" '')" || gap=""

	# --- (c) NO-MATCH (PRD §19 §3.34): <icon><query> (no match). Plain-ASCII marker. ---
	if [ "$FLEN" -eq 0 ]; then
		printf '%s' "#[fg=$FG,bg=$BG]${icon}${esc_filter} (no match)#[default]"
		return 0
	fi

	# clamp cidx (0-based; wrap is the input-handler's job).
	cidx="$IDX"
	[[ "$cidx" =~ ^[0-9]+$ ]] || cidx=0
	[ "$cidx" -ge "$FLEN" ] && cidx=$((FLEN - 1))
	[ "$cidx" -lt 0 ] && cidx=0

	# Build the tab segments (shared by query-empty + query-active): each name # escaped,
	# styled; the highlighted index uses HFG/HBG; joined by a single space (plain mode).
	first=1
	tabs=""
	for i in "${!filtered[@]}"; do
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

	if [ -z "$FILTER" ]; then
		# --- (a) QUERY EMPTY (PRD §19 §3.30): ONLY the tabs, positioned per status-justify.
		# No icon/query/gap/count. tmux does NOT justify #() output, so the renderer EMULATES
		# it with leading padding spaces (§P6). status-justify is ONE read per redraw (allowed).
		justify="$(tmux show-options -g -v status-justify 2>/dev/null)"
		[ -z "$justify" ] && justify=left
		width="$(get_state "$STATE_CLIENT_WIDTH" "0")"
		[[ "$width" =~ ^[0-9]+$ ]] || width=0
		pad=""
		if [ "$justify" != left ] && [ "$width" -gt 0 ]; then
			tabs_w="$(lp_disp_width "$tabs")"   # strip #[...] styles, count codepoints
			if [ "$tabs_w" -lt "$width" ]; then
				case "$justify" in
					centre | absolute-centre) padw=$(( (width - tabs_w) / 2 )) ;;
					right) padw=$(( width - tabs_w )) ;;
					*) padw=0 ;;
				esac
				[ "$padw" -gt 0 ] && pad="$(printf '%*s' "$padw" '')"
			fi
		fi
		printf '%s' "${pad}${tabs}"
		return 0
	fi

	# --- (b) QUERY ACTIVE (PRD §19 §3.31): <icon><query><gap><tabs> at column 0.
	# status-justify is SUSPENDED (pinned-left). Query is # escaped; gap is plain spaces.
	printf '%s' "#[fg=$FG,bg=$BG]${icon}${esc_filter}#[default]${gap}${tabs}"
```

**Task 4 — test_functional.sh assertion updates:**

```bash
# oldText (line 332 area — the match-branch assertion + message):
	assert_contains "$out" "query> ##dev" \
		"renderer escaped # -> ## in the query (match branch, count suffix)"
# newText:
	assert_contains "$out" "##dev" \
		"renderer escaped # -> ## in the query+tab (§19 query-active; query> prefix gone)"

# oldText (line 337 area — the no-match-branch assertion + message):
	assert_contains "$out" "query> ##zz" \
		"renderer escaped # -> ## in the query (no-match branch)"
# newText:
	assert_contains "$out" "##zz" \
		"renderer escaped # -> ## in the query (§19 no-match; no tabs -> query-only proof)"
```

**Task 5 — test_responsiveness.sh assertion update (line 94 area):**

```bash
# oldText:
	assert_contains "$("$LIVEPICKER_SCRIPTS/renderer.sh")" "query> a" \
		"status reflects the new query synchronously"
# newText (pin nerd_fonts on; assert the search icon — it only renders when a query is active):
	tmux set-option -g @livepicker-nerd-fonts on
	local rendered
	rendered="$("$LIVEPICKER_SCRIPTS/renderer.sh")"
	case "$rendered" in
		*$'\uf002'*) pass "status reflects the new query synchronously (query-active icon shown)" ;;
		*) fail "status did not show the query-active icon (§19 query-active layout)" ;;
	esac
```
(The SEQ-bump assertion immediately above is the load-bearing deferral proof; it is unchanged.)

NOTE for the implementer: the edits above are the complete, ready anchors (match the current
file content; TAB-indented). The only allowed deviation is comment phrasing. Do NOT touch the ws
path. Do NOT remove the SHOW_COUNT computation. Do NOT slice by SCROLL. Do NOT leave any `query>`
or `[i/N]` in the plain path.

### Integration Points

```yaml
CODE:
  - file: scripts/renderer.sh
    change: "+source layout.sh; +9 locals; plain-path body REPLACED with §19 (3 branches; SHOW_COUNT use dropped)"
    invariant: "plain line follows §19 (no query>, no count); ws path byte-identical"

CONSUMERS / PRODUCERS:
  - P1.M2.T2 (viewport windowing): will slice filtered[] by STATE_SCROLL + add overflow indicators
    to branches (a)/(b). This task READS SCROLL (the seam) but does not slice.
  - P1.M2.T3 (ws path §19 restructure): will mirror this layout onto the ws path AND remove
    SHOW_COUNT entirely (then the shared SHOW_COUNT compute can go).
  - P1.M3.T1 (client-width capture): will WRITE STATE_CLIENT_WIDTH — once it lands, the
    status-justify emulation (branch a) activates for centre/right users (today width=0 -> left).
  - P1.M4.T1 (test_layout.sh): the §15.28 layout integration suite (empty/active/overflow/no-match).

CONFIG / DATABASE / ROUTES: none.
```

## Validation Loop

### Level 1: Syntax & Style (Immediate Feedback)

```bash
cd /home/dustin/.config/tmux/plugins/tmux-livepicker
bash -n scripts/renderer.sh && echo "OK: renderer syntax"
bash -n tests/test_functional.sh && bash -n tests/test_responsiveness.sh && echo "OK: tests syntax"
shellcheck scripts/renderer.sh tests/test_functional.sh tests/test_responsiveness.sh
# layout.sh is now sourced:
grep -c 'source "$CURRENT_DIR/layout.sh"' scripts/renderer.sh   # -> 1
# NO plain-path SHOW_COUNT use / query> / [i/N] (EXCLUDE the ws block ~lines 46-135):
awk '/if \[ "\$\(opt_tab_style\)" = "window-status" \]; then/{ws=1} ws&&/fi$/{ws=0; next} !ws{print}' scripts/renderer.sh > /tmp/plain_only.txt
grep -cE 'query>|\[[0-9]+/[0-9]+\]|SHOW_COUNT' /tmp/plain_only.txt   # -> 0  (no count/query> in the plain path)
grep -c 'STATE_SCROLL\|STATE_CLIENT_WIDTH' scripts/renderer.sh       # -> 2 (both read)
# ws path INTACT (still has its SHOW_COUNT + query> — P1.M2.T3 removes them):
grep -c 'query>' scripts/renderer.sh   # -> 2 (both in the ws block: no-match + suffix)
# Tabs-not-spaces in the new region:
grep -nP '^    [^#/]' scripts/renderer.sh | tail -30 && echo "WARN: space-indent" || echo "OK: tabs"
rm -f /tmp/plain_only.txt
# Expected: syntax clean; shellcheck 0 new findings; plain path has NO query>/count/SHOW_COUNT;
# layout.sh sourced; ws path intact (its 2 query> lines remain).
```

### Level 2: Full suite (the 3 updated tests + no regression)

```bash
cd /home/dustin/.config/tmux/plugins/tmux-livepicker
tests/run.sh
# Expected: exit 0, all green — incl. test_renderer_escapes_hash_in_filter (updated assertions),
# test_renderer_escapes_hash_in_names (unchanged; query-empty still shows escaped tabs), and the
# test_responsiveness deferred-preview test (icon-presence assertion). If test_typing_filters or
# test_appearance FAIL, the ws path or the tab rendering was accidentally changed — diff-check.
```

### Level 3: Render-path smoke (throwaway — proves the 3 §19 branches; then DELETE)

```bash
cat > /tmp/smoke_render19.sh <<'EOF'
#!/usr/bin/env bash
set -u
cd /home/dustin/.config/tmux/plugins/tmux-livepicker
source tests/setup_socket.sh; source tests/helpers.sh
pass_n=0; fail_n=0
has()  { if [ -n "$2" ] && [[ "$2" == *"$1"* ]]; then pass_n=$((pass_n+1)); else fail_n=$((fail_n+1)); echo "FAIL: [$1] absent"; fi; }
nohas(){ if [[ "$2" != *"$1"* ]]; then pass_n=$((pass_n+1)); else fail_n=$((fail_n+1)); echo "FAIL: [$1] present (should be absent)"; fi; }

# (a) query EMPTY: only tabs; no icon/query/gap/count; highlight idx 1.
setup_test "lp19-empty"
tmux set-option -g @livepicker-list $'alpha\nbeta\ngamma'
tmux set-option -g @livepicker-filter ''
tmux set-option -g @livepicker-index 1
tmux set-option -g @livepicker-show-count on      # MUST be ignored by the plain path now
tmux set-option -g @livepicker-nerd-fonts on
out="$(bash scripts/renderer.sh)"
has "#[fg=black,bg=yellow]beta#[default]" "$out"   # idx 1 highlighted (HFG/HBG defaults)
has "alpha" "$out"; has "gamma" "$out"              # all tabs present
nohas $'\uf002' "$out"                              # NO icon (query empty)
nohas "query>" "$out"; nohas "[1/3]" "$out"; nohas "[2/3]" "$out"   # NO query>/count
teardown_test

# (b) query ACTIVE: <icon><query><gap><tabs>; pinned left; no query>/count.
setup_test "lp19-active"
tmux set-option -g @livepicker-list $'alpha\nbeta\ngamma'
tmux set-option -g @livepicker-filter 'a'
tmux set-option -g @livepicker-index 0
tmux set-option -g @livepicker-nerd-fonts on
tmux set-option -g @livepicker-query-gap 2
out="$(bash scripts/renderer.sh)"
has $'\uf002' "$out"        # icon present (query active)
has "a" "$out"              # query char
has "alpha" "$out"          # tab
nohas "query>" "$out"; nohas "[1/1]" "$out"
# icon immediately precedes the query (column-0 pinned layout):
has $'\uf002a' "$out"
teardown_test

# (c) no-match: <icon><query> (no match); no tabs.
setup_test "lp19-nomatch"
tmux set-option -g @livepicker-list $'alpha\nbeta'
tmux set-option -g @livepicker-filter 'zzz'
tmux set-option -g @livepicker-index 0
tmux set-option -g @livepicker-nerd-fonts on
out="$(bash scripts/renderer.sh)"
has "(no match)" "$out"; has $'\uf002' "$out"; has "zzz" "$out"
nohas "alpha" "$out"; nohas "[0/2]" "$out"   # no tabs, no count
teardown_test

echo "pass=$pass_n fail=$fail_n"; [ "$fail_n" -eq 0 ]
EOF
bash /tmp/smoke_render19.sh; rc=$?; rm -f /tmp/smoke_render19.sh; exit $rc
# Expected: pass~20 fail=0. (a) proves query-empty = tabs only + highlight + no count even with
# show-count=on; (b) proves icon+query+gap+tabs + the icon-precedes-query structure; (c) proves
# no-match. Decoupled from activate (seeds state directly).
```

### Level 4: status-justify emulation spot-check (RESIDUAL visual verify — FINDING 4)

```bash
# The emulation decision rests on §P6 + §19 §3.31 (tmux does NOT auto-justify #() output). Verify
# the empty-query centre case renders CENTRED (not double-justified, not left) on a real client:
cd /home/dustin/.config/tmux/plugins/tmux-livepicker
source tests/setup_socket.sh; source tests/helpers.sh
setup_test "lp19-justify"; attach_test_client
tmux set-option -g @livepicker-list $'alpha\nbeta'
tmux set-option -g @livepicker-filter ''
tmux set-option -g @livepicker-index 0
tmux set-option -g @livepicker-client-width 120     # emulate P1.M3.T1's capture (width known)
tmux set-option -g status-justify centre
tmux set-option -g status-format[0] "#($(pwd)/scripts/renderer.sh)"
tmux refresh-client -S; sleep 0.3
CLIENT="$(tmux list-clients -F '#{client_name}' | head -1)"
echo "status line (expect tabs centred ~col 58, NOT left at col 0, NOT double-shifted):"
tmux capture-pane -p -t "$CLIENT" | grep -E 'alpha|beta' | head -1 | sed 's/ *$//'
tmux set-option -g status-justify left   # contrast
tmux refresh-client -S; sleep 0.3
echo "status line (justify=left; expect tabs at col 0):"
tmux capture-pane -p -t "$CLIENT" | grep -E 'alpha|beta' | head -1 | sed 's/ *$//'
teardown_test
# Expected: centre -> tabs start ~mid-line; left -> tabs start at col 0. IF centre shows tabs at
# col 0 (emulation had no effect) OR past the midpoint (double-justified), the emulation assumption
# is wrong for this tmux build -> drop the padding block (documented fallback in research FINDING 4).
# (With STATE_CLIENT_WIDTH unset in the real activate today, centre degrades to left — that's
#  expected until P1.M3.T1; the spot-check sets it explicitly to exercise the emulation.)
```

## Final Validation Checklist

### Technical Validation
- [ ] `bash -n` + `shellcheck` clean on renderer.sh + the 2 test files.
- [ ] layout.sh sourced; 9 new locals declared; plain-path body replaced.
- [ ] NO `query>` / `[i/N]` / `SHOW_COUNT` use in the PLAIN path (L1 awk/grep).
- [ ] ws path byte-identical (its 2 `query>` lines + SHOW_COUNT usage intact).
- [ ] STATE_SCROLL + STATE_CLIENT_WIDTH both read (grep count 2).

### Feature Validation
- [ ] (a) query-empty: tabs only, highlighted, no icon/query/gap/count — even with show-count=on (L3).
- [ ] (b) query-active: `<icon><query><gap><tabs>`; icon precedes query; no count (L3).
- [ ] (c) no-match: `<icon><query> (no match)`; no tabs (L3).
- [ ] status-justify emulation centres/rights the empty-query tabs when width is set (L4); degrades
      to left when width=0.
- [ ] 3 updated test assertions PASS; full `tests/run.sh` green.

### Code Quality Validation
- [ ] 3-branch structure keyed on FILTER emptiness + FLEN; no-match checked before cidx clamp.
- [ ] `printf '%s' "..."` QUOTED everywhere (never unquoted — contract typo avoided).
- [ ] icon styled inside `#[fg=$FG,bg=$BG]…`; gap is PLAIN spaces after `#[default]`.
- [ ] query `#`-doubled; tabs per-item styled + `#[default]` after each (§P6).
- [ ] Edits confined to the plain path + header + locals + 3 test assertions; ws path untouched.

### Documentation & Deployment
- [ ] Inline comments cross-reference PRD §19 (§3.30/§3.31/§3.34) + §P6 + the P1.M2.T2/T3/P1.M3.T1 seams.
- [ ] No README/CHANGELOG edit here (renderer output is internal; the changeset sync is P4.T1).

---

## Anti-Patterns to Avoid

- ❌ Don't touch the window-status early-return path (the `if opt_tab_style == window-status … fi`
  block). It still uses SHOW_COUNT + `query>` — P1.M2.T3 reworks it. The L1 awk EXCLUDES it.
- ❌ Don't remove the SHOW_COUNT computation (SHOW_COUNT_RAW + case→SHOW_COUNT). The ws path uses
  it. Only remove the plain-path *use* (no-match count + trailing [i/N]). (FINDING 5.)
- ❌ Don't leave any `printf '%s' $out` UNQUOTED. The contract's `$out` (unquoted) is a typo —
  always `"$out"` / `"${pad}${tabs}"`. Unquoted word-splits the styled line. (§P6.)
- ❌ Don't assume tmux auto-applies status-justify to #() output. §P6 + §19 §3.31 require the
  renderer to emulate it (suspend-while-query-active is only possible renderer-side). Emulate in
  branch (a); pin left in (b)/(c). Verify visually (L4). (FINDING 4.)
- ❌ Don't slice filtered[] by STATE_SCROLL. Windowing/overflow is P1.M2.T2. READ scroll only.
- ❌ Don't forget to `source layout.sh` (lp_disp_width is needed for the justify emulation).
- ❌ Don't put the gap inside the `#[fg=$FG,bg=$BG]…#[default]` styled segment (it'd be a colored
  bar). Emit the gap as PLAIN spaces after the `#[default]` reset.
- ❌ Don't drop the `#`-doubling on the query (`${FILTER//\#/##}`). #() output isn't re-parsed for
  `#{…}` (§P6) — a raw `#` in the query is a stray directive.
- ❌ Don't branch on FLEN for (a) vs (b) — branch on FILTER emptiness. (No-match is FLEN==0; that's
  the only FLEN branch, checked first.)
- ❌ Don't break the 3 existing tests by leaving the old `query>` assertions. Update them (Task 4/5).
  `test_renderer_escapes_hash_in_names` and `test_typing_filters` need NO change — don't touch them.
- ❌ Don't use spaces for indent — TABS only (the file is tab-indented; a space edit won't match).
- ❌ Don't add a committed tests/ file — the §19/§15.28 layout suite is P1.M4.T1. Validate via the
  throwaway L3 smoke + L4 spot-check.

---

## Confidence Score

**8 / 10** for one-pass success. Rationale: the plain-path body is given verbatim (3 §19 branches,
reusing the already-shipped `lp_rank`/`lp_disp_width`/`opt_*`/`get_state` idioms); the 3 test
assertion updates are exact old→new; the dependencies are all COMPLETE (rank/layout/options/state);
the ws path is explicitly fenced off (L1 awk excludes it). The TWO residual risks are (1) the
status-justify emulation assumption — authoritative per §P6 + §19 §3.31 but NOT empirically
confirmed (pty probes flaky), so it carries an L4 visual spot-check + a documented fallback (drop
the padding if double-justified); and (2) STATE_CLIENT_WIDTH is unwritten today (P1.M3.T1), so
centre/right positioning is inert until that lands (degrades to left — by design). Both residuals
are caught/observed by the validation loop, not silent. The shellcheck/`bash -n` + full-suite-green
are the firm gates.
