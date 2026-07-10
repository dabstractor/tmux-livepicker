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
real layout. The user filters by typing, moves between **sessions** with their
session-nav keys (discovered from their config — for this user `)` / `(` plus the
arrow keys), and flips through the highlighted session's **windows** with the
same window-nav keys they use every day (`Ctrl-M-Tab` / `Ctrl-M-BTab` and
siblings), so they can visually locate their work among dozens of window tabs
spread across many sessions without ever leaving their seat. Confirming lands on
the chosen session **and window**; cancelling restores everything exactly —
including every previewed session's active window and pane layout, as if the
picker was never opened (sections 4 and 23).

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
- Two-axis navigation: move between sessions with the session-nav keys; flip
  through the highlighted session's **windows** with the user's own window-nav
  keys, with the live preview following each flip. This lets the user visually
  locate their work across dozens of window tabs spread over many sessions
  without leaving their seat.
- Filter by typing.
- Confirm lands on the chosen **session and window** — the exact tab being
  previewed — not just the session.
- Leave-no-trace while browsing: flipping a candidate's windows never changes
  that candidate's active window, and never moves, resizes, or otherwise alters
  any pane in any session. Moving to another session, or cancelling, snaps every
  candidate back to its original state — active window and pane layout intact
  (sections 4 and 23).
- Reserve every plain letter and digit for the query: navigation, confirm,
  cancel, and backspace use only non-alphanumeric keys, so typing can use the
  full `a`-`z`, `A`-`Z`, `0`-`9` range.
- Create a new session from the typed query when nothing matches, optionally
  opening it in the directory `zoxide` resolves for the query.
- Zero pollution of session history and the session toggle while browsing.
- Full, exact restoration of status layout, key table, focus, and pane geometry
  on exit.

### Non-goals

- A floating popup UI. The picker is on the status line.
- Previewing more than one window of a session at once. The preview shows one
  window (all its panes) at a time; the user flips between a session's windows
  one at a time.
- Pane-level picking. The picker selects sessions and windows, never individual
  panes.
- Recency or MRU (time-based) ordering. The empty-query order stays tmux
  default; with a query active, sessions are reordered by fuzzy similarity
  (section 20), never by access time.
- Multi-client coordination. The picker serves the invoking client.

## 3. User stories

- I press the activation key. The status bar becomes two lines; the area below
  shows my current session's panes live; the picker lists my sessions with the
  current one highlighted.
- I press my session-nav key (`)` or `Down`). The highlight moves to the next
  session and the preview below switches to show that session's active window,
  live. My history and toggle are untouched.
- While previewing a session, I press my window-nav key (`Ctrl-M-Tab`). The
  preview flips to that session's next window tab — live — and that window's
  name lights up on line 2 of my status bar. The session's *own* active window
  is unchanged; I'm only looking. I flip through a dozen tabs in a second to
  find the one I want.
- I press Enter. The picker closes and I land in that session **on the exact
  window I was previewing**.
- I change my mind and move to a different session, or I press Escape. The
  session I was flipping through snaps back to whichever window it was on
  before I touched it — no tab moved, no pane resized — as though I was never
  there.
- I type `log`. The list filters to matching sessions; the preview follows the
  top match.
- I type a query, press Enter on the top match. The picker closes and I am in
  that session on the window I was previewing.
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
  exactly where I was — same session, same window, every pane where I left it.
  Every session I peeked at is likewise untouched. My window-nav keys move
  windows again.
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

Section 4 names the headline rule; the full set of invariants the plugin must
uphold is:

- **Invariant A — no client session switch while browsing.** Browsing never
  calls `switch-client`. The only switch is the single one at confirm. (Above.)
- **Invariant B — no candidate state mutation while browsing.** Browsing never
  changes any candidate session's active window, and never moves, resizes, or
  alters any of its panes. Flipping a candidate's windows links the chosen
  window into the driver and selects it *there*; it never calls `select-window`
  on the candidate itself, so the candidate's active window is invariant, and
  the shared window is never reflowed (section 7, section 23). Moving to
  another session or cancelling therefore leaves every candidate exactly as it
  was — "leave no trace."
- **Invariant C — pane immutability.** No pane of any session — candidate,
  driver, or bystander — is moved, resized, reordered, reset, or has any
  property altered by browsing, confirming, or cancelling, even though the
  preview is a shared window object. Enforced by prevention, not repair: there
  is no reliable after-the-fact undo (section 23).

Confirm is the one place a candidate's state changes by design: a single
`select-window` commits the chosen window as the candidate's active window, and
a single `switch-client` moves the client onto it. Everything else is read-only.

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
  while the picker is active. It binds typing, filtering, the two navigation
  axes (session-nav and window-nav), confirm, cancel, and the management keys.
  Because only this table is consulted while active, any key bound here is in
  effect for the duration and reverts for free when the table is switched back
  (section 8).
