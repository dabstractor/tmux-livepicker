# PRP — P1.M3.T1.S2: Verify and update README.md feature/behavior sections

---

## Goal

**Feature Goal**: Sweep `README.md` so every feature/behavior section is
consistent with the six rev 002 QA bug fixes (Issues 1–6), making **minimal
edits — only where a section is now stale or silent about a changed behavior**.
The audit finds the README already reflects Issues 1, 2, 4, 5, and 6 correctly;
**only Issue 3's user-facing name-sanitization behavior is undocumented**, so the
single required edit is one concise sentence in the **Create** user story. All
other sections are verified clean and must NOT be edited (no `-a` reference
exists; no claim that `#S`/`#{session_name}` is unsupported; the Known
limitations section is properly placed).

**Deliverable**: One in-place edit to `README.md` — append one sentence to the
**Create** user-story bullet (L49–50) documenting that characters tmux disallows
in session names (such as `.`) are sanitized (`my.proj` → `my_proj`) and the user
still lands on the created session. No other file is touched; no other README
section is changed.

**Success Definition**:
- `grep -n -- '-a\b' README.md` returns nothing (no `link-window -a` reference —
  verified clean before AND after).
- The Create user story mentions name sanitization and landing on the created
  session.
- `grep -c '^### Known limitations' README.md` == 1, located under
  `## How it works`.
- `git diff README.md` is a **pure insertion of one sentence** (no deletions, no
  rewrites of existing prose).
- No edits to `scripts/`, `tests/`, `CHANGELOG.md` (owned by parallel S1),
  `PRD.md`, `tasks.json`.

## User Persona (if applicable)

**Target User**: End users reading the README to learn what the picker does
(especially the create-on-Enter behavior), and maintainers auditing whether the
docs match the shipped code after the bugfix round.

**Use Case**: A user types a query containing a dot (`my.proj`) expecting to
create a session; the README should set the correct expectation that the name is
sanitized and they still land on it (the exact behavior the Issue 3 fix
restored).

**User Journey**: User reads "Create" in the User stories / Usage, types
`my.proj`, presses Enter, and lands on `my_proj` — matching what the README now
says. Before this doc fix the README was silent on sanitization, so the user
could be surprised by the renamed session.

**Pain Points Addressed**: The README's create description was technically not
wrong (you do land on a created session) but omitted the sanitization that
Issue 3's fix made robust. The bugfix (commit `6aea983`) changed user-visible
behavior (dotted names no longer orphan/strand); the doc must reflect it.

## Why

- **Changeset-level documentation sync (Mode B).** This subtask IS the README half
  of the rev 002 doc sweep (the CHANGELOG half is the parallel P1.M3.T1.S1).
  Its job is to catch any overview/feature section that summarizes behavior
  changed by the bugfix.
- **The README is already 5/6 consistent.** A careful audit (see research/
  readme_consistency_audit.md) confirms Issues 1, 2, 4, 5, 6 are already reflected
  correctly: no `-a` reference exists (Issue 1); the broad "matches any theme"
  claim is now TRUE because the Issue 5 fix brought the code into line with the
  README (not the reverse); the Known limitations section (Issue 6) is properly
  placed and formatted. Editing those would be churn for no gain.
- **Only Issue 3's user-facing behavior is undocumented.** The create path now
  sanitizes names and lands on the sanitized result (`new-session -P -F
  '#{session_name}'`); the README's Create story uses a clean `newproj` example
  and never mentions sanitization. One sentence closes the gap.
- **Coordination with parallel S1.** S1 (P1.M3.T1.S1) edits `CHANGELOG.md` only;
  this task edits `README.md` only. Zero file overlap; no merge risk.

## What

A single README.md edit + four "verify, do not edit" checks. The complete audit
is in research/readme_consistency_audit.md; the verdicts:

1. **(a) `link-window -a` — CLEAN, no edit.** `grep` finds no `-a` flag anywhere.
   "How it works" (L159) says bare `tmux link-window`. The fix removed `-a`
   (commit `16c53a0`; `scripts/preview.sh:230`). Already consistent.
2. **(b) Create + sanitization — THE ONE EDIT.** Add one sentence to the Create
   user-story bullet (L49–50) noting that disallowed characters (e.g. `.`) are
   sanitized and the user still lands on the created session. Verified behavior:
   `scripts/input-handler.sh:387-403` (`new-session -d -P -F '#{session_name}' -s
   "$query"`; lands on `$created`).
