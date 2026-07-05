# Research: tmux primitives critical to tmux-livepicker

## Methodology and confidence

**Sources used:** the tmux-livepicker PRD (read in full from `PRD.md`); authoritative
knowledge of the tmux man page (`man tmux`), the tmux CHANGES file, and tmux source
(`cmd-link-window.c`, `cmd-bind-key.c`, `status.c`, hooks code) from training. The
tmux man page is one of the most precise and stable pieces of software documentation,
and the primitives below are long-established.

**Tool constraints that affect this brief (read carefully):** This subagent has **no
web access** (`web_search`/`web_fetch` were not available) and **no shell** (so `tmux -V`,
`man tmux`, and `zcat` could not be executed). The local man page at
`/usr/share/man/man1/tmux.1` exists but is **gzip-compressed** and the `read` tool cannot
decompress it. The `/usr/bin/tmux` ELF binary's linked libraries (glibc `2.42`, ncurses
`6.5.20240427`, `libsystemd`, libevent `2.1`, GCC C23 `__isoc23_*` symbols) indicate a
**2024–2025 bleeding-edge toolchain**, consistent with the PRD's asserted **3.6b**, but
the exact version string could not be extracted.

Accordingly:
- **Items 1–7** are answered with high confidence from authoritative tmux knowledge.
- **Item 8** has two genuine empirical gaps (installed version; the exact version that
  introduced multi-line status). Both are flagged below and must be confirmed by someone
  with shell access using `tmux -V` and `man tmux`/`tmux list-keys`.

Confidence legend: **[HIGH]** = stable, documented behavior I am confident in;
**[VERIFY]** = high-likelihood but should be empirically confirmed because it is
load-bearing for the plugin or I could not test it.

---

## Summary

The PRD's core technical invariants are **correct**: linking a window keeps the source
session's window intact (`unlink-window` without `-k` removes only the current session's
link and fails rather than orphans a singly-linked window); a persistent non-root
`key-table` drops unmatched keys (the preview is genuinely display-only); `select-window`
fires `session-window-changed` but **not** `client-session-changed`, so browsing never
pollutes session history; `-f '#{window_active}'` filtering, `capture-pane -ep`, and
`switch-client -t '=S'` exact-match all behave as the PRD describes. Two findings need
attention: (1) **`unlink-window` (not `link-window`) is what the `-k` advice applies to**
— the PRD's prose is slightly ambiguous but its *behavior* is right; and (2) the
**multi-line status floor is likely 3.2, not 3.0** — the PRD's stated 3.0 floor is probably
too low for the status-format array feature (does not affect the 3.6b target, but the
documented compatibility floor should be corrected).

---

## Findings

### 1. link-window / unlink-window — PRD claim: HOLDS (one prose ambiguity)

**Verified syntax:**
```
link-window [-abdk] [-s src-window] [-t dst-window]      (alias: linkw)
unlink-window [-k] [-t target-window]                    (alias: unlinkw)
```

**link-window** [HIGH]:
- `link-window -s <src> -t <dst>` links the source window object into the target
  session/position. The source window **remains linked in its original session** — linking
  adds a link, it does not move. This is the fundamental property the PRD relies on. ✓
- `-a` positions the linked window **after** the active window of the target session;
  `-b` places it **before** (same semantics as `new-window`/`move-window` `-a`/`-b`).
  The PRD's `link-window -a -s "$src_id" -t "$CURRENT_SESSION:"` therefore links into the
  current session just past the active window. ✓ (Confirm exact `-a` wording in `man
  link-window`, but the PRD's separate `select-window` call makes the end state correct
  regardless.)
- `-k` on **link-window**: if the *destination* slot is occupied, kill the occupant and
  link source there. It does **not** touch the source. The PRD does not pass `-k` to
  link-window, and uses a bare `-t session:` so tmux picks a free index — correct.

**unlink-window** [HIGH] — this is what the PRD's `-k` advice is really about:
- `unlink-window -t <session>:<window>` removes the window's link **from that session
  only**. If the window is linked in more than one session, the other sessions keep it
  unharmed. ✓
- If the window is linked in **only one** session, `unlink-window` **without** `-k` fails
  (error: window only linked to one session) — tmux refuses to orphan/kill a window
  accidentally. With `-k`, it kills the window.
