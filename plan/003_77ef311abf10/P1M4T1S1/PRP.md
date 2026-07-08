# PRP — P1.M4.T1.S1: tests/test_layout.sh — renderer layout integration suite

---

## Goal

**Feature Goal**: Create `tests/test_layout.sh` — a **renderer-seed** integration
suite (no attached client) that validates PRD §19 (Status-line layout: query bar,
viewport, overflow) and the §15.28 "Layout, ranking, scroll, and management"
items by seeding `@livepicker-*` state on the isolated test socket and asserting
on `scripts/renderer.sh` stdout. It covers the six contract cases: **(a)** empty
query → tabs only (no icon/query/gap/`[`/`query>`/`/`); **(b)** one-char query →
`<icon><query><exactly gap spaces><ranked tabs>` with the top match highlighted;
**(c)** overflow → `+N>` (N = total hidden) and `<` when `scroll>0`, neither when
it fits; **(d)** no-match → ` (no match)`; **(e)** NO `index/total` count pattern
in ANY state; **(f)** the `window-status` tab-style path STILL shows the query bar
+ viewport + overflow (honors §19, not the old full-line join). It also pins the
`status-justify` emulation (leading pad) for the empty-fits case.

**Deliverable**: The single NEW file `tests/test_layout.sh` (sourced by
`tests/run.sh` via its `test_*.sh` glob — NOT executed directly). Defines a
`lp_layout_seed` helper (mirrors `test_appearance.sh::lp_appearance_seed`) + ~11
`test_*` functions. Every assertion is backed by a **captured renderer output**
(see `research/test_layout_findings.md`) — no guessed bytes. All tests are
renderer-only (zero `attach_test_client`); they seed state and assert on stdout,
exactly as `test_appearance.sh` (a)-(d) do.

**Success Definition**:
- `bash -n tests/test_layout.sh` passes; `shellcheck tests/test_layout.sh` is clean
  (file-level `# shellcheck disable=SC2154,SC2016,SC2034,SC2086` mirrors
  `test_appearance.sh` — silences the run.sh-provided helpers/vars).
- `tests/run.sh` discovers and runs every `test_layout_*` function; the file adds
  ~11 passing tests and **does not break any existing test** (it touches no source).
- Each contract case (a)-(f) has at least one passing test whose assertions match
  the captured renderer bytes in `research/test_layout_findings.md` exactly.
- The §15.28 "no `index/total` count anywhere" invariant is proven by a sweep test
  that asserts NO `[0-9]/[0-9]` pattern across empty/active/no-match/overflow states.

## User Persona (if applicable)

**Target User**: The maintainer / CI (the suite runs under `tests/run.sh`). Mode A
(internal validation — no end-user surface). The README (P4.T1) summarizes the
validation coverage.

**Use Case**: A change to `scripts/renderer.sh`, `scripts/layout.sh`, or
`scripts/rank.sh` is made. `tests/run.sh` runs `test_layout.sh`'s functions
against a fresh isolated socket per test; any regression in the §19 layout (a
missing gap, a leaked count, a broken overflow indicator, a window-status path
that drops the query bar) turns a specific assertion red with a precise diff.

**User Journey**: `cd <repo> && tests/run.sh` → the runner sources
`setup_socket.sh` + `helpers.sh` + every `test_*.sh` (incl. the new
`test_layout.sh`), discovers every `test_layout_*` function, and runs each in a
per-test fresh-socket cycle (`setup_test "lp-$$-<name>"` → reset TEST_STATUS → run
→ read TEST_STATUS → `teardown_test`). PASS/FAIL printed per test + a summary.

**Pain Points Addressed**:
- (a) §19 is the most layout-dense part of the renderer (query bar / viewport /
  overflow / no-match / two tab styles / justify). Without a dedicated suite, a
  refactor silently breaks one branch (e.g. the count creeps back, or the
  window-status path drops the query bar). This suite pins every branch.
- (b) The `+N>` "total hidden" semantics and the `<` "presence-only" semantics
  are easy to get wrong (split-by-side vs combined; count vs no-count). The
  overflow tests assert the EXACT captured indicator strings.
- (c) The "no count" invariant (§15.28 + P1.M2.T3.S1 removed `opt_show_count`
  entirely) needs a negative sweep — a single positive test cannot prove absence.

## Why

- **§19 is the single source of truth for line 1**, and §15.28 enumerates the
  exact layout items the suite must cover. This task is the validation
  counterpart to the P1.M2 renderer rework (COMPLETE) and the P1.M3 scroll wiring
  (parallel). It locks the renderer's §19 behavior so P2/P3 work (session mgmt,
  preview clip) cannot regress it.
