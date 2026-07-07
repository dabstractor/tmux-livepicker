# Research: tests/test_appearance.sh — PRD §15.24 window-status tab validation

> Ground-truth for writing `tests/test_appearance.sh` (P1.M3.T2.S1). All paths are
> relative to the repo root `/home/dustin/.config/tmux/plugins/tmux-livepicker`.
> Every claim below is either grep/read-confirmed against the LANDED code or
> empirically verified on an isolated `-L` socket.

## 1. What landed (the SUT + its two halves — both COMPLETE per plan_status)

PRD §17 is implemented in two halves; this test file bridges them:

- **WRITER** — `scripts/livepicker.sh::_lp_resolve_tab_templates` (P1.M1.T2.S1).
  Called inside `activate_main` between the first-preview `if`-block and
  `set_state "$STATE_MODE" "on"`. Gated on `opt_tab_style == "window-status"`. Reads
  `window-status-current-format` / `window-status-format` via `show-options -gwv`,
  resolves both fully against a hidden `__lp_tab__` sentinel window via
  `display-message -p -t "$sent_sess:__lp_tab__"`, kills the sentinel, and caches
  the two rendered templates into `@livepicker-tab-current-tmpl` /
  `@livepicker-tab-inactive-tmpl`. **On ANY failure it `set_state ""` BOTH keys**
  (real `tmux set-option -g @x ""`, NOT unset) so the renderer falls back to plain.
  Plain mode is a no-op (early `return 0`; cache untouched). ALWAYS returns 0.

- **READER** — `scripts/renderer.sh::render()` (P1.M1.T3.S1). A self-contained
  `if [ "$(opt_tab_style)" = "window-status" ]` block inserted between the
  `SHOW_COUNT` case and the plain `LIST=` read. Enters the inner body only when
  **BOTH** `STATE_TAB_CURRENT_TMPL` and `STATE_TAB_INACTIVE_TMPL` are non-empty
  (`get_state` + `[ -n ]`). If either is empty → **falls through to the unchanged
  plain path**. In the body: reads `STATE_LIST/FILTER/INDEX` + `window-status-separator`
  (`show-options -gwv`, default space); builds the filtered list via the shared
  `lp_build_filtered`; the highlighted index (`cidx`) gets the CURRENT template, the
  rest the INACTIVE template; each does `${ws_tpl//__lp_tab__/$esc_wname}` (the name
  `#`-escaped to `##` BEFORE substitution); segments joined with `$ws_sep`;
  `SHOW_COUNT` suffix mirrored; `printf '%s' "$ws_out"; return 0`. The plain path
  (from `LIST=` to the final `printf`) is byte-identical to the pre-§17 code.

- **FOUNDATION** — `scripts/options.sh::opt_tab_style()` (P1.M1.T1.S1) returns
  `@livepicker-tab-style` or `"plain"` (default; enum `plain|window-status`).
  `scripts/state.sh` defines `STATE_TAB_CURRENT_TMPL`/`STATE_TAB_INACTIVE_TMPL` and
  BOTH are in `_STATE_RUNTIME_KEYS` → `clear_all_state` clears them on restore.

Grep-confirmed present (run at research time):
```
$ grep -c opt_tab_style scripts/options.sh            # 1
$ grep -c STATE_TAB_CURRENT_TMPL scripts/state.sh     # 1 (+ _STATE_RUNTIME_KEYS membership)
$ grep -c _lp_resolve_tab_templates scripts/livepicker.sh   # 3 (comment + def + call)
$ grep -c '__lp_tab__' scripts/renderer.sh            # 1 (the swap site)
```

## 2. THE load-bearing empirical fact: `display-message -p` PRESERVES `#[...]`

external_tmux_behavior.md Q2's note "display-message -p … does not apply #[…] as
terminal escapes (it strips/ignores styling)" is **ambiguous** and一度 risked
invalidating the whole §17 mechanism. **Empirically verified FALSE for "strips"**:
`display-message -p` keeps the literal `#[…]` text verbatim in stdout; it merely
does not convert it to ANSI escape codes. Proven on an isolated socket:

```
$ /usr/bin/tmux -L lp_probe -L ... display-message -p -t "s0:__lp_tab__" '#[fg=red,bold]#W#[default]'
#[fg=red,bold]__lp_tab__#[default]          # <- #[...] styles INTACT, #W -> __lp_tab__
$ ... '#[fg=#7aa89f]#W#[default]'
#[fg=#7aa89f]__lp_tab__#[default]           # <- hex colors preserved verbatim
```

**Consequence for the tests:** the cached templates the writer produces DO contain
literal `#[…]` styles (with `__lp_tab__` where `#W` was). So:
- `assert_contains` on `#[fg=red,bold]beta#[default]` (the swapped styling) is a
  VALID, deterministic assertion — the bytes are real, not stripped.