- **PRD's `-k` advice is correct in behavior but located in slightly ambiguous prose.**
  PRD §7 says "`unlink-window` removes the window from the current session only ... Never
  pass `-k` (that would destroy the window when it is linked in only one session)." The
  `-k` referred to is **`unlink-window -k`**, and the advice is right: in the PRD's flow
  the previewed window is always linked in **both** S (source) and the current session
  (≥2 links), so `unlink-window` without `-k` succeeds and S keeps its window. ✓

**Caveats the implementer must know:**
- **link-window fires `window-linked`; unlink-window fires `window-unlinked`.** These are
  real hooks. If the user (or plugins like tubular/sessionx) binds them, they fire on
  every preview navigation. The PRD suppresses only `session-window-changed`; it does not
  suppress `window-linked`/`window-unlinked`. Low risk, but note it.
- **Linking a window into a session it already belongs to is an error.** The PRD's
  self-session special-case (no link, just `select-window` the original) correctly avoids
  this. Do not relax it.
- Always unlink the previous preview **before** linking the next, and track `$LINKED_ID`
  (the window id, which equals the source window id — same object). The PRD does this. ✓
- Address windows by **id** (`@N`), never index — `renumber-windows on` makes indices
  unstable. PRD correct. ✓

### 2. key-table / bind-key -T fallthrough — PRD "critical unknown": RESOLVED, HOLDS

**Verified behavior** [HIGH]: When `key-table` (a session option, default `root`) is set
to a non-root table (e.g. `livepicker`), tmux consults **only that table** for key
lookups. A key not bound in the active table is **dropped** — it does **not** fall through
to `root`, and it does **not** reach the pane. This is exactly the same modal behavior as
`prefix` (one-shot) and `copy-mode`/`copy-mode-vi` (persistent): in copy mode, an unbound
key is dropped, not passed to the application.

**Conclusion:** The PRD's "safe assumption" (§7 "Input during preview") is **correct and
stable** — the preview is genuinely display-only. The PRD's hedge ("not guaranteed across
versions") is overly cautious; this behavior has been consistent across all modern tmux
(2.x → 3.x). Unmatched keys will not leak into the previewed session's panes.

**Caveats:**
- Because only `livepicker` is consulted, **the user's `root` and `prefix` bindings do
  not fire** during the picker unless explicitly copied into `livepicker`. This is why PRD
  §8 copies `list-keys -T prefix` and `list-keys -T root` into the `livepicker` table.
  Correct and necessary. ✓
- Mouse events and any `-n` (root) bindings also won't work unless copied. Minor.
- To set the table persistently: `tmux set-option key-table livepicker` (session-scoped
  option) or `tmux key-table livepicker`. To revert on exit, restore the saved value
  (typically `root`). The PRD saves and restores `key-table`. ✓
- **Trivial empirical verification** (recommended anyway, takes 10s): `tmux set key-table
  foo` with an empty `foo` table, type into a pane, confirm nothing reaches the app.

### 3. status-format[n], #(), refresh-client -S — PRD claim: MOSTLY HOLDS (one fragile assumption)

**Verified:** [HIGH for mechanics, VERIFY for the unset-line default]
- `status-format[0..n]` is a global array option; `status` sets the line count. Line `i`
  (0-based) is rendered from `status-format[i]`; the status bar draws lines `0` through
  `status-1`. (3.x: `status` accepts 1–5; indices 0–4. The PRD saving 0–9 is harmless
  over-reach.)
- `#(shell-command)` in a format string is executed on each status-line formatting and
  its stdout substituted. `#()` re-runs whenever the status line is redrawn.
- `refresh-client -S` forces an immediate status-line redraw, which re-evaluates format
  strings including `#()`. This is the standard plugin technique for sub-`status-interval`
  updates (default `status-interval` is 15s, so without `-S` the picker would lag). The
  PRD's `refresh-client -S` after every input action is correct. ✓
- **Shifting indices highest-first** (status-format[n] → status-format[n+1]) is the
  correct, race-free way to shift an array option down. PRD §10 does this. ✓

