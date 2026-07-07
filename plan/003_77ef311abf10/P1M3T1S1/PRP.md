# PRP — P1.M3.T1.S1: Capture client_width at activate + install/restore client-resized hook

> **Scope**: The viewport-width cache (PRD §10 step 5 / §3.35). At activate, capture the
> invoking client's width into `@livepicker-client-width` (so the §19 renderer measures
> the viewport with NO per-keystroke tmux round-trip — §18 budget) and install a
> `client-resized` hook that refreshes the cache on resize for the picker duration; save
> the prior hook and restore it byte-exactly on exit (mirroring `session-window-changed`,
> §P4). Adds a tiny `refresh-width` input action the hook calls. **3 script edits + 1
> input action + doc comments. No new files, no committed test** (P1.M4.T3.S1 owns the
> cache tests). All dependency inputs are LANDED (state keys, `lp_client_format`,
> `tmux_get_hook`/`tmux_clear_hook`).

---

## Goal

**Feature Goal**: After activate builds the session list and before it grows the status
bar, `livepicker.sh` captures `#{client_width}` (client-aware) into `STATE_CLIENT_WIDTH`
and installs a global `client-resized` hook → `input-handler.sh refresh-width` that
re-captures the width on any resize for the picker duration. `restore.sh` puts back the
user's exact prior `client-resized` hook (byte-identical — including the "user had no
hook" case). The renderer (which already reads `STATE_CLIENT_WIDTH`, defaulting to 0)
now gets a real width, activating the §19 viewport windowing + overflow indicators.

**Deliverable**: Edits to THREE files — **no new files, no committed test**.
1. `scripts/livepicker.sh`: insert a "client-width cache + resize hook" block between
   activate T2 (list build) and T3 (status grow): capture width, save prior hook, clear,
   install ours.
2. `scripts/input-handler.sh`: add a `refresh-width)` case branch (re-cache width +
   `refresh-client -S`); update the header action enum.
3. `scripts/restore.sh`: add the client-resized restore to STEP 4 (clear-first, then
   replay saved — the ONE difference from session-window-changed); update the STEP 4 header.

**Success Definition**:
- After activate, `@livepicker-client-width` holds the invoking client's width (e.g. 120;
  empty on the detached edge — renderer degrades to width=0 full-list, unchanged).
- `show-hooks -g` shows `client-resized[0] run-shell "<abs>/input-handler.sh refresh-width"`
  while the picker is active.
- After cancel/confirm, `show-hooks -g` is **byte-identical** to pre-activate (proven for
  BOTH the unset and the set prior-hook case — research §4).
- `@livepicker-client-width` + `@livepicker-orig-client-resized` are cleared on exit (both
  are in the auto-clear lists — state.sh:66 + the `@livepicker-orig-` grep).
- `tests/run.sh` stays 44/44 green (the byte-exact-restore test is the load-bearing gate).
- Resizing the client during the picker fires the hook → `refresh-width` re-caches the
  width → the renderer re-renders with the new viewport.

## User Persona (if applicable)

**Target User**: The end user browsing sessions on a resizable terminal. Also the
maintainer / QA.

**Use Case**: The user activates the picker, then resizes the tmux pane (or
detaches/reattaches). The picker's status-line viewport re-flows to the new width
(tabs re-window, overflow indicators update) without a per-keystroke `display-message`
round-trip slowing the render.

**Pain Points Addressed**: Before this task the renderer reads `STATE_CLIENT_WIDTH` but
no one writes it → width=0 → the §19 viewport/overflow logic is inert (every redraw
degrades to the full-list path). And without the `client-resized` hook, even a captured
width would go stale on resize. This task closes both gaps.

## Why

- **PRD §10 step 5 + §3.35 mandate it.** "Capture the invoking client's width into
  `@livepicker-client-width` via `tmux display-message -p '#{client_width}'` ... and
  install a `client-resized` hook that refreshes `@livepicker-client-width` for the
  duration of the picker. Save any prior `client-resized` hook and restore it on exit
  (mirror the `session-window-changed` save/restore)."
- **§18 performance contract.** The renderer is a `#()` command re-run on every redraw;
  it must be PURE+FAST (<50ms). Measuring the viewport against a CACHED width (one
  `get_state`) — never a per-keystroke `display-message` round-trip — is what keeps it
  in budget. The cache is only refreshed by the resize hook (rare), not by typing.
- **Exact-restoration invariant (PRD §9/§15).** Installing a global hook is pollution
  unless it is saved + restored byte-exactly. The session-window-changed save/restore
  (§P4) is the proven shape; client-resized mirrors it (with one clear-first difference
  at restore — research §3).
- **Activates already-wired renderer code.** renderer.sh:195 already reads
  `STATE_CLIENT_WIDTH`; P1.M2.T2.S1's viewport windowing + overflow indicators already
  consume it. This task is the missing PRODUCER — without it width is always 0 and the
  viewport logic never engages.
- **Cheap, surgical, low-risk.** 3 small edits + 1 trivial input action. Fully disjoint
  from the parallel P1.M2.T3.S1 (renderer.sh). The byte-identity is empirically proven.

## What

