# PRP — P1.M4.T3.S1: tests/test_scroll_width.sh — scroll + client-width cache suite

---

## Goal

**Feature Goal**: Create `tests/test_scroll_width.sh` — the **scroll-into-view +
client-width-cache** validation suite (PRD §15.28 "Layout, ranking, scroll, and
management" — the scroll + width items; PRD §10 step 5 / §3.35 width source; PRD
§3.32 viewport+scroll; PRD §16 "Width cache staleness"). It proves nine contract
behaviors by driving the REAL plugin (`scripts/livepicker.sh` → `input-handler.sh`
→ `renderer.sh` → `restore.sh`, all COMPLETE) on the socket-isolated harness:

- **(a) scroll advances** — many wide sessions + a small `@livepicker-client-width`
  + repeated `next-session` → `@livepicker-scroll` advances > 0 AND the renderer
  emits the left overflow indicator `<`. Plus the **viewport-recompute** flip:
  setting width 0 (no windowing) makes the renderer drop the `<` (it re-derives the
  slice against the cached width every redraw).
- **(a-clamp) scroll clamps to 0 when the list fits** — the same nav with a WIDE
  width leaves scroll at 0 and no `<` (PRD §3.32 "clamp scroll=0 when fits").
- **(d) scroll resets** — `type`, `backspace`, and the cancel CLEAR path each
  reset `@livepicker-scroll` to 0 (the cancel-clear case also clears the filter and
  keeps the picker open).
- **(b) width cache refresh** — seeding a stale width then firing `refresh-width`
  re-caches the LIVE `#{client_width}` (the action the `client-resized` hook runs);
  PLUS the hook is INSTALLED at `client-resized[0]` → `input-handler.sh refresh-width`.
- **(c) client-resized hook restored byte-exact** — a full activate→cancel cycle
  restores `show-hooks -g client-resized` byte-identically for BOTH an unset prior
  (bare) and a set prior (`-b`), proving no width-cache-staleness leak (PRD §16).

**Deliverable**: The single NEW file `tests/test_scroll_width.sh` (sourced by
`tests/run.sh` via its `test_*.sh` glob — NOT executed directly). It defines a
`_lp_scroll_setup [width]` helper + nine `test_scroll_*` / `test_width_*` /
`test_client_resized_*` functions. Every assertion is backed by a **captured
output** in `research/test_scroll_width_findings.md` — no guessed bytes. It touches
NO source (read-only against the COMPLETE plugin).

**Success Definition**:
- `bash -n tests/test_scroll_width.sh` passes; `shellcheck tests/test_scroll_width.sh`
  is clean (file-level `# shellcheck disable=SC2154,SC2016,SC2034,SC2086`, mirroring
  `test_functional.sh` / the in-flight `test_layout.sh` / `test_ranking.sh`).
- `tests/run.sh` discovers and runs every `test_scroll_*` / `test_width_*` /
  `test_client_resized_*` function; the file adds ~9 passing tests and **does not
  break any existing test** (it touches no source).
- Each contract case (a/a-clamp/d/b/c) has at least one passing test whose
  assertions match the live captures in `research/test_scroll_width_findings.md`.

## User Persona (if applicable)

**Target User**: The maintainer / CI (the suite runs under `tests/run.sh`). Mode A
(internal validation — no end-user surface). README (P4.T1) summarizes coverage.

**Use Case**: A change to the scroll-into-view math (`input-handler.sh::_lp_scroll_into_view`
/ `layout.sh::lp_viewport`), the client-width cache (`activate` capture / `refresh-width`
action / `client-resized` hook install+restore), or the renderer viewport slice is
made. `tests/run.sh` runs this file's functions (each on a fresh isolated socket
with an attached pty client); any regression — scroll not following the highlight,
scroll not resetting on type, the width cache going stale, or the user's
`client-resized` hook not restored — turns a specific assertion red with a precise
diagnostic.

**User Journey**: `cd <repo> && tests/run.sh` → the runner sources `setup_socket.sh`
+ `helpers.sh` + every `test_*.sh` (incl. the new file), discovers every
`test_scroll_*`/`test_width_*`/`test_client_resized_*` function, and runs each in a
per-test fresh-socket cycle (`setup_test` → reset `TEST_STATUS` → run → read
`TEST_STATUS` → `teardown_test`). PASS/FAIL printed per test + summary.

**Pain Points Addressed**:
- (a) **Scroll regressions are silent.** A changed `lp_viewport` constant or a
  dropped `_lp_scroll_into_view` call leaves the highlight pinned at the left edge
  while the user navigates off-screen. The scroll-advance + `<` assertions pin it.
