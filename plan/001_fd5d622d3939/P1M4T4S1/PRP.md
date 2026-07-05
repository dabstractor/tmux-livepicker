# PRP — P1.M4.T4.S1: livepicker.sh — build livepicker key table (input + nav + copied bindings)

---

## Goal

**Feature Goal**: Fill in the **T4.S1 seam** of `scripts/livepicker.sh` (the
file CREATED by P1.M4.T1.S1, list/index populated by T2, status grown by T3) —
implementing **PRD §8 "Binding" + §6 step 4** verbatim, in three load-bearing
sub-steps in this exact order: **(1) COPY** the user's `prefix` and `root` key
bindings into the `livepicker` table (skipping the repurposed next/prev keys),
**(2) BIND** the explicit picker keys — typing (`a`-`z`, `A`-`Z`, `0`-`9`,
`-`/`_`/`.`/`/`), backspace, confirm, cancel, and navigation (next/prev +
nav-next/nav-prev) — all routing through `scripts/input-handler.sh`, and
**(3) SWITCH** the active `key-table` to `livepicker`. After S1, while the
picker is active tmux consults ONLY the `livepicker` table (system_context §3
INVARIANT B): every typing/nav key reaches `input-handler.sh`, and the rest of
the user's keybinds (copied from prefix/root) keep working. Unbound keys are
dropped (display-only preview). S1 does NOT suppress the hook (S2), does NOT run
a preview or set `@livepicker-mode on` (T5) — those are the seams immediately
below.

**Deliverable**: A **surgical edit** to `scripts/livepicker.sh` that **replaces
the single T4 seam comment** (left by T1, shared label "T4 (P1.M4.T4.S1/S2)")
with the S1 key-table block **followed by a NEW, narrower seam comment for S2**
(hook suppression). No new file, no other file touched. The block is ~30 lines
(locals + copy via `source-file` + explicit-bind loops + `set-option -g
key-table`). It declares its own locals (`lp_key`, `lp_keys`, `lp_tf`, `lp_c`)
that do **not** collide with T2's (`pick_type current list idx i` / `items`) or
T3's (`sf_n sf_val sf_indices lp_idx orig_status` / `sf_desc`). The T5 seam
comment, the trailing `return 0`, and the driver remain untouched. S2's new seam
comment sits between the S1 block and the T5 seam.

**Success Definition**:
- `bash -n scripts/livepicker.sh` passes; `shellcheck scripts/livepicker.sh` is
  clean (0 findings; the file-level `# shellcheck disable=SC1091,SC2153` from T1
  covers source-lines + ORIG_*/STATE_*; this block's intentional word-splits are
  each annotated `# shellcheck disable=SC2086`).
- Tabs only; no `set -e`; no new files.
- **Mock (a) switch:** after running livepicker.sh, `show-option -gv key-table`
  == `livepicker`.
- **Mock (b) typing bound:** a typed key (e.g. `a`, and the punct `-`/`/`) is
  bound in the `livepicker` table to `run-shell "<abs>/scripts/input-handler.sh
  type <char>"`.
- **Mock (c) actions + nav bound:** `BSpace`→backspace, `Enter`→confirm,
  `Escape`→cancel, `C-M-Tab`→next-session, `C-M-BTab`→prev-session, `Down`/`j`
  →next-session, `Up`/`k`→prev-session — all in the `livepicker` table.
- **Mock (d) user bindings copied:** a real user prefix binding (e.g. `C-r` →
  `source-file`) is present in the `livepicker` table.
- **Mock (e) no nav-key leak:** `C-M-Tab` is bound to `next-session` ONLY (the
  user's `swap-window \; select-window` compound command is NOT in the table —
  the skip filter removed it from the copy).