1. **`livepicker.sh` (T2→T3 insert)**: capture `STATE_CLIENT_WIDTH` via
   `lp_client_format '#{client_width}'`; save `tmux_get_hook client-resized` into
   `ORIG_CLIENT_RESIZED_HOOK`; `tmux_clear_hook client-resized`; install
   `tmux set-hook -g client-resized "run-shell '$CURRENT_DIR/input-handler.sh refresh-width'"`.
2. **`input-handler.sh`**: add `refresh-width)` → `set_state STATE_CLIENT_WIDTH
   "$(lp_client_format '#{client_width}')"` + `tmux refresh-client -S`; update line-13 enum.
3. **`restore.sh` STEP 4**: `tmux_clear_hook client-resized` FIRST (remove ours), then
   replay every saved `client-resized[N] <cmd>` line preserving index + verbatim cmd
   (skip bare/blank); NOT gated. Update the STEP 4 header enumeration.

### Success Criteria

- [ ] `grep -c 'STATE_CLIENT_WIDTH' scripts/livepicker.sh` → ≥1 (the capture).
- [ ] `grep -c 'client-resized' scripts/livepicker.sh` → ≥3 (save + clear + install).
- [ ] `grep -c 'refresh-width)' scripts/input-handler.sh` → 1 (the new action).
- [ ] `grep -c 'ORIG_CLIENT_RESIZED_HOOK' scripts/restore.sh` → ≥1 (the restore read).
- [ ] `grep -c 'tmux_clear_hook client-resized' scripts/restore.sh` → 1 (clear-first).
- [ ] After a cancel, `show-hooks -g` byte-identical to pre-activate (the L2 gate).
- [ ] `bash -n` + `shellcheck` clean on all 3 files; `tests/run.sh` 44/44 green.

## All Needed Context

### Context Completeness Check

_Pass_: an implementer who has never seen this repo can do it from (a) the verbatim
old→new blocks for all 3 files (anchored on unique content), (b) the §P4 hook pattern +
the ONE clear-first difference at restore (research §3), (c) the empirical byte-identity
proof (research §4 — the load-bearing gate), and (d) the verified dependency signatures.
All deps are confirmed landed; the consumer (renderer.sh) is already wired.

### Documentation & References

```yaml
# MUST READ — the empirical ground-truth for THIS task (insertion points + byte-identity proof)
- docfile: plan/003_77ef311abf10/P1M3T1S1/research/client_width_hook_findings.md
  why: §1 (all deps grep-confirmed landed); §2 (the EXACT insertion points in livepicker/input-handler/
       restore); §3 (the §P4 pattern + the ONE clear-first-at-restore difference — load-bearing);
       §4 (the byte-identity proof for BOTH unset+set prior-hook cases); §5 (why the suite stays green);
       §6 (the 4-edit design summary).
  critical: §3+§4 are load-bearing — without clear-first-at-restore, the client-resized hook LEAKS
       after exit when the user had no prior hook, and the byte-exact-restore test FAILS.

# MUST READ — the established hook save/restore pattern (the shape to mirror)
- docfile: plan/003_77ef311abf10/architecture/codebase_patterns.md
  why: §P4 (Hook save/restore — the ONLY correct way): tmux_get_hook verbatim -> tmux_clear_hook
       (-gu, every index) -> replay name[N] <cmd> via set-hook -g "name[$N]" "$cmd" preserving
       index + -b. §P1 (sourced-library / driver contract). §P3 (state contract: new keys must
       be in _STATE_RUNTIME_KEYS — STATE_CLIENT_WIDTH already is; ORIG_CLIENT_RESIZED_HOOK is
       caught by the @livepicker-orig- grep).
  section: "P4 — Hook save/restore", "P3 — State contract"

# MUST READ — the empirical tmux behavior (client-resized installs as [0]; #{client_width} resolves)
- docfile: plan/003_77ef311abf10/architecture/empirical_findings.md
  why: Finding 4 — display-message -p '#{client_width}' returns the width (use lp_client_format);
       client-resized installs via set-hook -g and shows as client-resized[0]; save/restore mirrors
       session-window-changed. (The byte-identity CYCLE is re-verified live in research §4.)
  section: "Finding 4"

# MUST READ — PRD §10 step 5 (the feature spec) + §9 (save/restore list) + §3.35 (width source)
- docfile: PRD.md
  why: §10 step 5 (capture width + install client-resized hook + save/restore prior hook); §9
       (restore step 4 must restore the client-resized hook); §3.35 Width source (the renderer
       measures against @livepicker-client-width, refreshed by the hook); §18 (no per-keystroke
       tmux round-trip — the cache is the mechanism); §16 "Width cache staleness" (hook must
       target the invoking client; restore must put back the exact prior hook).
  section: "§10 Status-line setup (step 5)", "§9 State saved and restored", "§19 §3.35 Width source"

# MUST READ — the file being edited (activate T2→T3 boundary)
- file: scripts/livepicker.sh
  why: activate_main's STEP 2 (save) at ~136, T2 (build list) ending at `set_state "$STATE_INDEX"
        "$idx"` (~214), T3 (status grow) starting at ~215. CURRENT_DIR (line 51) is the house path
        var. lp_client_format/tmux_get_hook/tmux_clear_hook/get_state/set_state all sourced.
  pattern: the session-window-changed hook save at STEP 2 (~158: `tmux set-option -g "$ORIG_HOOK"
           "$(tmux_get_hook session-window-changed)"`) is the save idiom to mirror; the run-shell
           key-binding form (double-quoted, single-quoted arg) is the install idiom.
  gotcha: capture AFTER T2 (window-mode token resolution needs the client) and BEFORE T3 (renderer
          installed + first render). Save MUST precede clear; clear MUST precede install.

# MUST READ — the file being edited (restore STEP 4 — the session-window-changed loop to mirror)
- file: scripts/restore.sh
  why: STEP 4 (~131) restores status/format/key-table/renumber/session-window-changed. The session-
        window-changed restore loop (~166-180, GATED on opt_suppress_window_hook) parses
        `session-window-changed[N] <cmd>`, extracts idx+cmd, replays via set-hook -g "[$idx]" "$cmd",
        skips bare/blank. The client-resized block goes RIGHT AFTER it (before STEP 5), mirroring it
        but NOT gated + CLEAR-FIRST.
  gotcha: session-window-changed restore does NOT clear (it never installed). client-resized restore
          MUST `tmux_clear_hook client-resized` FIRST (activate installed ours at [0]; without the
          clear, ours leaks when the user had no hook — research §3/§4).

# MUST READ — the file being edited (the case dispatch + the refresh-width action)
- file: scripts/input-handler.sh
  why: input_main (line 187) case dispatch: type/backspace/next-session/prev-session/confirm/cancel
        then a `*)` catch-all (~462) → return 0 → esac. Insert `refresh-width)` before `*)`.
        lp_client_format/set_state/STATE_CLIENT_WIDTH all sourced. The locals line (188) needs NO
        change (the branch inlines set_state/lp_client_format).
  gotcha: line 13 header comment enumerates the actions — add `refresh-width` to it.

# MUST READ — the helpers (signatures confirmed)
- file: scripts/utils.sh
  why: lp_client_format FMT (line 172) — resolves #{...} against the invoking client, falls back to
        context-free; tmux_get_hook NAME (74) = show-hooks -g "$1"; tmux_clear_hook NAME (185) =
        set-hook -gu "$1" (every index). All house style; use them, do NOT inline raw tmux.

# Reference — the consumer (already wired; this task FEEDS it)
- file: scripts/renderer.sh
  why: line 195 `width="$(get_state "$STATE_CLIENT_WIDTH" "0")"` — width=0 today (this task writes
        a real width); the §19 viewport windowing + overflow indicators (P1.M2.T2.S1) consume it.
  gotcha: the renderer is PURE — it only READS STATE_CLIENT_WIDTH (never display-message). This task
          is the ONLY writer (activate) + the hook's refresh-width action.
```