- (b) **A stale width cache makes the viewport wrong** (PRD §16 "Width cache
  staleness"). The refresh-width re-cache + hook-restore tests lock the cache's
  refresh path and its exact teardown.
- (c) **A mis-restored `client-resized` hook leaks into the user's config.** The
  byte-exact restore test (unset + set `-b` prior) catches any index/flag/command
  drift, mirroring the session-window-changed restore guarantee.

## Why

- **§15.28 enumerates the scroll + layout items; §10 step 5 / §3.35 the width
  source; §3.32 the viewport+scroll; §16 the width-cache-staleness risk.** This
  task is the validation counterpart to P1.M3.T1 (client-width cache — COMPLETE)
  and P1.M3.T2 (scroll-into-view + reset — COMPLETE and shipping, despite the
  plan_status "Planned" label). It locks those behaviors so P2/P3 (session mgmt,
  preview clip) cannot regress them.
- **Every assertion is backed by a live capture.** The research file records the
  EXACT state/output the plugin produces for each scenario (run on 2026-07-08), so
  the test author encodes observed behavior, not guesses.
- **Boundary respect.** This task creates ONE test file. It does NOT touch any
  source, does NOT duplicate `test_layout.sh`'s §19-layout cases or
  `test_ranking.sh`'s §20-ranking cases, and does NOT cover the renderer's tab
  styling/appearance (`test_appearance.sh`). It covers SCROLL + WIDTH-CACHE only.

## What

A single NEW sourced test file at `tests/test_scroll_width.sh` that:

1. Declares the file-level shellcheck disable + documents the harness idiom
   (mirrors `test_functional.sh`'s header).
2. Defines `_lp_scroll_setup [width]` — attach a pty client, seed ~8 wide-named
   sessions, activate the picker, and pin `@livepicker-client-width` (default 12).
   (`setup_test` already pinned `@livepicker-preview-defer off`, so nav is
   synchronous — no async `-b` preview racing the scroll/state reads.)
3. Defines nine `test_*` functions (listed below). The scroll/nav tests use
   `_lp_scroll_setup`; the width/hook tests use `attach_test_client` + activate
   inline; failure is signaled ONLY via `fail`/`assert_*`.

### Success Criteria

- [ ] `tests/test_scroll_width.sh` EXISTS; file-level `# shellcheck disable=SC2154,SC2016,SC2034,SC2086`.
- [ ] `_lp_scroll_setup [width]` defined (attach + 8 wide sessions + activate + pin width).
- [ ] **(a)** `test_scroll_advances_on_nav`: width 12 + 5× next-session →
      `@livepicker-scroll` > 0 AND renderer output contains `<`; AND width 0 →
      renderer drops `<` (viewport recomputes against the cached width).
- [ ] **(a-clamp)** `test_scroll_clamps_zero_when_fits`: width 200 + 5× next-session →
      `@livepicker-scroll` == 0 AND renderer has NO `<`.
- [ ] **(d)** `test_scroll_resets_on_type`: advance scroll → `type` → scroll == 0.
- [ ] **(d)** `test_scroll_resets_on_backspace`: advance scroll → `backspace` → scroll == 0.
- [ ] **(d)** `test_scroll_resets_on_cancel_clear`: seed scroll 5 + filter "xx" +
      mode on → `cancel` → scroll 0, filter "", mode on.
- [ ] **(b)** `test_width_refresh_recaches_live`: seed stale 999 → `refresh-width` →
      `@livepicker-client-width` == live `#{client_width}` (and != 999).
- [ ] **(b)** `test_client_resized_hook_installed`: `show-hooks -g client-resized`
      contains `input-handler.sh` + `refresh-width`.
- [ ] **(c)** `test_client_resized_hook_restored_unset_prior`: byte-exact
      `show-hooks -g client-resized` before/after activate+cancel (bare prior).
- [ ] **(c)** `test_client_resized_hook_restored_set_prior`: byte-exact before/after
      (a set `-b` prior).
- [ ] `tests/run.sh` runs all nine and they PASS; no existing test breaks.

## All Needed Context

### Context Completeness Check

_Pass_: A developer who has never seen this repo can implement the suite from
(a) the complete ready-to-paste `tests/test_scroll_width.sh` body in the
Implementation Blueprint, (b) the 10 live-verified findings in
`research/test_scroll_width_findings.md` — most critically **FINDING 1** (the
exact scroll-advance fixture: 8 wide sessions + width 12 + 5 next → scroll 5 +
renderer `<` + `+8>`), **FINDING 5** (`resize-window` does NOT change
`#{client_width}` — so the resize path is validated via the refresh-width ACTION +
hook-INSTALL assertions, exactly the item's sanctioned "directly invoking the
hook's refresh"), **FINDING 7** (client-resized restore is byte-exact for BOTH
unset and set-`-b` priors), and **FINDING 10** (the renderer's LEFT `<` requires
scroll>0; index=0 shows only the right indicator), and (c) the captured exact
outputs. The code under test (input-handler, renderer, layout, livepicker, restore)
and the harness (`run.sh`/`helpers.sh`/`setup_socket.sh`) are all COMPLETE. The
in-flight siblings (`test_layout.sh`, `test_ranking.sh`) are disjoint (§19 layout /
§20 ranking).

### Documentation & References

```yaml
# MUST READ — the CODE UNDER TEST (scroll). COMPLETE + shipping (P1.M3.T2).
- file: scripts/input-handler.sh
  why: _lp_scroll_into_view (160-166) writes @livepicker-scroll via lp_viewport;
       type (241) / backspace (279) / cancel-clear (472-474,482) each set_state
       STATE_SCROLL 0; next/prev-session (311-313,336-338) call _lp_scroll_into_view;
       refresh-width (501-505) re-caches STATE_CLIENT_WIDTH via lp_client_format.
  critical: scroll advance reads STATE_CLIENT_WIDTH as T (a conservative approx of
            the renderer's narrower T). type/backspace/cancel-clear reset scroll to 0
            SYNCHRONOUSLY (no preview work — defer is OFF in setup_test). cancel-clear
            seeds: it sets filter "" + index 0 + scroll 0 + _lp_sync_preview_to_top_match
            + return 0 (picker STAYS OPEN — the load-bearing return at 482).

# MUST READ — the CODE UNDER TEST (client-width cache + hook). COMPLETE (P1.M3.T1).
- file: scripts/livepicker.sh
  why: T2b block (215-231) captures STATE_CLIENT_WIDTH via lp_client_format, saves
       the prior client-resized hook (tmux_get_hook), clears it (tmux_clear_hook),
       and installs ours: set-hook -g client-resized "run-shell '$CURRENT_DIR/input-handler.sh refresh-width'".
  critical: the installed hook is client-resized[0] -> run-shell "<abs>/input-handler.sh refresh-width".
            show-hooks -g client-resized asserts the wiring.

# MUST READ — the CODE UNDER TEST (hook restore). COMPLETE.
- file: scripts/restore.sh
  why: STEP-4 (180-198) clears ours (tmux_clear_hook client-resized) then replays
       every saved client-resized[N] <cmd> preserving index + -b + verbatim command.
       Identical shape to session-window-changed (§P4). Byte-exact for unset + set.
  critical: restore runs SYNCHRONOUSLY inside `restore.sh cancel` (no async) — so
            immediately after `input-handler.sh cancel` returns, show-hooks reflects
            the restored prior. The restore is NOT gated (width cache is always installed).

# MUST READ — the renderer (viewport slice + overflow indicators). COMPLETE (P1.M2).
- file: scripts/renderer.sh
  why: reads STATE_CLIENT_WIDTH (125) + STATE_SCROLL (71); when width>0 it computes
       T and calls lp_viewport, emitting the left indicator #[fg=$FG,bg=$BG]<#[default]
       when LPV_HIDDEN_LEFT>0, and +N> on the right. width 0 -> NO windowing (full list).
  pattern: |
    left_ind="#[fg=$FG,bg=$BG]${ovl}#[default]"   # ovl = opt_overflow_left (default "<")
    # shown iff LPV_HIDDEN_LEFT > 0 (i.e. scroll > 0)
  gotcha: on the test socket opt_fg=#ffffff (user conf pre-declares @livepicker-fg), so the
          styled wrapper varies -> assert on the RAW "<" presence (no tab name contains "<"
          in the fixture). The LEFT "<" requires scroll>0 (FINDING 10); index=0 shows only "+N>".

# MUST READ — the viewport math (shared). COMPLETE (P1.M1.T2).
- file: scripts/layout.sh
  why: lp_viewport RANKED T SCROLL HIGHLIGHT [SEP] -> LPV_SCROLL/START/END/HIDDEN_*.
       total<=T -> clamp scroll=0 (line 127). scroll-into-view advances scroll while
       cumwidth(scroll,hl) > T. Pure math; no tmux.
  critical: with scroll=hl=0 + overflow, LPV_HIDDEN_LEFT=0 (no "<"); the left "<" needs
            scroll>0. With a WIDE T the list fits -> scroll clamps to 0 (the a-clamp case).

# MUST READ — the test harness entry point. COMPLETE.
- file: tests/run.sh
  why: Sources setup_socket.sh + helpers.sh + every test_*.sh; discovers test_* via
       `compgen -A function | grep '^test_'`; runs each in a per-test fresh-socket cycle
       (setup_test -> reset TEST_STATUS -> run -> teardown_test). This file is SOURCED.
  critical: Test bodies signal failure ONLY via fail/assert_* (which set TEST_STATUS in
            the CURRENT shell). NEVER exit/return-nonzero — that kills the runner.

# MUST READ — the assertion + setup helpers. COMPLETE.
- file: tests/helpers.sh
  why: fail/pass/assert_eq/assert_contains + setup_test/teardown_test. setup_test brings
       up a FRESH isolated -L socket + baseline fixtures (driver/alpha/beta) AND pins
       @livepicker-preview-defer off (deterministic synchronous nav/scroll). attach_test_client
       spawns the pty client nav/refresh-width need.
  critical: assert_eq a b msg (POSIX =); assert_contains str sub msg (literal substring via
            a quoted case pattern — no glob, no subprocess). Use these — do NOT invent asserts.

# MUST READ — the socket-isolation layer + attach_test_client. COMPLETE.
- file: tests/setup_socket.sh
  why: Exports $LIVEPICKER_SCRIPTS (= scripts/), the PATH shim (bare `tmux` -> isolated -L
       socket), and attach_test_client/detach_test_client (script-pty pair). The isolated
       socket SOURCES the user tmux.conf -> @livepicker-fg "#ffffff" is pre-set (dormant).
  critical: $LIVEPICKER_SCRIPTS is the documented path to scripts/ — use it to invoke
            livepicker.sh / input-handler.sh / renderer.sh.

# MUST READ — the reference test (attach + activate + drive input idiom). COMPLETE.
- file: tests/test_functional.sh
  why: The canonical pattern this file mirrors: attach_test_client; add fixtures BEFORE
       activate (the list is captured at activate time); "$LIVEPICKER_SCRIPTS/livepicker.sh"
       to activate; "$LIVEPICKER_SCRIPTS/input-handler.sh" <action> to drive; read state via
       show-option -gqv; assert. Its test_nav_moves_selection / test_escape_restores are the
       closest analogs (nav + cancel-restore). Its renderer-seed tests (no attach) show the
       no-client idiom.
  critical: capture orig state DYNAMICALLY before activate for restore assertions; window ids
            are GLOBAL. For scroll we read @livepicker-scroll directly (no window-id math).

# MUST READ — the empirical ground-truth for THIS suite (10 live-verified findings).
- docfile: plan/003_77ef311abf10/P1M4T3S1/research/test_scroll_width_findings.md
  why: FINDING 1 (scroll->5 + renderer '<'+'+8>' at width 12); FINDING 2 (clamp 0 when fits);
       FINDING 3 (type/backspace/cancel-clear reset scroll 0); FINDING 4 (refresh-width
       re-caches 999->live); FINDING 5 (resize-window does NOT change client_width -> use the
       action + install assertions); FINDING 6 (hook installed at [0]->refresh-width);
       FINDING 7 (restore byte-exact unset + set -b); FINDING 8 (harness per-test lifecycle +
       defer OFF); FINDING 9 (fail/assert_* only); FINDING 10 (left '<' needs scroll>0).
  critical: Read BEFORE writing. FINDING 5 is the trap: a resize-window-driven width
            assertion WILL NOT move the cached value (client_width is pty-derived). FINDING 10
            is the trap: asserting the left '<' at index=0 fails (hidden_left=0).

# MUST READ — the in-parallel sibling PRPs (align conventions; confirm disjointness).
- docfile: plan/003_77ef311abf10/P1M4T1S1/PRP.md
  why: test_layout.sh establishes the conventions this file mirrors (file-level shellcheck
       disable; a _lp_*_setup/seed helper; test_* naming; the renderer-seed idiom). Its PRP
       covers §19 LAYOUT (query bar / gap / overflow indicators / no-count); it is DISJOINT
       from this file's SCROLL-dynamics + WIDTH-CACHE focus.
- docfile: plan/003_77ef311abf10/P1M4T2S1/PRP.md
  why: test_ranking.sh mirrors the same conventions and covers §20 RANKING (also disjoint).

# MUST READ — the PRD sections selected for this work item.
- docfile: PRD.md
  why: §15.28 (Layout, ranking, scroll, and management — the validation items); §10 step 5 /
       §3.35 (width source: capture at activate, refresh via client-resized hook, restore prior);
       §3.32 (viewport + scroll: scroll-into-view, clamp 0 when fits); §16 (width-cache-staleness
       risk + hook-restore-exactness).
  section: "§15 Validation (§3.28)", "§10 Status-line setup (step 5)", "§19 Status-line layout
           (§3.32 viewport+scroll, §3.35 width source)", "§16 Implementation risks (width cache)"

# MUST READ — architecture patterns (harness + hook conventions).
- docfile: plan/003_77ef311abf10/architecture/codebase_patterns.md
  why: §P8 (test harness: setup_test pins defer off; attach_test_client for nav/preview/scroll;
       renderer-seed tests need NO client); §P4 (hook save/restore IDENTICAL shape for
       session-window-changed and client-resized); §P7 (layout viewport shared by renderer +
       input-handler so they cannot disagree).
  section: "§P8 Test harness", "§P4 Hook save/restore", "§P7 Layout viewport"
```

### Current Codebase tree

```bash
tmux-livepicker/
  PRD.md
  plugin.tmux
  scripts/
    options.sh utils.sh state.sh layout.sh rank.sh   # COMPLETE libs.
    renderer.sh input-handler.sh preview.sh livepicker.sh restore.sh   # COMPLETE (code under test).
  tests/
    setup_socket.sh helpers.sh run.sh                 # COMPLETE harness (sourced by run.sh).
    test_self.sh test_functional.sh test_pollution.sh test_preview.sh test_restore.sh
    test_keyrepurpose.sh test_create.sh test_appearance.sh test_responsiveness.sh   # COMPLETE suites.
    test_layout.sh    # IN-FLIGHT (P1.M4.T1.S1, parallel) — §19 layout. DISJOINT.
    test_ranking.sh   # IN-FLIGHT (P1.M4.T2.S1, parallel) — §20 ranking. DISJOINT.
    test_scroll_width.sh   # <-- THIS TASK CREATES IT (§15.28 scroll + width-cache).
  plan/003_77ef311abf10/{architecture, P1M4T1S1/PRP.md, P1M4T2S1/PRP.md, P1M4T3S1/{PRP.md, research/}}
```

### Desired Codebase tree with files to be added and responsibility of file

```bash
tmux-livepicker/
  tests/
    test_scroll_width.sh   # NEW (this task). Sourced by run.sh. Drives the REAL plugin on the
                           # isolated harness. _lp_scroll_setup [width] helper.
                           #   test_scroll_advances_on_nav              (a: scroll>0 + '<' + recompute)
                           #   test_scroll_clamps_zero_when_fits       (a-clamp: wide width -> 0, no '<')
                           #   test_scroll_resets_on_type              (d)
                           #   test_scroll_resets_on_backspace          (d)
                           #   test_scroll_resets_on_cancel_clear      (d: seeded scroll+filter -> 0, open)
                           #   test_width_refresh_recaches_live        (b: 999 -> live via refresh-width)
                           #   test_client_resized_hook_installed      (b: show-hooks wiring)
                           #   test_client_resized_hook_restored_unset_prior   (c: byte-exact bare)
                           #   test_client_resized_hook_restored_set_prior     (c: byte-exact -b)
```

### Known Gotchas of our codebase & Library Quirks

```bash
# CRITICAL (research FINDING 5): `tmux resize-window` does NOT change #{client_width}.
# client_width is the CLIENT's pty width, not the window grid. resize-window leaves the
# cached @livepicker-client-width UNCHANGED and does NOT fire client-resized. So a
# resize-window-driven width assertion will not move the value (false-pass/fail).
# VALIDATE the width cache via (1) the refresh-width ACTION (seed stale 999 -> fire ->
# == live #{client_width}) + (2) the hook-INSTALL assertion (show-hooks contains
# refresh-width). The item explicitly sanctions "directly invoking the hook's refresh".

# CRITICAL (research FINDING 10): the renderer's LEFT '<' indicator requires scroll>0.
# layout.sh lp_viewport with scroll=hl=0 + overflow yields LPV_HIDDEN_LEFT=0 (no left '<');
# only the RIGHT '+N>' shows. So the scroll-advance test NAVIGATES DOWN first (scroll>0)
# before asserting '<'. A renderer-seed asserting '<' must seed @livepicker-scroll>0.

# CRITICAL (research FINDING 1): seed a SMALL @livepicker-client-width (e.g. 12) AFTER
# activate to force overflow deterministically. activate captures the live client_width
# (~80 on the pty); override it: `tmux set-option -g @livepicker-client-width 12`. The
# item's "small client_width" means exactly this direct seed (resize-window can't do it).
# With ~8 wide sessions (e.g. "session-tab-N", ~14 cols) + width 12, 3-5 next-session
# advances scroll well past 0 (verified: scroll=5 after 5 next).

# CRITICAL (renderer '<' assertion): assert on the RAW "<" character presence, NOT a
# hardcoded styled substring. The left indicator is #[fg=$FG,bg=$BG]<#[default] where
# $FG=#ffffff on the test socket (user conf pre-declares @livepicker-fg) — the wrapper
# varies. But "<" appears ONLY in the left indicator when the fixture's tab names
# contain no "<" (use clean names like "session-tab-N"). For absence (width 0 / fits),
# use an inline `case "$out" in *"<"*) fail ...;; esac` (mirrors test_functional negatives).

# CRITICAL (harness): signal failure ONLY via fail/assert_* (sets TEST_STATUS in the
# CURRENT shell). NEVER `exit` or `return-nonzero` — run.sh reads TEST_STATUS; an exit
# kills the whole runner. set -u is INHERITED from helpers.sh; TABS for indent; `local`
# for all function locals. File-level `# shellcheck disable=SC2154,SC2016,SC2034,SC2086`.

# GOTCHA (defer): setup_test pins @livepicker-preview-defer OFF -> nav/scroll are
# SYNCHRONOUS (no async -b preview racing the @livepicker-scroll read). Do NOT flip it
# on in these tests (test_responsiveness.sh owns the defer-on path). The scroll writes
# are status-only STATE writes regardless, but defer-off keeps the linked-id/preview
# side effects deterministic too.

# GOTCHA (fixtures BEFORE activate): @livepicker-list is captured at activate time
# (list-sessions). Add the wide sessions BEFORE `livepicker.sh` (the _lp_scroll_setup
# helper does this). Adding them after activate won't populate the picker list.

# GOTCHA (cancel-clear seeding): the normal flow never produces non-empty-filter +
# non-zero-scroll together (typing resets scroll). So test the cancel CLEAR branch's
# scroll reset by SEEDING @livepicker-filter + @livepicker-scroll directly post-activate
# (state is picker-internal; consistent with the renderer-seed idiom). Then `cancel`
# (non-empty filter -> clear path) and assert scroll==0 + filter=="" + mode==on.

# GOTCHA (client-resized prior capture): capture `show-hooks -g client-resized` BEFORE
# activate DYNAMICALLY and assert `after == before` (not a hardcoded string). The
# isolated socket sources the user conf; on this env client-resized is bare (unset) at
# baseline, but the dynamic compare is robust to any conf-set prior. Test BOTH the bare
# and a seeded `-b` prior (two functions).

# GOTCHA (naming): use `test_scroll_*` / `test_width_*` / `test_client_resized_*`
# (distinct from the siblings' `test_layout_*` / `test_ranking_*`) so the suites are
# visually distinct in run.sh output. Do NOT assert on §19 layout structure (gap/overflow
# format/count) or §20 ranking order — those are the siblings' domains.
```

## Implementation Blueprint

### Data models and structure

No data model. The file holds: the `_lp_scroll_setup [width]` helper; and nine
`test_*` functions. Each uses function-local vars; failure is signaled via
`fail`/`assert_eq`/`assert_contains` (from helpers.sh). The assertion surface is
`tmux show-option -gqv @livepicker-*`, `tmux show-hooks -g client-resized`,
`tmux display-message -p '#{client_width}'`, and `renderer.sh` stdout.

### Implementation Tasks (ordered by dependencies)

```yaml
Task 1: CREATE tests/test_scroll_width.sh — header + _lp_scroll_setup helper
  - FILE: ./tests/test_scroll_width.sh  (NEW; sourced by run.sh via its test_*.sh glob).
  - SHEBANG: #!/usr/bin/env bash
  - LINE 2 file-level shellcheck disable (mirror test_functional.sh EXACTLY):
      # shellcheck disable=SC2154,SC2016,SC2034,SC2086
      #   SC2154: TEST_STATUS / setup_test / attach_test_client / tmux / LIVEPICKER_SCRIPTS
      #           are provided by run.sh + helpers.sh + setup_socket.sh (sourced before this file).
      #   SC2016/SC2034/SC2086: the harness's eval/single-quote + word-split idioms.
  - NOTE: set -u is INHERITED from helpers.sh (do NOT re-declare; mirror test_functional.sh).
  - DEFINE _lp_scroll_setup [width]:
      _lp_scroll_setup() {
      	local width="${1:-12}"
      	attach_test_client
      	local i
      	for i in $(seq 1 8); do
      		tmux new-session -d -s "session-tab-$i" -x 120 -y 40   # wide names -> overflow at small width
      	done
      	"$LIVEPICKER_SCRIPTS/livepicker.sh"
      	tmux set-option -g @livepicker-client-width "$width"
      }
  - STYLE: tabs; quote every expansion.

Task 2: SCROLL tests (a) advance + (a-clamp) clamp + (d) resets
  - (a) test_scroll_advances_on_nav:
      _lp_scroll_setup 12
      local sc before out
      before="$(tmux show-option -gqv @livepicker-scroll)"; [ -z "$before" ] && before=0
      local n; for n in 1 2 3 4 5; do "$LIVEPICKER_SCRIPTS/input-handler.sh" next-session >/dev/null; done
      sc="$(tmux show-option -gqv @livepicker-scroll)"
      [ "$sc" -gt 0 ] 2>/dev/null || fail "(a) scroll advanced >0 after 5 next (got [$sc])"
      pass "(a) scroll advanced to $sc (width 12)"
      out="$("$LIVEPICKER_SCRIPTS/renderer.sh")"
      assert_contains "$out" "<" "(a) renderer shows left overflow '<' when scroll>0"
      # viewport recompute: width 0 -> no windowing -> no '<' (renderer re-derives vs cached width)
      tmux set-option -g @livepicker-client-width 0
      out="$("$LIVEPICKER_SCRIPTS/renderer.sh")"
      case "$out" in *"<"*) fail "(a) width 0 should drop '<' (no windowing; recompute)";; esac
      pass "(a) width 0 recomputes viewport (no '<')"
  - (a-clamp) test_scroll_clamps_zero_when_fits:
      _lp_scroll_setup 200
      local n sc out
      for n in 1 2 3 4 5; do "$LIVEPICKER_SCRIPTS/input-handler.sh" next-session >/dev/null; done
      sc="$(tmux show-option -gqv @livepicker-scroll)"; [ -z "$sc" ] && sc=0
      assert_eq "$sc" "0" "(a-clamp) scroll stays 0 when the list fits (wide width)"
      out="$("$LIVEPICKER_SCRIPTS/renderer.sh")"
      case "$out" in *"<"*) fail "(a-clamp) no '<' when the list fits";; esac
      pass "(a-clamp) no '<' when the list fits"
  - (d) test_scroll_resets_on_type:
      _lp_scroll_setup 12
      local n sc; for n in 1 2 3 4 5; do "$LIVEPICKER_SCRIPTS/input-handler.sh" next-session >/dev/null; done
      sc="$(tmux show-option -gqv @livepicker-scroll)"; [ "$sc" -gt 0 ] 2>/dev/null || fail "(d) precondition: scroll>0"
      "$LIVEPICKER_SCRIPTS/input-handler.sh" type x >/dev/null
      sc="$(tmux show-option -gqv @livepicker-scroll)"; [ -z "$sc" ] && sc=0
      assert_eq "$sc" "0" "(d) type resets scroll to 0"
  - (d) test_scroll_resets_on_backspace:
      _lp_scroll_setup 12
      "$LIVEPICKER_SCRIPTS/input-handler.sh" type x >/dev/null   # give backspace something to trim
      local n sc; for n in 1 2 3 4 5; do "$LIVEPICKER_SCRIPTS/input-handler.sh" next-session >/dev/null; done
      sc="$(tmux show-option -gqv @livepicker-scroll)"; [ "$sc" -gt 0 ] 2>/dev/null || fail "(d) precondition: scroll>0"
      "$LIVEPICKER_SCRIPTS/input-handler.sh" backspace >/dev/null
      sc="$(tmux show-option -gqv @livepicker-scroll)"; [ -z "$sc" ] && sc=0
      assert_eq "$sc" "0" "(d) backspace resets scroll to 0"
  - (d) test_scroll_resets_on_cancel_clear:
      _lp_scroll_setup 12
      # seed non-empty filter + non-zero scroll (the normal flow can't produce both; typing resets scroll)
      tmux set-option -g @livepicker-filter "xx"
      tmux set-option -g @livepicker-scroll 5
      "$LIVEPICKER_SCRIPTS/input-handler.sh" cancel >/dev/null
      local sc fl mo
      sc="$(tmux show-option -gqv @livepicker-scroll)"; [ -z "$sc" ] && sc=0
      fl="$(tmux show-option -gqv @livepicker-filter)"
      mo="$(tmux show-option -gqv @livepicker-mode)"
      assert_eq "$sc" "0" "(d) cancel-clear resets scroll to 0"
      assert_eq "$fl" ""   "(d) cancel-clear cleared the filter"
      assert_eq "$mo" "on" "(d) cancel-clear kept the picker OPEN (mode on)"

