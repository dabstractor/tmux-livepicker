# Sentinel-window format resolution — empirical grounding (tmux 3.6b)

> Verified LIVE on 2026-07-06 against isolated `-L` sockets (which source the
> user's tubular config, so `base-index=1`, `renumber-windows=on`, and the real
> tubular `window-status-*` formats are all in effect — this IS the target env).
> The `external_tmux_behavior.md` researcher had NO shell; every claim there was
> marked `[VERIFY]`. This file turns the load-bearing ones into PROVEN facts and
> corrects TWO contract errors that would have broken the implementation.

## Environment

| Tool | Version |
|---|---|
| tmux | **3.6b** |
| bash | **5.3.15(1)-release** |
| shellcheck | **0.11.0** |
| isolated-socket config | sources user tmux.conf → `base-index=1`, `renumber-windows=on`, tubular formats |

## T1.S1 status: LANDED (the foundation exists)

Verified in the working tree (will be present when this task begins):
- `scripts/options.sh:45` — `opt_tab_style() { get_opt "@livepicker-tab-style" "plain"; }` ✓
- `scripts/state.sh:46-47` — `STATE_TAB_CURRENT_TMPL`/`STATE_TAB_INACTIVE_TMPL` ✓
- `scripts/state.sh:61` — both in `_STATE_RUNTIME_KEYS` (cleared by `clear_all_state`) ✓

---

## FINDING 1 — ⚠️ CONTRACT CORRECTION: `new-window -d -t "$SENT"` FAILS under tubular

The contract (and `external_tmux_behavior.md` Q3) specify:
```
tmux new-session -d -s "$sent_sess" -n __lp_anchor__
tmux new-window  -d -t "$sent_sess" -n __lp_tab__
```
The SECOND line **FAILS** on the target environment:
```
create window failed: index 1 in use
```

**Root cause:** the isolated (and live) socket sources the user config → `base-index=1`
+ `renumber-windows=on`. `new-session` creates the anchor at index 1. `new-window -d -t
"$sent_sess"` (bare target, no trailing colon) then tries to create at index 1 **again**
→ collision → failure. The result was catastrophic: only ONE window existed (the anchor),
it was ACTIVE → `#F = *` (dirty) — exactly the failure the 2-window pattern exists to avoid.

**The fix (PROVEN):**
```bash
tmux new-session -d -s "$sent_sess" -n __lp_anchor__
tmux new-window  -d -t "$sent_sess:" -n __lp_tab__    # TRAILING COLON -> tmux picks a free index
tmux select-window -t "$sent_sess:__lp_anchor__" 2>/dev/null || true   # FORCE anchor active
```
- The trailing colon (`-t "$sent_sess:"`) means "target = the session" and tmux appends at
  the next free index (2). **Verified: SUCCEEDS** where the bare form failed.
- `select-window -t "$sent_sess:__lp_anchor__"` deterministically makes the ANCHOR the
  active window, guaranteeing `__lp_tab__` is non-active → clean `#F`. (With `-d` the new
  window is already non-active, but the explicit select is belt-braces against any config
  that auto-selects.)
- Result: `1:__lp_anchor__ active=1`, `2:__lp_tab__ active=0 flags=<clean>`. ✓

Also verified: `new-window -d -a -t "$SENT"` (the `-a` "after" flag) succeeds too, but the
trailing-colon form is simpler and target-by-name (`-t "$sent_sess:__lp_anchor__"`) is
robust to renumbering. **Use the trailing-colon + force-select-anchor form.**

---

## FINDING 2 — `display-message -p` does NOT escape `#`; resolved templates are clean

- `display-message -p 'a#b'` → `a#b` (NO doubling). So display-message -p output is raw.
- Resolving the REAL tubular `window-status-current-format` value against the clean
  sentinel produces a **fully-expanded** template:
  ```
  cur_tpl = #[fg=#7aa89f,bg=#181822,nobold,nounderscore,noitalics]#[fg=#181822,bg=#7aa89f] __lp_tab__ #[fg=#7aa89f,bg=#181822]
  ```
  - Every `#{E:@tubular_*}` → concrete hex color (`#7aa89f`, `#181822`).
  - `#W` → `__lp_tab__` (the placeholder, ready for the renderer to swap → each session name).
  - **No raw `#{` remains** (`grep -c '#{'` = 0). ✓
  - The `__lp_tab__` placeholder is present (`grep -c __lp_tab__` = 1). ✓
- **The `##` in `#F`**: when a format explicitly includes `#F`/`#{window_flags}`,
  display-message AND list-windows BOTH report `##` for the clean sentinel (a tmux
  window-flags representation quirk). This is HARMLESS for the target: **tubular's
  format contains NO `#F`** (only `#W`), so the resolved tubular template has zero flag
  artifact. Themes that DO use `#F` get the flag field baked in (which is their design).
  No special stripping is needed; the renderer (T3) only swaps `__lp_tab__`.

---

## FINDING 3 — ⚠️ CONTRACT CORRECTION: `show-options -gwv` NEVER returns empty for window-status-*

