# Research: client_width capture + client-resized hook save/restore (P1.M3.T1.S1)

> Implementation task (3 script edits + 1 input action + doc comments). This file
> captures the verified activate/restore insertion points, the hook save/restore
> pattern (§P4), the empirical byte-identity proof (the load-bearing gate), and the
> exact dependency signatures — everything needed for a one-pass implementation.

## 1. Dependency inputs — ALL LANDED (grep-confirmed 2026-07-07)

| Dependency | Location | Status |
|---|---|---|
| `STATE_CLIENT_WIDTH` (`@livepicker-client-width`) | state.sh:51 | ✅ in `_STATE_RUNTIME_KEYS` (line 66) → auto-cleared on exit |
| `ORIG_CLIENT_RESIZED_HOOK` (`@livepicker-orig-client-resized`) | state.sh:61 | ✅ auto-cleared by `clear_all_state`'s `grep '@livepicker-orig-'` |
| `lp_client_format FMT` | utils.sh:172 | ✅ resolves `#{...}` against the invoking client; falls back to context-free on detached/test edge |
| `tmux_get_hook NAME` | utils.sh:74 | ✅ = `tmux show-hooks -g "$1"`; full multi-line `name[N] <cmd>` output; bare `name` when cleared |
| `tmux_clear_hook NAME` | utils.sh:185 | ✅ = `tmux set-hook -gu "$1"` (clears EVERY index) |
| `opt_suppress_window_hook` | options.sh | ✅ (gates session-window-changed; client-resized is NOT gated — always installed) |

**consumer already wired**: renderer.sh:195 reads `width="$(get_state "$STATE_CLIENT_WIDTH" "0")"`; width=0 → degraded full-list render (no windowing). Capturing a real width here ACTIVATES the §19 viewport. Until this task lands, width is always 0.

## 2. The exact insertion points (verified against the live files)

### livepicker.sh activate_main — INSERT between T2 and T3
- T2 ends at: `set_state "$STATE_INDEX" "$idx"` (line 214).
- T3 starts at: `# --- T3 (P1.M4.T3.S1): grow status bar + install renderer ---` (line 215).
- **Insert the new "client-width cache + resize hook" block between them.** This is
  AFTER the list is built (T2 needs the client for window-mode token resolution via
  `lp_client_format`) and BEFORE the renderer is installed (T3) so the first render
  has a valid width. The capture needs the attached client (activate requires one).

### input-handler.sh — ADD a `refresh-width)` case branch
- The case dispatch (input_main, line 187) has branches: type(193)/backspace(227)/
  next-session(256)/prev-session(289)/confirm(312)/cancel(419), then a `*)` catch-all
  (line ~462) → `return 0` → `;;` → `esac`.
- **Insert `refresh-width)` immediately before the `*)` catch-all.** It re-caches
  client_width (via `lp_client_format`) + `refresh-client -S` so the renderer redraws
  with the new width. No argv[2], no preview work, no filter/index change.
- The locals line (188) needs NO change (the branch inlines `set_state`/`lp_client_format`).
- Update the header comment (line 13) to list `refresh-width` in the action enum.

