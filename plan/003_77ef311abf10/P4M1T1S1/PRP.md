name: "P4.M1.T1.S1 — README.md changeset sync (status line, session mgmt, appearance viewport, limitation reconcile)"
description: |

  Documentation-only task (Mode B). Edits ONE file: `README.md`. No code, no
  PRD, no CHANGELOG (P4.T1.S2 owns the CHANGELOG entry). The four implemented
  features (P1 rank/layout/scroll, P2 session management, P3 clip, plus the
  already-shipped §17 tab appearance and §18 deferred preview) are scattered
  across a flat Configuration table and partial prose. This task FOLDS them into
  coherent, cross-cutting prose and removes stale references, following the
  write-tech-docs skill style. Concretely: (a) add a `### Status line` subsection
  (query bar far-left only while typing; fuzzy-ranked tabs left-to-right; scroll
  viewport + `+N>` total-hidden / `<` presence overflow indicators; index/total
  count gone); (b) add a `### Session management` note (rename C-r pre-filled
  prompt; delete M-BSpace with driver/last-session guards + optional
  confirm-delete; the M-BSpace terminal/SSH/mosh caveat + C-h/DC rebind; the
  rename escaping limitation); (c) update `### Appearance` so the §19 viewport is
  named as governing window-status tabs too (query pinned left, tabs
  left-to-right, overflow indicators, status-justify only when no query + tabs
  fit); (d) rewrite the "Detached candidate" limitation to reconcile bugfix-001
  with §22 clip (status-grow reflow now fixed by clip; link-time resize of a
  detached candidate persists, use snapshot). Plus remove the stale
  `@livepicker-show-count` row, fix the substring->fuzzy wording, ensure the
  `@livepicker-preview-fit` row is present once, and pass the write-tech-docs
  lint. P3.M1.T2.S1 (parallel) adds the preview-fit row + a TIGHT limitation note
  inline; this task writes the FULL prose and dedupes idempotently.

---

## Goal

**Feature Goal**: `README.md` accurately and coherently documents the four shipped
changesets (P1 rank/layout/scroll, P2 rename/delete, P3 clip, plus §17/§18) as a
single cross-cutting narrative, with no stale references, in the write-tech-docs
style.

**Deliverable**: An edited `README.md` containing:
1. A new `### Status line` subsection (the §19 line-1 layout: query bar, fuzzy
   tabs, viewport, overflow indicators, no count).
2. A new `### Session management` subsection (PRD §21: rename, delete, guards,
   confirm-delete, terminal caveat, escaping limitation).
3. An updated `### Appearance` paragraph naming the §19 viewport as governing
   `window-status` tabs too.
4. A rewritten "Detached candidate" limitation reconciled with §22 clip.
5. The stale `@livepicker-show-count` row removed and the substring filter
   wording corrected to fuzzy; the `@livepicker-preview-fit` row present once.
6. The whole file passing the write-tech-docs linter (no em dashes, no
   tell-words, no over-long paragraphs).

**Success Definition**: A reader who knows nothing about the codebase can, from
the README alone, describe the status-line layout (query bar behavior, fuzzy
ranking, overflow indicators, no count), the rename/delete keys and their guards
and caveats, that window-status tabs obey the same viewport, and the two distinct
preview-sizing effects (status-grow now clipped vs link-time resize that
persists). `bash <skill>/scripts/lint.sh README.md` exits 0. `bash tests/run.sh`
still exits 0 (doc-only change). No `show-count` / `index/total` / `substring`
references remain.

## User Persona (if applicable)

**Target User**: A tmux user evaluating or configuring tmux-livepicker, and the
maintainer who will later write the CHANGELOG (P4.T1.S2) from this README.

**Use Case**: Read the Configuration + Status line + Session management sections
to understand what the picker shows on the status line, how to rename/delete
sessions, and what the preview-sizing options do, without reading the PRD or the
shell scripts.

**User Journey**: Install -> read Configuration table for the option list -> read
Status line / Appearance to understand the on-screen layout -> read Session
management to learn rename/delete and their caveats -> read Known limitations to
understand the preview-sizing tradeoffs and escape hatches.

**Pain Points Addressed**: The current README has a flat, scattered table (no
narrative tying the layout options together), a stale `show-count` row, a stale
substring-filter description, a conflate-the-two-effects limitation note, and no
status-line or session-management sections at all.

## Why

- The four features shipped (P1, P2, P3, §17, §18) are real but undocumented as a
  coherent whole. A user reading the README today would not learn the query bar /
  viewport / overflow layout, the rename/delete keys, or that the status-grow
  reflow is now fixed by clip.
- The `@livepicker-show-count` row and the substring-filter wording are actively
  wrong (the count was removed in P1.M2.T3.S1; the filter became fuzzy in
  P1.M1.T1.S1). Stale docs erode trust in the rest of the README.
- This is the single Mode-B documentation sync for the 003 changeset; the
  CHANGELOG (P4.T1.S2) is written from this README afterward.

## What

User-visible: the README gains two new subsections, one updated paragraph, one
rewritten limitation, loses a stale row and stale wording, and passes the lint.
No behavioral change to the plugin.