Task 3: WIDTH-CACHE tests (b) refresh-width + hook installed
  - (b) test_width_refresh_recaches_live:
      attach_test_client
      "$LIVEPICKER_SCRIPTS/livepicker.sh" >/dev/null
      local live cached
      live="$(tmux display-message -p '#{client_width}' 2>/dev/null)"
      tmux set-option -g @livepicker-client-width 999        # simulate stale cache
      "$LIVEPICKER_SCRIPTS/input-handler.sh" refresh-width >/dev/null
      cached="$(tmux show-option -gqv @livepicker-client-width)"
      assert_eq "$cached" "$live" "(b) refresh-width re-cached the LIVE client_width"
      [ "$cached" != "999" ] || fail "(b) stale 999 survived refresh-width"
  - (b) test_client_resized_hook_installed:
      attach_test_client
      "$LIVEPICKER_SCRIPTS/livepicker.sh" >/dev/null
      local hk; hk="$(tmux show-hooks -g client-resized)"
      assert_contains "$hk" "input-handler.sh" "(b) client-resized hook wired to input-handler.sh"
      assert_contains "$hk" "refresh-width"    "(b) client-resized hook runs the refresh-width action"

Task 4: HOOK-RESTORE tests (c) byte-exact for unset + set(-b) priors
  - (c) test_client_resized_hook_restored_unset_prior:
      local before after
      before="$(tmux show-hooks -g client-resized)"          # baseline: bare/unset on this socket
      attach_test_client
      "$LIVEPICKER_SCRIPTS/livepicker.sh" >/dev/null
      "$LIVEPICKER_SCRIPTS/input-handler.sh" cancel >/dev/null
      after="$(tmux show-hooks -g client-resized)"
      assert_eq "$after" "$before" "(c) client-resized restored byte-exact (unset prior)"
  - (c) test_client_resized_hook_restored_set_prior:
      tmux set-hook -g client-resized "run-shell -b /usr/bin/true"   # a user prior with -b
      local before after
      before="$(tmux show-hooks -g client-resized)"
      attach_test_client
      "$LIVEPICKER_SCRIPTS/livepicker.sh" >/dev/null
      "$LIVEPICKER_SCRIPTS/input-handler.sh" cancel >/dev/null
      after="$(tmux show-hooks -g client-resized)"
      assert_eq "$after" "$before" "(c) client-resized restored byte-exact (set -b prior: index+flag+cmd)"

