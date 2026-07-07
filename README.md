# tmux-livepicker

A modal status-line session and window picker that previews candidates live, in
place, without leaving your current session.

## Overview

tmux-livepicker turns the status bar into a fuzzy picker. While the picker is
active the status bar grows to two lines: line 1 is the candidate list, and the
area below it shows a live, all-panes preview of the highlighted candidate. You
filter by typing and move the selection with your usual window-navigation keys.
Confirming lands you on the chosen session (optionally creating a new one from
your filter query); cancelling restores your status line, key table, and focus
exactly. Browsing **never** switches your session, so it does not corrupt the
[tmux-session-history](https://github.com/dabstractor/tmux-session-history)
timeline or its Alt-Tab style toggle.

## Goals

- **Status-line picker.** List sessions or windows in the status bar, no popup.
- **Live, in-place preview.** See every pane of the highlighted candidate as you
  browse, rendered in your current window.
- **Filter + repurposed navigation.** Type to filter; move with keys you already
  use to navigate windows.
- **Create on Enter.** In session mode, with no match, Enter creates a session
  from your filter query.
- **Zero history pollution.** Browsing fires no `client-session-changed`, so
  session history and the toggle pointer are untouched while you browse.
- **Exact restore.** Cancel leaves no trace — status, keys, focus, and hooks are
  byte-for-byte restored.

## Non-goals

- No popup / floating UI (the status bar is the surface).
- One window at a time (no multi-select).
- No pane picking (windows only).
- No most-recently-used ordering.
- Single attached client.

## User stories

- **Activate.** I press my prefix, then `@livepicker-key`, and the picker appears
  in the status bar with a live preview below it.
- **Navigate.** I press my next/previous window keys and the selection moves to a
  different session, with the preview following live.
- **Filter.** I type `log` and the list narrows to sessions whose names contain
  `log`.
- **Confirm.** I press `Enter` and land on the selected session.
- **Create.** I type `newproj` (no match) and press `Enter`; a new `newproj`
  session is created and I am switched to it.
  Characters tmux disallows in
  session names (such as `.`) are sanitized — `my.proj` becomes `my_proj` —
  and you still land on the created session.
- **Cancel.** I press `Escape` (or `Escape` twice) and everything is restored
  exactly as if I had never opened the picker.

## Installation

**Option A — [Tmux Plugin Manager](https://github.com/tmux-plugins/tpm):**

```tmux
set -g @plugin '<your-org>/tmux-livepicker'
```

Reload your config and press `prefix + I` to install.

**Option B — manual `run-shell` (no TPM step; mirrors tmux-thumbs):**

```sh
git clone <repo-url> ~/.config/tmux/plugins/tmux-livepicker
```

```tmux
run-shell '~/.config/tmux/plugins/tmux-livepicker/plugin.tmux'
```

> `@livepicker-key` is **required**. If it is unset, the plugin prints a
> `display-message` (`tmux-livepicker: set @livepicker-key to activate`) and
> binds nothing — it still loads cleanly. Set it before first use:

```tmux
set -g @livepicker-key 'Space'
```

Reload tmux (`tmux source-file ~/.config/tmux/tmux.conf`) and press your prefix,
then the key.

## Configuration

All options use the `@livepicker-` prefix. Defaults are the shipped values from
`scripts/options.sh`.

| Option                             | Default    | Purpose                                                                                              |
| ---------------------------------- | ---------- | ---------------------------------------------------------------------------------------------------- |
| `@livepicker-key`                  | (required) | Prefix-table key that activates the picker. If unset, the plugin prints a `display-message` and binds nothing. |
| `@livepicker-type`                 | `session`  | `session` or `window`. What the picker lists.                                                        |
| `@livepicker-create`               | `on`       | In session mode, create a new session from the query on Enter when nothing matches.                  |
| `@livepicker-zoxide-mode`          | `off`      | In session mode, resolve the create query through `zoxide` and start the session in that dir (mirrors `@sessionx-zoxide-mode`). |
| `@livepicker-next-key`             | `C-M-Tab`  | Key that moves to the next session. Defaults to this user's next-window key.                         |
| `@livepicker-prev-key`             | `C-M-BTab` | Key that moves to the previous session. Defaults to this user's prev-window key.                     |
| `@livepicker-nav-next-keys`        | `Down`     | Extra next-session keys. Must be non-alphanumeric; a letter/digit here is intercepted and not typeable. |
| `@livepicker-nav-prev-keys`        | `Up`       | Extra previous-session keys. Must be non-alphanumeric; a letter/digit here is intercepted and not typeable. |
| `@livepicker-confirm-keys`         | `Enter`    | Confirm and land on the selection.                                                                   |
| `@livepicker-cancel-keys`          | `Escape`   | Clear the query, or cancel if the query is empty.                                                    |
| `@livepicker-backspace-keys`       | `BSpace`   | Remove the last filter character.                                                                    |
| `@livepicker-preview-mode`         | `live`     | `live` (link-window, all panes), `snapshot` (capture-pane, active pane), or `off`.                   |
| `@livepicker-preview-defer`        | `on`        | Defer the live preview to a background job so typing and navigation never wait on `link-window`/`select-window`; `off` restores the synchronous path for diagnosis. |
| `@livepicker-suppress-window-hook` | `on`       | Clear `session-window-changed` during the picker to avoid focus-resync side effects.                 |
| `@livepicker-tab-style`            | `plain`     | `plain` (standalone `@livepicker-fg`/`bg`/`highlight-*`) or `window-status` (reuse the theme's `window-status-current-format` / `window-status-format` so picker tabs match your window tabs; falls back to `plain`). |
| `@livepicker-fg`                   | `default`  | Picker text color.                                                                                   |
| `@livepicker-bg`                   | `default`  | Picker background.                                                                                   |
| `@livepicker-highlight-fg`         | `black`    | Highlighted (current) item text.                                                                     |
| `@livepicker-highlight-bg`         | `yellow`   | Highlighted item background.                                                                         |
| `@livepicker-show-count`           | `on`       | Show `index/total` in the picker.                                                                    |
| `@livepicker-status-format-index`  | `0`        | Which status line the picker takes.                                                                  |

Set any option before the plugin loads (or set it and reload tmux):

```tmux
set -g @livepicker-type 'window'
set -g @livepicker-highlight-bg 'magenta'
```

### Appearance

The picker can match your window-status theme. Set `@livepicker-tab-style window-status` and the picker renders its items through the theme's own `window-status-current-format` / `window-status-format`, so the tabs read as part of the status bar under any theme. The default is `plain`, which uses the standalone `@livepicker-fg` / `bg` / `highlight-*` colors. If the theme format cannot be resolved, the picker falls back to `plain`, so the option never breaks your status bar.

### Performance

The live preview is deferred by default. Typing and navigation redraw the status line immediately; the preview re-link runs in the background, so neither waits on `link-window` / `select-window`. Set `@livepicker-preview-defer off` to restore the synchronous preview path (useful for diagnosis).

## Usage

1. **Activate** — press your prefix, then `@livepicker-key` (`Space` by default).
   With [tubular](https://github.com/danutatubu/tubular-tmux) the prefix is
   `None` and `C-Space` enters the prefix table, so the sequence is
   `C-Space` → `Space`. The status bar grows to two lines: line 1 is the picker;
   the area below shows the highlighted candidate's panes, live.
2. **Filter** — type to filter the list (substring, case-insensitive); `BSpace`
   removes a character.
3. **Navigate** — `C-M-Tab` / `C-M-BTab` (your window-nav keys, repurposed) or
   `Down` / `Up` move the selection. The preview follows live. Plain letters
   and digits are reserved for the query, so `j`/`k` (and every other letter)
   are typeable by default; set `@livepicker-nav-next-keys`/`-prev-keys` to add
   vim-style `j`/`k` nav at the cost of typing them.
4. **Confirm** — `Enter` lands on the selection. In `session` mode with no match
   and `@livepicker-create on`, it creates a session from your query and switches
   to it.
5. **Cancel** — `Escape` clears the query if non-empty, otherwise cancels and
   restores your status line, key table, and focus exactly.

While the picker is active, the key table is fully modal: keys not explicitly
bound to a picker action (typing, navigation, confirm, cancel) or carried over
from your prefix/root tables are dropped and never reach the previewed panes.
Carried-over bindings are filtered to exclude any command that would switch the
session/window or mutate window/pane state, so browsing stays pollution-free and
the live preview remains display-only.

## How it works

Browsing does **not** switch your session. The plugin links the highlighted
candidate's active window into your current session with `tmux link-window` and
selects it with `select-window`, so all of its panes render live. `select-window`
fires `session-window-changed` (suppressed by default via
`@livepicker-suppress-window-hook`) but **not** `client-session-changed`, so the
tmux-session-history timeline and the toggle pointer are untouched while you
browse. The only session switch in the whole flow is the single `switch-client`
at confirm. Cancelling leaves zero trace.

### Known limitations

- **Detached candidate windows are resized during preview.** When a detached
  candidate window is linked into the attached driver session for live
  preview, tmux resizes the shared window object to the driver's dimensions.
  After the picker exits, the candidate's window retains the driver's size
  rather than its original dimensions. This is inherent to tmux's
  `window-size` behavior and affects only detached candidate sessions. To
  avoid this, set `@livepicker-preview-mode snapshot` (uses `capture-pane`
  and never links the window).

## Compatibility

- Requires tmux **≥ 3.2** (multi-line `status` / `status-format[n]` is the
  binding feature). Tested on **3.6b**.
- Composes with the rest of the stack. It mutates only well-scoped global options
  (`status`, `status-format[n]`, the key table, and the
  `session-window-changed` hook) and restores every one of them on exit:
  - **tmux-session-history** — the timeline this plugin is designed not to
    disturb (browsing fires no `client-session-changed`).
  - **tmux-sessionx** — different prefix key (`C-Space` vs `Space`); no clash.
  - **tmux-resurrect / continuum** — saves/restores from disk; no live-state
    overlap.
  - **tubular** — owns `status*` and `window-status*`; livepicker overrides
    `status-format[0]` on top and restores it with `set-option -gu status-format`
    on exit, leaving tubular's styles intact.
- Note: with tubular, `prefix` is `None` and `C-Space` enters the prefix table,
  so `@livepicker-key` is a prefix-table binding.

## Validation

```sh
bash tests/run.sh
```

Run from the repo root. The suite spins up a **private, isolated tmux socket per
test** via a `tmux` PATH-wrapper shim, so your real running server is never
touched. It prints `PASS` / `FAIL` per test plus a summary and exits `0` iff all
passed. Expect the full suite to take roughly **2–3 minutes** (each test starts
a fresh isolated tmux server and sources the user config). The suites cover the PRD §15 clusters:

- **Functional** — activation, filtering, navigation, confirm, cancel.
- **Live preview** — the all-panes in-place preview.
- **Pollution invariant** — browsing fires no `client-session-changed`.
- **Byte-exact restore** — status, keys, focus, and hooks are restored.
- **Key repurpose** — repurposed window-nav keys revert on cancel.
- **Create on Enter** — session creation from an unmatched query.

## Maintenance

`PRD.md` §0 ("Prior attempt") is a build-time scaffold left in place during
implementation. It should be removed by a human after post-verification of the
shipped plugin — this README intentionally does **not** edit `PRD.md`. Release
notes and the version bump live in the CHANGELOG (maintained separately).
