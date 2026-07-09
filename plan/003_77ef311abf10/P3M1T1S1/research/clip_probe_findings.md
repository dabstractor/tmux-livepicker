# Clip Probe Findings — tmux 3.6b (freeze-before-grow self-window + candidate-link residual)

> Direct empirical verification on the installed **tmux 3.6b**, using the project's
> OWN harness (`tests/setup_socket.sh` `attach_test_client` `script`-pty idiom).
> This CONFIRMS and **CORRECTS** `architecture/empirical_findings.md` Finding 2:
> `window-size manual` ALONE does **not** prevent the status-grow reflow on 3.6b.
> An explicit `resize-window -y <pre-grow-height>` pin is the load-bearing piece.

## TL;DR / decision box

| Question | Answer |
|---|---|
| Does `window-size manual` ALONE prevent the self-window status-grow reflow? | **NO.** Window still reflowed 23→22 (and global-manual jumped it to 40). |
| Does `resize-window -y <pre-grow-height>` prevent the reflow? | **YES — byte-identical layout, stable across a 2nd status grow.** |
| Is `manual` required alongside `resize-window`? | Not for the status-grow jank (resize-only works). Recommended for client-resized robustness (reasoned; not directly testable here). |
| **Is `clip` feasible / shippable as default?** | **YES — but via `manual + resize-window -y H0`, NOT `manual` alone.** |
| Linked candidate (post-grow) behavior? | One-time **link-time resize** to driver usable size (23→22); **no per-nav additional reflow**; source's own view also becomes 22 (shared window). |
| Real server untouched? | **YES** — byte-identical session list before/after every cycle. |

**BOTTOM LINE: Ship `clip` as the default `@livepicker-preview-fit`. The freeze
recipe must be `set-option -t "$ORIG_SESSION" window-size manual` (NO `=` prefix)
**followed by** `resize-window -y "$PRE_GROW_HEIGHT" -t "$active_window_id"`. The
`resize-window` pin is what actually kills the status-grow jank; `manual` alone is
insufficient on 3.6b. The residual (linked-candidate link-time resize + source
disturbance) is the already-documented bugfix-001 limitation.**

---

## 0. Critical gotchas discovered (must-read for the implementer)

These tripped the first probe passes and are load-bearing:

1. **The `=` exact-match prefix BREAKS `set-option -t` for session options.**
   `tmux set-option -t "=driver" window-size manual` → `no such window: =driver`
   (rc=1). `tmux set-option -t driver window-size manual` → rc=0, works. The `=`
   prefix IS valid for `list-windows -t`, `display-message -t`, `new-session -t`,
   `link-window -t`, but NOT for `set-option -t`. **Use bare session name for
   `set-option`.** (Confirmed in `/tmp/dbg1.sh`.)