3. **(c) window-status tab + `#S`/`#{session_name}` — CLEAN, no edit.** The
   README never claims session specifiers are unsupported; it claims broad theme
   support + `plain` fallback (L106, L123), which the Issue 5 fix made accurate.
4. **(d) Known limitations — OK, verify only.** `### Known limitations` (L167) is
   under `## How it works`, `###`-level (consistent with `### Appearance`/
   `### Performance`), accurately describes Issue 6, offers the `snapshot`
   mitigation. No rewrite.
5. **(e) Features/Behavior overview — CLEAN, no edit.** Goals, Non-goals, User
   stories, Overview, How it works, Compatibility have no stale claims.

### Success Criteria

- [ ] `grep -n -- '-a\b' README.md` is empty (no `-a` reference).
- [ ] The Create user-story bullet (L49–50) states names are sanitized (e.g.
      `my.proj` → `my_proj`) and the user lands on the created session.
- [ ] `grep -c '^### Known limitations' README.md` == 1 and it sits under
      `## How it works`.
- [ ] `git diff README.md` is a pure one-sentence insertion (no `-` content lines).
- [ ] No edits to any file other than `README.md`.

## All Needed Context

### Context Completeness Check

_Passed._ A new contributor who knows nothing about this codebase can do this
with only this PRP + read access to `README.md` and the two cited code lines: the
full audit (with line numbers and verdicts), the exact edit anchor + replacement
text, the verified create behavior (quoted from `input-handler.sh`), and the grep
self-checks are all below. The task is one sentence plus four confirmations.

### Documentation & References

```yaml
# MUST READ — the ONLY file you edit
- file: README.md
  why: The file under audit. Read the Create user story (L48-51), the How-it-works
        section (L156-166), the Known limitations section (L167-177), and the
        window-status Appearance note (L121-127) before editing.
  pattern: prose style — concise, user-facing, backticked option/command names,
            em dashes, no marketing tone. Match the surrounding bullet's voice.
  gotcha: Make ONE edit (the Create sanitization sentence). Do NOT "improve" the
          other sections — the audit proves they are already consistent; editing
          them is unrequested churn that risks introducing inaccuracy.

# MUST READ — the verified behavior the (b) edit must reflect (do NOT edit this file)
- file: scripts/input-handler.sh
  why: L387-403 — the create-on-confirm path. `new-session -d -P -F
        '#{session_name}' -s "$query"` captures the ACTUAL (possibly sanitized)
        name tmux created and lands on it. On a sanitized-name collision,
        new-session fails (rc=1, empty stdout) -> cancel, no orphan.
  critical: the user-facing fact is "sanitized + you still land on it". Do NOT
            document internals (-P -F, orphan, collision) in the README — keep
            it user-facing and minimal.

# MUST READ — the audit (full verdicts + line anchors for all 5 checks)
- docfile: plan/002_facc52335e68/bugfix/001_c7c6203f3e28/P1M3T1S2/research/readme_consistency_audit.md
  why: The per-check verdicts (a-e), the exact line numbers, the verified
        create-sanitization behavior, and the commit evidence that all six fixes
        landed. Read BEFORE editing so you do not edit a clean section.
  critical: 4 of 5 checks are CLEAN (no edit). Only (b) needs the one sentence.

# Reference — Issue 1 fix proof (no -a), confirms README (a) is clean
- file: scripts/preview.sh
  why: L230 — `tmux link-window -s "$src_id" -t "$current_session:"` (NO -a).
        Confirms the README's bare "link-window" wording matches shipped code.

# Reference — the bugfix findings/PRD cross-refs (READ-ONLY)
- file: plan/002_facc52335e68/bugfix/001_c7c6203f3e28/architecture/system_context.md
  why: L12-21 file map (README.md touched only by Issue 6) + verified BEFORE/AFTER
        behavior for each issue. Confirms which issues touch README (only 6, and
        that section already landed via P1.M2.T3.S1).
- file: PRD.md   # READ-ONLY — cite §refs only; do NOT edit
  why: §6 Confirm (create-on-enter), §7 (preview), §13 (link-window), §17
        (window-status tabs). The README does not cite section numbers, so no
        §ref updates are needed here.

# MUST READ — the parallel sibling (NO overlap; coordination only)
- docfile: plan/002_facc52335e68/bugfix/001_c7c6203f3e28/P1M3T1S1/PRP.md
  why: S1 edits CHANGELOG.md ONLY. This task edits README.md ONLY. Confirm there
        is no file overlap (there is none) and do not duplicate S1's content.
```

