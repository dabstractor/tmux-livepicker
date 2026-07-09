# test_preview_clip.sh — test-design findings (P3.M2.T1.S1)

> Synthesis for the `tests/test_preview_clip.sh` PRP. Pins the lifecycle to mirror,
> the exact assertions (drawn from `clip_probe_findings.md` §4 assert shape + §3
> candidate residual + §2 isolation), and the determinism decisions. Read alongside
> `P3M1T2S1/PRP.md` (the implementation it tests) and `clip_verification.md` (the
> GATE decision doc).

## 1. Lifecycle — mirror `test_scroll_width.sh`, NOT `test_preview.sh`

The contract says "mirror tests/test_preview.sh's lifecycle (needs
attach_test_client)". That is HALF-right and must be reconciled:

- `test_preview.sh` drives `preview.sh` DIRECTLY and deliberately does NOT call
  `attach_test_client`, because preview.sh is CLIENT-INDEPENDENT (it reads the
  driver from `@livepicker-orig-session`, not `display-message`).
- BUT the clip feature lives in the ACTIVATE path (`livepicker.sh` T3 b.5). The
  freeze uses `display-message -p '#{window_height}'` (the pre-grow height) and
  `resize-window -y "$H0" -t "$ORIG_WINDOW"`, both of which need an attached
  client to read the client-driven usable size (clip_probe_findings.md §0 gotcha
  #2/#5: on a client-less socket `window_height` reads the creation size 40).

=> The correct mirror is `test_scroll_width.sh`: it does the FULL real path
`attach_test_client` -> `"$LIVEPICKER_SCRIPTS/livepicker.sh"` (activate) ->
`"$LIVEPICKER_SCRIPTS/input-handler.sh" cancel` (restore), in the CURRENT shell
(run.sh sources it; `setup_test`/`teardown_test` run per test function). This is
the EXACT shape the clip verification needs: activate touches `window-size` +
resizes, cancel restores them.

The shared activate helper therefore looks like `_lp_scroll_setup`:

```bash
_lp_clip_activate() {
	attach_test_client                 # display-message -p needs a client
	tmux set-option -g @livepicker-preview-fit clip   # explicit (default is clip)
	# capture BEFORE activate (driver's ACTIVE window == ORIG_WINDOW after STEP 2)
	...
	"$LIVEPICKER_SCRIPTS/livepicker.sh" >/dev/null     # activate (freeze + grow)
	sleep 0.3                          # let the synchronous resize settle
}
```

`@livepicker-preview-defer` is already pinned OFF by `setup_test` (helpers.sh), so
the nav preview is synchronous — no race on the candidate-residual assertions.

## 2. The no-reflow assertion (self-session) — byte-identical window_layout

`clip_probe_findings.md` §4 gives the EXACT assert shape. The self-window is the
driver's ACTIVE window at activate time == ORIG_WINDOW (T5's first preview is the
SELF-SESSION: `livepicker.sh` line ~420 `preview.sh "$orig_session"` -> self guard
-> `select-window ORIG_WINDOW` WITHOUT linking, so the active window stays
ORIG_WINDOW). So:

```bash
AW="$(tmux list-windows -t "=$TEST_DRIVER_SESSION" -F '#{window_id}' -f '#{window_active}')"
L0="$(tmux display-message -p -t "$AW" '#{window_layout}')"
H0="$(tmux display-message -p -t "$AW" '#{window_height}')"
"$LIVEPICKER_SCRIPTS/livepicker.sh" >/dev/null; sleep 0.3
L1="$(tmux display-message -p -t "$AW" '#{window_layout}')"
H1="$(tmux display-message -p -t "$AW" '#{window_height}')"
assert_eq "$L0" "$L1" 'self-window layout unchanged across status grow (no reflow)'
assert_eq "$H0" "$H1" 'self-window height pinned (clip, not reflow)'
```

