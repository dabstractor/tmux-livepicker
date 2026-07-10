# External Dependencies & tmux Behavior Findings

## tmux version: 3.6b (target floor: 3.0)

All empirical verifications run on the installed 3.6b.

## 1. Window-ID Addressing (load-bearing — gates confirm form)

**Question:** Does `select-window -t "=$S:@id"` work for committing a window
choice in a candidate session at confirm time?

**Result (verified on isolated socket):**
```
select-window -t "=test_sess:@1"  →  rc=0, correct window becomes active
```

**Decision:** Use `select-window -t "=$S:$W"` where `W` is the `@id`. No fallback
to switch-client-then-select-window is needed on 3.6b. The delta_prd.md's
contingency (switch-client first if `=$S:@id` fails) is not triggered.

## 2. Key Discovery — list-keys Parsing

**Question:** What do `list-keys -T root` and `-T prefix` actually emit, and how
must discovery parse them?

**Finding:** The `bind-key` line format is:
```
bind-key [-r] -T <table> <key> <command...>
```
The `-r` flag (repeat) is OPTIONAL and shifts the key/command position. Discovery
must parse the key as the token after `-T <table>` (skipping an optional `-r`),
not by field position.

**Critical parsing detail:** Mouse bindings (`MouseDown3Status`, `WheelUpStatus`,
`M-MouseDown3StatusLeft`) contain `switch-client -n`/`next-window`/etc. INSIDE
`display-menu` blocks. Discovery MUST:
1. Match only the **top-level command token** immediately following the key spec
   (not a loose substring over the entire line).
2. **Exclude** keys matching `Mouse*` or `Wheel*` pattern.

**The swap-window compound pattern:** `C-M-Tab → swap-window -t +1 \; select-window -t +1`
The discovery for the window axis must match `select-window -t +1` (and `-t -1`)
as substrings of the command, which catches the compound after the `\;`.

## 3. Candidate Pane Immutability — Shared-Window Behavior

**Question:** Does linking a candidate window into the driver resize its panes?
And does freezing the candidate's `window-size` prevent it?

**Finding (from clip_verification.md §4, with real client):**
- A linked candidate window reflows ONCE at link time (to the driver's usable size).
- The candidate's SOURCE view is ALSO resized (shared window — one size, all sessions).
- `window-size manual` + `resize-window -y H` on the DRIVER prevents the driver-side
  reflow but does NOT cover candidate windows linked later.
- Freezing the CANDIDATE's `window-size` at link time may prevent the source-view
  resize — **requires real-client verification** (P3.M1.T1, gated).

**Confirmed-safe operations** (do not resize when session is not auto-resizing):
`link-window`, `select-window`, `unlink-window`.

**Forbidden during preview** (on any candidate/original window/panes):
`resize-window`, `resize-pane`, `select-layout`, `swap-pane`, `swap-window`,
`move-pane`, `move-window`, `break-pane`, `join-pane`, `pipe-pane`, geometry `setw`.
**EXCEPTION:** The activation-time driver pin (`window-size manual` + `resize-window -y H`)
and the conditional candidate link-time pin (P3.M2.T2).

## 4. Deferred Preview — run-shell -b Behavior

**Finding (from external_tmux_behavior.md Q5/Q6, already verified):**
- `tmux run-shell -b` launches a detached command that returns immediately (~4ms).
- The background job is NOT cancellable — supersession is achieved via a seq-number
  guard in `preview.sh` (3 guards: top-of-function, before-unlink, before-commit).
- The seq is bumped in `input-handler.sh::_lp_fire_preview` before each fire.
- A stale job reads the seq, finds it advanced past its captured value, and no-ops.
- `clear_all_state` unsets the seq on teardown, so post-teardown jobs also no-op.

## 5. link-window / unlink-window Semantics (already verified in prior plans)

- `link-window` does NOT fail when the window is already linked in the target
  session — it silently creates a DUPLICATE. So always unlink the previous preview
  before linking a different one.
- `unlink-window` without `-k` removes ONE link; the source session keeps its window.
  It fails (rc=1) only when singly-linked → always `|| true`. NEVER pass `-k`.
- Window IDs are server-global and survive `renumber-windows on`. Address by `@id`.
- `unlink-window` fires `window-unlinked` only — NOT `session-window-changed` or
  `client-session-changed`.

## 6. Modal Key Table Behavior

- While `key-table` is `livepicker`, tmux consults ONLY that table.
- Unbound keys are DROPPED (not passed to root/prefix/pane) — verified.
- `key-table` must be set with `-g` (global) on 3.6b.
- `kill-key-table` does NOT exist on 3.6b; use `unbind-key -a -T livepicker`.
- Binding order matters: tmux keeps the LAST binding for a key, so explicit
  picker binds (steps 2-6) override copied user bindings (step 1).

## 7. Sibling Plugins (context only — no interaction changes)

- **tmux-session-history:** monitors `client-session-changed`. Our preview uses
  `link-window`+`select-window` (never fires `client-session-changed`). Confirm
  fires exactly one. Cancel fires zero (same-session deduped). No conflict.
- **tmux-sessionx:** being replaced by livepicker. No runtime interaction.
- **tubular (status theme):** owns `status-left`/`status-right`/`window-status-format`.
  Our renderer takes `status-format[0]` (line 1) and leaves line 2 to compose from
  tubular's defaults. No conflict.
- **zoxide:** optional `@livepicker-zoxide-mode`. Shells out to `zoxide query`.
  Falls back to plain create on no match.

## 8. Test Harness

- `tests/setup_socket.sh` creates an isolated `-L` socket (never touches the real server).
- `attach_test_client` spawns a real pty client via `script` (reports 80×24).
  Required for pane-immutability tests (detached sessions are size-locked).
- Tests pin `@livepicker-preview-defer off` for deterministic state assertions,
  `on` for deferred re-link assertions.
- All tests are bash scripts run via `tests/run.sh`.