### Success Criteria

- [ ] `### Status line` subsection exists and describes: icon + query pinned
  far-left shown only while typing (query empty = just tabs); fuzzy-ranked tabs
  left-to-right; viewport windowed by scroll; right `+N>` total-hidden indicator
  and left `<` presence indicator (both can show; neither when tabs fit); the
  index/total count is gone; no-match state; status-justify suspended while a
  query is active.
- [ ] `### Session management` subsection exists and covers: rename C-r
  (command-prompt pre-filled); delete M-BSpace with driver/last-session guards;
  optional confirm-delete; the M-BSpace terminal/SSH/mosh caveat + C-h/DC rebind;
  the rename escaping limitation (quotes/backtick/dollar); window mode parity.
- [ ] `### Appearance` paragraph names the §19 viewport as governing window-status
  tabs (query pinned left, tabs left-to-right, overflow indicators, status-justify
  only when no query + tabs fit; same layout for plain and window-status).
- [ ] The "Detached candidate" limitation is rewritten to distinguish status-grow
  reflow (now fixed by default `clip`) from link-time resize of a detached
  candidate (persists; use `snapshot`), and names `reflow` as the escape hatch.
- [ ] The `@livepicker-show-count` table row is gone; no `index/total` text
  remains anywhere.
- [ ] The filter wording says fuzzy/subsequence/ranked, not substring.
- [ ] The `@livepicker-preview-fit` row is present exactly once (clip default,
  reflow escape hatch).
- [ ] `bash /home/dustin/.pi/agent/skills/write-tech-docs/scripts/lint.sh
  README.md` exits 0.

## All Needed Context

### Context Completeness Check

_"If someone knew nothing about this codebase, would they have everything needed
to implement this successfully?"_ — Yes. This PRP pins the current README
structure (line numbers), every stale reference and its fix, the exact content
each new/edited section must contain (quoted from the PRD sections that govern
it), the lint rules and the em-dash-scope decision, the parallel P3.M1.T2.S1
overlap and how to handle it idempotently, and the executable validation. No
guessing about what the features do is required; the PRD selectors are quoted in
the task brief and the research synthesis restates the load-bearing facts.

### Documentation & References

```yaml
# MUST READ — load into your context window before editing.

- file: README.md
  why: THE file being edited. Read it fully first (the item description requires
        this). Note the current structure (## sections + ### subsections), the
        Configuration table (flat, scattered per-feature rows), the stale
        @livepicker-show-count row (~L117), the substring filter wording
        (Usage step 2 ~L147 + User stories Filter bullet ~L48), the ### Appearance
        paragraph (~L132), and the ### Known limitations "Detached candidate"
        bullet (~L188).
  pattern: "edit in place; keep the table as the option reference; add ### prose
        subsections that fold the rows into a narrative; do NOT rewrite untouched
        sections wholesale (only de-em-dash them)."

- file: /home/dustin/.pi/agent/skills/write-tech-docs/SKILL.md
  why: THE style contract. Hard rules: no em dashes (U+2014) or ' -- '; no
        tell-words (powerful/robust/seamless/leverage/utilize/streamline/...); no
        hedging (moreover/furthermore/it's worth noting); no narrating the
        codebase; no prose paragraph over ~100 words. Imperative for steps,
        second person for guides, active voice, one idea per sentence.
  critical: "rule #1 (no em dashes) is enforced file-wide by lint.sh. The existing
        README is full of em dashes; the full-file sweep is in scope. Replace each
        with a colon (clause intro), parentheses (parenthetical), or period/comma."

- file: /home/dustin/.pi/agent/skills/write-tech-docs/scripts/lint.sh
  why: THE gate. Run `bash <this> README.md`. It strips fenced + inline code, then
        fails on em dashes / ' -- ', the tell-word list (case-insensitive whole
        word), and >100-word prose paragraphs (skips headings/lists/tables/quotes).
        MUST exit 0.
  pattern: "bash /home/dustin/.pi/agent/skills/write-tech-docs/scripts/lint.sh README.md"

- file: PRD.md   # READ-ONLY; do NOT edit
  why: the authoritative source for each section's content. The selectors quoted
        in the task brief are: §1 Overview, §2 Goals/non-goals, §3 User stories,
        §11 Configuration options (the full options table), §17 Tab appearance,
        §19 Status-line layout (the SINGLE SOURCE OF TRUTH for line 1), §21 Session
        management, §22 Preview sizing (clip vs reflow). Mine §19/§20/§21/§22 for
        the exact wording of the status-line / session-mgmt / limitation prose.

- file: plan/003_77ef311abf10/P4M1T1S1/research/readme_sync_findings.md
  why: THIS task's synthesis. The four deliverables mapped to exact PRD content,
        the stale-reference table, the clip-reconciliation facts, the lint/em-dash
        scope decision, the P3.M1.T2.S1 overlap handling, and placement
        recommendations. Read FIRST; it is the TL;DR.

- file: plan/003_77ef311abf10/architecture/clip_verification.md
  why: THE evidence for the limitation reconciliation (deliverable d). §2
        treatment = byte-identical layout across the status grow (clip works;
        manual ALONE fails; the resize-window -y H0 pin is load-bearing). §4 =
        the linked-candidate residual (one-time link-time resize 40->22;
        byte-identical on re-link = no per-nav reflow; source view also resized =
        shared window). Use these facts to write the two-effect distinction.
  section: "§2 the treatment (clip works); §4 the residual (link-time persists)."

- file: plan/003_77ef311abf10/architecture/empirical_findings.md
  why: Finding 2 named the bugfix-001 'Detached candidate resize' limitation.
        clip_verification.md supersedes Finding 2 for the freeze question (manual
        alone is too optimistic). Read Finding 2 to see the link-time-resize
        framing, then reconcile per clip_verification §4. Do NOT cite Finding 2's
        'manual protects' claim as current (it was corrected).

- file: plan/003_77ef311abf10/P3M1T2S1/PRP.md   # READ-ONLY; PARALLEL sibling
  why: P3.M1.T2.S1 is implementing in parallel and ALSO edits README.md (its
        Task 6): it ADDS the @livepicker-preview-fit table row + a TIGHT
        limitation note ('full prose deferred to P4'). When you run, the row and a
        short note may ALREADY be present. Your job for (d) is to write the FULL
        prose; for the row, ENSURE it is present exactly once (dedupe). Idempotent:
        read README fully first, reconcile to the correct final text regardless.
  section: "Task 6 (README edit); note it does NOT touch CHANGELOG and does NOT
        write the status-line / session-management / appearance sections."

- file: scripts/options.sh   # READ-ONLY; the option set
  why: confirms the live option names + defaults so the table rows match the code.
        opt_show_count() is GONE (removed P1.M2.T3.S1) -> the row must be deleted.
        opt_preview_fit() (clip|reflow) is added by P3.M1.T2.S1 -> the row must be
        present. fuzzy ranking lives in scripts/rank.sh (lp_rank); the old
        scripts/filter.sh is RETIRED (removed P1.M1.T1.S2).
  pattern: "grep -c 'opt_' scripts/options.sh for the full accessor list; the table
        must list every option with an accessor and no retired option."

- url: https://github.com/tmux/tmux/blob/master/CHANGES
  why: only if you need to justify the tmux version floor (3.2) or window-size
        semantics in the limitation note. The README already states >=3.2 / tested
        on 3.6b; do not change it unless the clip note needs a version caveat
        (clip is verified on 3.6b; reflow is the documented fallback otherwise).
```

