# tmux-livepicker: Product Requirements Document

> Self-contained specification. An implementing agent can build the entire plugin
> from this document alone. No prior knowledge of the project is assumed.

## 0. Prior attempt (remove this section after implementation)

This project was attempted once before and abandoned. That attempt failed
because its live preview called `switch-client` on every keystroke, which
shredded the session toggle and the session history timeline. This spec fixes
that at the architecture level (section 4).

This document is the single source of truth. Build the entire plugin from it.
If any stray files from the earlier attempt happen to exist in the environment,
disregard them. After the implementation lands and is verified, remove this
entire section on the next edit.

## 1. Overview

tmux-livepicker is a modal session and window picker that lives on the status
line and previews candidates live, in place, without leaving the current
session.

When activated, the status bar grows to two lines: line 1 becomes the session
picker (sessions shown where windows normally are), and the user's normal window
status drops to line 2. The full area below the status bar becomes a live
preview of the currently highlighted session, showing all of its panes in their
real layout. The user filters by typing and moves through sessions with the same
keys they normally use to move between windows. Confirming lands on the chosen
session; cancelling restores everything exactly.

The result is a session switcher that is faster and richer than a popup picker,
keeps the user oriented, and never corrupts session history or the toggle.

## 2. Goals and non-goals

### Goals

- Status-line picker: sessions replace windows on line 1, the user's window
  status moves to line 2.
- Live, in-place preview of the highlighted session, showing all panes of its
  active window at once, updating in real time.
- Filter by typing; move through the list with the user's own window-nav keys.
- Reserve every plain letter and digit for the query: navigation, confirm,
  cancel, and backspace use only non-alphanumeric keys, so typing can use the
  full `a`-`z`, `A`-`Z`, `0`-`9` range.
- Create a new session from the typed query when nothing matches, optionally
  opening it in the directory `zoxide` resolves for the query.
- Zero pollution of session history and the session toggle while browsing.
- Full, exact restoration of status layout, key table, and focus on exit.

### Non-goals

- A floating popup UI. The picker is on the status line.
- Previewing more than one window of a session at a time. The preview shows the
  candidate's active window with all its panes.
- Pane-level picking. Sessions and windows only.
- Recency or MRU ordering. tmux default order only.
- Multi-client coordination. The picker serves the invoking client.

## 3. User stories

- I press the activation key. The status bar becomes two lines; the area below
  shows my current session's panes live; the picker lists my sessions with the
  current one highlighted.
- I press my next-window key. The highlight moves to the next session and the
  preview below switches to show that session's panes, live. My history and
  toggle are untouched.
- I type `log`. The list filters to matching sessions; the preview follows the
  top match.
- I press Enter on a match. The picker closes and I am in that session.
- I type `newproj`, see no matches, press Enter. A session named `newproj` is
  created and I am in it. With zoxide mode on, it opens in the directory zoxide
  resolves for `newproj`.
- I press Escape. The picker closes, my status bar is one line again, and I am
  exactly where I was. My window-nav keys move windows again.

## 4. The core rule: preview without switching

The single most important invariant: **browsing the picker must not change the
client's session.**

The earlier attempt previewed by calling `switch-client` for each highlighted
session. Each call fired `client-session-changed`, which the session-history
engine treats as a navigation. N keystrokes produced N navigation entries and
collapsed forward history N times. It also rewrote the previous-session pointer
on every keystroke, breaking the toggle.

This plugin previews by linking the candidate's window into the current session
and selecting it (section 7). The client stays in its session.
`client-session-changed` does not fire while browsing, so history and toggle are
untouched. The only session switch happens once, at confirm.

## 5. Architecture

Three subsystems compose:

- **Status-line picker.** On activate, the status bar grows to two lines. Line 1
  runs a renderer (`#(renderer.sh)`) that draws the filtered session list with
  the current selection highlighted and the query and count shown. The user's
  existing status (windows) drops to line 2.
- **Modal key table.** A dedicated `livepicker` key table receives all input
  while the picker is active. It binds typing, filtering, navigation, confirm,
  and cancel. Because only this table is consulted while active, any key bound
  here is automatically "repurposed" for the duration and reverts for free when
  the table is switched back (section 8).
- **Live preview.** A separate preview routine links the highlighted session's
  active window into the current session and selects it, so all its panes show
  live in the area below the status bar (section 7).

