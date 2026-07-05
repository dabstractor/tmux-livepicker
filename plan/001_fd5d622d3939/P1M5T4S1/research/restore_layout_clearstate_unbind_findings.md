# Research Findings — P1.M5.T4.S1: select-layout ORIG_LAYOUT + clear_all_state + unbind livepicker

All findings verified **live** on an isolated tmux 3.6b socket (PATH-wrapper
shim, `tmux -L <sock>`). Zero impact on the live server. Each test self-cleaned.

These are the load-bearing facts for the T4.S1 implementation block (PRD §9
restore steps 5–6). Read them before editing `scripts/restore.sh`.

---

## FINDING 1 — `select-layout "$ORIG_LAYOUT"` round-trips BYTE-IDENTICAL  ✓

`tmux display-message -p '#{window_layout}'` captures the full pane-geometry
string (e.g. `e79b,120x40,0,0[120x20,0,0,0,120x9,0,21,1,120x9,0,31,2]`).
Feeding that EXACT string back to `tmux select-layout -t <win> "<layout>"`
restores the pane geometry byte-for-byte.

Verified on a 3-pane window: capture → mutate (`select-layout tiled`, geometry
changes) → restore (feed the original string) → `#{window_layout}` matches the
pre-mutation value EXACTLY. This is the work-item §5 MOCKING assertion
("`#{window_layout}` matches the pre-activation layout byte-for-byte").

`ORIG_LAYOUT` is the value activate STEP 2 (P1.M4.T1.S1) saved via
`tmux set-option -g "@livepicker-orig-layout" "$(tmux display-message -p '#{window_layout}')"`
(see P1M4T1S1 PRP line 608 / line 491). So T4 reads it back via
`get_state "$ORIG_LAYOUT" ""` and feeds it to `select-layout` unchanged.

NOTE: `select-layout` applies to the CURRENTLY ACTIVE window. STEP 2 (T1.S1)
ALREADY ran `select-window -t "$orig_window"` above the T4 seam, so the target
window is active. T4 does NOT re-select-window (that would duplicate T1.S1's
work — see FINDING 7).

---

## FINDING 2 — `select-layout` is BEST-EFFORT: guard with `2>/dev/null || true`  ✓

`select-layout` returns rc=1 (and refuses to change the layout) when:
- the layout string is INVALID (`invalid layout: bogus-layout-string` — verified);
- the target window has VANISHED (`can't find window: @99999` — verified);
- the layout string is EMPTY (`invalid layout: ` — verified).

