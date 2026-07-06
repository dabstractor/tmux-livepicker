# Research: `tests/test_pollution.sh` — PRD §15.18 Pollution (the core invariant) (P1.M7.T5.S1)

Empirically verified live on 2026-07-06 against `/usr/bin/tmux` (3.6b) on
**isolated sockets** (`tmux -L lp-t5verify-$$` / `lp-t5dbg-$$` / `lp-t5fix-$$` /
`lp-dmprobe-$$`, each `kill-server`'d on exit, each with ONE attached client via
`script -qec`). Every assertion below was observed PASSING in the final run. This
file is the ground-truth that makes the three pollution tests pass on the first
try. The **real `tmux-session-history` engine source** was read in full
(`~/.config/tmux/plugins/tmux-session-history/scripts/session_history.sh`) and is
the authoritative model for the stand-in recorder.

## The work-item crux (restated)

T5.S1 CREATES `tests/test_pollution.sh` — the PRD §15.18 Pollution cluster. Three
`test_*` functions drive the COMPLETE real plugin (livepicker.sh →
input-handler.sh → preview.sh → restore.sh) against the socket-isolated harness
(`tests/setup_socket.sh` T1.S1 + `tests/helpers.sh`/`run.sh` T2.S1) and assert
the core invariant (PRD §4 / §14): **browsing must not pollute session-history.**

The crux is the MOCKING: the real `tmux-session-history` plugin is NOT loaded on
the isolated socket, so the test must install a **stand-in recorder** on
`client-session-changed` that faithfully mirrors the real engine's
dedup + forward-collapse + `prev` semantics. The work-item recommends the stand-in
over loading the real plugin "for determinism."

## The three tests (PRD §15.18, mapped)

1. **test_browse_cancel_no_pollution** — snapshot `@test-hist`; activate; navigate
   5 sessions; cancel; assert `@test-hist` UNCHANGED AND the client's session ==
   original.
2. **test_browse_confirm_one_entry** — snapshot `@test-hist`; activate; navigate 5;
   confirm on the 5th; assert EXACTLY ONE new entry appended (the target) and
   forward history collapsed (no intermediate sessions recorded).
3. **test_toggle_after_confirm** — after a confirmed pick, simulate the
   session-history toggle (switch to `@test-prev`); assert it returns to the
   pre-pick session.

## Findings

### FINDING 1 — the real engine's exact semantics (the model for the stand-in)  [VERIFIED by reading session_history.sh in full]

The real `tmux-session-history` engine (`scripts/session_history.sh`) maintains
five `@session-history-*` options and is driven by ONE hook:

```
# session_history.tmux:22 (the spine):
tmux set-hook -g client-session-changed "run-shell '${SCRIPT} hook \"#{session_name}\"'"
```

State:
- `@session-history-hist` — ordered timeline, **NO DUPLICATES**, newline-separated.
- `@session-history-idx` — cursor position (index of the current session).
- `@session-history-current` — last-known current session (so the hook can diff from→to).
- `@session-history-prev` — the session the toggle flips to.
- `@session-history-walk` — transient flag (a back/forward WALK sets it so the hook does NOT collapse).

`do_hook(to)` (the exact logic the stand-in mirrors):
1. `[ -z "$to" ] && to=attached; [ -z "$to" ] && return` — ignore empty.
2. **First fire / uninitialized** (`CURRENT` empty): `HIST=(to); IDX=0; CURRENT=to; PREV=to; clear walk; save; return`.
3. **SAME-SESSION SHORT-CIRCUIT** (`to == CURRENT`): clear walk; **return without touching the timeline** — this is the dedup that makes cancel → 0 entries.
4. **NAVIGATION** (else): keep backward history `HIST[0..IDX]` MINUS `to`, then APPEND `to`; `IDX = len-1` (end of road; forward collapses). `PREV = from` (the old CURRENT) if `from` still exists. `CURRENT = to`; clear walk; save.

`do_toggle()`:
1. `cur = CURRENT`; if `PREV` non-empty AND `PREV != cur` AND `PREV` exists → `target = PREV`.
2. `switch-client -t "$target"` (NO walk flag → the hook treats it as a NAVIGATION → target appended at the tip; afterward forward is dead, like a browser).

**Implication for the stand-in:** to faithfully model `@session-history-hist` +
the toggle, the recorder must implement (2) the same-session short-circuit, (3)
the navigation collapse (backward-minus-to, append-to), and maintain `@test-prev`
(= from on navigation). The work-item's `@test-hist` maps to `@session-history-hist`;
`@test-prev` maps to `@session-history-prev`.

