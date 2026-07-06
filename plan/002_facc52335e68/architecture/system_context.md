# System Context — Delta 002 (§17 Theme-matched tabs + §18 Deferred preview)

> Synthesis of the three research briefs (`codebase_state.md`, `external_tmux_behavior.md`,
> `test_harness.md`) plus the delta PRD. Resolves every open question the scouts raised.
> Downstream PRP agents should read this FIRST, then the relevant focused brief.

## 1. What this delta is

A **changeset against the already-shipped plan-001 implementation** (green: 16 tests PASS).
Two new, independent features are added; nothing is rebuilt:

- **§17 — Theme-matched tabs.** A new `@livepicker-tab-style` option (`plain` default |
  `window-status`). In `window-status` mode the picker renders its items through the
  theme's own `window-status-current-format` / `window-status-format` (the same layer every
  tmux theme configures) so the picker reads as part of the status bar under any theme.
- **§18 — Deferred preview.** A new `@livepicker-preview-defer` option (`on` default |
  `off`). Typing and navigation redraw the status synchronously but defer the live preview
  to a background, supersedeable `run-shell -b` job, so a keystroke never waits on
  `link-window`/`select-window`. Confirm never blocks on a preview.

Neither feature fires `client-session-changed` or touches the saved-state contract
(`@livepicker-orig-*`). Both tear down via the existing `clear_all_state`.

## 2. PRD §11 defaults (authoritative — overrides any scout speculation)

| Option | Default | Type |
|--------|---------|------|
| `@livepicker-tab-style` | `plain` | enum `plain\|window-status` |
| `@livepicker-preview-defer` | `on` | bool `on\|off` |

## 3. Open questions RESOLVED

### Q1 — Are the tab templates runtime state or config?
**RUNTIME.** They are resolved ONCE at activation (via the sentinel window) and cached in
`@livepicker-tab-current-tmpl` / `@livepicker-tab-inactive-tmpl`. They are NOT config
mirrors (config is only the `plain` vs `window-status` toggle in `@livepicker-tab-style`).
They live in `state.sh` as `STATE_*` constants and MUST be added to `_STATE_RUNTIME_KEYS`
(line 49) so `clear_all_state` clears them on exit. They are initially empty (set-empty,
not unset) so the renderer can distinguish "not resolved yet" → `plain` fallback.

### Q2 — Sentinel window: status-format index or window-status-format override?
**Neither.** The sentinel is a short-lived HIDDEN window in a dedicated hidden session,
used solely to resolve the two window-status-format OPTION VALUES via
`display-message -p`. The resolved templates (concrete `#[…]` styles with the sentinel's
window name baked in) are cached in picker state keys. The renderer reads those keys and
swaps the sentinel name → each session name. No status-format index or window-status-format
override is involved. The renderer's `status-format[$idx]` entry (installed at activate T3)
is unchanged.

### Q3 — preview-defer semantics
- `@livepicker-preview-defer on` (default): the typing/nav paths do NO preview work inline;
  they schedule a background `run-shell -b` job carrying a sequence token. The seq guard in
  `preview.sh` makes a late/superseded job a no-op.
- `@livepicker-preview-defer off`: restore the legacy synchronous path (call `preview.sh`
  inline with one arg). This is the diagnostic escape hatch.
- The activation-time first preview stays synchronous (activation is not latency-sensitive).
- Confirm is ALREADY compliant (reads authoritative filter/index, never calls preview.sh).

### Q4 — _STATE_RUNTIME_KEYS update is mandatory
**Confirmed.** `clear_all_state` (state.sh line 139-164) iterates the `_STATE_RUNTIME_KEYS`
space-list (line 49) to `-gu` each runtime key. Any new runtime `STATE_*` key NOT added to
that list LEAKS across picker sessions. The four new keys must be appended.

## 4. Invariants that MUST hold (from plan-001, unchanged by this delta)

- **Invariant A (PRD §4):** browsing never fires `client-session-changed`. Both new
  features operate inside the current session (link/select for preview; option reads for
  tabs). Confirmed by `external_tmux_behavior.md` Q5/Q8.
- **Invariant B (PRD §8/§16):** unmatched keys in the `livepicker` key table are DROPPED,
  not passed to the pane (stable 2.x→3.6b, Q8). The preview is display-only.
- **Shared filter invariant:** `filter.sh::lp_build_filtered` is the SINGLE filter used by
  renderer.sh, input-handler.sh, and (via the defer helper) the preview target. Any new
  preview-sync logic MUST route through it or filtered[idx] drifts from the highlight.

## 5. External tmux facts confirmed on 3.6b (load-bearing for implementation)

