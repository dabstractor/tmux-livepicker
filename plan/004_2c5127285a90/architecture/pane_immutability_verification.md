# Pane-Immutability Verification — tmux 3.6b (candidate-window pinning, PRD §23 Invariant C)

> Verdict + evidence for PRD §23 "candidate windows linked in later must be
> protected (zero pane mutation of any session)." **Extends**
> `plan/003_77ef311abf10/architecture/clip_verification.md` §4 (which proved an
> UNPINNED linked candidate's window drops 40→22 AND disturbs its source view).
> **Refines** the reversibility finding of
> `plan/004_2c5127285a90/P3M1T1S1/research/candidate_pin_probe_findings.md` §ARM C2
> (a height-only restore is insufficient; BOTH width and height must be restored).
> **GATES P3.M2.T2** (conditional candidate-pin code); **informs P3.M2.T1**
> (drift-gated restore) and **P3.M3.T1** (the test assert shape + flip case).
>
> Evidence source: `plan/004_2c5127285a90/P3M1T1S1/research/pane_immutability_run1.log`
> (reproduced byte-identically in `pane_immutability_run2.log` — determinism
> verified, §1). Probe: `research/pane_immutability_probe.sh`.

## Decision box

| Question | Answer |
|---|---|
| Does candidate pinning hold Invariant C for a **DETACHED** candidate? | **YES — byte-identical.** (ARM B, layout `16ec`, deterministic across two runs) |
| Does it hold for a candidate **WITH its own attached client**? | **NO — and the pin is HARMFUL.** `window-size manual` reverts the candidate's client view to the creation size (22→40; ARM E3). |
| Does the **bare link** disturb a client-bearing candidate? | **NO** — with the driver manual, linking alone does not resize the candidate further (ARM E4, byte-identical). |
| Does flipping a candidate's windows resize the non-current one? | **NO** — distinct `@id` windows are independent shared objects (ARM D; clip_verification.md §4 no-per-nav-reflow). |
| Is the link-time mutation **reversible**? | **YES** — but only by restoring **BOTH** width and height: `resize-window -x W_orig -y H_orig` restores the exact layout byte-for-byte (ARM C). A height-only `resize-window -y H_orig` leaves the width at the disturbed value and the per-pane split differs. Equivalently: restore height THEN `select-layout`. |
| Verdict | **CONDITIONAL YES:** ship the pin for **detached** candidates, gated on `[ -z "$(tmux list-clients -t "=$S" 2>/dev/null)" ]`. **SKIP** the pin for client-bearing candidates (strict immutability there ⇒ `@livepicker-preview-mode snapshot`). |
| Real server untouched? | **YES** — session list byte-identical before/after the whole probe (PRD §15). |

**Bottom line:** Ship candidate pinning, but **CONDITIONAL on the candidate having
NO attached client**. At link time, if `tmux list-clients -t "=$cand"` is empty
(the common detached case — users browsing other sessions), set
`set-option -t "$cand" window-size manual` THEN
`resize-window -y "$H_cand" -t "$cand_wid"` BEFORE `link-window`, and restore the
candidate's prior `window-size` on unlink. If the candidate HAS an attached client,
**skip the pin** (it reverts their client view to the creation size, and the bare
link doesn't disturb them anyway — ARM E4). The global status-grow
(`set-option -g status`) still disturbs every client-bearing session by 1 row; that
is inherent to the global-status mechanism and is NOT fixed by candidate pinning —
strict §23 immutability for client-bearing candidates requires
`@livepicker-preview-mode snapshot`.

This is a **conditional YES** (not a flat NO): the invariant holds for the common
detached case, which is the dominant real-world scenario. Client-bearing candidates
are an edge case (multi-monitor / shared session) where pinning must be skipped and
`snapshot` remains the strict escape hatch.

---

## 1. Evidence matrix (5 arms) — verbatim `window_layout` + sorted `list-panes` + height

Each arm = a FRESH `setup_socket` (isolated `-L` socket) + `attach_test_client`
(driver) cycle. The candidate `alpha` carries a 3-pane window
(`split-window -h` + `split-window -v`). The driver is frozen FIRST in every arm
(per-session `window-size manual` + `resize-window -y H_drv`, then `status` grown
to 2 — clip_verification.md §3). Geometry is captured as `window_layout` (embeds
per-node dims + a 4-hex checksum → byte-identical == no mutation) AND sorted
`list-panes` per-pane geometry (the explicit §23 assertion). All values below are
verbatim from `research/pane_immutability_run1.log`.

### ARM A — CONTROL (no candidate pin; reproduce clip_verification.md §4)

Driver frozen, then alpha linked **UNPINNED**.

```
ALPHA source BEFORE link : h=40 lay=16ec,120x40,0,0{60x40,0,0,1,59x40,61,0[59x20,61,0,7,59x19,61,21,8]}
                         panes=%1:0,0,60,40|%7:61,0,59,20|%8:61,21,59,19
ALPHA source AFTER  link : h=22 lay=c33d,80x22,0,0{40x22,0,0,1,39x22,41,0[39x11,41,0,7,39x10,41,12,8]}
                         panes=%1:0,0,40,22|%7:41,0,39,11|%8:41,12,39,10
>> layout: DIFF   height: 40 -> 22  (DISTURBED)
```
**VERDICT A:** the unpinned candidate is dragged to the driver's usable size (22)
and its source view is mutated (120×40 → 80×22, checksum `16ec` → `c33d`). The
clip_verification.md §4 bug reproduces. ✓

### ARM B — PIN BEFORE LINK (the proposed fix), detached alpha — DECISIVE

```
ALPHA source BEFORE pin/link            : h=40 lay=16ec,120x40,...  panes=%1:0,0,60,40|%7:61,0,59,20|%8:61,21,59,19
ALPHA source AFTER  pin (manual+-y H)   : h=40 lay=16ec,120x40,...  (the pin itself did NOT change alpha)
ALPHA source AFTER  link                : h=40 lay=16ec,120x40,0,0{60x40,0,0,1,59x40,61,0[59x20,61,0,7,59x19,61,21,8]}
                                          panes=%1:0,0,60,40|%7:61,0,59,20|%8:61,21,59,19
>> layout: SAME/BYTE-IDENTICAL   panes: SAME/BYTE-IDENTICAL
```
**Determinism:** re-run on a fresh socket produced the identical `16ec,...` string
(run1 == run2, layout strings byte-identical across both — §"Determinism" below).
The decision rests on reproducible numbers.

**VERDICT B: candidate pinning HOLDS the invariant byte-identically for a detached
candidate.** The driver's manual+pin + alpha's manual+pin means NO session holding
the shared window exerts auto-resize pressure, so the window keeps its pinned size
(40) and its pane split is untouched. The driver CLIPS the oversized 40-row window
(renders top-left, hides overflow) — that is exactly the §22 clip, now extended to
the candidate.

### ARM C — PIN AFTER LINK (reversibility) — REFINES candidate_pin_probe_findings.md §C2

```
ALPHA source BEFORE link (unpinned)         : h=40 w=120 lay=16ec,120x40,...  panes=%1:0,0,60,40|%7:61,0,59,20|%8:61,21,59,19
ALPHA source AFTER  unpinned link (DISTURBED): h=22 w=80  lay=c33d,80x22,...   panes=%1:0,0,40,22|%7:41,0,39,11|%8:41,12,39,10
ALPHA source AFTER  pin-back -y 40 (height only): h=40 w=80 lay=7b79,80x40,0,0{40x40,0,0,1,39x40,41,0[39x20,41,0,7,39x19,41,21,8]}
                                              panes=%1:0,0,40,40|%7:41,0,39,20|%8:41,21,39,19
   >> height-only -y: layout DIFF  (width NOT restored: stays at the disturbed 80)
ALPHA source AFTER  pin-back -x 120 -y 40 (both dims): h=40 w=120 lay=16ec,120x40,0,0{60x40,0,0,1,59x40,61,0[59x20,61,0,7,59x19,61,21,8]}
                                                   panes=%1:0,0,60,40|%7:61,0,59,20|%8:61,21,59,19
   >> both-dim -x -y: layout SAME-restored/BYTE-IDENTICAL   panes: SAME-restored/BYTE-IDENTICAL
```
**VERDICT C: the link-time mutation IS reversible — but a height-only resize is
insufficient.** The link disturbs BOTH height (40→22) AND width (120→80).
`resize-window -y 40` restores the height but leaves the width at the disturbed
value (80), so the recomputed per-pane split (`7b79`, panes at width 40) differs
from the original (`16ec`, panes at width 60). Restoring **BOTH** dimensions with
`resize-window -x 120 -y 40` restores the EXACT original layout byte-for-byte
(`16ec`). Equivalently, `resize-window -y 40` followed by `select-layout` also
restores `16ec` (once the height is correct, select-layout re-derives the correct
full layout).

**This refines `candidate_pin_probe_findings.md` §ARM C2**, which reported
"`resize-window -y H_orig` restored the exact `16ec` layout." The difference: in
the C2 fixture the disturbed width happened to match what a height-only restore
needed; in this probe the link changed the width too, exposing that **height-only
is not a general restore**. The corrected, reliable recipe is: restore BOTH width
and height (`resize-window -x W_orig -y H_orig`), OR restore height then
`select-layout`. (See §3 for the implication for P3.M2.T1.)

### ARM D — FLIP (second distinct window of the same candidate)

Two distinct windows (`W1` 3-pane, `W2`) are created in alpha BEFORE the manual
state (gotcha #9), both pinned, then `W1` is linked + selected; `W2` is linked +
selected (the flip); then `W1` is re-selected. `W1`'s source geometry is compared
before vs after the flip.

```
W1 source BEFORE flip (linked, selected)         : h=40 lay=16ec,120x40,...  panes=%1:0,0,60,40|%7:61,0,59,20|%8:61,21,59,19
W1 source AFTER  flip (W2 linked+selected, back) : h=40 lay=16ec,120x40,...  panes=%1:0,0,60,40|%7:61,0,59,20|%8:61,21,59,19
>> flip layout: SAME/safe   panes: SAME/safe
```
**VERDICT D:** flipping a candidate's windows does NOT resize the non-current one.
Distinct `@id` windows are independent shared objects; a per-window pin
(`resize-window -y H -t @W1`) sets W1's size, and linking/selecting a different
window (`@W2`) cannot affect `@W1`'s geometry. This is the same independence
clip_verification.md §4 proved for navigating between two distinct candidate
sessions (no per-nav reflow). **Flip is SAFE under per-window candidate pinning.**

### ARM E — CANDIDATE WITH ITS OWN CLIENT (E3 pin=HARMFUL, E4 no-pin=CLEAN)

A second `script` pty is attached to `alpha` (so alpha has its OWN 80×24 client —
gotcha #8). The driver grows `status` globally (which itself disturbs alpha by 1
row), then alpha is linked.

**E3 (WITH candidate pin):**
```
ALPHA baseline (own client, after global status-2): h=22 lay=b17d,80x22,...  panes=%1:0,0,40,22|%7:41,0,39,10|%8:41,11,39,11
ALPHA AFTER candidate pin (manual + resize-window) : h=40 lay=15cc,120x40,... panes=%1:0,0,60,40|%7:61,0,59,19|%8:61,20,59,20  (REVERTED to creation size!)
>> pin changed alpha (vs post-grow)? YES/REVERTED  (22 -> 40)
```
**E4 (NO pin — control for the link effect):**
```
ALPHA (re-fitted) BEFORE link (no pin): h=22 lay=b17d,80x22,...
ALPHA AFTER bare link (no pin)         : h=22 lay=b17d,80x22,...   (BYTE-IDENTICAL)
>> link effect with NO pin: NO-change/CLEAN
```
**VERDICT E3/E4 (the critical edge case):**
1. `set-option -t alpha window-size manual` on a candidate that HAS its own client
   **REVERTS its window from the client-fitted size (80×22) to the creation/manual
   size (120×40)**, mutating the candidate's client view (height 22→40 AND a
   different pane split). The PRD §23 premise "a candidate's own attached clients
   should be unaffected by a manual pin" is **FALSE on 3.6b** — `manual` detaches
   the window from its client and reverts it. **So candidate-pinning must be
   SKIPPED for client-bearing candidates.**
2. The bare `link-window` does NOT further disturb a client-bearing candidate
   (E4: no-pin link = byte-identical), because the driver is manual (no downward
   pressure) and the candidate's own client keeps it fitted. **So skipping the pin
   there is SAFE.**
3. The GLOBAL status grow (`set-option -g status 2`) disturbs EVERY client-bearing
   session by 1 row (23→22) regardless of any pin. This is inherent to the global
   status mechanism (§22/§10), not the link, and candidate pinning cannot fix it.
   **Strict §23 immutability for client-bearing candidates ⇒
   `@livepicker-preview-mode snapshot`** (never links).

### Determinism (Level 1 gate)

`pane_immutability_run1.log` and `pane_immutability_run2.log` emit byte-identical
`window_layout` strings (every layout string appears an even number of times across
both runs; a direct `diff` of the sorted layout strings is empty). The decision
rests on reproducible numbers, not a single observation.

---

## 2. Mechanism: WHY does the unpinned candidate drop to 22, and WHY does the pin hold?

A linked window is ONE shared object with ONE size, influenced by every session it
is current in (PRD §23 root cause). `window-size` is a **per-SESSION** option
(`-t` isolates — confirmed in clip_verification.md §2) that governs whether that
session *auto-resizes the window to fit its client* (`largest`/`smallest`/`latest`/
`manual`). Under the default `latest`, the driver's attached client (usable 22 with
status 2) drags the shared window down to 22 for everyone — that is ARM A's 40→22.

`window-size manual` makes a session contribute **NO auto-resize pressure**. When
BOTH sessions holding the window (driver AND candidate) are `manual`, neither drags
the shared size; the window keeps whatever the last explicit `resize-window` set. So:

- **Unpinned candidate (A):** driver manual, candidate `latest`/detached-but-sized →
  the driver's client usable (22) wins → 40→22.
- **Pinned candidate (B):** driver manual + candidate manual → no pressure → window
  stays at the candidate's pinned height (40), clipped in the driver. Source view
  untouched. ✓
- **Client-bearing candidate pinned (E3):** candidate `manual` detaches the window
  from its client → the window reverts to its creation/manual size (120×40), which
  is NOT the client's fitted view → harmful. ✗

The pin works precisely because it removes the candidate's (and, with the driver
already manual, all) auto-resize pressure on the shared object. It fails for
client-bearing candidates because `manual` there means "ignore my client," reverting
the client's fitted view. (Reference: `plan/003_77ef311abf10/P3M1T1S1/research/tmux_window_size_docs.md`.)

