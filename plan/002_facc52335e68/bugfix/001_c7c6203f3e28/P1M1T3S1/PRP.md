# PRP — P1.M1.T3.S1: Replace has-session gate with -P -F name capture in input-handler.sh

---

## Goal

**Feature Goal**: Fix Issue 3 — the create-on-confirm path in `scripts/input-handler.sh`
that **orphans a session and strands the user** whenever tmux silently sanitizes the
typed query (e.g. `my.proj` → `my_proj`). Replace the buggy `has-session -t "=$query"`
gate (which checks the ORIGINAL unsanitized name and so always fails after a successful,
sanitized `new-session`) with a `-P -F '#{session_name}'` capture that records the
ACTUAL name tmux created and switches the client to THAT.

**Deliverable**: One focused edit to the confirm branch's create-on-no-match block in
`scripts/input-handler.sh` (~lines 388-405). **No new files.** The change is: (a) add
`-P -F '#{session_name}'` to the `new_session_args` array, (b) replace the
`new-session && has-session` gate with a `created="$(new-session …)"; [ -n "$created" ]`
gate, (c) land on `$created` instead of `$query`, (d) rewrite the gate's rationale
comment. The else branch (`restore.sh cancel`) is kept — it now fires ONLY on genuine
failure (empty query / collision), never on a sanitized success.

**Success Definition**:
- Typing `my.proj` (no match) + Enter → a session named `my_proj` is created AND the
  client lands on it (no orphan, no stranding). Verified for `.hidden`→`_hidden`,
  `a:b`→`a_b`, `foo bar.baz`→`foo bar_baz`.
- Typing a pure-alphanumeric query (`zzzno`) → lands on `zzzno` (unchanged behavior;
  existing tests stay green).
- Empty query OR a collision (sanitized name already exists) → `created=""` →
  `restore.sh cancel`, and NO session is left behind.
- `bash -n` + `shellcheck` clean; `tests/run.sh` green (existing create tests use
  alphanumeric queries, unaffected).

## User Persona (if applicable)

**Target User**: The end user who types a query containing `.` (a PRD §6 typeable
character) and presses Enter expecting to land on the new session.

**Use Case**: User wants a session named `my.proj`; they type it, see no match, press
Enter. Before the fix: a phantom `my_proj` is created and abandoned, and they're returned
to their original session with no feedback. After the fix: they land on `my_proj`.

