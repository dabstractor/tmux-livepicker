# PRP — Bugfix P1.M2.T3.S1: Remove the non-existent `./validate.sh` reference from the README Validation section (Issue 5)

> **Bug context**: This is Issue 5 (Minor, documentation) from the adversarial QA
> pass
> (`plan/001_fd5d622d3939/bugfix/001_15442f34c366/architecture/bugfix_findings.md`
> §ISSUE 5). The README `## Validation` section advertises
> "a `VALIDATE_SKIP_SLOW=1` budget is available in `./validate.sh` for faster
> static + E2E checks." — but **no `validate.sh` exists anywhere in the repo**,
> and `tests/run.sh` (the real runner) has **no `VALIDATE_SKIP_SLOW` handling**.
> Users who follow the README get `No such file or directory.` The correct entry
> point `bash tests/run.sh` is already documented one line above the broken
> clause and must be left untouched. This is a **documentation-only** change: it
> removes the broken clause and fixes the resulting punctuation so the paragraph
> is grammatical. No code, no test, no new file.

---

## Goal

**Feature Goal**: The README `## Validation` section no longer references the
non-existent `./validate.sh` or the `VALIDATE_SKIP_SLOW` "budget". After the fix
the Validation paragraph reads as a single, grammatically-correct paragraph that
documents only the real entry point (`bash tests/run.sh`).

**Deliverable**: A single surgical edit to `README.md` (the Validation-section
paragraph, currently around lines 180–183) that:
1. Deletes the trailing clause `a \`VALIDATE_SKIP_SLOW=1\` budget is available in
   \`./validate.sh\` for faster static + E2E checks.`
2. Converts the now-dangling `; ` (semicolon after `config)`) into `. ` (period)
   so `The suites cover the PRD §15 clusters:` begins a clean new sentence.
3. Leaves the `bash tests/run.sh` command (README line 174), the cluster bullet
   list, and every other part of the file byte-for-byte unchanged.

**Success Definition**:
- `grep -n 'validate\.sh\|VALIDATE_SKIP_SLOW' README.md` returns **nothing**.
- `grep -n 'bash tests/run.sh' README.md` still returns the (unchanged) command
  line in the Validation section.
- The Validation paragraph, rendered, reads: *"…Expect the full suite to take
  roughly 2–3 minutes (each test starts a fresh isolated tmux server and sources
  the user config). The suites cover the PRD §15 clusters:"* — i.e. no broken
  `; The suites` punctuation, no dangling reference.
- No other file in the repo is modified; no `validate.sh` wrapper is created.

## User Persona (if applicable)

**Target User**: Any developer / contributor / user who reads the README to run
the test suite.

**Use Case**: The user opens README.md, finds the Validation section, and copies
the documented command to validate the plugin. The documented command must (a)
exist and (b) be the real runner.

**Pain Points Addressed**: Today a user who reads past `bash tests/run.sh` to the
"…a `VALIDATE_SKIP_SLOW=1` budget is available in `./validate.sh`…" sentence may
try `./validate.sh` and get `No such file or directory.`, or believe a fast-mode
budget exists when it does not. The fix removes the false promise so the only
documented path is the correct one.

## Why

- **Documentation accuracy is part of the bugfix SOW.** Issue 5 is explicitly
  scoped as "Minor (documentation)"; the work-item contract selects the
  doc-removal option (not the "ship a wrapper" feature option).
- **The reference is verifiably false.** `find . -name 'validate.sh'` is empty;
  `grep VALIDATE_SKIP_SLOW tests/run.sh` is empty. The README promises a file and
  a flag that do not exist.
- **The real entry point is already documented** one line above
  (`bash tests/run.sh`, README line 174) and is correct — so removing the broken
  clause loses zero accurate information.
- **Cheap, surgical, zero-risk.** One prose edit to one file; no logic, no
  config, no state, no scripts, no tests. Confined to the Validation paragraph.
