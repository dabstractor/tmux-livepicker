# Candidate-Pinning Probe Findings — tmux 3.6b (PRD §23 pane immutability)

> Direct empirical verification on the installed **tmux 3.6b**, using the project's
> OWN harness (`tests/setup_socket.sh` `attach_test_client` `script`-pty idiom) on an
> isolated `-L` socket. This EXTENDS `plan/003_77ef311abf10/architecture/clip_verification.md`
> §4 (which proved an UNPINNED linked candidate's window drops 40→22 AND disturbs its
> source view). The question settled here: **does pinning the CANDIDATE's
> `window-size` + height at link time prevent that source disturbance?**
>
> Evidence source: `/tmp/cand_pin_probe.sh`, `cand_pin_probe2.sh`, `cand_pin_probe3.sh`,
> `cand_pin_probe_d4.sh` (ad-hoc probe scripts; re-run on demand against a fresh
> `setup_socket` cycle). All arms leave the user's real server byte-identical
> (`/usr/bin/tmux list-sessions` unchanged before/after — PRD §15).

## TL;DR / decision box

| Question | Answer |
|---|---|
| Does candidate-pinning hold the pane-immutability invariant for a **DETACHED** candidate (the common case)? | **YES — byte-identical.** (ARM B2) |
| Does candidate-pinning hold it for a candidate **WITH ITS OWN attached client**? | **NO — and the pin is actively HARMFUL.** Setting `window-size manual` on a client-bearing candidate REVERTS its window from client-fitted (80×22) to the creation/manual size (120×40), a bigger mutation than leaving it alone. (ARM E3) |
| Does the bare LINK itself disturb a candidate that has its own client? | **NO** — with the driver manual, linking does not resize the candidate further. (ARM E4) |
| Does flipping a candidate's windows resize the non-current one? | **NO** (by construction: distinct `@id` windows are independent shared objects; clip_verification.md §4 proved no per-nav reflow). See §4 caveat. |
| Is the link-time mutation reversible? | **YES via `resize-window -y H_orig`** (ARM C2) — restoring the original height restores the EXACT multi-pane layout. This *nuances* PRD §23's "permanent / select-layout failed" claim: that was about `select-layout`, not a size-pinning `resize-window`. |
| Real server untouched? | **YES** — session list byte-identical before/after every cycle. |

**BOTTOM LINE — GATE decision for P3.M2.T2:**