- The end-to-end test (e) can `assert_eq` the exact resolved template
  (`#[fg=red,bold]__lp_tab__#[default]`) because the resolution is byte-exact.
- `#()` status-command output then has those `#[…]` applied as styling by tmux's
  status processor (Q2 positive: `#[…]` IS applied to `#()` output) — this is WHY
  pre-resolution works and is the whole point of §17.

## 3. The isolated-socket config quirks (determinism hazards — tests MUST override)

The isolated socket **sources the user's `tmux.conf`** (tubular, on this machine).
Two dormant values land and would make naive assertions environment-dependent:

- **`@livepicker-fg "#ffffff"`** (and `@livepicker-key Space`) are pre-set
  (test_functional.sh header FINDING 2). So `opt_fg()` returns `#ffffff`, NOT the
  `"default"` PRD default. **Any plain-path assertion on `#[fg=$FG,…]` is
  non-deterministic unless the test sets `@livepicker-fg` itself.**
- **`window-status-separator`** is set by tubular to a glyph (probed: the default on
  the isolated socket is a non-ASCII narrow-space-ish char, NOT a plain ASCII space).
  The renderer reads it via `show-options -gwv` and defaults to a space only when
  EMPTY. **A window-status test that does not set the separator gets tubular's glyph
  between tabs → the inter-item gap assertion is non-deterministic.**

**Mitigation (baked into every test):** a `lp_appearance_seed` helper pins
`@livepicker-fg/bg/highlight-fg/highlight-bg` + `@livepicker-show-count off` +
`@livepicker-type` + `@livepicker-list/filter/index` to deterministic values, and
each window-status test sets `window-status-separator` explicitly. This makes every
assertion independent of the user's config.

## 4. The two-approach split (item §1) — direct-seed vs full-activate

The renderer is **CLIENT-INDEPENDENT** (PURE: reads options/state, prints one line,
zero tmux mutations; test_harness.md §4 + the appearance note). So the renderer's
swap/join/fallback logic can be tested by seeding `@livepicker-*` state directly and
running `$LIVEPICKER_SCRIPTS/renderer.sh` — **NO `attach_test_client`** (mirror
`test_functional.sh::test_renderer_escapes_hash_*`, the existing precedent).

- **Approach (b) — direct-seed (tests a–d):** seed `@livepicker-tab-current-tmpl` /
  `@livepicker-tab-inactive-tmpl` directly with already-resolved templates
  (`#[fg=red,bold]__lp_tab__#[default]`), bypassing the writer entirely. The
  renderer reads ONLY the cache keys (never `window-status-current-format`), so the
  raw window option need NOT be set. Cleanest unit coverage of the reader.
- **Approach (a) — full-activate (test e):** `attach_test_client` (MANDATORY —
  activate needs a client for `lp_client_format` ORIG_SESSION capture +
  `refresh-client -S`) → set `window-status-current-format`/`window-status-format`
  via `-gw` → `livepicker.sh` → assert the writer populated the cache correctly +
  the sentinel was killed + the reader swaps the names end-to-end. The ONLY test
  that exercises the writer + the writer↔reader integration.

Note: `display-message -p` (used by the writer) is itself client-less (Q1's
isolated-socket probe ran it with no client attached); but a FULL `activate` is not
(client-dependent steps). Hence test (e) attaches.

## 5. The harness contract (test_harness.md, distilled — same as P1.M3.T1.S1)

- `run.sh` sources `setup_socket.sh` + `helpers.sh` + every `tests/test_*.sh`
  (via nullglob `source test_*.sh`); discovers `test_*` via `compgen -A function |
  grep '^test_' | sort` in the CURRENT shell; per test calls `setup_test
  "lp-$$-<name>"` (fresh isolated socket + PATH shim + baseline driver/alpha/beta) →
  resets `TEST_STATUS=pass` → runs the test in the current shell → reads
  `TEST_STATUS` → `teardown_test`.
- **The COMPLETE assert API:** `fail msg`, `pass msg`, `assert_eq a b msg`,
  `assert_contains str sub msg` (`$sub` is QUOTED in the `case` pattern → literal,
  glob-safe). **No** `assert_not_contains`/`assert_match`/`assert_rc`. Negatives use
  inline `case "$x" in *<bad>*) fail … ;; esac`. A helper returning rc uses
  `helper || fail …`.
- **Signal failure ONLY via `fail`/`assert_*`** (they set `TEST_STATUS=fail`). NEVER
  `exit`, NEVER `return` nonzero (kills `run.sh`). Early `return 0` to skip is fine.
- **Non-test helpers MUST NOT start with `test_`** (or `compgen` runs them). Use the
  `lp_` prefix (`lp_appearance_seed` — mirrors `lp_preview_seed_state`,
  `lp_runtime_cleared`).
