# PRP — P1.M4.T2.S1: tests/test_ranking.sh — fuzzy ranking integration suite

---

## Goal

**Feature Goal**: Create `tests/test_ranking.sh` — a **fuzzy-ranking** validation
suite for `scripts/rank.sh::lp_rank` (PRD §20) that proves the five contract
behaviors and locks the §15.28 ranking items: **(a)** prefix bonus beats deep
subsequence; **(b)** a non-subsequence name is hidden entirely; **(c)** empty
filter preserves original tmux order byte-for-byte; **(d)** **no-drift** — the
renderer, next-session, prev-session, and confirm all resolve the SAME
`ranked[index]` because they share the single `lp_rank` source of truth; **(e)**
**performance** — `lp_rank` is O(N·Q) pure bash with NO per-name subshell (the
hard guard is a source grep; a generous timing bound is secondary). It also adds
cheap §15.28 edge coverage (stable tie-break, case-insensitive + case-preserved,
empty-list, quick-reject, word-boundary).

**Deliverable**: The single NEW file `tests/test_ranking.sh` (sourced by
`tests/run.sh` via its `test_*.sh` glob — NOT executed directly). It sources
`scripts/rank.sh` once (a pure leaf lib — no tmux, no side effects) so the four
**pure** tests (a,b,c,e + edges) call `lp_rank` directly with NO socket; the
**no-drift** test (d) additionally runs `scripts/renderer.sh` via the
renderer-seed idiom (seed `@livepicker-*` state on the per-test isolated socket,
capture stdout, assert the highlight). Defines a `lp_ranking_seed` helper +
~11 `test_ranking_*` functions. Every assertion is backed by a **captured
output** in `research/test_ranking_findings.md` — no guessed bytes.

**Success Definition**:
- `bash -n tests/test_ranking.sh` passes; `shellcheck tests/test_ranking.sh` is
  clean (file-level `# shellcheck disable=SC2154,SC2016,SC2034,SC2086`, mirroring
  `test_appearance.sh`/`test_layout.sh`).
- `tests/run.sh` discovers and runs every `test_ranking_*` function; the file
  adds ~11 passing tests and **does not break any existing test** (it touches no
  source — it only reads `scripts/rank.sh` + `scripts/renderer.sh`).
- Each contract case (a)–(e) has at least one passing test whose assertions match
  the captured outputs in `research/test_ranking_findings.md` exactly.
- The no-drift property is proven THREE ways (structural grep + determinism +
  renderer-highlight integration). The perf guard is the **source grep**
  (machine-independent) PLUS a generous timing bound.

## User Persona (if applicable)

**Target User**: The maintainer / CI (the suite runs under `tests/run.sh`). Mode A
(internal validation — no end-user surface). README (P4.T1) summarizes coverage.

**Use Case**: A change to `scripts/rank.sh` (scoring constants, match walk, sort)
or to a consumer's ranking call is made. `tests/run.sh` runs `test_ranking.sh`'s
functions (each on a fresh isolated socket); any regression — a reordered prefix
match, a hidden name leaking through, an empty-filter reorder, a consumer
diverging from the renderer's ranking, or an accidental per-name subshell
ballooning runtime — turns a specific assertion red with a precise diagnostic.

**User Journey**: `cd <repo> && tests/run.sh` → the runner sources
`setup_socket.sh` + `helpers.sh` + every `test_*.sh` (incl. the new
`test_ranking.sh`), discovers every `test_ranking_*` function, and runs each in a
per-test fresh-socket cycle (`setup_test "lp-$$-<name>"` → reset `TEST_STATUS` →
run → read `TEST_STATUS` → `teardown_test`). PASS/FAIL printed per test + summary.

**Pain Points Addressed**:
- (a) **Ranking regressions are silent.** A tweaked scoring constant can flip
  prefix-vs-subsequence ordering or stop hiding non-matches (breaking
  create-on-empty, PRD §6). This suite pins the order + hiding.
- (b) **No-drift is the core correctness invariant** (PRD §20: "what the renderer
  shows and what nav/confirm/… resolve can never drift"). Without a test, a
  consumer could re-implement filtering and silently disagree with the renderer.
  This suite proves all consumers call the SAME `lp_rank`.
- (c) **Empty-filter order is the §2 non-goal guard** ("no recency/MRU"). A
  ranking bug that reorders on empty query would violate it. The byte-identity
  test locks it.
- (d) **Perf regressions from subshells.** A `$()` slipped into the per-name loop
  makes N=300 take 300ms+ instead of ~20ms. The source grep catches it
  deterministically (no flaky timing).

## Why

- **§20 is the single source of truth for "what matches and in what order", and
  §15.28 enumerates the ranking items the suite must cover.** This task is the
  validation counterpart to the P1.M1.T1 ranker (COMPLETE) and the P1.M2 renderer
  rework (COMPLETE). It locks lp_rank's behavior so P2/P3 work (session mgmt,
  preview clip) cannot regress it.
- **lp_rank is a pure leaf function** (sources nothing, calls no tmux) — so four
  of the five contract cases are **direct unit tests** that run in microseconds
  with no socket (the work-item contract explicitly allows this: "test it directly
  by sourcing scripts/rank.sh and calling lp_rank (no tmux needed)"). Only the
  no-drift integration test needs the socket (it runs renderer.sh).
- **Every assertion is backed by a captured output.** The research file records
  the EXACT stdout `lp_rank` produces for each input (run against the real ranker
  on 2026-07-07), so the test author encodes observed behavior, not guesses.
- **Boundary respect.** This task creates ONE test file. It does NOT touch any
  source (`rank.sh`/`renderer.sh`/`input-handler.sh`), does NOT duplicate
  `test_layout.sh`'s §19-layout cases (that sibling explicitly defers
  ranking-order to this file), and does NOT cover scroll-into-view mechanics
  (that is `test_scroll`, P1.M4.T3). It covers RANKING only.

## What

A single NEW sourced test file at `tests/test_ranking.sh` that:

1. Declares the file-level shellcheck disable + documents the pure-leaf idiom
   (mirrors `test_appearance.sh`'s/`test_layout.sh`'s header).
2. **Sources `scripts/rank.sh` once** (guarded: `command -v lp_rank … || source`)
   so every test can call `lp_rank` directly. `$LIVEPICKER_SCRIPTS` (exported by
   `setup_socket.sh`, which `run.sh` sources before the test files) locates it.
3. Defines `lp_ranking_seed LIST [FILTER] [INDEX]` — pins the §11 default colors
   (fg/bg=default, highlight-fg=black, highlight-bg=yellow) + nerd-fonts OFF +
   tab-style plain + query-gap 2 + client-width 0 (full list, no viewport
   windowing) + scroll 0 + the list/filter/index. (Mirrors the sibling
   `lp_layout_seed`.)
4. Defines ~11 `test_ranking_*` functions (one per contract case + edges). The
   pure tests call `lp_rank` directly; the no-drift test seeds state and runs
   `"$LIVEPICKER_SCRIPTS/renderer.sh"`.
5. Signals failure ONLY via `fail`/`assert_*` (sets `TEST_STATUS`; never exits).

### Success Criteria

- [ ] `tests/test_ranking.sh` EXISTS; file-level `# shellcheck disable=SC2154,SC2016,SC2034,SC2086`.
- [ ] Sources `scripts/rank.sh` once (guarded) via `$LIVEPICKER_SCRIPTS`.
- [ ] `lp_ranking_seed LIST [FILTER] [INDEX]` defined (pins defaults + width 0).
- [ ] **(a)** `test_ranking_prefix_beats_subsequence`: `lp_rank` of
      `blog-engine\nlogs-prod\nalog` with `log` → first line == `logs-prod`.
