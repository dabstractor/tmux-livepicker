# Gap Analysis: Two-Axis Navigation (PRD §8 vs Current Code)

## Summary

The codebase implements **only the session axis**. The **window axis is entirely
absent** — no keys, no input-handler actions, no cursor state, no confirm-window
commit, and `preview.sh` always links the candidate's *active* window.

| Axis | PRD requires | Code has | Status |
|------|-------------|----------|--------|
| Session | `@livepicker-session-next-keys`/-prev-keys + arrows | `opt_next_key`/`opt_prev_key` + `opt_nav_next_keys`/`-prev-keys` → `next-session`/`prev-session` | Partial (works, wrong options + wrong defaults) |
| Window | `@livepicker-window-next-keys`/-prev-keys → `next-window`/`prev-window` | C-M-Tab/C-M-BTab **repurposed to SESSION nav** | Absent |
| Window cursor state | `@livepicker-cand-win-session`/-list/-cursor, `@livepicker-preview-win-id` | none | Absent |
| Confirm → window | `select-window -t "=$S:$W"` from window-cursor | session-mode confirm only `switch-client`s | Absent |
| Preview specific window | `preview.sh <session> [window-id]` | always the active window; `$2` is the supersede-seq | Absent |

## Gap (a): Key model

Current `options.sh:30-33`:
- `opt_next_key` → `@livepicker-next-key` default `C-M-Tab` (session nav)
- `opt_prev_key` → `@livepicker-prev-key` default `C-M-BTab` (session nav)
- `opt_nav_next_keys` → `@livepicker-nav-next-keys` default `Down` (session nav)
- `opt_nav_prev_keys` → `@livepicker-nav-prev-keys` default `Up` (session nav)

All four route to session navigation. PRD requires four two-axis options with
discovered defaults. See P1.M1.T1 for the replacement.

## Gap (b): Input-handler actions

`input-handler.sh` dispatches: `type | backspace | next-session | prev-session |
confirm | cancel | rename | delete | refresh-width`. There is NO `next-window`/
`prev-window` case branch. Window-nav keys (C-M-Tab) are bound to `next-session`
at `livepicker.sh:421-429`.

## Gap (c): Window-cursor state

`state.sh:40-68` defines 13 runtime keys. None of `@livepicker-cand-win-session`,
`-list`, `-cursor`, or `@livepicker-preview-win-id` exist. They are not in
`_STATE_RUNTIME_KEYS` (line 68) so would leak past teardown.

## Gap (d): Confirm lands on session AND window

`input-handler.sh:398-495` confirm branch. Session mode delegates to
`_confirm_land_on_session` (line 81-112) which does: unlink driver preview →
switch-client → restore keep. NO `select-window` for the chosen window. PRD §6
requires `select-window -t "=$S:$W"` to commit the window choice.

## Gap (e): Preview shows specific window

`preview.sh:80` signature is `preview_main() { local S="${1:-}" expected_seq="${2:-}"`.
`$2` is the supersede-seq, not a window-id. At line 166, src_id is always resolved
via `list-windows -f '#{window_active}'`. No path accepts a flipped-to window.

## Files needing change

1. `scripts/options.sh:30-33` — replace 4 old accessors with 4 two-axis (P1.M1.T1)
2. `scripts/utils.sh` — add `lp_discover_axis_keys` (P1.M1.T2)
3. `scripts/livepicker.sh:336-446` — rework T4 to bind two axes (P1.M2.T1)
4. `scripts/state.sh:40-68` — add 4 window-cursor keys (P2.M1.T1)
5. `scripts/preview.sh:80-166` — accept chosen window-id (P2.M1.T2)
6. `scripts/input-handler.sh` — add next-window/prev-window + cursor resets + confirm window commit (P2.M1.T3, P2.M2.T1)
7. `scripts/restore.sh:97-106` — keep skips STEP-2 (P2.M2.T2)
