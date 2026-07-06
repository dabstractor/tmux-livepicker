# Research: input-handler.sh `cancel` (P1.M6.T4.S1)

Empirically verified live on 2026-07-06 against `/usr/bin/tmux` (3.6b) on an
**isolated socket** (`tmux -L lp-t4verify-$$`, `kill-server`'d on exit) with an
attached client (via `script -qec`). Every `rc` / output below was observed.
This file is the ground-truth that makes the cancel branch safe and the
work-item §5 MOCKING assertion correct.

## The work-item crux (restated)

T4.S1 fills the LAST seam in `scripts/input-handler.sh` — the `cancel)` branch,
left as `return 0` by P1.M6.T1.S1. CONTRACT (work-item §1-§5), PRD §6 Cancel +
§9 + §14 + §11:

- **Two-step semantics (PRD §11 + work-item §1):** "the cancel key clears the
  query, or cancels if the query is empty."
  - **filter NON-empty** → set `@livepicker-filter=''`, `@livepicker-index=0`,
    `refresh-client -S`, `return` (clear the query; the picker STAYS OPEN).
  - **filter already empty** → call `restore.sh cancel` (full teardown +
    `switch-client` back to `ORIG_SESSION`; zero net history).
- **INVARIANT A (PRD §4 / §14 / system_context §3):** cancel must produce ZERO
  net session-history pollution. Both steps honor this (verified below).

This is the **simplest** of the six input-handler actions (no switch-client in
the cancel branch itself; no creation; no target resolution). The whole branch
is ~6 lines: a `cur_filter` read, a non-empty guard, a 3-line clear+reset+
refresh+`return`, and a `restore.sh cancel` fall-through. **No new locals, no
new helper, no new files.**

## Findings

### FINDING 1 — `set_state "$STATE_FILTER" ""` round-trips to `""` (set-empty reads as the empty default)  [VERIFIED]

`state.sh` `set_state` → `utils.sh` `tmux_set_opt` → `tmux set-option -g @x ""`.
Setting an `@`-option to `""` is a **set-empty**, NOT an unset — but `get_state`
→ `tmux_get_opt` does `[ -n "$v" ] && echo "$v" || echo "${2:-}"`, and an
empty-set option reads back as `""` (length 0), so the `[ -n "$v" ]` test is
FALSE → it returns the default `${2:-}`. For `STATE_FILTER` the default is `""`.
**Net:** `set_state "$STATE_FILTER" ""` then `get_state "$STATE_FILTER" ""`
yields `""` — byte-identical to the work-item's literal `@livepicker-filter=''`.

Verified live:
```
tmux set-option -g "@livepicker-filter" "abc"   -> raw=[abc]
tmux set-option -g "@livepicker-filter" ""       -> raw=[] len=0   -> get_state returns ""
```
This is the SAME mechanism `backspace` (T2.S1) relies on when it erases the last
char to `""`. So cancel's clear-filter step is a `set_state ""` (NOT an unset),
and it behaves identically to backspace-to-empty. **Do NOT use `tmux_unset_opt`
/ `-gu` here** — that would be a state teardown concern (restore owns it); the
contract is "clear the query", modeled exactly by `set_state "$STATE_FILTER" ""`.

### FINDING 2 — cancel's clear-filter step KEEPS the picker alive  [VERIFIED]

The work-item's load-bearing UX detail: "clear query, do NOT exit picker."
The clear-filter step writes ONLY two picker-INTERNAL runtime options
(`@livepicker-filter`, `@livepicker-index`) + a `refresh-client -S`. It does
NOT touch `@livepicker-mode`, `@livepicker-list`, `key-table`, `status`, the
status-format renderer, or the session-window-changed hook. Verified live:

```
BEFORE clear: mode=[on] filter=[be] list-set=yes kt=[livepicker] status=[2]
(set FILTER "" ; set INDEX 0 ; refresh-client -S)
AFTER  clear: mode=[on] filter=[]  idx=[0]   list-set=yes kt=[livepicker] status=[2]
client session still=[driver]
```

`@livepicker-mode` stays `on` (the activate double-activation guard still reads
"active"), `@livepicker-list` stays populated, `key-table` stays `livepicker`
(the modal key table is still live — the next keystroke is still captured), and
`status` stays grown at `2` (the renderer line is still installed and now
re-shows the FULL unfiltered list with index 0 highlighted, because an empty
filter matches everything — renderer FINDING 4 / filter.sh). The client never
moved. **The picker is provably still open after the first cancel press.**

### FINDING 3 — the clear-filter step is a SUPERSET of `backspace` (mirror it exactly)  [VERIFIED via T2.S1]

`backspace` (T2.S1, COMPLETE) does: read `cur_filter`; if non-empty, trim last
char + write; ALWAYS reset index=0; ALWAYS `refresh-client -S || true`. cancel's
clear-filter is the same shape with one difference: it writes `""` (the WHOLE
query) instead of `${cur_filter%?}` (one char). Both share:
- read `@livepicker-filter` via `get_state "$STATE_FILTER" ""` (defaults safe
  under `set -u`).
- guard on `[ -n "$cur_filter" ]` — if the filter is ALREADY empty, the
  clear-filter step is a no-op (writing `""` over `""` + refresh) AND we must
  NOT `return` (we fall through to `restore.sh cancel`). So the guard is the
  branch pivot: non-empty → clear + return; empty → fall through to cancel.
- ALWAYS reset `@livepicker-index` to `0` (PRD §6: a filter change snaps the
  highlight to the top match; safe even when the filtered list is empty — the
  renderer clamps, renderer FINDING 4).
- ALWAYS `tmux refresh-client -S 2>/dev/null || true` (forces the `#()` renderer
  to re-run so the picker redraws with the empty query + the full list; detached
  edge guard — mirror `backspace` / `type` / restore.sh STEP 6c).

**NO `preview.sh` call** in the clear-filter step. The work-item CONTRACT §3
lists ONLY `filter=''`, `index=0`, `refresh-client -S`, `return` — matching
backspace's contract (T2 FINDING 4: backspace does NOT call preview; the live
preview re-syncs on the next nav/confirm). Clearing the entire filter CAN change
which session sits at index 0 (re-admitting earlier matches), so the preview may
briefly show the pre-clear highlight — this is the SAME documented minor UX gap
as backspace, re-synced on the next nav/confirm. **Do NOT add a preview call —
it would diverge from the contract (backspace precedent) and risk scope creep.**