---

## 3. Reversibility correction — informs P3.M2.T1 (drift-gated restore)

PRD §23 states the link-time mutation is permanent and "`select-layout` restore is
size-dependent and failed." ARM C shows that is true for a **bare** `select-layout`
and for a **height-only** `resize-window -y H_orig`, but NOT for a full
two-dimensional restore:

- `select-layout` re-derives a layout for the window's *current* size. If the
  current size is wrong (22, not 40), it cannot restore the original geometry.
  Confirmed unreliable as a sole restore.
- `resize-window -y H_orig` restores the **height** but NOT the **width**: the link
  disturbed both (120×40 → 80×22), and a height-only resize leaves the width at 80,
  so the per-pane split differs from the original (`7b79` ≠ `16ec`). Insufficient.
- `resize-window -x W_orig -y H_orig` restores **BOTH** dimensions; tmux then
  recomputes the deterministic pane split for that size, matching the original
  byte-for-byte (ARM C: `16ec` restored exactly). **Reliable.**
- Equivalently, `resize-window -y H_orig` followed by `select-layout` also restores
  `16ec` — once the height is right, `select-layout` re-derives the correct width
  and split.

**Implication (P3.M2.T1 drift-gated restore):** a reliable restore path is
**"capture both W_orig and H_orig before link; on drift, restore size FIRST via
`resize-window -x W_orig -y H_orig -t <win>` (or `resize-window -y H_orig` +
`select-layout`), then the layout follows deterministically"** — NOT a bare
`select-layout` and NOT a height-only resize. Combined with the candidate-pin
prevention, this gives belt-and-suspenders: prevent (pin) + repair (full-size
restore) both work for detached candidates. For client-bearing candidates, neither
is safe (they fight the client) → snapshot.

