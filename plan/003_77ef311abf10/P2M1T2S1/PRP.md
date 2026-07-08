# PRP — P2.M1.T2.S1: Implement rename (command-prompt + do-rename) + input dispatch

---

## Goal

**Feature Goal**: Implement the **rename** management action for PRD §21.42:
pressing `C-r` (bound by P2.M1.T1.S1) opens tmux's built-in `command-prompt`
pre-filled with the highlighted session/window's current name; on submit a
`do-rename` runs that applies `rename-session`/`rename-window`, **rejects
sanitized or colliding names with `display-message` + NO rename** (reverts if
tmux silently sanitized), rewrites `@livepicker-list` with the new name on a
clean success, keeps the highlight on it, and `refresh-client -S` — all while
the picker **stays open** (no restore). Create `scripts/session-mgmt.sh` (the
rename + do-rename host; executable entry point) and add the `rename)` dispatch
branch to `scripts/input-handler.sh`.

**Deliverable** (2 file changes):
1. **CREATE** `scripts/session-mgmt.sh` — new executable entry point (§P1):
   sources options/utils/state/rank; hosts `session_mgmt_rename` (resolve S →
   open `command-prompt`), `session_mgmt_do_rename` (apply + detect + rewrite +
   refresh), and a `session_mgmt_main` driver (`rename` | `do-rename` | `*)`).
2. **EDIT** `scripts/input-handler.sh` — add a `rename)` branch (thin delegate
   to `session-mgmt.sh rename`) + a `delete)` seam comment for P2.M1.T2.S2.

**Success Definition**:
- `bash -n`/`shellcheck` clean on both files; `session-mgmt.sh` is executable
  (`chmod +x`, matching the other entry points).
- With the picker active on an isolated socket + attached client:
  - `C-r` opens tmux's prompt pre-filled with the highlighted name; the
    livepicker table is suspended while the prompt is open and restored on
    submit/escape (no extra binding work).
  - Submitting a valid new name renames the session, updates the tab in place
    (the renderer shows the new name after `refresh-client -S`), keeps the
    highlight on it, and leaves the picker open (`@livepicker-mode` still `on`).
  - Submitting a name that tmux would **sanitize** (`:`→`_`, leading `.`→`_`)
    is **rejected** with a `display-message` and **NO rename** — if tmux already
    applied a sanitized name, do-rename reverts it back to the original; the list
    + picker are unchanged (never silently mis-renamed, per OUTPUT §4).
  - Submitting a name that **collides** with an existing session (or is empty)
    aborts with a `display-message`, applies NO rename, leaves the list + picker
    unchanged.
  - The linked preview (`@livepicker-linked-id`) is NOT re-linked (a rename does
    not change the window id) and `@livepicker-index` is unchanged.
- `tests/run.sh` stays GREEN (no regression — rename is only reachable via the
  `C-r` binding, which no existing test exercises).

## User Persona (if applicable)

**Target User**: tmux users migrating from sessionx (the `C-r` default mirrors
`@sessionx-bind-rename-session ctrl-r`), who want to rename the highlighted
session without leaving the picker.

**Use Case**: Activate the picker → navigate to a session → press `C-r` → tmux
prompt pre-filled with the current name → edit/replace → Enter. The tab updates
in place; the picker stays open for further browsing.

**User Journey**: Activate (P2.M1.T1.S1 bound `C-r` → `input-handler.sh rename`)
→ `input-handler.sh` delegates to `session-mgmt.sh rename` → tmux `command-prompt`
opens (livepicker table suspended) → user types a new name → Enter → tmux spawns
`session-mgmt.sh do-rename <NEW>` (livepicker table restored) → do-rename applies
`rename-session`, detects sanitization/collision, rewrites `@livepicker-list`,
`refresh-client -S` → the tab shows the new name, highlight unchanged, picker open.

**Pain Points Addressed**: In-place rename without losing the picker session
(parity with sessionx); protection against silent tmux name sanitization and
collision (the user is told, never silently mis-renamed).

## Why

- **PRD §21.42 (Rename)** specifies the exact `command-prompt … run-shell
  '…/session-mgmt.sh do-rename %%'` flow, the sanitization/collision detection,
  and the list rewrite + highlight-keep + no-preview-re-link semantics.
- **PRD §13** lists `command-prompt -I -p "run-shell '<script> %%'"` and
  `rename-session -t "=S" "NEW"` as the primitives; §16 documents the `%%`
  escaping limitation + the "detect a sanitized result" requirement.
- **Decoupling**: P2.M1.T1.S1 bound the (inert) `C-r` key + added the option
  accessors; THIS task lights it up by adding the dispatch + the rename logic.
  `delete`/`do-delete` remain P2.M1.T2.S2's scope (seam comment left).
