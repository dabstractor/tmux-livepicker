name: "P4.M1.T1.S1 — Update README.md with two-axis nav + window-flip + confirm-on-window prose"
description: |

  Documentation-only task (Mode B). Edits ONE file: `README.md`. No code, no
  PRD, no CHANGELOG (P4.M1.T1.S2 owns that entry). The plan-004 changeset
  (two-axis key discovery, window-flip, confirm-on-window, pane-immutability)
  shipped its Mode-A README edits scattered across the Configuration table, the
  Usage numbered steps, and Known limitations, and several lines still describe
  the OLD single-axis "repurposed window-nav" model (the design PRD §8
  explicitly dropped). This task: (a) add a `### Two-axis navigation` subsection
  (session axis = switch-client -n/-p + arrows, moves between sessions; window
  axis = next-window/previous-window, flips the previewed session's windows live;
  both discovered from your config, overridable via the four `*-keys` options);
  (b) add a `### Window preview` note (confirm lands on the exact window being
  previewed; flipping never changes the candidate's own active window =
  leave-no-trace); (c) verify the `### Known limitations` reconciliation with §23
  (detached candidates pinned in clip mode; snapshot for strict immutability);
  (d) ensure the Configuration table has the four two-axis options with
  (discovered) defaults + the non-alphanumeric constraint; (e) fix the stale
  single-axis references (Overview, Goals, User stories, Validation) and remove
  the 2 em dashes, following the write-tech-docs rules (no em dashes, no
  tell-words). The write-tech-docs skill/lint is NOT on disk in this environment,
  so the rules are encoded below and the gate is grep-based.

---

## Goal

**Feature Goal**: `README.md` documents the two-axis + window-flip +
confirm-on-window + leave-no-trace feature set as coherent prose, with no stale
single-axis references and no style-rule violations.

**Deliverable**: An edited `README.md` containing:
1. A new `### Two-axis navigation` subsection (the two axes, discovery from your
   config, the four override options, the non-alphanumeric constraint).
