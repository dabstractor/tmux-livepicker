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
- Look like the user's own window tabs, not a foreign overlay: reuse the theme's
  window-status appearance (colors, shape, separators, alignment) so the picker
  reads as part of the status bar under any theme (section 17).
- Live, in-place preview of the highlighted session, showing all panes of its
  active window at once, updating in real time.
- Interaction feedback first: the status line redraws and the highlight moves
  the instant a key is pressed; the live preview is deferred (it is inherently
  slow) and must never block typing, navigation, or confirm (section 18).
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
- Recency or MRU (time-based) ordering. The empty-query order stays tmux
  default; with a query active, sessions are reordered by fuzzy similarity
  (section 20), never by access time.
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
- The picker tabs look identical to my window tabs — same colors, shape, and
  separators — because the picker reuses my theme's own window-status styling
  (section 17).
- I hit the keybind and type three letters and press Enter, all in about 100ms.
  I land in the session without ever perceiving lag or jank — and without ever
  seeing a preview. The status line kept up with every keystroke and Enter did
  not wait on a preview (section 18).
- I press Escape. The picker closes, my status bar is one line again, and I am
  exactly where I was. My window-nav keys move windows again.
- I open the picker. My status bar shows just my session tabs where windows
  normally are, justified the way my theme sets them (centred, for me). There is
  no search box, no `query>` label, no index/total numbers — nothing extra until
  I act.
- I type `log`. A magnifier icon and my query snap to the far-left edge, two
  spaces, then my sessions re-order so the best match (`logs-prod`) is first and
  previewed live. The further I type, the tighter the ranking gets; non-matches
  vanish.
- I have 40 sessions. The ones that don't fit get a `+12>` on the right telling
  me how many are off-screen. When I arrow over, they scroll into view and a `<`
  appears on the left so I know there are more behind me. That `12` is the total
  hidden, not split by side; there are no other numbers anywhere.
- I press `Ctrl-r` on a session. tmux's rename prompt opens pre-filled with the
  current name; I type a new one, press Enter, and the tab updates in place. The
  picker stays open and the highlight stays on the renamed session.
- I press `Alt-Backspace` on a session. It is killed and drops off the list; the
  next session is highlighted and previewed. My own session can't be deleted
  from inside the picker.
- I open the picker and the status grows to two lines, but nothing on screen
  reflows or flickers — the live preview keeps its size and just hides its
  bottom row behind the status. Typing and tabbing stay smooth.

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
  runs a renderer (`#(renderer.sh)`) that draws the query bar pinned to the
  far-left edge (a nerd-font search icon plus the query, shown only once the
  user starts typing), then the **ranked** session tabs in a **scrollable
  viewport** with overflow indicators (`+N>` on the right, `<` on the left). The
  `index/total` count indicator is gone. The user's existing status (windows)
  drops to line 2. Full layout spec: section 19; ranking: section 20.
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
  |- capture client width into @livepicker-client-width; install client-resized hook (section 19)
  |- freeze driver window-size=manual (@livepicker-preview-fit clip; section 22)
  |- grow status to 2 lines; install picker renderer on line 1
  |- switch key-table to livepicker; bind input keys (incl. repurposed window keys
  |    + rename/delete management keys, section 21)
  |- set initial selection (index 0, scroll 0); run first preview

scripts/input-handler.sh <action> [arg]
  |- type / backspace: update @livepicker-filter; rank; reset index=0 + scroll=0; refresh status FIRST, then defer a preview to the top match (section 18)
  |- next-session / prev-session: move @livepicker-index; refresh status FIRST (highlight moves); scroll-into-view (section 19); defer the preview
  |- confirm: resolve target from ranked list; create if needed; switch-client once; restore
  |- cancel: clear the query (reset index+scroll); or restore everything if query already empty
  `- rename / delete: delegate to scripts/session-mgmt.sh (section 21)

scripts/session-mgmt.sh <rename|delete|do-rename|do-delete> [arg]
  `- rename via tmux command-prompt; delete via kill-session (optionally confirm-before);
     guards (driver/last-session/linked-window leak); rewrite list + re-rank + re-sync preview

scripts/preview.sh <session>
  `- link candidate active window into current session; select it (all panes live)

scripts/renderer.sh
  `- #() status command: query bar (far left) + ranked tabs in a scroll viewport + overflow indicators (section 19/20); re-evaluated ASYNC by the server on refresh-client -S (never blocks the keystroke). Reads dynamic state (list/filter/index/scroll/width) live; caches static config once at activation (@livepicker-render-cache) and measures tab width fork-free, so the redraw stays within the section 16 budget (~60ms on a ~15-session list)

scripts/rank.sh (sourced lib)   — lp_rank: fuzzy subsequence match + score (section 20); sourced by renderer + input-handler + session-mgmt (single source of truth)
scripts/layout.sh (sourced lib) — lp_viewport: tab-width measurement + scroll-into-view math (section 19); sourced by renderer + input-handler

