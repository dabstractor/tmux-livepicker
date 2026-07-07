# PRP — P1.M3.T2.S1: tests/test_appearance.sh — PRD §15.24 window-status tab validation

> **Scope**: Test-ONLY. Creates `tests/test_appearance.sh` (one new file, no
> production code). Validates PRD §17's theme-matched-tab render path (PRD §15.24):
> when `@livepicker-tab-style=window-status` the renderer emits the picker list
> through the cached `window-status[-current]-format` templates (highlighted index →
> current template, rest → inactive, `__lp_tab__` swapped → each `#`-escaped session
> name, joined by `window-status-separator`); empty templates / plain mode fall back
> to the unchanged plain path. Both halves of §17 are LANDED — the WRITER
> (`livepicker.sh::_lp_resolve_tab_templates`, P1.M1.T2.S1) and the READER
> (`renderer.sh` window-status block, P1.M1.T3.S1). This task consumes them.

---

## Goal

**Feature Goal**: A new `tests/test_appearance.sh`, sourced by `run.sh`, that
deterministically validates the five §17 behaviors (PRD §15.24): (a) the highlighted
item renders through `window-status-current-format`, every other through
`window-status-format`; (b) the inter-item gap is `window-status-separator`; (c) an
empty cached template falls back to the plain path; (d) plain mode is byte-identical
to the pre-§17 plain path (and to the (c) fallback); (e) a full `activate` resolves
the theme formats into the cache, kills the sentinel (no leak), and the reader swaps
the names end-to-end. Tests (a)–(d) are client-independent renderer unit tests
(direct-seed); (e) is the writer↔reader integration test (full activate).

**Deliverable**: The single file `tests/test_appearance.sh` — a sourced library
defining 5 `test_*` functions (auto-discovered by `run.sh` via `compgen`) + 1
`lp_appearance_seed` helper (non-`test_`-prefixed → not auto-run). No production code
change, no other test file touched, no new fixture machinery.

**Success Definition**:
- `bash -n tests/test_appearance.sh` clean; `shellcheck` 0 new findings.
- `bash tests/run.sh` exits 0 with all 5 new tests printing PASS (and the existing
  suite still green).
- (a)–(d) run renderer.sh on directly-seeded state (NO `attach_test_client`) and
  assert exact/substring styling; (e) drives a real `activate` (`attach_test_client`
  + `livepicker.sh`), asserts the cache is populated with the resolved templates +
  no sentinel leaked.
- Every test is deterministic (the `lp_appearance_seed` helper pins
  `@livepicker-fg/bg/highlight-*/type/show-count` so the user's `tmux.conf` — which
  sources on the isolated socket, setting `@livepicker-fg "#ffffff"` — cannot shift
  the plain-path style bytes).

## User Persona (if applicable)

**Target User**: The maintainer / automated QA (CI). Not end-user facing.

**Use Case**: A maintainer runs `bash tests/run.sh` to validate the §17 contract did
not regress (e.g. someone broke the renderer's `__lp_tab__` swap, the empty-template
fallback, or the sentinel resolution in activate). Each PASS proves one §17 facet on
an isolated socket.

**Pain Points Addressed**: Before this task, the §17 render path (P1.M1.T3.S1) and
the sentinel resolution (P1.M1.T2.S1) are validated only by throwaway smokes (deleted
after). The committed suite runs `tab-style=plain` (the default) for every test, so a
regression in the window-status branch, the template-cache seam, or the sentinel
resolution would slip through. This file is the permanent, committed guard for PRD
§15.24.

## Why

- **PRD §15.24 mandates it.** The validation cluster "Appearance (window-status
  hijack)" requires tests proving the §17 mapping, separator, fallback, and control.
- **The seam is subtle and regress-prone.** The writer caches two resolved templates
  with a `__lp_tab__` placeholder; the reader swaps that placeholder → each session
  name (`#`-escaped) and joins with the separator. A wrong swap, a missing
  `#`→`##` escape, a broken empty-fallback, or a sentinel that leaks would each
  silently break the appearance (or pollute the session list). These tests pin all
  five shapes.
- **The existing suite cannot cover this.** It runs `tab-style=plain` (the default) →
  the renderer's window-status `if`-block is never entered → the swap/join/cache path
  is untested. (e) additionally is the only committed test that drives the sentinel
  resolution in a real `activate`.
- **Cheap, isolated, zero prod risk.** One new test file; no script edits; disjoint
  from every production task. Auto-discovered by `run.sh`.

## What

A single new file `tests/test_appearance.sh`, sourced by `run.sh`, defining:

1. One helper `lp_appearance_seed <list> [filter] [index]` — pins the deterministic
   `@livepicker-*` base state the renderer reads (colors/type/show-count + the
   list/filter/index), so tests are independent of the user's `tmux.conf`.
2. Five `test_*` functions (a–e). (a)–(d): call `lp_appearance_seed`, set
   `@livepicker-tab-style` + the cache templates + `window-status-separator` as
   needed, run `$LIVEPICKER_SCRIPTS/renderer.sh`, assert via `assert_eq`/
   `assert_contains` + inline `case`+`fail`. (e): `attach_test_client` → set
   `@livepicker-tab-style window-status` + raw `window-status-*-format` via `-gw` →
   `livepicker.sh` → assert the cache + no sentinel leak + the renderer output.

### Success Criteria

- [ ] File at `tests/test_appearance.sh`; shebang `#!/usr/bin/env bash`; header
      documents the run.sh sourcing contract + the renderer-is-client-independent
      note + the direct-seed-vs-full-activate split.
- [ ] Defines `lp_appearance_seed` (non-`test_` prefix) + 5 `test_*` functions.
- [ ] (a) `test_window_status_highlight_uses_current_format`: beta@idx1 → current
      template styling; alpha/driver → inactive; no `__lp_tab__`/`#[fg=blue]beta`.
- [ ] (b) `test_window_status_separator`: `assert_eq` the EXACT joined output with
      `window-status-separator='|'` between 3 segments.
- [ ] (c) `test_empty_template_falls_back_to_plain`: empty current template +
      `tab-style=window-status` → plain-path styling; no template styling leaks.