- [ ] **(b)** `test_ranking_non_subsequence_hidden`: `xyz` (not a subsequence of
      `log`) is ABSENT from output (`grep -c '^xyz$'` == 0).
- [ ] **(c)** `test_ranking_empty_filter_preserves_order`: `lp_rank "$LIST" ''`
      == `$LIST` byte-for-byte (assert_eq) AND `diff` is clean.
- [ ] **(d)** three no-drift tests: (d1) every consumer (`renderer.sh`,
      `input-handler.sh`) calls `lp_rank` (grep); (d2) two `lp_rank` calls with
      identical args are byte-identical; (d3) `renderer.sh`'s visible highlight
      == `ranked[IDX]` for IDX=0 AND IDX=1.
- [ ] **(e)** `test_ranking_perf_no_per_name_subshell`: the `lp_rank` function
      BODY has NO command substitution (`grep -nE '\$\([^(]'` on the extracted
      body is empty — `$((` arithmetic is excluded); AND a 300-name few-match
      `lp_rank` call completes in < 200 ms (generous; `date +%s%N` skipped if
      unavailable).
- [ ] Edges: stable tie-break, case-insensitive + case-preserved, empty-list →
      empty output, quick-reject (name shorter than query), word-boundary order.
- [ ] `tests/run.sh` runs all `test_ranking_*` and they PASS; no existing test
      breaks.

## All Needed Context

### Context Completeness Check

_Pass_: A developer who has never seen this repo can implement the suite from
(a) the complete ready-to-paste `tests/test_ranking.sh` body in the
Implementation Blueprint, (b) the 11 live-verified findings in
`research/test_ranking_findings.md` — most critically FINDING 5 (the **perf
caveat**: the <50ms claim is about the O(N·Q) matching loop, NOT the O(M²)
selection sort — an all-300-matching fixture takes 480 ms BY DESIGN, so the perf
test MUST use a few-match filter), FINDING 6 (the grep invariant: extract the
`lp_rank` body and assert NO `$(` non-arithmetic inside it), and FINDING 9 (the
three no-drift proofs), and (c) the captured exact outputs for every assertion
(`logs-prod` first; `xyz` absent; empty-filter byte-identity; the
`#[fg=black,bg=yellow]<name>#[default]` highlight token). The function under test
(`lp_rank`) and the full harness (`run.sh`/`helpers.sh`/`setup_socket.sh`) are
COMPLETE. The sibling `test_layout.sh` (in-flight) is disjoint (§19 layout vs
§20 ranking).

### Documentation & References

```yaml
# MUST READ — the FUNCTION UNDER TEST. COMPLETE (P1.M1.T1.S1).
- file: scripts/rank.sh
  why: Defines lp_rank LIST FILTER — the pure fuzzy ranker this suite validates.
       SOURCED leaf lib (no tmux, no source-time side effects). Match = subsequence
       (every FILTER char in order, case-insensitive). Score: PREFIX(1000) >
       WORD_BOUNDARY(100) > CONTIGUITY(10) > -position. Stable tie-break on
       original order. Empty FILTER -> all names, original order. Empty LIST -> nothing.
  critical: lp_rank is PURE (no tmux) -> tests (a,b,c,e) source rank.sh and call it
            directly with NO socket. The O(M^2) selection sort dominates when MANY
            names match (480ms for 300 matches) — BY DESIGN; the perf test must use
            a FEW-match fixture (research FINDING 5).

# MUST READ — the test harness entry point. COMPLETE.
- file: tests/run.sh
  why: Sources setup_socket.sh + helpers.sh + every test_*.sh; discovers test_* via
       `compgen -A function | grep '^test_'`; runs each in a per-test fresh-socket
       cycle (setup_test -> reset TEST_STATUS -> run -> teardown_test). Exits 0 iff
       all pass. test_ranking.sh is SOURCED by run.sh (NOT executed); it must ONLY
       define test_* functions + helpers (no side effects on source).
  critical: Test bodies signal failure ONLY via fail/assert_* (which set TEST_STATUS
            in the CURRENT shell). NEVER exit/return-nonzero — that kills the runner.

# MUST READ — the assertion + setup helpers. COMPLETE.
- file: tests/helpers.sh
  why: Provides fail/pass/assert_eq/assert_contains + setup_test/teardown_test (thin
       delegates to setup_socket). setup_test brings up a FRESH isolated -L socket +
       baseline fixtures + pins @livepicker-preview-defer off. assert_contains uses
       `case` with "$sub" QUOTED (literal match, no glob, no subprocess).
  critical: assert_eq a b msg (POSIX =); assert_contains str sub msg (literal substring).
            Use these — do NOT invent new assert helpers.

# MUST READ — the socket-isolation layer. COMPLETE.
- file: tests/setup_socket.sh
  why: Exports $LIVEPICKER_SCRIPTS (= scripts/), $LIVEPICKER_ROOT, and the PATH shim
       so bare `tmux` hits the isolated -L socket. Provides attach_test_client (NOT
       needed here — renderer-seed tests need NO client).
  critical: $LIVEPICKER_SCRIPTS is the documented path to scripts/ — use it to source
            rank.sh and invoke renderer.sh (NOT a hardcoded relative path).

# MUST READ — the no-drift consumer (renderer). COMPLETE.
- file: scripts/renderer.sh
  why: The renderer is the no-drift integration target. It does
       `mapfile -t filtered < <(lp_rank "$LIST" "$FILTER")` then renders each tab;
       the current-index tab is wrapped in the HFG/HBG style:
       `#[fg=$HFG,bg=$HBG]<name>#[default]`. With nerd-fonts OFF + width unset(=0)
       it renders the FULL ranked list, so the highlight token is directly assertable.
  pattern: |
    mapfile -t filtered < <(lp_rank "$LIST" "$FILTER")
    seg="#[fg=$HFG,bg=$HBG]${esc_name}#[default]"   # current-index tab (plain style)
  gotcha: esc_name doubles '#' (`${name//\#/##}`). For names without '#', the token is
          exactly `#[fg=black,bg=yellow]<name>#[default]` (defaults HFG=black, HBG=yellow).
          The lp_ranking_seed helper SETS these defaults explicitly so the assertion is
          deterministic regardless of user config.

# MUST READ — the no-drift consumers (nav/confirm). COMPLETE.
- file: scripts/input-handler.sh
  why: next-session / prev-session / confirm / sync all do
       `mapfile -t filtered < <(lp_rank "$cur_list" "$cur_filter")` (lines 137, 297,
       326, 357) — IDENTICAL args to the renderer's call. This is the structural
       no-drift proof: every consumer shares lp_rank (no re-implementation).
  critical: session-mgmt.sh is P2 (not yet built); this test greps only the consumers
            that EXIST (renderer.sh + input-handler.sh).

# MUST READ — option defaults (for the renderer-seed highlight assertion).
- file: scripts/options.sh
  why: opt_highlight_fg() default "black"; opt_highlight_bg() default "yellow";
       opt_nerd_fonts() default "on" (MUST pin OFF for clean-ASCII assertions);
       opt_tab_style() default "plain"; opt_query_gap() default "2".
  critical: lp_ranking_seed sets @livepicker-highlight-fg=black, -highlight-bg=yellow,
            -nerd-fonts=off, -tab-style=plain, -query-gap=2, -client-width=0 explicitly
            so the renderer output is deterministic.

