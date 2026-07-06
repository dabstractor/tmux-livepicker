#!/usr/bin/env bash
# research/cancel_mock.sh — THROWAWAY socket-isolated validator for the
# input-handler.sh `cancel` branch (P1.M6.T4.S1). NOT shipped — P1.M7 owns the
# real harness. Self-cleaning. Run from anywhere:
#   bash plan/001_fd5d622d3939/P1M6T4S1/research/cancel_mock.sh
#
# Drives the REAL scripts/livepicker.sh (activate), scripts/preview.sh (to build
# a preview link), scripts/input-handler.sh (cancel), and scripts/restore.sh
# (cancel) against an isolated tmux socket with ONE attached client. Asserts the
# work-item §5 two-step semantics + the PRD §14 "cancel -> 0 history entries"
# pollution invariant (via a smart-dedup client-session-changed recorder —
# cancel_findings FINDING 4 / restore_keep_cancel FINDING B).
set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../../../.." && pwd)"
SCRIPTS="$ROOT/scripts"
SOCK="lp-t4mock-$$"
T(){ tmux -L "$SOCK" "$@"; }
fail=0
n=0
ok(){ echo "  ok   [$n] $1"; }
bad(){ echo "  FAIL [$n] $1"; fail=1; }
assert(){ n=$((n+1)); if eval "${1:?}"; then ok "$2"; else bad "$2 [$1]"; fi; }

REC_DIR=""; REC_LOG=""
cleanup(){
	jobs -p 2>/dev/null | xargs -r kill 2>/dev/null || true
	tmux -L "$SOCK" kill-server 2>/dev/null || true
	[ -n "$REC_DIR" ] && rm -rf "$REC_DIR" 2>/dev/null || true
	[ -n "$REC_LOG" ] && rm -f "$REC_LOG" 2>/dev/null || true
}
trap cleanup EXIT INT TERM

# Fresh isolated server + an ATTACHED client (switch-client / display-message /
# refresh-client all REQUIRE a client). `script -qec` gives a pty.
tmux -L "$SOCK" new-session -d -s driver -x 120 -y 40
script -qec "tmux -L $SOCK attach -t driver" /dev/null >/dev/null 2>&1 &
sleep 0.6

# smart-dedup client-session-changed recorder (cancel_findings FINDING 4). Records
# #{session_name} ONLY when it differs from the last-seen name, so a same-session
# switch (cancel's restore STEP-3 -> driver when already on driver) is NOT counted
# — matching how the real tmux-session-history engine dedups (do_hook's
# [ "$to" = "$CURRENT" ] && return).
REC_DIR="$(mktemp -d)"
REC_LOG="$(mktemp)"
cat > "$REC_DIR/rec.sh" <<EOF
#!/usr/bin/env bash
new="\$1"
last="\$(tail -1 '$REC_LOG' 2>/dev/null || true)"
[ -n "\$new" ] && [ "\$new" != "\$last" ] && printf '%s\\n' "\$new" >> '$REC_LOG'
EOF
chmod +x "$REC_DIR/rec.sh"
T set-hook -g client-session-changed "run-shell '$REC_DIR/rec.sh #{session_name}'"
echo driver > "$REC_LOG"   # seed baseline = the client's current session
hcount(){ wc -l < "$REC_LOG" 2>/dev/null | tr -d ' '; }
reset_history(){ cur="$(T display-message -p '#{session_name}' 2>/dev/null || echo driver)"; : > "$REC_LOG"; echo "$cur" > "$REC_LOG"; }

cur_session(){ T display-message -p '#{session_name}' 2>/dev/null; }
getoptv(){ T show-option -gqv "$1" 2>/dev/null; }
isset(){ T show-options -g "$1" >/dev/null 2>&1; }   # @-options: rc=0 set, rc=1 unset

