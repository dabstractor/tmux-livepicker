# Codebase State: scripts/ — Baseline for Two New Features

Scope: map the CURRENT state of the 7 files in `scripts/` so a planner/PRP agent
can write precise edits for **two new features**:
1. `opt_tab_style()` + `@livepicker-tab-current-tmpl` / `@livepicker-tab-inactive-tmpl`
   (status-format window-status tab styling).
2. `opt_preview_defer()` + `@livepicker-preview-seq` / `@livepicker-preview-target`
   (deferred/racing preview sync — preview.sh gains an optional 2nd arg `<expected_seq>`).

All paths are relative to `scripts/`. Line numbers are from the working tree as of
this run (commit-independent; verified by grep).

---

## 1. `options.sh` — option accessors

**File role:** sourced library (NO side effects). Defines `get_opt()` + one
`opt_<name>()` accessor per `@livepicker-*` option, each baking in its PRD default.

### `get_opt` helper (line 15)
```bash
# $1: option name (e.g. "@livepicker-type"), $2: default value
get_opt() {
	local value
	value="$(tmux show-option -gqv "$1")"
	[ -n "$value" ] && echo "$value" || echo "$2"
}
```

### EVERY `opt_*` accessor (lines 26-44)
One per line, one-space arg formatting (load-bearing: the comment on line 20-22 says
this is so a "Level 4 default cross-check grep matches each
`get_opt "@livepicker-<suffix>" "<default>"` exactly once").

| line | accessor | signature | option | default |
|------|----------|-----------|--------|---------|
| 26 | `opt_key()` | `{ get_opt "@livepicker-key" ""; }` | `@livepicker-key` | `""` (required; guard in plugin.tmux) |
| 27 | `opt_type()` | `{ get_opt "@livepicker-type" "session"; }` | `@livepicker-type` | `"session"` (enum session\|window) |
| 28 | `opt_create()` | `{ get_opt "@livepicker-create" "on"; }` | `@livepicker-create` | `"on"` (bool) |
| 29 | `opt_zoxide()` | `{ get_opt "@livepicker-zoxide-mode" "off"; }` | `@livepicker-zoxide-mode` | `"off"` (bool) |
| 30 | `opt_next_key()` | `{ get_opt "@livepicker-next-key" "C-M-Tab"; }` | `@livepicker-next-key` | `"C-M-Tab"` |
| 31 | `opt_prev_key()` | `{ get_opt "@livepicker-prev-key" "C-M-BTab"; }` | `@livepicker-prev-key` | `"C-M-BTab"` |
| 32 | `opt_nav_next_keys()` | `{ get_opt "@livepicker-nav-next-keys" "Down"; }` | `@livepicker-nav-next-keys` | `"Down"` (space-list) |
| 33 | `opt_nav_prev_keys()` | `{ get_opt "@livepicker-nav-prev-keys" "Up"; }` | `@livepicker-nav-prev-keys` | `"Up"` (space-list) |
| 34 | `opt_confirm_keys()` | `{ get_opt "@livepicker-confirm-keys" "Enter"; }` | `@livepicker-confirm-keys` | `"Enter"` (space-list) |
| 35 | `opt_cancel_keys()` | `{ get_opt "@livepicker-cancel-keys" "Escape"; }` | `@livepicker-cancel-keys` | `"Escape"` (space-list) |
| 36 | `opt_backspace_keys()` | `{ get_opt "@livepicker-backspace-keys" "BSpace"; }` | `@livepicker-backspace-keys` | `"BSpace"` (space-list) |
| 37 | `opt_preview_mode()` | `{ get_opt "@livepicker-preview-mode" "live"; }` | `@livepicker-preview-mode` | `"live"` (enum live\|snapshot\|off) |
| 38 | `opt_suppress_window_hook()` | `{ get_opt "@livepicker-suppress-window-hook" "on"; }` | `@livepicker-suppress-window-hook` | `"on"` (bool) |
| 39 | `opt_fg()` | `{ get_opt "@livepicker-fg" "default"; }` | `@livepicker-fg` | `"default"` |
| 40 | `opt_bg()` | `{ get_opt "@livepicker-bg" "default"; }` | `@livepicker-bg` | `"default"` |
| 41 | `opt_highlight_fg()` | `{ get_opt "@livepicker-highlight-fg" "black"; }` | `@livepicker-highlight-fg` | `"black"` |
| 42 | `opt_highlight_bg()` | `{ get_opt "@livepicker-highlight-bg" "yellow"; }` | `@livepicker-highlight-bg` | `"yellow"` |
| 43 | `opt_show_count()` | `{ get_opt "@livepicker-show-count" "on"; }` | `@livepicker-show-count` | `"on"` (bool) |
| 44 | `opt_status_format_index()` | `{ get_opt "@livepicker-status-format-index" "0"; }` | `@livepicker-status-format-index` | `"0"` (int 0-9) |

### Patterns / conventions
- Naming: `opt_<suffix>()` where `<suffix>` strips the `@livepicker-` prefix and `-`.
- Each is a single-line `{ get_opt "@livepicker-<name>" "<default>"; }` body.
- Column-aligned whitespace before `{` (note the longer names like
  `opt_suppress_window_hook()` and `opt_status_format_index()` reduce to a single
  space before `{`).
- Trailing `# ...` comment after `}` documents the option's role.
- House `set -u`, NOT `-e` (option reads legitimately return non-zero).
- No wrapping function; accessors are top-level (sourced into caller's namespace).

### INSERTION POINTS for the two new accessors
- **`opt_tab_style()`** and **`opt_preview_defer()`** go after line 44
  (`opt_status_format_index`), as new single-line accessors matching the pattern.
  Example shapes the planner should mirror:
  ```bash
  opt_tab_style()        { get_opt "@livepicker-tab-style" "tabs"; }       # enum: tabs|off
  opt_preview_defer()    { get_opt "@livepicker-preview-defer" "off"; }    # bool on/off
  ```
  (Defaults per PRD; the planner must confirm exact PRD §11 defaults.)
- Reminder: the Level-4 cross-check grep expects exactly one `get_opt "@livepicker-<x>" "<d>"`
  per option, so each new accessor MUST follow the single-line format.

---

## 2. `state.sh` — runtime-state keys + saved-state contract

**File role:** sourced library (NO side effects beyond defining readonly consts).
Three responsibilities: set/get accessors, named readonly contract keys,
status-format trap helpers + `clear_all_state` teardown.

### EVERY `STATE_*` key (runtime — lines 31-36)
```bash
readonly STATE_MODE="@livepicker-mode"
readonly STATE_LIST="@livepicker-list"
readonly STATE_FILTER="@livepicker-filter"
readonly STATE_INDEX="@livepicker-index"
readonly STATE_LINKED_ID="@livepicker-linked-id"
readonly STATE_TYPE="@livepicker-type"   # session|window — ALIAS of PRD §11 config (read-only; NEVER cleared)
```

### `ORIG_*` saved-state contract keys (lines 38-46)
```bash
readonly ORIG_SESSION="@livepicker-orig-session"
readonly ORIG_WINDOW="@livepicker-orig-window"                         # window ID, NOT index
readonly ORIG_LAYOUT="@livepicker-orig-layout"
readonly ORIG_KEY_TABLE="@livepicker-orig-key-table"
readonly ORIG_STATUS="@livepicker-orig-status"
readonly ORIG_RENUMBER="@livepicker-orig-renumber-windows"
readonly ORIG_HOOK="@livepicker-orig-session-window-changed"
readonly ORIG_STATUS_FORMAT_INDICES="@livepicker-orig-status-format-indices"
readonly ORIG_STATUS_FORMAT_PREFIX="@livepicker-orig-status-format-"   # +N suffix
```

### The runtime-keys clear-list (line 49) — LOAD-BEARING for teardown
```bash
# keys clear_all_state unsets explicitly (STATE_TYPE deliberately absent: it is config)
readonly _STATE_RUNTIME_KEYS="$STATE_MODE $STATE_LIST $STATE_FILTER $STATE_INDEX $STATE_LINKED_ID"
```
**CRITICAL:** `clear_all_state` iterates THIS space-list (line 156) to clear runtime
keys. Any NEW runtime `STATE_*` key that should be cleared on teardown MUST be added
here too, OR it will leak across picker sessions.

### set/get helpers (lines 63-75)
```bash
# $1: STATE_* key, $2: value. Writes a runtime @livepicker-* option.
set_state() {
	tmux_set_opt "$1" "$2"
}
# $1: STATE_* key, $2: optional default (returned when unset/empty). ${2:-} = optional + set-u safe.
get_state() {
	tmux_get_opt "$1" "${2:-}"
}
```
- `tmux_set_opt` (utils.sh) = `tmux set-option -g "$1" "$2"`.
- `tmux_get_opt` (utils.sh) = show-option -gqv, falling back to `${2:-}`.
- There is NO explicit `unset_state()`; callers use `tmux_unset_opt "$STATE_X"`
  (=`set-option -gu`) directly — see preview.sh line 110 for the precedent.
- New keys get added as `readonly STATE_X="@livepicker-x"`, then read/written via
  `set_state "$STATE_X" "$val"` / `get_state "$STATE_X" "${2:-}"`.

### `clear_all_state` — EXACT body (lines 139-164)
```bash
clear_all_state() {
	local k
	# shellcheck disable=SC2086
	for k in $_STATE_RUNTIME_KEYS; do
		tmux set-option -gu "$k" 2>/dev/null || true
	done
	while IFS= read -r line; do
		k="${line%% *}"
		[ -n "$k" ] && tmux set-option -gu "$k" 2>/dev/null || true
	done <<EOF
$(tmux show-options -g 2>/dev/null | grep '@livepicker-orig-')
EOF
}
```
Mechanics:
1. Iterates `_STATE_RUNTIME_KEYS` (the 5-line-49 space-list) → `-gu` each.
2. Greps live global options for `@livepicker-orig-` → `-gu` each saved-state key.
3. PRESERVES PRD §11 config (CORRECTION A): never greps bare `@livepicker-`.

### INSERTION POINTS for the two new features' state keys
The 4 new keys are RUNTIME (written/read during a picker session, cleared on exit):
- `@livepicker-tab-current-tmpl`
- `@livepicker-tab-inactive-tmpl`
- `@livepicker-preview-seq`
- `@livepicker-preview-target`

**Add as new `readonly STATE_*` lines** between lines 36 and 38 (after the existing
runtime block, before the `ORIG_*` block). e.g.:
```bash
readonly STATE_TAB_CURRENT_TMPL="@livepicker-tab-current-tmpl"
readonly STATE_TAB_INACTIVE_TMPL="@livepicker-tab-inactive-tmpl"
readonly STATE_PREVIEW_SEQ="@livepicker-preview-seq"
readonly STATE_PREVIEW_TARGET="@livepicker-preview-target"
```
**Then append each new key to `_STATE_RUNTIME_KEYS` (line 49)** so `clear_all_state`
clears them — otherwise they leak across sessions. (Pattern: the existing 5 keys are
space-joined in one double-quoted string.)

> Open question for the planner: are `tab-current-tmpl` / `tab-inactive-tmpl`
> genuinely runtime (recomputed each redraw) or just config mirrors of
> `@livepicker-tab-style`? If they are config defaults, they belong in `options.sh`
> not `state.sh`. The task framing ("will be added" to state.sh) treats them as
> runtime state, but the naming (`-tmpl` = template) suggests config. Flag for PRD.

---

## 3. `livepicker.sh` — activate orchestrator

**File role:** top-level executable (`run-shell` target from plugin.tmux). Sources
options/utils/state. Defines `activate_main()` and the driver `activate_main "$@"`.

### activate() / main flow — the numbered steps (function at line 43)
Order is load-bearing. Exact regions:

| region | lines | step |
|--------|-------|------|
| `activate_main() {` | 43 | function entry |
| **STEP 1** double-activation guard | 44-52 | if `@livepicker-mode == on` return 0 (MUST be first) |
| **STEP 2** save originals into `@livepicker-orig-*` | 53-82 | 3× `lp_client_format` (session/window/layout) + 3× `tmux_save_opt` (key-table/status/renumber) + `ORIG_HOOK` capture + `state_status_format_save` + `set_state "$STATE_LINKED_ID" ""` (line 82) |
| **T2** build list + initial index | 84-117 | session/window list, resolve current, store LIST/FILTER/INDEX |
| **T3** grow status bar + install renderer | 126-167 | (a) shift user-set status-format indices; (b) install `#($CURRENT_DIR/renderer.sh)` at `status-format[$lp_idx]`; (c) grow `status` count (normalized case) |
| **T4.S1** build livepicker key table + switch | 175-272 | copy prefix+root (filtered, harmful dropped), bind explicit keys, `set-option -g key-table livepicker` (line 271) |
| **T4.S2** suppress session-window-changed hook | 273-291 | if `opt_suppress_window_hook == on` → `tmux_clear_hook session-window-changed` (line 290) |
| **T5** first preview + mode-on + refresh | 292-330 | see below |
| driver | 332 | `activate_main "$@" || exit 1; exit 0` |

### How the first preview is invoked (T5, lines 292-330)
```bash
local orig_session
orig_session="$(get_state "$ORIG_SESSION" "")"
# L2 FIX: if the first preview fails, roll back via restore cancel.
if ! "$CURRENT_DIR/preview.sh" "$orig_session"; then
	"$CURRENT_DIR/restore.sh" cancel 2>/dev/null || true
	return 1
fi
set_state "$STATE_MODE" "on"
tmux refresh-client -S
return 0
```
- First preview is the SELF-SESSION path (preview.sh sees `S == current_session` →
  select orig WITHOUT linking). Called at **line 323**.
- `set_state "$STATE_MODE" "on"` arms the STEP-1 guard at **line 327** (mode-on LAST).
- `tmux refresh-client -S` forces the #() renderer to draw at **line 328**.

### EXACT insertion point for sentinel-window format resolution (PRD §17)
The task specifies: "after key-table/first-preview setup." Both are complete at:
- key-table switch: line 271; hook suppress ends: line 291 (end of T4.S2).
- first preview invocation: lines 323-326 (the `if ! preview.sh ...; fi` block).
- mode-on: line 327.

**Recommended insertion: between line 326 (end of the first-preview `if` block) and
line 327 (`set_state "$STATE_MODE" "on"`).** Rationale:
- The sentinel-window status-format entry must be installed while the picker is
  visibly active but BEFORE the mode-on guard is armed (so a sentinel-install
  failure can still roll back — mirror the L2-fix pattern).
- It runs after the first preview so the sentinel reflects the real preview state.
- `status-format[$lp_idx]` (the renderer line) was installed at T3 (line 161); the
  sentinel-window format is a SEPARATE status-format index or a window-status-format
  override — the planner must decide per PRD §17. The block at 292-330 is the seam.

Alternative insertion considered: between T4.S2 (line 291) and T5 (line 292), i.e.
before the first preview. This is valid ONLY if the sentinel does not depend on the
preview's linked id; if it does, it must come after line 326. Flag for PRD §17.

---

## 4. `renderer.sh` — `#()` status-line renderer

**File role:** top-level executable invoked as `status-format[$lp_idx]`. Re-runs on
every status redraw + every `refresh-client -S`. PURE (read → print ONE line → exit;
ZERO tmux mutations). FAST (<50ms; ~9 option reads).

### `render()` — FULL body (lines 47-131)
```bash
render() {
	local TYPE FG BG HFG HBG SHOW_COUNT_RAW SHOW_COUNT
	local LIST FILTER IDX
	local -a all=() filtered=()
	local TOTAL FLEN
	local out seg i cidx first esc_filter esc_name

	TYPE="$(opt_type)"
	FG="$(opt_fg)"
	BG="$(opt_bg)"
	HFG="$(opt_highlight_fg)"
	HBG="$(opt_highlight_bg)"
	SHOW_COUNT_RAW="$(opt_show_count)"
	case "${SHOW_COUNT_RAW,,}" in
		'' | off | 0 | no | false | disable) SHOW_COUNT=0 ;;
		*) SHOW_COUNT=1 ;;
	esac

	LIST="$(get_state "$STATE_LIST" "")"
	FILTER="$(get_state "$STATE_FILTER" "")"
	esc_filter="${FILTER//\#/##}"   # display escape: every # -> ## (tmux literal-#; Issue 3)
	IDX="$(get_state "$STATE_INDEX" "0")"

	mapfile -t all < <(printf '%s' "$LIST")
	TOTAL="${#all[@]}"

	mapfile -t filtered < <(lp_build_filtered "$LIST" "$FILTER")
	FLEN="${#filtered[@]}"

	out=""
	if [ "$FLEN" -eq 0 ]; then
		if [ "$SHOW_COUNT" -eq 1 ]; then
			out="#[fg=$FG,bg=$BG]query> $esc_filter (no match) 0/$TOTAL#[default]"
		else
			out="#[fg=$FG,bg=$BG]query> $esc_filter (no match)#[default]"
		fi
		printf '%s' "$out"
		return 0
	fi

	cidx="$IDX"
	[[ "$cidx" =~ ^[0-9]+$ ]] || cidx=0
	[ "$cidx" -ge "$FLEN" ] && cidx=$((FLEN - 1))
	[ "$cidx" -lt 0 ] && cidx=0

	first=1
	for i in "${!filtered[@]}"; do
		esc_name="${filtered[$i]//\#/##}"   # display escape: every # -> ## (tmux literal-#; Issue 3)
		if [ "$i" -eq "$cidx" ]; then
			seg="#[fg=$HFG,bg=$HBG]${esc_name}#[default]"
		else
			seg="#[fg=$FG,bg=$BG]${esc_name}#[default]"
		fi
		if [ "$first" -eq 1 ]; then
			out="$seg"
			first=0
		else
			out="$out $seg"
		fi
	done

	if [ "$SHOW_COUNT" -eq 1 ]; then
		out="$out #[fg=$FG,bg=$BG]query> $esc_filter [$((cidx + 1))/$FLEN]#[default]"
	fi

	printf '%s' "$out"
}
render || printf '%s' '#[fg=red]livepicker: renderer error#[default]'
exit 0
```

### How it reads state + builds the highlighted list + `#` escaping
- **State reads:** `STATE_LIST` (the full newline-joined candidate list),
  `STATE_FILTER` (raw query), `STATE_INDEX` (0-based highlight).
- **Filtering:** delegates to `lp_build_filtered "$LIST" "$FILTER"` (filter.sh) →
  `mapfile -t filtered` → `FLEN`. Case-insensitive substring, original order+case.
- **Highlight:** `filtered[$cidx]` gets `#[fg=$HFG,bg=$HBG]...#[default]`; all others
  get `#[fg=$FG,bg=$BG]...#[default]`. `#[default]` after EVERY segment resets both
  fg AND bg (FINDING 1).
- **Index clamp:** non-numeric → 0; `>=FLEN` → `FLEN-1`; `<0` → 0 (lines ~108-110).
- **`#` escaping:** `${FILTER//\#/##}` and `${name//\#/##}` — every `#` → `##` so
  tmux treats it as a literal `#` not a style directive (Issue 3).
- **Output contract:** EXACTLY ONE line, NO trailing newline (`printf '%s'`).
  Multi-line stdout renders only the last line.
- **No `set -e`** (unset option → rc=1 would blank line 1). `set -u` inherited.
- **Crash guard:** `render || printf '#[fg=red]livepicker: renderer error#[default]'`
  (line 133) — a renderer crash must NEVER blank the bar.

### Window-status render branch point
- `TYPE` is READ (line 54) but **NOT branched on** (SC2034 suppressed at file top:
  "reserved for a future session/window label; the core render path does not branch
  on it"). The plain path above is the ONLY path today.
- A window-status render path would branch **right after the option reads**
  (after line 60, the SHOW_COUNT case), keyed on `opt_tab_style()` / `opt_type()`.
  The planner should add an early branch before the `out=""` / list-build block.
- Note: the new `@livepicker-tab-current-tmpl` / `@livepicker-tab-inactive-tmpl`
  state keys (state.sh §2) would be read here via `get_state "$STATE_TAB_*"` for
  the window-status path.

---

## 5. `preview.sh` — live preview core (link/unlink/select)

**File role:** top-level executable. argv[1] = candidate session name S. Sources
options/utils/state.

### Top-level command-line arg parsing (line 168)
```bash
preview_main "$@" || exit 1
exit 0
```
There is NO explicit arg parsing in `preview_main`'s signature beyond
`local S="${1:-}"` (line 76). The new optional 2nd arg `<expected_seq>` would be
read as `local expected_seq="${2:-}"` at line 76 alongside `S`.

### `preview_fallback()` — capture-pane snapshot (lines 55-73)
```bash
preview_fallback() {
	local captured target="$1"
	if [ "$(opt_type)" = "window" ] && [ "${1%%:*}" != "$1" ]; then
		local w_sess="${1%%:*}" w_idx="${1#*:}"
		target="$w_sess:$w_idx"
	fi
	# shellcheck disable=SC2034
	captured="$(tmux capture-pane -ep -t "=$target:." 2>/dev/null)" && return 0 || return 1
}
```
- Returns capture's rc (0=captured, non-zero=gone).
- Window mode parses `session:index` → `=$w_sess:$w_idx.` (bare `=$1:.` is malformed
  in window mode: `multi:1` → `multi:1:` error).

### `preview_main()` — the link/unlink/select flow (lines 75-166)
```bash
preview_main() {
	local S="${1:-}"
	local current_session orig_window linked_id src_id w_sess w_idx

	current_session="$(get_state "$ORIG_SESSION" "")"
	orig_window="$(get_state "$ORIG_WINDOW" "")"
	linked_id="$(get_state "$STATE_LINKED_ID" "")"

	# --- @livepicker-preview-mode gate (line 86) ---
	local mode
	mode="$(opt_preview_mode)"   # live | snapshot | off
	if [ "$mode" = "off" ]; then
		return 0
	fi
	if [ "$mode" = "snapshot" ]; then
		preview_fallback "$S"
		return $?
	fi
	# mode == live: fall through.

	# --- SELF-SESSION guard (lines 104-113) ---
	if [ -n "$current_session" ] && [ "$S" = "$current_session" ]; then
		if [ -n "$linked_id" ]; then
			tmux unlink-window -t "$current_session:$linked_id" 2>/dev/null || true
			tmux_unset_opt "$STATE_LINKED_ID"
		fi
		[ -n "$orig_window" ] && tmux select-window -t "$orig_window" 2>/dev/null || true
		return 0
	fi

	# --- Resolve candidate window id (lines 119-129) ---
	if [ "$(opt_type)" = "window" ] && [ "${S%%:*}" != "$S" ]; then
		w_sess="${S%%:*}"; w_idx="${S#*:}"
		src_id="$(tmux list-windows -t "=$w_sess" -F '#{window_id}:#{window_index}' 2>/dev/null | awk -F: -v idx="$w_idx" '$2==idx {print $1; exit}')"
	else
		src_id="$(tmux list-windows -t "=$S" -F '#{window_id}' -f '#{window_active}' 2>/dev/null)"
	fi
	if [ -z "$src_id" ]; then
		preview_fallback "$S"
		return $?
	fi

	# --- DUPLICATE guard: same window already linked (lines 134-138) ---
	if [ -n "$linked_id" ] && [ "$linked_id" = "$src_id" ]; then
		tmux select-window -t "$src_id" 2>/dev/null || true
		return 0
	fi

	# --- Drop previous preview link (lines 143-145) ---
	if [ -n "$linked_id" ]; then
		tmux unlink-window -t "$current_session:$linked_id" 2>/dev/null || true
	fi

	# --- Link + select + track (lines 150-164) ---
	if ! tmux link-window -a -s "$src_id" -t "$current_session:" 2>/dev/null; then
		preview_fallback "$S"
		return $?
	fi
	tmux select-window -t "$src_id" 2>/dev/null || true
	set_state "$STATE_LINKED_ID" "$src_id"
	return 0
}
```

### How LINKED_ID is tracked
- Read at entry: `linked_id="$(get_state "$STATE_LINKED_ID" "")"` (line 83).
- Cleared (via `-gu`) in the self-session path: `tmux_unset_opt "$STATE_LINKED_ID"`
  (line 110).
- Set on a successful link: `set_state "$STATE_LINKED_ID" "$src_id"` (line 164).
- Duplicate guard (line 134): if `linked_id == src_id`, skip unlink+link, just select.

### Self-session edge case (lines 104-113)
When `S == current_session` (= ORIG_SESSION, the driver): unlink any prior preview,
clear LINKED_ID, select ORIG_WINDOW, return 0 WITHOUT linking (avoids in-session
duplicate).

### Capture-pane fallback
- Reached when `@livepicker-preview-mode == snapshot` (always), OR when live link
  fails (lines 128, 151), OR when `src_id` is empty (line 128).

### INSERTION POINT for the optional `<expected_seq>` 2nd arg
- **Read it at line 76:** `local expected_seq="${2:-}"` next to `local S="${1:-}"`.
- The seq-comparison gate (PRD §18 racing-preview guard) belongs at the TOP of
  `preview_main`, right after reading `expected_seq`, BEFORE the preview-mode gate
  (line 86). Pattern: if `expected_seq` is set AND differs from the current
  `@livepicker-preview-seq`, return 0 early (a newer keystroke already superseded
  this preview). The new `STATE_PREVIEW_SEQ` / `STATE_PREVIEW_TARGET` keys (state.sh
  §2) back this.
- Note the call sites that would PASS the seq: every `preview.sh` invocation in
  input-handler.sh (lines 137, 246, 265) — see §6.

---

## 6. `input-handler.sh` — input dispatcher (CORE for §18 rework)

**File role:** top-level executable. argv[1]=action, argv[2]=typed char. Sources
options/utils/state/filter.

### Top-level dispatch (line 434)
```bash
input_main "$@" || exit 1
exit 0
```

### `_lp_sync_preview_to_top_match()` — EXACT (lines 130-138)
```bash
_lp_sync_preview_to_top_match() {
	local _list _filt
	local -a _sync_filtered=()
	_list="$(get_state "$STATE_LIST" "")"
	_filt="$(get_state "$STATE_FILTER" "")"
	mapfile -t _sync_filtered < <(lp_build_filtered "$_list" "$_filt")
	[ "${#_sync_filtered[@]}" -eq 0 ] && return 0
	"$CURRENT_DIR/preview.sh" "${_sync_filtered[0]}" 2>/dev/null || true
}
```
- Mirrors the renderer's filter (same `lp_build_filtered`).
- Empty filtered list → skip preview (no-op).
- Calls `preview.sh` with `filtered[0]` (the top match), guarded `2>/dev/null || true`.

### Where `_lp_sync_preview_to_top_match` is called inline (the §18 rework sites)
- **type branch:** line 172 (after `set_state "$STATE_INDEX" "0"`, line 169).
- **backspace branch:** line 210 (after `set_state "$STATE_INDEX" "0"`, line 207).
- **cancel-clear branch:** line 400 (after `set_state "$STATE_INDEX" "0"`, line 397).
- **NOT called by** next-session (line 246 calls `preview.sh "$target"` directly),
  prev-session (line 265 ditto), or confirm (lands on target via helper).

### The action branches — summary (all inside `input_main()`, line 141)
`case "$action" in ... esac` dispatch:

| branch | lines | behavior |
|--------|-------|----------|
| `type)` | 144-176 | append `$2` to FILTER via `new_filter="$(get_state "$STATE_FILTER" "")$char"`; `set_state FILTER`; `set_state INDEX 0`; `_lp_sync_preview_to_top_match`; `refresh-client -S` |
| `backspace)` | 184-215 | `new_filter="${cur_filter%?}"`; guard empty; `set_state FILTER`; `set_state INDEX 0`; `_lp_sync_preview_to_top_match`; `refresh-client -S` |
| `next-session)` | 216-248 | re-filter → `L`; sanitize idx; `new_idx=$(( (cur_index+1) % L ))`; `set_state INDEX`; `target="${filtered[$new_idx]}"`; `preview.sh "$target"`; `refresh-client -S` |
| `prev-session)` | 249-268 | mirror of next; `new_idx=$(( (cur_index-1+L) % L ))` |
| `confirm)` | 281-379 | resolve target at clamped INDEX; session mode → `_confirm_land_on_session`; window mode → unlink driver + switch-client + select-window + `restore.sh keep-window`; empty + session + create-on → new-session (zoxide-aware) → `_confirm_land_on_session`; else `restore.sh cancel` |
| `cancel)` | 380-432 | two-step: non-empty filter → clear it + INDEX 0 + sync + refresh (KEEP OPEN, return 0); empty filter → `restore.sh cancel` |
| `*)` | 433 | unknown action → defensive no-op |

### §18 rework impact (racing preview / seq guard)
Every `preview.sh` invocation site that a fast-typing user can fire must pass the
current `@livepicker-preview-seq` and bump it before the call:
- `_lp_sync_preview_to_top_match`: line 137 (covers type/backspace/cancel-clear).
- `next-session`: line 246.
- `prev-session`: line 265.
- (confirm's preview is implicit — it lands, no deferred race.)

The planner should centralize the bump+call (e.g. a helper that reads+bumps
`STATE_PREVIEW_SEQ`, writes `STATE_PREVIEW_TARGET`, then calls
`preview.sh "$target" "$seq"`). The `_lp_sync_preview_to_top_match` function
(line 130) is the natural place to fold the seq logic, since type/backspace/cancel
all route through it.

### Helpers also in this file
- `_confirm_land_on_session()` (line 79): shared "switch + teardown" sequence used by
  session-mode confirm and the create path. H2-hardened driver unlink.

---

## 7. `restore.sh` — teardown orchestrator

**File role:** top-level executable. argv[1]=`keep`|`cancel`|`keep-window`. Sources
options/utils/state.

### Top-level driver (line 218)
```bash
restore_main "$@" || exit 1
exit 0
```

### `restore_main()` flow (lines 56-177) — the 6 steps
| step | lines | action |
|------|-------|--------|
| STEP 1 unlink preview | 57-95 | if `STATE_LINKED_ID` non-empty: client-aware `current_session` resolve, fallback to ORIG_SESSION, HARDEN that `current_session == orig_session` before `unlink-window` (NO -k) |
| STEP 2 re-select original window | 96-104 | `select-window -t "$ORIG_WINDOW"` unless mode==`keep-window` |
| STEP 3 keep/cancel client branch | 105-127 | `cancel` → `switch-client -t "=$ORIG_SESSION"`; `keep`/`keep-window` → no switch |
| STEP 4 restore status/format/key-table/renumber/hook | 128-178 | `state_status_format_restore`; replay `status`, `key-table -g`, `renumber-windows`, hook (gated on `opt_suppress_window_hook`) |
| STEP 5 restore layout | 179-189 | `select-layout "$ORIG_LAYOUT"` (best-effort) |
| STEP 6 teardown | 195-216 | (a) `clear_all_state`; (b) `unbind-key -a -T livepicker`; (c) `refresh-client -S` |

### CONFIRM: calls `clear_all_state` from state.sh
**YES — line 214** (STEP 6a):
```bash
clear_all_state
tmux unbind-key -a -T livepicker 2>/dev/null || true
tmux refresh-client -S 2>/dev/null || true
```
- `clear_all_state` is the state.sh function (§2 above). It clears the 5 runtime
  keys (via `_STATE_RUNTIME_KEYS`) + every `@livepicker-orig-*` key.
- **IMPLICATION for the new features:** if the planner adds the new
  `@livepicker-preview-seq` / `@livepicker-preview-target` runtime keys, they will
  be auto-cleared on restore ONLY if added to `_STATE_RUNTIME_KEYS` (state.sh line 49).
  The same applies to `@livepicker-tab-current-tmpl` / `@livepicker-tab-inactive-tmpl`
  if those are runtime. **restore.sh itself needs no edit for these** as long as
  `_STATE_RUNTIME_KEYS` is updated.

---

## Cross-file architecture summary

```
plugin.tmux (binding)
   └─ run-shell livepicker.sh activate
        ├─ sources: options.sh, utils.sh, state.sh
        ├─ STEP1 guard (reads STATE_MODE)
        ├─ STEP2 save originals → ORIG_* keys
        ├─ T2 build list → STATE_LIST/FILTER/INDEX
        ├─ T3 install renderer → status-format[$idx] = #(renderer.sh)
        ├─ T4 build key table → bind keys → input-handler.sh
        ├─ T4.S2 suppress hook
        └─ T5 first preview.sh "$orig_session" → STATE_MODE=on
                          │
   keystroke ─► input-handler.sh <action> [char]
        ├─ sources: options/utils/state/filter
        ├─ type/backspace/cancel-clear → _lp_sync_preview_to_top_match → preview.sh "$top"
        ├─ next/prev → preview.sh "$filtered[idx]"
        └─ confirm → switch-client + restore.sh keep[|-window]
                          │
   restore.sh <keep|cancel|keep-window>
        ├─ STEP1 unlink STATE_LINKED_ID
        ├─ STEP2 select ORIG_WINDOW
        ├─ STEP3 cancel → switch-client ORIG_SESSION
        ├─ STEP4 restore status/format/key-table/hook
        ├─ STEP5 select-layout ORIG_LAYOUT
        └─ STEP6 clear_all_state + unbind-key -a -T livepicker

renderer.sh (status-format #(), pure, every redraw)
        ├─ reads STATE_LIST/FILTER/INDEX + opts
        └─ lp_build_filtered (filter.sh) → highlight filtered[idx]
```

### Shared filter invariant (load-bearing)
`filter.sh::lp_build_filtered LIST FILTER` is the SINGLE filter used by BOTH
renderer.sh (line 76) and input-handler.sh (lines 135, 227, 254, 282). Any new
preview-sync logic MUST route through the same function or filtered[idx] drifts
from the highlighted item.

### Key house helpers (utils.sh) referenced
- `tmux_get_opt`, `tmux_set_opt`, `tmux_unset_opt`, `tmux_save_opt`, `tmux_is_set`
- `tmux_get_hook`, `tmux_clear_hook`
- `lp_filter_harmful_bindings`, `lp_resolve_client`, `lp_client_format`

---

## Open questions for the planner (flag, don't resolve)
1. **tab-current-tmpl / tab-inactive-tmpl: runtime or config?** Naming suggests
   config (templates); task framing says state.sh. If config → they are new
   `opt_*` accessors in options.sh, NOT state keys. (§2 note.)
2. **PRD §17 sentinel-window: separate status-format index or window-status-format
   override?** Determines the exact T5-region insertion shape. (§3.)
3. **preview_defer default + semantics.** PRD §18 must define whether the seq guard
   is always-on or gated by `opt_preview_defer() == on`. (§5/§6.)
4. **`_STATE_RUNTIME_KEYS` update is mandatory** for any new runtime STATE_* key or
   it leaks across sessions (state.sh line 49; restore relies on it via
   clear_all_state). (§2, §7.)

## Start Here
Open **`state.sh`** first — the `_STATE_RUNTIME_KEYS` list (line 49) and the
`STATE_*` readonly block (lines 31-36) are the spine both features touch, and
`clear_all_state` (line 139) is the teardown contract every new key must satisfy.
Then `options.sh` (line 44) for the two new `opt_*` accessors, then
`preview.sh` (line 76) for the `<expected_seq>` arg, then the 5 call sites in
`input-handler.sh` (lines 137/172/210/246/265/400).