- **Disjoint from parallel work.** P1.M2.T1.S1 (renderer.sh + test_functional.sh)
  and P1.M2.T2.S1 (preview.sh + test_preview.sh) touch entirely different files.
  The cross-cutting CHANGELOG + README-overview sync is a later task
  (P1.M3.T1.S1) and is out of scope here.

## What

A single edit to `README.md`, inside the `## Validation` section, that removes
the broken trailing clause and repairs the punctuation. Concretely, the current
paragraph (the wrapped prose immediately after the `bash tests/run.sh` code
fence) currently contains:

> …Expect the full suite to take roughly **2–3 minutes** (each test starts a
> fresh isolated tmux server and sources the user config); a `VALIDATE_SKIP_SLOW=1`
> budget is available in `./validate.sh` for faster static + E2E checks. The suites cover the PRD §15 clusters:

After the fix it reads:

> …Expect the full suite to take roughly **2–3 minutes** (each test starts a
> fresh isolated tmux server and sources the user config). The suites cover the
> PRD §15 clusters:

(Only the clause + the `;`→`.` change differ. Everything else — the en-dash
`2–3`, the parenthetical, the `PRD §15 clusters:` lead-in, the cluster bullet
list that follows — is unchanged.)

### Success Criteria

- [ ] `grep -c 'validate\.sh\|VALIDATE_SKIP_SLOW' README.md` returns `0`.
- [ ] `grep -n 'bash tests/run.sh' README.md` still prints the unchanged command
      line in the Validation section.
- [ ] The Validation paragraph ends `…sources the user config).` (period, NOT
      `;`) and continues `The suites cover the PRD §15 clusters:`.
- [ ] No `validate.sh` file is created; no other file is modified.

## All Needed Context

### Context Completeness Check

_Pass_: An implementer who has never seen this repo can do this from (a) the
exact unique ASCII-only `oldText`→`newText` block below, (b) the grep self-checks
that prove correctness, and (c) the explicit "do not touch" list. No tmux / shell
/ plugin knowledge is required — it is a prose edit. All anchors verified against
the live file (research/readme_validate_findings.md, FINDINGS 1–9).

### Documentation & References

```yaml
# MUST READ — the bug report (root cause + the fix directive)
- docfile: plan/001_fd5d622d3939/bugfix/001_15442f34c366/architecture/bugfix_findings.md
  why: §ISSUE 5 states the broken sentence, confirms no validate.sh exists and
       tests/run.sh has no VALIDATE_SKIP_SLOW handling, and directs the removal.
  critical: The bugfix_findings "Fix" note says the paragraph should "end at
            '...sources the user config);'" (keep semicolon). The WORK-ITEM
            CONTRACT is authoritative and overrides that: the result must be
            '...sources the user config). The suites...' (PERIOD). Keeping the
            semicolon would leave the grammatically-broken "; The suites".

# MUST READ — the empirical ground-truth for THIS fix (9 verified findings)
- docfile: plan/001_fd5d622d3939/bugfix/001_15442f34c366/P1M2T3S1/research/readme_validate_findings.md
  why: FINDING 1 (no validate.sh anywhere); FINDING 2 (exact broken text +
       line numbers); FINDING 3 (contract requires ; -> . , superseding the
       findings-note's semicolon variant); FINDING 4 (the unique ASCII-only
       oldText anchor that avoids the en-dash / § bytes); FINDING 5 (run.sh has
       no VALIDATE_SKIP_SLOW); FINDING 6 (neither token elsewhere -> removal is
       the complete fix); FINDING 7 (no regression test -> doc-only, grep is the
       gate); FINDING 8 (disjoint from parallel tasks); FINDING 9 (do-NOT list).

# MUST READ — the file being edited (the Validation section)
- file: README.md
  why: The single file under edit. The ## Validation section starts ~line 172;
       the broken clause is in the wrapped paragraph ~lines 180-183.
  pattern: README paragraphs are hand-wrapped at ~76-81 columns; a single
           trailing newline inside a paragraph is a soft wrap (renders as a
           space). Collapsing the two wrapped lines into one ~94-char line after
           the edit is fine (renders identically); an optional re-wrap to ~78
           cols is cosmetic only (see Implementation Patterns).
  gotcha: Do NOT match on the `2–3` (en-dash, U+2013) or `§` (U+00A7) bytes.
          Anchor the edit on the ASCII-only `sources the user config)` region
          (research FINDING 4). Do NOT touch the `bash tests/run.sh` code fence
          (README line 174) or the cluster bullet list below the paragraph.
```

