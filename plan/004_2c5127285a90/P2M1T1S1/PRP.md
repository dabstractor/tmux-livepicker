# PRP — P2.M1.T1.S1: Add 4 window-cursor state keys to state.sh + init at activate

---

## Goal

**Feature Goal**: Define 4 new runtime state keys (`STATE_CAND_WIN_SESSION`,
`STATE_CAND_WIN_LIST`, `STATE_CAND_WIN_CURSOR`, `STATE_PREVIEW_WIN_ID`) in
`scripts/state.sh`, append them to `_STATE_RUNTIME_KEYS` so `clear_all_state`
tears them down (PRD §9 step 6 directive), and **initialize** them at activate in
`scripts/livepicker.sh::activate_main` T2 (immediately after the
`STATE_LIST`/`STATE_FILTER`/`STATE_INDEX` writes). This is a **no-behavior-change
scaffolding** task: the keys are read only by P2.M1.T2 (preview chosen window) and
P2.M1.T3 (next-window/prev-window flip actions), both of which land later. They
sit idle until then and are cleared on exit.

**Deliverable**: Edits to TWO existing files (NO new file):
1. `scripts/state.sh` — 4 new `readonly STATE_*` constants + 4 entries appended
   to `_STATE_RUNTIME_KEYS`.
2. `scripts/livepicker.sh` — 4 `set_state` inits + a comment, inserted in the T2
   block after `set_state "$STATE_INDEX" "$idx"`.

**Success Definition**:
- `bash -n`/`shellcheck` clean on both scripts.
- After activate on an isolated socket:
  - `@livepicker-cand-win-session` == the current (driver) session name;
  - `@livepicker-cand-win-list` == `""`; `@livepicker-cand-win-cursor` == `0`;
  - `@livepicker-preview-win-id` == `""`.
- After cancel/confirm (restore → `clear_all_state`), all 4 are **unset**
  (the `_STATE_RUNTIME_KEYS` append wires teardown).
- `tests/run.sh` stays GREEN (no existing test regresses — no test asserts the
  state-key set).

## User Persona (if applicable)

**Target User**: Future work items (P2.M1.T2/T3, P2.M2.T1) — this is internal
state infrastructure with NO user-facing surface (DOCS = none).

**Use Case**: When the user (post-P2.M1.T3) flips the previewed session's windows
with the window-axis keys, the cursor tracks which window is shown; confirm (post-
P2.M2.T1) lands on `(session, window)`. This task only lays the state seams those
features read/write.

**User Journey**: N/A (no user-visible change this task).

**Pain Points Addressed**: Provides the cache-invalidation key + window list +
cursor index + shown-window id that the two-axis window-picking feature needs, so
later tasks have stable, teardown-safe state to build on.

## Why

- **PRD §9** mandates the 4 runtime keys + explicitly directs "add them to
  `_STATE_RUNTIME_KEYS` in `state.sh`" for teardown (§9 restore step 6).
- **PRD §5/§8** (two-axis architecture): the window axis needs a per-candidate
  window cursor + the id of the window currently previewed. The state must exist
  before the actions that read it (P2.M1.T3) and the preview that consumes it
  (P2.M1.T2).
- **Decoupling**: defining state + init now (no behavior change) lets P2.M1.T2/T3
  focus purely on logic, with stable keys already wired to teardown. This is the
  standard "state seam first" ordering the codebase uses (e.g. STATE_SCROLL/
  STATE_CLIENT_WIDTH were added before their consumers).
- **Invariant safe**: adding 4 runtime keys to `_STATE_RUNTIME_KEYS` does not
  affect the §11-config-preservation invariant (CORRECTION A) — these are runtime,
  not config. STATE_LINKED_ID is KEPT (distinct handle role; only overlaps the new
  STATE_PREVIEW_WIN_ID for non-self candidates).

## What

1. **state.sh** — add 4 `readonly STATE_*` constants (contiguous with the runtime
   block, after `STATE_RENDER_CACHE`) and append the 4 names to
   `_STATE_RUNTIME_KEYS`.
2. **livepicker.sh** — in `activate_main` T2, after `set_state "$STATE_INDEX"`
   `"$idx"`, write the 4 inits: SESSION ← `ORIG_SESSION` (the current session),
   LIST ← `""`, CURSOR ← `"0"`, PREVIEW_WIN_ID ← `""`.

### Success Criteria

- [ ] 4 `readonly` constants exist in `scripts/state.sh` with the exact
      `@livepicker-*` names (cand-win-session/list/cursor, preview-win-id).
- [ ] `_STATE_RUNTIME_KEYS` includes all 4 (grep: 4 names present on that line).
- [ ] livepicker.sh T2 writes the 4 inits (session=ORIG_SESSION, list='', cursor='0',
      preview-win-id='') after the `STATE_INDEX` write, before the T2b block.
