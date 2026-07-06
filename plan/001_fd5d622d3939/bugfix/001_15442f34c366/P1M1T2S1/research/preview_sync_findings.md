# input-handler preview-sync — empirical & structural grounding

> Verified against the working tree at `/home/dustin/.config/tmux/plugins/tmux-livepicker`
> on 2026-07-06. This file nails the EXACT edit anchors (content-based, not
> line-based — line numbers drift because the parallel task P1.M1.T1.S1 deletes a
> line in the confirm branch) and the test design.

## 1. Current line numbers (PRE P1.M1.T1.S1) + the drift caveat

`scripts/input-handler.sh` branch landmarks (current working tree):

| Anchor | Line | Notes |
|---|---|---|
| `_confirm_land_on_session()` def | 79 | the new helper goes right AFTER its closing `}` (~line 119) |
| `# argv[1] = action...` / `input_main()` | 120 / 121 | the helper goes BEFORE this |
| `type)` branch | 127 | `set_state "$STATE_INDEX" "0"` at **147**; `tmux refresh-client -S` at ~149 |
| `backspace)` branch | 159 | `set_state "$STATE_INDEX" "0"` at **180**; refresh at ~182 |
| `next-session)` / preview call | 186 / ~216 | the pattern to MIRROR |
| `prev-session)` / preview call | 220 / ~235 | (mirror) |
| `confirm)` | 244 | **P1.M1.T1.S1 deletes a duplicate line at ~301** |
| `cancel)` | 338 | query-clear `set_state "$STATE_INDEX" "0"` at **353**; refresh at ~355 |

**DRIFT CAVEAT (critical):** P1.M1.T1.S1 (running in parallel) deletes the
duplicate `restore.sh keep-window` line at ~301 in the **confirm** branch.
Everything AFTER line 301 shifts up by 1. So the **cancel** branch landmarks
(338/353/355) become 337/352/354 after T1.S1 lands. The `type`/`backspace`
branches (lines 127–184) are BEFORE 301 → unaffected. **Therefore: anchor every
edit by CONTENT (the `set_state "$STATE_INDEX" "0"` + following `tmux
refresh-client -S` pair, inside each named branch), NOT by line number.**

## 2. Content-based edit anchors (use these, not line numbers)

Each of the three target branches (type / backspace / cancel query-clear) ends
its state-mutation with this EXACT pair (indent = 2 tabs inside `input_main`,
3 tabs inside the cancel `if`):

```
			set_state "$STATE_INDEX" "0"
			tmux refresh-client -S 2>/dev/null || true
```

The helper call inserts BETWEEN these two lines in each branch:

```
			set_state "$STATE_INDEX" "0"
			_lp_sync_preview_to_top_match    # <-- NEW (sync preview to filtered[0])
			tmux refresh-client -S 2>/dev/null || true
```

To make each `oldText` UNIQUE for the edit tool, include the preceding
branch-specific line:
- **type**: the preceding line is `set_state "$STATE_FILTER" "$new_filter"` … then
  `set_state "$STATE_INDEX" "0"`. Actually the unique anchor is the `type` branch's
  `new_filter="$(get_state "$STATE_FILTER" "")$char"` a few lines up. Simplest:
  match the `set_state INDEX 0` + `refresh` pair and disambiguate via the
  surrounding comment lines that are unique per branch.
- **backspace**: unique via its comment `# (a known minor UX gap that re-syncs on
  the next nav/confirm).` (this comment is ALSO being rewritten — see §5).
- **cancel query-clear**: unique via its `set_state "$STATE_FILTER" ""` (writes
  empty string) immediately above, + the 3-tab indent (it is inside the
  `if [ -n "$cur_filter" ]; then`).

The nav branches (next/prev) are the REFERENCE — they already do
`"$CURRENT_DIR/preview.sh" "$target" 2>/dev/null || true` then
`tmux refresh-client -S 2>/dev/null || true`. The helper replicates that call
shape, always at index 0.

## 3. The helper to add (verbatim body)

Place AFTER `_confirm_land_on_session`'s closing `}` and BEFORE the
`# argv[1] = action; argv[2]...` / `input_main()` block. `$CURRENT_DIR` is a
module-level global (set ~line 57, before any function) → in scope (same as
`_confirm_land_on_session` uses `"$CURRENT_DIR/restore.sh"`). `lp_build_filtered`
is in scope (input-handler.sh `source "$CURRENT_DIR/filter.sh"`). `get_state` +
`STATE_LIST`/`STATE_FILTER` in scope (state.sh sourced).

```bash
# _lp_sync_preview_to_top_match — re-link the live preview to the TOP filtered
# match (index 0), so the preview pane tracks the status-line highlight when the
# user types / backspaces / clears the query (PRD §3 story 3 + README "the preview
# follows live"). Reconciles PRD §5 (which lists type/backspace as status-only) in
# favour of §3 / the README. Mirrors the nav (next/prev) resolution: same
# lp_build_filtered the renderer uses (so filtered[0] == the highlighted session),
# same preview.sh call + `2>/dev/null || true` guard. type/backspace/cancel-clear
# always reset @livepicker-index to 0, so the top match is ALWAYS filtered[0].
# Empty filtered list (no matches) -> skip the preview (leave the prior pane as-is,
# mirroring nav's `[ "$L" -eq 0 ] && return 0` guard).
_lp_sync_preview_to_top_match() {
	local _list _filt
	local -a _sync_filtered=()
	_list="$(get_state "$STATE_LIST" "")"
	_filt="$(get_state "$STATE_FILTER" "")"
	mapfile -t _sync_filtered < <(lp_build_filtered "$_list" "$_filt")
	[ "${#_sync_filtered[@]}" -eq 0 ] && return 0
	"$CURRENT_DIR/preview.sh" "${_sync_filtered[0]}" 2>/dev/null || true
}
```