### Current Codebase tree

```bash
tmux-livepicker/
  README.md           # MODIFY: Validation-section paragraph — remove validate.sh clause + fix ; -> .
  CHANGELOG.md        # UNCHANGED (the "Fix:" entry for Issue 5 is added later by P1.M3.T1.S1)
  tests/run.sh        # UNCHANGED (real runner; no VALIDATE_SKIP_SLOW — read only)
  scripts/            # UNCHANGED (parallel tasks edit renderer.sh/preview.sh — disjoint)
  plugin.tmux, PRD.md # UNCHANGED
```

### Desired Codebase tree with files to be added and responsibility of file

```bash
README.md   # Validation paragraph: no validate.sh / VALIDATE_SKIP_SLOW; grammatical single paragraph documenting `bash tests/run.sh`
# (no files added; documentation-only change)
```

### Known Gotchas of our codebase & Library Quirks

```bash
# CRITICAL (research FINDING 3): the WORK-ITEM CONTRACT requires the result
# '...sources the user config). The suites cover the PRD §15 clusters:' — a
# PERIOD after config), not a semicolon. bugfix_findings.md's "Fix" note
# ("end at '...sources the user config);'") is the superseded variant; keeping
# its semicolon would produce the broken "; The suites". Convert ; -> .

# CRITICAL (research FINDING 4): the edit's oldText must be ASCII-only and
# UNIQUE. Anchor on:
#   sources the user config); a `VALIDATE_SKIP_SLOW=1`
#   budget is available in `./validate.sh` for faster static + E2E checks. The suites
# Do NOT include the `2–3` (en-dash) or `§` bytes in oldText — they are easy to
# mistype and are unnecessary (the clause to remove is entirely ASCII).
# `VALIDATE_SKIP_SLOW` appears ONLY in this one place, so the anchor is unique.

# CRITICAL (contract): Do NOT remove or change the `bash tests/run.sh` command
# (README line 174) — it is correct. Do NOT create a validate.sh wrapper
# (the PRD's alternate "ship a wrapper" option is a feature addition, out of
# scope for this doc-only pass).

# GOTCHA: after the surgical edit the two physical lines collapse into one
# ~94-char line ("...config). The suites cover the PRD §15 clusters:"). This is
# valid markdown (renders identically). Re-wrapping to ~78 cols is OPTIONAL and
# cosmetic — do it only if you also re-wrap consistently; never introduce a
# blank line inside the paragraph (a blank line would split it into two blocks).

# GOTCHA (research FINDING 6): neither `validate.sh` nor `VALIDATE_SKIP_SLOW`
# appears anywhere else in the repo, so removing the README sentence is the
# COMPLETE fix. Do NOT hunt for / "fix" other references; there are none.

# GOTCHA (research FINDING 7): no regression test is added — this is a one-time
# prose error, the contract is explicitly doc-only (MOCKING: N/A), and adding a
# grep-test would risk colliding with the parallel test-file edits. The
# validation gate IS the grep self-check (see Validation Loop Level 1).

# GOTCHA (research FINDING 8): CHANGELOG sync is deferred to P1.M3.T1.S1. Do
# NOT add the "Fix: remove validate.sh reference" CHANGELOG entry here.
```

## Implementation Blueprint

### Data models and structure

None. No data, no schema, no state. This is a prose edit to one Markdown
paragraph.

### Implementation Tasks (ordered by dependencies)