Task 5: VALIDATE (Level 1 + run the suite)
  - RUN: bash -n tests/test_scroll_width.sh            (expect exit 0, no output)
  - RUN: shellcheck tests/test_scroll_width.sh         (expect 0 findings)
  - RUN: grep -Pn '^    ' tests/test_scroll_width.sh   (expect empty — tabs only)
  - RUN: tests/run.sh                                  (expect: all 9 new tests PASS; no existing test FAILS)
```

### Implementation Patterns & Key Details

The complete, ready-to-paste file body (the implementer may use it as-is; the only
allowed deviation is comment phrasing):

```bash
#!/usr/bin/env bash
# shellcheck disable=SC2154,SC2016,SC2034,SC2086
#   SC2154: TEST_STATUS / fail / assert_* / setup_test / attach_test_client / tmux /
#           LIVEPICKER_SCRIPTS are provided by run.sh + helpers.sh + setup_socket.sh
#           (sourced before this file by run.sh). SC2016/SC2034/SC2086: the harness's
#           eval/single-quote + word-split idioms (mirrors test_functional.sh).
# tests/test_scroll_width.sh — tmux-livepicker scroll + client-width-cache validation
# suite (PRD §15.28 scroll/width items; §10 step 5 / §3.35 width source; §3.32 viewport+
# scroll; §16 width-cache-staleness). Drives the REAL plugin (livepicker.sh -> input-
# handler.sh -> renderer.sh -> restore.sh) on the isolated harness. scroll-into-view +
# the width cache are COMPLETE+shipping (P1.M3.T1/T2). See research/test_scroll_width_findings.md
# for the live captures behind every assertion.
#
# CONTRACT: run.sh sources setup_socket.sh + helpers.sh + every test_*.sh, then PER test
# calls setup_test "lp-$$-<name>" (-> fresh isolated -L socket + baseline fixtures, AND
# pins @livepicker-preview-defer OFF so nav/scroll are SYNCHRONOUS). So when a test_*
# runs: bare `tmux` hits the isolated socket; attach_test_client / $LIVEPICKER_SCRIPTS /
# fail / assert_* are IN SCOPE; this file SOURCES NOTHING and calls NO setup_test.
# set -u is INHERITED from helpers.sh (do NOT re-declare; mirror test_functional.sh).