2. **The `script`-pty client attaches at 80x24, NOT the session's 120x40.**
   `setup_socket` creates sessions at `-x 120 -y 40`, but the attached client
   (`attach_test_client` → `script -qec "tmux attach"`) reports the **controlling
   pty's size = 80x24**. So the driver's usable height is **23** (status `on` = 1
   line; 24−1) and **22** (status 2; 24−2). Detached sessions (alpha/beta) keep
   their creation size **40**. This is why the candidate comes in tall (40) and
   gets link-resized DOWN to 22. *(This matches empirical_findings.md's
   client_height=24 — that was never the 120x40; it's the pty.)*

3. **Driver windows are NOT at index 0.** After `setup_socket`, driver windows are
   at index **1** (`@0`, name "driver") and **2** (`@3`, "extra"). `=driver:0` →
   `can't find window: 0`. **Address windows by `@id` (e.g. `@3`) or by the active
   window**, never a hardcoded index. When using an id captured into a var, write
   `-t "$WID"` (the var already holds `@3`), NOT `-t "@$WID"` (→ `@@3`).

4. **`resize-window` needs the explicit `-t "@id"` and accepts a value LARGER than
   the client** — that is the clip. `resize-window -y 30` on a client-24 window
   makes it 30 and tmux renders the top, clipping the overflow (EXP A reproduction,
   CONFIRMED: layout `…,80x30,…`, height 30, client 24).

---

## 1. The decisive matrix — status-grow reflow (the core question)

Each row = a FRESH `setup_socket` + `attach_test_client` cycle; the self-window is
the driver's active 3-pane window (`@3`, "extra"); pre-grow height is always **23**
(status `on`, client 24). The status is then grown to `2`, and `window_layout` +
`window_height` are diffed before vs after.

| Cond | Freeze recipe applied BEFORE status grow | post-grow height | window_layout identical? | Verdict |
|------|------------------------------------------|------------------|-------------------------|---------|
| A | (none — control) | **22** | NO (`4a2d,…x23…` → `851c,…x22…`) | REFLOWED (the jank) |
| B | `set-option -t driver window-size manual` | **22** | NO | **REFLOWED — manual alone FAILS** |
| C | manual + `resize-window -y 23` | **23** | **YES** | **NO REFLOW ✓** |
| D | manual + `resize-window -y 30` (oversized) | 30 | NO (grew 23→30, clips) | oversized clip (EXP A) |
| E | `resize-window -y 30` (NO manual) | 30 | NO (grew to 30) | oversized clip w/o manual |
| F | `resize-window -y 23` (NO manual) | **23** | **YES** | **NO REFLOW ✓ (resize alone pins)** |
| G | `set-option -g window-size manual` (global, no resize) | **40** | NO (jumped to creation size 120x40) | REFLOWED — global manual FAILS differently |

Source: `/tmp/dbg4.sh` (A–E) + `/tmp/dbg5.sh` (F,G + second-grow). Reproduced
identically across two full runs.

**Verbatim layout strings (deterministic across runs):**

- Pre-grow (status on): `4a2d,80x23,0,0{40x23,0,0[40x11,0,0,3,40x11,0,12,5],39x23,41,0,4}`
- After NO-freeze / manual-only grow: `851c,80x22,0,0{40x22,0,0[40x10,0,0,3,40x11,0,11,5],39x22,41,0,4}` (the `80x23→80x22` is the visible 1-row reflow)
- After **manual + resize-pin** grow: `4a2d,80x23,…` (**byte-identical to pre-grow**)

### Second-grow robustness (status 2 → 3)

Conditions F and C2 were grown a second time (status → 3). The pinned window stayed
**byte-identical** at 23 in both (`>> second-grow: stable (PASS)`). So the
`resize-window` pin survives additional status changes — no per-grow drift.

### What this means (the correction to Finding 2)

`architecture/empirical_findings.md` Finding 2/EXP-F claimed "the self-session
window present at the status-grow moment is the one manual protects (it does not
dramatically reflow)." **That is too optimistic.** On 3.6b, `window-size manual`
(per-session B → 22, or global G → 40) does **not** pin the height against a status
grow. The window that "manual protects" is only protected if it was ALSO explicitly
resized (`resize-window`). The PROVEN mechanism is the **`resize-window` pin**;
`manual` contributes client-resized robustness but is NOT what stops the status jank.
Finding 1's "resize-window -y 30 clips" (EXP A) is the accurate half — and it
generalizes: `resize-window -y H0` pins the *current* (pre-grow) height and clips.

---

## 2. Per-session isolation (PRD §22 "Verification required" bullet 2)

```
tmux set-option -t driver window-size manual
tmux show-options -t alpha  -v window-size   =>   (empty)   # alpha falls back to global
tmux show-options -t driver -v window-size   =>   manual     # driver isolated
tmux show-options -g        -v window-size   =>   latest     # global untouched
```
`-t` isolation is CONFIRMED: setting driver to `manual` does not touch alpha or the
global `latest`. **BUT note the asymmetry:** per-session `manual` (B) left the
window following the client (→22); global `manual` (G) disconnected it from the
client entirely (→40). Neither pins the height by itself — only `resize-window`
does. Save/restore the per-session value with `set-option -t "$ORIG_SESSION"` (read
the effective value with `show-option -gv window-size`; assumes the driver uses the
global default, as documented in Finding 1).

---

## 3. Post-grow candidate link residual (task step 5)

Fresh cycle, self-window pinned via manual+resize (`-y 23`), status grown to 2.
Then alpha (multi-pane, source size 40) is linked into the driver:

```
alpha win id (source)            => @1
alpha height in alpha (pre-link) => 40
tmux link-window -s "alpha:" -t "driver:$NI"; select-window
linked alpha in DRIVER height    => 22   | layout 6004,80x22,0,0{40x22,0,0,1,39x22,41,0,7}
alpha height in alpha (post-link)=> 22   | layout 6004,80x22,…   # SOURCE ALSO became 22
```

Then a SECOND candidate (beta) is linked and the first (alpha-linked) is re-selected:

```
alpha-linked before  2nd-nav     => 6004,80x22,…{40x22,0,0,1,39x22,41,0,7}
alpha-linked after nav+back      => 6004,80x22,…{40x22,0,0,1,39x22,41,0,7}
>> NO per-nav additional reflow (PASS)
```

**Findings:**
- The linked candidate undergoes a **ONE-TIME link-time resize** from its source size
  (40) to the driver's current usable size (**22**). This is the residual — it does
  reflow once, at link time. Reproduced identically across two runs.
- There is **no per-nav additional reflow**: navigating to beta and back leaves the
  alpha-linked window byte-identical. So once a candidate is linked it is stable.
- The candidate is a **shared window**: linking it into the driver and the resize
  also changed **alpha's OWN source view** to 22 (`window_layout` 6004 matches in
  both). This is the §22 "single size is influenced by every session" subtlety,
  confirmed.
