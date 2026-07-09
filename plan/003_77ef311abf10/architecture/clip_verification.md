# Clip Verification — tmux 3.6b (clip vs reflow default decision)

> Verdict + evidence for PRD §22 "clip instead of reflow". Supersedes
> `empirical_findings.md` Finding 2 for the freeze question. **GATES P3.M1.T2.**
>
> Evidence source: `plan/003_77ef311abf10/P3M1T1S1/research/clip_verify_run1.log`
> (reproduced byte-identically in `clip_verify_run2.log` — determinism verified,
> see §2). Probe: `research/clip_verify_probe.sh`.

## Decision box

| Question | Answer |
|---|---|
| Is `clip` feasible as the `@livepicker-preview-fit` default on 3.6b? | **YES.** Ship `clip`. |
| Freeze recipe that actually pins the self-window | `set-option -t "$ORIG_SESSION" window-size manual` THEN `resize-window -y "$PRE_GROW_HEIGHT" -t "$ACTIVE_WID"`, BEFORE the status grow |
| Does `window-size manual` ALONE pin? | **NO** — the window still reflowed 23→22 across the status grow |
| Does `resize-window -y <pre-grow-height>` pin? | **YES** — byte-identical `window_layout` across the grow (and across a second grow) |
| Is `manual` required alongside `resize-window`? | Not for the status-grow jank alone (resize pins on its own). Kept for client-resized robustness (reasoned; not directly measurable in this harness — see §5). |
| Linked-candidate residual | One-time **link-time resize** to the driver's usable size (22); **no per-nav reflow** once linked; the candidate's **source view is also resized** (shared window). This IS the already-documented limitation. |
| Real server untouched? | **YES** — session list byte-identical before/after the probe (PRD §15). |

**Bottom line:** Ship `clip` as the default `@livepicker-preview-fit`. The freeze
recipe must be `window-size manual` **followed by** `resize-window -y H0`, applied
to the driver's active (self/preview) window BEFORE the status grow. The
`resize-window` pin is what actually kills the status-grow jank; `manual` alone is
insufficient on 3.6b. The linked-candidate link-time resize + source disturbance
remain as the accepted residual (reconciled with README + bugfix-001, see §4).

## 1. Correction to empirical_findings.md Finding 2

`architecture/empirical_findings.md` Finding 2 / EXP-F claims "the self-session
window present at the status-grow moment is the one manual protects (it does not
dramatically reflow)." **That is too optimistic.** This verification (fresh runs
on the same 3.6b, same harness) reproduces the reflow explicitly: with
`window-size manual` set on the driver and NO `resize-window` pin, growing
`status` 1→2 still shrank the self-window 23→22 and changed `window_layout`. The
window "manual protects" is only protected if it was ALSO explicitly resized.

