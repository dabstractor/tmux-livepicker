# Research: livepicker.sh T5 — first preview (self-session) + mode-on + refresh (P1.M4.T5.S1)

> **Methodology:** all findings verified LIVE on an **isolated tmux socket**
> (`tmux -L lp-t5v2-*`) against **tmux 3.6b**, **bash 5.3.15** on 2026-07-05,
> with ONE persistent attached client (via `script -qec "tmux -L $SOCK attach"`)
> so `refresh-client -S` has a target. Every rc below is real output. T5 is a
> SURGICAL EDIT: it replaces the single T5 seam comment in `scripts/livepicker.sh`
> (between T4.S2's hook-suppress block and the trailing `return 0`) with a small
> block. It DEPENDS ON preview.sh (P1.M3.T1.S2, COMPLETE), state.sh (COMPLETE),
> and the just-landed T1–T4 seams in livepicker.sh (guard, save, list, status,
> key-table, hook-suppress). The parallel sibling P1.M4.T4.S2 (hook suppress)
> is treated as a CONTRACT — its block is already present above the T5 seam.

T5 makes exactly ONE edit in place to `scripts/livepicker.sh`: replace the T5
seam comment with (a) a header comment + (b) read ORIG_SESSION, (c) call
preview.sh (self-session), (d) set @livepicker-mode on, (e) refresh-client -S.

---

## FINDING 1 — `refresh-client -S` DOES force the `#()` status renderer to re-evaluate.  [VERIFIED]

The whole point of the trailing refresh is PRD §10: "Every input action must
call `refresh-client -S`... it forces a status redraw that re-runs `#()`
commands, so the picker updates immediately rather than waiting on
`status-interval`." Verified live:

```
status-format[0] = #(printf 'x\n' >> /tmp/render_count)
baseline render runs:        1
tmux refresh-client -S
sleep 0.4
render runs AFTER refresh:   2     # <-- the #() ran again
```

**Implication:** calling `refresh-client -S` as the LAST activate step forces the
just-installed `#($CURRENT_DIR/renderer.sh)` (T3) to draw the picker list on
line 1 immediately, instead of waiting up to `status-interval` (default 15s) for
the first natural redraw. Without it, the user would press the activation key and
see a grown status bar with a BLANK line 1 for up to 15 seconds. This is the
T5 analog of why the input handler (P1.M6) refreshes after every keystroke.

---

## FINDING 2 — ⚠️ CRITICAL: `refresh-client -S` with NO attached client FAILS (rc=1 "no current client"). An attached client is REQUIRED.  [GOTCHA]

```
tmux refresh-client -S      (no client attached)   -> rc=1   stderr="no current client"
tmux refresh-client -S      (one client attached)  -> rc=0
tmux refresh-client -t <client> -S                 -> rc=0
```

**Implication for PRODUCTION:** a non-issue. livepicker.sh is invoked via
`run-shell` from the prefix-key binding (plugin.tmux). The user pressed the key,
so an attached client provably exists, and bare `refresh-client -S` targets that
invoking client (rc=0). This is why PRD §10/§13 and the work-item spec use the
BARE form (no `-t`): under run-shell the client context is implicit.

**Implication for the TEST HARNESS / MOCK:** the socket-shim mock MUST keep an
attached client across the `bash livepicker.sh` call (mirror the T4.S2 mock's
`attach`/`detach` helpers via `script -qec "tmux -L $SOCK attach"`). A purely
detached socket (only `new-session -d`) makes `refresh-client -S` return rc=1 —
which is HARMLESS to the picker (see FINDING 7: refresh rc is non-fatal under
no-set-e; mode is already on), but would make a mock that asserts refresh
rc==0 false-fail. So the mock attaches a client.

**Do NOT use `-t`:** there is no reliable client name under run-shell (client
names are pty paths like `/dev/pts/42`, not stable), and the bare form already
targets the invoking client. The bare form is the PRD/work-item spec and the
sibling idiom (P1.M6 will use bare `refresh-client -S` after every input).

---

## FINDING 3 — `preview.sh` invoked as a SUBPROCESS with the self-session name returns rc=0 and leaves `@livepicker-linked-id` empty.  [VERIFIED]

preview.sh is an executable script (shebang + `preview_main "$@" || exit 1;
exit 0`). It sources its own lib trio. Call it as a child process:

```
# activate's STEP 2 had set: @livepicker-orig-session=mysess, orig-window=@0, linked-id=""
bash scripts/preview.sh "mysess"     -> rc=0
@livepicker-linked-id after:         ""   (empty — no link created; self-session)
```

**Why rc=0 always (self-session path):** preview.sh reads `current_session` from
`@livepicker-orig-session` (the SAME value activate passes as argv[1]), so
`S == current_session` is TRUE → the self-session branch:

```bash
if [ -n "$current_session" ] && [ "$S" = "$current_session" ]; then
    if [ -n "$linked_id" ]; then tmux unlink-window ... || true; tmux_unset_opt STATE_LINKED_ID; fi
    [ -n "$orig_window" ] && tmux select-window -t "$orig_window" 2>/dev/null || true
    return 0            # <-- ALWAYS returns 0
fi
```

Every command in this branch is guarded with `2>/dev/null || true`, and the
branch ends with `return 0`. So for the FIRST preview (which the work item
defines as ALWAYS the self-session — "the initial highlight is the current
session"), preview.sh provably returns 0. The `|| return 1` guard in T5 is
therefore DEFENSIVE (see FINDING 5) — it cannot fire on the self-session path,
but it is what makes the "mode-on is LAST" safety property actually hold under
`set -u` (no `-e`).

---

## FINDING 4 — `$CURRENT_DIR` is the scripts/ dir; preview.sh is at `"$CURRENT_DIR/preview.sh"` (NOT `scripts/preview.sh`).  [IDIOM]

The work-item contract writes `"$SCRIPT_DIR/scripts/preview.sh"`, assuming
`SCRIPT_DIR` = repo root. In the ACTUAL code, livepicker.sh resolves
`CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"` = the `scripts/`
directory itself (livepicker.sh lives at `scripts/livepicker.sh`). So preview.sh
is `"$CURRENT_DIR/preview.sh"` — the SAME idiom T3 uses for the renderer
(`#($CURRENT_DIR/renderer.sh)`) and T4.S1 uses for the input handler
(`run-shell "$CURRENT_DIR/input-handler.sh type $lp_c"`).

**Decision (encoded in the PRP):** invoke `"$CURRENT_DIR/preview.sh" "$orig_session"`.
This matches every sibling call in the same file and avoids a wrong
`scripts/preview.sh` path (which would resolve to `scripts/scripts/preview.sh`
and fail). The work-item's `SCRIPT_DIR` is a notational shorthand; the
implementer uses the file's actual `$CURRENT_DIR`.

---

## FINDING 5 — ⚠️ LOAD-BEARING: under house `set -u` (NO `-e`), the `|| return 1` guard is what makes "mode-on is LAST" actually hold.  [ORDERING]

The work-item contract: "Order matters: mode-on is LAST so a crash mid-activate
leaves mode off (re-activatable) rather than stuck." Two readings:

- (A) mode-on BEFORE preview: if preview crashes, mode is ON (guard armed) → the
  picker is STUCK (a second activation is short-circuited by STEP 1's guard).
  This is the failure mode PRD §16 "Double activation" exists to prevent.
- (B) mode-on AFTER preview: if preview crashes, mode is OFF → re-activatable.

For (B) to actually leave mode OFF on a preview crash, the preview failure must
PREVENT mode-on from running. But house style is `set -u` with NO `set -e`
(system_context §9; options.sh/utils.sh/state.sh all `set -u` only; a transient
non-zero from show-option/show-hooks must not abort a half-saved activate). Under
no `-e`, a BARE:

```bash
"$CURRENT_DIR/preview.sh" "$orig_session"      # if this returns non-zero...
set_state "$STATE_MODE" "on"                    # ...this STILL RUNS  -> mode ON (stuck!)
```

would fall straight through to mode-on, VIOLATING the contract. So the guard is
REQUIRED:

```bash
"$CURRENT_DIR/preview.sh" "$orig_session" || return 1
set_state "$STATE_MODE" "on"                    # only reached if preview rc==0
```

**This is the single most important detail of T5.** Without the `|| return 1`,
"mode-on is LAST so a crash leaves mode off" is vacuously false under no-set-e.
The guard is defensive in PRACTICE (FINDING 3: the self-session path always
returns 0), but it is the mechanism by which the contract's stated safety
property is realized. It mirrors the guard idiom at the TOP of activate_main
(`if [ "$(get_state "$STATE_MODE" "off")" = "on" ]; then return 0; fi`) — a
single `|| return 1` on the one step whose failure must abort.

**On failure (return 1):** activate_main returns 1 → driver `activate_main "$@"
|| exit 1` → livepicker.sh exits 1. run-shell ignores the exit code. State is
half-saved (status grown, key-table switched, bindings installed, hook cleared)
but mode is OFF (re-activatable). True rollback (tear down the half-saved state)
is restore.sh's job (P1.M5, not built yet); the work-item explicitly prefers
"re-activatable rather than stuck" over full rollback. This is the accepted
tradeoff for T5.

---

## FINDING 6 — Arm the guard via `set_state "$STATE_MODE" "on"` (house idiom), NOT raw `tmux set-option -g`.  [STYLE]

The work-item contract writes `tmux set-option -g @livepicker-mode on`. That is
correct in effect, but the house idiom for writing a `STATE_*` runtime key is
`set_state` (state.sh): T2 uses `set_state "$STATE_LIST" "$list"`,
`set_state "$STATE_FILTER" ""`, `set_state "$STATE_INDEX" "$idx"`; STEP 2 uses
`set_state "$STATE_LINKED_ID" ""`. `set_state` delegates to `tmux_set_opt` →
`tmux set-option -g` (identical effect). Using `set_state "$STATE_MODE" "on"`:

- keeps T5 visually consistent with T2/STEP-2 (all runtime writes via set_state);
- references the `STATE_MODE` readonly constant (state.sh), so a rename of the
  underlying `@livepicker-mode` string is a one-line change in state.sh, not a
  grep across livepicker.sh;
- arms the STEP-1 guard exactly: `get_state "$STATE_MODE" "off"` reads "on".

**Decision:** `set_state "$STATE_MODE" "on"`. (Raw `tmux set-option -g
"@livepicker-mode" on` is equivalent and acceptable, but set_state is preferred.)

---

## FINDING 7 — `refresh-client -S`'s rc is NON-FATAL (best-effort draw); no guard needed.  [SAFETY]

`refresh-client -S` is the LAST statement before the trailing `return 0`. Under
no `-e`, its rc (0 on success, 1 if no client — FINDING 2) does NOT abort
activate. If it failed (impossible at activation — a client exists; possible
only in a broken test harness), mode is ALREADY on and the preview is ALREADY
selected; the picker is fully functional — the status bar would simply redraw on
the next natural redraw (status-interval, or the first input-handler keystroke,
which itself calls refresh-client -S). So no `|| true` or `if` guard is needed:
it is a best-effort "draw NOW" trigger, not a correctness gate. This matches
how P1.M6's input handler will call bare `refresh-client -S` after every action
with no rc check.

---

## FINDING 8 — Read `ORIG_SESSION` fresh via `get_state`; do NOT reuse T2's `current` local.  [SCOPING]

T2 declares `local pick_type current list idx i` and sets
`current="$(get_state "$ORIG_SESSION" "")"` — but ONLY in the session-mode
branch; in window mode `current` is the `session:window_index` token (from
`display-message`), NOT a bare session name. T5 needs the SESSION NAME to pass
to preview.sh (so it takes the self-session path). Reusing `current` would pass
a `session:window_index` string in window mode, and preview.sh's self-session
check (`S == current_session`, where current_session is the bare name) would be
FALSE → preview.sh would try to link a non-existent session → fallback path.

**Decision:** declare a T5-local `orig_session` and read it fresh:
`orig_session="$(get_state "$ORIG_SESSION" "")"`. This is always the bare
session name (saved by STEP 2 via `display-message -p '#{session_name}'`),
client-independent (FINDING 9 in P1.M3.T1.S1 research: display-message is
non-deterministic under run-shell without a client, but ORIG_SESSION was
captured at STEP 2 when the client existed). `orig_session` does not collide
with any existing local (T2: pick_type/current/list/idx/i; T3:
sf_n/sf_val/sf_indices/lp_idx/orig_status; T4.S1: lp_key/lp_keys/lp_tf/lp_c).
Bash `local` is function-scoped (not block-scoped), so a fresh declaration is
safe and clear.

---

## FINDING 9 — The trailing `return 0` (line 255) is the function's SUCCESS return; T5 does NOT add a duplicate.  [FOOTPRINT]

The current end of activate_main is:

```
	# --- T5 (P1.M4.T5.S1): first preview + set @livepicker-mode on (insert here) ---
	return 0
}
```

T5 REPLACES the seam comment line ONLY. The block ends with `tmux refresh-client
-S`; on success, execution falls through to the existing `return 0` (the
function's success return). On preview failure, `|| return 1` returns early. So
T5 adds NO new `return` — minimal footprint, mirroring how T4.S2 replaced its
seam comment without touching the trailing `return 0`. Do NOT remove or duplicate
the existing `return 0`.

---

## Summary of decisions encoded in the PRP

| # | Work-item contract says | Verified reality (3.6b) / house idiom | PRP action |
|---|---|---|---|
| §3 | `"$SCRIPT_DIR/scripts/preview.sh" "$ORIG_SESSION"` | `$CURRENT_DIR` = scripts/ dir; preview.sh is a sibling (FINDING 4) | `"$CURRENT_DIR/preview.sh" "$orig_session"` |
| §3 | `tmux set-option -g @livepicker-mode on` | set_state is the STATE_* write idiom (FINDING 6) | `set_state "$STATE_MODE" "on"` |
| §3 | `tmux refresh-client -S` | verified re-evals #() (FINDING 1); needs a client (FINDING 2); rc non-fatal (FINDING 7) | bare `tmux refresh-client -S`, last, no guard |
| §3 | "Order matters: mode-on is LAST so a crash leaves mode off" | under no-set-e a bare sequence falls through (FINDING 5) | `"$CURRENT_DIR/preview.sh" "$orig_session" \|\| return 1` BEFORE mode-on |
| §3 | "the current session name from @livepicker-orig-session" | T2's `current` is session:window_index in window mode (FINDING 8) | fresh `local orig_session; get_state "$ORIG_SESSION" ""` |

## Sources
- LIVE verification on tmux 3.6b, isolated socket, ONE attached client, 2026-07-05
  (every rc above is real output from `/tmp/lp_t5_verify2.sh`).
- `scripts/livepicker.sh` (host file — T1–T4 seams LANDED; T5 seam at line 254).
- `scripts/preview.sh` (P1.M3.T1.S2, COMPLETE — the self-session path T5 invokes).
- `scripts/state.sh` (`STATE_MODE` / `set_state` / `ORIG_SESSION`; COMPLETE).
- `scripts/options.sh` (COMPLETE; T5 does not read options directly).
- `plan/001_fd5d622d3939/P1M4T4S2/PRP.md` (parallel sibling — its block sits above
  the T5 seam; treated as a CONTRACT).
- `PRD.md` §6 (Activation steps 6-7), §7 (Self-session edge case), §10 (Status-line
  setup / refresh-client -S), §13 (refresh-client -S primitive), §16 (Double activation).
- `plan/001_fd5d622d3939/architecture/system_context.md` §9 (shell style: set -u, no -e).