**Pain Points Addressed**: PRD §6 Confirm ("If creation fails (invalid name), cancel
instead") is violated — creation SUCCEEDS (sanitized) but the gate treats it as failure,
orphaning the session. The bug report (Issue 3) reproduces this for every `.`/`:` query.

---

## Why

- **Fixes a Major data/state bug.** Issue 3 (bug report §h2.2/h3.2): every sanitized
  create leaves an orphan session AND strands the user. `.` is in the typeable set, so
  this fires on a common, intended user action.
- **Root cause is the gate, not creation.** `new-session` correctly creates `my_proj`
  (rc=0). The bug is checking `has-session -t "=my.proj"` (the unsanitized query) right
  after — it always fails, so the just-created session is never landed on or cleaned up.
- **The `-P -F` capture is the minimal, version-robust fix.** Rather than replicating
  tmux's sanitization rules in bash (fragile across versions), capture whatever name
  tmux actually used. Approach (a) of the bug report's suggested fix; empirically proven.
- **Strictly better than the old gate.** Lands on every successful creation (any name);
  cancels without orphan on every failure. The old gate orphaned on every sanitized success.

## What

Replace the create block's gate. The edit touches three things inside the existing
`if [ "$pick_type" = "session" ] && [ "$(opt_create)" = "on" ]; then` block:

1. **The `local` line**: add `created=""` and insert `-P -F '#{session_name}'` into the
   `new_session_args` array.
2. **The gate**: `created="$(tmux new-session "${new_session_args[@]}" 2>/dev/null)"; if [ -n "$created" ]; then _confirm_land_on_session "$created"`.
3. **The comment**: rewrite to document that the gate now captures the actual name via
   `-P` (the `has-session` gate was the bug; the `-P` capture is the fix).

The zoxide `+=(-c "$z_target" -n "$z_target")` append and the `else … restore.sh cancel`
branch are UNCHANGED.

### Success Criteria

- [ ] `new_session_args` includes `-P -F '#{session_name}'` (single-quoted so bash passes
      the literal `#{session_name}` to tmux, which expands it).
- [ ] The gate is `created="$(tmux new-session … 2>/dev/null)"; if [ -n "$created" ]`.
- [ ] `_confirm_land_on_session "$created"` (NOT `"$query"`).
- [ ] The `else` branch still calls `"$CURRENT_DIR/restore.sh" cancel`.
- [ ] `bash -n` + `shellcheck` clean; `tests/run.sh` green; L2 smoke passes (sanitized
      create lands; collision/empty cancel with no orphan).

## All Needed Context

### Context Completeness Check

_Pass_: The implementer needs (a) the exact BEFORE/AFTER of the block (below), (b) the
empirical proof that `-P -F` captures the sanitized name in every case, and (c) the
validation commands. The fix is a ~6-line edit; no inference about tmux internals is
required — every behavior is verified live.

### Documentation & References

```yaml
# MUST READ — the bug report's own analysis (the primary research)
- docfile: plan/002_facc52335e68/bugfix/001_c7c6203f3e28/architecture/issue3_findings.md
  why: Documents the root cause (new-session sanitizes '.'/'.'->'_' rc=0, has-session
       checks the wrong name), the empirical sanitization table, and the recommended
       fix (Approach a: post-resolve the actual name). The exact BEFORE/AFTER diff there
       is the spec this PRP implements.
  section: "Recommended Fix: Approach (a) — Post-resolve the actual name"

# MUST READ — the live verification of every branch of the fix
- docfile: plan/002_facc52335e68/bugfix/001_c7c6203f3e28/P1M1T3S1/research/issue3_fix_findings.md
  why: FINDING 1 (-P -F captures sanitized names + composes with zoxide -c/-n); FINDING 2
       (the [ -n "$created" ] gate handles empty/collision/sanitized-success correctly);
       FINDING 3 (_confirm_land_on_session "$created" is the correct landing call);
       FINDING 4 (the array edit is SC2155-safe); FINDING 5 (existing tests unaffected);
       FINDING 6 (no parallel conflict with P1.M1.T2.S2).
  critical: Read BEFORE editing. Confirms collision -> created="" -> cancel (no orphan)
            and that -F '#{session_name}' captures the SESSION name (not the -n window name).

# MUST READ — the file + exact function being edited
- file: scripts/input-handler.sh
  why: The confirm branch's create-on-no-match block (~lines 388-405). The variables in
        scope: $query (raw typed filter), $new_session_args (the array), $cur_filter,
        $pick_type, _confirm_land_on_session (the switch+restore helper at line 79).
        set -u is active (NO set -e); options/utils/state/filter sourced via CURRENT_DIR.
  pattern: the zoxide append `new_session_args+=(-c "$z_target" -n "$z_target")` stays
           exactly as-is; -P -F composes harmlessly before it (verified).
  gotcha: `_confirm_land_on_session "$created"` (the CAPTURED name), not `"$query"`. The
          helper does `switch-client -t "=$tgt"` — passing the sanitized name lands correctly.

# MUST READ — _confirm_land_on_session (the landing helper, UNCHANGED)
- file: scripts/input-handler.sh
  why: Lines 79-110. Takes tgt="${1:-}", unlinks the driver preview (H2-hardened),
        `tmux switch-client -t "=$tgt"`, then `restore.sh keep`. Passing $created makes
        the switch land on the actually-created session. Do NOT edit this helper.
  section: "_confirm_land_on_session()"

# MUST READ — the test pattern for the throwaway smoke (and S2's committed test)
- file: tests/test_create.sh
  why: The 3 existing create tests drive the REAL plugin (livepicker.sh activate →
        input-handler.sh type/confirm) against the socket-isolated harness and assert via
        pass/fail/assert_eq. They use alphanumeric queries (zzzno/qwfx/mplg) — unaffected
        by the fix. Mirror this pattern for the L2 throwaway smoke (use a DOTTED query).
  pattern: attach_test_client FIRST; set-option -g @livepicker-create on BEFORE activate;
           type char-by-char; confirm; assert has-session + display-message session_name.

# CONTEXT — PRD §6 (the confirm/create contract) + §11 (the create/zoxide options)
- docfile: PRD.md  (the livepicker PRD, repo root)
  why: §6 Confirm ("If creation fails (invalid name), cancel instead") + §6 Filtering
        (the typeable set includes '.') define the contract this fix restores. §11
        @livepicker-create / @livepicker-zoxide-mode are the options gating this branch.
  section: "§6 Behaviors → Confirm", "§6 Filtering", "§11 Configuration options"
```

### Current Codebase tree

```bash
tmux-livepicker/
  scripts/
    input-handler.sh   # MODIFY: the confirm/create block (~lines 388-405) — the gate
    preview.sh / restore.sh / livepicker.sh / renderer.sh / options.sh / state.sh / utils.sh / filter.sh  # UNCHANGED
  tests/
    test_create.sh      # UNCHANGED here (uses alphanumeric queries; the sanitized-name
                         #   regression test is P1.M1.T3.S2, the next subtask)
    ... (run.sh, setup_socket.sh, helpers.sh, test_*.sh)  # UNCHANGED
```

### Desired Codebase tree with files to be added and responsibility of file

```bash
scripts/input-handler.sh   # EDIT: create block captures the actual name via -P -F and
                            #   lands on it; no orphan on sanitized create.
```

### Known Gotchas of our codebase & Library Quirks

```bash
# CRITICAL: -F '#{session_name}' MUST be single-quoted so bash passes the LITERAL
# #{session_name} to tmux (which expands it). Double quotes would let bash try to expand
# it (no such var -> literal, happens to work, but single quotes are unambiguous and
# match the empirical test). In the array literal `(-d -P -F '#{session_name}' -s "$query")`
# the single quotes strip, leaving the element #{session_name}; "${new_session_args[@]}"
# passes it as one correct arg. Verified.

# CRITICAL: land on "$created" (the captured name), NOT "$query". _confirm_land_on_session
# does `switch-client -t "=$tgt"`; passing the sanitized name (my_proj) lands correctly,
# passing the raw query (my.proj) strands the client (no such session). This is the
# one-character-that-matters change: $query -> $created at the _confirm_land_on_session call.

# CRITICAL: the gate is `[ -n "$created" ]`, NOT new-session's rc. new-session returns rc=0
# on a SANITIZED success (my.proj -> my_proj, rc=0), so an rc-based gate cannot detect the
# name change. The -P capture is the only reliable signal: empty stdout => creation failed
# (empty query rc=1, or collision rc=1); non-empty stdout => the actual created name.

# CRITICAL: declare `created=""` on the local line BEFORE the assignment
# `created="$(tmux new-session ...)"`. Declaring+assigning in one statement
# (`local created="$(...)"`) triggers shellcheck SC2155 AND masks the tmux rc (not needed
# here since we check stdout, but keep the style consistent with the rest of the file).

# GOTCHA: tmux sanitizes BOTH '.' and ':' to '_' EVERYWHERE (not just leading). The old
# comment said "leading '.'" — that was wrong; the corrected comment must say every '.'/':'.
# (Verified: my.proj->my_proj, a:b->a_b, a..b->a__b, foo bar.baz->foo bar_baz.)

# GOTCHA: collision handling is automatic. If the sanitized name already exists (user types
# my.proj but my_proj exists), new-session refuses (no -A flag) -> rc=1, stdout empty ->
# created="" -> cancel. No orphan. (Verified live.) Do NOT add an explicit collision check.

# GOTCHA: the zoxide path appends `+=(-c "$z_target" -n "$z_target")` AFTER -s "$query".
# -n sets the WINDOW name (not session); -F '#{session_name}' still captures the SESSION
# name. The -P -F flags compose harmlessly before the -c/-n append. Verified (x.y + -c -n
# -> x_y). Do NOT reorder or touch the zoxide append.

# GOTCHA: input-handler.sh runs under `set -u` (NO `set -e`). $query, $cur_filter,
# $pick_type are all already in scope (set earlier in the confirm branch). `created` must
# be declared `local` (it is, on the local line) before use. Indent with TABS.

# GOTCHA: do NOT add a committed tests/ file in this subtask. The regression test for the
# sanitized-name path is P1.M1.T3.S2. Validate via the throwaway L2 smoke (DELETE after),
# which drives the REAL plugin with a dotted query.
```

## Implementation Blueprint

### Data models and structure

No data-model change. The "model" is the create+capture+gate flow:

```
confirm branch, empty-filtered-list, session mode, create on:
  query = cur_filter
  new_session_args = (-d -P -F '#{session_name}' -s "$query")      # -P captures the name
  if opt_zoxide == on: new_session_args += (-c "$z_target" -n "$z_target")   # unchanged
  created = $(tmux new-session "${new_session_args[@]}" 2>/dev/null)          # capture
  if [ -n "$created" ]:                                                      # gate on CAPTURED name
      _confirm_land_on_session "$created"                                    # land on actual name
  else:
      restore.sh cancel                                        # empty/collision -> cancel, no orphan
  return 0
```

### Implementation Tasks (ordered by dependencies)

```yaml
Task 1: MODIFY scripts/input-handler.sh — the local line
  - LOCATE (by content): the line
        local z_target="" new_session_args=(-d -s "$query")
    inside the `if [ "$pick_type" = "session" ] && [ "$(opt_create)" = "on" ]; then` block
    of the confirm branch.
  - REPLACE with:
        local z_target="" created="" new_session_args=(-d -P -F '#{session_name}' -s "$query")
  - RATIONALE: +created (declare-first for the capture, SC2155-safe); +-P -F '#{session_name}'
    (tmux prints the actual created session name to stdout). Single-quoted #{session_name}.

Task 2: MODIFY scripts/input-handler.sh — the comment + gate
  - LOCATE (by content): the comment block + gate:
        # Robust create gate (FINDING 4/5). new-session SILENTLY SANITIZES
        # names (':'->'_', leading '.'->'_') and returns rc=0 with a
        # DIFFERENT name, so checking rc alone would strand the client
        # (switch-client -t "=.hidden" -> rc=1, no such session). Require
        # BOTH new-session rc=0 AND the EXACT $query name to now exist
        # (has-session exact-match =). A duplicate cannot occur here: if
        # an exact-$query session existed it would be a case-insensitive
        # match -> in the filtered list -> this branch is never reached.
        # Empty query -> new-session rc=1 -> gate false -> cancel.
        if tmux new-session "${new_session_args[@]}" 2>/dev/null && tmux has-session -t "=$query" 2>/dev/null; then
            _confirm_land_on_session "$query"
        else
            # Invalid/sanitized/empty name -> cancel (PRD §6 Confirm).
            "$CURRENT_DIR/restore.sh" cancel
        fi
  - REPLACE with (see "Implementation Patterns" for the verbatim block): the -P capture
    gate. The comment is rewritten: the has-session gate WAS the bug (it checked the
    unsanitized $query); the -P capture is the fix (it lands on the actual name tmux
    created, whatever its sanitization).
  - PRESERVE: the `else … restore.sh cancel` branch (now fires only on genuine failure)
    and the trailing `return 0`. Do NOT touch the zoxide append above or anything else.

Task 3: VALIDATE (syntax + throwaway smoke + full suite)
  - RUN: bash -n scripts/input-handler.sh
  - RUN: shellcheck scripts/input-handler.sh (expect 0 NEW findings)
  - RUN: the throwaway smoke (Validation Loop L2) — drives the REAL plugin with a dotted
    query, asserts landing on the sanitized name + no orphan; plus the collision + plain
    cases. DELETE the smoke file after.
  - RUN: tests/run.sh (expect: full suite green — existing create tests use alphanumeric
    queries, so the fix is a no-op for them).
```

### Implementation Patterns & Key Details

**The edit (Tasks 1+2) — the BEFORE and AFTER of the create block:**

BEFORE (current, ~lines 388-405):
```bash
			if [ "$pick_type" = "session" ] && [ "$(opt_create)" = "on" ]; then
				query="$cur_filter"
				# @livepicker-zoxide-mode on (mirrors sessionx's @sessionx-zoxide-mode):
				# resolve the query through zoxide and start the session there
				# (-c "$z_target"), naming the window after the dir (-n, like sessionx).
				# zoxide only resolves dirs it has indexed with enough frecency; an
				# empty result (not indexed / below threshold / zoxide absent) falls
				# back to a PLAIN create (no -c) rather than -c "" — more robust than
				# sessionx, and still satisfies the create gate below.
				local z_target="" new_session_args=(-d -s "$query")
				if [ "$(opt_zoxide)" = "on" ]; then
					z_target="$(zoxide query "$query" 2>/dev/null)"
					[ -n "$z_target" ] && new_session_args+=(-c "$z_target" -n "$z_target")
				fi
				# Robust create gate (FINDING 4/5). new-session SILENTLY SANITIZES
				# names (':'->'_', leading '.'->'_') and returns rc=0 with a
				# DIFFERENT name, so checking rc alone would strand the client
				# (switch-client -t "=.hidden" -> rc=1, no such session). Require
				# BOTH new-session rc=0 AND the EXACT $query name to now exist
				# (has-session exact-match =). A duplicate cannot occur here: if
				# an exact-$query session existed it would be a case-insensitive
				# match -> in the filtered list -> this branch is never reached.
				# Empty query -> new-session rc=1 -> gate false -> cancel.
				if tmux new-session "${new_session_args[@]}" 2>/dev/null && tmux has-session -t "=$query" 2>/dev/null; then
					_confirm_land_on_session "$query"
				else
					# Invalid/sanitized/empty name -> cancel (PRD §6 Confirm).
					"$CURRENT_DIR/restore.sh" cancel
				fi
				return 0
			fi
```

AFTER (fixed):
```bash
			if [ "$pick_type" = "session" ] && [ "$(opt_create)" = "on" ]; then
				query="$cur_filter"
				# @livepicker-zoxide-mode on (mirrors sessionx's @sessionx-zoxide-mode):
				# resolve the query through zoxide and start the session there
				# (-c "$z_target"), naming the window after the dir (-n, like sessionx).
				# zoxide only resolves dirs it has indexed with enough frecency; an
				# empty result (not indexed / below threshold / zoxide absent) falls
				# back to a PLAIN create (no -c) rather than -c "" — more robust than
				# sessionx, and still satisfies the create gate below.
				local z_target="" created="" new_session_args=(-d -P -F '#{session_name}' -s "$query")
				if [ "$(opt_zoxide)" = "on" ]; then
					z_target="$(zoxide query "$query" 2>/dev/null)"
					[ -n "$z_target" ] && new_session_args+=(-c "$z_target" -n "$z_target")
				fi
				# Create gate (Issue 3 fix). new-session SILENTLY SANITIZES names
				# (every '.' and ':' -> '_') and returns rc=0 with a DIFFERENT name.
				# The OLD gate (has-session -t "=$query") checked the ORIGINAL
				# unsanitized query, so it always failed after a sanitized success ->
				# the just-created session was orphaned and the client stranded.
				# FIX: -P -F '#{session_name}' captures the ACTUAL name tmux created;
				# gate on a non-empty capture and switch to THAT name. Empty query or
				# a collision (sanitized name exists) -> new-session rc=1, stdout empty
				# -> created="" -> cancel (NO orphan). See research/issue3_fix_findings.md.
				created="$(tmux new-session "${new_session_args[@]}" 2>/dev/null)"
				if [ -n "$created" ]; then
					_confirm_land_on_session "$created"
				else
					# Genuine failure (empty/collision) -> cancel (PRD §6 Confirm).
					"$CURRENT_DIR/restore.sh" cancel
				fi
				return 0
			fi
```

NOTE for the implementer: the edit is the local line (Task 1) + the comment/gate block
(Task 2). The two regions are disjoint (the local line is ~10 lines above the gate); do
them as two `edit` entries in one call OR two sequential edits. Do NOT touch the zoxide
append, the `else` branch body, the `return 0`, or any other file. The helper
`_confirm_land_on_session` is UNCHANGED (it already takes the target name as `$1`).

### Integration Points

```yaml
CODE:
  - file: scripts/input-handler.sh
    change: "create block: +(-P -F '#{session_name}') to new_session_args; gate on captured name; land on $created"
    invariant: "sanitized create lands on the actual name; empty/collision cancel with no orphan"

CONSUMERS:
  - tests/test_create.sh: UNCHANGED (alphanumeric queries; the fix is a no-op for them).
  - P1.M1.T3.S2 (next subtask): adds the committed sanitized-name regression test
    (test_create_sanitized_name_lands or similar) to tests/test_create.sh — this PRP's
    L2 smoke is the throwaway prototype for it.

CONFIG / DATABASE / ROUTES: none.
```

## Validation Loop

### Level 1: Syntax & Style (Immediate Feedback)

```bash
cd /home/dustin/.config/tmux/plugins/tmux-livepicker
bash -n scripts/input-handler.sh && echo "OK: input-handler syntax"
shellcheck scripts/input-handler.sh
# Confirm the fix is present + the old gate is gone:
grep -c "has-session -t \"=\$query\"" scripts/input-handler.sh   # -> 0 (the buggy gate removed)
grep -c "-P -F '#{session_name}'" scripts/input-handler.sh       # -> 1 (the capture added)
grep -c '_confirm_land_on_session "\$created"' scripts/input-handler.sh  # -> 1 (land on captured)
# Tabs-not-spaces on the edited region (shfmt NOT installed):
grep -nP '^ +[^#/]' scripts/input-handler.sh && echo "WARN: space-indent (use tabs)" || echo "OK: tabs"
# Expected: syntax clean; shellcheck 0 new findings; the 3 grep counts as above.
```

### Level 2: Create-path smoke (via the existing socket-isolated harness)

Throwaway smoke (DELETE after; the committed regression test is P1.M1.T3.S2). Drives the
REAL plugin (livepicker.sh activate → input-handler.sh type/confirm) exactly like
`tests/test_create.sh`, but with DOTTED queries. Reuses `tests/setup_socket.sh` +
`tests/helpers.sh`:

```bash
cat > /tmp/smoke_issue3.sh <<'EOF'
#!/usr/bin/env bash
set -u
cd /home/dustin/.config/tmux/plugins/tmux-livepicker
source tests/setup_socket.sh
source tests/helpers.sh

pass_n=0; fail_n=0
ck() { if [ "$2" = "$3" ]; then pass_n=$((pass_n+1)); else fail_n=$((fail_n+1)); echo "FAIL $1: got[$2] want[$3]"; fi; }

# --- (1) sanitized create LANDS on the actual name (no orphan, no stranding) ---
setup_test "lp-i3-sanitized"
attach_test_client
tmux set-option -g @livepicker-create on
tmux set-option -g @livepicker-zoxide-mode off
"$LIVEPICKER_SCRIPTS/livepicker.sh"
for c in m y . p r o j; do "$LIVEPICKER_SCRIPTS/input-handler.sh" type "$c"; done
"$LIVEPICKER_SCRIPTS/input-handler.sh" confirm
# the sanitized session exists:
if tmux has-session -t "=my_proj" 2>/dev/null; then pass_n=$((pass_n+1)); else fail_n=$((fail_n+1)); echo "FAIL: my_proj not created"; fi
# the client LANDED on it (not stranded on driver):
ck "landed on sanitized name" "$(tmux display-message -p '#{session_name}')" "my_proj"
# NO orphan under the raw query name:
if tmux has-session -t "=my.proj" 2>/dev/null; then fail_n=$((fail_n+1)); echo "FAIL: orphan my.proj exists"; else pass_n=$((pass_n+1)); fi
# picker torn down:
ck "mode cleared" "$(tmux show-option -gqv @livepicker-mode)" ""
teardown_test

# --- (2) collision (sanitized name exists) -> cancel, NO new session, NO orphan ---
setup_test "lp-i3-collision"
attach_test_client
tmux set-option -g @livepicker-create on
tmux set-option -g @livepicker-zoxide-mode off
tmux new-session -d -s coll_proj 2>/dev/null   # pre-create the sanitized target
local_before="$(tmux list-sessions -F '#{session_name}' | sort | tr '\n' ',')"
"$LIVEPICKER_SCRIPTS/livepicker.sh"
for c in c o l l . p r o j; do "$LIVEPICKER_SCRIPTS/input-handler.sh" type "$c"; done   # filter "coll.proj"
"$LIVEPICKER_SCRIPTS/input-handler.sh" confirm
local_after="$(tmux list-sessions -F '#{session_name}' | sort | tr '\n' ',')"
ck "no new session on collision" "$local_after" "$local_before"   # session set unchanged
ck "client on driver (cancel)" "$(tmux display-message -p '#{session_name}')" "$TEST_DRIVER_SESSION"
teardown_test

# --- (3) plain alphanumeric (regression — existing behavior unchanged) ---
setup_test "lp-i3-plain"
attach_test_client
tmux set-option -g @livepicker-create on
tmux set-option -g @livepicker-zoxide-mode off
"$LIVEPICKER_SCRIPTS/livepicker.sh"
for c in z z z n o; do "$LIVEPICKER_SCRIPTS/input-handler.sh" type "$c"; done
"$LIVEPICKER_SCRIPTS/input-handler.sh" confirm
if tmux has-session -t "=zzzno" 2>/dev/null; then pass_n=$((pass_n+1)); else fail_n=$((fail_n+1)); echo "FAIL: zzzno not created"; fi
ck "landed on plain name" "$(tmux display-message -p '#{session_name}')" "zzzno"
teardown_test

echo "pass=$pass_n fail=$fail_n"
[ "$fail_n" -eq 0 ]
EOF
bash /tmp/smoke_issue3.sh; rc=$?
rm -f /tmp/smoke_issue3.sh
exit $rc
# Expected: pass~=12 fail=0. (1) proves the fix — my.proj -> land on my_proj, no orphan;
# (2) proves collision -> cancel, session set unchanged; (3) proves alphanumeric unchanged.
# NOTE: zoxide is forced OFF so zoxide query does not interfere with the dotted-name path.
#       (The zoxide composition is separately proven in research FINDING 1/4.)
```

### Level 3: Full suite (no regression)

```bash
cd /home/dustin/.config/tmux/plugins/tmux-livepicker
tests/run.sh
# Expected: exit 0, all existing tests green. The 3 create tests use alphanumeric queries
# (zzzno/qwfx/mplg); with the fix, created="<query>" (no sanitization) -> land, identical
# to today. No existing assertion can regress. (The sanitized-name regression test lands
# in P1.M1.T3.S2.)
```

### Level 4: Collision + zoxide-composition sanity (isolated socket, no plugin)

```bash
cd /home/dustin/.config/tmux/plugins/tmux-livepicker
# Re-confirm the -P -F mechanism directly (decoupled from the plugin) for collision + zoxide.
SOCK=lp_i3L4_$$
tmux -L "$SOCK" new-session -d -s driver
# collision: sanitized name exists -> empty stdout, rc=1
tmux -L "$SOCK" new-session -d -s taken_name
out="$(tmux -L "$SOCK" new-session -d -P -F '#{session_name}' -s 'taken.name' 2>/dev/null)"; echo "collision -> [$out] (empty=cancel)"
# zoxide-style -c/-n compose: captures the SESSION name (x.y -> x_y), not the -n window name
out="$(tmux -L "$SOCK" new-session -d -P -F '#{session_name}' -s 'dir.proj' -c /tmp -n winname 2>/dev/null)"; echo "zoxide-style -> [$out] (want dir_proj)"
tmux -L "$SOCK" kill-server 2>/dev/null
# Expected: collision -> [] (empty); zoxide-style -> [dir_proj].
```

## Final Validation Checklist

### Technical Validation

- [ ] `bash -n scripts/input-handler.sh` clean.
- [ ] `shellcheck scripts/input-handler.sh`: 0 NEW findings.
- [ ] `has-session -t "=$query"` no longer appears in the create gate (grep count 0).
- [ ] `-P -F '#{session_name}'` present once; `_confirm_land_on_session "$created"` once.

### Feature Validation

- [ ] `my.proj` + Enter → session `my_proj` created AND client on `my_proj` (L2 §1).
- [ ] No orphan `my.proj` session (L2 §1).
- [ ] Collision (sanitized name exists) → cancel, session set unchanged, client on driver (L2 §2).
- [ ] Plain alphanumeric (`zzzno`) → lands on `zzzno` (L2 §3, regression).
- [ ] Collision + zoxide composition confirmed direct (L4).
- [ ] Full `tests/run.sh` suite green (exit 0); no regression.

### Code Quality Validation

- [ ] `created` declared `local` (on the local line) before the `created="$(…)"` assign (SC2155-safe).
- [ ] `-F '#{session_name}'` single-quoted (literal passed to tmux).
- [ ] Lands on `$created`, not `$query`.
- [ ] Zoxide append, `else` branch, `return 0` UNCHANGED.
- [ ] Comment rewritten: documents the `-P` capture as the fix (the has-session gate was the bug);
      sanitization rule corrected to "every '.' and ':' -> '_'".
- [ ] Tabs for indent; `set -u`-safe.

### Documentation & Deployment

- [ ] Inline comment updated (Mode A — the gate's rationale now documents -P capture).
- [ ] No README/CHANGELOG change here (the bug-fix changelog entry is P1.M3.T1.S1; this is
      the code fix). 
- [ ] Do NOT commit a tests/ file (the sanitized-name regression test is P1.M1.T3.S2).

---

## Anti-Patterns to Avoid

- ❌ Don't keep the `has-session -t "=$query"` gate (or add it alongside the capture) — it is
  the BUG. It checks the unsanitized name and always fails after a sanitized success. The
  `-P -F` capture + `[ -n "$created" ]` replaces it entirely.
- ❌ Don't land on `"$query"` — land on `"$created"` (the captured/sanitized name). Passing
  the raw query to `_confirm_land_on_session` strands the client (the original bug).
- ❌ Don't gate on new-session's rc — it returns rc=0 on a sanitized success; only the
  captured name (empty vs non-empty) reliably distinguishes success from failure.
- ❌ Don't double-quote `#{session_name}` — single-quote it so bash passes the literal to
  tmux (which expands it). Double quotes happen to work but are ambiguous.
- ❌ Don't pre-sanitize the query in bash to "fix" the name — that replicates tmux's rules
  (fragile across versions). Capture the actual name instead (Approach a, not a bash rewrite).
- ❌ Don't touch the zoxide `+=(-c … -n …)` append — `-P -F` composes harmlessly before it;
  `-n` sets the window name, `-F '#{session_name}'` still captures the session name.
- ❌ Don't add a `kill-session` cleanup on the failure path — there's nothing to clean up
  (creation failed → no session was created). The old bug's orphan came from a SUCCESSFUL
  creation that the gate then rejected; the capture eliminates that.
- ❌ Don't edit `_confirm_land_on_session` — it already takes the target as `$1`. Only the
  argument changes (`$query` → `$created`).
- ❌ Don't commit a tests/ file — feature validation is P1.M1.T3.S2; use the throwaway L2 smoke.
- ❌ Don't collapse `local created=""; created="$(…)"` into `local created="$(…)"` (SC2155;
  masks the tmux rc — not needed here since we check stdout, but keep the file's style).
- ❌ Don't edit by line number — anchor on the unique content (the `local z_target=""…`
  line and the `has-session -t "=$query"` gate).

---

## Confidence Score

**9 / 10** for one-pass success. Rationale: the fix is a ~6-line edit whose BEFORE/AFTER is
given verbatim and whose mechanism (`-P -F '#{session_name}'` captures the sanitized name)
is empirically proven for every branch (sanitized success, plain name, empty query,
collision, zoxide composition). The landing helper is unchanged (only its argument changes).
Existing tests use alphanumeric queries, so the fix is a no-op for them (`tests/run.sh`
stays green by construction). The L2 smoke deterministically proves the three cases
(sanitized-lands, collision-cancels, plain-unchanged). Residual risk: an edit-tool `oldText`
mismatch on the comment block (mitigated by the unique `has-session -t "=$query"` anchor +
the L1 grep verification) and the single-vs-double-quote `#{session_name}` nuance
(documented; single quotes are unambiguous and match the empirical test).