State is held in `@livepicker-*` tmux options for the duration of the picker and
cleared on exit.

### Data flow

```
plugin.tmux
  `- binds prefix + @livepicker-key -> scripts/livepicker.sh (activate)

scripts/livepicker.sh (activate)
  |- guard double-activation
  |- save state (session, window, layout, key table, status, status-format[*],
  |              renumber-windows, session-window-changed hook)
  |- build session list into @livepicker-list
  |- grow status to 2 lines; install picker renderer on line 1
  |- switch key-table to livepicker; bind input keys (incl. repurposed window keys)
  |- set initial selection; run first preview

scripts/input-handler.sh <action> [arg]
  |- type / backspace: update @livepicker-filter; recompute list; refresh status
  |- next-session / prev-session: move @livepicker-index; refresh preview + status
  |- confirm: resolve target; create if needed; switch-client once; restore
  `- cancel: restore everything; switch-client back to original; no history write

scripts/preview.sh <session>
  `- link candidate active window into current session; select it (all panes live)

scripts/renderer.sh
  `- #() status command: draw filtered list with highlight, query, count

scripts/restore.sh <keep|cancel>
  `- unlink preview; restore status, key table, layout, hooks; clear state
```

## 6. Behaviors

### Activation

1. If already active (`@livepicker-mode on`), ignore.
2. Save original state (section 9 lists what is saved).
3. Build the session list: `tmux list-sessions -F '#{session_name}'`.
4. Grow the status bar to two lines and install the renderer (section 7 of the
   status setup below).
5. Switch `key-table` to `livepicker` and bind input keys (section 8).
6. Set the initial selection to the current session and run the first preview.
7. Set `@livepicker-mode on`.

### Filtering

Each typed character appends to `@livepicker-filter` and resets the index to the
top match. Backspace removes the last character. After each change, run
`tmux refresh-client -S` so the status renderer re-evaluates and the picker
redraws. The renderer filters `@livepicker-list` by the query (substring,
case-insensitive) and highlights the item at `@livepicker-index`.

The typeable set is the full `a`-`z`, `A`-`Z`, `0`-`9` plus `-_. /`. Because the
key table is modal (section 8), a key bound to a non-typing action is
intercepted and cannot be typed; navigation, confirm, cancel, and backspace keys
are therefore constrained to non-alphanumeric keys (arrows,
`C-M-Tab`/`C-M-BTab`, `Enter`, `Escape`, `BSpace`).

### Session navigation

`next-session` and `prev-session` move `@livepicker-index` within the filtered
list (wrapping). Each move refreshes the preview (section 7) and the status
renderer. Navigation must not call `switch-client`.

### Confirm

Resolve the target from the filtered list at the current index.

- If a target exists: `switch-client -t "=target"`. One switch. This is the only
  session switch in the whole flow.
- If the filtered list is empty, the type is `session`, and `@livepicker-create`
  is on: create a session from the query, then `switch-client` to it. If
  creation fails (invalid name), cancel instead.
  - Default: `tmux new-session -d -s "<query>"`.
  - With `@livepicker-zoxide-mode` on (mirrors tmux-sessionx's
    `@sessionx-zoxide-mode`): resolve the query through zoxide and start the
    session there — `z_target=$(zoxide query "<query>")`;
    `tmux new-session -d -s "<query>" -c "$z_target" -n "$z_target"`. If zoxide
    returns nothing (dir unindexed, below its frecency threshold, or zoxide
    absent), fall back to the default create above rather than `-c ""`.
- If the type is `window`: `select-window -t "<session>:<window>"`. No new
  session creation in window mode.

Then run `restore.sh keep`, which tears down the picker but leaves the client on
the chosen target.

### Cancel

Run `restore.sh cancel`: unlink the preview, restore the saved status layout and
key table, `select-window` back to the original window, and (because cancel is
not a navigation) `switch-client` back to the original session. Clear all
`@livepicker-*` state.

## 7. The preview subsystem (live, all panes)

This is the defining feature. It must show the candidate session's active window
with all of its panes, live, in the area below the status bar, without switching
sessions.

### Mechanism: link-window plus select-window

A tmux window can be linked into more than one session. A linked window is the
same window object: it renders all of its panes, live, and keeps the same global
window id everywhere it appears.

To preview candidate session `S`:

```
update_preview S:
    if S == current_session:
        tmux select-window -t "$ORIG_WINDOW"      # show own session, no link
        return
    src_id = active window id of S:
        tmux list-windows -t "=$S" -F '#{window_id}' -f '#{window_active}'
    if a previous linked preview exists (track $LINKED_ID):
        tmux unlink-window -t "$CURRENT_SESSION:$LINKED_ID"   # remove from cur; S keeps it
    tmux link-window -a -s "$src_id" -t "$CURRENT_SESSION:"  # link into cur session
    tmux select-window -t "$src_id"                            # show it (all panes, live)
    LINKED_ID = src_id