1. **`display-message -p -t <target> "$option_value"` expands the full `#{…}` tree**
   including `#{E:@user_option}` re-expansion and `#W`. Pass the OPTION VALUE (via
   `show-options -gwv`), NOT the literal `#{window_status_current_format}`. [HIGH]
2. **`#()` status-command stdout is NOT re-parsed for `#{…}`** — only `#[…]` styles apply.
   This is WHY the sentinel pre-resolution step exists. [HIGH]
3. **Sentinel window:** create a dedicated hidden 2-window session (anchor + sentinel); the
   sentinel is non-active → clean `#F` (empty), `#{window_panes}`=1, every `*_flag`=0. Kill
   the session after resolution. Make the session name unique (PID+epoch). [HIGH]
4. **`run-shell -b`** is detached/non-blocking; runs in a shell with `TMUX` set so a bare
   `tmux` reaches the same server. NOT cancellable by id — a late job must be a no-op via
   the seq guard. If the picker exits while a `-b` job is mid-flight, the seq guard prevents
   it from clobbering restored state. [HIGH]
5. **Supersede pattern:** monotonic `@livepicker-preview-seq` counter; bump on fire, capture
   at fire time, re-check in `preview.sh` immediately before mutating AND optionally before
   the final select. Mismatch → return 0 (no-op). [HIGH]
6. **`refresh-client -S`** forces `#()` re-evaluation. Safe per keystroke iff the renderer
   is cheap (option reads + string ops only — which is exactly what §18 ensures). [HIGH]

## 6. Exact insertion points (from codebase_state.md)

| File | Where | What |
|------|-------|------|
| `options.sh` | after line 44 (`opt_status_format_index`) | `opt_tab_style()` + `opt_preview_defer()` single-line accessors |
| `state.sh` | lines 31-36 (runtime `STATE_*` block) | 4 new `readonly STATE_*` constants |
| `state.sh` | line 49 (`_STATE_RUNTIME_KEYS`) | append the 4 new keys |
| `livepicker.sh` | between first-preview if-block (~line 326) and `set_state MODE on` (~line 327) | sentinel resolution (gated on `opt_tab_style == window-status`) |
| `livepicker.sh` | in the save/init region (~STEP 2 / T5) | init `@livepicker-preview-seq` to 0 |
| `renderer.sh` | after option reads (~line 60), before `out=""` list-build | window-status render branch (early return if templates present) |
| `preview.sh` | top of `preview_main` (~line 76), before preview-mode gate (~line 86) | seq guard: read `expected_seq="${2:-}"`, compare to live seq |
| `preview.sh` | inside the link/select body (~line 150-164) | re-read `linked_id` before unlink (race safety) |
| `input-handler.sh` | `_lp_sync_preview_to_top_match` (~line 130) | replace/augment with `_lp_fire_preview` (bump seq, set target, `run-shell -b`) |
| `input-handler.sh` | call sites ~lines 172, 210, 246, 265, 400 | route through deferred helper when `opt_preview_defer == on` |

## 7. Test harness leverage (from test_harness.md)

- `tests/run.sh` discovers `test_*` functions, per-test fresh isolated socket via
  `setup_test "lp-$$-<name>"`. Tests source nothing; define `test_*` only.
- **Appearance tests** need NO client (renderer is client-independent): mirror
  `test_functional.sh::test_renderer_escapes_hash_*` (seed options → run renderer.sh →
  `assert_contains` on stdout). Install `window-status-format`/`window-status-current-format`
  /`window-status-separator` fixtures directly on the socket (tubular is NOT loaded there).
- **Responsiveness tests** need `attach_test_client` (for `refresh-client -S` / `switch-client`).
  Mirror `test_functional.sh::test_activate_grows_status` lifecycle. Instrument preview.sh
  with a marker option to assert deferred vs synchronous timing.
- Assertion API: `fail`, `pass`, `assert_eq`, `assert_contains`, plus inline `case`+`fail`
  for negative checks. Seed helpers use `lp_` prefix (never `test_`).

## 8. Dependency graph

```
M1.T1 (options+state: tab-style) ──► M1.T2 (sentinel resolution) ──► M1.T3 (renderer path) ──┐
                                                                                              ├──► M3.T3 (docs)
M2.T1 (options+state: preview-defer) ──► M2.T2 (preview.sh seq) ──► M2.T3 (input defer) ──► M3.T1 (resp test) ─┤
                                                        M1.T3 ──► M3.T2 (appearance test) ──────────────────────┘
```
M1 and M2 are independent tracks (can parallelize). M3.T3 (docs) runs last, depends on all
implementing + test subtasks.
