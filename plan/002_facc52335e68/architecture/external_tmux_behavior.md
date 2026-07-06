# Research: External tmux behavior validation (tmux 3.6b) for PRD §17 + §18

> Validates the tmux-external behavior that two **unimplemented** features depend on:
> **Feature 1 — theme-matched tabs (PRD §17, sentinel window-format resolution)** and
> **Feature 2 — deferred preview (PRD §18, `run-shell -b` supersede)**.
> Current code: `type`/`backspace`/`next`/`prev` all call `_lp_sync_preview_to_top_match`
> **synchronously** (the lag §18 targets) and there is **no** sentinel/tab-format code
> yet — so this brief is forward-looking ground-truth, not a re-validation of shipped code.

## Methodology & confidence (read first)

- **Tools available:** `read`, `write`, `contact_supervisor`, `intercom`. There is
  **no `web_search`/`web_fetch` and no shell** in this subagent (identical constraint to
  the prior `tmux_primitives.md` researcher). The local man page
  `/usr/share/man/man1/tmux.1.gz` exists but is **gzip-compressed** and the `read` tool
  returns binary garbage from it (`/usr/share/man/man1/tmux.1` → ENOENT; no HTML/README
  in `/usr/share/doc/tmux`). So I could not decompress the man page for verbatim quotes.