So for the **freeze question** (the P3.M1.T2 gate), this document **supersedes**
Finding 2. Finding 1 of the same file ("`resize-window -y 30` clips an oversized
non-shared window — CONFIRMED") stays accurate and in fact generalizes: a
`resize-window -y <pre-grow-height>` pin holds the window at its current (pre-grow)
height and clips overflow, which is exactly the no-reflow behavior clip needs.
`empirical_findings.md` is left UNMODIFIED as read-only research history; the
correction lives here.

## 2. Experiment (control vs treatment) — verbatim evidence

Both arms run on a FRESH isolated `-L` socket (the shipped harness
`tests/setup_socket.sh`) with an attached client (`attach_test_client`, whose
`script` pty reports 80×24 — see §5). The driver's active window is the multi-pane
`extra` window. `status` is then grown 1→2 and `window_height`/`window_layout` are
diffed before vs after.

### Control — no freeze (the jank is reproduced)

```
before grow : height=23 layout=4a2d,80x23,0,0{40x23,0,0[40x11,0,0,3,40x11,0,12,5],39x23,41,0,4}
after  grow : height=22 layout=851c,80x22,0,0{40x22,0,0[40x10,0,0,3,40x11,0,11,5],39x22,41,0,4}
CONTROL: REFLOW confirmed (height 23->22, layout changed) PASS
```

`height` drops 23→22 and the checksum flips `4a2d→851c` (the per-node dims shrink by
one row). This is the visible content shift the clip strategy exists to eliminate.

### Treatment — the clip recipe (no reflow)

```
before freeze/grow : height=23 layout=4a2d,80x23,0,0{40x23,0,0[40x11,0,0,3,40x11,0,12,5],39x23,41,0,4}
after  grow 1->2   : height=23 layout=4a2d,80x23,0,0{40x23,0,0[40x11,0,0,3,40x11,0,12,5],39x23,41,0,4}
after  grow 2->3   : height=23 layout=4a2d,80x23,0,0{40x23,0,0[40x11,0,0,3,40x11,0,12,5],39x23,41,0,4}
TREATMENT grow 1->2: CLIP confirmed (height 23==23, layout byte-identical) PASS
TREATMENT grow 2->3: pin survives second grow (height 23==23) PASS
```

`window_layout` is **byte-identical** to the pre-grow capture across the status
grow, and stays byte-identical across a SECOND grow (1→2→3). A byte-identical
`window_layout` (checksum + per-node dims unchanged) is a strong no-reflow proof:
our experiment changes nothing structural, so identical == no reflow == no resize.

### Determinism

`clip_verify_run1.log` and `clip_verify_run2.log` emit byte-identical
`window_layout` strings (grep'd out + `diff`'d → DETERMINISTIC). The decision rests
on reproducible numbers, not a single observation.

### Per-session isolation

```
isolation: driver=[manual] alpha=[] global=[latest]
```

`set-option -t driver window-size manual` set ONLY `driver`. `alpha` shows empty
(falls back to the global), and the global `window-size` is `latest` (untouched).
`-t` isolation is confirmed; the freeze never bleeds into other sessions or the
global default.

## 3. The corrected freeze recipe + restore recipe

```bash
# --- freeze (slot into activate IMMEDIATELY BEFORE the status grow, i.e. right
#     before the livepicker.sh T3(c) `set-option -g status 2` analog) ---
tmux set-option -t "$ORIG_SESSION" window-size manual        # NO '=' prefix (§5 gotcha)
tmux resize-window -y "$PRE_GROW_HEIGHT" -t "$ACTIVE_WID"    # the LOAD-BEARING pin
# ... grow status (on -> 2) ...

# --- restore (after the picker exits, status shrunk FIRST) ---
tmux set-option -g status "$ORIG_STATUS"
tmux set-option -t "$ORIG_SESSION" window-size "$ORIG_WINDOW_SIZE"   # NO '=' prefix
```

Capture contract for P3.M1.T2:

- `$ORIG_SESSION` — the session the client was in at activate (the driver).
- `$ACTIVE_WID` — the driver's active window `@id`, captured dynamically via
  `tmux list-windows -t "=driver" -F '#{window_id}' -f '#{window_active}'`. Never
  a hardcoded index.
- `$PRE_GROW_HEIGHT` — `tmux display-message -p -t "$ACTIVE_WID" '#{window_height}'`
  captured BEFORE any status change. (In this harness that is 23; do not hardcode
  it — the pty is 80×24 here but a real client may differ.)
- `$ORIG_STATUS` — the saved pre-activate `status` value (normalize via the
  activate T3(c) case on restore, mirroring activate).
- `$ORIG_WINDOW_SIZE` — the saved pre-activate effective value, read with
  `show-option -gv window-size` (the global effective default; assumes the driver
  uses the global default, as documented in `empirical_findings.md` Finding 1).

### Optional candidate clip-at-link-time (residual mitigation, NOT required)

```bash
# When preview.sh links a candidate, optionally pin it to the self-window height:
tmux link-window -s "=$CAND:" -t "$ORIG_SESSION:$idx"
tmux resize-window -y "$SELF_HEIGHT" -t "$linked_id"   # one-time; not per-keystroke
```

Empirically (§4) the linked candidate is otherwise stable at its link-time size
with no per-nav reflow, so this is optional polish, not required for jank-free
navigation.

## 4. Residual (linked candidate) — reconciled with README "Detached candidate..." + bugfix-001

With the self-window pinned and `status` already grown to 2, alpha (detached,
source size 40) is linked into the driver:

```
driver self-window pinned: height=23 layout=4a2d,80x23,...{...}
alpha source window: id=@1
alpha source BEFORE link: height=40 layout=f924,120x40,0,0{60x40,0,0,1,59x40,61,0,7}
linked alpha IN driver : height=22 layout=6004,80x22,0,0{40x22,0,0,1,39x22,41,0,7}
alpha source AFTER link: height=22 layout=6004,80x22,0,0{40x22,0,0,1,39x22,41,0,7}
alpha-linked AFTER 2nd nav: height=22 layout=6004,80x22,0,0{40x22,0,0,1,39x22,41,0,7}
CANDIDATE: NO per-nav reflow (layout byte-identical across 2nd nav) PASS
```

Findings:

- **One-time link-time resize.** The linked candidate undergoes a single resize at
  link time from its source size (40) down to the driver's current usable size
  (22). This is the residual — it does reflow once, at link time, then is stable.
- **No per-nav reflow.** Navigating to a second candidate (beta) and back leaves
  the alpha-linked window **byte-identical**. Once a candidate is linked, browsing
  among candidates does not reflow it further.
- **Source view is also resized (shared window).** Linking the candidate and the
  resize changed **alpha's OWN source view** to 22 (`window_layout` `6004` matches
  in both the driver view and the alpha source view). A linked window is a single
  shared object with one size; the resize applies to everyone. This is the
  tmux `window-size` shared-window behavior confirmed.