The contract step (a) says: "If EITHER [format value] is empty, leave both cache keys
empty and return 0 (plain fallback)." **This check is effectively dead code** for these
options: tmux ALWAYS materializes a default. Verified:
```
set-option -gwu window-status-format          # unset it
show-options  -gwv window-status-format
  → "#I:#W#{?window_flags,#{window_flags}, }"   # the tmux DEFAULT, NOT empty
```
So `cur_fmt`/`reg_fmt` are NEVER empty. Implications:
- The empty-check in step (a) is **defensive only** (harmless to keep; never fires here).
- The REAL fallback trigger is step (e): "still contains an unexpanded `#{`".
- If the format is the tmux default (user/theme didn't override it), resolving it still
  yields a valid template (`2:__lp_tab__`-style) → the picker shows default-style tabs.
  That is consistent with §17 ("reuse the window-status format"); it is NOT a failure.

Use `show-options -gwv` (global-**window**, value-only). Verified: `-gv` (session-global)
also happens to return the same value for these options, but `-gwv` is the semantically
correct scope (these are window options). The contract's `-gwv` is right.

---

## FINDING 4 — The malformed-theme guard (step e) fires correctly for the tubular-misuse case

Step (e) blanks the cache when a resolved template "still contains an unexpanded `#{`".
Verified WHEN it fires and when it doesn't:
- **FIRES** (correctly): a theme that nests a format in a user-option WITHOUT `E:` —
  `window-status-format = #[fg=#{@lp_inner}]#W` where `@lp_inner` is itself a format.
  `#{@lp_inner}` (no `E:`) returns the RAW value → resolved output contains `#{` →
  `grep -c '#{'` = 1 → guard blanks cache → plain fallback. ✓ (This is exactly the
  tubular-style misuse §16 warns about.)
- **Does NOT fire** (correctly): a plain unset `#{@no_E_modifier}` resolves to EMPTY
  (the option is unset) → no `#{` → `#[fg=]` (empty color, valid template). The theme
  authored an empty color; that is its choice, not a resolution failure. Acceptable.

So the `#{` check is the correct, precise malformed-theme detector. Use a `case` glob:
`case "$tpl" in *"#{"*) tpl="" ;; esac` (`#` is literal in a bash case pattern; the
quotes make `#{` literal, `*` are the wildcards).

---

## FINDING 5 — set-empty vs unset contract CONFIRMED (the T1.S1 downstream requirement)

T1.S1's PRP requires the WRITER (this task) to `set_state ""` (real set-empty =
`tmux set-option -g @x ""`) on failure, NOT leave the key unset, so the renderer's
`tmux_is_set` probe can distinguish "resolved empty" from "not resolved yet". Verified:
```
set-option -g "@livepicker-tab-current-tmpl" ""   → rc=0
show-options -g "@livepicker-tab-current-tmpl"    → rc=0  (SET, even though empty)
set-option -gu "@livepicker-tab-current-tmpl"     → rc=0
show-options -g "@livepicker-tab-current-tmpl"    → rc=1  (UNSET)
```
→ Every fallback path in the helper MUST `set_state "$STATE_TAB_*" ""` (set-empty).
`get_state`/`get_opt` CANNOT make this distinction (both return `""`); only `tmux_is_set`
can. (Documented for the renderer P1.M1.T3; this task is the writer that makes it true.)

---

## FINDING 6 — Insertion point + helper scope (livepicker.sh)

- `activate_main()` is at line 43; `CURRENT_DIR` set at line 35; options/utils/state
  sourced at lines 37/39/41 → `opt_tab_style`, `set_state`, `STATE_TAB_*` all in scope.
- livepicker.sh does NOT source filter.sh (not needed — the helper reads format OPTIONS,
  not the session list).
- **Insertion point** (codebase_state §3, confirmed by grep): between the end of the
  first-preview `if` block (line ~326, `if ! "$CURRENT_DIR/preview.sh" "$orig_session"; then ... fi`)
  and `set_state "$STATE_MODE" "on"` (line 327). Rationale: a sentinel failure can still
  roll back via the existing L2-fix pattern (restore cancel) because MODE is not yet armed.
  Anchor the edit by CONTENT (the `set_state "$STATE_MODE" "on"` line + the preceding `fi`),
  not line number.
- The helper `_lp_resolve_tab_templates()` is defined BEFORE `activate_main()` (matching
  the `_confirm_land_on_session` convention in input-handler.sh; livepicker.sh currently
  has activate_main as its only function — add the helper just above it).

---

## FINDING 7 — Best-effort / never-block guarantee (PRD §17 fallback, §16 fragility)

Every tmux call in the helper is best-effort (`2>/dev/null || true` or the `|| { fallback }`
form). A failure at ANY step → set-empty both cache keys → continue activation. The picker
MUST NEVER fail to open over a styling miss. The sentinel session is ALWAYS killed (success
path step d; failure paths kill before returning). The unique session name
(`__lp_sent_$$_$(date +%s)`) avoids a double-activation collision.

---

## Resolved tubular templates (the proof the mechanism works on the real target)

Against a clean 2-window sentinel on the config-sourcing socket:
```
cur_tpl (active tab) = #[fg=#7aa89f,bg=#181822,nobold,nounderscore,noitalics]#[fg=#181822,bg=#7aa89f] __lp_tab__ #[fg=#7aa89f,bg=#181822]
reg_tpl (inactive)   = #[default] __lp_tab__ #[fg=#54546d] ...
```
Both: fully expanded (no `#{`), `__lp_tab__` placeholder present, concrete `#[...]` styles.
The renderer (T3) swaps `__lp_tab__` → each session name and emits these; the `#[...]`
styling renders correctly from the `#()` status command (Q2 asymmetry: `#[...]` live,
`#{...}` dead — which is exactly why pre-resolution is necessary and sufficient).
