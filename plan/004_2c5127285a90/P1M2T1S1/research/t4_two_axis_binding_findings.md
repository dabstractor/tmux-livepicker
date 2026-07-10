# Research — Plan-004 P1.M2.T1.S1: resolve axis keys + rework T4 binding blocks in livepicker.sh

> Verified against the current working tree. `lp_discover_axis_keys` IS present in
> utils.sh (P1.M1.T2.S1 effectively landed). The 4 new accessors are in options.sh
> (P1.M1.T1.S1 complete); the 4 OLD accessors are GONE — so livepicker.sh T4 is in the
> expected broken intermediate state (calls dead `opt_next_key`/`opt_prev_key`/
> `opt_nav_next_keys`/`opt_nav_prev_keys`) this task fixes.

## Environment

tmux 3.6b; bash 5.3; shellcheck installed. The isolated test socket sources the user's
tmux.conf, so `list-keys` matches the live bindings (the discovery SETs in
gap_analysis_key_discovery.md are reproducible in-test).

---

## FINDING 1 — the T4 block, its current (broken) state, and the exact rework sites

`scripts/livepicker.sh` T4 ("build livepicker key table + switch key-table") spans lines
~336-446. The rework touches 4 sites (line numbers from the current file):

| Site | Lines | Current (broken) | Rework |
|---|---|---|---|
| (A) axis resolution + locals | 355-358 | "Discovery intentionally OMITTED" comment + `local lp_key lp_keys lp_tf lp_c` | resolve 4 axes (explicit→discover); `local lp_tf lp_c s_next s_prev w_next w_prev` |
| (B) copy block | 388-398 | `lp_key="$(opt_next_key)"` / `lp_keys="$(opt_prev_key)"` (DEAD) + `grep -vF` skip of those keys | remove lp_key/lp_keys + the `grep -vF` skip; keep `lp_filter_harmful_bindings` |
| (C) nav loops | 421-429 | `for lp_c in $(opt_next_key) $(opt_nav_next_keys)` → next-session; prev analogous (DEAD accessors) | window-axis block (step 3: $w_next/$w_prev → next-window/prev-window) THEN session-axis block (step 4: $s_next/$s_prev → next-session/prev-session) |
| (D) stale comments | 355-357, 372, 384-387 | "Discovery OMITTED"; "Skip next/prev keys (FINDING 4)"; "L3 FIX grep -F" | rewrite to the two-axis/discovery reality |

**UNTOUCHED**: the typing binds (405-406), backspace/confirm/cancel binds (410-419), the
rename/delete binds (431-438 — they use `opt_rename_key`/`opt_delete_key` which ARE
present), the `set-option -g key-table livepicker` switch (443), and the hook-suppression
block below. The copy block's `lp_filter_harmful_bindings` + `source-file` mechanism stays.

---

## FINDING 2 — the 4 accessors + the discovery helper are the inputs (both present)

- **options.sh** (P1.M1.T1.S1, COMPLETE): `opt_session_next_keys`/`opt_session_prev_keys`/
  `opt_window_next_keys`/`opt_window_prev_keys` — each `get_opt "@livepicker-*-keys" ""`
  (empty default ⇒ discover). The OLD `opt_next_key`/`opt_prev_key`/`opt_nav_next_keys`/
  `opt_nav_prev_keys` are **GONE** (grep-confirmed: 0 in options.sh) — livepicker.sh's
  references to them are the break this task fixes.
- **utils.sh** (P1.M1.T2.S1, COMPLETE): `lp_discover_axis_keys AXIS DIR` — scans
  `tmux list-keys -T root` + `-T prefix`, classifies (window=substring, session=exact),
  drops mouse/`Mouse*|Wheel*`, drops single-char `[A-Za-z0-9]`, subtracts the control-key
  set, de-dups, appends `Down`/`Up` for the session axis. Prints a space-separated list.
  Verified output for this user: window/next `C-M-Tab M-n C-n C-l`, window/prev
  `C-M-BTab M-p C-p C-h`, session/next `) Down`, session/prev `( Up`.