- **Live preview.** A separate preview routine links the highlighted session's
  *chosen* window (its active window by default; whichever window the user has
  flipped to otherwise) into the current session and selects it there, so all
  its panes show live in the area below the status bar. It never touches the
  candidate session's own active window or panes (section 7, Invariant B/C).

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
  |- switch key-table to livepicker; bind input keys (two-axis nav discovered
  |    from the user's config + rename/delete management keys, section 8/21)
  |- set initial selection (index 0, scroll 0, window-cursor = current session's
  |    active window); run first preview

scripts/input-handler.sh <action> [arg]
  |- type / backspace: update @livepicker-filter; rank; reset index=0 + scroll=0 + window-cursor=candidate active window; refresh status FIRST, then defer a preview to the top match (section 18)
  |- next-session / prev-session: move @livepicker-index; refresh status FIRST (highlight moves); scroll-into-view (section 19); reset window-cursor to the new candidate's active window; defer the preview
  |- next-window / prev-window: advance @livepicker-cand-win-cursor within the current candidate's window list (wrapping); defer a re-link of the chosen window (section 18); refresh -S so line 2's window-status follows the flip
  |- confirm: resolve (session, window) from ranked list + window-cursor; create if needed; switch-client once + one select-window to land on the window; restore
  |- cancel: clear the query (reset index+scroll+window-cursor); or hard-reset everything if query already empty
  `- rename / delete: delegate to scripts/session-mgmt.sh (section 21)

scripts/session-mgmt.sh <rename|delete|do-rename|do-delete> [arg]
  `- rename via tmux command-prompt; delete via kill-session (optionally confirm-before);
     guards (driver/last-session/linked-window leak); rewrite list + re-rank + re-sync preview

scripts/preview.sh <session> [window-id]
  `- link the candidate's CHOSEN window (active window, or the window the user flipped to) into the current session and select it THERE (all panes live). Never select-window on the candidate; never resize/mutate its panes (Invariant B/C).

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
6. Set the initial selection to the current session (index 0, scroll 0) and the
   window cursor to the current session's active window, then run the first
   preview.
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
intercepted and cannot be typed; the session-nav, window-nav, confirm, cancel,
backspace, and management keys (rename/delete) are therefore constrained to
non-alphanumeric keys (arrows, `)`/`(`, `C-M-Tab`/`C-M-BTab`, `M-n`/`M-p`,
`C-n`/`C-p`/`C-l`/`C-h`, `Enter`, `Escape`, `BSpace`, `C-r`, `M-BSpace`).

### Session navigation

`next-session` and `prev-session` move `@livepicker-index` within the ranked
list (wrapping). After the move, the handler runs the **scroll-into-view** rule
(section 19): if the new highlight falls outside the viewport, advance/retreat
`@livepicker-scroll` until the highlighted tab is visible. Entering a new
candidate also **resets the window cursor** to that candidate's current active
window (every candidate starts previewed on its own active window; per-candidate
flip history is not remembered across session moves — Invariant B). Each move
redraws the status immediately; the preview re-sync (link the new candidate's
active window) is deferred to the background so the highlight tracks the
keypress with no lag (section 18). Navigation must not call `switch-client`.

### Window navigation (flip within the previewed session)

`next-window` and `prev-window` flip through the **windows of the currently
highlighted session**, advancing `@livepicker-cand-win-cursor` within that
session's ordered window list (wrapping; the list comes from
`list-windows -t "=$S" -F '#{window_id}'`, re-derived when the candidate
changes). The chosen window is then shown in the preview by the same link-into-
driver mechanism (section 7): unlink the previous linked window (if any) from
the driver, link the chosen window into the driver, and `select-window` it
**there**. This is the load-bearing leave-no-trace rule: the flip never calls
`select-window` on the candidate session, so the candidate's own active window
and pane layout never change (Invariant B/C). The re-link is deferred and
supersedeable exactly like a session-nav preview (section 18). The flip does
not change line 1 (the session tabs are unchanged), but it calls
`refresh-client -S` so line 2 — the user's normal window-status — updates to
show the newly active (linked) window's name; that is the only indicator the
user needs for which tab they are on.

Self-session note: when the highlighted session is the driver itself, there is
nothing to link (its windows already live there); `next-window`/`prev-window`
then `select-window` among the driver's own windows. That *does* move the
driver's active window while browsing, but cancel is a hard reset that restores
`ORIG_WINDOW`, and the panes are never resized (Invariant C); see section 23.

### Confirm

Resolve the target **session** `S` from the ranked list (section 20) at the
current index, and the target **window** `W` from `@livepicker-cand-win-cursor`
(the window currently being previewed for that session; for the self-session or
for `snapshot`/`off` preview modes with no chosen window, `W` is the session's
active window).

- If a target session `S` exists:
  - **Commit the window choice in `S`** with one `select-window -t "=$S:$W"`
    (this is the single, deliberate mutation of a candidate — Invariant B).
    Verify the window-id addressing form on the target tmux; if `=$S:@id` is
    not accepted, `switch-client` to `S` first and then `select-window -t "@id"`.
  - **Tear down the driver's preview link** (unlink `ORIG_SESSION:$linked_id`)
    exactly as today, targeting `ORIG_SESSION` explicitly — not the post-switch
    current session (mirror the existing confirm unlink discipline).
  - `switch-client -t "=$S"` — the one session switch; the client lands on `S:W`.
  - If `S == ORIG_SESSION` (self): skip the `switch-client`; the single
    `select-window -t "$W"` is the whole commit.
- If the ranked list is empty, the type is `session`, and `@livepicker-create`
  is on: create a session from the query, then `switch-client` to it (a brand-
  new session has one window, so there is no window choice). If creation fails
  (invalid name), cancel instead.
  - Default: `tmux new-session -d -s "<query>"`.
  - With `@livepicker-zoxide-mode` on (mirrors tmux-sessionx's
    `@sessionx-zoxide-mode`): resolve the query through zoxide and start the
    session there — `z_target=$(zoxide query "<query>")`;
    `tmux new-session -d -s "<query>" -c "$z_target" -n "$z_target"`. If zoxide
    returns nothing (dir unindexed, below its frecency threshold, or zoxide
    absent), fall back to the default create above rather than `-c ""`.
- If the type is `window`: `select-window -t "<session>:<window>"` (no new
  session creation in window mode).

Then run `restore.sh keep`, which tears down the picker but leaves the client on
the chosen `(S, W)` and does **not** re-select `ORIG_WINDOW` or switch back.

### Cancel

Run `restore.sh cancel` — a **hard reset**, regardless of how many sessions were
previewed or how many windows were flipped:

1. Unlink the driver's preview window if `@livepicker-linked-id` is set.
2. `select-window -t "$ORIG_WINDOW"` — restore the driver's original window
   (this also undoes any self-session window-flip).
3. `switch-client -t "=$ORIG_SESSION"` — return the client to its original
   session (cancel is not a navigation).
4. Restore `status`, every `status-format[n]`, `renumber-windows`, `key-table`,
   the hooks, and the driver's `window-size`; clear all `@livepicker-*` state.

Every **non-self** candidate is already pristine — its active window was never
changed and its panes were never touched (Invariant B/C, enforced by the
link-only preview mechanism), so cancel needs no per-candidate work. The result
is exactly the pre-activation state: same session, same window, every pane where
it was, every peeked session untouched.

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

This is the defining feature. It must show a window of the candidate session —
its active window by default, or whichever window the user has flipped to — with
all of that window's panes, live, in the area below the status bar, without
switching sessions and without changing the candidate's own active window or
moving any of its panes (Invariant B/C).

This section describes *how* a preview is produced. Section 18 specifies *when*:
previews are deferred relative to input, so they never block typing or
navigation.

### Mechanism: link-window plus select-window (on the driver only)

A tmux window can be linked into more than one session. A linked window is the
same window object: it renders all of its panes, live, and keeps the same global
window id everywhere it appears. Crucially, each session tracks its **own**
active window independently — selecting a window in one session does not change
any other session's active window. The preview exploits exactly that: it shows a
candidate window by linking it into the driver and selecting it **in the
driver**, never in the candidate.

To show window `W` of candidate session `S` (`W` defaults to `S`'s active
window, and is whatever window the user has flipped to otherwise):

```
show_window S, W:
    if S == ORIG_SESSION (driver/self):
        tmux select-window -t "$W"              # W already lives here; just select it
        LINKED_ID = ""                          # nothing linked for self
        return
    # non-self candidate: link W into the DRIVER and select it THERE.
    if a previous linked preview exists (track $LINKED_ID):
        tmux unlink-window -t "$ORIG_SESSION:$LINKED_ID"   # drop prior link; S keeps its window
    tmux link-window -s "$W" -t "$ORIG_SESSION:"           # link W into the driver
    tmux select-window -t "$W"                              # show it in the driver (all panes, live)
    LINKED_ID = W
    # NOTE: nothing above targets S. S's active window and panes are untouched.
```

Notes for the implementer:

- The linked window's id equals the source window's id. Track that id
  (`LINKED_ID`); it is the handle for unlinking on the next navigation and on
  exit.
- `unlink-window` removes the window from the driver only. The candidate keeps
  its window. Never pass `-k` (that would destroy the window when it is linked
  in only one session; here it is always linked in `S` too).
- Window ids are server-global and survive `renumber-windows on`. Address
  windows by id, never by index. `W` is resolved from
  `list-windows -t "=$S" -F '#{window_id}'` (ordered, for flipping) or with
  `-f '#{window_active}'` (for the default).
- Use `-t "=S"` (the `=` prefix) for exact session-name matching.
- **Leave-no-trace (Invariant B):** `show_window` never calls `select-window`,
  `resize-window`, or any layout/pane command on `S`. The candidate's active
  window is therefore whatever it was before the user started browsing, and its
  panes never move. This is what makes "select a different session, or cancel →
  the candidate snaps back to its original window" true for free.
- **Pane immutability (Invariant C):** because `W` is shared, anything that
  resizes it in the driver resizes it in `S` too, and **permanently** (verified:
  `unlink-window` does not roll it back). `show_window` links and selects only;
  the driver must be pinned so it cannot reflow `W`. See section 23 for the full
  prevention regime.

### Fallbacks

- If `link-window` fails for any reason, fall back to a snapshot of the active
  pane: `tmux capture-pane -ep -t "=$S"` written into the preview area. This is
  single-pane and not live, but it never blocks the picker.
- If `@livepicker-preview-mode` is `snapshot`, always use `capture-pane` and skip
  linking. If it is `off`, show no preview.
- The default is `live`.

### Self-session edge case

When the highlighted session is the driver itself, do not link (a session cannot
link its own window into itself). `show_window` just `select-window`s among the
driver's own windows — the default is `ORIG_WINDOW`, and window-nav flips through
the driver's other windows. Flipping here moves the driver's active window while
browsing (unlike a non-self candidate), but cancel is a hard reset back to
`ORIG_WINDOW` and the panes are never resized (Invariant C; section 23).

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

### Sizing: clip, don't reflow (and never mutate panes — section 23)

The live preview is a shared, linked window (above). When the status grows to
two lines (section 10) the client pane area shrinks by one row; by default
(`@livepicker-preview-fit clip`, section 22) the driver's `window-size` is set
to `manual` first, so the preview window keeps its full height and its bottom
row is **clipped** instead of reflowed. Because the window is shared, a reflow
would move the candidate's panes too — so clipping is not merely a jank fix, it
is a correctness requirement (Invariant C). The window's panes must never be
resized on any path — typing, session-nav, or window-nav. Section 22 gives the
mechanism and the `reflow`/`snapshot` fallbacks; section 23 states the absolute
pane-immutability invariant, the prevention regime, and the empirical
verification it requires.

## 8. The key subsystem (two-axis navigation, discovered)

The picker has two navigation axes, and **both reuse the keys the user already
has bound for that axis**, discovered from their live key tables:

- **Session axis** — move the highlight between candidate sessions. Defaults to
  the user's session-nav keys (`switch-client -n` / `-p`) plus the arrow keys.
- **Window axis** — flip through the highlighted session's windows in the
  preview. Defaults to the user's window-nav keys (`next-window` /
  `previous-window` / `select-window -n` / `-p`, including the
  `swap-window … \; select-window …` compounds).

The window-nav keys keep doing window navigation — just scoped to the previewed
session. They are **not** repurposed into session-nav (an earlier design did
that; it fought the user's muscle memory and is dropped). Confirm, cancel,
backspace, and the rename/delete management keys are the only other keys bound.

### Why this is low-cost

The picker uses a modal key table. While `key-table` is `livepicker`, tmux
consults only that table, so binding these keys there takes effect for the
duration and reverts for free when the table is switched back to its original
value (typically `root`). No per-key save/restore is needed for the revert.

### Discovery

For each axis, if the user has **not** set the corresponding `@livepicker-*`
option explicitly, discover the keys from `tmux list-keys -T root` and
`tmux list-keys -T prefix`:

- **Window axis** — a key is a *next-window* key if its command contains any of:
  `select-window -n`, `select-window -t +1`, `select-window -t :+1`,
  `next-window` (and `next-window -a`), or the `swap-window … \;
  select-window -t +1` compound; symmetrically for *prev-window* (`-p`,
  `-t -1`, `:-1`, `previous-window`). Matching on the `select-window`/
  `next-window` portion catches the user's `swap-window \; select-window`
  compounds automatically.
- **Session axis** — a key is a *next-session* key if its command is
  `switch-client -n`; *prev-session* if `switch-client -p`. (Do **not** treat
  `-l` (toggle) or `-t <name>` as axis keys.) Always add the arrow keys `Down`
  (next-session) and `Up` (prev-session) as universal extras.

Then, for either axis:

- Collect every matching key from both tables.
- **Drop any plain `a`-`z` / `A`-`Z` / `0`-`9`** (e.g. the user's prefix-table
  `n` and `p`, and the digit `select-window -t :=N` bindings) — those stay
  reserved for typing. Keep all control/meta/arrow/function keys (e.g. `C-n`,
  `C-p`, `C-l`, `C-h`, `M-n`, `M-p`, `C-M-Tab`, `C-M-BTab`).
- De-duplicate. Exclude any key that is one of the fixed control keys
  (confirm/cancel/backspace/rename/delete) so discovery never shadows them.
- Explicit `@livepicker-*-keys` options, when set, **override** discovery for
  that axis (discovery is only the default-resolution path).

**Worked example (this user).** Discovered window axis — next: `C-M-Tab`,
`M-n`, `C-n`, `C-l`; prev: `C-M-BTab`, `M-p`, `C-p`, `C-h` (plain `n`/`p` and
digits dropped). Discovered session axis — next: `)`, `Down`; prev: `(`, `Up`.
So out of the box the user flips a session's windows with their familiar
`Ctrl-M-Tab` / `Ctrl-M-Shift-Tab` (and `M-n`/`M-p`/`C-n`/`C-p`), and moves
sessions with `)` / `(` or the arrows.

### Binding

On activate, bind in the `livepicker` table, in this order (tmux keeps the
**last** binding for a key, so each step overrides the ones before it):

1. A copy of the user's current prefix and root bindings (read
   `tmux list-keys -T prefix` and `tmux list-keys -T root`, rewrite each line's
   table to `livepicker`, and re-bind it) so the rest of their keybinds keep
   working during the picker.
2. Typing: every `a`-`z`, `A`-`Z`, `0`-`9`, and `-_. /` →
   `input-handler.sh type <c>`.
3. Window axis: each discovered (or explicit) next-window key →
   `next-window`; each prev-window key → `prev-window`.
4. Session axis: each discovered (or explicit) next-session key →
   `next-session`; each prev-session key → `prev-session`.
5. Confirm (`@livepicker-confirm-keys`, default `Enter`), cancel
   (`@livepicker-cancel-keys`, default `Escape`), backspace
   (`@livepicker-backspace-keys`, default `BSpace`).
6. Session management (section 21): `@livepicker-rename-key` (default `C-r`) →
   `rename`; `@livepicker-delete-key` (default `M-BSpace`) → `delete`.

```
tmux bind-key -T livepicker "$W_NEXT" run-shell "$SCRIPT_DIR/input-handler.sh next-window"
tmux bind-key -T livepicker "$S_NEXT" run-shell "$SCRIPT_DIR/input-handler.sh next-session"
tmux bind-key -T livepicker "$CONFIRM" run-shell "$SCRIPT_DIR/input-handler.sh confirm"
```

**Load-bearing ordering and the typing reservation.** Steps 3–6 run after step
2, so any nav/confirm/cancel/backspace/rename/delete key overrides the typing
binding for the same key. That is safe only because every key bound in steps 3–6
is **non-alphanumeric** (control/meta/arrow keys are distinct tmux keys from the
letters). Discovery enforces this by dropping plain letters/digits; a plain
letter or digit used for navigation would be silently untypeable. If a user
genuinely wants vim-style `j`/`k` session-nav, they may set
`@livepicker-session-next-keys` / `-prev-keys` to include `j`/`k`, accepting
that those two letters then cannot be typed into a query.

## 9. State saved and restored

On activate, save (all into `@livepicker-orig-*`):

- Current session name and window id.
- Current `window_layout` of the active window, **plus a pane-geometry snapshot**
  of that window (`#{pane_id}`/`#{pane_left}`/`#{pane_top}`/`#{pane_width}`/
  `#{pane_height}` per pane). The layout string is for restore; the geometry
  snapshot is so restore can detect whether anything drifted and act only if it
  did (Invariant C; section 23).
