# Research — Plan-002 P1.M2.T1.S1: `opt_preview_defer()` accessor + `STATE_PREVIEW_SEQ`/`STATE_PREVIEW_TARGET` state keys + seq init (PRD §18)

> This subtask is the **exact analog of the already-COMPLETE P1.M1.T1.S1**
> (tab-style accessor + STATE_TAB_* keys), but for the §18 deferred-preview
> feature. The T1.S1 PRP is the closest template; this research adapts it. All
> facts below are verified against the current working tree (post-T1.S1/T2.S1
> landing: `opt_tab_style()` + `STATE_TAB_*` are present) and the
> already-live-verified `system_context.md` §3 + `external_tmux_behavior.md` Q6.

## Environment

| Tool | Version | Verified via |
|---|---|---|
| tmux | **3.6b** | system_context.md §2 |
| bash | **5.3.x** | (get_opt idiom + `${var//\#/##}` proven in plan-001) |
| shellcheck | installed | (T1.S1 used it; SC2034 file-wide disable present in state.sh) |

---

## FINDING 1 — targets are NOT yet present; T1.S1 already landed (verified by grep)

Grep of `scripts/{options,state,livepicker}.sh` for `opt_preview_defer` /
`STATE_PREVIEW_SEQ` / `STATE_PREVIEW_TARGET` / `@livepicker-preview-*` → **none
present** (correct — this task is "Researching"). Meanwhile the T1.S1 deliverables
ARE present (post-landing):
- `scripts/options.sh` line 45: `opt_tab_style() { get_opt "@livepicker-tab-style" "plain"; }` — **now the LAST accessor** (the insertion point for `opt_preview_defer` is immediately after it).
- `scripts/state.sh` lines 43-44: `STATE_TAB_CURRENT_TMPL` / `STATE_TAB_INACTIVE_TMPL` — in the runtime block, after `STATE_TYPE` (line 42), before the `ORIG_*` block (line 47).
- `scripts/state.sh` line 49: `_STATE_RUNTIME_KEYS` already lists the two STATE_TAB_* keys.

**Implication**: this task APPENDS after the T1.S1 additions (no edit collision;
T1.S1 is Complete, not in-flight). The only currently-in-flight sibling is
**P1.M1.T3.S1 (renderer.sh)** — which touches `renderer.sh` ONLY, so it is
**fully disjoint** from my three files (`options.sh`, `state.sh`, `livepicker.sh`).

---

## FINDING 2 — the DEFAULT is `on` (PRD §11 + system_context §2; authoritative)

Two independent authoritative sources agree:
- **PRD §11 table** (selected_prd_content h2.11): `@livepicker-preview-defer` → Default `on` → "Defer the live preview to the background so it never blocks typing/nav/confirm (section 18); `off` restores the synchronous path."
- **system_context.md §2**: `@livepicker-preview-defer` → Default `on` → bool `on|off`.
- **system_context.md §3 Q3**: "`@livepicker-preview-defer on` (default): the typing/nav paths do NO preview work inline … The seq guard in `preview.sh` makes a late/superseded job a no-op. `off` restores the legacy synchronous path."

