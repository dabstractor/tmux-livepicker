# Research: livepicker.sh T2 seam — list-building + initial index resolution

> All facts below were verified **LIVE on 2026-07-05** on an isolated tmux socket
> (`tmux 3.6b`, `bash 5.3.15(1)-release`, `shellcheck 0.11.0`). The isolated
> socket was driven through a PATH-wrapper shim (`exec /usr/bin/tmux -L "$SOCK"
> "$@"`) so the assertions run with **zero impact on the live server**. These
> are the ground-truth behaviors the T2 step of `scripts/livepicker.sh`
> (P1.M4.T2.S1) must encode. This file is the empirical basis for the PRP.

## Environment

| Tool | Version | Source |
|---|---|---|
| tmux | **3.6b** | `tmux -V` |
| bash | **5.3.15(1)-release** | `bash --version` |
| shellcheck | **0.11.0** | `shellcheck --version` |

The T2 block was also validated **end-to-end**: a temp `livepicker.sh` (= T1's
ready-to-paste body + the T2 block) was sourced against the REAL
`scripts/{options,utils,state}.sh` (symlinked into a temp dir) and run against
the isolated socket with a pty client attached. shellcheck + `bash -n` + tab
checks are clean; 9/9 session-mode, 4/4 window-mode, and 3/3 edge-case
assertions pass. See FINDINGS 8–10.

---

## FINDING 1 — `list-sessions -F '#{session_name}'`: one name per line, tmux default order, NO MRU

PRD §6 step 3 + §2 non-goal ("Recency or MRU ordering. tmux default order only").
Verified on the LIVE server (16 sessions) and the isolated socket:

```
$ tmux list-sessions -F '#{session_name}' | head -5
formality
hack
hypr
job hunt
main
```

- Output is **one session name per line**, in tmux's default (creation/numeric)
  order — NOT MRU. This is exactly what PRD §2 non-goal mandates.
- `od -c` of the raw output shows a trailing `\n` after the LAST name:
  `... g a m m a \n`. **Command substitution `$(…)` strips ALL trailing
  newlines** (bash semantics), so `list="$(tmux list-sessions …)"` yields
  `alpha\nbeta\ngamma` (no trailing `\n`). This is load-bearing for the
  round-trip — see FINDING 3.
- Session names may contain spaces ("job hunt") or hyphens. They are preserved
  as single lines (mapfile splits on `\n` only — renderer FINDING 3).
- `list-sessions` exits 0 even on a server with sessions; on an empty server it
  prints nothing and exits non-zero. Guard with `2>/dev/null` (we do); the empty
  string is handled gracefully (FINDING 8).

---

## FINDING 2 — `list-windows -a -F '#{session_name}:#{window_index}'`: window-mode tokens, one per line

PRD §11 type=window + the work-item contract. Verified on the isolated socket
(3 sessions; `alpha` with 3 windows, `beta`/`gamma` with 1 each):

```
$ tmux list-windows -a -F '#{session_name}:#{window_index}'
alpha:1
alpha:2
alpha:3
beta:1
gamma:1
```

- `-a` lists windows in **ALL sessions** (including the current/driver one).
- Order is deterministic: sessions in `list-sessions` order, windows in index
  order within each session.
- The token is `session_name` + `:` + `window_index`. The renderer treats each
  line as an **opaque string token** (renderer FINDING 11) — it does NOT parse
  the `:`. The confirm path (P1.M5, PRD §6 Confirm) parses `session:window` and
  does `select-window -t "<session>:<window>"`. So the `session:window_index`
  format is exactly what downstream consumes.
- `#{window_index}` is the **raw integer index** (no padding): `1`, `2`, …
- The current-window token resolves to the EXACT same format via
  `tmux display-message -p '#{session_name}:#{window_index}'` (FINDING 6), so
  matching is an exact string `=` comparison — unambiguous.

---

## FINDING 3 — THE CRITICAL GOTCHA: multi-line `@livepicker-list` round-trips cleanly through `set-option` → `show-option` → `mapfile`

This is the highest-consequence finding. The list (newline-separated names) is
stored into `@livepicker-list` via `set-option -g`, then re-read by the renderer
(P1.M2.T1.S1) via `show-option -gqv` + `mapfile -t all < <(printf '%s' "$LIST")`.
The round-trip MUST yield exactly the sessions, with NO phantom empty trailing
element. Verified LIVE:

```
$ MULTI="$(tmux list-sessions -F '#{session_name}')"      # $() strips trailing \n
$ echo "$MULTI"                                            # alpha\nbeta\ngamma (no trailing \n)
$ tmux set-option -g "@livepicker-list" "$MULTI"
$ READBACK="$(tmux show-option -gqv "@livepicker-list")"
$ printf '%s' "$READBACK" | od -c | tail -3
0000000   a   l   p   h   a  \n   b   e   t   a  \n   g   a   m   m   a
0000020                          # <-- ends at 'a' of gamma; NO trailing \n
$ mapfile -t arr < <(printf '%s' "$READBACK")
$ echo "${#arr[@]}"; printf '<%s>' "${arr[@]}"
3
<alpha><beta><gamma>
```

**Conclusions (all load-bearing):**
- `tmux set-option -g "@livepicker-list" "$MULTI"` preserves **embedded
  newlines** (tmux allows newlines in `@`-option values — the same property the
  hook save in P1.M4.T1.S1 relies on).
- `tmux show-option -gqv "@livepicker-list"` returns the value **with internal
  newlines preserved and NO trailing newline** (it does not append one).
- Therefore `mapfile -t arr < <(printf '%s' "$READBACK")` yields exactly the
  sessions — count N for N sessions, **NOT N+1**. No phantom empty element.
- This is ONLY true because `$(…)` stripped the trailing `\n` BEFORE storage. If
  a trailing `\n` were stored, mapfile would STILL give N (a single trailing
  `\n` does not create an empty element — renderer FINDING 3). The danger is a
  **double** trailing newline (`\n\n`) or content after the last `\n`; neither
  occurs here. Storing the raw `$()` output is the safe canonical form.
- **CORROBORATED by renderer FINDING 3** (P1.M2.T1.S1 research): `mapfile -t arr
  < <(printf '%s' "$LIST")` is the correct read form; process substitution (NOT
  a here-string, which would add a phantom empty element for an empty list).

**IMPLICATION:** store the list as `set_state "$STATE_LIST" "$list"` where
`$list` is the raw `$(tmux list-… )` output. Do NOT `printf '%s\n'`, do NOT
append a newline, do NOT join with a different delimiter. The renderer's read
path is already proven against exactly this form.

---

## FINDING 4 — `display-message -p '#{window_index}'`: the raw current window index

Window mode needs the CURRENT window's index to form the initial-selection token.
Verified on the LIVE server and isolated socket:

```
$ tmux display-message -p '#{window_id}'        # @N id (what T1 saves as ORIG_WINDOW)
@40
$ tmux display-message -p '#{window_index}'      # raw integer index
2
$ tmux display-message -p '#{session_name}:#{window_index}'   # exact token
tmux:2
```

- `#{window_index}` is the **raw integer** — the same value `list-windows -a -F
  '#{session_name}:#{window_index}'` emits. So
  `display-message -p '#{session_name}:#{window_index}'` produces a token that
  **exactly matches** one line of the window list. Index resolution is a plain
  string `=` (FINDING 7).
- `display-message -p` targets the **current client**. Under `run-shell` from the
  prefix binding, a client EXISTS (the user pressed the key), so it resolves
  correctly. In the socket-shim MOCK there is no client until you attach one —
  attach a pty client (`script -qec "tmux -L $SOCK attach -t <sess>" /dev/null
  >/dev/null 2>&1 &`) for deterministic capture (same as P1.M3.T1.S2 / T1).
- **NOTE:** `ORIG_WINDOW` (saved by T1) is the `@N` **id**, NOT the index. There
  is no saved window-INDEX. So window mode MUST use `display-message` for the
  index. (A client-independent alternative exists — `list-windows -t "=$ORIG_SESSION"
  -F '#{window_index} #{window_id}'` then match `window_id == ORIG_WINDOW` to
  recover the index — but it is more complex and unnecessary given the always-
  present client at activation. The display-message form is adopted; the
  alternative is noted as a fallback.)

---

## FINDING 5 — session mode reads `ORIG_SESSION` (client-independent); window mode reads `display-message`

- **Session mode:** the "current session" is `ORIG_SESSION` (saved by T1's STEP 2
  via `display-message -p '#{session_name}'`). Reading it back via
  `get_state "$ORIG_SESSION" ""` is (a) already available, (b) client-
  independent (works on a detached test socket), and (c) provably == the live
  client session during activation (T1 just captured it). This mirrors
  `preview.sh` FINDING 9's philosophy (read ORIG_SESSION, NOT display-message, so
  the logic is client-independent). **ADOPTED for session mode.**
