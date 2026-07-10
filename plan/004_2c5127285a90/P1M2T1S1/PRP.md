# PRP — P1.M2.T1.S1: Resolve axis keys + rework T4 binding blocks in livepicker.sh

> **Scope**: Rework the T4 key-binding block in `scripts/livepicker.sh::activate_main` to
> resolve the **two navigation axes** (session + window) via the new accessors +
> `lp_discover_axis_keys` (explicit option overrides; empty → discover from the user's live
> key tables), bind the **window axis** (next-window/prev-window) and **session axis**
> (next-session/prev-session) explicitly, remove the dead old-nav-key code path
> (`opt_next_key`/`opt_prev_key`/`opt_nav_*_keys` are GONE from options.sh — this fixes the
> resulting break), and update the one test that asserts the livepicker-table nav binding.
> PRD §8 (two-axis, discovered) is the spec.

---

## Goal

**Feature Goal**: Activate's T4 block resolves 4 axis key-lists (`s_next`/`s_prev`/`w_next`/
`w_prev`) — each from its `@livepicker-*-keys` option, falling back to `lp_discover_axis_keys`
when empty — and binds, in the `livepicker` table: the **window axis** (each `$w_next`→
`next-window`, `$w_prev`→`prev-window`) then the **session axis** (each `$s_next`→
`next-session`, `$s_prev`→`prev-session`). The dead `opt_next_key`/`opt_prev_key`/`opt_nav_*`
references and the now-redundant `grep -vF` copy-skip are removed. The copy
(`lp_filter_harmful_bindings`) already drops nav keys, so the explicit binds are authoritative.

**Deliverable**: Edits to `scripts/livepicker.sh` (the T4 block: axis resolution + locals;
copy block cleanup; nav-loop replacement; stale-comment rewrites) + `tests/test_keyrepurpose.sh`
(the during-picker assertion: next-session → next-window). **No new files.**

**Success Definition**:
- After activate, `list-keys -T livepicker C-M-Tab` → `run-shell …/input-handler.sh next-window`
  (C-M-Tab is a discovered window/next key); `C-M-BTab` → `prev-window`. Session-axis keys
  (e.g. `)`, `Down`) → `next-session`; `(`, `Up` → `prev-session`.
- An explicit `@livepicker-session-next-keys "j k"` OVERRIDES discovery for that axis (j/k →
  next-session; discovery not called for session/next).
- `next-window`/`prev-window` are inert no-ops until P2.M1.T3 (they hit input-handler's `*)`
  branch) — intentional; the bindings are correct and land now.
- The copy block keeps `lp_filter_harmful_bindings` (drops nav keys); the `grep -vF` skip is
  gone; no dead `opt_next_key`/`opt_prev_key`/`opt_nav_*` references remain.
- `test_keyrepurpose_during_picker` PASSES with the updated assertion; `test_keyrepurpose_reverts_after_exit`
  still passes (root table never mutated); `tests/run.sh` green (no other test regresses — the
  others call `input-handler.sh next-session` directly, which is unchanged).

## User Persona (if applicable)

**Target User**: The end user (muscle-memory reuse) + the §15.24 key-discovery tests.

**Use Case**: The user activates the picker. Their familiar `Ctrl-M-Tab`/`M-n`/`C-n` (which
flip windows in normal tmux) now flip the **previewed session's windows**; `)`/`(`/arrows
move between **sessions**. Both axes are discovered from their config — no imposed defaults.

**Pain Points Addressed**: The old single-axis model repurposed window-nav keys into
session-nav, fighting muscle memory (dropped per PRD §8). The current code is also BROKEN
(it calls accessors P1.M1.T1.S1 removed). This task ships the two-axis discovered binding.

## Why

- **Implements PRD §8 (the two-axis key subsystem).** Both axes reuse the user's own keys,
  discovered automatically. This is the binding half (T4); discovery (P1.M1.T2.S1) + the
  accessors (P1.M1.T1.S1) are the inputs.
- **Fixes the broken intermediate state.** P1.M1.T1.S1 removed `opt_next_key`/`opt_prev_key`/
  `opt_nav_next_keys`/`opt_nav_prev_keys`; livepicker.sh still calls them → activate is
  currently broken. This task is the consumer-side fix that completes the option-model swap.
- **Inert-but-correct window binds unblock P2.M1.T3.** The next-window/prev-window bindings
  land now (correct keys, correct actions); the actions themselves arrive in P2.M1.T3. Until
  then they no-op (picker stays open) — no regression.
- **Disjoint from the parallel P1.M1.T2.S1** (utils.sh only; `lp_discover_axis_keys` already
  present). Zero file overlap.

## What

1. **Axis resolution (top of T4)**: `local lp_tf lp_c s_next s_prev w_next w_prev`; resolve
   each axis (explicit `opt_*` → if empty, `lp_discover_axis_keys AXIS DIR`).
2. **Copy block**: remove `lp_key`/`lp_keys` (dead) + the `grep -vF` skip; keep
   `lp_filter_harmful_bindings | source-file`.
3. **Nav loops → two axis blocks**: window axis (`$w_next`→next-window, `$w_prev`→prev-window)
   then session axis (`$s_next`→next-session, `$s_prev`→prev-session).
4. **Rewrite stale comments**: "Discovery OMITTED"→two-axis resolution; "Skip next/prev keys
   (FINDING 4)"→lp_filter_harmful_bindings drops nav keys; remove the "L3 FIX grep -F" paragraph.
5. **UNTOUCHED**: typing/backspace/confirm/cancel binds, rename/delete binds, key-table switch,
   hook-suppression block.
