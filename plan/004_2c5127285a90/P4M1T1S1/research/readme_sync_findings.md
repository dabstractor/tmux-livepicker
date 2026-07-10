# README.md two-axis changeset sync (P4.M1.T1.S1) — research synthesis

> TL;DR for the PRP author. Documentation-only task (Mode B). Edits ONE file:
> `README.md`. The two-axis / window-flip / confirm-on-window / pane-immutability
> changeset (P1+P2+P3 of plan 004) shipped its Mode-A README edits scattered
> across the Configuration table, the Usage numbered steps, and Known
> limitations. This task FOLDS them into two coherent subsections (Two-axis
> navigation, Window preview), fixes the stale single-axis references that now
> contradict the shipped feature, verifies the §23 limitation reconciliation,
> and passes the write-tech-docs style rules. No code, no PRD, no CHANGELOG
> (P4.M1.T1.S2 owns the CHANGELOG entry).

## 0. Environment note: the write-tech-docs skill is NOT on disk here

`/home/dustin/.pi/agent/skills/write-tech-docs/` does not exist in this
environment (no SKILL.md, no scripts/lint.sh; `find` under ~/.pi returns
nothing). The skill is also NOT in this session's available_skills list. So the
PRP must encode the style rules DIRECTLY and use a grep-based gate instead of
lint.sh. The rules (well-defined, stable):
1. No em dashes (U+2014). Use a colon, parentheses, comma, or period.
2. No marketing tell-words (powerful, robust, elegant, seamless, comprehensive,
   leverage, utilize, unlock, streamline, elevate, delve, moreover, furthermore,
   truly, incredibly, etc.).
3. No hedging/formulaic transitions (moreover, furthermore, "it's worth noting").
4. Do not narrate the codebase; document what/why/how-to/gotchas.
5. No prose paragraph over ~100 words / ~4 sentences.
6. Active voice, imperative for steps, one idea per sentence, consistent terms.

Gate (lint.sh-free): `grep -cP '\x{2014}' README.md` == 0; grep the tell-word
list == 0; eyeball paragraph length. (If the skill IS present at implementation
time, also run `bash <skill>/scripts/lint.sh README.md` and require exit 0.)

## 1. Current README state (verified; item's "18956 bytes" is stale)

Actual: 20228 bytes. Structure:
```
  6  ## Overview
 19  ## Goals               ← has a STALE "Filter + repurposed navigation" goal
 33  ## Non-goals
 41  ## User stories        ← STALE Navigate bullet (window keys "move sessions")
 59  ## Installation
 90  ## Configuration
      table  ← already has the 4 two-axis options (session/window next/prev-keys)
134    ### Appearance
140    ### Performance
144    ### Status line
155  ## Usage               ← steps 3 (navigate sessions) + 4 (flip windows) present
188    ### Session management
201  ## How it works        ← short paragraph (no Window preview subsection)
212    ### Known limitations ← ALREADY reconciled with clip + candidate pin + snapshot
219  ## Compatibility
237  ## Validation          ← STALE "Key repurpose" cluster; missing two-axis/flip/immutability
256  ## Maintenance
```

So (c) Known-limitations reconciliation and (d) the 4 two-axis table rows are
ALREADY DONE. The real work is: two NEW subsections (a, b) + fixing the stale
references + the em-dash/lint gate.

## 2. Stale references that MUST be fixed (they contradict the shipped feature)

| Where | Current (stale) text | Why wrong | Fix |
|---|---|---|---|
| Overview ~L11 | "move the selection with your usual window-navigation keys" | single-axis; window keys now FLIP windows, not move sessions | two-axis: move between sessions with session-nav keys; flip a session's windows with window-nav keys |
| Goals ~L24 | "**Filter + repurposed navigation.** Type to filter; move with keys you already use to navigate windows." | single-axis "repurposed" model (the design the PRD §8 explicitly DROPPED) | replace with a two-axis goal; ADD a confirm-on-window goal and a leave-no-trace goal (PRD §2) |
| User stories ~L45 | "**Navigate.** I press my next/previous window keys and the selection moves to a different session" | flat-out WRONG: window keys now flip the previewed session's windows | split into a session-nav story (move between sessions) and a window-nav story (flip windows live, candidate's own active window unchanged) per PRD §3 |
| User stories ~L50 | "**Confirm.** I press `Enter` and land on the selected session." | omits the window | "...land on the chosen session AND the exact window I was previewing" |
| Validation ~L253 | "**Key repurpose:** repurposed window-nav keys revert on cancel." | stale terminology + stale cluster list | two-axis / key-discovery; update the cluster list to the ACTUAL test files (run `ls tests/test_*.sh`) incl. window-flip, confirm-on-window, key discovery, pane immutability |
| README L103, L169 | two em dashes (U+2014) | write-tech-docs bans em dashes | convert to colon/paren/comma (see §0) |

## 3. The two NEW subsections mapped to exact PRD content

### (a) "Two-axis navigation" subsection (PRD §8 + §2 Goals + §3 stories)

Two navigation axes; BOTH reuse the keys the user already has for that axis,
discovered from their live key tables; both overridable.

- **Session axis** (move the highlight between candidate sessions): defaults to
  the user's `switch-client -n` / `-p` bindings PLUS the arrow keys
  (`Down`=next, `Up`=prev). Overridable via `@livepicker-session-next-keys` /
  `-session-prev-keys`.