- `session-mgmt.sh` hosts BOTH `rename` (open prompt) and `do-rename` (apply) so
  they share the "resolve S from ranked[index]" logic without duplication
  (do-rename re-resolves because the index is stable during the prompt but the
  resolution must run in do-rename's own process).

## What

1. **scripts/session-mgmt.sh** (NEW) — the rename + do-rename host. Executable
   entry point (§P1): shebang, `set -u` (NOT `-e` — `rename-session` legitimately
   returns rc≠0 on collision and MUST NOT abort), `CURRENT_DIR` resolve, source
   options/utils/state/rank (NOT layout — no viewport/scroll work). Functions:
   `_lp_resolve_highlighted` (echo the highlighted session name / window token
   from `lp_rank(STATE_LIST, STATE_FILTER)[STATE_INDEX]`; empty if ranked empty),
   `session_mgmt_rename` (resolve → open `command-prompt`), `session_mgmt_do_rename`
   (apply → detect/reject/revert → rewrite → refresh), `session_mgmt_main` driver.
2. **scripts/input-handler.sh** (EDIT) — add `rename)` to the `case "$action"`
   dispatch: thin delegate `"$CURRENT_DIR/session-mgmt.sh" rename; return 0`.
   Insert between the `cancel)` block and `refresh-width)`, with a `delete)`
   seam comment for P2.M1.T2.S2.

### Success Criteria

- [ ] `scripts/session-mgmt.sh` exists, is `chmod +x`, `bash -n` + `shellcheck`
      clean, sources options/utils/state/rank, has `session_mgmt_main "$@" || exit 1; exit 0`.
- [ ] `session_mgmt_main` dispatches `rename` / `do-rename` (+ `*)` no-op + a
      `delete`/`do-delete` seam comment for P2.M1.T2.S2).
- [ ] `scripts/input-handler.sh` has a `rename)` branch that delegates to
      `session-mgmt.sh rename`; the `delete)` branch is NOT added (sibling scope).
- [ ] `C-r` (from P2.M1.T1.S1) → prompt opens pre-filled; submit renames; the tab
      updates after `refresh-client -S`; highlight unchanged; picker stays open.
- [ ] Sanitized name (`:`/leading`.`) → **rejected** with `display-message` + NO
      rename (reverted if tmux applied one); list + picker unchanged.
- [ ] Collision / empty → `display-message`, NO rename, list unchanged, picker open.
- [ ] `@livepicker-index` + `@livepicker-linked-id` unchanged (no re-link).
- [ ] `tests/run.sh` stays GREEN.

## All Needed Context

### Context Completeness Check

_Pass_: A developer who has never seen this repo can implement both changes
from (a) the verbatim file contents / insertion anchors in the Implementation
Blueprint, (b) the 10 findings in `research/findings.md` — most critically
**FINDING 1/3** (session-id-stable targeting + the exact do-rename detection
sequence), **FINDING 2** (rc=0 ≠ unchanged; sanitization table), **FINDING 4**
(window mode: index unchanged, no rewrite, no sanitization), **FINDING 5/6**
(the `%%` command-prompt primitive + its escaping limitation), and **FINDING 8**
(rename does not touch window id → no re-link; index unchanged → highlight stays).
The resolution pattern is reproduced verbatim from the existing `confirm` branch
(input-handler.sh), so no novel logic is required.

### Documentation & References

```yaml
# MUST READ — the file you EDIT (the dispatch + the delegate).
- file: scripts/input-handler.sh
  why: the `case "$action"` dispatch; the `cancel)` block is the INSERTION ANCHOR
       (insert `rename)` between its `;;` and `refresh-width)`); the `confirm)`
       branch is the verbatim PATTERN for resolving the highlighted target via
       lp_rank + STATE_INDEX (copy it into session-mgmt's _lp_resolve_highlighted);
       `$CURRENT_DIR` is the house variable (== scripts/; NOT $SCRIPT_DIR).
  pattern: |
    cur_list="$(get_state "$STATE_LIST" "")"
    cur_filter="$(get_state "$STATE_FILTER" "")"
    mapfile -t filtered < <(lp_rank "$cur_list" "$cur_filter")
    L="${#filtered[@]}"; cur_index="$(get_state "$STATE_INDEX" "0")"
    [[ "$cur_index" =~ ^[0-9]+$ ]] || cur_index=0
    [ "$L" -gt 0 ] || { <empty>; }; [ "$cur_index" -ge "$L" ] && cur_index=$((L-1))
    target="${filtered[$cur_index]}"
  gotcha: rename must NOT reference $2 (the C-r binding passes NO char; mirror
          confirm's FINDING 9). The `delete)` branch is P2.M1.T2.S2 — seam only.

# MUST READ — the resolution + list-read contract the new file mirrors.
- file: scripts/state.sh
  why: STATE_LIST / STATE_FILTER / STATE_INDEX / ORIG_SESSION / STATE_LINKED_ID
       constants; get_state/set_state accessors (get_state takes a default arg for
       set -u safety); STATE_LIST is newline-joined, embedded \n, NO trailing \n.
  pattern: 'cur_list="$(get_state "$STATE_LIST" "")"; set_state "$STATE_LIST" "$new"'

# MUST READ — the ranker the renderer/confirm/nav use (so rename resolves the
# SAME highlighted item the renderer shows).
- file: scripts/rank.sh
  why: lp_rank "$LIST" "$FILTER" prints matching names best-first (empty FILTER
       → all names, original order). mapfile -t arr < <(lp_rank …) is the call shape.
  pattern: 'mapfile -t filtered < <(lp_rank "$cur_list" "$cur_filter")'

# MUST READ — the §P1 executable-entry-point pattern session-mgmt.sh must follow.
- file: scripts/restore.sh
  why: the canonical NEW entry point: shebang + shellcheck disables + set -u +
       CURRENT_DIR resolve + source lib trio + a *_main driver
       (`restore_main "$@" || exit 1; exit 0`). session-mgmt.sh mirrors this shape.
  pattern: |
    CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    source "$CURRENT_DIR/options.sh"; …utils.sh; …state.sh; …rank.sh
    session_mgmt_main() { … }; session_mgmt_main "$@" || exit 1; exit 0
  gotcha: restore.sh is the precedent for a sibling entry point CALLED from
          input-handler.sh via "$CURRENT_DIR/restore.sh keep" — rename delegates
          the same way ("$CURRENT_DIR/session-mgmt.sh rename").

# MUST READ — option accessors (opt_type session|window) + the bound key.
- file: scripts/options.sh
  why: opt_type() returns "session"|"window" (PRD §11) — branch the rename on it.
       opt_rename_key (C-r) is bound by P2.M1.T1.S1; this task does NOT touch it.

# MUST READ — the ground-truth findings for THIS task (10 empirically-verified).
- docfile: plan/003_77ef311abf10/P2M1T2S1/research/findings.md
  why: FINDING 1 (session id stable + bare $N targeting); FINDING 2 (sanitization
       table; rc=0 ≠ unchanged); FINDING 3 (the exact do-rename detection sequence
       using the session id); FINDING 4 (window mode: index unchanged, no rewrite,
       no sanitization); FINDING 5/6 (command-prompt %% primitive + limitation);
       FINDING 7 (STATE_LIST in-place rewrite); FINDING 8 (no re-link; highlight stays).
  critical: Read BEFORE writing session-mgmt.sh. FINDING 3 is the load-bearing
            detection recipe; deviating from the session-id-targeting approach
            reintroduces the "can't find the renamed session" bug.

# MUST READ — the PRD sections selected for this work item.
- docfile: PRD.md
  why: §21.42 Rename (the exact command-prompt template + do-rename semantics);
       §21.44 Window mode (rename-window, same shape); §13 (command-prompt %% +
       rename-session primitives); §16 (%% escaping limitation + "detect a
       sanitized result" requirement).
  section: "§21 Session management (Rename / Window mode)", "§13 tmux primitives",
           "§16 Implementation risks (command-prompt substitution)"

# MUST READ — the architecture patterns (entry-point + option + set -u conventions).
- docfile: plan/003_77ef311abf10/architecture/codebase_patterns.md
  why: §P1 (sourced-lib vs executable-entry-point contract — session-mgmt.sh is
       the latter); §P5 (all preview work routes through _lp_preview_follow —
       rename does NONE, it only refresh-client -S); §P9 (set -u safety +
       escaping; the %% limitation).
  section: "§P1 Sourced library contract", "§P5 Preview entry point", "§P9 set -u safety"

# REFERENCE — what P2.M1.T1.S1 produced (the inert binding this task lights up).
- docfile: plan/003_77ef311abf10/P2M1T1S1/PRP.md
  why: confirms `C-r` is bound to `input-handler.sh rename` (so this task's
       `rename)` branch is what makes it functional) and the option accessors exist.
```

