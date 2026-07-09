#!/usr/bin/env bash
# tests/setup_socket.sh — tmux-livepicker socket-isolation test harness (P1.M7.T1.S1).
#
# Provides a PATH-wrapper `tmux` shim so the plugin's scripts (which call bare
# `tmux`) transparently hit an ISOLATED tmux server on `tmux -L "$TEST_SOCKET"`,
# leaving the user's REAL server (the live /tmp/tmux-$UID/default socket) totally
# untouched (PRD §15 Validation). This file IS the mocking infrastructure for the
# whole P1.M7 test suite: every later test (P1.M7.T2–T6) `source`s it and gets
# an isolated `tmux` for free.
#
# CONTRACT: sourcing this file has NO side effects — it defines functions only,
# exports NOTHING, starts NO server. All work happens inside setup_socket/
# teardown_socket called by the consumer. Executing this file directly
# (`bash tests/setup_socket.sh`) runs setup_socket_self_test, which exits 0/1.
#
# Mirrors scripts/utils.sh's sourced-library style: set -u ONLY (NOT -e / NOT -o
# pipefail — show-option/has-session/kill-server legitimately return nonzero),
# `local` for all function locals, TABS for indent, quote everything.
# See plan/001_fd5d622d3939/P1M7T1S1/research/setup_socket_findings.md for the
# empirical ground-truth behind every design choice (FINDING 1–12).

# TEST_* / TMUX_* / REAL_TMUX are set by setup_socket at runtime (downstream
# tests source this file; the exports appear "unused" to shellcheck but are the
# documented contract -> SC2154). The self-test's inline assert helper does
# `eval "$1"` on a single-quoted test expression (the resurrect/mock idiom), so
# vars expand at eval time, not parse time — shellcheck flags the single quotes
# (SC2016) and the "unused" locals (SC2034) as false positives. This mirrors the
# P1.M6 throwaway *_mock.sh assertion style.
# shellcheck disable=SC2154,SC2016,SC2034,SC2086

set -u   # NOT -e; NOT -o pipefail.

CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIVEPICKER_ROOT="$(cd "$CURRENT_DIR/.." && pwd)"
LIVEPICKER_SCRIPTS="$LIVEPICKER_ROOT/scripts"

# Documented baseline fixture names (populated by setup_socket; tests may add
# their own via bare `tmux new-session` — those calls hit the isolated socket).
TEST_DRIVER_SESSION="driver"           # attached-client home; picker-activate origin; preview-link target.
TEST_FIXTURE_SESSIONS="alpha beta"     # populate the picker list; ≥2 choices for filter/nav tests.

# Socket-bound state for the OPTIONAL attach_test_client/detach_test_client pair.
TEST_CLIENT_PID=""