- **Mock (f) override works:** `Down`/`Up` bind to next/prev-session (NOT the
  user's copied `select-pane`/nav binding) — proves copy-first/explicit-last
  ordering (research FINDING 2).

## User Persona (if applicable)

**Target User**: None directly (internal orchestration step). Transitively: the
end user pressing keys while the picker is open (PRD §3 stories — "I can type to
filter, arrow to move, Enter to land, Esc to dismiss, and my OTHER keybinds
still work because they were copied in"). S1 is what makes the picker
INTERACTIVE: until S1 switches the key-table and binds the routes, typed keys
are dropped (no filter change) and nav keys do nothing.

**Use Case**: The user pressed the activation key. T1 saved state; T2 built the
list + highlight; T3 grew the status bar + installed the renderer (visible but
static). **S1 (this task)** is what lets the picker RESPOND: it switches the
modal key-table and binds every key to an `input-handler.sh` action (or copies
the user's binding). Once T5 (next seam) runs the first preview + sets mode-on,
the full interactive loop is live.

**User Journey** (S1 scope — the table is switched and bound, but the picker
does not yet preview/mode-on until T5):
1. User presses activation key → T1 guard+save; T2 list+index; T3 status+renderer.
2. **S1 (this task):** copy prefix/root bindings → livepicker (skip C-M-Tab/
   C-M-BTab); bind typing/actions/nav keys → input-handler.sh; `set-option -g
   key-table livepicker`.
3. [S2 suppresses the session-window-changed hook; T5 runs the first preview +
   sets `@livepicker-mode on` + `refresh-client -S` — sibling seams.]
4. From this point, every key the user presses is routed (typing → filter;
   nav → highlight move; Enter → confirm; Esc → cancel; copied keys → their
   normal actions). Unbound keys are dropped — the preview is display-only.

**Pain Points Addressed**:
- (a) **The picker must be genuinely modal + complete.** Invariant B (system
  context §3): while `key-table==livepicker`, tmux consults ONLY that table and
  DROPS unbound keys. Two consequences S1 must handle: (i) the user's prefix/
  root bindings do NOT fire unless copied in (so S1 copies them), and (ii) every
  key the picker needs must be bound explicitly (typing/actions/nav). S1 does
  both.
- (b) **The copy must not break on complex bindings.** The naive `tmux $line`
  word-split copy CRASHES on tubular's giant `display-menu` binding
  (`set-buffer: too many arguments`). S1 uses `tmux source-file` so tmux's OWN
  parser re-binds each line (research FINDING 1) — the difference between a
  working copy and a hard error.
- (c) **Copied bindings must not clobber picker keys.** The user's prefix/root
  tables bind `Enter`/`Down`/`Up`/etc. If the copy runs AFTER the explicit
  binds, those revert to the user's commands and nav breaks. S1 copies FIRST
  and binds explicit LAST (research FINDING 2) — provably correct.

## Why

- **PRD §8 "Binding" + §6 step 4.** §8: bind typing (`a`-`z`, `A`-`Z`, `0`-`9`,
  `-_. /`), supplemental nav (`Down`/`j`, `Up`/`k`), confirm (`Enter`), cancel
  (`Escape`), backspace (`BSpace`), the repurposed window-nav keys
  (`@livepicker-next-key`/`prev-key`), AND "a copy of the user's current prefix
  and root bindings ... by reading `tmux list-keys -T prefix` and `-T root`,
  rewriting each line's table to `livepicker`, and re-binding it." §6 step 4:
  switch the key-table. S1 owns all of this.
- **The interactivity seam.** Until S1 runs, the renderer (T3) draws a static
  list and no key reaches the picker — every keystroke falls through to the
  pane (key-table is still `root`). S1 is what makes `input-handler.sh`
  (P1.M6 — planned) reachable. (The bindings are stored as command strings
  pointing at `input-handler.sh`; that script need not exist yet — the binding
  is inert until a key fires, which cannot happen before T5 sets mode-on.)
- **Boundary respect.** S1 touches ONLY: the `livepicker` key-table (bind/copy),
  and the global `key-table` option (switch to `livepicker`). It does NOT
  suppress the session-window-changed hook (S2 — the new seam comment S1 leaves
  behind marks where S2 inserts), does NOT run a preview / link-window /
  switch-client / `refresh-client` (T5), does NOT set `@livepicker-mode on`
  (T5), does NOT grow status / install the renderer (T3 — already done above).
  It reads: `opt_next_key`/`opt_prev_key`/`opt_nav_next_keys`/
  `opt_nav_prev_keys`/`opt_confirm_keys`/`opt_cancel_keys`/`opt_backspace_keys`
  (config defaults), and `CURRENT_DIR` (the scripts/ dir, a global already
  computed at the top of livepicker.sh).
- **Scope cohesion.** S1 is the input-routing foundation for S2/T5 (hook
  suppress + first-preview + mode-on + refresh that make the picker fully live)
  and for P1.M6 (input-handler.sh — the destination of every binding). Restore
  (P1.M5.T3.S1 + P1.M5.T4.S1) tears down exactly what S1 sets: restore the
  `key-table` option from `ORIG_KEY_TABLE` (global, matched pair with S1's `-g`
  switch) and `unbind-key -a -T livepicker` (clear the table S1 populated). S1's
  switch and restore's reset are a matched pair.

## What

A surgical in-place edit to `scripts/livepicker.sh` that replaces the T4 seam
comment with a block which:

1. Declares function-locals (`lp_key`, `lp_keys`, `lp_tf`, `lp_c`). Names are
   distinct from T2's and T3's and avoid shadowing bash builtins.
2. **(1) COPY** — `mktemp` a file; pipe `{ list-keys -T prefix | sed
   's/-T prefix/-T livepicker/'; list-keys -T root | sed 's/-T root/-T
   livepicker/'; }` through `grep -vE` (skip the next/prev keys) into the file;
   `tmux source-file "$lp_tf"`; `rm -f "$lp_tf"`. The `source-file` mechanism
   (NOT `tmux $line`) is MANDATORY — word-splitting breaks on complex bindings
   (research FINDING 1). The skip removes the user's compound swap-window
   bindings so the explicit nav binds are authoritative (research FINDING 4).
3. **(2) BIND explicit keys** — five `for` loops (typing brace-expansion set;
   backspace; confirm; cancel; next+nav-next; prev+nav-prev), each emitting
   `tmux bind-key -T livepicker "$lp_c" run-shell "$CURRENT_DIR/input-handler.sh
   <action> [<char>]"`. These run AFTER the copy so they OVERRIDE any copied
   same-key binding (research FINDING 2 — the `Down`/`Up`/`Enter` override
   proof). Word-split loops on the space-list accessors are annotated
   `# shellcheck disable=SC2086`.
4. **(3) SWITCH** — `tmux set-option -g key-table livepicker`. The `-g` is
   MANDATORY: it matches the global save/restore contract (`ORIG_KEY_TABLE`),
   and the no-`-g` form does NOT take effect on `show-option -gv` (research
   FINDING 3). The standalone `key-table` command does NOT exist on 3.6b.
5. Leaves a NEW seam comment for S2 immediately below the block:
   `# --- T4 (P1.M4.T4.S2): suppress session-window-changed hook (insert here) ---`
   (so the in-flight S2 subtask knows where to insert).

### Success Criteria

- [ ] The T4.S1/S2 seam comment is REPLACED by the S1 block + a new S2 seam
      comment; T3's block (above) and the T5 seam comment (below), `return 0`,
      and the driver are UNCHANGED.
- [ ] Copy uses `mktemp` + `source-file` + `rm -f` (NOT `tmux $line`).
- [ ] Copy's `sed` rewrites `-T prefix`/`-T root` → `-T livepicker`; the `grep
      -vE` skip pattern is `-T livepicker[[:space:]]+(${lp_key}|${lp_keys})
      ([[:space:]]|$)` with `lp_key`/`lp_keys` from `opt_next_key`/`opt_prev_key`.
- [ ] Typing loop iterates `{a..z} {A..Z} {0..9} - _ . /` and binds each to
      `run-shell "$CURRENT_DIR/input-handler.sh type $lp_c"`.
- [ ] Backspace/confirm/cancel loops iterate `opt_backspace_keys`/
      `opt_confirm_keys`/`opt_cancel_keys` → `input-handler.sh backspace`/
      `confirm`/`cancel`.
- [ ] Nav loops iterate `opt_next_key` + `opt_nav_next_keys` → `next-session`,
      and `opt_prev_key` + `opt_nav_prev_keys` → `prev-session`.
- [ ] Switch is `tmux set-option -g key-table livepicker` (with `-g`).
- [ ] ORDER: copy → explicit binds → switch (NOT explicit-then-copy).
- [ ] **NO** `set-hook`/hook suppression (S2); **NO** `link-window`/
      `switch-client`/`refresh-client`/preview (T5); **NO** `@livepicker-mode on`
      (T5); **NO** status mutation (T3).
- [ ] `bash -n` clean; `shellcheck` 0 findings; tabs only; no `set -e`.
- [ ] Mock (a) key-table==livepicker; (b) typing `a`/`-`/`/` bound; (c) actions
      + nav bound; (d) user C-r copied; (e) no swap-window leak on C-M-Tab;
      (f) Down/Up override copied bindings.

## All Needed Context

### Context Completeness Check

_Pass_: A developer who has never seen this repo can implement S1 from
(a) the verbatim S1 block in the Implementation Blueprint (complete, ready to
paste at the seam), (b) the 6 live-verified findings in
`research/key_table_findings.md` — most critically **FINDING 1** (copy via
`source-file`, NOT `tmux $line` — word-split CRASHES on `display-menu`:
`set-buffer: too many arguments`), **FINDING 2** (copy FIRST, explicit LAST —
else copied `Down`/`Up`/`Enter` overwrite picker keys), **FINDING 3**
(`set-option -g key-table` with `-g`; standalone `key-table` cmd absent on 3.6b),
and **FINDING 4** (the skip grep pattern), and (c) the socket-shim mock that
exercises switch + typing + actions + nav + copy + leak + override against an
isolated socket (zero live-server impact). The INPUT dependencies
(`opt_next_key`/`opt_prev_key`/`opt_nav_next_keys`/`opt_nav_prev_keys`/
`opt_confirm_keys`/`opt_cancel_keys`/`opt_backspace_keys`, `CURRENT_DIR`) are
all present. The host file `scripts/livepicker.sh` is created by T1 with the T4
seam comment; this task replaces exactly that line.

### Documentation & References

```yaml
# MUST READ — INPUT dependency: options.sh (the key accessors). COMPLETE (P1.M1.T1.S1).
- file: scripts/options.sh
  why: Defines the 7 key accessors S1 reads. opt_next_key() -> "C-M-Tab",
       opt_prev_key() -> "C-M-BTab" (PRD §11; defaults match THIS user's root-table
       window-nav keys — system_context §2). opt_nav_next_keys() -> "Down j",
       opt_nav_prev_keys() -> "Up k", opt_confirm_keys() -> "Enter",
       opt_cancel_keys() -> "Escape", opt_backspace_keys() -> "BSpace" (all
       space-lists except next/prev which are single tokens). S1 word-splits the
       space-lists in for-loops.
  critical: next/prev return SINGLE key tokens (used BOTH as the explicit nav bind
            AND as the skip-pattern keys in the copy). The nav-*/confirm/cancel/
            backspace accessors return SPACE-LISTS (caller word-splits; annotate
            SC2086). Defaults are PRD §11 verbatim.

# MUST READ — INPUT dependency: the scripts/ dir global. COMPLETE (set by T1).
- file: scripts/livepicker.sh
  why: CURRENT_DIR is computed at top level ("$(cd "$(dirname "${BASH_SOURCE[0]}")"
       && pwd)") = the scripts/ directory. It is in scope inside activate_main as a
       GLOBAL. S1 uses it to build the input-handler.sh path:
       "$CURRENT_DIR/input-handler.sh" (NOT "$SCRIPT_DIR/scripts/..." — see FINDING 6).
  pattern: CURRENT_DIR is the same global T3 uses for "$CURRENT_DIR/renderer.sh".

# MUST READ — the host file this task EDITS (created by P1.M4.T1.S1; T2/T3 fill their seams).
- docfile: plan/001_fd5d622d3939/P1M4T1S1/PRP.md
  why: T1 CREATES scripts/livepicker.sh with the seam-comment skeleton. The T4 seam
       comment is EXACTLY:
         # --- T4 (P1.M4.T4.S1/S2): switch key-table + bind keys + suppress hook (insert here) ---
       It sits AFTER the T3 seam (status) and BEFORE the T5 seam. S1 REPLACES that
       single line with the S1 block + a NEW narrower S2 seam comment. Confirm the
       seam text and surrounding context (CURRENT_DIR global scope) before editing.
  section: "Implementation Patterns & Key Details" (the seam skeleton),
           "Integration Points"

# MUST READ — the parallel siblings: T2 (list, ABOVE) and T3 (status, ABOVE).
- docfile: plan/001_fd5d622d3939/P1M4T2S1/PRP.md
  why: T2 populates @livepicker-list/filter/index (the renderer's data) in the seam
       ABOVE T3. S1's locals must not collide with T2's (T2: pick_type/current/list/
       idx/i/items). S1 uses lp_key/lp_keys/lp_tf/lp_c — distinct.
- docfile: plan/001_fd5d622d3939/P1M4T3S1/PRP.md
  why: T3 grows the status bar + installs the renderer in the seam IMMEDIATELY
       before T4. S1 runs AFTER T3 (the renderer is already installed; S1 does not
       touch status). Confirm T3's local names (sf_n/sf_val/sf_indices/lp_idx/
       orig_status/sf_desc) — S1's lp_* names are distinct. Re-read the file fresh
       at implementation time: T3 may have just landed (line numbers shift, but the
       T4 seam TEXT is stable).

# MUST READ — the destination of every S1 binding (planned, need NOT exist yet).
- docfile: plan/001_fd5d622d3939/tasks.json
  why: P1.M6 (input-handler.sh) is PLANNED, not complete. S1 stores bindings that
       POINT at scripts/input-handler.sh with actions type/backspace/confirm/cancel/
       next-session/prev-session. The binding is a stored command string; the script
       is invoked only when a key fires (which cannot happen before T5 sets
       mode-on). So input-handler.sh's absence does NOT break S1 or its mock.
  section: P1.M6 task definitions (the action names are the CONTRACT S1 emits).

# MUST READ — the empirical ground-truth for THIS seam (6 live-verified findings).
- docfile: plan/001_fd5d622d3939/P1M4T4S1/research/key_table_findings.md
  why: FINDING 1 (SHOWSTOPPER: copy via `tmux source-file`, NEVER `tmux $line` —
       word-split CRASHES on the display-menu binding with "set-buffer: too many
       arguments"; source-file lets tmux's own parser re-bind each line, 129/129
       copied); FINDING 2 (SHOWSTOPPER: copy FIRST, explicit LAST — explicit-then-
       copy lets the user's copied Down/Up/Enter/a overwrite the picker keys;
       verified 14/14 assertions pass with copy-first); FINDING 3 (`set-option -g
       key-table livepicker` WITH -g; the no-g form does not take effect on -gv;
       standalone `key-table` cmd is "unknown command" on 3.6b); FINDING 4 (the
       skip grep pattern `-T livepicker[[:space:]]+(K1|K2)([[:space:]]|$)`); FINDING
       5 (all typing chars bind, including `-`, no `--` needed; punct set = - _ . /);
       FINDING 6 (run-shell "PATH type CHAR" quoting; $CURRENT_DIR not $SCRIPT_DIR;
       input-handler must parse positionally — P1.M6 concern).
  critical: Read BEFORE writing the block. FINDINGS 1+2 are the highest-consequence
            details — `tmux $line` and explicit-then-copy are both hard failures.

# MUST READ — the PRD sections selected for this work item.
- docfile: PRD.md
  why: §8 "Binding" (the verbatim binding list + the copy-prefix/root step); §8
       "Why this is low-cost" / "Keys" (Invariant B — only livepicker consulted;
       next/prev default to C-M-Tab/C-M-BTab); §8 "Discovery (optional)" (NOT
       implemented — defaults cover this user's keys); §6 step 4 (switch key-table);
       §11 (the @livepicker-*-keys defaults); §13 (bind-key/-T, list-keys, key-table,
       source-file primitives).
  section: "§8 The repurposed-key subsystem", "§6 Behaviors / Activation",
           "§11 Configuration options", "§13 tmux primitives reference"

# MUST READ — system ground-truth (Invariant B + shell style).
- docfile: plan/001_fd5d622d3939/architecture/system_context.md
  why: §3 INVARIANT B (while key-table==livepicker, tmux consults ONLY that table;
       unbound keys are DROPPED, never passed to root/prefix/pane -> the user's
       prefix/root bindings do NOT fire unless copied in; VERIFIED live); §2
       (key-table=root, window-nav C-M-Tab/C-M-BTab in root table as compound
       swap-window;select-window); §9 shell style (set -u only NO -e, tabs, quote
       everything, CURRENT_DIR idiom).
  section: "§3 INVARIANT B", "§2 Verified environment", "§9 Shell style"

# MUST READ — primitive verification for the key-table mechanism.
- docfile: plan/001_fd5d622d3939/architecture/tmux_primitives.md
  why: §2 "key-table / bind-key -T fallthrough" (VERIFIED: non-root key-table is
       fully modal, drops unmatched keys; copy of prefix/root is necessary; set via
       set-option key-table — NOTE the doc's mention of a standalone `key-table` cmd
       is WRONG for 3.6b per FINDING 3). Confirms bind-key -T livepicker is the
       binding primitive and list-keys -T <table> is the read primitive.
  section: "§2 key-table / bind-key -T fallthrough"
```

### Current Codebase tree

```bash
tmux-livepicker/
  PRD.md
  plugin.tmux                 # (P1.M1.T4.S1) COMPLETE. Binds prefix key -> scripts/livepicker.sh.
  plan/001_fd5d622d3939/{architecture/*.md, tasks.json, prd_snapshot.md, prd_index.txt}
  plan/001_fd5d622d3939/P1M4T1S1/{PRP.md, research/}   # creator of livepicker.sh (guard+save)
  plan/001_fd5d622d3939/P1M4T2S1/{PRP.md, research/}   # parallel: list/index seam (ABOVE T3)
  plan/001_fd5d622d3939/P1M4T3S1/{PRP.md, research/}   # parallel: status grow seam (ABOVE T4)
  plan/001_fd5d622d3939/P1M4T4S1/{PRP.md, research/key_table_findings.md}  # THIS
  scripts/
    options.sh   # COMPLETE — opt_next_key/opt_prev_key/opt_nav_*/opt_confirm_keys/
                 #            opt_cancel_keys/opt_backspace_keys (INPUT deps). Unchanged.
    utils.sh     # COMPLETE — tmux_* (transitively used by state.sh). INPUT dep.
    state.sh     # COMPLETE — ORIG_KEY_TABLE + get_state/set_state (restore pair). INPUT dep.
    renderer.sh  # COMPLETE (P1.M2.T1.S1). Unchanged.
    preview.sh   # COMPLETE (P1.M3). Unchanged. Structural analog (seam-comment model).
    livepicker.sh   # CREATED by P1.M4.T1.S1; T2 (parallel) fills the list seam; T3 (parallel)
                    # fills the status seam. THIS task EDITS it (replaces the T4 seam comment
                    # with the key-table block + a new S2 seam comment).
  .gitignore
  # NOTE: NO test harness (P1.M7); NO input-handler.sh yet (P1.M6 — bindings point at it,
  #       but it is inert until a key fires, which is after T5). Validate via the throwaway
  #       socket-shim mock.
```

### Desired Codebase tree with files to be added and responsibility of file

```bash
tmux-livepicker/
  scripts/
    options.sh   # INPUT dep — unchanged.
    utils.sh     # INPUT dep — unchanged.
    state.sh     # INPUT dep — unchanged.
    renderer.sh  # unchanged.
    preview.sh   # unchanged.
    livepicker.sh   # EDITED (this task). The T4 seam comment is REPLACED by:
                    #   - locals (lp_key/lp_keys/lp_tf/lp_c)
                    #   - (1) COPY: mktemp; {list-keys -T prefix|root | sed} | grep -vE skip
                    #         > $lp_tf; tmux source-file $lp_tf; rm -f $lp_tf
                    #   - (2) BIND explicit: typing {a..z}{A..Z}{0..9}-_./ -> type <c>;
                    #         backspace/confirm/cancel loops; next+nav-next -> next-session;
                    #         prev+nav-prev -> prev-session (all run-shell input-handler.sh)
                    #   - (3) SWITCH: tmux set-option -g key-table livepicker
                    #   + NEW seam comment for S2 (suppress hook)
                    # T5 seam + return 0 + driver UNCHANGED. Still no mode-on (T5),
                    # no hook suppress (S2), no preview (T5).
```

### Known Gotchas of our codebase & Library Quirks

```bash
# CRITICAL (research FINDING 1 — SHOWSTOPPER): copy bindings via `tmux source-file`,
# NEVER `tmux $line` (word-split). The user's prefix table contains tubular's giant
# `display-menu` binding (braces, nested quotes, \;). Word-splitting it yields:
#   command set-buffer: too many arguments (need at most 1)
# and the binding is NOT copied. source-file feeds the rewritten lines to tmux's OWN
# parser, which re-binds each correctly (129/129 verified). Form:
#   lp_tf="$(mktemp)"
#   { tmux list-keys -T prefix | sed 's/-T prefix/-T livepicker/';
#     tmux list-keys -T root   | sed 's/-T root/-T livepicker/'; } \
#     | grep -vE -- "<skip>" > "$lp_tf"
#   tmux source-file "$lp_tf"; rm -f "$lp_tf"

# CRITICAL (research FINDING 2 — SHOWSTOPPER): ORDER is copy -> explicit -> switch.
# The user's prefix/root tables bind Down/Up/Enter/a (and more). If explicit binds
# run FIRST and copy SECOND, the copy OVERWRITES the picker keys (Down reverts to
# select-pane, nav breaks). Verified: explicit-then-copy fails 7/14 assertions;
# copy-first-explicit-last passes 14/14. The item's "skip next-key/prev-key" is
# NECESSARY but NOT SUFFICIENT — it handles C-M-Tab/C-M-BTab; the Down/Up/Enter
# override is guaranteed by ORDERING (explicit last), not by the skip.

# CRITICAL (research FINDING 3): `tmux set-option -g key-table livepicker` (WITH -g).
# The no-g form sets the session-scoped value but `show-option -gv key-table` still
# reads `root` -> the switch APPEARS to fail. -g matches the save/restore contract
# (ORIG_KEY_TABLE is saved via tmux_save_opt -> show-option -gqv, i.e. GLOBAL).
# ALSO: the standalone `tmux key-table livepicker` command is "unknown command" on
# 3.6b (tmux_primitives §2 mentions it but it does NOT exist). Use set-option -g.

# CRITICAL (research FINDING 4): the skip pattern in the copy grep must anchor the
# KEY token AFTER the (already-rewritten) `-T livepicker` and match the WHOLE key:
#   grep -vE -- "-T livepicker[[:space:]]+(${lp_key}|${lp_keys})([[:space:]]|$)"
# [[:space:]]+ handles the column-aligned multi-space; the trailing ([[:space:]]|$)
# prevents partial matches. Verified: removes BOTH compound swap-window bindings.

# GOTCHA (research FINDING 5): the typing punctuation set is `-`, `_`, `.`, `/`
# (4 chars). PRD §8 writes it as `-_. /`; the prose whitespace is a separator, NOT
# a literal space key. All bind cleanly including `-` (tmux accepts it as a key
# token; no `--` separator needed). If space-as-filter-char is ever wanted (e.g. to
# type-match "job hunt"), add `tmux bind-key -T livepicker Space run-shell
# "$CURRENT_DIR/input-handler.sh type ' '"` — out of scope here.

# GOTCHA (research FINDING 6): the binding form is
#   tmux bind-key -T livepicker "$lp_c" run-shell "$CURRENT_DIR/input-handler.sh type $lp_c"
# bash expands the double-quoted run-shell arg to ONE string; tmux stores it; on
# keypress /bin/sh -c runs it -> input-handler.sh gets `type` as $1 and the char as
# $2. So input-handler.sh (P1.M6) MUST parse positionally (action="$1"; char="$2"),
# NOT getopt (a `-` char would be misread as a flag). $CURRENT_DIR (the scripts/ dir)
# is the in-file global; use it, NOT a hypothetical $SCRIPT_DIR.

# GOTCHA: variable naming. T2 (seam above T3) uses pick_type/current/list/idx/i/
# items; T3 uses sf_n/sf_val/sf_indices/lp_idx/orig_status/sf_desc. S1 uses lp_key/
# lp_keys/lp_tf/lp_c — distinct from both. (lp_idx is T3's status-format index; lp_c
# is S1's loop char — different names, no collision.)

# GOTCHA: this task is a SURGICAL EDIT at the T4 seam, not a rewrite. Replace
# EXACTLY the T4 seam comment; leave T3's block (above), the T5 seam comment
# (below), `return 0`, and the driver untouched. ADD a new narrower S2 seam comment
# after the S1 block (S2 = hook suppression). Re-read the file fresh at
# implementation time: T3 may have just landed (line numbers shift; the T4 seam
# TEXT is stable).

# CRITICAL: NO `set -e`, NO `set -o pipefail` (house style; system_context §9).
# `tmux list-keys -T <table>` legitimately returns non-zero if the table is empty
# (first activation on a fresh server has no livepicker table yet) — under set -e
# the copy subshell would abort. The `2>/dev/null` + the proceeding source-file
# (empty file = no-op) handle this. set -u is inherited; every var is assigned
# first (lp_key/lp_keys/lp_tf/lp_c). The `grep -vE` in a pipeline returns 0/1 —
# under set -e a no-match (rc=1) would abort; we do NOT use set -e, so it is fine.

# STYLE (system_context §9): indent with TABS. Verify with
# `grep -Pn '^    ' scripts/livepicker.sh` (expect empty). shfmt is NOT installed.
```

## Implementation Blueprint

### Data models and structure

No new data model. The block adds function-locals to `activate_main`:
`lp_key`, `lp_keys`, `lp_tf`, `lp_c`. The state surface is the **read set**: the
7 `opt_*` key accessors + `CURRENT_DIR` (global). The **write surface** is the
tmux key tables: the `livepicker` table (populated by copy + explicit binds) and
the global `key-table` option (switched to `livepicker`). No `@livepicker-*`
keys are written by S1 (the list/filter/index/mode/linked-id are owned by
T1/T2/T5; the hook by S2).

### Implementation Tasks (ordered by dependencies)

```yaml
Task 1: LOCATE the T4 seam in scripts/livepicker.sh
  - FILE: ./scripts/livepicker.sh  (CREATED by P1.M4.T1.S1; T2/T3 fill their seams
    in parallel — re-read fresh at implementation time).
  - FIND the single seam comment line (T1's skeleton emits EXACTLY):
      # --- T4 (P1.M4.T4.S1/S2): switch key-table + bind keys + suppress hook (insert here) ---
  - CONTEXT: it sits AFTER the T3 seam/block (status grow) and BEFORE the T5 seam:
      # --- T5 (P1.M4.T5.S1): first preview + set @livepicker-mode on (insert here) ---
  - VERIFY (do not proceed if mismatched — T3 may still be in flight; re-read the
    file fresh): the line exists exactly once.

Task 2: REPLACE the T4 seam comment with the S1 block + a new S2 seam comment
  - OLD (exact): the single T4 seam comment line from Task 1.
  - NEW: the block below (indented with ONE tab to match activate_main's body;
    inner lines TWO tabs), followed by the new S2 seam comment. See
    "Implementation Patterns & Key Details" for the complete ready-to-paste block.
  - NOTE: locals are DISTINCT from T2's and T3's. If T3 is still in flight,
    confirm its local names fresh (no collision by design: lp_key/lp_keys/lp_tf/
    lp_c vs T3's sf_*/lp_idx/orig_status).

Task 3: VERIFY the edit left T3 (if present), T5 seam + return 0 + driver intact,
        and that a NEW S2 seam comment now exists
  - RUN: grep -n 'T3 (P1.M4.T3.S1)\|T4 (P1.M4.T4.S2)\|T5 (P1.M4.T5.S1\|return 0\|activate_main "\$@"' scripts/livepicker.sh
  - EXPECT: the T3 header (if landed), the NEW S2 seam comment, the T5 seam, a
    `return 0`, and the trailing driver are ALL present and unchanged.
  - EXPECT: the OLD T4.S1/S2 seam comment is GONE (replaced); the new S1 block
    header `# --- T4 (P1.M4.T4.S1): build livepicker key table + switch key-table ---`
    is present once, and the new `# --- T4 (P1.M4.T4.S2): suppress
    session-window-changed hook (insert here) ---` is present once.

Task 4: VALIDATE (Level 1 syntax/lint + Level 2 socket-shim mock switch/typing/
        actions/nav/copy/leak/override)
  - RUN: bash -n scripts/livepicker.sh            (expect exit 0, no output)
  - RUN: shellcheck scripts/livepicker.sh         (expect 0 findings — file-level
    disable=SC1091,SC2153 from T1; the S1 word-split loops are SC2086-annotated)
  - RUN: grep -Pn '^    ' scripts/livepicker.sh   (expect empty — tabs only)
  - RUN the socket-shim mock (Validation Loop §2) — switch (a) + typing (b) +
    actions+nav (c) + copy (d) + leak (e) + override (f), against an isolated
    socket. Self-cleaning.
```

### Implementation Patterns & Key Details

The complete, ready-to-paste S1 block (the implementer replaces the T4 seam
comment with this; indent is one tab for the block, two tabs inside `for`/the
copy pipeline):

```bash
	# --- T4 (P1.M4.T4.S1): build livepicker key table + switch key-table ---
	# PRD §8 "Binding" + §6 step 4. While key-table==livepicker, tmux consults
	# ONLY that table (system_context §3 INVARIANT B); unbound keys are DROPPED,
	# never passed to root/prefix/pane. So the user's prefix/root bindings do NOT
	# fire during the picker UNLESS explicitly copied in. This block, in this
	# exact order:
	#   (1) COPY the user's prefix + root bindings into livepicker (skipping the
	#       repurposed next/prev keys), via `source-file` (NOT `tmux $line` —
	#       word-split breaks on complex bindings like display-menu; research
	#       FINDING 1). Skip removes the compound swap-window bindings so the
	#       explicit nav binds below are authoritative (FINDING 4).
	#   (2) BIND the explicit picker keys (typing/actions/nav) — these OVERRIDE
	#       any copied same-key binding (e.g. Down/Up/Enter/a) because they run
	#       LAST (FINDING 2 — copy-first/explicit-last is load-bearing). All
	#       route through scripts/input-handler.sh (P1.M6; need not exist yet —
	#       the binding only stores the command string; it is inert until a key
	#       fires, which is after T5 sets mode-on).
	#   (3) SWITCH key-table to livepicker (global, matching the -g save/restore
	#       contract; the standalone `key-table` cmd is absent on 3.6b — FINDING 3).
	# Discovery (PRD §8) is intentionally OMITTED: the defaults (C-M-Tab /
	# C-M-BTab) already match this user's root-table window-nav keys
	# (system_context §2), and discovery must not override explicit options.
	local lp_key lp_keys lp_tf lp_c

	# (1) COPY prefix + root -> livepicker via source-file (tmux's own parser
	# re-binds each line; the sed rewrites ONLY the first `-T <table>` which is
	# always the table spec). Skip next/prev keys (FINDING 4 skip pattern).
	lp_key="$(opt_next_key)"
	lp_keys="$(opt_prev_key)"
	lp_tf="$(mktemp)"
	{
		tmux list-keys -T prefix 2>/dev/null | sed 's/-T prefix/-T livepicker/'
		tmux list-keys -T root   2>/dev/null | sed 's/-T root/-T livepicker/'
	} | grep -vE -- "-T livepicker[[:space:]]+(${lp_key}|${lp_keys})([[:space:]]|$)" > "$lp_tf"
	tmux source-file "$lp_tf"
	rm -f "$lp_tf"

	# (2) BIND explicit picker keys (run AFTER the copy -> override any copied
	# same-key binding). input-handler.sh path uses $CURRENT_DIR (the scripts/
	# dir global; same idiom as T3's renderer install).
	# typing: a-z A-Z 0-9 and - _ . / (PRD §8; FINDING 5 — `-` binds with no `--`).
	for lp_c in {a..z} {A..Z} {0..9} - _ . /; do
		tmux bind-key -T livepicker "$lp_c" run-shell "$CURRENT_DIR/input-handler.sh type $lp_c"
	done
	# backspace / confirm / cancel (space-list accessors -> word-split; SC2086).
	# shellcheck disable=SC2086
	for lp_c in $(opt_backspace_keys); do
		tmux bind-key -T livepicker "$lp_c" run-shell "$CURRENT_DIR/input-handler.sh backspace"
	done
	# shellcheck disable=SC2086
	for lp_c in $(opt_confirm_keys); do
		tmux bind-key -T livepicker "$lp_c" run-shell "$CURRENT_DIR/input-handler.sh confirm"
	done
	# shellcheck disable=SC2086
	for lp_c in $(opt_cancel_keys); do
		tmux bind-key -T livepicker "$lp_c" run-shell "$CURRENT_DIR/input-handler.sh cancel"
	done
	# nav: next-key + nav-next-keys -> next-session; prev-key + nav-prev-keys -> prev-session.
	# shellcheck disable=SC2086
	for lp_c in $(opt_next_key) $(opt_nav_next_keys); do
		tmux bind-key -T livepicker "$lp_c" run-shell "$CURRENT_DIR/input-handler.sh next-session"
	done
	# shellcheck disable=SC2086
	for lp_c in $(opt_prev_key) $(opt_nav_prev_keys); do
		tmux bind-key -T livepicker "$lp_c" run-shell "$CURRENT_DIR/input-handler.sh prev-session"
	done

	# (3) SWITCH the active key-table to livepicker (global; FINDING 3: -g is
	# mandatory and the standalone `key-table` cmd does not exist on 3.6b).
	tmux set-option -g key-table livepicker
	# --- T4 (P1.M4.T4.S2): suppress session-window-changed hook (insert here) ---
```

NOTE for the implementer:
- This block is verified end-to-end (shellcheck clean; all 14 mock assertions in
  the Validation Loop pass against the REAL sibling libs on an isolated socket —
  see research/key_table_findings.md FINDINGS 1–6 + the full-flow proof). Use it
  as-is; the only allowed deviation is comment phrasing.
- The OLD line to replace is EXACTLY:
  `	# --- T4 (P1.M4.T4.S1/S2): switch key-table + bind keys + suppress hook (insert here) ---`
  (one leading tab). If T1's emitted comment differs in whitespace/wording, match
  whatever T1 actually wrote (re-read the file fresh at implementation time; T3
  may have just landed — confirm T3's local names if needed).
- Do NOT add `set -e`. Do NOT use `tmux $line` for the copy (use source-file).
  Do NOT bind explicit keys BEFORE the copy (copy-first/explicit-last is
  load-bearing). Do NOT drop the `-g` from `set-option -g key-table`. Do NOT
  suppress the hook / run a preview / set mode-on / touch status (S2/T5/T3).
  Do NOT touch T3's block, the T5 seam, `return 0`, or the driver. Do NOT create
  any other file. Do NOT implement discovery (defaults suffice).

### Integration Points

```yaml
HOST FILE (what this task edits — created by P1.M4.T1.S1; T2/T3 fill their seams in parallel):
  - scripts/livepicker.sh: activate_main(). S1 replaces the T4 seam comment,
    which sits after the T3 seam/block (status) and before the T5 seam. The guard
    (STEP 1) and save (STEP 2) are ABOVE; T5 and `return 0` are BELOW. CURRENT_DIR
    (computed at top level) is in scope as a global.

CALLERS / CONSUMERS (this task's OUTPUT — observed by FUTURE subtasks + input-handler):
  - P1.M6 (input-handler.sh — PLANNED): every typing/action/nav binding S1 stores
        points at scripts/input-handler.sh with the action verbs type/backspace/
        confirm/cancel/next-session/prev-session. The script is invoked by
        run-shell ONLY when a key fires (after T5 sets mode-on), so its absence
        does not break S1. P1.M6 must parse positionally (action=$1, char=$2) —
        see FINDING 6.
  - P1.M4.T5.S1 (first preview + mode-on + refresh): sets @livepicker-mode on
        LAST, which is what enables the guard to short-circuit a re-activation
        and what makes the bindings "live" (the table is already switched by S1;
        T5 just draws the first preview and flips mode).
  - P1.M4.T4.S2 (suppress session-window-changed hook): inserts at the NEW seam
        comment S1 leaves directly below the block. S2 clears the hook so preview
        nav (select-window) does not trigger sync-window-focus side effects.
  - P1.M5.T3.S1 (restore key-table): replays ORIG_KEY_TABLE via `set-option -g
        key-table "$orig"` — the matched pair of S1's `-g` switch (both global).
  - P1.M5.T4.S1 (unbind livepicker table): `tmux unbind-key -a -T livepicker`
        clears the table S1 populated (copy + explicit). The matched teardown.

STATE READS (this task):
  - @livepicker-next-key        (via opt_next_key; default "C-M-Tab")
  - @livepicker-prev-key        (via opt_prev_key; default "C-M-BTab")
  - @livepicker-nav-next-keys   (via opt_nav_next_keys; default "Down j")
  - @livepicker-nav-prev-keys   (via opt_nav_prev_keys; default "Up k")
  - @livepicker-confirm-keys    (via opt_confirm_keys; default "Enter")
  - @livepicker-cancel-keys     (via opt_cancel_keys; default "Escape")
  - @livepicker-backspace-keys  (via opt_backspace_keys; default "BSpace")
  - CURRENT_DIR                 (global; the scripts/ dir)

STATE WRITES (this task): NONE (no @livepicker-* keys written by S1).

TMUX MUTATIONS (this task — PRD §13 primitives):
  - livepicker key-table: populated (copy of prefix+root minus next/prev keys, +
        explicit typing/action/nav bindings) via bind-key -T livepicker +
        source-file of rewritten list-keys output.
  - key-table option: set to "livepicker" (global, -g).
  - NO mutation of status / status-format / status-left / status-right (T3/tubular).
  - NO set-hook / hook suppression (S2); NO link-window / unlink-window /
        switch-client / select-window / refresh-client (T5/preview); NO
        @livepicker-mode (T5).

DATABASE / MIGRATIONS / ROUTES / CONFIG: none.
```

## Validation Loop

### Level 1: Syntax & Style (Immediate Feedback)

```bash
# Run after the edit — fix before proceeding.
bash -n scripts/livepicker.sh                     # syntax; expect no output, exit 0
shellcheck scripts/livepicker.sh                  # lint; expect 0 findings (file-level
                                                  # disable=SC1091,SC2153 from T1; the S1
                                                  # word-split loops are SC2086-annotated)
# Tabs-not-spaces sanity (shfmt NOT installed):
grep -Pn '^    ' scripts/livepicker.sh && echo "FAIL: 4-space indent found, use tabs" || echo "OK: tabs only"
# Confirm the T4.S1/S2 seam was REPLACED (old comment gone, new headers present):
grep -c 'switch key-table + bind keys + suppress hook (insert here)' scripts/livepicker.sh   # expect 0
grep -c 'T4 (P1.M4.T4.S1): build livepicker key table + switch key-table' scripts/livepicker.sh  # expect 1
grep -c 'T4 (P1.M4.T4.S2): suppress session-window-changed hook (insert here)' scripts/livepicker.sh  # expect 1
# Confirm T3 (if landed) + T5 seam + return 0 + driver survived:
grep -n 'T3 (P1.M4.T3.S1)\|T5 (P1.M4.T5.S1' scripts/livepicker.sh   # expect the seam/block headers
grep -nE '^\treturn 0$' scripts/livepicker.sh                       # expect the trailing return 0
grep -n 'activate_main "\$@" || exit 1' scripts/livepicker.sh       # expect the driver
# Confirm NO mode-on / hook / preview / refresh / status leaked into S1:
grep -n 'set-option -g "@livepicker-mode" on\|set_state "$STATE_MODE" "on"' scripts/livepicker.sh \
  && echo "FAIL: S1 must NOT turn mode on" || echo "OK: mode-on deferred to T5"
grep -n 'set-hook\|link-window\|switch-client\|refresh-client\|select-window' scripts/livepicker.sh \
  && echo "FAIL: S1 must not mutate hook/preview/refresh" || echo "OK: S1 is keys-only"
grep -n 'set-option.*status\|status-format' scripts/livepicker.sh \
  && echo "WARN: re-check — S1 must not touch status (T3 owns it; only the shared seam comment mentions key-table)" || echo "OK: status untouched by S1"
# Confirm the copy uses source-file (NOT tmux $line word-split):
grep -n 'source-file' scripts/livepicker.sh && echo "OK: source-file copy" || echo "FAIL: missing source-file"
# Confirm -g on the key-table switch:
grep -n 'set-option -g key-table livepicker' scripts/livepicker.sh && echo "OK: -g switch" || echo "FAIL: must use -g"
# Run from the repo root.
```

### Level 2: Socket-Shim Mock Validation — switch + typing + actions + nav + copy + leak + override, zero live-server impact

Reuses the PATH-wrapper socket shim. Self-cleaning. Sources the REAL
`scripts/{options,utils,state}.sh` and runs the ACTUAL `scripts/livepicker.sh`.
Note: livepicker.sh's guard requires `@livepicker-mode` to be off (it is, on a
fresh socket) and its STEP 2 capture needs an attached client for the
`display-message -p` calls — so the mock attaches a pty client (mirrors the T3
mock's `attach` helper) before invoking the script.

```bash
#!/usr/bin/env bash
# Throwaway socket-shim validation for scripts/livepicker.sh T4.S1 (do NOT commit).
set -u
REPO_ROOT="$(cd "$(dirname "$0")" && pwd)"
[ -f "$REPO_ROOT/scripts/livepicker.sh" ] || { echo "livepicker.sh missing"; exit 1; }
for l in options utils state renderer; do
	[ -f "$REPO_ROOT/scripts/$l.sh" ] || { echo "INPUT dep $l.sh missing"; exit 1; }
done

SOCK="lp-t4s1-mock-$$"
SHIM_DIR="$(mktemp -d)"
cat > "$SHIM_DIR/tmux" <<EOF
#!/usr/bin/env bash
exec /usr/bin/tmux -L "$SOCK" "\$@"
EOF
chmod +x "$SHIM_DIR/tmux"
export PATH="$SHIM_DIR:$PATH"

cleanup() {
	PATH="/usr/bin:/bin:$PATH" tmux -L "$SOCK" kill-server 2>/dev/null || true
	rm -rf "$SHIM_DIR"
}
trap cleanup EXIT

pass=0; fail=0
assert() { if [ "$2" = "$3" ]; then pass=$((pass+1)); printf 'ok   %s\n' "$1"; else fail=$((fail+1)); printf 'FAIL %s: got=[%s] want=[%s]\n' "$1" "$2" "$3"; fi; }
# bound KEY -> grep the livepicker table for a binding whose command contains $2.
# returns 1 (match count) or 0.
bound() { tmux list-keys -T livepicker 2>/dev/null | grep -E -- "bind-key +(-r +)?-T livepicker $1 " | grep -c -- "$2"; }

attach() { TMUX="" script -qec "tmux -L $SOCK attach -t $1" /dev/null >/dev/null 2>&1 & AP=$!; sleep 0.5; }
detach() { kill "$AP" 2>/dev/null; wait "$AP" 2>/dev/null; }
clear_lp() {
	for k in mode list filter index linked-id type orig-session orig-window orig-layout \
	         orig-key-table orig-status orig-renumber-windows orig-session-window-changed \
	         orig-status-format-indices; do tmux set-option -gu "@livepicker-$k" 2>/dev/null; done
}

# ---------- setup: a session + a user prefix binding to prove the copy ----------
tmux new-session -d -s aaa -x 100 -y 24
tmux bind-key -T prefix C-r source-file /tmp/nonexistent.conf   # user binding to copy
tmux bind-key -T prefix Down select-pane -D                      # conflicts w/ nav -> override test
tmux set-option -g "@livepicker-type" "session"

attach aaa
bash "$REPO_ROOT/scripts/livepicker.sh"; rc=$?
detach

# (a) switch
assert "(a) exit 0" "$rc" "0"
assert "(a) key-table switched" "$(tmux show-option -gv key-table)" "livepicker"
# (b) typing (incl. the punct '-' and '/')
assert "(b) typing 'a'"        "$(bound a 'type a')"        "1"
assert "(b) typing '-'"        "$(bound - 'type -')"        "1"
assert "(b) typing '/'"        "$(bound / 'type /')"        "1"
assert "(b) typing '_'"        "$(bound _ 'type _')"        "1"
# (c) actions + nav
assert "(c) BSpace backspace"  "$(bound BSpace backspace)"   "1"
assert "(c) Enter confirm"     "$(bound Enter confirm)"      "1"
assert "(c) Escape cancel"     "$(bound Escape cancel)"      "1"
assert "(c) C-M-Tab next-session"  "$(bound C-M-Tab next-session)"   "1"
assert "(c) C-M-BTab prev-session" "$(bound C-M-BTab prev-session)"  "1"
assert "(c) Down next-session" "$(bound Down next-session)"  "1"
assert "(c) Up prev-session"   "$(bound Up prev-session)"    "1"
assert "(c) j next-session"    "$(bound j next-session)"     "1"
assert "(c) k prev-session"    "$(bound k prev-session)"     "1"
# (d) user binding copied (the WHOLE point of the copy step)
assert "(d) user C-r copied into livepicker" "$(bound C-r source-file)" "1"
# (e) no nav-key leak: the compound swap-window command is NOT in the table
assert "(e) no swap-window leak on C-M-Tab" "$(bound C-M-Tab swap-window)" "0"
# (f) override: Down is next-session, NOT the user's select-pane -D
assert "(f) Down is NOT select-pane (override works)" "$(bound Down 'select-pane -D')" "0"
# path correctness: the type binding points at the real scripts/input-handler.sh
assert "(path) type binding uses abs scripts path" \
  "$(tmux list-keys -T livepicker 2>/dev/null | grep -E "bind-key +(-r +)?-T livepicker a " | grep -c -- "$REPO_ROOT/scripts/input-handler.sh")" "1"

clear_lp
printf '\n==== PASS=%d FAIL=%d ====\n' "$pass" "$fail"
[ "$fail" = "0" ]
# Expected: PASS=21 FAIL=0. Key proofs:
#  - (a) key-table==livepicker (the -g switch took effect).
#  - (b) typing incl. '-'/'/' bound (the flag-like '-' binds with no '--').
#  - (c) all actions + nav bound (incl. the repurposed C-M-Tab/BTab).
#  - (d) the user's C-r prefix binding is present in livepicker (source-file copy).
#  - (e) C-M-Tab has NO swap-window (the skip filter removed the compound binding).
#  - (f) Down is next-session NOT select-pane (copy-first/explicit-last ordering).
#  - (path) the binding uses the absolute scripts/ path ($CURRENT_DIR), so P1.M6's
#    input-handler.sh will be reached.
```

### Level 3: Integration Testing (System Validation)

```bash
# Live spot-check on an ISOLATED socket WITH an attached pty client — confirms the
# switched key-table actually drops an unbound key (Invariant B) and that a bound
# picker key would route to input-handler.sh (we simulate the route with a stub).
# Self-cleaning.
export LP_SOCK="lp-t4s1-live-$$"
REPO_ROOT="$(pwd)"
SHIM_DIR="$(mktemp -d)"
cat > "$SHIM_DIR/tmux" <<EOF
#!/usr/bin/env bash
exec /usr/bin/tmux -L "$LP_SOCK" "\$@"
EOF
chmod +x "$SHIM_DIR/tmux"
trap 'PATH=/usr/bin:/bin:$PATH tmux -L "$LP_SOCK" kill-server 2>/dev/null; rm -rf "$SHIM_DIR"' EXIT
T() { PATH="$SHIM_DIR:$PATH" tmux "$@"; }
T new-session -d -s demo -x 120 -y 40
T set-option -g "@livepicker-type" "session"
# Stub input-handler.sh so we can prove the binding routes to it (P1.M6 not built yet).
mkdir -p "$REPO_ROOT/scripts"
STUB="$REPO_ROOT/scripts/input-handler.sh"
printf '#!/usr/bin/env bash\necho "ROUTED:$1:$2" > /tmp/lp-t4s1-route.log\n' > "$STUB"
chmod +x "$STUB"
TMUX="" script -qec "tmux -L $LP_SOCK attach -t demo" /dev/null >/dev/null 2>&1 &
AP=$!; sleep 0.5
PATH="$SHIM_DIR:$PATH" bash "$REPO_ROOT/scripts/livepicker.sh"; echo "rc=$? (expect 0)"
kill "$AP" 2>/dev/null; wait "$AP" 2>/dev/null
echo "key-table=[$(T show-option -gv key-table)] (expect livepicker)"
echo "livepicker binding count=[$(T list-keys -T livepicker 2>/dev/null | wc -l)]"
# Synthesize a key press by invoking the bound command directly (tmux run-shell via
# the binding is client-driven; we instead confirm the stored command is correct).
echo "stored 'a' binding: [$(T list-keys -T livepicker 2>/dev/null | grep -E 'bind-key +(-r +)?-T livepicker a ' | head -1)]"
rm -f "$STUB" /tmp/lp-t4s1-route.log
# Expected: rc=0; key-table==livepicker; binding count > 100 (copy + explicit); the
# 'a' binding is `run-shell "<abs>/scripts/input-handler.sh type a"`.
```

### Level 4: Creative & Domain-Specific Validation

```bash
# Pollution invariant spot-check (PRD §15.18) for the T4.S1 key-table switch.
# Switching key-table + binding keys must NOT fire client-session-changed (S1 never
# calls switch-client). Run ONLY if @session-history-hist is present on the LIVE
# server; touches ONLY option reads + the @livepicker-* keys + one isolated run of
# livepicker.sh (then cleans up via restore-like teardown: set key-table root +
# unbind the livepicker table).
if tmux show-options -gv "@session-history-hist" >/dev/null 2>&1; then
	REPO_ROOT="$(pwd)"
	BEFORE="$(tmux show-options -gv "@session-history-hist" 2>/dev/null)"
	bash "$REPO_ROOT/scripts/livepicker.sh" 2>/dev/null
	AFTER="$(tmux show-options -gv "@session-history-hist" 2>/dev/null)"
	# teardown (mirror restore): switch back + clear the table + clear picker state
	tmux set-option -g key-table root
	tmux unbind-key -a -T livepicker 2>/dev/null
	for k in mode list filter index linked-id type; do tmux set-option -gu "@livepicker-$k" 2>/dev/null; done
	if [ "$BEFORE" = "$AFTER" ]; then
		echo "OK: @session-history-hist UNCHANGED across T4.S1 key-table switch (Invariant A holds)"
	else
		echo "FAIL: history polluted by T4.S1 (should be impossible — no switch-client)"
	fi
else
	echo "SKIP: tmux-session-history not present on live server (mock §2 covers this structurally)"
fi
# Expected: OK — S1 never calls switch-client, so client-session-changed never fires.

# Manual real-env gate (post-T5, when the picker is fully live): on the REAL tubular
# server, after activation, confirm (1) typing filters the list, (2) Down/Up/j/k and
# C-M-Tab/C-M-BTab move the highlight, (3) Enter lands, Esc dismisses, AND (4) a
# NON-picker prefix binding STILL works during the picker (e.g. the user's C-r
# reload, or window-split) — proving the copy step. This is the end-to-end proof
# that complements the unit-level socket mock; it requires T5 (mode-on) to be live.
```

## Final Validation Checklist

### Technical Validation

- [ ] `bash -n scripts/livepicker.sh` exits 0 with no output.
- [ ] `shellcheck scripts/livepicker.sh` reports 0 findings (file-level disable
      from T1; the S1 word-split loops are SC2086-annotated).
- [ ] No 4-space indents (`grep -Pn '^    '` is empty); tabs only.

### Feature Validation

- [ ] The T4.S1/S2 seam comment is REPLACED by the S1 block + a new S2 seam
      comment; both new headers appear exactly once; the old `(insert here)`
      comment is gone.
- [ ] T3's block (if landed), the T5 seam comment, `return 0`, and the trailing
      driver are UNCHANGED.
- [ ] Copy: `mktemp` + `{ list-keys -T prefix|root | sed }` piped through
      `grep -vE` (skip next/prev) into the file + `tmux source-file` + `rm -f`.
      NO `tmux $line` word-split.
- [ ] Typing loop: `{a..z} {A..Z} {0..9} - _ . /` → `run-shell
      "$CURRENT_DIR/input-handler.sh type $lp_c"`.
- [ ] Action loops: backspace/confirm/cancel from the `opt_*` space-lists.
- [ ] Nav loops: `opt_next_key`+`opt_nav_next_keys` → next-session;
      `opt_prev_key`+`opt_nav_prev_keys` → prev-session.
- [ ] Switch: `tmux set-option -g key-table livepicker` (WITH `-g`).
- [ ] ORDER: copy → explicit binds → switch.
- [ ] **NO** set-hook/hook suppression (S2); **NO** link-window/switch-client/
      refresh-client/select-window (T5); **NO** `@livepicker-mode on` (T5);
      **NO** status mutation (T3).
- [ ] Mock (a) key-table==livepicker; (b) typing `a`/`-`/`/`/`_` bound; (c) all
      actions + nav bound; (d) user C-r copied; (e) no swap-window leak; (f)
      Down is next-session not select-pane (override); (path) abs scripts path.

### Code Quality Validation

- [ ] NO `set -e`, NO `set -o pipefail` (house style; system_context §9).
- [ ] All expansions double-quoted (`"$lp_c"`, `"$lp_tf"`, `"$CURRENT_DIR/..."`,
      `"$(opt_next_key)"`); the only unquoted expansions are the intentional
      SC2086-annotated word-split loops over the space-list accessors.
- [ ] Copy uses `source-file` (tmux's parser), never `tmux $line`.
- [ ] Locals distinct from T2's and T3's; none shadow bash builtins.
- [ ] No new files created; no other source file touched.

### Documentation & Deployment

- [ ] Block header comment states: PRD §8 Binding + §6 step 4; Invariant B
      (modal table, drops unbound keys); the 3-step order + WHY copy-first;
      the source-file rationale (FINDING 1); the `-g` switch rationale
      (FINDING 3); discovery intentionally omitted (defaults suffice).
- [ ] New S2 seam comment left directly below the block (so S2 inserts cleanly).
- [ ] No README/doc file created (DOCS = Mode A; covered by README P1.M8.T1.S1).
- [ ] No tmux.conf edit; no tests/ dir committed.

---

## Anti-Patterns to Avoid

- ❌ Don't copy bindings with `tmux $line` (word-split). Tubular's `display-menu`
  binding has braces/nested quotes/`\;` — word-splitting yields
  `set-buffer: too many arguments` and the binding is silently dropped. Use
  `tmux source-file "$tmpfile"` so tmux's OWN parser re-binds each line
  (research FINDING 1).
- ❌ Don't bind explicit keys BEFORE the copy. The user's prefix/root tables bind
  `Down`/`Up`/`Enter`/`a`; a copy that runs AFTER the explicit binds OVERWRITES
  the picker keys and nav breaks. Copy FIRST, explicit LAST, switch LAST
  (research FINDING 2 — verified 14/14 with this order, 7 failures with the
  reverse). The skip of next/prev keys is NECESSARY but NOT SUFFICIENT.
- ❌ Don't drop the `-g` from `set-option -g key-table livepicker`. The no-`g`
  form sets the session-scoped value but `show-option -gv key-table` still reads
  `root` (the switch appears to no-op). `-g` also matches the global save/restore
  contract (`ORIG_KEY_TABLE`). The standalone `tmux key-table` command is
  `unknown command` on 3.6b (research FINDING 3).
- ❌ Don't implement discovery. PRD §8 makes it OPTIONAL/best-effort and forbids
  it from overriding explicit options. The defaults (`C-M-Tab`/`C-M-BTab`) match
  this user's root-table window-nav keys (system_context §2), so the feature
  works out of the box. Discovery adds complexity + risk for zero gain here.
- ❌ Don't suppress the hook, run a preview, set `@livepicker-mode on`, or touch
  status. S1 owns ONLY the key-table (bind + copy + switch). Hook = S2; preview
  + mode-on + refresh = T5; status = T3. Crossing these boundaries creates
  double-work and torn state across the parallel seams.
- ❌ Don't remove the T4 seam comment without leaving a new S2 seam. S1 owns the
  bind+switch half; S2 owns the hook-suppress half. Replace the shared
  `T4 (P1.M4.T4.S1/S2)` comment with the S1 block + a new
  `T4 (P1.M4.T4.S2): suppress session-window-changed hook (insert here)` comment
  so S2 inserts cleanly.
- ❌ Don't use `$SCRIPT_DIR` for the input-handler path. The in-file global is
  `CURRENT_DIR` (the scripts/ dir), already used by T3 for `$CURRENT_DIR/
  renderer.sh`. The path is `$CURRENT_DIR/input-handler.sh` (research FINDING 6).
- ❌ Don't add `set -e`. `tmux list-keys -T <table>` returns non-zero on an empty
  table (first activation) and `grep -vE` returns 1 on no-match; under `set -e`
  the copy pipeline would abort mid-activate. House style is `set -u` only
  (system_context §9).
