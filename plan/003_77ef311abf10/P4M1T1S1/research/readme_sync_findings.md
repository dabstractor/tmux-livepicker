# README.md changeset sync (P4.M1.T1.S1) — research synthesis

> TL;DR for the PRP author. This is a documentation-only task (Mode B). It edits
> ONE file: `README.md`. The deliverable is four prose changes (status line,
> session management, appearance viewport, limitation reconciliation) PLUS folding
> the scattered per-feature config rows into coherent prose, removing stale
> references, and passing the write-tech-docs lint. No code, no PRD, no CHANGELOG.

## 1. Current README structure (verified, line numbers)

```
  6  ## Overview
 18  ## Goals
 32  ## Non-goals
 40  ## User stories
 57  ## Installation
 88  ## Configuration            ← table (~L99-123) + prose
132    ### Appearance             ← (c) UPDATE here
136    ### Performance
140  ## Usage                     ← numbered steps 1-6 (rename/delete in step 6)
175  ## How it works
186    ### Known limitations      ← (d) REWRITE the "Detached candidate" bullet
197  ## Compatibility
215  ## Validation
234  ## Maintenance
```

The Configuration table is a flat Markdown table. Per-feature rows were appended
inline by P1.M1.T3.S1 (search-icon, query-gap, nerd-fonts, overflow-left,
overflow-right-format), P2.M1.T1.S1 (rename-key, delete-key, confirm-delete), and
P3.M1.T2.S1 (preview-fit). P4 FOLDS these into coherent prose sections so the
rows stop being an undifferentiated list.

## 2. Stale references that MUST be removed/fixed

| Where | Current text | Why stale | Fix |
|---|---|---|---|
| Table L117 | `\| @livepicker-show-count \| on \| Show index/total in the picker. \|` | `opt_show_count` + all SHOW_COUNT logic removed in P1.M2.T3.S1. PRD §19 kills the count entirely. | DELETE the whole row |
| Usage step 2 L147 | "type to filter the list (substring, case-insensitive)" | P1.M1.T1.S1 replaced substring filter with fuzzy `lp_rank` (subsequence + score). | Rewrite: fuzzy subsequence match, ranked best-first, non-matches hidden |
| User stories L48 ("Filter. I type log...") | "the list narrows to sessions whose names contain `log`" | substring wording | Rewrite to fuzzy/ranked wording |

Confirmed: `show-count` / `index/total` appears NOWHERE in the live code
(`grep -rn 'show-count\|show_count\|SHOW_COUNT' scripts/ tests/ plugin.tmux` is
empty). The only repo occurrence is README L117. So removing that row is the
entire stale-ref cleanup for the count. There is no other `index/total` prose.

## 3. The four deliverables mapped to exact PRD content

### (a) NEW "Status line" subsection (PRD §19 single source of truth + §20 + §3)

Line 1 is the same layout for BOTH `plain` and `window-status` tab styles (§19
governs both; PRD §17 diff). Must describe:

- **Query bar (icon + query):** the icon is `@livepicker-search-icon` (default
  U+F002 magnifier, raw UTF-8 bytes), shown only when `@livepicker-nerd-fonts on`
  (default on; tmux cannot detect the font, so it is opt-out). The query is the
  raw typed string with every `#` doubled so tmux renders it literally. The whole
  bar pins to the FAR LEFT and is shown ONLY while a query is non-empty. On open
  or after the query is cleared: no icon, no query, no gap, just the tabs
  justified per `status-justify`.
- **Gap:** exactly `@livepicker-query-gap` spaces (default 2) between the query
  and the first tab while a query is active.
- **Ranked tabs:** left-to-right, fuzzy-ranked by `lp_rank` (subsequence match;
  score prefix > word-boundary > contiguous > early-position; non-matches
  HIDDEN). Empty query = all sessions, tmux default order, score 0, no reorder.
- **Viewport + scroll:** tabs are windowed by `@livepicker-scroll`; typing /
  backspace / cancel-clear reset scroll to 0; next/prev scroll the highlight into
  view.
- **Overflow indicators:** right `+N>` where `N` = TOTAL hidden tabs
  (left+right combined, not split; default `@livepicker-overflow-right-format`
  `+%d>`); left `<` (presence only, when scroll > 0; default
  `@livepicker-overflow-left`). Both can show at once (`< …tabs… +N>`); neither
  shows when everything fits.