### Current Codebase tree

```bash
tmux-livepicker/
  scripts/
    livepicker.sh     # MODIFY: +client-width cache + client-resized hook (T2->T3 insert)
    input-handler.sh  # MODIFY: +refresh-width action (case, before *); +line-13 enum
    restore.sh        # MODIFY: +client-resized restore (STEP 4, after session-window-changed); +header
    utils.sh          # UNCHANGED (lp_client_format/tmux_get_hook/tmux_clear_hook — consumed)
    state.sh          # UNCHANGED (STATE_CLIENT_WIDTH/ORIG_CLIENT_RESIZED_HOOK + clear-lists — landed)
    renderer.sh       # UNCHANGED (the consumer; reads STATE_CLIENT_WIDTH — parallel P1.M2.T3 owns it)
    options.sh, layout.sh, rank.sh, preview.sh, plugin.tmux   # UNCHANGED
  tests/
    test_restore.sh   # UNCHANGED (test_restore_cancel_options_hooks_exact is the byte-identity gate)
    test_appearance.sh, test_functional.sh, ...   # UNCHANGED (stay green — research §5)
    test_layout.sh / scroll+client-width tests     # (do NOT exist yet — P1.M4.T1/T3)
    run.sh, setup_socket.sh, helpers.sh   # UNCHANGED
```

### Desired Codebase tree with files to be added and responsibility of file

```bash
scripts/livepicker.sh     # activate captures client_width + installs client-resized hook (save/clear/install)
scripts/input-handler.sh  # +refresh-width action: re-cache client_width on resize + redraw
scripts/restore.sh        # STEP 4 restores the exact prior client-resized hook (clear-first + replay)
```

### Known Gotchas of our codebase & Library Quirks

