# Clip Freeze Recipe — research for P3.M1.T2.S1 (window-size save/freeze/restore + opt)

> Load-bearing context for the P3.M1.T2.S1 PRP. This is the SYNTHESIS of (a) the
> item-description CONTRACT, (b) the gating PRP P3.M1.T1.S1 + its research
> (`clip_probe_findings.md` / `tmux_window_size_docs.md` / `clip_verification.md`),
> and (c) the live codebase insertion points (read directly from `scripts/`).

## 1. THE CENTRAL RECONCILIATION — "manual only" FAILS; the pin is `resize-window -y H0`

The item description (CONTRACT §3 LOGIC) states the freeze as:

> then `tmux set-option -t "$ORIG_SESSION" window-size manual` BEFORE the
> status-grow case block.

**That recipe, taken literally, FAILS on tmux 3.6b.** The gating research
(`plan/003_77ef311abf10/P3M1T1S1/research/clip_probe_findings.md`, condition B)
proved `window-size manual` ALONE still reflowed the self-window 23→22 across the
status grow. The PROVEN, load-bearing mechanism is an explicit `resize-window -y
<pre-grow-height>` pin (conditions C and F: byte-identical layout, stable across a
2nd grow).

**Verified freeze recipe (clip_probe_findings.md §4 + the clip_verification.md
contract P3.M1.T1.S1 produces):**

```bash
# capture the driver's active window id + its pre-grow height BEFORE any status change
# (the driver's active window at activate == ORIG_WINDOW; nothing has switched yet)
tmux set-option -t "$ORIG_SESSION" window-size manual        # NO '=' prefix (gotcha #1)
tmux resize-window -y "$PRE_GROW_HEIGHT" -t "$ORIG_WINDOW"   # the LOAD-BEARING pin
# ... THEN grow status (the existing T3 case block) ...
```

**THE PRP MUST IMPLEMENT THIS (manual + resize-pin), not the contract's "manual
only".** This is exactly the "treat the previous PRP as a CONTRACT / build upon its
outputs" instruction: P3.M1.T1.S1's `clip_verification.md` GATES P3.M1.T2 and names
this recipe. PRD §22 "Mechanism (intended)" text is ALSO based on the old
"manual only" understanding and is superseded by `clip_verification.md` §3.

## 2. Why `manual` stays in the recipe (even though the pin does the work)

Per `clip_probe_findings.md` §5 (UNTESTED — client-resized robustness): under
`latest`/`largest`, a detach/reattach at a different size would reflow the window
and LOSE the `resize-window` pin. `manual` (per-session) makes tmux IGNORE client
size changes, so the pin survives a client-resized event. Keep `manual` for that
robustness; the `resize-window -y H0` is what kills the status-grow jank.

## 3. H0 (pre-grow height) — where it comes from, whether it persists

- **Source:** the driver's active window height BEFORE the status grow, via
  `tmux display-message -p -t "$ORIG_WINDOW" '#{window_height}'` (matches the
  research recipe exactly; the active window at activate == ORIG_WINDOW). Equivalent
  client-aware form: `lp_client_format '#{window_height}'`.
- **Does NOT need to persist across activate→restore.** Restore does NOT
  `resize-window` back; it only restores `window-size`, after which tmux re-fits the
  window to the client naturally (shrink status FIRST, then restore window-size —
  per item description: "panes return to natural size"). So H0 is a LOCAL at
  activate, used once for the pin, never stored in state. (The future
  `test_preview_clip.sh` P3.M2 captures its own H0 for the assert; it does not read
  a stored one.)

## 4. ORIG_WINDOW_SIZE — byte-exact restore decision

**Contract/research (empirical_findings.md Finding 1):** read the GLOBAL
`show-option -gv window-size` and restore via `set-option -t "$ORIG_SESSION"
window-size "$saved"`. This leaves a FUNCTIONALLY-INERT but NOT-byte-exact residue:
the driver gains an explicit session-scoped `window-size = latest` that was UNSET
before activate (it inherited global). The driver then no longer follows future
global `window-size` changes — a minor violation of PRD §15 "Cancelling leaves zero
trace".

**Production-correct refinement (RECOMMENDED in the PRP):** capture the
SESSION-SCOPED value (`show-options -t "$ORIG_SESSION" -v window-size` → empty when
unset, the common case), and on restore UNSET our override when it was empty
(`set-option -u -t "$ORIG_SESSION" window-size`) else replay the prior value. This
is byte-exact (empty→empty) and handles the rare session-override case the global
read misses. Same line count; strictly dominates. The contract's global-read is the
documented fallback if `set-option -u -t` proves problematic on a given tmux.

