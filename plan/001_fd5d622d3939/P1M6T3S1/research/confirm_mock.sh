#!/usr/bin/env bash
# research/confirm_mock.sh — THROWAWAY socket-isolated validator for the
# input-handler.sh `confirm` branch (P1.M6.T3.S1). NOT shipped — P1.M7 owns the
# real harness. Self-cleaning. Run from anywhere:
#   bash plan/001_fd5d622d3939/P1M6T3S1/research/confirm_mock.sh
#
# Drives the REAL scripts/livepicker.sh (activate), scripts/preview.sh (to build
# a preview link), scripts/input-handler.sh (confirm), and scripts/restore.sh
# (keep/cancel) against an isolated tmux socket with ONE attached client.
# Asserts the work-item §5 clusters (a)-(e) + the FINDING 1/2 regression check
# (driver cleaned of the preview window after a session-mode confirm — the
# catastrophic switch-before-unlink bug) + a smart-dedup client-session-changed
# recorder (FINDING 7) for the PRD §14 "exactly one switch" pollution invariant.
set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../../../.." && pwd)"
SCRIPTS="$ROOT/scripts"
SOCK="lp-t3mock-$$"
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

# --- fresh isolated server + an ATTACHED client (switch-client / display-message
#     both REQUIRE a client; refresh-client -S too). `script -qec` gives a pty. ---
tmux -L "$SOCK" new-session -d -s driver -x 120 -y 40
script -qec "tmux -L $SOCK attach -t driver" /dev/null >/dev/null 2>&1 &
sleep 0.6

# --- smart-dedup client-session-changed recorder (research FINDING 7) ----------
# Records #{session_name} ONLY when it differs from the last-seen name, so a
# same-session switch (restore cancel -> driver when already on driver) is NOT
# counted — matching how the real tmux-session-history engine dedups.
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
nsessions(){ T list-sessions -F '#{session_name}' 2>/dev/null | wc -l | tr -d ' '; }
has(){ T has-session -t "=$1" 2>/dev/null; }

# Full activate from a known clean state. $1=type $2=create $3+=extra sessions.
activate_fresh(){
	local type="$1" create="$2"; shift 2
	"$SCRIPTS/restore.sh" cancel >/dev/null 2>&1 || true
	T kill-server 2>/dev/null || true
	sleep 0.2
	tmux -L "$SOCK" new-session -d -s driver -x 120 -y 40
	script -qec "tmux -L $SOCK attach -t driver" /dev/null >/dev/null 2>&1 &
	sleep 0.5
	for s in "$@"; do T new-session -d -s "$s" -x 120 -y 40; done
	T set-option -g "@livepicker-key" "L"
	T set-option -g "@livepicker-type" "$type"
	T set-option -g "@livepicker-create" "$create"
	T set-hook -g client-session-changed "run-shell '$REC_DIR/rec.sh #{session_name}'" # kill-server wiped it
	"$SCRIPTS/livepicker.sh" >/dev/null 2>&1
	reset_history
}

echo "== confirm mock (socket $SOCK) =="

# Cluster (a): match lands on target + driver cleaned + exactly 1 history entry
echo "cluster (a) session match"
activate_fresh session on alpha beta gamma
T set-option -g "@livepicker-list" "beta"
T set-option -g "@livepicker-filter" ""
T set-option -g "@livepicker-index" "0"
"$SCRIPTS/preview.sh" beta >/dev/null 2>&1
linked_before="$(T show-option -gqv "@livepicker-linked-id" 2>/dev/null)"
assert '[ -n "$linked_before" ]' "preview linked beta's window (linked_id set)"
"$SCRIPTS/input-handler.sh" confirm >/dev/null 2>&1
assert '[ "$(cur_session)" = "beta" ]' "client landed on beta"
assert '[ "$(hcount)" = "2" ]' "exactly 1 new history entry (seed+beta)"
# THE FINDING 1/2 regression check: driver must NOT still hold the preview window
driver_kept="$(T list-windows -t driver -F '#{window_id}' 2>/dev/null | grep -c "^${linked_before}\$")"
assert '[ "$driver_kept" = "0" ]' "driver cleaned of preview (no FINDING 1/2 target-destruction)"
assert '[ "$(T list-windows -t beta -F '#{window_id}' 2>/dev/null | wc -l)" -ge 1 ]' "target beta still has a window (intact)"

# Cluster (b): empty + session + create on + VALID name -> created + active
echo "cluster (b) create-on valid"
activate_fresh session on alpha
before_n="$(nsessions)"
T set-option -g "@livepicker-list" "alpha"
T set-option -g "@livepicker-filter" "zzz"   # matches nothing -> empty filtered list
T set-option -g "@livepicker-index" "0"
reset_history
"$SCRIPTS/input-handler.sh" confirm >/dev/null 2>&1
assert 'has clean123' "new session 'clean123' was created (has-session)"
assert '[ "$(nsessions)" = "$((before_n + 1))" ]' "session count +1"
assert '[ "$(cur_session)" = "clean123" ]' "client active on the new session"
assert '[ "$(hcount)" = "2" ]' "exactly 1 new history entry"

# Cluster (c): empty + create OFF -> nothing created, cancel, client on driver
echo "cluster (c) create-off"
activate_fresh session off alpha
before_n="$(nsessions)"
T set-option -g "@livepicker-list" "alpha"
T set-option -g "@livepicker-filter" "zzz"
T set-option -g "@livepicker-index" "0"
reset_history
"$SCRIPTS/input-handler.sh" confirm >/dev/null 2>&1
assert '[ "$(nsessions)" = "$before_n" ]' "NO new session created (create off)"
assert '! has zzz' "no stray session named after the query"
assert '[ "$(cur_session)" = "driver" ]' "client back on driver (cancel)"
assert '[ "$(hcount)" = "1" ]' "0 new history entries (dedup)"

# Cluster (d): window mode -> ZERO new-session; select-window; no creation
echo "cluster (d) window mode"
activate_fresh window on wina winb
before_n="$(nsessions)"
# window-mode target tokens are "session:window_index" (livepicker.sh FINDING 6)
T set-option -g "@livepicker-list" "wina:0"
T set-option -g "@livepicker-filter" ""
T set-option -g "@livepicker-index" "0"
reset_history
"$SCRIPTS/input-handler.sh" confirm >/dev/null 2>&1
assert '[ "$(nsessions)" = "$before_n" ]' "NO new session created in window mode"
assert '[ "$(cur_session)" = "driver" ]' "window mode does not switch-client"

# Cluster (e): sanitized/invalid name (query "proj:two") -> cancel
echo "cluster (e) invalid/sanitized name"
activate_fresh session on alpha
before_n="$(nsessions)"
T set-option -g "@livepicker-list" "alpha"
T set-option -g "@livepicker-filter" "proj:two"   # new-session sanitizes ':'->'_'
T set-option -g "@livepicker-index" "0"
reset_history
"$SCRIPTS/input-handler.sh" confirm >/dev/null 2>&1
assert '! has proj:two' "no session with the LITERAL sanitized query name (gate caught it)"
assert '[ "$(cur_session)" = "driver" ]' "client stays on driver (cancel)"
assert '[ "$(nsessions)" = "$before_n" ]' "no stray session left behind"

echo "=================================================="
[ "$fail" = "0" ] && { echo "ALL CLUSTERS PASSED"; exit 0; } || { echo "SOME CLUSTERS FAILED"; exit 1; }