- **livepicker.sh** sources options.sh + utils.sh + state.sh at the top (contract §2) →
  all of the above are in scope inside `activate_main` / the T4 block.

**Resolution idiom** (contract §3a): explicit overrides discovery; empty falls back:
```bash
s_next="$(opt_session_next_keys)"; [ -z "$s_next" ] && s_next="$(lp_discover_axis_keys session next)"
```
Under `set -u` this is safe (s_next is assigned before the `[ -z ]`). If discovery also
yields "" (no keys found), the later `for lp_c in $s_next` is a no-op (empty word-split) —
harmless.

---

## FINDING 3 — removing the `grep -vF` skip is SAFE (lp_filter_harmful_bindings covers it)

The current copy block (lines 390-398) pipes `list-keys prefix/root` → sed →
`lp_filter_harmful_bindings` → `grep -vF -e ...${lp_key}... -e ...${lp_keys}...` → source-file.
The `grep -vF` skip removed the old next/prev keys from the copy.

`lp_filter_harmful_bindings` (utils.sh, read in full) is a `grep -vE` that drops lines whose
command contains (among many): `switch-client`, `next-window`, `previous-window`, `select-window`,
`swap-window`, `last-window`. The user's nav bindings are:
- root `C-M-Tab` → `swap-window -t +1 \; select-window -t +1` — matches BOTH `swap-window`
  AND `select-window` → **dropped by the filter**.
- root `C-M-BTab` → `swap-window -t -1 \; select-window -t -1` → **dropped**.
- root `)` → `switch-client -n` → **dropped** (switch-client).
- prefix `M-n`/`C-n`/`C-l` → `next-window`/`select-window -n` → **dropped**.

So **every discovered nav key's copied binding is already removed by
lp_filter_harmful_bindings**. The explicit axis binds (steps 3-4) then bind those keys to the
picker actions. Removing the `grep -vF` skip is safe (the contract §3b primary path). Even
if a nav key's copied binding were NOT dropped (a custom non-standard nav command), the
explicit bind runs LAST (tmux keeps last) → explicit wins. The skip was defensive redundancy;
lp_filter_harmful_bindings + last-wins make it unnecessary.

---

## FINDING 4 — the binding ORDER (window then session) is functionally equivalent wherever placed among steps 3-6

PRD §8 h3.19 specifies the order: (1) copy, (2) typing, (3) window axis, (4) session axis,
(5) confirm/cancel/backspace, (6) rename/delete. The CURRENT code has backspace/confirm/cancel
BEFORE the nav loops; the contract says REPLACE the nav loops in place (lines 421-429), i.e.
window/session go AFTER backspace/confirm/cancel (not before, as h3.19 lists).