# _lp_scroll_setup [width] — attach a pty client, seed ~8 wide-named sessions, activate
# the picker, and pin @livepicker-client-width (default 12 -> forces overflow so scroll
# advances on nav). The wide session names ("session-tab-N") + small width make the
# scroll-into-view write deterministic. Sessions are added BEFORE activate (the list is
# captured at activate time).
_lp_scroll_setup() {
	local width="${1:-12}"
	local i
	attach_test_client
	for i in $(seq 1 8); do
		tmux new-session -d -s "session-tab-$i" -x 120 -y 40
	done
	"$LIVEPICKER_SCRIPTS/livepicker.sh"
	tmux set-option -g @livepicker-client-width "$width"
}

# (a) PRD §3.32: next-session advances @livepicker-scroll so the viewport follows the
# highlight; the renderer emits the left overflow '<'. With width 0 (no windowing) the
# renderer drops '<' — proving it re-derives the slice against the cached width.
test_scroll_advances_on_nav() {
	_lp_scroll_setup 12
	local n sc out before
	before="$(tmux show-option -gqv @livepicker-scroll)"; [ -z "$before" ] && before=0
	for n in 1 2 3 4 5; do
		"$LIVEPICKER_SCRIPTS/input-handler.sh" next-session >/dev/null
	done
	sc="$(tmux show-option -gqv @livepicker-scroll)"
	[ -n "$sc" ] && [ "$sc" -gt 0 ] 2>/dev/null \
		|| fail "(a) scroll advanced >0 after 5 next-session (got [$sc], started [$before])"
	pass "(a) scroll advanced to $sc (width 12, 8 wide sessions)"
	out="$("$LIVEPICKER_SCRIPTS/renderer.sh")"
	assert_contains "$out" "<" "(a) renderer shows left overflow '<' when scroll>0"
	# viewport recompute: width 0 -> renderer renders the FULL list (no windowing, no '<').
	tmux set-option -g @livepicker-client-width 0
	out="$("$LIVEPICKER_SCRIPTS/renderer.sh")"
	case "$out" in *"<"*) fail "(a) width 0 should drop '<' (viewport recompute, no windowing)" ;; esac
	pass "(a) width 0 recomputes viewport (no '<' — full list)"
}