> **Correction note:** this refines `candidate_pin_probe_findings.md` §ARM C2 +
> §3, which reported "`resize-window -y H_orig` restores the exact layout." That
> held in the C2 fixture but is not general: a height-only restore leaves the width
> at the disturbed value. The general, reliable restore requires BOTH dimensions.
> `candidate_pin_probe_findings.md` is left UNMODIFIED as read-only research
> history; the refinement lives here.

---

## 4. Recipes (for P3.M2.T2)

### Recipe — candidate pin at link time (CONDITIONAL: detached candidates only)

```bash
# In preview.sh, when about to link candidate S's window src_id into the driver.
# current_session = @livepicker-orig-session (the driver). src_id = candidate's @id.
# GUARD: only pin candidates with NO attached client of their own.
if [ -z "$(tmux list-clients -t "=$S" 2>/dev/null)" ]; then
	# save the candidate's effective window-size for restore-on-unlink (P3.M2.T2).
	# @livepicker-<S>-orig-window-size = "$(tmux show-option -gv window-size)"
	tmux set-option -t "$S" window-size manual          # NO '=' prefix (gotcha #1)
	H_cand="$(tmux display-message -p -t "$src_id" '#{window_height}')"
	tmux resize-window -y "$H_cand" -t "$src_id"         # pin the candidate's CURRENT height
fi
tmux link-window -s "$src_id" -t "$current_session:"
tmux select-window -t "$current_session:$src_id"         # session-scoped (P2.M3.T1.S1)
```