> **Ship candidate pinning, but CONDITIONAL on the candidate having NO attached client.**
> At link time, if `tmux list-clients -t "=$cand"` is empty (detached — the common
> case), do `set-option -t "$cand" window-size manual` THEN
> `resize-window -y "$H_cand" -t "$cand_wid"` BEFORE `link-window`, and restore the
> candidate's prior `window-size` on unlink. If the candidate HAS an attached client,
> **skip the pin** (it reverts their client view to the creation size; and the bare
> link doesn't disturb them anyway — ARM E4). The global status-grow (`set-option -g
> status`) still disturbs every client-bearing session by 1 row; that is inherent to
> the global-status mechanism and is NOT fixed by candidate pinning — strict §23
> immutability for client-bearing candidates requires `@livepicker-preview-mode snapshot`.

This is a **conditional YES** (not a flat NO): the invariant holds for the common
detached case, which is the dominant real-world scenario (users browse other detached
sessions). Client-bearing candidates are an edge case (multi-monitor / shared session)
where pinning must be skipped and `snapshot` remains the strict escape hatch.

---

## 1. The decisive matrix

Each arm = a FRESH `setup_socket` + `attach_test_client` (driver) cycle. The candidate
`alpha` gets a 3-pane window via `split-window -h` + `split-window -v`. Geometry is
captured as `window_layout` (embeds per-node dims + a 4-hex checksum → byte-identical
== no mutation) AND sorted `list-panes` per-pane geometry (the explicit §23 assertion).

### ARM A — CONTROL (no candidate pin; reproduce clip_verification.md §4)

Driver frozen first (manual + height pin, status grown to 2), then alpha linked
UNPINNED.

```
ALPHA-pre  : h=40 lay=aafe,120x40,0,0,1                      (single-pane control run)
ALPHA-post : h=22 lay=aa5e,80x22,0,0,1
>> alpha source disturbed: DIFF  (120x40 -> 80x22)
```
Confirms §4: an unpinned candidate is dragged to the driver's usable size (22) and
its source view is mutated. The bug reproduces. ✓

### ARM B2 — CANDIDATE PIN BEFORE LINK, multi-pane (THE proposed fix)

```
ALPHA-pre (3-pane)        : h=40 lay=16ec,120x40,0,0{60x40,0,0,1,59x40,61,0[59x20,61,0,7,59x19,61,21,8]}
                            panes=%1:0,0,60,40|%7:61,0,59,20|%8:61,21,59,19
ALPHA after driver grow   : h=40 lay=16ec,...  (driver grow alone did NOT touch detached alpha)
ALPHA after candidate pin : h=40 lay=16ec,...  (the pin itself did NOT change alpha)
ALPHA after link (source) : h=40 lay=16ec,120x40,0,0{60x40,0,0,1,59x40,61,0[59x20,61,0,7,59x19,61,21,8]}
                            panes=%1:0,0,60,40|%7:61,0,59,20|%8:61,21,59,19
>> layout: SAME   panes: SAME   (BYTE-IDENTICAL, including the 3-pane split)
```
**Determinism:** re-run on a fresh socket produced the identical `16ec,...` string
(B2-rerun = SAME). The decision rests on reproducible numbers.

**VERDICT B2: candidate pinning HOLDS the invariant byte-identically for a detached
candidate.** The driver's manual+pin + alpha's manual+pin means NO session holding the
shared window exerts auto-resize pressure, so the window keeps its pinned size (40) and
its pane split is untouched. The driver CLIPS the oversized 40-row window (renders
top-left, hides overflow) — that is exactly the §22 clip, now extended to the candidate.

### ARM C2 — pin AFTER link (reversibility test)

```
ALPHA-pre                 : h=40 lay=16ec,120x40,...  panes=%1|%7:61,0,59,20|%8:61,21,59,19
ALPHA after link(unpinned): h=22 lay=c33d,80x22,...   panes=%1:0,0,40,22|%7:41,0,39,11|%8:41,12,39,10  (DISTURBED)
ALPHA after pin-back -y 40: h=40 lay=16ec,120x40,...  panes=%1:0,0,60,40|%7:61,0,59,20|%8:61,21,59,19
>> reversibility layout: SAME-restored   panes: SAME-restored   (BYTE-IDENTICAL to pre)
```
**VERDICT C2: the link-time mutation IS reversible.** Pinning back to the original
height (`resize-window -y H_orig`) restored the EXACT multi-pane layout byte-for-byte.
This NUANCES PRD §23's "the mutation is permanent; select-layout restore is
size-dependent and failed": that finding was about `select-layout` (which re-derives a
layout for the *current* — wrong — size). `resize-window -y H_orig` instead restores
the *size* first and lets tmux recompute the deterministic split, which matches the
original. **Implication for P3.M2.T1 (drift-gated restore): a geometry-restore path
of "resize-window -y H_orig, then the layout follows" is reliable, not just
select-layout.** (Caveat: this restores cleanly when the candidate is detached; a
client-bearing candidate fights its client — see §3.)

### ARM E3/E4 — candidate WITH its own attached client (real multi-client)

A second `script` pty is attached to `alpha` (so alpha has its OWN 80×24 client). The
driver grows `status` globally, then alpha is linked.

**E3 (with candidate pin):**
```
ALPHA baseline (status 1)   : h=23 lay=0482,80x23,...   panes=%1:0,0,40,23|%7:41,0,39,11|%8:41,12,39,11
ALPHA after global status-2 : h=22 lay=b17d,80x22,...   panes=%1:0,0,40,22|%7:41,0,39,10|%8:41,11,39,11   (DISTURBED by the GLOBAL grow)
ALPHA after set manual+pin  : h=40 lay=15cc,120x40,...  panes=%1:0,0,60,40|%7:61,0,59,19|%8:61,20,59,20   (REVERTED to creation size!)
ALPHA after link            : h=40 lay=15cc,120x40,...  (link added NO further change)
>> global grow disturbed alpha-client? YES
>> pin changed alpha (vs post-grow)?   YES  (80x22 -> 120x40: the manual pin REVERTED the client view)
>> link changed alpha (vs post-pin)?   NO
```
**E4 (NO pin — control for the link effect):**
```
ALPHA after global grow     : h=22 lay=b17d,80x22,...
ALPHA after link (no pin)   : h=22 lay=b17d,80x22,...   (BYTE-IDENTICAL)
>> link effect with NO pin: NO-change
```
**VERDICT E3/E4 (the critical edge case):**
1. `set-option -t alpha window-size manual` on a candidate that HAS its own client
   **REVERTS its window from the client-fitted size (80×22) to the creation/manual
   size (120×40)**, mutating the candidate's client view (height 22→40 AND a different
   pane split). **The PRD §23 claim "a candidate's own attached clients should be
   unaffected by a manual pin" is FALSE on 3.6b** — `manual` detaches the window from
   its client and reverts it. So candidate-pinning must be SKIPPED for client-bearing
   candidates.
2. The bare `link-window` does NOT further disturb a client-bearing candidate (E4:
   no-pin link = byte-identical), because the driver is manual (no downward pressure)
   and the candidate's own client keeps it fitted. So skipping the pin there is SAFE.
3. The GLOBAL status grow (`set-option -g status 2`) disturbs EVERY client-bearing
   session by 1 row (23→22) regardless of any pin. This is inherent to the global
   status mechanism (§22/§10), not the link, and candidate pinning cannot fix it.
   Strict §23 immutability for client-bearing candidates ⇒ `@livepicker-preview-mode
   snapshot` (never links).

### ARM D — flip (second window of the candidate) — see §4 caveat

---

## 2. Mechanism: WHY does the unpinned candidate drop to 22, and WHY does the pin hold?

A linked window is ONE shared object with ONE size, influenced by every session it is
current in (PRD §23 root cause). `window-size` is per-SESSION and governs whether that
session *auto-resizes the window to fit its client* (`largest`/`smallest`/`latest`/
`manual`). Under the default `latest`, the driver's attached client (usable 22 with
status 2) drags the shared window down to 22 for everyone — that is ARM A's 40→22.

`window-size manual` makes a session contribute NO auto-resize pressure. When BOTH
sessions holding the window (driver AND candidate) are `manual`, neither drags the
shared size; the window keeps whatever the last explicit `resize-window` set. So:

- **Unpinned candidate (A):** driver manual, candidate `latest`/detached-but-sized →
  the driver's client usable (22) wins → 40→22.
- **Pinned candidate (B2):** driver manual + candidate manual → no pressure → window
  stays at the candidate's pinned height (40), clipped in the driver. Source view
  untouched. ✓
- **Client-bearing candidate pinned (E3):** candidate manual detaches the window from
  its client → the window reverts to its creation/manual size (120×40), which is NOT
  the client's view → harmful. ✗

The pin works precisely because it removes the candidate's (and, with the driver
already manual, all) auto-resize pressure on the shared object. It fails for
client-bearing candidates because `manual` there means "ignore my client," reverting
the client's fitted view.

---

## 3. Reversibility — corrects the "permanent" assumption for the resize-pin path

PRD §23 states the mutation is permanent and "`select-layout` restore is
size-dependent and failed." ARM C2 shows that is true ONLY for `select-layout`:

- `select-layout` re-derives a layout for the window's *current* size. If the current
  size is wrong (22, not 40), it cannot restore the original geometry. Confirmed
  unreliable.
- `resize-window -y H_orig` restores the *size* to the original (40); tmux then
  recomputes the deterministic pane split for that size, which matches the original
  byte-for-byte (C2: `16ec,...` restored exactly).

**Implication (P3.M2.T1 drift-gated restore):** a reliable restore path is
"if drift detected: `resize-window -y H_orig -t <win>` (size first), then the layout
follows deterministically" — NOT a bare `select-layout`. Combined with the
candidate-pin prevention, this gives belt-and-suspenders: prevent (pin) + repair
(resize-pin-back) both work for detached candidates. For client-bearing candidates,
neither is safe (they fight the client) → snapshot.

---

## 4. Flip (second window of the same candidate) — caveat

The §23 bullet "flipping a candidate's windows must never resize them" was targeted
but the in-probe reproduction hit a **harness window-creation quirk**: after the
candidate is set `manual` + linked, `new-window -t "alpha"` repeatedly failed with
`create window failed: index 3 in use` (base-index 1, renumber on; the failure is
specific to the post-manual/link state in this fixture, not a tmux rule — bare
`new-window -t alpha` on a clean socket works). Consequently a distinct second window
could not be cleanly created in-probe; the "DIFF" results in D2/D4 were the
split-window falling through onto W1 (adding a pane to W1), an artifact, not a
flip-induced resize.

**Reasoned conclusion (well-grounded, not a guess):** distinct candidate windows are
INDEPENDENT shared objects (different `@id`s). A per-window pin
(`resize-window -y H -t @W1`) sets W1's shared size; linking a different window
(`@W2`) cannot affect `@W1`'s geometry. `clip_verification.md` §4 already proved
**no per-nav reflow** when navigating between two distinct candidate windows
(alpha's `@1` vs beta's window stayed byte-identical across a 2nd-nav). The same
independence holds for two windows of one candidate. **Flip is SAFE under per-window
candidate pinning.** P3.M3.T1 (`test_pane_immutability.sh`) should add an explicit
flip-with-distinct-windows case to lock this directly (the real plugin creates W2
via `new-window`, not the manual-pty fixture).

---

## 5. CONFIRMED RECIPES (for P3.M2.T2 / P3.M3.T1)

### Recipe — candidate pin at link time (CONDITIONAL: detached candidates only)

```bash
# In preview.sh, when about to link candidate S's window src_id into the driver.
# current_session = @livepicker-orig-session (the driver). src_id = candidate's @id.
# GUARD: only pin candidates with NO attached client of their own.
if [ -z "$(tmux list-clients -t "=$S" 2>/dev/null)" ]; then
	# save the candidate's effective window-size for restore (P3.M2.T2)
	# @livepicker-<S>-orig-window-size = "$(tmux show-option -gv window-size)"  (or per-session -t S)
	tmux set-option -t "$S" window-size manual          # NO '=' prefix (gotcha #1)
	H_cand="$(tmux display-message -p -t "$src_id" '#{window_height}')"
	tmux resize-window -y "$H_cand" -t "$src_id"         # pin the candidate's CURRENT height
fi
tmux link-window -s "$src_id" -t "$current_session:"
tmux select-window -t "$current_session:$src_id"
```

### Recipe — candidate restore on unlink (P3.M2.T2)

```bash
# On unlinking the candidate (next nav / cancel / restore), restore its window-size.
if [ -n "${CAND_WAS_PINNED:-}" ]; then
	tmux set-option -t "$S" window-size "$ORIG_WS_CAND"   # back to latest/etc. (NO '=' prefix)
fi
# (The window's SIZE is left at the pinned value; with window-size restored to latest,
#  the candidate's own (re)attach will re-fit it. resize-window -y H_orig is available
#  as a deterministic restore if an explicit size-restore is wanted — see §3.)
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
```

---

## 6. Nondeterminism / timing / gotchas (condensed)

- **Determinism: GOOD.** B2 reproduced `16ec,...` byte-identically across two
  independent fresh-socket runs.
- **`window_height`/`window_layout` require an attached client** to reflect the
  client-driven usable size (else they read the creation size 40). Always assert
  `list-clients` non-empty before measuring; `sleep 0.5` (attach) + `sleep 0.3`
  (after grow/link/pin) is sufficient.
- **`split-window`/`new-window` target:** use the BARE session name (`alpha`), not
  `=alpha`. `split-window -t "=alpha"` → "can't find pane"; `new-window` post-manual
  with `=alpha` collided on an index. Bare `alpha` works.
- **Bare session name for `set-option -t`.** `set-option -t "=alpha" ...` → rc=1
  ("no such window"). Use `set-option -t alpha ...`. (`=` is fine for list-windows/
  display-message/link-window/select-window, NOT set-option.)
- **Address windows by `@id`, never index** (base-index 1, renumber on). Capture the
  active `@id` dynamically; when a var holds `@1`, write `-t "$WID"`, not `-t "@$WID"`.
- **Second client for the candidate:** spawn a pty manually
  (`script -qec "tmux attach -t alpha" /dev/null >/dev/null 2>&1 & CAND_PID=$!`),
  since `attach_test_client` overwrites the single `TEST_CLIENT_PID`. Kill it on
  teardown. Note `attach_test_client` itself sets the candidate's usable to 80×24.
- **NEVER `set-option -g window-size`** (global manual disconnects from the client →
  jumps to creation size). Per-session `-t` only.
- **Global status grow** (`set-option -g status`, as the shipped activate does)
  disturbs every client-bearing session by 1 row. This is inherent to the global
  status mechanism and is OUT OF SCOPE for candidate pinning to fix.

---

## 7. Recommendation summary (for `architecture/pane_immutability_verification.md`)

1. **GATE: conditional YES.** Ship candidate pinning for **detached** candidates
   (the common case) — it holds Invariant C byte-identically (ARM B2, deterministic).
   The §22 driver clip + the per-candidate pin together make live linking
   pane-immutable for detached candidates.
2. **Skip the pin for candidates WITH an attached client.** `window-size manual`
   reverts their client view to the creation size (ARM E3 — harmful). The bare link
   doesn't disturb them anyway (ARM E4), and the global status grow is the only
   (unavoidable, separate) disturbance. Gate the pin on
   `[ -z "$(tmux list-clients -t "=$S")" ]`.
3. **Strict immutability for client-bearing candidates ⇒ `@livepicker-preview-mode
   snapshot`** (never links a live window). This remains the documented escape hatch.
4. **Drift-gated restore (P3.M2.T1):** prefer `resize-window -y H_orig` (size-first,
   deterministic) over a bare `select-layout` (ARM C2 showed it restores the exact
   multi-pane layout; §23's "select-layout failed" is about select-layout, not this).
5. **P3.M2.T2 ships the conditional pin** (recipe §5); P3.M3.T1 locks it with the
   assert shape §5, including an explicit flip-with-distinct-windows case (§4 caveat).
