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
# pins the colors/type; each window-status test sets the separator. So
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
# no count suffix is ever emitted (PRD §19) -> exact-output assert_eq is safe. The caller
# sets @livepicker-tab-style + the cache templates + window-status-separator itself.
lp_appearance_seed() {
	tmux set-option -g @livepicker-type session
	tmux set-option -g @livepicker-fg             "default"
	tmux set-option -g @livepicker-bg             "default"
	tmux set-option -g @livepicker-highlight-fg   "black"
	tmux set-option -g @livepicker-highlight-bg   "yellow"
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
# assertion (no count suffix per PRD §19); the highlight is index 1 (beta, current).
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