# MUST READ — the empirical ground-truth for THIS suite (11 live-verified findings).
- docfile: plan/003_77ef311abf10/P1M4T2S1/research/test_ranking_findings.md
  why: FINDING 1 (lp_rank is pure -> no socket for a/b/c/e); FINDING 2 (prefix score
       trace: logs-prod=1120 > blog-engine=19 = alog=19, stable); FINDING 3 (xyz
       hidden, grep -c 0); FINDING 4 (empty filter byte-identity + clean diff);
       FINDING 5 (PERF CAVEAT: 0/few-match ~19-36ms, ALL-300-match 480ms — the <50ms
       claim is the O(N*Q) matching loop, NOT the O(M^2) sort; use few-match fixture);
       FINDING 6 (grep invariant: extract lp_rank body, no `$(` non-arithmetic);
       FINDING 7 (stable tie-break); FINDING 8 (edges: empty/quick-reject/case/boundary);
       FINDING 9 (no-drift: structural grep + determinism + renderer highlight);
       FINDING 10 (harness conventions); FINDING 11 (disjoint from test_layout.sh).
  critical: Read BEFORE writing the perf test. FINDING 5 is the trap: a 300-name
            ALL-matching fixture + a <50ms gate WILL FAIL (480ms, by design). Use a
            few-match filter (s99 -> 3 matches) + a generous <200ms bound + the grep.

# MUST READ — the PRD sections selected for this work item.
- docfile: PRD.md
  why: §20 (filtering and ranking — the spec lp_rank implements: subsequence match,
       scoring PREFIX>boundary>contiguity>position, stable tie-break, empty-query
       original order, the lp_rank LIST FILTER interface, O(N*Q) perf, single source
       of truth so renderer/nav/confirm never drift); §2 non-goals (no MRU — empty
       query keeps tmux order); §15.28 (the validation items this suite covers).
  section: "§20 Filtering and ranking (fuzzy)", "§2 Non-goals", "§15 Validation (§3.28 Layout, ranking, scroll, and management)"

# MUST READ — the in-parallel sibling PRP (align conventions; confirm disjointness).
- docfile: plan/003_77ef311abf10/P1M4T1S1/PRP.md
  why: The sibling test_layout.sh establishes the conventions this file mirrors:
       file-level `# shellcheck disable=SC2154,SC2016,SC2034,SC2086`; set -u only;
       a lp_*_seed helper that pins §11 default colors + client-width 0; test_*_func
       naming; renderer-seed idiom (seed state -> bash renderer.sh -> assert on stdout).
       Its PRP explicitly states ranking-order is deferred to test_ranking.sh (THIS).
  section: "Goal" (the seed-helper + convention shape), "What" (the lp_layout_seed pattern)
```

### Current Codebase tree

```bash
tmux-livepicker/
  PRD.md
  plugin.tmux
  scripts/
    options.sh utils.sh state.sh layout.sh rank.sh   # COMPLETE libs. rank.sh = FUNCTION UNDER TEST.
    renderer.sh input-handler.sh preview.sh livepicker.sh restore.sh   # COMPLETE (consumers of lp_rank).
  tests/
    setup_socket.sh helpers.sh run.sh                 # COMPLETE harness (sourced by run.sh).
    test_self.sh test_functional.sh test_pollution.sh test_preview.sh test_restore.sh
    test_keyrepurpose.sh test_create.sh test_appearance.sh test_responsiveness.sh   # COMPLETE suites.
    test_layout.sh    # IN-FLIGHT (P1.M4.T1.S1, parallel) — §19 layout. DISJOINT from this file.
    test_ranking.sh   # <-- THIS TASK CREATES IT (§20 ranking).
  plan/003_77ef311abf10/{architecture, P1M4T1S1/PRP.md, P1M4T2S1/{PRP.md, research/}}  # THIS = P1M4T2S1.
```

### Desired Codebase tree with files to be added and responsibility of file

```bash
tmux-livepicker/
  tests/
    test_ranking.sh   # NEW (this task). Sourced by run.sh. Sources rank.sh once (pure leaf).
                      #   lp_ranking_seed LIST [FILTER] [INDEX] (pins defaults + width 0).
                      #   test_ranking_prefix_beats_subsequence      (a)
                      #   test_ranking_non_subsequence_hidden        (b)
                      #   test_ranking_empty_filter_preserves_order  (c)
                      #   test_ranking_no_drift_consumers_share_source (d-structural)
                      #   test_ranking_no_drift_deterministic        (d-determinism)
                      #   test_ranking_no_drift_renderer_highlight   (d-integration)
                      #   test_ranking_perf_no_per_name_subshell     (e)
                      #   test_ranking_stable_tiebreak / case_insensitive / empty_list_quick_reject / word_boundary  (edges)
```

### Known Gotchas of our codebase & Library Quirks

```bash
# CRITICAL (research FINDING 5): the <50ms perf claim is about the O(N*Q) MATCHING
# loop, NOT the O(M^2) selection sort. A 300-name list where ALL match takes ~480ms
# (the sort: 300^2 = 90k iterations) — BY DESIGN (rank.sh: "O(M^2), M small <100";
# PRD §3.40 "typical N < 100"). The perf test MUST use a FEW-match filter (s99 -> 3
# of 300) so it measures O(N*Q) (~19ms), with a GENEROUS bound (<200ms). NEVER build
# an all-matching fixture and gate on <50ms — it fails for a non-bug reason.

# CRITICAL (research FINDING 6): the hard perf guard is a SOURCE GREP, not timing
# (timing varies by machine). Extract the lp_rank FUNCTION BODY (sed from '^lp_rank()'
# to '^}$') and assert it contains NO command substitution that is not arithmetic:
#   grep -nE '\$\([^(]' on the body must be EMPTY. The pattern '\$\([([^]' matches
#   '$(' (real command substitution) but EXCLUDES '$((' (arithmetic). The ONLY real
# command substitution in rank.sh is the source-time CURRENT_DIR resolver (line 30),
# which is OUTSIDE lp_rank. Process substitution '<(...)' has no '$(' so it is not
# matched. Do NOT grep the whole file (the CURRENT_DIR line is a false positive).

# CRITICAL (research FINDING 1): lp_rank is a PURE leaf function (sources nothing,
# calls no tmux). Tests (a,b,c,e,edges) source rank.sh and call lp_rank directly —
# NO socket needed. Only the no-drift integration test (d3) needs setup_test (it runs
# renderer.sh, which reads state via tmux show-option). The harness still runs
# setup_test once per test_* (harmless; the socket is unused by the pure tests).

# GOTCHA: source rank.sh ONCE at file load, GUARDED:
#   command -v lp_rank >/dev/null 2>&1 || source "$LIVEPICKER_SCRIPTS/rank.sh"
# rank.sh defines LP_* constants as `readonly`; an unguarded double-source would error
# on re-definition. The guard makes it idempotent. $LIVEPICKER_SCRIPTS is exported by
# setup_socket.sh, which run.sh sources BEFORE the test files.

# GOTCHA (renderer-seed): for the no-drift highlight assertion, pin nerd-fonts OFF
# (@livepicker-nerd-fonts off) so the renderer emits clean ASCII (no U+F002 icon
# bytes), and client-width 0 (unset -> renderer reads 0 -> full list, no viewport
# windowing / no overflow indicators). Then the current-index tab token is exactly
# `#[fg=black,bg=yellow]<name>#[default]` (defaults via lp_ranking_seed). Use
# assert_contains on that exact substring (research FINDING 9c, verified on the
# synthetic string reconstructed from renderer.sh source).