scripts/restore.sh <keep|cancel>
  `- unlink preview; restore status, key table, window-size, layout, hooks (incl. client-resized); clear state
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

### Filtering and ranking

Each typed character appends to `@livepicker-filter`; backspace removes the
last character. After each change the handler sets `@livepicker-index` and
`@livepicker-scroll` to `0` (top-ranked match, viewport at the far left) and
runs `tmux refresh-client -S` so the status renderer re-evaluates and the
picker redraws.

The renderer no longer does a plain case-insensitive substring filter. It calls
the shared `lp_rank` (section 20, `scripts/rank.sh`): a session matches iff the
query is a **subsequence** of its name (chars in order, case-insensitive);
matches are **scored** (prefix > word-boundary > contiguous > early-position)
and sorted best-first; **non-matches are hidden entirely** (so create-on-empty
still fires, section 6 Confirm). The top-ranked match is index 0 and is what the
preview follows. Empty query matches all at score 0 in original tmux order (no
reordering — honours the section 2 non-goal).

The status redraw is the only synchronous work on the typing path. The live
preview is re-synced in the background, never inline, so a keystroke never waits
on `link-window`/`select-window` (section 18).

The typeable set is the full `a`-`z`, `A`-`Z`, `0`-`9` plus `-_. /`. Because the
key table is modal (section 8), a key bound to a non-typing action is
intercepted and cannot be typed; navigation, confirm, cancel, backspace, and
the management keys (rename/delete) are therefore constrained to
non-alphanumeric keys (arrows, `C-M-Tab`/`C-M-BTab`, `Enter`, `Escape`,
`BSpace`, `C-r`, `M-BSpace`).

### Session navigation

`next-session` and `prev-session` move `@livepicker-index` within the ranked
list (wrapping). After the move, the handler runs the **scroll-into-view** rule
(section 19): if the new highlight falls outside the viewport, advance/retreat
`@livepicker-scroll` until the highlighted tab is visible. Each move redraws
the status immediately; the preview re-sync is deferred to the background so
the highlight tracks the keypress with no lag (section 18). Navigation must not
call `switch-client`.

### Confirm

Resolve the target from the ranked list (section 20) at the current index.

- If a target exists: `switch-client -t "=target"`. One switch. This is the only
  session switch in the whole flow.
- If the ranked list is empty, the type is `session`, and `@livepicker-create`
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

### Scrolling and overflow (status layout)

Behaviour summary; the precise layout/viewport math is section 19. The session
tabs render left-to-right in a viewport whose width is `cached client width −
query block − indicators`. When the ranked tabs overflow that width:

- a right indicator `+N>` appears, where `N` is the **total** number of hidden
  tabs (left-hidden + right-hidden combined);
- once the user scrolls right (`@livepicker-scroll > 0`), a left indicator `<`
  appears (presence only, no count);
- both can show at once (`< …tabs… +N>`); neither shows when everything fits.

The query bar (icon + query) and the overflow indicators are independent: the
query bar shows only while a query is active; the overflow indicators show
whenever tabs overflow, query or not. The `index/total` count never shows.

### Session management (rename / delete)

Behaviour summary; full spec in section 21. Two management keys, both acting on
the highlighted (and previewed) session:

- Rename (`@livepicker-rename-key`, default `C-r`): open tmux's `command-prompt`
  pre-filled with the current name; on submit, `rename-session`, rewrite the
  list entry, keep the highlight on it, refresh. The picker stays open.
- Delete (`@livepicker-delete-key`, default `M-BSpace`): guard against killing
  the driver session or the last session, unlink the preview window first if it
  belongs to the target (kill-session otherwise leaks it into the driver), then
  `kill-session`, rewrite the list, re-rank, re-sync the preview.

Both keys are control keys (not letters/digits), so they never collide with the
typing set.

## 7. The preview subsystem (live, all panes)

This is the defining feature. It must show the candidate session's active window
with all of its panes, live, in the area below the status bar, without switching
sessions.

This section describes *how* a preview is produced. Section 18 specifies *when*:
previews are deferred relative to input, so they never block typing or
navigation.

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

### Sizing: clip, don't reflow

The live preview is a shared, linked window (above). When the status grows to
two lines (section 10) the client pane area shrinks by one row; by default
(`@livepicker-preview-fit clip`, section 22) the driver's `window-size` is set
to `manual` first, so the preview window keeps its full height and its bottom
row is **clipped** instead of reflowed — eliminating the status-grow jank. The
window's panes are never resized on the typing/nav path. See section 22 for the
mechanism, the `reflow` fallback, and the empirical verification it requires.

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

5. Session management (section 21): `@livepicker-rename-key` (default `C-r`) →
   `rename`; `@livepicker-delete-key` (default `M-BSpace`) → `delete`:

```
tmux bind-key -T livepicker "$RENAME_KEY" run-shell "$SCRIPT_DIR/input-handler.sh rename"
tmux bind-key -T livepicker "$DELETE_KEY" run-shell "$SCRIPT_DIR/input-handler.sh delete"
```

Load-bearing ordering: tmux keeps the **last** binding for a key in a table, and
steps 4 and 5 run after step 2. Any navigation/confirm/cancel/backspace/
rename/delete key therefore **overrides** a typing binding for the same key —
which is why those keys must be non-alphanumeric (control keys like `C-r` and
`M-BSpace` are fine: they are distinct tmux keys from the letters `r` and
backspace). An earlier default of `j`/`k` for next/prev left `j` and `k`
silently untypeable: they were bound to `next-session`/`prev-session`, not
`type j`/`type k`, so a query could never contain them. Reserving the full
`a`-`z`, `A`-`Z`, `0`-`9` range for typing (navigating only with the arrows and
the repurposed window-nav keys, managing with `C-r`/`M-BSpace`) removes that
shadow. Vim-style `j`/`k` navigation is still available by setting
`@livepicker-nav-next-keys`/ `@livepicker-nav-prev-keys` to include `j`/`k`,
accepting that those two letters are then not typeable.

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
- Current `window-size` of the driver session (frozen to `manual` in clip mode;
  section 22).

On restore (`restore.sh`), in order:

1. Unlink the preview window from the current session if `@livepicker-linked-id`
   is set.
2. `select-window -t "$ORIG_WINDOW"`.
3. If cancel: `switch-client -t "$ORIG_SESSION"` (return to the original
   session). If keep: do not switch (stay on the chosen target).
4. Restore `status`, every `status-format[n]`, `renumber-windows`, `key-table`,
   the `session-window-changed` hook, the `client-resized` hook, and the driver's
   `window-size` (section 22).
5. `select-layout "$ORIG_LAYOUT"` for the original window.
6. Clear every `@livepicker-*` option (this MUST include the new runtime keys
   `@livepicker-scroll` and `@livepicker-client-width` — add them to
   `_STATE_RUNTIME_KEYS` in `state.sh`) and unbind the `livepicker` table.

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
4. When `@livepicker-preview-fit` is `clip` (default), set the driver session's
   `window-size` to `manual` **first** (section 22), then set `status` to the
   new line count (current plus one; typically `2`) so the preview clips its
   bottom row instead of reflowing. When `reflow`, skip the freeze and just set
   `status`.
5. Capture the invoking client's width into `@livepicker-client-width` via
   `tmux display-message -p '#{client_width}'` (resolved against the client
   that triggered activation), and install a `client-resized` hook that
   refreshes `@livepicker-client-width` for the duration of the picker. Save
   any prior `client-resized` hook and restore it on exit (mirror the
   `session-window-changed` save/restore). This cache is what the renderer
   measures the viewport against, so the per-keystroke render path makes **no**
   `tmux` round-trip for the width (section 18).

The renderer draws the query bar (far left, icon + query, only while typing),
the ranked session tabs in a scrollable viewport, and the overflow indicators;
it never draws an `index/total` count. Full layout: section 19; ranking:
section 20. After every input action, the handler runs `tmux refresh-client -S`
so the `#()` renderer re-evaluates and redraws. `refresh-client` forces a status
redraw that re-runs `#()` commands, so the picker updates immediately rather
than waiting on `status-interval`.

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
| `@livepicker-rename-key`           | `C-r`      | Rename the highlighted session via tmux's prompt (section 21). Control key; never collides with typing.  |
| `@livepicker-delete-key`           | `M-BSpace` | Delete (kill) the highlighted session (section 21). Matches sessionx's `@sessionx-bind-kill-session`.        |
| `@livepicker-confirm-delete`       | `off`      | When `on`, prompt `y/n` before killing a session (`confirm-before`). Default `off` = immediate, sessionx-style. |
| `@livepicker-preview-mode`         | `live`     | `live` (link-window, all panes), `snapshot` (capture-pane, active pane), or `off`.                       |
| `@livepicker-preview-defer`        | `on`       | Defer the live preview to the background so it never blocks typing/nav/confirm (section 18); `off` restores the synchronous path. |
| `@livepicker-preview-fit`          | `clip`     | How the preview yields the row the extra status line needs: `clip` (default) freezes the preview's height via `window-size manual` so its bottom row is clipped with no reflow (section 22); `reflow` resizes it (legacy, may jank). |
| `@livepicker-suppress-window-hook` | `on`       | Clear `session-window-changed` during the picker to avoid focus-resync side effects.                     |
| `@livepicker-tab-style`            | `plain`    | `plain` (standalone fg/bg highlight) or `window-status` (reuse the theme's window-status-current-format/`window-status-format` so picker tabs match the user's window tabs; section 17). |
| `@livepicker-fg`                   | `default`  | Picker text color.                                                                                       |
| `@livepicker-bg`                   | `default`  | Picker background.                                                                                       |
| `@livepicker-highlight-fg`         | `black`    | Highlighted (current) item text.                                                                         |
| `@livepicker-highlight-bg`         | `yellow`   | Highlighted item background.                                                                             |
| `@livepicker-status-format-index`  | `0`        | Which status line the picker takes.                                                                      |
| `@livepicker-nerd-fonts`           | `on`       | tmux cannot detect the terminal font, so this is opt-out. `on` (default) shows the search icon; `off` shows query text only. |
| `@livepicker-search-icon`          | `\uf002`   | The icon glyph shown before the query while typing (section 19). Default is `nf-fa-search` (U+F002). Raw UTF-8 bytes. |
| `@livepicker-query-gap`            | `2`        | Spaces between the query and the first session tab while a query is active (section 19).                  |
| `@livepicker-overflow-left`        | `<`        | Left overflow indicator (presence only; shown when `@livepicker-scroll > 0`).                            |
| `@livepicker-overflow-right-format`| `+%d>`     | Right overflow indicator; `%d` = total hidden tabs (left + right combined). Section 19.                   |