- Current `key-table`.
- Current `status` value (line count) and every set `status-format[n]`.
- Current `renumber-windows` value.
- Current `session-window-changed` hook value (if suppression is on).
- The id of the linked preview window (`@livepicker-linked-id`), initially empty.
- Current `window-size` of the driver session (frozen to `manual` in clip mode;
  section 22).

**Not saved, because never changed:** no candidate session's active window or
layout is captured. The preview mechanism (section 7) never mutates a candidate,
so there is nothing to restore for them (Invariant B). The only session whose
state can shift while browsing is the driver itself (self-session window-flips,
status grow) — that is what the items above cover.

Runtime state (not saved, live in `@livepicker-*`, cleared on exit):
`@livepicker-index`, `@livepicker-scroll`, `@livepicker-client-width`, plus the
new window-cursor keys `@livepicker-cand-win-session` (the candidate the cached
list belongs to), `@livepicker-cand-win-list` (that candidate's ordered window
ids), `@livepicker-cand-win-cursor` (index into it; defaults to the candidate's
active window on entry), and `@livepicker-preview-win-id` (the window currently
shown).

On restore (`restore.sh`), in order:

1. Unlink the preview window from **`ORIG_SESSION`** (not the client's current
   session — on a confirm/keep the client has already switched to the target) if
   `@livepicker-linked-id` is set.
