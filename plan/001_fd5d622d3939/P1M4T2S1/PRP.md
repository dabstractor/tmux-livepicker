# PRP — P1.M4.T2.S1: livepicker.sh — list-sessions/window + initial filter/index

---

## Goal

**Feature Goal**: Fill in the **T2 seam** of `scripts/livepicker.sh` (the file
CREATED in parallel by P1.M4.T1.S1) — implementing **PRD §6 Activation step 3
(build the list)** and **step 6's initial-selection half** (the highlight lands on
the user's own session/window, with the first preview handled later by T5). The
block runs **inside `activate_main()` after T1's save block** (so `ORIG_SESSION`
is already populated) and **before the T3 status-grow seam**. It reads
`@livepicker-type` (session|window) and `@livepicker-orig-session`, builds the
full list, sets `@livepicker-filter=''` (empty ⇒ full list), and sets
`@livepicker-index` to the 0-based position of the current session (or current
`session:window`) within that list. After S1, the three runtime keys
(`@livepicker-list`, `@livepicker-filter`, `@livepicker-index`) are populated and
mutually consistent — but the picker still does not visibly appear (no status
grow / key-table switch / mode-on — those are T3/T4/T5). The list+index is
independently and fully testable.

**Deliverable**: A **surgical edit** to `scripts/livepicker.sh` that **replaces
the single T2 seam comment line** (left by T1) with the list-build +
index-resolution block. No new file, no other file touched. The block is ~20
lines (locals + type branch + `mapfile` index resolution + three `set_state`
writes). It is the FIRST place `local` declarations appear in `activate_main`
(T1 inlines its captures), so there is no naming collision. The T3/T4/T5 seam
comments and the trailing `return 0` / driver remain untouched.

**Success Definition**:
- `bash -n scripts/livepicker.sh` passes; `shellcheck scripts/livepicker.sh` is
  clean (0 findings; the file-level `# shellcheck disable=SC1091,SC2153` from T1
  covers it — the T2 block adds no new warnings).
- Tabs only; no `set -e`; no new files.
- **Mock (a) session mode:** 4 sessions on an isolated socket with a pty client
  attached to `ccc` → after running livepicker.sh, `@livepicker-list` stores
  `aaa\nbbb\nccc\nddd` (newline-joined, no trailing newline), `@livepicker-filter`
  is `""`, and `@livepicker-index` is `2` (the position of `ccc`). The stored
  list re-reads via the renderer's `mapfile` path to **exactly 4 entries**, no
  phantom 5th element.
- **Mock (b) window mode:** `aaa` with windows 1/2/3 (current `aaa:2`) + others →
  `@livepicker-list` stores the `session:window` tokens, `@livepicker-index`
  points at the line equal to `tmux display-message -p '#{session_name}:#{window_index}'`.
- **Mock (c) vanish edge:** with `@livepicker-orig-session=GONE` (not in the
  list), livepicker.sh exits 0, builds the list anyway, and `@livepicker-index`
  defaults to `0`.

## User Persona (if applicable)

