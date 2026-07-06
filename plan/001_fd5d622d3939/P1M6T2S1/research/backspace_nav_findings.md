# Research Findings — P1.M6.T2.S1: input-handler.sh backspace / next-session / prev-session

> Empirical + codebase findings gathered 2026-07-05. Grounded in the COMPLETE
> siblings: `scripts/state.sh`, `scripts/renderer.sh`, `scripts/preview.sh`,
> `scripts/utils.sh`, `scripts/options.sh`, `scripts/livepicker.sh`, and the
> parallel PRP `P1.M6.T1S1/PRP.md` (creates `scripts/input-handler.sh` with the
> `backspace|next-session|prev-session)` seam this task fills).

---

## FINDING 1 — Caller contract: nav/backspace take argv[1] ONLY (no char)

`scripts/livepicker.sh` (activate T4.S1, COMPLETE) binds the keys verbatim:

```bash
# backspace (line 211-212):
for lp_c in $(opt_backspace_keys); do
	tmux bind-key -T livepicker "$lp_c" run-shell "$CURRENT_DIR/input-handler.sh backspace"
done
# next-session (line 224-225):
tmux bind-key -T livepicker "$lp_c" run-shell "$CURRENT_DIR/input-handler.sh next-session"
# prev-session (line 228-229):
tmux bind-key -T livepicker "$lp_c" run-shell "$CURRENT_DIR/input-handler.sh prev-session"
```

**Contrast with `type`** (T1.S1): `type` passes `$lp_c` as argv[2]
(`input-handler.sh type $lp_c`). backspace/nav do NOT — argv is JUST the action.
So the backspace/nav branches read ONLY `$1` (the action); they never touch `$2`.
Under `set -u` this is safe because the branches don't reference `$2`.

## FINDING 2 — The renderer's filter algorithm (the EXACT spec to reproduce)

`scripts/renderer.sh` `render()` (COMPLETE) computes the filtered list like this:

```bash
mapfile -t all < <(printf '%s' "$LIST")     # LIST via get_state STATE_LIST
TOTAL="${#all[@]}"
low_filter="${FILTER,,}"                      # lowercase the query
for name in "${all[@]}"; do
	low_name="${name,,}"                      # lowercase each candidate
	if [[ "$low_name" == *"$low_filter"* ]]; then
		filtered+=("$name")                   # preserve ORIGINAL case + ORDER
	fi
done
FLEN="${#filtered[@]}"
```

Key properties the input-handler's filter MUST reproduce byte-for-byte:
- **Parse:** `mapfile -t all < <(printf '%s' "$LIST")` — `printf '%s'` (NO trailing
  newline). An empty LIST → `all=()` (empty array, NOT `[""]`). A trailing newline
  in LIST is harmless (mapfile -t strips it; no phantom empty element).
- **Case-insensitive substring:** lowercase BOTH sides via `${VAR,,}`; match with
  `[[ "$low_name" == *"$low_filter"* ]]`. Empty filter → `*""*` matches ALL names
  (so navigation works with no query typed — PRD §6 nav is independent of filter).
- **Order preserved:** `filtered[]` is in the SAME order as `all[]` (the order
  `@livepicker-list` was built by activate T2.S1, i.e. `list-sessions` order).
- **INDEX is 0-based** and the renderer CLAMPS it (`idx>=FLEN → FLEN-1`,
  `idx<0 → 0`). Wrapping is the INPUT-HANDLER's job (PRD §6 + this task).

**Work-item contract point 1:** "The filtered[index] resolution must match the
renderer's ordering exactly — share a single filter function (put it in
utils.sh or a tiny sourced helper to avoid drift)."

## FINDING 3 — DECISION: create `scripts/filter.sh` (the shared helper); refactor renderer.sh to use it too

Two locations are endorsed by the contract: utils.sh OR a tiny sourced helper.
Chosen: a **new sourced helper `scripts/filter.sh`** defining `lp_build_filtered()`.

Why a new file (not utils.sh):
- utils.sh's mission is "safe tmux option & hook primitives" (tmux_get_opt /
  tmux_set_opt / tmux_unset_opt / tmux_save_opt / tmux_is_set / tmux_get_hook /
  tmux_clear_hook). A list-filter function is semantically off-mission there.
- A dedicated `filter.sh` is single-responsibility and trivially sourceable.
- Matches PRD §12 / system_context §8 file-layout conventions (one module per concern).

Why ALSO refactor `scripts/renderer.sh` to source + use it:
- The contract demands "a SINGLE filter function ... to avoid drift." If only
  input-handler.sh uses filter.sh while renderer.sh keeps its inline copy, there
  are TWO copies that can drift — exactly what the contract warns against.