- **Renderer-seed tests are cheap, deterministic, and client-free** (codebase
  patterns §P8: "Renderer tests need NO client: seed `@livepicker-*` state → run
  `scripts/renderer.sh` → `assert_contains` on stdout"). They run in milliseconds
  and never touch the user's real server (isolated `-L` socket).
- **Every assertion is backed by a captured output.** The research file records
  the EXACT bytes the renderer emits for each seeded state (run under the real
  harness on 2026-07-07). So the test author is not guessing — they are encoding
  observed behavior, which makes one-pass success near-certain.
- **Boundary respect.** This task creates ONE test file. It does NOT touch any
  source (`renderer.sh`/`layout.sh`/`rank.sh`/`input-handler.sh`), does NOT
  duplicate `test_functional.sh`'s `#`-escaping tests or `test_appearance.sh`'s
  theme-resolution tests, and does NOT cover ranking-order (that is
  `test_ranking.sh`, P1.M4.T2) or scroll-into-view mechanics (that is
  `test_scroll`, P1.M4.T3). It covers LAYOUT only.

## What

A single NEW sourced test file at `tests/test_layout.sh` that:

1. Declares the file-level shellcheck disable + documents the renderer-seed idiom
   (mirrors `test_appearance.sh`'s header).
2. Defines `lp_layout_seed LIST [FILTER] [INDEX]` — pins the §11 default colors
   (fg/bg=default, highlight-fg=black, highlight-bg=yellow) + type + the list +
   filter + index, and sets `@livepicker-client-width 0` (the renderer's "no
   windowing" default) + clears scroll, so structure tests see the full list.
3. Defines ~11 `test_layout_*` functions (one per contract case + the exact-gap
   and justify sub-cases). Each: seed → set the case-specific options → run
   `"$LIVEPICKER_SCRIPTS/renderer.sh"` → `assert_contains`/`assert_eq`/negative
   `case`.
4. Signals failure ONLY via `fail`/`assert_*` (sets `TEST_STATUS`; never exits).

### Success Criteria

- [ ] `tests/test_layout.sh` EXISTS; file-level `# shellcheck disable=SC2154,SC2016,SC2034,SC2086`.
- [ ] `lp_layout_seed LIST [FILTER] [INDEX]` defined (pins default colors + width 0 + scroll 0).
- [ ] **(a)** `test_layout_empty_query_tabs_only`: empty filter → output contains the
      tab names AND NOT the icon glyph, NOT `query>`, NOT ` (no match)`, NOT `/`,
      and (negative) NOT a leading query block.
- [ ] **(b)** `test_layout_query_active_structure`: filter `l`, nerd-fonts OFF →
      output contains the query `l`, EXACTLY 2 spaces (default gap) before the
      highlighted top match, the top match highlighted via HFG/HBG, and the
      non-matching `foo` HIDDEN.
- [ ] **(b-gap)** `test_layout_query_gap_exact`: `@livepicker-query-gap 4` → exactly
      4 spaces; `0` → zero spaces (highlight immediately follows the query block).
- [ ] **(b-icon)** `test_layout_query_active_nerd_font_icon`: nerd-fonts ON → output
      contains the U+F002 icon bytes (`$'\uf002'`).
- [ ] **(c)** `test_layout_overflow_right_indicator`: 8 tabs, width 20, scroll 0 →
      contains `+5>` AND NOT `<`.
- [ ] **(c)** `test_layout_overflow_left_indicator`: scroll 3, index 3 → contains
      `<` AND `+6>`.
- [ ] **(c)** `test_layout_overflow_fits_no_indicators`: 3 tabs, width 80 → NOT `+`
      (no `+N>`) AND NOT `<`.
- [ ] **(c+b)** `test_layout_overflow_with_query_active`: `s0..s9`, filter `s`,
      width 14 → query bar present AND `+N>` present; scroll>0 variant → `<` present.
- [ ] **(d)** `test_layout_no_match`: filter `zzz` → contains ` (no match)` AND NOT
      any tab name.
- [ ] **(e)** `test_layout_no_count_anywhere`: sweep empty/active/no-match/overflow
      → NONE matches `[0-9]/[0-9]` (the count is gone entirely).
- [ ] **(f)** `test_layout_window_status_keeps_query_bar`: window-status tab-style +
      templates + `s0..s9` + filter `s` + width 14 → query bar present AND `+N>`
      present AND the current-template styling used (not the old full-line join).
- [ ] **(justify)** `test_layout_status_justify_empty`: empty query, fits,
      `status-justify centre` → output starts with a leading space; `left` → no
      leading space.
- [ ] `bash -n` clean; `shellcheck` 0 new findings; `tests/run.sh` exit 0 (all green).

## All Needed Context

### Context Completeness Check

_Pass_: an implementer who has never seen this repo can implement `test_layout.sh`
from (a) the verbatim, ready-to-paste file body in the Implementation Blueprint,
(b) the captured renderer outputs in `research/test_layout_findings.md` (every
assertion string is observed, not guessed), (c) `tests/test_appearance.sh` (the
exact renderer-seed idiom to mirror — `lp_appearance_seed` + direct `assert_contains`
on `"$LIVEPICKER_SCRIPTS/renderer.sh"` stdout), and (d) `tests/helpers.sh` +
`tests/run.sh` (the `setup_test`/`assert_*`/`fail`/`TEST_STATUS` contract +
per-test fresh-socket cycle). The renderer under test (`scripts/renderer.sh`) and
its deps (`layout.sh`, `rank.sh`, `options.sh`, `state.sh`) are all COMPLETE. This
is a single-file greenfield test that adds a sourced module to an existing,
working runner.

### Documentation & References

```yaml
# MUST READ — the file to MIRROR (the renderer-seed idiom; the closest analog).
- file: tests/test_appearance.sh
  why: The template for test_layout.sh. Defines lp_appearance_seed (pins §11 default
       colors so output is byte-deterministic regardless of the user tmux.conf) and
       5 test_* functions that seed @livepicker-* state, run renderer.sh, and
       assert_contains/assert_eq on stdout — NO attach_test_client. Copy its header
       (shellcheck disable line + the SOURCED-by-run.sh contract comment), its seed
       shape, and its assertion style. Swap the appearance-specific seeds/asserts for
       the layout ones.
  pattern: |
    lp_appearance_seed() { tmux set-option -g @livepicker-fg default; ...; tmux set-option -g @livepicker-list "$1"; ... }
    test_X() { lp_appearance_seed $'a\nb' "" 1; tmux set-option -g @livepicker-tab-style ...; local out; out="$("$LIVEPICKER_SCRIPTS/renderer.sh")"; assert_contains "$out" "..." "..."; }
  gotcha: test_appearance.sh's seed sets client-width to NOTHING (width 0 → the
          renderer's no-windowing full-list path). test_layout.sh MUST seed width
          for the overflow tests (otherwise there is no viewport slicing) — see
          the overflow test bodies. Keep width 0 for the structure/empty/no-match
          tests (so they assert the full list, not a sliced window).

# MUST READ — the captured ground-truth (every assertion string is observed here).
- docfile: plan/003_77ef311abf10/P1M4T1S1/research/test_layout_findings.md
  why: The EXACT renderer output bytes for every seeded state test_layout.sh asserts
       against (OUT-a empty, OUT-b query nerd-off, OUT-b2 nerd-on, OUT-d no-match,
       OUT-c/c2 overflow, OUT-f window-status, OUT-justify). Plus the deterministic
       facts (gap=2 unstyled spaces; icon = raw U+F002 bytes; +N> %d = total hidden;
       < presence-only; (no match) plain ASCII; no count anywhere) and the test-design
       table mapping each contract item to a test_* function.
  critical: Read BEFORE writing any assertion. The "+5>" / "+6>" / "<" indicator
            strings, the exact 2-space gap, and the no-match " (no match)" text are
            all captured here verbatim — encode them as-is.

# MUST READ — the renderer under test (the program whose stdout we assert on).
- file: scripts/renderer.sh
  why: The COMPLETE §19 renderer. The four emit sites test_layout.sh exercises:
       (1) no-match early-return: printf '#[fg=$FG,bg=$BG]${icon}${esc_filter} (no match)#[default]';
       (2) query-empty fits: printf '%s' "${pad}${tabs}" (pad = status-justify leading pad);
       (3) query-empty overflow: printf '%s' "${left_ind}${tabs}${right_ind}";
       (4) query-active: printf '%s' "#[fg=$FG,bg=$BG]${icon}${esc_filter}#[default]${gap}${left_ind}${tabs}${right_ind}".
       gap = printf '%*s' opt_query_gap (plain spaces). icon = opt_search_icon iff nerd-fonts on.
       Confirms width 0 → no windowing (the `if [ "$width" -gt 0 ]` guard).
  section: the render() body (the 4 printf sites); the viewport/indicator-circle block.

# MUST READ — the assertion + setup contract (helpers.sh) and the runner (run.sh).
- file: tests/helpers.sh
  why: Defines fail/pass/assert_eq/assert_contains/setup_test/teardown_test.
       assert_contains uses a quoted `case` pattern (literal substring, glob-safe).
       setup_test [sock] = fresh isolated -L socket + PATH shim + baseline fixtures
       (driver/alpha/beta) + pins @livepicker-preview-defer off. TEST_STATUS is the
       per-test pass/fail flag run.sh reads. Test bodies signal failure ONLY via
       fail/assert_* (NEVER exit/return-nonzero — that would kill the runner).
  section: assert_contains, assert_eq, fail, setup_test.
- file: tests/run.sh
  why: Sources setup_socket.sh + helpers.sh + every tests/test_*.sh, discovers
       test_* via `compgen -A function | grep '^test_'`, runs each in a per-test
       fresh-socket cycle. So test_layout.sh SOURCES NOTHING and calls NO
       setup_test/teardown_test at file scope — it only DEFINES test_* functions.
  section: the source loop + the per-test cycle.

# MUST READ — the socket isolation (the baseline fixtures + $LIVEPICKER_SCRIPTS).
- file: tests/setup_socket.sh
  why: setup_socket spawns driver/alpha/beta (TEST_FIXTURE_SESSIONS) + a multi-pane
       driver window. Exports LIVEPICKER_SCRIPTS (== <repo>/scripts) + TEST_DRIVER_SESSION.
       test_layout.sh uses "$LIVEPICKER_SCRIPTS/renderer.sh" (not a relative path).
       For overflow tests that need MORE sessions than the baseline, the test adds
       its own via bare `tmux new-session` (hits the isolated socket) OR — simpler
       and what this suite does — seeds @livepicker-list DIRECTLY (the renderer reads
       the list from state, not list-sessions; it never queries live sessions).
  section: setup_socket (the fixture spawn + exports).

# MUST READ — the option accessors (the defaults the seed must pin against).
- file: scripts/options.sh
  why: The defaults the renderer uses when an option is unset: opt_query_gap=2,
       opt_nerd_fonts=on, opt_search_icon=$'\uf002' (U+F002), opt_overflow_left="<",
       opt_overflow_right_format="+%d>", opt_tab_style=plain, opt_fg/bg=default,
       opt_highlight_fg=black, opt_highlight_bg=yellow. test_layout.sh leaves the
       layout options at default EXCEPT where a test deliberately overrides
       (nerd-fonts off; query-gap 4/0; tab-style window-status; client-width).
  section: opt_query_gap, opt_nerd_fonts, opt_search_icon, opt_overflow_*.

# MUST READ — the state keys (what the seed writes).
- file: scripts/state.sh
  why: The renderer reads STATE_LIST/FILTER/INDEX/SCROLL/CLIENT_WIDTH and (for the
       window-status path) STATE_TAB_CURRENT_TMPL/STATE_TAB_INACTIVE_TMPL. The seed
       writes these via `tmux set-option -g @livepicker-<x>`. (No need to source
       state.sh in the test — the keys are just @livepicker-* option strings; the
       test writes them directly, mirroring test_appearance.sh.)
  section: STATE_SCROLL, STATE_CLIENT_WIDTH, STATE_TAB_CURRENT_TMPL.

# MUST READ — PRD §19 (the layout spec) + §15.28 (the validation items).
- docfile: PRD.md
  why: §19 is the single source of truth for line 1 (query bar / viewport / overflow
       / no-match; two independent visibility rules; the +%d> total-hidden semantics;
       the < presence-only semantics; the (no match) plain-ASCII marker; status-justify
       suspended while a query is active). §15.28 enumerates the exact items the suite
       must cover (empty → tabs only; one char → icon+query+2 spaces+ranked; overflow
       +N> and <; no index/total anywhere). §17 (tab appearance) grounds the
       window-status path test.
  section: "§19 Status-line layout", "§15.28 Layout, ranking, scroll, and management",
           "§17 Tab appearance".

# MUST READ — the conventions (the test-harness pattern + the renderer rules).
- docfile: plan/003_77ef311abf10/architecture/codebase_patterns.md
  why: §P8 (Test harness: renderer tests need NO client — seed state → run renderer.sh
       → assert_contains on stdout; mirror test_functional.sh's renderer-seed idiom);
       §P6 (Renderer rules: emits EXACTLY ONE line NO trailing newline; #[default]
       after every segment; #() stdout not re-parsed for #{…} so query # is doubled —
       that escaping is test_functional.sh's job, NOT this suite's).
  section: "P8", "P6".

# Reference — the parallel scroll task (do NOT duplicate its tests here).
- docfile: plan/003_77ef311abf10/P1M3T2S1/PRP.md
  why: P1.M3.T2.S1 wires STATE_SCROLL into the input paths (scroll-into-view + reset).
       test_layout.sh tests the RENDERER's reading of STATE_SCROLL (the < indicator
       appears when scroll>0) — which is a LAYOUT concern. It does NOT test the
       input-handler's scroll-into-view mechanics (that is P1.M4.T3.S1). The seam:
       test_layout.sh SETS @livepicker-scroll directly to exercise the renderer's
       left-indicator branch; it never drives input-handler.sh.
  section: the STATE_SCROLL renderer-read vs input-handler-write split.
```

### Current Codebase tree

```bash
tmux-livepicker/
  PRD.md, README.md, CHANGELOG.md, plugin.tmux
  scripts/
    renderer.sh   # EXISTS (P1.M2.* COMPLETE). The program under test.
    layout.sh     # EXISTS (P1.M1.T2 COMPLETE). lp_viewport — consumed by the renderer.
    rank.sh       # EXISTS (P1.M1.T1 COMPLETE). lp_rank — consumed by the renderer.
    options.sh, state.sh, utils.sh, input-handler.sh, livepicker.sh, preview.sh, restore.sh
  tests/
    run.sh            # EXISTS. Sources every test_*.sh; discovers test_*.
    setup_socket.sh   # EXISTS. Isolated -L socket + PATH shim + baseline fixtures.
    helpers.sh        # EXISTS. assert_eq/assert_contains/fail/setup_test/teardown_test.
    test_appearance.sh   # EXISTS. THE RENDERER-SEED TEMPLATE (mirror this).
    test_functional.sh, test_create.sh, test_keyrepurpose.sh, test_pollution.sh,
    test_preview.sh, test_responsiveness.sh, test_restore.sh, test_self.sh
    # test_layout.sh  # ← DOES NOT EXIST YET (this task CREATES it).
  plan/003_77ef311abf10/{architecture/*.md, tasks.json, prd_snapshot.md, prd_index.txt, P1M4T1S1/{PRP.md, research/}}
```

### Desired Codebase tree with files to be added and responsibility of file

```bash
tests/
  test_layout.sh   # NEW (this task). Renderer-seed suite for PRD §19 / §15.28.
                   #   lp_layout_seed (pins default colors + width 0 + scroll 0) +
                   #   ~11 test_layout_* fns: empty / query-active / gap-exact /
                   #   nerd-icon / overflow-right / overflow-left / fits / overflow+
                   #   query / no-match / no-count-sweep / window-status-keeps-§19 /
                   #   status-justify. Sourced by run.sh; signals failure via assert_*.
```

### Known Gotchas of our codebase & Library Quirks

```bash
# CRITICAL: the renderer emits NO trailing newline (printf '%s' "$out"; §P6). So
# `out="$("$LIVEPICKER_SCRIPTS/renderer.sh")"` captures the whole line with NO
# trailing \n. assert_contains / case matching works on it directly. Do NOT pipe
# through `head`/`tail` (they'd add/strip a newline). A direct capture is correct.

# CRITICAL: seed the §11 DEFAULT colors explicitly (lp_layout_seed does this).
# The isolated socket sources the user tmux.conf -> @livepicker-fg "#ffffff" is
# dormant there. If the seed does NOT pin fg/bg/highlight-*, the renderer reads
# #ffffff and the byte-exact assertions (#[fg=default,bg=default] / #[fg=black,bg=yellow])
# FAIL. This is exactly why test_appearance.sh::lp_appearance_seed pins them. Mirror it.

# CRITICAL: the renderer reads STATE_CLIENT_WIDTH; width 0 (unset) -> NO windowing
# (full-list render, NO indicators). So the structure/empty/no-match tests MUST leave
# width at 0 (the seed sets it) to assert the FULL list. The overflow tests MUST set
# a narrow width (e.g. 20) to force viewport slicing + indicators. Do not mix these up.

# CRITICAL: the icon glyph is RAW UTF-8 bytes (ef 80 82 = U+F002), emitted ONLY when
# nerd-fonts=on AND a query is active. To assert it, use the bash ANSI-C quote
# $'\uf002' as the assert_contains substring. Leave @livepicker-search-icon UNSET in
# the test (so it stays at the U+F002 default) — do NOT seed a custom icon. For the
# STRUCTURE tests (exact gap, ranked tabs), set nerd-fonts OFF so the icon is EMPTY
# and the query block is just the query (deterministic ASCII; no glyph-width ambiguity).

# CRITICAL (the gap is UNSTYLED): the gap between the query block and the first tab is
# raw spaces, NOT inside a #[…] segment. So the substring is `...#[default]  #[fg=HFG,bg=HBG]`
# (end of query block + N spaces + start of highlight). To assert EXACTLY N spaces,
# assert_contains the literal N-space substring AND a negative `case` for N+1. The
# exact-gap test (query-gap 4 and 0) nails it without ambiguity.

# GOTCHA: `assert_contains` is a LITERAL substring match (helpers.sh uses a quoted
# `case` pattern — glob specials are disabled for the quoted segment). So `+5>` and
# `<` and ` (no match)` match literally even though they contain no glob specials.
# For the negative assertions (NOT present), use `case "$out" in *SUBSTR*) fail ... ;; esac`
# (mirror test_appearance.sh's negative idiom).

# GOTCHA: `status-justify` is a SESSION option; the renderer reads it via
# `tmux show-options -g -v status-justify`. Set it on the test socket via
# `tmux set-option -g status-justify centre` (global session option). Do NOT use -w
# (window option). The justify test asserts STRUCTURE (leading pad present/absent),
# not an exact space count (pad = (width - tabs_w)/2 is brittle to tab-width math).

# GOTCHA: do NOT seed live sessions for the list. The renderer reads the list from
# STATE_LIST (@livepicker-list), NOT list-sessions. Seed `tmux set-option -g
# @livepicker-list "$(printf 's0\ns1\n...')"`. (The baseline fixtures driver/alpha/beta
# exist on the socket but the renderer never queries them — it reads state only.)

# GOTCHA (scope): this suite tests LAYOUT only. Do NOT add ranking-order assertions
# (prefix-vs-subsequence ordering is test_ranking.sh / P1.M4.T2) beyond "the top match
# is highlighted + non-matches hidden". Do NOT test scroll-into-view mechanics (that is
# P1.M4.T3). Do NOT test # escaping (test_functional.sh owns it). Do NOT attach a client.

# STYLE (system_context §9 / codebase_patterns §P8): TABS for indent; `set -u` is
# INHERITED from helpers.sh (do NOT re-declare; mirror test_appearance.sh's header
# comment). File-level shellcheck disable=SC2154,SC2016,SC2034,SC2086 (the run.sh-
# provided helpers/vars + the quoted case patterns).
```

## Implementation Blueprint

### Data models and structure

No data model. The "structure" is the renderer-seed flow every test follows:

```
lp_layout_seed LIST [FILTER] [INDEX]   # pins default colors + type + width 0 + scroll 0
tmux set-option -g @livepicker-<case-specific>...   # nerd-fonts / query-gap / tab-style / width / scroll / templates
out="$("$LIVEPICKER_SCRIPTS/renderer.sh")"          # capture stdout (NO trailing newline)
assert_contains "$out" "<expected substring>" "<msg>"   # positive
case "$out" in *"<must-be-absent>"*) fail "<msg>" ;; esac   # negative
```

### Implementation Tasks (ordered by dependencies)

```yaml
Task 1: CREATE tests/test_layout.sh — header + lp_layout_seed helper
  - FILE: ./tests/test_layout.sh  (NEW; run.sh's `test_*.sh` glob picks it up).
  - HEADER: shebang + file-level shellcheck disable=SC2154,SC2016,SC2034,SC2086 +
    a doc block (purpose: PRD §19 / §15.28 renderer-seed suite; the SOURCED-by-run.sh
    contract; the renderer-only/no-client approach; mirror test_appearance.sh).
  - lp_layout_seed LIST [FILTER] [INDEX]: pin fg=default/bg=default/highlight-fg=black/
    highlight-bg=yellow/type=session (the §11 defaults — byte-deterministic regardless
    of the user tmux.conf) + list/filter/index + @livepicker-client-width 0 (no windowing
    default) + @livepicker-scroll 0 + @livepicker-nerd-fonts OFF (deterministic ASCII;
    the icon test turns it ON). Mirror lp_appearance_seed's shape exactly.

Task 2: CREATE the (a) empty + (d) no-match + (e) no-count tests
  - test_layout_empty_query_tabs_only: seed 3 tabs, filter "". Assert contains each tab
    name; negative for the icon ($'\uf002'), "query>", " (no match)", "/". (§3.30)
  - test_layout_no_match: seed 2 tabs, filter "zzz". Assert contains " (no match)";
    negative for each tab name. (§3.34)
  - test_layout_no_count_anywhere: build 4 outputs (empty / query-active / no-match /
    overflow) and assert NONE matches the regex [0-9]/[0-9] (the count is gone). (§15.28)

Task 3: CREATE the (b) query-active tests (structure + exact gap + nerd icon)
  - test_layout_query_active_structure: seed list with a clear top match + a non-match
    (e.g. alpha/logs-prod/blog-engine/foo), filter "l", nerd off, width 0. Assert:
    contains the query "l"; the 2-space gap substring `l#[default]  #[fg=black,bg=yellow]`;
    the top match (logs-prod) highlighted; the non-match (foo) HIDDEN. Negative: NOT 3 spaces.
  - test_layout_query_gap_exact: seed, set @livepicker-query-gap 4 → assert the 4-space
    literal substring; set 0 → assert the highlight immediately follows `#[default]#[fg=black,bg=yellow]`.
  - test_layout_query_active_nerd_font_icon: nerd-fonts ON → assert_contains the
    U+F002 bytes ($'\uf002').

Task 4: CREATE the (c) overflow tests (right / left / fits / with-query)
  - test_layout_overflow_right_indicator: 8 tabs of width 5, width 20, scroll 0, idx 0.
    Assert contains "+5>" (5 hidden = 8-3); negative "<".
  - test_layout_overflow_left_indicator: same, scroll 3, idx 3. Assert contains "<" AND "+6>".
  - test_layout_overflow_fits_no_indicators: 3 tabs, width 80. Negative for "+" (no +N>) AND "<".
  - test_layout_overflow_with_query_active: seed s0..s9, filter "s", width 14, nerd off.
    Assert query bar ("s") + "+N>" present. scroll>0 variant → "<" present.

Task 5: CREATE the (f) window-status + justify tests
  - test_layout_window_status_keeps_query_bar: tab-style window-status + templates +
    separator "|" + s0..s9 + filter "s" + width 14. Assert query bar present AND "+N>"
    present AND the current-template styling (#[fg=red,bold]) used. (Proves §19 layout
    is shared by both tab styles; not the old full-line join.)
  - test_layout_status_justify_empty: empty query, 2 short tabs, width 40. Set
    status-justify centre → assert output starts with a space (leading pad). Set left
    (default) → assert it does NOT start with a space.

Task 6: VALIDATE (syntax + lint + full suite)
  - RUN: bash -n tests/test_layout.sh; shellcheck tests/test_layout.sh.
  - RUN: tests/run.sh (expect ALL green incl. the ~11 new test_layout_* fns; no existing
    test broken — the new file only DEFINES functions and is auto-discovered).
```

### Implementation Patterns & Key Details

The complete, ready-to-paste file body (the implementer may use it as-is; the only
allowed deviation is comment phrasing):

```bash
#!/usr/bin/env bash
# tests/test_layout.sh — tmux-livepicker PRD §19 / §15.28 renderer-layout integration suite.
#
# SOURCED by run.sh (NEVER executed directly). Defines lp_layout_seed + ~11 test_layout_*
# functions that validate the status-line LAYOUT the renderer emits: the query bar,
# the viewport windowing, the overflow indicators (+N> / <), the no-match marker, the
# absence of any index/total count, the status-justify emulation, and that the
# window-status tab-style path STILL honors §19 (query bar + viewport + overflow).
#
# CONTRACT: run.sh sources setup_socket.sh + helpers.sh + every tests/test_*.sh, then
# PER test calls setup_test "lp-$$-<name>" (-> fresh isolated socket + PATH shim +
# baseline fixtures) -> resets TEST_STATUS=pass -> runs the test_* in the CURRENT shell
# -> reads TEST_STATUS -> teardown_test. So when a test_* runs: bare `tmux` hits the
# isolated socket; $LIVEPICKER_SCRIPTS + fail/pass/assert_eq/assert_contains are IN SCOPE;
# this file SOURCES NOTHING and calls NO setup_test/teardown_test at file scope.
#
# APPROACH (codebase_patterns §P8; mirror test_appearance.sh): the renderer is PURE +
# CLIENT-INDEPENDENT (reads @livepicker-* state only, emits ONE line, zero tmux
# mutations). So every test seeds state DIRECTLY, runs renderer.sh, and asserts on
# stdout — NO attach_test_client. The seed pins the §11 DEFAULT colors so the output is
# byte-deterministic regardless of the user's tmux.conf (which sets @livepicker-fg
# "#ffffff" on the isolated socket). Every assertion is backed by a captured renderer
# output (research/test_layout_findings.md) — no guessed bytes.
#
# SCOPE: LAYOUT only. Ranking ORDER is test_ranking.sh (P1.M4.T2); scroll-into-view
# mechanics are P1.M4.T3; # escaping is test_functional.sh. This suite asserts the
# renderer's LAYOUT (positions/indicators/absence-of-count) for both tab styles.
#
# `set -u` is INHERITED from helpers.sh (do NOT re-declare; mirror test_appearance.sh).
# shellcheck disable=SC2154,SC2016,SC2034,SC2086
#   SC2154: assert_*/fail/$LIVEPICKER_SCRIPTS are defined by run.sh's sources.
#   SC2016: the negative-assertion case patterns use single-quoted literals.
#   SC2034/SC2086: locals + the intentional word-split-free literal substrings.

# lp_layout_seed LIST [FILTER] [INDEX] — pin the deterministic base state the renderer
# reads. §11 default colors (byte-deterministic output); width 0 -> NO windowing
# (the renderer's full-list path; structure tests see every tab); scroll 0; nerd-fonts
# OFF (deterministic ASCII; the icon test turns it ON). The caller overrides the
# case-specific options (nerd-fonts / query-gap / tab-style / client-width / scroll /
# templates) AFTER seeding.
lp_layout_seed() {
	tmux set-option -g @livepicker-type session
	tmux set-option -g @livepicker-fg             "default"
	tmux set-option -g @livepicker-bg             "default"
	tmux set-option -g @livepicker-highlight-fg   "black"
	tmux set-option -g @livepicker-highlight-bg   "yellow"
	tmux set-option -g @livepicker-list   "$1"
	tmux set-option -g @livepicker-filter "${2:-}"
	tmux set-option -g @livepicker-index  "${3:-0}"
	tmux set-option -g @livepicker-client-width "0"   # 0 -> no windowing (full list)
	tmux set-option -g @livepicker-scroll "0"
	tmux set-option -g @livepicker-nerd-fonts "off"   # ASCII-deterministic; icon test flips ON
}

# (a) PRD §19 §3.30 / §15.28: empty query -> line 1 is ONLY the session tabs. No icon,
# no query, no gap, no "query>", no "/", no count. Highlight = index 0 (alpha).
test_layout_empty_query_tabs_only() {
	lp_layout_seed $'alpha\nbeta\ndriver' "" 0
	local out
	out="$("$LIVEPICKER_SCRIPTS/renderer.sh")"
	# the tabs are all present, joined by a single space; alpha highlighted (index 0):
	assert_contains "$out" "#[fg=black,bg=yellow]alpha#[default]" "empty: alpha tab present + highlighted"
	assert_contains "$out" "#[fg=default,bg=default]beta#[default]" "empty: beta tab present (inactive)"
	assert_contains "$out" "#[fg=default,bg=default]driver#[default]" "empty: driver tab present (inactive)"
	# negatives: NO query machinery, NO no-match marker, NO slash, NO icon glyph.
	case "$out" in *"query>"*) fail "empty: 'query>' label leaked" ;; esac
	case "$out" in *" (no match)"*) fail "empty: no-match marker leaked" ;; esac
	case "$out" in *"/"*) fail "empty: '/' leaked (count or separator)" ;; esac
	case "$out" in *$'\uf002'*) fail "empty: nerd-font icon leaked (icon is query-active only)" ;; esac
}

