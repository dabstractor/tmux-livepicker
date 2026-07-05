# Sibling Plugins & Environment — tmux-livepicker Integration Grounding

Source: live inspection of `~/.config/tmux/` and `~/.config/tmux/plugins/` on
2026-07-05. All quoted lines are real. tmux server: **3.6b** (PRD floor is 3.0;
all primitives available).

---

## 0. TL;DR — the five facts that most constrain livepicker

1. **The `session-window-changed` hook is LIVE and array-indexed.** Actual
   running value (not just config text):
   `session-window-changed[0] run-shell -b /home/dustin/.config/tmux/scripts/sync-window-focus.sh`
   — uses `-b` (background), absolute path, index `[0]`. See §5.
2. **Prefix is `None`.** Tubular hijacks `C-Space` in the ROOT table
   (`bind-key -T root C-Space switch-client -T prefix \; refresh-client`) and
   sets `prefix None`. So `@livepicker-key Space` is a **prefix-table** key
   (press C-Space → enter prefix table → press Space). See §8.
3. **`status-format[*]` reports default values, not user-set.** Tubular runs
   `set-option -gu status-format`, so indices `[0]`,`[1]`,`[2]` show tmux's
   built-in defaults. On restore livepicker must `set-option -gu status-format`
   (unset), NOT re-set the captured literal string, or it will fight tubular.
   See §6.
4. **Window-nav keys confirmed:** root-table `C-M-Tab` (next) and `C-M-BTab`
   (prev), each a compound `swap-window \; select-window`. Matches PRD §8
   defaults exactly. See §7.
5. **No socket-isolation test harness exists anywhere.** The PRD §15 phrase
   "as in the session-history test" is aspirational: tmux-session-history has
   **no tests**; resurrect's tests use Vagrant+expect with a real
   `tmux kill-server` (NOT an isolated socket). Livepicker must invent the
   PATH-wrapper pattern itself. See §9.

Other confirmed runtime facts: `renumber-windows on`, current
`key-table` = `root`, `status` = `on`, `status-left-length`/`status-right-length`
unset (tubular sets them to 100/150 at load).

---

## 1. Directory layout / file-naming conventions

All sibling plugins follow the TPM convention: a top-level entry point named
`<plugin>.tmux` plus a `scripts/` dir.

| Plugin | Entry point | scripts/ | Notes |
|---|---|---|---|
| tmux-session-history | `session_history.tmux` | `scripts/session_history.sh` | single script, subcommand-dispatch (`init\|hook\|prune\|toggle\|back\|forward\|pick\|status\|reset`) |
| tmux-sessionx | `sessionx.tmux` | `scripts/{sessionx,fzf-marks,preview,reload_sessions,tmuxinator}.sh` | entry point builds fzf args into `@sessionx-_built-args` |
| tmux-resurrect | `resurrect.tmux` | `scripts/{save,restore,helpers,variables,...}.sh`, `lib/`, `strategies/`, `save_command_strategies/` | helper-sourcing pattern |
| tubular-tmux | `tubular.tmux` | `scripts/{pane-count-icon,prefix-highlight,select-icon,window-index-icon}.sh` | entry point is one big file (no `scripts/` helpers in the render path) |
| user's own scripts | n/a (in `~/.config/tmux/scripts/`) | `sync-window-focus.sh`, `window-nav.sh`, `select-pane.sh`, `auto-pane.sh`, `scroll.sh`, `tubular-palette-toggle.sh` | invoked via `~/.config/tmux/scripts/<name>.sh` |

**PRD §12 file layout** (`plugin.tmux` + `scripts/{options,utils,state,livepicker,input-handler,preview,renderer,restore}.sh`)
matches the sessionx/resurrect convention exactly. Use `plugin.tmux` (not
`livepicker.tmux`) only if you want the TPM autoload name to differ; either works
since the user loads via `run-shell` (see §2).

---

## 2. Plugin loading model — livepicker is NOT yet registered

`~/.config/tmux/tmux.conf` `@plugin` list (the TPM block) does **not** include
tmux-livepicker. Two loading precedents exist:

- **TPM autoload** (most plugins): `set -g @plugin 'org/tmux-foo'` then
  `run '~/.tmux/plugins/tpm/tpm'` at the very bottom. TPM runs each plugin's
  `*.tmux`.