- [ ] No `ORIG_*` keys added (these are runtime, not saved-state).
- [ ] STATE_LINKED_ID is UNTOUCHED (distinct handle role preserved).
- [ ] After activate the 4 keys hold their init values; after restore they are unset.
- [ ] `tests/run.sh` stays green; `bash -n`/`shellcheck` clean.

## All Needed Context

### Context Completeness Check

_Pass_: A developer who has never seen this repo can implement both edits from
(a) the exact edit anchors below (verbatim oldText/newText), (b) the 10 findings in
`research/findings.md` — most critically **FINDING 1** (state.sh layout: runtime
block lines 40-52, `_STATE_RUNTIME_KEYS` line 68), **FINDING 4** (the exact
`_STATE_RUNTIME_KEYS` append), **FINDING 5** (the activate T2 init site at line
239 + the load-bearing "use ORIG_SESSION not the `current` var" rule), and
**FINDING 6** (no conflict with the parallel P1.M2.T1.S1 T4 rework). No external
library knowledge needed beyond the shipped `set_state`/`get_state` accessors.

### Documentation & References

```yaml
# MUST READ — the file you EDIT #1 (state keys + teardown list).
- file: scripts/state.sh
  why: runtime keys block (40-52; LAST is STATE_RENDER_CACHE line 52); saved-state
       block (54-63) headed by "# --- saved-state CONTRACT keys ..."; _STATE_RUNTIME_KEYS
       (line 68) — the space-list clear_all_state iterates (line 153). set_state/get_state
       accessors (71/76). File-wide `# shellcheck disable=SC2034` (seam constants).
  pattern: "readonly STATE_<NAME>=\"@livepicker-<name>\"  # comment ... Cleared via _STATE_RUNTIME_KEYS"
  gotcha: the 4 keys are RUNTIME (place contiguous with STATE_RENDER_CACHE), NOT ORIG_*.
          Append the readonly NAMES (not @-strings) to _STATE_RUNTIME_KEYS, single-space separated.