## 12. File layout

```
tmux-livepicker/
  plugin.tmux                 bind @livepicker-key to activate
  scripts/
    options.sh                get_opt helper and defaults
    utils.sh                  safe tmux option helpers (get/set/unset/save)
    state.sh                  @livepicker-* state get/set/clear
    livepicker.sh             activate: save, build list, install status, bind keys, first preview
    input-handler.sh          type / backspace / next-session / prev-session / confirm / cancel / rename / delete
    preview.sh                link-window live preview (with capture fallback)
    renderer.sh               status-line #() renderer: query bar + ranked tabs in a scroll viewport + overflow indicators
    rank.sh                   sourced lib: lp_rank fuzzy subsequence match + score (section 20)
    layout.sh                 sourced lib: lp_viewport tab-width measurement + scroll-into-view math (section 19)
    session-mgmt.sh           rename (command-prompt) / delete (kill-session) on the highlighted item (section 21)
    restore.sh                tear down: unlink, restore status/keys/layout/hooks, clear state
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
- `display-message -p '#{client_width}'` (resolved against the invoking
  client) to capture the viewport width into `@livepicker-client-width` at
  activation; a `set-hook client-resized` hook refreshes it on resize.
- `rename-session -t "=S" "NEW"` and `kill-session -t "=S"` for the management
  keys (section 21); in window mode, `rename-window` / `kill-window`.
- `set-option -t "$SESSION" window-size manual` (and `resize-window -y H`) to
  freeze the preview's height so the status grow clips its bottom row instead
  of reflowing it (section 22).
- `command-prompt -I "<old>" -p "<prompt>" "run-shell '<script> %%'"` to read
  the new session name, and `confirm-before -p "<prompt>" "<cmd>"` for the
  optional delete confirmation (section 21).
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
- Clip sizing (`@livepicker-preview-fit clip`): on activation the status grows
  to two lines but the preview's panes do **not** reflow — its bottom row is
  clipped; navigating between candidates re-links without per-nav reflow. After
  exit, the driver's `window-size` is restored and the panes return to their
  natural size. (If empirical testing shows tmux force-resizes instead of
  clipping, `reflow` is the documented fallback.)

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

### Responsiveness

- The per-keystroke wall-clock on the typing path is dominated by the renderer,
  not by `link-window`/`select-window`: assert that typing a character redraws
  the status with the new query before any preview work runs.
- Rapid input then confirm: three keystrokes within ~100 ms followed immediately
  by Enter lands on the correct target, renders no preview, and queues no
  backlog of preview re-links.
- A preview whose target was superseded by a newer selection is a no-op: it does
  not unlink/link a stale window and does not clobber the newer link.
- Navigation moves the highlight visibly before the preview catches up.

### Appearance (window-status hijack)

- With `@livepicker-tab-style window-status`, the highlighted item matches the
  user's `window-status-current-format` and the others match
  `window-status-format` (same colors/shape); the inter-item gap matches
  `window-status-separator`. `status-justify` positions the tabs only when there
  is no query and the tabs fit; otherwise the section 19 viewport rules apply
  (query pinned left, tabs left-to-right, overflow indicators).
- If a format is empty or unresolvable, the renderer falls back to `plain`.

### Layout, ranking, scroll, and management

- On open (empty query) line 1 shows only the session tabs, positioned per
  `status-justify`; there is no icon, no query, no `query>` label, and no
  `index/total` count anywhere.
- Typing one char shows `<icon><query>` at column 0, then exactly two spaces,
  then the ranked tabs left-to-right; the top-ranked match is highlighted and
  previewed live.
- Ranking: with query `log`, `logs-prod` outranks `blog-engine` (prefix beats a
  deep subsequence); a name that is not a subsequence of the query is hidden.
  Empty query preserves tmux order (no reordering).
- Overflow: with more tabs than fit, a `+N>` appears on the right where `N` =
  total hidden; navigating past the right edge scrolls the highlight into view
  and a `<` appears on the left; when everything fits, neither indicator shows.
- Rename (`C-r`): the tmux prompt opens pre-filled; a new name updates the tab in
  place and keeps the highlight on it; the picker stays open.
- Delete (`M-BSpace`): the highlighted session is killed and removed from the
  list; a neighbour is highlighted and previewed; the driver session and the
  last remaining session refuse with a message and no kill.
- Width cache: resizing the client updates `@livepicker-client-width` (via the
  `client-resized` hook) and the next redraw recomputes the viewport; after exit
  the prior `client-resized` hook is restored exactly.

## 16. Implementation risks and notes

- **link-window edge cases.** Linking can fail if the source is already linked
  into the current session or if the target is invalid. Always unlink the
  previous preview first, and fall back to `capture-pane` on any link error.
- **Window addressing.** Use window ids, not indices. `renumber-windows on` makes
  indices unstable.
- **Status renderer refresh.** The `#()` renderer only re-runs on status redraw.
  Every input action must call `refresh-client -S`. Verify the renderer updates
  within 100 ms of a keystroke.