2. `select-window -t "$ORIG_WINDOW"` (cancel only; `keep` skips this so the
   client stays on the chosen `(S, W)`).
3. If cancel: `switch-client -t "$ORIG_SESSION"` (return to the original
   session). If keep: do not switch (stay on the chosen target).
4. Restore `status`, every `status-format[n]`, `renumber-windows`, `key-table`,
   the `session-window-changed` hook, the `client-resized` hook, and the driver's
   `window-size` (section 22).
5. **Original-window pane restore (Invariant C, section 23):** compare the
   original window's current pane geometry to the activation snapshot. If it is
   unchanged, do nothing (the common case — leave it alone rather than risk
   moving panes). Only if it drifted: restore the window's exact size first, then
   `select-layout "$ORIG_LAYOUT"`. `select-layout` is size-dependent and can
   itself move panes, so it is a last resort, never routine.
6. Clear every `@livepicker-*` option (this MUST include the runtime keys
   `@livepicker-scroll`, `@livepicker-client-width`, and the window-cursor keys
   `@livepicker-cand-win-session`/`-list`/`-cursor`/`@livepicker-preview-win-id`
   — add them to `_STATE_RUNTIME_KEYS` in `state.sh`) and unbind the
   `livepicker` table.

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
| `@livepicker-session-next-keys`    | (discovered) | Next-session keys (session axis). Default: discovered `switch-client -n` bindings + `Down`. For this user: `)`, `Down`. Must be non-alphanumeric; a plain letter/digit is intercepted and not typeable. Section 8. |
| `@livepicker-session-prev-keys`    | (discovered) | Previous-session keys (session axis). Default: discovered `switch-client -p` bindings + `Up`. For this user: `(`, `Up`. Must be non-alphanumeric. Section 8. |
| `@livepicker-window-next-keys`     | (discovered) | Next-window keys (window axis — flip the previewed session's windows). Default: discovered next-window bindings. For this user: `C-M-Tab`, `M-n`, `C-n`, `C-l`. Must be non-alphanumeric. Section 8. |
| `@livepicker-window-prev-keys`     | (discovered) | Previous-window keys (window axis). Default: discovered prev-window bindings. For this user: `C-M-BTab`, `M-p`, `C-p`, `C-h`. Must be non-alphanumeric. Section 8. |
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
    input-handler.sh          type / backspace / next-session / prev-session / next-window / prev-window / confirm / cancel / rename / delete
    preview.sh                link-window live preview of the candidate's chosen window into the driver (with capture fallback); never mutates the candidate (Invariant B/C)
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
  session's active window id; `list-windows -t "=$S" -F '#{window_id}'` (no
  `-f`) for the ordered full list the window-flip axis walks.