- The refactor is mechanical (6-line inline loop → 1 `mapfile` call into the
  helper's stdout; remove the 3 now-unused locals `low_filter name low_name`;
  add one `source` line). The renderer's `render || printf error` fallback
  (FINDING 9 of renderer_findings.md) protects the status bar even on regression.
- Re-validation is cheap: re-run the renderer's existing Level 2 mock (P1.M2.T1.S1).

### The helper (canonical, ready to paste)

```bash
#!/usr/bin/env bash
# scripts/filter.sh — tmux-livepicker shared filtered-list builder.
# Sourced library (NOT executed). NO source-time side effects.
set -u   # NOT -e; NOT -o pipefail.

# lp_build_filtered LIST FILTER
#   Print each name from LIST (newline-separated) that case-insensitively
#   contains FILTER (substring), one per line, PRESERVING original order+case.
#   Empty FILTER matches all names. Empty LIST prints nothing.
#   THIS IS THE SINGLE FILTER FUNCTION shared by renderer.sh (#() status) and
#   input-handler.sh (nav index resolution) — see PRD §6 + work-item contract.
#   Algorithm MUST stay byte-identical to what renderer.sh used inline
#   (mapfile -t < <(printf '%s' "$LIST") ; ${FILTER,,} ; [[ == *"$low"* ]]).
lp_build_filtered() {
	local LIST="${1:-}"
	local FILTER="${2:-}"
	local -a all=()
	local low_filter name low_name
	mapfile -t all < <(printf '%s' "$LIST")
	low_filter="${FILTER,,}"
	for name in "${all[@]}"; do
		low_name="${name,,}"
		if [[ "$low_name" == *"$low_filter"* ]]; then
			printf '%s\n' "$name"
		fi
	done
}
```

Round-trip correctness (caller does `mapfile -t filtered < <(lp_build_filtered ...)`):
- `printf '%s\n' "$name"` per match → e.g. "alpha\nbeta\n"; caller `mapfile -t`
  strips the trailing newline → `["alpha","beta"]`. Identical to the renderer's
  prior `filtered+=("$name")` accumulation.
- Empty LIST → `all=()` → loop body never runs → no output → caller `filtered=()`.

### renderer.sh refactor (mechanical)

BEFORE (`render()`):
```bash
mapfile -t all < <(printf '%s' "$LIST")
TOTAL="${#all[@]}"
low_filter="${FILTER,,}"
for name in "${all[@]}"; do
	low_name="${name,,}"
	if [[ "$low_name" == *"$low_filter"* ]]; then
		filtered+=("$name")
	fi
done
FLEN="${#filtered[@]}"
```
AFTER:
```bash
mapfile -t all < <(printf '%s' "$LIST")
TOTAL="${#all[@]}"
mapfile -t filtered < <(lp_build_filtered "$LIST" "$FILTER")
FLEN="${#filtered[@]}"
```
PLUS: add `# shellcheck source=filter.sh` + `source "$CURRENT_DIR/filter.sh"`
AFTER the state.sh source (load-bearing trio order preserved; filter.sh has no
deps). PLUS: trim the now-unused locals: `local TOTAL FLEN low_filter name
low_name` → `local TOTAL FLEN`.

## FINDING 4 — backspace logic (PRD §6 Filtering + work-item §3)

Work-item: "new_filter = old_filter with last char removed (guard empty). Set
filter. Set index=0. refresh-client -S."

- Strip last char via parameter expansion: `new_filter="${cur_filter%?}"`.
  `${var%?}` removes the shortest trailing match of one char. On an EMPTY var it
  yields "" (no error, no `set -u` issue) — but per the contract "guard empty":
  skip the filter write when already empty (writing "" over "" is a no-op anyway,
  and the guard makes intent explicit).
- ALWAYS reset `@livepicker-index` to "0" (PRD §6: filter change → highlight snaps
  to top match). Safe even if filtered list is empty (renderer handles FLEN=0).
- ALWAYS `tmux refresh-client -S 2>/dev/null || true` (re-runs the #() renderer;
  detached-edge guard — mirror restore.sh STEP 6c / T1.S1 `type` branch).
- Reads: `@livepicker-filter`. Writes: `@livepicker-filter`, `@livepicker-index`.
  Does NOT touch list/mode/linked-id. Does NOT call preview.sh (backspace never
  moves the highlight OFF the top match, and the top match is already previewed
  from activate's first preview / the prior keystroke — re-previewing is harmless
  but unnecessary; keep it minimal per the contract).