- **No count:** the index/total count is gone entirely (no count anywhere).
- **No-match state:** `<icon><query> (no match)`; create-on-Enter still applies.
- **justify suspended while typing:** with a query active, `status-justify` is
  suspended (the pinned query + left-to-right flow are required for the viewport).
  `status-justify` is honored only when there is no query AND the tabs fit.

### (b) NEW "Session management" note (PRD §21 + §3)

- **Rename:** `@livepicker-rename-key` (default `C-r`). Opens tmux's
  `command-prompt` pre-filled with the current name; on submit `rename-session`,
  rewrites the list, keeps the highlight on the renamed session, picker stays
  open. Control key, never collides with typing. Mirrors sessionx
  `@sessionx-bind-rename-session`.
- **Delete:** `@livepicker-delete-key` (default `M-BSpace`). Kills the
  highlighted session. Mirrors sessionx `@sessionx-bind-kill-session`.
- **Delete guards:** refused (with a display-message, no kill) for (1) the driver
  session you launched the picker from (killing it detaches your client and
  destroys the picker host), and (2) the last remaining session (tmux needs one).
- **Optional confirm:** `@livepicker-confirm-delete on` for a `y/n`
  `confirm-before` prompt; default `off` = immediate, sessionx-style.
- **Delete-key terminal caveat:** a few older terminals or SSH/mosh links strip
  Alt-modified keys entirely; if `M-BSpace` does not fire there, rebind
  `@livepicker-delete-key` to `C-h` or `DC` (Delete). PRD §21 calls this out and
  says to note it in the README.
- **Escaping limitation:** names containing `'`, `"`, `` ` ``, or `$` may break
  the rename prompt's `%%` substitution inside the single-quoted `run-shell`.
  tmux also rejects `:` and sanitizes leading `.` / `:`. Session names rarely
  contain these; known limitation.
- **Window mode:** rename/delete operate on the highlighted window analogously.

### (c) UPDATE Appearance (PRD §17 + §19)

The existing `### Appearance` paragraph (L132-134) explains the window-status
format hijack. ADD that the §19 viewport governs window-status tabs too: with a
query active, the query is pinned left, tabs flow left-to-right, and the overflow
indicators apply; `status-justify` is honored only when there is no query and the
tabs fit. Both `plain` and `window-status` tab styles use the same line-1 layout
(query bar, viewport, overflow). One source of truth (§19), two render styles.

### (d) REWRITE "Detached candidate" limitation (PRD §22 + clip_verification §4 + empirical Finding 2)

The current limitation bullet (L188-195) is the bugfix-001 note and conflates two
distinct effects. Reconcile into TWO clearly separated statements:

1. **Status-grow reflow (NOW FIXED).** When the status bar grows from one line to
   two, the preview's panes used to shrink one row (the visible jank on open).
   With the default `@livepicker-preview-fit clip`, the preview height is frozen
   before the status grows and the bottom row is clipped instead, so no pane
   reflows. Set `@livepicker-preview-fit reflow` to opt back into the old
   one-row reflow if clip misbehaves on your tmux/terminal.
2. **Link-time resize of a detached candidate (PERSISTS).** Navigating to a
   detached candidate links its window into the driver and resizes it once to the
   driver's size; because a linked window is a single shared object, the
   candidate's OWN session also sees the new size, and it persists after the
   picker exits. Clip does not eliminate this. Set `@livepicker-preview-mode
   snapshot` to avoid any candidate resizing (uses `capture-pane`, never links).

Evidence: clip_verification.md §2 (treatment byte-identical layout across the
grow; manual alone FAILS, the `resize-window -y H0` pin is load-bearing) and §4
(linked candidate: one-time link-time resize 40->22, byte-identical on re-link =
no per-nav reflow, source view also resized = shared window). empirical_findings.md
Finding 2 named this the bugfix-001 "Detached candidate resize" limitation; §22 +
clip_verification supersede Finding 2 for the freeze question.

## 4. Overlap with the PARALLEL P3.M1.T2.S1 (handle gracefully)