### Current Codebase tree

```bash
tmux-livepicker/
  scripts/
    options.sh utils.sh state.sh rank.sh layout.sh   # sourced libs (NOT +x)
    input-handler.sh  # +x; EDIT (add rename) branch). COMPLETE P1.M6.
    livepicker.sh renderer.sh preview.sh restore.sh   # +x; entry points (COMPLETE).
    session-mgmt.sh   # <-- DOES NOT EXIST yet (THIS TASK CREATES it; +x entry point).
  tests/
    setup_socket.sh helpers.sh run.sh                 # harness (COMPLETE).
    test_*.sh                                          # suites (COMPLETE; rename tests = P2.M2.T1.S1).
  README.md CHANGELOG.md plugin.tmux PRD.md
```

### Desired Codebase tree with files to be added and responsibility of file

```bash
tmux-livepicker/
  scripts/
    session-mgmt.sh   # NEW, +x. Executable entry point (§P1). Hosts rename +
                      #   do-rename (PRD §21.42) + a delete/do-delete SEAM for
                      #   P2.M1.T2.S2. Sources options/utils/state/rank.
                      #   _lp_resolve_highlighted: shared target resolution.
                      #   session_mgmt_rename: open command-prompt.
                      #   session_mgmt_do_rename: apply + detect + rewrite + refresh.
                      #   session_mgmt_main: rename|do-rename|* driver.
    input-handler.sh  # EDIT: + `rename)` branch (delegate to session-mgmt.sh rename)
                      #   + `delete)` seam comment. Inserted between cancel) and refresh-width).
```

### Known Gotchas of our codebase & Library Quirks

```bash
# CRITICAL (FINDING 2/3): rename-session returns rc=0 on SANITIZATION (`:`->`_`,
# leading `.`->`_) with a DIFFERENT name. rc=0 does NOT mean "unchanged". You
# MUST read back the actual name (via the stable session id) and compare to $NEW.
# Collision/empty return rc=1 and apply nothing (clean abort).

# CRITICAL (FINDING 1/3): after a sanitized rename the session is named neither
# $S nor $NEW -> a NAME target can't find it. Capture the STABLE session id from
# `list-sessions -F '#{session_id} #{session_name}'` BEFORE the rename, target
# rename-session + the read-back by the BARE id (`$0`, NOT `=$0`). display-message
# -p -t "$sid" '#{session_name}' works DETACHED (no attached client needed) and
# returns the full name (handles spaces in the result).

# CRITICAL (FINDING 3): reject sanitized names with NO rename. Pre-detect the
# documented tmux rules (`:` anywhere, leading `.`) and abort BEFORE renaming;
# as a safety net, if rename-session rc=0 but the read-back actual != $NEW
# (an unpredicted sanitization), REVERT it back to $S via the stable id. This
# matches OUTPUT §4 ("sanitized/collision names abort with a message and NO
# rename") — never silently mis-rename. (A literal "abort" that left the list
# stale would break the picker; reverting keeps the session + list unchanged.)

# CRITICAL: session-mgmt.sh MUST use `set -u` and MUST NOT use `set -e`.
# rename-session returns rc!=0 on collision; `set -e` would abort the script and
# strand the picker. Use `if ! tmux rename-session …; then …; fi` (rc checked,
# not fatal). Mirrors input-handler.sh / restore.sh (set -u only).

# CRITICAL (FINDING 6): use the EXACT PRD command-prompt template with UNQUOTED
# `%%`. Do NOT wrap %% in quotes to "handle spaces" — that breaks names with `"`,
# deviates from the PRD contract, and spaces are already part of the documented
# limitation (rides to P4).

# GOTCHA (FINDING 4): window mode does NOT rewrite STATE_LIST. rename-window
# leaves the window INDEX unchanged, so the picker token (session:window_index)
# is unchanged; window names are NOT sanitized. Window-mode do-rename = rename-window
# + rc check + refresh (no list edit, no actual-name read).

