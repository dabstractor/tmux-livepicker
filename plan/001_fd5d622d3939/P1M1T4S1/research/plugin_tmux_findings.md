# Research Findings — P1.M1.T4.S1: plugin.tmux (bind activation key, prefix table, unset guard)

> All facts below verified live on 2026-07-05 against tmux **3.6b** on the target
> machine. These are the empirical ground-truth for the `plugin.tmux` PRP.

## FINDING 1 — `bind-key KEY CMD` (no `-T` / `-n`) targets the PREFIX table

This is THE load-bearing fact for the contract's bind command. Verified live:

```bash
$ tmux bind-key 0 run-shell "/tmp/fake-livepicker-test"; echo "rc=$?"
rc=0
$ tmux list-keys -T prefix | grep /tmp/fake-livepicker-test
bind-key    -T prefix 0       run-shell /tmp/fake-livepicker-test     # ← FOUND IN PREFIX
$ tmux list-keys -T root | grep /tmp/fake-livepicker-test
(nothing)                                                          # ← NOT in root
$ tmux unbind-key -T prefix 0   # cleanup
```

**Conclusion:** `tmux bind-key "$KEY" run-shell "$CURRENT_DIR/scripts/livepicker.sh"`
(with NO `-T`, NO `-n`) binds into the **prefix** table. This is exactly what the
contract requires. Adding `-n` would put it in the **root** table and SHADOW
tubular's `C-Space` root binding (`switch-client -T prefix \; refresh-client`),
breaking prefix entry entirely. Do NOT add `-T root` or `-n`.

(Note: an earlier probe used key `F24`, which tmux 3.6b rejects as `unknown key:
F24` — only VALID tmux key names are accepted by `bind-key`. `Space` is valid.)

## FINDING 2 — Current prefix-table state (what `bind Space` overwrites)

```bash
$ tmux list-keys -T prefix | grep -iE 'Space|BSpace'
bind-key -r -T prefix Space   next-layout       # ← tmux DEFAULT; will be OVERWRITTEN by livepicker
bind-key -r -T prefix BSpace  previous-layout
bind-key    -T prefix C-Space run-shell .../tmux-sessionx/scripts/sessionx.sh   # sessionx
```

**Implications:**
- Binding `Space` (the user's `@livepicker-key`) **overwrites tmux's default
  `prefix Space → next-layout`**. This is the user's EXPLICIT INTENT (they
  pre-declared `@livepicker-key Space` in `tmux.conf`). Documented, expected,
  not a bug. The PRP's "Known Gotchas" calls this out so the implementer doesn't
  "preserve" next-layout.
- **No collision with sessionx**: sessionx is bound to `C-Space` (prefix table),
  livepicker to `Space` (prefix table) — different keys. Confirmed by
  sibling_plugins_and_env.md §10.
- The binding is **idempotent / reload-safe**: re-running `bind-key Space ...`
  simply overwrites the prior livepicker binding. Mirrors session_history.tmux's
  reload-safety. plugin.tmux can be sourced/re-run freely.

## FINDING 3 — `prefix` is `None`; C-Space lives in the ROOT table (tubular)

```bash
$ tmux show-options -gv prefix
None
$ tmux list-keys -T root | grep C-Space
bind-key -T root C-Space   switch-client -T prefix \; refresh-client
```

So the user's prefix-entry flow is: press `C-Space` (root → prefix table) → press
the prefix-table key. `@livepicker-key Space` is therefore a **prefix-table**
binding. This is exactly why the bind MUST go to the prefix table (FINDING 1) and
NOT root (`-n`). Confirmed verbatim by system_context.md §5.

## FINDING 4 — Pre-declared options are LIVE and correct

```bash
$ tmux show-options -gqv "@livepicker-key"
Space
$ tmux show-options -gqv "@livepicker-fg"
#ffffff
```

Both dormant options from `tmux.conf` are present. `@livepicker-key` resolves to
`Space` — so on this machine the guard's ELSE branch (bind) is the exercised path.
The IF branch (empty → display-message + exit 0) must STILL be implemented and
tested (mock sets the key to empty) because the PRD requires the unset-guard for
users who haven't set `@livepicker-key`.

## FINDING 5 — session_history.tmux is EXECUTABLE; plugin.tmux must be too

```bash
$ ls -la /home/dustin/.config/tmux/plugins/tmux-session-history/session_history.tmux
-rwxr-xr-x 1 dustin dustin 2054 ... session_history.tmux
```

