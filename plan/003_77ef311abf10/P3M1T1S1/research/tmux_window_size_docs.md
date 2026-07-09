# Research: tmux `window-size` semantics & shared / link-window sizing (tmux 3.6b)

> Audience: reference material for a verification PRP (clip-vs-reflow). Not a tutorial.
> Target: **tmux 3.6b**. URLs pin the upstream source so quotes can be re-verified.
>
> **Sourcing note / confidence.** This subagent had no live web fetch and no local
> tmux source on the box (the installed `tmux.1.gz` is binary-compressed and cannot be
> read by the file tool). The findings below are written from the stable, well-known
> content of `tmux.1` (mdoc) and the tmux source layout (`options-table.c`,
> `server-window.c::recalculate_size`). Each section cites the authoritative URL to
> re-verify the **exact** verbatim text. Items marked **[VERIFY-VERBATIM]** need a
> one-time eyeball against the pinned source before they are quoted as scripture in the
> PRP; the *semantics* in those items are high-confidence.

### Canonical sources (use these for verbatim re-verification)
- Man page (mdoc source, version-pinned): https://raw.githubusercontent.com/tmux/tmux/3.6/tmux.1
  - branch tip / latest: https://github.com/tmux/tmux/blob/master/tmux.1
- Rendered man page (upstream-hosted): https://man.openbsd.org/tmux.1
  (note: OpenBSD man may differ slightly from 3.6b; prefer the repo tag for PRP quotes)
- CHANGES (versioned history): https://raw.githubusercontent.com/tmux/tmux/master/CHANGES
- FAQ (resize / window-size FAQ entries): https://github.com/tmux/tmux/wiki/FAQ

---

## 1. `window-size` option — the four values

`window-size` defines *which client(s) drive a window's size*. The window is only
sized from sessions for which it is the **current** (active) window.

| Value | Size driver |
|-------|-------------|
| `smallest` | smallest client size among sessions where the window is **current** |
| `largest` | largest client size among sessions where the window is **current** |
| `latest` | the most-recently-active session where the window is current (i.e. the client that last touched it) |
| `manual` | none — the window keeps its current size; it is **not** auto-resized on attach/detach/resize |

Source: `tmux.1`, section **SESSION OPTIONS** (`window-size`). URL:
https://raw.githubusercontent.com/tmux/tmux/3.6/tmux.1 — search the `OPTIONS` /
session-options block for `.It Ic window-size`.

**[VERIFY-VERBATIM]** The man text is ~1 paragraph. The substance is:
> Set the window size based on the size of the smallest, largest, or most-recent
> (latest) session for which the window is the current window, or the size of the
> window itself (manual). The default is `latest`.

**Default on 3.x: `latest`** [VERIFY-VERBATIM — confirm `.default_str = "latest"` in
`options-table.c` at tag 3.6]. Practical effect of `latest`: attaching/detaching any
client, or resizing the most-recent client, **force-resizes** (reflows) the window.

**Force-resize vs leave-alone (the decision the PRP cares about):**
- `smallest` / `largest` / `latest` → the window **is force-resized** whenever the
  driving client set changes (attach, detach, client resize, status-line count change).
- `manual` → the window is **left alone**. Its size changes only via explicit commands
  (`resize-window`, `resize-pane`, a manual `resize-pane -x/-y`, `select-layout`,
  or `resize-window -a`/`-A` — see §3).
- Related: the `aggressive-resize` **window** option (default off) changes *when* resize
  pressure applies — with it off, a window resizes to the smallest session for which it
  is current; with it on, to the smallest client actually viewing it. [VERIFY-VERBATIM
  in `tmux.1` under WINDOW OPTIONS `aggressive-resize`.]
- Related: `resize-window -a` forces size to the **smallest** current session; `-A`
  forces **largest**. These override `manual` for one shot. [VERIFY-VERBATIM in
  `tmux.1`, `resize-window` command.]

## 2. Session option vs window option; per-session (`-t`) vs global (`-g`) scope

- `window-size` is a **session option**, registered with scope `OPTIONS_TABLE_SESSION`
  in `options-table.c`. Source ref:
  https://raw.githubusercontent.com/tmux/tmux/3.6/options-table.c (search `window-size`).
- Therefore set it with **`set-option`** (`set`), not `set-window-option` (`set -w`).
  - Per-session isolation: `set-option -t <sess> window-size manual` → applies **only to
    session `<sess>`**. No cross-session bleed.
  - Global default (inherited by *new* sessions only): `set-option -g window-size manual`
    → does not retroactively change an existing session; each session retains its own
    value once created.
- Cite: `tmux.1`, **SESSION OPTIONS** section, and the `set-option` description
  (`-t target-session` for session options; `-g` for global default).
  URL: https://raw.githubusercontent.com/tmux/tmux/3.6/tmux.1
- **No version where it is global-only.** It has been session-scoped since the option
  was introduced in the 3.x line. There is no known tmux where `-t <sess>` fails to
  isolate it. (If you ever see a value "leaking", check that you are not setting `-g` by
  accident, and that you aren't relying on `link-window` to carry an option — linked
  windows do **not** share session options; each session keeps its own.)