```

Notes for the implementer:

- The linked window's id equals the source window's id. Track that id; it is the
  handle for unlinking on the next navigation and on exit.
- `unlink-window` removes the window from the current session only. The source
  session keeps its window. Never pass `-k` (that would destroy the window when
  it is linked in only one session; here it is always linked in `S` too).
- Window ids are server-global and survive `renumber-windows on`, so indexing
  churn does not matter. Address windows by id, never by index.
- Use `-t "=S"` (the `=` prefix) for exact session-name matching when reading
  `S`'s active window, to avoid target ambiguity.

### Fallbacks

- If `link-window` fails for any reason, fall back to a snapshot of the active
  pane: `tmux capture-pane -ep -t "=$S"` written into the preview area. This is
  single-pane and not live, but it never blocks the picker.
- If `@livepicker-preview-mode` is `snapshot`, always use `capture-pane` and skip
  linking. If it is `off`, show no preview.
- The default is `live`.

### Self-session edge case

When the highlighted session is the current session, do not link (a session
cannot link its own window into itself). Select the original window so the user
sees their own session as the preview.

### Side effects to suppress

`select-window` fires `session-window-changed`. The user's config runs
`sync-window-focus.sh` on that hook, and rapid preview navigation would fire it
repeatedly. When `@livepicker-suppress-window-hook` is `on` (default), save the
current `session-window-changed` hook, clear it for the duration of the picker,
and restore it on exit.

`select-window` does **not** fire `client-session-changed`, so session history
and the toggle are unaffected regardless.

### Input during preview

While the picker is active, `key-table` is `livepicker`. Keys are looked up in
that table. The safe assumption is that unmatched keys do not fall through to
the underlying window, which would make the preview display-only, but this is
not guaranteed across tmux versions. The implementing agent should verify the
fallthrough behavior; if keys do pass through, bind common keys comprehensively
so input cannot reach the previewed session's panes.

## 8. The repurposed-key subsystem

Requirement: the user's existing next-window and previous-window keys become
next-session and previous-session keys while the picker is active, and revert
when it closes.

### Why this is low-cost

The picker already uses a modal key table. While `key-table` is `livepicker`,
tmux consults only that table. Binding the user's window-nav keys in it makes
them act as session-nav for the duration. On exit, `key-table` returns to its
original value (typically `root`), and the user's original window-nav bindings
take over again. No binding save or restore is needed for the revert.

### Keys

This user's window navigation is bound in the root table:

- Next window: `C-M-Tab` (`bind-key -n C-M-Tab swap-window -t +1 \; select-window -t +1`)
- Previous window: `C-M-BTab`

So the defaults for the session-nav keys match those, so the feature works out
of the box for this config:

- `@livepicker-next-key` default `C-M-Tab`
- `@livepicker-prev-key` default `C-M-BTab`

### Binding

On activate, bind in the `livepicker` table, in this order:

1. A copy of the user's current prefix and root bindings (read
   `tmux list-keys -T prefix` and `tmux list-keys -T root`, rewrite each line's
   table to `livepicker`, and re-bind it) so the rest of their keybinds keep
   working during the picker.
2. Typing: every `a`-`z`, `A`-`Z`, `0`-`9`, and `-_. /` →
   `input-handler.sh type <c>`.
3. Confirm (`@livepicker-confirm-keys`, default `Enter`), cancel
   (`@livepicker-cancel-keys`, default `Escape`), and backspace
   (`@livepicker-backspace-keys`, default `BSpace`).
4. Navigation: `@livepicker-next-key` + `@livepicker-nav-next-keys` (defaults
   `C-M-Tab`, `Down`) → `next-session`; `@livepicker-prev-key` +
   `@livepicker-nav-prev-keys` (defaults `C-M-BTab`, `Up`) → `prev-session`:

```
tmux bind-key -T livepicker "$NEXT_KEY" run-shell "$SCRIPT_DIR/input-handler.sh next-session"
tmux bind-key -T livepicker "$PREV_KEY" run-shell "$SCRIPT_DIR/input-handler.sh prev-session"
```

Load-bearing ordering: tmux keeps the **last** binding for a key in a table, and
step 4 runs after step 2. Any navigation/confirm/cancel/backspace key therefore
**overrides** a typing binding for the same key — which is why those keys must
be non-alphanumeric. An earlier default of `j`/`k` for next/prev left `j` and
`k` silently untypeable: they were bound to `next-session`/`prev-session`, not
`type j`/`type k`, so a query could never contain them. Reserving the full
`a`-`z`, `A`-`Z`, `0`-`9` range for typing (navigating only with the arrows and
the repurposed window-nav keys) removes that shadow. Vim-style `j`/`k`
navigation is still available by setting `@livepicker-nav-next-keys`/
`@livepicker-nav-prev-keys` to include `j`/`k`, accepting that those two letters
are then not typeable.

### Discovery (optional convenience)

A user with different bindings can set `@livepicker-next-key` and
`@livepicker-prev-key` explicitly. As a convenience, if those are unset the
plugin may attempt to discover window-nav keys by parsing `tmux list-keys` for
`next-window`, `previous-window`, and `select-window -t :+` or `:-` patterns.
Discovery is best-effort and must not override explicit options. (It would not
find this user's `swap-window \; select-window` compound binding, which is why
the defaults above are hardcoded to their keys.)

## 9. State saved and restored

On activate, save (all into `@livepicker-orig-*`):

- Current session name and window id.
- Current `window_layout` of the active window (for exact pane restore).
- Current `key-table`.
- Current `status` value (line count) and every set `status-format[n]`.
- Current `renumber-windows` value.
- Current `session-window-changed` hook value (if suppression is on).
- The id of the linked preview window (`@livepicker-linked-id`), initially empty.

On restore (`restore.sh`), in order:

1. Unlink the preview window from the current session if `@livepicker-linked-id`
   is set.
2. `select-window -t "$ORIG_WINDOW"`.
3. If cancel: `switch-client -t "$ORIG_SESSION"` (return to the original
   session). If keep: do not switch (stay on the chosen target).
4. Restore `status`, every `status-format[n]`, `renumber-windows`, `key-table`,
   and the `session-window-changed` hook.
5. `select-layout "$ORIG_LAYOUT"` for the original window.
6. Clear every `@livepicker-*` option and unbind the `livepicker` table.

## 10. Status-line setup

The user's status line is built from `status-left`, `status-right`, and
`window-status-format` (tubular), so `status-format[0]` is unset and composes
from those by default.

Setup on activate:

1. Read the current `status` value and every set `status-format[n]` (indices
   `0` through `9`). Save them.
2. For each set `status-format[n]`, shift it to `status-format[n+1]` (highest
   index first, to avoid overwriting). For tubular this set is empty, so nothing
   shifts and line 2 composes from the default (the user's normal window
   status), which is the desired result.
3. Set `status-format[0]` to `#($SCRIPT_DIR/renderer.sh)`.
4. Set `status` to the new line count (current plus one; typically `2`).