- **Deferred-preview concurrency.** A background preview must be superseded, not
  queued: track a pending target/sequence and discard a late result so a stale
  `unlink-window`/`link-window` never clobbers the current link. Confirm reads
  authoritative filter/index state and must not depend on a preview having run.
- **Window-status hijack fragility.** `#{…}` in a theme format is not re-expanded
  in `#()` output — it must be pre-resolved (sentinel window + `display-message`,
  section 17). Window-state specifiers (`#F`, pane/bell/prefix icons) resolve to
  the sentinel's state, not the session's; verify they collapse to a clean tab.
  Fall back to `plain` on any resolution failure.
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
- **Viewport measurement.** Tab display width must be measured with `#[…]`
  style directives stripped first (they occupy zero columns but inflate the raw
  string length). The measurement lives once in `scripts/layout.sh` and is used
  by both the renderer (to slice the visible window) and the input-handler (to
  scroll-into-view) so they cannot disagree. Re-derive the slice every redraw;
  measure width FORK-FREE (`_lp_measure_into` — a subshell per tab would
  dominate the redraw cost); clamp `@livepicker-scroll` to 0 when the list now fits.
- **Fuzzy ranking cost.** `lp_rank` is O(N·Q) per redraw in pure bash; verify it
  stays under the section 18 renderer budget for N up to a few hundred. The
  ranker needs no caching (sourced once per process, no per-name subshells). Note
  the renderer separately caches its STATIC `@livepicker-*` config once at
  activation (`@livepicker-render-cache`): each `tmux show-option` forks a client
  (~3–4 ms), so reading ~10 of them per redraw would otherwise bust the budget.