Loading model (system_context §1 / sibling_plugins §2): the `.tmux` entry point
is invoked via `tmux run-shell '/path/to/plugin.tmux'` (tmux-thumbs style) or by
TPM's `run-shell`. `run-shell` passes the path to `sh -c`, which requires the
file to be **executable** (shebang `#!/usr/bin/env bash` honored). A non-
executable `.tmux` fails with "Permission denied."

**Action:** `chmod +x plugin.tmux` is a REQUIRED, explicit task step (not
optional). The shebang `#!/usr/bin/env bash` is REQUIRED for the same reason.

## FINDING 6 — CURRENT_DIR idiom resolves under execution (not just sourcing)

```bash
# plugin.tmux body:
CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# executed as: bash /tmp/lp_idiom_test/plugin.tmux
# → CURRENT_DIR=/tmp/lp_idiom_test   ✓ correct
```

`${BASH_SOURCE[0]}` resolves to the script's own path whether executed or sourced.
The idiom (verbatim from session_history.tmux:9) is correct for an entry point.

## FINDING 7 — options.sh activates `set -u` when sourced; plugin.tmux inherits it

`scripts/options.sh` (P1.M1.T1.S1) begins with `set -u`. Sourcing it inside
plugin.tmux leaves `set -u` ACTIVE for the remainder of plugin.tmux. Verified
plugin.tmux's own code is `set -u`-safe: every variable it reads (`CURRENT_DIR`,
`KEY`) is assigned before use. The contract's "Do NOT set -e" rule is unaffected
(`set -u` ≠ `set -e`). No need to add `set -u` explicitly (inherited), and MUST
NOT add `set -e` (a bad/invalid `@livepicker-key` makes `tmux bind-key` print
`unknown key: ...` and return non-zero; `set -e` would abort plugin load — the
contract explicitly forbids this so an invalid key degrades gracefully).

## FINDING 8 — Validation strategy: fake-tmux-on-PATH mock (no live-server clobber)

The P1.M7 socket-isolation shim does not exist yet. Validating by binding `Space`
on the LIVE server would clobber the user's `prefix Space → next-layout` binding
(invasive). Instead, use a **fake `tmux` on PATH** that:

1. Logs every invocation (`bind-key`, `display-message`, `show-option`) to a file.
2. Responds to `show-option -gqv "@livepicker-key"` with a configurable value
   (set → exercises the bind branch; empty → exercises the guard branch).

Then execute `plugin.tmux` with `PATH="$MOCK_DIR:$PATH"` and assert the log
contains the exact expected command for each branch:
- **set branch:** `bind-key Space run-shell <CURRENT_DIR>/scripts/livepicker.sh`
  (and NOTHING in root; no `-n`; no `-T`).
- **empty branch:** `display-message 'tmux-livepicker: set @livepicker-key to activate'`
  (and NO `bind-key` call at all).

This is zero-impact (no live tmux touched), tests the EXACT emitted command
string, exercises BOTH branches, and is a natural precursor to the P1.M7 shim.
The live server is used only for the one-off FINDING-1 default-table confirmation
(already done + cleaned up).

## FINDING 9 — Contract reconciliation: inline `get_opt` vs `opt_key` accessor

The work-item contract says: "Source options.sh. Read KEY=get_opt @livepicker-key ''."
`scripts/options.sh` (P1.M1.T1.S1) also provides `opt_key()` which is exactly
`get_opt "@livepicker-key" ""`. Both are equivalent. The PRP uses the contract's
literal **inline `get_opt "@livepicker-key" ''`** form because:
1. It mirrors session_history.tmux's inline `get_tmux_option '@session-history-...-key' 'L'`
   idiom (the template the contract names).
2. It makes the **empty-string default visible at the call site** — and that empty
   default IS the guard semantics. Hiding it inside `opt_key` obscures the core
   logic of this file. For an entry point whose entire purpose is the guard,
   inline + visible-empty is clearer.
3. The contract's literal instruction says so.

`opt_key` remains the canonical accessor for downstream scripts; plugin.tmux is
the one place the empty-default guard matters visibly.

## FINDING 10 — `exit 0` semantics

- **Guard branch (empty key):** contract mandates explicit `exit 0` (do not bind).
  Required so plugin load succeeds cleanly when the user hasn't configured a key.
- **Bind branch (success):** contract does not mandate a trailing exit. session_history.tmux
  has none (falls off → implicit exit 0). BUT a defensive trailing `exit 0`
  guarantees plugin load reports success even if `tmux bind-key` warned about an
  invalid key (without `set -e`, a failing last command would otherwise set a
  non-zero script exit). The PRP adds a trailing `exit 0` for graceful-degradation
  (matches the contract's "tmux bind may warn; don't let it abort" intent).