The renderer draws the filtered session list, highlights the selection, and
shows the query and count. After every input action, the handler runs
`tmux refresh-client -S` so the `#()` renderer re-evaluates and redraws.
`refresh-client` forces a status redraw that re-runs `#()` commands, so the
picker updates immediately rather than waiting on `status-interval`.

## 11. Configuration options

All options use the `@livepicker-` prefix.

| Option                             | Default    | Purpose                                                                                                  |
| ---------------------------------- | ---------- | -------------------------------------------------------------------------------------------------------- |
| `@livepicker-key`                  | (required) | Prefix key that activates the picker. If unset, the plugin prints a `display-message` and does not bind. |
| `@livepicker-type`                 | `session`  | `session` or `window`. What the picker lists.                                                            |
| `@livepicker-create`               | `on`       | In session mode, create a new session from the query on Enter when nothing matches.                      |
| `@livepicker-zoxide-mode`          | `off`      | In session mode, when creating on Enter, resolve the query through `zoxide` and start the session there (mirrors `@sessionx-zoxide-mode`); falls back to a plain create if zoxide has no match. |
| `@livepicker-next-key`             | `C-M-Tab`  | Key that moves to the next session. Defaults to this user's next-window key.                             |
| `@livepicker-prev-key`             | `C-M-BTab` | Key that moves to the previous session. Defaults to this user's prev-window key.                         |
| `@livepicker-nav-next-keys`        | `Down`     | Extra next-session keys. Must be non-alphanumeric; a letter/digit here is intercepted and not typeable. |
| `@livepicker-nav-prev-keys`        | `Up`       | Extra previous-session keys. Must be non-alphanumeric; a letter/digit here is intercepted and not typeable. |
| `@livepicker-confirm-keys`         | `Enter`    | Confirm and land on the selection.                                                                       |
| `@livepicker-cancel-keys`          | `Escape`   | Clear the query, or cancel if the query is empty.                                                        |
| `@livepicker-backspace-keys`       | `BSpace`   | Remove the last filter character.                                                                        |
| `@livepicker-preview-mode`         | `live`     | `live` (link-window, all panes), `snapshot` (capture-pane, active pane), or `off`.                       |
| `@livepicker-suppress-window-hook` | `on`       | Clear `session-window-changed` during the picker to avoid focus-resync side effects.                     |
| `@livepicker-fg`                   | `default`  | Picker text color.                                                                                       |
| `@livepicker-bg`                   | `default`  | Picker background.                                                                                       |
| `@livepicker-highlight-fg`         | `black`    | Highlighted (current) item text.                                                                         |
| `@livepicker-highlight-bg`         | `yellow`   | Highlighted item background.                                                                             |
| `@livepicker-show-count`           | `on`       | Show `index/total` in the picker.                                                                        |
| `@livepicker-status-format-index`  | `0`        | Which status line the picker takes.                                                                      |