### Current Codebase tree (relevant slice)

```bash
README.md               # EDIT THIS — one sentence in the Create user story (L49-50)
CHANGELOG.md            # (parallel S1 edits this; DO NOT touch)
scripts/preview.sh      # Issues 1,2,4 — already fixed; reference only (L230 no -a)
scripts/input-handler.sh# Issue 3    — already fixed; reference only (L387-403)
scripts/livepicker.sh   # Issue 5    — already fixed; reference only
scripts/renderer.sh     # Issue 5    — already fixed; reference only
tests/                  # 44 tests; already landed; reference only
PRD.md / tasks.json / prd_snapshot.md   # READ-ONLY / orchestrator-owned
```

### Desired Codebase tree with files to be added and responsibility of file

```bash
README.md   # EDITED IN PLACE (this task): +1 sentence to the Create user story
            #   documenting name sanitization (Issue 3). All other sections
            #   unchanged (verified consistent with Issues 1,2,4,5,6).
```

### Known Gotchas of our codebase & Library Quirks

```text
# CRITICAL: this is a VERIFICATION sweep with ONE edit. The audit (research/
# readme_consistency_audit.md) proves 4 of 5 checks are already CLEAN. Do NOT
# edit the How-it-works section, the window-status Appearance note, the Known
# limitations section, or the Goals/Overview — they are consistent with the
# shipped code. Only the Create user story needs the sanitization sentence.

# CRITICAL: there is NO `link-window -a` reference in README.md today (grep
# confirms). Do NOT add one, and do NOT add an "appended at the end" insertion-
# position note — the contract says to describe appending "only if a mention
# exists"; none does. Silence on insertion position is correct.

# GOTCHA: the README does NOT document the sentinel/window-status INTERNALS
# (the __lp_tab__ / stable-session-name swap). Issue 5's fix is internal; the
# user-facing "matches any theme, falls back to plain" wording (L106/L123) is
# already correct. Do NOT add sentinel mechanism details to the README.

# GOTCHA: keep the (b) edit USER-FACING and minimal. State the behavior
# (sanitized + land on it); do NOT mention -P -F, orphan sessions, collisions,
# or the pre-fix bug. One sentence, matching the bullet's voice.

# GOTCHA: match the file's prose conventions — backtick option/command names
# (`link-window`, `@livepicker-preview-mode`), em dash with spaces ( — ) for
# asides, no exclamation/marketing tone. The existing Create bullet uses
# backticked `newproj`; mirror that (`my.proj`, `my_proj`).

# GOTCHA: the edit must be a PURE INSERTION (append a sentence to the existing
# two-line bullet; do not rewrite the bullet). `git diff README.md` must show
# only `+` lines (the new sentence), no `-` lines. This keeps the change
# reviewable and avoids touching verified-consistent prose.

# COORDINATION: P1.M3.T1.S1 (parallel) edits CHANGELOG.md. Do not touch it.
# P1.M2.T3.S1 already added the Known limitations section (commit bec7369); do
# not re-add or move it.
```

## Implementation Blueprint

### Data models and structure

N/A — static documentation. No data model.

### Implementation Tasks (ordered by dependencies)

```yaml
Task 1: READ README.md + the audit + the two code references
  - READ README.md in full (220 lines).
  - READ research/readme_consistency_audit.md (the 5-check verdicts + line anchors).
  - CONFIRM scripts/input-handler.sh:387-403 (create path: -P -F '#{session_name}',
    lands on $created) — the behavior the (b) edit documents.
  - CONFIRM scripts/preview.sh:230 (link-window with NO -a) — confirms (a) clean.

Task 2: VERIFY the four CLEAN checks (no edits — run the grep gates only)
  - (a) `grep -n -- '-a\b' README.md` -> expect EMPTY (no link-window -a).
  - (c) `grep -n '#S\|session_name\|sentinel' README.md` -> expect NO claim that
        session specifiers are unsupported (only the broad "matches any theme" +
        fallback wording at L106/L123).
  - (d) `grep -c '^### Known limitations' README.md` -> expect 1; confirm it is
        under `## How it works` (heading before it) and `###`-level.
  - (e) skim Goals/Overview/How-it-works/Compatibility -> expect no stale claims.
  - If any of these SURPRISES you (e.g. a `-a` reference appears), STOP and add a
    targeted edit for that check too — but the audit says none will.