**Decision**: `opt_preview_defer()` returns `"on"` when unset. NOT `"off"`, NOT `"plain"` (that's the tab-style default). The accessor line:
```bash
opt_preview_defer()        { get_opt "@livepicker-preview-defer" "on"; }    # bool on|off (PRD §18; on=defer preview to bg run-shell -b supersedeable job, off=legacy synchronous)
```

**Cross-check guard** (like T1.S1's L4 grep): `grep -c 'get_opt "@livepicker-preview-defer" "on"' scripts/options.sh` must be **1**; `"off"` must be **0**.

---

## FINDING 3 — STATE_PREVIEW_SEQ is the monotonic supersede counter (Q6, load-bearing)

`external_tmux_behavior.md` **Q6** ("Recommended supersedeable background-job pattern"
[HIGH]) is the ground-truth for why SEQ exists and how it is consumed:

- `run-shell -b` is detached/non-blocking AND **not cancellable by id** (Q5). A burst of
  typing spawns N `-b` jobs; you CANNOT kill the late ones. The ONLY way to neutralize a
  late job is to make it a **no-op** via a generation counter.
- Pattern: `@livepicker-preview-seq` (integer, init **0**). On every input that changes
  the preview target, the fire helper (P1.M2.T3) **increments** it and passes the new
  value to `run-shell -b "$CURRENT_DIR/preview.sh '<target>' '<seq>'"`. The background
  `preview.sh` (P1.M2.T2) re-reads the live seq immediately before mutating; if
  `my_seq != cur_seq`, a newer target won → `return 0` (no-op). Optional second re-check
  before the final `select-window` closes the read→mutate race.
- Critical safety (Q6 gotcha + §16 "Deferred-preview concurrency"): if the picker
  **exits** (cancel/confirm) while a `-b` job is mid-flight, `restore.sh`'s
  `clear_all_state` clears the seq (once STATE_PREVIEW_SEQ is in
  `_STATE_RUNTIME_KEYS`); the late job's captured seq then no longer matches the
  (now-empty/0) live seq → it no-ops → it CANNOT clobber the user's just-restored window.

**Implication for THIS task**:
1. Declare `STATE_PREVIEW_SEQ="@livepicker-preview-seq"` as a runtime constant.
2. **Append it to `_STATE_RUNTIME_KEYS`** (MANDATORY — system_context §3 Q4: a runtime
   key NOT listed LEAKS across sessions AND a late `-b` job could match a stale seq
   post-teardown).
3. **Initialize it to `"0"` at activation** (livepicker.sh) — the contract's explicit
   requirement and the known starting point for the monotonic counter. (Even though
   `clear_all_state` clears it on restore, the init is defense-in-depth + the
   authoritative reset for the fresh activation.)

---

## FINDING 4 — STATE_PREVIEW_TARGET: the latest session/window token (contract; observability + optional re-check)

The contract (§3) asks for a second key: `STATE_PREVIEW_TARGET` ("a session/window
token"). Q6's reference `_lp_fire_preview` passes the target as an **argument** to
`preview.sh`, but the contract additionally wants it in STATE so:

- The background `preview.sh` (P1.M2.T2) can re-read the **authoritative latest** target
  from state (rather than the possibly-staled argv) if a debounce is added — closing a
  target-race the argv-only path has.
- Observability/debugging: `show-option -gqv @livepicker-preview-target` shows what is
  pending without parsing argv.
- It is cleared on exit via `_STATE_RUNTIME_KEYS` (no leak; no stale target token
  survives teardown).

**Decision**: declare `STATE_PREVIEW_TARGET="@livepicker-preview-target"`. It is written
by the fire helper (P1.M2.T3) and read/rechecked by `preview.sh` (P1.M2.T2) — those
siblings own the read/write semantics; THIS task only declares the key + adds it to
`_STATE_RUNTIME_KEYS`. **No activation init for TARGET** — the contract initializes only
SEQ to 0 (TARGET can start unset/empty; preview.sh defaults it). Initializing TARGET to
"" at activation would be harmless but the contract does not ask for it, so omit (avoid
scope creep; the empty/get_state-default behavior is the documented contract).

---

## FINDING 5 — the EXACT three edits (verified against the current working tree)

### Edit A — `scripts/options.sh`: append `opt_preview_defer()` after `opt_tab_style()` (line 45)

Current last accessor (line 45):
```bash
opt_tab_style()            { get_opt "@livepicker-tab-style" "plain"; }       # enum: plain|window-status (PRD §17; plain=standalone fg/bg, window-status=reuse theme window-status-format)
```
Append immediately after it:
```bash
opt_preview_defer()        { get_opt "@livepicker-preview-defer" "on"; }      # bool on|off (PRD §18; on=defer preview to bg run-shell -b supersedeable job, off=legacy synchronous)
```
(Pad `{` near column 28 to match the block; the load-bearing part is the single-line
shape + the exact `get_opt "@livepicker-preview-defer" "on"` substring for the L4 grep.)

### Edit B — `scripts/state.sh`: add two runtime constants (after STATE_TAB_INACTIVE_TMPL, before the ORIG block) + extend `_STATE_RUNTIME_KEYS`

**B1** — insert two readonly consts after `STATE_TAB_INACTIVE_TMPL` (line 44) and before
the blank line + `# --- saved-state CONTRACT keys` header (line 46):
```bash
readonly STATE_PREVIEW_SEQ="@livepicker-preview-seq"     # monotonic supersede counter (PRD §18; Q6): bumped by the fire helper (P1.M2.T3), re-checked by preview.sh (P1.M2.T2) before mutating; init 0 at activate; cleared via _STATE_RUNTIME_KEYS
readonly STATE_PREVIEW_TARGET="@livepicker-preview-target"  # latest session/window token (PRD §18): written by the fire helper, read/rechecked by preview.sh; cleared via _STATE_RUNTIME_KEYS
```

**B2** — append both to `_STATE_RUNTIME_KEYS` (currently line 49):
```bash
# current:
readonly _STATE_RUNTIME_KEYS="$STATE_MODE $STATE_LIST $STATE_FILTER $STATE_INDEX $STATE_LINKED_ID $STATE_TAB_CURRENT_TMPL $STATE_TAB_INACTIVE_TMPL"
# new:
readonly _STATE_RUNTIME_KEYS="$STATE_MODE $STATE_LIST $STATE_FILTER $STATE_INDEX $STATE_LINKED_ID $STATE_TAB_CURRENT_TMPL $STATE_TAB_INACTIVE_TMPL $STATE_PREVIEW_SEQ $STATE_PREVIEW_TARGET"
```
(ORDER matters for the `$STATE_PREVIEW_SEQ` expansion in the readonly line: the consts
are declared at lines ~45-46, ABOVE the `_STATE_RUNTIME_KEYS` line ~49 → the expansion
resolves correctly. Same layout as STATE_TAB_* which already works.)

### Edit C — `scripts/livepicker.sh`: init the seq to 0 at activation

**LOCATE** (by content, NOT line number — the contract's "~line 82" is stale): the
picker-internal state-init block in `activate_main`. The exact anchor (verified live):
```bash
	# Init the linked-preview id (no preview linked yet). preview.sh reads this
	# via get_state "$STATE_LINKED_ID" "" — empty means no prior link to unlink.
	set_state "$STATE_LINKED_ID" ""
```
(currently at **line 157**; immediately followed by a blank line + the `# --- T2
(P1.M4.T2.S1): build session/window list ...` comment block at line 160.)

**ACTION**: insert ONE line immediately after `set_state "$STATE_LINKED_ID" ""`:
```bash
	# Init the deferred-preview supersede counter (PRD §18 / external_tmux_behavior.md Q6).
	# Monotonic from 0; bumped by the fire helper (P1.M2.T3) and re-checked by preview.sh
	# (P1.M2.T2) so a late/superseded -b job is a no-op. clear_all_state clears it on exit
	# (via _STATE_RUNTIME_KEYS); this init is the authoritative reset for the fresh session.
	set_state "$STATE_PREVIEW_SEQ" "0"
```
(Indent with ONE TAB to match the surrounding `set_state` lines inside `activate_main`.)

---

## FINDING 6 — runtime-vs-config + runtime-vs-ORIG classification (system_context §3 Q1/Q4)

- **`opt_preview_defer` is CONFIG** (PRD §11 user-tunable toggle). It belongs in
  `options.sh` as an `opt_*` accessor. It is NEVER cleared by `clear_all_state`
  (CORRECTION A: clear_all_state preserves §11 config; only `@livepicker-type` is the
  shared config+runtime mirror, and it is read-only). ✓
- **`STATE_PREVIEW_SEQ` / `STATE_PREVIEW_TARGET` are RUNTIME** (picker-internal,
  written during the picker lifetime, cleared on exit). They go in the runtime
  `STATE_*` block (after STATE_TAB_*, alongside STATE_LINKED_ID), NOT in the
  `ORIG_*` saved-state block (those are originals-to-restore per PRD §9). ✓
- **`_STATE_RUNTIME_KEYS` membership is MANDATORY** (Q4). Without it, a late `-b`
  preview job post-teardown could match a stale seq and clobber the restored window
  (Q6 gotcha). Both keys MUST be appended. ✓

---

## FINDING 7 — no-side-effects contract holds (sourcing = pure; verified pattern)

All three target files are sourced libraries (`options.sh`, `state.sh`) or have a
function-gated body (`livepicker.sh`'s `activate_main`). The edits ADD: one accessor
function (options.sh), two readonly constants (state.sh), one `set_state` call inside
`activate_main` (livepicker.sh — runs only when activate is invoked, not on source).
- Sourcing `options.sh`/`state.sh` defines symbols only — no tmux calls, no output
  (T1.S1 already proven this; the new additions are the same shape).
- `livepicker.sh`'s new `set_state` runs only inside `activate_main` (gated), so
  sourcing livepicker.sh has no new side effect.
- `set -u` safety: `opt_preview_defer`/`STATE_PREVIEW_*` are all assigned at declaration
  (accessor body / readonly / set_state arg) → no unbound-variable risk.

---

## FINDING 8 — the seq-init placement is correct relative to the deferred-preview flow

`livepicker.sh`'s `activate_main` order (verified by reading lines 150-205):
1. STEP 2 save (ORIG_* + status-format + hook) → line ~150-155.
2. **Picker-internal state init** (`set_state STATE_LINKED_ID ""`) → line 157. ← **EDIT C here**.
3. T2 list-build (`list-sessions` / `list-windows`, `set_state STATE_LIST/FILTER/INDEX`) → lines 160-200.
4. T3 status grow + renderer install.
5. First preview + `set_state STATE_MODE on` → line 404.

The seq-init (EDIT C) at step 2 is **before** the first preview (step 5) — correct,
because the first preview is synchronous at activation (system_context §3 Q3: "The
activation-time first preview may stay synchronous"). The seq counter must be 0 BEFORE
any deferred fire (which happens only on subsequent type/nav input via P1.M2.T3), so
the init at step 2 (right after STATE_LINKED_ID, before the list-build) is the right
spot. Grouping it with STATE_LINKED_ID init keeps the picker-internal state inits
together (clearer than burying it in the T2 list-build region).

---

## Summary of load-bearing decisions (encoded in the PRP)

1. **Default `"on"`** for `opt_preview_defer` (PRD §11 + system_context §2; NOT off/plain).
   (FINDING 2)
2. **Two runtime constants** STATE_PREVIEW_SEQ / STATE_PREVIEW_TARGET in the runtime block
   (after STATE_TAB_*), NOT the ORIG_* block. (FINDINGS 4, 6)
3. **Append BOTH to `_STATE_RUNTIME_KEYS`** — mandatory leak/supersede safety (Q4 + Q6).
   (FINDINGS 3, 6)
4. **Init SEQ to "0" at activation** (livepicker.sh, after STATE_LINKED_ID init). TARGET
   is NOT init'd (contract initializes only SEQ). (FINDINGS 3, 5C, 8)
5. **Edit C anchored by CONTENT** (`set_state "$STATE_LINKED_ID" ""`), NOT line number
   (contract's "~line 82" is stale; actual is line 157). (FINDING 5C)
6. **No conflict with parallel P1.M1.T3.S1** (renderer.sh-only); appends after the
   already-complete T1.S1 (options.sh/state.sh) + T2.S1 (livepicker.sh sentinel).
   (FINDING 1)
7. **No new sourcing/strictness**; `set -u`-safe; no side effects on source. (FINDING 7)

---

## Gaps

None material. Every edit is anchored on verified-current content (FINDING 5); the
defaults are doubly-attested (PRD §11 + system_context §2); the supersede rationale and
the `_STATE_RUNTIME_KEYS`-membership requirement are [HIGH]-confidence in
`external_tmux_behavior.md` Q6 + `system_context.md` §3 Q3/Q4. The downstream consumers
(P1.M2.T2 seq guard in preview.sh; P1.M2.T3 fire helper in input-handler.sh) are NOT this
task's scope — it only declares the seam they consume.