6. **Test**: `test_keyrepurpose_during_picker` assertions next-session→next-window,
   prev-session→prev-window (+ the attached prose comments).

### Success Criteria

- [ ] 4 axis locals resolved (explicit→discover) at the top of T4.
- [ ] No `opt_next_key`/`opt_prev_key`/`opt_nav_next_keys`/`opt_nav_prev_keys`/`lp_key`/`lp_keys`
      references remain in livepicker.sh (grep: 0).
- [ ] No `grep -vF` skip in the copy block; `lp_filter_harmful_bindings` retained.
- [ ] Window-axis binds (next-window/prev-window) precede session-axis binds (next-session/prev-session).
- [ ] Typing/backspace/confirm/cancel/rename/delete binds + key-table switch byte-identical.
- [ ] `test_keyrepurpose_during_picker` asserts next-window/prev-window; PASSES.
- [ ] `bash -n` + `shellcheck` clean; `tests/run.sh` green.

## All Needed Context

### Context Completeness Check

_Pass_: The implementer needs (a) the verbatim edits (below, with exact content anchors),
(b) the resolution idiom, (c) the "remove the grep-skip — lp_filter_harmful_bindings covers it"
decision, (d) the inert-next-window note, and (e) the one test update. Every site is located
by verified-current content.

### Documentation & References

```yaml
# MUST READ — the empirical ground-truth for THIS task (7 findings)
- docfile: plan/004_2c5127285a90/P1M2T1S1/research/t4_two_axis_binding_findings.md
  why: FINDING 1 (the 4 rework sites with current line numbers; what's UNTOUCHED); FINDING 2
       (the 4 accessors + lp_discover_axis_keys are present; the resolution idiom; the OLD
       accessors are GONE -> livepicker.sh is the broken intermediate this fixes); FINDING 3
       (removing the grep -vF skip is SAFE — lp_filter_harmful_bindings drops swap-window/
       select-window/next-window/switch-client, which covers every nav key; + last-wins);
       FINDING 4 (binding ORDER window-then-session, placed where the old nav loops were, is
       functionally equivalent — disjoint key sets); FINDING 5 (next-window/prev-window are
       INTENTIONALLY inert until P2.M1.T3 — do NOT add the actions); FINDING 6 (the ONE test
       to update + the reverts_after_exit + direct-call tests that stay green); FINDING 7
       (no conflict with parallel P1.M1.T2.S2... P1.M1.T2.S1 — utils.sh only).
  critical: FINDING 3 (the grep-skip removal is safe) + FINDING 5 (inert next-window) are the
            two things most likely to be second-guessed. Read BEFORE editing.

# MUST READ — the discovery helper CONTRACT (the function this task calls)
- docfile: plan/004_2c5127285a90/P1M1T2S1/PRP.md
  why: Defines lp_discover_axis_keys AXIS DIR (utils.sh): prints the space-separated keys for
        the axis+dir; mouse-excluded; alphanumerics dropped; control keys subtracted; arrows
        appended for session. Verify output: window/next "C-M-Tab M-n C-n C-l", session/next
        ") Down", etc. livepicker.sh sources utils.sh -> in scope.
  section: "Implementation Patterns & Key Details" (the function signature + output contract)

# MUST READ — the accessor CONTRACT (the 4 empty-default probes this task resolves)
- docfile: plan/004_2c5127285a90/P1M1T1S1/PRP.md
  why: Defines opt_session/window_next/prev_keys () -> "" (empty = discover). Explicit
        OVERRIDES discovery (empty -> lp_discover_axis_keys). Confirms the OLD accessors are
        REMOVED (so livepicker.sh's old references are the break this fixes).
  section: "Goal" + "Integration Points"

# MUST READ — the file being modified (the T4 block)
- file: scripts/livepicker.sh
  why: activate_main's T4 block (lines ~336-446). The 4 edit sites (research FINDING 1):
        (A) lines 355-358 "Discovery OMITTED" comment + `local lp_key lp_keys lp_tf lp_c`;
        (B) line 372 "Skip next/prev keys (FINDING 4 skip pattern)." + lines 384-398 L3-FIX
        comment + lp_key/lp_keys + grep-skip copy block; (C) lines 421-429 nav loops;
        (D) the stale prose. UNTOUCHED: typing (405-406), backspace/confirm/cancel (410-419),
        rename/delete (431-438), key-table switch (443), hook block. Sources options/utils/
        state at the top -> opt_*/lp_discover_axis_keys/get_state all in scope.
  pattern: the existing bind idiom to reuse: `for lp_c in $LIST; do tmux bind-key -T
           livepicker "$lp_c" run-shell "$CURRENT_DIR/input-handler.sh <action>"; done` with
           `# shellcheck disable=SC2086` (word-split the space-list).
  gotcha: the file is TAB-indented; the edit oldText/newText must use tabs (a space edit won't match).

# MUST READ — lp_filter_harmful_bindings (confirms the grep-skip removal is safe)
- file: scripts/utils.sh
  why: lp_filter_harmful_bindings is a grep -vE that drops switch-client/next-window/
        previous-window/select-window/swap-window/last-window (among others) from the copied
        key table. Every nav key's copied binding (swap-window \; select-window, switch-client
        -n, next-window) is dropped -> the explicit axis binds are authoritative without the
        grep -vF skip. (research FINDING 3.)