**Target User**: None directly (internal orchestration step). Transitively: the
end user pressing the activation key (PRD §3 user story 1 — "the picker lists my
sessions with the current one highlighted"). T2 is what makes the picker OPEN on
the user's own context rather than the top of the list.

**Use Case**: The user presses `C-Space` then the activation key. T1 saves
state. T2 builds the full session (or window) list and computes the initial
highlight position = the user's current session/window, so the very first
rendered picker frame (once T3–T5 land) shows the user's own session highlighted
and (via T5's first preview) its panes live below. The empty filter means the
full list is shown initially.

**User Journey** (S1–S2 scope — the picker does not yet appear; this is the data
foundation T3–T5 render):
1. User presses activation key → T1 guard + save run.
2. **T2 (this task):** `opt_type` ⇒ `session` (default). `list-sessions` builds
   the names. `ORIG_SESSION` (the current session, just saved) resolves to its
   0-based line number. `@livepicker-list/filter/index` are written.
3. [T3–T5 grow status, bind keys, run first preview, set mode on — later tasks.]

**Pain Points Addressed**:
- (a) **Opening on the wrong item.** Without index resolution, the renderer
  would default `@livepicker-index` to `0` and the picker would open highlighting
  the FIRST session in tmux order — disorienting (PRD §3 story 1 wants the
  current session highlighted). T2 resolves the current session's position so the
  opener lands on the user's own context.
- (b) **List/filter/index inconsistency.** These three keys are a tightly-coupled
  triple read together by the renderer on every redraw. T2 establishes them as a
  single consistent unit (index valid for the unfiltered list; empty filter ⇒
  filtered==all). Later input-handler (M6) mutations preserve this invariant.
- (c) **Window-mode parity.** PRD §11 `@livepicker-type=window` lists
  `session:window` tokens. T2 builds them and resolves the current token with the
  SAME logic (exact string match), so window mode opens on the current window —
  no special-casing downstream (renderer treats tokens as opaque strings).

## Why

- **Activation step 3 + half of step 6.** PRD §6 Activation: "3. Build the
  session list" and "6. Set the initial selection to the current session and run
  the first preview." T2 owns step 3 entirely (the list) and the *initial-
  selection* half of step 6 (the index); T5 owns the *first-preview* half and
  sets `@livepicker-mode on`.
- **The renderer's data source.** The renderer (P1.M2.T1.S1 — COMPLETE) reads
  `@livepicker-list` / `@livepicker-filter` / `@livepicker-index` via `get_state`
  on every status redraw. Until T2 populates them, the renderer would render an
  empty "no match" bar. T2 is what makes the renderer show real sessions.
- **Boundary respect.** T2 writes ONLY the three runtime keys (`STATE_LIST`,
  `STATE_FILTER`, `STATE_INDEX`) and reads `opt_type` + `ORIG_SESSION` (+ one
  `display-message` for window mode). It does NOT set `@livepicker-mode` (T5),
  does NOT grow status / install the renderer (T3), does NOT switch key-table /
  bind keys / suppress the hook (T4), does NOT run a preview / set linked-id
  (T1 inits it; T5/preview mutate it). It calls only: `list-sessions` /
  `list-windows -a`, `display-message -p` (window mode), and `set_state`. No
  `switch-client`, no `select-window`, no `link-window`, no `set-hook`, no
  `bind-key`, no `refresh-client`.
- **Scope cohesion.** T2 is the data foundation for T3 (renderer install — reads
  the keys), T5 (first preview — uses the resolved current session), and M6
  (input handler — mutates filter/index on the list T2 built). Getting the list
  format + index invariant right now unblocks three downstream milestones.

## What

A surgical in-place edit to `scripts/livepicker.sh` that replaces the T2 seam
comment with a block which:

1. Declares function-locals (`pick_type`, `current`, `list`, `idx`, `i`, and a
   `local -a items=()` array). Names avoid shadowing bash builtins (`pick_type`,
   not `type`).
2. Reads the mode: `pick_type="$(opt_type)"` (PRD §11; default `session`).
3. Reads the current-session token: `current="$(get_state "$ORIG_SESSION" "")"`
   (session mode keeps this; window mode overwrites it below). Client-
   independent, already saved by T1.
4. **Branches on type:**
   - `window`: `list="$(tmux list-windows -a -F '#{session_name}:#{window_index}' 2>/dev/null)"`
     and `current="$(tmux display-message -p '#{session_name}:#{window_index}')".
   - else (`session`): `list="$(tmux list-sessions -F '#{session_name}' 2>/dev/null)"`.
5. Resolves the 0-based index via `mapfile -t items < <(printf '%s' "$list")`
   then a first-match-wins loop `[ "${items[$i]}" = "$current" ] && { idx="$i"; break; }`,
   defaulting `idx=0`.
6. Writes the triple: `set_state "$STATE_LIST" "$list"`, `set_state "$STATE_FILTER" ""`,
   `set_state "$STATE_INDEX" "$idx"`.

### Success Criteria

- [ ] The T2 seam comment is REPLACED by the block; T3/T4/T5 seam comments and
      the trailing `return 0` / driver are UNCHANGED.
- [ ] `pick_type` read via `opt_type`; `current` initialized from `ORIG_SESSION`
      for both modes; window mode overwrites `current` via `display-message`.
- [ ] Session list built via `tmux list-sessions -F '#{session_name}'`; window
      list via `tmux list-windows -a -F '#{session_name}:#{window_index}'`; both
      with `2>/dev/null`.
- [ ] Index resolved with `mapfile -t items < <(printf '%s' "$list")` (process
      substitution, NOT a here-string) + first-match loop; 0-based; default 0.
- [ ] Three writes via `set_state` to `STATE_LIST`, `STATE_FILTER` (`""`),
      `STATE_INDEX`.
- [ ] **NO** `set-option -g "@livepicker-mode" on`, **NO** status/key-table/
      hook/preview mutations (T3/T4/T5's jobs).
- [ ] `bash -n` clean; `shellcheck` 0 findings; tabs only; no `set -e`.
- [ ] Mock (a) session: 4 sessions → list `aaa\nbbb\nccc\nddd`, filter `""`,
      index `2` (current `ccc`); re-read via mapfile ⇒ exactly 4 entries.
- [ ] Mock (b) window: list of `session:window` tokens; index points at the
      `display-message` token.
- [ ] Mock (c) vanish: `ORIG_SESSION=GONE` → exit 0, list built, index `0`.

## All Needed Context

### Context Completeness Check

_Pass_: A developer who has never seen this repo can implement T2 from
(a) the verbatim T2 block in the Implementation Blueprint (complete, ready to
paste at the seam), (b) the 12 live-verified findings in
`research/list_index_findings.md` — most critically FINDING 3 (the multi-line
`@livepicker-list` round-trip: `set-option -g` preserves embedded newlines and
`show-option -gqv` returns them with NO trailing newline, so the renderer's
`mapfile` yields exactly N entries — no phantom element), FINDING 4/5 (window
mode needs `display-message -p '#{session_name}:#{window_index}'` for the index
since `ORIG_WINDOW` is the `@N` id, not the index), and FINDING 8 (process
substitution, NOT here-string, so an empty list is a truly empty array), and
(c) the socket-shim mock that exercises session + window + vanish against an
isolated socket with a pty client (zero live-server impact). The INPUT
dependencies (`options.sh::opt_type`, `state.sh` with
`STATE_LIST`/`STATE_FILTER`/`STATE_INDEX`/`ORIG_SESSION`/`set_state`/`get_state`)
are all COMPLETE. The host file `scripts/livepicker.sh` is created in parallel by
T1 with the T2 seam comment; this task replaces exactly that line.

### Documentation & References

```yaml
# MUST READ — INPUT dependency: state.sh (the runtime + saved-state CONTRACT). COMPLETE (P1.M1.T3.S1).
- file: scripts/state.sh
  why: Defines the EXACT key constants T2 writes and reads. WRITES: STATE_LIST
       ("@livepicker-list"), STATE_FILTER ("@livepicker-filter"), STATE_INDEX
       ("@livepicker-index") via set_state. READS: ORIG_SESSION
       ("@livepicker-orig-session", saved by T1) via get_state. Also defines
       set_state/get_state (thin wrappers over utils tmux_set_opt/tmux_get_opt).
  critical: STATE_LIST/STATE_FILTER/STATE_INDEX are the three runtime keys the
            renderer (P1.M2.T1.S1) reads together on every redraw. ORIG_SESSION
            is the current session captured by T1's STEP 2 — reading it back is
            client-independent (works on a detached test socket).

# MUST READ — INPUT dependency: options.sh (the type accessor). COMPLETE (P1.M1.T1.S1).
- file: scripts/options.sh
  why: Defines opt_type() -> get_opt "@livepicker-type" "session" (PRD §11;
       enum session|window; default session). T2 calls opt_type to decide
       list-sessions vs list-windows.
  critical: opt_type returns "session" when unset (the default). Do NOT compare
            against empty; compare against "window" and treat everything else as
            session (forward-compatible with future modes — they'd just get
            session behavior).

# MUST READ — the host file this task EDITS (created in parallel by P1.M4.T1.S1).
- docfile: plan/001_fd5d622d3939/P1M4T1S1/PRP.md
  why: T1 CREATES scripts/livepicker.sh with: shebang; file-level
       `# shellcheck disable=SC1091,SC2153`; CURRENT_DIR; source trio
       (options/utils/state); activate_main() whose FIRST statement is the guard,
       then the STEP-2 save block, then the T2 seam comment, then T3/T4/T5 seam
       comments, then `return 0`, then the trailing driver. T2 REPLACES the T2
       seam comment with the block. Read this PRP to know the EXACT seam comment
       text and the insertion context (after set_state "$STATE_LINKED_ID" "",
       before the T3 seam).
  section: "Implementation Patterns & Key Details" (the ready-to-paste file body,
           specifically the T2 seam line), "Integration Points -> STATE WRITES/READS"

# MUST READ — the consumer of T2's output: the renderer. COMPLETE (P1.M2.T1.S1).
- file: scripts/renderer.sh
  why: The renderer reads the three keys T2 writes and PROVES the storage format
       is correct. It does: LIST=get_state(STATE_LIST,""); mapfile -t all < <(printf '%s' "$LIST");
       case-insensitive substring filter against FILTER; index all[$IDX] (clamped,
       0-based, displays idx+1). T2's output MUST satisfy this read path.
  pattern: |
    LIST="$(get_state "$STATE_LIST" "")"
    mapfile -t all < <(printf '%s' "$LIST")     # process substitution (NOT here-string)
    # filter: [[ "${name,,}" == *"${FILTER,,}"* ]]   # empty FILTER matches all
    # display filtered[$IDX] (0-based IDX; renderer clamps to [0,FLEN-1])
  gotcha: The renderer treats each list line as an OPAQUE string token — it does
          NOT parse session vs session:window. So T2's window-mode tokens need no
          special escaping; the ':' is a literal char in the substring filter.

# MUST READ — the consumer's research (proves the read path T2 must satisfy).
- docfile: plan/001_fd5d622d3939/P1M2T1S1/research/renderer_findings.md
  why: FINDING 3 proves mapfile -t < <(printf '%s' "$LIST") yields exactly N
       entries for an N-session newline-joined list (and 0 for empty), and that
       a here-string would create a phantom empty element. FINDING 4 proves an
       empty filter matches everything (so index-into-full == index-into-filtered
       when filter=''). FINDING 5 proves the index is 0-based (display idx+1).
       FINDING 11 confirms window-mode tokens need no special-casing.
  section: "FINDING 3", "FINDING 4", "FINDING 5", "FINDING 11"

# MUST READ — the empirical ground-truth for THIS seam (12 live-verified findings).
- docfile: plan/001_fd5d622d3939/P1M4T2S1/research/list_index_findings.md
  why: FINDING 1 (list-sessions: one name/line, default order, NO MRU, $() strips
       trailing \n); FINDING 2 (list-windows -a token format); FINDING 3 (THE
       critical multi-line @livepicker-list round-trip — set/show/mapfile yields
       exactly N, no phantom); FINDING 4/5 (display-message for window index;
       ORIG_WINDOW is @N id NOT index; session mode uses ORIG_SESSION); FINDING 6
       (0-based first-match index resolution); FINDING 7 (empty filter ⇒ full
       list); FINDING 8 (empty list ⇒ empty array via process sub); FINDING 9
       (vanish ⇒ idx 0); FINDING 10 (isolated -L socket inherits tmux.conf:
       base-index=1, renumber-windows=on — does not break exact-token matching);
       FINDING 11 (seam insertion model); FINDING 12 (shellcheck/tabs clean).
  critical: Read BEFORE writing the block. FINDING 3 (round-trip) and FINDING 8
            (process substitution) are the highest-consequence details — getting
            either wrong produces a phantom empty list element that the renderer
            would render as a blank highlighted item.

# MUST READ — the PRD sections selected for this work item.
- docfile: PRD.md
  why: §6 Activation step 3 (build the list) + step 6 (initial selection =
       current session; first preview is T5); §11 type=window (session:window
       tokens); §2 non-goals (NO MRU — tmux default order only); §3 user story 1
       (current session highlighted); §13 primitives (list-sessions -F '#{session_name}').
  section: "§6 Behaviors -> Activation (steps 3 and 6)", "§11 Configuration options (type)",
           "§2 Goals and non-goals -> Non-goals", "§3 User stories (story 1)",
           "§13 tmux primitives reference (list-sessions)"

# MUST READ — system ground-truth (shell style + test-harness reality).
- docfile: plan/001_fd5d622d3939/architecture/system_context.md
  why: §9 shell style (shebang, set -u only NO -e, tabs, quote everything); §7
       test-harness reality (the PATH-wrapper socket shim — the mock reuses it).
  section: "§9 Shell style", "§7 Test harness reality"
```

### Current Codebase tree

```bash
tmux-livepicker/
  PRD.md
  plugin.tmux                 # (P1.M1.T4.S1) COMPLETE. Binds prefix key -> scripts/livepicker.sh.
  plan/001_fd5d622d3939/{architecture/*.md, tasks.json, prd_snapshot.md, prd_index.txt}
  plan/001_fd5d622d3939/P1M4T1S1/{PRP.md, research/activate_guard_save_findings.md}  # parallel creator of livepicker.sh
  plan/001_fd5d622d3939/P1M4T2S1/{PRP.md, research/list_index_findings.md}            # THIS
  scripts/
    options.sh   # COMPLETE — opt_type (and other opt_*). INPUT dep.
    utils.sh     # COMPLETE — tmux_* (transitively used by state.sh). INPUT dep.
    state.sh     # COMPLETE — STATE_LIST/FILTER/INDEX + ORIG_SESSION + set_state/get_state. INPUT dep.
    renderer.sh  # COMPLETE (P1.M2.T1.S1). CONSUMES the keys T2 writes. Unchanged.
    preview.sh   # COMPLETE (P1.M3). Unchanged. Structural analog (seam-comment extension model).
    livepicker.sh   # CREATED IN PARALLEL by P1.M4.T1.S1. THIS task EDITS it (replaces the T2 seam comment).
  .gitignore
  # NOTE: NO test harness (P1.M7). Validate via the throwaway socket-shim mock (+ pty client).
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
    livepicker.sh   # EDITED (this task). The T2 seam comment is REPLACED by:
                    #   - locals (pick_type/current/list/idx/i + local -a items=())
                    #   - opt_type read + ORIG_SESSION read
                    #   - branch: window -> list-windows -a + display-message token;
                    #             session -> list-sessions
                    #   - mapfile + first-match index resolution (0-based, default 0)
                    #   - set_state LIST/FILTER("")/INDEX
                    # T3/T4/T5 seams + return 0 + driver UNCHANGED. Still no mode-on (T5).
```

### Known Gotchas of our codebase & Library Quirks

```bash
# CRITICAL (research FINDING 3): the multi-line @livepicker-list MUST round-trip
# cleanly. Store the RAW $(tmux list-…) output via set_state "$STATE_LIST" "$list".
# Command substitution STRIPS the trailing \n, so the stored value has embedded
# \n between names but NO trailing \n. tmux set-option -g preserves embedded
# newlines in @-options; tmux show-option -gqv returns them with no trailing \n.
# The renderer's mapfile -t all < <(printf '%s' "$LIST") then yields EXACTLY N
# entries — no phantom empty element. VERIFIED LIVE. Do NOT printf '%s\n', do NOT
# append a delimiter, do NOT re-join — store $() output verbatim.

# CRITICAL (research FINDING 8 + renderer FINDING 3): resolve the index with
# PROCESS SUBSTITUTION, never a here-string:
#   mapfile -t items < <(printf '%s' "$list")    # CORRECT — empty list -> items=() (0 elems)
#   mapfile -t items <<< "$list"                 # WRONG — empty list -> items=("") (1 phantom)
# The phantom empty element would render as a blank highlighted item and break
# the count. Always use < <(printf '%s' "$list").

# CRITICAL (research FINDING 4/5): in WINDOW mode there is NO saved window index.
# ORIG_WINDOW (saved by T1) is the @N window ID, NOT the index. So the current
# token MUST come from display-message -p '#{session_name}:#{window_index}',
# which produces the EXACT token format the list emits (#{window_index} is the
# raw integer). display-message needs a client — present at activation (the user
# pressed the key) and in the mock (attach a pty client). SESSION mode does NOT
# need display-message: it reads ORIG_SESSION (client-independent).

# CRITICAL (research FINDING 10): the isolated `tmux -L "$SOCK"` socket INHERITS
# the user's tmux.conf — so base-index may be 1 (not 0) and reumber-windows on.
# This does NOT break T2 (exact-token matching is base-index-agnostic: both
# list-windows and display-message honor base-index identically). In the MOCK,
# assert against the live display-message token, NOT a hardcoded "session:0".

# GOTCHA (research FINDING 5): read ORIG_SESSION via get_state for the session-
# mode current token — NOT display-message. ORIG_SESSION is client-independent
# (matches preview.sh FINDING 9 philosophy) and already saved by T1. Using
# display-message for the session would add an unnecessary client dependency.

# GOTCHA (research FINDING 7): an empty @livepicker-filter means the FULL list is
# shown (renderer FINDING 4: [[ "$x" == *""* ]] is always true). So the index T2
# stores (into the FULL unfiltered list) is ALSO a valid index into the filtered
# list at activation (filtered==all). This is the consistency invariant — do not
# over-think it; just set filter="" and the index into the full list.

# GOTCHA (research FINDING 9): if the current session/window is NOT in the list
# (a race — session vanished between T1's save and T2's list-build), idx defaults
# to 0. Do NOT exit 1 or abort — the picker should still open (benign degradation;
# the renderer clamps idx to [0,FLEN-1] anyway). First-match-wins + default 0.

# GOTCHA: variable naming. Do NOT name a local `type` — it shadows the bash
# builtin. Use `pick_type` (or `p_type`). The renderer uses uppercase `TYPE`; in
# activate_main use a distinct lowercase name to avoid confusion and keep
# shellcheck quiet.

# GOTCHA: this task is a SURGICAL EDIT at the T2 seam, not a rewrite. T1 created
# livepicker.sh with the seam comment `# --- T2 (P1.M4.T2.S1): build session list
# + initial selection (insert here) ---`. Replace EXACTLY that line. Leave the
# T3/T4/T5 seam comments, the trailing `return 0`, and the driver untouched.
# The block is the FIRST use of `local` in activate_main (T1 inlines its
# captures), so there is no naming collision with T1.

# CRITICAL: NO `set -e`, NO `set -o pipefail` (house style; system_context §9).
# list-sessions legitimately returns non-zero on an empty server; under set -e
# that would abort a half-built activate. Guard the list calls with 2>/dev/null
# (so the empty case yields list="") but do NOT add set -e. set -u is inherited
# from options.sh; every var is assigned first (pick_type/current/list/idx/i/items).

# STYLE (system_context §9): indent with TABS. Verify with
# `grep -Pn '^    ' scripts/livepicker.sh` (expect empty). shfmt is NOT installed.
```

## Implementation Blueprint

### Data models and structure

No new data model. The block adds function-locals to `activate_main`:
`pick_type`, `current`, `list`, `idx`, `i`, and `local -a items=()`. The state
surface is the **write set**: `STATE_LIST`, `STATE_FILTER`, `STATE_INDEX`. The
read set is `STATE_MODE`? No — T2 does NOT re-check the guard (T1 already did,
and T2 runs only after the guard passes). T2 reads `opt_type` (config) +
`ORIG_SESSION` (saved state) + one `display-message` (window mode). The list
format is newline-joined tokens (session names OR `session:window_index`), stored
verbatim from command substitution.

### Implementation Tasks (ordered by dependencies)

```yaml
Task 1: LOCATE the T2 seam in scripts/livepicker.sh
  - FILE: ./scripts/livepicker.sh  (CREATED IN PARALLEL by P1.M4.T1.S1).
  - FIND the single seam comment line (T1's ready-to-paste body emits EXACTLY):
      # --- T2 (P1.M4.T2.S1): build session list + initial selection (insert here) ---
  - CONTEXT: it sits AFTER the save block's last line (set_state "$STATE_LINKED_ID" "")
    and BEFORE the T3 seam comment:
      # --- T3 (P1.M4.T3.S1): grow status bar + install renderer (insert here) ---
  - VERIFY (do not proceed if mismatched — T1 may still be in flight; re-read the
    file fresh at implementation time): the line exists exactly once.

Task 2: REPLACE the T2 seam comment with the list-build + index-resolution block
  - OLD (exact): the single T2 seam comment line from Task 1.
  - NEW: the block below (indented with ONE tab to match activate_main's body):
      # --- T2 (P1.M4.T2.S1): build session/window list + initial selection ---
      # PRD §6 Activation step 3 (build the list) + step 6's initial-selection
      # half (highlight lands on the user's own session/window; the first PREVIEW
      # is P1.M4.T5.S1). Empty filter -> full list shown. Index is 0-based and
      # points at the current session (or current session:window) in the FULL
      # unfiltered list (renderer FINDING 4: empty filter matches all, so the
      # index is valid for filtered==all too).
      local pick_type current list idx i
      local -a items=()
      pick_type="$(opt_type)"                       # session | window (PRD §11; default session)
      current="$(get_state "$ORIG_SESSION" "")"     # client-independent; saved by STEP 2
      if [ "$pick_type" = "window" ]; then
      	# Window mode: session:window_index tokens across ALL sessions (PRD §11).
      	# The current token is the live session:window_index in the SAME format
      	# the list emits -> exact string match. ORIG_WINDOW is the @N id, NOT the
      	# index, so the index must come from display-message (client present at
      	# activation). (research FINDING 4/5)
      	list="$(tmux list-windows -a -F '#{session_name}:#{window_index}' 2>/dev/null)"
      	current="$(tmux display-message -p '#{session_name}:#{window_index}')"
      else
      	# Session mode: one name per line, tmux default order (NO MRU — PRD §2
      	# non-goals). $() strips the trailing newline so the stored value has
      	# embedded \n but no trailing \n (renderer mapfile yields exactly N).
      	list="$(tmux list-sessions -F '#{session_name}' 2>/dev/null)"
      fi
      # Resolve the 0-based index of `current` in the full list (default 0 if the
      # current session/window vanished between save and list-build — a race; the
      # renderer clamps anyway). PROCESS SUBSTITUTION (not a here-string) so an
      # empty list is a truly empty array (renderer FINDING 3 / research FINDING 8).
      mapfile -t items < <(printf '%s' "$list")
      idx=0
      for i in "${!items[@]}"; do
      	[ "${items[$i]}" = "$current" ] && { idx="$i"; break; }
      done
      # Store newline-joined list (verbatim $() output), empty filter (full list),
      # and the resolved index. set_state -> tmux set-option -g preserves embedded
      # newlines (research FINDING 3); renderer reads back exactly N entries.
      set_state "$STATE_LIST" "$list"
      set_state "$STATE_FILTER" ""
      set_state "$STATE_INDEX" "$idx"
  - NOTE: the block is indented with ONE tab (activate_main body level). The
    `if`/`else`/`for` inner lines use TWO tabs. Match the file's existing indent.

Task 3: VERIFY the edit left T3/T4/T5 seams + return 0 + driver intact
  - RUN: grep -n 'T3 (P1.M4.T3.S1)\|T4 (P1.M4.T4\|T5 (P1.M4.T5.S1\|return 0\|activate_main "\$@"' scripts/livepicker.sh
  - EXPECT: the T3/T4/T5 seam comments, a `return 0` (the last statement of
    activate_main), and the trailing driver are ALL still present and unchanged.
  - EXPECT: the OLD T2 seam comment is GONE (replaced); the new block's header
    comment `# --- T2 (P1.M4.T2.S1): build session/window list + initial selection ---`
    is present exactly once.

Task 4: VALIDATE (Level 1 syntax/lint + Level 2 socket-shim mock session/window/vanish)
  - RUN: bash -n scripts/livepicker.sh            (expect exit 0, no output)
  - RUN: shellcheck scripts/livepicker.sh         (expect 0 findings — file-level
    disable=SC1091,SC2153 from T1 covers it; T2 adds no new warnings)
  - RUN: grep -Pn '^    ' scripts/livepicker.sh   (expect empty — tabs only)
  - RUN the socket-shim mock (Validation Loop §2) — session (a) + window (b) +
    vanish (c), against an isolated socket WITH a pty client. Self-cleaning.
```

### Implementation Patterns & Key Details

The complete, ready-to-paste T2 block (the implementer replaces the T2 seam
comment with this; indent is one tab for the block, two tabs inside `if`/`for`):

```bash
	# --- T2 (P1.M4.T2.S1): build session/window list + initial selection ---
	# PRD §6 Activation step 3 (build the list) + step 6's initial-selection
	# half (highlight lands on the user's own session/window; the first PREVIEW
	# is P1.M4.T5.S1). Empty filter -> full list shown. Index is 0-based and
	# points at the current session (or current session:window) in the FULL
	# unfiltered list (renderer FINDING 4: empty filter matches all, so the
	# index is valid for filtered==all too).
	local pick_type current list idx i
	local -a items=()
	pick_type="$(opt_type)"                       # session | window (PRD §11; default session)
	current="$(get_state "$ORIG_SESSION" "")"     # client-independent; saved by STEP 2
	if [ "$pick_type" = "window" ]; then
		# Window mode: session:window_index tokens across ALL sessions (PRD §11).
		# The current token is the live session:window_index in the SAME format
		# the list emits -> exact string match. ORIG_WINDOW is the @N id, NOT the
		# index, so the index must come from display-message (client present at
		# activation). (research FINDING 4/5)
		list="$(tmux list-windows -a -F '#{session_name}:#{window_index}' 2>/dev/null)"
		current="$(tmux display-message -p '#{session_name}:#{window_index}')"
	else
		# Session mode: one name per line, tmux default order (NO MRU — PRD §2
		# non-goals). $() strips the trailing newline so the stored value has
		# embedded \n but no trailing \n (renderer mapfile yields exactly N).
		list="$(tmux list-sessions -F '#{session_name}' 2>/dev/null)"
	fi
	# Resolve the 0-based index of `current` in the full list (default 0 if the
	# current session/window vanished between save and list-build — a race; the
	# renderer clamps anyway). PROCESS SUBSTITUTION (not a here-string) so an
	# empty list is a truly empty array (renderer FINDING 3 / research FINDING 8).
	mapfile -t items < <(printf '%s' "$list")
	idx=0
	for i in "${!items[@]}"; do
		[ "${items[$i]}" = "$current" ] && { idx="$i"; break; }
	done
	# Store newline-joined list (verbatim $() output), empty filter (full list),
	# and the resolved index. set_state -> tmux set-option -g preserves embedded
	# newlines (research FINDING 3); renderer reads back exactly N entries.
	set_state "$STATE_LIST" "$list"
	set_state "$STATE_FILTER" ""
	set_state "$STATE_INDEX" "$idx"
```

NOTE for the implementer:
- This block is verified end-to-end (shellcheck clean; 9/9 session + 4/4 window +
  3/3 vanish assertions pass against the REAL sibling libs on an isolated socket
  with a pty client — see research/list_index_findings.md FINDINGS 8–10). Use it
  as-is; the only allowed deviation is comment phrasing.
- The OLD line to replace is EXACTLY:
  `	# --- T2 (P1.M4.T2.S1): build session list + initial selection (insert here) ---`
  (one leading tab). If T1's emitted comment differs in whitespace/wording, match
  whatever T1 actually wrote (re-read the file fresh at implementation time; T1
  may still be in flight in parallel).
- Do NOT add `set -e`. Do NOT use a here-string for mapfile. Do NOT append a
  trailing newline to the list. Do NOT use `display-message` for the session-mode
  current token (use ORIG_SESSION). Do NOT set `@livepicker-mode on`. Do NOT touch
  T3/T4/T5 seams, the `return 0`, or the driver. Do NOT create any other file.

### Integration Points

```yaml
HOST FILE (what this task edits — created in parallel by P1.M4.T1.S1):
  - scripts/livepicker.sh: activate_main(). T2 replaces the T2 seam comment,
    which sits after `set_state "$STATE_LINKED_ID" ""` (end of STEP 2 save) and
    before the T3 seam comment. The guard (STEP 1) and save (STEP 2) are ABOVE
    T2; T3/T4/T5 and `return 0` are BELOW. T2 runs only after the guard passes.

CALLERS / CONSUMERS (this task's OUTPUT — read by FUTURE subtasks + the renderer):
  - renderer.sh (P1.M2.T1.S1 — COMPLETE): reads @livepicker-list/filter/index via
        get_state on every redraw. T2's storage format is PROVEN compatible
        (renderer FINDING 3 + research FINDING 3): mapfile yields exactly N.
  - P1.M4.T3.S1 (status grow): installs the renderer into status-format; reads
        nothing from T2 directly but depends on the keys being populated so the
        first render shows real sessions.
  - P1.M4.T5.S1 (first preview + mode-on): uses the resolved current session
        (the item at @livepicker-index in @livepicker-list) as the first preview
        target, then sets @livepicker-mode on.
  - P1.M6 (input handler): mutates @livepicker-filter and @livepicker-index on
        the list T2 built (type/backspace/nav/confirm/cancel). The list itself
        is immutable for the picker lifetime (T2 builds it once).
  - P1.M5 (restore): clear_all_state unsets @livepicker-list/filter/index
        (they are in the STATE runtime-keys set). T2's writes are torn down.

STATE WRITES (this task — the list triple):
  - @livepicker-list   (newline-joined tokens; embedded \n preserved, no trailing \n)
  - @livepicker-filter ("")
  - @livepicker-index  (0-based int; position of current session/window; default 0)

STATE READS (this task):
  - @livepicker-type         (via opt_type; config — default "session")
  - @livepicker-orig-session (via get_state "$ORIG_SESSION"; saved by T1's STEP 2)

TMUX MUTATIONS (this task — PRD §13 primitives):
  - list-sessions -F '#{session_name}' (read-only; session mode)
  - list-windows -a -F '#{session_name}:#{window_index}' (read-only; window mode)
  - display-message -p '#{session_name}:#{window_index}' (read-only; window mode only)
  - set-option -g @livepicker-list/filter/index (the writes, via set_state)
  - NO switch-client, NO select-window, NO link-window/unlink-window, NO set-hook,
        NO bind-key, NO refresh-client, NO set-option key-table/status/status-format.

DATABASE / MIGRATIONS / ROUTES / CONFIG: none.
```

## Validation Loop

### Level 1: Syntax & Style (Immediate Feedback)

```bash
# Run after the edit — fix before proceeding.
bash -n scripts/livepicker.sh                     # syntax; expect no output, exit 0
shellcheck scripts/livepicker.sh                  # lint; expect 0 findings (file-level
                                                  # disable=SC1091,SC2153 from T1 covers it)
# Tabs-not-spaces sanity (shfmt NOT installed):
grep -Pn '^    ' scripts/livepicker.sh && echo "FAIL: 4-space indent found, use tabs" || echo "OK: tabs only"
# Confirm the T2 seam was REPLACED (old comment gone, new header present once):
grep -c 'build session list + initial selection (insert here)' scripts/livepicker.sh   # expect 0
grep -c 'T2 (P1.M4.T2.S1): build session/window list + initial selection' scripts/livepicker.sh  # expect 1
# Confirm T3/T4/T5 seams + return 0 + driver survived:
grep -n 'T3 (P1.M4.T3.S1)\|T4 (P1.M4.T4\|T5 (P1.M4.T5.S1' scripts/livepicker.sh   # expect 3 seam comments
grep -nE '^\treturn 0$' scripts/livepicker.sh                                     # expect the trailing return 0
grep -n 'activate_main "\$@" || exit 1' scripts/livepicker.sh                     # expect the driver
# Confirm NO mode-on / status / key-table / hook / preview mutation leaked into T2:
grep -n 'set-option -g "@livepicker-mode" on\|set_state "$STATE_MODE" "on"' scripts/livepicker.sh \
  && echo "FAIL: T2 must NOT turn mode on" || echo "OK: mode-on deferred to T5"
grep -n 'link-window\|switch-client\|set-hook\|bind-key\|refresh-client\|set-option.*key-table\|set-option.*status' scripts/livepicker.sh \
  && echo "FAIL: T2 must not mutate status/keys/hook/preview" || echo "OK: T2 is list-only"
# Run from the repo root.
```

### Level 2: Socket-Shim Mock Validation — session + window + vanish, zero live-server impact

Reuses the P1.M3.T1.S2 / T1 PATH-wrapper socket shim PLUS a pty client (window
mode's display-message needs one). Self-cleaning. This mock sources the REAL
`scripts/{options,utils,state}.sh` and runs the ACTUAL `scripts/livepicker.sh`.

```bash
#!/usr/bin/env bash
# Throwaway socket-shim validation for scripts/livepicker.sh T2 (do NOT commit).
set -u
REPO_ROOT="$(cd "$(dirname "$0")" && pwd)"
[ -f "$REPO_ROOT/scripts/livepicker.sh" ] || { echo "livepicker.sh missing (T1 in flight?)"; exit 1; }
[ -f "$REPO_ROOT/scripts/options.sh" ] && [ -f "$REPO_ROOT/scripts/utils.sh" ] && [ -f "$REPO_ROOT/scripts/state.sh" ] \
  || { echo "INPUT deps missing"; exit 1; }

SOCK="lp-t2-mock-$$"
SHIM_DIR="$(mktemp -d)"
cat > "$SHIM_DIR/tmux" <<EOF
#!/usr/bin/env bash
exec /usr/bin/tmux -L "$SOCK" "\$@"
EOF
chmod +x "$SHIM_DIR/tmux"
export PATH="$SHIM_DIR:$PATH"

cleanup() {
	PATH="/usr/bin:/bin:$PATH" tmux -L "$SOCK" kill-server 2>/dev/null || true
	rm -rf "$SHIM_DIR" /tmp/lp-t2-pty.log
}
trap cleanup EXIT

pass=0; fail=0
assert() { if [ "$2" = "$3" ]; then pass=$((pass+1)); printf 'ok   %s\n' "$1"; else fail=$((fail+1)); printf 'FAIL %s: got=[%s] want=[%s]\n' "$1" "$2" "$3"; fi; }
rg() { tmux show-option -gqv "$1"; }

# ---------- (a) SESSION MODE: 4 sessions; attach to ccc (index 2) ----------
tmux new-session -d -s aaa -x 80 -y 24
tmux new-session -d -s bbb -x 80 -y 24
tmux new-session -d -s ccc -x 80 -y 24
tmux new-session -d -s ddd -x 80 -y 24
tmux set-option -g "@livepicker-type" "session"
TMUX="" script -qec "tmux -L $SOCK attach -t ccc" /dev/null >/dev/null 2>&1 &
AP=$!; sleep 0.5
bash "$REPO_ROOT/scripts/livepicker.sh"; rc=$?
kill "$AP" 2>/dev/null; wait "$AP" 2>/dev/null
assert "session: exit 0" "$rc" "0"
LS="$(rg "@livepicker-list")"; declare -a rt=(); mapfile -t rt < <(printf '%s' "$LS")
assert "session: list count==4 (no phantom)" "${#rt[@]}" "4"
assert "session: list[0]==aaa" "${rt[0]}" "aaa"
assert "session: list[1]==bbb" "${rt[1]}" "bbb"
assert "session: list[2]==ccc" "${rt[2]}" "ccc"
assert "session: list[3]==ddd" "${rt[3]}" "ddd"
assert "session: filter==empty" "$(rg "@livepicker-filter")" ""
assert "session: index==2 (current ccc)" "$(rg "@livepicker-index")" "2"
assert "session: items[index]==current (renderer consistency)" "${rt[$(rg "@livepicker-index")]}" "ccc"
# cleanup livepicker keys for the next test
for k in mode list filter index linked-id type orig-session orig-window orig-layout \
         orig-key-table orig-status orig-renumber-windows orig-session-window-changed \
         orig-status-format-indices; do tmux set-option -gu "@livepicker-$k" 2>/dev/null; done

# ---------- (b) WINDOW MODE: aaa has windows 1/2/3; current aaa:2 ----------
tmux new-window -t aaa; tmux new-window -t aaa
tmux select-window -t aaa:2
tmux set-option -g "@livepicker-type" "window"
TMUX="" script -qec "tmux -L $SOCK attach -t aaa" /dev/null >/dev/null 2>&1 &
AP=$!; sleep 0.5
bash "$REPO_ROOT/scripts/livepicker.sh"; rc=$?
kill "$AP" 2>/dev/null; wait "$AP" 2>/dev/null
assert "window: exit 0" "$rc" "0"
WL="$(rg "@livepicker-list")"; declare -a wrt=(); mapfile -t wrt < <(printf '%s' "$WL")
assert "window: filter==empty" "$(rg "@livepicker-filter")" ""
CT="$(tmux display-message -p '#{session_name}:#{window_index}')"
eidx=0; for x in "${!wrt[@]}"; do [ "${wrt[$x]}" = "$CT" ] && { eidx="$x"; break; }; done
assert "window: stored index matches current-token position" "$(rg "@livepicker-index")" "$eidx"
assert "window: items[index]==current token" "${wrt[$(rg "@livepicker-index")]}" "$CT"
for k in mode list filter index linked-id type orig-session; do tmux set-option -gu "@livepicker-$k" 2>/dev/null; done

# ---------- (c) VANISH EDGE: current session not in list -> idx 0 ----------
tmux set-option -g "@livepicker-orig-session" "GONE"
tmux set-option -g "@livepicker-type" "session"
bash "$REPO_ROOT/scripts/livepicker.sh" 2>/dev/null; rc=$?
assert "vanish: exit 0 (session-mode list needs no client)" "$rc" "0"
assert "vanish: index defaults to 0" "$(rg "@livepicker-index")" "0"
assert "vanish: list still built (>=1 session exists)" "$([ "$(rg "@livepicker-list" | grep -c .)" -ge 1 ] && echo 1)" "1"

printf '\n==== PASS=%d FAIL=%d ====\n' "$pass" "$fail"
[ "$fail" = "0" ]
# Expected: PASS=15 FAIL=0. Key proofs:
#  - session: list is newline-joined with NO phantom element (count==4); index==2
#    (current ccc); items[index]==current (renderer-consistent).
#  - window: index points at the display-message token; items[index]==that token.
#  - vanish: current-not-in-list -> idx 0, list still built, exit 0.
```

### Level 3: Integration Testing (System Validation)

```bash
# Live spot-check on an ISOLATED socket WITH an attached pty client — confirms
# the stored list round-trips through the ACTUAL renderer read path (set/show/
# mapfile) with real session names. Self-cleaning.
export LP_SOCK="lp-t2-live-$$"
REPO_ROOT="$(pwd)"
SHIM_DIR="$(mktemp -d)"
cat > "$SHIM_DIR/tmux" <<EOF
#!/usr/bin/env bash
exec /usr/bin/tmux -L "$LP_SOCK" "\$@"
EOF
chmod +x "$SHIM_DIR/tmux"
trap 'PATH=/usr/bin:/bin:$PATH tmux -L "$LP_SOCK" kill-server 2>/dev/null; rm -rf "$SHIM_DIR"' EXIT
T() { PATH="$SHIM_DIR:$PATH" tmux "$@"; }
T new-session -d -s proj-a -x 120 -y 40
T new-session -d -s proj-b -x 120 -y 40
T new-session -d -s notes -x 120 -y 40
T set-option -g "@livepicker-type" "session"
TMUX="" script -qec "tmux -L $LP_SOCK attach -t proj-b" /dev/null >/dev/null 2>&1 &
AP=$!; sleep 0.5
PATH="$SHIM_DIR:$PATH" bash "$REPO_ROOT/scripts/livepicker.sh"; echo "rc=$? (expect 0)"
kill "$AP" 2>/dev/null; wait "$AP" 2>/dev/null
echo "list=[$(T show-option -gqv "@livepicker-list")] (expect proj-a newline proj-b newline notes)"
echo "filter=[$(T show-option -gqv "@livepicker-filter")] (expect empty)"
echo "index=[$(T show-option -gqv "@livepicker-index")] (expect 1 = proj-b)"
# Simulate the renderer's read path on the stored list:
LIST="$(T show-option -gqv "@livepicker-list")"
declare -a all=(); mapfile -t all < <(printf '%s' "$LIST")
echo "renderer-read count=${#all[@]} (expect 3, NOT 4)"
echo "renderer-read items: ${all[*]}"
# Expected: count==3 (no phantom); index==1; filter empty. Proves T2's stored
# format satisfies the renderer's read path with real multi-line data.
```

### Level 4: Creative & Domain-Specific Validation

```bash
# Pollution invariant spot-check (PRD §15.18 — the core guarantee) for the T2
# list-build. Building the list + setting the index must NOT fire client-session-
# changed (T2 never calls switch-client). Run ONLY if @session-history-hist is
# present on the LIVE server; touches ONLY option reads + the @livepicker-*
# keys + one isolated run of livepicker.sh.
if tmux show-options -gv "@session-history-hist" >/dev/null 2>&1; then
    REPO_ROOT="$(pwd)"
    BEFORE="$(tmux show-options -gv "@session-history-hist" 2>/dev/null)"
    bash "$REPO_ROOT/scripts/livepicker.sh" 2>/dev/null
    AFTER="$(tmux show-options -gv "@session-history-hist" 2>/dev/null)"
    for k in mode list filter index linked-id type; do
        tmux set-option -gu "@livepicker-$k" 2>/dev/null
    done
    if [ "$BEFORE" = "$AFTER" ]; then
        echo "OK: @session-history-hist UNCHANGED across T2 list-build (Invariant A holds)"
    else
        echo "FAIL: history polluted by T2 (should be impossible — no switch-client)"
    fi
else
    echo "SKIP: tmux-session-history not present on live server (mock §2 covers this structurally)"
fi
# Expected: OK — T2 never calls switch-client, so client-session-changed never fires.
```

## Final Validation Checklist

### Technical Validation

- [ ] `bash -n scripts/livepicker.sh` exits 0 with no output.
- [ ] `shellcheck scripts/livepicker.sh` reports 0 findings (file-level disable
      from T1 covers source-lines + ORIG_*/STATE_*; T2 adds none).
- [ ] No 4-space indents (`grep -Pn '^    '` is empty); tabs only.

### Feature Validation

- [ ] The T2 seam comment is REPLACED by the block; the new header comment
      `# --- T2 (P1.M4.T2.S1): build session/window list + initial selection ---`
      appears exactly once; the old `(insert here)` comment is gone.
- [ ] T3/T4/T5 seam comments, `return 0`, and the trailing driver are UNCHANGED.
- [ ] `pick_type="$(opt_type)"`; `current="$(get_state "$ORIG_SESSION" "")"`.
- [ ] Window branch: `list-windows -a -F '#{session_name}:#{window_index}'` +
      `display-message -p '#{session_name}:#{window_index}'`.
- [ ] Session branch: `list-sessions -F '#{session_name}'` (current stays ORIG_SESSION).
- [ ] Index via `mapfile -t items < <(printf '%s' "$list")` + first-match loop;
      0-based; default 0.
- [ ] Three writes: `set_state "$STATE_LIST" "$list"`, `set_state "$STATE_FILTER" ""`,
      `set_state "$STATE_INDEX" "$idx"`.
- [ ] **NO** `@livepicker-mode on`; **NO** status/key-table/hook/preview mutations.
- [ ] Mock (a) session: count==4, index==2, items[index]==current; PASS all.
- [ ] Mock (b) window: index matches current-token position; items[index]==token.
- [ ] Mock (c) vanish: idx==0, list built, exit 0.

### Code Quality Validation

- [ ] NO `set -e`, NO `set -o pipefail` (house style; system_context §9).
- [ ] All expansions double-quoted (`"$list"`, `"$current"`, `"$(…)"`, `"${items[$i]}"`).
- [ ] `mapfile` uses process substitution (`< <(printf …)`), NOT a here-string.
- [ ] List stored verbatim from `$(…)` (no appended newline / re-join).
- [ ] Locals avoid shadowing bash builtins (`pick_type`, not `type`).
- [ ] No new files created; no other source file touched.

### Documentation & Deployment

- [ ] Block header comment states: PRD §6 step 3 + step-6-initial-selection;
      empty-filter⇒full-list; 0-based index into unfiltered list; window-mode
      display-message rationale (ORIG_WINDOW is @N id); the no-set-e rule.
- [ ] No README/doc file created (DOCS = Mode A; covered by README P1.M8.T1.S1).
- [ ] No tmux.conf edit; no tests/ dir committed.

---

## Anti-Patterns to Avoid

- ❌ Don't store the list with a trailing newline or re-join it differently.
  Store the RAW `$(tmux list-…)` output verbatim — `$()` already stripped the
  single trailing `\n`, which is exactly what makes the renderer's `mapfile` yield
  N entries (not N+1). `printf '%s\n'` or appending `\n` risks a phantom element
  (research FINDING 3).
- ❌ Don't resolve the index with a here-string (`mapfile -t items <<< "$list"`).
  A here-string appends a `\n`, so an empty list becomes `items=("")` — a 1-element
  phantom array that renders as a blank highlighted item. Use PROCESS SUBSTITUTION
  `< <(printf '%s' "$list")` (research FINDING 8 + renderer FINDING 3).
- ❌ Don't use `display-message` for the session-mode current token. `ORIG_SESSION`
  (saved by T1) is client-independent and already available; `display-message`
  would add an unnecessary client dependency. Reserve `display-message` for the
  window-mode index (there is no saved index — `ORIG_WINDOW` is the `@N` id)
  (research FINDING 4/5).
- ❌ Don't `exit 1` when the current session/window isn't in the list. That's a
  benign race; default `idx=0` and let the picker open (the renderer clamps
  anyway). Aborting would leave the user with a half-activated picker
  (research FINDING 9).
- ❌ Don't name a local `type` — it shadows the bash builtin. Use `pick_type`.
- ❌ Don't set `@livepicker-mode on`, don't grow status / install the renderer,
  don't switch key-table / bind keys / suppress the hook, don't run a preview.
  Those are T3/T4/T5. T2 writes ONLY list/filter/index (research: boundary).
- ❌ Don't rewrite `livepicker.sh` or touch any other file. This is a SURGICAL
  EDIT: replace the single T2 seam comment with the block. Leave T1's guard,
  save, T3/T4/T5 seams, `return 0`, and the driver exactly as T1 wrote them.
- ❌ Don't add `set -e`/`set -o pipefail`. `list-sessions` returns non-zero on an
  empty server; under `set -e` that would abort a half-built activate. Guard with
  `2>/dev/null` (so the empty case yields `list=""`), not `set -e`.
- ❌ Don't hardcode a window index like `"session:0"` in the mock. The isolated
  `-L` socket inherits the user's `tmux.conf` (`base-index` may be 1). Assert
  against the live `display-message` token (research FINDING 10).
- ❌ Don't create a `tests/` directory or committed test file — the harness is
  invented in P1.M7. Validate via the throwaway socket-shim mock (Level 2).
- ❌ Don't use 4-space indent — tabs only (system_context §9).

---

## Confidence Score

**9 / 10** for one-pass success. Rationale: the deliverable is a ~20-line
surgical insertion into a file created in parallel by T1, whose complete body is
given verbatim in the Implementation Blueprint and was validated END-TO-END
against the REAL sibling libs (`scripts/{options,utils,state}.sh`) on an isolated
socket with a pty client: `bash -n` clean, `shellcheck` 0 findings, tabs only,
and 9/9 session-mode + 4/4 window-mode + 3/3 vanish assertions pass. Every
behavior the block depends on was re-verified live on `tmux 3.6b` — most
critically the multi-line `@livepicker-list` round-trip (`set-option` →
`show-option` → `mapfile` yields exactly N, no phantom element; FINDING 3), the
process-substitution requirement for an empty list (FINDING 8), and the window-
mode index source (`display-message -p '#{window_index}'`, since `ORIG_WINDOW` is
the `@N` id; FINDING 4/5). The INPUT dependencies (`opt_type`, `STATE_LIST`/
`FILTER`/`INDEX`, `ORIG_SESSION`, `set_state`/`get_state`) are all COMPLETE, and
the consumer (renderer P1.M2 COMPLETE) is PROVEN to read exactly this storage
format (renderer FINDING 3). Residual risks: (a) T1 still being in-flight at
implementation time — mitigated by Task 1's "re-read the file fresh; match
whatever T1 actually wrote for the seam comment" instruction; (b) the pty-client
attachment in the mock being flaky on some kernels — mitigated by redirecting pty
output to `/dev/null` and the Level 3 second-socket spot-check; (c) the
`base-index=1` quirk on the inherited-conf socket — mitigated by asserting
against the live `display-message` token, not a hardcoded index. All residual
risks are deterministically caught by the validation loop.
