# System Context — tmux-livepicker

> The canonical architectural ground-truth for this implementation. All facts
> below were verified live on 2026-07-05 on the target machine. Downstream PRP
> agents MUST treat this file as authoritative over any conflicting assumption.

## 1. Project state (greenfield)

- Working dir: `/home/dustin/.config/tmux/plugins/tmux-livepicker`
- Existing files: `PRD.md`, `plan/`, `PRPs/`, `.claude/`. **No source code exists yet.**
- This is a fresh build from the PRD. No prior-attempt files are present to
  disregard (the `.git` history is empty of implementation).
- The plugin is **NOT yet registered** in `~/.config/tmux/tmux.conf`'s TPM block,
  but two options are already pre-declared there (dormant until loaded):
  - `@livepicker-key Space`
  - `@livepicker-fg "#ffffff"`
- **Loading:** the implementer should add a `run-shell` line for `plugin.tmux`
  (mirrors how `tmux-thumbs` is loaded just above the TPM init line), OR add a
  `set -g @plugin` entry to the TPM block. Either works; `run-shell` avoids a
  TPM install step.

## 2. Verified environment (run on the live server)

| Fact | Value | Verified via |
|---|---|---|
| `tmux -V` | **3.6b** | `tmux -V` |
| `status` | `on` | `show-options -g status` |
| `key-table` | `root` | `show-options -gv key-table` |
| `prefix` | `None` | `show-options -gv prefix` |
| `renumber-windows` | `on` | `show-options -gv renumber-windows` |
| `session-window-changed` hook | `session-window-changed[0] run-shell -b /home/dustin/.config/tmux/scripts/sync-window-focus.sh` | `show-hooks -g session-window-changed` |
| `status-format[0..2]` | tmux built-in defaults (tubular UNSET them with `-gu`, so they appear as defaults) | `show-options -g status-format` |
| Window-nav (root) | `C-M-Tab → swap-window -t +1 \; select-window -t +1`<br>`C-M-BTab → swap-window -t -1 \; select-window -t -1` | `list-keys -T root` |
| Sessions present | 15 (hack, sellario, remote-pi, hypr, main, job hunt, formality, stagehand, tmux, skills, tubular, …) | `list-sessions` |

## 3. The three load-bearing architectural invariants (PROVEN by research)

These three facts are the spine of the design. They are verified, not assumed.

### INVARIANT A — Browsing never fires `client-session-changed`
`select-window` fires `session-window-changed` but **NOT** `client-session-changed`.
`link-window`/`unlink-window` fire neither (only `window-linked`/`window-unlinked`).
Therefore browsing via link+select keeps the tmux-session-history timeline and the
`@session-history-prev` toggle pointer completely untouched. The single
confirm-time `switch-client` is the only `client-session-changed` in the whole
flow. → PRD §4 / §14 holds.

### INVARIANT B — A non-root `key-table` is fully modal (drops unmatched keys)
When `key-table` is `livepicker`, tmux consults **only** that table. An unbound
key is **dropped**, never passed to root/prefix or the pane. The preview is
genuinely display-only. PRD §7 "Input during preview" hedge is overly cautious;
this behavior is stable across all modern tmux. → No input leaks into the
previewed session's panes.
**Consequence (load-bearing):** because only `livepicker` is consulted, the
user's `root` and `prefix` bindings do NOT fire during the picker unless
explicitly copied in. PRD §8's "copy `list-keys -T prefix` and `-T root`,
rewrite table to `livepicker`, re-bind" step is **necessary**, not optional.

### INVARIANT C — Multi-line status with one set + one unset line composes correctly
With `status=2`, `status-format[0]=#(renderer.sh)` (picker), and
`status-format[1]` **unset**, line 1 = picker and line 2 = tmux's built-in
default composite (status-left + window-status-format + status-right), which is
**exactly the user's tubular window-status line**. Verified that tubular unsets
`status-format` (`-gu`), so the defaults are live-composed from
`status-left`/`window-status-current-format` etc. → PRD §10 mechanism is sound.

## 4. Two environment-specific correctness traps (from scout, CONFIRMED)

### TRAP 1 — status-format restore must `set-option -gu`, not literal replay
`show-options -g status-format` returns tmux defaults (because tubular unset
them). If livepicker captures those default strings and replays them verbatim,
it *happens* to work (defaults reference style options by name), but it is
fragile and fights tubular on next reload.
**Correct restore:** `tmux set-option -gu status-format` (unset all → back to
default). At save time, use a "is this index genuinely user-set?" probe
(`tmux show-options -g status-format[n]` exit code distinguishes set-vs-default
in 3.x; alternatively just always `-gu` on restore since this env has no
genuine user overrides). PRD §9 step 4 should be read as "restore to default"
not "replay captured string".

### TRAP 2 — the session-window-changed hook is array-indexed with `-b`
The live value is exactly:
```
session-window-changed[0] run-shell -b /home/dustin/.config/tmux/scripts/sync-window-focus.sh
```
Save the **whole `show-hooks -g session-window-changed` output** (strip the
`session-window-changed[N] ` prefix, but there may be multiple indices).
Suppress with `set-hook -gu session-window-changed` (clears all indices).
Restore by re-running each saved `set-hook -g session-window-changed "<cmd>"`
verbatim, **preserving the `-b` flag**. If nothing was saved, leave unset.