# (b) PRD §19 §3.31 / §15.28: query active -> <icon><query><exactly gap spaces><ranked
# tabs>, top match highlighted, non-matches hidden. nerd-fonts OFF (icon empty) so the
# structure is pure ASCII + the gap is unambiguous. width 0 -> full ranked list.
test_layout_query_active_structure() {
	# logs-prod (prefix 'l') is the top match; alpha/blog-engine match as subsequences;
	# foo has no 'l' -> HIDDEN.
	lp_layout_seed $'alpha\nlogs-prod\nblog-engine\nfoo' "l" 0
	local out
	out="$("$LIVEPICKER_SCRIPTS/renderer.sh")"
	# the query 'l' is emitted (no icon prefix — nerd off):
	assert_contains "$out" "#[fg=default,bg=default]l#[default]" "query: 'l' emitted, styled FG/BG"
	# EXACTLY 2 spaces (default gap) between the query block and the highlighted top match:
	assert_contains "$out" "#[fg=default,bg=default]l#[default]  #[fg=black,bg=yellow]logs-prod#[default]" \
		"query: exactly 2-space gap then the highlighted top match (logs-prod)"
	# the top match is highlighted:
	assert_contains "$out" "#[fg=black,bg=yellow]logs-prod#[default]" "query: top match (logs-prod) highlighted"
	# a non-matching name is HIDDEN:
	case "$out" in *foo*) fail "query: non-match 'foo' was not hidden" ;; esac
	# negative: NOT 3 spaces (gap is exactly 2, not more):
	case "$out" in *"l#[default]   "#*) fail "query: gap is 3 spaces (want exactly 2)" ;; esac
}