Task 3: EDIT README.md — add the sanitization sentence to the Create user story
  - FILE: ./README.md  (the ONLY edit in this task).
  - FIND (exact existing text, the Create bullet, L49-50):
      - **Create.** I type `newproj` (no match) and press `Enter`; a new `newproj`
        session is created and I am switched to it.
  - REPLACE WITH (append one sentence; keep the existing two lines verbatim,
    then add the sanitization note as continuation lines at the same indent):
      - **Create.** I type `newproj` (no match) and press `Enter`; a new `newproj`
        session is created and I am switched to it. Characters tmux disallows in
        session names (such as `.`) are sanitized — `my.proj` becomes `my_proj` —
        and you still land on the created session.
  - PRESERVE: the bullet's leading `- **Create.**`, the backticked `newproj`,
    and the two-space continuation indent. Do NOT edit the Confirm or Cancel
    bullets around it. Do NOT edit the Overview/Goals/Usage/config-row create
    mentions (one mention is sufficient; the others are not inaccurate).
  - STYLE: em dash with spaces ( — ); backtick the example names; user-facing
    tone (no -P -F, no "orphan", no "collision").

Task 4: SELF-CHECK (no edits) — run the grep gates in Validation Loop Level 1.
  - Confirm: no -a reference; Create mentions sanitization; exactly one Known
    limitations section under How it works; git diff is a pure insertion.
```

### Implementation Patterns & Key Details

```text
# PATTERN (the existing Create bullet — match its voice):
#   - **Create.** I type `newproj` (no match) and press `Enter`; a new `newproj`
#     session is created and I am switched to it.
# The new sentence continues the same bullet at the same 2-space indent, in the
# same user-facing first/second-person voice.

# CRITICAL (the one sentence — verbatim, verified accurate against
# scripts/input-handler.sh:387-403):
#   Characters tmux disallows in session names (such as `.`) are sanitized —
#   `my.proj` becomes `my_proj` — and you still land on the created session.
# Em dash with spaces; backticked example names; no internal mechanism detail.

# CRITICAL: do NOT add a second mention elsewhere. The Overview (L12), Goals
# (L25), config row (L94), and Usage step 4 (L143) all say "creates a session
# from your query and switches to it" — accurate and sufficient. One sanitization
# note in the Create story is enough (contract: "minimal edits").
```

### Integration Points

```yaml
FILES:
  - edit:   README.md   (ONLY this file; one-sentence pure insertion)