### Recipe — candidate restore on unlink (P3.M2.T2)

```bash
# On unlinking the candidate (next nav / cancel / restore), restore its window-size.
if [ -n "${CAND_WAS_PINNED:-}" ]; then
	tmux set-option -t "$S" window-size "$ORIG_WS_CAND"   # back to latest/etc. (NO '=' prefix)
fi
# (The window's SIZE is left at the pinned value; with window-size restored to latest,
#  the candidate's own (re)attach re-fits it. For an EXPLICIT deterministic size-restore,
#  capture BOTH W_orig and H_orig pre-link and use resize-window -x W_orig -y H_orig — §3.)
```

### Recipe — drift-gated restore (for P3.M2.T1; detached candidates)

```bash
# Capture BOTH dims before link (height-only is insufficient — §3).
W_orig="$(tmux display-message -p -t "$src_id" '#{window_width}')"
H_orig="$(tmux display-message -p -t "$src_id" '#{window_height}')"
# ... link + browse; if pane drift is detected on the candidate source ...
tmux resize-window -x "$W_orig" -y "$H_orig" -t "$src_id"   # size-first: restores the exact layout
# (equivalently: resize-window -y "$H_orig" then select-layout)
```

### Assert shape (for P3.M3.T1 `test_pane_immutability.sh`, detached candidate)