# (a-clamp) PRD §3.32 "clamp scroll=0 when the list fits": with a WIDE width the whole
# list fits, so lp_viewport clamps scroll to 0 even after nav, and the renderer has no '<'.
test_scroll_clamps_zero_when_fits() {
	_lp_scroll_setup 200
	local n sc out
	for n in 1 2 3 4 5; do
		"$LIVEPICKER_SCRIPTS/input-handler.sh" next-session >/dev/null
	done
	sc="$(tmux show-option -gqv @livepicker-scroll)"; [ -z "$sc" ] && sc=0
	assert_eq "$sc" "0" "(a-clamp) scroll stays 0 when the list fits (wide width)"
	out="$("$LIVEPICKER_SCRIPTS/renderer.sh")"
	case "$out" in *"<"*) fail "(a-clamp) renderer should NOT show '<' when the list fits" ;; esac
	pass "(a-clamp) no '<' when the list fits"
}

# (d) PRD §19 §3.32: typing resets the viewport scroll to the top (a status-only STATE write).
test_scroll_resets_on_type() {
	_lp_scroll_setup 12
	local n sc
	for n in 1 2 3 4 5; do
		"$LIVEPICKER_SCRIPTS/input-handler.sh" next-session >/dev/null
	done
	sc="$(tmux show-option -gqv @livepicker-scroll)"
	[ -n "$sc" ] && [ "$sc" -gt 0 ] 2>/dev/null || fail "(d) type: precondition scroll>0 not met (got [$sc])"
	"$LIVEPICKER_SCRIPTS/input-handler.sh" type x >/dev/null
	sc="$(tmux show-option -gqv @livepicker-scroll)"; [ -z "$sc" ] && sc=0
	assert_eq "$sc" "0" "(d) type resets scroll to 0"
}

# (d) PRD §19 §3.32: backspace resets the viewport scroll to the top.
test_scroll_resets_on_backspace() {
	_lp_scroll_setup 12
	"$LIVEPICKER_SCRIPTS/input-handler.sh" type x >/dev/null   # give backspace a char to trim
	local n sc
	for n in 1 2 3 4 5; do
		"$LIVEPICKER_SCRIPTS/input-handler.sh" next-session >/dev/null
	done
	sc="$(tmux show-option -gqv @livepicker-scroll)"
	[ -n "$sc" ] && [ "$sc" -gt 0 ] 2>/dev/null || fail "(d) backspace: precondition scroll>0 not met (got [$sc])"
	"$LIVEPICKER_SCRIPTS/input-handler.sh" backspace >/dev/null
	sc="$(tmux show-option -gqv @livepicker-scroll)"; [ -z "$sc" ] && sc=0
	assert_eq "$sc" "0" "(d) backspace resets scroll to 0"
}

# (d) PRD §6 Cancel (two-step): cancel with a NON-empty filter CLEARS the query and keeps
# the picker OPEN; that clear path also resets scroll to 0. The normal flow can't produce
# non-empty-filter + non-zero-scroll together (typing resets scroll), so seed both directly
# post-activate (state is picker-internal) and assert the clear path resets scroll + filter.
test_scroll_resets_on_cancel_clear() {
	_lp_scroll_setup 12
	tmux set-option -g @livepicker-filter "xx"
	tmux set-option -g @livepicker-scroll 5
	"$LIVEPICKER_SCRIPTS/input-handler.sh" cancel >/dev/null
	local sc fl mo
	sc="$(tmux show-option -gqv @livepicker-scroll)"; [ -z "$sc" ] && sc=0
	fl="$(tmux show-option -gqv @livepicker-filter)"
	mo="$(tmux show-option -gqv @livepicker-mode)"
	assert_eq "$sc" "0"  "(d) cancel-clear resets scroll to 0"
	assert_eq "$fl" ""   "(d) cancel-clear cleared the filter"
	assert_eq "$mo" "on" "(d) cancel-clear kept the picker OPEN (mode on)"
}

# (b) PRD §10 step 5 / §3.35: the client-resized hook runs `input-handler.sh refresh-width`,
# which re-caches @livepicker-client-width from the LIVE #{client_width}. Deterministic
# proof: seed a STALE width (999), fire refresh-width, assert it returns to the live value.
# (resize-window does NOT move client_width — it is pty-derived — so the action is the path.)
test_width_refresh_recaches_live() {
	attach_test_client
	"$LIVEPICKER_SCRIPTS/livepicker.sh" >/dev/null
	local live cached
	live="$(tmux display-message -p '#{client_width}' 2>/dev/null)"
	tmux set-option -g @livepicker-client-width 999        # simulate a stale cache
	"$LIVEPICKER_SCRIPTS/input-handler.sh" refresh-width >/dev/null
	cached="$(tmux show-option -gqv @livepicker-client-width)"
	assert_eq "$cached" "$live" "(b) refresh-width re-cached the LIVE client_width (was stale 999)"
	[ "$cached" != "999" ] || fail "(b) stale 999 survived refresh-width"
}

# (b) PRD §10 step 5: activate installs a client-resized hook that runs refresh-width.
# Assert the wiring (the hook fires refresh-width on a real resize; resize-window can't
# trigger it deterministically, so we assert the install + the action separately).
test_client_resized_hook_installed() {
	attach_test_client
	"$LIVEPICKER_SCRIPTS/livepicker.sh" >/dev/null
	local hk
	hk="$(tmux show-hooks -g client-resized)"
	assert_contains "$hk" "input-handler.sh" "(b) client-resized hook wired to input-handler.sh"
	assert_contains "$hk" "refresh-width"    "(b) client-resized hook runs the refresh-width action"
}