- **`command-prompt` substitution.** The rename template uses `%%` inside a
  single-quoted `run-shell`; names containing `'`, `"`, `` ` ``, or `$` can
  break the substitution. tmux rejects `:` in session names and sanitizes
  others, so this is rare — but detect a sanitized result (exact name ≠ input)
  and `display-message` rather than silently renaming under a different name.
- **`kill-session` + linked preview leak.** A window linked into the driver as
  the preview SURVIVES `kill-session` of its source (it is still linked into the
  driver). Before killing the highlighted session, if its window id ==
  `@livepicker-linked-id`, `unlink-window` it from the driver first, else the
  preview window leaks into the driver as a permanent orphan.
- **Delete key terminal caveat (minor).** `@livepicker-delete-key` defaults to
  `M-BSpace` (sessionx's `@sessionx-bind-kill-session`), which most terminals
  send reliably. A few terminals or SSH/mosh links strip Alt-modified keys; if
  delete does not fire there, rebind to `C-h` or `DC` (Delete). Document in the
  README.
- **Width cache staleness.** `@livepicker-client-width` is captured at
  activation and refreshed only by the `client-resized` hook. The hook must
  target the invoking client, and restore must put back the exact prior hook;
  otherwise a detach/reattach or multi-client width mismatch leaves the viewport
  stale.
- **Preview clip feasibility (load-bearing, section 22).** The no-jank clip
  relies on tmux showing an oversized `window-size manual` window **clipped**
  rather than force-resizing it, for a window that is **shared with its source
  session**. This is subtle and version-dependent: the single shared size is
  influenced by every session/client the window is linked into, so a smaller
  client on the source could still drag the size down. Verify on 3.6b that (a) a
  manual session clips an oversized active window at the bottom, (b)
  `window-size -t` isolates to the driver (else save/restore globally), and (c)
  a linked-from-elsewhere window clips in the driver without disturbing the
  source. If any fails, fall back to `@livepicker-preview-fit reflow` or
  `@livepicker-preview-mode snapshot`.
- **Live Testing** Testing must _always_ be performed in an isolated tmux session
  to avoid conflicting with the user's live, running instance. When a final real
  -world test must be performed, it is critical to ensure that the user's
  initial state be returned upon completion.

## 17. Tab appearance — reuse the window-status format

**Requirement.** The picker must look like the user's own window tabs, not a
foreign element drawn on top of the status bar. Rather than ship its own styling
(which would either ignore the user's theme or special-case each one), the
renderer reuses tmux's standard, themeable window-status appearance — the same
system every tmux theme (tubular, catppuccin, gruvbox, plain) already
configures.

**The official tokens.** tmux exposes window-tab appearance through two layers:

- **Formats** (the full tab template — structure, colors, icons, the works):
  - `window-status-current-format` — the active window tab.
  - `window-status-format` — inactive window tabs.
- **Styles** (color/attribute only): `window-status-current-style`,
  `window-status-style` (+ `-last`, `-activity`, `-bell`).

The picker hooks the **format** layer. The style layer alone is insufficient:
themes like tubular set both styles to the same bar color and put the entire
visual distinction (the rounded pill) into the *format*. Reading only the styles
would make the highlighted item indistinguishable from the rest under such
themes. Reading the formats reproduces the exact tab — pill, caps, colors, icons
— for any theme.

**Mapping.** The highlighted picker item renders through
`window-status-current-format`; every other item renders through
`window-status-format`. The inter-item gap is `window-status-separator`. The
whole line honors `status-justify` (`absolute-centre` → centred), so the picker
sits where the rest of the status content does.

**The `#{…}` wrinkle (load-bearing).** Theme formats contain `#{…}` expansions
(e.g. tubular's `#{E:@tubular_pill_bg}`) and window-state specifiers (`#W` name,
`#F` flags, `#{window_panes}`, bell/prefix icons). Two facts constrain the
implementation:

1. A `#()` status command's stdout is **not** re-parsed for `#{…}` — only
   `#[…]` style directives are applied. The formats therefore cannot be emitted
   verbatim from the renderer; their `#{…}` must be expanded first.
2. The window-state specifiers are window-context, but picker items are sessions
   — there is no window whose name is the session name to render against.

**Resolution: the sentinel window.** At activation, spin up one short-lived
hidden window whose name is a unique placeholder (e.g. `__lp_tab__`), resolve
both formats against it with `tmux display-message -p -t <sentinel> "$format"`,
and cache the two rendered templates. Resolution expands every `#{…}` to
concrete `#[fg=#hex…]` styles and bakes the placeholder name into the styled
output; window-state bits resolve to a clean single-pane, no-bell, non-prefix
tab (which is exactly what a picker row should show). Kill the sentinel. The
renderer then only swaps the placeholder → each session name and emits the
cached templates; there is **no per-keystroke `display-message`**, so this stays
fast (it composes with the §18 responsiveness contract).

**Control.** `@livepicker-tab-style` selects the mode:

- `plain` (default): standalone `@livepicker-fg`/`bg`/`highlight-*` coloring
  (current behavior; no theme dependency).
- `window-status`: the format hijack above.

**Fallback.** If either format is empty, unresolvable, or the sentinel step
fails, fall back to `plain` so the option never breaks a setup.

## 18. Responsiveness — interaction-first, deferred preview

**Requirement.** Input feedback is the top priority; the live preview is a
nice-to-have that must never get in its way. Concretely: opening the picker,
typing several characters rapidly, and confirming must all feel instantaneous —
the status line tracks every keystroke as it happens, and confirm does not wait
on a preview. The user may open, type three letters within ~100 ms, press Enter,
and land in the new session **without ever seeing lag, jank, or even a preview**,
because previewing is inherently slow and is therefore decoupled from the input
path.

**Root cause being addressed.** Today every keystroke runs synchronously: append
to the filter, then `_lp_sync_preview_to_top_match` (an `unlink-window` +
`link-window` + `select-window` round-trip), then `refresh-client -S`. The
preview re-link is the expensive part and it blocks the status redraw, so each
letter waits on the previous letter's preview. Navigation has the same shape.
This is why fast typing and quick tab moves feel laggy.

**A second root cause: the redraw itself.** Deferring the preview is necessary
but not sufficient — the status redraw that tracks each keystroke is itself a
`#()` renderer process, and its cost dominates perceived latency (validation
section 3.26 asserts exactly this). Every `tmux show-option` in the renderer
forks a client (~3–4 ms), so re-reading ~10 static `@livepicker-*` options per
redraw *plus* a per-tab subshell in the width pass made each redraw ~200 ms on a
modest list — well over the section 16 budget. The renderer therefore caches its
static config once at activation (`@livepicker-render-cache`, one read per redraw
with a fresh-read fallback) and measures tab width fork-free (`_lp_measure_into`),
bringing the redraw back under budget (~60 ms on a ~15-session list, A/B vs ~200 ms).