## 12. File layout

```
tmux-livepicker/
  plugin.tmux                 bind @livepicker-key to activate
  scripts/
    options.sh                get_opt helper and defaults
    utils.sh                  safe tmux option helpers (get/set/unset/save)
    state.sh                  @livepicker-* state get/set/clear
    livepicker.sh             activate: save, build list, install status, bind keys, first preview
    input-handler.sh          type / backspace / next-session / prev-session / confirm / cancel
    preview.sh                link-window live preview (with capture fallback)
    renderer.sh               status-line #() renderer for the picker list
    restore.sh                tear down: unlink, restore status/keys/layout, clear state
```

## 13. tmux primitives reference

The commands the plugin relies on:

- `list-sessions -F '#{session_name}'` to build the list.
- `list-windows -t "=$S" -F '#{window_id}' -f '#{window_active}'` to find a
  session's active window id.
- `link-window -a -s <id> -t <session>:` to link a window into the current
  session.
- `unlink-window -t <session>:<id>` to remove the linked preview window.
- `select-window -t <id>` to show the linked window.
- `capture-pane -ep -t "=$S"` for the snapshot fallback.
- `switch-client -t "=S"` for the single confirm-time session switch.
- `set-option -g status <n>`, `status-format[n]`, `key-table`,
  `renumber-windows`, and `set-hook -g session-window-changed` for setup and
  restore.
- `refresh-client -S` to force the status renderer to re-run after each input.

## 14. Pollution and compatibility analysis

The invariant from section 4, proven:

- **Browsing:** `link-window` and `select-window` operate inside the current
  session. `client-session-changed` does not fire. The `tmux-session-history`
  timeline and `@session-history-prev` pointer are unchanged. Zero entries added.
- **Confirm:** exactly one `switch-client`. The history engine treats it as one
  navigation (forward history collapses, the new session appends at the tip),
  the same way it already treats a tmux-sessionx jump. This is correct,
  browser-like behavior.
- **Cancel:** zero `switch-client` to a different session. History and toggle are
  exactly as before activation.
- **Toggle after confirm:** `prefix L` returns to the session that was active
  before the pick, because only one switch occurred.
- **`session-window-changed`:** fires during preview navigation. Suppressed by
  default (section 7) to avoid running the user's focus hook on every keystroke.

The plugin composes with tmux-sessionx, tmux-resurrect, and tubular without
conflict because it mutates only well-scoped global options and restores them.

## 15. Validation

Implement as a manual checklist plus isolated scripted checks (separate tmux
socket via a `tmux` PATH wrapper, as in the session-history test, so the real
server is untouched).

