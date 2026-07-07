# Issue 3 Findings: Create-on-confirm Name Sanitization

## Bug Location
**File:** `scripts/input-handler.sh`
**Line:** ~401 (the create gate in the `confirm)` branch)
```bash
if tmux new-session "${new_session_args[@]}" 2>/dev/null && tmux has-session -t "=$query" 2>/dev/null; then
    _confirm_land_on_session "$query"
else
    "$CURRENT_DIR/restore.sh" cancel
fi
```

## Root Cause
The `.` character is in the PRD §6 typeable set (`a-z A-Z 0-9 - _ . /`). tmux
silently sanitizes session names containing `.` and `:` by replacing them with
`_`. The `new-session` call SUCCEEDS (rc=0) with the sanitized name, but the
`has-session -t "=$query"` gate checks for the ORIGINAL unsanitized query.
The gate fails, the code falls through to `restore.sh cancel`, and the
just-created session is orphaned.

## Empirical Sanitization Rules (verified on isolated socket)

| Input | Actual Created Name | Rule |
|-------|-------------------|------|
| `my.proj` | `my_proj` | ALL `.` → `_` |
| `a:b` | `a_b` | ALL `:` → `_` |
| `.hidden` | `_hidden` | leading `.` → `_` |
| `foo bar.baz` | `foo bar_baz` | space preserved, `.` → `_` |
| `a..b` | `a__b` | each `.` → `_` independently |
| `a-b_c.d/e` | `a-b_c_d/e` | `-`, `_`, `/` preserved; `.` → `_` |

Key: BOTH `.` and `:` are replaced with `_` everywhere (not just leading).

## Capture Mechanism: `new-session -P -F '#{session_name}'`
```bash
$ tmux new-session -P -F '#{session_name}' -d -s 'sanitized.name'
# Output: sanitized_name (the ACTUAL created name)
```
The `-P` flag prints session info on creation. `-F '#{session_name}'` specifies
the format. Composes harmlessly with `-d -s -c -n` args (zoxide path).

## Recommended Fix: Approach (a) — Post-resolve the actual name

Replace the `has-session` gate with a `-P -F '#{session_name}'` capture:

```bash
# BEFORE (buggy — gate on original query name):
local new_session_args=(-d -s "$query")
if [ "$(opt_zoxide)" = "on" ]; then
    z_target="$(zoxide query "$query" 2>/dev/null)"
    [ -n "$z_target" ] && new_session_args+=(-c "$z_target" -n "$z_target")
fi
if tmux new-session "${new_session_args[@]}" 2>/dev/null && tmux has-session -t "=$query" 2>/dev/null; then
    _confirm_land_on_session "$query"
else
    "$CURRENT_DIR/restore.sh" cancel
fi

# AFTER (fixed — capture actual name):
local created=""
local new_session_args=(-d -P -F '#{session_name}' -s "$query")
if [ "$(opt_zoxide)" = "on" ]; then
    z_target="$(zoxide query "$query" 2>/dev/null)"
    [ -n "$z_target" ] && new_session_args+=(-c "$z_target" -n "$z_target")
fi
created="$(tmux new-session "${new_session_args[@]}" 2>/dev/null)"
if [ -n "$created" ]; then
    _confirm_land_on_session "$created"
else
    "$CURRENT_DIR/restore.sh" cancel
fi
```

### Why this is better than pre-sanitizing
1. **No need to know sanitization rules** — whatever tmux names it, we use
2. **Eliminates orphan entirely** — we always switch to the created session
3. **Version-robust** — works across tmux versions
4. **Handles zoxide path** — `-P -F` composes harmlessly with `-c -n`
5. **Minimal diff** — replaces the gate (the bug) with a capture (the fix)

### Collision handling
If the sanitized name already exists (e.g., user types `my.proj` but `my_proj`
exists), `new-session` fails (no `-A` flag) → `created=""` → cancel. Correct.

### Empty query
`new-session -s ""` → rc=1, stdout empty → `created=""` → cancel. Correct.

## Edge Cases

| Input | Buggy behavior | Fixed behavior |
|-------|---------------|----------------|
| `my.proj` | orphan `my_proj`, stranded | land on `my_proj` |
| `a:b` | orphan `a_b`, stranded | land on `a_b` |
| `.hidden` | orphan `_hidden`, stranded | land on `_hidden` |
| `foo bar.baz` | orphan `foo bar_baz`, stranded | land on `foo bar_baz` |
| `zzzno` (alphanumeric) | works (gate passes) | works (`created="zzzno"`) |
| `""` (empty) | cancel (gate fails) | cancel (`created=""`) |
| sanitized name exists | cancel (collision) | cancel (collision) |

## Test Coverage Gap
All three existing create tests use pure-alphanumeric queries (`zzzno`, `qwfx`,
`mplg`) that are NEVER sanitized. The sanitization code path is completely
untested. A regression test must type a dotted query (e.g. `my.proj`) and assert:
1. The session is created under the sanitized name (`my_proj`)
2. The client lands on it (not cancelled)
3. No orphan sessions remain