# GOTCHA (FINDING 8): a rename does NOT change the window id and does NOT reorder
# the list -> @livepicker-linked-id stays valid (NO preview re-link / re-sync) and
# @livepicker-index is UNCHANGED (highlight stays). Only refresh-client -S redraws.

# GOTCHA: input-handler.sh's `rename)` branch must NOT reference $2 (the C-r
# binding passes no char; mirror confirm FINDING 9). It is a one-line delegate.

# GOTCHA: use $CURRENT_DIR (house variable, == scripts/). NEVER $SCRIPT_DIR
# (undefined under set -u -> crash). Mirrors input-handler.sh FINDING 6.

# GOTCHA (§P1): session-mgmt.sh is an EXECUTABLE entry point -> `chmod +x` (all
# entry points are +x; sourced libs are not). Has the `*_main "$@" || exit 1;
# exit 0` driver. Sources options/utils/state/rank (NOT layout — no scroll/viewport).
```

## Implementation Blueprint

### Data models and structure

No new data model. No new constants in `state.sh` (rename reuses the existing
`STATE_LIST` / `STATE_FILTER` / `STATE_INDEX` / `ORIG_SESSION` keys; it does NOT
add `STATE_*` or `ORIG_*` keys). The only state mutation is rewriting
`STATE_LIST` (session mode) — an in-place name swap.

### Implementation Tasks (ordered by dependencies)

```yaml
Task 1: CREATE scripts/session-mgmt.sh (NEW executable entry point; §P1)
  - FILE: ./scripts/session-mgmt.sh  (NEW; chmod +x).
  - HEADER (mirror scripts/restore.sh):
      #!/usr/bin/env bash
      # shellcheck disable=SC1091,SC2153
      #   SC1091: sources sibling libs (options/utils/state/rank) via $CURRENT_DIR.
      #   SC2153: STATE_*/ORIG_* are readonly CONTRACT constants from state.sh.
      # scripts/session-mgmt.sh — tmux-livepicker session/window MANAGEMENT (PRD §21).
      #   rename  : open tmux command-prompt pre-filled with the highlighted name.
      #   do-rename NEW : apply rename-session/rename-window, detect sanitization/
      #     collision, rewrite @livepicker-list (session mode), keep highlight, refresh.
      # Invoked via run-shell: from input-handler.sh `rename` (delegated), and from
      #   the command-prompt template `do-rename %%` (on submit).
      set -u   # NOT -e (rename-session legitimately rc!=0 on collision); NOT pipefail.
      CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
      source "$CURRENT_DIR/options.sh"
      source "$CURRENT_DIR/utils.sh"
      source "$CURRENT_DIR/state.sh"
      source "$CURRENT_DIR/rank.sh"
  - HELPER _lp_resolve_highlighted — echo the highlighted session name (session
    mode) or "session:window_index" token (window mode), or "" if ranked empty.
    VERBATIM resolution from input-handler.sh `confirm` (so S == what the renderer
    highlights):
      _lp_resolve_highlighted() {
          local _list _filt _idx _L _pick_type
          local -a _filtered=()
          _list="$(get_state "$STATE_LIST" "")"
          _filt="$(get_state "$STATE_FILTER" "")"
          mapfile -t _filtered < <(lp_rank "$_list" "$_filt")
          _L="${#_filtered[@]}"
          [ "$_L" -eq 0 ] && return 0   # empty ranked list -> no target (echo nothing)
          _idx="$(get_state "$STATE_INDEX" "0")"
          [[ "$_idx" =~ ^[0-9]+$ ]] || _idx=0
          [ "$_idx" -ge "$_L" ] && _idx=$(( _L - 1 ))   # clamp (mirror confirm)
          printf '%s' "${_filtered[$_idx]}"
      }
  - session_mgmt_rename — resolve S; no-op if empty; branch on opt_type; open
    command-prompt (session: prefill $S, "Rename session:"; window: prefill the
    current window NAME, "Rename window:"). Template uses UNQUOTED %% + $CURRENT_DIR:
      session_mgmt_rename() {
          local _target _pick_type _wprefill
          _target="$(_lp_resolve_highlighted)"
          [ -z "$_target" ] && return 0   # ranked empty -> no-op (PRD §21.42 step 1)
          _pick_type="$(opt_type)"
          if [ "$_pick_type" = "window" ]; then
              # window token = session:window_index; prefill the current WINDOW NAME.
              _wprefill="$(tmux display-message -p -t "$_target" '#{window_name}' 2>/dev/null)"
              tmux command-prompt -I "$_wprefill" -p "Rename window:" \
                  "run-shell '$CURRENT_DIR/session-mgmt.sh do-rename %%'"
          else
              tmux command-prompt -I "$_target" -p "Rename session:" \
                  "run-shell '$CURRENT_DIR/session-mgmt.sh do-rename %%'"
          fi
          # NOTE: while command-prompt is open it captures input (the livepicker
          # table is suspended); tmux restores the livepicker table on submit/escape
          # -> no extra binding work. Escape cancels (do-rename NOT run). The picker
          # stays OPEN throughout (no restore call). (PRD §21.42; FINDING 5.)
          return 0
      }
  - session_mgmt_do_rename — NEW="${2:-}"; empty -> no-op; re-resolve target
    (stable during the prompt); branch session/window:
      session_mgmt_do_rename() {
          local _new="${2:-}"
          [ -z "$_new" ] && return 0   # empty submit -> no-op (PRD §21.42)
          local _target _pick_type
          _target="$(_lp_resolve_highlighted)"
          [ -z "$_target" ] && return 0
          _pick_type="$(opt_type)"
          if [ "$_pick_type" = "window" ]; then
              # FINDING 4: rename-window does NOT change the index -> the picker
              # token (session:window_index) is unchanged -> NO STATE_LIST rewrite.
              # Window names are NOT sanitized. rc!=0 only on an invalid target.
              if ! tmux rename-window -t "$_target" "$_new" 2>/dev/null; then
                  tmux display-message "livepicker: cannot rename window '$_target'"
                  return 0
              fi
              tmux refresh-client -S 2>/dev/null || true
              return 0
          fi
          # --- session mode ---
          # FINDING 2/3: reject sanitized/colliding names with NO rename.
          # (a) Pre-detect the DOCUMENTED tmux sanitization rules (FINDING 2):
          #     ':' anywhere, or a leading '.'. Abort BEFORE renaming so the
          #     session is never renamed under a different name (OUTPUT §4).
          case "$_new" in
              *:*) tmux display-message "livepicker: ':' is not allowed in a session name"; return 0 ;;
          esac
          case "$_new" in
              .*)  tmux display-message "livepicker: a session name cannot start with '.'"; return 0 ;;
          esac
          # (b) Capture the STABLE session id (rename/revert/read-back by the bare
          #     id; FINDING 1) — after a sanitized rename the session is named
          #     neither $S nor $NEW, so a NAME target can't find it.
          local _S _sid _actual _list _new_list _first _l
          _S="$_target"
          _sid="$(tmux list-sessions -F '#{session_id} #{session_name}' 2>/dev/null \
              | awk -v s="$_S" '$2==s{print $1; exit}')"
          [ -z "$_sid" ] && return 0   # _S vanished (race) -> no-op
          if ! tmux rename-session -t "$_sid" "$_new" 2>/dev/null; then
              # collision (a session named $_new exists) OR invalid -> nothing renamed.
              tmux display-message "livepicker: cannot rename '$_S' to '$_new' (in use or invalid)"
              return 0   # picker stays open, list UNCHANGED
          fi
          _actual="$(tmux display-message -p -t "$_sid" '#{session_name}' 2>/dev/null)"
          if [ "$_actual" != "$_new" ]; then
              # SAFETY NET: tmux sanitized in an unpredicted way (rc=0, different
              # name). REVERT to $S via the stable id -> NO rename; never silent.
              # (The pre-detect above covers the documented cases; this catches
              # anything else so we never silently mis-rename. FINDING 3.)
              tmux rename-session -t "$_sid" "$_S" 2>/dev/null || true
              tmux display-message "livepicker: '$_new' is not a valid session name"
              return 0   # list UNCHANGED, picker stays open
          fi
          # (c) Clean success (_actual == _new). FINDING 7: rewrite STATE_LIST in
          # place (replace the _S line with _new). Whole-line compare handles
          # spaces; session names are unique -> one match.
          _list="$(get_state "$STATE_LIST" "")"
          local -a _lines=()
          local _i
          mapfile -t _lines < <(printf '%s' "$_list")
          for _i in "${!_lines[@]}"; do
              [ "${_lines[$_i]}" = "$_S" ] && _lines[$_i]="$_new"
          done
          _new_list=""; _first=1
          for _l in "${_lines[@]}"; do
              if [ "$_first" = 1 ]; then _new_list="$_l"; _first=0
              else _new_list="$_new_list"$'\n'"$_l"; fi
          done
          set_state "$STATE_LIST" "$_new_list"
          # FINDING 8: index unchanged (rename doesn't reorder) -> highlight stays;
          # window id unchanged -> NO preview re-link. Just redraw the status.
          tmux refresh-client -S 2>/dev/null || true
          return 0
      }
  - session_mgmt_main — dispatch + a delete/do-delete SEAM for P2.M1.T2.S2:
      session_mgmt_main() {
          local _action="${1:-}"
          case "$_action" in
              rename)     session_mgmt_rename ;;
              do-rename)  session_mgmt_do_rename "${2:-}" ;;
              # --- P2.M1.T2.S2 seam: delete / do-delete (guards + unlink-first +
              #     kill-session + re-sync). Add `delete)` + `do-delete)` branches here. ---
              *)          return 0 ;;   # unknown action -> defensive no-op
          esac
      }
      session_mgmt_main "$@" || exit 1
      exit 0
  - FOLLOW: scripts/restore.sh (entry-point shape + driver); input-handler.sh
    `confirm` (the resolution pattern); rank.sh (lp_rank call shape).
  - NAMING: session_mgmt_* functions; local vars _-prefixed (house style for
    helper locals, mirrors _lp_* in input-handler.sh).
  - PLACEMENT: scripts/session-mgmt.sh (new file).

