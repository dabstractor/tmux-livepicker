# Research Findings — P1.M7.T6.S1 (restore + key-repurpose + create-on-enter tests)

> All findings below were verified LIVE on an isolated `tmux -L` socket (tmux
> 3.6b) on 2026-07-06, by sourcing `tests/setup_socket.sh` + `tests/helpers.sh`
> and driving the COMPLETE real plugin (`scripts/livepicker.sh` →
> `input-handler.sh` → `preview.sh` → `restore.sh`). Probes:
> `/tmp/probe_t6.sh` (restore/keyrepurpose/create-on) + `/tmp/probe_t6b.sh`
> (create-off/window-mode/prev-key). Every "✓" below is a real observed value.

---

## FINDING 1 — The isolated server sources the user tmux.conf → the root-table
            C-M-Tab / C-M-BTab window-nav bindings ARE present (the key-repurpose
            precondition), AND the dormant §11 config IS present (the restore
            "grep" trap). Confirmed identical to test_functional.sh FINDING 2.

`setup_socket` starts the isolated server with `tmux new-session -d -s driver`;
a fresh tmux server sources `~/.config/tmux/tmux.conf`. Observed on the isolated
socket AFTER `setup_test`:

```
[C-M-Tab in root]:
bind-key -T root C-M-Tab swap-window -t +1 \; select-window -t +1
[C-M-BTab in root]:
bind-key -T root C-M-BTab swap-window -t -1 \; select-window -t -1
[rc of list-keys -T root C-M-Tab]: 0
```

and the dormant config (PRD §11, pre-declared in tmux.conf):

```
@livepicker-fg "#ffffff"
@livepicker-key Space
```

Implications:
- **Key-repurpose tests have their precondition for free**: the root-table
  `C-M-Tab`/`C-M-BTab` bindings exist before activate (no fixture needed).
- **The restore "grep" trap (FINDING 2)**: the dormant `@livepicker-fg`/
  `@livepicker-key` REMAIN after cancel (clear_all_state preserves §11 config —
  CORRECTION A in state.sh). So the literal contract clause "assert
  `show-options -g | grep livepicker` is empty" FALSE-FAILS. Use the
  byte-identical snapshot (FINDING 3) instead.

## FINDING 2 — THE "grep livepicker" TRAP (the single most likely false-fail).

After a clean activate → nav → cancel, observed:

```
[livepicker opts after cancel (runtime GONE, config REMAINS)]:
@livepicker-fg "#ffffff"
@livepicker-key Space
[grep livepicker empty?]: NO
```

`grep livepicker` is NOT empty because `clear_all_state` (state.sh) deliberately
PRESERVES PRD §11 config (@livepicker-fg, @livepicker-key, @livepicker-type).
The contract's literal "grep livepicker empty" would therefore FALSE-FAIL. This
is the SAME correction already encoded by test_functional.sh's `lp_runtime_cleared`
(FINDING 2 / CORRECTION 2) and by the pollution PRP. **The byte-identical
full-options snapshot (FINDING 3) is the correct, stronger substitute.**

## FINDING 3 — Full byte-identical restore is PROVABLE: snapshot
            `show-options -g` + `show-hooks -g` + `#{window_layout}` before
            activate, and after activate→nav→cancel ALL THREE are byte-identical.

Observed (activate → next-session [links alpha] → cancel):

```
OPTIONS: BYTE-IDENTICAL ✓
HOOKS:   BYTE-IDENTICAL ✓
LAYOUT:  BYTE-IDENTICAL ✓
```

This is the strongest possible proof of PRD §15.21 Restore:
- OPTIONS byte-identical ⟹ status, status-format[*], key-table, renumber-windows
  restored AND no @livepicker-* runtime/orig keys leaked (the before-snapshot has
  none; byte-identity forces the after-snapshot to have none too) AND the dormant
  §11 config correctly survives (it is in both snapshots). This single assertion
  subsumes the corrected "grep livepicker empty" clause.
- HOOKS byte-identical ⟹ the `session-window-changed[0] run-shell -b .../sync-
  window-focus.sh` hook (with its `-b` flag + index + absolute path) is restored
  exactly (TRAP 2 in system_context §4; restore.sh's index-preserving replay).
- LAYOUT byte-identical ⟹ `#{window_layout}` of the original window round-trips
  through `select-layout "$ORIG_LAYOUT"` (restore STEP 5) byte-for-byte.

`sort` both sides before comparing (option/hook dump order is not guaranteed
stable across a grow/restore cycle, but the SORTED set is — verified). Use
POSIX `=` via assert_eq on the sorted multi-line strings.

## FINDING 4 — `list-keys -T livepicker` is EMPTY after cancel (the table is
            GONE, not merely emptied). This is the contract's "table unbound".