**The contract.**

1. **Typing path is status-first, then a deferred preview.** A typed/backspaced
   character updates `@livepicker-filter` and resets index+scroll synchronously,
   then calls `refresh-client -S` *immediately* so the status reflects the new
   query before anything else; it then defers a preview to the new top match (the
   preview "follows live", section 3) on a supersedeable background job — never
   inline, never blocking. The status redraw is the latency-priority step, and it
   stays fast only because the renderer's static `@livepicker-*` config is cached
   once at activation (`@livepicker-render-cache`) and its tab-width pass is
   fork-free (see the second-root-cause note above).
2. **Navigation moves the highlight synchronously, defers the preview.**
   `next-session`/`prev-session` update `@livepicker-index` and call
   `refresh-client -S` *immediately* — before the scroll-catchup and the deferred
   preview fire — so the highlight moves first; the preview re-sync is scheduled,
   not inline.
3. **The preview is deferred and supersedeable.** Preview work runs in the
   background (`tmux run-shell -b`), not inline in the input handler. It is
   **superseded, not queued**: if a new keystroke/selection arrives before the
   pending preview runs, the pending one is cancelled (or its result discarded)
   and the latest target wins. The preview always chases the current selection
   and never accumulates a backlog. A short debounce may gate the background
   fire so a burst of typing collapses to a single trailing preview.
4. **Confirm does not block on the preview.** Resolving the target,
   creating/switching, and tearing down proceed from the authoritative
   filter/index state the moment Enter is pressed — independent of whether a
   preview has rendered. The “type and Enter before any preview” path is a
   first-class success case, not an edge case.

**Mechanism notes.**

- tmux has no threads; “background” means `run-shell -b` (a detached command)
  plus a lightweight pending-token/sequence check so a late preview whose target
  has been superseded is a no-op (it must not unlink/link a stale window, and
  must not clobber a newer link).
- The activation-time first preview may stay synchronous (activation is not
  latency-sensitive).
- Because the preview is no longer synchronous, the `session-window-changed`
  suppression (section 7) still applies, but the *rate* of hook fires is
  naturally bounded by debounce, easing that concern.

**Control.** `@livepicker-preview-defer` (default `on`) toggles this behavior;
`off` restores the legacy synchronous-preview path (useful for comparison or
diagnosis).

**Non-goal.** This is not about making the preview itself faster —
`link-window`/`select-window` are irreducible server round-trips. It is about
never making the user wait for them.

## 19. Status-line layout: query bar, viewport, overflow

This section is the single source of truth for what line 1 looks like, for
**both** `plain` and `window-status` tab styles (section 17). It replaces the
earlier "query and count shown at the line end" behavior. The `index/total`
count indicator is removed entirely.

### Two independent visibility rules

- **The query bar** (icon + query) is shown **only while the query is
  non-empty**. On open / after the query is cleared, there is no icon, no query
  text, and no gap — line 1 shows only the session tabs.
- **The overflow indicators** (`+N>` / `<`) are shown **whenever the tab region
  overflows the available width**, query or not.

These two are independent; do not conflate them.

### Query empty (open, or cleared)

Line 1 shows only the session tabs, positioned per `status-justify`
(`left` / `centre` / `right` / `absolute-centre`) exactly like normal window
tabs. No icon, no query, no gap, no count.

- If the tabs fit: they are justified per `status-justify`.
- If the tabs overflow: justification becomes moot (every column is occupied);
  the tabs flow left-to-right from column 0 and the overflow indicators below
  apply.

### Query active (≥1 character typed)

```
column 0:  <icon><query><gap><tabs left-to-right, windowed by scroll><optional +N>>
```

- `<icon>` = `@livepicker-search-icon` (default U+F002 `nf-fa-search`) if
  `@livepicker-nerd-fonts` is `on` (the default), else empty. tmux cannot detect
  the terminal's font, so nerd-font support is opt-out. Emit the glyph as raw
  UTF-8 bytes.
- `<query>` = the raw query string from `@livepicker-filter`, with every `#`
  doubled (`##`) so tmux renders it literally and does not parse `#[…]` styles
  the user may have typed.
- `<gap>` = exactly `@livepicker-query-gap` spaces (default `2`), regardless of
  `status-justify`. While a query is active, `status-justify` is suspended for
  the tabs (the pinned query and the left-to-right tab flow are required for the
  scroll viewport).
- `<tabs>` = the ranked+filtered list (section 20), sliced to the viewport by
  `@livepicker-scroll`. Tabs are joined by `window-status-separator` in
  `window-status` mode, or a single space in `plain` mode.

### The viewport and scroll

- Available tab width `T` = `@livepicker-client-width` − width(query block) −
  width(active indicators). The query block width is `len(icon) + len(query) +
  gap`; recompute it every redraw because the query length changes as the user
  types.
- Measure each tab's **display width** with `#[…]` style directives stripped
  first (they are zero-width but inflate the raw string). This measurement lives
  in `scripts/layout.sh` (`lp_viewport`), sourced by both the renderer and the
  input-handler so they never disagree.
- `@livepicker-scroll` is the index of the first visible tab in the ranked list
  (0 = far left). Maintain it as state:
  - `type` / `backspace` / cancel-clear → `scroll = 0` (and `index = 0`).
  - `next-session` / `prev-session` → after updating `index`, scroll into view:
    if `index < scroll`, set `scroll = index`; if the highlighted tab's right
    edge exceeds `scroll + T`, advance `scroll` until the tab fits.
  - Every redraw: if the whole list now fits in `T`, clamp `scroll = 0`.