- `link-window -s <id> -t <driver>:` to link the chosen window into the driver
  (bare, no `-a`; the driver is `ORIG_SESSION`, never the candidate).
- `unlink-window -t <driver>:<id>` to remove the linked preview window from the
  driver only (the candidate keeps its window).
- `select-window -t <id>` to show the linked window **in the driver** (never on
  the candidate while browsing).
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

- **Browsing — Invariant A (no client switch):** `link-window` and
  `select-window` operate inside the driver. `client-session-changed` does not
  fire. The `tmux-session-history` timeline and `@session-history-prev` pointer
  are unchanged. Zero entries added.
- **Browsing — Invariant B (no candidate mutation):** window-flips link the
  chosen window into the driver and select it there; no command targets the
  candidate session, so the candidate's active window and `window_layout` are
  byte-identical before and after browsing it. Verified by capturing
  `#{window_active}` + `#{window_layout}` of a candidate before preview and
  asserting equality after navigating away.
- **Browsing — Invariant C (pane immutability):** no pane of any session is
  moved or resized. The driver is pinned (`window-size manual` + height pin) so
  the status grow and the shared preview window cannot reflow. Verified by a
  pane-geometry snapshot diff across a full browse cycle (section 15/23).
- **Confirm:** exactly one `switch-client`. The history engine treats it as one
  navigation (forward history collapses, the new session appends at the tip),
  the same way it already treats a tmux-sessionx jump. This is correct,
  browser-like behavior.