NO CHANGES TO:
  - CHANGELOG.md        # parallel P1.M3.T1.S1 owns this
  - scripts/*.sh        # all fixes already landed (reference only)
  - tests/*.sh          # all tests already landed (reference only)
  - PRD.md / tasks.json / prd_snapshot.md   # READ-ONLY / orchestrator-owned
```

## Validation Loop

### Level 1: Structure & content self-checks (run immediately after the edit)

```bash
cd /home/dustin/.config/tmux/plugins/tmux-livepicker   # repo root

# (a) NO link-window -a reference (must be empty before AND after).
grep -n -- '-a\b' README.md && echo "FAIL: -a reference present" || echo "OK: no -a reference"

# (b) The Create user story now mentions sanitization + landing on the session.
grep -q -i 'sanitiz' README.md && echo "OK: sanitization mentioned" || echo "FAIL: sanitization missing"
grep -q 'my.proj` becomes `my_proj' README.md && echo "OK: example present" || echo "FAIL: example missing"

# (d) Exactly one Known limitations section, under How it works.
test "$(grep -c '^### Known limitations' README.md)" -eq 1 && echo "OK: 1 Known limitations" || echo "FAIL"
awk '/^## How it works/{h=1} /^### Known limitations/{if(h) print "OK: under How it works"; exit} /^## /{if($0 !~ /How it works/) h=0}' README.md

# (e) No accidental edits to other sections: the diff must be a PURE insertion
# (only + lines, no - content lines).
git diff README.md | grep '^-' | grep -v '^---' | grep -q . \
  && echo "FAIL: edit changed/deleted existing lines (must be insert-only)" \
  || echo "OK: pure insertion"

# Coordination: CHANGELOG.md untouched by THIS task (parallel S1 owns it).
git diff --name-only | grep -q '^CHANGELOG.md$' \
  && echo "NOTE: CHANGELOG.md modified (verify that is parallel S1, not this task)" \
  || echo "OK: CHANGELOG.md not touched by this task"
```

### Level 2: Content sanity (manual read)

- Read the edited Create bullet: the sanitization sentence is user-facing, uses
  the `my.proj` → `my_proj` example, and states you land on the created session.
- Confirm the Confirm/Cancel bullets around it are byte-identical.
- Confirm the How-it-works section still says bare `tmux link-window` (no `-a`).

### Level 3: N/A (no code, no service, no runtime)

This is a static-document edit. The plugin test suite (`tests/run.sh`) is
unaffected — the README is not executed. No integration to probe.

### Level 4: N/A (no creative/domain validation)

## Final Validation Checklist

### Technical Validation

- [ ] `grep -n -- '-a\b' README.md` is empty (no `link-window -a` reference).
- [ ] `grep -c '^### Known limitations' README.md` == 1, under `## How it works`.
- [ ] `git diff README.md` is a pure insertion (no `-` content lines).
- [ ] No file other than `README.md` is touched by this task.

### Feature Validation

- [ ] (a) No `-a` reference anywhere in README (verified, no edit).
- [ ] (b) Create user story states names are sanitized (`my.proj` → `my_proj`)
      and the user lands on the created session.
- [ ] (c) window-status Appearance/config makes no "session specifier unsupported"
      claim (verified, no edit).
- [ ] (d) Known limitations section is `###`-level, under How it works, accurate
      (verified, no edit).
- [ ] (e) Goals/Overview/How-it-works/Compatibility have no stale claims
      (verified, no edit).

### Code Quality Validation

- [ ] The edit matches the file's prose conventions (backticked names, em dash,
      user-facing tone, no internal mechanism detail).
- [ ] Only ONE sanitization mention added (no duplicate edits to Overview/Goals/
      Usage/config-row).
- [ ] The Confirm/Cancel bullets and all other sections are byte-identical.

### Documentation & Deployment

- [ ] The Create behavior documented matches the shipped code
      (`scripts/input-handler.sh:387-403`).
- [ ] No CHANGELOG.md edit (parallel S1 owns it); no PRD.md/tasks.json edit.
- [ ] No new options, env vars, or compatibility claims introduced.

---

## Anti-Patterns to Avoid

- ❌ Don't edit any file other than `README.md` (CHANGELOG is parallel S1's;
  scripts/tests/PRD are read-only or already-landed).
- ❌ Don't edit the clean sections (How-it-works, window-status Appearance, Known
  limitations, Goals, Overview) — the audit proves they already match the shipped
  code. Editing them is unrequested churn that risks introducing inaccuracy.
- ❌ Don't add a `link-window -a` reference or an "appended at the end" insertion-
  position note — none exists today and the contract says to add the latter only
  if a mention exists. Silence on insertion position is correct.
- ❌ Don't document Issue 5's sentinel internals (`__lp_tab__`, stable session
  name, second renderer swap) in the README — they are internal; the user-facing
  "matches any theme, falls back to plain" wording is already accurate.
- ❌ Don't document the create path internals (`-P -F`, orphan sessions,
  collisions, the pre-fix bug) — keep the (b) edit user-facing and minimal.
- ❌ Don't add a second sanitization mention to Overview/Goals/Usage/config-row —
  one mention in the Create story is sufficient (contract: "minimal edits").
- ❌ Don't rewrite the Create bullet — append a sentence (pure insertion). The
  diff must show only `+` lines.
- ❌ Don't move or re-add the Known limitations section — P1.M2.T3.S1 placed it
  correctly under How it works (commit `bec7369`).
- ❌ Don't run or modify `tests/run.sh` — the README is not executed; the suite
  is unaffected.

---

## Confidence Score

**9 / 10** — one-pass success likelihood. The task is a single one-sentence
insertion into one static file, anchored on exact existing text (the Create
bullet, L49–50, quoted verbatim). The full audit (research/
readme_consistency_audit.md) verified — via `git log`, `grep`, and source
inspection of `scripts/preview.sh:230` (no `-a`) and `scripts/input-handler.sh:
387-403` (the sanitized-name capture + landing) — that 4 of the 5 contract checks
are already CLEAN and only (b) needs the edit. The replacement sentence is given
verbatim and verified accurate against the shipped create behavior. The grep
self-checks (no `-a`; sanitization present; one Known limitations; pure-insertion
diff; CHANGELOG untouched) catch any structural slip on the spot. The only
residual risk is an implementer "improving" a clean section — explicitly walled
off by the anti-patterns and the "verify, do not edit" Task 2.
