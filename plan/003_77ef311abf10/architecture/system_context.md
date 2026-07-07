# System Context: tmux-livepicker delta 003

> Ground truth for the PRP agents building the §19/§20/§21/§22 delta on top of the
> shipped, 44/44-green implementation (plan-001 + rev-002 + bugfix-001/002).

## 1. What this project IS

A tmux plugin (`tmux-livepicker`) — a modal status-line session/window picker that
previews candidates live via `link-window`, without switching the client's session
(Invariant A, PRD §4). It lives at `/home/dustin/.config/tmux/plugins/tmux-livepicker`.

**Environment:** tmux **3.6b** (confirmed live). Bash. The plugin is pure bash +
tmux primitives; no external runtime deps except optional `zoxide`.

**This is a DELTA, not a greenfield build.** The full plugin already works
(activate → save → status grow → key-table → preview → input/confirm/cancel →
restore, all shipped and tested). Delta 003 adds **four features** on top without
rebuilding anything that works:

| Feature | PRD § | New files | Touches |
|---|---|---|---|
| Status-line layout (query bar + scroll viewport + overflow) | §19 | `scripts/layout.sh` | renderer, input-handler |
| Fuzzy ranking (subsequence + score) | §20 | `scripts/rank.sh` | renderer, input-handler, session-mgmt (replaces `filter.sh`) |
| Session management (rename / delete) | §21 | `scripts/session-mgmt.sh` | input-handler, livepicker (binding step 5), options, state |
| Preview sizing (clip not reflow) | §22 | — | livepicker, restore, options, state |

## 2. Invariants that still hold (do NOT break)

- **Invariant A (§4):** browsing never fires `client-session-changed`. All new work
  (rank/scroll/mgmt/clip) operates inside the current session. `rename-session` /
  `kill-session` mutate OTHER sessions, not the client's.
- **Deferred-preview supersede (§18):** the existing `_lp_preview_follow` /
  `_lp_fire_preview` / `STATE_PREVIEW_SEQ` 3-guard machinery in `preview.sh` +
  `input-handler.sh` is the single preview entry point. New input paths (scroll,
  rename, delete re-sync) route through it. No new inline `link-window`.
- **Save/restore contract (§9):** every new saved value (`window-size`,
  `client-resized` hook) pairs with a restore step; every new runtime key
  (`@livepicker-scroll`, `@livepicker-client-width`) is added to
  `_STATE_RUNTIME_KEYS` so `clear_all_state` tears it down.
- **Single source of truth for list order:** today `filter.sh::lp_build_filtered`
  is shared by renderer + input-handler. `rank.sh::lp_rank` preserves that contract
  (renderer + input-handler + session-mgmt all source `rank.sh`).

## 3. Key facts about the shipped code (confirmed by reading the source)

- **State contract** (`scripts/state.sh`): `STATE_*` runtime constants, `ORIG_*`
  saved-state constants, `_STATE_RUNTIME_KEYS` clear-list, `state_status_format_save`
  /`_restore`, `clear_all_state`. New keys follow the `readonly STATE_X="@livepicker-x"`
  pattern + append to `_STATE_RUNTIME_KEYS` (MANDATORY — else they leak across
  picker sessions).
- **Option accessors** (`scripts/options.sh`): one `opt_<name>()` per option, each a
  one-liner `get_opt "@livepicker-<suffix>" "<default>"`. **`opt_show_count()`
  currently EXISTS and must be REMOVED** (§19 drops the index/total count entirely).
- **The filter being superseded** (`scripts/filter.sh::lp_build_filtered`):
  case-insensitive **substring** filter, 40 lines. 6 call sites: renderer ws-path +
  plain-path, input-handler `_lp_sync_preview_to_top_match` / `next-session` /
  `prev-session` / `confirm`. `rank.sh::lp_rank` must be a drop-in
  (`mapfile -t ranked < <(lp_rank "$LIST" "$FILTER")`) and byte-identical for an
  empty filter (order preserved) so existing tests stay green.
- **Renderer** (`scripts/renderer.sh::render()`): emits ONE line (no trailing
  newline), `#[default]` after every segment, reads list via process substitution.
  Has BOTH a plain path and a §17 window-status early-return. The `SHOW_COUNT`
  suffix logic (`query> FILTER [i/N]`) appears in plain + ws + no-match paths and is
  removed entirely.
- **Input handler** (`scripts/input-handler.sh`): `input_main()` dispatches
  type/backspace/next-session/prev-session/confirm/cancel. Uses `_lp_preview_follow`
  for deferred preview, `_lp_fire_preview` for the seq-guarded `-b` launch,
  `_lp_sync_preview_to_top_match` for the type/backspace/cancel-clear top-match
  re-sync. **No `rename`/`delete` actions yet** (P2 adds them).
- **Activate** (`scripts/livepicker.sh::activate_main`): STEPs 1-5 (guard, save,
  list, status grow, key-table+hook, first preview+mode-on). Key bindings are bound
  in step (2) of T4: typing a-z A-Z 0-9 -_. /, then backspace/confirm/cancel, then
  nav. **No binding step 5 (rename/delete) yet.** Status grow uses the normalized
  case (on→2, etc.).
- **Restore** (`scripts/restore.sh::restore_main`): 6 steps. STEP 4 restores
  status-format/status/key-table/renumber/session-window-changed-hook. New restores
  (window-size, client-resized hook) go in STEP 4.
- **Preview** (`scripts/preview.sh::preview_main`): link-window core with 3-guard
  seq supersede, idempotent pre-link check, duplicate guard, capture-pane fallback.
  Self-session guard. Does NOT touch window-size.
- **Utils** (`scripts/utils.sh`): `tmux_get_opt/set_opt/unset_opt`, `tmux_save_opt`,
  `tmux_get_hook`/`tmux_clear_hook` (full show-hooks verbatim + set-hook -gu),
  `lp_filter_harmful_bindings`, `lp_resolve_client`/`lp_client_format`
  (client-aware display-message).
- **Test harness** (`tests/`): `setup_socket.sh` (isolated `-L` socket, PATH shim,
  `attach_test_client` via `script` pty), `helpers.sh` (`setup_test` pins
  `@livepicker-preview-defer off` for determinism, `assert_eq`/`assert_contains`),
  `run.sh` discovery. **Renderer tests need no client** (seed state → run
  renderer.sh → assert). Nav/scroll/preview tests need `attach_test_client`.

## 4. Cross-cutting constraints (apply everywhere)

- `set -u` is house style; `set -e` is FORBIDDEN in renderer/handler (transient
  tmux non-zero must not abort). Every option read via `get_opt`/`opt_*`; every
  state read via `get_state` with a default. No bare `tmux show-option` that can
  crash under `set -u`.
- The renderer runs on EVERY `refresh-client -S` (the typing path). It MUST stay
  PURE + FAST (<50ms): option reads + pure-bash rank/measure only. **No tmux
  round-trips on the render path** (the §18 budget). The width comes from the
  cached `@livepicker-client-width`, not `display-message`.
- tmux `#()` stdout is NOT re-parsed for `#{…}`; only `#[…]` styles apply (verified
  plan/002 Q2). So the query text must have every `#` doubled (`##`) to render
  literally, and theme formats must be pre-resolved (the existing sentinel step).
- Address windows by **@id**, never index (`renumber-windows` is on; indices churn).
