# tmux-livepicker: Delta PRD — Theme-matched tabs & deferred preview

> Delta against the completed PRD in `plan/001_fd5d622d3939/` (session 1, fully
> implemented). The whole plugin already exists and passes its §15 suite. This
> document specifies ONLY the changes added by PRD revision `002`: two new
> sections (§17 Tab appearance, §18 Responsiveness/deferred preview) plus the
> supporting edits to §2, §3, §6, §7, §11, §15, §16. An implementing agent should
> read this delta alongside the existing code, not rebuild from scratch.

## What actually changed (diff summary)

PRD `002` added two new sections and threaded references to them through the
existing spec. No existing requirement was removed. Concretely:

- **§17 (NEW) — Tab appearance, reuse the window-status format.** The picker can
  render its items through the theme's own `window-status-current-format` /
  `window-status-format` instead of the standalone `@livepicker-fg/bg` coloring,
  so the picker reads as part of the status bar under any theme. New option
  `@livepicker-tab-style` (`plain` default | `window-status`).
- **§18 (NEW) — Responsiveness, interaction-first deferred preview.** Typing and
  navigation redraw the status line synchronously but defer the live preview to a
  background, supersedeable job, so a keystroke never waits on
  `link-window`/`select-window`. Confirm does not block on a preview. New option
  `@livepicker-preview-defer` (`on` default | `off`).
- **§2** adds two goals (theme-matched tabs §17; interaction-first feedback §18).
- **§3** adds two user stories (tabs look identical; ~100ms type-and-confirm with
  no perceived lag and possibly no preview at all).
- **§6 Filtering / Session navigation** changed wording: the typing path is now
  "status-only, synchronous" and navigation "redraws status immediately; the
  preview re-sync is deferred to the background." This is a behavior change to
  the already-shipped `input-handler.sh` (see §3 below).
- **§7** gained an intro cross-referencing §18 for preview timing.
- **§11** adds two option rows (`@livepicker-preview-defer`, `@livepicker-tab-style`).
- **§15** adds two validation subsections (`### Responsiveness`, `### Appearance`).
- **§16** adds two risk bullets (deferred-preview concurrency; window-status
  hijack fragility).

Change size: two medium features. This PRD is deliberately one phase, three
milestones — not a full rebuild.

## Impact on already-shipped code (must-read before editing)

The session-1 implementation is the baseline. These are the files each feature
touches, with the load-bearing notes from reading the current source:

- **§18 directly conflicts with the current `scripts/input-handler.sh`.** The
  `type`, `backspace`, and `cancel` (clear-query) branches currently call
  `_lp_sync_preview_to_top_match` INLINE (an `unlink`/`link`/`select` round-trip
  per keystroke), and `next-session`/`prev-session` call `preview.sh` inline.
  §18 contract point 1 requires the typing path to do NO preview work inline;
  point 2 requires nav to defer the preview. The `_lp_sync_preview_to_top_match`
  helper exists precisely to reconcile old-PRD §5 vs §3 — §18 supersedes that
  reconciliation by making the preview deferred (it still "follows" the top match,
  just asynchronously). The `confirm` branch is already compliant: it resolves
  the target from authoritative `@livepicker-filter`/`@livepicker-index` state
  and never calls `preview.sh`, so confirm already does not block on a preview.
- **§17 adds a render path in `scripts/renderer.sh`** (currently `plain`-only)
  and a sentinel-window resolution step in `scripts/livepicker.sh` activation
  (currently: save state → list → status → keys → first preview → mode-on; §17
  inserts format resolution before the first preview, gated on `tab-style`).
- **§17 is verified against the live tubular format** (research, this session):
  `display-message -p -t <target> "$option_value"` expands the whole `#{…}` tree
  — including `#{E:@tubular_pill_bg}` and the enormous conditional
  `window-status-format` — into concrete `#[fg=#hex…]` styles with the window
  name (`#W`) baked in. For a clean single-pane, no-bell, non-prefix window the
  inactive format collapsed to `#[default] <name> #[fg=#54546d]<sep>` and the
  current format to the tubular pill with concrete colors. This is exactly §16's
  risk-note prediction and grounds the sentinel approach.