### FINDING 4 — the full-cancel path (filter empty) delegates to `restore.sh cancel`; ZERO net history  [VERIFIED via restore_keep_cancel FINDING A/B + TEST 2]

When the filter is already empty, cancel calls `"$CURRENT_DIR/restore.sh" cancel`.
`restore.sh` (COMPLETE, P1.M5, IMMUTABLE) runs its full teardown (STEP 1-6):
unlink the preview window (STEP 1, on `current_session` — which is the driver,
since cancel never switched the client; so it cleans the right link), re-select
`ORIG_WINDOW` (STEP 2), `switch-client -t "=$ORIG_SESSION"` (STEP 3, the cancel
branch), restore status/key-table/renumber/hook (STEP 4), restore layout
(STEP 5), `clear_all_state` + `unbind-key -a -T livepicker` + `refresh-client -S`
(STEP 6).

**The pollution invariant (PRD §14): cancel → 0 history entries.** PROVEN
(restore_keep_cancel FINDING A): during browse the client never left `ORIG`
(Invariant A — only `select-window`/`link-window` fired, NEVER
`switch-client`). So when restore STEP-3 does `switch-client -t "=ORIG_SESSION"`,
`to == ORIG == @session-history-current`, and the real `tmux-session-history`
engine's `do_hook` short-circuits on `[ "$to" = "$CURRENT" ] && return` →
**zero net history entries**. Verified live (TEST 2):
```
smart-dedup client-session-changed recorder seeded with "driver":
  switch-client -t "=driver" (client already on driver) -> 1 line total (0 new)
```
(A naive event counter would FALSE-FAIL — `client-session-changed` DOES fire on a
same-session switch, but the engine dedups. The MOCK recorder must dedup —
restore_keep_cancel FINDING B; same smart recorder the confirm_mock.sh uses.)