- `set -u` is INHERITED (do NOT re-declare; declare every `local`). TABS for indent
  (shfmt absent). The file SOURCES NOTHING and calls NO `setup_test`/`teardown_test`
  at file scope. shellcheck disable line: `SC2154,SC2016,SC2034,SC2086`.
- The renderer tests need NO `setup_test`-internal override (the baseline
  driver/alpha/beta are irrelevant — the tests seed `@livepicker-list` directly).
  `test_renderer_escapes_hash_*` in test_functional.sh uses an internal `setup_test`
  only because it needs a `#dev` session name; we do not.

## 6. The 5 test designs → deterministic assertions

| # | Function | What it proves | Approach | Key assertions |
|---|----------|----------------|----------|----------------|
| a | `test_window_status_highlight_uses_current_format` | §17 Mapping: highlighted item → current template; others → inactive | direct-seed | `assert_contains` `#[fg=red,bold]beta#[default]` (beta@idx1 current); `#[fg=blue]alpha#[default]` + `#[fg=blue]driver#[default]` (inactive); neg: no `__lp_tab__`, no `#[fg=blue]beta` |
| b | `test_window_status_separator` | §17: inter-item gap == `window-status-separator` | direct-seed | `assert_eq` EXACT joined output with sep `|` between 3 segments |
| c | `test_empty_template_falls_back_to_plain` | §17 Fallback / §16: empty cache → plain path | direct-seed | current template EMPTY + tab-style window-status → `assert_contains` `#[fg=black,bg=yellow]beta#[default]` (plain highlight); neg: no `#[fg=blue]` (template), no `__lp_tab__` |
| d | `test_tab_style_plain_unchanged` | §17 Control: plain mode → unchanged plain path | direct-seed | `assert_eq` EXACT plain output (byte-identical to c's fallback, proving plain==fallback); neg: no `__lp_tab__` |
| e | `test_sentinel_resolution_end_to_end` | §17 Resolution: activate resolves formats → cache + kills sentinel + reader swaps | full-activate | `assert_eq` cache == resolved templates (`#[fg=red,bold]__lp_tab__#[default]`); no `__lp_sent_*` in list-sessions; renderer `assert_contains` `#[fg=red,bold]` + a name; neg: no `__lp_tab__`, no `#{` |

**Determinism guarantees:** every test pins `@livepicker-fg/bg/highlight-*/type/
show-count` via `lp_appearance_seed`; (a)–(d) seed `@livepicker-list/filter/index`
+ cache + `window-status-separator` directly (renderer-only, no client); (e) sets
the raw `window-status-*-format` via `-gw` + `show-count off` before activate.
`show-count off` everywhere → no query suffix → exact-output `assert_eq` is safe.

## 7. Reliability / non-flakiness checklist

- (a)–(d) are PURE renderer invocations (subprocess `$(...renderer.sh)`): fully
  synchronous, no race, no client, no async job. Zero flakiness surface.
- (e) drives a synchronous `activate` (`livepicker.sh` returns only after the
  sentinel is created+resolved+killed); the post-activate `list-sessions` /
  `show-option` / `renderer.sh` reads are all immediate. No polling needed.
- (e) sets `@livepicker-preview-defer`? `setup_test` pins it OFF (helpers.sh); (e)
  does not opt in, so the first preview is synchronous → no async race. (The §18
  defer path is exercised ONLY by test_responsiveness.sh.)
- No hardcoded window ids (appearance tests assert on renderer STDOUT strings, not
  tmux window state) → robust to `renumber-windows`/global-id drift.
- Negatives use inline `case`+`fail` (the API has no `assert_not_contains`).

## 8. Sources / cross-refs

- `plan/002_facc52335e68/architecture/test_harness.md` §2/§3/§4 + appearance entry points.
- `plan/002_facc52335e68/architecture/codebase_state.md` §4 (renderer contract: one line, no trailing newline, `#[…]` segments).
- `plan/002_facc52335e68/architecture/external_tmux_behavior.md` Q1/Q2/Q3/Q4 (sentinel resolution + the `#[…]`-in-`#()` rule).
- `plan/002_facc52335e68/P1M1T2S1/PRP.md` (the writer; set-empty contract).
- `plan/002_facc52335e68/P1M1T3S1/PRP.md` (the reader; get_state+`[ -n ]` gate; `#`-escape-before-substitution).
- `plan/002_facc52335e68/P1M3T1S1/PRP.md` (the sibling test file — identical harness contract + style to mirror).
- `tests/test_functional.sh::test_renderer_escapes_hash_*` (the renderer-only test idiom).
- Empirical probes run on `tmux -L lp_probe_*` (this session): `display-message -p`
  preserves `#[…]`; default `window-status-separator` is a tubular glyph on the
  isolated socket.
