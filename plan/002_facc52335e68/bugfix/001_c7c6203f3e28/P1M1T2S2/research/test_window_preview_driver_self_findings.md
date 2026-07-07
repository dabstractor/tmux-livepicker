# Test: Window-mode driver-owned-window preview — empirical grounding (tmux 3.6b)

> Verified LIVE on 2026-07-07 against the isolated `-L` socket harness
> (`tests/setup_socket.sh` + `tests/helpers.sh`), the SAME harness `run.sh` uses.
> This research PROVES the new test function passes against the FIXED preview.sh
> (S1/P1.M1.T2.S1 applied — `check_session` + window-mode-aware self-session guard)
> and FAILS against the buggy behavior (the regression it must catch).

## Environment

| Tool | Version |
|---|---|
| tmux | **3.6b** |
| isolated-socket config | `base-index=1`, `renumber-windows=on` (inherited from ~/.tmux.conf) |
| preview.sh | the FIXED build (S1 landed: `check_session` local + `${S%%:*}` guard + mode-branched select) |

## Driver baseline state after `setup_socket` (load-bearing — do NOT assume @ids)

`tests/setup_socket.sh` creates `driver` then `new-window -t driver -n extra` +
splits. The resulting driver window list is **non-sequential in @id** (alpha/beta
and their splits consume ids in between):

```
1:zsh(id=@0,active=0)      # original window — NON-active after 'extra' was created
2:extra(id=@3,active=1)    # the 'extra' window — ACTIVE (new-window makes it active)
```