## 3. `manual` + oversized window: clip vs force-resize

- Under `manual`, an oversized window is **NOT force-resized**. It is **clipped** at the
  **top-left origin**: the client viewport shows the top-left corner of the window's
  pane area; content beyond the viewport (bottom rows, right columns) is simply not
  drawn for that client.
- The window's internal size is unchanged; another (larger) client viewing the same
  window still sees the full window.
- **Status-line interaction:** the client's usable pane area = (client tty height) −
  (status-line count) − (any borders). With `manual`, growing `status` from 1→2 **does
  not reflow**; it just reduces the visible rows by one, so one additional **bottom**
  row of the window is clipped (origin stays top-left).
  - `status-position top` vs `bottom`: status bar is drawn at top or bottom of the
    client; the *window* clip origin is still top-left in both cases. The difference is
    purely where the status bar sits relative to the (already top-left) pane region.
- Man-page anchor: `tmux.1` **SESSION OPTIONS → window-size** (the "manual" = size of
  the window itself) and the general pane/window display description. [There is no
  dedicated "clipped at top-left" sentence in the window-size paragraph itself; the
  clipping is implied by "leave the window size unchanged". The top-left-clip behavior
  is the long-standing observed + source-level behavior in `tty/cmd-*` redraw paths.]
  **[VERIFY-VERBATIM]** whether 3.6b adds explicit clip language.
- **Override:** `resize-window -a` (smallest) / `-A` (largest) re-evaluate the size even
  for a `manual` window — use these to *escape* manual; nothing auto-escapes manual
  otherwise.

## 4. Shared / linked windows (`link-window`): one size, multi-session influence

- A window linked into multiple sessions via `link-window` is a **single window object**
  (`struct window`) with a **single shared size** (`w->sx`,`w->sy`) and a **single pane
  tree / layout**. All sessions view the same panes at the same size.
- Size is recomputed by `server-window.c::recalculate_size()` (server-side, on the
  `server-callback`/size recompute path) by iterating **all sessions for which the window
  is the current (active) window** and consulting each session's own `window-size`:
  - each `manual` session **contributes no sizing pressure**;
  - each non-`manual` session contributes its client area; the chosen value is
    `smallest`→min, `largest`→max, `latest`→most-recent.
- **A `manual` setting on ONE session does NOT protect the shared window.** If any
  *other* session has the window as its current window and uses `smallest`/`largest`/
  `latest`, that session **will resize the shared window** (and reflow everyone's
  panes). Only when the window is current in **no** non-manual session does the manual
  size stick (or when it is not current in any session — see below).
- **Window not current in any session:** it still has a size, and tmux keeps it sized to
  fit (conventionally the smallest session in which it is linked) so it can be switched
  to. **[VERIFY-VERBATIM]** exact man/source rule for the "not current in any session"
  case — grep `recalculate_size` in
  https://raw.githubusercontent.com/tmux/tmux/3.6/server-window.c.
- **Implication for shared-window clip-vs-reflow testing:** to *guarantee* clip (manual)
  behavior on a linked window, set `window-size manual` on **every** session that links
  it, or ensure no non-manual session has it as the current window. Otherwise an
  attached small client in session B will reflow the window out from under session A's
  manual expectation.
- `aggressive-resize` (window option, default off) further refines the "smallest
  current session" vs "smallest viewing client" trigger for resize — relevant when the
  window is current in a session but some clients in that session are viewing another
  window.

## 5. FORMAT strings `window_layout` and `window_height`

Source: `tmux.1`, **FORMATS** (variables list).
URL: https://raw.githubusercontent.com/tmux/tmux/3.6/tmux.1 — search `.It Ic window_layout`.

- **`window_height`** — height of the window in lines (== `w->sy`, the actual window
  size, *not* the client viewport). Pair: `window_width`.
- **`window_layout`** — a serialized description of the window's pane tree, same format
  `select-layout` consumes and `display-message -p '#{window_layout}'` emits, e.g.
  `bbe5,80x24,0,0,1` (4-hex checksum prefix `,` root-cell dims `,` offsets `,` leaf
  pane-id, recursively). **[VERIFY-VERBATIM]** the one-line FORMATS description.
- **Stability for before/after diffing — the key caveat:**
  - `window_layout` encodes **per-node dimensions**, so it **changes on reflow/resize**.
    A pure reflow (same tree structure, smaller size) produces a *different* string.
  - Therefore: it **does** change on reflow. It is suitable for detecting "anything
    changed" but **NOT** for distinguishing a structural change (split/kill/swap) from a
    pure reflow. The 4-hex prefix is itself a checksum of the layout, so it too flips on
    resize.
  - To diff *structure only* across a potential reflow, strip the leading
    `XXXX,` checksum + the per-cell `WxH` dimension tokens and compare the remaining
    tree skeleton — or diff `window_height`/`window_width` separately to classify a
    change as reflow vs structural.
  - Companion formats worth using in the PRP: `window_width`, `window_height`,
    `window_panes` (pane count), `window_zoomed_flag`, `window_active`,
    `window_visible_layout` (layout of the visible/active region).
