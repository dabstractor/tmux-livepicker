# Delta PRD 004: Two-axis navigation, window-flip preview, pane immutability

> A changeset against the already-shipped, green implementation (plan-001 +
> rev-002 §17/§18 + bugfix-001/002 + delta-003 §19/§20/§21/§22 + the
> already-landed renderer-cache/fork-free-width work). One cohesive theme drives
> it: **the picker gains a second navigation axis.** Today the user's window-nav
> keys are *repurposed* into session-nav while the picker is open. This delta
> instead keeps window-nav keys doing window navigation (scoped to the previewed
> session) and adds separate, *discovered* session-nav keys — so the user can
> flip through a candidate's windows live, confirm lands on the exact window,
*and* nothing a user peeks at is ever mutated. Nothing that already works is
> rebuilt; the renderer/layout/ranking/management/clip code stays.

## 0. What changed (diff: 003 → 004)

PRD diff is ~551 lines added / 195 removed (commit `ee3c8d0`). The changes cluster
into one coherent feature plus a hardening pass:

- **§8 — The key subsystem (two-axis, discovered).** Replaces the *repurposed*
  single-axis design (window-nav keys → session-nav) with **two axes**: a
  **window axis** (discovered window-nav keys flip the previewed session's
  windows) and a **session axis** (discovered `switch-client -n`/`-p` keys + the
  arrows move between sessions). Both axes are **discovered from the user's live
  key tables** (`list-keys -T root/prefix`), replacing the hardcoded
  `@livepicker-next-key`/`-prev-key` defaults. Window-nav keys are **no longer
  repurposed** — they keep doing window navigation, scoped to the preview.
- **§6 Window navigation + §7 chosen-window preview.** The preview now shows a
  **chosen window** (the candidate's active window by default; whichever window
  the user flipped to otherwise). A flip links the chosen window into the driver
  and selects it **there** — never `select-window` on the candidate — so the
  candidate's own active window never changes ("leave no trace").
- **§6 Confirm lands on (session, window).** Confirm resolves the chosen window
  from the new window-cursor, commits it in the target with one `select-window`,
  then does the single `switch-client`. The client lands on the exact tab being
  previewed.
- **§4 + §23 — Pane immutability (Invariant C), absolute.** Formalizes a third
  invariant alongside the existing "no client switch" (A) and "no candidate
  mutation" (B): **no pane of any session is ever moved or resized** — even
  though the preview is a *shared* window object whose size is influenced by every
  session it is linked into. New §23 owns the prevention regime and a
  load-bearing empirical verification that closes the residual "linked candidate
  reflows at link time / source view is disturbed" gap left open by delta-003 §22
  (`clip_verification.md` §4).

Cross-cutting modifications ride with the features (not standalone): §1/§2/§3
(overview, goals/non-goals, user stories for two-axis + flip + leave-no-trace),
§5 data flow, §6 (activation init, session-nav resets window-cursor, cancel is a
hard reset), §7 (mechanism renamed "on the driver only"; self-session flip), §9
(pane-geometry snapshot; runtime window-cursor keys; restore keep skips
ORIG_WINDOW; drift-gated select-layout), §11 (4 options removed, 4 added), §12/§13
(file layout + primitives), §14 (Invariant B/C proven), §15 (new Pane-immutability
§15.23 + Key-discovery/two-axis §15.24 validation), §16 (new risks), §18
(window-flip defers like session-nav — the renderer "second root cause" text here
is **already shipped**, see below), §20 (perf note, also already shipped).

### Already shipped (NOT delta tasks — do not create work for these)

- **§18 "A second root cause: the redraw itself."** The renderer static-config
  cache (`STATE_RENDER_CACHE` / `_lp_build_render_config` / `_lp_load_render_config`)
  and the fork-free width pass (`layout.sh::_lp_measure_into`) are **already in
  the tree** (commits `6936ac0` + `2e8da31`). The PRD merely documents them now.
  No task here.
- **§20 Performance note + §16 FORK-FREE note.** Same code, already shipped.

## 1. Invariants that still hold (this delta extends, does not break, them)

- **Invariant A (§4, unchanged):** browsing never fires `client-session-changed`.
  The new window-flip links the chosen window into the **driver** and selects it
  there; no command targets a different session. Confirm is still the one switch.