Task 2: EDIT scripts/input-handler.sh — add the `rename)` dispatch branch
  - FILE: ./scripts/input-handler.sh  (EXISTING).
  - INSERT between the `cancel)` block's `;;` and `refresh-width)` (the anchor):
        \t\t"$CURRENT_DIR/restore.sh" cancel
        \t\treturn 0
        \t\t;;
        <INSERT rename) HERE>
        \trefresh-width)
  - ADD (TAB-indented to match the case body — 2 tabs):
        \t\t# --- P2.M1.T2.S1: rename the highlighted session/window via tmux's
        \t\t#     prompt (PRD §21.42). Thin delegate — session-mgmt.sh hosts the
        \t\t#     resolution + command-prompt (rename) + apply/detect/rewrite
        \t\t#     (do-rename). While command-prompt is open the livepicker table is
        \t\t#     suspended (the prompt captures input); tmux restores it on
        \t\t#     submit/escape -> no extra binding work. The picker stays OPEN
        \t\t#     (no restore). MUST NOT reference $2 (the C-r binding passes no char).
        \t\trename)
        \t\t\t"$CURRENT_DIR/session-mgmt.sh" rename
        \t\t\treturn 0
        \t\t\t;;
        \t\t# --- P2.M1.T2.S2 seam: `delete)` -> "$CURRENT_DIR/session-mgmt.sh" delete. ---
  - GOTCHA: 2-tab indent (the case body). The `rename)` label at 2 tabs; its body
    at 3 tabs (matches confirm/cancel). Verify with `grep -Pn '^\t\trename\)'`.
  - DEPENDENCIES: $CURRENT_DIR (already defined); session-mgmt.sh from Task 1.

