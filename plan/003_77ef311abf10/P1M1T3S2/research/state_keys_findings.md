# State-keys grounding — P1.M1.T3.S2

> Verified LIVE on 2026-07-07 on an isolated temp copy of the plugin (the real
> `scripts/state.sh` was NOT modified — research only). Same host as plan/002 and
> the `empirical_findings.md` run: tmux **3.6b**, bash **5.3.15**, shellcheck **0.11.0**.
> Confirms the 3 new `state.sh` constants + the mandatory `_STATE_RUNTIME_KEYS`
> update behave exactly as the contract requires (definitions only; no behavior
> change until P1.M3.T1 wires them).

## Environment

| Tool | Version |
|---|---|
| tmux | 3.6b |
| bash | 5.3.15(1)-release |
| shellcheck | 0.11.0 |

## The current `state.sh` structure (the target)

Two `readonly` blocks + one clear-list + `clear_all_state`:

- **Runtime block** (10 keys): `STATE_MODE, STATE_LIST, STATE_FILTER, STATE_INDEX,
  STATE_LINKED_ID, STATE_TYPE, STATE_TAB_CURRENT_TMPL, STATE_TAB_INACTIVE_TMPL,
  STATE_PREVIEW_SEQ, STATE_PREVIEW_TARGET`. (`STATE_TYPE` is deliberately ABSENT from
  the clear-list — it is a config mirror, never cleared.)
- **Saved-state block** (9 keys): `ORIG_SESSION, ORIG_WINDOW, ORIG_LAYOUT,
  ORIG_KEY_TABLE, ORIG_STATUS, ORIG_RENUMBER, ORIG_HOOK, ORIG_STATUS_FORMAT_INDICES,
  ORIG_STATUS_FORMAT_PREFIX`.
- **`_STATE_RUNTIME_KEYS`** (9 entries): the space-list `clear_all_state` iterates.
- **`clear_all_state`**: iterates `$_STATE_RUNTIME_KEYS` (unsets each), then
  `show-options -g | grep '@livepicker-orig-'` (unsets each match). It does NOT grep
  the broad `@livepicker-` (CORRECTION A — would wipe §11 config).

## The edit (verbatim; applied to the temp copy for proof)

Three disjoint, content-anchored edits:

1. **Append 2 runtime constants** at the END of the runtime block (after
   `STATE_PREVIEW_TARGET`): `STATE_SCROLL="@livepicker-scroll"`,
   `STATE_CLIENT_WIDTH="@livepicker-client-width"`.
2. **Append 1 saved-state constant** right after `ORIG_HOOK` (the
   `session-window-changed` hook — §P4 says `client-resized` is its IDENTICAL-shape
   mirror, so co-locate them): `ORIG_CLIENT_RESIZED_HOOK="@livepicker-orig-client-resized"`.
3. **Append the 2 runtime keys** to `_STATE_RUNTIME_KEYS` (MANDATORY — the clear-list).
   (`ORIG_CLIENT_RESIZED_HOOK` is NOT added to the list — ORIG_* keys are cleared by
   the grep, never the list; that is the convention.)

## FINDING 1 — the 3 constants resolve to the exact `@livepicker-*` strings

Sourced the edited `state.sh` (after `utils.sh`) under `set -u`; all three resolve:

| constant | value |
|---|---|
| `STATE_SCROLL` | `@livepicker-scroll` |
| `STATE_CLIENT_WIDTH` | `@livepicker-client-width` |
| `ORIG_CLIENT_RESIZED_HOOK` | `@livepicker-orig-client-resized` |

## FINDING 2 — `_STATE_RUNTIME_KEYS` expands to 11 keys and contains both new keys

`printf '%s\n' $_STATE_RUNTIME_KEYS | wc -l` == **11** (was 9). Both new keys are
present in the expansion: `@livepicker-scroll` and `@livepicker-client-width` (matched
via `case " $_STATE_RUNTIME_KEYS " in`). The word-split iteration `for k in
$_STATE_RUNTIME_KEYS` therefore reaches both new keys.

## FINDING 3 — `clear_all_state` tears down all 3 new keys; CORRECTION A still holds