- **Deferred-preview supersede (§18, unchanged machinery):** the window-flip
  re-link routes through the existing `_lp_preview_dispatch` /
  `_lp_fire_preview` / `STATE_PREVIEW_SEQ` 3-guard machinery. No new inline
  `link-window`. Confirm reads window-cursor state authoritatively and does not
  depend on a preview having run.
- **Save/restore contract (§9):** every new runtime key (window-cursor +
  preview-win-id) is added to `_STATE_RUNTIME_KEYS`; the new pane-geometry
  snapshot is an `ORIG_*` saved key (auto-cleared). Restore `keep` (session
  confirm) now skips the ORIG_WINDOW re-select exactly as `keep-window` already
  does, so the client stays on the chosen `(S, W)`.
- **Single source of truth for the list order:** `rank.sh::lp_rank` remains the
  shared ranker. Window-nav/flip add a **per-candidate window list** (separate
  from the session list); confirm/nav/flip all read the same window-cursor.

## 2. Dependency graph

```
P1 (§8 two-axis keys: discovery + options + binding) ──► P2 (window flip + confirm-on-window: needs the bound keys + the new actions)
                                                            │
                                                            └──► P3 (§23 pane immutability: verifies P2's flip doesn't mutate; hardens restore)
                                                                     │
                                                                     └──► P4 (Mode B changeset-level docs)
```

P1 lands first (it binds keys to actions that are inert until P2 implements
them). P2 is the core window-picking feature (depends on P1's bindings + the
new input actions). P3 is the §23 verification-gated hardening (depends on P2's
flip mechanism to verify). P4 (README + CHANGELOG) runs last.

## 3. Completed work this builds on (do NOT re-implement)

- **`scripts/state.sh`**: the `STATE_*`/`ORIG_*` contract, `_STATE_RUNTIME_KEYS`
  clear-list, `clear_all_state`. Add window-cursor keys + pane-geometry snapshot
  by the established pattern. `STATE_LINKED_ID` already tracks the linked window —
  note `@livepicker-preview-win-id` overlaps it for non-self candidates (and
  diverges only for the self-session, where linked-id is empty).
- **`scripts/options.sh`**: `get_opt` + one `opt_<name>()` per option. **REMOVE**
  `opt_next_key`/`opt_prev_key`/`opt_nav_next_keys`/`opt_nav_prev_keys`; **ADD**
  `opt_session_next_keys`/`-prev-keys`/`opt_window_next_keys`/`-prev-keys`
  (defaults empty/unset → discovery fills them).
- **`scripts/utils.sh`**: `lp_filter_harmful_bindings` (DROPS
  `switch-client`/`next-window`/`previous-window`/`select-window -n/-p` from the
  copied bindings), `lp_resolve_client`/`lp_client_format`. Add a new
  `lp_discover_axis_keys` helper here (it parses `list-keys`, sibling to the
  filter). **Discovery reads the RAW `list-keys` BEFORE the harmful filter is
  applied** — the filter drops these keys from the *copy*, but discovery must see
  them.
- **`scripts/livepicker.sh::activate_main`**: T4 binding block (copy → typing →
  backspace/confirm/cancel → nav → mgmt). P1 reworks T4 to discover + bind two
  axes; P2 adds the window-cursor init at T2/T6; P3 adds the pane-geometry
  snapshot at STEP 2. `_lp_build_render_cache` already exists (do not touch).
- **`scripts/input-handler.sh::input_main`**: dispatches
  type/backspace/next-session/prev-session/confirm/cancel/rename/delete/
  refresh-width, with `_lp_invalidate_pending_preview`/`_lp_status_redraw`/
  `_lp_preview_dispatch`/`_lp_scroll_into_view` helpers. P2 adds
  `next-window`/`prev-window` actions + resets the window-cursor on
  session-nav/type; reworks `confirm` to land on the window.
- **`scripts/preview.sh::preview_main`**: the link-window core with the 3-guard
  seq supersede, idempotent pre-link check, self-session guard, capture fallback.
  Currently shows only the candidate's **active** window. P2 extends it to accept
  a chosen window id (flip target); P3 may add candidate-window pinning at link
  time (gated by verification). It already links into `ORIG_SESSION` (the driver)
  and selects there — so Invariant B for **session-nav** is already satisfied.