- The linked candidate does NOT clip to an oversized size — it comes in at the
  usable size (22), one row below the pinned self-window (23). To make a candidate
  clip at the self-window's 23, the implementation could optionally
  `resize-window -y 23 -t "<linked_id>"` at link time (PRD §22 "optional one-time
  resize-window -y H at link time") — a single resize, not per-keystroke.

Source: `/tmp/dbg6.sh` (two runs, identical).

---

## 4. CONFIRMED RECIPES (minimal command sequence for the implementer)

### Recipe — self-window freeze (THE clip mechanism, status-grow jank)

```bash
# After capturing the driver's active window id + its pre-grow height.
# H0 = display-message -p -t "<driver>:#{window_id}" ... then '#{window_height}'
#   captured BEFORE any status change.
tmux set-option -t "$ORIG_SESSION" window-size manual        # NO '=' prefix (gotcha #1)
tmux resize-window -y "$H0" -t "$ACTIVE_WINDOW_ID"           # the load-bearing PIN
# ... grow status to 2 ...
# assert: window_layout is byte-identical to pre-grow; window_height == H0
```

### Assert shape (for the future `tests/test_preview_clip.sh`, P3.M2)

```bash
H0="$(tmux display-message -p -t "$AW" '#{window_height}')"
L0="$(tmux display-message -p -t "$AW" '#{window_layout}')"
tmux set-option -t driver window-size manual
tmux resize-window -y "$H0" -t "$AW"
tmux set-option -g status 2; sleep 0.3
H1="$(tmux display-message -p -t "$AW" '#{window_height}')"
L1="$(tmux display-message -p -t "$AW" '#{window_layout}')"
assert_eq "$L0" "$L1"  'self-window layout unchanged across status grow (no reflow)'
assert_eq "$H0" "$H1"  'self-window height pinned (clip, not reflow)'
```

### Recipe — restore (section 9)

```bash
tmux set-option -g status "$ORIG_STATUS"          # shrink status back first
tmux set-option -t "$ORIG_SESSION" window-size "$ORIG_WINDOW_SIZE"   # NO '=' prefix
```
After restoring `window-size`, a `resize-window -y <client_usable>` (or letting the
client-resized trigger re-fit) returns the window to auto sizing. `ORIG_WINDOW_SIZE`
should be captured with `show-option -gv window-size` (global effective value).

### Recipe — optional candidate clip-at-link-time (residual mitigation)

```bash
# When preview.sh links a candidate, optionally pin it to the self-window's height:
tmux link-window -s "=$CAND:" -t "$ORIG_SESSION:$idx"
tmux resize-window -y "$SELF_HEIGHT" -t "$linked_id"   # one-time; not per-keystroke
```
(Empirically the linked candidate is otherwise stable at its link-time size with no
per-nav reflow — see §3 — so this is optional polish, not required for jank-free
navigation.)

---

## 5. Nondeterminism / surprises / untested

- **Determinism: GOOD.** All window_layout strings reproduced byte-identically
  across independent fresh-socket runs (matrix run twice; dbg6 run twice).
- **`attach_test_client` settle time:** the harness's `sleep 0.5` is sufficient; I
  used `sleep 0.3` after attach and `list-clients` always showed the client. A
  too-fast probe would see `list-clients` empty → no client → window-size behavior
  reverts to detached (windows stay at creation size 40). Always assert a client is
  attached before measuring.
- **`window_height`/`window_layout` require an attached client** to reflect the
  client-driven usable size; on a client-less socket they read the creation size.
  The clip experiment is only meaningful WITH `attach_test_client`.
- **UNTESTED — client-resized robustness of `manual` vs `latest`:** I attempted to
  simulate a client resize with `tmux refresh-client -C 80,20 -t "$client"`, but it
  did NOT change the `script`-pty client's reported size (client stayed 80x24) — the
  pty size is owned by `script`, not `refresh-client -C` in this harness. So I could
  not directly measure whether `manual` protects the `resize-window` pin against a
  real client-resized event. Reasoned recommendation: keep `manual` in the recipe —
  under `latest` a detach/reattach at a different size would reflow the window and
  lose the pin, whereas `manual` (per tmux's documented window-size semantics)
  ignores client size changes. **Flag for P3.M1.T2 to confirm if a multi-client /
  detach scenario is in scope.**
- **Global `manual` is dangerous (G → 40):** do NOT set `window-size` globally; use
  per-session `-t "$ORIG_SESSION"` only.

---

## 6. Recommendation (for `architecture/clip_verification.md`)

1. **CLIP IS FEASIBLE — ship `clip` as the default `@livepicker-preview-fit`.**
2. The freeze recipe must be **`manual + resize-window -y <pre-grow-height>`**, in
   that order, applied to the driver's active (self/preview) window BEFORE the status
   grow. `window-size manual` alone is **insufficient on 3.6b** (it still reflowed
   23→22). The `resize-window` pin is the load-bearing, proven step.
3. **Residual (documented, reconciles with bugfix-001):** linked candidate windows
   undergo a one-time link-time resize to the driver's usable size (one row below the
   pinned self-window), and the candidate's source view is also affected (shared
   window). There is **no per-nav additional reflow** once linked.
4. Keep `manual` in the recipe for client-resized robustness (reasoned; see §5).
5. The fallback ladders (`reflow`, then `snapshot`) remain valid escape hatches if
   the corrected recipe misbehaves on another tmux/terminal, but on this 3.6b it is
   clean and deterministic.
