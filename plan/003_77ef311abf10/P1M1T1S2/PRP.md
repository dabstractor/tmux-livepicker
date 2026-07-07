# PRP — P1.M1.T1.S2: Switch 6 filter.sh call sites to rank.sh; retire filter.sh

> **Context**: S1 (P1.M1.T1.S1) created `scripts/rank.sh` exposing `lp_rank LIST FILTER`
> — a fuzzy subsequence ranker with the **same call convention** as
> `filter.sh::lp_build_filtered`. This subtask swaps the 6 consumers to `lp_rank`,
> deletes `filter.sh`, and proves the 44-green suite is unchanged. **Pure refactor**:
> no behavior change for empty/common filters (the subsequence match set is a superset
> of substring, and scoring only reorders once ≥1 char is typed — empty query is
> byte-identical, per S1's contract + verified in research/swap_findings.md §4).

---

## Goal

**Feature Goal**: `renderer.sh` and `input-handler.sh` source `rank.sh` and call
`lp_rank` at all 6 filtering call sites; `scripts/filter.sh` is deleted. One ranker
(`lp_rank`) is the single source of truth for "what the renderer shows" and "what
nav/confirm resolve", with **zero behavior change** on the empty/common-filter paths
that the 44 tests exercise.

**Deliverable**:
- MODIFIED `scripts/renderer.sh` (2 call sites: lines 97, 163 → `lp_rank`; source 44-45 → `rank.sh`).
- MODIFIED `scripts/input-handler.sh` (4 call sites: lines 135, 268, 294, 322 → `lp_rank`; source 60-61 → `rank.sh`; 2 comments auto-updated).
- DELETED `scripts/filter.sh`.
- No other file functionally changes (2 stale TEST comments are optional polish — §Known Gotchas).

**Success Definition**:
- `grep -rn 'lp_build_filtered\|filter\.sh' scripts/renderer.sh scripts/input-handler.sh` → nothing.
- `scripts/filter.sh` does not exist.
- `bash -n` + `shellcheck -x scripts/*.sh` clean.
- `bash tests/run.sh` → **44 passed, 0 failed** (no regression).
- Empty-filter output of `lp_rank` is byte-identical to the former `lp_build_filtered`
  (verified pre-delete via a diff against filter.sh while both still exist).

## User Persona (if applicable)

**Target User**: The maintainers / CI. End users see no difference on the empty/common
queries they already use; they gain fuzzy subsequence matching (e.g. `lg`→`blog`) once
S2 lands (the intended §3.36 behavior S1 made possible).

**Use Case**: A user types a query; the renderer and the nav/confirm resolver now use
the SAME fuzzy ranker, so "what's highlighted" and "what Enter lands on" can never drift.

**Pain Points Addressed**: Two divergent filter notions (substring in filter.sh) would
have left the codebase with dead, superseded logic. Retiring filter.sh removes the
divergence risk permanently.

---

## Why

- **Single source of truth (PRD §20 / §6).** `filter.sh` and `rank.sh` cannot both
  exist — if a future edit touched one but not the other, the renderer's view and
  nav/confirm's resolution would silently diverge. S1 added rank.sh; S2 finishes the
  job by retiring filter.sh.
- **Byte-identical empty-filter path keeps the suite green by construction.** S1
  guarantees `lp_rank "$LIST" "" == lp_build_filtered "$LIST" ""`. After S2, every
  empty-filter call (the entire cancel/restore lifecycle + the default no-query state)
  routes through lp_rank and is unchanged. Verified (research §4).
- **Zero scope creep.** No new behavior, no new option, no doc/API surface. Internal
  refactor; the committed ranking suite is a sibling (P1.M4.T2.S1).

## What

1. **PRECONDITION**: confirm S1 landed — `scripts/rank.sh` exists and defines `lp_rank`
   (verify with `declare -F lp_rank` after sourcing). If absent, S1 hasn't merged — STOP.
2. **Swap** all `lp_build_filtered` → `lp_rank` and all `filter.sh` → `rank.sh` in the
   two consumers via two global `sed -i` commands (verified; see Implementation Patterns).
3. **Delete** `scripts/filter.sh`.
4. **Validate**: `bash -n` + `shellcheck -x` clean; empty-filter byte-identity holds;
   `bash tests/run.sh` is 44-green.

### Success Criteria

- [ ] `scripts/rank.sh` is sourced by both renderer.sh (line 44-45 slot) and input-handler.sh (60-61).
- [ ] All 6 call sites call `lp_rank` (renderer: ws_filtered@97, filtered@163; input-handler:
      _sync_filtered@135, filtered@268/294/322).
- [ ] `scripts/filter.sh` is deleted; nothing sources it.
- [ ] `bash tests/run.sh` → 44 passed, 0 failed.
- [ ] `shellcheck -x scripts/*.sh` clean.

## All Needed Context

### Context Completeness Check

_Pass_: the implementer needs (a) the exact 6 call sites + source/directive lines
(tabulated below), (b) the two verified `sed -i` commands, (c) awareness that the 3
nav/confirm lines are byte-identical (so `sed` beats the `edit` tool), (d) the S1
precondition, and (e) the validation gates. Every fact is empirically verified in
`research/swap_findings.md`.

### Documentation & References

```yaml
# MUST READ — S1's PRP (the lp_rank contract S2 consumes)
- docfile: plan/003_77ef311abf10/P1M1T1S1/PRP.md
  why: defines lp_rank LIST FILTER with the IDENTICAL call convention to lp_build_filtered
       (`mapfile -t X < <(lp_rank "$LIST" "$FILTER")`). S1's load-bearing guarantee:
       empty-filter output is byte-identical to lp_build_filtered — that is WHY the
       44-green suite stays green after the swap.
  critical: lp_rank is SUBSEQUENCE (superset of substring). After S2, a query like "lg"
            matches "blog" where the old substring filter did not. INTENDED (PRD §3.36).
            Do not "tighten" callers back to substring.

# MUST READ — the empirical swap map + verified sed commands (this subtask's ground-truth)
- docfile: plan/003_77ef311abf10/P1M1T1S2/research/swap_findings.md
  why: §1 tabulates every reference (file:line + change); §2 explains why sed (3 identical
       lines defeat the edit tool); §3 gives the verified sed commands + their result;
       §4 proves empty-filter byte-identity; §5 proves the only behavior change is the
       intended subsequence superset; §6 proves deleting filter.sh is safe.
  critical: §3 — the two sed commands are the entire mechanical change. Run them verbatim.

# MUST READ — the sourced-library + source-order contract
- docfile: plan/003_77ef311abf10/architecture/codebase_patterns.md
  why: §P1 mandates source order options→utils→state→(filter|rank).sh and that
       # shellcheck source= directives switch filter.sh→rank.sh. §P6 mandates the renderer
       stays PURE+FAST (lp_rank is already pure bash, no tmux — S1's job; S2 doesn't change that).
  section: "## P1 — Sourced library contract"

# Reference — the file being superseded (read BEFORE deleting, to confirm the contract)
- file: scripts/filter.sh
  why: lp_build_filtered is the predecessor. Its mapfile-parsing of LIST, empty-LIST->nothing,
       empty-FILTER->all-in-original-order, and printf-one-per-line output are the contract
       lp_rank reproduces. DELETE this file in Task 3 (after the swap).
  gotcha: filter.sh is a LEAF lib (sources nothing). Swapping it for rank.sh (also a leaf)
          changes NO transitive dependencies and NO source order.

# Reference — the consumers being modified (read to confirm the exact lines)
- file: scripts/renderer.sh
  why: lines 44-45 (source+directive) and 97 (ws_filtered, §17 path), 163 (filtered, plain).
  pattern: `mapfile -t X < <(lp_build_filtered "$L" "$F")` then `X[0]` = highlight. lp_rank's
           index 0 is the top match — the contract is identical.
- file: scripts/input-handler.sh
  why: lines 60-61 (source+directive), 135 (_sync_preview_to_top_match), 268/294/322
       (next-session/prev-session/confirm — BYTE-IDENTICAL 3-tab-indented lines).
  gotcha: 268/294/322 are identical => use `sed`, NOT the edit tool (which needs unique oldText).

# Reference — the spec being honored
- docfile: PRD.md
  why: §20 (h3.36-h3.40) is the ranker spec; §12 file layout already lists rank.sh (not filter.sh).
  section: "## 20. Filtering and ranking (fuzzy)" and "## 12. File layout"
```

### Current Codebase tree

```bash
scripts/
  filter.sh        # PREDECESSOR — DELETE in S2 (lp_build_filtered, substring)
  rank.sh          # S1's NEW lib — lp_rank (subsequence + score). S2's consumers switch to it.
  renderer.sh      # MODIFY: source rank.sh; 2 lp_build_filtered -> lp_rank
  input-handler.sh # MODIFY: source rank.sh; 4 lp_build_filtered -> lp_rank
  options.sh utils.sh state.sh livepicker.sh preview.sh restore.sh  # UNCHANGED
tests/             # UNCHANGED (2 stale COMMENTS optional — see Gotchas)
```

### Desired Codebase tree with files to be added and responsibility of file

```bash
scripts/filter.sh   # REMOVED (fully superseded by rank.sh; no divergent substring logic left)
scripts/renderer.sh        # sources rank.sh; calls lp_rank at the 2 filter sites
scripts/input-handler.sh   # sources rank.sh; calls lp_rank at the 4 filter sites
```

### Known Gotchas of our codebase & Library Quirks

```bash
# CRITICAL — PRECONDITION: S1 must have landed. Verify BEFORE swapping:
#   ls scripts/rank.sh && bash -c 'set -u; source scripts/rank.sh; declare -F lp_rank'
# must print 'lp_rank'. If rank.sh is absent or lp_rank undefined, S1 hasn't merged — STOP.

# CRITICAL — the 3 nav/confirm lines (input-handler.sh 268/294/322) are BYTE-IDENTICAL
# (3-tab indent, same mapfile line). The `edit` tool rejects non-unique oldText, so
# disambiguating them needs verbose per-site anchors. USE `sed -i` for the swap instead
# (verified correct; handles all 6 sites + comments in one pass).

# CRITICAL — both seds are SURGICAL (verified, will not over-match):
#   `s/lp_build_filtered/lp_rank/g` matches ONLY the function name (never "filtered"/"filter").
#   `s|filter\.sh|rank.sh|g`     matches ONLY the literal filename `filter.sh` (the `\.` anchors
#     the dot; NEVER "filtered list" / "shared filter" / "top filtered match" concept comments).
# Do NOT broaden them to `filter` (would mangle dozens of unrelated "filtered[index]" comments).

# CRITICAL — empty-filter byte-identity is load-bearing. lp_rank "$LIST" "" MUST equal what
# lp_build_filtered "$LIST" "" produced. S1 guarantees this; verify pre-delete (Validation L2)
# by sourcing BOTH and diffing on empty filter while filter.sh still exists.

# CRITICAL — source ORDER is load-bearing (codebase_patterns §P1): options→utils→state→
# (filter|rank).sh. The sed renames filter.sh→rank.sh IN PLACE (same line/position), so the
# order is preserved. Do NOT move the source line.

# CRITICAL — subsequence is a SUPERSET of substring. After the swap, "lg" matches "blog",
# "bl" matches "blog", etc. This is INTENDED (PRD §3.36). It only ADDS matches (never
# removes), so no positive test assertion breaks and no negative assertion breaks (verified:
# the only negative assertion, test_typing_filters excluding alpha/driver for "log", holds —
# neither is a subsequence match).

# GOTCHA — rank.sh's OWN header comments reference "filter.sh" historically ("Supersedes
# filter.sh::lp_build_filtered"; "Mirrors filter.sh ..."). Those are S1's documentation and
# are HISTORICAL (still meaningful after deletion). S2 does NOT touch rank.sh (S1's scope).

# GOTCHA — two TEST files mention the old name in COMMENTS only (non-functional):
#   tests/test_pollution.sh:108 "(filter.sh)" and tests/test_responsiveness.sh:73
#   "Mirrors lp_build_filtered: case-insensitive substring". These are OUT of the stated S2
#   scope and comment-only (suite unaffected). Updating them is OPTIONAL polish; not required
#   for the green suite. If updated: filter.sh->rank.sh; lp_build_filtered: substring ->
#   lp_rank: subsequence (a superset of substring).

# GOTCHA — DELETE filter.sh with `rm` (or `git rm scripts/filter.sh` if you want the deletion
# staged). After the swap, grep confirms nothing sources it.

# GOTCHA — Indent with TABS (whole codebase). sed preserves existing content verbatim
# (it only swaps the two tokens), so tabs are untouched. Do NOT run a formatter (shfmt absent).
```

## Implementation Blueprint

### Data models and structure

No data model. The change is a 1:1 textual substitution at 6 call sites + 2 source
lines + 2 directives, plus a file deletion. The "model" is the call convention:
`mapfile -t X < <(lp_rank "$LIST" "$FILTER")` — identical shape to the old
`lp_build_filtered` call, so the surrounding `X[0]` / `${#X[@]}` / `X[$idx]` logic in
every consumer is untouched.

### Implementation Tasks (ordered by dependencies)

```yaml
PRECONDITION: S1 (P1.M1.T1.S1) is applied — scripts/rank.sh exists and defines lp_rank.
  VERIFY:
    ls scripts/rank.sh && \
    bash -c 'set -u; source scripts/rank.sh; declare -F lp_rank'   # must print: lp_rank
  If absent/undefined, S1 hasn't merged — STOP and flag it. Do NOT create rank.sh (S1's scope).

Task 1: SWAP the 6 call sites + source/directive lines (two sed -i commands; verified)
  - RUN (verbatim from research/swap_findings.md §3):
      sed -i 's/lp_build_filtered/lp_rank/g' scripts/renderer.sh scripts/input-handler.sh
      sed -i 's|filter\.sh|rank.sh|g'    scripts/renderer.sh scripts/input-handler.sh
  - EFFECT (verified): all 6 lp_build_filtered -> lp_rank (renderer 97/163; input-handler
    135/268/294/322); the source lines + # shellcheck source= directives -> rank.sh
    (renderer 44-45; input-handler 60-61); the 2 comments (input-handler 125, 435) updated.
  - DO NOT: broaden the patterns (would mangle "filtered"/"filter" concept comments).
  - DO NOT: touch rank.sh, options/utils/state, or any test functionally.

Task 2: VERIFY the swap (before deleting filter.sh — so the byte-identity check can still
         source BOTH libs)
  - RUN Validation L1 (bash -n + shellcheck -x) and L2 (empty-filter byte-identity diff
    sourcing both filter.sh AND rank.sh). Both must pass BEFORE Task 3.
  - RUN: grep -rn 'lp_build_filtered\|filter\.sh' scripts/renderer.sh scripts/input-handler.sh
        -> must be EMPTY.

Task 3: DELETE scripts/filter.sh
  - RUN: rm scripts/filter.sh   (or: git rm scripts/filter.sh)
  - VERIFY: grep -rn 'source.*filter\.sh' scripts/ -> EMPTY (nothing sources the deleted file).
  - NOTE: rank.sh's historical comments ("Supersedes filter.sh::...") remain — they are
    architectural and still meaningful; do NOT edit rank.sh.

Task 4 (OPTIONAL, low priority): refresh the 2 stale TEST comments
  - tests/test_pollution.sh:108 "(filter.sh)" -> "(rank.sh)"
  - tests/test_responsiveness.sh:73 "lp_build_filtered: case-insensitive substring"
    -> "lp_rank: subsequence (a superset of substring)"
  - COMMENT-ONLY; does not affect the green suite. Skip if keeping changes minimal.

Task 5: VALIDATE — full suite + byte-identity (the definitive gates)
  - RUN Validation L3: bash tests/run.sh  -> expect "44 passed, 0 failed".
```

### Implementation Patterns & Key Details

**The entire mechanical change** (run from the repo root; verified on /tmp copies in
research §3 — produces zero remaining refs, correct source lines, all 6 sites swapped,
bash -n + shellcheck -x clean):

```bash
cd /home/dustin/.config/tmux/plugins/tmux-livepicker

# (precondition) S1 landed?
ls scripts/rank.sh && bash -c 'set -u; source scripts/rank.sh; declare -F lp_rank' || { echo "STOP: S1 not merged"; exit 1; }

# Task 1 — swap the 6 call sites + source/directive lines (verbatim):
sed -i 's/lp_build_filtered/lp_rank/g' scripts/renderer.sh scripts/input-handler.sh
sed -i 's|filter\.sh|rank.sh|g'    scripts/renderer.sh scripts/input-handler.sh

# Task 2 — verify no stragglers in the consumers:
grep -n 'lp_build_filtered\|filter\.sh' scripts/renderer.sh scripts/input-handler.sh   # -> nothing

# Task 3 — retire filter.sh:
rm scripts/filter.sh
grep -rn 'source.*filter\.sh' scripts/   # -> nothing
```

**Why sed, not the `edit` tool**: input-handler.sh lines 268/294/322 are byte-identical
(3-tab indent, same `mapfile -t filtered < <(lp_build_filtered "$cur_list" "$cur_filter")`).
The `edit` tool requires unique `oldText`; these three are not, so each would need a
verbose multi-line anchor reaching up to its `next-session)`/`prev-session)`/`confirm)`
case label. `sed -i` is surgical (the two patterns match ONLY the function name and the
literal filename respectively — verified they do not touch "filtered"/"filter" concept
comments) and handles all 6 sites + the 2 comments + the source/directive lines in one pass.

**The call convention is unchanged** at every site, so no surrounding logic moves. E.g.
renderer.sh plain path:
```bash
mapfile -t filtered < <(lp_rank "$LIST" "$FILTER")   # was: lp_build_filtered
FLEN="${#filtered[@]}"                                 # untouched
... "${filtered[0]}" ...                               # ranked[0] == highlight (untouched)
```

### Integration Points

```yaml
CODE:
  - file: scripts/renderer.sh
    change: "source rank.sh (44-45); lp_build_filtered -> lp_rank at 97, 163"
    invariant: "ws_filtered[0]/filtered[0] == the top-ranked match (lp_rank index 0)"
  - file: scripts/input-handler.sh
    change: "source rank.sh (60-61); lp_build_filtered -> lp_rank at 135, 268, 294, 322"
    invariant: "nav/confirm resolve the SAME ranked list the renderer highlights (no drift)"
  - file: scripts/filter.sh
    change: "DELETED (fully superseded; no divergent substring logic remains)"

SOURCE ORDER (codebase_patterns §P1 — load-bearing, PRESERVED by in-place sed rename):
  options.sh -> utils.sh -> state.sh -> rank.sh   (was -> filter.sh; same slot)

CONSUMERS (unchanged behavior on empty/common filters; subsequence superset on others):
  - renderer.sh §17 window-status path (ws_filtered) + plain path (filtered)
  - input-handler.sh _lp_sync_preview_to_top_match + next/prev-session + confirm
  - (later) session-mgmt.sh (P2) — not yet present; will source rank.sh when added

CONFIG / DATABASE / ROUTES: none — internal refactor; no option/state/key change.
```

## Validation Loop

### Level 1: Syntax & Style (Immediate Feedback)

```bash
cd /home/dustin/.config/tmux/plugins/tmux-livepicker
bash -n scripts/renderer.sh && echo "renderer.sh: syntax OK"
bash -n scripts/input-handler.sh && echo "input-handler.sh: syntax OK"
shellcheck -x scripts/*.sh          # expect 0 NEW findings (rank.sh sourced + exists)
# No stragglers in the consumers:
grep -rn 'lp_build_filtered\|filter\.sh' scripts/renderer.sh scripts/input-handler.sh && echo "FAIL: stragglers remain" || echo "OK: consumers fully swapped"
# rank.sh is sourced in the correct slot (after state.sh) in both:
grep -n 'source=rank.sh\|source.*rank\.sh' scripts/renderer.sh scripts/input-handler.sh
# filter.sh is gone + nothing sources it:
[ ! -e scripts/filter.sh ] && echo "OK: filter.sh deleted" || echo "FAIL: filter.sh still present"
grep -rn 'source.*filter\.sh' scripts/ && echo "FAIL: something still sources filter.sh" || echo "OK: no filter.sh sourcers"
```

### Level 2: Empty-filter byte-identity (pre-delete safety net)

Run this BEFORE deleting filter.sh (Task 2), while both libs still exist. Proves the
empty-filter path is byte-identical — the guarantee that keeps the 44-green suite green.

```bash
cd /home/dustin/.config/tmux/plugins/tmux-livepicker
bash -c 'set -u
  source scripts/filter.sh
  source scripts/rank.sh
  fail=0
  for LIST in "" "solo" $'"'"'a\nb\n'"'"'c $'"'"'alpha\nbeta\ndriver'"'"' \
               $'"'"'with-dash\nunder_score\ndot.name\nsl/ash'"'"' $'"'"'trailing\n'"'"' \
               "CAPS lower MiXeD" "$(printf '"'"'session-%s\n'"'"' $(seq 1 50))"; do
    [ "$(lp_build_filtered "$LIST" "")" = "$(lp_rank "$LIST" "")" ] || { echo "BYTE-DIFF for LIST=[$LIST]"; fail=1; }
  done
  [ "$fail" -eq 0 ] && echo "OK: empty-filter byte-identical" || echo "FAIL"'
# Expected: OK: empty-filter byte-identical. If FAIL, S1's lp_rank empty-filter path is
# wrong — that is an S1 bug, not S2; flag it (do not paper over it in the consumers).
```

### Level 3: Full suite — the definitive gate (run AFTER Task 3, filter.sh deleted)

```bash
cd /home/dustin/.config/tmux/plugins/tmux-livepicker
bash tests/run.sh
# Expected: "44 passed, 0 failed" (exit 0). The empty-filter cancel/restore lifecycle +
# the default no-query state all route through lp_rank now; byte-identity (L2) guarantees
# they are unchanged. If a test fails, READ its assert message — most likely cause is an
# S1 lp_rank ordering bug on a NON-empty query (subsequence), which is S1's to fix, not
# something to "revert" the swap over.
```

### Level 4: Subsequence superset proof (the intended new behavior)

Confirms the swap actually routes through lp_rank (not a no-op) and that the
subsequence superset works as intended (PRD §3.36). Throwaway — delete after.

```bash
cd /home/dustin/.config/tmux/plugins/tmux-livepicker
bash -c 'set -u
  source scripts/rank.sh
  LIST=$'"'"'apple\nblog\nzebra'"'"'
  # empty filter: all 3, original order (byte-identical to the old substring filter)
  [ "$(lp_rank "$LIST" "")" = "$(printf '"'"'apple\nblog\nzebra'"'"')" ] && echo "OK: empty == full list, original order"
  # subsequence superset: "lg" matches "blog" (l..g in order) — the OLD substring filter did NOT
  [ "$(lp_rank "$LIST" "lg")" = "blog" ] && echo "OK: lg -> blog (subsequence superset)" || echo "FAIL: lg did not match blog"
  # "bl" matches "blog"; non-matches hidden
  [ "$(lp_rank "$LIST" "bl")" = "blog" ] && echo "OK: bl -> blog"
  [ -z "$(lp_rank "$LIST" "zzz")" ] && echo "OK: no-match hidden"'
# Expected: all four OK lines. This proves lp_rank is live and the superset behavior works.
```

## Final Validation Checklist

### Technical Validation
- [ ] L1: `bash -n` clean on renderer.sh + input-handler.sh; `shellcheck -x scripts/*.sh` clean.
- [ ] L1: `grep lp_build_filtered|filter.sh` in the two consumers → nothing; `filter.sh` deleted.
- [ ] L2: empty-filter byte-identity (lp_rank == lp_build_filtered) across all list shapes.
- [ ] L3: `bash tests/run.sh` → **44 passed, 0 failed**.
- [ ] L4: subsequence superset works (`lg`→`blog`); empty filter == full list original order.

### Feature Validation
- [ ] All 6 call sites call `lp_rank` (renderer ws_filtered@97, filtered@163; input-handler
      _sync_filtered@135, filtered@268/294/322).
- [ ] Both consumers source `rank.sh` in the options→utils→state→rank slot (order preserved).
- [ ] `filter.sh` removed; no script sources it.
- [ ] No behavior change on empty/common filters; subsequence superset on others (intended).

### Code Quality Validation
- [ ] Pure refactor: no new option/state/key; no doc/API change.
- [ ] rank.sh untouched (S1's scope); no test functionally changed.
- [ ] sed patterns surgical (do not touch "filtered"/"filter" concept comments).
- [ ] Source order preserved (in-place rename, not a move).

### Documentation & Deployment
- [ ] No README/CHANGELOG change (internal refactor; Mode A). Doc sync is P4.T1.
- [ ] (Optional) 2 stale TEST comments refreshed — comment-only, not required for green.

---

## Anti-Patterns to Avoid

- ❌ Don't swap callers BEFORE confirming S1 landed. Verify `rank.sh` exists + `lp_rank`
  is defined first; otherwise the consumers source a missing file and everything breaks.
- ❌ Don't use the `edit` tool for the 3 nav/confirm lines (268/294/322) — they are
  byte-identical, so `oldText` is non-unique. Use `sed -i` (verified).
- ❌ Don't broaden the sed patterns to `filter` or `lp_build` — they would mangle dozens
  of unrelated "filtered[index]"/"shared filter"/"top filtered match" comments. Match the
  FULL tokens `lp_build_filtered` and `filter\.sh` only.
- ❌ Don't reorder the source line. The sed renames `filter.sh`→`rank.sh` IN PLACE
  (same line/position), preserving the load-bearing options→utils→state→rank order.
- ❌ Don't touch `rank.sh` — it is S1's exclusive scope (including its historical
  "filter.sh" header comments, which remain meaningful after deletion).
- ❌ Don't leave `filter.sh` in place "just in case" — a second, divergent ranker is the
  exact drift risk this subtask eliminates. Delete it once the swap + byte-identity pass.
- ❌ Don't "revert" the swap if a non-empty-query test fails — that is an S1 lp_rank
  ordering bug (subsequence/scoring), not a problem with the swap. Flag it to S1.
- ❌ Don't tighten callers back to substring behavior. `lg`→`blog` is intended (PRD §3.36).
- ❌ Don't add a committed `tests/test_ranking.sh` here — that's P1.M4.T2.S1 (sibling).

---

## Confidence Score

**10 / 10** for one-pass success. Rationale:
1. The change is a verified 1:1 textual substitution — two `sed -i` commands, run on
   /tmp copies, produced exactly the intended result (zero stragglers, correct source
   lines, all 6 sites swapped, both comments updated, `bash -n` + `shellcheck -x` clean).
2. The 3 identical-line trap (input-handler 268/294/322) is sidestepped by sed (the edit
   tool would reject it).
3. The load-bearing empty-filter byte-identity (lp_rank == lp_build_filtered) is verified
   across 8 list shapes incl. a 50-session list — the 44-green suite stays green by
   construction.
4. `rank.sh` already exists (S1 in flight), the consumers' call convention is identical,
   and `filter.sh` is a leaf lib with exactly 2 sourcers (both swapped) — deletion is safe.
5. The only behavior change (subsequence superset) is intended, only ADDS matches, and no
   test asserts otherwise (verified). Zero blast radius beyond the 2 files + 1 deletion.