- **`scripts/restore.sh::restore_main`**: 6-step teardown. STEP 2 already has a
  `keep-window` branch that skips the ORIG_WINDOW re-select. P2 makes session
  `keep` skip it too; P3 makes STEP 5 drift-gated.
- **`plan/003_77ef311abf10/architecture/clip_verification.md`**: the prior clip
  research. Its §4 **already proved** the residual P3 must now close (a linked
  candidate reflows once at link time and its **source view is also resized**).
  P3 builds directly on that evidence.
- **`tests/` harness**: `setup_test` (isolated socket, pins defer off),
  `attach_test_client` (real client), renderer-seed idiom. New tests mirror these.

---

## Phase P1 — Two-axis key subsystem (discovery + options + binding)

> §8 rework. The picker gains two discovered navigation axes. The window-nav keys
> keep doing window navigation (scoped to the previewed session); a separate
> session-nav axis moves between sessions. Both are discovered from the user's
> live key tables. **Inert until P2 lands the preview/flip/confirm actions** —
> the new bindings store command strings that reference actions not yet
> implemented (the input-handler default `*` branch is a no-op).

### Milestone P1.M1 — Options + discovery helper

**Mode A docs:** `README.md` Configuration table — **remove** the
`@livepicker-next-key`/`-prev-key`/`-nav-next-keys`/`-nav-prev-keys` rows;
**add** `@livepicker-session-next-keys`/`-session-prev-keys`/
`@livepicker-window-next-keys`/`-window-prev-keys` rows noting the
(discovered) defaults and the "must be non-alphanumeric" constraint. (Full
prose lands in P4.)

#### Task P1.M1.T1 — Replace the 4 nav options + remove the 4 old ones

`options.sh`: **delete** `opt_next_key`/`opt_prev_key`/`opt_nav_next_keys`/
`opt_nav_prev_keys`. **Add** four space-list accessors with EMPTY defaults (so an
unset option means "run discovery"):
`opt_session_next_keys()`/`opt_session_prev_keys()`/`opt_window_next_keys()`/
`opt_window_prev_keys()`, each `get_opt "@livepicker-<suffix>" ""`. A non-empty
user-set value **overrides** discovery for that axis (PRD §8: explicit options
win). Note: the empty-default accessor is intentional — activate distinguishes
"explicitly set" (non-empty) from "discover" (empty).

#### Task P1.M1.T2 — `lp_discover_axis_keys` helper (utils.sh)

Add a pure-ish helper `lp_discover_axis_keys <axis> <direction>` (axis: `window`|
`session`; direction: `next`|`prev`) that scans `tmux list-keys -T root` and
`tmux list-keys -T prefix` and prints the de-duplicated, letter/digit-dropped key
list for that axis+direction. Rules (PRD §8 Discovery):

- **Window axis next** = a binding whose top-level command contains
  `select-window -n`, `select-window -t +1`, `select-window -t :+1`,
  `next-window` (and `-a`), or the `swap-window … \; select-window -t +1`
  compound; **prev** symmetric (`-p`, `-t -1`, `:-1`, `previous-window`).
  Matching on the command token **catches the user's
  `swap-window \; select-window` compounds** (verified: `C-M-Tab`/`C-M-BTab`).
- **Session axis next** = `switch-client -n`; **prev** = `switch-client -p`.
  Do **not** treat `-l` (toggle) or `-t <name>` as axis keys. **Always add**
  `Down` (next) / `Up` (prev) as universal session-axis extras.
- **Drop any plain `a`-`Z`/`0`-`9`** key (the user's prefix-table `n`/`p` and
  digit `:=N` bindings stay reserved for typing). Keep control/meta/arrow/
  function keys.
- **De-duplicate**; **exclude** any key that collides with the fixed control keys
  (`opt_confirm_keys`/`opt_cancel_keys`/`opt_backspace_keys`/`opt_rename_key`/
  `opt_delete_key`) so discovery never shadows them.