# GOTCHA (harness): signal failure ONLY via fail/assert_* (sets TEST_STATUS). NEVER
# `exit` or `return-nonzero` to abort — run.sh reads TEST_STATUS in the CURRENT shell;
# an exit kills the whole runner. set -u ONLY (NOT -e/pipefail — tmux/grep legitimately
# return nonzero). TABS for indent; `local` for all function locals.

# GOTCHA (empty-filter byte-identity): lp_rank emits a trailing '\n' after EACH name
# (incl. last); `out="$(lp_rank "$LIST" '')"` strips trailing newlines, so `out` ==
# `LIST` exactly WHEN LIST has no trailing newline. assert_eq "$out" "$LIST" is the
# cleanest check. The `diff` form also works if LIST is newline-terminated consistently.

# GOTCHA (stable tie-break): the sort advances `best` ONLY on STRICTLY-greater score,
# so equal scores keep original order. To test it, use two names with IDENTICAL match
# positions (e.g. aaa-mlog / bbb-mlog, both pos[0]=4) -> output keeps input order.

# GOTCHA (naming): use `test_ranking_*` (sibling uses `test_layout_*`) so the two
# suites are visually distinct in run.sh output. Do NOT assert on §19 layout structure
# (gap/overflow/count) — that is test_layout.sh's domain. This file asserts RANKING.
```

## Implementation Blueprint

### Data models and structure

No data model. The file holds: a one-time `source` of rank.sh; the
`lp_ranking_seed` helper; and ~11 `test_ranking_*` functions. Each pure test uses
function-local `LIST`/`out`/`ranked` vars; the no-drift integration test seeds
`@livepicker-*` state and captures `renderer.sh` stdout. The assertion surface is
`assert_eq` / `assert_contains` / `fail` (from helpers.sh).

### Implementation Tasks (ordered by dependencies)

```yaml
Task 1: CREATE tests/test_ranking.sh — header + source rank.sh + lp_ranking_seed
  - FILE: ./tests/test_ranking.sh  (NEW; sourced by run.sh via its test_*.sh glob).
  - SHEBANG: #!/usr/bin/env bash
  - LINE 2 file-level shellcheck disable (mirror test_appearance.sh EXACTLY):
      # shellcheck disable=SC2154,SC2016,SC2034,SC2086
      #   SC2154: TEST_STATUS / setup_test / tmux / LIVEPICKER_SCRIPTS are provided by
      #           run.sh + helpers.sh + setup_socket.sh (sourced before this file).
      #   SC2016/SC2034/SC2086: the harness's eval/single-quote + word-split idioms.
  - set -u  (NOT -e; NOT -o pipefail).
  - SOURCE rank.sh ONCE, guarded (so the readonly LP_* consts are not redefined):
      command -v lp_rank >/dev/null 2>&1 || source "$LIVEPICKER_SCRIPTS/rank.sh"
  - DEFINE lp_ranking_seed:
      lp_ranking_seed() {
      	local list="${1:-}" filter="${2:-}" index="${3:-0}"
      	tmux set-option -g @livepicker-fg default
      	tmux set-option -g @livepicker-bg default
      	tmux set-option -g @livepicker-highlight-fg black
      	tmux set-option -g @livepicker-highlight-bg yellow
      	tmux set-option -g @livepicker-nerd-fonts off        # clean ASCII (no U+F002 icon)
      	tmux set-option -g @livepicker-tab-style plain
      	tmux set-option -g @livepicker-query-gap 2
      	tmux set-option -g @livepicker-type session
      	tmux set-option -g @livepicker-client-width 0        # width 0 -> full list, no viewport windowing
      	tmux set-option -g @livepicker-scroll 0
      	tmux set-option -g @livepicker-list "$list"
      	tmux set-option -g @livepicker-filter "$filter"
      	tmux set-option -g @livepicker-index "$index"
      }
  - STYLE: tabs; quote every expansion.

Task 2: PURE tests (a)(b)(c) + edges — call lp_rank directly (NO renderer/socket)
  - (a) test_ranking_prefix_beats_subsequence:
      LIST=$'blog-engine\nlogs-prod\nalog'; out="$(lp_rank "$LIST" 'log')"
      first="$(printf '%s\n' "$out" | head -1)"
      assert_eq "$first" 'logs-prod' "(a) prefix bonus ranks logs-prod first"
      # also assert the full order (logs-prod, blog-engine, alog — stable tie at 19):
      assert_eq "$out" $'logs-prod\nblog-engine\nalog' "(a) full ranked order"
  - (b) test_ranking_non_subsequence_hidden:
      LIST=$'blog-engine\nlogs-prod\nalog\nxyz'; out="$(lp_rank "$LIST" 'log')"
      cnt="$(printf '%s\n' "$out" | grep -c '^xyz$')"
      assert_eq "$cnt" '0' "(b) non-subsequence 'xyz' hidden (grep count)"
      # also: output still has the 3 matches in ranked order:
      assert_eq "$out" $'logs-prod\nblog-engine\nalog' "(b) matches intact"
  - (c) test_ranking_empty_filter_preserves_order:
      LIST=$'gamma\nalpha\nbeta'; out="$(lp_rank "$LIST" '')"
      assert_eq "$out" "$LIST" "(c) empty filter byte-identical to LIST (order preserved)"
      diff <(printf '%s\n' "$LIST") <(lp_rank "$LIST" '') >/dev/null \
        || fail "(c) diff not clean (empty filter reordered)"
  - edges (cheap, pure):
      - test_ranking_stable_tiebreak: LIST=$'aaa-mlog\nbbb-mlog'; both pos[0]=4 (equal score);
        out="$(lp_rank "$LIST" 'mlog')"; assert_eq "$out" "$LIST" "stable tie keeps original order"
      - test_ranking_case_insensitive_preserves_case: out="$(lp_rank 'LOGS-Prod' 'log')";
        assert_eq "$out" 'LOGS-Prod' "case-insensitive match; original case preserved in output"
      - test_ranking_empty_list: assert lp_rank '' 'x' and lp_rank '' '' both produce empty out
      - test_ranking_quick_reject: 'ab' vs 'abc' (nlen<qlen) -> 'ab' absent (grep -c '^ab$' == 0)
      - test_ranking_word_boundary: LIST=$'my-log\nxlog'; out=lp_rank "$LIST" 'log';
        first==head -1; assert_eq "$first" 'my-log' "word-boundary (after '-') ranks my-log first"

Task 3: NO-DRIFT tests (d) — structural + determinism + renderer integration
  - (d1) test_ranking_no_drift_consumers_share_source:
      grep -q 'lp_rank' "$LIVEPICKER_SCRIPTS/renderer.sh"      || fail "renderer does not call lp_rank"
      grep -q 'lp_rank' "$LIVEPICKER_SCRIPTS/input-handler.sh" || fail "input-handler does not call lp_rank"
      pass "no-drift: renderer + nav/confirm share lp_rank (single source of truth)"
  - (d2) test_ranking_no_drift_deterministic:
      LIST=$'blog-engine\nlogs-prod\nalog'; a="$(lp_rank "$LIST" 'log')"; b="$(lp_rank "$LIST" 'log')"
      assert_eq "$a" "$b" "no-drift: lp_rank deterministic (two calls byte-identical)"
  - (d3) test_ranking_no_drift_renderer_highlight  (NEEDS setup_test — uses renderer.sh):
      LIST=$'blog-engine\nlogs-prod\nalog'
      mapfile -t ranked < <(lp_rank "$LIST" 'log')      # canonical (single source of truth)
      # IDX=0 -> renderer highlights ranked[0] (== confirm target)
      lp_ranking_seed "$LIST" 'log' 0
      raw0="$(bash "$LIVEPICKER_SCRIPTS/renderer.sh")"
      assert_contains "$raw0" "#[fg=black,bg=yellow]${ranked[0]}#[default]" \
        "no-drift: renderer highlights ranked[0] (== lp_rank top match / confirm target)"
      # IDX=1 (next-session moved) -> renderer highlights ranked[1] (same ranked array)
      lp_ranking_seed "$LIST" 'log' 1
      raw1="$(bash "$LIVEPICKER_SCRIPTS/renderer.sh")"
      assert_contains "$raw1" "#[fg=black,bg=yellow]${ranked[1]}#[default]" \
        "no-drift: renderer highlights ranked[1] after index move (== next-session highlight)"

