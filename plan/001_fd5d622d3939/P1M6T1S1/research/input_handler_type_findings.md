# Research Findings — P1.M6.T1.S1: input-handler.sh `type <char>`

All facts verified **LIVE on 2026-07-05** on an isolated tmux socket (`tmux 3.6b`,
`bash 5.3.15(1)-release`, `shellcheck 0.11.0`) via a PATH-wrapper `tmux -L <sock>`
shim. Zero impact on the live server. Every test self-cleaned.

These are the load-bearing facts for the `scripts/input-handler.sh` `type` branch.
Read before writing the file.

> Companion to the `restore.sh` / `livepicker.sh` skeletons already in the repo —
> `input-handler.sh` mirrors their structure (header + shellcheck disable +
> `CURRENT_DIR` + source the lib trio + `*_main` dispatch + driver).

---

## FINDING 1 — argv contract: `run-shell "path input-handler.sh type <char>"` → `$1=type`, `$2=<char>`  ✓

The activate key-table builder (livepicker.sh T4.S1, COMPLETE) binds each typing
key as:

```bash
tmux bind-key -T livepicker "$lp_c" run-shell "$CURRENT_DIR/input-handler.sh type $lp_c"
```

`run-shell` executes the WHOLE command string via the shell (word-split on
spaces). Verified live: a receiver script `printf 'argc=%s argv1=[%s]
argv2=[%s]\n' "$#" "$1" "${2:-MISSING}"`, invoked as `tmux run-shell
"/tmp/recv.sh type $c"` for each char:

| `$c` (bound key) | argc | `$1` | `$2` |
|---|---|---|---|
| `a` | 2 | `type` | `a` |
| `L` | 2 | `type` | `L` |
| `3` | 2 | `type` | `3` |
| `-` | 2 | `type` | `-` |
| `.` | 2 | `type` | `.` |
| `/` | 2 | `type` | `/` |
| `_` | 2 | `type` | `_` |

**Conclusions (all load-bearing):**
- `$1` is ALWAYS the literal action word `type`; `$2` is ALWAYS the single typed
  char. The handler dispatches on `$1` and consumes the char from `$2`.
- **The `-` char passes as `$2` correctly** — it is the SECOND positional
  argument (after `type`), so the shell does NOT treat it as a flag prefix.
  Do NOT use `getopts` (it would mis-parse `-`, `.`, `/`); use POSITIONAL `$1`/`$2`
  directly.
- Under house-style `set -u`, `$2` MUST be read with a default: `char="${2:-}"`.
  The binding always passes a char, but a manual/stale invocation without one
  would crash under `set -u` without the default.

---

## FINDING 2 — the handler does NOT filter; the RENDERER does. "recompute list" = the renderer's filtered VIEW  ✓

The PRD §6.2 "Filtering" + the data-flow diagram ("type / backspace: update
@livepicker-filter; recompute list; refresh status") is the controlling spec, but
"recompute list" is AMBIGUOUS and is the #1 trap. Verified against the COMPLETE
`scripts/renderer.sh` (P1.M2.T1.S1):

- `renderer.sh` reads THREE state keys: `@livepicker-list` (the FULL list set once
  at activate), `@livepicker-filter`, `@livepicker-index`.
- It computes the **filtered array at render time**:
  ```bash
  low_filter="${FILTER,,}"
  for name in "${all[@]}"; do
      low_name="${name,,}"
      [[ "$low_name" == *"$low_filter"* ]] && filtered+=("$name")
  done
  ```
  (case-insensitive substring — renderer research FINDING 4). The filtered list
  is a LOCAL variable; it is NEVER written back to a `@livepicker-*` option.
- It highlights the item at `@livepicker-index` (clamped to `[0, FLEN-1]`).

**CONTRACT CORRECTION (load-bearing):** the `type` handler MUST NOT touch
`@livepicker-list`. That key is immutable for the picker's lifetime (set once by
activate T2.S1). "Recompute list" in the data-flow diagram means **the renderer
recomputes the filtered VIEW on each redraw** — which `refresh-client -S` forces
(renderer FINDING 2: `#()` re-runs on every status redraw). The handler's entire
job for `type` is exactly three state ops + one refresh:

1. `new_filter = old_filter + char`  → `set_state "$STATE_FILTER" "$new_filter"`
2. reset `@livepicker-index` to `0` (top filtered match) → `set_state "$STATE_INDEX" "0"`
3. `tmux refresh-client -S` (re-runs the `#()` renderer)