## 5. Prefix key reality (grounds PRD §8 binding target)

`prefix` is `None`. Tubular hijacks `C-Space` in the **root** table:
`bind-key -T root C-Space switch-client -T prefix \; refresh-client`. So the
user's prefix flow is: press `C-Space` (root → prefix table) → press the
prefix-table key.
`@livepicker-key Space` is therefore a **prefix-table** binding. In `plugin.tmux`:
```bash
tmux bind-key "$LIVEPICKER_KEY" run-shell "$CURRENT_DIR/scripts/livepicker.sh"
# default target table is `prefix` — do NOT use -n (root) or you shadow tubular.
```
The user's two pre-declared options (`@livepicker-key Space`, `@livepicker-fg`)
confirm this is the intended UX.

## 6. tmux-session-history composition (the invariant we protect)

Live state observed:
```
@session-history-current tubular
@session-history-hist "hack\nsellario\nremote-pi\nhypr\nmain\njob hunt\nformality\nstagehand\ntmux\nskills\ntubular"
@session-history-idx 10
@session-history-prev skills
```
- History is newline-separated, deduped, stored in `@session-history-hist`.
- The engine is driven by `client-session-changed` (set in
  `session_history.tmux:24`). Browsing never fires it (Invariant A).
- Pollution test (PRD §15.18): diff `show-options -gv @session-history-hist`
  before/after a browse-then-cancel; assert zero delta. After confirm, assert
  exactly one new entry appended at the tip with forward history collapsed.

## 7. Test harness reality (PRD §15 reference is aspirational)

**No socket-isolation test harness exists in any sibling plugin.** The PRD
phrase "as in the session-history test" describes a pattern that does not
exist there. tmux-resurrect uses Vagrant + expect with a real `kill-server`
(too heavy, not socket-isolated).
**livepicker must invent the PATH-wrapper shim itself.** Recommended shape:
```bash
# test/setup_socket.sh
TMUX_SOCK_DIR=$(mktemp -d)
export TEST_SOCKET="livepicker-test-$$"
cat > "$TMUX_SOCK_DIR/tmux" <<EOF
#!/usr/bin/env bash
exec /usr/bin/tmux -L "$TEST_SOCKET" "\$@"
EOF
chmod +x "$TMUX_SOCK_DIR/tmux"
export PATH="$TMUX_SOCK_DIR:$PATH"
tmux new-session -d -s driver   # isolated server
# ... plugin scripts call bare `tmux` → hit the shim → isolated server ...
# teardown: tmux kill-server; rm -rf "$TMUX_SOCK_DIR"
```
Borrow assertion idioms from resurrect's `tests/helpers/helpers.sh`
(`fail_helper`, `teardown_helper`, `test_*` function discovery). Do NOT use
resurrect's Vagrant/expect pattern.

## 8. File layout to build (PRD §12, confirmed against sibling conventions)

```
tmux-livepicker/
  plugin.tmux                 # bind @livepicker-key (prefix table) → activate
  scripts/
    options.sh                # get_opt helper + defaults table
    utils.sh                  # safe tmux option helpers (get/set/unset/save/probe-is-set)
    state.sh                  # @livepicker-* state get/set/clear
    livepicker.sh             # activate
    input-handler.sh          # type / backspace / next / prev / confirm / cancel
    preview.sh                # link-window live preview (+ capture fallback)
    renderer.sh               # status-line #() renderer
    restore.sh                # tear down: unlink, restore status/keys/layout/hooks
tests/
  setup_socket.sh             # PATH-wrapper shim (invented — see §7)
  helpers.sh                  # fail/teardown/test discovery (resurrect-style)
  run.sh                      # entry; runs all test_* functions
  test_*.sh                   # one per validation cluster (PRD §15)
```

## 9. Shell style (mirror tmux-session-history, the closest composition target)

- Shebang: `#!/usr/bin/env bash`
- `set -u` (NO `-e`, NO `-o pipefail` — hooks/options legitimately return non-zero)
- `local` for all function locals
- Tabs for indent (sessionx/resurrect majority)
- SCRIPT_DIR: `CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"`
- `get_tmux_option` idiom (verbatim from siblings):
  ```bash
  get_tmux_option() { local v; v="$(tmux show-option -gqv "$1")"; [ -n "$v" ] && echo "$v" || echo "$2"; }
  ```
- Quote everything; addresses use `="$S"` exact-match and `@N` window ids, never indices.

## 10. Version floor

- PRD says 3.0. **Verified reality:** all primitives used exist on 3.6b.
- The genuinely binding feature is multi-line `status`/`status-format[n]`,
  likely introduced in 3.2 (researcher could not nail the exact version from
  man pages). Recommend documenting the floor as **3.2** and gating at activate
  (`tmux -V` parse), degrading to snapshot-only or refusing below it. On the
  target machine this is moot (3.6b).

## 11. Cross-references

- `tmux_primitives.md` — per-primitive verification (link/unlink, key-table,
  status-format, hooks, list-windows -f, capture-pane, switch-client, version).
- `sibling_plugins_and_env.md` — full scout of session-history/sessionx/resurrect/
  tubular, exact config quotes, option-namespacing conventions, the hook
  definition, prefix key flow, test-harness reality.
