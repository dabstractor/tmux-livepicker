# Changelog

All notable changes to tmux-livepicker are documented here. Format based on
[Keep a Changelog](https://keepachangelog.com/).

## [Unreleased]: two-axis navigation, window-flip preview, pane immutability

### Added

- **Two-axis discovered navigation** (PRD §8). The picker now has two navigation
  axes, and both reuse the keys you already have for that axis, discovered from
  your live key tables. The window axis flips the previewed session's windows
  (`next-window` / `previous-window` / `select-window -n` / `-p`, including your
  `swap-window ... ; select-window` compounds). The session axis moves the
  highlight between sessions (`switch-client -n` / `-p` plus the arrow keys).
  The four options `@livepicker-session-next-keys` / `-prev-keys` /
  `@livepicker-window-next-keys` / `-prev-keys` override discovery when set;
  otherwise discovery reads `tmux list-keys -T root` and `-T prefix`, drops plain
  letters and digits (reserved for the query), de-duplicates, and excludes the
  fixed control keys. This replaces the earlier single-axis model that
  repurposed window-nav into session-nav.

- **Window-flip preview + confirm-on-window** (PRD §6.6, §7). Flipping steps
  through a candidate's windows live, with the preview following each flip.
  Confirm lands on the exact window being previewed: it resolves the target
  session from the ranked list and the target window from the window cursor,
  commits that window with one `select-window`, then runs `switch-client`, so the
  client arrives on the chosen session and window. Flipping never changes the
  candidate's own active window (leave-no-trace, Invariant B): flips link the
  chosen window into the driver and select it there; no command targets the
  candidate session.

- **Pane immutability, Invariant C** (PRD §23, §4). No pane of any session
  (candidate, driver, or bystander) is moved, resized, reordered, reset, or
  altered by browsing, confirming, or cancelling, even though the preview is a
  shared window object. Enforced by prevention: the driver is pinned
  (`window-size manual` plus a height pin) so the status grow and the shared
  preview window cannot reflow; detached candidates are pinned at link time and
  restored on leave; and a pane-geometry snapshot taken at activate drives a
  drift-gated restore on exit (restore acts only if geometry drifted).

- **Defaults.** The four navigation options default to discovered (empty), so the
  new two-axis behavior is on out of the box. `@livepicker-preview-fit` defaults
  to `clip`. `@livepicker-preview-defer` defaults to `on`.

- **Invariants unchanged.** None of these changes the pollution and restore
  invariants the plugin already upholds (PRD §4 / §14). Browsing still never
  calls `switch-client` (Invariant A): the only switch is the single one at
  confirm, so the `tmux-session-history` timeline and the toggle are untouched.
  Flipping never changes a candidate's own active window or pane layout
  (Invariant B): every peeked session is left exactly as you found it. And no
  pane of any session is moved or resized (Invariant C): cancel restores the
  driver's window and pane geometry through the drift-gated restore.

- **Escape hatch for strict immutability.** For sessions where link-time pinning
  cannot apply (client-bearing candidates, because `window-size manual` reverts
  their client view), set `@livepicker-preview-mode snapshot`: it previews with
  `capture-pane` and never links or resizes a candidate window, so no
  candidate's geometry can drift.