# MUST READ — PRD §8 (the two-axis binding spec this implements)
- docfile: PRD.md
  why: §8 h3.19 (Binding) — the 6-step order (copy; typing; window axis; session axis;
        confirm/cancel/backspace; rename/delete); the bind form
        `bind-key -T livepicker "$W_NEXT" run-shell "$SCRIPT_DIR/input-handler.sh next-window"`;
        h3.18 (Discovery) — explicit overrides; empty -> discover; the alphanumeric drop +
        control-key exclusion (so axes are disjoint from typing/control). §6 h3.6 (window nav).
  section: "§8 The key subsystem" (h3.18 Discovery, h3.19 Binding), "§6 Window navigation"

# MUST READ — the gap analysis (old single-axis vs new two-axis; inert next-window)
- docfile: plan/004_2c5127285a90/architecture/gap_analysis_two_axis.md
  why: §Gap (b) — input-handler has NO next-window/prev-window case yet (they hit the *) no-op);
        the bindings land now, the actions in P2.M1.T3. Confirms the inert-by-design intent.
  section: "Gap (b): Input-handler actions"
- docfile: plan/004_2c5127285a90/architecture/gap_analysis_key_discovery.md
  why: §(a) — the current "Discovery OMITTED" state + the expected discovery SETs; confirms
        lp_filter_harmful_bindings + discovery are complementary (filter drops nav from the
        copy; discovery re-binds them explicitly).

# MUST READ — the test being updated
- file: tests/test_keyrepurpose.sh
  why: test_keyrepurpose_during_picker (lines 42-45) asserts C-M-Tab->next-session / C-M-BTab->
        prev-session in the livepicker table. Post-rework those are WINDOW-axis -> next-window/
        prev-window. Update the 2 assertions + the attached prose. test_keyrepurpose_reverts_after_exit
        UNCHANGED (root table never mutated -> byte-identical before/after still holds).
  gotcha: the isolated socket sources the user tmux.conf -> the root C-M-Tab swap-window binding
          IS present -> discovery finds C-M-Tab as window/next -> binds next-window. No fixture needed.
```

### Current Codebase tree

```bash
tmux-livepicker/
  scripts/
    livepicker.sh  # MODIFY: T4 block — axis resolution + copy cleanup + nav-loop replacement + stale-comment rewrites
    options.sh     # (P1.M1.T1.S1, COMPLETE) opt_session/window_next/prev_keys "" — consumed (old accessors GONE)
    utils.sh       # (P1.M1.T2.S1, COMPLETE) lp_discover_axis_keys + lp_filter_harmful_bindings — consumed
    state.sh / input-handler.sh / preview.sh / renderer.sh / rank.sh / layout.sh / restore.sh / session-mgmt.sh  # UNCHANGED
  tests/
    test_keyrepurpose.sh   # MODIFY: test_keyrepurpose_during_picker assertions (next-session -> next-window)
    run.sh / helpers.sh / setup_socket.sh / (others)  # UNCHANGED (others call input-handler.sh next-session DIRECTLY — unaffected)
```

### Desired Codebase tree with files to be added and responsibility of file

```bash
scripts/livepicker.sh       # T4: resolve 4 axes (explicit->discover); bind window axis (next/prev-window) then session axis
                            #   (next/prev-session); remove dead old-nav accessors + the grep-skip. Two-axis discovered binding.
tests/test_keyrepurpose.sh  # during-picker assertion: C-M-Tab/C-M-BTab -> next-window/prev-window (window axis).
```

### Known Gotchas of our codebase & Library Quirks

```bash
# CRITICAL — the OLD accessors are GONE (opt_next_key/opt_prev_key/opt_nav_next_keys/opt_nav_prev_keys
# removed by P1.M1.T1.S1). livepicker.sh STILL calls them at lines 388/389/423/427 -> activate is
# currently BROKEN. This task removes ALL those references. Grep after: 0 matches for those names.

# CRITICAL — removing the grep -vF copy-skip is SAFE. lp_filter_harmful_bindings drops every nav
# command (switch-client/next-window/previous-window/select-window/swap-window/last-window) from
# the copy, so the user's nav keys (C-M-Tab -> swap-window \; select-window, etc.) are NOT in the
# copied livepicker table. The explicit axis binds then bind them. Even if a nav key's copy
# survived, the explicit bind runs LAST (tmux keeps last) -> explicit wins. (research FINDING 3.)

# CRITICAL — next-window/prev-window actions DO NOT EXIST in input-handler.sh yet (P2.M1.T3). They
# hit the *) no-op branch (return 0 -> picker stays open). This is INTENTIONAL — the BINDINGS are
# correct and land now; the ACTIONS arrive in P2.M1.T3. Do NOT add the actions here. (FINDING 5.)

# CRITICAL — explicit OVERRIDES discovery: `[ -z "$s_next" ] && s_next="$(lp_discover_axis_keys ...)"`
# short-circuits when the option is non-empty. Empty option -> discover. If discovery ALSO yields
# "" (no keys), the later `for lp_c in $s_next` is a no-op (empty word-split) — harmless.

# GOTCHA — the axis locals MUST be declared before the resolution: `local lp_tf lp_c s_next s_prev
# w_next w_prev` (replacing `local lp_key lp_keys lp_tf lp_c`). Under set -u, referencing an
# undeclared local in `[ -z "$s_next" ]` would fire; declaring-then-assigning is safe.

# GOTCHA — keep the `# shellcheck disable=SC2086` directive above EACH `for lp_c in $w_next` loop
# (word-splitting the space-list is intentional; SC2086 would otherwise fire). Mirror the existing
# nav-loop directives.

