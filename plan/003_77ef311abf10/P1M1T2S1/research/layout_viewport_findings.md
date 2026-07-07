# layout.sh width measurement + viewport math — empirical grounding (tmux 3.6b / bash 5.3)

> Verified LIVE on 2026-07-07. The width-measurement mechanism and the viewport
> slice/scroll-into-view math are the load-bearing core of PRD §19. This file
> proves them and records the TWO traps that would break a naive implementation.

## Environment

| Tool | Version |
|---|---|
| bash | **5.3.15(1)-release** |
| tmux | **3.6b** (renderer runs as its `#()` child; inherits the server's locale) |
| locale | `LANG=en_US.UTF-8` (the nerd-font use case implies a UTF-8 locale) |

## rank.sh status: LANDED (the input format layout.sh consumes)

`scripts/rank.sh` is present (P1.M1.T1.S1). `lp_rank LIST FILTER` prints ranked
names, best-first, newline-separated (empty FILTER → all names, original order).
layout.sh consumes this newline-separated list — it is AGNOSTIC to the source
(filter.sh today, rank.sh after T1.S2 retires filter.sh). No coupling.

---

## FINDING 1 — ⚠️ `wc -m` is LOCALE-DEPENDENT (the contract's suggestion is a trap)

The contract says "use a byte/column counter — wc -m after stripping". **`wc -m` is
locale-dependent** and gives the WRONG answer under a C locale:

| locale | `wc -m` on nerd-font icon U+F002 (3 bytes / 1 codepoint) |
|---|---|
| `en_US.UTF-8` | **1** (codepoints — correct) |
| `C` (`LC_ALL=C`) | **3** (bytes — WRONG: inflates the icon's width 3×) |

The livepicker renderer runs as a `#()` command launched by the tmux SERVER, which
inherits the user's locale. A user with nerd fonts (the whole point of
`@livepicker-search-icon`) necessarily has a UTF-8 locale, so `wc -m` gives codepoints
in practice. BUT relying on that is fragile, AND `wc -m` spawns a subshell per call
(violates the §18 renderer budget when called per-tab).

**THE FIX: use bash's `${#var}`** (a builtin, no subshell) on the STRIPPED string.
Under a UTF-8 locale `${#var}` counts codepoints (verified: icon→1, "main"→4,
"icon main"→6). It is ALSO locale-dependent (bytes under C), but:
- it's a builtin (no per-tab process spawn → fits the §18 budget), and
- the nerd-font use case guarantees UTF-8 (a C-locale user would see raw icon bytes
  as garbage regardless, so a width miscalc is moot).

Document the UTF-8-locale assumption prominently. Do NOT use `wc -m`. (Forcing
`LC_ALL=C.UTF-8` inside the function is rejected — locale names vary across
systems and it's fragile.)

---

## FINDING 2 — ⚠️ The naive bash `#[…]` glob strip is BROKEN (the second trap)

The contract says "regex strip of `#\[[^]]*\]`". That is a REGEX, but bash
parameter expansion `${var//PAT/}` uses GLOB patterns, where `*` is a standalone
wildcard, NOT a quantifier on the preceding bracket. Verified BROKEN:

```
S="#[fg=red,bold]hello#[default] #[fg=blue]world#[default]"
${S//\#\[[^]]*\]/}   ->  ""   (EMPTY — ate EVERYTHING from first #[ to last ])
perl 's/#\[[^]]*\]//g'  ->  "hello world"   (correct — regex)
```

The glob `#[[^]]*\]` matches `#[` + one non-`]` char + `*`(any string) + `]` →
greedily consumes the whole span including visible text.

**THE FIX (two working pure-bash options, both verified):**

**(a) Manual loop** (RECOMMENDED — no shell-option changes, fully self-contained):
```bash
_lp_strip_styles() {
	local in="$1" out=""
	while :; do
		case "$in" in
			*"#["*) out="$out${in%%\#[*}"; in="${in#*]}" ;;  # text-before-#[ , then drop through to next ]
			*) out="$out$in"; break ;;
		esac
	done
	printf '%s' "$out"
}
```
Verified on `#[a]x#[b]y#[c]z` → `xyz`; `#[fg=red,bold]hello#[default] #[fg=blue]world#[default]` → `hello world`;
tubular-style `#[default]#[fg=...] __lp_tab__ #[...]` → ` __lp_tab__ `.

**(b) extglob one-liner** `${S//\#[+([^]])\]/}` (needs `shopt -s extglob`). Verified
→ `hello world`. REJECTED as primary: enabling extglob is a global shell-option change
that must be saved/restored to avoid surprising other code in the sourcing shell; the
manual loop has no global state and is equally fast.

**Perf (the §18 renderer budget):** manual loop over 200 realistic tabs = **21 ms**
(verified). Well under the <50ms renderer budget. sed would spawn 200 processes —
never use it on the render path.

Edge case verified: a literal `#` NOT followed by `[` survives the strip
(`${lit//\#\[[^]]*\]/}` on `a#b##c` → `a#b##c`, unchanged). (Query `#`-doubling is the
renderer's concern, not layout.sh's.)

---

## FINDING 3 — Realistic-tab widths (the icon counts as 1)

`lp_disp_width` = strip styles, then `${#}` (codepoints). Verified:

| raw tab | stripped | width |
|---|---|---|
| `#[fg=#7aa89f]<icon> main#[default]` | `<icon> main` | **6** (icon=1 + space + main=4) |
| `#[fg=red,bold]alpha#[default]` | `alpha` | **5** |
| `#[default]#[fg=...] __lp_tab__ #[...]` | ` __lp_tab__ ` | **12** |

The nerd-font icon U+F002 is 1 codepoint → width 1 (matches the contract's "single
narrow codepoint = width 1"). ASCII = 1/codepoint. **Assumption:** every codepoint in
play is narrow (true for session names + nerd-font PUA icons). Wide CJK/emoji glyphs
(width 2) would be undercounted — a documented limitation (not in scope for §19;
session names are typically ASCII). Do NOT add a wide-glyph check (YAGNI; PRD §16
doesn't require it).

---

## FINDING 4 — `lp_viewport` scroll-into-view + slice math (all 7 cases verified)

Algorithm (pure bash, O(n) per call via incremental cumwidth):
1. Measure each tab width via `lp_disp_width`; total = sum(w) + (n-1)*sep.
2. If total ≤ T → clamp scroll=0, slice=[0,n-1], no hidden. (PRD §3.32 "clamp scroll=0 when the list fits".)
3. Else (overflow): sanitize scroll/highlight to [0,n-1].
4. Scroll-into-view (PRD §3.32): if highlight < scroll → scroll=highlight. Then while
   cumwidth(scroll,highlight) > T and scroll<highlight: advance scroll (incrementally:
   cw -= w[scroll] + sep; scroll++). Ensures the highlight tab is always visible.
5. Find end = largest index ≥ scroll with cumwidth(scroll,end) ≤ T (forward scan).
6. hidden_left = scroll; hidden_right = n-1-end. (Their sum is the `+N>` %d — PRD §3.33.)

Verified cases (sep=1 unless noted):
- (1) fits-in-T → scroll=0, all visible, hidden=0. ✓
- (2) overflow, scroll=0, hl=0, 5 tabs width-3, T=10 → slice [0,1] (aaa bbb = 7≤10; +ccc=11>10), hidden_R=3. ✓
- (3) hl=3 (ddd), T=10 → scroll advances 0→2 (cumwidth(0,3)=15>10; (1,3)=12>10; (2,3)=7≤10); slice [2,3] (ccc ddd), hidden_L=2, hidden_R=1. ✓ highlight visible.
- (4) scroll=3, hl=1 → hl<scroll so scroll=1; slice [1,2], hidden_L=1, hidden_R=2. ✓
- (5) 7 tabs, T=10, scroll=2, hl=5 → scroll advances to 4; slice [4,5], hidden_L=4, hidden_R=1, total hidden=5. ✓
- (6) single tab wider than T (w=12, T=3) → scroll=0, end=0 (the tab itself, partially clipped), hidden=0. ✓ (degenerate; shows as much as possible)
- (7) styled tabs + nerd-font icon (widths 6,5,4; T=12, hl=1) → total 17>12; cumwidth(0,1)=12≤12 so no advance; slice [0,1] (tab0+tab1=12 fits exactly), hidden_R=1. ✓

**Separator accounting:** the inter-tab gap is 1 col (plain mode space) or
len(window-status-separator) (ws mode). `lp_viewport` takes SEP_WIDTH as an optional
5th arg (default 1); cumwidth includes (count)*sep between the counted tabs. This
keeps the math correct for BOTH tab styles (PRD §3.31).

---

## FINDING 5 — The "active indicators width" is the CALLER's concern, not layout.sh's

PRD §19 says `T = client_width − query_block − active_indicators`. The indicator
presence depends on hidden-counts (circular with the viewport). **Resolution: layout.sh
takes T as a GIVEN input** (already net of query block + whatever indicator budget the
caller reserves). lp_viewport returns the hidden counts; the RENDERER (M2) decides
indicator presence and reserves their width when computing T (two-pass or pessimistic
reserve — the renderer's concern). This keeps layout.sh PURE MATH with no circular
dependency, and testable in isolation (pass T, get a slice).

---

## API (final, verified)

```bash
# scripts/layout.sh — sourced lib, NO source-time side effects (matches rank.sh/filter.sh).

_lp_strip_styles STRING            # internal: strip #[...] runs, print visible text
lp_disp_width STRING               # print integer display columns (strip + ${#} codepoints)
# lp_viewport RANKED_LIST T SCROLL HIGHLIGHT [SEP_WIDTH=1]
#   sets globals: LPV_SCROLL LPV_START LPV_END LPV_HIDDEN_LEFT LPV_HIDDEN_RIGHT
lp_viewport "$list" "$T" "$scroll" "$hl" "${sep:-1}"
```

- RANKED_LIST: newline-separated (the `lp_rank` / `lp_build_filtered` output convention).
- LPV_END = -1 when the slice is empty (n=0 or T≤0); callers loop `for ((i=LPV_START; i<=LPV_END; i++))`.
- Pure bash, no tmux, no subshells on the measurement path (§18 budget). `set -u`; `local` everywhere; tabs.