- **Manual `run-shell`** (tmux-thumbs): `tmux.conf` has
  `run-shell '~/.config/tmux/plugins/tmux-thumbs/tmux-thumbs.tmux'` BEFORE the
  TPM init line (see `tmux.conf` ~line 95).

The `@livepicker-key Space` and `@livepicker-fg "#ffffff"` options are already
declared in `tmux.conf` (just above the `source-file ~/.config/tmux/tubular.conf`
line), but dormant because the plugin isn't loaded. **The implementer must add a
load line** — either add `set -g @plugin '<user>/tmux-livepicker'` to the TPM
block, or add a `run-shell` line for `plugin.tmux`. The `run-shell` approach
matches how tmux-thumbs is loaded and avoids a TPM install step.

---

## 3. Option namespacing — `@<plugin>-*`

Confirmed convention across all plugins:

- session-history: `@session-history-{toggle,back,forward,pick}-key` (config),
  internal state `@session-history-{hist,idx,current,prev,walk}`. Prefix is
  `@session-history` and a helper `H()` appends `-<name>`.
- sessionx: `@sessionx-*` (config) + `@sessionx-_built-args`,
  `@sessionx-_built-extra-options` (internal, leading underscore after the
  second dash).
- tubular: `@tubular_*` uses **underscore** (e.g. `@tubular_bg`,
  `@tubular_status_left_text`), and PRIVATE internal copies use `@_tubular_*`
  (leading underscore right after `@`). Dynamic public vars:
  `@tubular_mode_bg`, `@tubular_mode_fg`, `@tubular_pill_bg`, `@tubular_pill_fg`,
  `@tubular_icon_fg`.
- resurrect: `@resurrect-*`, `@resurrect-strategy-nvim`, `@resurrect-restore`.

**Implication for livepicker:** PRD's `@livepicker-*` (hyphen) is consistent
with session-history/sessionx. For internal-only state, follow sessionx's
`@livepicker-_...` or tubular's `@_livepicker_*`; the PRD uses `@livepicker-orig-*`
and `@livepicker-{mode,list,filter,index,linked-id}`, all hyphen-form — fine.

Live session-history state observed (the actual pollution target to protect):
```
@session-history-current tubular
@session-history-hist "hack\nsellario\nremote-pi\nhypr\nmain\njob hunt\nformality\nstagehand\ntmux\nskills\ntubular"
@session-history-idx 10
@session-history-prev skills
@session-history-walk ''
```
History is **newline-separated, deduped**, in `tmux show-options -gv` form. The
PRD §15 pollution test should `show-options -gv @session-history-hist` before &
after and diff.

---

## 4. SCRIPT_DIR computation & helper sourcing

**Canonical idiom (entry points):**
```bash
CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
```
Used verbatim by `session_history.tmux:9`, `sessionx.tmux:3`,
`tubular.tmux` (via the same pattern), and resurrect's `helpers.sh`.

- session-history: `SCRIPT="${CURRENT_DIR}/scripts/session_history.sh"` then
  `tmux run-shell "${SCRIPT} ..."`.
- sessionx: `SCRIPTS_DIR="$CURRENT_DIR/scripts"`; sources helper scripts:
  `source "$SCRIPTS_DIR/tmuxinator.sh"` and `source "$SCRIPTS_DIR/fzf-marks.sh"`.
- resurrect: `scripts/helpers.sh` is sourced by other scripts; it computes
  paths off `$CURRENT_DIR` and uses `source` for `variables.sh` etc.

**`get_tmux_option` helper** appears in every plugin with the same shape:
```bash
get_tmux_option() {
    local value
    value="$(tmux show-option -gqv "$1")"
    [ -n "$value" ] && echo "$value" || echo "$2"
}
```
(session_history.tmux:14-18; tubular.tmux has the identical body; sessionx calls
it `tmux_option_or_fallback`; resurrect `helpers.sh:23-32`.) PRD §12
`scripts/options.sh` `get_opt` should mirror this exactly.

**Note on `show-option` vs `show-options`:** both forms work; sessionx and
session-history use `show-option` (singular). For distinguishing user-set vs
default, tubular has a dedicated probe:
```bash
__tubular_is_set() { tmux show-options -g "$1" >/dev/null 2>&1; }
```
(tubular.tmux) — succeeds even when the option is set to `""`. Livepicker should
use this pattern when it needs "did the user set this?" semantics.

