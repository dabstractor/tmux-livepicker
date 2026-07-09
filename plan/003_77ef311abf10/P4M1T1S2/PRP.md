name: "P4.M1.T1.S2 — CHANGELOG.md [Unreleased] entry (4 features, defaults, invariants, escape hatches)"
description: |

  Documentation-only task (Mode B). Edits ONE file: `CHANGELOG.md`. No code, no
  PRD, no README (P4.M1.T1.S1 owns the README changeset). This task adds a new
  `## [Unreleased]: <subtitle>` block at the top of the changelog (newest-first,
  matching the repo's existing convention) documenting the four shipped changesets
  of plan 003: (1) fuzzy ranking (`lp_rank`, subsequence + score, replaces the
  retired substring filter), (2) scrollable status-line layout (query bar + ranked
  tab viewport + `+N>`/`<` overflow indicators; the `index/total` count is gone),
  (3) session management (rename `C-r` / delete `M-BSpace`, with the driver/last-
  session guards and optional confirm-delete), and (4) preview clip (`window-size
  manual` freeze + resize pin that kills the status-grow reflow). The entry states
  the defaults (preview-fit clip, preview-defer on, tab-style plain, nerd-fonts on,
  confirm-delete off, preview-mode live), asserts NONE of them changes the PRD §14
  pollution/restore invariants (no `client-session-changed` while browsing;
  `clear_all_state` still tears down everything including the new scroll /
  client-width / window-size / client-resized keys; exactly one `switch-client` at
  confirm), and names the four escape hatches that remain (reflow, plain,
  preview-defer off, snapshot). It follows the existing changelog format (the
  rev-002 "theme-matched tabs and deferred preview" block is the structural
  template) and the write-tech-docs style (no em dashes, no tell-words), so the
  whole file must pass `scripts/lint.sh` (which requires a file-wide em-dash sweep
  of the ~19 existing em dashes).

---

## Goal

**Feature Goal**: `CHANGELOG.md` has a coherent, accurate `[Unreleased]` entry for
the plan-003 changeset that lists the four feature groups, their defaults, the
unchanged invariants, and the remaining escape hatches, in the repo's existing
changelog format and the write-tech-docs style.

**Deliverable**: An edited `CHANGELOG.md` containing:
1. A new `## [Unreleased]: <subtitle>` block inserted directly under the intro
   paragraph, ABOVE the existing `## [Unreleased]: theme-matched tabs and deferred
   preview` block (newest-first convention). Subtitle names the four feature
   groups; uses a COLON separator (never an em dash).
2. A `### Added` section (mirroring the rev-002 block shape) with one bullet per
   feature group (fuzzy ranking; scrollable status-line layout; session
   management; preview clip), each naming the option(s)/default(s)/PRD section and
   the user-visible effect.
3. One invariants bullet asserting the PRD §14 invariants are unchanged by all
   four features (no `client-session-changed` while browsing; `clear_all_state`
   still tears down everything including the new state keys; exactly one
   `switch-client` at confirm).
4. One escape-hatches bullet naming the four remaining escapes: `reflow` (preview-
   fit), `plain` (tab-style), `preview-defer off`, `snapshot` (preview-mode).
5. A file-wide em-dash sweep so the WHOLE `CHANGELOG.md` passes the
   write-tech-docs linter (`lint: 0 hit(s)`).

**Success Definition**: A reader who knows nothing about the codebase can, from
the new changelog block alone, name the four features, their defaults, that none
of them breaks the no-pollution / exact-restore invariants, and the four escape
hatches. `bash <lint.sh path> CHANGELOG.md` exits 0. `bash tests/run.sh` still
exits 0 (doc-only change; CHANGELOG is not sourced by any test). No edits to
README.md, PRD.md, scripts/, tests/, or any tasks.json.

## User Persona (if applicable)

**Target User**: A tmux user / maintainer reading the changelog to learn what
changed in this build of tmux-livepicker, what the new defaults are, and whether
they need to change their config.

**Use Case**: Skim the top `[Unreleased]` block to see the four new features, the
defaults, and the escape hatches, then decide whether to adopt or override them.

**User Journey**: Open CHANGELOG.md -> read the newest `[Unreleased]` block (four
feature bullets) -> read the invariants bullet (confidence: nothing broke) -> read
the escape-hatches bullet (how to opt out) -> optionally open README.md for
detail.

**Pain Points Addressed**: Today there is no changelog entry for plan 003's
shipped features, so a reader cannot tell what the status-line overhaul, session
management, or preview-clip change did or how to revert them.

## Why

- The four changesets (P1 rank/layout/scroll, P2 session management, P3 clip) are
  shipped and tested but undocumented in the changelog. A changelog is the place
  users look for "what changed and what are the defaults".
- The defaults matter: `clip`, `plain`, `on` (defer + nerd-fonts), `off`
  (confirm-delete) are the shipped behavior; stating them tells users whether they
  already have the new behavior or must opt out.
- The invariants are the project's core promise (PRD §4/§14); asserting they are
  unchanged preserves trust across the changeset.
- This is the single Mode-B documentation sync for the plan-003 changelog; the
  README changeset is owned by the parallel P4.M1.T1.S1 task (do not touch it).

## What

User-visible: the changelog gains one new `[Unreleased]` block at the top, and the
whole file loses its em dashes (punctuation-only). No behavioral change to the
plugin; no other file changes.

### Success Criteria

- [ ] A new `## [Unreleased]: <subtitle>` block exists directly under the intro
      paragraph and ABOVE the `## [Unreleased]: theme-matched tabs and deferred
      preview` block; the subtitle uses a colon and names the four feature groups.
- [ ] A `### Added` section lists exactly the four feature groups, each as one
      bullet, in this order: fuzzy ranking; scrollable status-line layout;
      session management; preview clip. Each bullet states the relevant option
      name(s), the default(s), a PRD section ref, and the user-visible effect.
- [ ] Fuzzy ranking bullet states: subsequence match (chars in order, case-
      insensitive), scored (prefix > word-boundary > contiguity > position; stable
      tie-break on tmux order), non-matches hidden, empty query = tmux order with
      no reordering; REPLACES the old substring filter (`scripts/filter.sh`
      retired; `scripts/rank.sh` `lp_rank` is the single source).
- [ ] Status-line bullet states: query bar (icon + query, far-left, only while
      typing) + ranked tabs left-to-right windowed by scroll + `+N>` (total
      hidden) / `<` (presence) overflow indicators; the `index/total` COUNT is
      REMOVED; `status-justify` suspended while typing.
- [ ] Session-management bullet states: rename `C-r` (command-prompt pre-filled),
      delete `M-BSpace` (driver/last-session guards; unlink-first then kill;
      rebuild + re-sync), `@livepicker-confirm-delete` default `off`; window-mode
      parity.
- [ ] Preview-clip bullet states: `@livepicker-preview-fit` default `clip` freezes
      the preview height before the status grows so panes do not reflow (bottom
      row clipped); `reflow` is the legacy fallback.
- [ ] An invariants bullet asserts ALL of: no `client-session-changed` while
      browsing (link-window/select-window, not switch-client); exactly one
      `switch-client` at confirm; `clear_all_state` still tears down everything on
      exit, including the new `@livepicker-scroll`, `@livepicker-client-width`,
      `@livepicker-orig-window-size`, and `@livepicker-orig-client-resized` keys.
- [ ] An escape-hatches bullet names ALL of: `@livepicker-preview-fit reflow`,
      `@livepicker-tab-style plain`, `@livepicker-preview-defer off`,
      `@livepicker-preview-mode snapshot`.
- [ ] The whole file passes `bash <lint.sh path> CHANGELOG.md` (exit 0): no em
      dashes (U+2014), no ` -- `, no tell-words, no >100-word prose paragraph.
- [ ] No edits to README.md, PRD.md, scripts/, tests/, plugin.tmux, or any
      tasks.json / prd_snapshot.md.

## All Needed Context

### Context Completeness Check

_"If someone knew nothing about this codebase, would they have everything needed
to implement this successfully?"_ — Yes. This PRP pins the exact changelog format
(header convention, section order, newest-first, the colon subtitle, the rev-002
block as the structural template with quoted line references), the exact content
each of the four feature bullets must contain (sourced from the quoted PRD §19/
§20/§21/§22 selectors and verified against `scripts/options.sh` + `scripts/state.sh`),
the verified defaults, the verified invariant keys (from `state.sh` `_STATE_RUNTIME_KEYS`
and the `@livepicker-orig-` clear rule), the four escape hatches, and the CORRECT
write-tech-docs lint path plus its exact rules and the file-wide em-dash sweep
scope (~19 lines). The one trap (the sibling PRP's lint path does not exist) is
called out with the real path and a self-contained fallback.

### Documentation & References

```yaml
# MUST READ — load into your context window before editing.

- file: CHANGELOG.md
  why: THE file being edited. Read it FULLY first (the task contract requires
        this). Note: the intro + `# Changelog` heading (lines 1-3); the newest-
        first block order; the rev-002 `## [Unreleased]: theme-matched tabs and
        deferred preview` block (lines ~5-76) which is the STRUCTURAL TEMPLATE for
        the new entry (### Added bullets: bold option name + default + PRD ref +
        mechanism + effect; then an invariants bullet; then an escape-hatches
        bullet); and the ~19 em-dash (U+2014) lines that must be swept (§Known
        Gotchas). Insert the new block BETWEEN the intro (line ~3) and the rev-002
        header (line ~5).
  pattern: "newest-first: insert the new [Unreleased]: <subtitle> block directly
        under the intro, ABOVE the existing rev-002 block. Mirror the rev-002
        ### Added bullet shape. Do NOT merge into a single [Unreleased] (the repo
        convention is one [Unreleased]: <subtitle> per changeset)."

- file: /home/dustin/projects/writing-skills/skills/write-tech-docs/scripts/lint.sh
  why: THE gate. Run `bash <this> CHANGELOG.md`; MUST exit 0 (`lint: 0 hit(s)`).
        It strips fenced + inline code, then FAILS on: (1) em dashes (U+2014) or
        ' -- '; (2) the tell-word list (case-insensitive whole word: powerful,
        robust, elegant, seamless, comprehensive, cutting-edge, state-of-the-art,
        revolutionary, game-changing, next-generation, blazing-fast, lightning-fast,
        intuitive, effortless, frictionless, ultimate, stunning, beautiful,
        incredible, leverage, utilize, unlock, empower, supercharge, revolutionize,
        streamline, elevate, delve, tapestry, realm, landscape, moreover,
        furthermore, truly, incredibly); (3) a prose paragraph over 100 words
        (skips headings/lists/tables/quotes).
  critical: "the sibling P4.M1.T1.S1 PRP cites ~/.pi/agent/skills/write-tech-docs/
        scripts/lint.sh, which DOES NOT EXIST in this environment (only agent-browser
        and mdsel are installed under ~/.pi/agent/skills/). Use the path above. If
        it is unreachable, fall back to the self-contained grep checks in the
        Validation Loop (they replicate rules 1+2; rule 3 = keep paragraphs short)."

- file: /home/dustin/projects/writing-skills/skills/write-tech-docs/SKILL.md
  why: the style contract. Hard rules: no em dashes (U+2014), use colon/paren/
        comma/period instead; no marketing tell-words; no hedging or formulaic
        transitions (moreover/furthermore); no narrating the codebase; no prose
        paragraph over ~4 sentences / 100 words. Active voice, one idea per
        sentence. Evidence over adjectives.
  section: "rule #1 (no em dashes) and the Reference: tell-word list."

- file: PRD.md   # READ-ONLY; do NOT edit
  why: the authoritative source for each feature bullet's content. The selectors
        quoted in the task brief are §1 Overview, §2 Goals/non-goals, §4 Core rule,
        §14 Pollution analysis, §11 Configuration options, §19 Status-line layout
        (single source of truth for line 1; index/total removed), §20 Filtering and
        ranking (fuzzy), §21 Session management, §22 Preview sizing (clip vs
        reflow). Mine §19/§20/§21/§22 + the §11 options table for the exact
        wording, defaults, and PRD refs of the four bullets.

- file: plan/003_77ef311abf10/P4M1T1S2/research/changelog_entry_findings.md
  why: THIS task's synthesis (read FIRST; it is the TL;DR). Pins the changelog
        format, the four feature bullets' exact content, the verified defaults,
        the verified invariant keys, the four escape hatches, the correct lint
        path + rules, the file-wide em-dash sweep scope (the ~19 lines), and the
        parallel-execution non-conflict note.

- file: scripts/options.sh   # READ-ONLY; the option set + defaults
  why: confirms the exact defaults so the bullets are accurate: opt_preview_fit
        (clip), opt_preview_defer (on), opt_tab_style (plain), opt_nerd_fonts (on),
        opt_confirm_delete (off), opt_preview_mode (live). The bullets must match
        these. opt_show_count is GONE (do not mention a count option).

- file: scripts/state.sh   # READ-ONLY; the teardown contract
  why: confirms the invariant bullet. _STATE_RUNTIME_KEYS (line 67) INCLUDES
        STATE_SCROLL (@livepicker-scroll) and STATE_CLIENT_WIDTH (@livepicker-
        client-width), so clear_all_state clears them explicitly. ORIG_WINDOW_SIZE
        (@livepicker-orig-window-size, line 60) and ORIG_CLIENT_RESIZED_HOOK
        (@livepicker-orig-client-resized, line 62) are auto-cleared by clear_all_state's
        @livepicker-orig- grep. State this so the invariants bullet is precise.

- file: plan/003_77ef311abf10/architecture/clip_verification.md   # READ-ONLY
  why: the empirical evidence for the preview-clip bullet's mechanism wording.
        §1 corrects empirical_findings Finding 2 (manual ALONE fails; the
        resize-window -y <pre-grow-height> pin is load-bearing). §2 = control
        (reflow reproduced) vs treatment (clip: byte-identical window_layout
        across the grow, and a second grow). Use the user-visible OUTCOME in the
        bullet ("panes do not reflow; the bottom row is clipped"), not the recipe.
  section: "Decision box; §1 correction; §2 treatment evidence."

- file: plan/003_77ef311abf10/P4M1T1S1/PRP.md   # READ-ONLY; parallel sibling
  why: P4.M1.T1.S1 (README) is implemented in parallel. It edits README.md ONLY
        and explicitly does NOT touch CHANGELOG.md (this task owns it). So there
        is NO file conflict. Do not depend on the README's in-flight state; keep
        the changelog entry self-contained.

- url: https://keepachangelog.com/
  why: the changelog format the file's intro cites. NOTE the repo DEVIATES: it
        uses one `## [Unreleased]: <subtitle>` block per changeset (newest-first),
        not a single accumulating [Unreleased]. Follow the REPO convention, not
        strict Keep a Changelog. The task says "per the existing format".
```

### Current Codebase tree (run `ls` + `head CHANGELOG.md`)

```bash
tmux-livepicker/
├── CHANGELOG.md             # ← THE ONLY FILE EDITED BY THIS TASK (doc sync)
├── README.md                # READ-ONLY here (P4.M1.T1.S1 owns the README changeset)
├── PRD.md                   # READ-ONLY (never edit)
├── scripts/
│   ├── options.sh           # READ-ONLY — defaults: preview-fit clip, preview-defer on,
│   │                        #   tab-style plain, nerd-fonts on, confirm-delete off, preview-mode live
│   ├── rank.sh              # READ-ONLY — lp_rank fuzzy subsequence+score (replaced filter.sh)
│   ├── layout.sh            # READ-ONLY — lp_viewport display-width + scroll math
│   ├── session-mgmt.sh      # READ-ONLY — do-rename / do-delete
│   └── state.sh             # READ-ONLY — _STATE_RUNTIME_KEYS + @livepicker-orig- clear contract
├── tests/                   # READ-ONLY — run.sh must stay green; CHANGELOG not sourced by any test
└── plan/003_77ef311abf10/
    ├── architecture/clip_verification.md   # READ-ONLY — clip evidence
    └── P4M1T1S2/{PRP.md (THIS file), research/changelog_entry_findings.md}
```

### Desired Codebase tree with files to be added and responsibility of file

```bash
# ONE file modified. Nothing else is created or modified by this task.
CHANGELOG.md   # EDIT in place:
               #   + new ## [Unreleased]: <subtitle> block under the intro (4 feature bullets +
               #     invariants bullet + escape-hatches bullet), mirroring the rev-002 shape;
               #   ~ full-file em-dash sweep (~19 U+2014 lines -> colon/paren/comma/period),
               #     including the ## [Unreleased] — Initial implementation header (-> colon),
               #     so the WHOLE file passes lint.sh.
```

### Known Gotchas of our codebase & the write-tech-docs skill

```bash
# CRITICAL:

# 1. The write-tech-docs lint.sh path in the sibling P4.M1.T1.S1 PRP is WRONG.
#    /home/dustin/.pi/agent/skills/write-tech-docs/scripts/lint.sh DOES NOT EXIST
#    (only agent-browser and mdsel are installed under ~/.pi/agent/skills/). The
#    real script is /home/dustin/projects/writing-skills/skills/write-tech-docs/
#    scripts/lint.sh . Use it; if unreachable, use the grep fallback in Validation
#    Level 1. lint.sh is the hard gate and it is FILE-WIDE, so a passing run
#    requires the em-dash sweep below.

# 2. Em dashes (U+2014) are BANNED file-wide. The existing CHANGELOG has ~19
#    em-dash lines: 17, 23, 32, 35, 43, 52, 61, 71, 75, 78 (the
#    "## [Unreleased] — Initial implementation" header), 102, 107, 111, 116, 125,
#    133, 140, 149, 150. Sweep ALL of them (punctuation-only, meaning-preserving):
#    em dash -> colon (clause intro) / parentheses (parenthetical) / comma or
#    period. NEVER substitute ' -- ' (also banned) or a bare hyphen. A later
#    optional nicety: line 84 has an EN dash (U+2013, 'P1.M1–M7'); lint does NOT
#    flag en dashes, so leave it or convert to 'P1.M1 to M7' (optional).

# 3. lint.sh STRIPS fenced code blocks and inline code BEFORE checking, so option
#    names, commands, and `+N>` / `<` literals inside backticks are never flagged.
#    Keep every option/key/command/indicator in `code` spans.

# 4. The >100-word paragraph check skips headings, lists, tables, blockquotes.
#    The rev-002 block already uses bullets, so mirror that; keep any prose lead
#    to one or two short sentences. Do not write a long paragraph.

# 5. Repo changelog convention = one `## [Unreleased]: <subtitle>` block per
#    changeset, NEWEST on top (just under the intro), colon separator. Do NOT
#    merge into a single accumulating [Unreleased], and do NOT invent a version
#    number. The task says "[Unreleased] entry (or the next-version header per the
#    existing format)" = follow the existing `[Unreleased]: <subtitle>` format.

# 6. The structural template is the rev-002 `### Added` block, NOT the bugfix
#    blocks (those are `### Fixed` adversarial-QA passes with Major/Minor grading).
#    Mirror rev-002's bullet shape (bold option name + default + PRD ref +
#    mechanism + effect; then an invariants bullet; then an escape-hatches bullet).
#    The task note "the bugfix-001 entry is the template" refers to the overall
#    FORMAT/style of the existing entries; rev-002 is the feature-listing analog.

# 7. The `index/total` count and the substring filter are GONE in code (P1.M2.T3.S1
#    removed the count; P1.M1.T1.S1 replaced substring with fuzzy lp_rank; filter.sh
#    is retired). The status-line bullet must say the count is REMOVED and the
#    filter is now fuzzy. Do NOT reintroduce 'count' or 'substring' as current
#    behavior (substring is only mentioned as the thing fuzzy REPLACED).

# 8. Accuracy anchors (do not paraphrase into error):
#    - Defaults: preview-fit clip, preview-defer on, tab-style plain, nerd-fonts on,
#      confirm-delete off, preview-mode live (scripts/options.sh).
#    - Invariant keys torn down by clear_all_state: @livepicker-scroll +
#      @livepicker-client-width (explicit, in _STATE_RUNTIME_KEYS) and
#      @livepicker-orig-window-size + @livepicker-orig-client-resized (via the
#      @livepicker-orig- grep). scripts/state.sh lines 60-67.
#    - Clip mechanism: window-size manual + resize-window -y <pre-grow-height>;
#      manual ALONE is insufficient (clip_verification §1). State the OUTCOME in
#      the bullet, not the recipe.

# 9. Do NOT edit README.md (P4.M1.T1.S1 owns it), PRD.md, any script, any test,
#    plugin.tmux, or any tasks.json / prd_snapshot.md. This task edits CHANGELOG.md
#    ONLY. CHANGELOG is not sourced by any test, so the edit cannot break
#    tests/run.sh, but run it as a regression sanity check (Level 3).
```

## Implementation Blueprint

No data models. This task edits one Markdown file. The "structure" is: insert one
new changelog block, then a file-wide em-dash sweep, in dependency order.

### Implementation Tasks (ordered by dependencies)

```yaml
Task 1: READ the cited context (NO writes)
  - READ: CHANGELOG.md FULLY (the contract requires a full read first). Note the
        intro + heading (lines 1-3); newest-first block order; the rev-002
        `## [Unreleased]: theme-matched tabs and deferred preview` block (the
        STRUCTURAL TEMPLATE: ### Added bullets + an invariants bullet + an
        escape-hatches bullet); the rev-001 `## [Unreleased] — Initial
        implementation` header (em dash -> swept); and ALL ~19 em-dash lines.
  - READ: plan/003_77ef311abf10/P4M1T1S2/research/changelog_entry_findings.md
        (this task's synthesis, FIRST).
  - READ: /home/dustin/projects/writing-skills/skills/write-tech-docs/scripts/lint.sh
        (the gate; confirm the path EXISTS; note its three rules).
  - SKIM: /home/dustin/projects/writing-skills/skills/write-tech-docs/SKILL.md
        (the style rules + tell-word list).
  - SKIM: PRD.md §19 + §20 + §21 + §22 + §14 + §11 (authoritative content for the
        four bullets + the invariants + defaults). Mine the exact wording.
  - CONFIRM: scripts/options.sh (defaults: clip/on/plain/on/off/live) and
        scripts/state.sh lines 60-67 (the teardown keys for the invariants bullet).
  - SKIM: plan/003_77ef311abf10/architecture/clip_verification.md Decision box +
        §1/§2 (clip mechanism wording; manual alone insufficient).
  - PURPOSE: internalize the block shape, the four bullet contents, the defaults,
        the invariant keys, the four escape hatches, and the em-dash sweep. Do NOT
        edit README.md, PRD.md, scripts/, tests/, or any tasks.json.

Task 2: DRAFT the new ## [Unreleased]: <subtitle> block (deliverables 1-4)
  - PLACE: insert directly under the intro paragraph (after line ~3) and ABOVE the
        existing `## [Unreleased]: theme-matched tabs and deferred preview` header.
  - HEADER: `## [Unreleased]: fuzzy ranking, scrollable status line, session
        management, preview clip` (colon separator; names the four groups; NO em
        dash). Any equivalent colon-subtitled header naming the four groups is fine.
  - SECTION: `### Added`.
  - BULLET 1 — Fuzzy ranking (PRD §20): `lp_rank` in `scripts/rank.sh` replaces the
        retired substring `scripts/filter.sh`. Match = SUBSEQUENCE (query chars in
        order, case-insensitive; non-matches hidden). Score = prefix bonus >
        word-boundary > contiguity > position penalty; stable tie-break on tmux
        order. Empty query = all sessions at score 0 in tmux order (no reordering,
        preserves the no-MRU non-goal). Single source of truth for renderer,
        input-handler, and session-mgmt.
  - BULLET 2 — Scrollable status-line layout (PRD §19): line 1 is a query bar
        (icon `@livepicker-search-icon` U+F002 when `@livepicker-nerd-fonts` on +
        the query, pinned far-left, shown ONLY while a query is non-empty) + the
        ranked tabs left-to-right, windowed by `@livepicker-scroll`. Overflow
        indicators: right `+N>` (`@livepicker-overflow-right-format`, N = total
        hidden) and left `<` (`@livepicker-overflow-left`, presence only). The
        `index/total` COUNT is REMOVED. `status-justify` is suspended while typing.
        New `scripts/layout.sh` (`lp_viewport` display-width + scroll math); width
        from `@livepicker-client-width` cached at activate (no per-keystroke tmux
        round-trip), refreshed by a `client-resized` hook.
  - BULLET 3 — Session management (PRD §21): rename `@livepicker-rename-key`
        (default `C-r`) via tmux's `command-prompt` pre-filled; delete
        `@livepicker-delete-key` (default `M-BSpace`) with guards that refuse the
        driver session and the last session, unlink-first then kill-session, then
        rebuild the list and re-sync the preview; `@livepicker-confirm-delete`
        (default `off`) = sessionx-style immediate (`on` = y/n confirm). Both are
        control keys so they never collide with the typing set; window mode parity.
        New `scripts/session-mgmt.sh`.
  - BULLET 4 — Preview clip (PRD §22 + clip_verification): `@livepicker-preview-fit`
        (default `clip`) freezes the preview window's height before the status bar
        grows from 1 to 2 lines (`window-size manual` + a `resize-window` height pin),
        so panes do not reflow and only the bottom row is clipped; it kills the
        status-grow jank. `reflow` is the legacy escape hatch. The driver's
        `window-size` is saved to `@livepicker-orig-window-size` and restored on exit.
  - INVARIANTS BULLET: state that NONE of the four changes the PRD §14 invariants:
        browsing still fires no `client-session-changed` (link-window/select-window,
        not switch-client); the only switch is the single confirm-time switch-client;
        and `clear_all_state` still tears down everything on exit, including the new
        `@livepicker-scroll`, `@livepicker-client-width`,
        `@livepicker-orig-window-size`, and `@livepicker-orig-client-resized` keys.
  - ESCAPE-HATCHES BULLET: name all four: `@livepicker-preview-fit reflow` (legacy
        one-row reflow), `@livepicker-tab-style plain` (the shipped default, instead
        of window-status), `@livepicker-preview-defer off` (synchronous path),
        `@livepicker-preview-mode snapshot` (capture-pane, never links/resizes a
        candidate).
  - FOLLOW pattern: the rev-002 `### Added` bullet density (bold option name,
        default, PRD ref, mechanism, effect; one or two sentences).
  - GOTCHA: keep every option/key/command/indicator literal in `code` spans. No em
        dashes. No tell-words. No prose paragraph over ~100 words (use bullets).

Task 3: FILE-WIDE em-dash sweep (write-tech-docs gate)
  - SWEEP: remove every U+2014 from CHANGELOG.md (the ~19 existing lines listed in
        Known Gotchas #2, INCLUDING the `## [Unreleased] — Initial implementation`
        header -> `## [Unreleased]: Initial implementation`). Replace each with a
        colon (clause intro), parentheses (parenthetical), or comma/period per
        context. NEVER use ' -- ' (also banned) or a bare hyphen.
  - VERIFY: `grep -nP '\x{2014}' CHANGELOG.md` is EMPTY; `grep -n ' -- ' CHANGELOG.md`
        is EMPTY.
  - GOTCHA: punctuation-only; do NOT change wording or meaning. Keep all `code`
        spans intact (lint strips them anyway). The sweep is mechanical and
        low-risk, exactly like the README sweep in the parallel P4.M1.T1.S1 task.
  - OPTIONAL: convert the en dash at line 84 (`P1.M1–M7` -> `P1.M1 to M7`). lint
        does not flag en dashes, so this is optional polish.

Task 4: VALIDATE (see Validation Loop) — lint gate + content grep checks + regression.
```

### Implementation Patterns & Key Details

```markdown
<!-- Pattern: a rev-002-style Added bullet. Bold option/feature name, default, PRD
     ref, mechanism, effect. One or two sentences. Every literal in a code span. -->

- **Fuzzy ranking** (PRD §20). Matching is now a fuzzy subsequence match (every
  query character appears in the name in order, case-insensitive), not the old
  substring filter. Matches are scored best-first (prefix bonus, then word-
  boundary, then contiguity, with a small position penalty and a stable tie-break
  on tmux order), and non-matches are hidden. An empty query leaves sessions in
  tmux default order (no MRU reordering). The ranker lives once in
  `scripts/rank.sh` (`lp_rank`), replacing the retired `scripts/filter.sh`, so the
  renderer, the input handler, and session management can never drift.

<!-- Pattern: the invariants bullet. Assert the three §14 invariants and name the
     exact new keys clear_all_state tears down. -->

- None of these changes the invariants the plugin already upholds (PRD §14).
  Browsing still fires no `client-session-changed` (the preview uses
  `link-window` / `select-window`, never `switch-client`), so the
  `tmux-session-history` timeline and the toggle are untouched; the only switch is
  the single confirm-time `switch-client`. `clear_all_state` still tears down every
  picker state key on exit, including the new `@livepicker-scroll`,
  `@livepicker-client-width`, `@livepicker-orig-window-size`, and
  `@livepicker-orig-client-resized`.

<!-- Pattern: the escape-hatches bullet. Name all four escapes with their option. -->

- The escape hatches stay available: `@livepicker-preview-fit reflow` for the
  legacy one-row reflow, `@livepicker-tab-style plain` for the standalone tab style
  (the shipped default), `@livepicker-preview-defer off` for the synchronous
  preview path, and `@livepicker-preview-mode snapshot` to preview with
  `capture-pane` and never link or resize a candidate window.

<!-- Anti-pattern: do NOT write the clip recipe ("set-option -t manual then
     resize-window -y H0"). State the outcome (panes do not reflow; bottom row
     clipped) and name reflow as the fallback. -->
```

### Integration Points

```yaml
CHANGELOG.md (the only integration surface):
  - Insert point: directly under the intro paragraph (after line ~3), ABOVE the
        existing `## [Unreleased]: theme-matched tabs and deferred preview` header.
  - New block: `## [Unreleased]: <four-group subtitle>` + `### Added` (4 feature
        bullets) + 1 invariants bullet + 1 escape-hatches bullet.
  - Whole file: em-dash sweep so lint.sh exits 0.

NO other integration:
  - Do NOT edit README.md (P4.M1.T1.S1 owns it), PRD.md, any script in scripts/,
        any test in tests/, plugin.tmux, or any tasks.json / prd_snapshot.md.
```

## Validation Loop

### Level 1: Style gate (write-tech-docs linter)

```bash
cd /home/dustin/.config/tmux/plugins/tmux-livepicker
# PRIMARY gate. Use the REAL path (the sibling PRP's ~/.pi/agent/skills/... path
# does NOT exist in this environment):
bash /home/dustin/projects/writing-skills/skills/write-tech-docs/scripts/lint.sh CHANGELOG.md
# Expected: "lint: 0 hit(s)" and exit 0. lint.sh strips fenced + inline code, then
# flags em dashes (U+2014) / " -- ", the tell-word list (case-insensitive whole
# word), and >100-word prose paragraphs (skips headings/lists/tables/quotes).
# If it reports hits: fix each (em dash -> colon/paren/comma/period; cut/replace
# tell-words; split long paragraphs into bullets), then re-run. Mandatory.

# FALLBACK if the script path is unreachable (replicates lint rules 1 + 2; rule 3
# is covered by keeping prose as short bullets):
grep -nP '\x{2014}| -- ' CHANGELOG.md          # MUST be empty
grep -niEw 'powerful|robust|elegant|seamless|comprehensive|cutting-edge|state-of-the-art|revolutionary|game-changing|next-generation|blazing-fast|lightning-fast|intuitive|effortless|frictionless|ultimate|stunning|beautiful|incredible|leverage|utilize|unlock|empower|supercharge|revolutionize|streamline|elevate|delve|tapestry|realm|landscape|moreover|furthermore|truly|incredibly' CHANGELOG.md  # MUST be empty
```

### Level 2: Content + structure checks

```bash
cd /home/dustin/.config/tmux/plugins/tmux-livepicker
# New block is newest-first (directly under the intro, ABOVE the rev-002 block):
awk '/^## \[Unreleased\]/{print NR": "$0}' CHANGELOG.md   # the new subtitle line prints BEFORE "theme-matched tabs"
# Four feature groups all named in the new block:
grep -niE 'fuzzy|subsequence' CHANGELOG.md                # fuzzy ranking
grep -niE 'query bar|overflow|scroll|index/total|count' CHANGELOG.md   # status-line (index/total as REMOVED)
grep -niE 'rename|delete|M-BSpace|C-r' CHANGELOG.md       # session management
grep -niE 'clip|window-size|reflow' CHANGELOG.md          # preview clip
# Defaults present:
grep -niE 'preview-fit.*clip|clip.*default|default.*clip' CHANGELOG.md
grep -niE 'confirm-delete.*off' CHANGELOG.md
# Invariants bullet names the teardown keys + the no-switch-while-browsing rule:
grep -niE 'client-session-changed' CHANGELOG.md
grep -niE 'clear_all_state' CHANGELOG.md
grep -niE 'livepicker-scroll|livepicker-client-width|livepicker-orig-window-size|livepicker-orig-client-resized' CHANGELOG.md
# Escape hatches all named:
grep -niE 'preview-fit reflow|tab-style plain|preview-defer off|preview-mode snapshot' CHANGELOG.md
# Stale refs NOT re-introduced as current behavior:
grep -niE 'show-count' CHANGELOG.md                       # MUST be empty (no count option)
```

### Level 3: Regression (doc-only change must not break the suite)

```bash
cd /home/dustin/.config/tmux/plugins/tmux-livepicker
bash tests/run.sh
# Expected: exit 0 (prints "N passed, 0 failed (of M)"). CHANGELOG is not sourced
# by any test, so this is a sanity check that nothing else was accidentally touched.
# Confirm doc-only change:
git status --short README.md scripts/ tests/ plugin.tmux PRD.md   # MUST be empty
```

### Level 4: Readability + format sanity (manual)

```bash
cd /home/dustin/.config/tmux/plugins/tmux-livepicker
# Read the new block top-to-bottom as a user would. Confirm it reads as a coherent
# overview: four features -> defaults -> invariants unchanged -> escape hatches.
# Confirm the block is newest-first (under the intro, above the rev-002 block) and
# the subtitle uses a colon (no em dash).
# Confirm no em dash survived anywhere: grep -nP '\x{2014}' CHANGELOG.md  (empty).
# Optional render: mdcat CHANGELOG.md | head -40   # or: glow CHANGELOG.md
```

## Final Validation Checklist

### Technical Validation
- [ ] Level 1: `bash /home/dustin/projects/writing-skills/skills/write-tech-docs/scripts/lint.sh CHANGELOG.md` exits 0 (`lint: 0 hit(s)`). (Fallback greps in Level 1 are empty if the script is unreachable.)
- [ ] Level 2: the new block is newest-first; the four feature groups, the defaults (clip/on/plain/on/off/live), the invariants (no `client-session-changed` while browsing; one `switch-client` at confirm; `clear_all_state` tears down the named new keys), and the four escape hatches are all present and accurate.
- [ ] Level 3: `bash tests/run.sh` exits 0; `git status --short README.md scripts/ tests/ plugin.tmux PRD.md` is empty (doc-only change).
- [ ] Level 4: the new block reads coherently; no em dash anywhere (`grep -nP '\x{2014}' CHANGELOG.md` empty); subtitle uses a colon.

### Feature Validation
- [ ] Fuzzy ranking bullet: subsequence match + scoring (prefix > word-boundary > contiguity > position; stable tie-break), non-matches hidden, empty query = tmux order, replaces the retired substring `filter.sh`; `lp_rank` in `scripts/rank.sh` is the single source.
- [ ] Status-line bullet: query bar (far-left, only while typing) + ranked tabs left-to-right windowed by scroll + `+N>`/`<` overflow indicators; `index/total` count REMOVED; `status-justify` suspended while typing.
- [ ] Session-management bullet: rename `C-r` (command-prompt pre-filled), delete `M-BSpace` (driver/last-session guards; unlink-first then kill; rebuild + re-sync), `@livepicker-confirm-delete` default `off`; window-mode parity.
- [ ] Preview-clip bullet: `@livepicker-preview-fit` default `clip` freezes the preview height before the status grows (panes do not reflow; bottom row clipped); `reflow` legacy fallback.
- [ ] Invariants bullet: asserts all three §14 invariants AND names the new teardown keys (`@livepicker-scroll`, `@livepicker-client-width`, `@livepicker-orig-window-size`, `@livepicker-orig-client-resized`).
- [ ] Escape-hatches bullet: names all four (`reflow`, `plain`, `preview-defer off`, `snapshot`).

### Code Quality Validation
- [ ] New and swept prose follows write-tech-docs style (active voice, one idea per sentence, evidence over adjectives, consistent terminology).
- [ ] Every option/key/command/indicator literal is in a `code` span (lint strips code; also aids scanning).
- [ ] No prose paragraph over ~4 sentences / 100 words; long material is bulleted (mirrors rev-002).
- [ ] The em-dash sweep is punctuation-only; no wording or meaning changed; all `code` spans intact.

### Documentation & Deployment
- [ ] No edits to README.md (P4.M1.T1.S1 owns it), PRD.md, scripts/, tests/, plugin.tmux, or any tasks.json / prd_snapshot.md.
- [ ] The new block follows the repo's `## [Unreleased]: <subtitle>` convention (newest-first, colon separator), not a single accumulating [Unreleased].

---

## Anti-Patterns to Avoid

- ❌ Don't edit README.md (P4.M1.T1.S1 owns it), PRD.md, any script, any test, plugin.tmux, or any tasks.json. This task edits CHANGELOG.md ONLY.
- ❌ Don't use the lint path from the sibling PRP (`~/.pi/agent/skills/write-tech-docs/scripts/lint.sh`). It does NOT exist in this environment. Use `/home/dustin/projects/writing-skills/skills/write-tech-docs/scripts/lint.sh` (or the grep fallback).
- ❌ Don't leave em dashes anywhere. lint.sh is file-wide; the existing CHANGELOG has ~19 em-dash lines (including the `## [Unreleased] — Initial implementation` header). The full-file sweep is in scope. Don't substitute ` -- ` (also banned) or a bare hyphen for an em dash.
- ❌ Don't merge the new entry into a single accumulating `[Unreleased]` or invent a version number. The repo convention is one `## [Unreleased]: <subtitle>` block per changeset, newest-first.
- ❌ Don't use the bugfix (`### Fixed`) blocks as the shape. The structural template is the rev-002 `### Added` feature block. The task's "bugfix-001 entry is the template" note refers to the overall format/style, not the bugfix grading.
- ❌ Don't re-introduce `show-count` / `index/total` / `substring` as CURRENT behavior. The count is removed (P1.M2.T3.S1); the filter is fuzzy (P1.M1.T1.S1); `substring` is mentioned only as what fuzzy REPLACED, and `index/total` only as what was REMOVED.
- ❌ Don't mis-state the clip mechanism. The OUTCOME is "panes do not reflow; the bottom row is clipped". Do NOT claim `window-size manual` alone fixes it (clip_verification §1: manual alone is insufficient; the `resize-window` pin is load-bearing). Don't write the recipe.
- ❌ Don't invent defaults. They are: preview-fit clip, preview-defer on, tab-style plain, nerd-fonts on, confirm-delete off, preview-mode live (scripts/options.sh).
- ❌ Don't write marketing tell-words (powerful, seamless, comprehensive, leverage, streamline, ...) or formulaic transitions (moreover, furthermore). State facts.
- ❌ Don't hardcode a stale test count. If you cite the suite size, run `bash tests/run.sh` and record the real number (floor 44; currently ~91). Citing a count is optional; the rev-002 Added block did not cite one.

---

## Confidence Score: 9/10

This is a documentation task with a single, well-bounded file and an unambiguous
style gate. Every bullet's content is sourced from the quoted PRD selectors
(§19/§20/§21/§22) plus §14 for the invariants, and verified against
`scripts/options.sh` (defaults) and `scripts/state.sh` (the exact teardown keys).
The format is pinned to the repo's `## [Unreleased]: <subtitle>` convention with
the rev-002 block as the structural template. The one real trap, the write-tech-docs
lint PATH (the sibling PRP's `~/.pi/agent/skills/...` path does not exist), is
resolved with the correct path plus a self-contained grep fallback, and the
file-wide em-dash sweep scope is enumerated (~19 lines). The parallel P4.M1.T1.S1
task edits README.md only, so there is no file conflict. The implementer's job is
to translate four content blocks + a mechanical em-dash sweep into CHANGELOG.md
and pass the lint, not to discover what the features do.
