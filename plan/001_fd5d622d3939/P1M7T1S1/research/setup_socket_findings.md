# Research Findings — P1.M7.T1.S1: tests/setup_socket.sh (PATH-wrapper tmux shim)

> Empirical ground-truth, verified live on 2026-07-06 against tmux **3.6b** on
> `/usr/bin/tmux`. Every fact below was confirmed by running a probe (see
> PROBE EVIDENCE). This file is the authoritative reference for the PRP.

## 0. What this subtask is (one paragraph)

No sibling plugin ships a socket-isolation test harness (system_context §7;
sibling_plugins §9 — verified zero matches for `socket`/`TMUX_BIN`/`tmux -L`/
PATH-wrapper across session-history, sessionx, resurrect). The PRD §15 phrase
"as in the session-history test" describes a pattern that **does not exist
there**. resurrect uses Vagrant+expect with a real `tmux kill-server` (too heavy,
NOT socket-isolated — it touches the user's live server). So **this subtask
invents the harness.** The plugin scripts call **bare `tmux`** (e.g.
`utils.sh`'s `tmux show-option`, `restore.sh`'s `tmux switch-client`). A PATH
shim — an executable `tmux` wrapper placed FIRST in `PATH` that rewrites every
bare call to `/usr/bin/tmux -L "$TEST_SOCKET" "$@"` — lets those scripts hit an
**isolated socket with ZERO code changes.** `tests/setup_socket.sh` provides
`setup_socket`/`teardown_socket`; every later test (P1.M7.T2–T6) sources it and
gets an isolated `tmux` for free. This file IS the mocking infrastructure.

---

## FINDING 1 — the shim intercepts bare `tmux`; isolation is total

Verified by probe. Build a temp dir, write `tmpdir/tmux`:
```bash
#!/usr/bin/env bash
exec /usr/bin/tmux -L "<SOCK>" "$@"
```
`chmod +x`, `export PATH="$tmpdir:$PATH"`. Then:
- `type tmux` → `tmux is /tmp/tmp.XXXX/tmux` (the SHIM, not `/usr/bin/tmux`).
- Bare `tmux new-session -d -s driver` starts a server on the `-L` socket.
- `tmux list-sessions` (bare) → shows ONLY the isolated sessions.
- `/usr/bin/tmux list-sessions` (absolute, bypasses PATH) → does **NOT** see the
  isolated `driver`/`alpha` (it lists the user's REAL sessions).

**Conclusion:** the shim is transparent to callers (same argv) and hermetic
(isolated server has no overlap with the real server). This is the spine of the
whole P1.M7 test suite.

---

## FINDING 2 — CRITICAL GOTCHA: `kill-server` leaves the socket FILE on disk

The single most important gotcha for the contract's "assert the socket is gone"
self-test (§5). Probe step D:
```
tmux kill-server
has-session -t '=driver'  → rc=1          # server is DEAD
list-sessions             → rc=1          # server is DEAD
[ -e "$SOCKET" ]          → YES-lingers   # but the FILE is still on disk!
[ -S "$SOCKET" ]          → still -S (file inert)   # it's a dead unix socket
```

So `tmux kill-server` kills the **server** but does **NOT unlink the socket
file**. The contract's teardown ("`tmux kill-server` ... and `rm -rf` the temp
dir") removes the SHIM dir but NOT the socket file, which lives at
`/tmp/tmux-$UID/$SOCK` (OUTSIDE the temp dir). Evidence: `/tmp/tmux-1000/`
already contains ~24 orphaned `lp-*` socket files left by the throwaway
`*_mock.sh` harnesses from P1.M6.T3/T4 (they each `kill-server`'d but never
removed the socket file).

**Resolution (bake into teardown + the self-test):**
1. `teardown_socket` must do THREE things, not two: `tmux kill-server` (via shim)
   **+** `rm -rf "$TMUX_SOCK_DIR"` (the shim) **+** `rm -f "$TMUX_SOCKET_PATH"`
   (the orphaned socket file). The `rm -f` is a justified SUPERSET of the
   contract's "rm -rf the temp dir" — the contract predates this finding.
2. The self-test's "assert the socket is gone" must assert **server-deadness**
   (`tmux has-session -t '=driver'` returns NONZERO — the robust, portable
   signal), and OPTIONALLY assert the file is gone (`[ ! -e "$TMUX_SOCKET_PATH" ]`,
   which holds only because teardown `rm -f`'d it). Asserting file-gone WITHOUT
   the `rm -f` would FALSE-FAIL.

---

## FINDING 3 — the socket path is `${TMPDIR:-/tmp}/tmux-$UID/$SOCK`

Probe step A/C: with `TMPDIR` unset, `tmux -L lp-probe2-226750` created the
socket at `/tmp/tmux-1000/lp-probe2-226750` (`UID`=1000). tmux's `-L <name>`
socket base is `${TMPDIR:-/tmp}/tmux-<uid>/`. So:
```bash
SOCKET_BASE="${TMPDIR:-/tmp}/tmux-$(id -u)"          # or $UID in bash
TMUX_SOCKET_PATH="$SOCKET_BASE/$TEST_SOCKET"
```
This is how teardown computes the file to `rm -f`. (Bash exposes `$UID`
read-only; `id -u` is the portable form. Both equal 1000 here.)

**The real server's socket** is `${TMPDIR:-/tmp}/tmux-$(id -u)/default` —
visible as the `TMUX` env var's first field when inside tmux
(`/tmp/tmux-1000/default,2922,10`). The contract's "confirm the real user server
is untouched by checking its socket differs" is satisfied by asserting
`"$TMUX_SOCKET_PATH" != "$SOCKET_BASE/default"` (trivially true since
`$TEST_SOCKET != "default"`) — AND, more meaningfully, by asserting the real
server's session list lacks the test sessions (FINDING 4).

---

## FINDING 4 — the three isolation self-test assertions (contract §5), made concrete

The contract §5 self-test ("run setup, assert `tmux list-sessions` shows only
the test sessions, assert the real server via /usr/bin/tmux is unchanged, run
teardown, assert the socket is gone") decomposes into exactly these checks:

1. **Isolated list is exactly the fixtures.** After `setup_socket`:
   `tmux list-sessions -F '#{session_name}'` (bare → shim) == exactly the set
   `setup_socket` spawned (e.g. `{driver, alpha, beta}`), nothing else leaked in.
2. **Real server lacks the fixtures.** `/usr/bin/tmux list-sessions -F
   '#{session_name}'` does NOT contain any test session name (`driver`/`alpha`/
   `beta`). (Stronger: snapshot the real list BEFORE setup and AFTER teardown;
   assert byte-identical — proves the harness never touched the real server.)
3. **Socket differs.** `"$TMUX_SOCKET_PATH" != "${SOCKET_BASE}/default"`.
4. **After teardown: server dead + file gone.** `tmux has-session -t '=driver'`
   rc != 0 (server dead) AND `[ ! -e "$TMUX_SOCKET_PATH" ]` (file removed by
   teardown's `rm -f`).

All four verified by the probe.

---

## FINDING 5 — the heredoc must bake `$TEST_SOCKET` but pass `$@` through

The shim is written with an **unquoted** heredoc so `$TEST_SOCKET` expands at
WRITE time (the socket name is baked into the shim), while `$@` (and any other
caller-supplied token) is escaped so it survives to runtime:
```bash
cat > "$TMUX_SOCK_DIR/tmux" <<EOF
#!/usr/bin/env bash
exec "$REAL_TMUX" -L "$TEST_SOCKET" "\$@"
EOF
```
- Unquoted `<<EOF` → `$TEST_SOCKET` and `$REAL_TMUX` expand NOW (baked in).
- `"\$@"` → literal `"$@"` in the shim (passes the caller's argv through,
  correctly quoted for paths/args with spaces).
- A quoted heredoc (`<<'EOF'`) would bake NOTHING and the shim would reference an
  unset `$TEST_SOCKET` at runtime → `set -u` crash or a recursion/empty-`-L`
  bug. Use the UNQUOTED form.

**Why `exec` + absolute path (not bare `tmux`):** `exec` replaces the shim
process (no fork). The binary is referenced by its **absolute** path
(`/usr/bin/tmux`, or a detected `REAL_TMUX`) so PATH lookup is bypassed — if the
shim called bare `tmux` it would recurse into itself forever (`tmux` → shim →
`tmux` → shim → …). The contract's "hardcode the real tmux path, NOT recursive"
is exactly this.

---

## FINDING 6 — detect `REAL_TMUX` BEFORE prepending the shim to PATH

The contract literal is `/usr/bin/tmux` (verified: `command -v tmux` ==
`/usr/bin/tmux` here). But for portability (CI, other distros) resolve the real
binary **before** PATH is modified, then bake THAT absolute path into the shim:
```bash
REAL_TMUX="${REAL_TMUX:-$(command -v tmux)}"
# sanity: REAL_TMUX must NOT already be our shim dir (paranoia on re-source)
case "$REAL_TMUX" in "$TMUX_SOCK_DIR"/*) REAL_TMUX=/usr/bin/tmux;; esac
```
This honors the contract's intent ("absolute real path, never recurse") while
not hardcoding `/usr/bin` (which would break where tmux lives at
`/opt/homebrew/bin/tmux` etc.). Keep `/usr/bin/tmux` as the documented default +
fallback (verified value on this machine).

---

## FINDING 7 — `script` (util-linux) gives an attached client; downstream tests need one

`switch-client`, `display-message -p '#{session_name}'`, and `refresh-client -S`
all **require a client**. The throwaway mocks (P1.M6.T3/T4 `*_mock.sh`) attach
one via:
```bash
script -qec "tmux attach -t driver" /dev/null >/dev/null 2>&1 &
sleep 0.5   # let the attach settle
``
`script` is from util-linux (verified: `script from util-linux 2.42.1`,
`/usr/bin/script`). Probe step G confirmed: after this, `tmux list-clients`
shows `/dev/pts/N driver` and `tmux display-message -p '#{session_name}'`
returns `driver`. Teardown must `kill` that background job (`kill %1`/recorded
PID, then `wait`) before `kill-server` (an attached client can delay server
exit).

**Scope decision:** the contract §3 LOGIC lists only "shim+server+spawns a few
test sessions/windows/panes" for `setup_socket` — it does NOT mention a client.
But EVERY functional/preview/pollution test (P1.M7.T3–T6) needs an attached
client, and the client is **tightly coupled to the socket** (needs `TEST_SOCKET`
+ the shim). So `setup_socket.sh` should provide an **optional**
`attach_test_client`/`detach_test_client` helper pair (socket-bound), clearly
marked as a convenience for downstream tests — NOT exercised by setup_socket's
own self-test, and NOT duplicating T2.S1's `helpers.sh` (which owns the resurrect-
style `fail`/`test_*` discovery + higher-level fixtures). This keeps the socket
mechanism coherent in one file while respecting the module boundary.

---

## FINDING 8 — baseline fixtures: small, documented, enumerable

The contract says setup "spawns a few test sessions/windows/panes." The self-test
asserts `tmux list-sessions` == "only the test sessions," so the fixture set must
be **known and enumerable.** Recommended baseline (matches the throwaway mocks'
`driver`+`alpha`/`beta`/`gamma` shape, and gives the preview tests a multi-pane
window):

| Fixture | Why |
|---|---|
| session `driver` | the attached-client home; where the picker activates; where the preview window is linked (the throwaway mocks always activate from `driver`) |
| sessions `alpha`, `beta` (detached) | populate the picker list so filter/navigation tests have ≥2 choices |
| `driver`: a 2nd window + a split pane | exercises `list-windows`/`list-panes` and the layout-restore assertions |
| `beta`: a multi-pane window (e.g. `split-window -h` + `-v`) | the live all-panes preview test (PRD §15.19) needs a candidate with ≥2 panes |

Expose the names as exported vars (`TEST_DRIVER_SESSION`, `TEST_FIXTURE_SESSIONS`)
so tests can reference them and/or add their own via bare `tmux new-session`.
Keep `-x 120 -y 40` (matches the mocks; a sane fixed size for `capture-pane`
golden comparisons).

---

## FINDING 9 — sourced-library-vs-executed-self-test idiom

`tests/setup_socket.sh` is **sourced** by every test (it must DEFINE
`setup_socket`/`teardown_socket` with NO side effects — running it must not start
a server). But the contract §5 demands a SELF-TEST. The standard bash idiom:
```bash
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    setup_socket_self_test   # only when executed directly
fi
```
So `bash tests/setup_socket.sh` (or `./tests/setup_socket.sh`) runs the self-test
exits 0/1; `source tests/setup_socket.sh` defines functions only. This makes the
file its own Level-2 validation gate (no separate runner needed for the harness
itself; T2.S1's `run.sh` will `source` it for the suite).

---

## FINDING 10 — resurrect idioms to borrow (assertion style only, NOT Vagrant/expect)

From `tmux-resurrect/tests/helpers/helpers.sh` (sibling_plugins §9):
```bash
TEST_STATUS="success"
fail_helper()  { echo "$1" >&2; TEST_STATUS="fail"; }
teardown_helper() { rm -f ~/.tmux.conf; rm -rf ~/.tmux/; tmux kill-server 2>/dev/null; }
exit_helper()  { teardown_helper; [ "$TEST_STATUS" = fail ] && exit 1 || exit 0; }
# convention: test_* functions discovered via
#   for t in $(compgen -A function | grep '^test_'); do "$t"; done
```
**Borrow ONLY the `fail`/counted-assert/`test_*`-discovery style** (for the self-
test's `ok`/`bad`/`assert` helpers — same shape as the throwaway mocks). **DO
NOT** borrow resurrect's `teardown_helper` (it `rm -rf ~/.tmux/` + a REAL
`tmux kill-server` — the OPPOSITE of socket-isolated; it would nuke the user's
real server). Our `teardown_socket` kills ONLY the `-L` socket. The `fail`/
`test_*` machinery itself belongs to T2.S1's `helpers.sh`; setup_socket.sh's
self-test inlines a tiny local assert helper (so it has zero deps on helpers.sh).

---

## FINDING 11 — concurrency/parallelism safety of `$$`-unique socket names

Multiple test runs (or the throwaway mocks) can run in parallel. `TEST_SOCKET`
must be globally unique so two harnesses don't collide on the same `-L` socket.
`livepicker-test-$$` (system_context §7's recommendation) — `$$` is the sourcing
shell's PID — is unique per process. The probe used `lp-probe-$$` with no
collision. **GOTCHA:** `$$` is the PID of the shell that STARTED the heredoc;
if a test sources setup_socket in a subshell, `$$` is still the parent shell
(bash quirk: `$$` is NOT subshell-local; `$BASHPID` is). `$$` is fine and stable
here. Keep `livepicker-test-$$` (or `lp-test-$$`); never a fixed name.

---

## FINDING 12 — house style to mirror (from utils.sh + system_context §9)

- Shebang `#!/usr/bin/env bash`; `set -u` (NOT `-e`, NOT `-o pipefail` —
  `show-option`/`has-session` legitimately return nonzero).
- `local` for ALL function locals; tabs for indent (sessionx/resurrect majority).
- `CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"` (utils.sh +
  every sibling).
- Quote everything; addresses use `="=$S"` exact-match, window `@N` ids.
- Sourcing has NO side effects (utils.sh CONTRACT line) — mirrored: sourcing
  setup_socket.sh defines functions only; the self-test runs only under direct
  execution (FINDING 9).

---

## PROBE EVIDENCE (the two probes that established FINDINGS 1–7)

Probe 1 (`/tmp/probe_shim.sh`) confirmed: shim intercepts bare `tmux` (F1);
isolation total — `/usr/bin/tmux` doesn't see `driver`/`alpha` (F1/F4); socket at
`/tmp/tmux-1000/<SOCK>` (F3); real default socket present + differs (F3/F4);
after kill-server the file lingers but list-sessions → "server exited
unexpectedly" (F2); `rm -rf` removes the shim; real server alive throughout (F4).

Probe 2 (`/tmp/probe2.sh`) confirmed: `has-session` rc=1 + `list-sessions` rc=1
after kill-server, file still `[ -S ]` but inert (F2); `rm -f` removes the file
(F2); `${TMPDIR:-/tmp}/tmux-$UID` socket base (F3); `script -qec` attaches a
client + `display-message -p` then works (F7). (Both probes cleaned up their own
sockets; ~24 older `lp-*` orphans from P1.M6 mocks remain as negative evidence
of the kill-server-leaves-file gotcha.)

---

## TL;DR for the PRP

- **Core:** `tests/setup_socket.sh` (sourced) → `setup_socket`/`teardown_socket`.
  Shim = `exec "$REAL_TMUX" -L "$TEST_SOCKET" "$@"` (unquoted heredoc bakes
  `$TEST_SOCKET`; `"\$@"` passes argv; absolute path avoids recursion — F5/F6).
- **teardown = 3 steps** (F2): `tmux kill-server` + `rm -rf "$TMUX_SOCK_DIR"` +
  `rm -f "$TMUX_SOCKET_PATH"`. (kill-server alone leaves the file.)
- **Self-test** (F4/F9): executed-directly → assert isolated-list==fixtures,
  real-list-lacks-fixtures, socket differs, teardown → server-dead + file-gone.
- **Optional** (F7/F8): `attach_test_client`/`detach_test_client` (socket-bound,
  for downstream tests); documented baseline fixtures (driver/alpha/beta + a
  multi-pane window). Marked optional; do not duplicate T2.S1's helpers.sh.
- **Style** (F12): `set -u`, tabs, `local`, `CURRENT_DIR` idiom, no side effects
  on source.