# (b-gap) PRD §19 §3.31: the gap is EXACTLY @livepicker-query-gap spaces. Pin it with a
# distinctive value (4) and with 0 to prove the renderer honors the option verbatim.
test_layout_query_gap_exact() {
	lp_layout_seed $'alpha\nlogs-prod' "l" 0
	# gap = 4 -> exactly 4 spaces between the query block and the highlight.
	tmux set-option -g @livepicker-query-gap "4"
	local out4
	out4="$("$LIVEPICKER_SCRIPTS/renderer.sh")"
	assert_contains "$out4" "#[fg=default,bg=default]l#[default]    #[fg=black,bg=yellow]logs-prod#[default]" \
		"query-gap=4: exactly 4 spaces before the highlight"
	case "$out4" in *"l#[default]     "#*) fail "query-gap=4: 5 spaces leaked (want exactly 4)" ;; esac
	# gap = 0 -> NO spaces; the highlight immediately follows the query block's #[default].
	tmux set-option -g @livepicker-query-gap "0"
	local out0
	out0="$("$LIVEPICKER_SCRIPTS/renderer.sh")"
	assert_contains "$out0" "#[fg=default,bg=default]l#[default]#[fg=black,bg=yellow]logs-prod#[default]" \
		"query-gap=0: zero spaces (highlight immediately follows the query block)"
}

