# PRP — P2.M2.T1.S1: Rework confirm session-mode to commit window + self-session path

---

## Goal

**Feature Goal**: Make the session-mode `confirm` action land the client on the
**chosen session AND the exact window being previewed/flipped** (not just the
session's pre-existing active window), and give the **self-session** a dedicated
no-`switch-client` path that lands on the chosen driver window. PRD §6 Confirm
(h3.7) + §4 Invariant B. The window choice `W` is resolved **authoritatively**
from the window-cursor state (`STATE_CAND_WIN_*`), never from the possibly-lagged
deferred preview link (PRD §18 contract #4).

**Deliverable** (2 files edited, NO new file):
1. **EDIT `scripts/input-handler.sh`** — replace the session-mode `else` body of
   the `confirm)` branch (today a one-line `_confirm_land_on_session "$target"`
   call) with: resolve `S=target`; resolve `W` from `STATE_CAND_WIN_CURSOR/LIST`
   (default S's active window); then branch — **non-self**: `select-window -t
   "=$S:$W"` → H2-hardened unlink of the driver's preview → `switch-client -t
   "=$S"` → `restore.sh keep`; **self** (`S==ORIG_SESSION`): `select-window -t
   "$W"` → drop a foreign preview link only if set & `!=W` → `restore.sh keep`
   (NO switch). The window-mode branch, the create-on-empty path, and
   `_confirm_land_on_session` (still used by create) are **UNCHANGED**.
2. **EDIT `README.md`** — [Mode A] two minimal prose touches so "Confirm lands on
   the chosen session AND the exact window being previewed, not just the session."

**Success Definition**:
- `bash -n`/`shellcheck` clean on `scripts/input-handler.sh`.
- On an isolated socket + attached client (defer off), after activating + flipping
  to a candidate's non-active window: `Enter` lands the client on that candidate
  session AND that exact window (`#{session_name}`==candidate, `#{window_id}`==W).
- Self-session: flip the driver to a non-ORIG window, `Enter` lands the client on
  that driver window with **no** `switch-client` (still on the driver).
- No orphan preview window leaks into the driver (the H2-hardened unlink before
  the switch mirrors `_confirm_land_on_session`).
- `tests/run.sh` stays GREEN (confirm is reachable only via `Enter`, which
  existing tests press only on the no-flip path; the formal window suite is
  P2.M3.T1.S1).

## User Persona (if applicable)

**Target User**: a tmux user browsing sessions+windows in the picker who flips
through a candidate's windows and wants `Enter` to land on the *specific window*
they were previewing — parity with picking a window, not just a session.

**Use Case**: activate → navigate to a multi-window session → `next-window`/`
prev-window` flip to the desired window (previewed live) → `Enter` → land on that
exact `(session, window)`.

**User Journey**: highlight S → flip to window W (the preview shows W; the cursor
tracks W) → `Enter` → confirm resolves (S, W) authoritatively → `select-window
=$S:$W` commits W in S → `switch-client =$S` → the client is on S:W.

**Pain Points Addressed**: today `Enter` ignores the flipped window and lands on
S's pre-existing active window (the gap in `gap_analysis_confirm_preview.md §b`).
Self-session additionally did a redundant same-session `switch-client`.

## Why

- **PRD §6 Confirm (h3.7)** mandates: "Commit the window choice in `S` with one
  `select-window -t "=$S:$W"` … `switch-client -t "=$S"` … the client lands on
  `S:W`." and "If `S == ORIG_SESSION` (self): skip the `switch-client`; the single
  `select-window -t "$W"` is the whole commit."
- **PRD §4 Invariant B**: confirm is the ONE place a candidate's state changes by
  design — a single `select-window` commits the chosen window. Everything else is
  read-only while browsing.
- **PRD §18 contract #4**: confirm reads authoritative filter/index/**window-cursor**
  state and must NOT depend on a deferred preview having run. So `W` comes from
  `STATE_CAND_WIN_*` (synchronous), not `STATE_LINKED_ID`/`STATE_PREVIEW_WIN_ID`
  (which may lag the background `-b` preview job).
- **`external_deps.md §1`** (VERIFIED on 3.6b): `select-window -t "=test_sess:@1"`
  → rc=0, correct window active. The `=$S:@id` form needs **no fallback**.
- **Decoupling**: P2.M1.T1.S1 (state keys), P2.M1.T2.S1 (preview chosen-window +
  self-session flip), P2.M1.T3.S1 (flip actions), P2.M1.T3.S2 (cursor resets) all
  land first. THIS task consumes their outputs and only edits the confirm branch.
  P2.M2.T2 (`restore.sh keep` skips ORIG_WINDOW re-select) is the paired sibling —
  see the hard dependency in FINDING 6 / Anti-Patterns.

## What

1. **scripts/input-handler.sh** (EDIT) — in the `confirm)` branch, replace the
   session-mode `else` body (the `_confirm_land_on_session "$target"` call) with
   the W-resolution + self/non-self commit logic (verbatim code in the Blueprint).
   The window-mode `if` branch, the empty-list create path, and the helper
   `_confirm_land_on_session` are untouched.
2. **README.md** (EDIT) — two one-line prose additions ("…and the exact window
   being previewed…") at L12 and L169.

### Success Criteria

- [ ] `scripts/input-handler.sh`: the session-mode `confirm` path resolves `W`
      from `STATE_CAND_WIN_*` (default active window), commits it, switches once
      (non-self) / not at all (self), and calls `restore.sh keep`.
- [ ] `bash -n` + `shellcheck` clean; the window-mode branch + create path +
      `_confirm_land_on_session` are byte-unchanged (the create path still calls it).
- [ ] Non-self: `Enter` lands the client on `(S, W)` where `W` is the flipped
      window; `select-window -t "=$S:$W"` is the only candidate mutation.
- [ ] Self: `Enter` lands on the driver window `W` with no `switch-client`.
- [ ] No orphan preview leaks (H2-hardened unlink before the switch).
- [ ] README prose mentions the window at L12 + L169.
- [ ] `tests/run.sh` GREEN.

## All Needed Context

### Context Completeness Check

_Pass_: a developer who has never seen this repo implements both edits from
(a) the verbatim oldText/newText anchors below (TAB-indented; the `else` body is
**5 tabs**, `else`/`fi` are **4 tabs**; the `—` is a UTF-8 em-dash — preserve it),
(b) the 10 findings in `research/findings.md` — most critically **FINDING 3** (W
resolution mirrors the flip branch's lazy-derive; LIST non-empty ⟹ SESSION==S
post-flip), **FINDING 4** (non-self order + the verified `=$S:@id` form), **FINDING
5** (self-session no-switch + the `linked_id != W` guard), **FINDING 6** (the hard
dependency on P2.M2.T2 for `restore.sh keep` to skip ORIG_WINDOW), **FINDING 7**
(locals in scope + exact 4/5-tab indentation). The H2-hardened unlink is reproduced
verbatim from the window-mode confirm branch above it.

### Documentation & References

```yaml
# MUST READ — the ONLY code file you EDIT.
- file: scripts/input-handler.sh
  why: the confirm) branch session-mode `else` body (~L605-608) is the edit surface.
       The window-mode branch (~L552-575) is the VERBATIM source for the H2-hardened
       unlink (drv_wins/drv_active guard) you mirror. _lp_fire_preview/_lp_preview_dispatch
       (P2.M1.T2.S1) already pass win_id; you only consume STATE_CAND_WIN_* here.
  pattern: |
    # the window-mode H2-unlink to mirror (non-self path):
    if [ -n "$linked_id" ] && [ -n "$orig_session" ]; then
        local drv_wins drv_active
        drv_wins="$(tmux list-windows -t "=$orig_session" 2>/dev/null | wc -l)"
        drv_active="$(tmux list-windows -t "=$orig_session" -F '#{window_id}' -f '#{window_active}' 2>/dev/null)"
        if [ "$drv_wins" -gt 1 ] || [ "$drv_active" != "$linked_id" ]; then
            tmux unlink-window -t "$orig_session:$linked_id" 2>/dev/null || true
        fi
    fi
  gotcha: TAB-indented (the session-mode body is 5 TABS; else/fi are 4). The § and
          — are UTF-8 — preserve them in oldText. set -u (NOT -e); split `local` from
          `$(...)` assignment (house style — avoids shellcheck SC2155).

# MUST READ — the window-cursor state you resolve W from (DEFINED+INIT'd+WIRED by P2.M1.T1.S1).
- file: scripts/state.sh
  why: STATE_CAND_WIN_SESSION/LIST/CURSOR + STATE_LINKED_ID + STATE_PREVIEW_WIN_ID +
       ORIG_SESSION/ORIG_WINDOW — all readonly, all in _STATE_RUNTIME_KEYS, all init'd
       at activate. set_state/get_state accessors.
  critical: these keys ALREADY EXIST. Do NOT add/rename keys. Do NOT edit state.sh.

# MUST READ — the lazy-derive pattern W-resolution mirrors (P2.M1.T3.S1).
- file: scripts/input-handler.sh   # the next-window branch (~L441-470)
  why: the flip branch re-derives STATE_CAND_WIN_LIST when `SESSION != S OR list==""`,
       resets the cursor to the active window, and advances it. The confirm W-resolution
       reuses the SAME list-windows form + cursor indexing so W == the window the flip
       subsystem is showing. Read this branch before writing the resolution.
  pattern: 'mapfile -t win_arr < <(printf "%s\n" "$win_list"); W="${win_arr[$new_cursor]}"'

# MUST READ — the preview chosen-window flow (P2.M1.T2.S1) + self-session handling.
- file: scripts/preview.sh
  why: argv[2]=chosen_win; for NON-self it links W into the driver (LINKED_ID=PREVIEW_WIN_ID=W);
       for SELF it selects W among the driver's own windows, clears LINKED_ID, sets
       PREVIEW_WIN_ID=W. Confirms (a) W from the cursor == what the user previewed, and
       (b) why self leaves LINKED_ID empty (the self-confirm unlink guard handles a stale
       foreign link only).
  critical: DO NOT edit preview.sh (COMPLETE). You only consume STATE_CAND_WIN_*/LINKED_ID.

# MUST READ — restore.sh keep (what your confirm path hands off to).
- file: scripts/restore.sh   # STEP-1 (L59-95), STEP-2 (L97-106), STEP-3 (L109-128)
  why: STEP-1's client-aware unlink is SKIPPED after a confirm switch (current_session !=
       ORIG_SESSION) -> YOUR path must unlink the driver preview BEFORE the switch (it does).
       STEP-2 `keep` re-selects ORIG_WINDOW TODAY -> P2.M2.T2 makes `keep` skip it. STEP-3
       `keep` does NOT switch (correct). See FINDING 6 (hard dependency on P2.M2.T2).
  critical: call `restore.sh keep` (NOT keep-window) per the contract; correctness of the
            window-landing depends on P2.M2.T2 landing.

# MUST READ — the gap this task closes + the verified select-window form.
- docfile: plan/004_2c5127285a90/architecture/gap_analysis_confirm_preview.md
  why: §(b) documents the gap (session confirm delegates to _confirm_land_on_session =
       no select-window); §(c) lists the 4 changes (state/preview/confirm/restore) — THIS
       task is §(c).3 (confirm) + the self-session path; §(d) the self-session edge case.
- docfile: plan/004_2c5127285a90/architecture/external_deps.md
  why: §1 VERIFIES `select-window -t "=$S:@id"` rc=0 on 3.6b -> no fallback needed.
        §5 link/unlink semantics (never -k; singly-linked rc=1 swallowed).

# MUST READ — the parallel sibling that defines the window-cursor guarantees (P2.M1.T3.S2).
- docfile: plan/004_2c5127285a90/P2M1T3S2/PRP.md
  why: P2.M1.T3.S2 invalidates STATE_CAND_WIN_LIST on every session-nav + filter change,
       and the flip (S1) re-binds SESSION=S + populates LIST. => at confirm, LIST non-empty
       ⟹ SESSION==S (post-flip). This is WHY the W-resolution can trust LIST+cursor.
  critical: the `cand_win_sess == S` guard in the W-resolution is defense-in-depth against
            any merge ordering with S2; keep it.

# MUST READ — PRD §6 Confirm (h3.7) + §4 Invariants + §18 + §9.
- docfile: PRD.md
  why: §6 h3.7 (the exact confirm spec: commit W, unlink, switch, self-skip); §4 (Invariant
       B — one deliberate candidate mutation); §18 contract #4 (authoritative cursor read);
       §9 (restore keep does NOT re-select ORIG_WINDOW nor switch).
  section: "§6 Confirm", "§4 The core rule", "§18 Responsiveness", "§9 State saved/restored"

# MUST READ — the ground-truth findings for THIS task (10 findings).
- docfile: plan/004_2c5127285a90/P2M2T1S1/research/findings.md
  why: FINDING 1 (the 3 confirm sub-paths; only session-mode changes); FINDING 2 (the gap);
       FINDING 3 (W resolution + the state-at-confirm table); FINDING 4 (non-self order);
       FINDING 5 (self path); FINDING 6 (P2.M2.T2 dependency); FINDING 7 (locals + 5-tab
       indent); FINDING 8 (activate init); FINDING 9 (set -u); FINDING 10 (README anchors).
  critical: FINDING 3 + 4 + 6 + 7 are the load-bearing ones. Read BEFORE editing.
```

### Current Codebase tree (run `tree` in the repo root)

```bash
tmux-livepicker/
  scripts/
    input-handler.sh     # MODIFY: confirm) session-mode `else` body (commit W + self/non-self).
    state.sh             # UNCHANGED (window-cursor keys exist — P2.M1.T1.S1).
    preview.sh           # UNCHANGED (chosen-window + self-session — P2.M1.T2.S1).
    restore.sh           # UNCHANGED here (P2.M2.T2 owns the keep-skips-ORIG_WINDOW fix).
    options.sh utils.sh rank.sh layout.sh renderer.sh livepicker.sh session-mgmt.sh  # UNCHANGED
  README.md              # MODIFY: 2 one-line prose touches (L12, L169).
  tests/                 # UNCHANGED (formal window suite is P2.M3.T1.S1).
  plan/004_2c5127285a90/{architecture/gap_analysis_confirm_preview.md, architecture/external_deps.md,
                        P2M1T3S2/PRP.md, P2M1T3S1/PRP.md, P2M1T2S1/PRP.md, P2M1T1S1/PRP.md}
```

### Desired Codebase tree with files to be added and responsibility of file

```bash
scripts/input-handler.sh   # confirm) session-mode: resolve W from the window cursor; commit it in S
                           #   (select-window =$S:$W) for non-self / select-window $W for self; the one
                           #   switch (non-self only); H2-hardened driver-preview unlink before the switch;
                           #   restore.sh keep. Self skips switch-client. Window-mode + create UNCHANGED.
README.md                  # Confirm prose: "…the chosen session AND the exact window being previewed…"
```

### Known Gotchas of our codebase & Library Quirks

```bash
# CRITICAL (FINDING 6 — HARD DEPENDENCY): this task calls `restore.sh keep`. TODAY restore
# STEP-2 re-selects ORIG_WINDOW on `keep` (only `keep-window` skips it). Correct window-
# landing therefore DEPENDS ON P2.M2.T2 (same milestone) making `keep` skip the re-select.
# If this lands first, the client is re-selected to ORIG_WINDOW until P2.M2.T2 lands. The
# contract mandates `keep` (the post-unification canonical form); do NOT switch to keep-window.

# CRITICAL (FINDING 4): use `select-window -t "=$S:$W"` (W is a server-global @id). The
# `=$S:@id` form is VERIFIED on 3.6b (external_deps.md §1) -> NO fallback. For self use the
# bare `select-window -t "$W"` (current session == driver).

# CRITICAL (FINDING 3 — authoritative W): resolve W from STATE_CAND_WIN_CURSOR/LIST, NEVER
# from STATE_LINKED_ID/STATE_PREVIEW_WIN_ID (the deferred preview may lag). LIST is non-empty
# ONLY post-flip (SESSION==S); else default to S's active window. Keep the `cand_win_sess == S`
# guard (defense-in-depth vs the P2.M1.T3.S2 merge ordering).

# CRITICAL (FINDING 4 — unlink order): for NON-SELF, unlink the DRIVER's preview link BEFORE
# switch-client, targeting ORIG_SESSION (NOT the post-switch current session). Mirror the
# H2-hardened guard: only unlink when `drv_wins > 1 OR drv_active != linked_id` (else unlinking
# the driver's only window KILLS it, rc=0). `linked_id` may be empty -> skip.

# CRITICAL (FINDING 7 — indentation): the session-mode `else` body is 5 TABS; `else`/`fi` are
# 4 TABS. A space oldText won't match. The § and — are UTF-8 — copy verbatim. set -u (NOT -e):
# guard select-window/switch-client/unlink-window with `if`/`2>/dev/null || true`.

# GOTCHA: split `local` declarations from `$(...)` assignments (house style; avoids SC2155):
#   local cand_win_sess cand_list cand_cursor W
#   cand_win_sess="$(get_state "$STATE_CAND_WIN_SESSION" "")"   # NOT `local x="$(...)"`.
# `local S="$target"` is fine (plain var, no command sub).

# GOTCHA: `target`, `pick_type`, `orig_session`, `linked_id` are ALREADY declared in input_main's
# `local` line (~L249) -> reuse them; declare only the new S/W/cand_*/drv_*.

# GOTCHA: do NOT touch the window-mode `if` branch, the empty-list create path, or
# _confirm_land_on_session. The create path still calls _confirm_land_on_session (a brand-new
# session has one window — no window choice).
```

## Implementation Blueprint

### Data models and structure

No new data model / state keys. The confirm reads `STATE_LIST`/`STATE_FILTER`/
`STATE_INDEX` (target S), `STATE_CAND_WIN_SESSION`/`LIST`/`CURSOR` (window W),
`STATE_LINKED_ID` (the driver preview to unlink), `ORIG_SESSION` (driver +
self-test). It mutates only tmux session/window state (one `select-window`, one
`switch-client`, one `unlink-window`) and hands off to `restore.sh keep`.

The W-resolution state machine:

| last user action | SESSION | LIST | CURSOR | resolved W |
|---|---|---|---|---|
| session-nav to S (no flip) | `S` | `""` | `"0"` | S active window |
| flip on S (next/prev-window) | `S` | `<S window @ids>` | `<flipped idx>` | `LIST[cursor]` |
| type/backspace/cancel-clear | `""` | `""` | `"0"` | top-match active window |

### Implementation Tasks (ordered by dependencies)

```yaml
Task 1: EDIT scripts/input-handler.sh — rework the confirm session-mode `else` body
  - FILE: ./scripts/input-handler.sh (EXISTING). confirm) branch, the `else` of
    `if [ "$pick_type" = "window" ]; then` (~L605-608). The body is 5-TAB indent;
    `else`/`fi` are 4-TAB.
  - oldText — COLUMN-0 fenced block; each leading char is a real TAB
    (else = 4 TABs; body = 5 TABs). The `—` is a UTF-8 em-dash. Copy byte-exact:

```bash
				else
					# Session mode: the helper unlinks the driver preview BEFORE
					# switch-client (FINDING 1/2 — load-bearing), switches once,
					# and tears down with restore keep.
					_confirm_land_on_session "$target"
```

  - newText — COLUMN-0 fenced block (else/fi = 4 TABs; body = 5 TABs; nested
    6/7/8). The trailing 4-TAB `fi` that closes `if [ "$pick_type" = "window" ]`
    is NOT included (it stays). Copy byte-exact:

```bash
				else
					# Session mode (PRD §6 Confirm / h3.7 + §4 Invariant B). Commit the chosen
					# WINDOW W in S, then the one session switch, then restore keep. W is resolved
					# AUTHORITATIVELY from the window-cursor state (NOT the possibly-lagged preview
					# link — PRD §18 contract #4): the window currently previewed/flipped for S,
					# defaulting to S's active window when no flip occurred.
					local S="$target"
					# Resolve W (mirror the flip branch's lazy-derive). STATE_CAND_WIN_LIST is
					# non-empty ONLY when the user flipped windows on S (P2.M1.T3.S2 invalidates it
					# on every move/filter change; the flip re-binds SESSION=S + populates LIST).
					local cand_win_sess cand_list cand_cursor W
					local -a _cwin=()
					cand_win_sess="$(get_state "$STATE_CAND_WIN_SESSION" "")"
					cand_list="$(get_state "$STATE_CAND_WIN_LIST" "")"
					cand_cursor="$(get_state "$STATE_CAND_WIN_CURSOR" "0")"
					[[ "$cand_cursor" =~ ^[0-9]+$ ]] || cand_cursor=0
					W=""
					if [ "$cand_win_sess" = "$S" ] && [ -n "$cand_list" ]; then
						mapfile -t _cwin < <(printf '%s
' "$cand_list")
						if [ "$cand_cursor" -ge 0 ] && [ "$cand_cursor" -lt "${#_cwin[@]}" ]; then
							W="${_cwin[$cand_cursor]}"
						fi
					fi
					# No flip (LIST empty) / stale cache / cursor out of range -> S's ACTIVE window.
					if [ -z "$W" ]; then
						W="$(tmux list-windows -t "=$S" -F '#{window_id}' -f '#{window_active}' 2>/dev/null)"
					fi
					orig_session="$(get_state "$ORIG_SESSION" "")"
					if [ "$S" = "$orig_session" ]; then
						# SELF-SESSION (PRD §6: S == ORIG_SESSION). NO switch-client. The single
						# select-window -t "$W" (a DRIVER window @id) is the whole commit. Drop a
						# prior CROSS-session preview link ONLY when linked_id is set AND != W (a
						# non-self candidate previewed earlier can leave a foreign link).
						if [ -n "$W" ]; then
							tmux select-window -t "$W" 2>/dev/null || true
						fi
						linked_id="$(get_state "$STATE_LINKED_ID" "")"
						if [ -n "$linked_id" ] && [ "$linked_id" != "$W" ] && [ -n "$orig_session" ]; then
							tmux unlink-window -t "$orig_session:$linked_id" 2>/dev/null || true
						fi
						"$CURRENT_DIR/restore.sh" keep
					else
						# NON-SELF (PRD §6/h3.7). (1) Commit W in S — the single deliberate candidate
						# mutation (Invariant B); select-window -t "=$S:@id" is verified on 3.6b
						# (external_deps.md §1), no fallback. (2) Unlink the DRIVER's preview link
						# BEFORE the switch (mirror _confirm_land_on_session's H2-hardened unlink:
						# target ORIG_SESSION, NOT the post-switch session; only unlink when the
						# driver retains another window). (3) switch-client -t "=$S" (the one switch;
						# the client lands on S:W — W is already active in S). (4) restore keep.
						if [ -n "$W" ]; then
							tmux select-window -t "=$S:$W" 2>/dev/null || true
						fi
						linked_id="$(get_state "$STATE_LINKED_ID" "")"
						if [ -n "$linked_id" ] && [ -n "$orig_session" ]; then
							local drv_wins drv_active
							drv_wins="$(tmux list-windows -t "=$orig_session" 2>/dev/null | wc -l)"
							drv_active="$(tmux list-windows -t "=$orig_session" -F '#{window_id}' -f '#{window_active}' 2>/dev/null)"
							if [ "$drv_wins" -gt 1 ] || [ "$drv_active" != "$linked_id" ]; then
								tmux unlink-window -t "$orig_session:$linked_id" 2>/dev/null || true
							fi
						fi
						tmux switch-client -t "=$S" 2>/dev/null || true
						"$CURRENT_DIR/restore.sh" keep
					fi
```

  - FOLLOW pattern: the window-mode `if` branch above it (the H2-hardened unlink is copied
    verbatim) + the next-window flip branch (the lazy-derive W resolution).
  - NAMING: local vars _-prefixed or short (S, W, cand_win_sess, drv_wins) — house style.
  - DEPENDENCIES: STATE_CAND_WIN_* (P2.M1.T1.S1), preview chosen-window (P2.M1.T2.S1),
    flip actions (P2.M1.T3.S1), cursor resets (P2.M1.T3.S2), restore keep fix (P2.M2.T2).

Task 2: EDIT README.md — two prose touches (Mode A docs)
  - FILE: ./README.md (EXISTING).
  - Edit A (overview, L12-13):
    - oldText:
      Confirming lands you on the chosen session (optionally creating a new one from
      your filter query); cancelling restores your status line, key table, and focus
    - newText:
      Confirming lands you on the chosen session **and the exact window being
      previewed**, not just the session (optionally creating a new one from
      your filter query); cancelling restores your status line, key table, and focus
  - Edit B (workflow list, L169-170):
    - oldText:
      5. **Confirm:** `Enter` lands on the selection, or creates a session from
         your query in `session` mode with no match.
    - newText:
      5. **Confirm:** `Enter` lands on the chosen session **and the exact window
         being previewed** (not just the session), or creates a session from
         your query in `session` mode with no match.
  - WHY: contract DOCS = Mode A; the one-line prose change. Do NOT rewrite the paragraph.

Task 3: VALIDATE (L1 grep + L2 suite + L3 confirm-on-window smoke)
  - RUN: bash -n scripts/input-handler.sh ; shellcheck scripts/input-handler.sh.
  - RUN: grep cross-checks (the new logic; the window-mode/create/helper untouched).
  - RUN: tests/run.sh (expect GREEN; confirm is reached only via Enter on the no-flip path).
  - RUN: L3 isolated-socket confirm-on-window smoke (activate → flip → Enter → assert S:W;
         self: flip driver → Enter → assert driver:W, no switch). Deterministic (defer off).
```

### Implementation Patterns & Key Details

```bash
# === W resolution (FINDING 3 — mirror the flip branch's lazy-derive; AUTHORITATIVE). ===
local cand_win_sess cand_list cand_cursor W
local -a _cwin=()
cand_win_sess="$(get_state "$STATE_CAND_WIN_SESSION" "")"
cand_list="$(get_state "$STATE_CAND_WIN_LIST" "")"
cand_cursor="$(get_state "$STATE_CAND_WIN_CURSOR" "0")"
[[ "$cand_cursor" =~ ^[0-9]+$ ]] || cand_cursor=0
W=""
if [ "$cand_win_sess" = "$S" ] && [ -n "$cand_list" ]; then
    mapfile -t _cwin < <(printf '%s\n' "$cand_list")
    if [ "$cand_cursor" -ge 0 ] && [ "$cand_cursor" -lt "${#_cwin[@]}" ]; then
        W="${_cwin[$cand_cursor]}"
    fi
fi
[ -z "$W" ] && W="$(tmux list-windows -t "=$S" -F '#{window_id}' -f '#{window_active}' 2>/dev/null)"

# === SELF (S == ORIG_SESSION): no switch; one select-window; conditional foreign-link drop. ===
if [ "$S" = "$orig_session" ]; then
    [ -n "$W" ] && tmux select-window -t "$W" 2>/dev/null || true
    linked_id="$(get_state "$STATE_LINKED_ID" "")"
    if [ -n "$linked_id" ] && [ "$linked_id" != "$W" ] && [ -n "$orig_session" ]; then
        tmux unlink-window -t "$orig_session:$linked_id" 2>/dev/null || true
    fi
    "$CURRENT_DIR/restore.sh" keep

# === NON-SELF: commit W -> H2-unlink driver -> switch -> restore keep. ===
else
    [ -n "$W" ] && tmux select-window -t "=$S:$W" 2>/dev/null || true   # =S:@id verified (§1)
    linked_id="$(get_state "$STATE_LINKED_ID" "")"
    if [ -n "$linked_id" ] && [ -n "$orig_session" ]; then
        local drv_wins drv_active
        drv_wins="$(tmux list-windows -t "=$orig_session" 2>/dev/null | wc -l)"
        drv_active="$(tmux list-windows -t "=$orig_session" -F '#{window_id}' -f '#{window_active}' 2>/dev/null)"
        if [ "$drv_wins" -gt 1 ] || [ "$drv_active" != "$linked_id" ]; then
            tmux unlink-window -t "$orig_session:$linked_id" 2>/dev/null || true   # H2 guard
        fi
    fi
    tmux switch-client -t "=$S" 2>/dev/null || true   # the ONE switch; lands on S:W
    "$CURRENT_DIR/restore.sh" keep
fi
```

### Integration Points

```yaml
INPUT-HANDLER (input-handler.sh confirm) branch):
  - REPLACE the session-mode `else` body (_confirm_land_on_session call) with the W-resolution
    + self/non-self commit. Window-mode `if` branch + empty-list create path UNCHANGED.

STATE (state.sh): NO CHANGE. Reads STATE_CAND_WIN_SESSION/LIST/CURSOR + STATE_LINKED_ID +
  ORIG_SESSION; all exist (P2.M1.T1.S1).

PREVIEW (preview.sh): NO CHANGE (P2.M1.T2.S1). Confirm consumes the window-cursor state the
  flip subsystem wrote; it does NOT depend on the deferred preview link (PRD §18 #4).

RESTORE (restore.sh): calls `keep`. HARD DEPENDENCY on P2.M2.T2 (keep must skip the
  ORIG_WINDOW re-select). STEP-1's client-aware unlink is skipped after the switch, so THIS
  path unlinks the driver preview BEFORE the switch.

ACTIVATE (livepicker.sh): NO CHANGE. Window-cursor keys init'd at activate (P2.M1.T1.S1).

README.md: 2 one-line prose touches (Task 2).

DATABASE / MIGRATIONS / ROUTES / CONFIG-FILE: none.
```

## Validation Loop

### Level 1: Syntax & Style (Immediate Feedback)

```bash
cd /home/dustin/.config/tmux/plugins/tmux-livepicker
bash -n scripts/input-handler.sh && echo "OK: syntax"            # expect exit 0
shellcheck scripts/input-handler.sh                               # expect 0 findings
# The new session-mode commit is present (select-window =$S:$W for non-self):
grep -c 'select-window -t "=\$S:\$W"' scripts/input-handler.sh    # == 1 (the non-self commit)
# The self-session no-switch path is present:
grep -c 'if \[ "\$S" = "\$orig_session" \]' scripts/input-handler.sh   # == 1
# W is resolved from the window cursor (authoritative):
grep -c 'STATE_CAND_WIN_CURSOR' scripts/input-handler.sh          # >= 1 in the confirm body
# The create path STILL calls _confirm_land_on_session (UNCHANGED — a new session has 1 window):
grep -c '_confirm_land_on_session "\$created"' scripts/input-handler.sh   # == 1
# The session-mode _confirm_land_on_session "$target" call is GONE (replaced):
grep -c '_confirm_land_on_session "\$target"' scripts/input-handler.sh    # == 0
# restore.sh keep is called (NOT keep-window) in the session-mode path:
grep -c 'restore.sh" keep' scripts/input-handler.sh               # >= 2 (self + non-self)
# SCOPE GUARD: the window-mode branch's keep-window is untouched:
grep -c 'restore.sh" keep-window' scripts/input-handler.sh        # == 1
# No space-indent on the new lines (tabs only) — warn if any:
grep -Pn '^\t*    [^#/]' scripts/input-handler.sh | tail && echo "WARN: space-indent" || echo "OK: tabs"
# Expected: =$S:$W == 1; self-test == 1; cursor read present; created-call == 1; target-call == 0;
#           keep >= 2; keep-window == 1; tabs only.
```

### Level 2: Full suite (no regression)

```bash
cd /home/dustin/.config/tmux/plugins/tmux-livepicker
tests/run.sh
# Expected: exit 0, all green. Confirm is reached only via Enter; existing tests press Enter on the
# NO-FLIP path (cursor default -> active window) so the new W-resolution defaults to the active
# window (behaviorally identical to the old _confirm_land_on_session for those tests). The formal
# flip+confirm-on-window suite is P2.M3.T1.S1. NOTE: the window-landing assertion (Level 3) is THIS
# task's positive gate; if the suite is red from a P2.M2.T2 not-yet-landed intermediate (keep still
# re-selects ORIG_WINDOW), that is P2.M2.T2's fix — verify keep skips ORIG_WINDOW after it lands.
```

### Level 3: Confirm lands on (S, W) — isolated socket, deterministic (defer off)

```bash
cat > /tmp/smoke_confirm_window.sh <<'EOF'
#!/usr/bin/env bash
set -u
cd /home/dustin/.config/tmux/plugins/tmux-livepicker
source tests/setup_socket.sh; source tests/helpers.sh
fail=0
setup_test "lp-confirmwin"; attach_test_client
tmux set-option -g @livepicker-preview-defer off   # deterministic synchronous preview
# A multi-window candidate to flip on.
tmux new-session -d -s multi -x 120 -y 40
tmux new-window -t multi -n secondwin        # multi now has 2 windows
# Activate; highlight starts on driver (index 0). Move to multi, flip to the NON-active window.
"$LIVEPICKER_SCRIPTS/livepicker.sh"                       # activate
"$LIVEPICKER_SCRIPTS/input-handler.sh" next-session >/dev/null 2>&1 || true   # highlight -> multi
"$LIVEPICKER_SCRIPTS/input-handler.sh" next-window  >/dev/null 2>&1 || true   # flip multi's windows
sleep 0.2
# Resolve the window the cursor points at (the chosen W) DYNAMICALLY (window ids are global).
exp_sess="multi"
exp_win="$(tmux show-option -gqv @livepicker-cand-win-cursor 2>/dev/null)"
# Derive the actual @id the cursor selects from the cached list (mirror the confirm resolution).
_cl="$(tmux show-option -gqv @livepicker-cand-win-list)"
_wl=""; while IFS= read -r _ln; do _wl="$_wl$_ln "; done <<<"$_cl"
exp_id="$(awk -v c="$exp_win" 'NR==(c+1){print; exit}' <<<"$_cl")"
# Confirm -> should land on multi:exp_id.
"$LIVEPICKER_SCRIPTS/input-handler.sh" confirm >/dev/null 2>&1 || true
sleep 0.2
got_sess="$(tmux display-message -p '#{session_name}' 2>/dev/null)"
got_win="$(tmux display-message -p '#{window_id}'  2>/dev/null)"
echo "[non-self flip] want sess=$exp_sess win=$exp_id ; got sess=$got_sess win=$got_win"
[ "$got_sess" = "$exp_sess" ] || { echo "FAIL: session != $exp_sess"; fail=1; }
[ "$got_win"  = "$exp_id"   ] || { echo "FAIL: window != $exp_id (did keep re-select ORIG_WINDOW? P2.M2.T2)"; fail=1; }
teardown_test
[ "$fail" -eq 0 ] && echo "ALL OK: confirm lands on the chosen (session, window)" || exit 1
EOF
bash /tmp/smoke_confirm_window.sh; rc=$?; rm -f /tmp/smoke_confirm_window.sh; exit $rc
# Expected: the client lands on multi:<the flipped window id>. If `got_win` is the driver's
# ORIG_WINDOW, P2.M2.T2 (restore keep skips ORIG_WINDOW) has not landed — re-run after it does.
#
# SELF-SESSION variant (flip the driver, confirm, assert no switch):
#   activate -> (highlight stays on driver) -> next-window (flip driver's windows) -> confirm
#   -> assert #{session_name} == driver AND #{window_id} == the flipped driver window (NOT ORIG_WINDOW).
#   (Add as a second setup_test block mirroring the above with exp_sess=driver.)
```

### Level 4: Creative & Domain-Specific Validation

```bash
# (1) No-orphan regression (PRD §16/§7): after a non-self confirm on a flipped window, the driver
#     must NOT retain the preview link. Repeat L3 and assert the driver's window-id list no longer
#     contains the previously-linked candidate window (the H2-unlink before the switch removed it).
# (2) Invariant B (no candidate mutation while BROWSING): capture a NON-confirmed candidate's
#     #{window_active} + #{window_layout} before browsing; navigate + flip OTHER sessions; assert
#     the bystander is byte-identical (the flip never select-windows on a candidate — only confirm
#     does, on the ONE confirmed candidate). (The formal suite is P2.M3.T1.S1 / P3.M3.T1.S1.)
# (3) Self-session no-switch: with @livepicker-preview-defer off, flip the driver to a non-ORIG
#     window and confirm; assert #{session_name} == driver (no switch-client fired) and the client
#     is on the flipped window. This is the PRD §6 "self: skip switch-client" guarantee.
```

## Final Validation Checklist

### Technical Validation

- [ ] `bash -n` + `shellcheck` clean on `scripts/input-handler.sh`.
- [ ] The session-mode `else` body resolves W from `STATE_CAND_WIN_CURSOR/LIST` (default active
      window) and commits it; `_confirm_land_on_session "$target"` is gone (L1 == 0); the
      `$created` call remains (L1 == 1).
- [ ] Non-self: `select-window -t "=$S:$W"` (L1 == 1); self: `select-window -t "$W"`.
- [ ] `restore.sh keep` is called in both the self and non-self paths (L1 >= 2); the window-mode
      `keep-window` is untouched (L1 == 1).
- [ ] Indentation correct (5-tab session-mode body; 4-tab else/fi); tabs only (no spaces).

### Feature Validation

- [ ] Non-self: flipping to a candidate's non-active window + `Enter` lands on (candidate, that
      window) — Level 3.
- [ ] Self: flipping the driver + `Enter` lands on the driver window with no `switch-client`
      (Level 4.3).
- [ ] No orphan preview leaks into the driver (H2-hardened unlink before the switch) — Level 4.1.
- [ ] Bystander candidates are byte-unchanged by browsing (Invariant B) — Level 4.2.
- [ ] `tests/run.sh` GREEN (Level 2); correct window-landing requires P2.M2.T2 landed (keep skips
      ORIG_WINDOW).

### Code Quality Validation

- [ ] W is resolved AUTHORITATIVELY from `STATE_CAND_WIN_*`, never from `STATE_LINKED_ID`/
      `STATE_PREVIEW_WIN_ID` (PRD §18 #4).
- [ ] The non-self unlink mirrors the H2-hardened guard (`drv_wins > 1 OR drv_active != linked_id`),
      targets `ORIG_SESSION`, and runs BEFORE `switch-client`.
- [ ] `set -u` honored (split `local`/`$(...)`, `get_state … ""`, sanitized cursor); non-zero rc
      swallowed (`|| true`).
- [ ] Uses `$CURRENT_DIR` (NOT `$SCRIPT_DIR`); sources the existing libs only.
- [ ] Window-mode branch + create path + `_confirm_land_on_session` byte-unchanged.

### Documentation & Deployment

- [ ] README L12 + L169 mention the chosen window (Task 2).
- [ ] No CHANGELOG edit (the changeset CHANGELOG is P4.M1.T1.S2).
- [ ] No new test FILE (the formal window suite is P2.M3.T1.S1); L3 is a throwaway smoke.

---

## Anti-Patterns to Avoid

- ❌ Don't resolve W from `STATE_LINKED_ID` / `STATE_PREVIEW_WIN_ID`. The deferred preview may lag
  (PRD §18 #4); the window cursor is synchronous + authoritative. Read `STATE_CAND_WIN_CURSOR/LIST`.
  (FINDING 3.)
- ❌ Don't drop the `cand_win_sess == S` guard in the W-resolution. LIST is only non-empty post-flip
  (P2.M1.T3.S2 invalidates it on every move/filter change), so the guard is usually a no-op — but it
  is correct under any merge ordering with S2 and prevents trusting a stale list. (FINDING 3.)
- ❌ Don't `switch-client` for the self-session. PRD §6: self does ONE `select-window -t "$W"` and no
  switch. A redundant same-session switch still fires (deduped) `client-session-changed` and is
  pointless. (FINDING 5.)
- ❌ Don't unlink the driver preview AFTER `switch-client`. STEP-1 of `restore.sh keep` is
  client-aware and is SKIPPED after the switch (current_session != ORIG_SESSION) — so the driver
  preview would leak. Unlink BEFORE the switch, targeting `ORIG_SESSION` explicitly (mirror
  `_confirm_land_on_session`). (FINDING 4.)
- ❌ Don't unlink unconditionally. Mirror the H2-hardened guard: only unlink when `drv_wins > 1 OR
  drv_active != linked_id` (else unlinking the driver's only window KILLS it, rc=0). Skip when
  `linked_id` is empty. (FINDING 4.)
- ❌ Don't touch the window-mode `if` branch, the empty-list create path, or `_confirm_land_on_session`.
  The create path still calls the helper (a brand-new session has one window — no window choice).
  (FINDING 1.)
- ❌ Don't switch `restore.sh keep` to `keep-window` to dodge the P2.M2.T2 dependency. The contract
  mandates `keep` (the post-unification canonical form); `keep-window` is the window-MODE picker's
  arg. Use `keep` and ensure P2.M2.T2 lands. (FINDING 6.)
- ❌ Don't use SPACES for indent. The session-mode body is 5 TABS; `else`/`fi` are 4. Preserve the
  §/— UTF-8 chars in the oldText. (FINDING 7.)
- ❌ Don't combine `local x="$(...)"`. Split declaration from command-substitution assignment (house
  style; avoids shellcheck SC2155). `local S="$target"` is fine (plain var). (FINDING 9.)
- ❌ Don't add a fallback for `select-window -t "=$S:@id"`. It is VERIFIED on 3.6b (external_deps.md
  §1). The delta_prd contingency is not triggered.

---

## Confidence Score

**8 / 10** for one-pass success. Rationale: the change is ONE localized region (the 5-tab
session-mode `else` body) in ONE file, replacing a single helper call with self-contained
W-resolution + a self/non-self branch that reuses TWO verbatim, already-proven patterns (the
flip branch's lazy-derive for W; the window-mode confirm's H2-hardened unlink). The verified
`=$S:@id` form removes the only external unknown (external_deps.md §1). The two non-obvious
load-bearing details are both nailed: (1) W is resolved AUTHORITATIVELY from the window cursor
(not the lagging preview link — PRD §18 #4), with the `cand_win_sess == S` guard as
defense-in-depth vs the P2.M1.T3.S2 merge ordering (FINDING 3); (2) the non-self unlink runs
BEFORE `switch-client`, targeting `ORIG_SESSION` with the H2 guard (FINDING 4). Residual risk:
the HARD DEPENDENCY on P2.M2.T2 (`restore.sh keep` must skip the ORIG_WINDOW re-select) — if
that sibling has not landed, the L3 window-landing assertion will show ORIG_WINDOW until it does
(FINDING 6). The `bash -n`/`shellcheck` + suite-green + L3 smoke (with the P2.M2.T2 caveat) are
the firm gates. The §/— UTF-8 chars in the oldText must be copied verbatim.