```bash
# CRITICAL (research §3/§4): restore for client-resized MUST `tmux_clear_hook client-resized` FIRST,
# THEN replay the saved lines. activate INSTALLS ours at [0]; without the clear, ours leaks after
# exit when the user had no prior hook (saved = bare "client-resized" -> replay skips -> ours stays).
# This is the ONE difference from session-window-changed (which never installs, so it never clears
# at restore). Empirically proven byte-identical for BOTH unset+set prior states (research §4).

# CRITICAL: save BEFORE clear BEFORE install (in that order). tmux_get_hook reads the LIVE state;
# if you clear before saving, you save your own clear (losing the user's hook). If you install
# before clearing, the user's [1+] hooks remain and would double-install on restore.

# CRITICAL: show-hooks -g ALWAYS lists client-resized (bare "client-resized" when unset, never
# absent). So the byte-exact test's before/after BOTH contain a client-resized line; the cycle
# must return it to the SAME form (bare<->bare, or [0]<->[0]). The clear-first+replay guarantees it.

# CRITICAL: client-resized restore is NOT gated (unlike session-window-changed, which is gated on
# opt_suppress_window_hook). The width cache is ALWAYS needed -> activate ALWAYS installs -> restore
# ALWAYS restores. Do NOT wrap the client-resized restore in the suppress-window-hook gate.

# CRITICAL: the install uses the run-shell key-binding form — double-quoted command, SINGLE-quoted
# arg: "run-shell '$CURRENT_DIR/input-handler.sh refresh-width'". This bakes $CURRENT_DIR to an
# ABSOLUTE path at set-time (the server's cwd is NOT the plugin dir) and survives session names
# with spaces (not that refresh-width takes one). Verified it installs as client-resized[0].

# CRITICAL (PRD §16 "Width cache staleness"): the hook targets the invoking client via
# lp_client_format (client-aware). Single-client plugin (PRD §2); multi-client width mismatch is
# out of scope. On the detached/test edge lp_client_format falls back to context-free (empty width
# -> renderer degrades to width=0 full-list — safe).

# GOTCHA: capture client_width AFTER T2 (the list build) and BEFORE T3 (status grow / renderer
# install). T2's window-mode token resolution uses lp_client_format (needs the client); the capture
# must precede the first render so the renderer sees a real width.

# GOTCHA: the refresh-width action does NO preview work and NO filter/index change — it only
# re-caches width + refresh-client -S. It is called by the hook (run-shell), NOT by the user.
# Do NOT route it through _lp_preview_follow.

# GOTCHA: STATE_CLIENT_WIDTH + ORIG_CLIENT_RESIZED_HOOK are BOTH already in the auto-clear lists
# (state.sh:66 _STATE_RUNTIME_KEYS for the former; the @livepicker-orig- grep for the latter).
# Do NOT add them again; do NOT clear them manually in restore (clear_all_state at STEP 6 does it).

# GOTCHA: the session-window-changed restore loop is the template — COPY its shape (the case skip,
# the sed idx extract, the ${line#name[*] } cmd extract, the [ -z "$idx" ] && continue, the
# set-hook -g "name[$idx]" "$cmd" 2>/dev/null || true). Only the hook NAME changes (client-resized)
# + the leading clear + no gate.

# STYLE: TABS throughout (shfmt absent). livepicker activate body is 1-tab inside activate_main;
# the new block at 1 tab. input-handler case branches at 2 tabs. restore STEP 4 body at 1 tab;
# the while loop body at 2 tabs. SC1091 file-wide disabled on all three files (sourced libs).
```

## Implementation Blueprint

### Data models and structure

No data model. The "structure" is the save/clear/install ↔ clear/replay symmetry around the
`client-resized` hook, with `STATE_CLIENT_WIDTH` as the cached width the renderer reads:

```
ACTIVATE (livepicker.sh, T2->T3):
  set_state STATE_CLIENT_WIDTH (lp_client_format '#{client_width}')   # cache the viewport width
  set ORIG_CLIENT_RESIZED_HOOK (tmux_get_hook client-resized)         # save prior (verbatim)
  tmux_clear_hook client-resized                                      # clear every index
  set-hook -g client-resized "run-shell '<abs>/input-handler.sh refresh-width'"  # install ours

RESIZE (during picker): client-resized[0] fires -> input-handler.sh refresh-width:
  set_state STATE_CLIENT_WIDTH (lp_client_format '#{client_width}')   # re-cache
  refresh-client -S                                                   # redraw with new viewport

RESTORE (restore.sh STEP 4):
  tmux_clear_hook client-resized                                      # remove ours (CLEAR FIRST)
  replay saved client-resized[N] <cmd> lines (skip bare/blank)        # restore user's exact prior
```

### Implementation Tasks (ordered by dependencies)

```yaml
Task 1: MODIFY scripts/livepicker.sh — insert the client-width cache + resize hook (T2->T3)
  - LOCATE the boundary: T2 ends at `set_state "$STATE_INDEX" "$idx"`; T3 starts at the
    `# --- T3 (P1.M4.T3.S1): grow status bar + install renderer ---` comment.
  - INSERT (between them) the verbatim block from "Implementation Patterns" (Task 1):
    capture STATE_CLIENT_WIDTH; save ORIG_CLIENT_RESIZED_HOOK; clear; install ours.
  - ORDER: capture (anywhere) -> save -> clear -> install (save before clear before install).
  - PRESERVE: STEP 2, T2, T3, and every other step untouched.

Task 2: MODIFY scripts/input-handler.sh — add the refresh-width action + update the enum
  - LOCATE the case dispatch's `*)` catch-all (the last branch before `esac`).
  - INSERT `refresh-width)` immediately before `*)` (verbatim in Patterns, Task 2): re-cache
    STATE_CLIENT_WIDTH via lp_client_format + refresh-client -S.
  - UPDATE the line-13 header comment to append `| refresh-width` to the action enum.
  - NO change to the locals line (the branch inlines set_state/lp_client_format).