- **Window axis** (flip through the highlighted session's windows in the
  preview, live): defaults to the user's `next-window` / `previous-window` /
  `select-window -n` / `-p` bindings (incl. the `swap-window ... ; select-window`
  compounds). Overridable via `@livepicker-window-next-keys` /
  `-window-prev-keys`.
- **Discovery** (only when the option is unset): read `tmux list-keys -T root`
  and `-T prefix`; match the window-axis command substrings; for the session
  axis match `switch-client -n` / `-p` (NOT `-l` toggle or `-t <name>`); always
  add the arrows to the session axis. Drop any plain `a`-`z` / `A`-`Z` / `0`-`9`
  (those stay reserved for the query); keep control/meta/arrow/function keys.
  De-duplicate; exclude the fixed control keys (confirm/cancel/backspace/
  rename/delete). Explicit options OVERRIDE discovery.
- **Non-alphanumeric constraint:** every nav/confirm/cancel/backspace/management
  key is non-alphanumeric because plain letters/digits are reserved for the
  query. A plain letter/digit used for nav is silently untypeable. If a user
  wants vim-style `j`/`k` session-nav they set the option explicitly, accepting
  those letters become untypeable.
- **Low-cost revert:** the picker uses a modal key table; on cancel the table
  switches back (typically `root`), so the bindings revert for free.

### (b) "Window preview" note (PRD §6 Confirm + Window navigation + §4 Invariants)

Two facts:
- **Confirm lands on the exact window being previewed.** Confirm resolves the
  target session S from the ranked list and the target window W from the window
  cursor (the window currently being previewed for that session). It commits W
  in S with one `select-window`, then `switch-client`s. The client lands on
  (S, W), the exact tab being previewed. (For the self-session, or snapshot/off
  preview modes with no chosen window, W is the session's active window.)
- **Flipping never changes the candidate's own active window (leave-no-trace).**
  Window-nav flips link the chosen window into the driver and select it THERE;
  they never call `select-window` on the candidate session, so the candidate's
  own active window and pane layout never change while browsing (Invariant B).
  Moving to another session, or cancelling, leaves every peeked candidate
  exactly as it was. Confirm is the ONE deliberate mutation (the single
  `select-window` that commits the chosen window). Everything else is read-only.
  (Pane geometry immutability across all sessions is the stronger §23 guarantee;
  see Known limitations.)

## 4. §23 limitation reconciliation (deliverable c) — VERIFY, it appears done

The current `### Known limitations` already reconciles the detached-candidate
resize with §23. Verify it states (PRD §23 + §22 + the candidate-pin gate
`pane_immutability_verification.md`):
- Status-grow reflow fixed by default `clip` (driver height pinned pre-grow).
- Detached candidates are PINNED at link time in `clip` mode (window-size manual
  + window-height pin, restored on leave) -> their panes do not reflow and their
  own session keeps its original geometry after exit.
- Client-bearing candidates CANNOT be pinned (a manual pin would revert their
  attached client's view to the creation size); the bare link does not disturb
  them, but for STRICT pane-immutability across client-bearing sessions set
  `@livepicker-preview-mode snapshot` (capture-pane, never links a live window).
- `reflow` is the legacy escape hatch (candidates resize at link time); `clip`
  (default) and `snapshot` both avoid candidate reflow.

If the current text already says this coherently (it does), only de-em-dash /
tighten it. Do NOT rewrite it wholesale.

## 5. Placement decisions (recommendations; read README fully first)

- (a) **### Two-axis navigation** under `## Configuration` (after ### Status
  line). Rationale: it is the cross-cutting overview of the key model that the
  four `@livepicker-*-keys` options configure; consistent with the Appearance /
  Performance / Status line feature subsections. (A standalone ## Two-axis
  navigation between Configuration and Usage is also fine; pick one.)
- (b) **### Window preview** under `## How it works` (the leave-no-trace /
  confirm-on-window guarantees are mechanism). (A ### under ## Usage alongside
  ### Session management is also acceptable.)
- Fix the stale Overview / Goals / User-stories / Validation lines in place.
- Keep the Usage numbered steps (3 navigate sessions, 4 flip windows, 5
  confirm) but make them consistent with the new subsections (point to them;
  do not duplicate the full discovery detail in both places).

## 6. Validation (docs task, lint.sh-free)

- `grep -cP '\x{2014}' README.md` == 0 (no em dashes).
- `grep -niEw '<tell-words>' README.md` == 0 (seamless, powerful, robust,
  leverage, utilize, streamline, moreover, furthermore, truly, incredibly, ...).
- Stale refs gone: `grep -ni 'repurposed' README.md` empty; the Overview no
  longer says "usual window-navigation keys" alone.
- New subsections present: `grep -n 'Two-axis navigation' README.md` and
  `grep -n 'Window preview' README.md` each hit exactly once.
- The 4 two-axis options still present in the table (count via grep).
- Confirm-on-window + leave-no-trace phrasing present in the Window preview note.
- `ls tests/test_*.sh` reflected accurately in the Validation cluster list.
- `bash tests/run.sh` still exits 0 (README not sourced by any test; doc-only
  change cannot break it, but run it as a regression sanity check).