- **Window mode:** the current session part could come from `ORIG_SESSION`, but
  the window INDEX has no saved source, so the whole token is taken from a single
  `display-message -p '#{session_name}:#{window_index}'` call (exact-match
  format, FINDING 4). Both session and index resolve against the same client, so
  the token is consistent with the list. A client is present at activation.

---

## FINDING 6 — index resolution: 0-based, plain string `=`, first match wins

The renderer uses a **0-based** index (renderer FINDING 5), displays `idx+1`, and
**clamps** to `[0, FLEN-1]`. T2 must store a 0-based index into the FULL
unfiltered list. Verified bash idiom (shellcheck-clean):

```bash
mapfile -t items < <(printf '%s' "$list")
idx=0
for i in "${!items[@]}"; do
	[ "${items[$i]}" = "$current" ] && { idx="$i"; break; }
done
```

- `${!items[@]}` iterates 0-based indices; `idx` is the first index whose element
  equals `$current`. `break` makes it first-match-wins.
- Session names are unique (tmux enforces it) → unambiguous. Window tokens
  `session:window_index` are unique per (session,index) → unambiguous.
- If `$current` is NOT in the list (race: session vanished between save and
  list-build), `idx` stays 0 (FINDING 9). Safe: the renderer clamps anyway.
- Empty `$list` → `items=()` → loop body never runs → `idx=0` (FINDING 8).

---

## FINDING 7 — empty filter ⇒ full list (renderer FINDING 4 corroboration)

T2 sets `@livepicker-filter=""`. The renderer's filter is a case-insensitive
substring match; an **empty filter matches every item** (`[[ "$x" == *""* ]]` is
always true — renderer FINDING 4). So with `filter=""`, `filtered == all`, and
the index T2 stored (into the FULL list) is a valid index into `filtered` too.
This is the consistency guarantee: **index is valid for the unfiltered list, and
the unfiltered list == the empty-filter list.** No special-casing needed.

---

## FINDING 8 — empty-list edge case: `mapfile` yields a truly empty array

Verified (`renderer FINDING 3` + this research):

```bash
$ EMPTY=""; declare -a earr=(); mapfile -t earr < <(printf '%s' "$EMPTY")
$ echo "${#earr[@]}"
0
```

- An empty `$list` (e.g. `list-sessions` on a server with no sessions) →
  `items=()` (0 elements, NOT `([""])`). The for-loop does not execute; `idx=0`.
- `set_state "$STATE_LIST" ""` stores empty; the renderer reads it back as `""`
  → `all=()` → `TOTAL=0` → "no match" branch (`0/0`). Graceful.
- **DO NOT use a here-string** (`mapfile -t items <<< "$list"`): that appends a
  `\n`, so an empty list yields `items=("")` (1 phantom empty element). Use
  **process substitution** `< <(printf '%s' "$list")`. (renderer FINDING 3.)

---

## FINDING 9 — vanish edge case: current session/window not in list ⇒ idx 0

A session could vanish between T1's save and T2's list-build (a race on a heavily
churning server). Verified by pre-setting `@livepicker-orig-session=GONE` and
running T2 (session mode, no client even needed for the list):

```
ok   vanish: exit 0 (no client needed for session-mode list)
ok   vanish: index defaults to 0
ok   vanish: list still built
```

- `idx` defaults to 0 when no match. The renderer clamps `[0, FLEN-1]` anyway, so
  a stale/0 index is always safe (lands on the first item). This is a benign
  degradation, not an error. **Do NOT `exit 1` on no-match** — the picker should
  still appear (the user can navigate/filter to find what they want).

---

## FINDING 10 — the isolated `-L` socket INHERITS the user's `tmux.conf` (base-index, renumber-windows)

The mock uses `tmux -L "$SOCK"`, which starts a FRESH server that **still reads
the user's tmux.conf**. Verified: on the isolated socket, windows are indexed
from **1**, not 0 — proving `set -g base-index 1` and `renumber-windows on` are
loaded from the user's config:

```
alpha:1  alpha:2  alpha:3   (NOT alpha:0 alpha:1 alpha:2)
```

**Implications:**
- This does NOT break T2: `#{window_index}` and `list-windows -a -F
  '#{session_name}:#{window_index}'` both honor `base-index`, and
  `display-message -p '#{session_name}:#{window_index}'` produces the matching
  token. **Exact-token matching is base-index-agnostic.**