Task 3: chmod +x scripts/session-mgmt.sh
  - RUN: chmod +x scripts/session-mgmt.sh  (entry points are +x; §P1).

Task 4: VALIDATE (Level 1-4 below)
  - RUN: bash -n + shellcheck on both files; the isolated-socket spot-checks;
    tests/run.sh (expect all GREEN).
```

### Implementation Patterns & Key Details

```bash
# === Resolution (VERBATIM from input-handler.sh confirm — so rename resolves the
#     SAME item the renderer highlights). Lives once in _lp_resolve_highlighted. ===
_lp_resolve_highlighted() {
    local _list _filt _idx _L
    local -a _filtered=()
    _list="$(get_state "$STATE_LIST" "")"; _filt="$(get_state "$STATE_FILTER" "")"
    mapfile -t _filtered < <(lp_rank "$_list" "$_filt")
    _L="${#_filtered[@]}"
    [ "$_L" -eq 0 ] && return 0                       # empty -> echo nothing
    _idx="$(get_state "$STATE_INDEX" "0")"
    [[ "$_idx" =~ ^[0-9]+$ ]] || _idx=0
    [ "$_idx" -ge "$_L" ] && _idx=$(( _L - 1 ))        # clamp
    printf '%s' "${_filtered[$_idx]}"
}

# === The command-prompt template (PRD §21.42 verbatim; UNQUOTED %%). ===
# Double-quoted outer string -> $CURRENT_DIR expands to the abs scripts/ dir;
# %% stays literal for tmux's command-prompt to substitute on submit.
tmux command-prompt -I "$_target" -p "Rename session:" \
    "run-shell '$CURRENT_DIR/session-mgmt.sh do-rename %%'"

# === The load-bearing do-rename detection (session mode; FINDING 1/2/3). ===
# rc=0 does NOT mean the name is unchanged (sanitization returns 0). So:
#  (1) pre-detect the DOCUMENTED rules (':' anywhere, leading '.') -> abort, NO rename;
#  (2) rename targeting the STABLE session id; rc!=0 -> collision/invalid, NO rename;
#  (3) read the actual name back by id; if != _new (unpredicted sanitization) REVERT
#      to $S via the id -> NO rename. Only a clean success rewrites the list.
case "$_new" in *:*) tmux display-message "livepicker: ':' is not allowed in a session name"; return 0 ;; esac
case "$_new" in .*)  tmux display-message "livepicker: a session name cannot start with '.'"; return 0 ;; esac
_sid="$(tmux list-sessions -F '#{session_id} #{session_name}' | awk -v s="$_S" '$2==s{print $1; exit}')"
if ! tmux rename-session -t "$_sid" "$_new"; then
    tmux display-message "livepicker: cannot rename '$_S' to '$_new' (in use or invalid)"; return 0
fi
_actual="$(tmux display-message -p -t "$_sid" '#{session_name}')"
if [ "$_actual" != "$_new" ]; then
    tmux rename-session -t "$_sid" "$_S" 2>/dev/null || true   # REVERT -> no rename
    tmux display-message "livepicker: '$_new' is not a valid session name"; return 0
fi
# ... in-place mapfile rewrite _S -> _new; set_state LIST; refresh-client -S ...

# === input-handler.sh delegate (Task 2) — one line, NO $2. ===
rename)
    "$CURRENT_DIR/session-mgmt.sh" rename
    return 0
    ;;
```

### Integration Points

```yaml
INPUT DISPATCH (input-handler.sh case "$action"):
  - ADD: `rename)` -> "$CURRENT_DIR/session-mgmt.sh rename" (Task 2).
  - The C-r binding (P2.M1.T1.S1) -> input-handler.sh rename -> THIS branch.
  - `delete)` is P2.M1.T2.S2 (seam comment left; do NOT implement here).

NEW ENTRY POINT (scripts/session-mgmt.sh):
  - Invoked two ways: (a) `session-mgmt.sh rename` (from input-handler); (b)
    `session-mgmt.sh do-rename <NEW>` (from the command-prompt template on submit).
  - Sources options/utils/state/rank (its own process under run-shell; mirrors
    restore.sh being called from input-handler).

STATE (state.sh):
  - NO new keys. Reads STATE_LIST/STATE_FILTER/STATE_INDEX; REWRITES STATE_LIST
    (session mode only). @livepicker-index + @livepicker-linked-id UNCHANGED.

PREVIEW (preview.sh / _lp_preview_follow):
  - NO call. A rename does not change the window id -> NO preview re-link/re-sync.
    Only `refresh-client -S` (redraws the status with the new name). §P5.

RESTORE (restore.sh):
  - NO call. The picker STAYS OPEN after a rename (mode stays on; key-table stays
    livepicker). restore is only for confirm/cancel.

ACTIVATION (livepicker.sh): NO CHANGE. The C-r binding is P2.M1.T1.S1's output.

