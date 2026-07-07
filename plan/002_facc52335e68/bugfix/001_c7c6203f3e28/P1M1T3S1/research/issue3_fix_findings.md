# Issue 3 fix grounding — `-P -F` name capture (P1.M1.T3.S1)

> Verified LIVE on 2026-07-07 against isolated tmux sockets (`tmux 3.6b`,
> `bash 5.3.15`, `shellcheck 0.11.0`). Confirms the fix for the create-on-confirm
> name-sanitization orphan bug in `scripts/input-handler.sh`. The primary research
> is `architecture/issue3_findings.md` (the bug report's own analysis); this note
> adds the live end-to-end verification of every branch of the fix.

## Environment

| Tool | Version |
|---|---|
| tmux | **3.6b** |
| bash | **5.3.15(1)-release** |
| shellcheck | **0.11.0** |

---

## FINDING 1 — `new-session -d -P -F '#{session_name}' -s <q>` captures the ACTUAL created name

Run against an isolated socket (`tmux -L lp_i3_$$ ...`). The `-P` flag prints session
info on creation; `-F '#{session_name}'` selects the format. It composes harmlessly
with `-d` (detached), `-s` (name), and the zoxide `-c`/`-n` args:

| typed query (`-s`) | `-P -F` stdout | tmux sanitization rule |
|---|---|---|
| `my.proj` | `my_proj` | every `.` → `_` |
| `a:b` | `a_b` | every `:` → `_` |
| `.hidden` | `_hidden` | leading `.` → `_` |
| `foo bar.baz` | `foo bar_baz` | space preserved; `.` → `_` |
| `plainname` | `plainname` | no sanitization (regression-safe) |
| `x.y` + `-c /tmp -n winname` | `x_y` | session name captured (NOT the `-n` window name) |
| `""` (empty) | *(empty)* | rc=1 → cancel |

→ The fix captures the actual name tmux used, whatever its sanitization rules. No need
to replicate tmux's rules in bash (which would be fragile across versions).

## FINDING 2 — the gate `[ -n "$created" ]` correctly handles every failure mode

The old gate was `tmux new-session ... && tmux has-session -t "=$query"` (rc-based AND
name-equality). The new gate is `created="$(tmux new-session ... 2>/dev/null)"; [ -n "$created" ]`.

| Scenario | new-session rc | stdout | `created` | gate | outcome |
|---|---|---|---|---|---|
| sanitized name (`my.proj`) | 0 | `my_proj` | `my_proj` | true | **land on `my_proj`** (FIX) |
| plain name (`zzzno`) | 0 | `zzzno` | `zzzno` | true | land on `zzzno` (unchanged) |
| empty query (`""`) | 1 | *(empty)* | `""` | false | **cancel** (no orphan) |
| collision (`my.proj` but `my_proj` EXISTS) | 1 | *(empty)* | `""` | false | **cancel** (no orphan) |

Collision verified live:
```
$ tmux -L lp_i3c_$$ new-session -d -s my_proj
$ tmux -L lp_i3c_$$ new-session -d -P -F '#{session_name}' -s 'my.proj'   # my_proj exists
(empty output, rc=1)   # new-session refuses (no -A) → created="" → cancel
```
→ The fix is STRICTLY BETTER than the old gate: it lands when creation succeeds (under
ANY name tmux chose) and cancels (without orphan) when it fails. The old gate orphaned
on every sanitized success.

## FINDING 3 — `_confirm_land_on_session "$created"` is the correct landing call

`_confirm_land_on_session` (input-handler.sh:79) takes `tgt="${1:-}"` and does:
1. unlink the driver's preview window (H2-hardened),
2. `tmux switch-client -t "=$tgt"` (the ONE session switch, exact-match `=`),
3. `restore.sh keep` (tear down picker, leave client on target).

Passing the captured `$created` (e.g. `my_proj`) makes `switch-client -t "=my_proj"` land
on the actually-created session. The OLD code passed `$query` (`my.proj`) →
`switch-client -t "=my.proj"` → no such session → stranded. The fix changes ONLY the
argument (`$query` → `$created`); the helper itself is unchanged.

## FINDING 4 — the `new_session_args` array edit is minimal + composes with zoxide

Current: `local z_target="" new_session_args=(-d -s "$query")`, then optionally
`new_session_args+=(-c "$z_target" -n "$z_target")`.

Fixed: `local z_target="" created="" new_session_args=(-d -P -F '#{session_name}' -s "$query")`,
then the SAME optional `+=(-c "$z_target" -n "$z_target")`.

- Adding `created=""` to the `local` line (declare-first, assign-later) is SC2155-safe.
- `-P -F '#{session_name}'` are array-literal elements (single quotes → literal
  `#{session_name}` passed to tmux, NOT bash-expanded). Verified the array expansion
  `"${new_session_args[@]}"` passes `-F` and `#{session_name}` as separate correct args.
- The zoxide `+=(-c ... -n ...)` appends AFTER `-s "$query"`; tmux accepts flags in any
  order. The `-n` sets the WINDOW name (not session); `-F '#{session_name}'` still
  captures the SESSION name. Verified (`x.y` + `-c -n` → `x_y`).

## FINDING 5 — existing tests are unaffected (the coverage GAP is S2's job)

`tests/test_create.sh` uses pure-alphanumeric queries (`zzzno`, `qwfx`, `mplg`) — NEVER
sanitized. With the fix: `created="zzzno"` → land (identical to today). So the 3 existing
create tests pass unchanged. The sanitization code path is UNTESTED today; the regression
test for it is P1.M1.T3.S2 (the next subtask). This PRP (S1) is the FIX + a throwaway smoke;
it does NOT add a committed test (that's S2).

## FINDING 6 — no parallel conflict

P1.M1.T2.S2 (running in parallel) is **test-only**: it appends one `test_*` function to
`tests/test_preview.sh`. It does NOT touch `scripts/input-handler.sh`. So this fix (a
focused edit to the input-handler confirm/create block) cannot conflict with it.