### Current Codebase tree (run `ls` + `grep -nE '^#{2,3} ' README.md`)

```bash
tmux-livepicker/
├── README.md                 # ← THE ONLY FILE EDITED BY THIS TASK (doc sync)
├── CHANGELOG.md              # READ-ONLY here (P4.T1.S2 owns the new entry)
├── PRD.md                    # READ-ONLY (never edit)
├── scripts/                  # READ-ONLY (options.sh = option set; rank.sh = fuzzy)
│   ├── options.sh            #   opt_*() accessors; opt_show_count GONE; opt_preview_fit added by P3
│   ├── rank.sh               #   lp_rank fuzzy subsequence + score (replaces the retired filter.sh)
│   ├── layout.sh             #   lp_viewport display-width + scroll math
│   ├── session-mgmt.sh       #   do-rename / do-delete (the rename escaping caveat lives here)
│   └── ...
├── tests/                    # READ-ONLY (run.sh must stay green; README not sourced by any test)
└── plan/003_77ef311abf10/
    ├── architecture/{clip_verification.md (the clip evidence), empirical_findings.md (Finding 2)}
    ├── P3M1T2S1/PRP.md       # parallel sibling that adds the preview-fit row + tight note
    └── P4M1T1S1/{PRP.md (THIS file), research/readme_sync_findings.md}
```

### Desired Codebase tree with files to be added and responsibility of file

```bash
# ONE file modified. Nothing else is created or modified by this task.
README.md   # EDIT in place: + ### Status line, + ### Session management,
            # ~ ### Appearance (viewport governs window-status tabs),
            # ~ ### Known limitations "Detached candidate" (reconciled with clip),
            # - @livepicker-show-count row, ~ substring -> fuzzy wording,
            # ~ ensure @livepicker-preview-fit row present once,
            # + full-file em-dash sweep so lint.sh exits 0.
```

### Known Gotchas of our codebase & the write-tech-docs skill