# (b-icon) PRD §19 §3.31: with nerd-fonts ON, the search icon (U+F002) is emitted as raw
# UTF-8 bytes immediately before the query, inside the #[…] segment. Leave
# @livepicker-search-icon at its default (U+F002) so the bytes are deterministic.
test_layout_query_active_nerd_font_icon() {
	lp_layout_seed $'alpha\nlogs-prod' "l" 0
	tmux set-option -g @livepicker-nerd-fonts "on"
	local out
	out="$("$LIVEPICKER_SCRIPTS/renderer.sh")"
	# the U+F002 glyph (ef 80 82) appears right before the query 'l':
	assert_contains "$out" "#[fg=default,bg=default]$(_icon_bytes)l#[default]" \
		"nerd-on: search icon (U+F002) emitted before the query"
	assert_contains "$out" "$(_icon_bytes)" "nerd-on: the raw U+F002 bytes are present"
}
# the default icon glyph as raw bytes (ANSI-C $'\uf002' -> ef 80 82). Kept in a helper
# so the assertion reads cleanly and the byte source is documented in one place.
_icon_bytes() { printf '%s' $'\uf002'; }

# (c) PRD §19 §3.33 / §15.28: overflow -> +N> on the right where N = TOTAL hidden
# (left+right combined); scroll 0 -> NO left indicator. 8 tabs of width 5 = 47 cols;
# width 20 -> 3 visible -> 5 hidden -> "+5>".
test_layout_overflow_right_indicator() {
	lp_layout_seed $'aaaaa\nbbbbb\nccccc\nddddd\neeeee\nfffff\nggggg\nhhhhh' "" 0
	tmux set-option -g @livepicker-client-width "20"
	tmux set-option -g @livepicker-scroll "0"
	local out
	out="$("$LIVEPICKER_SCRIPTS/renderer.sh")"
	# +5> = total hidden (8 total - 3 visible = 5); styled as chrome (FG/BG):
	assert_contains "$out" "#[fg=default,bg=default]+5>#[default]" "overflow-right: +5> (total hidden=5), styled chrome"
	# scroll 0 -> NO left indicator:
	case "$out" in *"<"*) fail "overflow-right: '<' present at scroll 0 (want absent)" ;; esac
}