### Overflow indicators

- **Right indicator** (tabs hidden to the right of the viewport): render
  `@livepicker-overflow-right-format` (default `+%d>`) where `%d` is the
  **total** number of hidden tabs — left-hidden + right-hidden combined, not
  split by side. A tab that is fully or partially clipped at either edge counts
  as hidden. Placed at the far right of the tab region.
- **Left indicator** (tabs hidden to the left, i.e. `scroll > 0`): render
  `@livepicker-overflow-left` (default `<`), presence only, no count. Placed
  immediately after the gap, before the first visible tab.
- Both can show at once: `< …visible tabs… +N>`.
- Neither shows when the tabs fit entirely.
- Indicators are styled with `@livepicker-fg`/`bg` (plain) or the theme style
  (window-status); they are chrome, not tabs, and are never highlighted.

### No-match state

When the ranked list is empty, render `<icon><query>` and a trailing
` (no match)` (plain ASCII, shown regardless of nerd-font mode because glyph
coverage for it is uneven). No tabs, no indicators. Create-on-Enter still
applies (section 6 Confirm).

### Width source

`@livepicker-client-width` is captured at activation via
`tmux display-message -p '#{client_width}'` resolved against the invoking
client, and refreshed by a `client-resized` hook installed for the duration
(section 10). The renderer reads only this cached value — **no per-keystroke
`tmux` round-trip** — which preserves the section 18 latency budget.

## 20. Filtering and ranking (fuzzy)

Replaces the earlier case-insensitive substring filter. Implemented once in
`scripts/rank.sh` as `lp_rank`, sourced by the renderer, `input-handler.sh`, and
`session-mgmt.sh` — the same single-source-of-truth pattern `filter.sh` used, so
what the renderer shows and what nav/confirm/rename/delete resolve can never
drift.

### Match rule — subsequence

A session name matches the query iff every character of the query appears in the
name **in order**, case-insensitively (not necessarily contiguously).
Non-matches are **hidden entirely**, so the create-on-empty path still fires
(section 6 Confirm).

### Scoring

Score each match (higher = better; index 0 = the top match = the preview
target) by accumulating over the matched character positions:

- **Prefix bonus** (large): the first query char matches at name position 0.
- **Word-boundary bonus**: a matched char falls at name position 0 or right
  after a non-alphanumeric (`-_. /`) or at a camelCase boundary.
- **Contiguity bonus**: a matched char immediately follows the previous matched
  char in the name (rewards contiguous runs / near-prefix matches).