# setup_socket [socket_name] — create a temp dir; write + chmod +x the `tmux`
# shim; prepend the shim dir to PATH; start the isolated tmux server on
# `tmux -L "$TEST_SOCKET"`; spawn the documented baseline fixtures. Exports
# TEST_SOCKET / TMUX_SOCK_DIR / TMUX_SOCKET_PATH / REAL_TMUX / LIVEPICKER_*.
#
# The shim is ONE line: `exec "$REAL_TMUX" -L "$TEST_SOCKET" "$@"`. $REAL_TMUX is
# resolved by ABSOLUTE path BEFORE PATH is modified (FINDING 6) so the shim
# never recurses into itself (a bare `tmux` inside the shim would re-find the
# shim forever). Written via an UNQUOTED heredoc so $TEST_SOCKET + $REAL_TMUX
# bake in at write time while `"\$@"` passes the caller's argv through quoted
# at runtime (FINDING 5).
setup_socket() {
	local socket_name="${1:-}"
	local socket_base

	# (b) Honor an optional socket name else use a $$-unique default (FINDING 11:
	#     $$ = sourcing shell PID — NOT subshell-local — stable + unique per run,
	#     so parallel test runs don't collide on the same -L socket).
	if [ -n "$socket_name" ]; then
		TEST_SOCKET="$socket_name"
	else
		TEST_SOCKET="livepicker-test-$$"
	fi

	# (c) Temp dir holding the `tmux` shim (rm -rf'd on teardown).
	TMUX_SOCK_DIR="$(mktemp -d)"

	# (a) Resolve REAL_TMUX by ABSOLUTE path BEFORE prepending the shim dir to
	#     PATH (FINDING 6), so `command -v tmux` returns the REAL binary (not a
	#     prior shim). Default /usr/bin/tmux (verified: command -v tmux ==
	#     /usr/bin/tmux here). Paranoia: if the detected path already lives under
	#     our shim dir (re-source case), force the default.
	REAL_TMUX="${REAL_TMUX:-$(command -v tmux || echo /usr/bin/tmux)}"
	case "$REAL_TMUX" in
		"$TMUX_SOCK_DIR"/*) REAL_TMUX="/usr/bin/tmux" ;;
	esac

	# (d) Write the shim via UNQUOTED heredoc (FINDING 5): $TEST_SOCKET +
	#     $REAL_TMUX expand at WRITE time (baked in); `"\$@"` is escaped so the
	#     caller's argv passes through quoted at runtime. `exec` replaces the
	#     shim process (no fork). The ABSOLUTE $REAL_TMUX means PATH is never
	#     consulted inside the shim -> NO RECURSION (FINDING 6).
	cat > "$TMUX_SOCK_DIR/tmux" <<EOF
#!/usr/bin/env bash
exec "$REAL_TMUX" -L "$TEST_SOCKET" "\$@"
EOF
	chmod +x "$TMUX_SOCK_DIR/tmux"

	# (e) Compute the socket file path (FINDING 3): tmux -L <name> puts the
	#     socket at ${TMPDIR:-/tmp}/tmux-$(id -u)/<name>. $(id -u) is portable
	#     ($UID is bash-only; both work here). The REAL server's socket is the
	#     same dir + "default".
	socket_base="${TMPDIR:-/tmp}/tmux-$(id -u)"
	TMUX_SOCKET_PATH="$socket_base/$TEST_SOCKET"

	# (f) Export the environment contract every downstream test + every spawned
	#     subprocess relies on; prepend the shim dir to PATH so the shim wins.
	export TEST_SOCKET
	export TMUX_SOCK_DIR
	export TMUX_SOCKET_PATH
	export REAL_TMUX
	export LIVEPICKER_ROOT
	export LIVEPICKER_SCRIPTS
	export TEST_DRIVER_SESSION
	export TEST_FIXTURE_SESSIONS
	PATH="$TMUX_SOCK_DIR:$PATH"
	export PATH

	# (g) Start the isolated server (bare `tmux` now resolves to the shim ->
	#     isolated -L socket). The server intentionally sources the user's
	#     ~/.tmux.conf: some tests rely on config-derived state (e.g.
	#     test_keyrepurpose depends on the root-table C-M-Tab/C-M-BTab
	#     swap-window bindings; test_preview_clip depends on the client's
	#     configured terminal size). -x 120 -y 40 = a sane fixed size for
	#     capture-pane golden comparisons (matches the throwaway P1.M6 mocks).
	tmux new-session -d -s "$TEST_DRIVER_SESSION" -x 120 -y 40

	# (h) Spawn the baseline fixtures (FINDING 8): `alpha`/`beta` detached
	#     populate the picker list; a 2nd window + split pane in `driver`
	#     exercises list-windows/list-panes; a multi-pane window in `beta` gives
	#     the live all-panes preview (PRD §15.19) a candidate with ≥2 panes.
	for s in $TEST_FIXTURE_SESSIONS; do
		tmux new-session -d -s "$s" -x 120 -y 40
	done
	tmux new-window -t "$TEST_DRIVER_SESSION" -n extra
	tmux split-window -h -t "$TEST_DRIVER_SESSION:extra"
	tmux split-window -v -t "$TEST_DRIVER_SESSION:extra.0"
	tmux split-window -h -t "beta"
}

# teardown_socket — kill the isolated server AND remove the shim dir AND remove
# the orphaned socket file. Idempotent (safe when setup didn't run or already
# tore down — every step is guarded). Does NOT touch the user's real server:
# the bare `tmux` resolves to our shim -> hits ONLY the isolated -L socket.
teardown_socket() {
	# Detach any client we attached FIRST (FINDING 7: an attached client can
	# delay kill-server's server exit).
	detach_test_client 2>/dev/null || true

	# kill-server kills the SERVER but LEAVES the socket file (FINDING 2).
	# Guarded so teardown is idempotent (no TEST_SOCKET yet, or server already dead).
	[ -n "${TEST_SOCKET:-}" ] && tmux kill-server 2>/dev/null || true

	# Remove the shim dir (guard: maybe setup never ran / already tore down).
	[ -n "${TMUX_SOCK_DIR:-}" ] && [ -d "$TMUX_SOCK_DIR" ] && rm -rf "$TMUX_SOCK_DIR" 2>/dev/null || true

	# AND remove the orphaned socket file (FINDING 2/3: it lives OUTSIDE the
	# shim dir, at ${TMPDIR:-/tmp}/tmux-$UID/$TEST_SOCKET — kill-server leaves
	# it behind). This is the justified SUPERSET of the contract's "rm -rf the
	# temp dir"; the self-test's file-gone assertion relies on it.
	[ -n "${TMUX_SOCKET_PATH:-}" ] && rm -f "$TMUX_SOCKET_PATH" 2>/dev/null || true
}

# lp_sweep_orphans — kill orphaned tmux -L test servers + remove their socket
# files left behind by prior killed/interrupted test runs (M4 hygiene fix). The
# shipped suite is slow (~2-3 min) and frequently interrupted mid-run, which
# skips teardown_socket and leaks `lp-*`/`livepicker-test-*` servers that consume
# memory indefinitely. This sweeps them WITHOUT touching the user's real server
# (the real server runs on the `default` socket with no -L flag, so it is never
# matched by the `tmux -L (lp-|livepicker-test-)` pattern). Idempotent + safe.
# Uses $REAL_TMUX (absolute) to bypass any PATH shim.
lp_sweep_orphans() {
	local tmux_bin="${REAL_TMUX:-/usr/bin/tmux}"
	local sock_dir line name sock
	sock_dir="${TMPDIR:-/tmp}/tmux-$(id -u)"
	# Kill orphaned servers first (so their socket files are releasable). Walk
	# live tmux processes; match `tmux -L <lp-|livepicker-test-...>`. pgrep -af gives
	# the full command line (avoids SC2009 ps|grep).
	while IFS= read -r line; do
		[ -n "$line" ] || continue
		# Extract the socket name following `-L`. Word-split the command line.
		# shellcheck disable=SC2086
		set -- $line
		while [ "$#" -gt 0 ]; do
			if [ "$1" = "-L" ] && [ "$#" -gt 1 ]; then
				name="$2"
				case "$name" in
					lp-*|livepicker-test-*)
					sock="$sock_dir/$name"
					"$tmux_bin" -L "$name" kill-server 2>/dev/null || true
					rm -f "$sock" 2>/dev/null || true
					;;
				esac
				shift 2
				continue
			fi
			shift
		done
	done < <(pgrep -af 'tmux -L (lp-|livepicker-test-)' 2>/dev/null)
	# Also remove any leftover orphan socket files whose server already exited.
	[ -d "$sock_dir" ] && find "$sock_dir" -maxdepth 1 -type s \
		\( -name 'lp-*' -o -name 'livepicker-test-*' \) -delete 2>/dev/null || true
}

# attach_test_client [session] — OPTIONAL, socket-bound convenience for
# downstream tests (P1.M7.T3-T6) that need an attached client (switch-client /
# display-message -p / refresh-client -S all REQUIRE one — FINDING 7). NOT
# exercised by setup_socket_self_test; does NOT duplicate T2.S1's helpers.sh
# (which owns fail/test_* discovery + higher-level fixtures).
attach_test_client() {
	local sess="${1:-$TEST_DRIVER_SESSION}"
	# `script` (util-linux) gives a pty; attach to the isolated server via the
	# shim (bare `tmux` -> isolated -L socket).
	script -qec "tmux attach -t '$sess'" /dev/null >/dev/null 2>&1 &
	TEST_CLIENT_PID=$!
	sleep 0.5   # let the attach settle so list-clients/display-message see it
}

# detach_test_client — kill the client spawned by attach_test_client, then wait
# (FINDING 7). Idempotent (no-op when nothing attached).
detach_test_client() {
	[ -n "${TEST_CLIENT_PID:-}" ] && kill "$TEST_CLIENT_PID" 2>/dev/null || true
	[ -n "${TEST_CLIENT_PID:-}" ] && wait "$TEST_CLIENT_PID" 2>/dev/null || true
	TEST_CLIENT_PID=""
}

# setup_socket_self_test — runs ONLY on direct execution (FINDING 9). Exercises
# setup → the 4 isolation/cleanup assertion groups (FINDING 4) → teardown and
# exits 0/1. Inlines a tiny local assert helper (FINDING 10: borrow resurrect's
# counted-assert STYLE ONLY, not its teardown_helper; the full fail/test_*
# machinery belongs to T2.S1's helpers.sh — this self-test has zero deps on it).
setup_socket_self_test() {
	local fail=0
	local n=0
	local socket_base
	local real_before
	local real_after
	local isolated_list
	local fixture_sorted

	ok()  { echo "  ok   [$n] $1"; }
	bad() { echo "  FAIL [$n] $1"; fail=1; }
	assert() {
		n=$((n + 1))
		if eval "${1:?}"; then ok "$2"; else bad "$2 [$1]"; fi
	}

	socket_base="${TMPDIR:-/tmp}/tmux-$(id -u)"

	echo "== setup_socket self-test =="

	# Snapshot the REAL server's session list BEFORE the cycle (the gold-standard
	# non-pollution proof — PRD §15 invariant). /usr/bin/tmux bypasses the shim.
	# (server may have zero sessions here — that is fine; we compare before/after.)
	real_before="$(/usr/bin/tmux list-sessions -F '#{session_name}' 2>/dev/null | sort)"

	# --- setup ---
	setup_socket

	# Group (1): isolated list == exactly the fixtures (sorted compare). The
	# bare `tmux` resolves to the shim -> isolated -L socket.
	isolated_list="$(tmux list-sessions -F '#{session_name}' 2>/dev/null | sort)"
	fixture_sorted="$(printf '%s\n' "$TEST_DRIVER_SESSION" $TEST_FIXTURE_SESSIONS | sort)"
	assert '[ "$isolated_list" = "$fixture_sorted" ]' "isolated list == exactly the fixtures"

	# Group (2a): the REAL server lacks every fixture name.
	assert '! /usr/bin/tmux list-sessions -F "#{session_name}" 2>/dev/null | grep -Eq "^(driver|alpha|beta)$"' "real server lacks the fixture sessions"

	# Group (3): the socket differs from the real default socket.
	assert '[ "$TMUX_SOCKET_PATH" != "$socket_base/default" ]' "socket path differs from real default"

	# --- teardown ---
	teardown_socket

	# Group (4): after teardown, the server is DEAD (has-session rc != 0) AND
	# the socket file is GONE (only because teardown rm -f'd it — FINDING 2).
	assert '! tmux has-session -t "=driver" 2>/dev/null' "server dead (has-session rc != 0)"
	assert '[ ! -e "$TMUX_SOCKET_PATH" ]' "socket file removed by teardown"

	# Group (2b): the REAL server's session list is byte-identical before/after
	# the full setup→teardown cycle (the gold-standard non-pollution proof).
	real_after="$(/usr/bin/tmux list-sessions -F '#{session_name}' 2>/dev/null | sort)"
	assert '[ "$real_before" = "$real_after" ]' "real server byte-identical before/after (PRD §15)"

	echo "=================================================="
	if [ "$fail" = "0" ]; then
		echo "ALL ASSERTIONS PASSED"
		return 0
	else
		echo "SOME ASSERTIONS FAILED"
		return 1
	fi
}

# Sourcing this file defines functions ONLY (no server started, nothing
# exported). Executing it directly runs the self-test (FINDING 9). Mirror
# utils.sh's no-side-effects CONTRACT.
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
	setup_socket_self_test
fi