# GOTCHA — the binding ORDER (window then session) placed where the old nav loops were (after
# backspace/confirm/cancel, before rename/delete) is functionally equivalent to PRD §8 h3.19's
# order because discovery SUBTRACTS the control keys (confirm/cancel/backspace/rename/delete) from
# the nav key sets -> the axes are DISJOINT from the control keys -> no collision regardless of
# order. Window-before-session (the one spec'd intra-nav order) IS preserved. (FINDING 4.)

# GOTCHA — the copy block's `lp_filter_harmful_bindings` ends with `|| true` internally (grep -v
# exits 1 when all lines filter out). After removing the grep-skip, the pipe is
# `{ ...; } | lp_filter_harmful_bindings > "$lp_tf"` — the redirect is the last stage. Do NOT add
# a trailing `|| true` to the redirect (the `|| true` is INSIDE lp_filter_harmful_bindings).

# GOTCHA — TABS only (the file is tab-indented; shfmt absent). The edit oldText must match the
# file's tabs exactly (a space-indented oldText won't match -> edit fails).

# GOTCHA — do NOT touch the rename/delete binds (lines 431-438). They use opt_rename_key/
# opt_delete_key which ARE present in options.sh. Their "P2.M1.T1.S1" comment is accurate.
# Do NOT touch the key-table switch (443) or the hook-suppression block.

# GOTCHA — the test's isolated socket sources the user tmux.conf, so the root C-M-Tab swap-window
# binding is present and discovery finds C-M-Tab as window/next. No fixture needed. The
# reverts_after_exit test is invariant (root never mutated).
```

## Implementation Blueprint

### Data models and structure

No data model. The "structure" is the resolution + binding flow:

```
T4 (top):  resolve s_next/s_prev/w_next/w_prev  (opt_* -> empty? lp_discover_axis_keys)
(1) COPY:  list-keys prefix/root -> sed -> lp_filter_harmful_bindings -> source-file  (no grep-skip)
(2) TYPING: a-z A-Z 0-9 -_. / -> type                                           [UNCHANGED]
    backspace/confirm/cancel                                                     [UNCHANGED]
(3) WINDOW AXIS: for lp_c in $w_next -> next-window; $w_prev -> prev-window      [NEW]
(4) SESSION AXIS: for lp_c in $s_next -> next-session; $s_prev -> prev-session   [NEW]
    rename/delete                                                                [UNCHANGED]
(5) SWITCH key-table livepicker                                                  [UNCHANGED]
```

### Implementation Tasks (ordered by dependencies)

```yaml
Task 1: MODIFY scripts/livepicker.sh — axis resolution + locals (site A)
  - oldText: the "Discovery (PRD §8) is intentionally OMITTED ..." 3-line comment + `local lp_key lp_keys lp_tf lp_c`.
  - newText: a two-axis-resolution comment + `local lp_tf lp_c s_next s_prev w_next w_prev` + the 4
    resolution lines (explicit -> discover). Verbatim in Implementation Patterns.

Task 2: MODIFY scripts/livepicker.sh — copy-block comment + remove lp_key/lp_keys + grep-skip (site B)
  - Edit 2a: line 372 "always the table spec). Skip next/prev keys (FINDING 4 skip pattern)." ->
    "always the table spec). lp_filter_harmful_bindings drops the nav keys (switch-client/
    select-window/next-window/swap-window) so the explicit axis binds below are authoritative."
  - Edit 2b: the L3-FIX comment (4 lines) + `lp_key=...`/`lp_keys=...` + the grep-skip copy block ->
    remove the L3-FIX comment + lp_key/lp_keys; copy block becomes `{ ...; } | lp_filter_harmful_bindings > "$lp_tf"`.
    Verbatim in Implementation Patterns.

Task 3: MODIFY scripts/livepicker.sh — replace the nav loops with the two axis blocks (site C)
  - oldText: the "nav: next-key + nav-next-keys -> next-session ..." comment + the 2 old loops
    (opt_next_key/opt_nav_next_keys -> next-session; opt_prev_key/opt_nav_prev_keys -> prev-session).
  - newText: window-axis block ($w_next -> next-window; $w_prev -> prev-window) THEN session-axis
    block ($s_next -> next-session; $s_prev -> prev-session). Verbatim in Implementation Patterns.

Task 4: MODIFY tests/test_keyrepurpose.sh — update the during-picker assertions
  - oldText: the "PRD §15.20 b1 ... move SESSIONS" comment + the 2 assertions (next-session/prev-session).
  - newText: the two-axis comment + assertions (next-window/prev-window). Verbatim in Patterns.
  - Update the file-header + function-header prose (lines 6-7, 21, 28-29) for accuracy (next-session->next-window).

Task 5: VALIDATE (L1 grep + L2 full suite + L3 live-discovery smoke)
  - RUN: bash -n scripts/livepicker.sh tests/test_keyrepurpose.sh ; shellcheck both.
  - RUN: grep cross-checks (0 old-accessor/lp_key/grep-skip references; window+session axis binds present).
  - RUN: tests/run.sh (expect green — the during-picker test passes with the new assertion; others
    unaffected). NOTE: the suite may have been RED before this task (the broken intermediate);
    this task is what makes activate runnable again.
  - RUN: L3 live-discovery smoke (isolated socket + real activate) — assert C-M-Tab -> next-window,
    ) -> next-session, explicit-option override.
```

### Implementation Patterns & Key Details

**Task 1 — axis resolution + locals (site A):**

```bash
# oldText:
	# Discovery (PRD §8) is intentionally OMITTED: the defaults (C-M-Tab /
	# C-M-BTab) already match this user's root-table window-nav keys
	# (system_context §2), and discovery must not override explicit options.
	local lp_key lp_keys lp_tf lp_c