This is **functionally equivalent** because steps 3-6 bind DISJOINT key sets: discovery
SUBTRACTS the control keys (confirm/cancel/backspace/rename/delete via get_opt) from the nav
key sets (research key_discovery_findings.md FINDING + the helper's exclude set). So no key
appears in both a nav set and a control set → the order between nav and confirm/cancel/backspace
cannot cause a collision. Placing window/session where the old nav loops were (after
backspace/confirm/cancel, before rename/delete) is the minimal-churn choice and is correct.

WINDOW axis before SESSION axis (per the contract §3f) IS preserved (both are nav; their
order relative to each other is the one that's spec'd, though even that is collision-free
since the two axes' keys are disjoint for this user).

---

## FINDING 5 — next-window / prev-window are INERT actions (intentional; arrive in P2.M1.T3)

The window-axis binds use `input-handler.sh next-window` / `prev-window`. Those action
cases DO NOT EXIST in input-handler.sh yet (gap_analysis_two_axis.md §Gap (b): the dispatch
is `type | backspace | next-session | prev-session | confirm | cancel | rename | delete |
refresh-width`; no next-window/prev-window). An unbound action hits input-handler's `*)`
no-op branch (`return 0` → picker stays open). This is **intentional** (contract §3:
"next-window/prev-window actions do NOT exist yet ... INTENTIONAL (inert until P2). The
bindings are correct; the actions arrive in P2.M1.T3"). So pressing C-M-Tab during the
picker (post-rework, pre-P2.M1.T3) is a silent no-op — the binding is correct and lands now;
the action lands later. Do NOT add the actions here (P2.M1.T3's scope).

---

## FINDING 6 — the ONE test that asserts the livepicker-table nav binding (must update)

Grep of `tests/` for the nav bindings:
- **`tests/test_keyrepurpose.sh::test_keyrepurpose_during_picker`** (lines 42-45) — the ONLY
  test asserting the livepicker-table binding for C-M-Tab/C-M-BTab. Currently:
  `assert_contains "$next_bind" "next-session"` / `"prev-session"`. After the rework C-M-Tab
  is a discovered **window/next** key → bound to `next-window`. **Update**: `"next-session"`→
  `"next-window"`, `"prev-session"`→`"prev-window"` (+ the header comments lines 6-7, 21, 28-29, 41).
- **`test_keyrepurpose_reverts_after_exit`** (lines 56-79) — asserts the ROOT C-M-Tab binding
  is byte-identical before/after + still contains `swap-window`. The root table is NEVER
  mutated by activate (the copy re-binds into LIVEPICKER, not root). **UNCHANGED — still passes.**
- **All other tests** (test_pollution, test_restore, test_functional, test_responsiveness,
  test_ranking, test_scroll_width) call `input-handler.sh next-session` **directly by name**
  (not via key binding). `next-session` is still a valid action (it stays in input-handler's
  dispatch; the session-axis bind still routes to it). **UNCHANGED — they don't break.**

So the ONLY test edits are the 2 assertions (+ comments) in `test_keyrepurpose_during_picker`.

---

## FINDING 7 — no conflict with the parallel P1.M1.T2.S1 (utils.sh only)

P1.M1.T2.S1 (Implementing) appends `lp_discover_axis_keys` to `scripts/utils.sh`. It does NOT
touch livepicker.sh or any test. This task edits `scripts/livepicker.sh` (the T4 block) +
`tests/test_keyrepurpose.sh`. **Zero file overlap.** And `lp_discover_axis_keys` is already
present (grep count 1) — so the dependency is effectively landed; this task consumes it.

---

## Summary of load-bearing decisions (encoded in the PRP)

1. **Resolve 4 axes at the top of T4** (explicit `opt_*` overrides; empty →
   `lp_discover_axis_keys`). New locals `s_next s_prev w_next w_prev`. (FINDING 2)
2. **Remove lp_key/lp_keys + the `grep -vF` skip**; keep `lp_filter_harmful_bindings` (it
   drops all nav keys from the copy; explicit binds are authoritative via last-wins). (FINDING 3)
3. **Replace the nav loops** with window-axis (step 3: $w_next/$w_prev → next-window/prev-window)
   THEN session-axis (step 4: $s_next/$s_prev → next-session/prev-session), in place. (FINDINGS 1, 4)
4. **next-window/prev-window are intentionally inert** (no input-handler case yet → `*)` no-op).
   Do NOT add the actions (P2.M1.T3). (FINDING 5)
5. **Update test_keyrepurpose_during_picker**: next-session→next-window, prev-session→prev-window
   (+ header comments). reverts_after_exit UNCHANGED. (FINDING 6)
6. **Rewrite stale comments** (Discovery OMITTED → two-axis resolution; FINDING 4 skip →
   lp_filter_harmful_bindings; L3 FIX grep-F → removed). (FINDING 1D)
7. **Typing/backspace/confirm/cancel/rename/delete binds + key-table switch + hook block UNTOUCHED.** (FINDING 1)

---

## Gaps

None material. Every edit site is located by verified-current content (FINDING 1); the
discovery helper + accessors are present (FINDING 2); removing the grep-skip is proven safe
(FINDING 3); the single test update is identified (FINDING 6). The only forward-looking
dependency is P2.M1.T3 (the next-window/prev-window actions) — intentionally deferred; the
bindings land inert now and activate when P2.M1.T3 adds the cases.