Task 3: MODIFY scripts/restore.sh — add the client-resized restore to STEP 4 + update header
  - LOCATE STEP 4's session-window-changed block end (its `fi` + the `# When
    @livepicker-suppress-window-hook is "off"...` comment), before `# --- STEP 5`.
  - INSERT the client-resized restore block (verbatim in Patterns, Task 3): CLEAR FIRST
    (tmux_clear_hook client-resized), then replay saved client-resized[N] <cmd> lines
    (mirror the session-window-changed loop; skip bare/blank; NOT gated).
  - UPDATE the STEP 4 header (line 131-132) to add "client-resized hook" to the enumeration.

Task 4: VALIDATE (syntax + lint + byte-identity + full suite + throwaway smoke)
  - RUN: bash -n scripts/livepicker.sh scripts/input-handler.sh scripts/restore.sh; shellcheck all 3.
  - RUN: the L1 grep cross-checks (capture/clear/install/refresh-width/clear-first present).
  - RUN: tests/run.sh (expect 44/44 green — the byte-exact-restore test is the gate).
  - RUN: the throwaway client-width smoke (capture on activate; hook fires on resize; byte-identity
    after cancel); then DELETE it. (Committed cache tests are P1.M4.T3.S1.)
```

### Implementation Patterns & Key Details

> All anchors are CONTENT-based (line numbers drift). Indent is TABS. The three files all
> carry `# shellcheck disable=SC1091` (sourced libs) — no new disable needed.

**Task 1 — livepicker.sh: insert the client-width cache + resize hook between T2 and T3.**
CURRENT (the T2 tail → T3 head boundary):

```bash
	set_state "$STATE_LIST" "$list"
	set_state "$STATE_FILTER" ""
	set_state "$STATE_INDEX" "$idx"
	# --- T3 (P1.M4.T3.S1): grow status bar + install renderer ---
```
→ REPLACE WITH (the new block inserted between `set_state "$STATE_INDEX"` and the T3 comment):

```bash
	set_state "$STATE_LIST" "$list"
	set_state "$STATE_FILTER" ""
	set_state "$STATE_INDEX" "$idx"
	# --- T2b (P1.M3.T1.S1): client-width cache + client-resized hook (PRD §10 step 5 / §3.35).
	# Capture the invoking client's width into @livepicker-client-width so the §19 renderer
	# measures the viewport with NO per-keystroke tmux round-trip (§18 budget; width=0 ->
	# degraded full-list render). Done AFTER T2 (window-mode token resolution needs the
	# client) and BEFORE T3 (the renderer is installed + first-rendered here). CLIENT-AWARE
	# via lp_client_format (H1 fix; falls back to context-free on the detached/test edge).
	# Then save the prior client-resized hook (tmux_get_hook, verbatim incl. -b / multi-index),
	# clear every index, and install ours -> input-handler.sh refresh-width, which re-caches
	# the width on resize. restore.sh STEP 4 clears ours + replays the saved lines (the
	# IDENTICAL shape as session-window-changed, §P4; the save MUST precede the clear).
	set_state "$STATE_CLIENT_WIDTH" "$(lp_client_format '#{client_width}')"
	tmux set-option -g "$ORIG_CLIENT_RESIZED_HOOK" "$(tmux_get_hook client-resized)"
	tmux_clear_hook client-resized
	# Absolute path (server cwd != plugin dir); single-quote the arg inside the double-quoted
	# run-shell (matches the key-binding form, livepicker.sh bind-key lines). Installs as
	# client-resized[0]; show-hooks -g always lists client-resized (bare when unset).
	tmux set-hook -g client-resized "run-shell '$CURRENT_DIR/input-handler.sh refresh-width'"
	# --- T3 (P1.M4.T3.S1): grow status bar + install renderer ---
```

**Task 2 — input-handler.sh: add the `refresh-width` action + update the enum.**

Edit 2a — the header comment (line 13). CURRENT:

```bash
#   argv[1] = action (type | backspace | next-session | prev-session | confirm | cancel)
```
→ REPLACE WITH:

```bash
#   argv[1] = action (type | backspace | next-session | prev-session | confirm | cancel | refresh-width)
```

Edit 2b — the case branch. CURRENT (the `*)` catch-all at the end of the case):

```bash
		*)
			# Unknown action — defensive no-op (never crash the picker).
			return 0
			;;
	esac
```
→ REPLACE WITH (insert `refresh-width)` before `*)`):

```bash
		refresh-width)
			# PRD §10 step 5 / §3.35: the client-resized hook fires this on resize. Re-cache the
			# invoking client's width (client-aware via lp_client_format) and force a status redraw
			# so the §19 renderer re-windows the viewport for the new width. NO preview work, NO
			# filter/index change (the hook is global; single-client plugin — PRD §2).
			set_state "$STATE_CLIENT_WIDTH" "$(lp_client_format '#{client_width}')"
			tmux refresh-client -S 2>/dev/null || true
			return 0
			;;
		*)
			# Unknown action — defensive no-op (never crash the picker).
			return 0
			;;
	esac
```

**Task 3 — restore.sh: add the client-resized restore to STEP 4 + update the header.**

Edit 3a — the STEP 4 header (line 131-132). CURRENT:

```bash
	# --- STEP 4 (PRD §9 restore step 4): restore status / status-format /
	#     key-table / renumber-windows / session-window-changed hook ---
```
→ REPLACE WITH:

```bash
	# --- STEP 4 (PRD §9 restore step 4): restore status / status-format /
	#     key-table / renumber-windows / session-window-changed + client-resized hooks ---
```

Edit 3b — the client-resized restore block. CURRENT (the tail of the session-window-changed
block → the STEP 5 header):

```bash
	# When @livepicker-suppress-window-hook is "off": activate did NOT clear the
	# hook, so the live hook is still the user's original -> restore does nothing
	# here (the if skips). Symmetric with activate T4.S2.

	# --- STEP 5 (PRD §9 restore step 5): restore the original pane layout ---
```
→ REPLACE WITH (insert the client-resized restore between the comment and STEP 5):

```bash
	# When @livepicker-suppress-window-hook is "off": activate did NOT clear the
	# hook, so the live hook is still the user's original -> restore does nothing
	# here (the if skips). Symmetric with activate T4.S2.
	# client-resized hook (PRD §9 / §10 step 5 §3.35): the IDENTICAL shape as
	#   session-window-changed above (§P4), with ONE difference — activate
	#   INSTALLED ours at [0] (it didn't just suppress), so CLEAR ours FIRST;
	#   then replay every saved client-resized[N] <cmd> line preserving index +
	#   verbatim command. If nothing was saved (bare "client-resized" line, the
	#   common unset case), the loop skips -> the hook stays cleared (== the
	#   user's prior unset state) -> byte-identical to pre-activate. NOT gated
	#   (the width cache is always installed, unlike the opt-in window-hook
	#   suppression). Empirically proven byte-identical for unset + set priors.
	tmux_clear_hook client-resized
	r_cr_hook="$(get_state "$ORIG_CLIENT_RESIZED_HOOK" "")"
	while IFS= read -r cr_line; do
		case "$cr_line" in
			"client-resized"|"") continue ;;   # bare name / blank -> skip
		esac
		cr_idx="$(printf '%s\n' "$cr_line" | sed -n 's/^client-resized\[\([0-9]\+\)\].*/\1/p')"
		cr_cmd="${cr_line#client-resized\[*\] }"
		[ -z "$cr_idx" ] && continue
		tmux set-hook -g "client-resized[$cr_idx]" "$cr_cmd" 2>/dev/null || true
	done <<< "$r_cr_hook"

	# --- STEP 5 (PRD §9 restore step 5): restore the original pane layout ---
```

**Verification after all edits (copy-paste):**

```bash
cd /home/dustin/.config/tmux/plugins/tmux-livepicker
grep -c 'STATE_CLIENT_WIDTH' scripts/livepicker.sh            # -> >=1 (capture)
grep -c 'ORIG_CLIENT_RESIZED_HOOK' scripts/livepicker.sh      # -> >=1 (save)
grep -c 'tmux_clear_hook client-resized' scripts/livepicker.sh # -> 1 (clear before install)
grep -c "set-hook -g client-resized" scripts/livepicker.sh    # -> 1 (install)
grep -c 'refresh-width)' scripts/input-handler.sh             # -> 1 (the action)
grep -c 'tmux_clear_hook client-resized' scripts/restore.sh    # -> 1 (clear-first at restore)
grep -c 'ORIG_CLIENT_RESIZED_HOOK' scripts/restore.sh          # -> >=1 (replay read)
grep -c 'client-resized' scripts/restore.sh                    # -> >=3 (clear + case + set-hook)
```

### Integration Points

```yaml
CODE:
  - file: scripts/livepicker.sh
    change: "+client-width capture (STATE_CLIENT_WIDTH) + client-resized hook save/clear/install (T2->T3)"
    invariant: "width captured client-awarely; hook installed as client-resized[0] -> refresh-width; \
               prior hook saved verbatim before clear"
  - file: scripts/input-handler.sh
    change: "+refresh-width action (re-cache width + refresh-client -S); line-13 enum"
    invariant: "refresh-width does NO preview/filter/index work; only re-caches width + redraws"
  - file: scripts/restore.sh
    change: "+client-resized restore in STEP 4 (clear-first + replay); STEP-4 header enum"
    invariant: "show-hooks byte-identical pre/post activate (unset: bare<->bare; set: [0]<->[0]); \
               NOT gated (always restored)"

CONSUMERS / PRODUCERS:
  - renderer.sh (P1.M2.*, landed): READS STATE_CLIENT_WIDTH (line 195) — THIS task is the producer;
    width=0 today -> full-list; a real width activates the §19 viewport/indicators.
  - P1.M3.T2.S1 (scroll-into-view): will also consume STATE_CLIENT_WIDTH via layout.sh's lp_viewport.
  - P1.M4.T3.S1 (tests): the committed client-width-cache + scroll tests (planned).

CONFIG / DATABASE / ROUTES: none.
```

## Validation Loop

### Level 1: Syntax & Style (Immediate Feedback)

