# Sanitized-name create test grounding — P1.M1.T3.S2

> Verified LIVE on 2026-07-07 against isolated tmux sockets on the same machine as
> `P1M1T3S1/research/issue3_fix_findings.md` (tmux **3.6b**, bash **5.3.15**,
> shellcheck **0.11.0**). Confirms the committed regression test
> `test_create_sanitized_name_lands_on_session` (appended to `tests/test_create.sh`)
> PASSES against the S1-fixed `input-handler.sh` and FAILS against the reverted
> (buggy) gate — i.e. it is load-bearing, not vacuous.

## Environment

| Tool | Version (from P1M1T3S1 research; same host) |
|---|---|
| tmux | 3.6b |
| bash | 5.3.15(1)-release |
| shellcheck | 0.11.0 |

## S1 fix state at the time of this research

The S1 fix (P1.M1.T3.S1) is **already applied** to the real `scripts/input-handler.sh`
(the parallel implementation landed it). Verified by grep:

```
scripts/input-handler.sh:387:  local z_target="" created="" new_session_args=(-d -P -F '#{session_name}' -s "$query")
scripts/input-handler.sh:401:  created="$(tmux new-session "${new_session_args[@]}" 2>/dev/null)"
scripts/input-handler.sh:403:      _confirm_land_on_session "$created"
```

The only remaining `has-session -t "=$query"` is inside the explanatory **comment**
(line 394: "The OLD gate (has-session -t \"=$query\") checked the ORIGINAL"). So the
real plugin is on the FIXED path. (The plan_status "Implementing" label was stale.)

## FINDING 1 — the test PASSES against the FIXED plugin (pass=5 fail=0)

Drove the EXACT new-test logic (`attach_test_client` → `@livepicker-create on` →
`livepicker.sh` → type `m y . p r o j` → `confirm`) against the real fixed plugin on a
fresh isolated socket (baseline = driver/alpha/beta = 3 sessions):

```
before_list=[alpha,beta,driver,]   before_n=3
after_list =[alpha,beta,driver,my_proj,]   after_n=4
active session = [my_proj]
```

All 5 assertions PASS:
| # | assertion | result | value |
|---|---|---|---|
| A1 | `has-session -t "=my_proj"` (sanitized session created) | PASS | exists |
| A2 | `has-session -t "=my.proj"` (raw name absent — no duplicate) | PASS | absent |
| A3 | `display-message -p '#{session_name}'` == `my_proj` (client landed) | PASS | `my_proj` |
| A4 | session count == before+1 (exactly one new session) | PASS | 4 == 3+1 |
| A5 | `@livepicker-mode` == "" (picker torn down) | PASS | empty |

→ **The test is green on the fix.** The client lands on `my_proj`; no orphan; exactly
one session created; picker cleanly torn down.

## FINDING 2 — the test FAILS against the reverted (buggy) gate (pass=4 fail=1)

Reintroduced the bug in a TEMP COPY (reverted the local line + gate to the old
`has-session -t "=$query"` form + `_confirm_land_on_session "$query"`). Ran the same
logic. Never touched the real `scripts/input-handler.sh`.

```
before_list=[alpha,beta,driver,]   before_n=3
after_list =[alpha,beta,driver,my_proj,]   after_n=4
active session = [driver]            <-- STRANDED on the driver
FAIL A3 landed on sanitized name: got[driver] want[my_proj]
```

Result: **pass=4 fail=1**. The ONE failing assertion is **A3** (the client is stranded
on `driver` instead of `my_proj`). This is exactly the Issue 3 symptom: the sanitized
session `my_proj` IS created (A1 pass), but the client is returned to the driver by
`restore.sh cancel` (the old `has-session` gate rejected the sanitized success), so the
created session is orphaned/abandoned.

→ **The test is load-bearing**: regressing the S1 fix (restoring the `has-session` gate)
makes A3 fire. The test catches Issue 3.

## FINDING 3 — A3 is THE load-bearing assertion; A4 (count) is invariant across fix/bug

