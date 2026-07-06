#!/usr/bin/env bash
# tests/test_pollution.sh — tmux-livepicker PRD §15.18 Pollution (the core invariant)
# validation (P1.M7.T5.S1).
#
# SOURCED by run.sh (NEVER executed directly). Defines three test_* functions that drive the
# COMPLETE real plugin (scripts/livepicker.sh -> input-handler.sh -> preview.sh -> restore.sh,
# all COMPLETE P1.M1-M6) DIRECTLY (contract §1: the scripts; NOT via keypress) against the
# socket-isolated server the harness provides (tests/setup_socket.sh P1.M7.T1.S1 +
# tests/helpers.sh P1.M7.T2.S1), and assert the core invariant (PRD §4/§14): browsing must not
# pollute session-history, and the only navigation is the one confirm-time switch. Each test
# installs a stand-in tmux-session-history recorder (the real plugin is NOT loaded on the
# isolated socket), exercises one §15.18 bullet, and signals pass/fail via fail/assert_* (which
# set TEST_STATUS; run.sh reads it in the current shell).
#
# CONTRACT: run.sh sources setup_socket.sh + helpers.sh + every tests/test_*.sh, then PER test
# calls setup_test "lp-$$-<name>" (-> fresh isolated socket + PATH shim + baseline fixtures
# driver/alpha/beta) -> resets TEST_STATUS=pass -> runs the test_* in the CURRENT shell -> reads
# TEST_STATUS -> teardown_test. So when a test_* runs: bare `tmux` hits the isolated socket;
# $LIVEPICKER_SCRIPTS, $TEST_DRIVER_SESSION, $TMUX_SOCK_DIR, attach_test_client,
# fail/pass/assert_eq/assert_contains are all IN SCOPE; this file SOURCES NOTHING and calls NO
# setup_test/teardown_test.
#
# CRITICAL (research FINDING 3): `display-message -p '#{session_name}'` returns the LAST-CREATED/
# switched session, NOT necessarily the client's. So create ALL fixtures BEFORE attach_test_client
# (the attach resets the pointer to `driver`); the recorder force-switches to `driver` too.
#
# CRITICAL (research FINDING 7): the driven scripts (livepicker/confirm/cancel) REQUIRE an
# attached client. So every test_* calls attach_test_client FIRST (mirrors T3.S1; UNLIKE T4.S1).
#
# CRITICAL (research FINDING 5): the recorder bakes the ABSOLUTE shim path ($TMUX_SOCK_DIR/tmux)
# so run-shell hits the isolated socket, never /usr/bin/tmux.
#
# `set -u` is INHERITED from helpers.sh (do NOT re-declare; mirror test_self.sh).
# shellcheck disable=SC2154,SC2016,SC2034,SC2086
#   SC2154: assert_*/attach_test_client/$LIVEPICKER_SCRIPTS/$TEST_DRIVER_SESSION/$TMUX_SOCK_DIR
#           are defined by run.sh's sources, not in this file.

# lp_install_history_recorder — install a stand-in tmux-session-history engine on the isolated
# socket. The real plugin is NOT loaded there (contract §1 RESEARCH NOTE), so this recorder
# faithfully mirrors its do_hook (same-session short-circuit + forward-collapse) + do_toggle,
# read in full from the real scripts/session_history.sh (research FINDING 1). State lives in
# @test-* (== @session-history-*). The recorder file is written into $TMUX_SOCK_DIR (auto-cleaned
# by teardown_socket — FINDING 6) via an UNQUOTED heredoc so `T="$TMUX_SOCK_DIR/tmux"` bakes the
# ABSOLUTE shim path at write time (FINDING 5). The recorder is written WITHOUT set -u + with
# explicit defaults (the recorder exception — FINDING 10: a crash mid-hook leaves @test-*
# inconsistent). set-hook uses NO -b (FINDING 4: synchronous -> the test's next read sees the
# update). The trailing switch-client forces the display-message pointer to `driver` (FINDING 3
# belt-and-braces); the client is already on `driver` post-attach -> same-session -> deduped.
lp_install_history_recorder() {
	local rec="$TMUX_SOCK_DIR/session_history_rec.sh"
	# UNQUOTED heredoc: $TMUX_SOCK_DIR expands at WRITE time (bakes the absolute shim path);
	# \$1 / \$T / \$cur etc. stay literal (runtime). NO set -u in the recorder (FINDING 10).
	cat > "$rec" <<EOF
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
# SAME-SESSION short-circuit (the dedup that makes cancel -> 0 entries).
[ "\$to" = "\$cur" ] && exit 0
# NAVIGATION: keep backward hist[0..idx] MINUS 'to', append 'to', idx=len-1 (forward collapses).
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
	chmod +x "$rec"
	# Synchronous hook (NO -b — FINDING 4). #{session_name} is tmux format, not shell.
	tmux set-hook -g client-session-changed "run-shell '$rec #{session_name}'"
	# Seed the timeline so the first real switch is a NAVIGATION (not a first-fire init).
	tmux set-option -g @test-hist     "$TEST_DRIVER_SESSION"
	tmux set-option -g @test-current  "$TEST_DRIVER_SESSION"
	tmux set-option -g @test-prev     "$TEST_DRIVER_SESSION"
	tmux set-option -g @test-idx      0
	# Force the display-message pointer to `driver` (FINDING 3). Same-session -> deduped -> 0 entries.
	tmux switch-client -t "=$TEST_DRIVER_SESSION"
}