```bash
# CRITICAL (from the skill + the parallel-execution context):

# 1. Em dashes (U+2014) are BANNED file-wide by lint.sh. The existing README is
#    full of them (lines 29, 52, 59, 67, 79, 142, 147, 149, 154, 157, 159, 176,
#    184, 189, 194, 200, ...). lint.sh runs on the WHOLE file, so a passing gate
#    requires removing ALL of them, not just the ones in new prose. This sweep is
#    in scope ("follow the write-tech-docs skill style"). Mechanical + low-risk:
#    replace each with a colon (clause intro), parentheses (parenthetical), or a
#    period/comma. NEVER use ' -- ' (also banned) or a hyphen as a substitute.

# 2. lint.sh STRIPS fenced code blocks and inline code BEFORE checking, so option
#    names, commands, and `+N>` / `<` literals inside backticks are never flagged.
#    Keep option/indicator literals in `code` spans so they survive the lint.

# 3. The >100-word paragraph check skips headings, lists, tables, and blockquotes.
#    Write the new sections as short prose + bullets/tables, not long paragraphs.
#    Keep any single prose paragraph under ~4 sentences / 100 words.

# 4. P3.M1.T2.S1 (PARALLEL) edits README too: it adds the @livepicker-preview-fit
#    table row + a TIGHT 'Detached candidate' limitation note ('full prose
#    deferred to P4'). READ README fully before editing. If the row/note are
#    already present, do NOT duplicate them: expand P3's tight note into the full
#    prose (deliverable d) and keep exactly one preview-fit row. If they are NOT
#    yet present, add them yourself (the final README must contain them either way).
#    This is idempotent; reconcile to the correct final text regardless of P3's
#    timing. Do NOT touch CHANGELOG.md (P4.T1.S2 owns it).

# 5. The count is GONE in code (opt_show_count removed in P1.M2.T3.S1; PRD §19
#    removes index/total entirely). The ONLY repo occurrence of show-count /
#    index/total is README table row ~L117. Delete that row. Do not re-introduce
#    any index/total language anywhere.

# 6. The filter is FUZZY now (lp_rank in scripts/rank.sh; subsequence match +
#    score; filter.sh RETIRED in P1.M1.T1.S2). The README's 'substring,
#    case-insensitive' wording (Usage step 2 ~L147) and the User-stories 'names
#    contain log' bullet (~L48) are stale. Rewrite to fuzzy/subsequence/ranked.

# 7. Do NOT narrate the codebase (skill rule #4). Document what the status line
#    SHOWS, how to use rename/delete, what the preview-sizing options DO, and the
#    gotchas. Do not walk through scripts/ or restate the link-window mechanism
#    beyond what the existing 'How it works' section already says.

# 8. README is NOT sourced by any test. The doc edit cannot break tests/run.sh,
#    but run it anyway as a regression sanity check (Level 3).
```

## Implementation Blueprint

No data models. This task edits one Markdown file. The "structure" is four prose
edits plus a table cleanup plus a full-file em-dash sweep, in dependency order.

### Implementation Tasks (ordered by dependencies)

```yaml
Task 1: READ the cited context (NO writes)
  - READ: README.md FULLY (the item description requires a full read first). Note
        the structure (## / ### headings + line numbers), the Configuration table,
        the stale @livepicker-show-count row (~L117), the substring wording
        (Usage step 2 ~L147 + User-stories Filter bullet ~L48), the ### Appearance
        paragraph (~L132), the ### Known limitations "Detached candidate" bullet
        (~L188), and whether P3.M1.T2.S1's @livepicker-preview-fit row + tight
        limitation note are already present (parallel; reconcile, do not duplicate).
  - READ: /home/dustin/.pi/agent/skills/write-tech-docs/SKILL.md (the style rules).
  - READ: plan/003_77ef311abf10/P4M1T1S1/research/readme_sync_findings.md (this
        task's synthesis, FIRST).
  - READ: plan/003_77ef311abf10/architecture/clip_verification.md §2 + §4 (the
        clip evidence for the limitation reconciliation).
  - SKIM: PRD.md §19 + §20 + §21 + §22 + §17 + §11 (the authoritative content for
        the new prose). Mine the exact wording.
  - SKIM: scripts/options.sh (confirm the live option set: opt_show_count GONE,
        opt_preview_fit added by P3; rank.sh is fuzzy; filter.sh retired).
  - PURPOSE: internalize the four deliverables, the stale refs, the lint rules,
        and the P3 overlap. Do NOT edit PRD.md, CHANGELOG.md, or any script.

Task 2: REMOVE stale references
  - DELETE the @livepicker-show-count table row (the line starting
        `| \`@livepicker-show-count\``). It is the only repo occurrence of the
        count; PRD §19 + P1.M2.T3.S1 removed it. Confirm no index/total text
        remains: `grep -n 'index/total\|show-count' README.md` must be empty.
  - FIX the substring wording: Usage step 2 "type to filter the list (substring,
        case-insensitive)" -> fuzzy. State: type to filter the list; matching is a
        fuzzy subsequence match (characters in order, case-insensitive), results
        are ranked best-first (prefix > word-boundary > contiguous > early
        position), and non-matches are hidden. BSpace removes a character.
  - FIX the User-stories "Filter" bullet (~L48) "names contain log" -> fuzzy
        wording (e.g. typing narrows to sessions whose names fuzzy-match, best
        match first).
  - FOLLOW pattern: the existing bullets/steps tone; keep it one or two sentences.
  - GOTCHA: keep 'log' / example names inside `code` if used (lint strips inline
        code). Do not introduce index/total language.