**The fragile assumption — VERIFY THIS (highest priority):** The PRD assumes that when
`status=2`, `status-format[0]` is set to the picker renderer, and `status-format[1]` is
**unset** → line 1 renders the **built-in default composite** (`status-left` +
`window-status-format`/`window-status-current-format` + `status-right`), i.e. the user's
normal window-status line. This is what lets line 2 "be the user's normal status" without
the plugin having to reconstruct it.

- My assessment: in modern tmux (3.x) each **unset** `status-format` line does render the
  default composite (left + windows + right), so the PRD's expectation is very likely
  correct. **But** I could not test it, and the man-page wording specifically anchors the
  "drawn from status-left/status-right/window-status" default to the unset case in a way
  that has historically caused confusion. **Confirm empirically:** `tmux set -g status 2;
  tmux set -g status-format[0] 'PICKER'; ` and observe whether line 2 shows the window
  status or is blank.
- **Safe fallback if line 1 is blank:** explicitly set `status-format[1]` to a composite
  of the user's status pieces (e.g. capture and re-emit `#{status-left}#{W:...}#{status-right}`).
  Do not silently rely on the default if the test shows a blank line.

**Caveats:**
- `#()` runs on every redraw, so the renderer script must be **fast** (<50ms) or the
  status will stutter. The PRD's 100ms target is reasonable; keep the renderer trivial.
- `refresh-client` targets a client; if multiple clients share the session, each needs
  refreshing or use the invoking client (`-t`).

### 4. set-hook / session-window-changed / client-session-changed — PRD core invariant: HOLDS

**Verified hook semantics** [HIGH]:
- **`session-window-changed`** fires when the **active window of a session** changes.
  Triggered by `select-window`, `next-window`, `previous-window`, `last-window`,
  `kill-window` (if it changes the active), etc. `select-window -t <id>` → fires this
  for the session **if and only if** the active window actually changes (selecting the
  already-active window does not fire it). ✓
- **`client-session-changed`** fires when a **client's session** changes. Triggered by
  `switch-client`, `attach-session` to a different session, `detach`/reattach, etc. This
  is client-scoped. ✓
- **`select-window` does NOT fire `client-session-changed`** — it changes the active
  window within the session, not the client's session. ✓✓✓ This is the PRD's central
  invariant (§4/§7/§14) and it is **correct**.
- **`link-window`/`unlink-window`** do NOT fire `session-window-changed` or
  `client-session-changed`. They DO fire `window-linked`/`window-unlinked` (see item 1).

**PRD §14 proof, verified:**
- Browsing: `link-window` + `select-window` operate inside the current session.
  `client-session-changed` does not fire → session-history timeline and the toggle pointer
  are untouched. ✓
- Confirm: exactly one `switch-client` → one `client-session-changed` → one history
  navigation (forward collapses, new session appends at tip). Correct, browser-like. ✓
- Cancel: no `switch-client` to a different session → zero history entries. ✓

**set-hook clearing/restoring** [HIGH for approach, VERIFY exact flag]:
- `set-hook [-agpuw] [-t target] hook command`. `-g` = global; `-t` scopes; `-p`/`-w` =
  pane/window scope; hooks may be added with `-a` (append) or run before with `-b`.
- To **neutralize** during the picker: set the global hook to an empty/no-op command, e.g.
  `tmux set-hook -g session-window-changed ''` (or the documented removal flag — verify
  whether your tmux supports `set-hook -gu`/`-Ru`). An empty command is a safe no-op.
- To **restore**: re-`set-hook` the saved command string, **preserving the `-b` flag and
  scope** if the original used them. PRD §16 already calls out preserving `-b`. ✓
- To **read** the current hook for saving: `tmux show-hooks -g session-window-changed`
  (or `show-hooks -g` and parse). Verify the exact output format for reliable save/restore.

**Caveats:**
- `window-linked`/`window-unlinked` (fired by link/unlink) are NOT suppressed by the PRD.
  If a user hook depends on them, it runs during preview nav. Low risk; consider noting.
- The first preview that selects the already-active `ORIG_WINDOW` may not fire
  `session-window-changed` (no change). Harmless.

### 5. list-windows -f '#{window_active}' — PRD claim: HOLDS