Set the 3 new keys + an ordinary runtime key (`@livepicker-mode`) + 2 config keys
(`@livepicker-type` [config mirror], `@livepicker-fg` [§11 config]) on the isolated
socket, then called `clear_all_state`:

| option | before | after `clear_all_state` | expected |
|---|---|---|---|
| `@livepicker-scroll` | `3` | *(unset)* | cleared (via list) ✓ |
| `@livepicker-client-width` | `80` | *(unset)* | cleared (via list) ✓ |
| `@livepicker-orig-client-resized` | `client-resized[0] 'echo hi'` | *(unset)* | cleared (via grep) ✓ |
| `@livepicker-mode` | `on` | *(unset)* | cleared (existing runtime key, regression) ✓ |
| `@livepicker-type` | `window` | `window` | **PRESERVED** (config mirror; CORRECTION A) ✓ |
| `@livepicker-fg` | `#ffffff` | `#ffffff` | **PRESERVED** (§11 config; CORRECTION A) ✓ |

→ Both teardown mechanisms work: the 2 new runtime keys via the updated list, and
`ORIG_CLIENT_RESIZED_HOOK` via the `@livepicker-orig-` grep (NO list entry needed).
CORRECTION A is intact — broad-config keys survive.

## FINDING 4 — zero behavior change; the 44-test suite stays green by construction

The 3 constants are **unused** until P1.M3.T1 (client-width capture + hook) and
P1.M3.T2 (scroll-into-view). Sourcing `state.sh` is a no-side-effect library contract
(P1 in `codebase_patterns.md`): it defines functions/constants only, runs no tmux calls
at top level. Adding 3 readonly constants + 2 list entries cannot affect any existing
test path — no current code reads these names, and `clear_all_state` still clears the
original 9 keys plus the 2 new (unset-at-test-time) ones harmlessly. (FINDING 3 confirms
the existing `@livepicker-mode` teardown is unaffected.)

## FINDING 5 — placement (and why)

- **`STATE_SCROLL` + `STATE_CLIENT_WIDTH`**: appended at the END of the runtime readonly
  block (after `STATE_PREVIEW_TARGET`). The block's definition order already mirrors the
  `_STATE_RUNTIME_KEYS` list order; appending to BOTH keeps that parallel convention.
  These are §19/§10 layout keys — the newest additions — so the tail is the natural slot.
- **`ORIG_CLIENT_RESIZED_HOOK`**: placed immediately after `ORIG_HOOK` (the
  `session-window-changed` hook). `codebase_patterns.md §P4` states the `client-resized`
  hook uses the IDENTICAL save/restore shape as `session-window-changed` and "mirrors" it;
  co-locating the two `ORIG_*` hook keys makes that relationship visually obvious. Any
  position in the ORIG_* block is functionally correct (the grep is order-independent),
  but the hook-pair grouping is the most readable.
- **`_STATE_RUNTIME_KEYS`**: the 2 new runtime keys appended at the tail (parallel to the
  readonly-block tail). `ORIG_CLIENT_RESIZED_HOOK` is NOT added (ORIG_* keys are
  grep-cleared, never list-cleared — the file's existing convention).

## FINDING 6 — `shellcheck` adds 0 new findings (SC2034 is file-wide disabled)

The `state.sh` header carries a file-wide `# shellcheck disable=SC2034` because every
`STATE_*`/`ORIG_*` constant is the saved-state CONTRACT consumed by external scripts (it
is intentionally unused within the file). The 3 new constants are the same kind of
externally-consumed seam, so they inherit the existing SC2034 suppression — no new
finding. (The other silenced directives — SC2154/SC2016/SC2086 — are not relevant to a
`readonly` definition.)

## FINDING 7 — no parallel conflict with P1.M1.T3.S1

P1.M1.T3.S1 (running in parallel) edits `scripts/options.sh` + `README.md` (5 layout
option accessors + 5 config-table rows). It does NOT touch `scripts/state.sh`. This task
edits ONLY `scripts/state.sh`. Disjoint files → no merge conflict. `state.sh` and
`options.sh` are sibling sourced libraries with disjoint namespaces (`STATE_*`/`ORIG_*`
vs `opt_*`); neither references the other.