cancel issues ZERO `switch-client` ITSELF (the only switch is restore STEP-3,
and it is a deduped same-session switch). So cancel is pollution-safe BY
CONSTRUCTION — there is no FINDING-1/2-class catastrophic bug here (unlike
confirm, cancel never switches the client to a TARGET, so there is no
target-destruction / driver-preview-leak hazard). **The driver-preview cleanup is
handled entirely by restore STEP-1** (current_session==driver at cancel time →
restore unlinks `driver:$linked_id` correctly — confirm FINDING 3's rule:
"any branch that does NOT switch leaves cleanup to restore").

### FINDING 5 — caller contract: cancel takes argv[1] ONLY (no char)  [VERIFIED via livepicker.sh bind block]

`scripts/livepicker.sh` (activate T4.S1, COMPLETE) binds the cancel keys
(from `opt_cancel_keys`, PRD §11 default `Escape`) VERBATIM as:
```bash
for lp_c in $(opt_cancel_keys); do
	tmux bind-key -T livepicker "$lp_c" run-shell "$CURRENT_DIR/input-handler.sh cancel"
done
```
So argv is JUST `cancel` — NO `$2`. Under `set -u` the cancel branch MUST NOT
reference `$2` (it is unset → would crash). Mirror the `confirm`/`backspace`/
`next-session`/`prev-session` branches (T2 FINDING 1 / T3 FINDING 9). The `type`
branch is the only one that reads `$2` as `char`.

### FINDING 6 — `$CURRENT_DIR` is the house variable (the work-item's `$SCRIPT_DIR` is descriptive)  [VERIFIED via input-handler.sh]