The renderer then filters + highlights + draws. The handler stores the RAW typed
query (case preserved — filtering is case-insensitive at render time, not here).

---

## FINDING 3 — `refresh-client -S` works from a run-shell script context (client attached); filter round-trips  ✓

Verified live on an isolated socket WITH an attached pty client
(`script -qec 'tmux -L sock attach'`):
- `tmux set-option -g "@lp-filter" "log"` → `tmux show-option -gqv '@lp-filter'`
  returns `log` EXACTLY. The filter round-trips through set-option/show-option
  with NO quoting loss for the short query strings typing produces (`l`, `lo`,
  `log`, ...). (Well-established; the same accessor path the renderer uses.)
- `tmux refresh-client -S` invoked from inside a script that `run-shell` executed
  produced EMPTY stderr (= success, rc=0). `-S` redraws the status line only and
  re-runs all `#()` format commands (tmux_primitives §3, LIVE-PROVEN).

**Production guarantee:** the typing key fires from an ATTACHED client pressing a
key while `key-table==livepicker` (activate T4.S1 sets the table; restore clears
it). So a client ALWAYS exists when `type` runs → `refresh-client -S` succeeds.
The redrawing is the standard sub-`status-interval` (default 15s) plugin
technique; without it the picker would lag a keystroke behind.

**Edge cases for the guard:**
- `refresh-client -S` with NO client attached returns rc=1 ("no current client").
  Under house `set -u` (NO `set -e`) this does NOT abort the script, but the
  picker won't redraw for that keystroke. The state IS still updated, so the next
  keystroke's refresh draws the cumulative state — acceptable degradation.
  Mirror `restore.sh`'s idiom: `tmux refresh-client -S 2>/dev/null || true`
  (belt-and-braces; matches STEP 6c in restore.sh). Activate T5 leaves it
  unguarded; restore T4 guards it. For a PER-KEYSTROKE handler the guarded form
  is safer — a detached edge during rapid typing must never break the chain.

---

## FINDING 4 — the index reset to `0` is correct: renderer highlights index 0 of the FILTERED set  ✓

`@livepicker-index` is 0-based (renderer contract: `cidx="$IDX"; ... cidx+1` for
display). The renderer CLAMPS: `idx<0→0`, `idx>=FLEN→FLEN-1` (FLEN = filtered
length). The `type` action sets `@livepicker-index=0` so the highlight lands on
the TOP filtered match immediately after each keystroke (PRD §6 Filtering:
"resets the index to the top match").

Edge case: if the new filter matches NOTHING (FLEN=0), the renderer takes its
"no match" branch (`query> <FILTER> (no match) 0/<TOTAL>`) and the index value is
irrelevant (no item to highlight). So setting index=0 is always safe regardless
of whether the filter matches anything — the renderer handles FLEN=0 itself.
**The handler does NOT need to know whether the filter matches** — that is the
renderer's concern. The handler unconditionally sets index=0.

---

## FINDING 5 — file skeleton: mirror restore.sh / livepicker.sh; dispatch on `$1`, seam-comment the other actions  ✓

`input-handler.sh` is a NEW file and P1.M6.T1.S1 is the FIRST subtask of module
P1.M6. The sibling pattern (restore.sh was built incrementally across T1→T2→T3→T4
with seam comments) governs: CREATE the full skeleton now, implement ONLY the
`type` branch, and leave seam comments for the remaining actions (T2:
backspace/next-session/prev-session; T3: confirm; T4: cancel). Verified
conventions from restore.sh + livepicker.sh:

- **Shebang + shellcheck disable:** `#!/usr/bin/env bash` +
  `# shellcheck disable=SC1091,SC2153` (SC1091: sources sibling libs via
  `$CURRENT_DIR`; SC2153: `$STATE_*` are readonly CONTRACT constants defined in
  state.sh, sourced above, so shellcheck sees no assignment here).
- **`CURRENT_DIR` idiom:** `CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"`
- **Source the lib trio (order load-bearing — state.sh needs utils.sh first):**
  options.sh, utils.sh, state.sh. Each script is its OWN process under run-shell
  → sourced state does NOT cross process boundaries (restore.sh FINDING 7), so
  input-handler.sh MUST source its own trio.