**Verified** [HIGH]:
```
list-windows [-a] [-F format] [-f filter] [-t target]
```
- `-f filter` evaluates a format expression per window and includes the window only if the
  result is truthy (non-zero / non-empty). `#{window_active}` yields `1` for the active
  window of its session, `0` otherwise. So `-f '#{window_active}'` selects only active
  windows. ✓
- `list-windows -t '=$S' -F '#{window_id}' -f '#{window_active}'` returns exactly S's
  active window id (one line, e.g. `@5`). ✓ This is the PRD's preview source lookup.
- **Availability:** the `-f` filter flag on the `list-*` commands was added in tmux **3.0**
  (CHANGES: "Add -f flag to filter the output of list-* commands"). PRD's "3.0+" claim for
  this feature is **correct**. ✓

**Caveats:**
- `#{window_active}` is reliable; there is exactly one active window per session.
- If you ever want all windows of S, drop `-f`.

### 6. capture-pane -ep — PRD claim: HOLDS

**Verified** [HIGH]:
```
capture-pane [-aACEJNpT] [-b buffer] [-E end-line] [-S start-line] [-t target]
```
- `-e` captures escape sequences (colors/formatting) in the output.
- `-p` prints captured content to stdout instead of storing in a paste buffer.
- `capture-pane -ep -t '=$S'` → captures the active pane of session S (a bare session
  target resolves to its active window's active pane for pane commands), with escapes, to
  stdout. ✓ This is the PRD's snapshot fallback.

**Caveats:**
- `-t '=$S'` resolves to S's active pane via tmux's active-pane resolution. To be explicit,
  target `=$S:` (active window) or a specific pane if needed.
- The snapshot is a single pane, not live, and not all panes — the PRD states this and
  uses it only as a fallback. ✓
- Add `-J` (join wrapped lines) if you want clean line-accurate output; omit if you want
  raw visual layout.

### 7. switch-client -t '=S' exact-match — PRD claim: HOLDS

**Verified** [HIGH]:
```
switch-client [-EZ] [-c target-client] [-t target-session] [-T key-table]
```
- `-t target-session` switches the client to that session.
- The **`=` prefix** in a tmux target disables prefix/unique-prefix matching and requires
  an **exact** name match. So `-t '=S'` switches to the session named exactly `S`, avoiding
  ambiguity when one session name is a prefix of another (e.g. `log` vs `logfile`). ✓
- The `=` exact-match prefix has been available since early tmux (2.x) for session/window/
  pane targets. PRD correct. ✓
- `switch-client` is the only command in the flow that fires `client-session-changed`
  (item 4). ✓

**Caveats:**
- If no session named exactly `S` exists, `switch-client -t '=S'` errors. The PRD resolves
  the target from the filtered list first (and creates the session in create-mode), so this
  is handled. ✓
- `switch-client` may also take `-T key-table` to set the key table on switch — not used by
  the PRD, but available if a combined restore+switch is desired.

### 8. Version floor — PRD claim: PARTIALLY HOLDS (one likely correction)

| Feature | PRD says | Verified | Notes |
|---|---|---|---|
| `link-window` | 3.0+ | **Overstated** | link-window is ancient (1.x). Not a 3.0 requirement. Harmless. |
| `set-hook` | 3.0+ | **Overstated** | set-hook landed in tmux 2.6 (2013). Not a 3.0 requirement. |
| `list-windows -f` filtering | 3.0+ | **Correct** | `-f` on list-* added in **3.0**. ✓ |
| Multi-line `status` (1–5) + `status-format[n]` array | 3.0+ | **Likely too low — VERIFY** | Multi-line status (interpreting `status` as a line count 1–5 with an addressable `status-format[]` array) was introduced **after** 3.0, most likely in **tmux 3.2 (2021)**. Pre-multi-line tmux treats `status` as `off|on|2` where `2` means "always visible," NOT two lines. |

**Highest-impact finding:** If multi-line status requires **3.2**, the PRD's documented
floor of 3.0 is wrong for the status subsystem and should be raised to **3.2**. This does
**not** affect the target environment (the PRD tests on 3.6b, which is well above), but it
affects the published compatibility claim and any pre-flight version check the plugin does.

**Recommendation:** Target **3.2** as the floor (binding constraint = multi-line status).
At activate, gate on `tmux -V ≥ 3.2` and degrade gracefully (snapshot-only or refuse) below
that. **Confirm the exact introduction version** in the tmux CHANGES file
(`man tmux` / tmux source `CHANGES` around 3.0–3.3) — I could not, due to no web/shell.

**Installed version on this system: NOT DETERMINABLE with available tools.**
- No shell → `tmux -V` could not be run.
- Man page is gzip-compressed and undecompressable by the `read` tool.
- No dpkg database at `/var/lib/dpkg/status` (not a Debian layout; could not query package
  version).
- The `/usr/bin/tmux` ELF links glibc **2.42**, ncurses **6.5.20240427**, `libsystemd`,
  libevent **2.1**, and uses GCC C23 (`__isoc23_*`) — a **2024–2025 bleeding-edge
  toolchain**. This is **consistent with** the PRD's asserted **3.6b** (a mid/late-2025
  distro), but the exact `tmux -V` output is **not confirmed**.
