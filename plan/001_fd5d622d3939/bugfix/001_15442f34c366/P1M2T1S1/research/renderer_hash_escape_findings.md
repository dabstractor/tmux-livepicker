# Research — Bugfix P1.M2.T1.S1: escape `#`→`##` in renderer.sh format strings (Issue 3)

> All facts below were verified **LIVE on 2026-07-05** on an isolated tmux socket
> (`tmux 3.6b`, `bash 5.3.15(1)-release`, `shellcheck 0.11.0`) OR are quoted from
> the already-live-verified `bugfix_findings.md` (Issue 3 + External tmux research).
> These are the ground-truth behaviors the fix + its regression test must encode.

## Environment

| Tool | Version |
|---|---|
| tmux | **3.6b** (`tmux -V`) |
| bash | **5.3.15(1)-release** |
| shellcheck | **0.11.0** |

---

## FINDING 1 — session/window names CAN contain `#` (LIVE-PROVEN)

On an isolated socket: `tmux new-session -d -s "#dev"` **succeeds**, and
`tmux has-session -t "=#dev"` **succeeds**. tmux only sanitizes `:`→`_` and a
leading `.`→`_` in session names; `#` is legal and stored **literally**. So the
`@livepicker-list` (built from `list-sessions -F '#{session_name}'`) CAN contain
names with `#`, and the renderer WILL receive them.

**Implication**: the bug is reachable in real use. A user with a session named
`#dev`, `csharp#`, or `C#-proj` would see a mis-rendered picker today.

---

## FINDING 2 — `##` is the ONLY escape for a literal `#` in a tmux format string (LIVE-PROVEN)

Test: isolated socket + real pty client, `status-format[0]` set to a string with
`##dev` inside a styled `#[...]` segment:

```
status-format[0] = "#[fg=red,bg=yellow]##dev#[default] ok"
```

Capture of the rendered status line (decode of the SGR escapes tmux emitted):

```
\033[31m \033[43m  #dev  \033[38;2;120;120;120m\033[48;2;24;24;34m   ok
   ^^red  ^^yellow    ^^default reset (both axes)                        ok
```

So `##dev` rendered as the **literal text `#dev`**, in red-on-yellow (the
`#[fg=red,bg=yellow]` applied), and `#[default]` reset both fg+bg before ` ok`.

**Conclusions:**
- `##` collapses to a single literal `#`, **even inside a `#[...]` styled
  segment**, and does NOT disturb the surrounding styling. ✓ (The escape is
  format-level, applied before/independent of style parsing.)
- This is the **only** mechanism for a literal `#`. No backslash, no other
  character needs escaping for literal output (`{`, `[`, `(` are literal unless
  preceded by `#`). (bugfix_findings §External research point 1.)
- A **raw, unescaped** `#` in a user string is the injection vector: `#[fg=red]`
  in a name would inject red styling; any `#<letter>` or `#{...}` / `#(...)` /
  `##` sequence in a name is interpreted by the format engine. (bugfix_findings
  Issue 3: "`#dev` → `<day>ev`; `#[fg=red]x` would inject styling".)

**Implication**: the renderer MUST double every `#` in user-derived strings at
emission. The code's OWN `#[fg=...]`, `#[default]`, color values, and `$((...))`
arithmetic must NOT be escaped (they are authored literals).

---

## FINDING 3 — bash parameter expansion `${var//\#/##}` is the correct escape (LIVE-VERIFIED)

Bash 4.0+ (target is 5.3.15) global-substring-replace via `${var//OLD/NEW}`:

| `$name` (raw) | `${name//\#/##}` (escaped) |
|---|---|
| `#dev` | `##dev` |
| `csharp#` | `csharp##` |
| `C#-proj` | `C##-proj` |
| `a##b` | `a####b` |
| `plain` | `plain` (no `#` → unchanged) |
| `##` | `####` |
| `#a#b#` | `##a##b##` |
| `` (empty) | `` (unchanged) |

**Conclusions:**
- `${name//\#/##}` replaces EVERY `#` with `##`, exactly the tmux literal-`#`
  escape. Handles leading, trailing, multiple, and adjacent-`#` names correctly.
- Empty string is a no-op (no `#` → no change) → safe for empty `$FILTER`.
- The pattern `\#` is an escaped `#` (avoids any glob interpretation of `#`;
  `#` is not a glob special but the backslash is harmless and makes intent
  explicit). The replacement `##` is literal.