**Reconciliation.** This residual IS the already-documented limitation, not a new
defect:

- README "Known limitations / Detached candidate windows are resized during
  preview" states exactly this: a detached candidate linked into the attached
  driver is resized to the driver's dimensions and retains that size after exit.
  Clip does NOT remove this; the link-time resize + source disturbance ARE this
  limitation.
- CHANGELOG bugfix-001 "Detached candidate resize" names the same behavior.

Clip's primary goal — eliminating the **activation** status-grow jank for the
self-session preview — is achieved (§2 treatment). The linked-candidate link-time
resize remains as the documented, accepted cost of a live (linked) preview. Users
who need zero candidate disturbance set `@livepicker-preview-mode snapshot`
(uses `capture-pane`, never links).

## 5. Gotchas (condensed)

1. **Bare session name for `set-option -t`.** `set-option -t "=driver" window-size
   manual` → `no such window: =driver` (rc=1). The `=` exact-match prefix is valid
   for `list-windows`/`display-message`/`new-session`/`link-window`, but NOT for
   `set-option`. Use `set-option -t driver ...`.
2. **`attach_test_client`'s pty is 80×24, NOT 120×40.** `setup_socket` creates
   sessions at `-x 120 -y 40`, but the `script`-pty client reports the controlling
   pty (80×24). So the driver's usable height is 23 (status 1) / 22 (status 2);
   detached sessions keep 40 (which is why a linked candidate comes in tall and
   gets resized down). Measure `window_height` live; never hardcode it.
3. **Address windows by `@id`, never index.** After `setup_socket`, driver windows
   are at index 1 and 2; `=driver:0` → `can't find window: 0`. Capture the active
   `@id` dynamically. When a var holds `@3`, write `-t "$WID"`, NOT `-t "@$WID"`.