# lp_poll_make_fixtures — create 5 detached sessions so the picker has 8 total (driver/alpha/
# beta + nav1..nav5). MUST be called BEFORE attach_test_client (FINDING 3). 8 sessions => 5
# next-session steps from `driver` never wrap back to `driver` (so confirm lands on a real
# target != original — gotcha: fixture count).
lp_poll_make_fixtures() {
	local n
	for n in nav1 nav2 nav3 nav4 nav5; do
		tmux new-session -d -s "$n" -x 120 -y 40
	done
}

# lp_poll_resolve_target — predict the session confirm will land on, from the picker's OWN state.
# With an EMPTY filter (this suite never types), filtered == the full @livepicker-list (filter.sh),
# so target == items[@livepicker-index] — byte-identical to what input-handler.sh confirm resolves.
# NEVER hardcode a name (list-sessions order is server order, not sorted).
lp_poll_resolve_target() {
	local list idx
	local -a items=()
	list="$(tmux show-option -gqv @livepicker-list)"
	idx="$(tmux show-option -gqv @livepicker-index)"
	[[ "$idx" =~ ^[0-9]+$ ]] || idx=0
	mapfile -t items < <(printf '%s' "$list")
	if [ "$idx" -lt "${#items[@]}" ]; then
		printf '%s' "${items[$idx]}"
	else
		printf '%s' ""
	fi
}

# PRD §15.18 bullet 1: browse 5 sessions then cancel -> @test-hist UNCHANGED + client on origin.
test_browse_cancel_no_pollution() {
	# Fixtures BEFORE attach (FINDING 3): attach resets the display-message pointer to `driver`.
	lp_poll_make_fixtures
	attach_test_client
	lp_install_history_recorder

	local snap i
	snap="$(tmux show-option -gqv @test-hist)"   # "driver" (seeded)

	"$LIVEPICKER_SCRIPTS/livepicker.sh"           # activate (self-session preview; NO switch)

	# Invariant A: 5 navigations fire ZERO client-session-changed (link+select only).
	for i in 1 2 3 4 5; do
		"$LIVEPICKER_SCRIPTS/input-handler.sh" next-session
	done
	assert_eq "$(tmux show-option -gqv @test-hist)" "$snap" \
		"browse added no history entries (navigation never fires client-session-changed)"

	# PRD §15.18 b1: cancel -> restore.sh cancel -> switch-client -t "=driver" (SAME-session,
	# the client never left driver) -> the recorder dedups it -> 0 entries.
	"$LIVEPICKER_SCRIPTS/input-handler.sh" cancel   # empty filter -> full restore cancel
	assert_eq "$(tmux show-option -gqv @test-hist)" "$snap" \
		"cancel added no history (same-session switch deduped)"
	assert_eq "$(tmux display-message -p '#{session_name}')" "$TEST_DRIVER_SESSION" \
		"client returned to the original session"
}

# PRD §15.18 bullet 2: browse 5, confirm on the target -> EXACTLY ONE new entry (the target),
# no intermediates (forward history collapsed).
test_browse_confirm_one_entry() {
	lp_poll_make_fixtures
	attach_test_client
	lp_install_history_recorder

	local snap i target want
	snap="$(tmux show-option -gqv @test-hist)"   # "driver"

	"$LIVEPICKER_SCRIPTS/livepicker.sh"
	for i in 1 2 3 4 5; do
		"$LIVEPICKER_SCRIPTS/input-handler.sh" next-session
	done

	# Resolve the highlighted target DYNAMICALLY (empty filter -> full list; mirror confirm).
	target="$(lp_poll_resolve_target)"
	[ "$target" != "$TEST_DRIVER_SESSION" ] \
		|| fail "navigation did not move the highlight off the original session"

	"$LIVEPICKER_SCRIPTS/input-handler.sh" confirm   # the ONE switch (driver -> target)

	# PRD §15.18 b2: exactly ONE new entry appended (the target); the 4 intermediates were
	# NEVER recorded (Invariant A). The recorder's navigation: keep [driver] minus target,
	# append target -> "driver\ntarget". A real newline in the expected value (POSIX = compares
	# the whole multi-line string).
	want="$snap"$'\n'"$target"
	assert_eq "$(tmux show-option -gqv @test-hist)" "$want" \
		"confirm appended exactly one entry (the target); no intermediates (forward history collapsed)"
	assert_eq "$(tmux display-message -p '#{session_name}')" "$target" \
		"confirm landed the client on the target"
}

# PRD §15.18 bullet 3: after a confirmed pick, the toggle returns to the pre-pick session.
test_toggle_after_confirm() {
	lp_poll_make_fixtures
	attach_test_client
	lp_install_history_recorder

	local i target prev

	"$LIVEPICKER_SCRIPTS/livepicker.sh"
	for i in 1 2 3 4 5; do
		"$LIVEPICKER_SCRIPTS/input-handler.sh" next-session
	done
	target="$(lp_poll_resolve_target)"
	"$LIVEPICKER_SCRIPTS/input-handler.sh" confirm   # driver -> target (the ONE switch)

	# After the pick, @test-prev == the pre-pick session (driver) — the recorder set prev=from.
	# Read it BEFORE the toggle (the toggle itself is a navigation that flips @test-prev).
	prev="$(tmux show-option -gqv @test-prev)"
	assert_eq "$prev" "$TEST_DRIVER_SESSION" \
		"@test-prev points at the pre-pick session (driver)"

	# PRD §15.18 b3 / §14: simulate the session-history toggle (do_toggle: switch-client -t
	# "$PREV"). Because only ONE switch occurred, it returns to the pre-pick session.
	tmux switch-client -t "=$prev"
	assert_eq "$(tmux display-message -p '#{session_name}')" "$TEST_DRIVER_SESSION" \
		"toggle returned to the pre-pick session (driver)"
}