**Implication**: the fix is TWO one-line bash parameter expansions per user-
derived variable:
- `local esc_name="${filtered[$i]//\#/##}"` (use in the item segment, both the
  highlighted [line 94] and normal [line 96] branches).
- `local esc_filter="${FILTER//\#/##}"` (use in the query/count display at lines
  78, 80, 107).

---

## FINDING 4 — the EXACT 5 emission sites in the current renderer.sh (verified against the working tree)

The shipped `scripts/renderer.sh` emits user-derived strings (`$FILTER` and
`${filtered[$i]}`) raw into `#[...]` format strings at exactly these sites
(verified by reading the current file):

| # | Current line | Code | User string |
|---|---|---|---|
| 1 | 78 | `out="#[fg=$FG,bg=$BG]query> $FILTER (no match) 0/$TOTAL#[default]"` | `$FILTER` |
| 2 | 80 | `out="#[fg=$FG,bg=$BG]query> $FILTER (no match)#[default]"` | `$FILTER` |
| 3 | 94 | `seg="#[fg=$HFG,bg=$HBG]${filtered[$i]}#[default]"` | candidate name |
| 4 | 96 | `seg="#[fg=$FG,bg=$BG]${filtered[$i]}#[default]"` | candidate name |
| 5 | 107 | `out="$out #[fg=$FG,bg=$BG]query> $FILTER [$((cidx + 1))/$FLEN]#[default]"` | `$FILTER` |

**Do NOT escape** (these are code-authored literals, not user data):
- The `#[fg=$FG,bg=$BG]`, `#[fg=$HFG,bg=$HBG]`, `#[default]` style tokens.
- `$FG`, `$BG`, `$HFG`, `$HBG` color values (from `opt_*` — PRD §11 config; could
  contain `#ffffff` hex, but that is code-supplied config, NOT user session-name
  data, and it is placed inside `#[fg=...]` as a color spec which tmux parses
  correctly — a hex `#ffffff` there is fine because it is in the attribute list,
  not the free-text segment. Leave as-is.)
- `$TOTAL`, `$FLEN`, the `$((cidx + 1))` arithmetic (numeric; no `#`).

**GOTCHA on color values**: `$FG`/`$BG`/`$HFG`/`$HBG` may be `#ffffff` (hex). Do
NOT escape them — they sit inside the `#[fg=...,bg=...]` attribute list where tmux
expects a color spec; a hex value is correct there. Escaping `#ffffff`→`##ffffff`
would BREAK the color (tmux would treat `##ffffff` as `#ffffff` literal text in
the attribute, not a color). The fix escapes ONLY the two USER-DERIVED variables
(`$FILTER`, `${filtered[$i]}`), never the config color variables.

---

## FINDING 5 — do NOT change filter.sh (CONTRACT; confirmed by reading it)

`scripts/filter.sh::lp_build_filtered LIST FILTER` preserves original bytes:
it lowercases BOTH sides for matching (`${name,,}` / `${FILTER,,}`) but
**prints the original `$name` unchanged** (`printf '%s\n' "$name"`). This is
correct and MUST stay: the filtered list is ALSO consumed by `input-handler.sh`
nav resolution and `confirm` target resolution (`filtered[$idx]` → the session to
switch to). If we escaped `#`→`##` in the stored `@livepicker-list` or in
`lp_build_filtered`'s output, confirm would try to switch to a session literally
named `##dev` (which does not exist) — breaking navigation/confirm.

**Implication**: escaping happens ONLY at the renderer's emission point, on a
LOCAL copy of the string. The stored state (`@livepicker-list`, `@livepicker-filter`,
`@livepicker-index`) and `lp_build_filtered`'s output are NEVER modified. The
renderer reads the raw name, makes a local `esc_name`, and emits only `esc_name`
into the format string.

---

## FINDING 6 — the regression-test assertion: POSITIVE `##dev`, NOT negative `#dev` (CRITICAL — verified)

The contract says: "assert the output contains `##dev` (the escaped form) and
does NOT contain `#dev` as a bare unescaped sequence." The SECOND clause is
**misleading as a literal substring check** — verified:

| Output | Contains substring `##dev`? | Contains substring `#dev`? |
|---|---|---|
| BEFORE fix: `...yellow]#dev#[default] query> ...` | **NO** ✅ (test FAILS — correct) | **YES** |
| AFTER fix: `...yellow]##dev#[default] query> ...` | **YES** ✅ (test PASSES — correct) | **YES** |

The escaped form `##dev` CONTAINS the substring `#dev` (the 2nd `#` + `dev`).
So `! assert_contains "$out" "#dev"` would **FALSE-FAIL after the fix**.

**Decision — assert the POSITIVE escaped form, which cleanly discriminates:**
- **Name escaping (lines 94/96):** `assert_contains "$out" "##dev"`.
  Discriminates perfectly: absent before fix, present after. (The `##dev` token
  cannot appear before the fix because the name has only one `#`.)
- **Filter escaping, match branch (line 107):** `assert_contains "$out" "query> ##dev"`
  (filter = `#dev`, list = `#dev`). Discriminates: `query> #dev` (before) vs
  `query> ##dev` (after).
- **Filter escaping, no-match branch (lines 78/80):** `assert_contains "$out"
  "query> ##zz"` (filter = `#zz`, list = `#dev` — no match). Discriminates:
  `query> #zz` (before) vs `query> ##zz` (after).

**Why `##dev` (not the full styled segment)?** The color values
(`$FG`/`$BG`/`$HFG`/`$HBG`) come from PRD §11 config and the live env has
`@livepicker-fg="#ffffff"` pre-declared, so `#[fg=#ffffff,bg=default]` is the real
prefix — asserting the full `#[fg=black,bg=yellow]##dev` segment would be fragile
to config. Asserting `##dev` (just the escaped name) is config-independent and
unambiguous (the ONLY place `dev` appears is the name). ✓

---

## FINDING 7 — the test needs NO attached client (renderer is client-independent; CONTRACT §5)

Unlike most `test_functional.sh` tests (which call `attach_test_client` before
`livepicker.sh` because activate uses `display-message -p` / `switch-client`),
the renderer is a pure option-reader. The contract MOCKING note (§5) is explicit:
"renderer.sh reads @livepicker-* options directly (it is client-independent — no
attach_test_client needed)." Verified: `scripts/renderer.sh` sources
options+utils+state+filter and calls only `tmux show-option -gqv` (via
`get_state`/`opt_*`) + `lp_build_filtered` — no client-scoped commands.

**Implication**: the regression test skips `attach_test_client` entirely:
1. `setup_test "lp-bug3"` (brings up the isolated socket + PATH shim + baseline
   fixtures driver/alpha/beta).