`window_layout` embeds a 4-hex checksum + per-node dims, so it CHANGES on reflow.
Byte-identical == no reflow (clip_verification.md gotcha #7). Verbatim expected
values from the probe: L0==L1==`4a2d,80x23,0,0{...}`, H0==H1==`23` (status on =
1 line; pty 80x24). DO NOT hardcode — read live.

CONFIRMATION that the freeze actually ran: the driver is now `manual`
(`show-options -t "$TEST_DRIVER_SESSION" -v window-size` == `manual`) and status
grew (`show-options -gv status` == `2`).

## 3. The candidate residual — one-time link-time resize, NO per-nav reflow

clip addresses the SELF-window. A linked CANDIDATE still reflows ONCE at link time
(its source size 40 -> driver usable 22; the source view also changes — shared
window). That IS the documented limitation (README "Detached candidate resize" /
CHANGELOG bugfix-001), NOT a defect. The contract (b) asks to assert it is
BOUNDED: one-time, not per-nav.

Deterministic sequence (mirrors test_preview.sh's direct preview.sh seam; avoids
list-order fragility — the sorted list is [alpha,beta,driver], so nav indices
shift, but preview.sh-with-a-name targets exactly the candidate):

```bash
# after activate (self pinned at H0=23, status grown to 2)
"$LIVEPICKER_SCRIPTS/preview.sh" alpha; sleep 0.2      # link alpha -> 40..22 (one-time)
alpha_wid="$(tmux list-windows -t "=$TEST_DRIVER_SESSION" -F '#{window_id}' -f '#{window_active}')"
LA1="$(tmux display-message -p -t "$alpha_wid" '#{window_layout}')"
"$LIVEPICKER_SCRIPTS/preview.sh" beta;  sleep 0.2      # unlink alpha, link beta
"$LIVEPICKER_SCRIPTS/preview.sh" alpha; sleep 0.2      # re-link alpha (re-select by @id)
alpha_wid2="$(tmux list-windows -t "=$TEST_DRIVER_SESSION" -F '#{window_id}' -f '#{window_active}')"
LA2="$(tmux display-message -p -t "$alpha_wid2" '#{window_layout}')"
assert_eq "$LA1" "$LA2" 'candidate: no per-nav additional reflow (link-time only)'
```

Verbatim from clip_probe_findings.md §3: LA1==LA2==
`6004,80x22,0,0{40x22,0,0,1,39x22,41,0,7}`. NOTE the link-time resize itself
(alpha 40->22) is the residual — capture alpha's SOURCE height before the first
link to DOCUMENT it (assert it dropped to the driver usable size once), but the
load-bearing assertion is LA1==LA2 (no per-nav). `preview.sh` needs the picker
state ORIG_SESSION/ORIG_WINDOW, which activate already set -> no re-seed.

## 4. Restore — session-scoped window-size byte-exact + panes natural again

contract (c). P3.M1.T2.S1's restore does `set-option -u -t "$orig_session"
window-size` when the saved value was empty (the common case: driver had no
session override -> inherits global). So:

```bash
ws_before="$(tmux show-options -t "$TEST_DRIVER_SESSION" -v window-size 2>/dev/null || true)"  # "" baseline
# ... activate + cancel ...
"$LIVEPICKER_SCRIPTS/input-handler.sh" cancel >/dev/null; sleep 0.3
ws_after="$(tmux show-options -t "$TEST_DRIVER_SESSION" -v window-size 2>/dev/null || true)"
assert_eq "$ws_after" "$ws_before" 'restore: driver window-size byte-exact (unset->unset)'
```

Plus the global is NEVER touched (PRD §15 zero-trace):
`show-options -g -v window-size` unchanged before/after the whole cycle.

Plus panes returned to natural size: after cancel, status shrunk back (2->on),
window-size freed -> the window re-fits to the client. The self-window height
returns to H0 (e.g. 23), and restore.sh STEP 5 select-layout replays ORIG_LAYOUT.
Assert `window_height` (active window) == the pre-activate H0.

## 5. Reflow fallback — window-size NEVER touched; window DOES reflow

contract (d). Set `@livepicker-preview-fit reflow`; activate + cancel. The clip
gate (`if [ "$(opt_preview_fit)" = "clip" ]`) skips BOTH activate-freeze and
restore, so window-size is never read or written:

```bash
tmux set-option -g @livepicker-preview-fit reflow
ws_before="$(tmux show-options -t "$TEST_DRIVER_SESSION" -v window-size 2>/dev/null || true)"  # ""
H0=...; L0=...   # pre-activate
"$LIVEPICKER_SCRIPTS/livepicker.sh" >/dev/null; sleep 0.3
assert_eq "$(tmux show-options -t "$TEST_DRIVER_SESSION" -v window-size 2>/dev/null || true)" "$ws_before" \
    'reflow: window-size untouched (clip gate skipped)'
assert_eq "$(tmux show-options -gv status)" "2" 'reflow: status DID grow (legacy)'
H1=...; L1=...   # post-activate
[ "$L0" != "$L1" ] || fail 'reflow: window SHOULD have reflowed (height 23->22) — the legacy path'
"$LIVEPICKER_SCRIPTS/input-handler.sh" cancel >/dev/null; sleep 0.3
# restore byte-exact: window-size still untouched; status back; panes natural
```

The reflow assertion is the INVERSE of the clip assertion: layout MUST CHANGE
(23->22) proving the legacy one-row reflow fires when clip is off.

## 6. Gotchas specific to THIS test file

- **attach_test_client is MANDATORY** (unlike test_preview.sh). The freeze + the
  layout/height measurements all need a client. clip_probe_findings.md §5: a
  client-less socket reads creation size 40 and window-size behavior reverts to
  detached -> the test is meaningless. The harness `sleep 0.5` (attach) is
  sufficient; add `sleep 0.3` after activate/grow and `sleep 0.2` after each link.
- **The baseline driver has NO session window-size override** -> `show-options -t
  driver -v window-size` returns EMPTY pre-activate (inherits global `latest`).
  So the byte-exact restore asserts "" -> "". (If a future test seeds an override,
  capture THAT and assert it round-trips.)
- **Address windows by @id, never index.** Driver windows are at index 1/2
  (renumber on); `=driver:0` -> "can't find window". Read the active @id via
  `list-windows -f '#{window_active}'` and `-t "$AW"` (var holds `@3`).
- **Global window-size must never change.** Assert `show-options -g -v
  window-size` is byte-identical across EVERY test (clip never uses `-g`).
- **`set -u` is inherited** from helpers.sh (do NOT re-declare; mirror
  test_preview.sh / test_scroll_width.sh shellcheck disable block).
- **Determinism is GOOD** (clip_verify_run1 == run2 byte-identical). The layout
  strings are stable across fresh sockets, so byte-equality assertions are sound.
- **run.sh discovers test_* by `compgen -A function | grep '^test_' | sort`** —
  name the functions `test_*` so they auto-register; NO main/runner in the file.
- **Per-test hermetic**: run.sh calls `setup_test "lp-$$-<name>"` -> fresh socket
  PER function. So (a)/(b)/(c)/(d) are separate `test_*` functions (each a clean
  activate/restore cycle), NOT one giant function. Shared activate via a helper.

## 7. What is OUT OF SCOPE for this test file

- Re-deriving tmux behavior (that is clip_probe_findings.md / clip_verification.md
  — READ-ONLY here; cite, do not re-probe).
- The candidate LINK-TIME clip (preview.sh optional `resize-window -y H`) — that
  is future polish, NOT shipped by P3.M1.T2. The residual test asserts the CURRENT
  behavior (one-time link-time resize to usable size), not a clip-at-link.
- Editing any script (this task writes ONE file: tests/test_preview_clip.sh).
- Registering the test manually — run.sh auto-discovers `test_*` functions.