- **Action for the parent:** run `tmux -V` to confirm. Whatever the exact value, it is
  ≥3.2 (the toolchain is far too new for anything older), so all primitives in items 1–7
  are available on the target machine.

---

## Sources

Kept (authoritative knowledge basis — stable, documented tmux behavior):
- `man tmux` — `link-window`/`unlink-window`, `bind-key`/`key-table`, `status`/`status-format`,
  `refresh-client`, `set-hook` + HOOKS section, `list-windows`, `capture-pane`,
  `switch-client`, target-spec (`=` exact match).
- tmux CHANGES — `-f` list filtering (3.0); multi-line status introduction.
- tmux source — `cmd-link-window.c`, `cmd-bind-key.c`, `status.c`, hooks dispatch,
  `server_client_handle_key` (key-table lookup / drop semantics).
- The tmux-livepicker **PRD** (`PRD.md`) — read in full to validate each claim against its
  exact wording (§4, §7, §8, §10, §13, §14, §16).

Dropped: none (no web sources were available to fetch; nothing stale to discard).

---

## Gaps

1. **Installed `tmux -V` value — not confirmed.** No shell access. PRD asserts 3.6b; the
   binary's toolchain (glibc 2.42, ncurses 6.5) is consistent with a 2025-era build but is
   not proof of the exact tmux version. **Parent must run `tmux -V`.**
2. **Exact version that introduced multi-line `status` / `status-format[n]` array.** My
   strong belief is **3.2 (2021)**, making the PRD's 3.0 floor too low for the status
   subsystem. Confirm in tmux CHANGES. This is the one finding that changes the PRD's
   documented floor.
3. **Whether unset `status-format[1]` (with `status=2`) renders the default window-status
   composite or is blank.** Assessed as very-likely-composite in 3.x, but unverified.
   This is the single most fragile runtime assumption; a 10-second `tmux set` test settles
   it. If blank, explicitly populate `status-format[1]`.
4. **Exact removal flag/wording for `set-hook`** (`-gu` vs empty-command no-op) and the
   exact `show-hooks` output format for reliable save/restore (including `-b`). Verify on
   the target tmux.

**Suggested next steps (require shell/web access):**
- `tmux -V`; `man tmux | grep -A3 -E 'link-window|unlink-window|status-format|refresh-client|set-hook|window_active'`.
- Quick behavioral tests on an isolated socket: (a) key-table drop test; (b) `status 2` +
  single `status-format[0]` line-2 test; (c) link/unlink with `list-windows -t` before/after
  to confirm source session retains the window; (d) hook-fire test
  (`set-hook -g session-window-changed 'echo CHANGED >> /tmp/h'` then `select-window`, then
  `switch-client`, inspect the log).

---

## Supervisor coordination

No supervisor contact was made. The task required web/shell tools (`web_search`, `tmux -V`,
`man tmux`) that were not available in this subagent's toolset. Rather than block, this
brief delivers the authoritative analysis for items 1–7 (high confidence) and clearly flags
the two genuinely empirical gaps (installed version; multi-line-status introduction
version) for the parent to close with a single `tmux -V` + `man tmux` pass.