```bash
# alpha = candidate with a 3-pane window; driver attached; status grown.
geom_before="$(tmux display-message -p -t "$alpha_wid" '#{window_layout}')"
panes_before="$(tmux list-panes -t "$alpha_wid" -F '#{pane_id}:#{pane_left},#{pane_top},#{pane_width},#{pane_height}' | sort)"
# ... pin candidate (manual + resize-window -y H), link, browse, flip, cancel ...
geom_after="$(tmux display-message -p -t "$alpha_wid" '#{window_layout}')"
panes_after="$(tmux list-panes -t "$alpha_wid" -F '#{pane_id}:#{pane_left},#{pane_top},#{pane_width},#{pane_height}' | sort)"
assert_eq "$geom_before"  "$geom_after"  'candidate window_layout byte-identical (Invariant C, detached)'
assert_eq "$panes_before" "$panes_after" 'candidate pane geometry byte-identical (Invariant C, detached)'
# NEGATIVE case: candidate WITH a client must NOT be pinned; assert the pin is skipped:
#   [ -z "$(tmux show-options -t "$S" -v window-size 2>/dev/null)" ]  (no manual override applied)
# Flip case (gotcha #9): create a SECOND distinct candidate window BEFORE the manual
# state, pin both, link W2, re-select W1, assert W1 byte-identical (§1 ARM D).
```

