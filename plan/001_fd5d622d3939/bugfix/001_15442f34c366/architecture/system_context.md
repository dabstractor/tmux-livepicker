# System Context — Bugfix 001 (Adversarial QA Remediation)

## Project

**tmux-livepicker** — a modal status-line session/window picker tmux plugin.
Location: `/home/dustin/.config/tmux/plugins/tmux-livepicker`

## Codebase Architecture (verified during research)

The plugin is a set of POSIX bash scripts orchestrated via `tmux run-shell`.
Each script is its OWN process under run-shell → each sources its own trio of
libraries (`options.sh`, `utils.sh`, `state.sh`).

### Script inventory (all in `scripts/`)

| Script            | Role                                                            | Key functions                                  |
|-------------------|-----------------------------------------------------------------|------------------------------------------------|
| `livepicker.sh`   | Activate: snapshot state, grow status, bind key table, seed list| `livepicker_main`                              |
| `input-handler.sh`| Input dispatcher: type/backspace/next/prev/confirm/cancel       | `input_main`, `_confirm_land_on_session`       |
| `renderer.sh`     | `#()` status-line renderer (PURE, read-only)                    | `render`                                       |
| `preview.sh`      | Live link-window preview core                                   | `preview_main`, `preview_fallback`             |
| `restore.sh`      | Teardown orchestrator: keep / cancel / keep-window              | `restore_main`                                 |
| `filter.sh`       | Shared filtered-list builder (SOURCED lib)                      | `lp_build_filtered`                            |
| `state.sh`        | State accessors + saved-state contract + status-format save/restore | `get_state`, `set_state`, `state_status_format_save/restore`, `clear_all_state` |
| `options.sh`      | Per-option accessors with PRD defaults (SOURCED lib)           | `opt_type`, `opt_preview_mode`, etc.           |
| `utils.sh`        | tmux option/hook primitives (SOURCED lib)                       | `tmux_get_opt`, `tmux_set_opt`, `tmux_unset_opt`, `lp_client_format` |

### Data-flow (critical for understanding the bugs)

1. **Activate** (`livepicker.sh`): snapshots all state into `@livepicker-orig-*`
   keys, grows status to 2 lines, installs `renderer.sh` as `status-format[0]`,
   binds the `livepicker` key table, seeds `@livepicker-list`.

2. **Input** (`input-handler.sh`): dispatched from key table. Updates
   `@livepicker-filter` / `@livepicker-index`, then either refreshes status
   (type/backspace/cancel-clear) OR refreshes status + calls `preview.sh`
   (next-session/prev-session).

3. **Render** (`renderer.sh`): re-evaluated on every `refresh-client -S`. Reads
   `@livepicker-list` + `@livepicker-filter`, filters via `lp_build_filtered`
   (same function input-handler nav uses), highlights `@livepicker-index`.

4. **Preview** (`preview.sh`): `link-window` the candidate's window into the
   driver session + `select-window` (fires `session-window-changed`, NOT
   `client-session-changed`). Tracks `@livepicker-linked-id`.

5. **Restore** (`restore.sh`): 6-step teardown. Unlinks preview, re-selects
   ORIG_WINDOW (skipped in keep-window), switches client (cancel only), restores
   status/format/key-table/renumber/hook, restores layout, clears all state +
   unbinds the key table.

### Key invariants

- **Invariant A**: Browsing NEVER fires `client-session-changed` (only the one
  `switch-client` at confirm does).
- **Byte-exact restore**: cancel/keep/keep-window must leave `status`,
  `status-format[*]`, `key-table`, `renumber-windows`, the hook, and the layout
  byte-identical to pre-activate.
- Windows are addressed by **@id**, never index (renumber-windows is on).
- `clear_all_state` unsets ALL `@livepicker-orig-*` keys (STEP 6) — this is the
  root cause of Issue 1's destructiveness.

### Test harness (all in `tests/`)

- `run.sh` — entry point; sources all `test_*.sh`, discovers `test_*` functions,
  runs each in the CURRENT shell against a fresh isolated `-L` socket.
- `setup_socket.sh` — per-test isolated tmux server + PATH shim + baseline
  fixtures (driver/alpha/beta sessions, multi-pane windows). `attach_test_client`
  spawns a pty client for tests needing `switch-client`/`display-message`.
- `helpers.sh` — `fail`, `assert_eq`, `assert_contains`, `setup_test`,
  `teardown_test`. Failure sets `TEST_STATUS=fail` (never exits).
- Byte-identity pattern: snapshot `show-options -g | sort` before activate,
  assert byte-identical after teardown (subsumes "no leak" + "all restored").

## Bug Summary (5 issues from adversarial QA pass)

| Issue | Severity | File(s)                    | Root cause                                    |
|-------|----------|----------------------------|-----------------------------------------------|
| 1     | Critical | input-handler.sh:300-301   | Stray duplicate `restore.sh keep-window` call |
| 2     | Major    | input-handler.sh type/back/cancel | type/backspace/cancel-clear never call preview.sh |
| 3     | Minor    | renderer.sh:78,80,94,96,107| User strings emitted raw into `#[...]` format |
| 4     | Minor    | preview.sh:115             | `#{window_active}` ignores highlighted index  |
| 5     | Minor    | README.md:182              | References non-existent `./validate.sh`       |

## Fix Strategy

Each fix is localized to 1-2 files with a regression test that FAILS today and
PASSES after the fix (TDD). No architectural changes needed — all fixes are
within the existing data-flow. Dependencies are minimal (Issues 1-5 are
independent except Issue 2 + Issue 4 interact in window mode).