**Load-bearing parsing detail (call out in the subtask):** the live root table
contains **mouse** bindings (`MouseDown3Status`, `WheelUpStatus`, `WheelDownStatus`,
`MouseDown3StatusLeft`) whose lines *contain* `swap-window`/`next-window`/
`previous-window`/`switch-client -n` **inside `display-menu` blocks** — those are
NOT keyboard nav and must NOT be collected. Discovery must (a) match only the
**top-level command token immediately following the key spec** (parse the key
field + the command word, not a loose substring over the whole line), and (b)
**exclude keys matching `Mouse*`/`Wheel*`** (status-bar click handlers). Verify
against the live server: for this user discovery yields window next
`C-M-Tab M-n C-n C-l`, window prev `C-M-BTab M-p C-p C-h`, session next `) Down`,
session prev `( Up` — and `n`/`p`/digits/mouse keys are absent.

### Milestone P1.M2 — Activate binding rework (T4)

**Mode A docs:** `README.md` Usage — replace the "repurposed window-nav keys"
description with the two-axis description (session-nav keys move sessions;
window-nav keys flip the previewed session's windows; both discovered from your
config). (Full prose in P4.)

#### Task P1.M2.T1 — Rework activate T4 to bind two axes (discovered)

`livepicker.sh` activate T4 — **before** the copy block, resolve each axis's keys
into local vars (explicit option if set, else `lp_discover_axis_keys`). Then bind
in this order (tmux keeps the **last** binding, so each step overrides earlier):
1. COPY prefix+root → livepicker (existing `lp_filter_harmful_bindings` pipeline;
   unchanged — it already drops the nav keys from the copy, which is correct
   since steps 3–4 re-bind them as picker actions).
2. Typing: `a`-`z` `A`-`Z` `0`-`9` `-` `_` `.` `/` → `type <c>` (unchanged).
3. **Window axis**: each discovered/explicit next-window key →
   `input-handler.sh next-window`; each prev-window key → `prev-window`.
4. **Session axis**: each discovered/explicit next-session key → `next-session`;
   each prev-session key → `prev-session`.
5. Confirm/cancel/backspace (unchanged); then mgmt rename/delete (unchanged).

Keep the existing skip/grep plumbing for the copy. Verify the bindings are inert
(P2 implements the actions; until then `next-window`/`prev-window` hit the `*`
no-op branch and the picker stays open). Re-run `tests/test_keyrepurpose.sh` /
the binding-assertion tests and update them for the new key set.

---

## Phase P2 — Window-level picking: flip + confirm-on-window + window-cursor

> The core feature. Adds the per-candidate window-cursor state, extends
> `preview.sh` to show a chosen window, adds the `next-window`/`prev-window`
> input actions, and reworks confirm to land on `(S, W)`. Depends on P1 (the
> bound window-axis keys fire these actions). Invariant B is the design driver:
> **a flip links the chosen window into the driver and selects it there, never
> `select-window` on the candidate** — so the candidate's active window never
> changes.

### Milestone P2.M1 — Window-cursor state + preview chosen-window + flip actions