```bash
cd /home/dustin/.config/tmux/plugins/tmux-livepicker
bash -n scripts/livepicker.sh scripts/input-handler.sh scripts/restore.sh && echo "OK: syntax"
shellcheck scripts/livepicker.sh scripts/input-handler.sh scripts/restore.sh
# the 4 edits landed:
grep -c 'STATE_CLIENT_WIDTH' scripts/livepicker.sh             # -> >=1
grep -c 'tmux_clear_hook client-resized' scripts/livepicker.sh # -> 1
grep -c "set-hook -g client-resized" scripts/livepicker.sh     # -> 1
grep -c 'refresh-width)' scripts/input-handler.sh              # -> 1
grep -c 'tmux_clear_hook client-resized' scripts/restore.sh     # -> 1
grep -c 'ORIG_CLIENT_RESIZED_HOOK' scripts/restore.sh           # -> >=1
# Tabs-not-spaces in the new regions:
grep -nP '^ +[^#/]' scripts/livepicker.sh scripts/input-handler.sh scripts/restore.sh | tail && echo "WARN" || echo "OK: tabs"
# Expected: syntax clean; shellcheck 0 new findings; all grep counts as shown.
```

### Level 2: Full suite (the load-bearing gate — byte-exact restore)

```bash
cd /home/dustin/.config/tmux/plugins/tmux-livepicker
tests/run.sh
# Expected: exit 0, 44/44 green. THE gate is test_restore_cancel_options_hooks_exact
# (test_restore.sh:44): it diffs `show-hooks -g | sort` before activate vs after cancel.
# RATIONALE (research §4): the save->clear->install + clear->replay cycle is empirically
# byte-identical for BOTH the unset prior (client-resized bare <-> bare) and the set prior
# ([0] <-> [0]). test_appearance.sh seeds state + runs renderer.sh directly (never activates)
# -> STATE_CLIENT_WIDTH unset -> width=0 -> unchanged. test_functional.sh activates (captures
# a real width ~120 -> wide viewport, all tabs visible) but uses assert_contains (substring)
# -> still holds. If test_restore_cancel_options_hooks_exact FAILS, the client-resized restore
# left ours installed -> re-check the leading `tmux_clear_hook client-resized` in restore STEP 4.
```

### Level 3: Throwaway client-width smoke (capture + hook + byte-identity; then DELETE)

```bash
cat > /tmp/smoke_cw.sh <<'SMOKE'
#!/usr/bin/env bash
set -u
cd /home/dustin/.config/tmux/plugins/tmux-livepicker
source tests/setup_socket.sh; source tests/helpers.sh
pass_n=0; fail_n=0
ck() { if [ "$2" = "$3" ]; then pass_n=$((pass_n+1)); else fail_n=$((fail_n+1)); echo "FAIL $1: got[$2] want[$3]"; fi; }

setup_test "lp-cw-smoke"
attach_test_client
hks_before="$(tmux show-hooks -g | sort)"
# activate captures width + installs the hook.
"$LIVEPICKER_SCRIPTS/livepicker.sh"
# (1) width captured (non-empty on an attached client).
w="$(tmux show-option -gqv @livepicker-client-width)"
[ -n "$w" ] && ck "width captured" nonempty nonempty || ck "width captured" "$w" nonempty
# (2) the hook is installed as client-resized[0] -> refresh-width.
tmux show-hooks -g | grep -q '^client-resized\[0\] run-shell.*refresh-width' \
  && ck "hook installed" installed installed || { fail_n=$((fail_n+1)); echo "FAIL: hook not installed"; }
# (3) simulate a resize -> the hook re-caches the width (call the action directly).
before_w="$w"
"$LIVEPICKER_SCRIPTS/input-handler.sh" refresh-width
after_w="$(tmux show-option -gqv @livepicker-client-width)"
[ -n "$after_w" ] && ck "refresh-width re-caches" nonempty nonempty || ck "refresh-width re-caches" "$after_w" nonempty
# (4) cancel -> show-hooks BYTE-IDENTICAL to before activate (the load-bearing gate).
"$LIVEPICKER_SCRIPTS/input-handler.sh" cancel >/dev/null 2>&1 || true
hks_after="$(tmux show-hooks -g | sort)"
[ "$hks_before" = "$hks_after" ] && ck "show-hooks byte-identical" same same \
  || { fail_n=$((fail_n+1)); echo "FAIL: hooks differ"; diff <(printf '%s\n' "$hks_before") <(printf '%s\n' "$hks_after"); }
teardown_test
echo "pass=$pass_n fail=$fail_n"; [ "$fail_n" -eq 0 ]
SMOKE
bash /tmp/smoke_cw.sh; rc=$?; rm -f /tmp/smoke_cw.sh; exit $rc
# Expected: all pass. (1) width captured; (2) client-resized[0] -> refresh-width installed;
# (3) refresh-width re-caches; (4) show-hooks byte-identical after cancel. (Committed tests: P1.M4.T3.)
```

### Level 4: Real resize fires the hook (optional; proves the live path)

```bash
# In an isolated socket with an attached pty client, activate, then resize the client
# pane, and confirm @livepicker-client-width changes (the hook fired -> refresh-width ran).
# This is inherently interactive; the L3 smoke (calling refresh-width directly) covers the
# action logic; this step confirms tmux dispatches client-resized -> run-shell on resize.
# (Skippable if the pty resize is hard to drive programmatically; the unit of correctness
#  is the byte-identity + the action, both proven in L2/L3.)
```

## Final Validation Checklist

### Technical Validation
- [ ] `bash -n` + `shellcheck` clean on livepicker.sh, input-handler.sh, restore.sh.
- [ ] L1 grep: capture/save/clear/install in livepicker; refresh-width in input-handler; clear-first + replay in restore.
- [ ] Tabs only in the new regions.