# MUST READ — the file you EDIT #2 (activate init site).
- file: scripts/livepicker.sh
  why: activate_main T2 block. Lines 237-239 write STATE_LIST/STATE_FILTER/STATE_INDEX;
       line 240 is the T2b comment. INSERT the 4 inits BETWEEN line 239 and 240. ORIG_SESSION
       (saved STEP 2, line 173) holds the stable current session name. Sources state.sh ->
       set_state/get_state/STATE_*/ORIG_* all in scope.
  pattern: the existing init idiom — `set_state "$STATE_FILTER" ""` / `set_state "$STATE_LINKED_ID" ""`.
  gotcha: use `$(get_state "$ORIG_SESSION" "")` for the session name, NOT the `current` var
          (which is reassigned to a session:window_index TOKEN in window mode at line 219).
          TAB indentation (the file is tab-indented; a space oldText won't match).

# MUST READ — why STATE_PREVIEW_WIN_ID vs STATE_LINKED_ID (keep BOTH).
- file: scripts/preview.sh
  why: preview_main reads/sets STATE_LINKED_ID (line 88 read, 187/230-ish set); the
       self-session path NEVER sets linked-id (stays empty — line 190 init at activate).
       STATE_PREVIEW_WIN_ID is the LOGICAL shown-window (overlaps linked-id for non-self,
       diverges for self). This task only DEFINES+INITS preview-win-id to ''; the overlap
       logic is P2.M1.T2/T3. preview.sh is NOT edited here.
  critical: DO NOT replace STATE_LINKED_ID with STATE_PREVIEW_WIN_ID; they have distinct roles.

# MUST READ — the gap analysis (§Gap c names the exact keys + the teardown leak this fixes).
- docfile: plan/004_2c5127285a90/architecture/gap_analysis_two_axis.md
  why: §Gap (c) "Window-cursor state" — state.sh:40-68 has none of the 4 keys; they are not
       in _STATE_RUNTIME_KEYS so would leak past teardown. This task adds them + wires teardown.
  section: "Gap (c): Window-cursor state", "Files needing change" (item 4)

# MUST READ — the parallel task contract (confirm disjoint edit regions).
- docfile: plan/004_2c5127285a90/P1M2T1S1/PRP.md
  why: P1.M2.T1.S1 (in parallel) reworks the T4 KEY-BINDING block (livepicker.sh ~336-446).
       It does NOT touch state.sh, and its livepicker.sh edits start at the T4 "Discovery
       OMITTED" comment (~355) — DISJOINT from this task's T2 init site (237-239). No overlap.
  critical: do NOT edit the T4 block; your edit is confined to the T2 init (line 239 -> 240).

# MUST READ — PRD §9 (the runtime-state list + the teardown directive this implements).
- docfile: PRD.md
  why: §9 "State saved and restored" runtime-state paragraph names all 4 keys verbatim;
       restore step 6 explicitly says "add them to _STATE_RUNTIME_KEYS in state.sh". §5/§3.2
       data flow shows the cursor init ("window-cursor = current session's active window").
  section: "§9 State saved and restored" (runtime-state list + restore step 6), "§5 Architecture / Data flow"

# MUST READ — the ground-truth findings for THIS task (10 findings).
- docfile: plan/004_2c5127285a90/P2M1T1S1/research/findings.md
  why: FINDING 1 (state.sh layout + anchors); FINDING 2 (4 keys verbatim); FINDING 3
       (preview-win-id vs linked-id — keep both); FINDING 4 (the _STATE_RUNTIME_KEYS append);
       FINDING 5 (activate T2 site + ORIG_SESSION rule); FINDING 6 (no conflict w/ P1.M2.T1.S1);
       FINDING 7 (no test asserts state-key set); FINDING 8 (set_state/get_state contract);
       FINDING 9 (PRD §9 step 6 directive); FINDING 10 (validation approach).
  critical: FINDING 5's ORIG_SESSION rule + FINDING 6's disjoint-region confirmation are the
            two things most likely to be mis-done. Read BEFORE editing.
```

### Current Codebase tree

```bash
tmux-livepicker/
  scripts/
    state.sh        # MODIFY: +4 readonly STATE_* runtime keys; +4 entries in _STATE_RUNTIME_KEYS.
    livepicker.sh   # MODIFY: +4 set_state inits in activate_main T2 (after STATE_INDEX, before T2b).
    options.sh utils.sh rank.sh layout.sh renderer.sh input-handler.sh preview.sh restore.sh session-mgmt.sh  # UNCHANGED
  tests/
    *.sh            # UNCHANGED (no test asserts the state-key set; the window-flip suite is P2.M3.T1.S1).
  plan/004_2c5127285a90/{architecture/gap_analysis_two_axis.md, P2M1T1S1/{PRP.md, research/findings.md}, P1M2T1S1/PRP.md}
```

### Desired Codebase tree with files to be added and responsibility of file

```bash
scripts/state.sh        # +STATE_CAND_WIN_SESSION (cache-invalidation key)
                        # +STATE_CAND_WIN_LIST    (ordered window ids of the candidate)
                        # +STATE_CAND_WIN_CURSOR  (index; defaults to active window on entry)
                        # +STATE_PREVIEW_WIN_ID   (window shown; overlaps STATE_LINKED_ID for non-self)
                        #   — appended to _STATE_RUNTIME_KEYS (teardown wired).
scripts/livepicker.sh   # activate T2: init the 4 keys (session=ORIG_SESSION, list='', cursor='0', preview-win-id='').
```

### Known Gotchas of our codebase & Library Quirks

```bash
# CRITICAL (FINDING 5): init STATE_CAND_WIN_SESSION from ORIG_SESSION, NOT the `current`
# local. `current` is reassigned to a session:window_index TOKEN in window mode (line 219).
# ORIG_SESSION (saved STEP 2, line 173) is the stable client-independent session name.
#   set_state "$STATE_CAND_WIN_SESSION" "$(get_state "$ORIG_SESSION" "")"

# CRITICAL (FINDING 1): the 4 keys are RUNTIME keys, NOT ORIG_* saved-state. Place them
# contiguous with the runtime block (after STATE_RENDER_CACHE, before the saved-state
# "# --- saved-state CONTRACT keys" comment). Do NOT put them among the ORIG_* keys.

# CRITICAL (FINDING 4): append the readonly NAME symbols ($STATE_CAND_WIN_*) to
# _STATE_RUNTIME_KEYS, NOT the @-strings. Single-space separators, mirroring the existing
# entries. Without this, clear_all_state does NOT tear them down -> leak (gap_analysis §c).

# CRITICAL (FINDING 3): KEEP STATE_LINKED_ID. Do NOT replace it with STATE_PREVIEW_WIN_ID.
# They have distinct roles (handle vs logical shown-window) and diverge for the self-session.

# GOTCHA (FINDING 8): set_state "" is a SET-EMPTY (tmux set-option -g @x ""), NOT unset.
# Mirror the existing `set_state "$STATE_FILTER" ""` / `set_state "$STATE_LINKED_ID" ""`
# at activate. Do NOT use tmux_unset_opt/-gu for init.

# GOTCHA (FINDING 6): the parallel P1.M2.T1.S1 edits the T4 block (lines 336+). Your edit
# is in T2 (lines 237-239) + state.sh. NO overlap. Anchor on `set_state "$STATE_INDEX" "$idx"`
# + the T2b comment — stable, untouched by the T4 rework.

# GOTCHA (indentation): BOTH files use TAB indentation. The livepicker.sh edit oldText/newText
# must use a leading TAB (the body of activate_main). Verify: `grep -Pn '^    ' scripts/livepicker.sh`
# shows no 4-space indent on your new lines.

# GOTCHA (set -u): every `readonly` is assigned at definition; `get_state` takes a default
# arg. The new keys inherit the file-wide SC2034 disable (integration-seam constants).
```

## Implementation Blueprint

### Data models and structure

No data model beyond the 4 readonly string constants + their `@livepicker-*` tmux-
option names. They are the window-axis state seam:

| Constant | @livepicker-* | Init value (activate T2) | Consumer |
|----------|---------------|--------------------------|----------|
| `STATE_CAND_WIN_SESSION` | `@livepicker-cand-win-session` | `$(get_state "$ORIG_SESSION" "")` (current session) | P2.M1.T3 (cache invalidation) |
| `STATE_CAND_WIN_LIST` | `@livepicker-cand-win-list` | `""` (lazy-derived on first flip) | P2.M1.T3 (the window list) |
| `STATE_CAND_WIN_CURSOR` | `@livepicker-cand-win-cursor` | `"0"` (active window on entry) | P2.M1.T3 (advance/wrap) |
| `STATE_PREVIEW_WIN_ID` | `@livepicker-preview-win-id` | `""` (no window shown yet) | P2.M1.T2 (preview chosen window) |

All 4 are appended to `_STATE_RUNTIME_KEYS` → cleared by `clear_all_state` on exit.

### Implementation Tasks (ordered by dependencies)

```yaml
Task 1: EDIT scripts/state.sh — add 4 readonly runtime-key constants
  - FILE: ./scripts/state.sh (EXISTING; sourced lib).
  - PLACEMENT: contiguous with the runtime block, immediately AFTER the
    STATE_RENDER_CACHE line (line 52) and BEFORE the blank line + "# --- saved-state
    CONTRACT keys" comment (line 53-54). Keep them as RUNTIME keys (NOT among ORIG_*).
  - ADD (verbatim):
      readonly STATE_CAND_WIN_SESSION="@livepicker-cand-win-session"  # cache-invalidation key: the candidate session the cached window-list belongs to (PRD §9; read by P2.M1.T3 flip actions to decide whether to re-derive the list); init = current session at activate; cleared via _STATE_RUNTIME_KEYS
      readonly STATE_CAND_WIN_LIST="@livepicker-cand-win-list"        # newline-joined ordered window ids of STATE_CAND_WIN_SESSION's candidate; derived lazily on first window flip (P2.M1.T3); init '' at activate; cleared via _STATE_RUNTIME_KEYS
      readonly STATE_CAND_WIN_CURSOR="@livepicker-cand-win-cursor"    # 0-based index into STATE_CAND_WIN_LIST; defaults to the candidate's ACTIVE window on entry (PRD §9); advanced/wrapped by P2.M1.T3 next/prev-window; init '0' at activate; cleared via _STATE_RUNTIME_KEYS
      readonly STATE_PREVIEW_WIN_ID="@livepicker-preview-win-id"      # the window currently shown; OVERLAPS STATE_LINKED_ID for non-self candidates, DIVERGES for the self-session (linked-id empty there); set by P2.M1.T2 preview; init '' at activate; cleared via _STATE_RUNTIME_KEYS
  - NAMING: STATE_CAND_WIN_SESSION / _LIST / _CURSOR / STATE_PREVIEW_WIN_ID (PRD §9 verbatim).
  - STYLE: column-0 (matches the runtime block); trailing "Cleared via _STATE_RUNTIME_KEYS".

Task 2: EDIT scripts/state.sh — append the 4 to _STATE_RUNTIME_KEYS
  - FILE: ./scripts/state.sh (EXISTING).
  - oldText (line 68, verbatim):
      readonly _STATE_RUNTIME_KEYS="$STATE_MODE $STATE_LIST $STATE_FILTER $STATE_INDEX $STATE_LINKED_ID $STATE_TAB_CURRENT_TMPL $STATE_TAB_INACTIVE_TMPL $STATE_PREVIEW_SEQ $STATE_PREVIEW_TARGET $STATE_SCROLL $STATE_CLIENT_WIDTH $STATE_RENDER_CACHE"
  - newText: append (single-space separated, name symbols not @-strings):
      ... $STATE_RENDER_CACHE $STATE_CAND_WIN_SESSION $STATE_CAND_WIN_LIST $STATE_CAND_WIN_CURSOR $STATE_PREVIEW_WIN_ID"
  - GOTCHA: the 4 new entries MUST use the readonly NAME symbols ($STATE_CAND_WIN_*),
    not the @-strings, so clear_all_state's `set-option -gu "$k"` resolves them.

Task 3: EDIT scripts/livepicker.sh — init the 4 keys in activate_main T2
  - FILE: ./scripts/livepicker.sh (EXISTING; entry point).
  - PLACEMENT: in activate_main T2, AFTER `set_state "$STATE_INDEX" "$idx"` (line 239)
    and BEFORE the `# --- T2b (P1.M3.T1.S1): client-width cache ...` comment (line 240).
  - oldText (the 3 sibling inits + the T2b comment; TAB-indented):
      \tset_state "$STATE_LIST" "$list"
      \tset_state "$STATE_FILTER" ""
      \tset_state "$STATE_INDEX" "$idx"
      \t# --- T2b (P1.M3.T1.S1): client-width cache + client-resized hook (PRD §10 step 5 / §3.35).
  - newText: insert the 4 inits (+ comment) between the INDEX write and the T2b comment:
      \tset_state "$STATE_LIST" "$list"
      \tset_state "$STATE_FILTER" ""
      \tset_state "$STATE_INDEX" "$idx"
      \t# --- P2.M1.T1.S1: window-cursor state keys init (PRD §9 runtime-state / §8 window axis). No
      \t# behavior change — the keys are read by P2.M1.T2 (preview chosen window) + P2.M1.T3
      \t# (next/prev-window flip), both inert until then. CAND_WIN_SESSION = the session the
      \t# cached window-list belongs to (cache-invalidation key; init = current session, matching
      \t# the initial highlight at $idx). LIST = '' (derived lazily on first flip). CURSOR = '0'
      \t# (defaults to the candidate's active window on entry). PREVIEW_WIN_ID = '' (no window
      \t# shown yet; overlaps STATE_LINKED_ID for non-self, diverges for self). Use ORIG_SESSION
      \t# (NOT the `current` var, which is a session:window token in window mode) for the name.
      \tset_state "$STATE_CAND_WIN_SESSION" "$(get_state "$ORIG_SESSION" "")"
      \tset_state "$STATE_CAND_WIN_LIST" ""
      \tset_state "$STATE_CAND_WIN_CURSOR" "0"
      \tset_state "$STATE_PREVIEW_WIN_ID" ""
      \t# --- T2b (P1.M3.T1.S1): client-width cache + client-resized hook (PRD §10 step 5 / §3.35).
  - DEPENDENCIES: STATE_* constants from Task 1; ORIG_SESSION (saved STEP 2); set_state/get_state
    from state.sh (already sourced at the top of livepicker.sh).
  - GOTCHA: this is a NO-BEHAVIOR-CHANGE init. Do NOT add flip/preview logic (P2.M1.T2/T3).

Task 4: VALIDATE (L1 grep + L2 suite + L3 activate/teardown cycle)
  - RUN: bash -n scripts/state.sh scripts/livepicker.sh ; shellcheck both.
  - RUN: grep cross-checks (4 constants + 4 _STATE_RUNTIME_KEYS entries + 4 activate inits present).
  - RUN: tests/run.sh (expect GREEN — no regression).
  - RUN: L3 isolated-socket activate/teardown spot-check (assert init values + unset after cancel).
```

### Implementation Patterns & Key Details

```bash
# === state.sh: the 4 readonly constants (Task 1) — contiguous with the runtime block ===
# Pattern = the existing runtime-key idiom: readonly STATE_<NAME>="@livepicker-<name>"
# + a trailing "Cleared via _STATE_RUNTIME_KEYS" comment. Column-0. Match the block's style.
readonly STATE_CAND_WIN_SESSION="@livepicker-cand-win-session"
readonly STATE_CAND_WIN_LIST="@livepicker-cand-win-list"
readonly STATE_CAND_WIN_CURSOR="@livepicker-cand-win-cursor"
readonly STATE_PREVIEW_WIN_ID="@livepicker-preview-win-id"

# === state.sh: the _STATE_RUNTIME_KEYS append (Task 2) ===
# Append the NAME SYMBOLS (not @-strings), single-space separated. clear_all_state does
# `for k in $_STATE_RUNTIME_KEYS; do tmux set-option -gu "$k"; done` — $k must resolve to
# the @livepicker-* string the readonly holds.
readonly _STATE_RUNTIME_KEYS="$STATE_MODE ... $STATE_RENDER_CACHE $STATE_CAND_WIN_SESSION $STATE_CAND_WIN_LIST $STATE_CAND_WIN_CURSOR $STATE_PREVIEW_WIN_ID"

# === livepicker.sh: the 4 inits (Task 3) — TAB-indented, in activate_main T2 ===
# CRITICAL: ORIG_SESSION (NOT the `current` var) for the session name.
	set_state "$STATE_CAND_WIN_SESSION" "$(get_state "$ORIG_SESSION" "")"
	set_state "$STATE_CAND_WIN_LIST" ""
	set_state "$STATE_CAND_WIN_CURSOR" "0"
	set_state "$STATE_PREVIEW_WIN_ID" ""
# set_state "" = SET-EMPTY (tmux set-option -g @x ""), NOT unset — mirrors the existing
# set_state "$STATE_FILTER" "" / set_state "$STATE_LINKED_ID" "" at activate.

# === Why this is safe + inert ===
# Nothing reads the 4 keys today (P2.M1.T2/T3 are the consumers). They are written at
# activate and cleared at restore (via the _STATE_RUNTIME_KEYS append). The §11-config-
# preservation invariant (CORRECTION A) is unaffected — these are runtime keys, not config.
```

### Integration Points

```yaml
STATE (state.sh):
  - +4 readonly STATE_* runtime constants; +4 entries in _STATE_RUNTIME_KEYS.
  - No ORIG_* changes (these are runtime, not saved-state).
  - STATE_LINKED_ID UNCHANGED (distinct handle role; keep BOTH).

ACTIVATE (livepicker.sh activate_main T2):
  - +4 set_state inits after STATE_INDEX, before T2b.
  - No change to T4 (the parallel P1.M2.T1.S1 owns T4) / T3 / T5 / STEP-2 save.

TEARDOWN (restore.sh → clear_all_state):
  - NO CODE CHANGE. clear_all_state iterates _STATE_RUNTIME_KEYS; appending the 4 keys
    auto-wires their teardown. (PRD §9 step 6 directive satisfied.)

CONSUMERS (FUTURE — do not implement here):
  - P2.M1.T2 (preview.sh): reads STATE_PREVIEW_WIN_ID / chosen window.
  - P2.M1.T3 (input-handler.sh): next-window/prev-window read/advance STATE_CAND_WIN_*.
  - P2.M2.T1 (confirm): resolves (session, window) from STATE_CAND_WIN_CURSOR.

CONFIG / DATABASE / ROUTES: none.
```

## Validation Loop

### Level 1: Syntax & Style (Immediate Feedback)

```bash
cd /home/dustin/.config/tmux/plugins/tmux-livepicker
bash -n scripts/state.sh scripts/livepicker.sh && echo "OK: syntax"           # expect exit 0
shellcheck scripts/state.sh scripts/livepicker.sh                              # expect 0 findings (SC2034 covers state.sh)
# The 4 constants exist (each exactly once):
for k in STATE_CAND_WIN_SESSION STATE_CAND_WIN_LIST STATE_CAND_WIN_CURSOR STATE_PREVIEW_WIN_ID; do
  n=$(grep -c "readonly $k=" scripts/state.sh); [ "$n" -eq 1 ] && echo "OK: $k" || echo "FAIL: $k ($n)"
done
# _STATE_RUNTIME_KEYS includes all 4 (name symbols):
for k in STATE_CAND_WIN_SESSION STATE_CAND_WIN_LIST STATE_CAND_WIN_CURSOR STATE_PREVIEW_WIN_ID; do
  grep -q "\\\$$k" scripts/state.sh && echo "OK: \$$k in _STATE_RUNTIME_KEYS" || echo "FAIL: \$$k missing"
done
# The 4 activate inits exist (each exactly once):
grep -c 'set_state "$STATE_CAND_WIN_SESSION" "$(get_state "$ORIG_SESSION" "")"' scripts/livepicker.sh  # == 1
grep -c 'set_state "$STATE_CAND_WIN_LIST" ""'        scripts/livepicker.sh  # == 1
grep -c 'set_state "$STATE_CAND_WIN_CURSOR" "0"'     scripts/livepicker.sh  # == 1
grep -c 'set_state "$STATE_PREVIEW_WIN_ID" ""'       scripts/livepicker.sh  # == 1
# No 4-space indent on the new lines (tabs only):
grep -Pn '^    [^#/]' scripts/livepicker.sh | tail -20 && echo "WARN: space-indent" || echo "OK: tabs"
# Expected: all OK; each grep count == 1; tabs only.
```

### Level 2: Full suite (no regression)

```bash
cd /home/dustin/.config/tmux/plugins/tmux-livepicker
tests/run.sh
# Expected: exit 0, all green. No test asserts the state-key set, so the 4 new keys +
# their teardown cannot regress anything. (If the suite was red from the parallel
# P1.M2.T1.S1 broken-intermediate state, that task fixes it; this task is independent.)
```

### Level 3: Activate/teardown cycle (init values + unset after cancel)

```bash
cat > /tmp/smoke_cursor.sh <<'EOF'
#!/usr/bin/env bash
set -u
cd /home/dustin/.config/tmux/plugins/tmux-livepicker
source tests/setup_socket.sh; source tests/helpers.sh
setup_test "lp-cursor"; attach_test_client
fail=0

# name the driver so we can assert CAND_WIN_SESSION against it
drv="$(tmux display-message -p '#{session_name}')"
"$LIVEPICKER_SCRIPTS/livepicker.sh"                       # activate -> T2 inits the 4 keys

a="$(tmux show-option -gqv @livepicker-cand-win-session)"
b="$(tmux show-option -gqv @livepicker-cand-win-list)"
c="$(tmux show-option -gqv @livepicker-cand-win-cursor)"
d="$(tmux show-option -gqv @livepicker-preview-win-id)"
[ "$a" = "$drv" ] && echo "OK: cand-win-session=$a" || { echo "FAIL: session [$a] != [$drv]"; fail=1; }
[ -z "$b" ]         && echo "OK: cand-win-list empty" || { echo "FAIL: list [$b]"; fail=1; }
[ "$c" = "0" ]      && echo "OK: cursor=0" || { echo "FAIL: cursor [$c]"; fail=1; }
[ -z "$d" ]         && echo "OK: preview-win-id empty" || { echo "FAIL: preview-win-id [$d]"; fail=1; }

"$LIVEPICKER_SCRIPTS/input-handler.sh" cancel >/dev/null 2>&1 || true   # restore -> clear_all_state
# teardown: all 4 must be UNSET (show-option -gqv returns "" for an unset @-option)
for k in @livepicker-cand-win-session @livepicker-cand-win-list @livepicker-cand-win-cursor @livepicker-preview-win-id; do
  v="$(tmux show-option -gqv "$k")"
  [ -z "$v" ] && echo "OK: $k unset after teardown" || { echo "FAIL: $k leaked [$v]"; fail=1; }
done
teardown_test
[ "$fail" -eq 0 ]
EOF
bash /tmp/smoke_cursor.sh; rc=$?; rm -f /tmp/smoke_cursor.sh; exit $rc
# Expected: all OK. Proves the 4 keys are initialized at activate AND torn down on cancel
# (the _STATE_RUNTIME_KEYS append wired teardown). The isolated socket sources the user conf,
# so display-message '#{session_name}' is the driver name ORIG_SESSION also captured.
```

### Level 4: No-behavior-change confirmation

```bash
cd /home/dustin/.config/tmux/plugins/tmux-livepicker
# The 4 keys are inert: nothing reads them today. Prove the picker still behaves identically
# (activate -> nav -> cancel) with the new keys present. Reuse the smoke harness from L3 but
# also drive a next-session + confirm the index moves + the new keys are untouched by nav
# (P2.M1.T3 will be the first to MUTATE cand-win-cursor on flip; nav does not touch it yet).
cat > /tmp/smoke_inert.sh <<'EOF'
#!/usr/bin/env bash
set -u
cd /home/dustin/.config/tmux/plugins/tmux-livepicker
source tests/setup_socket.sh; source tests/helpers.sh
setup_test "lp-inert-cursor"; attach_test_client
tmux new-session -d -s other -x 120 -y 40     # a second session to navigate to
"$LIVEPICKER_SCRIPTS/livepicker.sh"
cur0="$(tmux show-option -gqv @livepicker-cand-win-cursor)"
"$LIVEPICKER_SCRIPTS/input-handler.sh" next-session >/dev/null 2>&1 || true
idx="$(tmux show-option -gqv @livepicker-index)"
cur1="$(tmux show-option -gqv @livepicker-cand-win-cursor)"
echo "index after next-session: [$idx] ; cursor unchanged: [$cur0]->[$cur1]"
[ "$cur0" = "$cur1" ] && echo "OK: cursor inert under session-nav (P2.M1.T3 owns it)" || echo "WARN: cursor moved under nav"
"$LIVEPICKER_SCRIPTS/input-handler.sh" cancel >/dev/null 2>&1 || true
teardown_test
EOF
bash /tmp/smoke_inert.sh; rc=$?; rm -f /tmp/smoke_inert.sh; exit $rc
# Expected: index advances on next-session (unchanged behavior); cand-win-cursor stays '0'
# (inert — nothing reads/mutates it until P2.M1.T3). Proves no behavior change.
```

## Final Validation Checklist

### Technical Validation

- [ ] `bash -n` + `shellcheck` clean on `scripts/state.sh` + `scripts/livepicker.sh`.
- [ ] 4 `readonly STATE_*` constants present (each exactly once) in state.sh.
- [ ] `_STATE_RUNTIME_KEYS` includes all 4 name symbols; tabs only (no 4-space indent).

### Feature Validation

- [ ] Activate sets: cand-win-session == driver session; cand-win-list == '';
      cand-win-cursor == '0'; preview-win-id == '' (L3).
- [ ] Cancel/restore UNSETS all 4 (clear_all_state teardown wired — L3).
- [ ] Session-nav does not mutate cand-win-cursor (inert until P2.M1.T3 — L4).
- [ ] `tests/run.sh` green (no regression).

### Code Quality Validation

- [ ] 4 keys placed contiguous with the runtime block (NOT among ORIG_*).
- [ ] `_STATE_RUNTIME_KEYS` appended with name symbols (not @-strings); single-space.
- [ ] SESSION init uses ORIG_SESSION (not the window-mode-token `current` var).
- [ ] STATE_LINKED_ID untouched; no ORIG_* added; `set -u` honored (defaults baked).
- [ ] Comments cross-reference PRD §9 + the P2.M1.T2/T3 consumer seams.

### Documentation & Deployment

- [ ] No README/CHANGELOG edit (DOCS = none; internal state keys).
- [ ] No new test file (the window-flip suite is P2.M3.T1.S1).

---

## Anti-Patterns to Avoid

- ❌ Don't init `STATE_CAND_WIN_SESSION` from the `current` local. In window mode `current`
  is a `session:window_index` TOKEN (line 219), not a session name. Use
  `$(get_state "$ORIG_SESSION" "")` (the stable session name saved at STEP 2). (FINDING 5.)
- ❌ Don't place the 4 keys among the `ORIG_*` saved-state keys, or omit them from
  `_STATE_RUNTIME_KEYS`. They are RUNTIME keys (contiguous with STATE_RENDER_CACHE) and
  MUST be appended to the teardown list (else they leak past cancel/confirm). (FINDING 1/4.)
- ❌ Don't append `@livepicker-*` strings to `_STATE_RUNTIME_KEYS`. Use the readonly NAME
  symbols (`$STATE_CAND_WIN_*`); `clear_all_state` does `set-option -gu "$k"` where `$k`
  must resolve to the @-string. (FINDING 4.)
- ❌ Don't replace `STATE_LINKED_ID` with `STATE_PREVIEW_WIN_ID`. They have distinct roles
  (link handle vs logical shown-window) and diverge for the self-session (linked-id empty).
  Keep BOTH. (FINDING 3.)
- ❌ Don't add flip/preview logic (next-window/prev-window actions, preview chosen-window).
  Those are P2.M1.T2 (preview) + P2.M1.T3 (actions). This task is state scaffolding only —
  the keys are inert until then. (FINDING 5/10.)
- ❌ Don't use `tmux_unset_opt`/`-gu` for the init. `set_state "$KEY" ""` is a SET-EMPTY
  (mirrors the existing `set_state "$STATE_FILTER" ""` at activate). (FINDING 8.)
- ❌ Don't edit the T4 key-binding block — that's the parallel P1.M2.T1.S1's region
  (livepicker.sh ~336-446). Your edit is confined to the T2 init (line 239 -> 240) + state.sh.
  No overlap. (FINDING 6.)
- ❌ Don't use spaces for indent — TABS only (both files are tab-indented; a space oldText
  won't match the livepicker.sh edit).
- ❌ Don't add a test that asserts these keys drive window-flip behavior — that's P2.M3.T1.S1
  (test_window_flip.sh). This task's validation is the init+teardown cycle (L3) + suite-green (L2).

---

## Confidence Score

**9 / 10** for one-pass success. Rationale: both edits are located by verified-current content
with verbatim oldText/newText anchors; the `_STATE_RUNTIME_KEYS` append + the 4 inits are
mechanical; no test asserts the state-key set (no regression surface); the parallel P1.M2.T1.S1
edits a disjoint region (T4 vs T2); and the one subtle rule (ORIG_SESSION not `current`) is
called out explicitly with the reason. The init is provably no-behavior-change (nothing reads
the keys until P2.M1.T2/T3), and the teardown is auto-wired by the append (proven by the L3
cycle). Residual risk: a cosmetic blank-line placement between STATE_RENDER_CACHE and the 4 new
runtime keys — harmless either way; the implementer keeps the runtime block contiguous. The
`bash -n`/`shellcheck` + full-suite-green + L3 cycle are the firm gates.
