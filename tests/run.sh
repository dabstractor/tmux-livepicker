#!/usr/bin/env bash
# tests/run.sh — tmux-livepicker test suite entry point (P1.M7.T2.S1).
#
# Sources tests/setup_socket.sh (socket isolation — P1.M7.T1.S1) + tests/helpers.sh
# (assertions + setup_test/teardown_test) + every tests/test_*.sh, discovers every
# test_* function via `compgen -A function | grep '^test_'`, and runs each against
# a FRESH isolated tmux server (per-test setup_test -> test -> teardown_test). Prints
# PASS/FAIL per test + a summary; exits 0 iff all passed, else 1.
#
# DESIGN (research FINDING 5): setup_test/teardown_test are the PER-TEST pair (each
# test gets its own fresh fixture via per-test setup/teardown — the work-item §3
# operative clause). This is hermetic: a killed+respawned server cannot leak state
# between tests that mutate shared tmux state (key-table/status/@livepicker-*/linked
# preview). "Runs setup_test once" is satisfied as once-per-test-function.
#
# CONTRACT for test bodies (tests/test_*.sh — P1.M7.T3-T6): define test_* functions
# ONLY (no side effects on source); use bare `tmux` + the baseline fixtures + the
# assert_* helpers; signal failure ONLY via fail/assert_* (which set TEST_STATUS) —
# NEVER exit/return-nonzero-to-abort (run.sh reads TEST_STATUS in the CURRENT shell;
# a bare exit would kill the runner). run.sh brings up + tears down the socket.
#
# set -u ONLY (NOT -e/pipefail); local; TABS. See research/helpers_run_findings.md.
# shellcheck disable=SC1091,SC2154,SC2016,SC2034,SC2086

set -u

CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# (a) Source the isolation layer (setup_socket/teardown_socket) + the assertion
#     layer (assert_*/setup_test/teardown_test). Both are sourced libraries (no
#     side effects on source).
# shellcheck source=setup_socket.sh
source "$CURRENT_DIR/setup_socket.sh"
# shellcheck source=helpers.sh
source "$CURRENT_DIR/helpers.sh"

# (b) Source every test file (defines test_* functions). nullglob => a non-matching
#     glob expands to NOTHING (safe when zero files; FINDING 7). Restore after so
#     later globs aren't surprised.
shopt -s nullglob
for f in "$CURRENT_DIR"/test_*.sh; do
	# shellcheck source=/dev/null
	source "$f"
done
shopt -u nullglob

# (c) Discover test_* in the CURRENT shell (so fail()'s TEST_STATUS is visible —
#     FINDING 7). sort for deterministic order.
tests="$(compgen -A function | grep '^test_' | sort)"

# (d)(e) Per-test fresh-socket cycle.
# Sweep orphaned test servers/sockets from prior interrupted runs FIRST (M4
# hygiene) so a clean run does not accumulate debris, and again at the end.
lp_sweep_orphans 2>/dev/null || true
trap 'lp_sweep_orphans 2>/dev/null || true' EXIT
passed=0
failed=0
total=0
for t in $tests; do
	total=$((total + 1))
	# Per-test UNIQUE socket name (FINDING 5/6): lp-$$-<testname>. setup_socket would
	# default to livepicker-test-$$ (stable $$) — passing a per-test name avoids any
	# collision and keeps the cycle clean across many tests.
	setup_test "lp-$$-${t#test_}"
	TEST_STATUS="pass"   # resurrect idiom; reset before each test.
	# Run in the CURRENT shell (NOT a subshell) so fail/assert_* can set TEST_STATUS.
	"$t"
	if [ "$TEST_STATUS" = "pass" ]; then
		echo "PASS  $t"
		passed=$((passed + 1))
	else
		echo "FAIL  $t"
		failed=$((failed + 1))
	fi
	teardown_test   # kill server + clean tmp — fresh for the next test.
done

# (f) Summary.
echo "----"
echo "$passed passed, $failed failed (of $total)"

# (g) Exit code reflects the aggregate (work-item §4 OUTPUT: exits 0/1).
[ "$failed" -eq 0 ] && exit 0 || exit 1