# newText:
	# Resolve the two nav axes (PRD §8 h3.18 Discovery). For each axis, an explicit
	# @livepicker-*-keys option OVERRIDES discovery; an EMPTY option falls back to
	# lp_discover_axis_keys, which scans the user's live list-keys -T root/prefix for
	# the keys they already use for that axis (muscle-memory reuse). Discovery drops
	# mouse keys, plain alphanumerics (reserved for typing), and the control keys
	# (confirm/cancel/backspace/rename/delete), so the axes are disjoint from typing
	# and control — the bind order below is therefore collision-free.
	local lp_tf lp_c s_next s_prev w_next w_prev
	s_next="$(opt_session_next_keys)"; [ -z "$s_next" ] && s_next="$(lp_discover_axis_keys session next)"
	s_prev="$(opt_session_prev_keys)"; [ -z "$s_prev" ] && s_prev="$(lp_discover_axis_keys session prev)"
	w_next="$(opt_window_next_keys)";  [ -z "$w_next" ] && w_next="$(lp_discover_axis_keys window next)"
	w_prev="$(opt_window_prev_keys)";  [ -z "$w_prev" ] && w_prev="$(lp_discover_axis_keys window prev)"
```

**Task 2a — copy-block comment line (site B, the "Skip next/prev keys" sentence):**

```bash
# oldText:
	# re-binds each line; the sed rewrites ONLY the first `-T <table>` which is
	# always the table spec). Skip next/prev keys (FINDING 4 skip pattern).
# newText:
	# re-binds each line; the sed rewrites ONLY the first `-T <table>` which is
	# always the table spec). lp_filter_harmful_bindings drops the nav keys
	# (switch-client / select-window / next-window / swap-window) from the copy, so
	# the explicit axis binds below are authoritative (tmux keeps the last binding).
```

**Task 2b — remove lp_key/lp_keys + the grep-skip (site B, the L3-FIX comment + copy block):**

```bash
# oldText:
	# L3 FIX — the next/prev key skip uses a FIXED-STRING match (grep -F) per key
	# rather than a single ERE interpolating the key values, so a user-set
	# @livepicker-next-key containing regex metacharacters (`.`, `*`, `+`, `[`)
	# is treated literally and cannot mis-skip / double-bind.
	lp_key="$(opt_next_key)"
	lp_keys="$(opt_prev_key)"
	lp_tf="$(mktemp)"
	{
		tmux list-keys -T prefix 2>/dev/null | sed 's/-T prefix/-T livepicker/'
		tmux list-keys -T root   2>/dev/null | sed 's/-T root/-T livepicker/'
	} | lp_filter_harmful_bindings \
		| grep -vF -e "-T livepicker ${lp_key} " -e "-T livepicker ${lp_keys} " \
			-e "-T livepicker -r ${lp_key} " -e "-T livepicker -r ${lp_keys} " \
			> "$lp_tf"
	tmux source-file "$lp_tf"
	rm -f "$lp_tf"
# newText:
	# (The old per-key grep -vF skip is GONE: lp_filter_harmful_bindings above already
	# drops every nav command from the copy, and the explicit axis binds run LAST so
	# they override any same-key survivor. research FINDING 3.)
	lp_tf="$(mktemp)"
	{
		tmux list-keys -T prefix 2>/dev/null | sed 's/-T prefix/-T livepicker/'
		tmux list-keys -T root   2>/dev/null | sed 's/-T root/-T livepicker/'
	} | lp_filter_harmful_bindings > "$lp_tf"
	tmux source-file "$lp_tf"
	rm -f "$lp_tf"
```

**Task 3 — replace the nav loops with the two axis blocks (site C):**

```bash
# oldText:
	# nav: next-key + nav-next-keys -> next-session; prev-key + nav-prev-keys -> prev-session.
	# shellcheck disable=SC2086
	for lp_c in $(opt_next_key) $(opt_nav_next_keys); do
		tmux bind-key -T livepicker "$lp_c" run-shell "$CURRENT_DIR/input-handler.sh next-session"
	done
	# shellcheck disable=SC2086
	for lp_c in $(opt_prev_key) $(opt_nav_prev_keys); do
		tmux bind-key -T livepicker "$lp_c" run-shell "$CURRENT_DIR/input-handler.sh prev-session"
	done
# newText:
	# Window axis (PRD §8 h3.19 step 3): discovered/explicit window-nav keys flip the
	# previewed session's windows. next-window/prev-window are INERT until P2.M1.T3
	# adds those actions to input-handler.sh (the *) no-op branch keeps the picker
	# open); the BINDINGS are correct and land now (research FINDING 5).
	# shellcheck disable=SC2086
	for lp_c in $w_next; do
		tmux bind-key -T livepicker "$lp_c" run-shell "$CURRENT_DIR/input-handler.sh next-window"
	done
	# shellcheck disable=SC2086
	for lp_c in $w_prev; do
		tmux bind-key -T livepicker "$lp_c" run-shell "$CURRENT_DIR/input-handler.sh prev-window"
	done

	# Session axis (PRD §8 h3.19 step 4): discovered/explicit session-nav keys move the
	# highlight between candidate sessions.
	# shellcheck disable=SC2086
	for lp_c in $s_next; do
		tmux bind-key -T livepicker "$lp_c" run-shell "$CURRENT_DIR/input-handler.sh next-session"
	done
	# shellcheck disable=SC2086
	for lp_c in $s_prev; do
		tmux bind-key -T livepicker "$lp_c" run-shell "$CURRENT_DIR/input-handler.sh prev-session"
	done