- **Position penalty** (small, proportional to the match's start offset):
  earlier matches win.
- **Tie-break**: original tmux order (stable sort).

The exact constants are not load-bearing; a simple integer score that satisfies
*exact-prefix > word-boundary substring > deep subsequence* is sufficient. Do
not over-tune.

### Empty query

Matches all names at score 0 in original tmux order — no reordering. This
preserves the section 2 non-goal (no recency/MRU). Ranking only reorders once
≥1 char is typed.

### Interface

`lp_rank LIST FILTER` prints the matching names best-first, one per line, like
`lp_build_filtered` did. Callers do
`mapfile -t ranked < <(lp_rank "$LIST" "$FILTER")`. The renderer windows the
result by `@livepicker-scroll` (section 19); nav/confirm/rename/delete index
into it directly so `ranked[index]` == the highlighted tab.

### Performance

O(N·Q) per redraw, N = session count, Q = query length. Fine for typical
N (< 100) in pure bash; the ranker itself needs no caching (sourced once per
process, no per-name subshell). The renderer as a whole stays within the section
18 budget only because its STATIC config is cached once at activation
(`@livepicker-render-cache`) — each `tmux show-option` forks a client (~3–4 ms),
so ~10 reads per redraw would otherwise dominate — and its viewport width pass is
fork-free (`_lp_measure_into`).

## 21. Session management (rename / delete)

Goal: session-CRUD parity with sessionx so livepicker can replace it. v1 ships
rename + delete. The control-key namespace reserves room for the rest of
sessionx's management keys (window mode, tree mode, configuration, etc.) as
future work — pick non-colliding defaults then.

### Keys

Bound in the `livepicker` table after the copied user bindings, so they
override any same-key copy (section 8, step 5). Both are control keys, not
letters/digits, so they never collide with the typing set:

- Rename: `@livepicker-rename-key`, default `C-r` (matches sessionx's
  `@sessionx-bind-rename-session ctrl-r`).
- Delete: `@livepicker-delete-key`, default `M-BSpace` (matches sessionx's
  `@sessionx-bind-kill-session alt-bspace`); most terminals send it reliably.

Both act on the currently highlighted (and previewed) item, resolved via
`lp_rank` + `@livepicker-index` exactly as confirm/nav do.

### Rename

1. On `C-r`, resolve the highlighted session `S` from `ranked[index]`. If the
   ranked list is empty, no-op.
2. Open tmux's built-in prompt pre-filled with the current name:

   ```
   tmux command-prompt -I "$S" -p "Rename session:" \
     "run-shell '$SCRIPT_DIR/session-mgmt.sh do-rename %%'"
   ```

   `command-prompt` uses tmux's own prompt mode; while it is open the
   `livepicker` table is suspended (the prompt captures input), and on
   submit/escape tmux restores the `livepicker` table. The status line and the
   linked preview remain in place throughout.

3. `session-mgmt.sh do-rename NEW`:
   - Re-resolve `S` from the current index (it is stable during the prompt).
   - Guard: empty `NEW` → no-op.
   - `tmux rename-session -t "=$S" "$NEW"`. tmux sanitizes session names
     (`:`→`_`, leading `.`→`_`); if the resulting exact name differs from `$NEW`,
     `display-message` the sanitized name and abort rather than silently
     renaming. If a session named `$NEW` already exists, `rename-session`
     errors; `display-message` and abort.
   - On success: rewrite `@livepicker-list` (replace the old name with the
     actual resulting name), keep the highlight on the renamed session, and
     `refresh-client -S`. The linked preview window id is unchanged by a rename,
     so no preview re-link is needed.
   - Escaping caveat: the `%%` substitution inside a single-quoted `run-shell`
     handles normal names; names containing `'`, `"`, `` ` ``, or `$` may break.
     Session names rarely contain these and tmux rejects `:`. Known limitation.

### Delete

1. On `M-BSpace`, resolve `S` from `ranked[index]`. If the ranked list is empty,
   no-op.
2. Guards (refuse with a `display-message`, no kill):
   - `S == ORIG_SESSION` (the driver the client lives in): killing it would
     destroy the picker host and detach the client.
   - `@livepicker-list` has length 1: tmux requires at least one session.
3. If `@livepicker-confirm-delete` is `on` (default `off`):
   `tmux confirm-before -p "Kill session $S? (y/n)" "run-shell '$SCRIPT_DIR/session-mgmt.sh do-delete $S'"`
   and return. Otherwise proceed immediately (sessionx-style, snappy).
4. `session-mgmt.sh do-delete S`:
   - If the linked preview window (`@livepicker-linked-id`) belongs to `S`,
     `unlink-window` it from the driver (`ORIG_SESSION:$linked_id`) **first**.
     Reason: `kill-session` destroys a session's windows, but a window still
     linked into another session SURVIVES there — without unlinking, the preview
     window would leak into the driver as a permanent orphan.
   - `tmux kill-session -t "=$S"`.
   - Rewrite `@livepicker-list` (drop `S`); clamp `index` to
     `min(index, new_len - 1)`; recompute the ranked view; re-sync the preview
     to the new highlight (the unlink+kill above cleared the old preview; this
     links the new highlight's window); `refresh-client -S`.

### Window mode (`@livepicker-type window`)

Rename/delete operate on the highlighted window analogously —
`rename-window -t "session:window"`, `kill-window -t "session:window"` — with
the same shape (rename via prompt; refuse to kill the driver's only window;
rebuild and re-sync after). Session mode is the primary path; window mode is
the obvious extension and shares the resolution logic.

### Delete key caveat

`@livepicker-delete-key` defaults to `M-BSpace` (sessionx's choice), which the
vast majority of terminals send as a distinct code. A few older terminals or
SSH/mosh links strip Alt-modified keys entirely; if delete does not fire there,
rebind to `C-h` or `DC` (Delete), and note it in the README.

## 22. Preview sizing: clip instead of reflow (kill the status-grow jank)

### The problem

Growing the status from one line to two shrinks the client's pane area by one
row. tmux then resizes the active window — the linked preview (section 7) — to
the smaller height, which **reflows every pane in it** (layout recalculated,
content re-wrapped, terminal re-rendered). That reflow is the visible jank: it
fires on activation and again whenever the live preview re-links a window whose
panes must shrink.

### The fix: freeze the preview's height, clip its bottom row

Instead of letting the preview reflow into the smaller area, **freeze the
active window's height before the status grows**, so it keeps its full pre-grow
height and overflows the now-shorter visible area by exactly one row. tmux then
renders the top of the window and clips the overflow at the bottom — the row
adjacent to the status bar. No pane is resized, no content reflows, no jank.
"Cut off the bottom row" is exactly this clip; it is the user's preferred side,
and it is tmux's natural clip side when `status-position` is `bottom` (the
default). (If `status-position` is `top`, the clip lands at the top instead.)

### Mechanism (intended)

`window-size` governs whether tmux auto-resizes a session's windows to fit its
clients (`largest` / `smallest` / `latest` / `manual`). At activation, in this
order:

1. Save the driver session's current `window-size` into
   `@livepicker-orig-window-size`.
2. `tmux set-option -t "$ORIG_SESSION" window-size manual` — the driver will no
   longer shrink its active window when the client area changes.
3. Grow `status` to two lines and install the renderer (section 10).

Because the session is now `manual`, the status grow does not resize the active
(preview) window; it keeps its height and the bottom row is clipped. Navigation
re-links other candidate windows; each is shown at its own height with the same
one-row bottom clip, never reflowing for the status grow. (If a candidate's
window comes in at an odd height, an optional one-time `resize-window -y H` at
link time pins it deterministically — a single resize, not per-keystroke.)

On restore (section 9): shrink `status` back, then
`tmux set-option -t "$ORIG_SESSION" window-size "$ORIG_WINDOW_SIZE"` to
re-enable auto-sizing.

### Control

`@livepicker-preview-fit`:

- `clip` (default): the behavior above. No reflow jank on status grow or on
  preview re-link.
- `reflow` (legacy): grow the status and let the preview reflow to the smaller
  area (the pre-section-22 behavior). Use if `clip` misbehaves on a given
  tmux/terminal.

### Verification required (load-bearing)

tmux's behavior for a window larger than its client under `window-size manual`
is subtle and version-dependent, and the preview window is **shared with its
source session** — its single size is influenced by every session/client it is
linked into. The implementer MUST empirically confirm on tmux 3.6b (mirror the
`research/` findings pattern used elsewhere) that:

- A `manual` session shows an oversized active window **clipped** (top-left
  viewport; bottom row hidden), not force-resized back down.
- Setting `window-size` per-session (`-t`) truly isolates the effect to the
  driver; if the installed tmux only honors it globally (`-g`), save/restore it
  globally and accept that the source session's sizing is briefly affected.
- A window linked into the manual driver from a differently-sized source still
  clips in the driver without disturbing the source's own attached clients.

If any of these fail, fall back to `@livepicker-preview-fit reflow`, or to
`@livepicker-preview-mode snapshot` (section 7), which never resizes a live
window at all.