4. **`resize-window` accepts a value larger than the client — that IS the clip.**
   `resize-window -y 30` on a client-24 window makes it 30 and tmux renders the
   top, clipping overflow. `resize-window -y <current>` pins current, no reflow.
5. **`window_height`/`window_layout` require an attached client** to reflect the
   client-driven usable size. On a client-less socket they read the creation size
   (40). Always assert `list-clients` is non-empty before measuring; the harness's
   `sleep 0.5` (attach) + `sleep 0.3` (after grow/link) is sufficient settle time.
6. **NEVER `set-option -g window-size`.** Global `manual` disconnected the window
   from the client entirely and jumped it to 40 (the creation size). Per-session
   `-t "$ORIG_SESSION"` only.
7. **`window_layout` embeds per-node dims + a 4-hex checksum**, so it CHANGES on
   reflow. A byte-identical `window_layout` across the status grow is a strong
   no-reflow proof (our experiment changes nothing structural, so identical ==
   no reflow). It cannot distinguish a reflow from a structural change, but we do
   not need to here.
8. **`split-window -t` also wants the bare session name.** `split-window -t
   "=alpha"` resolves `=alpha` as a pane target → `can't find pane: =alpha`. Same
   shape as gotcha #1, different command. Likewise, `display-message` against a
   source session's window is addressed by its captured `@id`, not `=session`.
9. **Untested — `manual` vs `latest` under a real client resize.** The `script`
   pty's size is owned by `script`, so `refresh-client -C` could not simulate a
   resize in this harness. Reasoned recommendation: keep `manual` in the recipe —
   under `latest` a detach/reattach at a different size would reflow the window and
   lose the pin, whereas `manual` ignores client size changes. Flag for P3.M1.T2
   to confirm if a multi-client / detach scenario is in scope.

## 6. GATES P3.M1.T2

P3.M1.T2 implements the freeze recipe in §3. The freeze it codes is:

```
set-option  -t "$ORIG_SESSION"  window-size manual     # NO '=' prefix
resize-window -y "$PRE_GROW_HEIGHT" -t "$ACTIVE_WID"   # the load-bearing pin
```

applied to the driver's active (self/preview) window **immediately BEFORE** the
status grow (livepicker.sh activate T3(c) `set-option -g status 2` analog), with
restore in the inverse order (shrink status first, then restore `window-size`).

`@livepicker-preview-fit` default = **`clip`**.

Fallback ladder (escape hatches if the corrected recipe misbehaves on another
tmux/terminal — not needed on this 3.6b, which is clean and deterministic):

1. **`clip`** — the recipe above (DEFAULT).
2. **`reflow`** — no freeze; accept the status-grow content shift.
3. **`snapshot`** — `capture-pane` preview; never links the window (no residual at
   all; the README's `@livepicker-preview-mode snapshot` escape).

## Summary table

| # | Claim | Status | Source |
|---|---|---|---|
| 1 | `window-size manual` ALONE pins the self-window across a status grow on 3.6b | **REFUTED** (reflowed 23→22) | §2 control-equivalent (prior probe cond B) |
| 2 | `manual` + `resize-window -y <pre-grow-height>` pins (byte-identical layout) | **CONFIRMED** | §2 treatment |
| 3 | The `resize-window` pin survives a second status grow | **CONFIRMED** | §2 treatment (1→2→3) |
| 4 | `window-size` `-t` isolates per-session (driver=manual, alpha=empty, global=latest) | **CONFIRMED** | §2 isolation |
| 5 | Linked candidate: one-time link-time resize to driver usable; no per-nav reflow | **CONFIRMED** | §4 candidate |
| 6 | Linked candidate's source view is also resized (shared window) | **CONFIRMED** | §4 candidate |
| 7 | Real tmux server byte-identical before/after the probe | **CONFIRMED** | §Decision box + run logs |
| 8 | `clip` is feasible / shippable as the default `@livepicker-preview-fit` | **CONFIRMED — SHIP `clip`** | §Decision box |
