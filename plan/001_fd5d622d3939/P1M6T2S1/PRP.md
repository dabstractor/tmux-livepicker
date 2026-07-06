# PRP — P1.M6.T2.S1: input-handler.sh `backspace` / `next-session` / `prev-session`

---

## Goal

**Feature Goal**: **FILL** the `backspace|next-session|prev-session` seam in
`scripts/input-handler.sh` (created by the COMPLETE sibling P1.M6.T1.S1 with
that seam as a placeholder `return 0`), splitting it into THREE fully-implemented
branches. To satisfy the work-item CONTRACT (point 1 — "share a single filter
function ... to avoid drift"), this task ALSO **CREATES** a new shared helper
`scripts/filter.sh` (defining `lp_build_filtered`) and **REFACTORS**
`scripts/renderer.sh` to consume it — collapsing the renderer's inline copy and
the input-handler's copy into ONE canonical filter, so nav's
`filtered[index]` resolution is byte-identical to the renderer's ordering.

Per PRD §6 Filtering + §6 Session navigation + §7 (preview subsystem) + Invariant
A (system_context §3: preview navigation must NEVER call `switch-client`):

- **backspace** — strip the last char off `@livepicker-filter` (`${old%?}`,
  guarded empty), reset `@livepicker-index` to `0`, `refresh-client -S`. Does NOT
  call preview.sh (per the explicit work-item §3 contract — see "Known Gotchas").
- **next-session** — re-filter `@livepicker-list` by `@livepicker-filter`
  (via the shared helper → length `L`); if `L==0` no-op; else
  `index=(index+1)%L`; set index; call `preview.sh "<filtered[new index]>"`;
  `refresh-client -S`.
- **prev-session** — `index=(index-1+L)%L`; preview + refresh (mirror of next).

Neither nav action calls `switch-client` — preview.sh does `link-window` /
`select-window` (fires only `session-window-changed`, already suppressed by
activate P1.M4.T4.S2; never `client-session-changed`), so **session history
stays clean** (Invariant A — the plugin's defining core rule, PRD §4).

This is the SECOND subtask of module P1.M6 (Input handler). It follows the
established incremental-edit pattern (see how `scripts/restore.sh` was grown
across P1.M5.T1→T4): T2.S1 EDITS the existing `input-handler.sh` IN PLACE —
grows the `local` line, adds a `source filter.sh`, and splits the combined seam
branch into three — while leaving the `confirm)` (T3) and `cancel)` (T4) seams
and the `*) return 0` default untouched.

**Deliverable**:
1. **NEW** `scripts/filter.sh` — a sourced library (NO source-time side effects)
   defining `lp_build_filtered LIST FILTER` (prints each newline-separated name
   from LIST that case-insensitively contains FILTER, preserving original
   order+case; empty FILTER matches all; empty LIST prints nothing). This is
   THE SINGLE FILTER FUNCTION shared by renderer.sh + input-handler.sh.
2. **EDIT** `scripts/renderer.sh` — replace its inline 6-line filter loop with a
   `source filter.sh` + one `mapfile` call into `lp_build_filtered`; trim the 3
   now-unused locals (`low_filter name low_name`). Mechanical; behavior identical.
3. **EDIT** `scripts/input-handler.sh` — add `source filter.sh` after state.sh;
   grow the `local` line; split `backspace|next-session|prev-session)` into three
   implemented branches; preserve the confirm/cancel seams + `*) return 0`.

**Success Definition**:
- `bash -n` + `shellcheck` (0 findings; only the file-level `disable=SC1091,SC2153`
  already present in the two edited scripts, and `disable=SC1091` in filter.sh)
  pass on all THREE files. Tabs only; `set -u` only (NO `-e`, NO `-o pipefail`).
- **Shared filter = single source of truth:** `grep -rn 'low_name\|low_filter'`
  in `scripts/` finds the pattern ONLY inside `filter.sh` (renderer.sh's inline
  copy is gone). renderer.sh output is byte-identical before/after the refactor
  (verified by the Level 2 mock rendering the same list+filter+index).
- **backspace:** on filter `"abc"` → `"ab"`, index → `0`; on `""` → no-op
  (filter stays `""`, index `0`); never crashes the picker.
- **next/prev wrap + cycle preview (work-item §5 MOCKING):** with a list of
  `alpha\nbeta\ngamma` and an empty filter (`L=3`), 3 `next-session` presses cycle
  index `0→1→2→0` (wrap) and `@livepicker-linked-id` follows
  alpha→beta→gamma→alpha (the previewed session). `prev-session` cycles
  `0→2→1→0` (reverse wrap). **A `client-session-changed` canary hook NEVER
  fires** (Invariant A — no `switch-client`).
- **L==0 guard:** with a filter matching nothing (e.g. `"zzz"`), `next-session`
  is a no-op (index unchanged, linked-id unchanged, NO division-by-zero error).
- **Invariant A:** no branch calls `switch-client` / `new-session` / `set-hook`
  / touches `@livepicker-list` / `@livepicker-mode` / any `@livepicker-orig-*`.
- **No off-limits work:** the `confirm)` and `cancel)` seams stay as `return 0`
  placeholders (T3/T4 fill them). backspace/nav are the ONLY implemented logic.

## User Persona (if applicable)

**Target User**: None directly (these actions are internal key-handlers invoked
by tmux's `livepicker` key table). Transitively: the end user browsing
sessions (PRD §3 story: "I ... navigate with arrows/j/k and a LIVE preview of
each session's panes appears ... without switching sessions"). T2.S1 makes the
"navigate ... and a live preview appears ... without switching sessions"
sentence literally TRUE — next/prev move the highlight + re-link the live
preview, while backspace lets the user correct a mistyped query. Critically, all
of this happens WITHOUT polluting session history (no `switch-client`), which is
the plugin's defining promise (PRD §4 "preview without switching").

**Use Case**: The picker is active (`@livepicker-mode=on`, `key-table=livepicker`,
a list populated, a filter possibly typed). The user:
- presses a nav key (`Down`/`j`/`C-M-Tab` → next-session; `Up`/`k`/`C-M-BTab` →
  prev-session) to cycle through the FILTERED matches and watch the live preview
  of each candidate session's panes; OR
- presses `BSpace` (→ backspace) to erase the last query char and re-widen the
  filtered set.

**User Journey** (T2.S1 scope — a single nav/backspace keystroke):
1. …activate (P1.M4) saved state, built the list, grew the status bar, installed
   the renderer, switched `key-table` to `livepicker`, bound all keys (incl.
   nav/backspace), ran the first preview, set `@livepicker-mode on`. The user
   has typed a filter (or none) via the `type` action (P1.M6.T1.S1, COMPLETE).
2. The user presses `j` (next-session).
3. **T2.S1 (this task):**
   - tmux looks up `j` in the `livepicker` table → `run-shell
     "$CURRENT_DIR/input-handler.sh next-session"`.
   - `input_main` → `case "$action" in next-session) ...`.
   - Re-filter `@livepicker-list` by `@livepicker-filter` via the shared
     `lp_build_filtered` → `filtered=(alpha beta gamma)`, `L=3`.
   - `cur_index=0` (sanitized) → `new_idx=((0+1)%3)=1` → set `@livepicker-index=1`.
   - `target="${filtered[1]}"`=`beta`; `"$CURRENT_DIR/preview.sh" "beta"`
     (links beta's window live; does NOT switch-client).
   - `tmux refresh-client -S` → the `#()` renderer redraws, highlighting index 1.
4. The user presses `j` twice more: index goes `1→2→0` (wraps), the preview
   cycles beta→gamma→alpha, and the client's session NEVER changes.

**Pain Points Addressed**:
- (a) **Dead nav/backspace keys.** Without these branches, nav/backspace keys
  are bound to `return 0` no-ops — pressing them does nothing visible. T2.S1
  makes next/prev cycle the highlight + live preview, and backspace trim the
  query (the picker's core browse/edit UX).
- (b) **Drifting filter logic.** Without a shared filter function, the
  input-handler's filtered-list length `L` could diverge from the renderer's
  (e.g. one lowercases, the other doesn't), so `index` would point at the wrong
  session or wrap off-by-one. The work-item CONTRACT (point 1) demands a SINGLE
  filter function; T2.S1 creates `filter.sh` and makes renderer.sh consume it too.
- (c) **Session-history pollution.** A naive nav might call `switch-client` to
  show the candidate — that would append every browsed session to the client's
  session history (the exact anti-pattern PRD §4 forbids). T2.S1 delegates to
  preview.sh (`link-window`/`select-window`), which changes the SHOWN window
  without changing the client's SESSION (Invariant A).

## Why

- **PRD §6 "Session navigation"** is the controlling spec: "next-session and
  prev-session move `@livepicker-index` within the filtered list (wrapping). Each
  move refreshes the preview (section 7) and the status renderer. Navigation
  must not call `switch-client`." T2.S1 implements this verbatim.
- **PRD §6 "Filtering"** governs backspace: "Backspace removes the last
  character. After each change, run `tmux refresh-client -S` ... The renderer
  filters `@livepicker-list` by the query (substring, case-insensitive) and
  highlights the item at `@livepicker-index`."
- **PRD §4 "The core rule: preview without switching"** + **PRD §7** (the
  preview subsystem) + **Invariant A** (system_context §3): preview navigation
  shows the candidate's panes LIVE via `link-window`/`select-window`, which fires
  only `session-window-changed` (suppressed globally by activate T4.S2) and NEVER
  `client-session-changed`. So nav is provably non-polluting.
- **Work-item CONTRACT point 1 (shared filter):** "The filtered[index]
  resolution ... must match the renderer's ordering exactly — share a single
  filter function (put it in utils.sh or a tiny sourced helper to avoid drift)."
  T2.S1 creates `filter.sh` AND refactors renderer.sh to use it (two copies would
  still drift; one copy is the only way to guarantee identity).
- **Scope cohesion.** T2.S1 is the nav/backspace counterpart of: activate T4.S1
  (which bound `run-shell "$CURRENT_DIR/input-handler.sh backspace|next-session|
  prev-session"`), activate T2.S1 (which built `@livepicker-list`), and the
  `type` action (T1.S1, which appends to the filter). The shared contract is the
  THREE state keys (`STATE_FILTER`/`STATE_INDEX`/`STATE_LIST`) + the preview
  delegation. T2.S1 writes only `STATE_INDEX` (nav) or `STATE_FILTER`+
  `STATE_INDEX` (backspace); it reads all three via the shared filter. This
  module (P1.M6) is the LAST functional module before P1.M7 validation — T2.S1
  is its browse/edit core (T1.S1 was its query-append core).

## What

**EDIT** the existing `scripts/input-handler.sh` IN PLACE + **CREATE**
`scripts/filter.sh` + **EDIT** `scripts/renderer.sh` IN PLACE. No other file is
touched.

1. **NEW `scripts/filter.sh`** — a sourced library (NOT executed; NO source-time
   side effects). Header doc-comment + `# shellcheck disable=SC1091` + `set -u`
   (NOT `-e`; NOT `-o pipefail`). Defines ONE function `lp_build_filtered()`
   (see "Implementation Patterns" for the canonical, ready-to-paste body). The
   algorithm is byte-identical to renderer.sh's current inline filter so the
   refactor is behavior-preserving: `mapfile -t all < <(printf '%s' "$LIST")`
   (NO trailing newline → empty LIST yields `all=()`, NOT `[""]`), lowercase
   both sides via `${VAR,,}`, match `[[ "$low_name" == *"$low_filter"* ]]`
   (empty filter matches all), `printf '%s\n' "$name"` per match (preserves
   original case + order; caller `mapfile -t` strips the trailing newline).
2. **EDIT `scripts/renderer.sh`** — (a) add `# shellcheck source=filter.sh` +
   `source "$CURRENT_DIR/filter.sh"` AFTER the `state.sh` source line (load-bearing
   trio order preserved; filter.sh has no deps, so appending it last is safe);
   (b) in `render()`, replace the inline filter block:
   ```bash
   low_filter="${FILTER,,}"
   for name in "${all[@]}"; do
       low_name="${name,,}"
       if [[ "$low_name" == *"$low_filter"* ]]; then
           filtered+=("$name")
       fi
   done
   FLEN="${#filtered[@]}"
   ```
   with:
   ```bash
   mapfile -t filtered < <(lp_build_filtered "$LIST" "$FILTER")
   FLEN="${#filtered[@]}"
   ```
   and (c) trim the now-unused locals on the `local TOTAL FLEN low_filter name
   low_name` line down to `local TOTAL FLEN`. Leave EVERYTHING else (the
   highlight/count/style emission, the `render || printf error` fallback, the
   driver) byte-identical.
3. **EDIT `scripts/input-handler.sh`** — (a) add `# shellcheck source=filter.sh`
   + `source "$CURRENT_DIR/filter.sh"` AFTER the `state.sh` source line; (b)
   grow the `local` line from `local action char new_filter` to
   `local action char new_filter cur_filter cur_list cur_index L new_idx target`
   and add `local -a filtered=()`; (c) SPLIT the combined
   `backspace|next-session|prev-session)` branch into THREE separate branches
   (`backspace)` / `next-session)` / `prev-session)`), each fully implemented
   (see "Implementation Patterns"). PRESERVE the `confirm)` seam (T3), the
   `cancel)` seam (T4), the `*) return 0` default, the header doc-comment, the
   driver `input_main "$@" || exit 1` / `exit 0`, and ALL of T1.S1's `type`
   branch unchanged.

### Success Criteria

- [ ] `scripts/filter.sh` exists, is a sourced library (NO driver / NO
      source-time side effects / NO `*_main` execution), passes `bash -n` +
      `shellcheck` (0 findings; only `disable=SC1091`), and defines exactly ONE
      function `lp_build_filtered`.
- [ ] `scripts/renderer.sh` still passes `bash -n` + `shellcheck`; its output is
      byte-identical before/after the refactor (mock-rendered on the same
      list+filter+index). `grep -n 'low_name\|low_filter' scripts/renderer.sh`
      is EMPTY (inline filter gone); it now contains exactly one
      `source "$CURRENT_DIR/filter.sh"` + one `lp_build_filtered` call.
- [ ] `scripts/input-handler.sh` still passes `bash -n` + `shellcheck` (only the
      existing file-level `disable=SC1091,SC2153`); sources filter.sh after
      state.sh; `local` line grown; three separate branches; confirm/cancel
      seams + `*) return 0` + `type` branch unchanged.
- [ ] **backspace:** trims one char (`${old%?}`), resets index to `0`, refreshes;
      empty-filter is a safe no-op; does NOT call preview.sh / switch-client.
- [ ] **next-session / prev-session:** re-filter via the shared helper; `L==0`
      no-op; else wrap-modulo the index, set it, call `preview.sh` with the
      session at the NEW index, refresh; NEVER `switch-client`.
- [ ] **Shared filter:** `grep -rn 'low_name\|=.\*"$low_filter"\|low_filter='
      scripts/` matches ONLY inside `filter.sh` (single source of truth).
- [ ] **Mock (work-item §5):** 3 matches, next×3 wraps 0→1→2→0, preview cycles
      alpha→beta→gamma→alpha, `client-session-changed` canary NEVER fires;
      prev×3 wraps 0→2→1→0; backspace trims + resets index; filter `"zzz"` →
      next is a no-op. See Validation Loop §2.

## All Needed Context

### Context Completeness Check

_Pass_: A developer who has never seen this repo can implement T2.S1 from
(a) the complete, ready-to-paste `filter.sh` body, the renderer.sh diff, and the
three input-handler.sh branches in "Implementation Patterns & Key Details"
below; (b) the 10 findings in `research/backspace_nav_findings.md` — most
critically **FINDING 1** (caller contract: nav/backspace take `argv[1]` ONLY, no
char), **FINDING 2/3** (the renderer's exact filter algorithm to reproduce +
the decision to create `filter.sh` and refactor renderer.sh to use it), **FINDING
4** (backspace = filter+index+refresh ONLY — NO preview.sh call, per contract),
**FINDING 5** (nav logic: `L==0` guard, modulo wrap, `+L` to dodge bash's
negative-modulo quirk, index sanitize, preview delegation, order of ops), and
**FINDING 10** (the wrap/cycle/no-pollution mock); and (c) the socket-shim mock
that seeds 3 sessions, plants a `client-session-changed` canary, and asserts the
index cycles + the preview follows + the canary never fires. The INPUT
dependencies (`input-handler.sh` skeleton with the seam, `renderer.sh`, `preview.sh`,
`state.sh`, `utils.sh`) are ALL COMPLETE/present.

### Documentation & References

```yaml
# MUST READ — the file THIS task fills (the seam). COMPLETE (T1.S1).
- file: scripts/input-handler.sh
  why: T1.S1 CREATED this file with the `type` branch implemented and a COMBINED
        `backspace|next-session|prev-session)` seam that is a placeholder
        `return 0`. T2.S1 EDITS IT IN PLACE: adds `source filter.sh`, grows the
        `local` line, and SPLITS that combined branch into three implemented
        branches. Copy the skeleton's header/source-block/driver/CURRENT_DIR
        idiom verbatim; only the seam + local line + source line change.
  pattern: incremental-edit (mirror how restore.sh grew across P1.M5.T1→T4);
           ONE `local` line; `set -u` inherited; tabs; driver
           `input_main "$@" || exit 1` / `exit 0`.
  gotcha: the nav/backspace branches read ONLY `$1` (the action). Under `set -u`
          they must NOT reference `$2` (nav/backspace bindings pass no char —
          research FINDING 1). The `type` branch still reads `$2` as `char`.

# MUST READ — the file to REFACTOR (consume the shared filter). COMPLETE (P1.M2).
- file: scripts/renderer.sh
  why: (1) It contains the EXACT filter algorithm (render()'s inline loop) that
        filter.sh MUST reproduce byte-for-byte (research FINDING 2): `mapfile -t
        all < <(printf '%s' "$LIST")`; `low_filter="${FILTER,,}"`; per-name
        `low_name="${name,,}"`; `[[ "$low_name" == *"$low_filter"* ]]`;
        `filtered+=("$name")`. (2) It is the SECOND consumer of filter.sh — the
        refactor removes its inline copy so there is ONE filter in the repo.
  pattern: the mechanical diff is in "Implementation Patterns". Keep `mapfile -t
        all < <(printf '%s' "$LIST")` (for TOTAL) and the `render || printf
        error` fallback UNCHANGED. Trim `local TOTAL FLEN low_filter name
        low_name` → `local TOTAL FLEN`.
  critical: the renderer CLAMPS idx to [0,FLEN-1] and handles FLEN=0 ("no match")
        itself — nav does NOT need to replicate clamping (it computes modulo on
        a sanitized int and sets the raw new index; the renderer clamps on draw).
        But the FILTERED LENGTH `L` nav computes MUST equal the renderer's FLEN,
        which is why both call the same function.

# MUST READ — the shared filter helper, DECIDED here (research FINDING 3).
- docfile: plan/001_fd5d622d3939/P1M6T2S1/research/backspace_nav_findings.md
  why: FINDING 3 decides filter.sh (NOT utils.sh) as the home for
        lp_build_filtered, AND mandates refactoring renderer.sh to consume it
        (two copies would still drift — the contract demands ONE). Gives the
        canonical, ready-to-paste filter.sh body + the mechanical renderer diff.
  section: "FINDING 3 — DECISION: create scripts/filter.sh + refactor renderer.sh"

# MUST READ — the preview subsystem nav delegates to. COMPLETE (P1.M3.T1.S1+S2).
- file: scripts/preview.sh
  why: nav calls `"$CURRENT_DIR/preview.sh" "$target"`. argv[1]=candidate session
        name. It: reads `@livepicker-orig-session` (the driver); for S != driver
        resolves S's active window id; unlink-window the prior preview (no -k);
        link-window -a -s src_id -t "driver:"; select-window src_id; sets
        `@livepicker-linked-id`=src_id. The DUPLICATE GUARD (linked_id==src_id →
        skip unlink+link, just select) makes re-previewing the SAME session safe
        (the wrap case). Does NOT fire client-session-changed (Invariant A).
  critical: preview.sh is its OWN process under run-shell and sources its OWN
        lib trio — nav does NOT need to pass it any state. Guard the call
        `2>/dev/null || true` so a preview failure (session gone mid-nav) does
        NOT crash nav; the index still advances and the status redraws.

# MUST READ — the state accessors nav/backspace read+write through. COMPLETE.
- file: scripts/state.sh
  why: `get_state "$STATE_LIST" ""` / `get_state "$STATE_FILTER" ""` /
        `get_state "$STATE_INDEX" "0"` (reads, all defaulted for set -u);
        `set_state "$STATE_INDEX" "$new_idx"` / `set_state "$STATE_FILTER"
        "$new_filter"` (writes). readonly `STATE_LIST/STATE_FILTER/STATE_INDEX`.
        ALSO defines STATE_MODE/STATE_LINKED_ID/ORIG_* — which nav/backspace
        MUST NOT touch (preview owns linked-id; activate/restore own mode/orig).
  critical: nav writes ONLY STATE_INDEX; backspace writes STATE_FILTER +
        STATE_INDEX. Neither writes STATE_LIST (immutable for the picker —
        activate T2.S1 set it once) or STATE_LINKED_ID (preview.sh owns it).

# MUST READ — the caller contract (the bindings that invoke these actions). COMPLETE.
- file: scripts/livepicker.sh
  why: activate T4.S1 (COMPLETE) bound the keys VERBATIM (research FINDING 1):
        backspace  -> `run-shell "$CURRENT_DIR/input-handler.sh backspace"`
        next-session -> `run-shell "$CURRENT_DIR/input-handler.sh next-session"`
        prev-session -> `run-shell "$CURRENT_DIR/input-handler.sh prev-session"`
        i.e. argv is JUST the action (NO char, unlike `type`). So the
        nav/backspace branches read ONLY `$1`; under `set -u` they must not
        reference `$2`. Confirm at lines 211-212 / 224-225 / 228-229.
  section: the key-table bind block (lines ~209-230).

# MUST READ — the empirical ground-truth for THIS task (10 findings).
- docfile: plan/001_fd5d622d3939/P1M6T2S1/research/backspace_nav_findings.md
  why: FINDING 1 (caller contract — nav/backspace take argv[1] only); FINDING 2
        (the renderer's exact filter algorithm); FINDING 3 (decision: filter.sh
        + refactor renderer.sh); FINDING 4 (backspace = filter+index+refresh
        ONLY, no preview — contract); FINDING 5 (nav logic: L==0 guard, modulo
        wrap, +L for negative-modulo, index sanitize, preview delegation, order
        of ops); FINDING 6 (no tmux_refresh_client helper — bare `tmux
        refresh-client -S`); FINDING 7 (input-handler is its own process → source
        its own trio + filter.sh); FINDING 8 (seam-fill model: EDIT in place,
        split the combined branch); FINDING 9 (preview.sh contract recap);
        FINDING 10 (the wrap/cycle/no-pollution mock design).
  critical: Read BEFORE writing. FINDING 5 is the nav spec; FINDING 3 is the
        shared-filter decision; FINDING 4 prevents scope creep (no preview on
        backspace).

# MUST READ — the PRD sections selected for this work item.
- docfile: PRD.md
  why: §6 "Filtering" (backspace removes last char + refresh; renderer filters);
        §6 "Session navigation" (next/prev move index in the filtered list,
        wrapping, refresh preview + status, MUST NOT switch-client); §7 "The
        preview subsystem" (link-window live preview nav delegates to; the
        self-session edge + capture-pane fallback preview.sh handles); §5.2
        "Data flow" (the recompute-list step = renderer's filtered view, which
        filter.sh now powers); §11 "Configuration options" (the nav/backspace
        keys come from opt_*; the handler does NOT read config).
  section: "§6 Behaviors / Filtering", "§6 Behaviors / Session navigation",
           "§7 The preview subsystem", "§5 Architecture / Data flow",
           "§11 Configuration options"

# MUST READ — system ground-truth (Invariant A + shell style).
- docfile: plan/001_fd5d622d3939/architecture/system_context.md
  why: §3 INVARIANT A (preview navigation must NEVER call switch-client — it
        changes only the SHOWN window via link/select-window, which fire
        session-window-changed [suppressed] but never client-session-changed);
        §9 shell style (set -u ONLY, NO -e/pipefail; tabs; `local` for all
        function locals; quote everything; no source-time side effects in libs).
  section: "§3 INVARIANT A", "§9 Shell style"

# MUST READ — primitive verification (refresh-client -S re-runs #()).
- docfile: plan/001_fd5d622d3939/architecture/tmux_primitives.md
  why: §3 — `refresh-client -S` forces an immediate status redraw that
        re-evaluates `#()` (so the renderer re-highlights the new index after
        nav/backspace). Requires a client; guard `2>/dev/null || true`.
  section: "§3 status-format[n], #(), refresh-client -S"
```

### Current Codebase tree

```bash
tmux-livepicker/
  PRD.md
  plugin.tmux                 # COMPLETE. Unchanged.
  plan/001_fd5d622d3939/{architecture/*.md, tasks.json, prd_snapshot.md, prd_index.txt}
  plan/001_fd5d622d3939/P1M6T1S1/{PRP.md, research/input_handler_type_findings.md}   # CREATED input-handler.sh
  plan/001_fd5d622d3939/P1M6T2S1/{PRP.md, research/backspace_nav_findings.md}        # THIS
  scripts/
    options.sh   # COMPLETE. Unchanged. (nav/backspace keys come from opt_*; handler reads none.)
    utils.sh     # COMPLETE. Unchanged. (NO tmux_refresh_client — bare `tmux refresh-client -S`.)
    state.sh     # COMPLETE. Unchanged. (STATE_LIST/FILTER/INDEX + set_state/get_state — INPUT deps.)
    renderer.sh  # COMPLETE (P1.M2).  EDIT (this task): source filter.sh + consume lp_build_filtered.
    preview.sh   # COMPLETE (P1.M3).  Unchanged. (nav DELEGATES to it; argv[1]=session name.)
    livepicker.sh   # COMPLETE (P1.M4). Unchanged. (T4.S1 bound nav/backspace keys — the CALLER.)
    restore.sh   # COMPLETE (P1.M5).  Unchanged. (skeleton + incremental-edit model.)
    input-handler.sh  # COMPLETE skeleton (P1.M6.T1.S1). EDIT (this task): source filter.sh +
                      #   grow local line + split the combined backspace|next-session|prev-session)
                      #   seam into three implemented branches. confirm/cancel seams stay.
    filter.sh    # DOES NOT EXIST YET. THIS task CREATES it (the shared lp_build_filtered).
  .gitignore
  # NOTE: NO test harness yet (P1.M7). Validate via the throwaway socket-shim mock
  #       (MUST keep an attached client so refresh-client -S works; MUST plant a
  #       client-session-changed canary to prove Invariant A — research FINDING 10).
```

### Desired Codebase tree with files to be added and responsibility of file

```bash
tmux-livepicker/
  scripts/
    options.sh        # unchanged.
    utils.sh          # unchanged.
    state.sh          # unchanged.
    renderer.sh       # EDITED: sources filter.sh; render() calls lp_build_filtered instead of the
                      #   inline loop; locals trimmed. Behavior byte-identical (single source of truth).
    preview.sh        # unchanged.
    livepicker.sh     # unchanged.
    restore.sh        # unchanged.
    input-handler.sh  # EDITED: sources filter.sh; local line grown; three separate branches
                      #   (backspace trims filter + index=0 + refresh; next/prev wrap-modulo
                      #   index + preview.sh + refresh, no switch-client). confirm/cancel seams stay.
    filter.sh         # NEW. Sourced library. Defines lp_build_filtered LIST FILTER — the SINGLE
                      #   filter function shared by renderer.sh (#() status) and input-handler.sh
                      #   (nav index resolution) so filtered[index] matches the renderer's ordering
                      #   exactly (PRD §6 + work-item CONTRACT point 1).
```

### Known Gotchas of our codebase & Library Quirks

```bash
# CRITICAL (research FINDING 1 — caller contract): backspace/next-session/
#   prev-session are bound VERBATIM as `run-shell "$CURRENT_DIR/input-handler.sh
#   backspace"` (next-session/prev-session likewise) — argv is JUST the action,
#   NO char (unlike `type`, which passes `$lp_c` as argv[2]). So the nav/backspace
#   branches read ONLY `$1`. Under `set -u` they MUST NOT reference `$2` (it is
#   unset for these actions → would crash). The `type` branch still reads `$2`.

# CRITICAL (research FINDING 3 + work-item CONTRACT point 1 — shared filter):
#   there must be EXACTLY ONE filter function in the repo. Creating filter.sh is
#   not enough — renderer.sh keeps its own inline copy, which would drift. So
#   T2.S1 ALSO refactors renderer.sh to consume lp_build_filtered. After this
#   task, `grep -rn 'low_name\|low_filter=' scripts/` matches ONLY filter.sh.

# CRITICAL (research FINDING 4 — backspace does NOT call preview.sh): the
#   work-item §3 contract for backspace lists ONLY: set filter, set index=0,
#   refresh. There is NO preview.sh call. (Shortening the filter can re-admit a
#   match at index 0 whose preview differs from the current one — a known minor
#   UX gap that re-syncs on the next nav/confirm. Do NOT add a preview call: it
#   diverges from the contract and risks scope creep. If a reviewer wants it,
#   it is a FUTURE task.) backspace = `${old%?}` + index=0 + refresh ONLY.

# CRITICAL (research FINDING 5 + PRD §6 + Invariant A): nav MUST NOT call
#   switch-client. It (1) re-filters via the shared helper → length L; (2) if
#   L==0, no-op (return 0 — never divide by zero); (3) else wrap-modulo the
#   index — next: `(index+1)%L`; prev: `(index-1+L)%L` (the `+L` dodges bash's
#   negative-modulo quirk, where `%` can return negatives for negative operands);
#   (4) set the NEW index; (5) resolve target=filtered[new_idx]; (6) call
#   preview.sh (link/select-window — fires session-window-changed [suppressed],
#   NEVER client-session-changed); (7) refresh-client -S.

# CRITICAL (research FINDING 5 — index sanitize): @livepicker-index is a STRING
#   read from an option. Defensively coerce to a non-negative int before the
#   modulo: `[[ "$cur_index" =~ ^[0-9]+$ ]] || cur_index=0`. (The renderer also
#   clamps on draw, but nav must compute modulo on a sane int.)

# GOTCHA (research FINDING 5 — order of ops): set the NEW index FIRST, then
#   resolve target from the filtered list at the NEW index, then call
#   preview.sh, then refresh-client -S. So the renderer redraw shows the new
#   highlight AND the live preview shows the new session — both consistent.

# GOTCHA (research FINDING 6): there is NO tmux_refresh_client helper in
#   utils.sh. House style (mirror restore.sh STEP 6c / T1.S1 `type` branch)
#   permits a DIRECT bare `tmux refresh-client -S 2>/dev/null || true` for this
#   one-off primitive. Do NOT add a utils helper.

# GOTCHA (research FINDING 7): input-handler.sh is its OWN process under
#   run-shell → it MUST source its OWN lib trio AND filter.sh. Sourced state
#   does NOT cross process boundaries. Source order: options → utils → state →
#   filter (the trio order is load-bearing — state.sh needs utils.sh; filter.sh
#   has no deps, so appending it last is safe).

# GOTCHA (research FINDING 8 — EDIT in place, do NOT recreate): T1.S1 CREATED
#   input-handler.sh. T2.S1 EDITS it: grow the `local` line, add one source
#   line, SPLIT the combined `backspace|next-session|prev-session)` branch into
#   three. PRESERVE the `type` branch, the confirm/cancel seams, the `*) return
#   0`, the header, and the driver verbatim. This is the SAME incremental-edit
#   model P1.M5 used to grow restore.sh across T1→T4.

# GOTCHA (research FINDING 9 — preview.sh is a clean delegation): nav does NOT
#   re-implement any link/unlink logic. preview.sh's DUPLICATE GUARD
#   (linked_id==src_id → skip unlink+link, just select) makes re-previewing the
#   SAME session safe (the single-match / wrap case). Guard the call
#   `"$CURRENT_DIR/preview.sh" "$target" 2>/dev/null || true` so a preview
#   failure (session gone mid-nav) never crashes nav.

# GOTCHA (filter.sh round-trip): the helper `printf '%s\n' "$name"` per match;
#   the caller `mapfile -t filtered < <(lp_build_filtered ...)` strips the
#   trailing newline → `["alpha","beta"]`, IDENTICAL to renderer.sh's prior
#   `filtered+=("$name")` accumulation. Empty LIST → `all=()` → loop body never
#   runs → no output → caller `filtered=()`. Empty FILTER → `*""*` matches all.

# CRITICAL: NO `set -e`, NO `set -o pipefail` (house style; system_context §9).
#   refresh-client / preview.sh legitimately return non-zero on edge cases; under
#   set -e that would abort mid-keystroke. `set -u` is inherited from the sourced
#   libs — do NOT re-declare it.

# STYLE (system_context §9): indent with TABS. Verify with `grep -Pn '^    '
#   scripts/{filter,renderer,input-handler}.sh` (expect empty). shfmt is NOT
#   installed. filter.sh must be a SOURCED LIBRARY (NO `*_main` execution, NO
#   driver `"$@"` call at the bottom — sourcing it must be a pure no-op).
```

## Implementation Blueprint

### Data models and structure

No new data model. T2.S1 adds NO new state keys and NO new options — it reads
and writes EXISTING `@livepicker-*` keys via the state.sh accessors, and
introduces ONE pure shell function (`lp_build_filtered`) with no state.

- **READ (nav):** `@livepicker-list`, `@livepicker-filter`, `@livepicker-index`.
- **READ (backspace):** `@livepicker-filter`.
- **WRITE (nav):** `@livepicker-index` (the wrapped new index).
- **WRITE (backspace):** `@livepicker-filter` (trimmed), `@livepicker-index` (`0`).
- **DELEGATE (nav):** `preview.sh "$target"` (writes `@livepicker-linked-id`
  internally — nav does NOT touch it directly).

The function locals input-handler.sh grows (declared in ONE `local` line):
`action` (argv[1]), `char` (argv[2], type only), `new_filter` (type/backspace),
`cur_filter` `cur_list` `cur_index` (the state reads), `L` (filtered length),
`new_idx` (the wrapped index), `target` (the session at new_idx), and
`local -a filtered=()` (the shared-filter output).

### Implementation Tasks (ordered by dependencies)

```yaml
Task 1: CREATE scripts/filter.sh — the shared filtered-list builder
  - FILE: ./scripts/filter.sh  (NEW; does NOT need +x — it is SOURCED, never exec'd).
  - WRITE: the complete file from "Implementation Patterns & Key Details" below
        (header + `# shellcheck disable=SC1091` + `set -u` + ONE function
        lp_build_filtered). NO driver, NO `*_main "$@"`, NO source-time side
        effects (sourcing it is a pure no-op).
  - VERIFY: bash -n + shellcheck (0 findings; only disable=SC1091).

Task 2: EDIT scripts/renderer.sh — consume the shared filter (behavior-preserving)
  - EDIT 1: after the `source "$CURRENT_DIR/state.sh"` line, add:
            # shellcheck source=filter.sh
            source "$CURRENT_DIR/filter.sh"
  - EDIT 2: in render(), REPLACE the inline filter block:
            low_filter="${FILTER,,}"
            for name in "${all[@]}"; do
                low_name="${name,,}"
                if [[ "$low_name" == *"$low_filter"* ]]; then
                    filtered+=("$name")
                fi
            done
            FLEN="${#filtered[@]}"
        WITH:
            mapfile -t filtered < <(lp_build_filtered "$LIST" "$FILTER")
            FLEN="${#filtered[@]}"
  - EDIT 3: trim the locals line `local TOTAL FLEN low_filter name low_name`
        to `local TOTAL FLEN`.
  - PRESERVE: the `mapfile -t all < <(printf '%s' "$LIST")` + TOTAL line (for
        the count denominator), the highlight/count/style emission, the
        `render || printf '#[fg=red]...'` fallback, the driver. Byte-identical
        behavior is the proof the refactor is correct.
  - DO NOT: change any other line; touch @livepicker-* state; add set -e.

Task 3: EDIT scripts/input-handler.sh — source filter.sh + grow local + split the seam
  - EDIT 1: after the `source "$CURRENT_DIR/state.sh"` line, add:
            # shellcheck source=filter.sh
            source "$CURRENT_DIR/filter.sh"
  - EDIT 2: grow the `local` line:
        BEFORE: local action char new_filter
        AFTER:  local action char new_filter cur_filter cur_list cur_index L new_idx target
        and add a new line right after it:  local -a filtered=()
  - EDIT 3: REPLACE the combined seam branch:
        backspace|next-session|prev-session)
            return 0
            ;;
        WITH the THREE separate, fully-implemented branches in "Implementation
        Patterns & Key Details" (backspace / next-session / prev-session).
  - PRESERVE: the `type)` branch (T1.S1, UNCHANGED), the `confirm)` seam (T3),
        the `cancel)` seam (T4), the `*) return 0` default, the header, the driver.
  - DO NOT: reference `$2` in the nav/backspace branches (set -u; FINDING 1);
        call switch-client / new-session / set-hook; mutate @livepicker-list /
        @livepicker-mode / @livepicker-linked-id / any @livepicker-orig-*; add
        a preview.sh call to backspace (FINDING 4); add set -e.

Task 4: VALIDATE (Level 1 syntax/lint on all 3 files + Level 2 socket-shim mock:
      shared-filter identity, renderer byte-identity, backspace trim, next/prev
      wrap + preview cycle + client-session-changed canary never fires + L==0 no-op)
  - RUN the socket-shim mock (Validation Loop §2). Self-cleaning, isolated
        socket, attached client (refresh-client -S needs one), client-session-
        changed canary (Invariant A). Calls the REAL input-handler.sh, the REAL
        renderer.sh, and the REAL preview.sh.
```

### Implementation Patterns & Key Details

#### Task 1 — the complete `scripts/filter.sh` (indent is ONE tab)

```bash
#!/usr/bin/env bash
# shellcheck disable=SC1091
#   SC1091: this is a SOURCED library; callers source it via $CURRENT_DIR.
# scripts/filter.sh — tmux-livepicker shared filtered-list builder.
#
# Sourced library (NOT executed). NO source-time side effects — sourcing this
# file defines lp_build_filtered and nothing else (no driver, no *_main call).
# Consumed by BOTH:
#   - scripts/renderer.sh   (the #() status filter+highlight view), and
#   - scripts/input-handler.sh (nav's filtered[index] resolution + length L)
# so there is EXACTLY ONE filter in the repo (PRD §6 + work-item CONTRACT
# point 1: "share a single filter function ... to avoid drift"). The algorithm
# is byte-identical to what renderer.sh used inline (research FINDING 2/3).

set -u   # NOT -e; NOT -o pipefail.

# lp_build_filtered LIST FILTER
#   Print each name from LIST (newline-separated) that case-insensitively
#   contains FILTER (substring), one per line, PRESERVING original order+case.
#   Empty FILTER matches all names. Empty LIST prints nothing.
#   Caller does:  mapfile -t filtered < <(lp_build_filtered "$LIST" "$FILTER")
#   which yields the SAME array renderer.sh used to build via filtered+=("$name").
lp_build_filtered() {
	local LIST="${1:-}"
	local FILTER="${2:-}"
	local -a all=()
	local low_filter name low_name
	# printf '%s' (NO trailing newline): empty LIST -> all=() (NOT [""]); a
	# trailing newline in LIST is harmless (mapfile -t strips it).
	mapfile -t all < <(printf '%s' "$LIST")
	# Case-insensitive substring: lowercase BOTH sides; empty filter -> *""*
	# matches everything (so nav works with no query typed — PRD §6).
	low_filter="${FILTER,,}"
	for name in "${all[@]}"; do
		low_name="${name,,}"
		if [[ "$low_name" == *"$low_filter"* ]]; then
			printf '%s\n' "$name"
		fi
	done
}
```

#### Task 2 — the renderer.sh diff (mechanical; behavior-preserving)

Add the source (right after the `source "$CURRENT_DIR/state.sh"` line):
```bash
# shellcheck source=filter.sh
source "$CURRENT_DIR/filter.sh"
```
In `render()`, change the locals line:
```bash
# BEFORE:
	local TOTAL FLEN low_filter name low_name
# AFTER:
	local TOTAL FLEN
```
In `render()`, replace the inline filter loop with:
```bash
	mapfile -t filtered < <(lp_build_filtered "$LIST" "$FILTER")
	FLEN="${#filtered[@]}"
```
(Keep the preceding `mapfile -t all < <(printf '%s' "$LIST")` + `TOTAL="${#all[@]}"`
untouched — TOTAL is the count denominator for the empty-filter case.)

#### Task 3 — the THREE input-handler.sh branches (indent is ONE tab)

These REPLACE the combined `backspace|next-session|prev-session)` seam. The
`type)` branch above them and the `confirm)`/`cancel)` seams + `*) return 0`
below them stay UNCHANGED.

```bash
		backspace)
			# --- P1.M6.T2.S1: trim the last char off the query, reset the
			#     highlight to the top filtered match, force a status redraw.
			# PRD §6 Filtering: "Backspace removes the last character. After
			# each change, run tmux refresh-client -S ..." The renderer does the
			# filtering + highlighting — the handler only trims filter/index +
			# refresh (research FINDING 2/4).
			# CONTRACT (work-item §3): backspace = filter+index+refresh ONLY.
			# It does NOT call preview.sh (FINDING 4) — the top match is already
			# shown; shortening the filter may re-admit a different top match
			# (a known minor UX gap that re-syncs on the next nav/confirm).
			cur_filter="$(get_state "$STATE_FILTER" "")"
			# ${var%?} removes the shortest trailing match of one char. On an
			# empty var it yields "" (no error, no set -u issue). Guard empty
			# so the write is an explicit no-op when nothing is left to erase.
			if [ -n "$cur_filter" ]; then
				new_filter="${cur_filter%?}"
				set_state "$STATE_FILTER" "$new_filter"
			fi
			# Reset the highlight to the top filtered match (PRD §6). Always
			# safe — the renderer clamps + handles FLEN=0 itself.
			set_state "$STATE_INDEX" "0"
			# Force the #() renderer to re-run (PRD §10/§16). Guard the detached
			# edge (FINDING 3; mirror the `type` branch / restore.sh STEP 6c).
			tmux refresh-client -S 2>/dev/null || true
			return 0
			;;
		next-session)
			# --- P1.M6.T2.S1: move the highlight DOWN within the FILTERED list
			#     (wrapping), refresh the live preview + the status renderer.
			# PRD §6 Session navigation: "next-session ... moves @livepicker-index
			# within the filtered list (wrapping). Each move refreshes the
			# preview (section 7) and the status renderer. Navigation must not
			# call switch-client." (Invariant A — PRD §4 / system_context §3.)
			# Re-filter via the SAME function the renderer uses (work-item
			# CONTRACT point 1; research FINDING 2/3) so L == the renderer's FLEN
			# and filtered[new_idx] is the session the renderer will highlight.
			cur_list="$(get_state "$STATE_LIST" "")"
			cur_filter="$(get_state "$STATE_FILTER" "")"
			mapfile -t filtered < <(lp_build_filtered "$cur_list" "$cur_filter")
			L="${#filtered[@]}"
			# Nothing matches -> no-op (never divide by zero; FINDING 5).
			[ "$L" -eq 0 ] && return 0
			# Sanitize the stored index to a non-negative int (it is a STRING
			# option; FINDING 5) before the modulo.
			cur_index="$(get_state "$STATE_INDEX" "0")"
			[[ "$cur_index" =~ ^[0-9]+$ ]] || cur_index=0
			# Wrap modulo L (PRD §6 "wrapping"). No +L needed for next.
			new_idx=$(( (cur_index + 1) % L ))
			# Set the NEW index FIRST, resolve the target at it, THEN preview +
			# refresh (so the highlight + the live preview agree — FINDING 5).
			set_state "$STATE_INDEX" "$new_idx"
			target="${filtered[$new_idx]}"
			# Delegate the live link/select to preview.sh (P1.M3; FINDING 9). It
			# fires session-window-changed (suppressed by activate T4.S2) but
			# NEVER client-session-changed (Invariant A). Guard a mid-nav failure
			# (session gone) so nav still advances + redraws.
			"$CURRENT_DIR/preview.sh" "$target" 2>/dev/null || true
			tmux refresh-client -S 2>/dev/null || true
			return 0
			;;
		prev-session)
			# --- P1.M6.T2.S1: move the highlight UP within the FILTERED list
			#     (wrapping, reverse). Mirror of next-session.
			cur_list="$(get_state "$STATE_LIST" "")"
			cur_filter="$(get_state "$STATE_FILTER" "")"
			mapfile -t filtered < <(lp_build_filtered "$cur_list" "$cur_filter")
			L="${#filtered[@]}"
			[ "$L" -eq 0 ] && return 0
			cur_index="$(get_state "$STATE_INDEX" "0")"
			[[ "$cur_index" =~ ^[0-9]+$ ]] || cur_index=0
			# Wrap modulo L (PRD §6). The +L dodges bash's negative-modulo quirk
			# (bash `%` can return negatives for negative operands — FINDING 5).
			new_idx=$(( (cur_index - 1 + L) % L ))
			set_state "$STATE_INDEX" "$new_idx"
			target="${filtered[$new_idx]}"
			"$CURRENT_DIR/preview.sh" "$target" 2>/dev/null || true
			tmux refresh-client -S 2>/dev/null || true
			return 0
			;;
```

NOTE for the implementer:
- This is an EDIT-IN-PLACE (T1.S1 created the file). Do NOT recreate it. Apply
  the three edits in Task 3 precisely; leave the rest byte-identical.
- The nav/backspace branches read ONLY `$1` (research FINDING 1) — never `$2`.
- backspace does NOT call preview.sh (research FINDING 4 — contract). Do NOT
  add one "to keep the preview in sync"; that diverges from the contract.
- `local -a filtered=()` is declared ONCE at the top of `input_main` and reused
  by both nav branches (they each re-`mapfile` it). `mapfile` overwrites the
  array (does not append), so reuse is safe.
- `L` (filtered length) MUST come from `lp_build_filtered` — never re-implement
  the filter inline (that is the drift the contract forbids).
- Wrap: next `(cur_index + 1) % L`; prev `(cur_index - 1 + L) % L`. The `+L` is
  load-bearing for prev (negative-modulo dodge).
- preview.sh call is guarded `2>/dev/null || true` (session-gone mid-nav must
  not crash nav); refresh-client likewise.

### Integration Points

```yaml
NEW FILE (what this task creates):
  - scripts/filter.sh: SOURCED library; defines lp_build_filtered LIST FILTER.
        Consumed by renderer.sh + input-handler.sh (the SINGLE filter).

EDITED FILES (what this task modifies):
  - scripts/renderer.sh: sources filter.sh; render() calls lp_build_filtered
        instead of the inline loop; locals trimmed. Behavior byte-identical.
  - scripts/input-handler.sh: sources filter.sh; local line grown; three
        separate branches (backspace / next-session / prev-session). confirm/
        cancel seams + type branch + driver unchanged.

CALLERS (the bindings that invoke these actions — COMPLETE siblings):
  - activate T4.S1 (P1.M4.T4.S1): bound `run-shell "$CURRENT_DIR/input-handler.sh
        backspace|next-session|prev-session"` (argv is JUST the action — FINDING 1).

CONSUMERS (what these branches feed):
  - scripts/renderer.sh: re-runs on refresh-client -S, re-reads the (wrapped)
        @livepicker-index, re-highlights via the SAME filter → consistent.
  - scripts/preview.sh: nav DELEGATES to it (argv[1]=session name). It links the
        candidate's window live (no switch-client — Invariant A) and sets
        @livepicker-linked-id.
  - P1.M6.T3/T4 (PLANNED): fill the confirm/cancel seams in input-handler.sh.

STATE READS (this task):
  - @livepicker-list    (nav only; via get_state "$STATE_LIST" "")
  - @livepicker-filter  (nav + backspace; via get_state "$STATE_FILTER" "")
  - @livepicker-index   (nav only; via get_state "$STATE_INDEX" "0")

STATE WRITES (this task):
  - @livepicker-index   (nav: wrapped new_idx; backspace: "0"; via set_state)
  - @livepicker-filter  (backspace only: trimmed; via set_state)

TMUX MUTATIONS (this task):
  - refresh-client -S   (status redraw after each action; || true; re-runs #())

DELEGATED (this task calls, does not own):
  - preview.sh "$target" (nav only; link/select-window; sets @livepicker-linked-id)

DATABASE / MIGRATIONS / ROUTES / CONFIG: none.
```

## Validation Loop

### Level 1: Syntax & Style (Immediate Feedback)

```bash
# Run after each file change — fix before proceeding.
bash -n scripts/filter.sh && bash -n scripts/renderer.sh && bash -n scripts/input-handler.sh
shellcheck scripts/filter.sh scripts/renderer.sh scripts/input-handler.sh
#   expect 0 findings beyond the file-level disables (filter.sh: SC1091;
#   renderer.sh + input-handler.sh: SC1091,SC2153).

# Tabs-not-spaces sanity (shfmt NOT installed):
grep -Pn '^    ' scripts/filter.sh scripts/renderer.sh scripts/input-handler.sh \
  && echo "FAIL: 4-space indent found, use tabs" || echo "OK: tabs only"

# Confirm house style (set -u only; NO -e / NO pipefail DECLARED in these files):
grep -n 'set -e\|set -o pipefail' scripts/filter.sh scripts/renderer.sh scripts/input-handler.sh \
  && echo "FAIL: set -e/pipefail present" || echo "OK: set -u inherited/declared only"

# filter.sh is a SOURCED LIBRARY (NO driver, NO execution at source time):
grep -n 'lp_build_filtered "\$@"\|_main "\$@"' scripts/filter.sh \
  && echo "FAIL: filter.sh must NOT execute anything at source time" || echo "OK: pure library"

# Shared filter = SINGLE source of truth (the contract's whole point):
grep -rn 'low_name\|low_filter=' scripts/ | grep -v 'scripts/filter.sh' \
  && echo "FAIL: filter logic exists OUTSIDE filter.sh (drift risk)" || echo "OK: one filter (filter.sh)"
grep -n 'lp_build_filtered' scripts/renderer.sh       # expect 1 (the refactor)
grep -n 'lp_build_filtered' scripts/input-handler.sh  # expect 2 (next + prev)

# renderer.sh refactor is mechanical (locals trimmed, source added):
grep -n 'source "$CURRENT_DIR/filter.sh"' scripts/renderer.sh      # expect 1 (after state.sh)
grep -n 'mapfile -t filtered < <(lp_build_filtered' scripts/renderer.sh  # expect 1
grep -n 'low_filter\|low_name' scripts/renderer.sh \
  && echo "FAIL: renderer still has inline filter locals" || echo "OK: renderer consumes filter.sh"

# input-handler.sh edits (source + local line + 3 branches):
grep -n 'source "$CURRENT_DIR/filter.sh"' scripts/input-handler.sh           # expect 1
grep -n 'local action char new_filter cur_filter cur_list cur_index L new_idx target' scripts/input-handler.sh  # expect 1
grep -n 'local -a filtered=()' scripts/input-handler.sh                      # expect 1
grep -n '^\t\tbackspace)' scripts/input-handler.sh                           # expect 1
grep -n '^\t\tnext-session)' scripts/input-handler.sh                        # expect 1
grep -n '^\t\tprev-session)' scripts/input-handler.sh                        # expect 1
# backspace does NOT call preview.sh (FINDING 4) — check the backspace branch only:
awk '/^\t\tbackspace\)/,/^\t\t;;/' scripts/input-handler.sh | grep -n 'preview.sh' \
  && echo "FAIL: backspace must NOT call preview.sh (FINDING 4)" || echo "OK: backspace = filter+index+refresh"

# Preserved seams + default + type branch:
grep -n 'P1.M6.T3.S1 seam' scripts/input-handler.sh   # expect 1 (confirm)
grep -n 'P1.M6.T4.S1 seam' scripts/input-handler.sh   # expect 1 (cancel)
grep -n '^\t\t\*)' scripts/input-handler.sh           # expect 1 (default return 0)
grep -n 'char="\${2:-}"' scripts/input-handler.sh     # expect 1 (type branch unchanged)

# Invariant A — NO switch-client / new-session / set-hook anywhere in input-handler.sh:
grep -n 'switch-client\|new-session\|set-hook' scripts/input-handler.sh \
  && echo "FAIL: nav/backspace must not switch-client (Invariant A)" || echo "OK: no switch-client"
# Run from the repo root.
```

### Level 2: Socket-Shim Mock Validation — shared-filter identity + renderer byte-identity + backspace trim + nav wrap/cycle/no-pollution

Reuses the PATH-wrapper socket shim. Self-cleaning. Seeds a `driver` + 3 detached
candidate sessions, seeds picker state as activate would, plants a
`client-session-changed` canary, attaches a client (refresh-client -S needs one),
then exercises the REAL input-handler.sh + renderer.sh + preview.sh. Asserts:
shared filter matches renderer; renderer output byte-identical before/after the
refactor; backspace trims + resets index; next×3 wraps 0→1→2→0 with the preview
cycling alpha→beta→gamma→alpha; prev×3 wraps 0→2→1→0; L==0 no-op; and the
`client-session-changed` canary NEVER fires (Invariant A).

```bash
#!/usr/bin/env bash
# Throwaway socket-shim validation for P1.M6.T2.S1 (do NOT commit).
set -u
REPO_ROOT="$(cd "$(dirname "$0")" && pwd)"
for f in filter renderer input-handler preview state utils options; do
	[ -f "$REPO_ROOT/scripts/$f.sh" ] || { echo "MISSING scripts/$f.sh"; exit 1; }
done

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
	rm -rf "$SHIM_DIR"
}
trap cleanup EXIT

pass=0; fail=0
assert() { if [ "$2" = "$3" ]; then pass=$((pass+1)); printf 'ok   %s\n' "$1"; else fail=$((fail+1)); printf 'FAIL %s: got=[%s] want=[%s]\n' "$1" "$2" "$3"; fi; }
attach() { TMUX="" script -qec "tmux -L $SOCK attach -t $1" /dev/null >/dev/null 2>&1 & AP=$!; sleep 0.5; }
detach() { kill "$AP" 2>/dev/null; wait "$AP" 2>/dev/null; }
wid() { tmux list-windows -t "=$1" -F '#{window_id}' -f '#{window_active}'; }  # active window id of session $1

# ---------- setup: driver + 3 candidates ----------
tmux new-session -d -s driver -x 120 -y 40
for s in alpha beta gamma; do tmux new-session -d -s "$s" -x 120 -y 40; done
attach driver   # refresh-client -S needs an attached client (FINDING 3)

# Seed picker state exactly as activate T2.S1/T5.S1 would.
tmux set-option -g "@livepicker-list"          $'alpha\nbeta\ngamma'
tmux set-option -g "@livepicker-filter"        ""
tmux set-option -g "@livepicker-index"         "0"
tmux set-option -g "@livepicker-mode"          "on"
tmux set-option -g "@livepicker-preview-mode"  "live"
tmux set-option -g "@livepicker-orig-session"  "driver"
tmux set-option -g "@livepicker-orig-window"   "$(wid driver)"
tmux set-option -g "@livepicker-linked-id"     ""

# Invariant A canary: client-session-changed must NEVER fire (no switch-client).
tmux set-option -g "@lp-csc-fired" "0"
tmux set-hook -g client-session-changed "set-option -g @lp-csc-fired 1"

# ---------- shared-filter identity: renderer == lp_build_filtered ordering ----------
# (renderer.sh now consumes lp_build_filtered; verify the filtered VIEW matches.)
tmux set-option -g status-format\[0\] "#($REPO_ROOT/scripts/renderer.sh)" >/dev/null 2>&1
tmux set-option -g "@livepicker-filter" "a"   # matches alpha + gamma (case-insensitive)
OUT="$(bash "$REPO_ROOT/scripts/renderer.sh")"
printf 'renderer(filter=a): %s\n' "$OUT"
assert "renderer shows alpha" "$(printf '%s' "$OUT" | grep -c 'alpha')" "1"
assert "renderer shows gamma" "$(printf '%s' "$OUT" | grep -c 'gamma')" "1"
assert "renderer hides beta"  "$(printf '%s' "$OUT" | grep -c 'beta')"  "0"
# renderer byte-identity: the refactor did not change output for a known case.
tmux set-option -g "@livepicker-filter" ""
OUT_ALL="$(bash "$REPO_ROOT/scripts/renderer.sh")"
assert "renderer(all) highlights alpha(idx0)" "$(printf '%s' "$OUT_ALL" | grep -c 'bg=yellow]alpha')" "1"

# ---------- next-session x3: wrap 0->1->2->0, preview cycles, canary clean ----------
tmux set-option -g "@livepicker-filter" ""   # L=3
tmux set-option -g "@livepicker-index"  "0"
tmux set-option -g "@livepicker-linked-id" ""
EXP_IDX=0
for step in 1 2 3; do
	bash "$REPO_ROOT/scripts/input-handler.sh" next-session
	EXP_IDX=$(( (EXP_IDX + 1) % 3 ))
	assert "next#$step index" "$(tmux show-option -gqv '@livepicker-index')" "$EXP_IDX"
	# the previewed session = the candidate now at the new index
	case "$EXP_IDX" in 0) EXP=alpha;; 1) EXP=beta;; 2) EXP=gamma;; esac
	assert "next#$step linked-id == $EXP active window" "$(tmux show-option -gqv '@livepicker-linked-id')" "$(wid "$EXP")"
	assert "next#$step client-session-changed NOT fired" "$(tmux show-option -gqv '@lp-csc-fired')" "0"
done
assert "after 3 nexts index wrapped to 0" "$(tmux show-option -gqv '@livepicker-index')" "0"

# ---------- prev-session x3: reverse wrap 0->2->1->0 ----------
EXP_IDX=0
for step in 1 2 3; do
	bash "$REPO_ROOT/scripts/input-handler.sh" prev-session
	EXP_IDX=$(( (EXP_IDX - 1 + 3) % 3 ))
	assert "prev#$step index" "$(tmux show-option -gqv '@livepicker-index')" "$EXP_IDX"
	case "$EXP_IDX" in 0) EXP=alpha;; 1) EXP=beta;; 2) EXP=gamma;; esac
	assert "prev#$step linked-id == $EXP active window" "$(tmux show-option -gqv '@livepicker-linked-id')" "$(wid "$EXP")"
	assert "prev#$step client-session-changed NOT fired" "$(tmux show-option -gqv '@lp-csc-fired')" "0"
done

# ---------- backspace: trims last char, resets index to 0 ----------
tmux set-option -g "@livepicker-filter" "abc"
tmux set-option -g "@livepicker-index"  "2"
bash "$REPO_ROOT/scripts/input-handler.sh" backspace
assert "backspace trims filter" "$(tmux show-option -gqv '@livepicker-filter')" "ab"
assert "backspace resets index" "$(tmux show-option -gqv '@livepicker-index')"  "0"
# backspace on empty is a no-op (guard empty; FINDING 4)
tmux set-option -g "@livepicker-filter" ""
tmux set-option -g "@livepicker-index"  "0"
bash "$REPO_ROOT/scripts/input-handler.sh" backspace
assert "backspace empty: filter stays empty" "$(tmux show-option -gqv '@livepicker-filter')" ""
assert "backspace empty: index stays 0"      "$(tmux show-option -gqv '@livepicker-index')"  "0"
# backspace never fires client-session-changed
assert "backspace client-session-changed NOT fired" "$(tmux show-option -gqv '@lp-csc-fired')" "0"

# ---------- L==0 guard: filter matches nothing -> next is a no-op ----------
tmux set-option -g "@livepicker-filter" "zzz"
tmux set-option -g "@livepicker-index"  "0"
LID_BEFORE="$(tmux show-option -gqv '@livepicker-linked-id')"
bash "$REPO_ROOT/scripts/input-handler.sh" next-session
assert "L==0 next: index unchanged" "$(tmux show-option -gqv '@livepicker-index')" "0"
assert "L==0 next: linked-id unchanged" "$(tmux show-option -gqv '@livepicker-linked-id')" "$LID_BEFORE"
assert "L==0 next: client-session-changed NOT fired" "$(tmux show-option -gqv '@lp-csc-fired')" "0"

detach
echo "=========================================="
echo "pass=$pass fail=$fail"
[ "$fail" -eq 0 ] && echo "ALL GREEN" || echo "HAS FAILURES"
exit "$fail"
```

### Level 3: Integration Testing (System Validation)

```bash
# input-handler.sh's nav/backspace are invoked by tmux's livepicker key table
# (activate T4.S1). Full end-to-end (activate -> type -> next/prev -> live preview
# swaps -> backspace widens) is exercised by the P1.M7 functional + pollution
# test harness (PLANNED). For T2.S1, the Level 2 mock covers the contract
# directly (wrap/cycle/no-pollution + backspace + L==0 + shared-filter identity).

# Optional manual smoke against the LIVE picker (AFTER the socket mock passes):
# set @livepicker-key, activate, type a filter, press j/k — the status highlight
# should move and the live preview should swap panes; press BSpace — the query
# shrinks. Then cancel and confirm the client's session/history is unchanged.
# (Not required for T2.S1 success; the mock is authoritative — but this is the
#  most convincing Invariant A check.)
```

### Level 4: Creative & Domain-Specific Validation

```bash
# (Domain-specific for this plugin = PRD §15 functional/pollution tests, owned by
#  P1.M7. T2.S1 contributes the nav/backspace actions + the shared filter they
#  will exercise. The Level 2 mock already plants the client-session-changed
#  canary — the PRD §15.18 "Pollution (the core invariant)" check for nav.)

# Optional: shellcheck strict mode (informational; the file-level disables cover
# the expected findings):
shellcheck -x scripts/filter.sh scripts/renderer.sh scripts/input-handler.sh
```

## Final Validation Checklist

### Technical Validation

- [ ] Level 1 (syntax/lint/style) completed on all THREE files: `bash -n` +
      `shellcheck` clean; tabs only; `set -u` only (no `-e`/`pipefail`).
- [ ] Level 2 (socket-shim mock) ALL GREEN: shared-filter identity; renderer
      byte-identity; backspace trims + resets index (+ empty no-op); next×3 wraps
      0→1→2→0 with preview cycling alpha→beta→gamma→alpha; prev×3 wraps 0→2→1→0;
      L==0 no-op; `client-session-changed` canary NEVER fires.
- [ ] `scripts/filter.sh` is a pure sourced library (no source-time side effects).
- [ ] Shared filter = single source of truth: `grep -rn 'low_name\|low_filter='
      scripts/` matches ONLY `filter.sh`; renderer.sh + input-handler.sh both call
      `lp_build_filtered`.
- [ ] No linting errors on any of the three files.

### Feature Validation

- [ ] All success criteria from "What" section met.
- [ ] **backspace:** `${old%?}` trim + index=0 + refresh; empty no-op; NO
      preview.sh call (contract FINDING 4); no switch-client.
- [ ] **next/prev:** re-filter via the shared helper; `L==0` no-op; wrap-modulo
      (next `(i+1)%L`, prev `(i-1+L)%L`); set index; `preview.sh` at the new
      index; refresh; NO switch-client (Invariant A).
- [ ] Shared `lp_build_filtered` is the ONLY filter; renderer.sh's inline copy
      is gone.
- [ ] `confirm)`/`cancel)` seams + `*) return 0` + `type` branch unchanged.
- [ ] Invariant A: no branch calls `switch-client`/`new-session`/`set-hook` or
      mutates `@livepicker-list`/`@livepicker-mode`/`@livepicker-linked-id`/orig-*.

### Code Quality Validation

- [ ] Follows existing codebase patterns (mirrors renderer.sh's filter
      algorithm in filter.sh; incremental-edit model in input-handler.sh like
      restore.sh across P1.M5; sourced-library style like utils.sh/state.sh).
- [ ] File placement matches the desired codebase tree (`scripts/filter.sh` NEW;
      `scripts/renderer.sh` + `scripts/input-handler.sh` edited).
- [ ] Anti-patterns avoided (check against Anti-Patterns section).
- [ ] Dependencies properly sourced (options→utils→state→filter; load-bearing
      trio order preserved; filter.sh appended last as it has no deps).

### Documentation & Deployment

- [ ] Code is self-documenting (the headers explain the shared-filter contract,
      the load-bearing rules, and the seam model).
- [ ] No new environment variables or config options (reads/writes only existing
      `@livepicker-*` keys; introduces one pure function).
- [ ] Mode A docs: none (per work-item §6).

---

## Anti-Patterns to Avoid

- ❌ Don't re-implement the filter inline in input-handler.sh — CALL
  `lp_build_filtered` (the work-item CONTRACT point 1; two copies drift). And
  don't leave renderer.sh's inline copy — refactor it to consume the same helper.
- ❌ Don't add a `preview.sh` call to backspace — the work-item §3 contract lists
  filter+index+refresh ONLY (research FINDING 4). Adding one is scope creep.
- ❌ Don't call `switch-client` in nav — that pollutes session history (Invariant
  A / PRD §4). Delegate to `preview.sh` (link-window/select-window).
- ❌ Don't compute modulo without the `+L` on prev — bash `%` can return negatives
  for negative operands; `(i-1+L)%L` keeps it positive (research FINDING 5).
- ❌ Don't skip the `L==0` guard — dividing by zero / indexing an empty array
  crashes nav. `[ "$L" -eq 0 ] && return 0`.
- ❌ Don't reference `$2` in the nav/backspace branches — they take `argv[1]`
  ONLY (research FINDING 1); under `set -u` that crashes.
- ❌ Don't recreate input-handler.sh — EDIT it in place (T1.S1 created it); grow
  the `local` line, add one source line, split the combined seam branch.
- ❌ Don't add `set -e` / `set -o pipefail` — refresh-client + preview.sh
  legitimately return non-zero on edge cases; `set -u` only (house style).
- ❌ Don't make filter.sh executable-at-source (no driver, no `*_main "$@"`) —
  sourcing it must be a pure no-op (it is a library, like utils.sh/state.sh).