---

## 5. Shell style

Mixed. No single house style — match the closest sibling (session-history) for
consistency since livepicker composes most tightly with it.

| Component | Shebang | Strictness | Quoting |
|---|---|---|---|
| `session_history.tmux` | `#!/usr/bin/env bash` | none | single-quoted hook cmds, double-quoted interpolations |
| `scripts/session_history.sh` | `#!/usr/bin/env bash` | **`set -u`** (NOT `-e`, NOT `-o pipefail`) | heavy `"$var"`; array ops `${HIST[@]}`, `${!HIST[@]}` |
| `sessionx.tmux` | `#!/usr/bin/env bash` | none | tabs for indent; `local` everywhere |
| `tubular.tmux` | `#!/usr/bin/env bash` | none | 2-space indent; `local` |
| resurrect `*.sh` | `#!/usr/bin/env bash` | none | tabs; `local` |
| user `sync-window-focus.sh` | **`#!/bin/sh`** | none | POSIX `while read -r`; `case` dispatch |
| user `select-pane.sh` | **`#!/bin/sh`** | none | POSIX |
| user `window-nav.sh` | `#!/bin/bash` | none | bash `[[ ]]` |

**Recommendation for livepicker:** `#!/usr/bin/env bash` + `set -u` (mirror
session-history). Avoid `set -e` (session-history deliberately omits it because
hooks/options can legitimately return non-zero). Use `local` for all function
locals. Indent with tabs (sessionx/resurrect) or 2-space (tubular) — pick one;
sessionx/resurrect tabs are the majority.

---

## 6. Status-line configuration (grounds PRD §9/10)

The status line is **entirely owned by tubular-tmux**, configured via
`~/.config/tmux/tubular.conf` (sourced from `tmux.conf`) which sets the
`@tubular_*` options, then `tubular.tmux` bakes them into the live options.

### What tubular sets (relevant to livepicker save/restore)

From `tubular.tmux` (the "Base Styling" + "Status Line Content" sections):

- `status on`
- `status-style`, `status-left-style`, `status-right-style`,
  `window-status-style`, `window-status-current-style`,
  `window-status-activity-style`, `window-status-bell-style` → all mode-colored.
- `status-left-length 100`, `status-right-length 150`
- `status-justify absolute-centre`
- `status-left` → only if `@tubular_status_left_text` is set (it is, in
  `tubular.conf`), rendered as a pill.
- `status-right` → only if `@tubular_status_right_text` is set (it is).
- `window-status-format`, `window-status-current-format`,
  `window-status-separator` → only if `@tubular_window_tab_text` is set (it is).
- **`status-format` is UNSET** by `tmux set-option -gu status-format` (the
  "Clean Up Legacy Machinery" block), and likewise `status-bg`/`status-fg`.

### CRITICAL NUANCE: `status-format[*]` shows default values

`tmux show-options -g status-format` returns content for `[0]`, `[1]`, `[2]`
even though tubular unset them — these are **tmux's built-in array defaults**
(the standard left/window-list/right + pane-list + session-list formats), not
user overrides. Observed:
```
status-format[0] "#[align=left range=left #{E:status-left-style}]#[push-default]#{T;=/#{status-left-length}:status-left}...#{T:window-status-format}..."
status-format[1] "#[align=left]#{R: ,#{n:#{session_name}}}P: ...#{P:...}"
status-format[2] "#[align=left]#{R: ,#{n:#{session_name}}}S: ...#{S:...}"
```

**Implication for PRD §9/10:** the save loop `for n in 0..9: capture status-format[n]`
WILL capture these default strings. If livepicker restores them by re-`set-option`
-ing the literal captured value, tubular's mode-coloring (which relies on the
default composing live from `status-left`/`window-status-format`) still works
*because the default format references those options by name* — so re-setting the
literal default is actually safe. But the **cleaner, tubular-friendly** restore is
`tmux set-option -gu status-format` (unset all → back to default), which is
idempotent and matches what tubular itself does on load. Recommend: on restore,
`set-option -gu status-format` rather than replaying captured strings, UNLESS a
captured index was genuinely user-set (detect with the `__tubular_is_set` probe
pattern at save time and only replay those).

