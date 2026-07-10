# PRP — P1.M1.T2.S1: Implement lp_discover_axis_keys discovery algorithm in utils.sh

---

## Goal

**Feature Goal**: A new function `lp_discover_axis_keys AXIS DIR` in `scripts/utils.sh`
that discovers the user's two-axis navigation keys from their live `tmux list-keys -T
root` + `-T prefix` tables (PRD §8 h3.18): which keys they already have bound for
window-flip (next/prev) and session-nav (next/prev), with mouse false-positives
excluded, plain alphanumerics dropped (reserved for typing), control-key collisions
subtracted, and the universal arrow extras appended for the session axis. Prints a
space-separated key list on stdout.

**Deliverable**: One new function appended to `scripts/utils.sh` (after `tmux_clear_hook`,
the last function). **No new files.** Not yet wired into activate (that is P1.M2.T1.S1);
this subtask ships the helper only.

**Success Definition**:
- Against the live user key tables, the function prints the correct key SET for all 4
  axes: window/next `{C-M-Tab, M-n, C-n, C-l}`, window/prev `{C-M-BTab, M-p, C-p, C-h}`,
  session/next `{), Down}`, session/prev `{(, Up}`. (Order within each list follows
  list-keys output and is functionally irrelevant — distinct keys bind to the same action.)
- Mouse bindings (`WheelDownStatus → next-window`, `MouseDown3StatusLeft → display-menu
  { switch-client -n }`) are EXCLUDED (never appear in the output).
- Plain alphanumerics (`n`, `p`, `0`-`9`) are dropped; `)` and `(` are kept; `-r`-flagged
  bindings (`C-h`, `C-l`) are parsed correctly.
- `bash -n` + `shellcheck` clean; sourcing utils.sh has no side effects; the helper
  requires only that `get_opt` (options.sh) be defined at call time (activate guarantees it).

## User Persona (if applicable)

**Target User**: The activate binding code (livepicker.sh T4, reworked in P1.M2.T1.S1).
Not end-user facing. Mode A — internal helper, no docs.

**Use Case**: At activate, for each axis, if the user has NOT set the corresponding
`@livepicker-*-keys` option (empty default ⇒ discover, per T1.S1), activate calls
`lp_discover_axis_keys window next` etc. and binds each returned key to the matching
picker action. This reuses the user's muscle-memory nav keys instead of imposing defaults.

**Pain Points Addressed**: PRD §8 — the picker must navigate on TWO axes (session + window)
using the keys the user ALREADY has bound for each, discovered automatically. Hardcoded
defaults fight muscle memory (the old single-axis model, dropped). This function is the
discovery engine.

---

## Why

- **Unblocks the two-axis binding rework (P1.M2.T1.S1).** The activate T4 rework calls
  this function to resolve each axis's keys when the user hasn't set an explicit override.
  Without it, the empty-default accessors (T1.S1) have no resolution path.
- **Muscle-memory reuse (PRD §8).** The user's `Ctrl-M-Tab`/`M-n`/`C-n` flip windows;
  `)`/`(`/arrows move sessions — discovery finds THESE, not imposed defaults.
- **Correctness-critical parsing.** The live key tables contain mouse false-positives
  (`WheelDownStatus → next-window` is a top-level command that substring-match would
  catch) and the `-r` flag + alignment-space variations that break naïve field parsing.
  This function encodes the verified parse + exclusions.
- **Leak-safe / side-effect-free.** A sourced-lib function that only READS `list-keys`
  and prints; it mutates no tmux state. Matches the existing `lp_*` helpers in utils.sh.

## What

A function `lp_discover_axis_keys` appended to `scripts/utils.sh`:
- **Args:** `$1 = axis` (`window` | `session`), `$2 = dir` (`next` | `prev`).
- **Reads** `tmux list-keys -T root` + `-T prefix` (combined stream).
- **Parses** each line: tokenize → skip to `-T` → skip the table → next token is the key →
  rest is the command. Excludes `Mouse*`/`Wheel*` keys.
- **Classifies** by axis+dir: window = substring match on the command; session = EXACT
  top-level match (`switch-client -n`/`-p` or starts-with, NOT `-l`/`-t`, NOT substrings
  inside `display-menu`).
- **Drops** single-char alphanumerics (`[A-Za-z0-9]`).
- **Excludes** the control-key set (confirm/cancel/backspace/rename/delete) read via `get_opt`.
- **De-duplicates** (first-seen).
- **Appends** `Down` (session/next) / `Up` (session/prev) as universal extras.
- **Prints** the space-separated result on stdout.

### Success Criteria

- [ ] `lp_discover_axis_keys` defined in utils.sh (after `tmux_clear_hook`); takes axis/dir.
- [ ] All 4 axes print the correct SET against the live key tables (L2 smoke, order-independent).
- [ ] Mouse/Wheel keys never appear; `-r`-flagged bindings parsed; plain alphanumerics dropped.
- [ ] Session axis uses exact top-level match (Z→`-l`, C-Space→`-T`, display-menu all excluded).
- [ ] `bash -n` + `shellcheck` clean; sourcing utils.sh = no side effects.

## All Needed Context

### Context Completeness Check

_Pass_: The implementer needs (a) the verbatim function body (below), (b) the parsing
traps from the research file (`-r`/alignment; `set --` clobbers $1/$2 → save to locals
first; mouse exclusion; session exact-match vs window substring), and (c) the live
bindings the algorithm must handle. Every behavior is empirically proven by a prototype
run against the live server.

### Documentation & References

```yaml
# MUST READ — the empirical ground-truth (prototype verified against live tables)
- docfile: plan/004_2c5127285a90/P1M1T2S1/research/key_discovery_findings.md
  why: PROVES the algorithm. FINDING 1 (the live nav bindings — the exact input); FINDING 2
       (the parser: -r flag + alignment spaces; the set---clobbers-$1/$2 TRAP); FINDING 3
       (mouse exclusion — two complementary protections; session EXACT vs window SUBSTRING);
       FINDING 4 (alphanumeric drop + de-dup); FINDING 5 (order is irrelevant — assert the SET).
  critical: Read BEFORE writing. The mouse false-positives and the -r flag are the two traps
            that produce silently-wrong output.

# MUST READ — the file being modified (append after the last function)
- file: scripts/utils.sh
  why: Sourced lib (NO source-time side effects; set -u; # shellcheck disable=SC1091).
        Existing lp_* helpers (lp_filter_harmful_bindings ~line 102, lp_resolve_client ~157,
        lp_client_format ~172) set the style; tmux_clear_hook (~185) is the LAST function —
        append after it. get_opt is NOT defined here (options.sh owns it) — see the call-time note.
  pattern: lp_* helpers read tmux state and print; local everywhere; quote expansions; no set -e.
  gotcha: lp_filter_harmful_bindings DROPS nav keys from the copied key table — discovery reads
          RAW list-keys BEFORE that filter (they are complementary; research FINDING in gap_analysis).

# MUST READ — the parsing spec + the mouse-exclusion requirement
- docfile: plan/004_2c5127285a90/architecture/external_deps.md
  why: §2 'Key Discovery' specifies the bind-key line format, the -r shift, the mouse-exclusion
        rule (match top-level command + exclude Mouse*/Wheel*), and the swap-window compound.
  section: "## 2. Key Discovery — list-keys Parsing"

# MUST READ — the discovery algorithm spec
- docfile: PRD.md
  why: §8 h3.18 (Discovery) — the window/session axis patterns, the alphanumeric drop, de-dup,
        control-key exclusion, the arrow extras, and the worked example (this user's output).
  section: "§8 The key subsystem" → "Discovery" (h3.18)

# MUST READ — the gap analysis (old model vs new; lp_filter_harmful_bindings complement)
- docfile: plan/004_2c5127285a90/architecture/gap_analysis_key_discovery.md
  why: Confirms the expected output SET + the mouse-exclusion criticality + that discovery reads
        RAW list-keys (before lp_filter_harmful_bindings, which is the copy-time filter).

# Reference — the sibling accessor task (LANDED; the empty-default probe this discovery resolves)
- docfile: plan/004_2c5127285a90/P1M1T1S1/PRP.md
  why: Defines opt_session/window_next/prev_keys () -> "" (empty = discover). Activate (M2.T1)
        calls THIS function when those accessors return empty. Confirms get_opt is the reader.
  section: "Goal" + "Integration Points"

# Reference — options.sh (get_opt + the control-key accessors the exclude set reads)
- file: scripts/options.sh
  why: get_opt (lines 15-19) is the low-level reader used for the exclude set; opt_confirm_keys
        (Enter), opt_cancel_keys (Escape), opt_backspace_keys (BSpace), opt_rename_key (C-r),
        opt_delete_key (M-BSpace) are the 5 control-key options to subtract.
```

### Current Codebase tree

```bash
tmux-livepicker/
  scripts/
    utils.sh      # MODIFY: append lp_discover_axis_keys after tmux_clear_hook (last function)
    options.sh    # (T1.S1, LANDED) opt_session/window_next/prev_keys "" + get_opt — consumed, not edited
    livepicker.sh # UNCHANGED here (T4 rework that CALLS this is P1.M2.T1.S1)
    ...
  tests/          # UNCHANGED (a discovery test may land with M2.T1's suite; validate via throwaway smoke)
```

### Desired Codebase tree with files to be added and responsibility of file

```bash
scripts/utils.sh   # +1 function lp_discover_axis_keys (two-axis key discovery from live list-keys)
```

### Known Gotchas of our codebase & Library Quirks

```bash
# CRITICAL (research FINDING 2) — `set -- $line` inside the function CLOBBERS the function's
# positional parameters ($1/$2 = axis/dir). SAVE axis/dir to LOCAL variables BEFORE the read-loop.
# Forgetting this makes $1/$2 become line tokens mid-loop and the axis:dir classify breaks.

# CRITICAL (research FINDING 2) — the `-r` flag is OPTIONAL and shifts the key/command position
# (bind-key -r -T prefix C-h select-window -p); AND prefix lines have alignment spaces
# (bind-key    -T prefix …). DO NOT parse by field index. Tokenize, skip every token until -T,
# drop -T + the table name, the NEXT token is the key, the rest is the command.

# CRITICAL (research FINDING 3) — mouse bindings are FALSE POSITIVES. WheelDownStatus -> next-window
# is a TOP-LEVEL command (substring match WOULD catch it); MouseDown3StatusLeft -> display-menu
# { switch-client -n } has switch-client -n INSIDE a block. TWO protections, BOTH required:
#   (1) exclude keys matching Mouse*|Wheel* (case "$key" in Mouse*|Wheel*) continue ;; esac);
#   (2) session axis uses EXACT top-level match (cmd == "switch-client -n" OR starts with
#       "switch-client -n "), NOT substring — so display-menu's inner switch-client -n never matches.

# CRITICAL — window axis uses SUBSTRING match on the command (so the swap-window \; select-window
# -t +1 compound matches via the "select-window -t +1" substring). Session axis uses EXACT match.
# Do NOT swap these: substring on session would catch display-menu inner commands; exact on window
# would miss the swap-window compound.

# CRITICAL — get_opt is NOT defined in utils.sh (options.sh owns it). It IS available at CALL TIME
# (activate sources options.sh before calling this). Use `get_opt "@livepicker-<name>" "<default>"`
# directly for the 5 control-key options. Do NOT source options.sh at utils.sh file scope (side
# effects + circular). The validation smoke sources options.sh alongside utils.sh (the real env).

# GOTCHA — drop EXACTLY single-char alphanumerics: `case "$key" in [A-Za-z0-9]) continue ;; esac`.
# This drops n, p, 0-9 (kept reserved for typing); KEEPS ) and ( (not in the class); multi-char
# keys (C-n, M-p, C-M-Tab) do not match the single-char glob. Verify ) and ( survive.

# GOTCHA — de-dup FIRST-SEEN: M-n appears in BOTH root (select-window -n) and prefix (next-window -a);
# it must appear ONCE. Use a `seen` accumulator: `case " $seen " in *" $key "*) continue ;; esac`.

# GOTCHA — the session axis ALWAYS appends the universal arrow extra: "Down" for next, "Up" for prev
# (PRD §8 h3.18). Append AFTER the list-keys scan (so it is always present even if discovery found
# nothing — arrows are the guaranteed fallback).

# GOTCHA — ORDER within the output is functionally irrelevant (distinct keys bind to the same
# action; tmux keeps the last binding per key but there are no duplicate keys). The contract's
# "expected" strings are a reference SET, not an order. The validation asserts the SET
# (order-independent). Do NOT add a sort (it would diverge from first-seen, which is the spec).

# GOTCHA — utils.sh runs under `set -u`. Guard every `$1`-style access with `${1:-}` (the set --
# loop and the arg reads). NO `set -e` (tmux list-keys / case matching are control flow). The
# function MUST tolerate an empty/unknown axis/dir (print nothing) rather than crash.

# GOTCHA — `set -- $line` word-splits on whitespace; the rejoined command (`$*`) collapses runs of
# spaces to single spaces. That is FINE for substring matching (the patterns use single spaces).
# Do NOT try to preserve exact command whitespace — unnecessary and the patterns don't need it.

# GOTCHA — do NOT wire this into livepicker.sh here (P1.M2.T1.S1 owns the T4 rework). Shipping the
# helper unreferenced is correct (it cannot regress the suite — nothing calls it yet). Validate via
# a throwaway smoke against an ISOLATED -L socket (or the live server read-only — list-keys mutates
# nothing).

# GOTCHA — Indent with TABS (utils.sh is tab-indented; shfmt is NOT installed).
```

## Implementation Blueprint

### Data models and structure

No data model — the function reads `list-keys`, classifies, and prints. The "model" is
the classify matrix:

```
axis:dir        match rule (on the command portion, after Mouse*/Wheel* key exclusion)
window:next     substring ∈ {select-window -n, select-window -t +1, select-window -t :+1, next-window}
window:prev     substring ∈ {select-window -p, select-window -t -1, select-window -t :-1, previous-window}
session:next    EXACT: cmd == "switch-client -n"  OR  cmd starts with "switch-client -n "
session:prev    EXACT: cmd == "switch-client -p"  OR  cmd starts with "switch-client -p "
```

### Implementation Tasks (ordered by dependencies)

```yaml
Task 1: MODIFY scripts/utils.sh — APPEND lp_discover_axis_keys
  - LOCATE: the end of tmux_clear_hook (the last function, ~line 185-187). Append the new
    function AFTER it (blank line separator). utils.sh is a sourced lib — NO driver line.
  - IMPLEMENT lp_discover_axis_keys AXIS DIR — paste the verbatim body from "Implementation
    Patterns" below (research FINDINGS 2/3/4 baked in).
  - NAMING: lp_discover_axis_keys (matches the lp_* helper convention: lp_filter_harmful_bindings,
    lp_resolve_client, lp_client_format).
  - DEPENDENCIES: tmux (bare — PATH shim in tests, real tmux in prod); get_opt (options.sh —
    available at call time; used for the control-key exclude set).
  - STYLE: tabs; local for ALL locals (axis/dir saved BEFORE the set-- loop); quote expansions;
    no set -e; prints the result via printf '%s'.
  - NO SIDE EFFECTS at source time (a function def); reads list-keys only when called.

Task 2: VALIDATE (throwaway smoke against an isolated -L socket — or the live server read-only)
  - RUN: bash -n scripts/utils.sh ; shellcheck scripts/utils.sh (expect 0 NEW findings)
  - RUN: the throwaway smoke (Validation L2) — sources utils.sh + options.sh; asserts all 4 axes
    produce the correct SET (order-independent) + mouse exclusion + alphanumeric drop. Then DELETE.
  - RUN: no-side-effects proof (L3): source utils.sh in a subshell, assert it defines the function
    and prints nothing.
  - (The full tests/run.sh suite is NOT a gate here — the helper is unreferenced until M2.T1.
     Note: the suite may currently be non-green due to the parallel T1.S1 intermediate; that is
     unrelated to this helper.)
```

### Implementation Patterns & Key Details

**The complete function** (paste verbatim at the end of utils.sh; the implementer may
adjust comment phrasing only):

```bash
# lp_discover_axis_keys AXIS DIR — PRD §8 h3.18 two-axis key discovery. Scans the user's
# live `tmux list-keys -T root` + `-T prefix` and prints the space-separated keys they
# already have bound for the requested axis+direction, so activate (P1.M2.T1.S1) can bind
# them in the livepicker table (muscle-memory reuse). Used when the @livepicker-*-keys
# option is unset (empty default => discover; the accessor is T1.S1).
#
#   AXIS = window | session ; DIR = next | prev
#
# PARSE (research key_discovery_findings.md FINDING 2): the bind-key line is
#   `bind-key [-r] -T <table> <key> <command...>` — the optional -r flag + alignment
#   spaces shift field positions, so tokenize and skip to -T, not field-index.
#   ⚠ `set -- $line` clobbers this function's $1/$2 => axis/dir are saved to locals FIRST.
# MOUSE EXCLUSION (FINDING 3, load-bearing): WheelDownStatus -> next-window is a TOP-LEVEL
#   command (substring would catch it) and MouseDown3StatusLeft has switch-client -n INSIDE
#   a display-menu block. TWO protections: (a) skip keys matching Mouse*|Wheel*; (b) the
#   session axis matches the command EXACTLY (== "switch-client -n" or starts with it + " "),
#   NOT as a substring — so display-menu's inner switch-client -n never matches. The window
#   axis DOES use substring (to catch the swap-window \; select-window compound).
# POST: drop single-char [A-Za-z0-9] (reserved for typing; keeps ) and ( ); de-dup first-seen;
#   subtract the control-key set (confirm/cancel/backspace/rename/delete via get_opt); append
#   the universal arrow extra for the session axis (Down/Up). ORDER is first-seen and
#   functionally irrelevant (distinct keys bind to the same action).
lp_discover_axis_keys() {
	local axis="${1:-}" dir="${2:-}"
	# save BEFORE the loop: `set -- $line` below clobbers the positional params.
	local out="" seen=""
	local line key cmd tok excl e match
	# control-key exclude set (get_opt is defined in options.sh, sourced by the caller at
	# call time — activate always sources options.sh first).
	excl="$(get_opt "@livepicker-confirm-keys" "Enter") $(get_opt "@livepicker-cancel-keys" "Escape") $(get_opt "@livepicker-backspace-keys" "BSpace") $(get_opt "@livepicker-rename-key" "C-r") $(get_opt "@livepicker-delete-key" "M-BSpace")"

	while IFS= read -r line; do
		[ -z "$line" ] && continue
		# shellcheck disable=SC2086  # intentional word-split: tokenize the bind-key line.
		set -- $line
		[ "${1:-}" = "bind-key" ] || continue
		shift
		# skip every flag (-r, and any other) until -T (handles -r + alignment uniformly)
		while [ "$#" -gt 0 ] && [ "${1:-}" != "-T" ]; do shift; done
		[ "${1:-}" = "-T" ] || continue
		shift              # drop -T
		[ "$#" -gt 0 ] && shift   # drop the table name (root/prefix)
		[ "$#" -gt 0 ] || continue
		key="$1"; shift
		cmd="$*"           # rejoined command (single-space-normalized; fine for substring match)

		# (b) exclude mouse/wheel keys (FINDING 3 protection 1)
		case "$key" in Mouse*|Wheel*) continue ;; esac

		# classify by axis:dir (FINDING 3: window=substring, session=EXACT top-level)
		match=0
		case "$axis:$dir" in
			window:next)
				case "$cmd" in
					*"select-window -n"*|*"select-window -t +1"*|*"select-window -t :+1"*|*"next-window"*) match=1 ;;
				esac ;;
			window:prev)
				case "$cmd" in
					*"select-window -p"*|*"select-window -t -1"*|*"select-window -t :-1"*|*"previous-window"*) match=1 ;;
				esac ;;
			session:next)
				[ "$cmd" = "switch-client -n" ] && match=1
				if [ "$match" -eq 0 ]; then
					case "$cmd" in "switch-client -n "*) match=1 ;; esac
				fi ;;
			session:prev)
				[ "$cmd" = "switch-client -p" ] && match=1
				if [ "$match" -eq 0 ]; then
					case "$cmd" in "switch-client -p "*) match=1 ;; esac
				fi ;;
		esac
		[ "$match" -eq 0 ] && continue

		# (d) drop single-char alphanumerics (reserved for typing; KEEPS ) and ( )
		case "$key" in [A-Za-z0-9]) continue ;; esac

		# (f) exclude fixed control keys so discovery never shadows them
		for e in $excl; do [ "$e" = "$key" ] && match=0; done
		[ "$match" -eq 0 ] && continue

		# (e) de-dup (first-seen)
		case " $seen " in *" $key "*) continue ;; esac
		seen="$seen $key"
		out="$out $key"
	done < <(tmux list-keys -T root 2>/dev/null; tmux list-keys -T prefix 2>/dev/null)

	# (g) session axis: always append the universal arrow extra
	if [ "$axis" = "session" ]; then
		case "$dir" in next) out="$out Down" ;; prev) out="$out Up" ;; esac
	fi

	# (h) print space-separated (trim the leading space); no trailing newline callers depend on
	out="${out# }"
	printf '%s' "$out"
}
```

Key pattern notes:
- `local axis="${1:-}" dir="${2:-}"` saves the args BEFORE the `set -- $line` loop (the trap).
- The `set -- $line` + skip-to-`-T` parse handles `-r` and alignment spaces uniformly.
- Window = substring `case` (catches the swap-window compound); session = exact `=` + starts-with.
- `case "$key" in [A-Za-z0-9])` drops exactly single-char alphanumerics; `)`/`(` survive.
- The exclude set is built once (outside the loop) via get_opt.
- Output is trimmed of its leading space; `printf '%s'` (no trailing newline — callers word-split).

### Integration Points

```yaml
CODE:
  - file: scripts/utils.sh
    change: "+1 function lp_discover_axis_keys (two-axis key discovery from live list-keys)"
    invariant: "prints the correct key SET per axis; mouse-excluded; alphanumerics dropped; control keys subtracted"

CONSUMERS (later subtask — DO NOT wire here):
  - P1.M2.T1.S1 (livepicker.sh T4): for each axis, if opt_<axis>_<dir>_keys is empty,
    call lp_discover_axis_keys <axis> <dir> and bind each returned key to the picker action.

CONFIG / DATABASE / ROUTES: none.
```

## Validation Loop

### Level 1: Syntax & Style (Immediate Feedback)

```bash
cd /home/dustin/.config/tmux/plugins/tmux-livepicker
bash -n scripts/utils.sh && echo "OK: utils syntax"
shellcheck scripts/utils.sh          # expect 0 NEW findings (SC1091/SC2086 disabled in-header/near set--)
# The function is present + named correctly:
grep -c '^lp_discover_axis_keys()' scripts/utils.sh   # -> 1
# No driver line added (utils.sh is a sourced lib):
tail -3 scripts/utils.sh | grep -q 'lp_discover_axis_keys "\$@"' && echo "FAIL: driver added" || echo "OK: no driver"
# Tabs-not-spaces on the new function (shfmt NOT installed):
awk '/^lp_discover_axis_keys/,/^}$/' scripts/utils.sh | grep -nP '^ ' && echo "WARN: space-indent" || echo "OK: tabs"
```

### Level 2: Discovery smoke (against an ISOLATED -L socket that sources the user config)

The isolated test socket sources the user's `~/.config/tmux/tmux.conf`, so its
`list-keys` matches the live bindings — the discovered SET must match the contract's
"for this user" values. Throwaway smoke (DELETE after; a committed test may land with
M2.T1's suite). Sources utils.sh + options.sh (so get_opt exists):

```bash
cat > /tmp/smoke_discover.sh <<'EOF'
#!/usr/bin/env bash
set -u
cd /home/dustin/.config/tmux/plugins/tmux-livepicker
source tests/setup_socket.sh
source tests/helpers.sh
setup_test "lp-smoke-discover"
source scripts/utils.sh
source scripts/options.sh   # get_opt for the control-key exclude set

pass=0; fail=0
# assert the SET (order-independent): sort both, compare.
seteq() { # $1 desc $2 got $3 want
	local got_sorted want_sorted
	got_sorted="$(printf '%s\n' $2 | sort | tr '\n' ' ' | sed 's/ $//')"
	want_sorted="$(printf '%s\n' $3 | sort | tr '\n' ' ' | sed 's/ $//')"
	if [ "$got_sorted" = "$want_sorted" ]; then pass=$((pass+1));
	else fail=$((fail+1)); printf 'FAIL %s:\n  got   [%s] -> sorted [%s]\n  want  [%s] -> sorted [%s]\n' "$1" "$2" "$got_sorted" "$3" "$want_sorted"; fi
}

seteq "window/next" "$(lp_discover_axis_keys window next)" "C-M-Tab M-n C-n C-l"
seteq "window/prev" "$(lp_discover_axis_keys window prev)" "C-M-BTab M-p C-p C-h"
seteq "session/next" "$(lp_discover_axis_keys session next)" ") Down"
seteq "session/prev" "$(lp_discover_axis_keys session prev)" "( Up"

# mouse exclusion: NO Mouse*/Wheel* key ever appears
for a in window session; do for d in next prev; do
	r="$(lp_discover_axis_keys "$a" "$d")"
	case " $r " in *" Mouse"*|*" Wheel"*) fail=$((fail+1)); echo "FAIL: mouse key leaked into $a/$d: [$r]";; esac
