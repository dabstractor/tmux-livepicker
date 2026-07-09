# P4.M1.T1.S2 research: CHANGELOG [Unreleased] entry

Synthesis of the facts the implementer needs. Read this FIRST; it is the TL;DR.

## 1. CHANGELOG.md format (verified by reading the file)

- Top of file: `# Changelog` heading + an intro paragraph referencing
  [Keep a Changelog](https://keepachangelog.com/). Do NOT touch these.
- Convention used by THIS repo: every changeset is its OWN
  `## [Unreleased]: <subtitle>` block (because no versioned tag exists yet).
  Newest block sits at the TOP (just under the intro); oldest at the BOTTOM.
  => The rev-003 entry is INSERTED between the intro paragraph and the existing
  `## [Unreleased]: theme-matched tabs and deferred preview` block.
- Subtitle separator: rev-002 uses a COLON (`## [Unreleased]: theme-matched ...`).
  rev-001 uses an EM DASH (`## [Unreleased] — Initial implementation`). The task
  mandates write-tech-docs style = NO em dashes, so USE THE COLON FORM for the
  new header. (The rev-001 em dash is swept as part of the file-wide pass, §5.)
- Standard section sub-headers seen: `### Added`, `### Fixed`,
  `### Documented corrections`, `### Notes for maintainers`. A pure-feature
  changeset uses `### Added`.
- STRUCTURAL TEMPLATE = the rev-002 `### Added` block. It is the closest analog
  (lists feature OPTIONS + an invariants bullet + an escape-hatches bullet).
  Mirror its shape: one `### Added` bullet per feature group, each starting with
  a **bold option/feature name**, its default, a PRD section ref, then what it
  does; then ONE bullet stating the invariants are unchanged; then ONE bullet
  stating the escape hatches remain. See §3/§4 for the exact content.
- Bullet tone: evidence-first, dense, active voice. Each feature bullet names the
  option, the default, the PRD section, the mechanism in one or two sentences,
  and the user-visible effect. Match the rev-002 density.

## 2. The four feature groups to list (PRD §19/§20/§21/§22 + plan P1/P2/P3)

1. **Fuzzy ranking** (P1.M1.T1; PRD §20). New `lp_rank` in `scripts/rank.sh`
   (sources the retired `scripts/filter.sh` pattern; filter.sh is GONE, replaced
   at all 6 call sites). Match rule = SUBSEQUENCE (every query char appears in
   the name in order, case-insensitive, not necessarily contiguous); non-matches
   are HIDDEN. Score = prefix bonus (large) > word-boundary bonus >
   contiguity bonus > position penalty; stable tie-break on original tmux order.
   Empty query = all names at score 0 in tmux order (NO reordering, preserves the
   §2 no-MRU/non-goal). Replaces the old case-insensitive SUBSTRING filter.
2. **Scrollable status-line layout** (P1.M2 + P1.M3; PRD §19). Line 1 is now a
   query bar + a scrollable tab viewport, and the `index/total` COUNT is REMOVED
   entirely. Query bar = icon (`@livepicker-search-icon`, U+F002 magnifier, only
   when `@livepicker-nerd-fonts` on) + query, pinned far-left, shown ONLY while a
   query is non-empty; `@livepicker-query-gap` spaces (default 2). Tabs flow
   left-to-right, windowed by `@livepicker-scroll`; scroll resets on type/backspace/
   cancel-clear and scrolls the highlight into view on next/prev. Overflow
   indicators: right `+N>` where N = TOTAL hidden tabs (`@livepicker-overflow-right-format`
   `+%d>`), left `<` presence-only (`@livepicker-overflow-left`); both can show,
   neither when tabs fit. No-match state `<icon><query> (no match)`. status-justify
   is suspended while a query is active. Width source = `@livepicker-client-width`
   cached at activate (no per-keystroke tmux round-trip; §18 budget), refreshed by
   a `client-resized` hook for the duration. New lib `scripts/layout.sh` (`lp_viewport`
   display-width + scroll math), sourced by renderer + input-handler.
3. **Session management** (P2; PRD §21). Rename via `@livepicker-rename-key`
   (default `C-r`): opens tmux's `command-prompt` pre-filled with the current
   name; `session-mgmt.sh do-rename` runs `rename-session`, guards the sanitized
   vs typed name and collisions, keeps the highlight on the renamed session
   (preview window id unchanged). Delete via `@livepicker-delete-key` (default
   `M-BSpace`): guards refuse the driver session and the last session;
   unlink-first then kill-session; rebuilds the list, clamps index, re-syncs the
   preview. `@livepicker-confirm-delete` (default `off`) = sessionx-style
   immediate; `on` = `confirm-before` y/n. Both keys are control keys so they
   never collide with the typing set. Window mode parity. New script
   `scripts/session-mgmt.sh`.
4. **Preview clip** (P3; PRD §22 + architecture/clip_verification.md). New
   `@livepicker-preview-fit` (default `clip`). Freezes the preview window's
   height BEFORE the status bar grows from 1 to 2 lines, so panes do NOT reflow
   (the bottom row is clipped instead; kills the visible status-grow jank).
   Mechanism (per clip_verification §1/§2/§3, load-bearing): save the driver's
   `window-size` to `@livepicker-orig-window-size`, `set-option -t <sess>
   window-size manual`, then `resize-window -y <pre-grow-height>` (the resize pin
   is what actually kills the jank; `manual` ALONE is insufficient). Restored on
   exit (status shrunk first, then window-size restored). `reflow` is the legacy
   escape hatch.

## 3. Defaults (verified in scripts/options.sh)

preview-fit = `clip`; preview-defer = `on`; tab-style = `plain`; nerd-fonts =
`on`; confirm-delete = `off`; preview-mode = `live`. These are the defaults to
state. None of the four features changes the others' default.

## 4. Invariants that MUST be stated as unchanged (PRD §14 + scripts/state.sh)

- Browsing fires NO `client-session-changed`: the preview still uses
  `link-window`/`select-window`, never `switch-client`. The only switch is the
  single confirm-time `switch-client` (so the tmux-session-history timeline and
  the `@session-history-prev` toggle are untouched while browsing).
- `clear_all_state` still tears down EVERYTHING on exit, INCLUDING the new keys:
  `@livepicker-scroll` and `@livepicker-client-width` are members of
  `_STATE_RUNTIME_KEYS` (cleared explicitly); `@livepicker-orig-window-size` and
  `@livepicker-orig-client-resized` are cleared by clear_all_state's
  `@livepicker-orig-` grep (auto). Verified in scripts/state.sh lines 50-67.
- Exactly one `switch-client` at confirm (unchanged).

## 5. Escape hatches that REMAIN (state each)

- `reflow` — set `@livepicker-preview-fit reflow` for the legacy one-row reflow
  (if `clip` misbehaves on a given tmux/terminal).
- `plain` — set `@livepicker-tab-style plain` (the shipped default) instead of
  `window-status` theme reuse.
- `preview-defer off` — set `@livepicker-preview-defer off` to restore the
  synchronous preview path.
- `snapshot` — set `@livepicker-preview-mode snapshot` to preview with
  `capture-pane` (never links/resizes a candidate window; the zero-disturbance
  escape).

## 6. write-tech-docs lint gate — CORRECT PATH + exact rules

- The sibling P4.M1.T1.S1 PRP cites `/home/dustin/.pi/agent/skills/write-tech-docs/scripts/lint.sh`.
  THAT PATH DOES NOT EXIST (only `agent-browser` and `mdsel` are installed under
  `~/.pi/agent/skills/`). Do NOT rely on it.
- The real script is:
  `/home/dustin/projects/writing-skills/skills/write-tech-docs/scripts/lint.sh`
  (also mirrored at `.claude/skills/write-tech-docs/scripts/lint.sh` in the same
  tree). Run: `bash <that path> CHANGELOG.md`. MUST exit 0 (`lint: 0 hit(s)`).
- What lint.sh checks (read the script; it strips fenced + inline code first):
  1. Em dashes (U+2014) OR ` -- ` — banned outright.
  2. Tell-words (case-insensitive whole word): powerful, robust, elegant,
     seamless/seamlessly, comprehensive, cutting-edge, state-of-the-art,
     revolutionary, game-changing, next-generation, blazing-fast, lightning-fast,
     intuitive, effortless, frictionless, ultimate, stunning, beautiful,
     incredible, leverage, utilize, unlock, empower, supercharge, revolutionize,
     streamline, elevate, delve, tapestry, realm, landscape, moreover,
     furthermore, truly, incredibly.
  3. Prose paragraphs over 100 words (skips headings, lists, tables, quotes).
- CURRENT em-dash hits in CHANGELOG.md (U+2014), file-wide — ALL must go for
  lint to pass (lint is file-wide): lines 17, 23, 32, 35, 43, 52, 61, 71, 75, 78
  (the `## [Unreleased] — Initial implementation` header), 102, 107, 111, 116,
  125, 133, 140, 149, 150. (~19 lines.) Plus one EN dash (U+2013) at line 84
  (`P1.M1–M7`); lint does NOT flag en dashes, so it is OPTIONAL to convert to
  `P1.M1 to M7`.
- SWEEP RULE: punctuation-only, meaning-preserving. Replace each em dash with a
  colon (clause intro), parentheses (parenthetical), or comma/period per context.
  Never substitute ` -- ` (also banned) or a bare hyphen. Keep all option names,
  commands, and `+N>` / `<` literals inside `code` spans (lint strips code, so
  they are never flagged). This sweep is exactly analogous to the README sweep in
  the sibling P4.M1.T1.S1 task.
- Robust fallback if the script path is unreachable: a self-contained grep that
  replicates rule 1+2 (rule 3 is covered by keeping paragraphs as short prose +
  bullets): `grep -nP '\x{2014}| -- ' CHANGELOG.md` must be empty; and
  `grep -niEw '<the tell-word list>' CHANGELOG.md` must be empty. Keep every
  prose paragraph under ~100 words / ~4 sentences (use bullets).

## 7. Test count (only if a validation note is added)

`tests/run.sh` prints `"$passed passed, $failed failed (of $total)"`. After
rev-002 the suite was 44/44; this changeset ADDS test files
(test_layout.sh, test_ranking.sh, test_scroll_width.sh, test_session_mgmt.sh,
test_preview_clip.sh), and there are currently 91 `test_*` functions across
tests/. The rev-002 Added block did NOT cite a count (only its bugfix block did),
so a count is OPTIONAL here. If cited, run `bash tests/run.sh` and record the
REAL number (floor 44; currently ~91). Do NOT hardcode a stale number.

## 8. Parallel-execution context

P4.M1.T1.S1 (README sync) is implemented in parallel. It does NOT touch
CHANGELOG.md (it owns README only; P4.T1.S2 owns CHANGELOG). So there is NO file
conflict. The CHANGELOG entry must be SELF-CONTAINED per the task contract (4
features + defaults + invariants + escape hatches); do not hard-depend on the
README's in-flight state.
