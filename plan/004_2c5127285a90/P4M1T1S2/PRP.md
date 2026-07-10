name: "P4.M1.T1.S2 — Add CHANGELOG entry for the plan-004 changeset (two-axis nav, window-flip + confirm-on-window, pane immutability)"
description: |

  Documentation-only task (Mode B). Edits ONE file: `CHANGELOG.md`. No code, no
  PRD, no README (P4.M1.T1.S1 owns the README changeset). LOAD-BEARING FACT:
  `CHANGELOG.md` does NOT exist on this branch (`main`) — not in the working
  tree, not in HEAD, and no commit on `main` ever added it. (The "changelog"
  commits reachable from main touched README/PRP files; the actual CHANGELOG.md
  only ever lived on the sibling `prd-updates` branch.) So this task CREATES
  CHANGELOG.md fresh: the standard Keep a Changelog intro + ONE new
  `## [Unreleased]: <subtitle>` block (colon form, newest-first) with a
  `### Added` section mirroring the prd-updates "theme-matched tabs" entry shape.
  The block documents the three plan-004 feature groups: (1) two-axis discovered
  navigation (window-nav keys flip the previewed session's windows; session-nav
  keys discovered from switch-client bindings; both discovered from your config,
  overridable; replaces the dropped single-axis "repurposed window-nav" model),
  (2) window-flip preview (flip through a candidate's windows live) + confirm-
  on-window (confirm lands on the exact window being previewed; flipping never
  changes the candidate's own active window = leave-no-trace), and (3) pane
  immutability (Invariant C: no pane of any session is ever moved or resized;
  drift-gated restore; detached-candidate pinning; snapshot escape). The entry
  states the defaults (axes discovered; preview-fit clip; preview-defer on),
  asserts NONE of the features changes the pollution/restore invariants A/B/C,
  and names `@livepicker-preview-mode snapshot` as the strict-immutability escape
  hatch. write-tech-docs style (no em dashes, no tell-words); because the file is
  created fresh, no em-dash sweep is needed, only clean new prose.

---

## Goal

**Feature Goal**: `CHANGELOG.md` exists on `main` and has a coherent, accurate
`[Unreleased]` entry for the plan-004 changeset (two-axis discovered navigation,
window-flip preview + confirm-on-window, pane immutability), in the repo's
existing changelog format and the write-tech-docs style.

**Deliverable**: A newly-created `CHANGELOG.md` containing:
1. The standard intro: a `# Changelog` heading + the Keep a Changelog reference
   paragraph (mirrored from the established format).
2. ONE new `## [Unreleased]: <subtitle>` block (colon separator, no em dash)
   directly under the intro, with a `### Added` section.
3. Three feature bullets: two-axis discovered navigation; window-flip preview +
   confirm-on-window; pane immutability (Invariant C). Each names the relevant
   option(s)/default(s)/PRD section and the user-visible effect.
4. A defaults note (axes discovered; `@livepicker-preview-fit clip`;
   `@livepicker-preview-defer on`).
5. An invariants bullet asserting A/B/C are unchanged by all three features.
6. An escape-hatch note naming `@livepicker-preview-mode snapshot` for strict
   immutability.
7. The whole file passes the write-tech-docs linter (`lint: 0 hit(s)`).

**Success Definition**: A reader who knows nothing about the codebase can, from
the new changelog block alone, name the three features, the defaults, that none
of them breaks the no-pollution / exact-restore invariants A/B/C, and the
snapshot escape hatch. `bash <lint.sh path> CHANGELOG.md` exits 0. No edits to
README.md, PRD.md, scripts/, tests/, or any tasks.json. Only CHANGELOG.md is
created.

## User Persona (if applicable)

**Target User**: A tmux user / maintainer reading the changelog to learn what
changed in this build of tmux-livepicker, what the new key model is, and what
confirm does.

**Use Case**: Open CHANGELOG.md -> read the top `[Unreleased]` block (three
feature bullets) -> read the defaults -> read the invariants bullet (nothing
broke) -> read the escape-hatch note (how to get strict immutability).

**User Journey**: Skim the newest block -> learn the two-axis key model and that
confirm lands on a window -> learn no panes are ever mutated -> learn snapshot
opts out of live preview entirely if needed.

**Pain Points Addressed**: There is no changelog entry for the plan-004
changeset, so a reader cannot tell what the two-axis navigation, window flip,
confirm-on-window, or pane-immutability work did.

## Why

- The plan-004 changeset (two-axis key discovery, window-flip, confirm-on-window,
  pane immutability) is shipped and tested but has no changelog entry. A
  changelog is where users look for "what changed".
- The two-axis model is a behavioral change from the earlier single-axis model
  (window-nav keys now flip windows instead of moving the session selection); the
  changelog must record this so it is not a surprise.
- The defaults matter (axes discovered; clip; defer on): stating them tells users
  they already have the new behavior.
- The invariants A/B/C are the project's core promise (PRD §4/§14/§23); asserting
  they are unchanged preserves trust across the changeset.
- This is the single Mode-B documentation sync for the plan-004 changelog; the
  README changeset is owned by the parallel P4.M1.T1.S1 task (do not touch it).

## What

User-visible: a brand-new `CHANGELOG.md` with an intro and one `[Unreleased]`
block for plan-004, in the write-tech-docs style. No behavioral change to the
plugin; no other file is created or modified.

### Success Criteria

- [ ] `CHANGELOG.md` exists (created fresh; it does not exist on `main` today).
- [ ] The file begins with the `# Changelog` heading + the Keep a Changelog
      reference intro paragraph (mirroring the established format).
- [ ] ONE `## [Unreleased]: <subtitle>` block sits directly under the intro; the
      subtitle uses a COLON and names the plan-004 feature groups (no em dash).
- [ ] A `### Added` section lists exactly three feature bullets in this order:
      two-axis discovered navigation; window-flip preview + confirm-on-window;
      pane immutability.
- [ ] Two-axis bullet states: two axes, both reuse the user's own keys for that
      axis, discovered from `tmux list-keys -T root`/`-T prefix`; WINDOW axis
      (`next-window`/`previous-window`/`select-window -n`/`-p`, incl.
      `swap-window ; select-window` compounds) flips the previewed session's
      windows; SESSION axis (`switch-client -n`/`-p` + arrows) moves between
      sessions; the four `@livepicker-{session,window}-{next,prev}-keys` options
      override discovery; replaces the dropped single-axis "repurposed window-
      nav" model.
- [ ] Window-flip bullet states: flip steps through a candidate's windows live
      (preview follows each flip); confirm lands on the EXACT window being
      previewed (resolves session + window cursor, one `select-window` then
      `switch-client`); flipping never changes the candidate's own active window
      (leave-no-trace, Invariant B).
- [ ] Pane-immutability bullet states: no pane of any session is moved or resized
      (Invariant C); enforced by prevention (driver `window-size manual` + height
      pin; detached candidates pinned at link time; pane-geometry snapshot +
      drift-gated restore); `snapshot` for strict immutability.
- [ ] A defaults note states: the four nav options default to DISCOVERED;
      `@livepicker-preview-fit` default `clip`; `@livepicker-preview-defer`
      default `on`.
- [ ] An invariants bullet asserts A/B/C are unchanged (A: no `switch-client`
      while browsing / one at confirm; B: no candidate state mutation while
      browsing; C: no pane moved or resized; cancel restores driver geometry).
- [ ] An escape-hatch note names `@livepicker-preview-mode snapshot` for strict
      immutability.
- [ ] The whole file passes `bash <lint.sh path> CHANGELOG.md` (exit 0): no em
      dashes (U+2014), no ` -- `, no tell-words, no >100-word prose paragraph.
- [ ] No edits to README.md, PRD.md, scripts/, tests/, plugin.tmux, or any
      tasks.json / prd_snapshot.md. Only CHANGELOG.md is created.

## All Needed Context

### Context Completeness Check

_"If someone knew nothing about this codebase, would they have everything needed
to implement this successfully?"_ — Yes. This PRP pins the load-bearing fact
(CHANGELOG.md does not exist on `main`; create it fresh), the exact format to
mirror (the intro + the colon-form `## [Unreleased]: <subtitle>` block + the
`### Added` shape, recovered from the `prd-updates` branch and quoted), the
exact content each of the three feature bullets must contain (sourced from the
quoted PRD §8/§6.6/§7/§23/§4 selectors and verified against `scripts/options.sh`
+ `scripts/state.sh` + `scripts/input-handler.sh`), the verified defaults, the
A/B/C invariants, the snapshot escape hatch, the CORRECT write-tech-docs lint
path plus its exact rules, and the explicit decision NOT to port the prd-updates
history (so the implementer does not waste effort or import 19 em dashes). The
one trap (the "changelog" commits on main do not actually contain CHANGELOG.md)
is fully explained.

### Documentation & References

```yaml
# MUST READ — load into your context window before editing.

- file: CHANGELOG.md
  why: DOES NOT EXIST on this branch. Confirm with `test -f CHANGELOG.md` (it
        prints nothing / fails) and `git cat-file -e HEAD:CHANGELOG.md` (fatal:
        does not exist in HEAD). This task CREATES it. Do not assume it exists.
  pattern: "CREATE fresh: intro + one [Unreleased] block. Do NOT port the
        prd-updates history (see Known Gotchas #3)."

- file: /home/dustin/projects/writing-skills/skills/write-tech-docs/scripts/lint.sh
  why: THE gate. Run `bash <this> CHANGELOG.md`; MUST exit 0 (lint: 0 hit(s)).
        Verified to exist at this path. (The sibling P4.M1.T1.S1 PRP wrongly
        says the skill is absent; it looked only under ~/.pi/agent/skills/.)
        It strips fenced + inline code, then FAILS on: (1) em dashes (U+2014) or
        ' -- '; (2) the tell-word list (case-insensitive whole word: powerful,
        robust, elegant, seamless, comprehensive, cutting-edge, state-of-the-art,
        revolutionary, game-changing, next-generation, blazing-fast, lightning-fast,
        intuitive, effortless, frictionless, ultimate, stunning, beautiful,
        incredible, leverage, utilize, unlock, empower, supercharge, revolutionize,
        streamline, elevate, delve, tapestry, realm, landscape, moreover,
        furthermore, truly, incredibly); (3) a prose paragraph over 100 words
        (skips headings/lists/tables/quotes).
  critical: "because CHANGELOG.md is CREATED FRESH, rule (1) is satisfied by
        keeping new prose clean: there is no existing content to sweep. Still run
        lint.sh (or the grep fallback) as the gate."

- file: /home/dustin/projects/writing-skills/skills/write-tech-docs/SKILL.md
  why: the style contract. Hard rules: no em dashes (U+2014), use colon/paren/
        comma/period; no marketing tell-words; no hedging or formulaic
        transitions (moreover/furthermore); no narrating the codebase; no prose
        paragraph over ~4 sentences / 100 words. Active voice, one idea per
        sentence. Evidence over adjectives.
  section: "rule #1 (no em dashes) and the Reference: tell-word list."

- file: PRD.md   # READ-ONLY; do NOT edit
  why: the authoritative source for each bullet's content. The selectors quoted
        in the task brief are §1 Overview, §2 Goals/non-goals, §4 Core rule
        (Invariants A/B/C), §8 The key subsystem (two-axis navigation,
        discovered), §14 Pollution analysis (A/B/C proven). ALSO mine §6.6
        (Window navigation flip), §7 (preview subsystem), §23 (Pane immutability
        / Invariant C), and §11 (Configuration options) for the exact wording,
        defaults, and PRD refs of the three bullets.

- file: plan/004_2c5127285a90/P4M1T1S2/research/changelog_entry_findings.md
  why: THIS task's synthesis (read FIRST; it is the TL;DR). Pins the
        load-bearing fact (CHANGELOG.md absent on main; create fresh), the
        decision NOT to port history, the format template (mirrored from
        prd-updates), the three feature bullets' exact content, the verified
        defaults, the A/B/C invariants, the snapshot escape hatch, the correct
        lint path + rules, and the parallel-execution non-conflict note.

- file: scripts/options.sh   # READ-ONLY; the option set + defaults
  why: confirms the four two-axis accessors default to DISCOVERED (empty):
        opt_session_next_keys / opt_session_prev_keys / opt_window_next_keys /
        opt_window_prev_keys (lines 30-33). Confirms opt_preview_fit (clip) and
        opt_preview_defer (on). The bullets must match these. The OLD
        opt_next_key/opt_prev_key/opt_nav_* are GONE (do not mention them).

- file: scripts/state.sh   # READ-ONLY; the teardown contract
  why: confirms the new state keys exist and are torn down on exit (accuracy for
        the invariants bullet): window-cursor STATE_CAND_WIN_SESSION/_LIST/
        _CURSOR + STATE_PREVIEW_WIN_ID (P2); candidate-pin STATE_CAND_PIN_SESSION
        / STATE_CAND_PIN_WS (P3); pane-geometry ORIG_PANE_GEOMETRY (P3,
        drift-gated restore). All are members of _STATE_RUNTIME_KEYS or
        auto-cleared by clear_all_state's @livepicker-orig- grep.

- file: scripts/input-handler.sh   # READ-ONLY; the action surface
  why: confirms the flip actions exist: next-window / prev-window (the window
        axis) alongside next-session / prev-session / confirm / cancel. Grounds
        the window-flip bullet.

- file: plan/004_2c5127285a90/architecture/gap_analysis_two_axis.md   # READ-ONLY
  why: documents what changed: the OLD single-axis model (C-M-Tab/C-M-BTab
        repurposed to SESSION nav; opt_next_key/opt_prev_key) was REPLACED by the
        two-axis model. Grounds the "replaces the dropped single-axis model"
        wording in bullet 1.
  section: "Gap (a) Key model; Gap (b) Input-handler actions (next-window/prev-window added)."

- file: plan/004_2c5127285a90/architecture/pane_immutability_verification.md   # READ-ONLY
  why: the gate for the pane-immutability bullet. Decision box: detached
        candidates pinned byte-identical; client-bearing candidates CANNOT be
        pinned (manual reverts their client view) -> snapshot for strict
        immutability. State the user-visible OUTCOME in the bullet, not the recipe.
  section: "Decision box (CONDITIONAL YES: pin detached; skip client-bearing; snapshot for strict)."

- file: plan/004_2c5127285a90/P4M1T1S1/PRP.md   # READ-ONLY; parallel sibling
  why: P4.M1.T1.S1 (README) is implemented in parallel. It edits README.md ONLY
        and explicitly does NOT touch CHANGELOG.md (this task owns it). No file
        conflict. Do not depend on the README's in-flight state; keep the
        changelog entry self-contained.
```

### Current Codebase tree (run `test -f CHANGELOG.md; ls`)

```bash
tmux-livepicker/                      # branch: main @ fe07a02
├── CHANGELOG.md                      # ABSENT -> this task CREATES it
├── README.md                         # READ-ONLY here (P4.M1.T1.S1 owns the README changeset)
├── PRD.md                            # READ-ONLY (never edit)
├── scripts/
│   ├── options.sh                    # READ-ONLY — 4 two-axis accessors (default=discover); preview-fit clip; preview-defer on
│   ├── input-handler.sh              # READ-ONLY — next-window/prev-window flip actions + next/prev-session/confirm/cancel
│   ├── state.sh                      # READ-ONLY — window-cursor + candidate-pin + pane-geometry keys (all torn down on exit)
│   └── ...
├── tests/                            # READ-ONLY — run.sh must stay green; CHANGELOG not sourced by any test
│   └── test_*.sh                     #   incl. test_window_flip.sh; test_pane_immutability.sh (parallel P3.M3.T1.S1)
└── plan/004_2c5127285a90/
    ├── architecture/{gap_analysis_two_axis.md, pane_immutability_verification.md, gap_analysis_confirm_preview.md}
    └── P4M1T1S2/{PRP.md (THIS file), research/changelog_entry_findings.md}

# NOTE: a SIBLING worktree tmux-livepicker-prd-updates (branch prd-updates) has a
# CHANGELOG.md (rev-001 + rev-002 blocks, 19 em dashes, NOT swept). Do NOT copy
# it (see Known Gotchas #3). Create fresh on main.
```

### Desired Codebase tree with files to be added and responsibility of file

```bash
# ONE file created. Nothing else is created or modified by this task.
CHANGELOG.md   # CREATE:
               #   # Changelog + Keep a Changelog intro paragraph;
               #   ## [Unreleased]: <plan-004 subtitle>  (colon, no em dash);
               #   ### Added with 3 feature bullets + a defaults note + an invariants
               #     bullet + a snapshot escape-hatch note;
               #   write-tech-docs clean (no em dashes, no tell-words).
```

### Known Gotchas of our codebase & the write-tech-docs skill

```bash
# CRITICAL:

# 1. CHANGELOG.md DOES NOT EXIST on `main`. Confirm: `test -f CHANGELOG.md`
#    (fails); `git cat-file -e HEAD:CHANGELOG.md` (fatal: does not exist in HEAD);
#    `git log --oneline -- CHANGELOG.md` (empty). The "changelog" commits on main
#    (0743a53 "Tighten changelog format", f722bea "Add changelog entry for
#    plan-003...") touched README.md / plan PRP files, NOT CHANGELOG.md. => CREATE
#    the file fresh. The task contract says exactly this: "If not, create it."

# 2. Create FRESH = intro + ONE new plan-004 [Unreleased] block. Because the file
#    is new, there is NOTHING to em-dash-sweep: keep the new prose em-dash-free
#    and the lint passes. (Do not pre-emptively import old content to sweep.)

# 3. Do NOT port the prd-updates CHANGELOG history. The sibling branch
#    `prd-updates` has a CHANGELOG.md (rev-001 initial impl + rev-002 theme
#    tabs/defer), but it carries 19 em dashes (never swept there) and reflects a
#    divergent lineage; the plan-003 entry does not exist in any committed
#    CHANGELOG to restore. Porting it would import a file-wide em-dash problem and
#    expand scope. The task scope is THIS changeset ("Add an [Unreleased] entry").
#    Create fresh with the one in-scope entry.

# 4. Repo changelog convention = one `## [Unreleased]: <subtitle>` block per
#    changeset, NEWEST on top (just under the intro), COLON separator (the
#    prd-updates rev-001 header uses an em dash; do NOT copy that — use a colon).
#    Do NOT invent a version number and do NOT merge into a single accumulating
#    [Unreleased]. The task says "per the existing format" = the colon-form block.

# 5. The structural template is the prd-updates `## [Unreleased]: theme-matched
#    tabs and deferred preview` -> `### Added` block: one bullet per feature
#    (bold name + default + PRD ref + mechanism + effect), then an invariants
#    note, then an escape-hatch note. Mirror that shape. (The task's "bugfix-001
#    entry is the template" wording from plan-003 referred to the overall style;
#    here the feature-listing ### Added block is the analog.)

# 6. The write-tech-docs lint.sh path in the sibling P4.M1.T1.S1 PRP ("NOT on
#    disk") is misleading. The script EXISTS (verified) at
#    /home/dustin/projects/writing-skills/skills/write-tech-docs/scripts/lint.sh.
#    Use it. If unreachable at impl time, fall back to the grep checks in
#    Validation Level 1 (they replicate rules 1+2; rule 3 = keep paragraphs short).

# 7. lint.sh STRIPS fenced code blocks and inline code BEFORE checking, so option
#    names, commands, and key tokens (C-M-Tab, switch-client -n, etc.) inside
#    backticks are never flagged. Keep every such literal in `code` spans.

# 8. The >100-word paragraph check skips headings, lists, tables, blockquotes.
#    Write the block as bullets (mirror the template); keep any prose lead to one
#    or two short sentences.

# 9. Accuracy anchors (do not paraphrase into error):
#    - Defaults: the 4 nav options default to DISCOVERED (empty); preview-fit
#      clip; preview-defer on (scripts/options.sh).
#    - Two-axis: WINDOW axis = next-window/previous-window family; SESSION axis =
#      switch-client -n/-p + arrows; discovery drops letters/digits; the 4
#      options override (PRD §8).
#    - Confirm-on-window: resolves session + window cursor, one select-window
#      then switch-client; flips never touch the candidate's own active window
#      (Invariant B) (PRD §6.6/§7/§4).
#    - Pane immutability: driver pinned (manual + height pin); detached
#      candidates pinned at link time; pane-geometry snapshot + drift-gated
#      restore; client-bearing candidates cannot be pinned -> snapshot (PRD §23).
#    - Invariants A/B/C are UNCHANGED (PRD §4/§14).
#    - Do NOT resurrect the dropped single-axis "repurposed window-nav" model as
#      current; mention it only as what two-axis REPLACED.

# 10. Do NOT edit README.md (P4.M1.T1.S1 owns it), PRD.md, any script, any test,
#     plugin.tmux, or any tasks.json / prd_snapshot.md. This task creates
#     CHANGELOG.md ONLY. CHANGELOG is not sourced by any test, so the creation
#     cannot break tests/run.sh, but run it as a regression sanity check.
```

## Implementation Blueprint

No data models. This task creates one Markdown file: an intro + one
`[Unreleased]` block, in the write-tech-docs style.

### Implementation Tasks (ordered by dependencies)

```yaml
Task 1: READ the cited context (NO writes)
  - CONFIRM CHANGELOG.md is absent: `test -f CHANGELOG.md || echo absent`;
        `git cat-file -e HEAD:CHANGELOG.md` (fatal = absent). This task CREATES it.
  - READ: plan/004_2c5127285a90/P4M1T1S2/research/changelog_entry_findings.md
        (this task's synthesis, FIRST).
  - READ: /home/dustin/projects/writing-skills/skills/write-tech-docs/scripts/lint.sh
        (the gate; confirm the path EXISTS; note its three rules).
  - SKIM: /home/dustin/projects/writing-skills/skills/write-tech-docs/SKILL.md
        (the style rules + tell-word list).
  - SKIM: PRD.md §8 (two-axis), §6.6 + §7 (window flip + confirm-on-window),
        §23 + §4 (pane immutability + Invariants A/B/C), §14 (A/B/C proven), §11
        (options/defaults). Mine the exact wording for the three bullets.
  - CONFIRM: scripts/options.sh (4 two-axis accessors default empty=discover;
        preview-fit clip; preview-defer on) and scripts/state.sh (window-cursor +
        candidate-pin + pane-geometry keys) and scripts/input-handler.sh
        (next-window/prev-window actions).
  - SKIM: gap_analysis_two_axis.md (old single-axis REPLACED) and
        pane_immutability_verification.md Decision box (pin detached; snapshot
        for client-bearing/strict).
  - PURPOSE: internalize the intro, the three bullet contents, the defaults, the
        A/B/C invariants, the snapshot escape hatch, and the decision to create
        fresh (not port history). Do NOT edit README.md, PRD.md, scripts/, tests/.

Task 2: CREATE CHANGELOG.md with the intro + the new [Unreleased] block
  - CREATE the file. Line 1: `# Changelog`. Then a blank line. Then the intro
        paragraph: "All notable changes to tmux-livepicker are documented here.
        Format based on [Keep a Changelog](https://keepachangelog.com/)." (Mirror
        the established intro verbatim.)
  - HEADER: `## [Unreleased]: two-axis navigation, window-flip preview, pane
        immutability` (colon separator; names the three groups; NO em dash). Any
        equivalent colon-subtitled header naming the three groups is fine.
  - SECTION: `### Added`.
  - BULLET 1 — Two-axis discovered navigation (PRD §8): the picker has two
        navigation axes, and both reuse the keys the user already has for that
        axis, discovered from their live key tables. WINDOW axis (flip the
        previewed session's windows live): defaults to the user's
        `next-window`/`previous-window`/`select-window -n`/`-p` bindings
        (including `swap-window ... ; select-window` compounds). SESSION axis
        (move the highlight between candidates): defaults to `switch-client -n`/
        `-p` plus the arrow keys (`Down`/`Up`). Discovery reads
        `tmux list-keys -T root` and `-T prefix`, drops plain letters/digits
        (reserved for the query), de-duplicates, and excludes the fixed control
        keys. The four options `@livepicker-session-next-keys`/`-prev-keys`/
        `@livepicker-window-next-keys`/`-prev-keys` override discovery when set.
        This replaces the earlier single-axis "repurposed window-nav into
        session-nav" model. Low-cost revert: a modal key table switches back on
        cancel.
  - BULLET 2 — Window-flip preview + confirm-on-window (PRD §6.6, §7): flipping
        steps through a candidate's windows live, with the preview following each
        flip. Confirm lands on the EXACT window being previewed: it resolves the
        target session from the ranked list and the target window from the window
        cursor, commits that window with one `select-window`, then
        `switch-client`s, so the client arrives on the chosen session AND window.
        Flipping never changes the candidate's OWN active window (leave-no-trace,
        Invariant B): flips link the chosen window into the driver and select it
        there; no command targets the candidate session.
  - BULLET 3 — Pane immutability, Invariant C (PRD §23, §4): no pane of any
        session (candidate, driver, or bystander) is moved, resized, reordered,
        reset, or altered by browsing, confirming, or cancelling, even though the
        preview is a shared window object. Enforced by prevention: the driver is
        pinned (`window-size manual` plus a height pin) so the status grow and the
        shared preview window cannot reflow; detached candidates are pinned at
        link time and restored on leave; and a pane-geometry snapshot taken at
        activate drives a drift-gated restore on exit (restore acts only if
        geometry drifted).
  - DEFAULTS NOTE: state the defaults in one short bullet or sentence: the four
        nav options default to DISCOVERED (empty); `@livepicker-preview-fit`
        defaults to `clip`; `@livepicker-preview-defer` defaults to `on`.
  - INVARIANTS BULLET: assert that NONE of the three features changes the
        pollution/restore invariants (PRD §4/§14): A, no `switch-client` while
        browsing (the only switch is the single one at confirm, so history and
        the toggle are untouched); B, no candidate state mutation while browsing
        (flipping never changes a candidate's active window or pane layout, so
        every candidate is left exactly as found); C, no pane moved or resized
        (cancel restores the driver's window and pane geometry via the
        drift-gated restore).
  - ESCAPE-HATCH NOTE: name `@livepicker-preview-mode snapshot` as the
        strict-immutability escape hatch: it previews with `capture-pane` and
        never links (or resizes) a candidate window, so no candidate's geometry
        can ever drift (use it for client-bearing sessions, where link-time
        pinning cannot apply).
  - FOLLOW pattern: the prd-updates "theme-matched tabs" `### Added` bullet
        density (bold name, default, PRD ref, mechanism, effect; one or two
        sentences each).
  - GOTCHA: keep every option/key/command literal in `code` spans. No em dashes.
        No tell-words. No prose paragraph over ~100 words (use bullets).

Task 3: VALIDATE (see Validation Loop) — lint gate + content grep checks + regression.
```

### Implementation Patterns & Key Details

```markdown
<!-- Pattern: a feature bullet in the established style. Bold name, default, PRD
     ref, mechanism, effect. One or two sentences. Every literal in a code span. -->

- **Two-axis discovered navigation** (PRD §8). The picker now has two navigation
  axes, and both reuse the keys you already have for that axis, discovered from
  your live key tables. The window axis flips the previewed session's windows
  (`next-window` / `previous-window` / `select-window -n` / `-p`, including your
  `swap-window ... ; select-window` compounds); the session axis moves the
  highlight between sessions (`switch-client -n` / `-p` plus the arrow keys). The
  four `@livepicker-session-next-keys` / `-prev-keys` /
  `@livepicker-window-next-keys` / `-prev-keys` options override discovery when
  set; otherwise discovery reads `tmux list-keys -T root` and `-T prefix`, drops
  plain letters and digits (reserved for the query), and de-duplicates. This
  replaces the earlier single-axis model that repurposed window-nav into
  session-nav.

<!-- Pattern: the invariants bullet. Assert A/B/C are unchanged. -->

- None of these changes the invariants the plugin already upholds (PRD §4 / §14).
  Browsing still never calls `switch-client` (Invariant A): the only switch is the
  single one at confirm, so the `tmux-session-history` timeline and the toggle are
  untouched. Flipping never changes a candidate's own active window or pane layout
  (Invariant B): every peeked session is left exactly as you found it. And no pane
  of any session is moved or resized (Invariant C): cancel restores the driver's
  window and pane geometry through the drift-gated restore.

<!-- Pattern: the escape-hatch note. Name the option and what it avoids. -->

- For strict pane immutability across every session (including client-bearing
  candidates that cannot be pinned at link time), set
  `@livepicker-preview-mode snapshot`: it previews with `capture-pane` and never
  links or resizes a candidate window, so no candidate's geometry can drift.

<!-- Anti-pattern: do NOT write the pin recipe ("set-option -t manual then
     resize-window -y H0"). State the outcome (no pane moved or resized; bottom
     row clipped) and name snapshot as the strict escape. -->
```

### Integration Points

```yaml
CHANGELOG.md (the only integration surface; CREATED fresh):
  - Intro: `# Changelog` heading + Keep a Changelog reference paragraph.
  - One `## [Unreleased]: <three-group subtitle>` block (colon, newest-first).
  - `### Added`: 3 feature bullets + a defaults note + an invariants bullet +
        a snapshot escape-hatch note.
  - Style: write-tech-docs clean (no em dashes, no tell-words).

NO other integration:
  - Do NOT edit README.md (P4.M1.T1.S1 owns it), PRD.md, any script in scripts/,
        any test in tests/, plugin.tmux, or any tasks.json / prd_snapshot.md.
  - Do NOT copy the prd-updates branch's CHANGELOG.md (divergent lineage; 19 em
        dashes; out of scope).
```

## Validation Loop

### Level 1: Style gate (write-tech-docs linter)

```bash
cd /home/dustin/.config/tmux/plugins/tmux-livepicker
# PRIMARY gate. Use the REAL path (verified to exist; the sibling PRP's "absent"
# note only checked ~/.pi/agent/skills/):
bash /home/dustin/projects/writing-skills/skills/write-tech-docs/scripts/lint.sh CHANGELOG.md
# Expected: "lint: 0 hit(s)" and exit 0. lint.sh strips fenced + inline code,
# then flags em dashes (U+2014) / " -- ", the tell-word list (case-insensitive
# whole word), and >100-word prose paragraphs (skips headings/lists/tables/
# quotes). Because the file is created fresh, fixing any hit is just editing your
# own new prose (there is no imported content to sweep).

# FALLBACK if the script path is unreachable (replicates lint rules 1 + 2):
grep -nP '\x{2014}| -- ' CHANGELOG.md          # MUST be empty
grep -niEw 'powerful|robust|elegant|seamless|comprehensive|cutting-edge|state-of-the-art|revolutionary|game-changing|next-generation|blazing-fast|lightning-fast|intuitive|effortless|frictionless|ultimate|stunning|beautiful|incredible|leverage|utilize|unlock|empower|supercharge|revolutionize|streamline|elevate|delve|tapestry|realm|landscape|moreover|furthermore|truly|incredibly' CHANGELOG.md  # MUST be empty
```

### Level 2: Content + structure checks

```bash
cd /home/dustin/.config/tmux/plugins/tmux-livepicker
# File exists (created):
test -f CHANGELOG.md && echo "CHANGELOG exists"
# Intro present:
head -1 CHANGELOG.md | grep -q '^# Changelog' && echo "intro OK"
grep -q 'keepachangelog.com' CHANGELOG.md && echo "KaC ref OK"
# Exactly one [Unreleased] block, colon form (no em dash in the header):
grep -cE '^## \[Unreleased\]' CHANGELOG.md                       # == 1
grep -nE '^## \[Unreleased\]' CHANGELOG.md | grep -q ':'         # colon form
grep -P '^\#\# \[Unreleased\] \x{2014}' CHANGELOG.md             # MUST be empty (no em-dash header)
# Three feature groups named:
grep -niE 'two-axis|discovered' CHANGELOG.md                     # two-axis nav
grep -niE 'flip|window being previewed|confirm' CHANGELOG.md     # window-flip + confirm-on-window
grep -niE 'pane immutab|Invariant C|no pane' CHANGELOG.md        # pane immutability
# Defaults present:
grep -niE 'discover|preview-fit.*clip|preview-defer.*on' CHANGELOG.md
# Invariants A/B/C named:
grep -niE 'Invariant [ABC]|switch-client|client-session-changed' CHANGELOG.md
# Escape hatch named:
grep -niE 'preview-mode snapshot|capture-pane' CHANGELOG.md
# Dropped single-axis model mentioned only as REPLACED, not current:
grep -niE 'repurposed|replaces' CHANGELOG.md
```

### Level 3: Regression (doc-only change must not break the suite)

```bash
cd /home/dustin/.config/tmux/plugins/tmux-livepicker
bash tests/run.sh
# Expected: exit 0. CHANGELOG is not sourced by any test, so this is a sanity
# check that nothing else was touched. Confirm the change is doc-only:
git status --short README.md scripts/ tests/ plugin.tmux PRD.md   # MUST be empty
# And that CHANGELOG.md is the only new tracked/untracked artifact (plus the
# plan/ PRP/research, which are out of the repo's functional tree):
git status --short | grep -v '^?? plan/' | grep -v 'plan/.*tasks.json'
```

### Level 4: Readability + format sanity (manual)

```bash
cd /home/dustin/.config/tmux/plugins/tmux-livepicker
# Read the new block top-to-bottom as a user would. Confirm it reads as a
# coherent overview: three features -> defaults -> invariants A/B/C unchanged ->
# snapshot escape hatch. Confirm the header uses a colon (no em dash) and the
# block is newest-first under the intro.
# Confirm no em dash survived: grep -nP '\x{2014}' CHANGELOG.md  (empty).
# Optional render: mdcat CHANGELOG.md | head -40   # or: glow CHANGELOG.md
```

## Final Validation Checklist

### Technical Validation
- [ ] Level 1: `bash /home/dustin/projects/writing-skills/skills/write-tech-docs/scripts/lint.sh CHANGELOG.md` exits 0 (`lint: 0 hit(s)`). (Fallback greps in Level 1 are empty if the script is unreachable.)
- [ ] Level 2: the file exists; the intro + exactly one colon-form `[Unreleased]` block + the three feature groups + defaults + invariants A/B/C + the snapshot escape hatch are all present and accurate; no em-dash header.
- [ ] Level 3: `bash tests/run.sh` exits 0; `git status --short README.md scripts/ tests/ plugin.tmux PRD.md` is empty (only CHANGELOG.md is new).
- [ ] Level 4: the block reads coherently; no em dash anywhere (`grep -nP '\x{2014}' CHANGELOG.md` empty).

### Feature Validation
- [ ] Two-axis bullet: window axis (next-window family) flips windows; session axis (switch-client -n/-p + arrows) moves sessions; both discovered from `list-keys -T root`/`-T prefix`; the four options override; replaces the dropped single-axis model.
- [ ] Window-flip bullet: flip steps through a candidate's windows live; confirm lands on the exact previewed window (session + window cursor, one select-window then switch-client); flipping never changes the candidate's own active window (Invariant B).
- [ ] Pane-immutability bullet: no pane moved or resized (Invariant C); prevention via driver pin + detached-candidate pin + pane-geometry drift-gated restore; snapshot for strict immutability.
- [ ] Defaults note: axes discovered; preview-fit clip; preview-defer on.
- [ ] Invariants bullet: A/B/C unchanged.
- [ ] Escape-hatch note: `@livepicker-preview-mode snapshot`.

### Code Quality Validation
- [ ] New prose follows write-tech-docs style (active voice, one idea per sentence, evidence over adjectives, consistent terminology).
- [ ] Every option/key/command literal is in a `code` span.
- [ ] No prose paragraph over ~4 sentences / 100 words; long material is bulleted (mirrors the template).
- [ ] No fabricated history; only the one in-scope plan-004 entry is added.

### Documentation & Deployment
- [ ] No edits to README.md (P4.M1.T1.S1 owns it), PRD.md, scripts/, tests/, plugin.tmux, or any tasks.json / prd_snapshot.md.
- [ ] The new block follows the repo's `## [Unreleased]: <subtitle>` convention (newest-first, colon separator), not a version number or a single accumulating [Unreleased].

---

## Anti-Patterns to Avoid

- ❌ Don't assume CHANGELOG.md exists. It does NOT exist on `main` (not in the working tree, not in HEAD, never committed here). The "changelog" commits on main touched README/PRP files. CREATE the file fresh. Confirm with `test -f CHANGELOG.md` and `git cat-file -e HEAD:CHANGELOG.md`.
- ❌ Don't port the prd-updates CHANGELOG history. That branch's CHANGELOG has 19 em dashes (never swept), reflects a divergent lineage, and the plan-003 entry does not exist in any committed CHANGELOG to restore. Porting it imports a file-wide em-dash problem and expands scope. Create fresh with the one in-scope entry.
- ❌ Don't edit README.md (P4.M1.T1.S1 owns it), PRD.md, any script, any test, plugin.tmux, or any tasks.json. This task creates CHANGELOG.md ONLY.
- ❌ Don't use the lint path conclusion from the sibling PRP ("absent"). The script EXISTS at `/home/dustin/projects/writing-skills/skills/write-tech-docs/scripts/lint.sh` (verified). Use it, or the grep fallback.
- ❌ Don't use an em dash in the header (or anywhere). Use the colon form `## [Unreleased]: <subtitle>` (the prd-updates rev-001 header uses an em dash; do not copy it). Never substitute ` -- ` or a bare hyphen.
- ❌ Don't merge the entry into a single accumulating `[Unreleased]` or invent a version number. One `## [Unreleased]: <subtitle>` block per changeset, newest-first.
- ❌ Don't resurrect the dropped single-axis "repurposed window-nav into session-nav" model as current behavior. Mention it only as what the two-axis model REPLACED.
- ❌ Don't mis-state the pane-immutability mechanism. The OUTCOME is "no pane moved or resized". Do NOT claim link-time pinning fixes client-bearing candidates (it cannot; manual reverts their client view). Name `snapshot` as the strict escape. Don't write the pin recipe.
- ❌ Don't invent defaults. They are: the four nav options default to DISCOVERED (empty); preview-fit clip; preview-defer on (scripts/options.sh).
- ❌ Don't write marketing tell-words (powerful, seamless, comprehensive, leverage, streamline, ...) or formulaic transitions (moreover, furthermore). State facts.
- ❌ Don't hardcode a stale test count. If you cite the suite size, run `bash tests/run.sh` and record the real number (currently ~96 across 16 files). Citing a count is optional; the template's Added block did not cite one.

---

## Confidence Score: 9/10

This is a documentation task that creates a single, well-bounded file. The
load-bearing fact (CHANGELOG.md is absent on `main` and must be created fresh,
NOT ported from the divergent `prd-updates` branch) is established and explained,
which removes the biggest risk (wasting effort importing/sweeping 19 em dashes or
fabricating history). Each bullet's content is sourced from the quoted PRD
selectors (§8/§6.6/§7/§23/§4/§14) and verified against `scripts/options.sh`
(defaults), `scripts/state.sh` (the new teardown keys), and
`scripts/input-handler.sh` (the flip actions). The format is pinned to the
established `# Changelog` intro + colon-form `## [Unreleased]: <subtitle>` block +
`### Added` shape (recovered from `prd-updates`). Because the file is new, the
em-dash gate is satisfied by keeping new prose clean (no sweep needed). The
write-tech-docs lint path is resolved with the verified real path plus a grep
fallback. The parallel P4.M1.T1.S1 task edits README.md only, so there is no file
conflict. The implementer's job is to create CHANGELOG.md with the intro + three
content blocks + defaults + invariants + escape hatch and pass the lint, not to
discover what the features do or to resolve git branch strategy.