### Functional

- Activation grows the status bar to two lines; line 1 shows the picker; the area
  below shows the current session's panes live.
- Typing filters the list and updates the highlight.
- `C-M-Tab` / `C-M-BTab` move the session selection; the preview follows live.
- Enter on a match closes the picker and lands on the session.
- Escape closes the picker and returns to the original session and window.

### Pollution (the core invariant)

With `tmux-session-history` installed:

- Browse five sessions, then cancel. Assert `@session-history-hist` is unchanged.
- Browse five sessions, confirm on the fifth. Assert exactly one entry was added.
- After a confirmed pick, the toggle returns to the pre-pick session.

### Live all-panes preview

- A candidate session with a multi-pane window shows all panes in their real
  layout, live, while highlighted.
- Navigating away unlinks the preview; the candidate's window is intact in its
  own session (verified by `list-windows -t` before and after).
- Self-session highlight shows the user's own session without linking.

### Key repurpose

- During the picker, `C-M-Tab` / `C-M-BTab` move sessions.
- After the picker closes, the same keys move windows again.

### Restore

- After exit, `status` and every `status-format[n]` match their pre-activation
  values.
- `key-table`, `renumber-windows`, and the `session-window-changed` hook are
  restored.
- No `@livepicker-*` options remain (`tmux show-options -g | grep livepicker`
  prints nothing).
- The original window's pane layout is exact (`select-layout` to the saved
  layout).

### Create-on-enter

- Session mode, no match, Enter: session created and active.
- `@livepicker-create off`: nothing created.
- Window mode: nothing created.
- `@livepicker-zoxide-mode on` + no match + Enter (session mode): the new
  session's starting directory (`#{pane_start_path}`) equals
  `zoxide query "<query>"`. Not covered by the isolated socket suite: zoxide's
  database is global, and a freshly indexed dir will not surface in a basename
  query until it crosses zoxide's frecency threshold, so a hermetic in-suite
  fixture cannot reliably resolve. Verify manually against an established
  zoxide entry (create, assert `pane_start_path`, kill).

## 16. Implementation risks and notes

- **link-window edge cases.** Linking can fail if the source is already linked
  into the current session or if the target is invalid. Always unlink the
  previous preview first, and fall back to `capture-pane` on any link error.
- **Window addressing.** Use window ids, not indices. `renumber-windows on` makes
  indices unstable.
- **Status renderer refresh.** The `#()` renderer only re-runs on status redraw.
  Every input action must call `refresh-client -S`. Verify the renderer updates
  within 100 ms of a keystroke.
- **Key fallthrough.** Confirm whether unmatched keys in the `livepicker` table
  are dropped or passed to the previewed pane. If passed, bind common keys so no
  input leaks into the candidate session.
- **Navigation keys must be non-alphanumeric.** In the modal `livepicker` table
  the navigation/confirm/cancel/backspace binds run after the typing binds, so a
  key in any of those lists overrides its typing binding. A plain letter or
  digit used for navigation is therefore silently untypeable. Keep those keys
  non-alphanumeric (arrows, `C-M-Tab`/`C-M-BTab`, `Enter`, `Escape`, `BSpace`);
  vim-style `j`/`k` is opt-in via `@livepicker-nav-*-keys`.
- **zoxide dependency.** `@livepicker-zoxide-mode` shells out to `zoxide query`.
  If `zoxide` is absent or returns no match, the create path falls back to a
  plain `new-session` (never `-c ""`). zoxide resolves only dirs it has indexed
  with sufficient frecency, so a one-off `zoxide add` of a temp dir will not
  surface in a basename query.
- **Hook suppression scope.** Clearing `session-window-changed` is global for the
  duration. Restore it exactly on exit, including the `-b` flag if present.
- **Double activation.** Guard with `@livepicker-mode`. A second activation
  while active is ignored.
- **tmux floor.** `link-window`, multi-line `status`, and `set-hook` require
  tmux 3.0 or newer. `-f '#{window_active}'` filtering on `list-windows` is
  available on 3.0+. Target 3.0 as the floor; test on the installed 3.6b.
- **Live Testing** Testing must _always_ be performed in an isolated tmux session
  to avoid conflicting with the user's live, running instance. When a final real
  -world test must be performed, it is critical to ensure that the user's
  initial state be returned upon completion.