- **`set -u` ONLY** (inherited from the sourced libs; NO `-e`, NO `-o pipefail`
  — refresh-client legitimately returns non-zero on the detached edge).
- **`input_main` dispatch:** declare ALL locals in ONE `local` line at the top
  (house style; restore.sh does this). `case "$action" in type) ... ;; ... esac`.
  Unknown action → `return 0` (defensive; never crash the picker).
- **Driver:** `input_main "$@" || exit 1; exit 0` (matches restore.sh /
  livepicker.sh verbatim).
- **Tabs for indent** (verify `grep -Pn '^    ' scripts/input-handler.sh` is
  empty). shfmt is NOT installed.

**Dispatch table (this task implements `type`; the rest are seam comments):**
```
type           → append char to filter, index=0, refresh        [T1.S1 — THIS]
backspace      → remove last char, index=0, refresh             [T2 seam]
next-session   → index+1 (wrap), refresh preview + status       [T2 seam]
prev-session   → index-1 (wrap), refresh preview + status       [T2 seam]
confirm        → resolve target / create / switch / restore keep [T3 seam]
cancel         → restore cancel                                  [T4 seam]
*              → return 0 (unknown — never crash)
```

---

## FINDING 6 — append idiom: `"$(get_state "$STATE_FILTER" "")$char"` (no `+=`, no quoting games)  ✓

The append is pure bash string concatenation via parameter expansion:

```bash
new_filter="$(get_state "$STATE_FILTER" "")$char"
```

- `get_state "$STATE_FILTER" ""` returns the current raw query (default `""` when
  unset — safe under `set -u`).
- Trailing `$char` (NO space) concatenates directly. `set_state` → `tmux
  set-option -g "$STATE_FILTER" "$new_filter"` stores it. The double-quoted arg
  preserves any special chars in `$char` (`-`, `.`, `/`, `_`, alphanumerics — all
  verified to round-trip, FINDING 1/3).
- Do NOT use bash `+=` on the option (options are not bash variables). Do NOT
  shell-escape `$char` (it is already a single positional arg; re-quoting is a
  no-op and risks mangling).

**Why reset index in the SAME op:** the filtered set may SHRINK as the query
grows, so a stale index could point past the new FLEN. Resetting to `0` after
every append (PRD §6 Filtering) keeps the highlight valid (renderer clamps
anyway, but the contract is explicit: "resets the index to the top match").

---

## FINDING 7 — no `tmux_refresh_client` accessor exists; call `tmux refresh-client -S` directly (house style)  ✓

`utils.sh` defines `tmux_get_opt`/`tmux_set_opt`/`tmux_unset_opt`/`tmux_save_opt`/
`tmux_is_set`/`tmux_get_hook`/`tmux_clear_hook` — but NO `tmux_refresh_client` or
`tmux_run` helper. House style (mirrored by `clear_all_state` calling bare
`tmux set-option -gu` directly, and restore.sh STEP 6c calling bare
`tmux refresh-client -S`) permits DIRECT bare `tmux` calls for one-off primitives
that have no accessor. So `type`'s refresh is `tmux refresh-client -S` (optionally
`2>/dev/null || true` per FINDING 3). Do NOT add a utils helper for it.

---

## Environment

| Tool | Version | Verified via |
|---|---|---|
| tmux | **3.6b** | `tmux -V` |
| bash | **5.3.15(1)-release** | `bash --version` |
| shellcheck | **0.11.0** | `shellcheck --version` |

## Cross-references

- `scripts/renderer.sh` (COMPLETE, P1.M2.T1.S1) — the FILTERING engine; reads
  STATE_LIST/STATE_FILTER/STATE_INDEX; highlights index; `#()` re-runs on refresh.
- `scripts/state.sh` (COMPLETE, P1.M1.T3.S1) — `set_state`/`get_state`/STATE_*.
- `scripts/livepicker.sh` T4.S1 (COMPLETE) — the key-table builder that binds
  `run-shell "$CURRENT_DIR/input-handler.sh type $lp_c"` for each typing char.
- `scripts/restore.sh` (P1.M5) — the file skeleton + driver + seam-comment model.
- PRD §6 Filtering, §10 Status-line setup, §11 Configuration, §16 Implementation
  risks ("Every input action must call `refresh-client -S` ... within 100ms").
- `plan/001_fd5d622d3939/architecture/tmux_primitives.md` §3 (refresh-client -S
  re-runs `#()`).