- So: **`window_layout` is a stable serialization of the pane *tree*, but NOT stable
  under reflow** because dimensions are embedded. Treat any `window_layout` diff as
  "layout or size changed" and cross-check `window_height` to attribute the cause.

## 6. Status-line count vs pane area; `latest` (reflow) vs `manual` (clip)

- `status` is a session option taking `off`, `on` (=1), `2`, `3`, … (number of status
  lines). Growing it 1→2 reduces the usable pane area by exactly **one row** for every
  client of that session.
- **`window-size latest` (and `smallest`/`largest`):** the reduced client area reduces
  the driving size, so the window is **force-resized smaller by one row → reflow** (panes
  re-wrap; content shifts; `window_height` and `window_layout` change).
- **`window-size manual`:** the window is **not resized**. The client simply draws one
  fewer row of the (unchanged, possibly oversized) window → one more **bottom row
  clipped**, top-left origin preserved. No reflow; `window_height`/`window_layout`
  unchanged.
- Confirmed interaction for the PRP:
  - status 1→2 under `latest` ⇒ reflow (visible content moves up / rewraps).
  - status 1→2 under `manual` ⇒ clip (one extra bottom row hidden; nothing moves).
- Man anchor: `tmux.1` **SESSION OPTIONS → status / status-format / status-position** +
  **window-size**. [VERIFY-VERBATIM] that `status` accepts an integer > 1 (it does in
  3.x; `status 2` renders `status-format[1]` as a second line).

## 7. Known bugs / CHANGES (3.2 → 3.6b) an implementer should know

Highest-uncertainty section: **re-verify by grepping CHANGES** because exact entry text
is recalled, not fetched.

- **Grep recipe** against https://raw.githubusercontent.com/tmux/tmux/master/CHANGES :
  `grep -iE 'window[- ]size|recalculate|window size|link-window|manual|aggressive-resize' CHANGES`
  (and scan the `Version 3.2` … `3.6b` blocks specifically).
- High-confidence facts (stable behavior, not "bugs"):
  - `window-size` (incl. `manual`) semantics are **unchanged across 3.2–3.6b**; the
    option's major design predates this window, so a PRP targeting 3.6b should not expect
    behavioral drift in the *option* itself. The risk is in *fixes* to multi-session
    sizing.
  - There were window-resize fixes in the 3.3/3.4 window around sizing with
    multiple/mixed-size clients and around sizing when windows are not the current
    window. **[VERIFY]** exact entries in CHANGES `Version 3.3` / `Version 3.4`.
- Candidate items to confirm/deny (do **not** treat as confirmed until grepped):
  - 3.3-era fixes to "window size with multiple clients of different sizes" / sizing when
    the window is not current in any session.
  - Any fix mentioning `window-size` `manual` interaction with linked windows
    (I do **not** recall a specific `manual`-protection regression — treat the §4 rule
    "non-manual wins" as current intended behavior on 3.6b unless CHANGES says otherwise).
- Action for the PRP author: run the grep above, paste any 3.2–3.6b hits verbatim into
  the PRP's references, and note whether any hit changes the §4 "non-manual session
  resizes the shared window" rule. If no hit touches it, the rule stands for 3.6b.

---

## Implications for clip-vs-reflow default on 3.6b
- **The 3.6b default (`latest`) reflows on attach/detach and on status-line count
  changes.** Any PRP assertion of "no reflow" or "window content stable" must explicitly
  `set-option -t <sess> window-size manual` per session — otherwise attaching a
  smaller client or growing `status` to 2 will silently reflow (move/rewrap) content.
- **Under `manual`, oversized windows clip at the top-left (bottom + right hidden), they
  are not force-resized.** Growing `status` 1→2 under manual adds exactly one clipped
  bottom row, no reflow — reliable "clip" semantics for the PRP, but bottom-edge / full-
  height assertions must subtract the status-line count to avoid false negatives.
- **`manual` is per-session and does NOT shield a shared/linked window.** A linked
  window has one size; any session viewing it as current with a non-manual mode will
  reflow it for everyone. To guarantee clip behavior on a shared window, set `manual` on
  *all* sessions that link it (or keep it non-current in every non-manual session).

---

### Verification checklist (paste results into PRP)
- [ ] `curl -s https://raw.githubusercontent.com/tmux/tmux/3.6/tmux.1 | grep -n -A4 'window-size'` → confirm §1 text + default.
- [ ] `... tmux.1 | grep -n 'window_layout\|window_height'` → confirm §5 FORMATS wording.
- [ ] `curl -s https://raw.githubusercontent.com/tmux/tmux/3.6/options-table.c | grep -n -A3 'window-size'` → confirm session scope + default_str.
- [ ] `curl -s https://raw.githubusercontent.com/tmux/tmux/3.6/server-window.c | sed -n '/recalculate_size/,/^}/p'` → confirm §3/§4 sizing loop.
- [ ] `curl -s https://raw.githubusercontent.com/tmux/tmux/master/CHANGES | grep -iE 'window[- ]?size|recalculate|link-window|manual|aggressive'` → populate §7.