Task 4: PERF test (e) — hard grep invariant + generous timing bound
  - test_ranking_perf_no_per_name_subshell:
      rank="$LIVEPICKER_SCRIPTS/rank.sh"
      # HARD invariant: the lp_rank FUNCTION BODY has NO command substitution
      # (only $(( arithmetic) + parameter expansion + <() process sub). Extract the
      # body and grep for '$(' not immediately followed by '(' (excludes arithmetic).
      body="$(sed -n '/^lp_rank()/,/^}$/p' "$rank")"
      bad="$(printf '%s' "$body" | grep -nE '\$\([^(]' || true)"
      [ -z "$bad" ] || fail "perf: lp_rank body has command substitution (per-name subshell?): $bad"
      pass "perf: no command substitution in the lp_rank per-name loop (hard invariant)"
      # TIMING (generous; measures O(N*Q) matching loop with a FEW-match filter, NOT the
      # O(M^2) sort — all-match would be ~480ms by design; research FINDING 5).
      big="$(seq -f 'sess-%g' 1 300)"          # 300 distinct names, one process
      m="$(lp_rank "$big" 's99' | grep -c .)"
      assert_eq "$m" '3' "perf fixture: 's99' matches exactly 3 of 300 (measures O(N*Q), not O(M^2))"
      if date +%s%N >/dev/null 2>&1; then
        best=999999
        for run in 1 2 3 4 5; do
          t0=$(date +%s%N); lp_rank "$big" 's99' >/dev/null; t1=$(date +%s%N)
          ms=$(( (t1 - t0) / 1000000 )); [ "$ms" -lt "$best" ] && best=$ms
        done
        pass "perf: lp_rank(300, few-match) min ${best}ms (generous bound 200ms)"
        [ "$best" -lt 200 ] || fail "perf: lp_rank(300,few-match) took ${best}ms (want <200; subshell regression?)"
      else
        pass "perf: date +%s%N unavailable; grep invariant above is the hard guard"
      fi

Task 5: VALIDATE (Level 1 + run the suite)
  - RUN: bash -n tests/test_ranking.sh            (expect exit 0, no output)
  - RUN: shellcheck tests/test_ranking.sh         (expect 0 findings)
  - RUN: grep -Pn '^    ' tests/test_ranking.sh   (expect empty — tabs only)
  - RUN: tests/run.sh                             (expect: all test_ranking_* PASS; no existing test FAILS)
```

### Implementation Patterns & Key Details

The complete, ready-to-paste file body (the implementer may use it as-is; the
only allowed deviation is comment phrasing):

```bash
#!/usr/bin/env bash
# shellcheck disable=SC2154,SC2016,SC2034,SC2086
#   SC2154: TEST_STATUS / fail / assert_* / setup_test / tmux / LIVEPICKER_SCRIPTS
#           are provided by run.sh + helpers.sh + setup_socket.sh (sourced before
#           this file by run.sh). SC2016/SC2034/SC2086: the harness's eval/single-
#           quote + word-split idioms (mirrors test_appearance.sh / test_layout.sh).
# tests/test_ranking.sh — tmux-livepicker fuzzy-ranking validation suite (PRD §20,
# §15.28). Validates scripts/rank.sh::lp_rank: (a) prefix>subsequence, (b) hidden,
# (c) empty-filter order, (d) no-drift (renderer/nav/confirm share lp_rank), (e)
# perf (O(N*Q), no per-name subshell). lp_rank is a PURE leaf function (sources
# nothing, calls no tmux) -> the pure tests source rank.sh and call lp_rank directly
# (NO socket); only the no-drift integration test runs renderer.sh (renderer-seed
# idiom). See research/test_ranking_findings.md for the captured outputs behind
# every assertion.

set -u   # NOT -e (tmux/grep legitimately return nonzero); NOT -o pipefail.

# Source the function under test ONCE (guarded: rank.sh defines LP_* as readonly;
# an unguarded re-source would error). $LIVEPICKER_SCRIPTS is exported by
# setup_socket.sh, which run.sh sources before the test files.
command -v lp_rank >/dev/null 2>&1 || source "$LIVEPICKER_SCRIPTS/rank.sh"

# lp_ranking_seed LIST [FILTER] [INDEX] — pin the §11 defaults so renderer-seed
# assertions are deterministic (highlight token == #[fg=black,bg=yellow]<name>#[default]).
# client-width 0 -> renderer renders the FULL ranked list (no viewport windowing).
# Mirrors the sibling test_layout.sh::lp_layout_seed.
lp_ranking_seed() {
	local list="${1:-}" filter="${2:-}" index="${3:-0}"
	tmux set-option -g @livepicker-fg default
	tmux set-option -g @livepicker-bg default
	tmux set-option -g @livepicker-highlight-fg black
	tmux set-option -g @livepicker-highlight-bg yellow
	tmux set-option -g @livepicker-nerd-fonts off        # clean ASCII (no U+F002 icon bytes)
	tmux set-option -g @livepicker-tab-style plain
	tmux set-option -g @livepicker-query-gap 2
	tmux set-option -g @livepicker-type session
	tmux set-option -g @livepicker-client-width 0        # width 0 -> full list, no viewport windowing
	tmux set-option -g @livepicker-scroll 0
	tmux set-option -g @livepicker-list "$list"
	tmux set-option -g @livepicker-filter "$filter"
	tmux set-option -g @livepicker-index "$index"
}

# (a) PRD §3.37: prefix bonus (1000) beats a deep subsequence. logs-prod (pos0,
# score 1120) ranks above blog-engine (pos1, score 19) and alog (pos1, score 19).
# blog-engine before alog: stable tie-break keeps original tmux order (score 19==19).
test_ranking_prefix_beats_subsequence() {
	local LIST=$'blog-engine\nlogs-prod\nalog'
	local out first
	out="$(lp_rank "$LIST" 'log')"
	first="$(printf '%s\n' "$out" | head -1)"
	assert_eq "$first" 'logs-prod' "(a) prefix bonus ranks logs-prod first"
	assert_eq "$out" $'logs-prod\nblog-engine\nalog' "(a) full ranked order (stable tie at score 19)"
}

# (b) PRD §3.36: a non-subsequence is HIDDEN entirely (so create-on-empty fires).
# 'xyz' has no 'l' -> not a subsequence of 'log' -> absent from output.
test_ranking_non_subsequence_hidden() {
	local LIST=$'blog-engine\nlogs-prod\nalog\nxyz'
	local out cnt
	out="$(lp_rank "$LIST" 'log')"
	cnt="$(printf '%s\n' "$out" | grep -c '^xyz$')"
	assert_eq "$cnt" '0' "(b) non-subsequence 'xyz' hidden (grep count == 0)"
	assert_eq "$out" $'logs-prod\nblog-engine\nalog' "(b) the 3 matches intact + ranked"
}