**CRITICAL gotcha**: the driver's two windows are `@0` and `@3` — NOT `@0`/`@1`.
So the test MUST detect the target window's `#{window_id}` DYNAMICALLY (hard-coding
`@1` would be wrong). The `extra` window is the ACTIVE one, so
`lp_preview_seed_state` sets `@livepicker-orig-window` = `@3` (extra's id).

`base-index=1` means the original window sits at index **1** (not 0). The
contract's literal `"$TEST_DRIVER_SESSION:1"` token resolves to the original
window here — but a base-index-agnostic test detects the index dynamically (the
sibling `test_window_preview_shows_highlighted_window` does exactly this).

## FINDING 1 — The test passes against the FIXED preview.sh (5/5)

Replicated the new test body via the harness (sourced setup_socket + helpers +
ran `setup_test`). Previewed the DRIVER's NON-active window token
(`driver:1` → window `@0`):

```
BEFORE:  1:zsh(@0,non-active)  2:extra(@3,active)   ids=[@0 @3] n=2
preview.sh "driver:1"   ->  guard fires (check_session=driver == current_session)
AFTER:   1:zsh(@0,ACTIVE)      2:extra(@3,non-active)  ids=[@0 @3] n=2
```

All 5 assertions PASS:
| # | assertion | got | want | result |
|---|-----------|-----|------|--------|
| 1 | `@livepicker-linked-id` EMPTY | `` | `` | PASS |
| 2 | window-id list unchanged | `@0\n@3` | `@0\n@3` | PASS |
| 3 | window count unchanged | 2 | 2 | PASS |
| 4 | no duplicate `@id` (`sort \| uniq -d` empty) | `` | `` | PASS |
| 5 | correct window selected (active == target id) | `@0` | `@0` | PASS |

`pass=5 fail=0`. The guard selects the target (`@0`) WITHOUT linking — the active
window changed from extra(`@3`) to the original(`@0`), proving `select-window` fired.

## FINDING 2 — The assertions are load-bearing (they FAIL on the bug)

Without modifying preview.sh, I replicated the buggy guard's effect directly:
`tmux link-window -s "@0" -t "driver:"` (the exact call the unfixed guard falls
through to — it silently creates a DUPLICATE, rc=0):

```
BEFORE:  ids=[@0 @3] n=2
tmux link-window -s @0 -t driver:   ->  rc=0  (DUPLICATE created)
AFTER:   1:zsh(@0)  2:extra(@3)  3:zsh(@0)   ids=[@0 @3 @0] n=3   uniq -d=[@0]
```

The SAME 3 "no duplicate" assertions now FAIL (the other 2 are not applicable
to the raw simulation):
| assertion | got | want | result |
|-----------|-----|------|--------|
| window-id list unchanged | `@0\n@3\n@0` | `@0\n@3` | **FAIL** |
| window count unchanged | 3 | 2 | **FAIL** |
| no duplicate `@id` (`uniq -d`) | `@0` | `` | **FAIL** |

`pass=0 fail=3`. This PROVES the test would catch a regression that reverts the
guard to the bare `[ "$S" = "$current_session" ]` comparison (Issue 2). The test
is not vacuous: it fails loudly the moment a driver-owned window gets linked.

## FINDING 3 — Why the test must NOT need a client

`preview.sh` is CLIENT-INDEPENDENT (reads `current_session` from
`@livepicker-orig-session`, NOT `display-message`). So `lp_preview_seed_state`
suffices — NO `attach_test_client`. This mirrors `test_self_session_no_link` and
`test_window_preview_shows_highlighted_window` exactly (both are client-free).
Confirmed: the smoke ran with no attached client and resolved everything via
bare `tmux` on the isolated socket.

## FINDING 4 — Dynamic index detection is mandatory (house style + correctness)

The target index is read from `list-windows -F '#{window_index} #{window_id}
#{window_active}' | awk '$3==0 {...}'` — the EXACT idiom the sibling
`test_window_preview_shows_highlighted_window` uses for its foreign `multi`
session. Reasons it is mandatory here:
1. `base-index` is inherited from `~/.tmux.conf` (1 here; could be 0 elsewhere) —
   hard-coding `:1` is fragile.
2. The driver's `@id`s are non-sequential (`@0`, `@3`), so the target id MUST be
   captured dynamically (assertion #5 compares against it).
3. Picking the NON-active window makes assertion #5 meaningful: the active window
   CHANGES to the target, proving `select-window -t "$S"` fired (if it picked the
   already-active window, the assertion would pass trivially).

Sanity guards: assert the target `@id` contains `@` (proves detection worked), and
`return 0` early with a `fail` if no non-active window exists (bad baseline) —
matches the sibling test's `na_id == active_id` loud-fail guard.

## FINDING 5 — The 3 "no duplicate" checks are complementary, not redundant

The contract asks to "count windows, verify unique ids". Three checks cover the
invariant from different angles (belt-and-braces — all must pass):
1. **window-id list byte-equality** (`before_ids == after_ids`) — catches ANY
   change (a duplicate appends a line; the lists differ). The strongest single
   check.
2. **window count** (`before_n == after_n`) — the contract's literal "count
   windows". A duplicate raises the count.
3. **unique ids** (`sort | uniq -d` must be empty) — the contract's "verify
   unique ids". Catches a duplicate even if tmux ever reordered the list (it
   doesn't, but this is the explicit uniqueness proof).

All three fail together under the bug (FINDING 2); all pass together under the
fix (FINDING 1). They are cheap (one `list-windows` each) and make the intent
unambiguous to a future reader.

## The exact test function to APPEND to tests/test_preview.sh

Mirrors `test_self_session_no_link` (session-mode counterpart) in structure and
assertion style, and `test_window_preview_shows_highlighted_window` (dynamic
index detection). Function name per the work-item contract:
`test_window_preview_driver_self_no_duplicate`.

```bash
# test_window_preview_driver_self_no_duplicate — Bugfix Issue 2 (window mode):
# previewing a window that LIVES in the driver (current) session must NOT link it
# (a session cannot usefully link its own window into itself — link-window would
# silently create a DUPLICATE, rc=0). The self-session guard must fire for the
# "session:index" token, select the target window, and leave the driver's window
# list byte-identical (no duplicate @id). This is the window-mode counterpart of
# test_self_session_no_link (session mode). Before S1/P1.M1.T2.S1, the guard's
# bare `[ "$S" = "$current_session" ]` never matched the "driver:N" token, so
# preview fell through to link-window and polluted the list — this test catches
# that regression. Mirrors the dynamic-index detection of
# test_window_preview_shows_highlighted_window (base-index may be 0 or 1;
# @ids are non-sequential — @0 and @3 here — so detect dynamically).
test_window_preview_driver_self_no_duplicate() {
	lp_preview_seed_state
	# Window mode: the self-session guard's window-mode branch gates on opt_type
	# (lp_preview_seed_state does NOT set type — set it explicitly).
	tmux set-option -g @livepicker-type window
	# Pick a DRIVER-OWNED window token. The baseline driver has ≥2 windows
	# (original + 'extra'); detect the NON-active one dynamically so the
	# "correct window selected" assertion is meaningful (selection changes) and
	# base-index-agnostic (the index comes straight from list-windows). @ids are
	# clean @N, so space-delimit to avoid any ':' ambiguity.
	local target target_idx target_id before_ids before_n
	target="$(tmux list-windows -t "=$TEST_DRIVER_SESSION" -F '#{window_index} #{window_id} #{window_active}' | awk '$3==0 {print $1" "$2; exit}')"
	target_idx="${target%% *}"
	target_id="${target#* }"
	assert_contains "$target_id" "@" "non-active driver window resolved to a @id handle"
	if [ -z "$target_idx" ] || [ -z "$target_id" ]; then
		fail "test setup invalid: no non-active driver window (need ≥2 driver windows)"
		return 0
	fi
	# Snapshot the driver's window list BEFORE (ids + count).
	before_ids="$(tmux list-windows -t "=$TEST_DRIVER_SESSION" -F '#{window_id}')"
	before_n="$(tmux list-windows -t "=$TEST_DRIVER_SESSION" -F '#{window_id}' | wc -l | tr -d '[:space:]')"
	# Preview the DRIVER's own window (window-mode token). The self-session guard
	# must fire (check_session = ${S%%:*} = "driver" = current_session) -> select
	# the target, NO link, NO duplicate.
	"$LIVEPICKER_SCRIPTS/preview.sh" "$TEST_DRIVER_SESSION:$target_idx"
	# (1) PRD §7 self-session: NO link attempted -> @livepicker-linked-id is EMPTY.
	assert_eq "$(tmux show-option -gqv @livepicker-linked-id)" "" \
		"window-mode self-session leaves @livepicker-linked-id empty (no link)"
	# (2) NO duplicate @id: the window-id list is unchanged (catches ANY change),
	#     the count is unchanged, AND every id is unique (sort | uniq -d empty).
	assert_eq "$(tmux list-windows -t "=$TEST_DRIVER_SESSION" -F '#{window_id}')" "$before_ids" \
		"window-mode self-session created no duplicate (window-id list unchanged)"
	local after_n dups
	after_n="$(tmux list-windows -t "=$TEST_DRIVER_SESSION" -F '#{window_id}' | wc -l | tr -d '[:space:]')"
	assert_eq "$after_n" "$before_n" "driver window count unchanged (no duplicate link added)"
	dups="$(tmux list-windows -t "=$TEST_DRIVER_SESSION" -F '#{window_id}' | sort | uniq -d)"
	assert_eq "$dups" "" "no duplicate @id entries in the driver window list"
	# (3) PRD §7: the CORRECT window was selected (active == the token's window),
	#     not a duplicate occupying a shifted index.
	assert_eq "$(tmux list-windows -t "=$TEST_DRIVER_SESSION" -F '#{window_id}' -f '#{window_active}')" "$target_id" \
		"window-mode self-session selects the highlighted (token's) window, not a duplicate"
}
```

## Run command (validation)

```bash
cd /home/dustin/.config/tmux/plugins/tmux-livepicker
bash tests/run.sh   # the new test is auto-discovered (compgen ^test_); expect it PASS
# targeted re-run of just preview tests is not natively supported by run.sh (it
# runs all test_*); run.sh is the single entry point. Full suite must stay green.
```