`restore.sh` STEP 6 does `unbind-key -a -T livepicker` which removes EVERY key
in the table; once empty tmux reports the table as non-existent. Observed:

```
[list-keys -T livepicker after cancel (rc)]:
table livepicker doesn't exist
  rc=1
```

So the "table unbound" assertion is: `out="$(tmux list-keys -T livepicker
2>/dev/null || true)"; [ -z "$out" ]` (the stderr "doesn't exist" is silenced by
2>/dev/null; stdout is empty). Do NOT assert on rc directly under `set -u`/no-`-e`
(capture + empty-test is robust). Verified: stdout empty after cancel.

## FINDING 5 — Key repurpose: the livepicker-table binding is verbatim
            `run-shell "<abs>/input-handler.sh next-session`; the root-table
            binding is byte-identical before AND after (it is never touched —
            the "revert" is free because key-table switches back to root).

During the picker (after activate), observed:

```
[C-M-Tab in livepicker table]:
bind-key -T livepicker C-M-Tab run-shell ".../scripts/input-handler.sh next-session"
[C-M-BTab in livepicker table]:
bind-key -T livepicker C-M-BTab run-shell ".../scripts/input-handler.sh prev-session"
[list-keys -T livepicker line count]: 169
[Down (nav-next) in livepicker]:
bind-key -T livepicker Down run-shell ".../scripts/input-handler.sh next-session"
```

and after cancel:

```
[C-M-Tab in root after cancel]:
bind-key -T root C-M-Tab swap-window -t +1 \; select-window -t +1
ROOT C-M-Tab BYTE-IDENTICAL before/after ✓
ROOT C-M-BTab BYTE-IDENTICAL before/after ✓
```

KEY INSIGHT (PRD §8 / system_context INVARIANT B): activate COPIES the prefix+root
bindings into `livepicker` (rewriting the table spec) and then binds the explicit
keys LAST so they override the copied same-key binding. The root table is NEVER
mutated. On exit, `key-table` returns to `root` (restore STEP 4) and
`unbind-key -a -T livepicker` drops the livepicker bindings. So the same physical
key (`C-M-Tab`) "moves sessions" during the picker (consults `livepicker`) and
"moves windows" after (consults `root`) — with NO binding save/restore for the
revert. The byte-identical root binding before/after is the proof.

`list-keys -T <table> <key>` filters to one key (verified: returns exactly one
line + rc=0 when present, empty + rc=1 when absent). Use `assert_contains` on the
captured line: during-picker → "next-session"/"prev-session"; after-exit →
"swap-window".

## FINDING 6 — Create-on-enter (PRD §15.22): session mode + create on + no match
            + Enter → new session EXISTS and is ACTIVE; create off → NOTHING
            created (picker tears down via cancel); window mode → NOTHING created.

`input-handler.sh confirm` re-filters `@livepicker-list` by `@livepicker-filter`;
if empty AND `opt_type`=session AND `opt_create`=on: `new-session -d -s "$query"`
+ `has-session -t "=$query"` gate → `_confirm_land_on_session` (switch once).
Observed (probe F + J):

```
[filter now]: zzzno        (typed z z z n o)
[has-session zzzno?]: YES
[client session]: zzzno     # ACTIVE
[filter]: newproj
[has-session newproj?]: YES
[active session]: newproj
ACTIVE == newproj ✓
```

create-off (probe G): `@livepicker-create off` + type "zz" + confirm → empty
filtered list + create off → restore.sh cancel → no session, client on driver:

```
[has-session zz?]: NO
[client session after create-off confirm]: driver
[picker torn down? mode]:        # empty = torn down
```

window-mode (probe H): `@livepicker-type window` + type "zq" + confirm → window
mode has no create path → restore.sh cancel → no session:

```
[list captured (window mode) first 3 lines]:
alpha:1
beta:1
driver:1
[has-session zq?]: NO
[client session after window confirm]: driver
[picker torn down? mode]:        # empty = torn down
```