# (c) PRD §3.38 + §2 non-goal: empty FILTER -> ALL names at score 0 in ORIGINAL
# tmux order (no reordering; no MRU). Byte-identical to LIST after $() normalization.
test_ranking_empty_filter_preserves_order() {
	local LIST=$'gamma\nalpha\nbeta'
	local out
	out="$(lp_rank "$LIST" '')"
	assert_eq "$out" "$LIST" "(c) empty filter byte-identical to LIST (original order preserved)"
	# diff form ( belt-and-braces): left re-terminates LIST; right is lp_rank's terminated output.
	diff <(printf '%s\n' "$LIST") <(lp_rank "$LIST" '') >/dev/null \
		|| fail "(c) diff not clean (empty filter reordered the list)"
	pass "(c) diff clean"
}

# (d1) STRUCTURAL no-drift: every consumer calls lp_rank (single source of truth),
# not a re-implementation. renderer.sh + input-handler.sh (next/prev/confirm/sync).
test_ranking_no_drift_consumers_share_source() {
	grep -q 'lp_rank' "$LIVEPICKER_SCRIPTS/renderer.sh" \
		|| fail "no-drift: renderer.sh does not call lp_rank (re-implemented filter?)"
	grep -q 'lp_rank' "$LIVEPICKER_SCRIPTS/input-handler.sh" \
		|| fail "no-drift: input-handler.sh does not call lp_rank (nav/confirm diverge?)"
	pass "no-drift: renderer + nav/confirm/prev/sync share lp_rank (PRD §20 single source of truth)"
}

# (d2) DETERMINISM no-drift: lp_rank is a pure function -> identical input gives
# identical output, so the renderer's ranked == nav's ranked == confirm's ranked.
test_ranking_no_drift_deterministic() {
	local LIST=$'blog-engine\nlogs-prod\nalog'
	local a b
	a="$(lp_rank "$LIST" 'log')"
	b="$(lp_rank "$LIST" 'log')"
	assert_eq "$a" "$b" "no-drift: lp_rank deterministic (two calls byte-identical)"
}

# (d3) INTEGRATION no-drift: the renderer's VISIBLE highlight == lp_rank's ranked[IDX]
# (what the user sees == what confirm targets == what next-session moves to). Uses the
# renderer-seed idiom (setup_test brought up the isolated socket). IDX=0 -> ranked[0];
# IDX=1 (next-session moved) -> ranked[1] (same ranked array, no drift).
test_ranking_no_drift_renderer_highlight() {
	local LIST=$'blog-engine\nlogs-prod\nalog'
	local -a ranked
	local raw0 raw1
	mapfile -t ranked < <(lp_rank "$LIST" 'log')   # canonical: single source of truth
	# IDX=0: renderer highlights ranked[0] (== confirm target).
	lp_ranking_seed "$LIST" 'log' 0
	raw0="$(bash "$LIVEPICKER_SCRIPTS/renderer.sh")"
	assert_contains "$raw0" "#[fg=black,bg=yellow]${ranked[0]}#[default]" \
		"no-drift: renderer highlights ranked[0] (${ranked[0]}) == lp_rank top / confirm target"
	# IDX=1 (next-session moved the index): renderer highlights ranked[1] (same array).
	lp_ranking_seed "$LIST" 'log' 1
	raw1="$(bash "$LIVEPICKER_SCRIPTS/renderer.sh")"
	assert_contains "$raw1" "#[fg=black,bg=yellow]${ranked[1]}#[default]" \
		"no-drift: renderer highlights ranked[1] (${ranked[1]}) after index move (== next-session)"
}

# (e) PERF: O(N*Q) pure bash, NO per-name subshell. The HARD guard is a source grep
# (machine-independent): the lp_rank FUNCTION BODY has NO command substitution (only
# $(( arithmetic + ${} expansion + <() process sub). Timing is secondary + generous
# (research FINDING 5: the <50ms claim is the O(N*Q) matching loop, NOT the O(M^2)
# sort — all-300-match is ~480ms BY DESIGN; so we use a FEW-match fixture).
test_ranking_perf_no_per_name_subshell() {
	local rank="$LIVEPICKER_SCRIPTS/rank.sh"
	# HARD invariant: extract the lp_rank body; assert NO '$(' non-arithmetic inside.
	local body bad
	body="$(sed -n '/^lp_rank()/,/^}$/p' "$rank")"
	bad="$(printf '%s' "$body" | grep -nE '\$\([^(]' || true)"   # excludes '$((' arithmetic
	[ -z "$bad" ] || fail "perf: lp_rank body has command substitution (per-name subshell?): $bad"
	pass "perf: no command substitution in lp_rank body (hard invariant — O(N*Q), no per-name subshell)"
	# TIMING: 300 names, few-match filter (s99 -> 3 matches) measures O(N*Q), not O(M^2).
	local big m t0 t1 ms run best
	big="$(seq -f 'sess-%g' 1 300)"                # 300 distinct names (one process)
	m="$(lp_rank "$big" 's99' | grep -c .)"
	assert_eq "$m" '3' "perf fixture: 's99' matches exactly 3 of 300 (few-match -> measures O(N*Q))"
	if date +%s%N >/dev/null 2>&1; then
		best=999999
		for run in 1 2 3 4 5; do
			t0=$(date +%s%N); lp_rank "$big" 's99' >/dev/null; t1=$(date +%s%N)
			ms=$(( (t1 - t0) / 1000000 )); [ "$ms" -lt "$best" ] && best=$ms
		done
		pass "perf: lp_rank(300, few-match) min ${best}ms (generous bound 200ms)"
		[ "$best" -lt 200 ] || fail "perf: lp_rank(300,few-match) took ${best}ms (want <200; subshell regression?)"
	else
		pass "perf: date +%s%N unavailable here; the grep invariant above is the hard guard"
	fi
}

# --- cheap §15.28 edge coverage (pure lp_rank, no socket) ---

# Stable tie-break (PRD §3.37): equal scores keep ORIGINAL tmux order. aaa-mlog and
# bbb-mlog both match 'mlog' at pos[0]=4 (identical score) -> input order preserved.
test_ranking_stable_tiebreak() {
	local LIST=$'aaa-mlog\nbbb-mlog'
	local out
	out="$(lp_rank "$LIST" 'mlog')"
	assert_eq "$out" "$LIST" "stable tie-break: equal scores keep original tmux order"
}

# Case-insensitive match (PRD §3.36); ORIGINAL case preserved in output (low_name is
# used only for matching/scoring; the printed token is the original name).
test_ranking_case_insensitive_preserves_case() {
	local out
	out="$(lp_rank 'LOGS-Prod' 'log')"
	assert_eq "$out" 'LOGS-Prod' "case-insensitive match; original case preserved in output"
}

# Empty LIST -> empty output (rank.sh: m==0 -> return 0, prints nothing).
test_ranking_empty_list_outputs_nothing() {
	local out
	out="$(lp_rank '' 'x')"
	[ -z "$out" ] || fail "empty LIST + filter 'x' should produce no output (got [$out])"
	out="$(lp_rank '' '')"
	[ -z "$out" ] || fail "empty LIST + empty filter should produce no output (got [$out])"
	pass "empty LIST -> empty output (both filter and empty-filter paths)"
}

# Quick reject (rank.sh): a name shorter than the query cannot be a subsequence.
test_ranking_quick_reject_short_name() {
	local out cnt
	out="$(lp_rank 'ab' 'abc')"
	cnt="$(printf '%s\n' "$out" | grep -c '^ab$')"
	assert_eq "$cnt" '0' "name shorter than query is hidden (quick-reject nlen<qlen)"
}

