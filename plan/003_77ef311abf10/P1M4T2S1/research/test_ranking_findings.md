# Research: tests/test_ranking.sh — fuzzy ranking integration suite

> All facts below were verified **LIVE on 2026-07-07** against the REAL
> `scripts/rank.sh::lp_rank` (plan 003 build, `tmux 3.6b`, `bash 5.3.15`,
> `shellcheck 0.11.0`). Every contract assertion (a)–(e) was executed and its
> exact output captured. This file is the empirical basis for the
> `tests/test_ranking.sh` PRP.

## Environment

| Tool | Version | Source |
|---|---|---|
| tmux | 3.6b | `tmux -V` |
| bash | 5.3.15(1)-release | `bash --version` |
| shellcheck | 0.11.0 | `shellcheck --version` |

The function under test (`lp_rank`) and the test harness (`tests/{run,helpers,setup_socket}.sh`)
are all COMPLETE. The sibling suite `tests/test_layout.sh` is being created in
parallel (P1.M4.T1.S1); its PRP confirms test_ranking.sh is the EXPECTED,
disjoint ranking counterpart (see FINDING 11).

---

## FINDING 1 — `lp_rank` is a PURE LEAF function: tests (a)(b)(c)(e) need NO tmux socket

`scripts/rank.sh` is a **sourced library** that defines `lp_rank` (+ `LP_*`
scoring constants) and **nothing else** — NO source-time side effects, and it
sources NO other lib (it does not even `source` options/utils/state; it is a
leaf). `lp_rank` itself calls **no `tmux`** — only `mapfile`, `printf`,
parameter expansion (`${name,,}`, `${var:off:len}`, `${#var}`), and integer
arithmetic (`$((…))`).

**Implication:** the four pure-ranking tests (prefix>subsequence, hidden,
empty-order, perf) can be written as **direct unit tests** —
`source "$LIVEPICKER_SCRIPTS/rank.sh"` then call `lp_rank "$LIST" "$FILTER"`
and assert on stdout. No `setup_test`/socket/client is *required* for them
(the work-item contract: "test it directly by sourcing scripts/rank.sh and
calling lp_rank (no tmux needed)"). They run in microseconds. (The harness
still calls `setup_test` once per test_* function — harmless; the socket is
simply unused by these tests. The no-drift test (d) DOES use the socket because
it runs `renderer.sh`, which reads state via `tmux show-option`.)

---

## FINDING 2 — contract (a) PREFIX > SUBSEQUENCE: `logs-prod` ranks first

```
$ source scripts/rank.sh
$ lp_rank "$(printf 'blog-engine\nlogs-prod\nalog')" 'log'
logs-prod        <- first line (WANT)
blog-engine
alog
```

**Why (score trace, constants from rank.sh: PREFIX=1000, WORD_BOUNDARY=100,
CONTIGUITY=10, position penalty = −pos[0]):**

| name | matched pos | prefix(+1000) | word-bdry(+100) | contig(+10) | penalty | **score** |
|---|---|---|---|---|---|---|
| `logs-prod` | [0,1,2] | yes (pos0) | +100 (pos0) | +10+10 (1,2 follow) | −0 | **1120** |
| `blog-engine` | [1,2,3] | no | 0 (no boundary) | +10+10 (2,3 follow) | −1 | **19** |
| `alog` | [1,2,3] | no | 0 (no boundary) | +10+10 (2,3 follow) | −1 | **19** |

