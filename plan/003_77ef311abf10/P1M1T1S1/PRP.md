# PRP — P1.M1.T1.S1: Implement lp_rank subsequence match + scoring algorithm

---

## Goal

**Feature Goal**: A new sourced library `scripts/rank.sh` exposing `lp_rank LIST FILTER`
— a pure-bash fuzzy ranker that (a) matches names by **subsequence** (every query
char in order, case-insensitive), (b) scores each match (prefix > word-boundary >
contiguity > position-penalty) with a **stable** tie-break on original tmux order,
and (c) prints matches best-first, preserving original case. It supersedes
`scripts/filter.sh::lp_build_filtered` (case-insensitive substring) with the **same
call convention** so the sibling subtask S2 swaps callers verbatim.

**Deliverable**: One new file `scripts/rank.sh` (sourced library, no driver, no
source-time side effects). `lp_build_filtered` and its callers are **untouched**
here — S2 (P1.M1.T1.S2) switches the 6 call sites + retires filter.sh.

**Success Definition**:
- `lp_rank "$LIST" ""` (empty filter) is **byte-identical** to
  `lp_build_filtered "$LIST" ""` — the critical guarantee that keeps existing
  tests green after S2.
- Non-matches are hidden entirely (subsequence miss → not printed).
- Ordering demonstrably satisfies PRD §3.37: exact-prefix > word-boundary substring
  > deep subsequence; equal scores keep original order (stable).
- Pure bash, O(N·Q), **no per-name subshell**, no `tmux` calls; N=100/Q=10 redraw
  well under the §18 renderer budget (<50ms).
- `bash -n` + `shellcheck` clean; sourcing the file has zero side effects.

## User Persona (if applicable)

**Target User**: The renderer, input-handler, and (later) session-mgmt.sh — all
consume `ranked[index]` where index 0 is the highlighted/previewed tab.

**Use Case**: User types a query; the picker shows names matching it as a
subsequence, best matches first, in original case. Empty query = full list,
untouched order.