# Word-boundary bonus (PRD §3.37): a match right after a separator (-_. /) scores
# higher than a deep subsequence. 'my-log' (boundary after '-') ranks above 'xlog'.
test_ranking_word_boundary_ordering() {
	local LIST=$'my-log\nxlog'
	local out first
	out="$(lp_rank "$LIST" 'log')"
	first="$(printf '%s\n' "$out" | head -1)"
	assert_eq "$first" 'my-log' "word-boundary (after '-') ranks my-log above xlog"
}
```

NOTE for the implementer: the block above is the COMPLETE, ready-to-paste file body
(verified: every assertion matches the captured outputs in
`research/test_ranking_findings.md`). Use it as-is; the only allowed deviation is
comment phrasing. Do NOT add `set -e`. Do NOT build an all-matching perf fixture
(research FINDING 5: it takes ~480ms by design and would fail the gate). Do NOT
grep the whole rank.sh for the perf invariant (the source-time CURRENT_DIR line is
a false positive — extract the lp_rank BODY). Do NOT assert on §19 layout
(gap/overflow/count) — that is test_layout.sh's domain. Do NOT create any other
file or touch any source.

### Integration Points

```yaml
HARNESS (how this file is consumed):
  - tests/run.sh sources setup_socket.sh + helpers.sh + every tests/test_*.sh (incl.
    this one), discovers test_* via compgen, and runs each in a per-test fresh-socket
    cycle. This file is SOURCED (defines functions); it is NOT executed directly.

FUNCTION UNDER TEST (read-only):
  - scripts/rank.sh::lp_rank LIST FILTER — sourced once at file load (guarded). Pure
    leaf; no tmux. The four pure test groups call it directly.

RENDERER (read-only, for the no-drift integration test only):
  - scripts/renderer.sh — invoked as `bash "$LIVEPICKER_SCRIPTS/renderer.sh"` after
    lp_ranking_seed sets @livepicker-* state. Reads state via tmux show-option (needs
    the isolated socket from setup_test). Emits the ranked tabs; current-index tab
    wrapped in #[fg=black,bg=yellow]<name>#[default].

STATE WRITES (this task — via lp_ranking_seed, on the isolated socket only):
  - @livepicker-{fg,bg,highlight-fg,highlight-bg,nerd-fonts,tab-style,query-gap,
    type,client-width,scroll,list,filter,index}. All pinned to defaults/fixtures.
  - These are TEARDOWN-managed by the harness (teardown_test kills the isolated
    socket) — ZERO impact on the user's real server (PRD §15 invariant).

STATE READS / TMUX MUTATIONS: none beyond the seeded @livepicker-* reads inside
renderer.sh (read-only show-option). No switch-client, no set-hook, no bind-key.

DATABASE / MIGRATIONS / ROUTES / CONFIG: none.
```

## Validation Loop

### Level 1: Syntax & Style (Immediate Feedback)

```bash
# Run after creating the file — fix before proceeding.
bash -n tests/test_ranking.sh                     # syntax; expect no output, exit 0
shellcheck tests/test_ranking.sh                  # lint; expect 0 findings (file-level
                                                 # disable=SC2154,SC2016,SC2034,SC2086 covers it)
# Tabs-not-spaces sanity (shfmt NOT installed):
grep -Pn '^    ' tests/test_ranking.sh && echo "FAIL: 4-space indent found, use tabs" || echo "OK: tabs only"
# Confirm every test function is named test_ranking_* (distinct from test_layout_*):
grep -nE '^test_[a-z_]+\(\)' tests/test_ranking.sh | grep -v 'test_ranking_' \
  && echo "FAIL: non-test_ranking_* function found" || echo "OK: all tests are test_ranking_*"
# Confirm rank.sh is sourced guarded (not bare):
grep -n 'command -v lp_rank' tests/test_ranking.sh && echo "OK: guarded source" \
  || echo "FAIL: rank.sh must be sourced guarded (readonly LP_* consts)"
# Run from the repo root.
```

### Level 2: Unit / Component Validation (the suite itself)

```bash
# Run the FULL suite (this file + every other test_*.sh). The new test_ranking_*
# functions must all PASS, and NO existing test may regress (this file touches no source).
tests/run.sh
# Expected: exit 0; summary line "N passed, 0 failed". The test_ranking_* lines all PASS.
# To run ONLY this file's tests in isolation (handy while iterating), temporarily move
# the other test_*.sh aside — but the gate is the FULL run.sh (no regressions).

# Spot-check the perf guard independently (the highest-consequence assertion):
source scripts/rank.sh
body="$(sed -n '/^lp_rank()/,/^}$/p' scripts/rank.sh)"
bad="$(printf '%s' "$body" | grep -nE '\$\([^(]' || true)"
[ -z "$bad" ] && echo "OK: no command substitution in lp_rank body" || { echo "FAIL: $bad"; }
big="$(seq -f 'sess-%g' 1 300)"; echo "s99 matches: $(lp_rank "$big" s99 | grep -c .) (want 3)"
# Expected: empty $bad; s99 matches exactly 3.
```

### Level 3: Integration Testing (the no-drift renderer path)

```bash
# Confirm the no-drift integration test's renderer-output format is exactly what the
# assertion expects (run renderer.sh with the seeded state on an isolated socket).
# This mirrors what test_ranking_no_drift_renderer_highlight does inside setup_test.
SOCK="lp-rank-manual-$$"; SHIM="$(mktemp -d)"
cat > "$SHIM/tmux" <<EOF
#!/usr/bin/env bash
exec /usr/bin/tmux -L "$SOCK" "\$@"
EOF
chmod +x "$SHIM/tmux"
trap '/usr/bin/tmux -L "$SOCK" kill-server 2>/dev/null; rm -rf "$SHIM" /tmp/tmux-$UID/$SOCK' EXIT
PATH="$SHIM:$PATH" tmux new-session -d -s driver -x 120 -y 40
PATH="$SHIM:$PATH" tmux set-option -g @livepicker-list      $'blog-engine\nlogs-prod\nalog'
PATH="$SHIM:$PATH" tmux set-option -g @livepicker-filter    'log'
PATH="$SHIM:$PATH" tmux set-option -g @livepicker-index     '0'
PATH="$SHIM:$PATH" tmux set-option -g @livepicker-nerd-fonts off
PATH="$SHIM:$PATH" tmux set-option -g @livepicker-tab-style plain
PATH="$SHIM:$PATH" tmux set-option -g @livepicker-highlight-fg black
PATH="$SHIM:$PATH" tmux set-option -g @livepicker-highlight-bg yellow
# STATE_CLIENT_WIDTH unset -> renderer reads 0 -> full list, no windowing
raw="$(PATH="$SHIM:$PATH" bash scripts/renderer.sh)"
printf 'raw: %s\n' "$raw"
# Expect the highlight token for the top match (logs-prod) present:
printf '%s' "$raw" | grep -q '#[fg=black,bg=yellow]logs-prod#\[default\]' \
  && echo "OK: renderer highlights ranked[0]=logs-prod" || echo "FAIL"
# Expected: OK. (If your sandbox's manual shim is flaky, trust setup_test — it powers
# the 9 existing passing suites. The assertion format is verified in research FINDING 9c.)
```

### Level 4: Creative & Domain-Specific Validation

```bash
# Pollution spot-check (PRD §15 invariant): running the suite must NOT touch the
# user's REAL tmux server. The harness's setup_socket isolates every test on a -L
# socket; verify the real server's session list is byte-identical before/after.
REAL_BEFORE="$(/usr/bin/tmux list-sessions -F '#{session_name}' 2>/dev/null | sort)"
tests/run.sh >/dev/null 2>&1
REAL_AFTER="$(/usr/bin/tmux list-sessions -F '#{session_name}' 2>/dev/null | sort)"
[ "$REAL_BEFORE" = "$REAL_AFTER" ] && echo "OK: real server untouched (PRD §15)" \
  || echo "FAIL: real server polluted"