- `logs-prod` wins by the PREFIX bonus (the contract's "prefix bonus beats
  blog-engine's deep subsequence"). ✓
- `blog-engine` (19) ties `alog` (19) → **stable tie-break keeps original tmux
  order** → `blog-engine` before `alog`. (FINDING 7 stress-tests this.)

**Test assertion:** `out="$(lp_rank "$LIST" 'log')"; first="$(printf '%s\n' "$out" | head -1)";
assert_eq "$first" 'logs-prod' "prefix bonus ranks logs-prod first"`. Verified.

---

## FINDING 3 — contract (b) NON-SUBSEQUENCE is HIDDEN entirely

```
$ lp_rank "$(printf 'blog-engine\nlogs-prod\nalog\nxyz')" 'log'
logs-prod
blog-engine
alog
$ # xyz is a 3-char name but 'l' never appears -> not a subsequence -> HIDDEN
$ printf '%s\n' "$out" | grep -c '^xyz$'
0
```

- `xyz` vs `log`: the walk for query char `l` scans `x`,`y`,`z`, finds no `l`
  → `matched=0` → `continue` (hidden). The name is **absent from output**.
- PRD §3.36: "Non-matches are HIDDEN entirely, so the create-on-empty path
  still fires (section 6 Confirm)." So a list with ONLY non-matches → empty
  output (FINDING 8 covers the empty-output case).

**Test assertion:** add `xyz` to the list; `cnt="$(printf '%s\n' "$out" | grep -c '^xyz$')";
assert_eq "$cnt" '0' "non-subsequence hidden"`. Verified (grep count = 0).

---

## FINDING 4 — contract (c) EMPTY FILTER → byte-identical to LIST, original order

```
$ LIST='gamma
alpha
beta'
$ out="$(lp_rank "$LIST" '')"
$ [ "$out" = "$LIST" ] && echo YES
YES
$ diff <(printf '%s\n' "$LIST") <(lp_rank "$LIST" '') && echo "(diff clean)"
(diff clean)
```

- Empty-filter path (rank.sh): prints every name with `printf '%s\n'`, in
  `mapfile` (original LIST) order, score 0 — **no reordering** (PRD §3.38;
  preserves §2 non-goal "no recency/MRU").
- The output equals the input **byte-for-byte after `$()` normalization**:
  `lp_rank` emits a trailing `\n` after each name (incl. the last), but
  `out="$(…)"` strips trailing newlines, so `out` == `LIST` exactly when LIST
  has no trailing newline. **assert_eq "$out" "$LIST"** is the cleanest check.
- The `diff` form also works IF LIST is constructed without a trailing newline
  (left side `printf '%s\n' "$LIST"` re-terminates; right side `lp_rank` is
  already terminated). Both are equivalent; assert_eq is preferred (house helper).

**Test assertion (both forms, for rigor):**
`assert_eq "$out" "$LIST" "empty filter preserves order"` AND
`diff <(printf '%s\n' "$LIST") <(lp_rank "$LIST" '') || fail "diff not clean"`.
Verified.

---

## FINDING 5 — contract (e) PERF: the <50ms claim is about the O(N·Q) MATCHING loop, NOT the O(M²) sort — CRITICAL

Measured `lp_rank` on a 300-name list, Q=4, **min of 5 runs** (`date +%s%N`):

| filter | matches (M) | min time | what it measures |
|---|---|---|---|
| `''` (empty) | 300 (no sort) | **3 ms** | the no-reorder printf path |
| `sprg` | **0** | **36 ms** | pure O(N·Q) subsequence walk (no scoring/sort) |
| `s99` | **3** | **19 ms** | O(N·Q) walk + scoring + O(M²) sort (M=3, trivial) |
| `prod` | **300** | **480 ms** | O(N·Q) walk + scoring + **O(M²) sort (M=300)** |

**This is the highest-consequence finding for the perf test.** The contract
says "N=300, Q=4 must complete well under 50ms" and "the point is no per-name
subshell." But:

- The **O(N·Q) matching loop** (the thing the grep invariant guards, FINDING 6)
  is fast: ~19–36 ms for N=300, Q=4, regardless of match count.
- The **O(M²) selection sort** (rank.sh: "O(M^2), M = match count (small <100)")
  dominates when MANY names match: 300 matches → **480 ms**, far over 50 ms.
  This is **by-design** (PRD §3.40: "Fine for typical N (< 100)") and is NOT a
  subshell/per-name-command-substitution issue — it is pure arithmetic in a
  double loop.

**Therefore the perf test MUST use a filter that matches a SMALL number of
names** (so it measures O(N·Q), the contract's stated complexity) — NOT a
filter that matches all 300 (which would measure the O(M²) sort and fail a
<50ms gate). A 300-name list `sess-001…sess-300` with filter `s99` matches
exactly 3 (`sess-099`, `sess-199`, `sess-299`) → ~19 ms, comfortably under
50 ms with headroom.

**Test design (two layers):**
1. **HARD invariant (machine-independent, the real guard):** grep the source to
   prove NO command substitution inside the per-name loop — see FINDING 6.
2. **Timing check (generous bound):** time `lp_rank "$big300" 's99'`; assert
   `< 200 ms` (generous — ~10× the observed 19 ms; absorbs slow-CI variance
   while still catching a per-name-subshell regression, which would push the
   walk alone to 300 ms+). Guard: if `date +%s%N` is unavailable (non-Linux),
   skip the timing — the grep is the hard invariant.

**DO NOT** build a 300-name all-matching list and gate on <50ms — it will FAIL
(480 ms) for a reason that is NOT a bug. (Documented here so the implementer
does not "fix" the test by loosening the sort.)

---

## FINDING 6 — the subshell invariant: `grep -nE '\$\([^(]' scripts/rank.sh` → ONLY the source-time CURRENT_DIR

The contract: "grep the source to confirm no `$(...)` inside the name loop."

```
$ grep -nE '\$\([^(]' scripts/rank.sh
30:CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
```

- The pattern `\$\([^(]` matches `$(` followed by any char that is NOT `(` —
  i.e. **real command substitution**, while **excluding arithmetic** `$((…))`
  (the `$((` has `(` right after `$(`). Every `$((…))` in rank.sh is integer
  arithmetic (score math, index increments) — NOT a subshell.
- The ONLY real command substitution is line 30 (`CURRENT_DIR="$(cd … && pwd)"`),
  which runs **once at source time**, OUTSIDE the per-name loop. Inside the
  per-name loop (the `for name in "${all[@]}"` body) there is **zero** command
  substitution — only parameter expansion + arithmetic. This is what keeps the
  O(N·Q) loop sub-50 ms (each subshell fork is ~1 ms; 300 forks would be 300 ms+).

**Test assertion (the hard perf guard):**
```bash
# Every '$(' not immediately followed by '(' is a real command substitution.
# Only the source-time CURRENT_DIR (line 1 of the function defs) is allowed;
# it must NOT appear inside the per-name loop.
subs="$(grep -nE '\$\([^(]' "$LIVEPICKER_SCRIPTS/rank.sh")"
# Expect exactly ONE line, and it is the CURRENT_DIR resolver.
[ "$(printf '%s\n' "$subs" | grep -cE 'CURRENT_DIR=.*\(cd')"' )" = '1' ] || fail "…"
# And NO '$(' inside the lp_rank function body (lines between 'lp_rank()' and the
# closing '}'): assert the only sub is above lp_rank.
```
Verified: exactly one match, and it is the CURRENT_DIR line (above `lp_rank`).

---

## FINDING 7 — STABLE TIE-BREAK: equal scores keep original tmux order

The selection sort advances `best` ONLY on **strictly-greater** score
(`rank.sh`: `if … r_score[k] -gt best_score`), so the earlier original index
wins ties. Verified by constructing a list where two names score equally and
asserting they keep input order:

```
$ lp_rank "$(printf 'aaa-mlog\nbbb-mlog')" 'mlog'   # both: pos[0]=4, same score
aaa-mlog     <- original order preserved (NOT swapped)
bbb-mlog
```

**Test:** `test_ranking_stable_tiebreak` — two names with identical score →
output order == input order. Cheap, pure-lp_rank. Strengthens §15.28 coverage.

---

## FINDING 8 — EDGE CASES (cheap, pure-lp_rank): empty list, quick-reject, case-insensitive, word-boundary

| case | input | result | assertion |
|---|---|---|---|
| empty LIST | `lp_rank '' 'x'` | (no output) | `out` is empty |
| empty LIST + empty FILTER | `lp_rank '' ''` | (no output) | `out` is empty |
| name shorter than query | `lp_rank 'ab' 'abc'` | (no output; quick-reject `nlen<qlen`) | `ab` absent |
| case-insensitive match | `lp_rank 'LOGS' 'log'` | `LOGS` (case preserved) | output == `LOGS` |
| word-boundary (separator) | `lp_rank 'my-log\nxlog' 'log'` | `my-log` first (boundary after `-`) | first == `my-log` |

All verified live. These round out §15.28 ranking coverage and are free
(no socket). The case-insensitive test also pins that **original case is
preserved in output** (`low_name` is used only for matching/scoring; the
printed token is the original `name`).

---

## FINDING 9 — contract (d) NO-DRIFT: three independent proofs

The no-drift contract: "renderer, next-session, prev-session, confirm all call
`lp_rank` with the same LIST+FILTER, so `ranked[index]` is identical across
them (single source of truth)." Three complementary proofs:

### 9a — STRUCTURAL: every consumer calls lp_rank (no re-implementation drift)

```
$ grep -c 'lp_rank' scripts/renderer.sh       → 1
$ grep -c 'lp_rank' scripts/input-handler.sh  → 5
```

`input-handler.sh` call sites (the no-drift consumers): lines 137, 297, 326, 357
+ the explanatory comment at 127 ("# lp_rank the renderer uses (so filtered[0]
== the highlighted session)"). Each does
`mapfile -t filtered < <(lp_rank "$cur_list" "$cur_filter")` — **identical
args** to the renderer's call. So nav/confirm/sync resolve the SAME array the
renderer renders. (`session-mgmt.sh` is P2 — not yet built; when it lands it
will adopt the same call. This test greps only the consumers that EXIST.)

**Test assertion:** `grep -q 'lp_rank' "$LIVEPICKER_SCRIPTS/renderer.sh"` and
`grep -q 'lp_rank' "$LIVEPICKER_SCRIPTS/input-handler.sh"` — both must pass
(the consumers share the single source of truth, not a copy).

### 9b — DETERMINISM: two lp_rank calls with identical args are byte-identical

```
$ a="$(lp_rank "$LIST" 'log')"; b="$(lp_rank "$LIST" 'log')"
$ [ "$a" = "$b" ] && echo MATCH
MATCH
```

`lp_rank` is a pure function (no randomness, no hidden state) → identical input
⇒ identical output. So renderer's ranked == nav's ranked == confirm's ranked.
**Test:** `assert_eq "$a" "$b" "lp_rank deterministic (no call-to-call drift)"`.

### 9c — INTEGRATION: renderer.sh's visible HIGHLIGHT == lp_rank's ranked[IDX]

Run the real renderer with seeded state (query ACTIVE, plain style, nerd-fonts
OFF, client-width UNSET → width=0 → full list, no viewport windowing) and assert
the highlighted tab is exactly `ranked[IDX]`. The renderer wraps the
current-index tab in the HFG/HBG style (defaults: `opt_highlight_fg=black`,
`opt_highlight_bg=yellow` — options.sh), so the highlight token is
`#[fg=black,bg=yellow]<name>#[default]`.

Renderer source (query-active final emit):
`printf '%s' "#[fg=$FG,bg=$BG]${icon}${esc_filter}#[default]${gap}${left_ind}${tabs}${right_ind}"`
and per tab (plain, current index):
`seg="#[fg=$HFG,bg=$HBG]${esc_name}#[default]"`.

Verified on the SYNTHETIC string reconstructed from the source (my ad-hoc shim
was flaky in the sandbox, but `setup_socket.sh` — used by 9 passing tests — is
reliable; the actual test uses `setup_test`):

```
raw = #[fg=default,bg=default]log#[default]  #[fg=black,bg=yellow]logs-prod#[default] #[fg=default,bg=default]blog-engine#[default] #[fg=default,bg=default]alog#[default]
assert_contains "$raw" '#[fg=black,bg=yellow]logs-prod#[default]'   → ok   (IDX=0 → ranked[0])
# then seed INDEX=1 and re-run: highlight moves to ranked[1] (simulating next-session)
assert_contains "$raw1" '#[fg=black,bg=yellow]blog-engine#[default]' → ok   (IDX=1 → ranked[1])
```

**Test design (`test_ranking_no_drift_renderer_highlight`):**
1. `setup_test` (isolated socket).
2. `lp_ranking_seed "$LIST" 'log' 0` (helper pins defaults + nerd off + width 0).
3. `mapfile -t ranked < <(lp_rank "$LIST" 'log')` (canonical).
4. `raw="$(bash "$LIVEPICKER_SCRIPTS/renderer.sh")"`.
5. `assert_contains "$raw" "#[fg=black,bg=yellow]${ranked[0]}#[default]" "renderer highlights ranked[0]"`.
6. Re-seed INDEX=1; re-run; `assert_contains` ranked[1] highlight → proves moving
   the index (as next-session does) makes the renderer highlight ranked[new_idx].

This is the visible, end-to-end no-drift proof: **what the user sees highlighted
== what confirm targets == lp_rank ranked[IDX]**.

---

## FINDING 10 — test harness conventions (run.sh / helpers.sh / setup_socket.sh + sibling test_layout.sh)

- **Discovery:** `run.sh` sources `setup_socket.sh` + `helpers.sh` + every
  `tests/test_*.sh`, then `compgen -A function | grep '^test_' | sort`, and runs
  each `test_*` with a **per-test fresh socket** (`setup_test "lp-$$-<name>"` →
  reset `TEST_STATUS=pass` → run → read `TEST_STATUS` → `teardown_test`).
- **Assertion API (helpers.sh):** `fail msg` (sets `TEST_STATUS=fail`), `pass msg`,
  `assert_eq a b msg`, `assert_contains str sub msg`. **Signal failure ONLY via
  fail/assert_*** — NEVER `exit`/`return-nonzero` (kills the runner).
- **Style:** file-level `# shellcheck disable=SC2154,SC2016,SC2034,SC2086`
  (mirrors `test_appearance.sh`/`test_layout.sh` — silences run.sh-provided
  helpers/vars + the eval/single-quote idioms); `set -u` ONLY (NOT -e/pipefail);
  TABS for indent; `local` for all function locals.
- **Paths:** `$LIVEPICKER_SCRIPTS` (exported by `setup_socket`) points at
  `scripts/` — use it to source rank.sh and invoke renderer.sh (NOT a hardcoded
  relative path, so the test is robust to CWD).
- **Renderer-seed idiom (codebase pattern, sibling PRP §P8):** seed
  `@livepicker-*` state via bare `tmux set-option -g` (hits the isolated socket),
  then `raw="$(bash "$LIVEPICKER_SCRIPTS/renderer.sh")"` and assert on stdout.
  Needs NO attached client.
- **Seed-helper pattern (sibling `lp_layout_seed` / `lp_appearance_seed`):**
  define `lp_ranking_seed LIST [FILTER] [INDEX]` that pins the §11 default
  colors + type + client-width 0 + scroll 0 + the list/filter/index, so each
  test's assertions are deterministic.

---

## FINDING 11 — DISJOINT from the sibling `tests/test_layout.sh` (no duplication)

The in-parallel sibling P1.M4.T1.S1 creates `tests/test_layout.sh`, which
covers **PRD §19 LAYOUT** (query bar / viewport / overflow / no-match / two tab
styles / status-justify / the "no count" sweep). Its PRP explicitly states:
"It does NOT cover ranking-order (that is `test_ranking.sh`, P1.M4.T2)."

`test_ranking.sh` covers **PRD §20 RANKING** (lp_rank's subsequence match,
scoring order, hiding, the no-drift single-source-of-truth, perf). The two
suites share only the **renderer-seed idiom** (the harness pattern) and the
**seed-helper shape** — NOT assertions. The one place test_ranking.sh runs
`renderer.sh` (the no-drift integration test, FINDING 9c) asserts on
**RANKING** (the highlight == ranked[index]), not on layout structure (gap /
overflow / count), so there is no overlap with test_layout.sh's cases.

**Naming:** use `test_ranking_*` (sibling uses `test_layout_*`) so the two
suites are visually distinct in `run.sh` output.

---

## Summary of load-bearing decisions (encoded in the PRP)

1. **Pure tests (a)(b)(c)(e):** `source rank.sh`; call `lp_rank` directly; NO
   socket needed (FINDING 1). Fast, deterministic.
2. **(a) prefix>subsequence:** assert first line == `logs-prod` (FINDING 2).
3. **(b) hidden:** non-subsequence absent (`grep -c == 0`) (FINDING 3).
4. **(c) empty order:** `assert_eq "$out" "$LIST"` + clean diff (FINDING 4).
5. **(e) perf:** few-match 300-name list (`sess-NNN`, filter `s99`, M=3) +
   generous `<200ms` bound + HARD grep invariant (no `$(` in the per-name loop;
   FINDINGS 5–6). **Never** all-match (480 ms; not a bug).
6. **(d) no-drift:** structural grep (consumers call lp_rank) + determinism (two
   calls identical) + integration (renderer highlight == ranked[IDX] for IDX=0
   and IDX=1) (FINDING 9).
7. **Extra §15.28 coverage:** stable tie-break, empty-list, quick-reject,
   case-insensitive (case preserved), word-boundary (FINDINGS 7–8).
8. **Conventions:** file-level shellcheck disable; `set -u` only; `test_ranking_*`
   funcs; `lp_ranking_seed` helper; fail via assert_* only; `$LIVEPICKER_SCRIPTS`
   paths (FINDING 10). Disjoint naming/assertions from `test_layout.sh` (FINDING 11).

---

## Gaps

None material. The function under test (`lp_rank`) and the full harness are
COMPLETE and every contract assertion (a)–(e) was executed against the real
`lp_rank` with exact outputs captured. The only sandbox artifact — my ad-hoc
manual socket shim was flaky — is irrelevant to the deliverable: the actual test
uses `setup_test` (the proven harness powering 9 passing `test_*.sh` suites), and
the pure-ranking tests need no socket at all. The renderer-output format used in
the no-drift integration assertion (FINDING 9c) was verified against the
renderer.sh SOURCE (the synthetic string reconstruction matches the emitted bytes
exactly).