### What livepicker must save (PRD §9, confirmed against this env)

- `status` value → `on` (a number/word; livepicker will set it to `2`).
- `status-format[0..9]` → capture; on restore prefer `set-option -gu status-format`.
- `status-left-length`, `status-right-length` → tubular sets these (100/150);
  PRD §9 does not list them. If livepicker only touches `status` + `status-format`,
  these are untouched and fine. (Safe to also save/restore for paranoia.)
- `key-table` → currently `root`.
- `renumber-windows` → `on` (confirming PRD's "use window ids not indices").
- `session-window-changed` hook → see §7 below (the array hook).

### Status-grow mechanism (PRD §10) confirmed feasible

`status-format[0] = #($SCRIPT_DIR/renderer.sh)` + `status = 2` will render the
picker on line 1 and the default (line 1's old content, i.e. the user's tubular
window list) on line 2 — exactly the PRD intent, because the old `status-format[0]`
(default) shifts to `status-format[1]`. `refresh-client -S` forces the `#()`
renderer to re-run; confirmed available on 3.6b.

---

## 7. The `session-window-changed` hook — EXACT definition (grounds PRD §7/9/16)

### In `tmux.conf` (the source of truth the user maintains):
```tmux
set-hook -g session-window-changed "run-shell -b ~/.config/tmux/scripts/sync-window-focus.sh"
```
(`tmux.conf`, in the "Keep focus-aware apps (lazygit) in sync" block, just above
the session-history options.)

### LIVE in the running server (what livepicker actually saves/clears/restores):
```
$ tmux show-hooks -g session-window-changed
session-window-changed[0] run-shell -b /home/dustin/.config/tmux/scripts/sync-window-focus.sh
```

Key properties livepicker MUST preserve on restore:
- **Array-indexed** `[0]` (tmux 3.x hooks are arrays; multiple `set-hook` calls
  append). `show-hooks` prints each index.
- **`-b` flag present** (background — the script does not block the hook chain).
  PRD §16 explicitly calls out "including the `-b` flag if present" — it IS
  present, so the restore command must be:
  `tmux set-hook -g session-window-changed "run-shell -b ~/.config/tmux/scripts/sync-window-focus.sh"`
- **Absolute path** in the live server (`/home/dustin/.config/tmux/scripts/...`),
  tilde-expanded from the config's `~/.config/...`. Save the **exact string
  `show-hooks` emits** (absolute path) and replay it verbatim; do not
  re-derive from `~`.

### Save / clear / restore recipe (recommended)
```bash
# SAVE (activate):
ORIG_HOOK=$(tmux show-hooks -g session-window-changed 2>/dev/null \
            | sed 's/^session-window-changed\[[0-9]*\] //')
tmux set-option -g @livepicker-orig-session-window-changed "$ORIG_HOOK"
# CLEAR (if @livepicker-suppress-window-hook == on):
tmux set-hook -gu session-window-changed   # unset ALL indices
# RESTORE (exit):
if [ -n "$ORIG_HOOK" ]; then
    tmux set-hook -g session-window-changed "$ORIG_HOOK"
else
    tmux set-hook -gu session-window-changed   # was unset; keep unset
fi
```
`set-hook -gu` clears the whole array (all indices). Since this user has exactly
one entry at `[0]`, that's correct. If livepicker ever needs to preserve sibling
entries at other indices, it would need per-index `set-hook -g session-window-changed[n]`,
but that's not needed here.

### What the hook actually does (so suppress makes sense)
`scripts/sync-window-focus.sh` (POSIX `sh`) iterates `tmux list-windows`, sends
`ESC[I` (focus-in) to the active window's pane and `ESC[O` (focus-out) to other
windows' panes, **skipping panes in copy-mode and skipping plain shells** (zsh
zle beeps on `\e[O`). Running this on every livepicker preview navigation (each
`select-window` fires `session-window-changed`) would spam focus bytes into the
linked preview window — exactly why PRD §7 defaults suppression to `on`.

---

## 8. Prefix key & window-nav keybindings (grounds PRD §8)