---

## 5. Residual + escape hatch

The candidate pin does NOT fix two disturbances:

1. **Client-bearing candidates.** `window-size manual` reverts their client view to
   the creation size (ARM E3 — harmful). The bare link doesn't disturb them (ARM E4),
   but the global status grow still does (1 row, inherent to the global-status
   mechanism). For these, **skip the pin** (gate on `list-clients`) and, for strict
   §23 immutability, use **`@livepicker-preview-mode snapshot`** (never links a live
   window → no shared-window disturbance at all).
2. **Global status grow.** `set-option -g status` (as the shipped activate does)
   disturbs every client-bearing session by 1 row. This is inherent to the
   global-status mechanism and is OUT OF SCOPE for candidate pinning to fix.

**Reconciliation with the README "Detached candidate windows are resized during
preview" limitation:** the conditional pin **REMOVES** this limitation for detached
candidates (ARM B — byte-identical, no resize). Client-bearing candidates still hit
it → `snapshot`. This is a strict improvement over the clip-only state
(clip_verification.md §4), where ALL linked candidates were resized at link time.

---

## 6. Gotchas (condensed — all tripped + verified on this box)

1. **Bare session name for `set-option`/`split-window`/`new-window`.**
   `set-option -t "=alpha" ...` → rc=1 ("no such window"); `split-window -t "=alpha"`
   → "can't find pane". Use the BARE name (`alpha`). The `=` prefix IS valid for
   `list-windows`/`display-message`/`link-window`/`select-window`, NOT for
   `set-option`/`split-window`/`new-window`.
2. **`attach_test_client`'s `script` pty reports 80×24, NOT the session's 120×40.**
   So an attached driver's usable height is 23 (status 1) / 22 (status 2); detached
   sessions keep 40. This size mismatch is WHY the shared-window resize reproduces.
   Measure `window_height` live; never hardcode.
3. **Address windows by `@id`, NEVER index** (base-index 1, `renumber-windows` on).
   Capture the active `@id` dynamically. When a var holds `@1`, write `-t "$WID"`,
   NOT `-t "@$WID"` (becomes `@@1`).
4. **`resize-window -y H` sets the SHARED window's size globally** (all linked
   sessions). H larger than the client = clip; H = current = pin (no reflow).
5. **`window_height`/`window_layout` need an attached client** to reflect the
   client-driven usable size; on a client-less socket they read the creation size.
   ALWAYS assert `list-clients` non-empty before measuring. `sleep 0.5` (attach) +
   `sleep 0.3` (after grow/link/pin) is sufficient.
6. **NEVER `set-option -g window-size`** (global manual disconnects from the client
   → jumps to creation size). Per-session `-t` only.
7. **`window_layout` embeds per-node dims + a 4-hex checksum** → CHANGES on
   reflow/resize. Byte-identical `window_layout` across an operation = strong
   no-mutation proof. ALSO capture sorted `list-panes` as the explicit §23 per-pane
   assertion.