Naming: leading `_` = internal helper (matches `_confirm_land_on_session`). The
local array is `_sync_filtered` (NOT `filtered`) to avoid any visual confusion
with `input_main`'s own `local -a filtered=()` — though they are in separate
scopes, the distinct name makes the helper self-contained and grep-friendly.

## 4. The nav resolution pattern (the template — verbatim from next-session)

This is what the helper generalizes (nav uses `filtered[$new_idx]`; the helper
always uses index 0):

```bash
cur_list="$(get_state "$STATE_LIST" "")"
cur_filter="$(get_state "$STATE_FILTER" "")"
mapfile -t filtered < <(lp_build_filtered "$cur_list" "$cur_filter")
L="${#filtered[@]}"
[ "$L" -eq 0 ] && return 0
...
target="${filtered[$new_idx]}"
"$CURRENT_DIR/preview.sh" "$target" 2>/dev/null || true
tmux refresh-client -S 2>/dev/null || true
```

filter.sh `lp_build_filtered LIST FILTER` is the SAME function renderer.sh uses
(`source`d by both renderer.sh and input-handler.sh) → filtered[0] is provably
the session the status bar highlights (byte-identical filter). This is the
load-bearing guarantee that the preview and the highlight stay in sync.

## 5. Comments to update (Mode A docs)

**backspace branch** — the stale comment (current, ~line 167):
```
			# CONTRACT (work-item §3): backspace = filter+index+refresh ONLY.
			# It does NOT call preview.sh (FINDING 4) — the top match is already
			# shown; shortening the filter may re-admit a different top match
			# (a known minor UX gap that re-syncs on the next nav/confirm).
```
Rewrite to reflect the fix: backspace now syncs the preview to the (possibly
new) top match via `_lp_sync_preview_to_top_match`. Keep the PRD §5-vs-§3 note.

**type branch** — its comment does NOT reference "the gap", but should be lightly
extended to state the preview now follows the top match (accuracy). The contract
says update it "if it references the gap" — it doesn't, so this is optional but
recommended for accuracy.

**cancel query-clear branch** — its comment says "Mirror backspace (T2.S1)
exactly: set filter, set index=0, refresh". Since backspace now also syncs the
preview, update this to note cancel-clear likewise re-syncs to the (now-unfiltered)
top match.

## 6. Test design (added to tests/test_functional.sh)

**Placement**: `tests/test_functional.sh` (preferred — it already owns
`test_typing_filters` and `test_nav_moves_selection`, the EXACT activate→type→assert
pattern to mirror; the contract allows test_preview.sh as an alternative).

**Pattern to mirror**: `test_typing_filters` (creates syslog+blog BEFORE activate,
types "log", asserts filter view) + `test_nav_moves_selection` (asserts
@livepicker-linked-id == the target's dynamically-read window id). Both call
`attach_test_client` first (livepicker.sh activate needs an attached client — it
uses display-message/lp_client_format).

**Primary test `test_preview_follows_type_filter`** (deterministic; FAILS before
the fix because linked-id stays "" on self-session):
- attach_test_client; create syslog + blog BEFORE activate; livepicker.sh.
- Assert initial linked-id == "" (activate previews the self-session/driver).
- Read blog's active window id DYNAMICALLY (window ids are global).
- Type "blog" (for c in b l o g) → uniquely matches blog.
- Assert linked-id == blog_wid. (Before the fix: linked-id stays "" → FAIL.)

Intermediate states during typing ("b" matches beta+blog) don't matter — only the
FINAL state ("blog" uniquely → blog) is asserted.

**Backspace variant `test_preview_follows_backspace`** (proves the backspace
branch also syncs; deterministic via dynamic expected-value):
- Same setup; type "blog" → linked-id == blog_wid.
- Backspace 4× → filter "" → full list; index reset to 0.
- Compute the top-of-full-list session DYNAMICALLY from @livepicker-list (first
  newline). Its expected linked-id is "" if it is the driver (self-session path
  clears linked_id) else that session's active window id.
- Assert linked-id == expected. (Before the fix: linked-id stays blog_wid → FAIL,
  because blog (created last) is never the top of the full list — the baseline
  driver/alpha/beta precede it.)

The dynamic expected-value computation makes the backspace variant robust to
list ordering AND handles the contract's "(or self-session)" hedge.

**No lp_preview_seed_state** — livepicker.sh activate seeds all @livepicker-*
state; the test drives the full activate→type flow (per contract).

## 7. Safety: why calling preview.sh from type/backspace is harmless

preview.sh does link-window + select-window + set_state STATE_LINKED_ID — the
EXACT operation next/prev already perform on every navigation. It fires
session-window-changed (suppressed globally by activate P1.M4.T4.S2) but NEVER
client-session-changed (Invariant A — no session-history pollution). The only
difference vs nav: type/backspace/cancel-clear always use index 0 (the top match);
nav uses the wrapped index. Same mechanism → same safety guarantees.

## 8. Isolation / harness facts

- Each `test_*` runs on a FRESH isolated `-L` socket (run.sh → setup_test →
  teardown_test per test). The global @livepicker-type/status mutations never leak.
- `attach_test_client` (setup_socket.sh) spawns a `script`-based pty client on the
  isolated socket; REQUIRED before livepicker.sh (activate uses lp_client_format).
- Test bodies run in the CURRENT shell under `set -u`; every var MUST be `local`;
  signal failure ONLY via fail()/assert_* (NEVER `exit` — run.sh reads TEST_STATUS).
- New `test_*` functions are auto-discovered by run.sh
  (`compgen -A function | grep '^test_'`) — no registration needed.