- **`scripts/options.sh`** and **`scripts/state.sh`** each gain a small addition
  (one option accessor + a couple of state keys). They are sourced libraries with
  a documented no-side-effects contract; mirror the existing `opt_*` / `STATE_*`
  patterns exactly.
- **Tests** run under the existing socket-isolated harness
  (`tests/setup_socket.sh`, `tests/run.sh`) — no new infra. The tubular theme is
  NOT loaded on the isolated socket, so §17 tests must install a representative
  `window-status-format`/`window-status-current-format` fixture themselves
  (mirrors how the pollution test installs a `client-session-changed` stand-in).

## Leverage from prior research

Do NOT re-research. `plan/001_fd5d622d3939/architecture/` already establishes:
- `tmux_primitives.md §3` — `refresh-client -S` re-runs `#()` status commands;
  this is how the renderer re-evaluates per keystroke (§18's "status reflects the
  new query within a frame" rests on it).
- `sibling_plugins_and_env.md §6` — tubular owns `window-status-format`,
  `window-status-current-format`, `window-status-separator`, `status-justify`
  (absolute-centre); `status-format[*]` is unset. §17 reads exactly those.
- `system_context.md §3` — Invariant A (no `client-session-changed` while
  browsing) and the modal-key-table guarantee; unchanged by this delta.
The two genuinely-new facts (sentinel format resolution; `run-shell -b`
supersede) are verified in this session's task context, not re-derived per task.

## The single phase

### Phase P1 — Theme-matched tabs (§17) & deferred preview (§18)

Deliver the two new capabilities as independent tracks, then validate each with a
focused test (mirroring the §15 subsections), then sync the cross-cutting docs.
Build target unchanged: tmux 3.6b (floor 3.2). All edits compose with the
existing pollution/restore invariants — neither feature fires
`client-session-changed` or touches the saved-state contract.

#### Milestone P1.M1 — §17 Theme-matched tabs (window-status format reuse)

Adds the `window-status` tab-style path: activation resolves the theme's two
window-status formats against a sentinel window and caches the rendered
templates; the renderer emits them with the session name swapped in, falling
back to `plain` on any failure. Self-contained: the feature is off by default
(`@livepicker-tab-style plain`), so the existing `plain` path is untouched.

- **Task P1.M1.T1 — `options.sh` + `state.sh`: add `tab-style` + template cache.**
  - Subtask P1.M1.T1.S1 — `opt_tab_style()` accessor (default `plain`) in
    `options.sh`; two cache state keys in `state.sh`
    (`@livepicker-tab-current-tmpl`, `@livepicker-tab-inactive-tmpl`, initially
    empty) and clear them in `clear_all_state`. Mirror the existing
    `opt_*`/`STATE_*` style; no new save-state contract keys (the templates are
    picker-internal runtime state, cleared on exit). Verify the empty value is
    a real `set-option -g @x ""` (set-empty), not unset, so the renderer can
    distinguish "not resolved yet" (→ `plain` fallback) from "resolved empty".
    - Mode A docs: none (internal accessor/state).
    - Depends on: nothing new (both files already exist).
    - PRD: h2.11, h2.17.

- **Task P1.M1.T2 — `livepicker.sh`: sentinel window + format resolution + cache.**
  - Subtask P1.M1.T2.S1 — At activation, when `opt_tab_style == window-status`:
    create a short-lived hidden window named a unique placeholder
    (e.g. `__lp_tab__`), resolve both formats with
    `tmux display-message -p -t "$sentinel_target" "$option_value"` (NOT
    `#{window_status_current_format}` — the format string is the OPTION VALUE so
    `display-message` expands its `#{…}`), cache the two rendered templates into
    the state keys from T1, then kill the sentinel. This runs ONCE at activation
    (activation is not latency-sensitive — PRD §18), so there is no per-keystroke
    `display-message`. Guard every step: if the option value is empty, the
    sentinel cannot be created, or `display-message` returns empty, leave both
    cache keys empty (the renderer's fallback handles it) and continue
    activation — the picker must never fail to open over a styling miss.
    Insert the resolution after the key-table/first-preview setup so a failure
    cannot strand a half-grown status bar; `tab-style plain` skips this entirely.
    - Mode A docs: none.
    - Depends on: P1.M1.T1.S1.
    - PRD: h2.17, h2.16 (window-status hijack fragility).

- **Task P1.M1.T3 — `renderer.sh`: `window-status` render path with fallback.**
  - Subtask P1.M1.T3.S1 — In `render()`, after computing the filtered list +
    highlight index: if `opt_tab_style == window-status` AND both template cache
    keys are non-empty, render each item by taking the current template (for the
    highlighted index) or inactive template (others) and replacing the
    placeholder window-name substring with the session name; join items with the
    live `window-status-separator`; honor `status-justify` (it is already applied
    to the whole status line by tmux, so the renderer only needs to emit the
    joined string). If anything is missing/empty, fall back to the existing
    `plain` path verbatim (do not branch the plain path). Edge: a session name
    equal to the placeholder, or containing `#`, must not corrupt the template —
    use a unique placeholder and the existing `#`→`##` display-escape only on the
    inserted name. Keep the renderer PURE and fast (no `display-message` here;
    option reads + string replace only).
    - Mode A docs: none (renderer output is internal).
    - Depends on: P1.M1.T1.S1, P1.M1.T2.S1.
    - PRD: h2.17, h2.15/h3.24 (Appearance validation), h2.16.

#### Milestone P1.M2 — §18 Deferred preview (interaction-first responsiveness)

Reworks the input→preview data flow: the typing and nav paths stop calling
`preview.sh` inline and instead schedule a background, supersedeable preview;
`preview.sh` gains a sequence guard so a late job whose target was superseded is
a no-op. Default-on; `@livepicker-preview-defer off` restores the synchronous
path (the current behavior) for diagnosis.

- **Task P1.M2.T1 — `options.sh` + `state.sh`: add `preview-defer` + sequence token.**
  - Subtask P1.M2.T1.S1 — `opt_preview_defer()` accessor (default `on`) in
    `options.sh`; a `@livepicker-preview-seq` counter (incremented by the
    input handler each time it schedules a preview) and
    `@livepicker-preview-target` (the session name the pending preview should
    show) in `state.sh`; clear both in `clear_all_state`. Initialize the seq to
    0 at activation. These are the supersede mechanism: the handler bumps the
    seq when it fires; the background job captures the seq+target at fire time
    and `preview.sh` re-reads the seq before mutating — if it changed, the job
    is stale and no-ops.
    - Mode A docs: none.
    - Depends on: nothing new.
    - PRD: h2.18, h2.16 (deferred-preview concurrency).

- **Task P1.M2.T2 — `preview.sh`: supersede/sequence guard + background-safe entry.**
  - Subtask P1.M2.T2.S1 — Add an optional second arg `preview.sh <session>
    <expected_seq>`. When `<expected_seq>` is provided, read the live
    `@livepicker-preview-seq` at the TOP of `preview_main` and if it differs
    from `<expected_seq>`, return 0 WITHOUT unlinking/linking/selecting (a stale
    job must never clobber the current link — PRD §16 deferred-preview
    concurrency). When called with one arg (the activation first-preview, and
    the `preview-defer off` synchronous path), behave exactly as today (no
    guard). The existing link/unlink/select core is unchanged; this only adds a
    precheck. Also: re-read the linked-id inside the body (not just once at the
    top) so a job that raced a newer link does not unlink the newer window.
    - Mode A docs: none.
    - Depends on: P1.M2.T1.S1.
    - PRD: h2.18, h2.7, h2.16.

- **Task P1.M2.T3 — `input-handler.sh`: defer preview on type/backspace/nav.**
  - Subtask P1.M2.T3.S1 — When `opt_preview_defer == on` (default): replace the
    inline `_lp_sync_preview_to_top_match` call in `type`/`backspace`/`cancel`
    (clear-query) and the inline `preview.sh` call in `next-session`/`prev-session`
    with a deferred schedule: increment `@livepicker-preview-seq`, set
    `@livepicker-preview-target` to the new top match / new index target, then
    `tmux run-shell -b "$CURRENT_DIR/preview.sh <target> <new_seq>"`. The
    synchronous work on these paths becomes ONLY: update filter/index state +
    `refresh-client -S` (PRD §18 contract 1 & 2). Keep the `cancel` full-exit and
    `confirm` branches unchanged (cancel delegates to `restore.sh cancel`;
    confirm already reads authoritative state). When `opt_preview_defer == off`,
    call `preview.sh` inline as today (legacy path). Guard the empty-filtered
    case (no top match → schedule nothing, leave the prior preview). Verify the
    type→Enter-within-~100ms path lands correctly with NO preview having run
    (confirm must not depend on the background job).
    - Mode A docs: none.
    - Depends on: P1.M2.T1.S1, P1.M2.T2.S1.
    - PRD: h2.18, h2.6/h3.4, h2.6/h3.5.

#### Milestone P1.M3 — Validation (§15.23 + §15.24) + Mode B docs

Feature-specific tests under the existing socket harness, then the cross-cutting
docs. Tests mirror the new §15 subsections verbatim.

- **Task P1.M3.T1 — `tests/test_responsiveness.sh` (§15.23).**
  - Subtask P1.M3.T1.S1 — Assert: (a) typing a character redraws the status with
    the new query before any preview work runs (instrument: set a marker option
    in `preview.sh` and assert it is NOT set when the status already reflects the
    new query — or assert `@livepicker-preview-seq` advanced while the linked-id
    lagged); (b) three keystrokes within ~100ms + immediate Enter lands on the
    correct target with no backlog of re-links (assert at most one link occurred);
    (c) a preview whose target was superseded is a no-op (fire two schedules
    rapidly, assert only the latest target's window is linked and the stale one
    never unlinked a newer link); (d) navigation moves the highlight (status)
    before the preview catches up. Also assert `@livepicker-preview-defer off`
    restores synchronous preview (one link per keystroke). Uses the existing
    `tests/setup_socket.sh` isolation.
    - Mode A docs: none (test).
    - Depends on: P1.M2.T3.S1.
    - PRD: h2.15/h3.23, h2.18.

- **Task P1.M3.T2 — `tests/test_appearance.sh` (§15.24).**
  - Subtask P1.M3.T2.S1 — Install representative `window-status-current-format` /
    `window-status-format` / `window-status-separator` fixtures on the isolated
    socket (tubular is not loaded there), activate with
    `@livepicker-tab-style window-status`, and assert: the highlighted item's
    renderer output contains the resolved current-format styling and the others
    the inactive-format styling; the inter-item gap matches the separator; and
    that setting an empty/unresolvable format falls back to `plain`. Assert
    `tab-style plain` (default) is unchanged from session-1 behavior.
    - Mode A docs: none (test).
    - Depends on: P1.M1.T3.S1.
    - PRD: h2.15/h3.24, h2.17.

- **Task P1.M3.T3 — Mode B: sync `README.md` + `CHANGELOG.md`.**
  - Subtask P1.M3.T3.S1 — README: add the two new options
    (`@livepicker-tab-style`, `@livepicker-preview-defer`) to the configuration
    table; add a short "Appearance" note (tabs can match your window-status
    theme) and a "Performance" note (preview is deferred so typing/nav stay
    snappy; set `@livepicker-preview-defer off` to restore synchronous preview
    for diagnosis). CHANGELOG: an entry for both features, noting they are
    default-on (`preview-defer`) / default-off (`tab-style`) and that they do not
    change the pollution/restore invariants. Do NOT edit `PRD.md` (read-only).
    - Mode A docs: this IS the docs task.
    - Depends on: P1.M1.T3.S1, P1.M2.T3.S1, P1.M3.T1.S1, P1.M3.T2.S1.
    - PRD: h2.1, h2.2, h2.11, h2.17, h2.18.

## Non-goals for this delta

- Do NOT re-implement any session-1 subsystem. Only edit the files named above.
- Do NOT change the saved-state contract (`@livepicker-orig-*`) or the restore
  order — both features are picker-internal and tear down via `clear_all_state`.
- Do NOT make the preview itself faster (PRD §18 non-goal:
  `link-window`/`select-window` are irreducible). Only decouple it from input.
- Do NOT remove the `plain` tab-style path or the synchronous preview path — both
  remain as the defaults / the `off` escape hatch.
- Do NOT touch `PRD.md`.