8. **Second client for the candidate:** `attach_test_client` overwrites the single
   `TEST_CLIENT_PID`. Spawn a pty MANUALLY for the candidate's own client (ARM E):
   `script -qec "tmux attach -t 'alpha'" /dev/null >/dev/null 2>&1 & CAND_PID=$!; sleep 0.5`.
   Kill it yourself on teardown (`kill "$CAND_PID"; wait "$CAND_PID" 2>/dev/null`).
9. **Flip / second window:** create distinct candidate windows BEFORE the manual
   +link state (creating a second window AFTER can collide on an index in this
   fixture). Distinct `@id` windows are independent shared objects — flip is safe
   under per-window pinning (§1 ARM D).
10. **Reversibility needs BOTH W and H** (§3): a height-only `resize-window -y H_orig`
    leaves the width at the disturbed value; use `resize-window -x W_orig -y H_orig`
    (or height + `select-layout`).

---

## 7. GATES P3.M2.T2 + informs P3.M2.T1 + P3.M3.T1

**GATES P3.M2.T2 (candidate-window pinning at link time — CONDITIONAL on this doc):**
SHIP the conditional pin. Read §4 recipe + the `list-clients` guard. Apply the pin
ONLY for detached candidates (`if [ -z "$(tmux list-clients -t "=$S" 2>/dev/null)" ]`);
SKIP it (no code) for client-bearing candidates. Save the candidate's prior
`window-size` and restore it on unlink. For an explicit size restore, capture BOTH
`W_orig` and `H_orig` pre-link and use `resize-window -x W_orig -y H_orig`.

**Informs P3.M2.T1 (drift-gated restore):** when pane drift is detected on a
detached candidate, restore size FIRST via `resize-window -x W_orig -y H_orig -t
<win>` (or `resize-window -y H_orig` + `select-layout`), then the layout follows
deterministically. Do NOT use a bare `select-layout` (fails on the wrong size) and
do NOT use a height-only `resize-window -y` (leaves the width wrong). Neither is
safe for client-bearing candidates → snapshot.

**Informs P3.M3.T1 (`test_pane_immutability.sh`):** lock the conditional pin with
the assert shape in §4 (`window_layout` + sorted `list-panes` byte-identical, for a
detached 3-pane candidate across pin→link→browse→flip→cancel), the NEGATIVE case
(a client-bearing candidate is NOT pinned — assert no `manual` override applied),
and an EXPLICIT flip-with-distinct-windows case (§1 ARM D / gotcha #9).

---

## Summary table

| # | Claim | Status | Source |
|---|---|---|---|
| 1 | Unpinned linked candidate's source view is disturbed (40→22, layout changes) | **CONFIRMED** | §1 ARM A |
| 2 | Detached candidate pin (manual + resize-window -y H_cand before link) HOLDS Invariant C byte-identically | **CONFIRMED** | §1 ARM B |
| 3 | The pin is byte-identical across two independent runs (deterministic) | **CONFIRMED** | §1 Determinism |
| 4 | Link-time mutation is reversible via `resize-window -x W_orig -y H_orig` (BOTH dims) | **CONFIRMED** | §1 ARM C + §3 |
| 5 | A height-only `resize-window -y H_orig` does NOT fully restore (width stays disturbed) | **CONFIRMED (refines C2)** | §1 ARM C + §3 |
| 6 | Flipping a candidate's windows does not resize the non-current one | **CONFIRMED** | §1 ARM D |
| 7 | `window-size manual` on a client-bearing candidate REVERTS its client view (harmful) | **CONFIRMED** | §1 ARM E3 |
| 8 | The bare link does NOT disturb a client-bearing candidate | **CONFIRMED** | §1 ARM E4 |
| 9 | Global status grow disturbs every client-bearing session by 1 row (not fixed by pin) | **CONFIRMED** | §1 ARM E + §5 |
| 10 | Real tmux server byte-identical before/after the whole probe | **CONFIRMED** | Decision box + run logs |
| 11 | Ship candidate pinning CONDITIONALLY (detached only; `list-clients` guard) | **CONDITIONAL YES — SHIP** | §4 + §7 |