# Full activate from a known clean state, then seed a NON-empty filter + a preview.
activate_fresh(){
	local type="$1"; shift
	"$SCRIPTS/restore.sh" cancel >/dev/null 2>&1 || true
	T kill-server 2>/dev/null || true
	sleep 0.2
	tmux -L "$SOCK" new-session -d -s driver -x 120 -y 40
	script -qec "tmux -L $SOCK attach -t driver" /dev/null >/dev/null 2>&1 &
	sleep 0.5
	for s in "$@"; do T new-session -d -s "$s" -x 120 -y 40; done
	T set-option -g "@livepicker-key" "L"
	T set-option -g "@livepicker-type" "$type"
	T set-option -g "@livepicker-create" "on"
	T set-hook -g client-session-changed "run-shell '$REC_DIR/rec.sh #{session_name}'" # kill-server wiped it
	"$SCRIPTS/livepicker.sh" >/dev/null 2>&1
	reset_history
}

echo "== cancel mock (socket $SOCK) =="

# Cluster 1: cancel with a NON-empty filter clears the query; picker STAYS open.
echo "cluster (1) cancel clears filter, picker open"
activate_fresh session alpha beta gamma
# Seed a query + an off-zero index + a live preview of beta (so we also prove the
# preview link is NOT torn down by the clear-filter step — only restore cancel does).
T set-option -g "@livepicker-filter" "be"
T set-option -g "@livepicker-index" "1"
"$SCRIPTS/preview.sh" beta >/dev/null 2>&1
linked_before="$(getoptv "@livepicker-linked-id")"
assert '[ -n "$linked_before" ]' "preview linked beta's window (linked_id set)"
assert '[ "$(getoptv "@livepicker-filter")" = "be" ]' "filter seeded non-empty"
reset_history
"$SCRIPTS/input-handler.sh" cancel >/dev/null 2>&1
assert '[ -z "$(getoptv "@livepicker-filter")" ]' "filter CLEARED to '' (FINDING 1)"
assert '[ "$(getoptv "@livepicker-index")" = "0" ]' "index reset to 0"
assert '[ "$(getoptv "@livepicker-mode")" = "on" ]' "picker STAYS OPEN (@livepicker-mode on)"
assert 'isset "@livepicker-list"' "list still populated (picker not torn down)"
assert '[ "$(getoptv key-table)" = "livepicker" ]' "key-table still livepicker (modal keys still captured)"
assert '[ "$(getoptv status)" = "2" ]' "status still grown (renderer line still installed)"
assert '[ "$(getoptv "@livepicker-linked-id")" = "$linked_before" ]' "preview link NOT touched (restore owns cleanup)"
assert '[ "$(cur_session)" = "driver" ]' "client never moved"
assert '[ "$(hcount)" = "1" ]' "ZERO history entries (no switch happened)"

# Cluster 2: cancel AGAIN (filter now empty) fully cancels; history unchanged.
echo "cluster (2) cancel again exits picker, client on original session, 0 entries"
reset_history
"$SCRIPTS/input-handler.sh" cancel >/dev/null 2>&1
assert '! isset "@livepicker-mode"' "picker GONE (@livepicker-mode cleared by restore STEP-6)"
assert '! isset "@livepicker-filter"' "filter runtime key cleared"
assert '! isset "@livepicker-list"' "list runtime key cleared"
assert '! isset "@livepicker-index"' "index runtime key cleared"
assert '! isset "@livepicker-linked-id"' "linked-id runtime key cleared"
assert '[ "$(getoptv key-table)" = "root" ]' "key-table restored to root"
assert '[ "$(cur_session)" = "driver" ]' "client back on original session (driver)"
assert '[ "$(hcount)" = "1" ]' "ZERO net history entries (restore STEP-3 dedup, FINDING 4)"
# The livepicker key table is unbound (restore STEP-6b unbind-key -a -T livepicker).
! T list-keys -T livepicker >/dev/null 2>&1 && rc_empty=1 || rc_empty=0
# list-keys rc is unreliable across versions; assert the table has no cancel bind:
n_lk="$(T list-keys -T livepicker 2>/dev/null | grep -c 'input-handler.sh cancel' || true)"
assert '[ "$n_lk" = "0" ]' "livepicker table has no cancel binding (unbound)"

echo "=================================================="
[ "$fail" = "0" ] && { echo "ALL CLUSTERS PASSED"; exit 0; } || { echo "SOME CLUSTERS FAILED"; exit 1; }