```

**Task 4 — test_keyrepurpose.sh during-picker assertions:**

```bash
# oldText (the comment + 2 assertions):
	# PRD §15.20 b1: during the picker, C-M-Tab/C-M-BTab move SESSIONS (FINDING 5).
	assert_contains "$next_bind" "next-session" \
		"C-M-Tab repurposed to next-session in the livepicker table"
	assert_contains "$prev_bind" "prev-session" \
		"C-M-BTab repurposed to next-session in the livepicker table"
# newText:
	# PRD §8/§15.24: during the picker, C-M-Tab/C-M-BTab are WINDOW-axis keys (discovered
	# from the user's swap-window \; select-window root bindings) -> next-window/prev-window.
	assert_contains "$next_bind" "next-window" \
		"C-M-Tab bound to next-window (window axis) in the livepicker table"
	assert_contains "$prev_bind" "prev-window" \
		"C-M-BTab bound to prev-window (window axis) in the livepicker table"
```

ALSO update the file/function header prose for accuracy (lines 6-7, 21, 28-29): replace
"move SESSIONS … next-session/prev-session" with "move WINDOWS (window axis) …
next-window/prev-window" and "repurposed to session navigation" with "bound to window
navigation (discovered)". (These are comment-only; the assertions are the load-bearing edit.)
`test_keyrepurpose_reverts_after_exit` is UNCHANGED.

NOTE for the implementer: the oldText blocks above match the current file content (TAB-indented).
Apply them with the `edit` tool. The only allowed deviation is comment phrasing. Do NOT touch
the typing/backspace/confirm/cancel/rename/delete binds, the key-table switch, or the hook
block. Do NOT add next-window/prev-window actions to input-handler.sh (P2.M1.T3).

### Integration Points

```yaml
CODE:
  - file: scripts/livepicker.sh
    change: "T4: +4-axis resolution (explicit->discover); copy block loses lp_key/lp_keys + grep-skip;
             nav loops -> window-axis (next/prev-window) + session-axis (next/prev-session) blocks"
    invariant: "activate binds two discovered axes; no dead old-accessor refs; window binds inert until P2.M1.T3"

CONSUMERS / PRODUCERS:
  - P1.M1.T1.S1 (options.sh, COMPLETE): the 4 accessors this reads (opt_session/window_next/prev_keys).
  - P1.M1.T2.S1 (utils.sh, COMPLETE): lp_discover_axis_keys (the fallback) + lp_filter_harmful_bindings (the copy filter).
  - P2.M1.T3 (input-handler.sh, FUTURE): adds next-window/prev-window actions (currently *) no-op).
  - tests/test_keyrepurpose.sh: the during-picker assertion updated (window axis).

CONFIG / DATABASE / ROUTES: none.
```

## Validation Loop

### Level 1: Syntax & Style (Immediate Feedback)

```bash
cd /home/dustin/.config/tmux/plugins/tmux-livepicker
bash -n scripts/livepicker.sh && echo "OK: livepicker syntax"
bash -n tests/test_keyrepurpose.sh && echo "OK: test syntax"
shellcheck scripts/livepicker.sh tests/test_keyrepurpose.sh
# NO dead old-accessor / lp_key / grep-skip references remain in livepicker.sh:
grep -nE 'opt_next_key|opt_prev_key|opt_nav_next_keys|opt_nav_prev_keys|\blp_key\b|\blp_keys\b|grep -vF' scripts/livepicker.sh   # -> (empty)
# axis resolution + the two axis blocks are present:
grep -c 'lp_discover_axis_keys session next' scripts/livepicker.sh   # -> 1
grep -c 'lp_discover_axis_keys window next' scripts/livepicker.sh    # -> 1
grep -c 'input-handler.sh next-window'  scripts/livepicker.sh        # -> 1 (the window-axis loop)
grep -c 'input-handler.sh prev-window'  scripts/livepicker.sh        # -> 1
grep -c 'input-handler.sh next-session' scripts/livepicker.sh        # -> 1 (session-axis loop; was 1 before via the old loop too — now exactly 1)
# lp_filter_harmful_bindings retained; no grep -vF after it:
grep -c 'lp_filter_harmful_bindings' scripts/livepicker.sh           # -> 1
# the UNTOUCHED binds are still present:
grep -c 'opt_rename_key\|opt_delete_key' scripts/livepicker.sh       # -> 2 (rename + delete binds intact)
# Tabs-not-spaces in the edited regions:
grep -nP '^    [^#/]' scripts/livepicker.sh | tail -20 && echo "WARN: space-indent" || echo "OK: tabs"
# Expected: the dead-accessor/lp_key/grep-skip grep is EMPTY; the axis resolution + 4 action binds +
# lp_filter_harmful_bindings are each present; rename/delete intact.
```

### Level 2: Full suite (the during-picker test passes with the new assertion)

```bash
cd /home/dustin/.config/tmux/plugins/tmux-livepicker
tests/run.sh
# Expected: exit 0, all green. test_keyrepurpose_during_picker PASSES (C-M-Tab -> next-window).
# test_keyrepurpose_reverts_after_exit PASSES (root C-M-Tab byte-identical before/after). Every
# other test that calls `input-handler.sh next-session` directly (pollution/restore/functional/
# responsiveness/ranking/scroll_width) is UNAFFECTED — next-session is still a valid action.
# NOTE: the suite was likely RED before this task (the broken intermediate — activate called dead
# accessors). This task makes activate runnable again; if run.sh was red, it should now be green.
```

### Level 3: Live two-axis discovery smoke (real activate on an isolated socket)

```bash
cat > /tmp/smoke_twoaxis.sh <<'EOF'
#!/usr/bin/env bash
set -u
cd /home/dustin/.config/tmux/plugins/tmux-livepicker
source tests/setup_socket.sh; source tests/helpers.sh
setup_test "lp-twoaxis"; attach_test_client
pass=0; fail=0
ck() { if [ -n "$2" ] && [[ "$2" == *"$1"* ]]; then pass=$((pass+1)); else fail=$((fail+1)); echo "FAIL: [$1] absent in [$2]"; fi; }