- **Cancel:** zero `switch-client` to a different session. History and toggle
  are exactly as before activation. Every non-self candidate is already pristine
  (Invariant B); the driver's window and pane geometry are restored (Invariant C).
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
- `)` / `Down` (session axis) move the session selection; the preview follows
  live. `C-M-Tab` / `C-M-BTab` (window axis) flip the previewed session's
  windows; line 2's window-status follows the flip.
- Enter on a match closes the picker and lands on the chosen session **and the
  window being previewed**.
- Escape closes the picker and returns to the original session and window; every
  session that was previewed is back on its original window.

### Pollution (the core invariant)

With `tmux-session-history` installed:

- Browse five sessions, then cancel. Assert `@session-history-hist` is unchanged.
- Browse five sessions, confirm on the fifth. Assert exactly one entry was added.
- After a confirmed pick, the toggle returns to the pre-pick session.

### Live all-panes preview

- A candidate session with a multi-pane window shows all panes in their real
  layout, live, while highlighted.
- Flipping its windows (window axis) re-links each chosen window; each shows all
  its panes live. The candidate's own active window is unchanged (Invariant B).
- Navigating away unlinks the driver's preview; the candidate's window is intact
  in its own session, on its original active window (verified by `list-windows
  -t` + `#{window_active}` before and after).
- Self-session highlight shows the user's own session without linking.
- Clip sizing (`@livepicker-preview-fit clip`): on activation the status grows
  to two lines but the preview's panes do **not** reflow — its bottom row is
  clipped; navigating between candidates and flipping windows re-links without
  per-action reflow. After exit, the driver's `window-size` is restored.