# (c) PRD §19 §3.33: scroll > 0 -> the left indicator '<' appears (presence-only, no
# count). scroll 3 -> visible starts at index 3; hidden_left=3, hidden_right=3 -> +6>.
test_layout_overflow_left_indicator() {
	lp_layout_seed $'aaaaa\nbbbbb\nccccc\nddddd\neeeee\nfffff\nggggg\nhhhhh' "" 3
	tmux set-option -g @livepicker-client-width "20"
	tmux set-option -g @livepicker-scroll "3"
	local out
	out="$("$LIVEPICKER_SCRIPTS/renderer.sh")"
	# both indicators: '<' (left, presence-only) + '+6>' (right, total hidden=3+3):
	assert_contains "$out" "#[fg=default,bg=default]<#[default]" "overflow-left: '<' present (scroll>0)"
	assert_contains "$out" "+6>" "overflow-left: +6> (hidden_left 3 + hidden_right 3)"
	# the highlighted tab (index 3 = ddddd) is in the visible slice:
	assert_contains "$out" "#[fg=black,bg=yellow]ddddd#[default]" "overflow-left: highlight (ddddd) visible"
}

# (c) PRD §19 §3.33: when the tabs fit, NEITHER indicator shows.
test_layout_overflow_fits_no_indicators() {
	lp_layout_seed $'alpha\nbeta\ngamma' "" 0
	tmux set-option -g @livepicker-client-width "80"   # plenty -> everything fits
	local out
	out="$("$LIVEPICKER_SCRIPTS/renderer.sh")"
	case "$out" in *"+">"") : ;; *) fail "fits: '+N>' present (want neither indicator)" ;; esac
	case "$out" in *"<"*) fail "fits: '<' present (want neither indicator)" ;; esac
	# sanity: the tabs ARE rendered (fits is not an empty-output bug):
	assert_contains "$out" "alpha" "fits: tabs still rendered"
}

# (c)+(b) PRD §19: overflow WITH a query active -> the query bar is pinned at column 0
# AND the overflow indicators apply to the tab region. Seed s0..s9 (all match 's'),
# narrow width, nerd off. Assert the query bar + +N>; scroll>0 variant -> '<'.
test_layout_overflow_with_query_active() {
	lp_layout_seed "$(printf 's0\ns1\ns2\ns3\ns4\ns5\ns6\ns7\ns8\ns9')" "s" 0
	tmux set-option -g @livepicker-client-width "14"   # T = 14-3(query block) = 11 -> overflow
	tmux set-option -g @livepicker-scroll "0"
	local out
	out="$("$LIVEPICKER_SCRIPTS/renderer.sh")"
	# the query bar is pinned left: icon(empty)+query 's'+#[default]+2-space gap:
	assert_contains "$out" "#[fg=default,bg=default]s#[default]  " "overflow+query: query bar pinned at column 0"
	# the tab region overflows -> +N>:
	case "$out" in *"+">"") : ;; *) fail "overflow+query: '+N>' absent (want overflow indicator)" ;; esac
	# scroll > 0 -> the left indicator '<' appears in the query-active layout too:
	tmux set-option -g @livepicker-scroll "3"
	tmux set-option -g @livepicker-index "3"
	local out2
	out2="$("$LIVEPICKER_SCRIPTS/renderer.sh")"
	assert_contains "$out2" "#[fg=default,bg=default]<#[default]" "overflow+query scroll>0: '<' present"
}

# (d) PRD §19 §3.34: no-match -> <icon><query> (no match). Plain-ASCII marker regardless
# of nerd-font mode. NO tabs, NO indicators.
test_layout_no_match() {
	lp_layout_seed $'alpha\nbeta' "zzz" 0
	local out
	out="$("$LIVEPICKER_SCRIPTS/renderer.sh")"
	assert_contains "$out" " (no match)" "no-match: ' (no match)' marker present"
	assert_contains "$out" "#[fg=default,bg=default]zzz (no match)#[default]" "no-match: full <query> (no match) segment"
	# NO tabs, NO indicators:
	case "$out" in *alpha*) fail "no-match: tab 'alpha' leaked (want no tabs)" ;; esac
	case "$out" in *beta*) fail "no-match: tab 'beta' leaked (want no tabs)" ;; esac
	case "$out" in *">"*) fail "no-match: overflow indicator leaked (want none)" ;; esac
}

# (e) PRD §15.28 / P1.M2.T3.S1: the index/total count is GONE ENTIRELY. Sweep every
# layout state and assert NONE contains a [digit]/[digit] pattern (the old [0/5] form).
test_layout_no_count_anywhere() {
	local outs=""
	# empty:
	lp_layout_seed $'alpha\nbeta\ndriver' "" 0
	outs="$outs|$("$LIVEPICKER_SCRIPTS/renderer.sh")"
	# query active:
	lp_layout_seed $'alpha\nlogs-prod\nblog-engine' "l" 0
	outs="$outs|$("$LIVEPICKER_SCRIPTS/renderer.sh")"
	# no-match:
	lp_layout_seed $'alpha\nbeta' "zzz" 0
	outs="$outs|$("$LIVEPICKER_SCRIPTS/renderer.sh")"
	# overflow:
	lp_layout_seed $'aaaaa\nbbbbb\nccccc\nddddd\neeeee\nfffff\nggggg\nhhhhh' "" 0
	tmux set-option -g @livepicker-client-width "20"
	outs="$outs|$("$LIVEPICKER_SCRIPTS/renderer.sh")"
	# NONE of the captured outputs contains a [0-9]/[0-9] count pattern:
	if [[ $outs == *[0-9]/[0-9]* ]]; then
		fail "no-count: an index/total pattern (e.g. [0/5]) leaked into a layout state"
	fi
	# sanity: each state DID render (the sweep is not vacuous):
	[ -n "$outs" ] || fail "no-count: the sweep captured no output (vacuous)"
}

# (f) PRD §19 + §17: the window-status tab-style path STILL honors §19 — the query bar
# + viewport + overflow indicators — it does NOT fall back to the old full-line join.
# Seed both cached templates + a separator + many matching tabs + a narrow width.
test_layout_window_status_keeps_query_bar() {
	lp_layout_seed "$(printf 's0\ns1\ns2\ns3\ns4\ns5\ns6\ns7\ns8\ns9')" "s" 0
	tmux set-option -g @livepicker-tab-style "window-status"
	tmux set-option -gw window-status-separator "|"
	tmux set-option -g @livepicker-tab-current-tmpl  "#[fg=red,bold]__lp_tab__#[default]"
	tmux set-option -g @livepicker-tab-inactive-tmpl "#[fg=blue]__lp_tab__#[default]"
	tmux set-option -g @livepicker-client-width "14"
	local out
	out="$("$LIVEPICKER_SCRIPTS/renderer.sh")"
	# the query bar is present (§19 honored; NOT the old full-line join):
	assert_contains "$out" "#[fg=default,bg=default]s#[default]  " "window-status: query bar present (§19 honored)"
	# the tab region overflows -> +N>:
	case "$out" in *"+">"") : ;; *) fail "window-status: '+N>' absent (overflow not honored)" ;; esac
	# the tabs render through the CACHED template (the current styling, not plain):
	assert_contains "$out" "#[fg=red,bold]" "window-status: current-template styling applied"
	# the placeholder was fully swapped (§17 reader contract):
	case "$out" in *__lp_tab__*) fail "window-status: unswapped __lp_tab__ leaked" ;; esac
}