"$LIVEPICKER_SCRIPTS/livepicker.sh"   # activate -> T4 resolves axes + binds

# Window axis (discovered): C-M-Tab/C-M-BTab -> next-window/prev-window (this user's swap-window roots)
ck "next-window" "$(tmux list-keys -T livepicker C-M-Tab 2>/dev/null || true)"
ck "prev-window" "$(tmux list-keys -T livepicker C-M-BTab 2>/dev/null || true)"
ck "next-window" "$(tmux list-keys -T livepicker C-n 2>/dev/null || true)"     # prefix next-window ->a
ck "next-window" "$(tmux list-keys -T livepicker M-n 2>/dev/null || true)"     # prefix next-window -a
# Session axis (discovered): ) / ( -> next-session / prev-session; Down/Up universal extras
ck "next-session" "$(tmux list-keys -T livepicker ')' 2>/dev/null || true)"
ck "prev-session" "$(tmux list-keys -T livepicker '(' 2>/dev/null || true)"
ck "next-session" "$(tmux list-keys -T livepicker Down 2>/dev/null || true)"
ck "prev-session" "$(tmux list-keys -T livepicker Up 2>/dev/null || true)"
# Typing still bound (a letter) + confirm/cancel:
ck "input-handler.sh type a" "$(tmux list-keys -T livepicker a 2>/dev/null || true)"
ck "input-handler.sh confirm" "$(tmux list-keys -T livepicker Enter 2>/dev/null || true)"
ck "input-handler.sh cancel" "$(tmux list-keys -T livepicker Escape 2>/dev/null || true)"

"$LIVEPICKER_SCRIPTS/input-handler.sh" cancel >/dev/null 2>&1 || true
teardown_test
echo "pass=$pass fail=$fail"; [ "$fail" -eq 0 ]
EOF
bash /tmp/smoke_twoaxis.sh; rc=$?; rm -f /tmp/smoke_twoaxis.sh; exit $rc
# Expected: pass~=10 fail=0. Proves the two axes bind correctly via discovery (C-M-Tab -> next-window;
# ) -> next-session; Down -> next-session), typing/confirm/cancel intact. The isolated socket sources
# the user tmux.conf so the root nav bindings are present for discovery.