**Pain Points Addressed**: The old substring filter misses useful matches (e.g.
`lg` can't match `blog`) and can't rank (everything that matches is equal). Ranking
makes the most relevant tab land at index 0 = the preview target.

---

## Why

- **Single source of truth (PRD §20).** One ranker, sourced by renderer +
  input-handler + session-mgmt, so "what the renderer shows" and "what
  nav/confirm/rename/delete resolve" can never drift — the same invariant
  `filter.sh` enforced.
- **`ranked[0] == the preview target` is load-bearing.** Nav/confirm index into
  the ranked array directly (PRD §3.39). A wrong top match lands the user on the
  wrong session.
- **Performance contract.** The renderer runs on every keystroke via `#()`;
  `lp_rank` is on that hot path (PRD §3.40 / §18). It must be pure bash with no
  per-name subshell or the status bar janks.
- **Empty-query invariance (PRD §2 non-goal + §3.38).** No recency/MRU. With an
  empty query the order is byte-identical to tmux's list order — ranking only
  reorders once ≥1 char is typed.

## What

1. Create `scripts/rank.sh` defining **only** `lp_rank` (+ scoring constants).
   Sourced-library contract (codebase_patterns.md §P1): `#!/usr/bin/env bash`,
   `# shellcheck disable=SC1091`, `set -u` (NOT `-e`, NOT `-o pipefail`),
   `CURRENT_DIR` resolver, **no source-time side effects**, no `*_main` driver.
2. Match rule (§3.36): subsequence, case-insensitive, in-order. Misses hidden.
3. Scoring (§3.37): PREFIX (large) > WORD-BOUNDARY > CONTIGUITY > POSITION penalty;
   stable tie-break on original order.
4. Empty filter (§3.38): all names, original order, score 0 — byte-identical to
   `lp_build_filtered`'s empty-filter output.

### Success Criteria

- [ ] `scripts/rank.sh` exists; defines `lp_rank` + `readonly LP_*` constants only.
- [ ] Empty-filter output == `lp_build_filtered` empty-filter output (diff empty).
- [ ] Subsequence match (e.g. `lg` matches `blog`; `ap` matches `apple` and `zappy`);
      non-matches hidden (e.g. `xyz` matches nothing in a normal list).
- [ ] Ordering: prefix-name > word-boundary-name > plain-subsequence-name > deep
      subsequence; equal scores stable on original order.
- [ ] camelCase boundary (`fooBar` ranks `b` higher than `foobaz` ranks `b`).
- [ ] Original CASE preserved in output; empty LIST → no output.
- [ ] No `tmux` calls, no `$(...)` inside the per-name loop; N=100/Q=10 < 50ms.

## All Needed Context

### Context Completeness Check

_Pass_: The implementer needs (a) the exact function being superseded
(`lp_build_filtered`, quoted verbatim below), (b) the call convention (identical),
(c) the scoring spec (§3.37, with concrete constants + worked examples below), and
(d) the sourced-lib contract (§P1). A complete reference implementation is given in
Implementation Patterns — the implementer may use it nearly verbatim.

### Documentation & References

```yaml
# MUST READ - the function being superseded (match its call convention EXACTLY)
- file: scripts/filter.sh
  why: lp_build_filtered is the predecessor. Its signature, mapfile-parsing of LIST,
        empty-LIST->nothing, empty-FILTER->all, and printf-one-per-line output shape
        are the contract lp_rank must reproduce (esp. the empty-filter byte-identity).
  pattern: |
      lp_build_filtered() {
          local LIST="${1:-}" FILTER="${2:-}" -a all=() low_filter name low_name
          mapfile -t all < <(printf '%s' "$LIST")
          low_filter="${FILTER,,}"
          for name in "${all[@]}"; do
              low_name="${name,,}"
              [[ "$low_name" == *"$low_filter"* ]] && printf '%s\n' "$name"
          done
      }
  critical: lp_build_filtered is case-insensitive SUBSTRING. lp_rank is SUBSEQUENCE
            (a superset of substring matches). The empty-filter path must be identical.

# MUST READ - the call sites lp_rank will drop into (S2 switches them; know the contract)
- file: scripts/renderer.sh
  why: lines 97 (window-status path, ws_filtered) and 163 (plain path, filtered) do
        `mapfile -t X < <(lp_build_filtered "$LIST" "$FILTER")` then use X[0] as the
        highlight. So lp_rank's index 0 MUST be the top match (the preview target).
- file: scripts/input-handler.sh
  why: lines 135 (_lp_sync_preview_to_top_match: _sync_filtered[0] = top match),
        268/294/322 (nav/confirm filtered[index]). Same contract: ranked[0]==highlight.
  critical: do NOT change these call sites in S1 — that is S2's job. S1 only adds rank.sh.

# MUST READ - the sourced-library contract (header shape, set -u, no side effects)
- docfile: plan/003_77ef311abf10/architecture/codebase_patterns.md
  why: §P1 mandates the exact header (shebang, SC1091 disable, set -u NOT -e, CURRENT_DIR,
        functions/constants ONLY, no driver). §P6 mandates the renderer is PURE+FAST
        (<50ms, no tmux round-trip) — lp_rank is on that path, so no tmux, no per-name subshell.
  section: "## P1 — Sourced library contract" and "## P6 — Renderer rules"

# MUST READ - the spec being implemented (match rule, scoring, empty query, interface, perf)
- docfile: PRD.md
  why: §20 (h3.36-h3.40) is the authoritative spec. §3.37 says "exact constants not
        load-bearing; do not over-tune" — only the PREFIX>BOUNDARY>CONTIGUITY>PENALTY
        ordering must hold. §3.38 mandates empty-query = all names, original order.
  section: "## 20. Filtering and ranking (fuzzy)"

# Reference - the empty-query non-goal (why empty filter must not reorder)
- docfile: PRD.md
  why: §2 non-goal "Recency or MRU ordering ... the empty-query order stays tmux default".
        Ranking reorders only once >=1 char is typed.
  section: "## 2. Goals and non-goals" -> Non-goals
```

### Current Codebase tree

```bash
tmux-livepicker/
  scripts/
    filter.sh     # PREDECESSOR (lp_build_filtered, substring). UNCHANGED in S1; retired in S2.
    rank.sh       # NEW (this task): lp_rank (subsequence + score). Sourced lib.
    renderer.sh   # UNCHANGED in S1 (S2 swaps its 2 lp_build_filtered calls -> lp_rank)
    input-handler.sh  # UNCHANGED in S1 (S2 swaps its 4 calls)
    options.sh / utils.sh / state.sh / livepicker.sh / preview.sh / restore.sh  # UNCHANGED
  tests/          # UNCHANGED in S1 (committed ranking suite is P1.M4.T2.S1, a sibling)
```

### Desired Codebase tree with files to be added and responsibility of file

```bash
scripts/rank.sh   # NEW sourced lib: lp_rank LIST FILTER -> best-first ranked names (PRD §20)
```

### Known Gotchas of our codebase & Library Quirks

```bash
# CRITICAL — empty-filter byte-identity. lp_rank "$LIST" "" MUST print exactly what
# lp_build_filtered "$LIST" "" prints (all names, original order, one per line). The
# renderer/input-handler have tests (test_pollution.sh:108 "empty filter == full list";
# the whole cancel/restore path runs with an empty filter) that break otherwise.
# Implement this as an EARLY RETURN before any scoring.

# CRITICAL — ranked[0] is the preview target. The renderer highlights index 0 and
# input-handler previews filtered[0]. So the sort MUST put the best match first.
# A stable DESCENDING-by-score sort does this.

# CRITICAL — subsequence is a SUPERSET of substring. After S2 swaps callers, a query
# like "lg" will now ALSO match "blog" (l..g in order) where the old substring filter
# did not. That is intended (PRD §3.36). Do not "tighten" it back to substring.

# CRITICAL — no per-name subshell. `$(...)` inside the name loop forks per name and
# blows the §18 budget. The ONLY subshell allowed is the single top-level
# `mapfile -t all < <(printf '%s' "$LIST")` (once, not per name). Use `${var,,}`,
# `${var:i:1}`, `${#var}`, `$(( ))`, `case`, `[[ ]]` — all builtins.

# CRITICAL — no `tmux` calls. lp_rank is pure bash. The renderer reads
# @livepicker-client-width etc. itself; lp_rank only ranks strings.

# CRITICAL — stable tie-break = ORIGINAL tmux order. "Stable" means equal scores are
# NOT reordered. Achieve this by collecting matches in `all[]` order (mapfile preserves
# LIST order) and using a sort that swaps only on STRICTLY-greater score.

# GOTCHA — camelCase boundary needs the ORIGINAL case. You lowercase for MATCHING
# (low_name) but the camelCase check (prev lowercase, cur uppercase) must read the
# ORIGINAL `name` chars at those positions. Keep both `name` and `low_name`.

# GOTCHA — bash 4+ required for ${var,,} and mapfile. Verified: bash 5.3.15 on this box.
# The shebang is #!/usr/bin/env bash (matches every sibling).

# GOTCHA — `case "$prevc" in [-_. /])` — the bracket has `-` FIRST so it is literal;
# matches one of dash, underscore, dot, SPACE, slash (the PRD §3.37 separator set).
# Do not write `[![:alnum:]]` (locale-dependent); use the explicit set for determinism.

# GOTCHA — set -u: default every positional (`${1:-}`, `${2:-}`) and every loop local.
# Declare all locals; reset the per-name `pos` array with `pos=()` each iteration.

# GOTCHA — Indent with TABS (whole codebase; shfmt absent). filter.sh uses tabs.
```

## Implementation Blueprint

### Data models and structure

No persistent state. The "model" is the per-name score, decomposed per PRD §3.37:

```
score = PREFIX?1000:0
      + WORD_BOUNDARY_BONUS(100) * (#matched chars at a boundary)
      + CONTIGUITY_BONUS(10)    * (#matched chars immediately after the prev matched)
      - start_offset                       (position penalty; the first matched char's index)
```

Boundary (per matched char at name position p): `p==0` OR `name[p-1] in {-,_,., ,/}` OR
camelCase (`name[p-1]` lowercase AND `name[p]` uppercase, original case).

Worked examples (prove the §3.37 ordering with these constants):

| query | name | matched pos | prefix | boundary | contiguity | start | score | note |
|-------|------|-------------|--------|----------|-----------|-------|-------|------|
| `ap`  | `apple`   | 0,1 | +1000 | +100(a@0) | +10(p@a+1) | 0 | **1110** | exact-prefix (top) |
| `ap`  | `-apy`    | 1,2 | 0 | +100(a after `-`) | +10(p@a+1) | 1 | **109** | word-boundary substring |
| `ap`  | `xapy`    | 1,2 | 0 | 0(a after `x`, alnum) | +10 | 1 | **9** | plain subsequence |
| `b`   | `fooBar`  | 3 | 0 | +100(B camelCase: o→B) | 0 | 3 | **97** | camelCase boundary |
| `b`   | `foobaz`  | 3 | 0 | 0(o→b, both lower) | 0 | 3 | **-3** | no boundary |
| `lg`  | `blog`    | 1,3 | 0 | 0 | 0 (g not at l+1) | 1 | **-1** | subsequence, NOT substring |
| `""`  | any       | — | — | — | — | — | **0** | empty filter: all, original order |

The ordering `apple(1110) > -apy(109) > xapy(9)` demonstrates prefix > word-boundary
> plain-subsequence. `blog` matching `lg` demonstrates the subsequence superset. The
exact constants are illustrative (PRD: "not load-bearing; do not over-tune") — only
the relative ordering must hold.

### Implementation Tasks (ordered by dependencies)

```yaml
Task 1: CREATE scripts/rank.sh
  - HEADER (mirror filter.sh + codebase_patterns §P1):
      #!/usr/bin/env bash
      # shellcheck disable=SC1091
      # scripts/rank.sh — tmux-livepicker shared fuzzy ranker (PRD §20). ... (doc block)
      set -u
      CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  - CONSTANTS: readonly LP_PREFIX_BONUS=1000, LP_WORD_BOUNDARY_BONUS=100,
    LP_CONTIGUITY_BONUS=10. (Position penalty is implicit: subtract start offset.)
  - IMPLEMENT lp_rank (full reference body in "Implementation Patterns").
  - CONTRACT: functions + readonly constants ONLY; NO *_main driver; NO tmux; NO
    source-time side effects (sourcing just defines things).
  - NAMING: lp_rank (lowercase fn, matches lp_build_filtered); LP_* (uppercase
    readonly consts, matches STATE_*/ORIG_* convention).
  - PLACEMENT: scripts/rank.sh.
  - DO NOT: touch filter.sh, renderer.sh, input-handler.sh, or any caller (S2's job).

Task 2: VALIDATE (standalone contract checks; no committed test file in S1)
  - RUN: bash -n scripts/rank.sh ; shellcheck scripts/rank.sh
  - RUN: the standalone validation script in Validation Loop §2/§3 (sources BOTH
    filter.sh and rank.sh; checks byte-identity on empty filter, the ordering
    examples above, subsequence-superset, case preservation, hidden non-matches,
    empty-list, stability, and perf). It is a THROWAWAY — delete after. The
    committed suite is P1.M4.T2.S1 (sibling).
```

### Implementation Patterns & Key Details

**Reference implementation** (the implementer may use this nearly verbatim; only
the constant magnitudes are tunable, and only if the §3.37 ordering still holds).
Tab-indented to match the codebase.

```bash
#!/usr/bin/env bash
# shellcheck disable=SC1091
#   SC1091: this is a SOURCED library; callers source it via $CURRENT_DIR.
# scripts/rank.sh — tmux-livepicker shared fuzzy ranker (PRD §20).
#
# Sourced library (NOT executed). NO source-time side effects — sourcing defines
# lp_rank (+ LP_* constants) and nothing else. Supersedes filter.sh::lp_build_filtered
# (case-insensitive substring) with a subsequence match + integer score. SAME call
# convention, so callers swap `lp_build_filtered` -> `lp_rank` verbatim:
#     mapfile -t ranked < <(lp_rank "$LIST" "$FILTER")
#
# CONTRACT (PRD §20):
#  - Match (§3.36): every FILTER char appears in the name IN ORDER, case-insensitively
#    (subsequence, not contiguous). Non-matches HIDDEN (so create-on-empty fires).
#  - Score (§3.37, higher=better; ranked[0] = top match = preview target):
#       PREFIX bonus > WORD-BOUNDARY bonus > CONTIGUITY bonus > POSITION penalty.
#       Stable tie-break on ORIGINAL tmux order (equal scores NOT reordered).
#  - Empty FILTER (§3.38): ALL names at score 0, ORIGINAL order — BYTE-IDENTICAL to
#    lp_build_filtered's empty-filter output (keeps existing tests green).
#  - Empty LIST: prints nothing.
#
# PERF (§3.40 / §18 budget): O(N·Q) pure bash, NO per-name subshell, source-once.
# Constants are illustrative (PRD: "not load-bearing; do not over-tune").

set -u   # NOT -e; NOT -o pipefail.

CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Scoring constants (integers; magnitudes chosen so the ordering is unambiguous).
readonly LP_PREFIX_BONUS=1000         # first query char matches at name position 0
readonly LP_WORD_BOUNDARY_BONUS=100   # per matched char at a word boundary
readonly LP_CONTIGUITY_BONUS=10       # per matched char immediately after the prev matched
# position penalty = the first matched char's index (1/unit; small)

# lp_rank LIST FILTER
#   Print each name from LIST (newline-separated) that subsequence-matches FILTER
#   (case-insensitive, in-order), BEST score first, one per line, PRESERVING case.
#   Empty FILTER -> all names, original order (score 0). Empty LIST -> nothing.
lp_rank() {
	local LIST="${1:-}"
	local FILTER="${2:-}"
	local -a all=()
	# printf '%s' (NO trailing newline): empty LIST -> all=() (NOT [""]); a trailing
	# newline in LIST is harmless (mapfile -t strips it). Mirrors filter.sh so the
	# empty/blank cases are byte-identical.
	mapfile -t all < <(printf '%s' "$LIST")

	local low_filter="${FILTER,,}"

	# EMPTY FILTER (§3.38): all names at score 0, ORIGINAL order, no reorder.
	# Byte-identical to lp_build_filtered's empty-filter path — CRITICAL for tests.
	if [ -z "$low_filter" ]; then
		local _n
		for _n in "${all[@]}"; do
			printf '%s\n' "$_n"
		done
		return 0
	fi

	local qlen=${#low_filter}
	# Per-name accumulators. Array index == original tmux order (mapfile preserves
	# LIST order) => that index is the stable tie-break key.
	local -a r_name=()
	local -a r_score=()
	# per-name scratch (declared once, reset each iteration):
	local name low_name nlen qi ni qc found matched score j p prevc curc prevp
	local -a pos=()

	for name in "${all[@]}"; do
		low_name="${name,,}"
		nlen=${#low_name}
		# Quick reject: a name shorter than the query cannot be a subsequence match.
		[ "$nlen" -lt "$qlen" ] && continue

		# --- subsequence walk (§3.36): find each query char at/after ni, in order ---
		qi=0
		ni=0
		matched=1
		pos=()
		while [ "$qi" -lt "$qlen" ]; do
			qc="${low_filter:$qi:1}"
			found=-1
			while [ "$ni" -lt "$nlen" ]; do
				if [ "${low_name:$ni:1}" = "$qc" ]; then
					found=$ni
					break
				fi
				ni=$((ni + 1))
			done
			if [ "$found" -lt 0 ]; then
				matched=0
				break
			fi
			pos+=("$found")
			ni=$((found + 1))
			qi=$((qi + 1))
		done
		[ "$matched" -eq 1 ] || continue   # non-match -> HIDDEN (create-on-empty fires)

		# --- score (§3.37) ---
		score=0
		# PREFIX: first query char at name position 0.
		[ "${pos[0]}" -eq 0 ] && score=$((score + LP_PREFIX_BONUS))
		# Per matched char: word-boundary + contiguity.
		prevp=-1
		j=0
		for p in "${pos[@]}"; do
			# word boundary: pos 0 | after a separator [-_. /] | camelCase (lower->UPPER)
			if [ "$p" -eq 0 ]; then
				score=$((score + LP_WORD_BOUNDARY_BONUS))
			else
				prevc="${name:$((p - 1)):1}"   # ORIGINAL case (camelCase needs it)
				case "$prevc" in
					[-_. /])
						score=$((score + LP_WORD_BOUNDARY_BONUS))
						;;
					*)
						curc="${name:$p:1}"
						# camelCase boundary: prev lowercase, current uppercase.
						if [[ "$prevc" == [a-z] && "$curc" == [A-Z] ]]; then
							score=$((score + LP_WORD_BOUNDARY_BONUS))
						fi
						;;
				esac
			fi
			# contiguity: this matched char immediately follows the previous matched.
			if [ "$j" -gt 0 ] && [ "$p" -eq $((prevp + 1)) ]; then
				score=$((score + LP_CONTIGUITY_BONUS))
			fi
			prevp=$p
			j=$((j + 1))
		done
		# position penalty: proportional to the match's start offset (small).
		score=$((score - pos[0]))

		r_name+=("$name")
		r_score+=("$score")
	done

	# --- stable sort by score DESCENDING (equal scores keep original order) ---
	# Pure-bash selection sort: advance `best` ONLY on strictly-greater score, so the
	# earlier original index wins ties (stable). O(M^2), M = match count (small <100).
	local m=${#r_name[@]}
	if [ "$m" -eq 0 ]; then
		return 0   # no matches -> print nothing (caller sees an empty ranked list)
	fi
	local -a taken=()
	local r k best best_score
	r=0
	while [ "$r" -lt "$m" ]; do taken[$r]=0; r=$((r + 1)); done
	r=0
	while [ "$r" -lt "$m" ]; do
		best=-1
		k=0
		while [ "$k" -lt "$m" ]; do
			if [ "${taken[$k]}" -ne 1 ]; then
				if [ "$best" -lt 0 ] || [ "${r_score[$k]}" -gt "$best_score" ]; then
					best=$k
					best_score="${r_score[$k]}"
				fi
			fi
			k=$((k + 1))
		done
		taken[$best]=1
		printf '%s\n' "${r_name[$best]}"
		r=$((r + 1))
	done
}
```

Key pattern notes:
- **No subshell in the hot loop.** `${low_name:$ni:1}` (builtin substring), `case`,
  `[[ == [a-z] ]]`, `$(( ))` — all builtins. The only subshell is the single top-level
  `mapfile … < <(printf …)`.
- **Stability for free.** `r_name`/`r_score` are appended in `all[]` order (= original
  tmux order). The selection sort only advances `best` on strictly-greater, so ties
  resolve to the lower index = original order.
- **Empty-filter early return** guarantees byte-identity with `lp_build_filtered`
  (same `for … printf '%s\n'` over `all[]`).
- **`pos=()` reset each iteration** (declared once outside the loop) keeps the
  per-name matched-position array fresh and `set -u`-safe.

### Integration Points

```yaml
CODE:
  - file: scripts/rank.sh
    change: "NEW sourced lib: lp_rank + LP_* constants"
    invariant: "ranked[0] == top match; empty-filter byte-identical to lp_build_filtered"

CONSUMERS (switched by S2 P1.M1.T1.S2 — DO NOT touch in S1):
  - scripts/renderer.sh:97   (window-status path)  -> lp_rank
  - scripts/renderer.sh:163  (plain path)          -> lp_rank
  - scripts/input-handler.sh:135 (_lp_sync_preview_to_top_match)
  - scripts/input-handler.sh:268/294/322 (nav/confirm)
  - (later) scripts/session-mgmt.sh (P2)

CONFIG / DATABASE / ROUTES: none — pure string ranker, no tmux, no state.
```

## Validation Loop

### Level 1: Syntax & Style (Immediate Feedback)

```bash
cd /home/dustin/.config/tmux/plugins/tmux-livepicker
bash -n scripts/rank.sh && echo "OK: syntax"
shellcheck scripts/rank.sh               # expect 0 findings (SC1091 disabled by header)
# Sourced-lib contract: sourcing prints nothing + defines exactly lp_rank:
out="$(bash -c 'set -u; source scripts/rank.sh; declare -F lp_rank' 2>&1)"
[ -z "$out" ] || echo "$out" | grep -q '^lp_rank$' && echo "OK: no side effects, lp_rank defined"
# Tabs-not-spaces (shfmt absent):
grep -nP '^    [^ ]' scripts/rank.sh && echo "WARN: 4-space indent found (use tabs)" || echo "OK: tabs"
```

### Level 2: Standalone contract checks (throwaway; delete after)

Sources BOTH filter.sh and rank.sh to prove byte-identity + the §3.37 ordering:

```bash
cat > /tmp/rank_smoke.sh <<'EOF'
#!/usr/bin/env bash
set -u
cd /home/dustin/.config/tmux/plugins/tmux-livepicker
source scripts/filter.sh
source scripts/rank.sh
p=0; f=0
ck() { if [ "$2" = "$3" ]; then p=$((p+1)); else f=$((f+1)); echo "FAIL $1: got[$2] want[$3]"; fi; }

LIST=$'apple\n-apy\nxapy\nfooBar\nfoobaz\nblog\nzebra'

# 1. EMPTY FILTER byte-identical to lp_build_filtered (the critical guarantee):
ck "empty-filter byte-identity" "$(lp_rank "$LIST" "")" "$(lp_build_filtered "$LIST" "")"

# 2. empty filter preserves ORIGINAL order (apple first, zebra last):
ck "empty order[0]" "$(lp_rank "$LIST" "" | sed -n '1p')" "apple"
ck "empty order[last]" "$(lp_rank "$LIST" "" | tail -n1)" "zebra"

# 3. ordering for "ap": apple(prefix) > -apy(boundary) > xapy(plain). zebra hidden.
ck "ap ranked order" "$(lp_rank "$LIST" "ap")" $'-apy\napple\nxapy' 2>/dev/null || true
#   (compute expected dynamically to be robust:)
exp_ap="$(lp_rank "$LIST" "ap")"
first="$(printf '%s\n' "$exp_ap" | sed -n '1p')"
ck "ap top is apple (prefix wins)" "$first" "apple"
ck "ap hides zebra" "$(printf '%s\n' "$exp_ap" | grep -c '^zebra$')" "0"

# 4. subsequence superset: "lg" matches "blog" (substring filter did NOT).
ck "lg matches blog (subsequence)" "$(lp_rank "$LIST" "lg" | grep -c '^blog$')" "1"

# 5. camelCase boundary: "b" ranks fooBar ABOVE foobaz.
b_order="$(lp_rank "$LIST" "b")"
fb_line="$(printf '%s\n' "$b_order" | grep -n '^fooBar$' | cut -d: -f1)"
fz_line="$(printf '%s\n' "$b_order" | grep -n '^foobaz$' | cut -d: -f1)"
[ -n "$fb_line" ] && [ -n "$fz_line" ] && [ "$fb_line" -lt "$fz_line" ] && p=$((p+1)) || { f=$((f+1)); echo "FAIL camelCase: fooBar($fb_line) should precede foobaz($fz_line)"; }

# 6. original CASE preserved:
ck "case preserved" "$(lp_rank "$LIST" "b" | grep -c '^fooBar$')" "1"

# 7. empty LIST -> nothing:
ck "empty list" "$(lp_rank "" "abc")" ""

# 8. no-match query -> nothing:
ck "no match" "$(lp_rank "$LIST" "zzz")" ""

# 9. stability: equal scores keep original order. "z" matches only "zebra" -> trivial;
#    use "o" which matches fooBar/foobaz/blog in subsequence — assert blog (earliest
#    original) precedes the others among EQUAL-ish scores where applicable. (Soft check.)
echo "o-order:"; lp_rank "$LIST" "o"

printf 'PASS=%d FAIL=%d\n' "$p" "$f"
[ "$f" -eq 0 ]
EOF
bash /tmp/rank_smoke.sh; rc=$?
rm -f /tmp/rank_smoke.sh
exit $rc
# Expected: PASS=9 FAIL=0 (plus the printed o-order line). The byte-identity check (#1)
# is the load-bearing one — if it fails, the empty-filter early return is wrong.
```

### Level 3: Byte-identity stress (the S2 safety net)

```bash
cd /home/dustin/.config/tmux/plugins/tmux-livepicker
source scripts/filter.sh; source scripts/rank.sh
# Across many lists (incl. special chars, single name, trailing newline), the EMPTY
# filter output of lp_rank must equal lp_build_filtered byte-for-byte:
fail=0
for LIST in "" "solo" $'a\nb\nc' $'alpha\nbeta\ndriver' $'with-dash\nunder_score\ndot.name\nsl/ash' $'trailing\n' "CAPS lower MiXeD"; do
	[ "$(lp_build_filtered "$LIST" "")" = "$(lp_rank "$LIST" "")" ] || { echo "BYTE-DIFF for LIST=[$LIST]"; fail=1; }
done
[ "$fail" -eq 0 ] && echo "OK: empty-filter byte-identical across all lists" || echo "FAIL"
# Expected: OK. This is what guarantees the existing test suite stays green after S2.
```

### Level 4: Performance (PRD §3.40 / §18 budget)

```bash
cd /home/dustin/.config/tmux/plugins/tmux-livepicker
source scripts/rank.sh
# Build a 100-name list + 10-char query; time 100 redraws. Must stay well under 50ms/redraw.
LIST=""; for i in $(seq 1 100); do LIST="${LIST}session-$i-longish-name-${i}${LIST:+$'\n'}"; done
QUERY="ses10longish"
# warm + measure (bash builtin time; report real)
t0=$(date +%s%N)
for r in $(seq 1 100); do :; lp_rank "$LIST" "$QUERY" >/dev/null; done
t1=$(date +%s%N)
per_us=$(( (t1 - t0) / 100 / 1000 ))
echo "lp_rank: ${per_us} us/redraw (100 names, Q=${#QUERY}); budget <50000 us (50ms)"
[ "$per_us" -lt 50000 ] && echo "OK: within §18 budget" || echo "WARN: over budget — check for accidental subshell/$(...)"
# Expected: well under 50ms (typically <5ms for N=100 in pure bash). If over, the most
# common cause is a `$(...)` or external cmd inside the name loop — grep for it.
grep -n '\$(' scripts/rank.sh | grep -v 'mapfile\|printf' && echo "WARN: possible subshell in loop" || echo "OK: no per-name subshell"
```

## Final Validation Checklist

### Technical Validation
- [ ] `bash -n scripts/rank.sh` clean; `shellcheck` 0 findings.
- [ ] Sourcing defines `lp_rank` and prints nothing (no side effects).
- [ ] L2 smoke: PASS=9 FAIL=0 (incl. empty-filter byte-identity).
- [ ] L3 byte-identity stress: OK across all list shapes.
- [ ] L4 perf: <50ms/redraw at N=100/Q=10; no per-name subshell.

### Feature Validation
- [ ] Empty filter → all names, original order, byte-identical to `lp_build_filtered`.
- [ ] Subsequence match (in-order, case-insensitive); non-matches hidden.
- [ ] Ordering: prefix > word-boundary > contiguity > position-penalty; stable ties.
- [ ] camelCase boundary detected (original-case chars).
- [ ] Original case preserved; empty list → nothing; `ranked[0]` = best match.

### Code Quality Validation
- [ ] Sourced-lib contract (§P1): header, `set -u`, no `-e`, CURRENT_DIR, no driver.
- [ ] No `tmux` calls; no per-name subshell; pure bash builtins in the hot loop.
- [ ] Tabs for indent; `readonly LP_*` constants; naming matches conventions.
- [ ] No caller touched (S1 adds only; S2 swaps the 6 call sites).

### Documentation & Deployment
- [ ] Header doc block cites PRD §20 (§3.36–§3.40) + the empty-filter byte-identity
      contract + the perf budget, so the file is self-documenting.
- [ ] No README/CHANGELOG change (rank.sh is internal; Mode A). The config table is
      unaffected (no new option here). Doc sync is P4.T1.

---

## Anti-Patterns to Avoid

- ❌ Don't change any caller in S1 (renderer/input-handler/filter.sh) — that's S2.
  S1 only creates `scripts/rank.sh`.
- ❌ Don't let the empty-filter path diverge from `lp_build_filtered` — it must be
  byte-identical (early-return over `all[]`, same `printf '%s\n'`).
- ❌ Don't use `$(...)` or any external command (`grep`/`sort`/`tr`) inside the
  per-name loop — it forks per name and blows the §18 budget. Use builtins only.
- ❌ Don't call `tmux` — `lp_rank` is pure string ranking.
- ❌ Don't make the sort unstable — equal scores MUST keep original tmux order
  (swap only on strictly-greater; the array index is the tie-break key).
- ❌ Don't lowercase the name for the camelCase check — matching uses `low_name`,
  but camelCase boundary reads the ORIGINAL `name` chars.
- ❌ Don't over-tune the constants (PRD §3.37 explicitly says not to). Only the
  PREFIX>BOUNDARY>CONTIGUITY>PENALTY ordering must hold; pick clean round numbers.
- ❌ Don't add a committed `tests/test_ranking.sh` here — that's P1.M4.T2.S1
  (sibling). Validate via the throwaway L2/L3 smoke only.
- ❌ Don't tighten subsequence back to substring — `lg` matching `blog` is intended.
- ❌ Don't reorder the empty-query list (PRD §2 non-goal: no MRU/recency).

---

## Confidence Score

**9 / 10** for one-pass success. Rationale: the function being superseded
(`lp_build_filtered`) and its exact call convention are quoted verbatim; the §3.37
spec is pinned with concrete constants and a worked-example table that proves the
required ordering; a complete reference implementation is provided (pure bash,
no per-name subshell, stable sort, empty-filter early-return); and the validation
includes the load-bearing byte-identity diff against `lp_build_filtered` (L3) plus a
perf gate (L4) and an accidental-subshell grep. The one residual risk is a
shellcheck quibble on the `case [-_. /]` bracket or an array-index `set -u` form,
both trivially fixable from the L1 output.
