# System Context: tmux-livepicker Delta 004

## Project state

The tmux-livepicker plugin is a **shipped, green implementation** (~3100 lines of
bash across 11 scripts + 16 test files). It works as a single-axis session picker:
type to filter, navigate sessions, confirm to land, cancel to restore. The prior
plan iterations (001 through 003) built the complete session-picker, renderer,
fuzzy ranking, status-line layout, scroll viewport, session management (rename/
delete), preview clip sizing, deferred preview, and window-status tab appearance.

**Delta 004 adds a second navigation axis**: the window-flip axis. Today the
user's window-nav keys (`C-M-Tab`/`C-M-BTab`) are repurposed into session-nav
while the picker is open. This delta instead keeps them doing window navigation
(scoped to the previewed session) and adds separate, *discovered* session-nav keys.

## What already works (DO NOT re-implement)

| Subsystem | Files | Status |
|-----------|-------|--------|
| Status-line renderer (query bar, ranked tabs, viewport, overflow) | `renderer.sh`, `layout.sh` | Shipped + cached config + fork-free width |
| Fuzzy ranking (subsequence match + score) | `rank.sh` | Shipped, single source of truth |
| Live preview (link-window mechanism) | `preview.sh` | Shipped, shows candidate's ACTIVE window only |
| Session picker (type/filter/nav/confirm/cancel) | `input-handler.sh`, `livepicker.sh` | Shipped, single-axis (session only) |
| State save/restore | `state.sh`, `restore.sh` | Shipped, 6-step teardown |
| Session management (rename/delete) | `session-mgmt.sh` | Shipped |
| Key table (copy+bind+switch) | `livepicker.sh` T4 block | Shipped, but single-axis (wrong binds) |
| Deferred preview (supersedeable) | `input-handler.sh` helpers | Shipped, 3-guard seq mechanism |
| Preview clip (window-size manual + height pin) | `livepicker.sh`, `restore.sh` | Shipped, driver-only pin |
| Window-status tab appearance | `livepicker.sh`, `renderer.sh` | Shipped, sentinel resolution + cache |
| Isolated-socket test harness | `tests/setup_socket.sh`, `tests/helpers.sh` | Shipped |

## What this delta changes

### Gap 1: Two-axis navigation (THE headline gap)
- **Current:** `opt_next_key`/`opt_prev_key` (C-M-Tab/C-M-BTab) + `opt_nav_next_keys`/
  `opt_nav_prev_keys` (Down/Up) → ALL wired to `next-session`/`prev-session`.
- **Required:** Two axes:
  - **Session axis:** discovered `switch-client -n/-p` keys + arrows → `next-session`/`prev-session`
  - **Window axis:** discovered `next-window`/`select-window -n` keys → `next-window`/`prev-window`
- **Option model change:** 4 old options removed, 4 new options added (empty default → discovery fills)

### Gap 2: Key discovery (absent)
- **Current:** Hardcoded defaults, no `list-keys` parsing. Comment at `livepicker.sh:355`:
  "Discovery (PRD §8) is intentionally OMITTED."
- **Required:** Parse `list-keys -T root` and `-T prefix`, classify keys by command
  substring, drop plain letters/digits, exclude mouse keys, de-duplicate, exclude
  fixed control keys.

### Gap 3: Window-cursor state (absent)
- **Required:** 4 new state keys: `@livepicker-cand-win-session`, `-list`, `-cursor`,
  `@livepicker-preview-win-id`. None exist in `state.sh`.

### Gap 4: Window-flip actions (absent)
- **Current:** `input-handler.sh` has no `next-window`/`prev-window` case branches.
- **Required:** Add both actions. Advance cursor within candidate's window list,
  re-link chosen window into driver (deferred), never select-window on candidate.

### Gap 5: Preview shows chosen window (absent)
- **Current:** `preview.sh` always resolves `#{window_active}`. `$2` is the supersede seq.
- **Required:** Accept chosen window-id as arg. Signature becomes `<session> [window-id] [seq]`.

### Gap 6: Confirm lands on (session, window) (absent)
- **Current:** Session-mode confirm only `switch-client`s. No window commit.
- **Required:** Resolve W from cursor, `select-window -t "=$S:$W"`, then `switch-client`.

### Gap 7: Restore keep skips ORIG_WINDOW (bug)
- **Current:** `restore.sh` STEP 2 re-selects ORIG_WINDOW for `keep` mode.
- **Required:** Both `keep` and `keep-window` skip; only `cancel` re-selects.

