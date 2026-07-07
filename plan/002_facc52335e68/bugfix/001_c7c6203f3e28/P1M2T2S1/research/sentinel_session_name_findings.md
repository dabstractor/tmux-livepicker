# Research — P1.M2.T2.S1: stable sentinel session name + second renderer swap (Issue 5)

> All findings below were verified LIVE against a fresh isolated tmux socket via
> `tests/setup_socket.sh` (the repo's own PATH-shim harness) on tmux 3.6b, against
> the CURRENT working tree (rev 002: §17 theme tabs + §18 deferred preview landed).
> Bug context: `plan/002_facc52335e68/bugfix/001_c7c6203f3e28/architecture/issue4_5_6_findings.md` §Issue 5.

---

## FINDING 1 — BUG REPRO: with the current UNIQUE sentinel name, session specifiers bake an unswappable string

**Live-verified.** `_lp_resolve_tab_templates()` (livepicker.sh line 76) sets
`sent_sess="__lp_sent_$$_$(date +%s)"` (unique per activation). It creates a 2-window
sentinel session: window `__lp_anchor__` + window `__lp_tab__`. Then `display-message`
resolves the theme's format against `"$sent_sess:__lp_tab__"`.

| specifier | resolves to | swappable? |
|-----------|-------------|------------|
| `#W` (window name) | `__lp_tab__` | ✓ (renderer swaps it) |
| `#{session_name}` | `__lp_sent_<PID>_<EPOCH>` | ✗ (NOT a fixed placeholder) |
| `#S` (session name) | `__lp_sent_<PID>_<EPOCH>` | ✗ (NOT a fixed placeholder) |

So a theme whose `window-status-format` / `window-status-current-format` contains a
SESSION-state specifier (`#S`/`#{session_name}`) bakes the unique sentinel session name
into the cached template. The renderer only swaps `__lp_tab__`, so EVERY tab renders the
literal `__lp_sent_<PID>_<EPOCH>`. The unexpanded-`#{` guard (livepicker.sh lines 102-103)
does NOT catch this — the specifier expanded fully (to the sentinel's session name),
leaving no residual `#{`. **This is exactly the Issue 5 bug.**

---

## FINDING 2 — THE FIX: a fixed sentinel session name `__lp_sentinel__` makes session specifiers swappable

**Live-verified.** Using a FIXED sentinel session name `__lp_sentinel__`:

| specifier | resolves to | swappable? |
|-----------|-------------|------------|
| `#W` | `__lp_tab__` | ✓ |
| `#{session_name}` | `__lp_sentinel__` | ✓ (NOW a fixed placeholder) |
| `#S` | `__lp_sentinel__` | ✓ (NOW a fixed placeholder) |

The renderer then swaps BOTH `__lp_tab__` AND `__lp_sentinel__` → the candidate name.
Tabs render correctly for themes that use session-state specifiers.

---

## FINDING 3 — the renderer double-swap is single-pass (NO recursion risk)

**Live-verified.** `${var//pat/rep}` (global replace) does NOT re-scan the replacement.
Tested the pathological case where the replacement IS a placeholder:

```
ws_tpl='__lp_tab__'; esc_wname='__lp_sentinel__'
ws_seg="${ws_tpl//__lp_tab__/$esc_wname}"      # -> '__lp_sentinel__'
ws_seg="${ws_seg//__lp_sentinel__/REPLACED}"   # -> 'REPLACED'
```
Single-pass confirmed: the second swap sees the FIRST swap's output but does not recurse
into it. The existing comment at renderer.sh lines 128-129 documents this property for
`__lp_tab__`; it holds identically for `__lp_sentinel__`. No recursion / infinite-loop risk.

A realistic template `'#[fg=red]__lp_tab__#[default] :: __lp_sentinel__'` with
`esc_wname='##dev'` → `'#[fg=red]##dev#[default] :: ##dev'` (both placeholders → the
candidate name). Both placeholders map to the SAME `$esc_wname` (the candidate's name).

---

## FINDING 4 — the pre-clean `kill-session` is idempotent and guarded

**Live-verified.** `tmux kill-session -t "__lp_sentinel__"`:
- On an EXISTING sentinel (stray from a crashed prior run) → succeeds (rc=0), removes it.
- On an ABSENT sentinel (normal case) → fails (rc=1, "can't kill session"), silently
  suppressed by `2>/dev/null || true`.

So `tmux kill-session -t "__lp_sentinel__" 2>/dev/null || true` placed BEFORE
`new-session -s "__lp_sentinel__"` reliably clears any stray sentinel and never errors.
This replaces the old unique-name collision-avoidance (PID+epoch) with explicit pre-cleaning.

---

## FINDING 5 — the modal `@livepicker-mode` guard prevents concurrent sentinel collisions

**Live-verified** (grep). `activate_main` line 124: `if [ "$(get_state "$STATE_MODE" "off")" = "on" ]; then ... return ...`
— a second activation while one is active is silently ignored. Since
`_lp_resolve_tab_templates` runs inside `activate_main` (line 409) and sets MODE on at
line 410, TWO concurrent `_lp_resolve_tab_templates` calls CANNOT happen (the second
activation bails at line 124 before reaching the sentinel creation). So the fixed
`__lp_sentinel__` name cannot collide between two picker instances running simultaneously.
The sentinel also lives only for the duration of `_lp_resolve_tab_templates` (created at
line 77, killed at line 98) — a few milliseconds.

---

## FINDING 6 — RESIDUAL: a user session literally named `__lp_sentinel__` would be destroyed by the pre-clean

**The one real trade-off of the fixed name.** The pre-clean
`tmux kill-session -t "__lp_sentinel__"` destroys ANY session with that exact name —
including a hypothetical user session. The old `__lp_sent_$$_$(date +%s)` name was
collision-FREE (no user has a session with that exact PID+epoch). The fixed name is
REQUIRED (the renderer needs a known placeholder to swap), so this residual is accepted.

**Mitigations in place:** (a) `__lp_sentinel__` is an internal-looking name (double-
underscore prefix + suffix) that no real user would choose; (b) the modal guard prevents
concurrent-picker collisions (FINDING 5); (c) the pre-clean handles crashed-prior-run
strays (FINDING 4). The probability of a user session named exactly `__lp_sentinel__` is
vanishing. **Document this in the PRP's Known Gotchas.** (An alternative — unique name +
a state key the renderer reads — was rejected by the contract as more complex; the
fixed-name approach is the chosen design.)

---

## FINDING 7 — `#{session_id}` is NOT covered (residual, out of scope)

**Live-verified.** `#{session_id}` against the sentinel resolves to `$4` (tmux's internal
`$N` session id), NOT to a stable placeholder. The contract's scope is `#{session_name}` /
`#S` only (the specifiers a theme would realistically put in window-status-format to show
a name). `#{session_id}` is vanishingly rare in user themes and resolves to a tmux
internal handle that is not name-swappable. **Out of scope** — document as a known
residual. (If a theme uses `#{session_id}`, it renders `$4`-style; the unexpanded-`#{`
guard does not catch it, same class as the original bug but for a far rarer specifier.)

---

## FINDING 8 — DISJOINT from the parallel P1.M2.T1.S1 (no file conflict)

**Verified by reading both the parallel PRP + the working tree.** P1.M2.T1.S1 (Issue 4,
in-flight) edits `scripts/preview.sh` ONLY (adds GUARD 3 + an idempotent pre-link check).
This task edits `scripts/livepicker.sh` (the sentinel name) + `scripts/renderer.sh` (the
second swap). **No shared file → no edit collision.** No other in-flight task touches
livepicker.sh or renderer.sh (P1.M2.T3.S1 is README.md only).

---

## FINDING 9 — Mode A: NO committed test (matches the parallel task + the contract tag)

The contract tags this DOCS work **[Mode A]** (inline-comment updates only), and the
parallel P1.M2.T1.S1 chose "no committed test (Mode A)" explicitly. The bugfix plan's
Minor issues are consistently Mode A. `tests/test_appearance.sh` EXISTS but is owned by
the PARENT plan (002) P1.M3.T2 — touching it risks colliding with that milestone. So:
**validate via a throwaway smoke (then delete it)**, do NOT commit a test file. The smoke
proves both halves: (A) the resolution bakes `__lp_sentinel__` (not `__lp_sent_PID_EPOCH`);
(B) the renderer swaps it → real names.

---

## FINDING 10 — livepicker.sh's entry point runs activate on source; the smoke must NOT source it

**Live-verified.** livepicker.sh ends with `activate_main "$@" || exit 1; exit 0`. So
SOURCING livepicker.sh runs `activate_main` immediately (it needs an attached client +
does switch-client/display-message). The throwaway smoke therefore tests the two halves
WITHOUT sourcing livepicker.sh:
- (A) Replicate the sentinel resolution inline (create `__lp_sentinel__` + `__lp_tab__`,
  run `display-message '#{session_name}'`, assert → `__lp_sentinel__`).
- (B) Seed `@livepicker-tab-current-tmpl` / `-inactive-tmpl` with a template containing
  `__lp_sentinel__`, set `@livepicker-tab-style window-status`, seed the list, run
  `scripts/renderer.sh`, assert the output contains the real names and NOT `__lp_sentinel__`.

This mirrors how the renderer actually consumes the cached templates (reads from state).

---

## FINDING 11 — both placeholders map to the SAME candidate name (acceptable for both #W and #S themes)

**Live-verified** (FINDING 3 realistic template). In the picker, each "tab" represents ONE
candidate (a session in session mode, a session:window in window mode). The candidate's
display name is the same whether the theme used `#W` (window name) or `#S`/`#{session_name}`
(session name) — both get `$esc_wname`. A theme that uses BOTH (`#S:#W`) renders the name
twice (`name:name`) — slightly redundant but correct and never wrong. The alternative
(resolving `#W` to the candidate's actual active-window name) would require a per-candidate
`display-message` round-trip in the renderer, defeating the cache-once optimization. The
findings doc (§Issue 5) and the contract accept this: "if the theme has BOTH #W and #S,
both placeholders get swapped."

---

## FINDING 12 — exact CURRENT edit anchors (content, not line numbers)

**livepicker.sh** (the sentinel-creation block — `_lp_resolve_tab_templates`, currently
lines 72-77):
```
	# (b) Create a unique hidden 2-window session (anchor + sentinel). CRITICAL (FINDING 1):
	# `new-window -d -t "$sent_sess"` (bare) FAILS under base-index=1/renumber ("index in
	# use"); the TRAILING-COLON form `-t "$sent_sess:"` picks a free slot. Force-select the
	# anchor so __lp_tab__ is NON-active -> clean window-state specifiers. Unique name
	# (PID+epoch) avoids a double-activation collision.
	sent_sess="__lp_sent_$$_$(date +%s)"
	if ! tmux new-session -d -s "$sent_sess" -n __lp_anchor__ 2>/dev/null; then
```
Edit: update the comment (no longer "unique name"; now "fixed stable placeholder") + add a
pre-clean `kill-session` + change `sent_sess` to `"__lp_sentinel__"`.

**renderer.sh** (the swap block — window-status path, currently lines 128-130):
```
			# literal swap: ${var//pat/rep} does not re-scan the replacement, so a name
			# equal to __lp_tab__ cannot corrupt or recurse.
			ws_seg="${ws_tpl//__lp_tab__/$esc_wname}"
```
Edit: add a second swap line `ws_seg="${ws_seg//__lp_sentinel__/$esc_wname}"` after line 130,
+ update the comment to mention the session-name placeholder.

**Stale-line-number warning:** the contract cites "line ~76" (livepicker) and "line ~130"
(renderer) — these ARE currently accurate, but anchor on CONTENT (the `sent_sess=...`
assignment and the `ws_seg="${ws_tpl//__lp_tab__...}` line) to be safe against drift.