```yaml
Task 1: MODIFY README.md — remove the broken validate.sh clause + fix punctuation
  - LOCATE the ## Validation section's wrapped paragraph (the prose immediately
    AFTER the `bash tests/run.sh` fenced block, ~README lines 180-183). The
    clause to remove is the trailing sub-clause that dangles after the main
    sentence's closing paren:
        ...sources the user config); a `VALIDATE_SKIP_SLOW=1`
        budget is available in `./validate.sh` for faster static + E2E checks. The suites
  - REPLACE the unique ASCII-only region (exact oldText/newText in
    "Implementation Patterns" below). The replacement:
      * deletes the `VALIDATE_SKIP_SLOW` + `./validate.sh` clause, AND
      * turns the dangling `config); ` into `config). ` (semicolon -> period)
        so "The suites cover the PRD §15 clusters:" begins a clean sentence.
  - PRESERVE: the `bash tests/run.sh` code fence (README line 174); the `2–3`
    en-dash; the parenthetical "(each test starts a fresh isolated tmux server
    and sources the user config)"; the "PRD §15 clusters:" lead-in; the entire
    cluster bullet list below; every other section of README.md.
  - DO NOT: create validate.sh; edit any other file; add a CHANGELOG entry.

Task 2: VALIDATE (grep self-check + optional no-breakage suite run)
  - RUN (Level 1): grep -c 'validate\.sh\|VALIDATE_SKIP_SLOW' README.md   # -> 0
  - RUN (Level 1): grep -n 'bash tests/run.sh' README.md                  # -> still present
  - RUN (Level 1): re-read the edited paragraph; confirm it ends
    "...sources the user config). The suites cover the PRD §15 clusters:"
    (period, not semicolon; no broken "; The suites").
  - OPTIONAL (Level 2): bash tests/run.sh  # confirm nothing broke (README is
    not read by tests; expected: 24/24 (+ any parallel-task tests) green, exit 0).
```

### Implementation Patterns & Key Details

**Task 1 — the surgical edit (paste verbatim into the edit tool).** This is the
**only** code change. Use the ASCII-only, unique anchor (research FINDING 4):

CURRENT (the exact text to match — spans the wrap between the two physical lines;
note the literal backticks around `VALIDATE_SKIP_SLOW=1` and `./validate.sh`):

```markdown
sources the user config); a `VALIDATE_SKIP_SLOW=1`
budget is available in `./validate.sh` for faster static + E2E checks. The suites
```

→ REPLACE WITH:

```markdown
sources the user config). The suites
```

What this does, line by line:
- `sources the user config); a \`VALIDATE_SKIP_SLOW=1\`` (end of physical line 1)
  + the newline + `budget is available in \`./validate.sh\` for faster static +
  E2E checks. The suites` (start of physical line 2) → all replaced by
  `sources the user config). The suites`.
- The remainder of physical line 2 — ` cover the PRD §15 clusters:` — is **not**
  part of `oldText`, so it is preserved verbatim and now follows directly.

**Resulting paragraph (rendered, single block):**

> Run from the repo root. The suite spins up a **private, isolated tmux socket
> per test** via a `tmux` PATH-wrapper shim, so your real running server is never
> touched. It prints `PASS` / `FAIL` per test plus a summary and exits `0` iff
> all passed. Expect the full suite to take roughly **2–3 minutes** (each test
> starts a fresh isolated tmux server and sources the user config). The suites
> cover the PRD §15 clusters:

**Optional cosmetic re-wrap.** After the edit, the two source lines collapse into
one ~94-char line. Markdown renders identically, so re-wrapping is optional. If
you choose to re-wrap for source consistency (~78 cols, matching the surrounding
paragraphs), produce exactly:

```markdown
passed. Expect the full suite to take roughly **2–3 minutes** (each test starts
a fresh isolated tmux server and sources the user config). The suites cover the
PRD §15 clusters:
```

(Do this ONLY by widening `oldText` to also include the `passed. Expect …each
test starts\n` prefix; never insert a blank line inside the paragraph — a blank
line would split it into two rendered blocks.)

**Verification after the edit (copy-paste):**

```bash
cd /home/dustin/.config/tmux/plugins/tmux-livepicker
# Must print 0 — the broken reference is gone:
grep -c 'validate\.sh\|VALIDATE_SKIP_SLOW' README.md
# Must still print the (unchanged) command line:
grep -n 'bash tests/run.sh' README.md
# Re-read the paragraph to eyeball grammar (period, not semicolon):
sed -n '/## Validation/,/## Maintenance/p' README.md
```