This matches the work-item contract: "Guard failure (layout may be invalid if
windows changed) — best-effort, do not block exit." So T4's select-layout call
MUST be `tmux select-layout "$orig_layout" 2>/dev/null || true`. Under the
house-style `set -u` (NO `set -e`) the `|| true` is belt-and-braces, but it is
the documented idiom (mirror STEP 1/2's `2>/dev/null || true` on unlink/select).

The empty-layout case also means T4 should GUARD on `orig_layout` being
non-empty before calling select-layout (defensive — `get_state "$ORIG_LAYOUT" ""`
could return empty if activate failed mid-save). Pattern (mirrors STEP 2's
`[ -n "$orig_window" ] && ...`):
```bash
[ -n "$orig_layout" ] && tmux select-layout "$orig_layout" 2>/dev/null || true
```

---

## FINDING 3 — `kill-key-table` does NOT exist on tmux 3.6b  [SHOWSTOPPER]

The work-item's "`tmux kill-key-table livepicker` if available on 3.6b
(verify; if not, loop unbind)" — **VERIFIED NOT AVAILABLE.**

```
$ tmux kill-key-table livepicker
unknown command: kill-key-table            rc=1
```

The keys REMAIN bound after the (failed) call. `kill-key-table` is a tmux-next /
future feature; it is NOT in 3.6b. T4 MUST NOT use it. Use `unbind-key -aT
livepicker` (FINDING 4) instead.

(`list-tables` also does NOT exist on 3.6b — `unknown command: list-tables`.
Not needed by T4, but noted so no one chases it.)

---

## FINDING 4 — `unbind-key -aT livepicker` (BULK) is the clean teardown  ✓

`tmux unbind-key -a -T livepicker` removes EVERY key in the `livepicker` table
in ONE atomic call. Verified: bound `a`+`b` → `unbind-key -aT livepicker` →
rc=0 → `list-keys -T livepicker` returns "table livepicker doesn't exist" (0
keys remain). After all keys are removed, the table is effectively gone
(`list-keys -T livepicker` rc=1, which is the work-item's "livepicker table
gone" success condition).

This is dramatically cleaner than the work-item's fallback "iterate
`list-keys -T livepicker` and unbind each key" — one call instead of ~169 (the
count activate T4.S1 copies in). The `-a` flag = "all keys"; `-T livepicker` =
the table scope. Both orderings of the flags (`-aT` / `-a -T`) work identically.

**GOTCHA — idempotency / empty-table guard:** when the `livepicker` table has
NO keys (or never existed — e.g. a double-restore, or restore without a
matching activate), `unbind-key -aT livepicker` returns rc=1 with
`table livepicker doesn't exist`. So it MUST be guarded `2>/dev/null || true`
(mirror house style; the failed call is harmless — there was nothing to clear).
Verified: first call (keys present) rc=0; second call (table now empty) rc=1.

Form:
```bash
tmux unbind-key -a -T livepicker 2>/dev/null || true
```

(The per-key loop alternative — `tmux list-keys -T livepicker | while read ...
tmux unbind-key -T livepicker "$key"` — ALSO works but is ~169 calls, needs the
same empty-table guard (`list-keys -T livepicker` rc=1 when empty), and risks a
race if a key is re-bound mid-loop. Prefer the bulk `-a` form.)

---

## FINDING 5 — `refresh-client -S` requires a client; guard it  ✓

`tmux refresh-client -S` redraws the status line (the `-S` flag = update the
status line only). This is what makes the restored status (T3.S1's status-format
restore + the status line-count restore) actually DRAW after teardown — the
`#()` renderer only re-runs on a status redraw (PRD §16 "Status renderer
refresh"; system_context §3 INVARIANT C).

Verified: with NO client attached, `refresh-client -S` returns rc=1
(`no current client`); with a client attached, rc=0. In PRODUCTION a client is
always attached (restore runs from a key press in the livepicker table —
confirm/cancel), so rc=0. But the test MOCK and any detached edge would rc=1,
so T4 guards it `2>/dev/null || true` (harmless if no client; matches house
style on every fail-possible tmux call).

This is the LAST call in restore_main (after select-layout + clear_all_state +
unbind) — so the redraw reflects the FULLY restored state. PRD §16: "Every
input action must call `refresh-client -S`." Restore's teardown is the final
such action.

---

## FINDING 6 — `clear_all_state` (state.sh) clears runtime + orig, KEEPS config  ✓

`clear_all_state` is ALREADY COMPLETE in `scripts/state.sh` (P1.M1.T3.S1). T4
just CALLS it. Verified live what it does to a fully-seeded option surface:

BEFORE (runtime + orig + config all set):
```
@livepicker-fg "#ffffff"            @livepicker-orig-key-table root
@livepicker-filter xy               @livepicker-orig-layout e79b,...
@livepicker-index 2                 @livepicker-orig-session demo
@livepicker-key Space               @livepicker-orig-window @3
@livepicker-linked-id @5            @livepicker-type session
@livepicker-list "a b c"
@livepicker-mode on
```
AFTER `clear_all_state` (rc=0):
```
@livepicker-fg "#ffffff"            @livepicker-key Space            @livepicker-type session
```

So clear_all_state:
- CLEARS the 5 runtime keys (mode/list/filter/index/linked-id) via `set-option -gu`;
- CLEARS every `@livepicker-orig-*` key (it greps `show-options -g | grep
  '@livepicker-orig-'` and unsets each) — this includes ORIG_LAYOUT, ORIG_WINDOW,
  ORIG_SESSION, ORIG_KEY_TABLE, ORIG_STATUS, ORIG_RENUMBER, ORIG_HOOK, and the
  status-format save keys;
- PRESERVES PRD §11 CONFIG (`@livepicker-key`, `@livepicker-fg`,
  `@livepicker-type`, ...) — CORRECTION A in state.sh: a broad `grep
  '@livepicker-'` would WIPE user config mid-session (the literal work-item
  spec was a production bug; state.sh corrected it).

**CORRECTION to encode in the PRP (the work-item's "no @livepicker-* options
remain" assertion is TOO BROAD):** the work-item §4 OUTPUT says
"`tmux show-options -g | grep livepicker` empty" and §5 MOCKING says "no
@livepicker-* options remain." Taken LITERALLY, that would require clearing the
user's config keys (@livepicker-key Space, @livepicker-fg #ffffff,
@livepicker-type session, ...) — which is WRONG (CORRECTION A) and would break
the next activation (no @livepicker-key → the guard in plugin.tmux refuses to
bind; no @livepicker-fg → wrong color). The CORRECT assertion (per state.sh
CORRECTION A + PRD §11) is:
- `show-options -g | grep '@livepicker-orig-'` → EMPTY (saved-state cleared);
- the 5 runtime keys (mode/list/filter/index/linked-id) → EMPTY (picker state cleared);
- CONFIG keys (@livepicker-key, @livepicker-fg, @livepicker-type, @livepicker-bg,
  @livepicker-create, ... per PRD §11) → UNCHANGED (user config preserved).

The mock in the PRP uses the SCOPED grep (`grep '@livepicker-orig-'` + the 5
runtime names), NOT the broad `grep livepicker`.

---

## FINDING 7 — T4 does NOT re-select-window; STEP 2 (T1.S1) already did it  ✓

The work-item's first bullet — "`tmux select-window -t "$ORIG_WINDOW"` (ensure
target window is active for layout apply)" — is a NOTE about the PREREQUISITE
for select-layout (layout applies to the active window), NOT a new command for
T4. STEP 2 (T1.S1) already ran `tmux select-window -t "$orig_window" 2>/dev/null
|| true` ABOVE the T4 seam (between STEP 1's unlink and the T2/T3 seams). T4
REUSES that — it does NOT re-issue select-window (that would duplicate T1.S1's
work and muddy the seam boundary). The PRP makes this explicit so the
implementer does not add a redundant select-window call.

(If a future race makes the window not-active at T4 time, select-layout would
apply to whatever window IS active — a mild bug, but acceptable: select-layout
is best-effort by FINDING 2, and the window is active by construction since
STEP 2 ran immediately above with no intervening select-window.)

---

## FINDING 8 — ORDERING: select-layout BEFORE clear_all_state (ORIG_LAYOUT is read)  ✓

`clear_all_state` CLEARS `@livepicker-orig-layout` (FINDING 6). T4 reads
ORIG_LAYOUT via `get_state "$ORIG_LAYOUT" ""` and feeds it to `select-layout`.
If clear_all_state ran FIRST, ORIG_LAYOUT would be empty and select-layout would
no-op (or fail on the empty string — FINDING 2). So the ORDER is load-bearing:

1. read `orig_layout` via `get_state "$ORIG_LAYOUT" ""`;
2. `select-layout "$orig_layout"` (best-effort, guarded) — STEP 5;
3. `clear_all_state` (clears runtime + orig-*) — STEP 6a;
4. `unbind-key -a -T livepicker` (clears the key table) — STEP 6b;
5. `refresh-client -S` (redraw status) — final.

This matches PRD §9 (step 5 select-layout, THEN step 6 clear+unbind) and the
work-item's stated order. clear_all_state and unbind-key are independent (one
clears options, one clears bindings) so 3↔4 could swap, but keeping clear
(options) before unbind (keys) reads as PRD §9 step 6's "Clear every
@livepicker-* option AND unbind the livepicker table."

---

## FINDING 9 — House style: `set -u` only; tabs; `|| true` on every fail-possible call  ✓

Mirror T1.S1/T2.S1/T3.S1 + system_context §9. NO `set -e`, NO `set -o pipefail`
(select-layout/unbind-key/refresh-client legitimately return non-zero —
FINDINGS 2/4/5). One-tab indent inside `restore_main`. Every fail-possible tmux
call gets `2>/dev/null || true`. `local` for all function locals (T4 adds ONE:
`orig_layout`). The file-level `# shellcheck disable=SC1091,SC2153` from T1.S1
still covers everything; T4 adds NO new word-split on user input → NO new
shellcheck disable needed.

T4's seam comment block (left by T1.S1) is REPLACED by the STEP 5+6 logic; the
header doc-comment's seam-map lines 5–6 ("5. select-layout ... [T4 seam]" /
"6. clear_all_state + unbind ... [T4 seam]") already describe T4 and may be left
as-is (optionally relabeled `[T4]`). No header edit required.

---

## Full-flow proof (the 5-line T4 block on an isolated socket)

Ran the complete T4 block (select-layout → clear_all_state → unbind → refresh)
on a 3-pane window seeded with the full @livepicker-* surface + a bound
livepicker table:

```
select-layout restored #{window_layout} byte-identical     ✓
clear_all_state: 0 @livepicker-orig-* remain               ✓
clear_all_state: 5 runtime keys empty                      ✓
clear_all_state: config (@livepicker-key/fg/type) KEPT     ✓
unbind-key -aT livepicker: 0 keys remain (table gone)      ✓
unbind-key -aT livepicker (2nd call): rc=1 guarded         ✓ (idempotent)
refresh-client -S (with client): rc=0                       ✓
```

The block is 5 logical lines (one local + 4 tmux calls, all guarded). After it:
the original pane geometry is restored, zero picker runtime/orig state remains,
the livepicker table is gone, and the status redraws. This completes the
PRD §9 restore sequence (steps 5–6) and the PRD §15.21 "Restore" invariant.