DATABASE / MIGRATIONS / ROUTES / CONFIG-FILE: none.
```

## Validation Loop

### Level 1: Syntax & Style (Immediate Feedback)

```bash
# Run from the repo root after creating session-mgmt.sh + editing input-handler.sh.
chmod +x scripts/session-mgmt.sh                                   # entry point must be +x
bash -n scripts/session-mgmt.sh scripts/input-handler.sh           # syntax; expect exit 0
shellcheck scripts/session-mgmt.sh scripts/input-handler.sh        # lint; expect 0 findings
# 2-tab indent for the new case branch (input-handler.sh body uses tabs):
grep -Pn '^\t\trename\)' scripts/input-handler.sh && echo "rename) branch present" || echo "MISSING"
# session-mgmt.sh has the driver + the seam:
grep -n 'session_mgmt_main "\$@" || exit 1' scripts/session-mgmt.sh   # 1 match
grep -n 'P2.M1.T2.S2 seam' scripts/session-mgmt.sh                    # 1 match (delete seam)
```

### Level 2: Unit / Component Validation (do-rename logic, NO command-prompt needed)

```bash
# do-rename is testable DIRECTLY (call it with seeded state — no prompt). On a
# throwaway isolated socket (self-cleaning). exercises session-mode happy path +
# sanitization + collision + window mode.
SOCK="lp-mgmt-$$"; SHIM="$(mktemp -d)"
printf '#!/usr/bin/env bash\nexec /usr/bin/tmux -L "%s" "$@"\n' "$SOCK" > "$SHIM/tmux"
chmod +x "$SHIM/tmux"
trap '/usr/bin/tmux -L "$SOCK" kill-server 2>/dev/null; rm -rf "$SHIM"' EXIT
export PATH="$SHIM:$PATH"
tmux new-session -d -s driver -x 120 -y 40
tmux new-session -d -s alpha  -x 120 -y 40
tmux new-session -d -s beta   -x 120 -y 40
# Seed picker state as activate would (highlight on alpha at index 1):
tmux set-option -g @livepicker-list $'driver\nalpha\nbeta'
tmux set-option -g @livepicker-filter ''
tmux set-option -g @livepicker-index 1
# (a) happy path: rename the highlighted session (alpha, at index 1) -> alphax
bash scripts/session-mgmt.sh do-rename alphax
tmux has-session -t '=alphax' && echo "HAPPY OK (alphax exists)" || echo "HAPPY FAIL"
echo "list rewritten: [$(tmux show-option -gqv @livepicker-list)]"               # contains alphax, not alpha
echo "index kept:    [$(tmux show-option -gqv @livepicker-index)]"               # 1
# (b) sanitization: rename to 'a:b' -> REJECTED, NO rename (no a_b session)
bash scripts/session-mgmt.sh do-rename 'a:b'
tmux has-session -t '=a_b' && echo "SANITIZE FAIL (a_b exists)" || echo "SANITIZE-REJECT OK (no a_b; alphax intact)"
# (c) collision: rename to existing 'beta' -> NO rename, list unchanged
before="$(tmux show-option -gqv @livepicker-list)"
bash scripts/session-mgmt.sh do-rename beta
after="$(tmux show-option -gqv @livepicker-list)"
[ "$before" = "$after" ] && echo "COLLISION-ABORT OK (list unchanged)" || echo "COLLISION FAIL"
# (d) empty -> no-op
bash scripts/session-mgmt.sh do-rename ''
# Expected: happy path rewrites the list (alphax) + keeps index; sanitize -> REJECTED
#           (no a_b); collision -> no rename + list unchanged; empty -> no-op.
```

### Level 3: Integration Testing (the command-prompt wiring + picker-stays-open)

```bash
# Manual spot-check on an isolated socket WITH an attached client (command-prompt
# is a client command). Self-cleaning.
SOCK="lp-mgmt-i-$$"; SHIM="$(mktemp -d)"
printf '#!/usr/bin/env bash\nexec /usr/bin/tmux -L "%s" "$@"\n' "$SOCK" > "$SHIM/tmux"
chmod +x "$SHIM/tmux"
trap '/usr/bin/tmux -L "$SOCK" kill-server 2>/dev/null; rm -rf "$SHIM"' EXIT
export PATH="$SHIM:$PATH"
tmux new-session -d -s driver -x 120 -y 40
tmux new-session -d -s alpha  -x 120 -y 40
tmux set-option -g @livepicker-key Space
script -qec "tmux -L "$SOCK" attach -t driver" /dev/null >/dev/null 2>&1 & AP=$!; sleep 0.5
bash scripts/livepicker.sh                                   # activate (binds C-r via P2.M1.T1.S1)
# Confirm the C-r binding resolves to the rename dispatch:
echo "C-r bind: $(tmux list-keys -T livepicker C-r)"         # run-shell .../input-handler.sh rename
# Drive the rename action directly (bypass the interactive prompt) to prove the
# end-to-end dispatch path lights up: input-handler rename -> session-mgmt rename.
# (The interactive command-prompt submit is a manual check below.)
tmux send-keys -T livepicker C-r 2>/dev/null || true         # opens the prompt (suspends table)
# MANUAL: in a real client, type a new name + Enter; verify the tab updates and the
# picker stays open. Programmatically, the do-rename path is proven in Level 2.
kill "$AP" 2>/dev/null
# Expected: C-r is bound; pressing it opens tmux's prompt pre-filled with the
# highlighted name; the picker stays open throughout.
```

### Level 4: Creative & Domain-Specific Validation

```bash
# (1) Full regression: the existing suite must stay GREEN (rename is reachable
#     only via C-r, which no existing test presses).
tests/run.sh
# Expected: exit 0; "N passed, 0 failed".

# (2) Window-mode rename does NOT rewrite the list (FINDING 4). Seed window mode.
SOCK="lp-mgmt-w-$$"; SHIM="$(mktemp -d)"
printf '#!/usr/bin/env bash\nexec /usr/bin/tmux -L "%s" "$@"\n' "$SOCK" > "$SHIM/tmux"
chmod +x "$SHIM/tmux"; trap '/usr/bin/tmux -L "$SOCK" kill-server 2>/dev/null; rm -rf "$SHIM"' EXIT
export PATH="$SHIM:$PATH"
tmux new-session -d -s drv -x 120 -y 40 -n firstwin
tmux new-window -t drv -n secondwin
tmux set-option -g @livepicker-type window
tmux set-option -g @livepicker-list $'drv:0\ndrv:1'
tmux set-option -g @livepicker-filter ''
tmux set-option -g @livepicker-index 1
list_before="$(tmux show-option -gqv @livepicker-list)"
bash scripts/session-mgmt.sh do-rename renamedwin
list_after="$(tmux show-option -gqv @livepicker-list)"
[ "$list_before" = "$list_after" ] && echo "WINDOW: list UNCHANGED (index-based token) OK" || echo "WINDOW FAIL"
echo "window name now: [$(tmux display-message -p -t 'drv:1' '#{window_name}')]"   # renamedwin
# Expected: the window was renamed (renamedwin) but the list token (drv:1) is unchanged.