done; done

# plain alphanumeric drop: 'n'/'p'/digits never appear; ) and ( DO appear on session axis
wn="$(lp_discover_axis_keys window next)"
case " $wn " in *" n "*|*" p "*) fail=$((fail+1)); echo "FAIL: plain n/p leaked: [$wn]";; esac
sn="$(lp_discover_axis_keys session next)"
case " $sn " in *") "*) pass=$((pass+1));; *) fail=$((fail+1)); echo "FAIL: ) missing from session/next: [$sn]";; esac

# control-key exclusion: set confirm-keys to a discovered key, verify it is subtracted
tmux set-option -g @livepicker-confirm-keys "C-n"
wn2="$(lp_discover_axis_keys window next)"
case " $wn2 " in *" C-n "*) fail=$((fail+1)); echo "FAIL: C-n not excluded after confirm-keys=C-n: [$wn2]";;
	*) pass=$((pass+1));; esac
tmux set-option -gu @livepicker-confirm-keys

teardown_test
printf 'pass=%d fail=%d\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
EOF
bash /tmp/smoke_discover.sh; rc=$?
rm -f /tmp/smoke_discover.sh
exit $rc
# Expected: pass~=8 fail=0. The 4 seteq are the core proof; the mouse/alphanumeric/exclusion
# checks prove the traps are handled. (Order is asserted via sort, not the raw string —
# list-keys order is not contractually stable.)
```

### Level 3: No-side-effects proof (sourced-lib contract)

```bash
cd /home/dustin/.config/tmux/plugins/tmux-livepicker
# Sourcing utils.sh must define the function and print NOTHING.
out="$(set -u; source scripts/utils.sh; echo OK)"
[ "$out" = "OK" ] && echo "OK: source is silent" || echo "FAIL: source printed [$out]"
(set -u; source scripts/utils.sh; declare -F lp_discover_axis_keys >/dev/null) \
  && echo "OK: function defined" || echo "FAIL: function missing"