NOTE: the contract lists NO preview.sh call for backspace — only filter+index+
refresh. Honor that (don't over-engineer). The renderer redraw shows the new
shorter query + the top match highlighted; the live preview does NOT need to
re-link because index resets to 0 and the session at index 0 is unchanged by
shortening the filter... EXCEPT: shortening the filter can ADD matches at the
top (e.g. filter "log"→"lo" re-admits "lobby" ahead of "login"), changing which
session is at index 0. Is a preview.sh call needed to keep the preview in sync?

**Resolution:** PRD §6 Filtering says typing/backspace "resets the index to the
top match" and the renderer redraws. The PREVIEW for index 0 after a backspace
SHOULD reflect the (possibly different) top match. BUT the work-item contract
for backspace (§3) explicitly lists ONLY: set filter, set index=0, refresh — NO
preview.sh call. The parallel T1.S1 seam comment ALSO lists no preview for
backspace. So the AUTHORITATIVE contract is: backspace does NOT call preview.sh.
(The preview will re-sync on the next nav/confirm; or the implementer may note
this as a known minor UX gap. Do NOT add a preview call — it would diverge from
the contract and risk scope creep. If a reviewer wants it, it's a future task.)
**Implementer action: follow the contract — backspace = filter+index+refresh only.**

## FINDING 5 — next-session / prev-session logic (PRD §6 nav + work-item §3 + Invariant A)

Work-item §3:
- next-session: compute filtered length L (same filter as renderer). If L==0,
  no-op. Else index=(index+1)%L. Call preview.sh "<filtered[index]>". refresh -S.
- prev-session: index=(index-1+L)%L. preview + refresh.

Key points:
- **INVARIANT A (system_context §3):** nav MUST NOT call `switch-client`. It only
  (a) moves `@livepicker-index` within the filtered list, (b) calls preview.sh
  (which link/select-windows — fires `session-window-changed`, suppressed by
  activate T4.S2, but NEVER `client-session-changed`). Session history stays clean.
- **L==0 guard:** if the filter matches nothing, nav is a no-op (return 0) —
  there is nothing to highlight/preview. Do NOT divide by zero.
- **Wrap:** `(index+1) % L` and `(index-1+L) % L` implement modulo wrap (PRD §6
  "wrapping"). The `+L` in prev avoids bash's negative-modulo quirk (bash `%`
  can return negatives for negative operands; `(+L)` keeps it positive).
- **Index sanitize:** `@livepicker-index` is a string from an option; defensively
  coerce to a non-negative int: `[[ "$cur_index" =~ ^[0-9]+$ ]] || cur_index=0`.
  (The renderer also clamps, but nav must compute modulo on a sane int.)
- **preview.sh call:** `"$CURRENT_DIR/preview.sh" "$target"` where
  `target="${filtered[$new_idx]}"`. This matches livepicker.sh line 277
  (`"$CURRENT_DIR/preview.sh" "$orig_session"`). preview.sh is its own process
  under run-shell; it sources its own lib trio (incl. filter.sh after this task).
  Guard `2>/dev/null || true` — a preview failure (session gone) must NOT crash
  nav; the index still advances and the status redraws.
- **Order of ops:** set the NEW index FIRST, resolve target from the filtered
  list at the NEW index, THEN call preview.sh, THEN refresh-client -S. (So the
  renderer redraw shows the new highlight, and the live preview shows the new
  session — both consistent.)
- **Reads:** filter, list, index. **Writes:** index. (preview.sh writes
  linked-id internally.) Does NOT write filter/list/mode.

## FINDING 6 — No `tmux_refresh_client` helper exists; call bare `tmux refresh-client -S`

Confirmed in `scripts/utils.sh`: the helpers are tmux_get_opt / tmux_set_opt /
tmux_unset_opt / tmux_save_opt / tmux_is_set / tmux_get_hook / tmux_clear_hook.
NO refresh-client wrapper. House style (restore.sh STEP 6c, T1.S1 `type` branch)
permits a DIRECT bare `tmux refresh-client -S 2>/dev/null || true` call for this
one-off primitive. Do NOT add a utils helper.

## FINDING 7 — input-handler.sh is its OWN process under run-shell; sources its own trio + filter.sh

restore.sh FINDING 7 / T1.S1 FINDING 7: a script under `run-shell` is a fresh
bash process; sourced state does NOT cross process boundaries. So input-handler.sh
MUST source its OWN lib trio (options/utils/state) AND the new filter.sh. T1.S1
already sources the trio; T2.S1 ADDS `source "$CURRENT_DIR/filter.sh"` after
state.sh. Source order is load-bearing only for the trio (state.sh needs
utils.sh); filter.sh has no deps, so appending it last is safe.

## FINDING 8 — Seam-fill model: T2.S1 EDITS input-handler.sh in place (does NOT recreate)

T1.S1 (parallel, in-flight) CREATES `scripts/input-handler.sh` with this seam
(T1.S1 PRP "Implementation Patterns & Key Details", confirmed verbatim):
```bash
# --- P1.M6.T2.S1 seam: backspace / next-session / prev-session ---
# backspace:      new_filter="${old_filter%?}"; set_state FILTER; index=0; refresh.
# next-session:   index = (index+1) % FLEN (wrap); refresh preview.sh + refresh -S.
# prev-session:   index = (index-1+FLEN) % FLEN (wrap); refresh preview.sh + refresh -S.
# (FLEN comes from re-filtering @livepicker-list by @livepicker-filter —
#  the same case-insensitive substring the renderer uses.)
backspace|next-session|prev-session)
	return 0
	;;
```
T2.S1 SPLITS that combined branch into THREE separate, fully-implemented branches
(`backspace)` / `next-session)` / `prev-session)`), preserving the `confirm)`
(T3) and `cancel)` (T4) seams and the `*) return 0` default untouched. This is
the SAME incremental-edit model P1.M5 used to grow restore.sh across T1→T4.
T2.S1 also grows the `local` line: T1.S1's `local action char new_filter` →
`local action char new_filter cur_filter cur_list cur_index L new_idx target` +
`local -a filtered=()`.

## FINDING 9 — preview.sh contract recap (what nav depends on)

`scripts/preview.sh` (COMPLETE, P1.M3.T1.S1+S2) `preview_main()`:
- argv[1] = candidate session name `S`.
- Reads `@livepicker-orig-session` (the driver), `@livepicker-orig-window`,
  `@livepicker-linked-id`, `@livepicker-preview-mode` (default live).
- For `S != driver`: resolves S's active window id (`list-windows -t "=$S" -F
  '#{window_id}' -f '#{window_active}'`); unlink-window the prior preview (no -k);
  link-window -a -s src_id -t "driver:"; select-window src_id; set linked-id.
- Duplicate guard: if linked_id == src_id (single-match wrap), skip unlink+link,
  just select-window. So calling preview.sh with the SAME session twice is safe
  (the wrap case in our mock: 3 nexts → alpha→beta→gamma→alpha; the 4th next
  re-previews alpha, which was the FIRST preview — linked_id may differ, so a
  fresh link happens; either way correct).
- Does NOT fire client-session-changed (Invariant A). DOES fire
  session-window-changed (suppressed globally by activate T4.S2).

So nav's `preview.sh "$target"` is a clean delegation; nav does NOT re-implement
any link/unlink logic.

## FINDING 10 — Mock design (work-item §5): 3 matches, next×3 wraps, preview cycles, client-session-changed never fires

Setup (socket-isolated shim, attached driver client):
- Create a `driver` session (ATTACHED — refresh-client -S needs a client) + 3
  detached candidate sessions `alpha` `beta` `gamma`, each with one window.
- Seed picker state as activate would:
  - `@livepicker-list` = $'alpha\nbeta\ngamma'
  - `@livepicker-filter` = "" (empty → all 3 match → L=3)
  - `@livepicker-index` = "0"
  - `@livepicker-mode` = "on"
  - `@livepicker-preview-mode` = "live" (default; set explicitly for determinism)
  - `@livepicker-orig-session` = "driver"
  - `@livepicker-orig-window` = driver's active window id
  - `@livepicker-linked-id` = "" (cleared)
- Plant a client-session-changed canary: `tmux set-hook -g client-session-changed
  "set-option -g @lp-csc-fired 1"`; assert `@lp-csc-fired` stays unset throughout.

Assertions:
1. Index cycles 0→1→2→0 across 3 nexts (wrap). Check `@livepicker-index` after each.
2. Preview cycles alpha→beta→gamma→alpha. Check `@livepicker-linked-id` after each
   press == the EXPECTED candidate's active window id
   (`tmux list-windows -t "=alpha" -F '#{window_id}' -f '#{window_active}'`).
3. `@lp-csc-fired` NEVER set (Invariant A — no switch-client).
4. prev×3 cycles back 0→2→1→0 (reverse wrap); linked-id follows.
5. backspace on filter "abc" → "ab", index resets to 0; backspace on "" → no-op
   (filter stays "", index 0); renderer reflects the (un)filtered set.
6. Filter "zzz" (no match) → next is a no-op (index unchanged, linked-id unchanged,
   no division-by-zero error).

This mock is self-cleaning (trap kill-server + rm shim dir). It reuses the
PATH-wrapper shim idiom (system_context §7) — the harness P1.M7 will formalize.