2. A new `### Window preview` note (confirm lands on the exact previewed window;
   flipping never changes the candidate's own active window).
3. The four two-axis options present in the Configuration table with
   `(discovered)` defaults and the non-alphanumeric constraint (verify; they
   appear already present).
4. The `### Known limitations` reconciliation with §23 verified coherent
   (detached candidates pinned in clip mode; snapshot for strict immutability).
5. All stale single-axis references fixed (Overview, Goals, User stories,
   Validation) so nothing says window keys "move the selection to a different
   session" or calls the model "repurposed navigation".
6. No em dashes, no tell-words (write-tech-docs gate).

**Success Definition**: A reader who knows nothing about the codebase can, from
the README alone, describe the two navigation axes and which keys drive each,
that confirm lands on the exact previewed window, that flipping never disturbs a
candidate's own state, and the clip/snapshot tradeoff for pane immutability. The
grep gates pass (0 em dashes, 0 tell-words, stale refs gone, both subsections
present). `bash tests/run.sh` still exits 0 (doc-only change).

## User Persona (if applicable)

**Target User**: A tmux user configuring tmux-livepicker (wants to know which
keys navigate sessions vs flip windows, and what confirm does), and the
maintainer who writes the CHANGELOG (P4.M1.T1.S2) from this README afterward.

**Use Case**: Read Configuration + Two-axis navigation + Window preview to
understand the key model and the preview/confirm behavior without reading the
PRD or the shell scripts.

**User Journey**: Install -> Configuration table (the four two-axis options) ->
Two-axis navigation (which keys do what, discovery, the override) -> Usage
(activate, filter, navigate sessions, flip windows, confirm, cancel) -> Window
preview / How it works (leave-no-trace + confirm-on-window) -> Known limitations
(clip vs snapshot).

**Pain Points Addressed**: The current README's Overview, Goals, and User
stories still describe the dropped single-axis model (window keys moving the
session selection), which is now wrong and confuses a reader; the two-axis
feature is only documented as scattered table rows and Usage bullets with no
coherent overview.

## Why

- The two-axis/window-flip/confirm-on-window feature shipped, but the README's
  headline sections (Overview, Goals, User stories) still describe the OLD
  single-axis model and even contradict the shipped behavior (window keys no
  longer move the session selection; they flip windows).
- The two-axis key model is non-obvious (two axes, both discovered from the
  user's own config, overridable) and deserves one coherent subsection instead
  of scattered table rows + Usage bullets.
- This is the single Mode-B documentation sync for the plan-004 changeset; the
  CHANGELOG (P4.M1.T1.S2) is written from this README afterward.

## What

User-visible: the README gains two new subsections, several stale lines are
corrected, and the file passes the style gates. No behavioral change to the
plugin.

### Success Criteria

- [ ] `### Two-axis navigation` subsection exists and describes the session axis (`switch-client -n`/`-p` + arrows, moves between sessions) and the window axis (`next-window`/`previous-window` family, flips the previewed session's windows live), that both are discovered from your config when the option is unset, and that the four `@livepicker-{session,window}-{next,prev}-keys` options override discovery. It states the non-alphanumeric constraint.
- [ ] `### Window preview` note exists and states confirm lands on the exact window being previewed, and that flipping never changes the candidate's own active window (leave-no-trace).
- [ ] The Configuration table has the four two-axis options with `(discovered)` defaults and the non-alphanumeric constraint (verify present; do not duplicate).
- [ ] `### Known limitations` coherently reconciles the detached-candidate resize with §23: status-grow reflow fixed by default `clip`; detached candidates pinned in `clip` mode; client-bearing candidates cannot be pinned so use `snapshot` for strict immutability; `reflow` is the legacy escape hatch.
- [ ] No stale single-axis references remain: nothing says the model is "repurposed navigation"; nothing says window keys "move the selection to a different session"; the Overview, Goals, User stories, and Validation lines are corrected.
- [ ] `grep -cP '\x{2014}' README.md` == 0 (no em dashes); no tell-words.

## All Needed Context

### Context Completeness Check

_"If someone knew nothing about this codebase, would they have everything needed
to implement this successfully?"_ — Yes. This PRP pins the current README
structure (with line numbers), every stale reference and its exact fix, the
content each new/edited section must contain (quoted from the PRD sections that
govern it: §8, §6, §4, §2, §3, §23), the §23 reconciliation facts, the
write-tech-docs rules (encoded directly because the skill/lint is not on disk
here), the parallel-context note (P3.M3.T1.S1 is a test file, no README overlap),
and the executable grep-based validation. No guessing about what the features do
is required.

### Documentation & References

```yaml
# MUST READ — load into your context window before editing.

- file: README.md
  why: THE file being edited. Read it FULLY first. Note the structure (## / ###
        with line numbers), the four two-axis table rows (~L101-104), the Usage
        steps 3-5 (~L159-173), the ### Status line / ### Session management
        subsections, and the STALE lines: Overview ~L11 ("usual window-navigation
        keys"), Goals ~L24 ("Filter + repurposed navigation"), User stories ~L45
        ("next/previous window keys ... selection moves to a different session"),
        User stories ~L50 ("land on the selected session"), Validation ~L253
        ("Key repurpose"). Note the 2 em dashes at ~L103 and ~L169.
  pattern: "edit in place; add the two subsections; fix the stale lines; remove
        em dashes. Do NOT rewrite sections that are already correct."

- file: plan/004_2c5127285a90/P4M1T1S1/research/readme_sync_findings.md
  why: THIS task's synthesis. The stale-reference table, the two new subsections
        mapped to exact PRD content, the §23 facts, the write-tech-docs rules
        (skill NOT on disk), placement recommendations, and the grep-based gate.
        Read FIRST; it is the TL;DR.

- file: PRD.md   # READ-ONLY; never edit
  why: the authoritative source. Mine these sections for the exact prose:
        §1 Overview (two-axis description), §2 Goals (two-axis + confirm-on-window
        + leave-no-trace goals), §3 User stories (the two-axis navigate + flip +
        confirm-on-window stories), §6 Behaviors (Window navigation flip +
        Confirm-on-window + Cancel hard-reset), §8 The key subsystem (the two
        axes, discovery, binding order, non-alphanumeric constraint), §23 Pane
        immutability (Invariant C; clip/snapshot). The selectors in the task
        brief quote §1/§2/§3/§6/§8/§11; also read §4 (Invariants A/B/C) and §23
        for the Window-preview / leave-no-trace wording.

- file: plan/004_2c5127285a90/architecture/gap_analysis_two_axis.md
  why: documents what the changeset CHANGED: the OLD single-axis model
        (C-M-Tab/C-M-BTab repurposed to SESSION nav; opt_next_key/opt_prev_key)
        was REPLACED by the two-axis model (session axis + window axis). This is
        why the README's "repurposed navigation" / "next/previous window keys
        move the session selection" wording is now WRONG and must be fixed.
  section: "Gap (a) Key model; Gap (b) Input-handler actions (next-window/prev-window added)."

- file: plan/004_2c5127285a90/architecture/gap_analysis_confirm_preview.md
  why: documents the confirm-on-window change: confirm NOW resolves the window
        from the window cursor and commits it with select-window -t "=$S:$W"
        (it used to switch-client only). Grounds the Window-preview "confirm
        lands on the exact window" prose.
  section: "(b) Confirm resolves session only -> now (session, window); (c) the changes."

- file: plan/004_2c5127285a90/architecture/pane_immutability_verification.md
  why: THE gate for the §23 limitation reconciliation (deliverable c). Decision
        box: detached candidates pinned byte-identical; client-bearing candidates
        CANNOT be pinned (manual reverts their client view) -> snapshot for strict
        immutability. Grounds the Known-limitations text. Verify the current
        README text matches this; fix only if it drifted.
  section: "Decision box (CONDITIONAL YES: pin detached; skip client-bearing; snapshot for strict)."

- file: scripts/options.sh   # READ-ONLY; the option set
  why: confirms the live two-axis option names + defaults so the table matches
        the code. The four accessors are opt_session_next_keys /
        opt_session_prev_keys / opt_window_next_keys / opt_window_prev_keys
        (defaults discovered; the OLD opt_next_key/opt_prev_key/opt_nav_* are
        GONE). Confirm the table does not list any retired option.
  pattern: "grep -nE 'opt_(session|window)_(next|prev)_keys' scripts/options.sh for the 4 accessors."

- file: plan/004_2c5127285a90/P3M3T1S1/PRP.md   # READ-ONLY; PARALLEL context
  why: P3.M3.T1.S1 is implementing tests/test_pane_immutability.sh IN PARALLEL.
        It is a TEST file only; it does NOT touch README.md. So there is NO
        README overlap with this task. (Its existence just means the Validation
        cluster list should eventually mention a pane-immutability suite; reflect
        the ACTUAL tests/ contents via `ls tests/test_*.sh`.)
  section: "Deliverable (ONE test file, no README edit)."
```

### Current Codebase tree (run `grep -nE '^#{2,3} ' README.md` + `ls tests/test_*.sh`)

```bash
tmux-livepicker/
├── README.md                 # <- THE ONLY FILE EDITED BY THIS TASK
├── CHANGELOG.md              # READ-ONLY here (P4.M1.T1.S2 owns the new entry)
├── PRD.md                    # READ-ONLY (never edit)
├── scripts/                  # READ-ONLY (options.sh = the 4 two-axis accessors; input-handler.sh = next-window/prev-window/confirm)
│   ├── options.sh            #   opt_session/window_next/prev_keys (discovered); OLD opt_next_key etc. GONE
│   ├── input-handler.sh      #   type|backspace|next-session|prev-session|next-window|prev-window|confirm|cancel|rename|delete
│   └── ...
├── tests/                    # READ-ONLY (run.sh must stay green; README not sourced by any test)
│   ├── test_*.sh             #   run `ls tests/test_*.sh` to list the actual suites for the Validation section
│   └── run.sh
└── plan/004_2c5127285a90/
    ├── architecture/{gap_analysis_two_axis.md, gap_analysis_confirm_preview.md, pane_immutability_verification.md}
    ├── P3M3T1S1/PRP.md       # parallel TEST task (no README overlap)
    └── P4M1T1S1/{PRP.md (THIS file), research/readme_sync_findings.md}
```

### Desired Codebase tree with files to be added and responsibility of file

```bash
# ONE file modified. Nothing else is created or modified by this task.
README.md   # EDIT in place:
            # + ### Two-axis navigation (the two axes + discovery + override + constraint)
            # + ### Window preview (confirm-on-window + leave-no-trace)
            # ~ Overview / Goals / User stories / Validation: fix stale single-axis wording
            # ~ ### Known limitations: verify the §23 reconciliation is coherent (de-em-dash only if needed)
            # ~ remove the 2 em dashes (L103, L169) so the grep gate passes
```

### Known Gotchas of our codebase & the write-tech-docs rules

```bash
# CRITICAL:

# 1. The write-tech-docs SKILL and its lint.sh are NOT on disk in this environment
#    (/home/dustin/.pi/agent/skills/write-tech-docs/ is absent; not in available_skills).
#    Apply the rules manually (encoded above in the research synthesis / Validation):
#    no em dashes (U+2014); no tell-words; no >100-word prose paragraphs; no narrating
#    the codebase; active voice; one idea per sentence. Gate = grep (see Validation).
#    IF the skill IS present at implementation time, also run lint.sh and require exit 0.

# 2. The README has 2 em dashes today (L103 table cell "window axis - flip"; L169
#    "untouched - you are only looking"). Both must go. Replace with a colon or
#    parentheses. NEVER use ' -- ' or a bare hyphen as a stand-in.

# 3. The single-axis wording is the headline trap. These lines describe the DROPPED
#    design and must be corrected, not merely supplemented:
#      Overview ~L11: "move the selection with your usual window-navigation keys"
#      Goals ~L24: "**Filter + repurposed navigation.**"
#      User stories ~L45: "I press my next/previous window keys and the selection
#        moves to a different session"  (WRONG: window keys flip windows now)
#      User stories ~L50: "land on the selected session"  (now: session AND window)
#      Validation ~L253: "**Key repurpose:** repurposed window-nav keys revert on cancel."
#    PRD §8 explicitly DROPPED the "repurposed window-nav into session-nav" design;
#    the README must not resurrect it.

# 4. Do NOT duplicate the four two-axis table rows (they are already present) and do
#    NOT duplicate the full discovery algorithm in BOTH the subsection and the Usage
#    steps. The subsection is the overview; the Usage steps are the how-to. Point one
#    at the other. Likewise keep the Window-preview note and the flip/confirm Usage
#    steps consistent, not verbatim copies.

# 5. lint.sh (if available) strips fenced code blocks and inline code BEFORE checking,
#    so option names / key tokens inside backticks are never flagged. Keep every
#    `@livepicker-*` name and key token (C-M-Tab, etc.) in `code` spans regardless.

# 6. The >100-word paragraph check (if lint is used) skips headings, lists, tables,
#    and blockquotes. Write the new subsections as short prose + bullets, not long
#    paragraphs.

# 7. P3.M3.T1.S1 (parallel) writes tests/test_pane_immutability.sh ONLY. It does NOT
#    touch README.md. Do NOT coordinate on the README; just reflect the actual
#    tests/ contents in the Validation cluster list via `ls tests/test_*.sh`.

# 8. Do NOT narrate the codebase (skill rule). Document what each axis DOES, how to
#    override it, what confirm does, and the leave-no-trace guarantee. Do not walk
#    through scripts/options.sh or scripts/input-handler.sh.

# 9. README is NOT sourced by any test. The edit cannot break tests/run.sh; run it
#    anyway as a regression sanity check (Level 3).
```

## Implementation Blueprint

No data models. This task edits one Markdown file: two new subsections, several
in-place line fixes, an em-dash removal, and a Verification-section cluster
refresh, in dependency order.

### Implementation Tasks (ordered by dependencies)

```yaml
Task 1: READ the cited context (NO writes)
  - READ: README.md FULLY. Note the structure (## / ### + line numbers), the four
        two-axis table rows (~L101-104), Usage steps 3-5 (~L159-173), the ### Status
        line / ### Session management subsections, ### Known limitations, and the
        STALE lines (Overview ~L11, Goals ~L24, User stories ~L45 + ~L50, Validation
        ~L253) and the 2 em dashes (~L103, ~L169).
  - READ: plan/004_2c5127285a90/P4M1T1S1/research/readme_sync_findings.md (FIRST; TL;DR).
  - READ: PRD.md §1, §2, §3, §6 (Window navigation + Confirm + Cancel), §8 (the key
        subsystem), §4 (Invariants A/B/C), §23 (pane immutability). Mine the exact
        wording for the new prose.
  - SKIM: gap_analysis_two_axis.md + gap_analysis_confirm_preview.md (what changed
        and why the old wording is wrong) and pane_immutability_verification.md
        (Decision box, for the Known-limitations reconciliation).
  - SKIM: scripts/options.sh (confirm the 4 two-axis accessors; the OLD
        opt_next_key/opt_prev_key/opt_nav_* are GONE).
  - RUN: `ls tests/test_*.sh` to list the actual suites for the Validation section.
  - PURPOSE: internalize the two new subsections, the stale-ref fixes, the §23
        facts, and the style rules. Do NOT edit PRD.md, CHANGELOG.md, any script,
        any test, or any tasks.json.

Task 2: ADD the "### Two-axis navigation" subsection (deliverable a; PRD §8 + §2 + §3)
  - PLACE: a new `### Two-axis navigation` subsection under `## Configuration`, after
        `### Status line` (~L154). (A standalone ## section between Configuration and
        Usage is also acceptable; pick one and be consistent.)
  - WRITE concise prose + bullets. Cover ALL of:
        * Two axes, both reusing the keys the user already has for that axis,
          discovered from their live key tables; both overridable.
        * SESSION axis (move the highlight between candidate sessions): defaults to
          the user's `switch-client -n` / `-p` bindings plus the arrow keys
          (`Down` next, `Up` prev). Override: `@livepicker-session-next-keys` /
          `@livepicker-session-prev-keys`.
        * WINDOW axis (flip the highlighted session's windows in the preview, live):
          defaults to the user's `next-window` / `previous-window` / `select-window -n`
          / `-p` bindings (incl. `swap-window ... ; select-window` compounds).
          Override: `@livepicker-window-next-keys` / `@livepicker-window-prev-keys`.
        * Discovery runs only when the option is unset: it reads `tmux list-keys -T
          root` and `-T prefix`, matches the window-axis command substrings and the
          session-axis `switch-client -n`/`-p` (not `-l` toggle or `-t <name>`),
          always adds the arrows to the session axis, drops plain letters/digits
          (reserved for the query), and de-duplicates.
        * Non-alphanumeric constraint: every nav/confirm/cancel/backspace/
          rename/delete key is non-alphanumeric; a plain letter/digit used for nav is
          silently untypeable. Vim-style `j`/`k` session-nav is possible only by
          setting the option explicitly (those letters then cannot be typed).
        * Low-cost revert: the picker uses a modal key table; on cancel the table
          switches back (typically `root`), so the bindings revert for free.
  - NAMING: heading `### Two-axis navigation`. Reference options/keys in `code` spans.
  - FOLLOW pattern: the existing ### Appearance / ### Status line subsections (short
        prose + bullets, option references in code spans).
  - GOTCHA: do NOT restate the full binding order from PRD §8 step-by-step; this is a
        user-facing overview, not the implementation runbook. Do NOT duplicate the
        four table rows.

Task 3: ADD the "### Window preview" note (deliverable b; PRD §6 + §4 Invariants)
  - PLACE: a new `### Window preview` subsection under `## How it works` (before or
        after ### Known limitations). (A ### under ## Usage alongside ### Session
        management is also acceptable.)
  - WRITE concise prose. Cover BOTH facts:
        * Confirm lands on the EXACT window being previewed: confirm resolves the
          target session S from the ranked list and the target window W from the
          window cursor (the window currently previewed for S), commits W in S with
          one `select-window`, then `switch-client`s; the client lands on (S, W).
          (For the self-session, or `snapshot`/`off` preview modes with no chosen
          window, W is the session's active window.)
        * Flipping never changes the candidate's own active window (leave-no-trace):
          window-nav flips link the chosen window into the driver and select it
          THERE; they never call `select-window` on the candidate session, so the
          candidate's own active window and pane layout never change while browsing
          (Invariant B). Moving to another session, or cancelling, leaves every
          peeked candidate exactly as it was. Confirm is the ONE deliberate
          mutation (the single `select-window` that commits the chosen window);
          everything else is read-only. (Pane geometry across ALL sessions is the
          stronger §23 guarantee; see Known limitations.)
  - NAMING: heading `### Window preview`. Reference keys/options/format-specifiers in
        `code` spans.
  - FOLLOW pattern: the existing ## How it works paragraph (active voice, fact-first).
  - GOTCHA: keep it to the two facts. Do not re-derive the link-window mechanism
        (that is the existing "How it works" paragraph's job); reference it.

Task 4: VERIFY + tighten the "### Known limitations" §23 reconciliation (deliverable c)
  - READ the current ### Known limitations. It should already distinguish:
        (1) status-grow reflow fixed by default `clip`;
        (2) detached candidates PINNED at link time in `clip` mode (window-size +
            height pin, restored on leave) -> no reflow, own session keeps original
            geometry;
        (3) client-bearing candidates CANNOT be pinned (manual reverts their client
            view) -> for STRICT pane-immutability use `@livepicker-preview-mode
            snapshot`; `reflow` is the legacy escape hatch (candidates resize at link
            time), so use `clip` (default) or `snapshot`.
  - IF it already states this coherently: leave it, only de-em-dash if needed. IF it
        drifted or omits the client-bearing / snapshot point, correct it to match the
        Decision box of pane_immutability_verification.md. Do NOT rewrite wholesale.
  - GOTCHA: the pin is CONDITIONAL on the candidate having NO attached client
        (detached). State that. Do NOT claim clip fixes client-bearing candidates.

Task 5: VERIFY the Configuration table has the four two-axis options (deliverable d)
  - CONFIRM the table already contains `@livepicker-session-next-keys`,
        `@livepicker-session-prev-keys`, `@livepicker-window-next-keys`,
        `@livepicker-window-prev-keys`, each with the `(discovered)` default and the
        "Must be non-alphanumeric; a plain letter/digit is intercepted and not
        typeable" constraint (PRD §11). They are present; if any is missing or
        mis-stated, add/fix it. Do NOT duplicate.
  - GOTCHA: the OLD options (@livepicker-next-key, -prev-key, -nav-next-keys,
        -nav-prev-keys) are RETIRED. Ensure NONE of them remain in the table
        (`grep -n '@livepicker-next-key\|@livepicker-prev-key\|@livepicker-nav-' README.md`
        must be empty).

Task 6: FIX the stale single-axis references (the headline trap)
  - Overview (~L11): replace "move the selection with your usual window-navigation
        keys" with the two-axis description: move between sessions with your
        session-nav keys and flip the highlighted session's windows with your
        window-nav keys, both discovered from your config.
  - Goals (~L24): replace the "Filter + repurposed navigation" goal. State two-axis
        navigation (move between sessions with the session-nav keys; flip a session's
        windows with the window-nav keys, both discovered from your config). ADD a
        confirm-on-window goal (confirm lands on the session AND the exact window
        being previewed) and a leave-no-trace goal (flipping never changes a
        candidate's active window or any pane; cancel restores everything). Mirror
        PRD §2's wording.
  - User stories (~L45 Navigate bullet): SPLIT into a session-nav story (press a
        session-nav key, the highlight moves to the next session, preview follows) and
        a window-nav story (press a window-nav key, the preview flips to that
        session's next window live; the session's own active window is unchanged; you
        are only looking). Mirror PRD §3's two-axis stories. The current "next/
        previous window keys ... selection moves to a different session" is WRONG.
  - User stories (~L50 Confirm bullet): change "land on the selected session" to
        "land on the chosen session AND the exact window being previewed".
  - Validation (~L253): replace "Key repurpose: repurposed window-nav keys revert on
        cancel" with two-axis / key-discovery terminology, and REFRESH the cluster
        list to the ACTUAL test suites (`ls tests/test_*.sh`): functional, live
        preview, pollution, byte-exact restore, key discovery / two-axis, window flip
        + confirm-on-window, create-on-enter, pane immutability (whatever is present).
  - GOTCHA: every fix must be em-dash-free and tell-word-free.

Task 7: EM-DASH + TELL-WORD + PARAGRAPH pass (write-tech-docs gate)
  - REMOVE the 2 em dashes (L103, L169) and any you introduced. Replace each with a
        colon, parentheses, comma, or period. NEVER ` -- ` or a bare hyphen.
  - GREP the tell-word list (seamless, powerful, robust, comprehensive, leverage,
        utilize, unlock, streamline, elevate, delve, moreover, furthermore, truly,
        incredibly, ...) and replace/cut any hit. The README is mostly clean; new
        prose must avoid them.
  - KEEP every prose paragraph under ~4 sentences / 100 words; split long ones into
        bullets.
  - VERIFY: `grep -cP '\x{2014}' README.md` == 0; tell-word grep == 0. If lint.sh is
        present, run it and require exit 0.

Task 8: VALIDATE (see Validation Loop) — grep gates + content checks + regression.
```

### Implementation Patterns & Key Details

```markdown
<!-- Pattern: a write-tech-docs subsection is short prose + bullets, every literal in
     a code span. Example shape for the Two-axis navigation bullets: -->

* **Session axis** (move between candidates). Defaults to your `switch-client -n` and
  `-p` bindings plus the arrow keys (`Down` next, `Up` prev). Override with
  `@livepicker-session-next-keys` / `@livepicker-session-prev-keys`.
* **Window axis** (flip the previewed session's windows). Defaults to your
  `next-window` / `previous-window` bindings (including `swap-window ... ;
  select-window` compounds). Override with `@livepicker-window-next-keys` /
  `@livepicker-window-prev-keys`.

<!-- Pattern: the Window preview note as two short paragraphs (deliverable b). State
     the fact, then the guarantee; do not narrate the link-window mechanism. -->

Confirm lands on the exact window you were previewing. It resolves the target
session from the ranked list and the target window from the window cursor, commits
that window with one `select-window`, then `switch-client`s. You arrive on the
session and the tab you were looking at.

Flipping never changes a candidate's own state. Window-nav flips link the chosen
window into the driver and select it there; they never touch the candidate
session's own active window, so every peeked session is exactly as you found it
when you move on or cancel. Confirm is the one deliberate change (the single
`select-window` that commits your choice); everything else is read-only.

<!-- Anti-pattern: do NOT write "the picker repurposes your window-nav keys to move
     between sessions". That was the DROPPED design. Window-nav keys flip windows;
     session-nav keys move sessions. Two axes. -->
```

### Integration Points

```yaml
README.md (the only integration surface):
  - ## Overview: fix the single-axis "usual window-navigation keys" line.
  - ## Goals: replace "Filter + repurposed navigation"; add confirm-on-window +
        leave-no-trace goals.
  - ## User stories: split the Navigate bullet into session-nav + window-nav; fix
        the Confirm bullet.
  - ## Configuration: ADD ### Two-axis navigation (after ### Status line); VERIFY
        the four two-axis table rows (no retired options).
  - ## How it works: ADD ### Window preview (confirm-on-window + leave-no-trace).
  - ### Known limitations: VERIFY the §23 reconciliation (clip pin / snapshot /
        reflow).
  - ## Validation: replace "Key repurpose"; refresh the cluster list to the actual
        tests/test_*.sh.
  - Whole file: remove em dashes + tell-words.

NO other integration:
  - Do NOT edit CHANGELOG.md (P4.M1.T1.S2 owns the entry).
  - Do NOT edit PRD.md, any script, any test, plugin.tmux, or any tasks.json.
```

## Validation Loop

### Level 1: Style gate (write-tech-docs rules; lint.sh-free)

```bash
cd /home/dustin/.config/tmux/plugins/tmux-livepicker
# Em dashes: MUST be 0 (the README has 2 today at ~L103 and ~L169).
test "$(grep -cP '\x{2014}' README.md)" -eq 0 && echo "no em dashes OK" || grep -nP '\x{2014}' README.md
# Tell-words: MUST be 0.
grep -niEw 'powerful|robust|elegant|seamless|comprehensive|leverage|utilize|unlock|streamline|elevate|delve|moreover|furthermore|truly|incredibly|cutting-edge|revolutionary' README.md || echo "no tell-words OK"
# If the skill IS present at impl time, also run the linter (file-wide):
# bash /home/dustin/.pi/agent/skills/write-tech-docs/scripts/lint.sh README.md   # require exit 0
```

### Level 2: Stale-reference + content checks

```bash
cd /home/dustin/.config/tmux/plugins/tmux-livepicker
# Stale single-axis refs GONE:
grep -ni 'repurposed' README.md                       # MUST be empty
grep -ni 'usual window-navigation keys' README.md     # MUST be empty
grep -ni 'selection moves to a different session' README.md  # MUST be empty (window keys no longer move sessions)
# Retired options GONE:
grep -nE '@livepicker-(next-key|prev-key|nav-next-keys|nav-prev-keys)' README.md  # MUST be empty
# New subsections PRESENT (each exactly once):
grep -c '^### Two-axis navigation' README.md          # == 1
grep -c '^### Window preview' README.md               # == 1
# Four two-axis options present in the table:
grep -cE '@livepicker-(session|window)-(next|prev)-keys' README.md  # >= 4
# Confirm-on-window + leave-no-trace phrasing in the Window preview note:
grep -ni 'exact window\|window being previewed' README.md
grep -ni 'leave-no-trace\|never changes\|own active window' README.md
# §23 reconciliation in Known limitations:
grep -niE 'pinned|snapshot|strict' README.md | grep -i limit  # or confirm by reading the section
```

### Level 3: Regression (doc-only change must not break the suite)

```bash
cd /home/dustin/.config/tmux/plugins/tmux-livepicker
bash tests/run.sh
# Expected: exit 0. README is not sourced by any test, so this is a sanity check
# that nothing else was touched. Confirm the change is doc-only:
git status --short scripts/ tests/ plugin.tmux PRD.md CHANGELOG.md   # MUST be empty
```

### Level 4: Readability sanity (manual)

```bash
cd /home/dustin/.config/tmux/plugins/tmux-livepicker
# Read the new subsections in context. The narrative should flow:
#   Configuration table -> ### Two-axis navigation (the key model overview)
#   -> ### Status line (line 1 layout) -> Usage (how-to) -> ### Window preview
#   (confirm-on-window + leave-no-trace) -> ### Known limitations (clip/snapshot).
# Confirm no section contradicts another (e.g. Goals must not say "repurposed"
# while Two-axis navigation says "two axes discovered").
```

## Final Validation Checklist

### Technical Validation
- [ ] Level 1: `grep -cP '\x{2014}' README.md` == 0; tell-word grep == 0 (lint.sh exit 0 if present).
- [ ] Level 2: no `repurposed` / `usual window-navigation keys` / `selection moves to a different session`; no retired `@livepicker-next-key`/`-prev-key`/`-nav-*` options; `### Two-axis navigation` and `### Window preview` each present once; four two-axis options in the table; confirm-on-window + leave-no-trace phrasing present; §23 reconciliation present.
- [ ] Level 3: `bash tests/run.sh` exits 0; `git status --short` shows only README.md changed.
- [ ] Level 4: the narrative flows and no section contradicts another.

### Feature Validation
- [ ] (a) Two-axis navigation describes the session axis (switch-client -n/-p + arrows) and window axis (next-window/previous-window family), discovery from your config, the four override options, and the non-alphanumeric constraint.
- [ ] (b) Window preview states confirm lands on the exact previewed window AND that flipping never changes the candidate's own active window (leave-no-trace).
- [ ] (c) Known limitations reconcile the detached-candidate resize with §23 (clip pins detached candidates; snapshot for strict immutability across client-bearing sessions; reflow legacy).
- [ ] (d) Configuration table has the four two-axis options with (discovered) defaults + the non-alphanumeric constraint; no retired options.
- [ ] (e) Stale single-axis references fixed in Overview, Goals, User stories, and Validation; no em dashes; no tell-words.

### Code Quality Validation
- [ ] New and touched prose follows write-tech-docs style (active voice, imperative for steps, one idea per sentence, consistent terminology).
- [ ] All option/key/format literals are in `code` spans.
- [ ] No prose paragraph over ~4 sentences / 100 words.
- [ ] No meaning changed beyond the intended corrections; already-correct sections left intact.

### Documentation & Deployment
- [ ] No edits to CHANGELOG.md (P4.M1.T1.S2 owns the entry), PRD.md, scripts/, tests/, plugin.tmux, or any tasks.json.
- [ ] The README cross-references its own sections (Two-axis navigation, Window preview, Status line, Known limitations) so a reader can navigate the feature set.

---

## Anti-Patterns to Avoid

- ❌ Don't edit CHANGELOG.md, PRD.md, any script, any test, plugin.tmux, or any tasks.json. This task edits README.md ONLY.
- ❌ Don't leave the stale single-axis wording. The Overview/Goals/User-stories/Validation lines describe the DROPPED "repurposed window-nav into session-nav" design and must be corrected; they actively contradict the shipped two-axis feature. Specifically, window keys do NOT "move the selection to a different session" anymore.
- ❌ Don't reintroduce retired options. `@livepicker-next-key`/`-prev-key`/`-nav-next-keys`/`-nav-prev-keys` are GONE; the four `@livepicker-{session,window}-{next,prev}-keys` options replaced them.
- ❌ Don't duplicate the four table rows or copy the full discovery algorithm into both the subsection and the Usage steps. One overview subsection + concise how-to steps that point at it.
- ❌ Don't leave em dashes (the README has 2 at ~L103 and ~L169; remove them and any you add). Don't substitute ` -- ` or a bare hyphen.
- ❌ Don't claim clip fixes client-bearing candidates. The candidate pin is CONDITIONAL on the candidate being detached; for strict immutability across client-bearing sessions, snapshot is the escape hatch (pane_immutability_verification.md Decision box).
- ❌ Don't narrate the codebase or the binding order from PRD §8 step-by-step. The README documents what each axis does and how to override it, not the implementation runbook.
- ❌ Don't write marketing tell-words or formulaic transitions. State facts.
- ❌ Don't rewrite already-correct sections wholesale (Known limitations, Status line, Session management, the four table rows). Fix only what is stale or out of style.
- ❌ Don't assume the byte count in the item brief (it says 18956; the file is ~20228 and has grown). Read the ACTUAL README fully before editing.
- ❌ Don't coordinate the README with P3.M3.T1.S1. It is a parallel TEST file and does not touch README.md. Just reflect the actual tests/ contents in the Validation cluster list.

---

## Confidence Score: 9/10

This is a documentation task with a single, well-bounded file. Every deliverable's
content is sourced from quoted PRD sections (§8/§6/§4/§2/§3/§23) and the verified
gap-analysis + pane-immutability gate. The stale references are pinpointed with
exact line numbers and fixes, and two of them (the "repurposed navigation" goal and
the "window keys move the session selection" story) are flat-out wrong today, so
the correction is unambiguous. The four two-axis table rows and the §23 Known-
limitations reconciliation already appear present, so those deliverables are
verify-and-tighten rather than write-from-scratch. The only residual risks: (1) the
write-tech-docs skill/lint is not on disk in this environment, so the style gate is
grep-based rather than the linter (mitigated by encoding the rules and the exact
grep checks); (2) exact placement of the two new subsections is a judgment call
after reading the README (mitigated by giving two placement options each with a
recommendation). The implementer's job is to translate the quoted content blocks
into two subsections, correct six stale lines, remove two em dashes, and pass the
grep gates, not to discover what the features do.