Task 3: ENSURE the @livepicker-preview-fit row is present exactly once
  - IF P3.M1.T2.S1 already added it (after @livepicker-preview-defer), KEEP it and
        FOLD it into the prose (Task 4/7 reference it). IF absent, ADD it:
        `| \`@livepicker-preview-fit\` | \`clip\` | \`clip\` freezes the preview
        height before the status bar grows so panes do not reflow (the bottom row
        is clipped); \`reflow\` is the legacy one-row reflow. Use \`reflow\` if
        \`clip\` misbehaves on your tmux/terminal. |`
  - VERIFY: `grep -c '@livepicker-preview-fit' README.md` == 1 (the table row) +
        prose mentions as needed (the limitation note names it). Do not duplicate
        the row.
  - GOTCHA: the row must match the live default (clip) from options.sh
        (opt_preview_fit, added by P3). reflow is the escape hatch.

Task 4: ADD the "### Status line" subsection (deliverable a; PRD §19 + §20)
  - PLACE: a new `### Status line` subsection under `## Configuration`, after
        `### Performance` (~L138). (Recommended placement; the content describes
        the configurable line-1 layout. A standalone ## section between
        Configuration and Usage is also acceptable; pick one and be consistent.)
  - WRITE concise prose + a short bullets/table. Cover ALL of:
        * Query bar: the icon (@livepicker-search-icon, default magnifier U+F002,
          shown only when @livepicker-nerd-fonts is on; tmux cannot detect the
          font so it is opt-out) plus the query, pinned to the far left, shown
          ONLY while a query is non-empty. On open or after the query is cleared:
          no icon, no query, no gap, just the session tabs.
        * Gap: exactly @livepicker-query-gap spaces (default 2) between the query
          and the first tab while a query is active.
        * Tabs: left-to-right, fuzzy-ranked (subsequence match, scored best-first,
          non-matches hidden). Empty query = all sessions in tmux default order.
        * Viewport: tabs are windowed by scroll; typing/backspace/cancel-clear
          reset scroll to 0; next/prev scroll the highlight into view.
        * Overflow indicators: right `+N>` where N is the TOTAL hidden tabs
          (left + right combined, not split; @livepicker-overflow-right-format
          default `+%d>`); left `<` (presence only, when scroll > 0;
          @livepicker-overflow-left default `<`). Both can show at once
          (`< …tabs… +N>`); neither shows when everything fits.
        * No count: there is no index/total count anywhere.
        * No-match: `<icon><query> (no match)`; create-on-Enter still applies.
        * justify: with a query active, status-justify is suspended (the pinned
          query + left-to-right flow are required). status-justify is honored only
          when there is no query AND the tabs fit.
  - NAMING: subsection heading `### Status line`. Reference options by their
        `@livepicker-*` names in `code` spans.
  - FOLLOW pattern: the existing ### Appearance / ### Performance subsections
        (short prose, option references in code spans).
  - GOTCHA: do NOT duplicate content already in the Configuration table; this
        section is the narrative, the table is the reference. Cross-reference.

Task 5: ADD the "### Session management" subsection (deliverable b; PRD §21)
  - PLACE: a new `### Session management` subsection under `## Usage`, after the
        numbered steps (the rename/delete blurb is currently inside Usage step 6;
        keep a one-line pointer there and expand the detail here). (A ### under
        ## How it works is also acceptable; Usage is recommended since these are
        user actions.)
  - WRITE concise prose + bullets. Cover ALL of:
        * Rename: @livepicker-rename-key (default `C-r`). Opens tmux's
          command-prompt pre-filled with the current name; on submit renames the
          session, keeps the highlight on it, and the picker stays open. Control
          key, never collides with typing.
        * Delete: @livepicker-delete-key (default `M-BSpace`). Kills the
          highlighted session.
        * Delete guards: refused (with a display-message, no kill) for the driver
          session you launched the picker from (killing it detaches your client
          and destroys the picker host) and for the last remaining session (tmux
          requires at least one).
        * Confirm: @livepicker-confirm-delete `on` prompts y/n (confirm-before)
          before a kill; default `off` = immediate, sessionx-style.
        * Delete-key terminal caveat: a few older terminals or SSH/mosh links
          strip Alt-modified keys entirely; if `M-BSpace` does not fire there,
          rebind @livepicker-delete-key to `C-h` or `DC` (Delete).
        * Escaping limitation: session names containing a single quote, double
          quote, backtick, or dollar sign may break the rename prompt; tmux also
          rejects `:`. Session names rarely contain these; known limitation.
        * Window mode: with @livepicker-type `window`, rename/delete act on the
          highlighted window analogously.
  - NAMING: subsection heading `### Session management`. Reference keys/options in
        `code` spans.
  - FOLLOW pattern: the existing Usage numbered steps + the ### subsections tone.
  - GOTCHA: keep each item to one or two sentences; do not narrate session-mgmt.sh.