### Gap 8: Pane immutability hardening (§23)
- **Current:** Unconditional `select-layout` in STEP 5. Candidate windows not pinned.
- **Required:** Drift-gated restore (only select-layout if pane geometry changed).
  Candidate-window pinning at link time (conditional on verification).

## Confirmed user key bindings (live tmux 3.6b)

### Window axis (discovered)
| Key | Table | Command | Direction |
|-----|-------|---------|-----------|
| `C-M-Tab` | root | `swap-window -t +1 \; select-window -t +1` | next |
| `C-M-BTab` | root | `swap-window -t -1 \; select-window -t -1` | prev |
| `M-n` | root | `select-window -n` | next |
| `M-p` | root | `select-window -p` | prev |
| `M-n` | prefix | `next-window -a` | next |
| `M-p` | prefix | `previous-window -a` | prev |
| `C-n` | prefix | `next-window` | next |
| `C-p` | prefix | `previous-window` | prev |
| `C-l` | prefix | `select-window -n` | next |
| `C-h` | prefix | `select-window -p` | prev |

Plain `n`/`p` in prefix table are **dropped** (alphanumeric, reserved for typing).

### Session axis (discovered)
| Key | Table | Command | Direction |
|-----|-------|---------|-----------|
| `)` | prefix | `switch-client -n` | next |
| `(` | prefix | `switch-client -p` | prev |

Plus universal arrow extras: `Down` (next), `Up` (prev).

### Mouse keys (MUST be excluded from discovery)
| Key | Table | Contains | Why exclude |
|-----|-------|----------|-------------|
| `WheelDownStatus` | root | `next-window` | Mouse wheel, not keyboard |
| `WheelUpStatus` | root | `previous-window` | Mouse wheel |
| `MouseDown3StatusLeft` | root | `switch-client -n` inside `display-menu` | Context menu, not direct nav |
| `M-MouseDown3StatusLeft` | root | same | Modified context menu |
| `MouseDown1Status` | root | `switch-client -t =` | Status bar click |

Discovery MUST: (a) match only the top-level command token (not substrings inside
`display-menu` blocks), and (b) exclude keys matching `Mouse*`/`Wheel*`.

## Expected discovery output (verified)
- Window next: `C-M-Tab M-n C-n C-l` (dedup M-n from root+prefix)
- Window prev: `C-M-BTab M-p C-p C-h` (dedup M-p from root+prefix)
- Session next: `) Down`
- Session prev: `( Up`

## Empirical verifications performed

### 1. Window-id addressing at confirm
**Test:** `select-window -t "=test_sess:@1"` on isolated socket.
**Result:** rc=0, correct window selected. **`=$S:@id` form works on 3.6b.**

### 2. Candidate pane immutability (detached)
**Test:** Link candidate window into driver, compare pane geometry.
**Result:** No change in either arm (linked or frozen). **NOTE:** sessions created
with `-x/-y` are size-locked and do NOT reproduce the shared-window resize
(confirmed by `clip_verification.md`). Real-client verification required (P3.M1.T1).

### 3. Clip recipe (from clip_verification.md §2-3, already proven)
- `window-size manual` ALONE does NOT pin (window reflowed 23→22).
- `window-size manual` + `resize-window -y <pre-grow-height>` pins byte-identical.
- Per-session (`-t`) isolation confirmed.
- Linked-candidate residual: one-time link-time resize + source view disturbance
  (shared window). This IS the gap P3 closes.

## File inventory (scripts/ — 3117 lines)

| File | Lines | Role | Delta changes |
|------|-------|------|---------------|
| `options.sh` | 54 | Option accessors | Remove 4 old nav accessors, add 4 two-axis |
| `utils.sh` | 187 | tmux helpers | Add `lp_discover_axis_keys` |
| `state.sh` | 164 | State contract | Add 4 window-cursor keys + pane-geometry snapshot |
| `livepicker.sh` | 505 | Activate orchestrator | Rework T4 binds, add cursor init, add pane snapshot |
| `input-handler.sh` | 591 | Input dispatch | Add next-window/prev-window, rework confirm, cursor resets |
| `preview.sh` | 264 | Live preview core | Accept chosen window-id, self-session flip |
| `restore.sh` | 259 | Teardown | keep skips STEP-2, drift-gated STEP-5, candidate pin restore |
| `renderer.sh` | 280 | Status renderer | No changes |
| `rank.sh` | 174 | Fuzzy ranker | No changes |
| `layout.sh` | 179 | Viewport math | No changes |
| `session-mgmt.sh` | 418 | Rename/delete | No changes |