### Prefix
`tmux.conf`: `set -g prefix C-Space` — **but tubular overrides this at load**:
```bash
# tubular.tmux "Prefix Handling":
tmux set-option -g prefix None
tmux bind-key -n "$prefix_key" 'switch-client -T prefix ; refresh-client'
tmux bind-key -T prefix Any 'refresh-client'
```
with `@tubular_prefix_key "C-Space"` (from `tubular.conf`). Live server confirms:
```
prefix None
bind-key -T root C-Space   switch-client -T prefix \; refresh-client
```
So **`prefix` is `None`** and `C-Space` lives in the **root** table, switching
to the `prefix` table. `@livepicker-key Space` is therefore a **prefix-table**
binding: the user presses `C-Space` (root → prefix table) then `Space`.

**livepicker `plugin.tmux` binding** must use the prefix table (the default
`tmux bind-key` target is `prefix`):
```bash
tmux bind-key "$LIVEPICKER_KEY" run-shell "$CURRENT_DIR/scripts/livepicker.sh"
# i.e. -T prefix (default). Do NOT use -n (root) — that would shadow tubular's
# C-Space handling and break prefix entry.
```
This matches sessionx's prefix-mode (`@sessionx-prefix on` → `tmux bind-key`).

### Window-nav keys (PRD §8 — confirmed EXACT)
`tmux.conf`:
```tmux
bind-key -n C-M-Tab  swap-window -t +1 \; select-window -t +1   # next window
bind-key -n C-M-BTab swap-window -t -1 \; select-window -t -1   # prev window
```
Both are **root-table** (`-n`), compound `swap-window \; select-window`. PRD §8
defaults `@livepicker-next-key C-M-Tab` / `@livepicker-prev-key C-M-BTab` are
correct. PRD §8 "Discovery" note is also confirmed accurate: discovery by
parsing `next-window`/`previous-window` would NOT find this compound binding, so
the hardcoded defaults are required.

### Other relevant keybinds in `tmux.conf`
- Pane nav (root): `C-M-h/j/k/l` → `~/.config/tmux/scripts/select-pane.sh -{L,R,U,D}`
- New window: `bind-key t new-window -c "#{pane_current_path}" -n "#{b:pane_current_path}"`
- Kill window: `bind-key C-w kill-window`, `bind-key X kill-window`
- Break+rename: `bind-key N break-pane \; command-prompt ...`
- Rename window: `bind-key r command-prompt -l -I "#{?{@user_named},#W,}" ...`
- Rename session: `bind-key R command-prompt -I "#S" "rename-session '%%'"`
- Reload: `bind-key C-r source-file ~/.config/tmux/tmux.conf`
- Palette toggle: `bind-key C-t run-shell ".../tubular-palette-toggle.sh"`
- sessionx: `@sessionx-bind C-Space` — **NOTE conflict**: sessionx is bound to
  `C-Space` (prefix-table, since `@sessionx-prefix` defaults `on`) and
  `@livepicker-key Space`. Both are prefix-table keys but different keys
  (`C-Space` vs `Space`), so no collision. Worth verifying at runtime that
  `prefix C-Space` then `Space` hits livepicker and not sessionx.

---

## 9. Test harness — PRD §15 reference does NOT exist (important finding)

**PRD §15 says:** "isolated scripted checks (separate tmux socket via a `tmux`
PATH wrapper, as in the session-history test ...)".

**Reality:** there is **no such test scaffolding in tmux-session-history** (or
any sibling). Verified:
- `tmux-session-history/` contains only `session_history.tmux`,
  `scripts/session_history.sh`, `README.md`, `LICENSE`, `.gitignore` — **no
  `tests/` dir, no socket wrapper, no PATH shim**. Grep for `socket`,
  `TMUX_BIN`, `tmux -L`, `fake.*tmux`, `PATH wrapper` across session-history,
  sessionx, resurrect → **zero matches** (only resurrect's `.travis.yml` +
  Vagrant machinery).
- The only test infra present is **tmux-resurrect's**, which is the OPPOSITE of
  socket-isolated: it uses `lib/tmux-test` (a git submodule) + Vagrant VMs +
  `expect`, and its teardown does a real **`tmux kill-server`**
  (`tests/helpers/create_and_save_tmux_test_environment.exp:42`,
  `helpers.sh:teardown_helper`). It writes a throwaway `~/.tmux.conf` and clones
  the plugin to `~/.tmux/plugins/tmux-plugin-under-test/`.