- The mock's expected indices reflect the inherited `base-index` (1-based here).
  Assert against the live `display-message` token, NOT a hardcoded `session:0`.
- `renumber-windows on` (inherited, also the live value per system_context §2)
  means window indices can shift if windows are created/destroyed — but during
  the picker the hook is suppressed (T4) and no windows are created/destroyed by
  T2, so indices are STABLE across T2's single activation pass. (Confirm-time
  index validity is a restore/confirm concern, not T2's.)

---

## FINDING 11 — file shape: surgical insertion at the T2 seam (no rewrite)

`scripts/livepicker.sh` is CREATED by P1.M4.T1.S1 with a clearly-marked seam:

```
# --- T2 (P1.M4.T2.S1): build session list + initial selection (insert here) ---
```

T2 **replaces that single comment line** with the list-build + index-resolution
block, leaving T3/T4/T5 seams and the trailing `return 0`/driver untouched. This
mirrors how P1.M3.T1.S2 extended preview.sh (seam-comment model). The insertion
point is **after** the save block (so `ORIG_SESSION` is already populated) and
**before** T3 (status grow). The block is the FIRST place `local` declarations
appear in `activate_main` (T1 inlines its captures with no locals), so there is
no naming collision.

---

## FINDING 12 — shellcheck / style: clean with the existing file-level disable

The full temp `livepicker.sh` (T1 body + T2 block) passes:
- `bash -n` — exit 0, no output.
- `shellcheck` — **0 findings** (the file-level `# shellcheck disable=SC1091,SC2153`
  from T1 covers source-lines + ORIG_*/STATE_*; the T2 block introduces no new
  warnings — `mapfile`, `${!items[@]}`, `[ … = … ]` are all clean).
- `grep -Pn '^    '` — empty (**tabs only**).

Variable names avoid shadowing bash builtins (`pick_type`, not `type`). Every
variable is assigned before use (safe under `set -u`, inherited from options.sh).
No `set -e`/`set -o pipefail` (house style — a transient `list-sessions` non-zero
must not abort a half-built activate).

---

## Summary of load-bearing decisions (encoded in the PRP)

1. **Session mode list:** `list="$(tmux list-sessions -F '#{session_name}')"` —
   `$()` strips the trailing `\n`; store verbatim. (FINDINGS 1, 3)
2. **Window mode list:** `list="$(tmux list-windows -a -F '#{session_name}:#{window_index}')"` —
   same storage rule. (FINDINGS 2, 3)
3. **Storage:** `set_state "$STATE_LIST" "$list"` — preserves embedded newlines;
   renderer reads back exactly N entries, no phantom element. (FINDING 3)
4. **Filter:** `set_state "$STATE_FILTER" ""` — empty ⇒ full list ⇒ index valid
   for both unfiltered and filtered. (FINDING 7)
5. **Current token:** session mode = `get_state "$ORIG_SESSION" ""` (client-
   independent); window mode = `tmux display-message -p '#{session_name}:#{window_index}'`
   (exact-match format; client present at activation). (FINDINGS 4, 5)
6. **Index:** 0-based, first-match-wins via `mapfile` + `${!items[@]}` +
   `[ … = … ]`; default 0 on no-match. (FINDINGS 6, 9)
7. **mapfile via process substitution** (NOT here-string) — empty list ⇒ empty
   array. (FINDINGS 3, 8)
8. **Surgical seam insertion** — replace the T2 comment; leave T3/T4/T5 + driver
   untouched. (FINDING 11)
9. **shellcheck/bash-n/tabs clean**; no `set -e`; vars avoid builtin names.
   (FINDING 12)

---

## Gaps

None material. Every behavior T2 depends on is proven live (FINDINGS 1–10) and
the implementation is verified end-to-end against the REAL sibling libs on an
isolated socket (FINDINGS 8–10 + the 9/9 + 4/4 + 3/3 assertion runs). The INPUT
dependencies (`options.sh::opt_type`, `utils.sh`, `state.sh` with
`STATE_LIST`/`STATE_FILTER`/`STATE_INDEX`/`ORIG_SESSION`/`set_state`/`get_state`)
are all COMPLETE. The downstream consumers (renderer P1.M2 COMPLETE reads the
three keys; T5/M6/restore read them later) are consistent with the contract.
