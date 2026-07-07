# Empirical Findings: tmux 3.6b behavior for delta 003 (§19/§20/§21/§22)

> Direct empirical verification on the installed tmux 3.6b, using isolated `-L`
> sockets with attached clients (via the `script` pty pattern). These are
> load-bearing facts the PRP agents must build on; they were NOT all covered by
> prior research (plan/002 covered §17/§18 only).

## Finding 1 — `window-size manual` EXISTS, is PER-SESSION, and CLIPS oversized windows  [§22, HIGH]

Tested: `tmux set-option -t <sess> window-size manual` then `resize-window -y 30`
while the attached client area is 24 rows.

- **Result:** the window stays **30 rows tall** (`window_layout` shows `80x30`),
  client_height is 24. tmux renders the top and clips the overflow — it does NOT
  force-resize back down. CONFIRMED clip behavior for a non-shared window.
- **Per-session isolation (EXP B):** `set-option -t drv window-size manual` sets
  `drv` to manual while `other` session shows empty (= falls back to global
  `latest`), and global stays `latest`. So `-t` isolates correctly; we save/restore
  the driver's value with `-t "$ORIG_SESSION"`, NOT globally.
- **Read scope:** `show-options -t <sess> -v window-size` returns the per-session
  value; `show-options -g -v window-size` returns the global. To SAVE the driver's
  current effective value, read `show-option -gv window-size` (the effective global
  default) — but note a session-scoped override would not be captured by `-g`. In
  practice the driver uses the global default (`latest`), so `-g` capture is
  correct; document this assumption.

## Finding 2 — BUT shared LINKED windows still reflow ~1 row on status-grow  [§22, VERIFY→PARTIAL]

**This is the subtlety the PRD §22 "Verification required" warned about, now
confirmed empirically.** A window linked from a source session into the
`window-size manual` driver is a SHARED object whose single size is influenced by
every session it is linked into.

- Test (EXP C): linked src's window into manual drv (status=1, came in at 23), then
  grew `status` to 2. Result: the linked window reflowed 23→22 (a 1-row shrink),
  and the SOURCE session's view of the same window ALSO went to 22.
- **Real-plugin ordering (EXP F):** freeze manual → grow status → THEN link
  candidate (nav). The self-session window present at the status-grow moment is the
  one manual protects (it does not dramatically reflow). Candidate windows linked
  AFTER status is already grown come in at the driver's current usable size (e.g.
  22 with status=2, client=24) — that is the **link-time resize** (the already-
  documented bugfix-001 "Detached candidate resize" limitation), NOT a per-nav
  reflow.
- **Implication for implementation:** the clip achieves its PRIMARY goal —
  eliminating the activation status-grow jank for the self-session preview — but
  does NOT fully eliminate reflow for linked candidate windows. This matches the
  PRD's explicit fallback: `@livepicker-preview-fit reflow` (or `snapshot`) if clip
  misbehaves. The P3.M1.T1 verification task GATES the clip implementation: confirm
  the exact ordering empirically in the harness; if the self-window clip is clean,
  ship `clip` as default; the linked-window link-time resize stays the documented
  limitation reconciled with bugfix-001.
- The exact heights are timing-sensitive (when `manual` takes effect relative to the
  status grow). The implementer must verify the freeze-before-grow ordering produces
  a non-reflowing self-window and document the residual.

## Finding 3 — kill-session does NOT remove linked windows from the driver (LEAK)  [§21 delete, §16, HIGH]

**Critical for the delete feature.** Test (EXP D): linked `victim`'s window `@1`
into `drv` (as preview does), then `kill-session -t victim` WITHOUT unlinking
first.

- **Result:** `@1:w` SURVIVES in `drv` after `kill-session`. The window is still
  linked into the driver, now an orphan with no source session.
- **Implication:** `session-mgmt.sh do-delete` MUST `unlink-window -t
  "$ORIG_SESSION:$linked_id"` FIRST (when `STATE_LINKED_ID` belongs to the victim)
  before `kill-session -t "=$S"`, else the preview window leaks into the driver as
  a permanent orphan. This is exactly the §16 "kill-session + linked preview leak"
  risk, now confirmed real. Use `unlink-window` WITHOUT `-k` (removes one link;
  the kill-session then destroys the window in its now-only session).

## Finding 4 — client_width, status-justify, window-status-separator, client-resized hook  [§10, §19, HIGH]

All the new layout primitives behave as the PRD expects (EXP E):

- `display-message -p '#{client_width}'` against the invoking client returns the
  width (e.g. 80). Use the existing `lp_client_format` helper to resolve against
  the invoking client (client-aware). Capture once at activate into
  `@livepicker-client-width`; the renderer reads ONLY this cache (no per-keystroke
  round-trip — §18 budget).
- `status-justify` reads via `show-options -g -v status-justify` (returns
  `absolute-centre` in this env / tubular). The renderer honors it for the
  query-empty, tabs-fit case.
- `window-status-separator` reads via `show-options -gwv window-status-separator`
  (global-window scope; returns a space here). Used as the inter-tab join in
  window-status mode.
- `client-resized` hook installs via `set-hook -g client-resized "<cmd>"` and shows
  as `client-resized[0] ...` in `show-hooks -g`. Save/restore mirrors the existing
  `session-window-changed` pattern (`tmux_get_hook` verbatim → replay, incl. `-b`).

## Finding 5 — prior research still valid (plan/002, §17/§18)  [HIGH]

The eight Q1-Q8 findings in `plan/002_facc52335e68/architecture/external_tmux_behavior.md`
remain authoritative and need not be re-verified:
- Q1: `display-message -p -t <sentinel>` expands the full `#{…}` tree (incl. `E:`).
- Q2: `#()` stdout is NOT re-parsed for `#{…}`; only `#[…]` applies.
- Q5/Q6: `run-shell -b` is non-blocking/non-cancellable; supersede via seq counter.
- Q7: `refresh-client -S` re-runs `#()`; safe per keystroke iff renderer is cheap.
- Q8: unmatched keys in a non-root key-table are DROPPED (preview is display-only).

## Summary table (load-bearing for PRP context_scopes)

| # | Claim | Status | Source |
|---|---|---|---|
| 1 | window-size manual clips oversized non-shared window | CONFIRMED | EXP A |
| 2 | window-size is per-session (-t isolates) | CONFIRMED | EXP B |
| 3 | shared linked window reflows ~1 row on status grow (manual doesn't fully prevent) | CONFIRMED | EXP C/F |
| 4 | kill-session leaks a linked window into the driver (must unlink first) | CONFIRMED | EXP D |
| 5 | client_width / status-justify / window-status-separator / client-resized hook all work | CONFIRMED | EXP E |
| 6 | fuzzy rank (subsequence + score) is pure-bash O(N·Q), no tmux calls | N/A — pure logic | §20 spec |