**Mode A docs:** `README.md` Usage — add the window-flip behavior (while
previewing a session, your window-nav keys flip its windows live; line 2's
window-status follows the flip; the session's own active window is untouched).
(Full prose in P4.)

#### Task P2.M1.T1 — Window-cursor state keys

`state.sh`: add four runtime keys + append all four to `_STATE_RUNTIME_KEYS`
(mandatory):
`STATE_CAND_WIN_SESSION` (`@livepicker-cand-win-session` — the candidate the
cached list belongs to; cache-invalidation key),
`STATE_CAND_WIN_LIST` (`@livepicker-cand-win-list` — newline-joined ordered
window ids of that candidate),
`STATE_CAND_WIN_CURSOR` (`@livepicker-cand-win-cursor` — index into the list;
defaults to the candidate's active window on entry),
`STATE_PREVIEW_WIN_ID` (`@livepicker-preview-win-id` — the window currently
shown; overlaps `STATE_LINKED_ID` for non-self candidates, diverges for the
self-session where linked-id is empty). Initialize at activate (T2/T6): cursor
= the current session's active window index; the list/session are derived lazily
on first nav/flip. No behavior change until T2/T3.

#### Task P2.M1.T2 — `preview.sh` shows a chosen window (flip target)

Extend `preview_main` to accept `argv[2] = <window-id>` (the chosen window; when
absent, fall back to the candidate's active window — the current behavior, so
session-nav is unchanged). The link flow already targets `ORIG_SESSION` (the
driver); keep it that way. **Leave-no-trace (Invariant B):** when a chosen window
is supplied, link THAT window (not necessarily the active one) into the driver and
`select-window` it **in the driver** — never target the candidate session. The
existing idempotent pre-link check + duplicate guard + 3-guard seq supersede
still apply (a flip is a re-link of a different window of the same candidate, so
unlink the prior linked window first as today). Snapshot/`off` modes: a flip in
`snapshot` mode captures the chosen window's active pane (`=$S:$W.` form, reusing
the existing window-mode pane-spec logic); `off` is a no-op. Self-session: a flip
selects among the driver's own windows (no link) — this moves the driver's active
window while browsing, which cancel's hard reset undoes (P3/P2.M2).

`preview.sh` signature becomes `preview.sh <session> [window-id] [seq]` — extend
the existing `$2`-seq handling so the deferred path still passes the seq (shift
the seq to `$3`, or keep `$2` as window-id and pass seq via an env var / a 4th
arg). Preserve the supersede contract exactly.

#### Task P2.M1.T3 — `next-window` / `prev-window` input actions

`input-handler.sh`: add `next-window)` / `prev-window)` actions. Each: invalidate
the pending preview (`_lp_invalidate_pending_preview`); **lazily derive** the
current candidate's window list if `STATE_CAND_WIN_SESSION` != the highlighted
session (re-derive `STATE_CAND_WIN_LIST` from
`list-windows -t "=$S" -F '#{window_id}'` and reset `STATE_CAND_WIN_CURSOR` to
the candidate's active window); advance/wrap the cursor within the list; resolve
`W = cand-win-list[cursor]`; `_lp_status_redraw` (so line 2's window-status
follows the flip — line 1 is unchanged); `_lp_preview_dispatch "$S" "$W"`
(routed through the deferred supersede machinery — never inline). The flip
**never calls `select-window` on the candidate** (Invariant B). Mirror the
existing `next-session`/`prev-session` sequencing (status-redraw FIRST, then the
deferred re-link).

Also: **session-nav and type reset the window-cursor** (PRD §6 Session nav /
Filtering). In `next-session`/`prev-session`, after setting the new index, set
`STATE_CAND_WIN_SESSION` to the new candidate and reset `STATE_CAND_WIN_LIST`/
`STATE_CAND_WIN_CURSOR` (re-derived lazily on the next flip; defaults to the new
candidate's active window). In `type`/`backspace`/cancel-clear, reset the cursor
to the top match's active window (the top match is index 0; the cursor follows the
session-nav reset). This means per-candidate flip history is **not** remembered
across session moves (Invariant B / PRD §6).

### Milestone P2.M2 — Confirm lands on (session, window) + restore keep-skip

**Mode A docs:** `README.md` Usage — confirm now lands on the chosen session
**and the exact window being previewed**. (Full prose in P4.)

#### Task P2.M2.T1 — Confirm resolves (S, W) and commits the window

`input-handler.sh` `confirm)`: resolve `S` from `ranked[index]` as today; resolve
`W` from `STATE_CAND_WIN_CURSOR` (the window currently previewed for `S`; for
self-session or `snapshot`/`off` with no chosen window, `W` = the session's active
window). Then (PRD §6 Confirm):

- If a target `S` exists:
  - **Commit the window in `S`** with one `select-window` targeting the window id
    (the single, deliberate candidate mutation — Invariant B). **Verify the
    addressing form on 3.6b** (load-bearing): try `select-window -t "=$S:$W"`
    where `W` is the `@id`; if `=$S:@id` is not accepted, fall back to
    `switch-client -t "=$S"` first then `select-window -t "@id"`. Record which
    form works.
  - **Unlink the driver's preview link** (`ORIG_SESSION:$linked_id`) **before**
    the switch — exactly as `_confirm_land_on_session` already does (mirror its
    H2-hardened unlink: only unlink when the driver retains another window).
    Target `ORIG_SESSION` explicitly, NOT the post-switch current session.
  - `switch-client -t "=$S"` — the one session switch; the client lands on `S:W`.
  - **Self-session** (`S == ORIG_SESSION`): skip the `switch-client`; the single
    `select-window -t "$W"` is the whole commit (drop the driver preview link
    only if it is not `W`).
  - `restore.sh keep` — which must NOT re-select ORIG_WINDOW (T2 below).
- Empty ranked list + session mode + `@livepicker-create on`: unchanged (a
  brand-new session has one window; no window choice) — keep the existing
  `_confirm_land_on_session` create path.
- Window mode (`@livepicker-type window`): unchanged (`select-window -t
  "<session>:<window>"`; the existing `keep-window` restore already skips the
  re-select).

`confirm` reads window-cursor state **authoritatively** — it must not depend on a
deferred preview having run (PRD §18 contract #4).

#### Task P2.M2.T2 — Restore `keep` skips the ORIG_WINDOW re-select

`restore.sh` STEP 2: today `keep-window` skips the `select-window -t
"$ORIG_WINDOW"`; session `keep` does NOT. P2's confirm now lands the client on
`S:W`, so session `keep` must ALSO skip the re-select (else restore would yank
the client off the chosen window). Unify: treat **both** `keep` and `keep-window`
as "do not re-select ORIG_WINDOW" (the client is already where confirm put it);
only `cancel` re-selects ORIG_WINDOW. Update the STEP-1 unlink to target
`ORIG_SESSION` explicitly (PRD §9 restore step 1: "not the client's current
session — on a confirm/keep the client has already switched to the target") —
this is already the case via the H2-hardened `ORIG_SESSION` guard; verify it
holds after the confirm rework. Cancel's hard reset is P3 (drift-gated restore).

### Milestone P2.M3 — Validation (window flip + confirm-on-window)

**Mode A docs:** none (internal tests).

#### Task P2.M3.T1 — `test_window_flip.sh` (flip + leave-no-trace + confirm-on-window)

Under the isolated socket + `attach_test_client` (defer pinned off for
determinism where the assertion is about state, ON where it is about the
deferred re-link): (a) **flip** — preview a multi-window candidate; send
`next-window` repeatedly; assert each chosen window is linked into the driver
(`list-windows -t =driver` contains it) and selected, and line 2 follows; (b)
**leave-no-trace (Invariant B)** — before/after a flip sequence, assert the
candidate's `#{window_active}` + `window_layout` are byte-identical (the flip
never selected a window in the candidate); (c) **confirm-on-window** — flip to a
non-active window `W`, confirm; assert the client lands on `S:W` (the chosen
window, not the session's prior active window); (d) **cursor reset** — flip a
candidate's windows, move to another session, come back; assert the candidate is
re-previewed on its own active window (flip history not remembered); (e)
**self-session flip** — flip the driver's own windows, cancel; assert the driver
is back on ORIG_WINDOW. Mirror `test_preview.sh`'s lifecycle.

---

## Phase P3 — Pane immutability (§23): snapshot, drift-restore, verify, candidate pin

> §23. The absolute invariant: **no pane of any session is ever moved or
> resized.** Delta-003's `clip_verification.md` §4 already proved the residual
> this phase closes: a linked candidate reflows once at link time AND its source
> view is resized (shared window). This phase (1) verifies whether freezing the
> candidate at link time prevents that, (2) implements candidate-window pinning
> if the verification says it is needed, and (3) hardens activate/restore so a
> drifted original window is only repaired when it actually drifted. Carries a
> **load-bearing empirical verification** that gates the candidate-pin code.

### Milestone P3.M1 — Empirical verification of candidate-window pinning (gates code)

**Mode A docs:** none (internal research doc).

#### Task P3.M1.T1 — Verify candidate pinning on 3.6b with a real client

Build directly on `plan/003_77ef311abf10/architecture/clip_verification.md` §4
(which already reproduced the link-time resize + source disturbance). On the
isolated socket with `attach_test_client`, link a candidate window into the
driver, then set the **candidate's** `window-size` to `manual` and pin its window
to its captured geometry (`resize-window -y <source-height>`), and assert the
candidate's **source view** no longer changes. Record to
`plan/004_2c5127285a90/architecture/pane_immutability_verification.md`:
- Does freezing the candidate at link time prevent the source-view resize?
  (Candidate `window-size manual` + geometry pin, restored on unlink.)
- Does it disturb the candidate's own attached clients? (Reasoned: a manual pin
  that only prevents auto-resize should be benign; verify.)
- Does a **window-flip re-link** (P2) ever resize the chosen window? (Link a
  second window of the same candidate and assert no per-flip reflow.)
- Reproduce the §15.23 assertions with a real client (the `script` pty IS a real
  client and reproduced the resize in clip_verification §4; confirm it reproduces
  the flip path too). Restore the user's live state afterward.

**Decision:** if candidate pinning holds the invariant, P3.M2.T2 ships it; if it
does not (or is too invasive), document that `@livepicker-preview-mode snapshot`
is the required setting for strict pane-immutability and ship the snapshot escape
as the documented contract (no candidate-pin code). This GATES P3.M2.T2.

### Milestone P3.M2 — Pane-geometry snapshot + drift-gated restore + (conditional) candidate pin

**Mode A docs:** `README.md` Known limitations — update the "Detached candidate
windows are resized during preview" / bugfix-001 note per the P3.M1.T1 decision:
either the candidate is now pinned (no resize) or the note states that strict
pane-immutability requires `@livepicker-preview-mode snapshot`. State the
leave-no-trace guarantee (every peeked session snaps back). (Full prose in P4.)

#### Task P3.M2.T1 — Pane-geometry snapshot at activate + drift-gated restore

`livepicker.sh` STEP 2: alongside the existing `ORIG_LAYOUT` capture, also capture
a **pane-geometry snapshot** of the original window
(`#{pane_id}`/`#{pane_left}`/`#{pane_top}`/`#{pane_width}`/`#{pane_height}` per
pane, via `list-panes -t "$ORIG_WINDOW" -F`). Store in a new `ORIG_*` key
(`@livepicker-orig-pane-geometry`, auto-cleared). `restore.sh` STEP 5: replace
the unconditional `select-layout "$ORIG_LAYOUT"` with a **drift check** —
re-capture the original window's current pane geometry; if it equals the
activation snapshot, **do nothing** (the common case — leave panes alone rather
than risk moving them, PRD §9 step 5 / §23); only if it drifted, restore the
window's exact size first, then `select-layout "$ORIG_LAYOUT"`. `select-layout`
is size-dependent and can itself move panes, so it is a **last resort, never
routine**. This is the §23 "prevent, never repair" stance: prefer leaving the
window untouched.

#### Task P3.M2.T2 — Candidate-window pinning at link time (CONDITIONAL on P3.M1.T1)

**Only if** `pane_immutability_verification.md` says candidate pinning holds the
invariant. `preview.sh`: when linking a non-self candidate window, **before** the
`link-window`, capture the candidate's session `window-size` (per-session) and
the window's geometry; after the link, set the candidate's `window-size` to
`manual` and pin the window to its captured geometry (so the driver's smaller
usable area cannot reflow it and cannot disturb the source view). On unlink
(next nav / restore), restore the candidate's prior `window-size`. **Forbidden
during preview** (PRD §23): never `resize-pane`/`select-layout`/`swap-*`/`move-*`/
`break-pane`/`join-pane`/`pipe-pane`/geometry `setw` on any candidate or original
window — the only allowed mutation is the activation driver pin (delta-003 §22)
and this candidate link-time pin. If P3.M1.T1 decided pinning is infeasible, this
task is a no-op and the snapshot escape is the documented contract.

### Milestone P3.M3 — Validation (§23 pane immutability)

**Mode A docs:** none (internal tests).

#### Task P3.M3.T1 — `test_pane_immutability.sh` (Invariant C, real client)

Under the isolated socket + `attach_test_client`, with a candidate whose active
window has a multi-pane layout: capture each pane's
`#{pane_left}`/`#{pane_top}`/`#{pane_width}`/`#{pane_height}`. Then: (a)
**flip + cancel** — flip several windows, move sessions, cancel; assert the
candidate's pane geometry is byte-identical to the pre-pick snapshot; (b)
**status-grow** — assert opening the picker (status 1→2) does not change the
candidate's geometry; (c) **confirm** — confirm on `S:W`; assert `S`'s OTHER
windows are unchanged and within `W` only the active-window selection changed
(pane geometry of `W`'s panes unchanged); (d) **original window** — after a full
browse→cancel, the driver's original-window geometry is byte-identical to the
activation snapshot (and `select-layout` did NOT run — assert via the
drift-check). If P3.M1.T1 decided snapshot is required, assert the invariant
holds trivially under `@livepicker-preview-mode snapshot`. Restore the user's
live state afterward.

---

## Phase P4 — Sync changeset-level documentation (Mode B)

> Depends on P1, P2, P3. Sweeps the two-axis nav, window-flip, confirm-on-window,
> and leave-no-trace invariants into the README overview and CHANGELOG. Do NOT
> edit `PRD.md` (read-only).

#### Task P4.T1 — README + CHANGELOG changeset sync

- **README.md** — fold the per-feature Mode-A edits (P1 keybinds/options, P2
  window-flip + confirm-on-window, P3 leave-no-trace/limitations) into coherent
  prose: a "Two-axis navigation" subsection (session-nav keys move sessions;
  window-nav keys flip the previewed session's windows; both discovered from your
  config, overridable via `@livepicker-session-*-keys`/`-window-*-keys`); a
  "Window preview" note (confirm lands on the exact window; flipping never
  changes the candidate's own active window); reconcile the detached-candidate
  limitation with §23 (pinned, or snapshot-required for strict immutability).
- **CHANGELOG.md** — add an `[Unreleased]` entry for the changeset: two-axis
  discovered navigation, window-flip preview, confirm-lands-on-window, pane
  immutability (Invariant C). Note the defaults (axes discovered; preview-fit
  `clip`; preview-defer `on`), that none changes the pollution/restore invariants
  (A: no `client-session-changed` while browsing; B: no candidate mutation; C: no
  pane mutation; `clear_all_state` still tears down everything including the new
  window-cursor keys), and that `@livepicker-preview-mode snapshot` remains the
  strict-immutability escape hatch. Follow the existing entry format and the
  write-tech-docs style (no em dashes, no marketing tell-words).

---

## Open implementation notes (for the breakdown agent)

- **Discovery reads RAW list-keys, before the harmful filter.** The copy block
  runs `lp_filter_harmful_bindings`, which DROPS `switch-client`/`next-window`/
  `previous-window`/`select-window -n/-p`. Discovery MUST scan the unfiltered
  `list-keys -T root/prefix` or it will find nothing. Resolve the axis keys into
  locals at the top of T4, before the copy.
- **Discovery must exclude mouse keys + match the top-level command only.** The
  live root table has `MouseDown3Status`/`WheelUpStatus`/etc. whose lines contain
  `swap-window`/`next-window`/`switch-client -n` INSIDE `display-menu` blocks.
  Parse the key field + the command token immediately after it; drop keys
  matching `Mouse*`/`Wheel*`. Verified expected output for this user: window next
  `C-M-Tab M-n C-n C-l`, window prev `C-M-BTab M-p C-p C-h`, session next `) Down`,
  session prev `( Up`.
- **Window-cursor state overlaps `STATE_LINKED_ID`.** For non-self candidates the
  linked id == the previewed window id; for the self-session the linked id is
  empty but a window is still shown. Keep both: `STATE_LINKED_ID` is the
  unlink-handle contract restore/preview already rely on; `STATE_PREVIEW_WIN_ID`
  is "what is on screen" (needed for the self-session + snapshot modes). Do not
  collapse them without auditing restore/preview's linked-id reads.
- **Window-id addressing at confirm is load-bearing.** Verify whether
  `select-window -t "=$S:@id"` is accepted on 3.6b; if not, switch-client-then-
  select-window. Record the working form in the subtask.
- **`preview.sh` arg signature shift.** It currently takes `<session> [seq]`.
  Adding a chosen window means `<session> <window-id> [seq]` (or seq via env).
  Preserve the deferred-path seq supersede exactly — a flip is a re-link and a
  stale superseded flip must be a no-op (it must not clobber a newer link).
- **P3.M1.T1 gates P3.M2.T2.** The candidate-pin is conditional. If verification
  says pinning is infeasible/invasive, ship the snapshot escape as the documented
  contract and skip the pin code — do not force a broken pin. Delta-003's
  `clip_verification.md` §4 is the starting evidence (it already proved the
  residual exists).
- **`set -u`:** every new option read via `get_opt`/`opt_*` (defaults baked in);
  every new state read via `get_state` with a default. No bare `tmux show-option`
  that can crash under `set -u`.