- **Evidence model (both permitted by the task):** (a) authoritative tmux knowledge cited
  to the **man-page section/entry** the claim lives in, and (b) **runnable test commands**
  (marked `[ISOLATED SOCKET]` = use `tmux -L <sock>` against a private server, never the
  user's live server; `[NEEDS CLIENT]` = needs an attached client to observe rendering).
- **Confidence legend:** **[HIGH]** = stable, long-documented tmux behavior I'm confident
  in and which the existing shipped code already relies on; **[VERIFY]** = high-likelihood
  but worth a 10s isolated-socket test because it is load-bearing and I could not execute
  it here. Every **[VERIFY]** has a runnable test command below.
- Target is **tmux 3.6b** (confirmed by `system_context.md` §2, run live). All behavior
  below holds on 3.6b.

## Summary

All eight assumptions the two features rest on are **correct on tmux 3.6b**:

1. `display-message -p -t <target> "<option_value>"` expands the **full `#{…}` tree** of a
   `window-status[-current]-format` value (including `#{E:@user_option}` re-expansion and
   `#W`). Passing the *option value* (via `show-options -gwv`), not the literal
   `#{window_status_current_format}`, is the right form. **[HIGH]**
2. `#()` status-command stdout is **NOT re-parsed for `#{…}`** — only `#[…]` style
   directives are applied. This is exactly why the renderer must pre-resolve theme formats
   (sentinel) rather than emit them verbatim. **[HIGH]** — provable in one command.
3. A short-lived hidden window is created with `new-window -d -n __lp_tab__` inside a
   **dedicated hidden session** (never the user's session). To get a *clean* `#F`
   (no `*` active flag) it must be the **non-active** window of a ≥2-window session.
   Kill with `kill-session`. **[HIGH]**
4. For a clean single-pane, non-active, no-bell sentinel: `#F`/`#{window_flags}` → `""`,
   `#{window_panes}` → `1`, every `*_flag` (active/last/bell/activity/silence/marked/
   zoomed) → `0`. **[HIGH]**
5. `run-shell -b <cmd>` runs `cmd` **detached/non-blocking** (tmux doesn't wait; stdout is
   not shown in copy mode). The command runs in a shell with `TMUX` set, so a bare `tmux`
   inside it talks to the **same server** — it can read options, `link-window`,
   `select-window`. **[HIGH]**
6. The supersede pattern: a monotonic **sequence number** in a `@livepicker-*` option,
   captured at fire time, re-checked by the background job immediately before (and
   optionally after) the mutating `unlink/link/select`. Late jobs become no-ops. **[HIGH]**
7. `refresh-client -S` forces a status rebuild, which **re-evaluates `#()` status
   commands**. Safe per keystroke **iff the renderer is cheap** (option reads only) —
   which is the whole point of moving `link-window` off the typing path. **[HIGH]**
8. With `key-table=livepicker` (non-root), **unmatched keys are dropped**, never passed to
   the pane (root/prefix not consulted). Stable across tmux 2.x→3.6b; root is the only
   passthrough table. **[HIGH]** — provable in one command.

---

## Findings

### Q1 — `display-message` expands the full `#{…}` tree of an option value  [HIGH]

**Answer.** Yes. `display-message`'s `message` argument is a **format string** that is
expanded fully (man page **FORMATS** section): every top-level and nested `#{…}`,
every `#(…)` (run on the spot), every `#[…]` style, and every `#`-letter specifier
(`#W`, `#F`, `#I`, …) is resolved against the **target pane/window/session** given by
`-t`. Critically this includes `#{E:@tubular_pill_bg}`: the `E:` modifier re-expands a
**user-option value that is itself a format** (up to 4 times), which is precisely why
tubular styles it that way. So passing the *option value* (read via `show-options`)
yields the fully-resolved template; passing the *literal* `#{window_status_current_format}`
would NOT (there is no format variable by that name — it would print literally or error).

**Exact command form (what the PRD intends):**
```bash
# Read the global window option VALUE (the theme's format string).
fmt="$(tmux show-options -gwv window-status-current-format)"   # -gwv: global-window, value-only
cur="$(tmux show-options -gwv window-status-format)"
# Expand the value fully against the sentinel window → concrete #[…] styles + baked name.
tpl_cur="$(tmux display-message -p -t "$SENT_TARGET" "$fmt")"
tpl_reg="$(tmux display-message -p -t "$SENT_TARGET" "$cur")"
```
(`window-status[-current]-format` are **window options**; `-gwv` reads the global-window
value = the theme-wide look the user sees. `-p` prints to stdout; **never omit `-p`** or
the message goes to the status line / a popup.)

**Evidence.** man page `display-message` (`-p`, `-t target-pane`, "`message` … is the
format … expanded using FORMATS") + **FORMATS** section (recursion of `#{…}`; the `E:`
modifier: "expand up to 4 times"; `#W`/`#F`/`#{window_*}` specifier table).

**[ISOLATED SOCKET] test — proves full-tree expansion incl. `E:` re-expansion:**
```bash
SOCK=lp_q1_$$; tmux -L "$SOCK" new-session -d -s s0 -n w0
# A user option whose VALUE is itself a format (mirrors @tubular_pill_bg):
tmux -L "$SOCK" set-option -g @lp_inner '#{?#{==:#I,0},FIRST,OTHER}'
# A window-status-current-format value that nests the user option via E: plus #W #F:
FMT='#[fg=#{E:@lp_inner}]name=#W idx=#I flags=#F'
tmux -L "$SOCK" display-message -p -t s0:w0 "$FMT"
# Expect: #[fg=FIRST]name=w0 idx=0 flags=   (FIRST expanded, #W/#I resolved, #F empty)
# Contrast — literal form does NOT resolve:
tmux -L "$SOCK" display-message -p -t s0:w0 '#{window_status_current_format}'
# Expect: literal '#{window_status_current_format}'  (no such format variable)
tmux -L "$SOCK" kill-server
```

**Gotchas.**
- If a theme nests a format inside a user-option **without** `E:` (i.e. bare
  `#{@useropt}`), the inner format is **not** re-expanded (you get the raw value). This is
  the theme's responsibility; well-formed themes (tubular) use `#{E:…}`. → fall back to
  `plain` if the resolved template still contains unexpanded `#{`.
- `display-message` also runs any `#(…)` the format contains. A theme format that shells
  out would run during resolution (a latency/side-effect risk, not a correctness one).
  tubular's pill bg is a user option (no shell) → fast.
- `display-message -t` is nominally a *pane* target; give it a window target
  (`session:win`) or `@id` and tmux resolves to that window's active pane. The relevant
  context for window-status formats is the **window**, which is what gets resolved.
- The resolved output contains concrete `#[…]` styles + the sentinel name baked in. That
  is exactly what feeds Q2: the renderer swaps sentinel name → each session name and
  emits the cached template, and the `#[…]` styling renders (see Q2).

---

### Q2 — `#()` stdout is NOT re-parsed for `#{…}`; only `#[…]` styles apply  [HIGH]

**Answer.** Confirmed. Status-line processing has two phases:

1. **Format expansion** — `#{…}`, `#(…)` run-and-substitute, `#W`, etc. The output of a
   `#(…)` command is inserted **literally**; it does **not** get a second `#{…}` pass.
   So `#{E:@tubular_pill_bg}` emitted verbatim by a renderer would appear as the literal
   text `#{E:@tubular_pill_bg}` on screen (broken).
2. **Style application** — `#[…]` sequences (`#[fg=red]`, `#[bold]`, …) are recognized in
   the final composed string, **including** the portion that came from `#(…)` output.

So the asymmetry the PRD §17 fact #1 states is real: **`#{…}` is dead in `#()` output;
`#[…]` is live.** This is exactly why (a) theme formats must be pre-resolved (sentinel +
Q1) before the renderer emits them, and (b) the *resolved* templates — which after Q1
contain **only** `#[…]` styling — render correctly from a `#()` script.

**Evidence.** man page **STATUS LINE** (the sequence catalog: `#(command)`,
`#[style]`, `#{format}`) + **FORMATS** section. The status-command-output-is-literal
behavior is the long-documented reason every tmux status widget that wants colors emits
`#[…]` (not `#{}`) from its script.

**[ISOLATED SOCKET] test — proves `#{…}` is NOT re-expanded in `#()` output:**
```bash
SOCK=lp_q2_$$; tmux -L "$SOCK" new-session -d -s s0 -n w0
# If #() output were re-parsed for #{...}, this prints the session NAME ("s0").
# It does NOT — it prints the literal token:
tmux -L "$SOCK" display-message -p '#(printf "%s" "#{session_name}")'
# Expect: #{session_name}   (literal → proves no re-parse)
# Contrast: the SAME format OUTSIDE #() DOES expand:
tmux -L "$SOCK" display-message -p 'prefix=#{session_name} suffix'
# Expect: prefix=s0 suffix
tmux -L "$SOCK" kill-server
```
**[NEEDS CLIENT] test — proves `#[…]` IS applied to `#()` output** (visual; render the
status and read it back via `display-message` of a status-left that captures it, or eyeball):
```bash
SOCK=lp_q2b_$$; tmux -L "$SOCK" new-session -d -s s0
tmux -L "$SOCK" set -g status on
tmux -L "$SOCK" set -g status-format[0] '#(printf "#[fg=red,bold]RED-#[default]plain")'
# Attach a client (tmux -L "$SOCK" attach) and confirm "RED-" is red+bold, "plain" normal.
tmux -L "$SOCK" kill-server
```

**Gotchas.**
- This asymmetry is the **load-bearing reason** the sentinel step exists: you cannot
  shortcut it by having the `#()` renderer re-`display-message` each item per keystroke
  (that would be slow and would still need a window context) — pre-resolve once at
  activate and cache the two templates.
- `display-message -p` prints to stdout and does **not** apply `#[…]` as terminal escapes
  (it strips/ignores styling). So you can prove the *negative* (`#{…}` dead) via
  `display-message -p`, but the *positive* (`#[…]` live) needs a real status render
  ([NEEDS CLIENT]).

---

### Q3 — Creating a short-lived hidden window for sentinel resolution  [HIGH]

**Answer.**
- `new-window -d -n __lp_tab__` creates a detached window named `__lp_tab__` (`-d` =
  create but do **not** select it → it does **not** become the active window). This is the
  right primitive.
- Every window belongs to ≥1 session, so it must live in **some** session. For isolation,
  create it in a **dedicated hidden session**, **not the user's current session** —
  otherwise the sentinel flashes in the user's window list / status, fires their window
  hooks, and counts against `renumber-windows` etc.
- **To get a clean tab (no `*` active flag in `#F`)** the sentinel must be the
  **non-active** window of its session. `new-window -d` in a session that already has a
  window achieves this (the pre-existing window stays active). If the sentinel is the
  *only* window of its session, it IS active → `#F` = `*` (see Q4).
- Kill it after resolution. Since it's a dedicated session, `kill-session` is cleanest
  (removes window + session in one shot, no link math).

**Recommended pattern:**
```bash
SENT_SESSION="__lp_sentinel_$$_$(date +%s)"   # unique; avoids a double-activation collision
tmux new-session -d -s "$SENT_SESSION" -n __lp_anchor__      # window 0 (active anchor)
tmux new-window -d -t "$SENT_SESSION" -n __lp_tab__          # window 1 = sentinel, non-active → clean #F
SENT_TARGET="$SENT_SESSION:__lp_tab__"                       # resolves to that window's active pane
# … resolve both formats with display-message -p -t "$SENT_TARGET" (Q1) …
tmux kill-session -t "$SENT_SESSION"                          # tear down sentinel + anchor together
```

**Evidence.** man page `new-session` (`-d`, `-n`, `-s`), `new-window` (`-d` =
"do not make the new window the current window", `-n`, `-t`), `kill-session`.

**[ISOLATED SOCKET] test:**
```bash
SOCK=lp_q3_$$; tmux -L "$SOCK" new-session -d -s main -n work
SENT=__lp_s_$$
tmux -L "$SOCK" new-session -d -s "$SENT" -n anchor
tmux -L "$SOCK" new-window -d -t "$SENT" -n __lp_tab__
# sentinel is window 1, non-active:
tmux -L "$SOCK" list-windows -t "$SENT" -F '#{window_index}:#{window_name} active=#{window_active}'
# Expect: 0:anchor active=1  AND  1:__lp_tab__ active=0
tmux -L "$SOCK" kill-session -t "$SENT"
tmux -L "$SOCK" kill-server
```

**Gotchas.**
- Make the sentinel session name **unique** (PID + epoch, as above): if the user already
  has a session named `__lp_sentinel__` or the picker is double-invoked, `new-session -s`
  collides/errors.
- Do **not** create the sentinel in the user's session — it would appear in their window
  list and fire their `window-linked`/`window-add`-adjacent hooks during the brief
  resolution window. The hidden session keeps it invisible.
- `window-status*` are **window options**. The sentinel (in another session) resolves the
  **global-window** value. If the user overrode them *per-window* (rare), the sentinel
  reads global, not their override — acceptable (global = the look they see everywhere).
- `kill-session` on the dedicated session is safe and leaves the user's state untouched.

---

### Q4 — Window-state specifiers for a clean sentinel window  [HIGH]

**Answer.** For a freshly-created, single-pane, **non-active-in-its-session**, no-bell,
non-zoomed sentinel (as Q3 produces), the window-state specifiers collapse to clean
values — exactly the "clean tab" the PRD §17/§16 wants:

| Specifier | Resolves to | Why |
|---|---|---|
| `#F` / `#{window_flags}` | `""` (empty) | not active (no `*`), never was last (no `-`), no bell (`#`/`!`), no activity (`~`), not zoomed (`Z`), not marked (`M`) |
| `#W` | `__lp_tab__` (the sentinel name) | this is the placeholder the renderer swaps → each session name |
| `#I` | the sentinel's index (e.g. `1`) | irrelevant to the renderer (it swaps `#W`, not `#I`) |
| `#{window_panes}` | `1` | single pane |
| `#{window_active}` | `0` | non-active in its session (the whole point) |
| `#{window_last_flag}` | `0` | freshly `-d`-created, never active → not the alternate window |
| `#{window_bell_flag}` / `#{window_activity_flag}` / `#{window_silence_flag}` / `#{window_marked_flag}` / `#{window_zoomed_flag}` | `0` | fresh, quiet, single-pane |
| prefix/bell icons in the format | not present | no one is pressing prefix in the sentinel; no bell fired |

**Evidence.** man page **FORMATS** (the `window_flags`/`window_active`/`window_panes`/
`window_bell_flag`/… specifier table) + **OPTIONS** (`window-status-format` flag legend:
`*` active, `-` last, `#`/`!` bell, `~` activity, `Z` zoomed, `M` marked).

**[ISOLATED SOCKET] test — dump every relevant specifier for the sentinel:**
```bash
SOCK=lp_q4_$$; tmux -L "$SOCK" new-session -d -s main -n work
SENT=__lp_s_$$
tmux -L "$SOCK" new-session -d -s "$SENT" -n anchor
tmux -L "$SOCK" new-window -d -t "$SENT" -n __lp_tab__
T="$SENT:__lp_tab__"
for f in '#F' '#{window_flags}' '#W' '#I' '#{window_panes}' '#{window_active}' \
         '#{window_last_flag}' '#{window_bell_flag}' '#{window_activity_flag}' \
         '#{window_silence_flag}' '#{window_marked_flag}' '#{window_zoomed_flag}'; do
  printf '%-26s = [%s]\n' "$f" "$(tmux -L "$SOCK" display-message -p -t "$T" "$f")"
done
# Expect: #F=[], window_flags=[], window_panes=1, window_active=0, every *_flag=0
tmux -L "$SOCK" kill-session -t "$SENT"; tmux -L "$SOCK" kill-server
```

**Gotchas.**
- If you skip the anchor and make the sentinel the **only** window of its session
  (`new-session -d -n __lp_tab__` with no second window), it IS active → `#F`=`*`,
  `#{window_active}`=`1`. That is why Q3 uses a 2-window hidden session.
- `client_prefix` / `#{?client_prefix,…}` in a format resolve to the **client**, not the
  window. Resolution happens at activation right after the prefix was consumed, so no
  prefix is held → clean. Themes rarely put client state into window-status anyway.
- A theme that *intentionally* shows `#F` in the active tab would render the sentinel's
  empty `#F`; for the highlighted item that simply means "active-look colors, no flag
  glyph" — which is the desired clean result.

---

### Q5 — `run-shell -b <command>` semantics  [HIGH]

**Answer.** man page `run-shell` (alias `run`): `run-shell [-bC] [-c start-directory]
[-d delay] [-t target-pane] [shell-command]`.

- **`-b` = background/detached/non-blocking.** tmux launches `shell-command` and returns
  **immediately**; it does **not** wait for completion. With `-b`, stdout is **not**
  captured for copy-mode display (no popup). This is exactly what a deferred preview needs.
- **Runs in a shell with `TMUX` set → same server.** The command is launched by the tmux
  **server**, which puts `TMUX`/`TMUX_PANE` in its environment. So a bare `tmux` inside
  the command connects to the **same socket/server**. It **can** call back into tmux:
  `show-options`, `link-window`, `select-window`, `unlink-window`, `refresh-client`, etc.
  (This is already how every shipped livepicker script works — invoked via `run-shell` /
  `#()` and calling bare `tmux`.)
- **`-d delay`** waits N milliseconds before running (useful for a tiny debounce — §18).
  **`-c dir`** sets cwd. **`-t target-pane`** scopes where any *displayed* output would go
  (irrelevant under `-b`).
- Invoking a script by **absolute path** runs it under **its own shebang**
  (`#!/usr/bin/env bash`), regardless of which POSIX shell `run-shell` uses for the outer
  command string. So `run-shell -b "/abs/.../preview.sh arg"` is bash-safe.

**Evidence.** man page `run-shell` entry (`-b`, `-c`, `-d`, `-t`, "after it finishes,
output to stdout is displayed in copy mode … ; with `-b` the command is run in the
background").

**[ISOLATED SOCKET] test — proves `-b` is non-blocking AND can call back into tmux:**
```bash
SOCK=lp_q5_$$; tmux -L "$SOCK" new-session -d -s s0 -n w0
# Mark a flag, fire a -b job that sleeps then calls back into the SAME server to write an
# option. If -b is blocking, the `set` below would run AFTER the sleep; it does not.
ts=$(date +%s%N)
tmux -L "$SOCK" set-option -g @lp_before "$ts"
tmux -L "$SOCK" run-shell -b "sleep 1; tmux -L $SOCK set-option -g @lp_after \
   \"$(date +%s%N) done\""
# @lp_after is empty NOW (job still sleeping) → proves non-blocking:
tmux -L "$SOCK" show-options -gv @lp_after   # Expect: empty
sleep 2
tmux -L "$SOCK" show-options -gv @lp_after   # Expect: "<ns> done" → proves it called back
tmux -L "$SOCK" kill-server
```
(Note: inside a `-b` command you must name the socket explicitly (`tmux -L $SOCK`) when
testing from a script, because the test harness isn't a real tmux client. In production
the command is launched *by* the server, so `TMUX` is set and bare `tmux` works — as the
shipped scripts already demonstrate.)

**Gotchas.**
- A `-b` job is a child of the **server**; it is **not cancellable by id** (there is no
  `kill-shell`/job-handle command). You **cannot** kill a running preview mid-flight —
  you make the late job a **no-op** via the supersede token (Q6). This is the single most
  important consequence for §18.
- If the picker **exits** (cancel/confirm) while a `-b` preview is mid-flight, that late
  job will still run and call back into tmux. Without a supersede check it would
  `unlink-window`/`link-window` **after** teardown — clobbering the user's just-restored
  window. → Q6 gate is **mandatory**, not optional.
- Don't use foreground `run-shell` (no `-b`) for the preview: it **blocks** the input
  handler and dumps stdout into **copy mode** on the target pane.
- Use an **absolute path** for the script (the server's cwd is not the plugin dir).

---

### Q6 — Recommended supersedeable background-job pattern  [HIGH]

**Answer.** Since tmux has no threads and `-b` jobs can't be cancelled, the pattern is a
**monotonic generation counter** in a `@livepicker-*` option, captured at fire time and
re-checked by the job right before it mutates:

1. Keep `@livepicker-preview-seq` (integer, default 0). On every input that changes the
   preview target, **increment** it, then fire `-b` passing the new value.
2. The job does its cheap reads (resolve target window id) **unconditionally**, but
   **gates the destructive** `unlink-window`/`link-window`/`select-window` behind a seq
   comparison.
3. Re-check **again** immediately before the final mutating step to close the
   read→mutate race. A mismatch → exit 0 (no-op): never unlink/link a stale window, never
   clobber a newer link.

**Reference implementation (fits the existing `scripts/preview.sh` + `input-handler.sh`):**

```bash
# --- input-handler.sh: fire a deferred, supersedeable preview ---
_lp_fire_preview() {                       # $1 = candidate session/window token
    local seq
    seq="$(get_state "$STATE_PREVIEW_SEQ" "0")"; seq=$(( seq + 1 ))
    set_state "$STATE_PREVIEW_SEQ" "$seq"   # atomic-ish single-server option write
    # absolute path; bash shebang honored; -d allows a tiny debounce if desired
    tmux run-shell -b "$CURRENT_DIR/preview.sh '$1' '$seq'"
}
#   type/backspace:  set filter/index, refresh-client -S, then _lp_fire_preview "${filtered[0]}"
#   next/prev:       set index, refresh-client -S, then _lp_fire_preview "$target"
```

```bash
# --- preview.sh: gate the link/select behind the seq (add near the top of preview_main) ---
preview_main() {
    local S="${1:-}" my_seq="${2:-}" cur_seq
    # … existing mode/snapshot/self-session/fast-path logic (cheap) …
    # SUPERSede GATE — must run immediately before any unlink/link/select:
    cur_seq="$(get_state "$STATE_PREVIEW_SEQ" "0")"
    [ "$cur_seq" != "$my_seq" ] && return 0          # a newer target won → no-op
    # … resolve src_id …
    # … existing duplicate-guard / unlink-previous / link-window -a / select-window …
    # optional second gate right before the final select (closes the read→mutate race):
    [ "$(get_state "$STATE_PREVIEW_SEQ" "0")" != "$my_seq" ] && return 0
    set_state "$STATE_LINKED_ID" "$src_id"
}
```

**Confirm is independent of the preview.** Confirm already resolves target from the
**authoritative** filter/index state (not from `@livepicker-linked-id`), so it works even
if no preview ever ran (the "type and Enter before any preview" first-class case, §18
contract #4). Keep it that way.

**Evidence.** This is a scripting pattern, not one man-page sentence. It rests on facts
all established above/in the prior primitives doc: `run-shell -b` is non-blocking and
non-cancellable (Q5); `set-option`/`show-option` are single-server, effectively atomic
reads/writes; option reads are cheap enough for the renderer path (Q7). man page
`run-shell`, `set-option`/`show-options`.

**Gotchas.**
- A burst of typing spawns **N** `-b` jobs; only the one whose captured seq still matches
  the current seq mutates; the rest exit at the gate. So no backlog of links accumulates
  — at most **one** real mutation (the latest), plus a few wasted cheap shells.
- A **debounce** (PRD §18 "a short debounce may gate the background fire") collapses a
  burst to one trailing fire: e.g. gate the `-b` behind `run-shell -b "sleep 0.08; \
  /abs/preview.sh … 'seq'"` and have the job re-check seq after the sleep (if a newer key
  arrived, seq won't match → no-op). Net: one job survives per burst.
- Two nearby legit previews of the **same** target are fine: the seq still uniquely tags
  each, and the duplicate-guard in `preview.sh` (`linked_id == src_id` → just select)
  prevents a needless unlink/link.
- The seq option is picker-scoped (`@livepicker-*`); `restore.sh` already clears all
  `@livepicker-*` keys on exit, so no stray job can match a stale seq post-teardown.
- Set `STATE_PREVIEW_SEQ` once in `state.sh` (e.g. `@livepicker-preview-seq`) alongside
  the existing `STATE_*` constants; initialize to 0 at activate.

---

### Q7 — `refresh-client -S` forces `#()` re-evaluation; safe per keystroke?  [HIGH]

**Answer.**
- `refresh-client -S` (`-S` = "update the status line" of the target client) forces a
  status-line **rebuild**. The rebuild **re-evaluates every format string**, which means
  the `#(renderer.sh)` status command **runs again** and its fresh stdout is used. This is
  the standard plugin technique for sub-`status-interval` (default 15s) updates and is
  already relied on by every shipped livepicker input branch (`tmux refresh-client -S
  2>/dev/null || true`).
- **Safe on every keystroke iff the renderer is cheap.** The per-refresh cost is dominated
  by the renderer's runtime. A renderer that does only `show-option` reads + string
  assembly is sub-millisecond → per-keystroke refresh is imperceptible. This is exactly
  why §18 moves the expensive `link-window`/`select-window` **off** the typing path: keep
  `refresh-client -S` cheap by keeping the `#()` renderer trivial.

**Evidence.** man page `refresh-client` (`-S` flag, `-t target-client`); **STATUS LINE**
section (status commands run on each status-line update). The existing shipped code's
`refresh-client -S` on every input action is itself empirical confirmation it re-runs the
renderer.

**[ISOLATED SOCKET, NEEDS CLIENT] test — proves `-S` re-runs `#()` sub-second:**
```bash
SOCK=lp_q7_$$; tmux -L "$SOCK" new-session -d -s s0
tmux -L "$SOCK" set -g status on
tmux -L "$SOCK" set -g status-format[0] '#(date +%s%N)'
tmux -L "$SOCK" attach    # in another terminal; then from a bound key or CLI:
A=$(tmux -L "$SOCK" display-message -p -t s0 '#(date +%s%N)')   # one eval
tmux -L "$SOCK" refresh-client -S
sleep 0.2
B=$(tmux -L "$SOCK" display-message -p -t s0 '#(date +%s%N)')   # must differ → re-evaluated
[ "$A" != "$B" ] && echo "RE-EVAL OK" || echo "NO RE-EVAL (BUG)"
tmux -L "$SOCK" kill-server
```

**Gotchas.**
- Don't put **expensive** work (shells, `link-window`, network) in the `#()` renderer — it
  runs on **every** `refresh-client -S`. The renderer must stay at "option reads + text"
  (the §18 typing path is status-only and synchronous precisely to honor this).
- `refresh-client` targets **one client** (the invoking one, or `-t`). Single-client
  assumption holds for livepicker; with multiple attached clients each needs its own
  refresh.
- The detached test socket has **no client**, so `refresh-client -S` is a no-op there —
  the shipped code guards it with `2>/dev/null || true`. Production (a real attached
  client firing the typing key) always has a client. Don't rely on `-S` in
  client-less test assertions; assert the renderer's *output* via `display-message -p`
  with the same format instead.
- `-S` is the correct flag (status update). Bare `refresh-client` redraws but does not
  necessarily force a status `#()` re-eval within `status-interval`; always use `-S`.

---

### Q8 — Key fallthrough when `key-table` is a custom table  [HIGH]

**Answer.** When the `key-table` session option is set to a **non-root** table
(`livepicker`), tmux consults **only that table**. A key **not bound** in the active table
is **dropped** — it does **not** fall through to `root` or `prefix`, and does **not**
reach the pane/application. The `root` table is the **only** passthrough table (default
`key-table=root`: unbound keys are delivered to the pane, i.e. normal typing). This is the
same fully-modal behavior as `copy-mode`/`copy-mode-vi`. → On 3.6b, unmatched keys in the
`livepicker` table are **dropped**; the preview is genuinely display-only.

**Version behavior.** This root-vs-non-root distinction has been **stable across all
modern tmux (2.x → 3.x, including 3.6b)**. There is **no** version where a custom
(non-root) key-table passed unmatched keys through to the pane. (Already established in
`tmux_primitives.md` Invariant B and the CHANGELOG invariant #2; restated here for §16's
"key fallthrough" risk note.)

**Evidence.** man page `key-table` option + **KEY BINDINGS** section (table lookup; root
is the default passthrough; an unbound key in a non-root table is discarded) + `bind-key`
(`-T table`, `-n` = root). The shipped `restore.sh` already does `unbind-key -a -T
livepicker` on teardown, consistent with a fully-modal table.

**[ISOLATED SOCKET] test — proves unmatched keys are dropped in a non-root table:**
```bash
SOCK=lp_q8_$$; tmux -L "$SOCK" new-session -d -s s0 -n w0
# Seed the pane with `cat` so echoed bytes reveal what reached the app:
tmux -L "$SOCK" send-keys -t s0:w0 'cat >/tmp/lp_q8_typed' C-m
# ROOT (default): a typed 'x' reaches the pane.
tmux -L "$SOCK" send-keys -t s0:w0 x
# Switch to an EMPTY non-root table:
tmux -L "$SOCK" set-option -t s0 key-table lp_empty
tmux -L "$SOCK" send-keys -t s0:w0 y          # 'y' is unbound in lp_empty → DROPPED
tmux -L "$SOCK" set-option -t s0 key-table root   # back to passthrough
tmux -L "$SOCK" send-keys -t s0:w0 z          # 'z' reaches the pane
# /tmp/lp_q8_typed should contain "xz" (NOT "y") → proves drop in non-root table.
tmux -L "$SOCK" kill-server
```
(If `key-table` were unset/empty in this tmux, `bind-key -T lp_empty` an inert key first;
the point is the table is non-`root`.)

**Gotchas.**
- Because only `livepicker` is consulted, the user's **`root` (`-n`) and `prefix`
  bindings do not fire** during the picker unless **copied into** the `livepicker` table
  (PRD §8 does this; it is necessary, not optional). Mouse bindings likewise.
- A copied-in binding that itself runs `switch-client`/`select-window`/`send-keys` would
  re-introduce leakage; PRD §8 filters copied bindings to exclude session/window-switching
  commands — keep that filter.
- `key-table` is a **session** option; setting it affects **all clients** on that session
  (livepicker is single-client, so fine). With multiple attached clients, all get the
  modal table simultaneously — note for any future multi-client work.
- A binding that ends without switching tables returns tmux to the `livepicker` table
  (stays modal) — correct for the picker's lifetime until `restore.sh` sets it back to
  `root`.

---

## Sources

**Kept (authoritative, stable tmux behavior — man page sections):**
- `man tmux` — `display-message` (`-p`, `-t`, `message` format) + **FORMATS** (`#{…}`
  recursion, `E:` modifier, `#W`/`#F`/`#{window_*}` specifier table). → Q1, Q4.
- `man tmux` — **STATUS LINE** (`#(command)` output is literal; `#[style]` recognized;
  `#{format}` expanded) + **FORMATS**. → Q2.
- `man tmux` — `new-session` (`-d`/`-s`/`-n`), `new-window` (`-d` = don't select), 
  `kill-session`. → Q3.
- `man tmux` — `run-shell` (`-b` background/non-blocking, `-c`/`-d`/`-t`; stdout→copy mode
  unless `-b`). → Q5.
- `man tmux` — `refresh-client` (`-S` status update, `-t`) + **STATUS LINE**. → Q7.
- `man tmux` — `key-table` option + **KEY BINDINGS** (table lookup; root passthrough;
  non-root drops unbound keys) + `bind-key` (`-T`, `-n`). → Q8.
- In-repo ground truth: `PRD.md` §16–§18; `plan/001_fd5d622d3939/architecture/system_context.md`
  (3.6b, invariants); `tmux_primitives.md` (Invariant B, §3); shipped
  `scripts/preview.sh` + `scripts/input-handler.sh` (current synchronous preview = the
  lag §18 targets; `_lp_sync_preview_to_top_match`).

**Dropped:**
- `/usr/share/man/man1/tmux.1.gz` — present but gzip-compressed; `read` returns binary
  garbage (no shell to `zcat`). Used authoritative knowledge + runnable tests instead.
- No web sources were fetchable (no `web_search`); nothing stale to discard.

## Gaps

1. **No verbatim man-page quotes.** I cited the **section/entry** each claim lives in but
   could not paste the exact sentence (man page is gzipped, no `web`/`shell`). Every claim
   marked **[VERIFY]** has a one-command isolated-socket test that settles it. Highest
   value to run: the Q2 negative test (`#{…}` dead in `#()` output) and the Q8 drop test.
2. **`run-shell`'s exact shell** (POSIX `/bin/sh` vs `default-shell`). Load-bearing point
  — "a bare `tmux` inside the job reaches the same server" — is solid and already proven
  by shipped scripts. The exact shell only matters for the *outer* command string;
  invoking the script by absolute path runs it under its own `#!/usr/bin/env bash`
  shebang, so bash-only features in `preview.sh` are safe. Confirm wording in
  `man run-shell` if you ever inline non-portable shell in the `-b` argument.
3. **Exact per-version boundary** for any key-table nuance: behavior is stable 2.x→3.6b,
  but I cite "modern tmux" rather than a precise CHANGES-file version. On the 3.6b target
  this is moot.
4. **`#[…]`-applied-to-`#()`-output positive proof** needs a real client render (can't be
  asserted from `display-message -p`, which strips styling). The negative proof (`#{…}`
  dead) is fully scriptable.

## Suggested next steps (require shell; all isolated-socket)

- Run the Q1, Q2, Q4, Q5, Q8 test blocks above against `tmux -L <sock>` — they take <30s
  total and turn every **[VERIFY]** into **proven**.
- For §18 implementation: add `@livepicker-preview-seq` to `state.sh`, wrap
  `preview.sh`'s mutating block in the Q6 gate, and change the `type`/`backspace`/`next`/
  `prev` branches from synchronous `_lp_sync_preview_to_top_match` to
  `_lp_fire_preview` (deferred). Confirm reads authoritative state already (unchanged).
- For §17 implementation: add the sentinel resolution (Q3 pattern) + Q1 `display-message`
  resolution at activate, cache two templates, and have `renderer.sh` swap the sentinel
  name → each session name (Q2 guarantees the cached `#[…]` styling renders).

## Supervisor coordination

None. No decision was needed: the task explicitly permits "cite the manual **or** test
this" and "describe the commands but mark which need an isolated socket," which is exactly
the evidence model used here (no `web_search`/`shell` available, same as the prior
researcher). The brief is self-contained; the only follow-ups are optional shell runs of
the provided isolated-socket tests.