# (justify) PRD §19 §3.30: empty query + tabs fit -> tabs positioned per status-justify.
# centre -> leading pad (output starts with a space); left (default) -> no leading pad.
test_layout_status_justify_empty() {
	lp_layout_seed $'alpha\nbeta' "" 0
	tmux set-option -g @livepicker-client-width "40"
	# centre -> leading pad:
	tmux set-option -g status-justify centre
	local outc
	outc="$("$LIVEPICKER_SCRIPTS/renderer.sh")"
	case "$outc" in " "*) : ;; *) fail "justify centre: no leading pad (want output to start with a space)" ;; esac
	assert_contains "$outc" "alpha" "justify centre: tabs still rendered after the pad"
	# left (default) -> NO leading pad:
	tmux set-option -g status-justify left
	local outl
	outl="$("$LIVEPICKER_SCRIPTS/renderer.sh")"
	case "$outl" in " "*) fail "justify left: leading pad present (want none)" ;; *) : ;; esac
}
```

NOTE for the implementer: the block above is the COMPLETE, ready file body. Use it
as-is; the only allowed deviation is comment phrasing. Do NOT attach a client. Do NOT
seed live sessions for the list (seed `@livepicker-list`). Do NOT add ranking-order
assertions beyond "top match highlighted + non-match hidden". Do NOT duplicate the
`#`-escaping tests (test_functional.sh). Do NOT create any other file. The full suite
(`tests/run.sh`) is the gate — every `test_layout_*` must PASS alongside the existing
44-green suite (the new file only DEFINES functions; it touches no source).

### Integration Points

```yaml
DISCOVERY (how run.sh picks up the new file):
  - run.sh's `for f in "$CURRENT_DIR"/test_*.sh; do source "$f"; done` glob sources
    test_layout.sh, and `compgen -A function | grep '^test_'` discovers every
    test_layout_* function. No registration needed — just the filename + test_ prefix.

DEPENDENCIES (consumed — all COMPLETE):
  - tests/run.sh + tests/helpers.sh + tests/setup_socket.sh (the harness): provide
    setup_test/teardown_test, assert_eq/assert_contains/fail, TEST_STATUS, the
    isolated -L socket + PATH shim, $LIVEPICKER_SCRIPTS, baseline fixtures.
  - scripts/renderer.sh (P1.M2.* COMPLETE): the program under test.
  - scripts/layout.sh (lp_viewport) + scripts/rank.sh (lp_rank) + scripts/options.sh
    + scripts/state.sh: the renderer's sourced deps (all COMPLETE). The test does NOT
    source them — it writes @livepicker-* state directly (the renderer reads it).

PARALLEL / SIBLING BOUNDARIES (do NOT collide):
  - P1.M3.T2.S1 (parallel — scroll wiring in input-handler.sh): test_layout.sh tests
    the RENDERER's READING of @livepicker-scroll (the '<' indicator), NOT the input-
    handler's scroll-into-view WRITE. It sets @livepicker-scroll directly. No collision.
  - P1.M4.T2.S1 (test_ranking.sh — planned): owns ranking-ORDER assertions (prefix vs
    subsequence). test_layout.sh asserts only "top match highlighted + non-match hidden".
  - P1.M4.T3.S1 (scroll/client-width tests — planned): owns scroll-into-view mechanics.
    test_layout.sh owns the renderer's overflow-indicator LAYOUT.
  - test_functional.sh: owns the `#`-escaping renderer tests. test_layout.sh does not
    duplicate them.
  - test_appearance.sh: owns the §17 theme-resolution (sentinel writer + reader) tests.
    test_layout.sh's window-status test seeds the CACHE directly (the reader path) and
    asserts the §19 layout is shared — it does NOT drive the writer.

CONFIG / DATABASE / ROUTES: none. The only "config" the suite sets is @livepicker-*
state + (for the justify + window-status tests) the tmux session/global options
status-justify, window-status-separator — all on the isolated socket (torn down per test).
```

## Validation Loop

### Level 1: Syntax & Style (Immediate Feedback)

```bash
cd /home/dustin/.config/tmux/plugins/tmux-livepicker
bash -n tests/test_layout.sh && echo "OK: syntax"
shellcheck tests/test_layout.sh
# expect 0 findings (file-level disable=SC2154,SC2016,SC2034,SC2086 covers the run.sh-
# provided helpers/vars + the quoted case patterns). If SC1091 fires, add it to the
# disable line (test_appearance.sh did not need it; mirror its disable set).
# tabs-only (shfmt absent):
grep -nP '^ +[^#/]' tests/test_layout.sh && echo "WARN: space-indent (use tabs)" || echo "OK: tabs"
# the contract cases are all present:
for fn in test_layout_empty_query_tabs_only test_layout_query_active_structure \
  test_layout_query_gap_exact test_layout_query_active_nerd_font_icon \
  test_layout_overflow_right_indicator test_layout_overflow_left_indicator \
  test_layout_overflow_fits_no_indicators test_layout_overflow_with_query_active \
  test_layout_no_match test_layout_no_count_anywhere \
  test_layout_window_status_keeps_query_bar test_layout_status_justify_empty; do
  grep -q "^${fn}()" tests/test_layout.sh || echo "MISSING: $fn"
done
# Expected: syntax clean; shellcheck 0; tabs only; no MISSING.
```

### Level 2: Full suite (the gate — every test_layout_* passes + no regression)

```bash
cd /home/dustin/.config/tmux/plugins/tmux-livepicker
tests/run.sh
# Expected: exit 0; ALL green, including the ~11 new test_layout_* functions. The new
# file only DEFINES functions and is auto-discovered; it touches NO source, so the
# existing suite cannot regress. If a test_layout_* FAILS, read its ASSERT FAIL line
# (fail() prints the got/want diff to stderr) and compare against the captured output
# in research/test_layout_findings.md — the assertion string should match a captured
# byte-for-byte. Common fixes: (a) the seed did not pin the default colors -> re-check
# lp_layout_seed sets fg/bg/highlight-*; (b) width left at 0 for an overflow test ->
# set @livepicker-client-width; (c) nerd-fonts left on for a structure test -> the
# icon prefix shifts bytes -> set nerd-fonts off in the structure test.
# Isolate a single failing test for fast iteration:
#   source tests/setup_socket.sh; source tests/helpers.sh; source tests/test_layout.sh
#   setup_test "lp-debug"; test_layout_<name>; echo "STATUS=$TEST_STATUS"; teardown_test
```

### Level 3: Confirm the assertions match the captured ground-truth (read-only diff)

```bash
cd /home/dustin/.config/tmux/plugins/tmux-livepicker
# Re-run the research probe and eyeball that the live renderer output still matches the
# strings test_layout.sh asserts on (guards against a silent renderer change). If any
# captured byte differs from research/test_layout_findings.md, EITHER the renderer
# changed (update the test) OR the research is stale (re-capture).
source tests/setup_socket.sh; source tests/helpers.sh
setup_test "lp-diff"
tmux set-option -g @livepicker-type session
tmux set-option -g @livepicker-fg default; tmux set-option -g @livepicker-bg default
tmux set-option -g @livepicker-highlight-fg black; tmux set-option -g @livepicker-highlight-bg yellow
tmux set-option -g @livepicker-list $'aaaaa\nbbbbb\nccccc\nddddd\neeeee\nfffff\nggggg\nhhhhh'
tmux set-option -g @livepicker-filter ""; tmux set-option -g @livepicker-index 0
tmux set-option -g @livepicker-client-width 20; tmux set-option -g @livepicker-scroll 0
tmux set-option -g @livepicker-nerd-fonts off
echo "overflow-right (expect +5>, no <):"; "$LIVEPICKER_SCRIPTS/renderer.sh" | cat -A
tmux set-option -g @livepicker-scroll 3; tmux set-option -g @livepicker-index 3
echo "overflow-left (expect < and +6>):"; "$LIVEPICKER_SCRIPTS/renderer.sh" | cat -A
teardown_test
# Expected: the bytes match research OUT-c / OUT-c2 exactly (+5> / +6> / < chrome styling).
```

### Level 4: Creative & Domain-Specific Validation

```bash
cd /home/dustin/.config/tmux/plugins/tmux-livepicker
# Non-pollution confirmation (PRD §15 invariant): the new renderer-seed tests NEVER
# touch the user's real server. Confirm by diffing the real session list before/after
# a full run. (The harness isolates via -L; this is belt-and-braces.)
REAL_BEFORE="$(/usr/bin/tmux list-sessions -F '#{session_name}' 2>/dev/null | sort)"
tests/run.sh >/dev/null 2>&1
REAL_AFTER="$(/usr/bin/tmux list-sessions -F '#{session_name}' 2>/dev/null | sort)"
[ "$REAL_BEFORE" = "$REAL_AFTER" ] && echo "OK: real server untouched" || echo "FAIL: pollution"
# Expected: OK. The renderer-seed tests run on isolated -L sockets (setup_test -> setup_socket)
# and never call switch-client/display-message-against-a-real-client.