# Expected: OK — the harness isolates every test on tmux -L (setup_socket.sh FINDING 2).
```

## Final Validation Checklist

### Technical Validation

- [ ] `bash -n tests/test_ranking.sh` exits 0 with no output.
- [ ] `shellcheck tests/test_ranking.sh` reports 0 findings (file-level disable covers it).
- [ ] No 4-space indents (`grep -Pn '^    '` is empty); tabs only.
- [ ] All test functions named `test_ranking_*`.

### Feature Validation

- [ ] File at `tests/test_ranking.sh`; file-level shellcheck disable + `set -u`.
- [ ] `rank.sh` sourced once, guarded (`command -v lp_rank || source`).
- [ ] `lp_ranking_seed LIST [FILTER] [INDEX]` defined (pins defaults + width 0).
- [ ] **(a)** prefix test: first line == `logs-prod`; full order pinned.
- [ ] **(b)** hidden test: `xyz` absent (`grep -c '^xyz$'` == 0).
- [ ] **(c)** empty-filter test: `assert_eq out LIST` + clean diff.
- [ ] **(d)** three no-drift tests: consumers-grep + determinism + renderer-highlight
      (IDX=0 and IDX=1).
- [ ] **(e)** perf test: lp_rank body has NO command substitution (grep); few-match
      300-name timing < 200ms (or skipped if `date +%s%N` unavailable).
- [ ] Edges: stable tie-break, case-insensitive + case-preserved, empty-list,
      quick-reject, word-boundary.
- [ ] `tests/run.sh` runs all `test_ranking_*` and they PASS; no existing test breaks.

### Code Quality Validation

- [ ] NO `set -e`, NO `set -o pipefail` (house style; helpers/setup_socket).
- [ ] Failure signaled ONLY via `fail`/`assert_*` (never exit/return-nonzero).
- [ ] All expansions double-quoted; `local` for all function locals.
- [ ] Perf fixture is FEW-match (s99 → 3), NOT all-match (research FINDING 5).
- [ ] Perf grep targets the lp_rank BODY (sed extraction), not the whole file.
- [ ] No new source files; no edit to `rank.sh`/`renderer.sh`/`input-handler.sh`.

### Documentation & Deployment

- [ ] Header comment states: purpose (PRD §20 ranking); the pure-leaf idiom (no socket
      for a/b/c/e); the no-drift three-proof design; the perf caveat (O(N·Q) vs O(M²));
      the reference to research/test_ranking_findings.md.
- [ ] No README/doc file created (DOCS = Mode A; covered by README P4.T1).
- [ ] No tmux.conf edit; no other test file touched.

---

## Anti-Patterns to Avoid

- ❌ Don't build a perf fixture where ALL 300 names match and gate on <50ms. The
  O(M²) selection sort makes that ~480ms BY DESIGN (research FINDING 5; PRD §3.40
  "typical N < 100"). Use a FEW-match filter (`s99` → 3 of 300) so the test measures
  the O(N·Q) matching loop (the contract's stated complexity, ~19ms).
- ❌ Don't grep the WHOLE `rank.sh` for the perf invariant. The source-time
  `CURRENT_DIR="$(cd …)"` (line 30) is a real command substitution but it is OUTSIDE
  `lp_rank` and runs once at source. Extract the `lp_rank` FUNCTION BODY
  (`sed -n '/^lp_rank()/,/^}$/p'`) and grep THAT — it must be empty of `$(` non-arithmetic.
- ❌ Don't gate perf on a tight timing bound (e.g. <50ms). Timing varies by machine;
  a slow CI box can double it. Use a GENEROUS bound (<200ms) AND the hard source grep.
  The grep is the real guard; timing is secondary.
- ❌ Don't run `renderer.sh` for the pure tests (a/b/c/e). `lp_rank` is a pure leaf —
  source `rank.sh` and call `lp_rank` directly. Only the no-drift INTEGRATION test
  needs `renderer.sh` (it asserts the renderer consumes lp_rank).
- ❌ Don't assert the renderer's full tab ORDER by parsing styled output (fragile).
  Assert the HIGHLIGHT specifically: `assert_contains "$raw" "#[fg=black,bg=yellow]<ranked[IDX]>#[default]"`.
  That proves the visible highlight == lp_rank's ranked[IDX] without parsing the whole line.
- ❌ Don't forget to pin `@livepicker-nerd-fonts off` + `client-width 0` in the seed
  helper. Default nerd-fonts is ON (U+F002 icon bytes) and width unset → 0; pinning
  makes the renderer output deterministic (clean ASCII, full list, no windowing).
- ❌ Don't `exit` or `return-nonzero` to signal failure. run.sh reads `TEST_STATUS`
  in the CURRENT shell; an exit kills the runner. Use `fail`/`assert_*` only.
- ❌ Don't source `rank.sh` unguarded. Its `LP_*` constants are `readonly`; if another
  code path already sourced it, a bare re-source errors. Guard with
  `command -v lp_rank >/dev/null 2>&1 || source …`.
- ❌ Don't add `set -e`/`set -o pipefail`. `tmux`/`grep`/`date` legitimately return
  nonzero; `set -e` would abort a test mid-assertion. `set -u` only.
- ❌ Don't duplicate `test_layout.sh`'s §19-layout assertions (gap/overflow/count/
  tab-style/justify). This file covers §20 RANKING only. The two suites share the
  renderer-seed IDIOM, not assertions.
- ❌ Don't use 4-space indent — tabs only. Don't invent new assert helpers — use
  `fail`/`assert_eq`/`assert_contains` from helpers.sh.

---

## Confidence Score

**9 / 10** for one-pass success. Rationale: the deliverable is a single sourced
test file whose complete body is given verbatim in the Implementation Blueprint,
and EVERY assertion in it was executed against the REAL `scripts/rank.sh::lp_rank`
on 2026-07-07 with exact outputs captured in `research/test_ranking_findings.md`
(`logs-prod` first; `xyz` absent; empty-filter byte-identity; the
`#[fg=black,bg=yellow]<name>#[default]` highlight; perf 19ms few-match / 480ms
all-match). The function under test and the full harness (`run.sh`/`helpers.sh`/
`setup_socket.sh`) are COMPLETE, and the conventions mirror the in-flight sibling
`test_layout.sh` (same file-level disable, same `lp_*_seed` helper shape, same
renderer-seed idiom). The three highest-consequence details — the **perf caveat**
(few-match fixture, NOT all-match; research FINDING 5), the **grep invariant**
(extract the lp_rank body, not the whole file; FINDING 6), and the **no-drift
highlight assertion** (pin nerd-fonts off + width 0; FINDING 9c) — are each backed
by a live finding and a dedicated test. Residual risks: (a) the perf timing bound
being exceeded on an unusually slow CI box — mitigated by the GENEROUS <200ms bound
(10× the observed 19ms) AND the machine-independent source grep as the hard guard;
(b) `seq -f 'sess-%g'` formatting differing on exotic platforms — mitigated by the
explicit `assert_eq "$m" '3'` fixture sanity check (if the match count is wrong,
the test fails loudly before the timing, pointing at the fixture, not the ranker);
(c) the sandbox's ad-hoc manual shim being flaky for the Level 3 spot-check —
irrelevant to the deliverable, which uses `setup_test` (the proven harness powering
9 existing passing suites). All residual risks are deterministically caught.