### Pane immutability (Invariant C — load-bearing)

These MUST be verified with a **real attached client** (sessions created with
`-x`/`-y` are size-locked and will not reproduce the shared-window resize); use
the isolated-socket harness with a real client, and restore the user's live
state afterward.

- **No candidate pane movement:** open the picker on a driver client; preview a
  candidate whose active window has a multi-pane layout; capture its pane
  geometry (`#{pane_left}`/`#{pane_top}`/`#{pane_width}`/`#{pane_height}` per
  pane). Flip through several of its windows, move to other sessions, then
  cancel. Assert the candidate's pane geometry is byte-identical to the
  pre-pick snapshot.
- **No status-grow reflow:** assert the candidate's pane geometry does not
  change merely because the picker opened (status 1 -> 2).
- **No confirm side-effects beyond the chosen window:** confirm on candidate `S`
  window `W`. Assert `S`'s OTHER windows are unchanged, and that within `W` only
  the active-window selection changed — pane geometry of `W`'s panes is
  unchanged.
- **Original window intact:** after a full browse -> cancel cycle, the driver's
  original window pane geometry is byte-identical to the activation snapshot.
- **Escape hatch:** if any of the above cannot be satisfied with `clip` on the
  target tmux, `@livepicker-preview-fit reflow` or `@livepicker-preview-mode
  snapshot` (never touches a live window) must hold the invariant. See section
  23.

### Key discovery / two-axis

- Discovery resolves the window axis to this user's `C-M-Tab`/`M-n`/`C-n`/`C-l`
  (next) and `C-M-BTab`/`M-p`/`C-p`/`C-h` (prev), and the session axis to
  `)`/`Down` (next) and `(`/`Up` (prev); plain `n`/`p` and digits are NOT bound
  (still typeable).
- During the picker, the window-axis keys flip the previewed session's windows
  and the session-axis keys move sessions.
- After the picker closes, every one of those keys does exactly what it did
  before (window-nav keys move/reorder windows; `(`/`)` switch sessions).
- Setting `@livepicker-session-*-keys` / `@livepicker-window-*-keys` explicitly
  overrides discovery for that axis.

### Restore

- After exit, `status` and every `status-format[n]` match their pre-activation
  values.
- `key-table`, `renumber-windows`, and the `session-window-changed` hook are
  restored.
- No `@livepicker-*` options remain (`tmux show-options -g | grep livepicker`
  prints nothing).
- The original window's pane geometry is byte-identical to the activation
  snapshot; `select-layout` ran only if drift was detected (section 23).
- For every candidate previewed during the run, its active window id and
  `window_layout` equal their pre-activation values (Invariant B).

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
  the session/window/confirm/cancel/backspace binds run after the typing binds,
  so a key in any of those lists overrides its typing binding. A plain letter or
  digit used for navigation is therefore silently untypeable. Keep those keys
  non-alphanumeric (arrows, `(`/`)`, `C-M-Tab`/`C-M-BTab`, `M-n`/`M-p`,
  `C-n`/`C-p`/`C-l`/`C-h`, `Enter`, `Escape`, `BSpace`); discovery enforces this
  by dropping plain letters/digits. Vim-style `j`/`k` is opt-in via
  `@livepicker-session-*-keys`, accepting that those letters are then not
  typeable.
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
- **Shared-window pane mutation (Invariant C, confirmed root cause, section 23).**
  The preview is one shared window object across every session it is linked
  into, so resizing it in the driver reflows its panes **in the candidate too**
  — and the mutation is **permanent**: `unlink-window` does not roll it back
  (verified), and `select-layout` restore is size-dependent and unreliable
  (verified). Therefore the plugin must PREVENT any resize, never attempt to
  repair it. Confirmed-safe operations (when the session is not auto-resizing):
  `link-window`, `select-window`, `unlink-window`. Forbidden on any candidate /
  original window during preview: `resize-window`, `resize-pane`,
  `select-layout`, `swap-pane`, `swap-window`, `move-pane`, `move-window`,
  `break-pane`, `join-pane`, `pipe-pane`, and geometry-affecting `setw`. The
  §22 clip (driver `window-size manual` + height pin) is the prevention
  mechanism but, as scoped today, pins only the driver's activation-time
  window — candidate windows linked later are NOT covered and must be verified.
