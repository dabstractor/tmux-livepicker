# tmux-livepicker

A modal status-line session and window picker that previews candidates live, in
place, without leaving your current session.

## Overview

tmux-livepicker turns the status bar into a fuzzy picker. While the picker is
active the status bar grows to two lines: line 1 is the candidate list, and the
area below it shows a live, all-panes preview of the highlighted candidate. You
filter by typing and move the selection with your usual window-navigation keys.
Confirming lands you on the chosen session **and the exact window being
previewed**, not just the session (optionally creating a new one from
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
- **Exact restore.** Cancel leaves no trace: status, keys, focus, and hooks are
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
- **Filter.** I type `log` and the list narrows to sessions whose names
  fuzzy-match `log` (characters in order, not necessarily contiguous), with the
  best match first.
- **Confirm.** I press `Enter` and land on the selected session.
- **Create.** I type `newproj` (no match) and press `Enter`; a new `newproj`
  session is created and I am switched to it.
  Characters tmux disallows in
  session names (such as `.`) are sanitized (`my.proj` becomes `my_proj`),
  and you still land on the created session.
- **Cancel.** I press `Escape` (or `Escape` twice) and everything is restored
  exactly as if I had never opened the picker.

## Installation

**Option A: [Tmux Plugin Manager](https://github.com/tmux-plugins/tpm):**

```tmux
set -g @plugin '<your-org>/tmux-livepicker'
```

Reload your config and press `prefix + I` to install.

**Option B: manual `run-shell` (no TPM step; mirrors tmux-thumbs):**

```sh
git clone <repo-url> ~/.config/tmux/plugins/tmux-livepicker
```

```tmux
run-shell '~/.config/tmux/plugins/tmux-livepicker/plugin.tmux'
```

> `@livepicker-key` is **required**. If it is unset, the plugin prints a
> `display-message` (`tmux-livepicker: set @livepicker-key to activate`) and
> binds nothing; it still loads cleanly. Set it before first use:

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
| `@livepicker-session-next-keys` | `(discovered)` | Next-session keys (session axis). Default: discovered `switch-client -n` bindings + `Down`. For this user: `)`, `Down`. Must be non-alphanumeric; a plain letter/digit is intercepted and not typeable. Section 8. |
| `@livepicker-session-prev-keys` | `(discovered)` | Previous-session keys (session axis). Default: discovered `switch-client -p` bindings + `Up`. For this user: `(`, `Up`. Must be non-alphanumeric. Section 8. |
| `@livepicker-window-next-keys`  | `(discovered)` | Next-window keys (window axis — flip the previewed session's windows). Default: discovered next-window bindings. For this user: `C-M-Tab`, `M-n`, `C-n`, `C-l`. Must be non-alphanumeric. Section 8. |
| `@livepicker-window-prev-keys`  | `(discovered)` | Previous-window keys (window axis). Default: discovered prev-window bindings. For this user: `C-M-BTab`, `M-p`, `C-p`, `C-h`. Must be non-alphanumeric. Section 8. |
| `@livepicker-confirm-keys`         | `Enter`    | Confirm and land on the selection.                                                                   |
| `@livepicker-cancel-keys`          | `Escape`   | Clear the query, or cancel if the query is empty.                                                    |
| `@livepicker-backspace-keys`       | `BSpace`   | Remove the last filter character.                                                                    |
| `@livepicker-rename-key`           | `C-r`      | Rename the highlighted session via tmux's prompt. Control key; never collides with typing.           |
| `@livepicker-delete-key`           | `M-BSpace` | Delete (kill) the highlighted session. Matches sessionx's `@sessionx-bind-kill-session`.             |
| `@livepicker-confirm-delete`       | `off`      | When `on`, prompt `y/n` before killing a session (`confirm-before`). Default `off` = immediate, sessionx-style. |
| `@livepicker-preview-mode`         | `live`     | `live` (link-window, all panes), `snapshot` (capture-pane, active pane), or `off`.                   |
| `@livepicker-preview-defer`        | `on`        | Defer the live preview to a background job so typing and navigation never wait on `link-window`/`select-window`; `off` restores the synchronous path for diagnosis. |
| `@livepicker-preview-fit`          | `clip`      | `clip` freezes the preview height before the status bar grows so the panes do not reflow (the bottom row is clipped instead); `reflow` is the legacy one-row reflow. Use `reflow` if `clip` misbehaves on your tmux/terminal. |
| `@livepicker-suppress-window-hook` | `on`       | Clear `session-window-changed` during the picker to avoid focus-resync side effects.                 |
| `@livepicker-tab-style`            | `plain`     | `plain` (standalone `@livepicker-fg`/`bg`/`highlight-*`) or `window-status` (reuse the theme's `window-status-current-format` / `window-status-format` so picker tabs match your window tabs; falls back to `plain`). |
| `@livepicker-fg`                   | `default`  | Picker text color.                                                                                   |
| `@livepicker-bg`                   | `default`  | Picker background.                                                                                   |
| `@livepicker-highlight-fg`         | `black`    | Highlighted (current) item text.                                                                     |
| `@livepicker-highlight-bg`         | `yellow`   | Highlighted item background.                                                                         |
| `@livepicker-status-format-index`  | `0`        | Which status line the picker takes. Must be a displayed line: the status bar grows to `current + 1` lines on activation, so a value at or beyond the grown line count renders the picker invisibly. `0` (the default) is always safe. |
| `@livepicker-nerd-fonts`            | `on`       | Opt-out for the search icon (tmux cannot detect the terminal font). `on` shows the icon; `off` shows query text only. |
| `@livepicker-search-icon`           | `\uf002`   | The icon glyph shown before the query while typing. Default is `nf-fa-search` (U+F002); raw UTF-8 bytes in the source. |
| `@livepicker-query-gap`             | `2`        | Spaces between the query and the first session tab while a query is active. |
| `@livepicker-overflow-left`         | `<`        | Left overflow indicator (presence only; shown when `@livepicker-scroll > 0`). |
| `@livepicker-overflow-right-format` | `+%d>`     | Right overflow indicator; `%d` = total hidden tabs (left + right combined). |

Set any option before the plugin loads (or set it and reload tmux):

```tmux
set -g @livepicker-type 'window'
set -g @livepicker-highlight-bg 'magenta'
```

### Appearance

The picker can match your window-status theme. Set `@livepicker-tab-style window-status` and the picker renders its items through the theme's own `window-status-current-format` / `window-status-format`, so the tabs read as part of the status bar under any theme. The default is `plain`, which uses the standalone `@livepicker-fg` / `bg` / `highlight-*` colors. If the theme format cannot be resolved, the picker falls back to `plain`, so the option never breaks your status bar.

Both `plain` and `window-status` styles draw line 1 from the same layout described in [Status line](#status-line): with a query active the query is pinned far left, the tabs flow left-to-right windowed by scroll, and the overflow indicators apply; `status-justify` is honored only when there is no query and the tabs fit. One source of truth for line 1, two render styles for the tab glyphs.

### Performance

The live preview is deferred by default. Typing and navigation redraw the status line immediately; the preview re-link runs in the background, so neither waits on `link-window` / `select-window`. Set `@livepicker-preview-defer off` to restore the synchronous preview path (useful for diagnosis).

### Status line

Line 1 of the status bar is the picker. Its layout is the same for both `plain` and `window-status` tab styles, and it changes with the query.

- **Query bar.** A search icon (`@livepicker-search-icon`, a magnifier by default) followed by your query sits at the far left of line 1, but only while you are typing. On open, or after you clear the query, there is no icon, no query, and no gap: line 1 shows only the session tabs. The icon shows when `@livepicker-nerd-fonts` is `on` (the default); tmux cannot detect your font, so set it `off` if you see a missing-glyph box. Exactly `@livepicker-query-gap` spaces (default `2`) separate the query from the first tab while a query is active.
- **Tabs.** The tabs run left-to-right, fuzzy-ranked (a subsequence match: every query character appears in order, case-insensitive, not necessarily contiguous), with the best match first and non-matches hidden. With an empty query, all sessions show in tmux's default order. Tabs are windowed by scroll; typing, backspace, or clearing the query resets the scroll to the far left, and next/previous scroll the highlight into view.
- **Overflow indicators.** When the tabs do not fit, a right `+N>` (`@livepicker-overflow-right-format`, default `+%d>`) shows the total number of hidden tabs, left and right combined, and a left `<` (`@livepicker-overflow-left`, default `<`) appears when the scroll is past the far left. Both can show at once (`< tabs +N>`); neither shows when everything fits.
- **No count.** The picker shows no position or total count anywhere.
- **No match.** With no matching session, line 1 shows the icon and query followed by ` (no match)`; create-on-Enter still applies.
- **Justify.** While a query is active, `status-justify` is suspended because the query is pinned left and the tabs must flow left-to-right for the scroll viewport. `status-justify` is honored only when there is no query and the tabs fit.

## Usage

1. **Activate:** press your prefix, then `@livepicker-key` (`Space` by
   default). The status bar grows to two lines: the picker, with a live
   preview of the highlighted candidate below.
2. **Filter:** type to filter; matching is fuzzy and ranked best-first
   (see [Status line](#status-line)). `BSpace` removes a character.
3. **Navigate sessions:** `Down` / `Up` (or your `@livepicker-session-next-keys` /
   `-session-prev-keys`) move the selection between candidates; the preview
   follows live.
4. **Flip windows:** while previewing a session, your window-nav keys
   (`@livepicker-window-next-keys` / `-window-prev-keys`, discovered from your
   own `next-window` / `previous-window` bindings) flip its windows live. Line
   2's window-status follows the flip. The session's own active window is
   untouched — you are only looking.
5. **Confirm:** `Enter` lands on the chosen session **and the exact window
   being previewed** (not just the session), or creates a session from
   your query in `session` mode with no match.
6. **Cancel:** `Escape` clears the query if non-empty, otherwise cancels and
   restores everything exactly.
7. **Rename / delete:** `C-r` renames the highlighted session; `M-BSpace`
   kills it. See [Session management](#session-management).

- With [tubular](https://github.com/danutatubu/tubular-tmux), the prefix is `None` and `C-Space` enters the prefix table, so the activate sequence is `C-Space` → `Space`.
- Letters and digits go to the query by default; set `@livepicker-session-next-keys` / `-session-prev-keys` to `j` / `k` for vim-style navigation at the cost of typing them.

While the picker is active, the key table is fully modal: keys not explicitly
bound to a picker action (typing, navigation, confirm, cancel) or carried over
from your prefix/root tables are dropped and never reach the previewed panes.
Carried-over bindings are filtered to exclude any command that would switch the
session/window or mutate window/pane state, so browsing stays pollution-free and
the live preview remains display-only.

### Session management

Rename and delete act on the highlighted (and previewed) session, resolved the
same way as confirm and navigation. With `@livepicker-type window` they act on
the highlighted window analogously.

- **Rename.** `@livepicker-rename-key` (default `C-r`) opens tmux's `command-prompt` pre-filled with the current name; on submit the session is renamed, the list is rewritten, and the highlight stays on the renamed session while the picker remains open. It is a control key, so it never collides with typing.
- **Delete.** `@livepicker-delete-key` (default `M-BSpace`) kills the highlighted session.
- **Delete guards.** The kill is refused with a `display-message` (no kill happens) for the driver session you launched the picker from (killing it detaches your client and destroys the picker host) and for the last remaining session (tmux requires at least one).
- **Confirm.** `@livepicker-confirm-delete on` prompts `y/n` via `confirm-before` before a kill; the default `off` is immediate.
- **Delete-key caveat.** A few older terminals or SSH/mosh links strip Alt-modified keys entirely. If `M-BSpace` does not fire there, rebind `@livepicker-delete-key` to `C-h` or `DC` (Delete).
- **Escaping limitation.** Session names containing a single quote, double quote, backtick, or dollar sign may break the rename prompt. tmux also rejects `:` in a session name. Such names are rare; this is a known limitation.

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

Two preview-resizing effects stem from tmux's `window-size` behavior on a linked (live) preview window. One is fixed by default; the other persists.

- **Status-grow reflow is fixed by default.** Growing the status bar from one line to two on activation used to shrink the preview's panes by one row, the visible jank on open. With the default `@livepicker-preview-fit` `clip`, the preview height is frozen before the status grows and the bottom row is clipped instead, so no pane reflows. Set `@livepicker-preview-fit` `reflow` to get the old one-row shrink back if `clip` misbehaves on your tmux or terminal.
- **Detached candidates are pinned (no resize) in `clip` mode.** When you navigate to a detached candidate, the picker freezes that candidate's `window-size` and window height at link time (and restores them when you leave), so its panes are not reflowed by the live link and its own session keeps its original geometry after the picker exits. Candidates that carry their own attached client cannot be pinned this way (freezing `window-size` would revert that client's view to the window's creation size), so for strict pane-immutability across client-bearing sessions set `@livepicker-preview-mode` `snapshot` (preview with `capture-pane` and never link a live window). In `@livepicker-preview-fit` `reflow` mode candidates still resize at link time (reflow is the legacy escape hatch); use `clip` (the default) or `snapshot` to avoid it.

## Compatibility

- Requires tmux **≥ 3.2** (multi-line `status` / `status-format[n]` is the
  binding feature). Tested on **3.6b**.
- Composes with the rest of the stack. It mutates only well-scoped global options
  (`status`, `status-format[n]`, the key table, and the
  `session-window-changed` hook) and restores every one of them on exit:
  - **tmux-session-history:** the timeline this plugin is designed not to
    disturb (browsing fires no `client-session-changed`).
  - **tmux-sessionx:** different prefix key (`C-Space` vs `Space`); no clash.
  - **tmux-resurrect / continuum:** saves/restores from disk; no live-state
    overlap.
  - **tubular:** owns `status*` and `window-status*`; livepicker overrides
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

- **Functional:** activation, filtering, navigation, confirm, cancel.
- **Live preview:** the all-panes in-place preview.
- **Pollution invariant:** browsing fires no `client-session-changed`.
- **Byte-exact restore:** status, keys, focus, and hooks are restored.
- **Key repurpose:** repurposed window-nav keys revert on cancel.
- **Create on Enter:** session creation from an unmatched query.

## Maintenance

`PRD.md` §0 ("Prior attempt") is a build-time scaffold left in place during
implementation. It should be removed by a human after post-verification of the
shipped plugin; this README intentionally does **not** edit `PRD.md`. Release
notes and the version bump live in the CHANGELOG (maintained separately).
