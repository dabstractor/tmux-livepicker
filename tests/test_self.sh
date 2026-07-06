#!/usr/bin/env bash
# tests/test_self.sh — P1.M7.T2.S1 §5 MOCKING self-test.
#
# SOURCED by run.sh (defines test_* only; NO side effects on source; no file-scope
# execution). Proves the runner reports a PASS (test_true) and a FAIL (test_false)
# and the exit code reflects it (work-item §5). test_false is GATED so the default
# suite stays green; enable the negative path to exercise the failure reporting:
#   bash tests/run.sh                                  # test_true PASS, test_false PASS, exit 0
#   LIVEPICKER_NEGATIVE_SELF_TEST=1 bash tests/run.sh  # test_true PASS, test_false FAIL, exit 1
#
# set -u is inherited from helpers.sh (sourced by run.sh before this file).
# shellcheck disable=SC2154

# test_true — a trivially-passing test (proves the PASS path).
test_true() {
	assert_eq "1" "1" "sanity equality holds"
	assert_contains "hello world" "world" "substring found"
}

# test_false — an intentionally-failing test (proves the FAIL path + exit code).
# Gated: only fails under LIVEPICKER_NEGATIVE_SELF_TEST=1, so `bash tests/run.sh`
# is green by default and the negative path is opt-in (keeps test_self.sh shippable).
test_false() {
	if [ "${LIVEPICKER_NEGATIVE_SELF_TEST:-0}" = "1" ]; then
		assert_eq "1" "2" "intentional self-test failure (expected)"
	else
		assert_eq "1" "1" "negative path disabled (set LIVEPICKER_NEGATIVE_SELF_TEST=1 to exercise)"
	fi
}