# (c) PRD §9 / §16 "width cache staleness": restore puts back the EXACT prior client-resized
# hook. UNSET prior: the baseline socket has client-resized bare/unset; a full activate ->
# cancel cycle must leave show-hooks byte-identical (no leak of our refresh-width hook).
test_client_resized_hook_restored_unset_prior() {
	local before after
	before="$(tmux show-hooks -g client-resized)"
	attach_test_client
	"$LIVEPICKER_SCRIPTS/livepicker.sh" >/dev/null
	"$LIVEPICKER_SCRIPTS/input-handler.sh" cancel >/dev/null
	after="$(tmux show-hooks -g client-resized)"
	assert_eq "$after" "$before" "(c) client-resized restored byte-exact (unset/bare prior)"
}

# (c) SET prior with -b: activate saves + clears + installs ours; cancel replays the saved
# client-resized[0] line preserving index + -b + verbatim command. Byte-identical before/after.
test_client_resized_hook_restored_set_prior() {
	tmux set-hook -g client-resized "run-shell -b /usr/bin/true"   # a user prior (-b, [0])
	local before after
	before="$(tmux show-hooks -g client-resized)"
	attach_test_client
	"$LIVEPICKER_SCRIPTS/livepicker.sh" >/dev/null
	"$LIVEPICKER_SCRIPTS/input-handler.sh" cancel >/dev/null
	after="$(tmux show-hooks -g client-resized)"
	assert_eq "$after" "$before" "(c) client-resized restored byte-exact (set -b prior)"
}
```

NOTE for the implementer: the block above is the COMPLETE, ready-to-paste file body.
Every assertion matches the live captures in `research/test_scroll_width_findings.md`.
Use it as-is; the only allowed deviation is comment phrasing. Do NOT add `set -e`. Do
NOT drive the width change via `resize-window` (research FINDING 5: it does not move
client_width). Do NOT assert the left `<` at index 0 (research FINDING 10: needs
scroll>0). Do NOT assert on §19 layout structure or §20 ranking order (siblings'
domains). Do NOT create any other file or touch any source.

### Integration Points

```yaml
HARNESS (how this file is consumed):
  - tests/run.sh sources setup_socket.sh + helpers.sh + every tests/test_*.sh (incl.
    this one), discovers test_* via compgen, and runs each in a per-test fresh-socket
    cycle (setup_test pins @livepicker-preview-defer OFF). This file is SOURCED.

CODE UNDER TEST (read-only — all COMPLETE + shipping):
  - scripts/input-handler.sh — _lp_scroll_into_view (scroll write); type/backspace/
    cancel-clear scroll reset; next/prev-session; refresh-width (width re-cache).
  - scripts/livepicker.sh — T2b client-width capture + client-resized hook install.
  - scripts/restore.sh — STEP-4 client-resized hook restore (byte-exact).
  - scripts/renderer.sh — viewport slice + overflow indicators (the '<' assertion target).
  - scripts/layout.sh — lp_viewport scroll math (shared by renderer + input-handler).

STATE WRITES (this task — on the isolated socket only, via the plugin itself or direct
seeds for the cancel-clear case):
  - @livepicker-client-width (pinned small/large; seeded stale 999 in the refresh test)
  - @livepicker-filter / @livepicker-scroll (seeded for the cancel-clear case)
  - All torn down by the harness (teardown_test kills the isolated socket) — ZERO impact
    on the user's real server (PRD §15 invariant).

STATE READS / TMUX MUTATIONS: none beyond the plugin's own (activate/nav/cancel/refresh)
+ read-only show-option/show-hooks/display-message. No switch-client by the TEST (the
plugin's cancel does one same-session switch — Invariant A preserved).

DATABASE / MIGRATIONS / ROUTES / CONFIG: none.
```

## Validation Loop

### Level 1: Syntax & Style (Immediate Feedback)

```bash
# Run after creating the file — fix before proceeding.
bash -n tests/test_scroll_width.sh                  # syntax; expect no output, exit 0
shellcheck tests/test_scroll_width.sh               # lint; expect 0 findings (file-level
                                                    # disable=SC2154,SC2016,SC2034,SC2086 covers it)
# Tabs-not-spaces sanity (shfmt NOT installed):
grep -Pn '^    ' tests/test_scroll_width.sh && echo "FAIL: 4-space indent found, use tabs" || echo "OK: tabs only"
# Confirm every test function is named test_scroll_*/test_width_*/test_client_resized_*:
grep -nE '^test_[a-z_]+\(\)' tests/test_scroll_width.sh
# Confirm NO set -e / set -o pipefail and NO setup_test call at file scope:
grep -nE 'set -e|pipefail|^\s*setup_test' tests/test_scroll_width.sh && echo "FAIL" || echo "OK"
# Run from the repo root.
```

### Level 2: Unit / Component Validation (the suite itself)

```bash
# Run the FULL suite (this file + every other test_*.sh). The 9 new functions must all
# PASS, and NO existing test may regress (this file touches no source).
tests/run.sh
# Expected: exit 0; summary line "N passed, 0 failed". The test_scroll_* / test_width_* /
# test_client_resized_* lines all PASS.
# To run ONLY this file's tests in isolation (handy while iterating), temporarily move the
# other test_*.sh aside — but the gate is the FULL run.sh (no regressions).
```

### Level 3: Integration Testing (drive the real plugin on an isolated socket)

```bash
# Manual spot-check mirroring test_scroll_advances_on_nav + test_width_refresh_recaches_live,
# on a throwaway isolated socket with a pty client. Self-cleaning.
SOCK="lp-scroll-manual-$$"; SHIM="$(mktemp -d)"
cat > "$SHIM/tmux" <<EOF
#!/usr/bin/env bash
exec /usr/bin/tmux -L "$SOCK" "\$@"
EOF
chmod +x "$SHIM/tmux"
trap '/usr/bin/tmux -L "$SOCK" kill-server 2>/dev/null; rm -rf "$SHIM"' EXIT
PATH="$SHIM:$PATH" tmux new-session -d -s driver -x 120 -y 40
for i in $(seq 1 8); do PATH="$SHIM:$PATH" tmux new-session -d -s "session-tab-$i" -x 120 -y 40; done
script -qec "tmux -L "$SOCK" attach -t driver" /dev/null >/dev/null 2>&1 & AP=$!; sleep 0.5
PATH="$SHIM:$PATH" bash scripts/livepicker.sh
PATH="$SHIM:$PATH" tmux set-option -g @livepicker-preview-defer off
PATH="$SHIM:$PATH" tmux set-option -g @livepicker-client-width 12
for n in 1 2 3 4 5; do PATH="$SHIM:$PATH" bash scripts/input-handler.sh next-session >/dev/null; done
echo "scroll after 5 next: [$(PATH="$SHIM:$PATH" tmux show-option -gqv @livepicker-scroll)] (want >0)"
out="$(PATH="$SHIM:$PATH" bash scripts/renderer.sh)"; printf 'renderer: %.200s\n' "$out"
case "$out" in *"<"*) echo "OK: renderer has '<'";; *) echo "FAIL: no '<'";; esac
kill "$AP" 2>/dev/null
# Expected: scroll > 0; renderer contains '<'.
```

### Level 4: Creative & Domain-Specific Validation

```bash
# Pollution spot-check (PRD §15 invariant): running the suite must NOT touch the user's
# REAL tmux server. The harness isolates every test on a -L socket; verify the real
# server's session list is byte-identical before/after.
REAL_BEFORE="$(/usr/bin/tmux list-sessions -F '#{session_name}' 2>/dev/null | sort)"
tests/run.sh >/dev/null 2>&1
REAL_AFTER="$(/usr/bin/tmux list-sessions -F '#{session_name}' 2>/dev/null | sort)"
[ "$REAL_BEFORE" = "$REAL_AFTER" ] && echo "OK: real server untouched (PRD §15)" \
  || echo "FAIL: real server polluted"