### Feature Validation
- [ ] activate captures a non-empty `@livepicker-client-width` (attached client).
- [ ] `client-resized[0] run-shell "...refresh-width"` present while active.
- [ ] `refresh-width` re-caches the width + redraws (no preview/filter/index work).
- [ ] After cancel/confirm, `show-hooks -g` byte-identical to pre-activate (unset + set cases).
- [ ] `@livepicker-client-width` + `@livepicker-orig-client-resized` cleared on exit (auto via the clear-lists).

### Code Quality Validation
- [ ] Mirrors the §P4 hook save/restore shape (verbatim replay, index + -b preserved).
- [ ] The ONE difference (clear-first at restore) is correct + documented.
- [ ] Uses the house helpers (lp_client_format/tmux_get_hook/tmux_clear_hook/get_state/set_state); no raw tmux for those ops.
- [ ] client-resized restore NOT gated (unlike session-window-changed); install uses the run-shell key-binding form.
- [ ] Disjoint from the parallel P1.M2.T3.S1 (renderer.sh); no other file touched.

### Documentation & Deployment
- [ ] Inline comments cross-reference PRD §9/§10 step 5/§3.35 + §P4 + the clear-first difference.
- [ ] restore STEP 4 header + input-handler line-13 enum updated to name client-resized/refresh-width.
- [ ] No README/CHANGELOG edit here (the §10/§11 option rows are P4.T1's Mode-B sync).

---

## Anti-Patterns to Avoid

- ❌ Don't omit the `tmux_clear_hook client-resized` at the START of restore — activate installs
  ours at [0]; without the clear, ours LEAKS after exit when the user had no prior hook, and the
  byte-exact-restore test FAILS. (research §3/§4; the ONE difference from session-window-changed.)
- ❌ Don't clear before saving at activate — `tmux_get_hook` reads the LIVE state; clearing first
  saves your own clear (loses the user's hook). Order: save → clear → install.
- ❌ Don't gate the client-resized restore on `opt_suppress_window_hook` — that gate is specific to
  session-window-changed (an opt-in suppression). The width cache is ALWAYS installed → ALWAYS
  restored. Wrapping it in the gate would skip restore when suppression is off → ours leaks.
- ❌ Don't use the index-less `set-hook -g client-resized "$cmd"` at restore — it ALWAYS writes [0]
  and would clobber a multi-index hook. Use `client-resized[$idx]` (mirror session-window-changed).
- ❌ Don't add STATE_CLIENT_WIDTH / ORIG_CLIENT_RESIZED_HOOK to the clear-lists again — they're
  already there (state.sh:66 + the @livepicker-orig- grep). clear_all_state (STEP 6) handles them.
- ❌ Don't make `refresh-width` do preview/filter/index work — it ONLY re-caches width + refreshes.
  Don't route it through `_lp_preview_follow`. It's a hook callback, not a user action.
- ❌ Don't read `#{client_width}` with bare `display-message -p` — use `lp_client_format` (client-
  aware; the context-free form returns the SERVER's last-active client's width, which can be wrong
  under a stale pointer — the H1 fix rationale).
- ❌ Don't touch renderer.sh (the consumer) — it's owned by the parallel P1.M2.T3.S1. This task
  only WRITES STATE_CLIENT_WIDTH; the reader is already wired.
- ❌ Don't write a committed test — the cache tests are P1.M4.T3.S1. Validate via the full suite
  (the byte-exact gate) + the throwaway L3 smoke (delete after).
- ❌ Don't change the order (capture must follow T2; install must precede T3's first render).
- ❌ Don't use spaces for indent — TABS only (the files are tab-indented; a space edit won't match).

---

## Confidence Score

**9 / 10** for one-pass success. Rationale: every dependency is **grep-confirmed landed**
(STATE_CLIENT_WIDTH + ORIG_CLIENT_RESIZED_HOOK in the auto-clear lists; lp_client_format;
tmux_get_hook/tmux_clear_hook), and the consumer (renderer.sh:195) is already wired — this
task is purely the producer (activate capture + hook install) + the restore symmetry + the
hook's refresh-width action. The §P4 hook save/restore pattern is established (session-window-
changed), and the ONE difference (clear-first at restore, because activate installs rather
than just suppresses) is **empirically proven byte-identical** for both the unset and the set
prior-hook case (research §4 — the load-bearing gate). The install form (single-quoted arg
inside a double-quoted run-shell) is verified to install as `client-resized[0]`, and
`#{client_width}` is confirmed to resolve client-awarely (80 with a client, empty without).
The 3 edits are small with verbatim old→new blocks anchored on unique content; the existing
suite stays green (test_restore's byte-identity gate + test_appearance's width=0 path +
test_functional's substring asserts — research §5). Residual risks: (a) the clear-first-at-
restore subtlety — if missed, the byte-exact test fails (mitigated: loud FINDING callout + the
L2 gate catches it deterministically); (b) anchoring on the restore session-window-changed tail
— mitigated by the unique `# --- STEP 5` anchor. The 1-point deduction is for the byte-exact-
restore sensitivity (a single missed `tmux_clear_hook` fails the suite), which is explicitly
gated by L2.