NOTES:
- The query MUST be unique (not a substring of driver/alpha/beta). "zzzno",
  "newproj", etc. are safe. Type char-by-char via `input-handler.sh type <c>`.
- `@livepicker-create` / `@livepicker-type` are read at confirm time (opt_create/
  opt_type in input-handler.sh); set them via `tmux set-option -g` BEFORE activate
  (activate also reads opt_type to build the list). Setting before activate is
  correct for both. The default `@livepicker-create` is "on" (unset on the
  isolated socket → default), but set it explicitly for determinism.
- "active" = `display-message -p '#{session_name}'` == the query. After
  `switch-client -t "=query"` the pointer resets to the query (no fixtures-after-
  attach hazard here: we only read the post-switch state, not a pre-activate
  ORIG_SESSION save).

## FINDING 7 — attach_test_client is REQUIRED for every test_* in this cluster.

All three clusters drive `livepicker.sh` activate (uses `display-message -p` +
`refresh-client -S`), and create/restore use `switch-client`/`display-message`.
ALL require an attached client (setup_socket FINDING 7). Mirrors test_functional.sh
/ test_pollution.sh. UNLIKE test_preview.sh (preview.sh is client-independent — it
reads the driver from @livepicker-orig-session). Every T6 test_* calls
`attach_test_client` FIRST.

No fixtures need to be created AFTER attach for these clusters (the baseline
driver/alpha/beta from setup_socket suffice; create-on-enter makes its OWN new
session). The pollution PRP's "fixtures before attach" rule (FINDING 3 there) is
about ORIG_SESSION save correctness for the recorder — NOT needed here (we read
post-action state, and cancel's switch-client -t "=ORIG_SESSION" with the baseline
already-before-attach returns to driver cleanly, verified).

## FINDING 8 — House style / file contract (mirror test_functional.sh +
            test_preview.sh + test_pollution.sh).

- Each file is SOURCED by run.sh (NEVER executed directly; NO self-test guard; NO
  `BASH_SOURCE`/`$0` check; NO side effects on source; defines `test_*` + `lp_*`
  helpers ONLY; calls NO `setup_test`/`teardown_test` — run.sh owns the per-test
  cycle).
- `set -u` is INHERITED (helpers.sh/run.sh declare it) — do NOT re-declare (mirror
  test_self.sh: "`# set -u is inherited`"). NO `set -e`/`pipefail`.
- Shebang `#!/usr/bin/env bash`; file-level
  `# shellcheck disable=SC2154,SC2016,SC2034,SC2086` (SC2154: assert_*/
  attach_test_client/$LIVEPICKER_SCRIPTS/$TEST_DRIVER_SESSION come from run.sh's
  sources, not this file). TABS for indent; `local` for all function locals.
- Signal failure ONLY via `fail`/`assert_*` (NEVER `exit` — run.sh reads
  TEST_STATUS in the CURRENT shell; a bare exit kills the runner).
- `assert_contains str sub msg` uses a `case` with `"$sub"` quoted (literal
  substring, no subprocess, glob-safe). `assert_eq a b msg` is POSIX `=`.
- run.sh sources test files in ALPHABETICAL order (test_create, test_functional,
  test_pollution, test_preview, test_restore, test_self) BEFORE discovering any
  test_*, so test_functional.sh's `lp_runtime_cleared` IS defined at test-run
  time. But do NOT rely on cross-file helpers — keep each file SELF-CONTAINED
  (house style: each defines its own `lp_*`). The byte-identical snapshot makes a
  runtime-cleared predicate UNNECESSARY for test_restore.sh (FINDING 3 subsumes
  it); test_create.sh checks `@livepicker-mode` empty inline.

## FINDING 9 — The validated end-to-end run.

The probes exercised every scenario this PRP specifies and ALL passed:
- restore byte-identical (options+hooks+layout) ✓ (FINDING 3)
- livepicker table gone after cancel ✓ (FINDING 4)
- key repurpose during (next/prev-session) + after (swap-window, byte-identical)
  ✓ (FINDING 5)
- create-on (exists+active) / create-off (nothing) / window-mode (nothing) ✓
  (FINDING 6)

The existing suite (test_self + T3.S1 functional + T4.S1 preview) is green; these
3 new files add 7 test_* (2 restore + 2 keyrepurpose + 3 create), each hermetic
via run.sh's per-test fresh-socket cycle.