**Implication:** the livepicker test author must **invent** the PATH-wrapper
socket-isolation pattern. Recommended shape (not found anywhere, proposed):
```bash
# test/setup_socket.sh
SOCK="livepicker-test-$$.sock"
TMUX_SOCK_DIR=$(mktemp -d)
export PATH="$TMUX_SOCK_DIR:$PATH"
cat > "$TMUX_SOCK_DIR/tmux" <<'EOF'
#!/usr/bin/env bash
exec /usr/bin/tmux -L "$TEST_SOCKET" "$@"
EOF
chmod +x "$TMUX_SOCK_DIR/tmux"
export TEST_SOCKET="$SOCK"
# start isolated server: tmux new-session -d -s driver
# ... run plugin scripts (they call bare `tmux`, which hits the shim) ...
# teardown: tmux kill-server; rm -rf "$TMUX_SOCK_DIR"
```
This keeps the user's real server untouched — the property PRD §15 wants. The
implementer should NOT look to session-history for a template (there is none);
resurrect's Vagrant/expect pattern is a poor fit (too heavy, not socket-isolated).

The resurrect helper idioms worth borrowing for assertions (from
`tests/helpers/helpers.sh`):
```bash
TEST_STATUS="success"
fail_helper() { echo "$1" >&2; TEST_STATUS="fail"; }
teardown_helper() { rm -f ~/.tmux.conf; rm -rf ~/.tmux/; tmux kill-server 2>/dev/null; }
exit_helper() { teardown_helper; [ "$TEST_STATUS" = fail ] && exit 1 || exit 0; }
# convention: test functions named test_* ; discovered via
#   for t in $(compgen -A function | grep '^test_'); do "$t"; done
```

---

## 10. Composition notes per sibling (grounds PRD §14)

- **tmux-session-history:** the invariant target. `client-session-changed` is its
  spine (set in `session_history.tmux:24`). livepicker's preview uses
  `select-window` (fires `session-window-changed`, NOT `client-session-changed`)
  so the timeline is untouched while browsing — PRD §4/14 holds. The single
  confirm-time `switch-client` lands as one navigation at the tip, same as a
  sessionx jump. Confirmed the engine dedups and collapses forward history
  (`session_history.sh:do_hook`).
- **tmux-sessionx:** bound to `C-Space` (prefix table). livepicker bound to
  `Space` (prefix table). Different keys → no clash, but verify at runtime.
  sessionx writes `@sessionx-_built-args`/`@sessionx-_built-extra-options`
  (declare -p arrays); livepicker must not touch `@sessionx-*`.
- **tmux-resurrect / continuum:** `@continuum-restore on`,
  `@resurrect-restore C-R`. Resurrect saves/restores sessions from disk; it does
  not hold live state livepicker could corrupt (it snapshots on save, restores on
  load). No hook overlap with livepicker. Safe.
- **tubular-tmux:** owns `status*`, `window-status*`, `pane-*-style`,
  `pane-border-*-style`, and dynamically sets `@tubular_mode_*` on every redraw
  via `#{E:...}`. livepicker's `status-format[0]` override composes ON TOP of
  tubular's styles (the picker line inherits `status-style`). On restore,
  `set-option -gu status-format` returns the bar to tubular's default
  composition. **Do NOT touch `status-left`/`status-right`/`window-status-format`**
  — tubular owns those and they must persist so line 2 (the user's windows)
  renders correctly during the picker.

---

## Start Here

Open **`~/.config/tmux/plugins/tmux-session-history/session_history.tmux`** first
(38 lines) — it is the cleanest template for livepicker's `plugin.tmux`:
`CURRENT_DIR` idiom, `get_tmux_option` helper, option-driven key binding, and
`tmux set-hook` / `tmux run-shell` wiring. Then read
`scripts/session_history.sh` for the `set -u` + array-state-in-`@option` style to
mirror in `scripts/state.sh`.

For the two environment-specific correctness traps, see §6 (status-format
restore via `-gu`, not literal replay) and §7 (the live `session-window-changed[0]`
hook with `-b` and absolute path).

---

*End of scout findings. No files outside the output artifact were modified.*