- [ ] (d) `test_tab_style_plain_unchanged`: `tab-style=plain` → `assert_eq` the exact
      plain output (byte-identical to (c)'s fallback).
- [ ] (e) `test_sentinel_resolution_end_to_end`: activate resolves the cache to the
      exact templates; no `__lp_sent_*` session leaked; renderer output carries the
      resolved styling + a swapped name; no `__lp_tab__`/`#{`.
- [ ] `bash -n` clean; `shellcheck` 0 new findings; `bash tests/run.sh` exit 0 with
      all 5 new tests PASS + existing suite green.

## All Needed Context

### Context Completeness Check

_Pass_: an implementer who has never seen this repo can do it from (a) the verbatim
test file body in the Implementation Blueprint (copy-paste), (b) the empirical
ground-truth that `display-message -p` preserves `#[…]` styles (research §2), (c) the
isolated-socket config quirks (`@livepicker-fg="#ffffff"`, tubular separator) that the
`lp_appearance_seed` helper neutralizes (research §3), and (d) the harness contract
(sourced by run.sh; assert API; attach_test_client only for (e)). No inference
required.

### Documentation & References

```yaml
# MUST READ — the empirical ground-truth for THIS task (the load-bearing #[...] fact + config quirks + 5 designs)
- docfile: plan/002_facc52335e68/P1M3T2S1/research/appearance_test_findings.md
  why: §1 (both §17 halves LANDED, grep-confirmed); §2 (THE fact: display-message -p PRESERVES #[…] in stdout
       — so assert_contains on #[fg=red,bold]beta#[default] is a real, deterministic assertion); §3 (isolated
       socket sources tmux.conf -> @livepicker-fg "#ffffff" + a tubular separator -> lp_appearance_seed pins
       deterministic values); §4 (direct-seed for a-d, full-activate for e); §5 (harness contract); §6 (5 designs).
  critical: §2 + §3 are load-bearing — without "display-message -p keeps #[…]" the style assertions look wrong,
            and without pinning fg/separator the plain-path + gap assertions are non-deterministic.

# MUST READ — the READER contract (the SUT for a-d; treat as implemented exactly)
- docfile: plan/002_facc52335e68/P1M1T3S1/PRP.md
  why: the renderer window-status block. Entered when opt_tab_style==window-status AND BOTH cache keys
       non-empty (get_state + [ -n ]); else falls through to the UNCHANGED plain path. Swaps __lp_tab__ ->
       each #-escaped name (# -> ## BEFORE substitution); joins with window-status-separator (show-options -gwv,
       default space); SHOW_COUNT suffix mirrored; printf '%s' (one line, no trailing newline).
  critical: the renderer reads STATE_TAB_CURRENT_TMPL/INACTIVE_TMPL (the CACHE), NOT window-status-current-format.
            So the direct-seed tests (a-d) set the CACHE KEYS directly and need NOT set the raw window option.

# MUST READ — the WRITER contract (what populate the cache test e asserts)
- docfile: plan/002_facc52335e68/P1M1T2S1/PRP.md
  why: _lp_resolve_tab_templates: at activate, resolves window-status[-current]-format against a hidden
       __lp_tab__ sentinel via display-message -p, caches both templates; on ANY failure set_state "" BOTH
       (real set-empty). Gated on tab-style==window-status; plain mode is a no-op. ALWAYS returns 0.
       Its L2 smoke (resolve _lp_resolve_tab_templates directly, no full activate) proves display-message
       works client-less — but a FULL activate needs a client (lp_client_format + refresh-client -S).
  critical: the resolved template for "#[fg=red,bold]#W#[default]" is EXACTLY "#[fg=red,bold]__lp_tab__#[default]"
            (empirically verified, research §2) -> test (e) can assert_eq it byte-for-byte.

# MUST READ — the external-behavior rationale (Q1/Q2 are load-bearing for WHY)
- docfile: plan/002_facc52335e68/architecture/external_tmux_behavior.md
  why: Q1 (display-message -p -t <sentinel> "$value" expands the full #{…} tree incl. E: + #W -> the sentinel name);
       Q2 (#() stdout is NOT re-parsed for #{…} but #[…] IS applied — why pre-resolution is needed; AND the note
       that display-message -p "strips/ignores styling" is re-clarified in research §2 to mean "keeps #[…] literal,
       just no ANSI conversion"); Q3 (2-window hidden sentinel session); Q4 (clean window-state specifiers).
  section: "Q1", "Q2", "Q3", "Q4"

# MUST READ — the harness contract (how run.sh discovers + runs tests; the COMPLETE assert API)
- docfile: plan/002_facc52335e68/architecture/test_harness.md
  why: §2 (run.sh sources setup_socket+helpers+test_*.sh; discovers test_* via compgen in the CURRENT shell;
       per-test setup_test/teardown_test); §3 (fail/pass/assert_eq/assert_contains + inline case+fail for
       negatives; NEVER exit); §4 (test_functional.sh is the structural template; the test_renderer_escapes_hash_*
       functions are the EXACT renderer-only idiom this file mirrors — seed options, run renderer.sh, assert_contains,
       NO attach_test_client); the appearance entry points note (renderer is client-independent).
  critical: tests signal failure ONLY via fail/assert_* (set TEST_STATUS); a bare exit kills run.sh. Non-test
            helpers MUST be prefixed lp_ (or non-test_) so compgen does not discover them.

# MUST READ — the renderer-output contract (one line, no trailing newline, #[…] segments)
- docfile: plan/002_facc52335e68/architecture/codebase_state.md
  why: §4 documents renderer.sh's output: printf '%s' (NO trailing newline — multi-line #() renders last only);
       #[default] after every segment; mapfile via process-substitution; the #->## display escape. The exact plain
       output bytes the assert_eq in (c)/(d) must match.
  section: "## 4. renderer.sh"

# MUST READ — the structural + renderer-test idiom template
- file: tests/test_functional.sh
  why: the exact pattern to mirror for (a)-(d) — header contract block; seed @livepicker-* options DIRECTLY;
        run "$LIVEPICKER_SCRIPTS/renderer.sh"; assert_contains + inline case+fail for negatives. NO attach_test_client
        (renderer is client-independent). And test_activate_grows_status / test_escape_restores for (e)'s
        attach+activate lifecycle.
  pattern: test_renderer_escapes_hash_in_names / test_renderer_escapes_hash_in_filter (the renderer-only idiom);
           test_activate_grows_status (attach+activate+assert), test_escape_restores (capture orig dynamic, cancel).

# MUST READ — the activation origin + attach_test_client (for test e)
- file: tests/setup_socket.sh
  why: attach_test_client [sess="driver"] (spawns a script pty, sleep 0.5 — MANDATORY for activate's
        lp_client_format + refresh-client -S); baseline fixtures (driver/alpha/beta). TEST_DRIVER_SESSION="driver".
  gotcha: setup_test (helpers.sh) pins @livepicker-preview-defer OFF — (e) does not opt in, so activate's first
          preview is synchronous (no async race). Fine for appearance; the defer path is test_responsiveness.sh.

# MUST READ — PRD §17 (the feature spec) + §15.24 (the validation cluster) + §16 (the fallback mandate)
- docfile: PRD.md
  why: §17 (the sentinel resolution, the placeholder swap, the separator join, the plain fallback, the Control);
       §15.24 names the Appearance cluster; §16 "window-status hijack fragility" mandates the plain fallback on
       any resolution failure (-> empty template -> plain, which (c) tests).
  section: "§17 Tab appearance", "§15.24 Appearance", "§16 Implementation risks"
```

### Current Codebase tree

```bash
tmux-livepicker/
  tests/
    run.sh                  # UNCHANGED — auto-sources test_*.sh via nullglob; discovers test_*
    setup_socket.sh         # UNCHANGED — attach_test_client + baseline fixtures (driver/alpha/beta)
    helpers.sh              # UNCHANGED — fail/pass/assert_eq/assert_contains; setup_test (pins defer=off)
    test_functional.sh      # UNCHANGED — the renderer-only idiom template (test_renderer_escapes_hash_*)
    test_preview.sh, test_pollution.sh, test_restore.sh, test_create.sh, test_keyrepurpose.sh, test_self.sh  # UNCHANGED
    test_responsiveness.sh  # (P1.M3.T1.S1, parallel sibling) — the §18 tests; disjoint from this file
    test_appearance.sh      # NEW (this task) — the 5 §15.24 / §17 tests
  scripts/                  # UNCHANGED (all §17 deps landed: renderer/options/state/livepicker)
```

### Desired Codebase tree with files to be added and responsibility of file

```bash
tests/test_appearance.sh   # NEW. 5 test_* functions (a-e) + lp_appearance_seed helper. Sourced by run.sh.
                           #   (a)-(d): client-independent renderer unit tests (direct-seed the cache).
                           #   (e): full-activate integration test (writer resolves -> cache -> reader swaps).
                           #   Validates PRD §15.24 / §17.
```

### Known Gotchas of our codebase & Library Quirks

```bash
# CRITICAL (research §2): display-message -p PRESERVES #[...] style directives verbatim in stdout
# (the Q2 "strips styling" note means "no ANSI conversion", NOT "removes the #[...] text"). Proven:
#   '#[fg=red,bold]#W#[default]' -> '#[fg=red,bold]__lp_tab__#[default]'. So assert_contains on
#   '#[fg=red,bold]beta#[default]' is a REAL assertion (the bytes are there, not stripped). This is also
#   why test (e) can assert_eq the exact resolved template byte-for-byte.

# CRITICAL (research §3): the isolated socket SOURCES the user tmux.conf (tubular). Two dormant values land:
#   - @livepicker-fg "#ffffff" (NOT the "default" PRD default) -> opt_fg() returns #ffffff unless overridden.
#   - window-status-separator = a tubular GLYPH (NOT a plain ASCII space) -> the renderer's inter-item gap.
# The lp_appearance_seed helper pins @livepicker-fg/bg/highlight-*/type/show-count to deterministic values,
# and EVERY window-status test sets window-status-separator explicitly. Without this, the plain-path style
# bytes (c/d) and the gap assertions (a/b) are non-deterministic.

# CRITICAL (research §4): the renderer reads STATE_TAB_CURRENT_TMPL/INACTIVE_TMPL (the CACHE), NOT
# window-status-current-format. So the direct-seed tests (a-d) set the CACHE KEYS directly with the
# already-resolved templates ('#[fg=red,bold]__lp_tab__#[default]') and need NOT touch the raw window
# option. (Setting window-status-current-format in a-d would be a no-op for the renderer and misleading.)
# Only test (e) sets the raw window option (it drives the writer via a full activate).

# CRITICAL: NEVER `exit` or `return`-nonzero from a test body to signal failure — run.sh reads TEST_STATUS
# in the CURRENT shell; a bare exit kills the runner. Use fail()/assert_* (they set TEST_STATUS=fail).
# Early `return 0` to skip the rest of a body is OK.

# GOTCHA: the renderer emits ONE line with NO trailing newline (printf '%s'). $(...) captures strip the
# trailing newline anyway, so assert_eq on the captured $out is exact (no newline to worry about).

# GOTCHA: there is NO assert_not_contains / assert_rc in the API. For negatives use an inline
#   case "$out" in *<bad>*) fail "<bad> leaked" ;; esac
# (#-escape note: a literal '#' in a case pattern is fine; glob specials ?/*/[] in the substring would
#  need care, but our negatives ('__lp_tab__', '#[fg=blue]beta', '#{') contain none that break case.)

# GOTCHA: non-test helpers MUST be prefixed `lp_` (or otherwise not start with `test_`), or run.sh's
# `compgen -A function | grep '^test_'` will try to run them as tests. lp_appearance_seed is safe.

# GOTCHA: the file SOURCES NOTHING and calls NO setup_test/teardown_test at file scope (run.sh owns the
# per-test cycle). Each test_* body uses bare tmux (hits the isolated socket via the shim).

# GOTCHA: setup_test pins @livepicker-preview-defer OFF (helpers.sh). (e) does NOT opt in -> activate's
# first preview is synchronous (no async race). Good — appearance is about styling, not timing.

# GOTCHA: test (e)'s activate sets STATE_LIST from list-sessions (driver/alpha/beta) and STATE_INDEX to the
# current session (driver). Do NOT hardcode the highlighted index in (e) — assert on structural properties
# (the resolved cache is exact; the renderer carries #[fg=red,bold] + a name; no placeholder/#{ leaks).

# GOTCHA: the sentinel session name is __lp_sent_$$_$(date +%s) (unique). Asserting "no __lp_sent_* in
# list-sessions" after activate proves kill-session cleaned up (never leaks into the user's session list).

# STYLE: indent with TABS (match test_functional.sh; shfmt NOT installed). `set -u` is INHERITED —
# declare every local. Mirror test_functional.sh's shellcheck disable line:
#   # shellcheck disable=SC2154,SC2016,SC2034,SC2086
```

## Implementation Blueprint

### Data models and structure

No data model. The "structure" is the two-approach split the tests encode:

```
(a)-(d) RENDERER UNIT TESTS (client-independent; direct-seed the cache):
  lp_appearance_seed <list> [filter] [idx]   # pin deterministic @livepicker-* base state
  set @livepicker-tab-style (window-status | plain)
  set window-status-separator (the window option; -gw)
  set @livepicker-tab-current-tmpl / -inactive-tmpl (the CACHE; resolved form with __lp_tab__)
  out="$($LIVEPICKER_SCRIPTS/renderer.sh)"
  assert_eq / assert_contains + inline case+fail

(e) WRITER↔READER INTEGRATION TEST (full activate; needs a client):
  attach_test_client
  set @livepicker-tab-style window-status
  set window-status-current-format / -format (the RAW window option; -gw) -> the writer reads these
  set @livepicker-show-count off  (clean output; colors optional — not asserted)
  $LIVEPICKER_SCRIPTS/livepicker.sh   # runs _lp_resolve_tab_templates -> caches resolved templates
  assert_eq cache == resolved templates; no __lp_sent_* leaked; renderer swaps names end-to-end
```

### Implementation Tasks (ordered by dependencies)

```yaml
Task 1: CREATE tests/test_appearance.sh — header + lp_appearance_seed helper
  - FILE: ./tests/test_appearance.sh
  - SHEBANG: #!/usr/bin/env bash
  - HEADER: mirror test_functional.sh's contract block (SOURCED by run.sh; defines test_*; run.sh owns
    the per-test cycle; bare tmux hits the isolated socket). ADD: the two-halves note (writer P1.M1.T2 /
    reader P1.M1.T3); the renderer-is-client-independent note (a-d need NO attach_test_client); the
    direct-seed-vs-full-activate split; the shellcheck disable line.
  - HELPER lp_appearance_seed <list> [filter] [idx]: pin @livepicker-type session + the 4 colors
    (fg=default bg=default highlight-fg=black highlight-bg=yellow) + show-count off + list/filter/index.
    Neutralizes the user-config @livepicker-fg="#ffffff" + gives the plain path deterministic bytes.
  - STYLE: TAB indent; `set -u` inherited (do NOT re-declare); `local` for all locals.

Task 2: IMPLEMENT (a) test_window_status_highlight_uses_current_format
  - lp_appearance_seed 'alpha\nbeta\ndriver' "" 1 (highlight beta @ idx 1).
  - tab-style window-status; window-status-separator ' '; cache: current='#[fg=red,bold]__lp_tab__#[default]',
    inactive='#[fg=blue]__lp_tab__#[default]'.
  - assert_contains '#[fg=red,bold]beta#[default]' (current); '#[fg=blue]alpha#[default]' + '#[fg=blue]driver#[default]' (inactive).
  - NEG: no '__lp_tab__'; no '#[fg=blue]beta' (beta must carry the CURRENT style).

Task 3: IMPLEMENT (b) test_window_status_separator
  - lp_appearance_seed 'alpha\nbeta\ngamma' "" 1; tab-style window-status; window-status-separator '|';
    cache: current='#[fg=cyan,bold]__lp_tab__#[default]', inactive='#[fg=gray]__lp_tab__#[default]'.
  - assert_eq the EXACT joined output: '#[fg=gray]alpha#[default]|#[fg=cyan,bold]beta#[default]|#[fg=gray]gamma#[default]'.

Task 4: IMPLEMENT (c) test_empty_template_falls_back_to_plain
  - lp_appearance_seed 'alpha\nbeta\ndriver' "" 1; tab-style window-status; window-status-separator '|'.
  - cache: current='' (EMPTY — mirrors a set-empty resolution failure); inactive='#[fg=blue]__lp_tab__#[default]'.
  - assert_contains '#[fg=black,bg=yellow]beta#[default]' (plain highlight) + '#[fg=default,bg=default]alpha#[default]' (plain inactive).
  - NEG: no '#[fg=blue]' (template style leaked); no '__lp_tab__'.

Task 5: IMPLEMENT (d) test_tab_style_plain_unchanged
  - lp_appearance_seed 'alpha\nbeta\ndriver' "" 1; tab-style plain; cache left UNSET.
  - assert_eq the EXACT plain output: '#[fg=default,bg=default]alpha#[default] #[fg=black,bg=yellow]beta#[default] #[fg=default,bg=default]driver#[default]'.
  - NEG: no '__lp_tab__' (plain mode never engages the tab machinery).

Task 6: IMPLEMENT (e) test_sentinel_resolution_end_to_end
  - attach_test_client; tab-style window-status; window-status-current-format '#[fg=red,bold]#W#[default]';
    window-status-format '#[fg=blue]#W#[default]'; show-count off.
  - $LIVEPICKER_SCRIPTS/livepicker.sh (runs the writer; caches resolved templates).
  - assert_eq cache current == '#[fg=red,bold]__lp_tab__#[default]'; inactive == '#[fg=blue]__lp_tab__#[default]'.
  - NEG: no '__lp_sent_*' in list-sessions (sentinel killed).
  - out=renderer.sh; assert_contains '#[fg=red,bold]' (resolved styling) + 'alpha' (a swapped name);
    NEG: no '__lp_tab__', no '#{' (fully resolved).
  - input-handler.sh cancel (teardown the picker).

Task 7: VALIDATE (syntax + lint + full suite)
  - RUN: bash -n tests/test_appearance.sh
  - RUN: shellcheck tests/test_appearance.sh (expect 0 new findings; disable line mirrors test_functional.sh).
  - RUN: bash tests/run.sh (expect the 5 new tests PASS + existing suite green; exit 0).
```

### Implementation Patterns & Key Details

> The block below is the COMPLETE, ready file body. Use it as-is; the only allowed
> deviation is comment phrasing. TAB indent throughout (match test_functional.sh).
> (a)–(d) seed state directly + run renderer.sh (NO client); (e) attaches + activates.

```bash
#!/usr/bin/env bash
# tests/test_appearance.sh — tmux-livepicker PRD §15.24 Appearance (window-status
# tab hijack) validation (P1.M3.T2.S1).
#
# SOURCED by run.sh (NEVER executed directly). Defines five test_* functions that
# validate PRD §17's theme-matched-tab render path: when @livepicker-tab-style is
# window-status, the renderer emits the picker list through the cached
# window-status[-current]-format templates (highlighted index -> current template,
# the rest -> inactive template, each __lp_tab__ swapped -> the #-escaped session
# name, joined by window-status-separator); empty templates / plain mode fall back
# to the unchanged plain path. Plus one end-to-end test of the sentinel resolution.
#
# CONTRACT: run.sh sources setup_socket.sh + helpers.sh + every tests/test_*.sh,
# then PER test calls setup_test "lp-$$-<name>" (-> fresh isolated socket + PATH
# shim + baseline fixtures driver/alpha/beta) -> resets TEST_STATUS=pass -> runs
# the test_* in the CURRENT shell -> reads TEST_STATUS -> teardown_test. So when a
# test_* runs: bare `tmux` hits the isolated socket; $LIVEPICKER_SCRIPTS,
# attach_test_client, fail/pass/assert_eq/assert_contains are all IN SCOPE; this
# file SOURCES NOTHING and calls NO setup_test/teardown_test at file scope.
#
# ARCHITECTURE (the two halves of PRD §17 this file bridges):
#   WRITER (P1.M1.T2.S1, livepicker.sh::_lp_resolve_tab_templates): at activate,
#     resolves window-status[-current]-format against a hidden __lp_tab__ sentinel
#     window via display-message -p, fully expanding #{...} to #[...] styles with
#     __lp_tab__ baked in where #W was, and caches both into STATE_TAB_CURRENT_TMPL
#     / STATE_TAB_INACTIVE_TMPL. Any failure -> set-empty BOTH -> plain fallback.
#   READER (P1.M1.T3.S1, renderer.sh): when opt_tab_style==window-status AND both
#     cache keys are non-empty, swaps __lp_tab__ -> each #-escaped session name,
#     joins with window-status-separator; else falls through to the unchanged
#     plain path.
#
# APPROACH (item §1): the renderer is CLIENT-INDEPENDENT (PURE: reads state only,
# emits one line, zero tmux mutations) — so tests (a)-(d) seed @livepicker-* state
# DIRECTLY and run renderer.sh, NO attach_test_client (mirror test_functional.sh's
# test_renderer_escapes_hash_*). Test (e) drives a FULL activate (attach_test_client
# + livepicker.sh) to validate the sentinel resolution end-to-end (the ONLY test
# that exercises the WRITER). The renderer reads the CACHE keys (not the raw
# window-status-format), so (a)-(d) seed the cache directly and need not touch the
# raw window option; only (e) sets it (it drives the writer).
#
# DETERMINISM: the isolated socket sources the user tmux.conf -> @livepicker-fg
# "#ffffff" + a tubular window-status-separator glyph are dormant. lp_appearance_seed
# pins the colors/type/show-count; each window-status test sets the separator. So
# every assertion is independent of the user's config. display-message -p PRESERVES
# #[...] styles verbatim in stdout (research §2) -> the style assertions are real.
#
# `set -u` is INHERITED from helpers.sh (do NOT re-declare; mirror test_self.sh).
# shellcheck disable=SC2154,SC2016,SC2034,SC2086
#   SC2154: assert_*/attach_test_client/$LIVEPICKER_SCRIPTS/$TEST_DRIVER_SESSION are
#           defined by run.sh's sources, not in this file.

# lp_appearance_seed LIST [FILTER] [INDEX] — pin the MINIMAL deterministic
# @livepicker-* base state the renderer reads, so every test is independent of the
# user's tmux.conf (which sets @livepicker-fg "#ffffff" on the isolated socket).
# Colors: fg/bg=default, highlight-fg=black, highlight-bg=yellow (the PRD defaults),
# so the plain path emits EXACT bytes (#(fg=default,bg=default) / #[fg=black,bg=yellow]).
# show-count OFF -> no query suffix -> exact-output assert_eq is safe. The caller
# sets @livepicker-tab-style + the cache templates + window-status-separator itself.
lp_appearance_seed() {
	tmux set-option -g @livepicker-type session
	tmux set-option -g @livepicker-fg             "default"
	tmux set-option -g @livepicker-bg             "default"
	tmux set-option -g @livepicker-highlight-fg   "black"
	tmux set-option -g @livepicker-highlight-bg   "yellow"
	tmux set-option -g @livepicker-show-count     off
	tmux set-option -g @livepicker-list   "$1"
	tmux set-option -g @livepicker-filter "${2:-}"
	tmux set-option -g @livepicker-index  "${3:-0}"
}

# (a) test_window_status_highlight_uses_current_format — PRD §17 Mapping: the
# highlighted picker item renders through window-status-current-format; every other
# item through window-status-format. Seed 3 sessions, highlight index 1 (beta), set
# window-status tab-style, and seed the two CACHE templates directly (the resolved
# form the writer would produce). Assert the renderer emits beta through the CURRENT
# styling and alpha/driver through the INACTIVE styling. Renderer-only (no client).
test_window_status_highlight_uses_current_format() {
	lp_appearance_seed $'alpha\nbeta\ndriver' "" 1
	tmux set-option -g @livepicker-tab-style window-status
	tmux set-option -gw window-status-separator " "
	tmux set-option -g @livepicker-tab-current-tmpl  "#[fg=red,bold]__lp_tab__#[default]"
	tmux set-option -g @livepicker-tab-inactive-tmpl "#[fg=blue]__lp_tab__#[default]"
	local out
	out="$("$LIVEPICKER_SCRIPTS/renderer.sh")"
	# beta (highlighted) renders through the CURRENT template (red,bold):
	assert_contains "$out" "#[fg=red,bold]beta#[default]" \
		"highlighted item (beta) uses the current-format styling"
	# alpha + driver (inactive) render through the INACTIVE template (blue):
	assert_contains "$out" "#[fg=blue]alpha#[default]" \
		"inactive item (alpha) uses the inactive-format styling"
	assert_contains "$out" "#[fg=blue]driver#[default]" \
		"inactive item (driver) uses the inactive-format styling"
	# the placeholder was fully swapped (none remain):
	case "$out" in *__lp_tab__*) fail "an unswapped __lp_tab__ placeholder leaked" ;; esac
	# negative: beta must NOT carry the inactive styling (proves the current/inactive split):
	case "$out" in *"#[fg=blue]beta"*) fail "beta leaked the inactive (window-status-format) styling" ;; esac
}

# (b) test_window_status_separator — PRD §17 Mapping: the inter-item gap is
# window-status-separator. Set it to a known string ('|') and assert the renderer
# joins the tabs with EXACTLY that separator (NOT a plain space). Exact-output
# assertion (show-count off -> no suffix); the highlight is index 1 (beta, current).
test_window_status_separator() {
	lp_appearance_seed $'alpha\nbeta\ngamma' "" 1
	tmux set-option -g @livepicker-tab-style window-status
	tmux set-option -gw window-status-separator "|"
	tmux set-option -g @livepicker-tab-current-tmpl  "#[fg=cyan,bold]__lp_tab__#[default]"
	tmux set-option -g @livepicker-tab-inactive-tmpl "#[fg=gray]__lp_tab__#[default]"
	local out
	out="$("$LIVEPICKER_SCRIPTS/renderer.sh")"
	# exact joined output: alpha(inactive) | beta(current) | gamma(inactive)
	assert_eq "$out" \
		"#[fg=gray]alpha#[default]|#[fg=cyan,bold]beta#[default]|#[fg=gray]gamma#[default]" \
		"tabs joined with window-status-separator ('|'), highlight through the current template"
}

# (c) test_empty_template_falls_back_to_plain — PRD §17 Fallback / §16 fragility:
# if either cached template is empty (resolution failed -> set-empty by the writer,
# or the helper never ran -> unset), window-status mode falls back to the PLAIN
# path. Leave the current template EMPTY, set tab-style window-status, and assert
# the renderer output is the PLAIN styling (#(highlight) + #(plain)), NOT the
# window-status templates.
test_empty_template_falls_back_to_plain() {
	lp_appearance_seed $'alpha\nbeta\ndriver' "" 1
	tmux set-option -g @livepicker-tab-style window-status
	tmux set-option -gw window-status-separator "|"   # ignored on the plain path (space join); set for realism
	# current template EMPTY (mirrors a set-empty resolution failure); inactive set:
	tmux set-option -g @livepicker-tab-current-tmpl  ""
	tmux set-option -g @livepicker-tab-inactive-tmpl "#[fg=blue]__lp_tab__#[default]"
	local out
	out="$("$LIVEPICKER_SCRIPTS/renderer.sh")"
	# beta highlighted via the PLAIN path (#[fg=black,bg=yellow]); NOT a template:
	assert_contains "$out" "#[fg=black,bg=yellow]beta#[default]" \
		"empty current template -> highlight falls back to plain (#[fg=HFG,bg=HBG])"
	assert_contains "$out" "#[fg=default,bg=default]alpha#[default]" \
		"empty current template -> inactive items fall back to plain (#[fg=FG,bg=BG])"
	# negative: the window-status template styling must NOT appear:
	case "$out" in *"#[fg=blue]"*) fail "window-status template leaked into the plain fallback" ;; esac
	case "$out" in *__lp_tab__*) fail "unswapped placeholder leaked (should be the plain path)" ;; esac
}

# (d) test_tab_style_plain_unchanged — PRD §17 Control: @livepicker-tab-style=plain
# (the default) uses the standalone @livepicker-fg/bg/highlight-* coloring (current
# behavior; no theme dependency). Assert the renderer output is the UNCHANGED plain
# path — byte-identical to the pre-§17 behavior AND to the (c) empty-template
# fallback (proving plain mode == plain fallback).
test_tab_style_plain_unchanged() {
	lp_appearance_seed $'alpha\nbeta\ndriver' "" 1
	tmux set-option -g @livepicker-tab-style plain
	# cache keys left UNSET (plain mode never resolves/caches):
	local out
	out="$("$LIVEPICKER_SCRIPTS/renderer.sh")"
	# the pre-§17 plain output: items joined by a single space; highlight via HFG/HBG:
	assert_eq "$out" \
		"#[fg=default,bg=default]alpha#[default] #[fg=black,bg=yellow]beta#[default] #[fg=default,bg=default]driver#[default]" \
		"plain mode renders the unchanged plain path (no window-status templates)"
	# negative: no window-status machinery engaged:
	case "$out" in *__lp_tab__*) fail "plain mode engaged the window-status tab machinery" ;; esac
}

# (e) test_sentinel_resolution_end_to_end — PRD §17 Resolution: at activation, the
# sentinel window resolves the theme formats into #[...]-styled templates with
# __lp_tab__ baked in, and the sentinel session is killed (no leak). This is the
# ONLY test that exercises the WRITER (livepicker.sh::_lp_resolve_tab_templates) via
# a real activate; (a)-(d) cover the reader in isolation. attach_test_client is
# MANDATORY (activate needs a client for ORIG_SESSION capture + refresh-client -S).
test_sentinel_resolution_end_to_end() {
	attach_test_client
	tmux set-option -g @livepicker-tab-style window-status
	tmux set-option -g @livepicker-show-count off
	# representative theme formats: #W resolves to the sentinel name __lp_tab__.
	tmux set-option -gw window-status-current-format "#[fg=red,bold]#W#[default]"
	tmux set-option -gw window-status-format          "#[fg=blue]#W#[default]"
	"$LIVEPICKER_SCRIPTS/livepicker.sh"
	# the WRITER populated the cache with the fully-resolved templates:
	assert_eq "$(tmux show-option -gqv @livepicker-tab-current-tmpl)" \
		"#[fg=red,bold]__lp_tab__#[default]" \
		"activate resolved window-status-current-format -> #[...]-styled template with __lp_tab__ baked in"
	assert_eq "$(tmux show-option -gqv @livepicker-tab-inactive-tmpl)" \
		"#[fg=blue]__lp_tab__#[default]" \
		"activate resolved window-status-format -> #[...]-styled template with __lp_tab__ baked in"
	# the sentinel session was killed (never leaks into the session list):
	case "$(tmux list-sessions -F '#{session_name}' 2>/dev/null)" in
		*__lp_sent_*) fail "sentinel session leaked into list-sessions" ;;
	esac
	# end-to-end: the READER swaps __lp_tab__ -> the live session names. The
	# highlighted item (the activate origin, driver) carries the current styling;
	# the renderer emits no unswapped placeholder / no raw #{.
	local out
	out="$("$LIVEPICKER_SCRIPTS/renderer.sh")"
	assert_contains "$out" "#[fg=red,bold]" "renderer applied the resolved current styling"
	assert_contains "$out" "alpha" "renderer swapped in a live session name (alpha)"
	case "$out" in *__lp_tab__*) fail "renderer left an unswapped __lp_tab__ placeholder" ;; esac
	case "$out" in *"#{"*) fail "renderer leaked an unexpanded #{} from the sentinel" ;; esac
	"$LIVEPICKER_SCRIPTS/input-handler.sh" cancel >/dev/null 2>&1 || true
}
```

NOTE for the implementer: the block above is the COMPLETE file. The subtle bits:
- **The cache vs raw-window-option distinction** (research §4): (a)–(d) seed
  `@livepicker-tab-current-tmpl`/`-inactive-tmpl` (the CACHE) directly and do NOT
  set `window-status-current-format` — the renderer reads only the cache. Only (e)
  sets the raw window option (it drives the writer).
- **Determinism** (research §3): `lp_appearance_seed` pins the 4 colors + show-count
  so the plain-path bytes (c/d) are exact; every window-status test sets
  `window-status-separator` so the gap (a/b) is exact. Don't drop these or the user's
  `tmux.conf` (`@livepicker-fg "#ffffff"`, tubular separator) shifts the bytes.
- **(e)'s cache assertion** is byte-exact because `display-message -p` preserves
  `#[…]` (research §2): `"#[fg=red,bold]#W#[default]"` resolves to exactly
  `"#[fg=red,bold]__lp_tab__#[default]"`.

### Integration Points

```yaml
TEST DISCOVERY:
  - file: tests/test_appearance.sh
    change: "NEW. 5 test_* functions + lp_appearance_seed helper."
    discovery: "auto via run.sh `compgen -A function | grep '^test_'` (sourced by the
               nullglob `source test_*.sh` loop). No registration needed."

HARNESS DEPENDENCIES (consumed — all UNCHANGED, all in scope via run.sh):
  - tests/setup_socket.sh: attach_test_client (for (e) only), baseline fixtures, $LIVEPICKER_SCRIPTS.
  - tests/helpers.sh: fail/pass/assert_eq/assert_contains; setup_test (pins defer=off);
    teardown_test (auto-cleanup).
  - tests/run.sh: sources this file; per-test setup_test/teardown_test; PASS/FAIL + exit.

PROD DEPENDENCIES (consumed — all LANDED, UNCHANGED by this task):
  - scripts/renderer.sh: the window-status render block (P1.M1.T3.S1) — the SUT for (a)-(e).
  - scripts/options.sh: opt_tab_style (P1.M1.T1.S1).
  - scripts/state.sh: STATE_TAB_CURRENT_TMPL / STATE_TAB_INACTIVE_TMPL (P1.M1.T1.S1).
  - scripts/livepicker.sh: _lp_resolve_tab_templates (P1.M1.T2.S1) — exercised by (e)'s activate.
  - scripts/filter.sh: lp_build_filtered (the shared filter the renderer uses).

CODE / DATABASE / CONFIG / ROUTES: none (test-only; no production code change).
```

## Validation Loop

### Level 1: Syntax & Style (Immediate Feedback)

```bash
cd /home/dustin/.config/tmux/plugins/tmux-livepicker
bash -n tests/test_appearance.sh && echo "OK: syntax"
shellcheck tests/test_appearance.sh
# Tabs-not-spaces (shfmt NOT installed):
grep -nP '^ +' tests/test_appearance.sh && echo "WARN: space-indent (use tabs)" || echo "OK: tabs"
# Exactly 5 discovered tests + 1 non-test helper (lp_appearance_seed):
grep -c '^test_' tests/test_appearance.sh        # -> 5
grep -c '^lp_appearance_seed()' tests/test_appearance.sh   # -> 1
# Expected: syntax clean; shellcheck 0 NEW findings (disable line mirrors test_functional.sh);
# 5 test_* functions; lp_appearance_seed is NOT test_-prefixed (so compgen won't run it).
```

### Level 2: Full suite (the committed validation)

```bash
cd /home/dustin/.config/tmux/plugins/tmux-livepicker
bash tests/run.sh
# Expected: exit 0. The 5 new tests print PASS:
#   test_empty_template_falls_back_to_plain
#   test_sentinel_resolution_end_to_end
#   test_tab_style_plain_unchanged
#   test_window_status_highlight_uses_current_format
#   test_window_status_separator
# AND the existing suite stays green (it runs tab-style=plain by default; unaffected).
# Takes ~2-3 min. If (a)-(d) FAIL on an assert_contains/assert_eq, the renderer's
# window-status block swapped/joined wrong (re-check the __lp_tab__ swap + the
# #->## escape-before-substitution + the separator read). If (e) FAILs on the cache
# assert_eq, the writer resolved differently (re-check _lp_resolve_tab_templates).
```

### Level 3: Isolated spot-run (fast feedback, no full suite)

```bash
cd /home/dustin/.config/tmux/plugins/tmux-livepicker
# Run JUST the appearance tests in a one-shot harness (mirrors the test_functional.sh
# renderer-only idiom; no client needed for a-d). Quick confidence before the full run.
cat > /tmp/lp_app_spot.sh <<'EOF'
#!/usr/bin/env bash
set -u
cd /home/dustin/.config/tmux/plugins/tmux-livepicker
source tests/setup_socket.sh
source tests/helpers.sh
source tests/test_appearance.sh
for t in test_window_status_highlight_uses_current_format test_window_status_separator \
         test_empty_template_falls_back_to_plain test_tab_style_plain_unchanged; do
	setup_test "lp-spot-${t#test_}"; TEST_STATUS=pass; "$t"
	[ "$TEST_STATUS" = pass ] && echo "PASS $t" || echo "FAIL $t"
	teardown_test
done
EOF
bash /tmp/lp_app_spot.sh; rc=$?; rm -f /tmp/lp_app_spot.sh; exit $rc
# Expected: 4 PASS (a-d). (e) needs a full activate + client -> run via tests/run.sh.
```

### Level 4: Bug-reintroduction spot-check (the tests actually guard §17)

```bash
cd /home/dustin/.config/tmux/plugins/tmux-livepicker
# (Optional, defense-in-depth) Temporarily break the reader and confirm a test FAILS:
#   e.g. in scripts/renderer.sh make the window-status block skip the #->## escape
#   (use $ws_name instead of $esc_wname) -> with a '#'-bearing name the output would
#   carry a stray directive. (Our tests use plain names so they'd still pass; to truly
#   exercise the escape, temporarily add a '#'-bearing session to test (a).) Or: make
#   the empty-template gate always-enter -> test_empty_template_falls_back_to_plain FAILS.
# Restore. (Mirror the P1.M1.T3.S1 L2 pattern.) Proves the tests are not vacuous.
```

## Final Validation Checklist

### Technical Validation

- [ ] `bash -n tests/test_appearance.sh` clean.
- [ ] `shellcheck tests/test_appearance.sh`: 0 new findings (disable line present).
- [ ] L1 grep: 5 `test_*` functions; `lp_appearance_seed` present (non-`test_`).
- [ ] Tabs only (no space-indent).

### Feature Validation

- [ ] (a) highlight: beta → current styling; alpha/driver → inactive; no placeholder/leak.
- [ ] (b) separator: exact joined output with `|` between 3 segments.
- [ ] (c) empty current template + window-status → plain styling; no template leak.
- [ ] (d) plain mode → exact plain output (byte-identical to (c)'s fallback).
- [ ] (e) activate resolves cache to exact templates; no `__lp_sent_*` leak; renderer swaps names; no placeholder/`#{`.
- [ ] (a)-(d) run renderer.sh with NO `attach_test_client`; (e) attaches + activates.
- [ ] `bash tests/run.sh` exit 0; 5 new tests PASS; existing suite green.

### Code Quality Validation

- [ ] Mirrors test_functional.sh structure (header contract block; seed → run renderer → assert).
- [ ] Failure signaled ONLY via `fail`/`assert_*` + inline `case`+`fail`; NO `exit`/`return`-nonzero.
- [ ] `lp_appearance_seed` prefixed `lp_` (NOT `test_` → not auto-run).
- [ ] Determinism: every test pins colors (via the helper) + the separator; no reliance on the user config.
- [ ] TAB indent; `set -u` inherited; all locals declared.
- [ ] File sources nothing; no `setup_test`/`teardown_test` at file scope.

### Documentation & Deployment

- [ ] Header documents: the run.sh sourcing contract, the renderer-is-client-independent note,
      the direct-seed-vs-full-activate split, and the cache-vs-raw-window-option distinction.
- [ ] No README/CHANGELOG edit (test file; the §17 option row is synced by the Mode-B docs
      task P1.M3.T3.S1).
- [ ] No production code change; no other test file touched.

---

## Anti-Patterns to Avoid

- ❌ Don't assert the renderer output WITHOUT pinning the colors — the isolated socket sources the
  user's `tmux.conf` (`@livepicker-fg "#ffffff"`), so `opt_fg()` returns `#ffffff`, not `default`,
  and the plain-path bytes (c/d) shift. Always `lp_appearance_seed` first (or set the 4 colors yourself).
- ❌ Don't omit the `window-status-separator` set in a window-status test — the isolated socket's
  tubular config sets it to a glyph (NOT a plain space); the renderer reads it and your gap/separator
  assertions (a/b) become non-deterministic. Set it explicitly per test.
- ❌ Don't set `window-status-current-format` in (a)–(d) expecting the renderer to read it — the
  renderer reads the CACHE keys (`STATE_TAB_CURRENT_TMPL`/`INACTIVE_TMPL`), never the raw window
  option. Seed the cache directly. Only (e) sets the raw option (it drives the writer).
- ❌ Don't `exit` or `return`-nonzero from a test body to fail — it kills `run.sh`. Use `fail`/
  `assert_*` (set `TEST_STATUS`). Early `return 0` to skip is fine.
- ❌ Don't name a helper `test_*` — `run.sh`'s `compgen | grep '^test_'` will try to RUN it. Use
  the `lp_` prefix (`lp_appearance_seed`).
- ❌ Don't attach a client in (a)–(d) — the renderer is client-independent (PURE: reads state,
  prints one line, zero mutations); attaching is wasted work and the existing renderer-only idiom
  (`test_renderer_escapes_hash_*`) deliberately skips it. Only (e) needs `attach_test_client`.
- ❌ Don't hardcode the highlighted index in (e) — activate sets STATE_LIST/INDEX from live state
  (driver is the origin); assert structural properties (exact cache, no leak, renderer carries the
  styling + a name) instead.
- ❌ Don't rely on `assert_not_contains` — there is none in the API. Use inline `case "$out" in
  *<bad>*) fail … ;; esac`.
- ❌ Don't add a `setup_test`/`teardown_test` call at file scope — run.sh owns the per-test cycle;
  adding one would double-setup and leak sockets. (a)–(e) run on the per-test socket run.sh provides.
- ❌ Don't edit any production script or any other test file — this is test-only. All §17 deps are
  landed; if a test reveals a prod bug, surface it to the orchestrator (do NOT fix prod here).
- ❌ Don't use spaces for indent — TABS only (match test_functional.sh; shfmt absent).

---

## Confidence Score

**9 / 10** for one-pass success. Rationale: both §17 halves are **grep-confirmed landed**
(the writer `_lp_resolve_tab_templates` + the reader window-status block in renderer.sh),
and the load-bearing empirical fact is **verified live**: `display-message -p` preserves
`#[…]` styles verbatim (`#[fg=red,bold]#W#[default]` → `#[fg=red,bold]__lp_tab__#[default]`),
so every style assertion is a real byte-exact check — not a guess. The determinism hazards
(the isolated socket's `@livepicker-fg "#ffffff"` and the tubular `window-status-separator`
glyph) are neutralized by the `lp_appearance_seed` helper + explicit separator sets, making
the `assert_eq` exact-output assertions (b/c/d) and the cache `assert_eq` in (e) robust. The
test file mirrors `test_functional.sh`'s proven renderer-only idiom (`test_renderer_escapes_hash_*`)
for (a)–(d) and its `attach`+`activate` lifecycle for (e). The 5 tests map 1:1 to the contract's
§1 a–e, each with a deterministic assertion core. Residual risks: (i) the exact-resolved-template
`assert_eq` in (e) is byte-exact — if a future tmux/version ever emits styles differently the test
would catch it (arguably correct); mitigated by the structural backstops (no `#{`, `#[` present,
`__lp_tab__` present) the test ALSO implicitly checks via the negatives. (ii) (e) drives a full
activate, which exercises the broader machinery (key table/preview/status grow) — mitigated by
keeping (e)'s assertions scoped to the §17 facets (cache + sentinel + renderer swap) and by
`setup_test` pinning `preview-defer off` so the first preview is synchronous. The 1-point
deduction is for these two integration/byte-exactness sensitivities, both deterministically
scoped, not for any missing context.
