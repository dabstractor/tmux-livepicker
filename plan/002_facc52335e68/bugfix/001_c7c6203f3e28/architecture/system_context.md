# System Context: Bug Fix 001_c7c6203f3e28

## Scope

End-to-end QA bug fixes for the tmux-livepicker plugin (rev 002:
theme-matched tabs §17 + deferred preview §18). Six issues found: 3 Major
(state corruption, user stranding), 3 Minor (race, rendering edge case,
inherent resize side effect).

## Codebase Map (files touched by these fixes)

| File | Lines | Issues | Nature of Change |
|------|-------|--------|-----------------|
| `scripts/preview.sh` | 203 | 1, 2, 4 | Core: link-window call, self-session guard, supersede guard |
| `scripts/input-handler.sh` | 469 | 3 | Confirm branch: create-on-confirm name capture |
| `scripts/livepicker.sh` | 416 | 5 | Sentinel session name in `_lp_resolve_tab_templates` |
| `scripts/renderer.sh` | 201 | 5 | Second placeholder swap in window-status render path |
| `tests/test_preview.sh` | 212 | 1, 2 | New tests: window-index assertions, window-mode driver self |
| `tests/test_restore.sh` | 183 | 1 | Strengthen existing tests with index assertions |
| `tests/test_create.sh` | 92 | 3 | New test: sanitized-name create path |
| `README.md` | 209 | 6 | Known Limitations section |
| `CHANGELOG.md` | — | all | Bug fix entries |

## Key Architectural Invariants (must be preserved)

1. **Exact restoration** (PRD §9/§15): after any picker cycle (cancel or confirm),
   the driver session's window list must be byte-identical — including window
   **indices**, not just window IDs.
2. **Invariant A** (no session switch during browsing): `select-window` does NOT
   fire `client-session-changed`; preview links do not switch the client.
3. **Address windows by @id, never index**: `renumber-windows` is on, so indices
   are unstable. BUT the index-corruption bug means even the @id-only addressing
   can leave the user's window list corrupted (gaps, shifted indices).
4. **Supersede guarantee** (PRD §18): a late/superseded deferred preview job must
   be a true no-op, never leaving a linked window behind.

## Dependency Graph

```
Issue 1 (link-window -a) ─┐
                          ├─► Both in preview.sh, independent fixes
Issue 2 (self-session) ───┘
                          │
Issue 3 (create sanitize) ──► input-handler.sh, independent
                          │
Issue 4 (TOCTOU race) ──────► preview.sh, depends on Issue 1's link-window change
                          │
Issue 5 (sentinel) ────────► livepicker.sh + renderer.sh, independent
                          │
Issue 6 (resize) ──────────► README.md only, independent
```

Issue 4 depends on Issue 1 because both modify the link-window block in
preview.sh; Issue 4's third seq-check and idempotent link probe are inserted
in the same region as Issue 1's `-a` removal. Implement Issue 1 first.

## Test Infrastructure

- Harness: `tests/setup_socket.sh` (isolated `-L` socket + PATH shim)
- Helpers: `tests/helpers.sh` (assert_eq, assert_contains, fail/pass)
- Runner: `tests/run.sh` (sources all test_*.sh, runs test_* functions)
- Tests use `$TEST_DRIVER_SESSION` (="driver") with a multi-pane "extra" window
- `attach_test_client` required for tests that call `display-message -p`
- `setup_test` pins `@livepicker-preview-defer off` for deterministic synchronous
  preview assertions

## Empirical Verification Results (run by supervisor)

### Issue 1: link-window -a index shift
```
BEFORE: 1:w0 2:w1 3:w2 (active=w0 at index 1, NOT last)
WITH -a:   link -> 1:w0 2:zsh 3:w1 4:w2 (INSERTED MIDDLE, shifted!)
           unlink -> 1:w0 3:w1 4:w2 (GAP at 2, permanent shift)
WITHOUT -a: link -> 1:w0 2:w1 3:w2 4:zsh (APPENDED AT END)
            select -> active=@3 (correct)
            unlink -> 1:w0 2:w1 3:w2 (PERFECT restoration)
```
renumber-windows on does NOT close the gap on unlink.

### Issue 2: duplicate link
`link-window -a -s @7 -t drv:` (where @7 is already in drv) creates a duplicate
entry with id @7, rc=0. The `${S%%:*}` extraction works: `drv:1` -> `drv`.

### Issue 3: name sanitization
`new-session -d -s 'my.proj'` -> creates `my_proj` (all `.` replaced with `_`)
`new-session -P -F '#{session_name}' -d -s 'my.proj'` -> outputs `my_proj` ✓
`has-session -t '=my.proj'` -> FAILS; `has-session -t '=my_proj'` -> succeeds

### Issue 5: sentinel resolution
`#W` against sentinel -> `__lp_tab__` (swappable placeholder)
`#{session_name}` against sentinel -> `__lp_sent_123_456` (unique, NOT swappable)