# Expected: OK — the harness isolates every test on tmux -L (setup_socket.sh).
```

## Final Validation Checklist

### Technical Validation

- [ ] `bash -n tests/test_scroll_width.sh` exits 0 with no output.
- [ ] `shellcheck tests/test_scroll_width.sh` reports 0 findings (file-level disable covers it).
- [ ] No 4-space indents (`grep -Pn '^    '` is empty); tabs only.
- [ ] All test functions named `test_scroll_*` / `test_width_*` / `test_client_resized_*`.

### Feature Validation

- [ ] File at `tests/test_scroll_width.sh`; file-level shellcheck disable; NO `set -e`.
- [ ] `_lp_scroll_setup [width]` defined (attach + 8 wide sessions + activate + pin width).
- [ ] **(a)** scroll-advances: scroll > 0 after nav (width 12); renderer `<`; width 0 drops `<`.
- [ ] **(a-clamp)** scroll-clamps: scroll == 0 after nav (width 200); no `<`.
- [ ] **(d)** type / backspace / cancel-clear each reset scroll to 0 (cancel-clear also
      clears filter + keeps mode on).
- [ ] **(b)** refresh-width: stale 999 → == live `#{client_width}`.
- [ ] **(b)** client-resized hook installed (show-hooks contains input-handler.sh + refresh-width).
- [ ] **(c)** client-resized restored byte-exact for unset prior AND set `-b` prior.
- [ ] `tests/run.sh` runs all 9 and they PASS; no existing test breaks.

### Code Quality Validation

- [ ] NO `set -e`, NO `set -o pipefail` (house style; helpers/setup_socket).
- [ ] Failure signaled ONLY via `fail`/`assert_*` (never exit/return-nonzero).
- [ ] All expansions double-quoted; `local` for all function locals.
- [ ] Width change driven via the refresh-width ACTION + direct seed (NOT `resize-window`).
- [ ] The left `<` is asserted only after scroll>0 (nav or seed), never at index 0.
- [ ] No new source files; no edit to any `scripts/*.sh`.

### Documentation & Deployment

- [ ] Header comment states: purpose (PRD §15.28 scroll + width-cache); the harness idiom
      (per-test setup_test + defer OFF); the resize-window caveat (use the action); the
      reference to research/test_scroll_width_findings.md.
- [ ] No README/doc file created (DOCS = Mode A; covered by README P4.T1).
- [ ] No tmux.conf edit; no other test file touched.

---

## Anti-Patterns to Avoid

- ❌ Don't drive the width change via `tmux resize-window`. `#{client_width}` is the
  client's PTY width, not the window grid; `resize-window` leaves it unchanged and does
  NOT fire `client-resized` (research FINDING 5). Seed the width directly + exercise the
  `refresh-width` ACTION (the item's sanctioned "directly invoking the hook's refresh").
- ❌ Don't assert the renderer's left `<` at index 0. `lp_viewport` with scroll=hl=0 +
  overflow yields `LPV_HIDDEN_LEFT=0` (no left indicator; only the right `+N>` shows)
  (research FINDING 10). Navigate DOWN first (scroll>0) or seed `@livepicker-scroll>0`.
- ❌ Don't assert on a hardcoded styled `<` substring like `#[fg=default,bg=default]<#[default]`.
  The test socket sources the user conf → `@livepicker-fg "#ffffff"`, so the wrapper is
  `#[fg=#ffffff,bg=default]<#[default]`. Assert the RAW `<` presence (no tab name contains
  `<` in the fixture) (research FINDING 1). For absence, use an inline `case`.
- ❌ Don't rely on the live client_width being a specific number. Capture it DYNAMICALLY
  via `tmux display-message -p '#{client_width}'` and compare the re-cached value to THAT
  (research FINDING 4). The pty width is whatever the runner's terminal is.
- ❌ Don't seed sessions AFTER activate. `@livepicker-list` is captured at activate time
  (`list-sessions`). Add the wide sessions in `_lp_scroll_setup` BEFORE `livepicker.sh`.
- ❌ Don't test the cancel-clear scroll reset via the normal flow. Typing resets scroll,
  so non-empty-filter + non-zero-scroll never co-occur naturally. SEED both directly
  post-activate and assert the clear path resets them (research FINDING 3).
- ❌ Don't hardcode the client-resized prior. Capture `show-hooks -g client-resized`
  DYNAMICALLY before activate and assert `after == before`. Test BOTH the bare (unset)
  and a seeded `-b` prior in two functions (research FINDING 7).
- ❌ Don't `exit` or `return-nonzero` to signal failure. run.sh reads `TEST_STATUS` in the
  CURRENT shell; an exit kills the runner. Use `fail`/`assert_*` only.
- ❌ Don't flip `@livepicker-preview-defer` on. `setup_test` pins it OFF so nav/scroll are
  synchronous; `test_responsiveness.sh` owns the defer-on path. The scroll writes are
  status-only STATE writes regardless.
- ❌ Don't assert on §19 layout structure (gap/overflow-FORMAT/count) or §20 ranking order.
  Those are `test_layout.sh`'s / `test_ranking.sh`'s domains. This file asserts SCROLL
  dynamics + WIDTH-CACHE only.
- ❌ Don't create a `tests/` collision or touch any source. This is ONE new sourced test
  file. Use `set -u` inherited from helpers.sh; TABS for indent.

---

## Confidence Score

**9 / 10** for one-pass success. Rationale: the deliverable is ONE new sourced test file
whose complete body is given verbatim in the Implementation Blueprint and whose every
assertion was validated LIVE on `tmux 3.6b` against an isolated socket with a pty client
driving the REAL plugin: `bash -n` clean, `shellcheck` 0 findings, and every captured
state/output matches (scroll→5 + renderer `<`+`+8>` at width 12; scroll→0 on
type/backspace/cancel-clear; refresh-width 999→live; client-resized hook installed at
`[0]`→refresh-width; restore byte-exact for both unset and set-`-b` priors). The code
under test (P1.M3.T1 client-width + P1.M3.T2 scroll) is COMPLETE and shipping despite
the plan_status "Planned" label on T2. The two highest-risk traps are explicitly
sidestepped: (1) `resize-window` does not move `client_width` → the width cache is
validated via the refresh-width action + hook-install assertion (research FINDING 5); (2)
the renderer's left `<` requires scroll>0 → asserted only after nav (research FINDING 10).
Residual risks: (a) the in-flight siblings (`test_layout.sh`, `test_ranking.sh`) sharing
the `test_*` namespace — mitigated by the distinct `test_scroll_*`/`test_width_*`/
`test_client_resized_*` prefixes; (b) the pty client's actual width varying by runner —
mitigated by capturing it DYNAMICALLY and comparing the re-cached value to that capture
(never a hardcoded number); (c) a conf-set client-resized prior on some other machine —
mitigated by the dynamic before/after compare (robust to any prior). All residual risks
are deterministically caught by the validation loop.