Task 6: UPDATE "### Appearance" (deliverable c; PRD §17 + §19)
  - EDIT the existing ### Appearance paragraph (~L132) IN PLACE. Keep the existing
        window-status-format explanation (sentinel window, swap placeholder, plain
        fallback). ADD that the §19 status-line layout governs window-status tabs
        too: with a query active the query is pinned left, tabs flow left-to-right,
        and the overflow indicators apply; status-justify is honored only when
        there is no query and the tabs fit. Both `plain` and `window-status` tab
        styles use the same line-1 layout (query bar, viewport, overflow); §19 is
        the single source of truth for both.
  - NAMING: keep the `### Appearance` heading.
  - GOTCHA: do not restate the full Status line content here; point to it. One
        source of truth (§19 / the Status line section), two render styles.

Task 7: REWRITE the "Detached candidate" limitation (deliverable d; PRD §22 + clip_verification §4)
  - EDIT the ### Known limitations "Detached candidate" bullet (~L188) IN PLACE.
        (If P3.M1.T2.S1 already wrote a TIGHT version, EXPAND it to the full prose
        here; if absent, write it fresh. Idempotent.)
  - WRITE the TWO distinct effects, clearly separated:
        (1) STATUS-GROW reflow (NOW FIXED): when the status bar grows from one
            line to two, the preview's panes used to shrink one row (the visible
            jank on open). With the default @livepicker-preview-fit `clip`, the
            preview height is frozen before the status grows and the bottom row is
            clipped instead, so no pane reflows. Set @livepicker-preview-fit
            `reflow` to opt back into the old one-row reflow if clip misbehaves on
            your tmux/terminal.
        (2) LINK-TIME resize of a detached candidate (PERSISTS): navigating to a
            detached candidate links its window into the driver and resizes it
            once to the driver's size; because a linked window is one shared
            object, the candidate's OWN session also sees the new size, and it
            persists after the picker exits. Clip does not eliminate this. Set
            @livepicker-preview-mode `snapshot` to avoid any candidate resizing
            (uses capture-pane and never links the window).
  - NAMING: keep the bullet's bold lead or split into two bullets; pick the
        clearer form. Reference options in `code` spans.
  - FOLLOW pattern: the existing limitation-bullet tone (evidence-first, no
        hedging). Cite the effect, not the probe internals.
  - GOTCHA: do NOT claim clip fixes the link-time resize (it does not). Do NOT
        cite empirical_findings.md Finding 2's 'manual protects the self-window'
        as current (clip_verification.md §1 corrected it: manual alone fails; the
        resize-window pin is load-bearing). The README states the user-visible
        outcome (no reflow with clip), not the recipe.

Task 8: EM-DASH SWEEP + TELL-WORD / PARAGRAPH pass (write-tech-docs gate)
  - SWEEP: remove every U+2014 em dash from README.md (the existing file is full
        of them; lint.sh is file-wide). Replace each with a colon (clause intro),
        parentheses (parenthetical), or a period/comma per context. NEVER use
        ' -- ' (also banned) or a bare hyphen as a stand-in dash. Suggested:
        grep for the byte: `grep -nP '\x{2014}' README.md`; fix each hit.
  - TELL-WORDS: grep for the skill's list (powerful, robust, elegant, seamless,
        comprehensive, leverage, utilize, unlock, streamline, elevate, moreover,
        furthermore, truly, incredibly, ...) and replace/cut. The existing README
        is mostly clean of these, but new prose must avoid them.
  - PARAGRAPHS: keep every prose paragraph under ~4 sentences / 100 words (lint
        skips headings/lists/tables/quotes). Split long paragraphs into bullets.
  - VERIFY: `bash /home/dustin/.pi/agent/skills/write-tech-docs/scripts/lint.sh
        README.md` exits 0. Fix every hit; re-run until clean.
  - GOTCHA: the sweep is mechanical but do not change MEANING. The conversion is
        punctuation-only. Keep all option names / commands / literals in `code`
        spans (lint strips them).

Task 9: VALIDATE (see Validation Loop) — lint + grep checks + render sanity + regression.
```

### Implementation Patterns & Key Details

```markdown
<!-- Pattern: a write-tech-docs subsection is short prose + bullets/table, every
     literal in a code span. Example shape for the Status line query-bar bullet: -->

* **Query bar.** A search icon (`@livepicker-search-icon`, a magnifier by default)
  followed by your query sits at the far left of line 1, but only while you are
  typing. On open, or after you clear the query, there is no icon, no query, and
  no gap: line 1 shows only the session tabs. The icon shows when
  `@livepicker-nerd-fonts` is `on` (the default); tmux cannot detect your font,
  so set it `off` if you see a missing-glyph box.

<!-- Pattern: the limitation reconciliation as two distinct bullets (deliverable d).
     State the effect and the escape hatch; do not narrate the freeze recipe. -->

* **Status-grow reflow is fixed by default.** Growing the status bar from one line
  to two used to shrink the preview's panes one row. With the default
  `@livepicker-preview-fit` `clip`, the preview height is frozen before the status
  grows and the bottom row is clipped instead, so no pane reflows. Set it `reflow`
  to get the old one-row shrink back if `clip` misbehaves on your tmux or terminal.