- **Preview clip feasibility (load-bearing, section 22/23).** The no-reflow clip
  relies on tmux showing an oversized `window-size manual` window **clipped**
  rather than force-resizing it, for a window that is **shared with its source
  session**. This is subtle and version-dependent: the single shared size is
  influenced by every session/client the window is linked into, so a smaller
  client on the source could still drag the size down. This could NOT be fully
  verified without a real multi-client setup, so the implementer MUST confirm on
  3.6b with a real client that (a) a manual session clips an oversized active
  window at the bottom, (b) `window-size -t` isolates to the driver (else
  save/restore globally), (c) a linked-from-elsewhere window clips in the driver
  without disturbing the source's panes, and (d) flipping a candidate's windows
  never resizes them. If any fails, fall back to freezing each candidate's
  `window-size`+size at link time (restore on unlink), or to
  `@livepicker-preview-fit reflow`, or to `@livepicker-preview-mode snapshot`
  (which never touches a live window). Section 23 owns the full regime.
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
- **Window-axis flips defer the same way.** `next-window`/`prev-window` advance
  the window cursor and schedule a supersedeable re-link exactly like a
  session-nav preview; they never block the next keypress. A flip does not
  change line 1 (the session tabs are unchanged), so it issues only a
  `refresh-client -S` so line 2's window-status follows the newly active window
  — cheaper than a session move. Because flips only link into the driver and
  never touch the candidate, a stale superseded flip can never mutate a
  candidate's panes (Invariant B/C holds regardless of debounce timing).

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

## 23. Pane immutability — zero mutation of any session's panes

**Requirement (Invariant C, absolute).** Browsing, confirming, or cancelling
must not move, resize, reorder, reset, or otherwise alter any property of any
pane in any session — not the candidate being previewed, not the driver/original
window, not any bystander session. "I selected a session and some of its panes
resized / swapped places" is a bug this section exists to eliminate.

**Root cause (confirmed empirically in isolation).** The preview is a *shared*
tmux window object (section 7): a window linked into multiple sessions has ONE
size and ONE pane set. Resizing it in any session reflows its panes in ALL of
them. Three findings drive the design:

1. Resizing a shared window moves panes in every session it is linked into
   (reproduced: a candidate's panes changed geometry when the shared window was
   resized from the driver).
2. `window-size manual` blocks *automatic* resize-to-client, but does **not**
   block an explicit `resize-window`, and does not by itself guarantee a shared
   window is immune when other sessions/clients act on it.
3. The mutation is **permanent** — `unlink-window` does not roll it back
   (reproduced), and `select-layout` restore is size-dependent and failed to
   restore geometry in testing. **There is no reliable after-the-fact repair.**

**Therefore: prevent, never repair.** The plugin must never cause the
candidate's or original's window to be resized or its panes mutated.

**Confirmed-safe operations** (verified not to resize when the session is not
auto-resizing to a mismatched client): `link-window`, `select-window`,
`unlink-window`. The entire preview / flip / confirm-cancel mechanism is built
from these plus the driver's `window-size` pin.

**Forbidden during preview** (on any candidate or original window or its
panes): `resize-window`, `resize-pane`, `select-layout`, `swap-pane`,
`swap-window`, `move-pane`, `move-window`, `break-pane`, `join-pane`,
`pipe-pane`, and any `set-window-option`/`setw` that affects pane geometry —
*except* the one activation-time driver height pin in section 22, which is
scoped to the driver's own pre-grow window and must be verified not to perturb
candidates.

**Prevention regime.** The section 22 clip is necessary but, as scoped today,
insufficient: it pins the driver's `window-size` and the driver's
activation-time window height, but candidate windows linked in later are not
pinned, and the restore-time `select-layout` can itself move panes. The
implementer must close both gaps. The spec is deliberately non-prescriptive
about the exact command sequence (the cross-session shared-window behavior is
version/client-dependent and could not be fully verified here); the
requirements are:

- The driver must be pinned (`window-size manual` + height pin) before the
  status grows, so the status grow never reflows the shared preview window.
- Candidate windows linked in later must be protected just as well. If the
  driver pin alone does not guarantee that on the target tmux (verify with a
  real client), freeze each candidate at link time too: set the candidate's
  `window-size` to `manual` and pin its window to its captured geometry, and
  restore the candidate's prior `window-size` on unlink. (A candidate's own
  attached clients should be unaffected by a manual pin that merely prevents
  auto-resize; verify.)
- Restore-time `select-layout` (section 9 step 5) must be a **no-op whenever
  the original window did not actually drift** (compare the pane-geometry
  snapshot captured at activation). Only if drift is detected: restore the
  window's exact size first, then `select-layout`. Leaving the window untouched
  is always preferable to moving its panes.
- If live linking cannot meet the invariant on a given setup, degrade to
  `@livepicker-preview-mode snapshot`, which renders `capture-pane` output and
  never touches a live window — the invariant then holds trivially.

**Verification (load-bearing, requires a real client).** Reproduce with a real
attached client (sessions created with `new-session -x -y` are size-locked and
hide the bug). Use the isolated-socket harness, and restore the user's live
state afterward. Assert, across open -> flip several windows -> move sessions ->
cancel, and across open -> flip -> confirm:

- Each candidate's pane geometry is byte-identical before and after.
- The original/driver window's pane geometry is byte-identical after cancel.
- On confirm, only the chosen window becomes active in the target session; no
  pane anywhere is resized.

**Control.** This invariant is always on; it is not optional.
`@livepicker-preview-fit clip` (section 22) is the primary mechanism; `reflow`
and `snapshot` are escape hatches if `clip` cannot meet the invariant on a
given tmux/terminal.