Important nuance: the orphan in Issue 3 is the +1 session itself (`my_proj`), NOT an
extra session beyond it. So:

| assertion | FIXED build | BUGGY build | load-bearing? |
|---|---|---|---|
| A1 sanitized session created | PASS (my_proj) | PASS (my_proj) | no |
| A2 raw name absent | PASS | PASS | no |
| A3 client landed on sanitized name | PASS (my_proj) | **FAIL (driver)** | **YES** |
| A4 count == before+1 | PASS (4) | PASS (4) | no (belt-and-braces) |
| A5 mode cleared | PASS | PASS | no |

A4 (`count == before+1`) PASSES on both — it is a valid "no extra orphan" invariant but
does NOT by itself distinguish fix from bug. **A3 (landed on the sanitized name) is the
single assertion that flips.** The test is still worthwhile with all 5 (A1/A2/A5 document
intent and guard separate failure modes; A4 guards a double-create/leftover); but the
regression-detection power lives in A3. (A double-orphan bug — e.g. a leftover from a
prior failed create — WOULD trip A4, so it earns its place.)

## FINDING 4 — the test follows `test_create_on_creates_and_activates` EXACTLY (zoxide is a non-issue)

Pattern fidelity check against the sibling test (`test_create_on_creates_and_activates`):
both do `attach_test_client` → `tmux set-option -g @livepicker-create on` →
`"$LIVEPICKER_SCRIPTS/livepicker.sh"` → char-by-char `input-handler.sh type` → `confirm`
→ assert via `pass`/`fail`/`assert_eq`.

The ONLY deliberate difference is the **query** (`my.proj` instead of `zzzno`). No extra
option pinning is needed:
- `@livepicker-zoxide-mode` **defaults to `"off"`** (`scripts/options.sh:29`), and the
  sibling test relies on that default (it sets neither create-mode-adjacent options nor
  zoxide). The create path's `if [ "$(opt_zoxide)" = "on" ]` branch therefore never
  fires → `my.proj` takes the PLAIN create path → `-P -F '#{session_name}'` captures
  `my_proj` → land. Verified (FINDING 1 ran WITHOUT an explicit zoxide pin and passed).
- Do NOT add `tmux set-option -g @livepicker-zoxide-mode off`: it would deviate from the
  sibling pattern and is redundant (the default is already off; `setup_test` does not
  touch zoxide — it only pins `@livepicker-preview-defer off`).

→ Mirror the sibling exactly; the dotted query is the entire point and the only change.

## FINDING 5 — exact assertion values + base-count handling

- The sanitized name is the **literal** `my_proj` (tmux maps every `.` → `_`; verified in
  `architecture/issue3_findings.md` and S1's FINDING 1). Assert on the literal — do NOT
  compute it from the typed query in bash (that would replicate tmux's sanitization
  rules, the anti-pattern S1 deliberately avoided).
- The "no orphan" count check must snapshot `before_n` DYNAMICALLY and assert
  `after_n == before_n + 1`. `setup_socket` seeds driver/alpha/beta (3) today; a future
  fixture change must not break the test. `wc -l` emits leading whitespace → pipe through
  `tr -d '[:space:]'` before the string compare (the same normalization
  `test_window_preview_driver_self_no_duplicate` in `tests/test_preview.sh` uses).
- `attach_test_client` is REQUIRED: `display-message -p '#{session_name}'` and
  `switch-client` need an attached client (per `tests/setup_socket.sh` FINDING 7). The
  sibling test attaches first; so does this one.

## FINDING 6 — no parallel conflict

P1.M1.T3.S1 (running in parallel) edits `scripts/input-handler.sh`. This task (S2) edits
ONLY `tests/test_create.sh`. No shared file → no merge conflict. The test consumes S1's
output (the `-P -F` capture) but does not modify it. The test PASSES the moment S1's fix
is present (it already is) and FAILS if S1's fix is reverted (FINDING 2).
