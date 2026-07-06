#!/usr/bin/env bash
# tests/helpers.sh — tmux-livepicker test assertion + per-test-setup helpers (P1.M7.T2.S1).
#
# Sourced library (NOT executed). Provides the resurrect-style assertion helpers
# (fail/pass/assert_eq/assert_contains) + the per-test setup_test/teardown_test
# pair (THIN delegates to tests/setup_socket.sh's setup_socket/teardown_socket —
# P1.M7.T1.S1). Builds the discovery/runner layer that run.sh + tests/test_*.sh
# (P1.M7.T3-T6) rely on.
#
# CONTRACT: sourcing this file has NO side effects — it defines functions +
# initializes the TEST_STATUS global only; it starts NO server, sources nothing,
# prints nothing (mirrors scripts/utils.sh + tests/setup_socket.sh). run.sh is the
# executable entry point that sources this + setup_socket.sh + every tests/test_*.sh.
#
# Borrows resurrect's TEST_STATUS/fail/test_*-discovery STYLE (system_context §7,
# sibling_plugins §9) and REJECTS resurrect's teardown_helper (a REAL tmux
# kill-server + rm -rf ~/.tmux — the anti-pattern; our teardown_test delegates to
# teardown_socket, which kills ONLY the isolated -L socket).
#
# set -u ONLY (NOT -e — fail/assertions/tmux cmds legitimately "fail" without
# aborting; NOT pipefail); local for all function locals; TABS for indent.
# See plan/001_fd5d622d3939/P1M7T2S1/research/helpers_run_findings.md (FINDING 1-9).
# shellcheck disable=SC2154,SC2016,SC2034,SC2086

set -u

CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# resurrect-style global assertion flag (FINDING 1). run.sh resets this to "pass"
# before each test; fail()/assert_*() set it to "fail"; run.sh reads it after each
# test to decide PASS/FAIL. Never exits on failure (accumulate — mirrors fail_helper).
TEST_STATUS=""

# fail msg — resurrect fail_helper: record a failure (stderr) + set TEST_STATUS=fail.
# Does NOT exit/abort — run.sh aggregates at the end. (Mirrors resurrect's fail_helper;
# the CONTRACT for test bodies is: signal failure ONLY via fail/assert_*.)
fail() {
	local msg="$1"
	echo "  ASSERT FAIL: $msg" >&2
	TEST_STATUS="fail"
}

# pass msg — optional explicit pass narration (verbose). Does NOT touch TEST_STATUS
# (only fail does). Use for human-readable progress inside a test body.
pass() {
	local msg="$1"
	echo "  ok: $msg"
}

# assert_eq a b msg — POSIX equality (no subprocess). Quiet on success; on mismatch
# calls fail (sets TEST_STATUS=fail) with a diff-style diagnostic.
assert_eq() {
	local a="$1" b="$2" msg="$3"
	if [ "$a" = "$b" ]; then
		:
	else
		fail "$msg (got [$a] want [$b])"
	fi
}

# assert_contains str sub msg — literal substring. Uses `case` with "$sub" QUOTED
# in the pattern so glob specials (?,*,[) are disabled for the quoted segment =>
# literal match, no subprocess, robust vs special chars (FINDING 3). Quiet on
# success; on absence calls fail with a diagnostic.
assert_contains() {
	local str="$1" sub="$2" msg="$3"
	case "$str" in
		*"$sub"*)
			:
			;;
		*)
			fail "$msg (substring [$sub] absent in [$str])"
			;;
	esac
}

# setup_test [socket_name] — bring up a FRESH isolated tmux server + baseline
# fixtures for ONE test. THIN delegate to setup_socket (P1.M7.T1.S1 — FINDING 2):
# the temp dir + PATH shim + exports + server start + baseline fixture seeding
# (driver/alpha/beta + multi-pane windows) ALL happen inside setup_socket. Does
# NOT attach a client (tests needing switch-client/display-message-p/refresh-client-S
# call attach_test_client themselves). run.sh calls this once PER test with a
# unique socket name (FINDING 5) so each test is hermetic.
setup_test() {
	setup_socket "${1:-}"
	# PRD §18: the shipped default is @livepicker-preview-defer=on (background
	# run-shell -b preview). That makes the existing functional/restore/etc. tests'
	# SYNCHRONOUS @livepicker-linked-id assertions race the async job (they assert
	# immediately after input-handler.sh type/next/backspace). Pin OFF here so the
	# whole suite stays deterministic on the synchronous path it was written for;
	# the deferred path is validated by tests/test_responsiveness.sh (P1.M3.T1.S1),
	# which sets @livepicker-preview-defer back to ON. (Per-test: each test gets a
	# fresh server; clear_all_state preserves §11 config so the pin holds for the
	# picker lifetime within a test.)
	tmux set-option -g @livepicker-preview-defer off 2>/dev/null || true
}

# teardown_test — kill the isolated server + clean tmp for the test just run. THIN
# delegate to teardown_socket (idempotent: detaches any client, kill-server, rm -rf
# the shim dir, rm -f the orphaned socket file — all inside teardown_socket).
teardown_test() {
	teardown_socket
}