# Expected: source silent; function defined. (utils.sh sources nothing itself; get_opt is
# only needed at CALL time, which the smoke satisfies by sourcing options.sh too.)
```

### Level 4: Manual cross-check against the live server (read-only; list-keys mutates nothing)

```bash
cd /home/dustin/.config/tmux/plugins/tmux-livepicker
# A direct check against the user's real server (the isolated socket sources the same config,
# so results match). Confirm the 4 axes' SETs by eye:
set -u; source scripts/utils.sh; source scripts/options.sh
for a in window session; do for d in next prev; do
	printf '  %s/%s → [%s]\n' "$a" "$d" "$(lp_discover_axis_keys "$a" "$d")"
done; done
# Expected SETs: window/next {C-M-Tab,M-n,C-n,C-l}; window/prev {C-M-BTab,M-p,C-p,C-h};
# session/next {),Down}; session/prev {(,Up}. (Read-only — safe on the live server.)
```

## Final Validation Checklist

### Technical Validation

- [ ] `bash -n scripts/utils.sh` clean; `shellcheck` 0 NEW findings.
- [ ] `lp_discover_axis_keys` defined once (after tmux_clear_hook); no driver line.
- [ ] L2 smoke: pass~=8 fail=0 (4 seteq + mouse-exclusion + alphanumeric-drop + control-key-exclusion).
- [ ] L3: source is silent; function defined.

### Feature Validation

- [ ] All 4 axes print the correct SET (order-independent) against the live key tables.
- [ ] Mouse/Wheel keys never appear (WheelDownStatus→next-window, display-menu mouse keys excluded).
- [ ] `-r`-flagged bindings (C-h, C-l) parsed; plain n/p/0-9 dropped; `)`/`(` kept.
- [ ] Session axis excludes `-l`/`-t` (Z, C-Space) and display-menu inner commands (exact match).
- [ ] Session axis appends Down/Up; control-key exclusion subtracts confirm/cancel/etc.

### Code Quality Validation

- [ ] axis/dir saved to locals BEFORE the `set --` loop (the clobber trap).
- [ ] Parse skips-to-`-T` (handles `-r` + alignment spaces); not field-index.
- [ ] Window = substring; session = exact top-level (the two complementary rules).
- [ ] get_opt used for the exclude set (not a file-scope source of options.sh).
- [ ] `local` everywhere; tabs; `set -u`-safe; no `set -e`; tolerates empty/unknown axis/dir.

### Documentation & Deployment

- [ ] Header comment documents the parse trap, the mouse-exclusion dual protection, and the
      order-irrelevance note (Mode A — internal helper).
- [ ] No README/CHANGELOG change (the 4 option rows are T1.S1/P4; this is the discovery engine).
- [ ] Not wired into livepicker.sh here (M2.T1 owns the T4 rework).

---

## Anti-Patterns to Avoid

- ❌ Don't parse by field index — the `-r` flag + alignment spaces shift positions. Tokenize and
  skip to `-T`. (research FINDING 2.)
- ❌ Don't `set -- $line` before saving axis/dir to locals — it clobbers $1/$2. Save first. (FINDING 2.)
- ❌ Don't use substring match for the session axis — `display-menu { switch-client -n }` would
  match. Use EXACT top-level (`==` or starts-with `switch-client -n `). (FINDING 3.)
- ❌ Don't use exact match for the window axis — the `swap-window \; select-window` compound needs
  substring. Window=substring, session=exact — do NOT swap them.
- ❌ Don't forget the `Mouse*|Wheel*` key exclusion — `WheelDownStatus → next-window` is top-level
  and substring WOULD catch it. (FINDING 3.)
- ❌ Don't drop `)`/`(` — the alphanumeric-drop glob is `[A-Za-z0-9]` (single char in that class);
  punctuation is NOT in it. Verify `)`/`(` survive.
- ❌ Don't assert the exact output ORDER in a test — list-keys order isn't stable and the contract's
  "expected" string is a reference SET. Assert order-independently (sort both, compare).
- ❌ Don't source options.sh at utils.sh file scope — side effects + circular. Use get_opt at call
  time (activate sources options.sh first). The smoke sources options.sh alongside.
- ❌ Don't add a driver line (`*_main "$@"`) — utils.sh is a SOURCED library.
- ❌ Don't wire this into livepicker.sh here — P1.M2.T1.S1 owns the T4 rework. Ship unreferenced.
- ❌ Don't run the behavioral smoke against the user's real server for MUTATING ops — but list-keys
  is read-only, so L4 is safe; prefer the isolated socket (L2) for the committed-style smoke.
- ❌ Don't sort the output "for determinism" — first-seen is the spec; sorting diverges from it and
  gains nothing (order is functionally irrelevant).

---

## Confidence Score

**9 / 10** for one-pass success. Rationale: the complete function body is given verbatim and was
PROTOTYPED + run against the live user key tables, producing the correct SET for all 4 axes (mouse
false-positives excluded, `-r` bindings parsed, plain alphanumerics dropped, session exact-match
correct, de-dup correct, arrow extras appended). Every parsing trap (the `-r`/alignment parse, the
`set --` clobber, the mouse dual-exclusion, the window-substring-vs-session-exact rule) is documented
with the verified fix. The L2 smoke asserts the SET order-independently (robust to list-keys order)
plus the mouse/alphanumeric/exclusion traps. The function is a pure read-and-print helper, unreferenced
until M2.T1, so blast radius is nil. Residual risk: a shellcheck nuance on the `set --` word-split
(suppressed inline with SC2086) — caught by L1.