`scripts/input-handler.sh` resolves `CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"`
at the top — which is `.../scripts` (the file lives in `scripts/`). Every
sibling-call in the file uses `"$CURRENT_DIR/<sibling>.sh"` (T2's
`"$CURRENT_DIR/preview.sh"`, T3's `"$CURRENT_DIR/restore.sh" keep`). The
work-item CONTRACT §3 writes `"$SCRIPT_DIR/scripts/restore.sh" cancel` — that is
**descriptive** (telling you WHICH script). The ACTUAL house idiom is
`"$CURRENT_DIR/restore.sh" cancel` (CURRENT_DIR already IS the scripts dir).
**Use `"$CURRENT_DIR/restore.sh" cancel`** to match every other sibling call and
avoid introducing a new undefined variable (`$SCRIPT_DIR` does not exist in
input-handler.sh → would crash under `set -u`).

### FINDING 7 — cancel needs NO new locals and NO new helper  [VERIFIED via input-handler.sh local line]

The cancel branch uses exactly ONE local: `cur_filter` (read from
`get_state "$STATE_FILTER" ""`). That variable is ALREADY on `input_main`'s
`local` line — declared by T1.S1/T2.S1 (`local action char new_filter cur_filter
cur_list cur_index L new_idx target`) and grown by the parallel T3.S1
(+`pick_type query`, per the parallel-execution contract — T3 is "Implementing",
lands before T4). cancel reuses `cur_filter`; it needs NEITHER `pick_type` NOR
`query` (no type branching, no create). **cancel does NOT grow the local line
and does NOT add a file-scope helper** (contrast confirm's `_confirm_land_on_session`).
The edit is a single surgical replacement of the `cancel)` seam block — nothing
else in the file changes.

### FINDING 8 — cancel is the LAST seam; filling it completes the T1.S1 skeleton (and module P1.M6)  [VERIFIED via input-handler.sh seam map]

T1.S1 created `input-handler.sh` with SIX seams (`type`/`backspace`/
`next-session`/`prev-session`/`confirm`/`cancel`) + the `*) return 0` default.
T2.S1 filled backspace/nav. T3.S1 fills confirm. **T4.S1 fills cancel — the
LAST seam.** After T4, every action is implemented and the `*) return 0` default
is the only remaining no-op (defensive — never crashes the picker on an unknown
action). This completes P1.M6.T4, and since T3+T4 are the last subtasks of
P1.M6, it completes the input-handler module — the gateway to P1.M7 validation.

### FINDING 9 — MOCKING design (work-item §5): type→cancel→cancel, picker-open-then-gone, history unchanged  [VERIFIED shape]

The work-item §5 scenario: "type a filter, press cancel once (filter clears,
picker open), press cancel again (picker exits, client on original session,
history unchanged)." Mapped to assertions over an isolated socket with an
attached client + a deduping `client-session-changed` recorder (FINDING 4 /
restore_keep_cancel FINDING B — same recorder as confirm_mock.sh):

**Cluster 1 — cancel with a non-empty filter clears the query, picker STAYS open:**
- Seed picker state (activate, or manual: mode=on, list=alpha\nbeta\ngamma,
  filter="be", index=1, key-table=livepicker, status=2, linked-id set via a
  preview of beta). Plant the dedup recorder seeded with the driver session.
- `input-handler.sh cancel`.
- Assert: `@livepicker-filter` == `""`; `@livepicker-index` == `"0"`;
  `@livepicker-mode` == `"on"` (STILL on); `@livepicker-list` still populated;
  `key-table` == `"livepicker"`; `status` == `2` (still grown); client session
  == `driver` (never moved); recorder == 1 line (0 new — no switch happened).
- (The renderer, on the next refresh, shows the FULL list with index 0 highlighted.)

**Cluster 2 — cancel AGAIN (filter now empty) fully cancels, history unchanged:**
- `input-handler.sh cancel` a second time (filter is now `""` → fall through to
  `restore.sh cancel`).
- Assert: `@livepicker-mode` UNSET (clear_all_state STEP-6); `@livepicker-filter`,
  `@livepicker-list`, `@livepicker-index`, `@livepicker-linked-id` all UNSET;
  `key-table` == `"root"` (restored); `status` == the original value (on);
  `status-format[0]` no longer the picker `#(...)`; client session == `driver`
  (the deduped switch back); recorder == 1 line (0 new — restore STEP-3's same-
  session switch deduped); `list-keys -T livepicker` is empty/gone
  (`unbind-key -a -T livepicker` STEP-6b).

The canary is the smart-dedup recorder (NOT a naive counter — FINDING 4). The
mock reuses the `script -qec` attached-client + `activate_fresh` idiom from
`confirm_mock.sh` (throwaway; P1.M7 owns the real harness).

## Sources

- Empirical: isolated-socket script run 2026-07-06 on tmux 3.6b (4 tests:
  set-empty round-trip; cancel same-session switch dedup; refresh-client -S rc;
  clear-filter keeps picker alive).
- `scripts/input-handler.sh` (the host file T1.S1 created + T2.S1 grew; T3.S1
  in-flight; T4.S1 fills the `cancel)` seam — the LAST seam).
- `scripts/restore.sh` (COMPLETE P1.M5, IMMUTABLE) — STEP 1-6 teardown + the
  cancel STEP-3 same-session switch (the pollution-safe path).
- `scripts/state.sh` (get_state/set_state/STATE_FILTER/STATE_INDEX) — the set-empty
  round-trip semantics (FINDING 1).
- `scripts/options.sh` — `opt_cancel_keys()` (PRD §11 default `Escape`).
- `scripts/livepicker.sh` — the cancel key bind block (argv = JUST `cancel`).
- `plan/001_fd5d622d3939/P1M6T2S1/research/backspace_nav_findings.md` FINDING 4
  (backspace = filter+index+refresh ONLY; no preview — the exact precedent the
  clear-filter step mirrors).
- `plan/001_fd5d622d3939/P1M5T2S1/research/restore_keep_cancel_findings.md`
  FINDING A/B/E (cancel same-session switch dedups to 0; the smart recorder;
  get_state for ORIG_SESSION).
- `plan/001_fd5d622d3939/P1M6T3S1/research/confirm_findings.md` FINDING 3
  (any branch that does NOT switch leaves driver-preview cleanup to restore —
  cancel's rule), FINDING 9 (argv[1]-only contract).
- `plan/001_fd5d622d3939/architecture/system_context.md` §3 (Invariant A), §6
  (session-history composition/dedup), §9 (shell style: `set -u` only; tabs).
- `PRD.md` §6 Cancel, §9 (restore steps), §11 (Configuration — cancel-keys
  default Escape + "clear query, else cancel" semantics), §14 (Pollution —
  cancel → zero entries).