# Determinism check: run the suite twice; the pass count must be identical (no flaky
# async — renderer-seed tests have no client, no preview, no timing).
A="$(tests/run.sh 2>&1 | grep -E 'passed,'); tests/run.sh 2>&1 | grep -E 'passed,' | cmp -s <(echo "$A") - && echo "OK: deterministic" || echo "FAIL: flaky"
# Expected: OK (every test is a pure seed->render->assert; no races).
```

## Final Validation Checklist

### Technical Validation

- [ ] `bash -n tests/test_layout.sh` exits 0 with no output.
- [ ] `shellcheck tests/test_layout.sh` reports 0 findings (file-level disable covers it).
- [ ] No 4-space indents (`grep -Pn '^    '` is empty); tabs only.
- [ ] All ~12 `test_layout_*` functions present (Level 1 grep confirms; no MISSING).

### Feature Validation

- [ ] **(a)** empty query → tabs only; NO icon/`query>`/` (no match)`/`/`.
- [ ] **(b)** query `l` → query + EXACTLY 2-space gap + ranked tabs; top highlighted; non-match hidden.
- [ ] **(b-gap)** query-gap 4 → 4 spaces; 0 → zero spaces.
- [ ] **(b-icon)** nerd-fonts ON → U+F002 icon bytes present.
- [ ] **(c)** overflow → `+5>` (scroll 0, no `<`); `<` + `+6>` (scroll 3); neither when fits.
- [ ] **(c+b)** overflow + query → query bar + `+N>`; scroll>0 → `<`.
- [ ] **(d)** no-match → ` (no match)`; NO tabs.
- [ ] **(e)** NO `[0-9]/[0-9]` count pattern across empty/active/no-match/overflow.
- [ ] **(f)** window-status → query bar + overflow + current-template styling; no unswapped placeholder.
- [ ] **(justify)** centre → leading pad; left → none.
- [ ] `tests/run.sh` exit 0; existing suite still green (no source touched).

### Code Quality Validation

- [ ] Mirrors `test_appearance.sh`'s renderer-seed idiom (header, seed shape, assertion style).
- [ ] Signals failure ONLY via `fail`/`assert_*` (never exits / returns nonzero).
- [ ] Sources NOTHING at file scope; calls NO `setup_test`/`teardown_test` at file scope.
- [ ] Every assertion backed by a captured output in `research/test_layout_findings.md`.
- [ ] No duplication of ranking-order (test_ranking), scroll-mechanics (test_scroll), or
      `#`-escaping (test_functional) tests.
- [ ] TABS only; `set -u` inherited (not re-declared); file-level shellcheck disable.

### Documentation & Deployment

- [ ] Header documents: purpose (§19/§15.28), the SOURCED-by-run.sh contract, the
      renderer-only/no-client approach, the scope boundary (layout only).
- [ ] No README/CHANGELOG edit here (Mode-B docs sync is P4.T1).
- [ ] No source file touched; no other test file touched.

---

## Anti-Patterns to Avoid

- ❌ Don't attach a client (`attach_test_client`). The renderer is PURE and
  client-independent; seeding state + running renderer.sh + asserting stdout is the
  whole test (codebase_patterns §P8). A client adds races + a pty dependency for nothing.
- ❌ Don't forget to pin the §11 default colors in the seed. The isolated socket
  sources the user tmux.conf → `@livepicker-fg "#ffffff"` is dormant. Without the pin,
  the byte-exact assertions (`#[fg=default,bg=default]`, `#[fg=black,bg=yellow]`) FAIL.
  This is exactly why `lp_appearance_seed` exists — mirror it.
- ❌ Don't leave `@livepicker-client-width` unset/0 for an overflow test. Width 0 is the
  renderer's NO-WINDOWING path (full list, no indicators). The overflow tests MUST set a
  narrow width (e.g. 20 / 14). Conversely, the structure/empty/no-match tests SHOULD
  leave width 0 so they assert the full list (the seed sets it).
- ❌ Don't leave `@livepicker-nerd-fonts` ON for a structure test. The icon glyph shifts
  the bytes (the query block gains a 3-byte prefix). Set nerd-fonts OFF in the structure
  / gap / overflow tests (the seed does); turn it ON only for the dedicated icon test.
- ❌ Don't assert an EXACT full-line string for the overflow tests. The visible-slice
  composition depends on `lp_viewport`'s exact cumwidth math (tab widths + separators);
  a brittle full-line assert_eq will flake if a tab width changes. Assert the INDICATOR
  substrings (`+5>`, `<`) and the highlight's presence — not the whole line.
- ❌ Don't duplicate ranking-order assertions. "logs-prod outranks blog-engine" is
  test_ranking.sh's job (P1.M4.T2). test_layout asserts only "the top match is
  highlighted + a non-match is hidden" — enough to prove the layout, not the ranker.
- ❌ Don't duplicate scroll-into-view mechanics. Setting `@livepicker-scroll` directly
  (to exercise the renderer's `<` indicator) is a LAYOUT test; driving input-handler.sh
  nav is P1.M4.T3. Don't blur the seam.
- ❌ Don't duplicate the `#`-escaping tests. `test_functional.sh::test_renderer_escapes_hash_*`
  owns them. Adding one here is harmless scope creep; the contract item list (a-f) doesn't include it.
- ❌ Don't seed live sessions for the list. The renderer reads `@livepicker-list`, NOT
  list-sessions. Seed `tmux set-option -g @livepicker-list "$(printf 's0\n...')"`.
- ❌ Don't call `exit` or `return` nonzero in a test body — run.sh reads `TEST_STATUS` in
  the CURRENT shell; an exit kills the runner. Signal failure ONLY via `fail`/`assert_*`.
- ❌ Don't use 4-space indent — TABS only (mirror test_appearance.sh).

---

## Confidence Score

**9 / 10** for one-pass success. Rationale: the deliverable is a single sourced test
file whose complete body is given verbatim in the Implementation Blueprint, and it
mirrors a shipped, working template (`test_appearance.sh`) structure-for-structure
(header, shellcheck disable, `lp_*_seed` helper, `test_*` bodies that seed → run
renderer.sh → `assert_contains`). The decisive de-risking: **every assertion string is
a captured renderer output** (research/test_layout_findings.md, recorded 2026-07-07 by
running the real renderer under the real harness) — the author is encoding OBSERVED
behavior, not predicting it. The four renderer emit sites (no-match / empty-fits /
empty-overflow / query-active) are read in full from `scripts/renderer.sh`, and the
seed pinning (default colors + width 0 + nerd off) matches `test_appearance.sh`'s
proven approach. The only tests that "compose" rather than copy (overflow-with-query,
window-status-overflow, justify) reuse the verified renderer FORMAT STRINGS
(`printf '%s' "#[fg=$FG,bg=$BG]${icon}${esc_filter}#[default]${gap}${left_ind}${tabs}${right_ind}"`
+ the leading-pad emulation), so their assertions are sound by construction. Residual
risks: (a) a brittle full-line `assert_eq` on an overflow test — mitigated by the
"assert indicator substrings, not the whole line" rule (Anti-Pattern); (b) the
status-justify `-g` vs `-gw` option-type subtlety — mitigated by the STRUCTURAL
assertion (leading-space present/absent), not an exact pad count; (c) the U+F002 icon
bytes under a non-UTF-8 locale — mitigated by the dedicated icon test being the ONLY
one that turns nerd-fonts on, and `$'\uf002'` being the documented default. All
residual risks are deterministically caught by Level 2 (the full-suite gate) with a
precise `fail()` diff pointing at the offending assertion.