### FINDING 2 — the proven smart-recorder pattern (from P1.M6 throwaway mocks)  [VERIFIED]

The P1.M6.T3.S1 `confirm_mock.sh` + T4.S1 `cancel_mock.sh` throwaway validators
already proved a smart-dedup `client-session-changed` recorder works in the hook:

```bash
REC_DIR="$(mktemp -d)"
cat > "$REC_DIR/rec.sh" <<EOF
#!/usr/bin/env bash
new="\$1"
last="\$(tail -1 '$REC_LOG' 2>/dev/null || true)"
[ -n "\$new" ] && [ "\$new" != "\$last" ] && printf '%s\\n' "\$new" >> '$REC_LOG'
EOF
T set-hook -g client-session-changed "run-shell '$REC_DIR/rec.sh #{session_name}'"
echo driver > "$REC_LOG"   # seed baseline
```

The mock's recorder dedups (records ONLY when `to != last`) — matching `do_hook`'s
short-circuit. BUT it writes a FILE (`$REC_LOG`), not tmux options, and does NOT
model forward-collapse or maintain a `prev` pointer. T5.S1 needs MORE: the
collapse (for the "no intermediates" assertion) + `@test-prev` (for the toggle).
So the stand-in is a SUPERSET of the mock: it mirrors `do_hook` fully and writes
tmux OPTIONS (`@test-hist`/`@test-current`/`@test-prev`/`@test-idx`) — faithful to
the real plugin's state shape (PRD §14 "composes with tmux-session-history").

### FINDING 3 — [CRITICAL] `display-message -p '#{session_name}'` (no `-t`) returns the LAST-CREATED session, NOT the attached client's session  [VERIFIED — the load-bearing trap]

Probed directly (`/tmp/lp_dm_probe.sh`, isolated socket + one attached client on
`driver`):

```
A) after attach, before creating others:
   display-message -p '#{session_name}':  [driver]      # driver is last-created AND client's session
   list-clients:  /dev/pts/101 -> driver
B) after creating alpha, s5 (detached, -d):
   display-message -p '#{session_name}':  [s5]           # <<< LAST-CREATED, not the client's (driver)!
   list-clients:  /dev/pts/101 -> driver                 # client is STILL on driver
C) -t target forms:
   display-message -t '{client}' -p '#{session_name}':  []   (empty — this form does not resolve)
   display-message -p -t '=driver' '#{session_name}':   []   (empty)
D) new-window / select-window on driver:
   after `new-window -t driver` + `select-window -t driver`:  display-message -> [s5]   (UNCHANGED)
   after `split-window -t s5`:                                display-message -> [s5]
E) switch-client to driver:
   after `switch-client -t "=driver"`:  display-message -> [driver]   # <<< switch-client RESETS it
```

**Conclusion:** `display-message -p '#{session_name}'` (no `-t`) resolves to the
server's notion of the "current session" — which is the **last session that was
CREATED or SWITCHED TO**, NOT necessarily the attached client's session. Only
`attach` and `switch-client` reset this pointer; `new-session -d`,
`select-window`, `new-window`, `split-window` do NOT.