# (3) Interactive command-prompt flow (manual, real client): activate, press C-r,
#     confirm the prompt is pre-filled, type a new name, Enter -> the tab updates
#     in place, highlight stays, picker stays open. Then C-r + Escape -> picker
#     stays open, no rename. (The non-interactive do-rename logic is proven above.)
```

## Final Validation Checklist

### Technical Validation

- [ ] `bash -n scripts/session-mgmt.sh scripts/input-handler.sh` exits 0, no output.
- [ ] `shellcheck scripts/session-mgmt.sh scripts/input-handler.sh` reports 0 findings.
- [ ] `scripts/session-mgmt.sh` is `chmod +x`.
- [ ] The `rename)` branch is at 2-tab indent in input-handler.sh (no spaces).
- [ ] session-mgmt.sh sources options/utils/state/rank (NOT layout); has
      `session_mgmt_main "$@" || exit 1; exit 0`; uses `set -u` (NOT `-e`).

### Feature Validation

- [ ] `C-r` opens the prompt pre-filled with the highlighted name (Level 3).
- [ ] A valid new name renames the session; the tab updates after
      `refresh-client -S`; the highlight stays; the picker stays open.
- [ ] A sanitized name (`:`/leading`.`) is **rejected** with `display-message` + NO
      rename (reverted if tmux applied one); list + picker unchanged (Level 2b).
- [ ] A collision / empty name aborts with a `display-message`, applies NO rename,
      and leaves the list unchanged (Level 2c/2d).
- [ ] Window-mode rename renames the window, does NOT rewrite the list (token is
      index-based), and keeps the highlight (Level 4.2).
- [ ] `@livepicker-index` + `@livepicker-linked-id` are unchanged (no re-link).
- [ ] The picker stays open after a rename (`@livepicker-mode` still `on`).

### Code Quality Validation

- [ ] session-mgmt.sh follows §P1 (executable entry point; driver; no source-time
      side effects beyond defining functions + the driver call).
- [ ] `_lp_resolve_highlighted` mirrors input-handler.sh `confirm` verbatim (so
      rename resolves the same item the renderer highlights).
- [ ] do-rename targets rename-session by the STABLE session id (not `=S`), reads
      the actual name back by id, and REVERTS on sanitization (FINDING 1/3).
- [ ] STATE_LIST rewrite is an in-place whole-line swap (handles spaces; one match).
- [ ] `set -u` honored (every var defaulted: `${2:-}`, `get_state … ""`); no `set -e`.
- [ ] Uses `$CURRENT_DIR` (NOT `$SCRIPT_DIR`); the `%%` template is unquoted (PRD verbatim).

### Documentation & Deployment

- [ ] NO docs edit (the escaping caveat + rename/delete prose ride on P2.M1.T1.S1's
      README note / P4.T1, per work-item §5).
- [ ] NO new test file (test_session_mgmt.sh is P2.M2.T1.S1).
- [ ] NO CHANGELOG edit (P4.T2 owns the [Unreleased] entry).

---

## Anti-Patterns to Avoid

- ❌ Don't add the `delete)`/`do-delete` dispatch or implement delete logic here.
  That is P2.M1.T2.S2's contract; leave only the seam comment.
- ❌ Don't use `set -e` in session-mgmt.sh. `rename-session` legitimately returns
  rc≠0 on collision; `set -e` would abort and strand the picker. Check rc with
  `if ! …; then …; fi`. House style is `set -u` only.
- ❌ Don't trust `rename-session`'s rc=0 as "success". Sanitization (`:`→`_`,
  leading `.`→`_`) returns rc=0 with a DIFFERENT name. ALWAYS read back the
  actual name via the stable session id and compare to `$NEW` (FINDING 2/3).
- ❌ Don't target rename-session / the read-back by `=S` or `=NEW`. After a
  sanitized rename the session is named neither; use the STABLE session id
  (captured from `list-sessions -F '#{session_id} #{session_name}'`), bare `$N`.
- ❌ Don't apply a sanitized rename and rewrite the list with the sanitized
  name (the OUTPUT contract requires NO rename for sanitized/collision). Instead
  PRE-detect the documented rules (`:`/leading`.`) and abort, and REVERT any
  rename tmux silently applied (read the actual name back by the stable id; if it
  differs from $NEW, rename back to $S). FINDING 2/3.
- ❌ Don't re-link the preview or change `@livepicker-index` on a rename. A rename
  does not change the window id and does not reorder the list — only
  `refresh-client -S` is needed. FINDING 8.
- ❌ Don't rewrite STATE_LIST in window mode. rename-window leaves the window
  index unchanged, so the picker token (session:window_index) is already correct.
  FINDING 4.
- ❌ Don't wrap `%%` in quotes to "handle spaces". Use the EXACT PRD template
  (unquoted `%%`); quoting trades one breakage class for another and deviates
  from the contract. The limitation is documented (rides to P4). FINDING 6.
- ❌ Don't reference `$2` in input-handler.sh's `rename)` branch (the C-r binding
  passes no char; mirror confirm's FINDING 9). It is a one-line delegate.
- ❌ Don't create tests here. test_session_mgmt.sh is P2.M2.T1.S1. The gate for
  THIS task is that the existing suite stays GREEN + the Level 2-4 spot-checks pass.
- ❌ Don't source layout.sh in session-mgmt.sh. Rename does no viewport/scroll
  work; source only options/utils/state/rank (keeps it minimal, §P1).