### Integration Points

```yaml
CODE:
  - file: README.md
    change: "Validation-section paragraph: delete the 'a VALIDATE_SKIP_SLOW=1
             budget is available in ./validate.sh for faster static + E2E
             checks.' clause and convert the trailing '; ' to '. '. No other
             change to README.md or any other file."
    invariant: "the only documented validation entry point is 'bash tests/run.sh';
               the paragraph is a single grammatical block; no validate.sh /
               VALIDATE_SKIP_SLOW reference remains anywhere in the repo"

TESTS: none added (doc-only; contract MOCKING: N/A).
DATABASE / CONFIG / ROUTES: none.
```

## Validation Loop

### Level 1: Content self-check (primary gate — doc-only)

```bash
cd /home/dustin/.config/tmux/plugins/tmux-livepicker
# 1) The broken reference is GONE (must print 0):
grep -c 'validate\.sh\|VALIDATE_SKIP_SLOW' README.md        # -> 0
grep -rn 'validate\.sh\|VALIDATE_SKIP_SLOW' . --exclude-dir=.git --exclude-dir=plan 2>/dev/null | grep -v '^\./\.pi-subagents/'
#   ^ whole-repo sweep should also be empty outside plan/ and .pi-subagents/ artifacts
# 2) The correct entry point is UNCHANGED (must still print a line in Validation):
grep -n 'bash tests/run.sh' README.md                       # -> 174: bash tests/run.sh
# 3) Paragraph grammar: ends "config)." (period), continues "The suites ..." (no "; The")
sed -n '/## Validation/,/## Maintenance/p' README.md | grep -n 'config)\.\|config);'
#   -> only "config)." must appear; "config);" must be absent.
# Expected: 0 references to validate.sh/VALIDATE_SKIP_SLOW; run.sh command intact;
#           period (not semicolon) after the parenthetical.
```

### Level 2: No-breakage suite run (optional — belt-and-braces)

```bash
cd /home/dustin/.config/tmux/plugins/tmux-livepicker
bash tests/run.sh
# Expected: full suite green (exit 0). README is NOT read by the tests, so this
# is purely a "nothing else regressed" sanity check. If P1.M2.T1.S1 / P1.M2.T2.S1
# landed in parallel, their tests also pass (disjoint files). Takes ~2–3 min.
```

### Level 3: Prove the fix addresses the user-facing bug (manual, 30 sec)

```bash
cd /home/dustin/.config/tmux/plugins/tmux-livepicker
# Before the fix, a user running the documented command got "No such file":
#   $ ./validate.sh         -> bash: ./validate.sh: No such file or directory
# After the fix the README documents ONLY 'bash tests/run.sh'. Confirm that file
# exists and is the documented path:
test -f tests/run.sh && echo "tests/run.sh exists (documented path is valid)"
grep -q 'bash tests/run.sh' README.md && echo "README documents the correct path"
# Confirm a user following the README will NOT find a validate.sh to run:
! test -f validate.sh && echo "no validate.sh to mislead users (correct)"
# Expected: all three echoes print; the README's only validation instruction is
# the real, existing runner.
```

### Level 4: Creative & Domain-Specific Validation

```bash
# Markdown render sanity (optional): render the Validation section and eyeball
# that the paragraph is a single block with no broken punctuation. If you have a
# markdown renderer handy:
#   - the "a VALIDATE_SKIP_SLOW=1 budget … ./validate.sh …" sentence is GONE;
#   - "The suites cover the PRD §15 clusters:" begins a new sentence after
#     "...sources the user config).";
#   - the cluster bullet list below is unchanged.
# No performance / security / load validation applies (prose edit).
```

## Final Validation Checklist

### Technical Validation