## 5. Exact insertion points (read directly from scripts/)

### activate — `scripts/livepicker.sh` activate_main, T3 block, step (c)
The freeze slots in BETWEEN step (b) install-renderer and step (c) status-grow,
GATED on `opt_preview_fit == clip`:

```bash
	# (b) install the picker renderer at the configured index (default 0).
	lp_idx="$(opt_status_format_index)"
	tmux set-option -g "status-format[$lp_idx]" "#($CURRENT_DIR/renderer.sh)"
	# (b.5) P3.M1.T2.S1 — FREEZE the driver's window-size (clip mode) BEFORE the grow.
	if [ "$(opt_preview_fit)" = "clip" ]; then
		...save ORIG_WINDOW_SIZE (session-scoped); capture H0; manual; resize-window -y H0...
	fi
	# (c) grow the status line count by one — NORMALIZED ...
	orig_status="$(get_state "$ORIG_STATUS" "on")"
	case "$orig_status" in ... esac
```

At this point: ORIG_SESSION + ORIG_WINDOW are already saved (STEP 2); the active
window is still ORIG_WINDOW (T2 list-build switches nothing; first preview is T5,
AFTER the grow). So `resize-window -y "$H0" -t "$ORIG_WINDOW"` targets the right
window.

### restore — `scripts/restore.sh` restore_main, STEP 4, after the status restore
GATED on `opt_preview_fit == clip` (mirror symmetry; reflow skips):

```bash
	r_status="$(get_state "$ORIG_STATUS" "on")"
	tmux set-option -g status "$r_status"
	# P3.M1.T2.S1 — restore the driver's window-size (clip mode mirror). AFTER the
	# status shrink so the panes return to natural size.
	if [ "$(opt_preview_fit)" = "clip" ]; then
		...restore-or-unset window-size on "$ORIG_SESSION"...
	fi
	# key-table / renumber-windows / hooks ... (rest of STEP 4)
```

`orig_session` is already read in STEP 3 (`orig_session="$(get_state "$ORIG_SESSION" "")"`)
so it is in scope for STEP 4. `opt_preview_fit` reads the live option (clear_all_state
PRESERVES §11 config, so it survives the picker lifetime within a restore call).

## 6. Gotchas (from clip_probe_findings.md §0 — all probed on 3.6b)

1. **The `=` exact-match prefix BREAKS `set-option -t` for session options.**
   `set-option -t "=driver" window-size manual` → rc=1. Use the BARE session name
   (`$ORIG_SESSION` holds a bare name — no `=`). `show-options -t` tolerates both;
   `set-option -t` does NOT.
2. **NEVER `set-option -g window-size`** (global). Global manual disconnected the
   window from the client (jumped to creation size 40). Per-session `-t` only.
3. **Address windows by `@id`, never index.** ORIG_WINDOW IS the `@N` id (saved via
   `lp_client_format '#{window_id}'`). `resize-window -y "$H0" -t "$ORIG_WINDOW"`
   (the var already holds `@3`); do NOT write `-t "@$ORIG_WINDOW"` (→ `@@3`).
4. **window_height requires an attached client.** Activate runs from a key press →
   a client is attached, so `display-message -p '#{window_height}'` returns the
   client-driven usable height (e.g. 23 with status on). On a client-less socket it
   reads the creation size — irrelevant at activate (always has a client).
5. **`resize-window` accepts a value LARGER than the client — that IS the clip.**
   `resize-window -y "$H0"` pins the CURRENT height; the status grow then cannot
   shrink it; tmux renders the top and clips the overflow row. Exactly the §22 fix.

## 7. reflow mode (the escape hatch)

When `opt_preview_fit == "reflow"`: SKIP the freeze entirely (no save, no manual,
no resize-pin) in activate AND skip the restore entirely. The status grow then
reflows the preview one row (the pre-§22 legacy behavior). The gate (`if [ clip ]`)
makes this automatic — no else branch needed.

## 8. Residual (linked candidate) — OUT OF SCOPE for this task

clip addresses the SELF-WINDOW status-grow reflow. A linked CANDIDATE window still
undergoes a one-time link-time resize to the driver's usable size (and the source
view is also affected — shared window). That is the documented "Detached candidate
resize" limitation (README / CHANGELOG bugfix-001), NOT fixed by clip. An OPTIONAL
`resize-window -y H` at link time (preview.sh) is future polish — NOT this task
(this task is activate-freeze + restore only). The README limitation note is
RECONCILED (distinguish status-grow reflow [fixed by clip] from link-time resize
[persists]) per item description §5.