P3.M1.T2.S1 (implementing in parallel) ALSO touches README.md, per its PRP Task 6:
- ADDS the `@livepicker-preview-fit` table row (after `@livepicker-preview-defer`).
- ADDS a TIGHT "Detached candidate" limitation reconciliation, explicitly marked
  "Keep it tight; full prose is deferred to P4."

So when P4 runs, the preview-fit row + a tight limitation note may ALREADY be
present. P4's contract for (d) is to write the FULL prose (expand P3's tight
note). For the preview-fit row: ENSURE it is present (do not duplicate if P3
already added it). Both are idempotent: read README fully first, then make the
final text correct and coherent regardless of whether P3's inline edits landed.
Do NOT assume the row/note are missing; do NOT assume they are present. Read and
reconcile.

P3.M1.T2.S1 does NOT touch CHANGELOG.md and does NOT write the status-line /
session-management / appearance sections. Those are P4-only.

## 5. write-tech-docs style gate (MANDATORY)

Load `/home/dustin/.pi/agent/skills/write-tech-docs/SKILL.md`. Hard rules:
1. NO em dashes (U+2014) anywhere. Use colon, parentheses, comma, or period. The
   linter bans `—` and ` -- ` outright.
2. No marketing tell-words (powerful, robust, elegant, seamless, comprehensive,
   leverage, utilize, unlock, streamline, etc.).
3. No hedging/formulaic transitions (moreover, furthermore, "it's worth noting").
4. Do not narrate the codebase; document what, why, how-to, gotchas.
5. No prose paragraph over 100 words.

Linter: `bash /home/dustin/.pi/agent/skills/write-tech-docs/scripts/lint.sh
README.md`. It strips code blocks/inline code first, then checks em dashes,
tell-words, and >100-word paragraphs. MUST exit 0.

**Em-dash scope reality:** the EXISTING README is full of em dashes (L29, 52, 59,
67, 79, 142, 147, 149, 154, 157, 159, 176, 184, 189, 194, 200, ...). lint.sh runs
on the whole file, so a passing gate requires removing ALL of them. This is a
mechanical, low-risk conversion for this simple prose: replace `—` with a colon
(when the dash introduces a clause), parentheses (when it's parenthetical), or a
period/comma. The task explicitly says "follow the write-tech-docs skill style,"
so the full-file sweep IS in scope. All NEW prose must also be em-dash-free.

## 6. Placement decisions (recommendations; read README fully first)

- (a) `### Status line` — new subsection. Best as a `###` under `## Configuration`
  (after `### Performance`, ~L138), OR a standalone `## Status line` between
  Configuration and Usage. It describes configurable line-1 layout, so under
  Configuration fits. Recommend `### Status line` under Configuration.
- (b) `### Session management` — new subsection. Usage step 6 already has a brief
  rename/delete blurb. Recommend keeping a one-line pointer in Usage step 6 and
  adding `### Session management` under `## Usage` (after the numbered list) with
  the full rename/delete + guards + caveats. (Behavioral content belongs in
  Usage, not Configuration.)
- (c) Update the existing `### Appearance` paragraph in place (L132-134).
- (d) Rewrite the `### Known limitations` "Detached candidate" bullet in place
  (L188-195).

The new Status line + Session management + updated Appearance prose together ARE
the "cross-cutting overview": they reference the scattered config options
(search-icon/query-gap/overflow-*, tab-style, rename/delete/confirm-delete,
preview-fit/preview-mode) and explain how they compose. The table stays as the
reference; the prose gives the narrative.

## 7. Validation (docs task — no code tests)

- `bash /home/dustin/.pi/agent/skills/write-tech-docs/scripts/lint.sh README.md`
  exits 0 (em dashes, tell-words, paragraph length).
- `grep -n 'show-count\|index/total' README.md` is empty (no stale count refs).
- `grep -n 'substring' README.md` is empty (filter is now fuzzy).
- The four deliverables are present: `grep -n 'Status line\|Session management'`,
  the Appearance paragraph mentions the viewport/query-left/justify, the
  limitation note mentions `clip` AND distinguishes status-grow vs link-time.
- The `@livepicker-preview-fit` row is present exactly once.
- `bash tests/run.sh` still exits 0 (doc-only change must not break the suite; the
  README is not sourced by any test).