- [ ] `grep -c 'validate\.sh\|VALIDATE_SKIP_SLOW' README.md` returns `0`.
- [ ] `grep -n 'bash tests/run.sh' README.md` still prints the unchanged command.
- [ ] The Validation paragraph ends `…sources the user config).` (period, not `;`).
- [ ] (Optional) `bash tests/run.sh` exits 0 (no regression — README not read).

### Feature Validation

- [ ] No `validate.sh` reference remains in README.md (or anywhere in the repo).
- [ ] No `VALIDATE_SKIP_SLOW` reference remains in README.md (or anywhere).
- [ ] The paragraph renders as one grammatical block; no broken `; The suites`.
- [ ] The real entry point `bash tests/run.sh` is still documented and correct.
- [ ] User-facing bug is resolved: nothing in the README instructs a user to run
      a non-existent file.

### Code Quality Validation

- [ ] Change confined to the single Validation-section paragraph in README.md.
- [ ] No other file modified; no `validate.sh` created; no CHANGELOG entry added
      (that is P1.M3.T1.S1's job).
- [ ] No blank line introduced inside the paragraph (would split rendered block).
- [ ] The en-dash `2–3`, the `§15`, the parenthetical, and the cluster bullets
      are all byte-for-byte unchanged.

### Documentation & Deployment

- [ ] The README Validation section is now accurate: the only documented path is
      the real runner `bash tests/run.sh`, and it takes ~2–3 minutes.
- [ ] No false "fast-mode budget" promise remains.

---

## Anti-Patterns to Avoid

- ❌ Don't keep the semicolon (`config);`) — the work-item contract requires
  `config).` (period). `; The suites` is a punctuation error (research FINDING 3).
- ❌ Don't anchor the edit's `oldText` on the `2–3` (en-dash) or `§` bytes — use
  the ASCII-only `sources the user config)` region; it's unique and mistype-proof
  (research FINDING 4).
- ❌ Don't remove or alter the `bash tests/run.sh` command (README line 174) — it
  is correct and is the real entry point (contract; research FINDING 5).
- ❌ Don't create a `validate.sh` wrapper — the PRD's alternate option is a
  feature addition; this pass is doc-removal only (contract; research FINDING 9).
- ❌ Don't add a regression test — the contract is explicitly doc-only
  (`MOCKING: N/A`), a grep-test risks colliding with the parallel test-file edits,
  and the validation gate IS the grep self-check (research FINDING 7).
- ❌ Don't edit CHANGELOG.md, the README overview section, or any other file —
  the cross-cutting doc sync is P1.M3.T1.S1 (research FINDING 8).
- ❌ Don't insert a blank line inside the paragraph when (optionally) re-wrapping —
  a blank line splits it into two rendered Markdown blocks.
- ❌ Don't "hunt" for other validate.sh references to fix — there are none
  (research FINDING 6); the README sentence is the complete fix.
- ❌ Don't merge/change the cluster bullet list, the `2–3` timing, or the
  parenthetical — only the trailing clause + the one `;`→`.` change are in scope.

---

## Confidence Score

**10 / 10** for one-pass success. Rationale: this is a single, surgical prose
edit to one Markdown paragraph in one file. Every load-bearing fact is
**live-verified**: no `validate.sh` exists anywhere (`find` empty — FINDING 1);
`tests/run.sh` has no `VALIDATE_SKIP_SLOW` handling (`grep` empty — FINDING 5);
neither token appears anywhere else in the repo (FINDING 6); the exact broken
text and its byte offsets are captured (FINDING 2); the contract-mandated result
(`;` → `.`) is unambiguous and supersedes the findings-note's semicolon variant
(FINDING 3); the `oldText` anchor is unique and ASCII-only, sidestepping the
en-dash/§ bytes that would otherwise risk an edit-tool mismatch (FINDING 4). The
grep self-checks (Validation Level 1) deterministically prove correctness, and
the task is fully disjoint from both parallel tasks (renderer.sh / preview.sh —
FINDING 8) and from the later CHANGELOG sync (P1.M3.T1.S1). Residual risk: an
edit-tool `oldText` mismatch — mitigated by the verbatim old→new pair above and
the ASCII-only anchor. There is no logic, no test, and no integration surface to
get wrong.