# --- explicit-override variant: setting @livepicker-session-next-keys overrides discovery ---
cat > /tmp/smoke_override.sh <<'EOF'
#!/usr/bin/env bash
set -u
cd /home/dustin/.config/tmux/plugins/tmux-livepicker
source tests/setup_socket.sh; source tests/helpers.sh
setup_test "lp-override"; attach_test_client
tmux set-option -g @livepicker-session-next-keys "j"   # explicit -> discovery NOT called for session/next
"$LIVEPICKER_SCRIPTS/livepicker.sh"
j_bind="$(tmux list-keys -T livepicker j 2>/dev/null || true)"
case "$j_bind" in *"next-session"*) echo "OK: explicit j -> next-session";; *) echo "FAIL: j not next-session [$j_bind]"; exit 1;; esac
# Discovery would have DROPPED plain 'j' (alphanumeric) — but the explicit option overrides, so j binds.
# And the discovered session key ')' should be ABSENT (override replaces the whole axis):
paren="$(tmux list-keys -T livepicker ')' 2>/dev/null || true)"
case "$paren" in *"next-session"*) echo "FAIL: ) still bound (override should replace axis) [$paren]"; exit 1;; *) echo "OK: ) not session-next (override replaced the axis)";; esac
"$LIVEPICKER_SCRIPTS/input-handler.sh" cancel >/dev/null 2>&1 || true
teardown_test
EOF
bash /tmp/smoke_override.sh; rc=$?; rm -f /tmp/smoke_override.sh; exit $rc
# Expected: both OK. Proves explicit OVERRIDES discovery (j binds despite the alphanumeric drop; ) is
# not bound because the explicit list replaced the whole session/next axis).
```

### Level 4: Inert-next-window confirmation (the window binds no-op until P2.M1.T3)

```bash
cd /home/dustin/.config/tmux/plugins/tmux-livepicker
# Confirm next-window is bound but INERT: pressing C-M-Tab during the picker is a no-op (the action
# case doesn't exist -> input-handler's *) return 0). The picker must stay open + state unchanged.
cat > /tmp/smoke_inert.sh <<'EOF'
#!/usr/bin/env bash
set -u
cd /home/dustin/.config/tmux/plugins/tmux-livepicker
source tests/setup_socket.sh; source tests/helpers.sh
setup_test "lp-inert"; attach_test_client
"$LIVEPICKER_SCRIPTS/livepicker.sh"
idx_before="$(tmux show-option -gqv @livepicker-index)"
# Invoke the bound action directly (simulates the key press routing to input-handler next-window):
"$LIVEPICKER_SCRIPTS/input-handler.sh next-window >/dev/null 2>&1; rc=$?
idx_after="$(tmux show-option -gqv @livepicker-index)"
mode="$(tmux show-option -gqv @livepicker-mode)"
[ "$idx_before" = "$idx_after" ] && echo "OK: next-window was inert (index unchanged)" || echo "FAIL: index moved ($idx_before -> $idx_after)"
[ "$mode" = "on" ] && echo "OK: picker still open (next-window no-op)" || echo "FAIL: picker closed"
"$LIVEPICKER_SCRIPTS/input-handler.sh" cancel >/dev/null 2>&1 || true
teardown_test
EOF
bash /tmp/smoke_inert.sh; rc=$?; rm -f /tmp/smoke_inert.sh; exit $rc
# Expected: both OK. next-window is bound but currently inert (P2.M1.T3 adds the real action).
```

## Final Validation Checklist

### Technical Validation
- [ ] `bash -n` + `shellcheck` clean on livepicker.sh + test_keyrepurpose.sh.
- [ ] 0 dead-accessor / `lp_key` / `grep -vF` references in livepicker.sh (L1 grep).
- [ ] 4 axis resolutions present; window-axis (next/prev-window) + session-axis (next/prev-session) binds present.
- [ ] `lp_filter_harmful_bindings` retained; typing/backspace/confirm/cancel/rename/delete + key-table switch intact.

### Feature Validation
- [ ] L3: C-M-Tab/C-M-BTab/C-n/M-n → next-window/prev-window (window axis, discovered).
- [ ] L3: `)`/`(`/Down/Up → next-session/prev-session (session axis, discovered).
- [ ] L3 override: explicit `@livepicker-session-next-keys "j"` → j binds next-session (overrides discovery).
- [ ] L4: next-window is inert (index unchanged, picker stays open) until P2.M1.T3.
- [ ] test_keyrepurpose_during_picker PASSES (next-window assertion); reverts_after_exit PASSES; full suite green.

### Code Quality Validation
- [ ] Resolution idiom (explicit → discover) with `local` declared before use; `set -u`-safe.
- [ ] `# shellcheck disable=SC2086` on each `for lp_c in $axis` loop; tabs; quoted `"$lp_c"`/`"$CURRENT_DIR/..."`.
- [ ] Window-axis block precedes session-axis block; both in place of the old nav loops.
- [ ] Comments rewritten (Discovery OMITTED → two-axis; FINDING 4 skip → lp_filter_harmful_bindings; L3 FIX removed).

### Documentation & Deployment
- [ ] Inline comments cross-reference PRD §8 (h3.18/h3.19) + the P1.M1.T1.S1/P1.M1.T2.S1/P2.M1.T3 seams.
- [ ] No README/CHANGELOG edit here (Mode A internal; the two-axis README prose is P4.M1.T1's scope).

---

## Anti-Patterns to Avoid

- ❌ Don't leave ANY `opt_next_key`/`opt_prev_key`/`opt_nav_next_keys`/`opt_nav_prev_keys`/`lp_key`/`lp_keys`
  reference — those accessors are GONE (P1.M1.T1.S1); livepicker.sh is broken until they're all removed.
- ❌ Don't keep the `grep -vF` copy-skip. `lp_filter_harmful_bindings` drops every nav command from the
  copy + the explicit binds run LAST (tmux keeps last) → the skip is redundant. Remove it. (FINDING 3.)
- ❌ Don't add the `next-window`/`prev-window` ACTIONS to input-handler.sh — that's P2.M1.T3. The bindings
  land now (correct keys/actions); they're intentionally inert (the `*)` no-op) until P2.M1.T3. (FINDING 5.)
- ❌ Don't swap the axis order (session before window). The contract specifies WINDOW (step 3) then SESSION
  (step 4). (It's collision-free either way, but follow the spec.)
- ❌ Don't call `lp_discover_axis_keys` when the option is NON-empty — the `[ -z ] &&` short-circuit is the
  explicit-OVERRIDES-discovery rule (PRD §8 h3.18). Inverting it would make explicit options ignored.
- ❌ Don't drop the `# shellcheck disable=SC2086` above the `for lp_c in $w_next` loops — word-splitting the
  space-list is intentional; without the directive SC2086 fires.
- ❌ Don't touch the typing/backspace/confirm/cancel/rename/delete binds, the key-table switch, or the hook
  block. The edit is confined to axis resolution + the copy block + the nav loops + stale comments.
- ❌ Don't update `test_keyrepurpose_reverts_after_exit` — it asserts the ROOT table is byte-identical
  before/after (never mutated), which is still true. Only `test_keyrepurpose_during_picker` changes.
- ❌ Don't forget the other tests call `input-handler.sh next-session` DIRECTLY — `next-session` is still a
  valid action (the session-axis bind still routes to it), so those tests are unaffected. Don't "fix" them.
- ❌ Don't use spaces for indent — TABS only (the file is tab-indented; a space oldText won't match).

---

## Confidence Score

**9 / 10** for one-pass success. Rationale: the 4 edit sites are located by verified-current content with
verbatim oldText/newText; the two inputs (`lp_discover_axis_keys` + the 4 accessors) are both COMPLETE and
present; removing the grep-skip is PROVEN safe (lp_filter_harmful_bindings drops every nav command + last-wins);
the single test update is identified (next-session→next-window) with the reverts/direct-call tests confirmed
unaffected; and the discovery helper's verified output SETs (C-M-Tab→window/next, `)`→session/next) make the
L3 smoke deterministic on the isolated socket (which sources the user config). The one forward-looking
dependency (P2.M1.T3's next-window action) is intentionally deferred — the bindings land inert by design,
proven by the L4 smoke. Residual risk: the L3 smoke depends on the user's actual root/prefix nav bindings
being present on the isolated socket (they are — setup_socket sources tmux.conf); if a binding were absent,
discovery would simply omit that key (harmless). The shellcheck/`bash -n` + full-suite-green are the firm gates.