2. (Optional but faithful) `tmux new-session -d -s "#dev"` — proves a `#`-name
   is a real, listable session (mirrors how `@livepicker-list` gets populated by
   activate's `list-sessions`).
3. Seed the minimal state the renderer reads DIRECTLY (mirror the contract's
   `lp_preview_seed_state` shape but inline):
   `tmux set-option -g @livepicker-list "#dev"`,
   `tmux set-option -g @livepicker-filter ""`,
   `tmux set-option -g @livepicker-index 0`.
4. `out="$("$LIVEPICKER_SCRIPTS/renderer.sh")"`.
5. `assert_contains "$out" "##dev"`.
6. (teardown happens via run.sh's per-test teardown_test.)

This is ~6 lines and fully hermetic. The renderer runs standalone on the
isolated socket.

---

## FINDING 8 — renderer.sh's sourcing + strictness (no change needed; confirmed by reading)

`scripts/renderer.sh` already:
- `set -u` (inherited from the sourced libs; NO `set -e`).
- Sources `options.sh → utils.sh → state.sh → filter.sh` (filter.sh added since
  the original PRP — provides `lp_build_filtered`).
- Has a `render()` body wrapped in `render || fallback-red-echo; exit 0`.

The fix adds two `local` variables (`esc_name`, `esc_filter`) inside `render()`
and substitutes them at the 5 sites. NO new sourcing, NO strictness change, NO
new function, NO driver change. The `set -u` safety holds because both new locals
are assigned before use (`esc_name=...; esc_filter=...`).

---

## FINDING 9 — placement of the new test (test_functional.sh, auto-discovered; CONTRACT §3)

`tests/run.sh` auto-discovers every `test_*` function via
`compgen -A function | grep '^test_'` and runs each on a FRESH isolated socket
(per-test `setup_test "lp-$$-<name>"` → run → `teardown_test`). So adding a
`test_*` function to ANY `tests/test_*.sh` is sufficient — no registration.

**Decision**: add to `tests/test_functional.sh` (the renderer already has
`test_typing_filters` there which captures renderer output via
`out="$("$LIVEPICKER_SCRIPTS/renderer.sh")"` — the EXACT pattern to mirror). Keeps
renderer assertions in the functional cluster. The contract also permits a new
`tests/test_renderer.sh`; test_functional.sh is preferred for cohesion and to
avoid a new file for two small tests.

**Naming** (contract-specified + companion):
- `test_renderer_escapes_hash_in_names` — the contract test (name escaping,
  lines 94/96).
- `test_renderer_escapes_hash_in_filter` — companion (filter escaping, lines
  78/80/107: match branch + no-match branch).

Both follow the file's conventions: `local` for all vars; signal failure ONLY via
`fail()`/`assert_*` (never `exit` — run.sh reads `TEST_STATUS` in the current
shell); TABS for indent.

---

## FINDING 10 — no conflict with the parallel task P1.M1.T2.S1 (input-handler.sh only)

The parallel task (preview-sync helper) modifies `scripts/input-handler.sh`
(adds `_lp_sync_preview_to_top_match` + 3 call sites) and `tests/test_functional.sh`
(appends `test_preview_follows_type_filter` + `test_preview_follows_backspace`).

This task (P1.M2.T1.S1) modifies `scripts/renderer.sh` and appends
`test_renderer_escapes_hash_*` to `tests/test_functional.sh`.

**Overlap analysis**:
- `scripts/renderer.sh` — DISJOINT (P1.M1.T2.S1 never touches renderer.sh). ✓
- `tests/test_functional.sh` — BOTH append test functions at EOF. If both land
  concurrently, the edit tool needs unique anchors. Since both APPEND (and the
  test function NAMES are distinct), the merge is clean as long as each anchors
  its insertion at a unique, still-present location (e.g. after a named existing
  test, or at EOF). The renderer tests should anchor after
  `test_window_confirm_lands_on_chosen_window` (the current last function) or at
  the end-of-file. **To avoid a collision if P1.M1.T2.S1 lands first**, anchor
  by appending after the LAST `}` in the file (EOF), not after a specific named
  function (which P1.M1.T2.S1 may have moved past). The `edit` tool's `oldText`
  should target the final lines of the file (e.g. the closing of
  `test_window_confirm_lands_on_chosen_window` or, if that moved, the file's true
  tail).

---

## Summary of load-bearing decisions (encoded in the PRP)

1. **Escape ONLY user-derived strings** (`$FILTER`, `${filtered[$i]}`) at the 5
   sites. Do NOT escape code-authored `#[...]`, color vars, `$TOTAL`/`$FLEN`/
   `$((cidx+1))`. (FINDINGS 2, 4)
2. **Two `local` expansions**: `esc_name="${filtered[$i]//\#/##}"` (use in lines
   94/96) and `esc_filter="${FILTER//\#/##}"` (use in lines 78/80/107). (FINDING 3)
3. **Do NOT touch filter.sh / stored state** — escaping is local-copy-only at
   emission. (FINDING 5)
4. **Regression test asserts the POSITIVE escaped form** (`##dev`, `query> ##dev`,
   `query> ##zz`), NOT a negative `#dev` (which false-fails). (FINDING 6)
5. **Test needs NO `attach_test_client`** — renderer is client-independent; seed
   `@livepicker-list`/`@livepicker-filter`/`@livepicker-index` directly. (FINDING 7)
6. **Two tests in `tests/test_functional.sh`** (auto-discovered), mirroring
   `test_typing_filters`'s `out="$(... renderer.sh)"` capture pattern. (FINDING 9)
7. **Append at EOF** (anchor by the file's tail, not a named function that the
   parallel task may have moved). (FINDING 10)
8. **No sourcing/strictness/driver change** in renderer.sh — just two locals + 5
   substitutions. (FINDING 8)

---

## Gaps

None material. Every behavior the fix + test depend on is either (a) proven live
on 3.6b here (FINDINGS 1, 2, 3, 6), or (b) confirmed by reading the current
working tree (FINDINGS 4, 5, 7, 8, 9, 10). The 5 emission sites are located by
content+line; the assertion-discrimination logic is verified for all 3 branches.