* **Detached candidates still resize once at link time.** When you navigate to a
  detached candidate, tmux links its window into the driver and resizes it once to
  the driver's size. A linked window is a single shared object, so the candidate's
  own session keeps that size after the picker exits. `clip` does not change this.
  Set `@livepicker-preview-mode` `snapshot` to preview with `capture-pane` and
  never link (and never resize) the candidate.

<!-- Anti-pattern: do NOT write the recipe ("set-option -t manual then
     resize-window -y H0"). The README documents the outcome and the escape
     hatch, not the mechanism. -->
```

### Integration Points

```yaml
README.md (the only integration surface):
  - Configuration table: DELETE the @livepicker-show-count row; ENSURE exactly one
        @livepicker-preview-fit row (default clip); keep all other rows.
  - ## Configuration: ADD ### Status line (after ### Performance); UPDATE ###
        Appearance (viewport governs window-status tabs).
  - ## Usage: ADD ### Session management (after the numbered steps); keep a
        one-line rename/delete pointer in step 6.
  - ## How it works / ### Known limitations: REWRITE the "Detached candidate"
        bullet into the two-effect reconciliation.
  - Whole file: em-dash sweep so lint.sh exits 0.

NO other integration:
  - Do NOT edit CHANGELOG.md (P4.T1.S2 owns the [Unreleased] entry).
  - Do NOT edit PRD.md (read-only, human-owned).
  - Do NOT edit any script in scripts/ or any test in tests/.
  - Do NOT edit any tasks.json or prd_snapshot.md.
```

## Validation Loop

### Level 1: Style gate (write-tech-docs linter)

```bash
cd /home/dustin/.config/tmux/plugins/tmux-livepicker
bash /home/dustin/.pi/agent/skills/write-tech-docs/scripts/lint.sh README.md
# Expected: "lint: 0 hit(s)" and exit 0. The linter strips code blocks/inline code,
# then flags em dashes (U+2014) / " -- ", tell-words, and >100-word paragraphs.
# If it reports hits: fix each (em dash -> colon/paren/period; cut/replace
# tell-words; split long paragraphs into bullets), then re-run. Mandatory.
# Targeted re-checks while iterating:
grep -nP '\x{2014}' README.md            # MUST be empty (no em dashes anywhere)
grep -niEw 'powerful|robust|seamless|leverage|utilize|streamline|moreover|furthermore' README.md  # empty
```

### Level 2: Stale-reference + content checks

```bash
cd /home/dustin/.config/tmux/plugins/tmux-livepicker
# Stale refs GONE:
grep -n 'show-count\|index/total' README.md          # MUST be empty
grep -ni 'substring' README.md                       # MUST be empty (filter is fuzzy)
# Required content PRESENT:
grep -n '^### Status line' README.md                 # exactly one
grep -n '^### Session management' README.md          # exactly one
grep -c '@livepicker-preview-fit' README.md          # >=1 (table row); the table has exactly one row:
awk '/^\| .*preview-fit/{n++} END{print n}' README.md  # == 1
# Appearance names the viewport governing window-status tabs:
grep -n 'viewport\|window-status' README.md | grep -i appearance  # or confirm by reading
# Limitation note distinguishes the two effects + names clip/reflow/snapshot:
grep -niE 'clip|reflow|snapshot' README.md           # mentions all three in the limitation
grep -ni 'link-time\|link time\|at link time\|once to' README.md  # the persisting effect is named
grep -ni 'status bar grows\|status grows\|grow.*one line to two\|one row' README.md  # the fixed effect is named
```

### Level 3: Regression (doc-only change must not break the suite)

```bash
cd /home/dustin/.config/tmux/plugins/tmux-livepicker
bash tests/run.sh
# Expected: exit 0. README is not sourced by any test, so this is a sanity check
# that nothing else was accidentally touched. The real tmux server is untouched.
# If run.sh is slow/unavailable, at minimum confirm no script/test file was modified:
git status --short scripts/ tests/ plugin.tmux       # MUST be empty (doc-only change)
```

### Level 4: Render + readability sanity (manual)

```bash
cd /home/dustin/.config/tmux/plugins/tmux-livepicker
# Render-check: the Markdown table is still well-formed (lint strips it, so eyeball it).
# Confirm the four sections read coherently as a cross-cutting overview:
#   1. Configuration table -> the option reference.
#   2. ### Status line -> how line 1 is laid out (query bar, fuzzy tabs, viewport, overflow, no count).
#   3. ### Appearance -> window-status tabs obey the same §19 viewport.
#   4. ### Session management -> rename/delete keys, guards, caveats.
#   5. ### Known limitations -> status-grow (clipped) vs link-time (persists, snapshot).
# Optional markdown lint if a renderer is available:
#   mdcat README.md | head -80    # or: glow README.md
```

## Final Validation Checklist

### Technical Validation
- [ ] Level 1: `bash <skill>/scripts/lint.sh README.md` exits 0 (no em dashes, no tell-words, no >100-word paragraphs).
- [ ] Level 2: no `show-count` / `index/total` / `substring` references; `### Status line` and `### Session management` exist; `@livepicker-preview-fit` row present exactly once; the limitation note names clip + reflow + snapshot and distinguishes the two effects.
- [ ] Level 3: `bash tests/run.sh` exits 0; `git status --short scripts/ tests/ plugin.tmux` is empty (doc-only change).
- [ ] Level 4: the four sections read as a coherent cross-cutting overview; the table is well-formed.

### Feature Validation
- [ ] (a) Status line describes the query bar (far-left, only while typing, icon opt-out), fuzzy-ranked tabs left-to-right, viewport windowed by scroll, `+N>` total-hidden + `<` presence overflow indicators, no count, no-match state, status-justify suspended while typing.
- [ ] (b) Session management covers rename C-r (pre-filled prompt), delete M-BSpace (driver/last-session guards), confirm-delete, the M-BSpace terminal/SSH/mosh caveat + C-h/DC rebind, the rename escaping limitation, window-mode parity.
- [ ] (c) Appearance names the §19 viewport as governing window-status tabs (query pinned left, tabs left-to-right, overflow indicators, status-justify only when no query + tabs fit; same layout for plain and window-status).
- [ ] (d) The "Detached candidate" limitation distinguishes status-grow reflow (fixed by default clip; reflow escape hatch) from link-time resize of a detached candidate (persists; snapshot workaround).
- [ ] Stale `@livepicker-show-count` row removed; substring filter wording corrected to fuzzy.
- [ ] `@livepicker-preview-fit` row present exactly once (deduped with P3.M1.T2.S1 if it landed).

### Code Quality Validation
- [ ] New and touched prose follows write-tech-docs style (active voice, imperative for steps, one idea per sentence, consistent terminology).
- [ ] All option/key/literal references are in `code` spans (lint strips them; also aids scanning).
- [ ] No prose paragraph over ~4 sentences / 100 words; long material split into bullets/tables.
- [ ] No meaning changed by the em-dash sweep (punctuation-only conversion).
- [ ] The table remains the option reference; the prose sections are the narrative (no duplicated wall of text).

### Documentation & Deployment
- [ ] No edits to CHANGELOG.md (P4.T1.S2 owns the entry), PRD.md, scripts/, tests/, plugin.tmux, or any tasks.json.
- [ ] The README cross-references its own sections (Status line, Appearance, Known limitations) so a reader can navigate the cross-cutting overview.

---

## Anti-Patterns to Avoid

- ❌ Don't edit PRD.md, CHANGELOG.md, any script, any test, plugin.tmux, or any tasks.json. This task edits README.md ONLY.
- ❌ Don't leave em dashes in new prose OR in untouched sections. lint.sh is file-wide; the existing README is full of em dashes, and the sweep is in scope. Don't substitute ` -- ` or a bare hyphen for an em dash (both banned / wrong).
- ❌ Don't duplicate the `@livepicker-preview-fit` row or the limitation note if P3.M1.T2.S1 (parallel) already added them. Read README fully first; reconcile idempotently to the correct final text.
- ❌ Don't claim clip fixes the link-time candidate resize. It does not (clip_verification §4). Don't cite empirical_findings.md Finding 2's "manual protects the self-window" as current (clip_verification §1 corrected it: manual alone fails; the resize-window pin is load-bearing).
- ❌ Don't narrate the codebase or the freeze recipe (set-option manual + resize-window). The README documents the user-visible outcome and the escape hatches, not the mechanism.
- ❌ Don't restate the full Status line content in Appearance (or vice versa). One source of truth (§19); cross-reference.
- ❌ Don't reintroduce index/total / show-count / substring language anywhere. The count is gone (P1.M2.T3.S1); the filter is fuzzy (P1.M1.T1.S1).
- ❌ Don't write marketing tell-words (powerful, seamless, comprehensive, leverage, streamline, ...) or formulaic transitions (moreover, furthermore). State facts.
- ❌ Don't skip the lint pass. `bash <skill>/scripts/lint.sh README.md` exiting 0 is a hard gate. Fix every hit.
- ❌ Don't rewrite untouched sections beyond the em-dash/tell-word sweep. The four deliverables + stale-ref fixes are the scope; wholesale rewrites risk introducing errors.

---

## Confidence Score: 9/10

This is a documentation task with a single, well-bounded file and an unambiguous
style gate. Every deliverable's content is sourced from quoted PRD sections
(§19/§20/§21/§22/§17) and verified research (clip_verification §2/§4 for the
limitation reconciliation). The stale references are pinpointed (show-count row
~L117 is the only repo occurrence; substring wording at Usage step 2 ~L147 and the
User-stories bullet ~L48). The lint rules and the em-dash-scope decision are
explicit. The only residual risk is the parallel P3.M1.T2.S1 timing (it also adds
the preview-fit row + a tight limitation note), but the handling is idempotent:
read README fully first, then reconcile to the correct final text whether or not
P3's inline edits have landed, never duplicating the row. The implementer's job is
to translate five quoted content blocks + a mechanical em-dash sweep into the
README and pass the lint, not to discover what the features do.
