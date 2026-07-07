# Research: P1.M1.T1.S2 — switch 6 filter.sh call sites to rank.sh; retire filter.sh

> Empirical verification run on /tmp COPIES of the repo scripts (the real source was
> NOT modified — research agent). tmux 3.6b, bash 5.3.15. This file records the
> ground-truth the PRP's swap commands + validation rely on.

## 0. S1 is already in flight — rank.sh EXISTS

At research time `scripts/rank.sh` already exists (S1 P1.M1.T1.S1 created it in
parallel). It is a LEAF sourced library (sources nothing itself; defines `lp_rank` +
`LP_*` constants only; no driver). So the swap is a clean 1:1 textual replacement of
`filter.sh`→`rank.sh` / `lp_build_filtered`→`lp_rank` in the two consumers; no
transitive dependency changes, no source-order change (codebase_patterns §P1:
options→utils→state→(filter|rank).sh — sed renames in place, preserving order).

NOTE: rank.sh's OWN header comments reference "filter.sh" historically
("Supersedes filter.sh::lp_build_filtered"; "Mirrors filter.sh so the ..."). Those
are S1's documentation and are HISTORICAL/architectural (still meaningful after
filter.sh is deleted). S2 does NOT touch rank.sh (S1's exclusive scope).

## 1. The complete reference map (grep -n 'lp_build_filtered\|filter\.sh' scripts/)

### renderer.sh (2 call sites + source + directive)
| line | content | S2 change |
|------|---------|-----------|
| 44 | `# shellcheck source=filter.sh` | → `source=rank.sh` |
| 45 | `source "$CURRENT_DIR/filter.sh"` | → `rank.sh` |
| 97 | `mapfile -t ws_filtered < <(lp_build_filtered "$ws_list" "$ws_filter")` | → `lp_rank` (§17 window-status path) |
| 163 | `mapfile -t filtered < <(lp_build_filtered "$LIST" "$FILTER")` | → `lp_rank` (plain path) |

### input-handler.sh (4 call sites + source + directive + 2 comments)
| line | content | S2 change |
|------|---------|-----------|
| 60 | `# shellcheck source=filter.sh` | → `source=rank.sh` |
| 61 | `source "$CURRENT_DIR/filter.sh"` | → `rank.sh` |
| 125 | comment: "same lp_build_filtered the renderer uses ..." | → `lp_rank` (auto via sed) |
| 135 | `mapfile -t _sync_filtered < <(lp_build_filtered "$_list" "$_filt")` | → `lp_rank` (_lp_sync_preview_to_top_match) |
| 268 | `mapfile -t filtered < <(lp_build_filtered "$cur_list" "$cur_filter")` | → `lp_rank` (next-session) |
| 294 | IDENTICAL to 268 (3-tab indent) | → `lp_rank` (prev-session) |
| 322 | IDENTICAL to 268 (3-tab indent) | → `lp_rank` (confirm) |
| 435 | comment: "... renderer FINDING 4 / filter.sh)." | → `rank.sh` (auto via sed) |

### filter.sh itself
| line | content | S2 change |
|------|---------|-----------|
| whole file | `lp_build_filtered` (case-insensitive substring) | **DELETE the file** |

**Total: 6 call sites** (renderer 2 + input-handler 4) + 2 source lines + 2 shellcheck
directives + 2 comments + 1 file deletion.

## 2. The 3 identical lines make `sed` the right tool (not the `edit` tool)

Lines 268 / 294 / 322 are BYTE-IDENTICAL (verified with `cat -A`):
```
^I^I^Imapfile -t filtered < <(lp_build_filtered "$cur_list" "$cur_filter")$
```
(3 tabs of indent, inside the next-session / prev-session / confirm case branches.)
The `edit` tool requires each `oldText` to be UNIQUE in the file — these 3 are not, so
disambiguating them needs verbose multi-line anchors per site. A global `sed -i` swap
is simpler, surgical, and verified-correct. Use sed.

## 3. The verified swap commands (run on /tmp copies; repo untouched)

```bash
sed -i 's/lp_build_filtered/lp_rank/g' scripts/renderer.sh scripts/input-handler.sh
sed -i 's|filter\.sh|rank.sh|g'    scripts/renderer.sh scripts/input-handler.sh
rm scripts/filter.sh     # (or: git rm scripts/filter.sh)
```

### Result (verified):
- `grep -n 'lp_build_filtered\|filter\.sh' renderer.sh input-handler.sh` → **nothing** (0 refs).
- `rank.sh` sourced at renderer.sh:44-45 and input-handler.sh:60-61 (correct source-order slot).
- `lp_rank` call sites: 2 in renderer.sh, 5 in input-handler.sh (4 calls + 1 comment).
- The line-435 comment auto-updated: "renderer FINDING 4 / rank.sh)." (still reads sensibly).
- `bash -n` clean on both; `shellcheck -x scripts/*.sh` clean.

Both seds are SURGICAL:
- `s/lp_build_filtered/lp_rank/g` matches ONLY the function name (never "filtered"/"filter").
- `s|filter\.sh|rank.sh|g` matches ONLY the literal filename `filter.sh` (the `\.` anchors
  the dot; never "filtered list"/"shared filter"/"top filtered match" concept comments).

## 4. Byte-identity on empty filter (the load-bearing S1 contract) — VERIFIED

Sourced BOTH filter.sh and rank.sh; diffed empty-filter output across many list shapes:

```
LIST ∈ { "", "solo", "a\nb\nc", "alpha\nbeta\ndriver",
          "with-dash\nunder_score\ndot.name\nsl/ash", "trailing\n",
          "CAPS lower MiXeD", <50-session list> }
→ lp_build_filtered "$LIST" ""  ==  lp_rank "$LIST" ""   for EVERY shape.  OK.
```

This is why the 44-green suite stays green: every empty-filter path (the whole
cancel/restore lifecycle + the default no-query state) produces identical output
through lp_rank. The PRE-DELETE check (source both, diff on empty filter) is the
safety net; the POST-DELETE `bash tests/run.sh` is the definitive gate.

## 5. The only observable behavior change is the intended subsequence superset

For NON-empty filters, `lp_rank` matches by SUBSEQUENCE (every query char in order,
case-insensitive), which is a SUPERSET of the old substring match. Verified live on a
/tmp renderer copy: filter `"bl"` now matches `"blog"` (b..l in order) where the old
substring filter did not. This is INTENDED (PRD §3.36; S1 PRP "do not tighten back").

No test asserts a name does NOT match under a non-empty query in a way subsequence
would expand (the only negative assertions — test_typing_filters excludes alpha/driver
for query "log", and neither is a subsequence match). So no negative assertion breaks
and no positive assertion breaks (subsequence only ADDS matches). **Suite stays green.**

## 6. Deleting filter.sh is safe

`grep -rn 'filter\.sh' scripts/` shows it is sourced ONLY by renderer.sh:45 and
input-handler.sh:61 (both swapped to rank.sh). No other script sources it; livepicker/
preview/restore/state/utils/options never referenced it. Tests reference it in COMMENTS
only (test_pollution.sh:108, test_responsiveness.sh:73 — see §7).

## 7. Stale TEST comments (optional, non-functional)

Two test files mention the old name in comments only (not functional code):
- `tests/test_pollution.sh:108` — "(filter.sh)" in a comment about the empty-filter
  full-list invariant.
- `tests/test_responsiveness.sh:73` — "Mirrors lp_build_filtered: case-insensitive
  substring" (now lp_rank / subsequence).

These are OUT of the stated S2 scope (renderer + input-handler + delete filter.sh) and
are comment-only (the suite is unaffected). Listed for awareness; updating them is
optional polish. If updated: test_pollution `filter.sh`→`rank.sh`; test_responsiveness
`lp_build_filtered: case-insensitive substring`→`lp_rank: subsequence (a superset of
substring)`. NOT required for the green suite.

## 8. Test count = 44

`grep -rhoP '^\s*test_[a-z0-9_]+\s*\(\)' tests/test_*.sh | wc -l` → **44**. Matches the
"44-green suite" reference. `bash tests/run.sh` is the gate (exits 0 iff all pass).