**Why this is load-bearing for T5.S1:** `livepicker.sh` activate STEP-2 saves
`@livepicker-orig-session = "$(tmux display-message -p '#{session_name}')"`. If
the test creates fixture sessions AFTER `attach_test_client`, the pointer is the
LAST fixture (e.g. `s5`), so activate saves `ORIG_SESSION=s5` (WRONG — should be
`driver`). Then cancel's `switch-client -t "=$ORIG_SESSION"` = `switch-client -t
=s5` is a REAL navigation (driver→s5, not same-session) → the recorder appends s5
→ **FALSE POLLUTION — the test FALSE-FAILS.** (This is EXACTLY what the first
verify run showed: `@test-hist` became `driver\ns5` after browse+cancel.)

**THE FIX (verified): create ALL fixture sessions BEFORE `attach_test_client`.**
The attach (`tmux attach -t driver`) resets the pointer to `driver`, so activate's
`display-message` returns `driver` → `ORIG_SESSION=driver` → cancel's switch is
same-session → deduped → 0 pollution. Verified (`/tmp/lp_poll_fix.sh`): with
fixtures-before-attach, T1/T2/T3 ALL PASS.

**Belt-and-braces:** the `lp_install_history_recorder` helper additionally does an
explicit `tmux switch-client -t "=$TEST_DRIVER_SESSION"` right after seeding. Since
the client is on driver post-attach, this is a same-session switch → deduped → 0
pollution, AND it FORCES the pointer to driver (defeats the gotcha even if some
prior op moved it). Section E proves switch-client resets the pointer.

### FINDING 4 — the recorder is SYNCHRONOUS (run-shell WITHOUT -b); the test's next read sees the update  [VERIFIED]

`set-hook -g client-session-changed "run-shell '$REC #{session_name}'"` (NO `-b`)
runs the recorder synchronously: the tmux server blocks the triggering
`switch-client` until the recorder's `run-shell` completes. So when
`input-handler.sh confirm` (or cancel) returns, the recorder has ALREADY updated
`@test-*`. The test's very next `tmux show-option -gqv @test-hist` sees the
post-switch state. Verified: every `@test-hist` assertion in T1/T2/T3 read the
value IMMEDIATELY after the switch and saw the correct state (no sleep needed).
This mirrors the real plugin's hook (`session_history.tmux:22` uses NO `-b`).

(The `-b` flag would make it background/async — the recorder might not finish
before the test reads `@test-*` → flaky FALSE-fails. DO NOT use `-b`.)

### FINDING 5 — the recorder MUST call `tmux` via the BAKED-IN ABSOLUTE shim path  [VERIFIED]

The recorder maintains tmux OPTIONS (`@test-*`), so it must call `tmux
show-option`/`set-option`. The recorder is invoked by the tmux SERVER's
`run-shell`, which inherits the SERVER's environment — NOT necessarily the test
shell's PATH (where the shim dir was prepended by setup_socket). A bare `tmux`
inside the recorder may resolve to `/usr/bin/tmux` (the REAL server) → would
corrupt the user's REAL `@session-history-*` and miss the isolated socket.

**THE FIX (verified, mirrors setup_socket's own shim-heredoc pattern):** bake the
ABSOLUTE shim path into the recorder at write time via an UNQUOTED heredoc:

```bash
cat > "$TMUX_SOCK_DIR/session_history_rec.sh" <<EOF
#!/usr/bin/env bash
T="$TMUX_SOCK_DIR/tmux"        # <<< baked at write time; the shim execs REAL_TMUX -L TEST_SOCKET
to="\$1"
cur="\$(\$T show-option -gqv @test-current 2>/dev/null)"
...
EOF
```

`$TMUX_SOCK_DIR` expands at WRITE time (the recorder gets the absolute shim path);
`\$1` etc. stay literal. The shim (`$TMUX_SOCK_DIR/tmux`, written by setup_socket)
does `exec "$REAL_TMUX" -L "$TEST_SOCKET" "$@"` → hits ONLY the isolated socket.
Verified: the recorder's `\$T show-option`/`set-option` calls hit the isolated
socket (the user's real server was provably untouched — the recorder never
references `/usr/bin/tmux`).

### FINDING 6 — the recorder temp file is auto-cleaned (write it into `$TMUX_SOCK_DIR`)  [VERIFIED via setup_socket/teardown_socket]

setup_socket (T1.S1) writes the `tmux` shim into `$TMUX_SOCK_DIR` and exports it;
teardown_socket does `[ -n "${TMUX_SOCK_DIR:-}" ] && [ -d "$TMUX_SOCK_DIR" ] && rm
-rf "$TMUX_SOCK_DIR"`. So writing the recorder to `$TMUX_SOCK_DIR/session_history_rec.sh`
means run.sh's per-test `teardown_test` removes it automatically — NO manual
cleanup, NO trap (test bodies cannot own the lifecycle — run.sh does). The P1.M6
mocks used a SEPARATE `mktemp` + a `trap cleanup EXIT` because they were standalone
executables; the real test is SOURCED by run.sh, so the `$TMUX_SOCK_DIR` placement
is the clean idiom. `$TMUX_SOCK_DIR` is in scope when each `test_*` runs (setup_test
→ setup_socket sets it before the test body).

### FINDING 7 — a CLIENT is required (unlike T4.S1 preview tests)  [VERIFIED]

T4.S1's `test_preview.sh` did NOT call `attach_test_client` — `preview.sh` is
client-independent (reads the driver from `@livepicker-orig-session`). T5.S1 is
DIFFERENT: it drives `livepicker.sh` activate (uses `display-message -p
'#{session_name}'` STEP-2 + `refresh-client -S`) and `input-handler.sh`
confirm/cancel (use `switch-client`). ALL of those REQUIRE an attached client.
So every pollution `test_*` calls `attach_test_client` FIRST (mirrors T3.S1's
`test_functional.sh`, which also `attach_test_client`s before driving livepicker.sh).

### FINDING 8 — navigation NEVER fires the hook (Invariant A, RE-PROVEN)  [VERIFIED]

The recorder saw ZERO events during 5 `next-session` calls (debug output: `@test-hist`
stayed `[driver|]` through all 5 navs). `next-session` → `preview.sh` → `link-window`
+ `select-window` (NOT `switch-client`). `link-window`/`unlink-window` fire only
`window-linked`/`window-unlinked`; `select-window` fires `session-window-changed`
(suppressed by activate T4.S2). NONE fire `client-session-changed`. So the only
hook events in the whole flow are the confirm switch (1 navigation) and the cancel
switch (same-session, deduped → 0). This is the empirical proof of PRD §4/§14
"browsing does not fire client-session-changed."

### FINDING 9 — the toggle, simulated  [VERIFIED]

The real `do_toggle` does `switch-client -t "$PREV"` (PREV = the session before
the current). The stand-in maintains `@test-prev` (= from on navigation). So the
test simulates the toggle with one line:

```bash
tmux switch-client -t "=$(tmux show-option -gqv @test-prev)"
```

After a confirm pick (driver→target): `@test-prev=driver` (from=driver). The
toggle switches to driver → recorder navigation (target→driver, append driver at
tip, `@test-prev`=target) → client lands on driver = the pre-pick session. Verified
(T3): `display-message` after the toggle == the pre-pick session. The stand-in
mirrors `do_toggle`/`do_hook` EXACTLY (the toggle is a navigation, target appended
at the tip — faithful to the real engine's "end of road" semantics).

### FINDING 10 — house style for the test file + the recorder exception  [VERIFIED via test_self.sh/test_functional.sh + system_context §9]

The test FILE mirrors `test_functional.sh`/`test_preview.sh` (the sibling
sourced-by-run.sh test files): shebang `#!/usr/bin/env bash`; `set -u` INHERITED
(do NOT re-declare; mirror test_self.sh's "`# set -u is inherited`"); TABS; `local`
for all function locals; file-level `# shellcheck disable=SC2154,SC2016,SC2034,SC2086`
(assert_*/attach_test_client/$LIVEPICKER_SCRIPTS/$TEST_DRIVER_SESSION/$TMUX_SOCK_DIR
are defined by run.sh's sources, not here). SOURCED by run.sh → define `test_*` +
`lp_install_history_recorder` ONLY; NO side effects on source; NO setup_test/
teardown_test calls (run.sh owns the per-test cycle); signal failure ONLY via
`fail`/`assert_*` (NEVER `exit` — run.sh reads TEST_STATUS in the CURRENT shell).

**Recorder exception:** the recorder (`session_history_rec.sh`) is a SEPARATE
script invoked by the tmux server's `run-shell`. It must NEVER crash mid-hook (a
crash leaves `@test-*` inconsistent → mysterious false-fails). So the recorder is
written WITHOUT `set -u` (matching the proven P1.M6 mock `rec.sh`, which has no
set statements) and with explicit defaults on every read (`:-0`, `2>/dev/null`).
Robustness > house style for a hook-invoked stand-in. The real engine uses
`set -u` but it is careful; the stand-in prioritizes not-crashing.

### FINDING 11 — the validated end-to-end run  [VERIFIED]

`/tmp/lp_poll_fix.sh` (fixtures-before-attach + the faithful recorder + the
force-switch) ran ALL three scenarios on one isolated socket and printed:

```
== T1: browse+cancel ==
  ORIG_SESSION after activate: [driver]
  ok   browse+cancel: @test-hist unchanged
  ok   browse+cancel: client on driver
== T2: browse+confirm one entry ==
  ok   confirm: exactly one new entry [s5], no intermediates
== T3: toggle after confirm ==
  ok   confirm landed on pickme
  ok   @test-prev==driver (pre-pick)
  ok   toggle returned to pre-pick (driver)
==================================================
ALL PASSED
```

(Note: the verify conflated T1/T2/T3 in ONE server with manual re-seeds; the REAL
test is SOURCED by run.sh, which gives EACH `test_*` a FRESH isolated socket via
per-test setup_test/teardown_test — so there is NO cross-test leakage and NO need
to re-seed/reset between tests. Each test seeds its own baseline via
`lp_install_history_recorder`.)

## The validated stand-in recorder (ready to paste into lp_install_history_recorder)

```bash
# Written to $TMUX_SOCK_DIR/session_history_rec.sh (auto-cleaned by teardown_socket).
# Bakes the ABSOLUTE shim path ($TMUX_SOCK_DIR/tmux) so run-shell's recorder hits
# the isolated socket (FINDING 5). Mirrors do_hook (FINDING 1); NO set -u (FINDING 10).
cat > "$TMUX_SOCK_DIR/session_history_rec.sh" <<EOF
#!/usr/bin/env bash
T="$TMUX_SOCK_DIR/tmux"
to="\$1"
cur="\$(\$T show-option -gqv @test-current 2>/dev/null)"
if [ -z "\$cur" ]; then
	\$T set-option -g @test-hist "\$to"
	\$T set-option -g @test-current "\$to"
	\$T set-option -g @test-prev "\$to"
	\$T set-option -g @test-idx 0
	exit 0
fi
[ "\$to" = "\$cur" ] && exit 0
idx="\$(\$T show-option -gqv @test-idx 2>/dev/null)"; [ -z "\$idx" ] && idx=0
mapfile -t HIST < <(\$T show-option -gqv @test-hist 2>/dev/null)
nh=(); i=0
for line in "\${HIST[@]}"; do
	[ "\$i" -gt "\$idx" ] && break
	[ "\$line" != "\$to" ] && nh+=("\$line")
	i=\$((i+1))
done
nh+=("\$to"); newidx=\$(( \${#nh[@]} - 1 ))
LF=\$'\n'; newhist=""
for line in "\${nh[@]}"; do newhist="\${newhist:+\$newhist\$LF}\$line"; done
\$T set-option -g @test-hist "\$newhist"
\$T set-option -g @test-idx "\$newidx"
\$T set-option -g @test-prev "\$cur"
\$T set-option -g @test-current "\$to"
EOF
chmod +x "$TMUX_SOCK_DIR/session_history_rec.sh"
tmux set-hook -g client-session-changed "run-shell '$TMUX_SOCK_DIR/session_history_rec.sh #{session_name}'"
tmux set-option -g @test-hist "$TEST_DRIVER_SESSION"
tmux set-option -g @test-current "$TEST_DRIVER_SESSION"
tmux set-option -g @test-prev "$TEST_DRIVER_SESSION"
tmux set-option -g @test-idx 0
tmux switch-client -t "=$TEST_DRIVER_SESSION"   # force the pointer (FINDING 3); same-session -> deduped
```

## Sources

- Empirical: isolated-socket probe/verify scripts run 2026-07-06 on tmux 3.6b
  (`/tmp/lp_poll_verify.sh`, `/tmp/lp_poll_debug.sh`, `/tmp/lp_dm_probe.sh`,
  `/tmp/lp_poll_fix.sh` — all kill-server'd on exit).
- `~/.config/tmux/plugins/tmux-session-history/scripts/session_history.sh` — the real
  engine (`do_hook` same-session short-circuit + forward-collapse; `do_toggle`; the
  `@session-history-*` state model). THE authoritative model for the stand-in.
- `~/.config/tmux/plugins/tmux-session-history/session_history.tmux:22` — the exact
  hook wire `run-shell 'SCRIPT hook "#{session_name}"'` (NO `-b` → synchronous).
- `plan/001_fd5d622d3939/P1M5T2S1/research/restore_keep_cancel_findings.md`
  FINDING A/B — the same-session hook-fire + dedup proof (cancel → 0 entries);
  the smart-recorder wire.
- `plan/001_fd5d622d3939/P1M6T3S1/research/confirm_findings.md` FINDING 7 — confirm
  → exactly 1 entry (navigation); the smart recorder.
- `plan/001_fd5d622d3939/P1M6T3S1/research/confirm_mock.sh` +
  `P1M6T4S1/research/cancel_mock.sh` — the proven smart-recorder heredoc pattern
  (the seed of the stand-in).
- `tests/setup_socket.sh` (T1.S1) — `$TMUX_SOCK_DIR` (auto-cleaned) + the shim +
  `attach_test_client`/`detach_test_client` + the `TEST_DRIVER_SESSION` export.
- `tests/helpers.sh`/`tests/run.sh` (T2.S1) — `fail`/`assert_*` + the per-test
  setup_test/teardown_test cycle + `TEST_STATUS`.
- `scripts/livepicker.sh` STEP-2 (the `display-message -p '#{session_name}'` that
  FINDING 3 is about), `scripts/input-handler.sh` (next/confirm/cancel), `scripts/restore.sh`
  (STEP-3 cancel switch to ORIG_SESSION).
- `plan/001_fd5d622d3939/architecture/system_context.md` §3 (Invariant A), §6
  (session-history composition/dedup), §9 (shell style).
- `PRD.md` §4 (the core rule), §14 (pollution analysis), §15.18 (Pollution — the
  three bullets this suite implements).