### restore.sh STEP 4 — ADD the client-resized restore after session-window-changed
- STEP 4 (line 131) restores status/status-format/key-table/renumber-windows/**session-
  window-changed hook** (the index-preserving loop at lines ~166-180, GATED on
  `opt_suppress_window_hook`).
- The session-window-changed block ends with its `fi` + the `# When
  @livepicker-suppress-window-hook is "off"...` comment, then `# --- STEP 5 ...`.
- **Insert the client-resized restore between the session-window-changed comment and
  `# --- STEP 5`.** Mirror the loop but (a) NOT gated, (b) CLEAR FIRST (see §3).
- Update the STEP 4 header (line 131-132) to add "client-resized hook" to the enumeration.

## 3. The hook save/restore pattern (codebase_patterns.md §P4) + the ONE difference

`session-window-changed` and `client-resized` use the IDENTICAL shape (§P4):
1. Save: `tmux_get_hook <name>` → full multi-line output → store in `ORIG_*`.
2. Clear: `tmux_clear_hook <name>` (= `set-hook -gu`) clears every index.
3. Restore: parse each `name[N] <cmd>` line; replay via `set-hook -g "name[$N]" "$cmd"`
   preserving index + `-b` + verbatim command. Skip bare `name`/blank lines.

### THE ONE DIFFERENCE (load-bearing): restore for client-resized MUST CLEAR FIRST

- **session-window-changed**: activate SUPPRESSES (clears; installs nothing). At
  restore, the live hook is empty → replaying the saved lines restores them cleanly;
  if the user had none, the loop skips → "stays cleared" (correct). NO clear at restore.
- **client-resized**: activate INSTALLS ours at [0] (after clearing). At restore, ours
  is live at [0]. If the user had NO hook (saved = bare `client-resized`), replaying
  skips → ours at [0] would LEAK. So restore MUST `tmux_clear_hook client-resized`
  FIRST (remove ours), THEN replay the saved lines (restore the user's exact prior
  state, or leave it cleared if they had none).

This is the single subtlety. The empirical proof (§4) confirms clear-first-at-restore
yields byte-identical show-hooks for BOTH the unset and the set prior state.

## 4. Empirical byte-identity proof (load-bearing — verified on tmux 3.6b isolated socket)

The committed `test_restore_cancel_options_hooks_exact` (test_restore.sh:44) diffs
`show-hooks -g | sort` before activate vs after cancel. This task's cycle MUST be byte-
identical. Verified live:

**UNSET case (the test-env default — no prior client-resized hook):**
- baseline: `client-resized` (bare — show-hooks ALWAYS lists it, even when unset).
- save `tmux_get_hook client-resized` → `client-resized` (bare).
- clear `set-hook -gu` + install ours `set-hook -g client-resized "run-shell '...'"` →
  `client-resized[0] run-shell "..."`.
- restore: clear `set-hook -gu` → `client-resized` (bare); replay saved (bare → skip).
- after: `client-resized` (bare). **== baseline. BYTE-IDENTICAL. ✅**

**SET case (user had `client-resized[0] run-shell '/user/orig.sh'`):**
- save → `client-resized[0] run-shell "/user/orig.sh"`; clear + install ours; restore:
  clear + replay [0] → `client-resized[0] run-shell "/user/orig.sh"`. **BYTE-IDENTICAL. ✅**

Other verified facts:
- The install form `tmux set-hook -g client-resized "run-shell '$CURRENT_DIR/input-handler.sh refresh-width'"`
  (single quotes inside double quotes) parses and installs as `client-resized[0] run-shell "..."`.
- `display-message -p '#{client_width}'` → `80` with an attached client, empty without
  (lp_client_format resolves client-awarely + falls back to context-free).

## 5. Why the existing suite stays green (no committed test here — P1.M4.T3 owns it)

- **test_restore_cancel_options_hooks_exact**: the byte-identity proof (§4) → PASS.
- **test_appearance.sh**: seeds state + runs `renderer.sh` directly (never activates);
  STATE_CLIENT_WIDTH stays unset → width=0 → unchanged output. PASS.
- **test_functional.sh**: activates via livepicker.sh (now captures a real width) +
  runs renderer.sh. With a real width (~120) the viewport is wide → all tabs visible,
  no indicators. Its assertions are `assert_contains` (substring), not exact-match →
  still hold. PASS.
- **test_responsiveness.sh / test_preview.sh / etc.**: unaffected (no client-resized
  assertions; restore is byte-identical).
- Committed client-width-cache tests are P1.M4.T3.S1 (planned). Validate here via the
  full suite (must stay 44/44) + a throwaway smoke (capture/refresh/byte-identity).

## 6. Design summary (the 4 edits)

1. **livepicker.sh** (T2→T3 insert): capture STATE_CLIENT_WIDTH via lp_client_format;
   save prior client-resized hook (tmux_get_hook → ORIG_CLIENT_RESIZED_HOOK); clear
   (tmux_clear_hook); install ours (`set-hook -g client-resized "run-shell '$CURRENT_DIR/input-handler.sh refresh-width'"`).
2. **input-handler.sh** (case, before `*)`): `refresh-width)` → re-cache width + refresh.
3. **restore.sh** (STEP 4, after session-window-changed block): `tmux_clear_hook client-resized`
   THEN replay saved `client-resized[N] <cmd>` lines (NOT gated; clear-first is the
   one difference from session-window-changed).
4. **Doc comments**: restore STEP 4 header + input-handler line-13 action enum + the
   new blocks' inline comments (reference PRD §9/§10 §3.35).
